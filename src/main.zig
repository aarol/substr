//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

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
    // if (idx != 24957) {
    //     @panic("Wrong index found, expected 24957");
    // }
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

    var i: usize = 0;
    while (i + k + 32 <= n) : (i += 32) {
        const block_first: U8x32 = haystack[i..][0..32].*;
        const block_last: U8x32 = haystack[i + k - 1 ..][0..32].*;
        const eq_first = first == block_first;
        const eq_last = last == block_last;
        var mask: std.bit_set.IntegerBitSet(32) = .{ .mask = @bitCast(eq_first & eq_last) };
        while (mask.count() > 0) {
            const bitpos = mask.findFirstSet().?;
            if (std.mem.eql(u8, haystack[i + bitpos + 1 ..][0 .. k - 1], needle[1..])) {
                return i + bitpos;
            }
            _ = mask.toggleFirstSet();
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

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}

const std = @import("std");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("substr_lib");
