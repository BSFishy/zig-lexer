# zig lexer

> [!CAUTION]
> I don't recommend that you use this project. I have built it for myself, and
> as such there are certainly holes in the implementation that I am aware about
> but will be very difficult to reason about in the spaghetti that I have built.
>
> I have open sourced the code for the culture. If you ARE interested in
> investing some blood, sweat, and tears you are free to fork the project and
> patch the wholes that I have left. This is and will remain a project that I
> have built for myself, and as such I won't be paying attention to issues and
> PRs in this repo.

This is the home of my lexer. It uses Zig's comptime to generate jump tables at
compile time for super easy maintenance and pretty decent performance.

I primarily made this project because I want to use lexers but I am bad at
writing them and I don't really care about the implementation. I kinda just care
about the tokens and their patterns. And this is exactly that.

```zig
const lexer = @import("lexer");

const token_patterns = [_]lexer.TokenPattern{
    .{ .name = "Comment", .pattern = "//([^\n])*" },
    .{ .name = "Division", .pattern = "/" },
    .{ .name = "Func", .pattern = "func" },
    .{ .name = "String", .pattern = "\"([^\"]|\\\\\")*\"" },
    .{ .name = "Newline", .pattern = "(\n|\r\n)" },
    .{ .name = "Ident", .pattern = "\\w\\W*" },
};

const l = lexer.Lexer(&token_patterns).init(allocator);
const tokens = try l.lex(input, .{});
for (tokens) |token| {
  _ = token.token_type; // enum of all the variant names
  _ = token.source; // slice into the input
}
```

Features:

- Generates jump tables at compile time
- Supports UTF-8 out of the box
- Allows matching specific token variants into exhaustive enums
- Regular expression-esque patterns for matching
- Linear time complexity lexing

## Implementation details

The first step is parsing the regular expressions. This is a small pattern
language taken after regular expressions, that only has the functionality that I
find useful in making token patterns. You can see every feature that it supports
in the example above.

Once tokens are parsed into a tree that represents the structure of the pattern,
it is passed into the parser. The parser creates a jump table, which is a list
of tables. The tables are a few maps of kvs. These match a specific character to
either a next table or a leaf token. There are separate maps for direct matches,
sequence matches (something like a `\w`), and fallthroughs (if the character
doesn't match anything else and isn't a specific character).

These are the available sequences:

- **`\a`** - any alphabetic character
- **`\A`** - any alphanumeric character
- **`\0`** - any numeric character

This structure must be recursively constructed due to the fact that the regular
expression grammar returns a hierarchical structure. All that code is super
complicated and I quite frankly only have a loose grasp on what is actually
going on. But it works, and that's all I really care about.

Once the jump table has been generate, we convert it into static tables. This is
super important at the comptime -> runtime boundary. After that, once we have
UTF-8 input to lex, we just jump around the jump tables, reading through the
input.

## Visualizing the tables

Because the tables are just data in memory, we also have the ability to export
graphs representing the tables. This is available through the following API:

```zig
const writer = std.io.getStdOut().writer();
try l.to_graph(writer);
```

I found this tremendously useful in building this project. I implemented lexer
for a small example language to test out its features. Here is the graphviz of
the lexer:

```mermaid
flowchart
    0 -->|"/"| 1
    1 -->|"super / leaf"| Division
    0 -->|"f"| 3
    3 -->|"super f leaf"| Ident
    0 -->|"l"| 6
    6 -->|"super l leaf"| Ident
    0 -->|"i"| 8
    8 -->|"super i leaf"| Ident
    0 -->|"e"| 9
    9 -->|"super e leaf"| Ident
    0 -->|"r"| 12
    12 -->|"super r leaf"| Ident
    0 -->|":#quot;"| 17
    0 -->|"\\n leaf"| Newline
    0 -->|"\\r"| 19
    0 -->|"w"| 22
    22 -->|"super w leaf"| Ident
    0 -->|"  leaf"| Space
    0 -->|"( leaf"| LParen
    0 -->|") leaf"| RParen
    0 -->|", leaf"| Comma
    0 -->|"{ leaf"| LBrace
    0 -->|"} leaf"| RBrace
    0 -->|"+ leaf"| Plus
    0 -->|"- leaf"| Minus
    0 -->|"; leaf"| Semicolon
    0 -->|"= leaf"| Equal
    0 -->|"<"| 29
    29 -->|"super < leaf"| LT
    0 -->|">"| 30
    30 -->|"super > leaf"| GT
    0 -->|"\\w"| 20
    20 -->|"super \\w leaf"| Ident
    0 -->|"\\0"| 26
    26 -->|"super \\0 leaf"| Number
    1 -->|"/"| 2
    2 -->|"super / leaf"| Comment
    2 -->|"\\n"| 2
    2 -->|"super \\n leaf"| Comment
    3 -->|"u"| 4
    4 -->|"super u leaf"| Ident
    3 -->|"o"| 21
    21 -->|"super o leaf"| Ident
    3 -->|"\\W"| 31
    31 -->|"super \\W leaf"| Ident
    4 -->|"n"| 5
    5 -->|"super n leaf"| Ident
    4 -->|"\\W"| 37
    37 -->|"super \\W leaf"| Ident
    5 -->|"c"| 40
    40 -->|"super c leaf"| Func
    5 -->|"\\W"| 39
    39 -->|"super \\W leaf"| Ident
    6 -->|"e"| 7
    7 -->|"super e leaf"| Ident
    6 -->|"\\W"| 32
    32 -->|"super \\W leaf"| Ident
    7 -->|"t"| 45
    45 -->|"super t leaf"| Let
    7 -->|"\\W"| 44
    44 -->|"super \\W leaf"| Ident
    8 -->|"f"| 47
    47 -->|"super f leaf"| If
    8 -->|"\\W"| 33
    33 -->|"super \\W leaf"| Ident
    9 -->|"l"| 10
    10 -->|"super l leaf"| Ident
    9 -->|"\\W"| 34
    34 -->|"super \\W leaf"| Ident
    10 -->|"s"| 11
    11 -->|"super s leaf"| Ident
    10 -->|"\\W"| 49
    49 -->|"super \\W leaf"| Ident
    11 -->|"e"| 51
    51 -->|"super e leaf"| Else
    11 -->|"\\W"| 50
    50 -->|"super \\W leaf"| Ident
    12 -->|"e"| 13
    13 -->|"super e leaf"| Ident
    12 -->|"\\W"| 35
    35 -->|"super \\W leaf"| Ident
    13 -->|"t"| 14
    14 -->|"super t leaf"| Ident
    13 -->|"\\W"| 53
    53 -->|"super \\W leaf"| Ident
    14 -->|"u"| 15
    15 -->|"super u leaf"| Ident
    14 -->|"\\W"| 54
    54 -->|"super \\W leaf"| Ident
    15 -->|"r"| 16
    16 -->|"super r leaf"| Ident
    15 -->|"\\W"| 55
    55 -->|"super \\W leaf"| Ident
    16 -->|"n"| 57
    57 -->|"super n leaf"| Return
    16 -->|"\\W"| 56
    56 -->|"super \\W leaf"| Ident
    17 -->|"\\"| 18
    17 -->|":#quot; leaf"| String
    17 -->|":#quot;"| 17
    18 -->|":#quot;"| 17
    18 -->|":#quot;"| 17
    19 -->|"\\n leaf"| Newline
    20 -->|"\\W"| 20
    20 -->|"super \\W leaf"| Ident
    21 -->|"r"| 42
    42 -->|"super r leaf"| For
    21 -->|"\\W"| 38
    38 -->|"super \\W leaf"| Ident
    22 -->|"h"| 23
    23 -->|"super h leaf"| Ident
    22 -->|"\\W"| 36
    36 -->|"super \\W leaf"| Ident
    23 -->|"i"| 24
    24 -->|"super i leaf"| Ident
    23 -->|"\\W"| 59
    59 -->|"super \\W leaf"| Ident
    24 -->|"l"| 25
    25 -->|"super l leaf"| Ident
    24 -->|"\\W"| 60
    60 -->|"super \\W leaf"| Ident
    25 -->|"e"| 62
    62 -->|"super e leaf"| While
    25 -->|"\\W"| 61
    61 -->|"super \\W leaf"| Ident
    26 -->|"."| 27
    26 -->|"\\0"| 26
    26 -->|"super \\0 leaf"| Number
    27 -->|"\\0"| 28
    28 -->|"super \\0 leaf"| Number
    28 -->|"\\0"| 28
    28 -->|"super \\0 leaf"| Number
    29 -->|"= leaf"| LE
    30 -->|"= leaf"| GE
    31 -->|"\\W"| 31
    31 -->|"super \\W leaf"| Ident
    32 -->|"\\W"| 32
    32 -->|"super \\W leaf"| Ident
    33 -->|"\\W"| 33
    33 -->|"super \\W leaf"| Ident
    34 -->|"\\W"| 34
    34 -->|"super \\W leaf"| Ident
    35 -->|"\\W"| 35
    35 -->|"super \\W leaf"| Ident
    36 -->|"\\W"| 36
    36 -->|"super \\W leaf"| Ident
    37 -->|"\\W"| 37
    37 -->|"super \\W leaf"| Ident
    38 -->|"\\W"| 38
    38 -->|"super \\W leaf"| Ident
    39 -->|"\\W"| 39
    39 -->|"super \\W leaf"| Ident
    40 -->|"\\W"| 41
    41 -->|"super \\W leaf"| Ident
    41 -->|"\\W"| 41
    41 -->|"super \\W leaf"| Ident
    42 -->|"\\W"| 43
    43 -->|"super \\W leaf"| Ident
    43 -->|"\\W"| 43
    43 -->|"super \\W leaf"| Ident
    44 -->|"\\W"| 44
    44 -->|"super \\W leaf"| Ident
    45 -->|"\\W"| 46
    46 -->|"super \\W leaf"| Ident
    46 -->|"\\W"| 46
    46 -->|"super \\W leaf"| Ident
    47 -->|"\\W"| 48
    48 -->|"super \\W leaf"| Ident
    48 -->|"\\W"| 48
    48 -->|"super \\W leaf"| Ident
    49 -->|"\\W"| 49
    49 -->|"super \\W leaf"| Ident
    50 -->|"\\W"| 50
    50 -->|"super \\W leaf"| Ident
    51 -->|"\\W"| 52
    52 -->|"super \\W leaf"| Ident
    52 -->|"\\W"| 52
    52 -->|"super \\W leaf"| Ident
    53 -->|"\\W"| 53
    53 -->|"super \\W leaf"| Ident
    54 -->|"\\W"| 54
    54 -->|"super \\W leaf"| Ident
    55 -->|"\\W"| 55
    55 -->|"super \\W leaf"| Ident
    56 -->|"\\W"| 56
    56 -->|"super \\W leaf"| Ident
    57 -->|"\\W"| 58
    58 -->|"super \\W leaf"| Ident
    58 -->|"\\W"| 58
    58 -->|"super \\W leaf"| Ident
    59 -->|"\\W"| 59
    59 -->|"super \\W leaf"| Ident
    60 -->|"\\W"| 60
    60 -->|"super \\W leaf"| Ident
    61 -->|"\\W"| 61
    61 -->|"super \\W leaf"| Ident
    62 -->|"\\W"| 63
    63 -->|"super \\W leaf"| Ident
    63 -->|"\\W"| 63
    63 -->|"super \\W leaf"| Ident
```

## License

This project is licensed under either:

- MIT License ([LICENSE-MIT](./LICENSE-MIT))
- Apache License 2.0 ([LICENSE-APACHE](./LICENSE-APACHE))

You may choose either license.
