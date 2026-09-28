# akashic-syntax — Syntax Highlighting by Meaning

Line-by-line scanners that fill a style map: one meaning per byte of a
line, from the list in [text-style](text-style.md), 0 for plain text. The
map says what the text means, never how it looks; each display chooses its
own look. Built-in scanners handle Forth and Markdown.

```forth
REQUIRE text/syntax.f
```

`PROVIDED akashic-syntax` — safe to include multiple times.

---

## Scanners

Every scanner has the shape `( line-a line-u map -- )`, the style source a
text area takes (see [textarea](../tui/widgets/textarea.md)). It first
clears `map[0..line-u)` to plain and then marks what it finds. A line is
scanned on its own, so nothing carries over from one line to the next: a
Forth `(` comment or Markdown emphasis that is not closed on its line ends
there.

| Word | Marks |
|------|-------|
| `SYN-SCAN-FORTH` | keywords, comments, strings, numbers |
| `SYN-SCAN-MD` | headings, inline code, strong, emphasis, links |
| `SYN-SCAN-URLS` | web links in prose |
| `SYN-SCAN-PLAIN` | nothing: every byte plain |

`SYN-LANG-FORTH`, `SYN-LANG-MD`, `SYN-LANG-URLS`, and `SYN-LANG-PLAIN` are
constants holding each scanner's xt, and `SYN-SCAN ( line-a line-u map xt
-- )` runs one.

### Forth

| Meaning | Text |
|---------|------|
| `TSTY-KEYWORD` | defining and control words such as `:` `;` `IF` `THEN` `BEGIN` `DO` `LOOP` `CASE` `CREATE` `CONSTANT` `VARIABLE` `REQUIRE`, in any case |
| `TSTY-COMMENT` | `\` and a blank to the line's end; `(` and a blank through the next `)`, or to the line's end |
| `TSTY-STRING` | a word ending in a quote, such as `S"` `."` `ABORT"`, and its text through the next quote |
| `TSTY-NUMBER` | decimal digits; hex after `$` or `0x`; binary after `%`; each with an optional leading `-` |

A `\` or `(` glued to other characters is an ordinary word.

### Markdown

| Meaning | Text |
|---------|------|
| `TSTY-HEADING` | a whole line starting with one to six `#` and then a blank |
| `TSTY-CODE` | `` `code` ``, backtick to backtick |
| `TSTY-STRONG` | `**text**` or `__text__` |
| `TSTY-EMPHASIS` | `*text*` or `_text_` |
| `TSTY-LINK` | `[text](target)`, the whole of it |

Emphasis text must not start with a blank, and must not end with one
before its closing marker. An underscore between letters or digits is part
of a word, so `snake_case` is plain. Text inside a code span, a strong or
emphasised span, or a link is not scanned again. Markers that open nothing
are plain.

### Web links

`SYN-SCAN-URLS` marks `TSTY-LINK` over each web link in prose such as a
post: `http://` or `https://`, in any case, at the start of the line or
after a character that is not a letter or digit, through the next blank or
control character.  Punctuation that usually ends a sentence or closes a
bracket or quote (`. , ; : ! ? ) ] } ' " >`) is not part of the link's
end, and a scheme with nothing after it is plain.  Streams marks the links
in its posts' text this way.

## Following a Markdown link

`SYN-MD-LINK-AT ( line-a line-u pos -- target-a target-u found? )` finds
the `[text](target)` that covers byte `pos` of the line and returns its
target: the bytes inside the parentheses up to the first blank, so an
optional title such as `"Title"` is left out. The target points into the
line. `found?` is false, with `0 0`, when no link covers `pos`; code spans
are passed over, so a link written inside backticks is not found.

## Choosing a scanner by file name

`SYN-FOR-FILE ( name-a name-u -- xt | 0 )` looks the name's extension up in
[file-types](../utils/file-types.md) and returns `SYN-LANG-FORTH` for Forth
source, `SYN-LANG-MD` for Markdown, and 0 for anything else. Zero means the
text is plain, so an editor can skip styling altogether.

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `SYN-SCAN-FORTH` | `( line-a line-u map -- )` | Scan a line of Forth |
| `SYN-SCAN-MD` | `( line-a line-u map -- )` | Scan a line of Markdown |
| `SYN-SCAN-PLAIN` | `( line-a line-u map -- )` | Clear the map |
| `SYN-SCAN` | `( line-a line-u map xt -- )` | Run a scanner |
| `SYN-LANG-FORTH` / `SYN-LANG-MD` / `SYN-LANG-PLAIN` | `( -- xt )` | Scanner xts |
| `SYN-FOR-FILE` | `( name-a name-u -- xt \| 0 )` | Scanner for a file name, 0 for plain |
| `SYN-MD-LINK-AT` | `( line-a line-u pos -- target-a target-u found? )` | Target of the link at `pos` |

## Dependencies

- `text/text-style.f` — the meanings
- `utils/string.f` — `STR-STRI=`, `STR-INDEX`, `_STR-LC`
- `utils/file-types.f` — `FT-LOOKUP-LANG`

## Consumers

- Pad — styles each open file by its name, and follows Markdown links
