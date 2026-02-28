# LEL — LIRAQ Expression Language

**Module:** `akashic-lel`  
**File:** `akashic/liraq/lel.f`  
**Requires:** `akashic-string`, `akashic-fp32`, `akashic-fixed`, `akashic-state-tree`

## Overview

LEL is a pure, total, deterministic expression evaluator for LIRAQ data bindings.
It evaluates formula expressions against the current state tree, supporting
arithmetic, comparison, logic (with short-circuit), string manipulation, and
type conversion — all with automatic float promotion and graceful coercion.

**Totality guarantee:** Every expression produces a value. Division by zero → 0,
missing paths → null, type mismatches → coerced or 0/empty/false.

## Public API

### LEL-EVAL
```forth
LEL-EVAL ( expr-a expr-l -- type v1 v2 )
```
Evaluate an expression string. Returns a triple: type tag (ST-T-* constant),
value cell 1, and value cell 2. For strings: type=1, v1=addr, v2=len.
For integers: type=2, v1=value, v2=0. For booleans: type=3, v1=0|1, v2=0.
For floats: type=5, v1=packed-fp32, v2=0.

### LEL-SET-CONTEXT
```forth
LEL-SET-CONTEXT ( item-node index -- )
```
Set the `_item` and `_index` context variables for collection template iteration.
`item-node` is a state-tree node address; `index` is an integer.

### LEL-CLEAR-CONTEXT
```forth
LEL-CLEAR-CONTEXT ( -- )
```
Clear context variables (sets both to 0/null).

## Expression Syntax

### Literals
| Syntax | Type | Example |
|--------|------|---------|
| Integer | `ST-T-INTEGER` | `42`, `-5`, `0` |
| Float | `ST-T-FLOAT` | `3.14`, `-2.7`, `1.0` |
| String | `ST-T-STRING` | `'hello'`, `'it''s'` (escaped quote) |
| Boolean | `ST-T-BOOLEAN` | `true`, `false` |
| Null | `ST-T-NULL` | `null` |

### State References
Bare identifiers resolve against the state tree via `ST-GET-PATH`:
- `speed` → looks up `/speed`
- `ship.speed` → looks up `/ship/speed`
- `ship.info.name` → nested path lookup

### Context Variables
- `_index` — current iteration index (integer)
- `_item` — current collection item (state-tree node, supports `.field` chaining)

### Function Calls
```
function-name(arg1, arg2, ...)
```

## Built-in Functions (38 total)

### Arithmetic (13)
All arithmetic functions support **float promotion**: if either operand is a float,
both are promoted to FP32 and the result is float.

| Function | Args | Description |
|----------|------|-------------|
| `add(a,b)` | 2 | Addition |
| `sub(a,b)` | 2 | Subtraction (a - b) |
| `mul(a,b)` | 2 | Multiplication |
| `div(a,b)` | 2 | Division (div by zero → 0) |
| `mod(a,b)` | 2 | Modulo (mod by zero → 0) |
| `neg(a)` | 1 | Negate |
| `abs(a)` | 1 | Absolute value |
| `round(a)` | 1 | Round to nearest (via FX-ROUND) |
| `floor(a)` | 1 | Floor (via FX-FLOOR) |
| `ceil(a)` | 1 | Ceiling (via FX-CEIL) |
| `min(a,b)` | 2 | Minimum |
| `max(a,b)` | 2 | Maximum |
| `clamp(v,lo,hi)` | 3 | Clamp value to range |

### Comparison (7)
| Function | Args | Description |
|----------|------|-------------|
| `eq(a,b)` | 2 | Equal (type-aware: null=null, string=string, numeric promotion) |
| `neq(a,b)` | 2 | Not equal |
| `gt(a,b)` | 2 | Greater than (numeric, coerces to FP32) |
| `gte(a,b)` | 2 | Greater than or equal |
| `lt(a,b)` | 2 | Less than |
| `lte(a,b)` | 2 | Less than or equal |
| `not(a)` | 1 | Logical not (truthy → false, falsy → true) |

### Logic (4) — Short-circuit
These functions evaluate arguments lazily (short-circuit):

| Function | Args | Description |
|----------|------|-------------|
| `if(cond,then,else)` | 3 | Conditional: evaluates only the chosen branch |
| `and(a,b)` | 2 | If a is falsy, return a; else evaluate and return b |
| `or(a,b)` | 2 | If a is truthy, return a; else evaluate and return b |
| `coalesce(a,b)` | 2 | If a is not null, return a; else evaluate b |

### String (9)
| Function | Args | Description |
|----------|------|-------------|
| `concat(a,b,...)` | variadic | Concatenate (coerces all args to string) |
| `length(s)` | 1 | String length (also works on arrays/objects → child count) |
| `upper(s)` | 1 | Uppercase |
| `lower(s)` | 1 | Lowercase |
| `trim(s)` | 1 | Trim whitespace |
| `substring(s,start,len)` | 3 | Extract substring (0-indexed, clamped) |
| `contains(s,sub)` | 2 | True if s contains sub |
| `starts-with(s,pfx)` | 2 | True if s starts with pfx |
| `ends-with(s,sfx)` | 2 | True if s ends with sfx |

### Type (5)
| Function | Args | Description |
|----------|------|-------------|
| `to-string(v)` | 1 | Convert to string |
| `to-number(v)` | 1 | Convert to integer |
| `to-boolean(v)` | 1 | Convert to boolean (truthy test) |
| `is-null(v)` | 1 | True if v is null |
| `type-of(v)` | 1 | Returns type name as string |

## Coercion Rules

### Truthy/Falsy
- **Truthy:** non-zero integer, non-zero float, non-empty string, `true`, array, object
- **Falsy:** `0`, `0.0`, `''`, `false`, `null`

### To Integer
- Integer → itself
- Boolean → 0 or 1
- Float → truncated (FP32>INT)
- String → parsed as decimal (STR>NUM), 0 on failure
- Null/Array/Object → 0

### To FP32
- Float → itself
- Integer → INT>FP32
- Boolean → INT>FP32 (0.0 or 1.0)
- String → parsed as int then INT>FP32, 0.0 on failure
- Null/Array/Object → FP32-ZERO

### To String
- String → itself
- Integer → decimal string (NUM>STR)
- Float → truncated to int then decimal string
- Boolean → `"true"` or `"false"`
- Null → `""` (empty)

## Limits
- Max expression length: limited by source buffer
- Value stack: 48 entries
- Path buffer: 256 bytes
- Scratch string buffer: 4096 bytes
- Max function args: limited by value stack depth

## Example Expressions
```
42                          → INTEGER 42
add(3, 4)                   → INTEGER 7
mul(2.5, 4)                 → FLOAT 10.0
if(gt(score, 100), 'high', 'low')
concat('Hello, ', name, '!')
coalesce(nickname, name)
and(active, gt(health, 0))
```
