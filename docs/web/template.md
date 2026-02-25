# akashic-web-template — HTML Builder DSL / Micro-Templates for KDOS / Megapad-64

Two complementary approaches over `html.f`:

- **Approach A — Compositional Words**: `TPL-PAGE`, `TPL-LINK`, `TPL-LIST`, etc.
  Templates are just Forth words that call the html.f builder.
- **Approach B — Micro-Templates**: `TPL-VAR!`, `TPL-EXPAND` with `{{ name }}`
  placeholders for string interpolation.

All output goes through the `html.f` builder output buffer.
The caller must set up the buffer with `HTML-SET-OUTPUT` before use.

```forth
REQUIRE web/template.f
```

`PROVIDED akashic-web-template` — safe to include multiple times.

### Dependencies

```
web/template.f
├── markup/html.f  (akashic-html)
└── utils/string.f (akashic-string)
```

---

## Table of Contents

- [Design Principles](#design-principles)
- [Setup — HTML Output Buffer](#setup--html-output-buffer)
- [Approach A — Compositional Words](#approach-a--compositional-words)
  - [TPL-PAGE](#tpl-page)
  - [TPL-LINK](#tpl-link)
  - [TPL-LIST](#tpl-list)
  - [TPL-TABLE-ROW](#tpl-table-row)
  - [TPL-FORM / TPL-INPUT](#tpl-form--tpl-input)
- [Approach B — Micro-Templates](#approach-b--micro-templates)
  - [TPL-VAR! / TPL-VAR-CLEAR](#tpl-var--tpl-var-clear)
  - [TPL-EXPAND](#tpl-expand)
- [Quick Reference](#quick-reference)
- [Internal Words](#internal-words)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **No new parser** | Compositional words are plain Forth.  No template files, no template language — just function composition. |
| **Builds on html.f** | All tag generation delegates to `HTML-<`, `HTML->`, `HTML-</`, `HTML-ATTR!`, `HTML-TEXT!`.  Templates are a convenience layer, not an abstraction barrier. |
| **Two modes** | Compositional words for structured pages; `{{ }}` expansion for one-off string templates (email bodies, snippets). |
| **Static output buffer** | `TPL-EXPAND` writes to a fixed 4 KB buffer.  Not re-entrant.  Compositional words write to the html.f builder buffer (set by caller). |

---

## Setup — HTML Output Buffer

Before using any compositional template word (`TPL-PAGE`, `TPL-LINK`, etc.),
you must point the html.f builder at a buffer:

```forth
CREATE my-buf 8192 ALLOT
my-buf 8192 HTML-SET-OUTPUT
```

Then after rendering:

```forth
HTML-OUTPUT-RESULT  ( -- addr len )   \ the generated HTML
RESP-BODY                              \ append to response
```

Use `HTML-OUTPUT-RESET` to rewind the write position before rendering
a new page into the same buffer.

---

## Approach A — Compositional Words

### TPL-PAGE

```
TPL-PAGE ( title-a title-u body-xt -- )
```

Emit a full HTML5 page:

```html
<!DOCTYPE html><html><head><meta charset="utf-8"><title>...</title></head>
<body> [body-xt output] </body></html>
```

**Important**: `TPL-PAGE` calls `HTML-DOCTYPE` internally.
Do not call `HTML-DOCTYPE` separately.

```forth
: my-body  ( -- )
    S" h1" HTML-<  HTML->  S" Hello" HTML-TEXT!  S" h1" HTML-</
    S" p"  HTML-<  HTML->  S" It works." HTML-TEXT!  S" p" HTML-</ ;

HTML-OUTPUT-RESET
S" My App" ['] my-body TPL-PAGE
HTML-OUTPUT-RESULT RESP-BODY
```

### TPL-LINK

```
TPL-LINK ( href-a href-u text-a text-u -- )
```

Emit `<a href="href">text</a>`.

```forth
S" /login" S" Log In" TPL-LINK
\ → <a href="/login">Log In</a>
```

### TPL-LIST

```
TPL-LIST ( n xt -- )
```

Emit `<ul>` with `n` `<li>` items.  The xt receives the loop index
on the stack `( I -- )` and should emit the item content.

```forth
: show-item  ( i -- )
    ." Item " . ;  \ Use HTML-TEXT! in real code
3 ['] show-item TPL-LIST
\ → <ul><li>Item 0</li><li>Item 1</li><li>Item 2</li></ul>
```

### TPL-TABLE-ROW

```
TPL-TABLE-ROW ( n-cols xt -- )
```

Emit `<tr>` with `n` `<td>` cells.  The xt receives the column index
`( I -- )`.

```forth
: show-cell  ( col -- )  . ;
4 ['] show-cell TPL-TABLE-ROW
\ → <tr><td>0</td><td>1</td><td>2</td><td>3</td></tr>
```

### TPL-FORM / TPL-INPUT

```
TPL-FORM  ( action-a action-u method-a method-u body-xt -- )
TPL-INPUT ( type-a type-u name-a name-u -- )
```

Generate HTML form elements:

```forth
: login-fields  ( -- )
    S" text"     S" username" TPL-INPUT
    S" password" S" password" TPL-INPUT ;

S" /login" S" POST" ['] login-fields TPL-FORM
\ → <form action="/login" method="POST">
\     <input type="text" name="username" />
\     <input type="password" name="password" />
\   </form>
```

---

## Approach B — Micro-Templates

### TPL-VAR! / TPL-VAR-CLEAR

```
TPL-VAR!     ( val-a val-u name-a name-u -- )
TPL-VAR-CLEAR ( -- )
```

Set or clear template variables.  Up to 16 variables.
Name: max 24 bytes.  Value: max 120 bytes.

```forth
S" Alice"   S" user"  TPL-VAR!
S" Welcome" S" title" TPL-VAR!
\ ...
TPL-VAR-CLEAR   \ remove all variables
```

Calling `TPL-VAR!` with an existing name updates the value.

### TPL-EXPAND

```
TPL-EXPAND ( tmpl-a tmpl-u -- result-a result-u )
```

Replace `{{ name }}` placeholders with variable values.
Whitespace inside braces is trimmed: `{{ user }}`, `{{user}}`,
and `{{ user}}` all work.

Unknown variables produce empty output (no error).

Result is in a static 4 KB buffer (`_TPL-OUT-BUF`) — not re-entrant.

```forth
S" Alice" S" name" TPL-VAR!
S" <h1>Hello, {{ name }}!</h1>" TPL-EXPAND
\ → ( addr len )  pointing to "<h1>Hello, Alice!</h1>"
```

---

## Quick Reference

| Word | Stack | Purpose |
|---|---|---|
| `TPL-PAGE` | `( title-a title-u body-xt -- )` | Full HTML5 page wrapper |
| `TPL-LINK` | `( href-a href-u text-a text-u -- )` | `<a>` link element |
| `TPL-LIST` | `( n xt -- )` | `<ul>` with `n` `<li>`s |
| `TPL-TABLE-ROW` | `( n-cols xt -- )` | `<tr>` with `n` `<td>`s |
| `TPL-FORM` | `( action-a action-u method-a method-u body-xt -- )` | `<form>` element |
| `TPL-INPUT` | `( type-a type-u name-a name-u -- )` | `<input />` element |
| `TPL-VAR!` | `( val-a val-u name-a name-u -- )` | Set template variable |
| `TPL-VAR-CLEAR` | `( -- )` | Clear all variables |
| `TPL-EXPAND` | `( tmpl-a tmpl-u -- result-a result-u )` | Expand `{{ }}` placeholders |

---

## Internal Words

| Word | Stack | Purpose |
|---|---|---|
| `_TPL-XT` | VARIABLE | Saved xt for body/list callbacks |
| `_TPL-A1/U1` | VARIABLE pair | Temp storage for first string arg |
| `_TPL-A2/U2` | VARIABLE pair | Temp storage for second string arg |
| `_TPL-VARS` | CREATE 2560 | Variable table (16 × 160 bytes) |
| `_TPL-NVAR` | VARIABLE | Count of set variables |
| `_TPL-OUT-BUF` | CREATE 4096 | Expansion output buffer |
| `_TPL-OUT-POS` | VARIABLE | Write position in output buffer |
| `_TPL-SLOT` | `( idx -- addr )` | Get variable slot address |
| `_TPL-VAR-FIND` | `( name-a name-u -- slot \| 0 )` | Lookup variable by name |
| `_TPL-OUT-CH` | `( c -- )` | Append char to output buffer |
| `_TPL-OUT-STR` | `( a u -- )` | Append string to output buffer |
| `_TPL-FIND-OPEN` | `( a u -- offset \| -1 )` | Find `{{` in string |
| `_TPL-FIND-CLOSE` | `( a u -- offset \| -1 )` | Find `}}` in string |

### Variable Slot Layout (160 bytes)

```
+0    name length     (8 bytes, 1 cell)
+8    name chars      (24 bytes)
+32   value length    (8 bytes, 1 cell)
+40   value chars     (120 bytes)
```

---

## Cookbook

### Full HTML page in a handler

```forth
CREATE html-buf 8192 ALLOT
html-buf 8192 HTML-SET-OUTPUT

: page-body  ( -- )
    S" h1" HTML-<  HTML->  S" Welcome" HTML-TEXT!  S" h1" HTML-</
    S" p"  HTML-<  HTML->  S" It works!" HTML-TEXT!  S" p" HTML-</ ;

: handle-index  ( -- )
    200 RESP-STATUS
    S" text/html" RESP-CONTENT-TYPE
    HTML-OUTPUT-RESET
    S" My App" ['] page-body TPL-PAGE
    HTML-OUTPUT-RESULT RESP-BODY
    RESP-SEND ;
```

### Greeting page with template variable

```forth
: handle-hello  ( -- )
    200 RESP-STATUS
    S" text/html" RESP-CONTENT-TYPE
    TPL-VAR-CLEAR
    S" name" ROUTE-PARAM S" name" TPL-VAR!
    S" <h1>Hello, {{ name }}!</h1><p>Welcome.</p>" TPL-EXPAND
    RESP-BODY
    RESP-SEND ;

S" GET" S" /hello/:name" ['] handle-hello ROUTE
```

### Navigation list

```forth
CREATE items 3 CELLS ALLOT
\ ... populate items array ...

: show-nav-item  ( i -- )
    items SWAP CELLS + @ COUNT HTML-TEXT! ;

: nav-bar  ( -- )
    3 ['] show-nav-item TPL-LIST ;
```

### Login form

```forth
: login-page  ( -- )
    S" h1" HTML-<  HTML->  S" Login" HTML-TEXT!  S" h1" HTML-</
    S" /auth" S" POST" ['] login-fields TPL-FORM ;

: login-fields  ( -- )
    S" text"     S" username" TPL-INPUT
    S" password" S" password" TPL-INPUT ;

S" Login" ['] login-page TPL-PAGE
```

### Combining both approaches

```forth
: dashboard-body  ( -- )
    S" h1" HTML-< HTML->  S" Dashboard" HTML-TEXT!  S" h1" HTML-</
    \ Inline template expansion, appended to HTML builder output
    S" user" ROUTE-PARAM S" user" TPL-VAR!
    S" Welcome back, {{ user }}." TPL-EXPAND
    HTML-RAW!
    \ Structured list via compositional word
    5 ['] show-stat TPL-LIST ;
```
