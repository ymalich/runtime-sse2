@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "PROBE_ROOT=%~dp0"
set "RUNTIME_ROOT=%~dp0..\..\..\..\..\.."
set "LOCAL_FEED=%RUNTIME_ROOT%\artifacts\packages\Release\Shipping"
set "NUGET_PACKAGES=%RUNTIME_ROOT%\artifacts\sse2-baseline-probe\nuget-single-file"
set "PUBLISH_DIR=%PROBE_ROOT%publish-single-file"
set "PACKAGE_VERSION=11.0.0-sse2"
set "PACKED_JIT=%NUGET_PACKAGES%\microsoft.netcore.app.runtime.win-x64\%PACKAGE_VERSION%\runtimes\win-x64\native\clrjit.dll"

if not exist "%LOCAL_FEED%\Microsoft.NETCore.App.Runtime.win-x64.%PACKAGE_VERSION%.nupkg" (
    echo ERROR: Local runtime package was not found:
    echo        %LOCAL_FEED%\Microsoft.NETCore.App.Runtime.win-x64.%PACKAGE_VERSION%.nupkg
    echo Run build-local-runtime-sse2.cmd first.
    exit /b 1
)

if exist "%NUGET_PACKAGES%" rmdir /s /q "%NUGET_PACKAGES%"
if exist "%NUGET_PACKAGES%" (
    echo ERROR: The NuGet cache is still in use: %NUGET_PACKAGES%
    echo Run "%RUNTIME_ROOT%\.dotnet\dotnet.exe" build-server shutdown and try again.
    exit /b 1
)
if exist "%PUBLISH_DIR%" rmdir /s /q "%PUBLISH_DIR%"

echo Project      : %PROBE_ROOT%Sse2BaselineProbe.csproj
echo Runtime feed : %LOCAL_FEED%
echo NuGet cache  : %NUGET_PACKAGES%
echo Output       : %PUBLISH_DIR%
echo Runtime      : custom JIT %PACKAGE_VERSION% win-x64
echo Mode         : self-contained, trimmed, single file
echo.

"%RUNTIME_ROOT%\.dotnet\dotnet.exe" publish "%PROBE_ROOT%Sse2BaselineProbe.csproj" ^
    --disable-build-servers ^
    -c Release ^
    -r win-x64 ^
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
if errorlevel 1 exit /b %ERRORLEVEL%

if not exist "%PACKED_JIT%" goto :wrongruntime
if not exist "%PUBLISH_DIR%\Sse2BaselineProbe.exe" goto :missing

echo.
echo Trimmed single-file custom-runtime publish completed successfully.
echo Copy this executable to the target machine:
echo   %PUBLISH_DIR%\Sse2BaselineProbe.exe
exit /b 0

:missing
echo ERROR: Publish completed but Sse2BaselineProbe.exe was not found.
exit /b 1

:wrongruntime
echo ERROR: The local %PACKAGE_VERSION% runtime package was not restored.
exit /b 1
