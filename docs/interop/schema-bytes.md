# Canonical schema bytes

`akashic/interop/codecs/schema-bytes.f` gives every interoperability schema
(`interop/schema.f`) exactly one byte form, so a digest of those bytes
identifies the schema. The JSON Schema codec
(`interop/codecs/json-schema.f`) writes a schema as JSON and reads that same
JSON form back into these bytes. `interop/codecs/sandbox-schema.f` restricts
them to what a sandbox module may declare and digests them.

There is one validator: a decoded schema is an ordinary `CS` graph, checked
with `CS-VALIDATE-DEEP` like any other.

## Document

All integers are little-endian. A document is the 8-byte ASCII magic
`AKSCHEMA` followed by exactly one node, with nothing after it.

```text
node  = mask:u16  flags:u8  0:u8
        [min:i64]      flags & 1
        [max:i64]      flags & 2
        [max-len:u64]  flags & 4
        [item:node]    flags & 8
        [count:u16  field{count}]  flags & 16

field = key-u:u32  key:bytes[key-u]  required:u8  schema:node
```

`mask` has bit `t` set for each allowed `CV-T-` type `t`, as `CS.TYPE-MASK`
does. A node's parts mean what the matching `CS` fields mean: `min` and `max`
bound an integer, `max-len` is the one maximum length, `item` describes a
list's items, and the fields close a map.

The canonical form allows no alternatives. A document is refused unless:

- the mask is nonzero and names only known types, and every type is in the
  allowed mask the caller passes;
- the zero byte is zero and only the five flags are used;
- each part's type is in the mask: an integer for `min` and `max`, a type
  with a length for `max-len`, a list for `item`, and a map for the fields;
- `min` is not the cell's minimum, `max` is not its maximum, and `min` is at
  most `max`, because a bound at the extreme is no bound;
- `max-len` is not negative;
- a map has 1 through 256 fields, its keys are valid UTF-8 of at most
  65,536 bytes and strictly increase by unsigned bytes, and each required
  byte is 0 or 1;
- the depth is below 16 and there are at most 65,536 nodes, the bounds
  `CS-SCHEMA-VALIDATE` uses.

A map without fields is open, as in `CS`. A list without an item schema
takes any item.

## Words

- `CSB-MEASURE ( document document-u type-mask -- storage-u ior )` validates
  a document and returns the storage its graph needs.
- `CSB-DECODE ( document document-u type-mask storage storage-u -- schema|0
  ior )` builds the graph in cell-aligned storage of at least that size,
  disjoint from the document. The graph copies every key and borrows nothing
  from the document.
- `CSBW-BEGIN`, `CSBW-U8`, `CSBW-U16`, `CSBW-U32`, `CSBW-U64`, `CSBW-BYTES`,
  `CSBW-FAIL` and `CSBW-END ( -- length ior )` write a document into a
  caller buffer for one producer at a time.

The codes are `CSB-E-INVALID` for a noncanonical document, `CSB-E-TYPE` for
a type outside the allowed mask, `CSB-E-DEPTH`, and `CSB-E-CAPACITY` for
storage that is too small.

## JSON form

`CSJSON-WRITE` and `CSJSON-ENCODE` write a schema as JSON Schema.
`CSJSON-READ ( json json-u buffer capacity -- length ior )` reads that form
into canonical bytes. Each schema is an object:

| Key | Meaning |
| --- | --- |
| `type` | a name, or an array of distinct names: `null`, `boolean`, `integer`, `string`, `array`, `object` |
| `minimum`, `maximum` | integer bounds; a bound at the cell's extreme is dropped |
| `maxLength`, `maxItems`, `maxProperties` | the one maximum length; each the type allows must be present when any is, all equal |
| `items` | the schema of a list's items |
| `properties`, `required`, `additionalProperties` | a closed map: its fields, the required ones, and `false` |
| `description` | a string, ignored |

Any other key is refused. Fields are written in key order. The reader takes
only what JSON can carry (`IVJSON-SCHEMA-COMPATIBLE?`): a list of at most 64
items, empty when its items are unconstrained, and an open map only when it
is empty. Because JSON also counts each value's depth, the deepest schema it
can express is 14 levels below the root, while the byte form allows 15.

The bytes are never longer than the JSON text plus the 8-byte magic, so a
buffer of `json-u + CSB-MAGIC-SIZE` always suffices. The reader answers with
the JSON codec's codes: `IVJSON-E-INVALID` for malformed JSON or a duplicate
key, `IVJSON-E-UNSUPPORTED` for an unknown key or type or anything JSON cannot
carry, `IVJSON-E-TYPE` for an invalid schema, and `IVJSON-E-DEPTH`,
`IVJSON-E-RANGE` and `IVJSON-E-CAPACITY`.

## Sandbox schemas

A sandbox module's entry schemas use only the types a sandbox value carries,
`SBCS-TYPE-MASK`: null, boolean, integer, string, bytes, list and map
(`interop/codecs/sandbox-value.f` carries them as NULL, BOOL, I64, UTF8,
BYTES, LIST and MAP).

- `SBCS-MEASURE` and `SBCS-DECODE` are `CSB-MEASURE` and `CSB-DECODE` with
  that mask.
- `SBCS-DIGEST ( document document-u digest workspace -- ior )` admits a
  document and writes its identity,
  `SHA3-256("akashic.sandbox.schema" || 0x00 || bytes)`.

## Tests

`local_testing/test_sandbox_schema_bytes.py` holds a Python reference of the
reader. The emulator must match it byte for byte on every accepted schema,
refuse every rejected one with the same code, refuse each noncanonical byte
variant, decode each document into a graph the writer turns back into the
expected JSON, and digest it as `hashlib` does.
