const std = @import("std");

const initial_capacity = 8;
const extension_amount = 8;

fn uninit(typ: type, len: usize) []?typ {
    var out = [_]?typ{null} ** len;
    return out[0..];
}

/// A comptime compatible dynamic array. Since it happens in comptime, there
/// shouldn't be issues with stack overflows or anything like that, I hope.
///
/// NOTE: only works in comptime
pub fn ArrayList(typ: type) type {
    return struct {
        const Self = @This();

        contents: []?typ,

        pub fn init() Self {
            // var contents = [_]?typ{null} ** initial_capacity;
            return Self{
                .contents = uninit(typ, initial_capacity),
            };
        }

        pub fn import(input: []typ) Self {
            // var contents = [_]?typ{null} ** input.len;
            var contents = uninit(typ, input.len);
            for (input, 0..) |val, i| {
                contents[i] = val;
            }

            return Self{
                .contents = contents,
            };
        }

        pub fn len(self: *const Self) usize {
            // @setEvalBranchQuota(100000);
            // @setEvalBranchQuota(10 * self.contents.len * std.math.log2_int_ceil(usize, self.contents.len));

            var l: usize = 0;
            for (self.contents) |item| {
                if (item) |_| {
                    l += 1;
                } else {
                    break;
                }
            }

            return l;
        }

        pub fn is_empty(self: *Self) bool {
            return self.len() == 0;
        }

        /// extends the capacity of the internal storage. this may fail if the number of
        /// elements exceeds 1000. if that is the case, probably just use simpler patterns.
        pub fn extend(self: *Self, amount: usize) void {
            const new_capacity = self.contents.len + amount;
            // @setEvalBranchQuota(10 * new_capacity * std.math.log2_int_ceil(usize, new_capacity));
            // var new = [_]?typ{null} ** new_capacity;
            var new = uninit(typ, new_capacity);
            for (self.contents, 0..) |item, i| {
                new[i] = item;
            }

            self.contents = new;
        }

        pub fn append(self: *Self, item: typ) void {
            const l = self.len();
            if (l >= self.contents.len - 1) {
                self.extend(extension_amount);
            }

            self.contents[l] = item;
        }

        pub fn set(self: *Self, index: usize, item: typ) void {
            if (index >= self.len()) {
                @compileError("array out of bounds error");
            }

            self.contents[index] = item;
        }

        pub fn insert(self: *Self, other: []typ) void {
            for (other) |item| {
                self.append(item);
            }
        }

        pub fn get(self: *const Self) []typ {
            var out = [_]typ{undefined} ** self.len();
            for (out, 0..) |_, i| {
                out[i] = self.contents[i].?;
            }

            return out[0..];
        }

        pub fn has(self: *const Self, item: typ) bool {
            for (0..self.len()) |i| {
                if (self.contents[i] orelse unreachable == item) {
                    return true;
                }
            }

            return false;
        }

        pub fn get_static(self: *const Self) [*]const typ {
            const length = self.len();
            const values = self.get();

            var out: [length]typ = undefined;
            for (values, 0..) |val, i| {
                out[i] = val;
            }

            const static_out = out;
            return &static_out;
        }

        pub fn at(self: *Self, idx: usize) *typ {
            if (idx >= self.len()) {
                @panic("index out of bounds error");
            }

            return &(self.contents[idx] orelse unreachable);
        }

        // pub fn get_mut(self: *Self) []*typ {
        //     var out = [_]*typ{undefined} ** self.len();
        //     for (out, 0..) |_, i| {
        //         const value = &(self.contents[i] orelse unreachable);
        //         out[i] = value;
        //     }
        //
        //     return &out;
        // }
    };
}

test "works" {
    comptime {
        var list = ArrayList(u8).init();
        list.append(1);
        list.append(2);
        list.append(3);
        try std.testing.expect(list.len() == 3);

        list.append(4);
        list.append(5);
        list.append(6);
        try std.testing.expect(list.len() == 6);

        list.append(7);
        list.append(8);
        list.append(9);
        try std.testing.expect(list.len() == 9);

        for (list.get(), 0..) |item, i| {
            try std.testing.expect(item == i + 1);
        }
    }
}
