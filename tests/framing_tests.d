module framing_tests;
import compression.core;
import compression.checksum;
import compression.deflate;
import compression.zlib;
import compression.gzip;
import framing_fixtures;
import std.algorithm : min;

private ubyte[] unhex(string text) @safe
{
    auto data = new ubyte[text.length / 2];
    foreach (i, ref value; data)
    {
        uint number;
        foreach (digit; text[i * 2 .. i * 2 + 2])
            number = number * 16 + (digit <= '9' ? digit - '0' : digit - 'a' + 10);
        value = cast(ubyte) number;
    }
    return data;
}

private ubyte[] plaintext(uint pattern, size_t length) @safe
{
    auto data = new ubyte[length];
    foreach (i, ref value; data)
    {
        switch (pattern)
        {
        case 0: value = 0; break;
        case 1: value = cast(ubyte) "hello"[i % 5]; break;
        case 2: value = 'A'; break;
        case 3: value = cast(ubyte) "the quick brown fox jumps over the lazy dog\n"[i % 44]; break;
        case 5: value = cast(ubyte)(i % 251); break;
        default: assert(0);
        }
    }
    return data;
}

private Result decode(bool gzip)(ref SelectState!gzip state, ref InflateWorkspace ws,
    scope const(ubyte)[] input, scope ubyte[] output, bool last) @safe pure nothrow @nogc
{
    static if (gzip) return decodeGzip(state, ws, input, output, last);
    else return decodeZlib(state, ws, input, output, last);
}
private template SelectState(bool gzip)
{
    static if (gzip) alias SelectState = GzipState;
    else alias SelectState = ZlibState;
}

private void checkLimits(bool gzip)() @safe
{
    const fixture = frameFixtures[gzip ? 11 : 4]; // 70000 'A' bytes
    auto encoded = unhex(fixture.hex);
    auto output = new ubyte[fixture.length + 8];
    InflateWorkspace ws;
    foreach (limits; [DecodeLimits(0), DecodeLimits(1), DecodeLimits(258),
        DecodeLimits(69999), DecodeLimits(ulong.max, 1), DecodeLimits(ulong.max, 2)])
    {
        output[] = 0xA5;
        SelectState!gzip full, chunked;
        full.reset(limits); chunked.reset(limits);
        const result = decode!gzip(full, ws, encoded, output, true);
        assert(result.error.code == ErrorCode.outputLimitExceeded || result.error.code == ErrorCode.expansionLimitExceeded);
        foreach (guard; output[result.produced .. $]) assert(guard == 0xA5);
        size_t position, written;
        Result part;
        do
        {
            ubyte[1] chunk;
            part = decode!gzip(chunked, ws, encoded[position .. $], chunk, true);
            position += part.consumed; written += part.produced;
        } while (part.status == DecodeStatus.needOutput);
        assert(part.error.code == result.error.code && position == result.consumed && written == result.produced);
        assert(full.totalInput == chunked.totalInput && full.totalOutput == chunked.totalOutput);
    }
    assert((gzip ? inflateGzip(encoded, output, ws, DecodeLimits(70000)) :
        inflateZlib(encoded, output, ws, DecodeLimits(70000))).status == DecodeStatus.done);
}

@safe unittest
{
    checkLimits!false(); checkLimits!true();
    // Framing bytes count toward ratio policy: one output byte exceeds its
    // compressed payload alone at some boundaries, but headers are real input.
    InflateWorkspace ws;
    ubyte[5] output;
    auto z = unhex(frameFixtures[2].hex);
    auto g = unhex(frameFixtures[9].hex);
    assert(inflateZlib(z, output, ws, DecodeLimits(5, 1)).status == DecodeStatus.done);
    assert(inflateGzip(g, output, ws, DecodeLimits(5, 1)).status == DecodeStatus.done);
    auto emptyZ = unhex(frameFixtures[0].hex);
    auto emptyG = unhex(frameFixtures[7].hex);
    assert(inflateZlib(emptyZ, null, ws, DecodeLimits(0)).status == DecodeStatus.done);
    assert(inflateGzip(emptyG, null, ws, DecodeLimits(0)).status == DecodeStatus.done);
    // Payload errors are translated to offsets in the framed input.
    auto badZ = unhex("780107");
    auto badG = unhex("1f8b08000000000000ff07");
    assert(inflateZlib(badZ, output, ws).error.inputOffset == 2);
    assert(inflateGzip(badG, output, ws).error.inputOffset == 10);
}

@safe unittest
{
    // One literal plus a 258-byte overlapping match: raw expansion fails at
    // these ratios, but the actually consumed frame headers make it admissible.
    ubyte[] raw;
    uint bitPosition;
    putBits(raw, bitPosition, 3, 3);
    putCode(raw, bitPosition, 'A' + 48, 8);
    putCode(raw, bitPosition, 285 - 88, 8);
    putCode(raw, bitPosition, 0, 5); putCode(raw, bitPosition, 0, 7);
    ubyte[259] output, expected;
    expected[] = 'A';
    InflateWorkspace ws;
    assert(inflateRaw(raw, output, ws, DecodeLimits(259, 52)).error.code == ErrorCode.expansionLimitExceeded);
    auto z = [cast(ubyte)0x78, cast(ubyte)1] ~ raw;
    const adler = adler32(expected);
    foreach_reverse (uint shift; 0 .. 4) z ~= cast(ubyte)(adler >> (shift * 8));
    assert(inflateZlib(z, output, ws, DecodeLimits(259, 52)).status == DecodeStatus.done);
    auto g = unhex("1f8b08000000000000ff") ~ raw;
    const crc = crc32(expected);
    foreach (uint shift; 0 .. 4) g ~= cast(ubyte)(crc >> (shift * 8));
    g ~= [cast(ubyte)3, cast(ubyte)1, cast(ubyte)0, cast(ubyte)0]; // 259
    assert(inflateGzip(g, output, ws, DecodeLimits(259, 20)).status == DecodeStatus.done);
}

private void checkStream(bool gzip)(scope const(ubyte)[] encoded, scope const(ubyte)[] expected,
    size_t inputStep, size_t outputStep, bool concatenated = false) @safe
{
    SelectState!gzip state;
    static if (gzip) state.reset(DecodeLimits.init, concatenated);
    InflateWorkspace ws;
    auto output = new ubyte[expected.length + 8];
    output[] = 0xA5;
    size_t position, written, calls;
    size_t available = min(encoded.length, inputStep);
    while (true)
    {
        const end = min(written + outputStep, expected.length);
        const result = decode!gzip(state, ws, encoded[position .. available], output[written .. end], available == encoded.length);
        assert(result.consumed <= available - position && result.produced <= end - written);
        position += result.consumed; written += result.produced;
        assert(state.totalInput == position && state.totalOutput == written);
        assert(++calls < (encoded.length + expected.length) * 4 + 100);
        if (result.status == DecodeStatus.done) break;
        assert(result.status != DecodeStatus.error);
        if (result.status == DecodeStatus.needInput)
        {
            assert(available < encoded.length);
            available = min(encoded.length, available + inputStep);
        }
        else assert(result.status == DecodeStatus.needOutput && written < expected.length);
    }
    assert(position == encoded.length && output[0 .. written] == expected && written == expected.length);
    foreach (guard; output[written .. $]) assert(guard == 0xA5);
    assert(decode!gzip(state, ws, null, null, true).error.code == ErrorCode.invalidArgument);
}

@safe unittest
{
    foreach (fixture; frameFixtures)
    {
        auto encoded = unhex(fixture.hex);
        auto expected = plaintext(fixture.pattern, fixture.length);
        InflateWorkspace ws;
        auto output = new ubyte[expected.length];
        const result = fixture.gzip ? inflateGzip(encoded, output, ws) : inflateZlib(encoded, output, ws);
        assert(result.status == DecodeStatus.done && output == expected, fixture.name);
        assert(result.consumed == encoded.length && result.produced == expected.length);
        auto trailing = encoded ~ [cast(ubyte)0xA5, cast(ubyte)0x5A];
        const tail = fixture.gzip ? inflateGzip(trailing, output, ws) : inflateZlib(trailing, output, ws);
        assert(tail.status == DecodeStatus.done && tail.consumed == encoded.length);
        if (fixture.gzip)
        {
            checkStream!true(encoded, expected, 1, 1);
            checkStream!true(encoded, expected, 3, 7);
        }
        else
        {
            checkStream!false(encoded, expected, 1, 1);
            checkStream!false(encoded, expected, 3, 7);
        }
        if (fixture.name != "z-fixed" && fixture.name != "g-fixed" && fixture.name != "g-flags-31") continue;
        foreach (cut; 0 .. encoded.length)
        {
            const truncated = fixture.gzip ? inflateGzip(encoded[0 .. cut], output, ws) : inflateZlib(encoded[0 .. cut], output, ws);
            assert(truncated.error.code == ErrorCode.truncatedInput, fixture.name);
            assert(truncated.error.inputOffset == cut);
        }
    }
}

@safe unittest
{
    InflateWorkspace ws;
    ubyte[16] output;
    auto z = unhex(frameFixtures[2].hex); // z-fixed
    auto g = unhex(frameFixtures[9].hex); // g-fixed
    foreach (index; [0UL, 1UL])
    {
        auto bad = z.dup; bad[index] ^= 1;
        assert(inflateZlib(bad, output, ws).error.code == ErrorCode.invalidHeader);
    }
    auto badZ = z.dup; badZ[$ - 1] ^= 1;
    assert(inflateZlib(badZ, output, ws).error.code == ErrorCode.checksumMismatch);
    foreach (index; [0UL, 1UL, 2UL, 3UL])
    {
        auto bad = g.dup;
        if (index == 3) bad[index] |= 0x20; else bad[index] ^= 1;
        assert(inflateGzip(bad, output, ws).error.code == ErrorCode.invalidHeader);
    }
    foreach (index; [g.length - 8, g.length - 1])
    {
        auto bad = g.dup; bad[index] ^= 1;
        assert(inflateGzip(bad, output, ws).error.code == ErrorCode.checksumMismatch);
    }
    auto options = unhex(frameFixtures[$ - 1].hex);
    // Header length 10+2+4+9+7+2=34, including FHCRC.
    options[32] ^= 1;
    assert(inflateGzip(options, output, ws).error.code == ErrorCode.checksumMismatch);
    auto dict = unhex("782012345678"); // FDICT with valid FCHECK.
    ZlibState state;
    auto result = decodeZlib(state, ws, dict, output, true);
    assert(result.error.code == ErrorCode.dictionaryRequired && state.dictionaryId == 0x12345678);
    assert(result.consumed == 6 && result.produced == 0);
    assert(decodeZlib(state, ws, z, output, true).error.code == ErrorCode.dictionaryRequired);
    state.reset();
    assert(decodeZlib(state, ws, z, output, true).status == DecodeStatus.done);
    foreach (cut; 2 .. dict.length)
        assert(inflateZlib(dict[0 .. cut], output, ws).error.code == ErrorCode.truncatedInput);
}

@safe unittest
{
    InflateWorkspace ws;
    auto g = unhex(frameFixtures[9].hex);
    auto combined = g ~ g;
    ubyte[16] output;
    auto result = inflateGzip(combined, output, ws);
    assert(result.status == DecodeStatus.done && result.consumed == g.length && result.produced == 5);
    result = inflateGzip(combined, output, ws, DecodeLimits(10), true);
    assert(result.status == DecodeStatus.done && result.produced == 10 && output[0 .. 10] == "hellohello");
    checkStream!true(combined, cast(const(ubyte)[]) "hellohello", 1, 1, true);
    result = inflateGzip(combined, output, ws, DecodeLimits(5), true);
    assert(result.error.code == ErrorCode.outputLimitExceeded && result.produced == 5);
    GzipState state;
    state.reset(DecodeLimits.init, true);
    result = decodeGzip(state, ws, g, output, false);
    assert(result.status == DecodeStatus.needInput && state.memberCount == 1);
    result = decodeGzip(state, ws, g, output[5 .. $], false);
    assert(result.status == DecodeStatus.needInput && state.memberCount == 2 && state.totalOutput == 10);
    result = decodeGzip(state, ws, null, null, true);
    assert(result.status == DecodeStatus.done);
    state.reset();
    assert(state.totalInput == 0 && state.totalOutput == 0 && state.memberCount == 0);
    assert(decodeGzip(state, ws, g, output, true).status == DecodeStatus.done);
    auto junk = combined ~ [cast(ubyte)0x42];
    assert(inflateGzip(junk, output, ws, DecodeLimits.init, true).error.code == ErrorCode.invalidHeader);
    auto partial = combined ~ [cast(ubyte)31];
    assert(inflateGzip(partial, output, ws, DecodeLimits.init, true).error.code == ErrorCode.truncatedInput);
    // A new member may not refer back to the preceding member's history.
    ubyte[] raw;
    uint bits;
    putBits(raw, bits, 3, 3); putCode(raw, bits, 1, 7); putCode(raw, bits, 0, 5);
    auto borrowedHistory = g ~ g[0 .. 10] ~ raw;
    assert(inflateGzip(borrowedHistory, output, ws, DecodeLimits.init, true).error.code == ErrorCode.invalidDistance);
    auto largeMember = unhex(frameFixtures[11].hex);
    auto mixed = g ~ largeMember;
    auto largeOutput = new ubyte[70005];
    const failed = inflateGzip(mixed, largeOutput, ws, DecodeLimits(ulong.max, 1), true);
    assert(failed.error.code == ErrorCode.expansionLimitExceeded);
    state.reset(DecodeLimits(ulong.max, 1), true);
    size_t consumed, produced;
    do
    {
        ubyte[1] chunk;
        result = decodeGzip(state, ws, mixed[consumed .. $], chunk, true);
        consumed += result.consumed; produced += result.produced;
    } while (result.status == DecodeStatus.needOutput);
    assert(result.error.code == failed.error.code && consumed == failed.consumed && produced == failed.produced);
    // Terminal errors require reset; a reused workspace does not leak CRC state.
    assert(decodeGzip(state, ws, g, output, true).consumed == 0);
    state.reset();
    assert(decodeGzip(state, ws, g, output, true).status == DecodeStatus.done);
}

private void putBits(ref ubyte[] bytes, ref uint position, uint value, uint width) @safe
{
    foreach (uint bit; 0 .. width)
    {
        if (position % 8 == 0) bytes ~= cast(ubyte)0;
        bytes[$ - 1] |= ((value >> bit) & 1) << (position % 8);
        ++position;
    }
}
private void putCode(ref ubyte[] bytes, ref uint position, uint value, uint width) @safe
{
    foreach_reverse (uint bit; 0 .. width) putBits(bytes, position, (value >> bit) & 1, 1);
}

@safe unittest
{
    // A 300-byte stored block followed by a fixed match at distance 300.
    // The advertised zlib window must constrain otherwise available history.
    ubyte[] raw;
    uint position;
    putBits(raw, position, 0, 8);
    putBits(raw, position, 300, 16); putBits(raw, position, 65535 ^ 300, 16);
    auto expected = new ubyte[303];
    foreach (uint i; 0 .. 300)
    {
        expected[i] = cast(ubyte)i;
        putBits(raw, position, i & 255, 8);
    }
    putBits(raw, position, 3, 3); // final fixed block
    putCode(raw, position, 1, 7); // length 3
    putCode(raw, position, 16, 5); putBits(raw, position, 43, 7); // distance 300
    putCode(raw, position, 0, 7); // EOB
    expected[300 .. $] = expected[0 .. 3];
    auto large = [cast(ubyte)0x78, cast(ubyte)1] ~ raw;
    const checksum = adler32(expected);
    foreach_reverse (uint shift; 0 .. 4) large ~= cast(ubyte)(checksum >> (shift * 8));
    InflateWorkspace ws;
    ubyte[303] output;
    assert(inflateZlib(large, output, ws).status == DecodeStatus.done && output[] == expected);
    large[0] = 8; large[1] = 29; // CINFO=0: 256 bytes
    assert(inflateZlib(large, output, ws).error.code == ErrorCode.invalidDistance);
    // All legal windows admit the small literal-only example.
    foreach (uint cinfo; 0 .. 8)
    {
        auto encoded = unhex(frameFixtures[2].hex);
        encoded[0] = cast(ubyte)((cinfo << 4) | 8);
        encoded[1] = cast(ubyte)((31 - ((cast(uint)encoded[0] << 8) % 31)) % 31);
        assert(inflateZlib(encoded, output, ws).status == DecodeStatus.done);
    }
    // Empty and maximum-size FEXTRA fields are skipped without retaining data.
    auto g = unhex(frameFixtures[9].hex);
    foreach (uint length; [0U, 65535U])
    {
        auto encoded = g[0 .. 10].dup;
        encoded[3] = 4;
        encoded ~= cast(ubyte)length; encoded ~= cast(ubyte)(length >> 8);
        encoded.length += length; // initialized binary metadata
        encoded ~= g[10 .. $];
        assert(inflateGzip(encoded, output, ws).status == DecodeStatus.done);
        if (length == 0) checkStream!true(encoded, cast(const(ubyte)[]) "hello", 1, 1);
    }
}

@safe unittest
{
    // Alternate independently owned pairs while reusing/overwriting one output
    // byte: both history and incremental checksums must outlive caller buffers.
    auto z = unhex(frameFixtures[2].hex);
    auto g = unhex(frameFixtures[$ - 1].hex);
    ZlibState zs;
    GzipState gs;
    InflateWorkspace zw, gw;
    size_t zi, gi, zo, go;
    bool zd, gd;
    while (!zd || !gd)
    {
        ubyte[1] output;
        if (!zd)
        {
            auto result = decodeZlib(zs, zw, z[zi .. $], output, true);
            assert(result.status == DecodeStatus.done || result.status == DecodeStatus.needOutput);
            if (result.produced != 0) assert(output[0] == "hello"[zo++]);
            zi += result.consumed; zd = result.status == DecodeStatus.done;
        }
        output[] = 0xFF;
        if (!gd)
        {
            auto result = decodeGzip(gs, gw, g[gi .. $], output, true);
            assert(result.status == DecodeStatus.done || result.status == DecodeStatus.needOutput);
            if (result.produced != 0) assert(output[0] == "hello"[go++]);
            gi += result.consumed; gd = result.status == DecodeStatus.done;
        }
    }
    assert(zo == 5 && go == 5 && zi == z.length && gi == g.length);
}
