# UIDL — LIRAQ Document Model

**Module:** `akashic-uidl`  
**File:** `akashic/liraq/uidl.f`  
**Requires:** `akashic-string`, `akashic-markup-core`, `akashic-xml`, `akashic-lel`, `akashic-state-tree`

## Overview

The UIDL Document Model implements LIRAQ Spec §02 — parsing UIDL XML
documents into a static-pool semantic element tree.  UIDL (Universal
Interface Description Language) describes user interfaces as a tree of
typed, attributed elements with no visual or auditory bias.

The parser accepts UIDL XML text (addr len), validates it, and builds an
in-memory tree of element nodes with:

- **16 semantic element types** — structural, content, interactive, and
  collection primitives
- **4 pseudo-types** — uidl (root), template, empty, rep
- **6 arrangement modes** — none, dock, flex, stack, flow, grid
- **Per-element attribute linked lists** — generic key/value pairs
- **FNV-1a hashed ID registry** — O(1) element lookup by ID
- **Data binding and conditional display** — `bind` and `when` expressions
  evaluated via LEL against the state tree

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

## Element Types

### Semantic Types (1–16)

| Constant | Value | Category | Description |
|----------|-------|----------|-------------|
| `UIDL-T-REGION` | 1 | Structural | Major layout region |
| `UIDL-T-GROUP` | 2 | Structural | Grouping container |
| `UIDL-T-SEPARATOR` | 3 | Structural | Visual/logical separator |
| `UIDL-T-META` | 4 | Structural | Key/value metadata |
| `UIDL-T-LABEL` | 5 | Content | Text label |
| `UIDL-T-MEDIA` | 6 | Content | Multi-representation media |
| `UIDL-T-SYMBOL` | 7 | Content | Named symbol/icon |
| `UIDL-T-CANVAS` | 8 | Content | Drawing surface |
| `UIDL-T-ACTION` | 9 | Interactive | Button/command trigger |
| `UIDL-T-INPUT` | 10 | Interactive | Text entry (two-way) |
| `UIDL-T-SELECTOR` | 11 | Interactive | Choice selector (two-way) |
| `UIDL-T-TOGGLE` | 12 | Interactive | Boolean toggle (two-way) |
| `UIDL-T-RANGE` | 13 | Interactive | Numeric slider (two-way) |
| `UIDL-T-COLLECTION` | 14 | Collection | Data-driven list |
| `UIDL-T-TABLE` | 15 | Collection | Tabular data |
| `UIDL-T-INDICATOR` | 16 | Content | Progress/status display |

### Pseudo-Types (17–20)

| Constant | Value | Description |
|----------|-------|-------------|
| `UIDL-T-UIDL` | 17 | Root document element |
| `UIDL-T-TEMPLATE` | 18 | Collection item template |
| `UIDL-T-EMPTY` | 19 | Collection empty-state template |
| `UIDL-T-REP` | 20 | Media representation variant |

`UIDL-T-NONE` (0) indicates an unknown/unmapped tag.

## Arrangement Modes

| Constant | Value | Description |
|----------|-------|-------------|
| `UIDL-A-NONE` | 0 | No arrangement specified |
| `UIDL-A-DOCK` | 1 | Docked to edges |
| `UIDL-A-FLEX` | 2 | Flexible proportional layout |
| `UIDL-A-STACK` | 3 | Linear stack (vertical/horizontal) |
| `UIDL-A-FLOW` | 4 | Wrapping flow layout |
| `UIDL-A-GRID` | 5 | Grid layout |

## Element Flags

| Constant | Value | Description |
|----------|-------|-------------|
| `UIDL-F-SELFCLOSE` | 1 | Element was self-closing (`<tag />`) |
| `UIDL-F-TWOWAY` | 2 | Auto-set on input, selector, toggle, range |

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

## Test Coverage

132 tests in `local_testing/test_uidl.py` covering:

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
