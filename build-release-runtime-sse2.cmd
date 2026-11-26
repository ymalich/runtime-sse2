@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem Build the user-facing SSE2 replacement for the stable .NET runtime of this checkout.
rem Use this script only in a dedicated release checkout with clean artifacts.
rem Usage: build-release-runtime-sse2.cmd [x64|x86]   (default: x64)

set "RUNTIME_ROOT=%~dp0"
set "CONFIGURATION=Release"

rem Optional first argument wins, otherwise honor an ARCHITECTURE env var, otherwise default to x64.
if not "%~1"=="" set "ARCHITECTURE=%~1"
if not defined ARCHITECTURE set "ARCHITECTURE=x64"
if /i not "%ARCHITECTURE%"=="x64" if /i not "%ARCHITECTURE%"=="x86" (
    echo ERROR: Unsupported architecture "%ARCHITECTURE%". Supported values: x64, x86.
    exit /b 2
)
rem Derive the product version from eng\Versions.props so the script follows the
rem checkout instead of carrying a hand-maintained copy of the version number.
set "VERSIONS_PROPS=%RUNTIME_ROOT%eng\Versions.props"
call :ReadProductVersion || exit /b 1
set "PACKAGE_VERSION=%PRODUCT_VERSION%"
set "MSBUILDDISABLENODEREUSE=1"
set "LOCAL_FEED=%RUNTIME_ROOT%artifacts\packages\%CONFIGURATION%\Shipping"
set "INTERMEDIATE_OUTPUT=%RUNTIME_ROOT%artifacts\obj"
set "LOCAL_RUNTIME_ZIP=%LOCAL_FEED%\dotnet-runtime-%PACKAGE_VERSION%-win-%ARCHITECTURE%.zip"
set "LOCAL_RUNTIME_STAGE=%RUNTIME_ROOT%artifacts\tmp\sse2-release-local-runtime"
rem Keep each architecture in its own shared-framework slot under the local SDK.
rem x64 uses the default layout; x86 uses the standard multi-arch .dotnet\x86 root
rem so an x86 run never replaces the 64-bit framework used by the host tooling.
if /i "%ARCHITECTURE%"=="x86" (
    set "SDK_ARCH_ROOT=%RUNTIME_ROOT%.dotnet\x86"
) else (
    set "SDK_ARCH_ROOT=%RUNTIME_ROOT%.dotnet"
)
set "LOCAL_SHARED_FRAMEWORK=%SDK_ARCH_ROOT%\shared\Microsoft.NETCore.App\%PACKAGE_VERSION%"
set "DISTRIBUTION_DIR=%RUNTIME_ROOT%artifacts\sse2-distribution\%PACKAGE_VERSION%"
set "RUNTIME_INSTALLER=%LOCAL_FEED%\dotnet-runtime-%PACKAGE_VERSION%-win-%ARCHITECTURE%.exe"
set "PUBLIC_RUNTIME_INSTALLER=%DISTRIBUTION_DIR%\dotnet-runtime-%PACKAGE_VERSION%-sse2-win-%ARCHITECTURE%.exe"

echo WARNING: This build uses the official framework identity %PACKAGE_VERSION%.
echo It is a replacement for the official .NET runtime, not a side-by-side build.
echo.
echo Runtime root : %RUNTIME_ROOT%
echo Configuration: %CONFIGURATION%
echo Architecture : %ARCHITECTURE%
echo Package ver. : %PACKAGE_VERSION%
echo.

cd /d "%RUNTIME_ROOT%" || exit /b 1

rem Release and development builds reuse several build-task binaries. Stop an
rem earlier MSBuild node before cleaning or overwriting those assemblies, and
rem keep this build from leaving another reusable node behind.
call "%RUNTIME_ROOT%dotnet.cmd" build-server shutdown || exit /b 1

rem Development and stable-identity builds cannot safely share packaging
rem intermediates. Their staged pack layouts otherwise contain both the stable
rem version and its -sse2 variant, causing WiX payload queries to find duplicates.
if exist "%INTERMEDIATE_OUTPUT%" (
    echo Removing version-sensitive intermediate build outputs...
    rmdir /s /q "%INTERMEDIATE_OUTPUT%" || exit /b 1
)

if exist "%LOCAL_FEED%\*%PACKAGE_VERSION%*.nupkg" (
    echo Removing stale %PACKAGE_VERSION% packages from the local Shipping feed...
    del /q "%LOCAL_FEED%\*%PACKAGE_VERSION%*.nupkg" || exit /b 1
)

call "%RUNTIME_ROOT%build.cmd" clr+libs+host+packs ^
    -c %CONFIGURATION% ^
    -arch %ARCHITECTURE% ^
    /p:DotNetFinalVersionKind=release
if errorlevel 1 exit /b %ERRORLEVEL%

call "%RUNTIME_ROOT%dotnet.cmd" msbuild ^
    "%RUNTIME_ROOT%src\installer\pkg\sfx\Microsoft.NETCore.App\Microsoft.NETCore.App.Runtime.NativeAOT.sfxproj" ^
    /t:Pack ^
    /restore ^
    /p:Configuration=%CONFIGURATION% ^
    /p:TargetOS=windows ^
    /p:TargetArchitecture=%ARCHITECTURE% ^
    /p:TargetRid=win-%ARCHITECTURE% ^
    /p:RuntimeIdentifier=win-%ARCHITECTURE% ^
    /p:DotNetFinalVersionKind=release
if errorlevel 1 exit /b %ERRORLEVEL%

call "%RUNTIME_ROOT%dotnet.cmd" msbuild ^
    "%RUNTIME_ROOT%src\tools\illink\src\ILLink.Tasks\ILLink.Tasks.csproj" ^
    /t:Pack ^
    /restore ^
    /p:Configuration=%CONFIGURATION% ^
    /p:DotNetFinalVersionKind=release
if errorlevel 1 exit /b %ERRORLEVEL%

echo.
echo Verifying required release packages...
call :RequirePackage "Microsoft.DotNet.ILCompiler.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequirePackage "runtime.win-%ARCHITECTURE%.Microsoft.DotNet.ILCompiler.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequirePackage "Microsoft.NETCore.App.Runtime.NativeAOT.win-%ARCHITECTURE%.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequirePackage "Microsoft.NETCore.App.Runtime.win-%ARCHITECTURE%.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequirePackage "Microsoft.NETCore.App.Ref.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequirePackage "Microsoft.NET.ILLink.Tasks.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequirePackage "dotnet-runtime-%PACKAGE_VERSION%-win-%ARCHITECTURE%.msi" || exit /b 1
call :RequirePackage "dotnet-runtime-%PACKAGE_VERSION%-win-%ARCHITECTURE%.zip" || exit /b 1
call :RequirePackage "dotnet-runtime-%PACKAGE_VERSION%-win-%ARCHITECTURE%.exe" || exit /b 1

rem Install the stable custom runtime into this checkout's private SDK so that
rem framework-dependent build tools resolve the same locally built runtime.
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

if not exist "%DISTRIBUTION_DIR%" mkdir "%DISTRIBUTION_DIR%" || exit /b 1
copy /y "%RUNTIME_INSTALLER%" "%PUBLIC_RUNTIME_INSTALLER%" >nul || exit /b 1
call :WriteSha256 "%PUBLIC_RUNTIME_INSTALLER%" || exit /b 1

echo.
echo Stable SSE2 runtime build completed successfully.
echo Packages     : %LOCAL_FEED%
echo Local runtime: %LOCAL_SHARED_FRAMEWORK%
echo Distribution : %PUBLIC_RUNTIME_INSTALLER%
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

:WriteSha256
powershell.exe -NoProfile -NonInteractive -Command ^
    "$ErrorActionPreference='Stop'; $p=[IO.Path]::GetFullPath('%~1'); $s=[IO.File]::OpenRead($p); try { $a=[Security.Cryptography.SHA256]::Create(); try { $h=([BitConverter]::ToString($a.ComputeHash($s))).Replace('-','') } finally { $a.Dispose() } } finally { $s.Dispose() }; [IO.File]::WriteAllText($p + '.sha256', $h + '  ' + [IO.Path]::GetFileName($p) + [Environment]::NewLine)"
exit /b %ERRORLEVEL%
