pub fn main() !void {
    const file = @embedFile("./haystack.txt");
    const haystack = file[0..];
    const needle = "newsletter";

    var use_simd = false;
    var it = std.process.args();
    while (it.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--simd")) {
            use_simd = true;
            break;
        }
    }
    var idx: ?usize = undefined;
    if (use_simd) {
        idx = find_substr_simd(needle, haystack);
    } else {
        idx = find_substr(needle, haystack);
    }

    std.debug.print("Index: {}\n", .{idx.?});
}

fn find_substr(needle: []const u8, haystack: []const u8) ?usize {
    return std.mem.indexOf(u8, haystack, needle);
}

fn find_substr_simd(needle: []const u8, haystack: []const u8) ?usize {
    const n = haystack.len;
    const k = needle.len;
    if (k == 0 or k > n) return null;
    const U8x32 = @Vector(32, u8);
    const first: U8x32 = @splat(needle[0]);
    const last: U8x32 = @splat(needle[needle.len - 1]);

    var count: usize = 0;
    var i: usize = 0;
    while (i + k + 32 <= n) : (i += 32) {
        const block_first: U8x32 = haystack[i..][0..32].*;
        const block_last: U8x32 = haystack[i + k - 1 ..][0..32].*;
        const eq_first = first == block_first;
        const eq_last = last == block_last;
        var mask: u32 = @bitCast(eq_first & eq_last);
        while (mask != 0) {
            count += 1;
            const bitpos = @ctz(mask); // count trailing zeroes
            if (std.mem.eql(u8, haystack.ptr[i + bitpos + 1 ..][0 .. k - 1], needle[1..])) {
                std.debug.print("Found at count: {}\n", .{count});
                return i + bitpos;
            }
            mask = mask & (mask - 1); // clear the lowest set bit
        }
    }
    // Fallback to scalar search for the tail
    if (i < n) {
        if (std.mem.indexOf(u8, haystack[i..], needle)) |rel_idx| {
            return i + rel_idx;
        }
    }
    return null;
}

const std = @import("std");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("substr_lib");
