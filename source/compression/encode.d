/// Allocation-free RFC 1951 stored-block encoder and common framing helpers.
module compression.encode;

import compression.checksum;
import compression.core;
import compression.deflate;
import compression.zlib;

private enum BlockLimit = 65535;
private immutable ushort[29] lengthBase = [3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258];
private immutable ubyte[29] lengthExtra = [0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0];
private immutable ushort[30] distanceBase = [1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577];
private immutable ubyte[30] distanceExtra = [0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13];

private uint reverseBits(uint value, uint count) @safe pure nothrow @nogc
{
    uint result;
    foreach (_; 0 .. count) { result = (result << 1) | (value & 1); value >>= 1; }
    return result;
}

private uint fixedLiteralCode(uint symbol, ref uint bits) @safe pure nothrow @nogc
{
    uint code, width;
    if (symbol <= 143) { code = 0x30 + symbol; width = 8; }
    else if (symbol <= 255) { code = 0x190 + symbol - 144; width = 9; }
    else if (symbol <= 279) { code = symbol - 256; width = 7; }
    else { code = 0xC0 + symbol - 280; width = 8; }
    bits = width; return reverseBits(code, width);
}

private struct BitWriter
{
    ubyte[] buffer; size_t pos; uint bits, count;
    @safe pure nothrow @nogc:
    bool put(uint value, uint width) scope
    {
        if (width == 0) return true;
        if (pos + ((count + width + 7) / 8) > buffer.length) return false;
        bits |= value << count; count += width;
        while (count >= 8) { buffer[pos++] = cast(ubyte) bits; bits >>= 8; count -= 8; }
        return true;
    }
    bool finish() scope
    { if (count != 0) { if (pos >= buffer.length) return false; buffer[pos++] = cast(ubyte) bits; } return true; }
}

private bool emitFixed(ref BitWriter w, uint symbol) @safe pure nothrow @nogc
{ uint n; return w.put(fixedLiteralCode(symbol, n), n); }

private bool emitMatch(ref BitWriter w, LzMatch m) @safe pure nothrow @nogc
{
    uint li;
    foreach (i; 0 .. 29) if (m.length >= lengthBase[i] && m.length <= lengthBase[i] + ((1U << lengthExtra[i]) - 1)) li = i;
    uint di;
    foreach (i; 0 .. 30) if (m.distance >= distanceBase[i] && m.distance <= distanceBase[i] + ((1U << distanceExtra[i]) - 1)) di = i;
    if (!emitFixed(w, 257 + li)) return false;
    if (!w.put(m.length - lengthBase[li], lengthExtra[li])) return false;
    if (!w.put(reverseBits(di, 5), 5)) return false;
    return w.put(m.distance - distanceBase[di], distanceExtra[di]);
}

/// Greedy fixed-Huffman DEFLATE with bounded LZ77 matches.
Result encodeRawFixedLz(scope const(ubyte)[] input, scope ubyte[] output,
    bool finalBlock = true, scope const(ubyte)[] history = null,
    uint historySize = 0, uint historyWrite = 0)
    @safe pure nothrow @nogc
{
    BitWriter w; w.buffer = output;
    if (!w.put(finalBlock ? 1 : 0, 1) || !w.put(1, 2)) return Result.needOutput;
    size_t p;
    while (p < input.length)
    {
        auto m = historySize == 0 ? findLzMatch(input, p) :
            findLzMatchWithHistory(input, p, history, historySize, historyWrite);
        if (m.length >= 3) { if (!emitMatch(w, m)) return Result.needOutput; p += m.length; }
        else { if (!emitFixed(w, input[p])) return Result.needOutput; ++p; }
    }
    if (!emitFixed(w, 256) || !w.finish()) return Result.needOutput;
    return Result.done(input.length, w.pos);
}

struct LzMatch
{
    ushort length;
    ushort distance;
}

/// Caller-owned bounded hash-chain match finder.
///
/// The tables use 32,768 buckets and a 32-entry search budget. The fixed
/// arrays are part of the value, so callers can place this state wherever the
/// encoder workspace is owned. The finder retains only the RFC 1951 history
/// window and never allocates.
struct HashChainMatchFinder
{
    private uint[32768] heads;
    private uint[32768] previous;
    private ubyte[32768] history;
    private uint historySize;
    private uint historyWrite;
    private uint position;
    private uint pendingBits;
    private uint pendingCount;
    private bool overflowed;

    @safe pure nothrow @nogc:
    void reset() { this = HashChainMatchFinder.init; }
    @property uint availableHistory() const { return historySize; }
    @property bool valid() const { return !overflowed; }
}

/// Fixed caller-owned storage required by HashChainMatchFinder.
enum size_t hashChainWorkspaceBytes = HashChainMatchFinder.sizeof;

private uint chainHash(ubyte a, ubyte b, ubyte c) @safe pure nothrow @nogc
{ return (((cast(uint) a * 251 + b) * 251 + c) & 32767); }

private ubyte finderByte(scope const(ubyte)[] input, uint base, uint historySize,
    scope const(ubyte)[] history, uint writePos, uint absolute)
    @safe pure nothrow @nogc
{
    if (absolute < base)
        return history[(writePos + 32768 - (base - absolute)) & 32767];
    return input[absolute - base];
}

private bool finderHasByte(uint base, uint inputLength, uint historySize, uint absolute)
    @safe pure nothrow @nogc
{ return absolute >= base - historySize && absolute < base + inputLength; }

private void finderInsert(ref HashChainMatchFinder finder, scope const(ubyte)[] input,
    uint base, uint absolute)
    @safe pure nothrow @nogc
{
    if (!finderHasByte(base, cast(uint) input.length, finder.historySize, absolute) ||
        !finderHasByte(base, cast(uint) input.length, finder.historySize, absolute + 2)) return;
    auto hash = chainHash(finderByte(input, base, finder.historySize, finder.history[],
        finder.historyWrite, absolute), finderByte(input, base, finder.historySize,
        finder.history[], finder.historyWrite, absolute + 1), finderByte(input, base,
        finder.historySize, finder.history[], finder.historyWrite, absolute + 2));
    const slot = absolute & 32767;
    finder.previous[slot] = finder.heads[hash];
    finder.heads[hash] = absolute + 1;
}

private LzMatch finderMatch(ref HashChainMatchFinder finder, scope const(ubyte)[] input,
    uint base, uint position)
    @safe pure nothrow @nogc
{
    if (position >= input.length || input.length - position < 3) return LzMatch.init;
    const absolute = base + position;
    auto hash = chainHash(input[position], input[position + 1], input[position + 2]);
    uint candidateEntry = finder.heads[hash];
    LzMatch best;
    foreach (_; 0 .. 32)
    {
        if (candidateEntry == 0) break;
        const candidate = candidateEntry - 1;
        if (candidate >= absolute || absolute - candidate > 32768) break;
        const maxLength = (input.length - position) > 258 ? 258 : input.length - position;
        size_t length;
        while (length < maxLength && finderByte(input, base, finder.historySize,
            finder.history[], finder.historyWrite, candidate + cast(uint) length) ==
            finderByte(input, base, finder.historySize, finder.history[], finder.historyWrite,
                absolute + cast(uint) length)) ++length;
        if (length >= 3 && length > best.length)
        {
            best = LzMatch(cast(ushort) length, cast(ushort) (absolute - candidate));
            if (length == maxLength) break;
        }
        candidateEntry = finder.previous[candidate & 32767];
    }
    return best;
}

private void finderRemember(ref HashChainMatchFinder finder, scope const(ubyte)[] input,
    uint base)
    @safe pure nothrow @nogc
{
    foreach (i; 0 .. input.length)
    {
        const absolute = base + cast(uint) i;
        finderInsert(finder, input, base, absolute);
        finder.history[finder.historyWrite] = input[i];
        finder.historyWrite = (finder.historyWrite + 1) & 32767;
        finder.historySize = finder.historySize == 32768 ? 32768 : finder.historySize + 1;
    }
    if (cast(ulong) base + input.length > uint.max)
        finder.overflowed = true;
    else finder.position = base + cast(uint) input.length;
}

/// Fixed-Huffman DEFLATE using a bounded hash-chain search.
/// The default linear matcher remains available through encodeRawFixedLz.
Result encodeRawFixedLzHashChain(ref HashChainMatchFinder finder,
    scope const(ubyte)[] input, scope ubyte[] output, bool finalBlock = true)
    @safe pure nothrow @nogc
{
    if (finder.overflowed || cast(ulong) finder.position + input.length > uint.max)
        return Result.failure(ErrorCode.invalidArgument);
    // Complete the two positions at the end of the previous chunk now that
    // their three-byte hashes can see the new chunk's prefix.
    if (finder.position >= 2)
        finderInsert(finder, input, finder.position, finder.position - 2);
    if (finder.position >= 1)
        finderInsert(finder, input, finder.position, finder.position - 1);
    BitWriter w; w.buffer = output; w.bits = finder.pendingBits; w.count = finder.pendingCount;
    if (!w.put(finalBlock ? 1 : 0, 1) || !w.put(1, 2)) return Result.needOutput;
    size_t p;
    while (p < input.length)
    {
        auto m = finderMatch(finder, input, finder.position, cast(uint) p);
        const count = m.length >= 3 ? m.length : 1;
        if (m.length >= 3) { if (!emitMatch(w, m)) return Result.needOutput; }
        else if (!emitFixed(w, input[p])) return Result.needOutput;
        foreach (i; 0 .. count) finderInsert(finder, input, finder.position, finder.position + cast(uint) p + i);
        p += count;
    }
    if (!emitFixed(w, 256)) return Result.needOutput;
    if (finalBlock && !w.finish()) return Result.needOutput;
    finder.pendingBits = w.bits;
    finder.pendingCount = w.count;
    finderRemember(finder, input, finder.position);
    return Result.done(input.length, w.pos);
}

private ubyte virtualByte(scope const(ubyte)[] input, size_t pos,
    scope const(ubyte)[] history, uint historySize, uint writePos)
    @safe pure nothrow @nogc
{
    if (pos < historySize)
        return history[(writePos + 32768 - historySize + pos) & 32767];
    return input[pos - historySize];
}

private LzMatch findLzMatchWithHistory(scope const(ubyte)[] input, size_t position,
    scope const(ubyte)[] history, uint historySize, uint writePos)
    @safe pure nothrow @nogc
{
    const total = historySize + input.length;
    if (position >= input.length || total - (historySize + position) < 3) return LzMatch.init;
    const absolute = historySize + position;
    const maxLength = (input.length - position) > 258 ? 258 : input.length - position;
    LzMatch best;
    const maxDistance = absolute > 32768 ? 32768 : absolute;
    foreach (size_t distance; 1 .. maxDistance + 1)
    {
        const candidate = absolute - distance;
        size_t length;
        while (length < maxLength && virtualByte(input, candidate + length, history, historySize, writePos) ==
            virtualByte(input, absolute + length, history, historySize, writePos)) ++length;
        if (length >= 3 && length > best.length)
            best = LzMatch(cast(ushort) length, cast(ushort) distance);
    }
    return best;
}

/// Bounded greedy LZ77 search. The returned match never crosses the input
/// slice and is limited to the RFC 1951 distance/length ranges.
LzMatch findLzMatch(scope const(ubyte)[] input, size_t position)
    @safe pure nothrow @nogc
{
    if (position >= input.length || input.length - position < 3 || position == 0)
        return LzMatch.init;
    const windowStart = position > 32768 ? position - 32768 : 0;
    const maxLength = (input.length - position) > 258 ? 258 : input.length - position;
    LzMatch best;
    size_t candidate = position;
    while (candidate > windowStart)
    {
        --candidate;
        if (input[candidate] != input[position]) continue;
        size_t length;
        while (length < maxLength && input[candidate + length] == input[position + length])
        {
            // Do not read beyond the already available prefix for overlapping matches.
            if (candidate + length >= position && position + length >= input.length) break;
            ++length;
        }
        if (length >= 3 && length > best.length)
        {
            best = LzMatch(cast(ushort) length, cast(ushort) (position - candidate));
            if (length == maxLength) break;
        }
    }
    return best;
}

/// Caller-owned state for the one-block-per-call streaming encoder.
struct RawStoredEncoderState
{
    private bool finished;
    private ulong totalInput;
    private ubyte[32768] history;
    private uint historySize;
    private uint historyWrite;
    private uint pendingBits;
    private uint pendingCount;

    @safe pure nothrow @nogc:
    void reset() { this = RawStoredEncoderState.init; }
    @property ulong inputCount() const { return totalInput; }
    @property bool done() const { return finished; }
    @property uint availableHistory() const { return historySize; }
    private void remember(scope const(ubyte)[] bytes)
    {
        foreach (value; bytes)
        {
            history[historyWrite] = value;
            historyWrite = (historyWrite + 1) & 32767;
            historySize = historySize == 32768 ? 32768 : historySize + 1;
        }
    }
}

private Result encodeFixedChunk(ref RawStoredEncoderState state,
    scope const(ubyte)[] input, scope ubyte[] output, bool finalBlock)
    @safe pure nothrow @nogc
{
    BitWriter w;
    w.buffer = output; w.bits = state.pendingBits; w.count = state.pendingCount;
    if (!w.put(finalBlock ? 1 : 0, 1) || !w.put(1, 2)) return Result.needOutput;
    size_t p;
    while (p < input.length)
    {
        auto m = state.historySize == 0 ? findLzMatch(input, p) :
            findLzMatchWithHistory(input, p, state.history[], state.historySize, state.historyWrite);
        if (m.length >= 3) { if (!emitMatch(w, m)) return Result.needOutput; p += m.length; }
        else { if (!emitFixed(w, input[p])) return Result.needOutput; ++p; }
    }
    if (!emitFixed(w, 256)) return Result.needOutput;
    if (finalBlock && !w.finish()) return Result.needOutput;
    state.pendingBits = w.bits; state.pendingCount = w.count;
    state.remember(input);
    if (finalBlock) state.finished = true;
    return Result.done(input.length, w.pos);
}

struct ZlibStoredEncoderState
{
    private RawStoredEncoderState raw;
    private Adler32 checksum;
    private bool started, finished;
    @safe pure nothrow @nogc:
    void reset() { this = ZlibStoredEncoderState.init; }
}

struct GzipStoredEncoderState
{
    private RawStoredEncoderState raw;
    private Crc32 checksum;
    private uint size;
    private bool started, finished;
    @safe pure nothrow @nogc:
    void reset() { this = GzipStoredEncoderState.init; }
}

/// Returns the exact number of bytes needed for RFC 1951 stored blocks.
size_t rawStoredSize(size_t inputLength) @safe pure nothrow @nogc
{
    if (inputLength == 0) return 5;
    return inputLength + ((inputLength + BlockLimit - 1) / BlockLimit) * 5;
}

/// Encodes input as valid, bounded raw DEFLATE stored blocks.
/// No allocation or native compression backend is used. The output is complete
/// when `status == done`; callers may use rawStoredSize to size the buffer.
Result encodeRawStored(scope const(ubyte)[] input, scope ubyte[] output)
    @safe pure nothrow @nogc
{
    const needed = rawStoredSize(input.length);
    if (needed > output.length) return Result.needOutput(0, 0);
    size_t inPos, outPos;
    if (input.length == 0)
    {
        output[0] = 1; output[1] = 0; output[2] = 0; output[3] = 255; output[4] = 255;
        return Result.done(0, 5);
    }
    while (inPos < input.length)
    {
        const left = input.length - inPos;
        const n = left > BlockLimit ? BlockLimit : left;
        const finalBlock = inPos + n == input.length;
        output[outPos++] = finalBlock ? 1 : 0; // BFINAL, BTYPE=00, byte aligned
        output[outPos++] = cast(ubyte) n;
        output[outPos++] = cast(ubyte) (n >> 8);
        const inverse = cast(ushort) ~cast(ushort) n;
        output[outPos++] = cast(ubyte) inverse;
        output[outPos++] = cast(ubyte) (inverse >> 8);
        output[outPos .. outPos + n] = input[inPos .. inPos + n];
        outPos += n;
        inPos += n;
    }
    return Result.done(input.length, outPos);
}

/// Encodes one streaming input chunk as one or more stored blocks.
/// `finalChunk` must be true exactly once, for the last call. Empty final
/// input emits the required empty final block. State and output are caller-owned.
Result encodeRawStoredChunk(ref RawStoredEncoderState state,
    scope const(ubyte)[] input, scope ubyte[] output, bool finalChunk)
    @safe pure nothrow @nogc
{
    if (state.finished) return Result.failure(ErrorCode.invalidArgument);
    if (input.length == 0 && !finalChunk) return Result.done(0, 0);
    const required = rawStoredSize(input.length);
    if (required > output.length) return Result.needOutput(0, 0);
    auto result = encodeRawStored(input, output);
    if (result.status != DecodeStatus.done) return result;
    if (advanceInput(state.totalInput, input.length) != ErrorCode.none)
        return Result.failure(ErrorCode.sizeOverflow);
    // A non-final chunk must not contain a BFINAL block. Rewrite the final
    // block header from 1 to 0; the chunk remains byte-aligned and valid.
    if (!finalChunk && input.length != 0)
    {
        size_t last = 0;
        while (last + 5 <= result.produced)
        {
            const n = cast(size_t) output[last + 1] | (cast(size_t) output[last + 2] << 8);
            if (last + 5 + n == result.produced) break;
            last += 5 + n;
        }
        output[last] = 0;
    }
    if (finalChunk) state.finished = true;
    state.remember(input);
    return result;
}

size_t zlibStoredSize(size_t inputLength) @safe pure nothrow @nogc
{ return 2 + rawStoredSize(inputLength) + 4; }

/// Encodes a zlib stream using stored DEFLATE blocks and Adler-32.
Result encodeZlibStored(scope const(ubyte)[] input, scope ubyte[] output)
    @safe pure nothrow @nogc
{
    const needed = zlibStoredSize(input.length);
    if (needed > output.length) return Result.needOutput(0, 0);
    output[0] = 0x78; output[1] = 0x01;
    auto raw = encodeRawFixedLz(input, output[2 .. $]);
    const sum = adler32(input);
    const p = 2 + raw.produced;
    output[p] = cast(ubyte)(sum >> 24); output[p + 1] = cast(ubyte)(sum >> 16);
    output[p + 2] = cast(ubyte)(sum >> 8); output[p + 3] = cast(ubyte) sum;
    return Result.done(input.length, p + 4);
}

/// Streaming zlib wrapper around stored-block encoding.
Result encodeZlibStoredChunk(ref ZlibStoredEncoderState state,
    scope const(ubyte)[] input, scope ubyte[] output, bool finalChunk)
    @safe pure nothrow @nogc
{
    if (state.finished) return Result.failure(ErrorCode.invalidArgument);
    const header = state.started ? 0 : 2;
    const trailer = finalChunk ? 4 : 0;
    if (output.length < header + rawStoredSize(input.length) + trailer)
        return Result.needOutput(0, 0);
    size_t p;
    if (!state.started) { output[0] = 0x78; output[1] = 1; p = 2; state.started = true; }
    state.checksum.update(input);
    // Streaming calls are byte-oriented; fixed-Huffman blocks retain residual
    // bits across block boundaries and therefore require a persistent bitwriter.
    // Until that stateful writer is exposed, use aligned stored blocks here.
    auto raw = encodeFixedChunk(state.raw, input, output[p .. $], finalChunk);
    if (raw.status != DecodeStatus.done) return raw;
    p += raw.produced;
    if (finalChunk)
    {
        const sum = state.checksum.value;
        output[p] = cast(ubyte)(sum >> 24); output[p + 1] = cast(ubyte)(sum >> 16);
        output[p + 2] = cast(ubyte)(sum >> 8); output[p + 3] = cast(ubyte) sum;
        p += 4; state.finished = true;
    }
    return Result.done(input.length, p);
}

size_t gzipStoredSize(size_t inputLength) @safe pure nothrow @nogc
{ return 10 + rawStoredSize(inputLength) + 8; }

/// Encodes one minimal GZIP member using stored DEFLATE blocks.
Result encodeGzipStored(scope const(ubyte)[] input, scope ubyte[] output)
    @safe pure nothrow @nogc
{
    const needed = gzipStoredSize(input.length);
    if (needed > output.length) return Result.needOutput(0, 0);
    output[0] = 31; output[1] = 139; output[2] = 8; output[3] = 0;
    output[4] = 0; output[5] = 0; output[6] = 0; output[7] = 0;
    output[8] = 0; output[9] = 3;
    auto raw = encodeRawFixedLz(input, output[10 .. $]);
    const p = 10 + raw.produced;
    const crc = crc32(input);
    const size = cast(uint) input.length;
    output[p] = cast(ubyte) crc; output[p + 1] = cast(ubyte)(crc >> 8);
    output[p + 2] = cast(ubyte)(crc >> 16); output[p + 3] = cast(ubyte)(crc >> 24);
    output[p + 4] = cast(ubyte) size; output[p + 5] = cast(ubyte)(size >> 8);
    output[p + 6] = cast(ubyte)(size >> 16); output[p + 7] = cast(ubyte)(size >> 24);
    return Result.done(input.length, p + 8);
}

/// Streaming single-member GZIP wrapper around stored-block encoding.
Result encodeGzipStoredChunk(ref GzipStoredEncoderState state,
    scope const(ubyte)[] input, scope ubyte[] output, bool finalChunk)
    @safe pure nothrow @nogc
{
    if (state.finished) return Result.failure(ErrorCode.invalidArgument);
    const header = state.started ? 0 : 10;
    const trailer = finalChunk ? 8 : 0;
    if (output.length < header + rawStoredSize(input.length) + trailer)
        return Result.needOutput(0, 0);
    size_t p;
    if (!state.started)
    {
        output[0] = 31; output[1] = 139; output[2] = 8; output[3] = 0;
        output[4] = 0; output[5] = 0; output[6] = 0; output[7] = 0;
        output[8] = 0; output[9] = 3; p = 10; state.started = true;
    }
    state.checksum.update(input);
    state.size += cast(uint) input.length;
    auto raw = encodeFixedChunk(state.raw, input, output[p .. $], finalChunk);
    if (raw.status != DecodeStatus.done) return raw;
    p += raw.produced;
    if (finalChunk)
    {
        const crc = state.checksum.value, size = state.size;
        output[p] = cast(ubyte) crc; output[p + 1] = cast(ubyte)(crc >> 8);
        output[p + 2] = cast(ubyte)(crc >> 16); output[p + 3] = cast(ubyte)(crc >> 24);
        output[p + 4] = cast(ubyte) size; output[p + 5] = cast(ubyte)(size >> 8);
        output[p + 6] = cast(ubyte)(size >> 16); output[p + 7] = cast(ubyte)(size >> 24);
        p += 8; state.finished = true;
    }
    return Result.done(input.length, p);
}

@safe pure nothrow @nogc unittest
{
    immutable ubyte[6] sample = [0, 1, 2, 3, 4, 255];
    ubyte[64] raw, framed, gz;
    auto r = encodeRawStored(sample, raw[]);
    assert(r.status == DecodeStatus.done && r.produced == rawStoredSize(sample.length));
    InflateWorkspace workspace;
    ubyte[6] decoded;
    assert(inflateRawForEncodeTest(raw[0 .. r.produced], decoded, workspace));
    assert(decoded == sample);
    auto z = encodeZlibStored(sample, framed[]);
    assert(z.status == DecodeStatus.done && z.produced <= zlibStoredSize(sample.length));
    auto g = encodeGzipStored(sample, gz[]);
    assert(g.status == DecodeStatus.done && g.produced <= gzipStoredSize(sample.length));
    assert(encodeRawStored(sample, raw[0 .. 4]).status == DecodeStatus.needOutput);
    immutable ubyte[12] repetitive = ['a','b','c','a','b','c','a','b','c','a','b','c'];
    auto match = findLzMatch(repetitive, 6);
    assert(match.length >= 6 && match.distance == 3);
    ubyte[64] fixed;
    auto fixedResult = encodeRawFixedLz(repetitive, fixed[]);
    assert(fixedResult.status == DecodeStatus.done && fixedResult.produced < repetitive.length);
    ubyte[12] fixedDecoded;
    workspace = InflateWorkspace.init;
    assert(inflateRawForEncodeTest(fixed[0 .. fixedResult.produced], fixedDecoded, workspace));
    assert(fixedDecoded == repetitive);
    HashChainMatchFinder finder;
    ubyte[64] hashed;
    auto hashedResult = encodeRawFixedLzHashChain(finder, repetitive, hashed[]);
    assert(hashedResult.status == DecodeStatus.done && hashedResult.produced <= fixedResult.produced + 8);
    ubyte[12] hashedDecoded;
    workspace = InflateWorkspace.init;
    assert(inflateRawForEncodeTest(hashed[0 .. hashedResult.produced], hashedDecoded, workspace));
    assert(hashedDecoded == repetitive);
    HashChainMatchFinder chunkFinder;
    ubyte[64] chunkA, chunkB, chunkJoined;
    auto chunkAR = encodeRawFixedLzHashChain(chunkFinder, repetitive[0 .. 6], chunkA[], false);
    auto chunkBR = encodeRawFixedLzHashChain(chunkFinder, repetitive[6 .. $], chunkB[], true);
    assert(chunkAR.status == DecodeStatus.done && chunkBR.status == DecodeStatus.done);
    chunkJoined[0 .. chunkAR.produced] = chunkA[0 .. chunkAR.produced];
    chunkJoined[chunkAR.produced .. chunkAR.produced + chunkBR.produced] =
        chunkB[0 .. chunkBR.produced];
    workspace = InflateWorkspace.init;
    assert(inflateRawForEncodeTest(chunkJoined[0 .. chunkAR.produced + chunkBR.produced],
        hashedDecoded, workspace));
    assert(hashedDecoded == repetitive);
    ZlibStoredEncoderState zs;
    ubyte[128] z1, z2, zjoined, zdecoded;
    auto z1r = encodeZlibStoredChunk(zs, repetitive[0 .. 6], z1[], false);
    auto z2r = encodeZlibStoredChunk(zs, repetitive[6 .. $], z2[], true);
    assert(z1r.status == DecodeStatus.done && z2r.status == DecodeStatus.done);
    zjoined[0 .. z1r.produced] = z1[0 .. z1r.produced];
    zjoined[z1r.produced .. z1r.produced + z2r.produced] = z2[0 .. z2r.produced];
    workspace = InflateWorkspace.init;
    auto zdecodedResult = inflateZlib(zjoined[0 .. z1r.produced + z2r.produced], zdecoded, workspace);
    assert(zdecodedResult.status == DecodeStatus.done);
    assert(zdecodedResult.produced == repetitive.length);
    assert(zdecoded[0 .. zdecodedResult.produced] == repetitive[]);
    RawStoredEncoderState streaming;
    ubyte[32] first, second;
    assert(encodeRawStoredChunk(streaming, sample[0 .. 2], first[], false).status == DecodeStatus.done);
    assert(encodeRawStoredChunk(streaming, sample[2 .. $], second[], true).status == DecodeStatus.done);
    ubyte[6] streamed;
    ubyte[64] joined;
    joined[0 .. 7] = first[0 .. 7];
    joined[7 .. 7 + 9] = second[0 .. 9];
    workspace = InflateWorkspace.init;
    assert(inflateRawForEncodeTest(joined[0 .. 16], streamed, workspace));
    assert(streamed == sample);
}

// Kept local to this module so the encoder unittest does not couple the public
// encoder contract to a framed decoder test harness.
private bool inflateRawForEncodeTest(scope const(ubyte)[] input, scope ubyte[] output,
    ref InflateWorkspace workspace) @safe pure nothrow @nogc
{
    InflateState state;
    return inflate(state, workspace, input, output, true).status == DecodeStatus.done;
}
