# OAuth 2 PAR success-response callback

`akashic/security/oauth2/par-response.f` is a generic, standalone decoder for
successful OAuth 2 pushed authorization request (PAR) JSON responses. It
performs strict JSON and field validation, exposes the decoded result only
through a callback, and wipes its complete caller-owned workspace before
returning from every admitted operation.

The component does not perform HTTP, authorization-server discovery, endpoint
selection, PAR request construction, error-response decoding, browser
redirection, authorization callback handling, transaction ownership, or
application-profile policy. In particular, it does not contain AT Protocol or
Streams behavior.

## Recognized members

The input must be one complete JSON object. Both recognized root members are
required:

| Member | Requirement and validation |
| --- | --- |
| `request_uri` | Nonempty JSON string; 1–4096 decoded bytes, each in RFC 6749 `VSCHAR` (`0x20`–`0x7e`) |
| `expires_in` | Integral JSON number from `1` through `2147483647` |

The published capacity constants are:

```forth
OAUTH2-PAR-VIEW-REQUEST-URI-CAPACITY
OAUTH2-PAR-VIEW-MAX-EXPIRES-IN
```

The decoder never truncates `request_uri`. A decoded value that exceeds its
capacity is rejected with `OAUTH2-PAR-RESPONSE-S-CAPACITY`. Empty strings and
decoded bytes outside `VSCHAR` are rejected with
`OAUTH2-PAR-RESPONSE-S-VALUE`.

RFC 9126 leaves the `request_uri` format to the authorization server. This
decoder consequently does not impose RFC 3986 syntax, a URI scheme, or an
authorization-server-specific prefix. The authorization transaction above
this codec remains responsible for accepting a request URI only from its
selected PAR endpoint, binding it to the initiating client and transaction,
using it only as permitted by the server, and preventing reuse.

`expires_in` accepts decimal digits only. A minus sign, zero, fractions,
exponent notation, and values above the published maximum are rejected with
`OAUTH2-PAR-RESPONSE-S-VALUE`; malformed JSON number spellings remain JSON
errors. The codec reports the duration but does not read a clock or calculate
an expiry deadline; the transaction owner must do so at the appropriate
response-receipt boundary.

All other members are unknown extensions. They are ignored only after their
names and complete values have passed strict JSON validation. The parser still
rejects malformed UTF-8, invalid escapes or Unicode scalar values, trailing
input, excessive nesting, and duplicate decoded member names, including in
unknown nested objects.

The root object is limited to 16 members, 1024 aggregate decoded member-name
bytes, and the JOSE JSON document bound of 65536 source bytes. Exceeding any of
those resource limits is a capacity failure.

## Callback API

Allocate an 8-byte-aligned workspace of at least the published size:

```forth
OAUTH2-PAR-RESPONSE-WORKSPACE-SIZE  \ 14568 bytes
```

Then invoke:

```forth
OAUTH2-PAR-RESPONSE-WITH
( source source-u callback context workspace
  -- callback-status response-status )
```

The callback has this stack effect:

```forth
( view context -- callback-status )
```

After the complete response has validated, `WITH` invokes the callback exactly
once. The callback receives the supplied context cell unchanged and may return
any one-cell application status. `WITH` does not interpret that cell: when the
callback returns normally, it is returned as `callback-status` and
`response-status` is `OAUTH2-PAR-RESPONSE-S-OK`.

If admission or parsing fails, the callback is not invoked and
`callback-status` is zero. If the callback throws or does not consume exactly
its two arguments and return exactly one cell, `callback-status` is zero and
`response-status` is `OAUTH2-PAR-RESPONSE-S-CALLBACK`.

For example:

```forth
CREATE par-response-work-storage
    OAUTH2-PAR-RESPONSE-WORKSPACE-SIZE 7 + ALLOT

: par-response-work  ( -- aligned-address )
    par-response-work-storage 7 + -8 AND ;

: accept-par-result  ( view transaction -- callback-status )
    \ Copy and bind the request URI and derive its deadline here.
    2DROP 0 ;

source source-u ['] accept-par-result transaction par-response-work
OAUTH2-PAR-RESPONSE-WITH
```

## Ephemeral view

The callback can inspect the view with:

```forth
OAUTH2-PAR-VIEW-REQUEST-URI@
( view -- address length status )

OAUTH2-PAR-VIEW-EXPIRES-IN@
( view -- seconds status )
```

Both accessors succeed for every valid view. The view and the request-URI span
point inside the operation workspace and are valid only during that callback
invocation. The final wipe invalidates the view magic, so retaining the view or
the request-URI address after the callback is an error; a later accessor call
returns `OAUTH2-PAR-RESPONSE-S-INVALID`. A caller that needs the PAR result
after `WITH` returns must copy and bind it into its own transaction owner while
the callback is running.

Treat the view as read-only. Mutating it can invalidate subsequent accessors
and does not provide a supported way to alter the parsed response.

## Admission, aliasing, and cleanup

Before writing any byte, `WITH` qualifies the complete source and workspace
spans at the caller-memory boundary. The source must be nonempty, no larger
than the JSON document bound, stable for the entire operation, and disjoint
from the complete workspace. The workspace address must be 8-byte aligned. The
callback must be a valid execution token; preflight rejects zero but cannot
establish that an arbitrary nonzero cell is executable. The context is an
opaque cell and may be zero.

Preflight failures return `( 0 response-status )` without changing the
workspace. This distinction is intentional: an unqualified workspace cannot
be safely cleared, and a source/workspace alias cannot be cleared without
destroying the input. The caller remains responsible for any sensitive bytes
already present in a workspace rejected during preflight.

Once admitted, the complete workspace is wiped before staging begins and again
before `WITH` returns. That final wipe occurs after successful parsing and
callback return, ordinary parse rejection, callback failure, or a caught
internal throw. An unexpected admitted throw outside the callback is converted
to `OAUTH2-PAR-RESPONSE-S-INTERNAL` after cleanup. A failure of the mandatory
wipe itself propagates rather than being reported as a successfully scrubbed
ordinary status.

The input source is borrowed and is never wiped by this component. A PAR
request URI is a short-lived authorization transaction artifact, so the
transport owner should scrub or release its receive buffer according to that
owner's security policy. Any bound transaction state populated by the callback
likewise remains the caller's responsibility.

The module has no mutable global operation state. Concurrent uses require
independent source ownership, workspaces, callback contexts, and transaction
destinations.

## Caller responsibilities

A caller must:

- verify exactly HTTP `201 Created` and the JSON media type before invoking
  the decoder;
- provide an exclusively owned, aligned workspace and keep the disjoint source
  stable until `WITH` returns;
- supply a valid callback with the exact documented stack effect;
- copy and bind the request URI and derive its deadline while the callback view
  remains live;
- enforce authorization-server, client, transaction, expiry, and single-use
  policy above this syntax boundary; and
- scrub the transport buffer and any caller-owned transaction copies when
  their respective owners release them.

## Status model

Use `OAUTH2-PAR-RESPONSE-STATUS-VALID?` to validate a status value.

| Status | Meaning |
| --- | --- |
| `OAUTH2-PAR-RESPONSE-S-OK` | The response validated and the callback returned normally |
| `OAUTH2-PAR-RESPONSE-S-INVALID` | Invalid argument, empty document, misaligned workspace, null callback, or invalid/no-longer-live view |
| `OAUTH2-PAR-RESPONSE-S-CAPACITY` | Document, member, name, or decoded-field bound exceeded |
| `OAUTH2-PAR-RESPONSE-S-ALIAS` | The source overlaps the operation workspace |
| `OAUTH2-PAR-RESPONSE-S-JSON` | Strict JSON, UTF-8, Unicode, or nesting rejection |
| `OAUTH2-PAR-RESPONSE-S-MISSING` | A required response member is absent |
| `OAUTH2-PAR-RESPONSE-S-TYPE` | A recognized member has the wrong JSON type |
| `OAUTH2-PAR-RESPONSE-S-VALUE` | A recognized member is empty or violates its field grammar |
| `OAUTH2-PAR-RESPONSE-S-DUPLICATE` | A duplicate decoded JSON member name was found |
| `OAUTH2-PAR-RESPONSE-S-CALLBACK` | The callback threw or violated its stack contract |
| `OAUTH2-PAR-RESPONSE-S-INTERNAL` | An admitted invariant failed or a non-callback operation threw |
| `OAUTH2-PAR-RESPONSE-S-RANGE` | A public span is outside the caller-memory range |
| `OAUTH2-PAR-RESPONSE-S-PROTECTED` | A public span aliases protected platform storage |
| `OAUTH2-PAR-RESPONSE-S-PLATFORM` | Caller-span qualification failed at the platform boundary |

Consumers should check `response-status` before interpreting
`callback-status`. Provider- or application-specific requirements—such as
HTTP status handling, request-URI binding, expiry calculation, browser
redirection, callback-state verification, or durable transaction
installation—belong in the callback or in a higher-level component.
