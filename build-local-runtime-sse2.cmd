@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "MSBUILDDISABLENODEREUSE=1"

rem Build a local .NET runtime and all packs needed to publish Windows NativeAOT applications.
rem Run this script from any directory. It always builds the checkout that contains this file.
rem Usage: build-local-runtime-sse2.cmd [x64|x86]   (default: x64)

set "RUNTIME_ROOT=%~dp0"
set "DOTNET_INSTALL_DIR=%RUNTIME_ROOT%.dotnet"
set "CONFIGURATION=Release"

rem Optional first argument wins, otherwise honor an ARCHITECTURE env var, otherwise default to x64.
if not "%~1"=="" set "ARCHITECTURE=%~1"
if not defined ARCHITECTURE set "ARCHITECTURE=x64"
if /i not "%ARCHITECTURE%"=="x64" if /i not "%ARCHITECTURE%"=="x86" (
    echo ERROR: Unsupported architecture "%ARCHITECTURE%". Supported values: x64, x86.
    exit /b 2
)
set "VERSION_SUFFIX=sse2"
rem Derive the product version from eng\Versions.props so the script follows the
rem checkout instead of carrying a hand-maintained copy of the version number.
set "VERSIONS_PROPS=%RUNTIME_ROOT%eng\Versions.props"
call :ReadProductVersion || exit /b 1
set "PACKAGE_VERSION=%PRODUCT_VERSION%-%VERSION_SUFFIX%"
set "LOCAL_FEED=%RUNTIME_ROOT%artifacts\packages\%CONFIGURATION%\Shipping"
set "INTERMEDIATE_OUTPUT=%RUNTIME_ROOT%artifacts\obj"
set "LOCAL_RUNTIME_ZIP=%LOCAL_FEED%\dotnet-runtime-%PACKAGE_VERSION%-win-%ARCHITECTURE%.zip"
set "LOCAL_RUNTIME_STAGE=%RUNTIME_ROOT%artifacts\tmp\sse2-local-runtime"
rem Keep each architecture in its own shared-framework slot under the local SDK.
rem x64 uses the default layout; x86 uses the standard multi-arch .dotnet\x86 root
rem so an x86 run never replaces the 64-bit framework used by the host tooling.
if /i "%ARCHITECTURE%"=="x86" (
    set "SDK_ARCH_ROOT=%RUNTIME_ROOT%.dotnet\x86"
) else (
    set "SDK_ARCH_ROOT=%RUNTIME_ROOT%.dotnet"
)
set "LOCAL_SHARED_FRAMEWORK=%SDK_ARCH_ROOT%\shared\Microsoft.NETCore.App\%PACKAGE_VERSION%"

echo Runtime root : %RUNTIME_ROOT%
echo Configuration: %CONFIGURATION%
echo Architecture : %ARCHITECTURE%
echo Package ver. : %PACKAGE_VERSION%
echo.

cd /d "%RUNTIME_ROOT%" || exit /b 1

rem Stop build servers left by an earlier invocation before deleting or replacing
rem packages and compiler binaries that they may still have loaded.
call "%RUNTIME_ROOT%dotnet.cmd" build-server shutdown >nul 2>&1

rem Arcade's packaging target only tracks the generated nuspec. If an nupkg with
rem the same version already exists, changed compiler binaries may not be repacked.
if exist "%LOCAL_FEED%\*%PACKAGE_VERSION%*.nupkg" (
    echo Removing stale %PACKAGE_VERSION% packages from the local Shipping feed...
    del /q "%LOCAL_FEED%\*%PACKAGE_VERSION%*.nupkg" || exit /b 1
)

rem A stable-identity release build in the same checkout leaves its versioned
rem pack layout under artifacts\obj. WiX harvesting requires exactly one version
rem per pack directory, so drop staging directories for other versions only.
for /f "delims=" %%p in ('dir /s /b /ad "%INTERMEDIATE_OUTPUT%" 2^>nul ^| findstr /i /e /c:"\o\packs"') do (
    for /d %%f in ("%%p\*") do (
        for /d %%v in ("%%f\*") do if /i not "%%~nxv"=="%PACKAGE_VERSION%" (
            echo Removing stale pack layout: %%v
            rmdir /s /q "%%v"
        )
    )
)

rem Do not add DotNetBuildAllRuntimePacks=true here. It requests Mono cross packs
rem for Android/WASM and requires cross compilers that are irrelevant to Windows.
call "%RUNTIME_ROOT%build.cmd" clr+libs+host+packs ^
    -c %CONFIGURATION% ^
    -arch %ARCHITECTURE% ^
    /p:VersionSuffix=%VERSION_SUFFIX%

if errorlevel 1 exit /b %errorlevel%

rem The normal win-%ARCHITECTURE% packs subset builds the NativeAOT compiler packages, but
rem not Microsoft.NETCore.App.Runtime.NativeAOT.win-%ARCHITECTURE%. Enabling
rem DotNetBuildAllRuntimePacks would also request unrelated Mono Android/WASM
rem cross packs, so package just the NativeAOT runtime pack explicitly.
call "%RUNTIME_ROOT%dotnet.cmd" msbuild ^
    "%RUNTIME_ROOT%src\installer\pkg\sfx\Microsoft.NETCore.App\Microsoft.NETCore.App.Runtime.NativeAOT.sfxproj" ^
    /t:Pack ^
    /restore ^
    /p:Configuration=%CONFIGURATION% ^
    /p:TargetOS=windows ^
    /p:TargetArchitecture=%ARCHITECTURE% ^
    /p:TargetRid=win-%ARCHITECTURE% ^
    /p:RuntimeIdentifier=win-%ARCHITECTURE% ^
    /p:VersionSuffix=%VERSION_SUFFIX%
if errorlevel 1 exit /b %errorlevel%

rem ILLink.Tasks is a tools package and is not packed by clr+libs+host+packs.
rem NativeAOT restore requires the package with exactly the local runtime version.
call "%RUNTIME_ROOT%dotnet.cmd" msbuild ^
    "%RUNTIME_ROOT%src\tools\illink\src\ILLink.Tasks\ILLink.Tasks.csproj" ^
    /t:Pack ^
    /restore ^
    /p:Configuration=%CONFIGURATION% ^
    /p:VersionSuffix=%VERSION_SUFFIX%
if errorlevel 1 exit /b %errorlevel%

echo.
echo Verifying required NativeAOT packages...
call :RequirePackage "Microsoft.DotNet.ILCompiler.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequirePackage "runtime.win-%ARCHITECTURE%.Microsoft.DotNet.ILCompiler.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequirePackage "Microsoft.NETCore.App.Runtime.NativeAOT.win-%ARCHITECTURE%.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequirePackage "Microsoft.NETCore.App.Runtime.win-%ARCHITECTURE%.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequirePackage "Microsoft.NETCore.App.Ref.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequirePackage "Microsoft.NET.ILLink.Tasks.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequirePackage "dotnet-runtime-%PACKAGE_VERSION%-win-%ARCHITECTURE%.msi" || exit /b 1
call :RequirePackage "dotnet-runtime-%PACKAGE_VERSION%-win-%ARCHITECTURE%.zip" || exit /b 1

rem Framework-dependent build tools in packages such as ILLink.Tasks request
rem Microsoft.NETCore.App with the same prerelease suffix. Install that runtime
rem into the repository-local SDK so publishing works without a system-wide
rem installation of this unofficial runtime.
echo.
echo Installing %PACKAGE_VERSION% into the repository-local SDK...
if exist "%LOCAL_RUNTIME_STAGE%" rmdir /s /q "%LOCAL_RUNTIME_STAGE%"
mkdir "%LOCAL_RUNTIME_STAGE%" || exit /b 1
tar.exe -xf "%LOCAL_RUNTIME_ZIP%" -C "%LOCAL_RUNTIME_STAGE%" || exit /b 1
if not exist "%LOCAL_RUNTIME_STAGE%\shared\Microsoft.NETCore.App\%PACKAGE_VERSION%\System.Private.CoreLib.dll" (
    echo ERROR: The runtime ZIP does not contain Microsoft.NETCore.App %PACKAGE_VERSION%.
    exit /b 1
)
if exist "%LOCAL_SHARED_FRAMEWORK%" rmdir /s /q "%LOCAL_SHARED_FRAMEWORK%"
mkdir "%LOCAL_SHARED_FRAMEWORK%" || exit /b 1
xcopy /e /i /q /y ^
    "%LOCAL_RUNTIME_STAGE%\shared\Microsoft.NETCore.App\%PACKAGE_VERSION%\*" ^
    "%LOCAL_SHARED_FRAMEWORK%\" >nul || exit /b 1
rmdir /s /q "%LOCAL_RUNTIME_STAGE%"
if not exist "%LOCAL_SHARED_FRAMEWORK%\.version" exit /b 1

echo.
echo Local NativeAOT runtime build completed successfully.
echo Packages: %LOCAL_FEED%
echo Local SDK runtime: %LOCAL_SHARED_FRAMEWORK%
exit /b 0

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

:RequirePackage
if not exist "%LOCAL_FEED%\%~1" (
    echo ERROR: Required package was not produced: %LOCAL_FEED%\%~1
    exit /b 1
)
echo   %~1
exit /b 0
