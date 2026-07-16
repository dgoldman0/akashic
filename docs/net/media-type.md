# Bounded media-type parsing

`akashic/net/media-type.f` parses one HTTP media-type field value into a
caller-owned, bounded model. It validates syntax only. The caller remains
responsible for deciding which type, subtype, parameters, and parameter values
are acceptable for a particular resource.

```forth
REQUIRE net/media-type.f

CREATE response-type MTYPE-SIZE ALLOT
response-type MTYPE-INIT
header-a header-u response-type MTYPE-PARSE
```

The parser accepts a `type/subtype` pair, optional HTTP whitespace around
semicolon separators, and at most `MTYPE-PARAM-MAX` parameters. Parameter
values may be tokens or quoted strings. Quoted pairs are decoded, and quoted
values are returned without their surrounding quotes. Whitespace around `/`
or `=` is rejected rather than guessed away. Duplicate parameter names are
retained in input order so admission policy can reject or interpret them
explicitly.

The model owns a copy of the field value, so views remain valid until that
model is initialized or parsed again. A failed parse leaves the previous model
byte-for-byte unchanged. `MTYPE-VALUE-MAX` is 1,024 bytes,
`MTYPE-PARAM-MAX` is eight, and exceeding either bound returns
`MTYPE-S-CAPACITY`.

| Word | Stack effect | Meaning |
| --- | --- | --- |
| `MTYPE-INIT` | `( model -- )` | Clear a model; nonpositive pointers are ignored. |
| `MTYPE-PARSE` | `( value-a value-u model -- status )` | Parse transactionally into the model. |
| `MTYPE-VALID?` | `( model -- flag )` | Check the model's structural marker and bounded offsets. |
| `MTYPE-TYPE$` | `( model -- type-a type-u )` | Return the original-cased type token. |
| `MTYPE-SUBTYPE$` | `( model -- subtype-a subtype-u )` | Return the original-cased subtype token. |
| `MTYPE-PARAM-COUNT@` | `( model -- count )` | Return the retained parameter count. |
| `MTYPE-PARAM-NTH` | `( index model -- name-a name-u value-a value-u found? )` | Return one decoded parameter view. |

Statuses are independent of any consuming applet: `MTYPE-S-OK`,
`MTYPE-S-INVALID`, and `MTYPE-S-CAPACITY`. Type, subtype, and parameter-name
comparison is normally ASCII case-insensitive; the meaning and comparison
rules for a parameter value belong to the consumer.

This module is not a MIME registry, comma-delimited HTTP field-list parser,
content-sniffing algorithm, charset transcoder, or trust decision. In
particular, successful parsing does not make a representation safe to render
or execute.

Run its deterministic contracts with:

```sh
python3 local_testing/akashic_tui.py smoke --profile media-type-contracts
```
