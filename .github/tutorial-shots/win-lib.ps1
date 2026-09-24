# © Happy AI · 教程截图 Windows 小工具（每个步骤开头 . 引入）
# 注意：这里所有等待都有上限，绝不用 Start-Process -Wait
#       （PowerShell 7 的 -Wait 会连「安装器顺手拉起的软件」一起等，软件不退出就永远卡住——上次 Cherry Studio 就是这么卡死的）

function Get-LatestTag([string]$Repo, [string]$Fallback) {
  # 不调 GitHub API：直接看 releases/latest 跳转到哪个 tag
  try {
    $h = & curl.exe -sSI --max-time 20 "https://github.com/$Repo/releases/latest" 2>$null
    foreach ($line in $h) { if ($line -match '^[Ll]ocation:\s*\S+/tag/([^/\s]+)') { return $Matches[1] } }
  } catch {}
  return $Fallback
}

function Get-File([string]$Url, [string]$Out, [int]$MaxSec = 240) {
  & curl.exe -fsSL --retry 2 --max-time $MaxSec -o $Out $Url
  return ($LASTEXITCODE -eq 0 -and (Test-Path $Out) -and ((Get-Item $Out).Length -gt 100000))
}

function Invoke-Bounded([string]$File, [string[]]$ArgList, [int]$Sec) {
  $p = Start-Process -FilePath $File -ArgumentList $ArgList -PassThru
  if (-not $p.WaitForExit($Sec * 1000)) {
    Write-Host "超过 $Sec 秒还没结束，强制结束：$File"
    try { $p.Kill() } catch {}
    return $false
  }
  return $true
}

function Save-FullScreen([string]$Path) {
  Add-Type -AssemblyName System.Windows.Forms, System.Drawing
  $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
  $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  Write-Host "saved $Path"
}
