# ============================================================
#  Claude Code 中文一键安装器 · Windows 版（1.0.0 · 2026-09-23）
#  由「双击安装.bat」调用。不需要管理员权限，全部装在当前用户目录。
#  装好后桌面出现两个图标：「打开 Claude Code」「CC Switch 切换 key」
#
#  测试参数（普通用户用不到）：
#    -DryRun        只演练：打印每一步，不下载、不安装、不改任何文件
#    -PretendFresh  假装电脑上什么都没装（测试全流程用）
#    -NoPause       结束时不等回车（自动化测试用）
#  兼容 Windows PowerShell 5.1（Win10/11 自带）。本文件必须存成 UTF-8 带 BOM。
# ============================================================
param(
  [switch]$DryRun,
  [switch]$PretendFresh,
  [switch]$NoPause
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'   # 关掉 PowerShell 自带进度条，下载快很多
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

$Here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$CfgPath = Join-Path $Here 'config.json'
$Total   = 5
$Tmp     = Join-Path $env:TEMP ("lingji-cc-installer-" + [guid]::NewGuid().ToString('N').Substring(0,8))
$Problems = New-Object System.Collections.ArrayList
$LogPath = Join-Path $env:LOCALAPPDATA 'ClaudeCode中文安装器.log'

function Say($t)  { Write-Host $t }
function Ok($t)   { Write-Host "   [好了] $t" -ForegroundColor Green }
function Info($t) { Write-Host "   · $t" }
function Warn($t) { Write-Host "   [注意] $t" -ForegroundColor Yellow }
function Fail($what, $next) {
  Write-Host ""
  Write-Host "   [没成功] $what" -ForegroundColor Red
  Write-Host "   下一步：$next" -ForegroundColor Red
  Write-Host "   安装日志在：$LogPath"
  Finish 1
}
function Step($n, $title) {
  $left = $Total - $n
  Write-Host ""
  Write-Host "【第 $n 步 / 共 $Total 步】$title   （这步做完还剩 $left 步）" -ForegroundColor Cyan
}
function Plan($t) { Write-Host "   [演练·不执行] $t" -ForegroundColor DarkGray }
function Finish($code) {
  try { if (-not $DryRun) { Stop-Transcript | Out-Null } } catch {}
  if (Test-Path $Tmp) { Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue }
  if (-not $NoPause) { Write-Host ""; Read-Host "按回车键关闭这个窗口" | Out-Null }
  exit $code
}

# 演练时只探测地址（HEAD），真装时下载
function Probe-Url($url) {
  try {
    $r = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 20 -MaximumRedirection 5
    $len = 0; try { $len = [int64]$r.Headers['Content-Length'] } catch {}
    Info ("下载地址可用（HTTP {0}，约 {1} MB）：{2}" -f $r.StatusCode, [math]::Round($len/1MB), $url)
    return $true
  } catch { Warn "下载地址不通：$url"; return $false }
}
function Download($url, $dest) {
  if ($DryRun) { if (Probe-Url $url) { Plan "下载到 $dest"; return $true } else { return $false } }
  try {
    Info "正在下载：$url"
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 900
    return (Test-Path $dest)
  } catch { Warn "这个地址没下下来：$url"; return $false }
}

function Add-UserPath($dir) {
  $cur = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ($null -eq $cur) { $cur = '' }
  $parts = $cur -split ';' | Where-Object { $_ -ne '' }
  if ($parts -notcontains $dir) {
    if ($DryRun) { Plan "把 $dir 加进当前用户的 PATH（不改系统 PATH）" }
    else { [Environment]::SetEnvironmentVariable('Path', (($parts + $dir) -join ';'), 'User') }
  }
  if (($env:Path -split ';') -notcontains $dir) { $env:Path = "$dir;$env:Path" }
}

function Find-Claude {
  $native = Join-Path $env:USERPROFILE '.local\bin\claude.exe'
  if (Test-Path $native) { return $native }
  $c = Get-Command claude.cmd -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { return $c.Source }
  $c = Get-Command claude.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { return $c.Source }
  return $null
}

# ---------- 开场 ----------
if (-not $DryRun) { try { Start-Transcript -Path $LogPath -Append | Out-Null } catch {} }
Clear-Host
Say "=============================================="
Say "   Claude Code 中文一键安装器（Windows）"
Say "   全程自动，大概 3～10 分钟，中途不用你做任何事"
Say "   不要管理员权限，不改系统，只装在你自己的用户目录"
if ($DryRun)       { Say "   >>> 当前是【演练模式】：只打印步骤，不会真的装任何东西 <<<" }
if ($PretendFresh) { Say "   >>> 测试开关：假装电脑上什么都没装 <<<" }
Say "=============================================="

if (-not (Test-Path $CfgPath)) {
  Fail "找不到配置文件 installer-files\config.json。" "把整个压缩包重新「全部解压」，再在解压出来的文件夹里双击「双击安装」。不要直接在压缩包里双击。"
}
try { $Cfg = Get-Content -Raw -Encoding UTF8 $CfgPath | ConvertFrom-Json }
catch { Fail "配置文件读不出来（可能被改坏了）。" "重新解压一份原始压缩包再试。" }
if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $Tmp | Out-Null }

# ============ 第 1 步：检查电脑 ============
Step 1 "检查你的电脑"
$Arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
switch ($Arch) {
  'AMD64' { $NodeArch = 'x64';   $CcsSuffix = 'Windows-Portable.zip';       Ok "处理器：64 位（x64）" }
  'ARM64' { $NodeArch = 'arm64'; $CcsSuffix = 'Windows-arm64-Portable.zip'; Ok "处理器：ARM64" }
  default { Fail "这台电脑是 32 位或不认识的处理器（$Arch），Claude Code 不支持。" "换一台 64 位的 Windows 10/11 电脑。" }
}
$osv = [Environment]::OSVersion.Version
if ($osv.Major -lt 10 -or ($osv.Major -eq 10 -and $osv.Build -lt 17763)) {
  Fail "系统版本太老（$osv），Claude Code 官方要求 Windows 10 1809 以上。" "先用 Windows 更新把系统升到最新，再双击安装。"
}
Ok "系统：Windows $($osv.Major).$($osv.Minor) build $($osv.Build)"
try { Invoke-WebRequest -Uri $Cfg.claude_code.npm_registry -Method Head -UseBasicParsing -TimeoutSec 10 | Out-Null; Ok "网络：能连上国内下载镜像" }
catch { Fail "连不上网（国内镜像 npmmirror 打不开）。" "检查网络，确认浏览器能打开网页后，再双击一次安装器。" }

# ============ 第 2 步：Node.js ============
Step 2 "准备 Node.js（Claude Code 的运行底座）"
$NodeMin = [int]$Cfg.node.min_major
$HaveNode = $false
if (-not $PretendFresh) {
  $n = Get-Command node -ErrorAction SilentlyContinue
  if ($n) {
    $nv = (& node -v 2>$null)
    $maj = 0; [int]::TryParse(($nv -replace '^v','').Split('.')[0], [ref]$maj) | Out-Null
    if ($maj -ge $NodeMin) { $HaveNode = $true; Ok "已经装过 Node.js $nv，跳过" }
    else { Info "电脑上的 Node.js 是 $nv，太旧了（要 $NodeMin 以上），给你单独装一个新的，不影响旧的" }
  }
}
if (-not $HaveNode) {
  $Mirror = $Cfg.node.mirror_base; $Official = $Cfg.node.official_base
  $NVer = $null
  foreach ($b in @($Mirror, $Official)) {
    try { $idx = Invoke-RestMethod -Uri "$b/index.json" -TimeoutSec 20; $NVer = ($idx | Where-Object { $_.lts } | Select-Object -First 1).version; if ($NVer) { break } } catch {}
  }
  if (-not $NVer) { $NVer = $Cfg.node.fallback_version; Info "查不到最新版本号，用内置版本 $NVer" }
  $Pkg = "node-$NVer-win-$NodeArch"
  $NodeRoot = Join-Path $env:LOCALAPPDATA 'Programs\lingji-node'
  $NodeHome = Join-Path $NodeRoot $Pkg
  Info "要装的版本：Node.js $NVer（长期支持版）"
  Info "装到：$NodeHome（你自己的目录，不要管理员）"
  $zip = Join-Path $Tmp 'node.zip'
  if ((Download "$Mirror/$NVer/$Pkg.zip" $zip) -or (Download "$Official/$NVer/$Pkg.zip" $zip)) {
    if ($DryRun) { Plan "解压到 $NodeRoot" }
    else {
      try { New-Item -ItemType Directory -Force -Path $NodeRoot | Out-Null; Expand-Archive -Path $zip -DestinationPath $NodeRoot -Force }
      catch { Fail "Node.js 解压失败（$($_.Exception.Message)）。" "可能是杀毒软件拦了。暂时关掉杀毒软件后再双击一次安装器。" }
    }
    Add-UserPath $NodeHome
    Ok "Node.js 准备好了"
  } else {
    Fail "Node.js 下载失败（国内镜像和官方地址都没下下来）。" "等 5 分钟再双击一次；还不行就打开 https://nodejs.org 下载「LTS」安装包手动装，装完再双击本安装器。"
  }
}

# ============ 第 3 步：Claude Code ============
Step 3 "安装 Claude Code 本体"
$ClaudePath = $null
if (-not $PretendFresh) { $ClaudePath = Find-Claude }
if ($ClaudePath) {
  $ver = (& $ClaudePath --version 2>$null | Select-Object -First 1)
  Ok "已经装过 Claude Code（$ver），跳过"
} else {
  $NpmPkg = $Cfg.claude_code.npm_package; $NpmReg = $Cfg.claude_code.npm_registry
  Info "方式一：从国内 npm 镜像装官方包 $NpmPkg"
  if ($DryRun) {
    if (Probe-Url "$NpmReg/$NpmPkg/latest") { Info "镜像上能查到 $NpmPkg" }
    Plan "npm.cmd install -g $NpmPkg --registry=$NpmReg --allow-scripts=@anthropic-ai/claude-code --no-fund --no-audit"
    Info "（真装时如果方式一失败，会自动换方式二：官方脚本 irm $($Cfg.claude_code.official_install_ps1) | iex）"
    $ClaudePath = '(演练)claude'
  } else {
    # 新版 npm 默认拦包的安装后脚本，Claude Code 靠它解压程序文件，必须放行（旧版 npm 忽略此参数）
    & npm.cmd install -g $NpmPkg "--registry=$NpmReg" "--allow-scripts=@anthropic-ai/claude-code" --no-fund --no-audit
    # npm 全局目录（MSI 装的 Node 是 %APPDATA%\npm；我们装的 Node 就是 Node 目录本身）
    try { $prefix = (& npm.cmd prefix -g 2>$null | Select-Object -First 1).Trim(); if ($prefix) { Add-UserPath $prefix } } catch {}
    $ClaudePath = Find-Claude
    if (-not $ClaudePath) {
      Warn "国内镜像没装成功，换方式二：官方安装脚本"
      try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm $($Cfg.claude_code.official_install_ps1) | iex"
      } catch {}
      Add-UserPath (Join-Path $env:USERPROFILE '.local\bin')
      $ClaudePath = Find-Claude
    }
    if (-not $ClaudePath) {
      Fail "Claude Code 没装上（国内镜像和官方脚本都失败了）。" "等 5 分钟再双击一次安装器；还不行，把安装日志发给我们。"
    }
    $ver = (& $ClaudePath --version 2>$null | Select-Object -First 1)
    Ok "Claude Code 装好了（$ver）"
  }
}

# ============ 第 4 步：CC Switch ============
Step 4 "安装 CC Switch（一键切换 key / 中转地址的小工具）"
$CcsDir = Join-Path $env:LOCALAPPDATA 'Programs\CC-Switch'
$CcsExe = $null
if (-not $PretendFresh) {
  $cands = @(
    (Join-Path $CcsDir 'cc-switch.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\CC Switch\cc-switch.exe'),
    (Join-Path $env:ProgramFiles 'CC Switch\cc-switch.exe')
  )
  foreach ($c in $cands) { if (Test-Path $c) { $CcsExe = $c; break } }
}
if ($CcsExe) {
  Ok "已经装过 CC Switch（$CcsExe），跳过"
} else {
  $Repo = $Cfg.cc_switch.github_repo
  $Tag = $null
  try { $Tag = (Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -TimeoutSec 15).tag_name } catch {}
  if (-not $Tag) { $Tag = $Cfg.cc_switch.fallback_version; Info "查不到最新版本号，用内置版本 $Tag" }
  $Asset = "CC-Switch-$Tag-$CcsSuffix"
  Info "要装的版本：CC Switch $Tag（原作者官方免安装版）"
  Info "装到：$CcsDir（你自己的目录，不要管理员）"
  $zip = Join-Path $Tmp 'ccs.zip'
  $got = $false
  $extra = $Cfg.cc_switch.extra_download_base
  if ($extra) { $got = Download ("{0}/{1}" -f $extra.TrimEnd('/'), $Asset) $zip }
  if (-not $got) { $got = Download "https://github.com/$Repo/releases/download/$Tag/$Asset" $zip }
  if ($got) {
    if ($DryRun) { Plan "解压到 $CcsDir" }
    else {
      try { New-Item -ItemType Directory -Force -Path $CcsDir | Out-Null; Expand-Archive -Path $zip -DestinationPath $CcsDir -Force } catch {}
    }
    $CcsExe = Join-Path $CcsDir 'cc-switch.exe'
    if ($DryRun -or (Test-Path $CcsExe)) { Ok "CC Switch 装好了" }
    else { $CcsExe = $null; Warn "CC Switch 解压失败，可能被杀毒软件拦了。"; [void]$Problems.Add("CC Switch 没装上（解压失败），关掉杀毒软件后重新双击安装器即可") }
  } else {
    Warn "CC Switch 下载失败（它放在 GitHub 上，国内有时候打不开）。"
    Warn "不影响 Claude Code 使用。过一会儿再双击一次安装器（已装好的会自动跳过），"
    Warn "或者自己打开 https://github.com/$Repo/releases 下载「Windows.msi」双击安装。"
    [void]$Problems.Add("CC Switch 没装上（GitHub 下载失败），稍后重新双击安装器即可")
  }
}

# 建快捷方式：老式 WScript.Shell 在非中文系统上存不了中文文件名 → 先用英文临时名保存，再改成中文名；真的存在才算成功
# 注意：WScript.Shell 还会把 .lnk 里的字符串（Arguments / WorkingDirectory 等）按系统 ANSI 代码页保存，
#       英文版 Windows 上中文会变成「???」。所以 .lnk 里只放英文字符，中文全放进启动脚本（UTF-8 带 BOM）。
function Save-Lnk([string]$Path, [scriptblock]$Fill, [string]$TmpDir) {
  if (-not $TmpDir) { $TmpDir = Split-Path $Path }
  $tmpLnk = Join-Path $TmpDir ("happyai-tmp-" + [guid]::NewGuid().ToString('N') + ".lnk")
  try {
    $sh = New-Object -ComObject WScript.Shell
    $s = $sh.CreateShortcut($tmpLnk)
    & $Fill $s
    $want = $s.Arguments
    $s.Save()
    # 回读：参数被代码页改坏（出现 ?）就不算成功
    if ($sh.CreateShortcut($tmpLnk).Arguments -ne $want) { throw "shortcut arguments changed after save" }
    Move-Item -LiteralPath $tmpLnk -Destination $Path -Force
  } catch {
    if (Test-Path -LiteralPath $tmpLnk) { Remove-Item -LiteralPath $tmpLnk -Force -ErrorAction SilentlyContinue }
  }
  return (Test-Path -LiteralPath $Path)
}

function Test-Ascii([string]$t) { return ($t -notmatch '[^\x00-\x7F]') }
# 路径里有中文（比如中文用户名）时，换成系统的 8.3 短路径（纯英文）；换不了返回空
function Get-AsciiDir([string]$dir) {
  if (Test-Ascii $dir) { return $dir }
  try { $fso = New-Object -ComObject Scripting.FileSystemObject; $sp = $fso.GetFolder($dir).ShortPath; if ($sp -and (Test-Ascii $sp)) { return $sp } } catch {}
  return $null
}

# 启动脚本模板（中文都放这里；安装时替换 __WS__ / __BIN__ 后存成 UTF-8 带 BOM）
$LauncherTpl = @'
# Claude Code 启动脚本（由「Claude Code 中文一键安装器」生成；删掉后重新双击安装器会再生成）
$host.UI.RawUI.WindowTitle = 'Claude Code'
$WsName = '__WS__'
$BinPath = '__BIN__'
$Ws = Join-Path $env:USERPROFILE $WsName
if (-not (Test-Path -LiteralPath $Ws)) { New-Item -ItemType Directory -Force -Path $Ws | Out-Null }
Set-Location -LiteralPath $Ws
if (-not (Test-Path -LiteralPath $BinPath)) {
  $c = Get-Command claude.cmd, claude.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { $BinPath = $c.Source }
}
Write-Host '正在启动 Claude Code……（第一次会让你登录或填 key，按提示走就行）'
Write-Host '想退出：输入 /exit 回车，或者直接关掉这个窗口。'
Write-Host ''
& $BinPath
'@

# ============ 第 5 步：桌面图标 + 配置 ============
Step 5 "在桌面放图标"
$Desk = [Environment]::GetFolderPath('Desktop')     # 桌面被 OneDrive 接管也能找对
if (-not $Desk) { $Desk = Join-Path $env:USERPROFILE 'Desktop' }
# 保存快捷方式前确保桌面文件夹存在（不存在时 .Save() 会报「找不到文件」）
if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $Desk | Out-Null }
$Ws = Join-Path $env:USERPROFILE $Cfg.shortcuts.workspace_dir_name
if ($DryRun) { Plan "新建工作文件夹 $Ws" } else { New-Item -ItemType Directory -Force -Path $Ws | Out-Null }
Info "工作文件夹：$Ws（Claude Code 默认在这里干活）"

$Lnk1 = Join-Path $Desk ($Cfg.shortcuts.claude_name + '.lnk')
$Lnk2 = Join-Path $Desk ($Cfg.shortcuts.ccswitch_name + '.lnk')
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

# 启动脚本放在英文目录（快捷方式里只能有英文字符）
$LauncherDir = Join-Path $env:LOCALAPPDATA 'Programs\lingji-claude'
if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $LauncherDir | Out-Null }
$LauncherAscii = Get-AsciiDir $LauncherDir
if (-not $LauncherAscii) {
  # 用户名是中文、系统又关了 8.3 短路径 → 退到公共目录 C:\Users\Public（普通用户可写）
  $pub = if ($env:PUBLIC) { $env:PUBLIC } else { 'C:\Users\Public' }
  $LauncherDir = Join-Path $pub ('lingji-claude-' + $env:USERNAME)
  if (-not (Test-Ascii $LauncherDir)) { $LauncherDir = Join-Path $pub ('lingji-claude-' + [guid]::NewGuid().ToString('N').Substring(0,8)) }
  if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $LauncherDir | Out-Null }
  $LauncherAscii = Get-AsciiDir $LauncherDir
}
$Launcher = Join-Path $LauncherDir 'open-claude.ps1'
$LauncherArg = if ($LauncherAscii) { Join-Path $LauncherAscii 'open-claude.ps1' } else { $null }

if ((Test-Path $Lnk1) -and (Test-Path $Launcher) -and -not $PretendFresh) { Ok "桌面已经有「$($Cfg.shortcuts.claude_name)」，跳过" }
else {
  $ok1 = $false
  if ($DryRun) {
    Plan "生成启动脚本 $Launcher（UTF-8 带 BOM：进入 $Ws，运行 $ClaudePath）"
    Plan "桌面快捷方式 $Lnk1 → $psExe -File `"$LauncherArg`"（快捷方式里只有英文字符）"
  } elseif (-not $LauncherArg) {
    Warn "找不到纯英文的目录放启动脚本（用户名是中文且系统关了短路径）"
  } else {
    try {
      $body = $LauncherTpl.Replace('__WS__', $Cfg.shortcuts.workspace_dir_name.Replace("'", "''")).Replace('__BIN__', $ClaudePath.Replace("'", "''"))
      [IO.File]::WriteAllText($Launcher, $body, (New-Object Text.UTF8Encoding($true)))
    } catch { Warn "启动脚本写不进去：$($_.Exception.Message)" }
    if (Test-Path -LiteralPath $Launcher) {
      $icon = $null
      $iconExe = if ($ClaudePath -like '*.exe') { $ClaudePath } else { (Join-Path (Split-Path $ClaudePath) 'node_modules\@anthropic-ai\claude-code\bin\claude.exe') }
      if ($iconExe -and (Test-Path -LiteralPath $iconExe)) { $d = Get-AsciiDir (Split-Path $iconExe); if ($d) { $icon = (Join-Path $d (Split-Path $iconExe -Leaf)) + ',0' } }
      $ok1 = Save-Lnk $Lnk1 {
        param($s)
        $s.TargetPath = $psExe
        $s.Arguments = "-NoExit -NoLogo -ExecutionPolicy Bypass -File `"$LauncherArg`""
        $s.WorkingDirectory = $LauncherAscii
        if ($icon -and (Test-Ascii $icon)) { $s.IconLocation = $icon }
        $s.Description = 'Claude Code'
      } $LauncherAscii
    }
  }
  if ($DryRun -or $ok1) { Ok "桌面图标「$($Cfg.shortcuts.claude_name)」已放好" }
  else { Warn "桌面图标「$($Cfg.shortcuts.claude_name)」没放上。"; [void]$Problems.Add("桌面图标「$($Cfg.shortcuts.claude_name)」没放上：可以在开始菜单搜 PowerShell，输入 claude 回车来用") }
}

if (-not $CcsExe) { Warn "CC Switch 没装上，先不放它的图标（重新双击安装器会补上）" }
elseif ((Test-Path $Lnk2) -and -not $PretendFresh) { Ok "桌面已经有「$($Cfg.shortcuts.ccswitch_name)」，跳过" }
else {
  if ($DryRun) { Plan "桌面快捷方式 $Lnk2 → $CcsExe" }
  else {
    $ok2 = Save-Lnk $Lnk2 {
      param($s)
      $s.TargetPath = $CcsExe
      $s.WorkingDirectory = Split-Path $CcsExe
      $s.IconLocation = "$CcsExe,0"
      $s.Description = 'CC Switch'
    }
  }
  if ($DryRun -or $ok2) { Ok "桌面图标「$($Cfg.shortcuts.ccswitch_name)」已放好" }
  else { Warn "桌面图标「$($Cfg.shortcuts.ccswitch_name)」没放上。"; [void]$Problems.Add("桌面图标「$($Cfg.shortcuts.ccswitch_name)」没放上：CC Switch 在 $CcsExe，双击它也能打开") }
}

# 配置位：将来灵极 API 预填（现在 config.json 为空 → 跳过，不写任何 key）
$ApiUrl = $Cfg.api.base_url; $ApiKey = $Cfg.api.api_key
if ($ApiUrl -and $ApiKey) {
  $SetPath = Join-Path $env:USERPROFILE '.claude\settings.json'
  Info "检测到预填的 $($Cfg.api.provider_name) 配置，写入 $SetPath（先备份原文件；key 不在屏幕上显示）"
  if ($DryRun) { Plan "合并写入 env.ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN（key 打码）" }
  else {
    try {
      New-Item -ItemType Directory -Force -Path (Split-Path $SetPath) | Out-Null
      $obj = New-Object PSObject
      if (Test-Path $SetPath) {
        Copy-Item $SetPath ("$SetPath.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $obj = Get-Content -Raw -Encoding UTF8 $SetPath | ConvertFrom-Json
      }
      if (-not $obj.env) { $obj | Add-Member -NotePropertyName env -NotePropertyValue (New-Object PSObject) -Force }
      $obj.env | Add-Member -NotePropertyName ANTHROPIC_BASE_URL -NotePropertyValue $ApiUrl -Force
      $obj.env | Add-Member -NotePropertyName ANTHROPIC_AUTH_TOKEN -NotePropertyValue $ApiKey -Force
      if ($Cfg.api.model) { $obj.env | Add-Member -NotePropertyName ANTHROPIC_MODEL -NotePropertyValue $Cfg.api.model -Force }
      $json = $obj | ConvertTo-Json -Depth 20
      [IO.File]::WriteAllText($SetPath, $json, (New-Object Text.UTF8Encoding($false)))
      Ok "API 配置已写入"
    } catch { Warn "API 配置写入失败（原文件已备份，没改坏）。可以在 CC Switch 里手动添加。"; [void]$Problems.Add("API 配置没写进去，可在 CC Switch 里手动添加") }
  }
} else {
  Info "API 配置位为空（还没有预填 key）→ 不改你的 Claude 配置。第一次打开时按提示登录，或在 CC Switch 里填 key。"
}

# ---------- 收尾 ----------
Say ""
Say "=============================================="
if ($DryRun) { Say "   演练结束：以上是真装时会做的全部动作，本次没有改动你的电脑。" }
else {
  Say "   装好了！"
  Say "   回到桌面，双击「$($Cfg.shortcuts.claude_name)」就能开始用。"
  if ($CcsExe) { Say "   要换 key / 换中转地址：双击「$($Cfg.shortcuts.ccswitch_name)」。" }
}
if ($Problems.Count -gt 0) { Say "   还有这些没弄完（不影响主功能）："; foreach ($p in $Problems) { Say "   - $p" } }
Say "=============================================="
Finish 0
