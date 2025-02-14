const std = @import("std");
const ArrayList = @import("array_list.zig").ArrayList;

pub fn Entry(comptime K: type, comptime V: type) type {
    return struct {
        key: K,
        value: V,
    };
}

pub fn StaticMap(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        len: usize,
        entries: [*]const Entry(K, V),

        pub fn get(self: *const Self, key: K) ?V {
            // TODO: make this O(1) instead of linear search
            for (self.keys, self.values) |k, v| {
                if (key == k) {
                    return v;
                }
            }

            return null;
        }

        pub fn has(self: *const Self, key: K) bool {
            return self.get(key) == null;
        }
    };
}

pub fn Map(K: type, V: type) type {
    return struct {
        const Self = @This();

        entries: ArrayList(Entry(K, V)),

        pub fn init() Self {
            return .{
                .entries = ArrayList(Entry(K, V)).init(),
            };
        }

        pub fn put(self: *Self, key: K, value: V) void {
            for (self.entries.get()) |*entry| {
                if (entry.key == key) {
                    entry.value = value;
                    return;
                }
            }

            self.entries.append(.{
                .key = key,
                .value = value,
            });
        }

        pub fn has(self: *Self, key: K) bool {
            for (self.entries.get()) |entry| {
                if (entry.key == key) {
                    return true;
                }
            }

            return false;
        }

        pub fn len(self: *const Self) usize {
            return self.entries.len;
        }

        pub fn get(self: *const Self, key: K) ?V {
            for (self.entries.get()) |entry| {
                if (entry.key == key) {
                    return entry.value;
                }
            }

            return null;
        }

        pub fn getEntries(self: *const Self) []Entry(K, V) {
            return self.entries.get();
        }

        pub fn get_mut(self: *Self, key: K) ?*V {
            for (self.entries.get()) |*entry| {
                if (entry.key == key) {
                    return &entry.value;
                }
            }

            return null;
        }

        pub fn compile(self: *const Self) StaticMap(K, V) {
            const length = self.entries.len;

            var ent: [length]Entry(K, V) = undefined;
            @memcpy(&ent, self.entries.contents[0..length]);

            const const_entries = ent;
            return .{
                .len = length,
                .entries = &const_entries,
            };
        }
    };
}
