@echo off
setlocal

set "SDE_EXE=%~1"
set "AOT_EXE=%~2"
set "SDE_CPU=%~3"

if not defined SDE_EXE set "SDE_EXE=T:\SDE\sde.exe"
if not defined AOT_EXE set "AOT_EXE=%~dp0publish\Sse2BaselineProbe.exe"
if not defined SDE_CPU set "SDE_CPU=p4p"

echo SDE   : %SDE_EXE%
echo CPU   : %SDE_CPU%
echo probe : %AOT_EXE%

"%SDE_EXE%" -%SDE_CPU% -- "%AOT_EXE%"
set "EXITCODE=%ERRORLEVEL%"
if "%EXITCODE%"=="100" set "EXITCODE=0"
exit /b %EXITCODE%
