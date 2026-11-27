@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "PROBE_ROOT=%~dp0"
set "RUNTIME_ROOT=%~dp0..\..\..\..\..\.."
set "LOCAL_FEED=%RUNTIME_ROOT%\artifacts\packages\Release\Shipping"
set "NUGET_PACKAGES=%RUNTIME_ROOT%\artifacts\sse2-baseline-probe\nuget-single-file-x86"
set "PUBLISH_DIR=%PROBE_ROOT%publish-single-file-x86"
set "VERSION_SUFFIX=sse2"
rem Derive the product version from eng\Versions.props so the probe follows the
rem checkout instead of carrying a hand-maintained copy of the version number.
set "VERSIONS_PROPS=%RUNTIME_ROOT%\eng\Versions.props"
call :ReadProductVersion || exit /b 1
set "PACKAGE_VERSION=%PRODUCT_VERSION%-%VERSION_SUFFIX%"
set "PACKED_JIT=%NUGET_PACKAGES%\microsoft.netcore.app.runtime.win-x86\%PACKAGE_VERSION%\runtimes\win-x86\native\clrjit.dll"
set "DOTNET_EXE=%~1"
set "MSBUILDDISABLENODEREUSE=1"
set "DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1"

if not defined DOTNET_EXE call :ResolveHost

if not exist "%DOTNET_EXE%" (
    echo ERROR: The x64 .NET SDK host was not found:
    echo        %DOTNET_EXE%
    echo Pass the full path to an x64 dotnet.exe as the first argument.
    exit /b 2
)

"%DOTNET_EXE%" --list-sdks | findstr /r /b "11\." >nul
if errorlevel 1 (
    echo ERROR: An x64 .NET 11 SDK is required.
    echo        Pass the full path to an x64 dotnet.exe as the first argument.
    exit /b 2
)

if not exist "%LOCAL_FEED%\Microsoft.NETCore.App.Runtime.win-x86.%PACKAGE_VERSION%.nupkg" (
    echo ERROR: Local x86 runtime package was not found:
    echo        %LOCAL_FEED%\Microsoft.NETCore.App.Runtime.win-x86.%PACKAGE_VERSION%.nupkg
    echo Run build-local-runtime-sse2.cmd x86 first.
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
rem SDK, which is bound to this checkout.
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
    -p:CustomRuntimeVersion=%PACKAGE_VERSION% ^
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

:ResolveHost
rem Prefer the repository-local x64 host: ILLink runs as an x64 tool and requests
rem the custom x64 shared framework, which the x86 build installs into .dotnet\x86
rem without replacing the x64 one.
set "DOTNET_EXE=%RUNTIME_ROOT%\.dotnet\dotnet.exe"
if exist "%DOTNET_EXE%" goto :eof
set "DOTNET_EXE=%ProgramFiles%\dotnet\dotnet.exe"
goto :eof

:ReadProductVersion
rem Read MajorVersion/MinorVersion/PatchVersion from the eng\Versions.props of the
rem checkout named by VERSIONS_PROPS and expose the result as PRODUCT_VERSION.
if not exist "%VERSIONS_PROPS%" (
    echo ERROR: Version file was not found: %VERSIONS_PROPS%
    exit /b 1
)
set "PRODUCT_VERSION="
for /f "usebackq delims=" %%v in (`powershell.exe -NoProfile -NonInteractive -Command "$g=([xml](Get-Content -Raw -LiteralPath '%VERSIONS_PROPS%')).Project.PropertyGroup; '{0}.{1}.{2}' -f @($g.MajorVersion)[0],@($g.MinorVersion)[0],@($g.PatchVersion)[0]"`) do set "PRODUCT_VERSION=%%v"
echo %PRODUCT_VERSION%| findstr /r "^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul
if errorlevel 1 (
    echo ERROR: Could not read MajorVersion, MinorVersion and PatchVersion from:
    echo        %VERSIONS_PROPS%
    echo        Read value: "%PRODUCT_VERSION%"
    exit /b 1
)
exit /b 0
