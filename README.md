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

[![Graphviz visualization of the lexer](./.github/graphviz.svg)][graphviz]

## License

This project is licensed under either:

- MIT License ([LICENSE-MIT](./LICENSE-MIT))
- Apache License 2.0 ([LICENSE-APACHE](./LICENSE-APACHE))

You may choose either license.

[graphviz]: https://dreampuf.github.io/GraphvizOnline/?engine=dot&compressed=CYSw5gTghgDgFgUgEwAYEHYBCCUEFlqoDOALlBCQQLQIDMAogQIwEICsmANlAEYCmnOgBFkSZADFR7EbWx5WqFqhoMFSTnwAefCADoAxgHsAtjBAaA%2BiUMBrPgDsrATxh9dZMLqEgAbiCIghvZSqOxcvALCokQArq4QCpKoGlAAZiEoRpyGCbRCPJwxfNJ0cvihxGQU1HSMqLSsHNz8gnmi6UhibDJlCigNyrVqGtp6RqbmfFa2Ds6u7lCeAJLADpSdjeEtUZ2x8QQdKCkdYqhZOcIFRSWyOOWEKKTk6ygqdSgAbJvNkW2dghtuqU7n0voNVBV1FodAYTGZLNY7I4SC43B5dCs1hkwj9WiJdnEdAQAUc%2BGkMudcvlCsUgbd5BVHlUXm8CAAOb4RPGiEBSOm9Rkc8HvUQjGHjeFTRGzFHzdGY%2BzrU5oJpcnZIPZE1C85Jkk4ESmXGk3AUPJ7VYUEACcnO2fyQxUBPRBjJtlshYrGcMm0yRczRiwxq0V2NVdvxGsJCVQjtJ5I2Z0M2SpV1pzoZZuZNQhKCYypxavt0a66fuzGVrI90K9EwRM2RqIWy2DSttvwjmujKC7xwpSYueVTJpdmee2feTHQbe5gIAwiES8CMwRzSyhlXRrDa1L6-6m7oAHJ8ADunBA9kd%2BbD7b587Ys%2BCuvjysNg%2BN-JHK6z7tzbpVWxvOd2FnYth2XSoxx-BN-1xdVjz5Us%2BmgytCChTcJR9aUGzlQMFVbUJrxnSN9lQeCn31RNkyNa4P3AplINeddUM9LdJV9GVG3RABlGAoH0S9p3VPpe2g19qRoxDGVXcdhmrVjMN3WUA08AAZAAFcgHFDACiIACmJPU%2Byot8JKXMsIItRic1FOSMLrP0lP3AAlDSIC06CC3DUQAEoDOfA1%2BxTd9JNHSyUJs9DvXsjicM8WcTGMKBtNg%2B1kHncijIHcS0zMvppJ-CLxSincHM4wMVMwaB%2BOSwsIwwbAMtEwLqJy%2BlzPosKmMKms2Kwvd0Scyq%2BIEgidKE9B8TjCjMmakzWtNL8GPC-5bOK9jsOU3Q1MKIgaq8hMGqmzKgtMtq8u-KyRRWyLt3W-rAwAWXPGJdo8wj1RoRqX1m7KwPa-LLtkm7esUsrPC4vhjBAc5HyvMbUtuL6AuM37aP%2Bi7lrQorbr6xz0XoABHGIoABOGUrqv4jqalGhzR86lqYpA-08wCxFodLFzOxkmZkjdsZB0rYt0FSABU9tZztWHZvzprE2mQsWzqc1oB4WaI9dOYW%2BoHkxli7JKmLNoAcTFt74Y7KMpfeETvpp4LcqkjHGdV97UvvYCyNtrKcigewwHmz9UEZXXVpx0Ghbw8WiMlgi71nMiqa9qlID4LS6cdhmcyQMEYNq29gNQ5HvegP2A7o7PeeY0OBcN-cDxiYx%2BFA0byeiS3Y4LmXjuEFO04VxRK7JvOEySTXA5QCsuuu-mFMFzb4uMYwsTN1uCRIwgkkTouTrL9rJ6zwS3bj2Ht%2BENzgD%2BpDK%2B6%2BToo2-cF6XkMV%2BH4itRVY%2Bu%2BprKYBiCAYA0JfRkAxAaoAACyHwjDEBCDsHgQIKtPHqs9a7yhbFHdUMcUDQKRpRLK8tYEEBAShJAShc77SQIYGBXMHgkOvog2%2BBt76oOXkPchmDKE4JmnbU6Wt%2BiV1oKQtWQl3b3gAOrdzyD7UuQCHgCLoVjJBd97rNhYZAtu69gLAXEZwsSvdgjpzgZXNgajOgnwMQQYxCCFEMLunjXCaCX5sPbigR8W9cE7xkQQeBoD%2BhThbq-TRYiJFCCkf7Tx9Q-E%2BJvvrWxYMgyqP8U4jRIjZzaLcVwrKejwkoEsT4sBLtzaiH0FQ3h%2BT5F6zWrjOJ4gYj2GKY4iWzj6npLlvbahFj%2BHM1dnVFJ2ik7CFCbvPotA-wh2Bsgph9iElkMackuOaSbanzyFk8xqAc4oUiUI%2B0AlVkoEiWMmeSi7EqOfqw2Z79YyLPcS1bJ6ymK0DOerXpwTBnZIeeU6uEzlHxNOSYt%2BXZAmpK-v05Zbk%2B4ENQPspiYDclbIjK2XZMKPnjKOXElSfB8IzOjs4l4VyMkeN2VCnMYDvFwvzkE7%2BVJXmIu8QcxRjDvmRwadiuZWjgVLKECs-uKAhR5M2d09oJTx5gKJVdaxMSqkR2mmSte79Dh4taTw8evKUK0BATKro8yXklzCbstVyLDkMuOT8zFGrMGAoWYZSlPcwX6O5aMpiTACmr3UEKuiTqDX0tiRHBxjyMHOJJAqn6%2BD2moAdcrUlAqgIUpBSEnVQzgG0qnuKyp4dNpMr9fac1zydE-S5RC3MOtHWCKjRqN17UmCkLpTYyV6bfV-Mwa9Fpwa2m8I9T%2BMBXTCnRqBdayR8bsmds9TWtN%2B4M0NucRa9l1zQWpztQWytRiS3dodOWvobAq3JoqWHOe%2B56CcCICNLF-r16XKtbGkNbbN05jYM6gJObY3Uu5be4dErR3MN%2BYk85AKc3NpRvm0NuZ94TnVaWnZ3KmBEK3Z81FPrplmucWe-yM7UYQeA4Q2Fpap19rjb7XV3LaC5OrW%2B3dH7TWluzVq3N-7bXZMg5XJgkaV0Iog0m6y9CSMoKmZ%2B49WacXTvxTc3Z9GfxsFAyu7Dj6B27LE6%2B1NpHuPkZXZRtl1HMm0eE2xicmGV3YLHu6oj0GUVGrieOr9LL37YL-Xg1t49GNGKYy6yTHKn0FrYFpoGhrvV1vgxRydv6g00bnXRwzOYmA5w1aBYTdz2Mpp3Vxk5SmXWYJ7Oejll67OhfeGwHTTmH0uek8%2BrLnmvW1rHfW8zJ737Yes8nDTEGYvZf5Susxz7RUlZHQpzwTkMV-xPpVvj69XGBZs0q91jWLERaw-llDrnANsAm3zUr77FPoMG9VgLaWUMAbbe1xQvKNWArXYySccn4uTPBiQCA54wBrZ6RzATiqE0PFOz%2BV7vH7sLg5efOjKrHXNbyw9p0C6-thYB-eoHsafvCfDWK7dNcLuHhPGeC8d3yUPkey2sbe8i1ZzveQ5zs3CsFuDkZrzZWyNo9lT%2BqjtWbXBd2bQjtmaIxRe5WA9DS3OsJd0OIC4zKqtdlS8hwTc1slM58bQA702qNSbw89whoO4cwZM3BnjCHWUUrp7O8FgHkKM3Ey6xAwO9dQdi-Dr5xqzMffUe-Y32vUMk85-0KbEmZui9w9IvVi2q7Ge8%2BV3zyn-O05G3Vhn3KkBm-eEgRzr8dT6b3h5rnnHEfW41%2B-HUDuMvlyjxYrtgPVNy698%2B2HHWU%2BMoqzb6njQQ9bY9zt8eMfB65dfqTcXxXk-yZ52nvz69A116e%2BLpPnx8es0Jx7ubvCPi4%2BV37inq2BfrZp6ph3Dfy4d8%2BCz0Q4GC0fGd9ErviPRFwEmFT-5BAkOyyxwroOG%2BPjLoLzGgr8vbnXtn%2BTlbiWz8qa16H%2BnuveEK4oJwdyFdBjsaEfcgCq9NVO4cNJ9G8fcD9ztvl65G4tQt9q8O57wHg-8dd509c9sJ5pc3c45C4icX9Gclcy9D8UCG4m5v9g9YDV96sScqCg5iDH9ZwyCJ9ic9c2DfcP8utDw6D0CJ1NcuDMcgsADG9S9O9kDjUVI6gMC2ZJpcDHdAMVYzsEdvkjYlC-kdgs9bM6I5EfwTDoDx8xJ4DjC39qD5DTNK909l9f8B880WCNDnd3kBtPsn9yDi8C1PCokOMaCrcHDe8Nta8RddE3DeF9VTDDcIdC9n8-CNDc85DtCQjA9ktGDnDIjXDw9-Dh9aBY8Cd3dLDeCYjh8kD0j7DMjX4f9e1mD8iNCN9CN9DSiforD2pWirELdYMfN1cwinCGi1C18uifdaBXdOC%2Bkkj8N-DECgi7C1cks6jsjhiXCpD8CYjCDaAQCx92iUZOjhlCCqjLcaiBig9xDLVciNi3l%2BCpc2jZcZib9%2Bh%2BCTi%2BiA9zisjLjJD1MmiYjZD%2Bh88EifCeCKCCMAS3jVd%2BjliklwiV8RjojhUZ8vEH9gTe0i9ZjAMwEbC0jTiliGDvi1Mw9pC6JsTK4ySvD0dpjfDMTSkcSBDlshCe8Li4Scir8bjEVncwF4iSjHiaTnjuStC8ToSCTWS1jrjfiST2pBSO0eS9i%2BTQTkjSlUiGTudU9QiWShirj2TJTNjhVh8SUHjEj%2BTB1KiFjqj8TF8LZCTGipS%2BgkUO1Ji0TqTFTaThV5i4sLSRSrTbctSfjiS9TSSfcwEnTeTjTXSBSPTeioSPiYTv0a94T1jdTB1CCwEODnTtUwSC00yhT3jKcfTMCP5EyJSAzB1%2BCczKSe0XSyisysTXjzThTYzRS-SiT-9AzpSASh1KyYCQSaylThUISGy8yF9lD6jtTglRj11kTUAX1uyLCOjyjx5ZzAjPTGz8zRzVjxycNJzGQN0jFlD5yDjFy6I2B98hyYz1yxCxStzY0dyHhTz9yjTeyFzazeEHyeiVd-dLzuyxz-S2zslZNRM5SnkFS%2By3STyVTISvyRyryWzbT2z11h93Mnz0SniAKzTVzhyv8Czz8sDxSdTSyZMN8csULqyXz%2ByTyN8oL59sKNybSES-ilyfcFtSLMyKL2oWKPy59P8TVmyEy2SJzESTzCC2B0ywznyjzXylz6zMKLyYKfzNy-y8CAL%2BDRLWK4DjyOKZLozoLaLYL%2BL8LBLGKTyAS2AgTxLUKTSZNBzZLdLeKcLfzWzlLdlp9K5XK5z9ji4pK6J3KVydKaL7K6LrylLOUhL2p783LUSLKyLJL2LQR6TqKeLmSvjgqnLQrjLwrncPhgLhFQLyLwLwrILzy7LkqVj6KkzCLuVsq3Kcqj5wywLnjqquLBDu8NSUq4KGK7SJo7ggA
