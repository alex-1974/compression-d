// Synthetic symbol-lookup benchmark, NOT an Inflate/throughput benchmark.
module huffman_benchmark;

import compression.bitstream;
import compression.core;
import compression.huffman;
import core.time : MonoTime;
import std.conv : to;
import std.stdio : writefln;

enum symbolCount = 65_536;

// Prevent whole-loop folding/hoisting across repetitions. Data and iteration
// count originate at runtime; each decoded symbol contributes to printed output.
pragma(inline, false)
ulong decodePass(uint rootBits)(ref const HuffmanTable!rootBits table,
    scope const(ubyte)[] data, ulong checksum) @safe pure nothrow @nogc
{
    BitReader reader;
    size_t cursor;
    foreach (index; 0 .. symbolCount)
    {
        const decoded = table.decode(reader, data, cursor, true);
        assert(decoded.status == DecodeStatus.done);
        checksum = checksum * 33 + decoded.symbol;
    }
    assert(cursor == data.length);
    return checksum;
}

pragma(inline, false)
ErrorCode buildPass(uint rootBits)(ref HuffmanTable!rootBits table,
    scope const(ubyte)[] lengths) @safe pure nothrow @nogc
{
    return table.build(lengths);
}

void measure(uint rootBits)(string corpus, const(ubyte)[] lengths,
    const(ubyte)[] encoded, uint passes, ulong expected)
{
    HuffmanTable!rootBits table;
    assert(table.build(lengths) == ErrorCode.none);
    decodePass(table, encoded, 0); // warm-up
    const start = MonoTime.currTime;
    ulong checksum;
    foreach (pass; 0 .. passes)
        checksum = decodePass(table, encoded, checksum);
    const seconds = (MonoTime.currTime - start).total!"nsecs" / 1e9;
    assert(checksum == expected);
    const buildStart = MonoTime.currTime;
    uint builds;
    foreach (iteration; 0 .. passes * 100)
        builds += buildPass(table, lengths) == ErrorCode.none;
    const buildSeconds = (MonoTime.currTime - buildStart).total!"nsecs" / 1e9;
    assert(builds == passes * 100);
    writefln("%s root=%s workspace=%s bytes decode=%.2f Msymbol/s build=%.1f us checksum=%s builds=%s",
        corpus, rootBits, table.sizeof, symbolCount * cast(double) passes / seconds / 1e6,
        buildSeconds * 1e6 / builds, checksum, builds);
}

void main(string[] args)
{
    const passes = args.length > 1 ? to!uint(args[1]) : 20;
    uint seed = args.length > 2 ? to!uint(args[2]) : 12345;
    assert(passes > 0 && passes <= 10_000);
    writefln("passes=%s symbols/pass=%s seed=%s", passes, symbolCount, seed);
    foreach (deep; [false, true])
    {
        ubyte[] lengths = new ubyte[deep ? 16 : 288];
        foreach (symbol, ref length; lengths)
            length = cast(ubyte)(deep ? (symbol < 15 ? symbol + 1 : 15) :
                symbol < 144 ? 8 : symbol < 256 ? 9 : symbol < 280 ? 7 : 8);
        auto data = new ubyte[symbolCount * 2];
        auto sequence = new ushort[symbolCount];
        size_t bitPosition;
        foreach (ref symbol; sequence)
        {
            seed = seed * 1664525 + 1013904223;
            symbol = cast(ushort)((seed >> 16) % lengths.length);
            const width = lengths[symbol];
            const code = deep ? (symbol == 15 ? 32767 : (1U << width) - 2) :
                symbol < 144 ? symbol + 48 : symbol < 256 ? symbol + 256 :
                symbol < 280 ? symbol - 256 : symbol - 88;
            foreach_reverse (uint bit; 0 .. width)
            {
                data[bitPosition / 8] |= ((code >> bit) & 1) << (bitPosition % 8);
                ++bitPosition;
            }
        }
        data = data[0 .. (bitPosition + 7) / 8];
        ulong expected;
        foreach (pass; 0 .. passes)
        foreach (symbol; sequence)
            expected = expected * 33 + symbol;
        const name = deep ? "deep-15" : "fixed";
        measure!0(name, lengths, data, passes, expected);
        measure!9(name, lengths, data, passes, expected);
    }
}
