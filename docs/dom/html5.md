# akashic-html5 — HTML5 Document Model Layer for KDOS / Megapad-64

Sits atop `dom.f` and provides the standard HTML5 document skeleton
(`<html>`, `<head>`, `<body>`), structural getters, and one-liner
element sugar words.  Does **not** import `event.f` — orthogonal
concern.

```forth
REQUIRE html5.f
```

`PROVIDED akashic-html5` — safe to include multiple times.
Automatically loads `akashic-dom`.

---

## Table of Contents

- [Design Overview](#design-overview)
- [Dependencies](#dependencies)
- [Document Scaffolding](#document-scaffolding)
- [Structural Getters](#structural-getters)
- [Element Sugar](#element-sugar)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Overview

| Principle | Detail |
|---|---|
| **Convention over configuration** | `DOM-HTML-INIT` creates the standard `<html>/<head>/<body>` skeleton in one call. |
| **Thin wrapper** | Every sugar word is a one-liner around `DOM-CREATE-ELEMENT` with a baked-in tag string. |
| **Descriptor slots** | The three structural nodes are stored in the doc descriptor's `D.HTML` (+80), `D.HEAD` (+88), `D.BODY` (+96) slots added in dom.f v2 (13-cell / 104-byte descriptor). |
| **No event coupling** | html5.f is independent of event.f.  Load either or both. |

---

## Dependencies

```
html5.f
└── dom.f   (akashic-dom)
```

Loaded automatically via `REQUIRE`.

---

## Document Scaffolding

### DOM-HTML-INIT

```forth
DOM-HTML-INIT  ( -- )
```

Creates the standard HTML5 skeleton and stores the three nodes in the
document descriptor:

```
<html>          → D.HTML (+80)
  <head>        → D.HEAD (+88)
  <body>        → D.BODY (+96)
</html>
```

**Preconditions:**
- A document must be active (`DOM-DOC-NEW` + `DOM-USE`).
- Must be called exactly once per document.  Calling twice ABORTs with
  `"html5: already initialised"`.

**Descriptor fields set:**

| Field | Offset | Contents |
|---|---|---|
| `D.HTML` | +80 | `<html>` element node |
| `D.HEAD` | +88 | `<head>` element node |
| `D.BODY` | +96 | `<body>` element node |

### Example

```forth
my-arena 64 64 DOM-DOC-NEW CONSTANT my-doc
DOM-HTML-INIT

\ Now DOM-HTML, DOM-HEAD, DOM-BODY are available
DOM-BODY DOM-TAG-NAME TYPE CR   \ body
```

---

## Structural Getters

| Word | Stack | Description |
|---|---|---|
| `DOM-HTML` | `( -- node )` | Return the `<html>` element. |
| `DOM-HEAD` | `( -- node )` | Return the `<head>` element. |
| `DOM-BODY` | `( -- node )` | Return the `<body>` element. |

All three read from the current document descriptor (`DOM-DOC`).
Returns 0 if `DOM-HTML-INIT` has not been called.

---

## Element Sugar

One-liner wrappers around `DOM-CREATE-ELEMENT`.  Each returns a
freshly-allocated element node.  **Caller is responsible for appending
to the tree.**

### Structural / Sectioning

| Word | Tag | Word | Tag |
|---|---|---|---|
| `DOM-DIV` | `<div>` | `DOM-SECTION` | `<section>` |
| `DOM-ARTICLE` | `<article>` | `DOM-NAV` | `<nav>` |
| `DOM-HEADER` | `<header>` | `DOM-FOOTER` | `<footer>` |
| `DOM-MAIN` | `<main>` | `DOM-ASIDE` | `<aside>` |

### Headings

| Word | Tag | Word | Tag |
|---|---|---|---|
| `DOM-H1` | `<h1>` | `DOM-H2` | `<h2>` |
| `DOM-H3` | `<h3>` | `DOM-H4` | `<h4>` |
| `DOM-H5` | `<h5>` | `DOM-H6` | `<h6>` |

### Inline / Phrasing

| Word | Tag | Word | Tag |
|---|---|---|---|
| `DOM-SPAN` | `<span>` | `DOM-A` | `<a>` |
| `DOM-STRONG` | `<strong>` | `DOM-EM` | `<em>` |
| `DOM-P` | `<p>` | `DOM-PRE` | `<pre>` |
| `DOM-CODE` | `<code>` | | |

### Lists

| Word | Tag |
|---|---|
| `DOM-UL` | `<ul>` |
| `DOM-OL` | `<ol>` |
| `DOM-LI` | `<li>` |

### Tables

| Word | Tag | Word | Tag |
|---|---|---|---|
| `DOM-TABLE` | `<table>` | `DOM-THEAD` | `<thead>` |
| `DOM-TBODY` | `<tbody>` | `DOM-TR` | `<tr>` |
| `DOM-TH` | `<th>` | `DOM-TD` | `<td>` |

### Forms / Interactive

| Word | Tag | Word | Tag |
|---|---|---|---|
| `DOM-FORM` | `<form>` | `DOM-BUTTON` | `<button>` |
| `DOM-INPUT` | `<input>` | `DOM-LABEL` | `<label>` |
| `DOM-SELECT` | `<select>` | `DOM-OPTION` | `<option>` |
| `DOM-TEXTAREA` | `<textarea>` | | |

### Media / Embedded

| Word | Tag |
|---|---|
| `DOM-IMG` | `<img>` |
| `DOM-CANVAS` | `<canvas>` |

### Misc

| Word | Tag |
|---|---|
| `DOM-BR` | `<br>` |
| `DOM-HR` | `<hr>` |

---

## Quick Reference

```
DOM-HTML-INIT   ( -- )            Create <html>/<head>/<body> skeleton
DOM-HTML        ( -- node )       Get <html> element
DOM-HEAD        ( -- node )       Get <head> element
DOM-BODY        ( -- node )       Get <body> element

DOM-DIV         ( -- node )       DOM-SECTION     ( -- node )
DOM-ARTICLE     ( -- node )       DOM-NAV         ( -- node )
DOM-HEADER      ( -- node )       DOM-FOOTER      ( -- node )
DOM-MAIN        ( -- node )       DOM-ASIDE       ( -- node )
DOM-H1 .. DOM-H6  ( -- node )
DOM-SPAN        ( -- node )       DOM-A           ( -- node )
DOM-STRONG      ( -- node )       DOM-EM          ( -- node )
DOM-P           ( -- node )       DOM-PRE         ( -- node )
DOM-CODE        ( -- node )
DOM-UL          ( -- node )       DOM-OL          ( -- node )
DOM-LI          ( -- node )
DOM-TABLE       ( -- node )       DOM-THEAD       ( -- node )
DOM-TBODY       ( -- node )       DOM-TR          ( -- node )
DOM-TH          ( -- node )       DOM-TD          ( -- node )
DOM-FORM        ( -- node )       DOM-BUTTON      ( -- node )
DOM-INPUT       ( -- node )       DOM-LABEL       ( -- node )
DOM-SELECT      ( -- node )       DOM-OPTION      ( -- node )
DOM-TEXTAREA    ( -- node )
DOM-IMG         ( -- node )       DOM-CANVAS      ( -- node )
DOM-BR          ( -- node )       DOM-HR          ( -- node )
```

---

## Cookbook

### Basic page structure

```forth
my-arena 64 64 DOM-DOC-NEW CONSTANT my-doc
DOM-HTML-INIT

DOM-H1 DOM-HEAD DOM-APPEND
S" My Page" DOM-CREATE-TEXT DOM-HEAD DOM-LAST-CHILD DOM-APPEND

DOM-DIV DOM-BODY DOM-APPEND
S" Hello, world!" DOM-CREATE-TEXT DOM-BODY DOM-FIRST-CHILD DOM-APPEND
```

### Build a list

```forth
DOM-UL CONSTANT my-list
my-list DOM-BODY DOM-APPEND

: add-item  ( addr u -- )
    DOM-LI >R
    DOM-CREATE-TEXT R@ DOM-APPEND
    R> my-list DOM-APPEND ;

S" Alpha" add-item
S" Bravo" add-item
S" Charlie" add-item
```

### Build a table row

```forth
: add-cell  ( addr u row -- )
    >R DOM-TD DUP >R DOM-CREATE-TEXT R@ DOM-APPEND
    R> R> DOM-APPEND ;

DOM-TR CONSTANT row
S" Name" row add-cell
S" Age"  row add-cell
my-table DOM-APPEND
```

### Use with event system

```forth
REQUIRE event.f
REQUIRE html5.f

my-doc DOME-INIT-DEFAULT CONSTANT my-dome

DOM-BUTTON CONSTANT btn
btn DOM-BODY DOM-APPEND

: on-click  ( event node -- )  2DROP ." clicked!" CR ;
btn  DOME-TI-CLICK DOME-TYPE@  ['] on-click  DOME-LISTEN
```
