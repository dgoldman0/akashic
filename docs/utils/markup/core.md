# akashic-markup-core — Shared Markup Core for KDOS / Megapad-64

Low-level tag scanning, attribute parsing, entity decoding, and
depth-aware element navigation shared by both the XML and HTML5
vocabularies.  Operates on zero-copy `(addr len)` cursor pairs — same
model as `akashic-json`.

```forth
REQUIRE core.f
```

`PROVIDED akashic-markup-core` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Cursor Model](#cursor-model)
- [Error Handling](#error-handling)
- [Layer 0 — Low-level Scanning](#layer-0--low-level-scanning)
- [Layer 1 — Tag Detection & Classification](#layer-1--tag-detection--classification)
- [Layer 2 — Tag Scanning](#layer-2--tag-scanning)
- [Layer 3 — Attribute Parsing](#layer-3--attribute-parsing)
- [Layer 4 — Entity Decoding](#layer-4--entity-decoding)
- [Layer 5 — Element Navigation](#layer-5--element-navigation)
- [Quick Reference](#quick-reference)
- [Internal Words](#internal-words)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Zero-copy** | Reader words return pointers into the original markup buffer — no intermediate copies unless you explicitly unescape. |
| **No hidden allocations** | All buffers (unescape targets) are user-provided. The library allocates only a handful of internal `VARIABLE`s. |
| **Composable cursors** | Every navigation word takes `(addr len)` and returns `(addr' len')`, so words chain naturally. |
| **Depth-aware** | Element navigation tracks nesting depth — `MU-SKIP-ELEMENT` and `MU-FIND-CLOSE` correctly handle nested elements with the same tag name. |
| **Configurable errors** | Abort-on-error or soft-fail with flag checking — your choice, changeable at runtime. |
| **Shared foundation** | Both `akashic-xml` and `akashic-html` build on these primitives. Tag classification, attribute parsing, and entity decoding are defined once here. |

---

## Cursor Model

A **cursor** is a standard Forth string pair `( addr len )` pointing somewhere
into a markup text buffer. `addr` is the byte address of the current position,
`len` is the number of remaining bytes.

```
Markup text in memory:
  addr ──►<root><item id="1">Hello</item></root>
           ↑ cursor starts here

After MU-ENTER (skip past <root>):
  addr' ──►<item id="1">Hello</item></root>
            ↑ inside <root>

After MU-SKIP-ELEMENT:
  addr'' ──►</root>
             ↑ past the <item>...</item>
```

Words that navigate (enter, skip, find) return a new cursor.
Words that extract (`MU-GET-NAME`, `MU-GET-TEXT`, etc.) return both
the advanced cursor and the extracted string.

> **Important:** Cursors are ephemeral. If you modify the underlying
> buffer, all cursors into it are invalidated. The reader is strictly
> read-only.

---

## Error Handling

### Variables

| Word | Stack | Description |
|---|---|---|
| `MU-ERR` | `( -- addr )` | Variable holding the current error code. `0` = no error. |
| `MU-ABORT-ON-ERROR` | `( -- addr )` | Variable. `-1` = abort on error, `0` = set flag only. Default: `0` (soft-fail). |

### Words

| Word | Stack | Description |
|---|---|---|
| `MU-FAIL` | `( err-code -- )` | Store error code. If abort mode is on, calls `ABORT" Markup error"`. |
| `MU-OK?` | `( -- flag )` | `-1` if no error, `0` if error is set. |
| `MU-CLEAR-ERR` | `( -- )` | Reset error code to `0`. |

### Error Codes

| Constant | Value | Meaning |
|---|---|---|
| `MU-E-NOT-FOUND` | 1 | Tag or attribute not found |
| `MU-E-MALFORMED` | 2 | Malformed markup |
| `MU-E-UNTERMINATED` | 3 | Unterminated string or comment |
| `MU-E-UNEXPECTED` | 4 | Unexpected character encountered |
| `MU-E-OVERFLOW` | 5 | User-provided buffer is too small |

### Usage Patterns

**Abort mode** — simplest, crashes on any error:

```forth
-1 MU-ABORT-ON-ERROR !
my-xml MU-ENTER S" item" MU-FIND-TAG DROP
```

**Flag mode** — check after each operation:

```forth
0 MU-ABORT-ON-ERROR !
MU-CLEAR-ERR
my-xml MU-ENTER S" item" MU-FIND-TAG
IF ." found" ELSE ." not found" THEN
```

---

## Layer 0 — Low-level Scanning

Character-level scanning primitives. These words advance a cursor past
individual syntactic elements without extracting values.

| Word | Stack | Description |
|---|---|---|
| `/STRING` | `( addr len n -- addr+n len-n )` | Standard Forth string advancement. Defined here as a fallback if the BIOS omits it. |
| `MU-SKIP-WS` | `( addr len -- addr' len' )` | Skip whitespace (space, tab, LF, CR). |
| `MU-SKIP-UNTIL-CH` | `( addr len char -- addr' len' )` | Advance until `char` is found. Stops AT the character. |
| `MU-SKIP-PAST-CH` | `( addr len char -- addr' len' )` | Advance past the first occurrence of `char`. |
| `MU-SKIP-NAME` | `( addr len -- addr' len' )` | Skip a tag/attribute name (letters, digits, `-`, `_`, `.`, `:`). |
| `MU-GET-NAME` | `( addr len -- addr' len' name-a name-u )` | Extract a name: returns both the advanced cursor and the name string. |
| `MU-SKIP-QUOTED` | `( addr len -- addr' len' )` | Skip a quoted string (`"..."` or `'...'`). Cursor must be at the opening quote. |
| `MU-GET-QUOTED` | `( addr len -- addr' len' val-a val-u )` | Extract the inner bytes of a quoted string (without quotes). |

### String Comparison Helpers

| Word | Stack | Description |
|---|---|---|
| `_MU-STR=` | `( s1 l1 s2 l2 -- flag )` | Case-sensitive string comparison. |
| `_MU-TOLOWER` | `( c -- c' )` | Convert A-Z to a-z; other chars unchanged. |
| `_MU-STRI=` | `( s1 l1 s2 l2 -- flag )` | Case-insensitive string comparison. |

> The string comparison helpers are prefixed `_MU-` (internal) but are
> used freely by both the XML and HTML5 vocabularies.

### Example

```forth
\ Skip whitespace then extract a tag name:
my-markup MU-SKIP-WS
1 /STRING                        \ skip '<'
MU-GET-NAME                      \ ( addr' len' name-a name-u )
TYPE                             \ print the tag name
```

---

## Layer 1 — Tag Detection & Classification

Examine what kind of markup construct starts at the current cursor
position without consuming it.

### Type Constants

| Constant | Value | Meaning |
|---|---|---|
| `MU-T-TEXT` | 0 | Plain text (not a tag) |
| `MU-T-OPEN` | 1 | Opening tag `<tag ...>` |
| `MU-T-CLOSE` | 2 | Closing tag `</tag>` |
| `MU-T-SELF-CLOSE` | 3 | Self-closing tag `<tag .../>` |
| `MU-T-COMMENT` | 4 | Comment `<!-- ... -->` |
| `MU-T-PI` | 5 | Processing instruction `<?target ... ?>` |
| `MU-T-CDATA` | 6 | CDATA section `<![CDATA[ ... ]]>` |
| `MU-T-DOCTYPE` | 7 | `<!DOCTYPE ...>` |

### Words

| Word | Stack | Description |
|---|---|---|
| `MU-AT-TAG?` | `( addr len -- flag )` | True if cursor is at a `<` character. |
| `MU-TAG-TYPE` | `( addr len -- type )` | Classify the tag at the cursor. Returns one of the type constants above. |

### Example

```forth
my-markup MU-TAG-TYPE
CASE
    MU-T-OPEN       OF ." open tag"    ENDOF
    MU-T-CLOSE      OF ." close tag"   ENDOF
    MU-T-SELF-CLOSE OF ." self-close"  ENDOF
    MU-T-COMMENT    OF ." comment"     ENDOF
    MU-T-PI         OF ." PI"         ENDOF
    MU-T-CDATA      OF ." CDATA"      ENDOF
    MU-T-DOCTYPE    OF ." DOCTYPE"    ENDOF
    ." text"
ENDCASE
```

---

## Layer 2 — Tag Scanning

Skip over complete tags and extract their parts.

| Word | Stack | Description |
|---|---|---|
| `MU-SKIP-TAG` | `( addr len -- addr' len' )` | Skip one complete tag `<...>`. Handles quoted attributes so `>` inside quotes doesn't stop early. |
| `MU-SKIP-COMMENT` | `( addr len -- addr' len' )` | Skip `<!-- ... -->`. Scans for `-->` end marker. |
| `MU-SKIP-PI` | `( addr len -- addr' len' )` | Skip `<?...?>`. Scans for `?>` end marker. |
| `MU-SKIP-CDATA` | `( addr len -- addr' len' )` | Skip `<![CDATA[...]]>`. Scans for `]]>` end marker. |
| `MU-SKIP-TO-TAG` | `( addr len -- addr' len' )` | Skip text content, stopping at the next `<` (or end of input). |
| `MU-GET-TEXT` | `( addr len -- addr' len' txt-a txt-u )` | Extract text content before the next `<`. Returns both the advanced cursor and the text string. |
| `MU-GET-TAG-NAME` | `( addr len -- addr' len' name-a name-u )` | Extract the tag name. Works for open, close, and self-close tags. Cursor must be at `<`. |
| `MU-GET-TAG-BODY` | `( addr len -- body-a body-u )` | Extract everything between `<` and `>` (the inner content of the tag). Does NOT advance the cursor. |

### Example

```forth
\ Extract tag name and check it:
my-tag MU-GET-TAG-NAME     \ ( addr' len' name-a name-u )
2SWAP 2DROP                \ discard cursor, keep name
S" div" _MU-STR= IF ." found a div" THEN
```

```forth
\ Get text content inside an element:
my-elem MU-ENTER           \ skip past opening tag
MU-GET-TEXT                 \ ( addr' len' txt-a txt-u )
2SWAP 2DROP TYPE            \ print the text
```

---

## Layer 3 — Attribute Parsing

Parse attributes from the body of a tag. The tag body is obtained with
`MU-GET-TAG-BODY`, then `MU-SKIP-NAME` to skip past the tag name, leaving
the cursor in the attribute area.

### Words

| Word | Stack | Description |
|---|---|---|
| `MU-ATTR-NEXT` | `( a u -- a' u' na nl va vl flag )` | Parse one attribute. Returns: advanced cursor, name `(na nl)`, value `(va vl)`, flag. If bare attribute (no `=value`), value is `0 0`. Flag = `-1` found, `0` no more. |
| `MU-ATTR-FIND` | `( body-a body-u attr-a attr-u -- val-a val-u flag )` | Find attribute by name. Returns value and flag. Body cursor should be past the tag name. |
| `MU-ATTR-HAS?` | `( body-a body-u attr-a attr-u -- flag )` | Does this tag body have the named attribute? |

### Attribute Formats

The parser handles all common attribute formats:

| Format | Name | Value |
|---|---|---|
| `name="value"` | `name` | `value` (inner bytes, no quotes) |
| `name='value'` | `name` | `value` |
| `name=value` | `name` | `value` (bare — scanned to space/`>`/`/`) |
| `name` | `name` | `0 0` (bare attribute, no value) |

### Example

```forth
\ Find a specific attribute:
my-tag MU-GET-TAG-BODY MU-SKIP-NAME
S" id" MU-ATTR-FIND
IF TYPE ELSE ." no id" THEN
```

```forth
\ Iterate all attributes:
my-tag MU-GET-TAG-BODY MU-SKIP-NAME
BEGIN
    MU-ATTR-NEXT         \ ( a' u' na nl va vl flag )
WHILE
    2>R                  \ save value
    TYPE                 \ print name
    ." ="
    2R> TYPE CR          \ print value
REPEAT
2DROP                    \ drop remaining cursor
```

---

## Layer 4 — Entity Decoding

Decode `&...;` entities in markup text.

### Words

| Word | Stack | Description |
|---|---|---|
| `MU-DECODE-ENTITY` | `( addr len -- char addr' len' )` | Decode one entity starting at `&`. Returns the decoded character and the advanced cursor. If unrecognised, returns `&` (char 38) and advances past `&`. |
| `MU-UNESCAPE` | `( src slen dest dmax -- len )` | Decode all entities from `src` into `dest` buffer. Returns number of bytes written. Stops at end of `src` or when `dest` is full. |

### Supported Entities

| Entity | Character | Code |
|---|---|---|
| `&amp;` | `&` | 38 |
| `&lt;` | `<` | 60 |
| `&gt;` | `>` | 62 |
| `&quot;` | `"` | 34 |
| `&apos;` | `'` | 39 |
| `&#DD;` | decimal | — |
| `&#xHH;` | hexadecimal | — |

> The HTML5 vocabulary (`akashic-html`) extends this with 31 additional
> named entities via `HTML-DECODE-ENTITY`.

### Example

```forth
\ Decode a single entity:
S" &amp;rest" MU-DECODE-ENTITY   \ ( 38 addr' len' )
ROT EMIT                        \ prints '&'
TYPE                             \ prints 'rest'
```

```forth
\ Unescape a full string into a buffer:
CREATE buf 256 ALLOT
S" Tom &amp; Jerry" buf 256 MU-UNESCAPE   \ ( len )
buf SWAP TYPE                              \ prints 'Tom & Jerry'
```

---

## Layer 5 — Element Navigation

Depth-aware navigation through element hierarchies.

| Word | Stack | Description |
|---|---|---|
| `MU-ENTER` | `( addr len -- addr' len' )` | Skip past the opening tag. Cursor must be at `<`. After: cursor is at the content inside the element. |
| `MU-SKIP-ELEMENT` | `( addr len -- addr' len' )` | Skip an entire element including content and closing tag. Handles nested elements, self-closing tags, comments, PIs, and CDATA sections. |
| `MU-FIND-CLOSE` | `( addr len name-a name-u -- addr' len' )` | Find the matching `</name>` tag. Depth-aware — tracks nested elements with the same name. Cursor should be inside the element (past the opening tag). Leaves cursor AT the closing tag. |
| `MU-INNER` | `( addr len -- inner-a inner-u )` | Extract everything between the opening and closing tags. Cursor must be at the opening `<tag>`. |
| `MU-NEXT-SIBLING` | `( addr len -- addr' len' flag )` | Skip to the next sibling element. Cursor at an opening tag. Returns flag = `-1` if sibling found, `0` if end reached. |
| `MU-FIND-TAG` | `( addr len name-a name-u -- addr' len' flag )` | Find next opening tag with the given name at the same depth. Skips non-matching elements entirely. Case-sensitive. Flag = `-1` found, `0` not found. |

### Example

```forth
\ Enter root, find a child element:
my-xml MU-ENTER                     \ inside <root>
S" item" MU-FIND-TAG
IF
    MU-INNER TYPE                    \ print inner content
THEN
```

```forth
\ Walk siblings:
my-xml MU-ENTER
S" item" MU-FIND-TAG DROP           \ at first <item>
BEGIN
    2DUP MU-INNER TYPE CR
    MU-NEXT-SIBLING
0= UNTIL
```

> **Note:** `MU-FIND-TAG` and `MU-FIND-CLOSE` use case-sensitive matching
> (`_MU-STR=`). The HTML5 vocabulary provides case-insensitive versions
> via its own `_HTML-FIND-TAG` and `_HTML-FIND-CLOSE`.

---

## Quick Reference

All public words at a glance, grouped by function.

### Error Handling

```
MU-ERR                 ( -- addr )         error code variable
MU-ABORT-ON-ERROR      ( -- addr )         abort mode variable
MU-FAIL                ( err-code -- )     signal error
MU-OK?                 ( -- flag )         check for errors
MU-CLEAR-ERR           ( -- )              reset error state
```

### Layer 0 — Scanning

```
/STRING                ( a u n -- a' u' )          string advancement
MU-SKIP-WS             ( a u -- a' u' )            skip whitespace
MU-SKIP-UNTIL-CH       ( a u ch -- a' u' )         stop AT char
MU-SKIP-PAST-CH        ( a u ch -- a' u' )         stop PAST char
MU-SKIP-NAME           ( a u -- a' u' )            skip name chars
MU-GET-NAME            ( a u -- a' u' na nu )       extract name
MU-SKIP-QUOTED         ( a u -- a' u' )            skip "..." or '...'
MU-GET-QUOTED          ( a u -- a' u' va vu )       extract quoted inner
```

### Layer 1 — Classification

```
MU-AT-TAG?             ( a u -- flag )     at '<'?
MU-TAG-TYPE            ( a u -- type )     classify tag
MU-T-TEXT = 0    MU-T-OPEN = 1    MU-T-CLOSE = 2
MU-T-SELF-CLOSE = 3   MU-T-COMMENT = 4   MU-T-PI = 5
MU-T-CDATA = 6        MU-T-DOCTYPE = 7
```

### Layer 2 — Tag Scanning

```
MU-SKIP-TAG            ( a u -- a' u' )            skip <...>
MU-SKIP-COMMENT        ( a u -- a' u' )            skip <!-- ... -->
MU-SKIP-PI             ( a u -- a' u' )            skip <? ... ?>
MU-SKIP-CDATA          ( a u -- a' u' )            skip CDATA section
MU-SKIP-TO-TAG         ( a u -- a' u' )            skip to next '<'
MU-GET-TEXT            ( a u -- a' u' ta tu )       extract text
MU-GET-TAG-NAME        ( a u -- a' u' na nu )       extract tag name
MU-GET-TAG-BODY        ( a u -- ba bu )            tag inner content
```

### Layer 3 — Attributes

```
MU-ATTR-NEXT           ( a u -- a' u' na nl va vl f )  next attribute
MU-ATTR-FIND           ( a u sa su -- va vu f )        find by name
MU-ATTR-HAS?           ( a u sa su -- f )              attribute exists?
```

### Layer 4 — Entity Decoding

```
MU-DECODE-ENTITY       ( a u -- ch a' u' )   decode one &...;
MU-UNESCAPE            ( s sl d dm -- n )    decode all entities
```

### Layer 5 — Element Navigation

```
MU-ENTER               ( a u -- a' u' )            skip past open tag
MU-SKIP-ELEMENT        ( a u -- a' u' )            skip entire element
MU-FIND-CLOSE          ( a u na nu -- a' u' )       find </name>
MU-INNER               ( a u -- ia iu )            inner content
MU-NEXT-SIBLING        ( a u -- a' u' f )           next sibling
MU-FIND-TAG            ( a u na nu -- a' u' f )     find <name>
```

### Constants

```
MU-T-TEXT       = 0     MU-E-NOT-FOUND    = 1
MU-T-OPEN       = 1     MU-E-MALFORMED    = 2
MU-T-CLOSE      = 2     MU-E-UNTERMINATED = 3
MU-T-SELF-CLOSE = 3     MU-E-UNEXPECTED   = 4
MU-T-COMMENT    = 4     MU-E-OVERFLOW     = 5
MU-T-PI         = 5
MU-T-CDATA      = 6
MU-T-DOCTYPE    = 7
```

---

## Internal Words

These are prefixed with `_MU-` and are not part of the public API.
They may change between versions.

| Word | Purpose |
|---|---|
| `_MU-NAME-CHAR?` | Check if a character is valid in a tag/attribute name. |
| `_MU-STR=` | Case-sensitive string comparison. |
| `_MU-TOLOWER` | Convert A-Z to a-z. |
| `_MU-STRI=` | Case-insensitive string comparison. |
| `_MU-PEEK2` | Peek at first two characters of a cursor. |
| `_MU-DIGIT?` | Check if character is a decimal digit; return value. |
| `_MU-HEXDIG?` | Check if character is a hex digit; return value. |
| `_MTT-A` | Variable used by `MU-TAG-TYPE` for multi-byte peeks. |
| `_MSC-A` | Variable used by `MU-SKIP-COMMENT` for end-marker detection. |
| `_MSP-A` | Variable used by `MU-SKIP-PI`. |
| `_MSD-A` | Variable used by `MU-SKIP-CDATA`. |
| `_MGT-A` | Variable used by `MU-GET-TEXT`. |
| `_MGB-A` | Variable used by `MU-GET-TAG-BODY`. |
| `_MQ-VA`, `_MQ-VL` | State for `MU-GET-QUOTED`. |
| `_MAN-NA`, `_MAN-NL`, `_MAN-VA`, `_MAN-VL` | State for `MU-ATTR-NEXT`. |
| `_MAF-SA`, `_MAF-SL` | Search state for `MU-ATTR-FIND`. |
| `_MDE-A`, `_MDE-B`, `_MDE-ACC` | State for `MU-DECODE-ENTITY`. |
| `_MUE-D`, `_MUE-N`, `_MUE-MAX` | State for `MU-UNESCAPE`. |
| `_MSE-D`, `_MSE-NA`, `_MSE-NL` | State for `MU-SKIP-ELEMENT`. |
| `_MFC-NA`, `_MFC-NL`, `_MFC-D`, `_MFC-TA`, `_MFC-TL` | State for `MU-FIND-CLOSE`. |
| `_MI-A`, `_MI-NA`, `_MI-NL` | State for `MU-INNER`. |
| `_MFT-NA`, `_MFT-NL`, `_MFT-TA`, `_MFT-TL` | State for `MU-FIND-TAG`. |
