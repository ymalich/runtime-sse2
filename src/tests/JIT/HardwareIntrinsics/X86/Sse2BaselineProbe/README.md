# SSE2 baseline probe

This console application validates the generic `Vector128` paths affected by restoring the x86/x64 baseline to SSE2.
Every operation is compared with a scalar expected result. Success exits with the conventional runtime-test code `100`.

Build the managed probe, then run it with the freshly built `corerun`:

```cmd
dotnet build Sse2BaselineProbe.csproj -c Release
run-sde-jit.cmd T:\SDE\sde.exe T:\Git\runtime-11-sse2-ox-alpha\artifacts\sse2-baseline-probe\core_root\corerun.exe bin\Release\net11.0\Sse2BaselineProbe.dll p4p
```

For NativeAOT, publish against the locally produced runtime packages and pass the resulting executable:

```cmd
publish-local-aot.cmd
run-sde-aot.cmd T:\SDE\sde.exe publish\Sse2BaselineProbe.exe p4p
```

`publish-local-aot.cmd` uses the checkout's `Release\Shipping` feed, an isolated NuGet cache under
`artifacts\sse2-baseline-probe`, and `IlcInstructionSet=base`.

The fourth/third argument is the SDE CPU model. `p4p` is the oldest SDE profile that can run an x64 process.
For JIT runs the script additionally sets `COMPlus_EnableSSE42=0`, disabling the combined
SSE3/SSSE3/SSE4.x/POPCNT group and forcing the new SSE2 fallback paths.
Use a complete `Core_Root` test host: the product `artifacts\bin\coreclr` directory does not contain
framework assemblies such as `System.Runtime.dll` and cannot run this managed probe by itself.

To cover every relevant boundary in one run, use the matrix wrapper. It runs `p4p` (forced SSE2 JIT),
`mrm` (SSSE3), `pnr` (SSE4.1), and `nhm` (SSE4.2 plus POPCNT):

```cmd
run-sde-matrix.cmd jit
run-sde-matrix.cmd aot publish\Sse2BaselineProbe.exe
```

The first three profiles must use the SSE2 fallback paths. `nhm` verifies that the optimized SSE4.2 group remains enabled.
For NativeAOT, `p4p` can reject SSSE3/SSE4 instructions but cannot reject SSE3 instructions; the final SSE2-only
validation therefore remains a run on a real SSE2-only x64 processor such as the target Athlon II.
