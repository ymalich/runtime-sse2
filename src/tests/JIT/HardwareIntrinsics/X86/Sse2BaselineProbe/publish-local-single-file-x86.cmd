@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "PROBE_ROOT=%~dp0"
set "RUNTIME_ROOT=%~dp0..\..\..\..\..\.."
set "LOCAL_FEED=%RUNTIME_ROOT%\artifacts\packages\Release\Shipping"
set "NUGET_PACKAGES=%RUNTIME_ROOT%\artifacts\sse2-baseline-probe\nuget-single-file-x86"
set "PUBLISH_DIR=%PROBE_ROOT%publish-single-file-x86"
set "PACKAGE_VERSION=11.0.0-sse2"
set "PACKED_JIT=%NUGET_PACKAGES%\microsoft.netcore.app.runtime.win-x86\%PACKAGE_VERSION%\runtimes\win-x86\native\clrjit.dll"
set "DOTNET_EXE=%~1"
set "MSBUILDDISABLENODEREUSE=1"

if not defined DOTNET_EXE set "DOTNET_EXE=%ProgramFiles%\dotnet\dotnet.exe"

if not exist "%DOTNET_EXE%" (
    echo ERROR: The x64 .NET SDK host was not found:
    echo        %DOTNET_EXE%
    echo Pass its full path as the first argument.
    exit /b 2
)

"%DOTNET_EXE%" --list-sdks | findstr /r /b "11\." >nul
if errorlevel 1 (
    echo ERROR: A system-wide x64 .NET 11 SDK is required.
    echo        The repository-local SDK cannot be used after an x86 runtime
    echo        has been installed into its shared framework directory.
    exit /b 2
)

if not exist "%LOCAL_FEED%\Microsoft.NETCore.App.Runtime.win-x86.%PACKAGE_VERSION%.nupkg" (
    echo ERROR: Local x86 runtime package was not found:
    echo        %LOCAL_FEED%\Microsoft.NETCore.App.Runtime.win-x86.%PACKAGE_VERSION%.nupkg
    echo Run build-local-runtime-sse2-x86.cmd first.
    exit /b 1
)

call "%DOTNET_EXE%" build-server shutdown >nul 2>&1

if exist "%NUGET_PACKAGES%" rmdir /s /q "%NUGET_PACKAGES%"
if exist "%NUGET_PACKAGES%" (
    echo ERROR: The NuGet cache is still in use: %NUGET_PACKAGES%
    echo Stop remaining dotnet or MSBuild processes and try again.
    exit /b 1
)

if exist "%PUBLISH_DIR%" rmdir /s /q "%PUBLISH_DIR%"
if exist "%PUBLISH_DIR%" (
    echo ERROR: The publish directory is still in use: %PUBLISH_DIR%
    exit /b 1
)

echo Project      : %PROBE_ROOT%Sse2BaselineProbe.csproj
echo Runtime feed : %LOCAL_FEED%
echo NuGet cache  : %NUGET_PACKAGES%
echo Output       : %PUBLISH_DIR%
echo SDK host     : %DOTNET_EXE%
echo Runtime      : custom JIT %PACKAGE_VERSION% win-x86
echo Mode         : self-contained, trimmed, single file
echo.

rem Run outside the repository so global.json does not select the repository-local
rem x64 SDK whose shared framework directory contains the x86 custom runtime.
pushd "%TEMP%"
"%DOTNET_EXE%" publish "%PROBE_ROOT%Sse2BaselineProbe.csproj" ^
    --disable-build-servers ^
    -c Release ^
    -r win-x86 ^
    --self-contained true ^
    --packages "%NUGET_PACKAGES%" ^
    -p:PublishAot=false ^
    -p:UseAppHost=true ^
    -p:PublishSingleFile=true ^
    -p:PublishTrimmed=true ^
    -p:IncludeNativeLibrariesForSelfExtract=true ^
    -p:DebugType=None ^
    -p:DebugSymbols=false ^
    -p:RestoreAdditionalProjectSources="%LOCAL_FEED%" ^
    -o "%PUBLISH_DIR%"
set "EXITCODE=%ERRORLEVEL%"
popd
if not "%EXITCODE%"=="0" exit /b %EXITCODE%

if not exist "%PACKED_JIT%" goto :wrongruntime
if not exist "%PUBLISH_DIR%\Sse2BaselineProbe.exe" goto :missing

call "%DOTNET_EXE%" build-server shutdown >nul 2>&1

echo.
echo x86 trimmed single-file custom-runtime publish completed successfully.
echo Run the SSE2 SDE test with:
echo   "%PROBE_ROOT%run-sde-x86.cmd"
exit /b 0

:missing
echo ERROR: Publish completed but Sse2BaselineProbe.exe was not found.
exit /b 1

:wrongruntime
echo ERROR: The local %PACKAGE_VERSION% win-x86 runtime package was not restored.
exit /b 1
