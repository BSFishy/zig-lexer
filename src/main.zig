const std = @import("std");
const lexer = @import("lexer.zig");
const regex = @import("regex.zig");
const ArrayList = @import("array_list.zig").ArrayList;

pub const Lexer = lexer.Lexer;

const token_patterns = [_]lexer.TokenPattern{
    .{ .name = "Comment", .pattern = "//([^\n])*" },
    .{ .name = "Division", .pattern = "/" },
    .{ .name = "Func", .pattern = "func" },
    .{ .name = "String", .pattern = "\"([^\"]|\\\\\")*\"" },
    .{ .name = "Newline", .pattern = "(\n|\r\n)" },
    .{ .name = "Ident", .pattern = "\\w\\W*" },
    .{ .name = "For", .pattern = "for" },
    .{ .name = "Number", .pattern = "\\0+(.\\0+)?" },
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

    var l = Lexer(&token_patterns).init(allocator);

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (includes(args, "tree")) {
        const writer = std.io.getStdOut().writer();
        try l.to_graph(writer);

        return;
    }

    var diag: lexer.Diagnostics = .{};
    const tokens = l.lex("example/for/fortif\nication/\"test example\"1.0/asdf", .{
        .diagnostics = &diag,
    }) catch {
        const failure = diag.failure orelse unreachable;
        try failure.print();
        std.process.exit(1);
    };
    defer allocator.free(tokens);

    for (tokens) |token| {
        std.debug.print("{} - {s}\n", .{ token.token_type, token.source });
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
