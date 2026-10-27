// Test-only subprocess protocol. No allocation restrictions apply to this tool.
module inflate_oracle;
import compression.core;
import compression.deflate;
import std.stdio;
import std.string : strip;
import std.conv : to;
import std.digest.sha : sha256Of;
import std.digest : toHexString;

void main()
{
    InflateWorkspace workspace;
    auto output = new ubyte[1_048_576];
    foreach (line; stdin.byLine())
    {
        auto text = strip(line);
        auto input = new ubyte[text.length / 2];
        foreach (i, ref value; input)
            value = to!ubyte(text[i * 2 .. i * 2 + 2], 16);
        auto result = inflateRaw(input, output, workspace, DecodeLimits(output.length));
        writefln("%s %s %s %s %s", result.status, result.error.code,
            result.consumed, result.produced, toHexString(sha256Of(output[0 .. result.produced])));
    }
}
