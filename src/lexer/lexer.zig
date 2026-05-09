const std = @import("std");
const token = @import("token.zig");
const errors = @import("errors.zig");
const ArrayList = std.ArrayList;
const TokenType = token.TokenType;
const UsizeConversionError = errors.UsizeConversionError;
// const print = std.debug.print;

pub const RED = "\x1b[31m";
pub const RESET = "\x1b[0m";
pub const GREEN = "\x1b[32m";
pub const YELLOW = "\x1b[33m";
pub const MAGENTA = "\x1b[35m";
pub const CYAN = "\x1b[36m";
pub const BLUE = "\x1b[34m";
pub const ORANGE = "\x1b[38;2;206;145;120m";
pub const GREY = "\x1b[38;2;156;156;156m";
pub const CREAM = "\x1b[38;2;220;220;145m";
pub const LIGHT_GREEN = "\x1b[38;2;181;206;143m";
pub const LIGHT_BLUE = "\x1b[38;2;5;169;173m";
pub const PEACH = "\x1b[38;2;255;231;190m";

pub const Lexer = struct {
    token_list: *ArrayList(Token),
    last_token: ?Token = null,
    character_index: usize = 0,
    source: []const u8 = "",
    line_count: usize = 0, // for token position
    character_count: usize = 0,
    was_comment: bool = false,
};

pub const Token = struct {
    token_type: TokenType,
    value: []const u8,
    line: usize,
    character: usize,

    pub fn PrintValues(self: *const Token) void {
        std.debug.print("Token Type: {d}, Value: {s}, Line: {d}, Character: {d}\n", .{
            self.token_type,
            self.value,
            self.line,
            self.character,
        });
    }

    pub fn IsType(self: *const Token, token_type: TokenType) bool {
        return self.token_type == token_type;
    }
};

pub fn printNumberSlice(comptime T: type, source: []const T) void {
    std.debug.print("{any}", .{source});
}

pub fn printlnNumberSlice(comptime T: type, source: []const T) void {
    std.debug.print("{any}\n", .{source});
}

pub fn printlnQuotes(source: []const u8) void {
    std.debug.print("'{s}'\n", .{source});
}

pub fn printMessage(message: []const u8, source: []const u8) void {
    std.debug.print("{s}: '{s}'", .{ message, source });
}

pub fn printlnMessage(message: []const u8, source: []const u8) void {
    std.debug.print("{s}: '{s}'\n", .{ message, source });
}

pub fn print(source: []const u8) void {
    std.debug.print("{s}", .{source});
}

pub fn println(source: []const u8) void {
    std.debug.print("{s}\n", .{source});
}

pub fn printVar(source: anytype) void {
    std.debug.print("{any}", .{source});
}

pub fn printlnVar(source: anytype) void {
    std.debug.print("{any}\n", .{source});
}

pub fn newLine() void {
    std.debug.print("\n", .{});
}

pub fn printMessageVariable(message: []const u8, source: anytype) void {
    std.debug.print("{s} {}", .{ message, source });
}

pub fn printMessageVariableln(message: []const u8, source: anytype) void {
    std.debug.print("{s} {}\n", .{ message, source });
}

pub fn printTypeOfVariable(source: anytype) void {
    std.debug.print("Type: {}\n", .{@TypeOf(source)});
}

pub fn printFloat(source: anytype, decimal_point_count: u4) void {
    switch (decimal_point_count) {
        0 => std.debug.print("{any}", .{source}),
        1 => std.debug.print("{any:.1}", .{source}),
        2 => std.debug.print("{any:.2}", .{source}),
        3 => std.debug.print("{any:.3}", .{source}),
        4 => std.debug.print("{any:.4}", .{source}),
        5 => std.debug.print("{any:.5}", .{source}),
        6 => std.debug.print("{any:.6}", .{source}),
        7 => std.debug.print("{any:.7}", .{source}),
        8 => std.debug.print("{any:.8}", .{source}),
        9 => std.debug.print("{any:.9}", .{source}),
        10 => std.debug.print("{any:.10}", .{source}),
        11 => std.debug.print("{any:.11}", .{source}),
        12 => std.debug.print("{any:.12}", .{source}),
        13 => std.debug.print("{any:.13}", .{source}),
        14 => std.debug.print("{any:.14}", .{source}),
        15 => std.debug.print("{any:.15}", .{source}),
        else => std.debug.print("{any}", .{source}), // default case
    }
}

pub fn printlnFloat(source: anytype, decimal_point_count: u4) void {
    switch (decimal_point_count) {
        0 => std.debug.print("{any}\n", .{source}),
        1 => std.debug.print("{any:.1}\n", .{source}),
        2 => std.debug.print("{any:.2}\n", .{source}),
        3 => std.debug.print("{any:.3}\n", .{source}),
        4 => std.debug.print("{any:.4}\n", .{source}),
        5 => std.debug.print("{any:.5}\n", .{source}),
        6 => std.debug.print("{any:.6}\n", .{source}),
        7 => std.debug.print("{any:.7}\n", .{source}),
        8 => std.debug.print("{any:.8}\n", .{source}),
        9 => std.debug.print("{any:.9}\n", .{source}),
        10 => std.debug.print("{any:.10}\n", .{source}),
        11 => std.debug.print("{any:.11}\n", .{source}),
        12 => std.debug.print("{any:.12}\n", .{source}),
        13 => std.debug.print("{any:.13}\n", .{source}),
        14 => std.debug.print("{any:.14}\n", .{source}),
        15 => std.debug.print("{any:.15}\n", .{source}),
        else => std.debug.print("{any}\n", .{source}), // default case
    }
}

pub fn printBitsU8(source: u8) void {
    var output: [8]u8 = undefined;
    var temp: u8 = 128;
    for (0..8) |i| {
        const AND_RESULT: u8 = temp & source;
        if (AND_RESULT != 0) {
            output[i] = '1';
        }
        // else {
        //     output[i] = '0';
        // }
        temp /= 2;
    }
    std.debug.print("{s} ", .{output[0..]});
}

pub fn isIndexInRange(max: usize, index: usize) bool {
    if (index >= max) {
        return false;
    }
    return true;
}

pub fn convertIndexToUsize(source: anytype) !usize {
    if (source < 0) {
        return UsizeConversionError.OutOfRange;
    }
    return @intCast(source);
}

pub fn twoSlicesAreTheSame(first_slice: []const u8, second_slice: []const u8) bool {
    const FIRST_SLICE_LENGTH: usize = first_slice.len;

    if (FIRST_SLICE_LENGTH != second_slice.len) {
        return false;
    }
    for (0..FIRST_SLICE_LENGTH) |index| {
        if (first_slice[index] != second_slice[index]) {
            return false;
        }
    }
    return true;
}

pub fn contains(slice: []const u8, char: u8) bool {
    const LENGTH: usize = slice.len;

    if (LENGTH == 0) {
        return false;
    }
    for (0..LENGTH) |index| {
        if (slice[index] == char) {
            return true;
        }
    }
    return false;
}
