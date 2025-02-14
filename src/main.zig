const std = @import("std");
const lexer = @import("lexer.zig");
const regex = @import("regex.zig");
const ArrayList = @import("array_list.zig").ArrayList;

pub const Lexer = lexer.Lexer(.{
    .Comment = .{ .pattern = "//([^\n])*" },
    .Division = .{ .pattern = "/" },
    .Func = .{ .pattern = "func" },
    .Let = .{ .pattern = "let" },
    .If = .{ .pattern = "if" },
    .Else = .{ .pattern = "else" },
    .Return = .{ .pattern = "return" },
    .String = .{ .pattern = "\"([^\"]|\\\\\")*\"" },
    .Newline = .{ .pattern = "(\n|\r\n)" },
    .Ident = .{ .pattern = "\\w\\W*" },
    .For = .{ .pattern = "for" },
    .While = .{ .pattern = "while" },
    .Number = .{ .pattern = "\\0+(.\\0+)?" },
    .Integer = .{ .pattern = "\\0+i\\0+" },
    .Space = .{ .pattern = " " },
    .LParen = .{ .pattern = "\\(" },
    .RParen = .{ .pattern = "\\)" },
    .Comma = .{ .pattern = "," },
    .LBrace = .{ .pattern = "{" },
    .RBrace = .{ .pattern = "}" },
    .Plus = .{ .pattern = "\\+" },
    .Minus = .{ .pattern = "-" },
    .Semicolon = .{ .pattern = ";" },
    .Equal = .{ .pattern = "=" },
    .LT = .{ .pattern = "<" },
    .GT = .{ .pattern = ">" },
    .LE = .{ .pattern = "<=" },
    .GE = .{ .pattern = ">=" },
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            @panic("detected memory leaks");
        }
    }

    const l = Lexer.init(allocator);

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

    const start = try std.time.Instant.now();

    var diag: lexer.Diagnostics = .{};
    const tokens = l.lex(contents, .{ .diagnostics = &diag }) catch {
        const failure = diag.failure orelse unreachable;
        try failure.print();
        std.process.exit(1);
    };
    defer allocator.free(tokens);

    const end = try std.time.Instant.now();

    if (tokens[0].match(&.{ .Comment, .String })) |token| {
        std.debug.print("token type is: {s} - ", .{@tagName(token.token_type)});

        for (token.source) |char| {
            var buffer: [4]u8 = undefined;
            _ = try std.unicode.utf8Encode(char, &buffer);
            std.debug.print("{s}", .{buffer});
        }

        std.debug.print("\n", .{});
    } else {
        std.debug.print("token is not a comment or string\n", .{});
    }

    for (tokens) |token| {
        printColorForToken(token.token_type);

        for (token.source) |char| {
            var buffer: [4]u8 = undefined;
            _ = try std.unicode.utf8Encode(char, &buffer);
            std.debug.print("{s}", .{buffer});
        }

        std.debug.print("\x1B[0m", .{});
    }

    const elapsed = end.since(start);
    try printDuration("\nTime spend lexing: ", "\n", elapsed);

    const time_per_token = elapsed / tokens.len;
    try printDuration("Time per token: ", " / token\n", time_per_token);

    const time_per_char = elapsed / contents.len;
    try printDuration("Time per character: ", " / character\n", time_per_char);
}

fn printDuration(prefix: []const u8, postfix: []const u8, elapsed: u64) !void {
    const formatter = std.fmt.fmtDuration(elapsed);

    std.debug.print("{s}", .{prefix});
    const stdout = std.io.getStdErr();
    try formatter.format("", .{}, stdout.writer());

    std.debug.print("{s}", .{postfix});
}

fn printColorForToken(token: Lexer.TokenType) void {
    switch (token) {
        .Comment => std.debug.print("\x1B[2m", .{}),

        .String => std.debug.print("\x1B[32m", .{}),

        .Newline, .Space => {},

        .Ident => std.debug.print("\x1B[34m", .{}),

        .Func, .For, .While, .If, .Else, .Return, .Let => std.debug.print("\x1B[31m", .{}),

        .Number, .Integer => std.debug.print("\x1B[35m", .{}),

        .Division, .LParen, .RParen, .Comma, .LBrace, .RBrace, .Minus, .Semicolon, .Equal, .Plus, .GT, .LT, .GE, .LE => std.debug.print("\x1B[36m", .{}),
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
