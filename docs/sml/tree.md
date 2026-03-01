# akashic-sml-tree — SOM Tree for KDOS / Megapad-64

DOM-backed tree plus the Sequential Object Model (SOM) cursor,
focus stack, and input context — the runtime navigation layer for
1D user interfaces.

Reuses the arena-backed DOM from `dom/dom.f` for node storage and
adds a 448-byte SOM extension block per document for cursor state,
a 16-frame focus stack, and input-context fields.

```forth
REQUIRE sml/tree.f
```

`PROVIDED akashic-sml-tree` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Dependencies](#dependencies)
- [Architecture](#architecture)
- [Tree Handle](#tree-handle)
- [SML Type Encoding](#sml-type-encoding)
- [Tree Creation / Destruction](#tree-creation--destruction)
- [SML-LOAD — Parse Markup into Tree](#sml-load--parse-markup-into-tree)
- [DFS Navigation](#dfs-navigation)
- [Node Queries](#node-queries)
- [Node Mutation](#node-mutation)
- [Cursor Read API](#cursor-read-api)
- [Cursor Movement](#cursor-movement)
- [Focus Stack](#focus-stack)
- [Input Context](#input-context)
- [Convenience](#convenience)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **DOM reuse** | Nodes live in the existing arena-backed DOM (80-byte records, node/attr free-lists, interned strings). No parallel tree. |
| **SML type in DOM flags** | 5-bit SML element type stored in DOM `N.FLAGS` bits 8–12 — zero new per-node cost. |
| **Single extension block** | All SOM state (cursor, focus stack, input context) in one 448-byte arena allocation alongside the DOM document. |
| **Factored DFS** | All depth-first walks share `_DFS-UP`, a helper word where `EXIT` correctly returns to the caller rather than prematurely exiting the outer DFS loop. |
| **Scope-local cursor** | `SOM-NEXT`/`SOM-PREV` walk direct children of the current scope — not the full DFS — matching the SOM spec's scope-bounded navigation. |
| **Prefix convention** | `SML-` for tree API, `SOM-` for cursor/focus/context API, `_SML-`/`_SOM-` for internals. |
| **Not re-entrant** | Module-scoped VARIABLEs for DFS state. One active tree at a time via `SML-TREE-USE`. |

---

## Dependencies

```forth
REQUIRE core.f          \ SML-TYPE?, SML-POSITION?, SML-SCOPE?, etc.
REQUIRE ../dom/dom.f    \ DOM-DOC-NEW, DOM-PARSE-HTML, DOM-CREATE-ELEMENT, etc.
```

Transitively depends on `markup/core.f`, `markup/html.f`,
`css/bridge.f`, `text/utf8.f`, and `utils/string.f`.

---

## Architecture

### SOM Extension Block (448 bytes)

Allocated from the same arena as the DOM, **before** `DOM-DOC-NEW`
(because `DOM-DOC-NEW` claims all remaining arena space for the
string pool).

| Section | Offset | Size | Description |
|---|---|---|---|
| **Cursor** | +0 | 32 B | `current`, `scope`, `position`, `at-boundary` |
| **FocusStack** | +32 | 392 B | `depth` (1 cell) + 16 frames × 24 B |
| **InputContext** | +424 | 24 B | `state`, `target`, `value` |

#### Cursor Fields

| Accessor | Offset | Description |
|---|---|---|
| `SX.CURRENT` | +0 | Current node address (0 = none) |
| `SX.SCOPE` | +8 | Scope node address |
| `SX.POSITION` | +16 | Zero-based index in scope |
| `SX.AT-BOUND` | +24 | 0=none, 1=first, 2=last |

#### Focus Frame (24 bytes each)

| Accessor | Offset | Description |
|---|---|---|
| `SF.SCOPE` | +0 | Scope node address |
| `SF.SAVED-POS` | +8 | Last cursor position (-1 = none) |
| `SF.RESUME` | +16 | Resume policy (0=first, 1=last, 2=none) |

### Tree Handle (16 bytes)

| Accessor | Offset | Description |
|---|---|---|
| `T.DOC` | +0 | DOM document descriptor address |
| `T.EXT` | +8 | SOM extension block address |

---

## Tree Handle

| Word | Stack | Description |
|---|---|---|
| `SML-TREE-USE` | `( tree -- )` | Set tree as active |
| `SML-TREE` | `( -- tree )` | Return active tree handle |

---

## SML Type Encoding

SML element types from `core.f` are stored in bits 8–12 of the
DOM node's `N.FLAGS` field (5-bit field, shift 8, mask 31).

| Word | Stack | Description |
|---|---|---|
| `SML-NODE-TYPE@` | `( node -- sml-type )` | Read SML type from flags |

Internal: `_SML-SET-TYPE ( sml-type node -- )`.

---

## Tree Creation / Destruction

| Word | Stack | Description |
|---|---|---|
| `SML-TREE-CREATE` | `( -- tree )` | Allocate arena (256 KB XMEM), tree handle, SOM extension block, and DOM document (256 nodes, 512 attrs). Sets tree + DOM as active. |
| `SML-TREE-DESTROY` | `( tree -- )` | Destroy the backing arena. |

---

## SML-LOAD — Parse Markup into Tree

| Word | Stack | Description |
|---|---|---|
| `SML-LOAD` | `( a u tree -- )` | Parse SML string via `DOM-PARSE-HTML`, then DFS-tag every element node with its SML type (via `SML-TYPE?`). |

---

## DFS Navigation

Global depth-first traversal across the entire tree, landing only
on **position** elements (elements where `SML-POSITION?` is true
and `hidden="true"` is absent).

| Word | Stack | Description |
|---|---|---|
| `SML-FIRST` | `( tree -- node\|0 )` | First navigable node in DFS order |
| `SML-LAST` | `( tree -- node\|0 )` | Last navigable node in DFS order |
| `SML-NEXT` | `( node tree -- node'\|0 )` | Next navigable after given node |
| `SML-PREV` | `( node tree -- node'\|0 )` | Previous navigable before given node |

All four set the active tree and DOM before walking.

### Helper: `_DFS-UP`

| Word | Stack | Description |
|---|---|---|
| `_DFS-UP` | `( cur root -- next\|0 )` | Walk parent chain from `cur` until a sibling is found. Return the sibling or 0 if root is reached. |

Factored into its own word so that `EXIT` returns to the DFS
caller — not prematurely from the outermost word.

---

## Node Queries

| Word | Stack | Description |
|---|---|---|
| `SML-NODE@` | `( node tree -- addr )` | Node descriptor address (identity in this impl) |
| `SML-JUMP?` | `( node tree -- flag )` | True if node is a scope with `jump="true"` |
| `SML-CHILDREN` | `( scope tree -- n )` | Count navigable + enterable direct children |

### Internal Predicates

| Word | Stack | Description |
|---|---|---|
| `_SML-NODE-NAVIGABLE?` | `( node -- flag )` | Position element, not hidden |
| `_SML-NODE-SCOPE?` | `( node -- flag )` | Scope element (seq/ring/gate/trap) |
| `_SML-NODE-ENTERABLE?` | `( node -- flag )` | Scope element, not hidden |
| `_SML-NODE-HIDDEN?` | `( node -- flag )` | Has `hidden="true"` attribute |

---

## Node Mutation

| Word | Stack | Description |
|---|---|---|
| `SML-NODE-ADD` | `( parent kind-a kind-u label-a label-u -- node )` | Create an element, tag with SML type, set label attr if non-empty, append to parent |
| `SML-NODE-REMOVE` | `( node tree -- )` | Detach node and its subtree |
| `SML-PATCH` | `( op-a op-u tree -- )` | **Stub** — placeholder for Layer 3 mutations |

---

## Cursor Read API

All read words accept the tree handle and return current cursor
state from the SOM extension block.

| Word | Stack | Description |
|---|---|---|
| `SOM-CURRENT` | `( tree -- node\|0 )` | Current cursor node |
| `SOM-SCOPE` | `( tree -- scope\|0 )` | Current scope node |
| `SOM-POSITION` | `( tree -- n )` | Zero-based index in scope |
| `SOM-AT-BOUNDARY` | `( tree -- bound )` | 0=none, 1=first, 2=last |

### Boundary Constants

| Constant | Value |
|---|---|
| `SOM-BOUND-NONE` | 0 |
| `SOM-BOUND-FIRST` | 1 |
| `SOM-BOUND-LAST` | 2 |

---

## Cursor Movement

### SOM-NEXT / SOM-PREV (scope-local)

| Word | Stack | Description |
|---|---|---|
| `SOM-NEXT` | `( tree -- moved? )` | Move to next navigable sibling within scope. In a ring, wraps to first. In seq/gate/trap, sets boundary=LAST at end. |
| `SOM-PREV` | `( tree -- moved? )` | Move to previous. Ring wraps to last. Seq/gate/trap sets boundary=FIRST. |

### SOM-ENTER / SOM-BACK (scope depth)

| Word | Stack | Description |
|---|---|---|
| `SOM-ENTER` | `( tree -- moved? )` | Enter the scope at cursor. Pushes focus frame, moves cursor to first child. Sets `ctx=MENU` for ring, `ctx=TRAPPED` for trap. |
| `SOM-BACK` | `( tree -- moved? )` | Exit current scope (denied in trap). Pops focus frame, lands on scope element in parent. Resets context to NAV. |

### SOM-JUMP

| Word | Stack | Description |
|---|---|---|
| `SOM-JUMP` | `( id-a id-u tree -- moved? )` | Jump cursor to element with given `id` attribute. Uses `DOM-GET-BY-ID`. |

---

## Focus Stack

16-frame stack tracking scope nesting.

| Word | Stack | Description |
|---|---|---|
| `SOM-FS-DEPTH` | `( tree -- n )` | Current focus stack depth |

Internal: `_SOM-FS-PUSH`, `_SOM-FS-POP`, `_SOM-FS-PEEK`,
`_SOM-FS-UPDATE-POS`.

### Resume Policies

| Constant | Value | Meaning |
|---|---|---|
| `SOM-RESUME-FIRST` | 0 | Resume at first child on re-entry |
| `SOM-RESUME-LAST` | 1 | Resume at last position (default) |
| `SOM-RESUME-NONE` | 2 | No resume — start fresh |

---

## Input Context

The input context tracks the interaction mode (navigation, text
editing, slider, cycling, menu, trapped).

| Word | Stack | Description |
|---|---|---|
| `SOM-CTX@` | `( tree -- state )` | Current context state |
| `SOM-CTX-ENTER` | `( target state tree -- )` | Transition to new context |
| `SOM-CTX-EXIT` | `( tree -- )` | Return to NAV context |
| `SOM-CTX-TARGET` | `( tree -- node\|0 )` | Context target element |
| `SOM-CTX-VALUE` | `( tree -- val )` | Context edit value |
| `SOM-CTX-SET-VALUE` | `( val tree -- )` | Set context edit value |

### Context State Constants

| Constant | Value | Meaning |
|---|---|---|
| `SOM-CTX-NAV` | 0 | Navigation mode |
| `SOM-CTX-TEXT` | 1 | Text editing |
| `SOM-CTX-SLIDER` | 2 | Slider adjustment |
| `SOM-CTX-CYCLING` | 3 | Cycle selection |
| `SOM-CTX-MENU` | 4 | Menu navigation (ring scope) |
| `SOM-CTX-TRAPPED` | 5 | Trapped (trap scope) |

---

## Convenience

| Word | Stack | Description |
|---|---|---|
| `SML-INIT` | `( sml-a sml-u -- tree )` | Create tree, load markup, initialize cursor. Returns tree handle. |

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `SML-TREE-CREATE` | `( -- tree )` | New tree + arena |
| `SML-TREE-DESTROY` | `( tree -- )` | Destroy arena |
| `SML-TREE-USE` | `( tree -- )` | Set active tree |
| `SML-TREE` | `( -- tree )` | Get active tree |
| `SML-LOAD` | `( a u tree -- )` | Parse + tag |
| `SML-NODE-TYPE@` | `( node -- type )` | Read SML type |
| `SML-FIRST` | `( tree -- node\|0 )` | First DFS |
| `SML-LAST` | `( tree -- node\|0 )` | Last DFS |
| `SML-NEXT` | `( node tree -- node'\|0 )` | Next DFS |
| `SML-PREV` | `( node tree -- node'\|0 )` | Prev DFS |
| `SML-JUMP?` | `( node tree -- flag )` | Has jump attr |
| `SML-CHILDREN` | `( scope tree -- n )` | Nav child count |
| `SML-NODE-ADD` | `( par ka ku la lu -- node )` | Add element |
| `SML-NODE-REMOVE` | `( node tree -- )` | Detach node |
| `SOM-CURRENT` | `( tree -- node\|0 )` | Cursor node |
| `SOM-SCOPE` | `( tree -- scope\|0 )` | Cursor scope |
| `SOM-POSITION` | `( tree -- n )` | Cursor index |
| `SOM-AT-BOUNDARY` | `( tree -- bound )` | Boundary flag |
| `SOM-NEXT` | `( tree -- moved? )` | Scope-local next |
| `SOM-PREV` | `( tree -- moved? )` | Scope-local prev |
| `SOM-ENTER` | `( tree -- moved? )` | Enter scope |
| `SOM-BACK` | `( tree -- moved? )` | Exit scope |
| `SOM-JUMP` | `( id-a id-u tree -- moved? )` | Jump by id |
| `SOM-FS-DEPTH` | `( tree -- n )` | Focus depth |
| `SOM-CTX@` | `( tree -- state )` | Context state |
| `SOM-CTX-ENTER` | `( target state tree -- )` | Set context |
| `SOM-CTX-EXIT` | `( tree -- )` | NAV context |
| `SOM-CTX-TARGET` | `( tree -- node\|0 )` | Context target |
| `SOM-CTX-VALUE` | `( tree -- val )` | Context value |
| `SOM-CTX-SET-VALUE` | `( val tree -- )` | Set ctx value |
| `SML-PATCH` | `( op-a op-u tree -- )` | Mutation stub |
| `SML-INIT` | `( sml-a sml-u -- tree )` | Create + load + init |

---

## Cookbook

### Load and navigate a simple menu

```forth
S" <sml><seq><item/><act/><val/></seq></sml>"  SML-INIT
CONSTANT MY-TREE

MY-TREE SOM-CURRENT DOM-TAG-NAME TYPE   \ prints "item"
MY-TREE SOM-NEXT DROP
MY-TREE SOM-CURRENT DOM-TAG-NAME TYPE   \ prints "act"
```

### Enter a nested scope

```forth
S" <sml><seq><seq><item/><act/></seq></seq></sml>"  SML-INIT
CONSTANT MY-TREE

MY-TREE SOM-ENTER DROP    \ enter inner <seq>
MY-TREE SOM-SCOPE         \ inner <seq> node
MY-TREE SOM-FS-DEPTH .    \ 2
MY-TREE SOM-BACK DROP     \ return to outer scope
```

### DFS traversal over all navigable nodes

```forth
S" <sml><seq><item/><act/><val/></seq></sml>"  SML-INIT
CONSTANT MY-TREE

MY-TREE SML-FIRST
BEGIN DUP WHILE
    DUP DOM-TAG-NAME TYPE SPACE
    MY-TREE SML-NEXT
REPEAT DROP
\ Output: item act val
```

### Jump to element by id

```forth
S" <sml><seq><item id=\"a\"/><act id=\"b\"/></seq></sml>"
SML-INIT  CONSTANT MY-TREE

S" b" MY-TREE SOM-JUMP .    \ -1  (moved)
MY-TREE SOM-CURRENT DOM-TAG-NAME TYPE  \ prints "act"
```
