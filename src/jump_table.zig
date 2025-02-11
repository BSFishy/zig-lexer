const std = @import("std");
const regex = @import("regex.zig");
const ArrayList = @import("array_list.zig").ArrayList;
const map = @import("map.zig");

const Map = map.Map;
const StaticMap = map.StaticMap;

pub fn JumpTable(TokenType: type) type {
    return struct {
        const Self = @This();

        tables: ArrayList(Table(TokenType)),

        pub fn init() Self {
            return .{
                .tables = .init(),
            };
        }

        pub fn insert(self: *Self, patterns: []const regex.Token) void {
            var from_tables: []usize = &.{0};
            for (patterns) |pattern| {
                const next_jump_table = Self.fromPattern(&pattern);

                var next_tables = ArrayList(usize).init();
                for (from_tables) |table| {
                    next_tables.insert(self.insert_jump_table(next_jump_table, table));
                }

                from_tables = next_tables.get();
            }
        }

        fn fromPattern(pattern: *const regex.Token) Self {
            var self = Self.init();
            switch (pattern) {
                .Char => |char| {
                    var table = self.getTable(0);

                    table.chars.put(char, .{});
                },
                else => {
                    @compileError("unimplemented");
                },
            }

            return self;
        }

        fn insert_jump_table(self: *Self, other: *const Self, start: usize) []usize {
            _ = start; // autofix
            _ = other; // autofix
            _ = self; // autofix
        }

        fn getTable(self: *Self, index: usize) *Table(TokenType) {
            while (self.tables.len < index) {
                self.tables.append(Table(TokenType).init());
            }

            return self.tables.at(index);
        }
    };
}

pub fn Table(TokenType: type) type {
    return struct {
        const Self = @This();

        chars: Map(u21, Node(TokenType)),
        sequences: Map(u21, Node(TokenType)),

        pub fn init() Self {
            return .{
                .chars = .init(),
                .sequences = .init(),
            };
        }
    };
}

fn Node(TokenType: type) type {
    return struct {
        const Self = @This();

        leaf: ?TokenType = null,
        next: ?usize = null,
    };
}
