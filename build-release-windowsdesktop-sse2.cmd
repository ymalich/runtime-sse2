@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem Build the user-facing Windows Desktop Runtime 11.0.0 replacement bundle.
rem Run build-release-runtime-sse2.cmd in this checkout first.

set "RUNTIME_ROOT=%~dp0"
set "WINDOWSDESKTOP_ROOT=%~1"
if not defined WINDOWSDESKTOP_ROOT set "WINDOWSDESKTOP_ROOT=T:\Git\windowsdesktop"
if not "%WINDOWSDESKTOP_ROOT:~-1%"=="\" set "WINDOWSDESKTOP_ROOT=%WINDOWSDESKTOP_ROOT%\"
set "CONFIGURATION=Release"
set "ARCHITECTURE=x64"
set "PACKAGE_VERSION=11.0.0"
set "LOCAL_FEED=%RUNTIME_ROOT%artifacts\packages\%CONFIGURATION%\Shipping"
set "DESKTOP_SHIPPING=%WINDOWSDESKTOP_ROOT%artifacts\packages\%CONFIGURATION%\Shipping"
set "DESKTOP_BUNDLE=%WINDOWSDESKTOP_ROOT%src\windowsdesktop\src\bundle\bundle.wixproj"
set "DISTRIBUTION_DIR=%RUNTIME_ROOT%artifacts\sse2-distribution\%PACKAGE_VERSION%"
set "DESKTOP_INSTALLER=%DESKTOP_SHIPPING%\windowsdesktop-runtime-%PACKAGE_VERSION%-win-%ARCHITECTURE%.exe"
set "PUBLIC_DESKTOP_INSTALLER=%DISTRIBUTION_DIR%\windowsdesktop-runtime-%PACKAGE_VERSION%-sse2-win-%ARCHITECTURE%.exe"

if not exist "%WINDOWSDESKTOP_ROOT%build.cmd" (
    echo ERROR: windowsdesktop checkout was not found: %WINDOWSDESKTOP_ROOT%
    exit /b 1
)
findstr /c:"UseLocalRuntimePrereqs" "%WINDOWSDESKTOP_ROOT%src\windowsdesktop\src\bundle\Wix.targets" >nul
if errorlevel 1 (
    echo ERROR: The windowsdesktop checkout does not support local runtime prerequisites.
    echo Apply the SSE2 local-runtime changes to src\windowsdesktop\src\bundle\Wix.targets first.
    exit /b 1
)

call :RequireRuntimeArtifact "Microsoft.NETCore.App.Ref.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequireRuntimeArtifact "Microsoft.NETCore.App.Crossgen2.win-x64.%PACKAGE_VERSION%.nupkg" || exit /b 1
call :RequireRuntimeArtifact "dotnet-host-%PACKAGE_VERSION%-win-x64.msi" || exit /b 1
call :RequireRuntimeArtifact "dotnet-hostfxr-%PACKAGE_VERSION%-win-x64.msi" || exit /b 1
call :RequireRuntimeArtifact "dotnet-runtime-%PACKAGE_VERSION%-win-x64.msi" || exit /b 1

echo WARNING: This bundle installs framework version %PACKAGE_VERSION% and replaces
echo the official .NET 11 runtime identity on the target computer.
echo.
echo Windows Desktop root : %WINDOWSDESKTOP_ROOT%
echo Custom runtime feed  : %LOCAL_FEED%
echo Package version      : %PACKAGE_VERSION%
echo Architecture         : %ARCHITECTURE%
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WINDOWSDESKTOP_ROOT%eng\common\Build.ps1" ^
    -configuration %CONFIGURATION% ^
    -platform %ARCHITECTURE% ^
    -restore -build -pack ^
    -projects "%DESKTOP_BUNDLE%" ^
    /p:VersionSuffix= ^
    /p:DotNetFinalVersionKind=release ^
    /p:PreReleaseVersionLabel= ^
    /p:PreReleaseVersionIteration= ^
    /p:MicrosoftNETCoreAppRefPackageVersion=%PACKAGE_VERSION% ^
    /p:MicrosoftNETCoreAppRefVersion=%PACKAGE_VERSION% ^
    /p:RestoreAdditionalProjectSources=%LOCAL_FEED% ^
    /p:UseLocalRuntimePrereqs=true ^
    /p:RuntimePrereqDownloadDirectory=%LOCAL_FEED%\
if errorlevel 1 exit /b %ERRORLEVEL%

call :RequireDesktopArtifact "windowsdesktop-runtime-%PACKAGE_VERSION%-win-x64.msi" || exit /b 1
call :RequireDesktopArtifact "windowsdesktop-runtime-%PACKAGE_VERSION%-win-x64.exe" || exit /b 1

if not exist "%DISTRIBUTION_DIR%" mkdir "%DISTRIBUTION_DIR%" || exit /b 1
copy /y "%DESKTOP_INSTALLER%" "%PUBLIC_DESKTOP_INSTALLER%" >nul || exit /b 1
call :WriteSha256 "%PUBLIC_DESKTOP_INSTALLER%" || exit /b 1

echo.
echo Stable SSE2 Windows Desktop Runtime build completed successfully.
echo Internal bundle: %DESKTOP_INSTALLER%
echo Distribution  : %PUBLIC_DESKTOP_INSTALLER%
exit /b 0

:RequireRuntimeArtifact
if not exist "%LOCAL_FEED%\%~1" (
    echo ERROR: Required stable runtime artifact was not found: %LOCAL_FEED%\%~1
    echo Run build-release-runtime-sse2.cmd first.
    exit /b 1
)
exit /b 0

:RequireDesktopArtifact
if not exist "%DESKTOP_SHIPPING%\%~1" (
    echo ERROR: Expected Windows Desktop artifact was not produced: %DESKTOP_SHIPPING%\%~1
    exit /b 1
)
exit /b 0

:WriteSha256
powershell.exe -NoProfile -Command ^
    "$p=[IO.Path]::GetFullPath('%~1'); $h=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash; [IO.File]::WriteAllText($p + '.sha256', $h + '  ' + [IO.Path]::GetFileName($p) + [Environment]::NewLine)"
exit /b %ERRORLEVEL%
