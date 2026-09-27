# akashic-text-style — What the Parts of a Text Mean

A style says what a stretch of text means, never how it looks, so that
each display can choose its own look: a colour screen might use colour and
an e-paper panel weight and underline. The ten meanings are the shared list
of the rich terminal's semantic text (MegaPad's `SEMANTIC-CONTENT-1`, style
runs), with the same values, so a producer passes them through unchanged.

```forth
REQUIRE text/text-style.f
```

`PROVIDED akashic-text-style` — safe to include multiple times.

---

## Meanings

| Constant | Value | Marks |
|----------|------:|-------|
| `TSTY-PLAIN` | 0 | plain text |
| `TSTY-KEYWORD` | 1 | a keyword of a programming language |
| `TSTY-COMMENT` | 2 | a comment |
| `TSTY-STRING` | 3 | a string or character literal |
| `TSTY-NUMBER` | 4 | a numeric literal |
| `TSTY-HEADING` | 5 | a heading |
| `TSTY-EMPHASIS` | 6 | emphasised text |
| `TSTY-STRONG` | 7 | strongly emphasised text |
| `TSTY-CODE` | 8 | code set within prose |
| `TSTY-LINK` | 9 | a link the reader can follow |
| `TSTY-ERROR` | 10 | text the application reports as wrong |

`TSTY-COUNT` is 11, the number of meanings including plain, and
`TSTY-VALID? ( meaning -- flag )` is true for the ten that are not plain.

## Style maps and runs

A style map holds one meaning per byte of a line. A highlighter such as
[syntax](syntax.md) fills one. A character takes the meaning of its first
scalar, and each scalar the meaning at its first byte; a continuation
byte's entry is never read.

`TSTY-RUNS ( text-a text-u map xt -- ok? )` turns a map into runs of
Unicode scalars, the form semantic text carries. It calls
`xt ( start length meaning -- ok? )` once for each run of scalars that
share a meaning other than plain, in order, with `start` and `length`
counted in scalars. Neighbouring scalars with the same meaning form one
run, so two runs with the same meaning never touch, as the contract
requires. A meaning outside the list counts as plain. `TSTY-RUNS` stops and
returns false as soon as `xt` does, and returns true otherwise.

## Consumers

- `text/syntax.f` — fills style maps
- `tui/widgets/textarea.f` — draws styled lines in CELL and publishes their runs
