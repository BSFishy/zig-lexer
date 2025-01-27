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
};

const token_patterns = [_]lexer.TokenPattern(TokenType){
    .{ .token_type = .Comment, .pattern = "//([^\n])*" },
    .{ .token_type = .Division, .pattern = "/" },
    .{ .token_type = .Func, .pattern = "func" },
    .{ .token_type = .String, .pattern = "\"([^\"]|\\\\\")*\"" },
    .{ .token_type = .Newline, .pattern = "(\n|\r\n)" },
    .{ .token_type = .Ident, .pattern = "\\w\\W*" },
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

    const stdout = std.io.getStdOut().writer();
    try l.to_graph(stdout, allocator);
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
