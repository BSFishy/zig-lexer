const std = @import("std");
const regex = @import("regex.zig");
const ArrayList = @import("array_list.zig").ArrayList;
const map = @import("map.zig");
const jumpTable = @import("jump_table.zig");

const Map = map.Map;
const StaticMap = map.StaticMap;

const StaticJumpTable = jumpTable.StaticJumpTable;
const JumpTable = jumpTable.JumpTable;
const StaticTable = jumpTable.StaticTable;
const Table = jumpTable.Table;
const Fallthrough = jumpTable.Fallthrough;
const match_sequence = jumpTable.match_sequence;

pub const TokenPattern = struct {
    name: []const u8,
    pattern: []const u8,
    skip: bool = false,
};

fn FallthroughExpansion(token_type: type) type {
    return struct {
        index: usize,
        fallthrough: Fallthrough(token_type),
    };
}

fn expand_jump_table_sequences(token_type: type, jump_table: *JumpTable(token_type), index: usize) void {
    const table = jump_table.getTable(index);
    defer jump_table.exit();
    if (jump_table.visit(index)) {
        // already expanded lol
        return;
    }

    if (table.sequences.len() != 0) {
        for (table.chars.getEntries()) |entry| {
            const key = entry.key;
            for (table.sequences.getEntries()) |seq_entry| {
                const seq_key = seq_entry.key;
                if (!match_sequence(seq_key, key)) {
                    continue;
                }

                var node = table.chars.get_mut(key) orelse unreachable;
                const seq_node = table.sequences.get_mut(seq_key) orelse unreachable;

                if (node.leaf == null) {
                    if (seq_node.leaf) |leaf| {
                        node.leaf = leaf;
                    }
                }

                if (seq_node.next) |seq_next| {
                    const next_table_idx = node.next orelse blk: {
                        const idx = jump_table.tables.len;
                        node.next = idx;
                        break :blk idx;
                    };
                    var next_table = jump_table.getTable(next_table_idx);

                    const seq_table = jump_table.getTable(seq_next);
                    next_table.merge(seq_table);
                }
            }
        }
    }

    for (table.chars.getEntries()) |entry| {
        const node = entry.value;
        if (node.next) |next| {
            expand_jump_table_sequences(token_type, jump_table, next);
        }
    }
}

fn Leaf(token_type: type) type {
    return union(enum) {
        const Self = @This();

        leaf: token_type,
        skip,

        fn eql(self: Self, other: Self) bool {
            switch (self) {
                .leaf => |leaf| {
                    switch (other) {
                        .leaf => |other_leaf| return leaf == other_leaf,
                        .skip => return false,
                    }
                },
                .skip => {
                    switch (other) {
                        .leaf => return false,
                        .skip => return true,
                    }
                },
            }
        }

        fn name(self: Self) []const u8 {
            switch (self) {
                .leaf => |leaf| return @tagName(leaf),
                .skip => return "skip",
            }
        }
    };
}

fn compile_static_jump_map(comptime token_patterns: []const TokenPattern, comptime TokenType: type) StaticJumpTable(Leaf(TokenType)) {
    if (!@inComptime()) {
        @compileError("This function must be executed at compile time.");
    }

    std.debug.assert(token_patterns.len > 0);

    @setEvalBranchQuota(token_patterns.len * 10000);

    var jump_table = JumpTable(Leaf(TokenType)).init();
    for (token_patterns) |token_pattern| {
        const pattern = regex.parsePattern(token_pattern.pattern) catch |err| @compileError(err);
        const indicies = jump_table.insert(pattern);
        for (indicies) |index| {
            var node = index.node(Leaf(TokenType), &jump_table);
            const leaf: Leaf(TokenType) = if (token_pattern.skip) .skip else .{ .leaf = @field(TokenType, token_pattern.name) };

            if (node.leaf) |node_leaf| {
                if (!leaf.eql(node_leaf)) {
                    @compileError("duplicate token detected");
                }
            } else {
                node.leaf = leaf;
            }
        }
    }

    expand_jump_table_sequences(Leaf(TokenType), &jump_table, 0);

    var static_table = ArrayList(StaticTable(Leaf(TokenType))).init();
    for (jump_table.tables.get()) |table| {
        static_table.append(.{
            .chars = table.chars.compile(),
            .sequences = table.sequences.compile(),
            .fallthrough = table.fallthrough,
        });
    }

    const len = static_table.len;
    const static_jump_table = static_table.get_static();

    return .{
        .len = len,
        .tables = static_jump_table,
    };
}

fn compile_token_type(comptime token_patterns: []const TokenPattern) type {
    var enum_fields = ArrayList(std.builtin.Type.EnumField).init();
    {
        var i: usize = 0;
        for (token_patterns) |pattern| {
            if (pattern.skip) {
                continue;
            }

            var name: [pattern.name.len:0]u8 = undefined;
            @memcpy(name[0..], pattern.name);

            enum_fields.append(.{
                .name = &name,
                .value = i,
            });

            i += 1;
        }
    }

    const tag = @Type(.{
        .@"enum" = .{
            .tag_type = @Type(.{ .int = .{ .signedness = .unsigned, .bits = @ceil(@log2(@as(f32, token_patterns.len))) } }),
            .fields = enum_fields.get(),
            .decls = &.{},
            .is_exhaustive = true,
        },
    });

    return struct {
        const Self = @This();
        const Tag = tag;

        token_type: tag,
        source: []const u21,

        pub fn MatchedType(comptime tokens: []const tag) type {
            var token_types: [tokens.len]std.builtin.Type.EnumField = undefined;
            for (tokens, 0..) |token, i| {
                token_types[i] = .{
                    .name = @tagName(token),
                    .value = i,
                };
            }

            const matched_tag = @Type(.{
                .@"enum" = .{
                    .tag_type = @Type(.{ .int = .{ .signedness = .unsigned, .bits = @ceil(@log2(@as(f32, tokens.len))) } }),
                    .fields = &token_types,
                    .decls = &.{},
                    .is_exhaustive = true,
                },
            });

            return struct {
                token_type: matched_tag,
                source: []const u21,
            };
        }

        pub fn match(self: *const Self, comptime tokens: []const tag) ?MatchedType(tokens) {
            inline for (tokens, 0..) |token, i| {
                if (token == self.token_type) {
                    return .{
                        .token_type = @enumFromInt(i),
                        .source = self.source,
                    };
                }
            }

            return null;
        }
    };
}

fn findLineNumber(input: []const u21, start: usize) usize {
    var line_number: usize = 1;
    var i = start;
    while (i > 0) : (i -= 1) {
        if (input[i - 1] == '\n') {
            line_number += 1;
        }
    }

    return line_number;
}

fn findLineStart(input: []const u21, start: usize) usize {
    var i = start;
    while (i > 0 and input[i - 1] != '\n') : (i -= 1) {}

    return i;
}

fn findLineEnd(input: []const u21, start: usize) usize {
    var i = start;
    while (i < input.len - 1 and input[i] != '\r' and input[i] != '\n') : (i += 1) {}

    return i;
}

fn renderErrorLine(allocator: std.mem.Allocator, line_start: usize, line_end: usize, failure_start: usize, failure_end: usize) ![]u8 {
    var line = std.ArrayListUnmanaged(u8).empty;
    try line.appendSlice(allocator, "        ");

    var i = line_start;
    while (i < failure_start) : (i += 1) {
        try line.append(allocator, ' ');
    }

    while (i < failure_end and i < line_end) : (i += 1) {
        try line.append(allocator, '~');
    }

    if (i == failure_end) {
        try line.append(allocator, '^');
    }

    return line.toOwnedSlice(allocator);
}

pub const Failure = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    input: []const u21,
    start: usize,
    end: usize,

    pub fn print(self: *const Self) !void {
        const line_start = findLineStart(self.input, self.start);
        const line_end = findLineEnd(self.input, self.end);

        const input = self.input[line_start..line_end];
        var line_number = findLineNumber(self.input, self.start);

        std.debug.print("unexpected input:\n", .{});

        // doing this because im lazy and cant think of another way to do this
        var started = false;
        for (input, line_start..) |char, i| {
            if (char == '\n' or !started) {
                if (started) {
                    const current_line_start = findLineStart(self.input, i);
                    const current_line_end = findLineEnd(self.input, i);
                    const error_line = try renderErrorLine(self.allocator, current_line_start, current_line_end, self.start, self.end);
                    defer self.allocator.free(error_line);

                    std.debug.print("\n{s}\n", .{error_line});
                }

                std.debug.print(" {d: >4} | ", .{line_number});
                line_number += 1;

                if (!started) {
                    started = true;
                } else {
                    continue;
                }
            }

            var buffer: [4]u8 = undefined;
            _ = try std.unicode.utf8Encode(char, &buffer);
            std.debug.print("{s}", .{buffer});
        }

        const current_line_start = findLineStart(self.input, self.end);
        const current_line_end = findLineEnd(self.input, self.end);
        const error_line = try renderErrorLine(self.allocator, current_line_start, current_line_end, self.start, self.end);
        defer self.allocator.free(error_line);

        std.debug.print("\n{s}\n", .{error_line});
    }
};

pub const Diagnostics = struct {
    failure: ?Failure = null,
};

pub const LexerOptions = struct {
    const Self = @This();

    diagnostics: ?*Diagnostics = null,

    fn fill_failure(self: *const Self, failure: ?Failure) void {
        var diag = self.diagnostics orelse return;
        diag.failure = failure;
    }
};

fn tokenPatternsFromTokens(comptime tokens: anytype) [@typeInfo(@TypeOf(tokens)).@"struct".fields.len]TokenPattern {
    const fields = @typeInfo(@TypeOf(tokens)).@"struct".fields;
    var token_patterns: [fields.len]TokenPattern = undefined;
    for (fields, 0..) |field, i| {
        var token: TokenPattern = .{ .name = undefined, .pattern = undefined };
        token.name = field.name;

        const values = @field(tokens, field.name);
        for (@typeInfo(@TypeOf(values)).@"struct".fields) |value_field| {
            @field(token, value_field.name) = @field(values, value_field.name);
        }

        token_patterns[i] = token;
    }

    return token_patterns;
}

pub fn Lexer(comptime tokens: anytype) type {
    return struct {
        const Self = @This();

        const token_patterns = tokenPatternsFromTokens(tokens);
        pub const Token = compile_token_type(&token_patterns);
        pub const TokenType = Token.Tag;
        const static_jump_table = compile_static_jump_map(&token_patterns, TokenType);

        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        pub fn to_graph(self: *const Self, writer: anytype) !void {
            try std.fmt.format(writer, "digraph {{\n", .{});

            for (0..static_jump_table.len) |i| {
                const start = if (i == 0) try self.allocator.dupe(u8, "start") else try std.fmt.allocPrint(self.allocator, "{}", .{i});
                defer self.allocator.free(start);

                const static_table = static_jump_table.tables[i];
                for (0..static_table.chars.len) |idx| {
                    const entry = static_table.chars.entries[idx];
                    const key_codepoint = entry.key;
                    const value = entry.value;

                    const buffer = try uft8ToString(self.allocator, key_codepoint, false);
                    defer self.allocator.free(buffer);

                    if (value.next) |next| {
                        try std.fmt.format(writer, "  {s} -> {} [label=\"{s}\"];\n", .{ start, next, buffer });
                    }

                    if (value.leaf) |leaf| {
                        if (value.next) |next| {
                            try std.fmt.format(writer, "  {} -> {s} [label=\"super {s} leaf\" color=blue];\n", .{ next, leaf.name(), buffer });
                        } else {
                            try std.fmt.format(writer, "  {s} -> {s} [label=\"{s} leaf\" color=blue];\n", .{ start, leaf.name(), buffer });
                        }
                    }

                    if (value.next == null and value.leaf == null) {
                        std.debug.print("{s} has no next and no leaf\n", .{buffer});
                    }
                }

                for (0..static_table.sequences.len) |idx| {
                    const entry = static_table.sequences.entries[idx];
                    const key_codepoint = entry.key;
                    const value = entry.value;

                    const buffer = try uft8ToString(self.allocator, key_codepoint, true);
                    defer self.allocator.free(buffer);

                    if (value.next) |next| {
                        try std.fmt.format(writer, "  {s} -> {} [label=\"{s}\" color=orange];\n", .{ start, next, buffer });
                    }

                    if (value.leaf) |leaf| {
                        if (value.next) |next| {
                            try std.fmt.format(writer, "  {} -> {s} [label=\"super {s} leaf\" color=green];\n", .{ next, leaf.name(), buffer });
                        } else {
                            try std.fmt.format(writer, "  {s} -> {s} [label=\"{s} leaf\" color=green];\n", .{ start, leaf.name(), buffer });
                        }
                    }

                    if (value.next == null and value.leaf == null) {
                        std.debug.print("{s} has no next and no leaf\n", .{buffer});
                    }
                }

                if (static_table.fallthrough) |fallthrough| {
                    const value = fallthrough.next;
                    const buffer = try uft8ToString(self.allocator, switch (fallthrough.value) {
                        .char => |char| char,
                        .sequence => |char| char,
                    }, switch (fallthrough.value) {
                        .char => false,
                        .sequence => true,
                    });
                    defer self.allocator.free(buffer);

                    if (value.next) |next| {
                        try std.fmt.format(writer, "  {s} -> {} [label=\"not {s}\" color=red];\n", .{ start, next, buffer });
                    }

                    if (value.leaf) |leaf| {
                        if (value.next) |next| {
                            try std.fmt.format(writer, "  {} -> {s} [label=\"super not {s} leaf\" color=purple];\n", .{ next, leaf.name(), buffer });
                        } else {
                            try std.fmt.format(writer, "  {s} -> {s} [label=\"not {s} leaf\" color=purple];\n", .{ start, leaf.name(), buffer });
                        }
                    }
                }
            }

            try std.fmt.format(writer, "}}\n", .{});
        }

        pub fn lex(self: *const Self, input: []const u21, opts: LexerOptions) ![]Token {
            var out = std.ArrayListUnmanaged(Token).empty;
            defer out.deinit(self.allocator);

            opts.fill_failure(null);

            var i: usize = 0;
            var table_idx: usize = 0;
            var leaf: ?Leaf(TokenType) = null;
            var start: usize = 0;
            outer: while (i < input.len) : (i += 1) {
                const table = static_jump_table.tables[table_idx];
                const char = input[i];

                for (0..table.chars.len) |char_idx| {
                    const char_entry = table.chars.entries[char_idx];
                    const char_key = char_entry.key;
                    const char_node = char_entry.value;
                    if (char_key != char) {
                        continue;
                    }

                    if (char_node.next) |next| {
                        table_idx = next;
                        leaf = char_node.leaf;
                    } else {
                        if (char_node.leaf) |char_leaf| {
                            switch (char_leaf) {
                                .leaf => |token_leaf| {
                                    try out.append(self.allocator, .{
                                        .token_type = token_leaf,
                                        .source = input[start .. i + 1],
                                    });
                                },
                                else => {},
                            }

                            table_idx = 0;
                            leaf = null;
                            start = i + 1;
                        } else {
                            unreachable;
                        }
                    }

                    continue :outer;
                }

                for (0..table.sequences.len) |seq_idx| {
                    const seq_entry = table.sequences.entries[seq_idx];
                    const seq_key = seq_entry.key;
                    const seq_node = seq_entry.value;
                    if (!match_sequence(seq_key, char)) {
                        continue;
                    }

                    if (seq_node.next) |next| {
                        table_idx = next;
                        leaf = seq_node.leaf;
                    } else {
                        if (seq_node.leaf) |seq_leaf| {
                            switch (seq_leaf) {
                                .leaf => |token_leaf| {
                                    try out.append(self.allocator, .{
                                        .token_type = token_leaf,
                                        .source = input[start .. i + 1],
                                    });
                                },
                                else => {},
                            }

                            table_idx = 0;
                            leaf = null;
                            start = i + 1;
                        } else {
                            unreachable;
                        }
                    }

                    continue :outer;
                }

                if (table.fallthrough) |fallthrough| {
                    if (!fallthrough.value.match(char)) {
                        const fallthrough_node = fallthrough.next;
                        if (fallthrough_node.next) |next| {
                            table_idx = next;
                            leaf = fallthrough_node.leaf;
                        } else {
                            if (fallthrough_node.leaf) |fallthrough_leaf| {
                                switch (fallthrough_leaf) {
                                    .leaf => |token_leaf| {
                                        try out.append(self.allocator, .{
                                            .token_type = token_leaf,
                                            .source = input[start .. i + 1],
                                        });
                                    },
                                    else => {},
                                }

                                table_idx = 0;
                                leaf = null;
                                start = i + 1;
                            } else {
                                unreachable;
                            }
                        }

                        continue :outer;
                    }
                }

                if (leaf) |l| {
                    switch (l) {
                        .leaf => |token_leaf| {
                            try out.append(self.allocator, .{
                                .token_type = token_leaf,
                                .source = input[start..i],
                            });
                        },
                        else => {},
                    }

                    table_idx = 0;
                    leaf = null;
                    i -= 1;
                    start = i + 1;

                    continue :outer;
                }

                opts.fill_failure(.{
                    .allocator = self.allocator,
                    .input = input,
                    .start = start,
                    .end = i,
                });
                return error.invalidInput;
            }

            if (leaf) |l| {
                switch (l) {
                    .leaf => |token_leaf| {
                        try out.append(self.allocator, .{
                            .token_type = token_leaf,
                            .source = input[start..i],
                        });
                    },
                    else => {},
                }
            } else {
                if (start != input.len) {
                    opts.fill_failure(.{
                        .allocator = self.allocator,
                        .input = input,
                        .start = start,
                        .end = i - 1,
                    });
                    return error.invalidInput;
                }
            }

            return out.toOwnedSlice(self.allocator);
        }
    };
}

fn uft8ToString(allocator: std.mem.Allocator, codepoint: u21, escaped: bool) ![]u8 {
    var buffer: [4]u8 = undefined;
    const len = try std.unicode.utf8Encode(codepoint, &buffer);

    const backslash = try replace(allocator, buffer[0..len], "\\", "\\\\");
    defer allocator.free(backslash);

    const newline = try replace(allocator, backslash, "\n", "\\\\n");
    defer allocator.free(newline);

    const registered = try replace(allocator, newline, "\r", "\\\\r");
    defer allocator.free(registered);

    const string = try replace(allocator, registered, "\"", "\\\"");
    if (!escaped) {
        return string;
    }

    defer allocator.free(string);

    var out = try allocator.alloc(u8, string.len + 2);
    @memcpy(out[2..], string);
    @memset(out[0..2], '\\');

    return out;
}

pub fn replace(allocator: std.mem.Allocator, input: []const u8, target: []const u8, replacement: []const u8) ![]u8 {
    var result = std.ArrayListUnmanaged(u8).empty;

    var index: usize = 0;
    while (index < input.len) {
        if (std.mem.startsWith(u8, input[index..], target)) {
            try result.appendSlice(allocator, replacement);
            index += target.len;
        } else {
            try result.append(allocator, input[index]);
            index += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}
