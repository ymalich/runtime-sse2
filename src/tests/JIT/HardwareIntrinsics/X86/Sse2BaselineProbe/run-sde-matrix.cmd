@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "MODE=%~1"
set "PROBE=%~2"
set "SDE_EXE=%~3"

if not defined MODE set "MODE=single-file"

if /i "%MODE%"=="aot" goto :aot
if /i "%MODE%"=="single-file" goto :singlefile
if /i "%MODE%"=="singlefile" goto :singlefile

echo Usage:
echo   %~nx0 aot [probe.exe] [sde.exe]
echo   %~nx0 single-file [probe.exe] [sde.exe]
exit /b 2

:singlefile
if not defined PROBE set "PROBE=%~dp0publish-single-file\Sse2BaselineProbe.exe"
if not defined SDE_EXE set "SDE_EXE=T:\SDE\sde.exe"

for %%P in (p4p mrm pnr nhm) do (
    echo.
    echo ==== Single-file JIT profile %%P ====
    call "%~dp0run-sde-single-file.cmd" "%SDE_EXE%" "%PROBE%" %%P
    if errorlevel 1 exit /b !ERRORLEVEL!
)
exit /b 0

:aot
if not defined PROBE set "PROBE=%~dp0publish-aot\Sse2BaselineProbe.exe"
if not defined SDE_EXE set "SDE_EXE=T:\SDE\sde.exe"

for %%P in (p4p mrm pnr nhm) do (
    echo.
    echo ==== NativeAOT profile %%P ====
    call "%~dp0run-sde-aot.cmd" "%SDE_EXE%" "%PROBE%" %%P
    if errorlevel 1 exit /b !ERRORLEVEL!
)
exit /b 0
