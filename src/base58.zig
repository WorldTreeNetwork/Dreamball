//! Base58 (Bitcoin alphabet) encode/decode. Small, allocation-free decode
//! into caller buffer; encode returns an owned slice.
//!
//! Kept hand-rolled rather than depending on a library to keep the dep tree
//! minimal — the protocol only needs short keys/hashes (≤ 32 bytes), where
//! the O(n²) bignum arithmetic is negligible.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

pub fn encode(allocator: Allocator, bytes: []const u8) ![]u8 {
    if (bytes.len == 0) return allocator.alloc(u8, 0);

    var leading_zeros: usize = 0;
    while (leading_zeros < bytes.len and bytes[leading_zeros] == 0) : (leading_zeros += 1) {}

    // Worst case: log(256)/log(58) ≈ 1.366 digits per byte.
    const cap = bytes.len * 138 / 100 + 1;
    var digits = try allocator.alloc(u8, cap);
    defer allocator.free(digits);
    @memset(digits, 0);

    var length: usize = 0;
    for (bytes) |byte| {
        var carry: u32 = byte;
        var i: usize = 0;
        var j: usize = cap;
        while (j > 0) {
            j -= 1;
            if (i >= length and carry == 0) break;
            carry += @as(u32, digits[j]) * 256;
            digits[j] = @intCast(carry % 58);
            carry /= 58;
            i += 1;
        }
        length = i;
    }

    // Skip leading zeros in the buffer, then prepend a '1' per source leading zero byte.
    var start: usize = cap - length;
    const out_len = leading_zeros + length;
    const out = try allocator.alloc(u8, out_len);
    errdefer allocator.free(out);
    @memset(out[0..leading_zeros], '1');
    var k: usize = leading_zeros;
    while (start < cap) : (start += 1) {
        out[k] = alphabet[digits[start]];
        k += 1;
    }
    return out;
}

pub fn decodedLenUpperBound(input_len: usize) usize {
    return input_len * 733 / 1000 + 1;
}

pub const DecodeError = error{InvalidBase58Char};

pub fn decode(allocator: Allocator, str: []const u8) ![]u8 {
    if (str.len == 0) return allocator.alloc(u8, 0);

    var leading_ones: usize = 0;
    while (leading_ones < str.len and str[leading_ones] == '1') : (leading_ones += 1) {}

    const cap = decodedLenUpperBound(str.len);
    var bytes = try allocator.alloc(u8, cap);
    defer allocator.free(bytes);
    @memset(bytes, 0);

    var length: usize = 0;
    for (str) |c| {
        const idx = std.mem.indexOfScalar(u8, alphabet, c) orelse return DecodeError.InvalidBase58Char;
        var carry: u32 = @intCast(idx);
        var i: usize = 0;
        var j: usize = cap;
        while (j > 0) {
            j -= 1;
            if (i >= length and carry == 0) break;
            carry += @as(u32, bytes[j]) * 58;
            bytes[j] = @intCast(carry & 0xFF);
            carry >>= 8;
            i += 1;
        }
        length = i;
    }

    const start = cap - length;
    const out_len = leading_ones + length;
    const out = try allocator.alloc(u8, out_len);
    @memset(out[0..leading_ones], 0);
    @memcpy(out[leading_ones..], bytes[start..]);
    return out;
}

test "base58 round-trip for fingerprint-sized input" {
    const allocator = std.testing.allocator;
    const input: [32]u8 = [_]u8{
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
        0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
        0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F,
    };
    const encoded = try encode(allocator, &input);
    defer allocator.free(encoded);
    const decoded = try decode(allocator, encoded);
    defer allocator.free(decoded);
    try std.testing.expectEqualSlices(u8, &input, decoded);
}

test "base58 leading zeros preserved as '1's" {
    const allocator = std.testing.allocator;
    const input = [_]u8{ 0x00, 0x00, 0x00, 0xAB };
    const encoded = try encode(allocator, &input);
    defer allocator.free(encoded);
    try std.testing.expect(encoded.len >= 3);
    try std.testing.expectEqual(@as(u8, '1'), encoded[0]);
    try std.testing.expectEqual(@as(u8, '1'), encoded[1]);
    try std.testing.expectEqual(@as(u8, '1'), encoded[2]);
    const decoded = try decode(allocator, encoded);
    defer allocator.free(decoded);
    try std.testing.expectEqualSlices(u8, &input, decoded);
}

test "base58 known vector" {
    const allocator = std.testing.allocator;
    // "Hello World!" in Base58 is "2NEpo7TZRRrLZSi2U"
    const input = "Hello World!";
    const encoded = try encode(allocator, input);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("2NEpo7TZRRrLZSi2U", encoded);
}

test "base58 rejects invalid character" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(DecodeError.InvalidBase58Char, decode(allocator, "abc0"));
}
