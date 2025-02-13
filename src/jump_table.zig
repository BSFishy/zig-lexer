const std = @import("std");
const regex = @import("regex.zig");
const ArrayList = @import("array_list.zig").ArrayList;
const map = @import("map.zig");

const Map = map.Map;
const StaticMap = map.StaticMap;

pub fn StaticJumpTable(TokenType: type) type {
    return struct {
        len: usize,
        tables: [*]const StaticTable(TokenType),
    };
}

pub fn TablePattern(TokenType: type) type {
    return struct {
        jump_table: JumpTable(TokenType),
        zero_length: bool,
    };
}

pub fn JumpTable(TokenType: type) type {
    return struct {
        const Self = @This();

        visiting: usize = 0,
        tables: ArrayList(Table(TokenType)),

        pub fn init() Self {
            return .{
                .tables = ArrayList(Table(TokenType)).init(),
            };
        }

        pub fn insert(self: *Self, patterns: []const regex.Token) []Index {
            var first_pattern = Self.fromPattern(patterns[0], false);
            var first_mappings = Map(usize, usize).init();
            var indicies = self.insert_jump_table(&first_pattern.jump_table, &first_mappings, 0, 0);
            for (patterns[1..], 1..) |pattern, idx| {
                var next_jump_table = Self.fromPattern(pattern, false);

                var next_tables = ArrayList(Index).init();
                var mappings = Map(usize, usize).init();
                if (idx == 1 and first_pattern.zero_length) {
                    next_tables.insert(self.insert_jump_table(&next_jump_table.jump_table, &mappings, 0, 0));
                }

                if (next_jump_table.zero_length) {
                    next_tables.insert(indicies);
                }

                for (indicies) |index| {
                    const node = index.node(TokenType, self);
                    const next = node.next orelse blk: {
                        node.next = self.tables.len;
                        break :blk node.next orelse unreachable;
                    };

                    next_tables.insert(self.insert_jump_table(&next_jump_table.jump_table, &mappings, next, 0));
                }

                indicies = next_tables.get();
            }

            return indicies;
        }

        fn fromPattern(pattern: regex.Token, invert: bool) TablePattern(TokenType) {
            var self = Self.init();
            var zero_length = false;
            switch (pattern) {
                .Char => |char| {
                    var table = self.getTable(0);
                    if (invert) {
                        if (table.fallthrough) |fallthrough| {
                            if (!fallthrough.value.compare(.{ .char = char })) {
                                @compileError("found multiple incompatible fallthroughs");
                            }
                        } else {
                            table.fallthrough = .{
                                .value = .{ .char = char },
                                .next = .{ .exit = true },
                            };
                        }
                    } else {
                        table.chars.put(char, .{ .exit = true });
                    }
                },
                .Sequence => |seq| {
                    var table = self.getTable(0);
                    table.sequences.put(seq, .{ .exit = true });
                },
                .Group => |group| {
                    for (group.chars) |char| {
                        // this can never be zero length so we dont have to
                        // worry about it :)
                        var jump_table = Self.fromPattern(.{ .Char = char }, group.invert);
                        var mappings = Map(usize, usize).init();
                        const indicies = self.insert_jump_table(&jump_table.jump_table, &mappings, 0, 0);
                        for (indicies) |index| {
                            var node = index.node(TokenType, &self);
                            node.exit = true;
                        }
                    }
                },
                .Capture => |capture| {
                    for (capture.options) |option| {
                        const indicies = self.insert(option);
                        for (indicies) |index| {
                            var node = index.node(TokenType, &self);
                            node.exit = true;
                        }
                    }
                },
                .Quantified => |quant| {
                    const inner = quant.inner.*;
                    if (quant.quantifier.hasZero()) {
                        zero_length = true;
                    }

                    // TODO: do we need to worry about zero length here?
                    var inner_jump_table = Self.fromPattern(inner, invert);
                    var mappings = Map(usize, usize).init();
                    const indicies = self.insert_jump_table(&inner_jump_table.jump_table, &mappings, 0, 0);

                    var no_next = ArrayList(Index).init();
                    var with_next = ArrayList(Index).init();
                    for (indicies) |index| {
                        const node = index.node(TokenType, &self);
                        node.exit = true;

                        if (node.next == null) {
                            no_next.append(index);
                        } else {
                            with_next.append(index);
                        }
                    }

                    if (quant.quantifier.hasMore()) {
                        mappings = Map(usize, usize).init();
                        if (no_next.len > 0) {
                            const idx = self.tables.len;
                            _ = self.getTable(idx);

                            const next_indicies = self.insert_jump_table(&inner_jump_table.jump_table, &mappings, idx, 0);
                            for (next_indicies) |next_index| {
                                var next_node = next_index.node(TokenType, &self);
                                next_node.exit = true;
                                if (next_node.next) |next| {
                                    std.debug.assert(next == idx);
                                } else {
                                    next_node.next = idx;
                                }
                            }

                            for (no_next.get()) |index| {
                                var node = index.node(TokenType, &self);
                                if (node.next) |next| {
                                    std.debug.assert(next == idx);
                                } else {
                                    node.next = idx;
                                }
                            }
                        }

                        for (with_next.get()) |index| {
                            @compileLog("here");
                            const node = index.node(TokenType, &self);
                            const idx = node.next orelse unreachable;

                            const next_indicies = self.insert_jump_table(&inner_jump_table.jump_table, idx, 0);
                            for (next_indicies) |next_index| {
                                var next_node = next_index.node(TokenType, &self);
                                next_node.exit = true;
                                if (next_node.next) |next| {
                                    std.debug.assert(next == idx);
                                } else {
                                    next_node.next = idx;
                                }
                            }
                        }
                    }
                },
            }

            // @compileLog(pattern);
            return .{ .jump_table = self, .zero_length = zero_length };
        }

        fn insert_jump_table(self: *Self, other: *Self, table_mapping: *Map(usize, usize), start: usize, other_start: usize) []Index {
            var indicies = ArrayList(Index).init();

            var table = self.getTable(start);
            var other_table = other.tables.at(other_start);

            if (other_table.visited) {
                return &.{};
            }

            other_table.visited = true;
            other.visiting += 1;
            defer {
                other.visiting -= 1;
                if (other.visiting == 0) {
                    other.clearVisiting();
                }
            }

            for (other_table.chars.keys_iter()) |key| {
                const other_node = other_table.chars.get(key) orelse unreachable;
                if (other_node.exit) {
                    indicies.append(.{
                        .table = start,
                        .branch = .{ .char = key },
                    });
                }

                var next_table: usize = undefined;
                var other_next: usize = undefined;
                if (other_node.next) |other_next_table| {
                    other_next = other_next_table;
                    if (table_mapping.get(other_next)) |new_next| {
                        next_table = new_next;

                        if (!table.chars.has(key)) {
                            table.chars.put(key, .{ .next = next_table });
                        }
                    } else {
                        if (table.chars.get_mut(key)) |node| {
                            if (node.next) |next| {
                                next_table = next;
                            } else {
                                next_table = self.tables.len;
                            }
                        } else {
                            if (other_next == other_start) {
                                next_table = start;
                            } else {
                                next_table = self.tables.len;
                            }

                            table.chars.put(key, .{ .next = next_table });
                        }
                    }
                } else {
                    if (!table.chars.has(key)) {
                        table.chars.put(key, .{});
                    }

                    continue;
                }

                table_mapping.put(other_next, next_table);
                indicies.insert(self.insert_jump_table(other, table_mapping, next_table, other_next));
            }

            for (other_table.sequences.keys_iter()) |key| {
                const other_node = other_table.sequences.get(key) orelse unreachable;
                if (other_node.exit) {
                    indicies.append(.{
                        .table = start,
                        .branch = .{ .sequence = key },
                    });
                }

                var next_table: usize = undefined;
                var other_next: usize = undefined;
                if (other_node.next) |other_next_table| {
                    other_next = other_next_table;
                    if (table_mapping.get(other_next)) |new_next| {
                        next_table = new_next;

                        if (!table.sequences.has(key)) {
                            table.sequences.put(key, .{ .next = next_table });
                        }
                    } else {
                        if (table.sequences.get_mut(key)) |node| {
                            if (node.next) |next| {
                                next_table = next;
                            } else {
                                next_table = self.tables.len;
                            }
                        } else {
                            if (other_next == other_start) {
                                next_table = start;
                            } else {
                                next_table = self.tables.len;
                            }

                            table.sequences.put(key, .{ .next = next_table });
                        }
                    }
                } else {
                    if (!table.sequences.has(key)) {
                        table.sequences.put(key, .{});
                    }

                    continue;
                }

                table_mapping.put(other_next, next_table);
                indicies.insert(self.insert_jump_table(other, table_mapping, next_table, other_next));
            }

            if (other_table.fallthrough) |other_fallthrough| {
                if (other_fallthrough.next.exit) {
                    indicies.append(.{ .table = start, .branch = .fallthrough });
                }

                if (table.fallthrough) |*table_fallthrough| {
                    if (!other_fallthrough.value.compare(table_fallthrough.value)) {
                        @compileError("multiple incompatible fallthroughs");
                    }
                } else {
                    table.fallthrough = .{
                        .value = other_fallthrough.value,
                        .next = .{},
                    };
                }

                const fallthrough = &(table.fallthrough orelse unreachable);
                const node = &fallthrough.next;
                const other_node = other_fallthrough.next;
                if (other_node.next) |other_next| {
                    var next_table: usize = undefined;
                    if (node.next) |next| {
                        next_table = next;
                    } else {
                        if (table_mapping.get(other_next)) |mapped_next| {
                            next_table = mapped_next;
                        } else {
                            const idx = self.tables.len;
                            next_table = idx;

                            table_mapping.put(other_next, idx);
                        }

                        node.next = next_table;
                    }

                    table_mapping.put(other_next, next_table);
                    indicies.insert(self.insert_jump_table(other, table_mapping, next_table, other_next));
                }
            }

            return indicies.get();
        }

        fn getTable(self: *Self, index: usize) *Table(TokenType) {
            while (self.tables.len < index + 1) {
                self.tables.append(Table(TokenType).init());
            }

            return self.tables.at(index);
        }

        fn clearVisiting(self: *Self) void {
            // @compileLog("cleared");
            for (0..self.tables.len) |idx| {
                var table = self.getTable(idx);
                table.visited = false;
            }
        }
    };
}

pub fn StaticTable(TokenType: type) type {
    return struct {
        chars: StaticMap(u21, Node(TokenType)),
        sequences: StaticMap(u21, Node(TokenType)),
        fallthrough: ?Fallthrough(TokenType),
    };
}

pub fn Table(TokenType: type) type {
    return struct {
        const Self = @This();

        chars: Map(u21, Node(TokenType)),
        sequences: Map(u21, Node(TokenType)),
        fallthrough: ?Fallthrough(TokenType),
        visited: bool = false,

        pub fn init() Self {
            return .{
                .chars = Map(u21, Node(TokenType)).init(),
                .sequences = Map(u21, Node(TokenType)).init(),
                .fallthrough = null,
            };
        }
    };
}

fn Node(TokenType: type) type {
    return struct {
        const Self = @This();

        leaf: ?TokenType = null,
        next: ?usize = null,
        exit: bool = false,
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

pub fn Fallthrough(token_type: type) type {
    return struct {
        value: FallthroughChar,
        next: Node(token_type),
    };
}

const Branch = union(enum) {
    char: u21,
    sequence: u21,
    fallthrough,
};

const Index = struct {
    const Self = @This();

    table: usize,
    branch: Branch,

    pub fn node(self: *const Self, TokenType: type, jump_table: *JumpTable(TokenType)) *Node(TokenType) {
        const table = jump_table.tables.at(self.table);
        return switch (self.branch) {
            .char => |char| table.chars.at(char),
            .sequence => |seq| table.sequences.at(seq),
            .fallthrough => &(table.fallthrough orelse @panic("unimplemented")).next,
        };
    }
};

pub fn match_sequence(sequence: u21, key: u21) bool {
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
