# Claude Code 中文一键安装器 · 怎么用

> 草稿 0.1.0 · 2026-09-23 · 未发布。推广素材（七件套：先看我.html / 海报 / 官网快捷方式 / 二维码）由主线后面统一加进包里。

**装完能干嘛**：桌面多出两个图标。双击「打开 Claude Code」就能跟 AI 编程助手说话；双击「CC Switch 切换 key」一键换 key / 换中转地址。

## 三步用法

### Windows
1. 把压缩包**全部解压**（右键 → 全部解压缩），别在压缩包里直接双击
2. 双击「**双击安装.bat**」。如果弹出蓝色的「Windows 已保护你的电脑」：点「**更多信息**」→「**仍要运行**」
3. 等它跑完（3～10 分钟），回桌面双击「**打开 Claude Code**」

### Mac
1. 双击压缩包解压
2. **右键**点「**双击安装.command**」→「打开」→ 再点「打开」。如果提示「无法验证开发者」：打开「系统设置 → 隐私与安全性」，拉到底点「**仍要打开**」
3. 等它跑完（3～10 分钟），回桌面双击「**打开 Claude Code**」

> 第一次打开 Claude Code 会让你登录 Claude 账号，或者在 CC Switch 里填中转站的 key。

## 装了什么、装在哪（不要管理员密码，不改系统）

| 东西 | 什么时候装 | Windows 装到 | Mac 装到 |
|---|---|---|---|
| Node.js LTS | 电脑上没有 22 以上版本时 | `%LOCALAPPDATA%\Programs\lingji-node\` | `~/.local/share/lingji-node/`（命令链接到 `~/.local/bin`） |
| Claude Code（官方 npm 包） | 没装过时 | npm 全局目录 | `~/.local/bin/claude` |
| CC Switch（原作者官方包，MIT） | 没装过时 | `%LOCALAPPDATA%\Programs\CC-Switch\`（免安装版） | `~/Applications/CC Switch.app` |
| 桌面图标 ×2 | 桌面上还没有时 | `.lnk` 快捷方式 | `打开 Claude Code.command` + `CC Switch 切换 key.app` |
| 工作文件夹 | — | `%USERPROFILE%\Claude工作区` | `~/Claude工作区` |

已经装过的会自动跳过，重复双击不会重复装。安装日志：Windows `%LOCALAPPDATA%\ClaudeCode中文安装器.log`，Mac `~/Library/Logs/ClaudeCode中文安装器.log`。

## 下载走哪里（不内置任何翻墙/代理）
- Node.js：先国内镜像 `npmmirror.com/mirrors/node`，失败再官方 `nodejs.org/dist`
- Claude Code：先国内 npm 镜像 `registry.npmmirror.com`，失败再官方脚本 `claude.ai/install.sh` / `install.ps1`
- CC Switch：原作者 GitHub Release（国内偶尔打不开 → 提示稍后重试或手动下载；`config.json` 里 `cc_switch.extra_download_base` 留给将来我们自己的 OSS 备份）

## 给我们自己看：配置位 `installer-files/config.json`
- `api.base_url` / `api.api_key`：**现在为空**。将来灵极 API 上线，打包前填好，两项都不为空时安装器才会写入用户的 `~/.claude/settings.json`（`env.ANTHROPIC_BASE_URL` + `env.ANTHROPIC_AUTH_TOKEN`，写前自动备份，key 不在屏幕上显示）
- `node.fallback_version` / `cc_switch.fallback_version`：查不到最新版时用的保底版本（2026-09-23 核实：Node v24.21.0 LTS、CC Switch v3.20.4）

## 测试开关（普通用户用不到）
- Mac：`./双击安装.command --dry-run [--pretend-fresh] [--no-pause]`
- Windows：`双击安装.bat -DryRun [-PretendFresh] [-NoPause]`
- `--dry-run` 只打印步骤 + 探测下载地址能不能通，不下载、不装、不改任何文件
- 云端真机测试草稿：`tests/github-actions-installer-test.yml`（未推送）
