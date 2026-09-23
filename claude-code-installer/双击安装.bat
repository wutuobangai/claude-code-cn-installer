@echo off
rem Claude Code one-click installer (Windows) - draft 0.1.0 2026-09-23
rem Double-click me. No admin rights needed. The real work is in installer-files\install.ps1
setlocal
chcp 65001 >nul
cd /d "%~dp0"
if not exist "%~dp0installer-files\install.ps1" (
  echo.
  echo [!] installer-files folder not found. Please EXTRACT ALL files from the zip first, then double-click again.
  echo [!] 找不到 installer-files 文件夹：请先把压缩包「全部解压」，再双击本文件。
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer-files\install.ps1" %*
exit /b %errorlevel%
