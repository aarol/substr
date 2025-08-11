pub fn main() !void {
    const haystack_big = @embedFile("./haystack.txt");
    const haystack_small = @embedFile("./haystack-small.txt");
    const needle = "newsletter";

    var command = &find_substr;
    var haystack: []const u8 = haystack_big;

    var it = std.process.args();
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--simd")) {
            command = &find_substr_simd;
            break;
        }
        if (std.mem.eql(u8, arg, "--simdv2")) {
            command = &find_substr_simd_v2;
            break;
        }
        if (std.mem.eql(u8, arg, "--simdv3")) {
            command = &find_substr_simd_v3;
            break;
        }
        if (std.mem.eql(u8, arg, "--small")) {
            haystack = haystack_small;
        }
    }

    const idx = command(needle, haystack);

    std.debug.print("Index: {}\n", .{idx.?});
}

fn find_substr(needle: []const u8, haystack: []const u8) ?usize {
    return std.mem.indexOf(u8, haystack, needle);
}

fn find_substr_simd(needle: []const u8, haystack: []const u8) ?usize {
    const n = haystack.len;
    const k = needle.len;

    if (k == 0 or k > n) return null;
    const Block = @Vector(32, u8);
    const first_letter: Block = @splat(needle[0]);
    const last_letter: Block = @splat(needle[k - 1]);

    var i: usize = 0;
    while (i + k + 32 <= n) : (i += 32) {
        const first_block: Block = haystack[i..][0..32].*;
        const last_block: Block = haystack[i + k - 1 ..][0..32].*;
        const eq_first = first_letter == first_block;
        const eq_last = last_letter == last_block;
        var mask: std.bit_set.IntegerBitSet(32) = .{ .mask = @bitCast(eq_first & eq_last) };
        while (mask.findFirstSet()) |bitpos| {
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

fn find_substr_simd_v2(needle: []const u8, haystack: []const u8) ?usize {
    const n = haystack.len;
    const k = needle.len;
    if (k == 0 or k > n) return null;

    const Block = @Vector(32, u8);

    const first_offset, const second_offset =
        find_rarest(needle) orelse [2]usize{ 0, @intCast(k - 1) };

    const first_letter: Block = @splat(needle[first_offset]);
    const second_letter: Block = @splat(needle[second_offset]);

    var i: usize = 0;
    while (i + k + 32 <= n) : (i += 32) {
        const first_block: Block = haystack[i + first_offset ..][0..32].*;
        const second_block: Block = haystack[i + second_offset ..][0..32].*;
        const eq_first = first_letter == first_block;
        const eq_second = second_letter == second_block;
        var mask: std.bit_set.IntegerBitSet(32) = .{ .mask = @bitCast(eq_first & eq_second) };
        while (mask.findFirstSet()) |bitpos| {
            if (std.mem.eql(u8, haystack[i + bitpos ..][0..k], needle)) {
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

fn find_substr_simd_v3(needle: []const u8, haystack: []const u8) ?usize {
    const n = haystack.len;
    const k = needle.len;
    if (k == 0 or k > n) return null;

    const block_size = std.simd.suggestVectorLength(u8).?; // assumes SIMD support
    const Block = @Vector(block_size, u8);

    const first_offset, const second_offset =
        find_rarest(needle) orelse [2]usize{ 0, @intCast(k - 1) };

    const first_letter: Block = @splat(needle[first_offset]);
    const second_letter: Block = @splat(needle[second_offset]);

    var i: usize = 0;
    while (i + k + block_size <= n) : (i += block_size) {
        const first_block: Block = haystack[i + first_offset ..][0..block_size].*;
        const second_block: Block = haystack[i + second_offset ..][0..block_size].*;
        const eq_first = first_letter == first_block;
        const eq_second = second_letter == second_block;
        var mask: std.bit_set.IntegerBitSet(block_size) = .{ .mask = @bitCast(eq_first & eq_second) };
        while (mask.findFirstSet()) |bitpos| {
            if (std.mem.eql(u8, haystack[i + bitpos ..][0..k], needle)) {
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

// Finds the rarest two values in needle and returns their indices.
// Author: BurntSushi
// https://github.com/BurntSushi/memchr/blob/3962118774ac511580c5b40fd14323e31629fa52/src/arch/all/packedpair/mod.rs#L163
fn find_rarest(needle: []const u8) ?[2]usize {
    if (needle.len <= 1 or needle.len > 256) {
        return null;
    }

    var rare1: u8 = needle[0];
    var index1: usize = 0;
    var rare2: u8 = needle[1];
    var index2: usize = 1;
    if (RANK[rare2] < RANK[rare1]) {
        std.mem.swap(u8, &rare1, &rare2);
        std.mem.swap(usize, &index1, &index2);
    }
    for (needle[2..], 2..) |b, i| {
        if (RANK[b] < RANK[rare1]) {
            rare2 = rare1;
            index2 = index1;
            rare1 = b;
            index1 = @intCast(i);
        } else if (b != rare1 and RANK[b] < RANK[rare2]) {
            rare2 = b;
            index2 = @intCast(i);
        }
    }

    std.debug.assert(index1 != index2);
    return [2]usize{ index1, index2 };
}

// Precalculated background frequency distribution
// Smaller = less common
// Author: BurntSushi
// https://github.com/BurntSushi/memchr/blob/master/src/arch/all/packedpair/default_rank.rs
const RANK = [256]u8{
    55, // '\x00'
    52, // '\x01'
    51, // '\x02'
    50, // '\x03'
    49, // '\x04'
    48, // '\x05'
    47, // '\x06'
    46, // '\x07'
    45, // '\x08'
    103, // '\t'
    242, // '\n'
    66, // '\x0b'
    67, // '\x0c'
    229, // '\r'
    44, // '\x0e'
    43, // '\x0f'
    42, // '\x10'
    41, // '\x11'
    40, // '\x12'
    39, // '\x13'
    38, // '\x14'
    37, // '\x15'
    36, // '\x16'
    35, // '\x17'
    34, // '\x18'
    33, // '\x19'
    56, // '\x1a'
    32, // '\x1b'
    31, // '\x1c'
    30, // '\x1d'
    29, // '\x1e'
    28, // '\x1f'
    255, // ' '
    148, // '!'
    164, // '"'
    149, // '#'
    136, // '$'
    160, // '%'
    155, // '&'
    173, // "'"
    221, // '('
    222, // ')'
    134, // '*'
    122, // '+'
    232, // ','
    202, // '-'
    215, // '.'
    224, // '/'
    208, // '0'
    220, // '1'
    204, // '2'
    187, // '3'
    183, // '4'
    179, // '5'
    177, // '6'
    168, // '7'
    178, // '8'
    200, // '9'
    226, // ':'
    195, // ';'
    154, // '<'
    184, // '='
    174, // '>'
    126, // '?'
    120, // '@'
    191, // 'A'
    157, // 'B'
    194, // 'C'
    170, // 'D'
    189, // 'E'
    162, // 'F'
    161, // 'G'
    150, // 'H'
    193, // 'I'
    142, // 'J'
    137, // 'K'
    171, // 'L'
    176, // 'M'
    185, // 'N'
    167, // 'O'
    186, // 'P'
    112, // 'Q'
    175, // 'R'
    192, // 'S'
    188, // 'T'
    156, // 'U'
    140, // 'V'
    143, // 'W'
    123, // 'X'
    133, // 'Y'
    128, // 'Z'
    147, // '['
    138, // '\\'
    146, // ']'
    114, // '^'
    223, // '_'
    151, // '`'
    249, // 'a'
    216, // 'b'
    238, // 'c'
    236, // 'd'
    253, // 'e'
    227, // 'f'
    218, // 'g'
    230, // 'h'
    247, // 'i'
    135, // 'j'
    180, // 'k'
    241, // 'l'
    233, // 'm'
    246, // 'n'
    244, // 'o'
    231, // 'p'
    139, // 'q'
    245, // 'r'
    243, // 's'
    251, // 't'
    235, // 'u'
    201, // 'v'
    196, // 'w'
    240, // 'x'
    214, // 'y'
    152, // 'z'
    182, // '{'
    205, // '|'
    181, // '}'
    127, // '~'
    27, // '\x7f'
    212, // '\x80'
    211, // '\x81'
    210, // '\x82'
    213, // '\x83'
    228, // '\x84'
    197, // '\x85'
    169, // '\x86'
    159, // '\x87'
    131, // '\x88'
    172, // '\x89'
    105, // '\x8a'
    80, // '\x8b'
    98, // '\x8c'
    96, // '\x8d'
    97, // '\x8e'
    81, // '\x8f'
    207, // '\x90'
    145, // '\x91'
    116, // '\x92'
    115, // '\x93'
    144, // '\x94'
    130, // '\x95'
    153, // '\x96'
    121, // '\x97'
    107, // '\x98'
    132, // '\x99'
    109, // '\x9a'
    110, // '\x9b'
    124, // '\x9c'
    111, // '\x9d'
    82, // '\x9e'
    108, // '\x9f'
    118, // '\xa0'
    141, // '¡'
    113, // '¢'
    129, // '£'
    119, // '¤'
    125, // '¥'
    165, // '¦'
    117, // '§'
    92, // '¨'
    106, // '©'
    83, // 'ª'
    72, // '«'
    99, // '¬'
    93, // '\xad'
    65, // '®'
    79, // '¯'
    166, // '°'
    237, // '±'
    163, // '²'
    199, // '³'
    190, // '´'
    225, // 'µ'
    209, // '¶'
    203, // '·'
    198, // '¸'
    217, // '¹'
    219, // 'º'
    206, // '»'
    234, // '¼'
    248, // '½'
    158, // '¾'
    239, // '¿'
    255, // 'À'
    255, // 'Á'
    255, // 'Â'
    255, // 'Ã'
    255, // 'Ä'
    255, // 'Å'
    255, // 'Æ'
    255, // 'Ç'
    255, // 'È'
    255, // 'É'
    255, // 'Ê'
    255, // 'Ë'
    255, // 'Ì'
    255, // 'Í'
    255, // 'Î'
    255, // 'Ï'
    255, // 'Ð'
    255, // 'Ñ'
    255, // 'Ò'
    255, // 'Ó'
    255, // 'Ô'
    255, // 'Õ'
    255, // 'Ö'
    255, // '×'
    255, // 'Ø'
    255, // 'Ù'
    255, // 'Ú'
    255, // 'Û'
    255, // 'Ü'
    255, // 'Ý'
    255, // 'Þ'
    255, // 'ß'
    255, // 'à'
    255, // 'á'
    255, // 'â'
    255, // 'ã'
    255, // 'ä'
    255, // 'å'
    255, // 'æ'
    255, // 'ç'
    255, // 'è'
    255, // 'é'
    255, // 'ê'
    255, // 'ë'
    255, // 'ì'
    255, // 'í'
    255, // 'î'
    255, // 'ï'
    255, // 'ð'
    255, // 'ñ'
    255, // 'ò'
    255, // 'ó'
    255, // 'ô'
    255, // 'õ'
    255, // 'ö'
    255, // '÷'
    255, // 'ø'
    255, // 'ù'
    255, // 'ú'
    255, // 'û'
    255, // 'ü'
    255, // 'ý'
    255, // 'þ'
    255, // 'ÿ'
};

const std = @import("std");

const testing = std.testing;

test "find_substr" {
    const haystack = @embedFile("./haystack.txt");
    const needle = "newsletter";

    const expected = find_substr(needle, haystack);
    const actual = find_substr_simd_v2(needle, haystack);
    try testing.expectEqual(expected, actual);
}

fn benchmarkFindSubstr(_: std.mem.Allocator) void {
    const haystack_small = @embedFile("./haystack-small.txt");
    const needle = "precisely";
    const idx = find_substr(needle, haystack_small);
    if (idx != 76) {
        @panic("find_substr wrong index!");
    }
}
fn benchmarkFindSubstrSimdV2(_: std.mem.Allocator) void {
    const haystack_small = @embedFile("./haystack-small.txt");
    const needle = "precisely";
    const idx = find_substr_simd_v2(needle, haystack_small);
    if (idx != 76) {
        @panic("find_substr_simd_v2 wrong index!");
    }
}

const zbench = @import("zbench");
test "bench find_substr" {
    var bench = zbench.Benchmark.init(std.testing.allocator, .{});
    defer bench.deinit();
    try bench.add("find_substr", benchmarkFindSubstr, .{});
    try bench.add("find_substr_simd_v2", benchmarkFindSubstrSimdV2, .{});

    var w = std.fs.File.stderr().writer(&.{});
    try bench.run(&w.interface);
}
