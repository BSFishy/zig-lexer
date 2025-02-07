const std = @import("std");
const ArrayList = @import("array_list.zig").ArrayList;

pub fn StaticMap(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        len: usize,
        keys: [*]const K,
        values: [*]const V,

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

        keys: ArrayList(K),
        values: ArrayList(V),

        pub fn init() Self {
            return .{
                .keys = ArrayList(K).init(),
                .values = ArrayList(V).init(),
            };
        }

        pub fn put(self: *Self, key: K, value: V) void {
            for (self.keys.get(), 0..) |k, i| {
                if (key == k) {
                    self.values.set(i, value);
                    return;
                }
            }

            if (K == u21) {
                // @compileLog("putting", std.unicode.utf8EncodeComptime(key), value);
            }

            self.keys.append(key);
            self.values.append(value);
        }

        pub fn has(self: *Self, key: K) bool {
            for (self.keys.get()) |k| {
                if (key == k) {
                    return true;
                }
            }

            return false;
        }

        pub fn len(self: *const Self) usize {
            return self.keys.len;
        }

        pub fn get(self: *const Self, key: K) ?V {
            for (self.keys.get(), self.values.get()) |k, value| {
                if (key == k) {
                    return value;
                }
            }

            return null;
        }

        pub fn get_mut(self: *Self, key: K) ?*V {
            for (self.keys.get(), 0..) |k, i| {
                if (key == k) {
                    return self.values.at(i);
                }
            }

            return null;
        }

        pub fn at(self: *Self, key: K) *V {
            for (self.keys.get(), 0..) |k, i| {
                if (key == k) {
                    return self.values.at(i);
                }
            }

            unreachable;
        }

        pub fn keys_iter(self: *const Self) []K {
            return self.keys.get();
        }

        pub fn compile(self: *const Self) StaticMap(K, V) {
            const length = self.keys.len;

            var keys: [length]K = undefined;
            var values: [length]V = undefined;
            @memcpy(&keys, self.keys.contents[0..length]);
            @memcpy(&values, self.values.contents[0..length]);

            // @compileLog(self.keys.contents, keys);
            // @compileLog(self.values.contents, values);

            const const_keys = keys;
            const const_values = values;
            return .{
                .len = length,
                .keys = &const_keys,
                .values = &const_values,
            };
        }
    };
}
