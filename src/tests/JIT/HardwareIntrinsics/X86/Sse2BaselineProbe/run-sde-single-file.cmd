@echo off
setlocal

set "SDE_EXE=%~1"
set "PROBE_EXE=%~2"
set "SDE_CPU=%~3"

if not defined SDE_EXE set "SDE_EXE=T:\SDE\sde.exe"
if not defined PROBE_EXE set "PROBE_EXE=%~dp0publish-single-file\Sse2BaselineProbe.exe"
if not defined SDE_CPU set "SDE_CPU=p4p"

echo SDE   : %SDE_EXE%
echo CPU   : %SDE_CPU%
echo probe : %PROBE_EXE%

"%SDE_EXE%" -%SDE_CPU% -- "%PROBE_EXE%"
set "EXITCODE=%ERRORLEVEL%"
if "%EXITCODE%"=="100" set "EXITCODE=0"
exit /b %EXITCODE%
