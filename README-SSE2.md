# Unofficial .NET 11 Runtime with an SSE2 Baseline

## Overview

This repository contains an unofficial, community-maintained build of the .NET 11 runtime. It restores the SSE2 CPU baseline for x86 and x64 instead of requiring SSE4.1, SSE4.2, and POPCNT as part of the minimum supported instruction-set group.

The project is intended for:

- developers and runtime enthusiasts interested in supporting older computers;
- users who need to run .NET 11 applications on processors without SSE4.1, SSE4.2, or POPCNT;
- developers who want to publish self-contained, single-file, ReadyToRun, or NativeAOT applications for such computers.

This fork is not an official Microsoft product and is not supported by Microsoft or the .NET Foundation. It should be treated as an experimental compatibility project. Before deploying it in production, review the source changes, run the supplied tests, and evaluate security and servicing requirements for your environment.

## What is different

The upstream .NET 11 runtime raised its x86/x64 requirements and uses newer instruction-set baselines for several compilation modes. This fork changes the runtime, JIT, Crossgen2, and NativeAOT compiler so that:

- SSE and SSE2 are the unconditional x86/x64 baseline;
- SSE3, SSSE3, SSE4.1, SSE4.2, and POPCNT are optional;
- the JIT uses newer instructions when the complete required ISA group is available;
- software or SSE2 code-generation fallbacks are used when that group is unavailable;
- the default ReadyToRun baseline is SSE2 instead of `x86-64-v3`;
- NativeAOT applications can be compiled with `IlcInstructionSet=base` for an SSE2-compatible target.

AVX, AVX2, and newer instruction sets remain available on supported processors. Tiered JIT compilation can optimize hot methods for the actual CPU at runtime.

The current Windows x64 build has been tested with Intel SDE profiles and on an AMD Athlon II x4 system. The SSE2 baseline probe passed in both self-contained JIT single-file and NativeAOT configurations.

## Important limitations

- The instructions below describe the validated `win-x64` configuration.
- A target processor must support SSE2.
- Restoring CPU compatibility does not add support for operating systems that are unsupported by .NET 11.
- NativeAOT has no JIT fallback. Its instruction-set baseline must be compatible with the target CPU.
- ReadyToRun retains IL and can fall back to JIT compilation, but using an incompatible R2R baseline can substantially increase startup JIT work.
- Trimming can change application behavior when reflection, dynamic loading, serializers, COM interop, or dependency injection is used. Test trimmed applications carefully.
- Rebuild and republish applications whenever the custom runtime packages are rebuilt, even if they retain the same `11.0.0-sse2` version.

## Building the custom runtime

Install the normal prerequisites for building dotnet/runtime on Windows, including Visual Studio with the required C++ toolchain and Windows SDK.

From the repository root, run:

```cmd
build-local-runtime-sse2.cmd
```

The helper builds the Release x64 runtime, host, libraries, NativeAOT compiler, NativeAOT runtime pack, Crossgen2 pack, and ILLink package. It also installs `Microsoft.NETCore.App 11.0.0-sse2` into the repository-local `.dotnet` directory. This local installation is required to run framework-dependent build tools, such as ILLink, whose runtime configuration requests the same `sse2` prerelease version. It does not modify the system-wide .NET installation.

The local NuGet feed is created at:

```text
artifacts\packages\Release\Shipping
```

The examples below assume:

```text
Custom runtime repository: T:\Git\runtime-11-sse2-ox-alpha
Package version:           11.0.0-sse2
Runtime identifier:        win-x64
```

Replace the repository path if your checkout is elsewhere.

## Configuring an application project

The custom packages use the distinctive version `11.0.0-sse2`, produced with `VersionSuffix=sse2`. This suffix separates the fork's artifacts from packages produced by a regular dotnet/runtime checkout. A regular .NET 11 SDK may otherwise select its bundled official runtime version. Add the following items to the application project so that restore selects the custom CoreCLR, apphost, Crossgen2, NativeAOT compiler, NativeAOT runtime, and linker packs.

```xml
<PropertyGroup>
  <TargetFramework>net11.0</TargetFramework>
  <RuntimeIdentifier>win-x64</RuntimeIdentifier>
  <SelfContained>true</SelfContained>
</PropertyGroup>

<ItemGroup>
  <!-- Self-contained JIT and ReadyToRun -->
  <KnownFrameworkReference Update="Microsoft.NETCore.App">
    <DefaultRuntimeFrameworkVersion>11.0.0-sse2</DefaultRuntimeFrameworkVersion>
    <LatestRuntimeFrameworkVersion>11.0.0-sse2</LatestRuntimeFrameworkVersion>
  </KnownFrameworkReference>

  <KnownAppHostPack Update="Microsoft.NETCore.App">
    <AppHostPackVersion>11.0.0-sse2</AppHostPackVersion>
  </KnownAppHostPack>

  <!-- ReadyToRun -->
  <KnownCrossgen2Pack Update="Microsoft.NETCore.App.Crossgen2">
    <Crossgen2PackVersion>11.0.0-sse2</Crossgen2PackVersion>
  </KnownCrossgen2Pack>

  <!-- NativeAOT -->
  <KnownILCompilerPack Update="Microsoft.DotNet.ILCompiler">
    <ILCompilerPackVersion>11.0.0-sse2</ILCompilerPackVersion>
  </KnownILCompilerPack>

  <KnownRuntimePack Update="Microsoft.NETCore.App">
    <LatestRuntimeFrameworkVersion>11.0.0-sse2</LatestRuntimeFrameworkVersion>
  </KnownRuntimePack>

  <KnownILLinkPack Update="Microsoft.NET.ILLink.Tasks">
    <ILLinkPackVersion>11.0.0-sse2</ILLinkPackVersion>
  </KnownILLinkPack>
</ItemGroup>
```

It is safe to keep all these entries in a project that supports several publication modes. Alternatively, include only the entries required by the selected mode.

Use an isolated package cache for the custom runtime. Delete this cache before restoring after every runtime rebuild because local packages keep the same `11.0.0-sse2` version.

The following commands use the SDK bootstrapped in this repository:

```cmd
set "CUSTOM_RUNTIME=T:\Git\runtime-11-sse2-ox-alpha"
set "CUSTOM_FEED=%CUSTOM_RUNTIME%\artifacts\packages\Release\Shipping"
set "CUSTOM_PACKAGES=%CD%\.nuget-custom-runtime"
```

## Self-contained JIT publication

A self-contained publication carries the custom CoreCLR and JIT beside the application. The target computer does not need a separately installed .NET runtime.

Project properties:

```xml
<PropertyGroup>
  <PublishAot>false</PublishAot>
  <UseAppHost>true</UseAppHost>
</PropertyGroup>
```

Publish command:

```cmd
"%CUSTOM_RUNTIME%\.dotnet\dotnet.exe" publish MyApplication.csproj ^
  -c Release ^
  -r win-x64 ^
  --self-contained true ^
  --packages "%CUSTOM_PACKAGES%" ^
  -p:PublishAot=false ^
  -p:UseAppHost=true ^
  -p:RestoreAdditionalProjectSources="%CUSTOM_FEED%" ^
  -o publish-self-contained
```

Copy the entire `publish-self-contained` directory to the target computer. Verify that it contains at least `coreclr.dll`, `clrjit.dll`, and `System.Private.CoreLib.dll`.

## Self-contained trimmed single-file publication

This mode bundles the managed application and the custom native runtime into one executable. Native runtime files are extracted automatically when the application starts.

Project properties:

```xml
<PropertyGroup>
  <PublishAot>false</PublishAot>
  <UseAppHost>true</UseAppHost>
  <PublishSingleFile>true</PublishSingleFile>
  <PublishTrimmed>true</PublishTrimmed>
  <IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>
</PropertyGroup>
```

Publish command:

```cmd
"%CUSTOM_RUNTIME%\.dotnet\dotnet.exe" publish MyApplication.csproj ^
  -c Release ^
  -r win-x64 ^
  --self-contained true ^
  --packages "%CUSTOM_PACKAGES%" ^
  -p:PublishAot=false ^
  -p:UseAppHost=true ^
  -p:PublishSingleFile=true ^
  -p:PublishTrimmed=true ^
  -p:IncludeNativeLibrariesForSelfExtract=true ^
  -p:RestoreAdditionalProjectSources="%CUSTOM_FEED%" ^
  -o publish-single-file
```

Copy the generated executable to the target computer. If the application uses reflection or dynamic code, review all trimming warnings and add the appropriate annotations or linker configuration.

## ReadyToRun publication

ReadyToRun uses Crossgen2 to place precompiled native code in managed assemblies while retaining IL for JIT fallback. This fork changes the default x86/x64 R2R baseline from `x86-64-v3` to SSE2.

For an old target computer, publish ReadyToRun as self-contained so that the application also carries this custom CoreCLR and JIT.

Project properties:

```xml
<PropertyGroup>
  <PublishAot>false</PublishAot>
  <PublishReadyToRun>true</PublishReadyToRun>
  <PublishReadyToRunComposite>true</PublishReadyToRunComposite>
</PropertyGroup>
```

Publish command:

```cmd
"%CUSTOM_RUNTIME%\.dotnet\dotnet.exe" publish MyApplication.csproj ^
  -c Release ^
  -r win-x64 ^
  --self-contained true ^
  --packages "%CUSTOM_PACKAGES%" ^
  -p:PublishAot=false ^
  -p:PublishReadyToRun=true ^
  -p:PublishReadyToRunComposite=true ^
  -p:RestoreAdditionalProjectSources="%CUSTOM_FEED%" ^
  -o publish-r2r
```

`PublishReadyToRunComposite=true` is optional. Composite images can improve optimization and startup at the cost of a slower publication and a larger unit of recompilation. The custom Crossgen2 compiler uses SSE2 as its default baseline; newer ISA-dependent R2R code is guarded by runtime instruction-set checks.

Copy the entire `publish-r2r` directory to the target computer.

## NativeAOT publication

NativeAOT produces a native executable and does not ship a JIT fallback. Always specify the SSE2 baseline explicitly.

Project properties:

```xml
<PropertyGroup>
  <PublishAot>true</PublishAot>
  <IlcInstructionSet>base</IlcInstructionSet>
  <InvariantGlobalization>true</InvariantGlobalization>
</PropertyGroup>
```

`InvariantGlobalization` is optional. Remove it if the application requires full culture data and ensure the required globalization dependencies are available on the target system.

Publish command:

```cmd
"%CUSTOM_RUNTIME%\.dotnet\dotnet.exe" publish MyApplication.csproj ^
  -c Release ^
  -r win-x64 ^
  --self-contained true ^
  --packages "%CUSTOM_PACKAGES%" ^
  -p:PublishAot=true ^
  -p:ILCompilerVersion=11.0.0-sse2 ^
  -p:IlcInstructionSet=base ^
  -p:RestoreAdditionalProjectSources="%CUSTOM_FEED%" ^
  -o publish-nativeaot
```

Only the files in `publish-nativeaot` are required on the target computer. NativeAOT applications must be tested carefully because unsupported reflection, dynamic loading, and runtime code generation cannot fall back to the JIT.

## Verifying that the custom runtime was used

Do not rely only on a successful build. Check the restore output or `obj\project.assets.json` and confirm that these packages resolve to `11.0.0-sse2` from the local feed:

- `Microsoft.NETCore.App.Runtime.win-x64` for self-contained JIT and ReadyToRun;
- `Microsoft.NETCore.App.Host.win-x64` for the apphost;
- `Microsoft.NETCore.App.Crossgen2.win-x64` for ReadyToRun;
- `Microsoft.DotNet.ILCompiler` and `runtime.win-x64.Microsoft.DotNet.ILCompiler` for NativeAOT;
- `Microsoft.NETCore.App.Runtime.NativeAOT.win-x64` for NativeAOT;
- `Microsoft.NET.ILLink.Tasks` for trimmed and NativeAOT publications.

For a non-single-file self-contained application, compare the published `clrjit.dll` with the copy in the restored local runtime package. They should be byte-for-byte identical.

## Compatibility tests

The repository includes an SSE2 baseline probe at:

```text
src\tests\JIT\HardwareIntrinsics\X86\Sse2BaselineProbe
```

Useful commands in that directory include:

```cmd
publish-local-self-contained.cmd
publish-local-single-file.cmd
publish-local-aot.cmd
run-sde-single-file.cmd
run-sde-aot.cmd
run-sde-matrix.cmd
```

The probe compares vector and scalar results and exits with code `100` on success. Test on Intel SDE first, then on the real target processor. A successful SDE run is valuable but does not replace real-hardware validation.

## Updating this fork

This fork is intended to track the upstream .NET 11 release branch. When rebasing onto a newer upstream commit:

1. review all conflicts in JIT, hardware-intrinsic, Crossgen2, NativeAOT, and CPU-feature detection files;
2. search for new uses of the upstream SSE4.2 or `x86-64-v3` baseline;
3. rebuild all runtime and compiler packages;
4. clear isolated NuGet caches;
5. republish and run the JIT, ReadyToRun, and NativeAOT tests under SDE and on real older hardware.

## License and support

The source code remains subject to the licenses included in the dotnet/runtime repository. The modifications in this fork do not imply endorsement or support by Microsoft or the .NET Foundation.

Use this runtime at your own risk. Report fork-specific issues to the maintainer of this repository rather than to the official .NET support channels unless the issue is reproducible with an official .NET build.
