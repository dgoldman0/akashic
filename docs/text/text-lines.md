# akashic-text-lines — Text Broken into Lines

Breaks text into lines at most a given number of cells wide, by the one
line rule of the shared text contract
([`docs/rich-terminal/APT-1-TEXT.md`](../rich-terminal/APT-1-TEXT.md)
Section 12), so that CELL, a list's scrolling, and a rich terminal all
find the same lines.

```forth
REQUIRE text/text-lines.f
```

`PROVIDED akashic-text-lines` — safe to include multiple times.

---

## The rule

Line feeds separate the text's paragraphs, and each paragraph breaks on
its own; an empty paragraph is one empty line.  A space is a character
that is exactly U+0020.  A break opportunity is the position after a
space and before a character that is not a space, when the line has such
a character before it.  A line's width does not count the spaces at its
end.  Each line starts where the one before it ended and is as long as
possible: the rest of the paragraph when it fits, else up to its last
break opportunity that fits, else up to the character that would take
its width, spaces included, past the limit, or just its first character
when that one alone is too wide.  The spaces at a line's end take no cell
and are not drawn.

## Reading lines

A cursor is `TLINES-SIZE` bytes of caller storage holding one text row;
`TLINES-INIT` clears it and `TLINES-FREE` releases its buffers.

| Word | Stack | Meaning |
|------|-------|---------|
| `TLINES-START` | `( addr u flags direction limit cursor -- line? )` | Read the text's first line |
| `TLINES-NEXT` | `( cursor -- line? )` | Read the next line |
| `TLINES-FAILED?` | `( cursor -- flag )` | A paragraph could not be laid out |
| `TLINES-COUNT` | `( addr u flags direction limit cursor -- lines ok? )` | How many lines the text takes |
| `TLINES-ROW` | `( cursor -- row\|0 )` | The row showing the line, or 0 for bytes shown as they are |
| `TLINES-BYTES` | `( cursor -- addr u )` | The line's bytes, less the spaces at its end |
| `TLINES-PARAGRAPH` | `( cursor -- addr )` | The first byte of the line's paragraph |
| `TLINES-WIDTH` | `( cursor -- cells )` | The line's width |
| `TLINES-RTL?` | `( cursor -- flag )` | The line starts at the right edge |

`flags` and `direction` are as for `TROW-LAYOUT`
([text-row](text-row.md)); a limit below 1 counts as 1.  `TLINES-START`
and `TLINES-NEXT` are false past the last line, and when a paragraph
cannot be laid out because its row buffer cannot grow.  The text must
stay unchanged while a cursor reads it.

A paragraph not forced right to left whose every scalar is simple breaks
on its scalars.  A simple scalar is a character on its own (grapheme break
Other, with no emoji or conjunct role), one cell wide, not
default-ignorable, and neither right to left nor an Arabic number, so it
stays at level 0 as printable ASCII does: the cheap path of the shared
contract's Section 11.  A line's end is found from the scalar its limit
reaches, without walking the line, and the line is drawn as its bytes
(`TLINES-ROW` is 0).  Printable ASCII needs no decoding.  Other simple
text is decoded once, into a map of where each scalar starts, which the
cursor keeps and grows to its longest such paragraph.  Any other paragraph
is laid out once by `TROW-LAYOUT`, so its levels and joining come from the
whole paragraph, and each of its lines is shown by `TROW-LINE`; `DRW-TROW`
draws it, its byte offsets counted from `TLINES-PARAGRAPH`.  A line of a
right-to-left paragraph starts at the right edge of its field.

## Cost

`local_testing/test_text_lines.py` ratchets `TLINES-COUNT` in guest steps
per scalar: about 300 for printable ASCII, 1,400 for other simple text,
and 22,000 for Hebrew, which needs the paragraph's layout.

## Tests

`local_testing/test_text_lines.py` compares every line, and every visible
character on it, with MegaPad's independent `layout_lines`
(`rich_terminal/text_rules.py`): fixed cases (runs of spaces, long words,
wide characters, emoji sequences, Hebrew and Arabic with joining, spaces
that are not U+0020 at a line's end, explicit and untrusted direction
controls, forced directions, and several paragraphs), and random mixed
and ASCII texts at random limits.

## Concurrency

Reading keeps its scratch state in module variables, so the reading
words take the module guard in `GUARDED` builds.
