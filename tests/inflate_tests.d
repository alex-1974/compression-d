module inflate_tests;

import compression.core;
import compression.deflate;
import inflate_fixtures;
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
    uint seed = 12345;
    foreach (i, ref value; data)
    {
        seed = seed * 1664525 + 1013904223;
        final switch (pattern)
        {
        case 0: value = 0; break;
        case 1: value = cast(ubyte) "hello"[i % 5]; break;
        case 2: value = 'A'; break;
        case 3: value = cast(ubyte) "the quick brown fox jumps over the lazy dog\n"[i % 44]; break;
        case 4: value = cast(ubyte)(seed >> 24); break;
        case 5: value = cast(ubyte)(i % 251); break;
        }
    }
    return data;
}

private void streamCheck(scope const(ubyte)[] encoded, scope const(ubyte)[] expected,
    size_t inputStep, size_t outputStep) @safe
{
    InflateState state;
    InflateWorkspace workspace;
    auto resultBytes = new ubyte[expected.length + 16];
    resultBytes[] = 0xA5;
    size_t available = min(inputStep, encoded.length), position, written;
    size_t calls;
    while (true)
    {
        const end = min(written + outputStep, expected.length);
        auto result = inflate(state, workspace, encoded[position .. available],
            resultBytes[written .. end], available == encoded.length);
        assert(result.consumed <= available - position);
        assert(result.produced <= end - written);
        position += result.consumed;
        written += result.produced;
        assert(state.totalInput == position && state.totalOutput == written);
        assert(++calls < (encoded.length + expected.length) * 4 + 100);
        if (result.status == DecodeStatus.done)
            break;
        assert(result.status != DecodeStatus.error);
        if (result.status == DecodeStatus.needInput)
        {
            assert(available < encoded.length);
            available = min(available + inputStep, encoded.length);
        }
        else
            assert(result.status == DecodeStatus.needOutput && written < expected.length);
    }
    assert(position == encoded.length);
    assert(written == expected.length && resultBytes[0 .. written] == expected);
    foreach (guard; resultBytes[written .. $])
        assert(guard == 0xA5);
    assert(inflate(state, workspace, null, null).error.code == ErrorCode.invalidArgument);
}

@safe unittest
{
    foreach (fixture; fixtures)
    {
        auto encoded = unhex(fixture.hex);
        auto expected = plaintext(fixture.pattern, fixture.length);
        InflateWorkspace workspace;
        auto output = new ubyte[expected.length];
        const result = inflateRaw(encoded, output, workspace);
        assert(result.status == DecodeStatus.done, fixture.name);
        assert(result.consumed == encoded.length && result.produced == expected.length, fixture.name);
        assert(output == expected, fixture.name);
        streamCheck(encoded, expected, 1, 1);
        streamCheck(encoded, expected, 3, 7);
        streamCheck(encoded, expected, 127, 258);
        auto withTrailer = encoded ~ [cast(ubyte)0xA5, cast(ubyte)0x5A];
        assert(inflateRaw(withTrailer, output, workspace).consumed == encoded.length, fixture.name);
    }
}

@safe unittest
{
    // Every byte truncation of representative stored, fixed and dynamic streams.
    foreach (fixture; fixtures)
    {
        if (fixture.name != "hello-stored" && fixture.name != "hello-fixed" &&
            fixture.name != "dynamic-text")
            continue;
        auto encoded = unhex(fixture.hex);
        auto output = new ubyte[fixture.length];
        InflateWorkspace workspace;
        foreach (cut; 0 .. encoded.length)
        {
            InflateState state;
            const result = inflate(state, workspace, encoded[0 .. cut], output, true);
            assert(result.status == DecodeStatus.error &&
                result.error.code == ErrorCode.truncatedInput, fixture.name);
            assert(result.error.inputOffset == cut);
            const again = inflate(state, workspace, encoded, output, true);
            assert(again.error.code == result.error.code && again.consumed == 0 && again.produced == 0);
        }
    }
}

@safe unittest
{
    // Budgets are cumulative and a rejected match writes none of that token.
    auto fixture = fixtures[5]; // fixed A * 70000, includes distance-one overlap.
    auto encoded = unhex(fixture.hex);
    InflateWorkspace workspace;
    auto output = new ubyte[fixture.length + 8];
    foreach (ulong cap; [0UL, 1UL, 2UL, 257UL, 258UL, 300UL, 69999UL])
    {
        output[] = 0xA5;
        InflateState state;
        state.reset(DecodeLimits(cap));
        auto result = inflate(state, workspace, encoded, output, true);
        assert(result.error.code == ErrorCode.outputLimitExceeded);
        assert(state.totalOutput <= cap && result.produced == state.totalOutput);
        foreach (guard; output[result.produced .. $])
            assert(guard == 0xA5);
        // Identical rejection boundary with one-byte output chunks.
        InflateState chunked;
        chunked.reset(DecodeLimits(cap));
        size_t consumed, produced;
        do
        {
            ubyte[1] chunk;
            result = inflate(chunked, workspace, encoded[consumed .. $], chunk, true);
            consumed += result.consumed;
            produced += result.produced;
        } while (result.status == DecodeStatus.needOutput);
        assert(result.error.code == ErrorCode.outputLimitExceeded);
        assert(produced == state.totalOutput && chunked.totalInput == state.totalInput);
    }
    assert(inflateRaw(encoded, output, workspace, DecodeLimits(70000)).status == DecodeStatus.done);
    auto bomb = inflateRaw(encoded, output, workspace, DecodeLimits(ulong.max, 2));
    assert(bomb.error.code == ErrorCode.expansionLimitExceeded);
    assert(bomb.produced <= bomb.consumed * 2);
    InflateState limited;
    limited.reset(DecodeLimits(ulong.max, 2));
    size_t limitedInput, limitedOutput;
    Result part;
    do
    {
        ubyte[1] chunk;
        part = inflate(limited, workspace, encoded[limitedInput .. $], chunk, true);
        limitedInput += part.consumed;
        limitedOutput += part.produced;
    } while (part.status == DecodeStatus.needOutput);
    assert(part.error.code == bomb.error.code && limitedInput == bomb.consumed && limitedOutput == bomb.produced);
    assert(inflateRaw(encoded, output, workspace, DecodeLimits(ulong.max, 10000)).status == DecodeStatus.done);
    // Exact zero budget is valid for an empty stream and zero-sized output.
    assert(inflateRaw(unhex(fixtures[0].hex), null, workspace, DecodeLimits(0)).status == DecodeStatus.done);
}

@safe unittest
{
    // Overwrite the output on every call; history must live in the workspace.
    auto encodedA = unhex(fixtures[5].hex);
    auto encodedB = unhex(fixtures[6].hex);
    auto expectedA = plaintext(fixtures[5].pattern, fixtures[5].length);
    auto expectedB = plaintext(fixtures[6].pattern, fixtures[6].length);
    InflateState a, b;
    InflateWorkspace wa, wb;
    size_t ia, ib, oa, ob;
    bool doneA, doneB;
    while (!doneA || !doneB)
    {
        ubyte[7] chunk;
        if (!doneA)
        {
            auto result = inflate(a, wa, encodedA[ia .. $], chunk, true);
            assert(result.status == DecodeStatus.needOutput || result.status == DecodeStatus.done);
            assert(chunk[0 .. result.produced] == expectedA[oa .. oa + result.produced]);
            ia += result.consumed; oa += result.produced;
            doneA = result.status == DecodeStatus.done;
        }
        chunk[] = 0xFF;
        if (!doneB)
        {
            auto result = inflate(b, wb, encodedB[ib .. $], chunk, true);
            assert(result.status == DecodeStatus.needOutput || result.status == DecodeStatus.done);
            assert(chunk[0 .. result.produced] == expectedB[ob .. ob + result.produced]);
            ib += result.consumed; ob += result.produced;
            doneB = result.status == DecodeStatus.done;
        }
    }
    assert(oa == expectedA.length && ob == expectedB.length);
    a.reset();
    assert(a.totalInput == 0 && a.totalOutput == 0);
    auto result = inflate(a, wa, unhex(fixtures[3].hex), expectedA, true);
    assert(result.status == DecodeStatus.done && result.produced == 5);
}

// Test-only raw bit writer, independent of the library's canonical builder.
private struct Writer
{
    ubyte[] bytes;
    uint bits;
    void put(uint value, uint width) @safe
    {
        foreach (uint bit; 0 .. width)
        {
            if (bits % 8 == 0) bytes ~= cast(ubyte)0;
            bytes[$ - 1] |= ((value >> bit) & 1) << (bits % 8);
            ++bits;
        }
    }
    void code(uint value, uint width) @safe
    {
        foreach_reverse (uint bit; 0 .. width)
            put((value >> bit) & 1, 1);
    }
    void fixed(uint symbol) @safe
    {
        if (symbol < 144) code(symbol + 48, 8);
        else if (symbol < 256) code(symbol + 256, 9);
        else if (symbol < 280) code(symbol - 256, 7);
        else code(symbol - 88, 8);
    }
}

private void dynamicHeader(ref Writer writer, scope const(ubyte)[] codeLengths,
    uint hdist = 0) @safe
{
    immutable ubyte[19] order = [16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15];
    writer.put(5, 3);
    writer.put((15 << 10) | (hdist << 5), 14); // 257 literals, 19 code lengths
    foreach (symbol; order) writer.put(codeLengths[symbol], 3);
}

@safe unittest
{
    InflateWorkspace workspace;
    ubyte[16] output;
    ubyte[19] lengths;
    lengths[0] = 1; lengths[1] = 2; lengths[18] = 2;
    Writer empty;
    dynamicHeader(empty, lengths);
    empty.code(3, 2); empty.put(127, 7); // 138 zeros
    empty.code(3, 2); empty.put(107, 7); // 118 zeros, total 256
    empty.code(2, 2); // EOB length 1
    empty.code(0, 1); // empty distance alphabet
    empty.put(0, 1); // EOB singleton
    auto result = inflateRaw(empty.bytes, null, workspace, DecodeLimits(0));
    assert(result.status == DecodeStatus.done && result.produced == 0);
    streamCheck(empty.bytes, null, 1, 1);

    // Repeats 16/17/18, including a repeat that crosses the alphabet boundary.
    Writer cross;
    lengths[] = 0;
    lengths[0] = 2; lengths[1] = 2; lengths[16] = 2; lengths[17] = 3; lengths[18] = 3;
    dynamicHeader(cross, lengths, 1);
    cross.code(7, 3); cross.put(127, 7); // 138 zeros
    cross.code(7, 3); cross.put(106, 7); // 117 zeros
    cross.code(1, 2); // symbol 255 has length 1
    cross.code(2, 2); cross.put(0, 2); // 3 copies: EOB and two distances
    cross.put(0, 1); cross.put(1, 1); // literal 255, EOB
    result = inflateRaw(cross.bytes, output, workspace);
    assert(result.status == DecodeStatus.done && result.produced == 1 && output[0] == 255);
    streamCheck(cross.bytes, [cast(ubyte)255], 1, 1);

    Writer repeated;
    lengths[1] = 0; lengths[3] = 2;
    dynamicHeader(repeated, lengths);
    repeated.code(7, 3); repeated.put(51, 7); // 62 zeros
    repeated.code(6, 3); repeated.put(0, 3); // 3 zeros
    repeated.code(1, 2); // literal 65 length 3
    repeated.code(2, 2); repeated.put(3, 2); // 6 copies, symbols 66..71
    repeated.code(7, 3); repeated.put(127, 7); // 138 zeros
    repeated.code(7, 3); repeated.put(35, 7); // 46 zeros
    repeated.code(1, 2); repeated.code(0, 2); // EOB length3, empty distances
    repeated.code(0, 3); repeated.code(7, 3); // A, EOB
    result = inflateRaw(repeated.bytes, output, workspace);
    assert(result.status == DecodeStatus.done && result.produced == 1 && output[0] == 'A');
    streamCheck(repeated.bytes, [cast(ubyte)'A'], 1, 1);

    lengths[3] = 0; lengths[1] = 2;
    Writer noPrevious;
    dynamicHeader(noPrevious, lengths);
    noPrevious.code(2, 2); // Repeat 16 without a preceding length.
    assert(inflateRaw(noPrevious.bytes, output, workspace).error.code == ErrorCode.invalidHuffmanTree);
    Writer overrun;
    dynamicHeader(overrun, lengths);
    foreach (i; 0 .. 2) { overrun.code(7, 3); overrun.put(127, 7); }
    assert(inflateRaw(overrun.bytes, output, workspace).error.code == ErrorCode.invalidHuffmanTree);
    Writer missingEnd;
    dynamicHeader(missingEnd, lengths);
    missingEnd.code(7, 3); missingEnd.put(127, 7);
    missingEnd.code(7, 3); missingEnd.put(109, 7); // 258 zeros: no EOB
    assert(inflateRaw(missingEnd.bytes, output, workspace).error.code == ErrorCode.invalidHuffmanTree);
    Writer overfull;
    lengths[] = 0; lengths[0] = 1; lengths[1] = 1; lengths[18] = 1;
    dynamicHeader(overfull, lengths);
    assert(inflateRaw(overfull.bytes, output, workspace).error.code == ErrorCode.invalidHuffmanTree);
}

@safe unittest
{
    InflateWorkspace workspace;
    ubyte[32] output;
    // Reserved block type and bad stored complement.
    assert(inflateRaw(unhex("07"), output, workspace).error.code == ErrorCode.invalidHeader);
    assert(inflateRaw(unhex("010100000041"), output, workspace).error.code == ErrorCode.invalidData);
    foreach (uint bad; [286U, 287U])
    {
        Writer writer;
        writer.put(3, 3); writer.fixed(bad);
        assert(inflateRaw(writer.bytes, output, workspace).error.code == ErrorCode.invalidData);
    }
    foreach (uint bad; [0U, 30U, 31U])
    {
        Writer writer;
        writer.put(3, 3); writer.fixed(257); writer.code(bad, 5);
        assert(inflateRaw(writer.bytes, output, workspace).error.code == ErrorCode.invalidDistance);
    }
    foreach (uint counts; [30U, 31U, 30U << 5, 31U << 5])
    {
        Writer writer;
        writer.put(5, 3); writer.put(counts, 14);
        assert(inflateRaw(writer.bytes, output, workspace).error.code == ErrorCode.invalidHeader);
    }
    // Empty code-length tree.
    assert(inflateRaw(unhex("05000000"), output, workspace).error.code == ErrorCode.invalidHuffmanTree);
}

@safe unittest
{
    // Exact distance 32768, stored/fixed cross-block history, ring rollover.
    Writer writer;
    writer.put(0, 3); writer.put(0, 5); // nonfinal stored, aligned
    writer.put(32768, 16); writer.put(32767, 16);
    auto expected = plaintext(5, 32768);
    foreach (value; expected) writer.put(value, 8);
    writer.put(3, 3); writer.fixed(257); writer.code(29, 5); writer.put(8191, 13);
    writer.fixed(256);
    expected ~= expected[0 .. 3];
    streamCheck(writer.bytes, expected, 1, 7);
    // Maximum stored LEN and a second empty final block.
    Writer maximum;
    maximum.put(0, 3); maximum.put(0, 5);
    maximum.put(65535, 16); maximum.put(0, 16);
    foreach (uint i; 0 .. 65535) maximum.put(i & 255, 8);
    maximum.put(1, 3); maximum.put(0, 5);
    maximum.put(0, 16); maximum.put(65535, 16);
    auto output = new ubyte[65535];
    InflateWorkspace workspace;
    auto result = inflateRaw(maximum.bytes, output, workspace);
    assert(result.status == DecodeStatus.done && result.produced == 65535);
    foreach (i, value; output) assert(value == (i & 255));
}

@safe unittest
{
    // Every length/distance extra-bit range, using independent arithmetic.
    InflateWorkspace workspace;
    foreach (uint index; 0 .. 29)
    foreach (maximum; [false, true])
    {
        const width = index < 8 || index == 28 ? 0 : index / 4 - 1;
        const extra = maximum ? (1U << width) - 1 : 0;
        const length = index < 8 ? index + 3 : index == 28 ? 258 :
            (1U << (width + 2)) + 3 + (index % 4) * (1U << width) + extra;
        Writer writer;
        writer.put(3, 3); writer.fixed('Q'); writer.fixed(index + 257);
        writer.put(extra, width); writer.code(0, 5); writer.fixed(256);
        auto output = new ubyte[length + 1];
        const result = inflateRaw(writer.bytes, output, workspace);
        assert(result.status == DecodeStatus.done && result.produced == length + 1);
        foreach (value; output) assert(value == 'Q');
    }
    foreach (uint code; 0 .. 30)
    foreach (maximum; [false, true])
    {
        const width = code < 4 ? 0 : code / 2 - 1;
        const extra = maximum ? (1U << width) - 1 : 0;
        const distance = code < 4 ? code + 1 :
            (1U << (width + 1)) + 1 + (code % 2) * (1U << width) + extra;
        Writer writer;
        writer.put(0, 3); writer.put(0, 5);
        writer.put(32768, 16); writer.put(32767, 16);
        auto expected = plaintext(5, 32768);
        foreach (value; expected) writer.put(value, 8);
        writer.put(3, 3); writer.fixed(257); writer.code(code, 5);
        writer.put(extra, width); writer.fixed(256);
        foreach (i; 0 .. 3) expected ~= expected[$ - distance];
        auto output = new ubyte[expected.length];
        const result = inflateRaw(writer.bytes, output, workspace);
        assert(result.status == DecodeStatus.done && output == expected);
    }
}
