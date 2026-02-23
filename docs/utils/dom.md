# akashic-dom — Arena-Backed DOM for KDOS / Megapad-64

An in-memory document object model backed by the KDOS arena allocator.
Each document lives in a single arena, enabling multiple simultaneous
documents and O(1) bulk teardown via `ARENA-DESTROY`.

```forth
REQUIRE dom.f
```

`PROVIDED akashic-dom` — safe to include multiple times.
Automatically loads `akashic-css-bridge` (which loads `akashic-html`,
`akashic-markup-core`, and `akashic-css`).

---

## Table of Contents

- [Design Principles](#design-principles)
- [Dependencies](#dependencies)
- [Memory Architecture](#memory-architecture)
- [Document Lifecycle](#document-lifecycle)
- [Node Types & Constants](#node-types--constants)
- [Tree Navigation](#tree-navigation)
- [Tree Mutation](#tree-mutation)
- [Node Creation](#node-creation)
- [Text & Tag Access](#text--tag-access)
- [Attributes](#attributes)
- [Attribute Iteration](#attribute-iteration)
- [Style Resolution](#style-resolution)
- [Query & Traversal](#query--traversal)
- [Serialisation](#serialisation)
- [Parser (HTML → DOM)](#parser-html--dom)
- [Quick Reference](#quick-reference)
- [Internal Words](#internal-words)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Arena-backed** | All memory (nodes, attrs, strings) is allotted from a single KDOS arena per document.  `ARENA-DESTROY` frees everything at once. |
| **Slab allocation** | Nodes and attributes are fixed-size (80 and 24 bytes respectively) and managed by free-lists for O(1) alloc/free. |
| **String pool** | All strings (tag names, text, attribute names/values) are stored in a bump-allocated region with reference counting.  Multiple nodes can share the same string handle. |
| **No hidden heap use** | All output buffers are user-provided.  No dynamic allocation outside the arena. |
| **Multiple documents** | Switch between documents with `DOM-USE` / `DOM-DOC`. |
| **CSS integration** | Style resolution uses `akashic-css-bridge` for selector matching and declaration collection.  No separate style subsystem needed. |
| **Void-element aware** | The serialiser and parser both respect HTML5 void elements via `HTML-VOID?`. |

---

## Dependencies

```
dom.f
└── ../css/bridge.f      (akashic-css-bridge)
    ├── ../markup/html.f  (akashic-html)
    │   └── ../markup/core.f  (akashic-markup-core)
    └── css.f             (akashic-css)
```

All dependencies are loaded automatically via `REQUIRE` with relative
paths.

**Runtime requirement:** The KDOS arena allocator must be available
(`ARENA-NEW`, `ARENA-ALLOT`).  The arena should be backed by
`A-XMEM` (extended memory, 14+ MiB) rather than `A-HEAP` (~94 KiB).

---

## Memory Architecture

A document is created with `DOM-DOC-NEW` which allots three regions
from the arena:

```
┌─────────────────────────────────┐
│  Document Descriptor (80 bytes) │
├─────────────────────────────────┤
│  Node Slab (80 × max-nodes)     │  fixed-size, free-list managed
├─────────────────────────────────┤
│  Attr Slab (24 × max-attrs)     │  fixed-size, free-list managed
├─────────────────────────────────┤
│  String Region (remaining)      │  bump-allocated, refcounted
└─────────────────────────────────┘
```

### Memory Budget

| Component | Formula | Example (64 nodes, 64 attrs) |
|---|---|---|
| Doc descriptor | 80 B | 80 B |
| Node slab | 80 × N | 5,120 B |
| Attr slab | 24 × A | 1,536 B |
| String region | remainder | ~517 KiB (in 524,288 arena) |

### Node Layout (80 bytes = 10 cells)

| Offset | Field | Purpose |
|---|---|---|
| +0 | `N.TYPE` | Node type (element, text, etc.) |
| +8 | `N.FLAGS` | User-defined flags |
| +16 | `N.PARENT` | Parent node address (0 = root) |
| +24 | `N.FIRST-CHILD` | First child address |
| +32 | `N.LAST-CHILD` | Last child address |
| +40 | `N.NEXT-SIB` | Next sibling address |
| +48 | `N.PREV-SIB` | Previous sibling address |
| +56 | `N.NAME` | String handle (tag name or text) |
| +64 | `N.FIRST-ATTR` | First attr in linked list |
| +72 | `N.AUX` | Reserved for extensions |

### Attribute Layout (24 bytes = 3 cells)

| Offset | Field | Purpose |
|---|---|---|
| +0 | `A.NAME` | String handle for attribute name |
| +8 | `A.VALUE` | String handle for attribute value |
| +16 | `A.NEXT` | Next attr in linked list (0 = end) |

---

## Document Lifecycle

| Word | Stack | Description |
|---|---|---|
| `DOM-DOC-NEW` | `( arena max-nodes max-attrs -- doc )` | Create a new document in the given arena.  Allots descriptor, node slab, attr slab, and string region.  Builds free-lists.  Calls `DOM-USE` on the new doc. |
| `DOM-USE` | `( doc -- )` | Set `doc` as the current document for all subsequent DOM operations. |
| `DOM-DOC` | `( -- doc )` | Return the current document handle. |

### Example

```forth
524288 A-XMEM ARENA-NEW DROP CONSTANT my-arena
my-arena 256 128 DOM-DOC-NEW CONSTANT my-doc

\ Switch documents:
other-doc DOM-USE
\ ... work with other-doc ...
my-doc DOM-USE
```

Teardown: call `ARENA-DESTROY` on the arena to free all memory at
once (nodes, attrs, strings, descriptor).

---

## Node Types & Constants

| Constant | Value | Description |
|---|---|---|
| `DOM-T-ELEMENT` | 1 | Element node (`<div>`, `<p>`, etc.) |
| `DOM-T-TEXT` | 2 | Text content node |
| `DOM-T-COMMENT` | 3 | Comment node (`<!-- ... -->`) |
| `DOM-T-DOCUMENT` | 4 | Document root (reserved) |
| `DOM-T-FRAGMENT` | 5 | Document fragment (no tag) |

| Constant | Value | Description |
|---|---|---|
| `DOM-NODE-SIZE` | 80 | Bytes per node |
| `DOM-ATTR-SIZE` | 24 | Bytes per attribute |

---

## Tree Navigation

All navigation words return 0 when there is no such node.

| Word | Stack | Description |
|---|---|---|
| `DOM-PARENT` | `( node -- parent\|0 )` | Parent node |
| `DOM-FIRST-CHILD` | `( node -- child\|0 )` | First child |
| `DOM-LAST-CHILD` | `( node -- child\|0 )` | Last child |
| `DOM-NEXT` | `( node -- sib\|0 )` | Next sibling |
| `DOM-PREV` | `( node -- sib\|0 )` | Previous sibling |
| `DOM-CHILD-COUNT` | `( node -- n )` | Number of children |
| `DOM-NTH-CHILD` | `( parent n -- node\|0 )` | 0-based nth child |
| `DOM-TYPE@` | `( node -- type )` | Node type constant |
| `DOM-FLAGS@` | `( node -- flags )` | User-defined flags |
| `DOM-FLAGS!` | `( flags node -- )` | Set flags |

---

## Tree Mutation

| Word | Stack | Description |
|---|---|---|
| `DOM-APPEND` | `( child parent -- )` | Append child as last child of parent |
| `DOM-PREPEND` | `( child parent -- )` | Prepend child as first child of parent |
| `DOM-DETACH` | `( node -- )` | Remove node from its parent (preserves node, no free) |
| `DOM-INSERT-BEFORE` | `( new ref -- )` | Insert `new` before `ref` in `ref`'s parent |
| `DOM-REMOVE` | `( node -- )` | Detach node and recursively free it, all descendants, and all attributes.  Uses iterative DFS (no stack overflow). |

### Example

```forth
S" div" DOM-CREATE-ELEMENT CONSTANT my-div
S" Hello" DOM-CREATE-TEXT my-div DOM-APPEND
S" span" DOM-CREATE-ELEMENT my-div DOM-APPEND

my-div DOM-CHILD-COUNT .   \ 2

my-div DOM-FIRST-CHILD DOM-DETACH    \ detach text node
my-div DOM-CHILD-COUNT .   \ 1
```

---

## Node Creation

All creation words allocate from the current document's pools.

| Word | Stack | Description |
|---|---|---|
| `DOM-CREATE-ELEMENT` | `( tag-a tag-u -- node )` | Create an element node with the given tag name |
| `DOM-CREATE-TEXT` | `( txt-a txt-u -- node )` | Create a text node |
| `DOM-CREATE-COMMENT` | `( txt-a txt-u -- node )` | Create a comment node |
| `DOM-CREATE-FRAGMENT` | `( -- node )` | Create a document fragment (no tag name) |

---

## Text & Tag Access

| Word | Stack | Description |
|---|---|---|
| `DOM-TAG-NAME` | `( node -- name-a name-u )` | Return element's tag name string |
| `DOM-TEXT` | `( node -- txt-a txt-u )` | Return text/comment content string |
| `DOM-SET-TEXT` | `( node txt-a txt-u -- )` | Replace text/comment content.  Releases old string, allocates new. |

`DOM-TAG-NAME` and `DOM-TEXT` are the same underlying operation (both
read `N.NAME`); the two names exist for clarity.

---

## Attributes

Attribute names are matched **case-insensitively**.

| Word | Stack | Description |
|---|---|---|
| `DOM-ATTR@` | `( node name-a name-u -- val-a val-u flag )` | Get attribute value.  Flag = -1 found, 0 not found. |
| `DOM-ATTR!` | `( node name-a name-u val-a val-u -- )` | Set attribute (creates or updates). |
| `DOM-ATTR-DEL` | `( node name-a name-u -- )` | Delete attribute.  No-op if not present. |
| `DOM-ATTR-HAS?` | `( node name-a name-u -- flag )` | Test if attribute exists. |
| `DOM-ATTR-COUNT` | `( node -- n )` | Number of attributes on node. |
| `DOM-ID` | `( node -- str-a str-u )` | Shortcut: returns `id` attribute value (or `0 0`). |
| `DOM-CLASS` | `( node -- str-a str-u )` | Shortcut: returns `class` attribute value (or `0 0`). |

### Example

```forth
S" div" DOM-CREATE-ELEMENT CONSTANT el

el S" class" S" container" DOM-ATTR!
el S" id"    S" main"      DOM-ATTR!

el DOM-CLASS TYPE CR    \ container
el DOM-ID    TYPE CR    \ main

el S" class" DOM-ATTR-HAS? .    \ -1
el S" CLASS" DOM-ATTR-HAS? .    \ -1  (case-insensitive)

el S" id" DOM-ATTR-DEL
el S" id" DOM-ATTR-HAS? .      \ 0
```

---

## Attribute Iteration

Walk the linked list of attributes on a node:

| Word | Stack | Description |
|---|---|---|
| `DOM-ATTR-FIRST` | `( node -- attr\|0 )` | First attribute handle |
| `DOM-ATTR-NEXTATTR` | `( attr -- attr\|0 )` | Next attribute handle |
| `DOM-ATTR-NAME@` | `( attr -- a u )` | Attribute name string |
| `DOM-ATTR-VAL@` | `( attr -- a u )` | Attribute value string |

### Example

```forth
el DOM-ATTR-FIRST
BEGIN ?DUP WHILE
    DUP DOM-ATTR-NAME@ TYPE ." =" DUP DOM-ATTR-VAL@ TYPE CR
    DOM-ATTR-NEXTATTR
REPEAT
```

---

## Style Resolution

CSS style resolution connects the DOM to `akashic-css-bridge`.
A stylesheet must be set before style queries work.

| Word | Stack | Description |
|---|---|---|
| `DOM-SET-STYLESHEET` | `( css-a css-u -- )` | Set the current CSS stylesheet for style computation. |
| `DOM-COMPUTE-STYLE` | `( node buf max -- n )` | Compute all matching CSS declarations for an element node.  Reconstructs the open tag (`<tag attrs>`) and feeds it to `CSSB-APPLY-INLINE`.  Returns bytes written.  Returns 0 for non-element nodes. |
| `DOM-STYLE@` | `( node prop-a prop-u -- val-a val-u flag )` | Look up a single CSS property.  Computes style, then searches declarations with `CSS-DECL-FIND`.  Flag = -1 found, 0 not found. |
| `DOM-STYLE-CACHED?` | `( node -- flag )` | Stub: always returns 0 (cache not yet implemented). |
| `DOM-INVALIDATE-STYLE` | `( node -- )` | Stub: no-op (cache not yet implemented). |

### Example

```forth
S" div { color: red } .box { padding: 8px }" DOM-SET-STYLESHEET

S" div" DOM-CREATE-ELEMENT CONSTANT el
el S" class" S" box" DOM-ATTR!
el DOM-APPEND-TO root

\ Compute all styles:
CREATE buf 2048 ALLOT
el buf 2048 DOM-COMPUTE-STYLE    \ ( n )
buf SWAP TYPE CR
\ Output: color: red; padding: 8px

\ Look up a single property:
el S" padding" DOM-STYLE@
IF TYPE CR ELSE 2DROP ." not found" CR THEN
\ Output: 8px
```

### How It Works

1. `DOM-COMPUTE-STYLE` reconstructs the element's open tag string
   (e.g. `<div class="box">`) by walking the node's tag name and
   attribute list.
2. It passes the reconstructed tag and the current stylesheet to
   `CSSB-APPLY-INLINE` (from `akashic-css-bridge`), which handles
   selector matching, cascade, and inline style merging.
3. `DOM-STYLE@` calls `DOM-COMPUTE-STYLE` then searches the result
   with `CSS-DECL-FIND`.

---

## Query & Traversal

All query words perform depth-first search on the subtree rooted at
the given node.  The root node itself is **not** tested (queries start
from its descendants).

### CSS Selector Queries

| Word | Stack | Description |
|---|---|---|
| `DOM-MATCHES?` | `( node sel-a sel-u -- flag )` | Does this element node match a CSS selector?  Returns 0 for non-element nodes. |
| `DOM-QUERY` | `( root sel-a sel-u -- node\|0 )` | Find the first descendant matching a CSS selector (depth-first).  Returns 0 if not found. |
| `DOM-QUERY-ALL` | `( root sel-a sel-u buf max -- n )` | Find all matching descendants.  Stores node addresses in `buf` (8 bytes each, up to `max` entries).  Returns count. |

### Specialised Queries

| Word | Stack | Description |
|---|---|---|
| `DOM-GET-BY-ID` | `( root id-a id-u -- node\|0 )` | Find first descendant with matching `id` attribute (case-insensitive). |
| `DOM-GET-BY-TAG` | `( root tag-a tag-u buf max -- n )` | Find all descendants with matching tag name.  Returns count. |
| `DOM-GET-BY-CLASS` | `( root cls-a cls-u buf max -- n )` | Find all descendants with matching class.  Builds `.classname` selector internally, delegates to `DOM-QUERY-ALL`. |

### Walking

| Word | Stack | Description |
|---|---|---|
| `DOM-WALK-DEPTH` | `( root xt -- )` | Walk all nodes in depth-first order, calling `xt` for each.  `xt` receives `( node -- )`.  **Not reentrant** (shares DFS state variables). |
| `DOM-NTH-CHILD` | `( parent n -- node\|0 )` | Return the nth child (0-based).  Returns 0 if out of range. |

### Example

```forth
S" <div><h1 id=\"title\">Hi</h1><p class=\"intro\">Text</p></div>"
DUP SWAP DOM-PARSE-HTML CONSTANT root

\ Find by selector:
root S" h1" DOM-QUERY DOM-TAG-NAME TYPE CR     \ h1
root S" .intro" DOM-QUERY DOM-TAG-NAME TYPE CR \ p

\ Find by id:
root S" title" DOM-GET-BY-ID DOM-TAG-NAME TYPE CR  \ h1

\ Count all elements:
VARIABLE cnt
: count-el  ( node -- ) DROP 1 cnt +! ;
0 cnt !
root ['] count-el DOM-WALK-DEPTH
cnt @ .   \ 4  (div + h1 + p + text nodes)
```

---

## Serialisation

Convert a DOM tree (or subtree) back to HTML text.  Uses the
`akashic-html` builder for proper escaping and void-element handling.

| Word | Stack | Description |
|---|---|---|
| `DOM-TO-HTML` | `( node buf max -- n )` | Serialise the node and all its descendants to HTML.  Returns bytes written. |
| `DOM-OUTER-HTML` | `( node buf max -- n )` | Alias for `DOM-TO-HTML`. |
| `DOM-INNER-HTML` | `( node buf max -- n )` | Serialise only the children of `node` (no wrapping tag).  Returns bytes written. |

### Behaviour by Node Type

| Type | Output |
|---|---|
| Element | `<tag attrs>children</tag>` (or `<tag attrs>` for void elements) |
| Text | Entity-escaped text (`<` → `&lt;`, `>` → `&gt;`, `&` → `&amp;`) |
| Comment | `<!-- text -->` |
| Fragment | Children only (no wrapping tag) |

### Example

```forth
S" div" DOM-CREATE-ELEMENT CONSTANT el
S" Hello" DOM-CREATE-TEXT el DOM-APPEND
el S" class" S" box" DOM-ATTR!

CREATE buf 1024 ALLOT
el buf 1024 DOM-TO-HTML    \ ( n )
buf SWAP TYPE CR
\ Output: <div class="box">Hello</div>

el buf 1024 DOM-INNER-HTML
buf SWAP TYPE CR
\ Output: Hello
```

### Round-Trip

Parsing then serialising should produce equivalent (though not
necessarily identical) HTML:

```forth
S" <div><p>hello</p></div>"
DUP SWAP DOM-PARSE-HTML
DOM-FIRST-CHILD buf 1024 DOM-TO-HTML
buf SWAP TYPE CR
\ Output: <div><p>hello</p></div>
```

---

## Parser (HTML → DOM)

Parse HTML text into a DOM tree.

| Word | Stack | Description |
|---|---|---|
| `DOM-PARSE-HTML` | `( html-a html-u -- root )` | Parse HTML into a DOM tree.  Returns a fragment node containing the parsed tree.  All top-level elements/text/comments become children of the fragment. |
| `DOM-PARSE-FRAGMENT` | `( html-a html-u parent -- )` | Parse HTML and append results as children of an existing parent node. |

### Supported Constructs

| Construct | Handling |
|---|---|
| Open tags `<tag>` | Creates element, pushes onto internal parent stack |
| Close tags `</tag>` | Pops parent stack |
| Self-closing `<tag/>` | Creates element, does not push |
| Void elements | Detected via `HTML-VOID?`, treated like self-closing |
| Text content | Creates text node between tags |
| Comments `<!-- -->` | Creates comment node |
| Attributes | Parsed with `MU-ATTR-NEXT`, set via `DOM-ATTR!` |
| `<!DOCTYPE>` | Skipped |
| PI `<?...?>` | Skipped |
| CDATA `<![CDATA[...]]>` | Skipped |

### Example

```forth
S" <ul><li>One</li><li>Two</li></ul>"
DUP SWAP DOM-PARSE-HTML CONSTANT root

root DOM-FIRST-CHILD DOM-CHILD-COUNT .   \ 2

\ Parse into existing node:
S" <span>new</span>"
my-div DOM-PARSE-FRAGMENT
my-div DOM-CHILD-COUNT .   \ now has span as child
```

---

## Quick Reference

### Document Management

```
DOM-DOC-NEW         ( arena max-n max-a -- doc )   create document
DOM-USE             ( doc -- )                     set current doc
DOM-DOC             ( -- doc )                     get current doc
```

### Node Creation

```
DOM-CREATE-ELEMENT  ( tag-a tag-u -- node )        new element
DOM-CREATE-TEXT     ( txt-a txt-u -- node )         new text node
DOM-CREATE-COMMENT  ( txt-a txt-u -- node )         new comment
DOM-CREATE-FRAGMENT ( -- node )                     new fragment
```

### Tree Navigation

```
DOM-PARENT          ( node -- parent|0 )
DOM-FIRST-CHILD     ( node -- child|0 )
DOM-LAST-CHILD      ( node -- child|0 )
DOM-NEXT            ( node -- sib|0 )
DOM-PREV            ( node -- sib|0 )
DOM-CHILD-COUNT     ( node -- n )
DOM-NTH-CHILD       ( parent n -- node|0 )
DOM-TYPE@           ( node -- type )
DOM-FLAGS@          ( node -- flags )
DOM-FLAGS!          ( flags node -- )
```

### Tree Mutation

```
DOM-APPEND          ( child parent -- )
DOM-PREPEND         ( child parent -- )
DOM-DETACH          ( node -- )
DOM-INSERT-BEFORE   ( new ref -- )
DOM-REMOVE          ( node -- )                    recursive free
```

### Attributes

```
DOM-ATTR@           ( node na nu -- va vu flag )
DOM-ATTR!           ( node na nu va vu -- )
DOM-ATTR-DEL        ( node na nu -- )
DOM-ATTR-HAS?       ( node na nu -- flag )
DOM-ATTR-COUNT      ( node -- n )
DOM-ID              ( node -- a u )
DOM-CLASS           ( node -- a u )
```

### Attribute Iteration

```
DOM-ATTR-FIRST      ( node -- attr|0 )
DOM-ATTR-NEXTATTR   ( attr -- attr|0 )
DOM-ATTR-NAME@      ( attr -- a u )
DOM-ATTR-VAL@       ( attr -- a u )
```

### Text & Tag Name

```
DOM-TAG-NAME        ( node -- a u )
DOM-TEXT            ( node -- a u )
DOM-SET-TEXT        ( node txt-a txt-u -- )
```

### Style Resolution

```
DOM-SET-STYLESHEET  ( css-a css-u -- )
DOM-COMPUTE-STYLE   ( node buf max -- n )
DOM-STYLE@          ( node prop-a prop-u -- va vu flag )
DOM-STYLE-CACHED?   ( node -- flag )               stub
DOM-INVALIDATE-STYLE ( node -- )                    stub
```

### Query & Traversal

```
DOM-MATCHES?        ( node sel-a sel-u -- flag )
DOM-QUERY           ( root sel-a sel-u -- node|0 )
DOM-QUERY-ALL       ( root sel-a sel-u buf max -- n )
DOM-GET-BY-ID       ( root id-a id-u -- node|0 )
DOM-GET-BY-TAG      ( root tag-a tag-u buf max -- n )
DOM-GET-BY-CLASS    ( root cls-a cls-u buf max -- n )
DOM-WALK-DEPTH      ( root xt -- )
DOM-NTH-CHILD       ( parent n -- node|0 )
```

### Serialisation

```
DOM-TO-HTML         ( node buf max -- n )
DOM-OUTER-HTML      ( node buf max -- n )
DOM-INNER-HTML      ( node buf max -- n )
```

### Parser

```
DOM-PARSE-HTML      ( html-a html-u -- root )
DOM-PARSE-FRAGMENT  ( html-a html-u parent -- )
```

---

## Internal Words

These are prefixed with `_DOM-`, `_DDN-`, `_DFS-`, `_DMQ-`, `_DQ-`,
`_DQA-`, `_SER-`, `_PH-`, etc.  They are not part of the public API
and may change without notice.

| Prefix | Purpose |
|---|---|
| `_DOM-CUR` | Current document pointer |
| `_DOM-STR-*` | String pool operations (alloc, get, ref, release) |
| `_DOM-ZERO-NODE` | Zero-fill a node |
| `_DOM-ALLOC` / `_DOM-FREE` | Node free-list management |
| `_DOM-ATTR-ALLOC` / `_DOM-ATTR-RELEASE` | Attribute free-list management |
| `_DOM-TOLOWER` / `_DOM-CISTREQ` | Case-insensitive string helpers |
| `_DOM-NODE-INIT-FREE` / `_DOM-ATTR-INIT-FREE` | Free-list construction at doc creation |
| `_DOM-FREE-ATTRS` | Release all attributes on a node |
| `_DOM-BUILD-OPEN-TAG` | Reconstruct `<tag attrs>` from a DOM node |
| `_DOM-SER-*` | Serialisation DFS walk |
| `_DFS-*` | Shared DFS infrastructure for queries |
| `_DMQ-*` | DOM-MATCHES? state variables |
| `_DQ-*` / `_DQA-*` | DOM-QUERY / DOM-QUERY-ALL state |
| `_PH-*` | Parser state variables |
| `D.*` | Document descriptor field accessors |
| `N.*` | Node field accessors |
| `A.*` | Attribute field accessors |

---

## Cookbook

### Create a document and build a tree

```forth
\ Create arena (512 KiB in extended memory):
524288 A-XMEM ARENA-NEW DROP CONSTANT my-arena

\ Create document (up to 256 nodes, 128 attrs):
my-arena 256 128 DOM-DOC-NEW CONSTANT my-doc

\ Build a tree:
S" div" DOM-CREATE-ELEMENT CONSTANT root
root S" class" S" container" DOM-ATTR!

S" Hello, world!" DOM-CREATE-TEXT root DOM-APPEND

S" br" DOM-CREATE-ELEMENT root DOM-APPEND

S" p" DOM-CREATE-ELEMENT CONSTANT para
S" More text" DOM-CREATE-TEXT para DOM-APPEND
para root DOM-APPEND

\ Serialise:
CREATE buf 4096 ALLOT
root buf 4096 DOM-TO-HTML
buf SWAP TYPE CR
\ <div class="container">Hello, world!<br><p>More text</p></div>
```

### Parse HTML and query the tree

```forth
S" <div><h1 id=\"title\">Welcome</h1><p class=\"intro\">Hi</p></div>"
DUP SWAP DOM-PARSE-HTML CONSTANT root

\ Find by ID:
root S" title" DOM-GET-BY-ID
DUP DOM-FIRST-CHILD DOM-TEXT TYPE CR    \ Welcome

\ Find by selector:
root S" .intro" DOM-QUERY
DUP DOM-FIRST-CHILD DOM-TEXT TYPE CR    \ Hi

\ Count all children of root's first child (the div):
root DOM-FIRST-CHILD DOM-CHILD-COUNT .  \ 2
```

### Apply styles to a parsed document

```forth
S" h1 { color: blue } .intro { font-size: 14px }"
DOM-SET-STYLESHEET

root S" title" DOM-GET-BY-ID
S" color" DOM-STYLE@
IF TYPE CR ELSE 2DROP ." no color" CR THEN
\ blue

root S" .intro" DOM-QUERY
S" font-size" DOM-STYLE@
IF TYPE CR ELSE 2DROP ." no size" CR THEN
\ 14px
```

### Walk and transform

```forth
\ Double-wrap every text node in <em>:
: wrap-text  ( node -- )
    DUP DOM-TYPE@ DOM-T-TEXT <> IF DROP EXIT THEN
    DUP DOM-TEXT                  \ ( node txt-a txt-u )
    S" em" DOM-CREATE-ELEMENT    \ ( node txt-a txt-u em )
    >R                           \ save em
    DOM-CREATE-TEXT R@ DOM-APPEND \ text inside em
    DUP DOM-PARENT >R            \ save parent
    DUP DOM-DETACH               \ detach text node
    R> R> SWAP DOM-APPEND        \ em → parent
    DOM-REMOVE ;                 \ free old text node

root ['] wrap-text DOM-WALK-DEPTH
```

### Round-trip: HTML → DOM → HTML

```forth
CREATE out 4096 ALLOT

S" <ul><li>A</li><li>B</li></ul>"
DUP SWAP DOM-PARSE-HTML DOM-FIRST-CHILD
out 4096 DOM-TO-HTML
out SWAP TYPE CR
\ <ul><li>A</li><li>B</li></ul>
```

### Inner HTML manipulation

```forth
S" div" DOM-CREATE-ELEMENT CONSTANT el

\ Add children by parsing HTML:
S" <span>One</span><span>Two</span>"
el DOM-PARSE-FRAGMENT

\ Read inner HTML:
el out 4096 DOM-INNER-HTML
out SWAP TYPE CR
\ <span>One</span><span>Two</span>
```
