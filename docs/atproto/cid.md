# AT Protocol CID text admission

`akashic/atproto/cid.f` admits the current blessed textual CID profile used
by AT Protocol.  It validates a caller-owned span synchronously, retains no
borrow, allocates no storage, and owns no mutable module state.

The admitted representation is exact:

- CID version 1;
- DRISL/DAG-CBOR (`0x71`) or raw (`0x55`) multicodec;
- SHA-256 (`0x12`) with a 32-byte digest;
- lowercase RFC 4648 base32 with a leading `b` multibase marker;
- no `=` padding and canonical zero trailing bits.

These requirements produce exactly 59 ASCII bytes.  That length is a wire
format consequence, not an implementation capacity.  Callers continue to
own the input bytes; the validator has no destination buffer or retained
result object.

## API

```forth
AT-CID-TEXT-LENGTH             ( -- 59 )

AT-CID-CODEC-NONE              ( -- 0 )
AT-CID-CODEC-RAW               ( -- 0x55 )
AT-CID-CODEC-DAG-CBOR          ( -- 0x71 )
AT-CID-CODEC-VALID?            ( codec -- flag )

AT-CID-STATUS-VALID?           ( status -- flag )
AT-CID-TEXT-CHECK              ( source source-u -- codec status )
AT-CID-TEXT-VALID?             ( source source-u -- flag )
```

`AT-CID-TEXT-CHECK` returns `AT-CID-S-OK` and the exact multicodec on
success.  Every failure returns `AT-CID-CODEC-NONE` with one of:

```forth
AT-CID-S-INVALID
AT-CID-S-LENGTH
AT-CID-S-ENCODING
AT-CID-S-PROFILE
AT-CID-S-RANGE
AT-CID-S-PROTECTED
AT-CID-S-PLATFORM
```

`AT-CID-S-ENCODING` covers the textual envelope: the multibase marker,
alphabet, lowercase requirement, lack of padding, and canonical trailing
bits.  `AT-CID-S-PROFILE` means the text is canonical base32 of the right
length but does not encode the blessed version, codec, hash function, or
digest length.

The codec result deliberately keeps record links and blob links distinct.
For example, a create-record response can admit the CID text here and then
require `AT-CID-CODEC-DAG-CBOR`; accepting `raw` there would be a caller
policy error, not a failure of generic CID syntax admission.

## References

- [AT Protocol data model](https://atproto.com/specs/data-model#link-and-cid-formats)
- [CID specification](https://github.com/multiformats/cid)
