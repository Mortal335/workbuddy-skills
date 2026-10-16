@echo off
rem ============================================================
rem  fix-acl.bat  --  repair missing ACE for
rem  APPLICATION PACKAGE AUTHORITY\ALL RESTRICTED APPLICATION PACKAGES
rem  (S-1-15-2-2) -- Windows Electron/Chromium launcher regression.
rem
rem  Usage:
rem    1) drag a folder onto it       : fix that folder
rem    2) fix-acl.bat "D:\SomeApp"    : fix the given folder
rem    3) must be run AS ADMINISTRATOR (right-click, then "Run as administrator")
rem       when the target owner is BUILTIN\Administrators.
rem
rem  NOTE: never put a redirection character in a rem line -- cmd.exe parses
rem        it and silently creates a stray file.
rem
rem  Log: %TEMP%\_acl_fix.log
rem  NOTE: keep this file pure ASCII + CRLF. cmd.exe reads .bat by byte
rem        blocks; LF-only or CJK content can break parsing mid-line.
rem ============================================================
setlocal

set "TARGET=%~1"
set "LOG=%TEMP%\_acl_fix.log"

if "%TARGET%"=="" goto :usage

echo ==== fix-acl ==== > "%LOG%"
echo target = %TARGET% >> "%LOG%"
echo date   = %DATE% %TIME% >> "%LOG%"
echo. >> "%LOG%"

if not exist "%TARGET%" (
  echo [ERROR] target does not exist >> "%LOG%"
  echo MISSING >> "%LOG%"
  goto :done
)

echo [1] existing ACL on target >> "%LOG%"
icacls "%TARGET%" >> "%LOG%" 2>&1
echo. >> "%LOG%"

echo [2] grant S-1-15-2-2:(RX) recursively >> "%LOG%"
icacls "%TARGET%" /grant "*S-1-15-2-2:(RX)" /T /C >> "%LOG%" 2>&1
echo. >> "%LOG%"
echo [3] icacls exitcode = %ERRORLEVEL% >> "%LOG%"
echo. >> "%LOG%"

echo [4] verify every exe under target root >> "%LOG%"
for %%F in ("%TARGET%\*.exe") do (
  echo --- %%F --- >> "%LOG%"
  icacls "%%F" >> "%LOG%" 2>&1
)
if exist "%TARGET%\resources" (
  echo --- %TARGET%\resources --- >> "%LOG%"
  icacls "%TARGET%\resources" >> "%LOG%" 2>&1
)
echo. >> "%LOG%"
echo [5] verify chromium dlls >> "%LOG%"
for %%D in (libGLESv2.dll libEGL.dll d3dcompiler_47.dll dxcompiler.dll dxil.dll icudtl.dat vk_swiftshader.dll vulkan-1.dll) do (
  if exist "%TARGET%\%%D" (
    icacls "%TARGET%\%%D" >> "%LOG%" 2>&1
  )
)
echo. >> "%LOG%"
echo [6] done exitcode=%ERRORLEVEL% >> "%LOG%"
echo DONE >> "%LOG%"

:done
echo.
echo Log written to %LOG%
echo.
if "%~1"=="" pause
exit /b 0

:usage
echo.
echo [USAGE] Drag a folder onto this .bat file, or run:
echo         fix-acl.bat "D:\SomeApp"
echo.
echo         If the target owner is BUILTIN\Administrators, close this
echo         and instead right-click the file, then choose
echo         "Run as administrator" -- otherwise icacls reports
echo         "access denied" on every program file.
echo.
echo No argument was given, so nothing was changed.
echo.
pause
exit /b 1
