@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem Build the user-facing SSE2 replacement for the stable .NET 11.0.0 runtime.
rem Use this script only in a dedicated release checkout with clean artifacts.

set "RUNTIME_ROOT=%~dp0"
set "CONFIGURATION=Release"
set "ARCHITECTURE=x64"
set "VERSION_SUFFIX="
set "PACKAGE_VERSION=11.0.0"
set "LOCAL_FEED=%RUNTIME_ROOT%artifacts\packages\%CONFIGURATION%\Shipping"
set "LOCAL_RUNTIME_ZIP=%LOCAL_FEED%\dotnet-runtime-%PACKAGE_VERSION%-win-%ARCHITECTURE%.zip"
set "LOCAL_RUNTIME_STAGE=%RUNTIME_ROOT%artifacts\tmp\sse2-release-local-runtime"
set "LOCAL_SHARED_FRAMEWORK=%RUNTIME_ROOT%.dotnet\shared\Microsoft.NETCore.App\%PACKAGE_VERSION%"
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

if exist "%LOCAL_FEED%\*%PACKAGE_VERSION%*.nupkg" (
    echo Removing stale %PACKAGE_VERSION% packages from the local Shipping feed...
    del /q "%LOCAL_FEED%\*%PACKAGE_VERSION%*.nupkg" || exit /b 1
)

call "%RUNTIME_ROOT%build.cmd" clr+libs+host+packs ^
    -c %CONFIGURATION% ^
    -arch %ARCHITECTURE% ^
    /p:VersionSuffix=%VERSION_SUFFIX% ^
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
    /p:VersionSuffix=%VERSION_SUFFIX% ^
    /p:DotNetFinalVersionKind=release
if errorlevel 1 exit /b %ERRORLEVEL%

call "%RUNTIME_ROOT%dotnet.cmd" msbuild ^
    "%RUNTIME_ROOT%src\tools\illink\src\ILLink.Tasks\ILLink.Tasks.csproj" ^
    /t:Pack ^
    /restore ^
    /p:Configuration=%CONFIGURATION% ^
    /p:VersionSuffix=%VERSION_SUFFIX% ^
    /p:DotNetFinalVersionKind=release
if errorlevel 1 exit /b %ERRORLEVEL%

echo.
echo Verifying required release packages...
call :RequirePackage "Microsoft.DotNet.ILCompiler.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequirePackage "runtime.win-x64.Microsoft.DotNet.ILCompiler.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequirePackage "Microsoft.NETCore.App.Runtime.NativeAOT.win-x64.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequirePackage "Microsoft.NETCore.App.Runtime.win-x64.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequirePackage "Microsoft.NETCore.App.Ref.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequirePackage "Microsoft.NET.ILLink.Tasks.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequirePackage "dotnet-runtime-%PACKAGE_VERSION%-win-x64.msi" || exit /b 1
call :RequirePackage "dotnet-runtime-%PACKAGE_VERSION%-win-x64.zip" || exit /b 1
call :RequirePackage "dotnet-runtime-%PACKAGE_VERSION%-win-x64.exe" || exit /b 1

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

:RequirePackage
if not exist "%LOCAL_FEED%\%~1" (
    echo ERROR: Required package was not produced: %LOCAL_FEED%\%~1
    exit /b 1
)
echo   %~1
exit /b 0

:WriteSha256
powershell.exe -NoProfile -Command ^
    "$p=[IO.Path]::GetFullPath('%~1'); $h=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash; [IO.File]::WriteAllText($p + '.sha256', $h + '  ' + [IO.Path]::GetFileName($p) + [Environment]::NewLine)"
exit /b %ERRORLEVEL%
