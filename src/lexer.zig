const std = @import("std");
const regex = @import("regex.zig");
const ArrayList = @import("array_list.zig").ArrayList;
const map = @import("map.zig");

const Map = map.Map;
const StaticMap = map.StaticMap;

pub fn Token(token_type: type) type {
    return struct {
        token_type: token_type,
        value: []const u8,
    };
}

pub fn TokenPattern(token_type: type) type {
    return struct {
        token_type: token_type,
        pattern: []const u8,
    };
}

fn Node(token_type: type) type {
    return union(enum) {
        const Self = @This();

        leaf: token_type,
        next: usize,
        both: struct {
            next: usize,
            leaf: token_type,
        },

        pub fn compare(self: Self, other: Self) bool {
            switch (self) {
                .leaf => |a| {
                    switch (other) {
                        .leaf => |b| return a == b,
                        .next => return false,
                        .both => |b| return a == b.leaf,
                    }
                },
                .next => |a| {
                    switch (other) {
                        .leaf => return false,
                        .next => |b| return a == b,
                        .both => |b| return a == b.next,
                    }
                },
                .both => |a| {
                    switch (other) {
                        .leaf => return false,
                        .next => return false,
                        .both => |b| return a.next == b.next and a.leaf == b.leaf,
                    }
                },
            }
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
    };
}

fn JumpTable(token_type: type) type {
    return ArrayList(Table(token_type));
}

fn Child(token_type: type) type {
    return union(enum) {
        token: token_type,
        next: usize,
        both: struct {
            token: token_type,
            next: usize,
        },
    };
}

fn insert_tokens(token_type: type, index: usize, invert: bool, jump_table: *JumpTable(token_type), tokens: []regex.Token, child: Child(token_type)) void {
    const children = tokens[1..];
    var table = if (jump_table.len() > 0) jump_table.at(index) else blk: {
        jump_table.append(Table(token_type).init());

        break :blk jump_table.at(index);
    };

    switch (tokens[0]) {
        .Char => |c| {
            if (invert) {
                const value: FallthroughChar = .{ .char = c };
                const next: Node(token_type) = switch (child) {
                    .next => |idx| .{ .next = idx },
                    .token => |leaf| .{ .leaf = leaf },
                    .both => |both| .{ .both = .{ .next = both.next, .leaf = both.token } },
                };

                if (table.fallthrough) |fallthrough| {
                    if (fallthrough.value.compare(value) and fallthrough.next.compare(next)) {
                        if (fallthrough.next != .both and next == .both) {
                            table.setFallthrough(.{ .value = value, .next = next });
                        }

                        return;
                    } else {
                        @panic("cannot have multiple fallthroughs here");
                    }
                }

                table.setFallthrough(.{ .value = value, .next = next });

                return;
            }

            if (table.get(c)) |v| {
                switch (v) {
                    .next => |idx| {
                        if (children.len == 0) {
                            switch (child) {
                                .token => |token| {
                                    table.put(c, .{ .both = .{ .next = idx, .leaf = token } });
                                    return;
                                },
                                else => unreachable,
                            }
                        }

                        insert_tokens(token_type, idx, invert, jump_table, children, child);
                        return;
                    },
                    .leaf => |value| {
                        if (children.len == 0) {
                            @compileError("multiple identical patterns");
                        }

                        const idx = jump_table.len();
                        jump_table.append(Table(token_type).init());

                        table.put(c, .{ .both = .{ .next = idx, .invert = invert, .leaf = value } });
                        insert_tokens(token_type, idx, invert, jump_table, children, child);
                        return;
                    },
                    .both => |value| {
                        if (children.len == 0) {
                            @compileError("multiple identical patterns");
                        }

                        insert_tokens(token_type, value.next, jump_table, children, child);
                        return;
                    },
                }
            } else {
                if (children.len == 0) {
                    switch (child) {
                        .token => |chil| {
                            table.put(c, .{ .leaf = chil });
                            return;
                        },
                        .next => |idx| {
                            table.put(c, .{ .next = idx });
                            return;
                        },
                        else => unreachable,
                    }
                }

                const idx = jump_table.len();
                jump_table.append(Table(token_type).init());

                if (invert) {
                    table.put(c, .{ .next = .{ .invert = idx } });
                } else {
                    table.put(c, .{ .next = idx });
                }

                insert_tokens(token_type, idx, invert, jump_table, children, child);
                return;
            }
        },
        .Sequence => |c| {
            if (invert) {
                if (table.hasFallthrough()) {
                    @panic("cannot have multiple fallthroughs here");
                }

                table.setFallthrough(.{
                    .char = c,
                    .next = switch (child) {
                        .next => |idx| .{ .next = idx },
                        .token => |leaf| .{ .leaf = leaf },
                        .both => |both| .{ .both = .{ .next = both.next, .leaf = both.token } },
                    },
                });

                return;
            }

            if (table.sequences.get(c)) |v| {
                switch (v) {
                    .next => |idx| {
                        if (children.len == 0) {
                            switch (child) {
                                .token => |token| {
                                    table.sequences.put(c, .{ .both = .{ .next = idx, .leaf = token } });
                                    return;
                                },
                                else => unreachable,
                            }
                        }

                        insert_tokens(token_type, idx, invert, jump_table, children, child);
                        return;
                    },
                    .leaf => |value| {
                        if (children.len == 0) {
                            @compileError("multiple identical patterns");
                        }

                        const idx = jump_table.len();
                        jump_table.append(Table(token_type).init());

                        table.sequences.put(c, .{ .both = .{ .next = idx, .invert = invert, .leaf = value } });
                        insert_tokens(token_type, idx, invert, jump_table, children, child);
                        return;
                    },
                    .both => |value| {
                        if (children.len == 0) {
                            @compileError("multiple identical patterns");
                        }

                        insert_tokens(token_type, value.next, jump_table, children, child);
                        return;
                    },
                }
            } else {
                if (children.len == 0) {
                    switch (child) {
                        .token => |chil| {
                            table.sequences.put(c, .{ .leaf = chil });
                            return;
                        },
                        .next => |idx| {
                            table.sequences.put(c, .{ .next = idx });
                            return;
                        },
                        else => unreachable,
                    }
                }

                const idx = jump_table.len();
                jump_table.append(Table(token_type).init());

                if (invert) {
                    table.sequences.put(c, .{ .next = .{ .invert = idx } });
                } else {
                    table.sequences.put(c, .{ .next = idx });
                }

                insert_tokens(token_type, idx, invert, jump_table, children, child);
                return;
            }
        },
        .Group => |group| {
            for (group.chars) |char| {
                var sub_tokens = [_]regex.Token{.{ .Char = char }};
                if (children.len == 0) {
                    const c = switch (child) {
                        .token => |token| .{ .both = .{ .next = index, .token = token } },
                        .next => |next| .{ .next = next },
                        else => unreachable,
                    };

                    insert_tokens(token_type, index, group.invert, jump_table, &sub_tokens, c);
                } else {
                    const idx = jump_table.len();
                    jump_table.append(Table(token_type).init());

                    insert_tokens(token_type, index, group.invert, jump_table, &sub_tokens, .{ .next = idx });
                    insert_tokens(token_type, idx, invert, jump_table, children, child);
                }
            }
        },
        .Capture => |capture| {
            for (capture.options) |option| {
                if (children.len == 0) {
                    insert_tokens(token_type, index, invert, jump_table, option, child);
                } else {
                    const idx = jump_table.len();
                    jump_table.append(Table(token_type).init());

                    insert_tokens(token_type, index, invert, jump_table, option, .{ .next = idx });
                    insert_tokens(token_type, idx, invert, jump_table, children, child);
                }
            }
        },
        .Quantified => |quant| {
            switch (quant.quantifier) {
                .ZeroOrOne => {
                    var sub_tokens: [children.len + 1]regex.Token = undefined;
                    sub_tokens[0] = quant.inner.*;
                    for (children, 1..) |c, i| {
                        sub_tokens[i] = c;
                    }

                    if (children.len == 0) {
                        insert_tokens(token_type, index, invert, jump_table, &sub_tokens, child);
                        @compileError("zero or one at the end is not implemented correctly");
                    } else {
                        insert_tokens(token_type, index, invert, jump_table, &sub_tokens, child);
                        insert_tokens(token_type, index, invert, jump_table, children, child);
                    }
                },
                .ZeroOrMore => {
                    var sub_tokens = [_]regex.Token{quant.inner.*};
                    if (children.len == 0) {
                        insert_tokens(token_type, index, invert, jump_table, &sub_tokens, .{ .next = index });
                        insert_tokens(token_type, index, invert, jump_table, &sub_tokens, child);
                    } else {
                        insert_tokens(token_type, index, invert, jump_table, &sub_tokens, .{ .next = index });
                        insert_tokens(token_type, index, invert, jump_table, children, child);
                    }
                },
                .OneOrMore => {
                    const idx = jump_table.len();
                    jump_table.append(Table(token_type).init());

                    var sub_tokens = [_]regex.Token{quant.inner.*};
                    if (children.len == 0) {
                        insert_tokens(token_type, index, invert, jump_table, &sub_tokens, .{ .next = idx });
                        insert_tokens(token_type, idx, invert, jump_table, &sub_tokens, child);
                    } else {
                        insert_tokens(token_type, index, invert, jump_table, &sub_tokens, .{ .next = idx });
                        insert_tokens(token_type, idx, invert, jump_table, &sub_tokens, .{ .next = idx });
                        insert_tokens(token_type, idx, invert, jump_table, children, child);
                    }
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

fn Expansion(token_type: type) type {
    return struct {
        index: usize,
        fallthrough: Fallthrough(token_type),
    };
}

fn expand_jump_table(token_type: type, jump_table: *JumpTable(token_type), index: usize, in_expansion: ?Expansion(token_type)) void {
    var table = jump_table.at(index);
    if (table.expanded) {
        return;
    }

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
                        const next_index = switch (node) {
                            .next => |next| next,
                            .leaf => continue,
                            .both => |both| both.next,
                        };

                        var next_table = jump_table.at(next_index);
                        if (next_table.fallthrough != null) {
                            continue;
                        }

                        next_table.fallthrough = fallthrough;
                        expand_jump_table(token_type, jump_table, next_index, expansion);
                    }
                },
                else => @compileError("unimplemented"),
            }
        }

        return;
    }

    if (table.fallthrough) |fallthrough| {
        expand_jump_table(token_type, jump_table, index, .{ .fallthrough = fallthrough, .index = index });
        return;
    }

    table.expanded = true;
    for (table.table.keys_iter()) |key| {
        const node = table.get(key) orelse unreachable;
        const next_index = switch (node) {
            .next => |next| next,
            .leaf => continue,
            .both => |both| both.next,
        };

        expand_jump_table(token_type, jump_table, next_index, null);
    }
}

fn compile_static_jump_map(token_type: type, comptime token_patterns: []const TokenPattern(token_type)) StaticJumpTable(token_type) {
    if (!@inComptime()) {
        @compileError("This function must be executed at compile time.");
    }

    std.debug.assert(token_patterns.len > 0);

    @setEvalBranchQuota(token_patterns.len * 10000);

    var jump_table = JumpTable(token_type).init();
    for (token_patterns) |token_pattern| {
        const tokens = regex.parsePattern(token_pattern.pattern) catch |err| @compileError(err);
        insert_tokens(token_type, 0, false, &jump_table, tokens, .{ .token = token_pattern.token_type });
    }

    expand_jump_table(token_type, &jump_table, 0, null);

    var static_table = ArrayList(StaticTable(token_type)).init();
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

pub fn Lexer(token_type: type, comptime token_patterns: []const TokenPattern(token_type)) type {
    return struct {
        const Self = @This();

        pub fn to_graph(writer: anytype, allocator: std.mem.Allocator) !void {
            const static_jump_table = comptime compile_static_jump_map(token_type, token_patterns);
            try std.fmt.format(writer, "digraph {{\n", .{});

            for (0..static_jump_table.len) |i| {
                const start = if (i == 0) try allocator.dupe(u8, "start") else try std.fmt.allocPrint(allocator, "{}", .{i});
                defer allocator.free(start);

                const static_table = static_jump_table.table[i];
                for (0..static_table.table.len) |idx| {
                    const key_codepoint = static_table.table.keys[idx];
                    const value = static_table.table.values[idx];

                    const buffer = try uft8ToString(allocator, key_codepoint, false);
                    defer allocator.free(buffer);

                    switch (value) {
                        .next => |next| {
                            try std.fmt.format(writer, "  {s} -> {} [label=\"{s}\"];\n", .{ start, next, buffer });
                        },
                        .leaf => |leaf| {
                            try std.fmt.format(writer, "  {s} -> \"{}\" [label=\"{s}\"];\n", .{ start, leaf, buffer });
                        },
                        .both => |both| {
                            try std.fmt.format(writer, "  {s} -> {} [label=\"{s}\"];\n", .{ start, both.next, buffer });
                            try std.fmt.format(writer, "  {} -> \"{}\" [label=leaf color=blue];\n", .{ both.next, both.leaf });
                        },
                    }
                }

                for (0..static_table.sequences.len) |idx| {
                    const key_codepoint = static_table.sequences.keys[idx];
                    const value = static_table.sequences.values[idx];

                    const buffer = try uft8ToString(allocator, key_codepoint, true);
                    defer allocator.free(buffer);

                    switch (value) {
                        .next => |next| {
                            try std.fmt.format(writer, "  {s} -> {} [label=\"{s}\" color=orange];\n", .{ start, next, buffer });
                        },
                        .leaf => |leaf| {
                            try std.fmt.format(writer, "  {s} -> \"{}\" [label=\"{s}\" color=orange];\n", .{ start, leaf, buffer });
                        },
                        .both => |both| {
                            try std.fmt.format(writer, "  {s} -> {} [label=\"{s}\" color=orange];\n", .{ start, both.next, buffer });
                            try std.fmt.format(writer, "  {} -> \"{}\" [label=leaf color=green];\n", .{ both.next, both.leaf });
                        },
                    }
                }

                if (static_table.fallthrough) |fallthrough| {
                    const buffer = try uft8ToString(allocator, switch (fallthrough.value) {
                        .char => |char| char,
                        .sequence => |char| char,
                    }, switch (fallthrough.value) {
                        .char => false,
                        .sequence => true,
                    });
                    defer allocator.free(buffer);

                    switch (fallthrough.next) {
                        .next => |next| {
                            try std.fmt.format(writer, "  {s} -> {} [label=\"{s}\" color=red];\n", .{ start, next, buffer });
                        },
                        .leaf => |leaf| {
                            try std.fmt.format(writer, "  {s} -> \"{}\" [label=\"{s}\" color=red];\n", .{ start, leaf, buffer });
                        },
                        .both => |both| {
                            try std.fmt.format(writer, "  {s} -> {} [label=\"{s}\" color=red];\n", .{ start, both.next, buffer });
                            try std.fmt.format(writer, "  {} -> \"{}\" [label=leaf color=purple];\n", .{ both.next, both.leaf });
                        },
                    }
                }
            }

            try std.fmt.format(writer, "}}\n", .{});
        }

        pub fn lex(allocator: std.mem.Allocator, input: []const u8) !std.ArrayList(Token(token_type)) {
            var out = std.ArrayList(Token(token_type)).init(allocator);
            for (token_patterns) |t| {
                if (std.mem.eql(u8, t.pattern, input)) {
                    try out.append(.{
                        .token_type = t.token_type,
                        .value = input,
                    });
                }
            }

            return out;
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
