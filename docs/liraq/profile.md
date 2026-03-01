# Profile — LIRAQ Presentation Profile Parser

**Module:** `akashic-profile`  
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

#### PROF-NAME
```forth
PROF-NAME ( p-a p-l -- str-a str-l )
```
Extract the profile's name string.  Aborts if `profile.name` is absent.

#### PROF-VERSION
```forth
PROF-VERSION ( p-a p-l -- str-a str-l )
```
Extract the profile's version string.

#### PROF-DESC?
```forth
PROF-DESC? ( p-a p-l -- str-a str-l flag )
```
Extract the optional description.  Returns `( str-a str-l -1 )` if present,
`( 0 0 0 )` if absent.

#### PROF-VALID?
```forth
PROF-VALID? ( p-a p-l -- flag )
```
Does this YAML document have a valid profile header with at least
`name` and `capabilities`?

#### PROF-CAPS-COUNT
```forth
PROF-CAPS-COUNT ( p-a p-l -- n )
```
Number of capabilities declared by the profile.

#### PROF-HAS-CAP?
```forth
PROF-HAS-CAP? ( p-a p-l cap-a cap-l -- flag )
```
Does the profile's `capabilities` array contain the given string?

### Element Category Classifier

#### PROF-ELEM-CAT
```forth
PROF-ELEM-CAT ( type-a type-l -- cat-a cat-l )
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

#### PROF-DEFAULT
```forth
PROF-DEFAULT ( p-a p-l cat-a cat-l prop-a prop-l -- val-a val-l flag )
```
Look up `defaults.<category>.<property>`.

#### PROF-ETYPE
```forth
PROF-ETYPE ( p-a p-l type-a type-l prop-a prop-l -- val-a val-l flag )
```
Look up `element-types.<type>.<property>`.

#### PROF-ROLE
```forth
PROF-ROLE ( p-a p-l role-a role-l prop-a prop-l -- val-a val-l flag )
```
Look up `roles.<role>.<property>`.

#### PROF-STATE
```forth
PROF-STATE ( p-a p-l state-a state-l prop-a prop-l -- val-a val-l flag )
```
Look up `states.<state>.<property>`.

#### PROF-IMPORTANCE
```forth
PROF-IMPORTANCE ( p-a p-l imp-a imp-l prop-a prop-l -- val-a val-l flag )
```
Look up `importance.<level>.<property>`.

#### PROF-DENSITY
```forth
PROF-DENSITY ( p-a p-l name-a name-l key-a key-l -- val-a val-l flag )
```
Look up `density.<name>.<key>`.

#### PROF-HIGH-CONTRAST
```forth
PROF-HIGH-CONTRAST ( p-a p-l key-a key-l -- val-a val-l flag )
```
Look up `high-contrast.<key>`.

### Cascade Context

Set context once, then call `PROF-GET` repeatedly for different properties:

```forth
S" label" PROF-SET-TYPE
S" navigation" PROF-SET-ROLE
S" attended" PROF-SET-STATE
prof-a prof-l S" color" PROF-GET  ( -- val-a val-l flag )
prof-a prof-l S" font-size" PROF-GET
PROF-CLEAR-CTX
```

#### PROF-SET-TYPE
```forth
PROF-SET-TYPE ( type-a type-l -- )
```
Set element type for cascade.  Auto-sets the default category via
`PROF-ELEM-CAT`.

#### PROF-SET-ROLE
```forth
PROF-SET-ROLE ( role-a role-l -- )
```

#### PROF-SET-STATE
```forth
PROF-SET-STATE ( state-a state-l -- )
```

#### PROF-SET-IMP
```forth
PROF-SET-IMP ( imp-a imp-l -- )
```
Set importance level for cascade.

#### PROF-CLEAR-CTX
```forth
PROF-CLEAR-CTX ( -- )
```
Clear all cascade context (type, role, state, importance, category).

#### PROF-GET
```forth
PROF-GET ( p-a p-l prop-a prop-l -- val-a val-l flag )
```
Resolve a property through the full cascade using the current context.
Checks all five layers in order; later matches override earlier ones.
Returns the most-specific value found, or `( 0 0 0 )` if not found.

### Error Handling

```forth
PROF-ERR        ( variable )   \ error code, 0 = OK
PROF-OK?        ( -- flag )    \ true if no error
PROF-CLEAR-ERR  ( -- )         \ reset error state
PROF-E-NOT-FOUND  ( constant = 1 )  \ property not found
PROF-E-BAD-PROFILE ( constant = 2 ) \ missing profile header
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
