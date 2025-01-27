const std = @import("std");
const ArrayList = @import("array_list.zig").ArrayList;

const regex = @import("regex.zig");
const Token = regex.Token;
const Quantifier = regex.Quantifier;

const Key = union(enum) {
    const Self = @This();

    Char: u21,
    Sequence: u21,

    fn to_string(self: Self) []const u8 {
        var buffer: [4]u8 = undefined;
        const encoded_len = std.unicode.utf8Encode(switch (self) {
            .Char => |c| c,
            .Sequence => |s| s,
        }, &buffer) catch unreachable;
        return buffer[0..encoded_len];
    }
};

fn Branch(token_type: type) type {
    return struct {
        key: Key,
        node: ?*const Node(token_type),
        invert: bool,
        leaf: ?token_type,
        cyclical: bool = false,
    };
}

fn setNullBranches(token_type: type, branches: []Branch(token_type), child: ?*Node(token_type)) []Branch(token_type) {
    for (branches) |*branch| {
        if (branch.node) |node| {
            _ = setNullBranches(token_type, node.branches, child);
        } else {
            branch.node = child;
        }
    }

    return branches;
}

pub fn Node(token_type: type) type {
    if (!@inComptime()) {
        @compileError("not in comptime");
    }

    return struct {
        const Self = @This();

        branches: []const Branch(token_type),

        pub fn init(tokens: []Token, leaf_value: ?token_type, child_value: ?*Self) Self {
            const children = tokens[1..];
            var child: ?*Self = child_value;
            if (children.len != 0) {
                // child = Self.init(children, leaf_value, child_value);
                var tmp = Self.init(children, leaf_value, child_value);
                child = &tmp;
            }

            const leaf: ?token_type = if (child == null) leaf_value else null;
            var branches = ArrayList(Branch(token_type)).init();
            switch (tokens[0]) {
                .Char => |c| {
                    branches.append(Branch(token_type){
                        .key = Key{ .Char = c },
                        .node = child,
                        .invert = false,
                        .leaf = leaf,
                    });
                },
                .Group => |group| {
                    for (group.chars) |c| {
                        branches.append(Branch(token_type){
                            .key = Key{ .Char = c },
                            .node = child,
                            .invert = group.invert,
                            .leaf = leaf,
                        });
                    }
                },
                .Capture => |capture| {
                    for (capture.options) |option| {
                        const node = Self.init(option, null, child);
                        for (node.branches) |branch| {
                            branches.append(branch);
                        }
                    }

                    branches = ArrayList(Branch(token_type)).import(setNullBranches(token_type, branches.get(), child));
                },
                .Quantified => |quant| {
                    var token = [_]Token{quant.inner.*};
                    const node = Self.init(&token, null, child);

                    var quant_branches = ArrayList(Branch(token_type)).init();
                    for (node.branches) |branch| {
                        quant_branches.append(branch);
                    }

                    switch (quant.quantifier) {
                        .ZeroOrOne => {
                            // for (setNullBranches(token_type, quant_branches.get(), child)) |branch| {
                            //     branches.append(branch);
                            // }
                            for (quant_branches.get()) |branch| {
                                branches.append(branch);
                            }

                            if (child) |c| {
                                for (c.branches) |branch| {
                                    branches.append(branch);
                                }
                            }
                        },
                        else => @compileError("unimplemented"),
                    }
                },
            }

            return Self{
                .id = undefined,
                .branches = branches.get(),
            };
        }

        // pub fn debug(self: Self, indent: usize) void {
        //     for (self.branches) |branch| {
        //         const data = std.fmt.comptimePrint("{s}{s}{s}", .{ createIndent(indent), branch.key.to_string(), if (branch.leaf) |leaf| std.fmt.comptimePrint(" - {any}", .{leaf}) else "" });
        //         @compileLog(data);
        //
        //         if (branch.node) |node| {
        //             node.debug(indent + 1);
        //         } else {
        //             const node = std.fmt.comptimePrint("{s}null branch", .{createIndent(indent + 1)});
        //             @compileLog(node);
        //         }
        //     }
        // }
    };
}
