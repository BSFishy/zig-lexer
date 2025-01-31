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
    .{ .name = "While", .pattern = "while" },
    .{ .name = "Number", .pattern = "\\0+(.\\0+)?" },
    .{ .name = "Space", .pattern = " " },
    .{ .name = "LParen", .pattern = "\\(" },
    .{ .name = "RParen", .pattern = "\\)" },
    .{ .name = "Comma", .pattern = "," },
    .{ .name = "LBrace", .pattern = "{" },
    .{ .name = "RBrace", .pattern = "}" },
    .{ .name = "Plus", .pattern = "\\+" },
    .{ .name = "Minus", .pattern = "-" },
    .{ .name = "Semicolon", .pattern = ";" },
    .{ .name = "Equal", .pattern = "=" },
    .{ .name = "LT", .pattern = "<" },
    .{ .name = "GT", .pattern = ">" },
    .{ .name = "LE", .pattern = "<=" },
    .{ .name = "GE", .pattern = ">=" },
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

    const contents = try blk: {
        const input = try std.fs.cwd().readFileAlloc(allocator, "example.lang", 2 * 1024 * 1024 * 1024);
        defer allocator.free(input);

        const input_view = try std.unicode.Utf8View.init(input);

        var contents = std.ArrayList(u21).init(allocator);
        var iterator = input_view.iterator();
        while (iterator.nextCodepoint()) |codepoint| {
            try contents.append(codepoint);
        }

        break :blk contents.toOwnedSlice();
    };
    defer allocator.free(contents);

    var diag: lexer.Diagnostics = .{};
    const tokens = l.lex(contents, .{
        .diagnostics = &diag,
    }) catch {
        const failure = diag.failure orelse unreachable;
        try failure.print();
        std.process.exit(1);
    };
    defer allocator.free(tokens);

    for (tokens) |token| {
        std.debug.print("{} - ", .{
            token.token_type,
        });

        for (token.source) |char| {
            var buffer: [4]u8 = undefined;
            _ = try std.unicode.utf8Encode(char, &buffer);
            std.debug.print("{s}", .{buffer});
        }

        std.debug.print("\n", .{});
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
