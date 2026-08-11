@echo off
REM One-click Windows build for the native IPFS node core.
REM Pass through switches to the PowerShell script, e.g.:
REM   build-windows.bat -Example
setlocal
set "SCRIPT_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%build-windows.ps1" %*
endlocal
