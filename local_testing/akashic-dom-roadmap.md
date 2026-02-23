# Roadmap: akashic-dom — Rich DOM Vocabulary for KDOS / Megapad-64

A layered plan for building a fully functional DOM (Document Object
Model) vocabulary on top of the existing akashic libraries and the
KDOS arena allocator.

## Status Quo

### What We Have

| Library | File | Lines | Tests | Purpose |
|---|---|---|---|---|
| akashic-markup-core | `utils/markup/core.f` | 881 | 114 | Tag scanning, attribute parsing, entity decode, element nav |
| akashic-html | `utils/markup/html.f` | 628 | 60 | HTML5 reader + builder, void/raw-text aware |
| akashic-xml | `utils/markup/xml.f` | 278 | 20 | XML reader + builder |
| akashic-css | `utils/css/css.f` | 1676 | 221 | CSS scanner, declarations, rules, selectors, matching, specificity, values, shorthands, @-rules, builder, named colors |
| akashic-css-bridge | `utils/css/bridge.f` | 189 | 24 | HTML↔CSS matching, style collection, inline merge |
| akashic-json | `utils/json/json.f` | 873 | 141 | JSON reader + builder |
| KDOS Arena Allocator | `kdos.f §1.1b` | ~200 | 33 | Region-aware scoped allocation (HEAP/XMEM/HBW), snapshots, scoped stack |
| **Total** | | **4725** | **613** | |

### What We Don't Have

The current libraries are **stateless readers and builders** — they
scan text in-place with zero-copy cursors.  There is no persistent,
mutable in-memory representation of a document.  To build a DOM we
need:

1. **Node allocation** — create/destroy nodes dynamically
2. **Tree structure** — parent/child/sibling links
3. **Attribute storage** — mutable attribute maps per node
4. **Text content** — owned string storage
5. **Style resolution** — computed styles per element
6. **Tree mutation** — insert, remove, move, clone nodes
7. **Serialisation** — render DOM tree back to HTML text

### Constraints

- **64-bit cells** — Megapad-64's Forth cell is 8 bytes (`@`/`!` operate on 8 bytes)
- **No DEFER/IS** — can't use late-binding for polymorphism
- **Extended memory** — 16 MiB via `ENTER-USERLAND`, plenty of space
- **CMOVE is `( src dst cnt -- )`** — non-standard order
- **S" is compile-only** — string literals only inside `:` definitions
- **CREATE cannot be inside `:`** — must pre-allocate tables
- **VARIABLE for all multi-step state** — no locals, no return-stack tricks in interpreted mode
- **KDOS arenas available** — `ARENA-NEW`, `ARENA-ALLOT`, `ARENA-RESET`, `ARENA-DESTROY`, `ARENA-SNAP`, `ARENA-ROLLBACK` all implemented and tested

---

## Architecture

### Arena-Based Design

Every DOM document lives inside a single KDOS arena.  This enables:
- **Multiple simultaneous documents** — each in its own arena
- **O(1) bulk document teardown** — `ARENA-DESTROY` frees everything
- **Transactional parsing** — `ARENA-SNAP` / `ARENA-ROLLBACK`
- **No custom allocator** — reuses existing, tested arena infrastructure

```
┌─────────────────────────────────────────────────┐
│                  Application                     │
├─────────────────────────────────────────────────┤
│  Layer 7: Serialisation (dom → HTML text)        │
├─────────────────────────────────────────────────┤
│  Layer 6: Query & Traversal (querySelector etc.) │
├─────────────────────────────────────────────────┤
│  Layer 5: Style Resolution (computed styles)     │
├─────────────────────────────────────────────────┤
│  Layer 4: Mutation (insert, remove, clone)       │
├─────────────────────────────────────────────────┤
│  Layer 3: Attribute Storage (get/set/remove)     │
├─────────────────────────────────────────────────┤
│  Layer 2: Tree Structure (parent/child/sibling)  │
├─────────────────────────────────────────────────┤
│  Layer 1: Node Allocation (free-list over arena) │
├─────────────────────────────────────────────────┤
│  Layer 0: String Pool (bump alloc in arena)      │
├─────────────────────────────────────────────────┤
│  KDOS Arena Allocator (ARENA-NEW / ALLOT / etc.) │
├─────────────────────────────────────────────────┤
│  Existing: markup/core, html, css, bridge, json  │
└─────────────────────────────────────────────────┘
```

### Per-Document Memory Layout

Each document's arena is carved into three sub-regions at creation:

```
┌─────────────────────────────────────────────────┐
│  Document Arena (one ARENA-NEW call)             │
│  ┌───────────────────────────────────────────┐  │
│  │  Doc descriptor (10 cells = 80 bytes)      │  │
│  ├───────────────────────────────────────────┤  │
│  │  String region (bump allocator)            │  │
│  │  Entries: [len:1cell][refcount:1cell][...]  │  │
│  ├───────────────────────────────────────────┤  │
│  │  Node pool (fixed 80-byte slots)           │  │
│  │  Free-list managed by DOM layer             │  │
│  ├───────────────────────────────────────────┤  │
│  │  Attr pool (fixed 24-byte slots)           │  │
│  │  Free-list managed by DOM layer             │  │
│  └───────────────────────────────────────────┘  │
│                                                  │
│  ARENA-DESTROY → all of the above freed at once  │
└─────────────────────────────────────────────────┘
```

### Multi-Document Support

```forth
\ Document A — a parsed webpage
524288 A-XMEM ARENA-NEW DROP CONSTANT page-arena
page-arena DOM-DOC-NEW  CONSTANT page-doc

\ Document B — a template
131072 A-XMEM ARENA-NEW DROP CONSTANT tmpl-arena
tmpl-arena DOM-DOC-NEW  CONSTANT tmpl-doc

\ Work with each independently
page-doc DOM-USE   ( ... parse, query, mutate page ... )
tmpl-doc DOM-USE   ( ... work with template ... )

\ Destroy document A — all nodes, strings, attrs gone in O(1)
page-arena ARENA-DESTROY
```

File: `utils/dom/dom.f`
Prefix: `DOM-` (public), `_DOM-` (internal)
Provider: `PROVIDED akashic-dom`
Dependencies: `REQUIRE ../css/bridge.f` (which chains html + css)

---

## Document Descriptor

The document descriptor is the first thing allocated from the arena.
It holds all per-document state.  All DOM words operate on the
"current document" set by `DOM-USE`.

### Layout (10 cells = 80 bytes)

```
Offset  Field            Purpose
  +0    arena            KDOS arena handle (for further allocation)
  +8    str-base         string region start address
 +16    str-ptr          string region bump pointer
 +24    str-end          string region end address
 +32    node-base        node pool start address
 +40    node-max         max number of nodes
 +48    node-free        head of node free-list (address, 0=empty)
 +56    attr-base        attr pool start address
 +64    attr-max         max number of attributes
 +72    attr-free        head of attr free-list (address, 0=empty)
```

---

## Layer 0 — String Pool

**Goal:** Owned, reference-counted string storage so DOM nodes can
hold copies of tag names, attribute values, and text content that
outlive the original source buffer.

### Design

- Sub-region of the document arena (carved out by `DOM-DOC-NEW`)
- Bump allocator within the string region (no arena overhead per string)
- Each string entry: `[len:1cell][refcount:1cell][bytes:len]`
- Strings are immutable once allocated; mutation = allocate new + release old
- Reference counting so multiple nodes can share the same string
- Handle = address of entry (not an index)
- Handle 0 = "no string" sentinel

**Note:** Individual string slots are NOT reused when released (bump-only).
Fragmentation is acceptable — `ARENA-DESTROY` reclaims all at once.
For mutation-heavy documents, size the string region generously.

### Words

| Word | Stack | Purpose |
|---|---|---|
| `_DOM-STR-ALLOC` | `( src-a src-u -- handle )` | Copy string into pool, return handle (refcount=1) |
| `_DOM-STR-GET` | `( handle -- addr len )` | Resolve handle to address+length |
| `_DOM-STR-REF` | `( handle -- )` | Increment reference count |
| `_DOM-STR-RELEASE` | `( handle -- )` | Decrement refcount (no slot reuse in v1) |
| `_DOM-STR-FREE?` | `( -- n )` | Bytes remaining in string region |

### Test targets: ~15 tests
- Alloc + get, release, ref counting, multiple strings, zero-length, pool exhaustion

---

## Layer 1 — Node Allocation

**Goal:** Fixed-size node pool with type tags, free-list for O(1)
alloc/free, all backed by the document's arena.

### Design

- Node pool slab allocated from arena by `DOM-DOC-NEW`
- Fixed-size node records (10 cells = 80 bytes each)
- Singly-linked free-list through the first cell of each free slot
- Node types: `DOM-T-ELEMENT`, `DOM-T-TEXT`, `DOM-T-COMMENT`,
  `DOM-T-DOCUMENT`, `DOM-T-FRAGMENT`

### Node Record Layout (10 cells = 80 bytes)

```
Offset  Size   Field
  +0     1cell  type          (element/text/comment/document/fragment)
  +8     1cell  flags         (dirty, detached, etc.)
 +16     1cell  parent        (node address, 0 = none)
 +24     1cell  first-child   (node address, 0 = none)
 +32     1cell  last-child    (node address, 0 = none)
 +40     1cell  next-sibling  (node address, 0 = none)
 +48     1cell  prev-sibling  (node address, 0 = none)
 +56     1cell  name-or-text  (string handle: tag name OR text content)
 +64     1cell  first-attr    (attr address, 0 = none)
 +72     1cell  aux           (style cache handle or other per-type data)
```

When a slot is free, `+0` holds the address of the next free slot
(or 0 for end of list).

### Words

| Word | Stack | Purpose |
|---|---|---|
| `DOM-DOC-NEW` | `( arena -- doc )` | Create document: carve arena into regions, return doc handle |
| `DOM-USE` | `( doc -- )` | Set current document for subsequent DOM operations |
| `DOM-DOC` | `( -- doc )` | Get current document handle |
| `_DOM-ALLOC` | `( type -- node )` | Allocate node from current doc's pool |
| `_DOM-FREE` | `( node -- )` | Return node to free-list (release strings) |
| `DOM-TYPE@` | `( node -- type )` | Get node type |
| `DOM-FLAGS@` | `( node -- flags )` | Get node flags |
| `DOM-FLAGS!` | `( flags node -- )` | Set node flags |

### Constants

| Constant | Value |
|---|---|
| `DOM-T-ELEMENT` | 1 |
| `DOM-T-TEXT` | 2 |
| `DOM-T-COMMENT` | 3 |
| `DOM-T-DOCUMENT` | 4 |
| `DOM-T-FRAGMENT` | 5 |
| `DOM-NODE-SIZE` | 80 |

### Test targets: ~15 tests
- DOC-NEW, alloc, free, reuse, type check, exhaust pool, multi-document

---

## Layer 2 — Tree Structure

**Goal:** Parent/child/sibling link management.  Doubly-linked child
lists for O(1) append and O(1) removal.

### Words

| Word | Stack | Purpose |
|---|---|---|
| `DOM-PARENT` | `( node -- parent \| 0 )` | Get parent node |
| `DOM-FIRST-CHILD` | `( node -- child \| 0 )` | Get first child |
| `DOM-LAST-CHILD` | `( node -- child \| 0 )` | Get last child |
| `DOM-NEXT` | `( node -- sibling \| 0 )` | Get next sibling |
| `DOM-PREV` | `( node -- sibling \| 0 )` | Get previous sibling |
| `DOM-APPEND` | `( child parent -- )` | Append child to parent's child list |
| `DOM-PREPEND` | `( child parent -- )` | Prepend child to parent's child list |
| `DOM-INSERT-BEFORE` | `( new ref -- )` | Insert new before ref in parent's list |
| `DOM-DETACH` | `( node -- )` | Remove from parent, fix sibling links |
| `DOM-CHILD-COUNT` | `( node -- n )` | Count children |

### Test targets: ~25 tests
- Append, prepend, insert-before, detach, traversal, edge cases (empty, single child, reattach)

---

## Layer 3 — Attribute Storage

**Goal:** Per-element attribute list (linked list of attr records).

### Design

- Attribute pool slab allocated from arena by `DOM-DOC-NEW`
- Fixed-size attr records (3 cells = 24 bytes each)
- Each attr: `[name-handle:1cell][value-handle:1cell][next-attr:1cell]`
- Free-list through first cell of free slots
- Case-insensitive name matching (HTML mode)

### Words

| Word | Stack | Purpose |
|---|---|---|
| `DOM-ATTR@` | `( node name-a name-u -- val-a val-u flag )` | Get attribute value |
| `DOM-ATTR!` | `( node name-a name-u val-a val-u -- )` | Set attribute (create or update) |
| `DOM-ATTR-DEL` | `( node name-a name-u -- )` | Remove attribute |
| `DOM-ATTR-HAS?` | `( node name-a name-u -- flag )` | Check if attribute exists |
| `DOM-ATTR-EACH` | `( node -- name-a name-u val-a val-u flag )` | Iterate attributes (call repeatedly) |
| `DOM-ID` | `( node -- str-a str-u )` | Shortcut: get id attribute |
| `DOM-CLASS` | `( node -- str-a str-u )` | Shortcut: get class attribute |
| `DOM-CLASS-HAS?` | `( node cls-a cls-u -- flag )` | Check for class |

### Test targets: ~20 tests
- Set, get, update, delete, iterate, case-insensitive

---

## Layer 4 — Mutation

**Goal:** High-level tree mutation with automatic string management.

### Words

| Word | Stack | Purpose |
|---|---|---|
| `DOM-CREATE-ELEMENT` | `( tag-a tag-u -- node )` | Create element node with tag name |
| `DOM-CREATE-TEXT` | `( txt-a txt-u -- node )` | Create text node |
| `DOM-CREATE-COMMENT` | `( txt-a txt-u -- node )` | Create comment node |
| `DOM-CREATE-FRAGMENT` | `( -- node )` | Create document fragment |
| `DOM-CLONE` | `( node deep? -- new-node )` | Clone node (shallow or deep) |
| `DOM-REMOVE` | `( node -- )` | Detach and free node (deep: frees subtree) |
| `DOM-TAG-NAME` | `( node -- name-a name-u )` | Get element's tag name |
| `DOM-TEXT` | `( node -- txt-a txt-u )` | Get text/comment content |
| `DOM-SET-TEXT` | `( node txt-a txt-u -- )` | Set text/comment content |
| `DOM-INNER-TEXT` | `( node buf max -- n )` | Collect all text descendants into buffer |

### Test targets: ~20 tests
- Create all types, clone shallow/deep, remove subtree, tag-name, text get/set

---

## Layer 5 — Style Resolution

**Goal:** Compute applied styles for an element by combining
stylesheet rules, inherited styles, and inline styles.

### Design

Leverages existing `akashic-css-bridge`:
- `CSSB-APPLY-INLINE` collects matching rules + inline `style=""`
- This layer adds **inheritance** (certain properties inherit from parent)
- And **default values** (display: inline for `<span>`, block for `<div>`, etc.)

### Words

| Word | Stack | Purpose |
|---|---|---|
| `DOM-SET-STYLESHEET` | `( css-a css-u -- )` | Set the document's stylesheet |
| `DOM-COMPUTE-STYLE` | `( node buf max -- n )` | Compute applied styles for node |
| `DOM-STYLE@` | `( node prop-a prop-u -- val-a val-u flag )` | Get computed property value |
| `DOM-STYLE-CACHED?` | `( node -- flag )` | Is computed style cached? |
| `DOM-INVALIDATE-STYLE` | `( node -- )` | Mark style cache dirty (propagate to children) |

### Inheritable properties (initial set)
`color`, `font-family`, `font-size`, `font-style`, `font-weight`,
`line-height`, `text-align`, `visibility`, `cursor`, `direction`,
`letter-spacing`, `word-spacing`, `white-space`, `list-style-type`

### Test targets: ~20 tests
- Single rule, multiple rules, inheritance, inline override, cache invalidation, default display values

---

## Layer 6 — Query & Traversal

**Goal:** CSS-selector-based element queries and tree walkers.

### Words

| Word | Stack | Purpose |
|---|---|---|
| `DOM-QUERY` | `( root sel-a sel-u -- node \| 0 )` | Find first matching element (depth-first) |
| `DOM-QUERY-ALL` | `( root sel-a sel-u buf max -- n )` | Find all matching, store in buf, return count |
| `DOM-GET-BY-ID` | `( root id-a id-u -- node \| 0 )` | Find element by id |
| `DOM-GET-BY-TAG` | `( root tag-a tag-u buf max -- n )` | Find elements by tag name |
| `DOM-GET-BY-CLASS` | `( root cls-a cls-u buf max -- n )` | Find elements by class |
| `DOM-WALK-DEPTH` | `( root xt -- )` | Depth-first walk, call xt for each node |
| `DOM-NTH-CHILD` | `( parent n -- node \| 0 )` | Get nth child (0-based) |
| `DOM-MATCHES?` | `( node sel-a sel-u -- flag )` | Does this node match selector? |

### Test targets: ~25 tests
- Query by type/id/class/compound, query-all, walk, nth-child, no-match, nested

---

## Layer 7 — Serialisation

**Goal:** Render a DOM tree back to HTML text.

### Words

| Word | Stack | Purpose |
|---|---|---|
| `DOM-TO-HTML` | `( node buf max -- n )` | Serialise subtree to HTML text |
| `DOM-OUTER-HTML` | `( node buf max -- n )` | Serialise including the node's own tag |
| `DOM-INNER-HTML` | `( node buf max -- n )` | Serialise children only |
| `DOM-SET-INNER-HTML` | `( node html-a html-u -- )` | Parse HTML and replace children |

### Design

- Uses the existing `akashic-html` builder for escaping and void-element handling
- Walks the DOM tree depth-first
- For each element: emit open tag + attributes, recurse children, emit close tag
- Text nodes: entity-escape and emit
- Comment nodes: emit `<!-- ... -->`

### Test targets: ~15 tests
- Single element, nested, attributes, text escaping, void elements, round-trip (parse → DOM → serialise → compare)

---

## Parser (Layer 0.5) — HTML → DOM

Before any of the upper layers are useful, we need to parse HTML text
into a DOM tree.  This isn't a separate "layer" — it's a bootstrapping
word that uses Layers 0–4.

### Words

| Word | Stack | Purpose |
|---|---|---|
| `DOM-PARSE-HTML` | `( html-a html-u -- root )` | Parse HTML into a DOM tree, return document root |
| `DOM-PARSE-FRAGMENT` | `( html-a html-u parent -- )` | Parse HTML and append as children of parent |

### Design

- Walk the HTML with `MU-NEXT-TAG` / `MU-TAG-TYPE`
- For each open tag: create element, extract attributes, push onto stack
- For each close tag: pop stack
- For text between tags: create text node
- Void elements: create + close immediately (no push)
- Uses the existing `akashic-html` void-element and raw-text awareness
- **Transactional:** `ARENA-SNAP` before parse, `ARENA-ROLLBACK` on failure

### Test targets: ~15 tests
- Simple element, nested, attributes, text nodes, void elements, raw text, deep nesting

---

## Stage Plan

Each stage = implement one layer, write tests, commit.

| Stage | Layer | File(s) | Est. Lines | Est. Tests | Dependencies |
|---|---|---|---|---|---|
| 1 | L0: String Pool + Doc Init | `dom.f` | ~80 | ~15 | Arena API |
| 2 | L1: Node Allocation | `dom.f` | ~80 | ~15 | L0 |
| 3 | L2: Tree Structure | `dom.f` | ~120 | ~25 | L1 |
| 4 | L3: Attribute Storage | `dom.f` | ~130 | ~20 | L0, L1, L2 |
| 5 | Parser: HTML → DOM | `dom.f` | ~150 | ~15 | L0–L3, html.f |
| 6 | L4: Mutation | `dom.f` | ~100 | ~20 | L0–L3 |
| 7 | L5: Style Resolution | `dom.f` | ~120 | ~20 | L0–L4, bridge.f |
| 8 | L6: Query & Traversal | `dom.f` | ~130 | ~25 | L0–L4, bridge.f |
| 9 | L7: Serialisation | `dom.f` | ~100 | ~15 | L0–L4, html.f builder |
| 10 | Documentation | `docs/utils/dom/dom.md` | — | — | — |
| | **Totals** | | **~1010** | **~170** | |

---

## Memory Budget

Assuming 16 MiB extended memory, per document:

| Component | Size | Notes |
|---|---|---|
| Doc descriptor | 80 B | 10 cells |
| String region | 256 KiB | ~10K short strings (bump-only) |
| Node pool | 160 KiB | 2048 nodes × 80 bytes |
| Attribute pool | 48 KiB | 2048 attrs × 24 bytes |
| **Per-document total** | **~464 KiB** | |
| Output/scratch buffers | 64 KiB | serialisation, style collection (shared) |
| Library code | ~70 KiB | all layers compiled in userland |
| **System total** | **~598 KiB** | < 4% of ext memory; room for 30+ documents |

---

## Design Decisions & Rationale

### Why KDOS arenas instead of a custom allocator?

KDOS already has a fully tested arena allocator (33 tests) supporting
three memory regions (HEAP, XMEM, HBW), snapshots, and scoped stacks.
Building a custom bump allocator would duplicate this.  Using arenas
also gives us multi-document support and O(1) document teardown for
free.

### Why free-lists on top of arenas?

Arenas are bump-only — no per-object deallocation.  DOM nodes need
individual free/reuse (e.g., remove a `<div>`, reuse the slot).  The
solution: arena allocates the raw slab, DOM manages a singly-linked
free-list of fixed-size slots within it.  Only ~10 extra lines of code.
`ARENA-DESTROY` still works for bulk teardown (bypasses free-lists).

### Why string handles instead of raw pointers?

Source HTML may be in transient buffers (UART input, network packets).
DOM nodes need owned copies that outlive the source.  Handles enable
reference counting so shared strings (common attribute values) aren't
duplicated.

### Why single-file `dom.f`?

All layers share internal data structures (node/attr records, pools).
Splitting into separate files would require cross-file variable access
and complicate REQUIRE ordering.  A single file with clear layer
sections (matching the existing `css.f` pattern) keeps things simple.

### Why no virtual dispatch / node type polymorphism?

KDOS has no `DEFER`/`IS`.  Type dispatch is done with `CASE` or
chained `IF` on the node type field.  With only 5 node types this is
fast and clear.

### Why 80-byte nodes?

64-bit cells mean each field is 8 bytes.  A node needs 10 logical
fields (type, flags, parent, first-child, last-child, next-sibling,
prev-sibling, name-or-text, first-attr, aux).  10 × 8 = 80 bytes.
Using sub-cell packing would save space but add complexity for
bit-shifting on every access.

---

## KDOS Arena API Reference (for DOM implementor)

| Word | Stack | What it does |
|---|---|---|
| `ARENA-NEW` | `( size source -- arena ior )` | Create arena (A-HEAP / A-XMEM / A-HBW) |
| `ARENA-ALLOT` | `( arena u -- addr )` | Bump-allocate u bytes (8-aligned) |
| `ARENA-ALLOT?` | `( arena u -- addr ior )` | Non-aborting variant |
| `ARENA-RESET` | `( arena -- )` | Rewind to empty (O(1) bulk free) |
| `ARENA-DESTROY` | `( arena -- )` | Free backing + zero descriptor |
| `ARENA-SNAP` | `( arena -- snap )` | Save bump pointer |
| `ARENA-ROLLBACK` | `( arena snap -- )` | Restore bump pointer |
| `ARENA-USED` | `( arena -- u )` | Bytes consumed |
| `ARENA-FREE` | `( arena -- u )` | Bytes remaining |

---

## Risk Assessment

| Risk | Impact | Mitigation |
|---|---|---|
| Dictionary full (RAM) | Blocks compilation | Use `ENTER-USERLAND` (already working) |
| Pool exhaustion | Can't create more nodes | Pre-size pools generously; `_DOM-FREE` reclaims |
| String region exhaustion | Can't store more text | Size generously; ARENA-DESTROY reclaims all |
| Stack depth during deep parse | Stack overflow on malformed HTML | Limit nesting depth; iterative where possible |
| Slow style resolution | Quadratic if naive | Cache computed styles; invalidate on mutation |
| Test suite runtime | 5+ minutes already | Snapshot approach (already working); maybe split test files |
| Arena not available | No arena words in KDOS | KDOS arenas fully implemented (33 tests, 4 phases) |

---

## Future Extensions (Post-v1)

These are explicitly **not** in scope for the initial build but worth
noting for later:

- **Event system** — attach/dispatch event handlers to nodes
- **Layout engine** — box model calculation (width, height, margin, padding)
- **Rendering pipeline** — paint DOM to framebuffer
- **Virtual DOM / diffing** — efficient incremental updates
- **XPath or advanced selectors** — `:nth-child()`, `:not()`, attribute selectors with operators
- **String pool compaction** — defragment after many alloc/free cycles
- **Shadow DOM** — encapsulated subtrees
- **Template engine** — data-driven DOM construction from JSON + template
- **String slot reuse** — free-list by size class for released strings
