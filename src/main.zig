const std = @import("std");
const lexer = @import("lexer.zig");
const regex = @import("regex.zig");
const Node = @import("node.zig").Node;
const ArrayList = @import("array_list.zig").ArrayList;

pub const Lexer = lexer.Lexer;

const TokenType = enum {
    Comment,
    Division,
    Func,
    String,
    Newline,
    Ident,
    For,
    Number,
};

const token_patterns = [_]lexer.TokenPattern(TokenType){
    .{ .token_type = .Comment, .pattern = "//([^\n])*" },
    .{ .token_type = .Division, .pattern = "/" },
    .{ .token_type = .Func, .pattern = "func" },
    .{ .token_type = .String, .pattern = "\"([^\"]|\\\\\")*\"" },
    .{ .token_type = .Newline, .pattern = "(\n|\r\n)" },
    .{ .token_type = .Ident, .pattern = "\\w\\W*" },
    .{ .token_type = .For, .pattern = "for" },
    .{ .token_type = .Number, .pattern = "\\0+(.\\0+)?" },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            @panic("detected memory leaks");
        }
    }

    const l = Lexer(TokenType, &token_patterns);

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (includes(args, "tree")) {
        const writer = std.io.getStdOut().writer();
        try l.to_graph(writer, allocator);

        return;
    }

    const tokens = try l.lex(allocator, "example/for/fortification/\"test example\"1.0/1//test");
    defer allocator.free(tokens);

    for (tokens) |token| {
        std.debug.print("{}\n", .{token.token_type});
    }
}

fn includes(haystack: []const []const u8, needle: []const u8) bool {
    for (haystack) |item| {
        if (std.mem.eql(u8, item, needle)) {
            return true;
        }
    }

    return false;
}
