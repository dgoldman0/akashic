# akashic-xml — XML Vocabulary for KDOS / Megapad-64

An XML reader and builder library for KDOS Forth.  Builds on
`akashic-markup-core` for tag scanning, attribute parsing, and entity
decoding.  Case-sensitive tag matching throughout.  Strict
well-formedness assumed.

```forth
REQUIRE xml.f
```

`PROVIDED akashic-xml` — safe to include multiple times.
Automatically loads `akashic-markup-core`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Reader](#reader)
  - [Entering & Text](#entering--text)
  - [Child Navigation](#child-navigation)
  - [Attributes](#attributes)
  - [CDATA & Processing Instructions](#cdata--processing-instructions)
  - [Path Navigation](#path-navigation)
  - [Iteration](#iteration)
- [Builder](#builder)
  - [Buffer Output](#buffer-output)
  - [Structural Words](#structural-words)
  - [Content Words](#content-words)
  - [Special Constructs](#special-constructs)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Case-sensitive** | Tag names and attribute names are matched exactly — `<Item>` and `<item>` are different elements. |
| **Well-formed assumed** | Every opening tag is expected to have a matching closing tag (or be self-closing). No error recovery for malformed XML. |
| **Zero-copy reader** | All reader words return pointers into the original buffer. |
| **Buffer builder** | Builder output goes to a user-provided buffer via `XML-SET-OUTPUT`. |
| **Core reuse** | Error handling, entity decoding, attribute parsing, and depth-aware skip all come from `akashic-markup-core`. |

---

## Reader

### Entering & Text

| Word | Stack | Description |
|---|---|---|
| `XML-ENTER` | `( addr len -- addr' len' )` | Enter an element: skip past the opening tag. Cursor must be at `<tag>`. After: cursor at content inside the element. |
| `XML-TEXT` | `( addr len -- txt-a txt-u )` | Extract text content. Cursor at opening tag. Returns text before any child element or close tag. |
| `XML-INNER` | `( addr len -- inner-a inner-u )` | Extract everything between open and close tags. Cursor at opening tag. |

### Example

```forth
\ Given: <msg>Hello World</msg>
my-xml XML-TEXT TYPE        \ prints "Hello World"

\ Given: <msg>Hello <b>World</b></msg>
my-xml XML-INNER TYPE       \ prints "Hello <b>World</b>"
```

### Child Navigation

| Word | Stack | Description |
|---|---|---|
| `XML-CHILD` | `( addr len name-a name-u -- addr' len' )` | Find child element by tag name. Cursor at parent's opening tag. Aborts (or sets error) if not found. |
| `XML-CHILD?` | `( addr len name-a name-u -- addr' len' flag )` | Like `XML-CHILD` but returns flag instead of aborting. |

### Example

```forth
\ Navigate: <root><user><name>Alice</name></user></root>
my-xml S" user" XML-CHILD
       S" name" XML-CHILD
       XML-TEXT TYPE              \ prints "Alice"
```

```forth
\ Safe check:
my-xml S" optional" XML-CHILD?
IF XML-TEXT TYPE ELSE ." not found" THEN
```

### Attributes

| Word | Stack | Description |
|---|---|---|
| `XML-ATTR` | `( tag-a tag-u attr-a attr-u -- val-a val-u )` | Get attribute value. Cursor at opening `<`. Aborts if not found. |
| `XML-ATTR?` | `( tag-a tag-u attr-a attr-u -- val-a val-u flag )` | Like `XML-ATTR` but returns flag. |

### Example

```forth
\ Given: <item id="42" type="book">
my-item S" id" XML-ATTR TYPE          \ prints "42"
my-item S" type" XML-ATTR TYPE        \ prints "book"

\ Safe check:
my-item S" optional" XML-ATTR?
IF TYPE ELSE ." no attr" THEN
```

### CDATA & Processing Instructions

| Word | Stack | Description |
|---|---|---|
| `XML-SKIP-PI` | `( addr len -- addr' len' )` | Skip a processing instruction `<?...?>`. |
| `XML-SKIP-CDATA` | `( addr len -- addr' len' )` | Skip a CDATA section `<![CDATA[...]]>`. |
| `XML-GET-CDATA` | `( addr len -- txt-a txt-u )` | Extract the content of a CDATA section (without `<![CDATA[` and `]]>` delimiters). |

### Example

```forth
\ Given cursor at: <![CDATA[Hello <World>]]>
my-cdata XML-GET-CDATA TYPE    \ prints "Hello <World>"
```

### Path Navigation

| Word | Stack | Description |
|---|---|---|
| `XML-PATH` | `( addr len path-a path-u -- addr' len' )` | Navigate a slash-separated path like `"a/b/c"`. Intermediate segments are entered; the last segment leaves the cursor AT the element. |

### Example

```forth
\ Navigate: <root><data><items><item>Hello</item></items></data></root>
my-xml S" data/items/item" XML-PATH
XML-TEXT TYPE                    \ prints "Hello"
```

### Iteration

| Word | Stack | Description |
|---|---|---|
| `XML-EACH-CHILD` | `( addr len -- addr' len' name-a name-u flag )` | Iterate child elements. Call with cursor INSIDE an element (past the opening tag). Returns cursor at child, child's tag name, flag. Flag = `-1` if child found, `0` if no more. Automatically skips comments and PIs. |

To iterate, use the returned cursor for the next call after skipping
the current child with `MU-SKIP-ELEMENT`.

### Example

```forth
\ Print all child tag names:
my-xml XML-ENTER
BEGIN
    XML-EACH-CHILD
WHILE
    TYPE CR                      \ print child tag name
    2DROP                        \ drop name addr/len
    MU-SKIP-ELEMENT              \ skip past child
REPEAT
2DROP                            \ drop cursor
```

---

## Builder

Construct XML text programmatically with buffer output.

### Buffer Output

| Word | Stack | Description |
|---|---|---|
| `XML-SET-OUTPUT` | `( addr max -- )` | Direct all builder output into buffer `addr` of capacity `max`. Resets write position to 0. |
| `XML-OUTPUT-RESULT` | `( -- addr len )` | Return the buffer address and number of bytes written so far. |
| `XML-OUTPUT-RESET` | `( -- )` | Reset write position to 0 (re-use the same buffer). |

### Structural Words

| Word | Stack | Description |
|---|---|---|
| `XML-<` | `( name-a name-u -- )` | Start an opening tag: outputs `<name`. Tag remains open for attributes. |
| `XML->` | `( -- )` | Close an opening tag: outputs `>`. |
| `XML-/>` | `( -- )` | Self-closing tag end: outputs `/>`. |
| `XML-</` | `( name-a name-u -- )` | Closing tag: outputs `</name>`. |

### Content Words

| Word | Stack | Description |
|---|---|---|
| `XML-ATTR!` | `( name-a name-u val-a val-u -- )` | Add attribute to current tag: outputs ` name="value"`. Must be called between `XML-<` and `XML->`. |
| `XML-TEXT!` | `( txt-a txt-u -- )` | Emit text content with XML escaping (`&` → `&amp;`, `<` → `&lt;`, `>` → `&gt;`). |
| `XML-RAW!` | `( txt-a txt-u -- )` | Emit raw text (no escaping). |

### Special Constructs

| Word | Stack | Description |
|---|---|---|
| `XML-COMMENT!` | `( txt-a txt-u -- )` | Emit `<!-- text -->`. |
| `XML-PI!` | `( target-a tu data-a du -- )` | Emit `<?target data?>`. |

### Example — Build to Buffer

```forth
CREATE out-buf 512 ALLOT
out-buf 512 XML-SET-OUTPUT

S" xml" S" version=\"1.0\"" XML-PI!
S" root" XML-<  XML->
    S" item" XML-<  S" id" S" 1" XML-ATTR!  XML->
        S" Hello & World" XML-TEXT!
    S" item" XML-</
    S" empty" XML-<  XML-/>
S" root" XML-</

XML-OUTPUT-RESULT TYPE
\ prints: <?xml version="1.0"?><root><item id="1">Hello &amp; World</item><empty/></root>
```

### Escaping

`XML-TEXT!` automatically escapes the three XML-sensitive characters:

| Character | Escaped |
|---|---|
| `&` | `&amp;` |
| `<` | `&lt;` |
| `>` | `&gt;` |

Use `XML-RAW!` to emit pre-escaped or known-safe text verbatim.

---

## Quick Reference

### Reader

```
XML-ENTER              ( a u -- a' u' )            enter element
XML-TEXT               ( a u -- ta tu )            text content
XML-INNER              ( a u -- ia iu )            inner content
XML-CHILD              ( a u na nu -- a' u' )       find child (fail)
XML-CHILD?             ( a u na nu -- a' u' f )     find child (flag)
XML-ATTR               ( a u na nu -- va vu )       get attr (fail)
XML-ATTR?              ( a u na nu -- va vu f )     get attr (flag)
XML-SKIP-PI            ( a u -- a' u' )            skip <?...?>
XML-SKIP-CDATA         ( a u -- a' u' )            skip CDATA
XML-GET-CDATA          ( a u -- ta tu )            CDATA content
XML-PATH               ( a u pa pu -- a' u' )       slash path nav
XML-EACH-CHILD         ( a u -- a' u' na nu f )     iterate children
```

### Builder

```
XML-SET-OUTPUT         ( a m -- )          redirect to buffer
XML-OUTPUT-RESULT      ( -- a u )          get buffer contents
XML-OUTPUT-RESET       ( -- )              reset write position
XML-<                  ( na nu -- )        start open tag
XML->                  ( -- )              close open tag
XML-/>                 ( -- )              self-close tag
XML-</                 ( na nu -- )        closing tag
XML-ATTR!              ( na nu va vu -- )  add attribute
XML-TEXT!              ( ta tu -- )        text (escaped)
XML-RAW!               ( ta tu -- )        text (raw)
XML-COMMENT!           ( ta tu -- )        <!-- ... -->
XML-PI!                ( ta tu da du -- )  <?target data?>
```

---

## Cookbook

### Parse an RSS Feed Item

```forth
my-rss S" channel/item" XML-PATH
2DUP S" title" XML-CHILD XML-TEXT TYPE CR
2DUP S" link"  XML-CHILD XML-TEXT TYPE CR
      S" description" XML-CHILD XML-TEXT TYPE CR
```

### Extract Attribute and Content

```forth
\ <book isbn="978-0-123">The Title</book>
my-book 2DUP S" isbn" XML-ATTR TYPE    \ prints "978-0-123"
XML-TEXT TYPE                           \ prints "The Title"
```

### Build a SOAP-like Envelope

```forth
CREATE buf 1024 ALLOT
buf 1024 XML-SET-OUTPUT

S" xml" S" version=\"1.0\"" XML-PI!
S" Envelope" XML-<  XML->
    S" Body" XML-<  XML->
        S" GetPrice" XML-<  XML->
            S" Item" XML-<  XML->
                S" Widget" XML-TEXT!
            S" Item" XML-</
        S" GetPrice" XML-</
    S" Body" XML-</
S" Envelope" XML-</

XML-OUTPUT-RESULT TYPE
```

### Iterate All Children

```forth
\ Print names and text of all children of <root>:
my-xml XML-ENTER
BEGIN
    XML-EACH-CHILD
WHILE
    2DUP TYPE ." : "             \ print tag name
    2DROP                        \ drop name
    2DUP XML-TEXT TYPE CR        \ print text
    MU-SKIP-ELEMENT              \ advance past child
REPEAT
2DROP
```

---

## Internal Words

These are prefixed with `_X` and are not part of the public API.

| Word | Purpose |
|---|---|
| `_XML-EMIT` | Emit one character to builder output buffer. |
| `_XML-TYPE` | Emit a string to builder output buffer. |
| `_XML-ESCAPE-CHAR` | Emit character with XML text escaping. |
| `_XB-BUF`, `_XB-MAX`, `_XB-POS` | Builder buffer state. |
| `_XC-NA`, `_XC-NL` | State for `XML-CHILD`. |
| `_XGC-A` | State for `XML-GET-CDATA`. |
| `_XP-PA`, `_XP-PL`, `_XP-SA`, `_XP-SL` | State for `XML-PATH`. |
| `_XEC-NA`, `_XEC-NL` | State for `XML-EACH-CHILD`. |
