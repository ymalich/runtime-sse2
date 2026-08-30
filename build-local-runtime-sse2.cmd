@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem Build a local .NET runtime and all packs needed to publish win-x64 NativeAOT applications.
rem Run this script from any directory. It always builds the checkout that contains this file.

set "RUNTIME_ROOT=%~dp0"
set "CONFIGURATION=Release"
set "ARCHITECTURE=x64"
set "VERSION_SUFFIX=sse2"
set "PACKAGE_VERSION=11.0.0-sse2"
set "LOCAL_FEED=%RUNTIME_ROOT%artifacts\packages\%CONFIGURATION%\Shipping"
set "LOCAL_RUNTIME_ZIP=%LOCAL_FEED%\dotnet-runtime-%PACKAGE_VERSION%-win-%ARCHITECTURE%.zip"
set "LOCAL_RUNTIME_STAGE=%RUNTIME_ROOT%artifacts\tmp\sse2-local-runtime"
set "LOCAL_SHARED_FRAMEWORK=%RUNTIME_ROOT%.dotnet\shared\Microsoft.NETCore.App\%PACKAGE_VERSION%"

echo Runtime root : %RUNTIME_ROOT%
echo Configuration: %CONFIGURATION%
echo Architecture : %ARCHITECTURE%
echo Package ver. : %PACKAGE_VERSION%
echo.

cd /d "%RUNTIME_ROOT%" || exit /b 1

rem Arcade's packaging target only tracks the generated nuspec. If an nupkg with
rem the same version already exists, changed compiler binaries may not be repacked.
if exist "%LOCAL_FEED%\*%PACKAGE_VERSION%*.nupkg" (
    echo Removing stale %PACKAGE_VERSION% packages from the local Shipping feed...
    del /q "%LOCAL_FEED%\*%PACKAGE_VERSION%*.nupkg" || exit /b 1
)

rem Do not add DotNetBuildAllRuntimePacks=true here. It requests Mono cross packs
rem for Android/WASM and requires cross compilers that are irrelevant to win-x64.
call "%RUNTIME_ROOT%build.cmd" clr+libs+host+packs ^
    -c %CONFIGURATION% ^
    -arch %ARCHITECTURE% ^
    /p:VersionSuffix=%VERSION_SUFFIX%

if errorlevel 1 exit /b %errorlevel%

rem The normal win-x64 packs subset builds the NativeAOT compiler packages, but
rem not Microsoft.NETCore.App.Runtime.NativeAOT.win-x64. Enabling
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
call :RequirePackage "runtime.win-x64.Microsoft.DotNet.ILCompiler.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequirePackage "Microsoft.NETCore.App.Runtime.NativeAOT.win-x64.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequirePackage "Microsoft.NETCore.App.Runtime.win-x64.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequirePackage "Microsoft.NETCore.App.Ref.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequirePackage "Microsoft.NET.ILLink.Tasks.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequirePackage "dotnet-runtime-%PACKAGE_VERSION%-win-x64.msi" || exit /b 1
call :RequirePackage "dotnet-runtime-%PACKAGE_VERSION%-win-x64.zip" || exit /b 1

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

:RequirePackage
if not exist "%LOCAL_FEED%\%~1" (
    echo ERROR: Required package was not produced: %LOCAL_FEED%\%~1
    exit /b 1
)
echo   %~1
exit /b 0
