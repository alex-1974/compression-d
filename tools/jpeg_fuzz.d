module jpeg_fuzz;

import compression.jpeg;
import std.file : dirEntries, SpanMode, read;
import std.stdio : writefln;

void main(string[] args)
{
    assert(args.length == 2);
    size_t files, accepted;
    foreach (entry; dirEntries(args[1], SpanMode.shallow))
    {
        if (!entry.isFile) continue;
        const bytes = cast(const(ubyte)[]) read(entry.name);
        Limits limits;
        limits.maxFileBytes = 2 * 1024 * 1024;
        const frame = inspectJpegFrame(bytes, limits);
        if (!frame.ok) { ++files; continue; }
        MutablePlane[] planes;
        ubyte[][3] storage;
        foreach (size_t c; 0 .. frame.info.components)
        {
            const h = frame.horizontal[c], v = frame.vertical[c];
            const width = (cast(size_t)frame.info.width + h - 1) / h;
            const height = (cast(size_t)frame.info.height + v - 1) / v;
            storage[c] = new ubyte[width * height];
            planes ~= MutablePlane(storage[c], width);
        }
        const result = decodeJpegPlanes(bytes, planes, limits);
        ++files;
        if (result.ok) ++accepted;
    }
    writefln("jpeg-fuzz files=%s accepted=%s", files, accepted);
}
