@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "SDE_EXE=%~1"
set "PROBE_EXE=%~2"
set "SDE_CPU=%~3"

if not defined SDE_EXE set "SDE_EXE=T:\SDE\sde.exe"
if not defined PROBE_EXE set "PROBE_EXE=%~dp0publish-single-file-x86\Sse2BaselineProbe.exe"
if not defined SDE_CPU set "SDE_CPU=p4p"

if not exist "%SDE_EXE%" (
    echo ERROR: Intel SDE was not found:
    echo        %SDE_EXE%
    exit /b 2
)

if not exist "%PROBE_EXE%" (
    echo ERROR: The x86 probe was not found:
    echo        %PROBE_EXE%
    echo Publish Sse2BaselineProbe as a self-contained win-x86 single-file application first.
    exit /b 2
)

echo SDE   : %SDE_EXE%
echo CPU   : %SDE_CPU%
echo probe : %PROBE_EXE%
echo mode  : win-x86 self-contained single-file
echo.

"%SDE_EXE%" -%SDE_CPU% -- "%PROBE_EXE%"
set "EXITCODE=%ERRORLEVEL%"

rem Sse2BaselineProbe returns 100 when all checks pass.
if "%EXITCODE%"=="100" (
    echo.
    echo PASS: x86 SSE2 baseline probe completed successfully under SDE.
    exit /b 0
)

if "%EXITCODE%"=="127" (
    echo.
    echo ERROR: Intel SDE returned exit code 127.
    echo Check Windows Event Viewer for a crash in ia32\pinrt\pind.exe or smserver-plugin.dll.
    echo Also try a current Intel SDE release and keep the extracted SDE directory intact.
)

exit /b %EXITCODE%
