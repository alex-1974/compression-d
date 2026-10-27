module framing_oracle;
import compression.core;
import compression.deflate;
import compression.zlib;
import compression.gzip;
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
        const mode = line[0];
        auto text = strip(line[2 .. $]);
        auto input = new ubyte[text.length / 2];
        foreach (i, ref value; input)
            value = to!ubyte(text[i * 2 .. i * 2 + 2], 16);
        auto result = mode == 'z' ? inflateZlib(input, output, workspace, DecodeLimits(output.length)) :
            inflateGzip(input, output, workspace, DecodeLimits(output.length), mode == 'a');
        writefln("%s %s %s %s %s", result.status, result.error.code, result.consumed,
            result.produced, toHexString(sha256Of(output[0 .. result.produced])));
    }
}
