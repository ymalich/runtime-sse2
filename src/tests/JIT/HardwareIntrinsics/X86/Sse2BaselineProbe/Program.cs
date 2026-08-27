using System;
using System.Numerics;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Runtime.Intrinsics;
using System.Runtime.Intrinsics.X86;

internal static class Program
{
    private static volatile int s_seed = 7;
    private static int s_checks;

    private static int Main(string[] args)
    {
        if (args.Length != 0 && int.TryParse(args[0], out int seed))
            s_seed = seed;

        Console.WriteLine($"Process: {Environment.ProcessPath}");
        Console.WriteLine($"OS: {Environment.OSVersion}; 64-bit={Environment.Is64BitProcess}");
        Console.WriteLine($"Vector128.IsHardwareAccelerated={Vector128.IsHardwareAccelerated}");
        Console.WriteLine($"Sse={Sse.IsSupported}, Sse2={Sse2.IsSupported}, Sse3={Sse3.IsSupported}, " +
                          $"Ssse3={Ssse3.IsSupported}, Sse41={Sse41.IsSupported}, Sse42={Sse42.IsSupported}, " +
                          $"Popcnt={Popcnt.IsSupported}, Avx={Avx.IsSupported}, Avx2={Avx2.IsSupported}");

        try
        {
            Run(nameof(TestAbsAndMinMax), TestAbsAndMinMax);
            Run(nameof(TestComparisons), TestComparisons);
            Run(nameof(TestDot), TestDot);
            Run(nameof(TestRounding), TestRounding);
            Run(nameof(TestGetAndWithElement), TestGetAndWithElement);
            Run(nameof(TestShuffle), TestShuffle);
            Run(nameof(TestWidenAndNarrow), TestWidenAndNarrow);
            Run(nameof(TestExtractMostSignificantBits), TestExtractMostSignificantBits);
            Run(nameof(TestConversionsAndMemory), TestConversionsAndMemory);
            Run(nameof(TestPopCount), TestPopCount);
            Run(nameof(TestVector3), TestVector3);

            Console.WriteLine($"PASS: {s_checks} checks");
            return 100;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("FAIL: " + ex);
            return 1;
        }
    }

    private static void Run(string name, Action test)
    {
        Console.WriteLine($"RUN: {name}");
        test();
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestAbsAndMinMax()
    {
        TestAbsInt();
        TestAbsSByte();
        TestMinMaxSByte();
        TestMinMaxByte();
        TestMinMaxUShort();
        TestMinMaxInt();
        TestMinMaxUInt();
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestAbsInt()
    {
        int x = s_seed;
        Vector128<int> ints = Vector128.Create(-x, -1234567, 42, int.MinValue + 1);
        AssertVector(Vector128.Abs(ints), new[] { Math.Abs(-x), 1234567, 42, int.MaxValue }, "Abs<int>");
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestAbsSByte()
    {
        Vector128<sbyte> signedBytes = Vector128.Create((sbyte)-7, (sbyte)3, (sbyte)-100, (sbyte)99,
            (sbyte)-1, (sbyte)2, (sbyte)-3, (sbyte)4, (sbyte)-5, (sbyte)6, (sbyte)-7, (sbyte)8,
            (sbyte)-9, (sbyte)10, (sbyte)-11, (sbyte)12);
        Vector128<sbyte> absBytes = Vector128.Abs(signedBytes);
        for (int i = 0; i < Vector128<sbyte>.Count; i++)
            Equal((sbyte)Math.Abs(signedBytes.GetElement(i)), absBytes.GetElement(i), $"Abs<sbyte>[{i}]");
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestMinMaxSByte()
    {
        Vector128<sbyte> signedBytes = Vector128.Create((sbyte)-7, (sbyte)3, (sbyte)-100, (sbyte)99,
            (sbyte)-1, (sbyte)2, (sbyte)-3, (sbyte)4, (sbyte)-5, (sbyte)6, (sbyte)-7, (sbyte)8,
            (sbyte)-9, (sbyte)10, (sbyte)-11, (sbyte)12);
        Vector128<sbyte> signedBytes2 = Vector128.Create((sbyte)-8, (sbyte)2, (sbyte)-99, (sbyte)100,
            (sbyte)-2, (sbyte)3, (sbyte)-4, (sbyte)5, (sbyte)-6, (sbyte)7, (sbyte)-8, (sbyte)9,
            (sbyte)-10, (sbyte)11, (sbyte)-12, (sbyte)13);
        AssertMinMax(signedBytes, signedBytes2, "sbyte");
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestMinMaxByte()
    {
        Vector128<byte> b1 = Vector128.Create((byte)1, 220, 3, 240, 5, 200, 7, 180, 9, 160, 11, 140, 13, 120, 15, 100);
        Vector128<byte> b2 = Vector128.Create((byte)2, 210, 4, 230, 6, 190, 8, 170, 10, 150, 12, 130, 14, 110, 16, 90);
        AssertMinMax(b1, b2, "byte");
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestMinMaxUShort()
    {
        Vector128<ushort> u1 = Vector128.Create((ushort)1, 60000, 3, 50000, 5, 40000, 7, 30000);
        Vector128<ushort> u2 = Vector128.Create((ushort)2, 59000, 4, 49000, 6, 39000, 8, 29000);
        AssertMinMax(u1, u2, "ushort");
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestMinMaxInt()
    {
        int x = s_seed;
        Vector128<int> i1 = Vector128.Create(int.MinValue + x, 100, -200, int.MaxValue - 3);
        Vector128<int> i2 = Vector128.Create(-1, 200, -300, int.MaxValue - 2);
        AssertMinMax(i1, i2, "int");
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestMinMaxUInt()
    {
        Vector128<uint> ui1 = Vector128.Create(0U, uint.MaxValue, 17U, 0x8000_0000U);
        Vector128<uint> ui2 = Vector128.Create(1U, uint.MaxValue - 1, 16U, 0x7FFF_FFFFU);
        AssertMinMax(ui1, ui2, "uint");
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestComparisons()
    {
        TestEqualsLong();
        TestGreaterThanLong();
        TestLessThanLong();
        TestLessThanULong();
        TestGreaterThanULong();
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestEqualsLong()
    {
        long x = s_seed;
        Vector128<long> a = Vector128.Create(long.MinValue + x, long.MaxValue - x);
        Vector128<long> b = Vector128.Create(long.MinValue + x, long.MaxValue - x - 1);
        Console.WriteLine("  Equals<long>");
        AssertMask(Vector128.Equals(a, b), new[] { true, false }, "Equals<long>");
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestGreaterThanLong()
    {
        long x = s_seed;
        Vector128<long> a = Vector128.Create(long.MinValue + x, long.MaxValue - x);
        Vector128<long> b = Vector128.Create(long.MinValue + x, long.MaxValue - x - 1);
        Console.WriteLine("  GreaterThan<long>");
        AssertMask(Vector128.GreaterThan(a, b), new[] { false, true }, "GreaterThan<long>");
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestLessThanLong()
    {
        long x = s_seed;
        Vector128<long> a = Vector128.Create(long.MinValue + x, long.MaxValue - x);
        Vector128<long> b = Vector128.Create(long.MinValue + x, long.MaxValue - x - 1);
        Console.WriteLine("  LessThan<long>");
        AssertMask(Vector128.LessThan(b, a), new[] { false, true }, "LessThan<long>");
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestLessThanULong()
    {
        long x = s_seed;
        Vector128<ulong> ua = Vector128.Create(0UL, ulong.MaxValue - (ulong)x);
        Vector128<ulong> ub = Vector128.Create(1UL, (ulong)x);
        Console.WriteLine("  LessThan<ulong>");
        AssertMask(Vector128.LessThan(ua, ub), new[] { true, false }, "LessThan<ulong>");
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestGreaterThanULong()
    {
        long x = s_seed;
        Vector128<ulong> ua = Vector128.Create(0UL, ulong.MaxValue - (ulong)x);
        Vector128<ulong> ub = Vector128.Create(1UL, (ulong)x);
        Console.WriteLine("  GreaterThan<ulong>");
        AssertMask(Vector128.GreaterThan(ua, ub), new[] { false, true }, "GreaterThan<ulong>");
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestDot()
    {
        TestDotInt();
        TestDotFloat();
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestDotInt()
    {
        Console.WriteLine("  Dot<int>");
        Vector128<int> ia = Vector128.Create(s_seed, 2, -3, 4);
        Vector128<int> ib = Vector128.Create(5, -6, 7, 8);
        Equal(ia.GetElement(0) * ib.GetElement(0) + ia.GetElement(1) * ib.GetElement(1) +
              ia.GetElement(2) * ib.GetElement(2) + ia.GetElement(3) * ib.GetElement(3),
              Vector128.Dot(ia, ib), "Dot<int>");
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestDotFloat()
    {
        Console.WriteLine("  Dot<float>");
        Vector128<float> fa = Vector128.Create((float)s_seed, 2.5f, -3.25f, 4.75f);
        Vector128<float> fb = Vector128.Create(5.5f, -6.0f, 7.25f, 8.0f);
        float expected = 0;
        for (int i = 0; i < 4; i++) expected += fa.GetElement(i) * fb.GetElement(i);
        NearlyEqual(expected, Vector128.Dot(fa, fb), "Dot<float>");
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestRounding()
    {
        Vector128<float> v = Vector128.Create(-3.75f, -0.25f, 1.5f, 123.875f + s_seed);
        AssertVector(Vector128.Floor(v), Map(v, MathF.Floor), "Floor<float>");
        AssertVector(Vector128.Ceiling(v), Map(v, MathF.Ceiling), "Ceiling<float>");
        AssertVector(Vector128.Truncate(v), Map(v, MathF.Truncate), "Truncate<float>");
        AssertVector(Vector128.Round(v), Map(v, MathF.Round), "Round<float>");
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestGetAndWithElement()
    {
        int index = (s_seed & 1) + 1;
        Vector128<int> ints = Vector128.Create(10, 20, 30, 40);
        Equal((index + 1) * 10, ints.GetElement(index), "GetElement<int>");
        AssertVector(ints.WithElement(index, 777), index == 1 ? new[] { 10, 777, 30, 40 } : new[] { 10, 20, 777, 40 }, "WithElement<int>");

        Vector128<byte> bytes = Vector128.Create((byte)0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15);
        Equal((byte)9, bytes.GetElement(9), "GetElement<byte>");
        Equal((byte)222, bytes.WithElement(9, (byte)222).GetElement(9), "WithElement<byte>");

        Vector128<short> shorts = Vector128.Create((short)1, 2, 3, 4, 5, 6, 7, 8);
        Equal((short)444, shorts.WithElement(3, (short)444).GetElement(3), "WithElement<short>");

        Vector128<float> floats = Vector128.Create(1f, 2f, 3f, 4f);
        NearlyEqual(3f, floats.GetElement(2), "GetElement<float>");
        NearlyEqual(99.5f, floats.WithElement(2, 99.5f).GetElement(2), "WithElement<float>");

        Vector128<double> doubles = Vector128.Create(1.25, 2.5);
        Equal(7.75, doubles.WithElement(1, 7.75).GetElement(1), "WithElement<double>");

        Vector128<long> longs = Vector128.Create(11L, 22L);
        Equal(22L, longs.GetElement(1), "GetElement<long>");
        Equal(999L, longs.WithElement(1, 999L).GetElement(1), "WithElement<long>");
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestShuffle()
    {
        Vector128<int> values = Vector128.Create(10 + s_seed, 20, 30, 40);
        Vector128<int> indices = Vector128.Create(3, 1, 0, 2);
        AssertVector(Vector128.Shuffle(values, indices), new[] { 40, 20, 10 + s_seed, 30 }, "Shuffle<int>");

        int dynamicIndex = s_seed & 3;
        Vector128<int> dynamicIndices = Vector128.Create(dynamicIndex, 3 - dynamicIndex, 1, 2);
        Vector128<int> dynamicResult = Vector128.Shuffle(values, dynamicIndices);
        for (int i = 0; i < 4; i++)
            Equal(values.GetElement(dynamicIndices.GetElement(i)), dynamicResult.GetElement(i), $"Shuffle<int,dynamic>[{i}]");

        Vector128<byte> bytes = Vector128.Create((byte)0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15);
        Vector128<byte> reverse = Vector128.Create((byte)15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0);
        Vector128<byte> shuffled = Vector128.Shuffle(bytes, reverse);
        for (int i = 0; i < 16; i++) Equal((byte)(15 - i), shuffled.GetElement(i), $"Shuffle<byte>[{i}]");
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestWidenAndNarrow()
    {
        Vector128<byte> bytes = Vector128.Create((byte)1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
        Vector128<ushort> low = Vector128.WidenLower(bytes);
        Vector128<ushort> high = Vector128.WidenUpper(bytes);
        for (int i = 0; i < 8; i++)
        {
            Equal((ushort)(i + 1), low.GetElement(i), $"WidenLower<byte>[{i}]");
            Equal((ushort)(i + 9), high.GetElement(i), $"WidenUpper<byte>[{i}]");
        }

        Vector128<byte> narrowed = Vector128.Narrow(low, high);
        for (int i = 0; i < 16; i++) Equal((byte)(i + 1), narrowed.GetElement(i), $"Narrow<ushort>[{i}]");

        Vector128<int> signed = Vector128.Create(int.MinValue + s_seed, -1, 0, int.MaxValue);
        Vector128<long> signedLow = Vector128.WidenLower(signed);
        Vector128<long> signedHigh = Vector128.WidenUpper(signed);
        Equal((long)signed.GetElement(0), signedLow.GetElement(0), "WidenLower<int>[0]");
        Equal((long)signed.GetElement(1), signedLow.GetElement(1), "WidenLower<int>[1]");
        Equal((long)signed.GetElement(2), signedHigh.GetElement(0), "WidenUpper<int>[0]");
        Equal((long)signed.GetElement(3), signedHigh.GetElement(1), "WidenUpper<int>[1]");

        Vector128<uint> unsigned = Vector128.Create(0U, 0x7FFF_FFFFU, 0x8000_0000U, uint.MaxValue);
        Vector128<ulong> unsignedLow = Vector128.WidenLower(unsigned);
        Vector128<ulong> unsignedHigh = Vector128.WidenUpper(unsigned);
        Equal((ulong)unsigned.GetElement(0), unsignedLow.GetElement(0), "WidenLower<uint>[0]");
        Equal((ulong)unsigned.GetElement(1), unsignedLow.GetElement(1), "WidenLower<uint>[1]");
        Equal((ulong)unsigned.GetElement(2), unsignedHigh.GetElement(0), "WidenUpper<uint>[0]");
        Equal((ulong)unsigned.GetElement(3), unsignedHigh.GetElement(1), "WidenUpper<uint>[1]");

        Vector128<uint> narrowLower = Vector128.Create(1U, 65535U, 17U, 32768U);
        Vector128<uint> narrowUpper = Vector128.Create(2U, 60000U, 19U, 40000U);
        Vector128<ushort> narrowUnsigned = Vector128.Narrow(narrowLower, narrowUpper);
        AssertVector(narrowUnsigned, new ushort[] { 1, 65535, 17, 32768, 2, 60000, 19, 40000 }, "Narrow<uint>");
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestExtractMostSignificantBits()
    {
        Vector128<short> v = Vector128.Create((short)-1, 2, -3, 4, -5, 6, -7, 8);
        Equal(0b0101_0101u, Vector128.ExtractMostSignificantBits(v), "ExtractMostSignificantBits<short>");
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static unsafe void TestConversionsAndMemory()
    {
        Vector128<float> source = Vector128.Create(1.4f + s_seed, -2.6f, 3.5f, -4.5f);
        Vector128<int> converted = Vector128.ConvertToInt32(source);
        for (int i = 0; i < 4; i++)
            Equal((int)MathF.Truncate(source.GetElement(i)), converted.GetElement(i), $"ConvertToInt32[{i}]");

        int* memory = (int*)NativeMemory.AlignedAlloc(16, 16);
        if (memory == null) throw new OutOfMemoryException();
        try
        {
            for (int i = 0; i < 4; i++) memory[i] = s_seed + (i * 11);
            Vector128<int> loaded = Vector128.LoadAlignedNonTemporal(memory);
            for (int i = 0; i < 4; i++) Equal(memory[i], loaded.GetElement(i), $"LoadAlignedNonTemporal[{i}]");
        }
        finally
        {
            NativeMemory.AlignedFree(memory);
        }
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestPopCount()
    {
        uint value = 0xA5A5_0000U ^ (uint)s_seed;
        int expected = 0;
        for (uint bits = value; bits != 0; bits >>= 1) expected += (int)(bits & 1);
        Equal(expected, BitOperations.PopCount(value), "BitOperations.PopCount");
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void TestVector3()
    {
        Vector3 a = new(s_seed, 2.5f, -3.0f);
        Vector3 b = new(4.0f, -5.0f, 6.0f);
        Vector3 c = a + b;
        NearlyEqual(s_seed + 4.0f, c.X, "Vector3.X");
        NearlyEqual(-2.5f, c.Y, "Vector3.Y");
        NearlyEqual(3.0f, c.Z, "Vector3.Z");
        NearlyEqual(a.X * b.X + a.Y * b.Y + a.Z * b.Z, Vector3.Dot(a, b), "Vector3.Dot");
    }

    private static float[] Map(Vector128<float> vector, Func<float, float> map)
    {
        float[] result = new float[4];
        for (int i = 0; i < result.Length; i++) result[i] = map(vector.GetElement(i));
        return result;
    }

    private static void AssertMinMax<T>(Vector128<T> a, Vector128<T> b, string name) where T : unmanaged, INumber<T>
    {
        Vector128<T> min = Vector128.Min(a, b);
        Vector128<T> max = Vector128.Max(a, b);
        for (int i = 0; i < Vector128<T>.Count; i++)
        {
            Equal(T.Min(a.GetElement(i), b.GetElement(i)), min.GetElement(i), $"Min<{name}>[{i}]");
            Equal(T.Max(a.GetElement(i), b.GetElement(i)), max.GetElement(i), $"Max<{name}>[{i}]");
        }
    }

    private static void AssertMask<T>(Vector128<T> actual, bool[] expected, string name) where T : unmanaged, IBinaryInteger<T>
    {
        for (int i = 0; i < expected.Length; i++)
            Equal(expected[i] ? T.AllBitsSet : T.Zero, actual.GetElement(i), $"{name}[{i}]");
    }

    private static void AssertVector<T>(Vector128<T> actual, T[] expected, string name) where T : unmanaged, IEquatable<T>
    {
        for (int i = 0; i < expected.Length; i++) Equal(expected[i], actual.GetElement(i), $"{name}[{i}]");
    }

    private static void NearlyEqual(float expected, float actual, string name)
    {
        s_checks++;
        float tolerance = MathF.Max(1e-5f, MathF.Abs(expected) * 1e-5f);
        if (MathF.Abs(expected - actual) > tolerance) throw new InvalidOperationException($"{name}: expected {expected}, actual {actual}");
    }

    private static void Equal<T>(T expected, T actual, string name) where T : IEquatable<T>
    {
        s_checks++;
        if (!expected.Equals(actual)) throw new InvalidOperationException($"{name}: expected {expected}, actual {actual}");
    }
}
