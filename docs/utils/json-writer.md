# Caller-owned JSON string writer

`akashic/utils/json-writer.f` adds one neutral JSON primitive to the
caller-owned checked buffer writer. It has no process-global builder, hidden
arena, protocol policy, or payload ceiling. Capacity is exactly the capacity
of the `CBW` arena supplied by the caller.

## API

```forth
JSONW-STRING-MEASURE  ( source-a source-u -- encoded-u status )
JSONW-STRING          ( source-a source-u writer -- status )
```

The status values are the existing `CBW-S-OK`, `CBW-S-INVALID`, and
`CBW-S-CAPACITY` values from `buffer-writer.f`. `JSONW-STRING-MEASURE` returns
the exact number of output bytes, including both quotes. `JSONW-STRING`
appends that quoted representation to an already initialized writer. JSON
object punctuation, keys, and value structure remain the caller's concern and
can be composed with `CBW-CHAR`, `CBW-APPEND`, and the other buffer-writer
words.

Input must be a nonwrapping byte span containing strict UTF-8. The empty span
is valid and emits `""`. Quote and reverse-solidus are escaped; backspace,
tab, newline, form feed, and carriage return use their short escapes; the
other C0 controls use uppercase `\u00XX`. All other UTF-8 bytes are copied
unchanged. Solidus is not escaped.

## Ownership and failure behavior

The writer descriptor and output arena remain caller-owned.
Independent writers can be used in any interleaving because this module
introduces no mutable state. Each call reserves the complete representation before writing any byte.
Invalid input or insufficient capacity leaves the length and arena unchanged
and latches the ordinary `CBW` sticky status.

A source may borrow an earlier, disjoint part of the same output arena. It may
not overlap the writer descriptor or the exact output span reserved by the
call. That policy permits useful append-from-prefix composition without
claiming an unsafe in-place escaping contract.
