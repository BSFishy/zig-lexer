const std = @import("std");
const regex = @import("regex.zig");
const ArrayList = @import("array_list.zig").ArrayList;
const map = @import("map.zig");

const Map = map.Map;
const StaticMap = map.StaticMap;

pub const TokenPattern = struct {
    name: []const u8,
    pattern: []const u8,
};

fn Node(token_type: type) type {
    return struct {
        const Self = @This();

        leaf: ?token_type = null,
        next: ?usize = null,

        pub fn compare(self: *const Self, other: *const Self) bool {
            return self.leaf == other.leaf and self.next == other.next;
        }
    };
}

const FallthroughChar = union(enum) {
    const Self = @This();

    char: u21,
    sequence: u21,

    pub fn compare(self: Self, other: Self) bool {
        switch (self) {
            .char => |a| {
                switch (other) {
                    .char => |b| return a == b,
                    .sequence => return false,
                }
            },
            .sequence => |a| {
                switch (other) {
                    .char => return false,
                    .sequence => |b| return a == b,
                }
            },
        }
    }

    pub fn match(self: Self, c: u21) bool {
        switch (self) {
            .char => |char| return char == c,
            .sequence => |seq| return match_sequence(seq, c),
        }
    }
};

fn Fallthrough(token_type: type) type {
    return struct {
        value: FallthroughChar,
        next: Node(token_type),
    };
}

fn Table(token_type: type) type {
    return struct {
        const Self = @This();

        table: Map(u21, Node(token_type)),
        sequences: Map(u21, Node(token_type)),
        fallthrough: ?Fallthrough(token_type),
        expanded: bool = false,
        expanded2: bool = false,

        pub fn init() Self {
            return .{
                .table = Map(u21, Node(token_type)).init(),
                .sequences = Map(u21, Node(token_type)).init(),
                .fallthrough = null,
            };
        }

        pub fn get(self: *const Self, key: u21) ?Node(token_type) {
            return self.table.get(key);
        }

        pub fn put(self: *Self, key: u21, value: Node(token_type)) void {
            self.table.put(key, value);
        }

        pub fn hasFallthrough(self: *const Self) bool {
            return self.fallthrough != null;
        }

        pub fn setFallthrough(self: *Self, fallthrough: Fallthrough(token_type)) void {
            self.fallthrough = fallthrough;
        }

        pub fn merge(self: *Self, other: *const Self, jump_table: *JumpTable(token_type), other_index: usize) void {
            for (other.table.keys_iter()) |key| {
                @compileLog(key);
            }

            for (other.sequences.keys_iter()) |key| {
                const node = other.sequences.get(key) orelse unreachable;

                if (node.next) |next| {
                    if (next == other_index) {
                        const idx = jump_table.len();
                        const new_node = .{ .leaf = node.leaf, .next = idx };

                        var new_table = Table(token_type).init();
                        new_table.sequences.put(key, new_node);
                        jump_table.append(new_table);

                        self.sequences.put(key, new_node);
                    } else {
                        @compileError("unimplemented");
                    }
                } else {
                    @compileError("unimplemented");
                }
            }
        }
    };
}

fn JumpTable(token_type: type) type {
    return ArrayList(Table(token_type));
}

fn Child(token_type: type) type {
    return union(enum) {
        const Self = @This();

        token: token_type,
        next: usize,
        both: struct {
            token: token_type,
            next: usize,
        },

        pub fn getToken(self: Self) ?token_type {
            switch (self) {
                .token => |token| return token,
                .next => return null,
                .both => |both| return both.token,
            }
        }

        pub fn getNext(self: Self) ?usize {
            switch (self) {
                .token => return null,
                .next => |next| return next,
                .both => |both| return both.next,
            }
        }
    };
}

fn insert_tokens(token_type: type, index: usize, invert: bool, jump_table: *JumpTable(token_type), tokens: []const regex.Token, parents: []const *Node(token_type), next: ?usize) []const *Node(token_type) {
    const children = tokens[1..];
    var table = if (jump_table.len() > 0) jump_table.at(index) else blk: {
        jump_table.append(Table(token_type).init());

        break :blk jump_table.at(index);
    };

    switch (tokens[0]) {
        .Char => |c| {
            if (invert) {
                const value: FallthroughChar = .{ .char = c };

                if (table.fallthrough) |fallthrough| {
                    if (fallthrough.value.compare(value) and fallthrough.next.next == next) {
                        @compileError("unimplemented");
                    } else {
                        @compileError("cannot have multiple fallthroughs here");
                    }
                }

                if (children.len == 0) {
                    table.setFallthrough(.{
                        .value = value,
                        .next = .{
                            .next = next,
                        },
                    });

                    return &.{&(table.fallthrough orelse unreachable).next};
                }

                @compileError("unimplemented");
            }

            if (table.table.get_mut(c)) |v| {
                if (children.len == 0) {
                    if (next == null or v.next == next) {
                        return &.{table.table.at(c)};
                    }

                    @compileError("unimplemented");
                }

                if (v.next) |next_table| {
                    return insert_tokens(token_type, next_table, invert, jump_table, children, &.{table.table.at(c)}, next);
                }

                const idx = jump_table.len();
                jump_table.append(Table(token_type).init());

                v.next = idx;
                return insert_tokens(token_type, idx, invert, jump_table, children, &.{table.table.at(c)}, next);
            }

            if (children.len == 0) {
                table.put(c, .{ .next = next });
                return &.{table.table.at(c)};
            }

            const idx = jump_table.len();
            jump_table.append(Table(token_type).init());

            table.put(c, .{ .next = idx });
            return insert_tokens(token_type, idx, invert, jump_table, children, &.{table.table.at(c)}, next);
        },
        .Sequence => |c| {
            if (invert) {
                @compileError("unimplemented");
            }

            if (table.sequences.get(c)) |v| {
                if (children.len == 0) {
                    if (v.next == next) {
                        return &.{table.sequences.at(c)};
                    }

                    @compileError("unimplemented");
                }

                @compileError("unimplemented");
            }

            if (children.len == 0) {
                table.sequences.put(c, .{ .next = next });
                return &.{table.sequences.at(c)};
            }

            const idx = jump_table.len();
            jump_table.append(Table(token_type).init());

            table.sequences.put(c, .{ .next = idx });
            return insert_tokens(token_type, idx, invert, jump_table, children, &.{table.sequences.at(c)}, next);
        },
        .Group => |group| {
            var new_parents = ArrayList(*Node(token_type)).init();
            for (group.chars) |char| {
                var sub_tokens = [_]regex.Token{.{ .Char = char }};
                new_parents.insert(insert_tokens(token_type, index, group.invert, jump_table, &sub_tokens, parents, next));
            }

            return new_parents.get();
        },
        .Capture => |capture| {
            var new_parents = ArrayList(*Node(token_type)).init();
            for (capture.options) |option| {
                new_parents.insert(insert_tokens(token_type, index, invert, jump_table, option, parents, next));
            }

            return new_parents.get();
        },
        .Quantified => |quant| {
            switch (quant.quantifier) {
                .ZeroOrOne => {
                    var sub_tokens: [children.len + 1]regex.Token = undefined;
                    sub_tokens[0] = quant.inner.*;
                    for (children, 1..) |c, i| {
                        sub_tokens[i] = c;
                    }

                    var new_parents = ArrayList(*Node(token_type)).init();
                    new_parents.insert(insert_tokens(token_type, index, invert, jump_table, &sub_tokens, parents, next));
                    new_parents.insert(parents);

                    return new_parents.get();
                },
                .ZeroOrMore => {
                    var new_parents = ArrayList(*Node(token_type)).init();
                    new_parents.insert(insert_tokens(token_type, index, invert, jump_table, &.{quant.inner.*}, parents, index));
                    new_parents.insert(parents);

                    if (children.len > 0) {
                        return insert_tokens(token_type, index, invert, jump_table, children, parents, next);
                    }

                    return new_parents.get();
                },
                .OneOrMore => {
                    const idx = jump_table.len();
                    jump_table.append(Table(token_type).init());

                    var sub_tokens = [_]regex.Token{quant.inner.*};

                    var new_parents = ArrayList(*Node(token_type)).init();
                    new_parents.insert(insert_tokens(token_type, index, invert, jump_table, &sub_tokens, parents, idx));
                    new_parents.insert(insert_tokens(token_type, idx, invert, jump_table, &sub_tokens, parents, idx));

                    if (children.len != 0) {
                        new_parents.insert(insert_tokens(token_type, idx, invert, jump_table, children, parents, next));
                    }

                    return new_parents.get();
                },
            }
        },
    }
}

fn StaticJumpTable(token_type: type) type {
    return struct {
        len: usize,
        table: [*]const StaticTable(token_type),
    };
}

fn StaticTable(token_type: type) type {
    return struct {
        table: StaticMap(u21, Node(token_type)),
        sequences: StaticMap(u21, Node(token_type)),
        fallthrough: ?Fallthrough(token_type),
    };
}

fn FallthroughExpansion(token_type: type) type {
    return struct {
        index: usize,
        fallthrough: Fallthrough(token_type),
    };
}

fn expand_jump_table_fallthrough(token_type: type, jump_table: *JumpTable(token_type), index: usize, in_expansion: ?FallthroughExpansion(token_type)) void {
    var table = jump_table.at(index);
    if (table.expanded) {
        // already expanded, prevent infinite recursion
        return;
    }

    // currently expanding this branch
    if (in_expansion) |expansion| {
        const fallthrough = expansion.fallthrough;
        table.expanded = true;
        if (table.fallthrough != null and expansion.index != index) {
            return;
        }

        for (table.table.keys_iter()) |key| {
            switch (fallthrough.value) {
                .char => |char| {
                    if (key != char) {
                        const node = table.get(key) orelse unreachable;
                        const next_index = node.next orelse continue;

                        var next_table = jump_table.at(next_index);
                        if (next_table.fallthrough != null) {
                            continue;
                        }

                        next_table.fallthrough = fallthrough;
                        expand_jump_table_fallthrough(token_type, jump_table, next_index, expansion);
                    }
                },
                else => @compileError("unimplemented"),
            }
        }

        return;
    }

    // if this branch has a fallthrough, expand it
    if (table.fallthrough) |fallthrough| {
        expand_jump_table_fallthrough(token_type, jump_table, index, .{ .fallthrough = fallthrough, .index = index });
        return;
    }

    // not in an expansion and don't have a fallthrough
    table.expanded = true;
    for (table.table.keys_iter()) |key| {
        const node = table.get(key) orelse unreachable;
        const next_index = node.next orelse continue;

        expand_jump_table_fallthrough(token_type, jump_table, next_index, null);
    }
}

fn expand_jump_table_sequences(token_type: type, jump_table: *JumpTable(token_type), index: usize) void {
    const table = jump_table.at(index);
    if (table.expanded2) {
        // already expanded lol
        return;
    }

    table.expanded2 = true;
    if (table.sequences.len() != 0) {
        for (table.table.keys_iter()) |key| {
            for (table.sequences.keys_iter()) |seq_key| {
                if (!match_sequence(seq_key, key)) {
                    continue;
                }

                var node = table.table.at(key);
                const seq_node = table.sequences.at(seq_key);

                if (node.leaf == null) {
                    if (seq_node.leaf) |leaf| {
                        node.leaf = leaf;
                    }
                }

                if (node.next) |next| {
                    if (seq_node.next) |seq_next| {
                        var next_table = jump_table.at(next);
                        const next_seq_table = jump_table.at(seq_next);

                        next_table.merge(next_seq_table, jump_table, seq_next);
                    }
                } else {
                    if (seq_node.next) |seq_next| {
                        const next_seq_table = jump_table.at(seq_next);

                        const idx = jump_table.len();
                        jump_table.append(Table(token_type).init());

                        node.next = idx;

                        var next_table = jump_table.at(idx);
                        next_table.merge(next_seq_table, jump_table, seq_next);
                    }
                }
            }
        }
    }

    for (table.table.keys_iter()) |key| {
        const node = table.table.get(key) orelse unreachable;
        if (node.next) |next| {
            expand_jump_table_sequences(token_type, jump_table, next);
        }
    }
}

fn match_sequence(sequence: u21, key: u21) bool {
    switch (sequence) {
        'w' => {
            // uppercase letter
            if ('A' <= key and key <= 'Z') {
                return true;
            }

            // lowercase letter
            if ('a' <= key and key <= 'z') {
                return true;
            }

            return false;
        },
        '0' => {
            if ('0' <= key and key <= '9') {
                return true;
            }

            return false;
        },
        'W' => {
            if (match_sequence('w', key)) {
                return true;
            }

            if (match_sequence('0', key)) {
                return true;
            }

            return false;
        },
        else => unreachable,
    }
}

fn compile_static_jump_map(comptime token_patterns: []const TokenPattern, comptime TokenType: type) StaticJumpTable(TokenType) {
    if (!@inComptime()) {
        @compileError("This function must be executed at compile time.");
    }

    std.debug.assert(token_patterns.len > 0);

    @setEvalBranchQuota(token_patterns.len * 10000);

    var jump_table = JumpTable(TokenType).init();
    for (token_patterns, 0..) |token_pattern, i| {
        const tokens = regex.parsePattern(token_pattern.pattern) catch |err| @compileError(err);
        const nodes = insert_tokens(TokenType, 0, false, &jump_table, tokens, &.{}, null);
        for (nodes) |node| {
            node.leaf = std.meta.intToEnum(TokenType, i) catch unreachable;
        }
    }

    expand_jump_table_fallthrough(TokenType, &jump_table, 0, null);
    expand_jump_table_sequences(TokenType, &jump_table, 0);

    var static_table = ArrayList(StaticTable(TokenType)).init();
    for (jump_table.get()) |table| {
        static_table.append(.{
            .table = table.table.compile(),
            .sequences = table.sequences.compile(),
            .fallthrough = table.fallthrough,
        });
    }

    const len = static_table.len();
    const static_jump_table = static_table.get_static();

    return .{
        .len = len,
        .table = static_jump_table,
    };
}

fn compile_token_type(comptime token_patterns: []const TokenPattern) type {
    var enum_fields = ArrayList(std.builtin.Type.EnumField).init();
    for (token_patterns, 0..) |pattern, i| {
        var name: [pattern.name.len:0]u8 = undefined;
        for (pattern.name, 0..) |char, idx| {
            name[idx] = char;
        }

        enum_fields.append(.{
            .name = &name,
            .value = i,
        });
    }

    const tag = @Type(.{
        .Enum = .{
            .tag_type = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = @ceil(@log2(@as(f32, token_patterns.len))) } }),
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
            var token_types = ArrayList(std.builtin.Type.EnumField).init();
            for (tokens, 0..) |token, i| {
                token_types.append(.{
                    .name = @tagName(token),
                    .value = i,
                });
            }

            const matched_tag = @Type(.{
                .Enum = .{
                    .tag_type = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = @ceil(@log2(@as(f32, tokens.len))) } }),
                    .fields = token_types.get(),
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
    while (i < input.len - 1 and input[i + 1] != '\r' and input[i + 1] != '\n') : (i += 1) {}

    return i + 1;
}

fn renderErrorLine(allocator: std.mem.Allocator, line_start: usize, failure_start: usize, failure_end: usize) ![]u8 {
    var line = std.ArrayList(u8).init(allocator);
    try line.appendSlice("        ");

    var i = line_start;
    while (i < failure_start) : (i += 1) {
        try line.append(' ');
    }

    while (i < failure_end) : (i += 1) {
        try line.append('~');
    }

    try line.append('^');
    return line.toOwnedSlice();
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
        const line_number = findLineNumber(self.input, self.start);

        std.debug.print("unexpected input:\n", .{});
        std.debug.print(" {d: >4} | ", .{line_number});

        const input = self.input[line_start..line_end];
        for (input) |char| {
            var buffer: [4]u8 = undefined;
            _ = try std.unicode.utf8Encode(char, &buffer);
            std.debug.print("{s}", .{buffer});
        }

        const error_line = try renderErrorLine(self.allocator, line_start, self.start, self.end);
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

pub fn Lexer(comptime token_patterns: []const TokenPattern) type {
    return struct {
        const Self = @This();

        pub const Token = compile_token_type(token_patterns);
        pub const TokenType = Token.Tag;
        const static_jump_table = compile_static_jump_map(token_patterns, TokenType);

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

                const static_table = static_jump_table.table[i];
                for (0..static_table.table.len) |idx| {
                    const key_codepoint = static_table.table.keys[idx];
                    const value = static_table.table.values[idx];

                    const buffer = try uft8ToString(self.allocator, key_codepoint, false);
                    defer self.allocator.free(buffer);

                    if (value.next) |next| {
                        try std.fmt.format(writer, "  {s} -> {} [label=\"{s}\"];\n", .{ start, next, buffer });
                    }

                    if (value.leaf) |leaf| {
                        if (value.next) |next| {
                            try std.fmt.format(writer, "  {} -> {s} [label=\"super {s} leaf\" color=blue];\n", .{ next, @tagName(leaf), buffer });
                        } else {
                            try std.fmt.format(writer, "  {s} -> {s} [label=\"{s} leaf\" color=blue];\n", .{ start, @tagName(leaf), buffer });
                        }
                    }
                }

                for (0..static_table.sequences.len) |idx| {
                    const key_codepoint = static_table.sequences.keys[idx];
                    const value = static_table.sequences.values[idx];

                    const buffer = try uft8ToString(self.allocator, key_codepoint, true);
                    defer self.allocator.free(buffer);

                    if (value.next) |next| {
                        try std.fmt.format(writer, "  {s} -> {} [label=\"{s}\" color=orange];\n", .{ start, next, buffer });
                    }

                    if (value.leaf) |leaf| {
                        if (value.next) |next| {
                            try std.fmt.format(writer, "  {} -> {s} [label=\"super {s} leaf\" color=green];\n", .{ next, @tagName(leaf), buffer });
                        } else {
                            try std.fmt.format(writer, "  {s} -> {s} [label=\"{s} leaf\" color=green];\n", .{ start, @tagName(leaf), buffer });
                        }
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
                        try std.fmt.format(writer, "  {s} -> {} [label=\"{s}\" color=red];\n", .{ start, next, buffer });
                    }

                    if (value.leaf) |leaf| {
                        if (value.next) |next| {
                            try std.fmt.format(writer, "  {} -> {s} [label=\"super {s} leaf\" color=purple];\n", .{ next, @tagName(leaf), buffer });
                        } else {
                            try std.fmt.format(writer, "  {s} -> {s} [label=\"{s} leaf\" color=purple];\n", .{ start, @tagName(leaf), buffer });
                        }
                    }
                }
            }

            try std.fmt.format(writer, "}}\n", .{});
        }

        pub fn lex(self: *const Self, input: []const u21, opts: LexerOptions) ![]Token {
            var out = std.ArrayList(Token).init(self.allocator);
            defer out.deinit();

            opts.fill_failure(null);

            var i: usize = 0;
            var table_idx: usize = 0;
            var leaf: ?TokenType = null;
            var start: usize = 0;
            outer: while (i < input.len) : (i += 1) {
                const table = static_jump_table.table[table_idx];
                const char = input[i];

                for (0..table.table.len) |char_idx| {
                    const char_key = table.table.keys[char_idx];
                    if (char_key != char) {
                        continue;
                    }

                    const char_node = table.table.values[char_idx];
                    if (char_node.next) |next| {
                        table_idx = next;
                        leaf = char_node.leaf;
                    } else {
                        if (char_node.leaf) |char_leaf| {
                            try out.append(.{
                                .token_type = char_leaf,
                                .source = input[start .. i + 1],
                            });

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
                    const seq_key = table.sequences.keys[seq_idx];
                    if (!match_sequence(seq_key, char)) {
                        continue;
                    }

                    const seq_node = table.sequences.values[seq_idx];
                    if (seq_node.next) |next| {
                        table_idx = next;
                        leaf = seq_node.leaf;
                    } else {
                        if (seq_node.leaf) |seq_leaf| {
                            try out.append(.{
                                .token_type = seq_leaf,
                                .source = input[start .. i + 1],
                            });

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
                                try out.append(.{
                                    .token_type = fallthrough_leaf,
                                    .source = input[start .. i + 1],
                                });

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
                    try out.append(.{
                        .token_type = l,
                        .source = input[start..i],
                    });

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
                try out.append(.{
                    .token_type = l,
                    .source = input[start..i],
                });
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

            return out.toOwnedSlice();
        }
    };
}

fn uft8ToString(allocator: std.mem.Allocator, codepoint: u21, escaped: bool) ![]u8 {
    var buffer: [4]u8 = undefined;
    _ = try std.unicode.utf8Encode(codepoint, &buffer);

    const backslash = try replace(allocator, &buffer, "\\", "\\\\");
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
    var result = std.ArrayList(u8).init(allocator);

    var index: usize = 0;
    while (index < input.len) {
        if (std.mem.startsWith(u8, input[index..], target)) {
            try result.appendSlice(replacement);
            index += target.len;
        } else {
            try result.append(input[index]);
            index += 1;
        }
    }

    return result.toOwnedSlice();
}
