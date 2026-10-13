# akashic-md5 — MD5

The MD5 digest of RFC 1321. MD5 is broken for signatures and certificates;
it is here because PDF's standard security handler derives its keys with
it.

```forth
REQUIRE md5.f
```

`PROVIDED akashic-md5`. It depends on nothing.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `MD5-SIZE` | `( -- 112 )` | A sum's record. |
| `MD5-INIT` | `( md5 -- )` | Start a sum. |
| `MD5-UPDATE` | `( a u md5 -- )` | Continue it over `u` bytes at `a`. |
| `MD5-FINAL` | `( digest md5 -- )` | End it, and write its 16 bytes at `digest`. |
| `MD5` | `( a u digest -- )` | The sum of `u` bytes at `a`. |

The caller owns a sum's record. A block's working state lives in module
variables, so one call runs at a time, though any number of sums may take
turns; in a guarded build the public words take the module's guard. `MD5`
uses the module's own record. `"abc"` sums to
`900150983cd24fb0d6963f7d28e17f72`.

## Cost

About 134 guest steps a byte, a megabyte in one sum.
