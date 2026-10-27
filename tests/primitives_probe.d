module primitives_probe;

import compression.bitstream;
import compression.core;
import compression.huffman;

void probe() @safe pure nothrow @nogc
{
    ubyte[2] lengths = [1, 1];
    ubyte[2] input = [0xA5, 0x5A];
    foreach (rootBits; AliasSeq!(0, 9))
    {
        HuffmanTable!rootBits workspace;
        assert(workspace.build(lengths) == ErrorCode.none);
        assert(workspace.isReady);
        BitReader reader;
        size_t cursor;
        assert(reader.peek(input, cursor, 1).value == 1);
        assert(workspace.decode(reader, input, cursor, true).symbol == 1);
        assert(reader.bufferedBits == 7);
        assert(reader.drop(input, cursor, 2).status == DecodeStatus.done);
        assert(reader.alignToByte() == 5);
        assert(reader.read(input, cursor, 8).value == 0x5A);
        reader.reset();
    }
}

import std.meta : AliasSeq;

void main() @safe nothrow @nogc { probe(); }
