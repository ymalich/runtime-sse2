@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem Build a custom Windows Desktop Runtime bundle that carries the SSE2 CoreCLR.
rem The windowsdesktop checkout remains unmodified; all overrides are command-line properties.

set "RUNTIME_ROOT=%~dp0"
set "WINDOWSDESKTOP_ROOT=%~1"
if not defined WINDOWSDESKTOP_ROOT set "WINDOWSDESKTOP_ROOT=T:\Git\windowsdesktop"
if not "%WINDOWSDESKTOP_ROOT:~-1%"=="\" set "WINDOWSDESKTOP_ROOT=%WINDOWSDESKTOP_ROOT%\"
set "CONFIGURATION=Release"
set "ARCHITECTURE=x64"
set "PACKAGE_VERSION=11.0.0-sse2"
set "LOCAL_FEED=%RUNTIME_ROOT%artifacts\packages\%CONFIGURATION%\Shipping"
set "DESKTOP_SHIPPING=%WINDOWSDESKTOP_ROOT%artifacts\packages\%CONFIGURATION%\Shipping"
set "DESKTOP_BUNDLE=%WINDOWSDESKTOP_ROOT%src\windowsdesktop\src\bundle\bundle.wixproj"

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

echo Windows Desktop root : %WINDOWSDESKTOP_ROOT%
echo Custom runtime feed  : %LOCAL_FEED%
echo Package version      : %PACKAGE_VERSION%
echo Architecture         : %ARCHITECTURE%
echo.

rem The bundle project builds the WindowsForms/WPF shared framework MSI through
rem its project references. The custom ref and Crossgen2 packs keep generated R2R
rem code compatible with the SSE2 baseline. The local prerequisite directory makes
rem the bundle embed our host, hostfxr and runtime MSI instead of downloading them.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WINDOWSDESKTOP_ROOT%eng\common\Build.ps1" ^
    -configuration %CONFIGURATION% ^
    -platform %ARCHITECTURE% ^
    -restore -build -pack ^
    -projects "%DESKTOP_BUNDLE%" ^
    /p:VersionSuffix=sse2 ^
    /p:MicrosoftNETCoreAppRefPackageVersion=%PACKAGE_VERSION% ^
    /p:MicrosoftNETCoreAppRefVersion=%PACKAGE_VERSION% ^
    /p:RestoreAdditionalProjectSources=%LOCAL_FEED% ^
    /p:UseLocalRuntimePrereqs=true ^
    /p:RuntimePrereqDownloadDirectory=%LOCAL_FEED%\
if errorlevel 1 exit /b %ERRORLEVEL%

call :RequireDesktopArtifact "windowsdesktop-runtime-%PACKAGE_VERSION%-win-x64.msi" || exit /b 1
call :RequireDesktopArtifact "windowsdesktop-runtime-%PACKAGE_VERSION%-win-x64.exe" || exit /b 1

echo.
echo Custom Windows Desktop Runtime build completed successfully.
echo MSI    : %DESKTOP_SHIPPING%\windowsdesktop-runtime-%PACKAGE_VERSION%-win-x64.msi
echo Bundle : %DESKTOP_SHIPPING%\windowsdesktop-runtime-%PACKAGE_VERSION%-win-x64.exe
exit /b 0

:RequireRuntimeArtifact
if not exist "%LOCAL_FEED%\%~1" (
    echo ERROR: Required custom runtime artifact was not found: %LOCAL_FEED%\%~1
    echo Run build-local-runtime-sse2.cmd first.
    exit /b 1
)
exit /b 0

:RequireDesktopArtifact
if not exist "%DESKTOP_SHIPPING%\%~1" (
    echo ERROR: Expected Windows Desktop artifact was not produced: %DESKTOP_SHIPPING%\%~1
    exit /b 1
)
exit /b 0
