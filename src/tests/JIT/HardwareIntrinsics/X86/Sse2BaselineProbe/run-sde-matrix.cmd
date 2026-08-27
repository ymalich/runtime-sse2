@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "MODE=%~1"
set "PROBE=%~2"
set "RUNTIME_OR_SDE=%~3"
set "SDE_EXE=%~4"

if not defined MODE set "MODE=jit"

if /i "%MODE%"=="jit" goto :jit
if /i "%MODE%"=="aot" goto :aot

echo Usage:
echo   %~nx0 jit [probe.dll] [corerun.exe] [sde.exe]
echo   %~nx0 aot [probe.exe] [sde.exe]
exit /b 2

:jit
if not defined PROBE set "PROBE=%~dp0bin\Release\net11.0\Sse2BaselineProbe.dll"
if not defined RUNTIME_OR_SDE set "RUNTIME_OR_SDE=%~dp0..\..\..\..\..\..\artifacts\sse2-baseline-probe\core_root\corerun.exe"
if not defined SDE_EXE set "SDE_EXE=T:\SDE\sde.exe"

for %%P in (p4p mrm pnr nhm) do (
    echo.
    echo ==== JIT profile %%P ====
    call "%~dp0run-sde-jit.cmd" "%SDE_EXE%" "%RUNTIME_OR_SDE%" "%PROBE%" %%P
    if errorlevel 1 exit /b !ERRORLEVEL!
)
exit /b 0

:aot
if not defined PROBE set "PROBE=%~dp0publish\Sse2BaselineProbe.exe"
if not defined RUNTIME_OR_SDE set "RUNTIME_OR_SDE=T:\SDE\sde.exe"

for %%P in (p4p mrm pnr nhm) do (
    echo.
    echo ==== NativeAOT profile %%P ====
    call "%~dp0run-sde-aot.cmd" "%RUNTIME_OR_SDE%" "%PROBE%" %%P
    if errorlevel 1 exit /b !ERRORLEVEL!
)
exit /b 0
