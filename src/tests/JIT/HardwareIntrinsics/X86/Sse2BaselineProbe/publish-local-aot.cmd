@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "PROBE_ROOT=%~dp0"
set "RUNTIME_ROOT=%~dp0..\..\..\..\..\.."
set "LOCAL_FEED=%RUNTIME_ROOT%\artifacts\packages\Release\Shipping"
set "NUGET_PACKAGES=%RUNTIME_ROOT%\artifacts\sse2-baseline-probe\nuget"
set "PUBLISH_DIR=%PROBE_ROOT%publish-aot"
set "PACKAGE_VERSION=11.0.0-sse2"

if exist "%NUGET_PACKAGES%" rmdir /s /q "%NUGET_PACKAGES%"
if exist "%NUGET_PACKAGES%" (
    echo ERROR: The NuGet cache is still in use: %NUGET_PACKAGES%
    echo Run "%RUNTIME_ROOT%\.dotnet\dotnet.exe" build-server shutdown and try again.
    exit /b 1
)

echo Project      : %PROBE_ROOT%Sse2BaselineProbe.csproj
echo Runtime feed : %LOCAL_FEED%
echo NuGet cache  : %NUGET_PACKAGES%
echo ISA baseline : base

"%RUNTIME_ROOT%\.dotnet\dotnet.exe" publish "%PROBE_ROOT%Sse2BaselineProbe.csproj" ^
    --disable-build-servers ^
    -c Release ^
    -r win-x64 ^
    --self-contained true ^
    --packages "%NUGET_PACKAGES%" ^
    -p:PublishAot=true ^
    -p:ILCompilerVersion=%PACKAGE_VERSION% ^
    -p:RestoreAdditionalProjectSources="%LOCAL_FEED%" ^
    -p:IlcInstructionSet=base ^
    -o "%PUBLISH_DIR%"
exit /b %ERRORLEVEL%
