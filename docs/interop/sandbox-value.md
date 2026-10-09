# Sandbox value bridge

`akashic/interop/codecs/sandbox-value.f` converts interoperability values
(`interop/value.f`) to and from the sandbox's canonical value codec
([`../sandbox/value-codec.md`](../sandbox/value-codec.md)). A value enters or
leaves a sandbox job only in that codec.

| Interop value | Sandbox value |
| --- | --- |
| `CV-T-NULL` | `NULL` |
| `CV-T-BOOL` | `BOOL` (true is all ones) |
| `CV-T-INT` | `I64` |
| `CV-T-BYTES` | `BYTES` |
| `CV-T-STRING` | `UTF8` |
| `CV-T-LIST` | `LIST` |
| `CV-T-MAP` | `MAP` |

`CV-T-F32` and `CV-T-RESOURCE` have no sandbox form. Encoding either fails with
`SBCV-S-TYPE`.

## Encoding

`SBCV-MEASURE ( value limits -- bytes status )` validates a value and returns
its exact canonical length. `SBCV-ENCODE ( value limits buffer capacity --
bytes status )` measures and then writes, so after a successful measure it can
fail only with:

- `SBCV-S-CAPACITY`, for a buffer that is too small;
- `SBCV-S-ALIAS`, for a buffer that overlaps the value's owned memory;
- `SBCV-S-NOMEM`, when memory runs out.

A string must be exact UTF-8 (`SBCV-S-UTF8`). A map key must be a string, and
keys must be distinct (`SBCV-S-KEY`). Map entries are written in the codec's
raw-byte key order, whatever their order in the value.

## Decoding

`SBCV-DECODE ( bytes bytes-u limits value -- status )` builds an owned value
from exactly one canonical root that fills the span. It validates every header,
extent, count, BOOL bit pattern, UTF-8 payload and key order as it builds.
`SBCV-S-INVALID` reports malformed bytes. On any refusal the value is left
`NULL` and nothing it built remains allocated.

## Limits

Both directions take a sealed `SBOX-VALUE-LIMITS` record and check it while
walking, so a value that a job would refuse fails here first. Both check
depth, blob bytes, list count and map count. Encoding also checks the input
node and expanded-byte totals; decoding checks the result totals instead. A
value beyond any limit fails with `SBCV-S-LIMIT`. Neither walk recurses deeper
than the limit's depth, and sorting a map costs at most the square of the map
count limit.

The bridge proves structure only. Schema validation belongs to the caller.

The test `local_testing/test_sandbox_value_bridge.py` checks the bridge byte
for byte against a Python reference of the codec, which itself reproduces the
codec's golden vectors.
