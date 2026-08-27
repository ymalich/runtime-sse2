# SSE2 baseline probe

This console application validates the generic `Vector128` paths affected by restoring the x86/x64 baseline to SSE2.
Every operation is compared with a scalar expected result. Success exits with the conventional runtime-test code `100`.

For NativeAOT, publish against the locally produced runtime packages and pass the resulting executable:

```cmd
publish-local-aot.cmd
run-sde-aot.cmd T:\SDE\sde.exe publish\Sse2BaselineProbe.exe p4p
```

`publish-local-aot.cmd` uses the checkout's `Release\Shipping` feed, an isolated NuGet cache under
`artifacts\sse2-baseline-probe`, and `IlcInstructionSet=base`.

To publish a self-contained JIT application with this checkout's custom CoreCLR and JIT:

```cmd
publish-local-self-contained.cmd
publish-self-contained\Sse2BaselineProbe.exe
```

Copy the entire `publish-self-contained` directory to the target machine, not only the executable.
The script pins `Microsoft.NETCore.App.Runtime.win-x64` to the locally built `11.0.0-sse2` package and
verifies that `coreclr.dll`, `clrjit.dll`, and `System.Private.CoreLib.dll` are present in the result.

To bundle the custom JIT runtime into one trimmed executable:

```cmd
publish-local-single-file.cmd
publish-single-file\Sse2BaselineProbe.exe
```

The single-file script sets `PublishSingleFile=true`, `PublishTrimmed=true`, and
`IncludeNativeLibrariesForSelfExtract=true`. The last option embeds native runtime libraries such as
`coreclr.dll` and `clrjit.dll`; they are extracted automatically when the application starts.

Run the single-file JIT application under SDE with:

```cmd
run-sde-single-file.cmd
```

This is the supported SDE test for the custom JIT.

The third argument of the individual SDE scripts is the CPU model. `p4p` is the oldest SDE profile that
can run an x64 process and exposes only the SSE/SSE2 baseline used by this test.

To cover every relevant boundary in one run, use the matrix wrapper. It runs `p4p` (forced SSE2 JIT),
`mrm` (SSSE3), `pnr` (SSE4.1), and `nhm` (SSE4.2 plus POPCNT):

```cmd
run-sde-matrix.cmd
run-sde-matrix.cmd single-file
run-sde-matrix.cmd aot publish\Sse2BaselineProbe.exe
```

The first three profiles must use the SSE2 fallback paths. `nhm` verifies that the optimized SSE4.2 group remains enabled.
For NativeAOT, `p4p` can reject SSSE3/SSE4 instructions but cannot reject SSE3 instructions; the final SSE2-only
validation therefore remains a run on a real SSE2-only x64 processor such as the target Athlon II.

## Real-hardware validation

The following locally built applications have passed on an AMD E-450 system:

- the trimmed single-file JIT `Sse2BaselineProbe.exe`;
- the NativeAOT `Sse2BaselineProbe.exe`;

This verifies both the custom JIT and NativeAOT fallback paths on real AMD hardware in addition to the SDE runs.
