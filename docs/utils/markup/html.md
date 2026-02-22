# akashic-html — HTML5 Vocabulary for KDOS / Megapad-64

An HTML5 reader and builder library for KDOS Forth.  Builds on
`akashic-markup-core` for tag scanning, attribute parsing, and entity
decoding.  Case-insensitive tag matching.  Void-element aware.
Raw-text elements (`<script>`, `<style>`) handled specially.

```forth
REQUIRE html.f
```

`PROVIDED akashic-html` — safe to include multiple times.
Automatically loads `akashic-markup-core`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [HTML5 Specifics](#html5-specifics)
  - [Void Elements](#void-elements)
  - [Raw Text Elements](#raw-text-elements)
- [Reader](#reader)
  - [Entering & Text](#entering--text)
  - [Child Navigation](#child-navigation)
  - [Attributes](#attributes)
  - [Convenience Accessors](#convenience-accessors)
  - [Iteration](#iteration)
- [Entity Decoding](#entity-decoding)
- [Builder](#builder)
  - [Buffer Output](#buffer-output)
  - [Structural Words](#structural-words)
  - [Content Words](#content-words)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Case-insensitive** | Tag matching is case-insensitive — `<DIV>`, `<Div>`, and `<div>` are the same element. |
| **Void-element aware** | The 14 HTML5 void elements (`<br>`, `<img>`, `<input>`, etc.) never have closing tags. Navigation and skip logic handle them correctly. |
| **Raw text elements** | `<script>` and `<style>` content is treated as raw text — tags inside them are not parsed. |
| **Zero-copy reader** | All reader words return pointers into the original buffer. |
| **Extended entities** | `HTML-DECODE-ENTITY` recognises 31 additional named entities beyond the 5 XML built-ins. |
| **Core reuse** | Error handling, basic scanning, attribute parsing, and the XML 5 entities all come from `akashic-markup-core`. |

---

## HTML5 Specifics

### Void Elements

HTML5 void elements never have a closing tag. Both `<br>` and `<br/>`
are valid, but `<br></br>` is NOT valid HTML5. The library recognises
these 14 void elements (case-insensitive):

| | | | | |
|---|---|---|---|---|
| `area` | `base` | `br` | `col` | `embed` |
| `hr` | `img` | `input` | `link` | `meta` |
| `param` | `source` | `track` | `wbr` | |

| Word | Stack | Description |
|---|---|---|
| `HTML-VOID?` | `( name-a name-u -- flag )` | Is this tag name a void element? Case-insensitive lookup in a 14-entry table. |

### Raw Text Elements

The content of `<script>` and `<style>` elements is treated as raw text.
The parser scans for the matching `</script>` or `</style>` close tag
instead of parsing their content as markup. This prevents false tag
matches inside JavaScript or CSS code.

---

## Reader

### Entering & Text

| Word | Stack | Description |
|---|---|---|
| `HTML-ENTER` | `( addr len -- addr' len' )` | Enter an element: skip past the opening tag. |
| `HTML-TEXT` | `( addr len -- txt-a txt-u )` | Extract text content. Cursor at opening tag. Returns text before any child or close tag. |
| `HTML-INNER` | `( addr len -- inner-a inner-u )` | Extract everything between open and close tags. Uses case-insensitive close matching. For raw text elements, scans for `</name>` in raw content. |

### Example

```forth
\ Given: <p>Hello World</p>
my-html HTML-TEXT TYPE        \ prints "Hello World"

\ Given: <div>Hello <b>World</b></div>
my-html HTML-INNER TYPE       \ prints "Hello <b>World</b>"
```

### Child Navigation

| Word | Stack | Description |
|---|---|---|
| `HTML-CHILD` | `( addr len name-a name-u -- addr' len' )` | Find child element by tag name (case-insensitive). Cursor at parent's opening tag. Aborts if not found. Skips void elements and raw text elements correctly. |
| `HTML-CHILD?` | `( addr len name-a name-u -- addr' len' flag )` | Like `HTML-CHILD` but returns flag instead of aborting. |

### Example

```forth
\ Navigate: <html><body><p>Hello</p></body></html>
my-html S" body" HTML-CHILD
        S" p"    HTML-CHILD
        HTML-TEXT TYPE              \ prints "Hello"

\ Works case-insensitively:
my-html S" BODY" HTML-CHILD         \ same result
```

### Attributes

| Word | Stack | Description |
|---|---|---|
| `HTML-ATTR` | `( tag-a tag-u attr-a attr-u -- val-a val-u )` | Get attribute value. Cursor at opening `<`. Aborts if not found. |
| `HTML-ATTR?` | `( tag-a tag-u attr-a attr-u -- val-a val-u flag )` | Like `HTML-ATTR` but returns flag. |

### Example

```forth
\ Given: <img src="photo.jpg" alt="A photo">
my-img S" src" HTML-ATTR TYPE      \ prints "photo.jpg"
my-img S" alt" HTML-ATTR TYPE      \ prints "A photo"
```

### Convenience Accessors

| Word | Stack | Description |
|---|---|---|
| `HTML-ID` | `( addr len -- val-a val-u )` | Shortcut: get the `id` attribute value. Equivalent to passing `S" id"` to `HTML-ATTR`. |
| `HTML-CLASS-HAS?` | `( tag-a tag-u class-a class-u -- flag )` | Does the element have this CSS class? Checks the `class=""` attribute for a space-delimited word match. |

### Example

```forth
\ Given: <div id="main" class="container wide dark">
my-div HTML-ID TYPE                        \ prints "main"
my-div S" wide" HTML-CLASS-HAS? .          \ prints -1 (true)
my-div S" narrow" HTML-CLASS-HAS? .        \ prints 0 (false)
```

### Iteration

| Word | Stack | Description |
|---|---|---|
| `HTML-EACH-CHILD` | `( addr len -- addr' len' name-a name-u flag )` | Iterate child elements. Call with cursor INSIDE element (past opening tag). Returns cursor at child, tag name, flag. Automatically skips comments. To advance: call `_HTML-SKIP-ELEMENT` then `HTML-EACH-CHILD` again. |

### Example

```forth
\ Print all child tag names:
my-div HTML-ENTER
BEGIN
    HTML-EACH-CHILD
WHILE
    TYPE CR                      \ print child tag name
    2DROP                        \ drop name
    _HTML-SKIP-ELEMENT           \ skip past child (void-aware)
REPEAT
2DROP
```

> **Note:** Use `_HTML-SKIP-ELEMENT` (not `MU-SKIP-ELEMENT`) when
> iterating HTML children — it handles void elements and raw text
> elements correctly.

---

## Entity Decoding

`HTML-DECODE-ENTITY` extends the core's 5 XML entities with 31
additional HTML5 named entities.

| Word | Stack | Description |
|---|---|---|
| `HTML-DECODE-ENTITY` | `( addr len -- char addr' len' )` | Decode one `&...;` entity. Tries core decoder first (for `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`, `&#DD;`, `&#xHH;`). Falls back to extended HTML5 entities. Returns `&` (38) for unknown entities. |

### Extended Named Entities

| Entity | Char | Code | | Entity | Char | Code |
|---|---|---|---|---|---|---|
| `&nbsp;` | (nb-space) | 160 | | `&bull;` | • | 8226 |
| `&copy;` | © | 169 | | `&hellip;` | … | 8230 |
| `&reg;` | ® | 174 | | `&euro;` | € | 8364 |
| `&trade;` | ™ | 8482 | | `&rarr;` | → | 8594 |
| `&mdash;` | — | 8212 | | `&larr;` | ← | 8592 |
| `&ndash;` | – | 8211 | | `&times;` | × | 215 |
| `&lsquo;` | ' | 8216 | | `&divide;` | ÷ | 247 |
| `&rsquo;` | ' | 8217 | | `&para;` | ¶ | 182 |
| `&ldquo;` | " | 8220 | | `&sect;` | § | 167 |
| `&rdquo;` | " | 8221 | | `&deg;` | ° | 176 |
| `&plusmn;` | ± | 177 | | `&iquest;` | ¿ | 191 |
| `&micro;` | µ | 181 | | `&iexcl;` | ¡ | 161 |
| `&middot;` | · | 183 | | `&cent;` | ¢ | 162 |
| `&pound;` | £ | 163 | | `&yen;` | ¥ | 165 |
| `&curren;` | ¤ | 164 | | `&laquo;` | « | 171 |
| `&raquo;` | » | 187 | | | | |

### Example

```forth
S" &copy; 2025" HTML-DECODE-ENTITY
ROT .                            \ prints 169
\ cursor now at " 2025"
```

---

## Builder

Construct HTML5 text programmatically with buffer output.

### Buffer Output

| Word | Stack | Description |
|---|---|---|
| `HTML-SET-OUTPUT` | `( addr max -- )` | Direct all builder output into buffer `addr` of capacity `max`. Resets write position to 0. |
| `HTML-OUTPUT-RESULT` | `( -- addr len )` | Return the buffer address and number of bytes written so far. |
| `HTML-OUTPUT-RESET` | `( -- )` | Reset write position to 0 (re-use the same buffer). |

### Structural Words

| Word | Stack | Description |
|---|---|---|
| `HTML-DOCTYPE` | `( -- )` | Emit `<!DOCTYPE html>`. |
| `HTML-<` | `( name-a name-u -- )` | Start an opening tag: outputs `<name`. Tag remains open for attributes. |
| `HTML->` | `( -- )` | Close an opening tag: outputs `>`. |
| `HTML-/>` | `( -- )` | Close a void element. In HTML5, emits just `>` (not `/>`) for spec compliance. |
| `HTML-</` | `( name-a name-u -- )` | Closing tag: outputs `</name>`. |

### Content Words

| Word | Stack | Description |
|---|---|---|
| `HTML-ATTR!` | `( name-a name-u val-a val-u -- )` | Add attribute with value: outputs ` name="value"`. Must be called between `HTML-<` and `HTML->`. |
| `HTML-BARE-ATTR!` | `( name-a name-u -- )` | Add bare (valueless) attribute: outputs ` name`. For HTML5 boolean attributes like `disabled`, `checked`, `readonly`. |
| `HTML-TEXT!` | `( txt-a txt-u -- )` | Emit text with HTML escaping (`&` → `&amp;`, `<` → `&lt;`, `>` → `&gt;`). |
| `HTML-RAW!` | `( txt-a txt-u -- )` | Emit raw text (no escaping). Useful for inline scripts or styles. |
| `HTML-COMMENT!` | `( txt-a txt-u -- )` | Emit `<!-- text -->`. |

### Example — Build a Complete Page

```forth
CREATE out-buf 2048 ALLOT
out-buf 2048 HTML-SET-OUTPUT

HTML-DOCTYPE
S" html" HTML-<  S" lang" S" en" HTML-ATTR!  HTML->
  S" head" HTML-<  HTML->
    S" meta" HTML-<  S" charset" S" utf-8" HTML-ATTR!  HTML-/>
    S" title" HTML-<  HTML->
      S" My Page" HTML-TEXT!
    S" title" HTML-</
  S" head" HTML-</
  S" body" HTML-<  HTML->
    S" h1" HTML-<  HTML->
      S" Hello & World" HTML-TEXT!
    S" h1" HTML-</
    S" br" HTML-<  HTML-/>
    S" input" HTML-<
      S" type" S" text" HTML-ATTR!
      S" disabled" HTML-BARE-ATTR!
    HTML-/>
  S" body" HTML-</
S" html" HTML-</

HTML-OUTPUT-RESULT TYPE
```

Output:

```html
<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>My Page</title></head><body><h1>Hello &amp; World</h1><br><input type="text" disabled></body></html>
```

---

## Quick Reference

### Reader

```
HTML-ENTER             ( a u -- a' u' )            enter element
HTML-TEXT              ( a u -- ta tu )            text content
HTML-INNER             ( a u -- ia iu )            inner content
HTML-CHILD             ( a u na nu -- a' u' )       find child (fail)
HTML-CHILD?            ( a u na nu -- a' u' f )     find child (flag)
HTML-ATTR              ( a u na nu -- va vu )       get attr (fail)
HTML-ATTR?             ( a u na nu -- va vu f )     get attr (flag)
HTML-ID                ( a u -- va vu )            get id attribute
HTML-CLASS-HAS?        ( a u ca cu -- f )           has CSS class?
HTML-EACH-CHILD        ( a u -- a' u' na nu f )     iterate children
HTML-VOID?             ( na nu -- f )              is void element?
```

### Entity Decoding

```
HTML-DECODE-ENTITY     ( a u -- ch a' u' )   decode one &...;
```

### Builder

```
HTML-SET-OUTPUT        ( a m -- )          redirect to buffer
HTML-OUTPUT-RESULT     ( -- a u )          get buffer contents
HTML-OUTPUT-RESET      ( -- )              reset write position
HTML-DOCTYPE           ( -- )              emit <!DOCTYPE html>
HTML-<                 ( na nu -- )        start open tag
HTML->                 ( -- )              close open tag
HTML-/>                ( -- )              close void element
HTML-</                ( na nu -- )        closing tag
HTML-ATTR!             ( na nu va vu -- )  add attribute
HTML-BARE-ATTR!        ( na nu -- )        bare attribute
HTML-TEXT!             ( ta tu -- )        text (escaped)
HTML-RAW!              ( ta tu -- )        text (raw)
HTML-COMMENT!          ( ta tu -- )        <!-- ... -->
```

---

## Cookbook

### Scraping a Web Page

```forth
\ Find the page title:
my-html S" html" HTML-CHILD
        S" head" HTML-CHILD
        S" title" HTML-CHILD
        HTML-TEXT TYPE

\ Find an element by ID — walk descendants:
my-html S" html" HTML-CHILD
        S" body" HTML-CHILD
        S" div"  HTML-CHILD         \ first <div>
        HTML-ID TYPE                 \ prints its id
```

### Check Classes on an Element

```forth
\ Given: <div class="card featured large">
my-div S" featured" HTML-CLASS-HAS?
IF ." This is a featured card" THEN
```

### Build a Form

```forth
CREATE buf 1024 ALLOT
buf 1024 HTML-SET-OUTPUT

S" form" HTML-<
  S" action" S" /submit" HTML-ATTR!
  S" method" S" post" HTML-ATTR!
HTML->
  S" label" HTML-<  HTML->
    S" Name: " HTML-TEXT!
  S" label" HTML-</
  S" input" HTML-<
    S" type" S" text" HTML-ATTR!
    S" name" S" username" HTML-ATTR!
    S" required" HTML-BARE-ATTR!
  HTML-/>
  S" br" HTML-<  HTML-/>
  S" button" HTML-<  S" type" S" submit" HTML-ATTR!  HTML->
    S" Send" HTML-TEXT!
  S" button" HTML-</
S" form" HTML-</

HTML-OUTPUT-RESULT TYPE
```

### Iterate Children (Void-Aware)

```forth
\ List all children of <body>, skipping void elements correctly:
my-body HTML-ENTER
BEGIN
    HTML-EACH-CHILD
WHILE
    ." Found: " TYPE CR          \ print tag name
    2DROP
    _HTML-SKIP-ELEMENT           \ void-aware skip
REPEAT
2DROP
```

---

## Internal Words

These are prefixed with `_H` or `_HTML-` and are not part of the public
API.  They may change between versions.

| Word | Purpose |
|---|---|
| `_HV-TBL`, `_HV-COUNT`, `_HV-ENTRY-SIZE` | Void element lookup table (14 entries × 9 bytes). |
| `_HV-NA`, `_HV-NL` | State for `HTML-VOID?`. |
| `_HR-SCRIPT`, `_HR-STYLE` | Byte arrays for raw-text element name matching. |
| `_HTML-RAW-TEXT?` | Check if tag name is a raw text element. |
| `_HTML-FIND-RAW-CLOSE` | Scan raw content for `</name>` (case-insensitive). |
| `_HTML-SKIP-RAW` | Skip raw content past `</name>`. |
| `_HTML-SKIP-ELEMENT` | Skip element (void-aware, raw-text-aware, case-insensitive). |
| `_HTML-FIND-TAG` | Find opening tag (case-insensitive, void-aware). |
| `_HTML-FIND-CLOSE` | Find matching close tag (case-insensitive, void-aware). |
| `_HTML-INNER` | Extract inner content (case-insensitive close matching). |
| `_HTML-EMIT`, `_HTML-TYPE` | Builder output primitives. |
| `_HTML-ESCAPE-CHAR` | Emit character with HTML text escaping. |
| `_HB-BUF`, `_HB-MAX`, `_HB-POS` | Builder buffer state. |
| `_HC-NA`, `_HC-NL` | State for `HTML-CHILD`. |
| `_HCH-*` | State for `HTML-CLASS-HAS?`. |
| `_HC-LIT-CLASS` | Byte array `"class"` for attribute lookup. |
| `_HID-BUF` | Inline `"id"` for `HTML-ID`. |
| `_HEC-NA`, `_HEC-NL` | State for `HTML-EACH-CHILD`. |
| `_HDE-*` | State for `HTML-DECODE-ENTITY`. |
| `_HE-*` | Byte arrays for 31 named entity strings. |
| `_HSE-*`, `_HFT-*`, `_HFC-*`, `_HI-*`, `_HFRC-*` | State for internal navigation words. |
