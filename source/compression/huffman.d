/// Canonical Huffman tables, bounded to DEFLATE's 288 symbols and 15 code bits.
module compression.huffman;

import compression.bitstream : BitReader;
import compression.core : DecodeStatus, ErrorCode;

enum TreeKind : ubyte
{
    complete,      /// Generic complete prefix tree, e.g. RFC 1951's example.
    codeLength,    /// At most 19 symbols, at most 7 bits; must be complete.
    literalLength, /// 257..288 symbols, requires end-of-block symbol 256.
    distance,      /// At most 32 symbols; an empty distance alphabet is allowed.
}

struct SymbolResult
{
    DecodeStatus status = DecodeStatus.needInput;
    ushort symbol;
    ErrorCode error = ErrorCode.none;
}

/** Caller-owned typed workspace. rootBits=0 is compact canonical lookup;
    rootBits=9 adds a 512-entry fast prefix table with canonical fallback.
    Both use transactional bit reads: success consumes only the symbol's bytes.
    A failed build invalidates the previous table. No input slice is retained. */
struct HuffmanTable(uint rootBits = 9)
{
    static assert(rootBits == 0 || rootBits == 9, "Supported root widths are 0 and 9");
    enum maxSymbols = 288;
    enum maxCodeBits = 15;

    private ushort[16] counts;
    private ushort[16] offsets;
    private uint[16] firstCodes;
    private ushort[maxSymbols] symbols;
    private ubyte maximum;
    private bool ready;
    static if (rootBits != 0)
    {
        private struct Entry
        {
            ushort symbol;
            ubyte width;
        }
        private Entry[1 << rootBits] root;
    }

    @safe pure nothrow @nogc:

    @property bool isReady() const { return ready; }

    ErrorCode build(scope const(ubyte)[] lengths, TreeKind kind = TreeKind.complete)
    {
        ready = false;
        maximum = 0;
        counts[] = 0;
        offsets[] = 0;
        firstCodes[] = 0;
        static if (rootBits != 0)
            root[] = Entry.init;
        if (lengths.length == 0 || lengths.length > maxSymbols ||
            cast(uint) kind > TreeKind.max)
            return ErrorCode.invalidArgument;
        if ((kind == TreeKind.codeLength && lengths.length > 19) ||
            (kind == TreeKind.distance && lengths.length > 32) ||
            (kind == TreeKind.literalLength && lengths.length < 257))
            return ErrorCode.invalidArgument;
        const limit = kind == TreeKind.codeLength ? 7 : maxCodeBits;
        uint used;
        foreach (length; lengths)
        {
            if (length > limit)
                return ErrorCode.invalidHuffmanTree;
            if (length != 0)
            {
                ++counts[length];
                ++used;
                if (length > maximum)
                    maximum = length;
            }
        }
        if (kind == TreeKind.literalLength && lengths[256] == 0)
            return ErrorCode.invalidHuffmanTree;
        if (used == 0)
        {
            if (kind != TreeKind.distance)
                return ErrorCode.invalidHuffmanTree;
            ready = true; // Every attempted symbol decode fails without reading.
            return ErrorCode.none;
        }
        int left = 1;
        foreach (uint width; 1 .. maxCodeBits + 1)
        {
            left = left * 2 - counts[width];
            if (left < 0)
                return ErrorCode.invalidHuffmanTree;
        }
        const singletonAllowed = kind == TreeKind.literalLength || kind == TreeKind.distance;
        if (left != 0 && !(singletonAllowed && used == 1 && maximum == 1))
            return ErrorCode.invalidHuffmanTree;

        uint code;
        ushort offset;
        foreach (uint width; 1 .. maxCodeBits + 1)
        {
            code = (code + counts[width - 1]) << 1;
            firstCodes[width] = code;
            offsets[width] = offset;
            offset += counts[width];
        }
        auto nextOffset = offsets;
        auto nextCode = firstCodes;
        foreach (index, width; lengths)
        {
            if (width == 0)
                continue;
            symbols[nextOffset[width]++] = cast(ushort) index;
            const canonical = nextCode[width]++;
            static if (rootBits != 0)
            {
                if (width <= rootBits)
                {
                    uint reversed;
                    foreach (uint bit; 0 .. width)
                        reversed = (reversed << 1) | ((canonical >> bit) & 1);
                    for (uint slot = reversed; slot < root.length; slot += 1U << width)
                        root[slot] = Entry(cast(ushort) index, width);
                }
            }
        }
        ready = true;
        return ErrorCode.none;
    }

    SymbolResult decode(ref BitReader reader, scope const(ubyte)[] input,
        ref size_t cursor, bool endOfInput = false) const
    {
        if (!ready || cursor > input.length)
            return SymbolResult(DecodeStatus.error, 0, ErrorCode.invalidArgument);
        if (maximum == 0)
            return SymbolResult(DecodeStatus.error, 0, ErrorCode.invalidData);
        static if (rootBits != 0)
        {
            auto prefix = reader.peek(input, cursor, rootBits);
            if (prefix.status == DecodeStatus.done)
            {
                const entry = root[prefix.value];
                if (entry.width != 0)
                {
                    reader.drop(input, cursor, entry.width);
                    return SymbolResult(DecodeStatus.done, entry.symbol);
                }
            }
        }
        // Also handles short codes at EOF without requiring rootBits lookahead.
        auto trial = reader;
        auto next = cursor;
        uint code;
        foreach (uint width; 1 .. cast(uint) maximum + 1)
        {
            const bit = trial.read(input, next, 1, endOfInput);
            if (bit.status != DecodeStatus.done)
                return SymbolResult(bit.status, 0, bit.error);
            code = (code << 1) | bit.value;
            const first = firstCodes[width];
            if (code >= first && code - first < counts[width])
            {
                const symbol = symbols[offsets[width] + code - first];
                reader = trial;
                cursor = next;
                return SymbolResult(DecodeStatus.done, symbol);
            }
        }
        return SymbolResult(DecodeStatus.error, 0, ErrorCode.invalidData);
    }
}
