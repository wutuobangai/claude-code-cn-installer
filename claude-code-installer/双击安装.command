#!/bin/bash
# ============================================================
#  Claude Code 中文一键安装器 · Mac 版 （草稿 0.1.0 · 2026-09-23）
#  双击运行即可。装好后桌面会出现两个图标：
#    「打开 Claude Code」「CC Switch 切换 key」
#  不需要管理员密码，所有东西都装在你自己的用户目录里。
#
#  测试参数（普通用户用不到）：
#    --dry-run       只演练：打印将要做的每一步，不下载、不安装、不改任何文件
#    --pretend-fresh 假装电脑上什么都没装（配合 --dry-run 看完整流程）
#    --no-pause      结束时不等回车（自动化测试用）
# ============================================================
set -u

DRY=0; FRESH=0; NOPAUSE=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --pretend-fresh) FRESH=1 ;;
    --no-pause) NOPAUSE=1 ;;
  esac
done
[ -t 0 ] || NOPAUSE=1

HERE="$(cd "$(dirname "$0")" && pwd)"
CFG="$HERE/installer-files/config.json"
TOTAL=5
LOCAL_BIN="$HOME/.local/bin"
TMPD="$(mktemp -d -t lingji-cc-installer)"
trap 'rm -rf "$TMPD"' EXIT
PROBLEMS=""
export PATH="$LOCAL_BIN:$PATH"

# 真装时把日志存一份，出问题好查；演练模式不写任何文件
if [ "$DRY" = 0 ]; then
  LOG="$HOME/Library/Logs/ClaudeCode中文安装器.log"
  mkdir -p "$HOME/Library/Logs" && exec > >(tee -a "$LOG") 2>&1
fi

# ---------- 小工具 ----------
say()  { printf '%s\n' "$*"; }
ok()   { printf '   ✅ %s\n' "$*"; }
info() { printf '   · %s\n' "$*"; }
warn() { printf '   ⚠️  %s\n' "$*"; }
step() { # step 序号 标题
  local left=$((TOTAL - $1))
  say ""
  say "【第 $1 步 / 共 $TOTAL 步】$2   （这步做完还剩 $left 步）"
}
note_problem() { PROBLEMS="${PROBLEMS}\n   - $*"; }

# run：真装时执行命令；演练时只打印
run() {
  if [ "$DRY" = 1 ]; then printf '   [演练·不执行] %s\n' "$*"; return 0; fi
  "$@"
}
# run_sh：同上，但接收一整段 shell 语句（带管道时用）
run_sh() {
  if [ "$DRY" = 1 ]; then printf '   [演练·不执行] %s\n' "$1"; return 0; fi
  /bin/bash -c "$1"
}

# 读 config.json（用 macOS 自带的 JavaScript，不依赖 python）
cfg() {
  /usr/bin/osascript -l JavaScript - "$CFG" "$1" <<'JS' 2>/dev/null
ObjC.import('Foundation');
function run(argv){
  var s = $.NSString.stringWithContentsOfFileEncodingError(argv[0], 4, null);
  if (!s) return '';
  var o = JSON.parse(ObjC.unwrap(s));
  var v = argv[1].split('.').reduce(function(a,k){ return (a==null)?a:a[k]; }, o);
  return (v==null) ? '' : String(v);
}
JS
}

# 从 Node 镜像的 index.json 里挑最新的 LTS 版本
latest_node_lts() {
  local f="$TMPD/node-index.json"
  curl -fsSL -m 20 "$1/index.json" -o "$f" 2>/dev/null || return 1
  /usr/bin/osascript -l JavaScript - "$f" <<'JS' 2>/dev/null
ObjC.import('Foundation');
function run(argv){
  var s = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(argv[0], 4, null));
  var l = JSON.parse(s);
  for (var i=0;i<l.length;i++){ if (l[i].lts) return l[i].version; }
  return '';
}
JS
}

# 演练模式下只探测下载地址能不能通（HEAD 请求，不下载文件）
probe_url() {
  local code size
  code=$(curl -sIL -m 20 -o /dev/null -w '%{http_code}' "$1" 2>/dev/null)
  size=$(curl -sIL -m 20 "$1" 2>/dev/null | awk 'tolower($1)=="content-length:"{s=$2} END{gsub("\r","",s); print s}')
  if [ "$code" = "200" ]; then info "下载地址可用（HTTP 200，约 $((${size:-0}/1024/1024)) MB）：$1"; return 0
  else warn "下载地址不通（HTTP ${code:-超时}）：$1"; return 1; fi
}

download() { # download URL 目标文件
  if [ "$DRY" = 1 ]; then
    probe_url "$1" || return 1
    printf '   [演练·不执行] 下载到 %s\n' "$2"; return 0
  fi
  curl -fL --retry 2 --connect-timeout 15 -m 900 --progress-bar "$1" -o "$2"
}

pause_exit() {
  if [ "$NOPAUSE" = 0 ]; then say ""; read -r -p "按回车键关闭这个窗口……" _; fi
  exit "${1:-0}"
}

# ---------- 开场 ----------
clear 2>/dev/null
say "=============================================="
say "   Claude Code 中文一键安装器（Mac）"
say "   全程自动，大概 3～10 分钟，中途不用你做任何事"
say "   不要管理员密码，不改系统，只装在你自己的用户目录"
[ "$DRY" = 1 ] && say "   >>> 当前是【演练模式】：只打印步骤，不会真的装任何东西 <<<"
[ "$FRESH" = 1 ] && say "   >>> 测试开关：假装电脑上什么都没装 <<<"
say "=============================================="

if [ ! -f "$CFG" ]; then
  say "❌ 找不到配置文件 installer-files/config.json。"
  say "   下一步：请把整个压缩包重新解压，然后在解压出来的文件夹里双击「双击安装」。"
  pause_exit 1
fi

# ============ 第 1 步：检查电脑 ============
step 1 "检查你的电脑"
ARCH="$(uname -m)"
case "$ARCH" in
  arm64)  NODE_ARCH="arm64"; ok "芯片：苹果 M 系列（arm64）" ;;
  x86_64) NODE_ARCH="x64";   ok "芯片：英特尔（x64）" ;;
  *) say "❌ 没见过这种芯片（${ARCH}），这个安装器暂时不支持。"; pause_exit 1 ;;
esac
OSV="$(sw_vers -productVersion)"; OSMAJ="${OSV%%.*}"
if [ "$OSMAJ" -lt 13 ] 2>/dev/null; then
  say "❌ 你的系统是 macOS ${OSV}，Claude Code 官方要求 macOS 13 以上。"
  say "   下一步：打开「系统设置 → 通用 → 软件更新」升级系统后再双击安装。"
  pause_exit 1
fi
ok "系统：macOS $OSV"
if curl -sI -m 10 "$(cfg claude_code.npm_registry)" >/dev/null 2>&1; then
  ok "网络：能连上国内下载镜像"
else
  say "❌ 连不上网（国内镜像 npmmirror 打不开）。"
  say "   下一步：检查 Wi-Fi 或网线，确认能打开网页后，再双击一次安装器。"
  pause_exit 1
fi

# ============ 第 2 步：Node.js ============
step 2 "准备 Node.js（Claude Code 的运行底座）"
NODE_MIN="$(cfg node.min_major)"; NODE_MIN="${NODE_MIN:-22}"
HAVE_NODE=0
if [ "$FRESH" = 0 ] && command -v node >/dev/null 2>&1; then
  NV="$(node -v 2>/dev/null)"; NMAJ="${NV#v}"; NMAJ="${NMAJ%%.*}"
  if [ "${NMAJ:-0}" -ge "$NODE_MIN" ] 2>/dev/null; then
    HAVE_NODE=1; ok "已经装过 Node.js ${NV}，跳过"
  else
    info "电脑上的 Node.js 是 ${NV}，太旧了（要 $NODE_MIN 以上），给你单独装一个新的，不影响旧的"
  fi
fi
if [ "$HAVE_NODE" = 0 ]; then
  MIRROR="$(cfg node.mirror_base)"; OFFICIAL="$(cfg node.official_base)"
  NVER="$(latest_node_lts "$MIRROR")"
  [ -z "$NVER" ] && NVER="$(latest_node_lts "$OFFICIAL")"
  [ -z "$NVER" ] && NVER="$(cfg node.fallback_version)"
  info "要装的版本：Node.js ${NVER}（长期支持版）"
  PKG="node-$NVER-darwin-$NODE_ARCH"
  NODE_HOME="$HOME/.local/share/lingji-node/$PKG"
  info "装到：${NODE_HOME}（你自己的目录，不要密码）"
  if download "$MIRROR/$NVER/$PKG.tar.gz" "$TMPD/node.tgz" || download "$OFFICIAL/$NVER/$PKG.tar.gz" "$TMPD/node.tgz"; then
    run mkdir -p "$HOME/.local/share/lingji-node" "$LOCAL_BIN"
    run tar -xzf "$TMPD/node.tgz" -C "$HOME/.local/share/lingji-node"
    for b in node npm npx; do run ln -sf "$NODE_HOME/bin/$b" "$LOCAL_BIN/$b"; done
    ok "Node.js 准备好了"
  else
    say "❌ Node.js 下载失败（国内镜像和官方地址都没下下来）。"
    say "   下一步：等 5 分钟再双击一次安装器；还不行就打开 https://nodejs.org 下载「LTS」安装包手动装，装完再双击本安装器。"
    pause_exit 1
  fi
fi

# 让新打开的终端也能找到 ~/.local/bin 里的命令
for rc in "$HOME/.zshrc" "$HOME/.bash_profile"; do
  if [ -f "$rc" ] && grep -q 'lingji-cc-installer' "$rc" 2>/dev/null; then continue; fi
  run_sh "printf '\n# lingji-cc-installer: 让终端找到 Claude Code\nexport PATH=\"\$HOME/.local/bin:\$PATH\"\n' >> \"$rc\""
done
ok "终端路径已设置（以后新开的终端都能直接用 claude 命令）"

# ============ 第 3 步：Claude Code ============
step 3 "安装 Claude Code 本体"
CLAUDE_BIN=""
if [ "$FRESH" = 0 ]; then
  if command -v claude >/dev/null 2>&1; then CLAUDE_BIN="$(command -v claude)"
  elif [ -x "$LOCAL_BIN/claude" ]; then CLAUDE_BIN="$LOCAL_BIN/claude"; fi
fi
if [ -n "$CLAUDE_BIN" ]; then
  ok "已经装过 Claude Code（$("$CLAUDE_BIN" --version 2>/dev/null | head -1)），跳过"
else
  NPM_PKG="$(cfg claude_code.npm_package)"; NPM_REG="$(cfg claude_code.npm_registry)"
  info "方式一：从国内 npm 镜像装官方包 $NPM_PKG"
  if [ "$DRY" = 1 ]; then
    probe_url "$NPM_REG/$NPM_PKG/latest" >/dev/null && info "镜像上能查到 $NPM_PKG"
  fi
  if run "$LOCAL_BIN/npm" install -g --prefix "$HOME/.local" "$NPM_PKG" --registry="$NPM_REG" --no-fund --no-audit \
     || run npm install -g --prefix "$HOME/.local" "$NPM_PKG" --registry="$NPM_REG" --no-fund --no-audit; then
    CLAUDE_BIN="$LOCAL_BIN/claude"
  fi
  if [ "$DRY" = 0 ] && ! "$LOCAL_BIN/claude" --version >/dev/null 2>&1; then
    warn "国内镜像没装成功，换方式二：官方安装脚本"
    if run_sh "curl -fsSL '$(cfg claude_code.official_install_sh)' | bash" && "$LOCAL_BIN/claude" --version >/dev/null 2>&1; then
      CLAUDE_BIN="$LOCAL_BIN/claude"
    else
      say "❌ Claude Code 没装上（国内镜像和官方脚本都失败了）。"
      say "   下一步：等 5 分钟再双击一次安装器。还不行，把日志文件发给我们："
      say "   $HOME/Library/Logs/ClaudeCode中文安装器.log"
      pause_exit 1
    fi
  fi
  [ "$DRY" = 1 ] && info "（真装时如果方式一失败，会自动换方式二：curl -fsSL $(cfg claude_code.official_install_sh) | bash）"
  [ "$DRY" = 1 ] && CLAUDE_BIN="$LOCAL_BIN/claude"
  if [ "$DRY" = 0 ]; then ok "Claude Code 装好了：$("$CLAUDE_BIN" --version 2>/dev/null | head -1)"; else ok "（演练）Claude Code 将装到 $CLAUDE_BIN"; fi
fi

# ============ 第 4 步：CC Switch ============
step 4 "安装 CC Switch（一键切换 key / 中转地址的小工具）"
CCS_APP=""
if [ "$FRESH" = 0 ]; then
  for p in "/Applications/CC Switch.app" "$HOME/Applications/CC Switch.app"; do
    [ -d "$p" ] && CCS_APP="$p" && break
  done
fi
if [ -n "$CCS_APP" ]; then
  ok "已经装过 CC Switch（${CCS_APP}），跳过"
else
  REPO="$(cfg cc_switch.github_repo)"
  TAG="$(curl -fsSL -m 15 "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
  [ -z "$TAG" ] && TAG="$(cfg cc_switch.fallback_version)" && info "查不到最新版本号，用内置版本 $TAG"
  ASSET="CC-Switch-$TAG-macOS.tar.gz"
  info "要装的版本：CC Switch ${TAG}（原作者官方包，Apple 公证过）"
  info "装到：$HOME/Applications（你自己的应用文件夹，不要密码）"
  EXTRA="$(cfg cc_switch.extra_download_base)"
  GOT=0
  if [ -n "$EXTRA" ] && download "${EXTRA%/}/$ASSET" "$TMPD/ccs.tgz"; then GOT=1
  elif download "https://github.com/$REPO/releases/download/$TAG/$ASSET" "$TMPD/ccs.tgz"; then GOT=1; fi
  if [ "$GOT" = 1 ]; then
    run mkdir -p "$HOME/Applications"
    run tar -xzf "$TMPD/ccs.tgz" -C "$HOME/Applications"
    CCS_APP="$HOME/Applications/CC Switch.app"
    ok "CC Switch 装好了"
  else
    warn "CC Switch 下载失败（它放在 GitHub 上，国内有时候打不开）。"
    warn "不影响 Claude Code 使用。下一步：过一会儿再双击一次安装器（已装好的会自动跳过），"
    warn "或者自己打开 https://github.com/$REPO/releases 下载「macOS.dmg」拖进应用程序。"
    note_problem "CC Switch 没装上（GitHub 下载失败），稍后重新双击安装器即可"
  fi
fi

# ============ 第 5 步：桌面图标 + 配置 ============
step 5 "在桌面放图标"
DESK="$HOME/Desktop"
SC_CLAUDE="$(cfg shortcuts.claude_name)"; SC_CCS="$(cfg shortcuts.ccswitch_name)"; WS="$(cfg shortcuts.workspace_dir_name)"
run mkdir -p "$HOME/$WS"
info "工作文件夹：$HOME/${WS}（Claude Code 默认在这里干活）"

# 图标 1：打开 Claude Code（一个 .command 文件，双击就开终端跑 claude，不需要额外授权）
F1="$DESK/$SC_CLAUDE.command"
if [ -e "$F1" ] && [ "$FRESH" = 0 ]; then ok "桌面已经有「${SC_CLAUDE}」，跳过"
else
  if [ "$DRY" = 1 ]; then
    printf '   [演练·不执行] 写入桌面文件 %s（内容：进入 ~/%s，运行 %s）\n' "$F1" "$WS" "$CLAUDE_BIN"
  else
    # 双击 .command 时终端的 PATH 很干净，所以把 claude 的完整路径写死，找不到再退回 PATH 查找
    cat > "$F1" <<EOF
#!/bin/bash
export PATH="\$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:\$PATH"
CLAUDE_BIN="$CLAUDE_BIN"
[ -x "\$CLAUDE_BIN" ] || CLAUDE_BIN="claude"
cd "\$HOME/$WS" 2>/dev/null || cd "\$HOME"
clear
echo "正在启动 Claude Code……（第一次会让你登录或填 key，按提示走就行）"
echo "想退出：输入 /exit 回车，或者直接关掉这个窗口。"
echo ""
exec "\$CLAUDE_BIN"
EOF
    chmod +x "$F1"
  fi
  ok "桌面图标「${SC_CLAUDE}」已放好"
fi

# 图标 2：CC Switch 切换 key（一个小 app，双击打开 CC Switch，不弹终端）
F2="$DESK/$SC_CCS.app"
if [ -z "$CCS_APP" ]; then warn "CC Switch 没装上，先不放它的图标（重新双击安装器会补上）"
elif [ -e "$F2" ] && [ "$FRESH" = 0 ]; then ok "桌面已经有「${SC_CCS}」，跳过"
else
  run /usr/bin/osacompile -o "$F2" -e "do shell script \"open -b com.ccswitch.desktop || open -a 'CC Switch'\""
  # 换成 CC Switch 自己的图标（失败也不影响使用）
  run_sh "cp '$CCS_APP/Contents/Resources/icon.icns' '$F2/Contents/Resources/applet.icns' 2>/dev/null && /usr/bin/codesign -f -s - '$F2' >/dev/null 2>&1; touch '$F2'"
  ok "桌面图标「${SC_CCS}」已放好"
fi

# 配置位：将来灵极 API 预填（现在 config.json 里为空 → 跳过，不写任何 key）
API_URL="$(cfg api.base_url)"; API_KEY="$(cfg api.api_key)"
if [ -n "$API_URL" ] && [ -n "$API_KEY" ]; then
  info "检测到预填的 $(cfg api.provider_name) 配置，写入 ~/.claude/settings.json（先备份原文件；key 不在屏幕上显示）"
  SET="$HOME/.claude/settings.json"
  run mkdir -p "$HOME/.claude"
  [ -f "$SET" ] && run cp "$SET" "$SET.bak-$(date +%Y%m%d-%H%M%S)"
  if [ "$DRY" = 0 ]; then
    /usr/bin/osascript -l JavaScript - "$SET" "$API_URL" "$API_KEY" "$(cfg api.model)" <<'JS' >/dev/null || note_problem "API 配置写入失败，可以在 CC Switch 里手动添加"
ObjC.import('Foundation');
function run(argv){
  var p=argv[0], o={};
  var s=$.NSString.stringWithContentsOfFileEncodingError(p,4,null);
  if (s) { try { o=JSON.parse(ObjC.unwrap(s)); } catch(e) { throw 'settings.json 不是合法 JSON，未改动'; } }
  o.env=o.env||{};
  o.env.ANTHROPIC_BASE_URL=argv[1];
  o.env.ANTHROPIC_AUTH_TOKEN=argv[2];
  if (argv[3]) o.env.ANTHROPIC_MODEL=argv[3];
  $(JSON.stringify(o,null,2)).writeToFileAtomicallyEncodingError(p,true,4,null);
  return 'ok';
}
JS
  else
    printf '   [演练·不执行] 合并写入 %s 的 env.ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN（key 打码不显示）\n' "$SET"
  fi
else
  info "API 配置位为空（还没有预填 key）→ 不改你的 Claude 配置。第一次打开时按提示登录，或在 CC Switch 里填 key。"
fi

# ---------- 收尾 ----------
say ""
say "=============================================="
if [ "$DRY" = 1 ]; then
  say "   演练结束：以上是真装时会做的全部动作，本次没有改动你的电脑。"
else
  say "   🎉 装好了！"
  say "   回到桌面，双击「${SC_CLAUDE}」就能开始用。"
  [ -n "$CCS_APP" ] && say "   要换 key / 换中转地址：双击「${SC_CCS}」。"
fi
if [ -n "$PROBLEMS" ]; then say "   还有这些没弄完（不影响主功能）："; printf "%b\n" "$PROBLEMS"; fi
say "=============================================="
pause_exit 0
