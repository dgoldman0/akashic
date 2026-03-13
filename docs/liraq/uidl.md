# UIDL — LIRAQ Document Model

**Module:** `akashic-uidl`  
**File:** `akashic/liraq/uidl.f`  
**Companion:** `akashic/liraq/uidl-chrome.f` (chrome element registrations)  
**Requires:** `akashic-string`, `akashic-markup-core`, `akashic-xml`, `akashic-lel`, `akashic-state-tree`

## Overview

The UIDL Document Model implements LIRAQ Spec §02 — parsing UIDL XML
documents into a static-pool semantic element tree.  UIDL (Universal
Interface Description Language) describes user interfaces as a tree of
typed, attributed elements with no visual or auditory bias.

The parser accepts UIDL XML text (addr len), validates it, and builds an
in-memory tree of element nodes with:

- **Extensible Element Registry** — open hash-table of element definitions;
  any code can register new element types at load time via `DEFINE-ELEMENT`
- **21 built-in element types** — structural, content, interactive,
  collection, and pseudo-type primitives (type-ids 1–21)
- **21 chrome elements** registered by `uidl-chrome.f` — menubar, tabs,
  dialog, toast, textarea, dropdown, toolbar, etc.
- **6 arrangement modes** — none, dock, flex, stack, flow, grid
- **Per-element attribute linked lists** — generic key/value pairs
- **FNV-1a hashed ID registry** — O(1) element lookup by ID
- **Data binding and conditional display** — `bind` and `when` expressions
  evaluated via LEL against the state tree
- **Subscription table** — maps state-tree paths to elements; `UIDL-NOTIFY`
  marks subscribers dirty for incremental repaint
- **Dirty flag tracking** — per-element `UIDL-F-DIRTY` bit for efficient
  change propagation

All string data (IDs, roles, attribute names/values) is copied into a
dedicated string pool.  Element and attribute nodes are allocated from
fixed-size static pools — no heap allocation is used.

## Public API

### Parsing

#### UIDL-PARSE
```forth
UIDL-PARSE ( xml-a xml-l -- flag )
```
Parse a UIDL XML document.  Calls `UIDL-RESET` internally, then parses
the document into the element pool.  Returns `-1` on success, `0` on
error (check `UIDL-ERR` for the error code).

The root element must be `<uidl>`.

#### UIDL-RESET
```forth
UIDL-RESET ( -- )
```
Clear all pools and reset state.  Called automatically by `UIDL-PARSE`.

### Document Queries

#### UIDL-ROOT
```forth
UIDL-ROOT ( -- elem | 0 )
```
Return the root `<uidl>` element, or 0 if no document is loaded.

#### UIDL-BY-ID
```forth
UIDL-BY-ID ( id-a id-l -- elem | 0 )
```
Look up an element by its `id` attribute.  Uses the FNV-1a hash table
for O(1) average-case lookup.  Returns 0 if the ID is not found.

#### UIDL-ELEM-COUNT
```forth
UIDL-ELEM-COUNT ( -- n )
```
Total number of allocated element nodes.

#### UIDL-ERR
```forth
UIDL-ERR ( -- code )
```
Return the current error code (0 = OK).

### Element Properties

#### UIDL-TYPE
```forth
UIDL-TYPE ( elem -- type )
```
Element type constant (see Element Types below).

#### UIDL-TYPE-NAME
```forth
UIDL-TYPE-NAME ( type -- a l )
```
Convert a type constant to its human-readable name string.
Returns `"unknown"` for out-of-range values.

#### UIDL-ID
```forth
UIDL-ID ( elem -- a l )
```
Element's `id` string.  Returns `( 0 0 )` if no ID was set.

#### UIDL-ROLE
```forth
UIDL-ROLE ( elem -- a l )
```
Element's `role` string.  Returns `( 0 0 )` if no role was set.

#### UIDL-ARRANGE
```forth
UIDL-ARRANGE ( elem -- mode )
```
Element's arrangement mode constant (see Arrangement Modes below).

#### UIDL-FLAGS
```forth
UIDL-FLAGS ( elem -- flags )
```
Element's flag bit field.  See Element Flags below.

#### UIDL-BIND
```forth
UIDL-BIND ( elem -- a l flag )
```
Return the element's data binding expression.  Leading `=` is stripped.
Returns `( expr-a expr-l -1 )` if present, `( 0 0 0 )` if absent.

#### UIDL-WHEN
```forth
UIDL-WHEN ( elem -- a l flag )
```
Return the element's `when` condition expression.  Leading `=` is
stripped.  Returns `( expr-a expr-l -1 )` if present, `( 0 0 0 )` if
absent.

### Tree Traversal

#### UIDL-PARENT
```forth
UIDL-PARENT ( elem -- p | 0 )
```

#### UIDL-FIRST-CHILD
```forth
UIDL-FIRST-CHILD ( elem -- c | 0 )
```

#### UIDL-LAST-CHILD
```forth
UIDL-LAST-CHILD ( elem -- c | 0 )
```

#### UIDL-NEXT-SIB
```forth
UIDL-NEXT-SIB ( elem -- s | 0 )
```

#### UIDL-PREV-SIB
```forth
UIDL-PREV-SIB ( elem -- s | 0 )
```

#### UIDL-NCHILDREN
```forth
UIDL-NCHILDREN ( elem -- n )
```
Number of direct children.

### Generic Attributes

Special attributes (`id`, `role`, `arrange`, `bind`, `xmlns`) are parsed
into dedicated element fields.  All other attributes are stored in a
per-element singly-linked list accessible through these words.

#### UIDL-ATTR
```forth
UIDL-ATTR ( elem na nl -- va vl flag )
```
Look up a generic attribute by name.  Returns `( val-a val-l -1 )` if
found, `( 0 0 0 )` if not found.

#### UIDL-ATTR-FIRST
```forth
UIDL-ATTR-FIRST ( elem -- attr | 0 )
```
Head of the attribute linked list for manual iteration.

#### UIDL-ATTR-NEXT
```forth
UIDL-ATTR-NEXT ( attr -- next | 0 )
```

#### UIDL-ATTR-NAME
```forth
UIDL-ATTR-NAME ( attr -- a l )
```

#### UIDL-ATTR-VAL
```forth
UIDL-ATTR-VAL ( attr -- a l )
```

### Binding & When Evaluation

These words integrate with LEL and the state tree to evaluate
expressions at runtime.

#### UIDL-BIND-EVAL
```forth
UIDL-BIND-EVAL ( elem -- type v1 v2 )
```
Evaluate the element's `bind` expression via `LEL-EVAL`.  Returns
`( ST-T-NULL 0 0 )` if no binding is present.

#### UIDL-EVAL-WHEN
```forth
UIDL-EVAL-WHEN ( elem -- flag )
```
Evaluate the element's `when` condition.  Returns `-1` (true) if no
condition is present, or the boolean result of the expression.
Integer/string results are coerced to boolean (non-zero/non-empty = true).
Null always yields false.

### Collection Helpers

#### UIDL-TEMPLATE
```forth
UIDL-TEMPLATE ( coll -- template | 0 )
```
Find the `<template>` child of a `<collection>` element.

#### UIDL-EMPTY-CHILD
```forth
UIDL-EMPTY-CHILD ( coll -- empty | 0 )
```
Find the `<empty>` child of a `<collection>` element.

### Representation Set Helpers

#### UIDL-REP-COUNT
```forth
UIDL-REP-COUNT ( media -- n )
```
Count the number of `<rep>` children in a `<media>` element.

#### UIDL-REP-BY-MOD
```forth
UIDL-REP-BY-MOD ( media mod-a mod-l -- rep | 0 )
```
Find a `<rep>` child whose `modality` attribute matches the given string.
Returns the rep element, or 0 if not found.

### Document Validation

#### UIDL-VALIDATE
```forth
UIDL-VALIDATE ( -- n-errors )
```
Scan all allocated elements and check validation rules.  Up to 16 errors
are stored in an internal buffer.  Returns the number of errors found.

**Rules checked:**
| Rule | Description |
|------|-------------|
| 2 | ID format: `[a-z][a-z0-9-]*`, max 64 characters |
| 3 | Bind path: dot-separated `[a-z_][a-z0-9_.]*` |
| 4 | When expression: must parse without LEL error |
| 5 | Collection elements must have a `<template>` child |
| 7 | Arrange value in range 0–5 |
| 8 | `on-activate` and `emit` are mutually exclusive |
| 10 | Root must be `<uidl>` |

#### UIDL-ERROR-COUNT
```forth
UIDL-ERROR-COUNT ( -- n )
```
Return the current number of validation errors.

#### UIDL-ERROR-NTH
```forth
UIDL-ERROR-NTH ( n -- rule elem )
```
Return the rule number and element address of the nth error (0-based).
Returns `0 0` if `n` is out of range.

#### UIDL-ERRORS-CLEAR
```forth
UIDL-ERRORS-CLEAR ( -- )
```
Clear the error buffer and reset the error count to zero.

### Document Mutation

#### UIDL-ADD-ELEM
```forth
UIDL-ADD-ELEM ( parent type -- new-elem | 0 )
```
Allocate a new element of the given type and link it as the last child
of `parent`.  Returns the element address, or 0 if the pool is full.

#### UIDL-REMOVE-ELEM
```forth
UIDL-REMOVE-ELEM ( elem -- )
```
Recursively remove an element and all its children.  Unlinks from the
parent's child chain and zeroes the element slots.

#### UIDL-SET-ATTR
```forth
UIDL-SET-ATTR ( elem name-a name-l val-a val-l -- )
```
Set an attribute on an element.  If an attribute with the same name
already exists, its value is overwritten.  Otherwise a new attribute is
created via the attribute pool.  Both name and value are copied to the
string pool.

#### UIDL-REMOVE-ATTR
```forth
UIDL-REMOVE-ATTR ( elem name-a name-l -- )
```
Remove the named attribute from the element's attribute chain.  No-op
if the attribute is not found.

#### UIDL-MOVE-ELEM
```forth
UIDL-MOVE-ELEM ( elem new-parent -- )
```
Unlink an element from its current parent and re-link it as the last
child of `new-parent`.

### Bind Write-Back

#### UIDL-BIND-WRITE
```forth
UIDL-BIND-WRITE ( elem value-a value-l -- )
```
Write a value back to the state tree through the element's bind path.
The write strategy depends on the element type:

| Type | State tree operation |
|------|---------------------|
| Toggle | `ST-SET-PATH-BOOL` — value `"true"` → -1 (TRUE), else 0 |
| Range | `ST-SET-PATH-INT` — value parsed via `STR>NUM` |
| Other | `ST-SET-PATH-STR` — value stored as string |

No-op if the element has no bind expression.

### Action Dispatch

#### UIDL-DISPATCH
```forth
UIDL-DISPATCH ( elem -- action-type )
```
Determine the action type of an element by checking for action
attributes in priority order: `on-activate` (→ 0), `emit` (→ 1),
`set-state` (→ 2).  Returns -1 if no action attribute is present.

| Constant | Value | Attribute |
|----------|-------|-----------|
| `UIDL-ACT-ACTIVATE` | 0 | `on-activate` |
| `UIDL-ACT-EMIT` | 1 | `emit` |
| `UIDL-ACT-SET-STATE` | 2 | `set-state` |

#### UIDL-HAS-ACTION?
```forth
UIDL-HAS-ACTION? ( elem -- flag )
```
Return TRUE if the element has any action attribute.

#### UIDL-ACTION-VALUE
```forth
UIDL-ACTION-VALUE ( elem -- a l flag )
```
Return the value of the element's action attribute (same priority as
`UIDL-DISPATCH`).  Returns `( a l -1 )` if found, `( 0 0 0 )` if none.

### Element Registry

The Element Registry replaces the old fixed type enum with an open
hash-table of element definitions.  Any code can register new element
types at load time.

#### DEFINE-ELEMENT
```forth
DEFINE-ELEMENT ( render-xt event-xt layout-xt flags "name" -- type-id )
```
Parse the next word from input as the tag name and register a new
element type.  Returns the assigned type-id (1-based, sequential).
Registry entries are persistent — they survive `UIDL-RESET`.

Flag constants are composed with `OR`:
```forth
' my-render ' my-event ' my-layout  EL-CONTAINER OR-CHROME OR-FOCUS
DEFINE-ELEMENT my-widget  CONSTANT UIDL-T-MY-WIDGET
```

#### EL-LOOKUP
```forth
EL-LOOKUP ( name-a name-l -- def | 0 )
```
Look up an element definition by tag name string.  Returns the
definition record address, or 0 if not found.

#### EL-DEF-BY-TYPE
```forth
EL-DEF-BY-TYPE ( type-id -- def | 0 )
```
Look up a definition by its numeric type-id.  O(1) via index table.

#### Definition Record Accessors

Each definition record is 64 bytes with these field accessors:

| Word | Offset | Description |
|------|--------|-------------|
| `ED.TYPE` | +0 | Type-id (integer) |
| `ED.NAME-A` | +8 | Tag name string address |
| `ED.NAME-L` | +16 | Tag name string length |
| `ED.FLAGS` | +24 | Content model + category + special flags |
| `ED.RENDER-XT` | +32 | `( elem -- )` rendering hook |
| `ED.EVENT-XT` | +40 | `( elem evt -- handled? )` event hook |
| `ED.LAYOUT-XT` | +48 | `( elem -- )` layout hook |
| `ED.NEXT` | +56 | Reserved / hash chain |

### Element Definition Flags

#### Content Model (bits 0–2)

| Constant | Value | Description |
|----------|-------|-------------|
| `EL-LEAF` | 0 | No children allowed |
| `EL-CONTAINER` | 1 | Arbitrary children |
| `EL-COLLECTION` | 2 | Requires `<template>` + optional `<empty>` |
| `EL-SELECTOR` | 3 | Contains `<option>` children |
| `EL-FIXED-2` | 4 | Exactly 2 children (e.g. split) |
| `EL-FIXED-1` | 5 | Exactly 1 child (e.g. scroll) |

#### Category (bits 3–4)

| Constant | Value | Description |
|----------|-------|-------------|
| `EL-CAT-ENVELOPE` | 0 | Structural envelope |
| `EL-CAT-DATA` | 8 | Data / content element |
| `EL-CAT-CHROME` | 16 | Chrome / UI decoration |
| `EL-CAT-BINDING` | 24 | Binding infrastructure |

#### Special Flags (bits 5–7)

| Constant | Value | Description |
|----------|-------|-------------|
| `EL-F-FOCUS` | 32 | Inherently focusable |
| `EL-F-SELF` | 64 | Self-closing allowed |
| `EL-F-TWOWAY` | 128 | Two-way binding element |

#### Composition Helpers

| Word | Effect |
|------|--------|
| `OR-DATA` | Set data category |
| `OR-CHROME` | Set chrome category |
| `OR-BINDING` | Set binding category |
| `OR-FOCUS` | Set focusable flag |
| `OR-SELF` | Set self-closing flag |
| `OR-TWOWAY` | Set two-way flag |

#### Query Words

| Word | Stack | Description |
|------|-------|-------------|
| `EL-CONTENT-MODEL` | `( fl -- model )` | Extract content model (bits 0–2) |
| `EL-CATEGORY` | `( fl -- cat )` | Extract category (0–3) |
| `EL-FOCUSABLE?` | `( fl -- flag )` | Test focusable bit |
| `EL-SELF-CLOSE?` | `( fl -- flag )` | Test self-closing bit |
| `EL-TWOWAY?` | `( fl -- flag )` | Test two-way bit |

### Subscription Table

The subscription table provides reactive binding between state-tree
paths and UIDL elements.  When a state-tree path changes, calling
`UIDL-NOTIFY` marks all subscribed elements dirty so the paint cycle
can limit itself to changed subtrees.

#### UIDL-SUBSCRIBE
```forth
UIDL-SUBSCRIBE ( elem bind-a bind-l -- )
```
Register an element as a subscriber to the given bind path.
The path is hashed (FNV-1a) for O(1) matching.  No-op if the
subscription table is full (128 entries).

#### UIDL-NOTIFY
```forth
UIDL-NOTIFY ( path-a path-l -- )
```
Hash the path and scan all subscriptions.  For each match, set the
`UIDL-F-DIRTY` flag on the subscribed element.

#### UIDL-RESET-SUBS
```forth
UIDL-RESET-SUBS ( -- )
```
Clear all subscriptions and zero the table.

### Dirty Flag Helpers

#### UIDL-DIRTY?
```forth
UIDL-DIRTY? ( elem -- flag )
```
Test the `UIDL-F-DIRTY` bit on an element's flags.

#### UIDL-DIRTY!
```forth
UIDL-DIRTY! ( elem -- )
```
Set the `UIDL-F-DIRTY` bit on an element.

#### UIDL-CLEAN!
```forth
UIDL-CLEAN! ( elem -- )
```
Clear the `UIDL-F-DIRTY` bit on an element.

## Element Types

All built-in types are registered via the Element Registry at load time.
Type-ids are assigned sequentially (1-based) in registration order,
preserving backward compatibility.

### Core Types (1–21, registered by uidl.f)

| Constant | Value | Model | Category | Description |
|----------|-------|-------|----------|-------------|
| `UIDL-T-REGION` | 1 | container | data | Major layout region |
| `UIDL-T-GROUP` | 2 | container | data | Grouping container |
| `UIDL-T-SEPARATOR` | 3 | leaf | data | Visual/logical separator |
| `UIDL-T-META` | 4 | leaf | data | Key/value metadata |
| `UIDL-T-LABEL` | 5 | leaf | data | Text label |
| `UIDL-T-MEDIA` | 6 | container | data | Multi-representation media |
| `UIDL-T-SYMBOL` | 7 | leaf | data | Named symbol/icon |
| `UIDL-T-CANVAS` | 8 | leaf | data | Drawing surface |
| `UIDL-T-ACTION` | 9 | leaf | data | Button/command trigger |
| `UIDL-T-INPUT` | 10 | leaf | data | Text entry (two-way) |
| `UIDL-T-SELECTOR` | 11 | selector | data | Choice selector (two-way) |
| `UIDL-T-TOGGLE` | 12 | leaf | data | Boolean toggle (two-way) |
| `UIDL-T-RANGE` | 13 | leaf | data | Numeric slider (two-way) |
| `UIDL-T-COLLECTION` | 14 | collection | data | Data-driven list |
| `UIDL-T-TABLE` | 15 | container | data | Tabular data |
| `UIDL-T-INDICATOR` | 16 | leaf | data | Progress/status display |
| `UIDL-T-UIDL` | 17 | container | envelope | Root document element |
| `UIDL-T-TEMPLATE` | 18 | container | binding | Collection item template |
| `UIDL-T-EMPTY` | 19 | container | binding | Collection empty-state |
| `UIDL-T-REP` | 20 | leaf | binding | Media representation variant |
| `UIDL-T-OPTION` | 21 | leaf | binding | Selector option |

`UIDL-T-NONE` (0) indicates an unknown/unmapped tag.

### Chrome Types (22–42, registered by uidl-chrome.f)

| Constant | Value | Model | Category | Description |
|----------|-------|-------|----------|-------------|
| `UIDL-T-MENUBAR` | 22 | container | chrome | Menu bar |
| `UIDL-T-MENU` | 23 | container | chrome | Pull-down menu |
| `UIDL-T-ITEM` | 24 | leaf | chrome | Menu item |
| `UIDL-T-TABS` | 25 | container | chrome | Tab container |
| `UIDL-T-TAB` | 26 | container | chrome | Tab panel |
| `UIDL-T-SPLIT` | 27 | fixed-2 | chrome | Split pane |
| `UIDL-T-SCROLL` | 28 | fixed-1 | chrome | Scroll wrapper |
| `UIDL-T-TREE` | 29 | container | chrome | Tree widget |
| `UIDL-T-STATUS` | 30 | container | chrome | Status bar |
| `UIDL-T-DIALOG` | 31 | container | chrome | Dialog box |
| `UIDL-T-TOAST` | 32 | leaf | chrome | Toast notification |
| `UIDL-T-TEXTAREA` | 33 | leaf | data | Multi-line text (two-way) |
| `UIDL-T-DROPDOWN` | 34 | container | data | Dropdown selector |
| `UIDL-T-RADIOGROUP` | 35 | container | data | Radio button group |
| `UIDL-T-RADIO` | 36 | leaf | data | Radio button (two-way) |
| `UIDL-T-TOOLBAR` | 37 | container | chrome | Tool bar |
| `UIDL-T-LOG` | 38 | container | data | Log/output display |
| `UIDL-T-CODE` | 39 | leaf | data | Code block |
| `UIDL-T-ACCORDION` | 40 | container | data | Collapsible sections |
| `UIDL-T-PASSWORD` | 41 | leaf | data | Password input (two-way) |
| `UIDL-T-CONTEXTMENU` | 42 | container | chrome | Context menu |

## Arrangement Modes

| Constant | Value | Description |
|----------|-------|-------------|
| `UIDL-A-NONE` | 0 | No arrangement specified |
| `UIDL-A-DOCK` | 1 | Docked to edges |
| `UIDL-A-FLEX` | 2 | Flexible proportional layout |
| `UIDL-A-STACK` | 3 | Linear stack (vertical/horizontal) |
| `UIDL-A-FLOW` | 4 | Wrapping flow layout |
| `UIDL-A-GRID` | 5 | Grid layout |

## Element Instance Flags

These are per-instance flags stored in the element's `UE.FLAGS` field,
separate from the definition flags in the registry.

| Constant | Value | Description |
|----------|-------|-------------|
| `UIDL-F-SELFCLOSE` | 1 | Element was self-closing (`<tag />`) |
| `UIDL-F-TWOWAY` | 2 | Auto-set on input, selector, toggle, range |
| `UIDL-F-DIRTY` | 4 | Element needs repaint (set by `UIDL-NOTIFY`) |

## Error Codes

| Constant | Value | Description |
|----------|-------|-------------|
| `UIDL-E-OK` | 0 | No error |
| `UIDL-E-NO-ROOT` | 1 | Missing or non-`<uidl>` root element |
| `UIDL-E-DUP-ID` | 2 | Duplicate `id` attribute |
| `UIDL-E-BAD-TAG` | 3 | Unknown element tag name |
| `UIDL-E-FULL` | 4 | Element pool exhausted |
| `UIDL-E-STR-FULL` | 5 | String pool exhausted |
| `UIDL-E-ATTR-FULL` | 6 | Attribute pool exhausted |
| `UIDL-E-REG-FULL` | 7 | Element registry full (max 64 types) |

## Internal Layout

### Element Node (128 bytes / 16 cells)

| Offset | Field | Description |
|--------|-------|-------------|
| 0 | TYPE | Element type constant |
| 8 | FLAGS | Bit flags |
| 16 | PARENT | Parent element pointer |
| 24 | NEXT | Next sibling pointer |
| 32 | PREV | Previous sibling pointer |
| 40 | FCHILD | First child pointer |
| 48 | LCHILD | Last child pointer |
| 56 | NCHILD | Child count |
| 64 | ID-A | ID string address (in pool) |
| 72 | ID-L | ID string length |
| 80 | ROLE-A | Role string address |
| 88 | ROLE-L | Role string length |
| 96 | ARRANGE | Arrangement mode constant |
| 104 | ATTR | Head of attribute linked list |
| 112 | BIND-A | Bind expression address |
| 120 | BIND-L | Bind expression length |

### Attribute Node (40 bytes / 5 cells)

| Offset | Field | Description |
|--------|-------|-------------|
| 0 | NEXT | Next attribute pointer |
| 8 | NAME-A | Name string address |
| 16 | NAME-L | Name string length |
| 24 | VAL-A | Value string address |
| 32 | VAL-L | Value string length |

### Static Pool Sizes

| Pool | Capacity |
|------|----------|
| Elements | 256 × 128 bytes = 32 KB |
| Attributes | 512 × 40 bytes = 20 KB |
| Strings | 12 KB |
| ID hash table | 256 buckets (linear probing) |
| Subscriptions | 128 × 24 bytes = 3 KB |

### Element Registry Storage

| Pool | Capacity |
|------|----------|
| Registry slots | 64 × 64 bytes = 4 KB |
| Registry strings | 512 bytes (persistent, not reset) |
| Type index | 64 cells |

## UIDL Document Format

```xml
<uidl>
  <region id="nav" arrange="dock" role="navigation">
    <action id="btn-a" on-activate="nav-switch" label="Go" />
    <action id="btn-b" emit="help-request" label="Help" />
  </region>

  <region id="content" arrange="flex" role="primary">
    <label id="title" bind="=ship.name" />
    <indicator id="speed" bind="=ship.speed" mode="bar" min="0" max="100" />
    <media id="status">
      <rep modality="visual" src="diagram.svg" />
      <rep modality="auditory" text="All systems nominal" />
    </media>
  </region>

  <collection id="alerts" arrange="flow">
    <template>
      <group id="alert-{_index}" role="alert">
        <label id="alert-msg-{_index}" />
      </group>
    </template>
    <empty>
      <label id="no-alerts" text="No alerts" />
    </empty>
  </collection>
</uidl>
```

### Special Attributes

These attributes are parsed into dedicated element fields rather than the
generic attribute list:

| Attribute | Stored in | Notes |
|-----------|-----------|-------|
| `id` | `UE.ID-A` / `UE.ID-L` | Registered in hash table |
| `role` | `UE.ROLE-A` / `UE.ROLE-L` | |
| `arrange` | `UE.ARRANGE` | Mapped to `UIDL-A-*` constant |
| `bind` | `UE.BIND-A` / `UE.BIND-L` | Leading `=` stripped |
| `xmlns` | (ignored) | |

All other attributes (e.g. `label`, `on-activate`, `emit`, `src`, `when`,
`mode`, `min`, `max`) are stored in the generic attribute linked list.

## uidl-chrome.f — Chrome Element Registrations

**Module:** `akashic-uidl-chrome`  
**File:** `akashic/liraq/uidl-chrome.f`  
**Requires:** `akashic-uidl`

Registers 21 additional element types for chrome, must-have, and
nice-to-have UI widgets.  All render/event/layout execution tokens
start as `NOOP` — the TUI backend patches them when loaded.

Load after `uidl.f`, before any backend:
```forth
REQUIRE uidl-chrome.f
```

See the Chrome Types table above for the full list.

## Test Coverage

167 tests in `local_testing/test_uidl.py` covering:

- Parse basics (minimal doc, root validation, error codes)
- All 16+4 element types
- Type name mapping
- ID registry (lookup, missing, duplicates)
- Arrangement modes
- Roles
- Tree traversal (parent, children, siblings, chain navigation)
- Self-closing flag
- Two-way flag (auto-set on interactive types)
- Data binding (present/absent, expression stripping)
- When conditions (present/absent, expression stripping)
- Generic attribute lookup (by name, missing, iteration)
- Representation sets (count, lookup by modality, rep attributes)
- Collections (template/empty child lookup)
- Meta element attributes
- Binding and when evaluation (via LEL + state tree)
- Complete document integration test (15 assertions)
- Document validation (14 tests — all 7 rules, error buffer, clear)
- Document mutation (8 tests — add, remove, set/overwrite/remove attr, move)
- Bind write-back (4 tests — string, bool, int, no-bind no-op)
- Action dispatch (9 tests — types, priority, has-action, action-value)
