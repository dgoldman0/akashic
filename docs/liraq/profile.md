# Profile — LIRAQ Presentation Profile Parser

**Module:** `akashic-pp`  
**File:** `akashic/liraq/profile.f`  
**Requires:** `akashic-yaml`, `akashic-string`

## Overview

The Presentation Profile Parser implements LIRAQ Spec §07 — loading and
querying YAML presentation profiles.  Profiles declare visual, auditory,
or tactile styling for UIDL components, providing a six-level cascade:

1. **Capability defaults** — `defaults.<category>.<property>`
2. **Element-type defaults** — `element-types.<type>.<property>`
3. **Role overrides** — `roles.<role>.<property>`
4. **State overrides** — `states.<state>.<property>`
5. **Importance overrides** — `importance.<level>.<property>`
6. **Inline overrides** — handled by caller (present-* attributes)

All lookups are cursor-based (zero-copy) via the `akashic-yaml` library.
Profile documents are YAML text (addr len) stored in memory.

## Public API

### Metadata

#### PP-NAME
```forth
PP-NAME ( p-a p-l -- str-a str-l )
```
Extract the profile's name string.  Aborts if `profile.name` is absent.

#### PP-VERSION
```forth
PP-VERSION ( p-a p-l -- str-a str-l )
```
Extract the profile's version string.

#### PP-DESC?
```forth
PP-DESC? ( p-a p-l -- str-a str-l flag )
```
Extract the optional description.  Returns `( str-a str-l -1 )` if present,
`( 0 0 0 )` if absent.

#### PP-VALID?
```forth
PP-VALID? ( p-a p-l -- flag )
```
Does this YAML document have a valid profile header with at least
`name` and `capabilities`?

#### PP-CAPS-COUNT
```forth
PP-CAPS-COUNT ( p-a p-l -- n )
```
Number of capabilities declared by the profile.

#### PP-HAS-CAP?
```forth
PP-HAS-CAP? ( p-a p-l cap-a cap-l -- flag )
```
Does the profile's `capabilities` array contain the given string?

### Element Category Classifier

#### PP-ELEM-CAT
```forth
PP-ELEM-CAT ( type-a type-l -- cat-a cat-l )
```
Map a UIDL element type name to its default cascade category.  The 16
standard types map as:

| Category      | Element Types                                   |
|---------------|-------------------------------------------------|
| `content`     | label, indicator, media, canvas, symbol, meta   |
| `container`   | region, group, collection, table                |
| `interactive` | action, input, selector, toggle, range          |
| `separator`   | separator                                       |

Unknown types default to `content`.

### Direct Layer Access

Each layer accessor follows the same pattern:
```forth
( p-a p-l  key-a key-l  prop-a prop-l -- val-a val-l flag )
```
Where *key* is the subsection name (category, type, role, etc.) and *prop* is
the property name.  Returns `( val-cursor -1 )` on success, `( 0 0 0 )` on
not-found.

#### PP-DEFAULT
```forth
PP-DEFAULT ( p-a p-l cat-a cat-l prop-a prop-l -- val-a val-l flag )
```
Look up `defaults.<category>.<property>`.

#### PP-ETYPE
```forth
PP-ETYPE ( p-a p-l type-a type-l prop-a prop-l -- val-a val-l flag )
```
Look up `element-types.<type>.<property>`.

#### PP-ROLE
```forth
PP-ROLE ( p-a p-l role-a role-l prop-a prop-l -- val-a val-l flag )
```
Look up `roles.<role>.<property>`.

#### PP-STATE
```forth
PP-STATE ( p-a p-l state-a state-l prop-a prop-l -- val-a val-l flag )
```
Look up `states.<state>.<property>`.

#### PP-IMPORTANCE
```forth
PP-IMPORTANCE ( p-a p-l imp-a imp-l prop-a prop-l -- val-a val-l flag )
```
Look up `importance.<level>.<property>`.

#### PP-DENSITY
```forth
PP-DENSITY ( p-a p-l name-a name-l key-a key-l -- val-a val-l flag )
```
Look up `density.<name>.<key>`.

#### PP-HIGH-CONTRAST
```forth
PP-HIGH-CONTRAST ( p-a p-l key-a key-l -- val-a val-l flag )
```
Look up `high-contrast.<key>`.

### Cascade Context

Set context once, then call `PP-GET` repeatedly for different properties:

```forth
S" label" PP-SET-TYPE
S" navigation" PP-SET-ROLE
S" attended" PP-SET-STATE
prof-a prof-l S" color" PP-GET  ( -- val-a val-l flag )
prof-a prof-l S" font-size" PP-GET
PP-CLEAR-CTX
```

#### PP-SET-TYPE
```forth
PP-SET-TYPE ( type-a type-l -- )
```
Set element type for cascade.  Auto-sets the default category via
`PP-ELEM-CAT`.

#### PP-SET-ROLE
```forth
PP-SET-ROLE ( role-a role-l -- )
```

#### PP-SET-STATE
```forth
PP-SET-STATE ( state-a state-l -- )
```

#### PP-SET-IMP
```forth
PP-SET-IMP ( imp-a imp-l -- )
```
Set importance level for cascade.

#### PP-CLEAR-CTX
```forth
PP-CLEAR-CTX ( -- )
```
Clear all cascade context (type, role, state, importance, category).

#### PP-GET
```forth
PP-GET ( p-a p-l prop-a prop-l -- val-a val-l flag )
```
Resolve a property through the full cascade using the current context.
Checks all five layers in order; later matches override earlier ones.
Returns the most-specific value found, or `( 0 0 0 )` if not found.

### Error Handling

```forth
PP-ERR        ( variable )   \ error code, 0 = OK
PP-OK?        ( -- flag )    \ true if no error
PP-CLEAR-ERR  ( -- )         \ reset error state
PP-E-NOT-FOUND  ( constant = 1 )  \ property not found
PP-E-BAD-PROFILE ( constant = 2 ) \ missing profile header
```

## Profile YAML Format

```yaml
profile:
  name: lcars-dark
  version: "1.0"
  capabilities: [visual]
  description: "LCARS dark theme"

defaults:
  content:
    font-family: "Antonio"
    font-size: 18
    color: "#FF9900"
  container:
    background: "#000000"
    padding: 12

element-types:
  label:
    font-weight: 400
  action:
    background: "#CC6699"

roles:
  alert:
    color: "#FF3333"

states:
  attended:
    outline: "2px solid #FFFFFF"

importance:
  high:
    font-weight: 700

density:
  compact:
    font-size: 14

high-contrast:
  foreground: "#FFFFFF"
  background: "#000000"
```

## Test Coverage

82 tests in `local_testing/test_profile.py` covering:

- Metadata extraction (name, version, description, validation, capabilities)
- Element category classification (all 16 types)
- Direct layer access (defaults, element-types, roles, states, importance,
  density, high-contrast) including missing-key paths
- Full cascade resolution (defaults-only, element-type override, role override,
  state override, importance override, region/container defaults)
- Multi-capability and auditory profile variants
