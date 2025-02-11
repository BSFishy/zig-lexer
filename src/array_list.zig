const std = @import("std");

const extension_amount = 8;

/// A comptime compatible dynamic array. Since it happens in comptime, there
/// shouldn't be issues with stack overflows or anything like that, I hope.
///
/// NOTE: only works in comptime
pub fn ArrayList(Item: type) type {
    return struct {
        const Self = @This();

        contents: []Item,
        len: usize,

        pub fn init() Self {
            return Self{
                .contents = &.{},
                .len = 0,
            };
        }

        pub fn import(other: []const Item) Self {
            var data: [other.len]Item = undefined;
            @memcpy(data[0..], other);

            return .{
                .contents = &data,
                .len = other.len,
            };
        }

        pub fn is_empty(self: *Self) bool {
            return self.len == 0;
        }

        pub fn extend(self: *Self, amount: usize) void {
            const new_capacity = self.contents.len + amount;
            var new: [new_capacity]Item = undefined;
            @memcpy(new[0..self.contents.len], self.contents);

            self.contents = &new;
        }

        pub fn append(self: *Self, item: Item) void {
            if (self.len >= self.contents.len) {
                self.extend(extension_amount);
            }

            self.contents[self.len] = item;
            self.len += 1;
        }

        pub fn set(self: *Self, index: usize, item: Item) void {
            if (index >= self.len()) {
                @compileError("array out of bounds error");
            }

            self.contents[index] = item;
        }

        pub fn insert(self: *Self, other: []const Item) void {
            // TODO: this could also be a memcpy but i am too lazy to figure out
            // that single line right now
            for (other) |item| {
                self.append(item);
            }
        }

        pub fn get(self: *const Self) []Item {
            return self.contents[0..self.len];
        }

        pub fn has(self: *const Self, item: Item) bool {
            for (self.contents[0..self.len]) |i| {
                if (i == item) {
                    return true;
                }
            }

            return false;
        }

        pub fn get_static(self: *const Self) [*]const Item {
            var out: [self.len]Item = undefined;
            @memcpy(&out, self.contents[0..self.len]);

            const static_out = out;
            return &static_out;
        }

        pub fn at(self: *Self, idx: usize) *Item {
            if (idx >= self.len) {
                @panic("index out of bounds error");
            }

            return &(self.contents[idx]);
        }
    };
}

test "works" {
    comptime {
        var list = ArrayList(u8).init();
        list.append(1);
        list.append(2);
        list.append(3);
        try std.testing.expect(list.len == 3);

        list.append(4);
        list.append(5);
        list.append(6);
        try std.testing.expect(list.len == 6);

        list.append(7);
        list.append(8);
        list.append(9);
        try std.testing.expect(list.len == 9);

        list.append(1);
        list.append(2);
        list.append(3);
        try std.testing.expect(list.len == 12);

        list.append(4);
        list.append(5);
        list.append(6);
        try std.testing.expect(list.len == 15);

        list.append(7);
        list.append(8);
        list.append(9);
        try std.testing.expect(list.len == 18);

        for (list.get(), 0..) |item, i| {
            try std.testing.expect(item == i % 9 + 1);
        }
    }
}
