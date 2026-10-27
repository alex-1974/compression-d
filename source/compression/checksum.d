/// Allocation-free incremental Adler-32 and IEEE CRC-32 checksums.
module compression.checksum;

struct Adler32
{
    private uint a = 1, b;
    @safe pure nothrow @nogc:
    void reset() { this = Adler32.init; }
    void updateByte(ubyte value)
    {
        a += value;
        if (a >= 65521) a -= 65521;
        b += a;
        if (b >= 65521) b -= 65521;
    }
    void update(scope const(ubyte)[] bytes)
    {
        foreach (value; bytes) updateByte(value);
    }
    @property uint value() const { return (b << 16) | a; }
}

private uint[256] makeCrcTable() @safe pure nothrow @nogc
{
    uint[256] result;
    foreach (uint index; 0 .. 256)
    {
        uint crc = index;
        foreach (bit; 0 .. 8)
            crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xEDB88320U : 0);
        result[index] = crc;
    }
    return result;
}
private immutable uint[256] crcTable = makeCrcTable();

struct Crc32
{
    private uint crc = uint.max;
    @safe pure nothrow @nogc:
    void reset() { this = Crc32.init; }
    void updateByte(ubyte value) { crc = (crc >> 8) ^ crcTable[(crc ^ value) & 255]; }
    void update(scope const(ubyte)[] bytes) { foreach (value; bytes) updateByte(value); }
    @property uint value() const { return crc ^ uint.max; }
}

uint adler32(scope const(ubyte)[] bytes) @safe pure nothrow @nogc
{
    Adler32 state;
    state.update(bytes);
    return state.value;
}

uint crc32(scope const(ubyte)[] bytes) @safe pure nothrow @nogc
{
    Crc32 state;
    state.update(bytes);
    return state.value;
}

@safe pure nothrow @nogc unittest
{
    assert(adler32(null) == 1 && crc32(null) == 0);
    immutable ubyte[9] digits = ['1','2','3','4','5','6','7','8','9'];
    assert(adler32(digits) == 0x091E01DE && crc32(digits) == 0xCBF43926);
    foreach (split; 0 .. digits.length + 1)
    {
        Adler32 a; Crc32 c;
        a.update(digits[0 .. split]); c.update(digits[0 .. split]);
        a.update(digits[split .. $]); c.update(digits[split .. $]);
        assert(a.value == adler32(digits) && c.value == crc32(digits));
        a.reset(); c.reset();
        assert(a.value == 1 && c.value == 0);
    }
    // Slow independent modulo/bitwise oracles, including repeated reductions.
    Adler32 a; Crc32 c;
    ulong sumA = 1, sumB;
    uint reference = uint.max;
    foreach (uint i; 0 .. 200_000)
    {
        const byteValue = cast(ubyte)(i * 17);
        a.updateByte(byteValue); c.updateByte(byteValue);
        sumA = (sumA + byteValue) % 65521;
        sumB = (sumB + sumA) % 65521;
        reference ^= byteValue;
        foreach (bit; 0 .. 8)
            reference = (reference >> 1) ^ ((reference & 1) != 0 ? 0xEDB88320U : 0);
    }
    assert(a.value == ((sumB << 16) | sumA));
    assert(c.value == (reference ^ uint.max));
}
