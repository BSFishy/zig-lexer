const std = @import("std");
const ArrayList = @import("array_list.zig").ArrayList;

const TokenType = union(enum) {
    const Self = @This();

    Char: u21,
    Escape,
    GroupStart,
    GroupEnd,
    CaptureStart,
    CaptureEnd,
    Star,
    Question,
    Plus,
    Or,
    Carat,

    fn to_char(self: Self) u21 {
        switch (self) {
            .Char => |c| return c,
            .Escape => return '\\',
            .GroupStart => return '[',
            .GroupEnd => return ']',
            .CaptureStart => return '(',
            .CaptureEnd => return ')',
            .Star => return '*',
            .Question => return '?',
            .Plus => return '+',
            .Or => return '|',
            .Carat => return '^',
        }
    }
};

pub const Token = union(enum) {
    Char: u21,
    Sequence: u21,
    Group: Group,
    Capture: Capture,
    Quantified: Quantified,
};

pub const Group = struct {
    invert: bool,
    chars: []const u21,
};

pub const Capture = struct {
    const Self = @This();

    options: [][]Token,

    pub fn expands(self: Self) bool {
        return self.options.len > 1;
    }
};

pub const Quantified = struct {
    quantifier: Quantifier,
    inner: *Token,
};

pub const Quantifier = enum {
    ZeroOrMore,
    OneOrMore,
    ZeroOrOne,
};

pub fn parsePattern(pattern: []const u8) ![]Token {
    const tokens = try toTokens(pattern);
    var parser = Parser.init(truncate(TokenType, tokens));

    return parser.parse();
}

fn toTokens(pattern: []const u8) ![]?TokenType {
    var tokens = [_]?TokenType{null} ** pattern.len;
    var utf8 = (try std.unicode.Utf8View.init(pattern)).iterator();
    var i: usize = 0;
    while (utf8.nextCodepoint()) |codepoint| {
        switch (codepoint) {
            '[' => tokens[i] = TokenType{ .GroupStart = undefined },
            ']' => tokens[i] = TokenType{ .GroupEnd = undefined },
            '\\' => tokens[i] = TokenType{ .Escape = undefined },
            '^' => tokens[i] = TokenType{ .Carat = undefined },
            '(' => tokens[i] = TokenType{ .CaptureStart = undefined },
            ')' => tokens[i] = TokenType{ .CaptureEnd = undefined },
            '*' => tokens[i] = TokenType{ .Star = undefined },
            '?' => tokens[i] = TokenType{ .Question = undefined },
            '+' => tokens[i] = TokenType{ .Plus = undefined },
            '|' => tokens[i] = TokenType{ .Or = undefined },
            else => tokens[i] = TokenType{ .Char = codepoint },
        }
        i += 1;
    }

    return &tokens;
}

const Parser = struct {
    const Self = @This();

    i: usize,
    tokens: []const TokenType,

    fn init(tokens: []const TokenType) Self {
        return Self{
            .i = 0,
            .tokens = tokens,
        };
    }

    fn parse(self: *Self) ![]Token {
        var out = [_]?Token{null} ** self.tokens.len;
        var i: usize = 0;
        while (try self.next()) |token| {
            out[i] = token;
            i += 1;
        }

        return truncate(Token, &out);
    }

    fn next(self: *Self) !?Token {
        const peek = self.peek_token();
        if (peek) |p| {
            var node = switch (p) {
                .Char => |c| self.next_char(c),
                .Carat => self.next_char('^'),
                .Escape => try self.next_escape(),
                .GroupStart => try self.next_group(),
                .CaptureStart => try self.next_capture(),
                else => return error.invalidPattern,
            };

            const quant_peek = self.peek_token();
            if (quant_peek) |quant| {
                switch (quant) {
                    .Star => {
                        self.bump();
                        return Token{ .Quantified = Quantified{
                            .quantifier = Quantifier.ZeroOrMore,
                            .inner = &node,
                        } };
                    },
                    .Plus => {
                        self.bump();
                        return Token{ .Quantified = Quantified{
                            .quantifier = Quantifier.OneOrMore,
                            .inner = &node,
                        } };
                    },
                    .Question => {
                        self.bump();
                        return Token{ .Quantified = Quantified{
                            .quantifier = Quantifier.ZeroOrOne,
                            .inner = &node,
                        } };
                    },
                    else => {},
                }
            }
            return node;
        } else {
            return null;
        }
    }

    fn bump(self: *Self) void {
        self.i += 1;
    }

    fn peek_token(self: *Self) ?TokenType {
        return index(TokenType, self.tokens, self.i);
    }

    fn next_char(self: *Self, c: u21) Token {
        self.bump();
        return Token{ .Char = c };
    }

    fn next_sequence(self: *Self, c: u21) Token {
        self.bump();
        return Token{ .Sequence = c };
    }

    fn next_escape(self: *Self) !Token {
        self.bump();

        const peek = self.peek_token();
        if (peek) |p| {
            const char = p.to_char();
            switch (char) {
                'w' => return self.next_sequence('w'),
                'W' => return self.next_sequence('W'),
                '\\' => return self.next_char('\\'),
                else => {
                    var buffer: [4]u8 = undefined;
                    _ = std.unicode.utf8Encode(char, &buffer) catch unreachable;

                    @compileError("invalid pattern: \\" ++ buffer);
                },
            }
        } else {
            return error.invalidPattern;
        }
    }

    fn next_group(self: *Self) !Token {
        self.bump();

        var invert = false;
        var items = [_]?u21{null} ** self.tokens.len;
        for (items, 0..) |_, i| {
            const peek = self.peek_token();
            if (peek) |p| {
                self.bump();
                switch (p) {
                    .Char => |c| items[i] = c,
                    .Escape => {
                        const char = self.peek_token();
                        self.bump();

                        if (char) |c| {
                            items[i] = c.to_char();
                        } else {
                            return error.invalidPattern;
                        }
                    },
                    .Carat => if (i == 0) {
                        invert = true;
                    } else {
                        items[i] = '^';
                    },
                    .GroupEnd => break,
                    else => return error.invalidPattern,
                }
            } else {
                return error.invalidPattern;
            }
        }

        return Token{ .Group = Group{
            .invert = invert,
            .chars = truncate(u21, &items),
        } };
    }

    fn next_capture(self: *Self) !Token {
        self.bump();

        var options = ArrayList([]Token).init();
        var option = ArrayList(Token).init();
        while (true) {
            const peek = self.peek_token();
            if (peek) |p| {
                switch (p) {
                    .CaptureEnd => {
                        self.bump();
                        break;
                    },
                    .Or => {
                        self.bump();
                        options.append(option.get());
                        option = ArrayList(Token).init();
                    },
                    else => option.append(try self.next() orelse unreachable),
                }
            } else {
                return error.invalidPattern;
            }
        }

        if (!option.is_empty()) {
            options.append(option.get());
        }

        return Token{ .Capture = Capture{ .options = options.get() } };
    }
};

fn truncate(typ: type, in: []const ?typ) []typ {
    var len: usize = 0;
    for (in) |item| {
        if (item) |_| {
            len += 1;
        }
    }

    var out = [_]typ{undefined} ** len;
    var i: usize = 0;
    for (in) |item| {
        if (item) |it| {
            out[i] = it;
            i += 1;
        }
    }

    return &out;
}

fn index(typ: type, arr: []const typ, i: usize) ?typ {
    if (i >= arr.len) {
        return null;
    }

    return arr[i];
}
