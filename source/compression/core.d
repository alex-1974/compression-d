/** Experimental contracts shared by raw decoders and framed containers.
    See docs/CORE_CONTRACT.md. No codec or allocation is provided here. */
module compression.core;

/// Streaming progress; a default Result requests input and reports no progress.
enum DecodeStatus : ubyte
{
    needInput,
    needOutput,
    done,
    error,
}

/// Stable categories within this experimental contract, not numeric ABI values.
enum ErrorCode : ubyte
{
    none,
    invalidArgument,
    workspaceTooSmall,
    sizeOverflow,
    outputLimitExceeded,
    expansionLimitExceeded,
    truncatedInput,
    invalidHeader,
    invalidData,
    invalidHuffmanTree,
    invalidDistance,
    checksumMismatch,
    dictionaryRequired,
    unsupportedFeature,
}

/// Error location is an absolute, zero-based byte offset in the encoded stream.
struct DecodeError
{
    ErrorCode code = ErrorCode.none;
    /// Unknown or inapplicable locations use this sentinel, never an input slice.
    ulong inputOffset = unknownOffset;
    enum ulong unknownOffset = ulong.max;
}

/// Per-call counts; cumulative counters live in caller-owned decoder state.
struct Result
{
    DecodeStatus status = DecodeStatus.needInput;
    size_t consumed;
    size_t produced;
    DecodeError error;

    @safe pure nothrow @nogc:

    static Result done(size_t consumed = 0, size_t produced = 0)
    {
        return Result(DecodeStatus.done, consumed, produced);
    }

    static Result needInput(size_t consumed = 0, size_t produced = 0)
    {
        return Result(DecodeStatus.needInput, consumed, produced);
    }

    static Result needOutput(size_t consumed = 0, size_t produced = 0)
    {
        return Result(DecodeStatus.needOutput, consumed, produced);
    }

    /// Callers must supply a non-none code. Invalid codes become invalidArgument.
    static Result failure(ErrorCode code, size_t consumed = 0,
        size_t produced = 0, ulong inputOffset = DecodeError.unknownOffset)
    {
        if (code == ErrorCode.none || cast(uint) code > ErrorCode.max)
            code = ErrorCode.invalidArgument;
        return Result(DecodeStatus.error, consumed, produced,
            DecodeError(code, inputOffset));
    }
}

/// Inclusive cumulative bounds. Defaults disable policy limits, not overflow checks.
struct DecodeLimits
{
    ulong maxOutputBytes = ulong.max;
    /// Integer output/input ratio. Zero disables this bound; zero input permits
    /// zero output when enabled. Input includes framing for a framed decoder.
    ulong maxExpansionRatio = 0;

    /** Validate a proposed output increment before writing any of it.
        totalInput and totalOutput are cumulative stream counts, not slice sizes.
        Error precedence: arithmetic overflow, absolute bound, ratio bound.
        Never multiplies or adds unchecked, including for ulong.max values. */
    ErrorCode checkGrowth(ulong totalInput, ulong totalOutput,
        ulong additionalOutput) const @safe pure nothrow @nogc
    {
        if (additionalOutput > ulong.max - totalOutput)
            return ErrorCode.sizeOverflow;
        const prospective = totalOutput + additionalOutput;
        if (prospective > maxOutputBytes)
            return ErrorCode.outputLimitExceeded;
        if (maxExpansionRatio != 0)
        {
            // If the product would overflow, every representable output fits.
            if (totalInput <= ulong.max / maxExpansionRatio &&
                prospective > totalInput * maxExpansionRatio)
                return ErrorCode.expansionLimitExceeded;
        }
        return ErrorCode.none;
    }
}

/// Checked cumulative input accounting; leaves total unchanged on overflow.
ErrorCode advanceInput(ref ulong total, ulong consumed) @safe pure nothrow @nogc
{
    if (consumed > ulong.max - total)
        return ErrorCode.sizeOverflow;
    total += consumed;
    return ErrorCode.none;
}

unittest
{
    assert(Result.init.status == DecodeStatus.needInput);
    assert(Result.init.consumed == 0 && Result.init.produced == 0);
    assert(Result.init.error.code == ErrorCode.none);
    assert(Result.init.error.inputOffset == DecodeError.unknownOffset);
    foreach (r; [Result.done(2, 3), Result.needInput(2, 3), Result.needOutput(2, 3)])
    {
        assert(r.consumed == 2 && r.produced == 3);
        assert(r.error.code == ErrorCode.none);
    }
    auto failure = Result.failure(ErrorCode.truncatedInput, 2, 3, 42);
    assert(failure.status == DecodeStatus.error);
    assert(failure.consumed == 2 && failure.produced == 3);
    assert(failure.error.code == ErrorCode.truncatedInput);
    assert(failure.error.inputOffset == 42);
    assert(Result.failure(ErrorCode.none).error.code == ErrorCode.invalidArgument);
    assert(Result.failure(cast(ErrorCode) 255).error.code == ErrorCode.invalidArgument);
}

unittest
{
    with (ErrorCode)
    {
        assert(DecodeLimits.init.checkGrowth(0, 0, ulong.max) == none);
        assert(DecodeLimits.init.checkGrowth(0, ulong.max, 1) == sizeOverflow);
        assert(DecodeLimits(0).checkGrowth(0, 0, 0) == none);
        assert(DecodeLimits(0).checkGrowth(1, 0, 1) == outputLimitExceeded);
        assert(DecodeLimits(10).checkGrowth(1, 4, 6) == none);
        assert(DecodeLimits(10).checkGrowth(1, 4, 7) == outputLimitExceeded);
        auto ratio = DecodeLimits(ulong.max, 3);
        assert(ratio.checkGrowth(0, 0, 0) == none);
        assert(ratio.checkGrowth(0, 0, 1) == expansionLimitExceeded);
        assert(ratio.checkGrowth(2, 4, 2) == none);
        assert(ratio.checkGrowth(2, 4, 3) == expansionLimitExceeded);
        const boundaryInput = ulong.max / 3;
        assert(ratio.checkGrowth(boundaryInput, 0, boundaryInput * 3) == none);
        assert(ratio.checkGrowth(boundaryInput + 1, 0, ulong.max) == none);
        assert(ratio.checkGrowth(ulong.max, 0, ulong.max) == none);
        assert(DecodeLimits(ulong.max, ulong.max).checkGrowth(1, 0, ulong.max) == none);
        assert(DecodeLimits(ulong.max, ulong.max).checkGrowth(2, 0, ulong.max) == none);
        assert(DecodeLimits(1, 1).checkGrowth(0, 1, 1) == outputLimitExceeded);
        assert(DecodeLimits(0, 1).checkGrowth(0, ulong.max, 1) == sizeOverflow);

        // Chunking cannot reset either bound: cumulative counts are authoritative.
        auto limits = DecodeLimits(12, 2);
        assert(limits.checkGrowth(3, 0, 6) == none);
        assert(limits.checkGrowth(5, 6, 4) == none);
        assert(limits.checkGrowth(5, 10, 1) == expansionLimitExceeded);
        assert(limits.checkGrowth(7, 10, 3) == outputLimitExceeded);
        ulong total = ulong.max - 2;
        assert(advanceInput(total, 2) == none && total == ulong.max);
        assert(advanceInput(total, 1) == sizeOverflow && total == ulong.max);

        // A small exact-arithmetic oracle covers both bounds in combination.
        foreach (ulong input; 0 .. 9)
        foreach (ulong output; 0 .. 9)
        foreach (ulong increment; 0 .. 9)
        foreach (ulong multiplier; 0 .. 5)
        {
            const proposed = output + increment;
            const expected = proposed > 12 ? outputLimitExceeded :
                multiplier != 0 && proposed > input * multiplier ?
                expansionLimitExceeded : none;
            assert(DecodeLimits(12, multiplier).checkGrowth(input, output,
                increment) == expected);
        }
    }
}
