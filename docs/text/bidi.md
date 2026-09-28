# akashic-bidi — The Unicode Bidirectional Algorithm

Resolves embedding levels for one paragraph and puts a line into visual
order, following UAX #9 for Unicode 15.1.0 as the shared text contract
([`docs/rich-terminal/APT-1-TEXT.md`](../rich-terminal/APT-1-TEXT.md)
Section 7) requires.

```forth
REQUIRE text/bidi.f
```

`PROVIDED akashic-bidi` — safe to include multiple times.

---

## What it implements

Rules P2 and P3 (first strong character, skipping isolates), X1 to X8 with
isolates, overflow counters, and the maximum explicit depth of 125, X9
removal, X10 isolating run sequences, W1 to W7, N0 paired brackets (BD16,
comparing brackets through their canonical equivalents), N1 and N2, I1 and
I2, L1, and L2.  L3 does not apply: callers reorder whole characters, whose
scalars stay in logical order.  Mirroring (L4) belongs to the caller, which
knows each character's first scalar.

## API

| Word | Stack | Meaning |
|------|-------|---------|
| `BIDI-AUTO` `BIDI-LTR` `BIDI-RTL` | `( -- n )` | Paragraph direction: first strong, 0, or 1 |
| `BIDI-REMOVED` | `( -- 255 )` | Level recorded for a character X9 removes |
| `BIDI-WORK-BYTES` | `( n -- bytes )` | Workspace for `n` characters |
| `BIDI-RESOLVE` | `( classes scalars n direction work -- paragraph )` | Resolve levels |
| `BIDI-LEVELS` | `( work -- addr )` | The `n` resolved level bytes |
| `BIDI-REORDER` | `( levels n order -- m )` | Rule L2 over a level byte array |
| `BIDI-TRAILING?` | `( class -- flag )` | Does rule L1 reset this class at a line's end? |

`classes` is a byte array of `UP-BC-*` values.  `scalars` is a 32-bit array
of the same characters, consulted only for paired brackets; pass 0 when the
text has none.  `work` is cell-aligned caller storage of `BIDI-WORK-BYTES n`
bytes: three bytes and three 32-bit words per character, plus the two
stacks the algorithm itself bounds (127 directional status entries and 63
open brackets).  There is no other limit on paragraph length.

`BIDI-REORDER` writes into `order` the 32-bit indexes of every level that is
not `BIDI-REMOVED`, left to right, and returns how many it wrote.  It
reverses from the highest level down to the lowest odd level; with no odd
level there is nothing to reverse.

`BIDI-RESOLVE` applies rule L1 with the paragraph's end as its only line
end.  A caller that breaks the paragraph into lines applies L1 at each
line's end as well: the run of characters at the end whose class
`BIDI-TRAILING?` accepts (whitespace, isolate controls, and the characters
X9 removes) takes the paragraph level.  Every other L1 reset is the same on
every line, so the paragraph's levels already hold it.  `TROW-LINE`
([text-row](text-row.md)) does this.

## Concurrency

The algorithm keeps its scratch state in module variables, so
`BIDI-RESOLVE` and `BIDI-REORDER` take the module guard in `GUARDED`
builds.  `BIDI-TRAILING?` is pure.  They call only the pure `UP-` lookups, so they cannot deadlock
with another guard.

## Tests

`local_testing/test_bidi_conformance.py` evaluates the unmodified
production sources on the native hosted MegaForth runtime and checks every
case in Unicode's `BidiTest.txt` (770,241 cases) and
`BidiCharacterTest.txt` (91,707 cases): paragraph level, every resolved
level, and the visual order.  The full run takes under a minute;
`BIDI_CONFORMANCE_SAMPLE=N` runs every Nth BidiTest case while editing.
MegaPad's `rich_terminal/text_rules.py` is the terminal's independent
implementation and passes the same files.
