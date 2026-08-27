@echo off
setlocal
set "COMPlus_NoGuiOnAssert=1"

set "SDE_EXE=%~1"
set "CORERUN_EXE=%~2"
set "PROBE_DLL=%~3"
set "SDE_CPU=%~4"

if not defined SDE_EXE set "SDE_EXE=T:\SDE\sde.exe"
if not defined CORERUN_EXE set "CORERUN_EXE=%~dp0..\..\..\..\..\..\artifacts\sse2-baseline-probe\core_root\corerun.exe"
if not defined PROBE_DLL set "PROBE_DLL=%~dp0bin\Release\net11.0\Sse2BaselineProbe.dll"
if not defined SDE_CPU set "SDE_CPU=p4p"

rem Prescott is the oldest x64 profile in Intel SDE. Disable the combined
rem SSE3/SSSE3/SSE4.x/POPCNT group so this profile exercises SSE2 codegen.
if /i "%SDE_CPU%"=="p4p" set "COMPlus_EnableSSE42=0"

echo SDE     : %SDE_EXE%
echo CPU     : %SDE_CPU%
echo corerun : %CORERUN_EXE%
echo probe   : %PROBE_DLL%

"%SDE_EXE%" -%SDE_CPU% -- "%CORERUN_EXE%" "%PROBE_DLL%"
set "EXITCODE=%ERRORLEVEL%"
if "%EXITCODE%"=="100" set "EXITCODE=0"
exit /b %EXITCODE%
