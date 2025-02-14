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
    const Self = @This();

    ZeroOrMore,
    OneOrMore,
    ZeroOrOne,

    pub fn hasZero(self: Self) bool {
        switch (self) {
            .ZeroOrOne, .ZeroOrMore => return true,
            else => return false,
        }
    }

    pub fn hasMore(self: Self) bool {
        switch (self) {
            .ZeroOrMore, .OneOrMore => return true,
            else => return false,
        }
    }
};

pub fn parsePattern(pattern: []const u8) ![]Token {
    var parser = Parser.init(try toTokens(pattern));

    return parser.parse();
}

fn toTokens(pattern: []const u8) ![]TokenType {
    var tokens = ArrayList(TokenType).init();
    var utf8 = (try std.unicode.Utf8View.init(pattern)).iterator();
    while (utf8.nextCodepoint()) |codepoint| {
        switch (codepoint) {
            '[' => tokens.append(TokenType{ .GroupStart = undefined }),
            ']' => tokens.append(TokenType{ .GroupEnd = undefined }),
            '\\' => tokens.append(TokenType{ .Escape = undefined }),
            '^' => tokens.append(TokenType{ .Carat = undefined }),
            '(' => tokens.append(TokenType{ .CaptureStart = undefined }),
            ')' => tokens.append(TokenType{ .CaptureEnd = undefined }),
            '*' => tokens.append(TokenType{ .Star = undefined }),
            '?' => tokens.append(TokenType{ .Question = undefined }),
            '+' => tokens.append(TokenType{ .Plus = undefined }),
            '|' => tokens.append(TokenType{ .Or = undefined }),
            else => tokens.append(TokenType{ .Char = codepoint }),
        }
    }

    return tokens.get();
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
        var out = ArrayList(Token).init();
        while (try self.next()) |token| {
            out.append(token);
        }

        return out.get();
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
                        return .{ .Quantified = Quantified{ .quantifier = Quantifier.ZeroOrMore, .inner = &node } };
                    },
                    .Plus => {
                        self.bump();
                        return .{ .Quantified = Quantified{ .quantifier = Quantifier.OneOrMore, .inner = &node } };
                    },
                    .Question => {
                        self.bump();
                        return .{ .Quantified = Quantified{ .quantifier = Quantifier.ZeroOrOne, .inner = &node } };
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
        if (self.i >= self.tokens.len) {
            return null;
        }

        return self.tokens[self.i];
    }

    fn next_char(self: *Self, c: u21) Token {
        self.bump();
        return .{ .Char = c };
    }

    fn next_sequence(self: *Self, c: u21) Token {
        self.bump();
        return .{ .Sequence = c };
    }

    fn next_escape(self: *Self) !Token {
        self.bump();

        const peek = self.peek_token();
        if (peek) |p| {
            const char = p.to_char();
            switch (char) {
                'w' => return self.next_sequence('w'),
                'W' => return self.next_sequence('W'),
                '0' => return self.next_sequence('0'),
                '\\' => return self.next_char('\\'),
                '(' => return self.next_char('('),
                ')' => return self.next_char(')'),
                '[' => return self.next_char('['),
                ']' => return self.next_char(']'),
                '^' => return self.next_char('^'),
                '*' => return self.next_char('*'),
                '+' => return self.next_char('+'),
                '?' => return self.next_char('?'),
                '|' => return self.next_char('|'),
                else => {
                    @compileError("invalid pattern: \\" ++ std.unicode.utf8EncodeComptime(char));
                },
            }
        } else {
            return error.invalidPattern;
        }
    }

    fn next_group(self: *Self) !Token {
        self.bump();

        var invert = false;
        var items = ArrayList(u21).init();
        for (0..self.tokens.len) |i| {
            const peek = self.peek_token();
            if (peek) |p| {
                self.bump();
                switch (p) {
                    .Char => |c| items.append(c),
                    .Escape => {
                        const char = self.peek_token();
                        self.bump();

                        if (char) |c| {
                            items.append(c.to_char());
                        } else {
                            return error.invalidPattern;
                        }
                    },
                    .Carat => if (i == 0) {
                        invert = true;
                    } else {
                        items.append('^');
                    },
                    .GroupEnd => break,
                    else => return error.invalidPattern,
                }
            } else {
                return error.invalidPattern;
            }
        }

        return .{ .Group = Group{ .invert = invert, .chars = items.get() } };
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
