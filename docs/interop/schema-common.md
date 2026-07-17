# Common caller-owned schemas

`akashic/interop/schema-common.f` contains only small schema initializers. Each
word fills one caller-supplied `CS-SIZE` allocation; the module publishes no
mutable schema object and does not encode domain maps, paging, resolution, or
authority policy.

| Word | Stack effect | Schema shape |
|---|---|---|
| `CSC-NULL!` | `( schema -- )` | null |
| `CSC-BOOL!` | `( schema -- )` | boolean |
| `CSC-NONNEG-INT!` | `( schema -- )` | integer, minimum 0 |
| `CSC-POSITIVE-REVISION!` | `( schema -- )` | integer, minimum 1 |
| `CSC-UTF8!` | `( max-length schema -- )` | UTF-8 string with the supplied byte bound |
| `CSC-SEMANTIC-RREF!` | `( schema -- )` | resource value bounded by the canonical semantic-RREF maximum |
| `CSC-OPTIONAL-SEMANTIC-RREF!` | `( schema -- )` | null or bounded semantic-RREF resource value |
| `CSC-RREF-TEXT!` | `( schema -- )` | UTF-8 string bounded to canonical RREF text |
| `CSC-VFS-LOCATOR-TEXT!` | `( schema -- )` | UTF-8 string bounded for `vfs:` plus a 512-byte Explorer path |

`CSC-RREF-TEXT-MAX` follows `IRES-RREF-URI-MAX` and is currently 110 bytes.
`CSC-VFS-LOCATOR-TEXT-MAX` is separately fixed at 516 bytes. They are not
interchangeable: existing 516-byte resource schemas may admit VFS locators and
must not be narrowed merely because a semantic RREF is shorter.

Schema validation checks type, byte bound, and UTF-8. Canonical RREF grammar
and VFS prefix/path policy remain with `IRES-RREF@`, `IRES-VFS-PATH`, and the
owning capability; an initializer alone cannot prove locator provenance or
grant authority.
