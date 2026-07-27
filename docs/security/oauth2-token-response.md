# OAuth 2 token-response callback

`akashic/security/oauth2/token-response.f` is a generic, standalone decoder for
successful OAuth 2 JSON token responses. It performs strict JSON and field
validation, exposes the decoded credentials only through a callback, and wipes
its complete caller-owned workspace before returning from every admitted
operation.

The component does not perform HTTP, authorization-server discovery, endpoint
selection, token installation, refresh, persistence, OIDC validation, or
application-profile policy. In particular, it does not assign meaning to a
token type or scope and contains no provider- or application-specific behavior.

## Recognized members

The input must be one complete JSON object. Five root members are recognized:

| Member | Requirement and validation |
| --- | --- |
| `access_token` | Required, nonempty JSON string; 1–8192 decoded bytes, each in RFC 6749 `VSCHAR` (`0x20`–`0x7e`) |
| `token_type` | Required, nonempty JSON string; 1–4096 decoded bytes matching RFC 6749 `type-name / URI-reference` |
| `refresh_token` | Optional; when present, a nonempty JSON string of at most 4096 decoded `VSCHAR` bytes |
| `scope` | Optional; when present, a nonempty RFC 6749 scope string of at most 4096 decoded bytes |
| `expires_in` | Optional; when present, an integral JSON number from `0` through `2147483647` |

The published capacity constants are:

```forth
OAUTH2-TOKEN-VIEW-ACCESS-CAPACITY
OAUTH2-TOKEN-VIEW-TOKEN-TYPE-CAPACITY
OAUTH2-TOKEN-VIEW-REFRESH-CAPACITY
OAUTH2-TOKEN-VIEW-SCOPE-CAPACITY
OAUTH2-TOKEN-VIEW-MAX-EXPIRES-IN
```

The decoder never truncates a value. A recognized string that exceeds its
field capacity is rejected with `OAUTH2-TOKEN-RESPONSE-S-CAPACITY`.

An accepted scope consists of one or more nonempty scope tokens separated by
single spaces. Token bytes are `0x21`, `0x23`–`0x5b`, or `0x5d`–`0x7e`;
leading, trailing, and repeated spaces are rejected. `expires_in` accepts
decimal digits only. Signs, fractions, exponent notation, and overflow beyond
the published maximum are rejected.

A token `type-name` contains only ASCII letters, digits, `-`, `.`, and `_`.
The alternative URI-reference form is validated as RFC 3986 syntax, including
component delimiters, percent triplets, authority and path forms, and
bracketed IP literals. The decoder preserves the exact spelling and still
leaves the decision about which valid token types the application supports to
the callback.

All other members are unknown extensions. They are ignored only after their
names and complete values have passed strict JSON validation. The parser still
rejects malformed UTF-8, invalid escapes or Unicode scalar values, trailing
input, excessive nesting, and duplicate decoded member names, including in
unknown nested objects.

The root object is limited to 16 members, 1024 aggregate decoded member-name
bytes, and the JOSE JSON document bound of 65536 source bytes. Exceeding any of
those resource limits is a capacity failure.

## Callback API

Allocate at least the published workspace size:

```forth
OAUTH2-TOKEN-RESPONSE-WORKSPACE-SIZE  \ 30976 bytes
```

Then invoke:

```forth
OAUTH2-TOKEN-RESPONSE-WITH
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
`response-status` is `OAUTH2-TOKEN-RESPONSE-S-OK`.

If admission or parsing fails, the callback is not invoked and
`callback-status` is zero. If the callback throws or does not consume exactly
its two arguments and return exactly one cell, `callback-status` is zero and
`response-status` is `OAUTH2-TOKEN-RESPONSE-S-CALLBACK`.

For example:

```forth
CREATE token-response-work
    OAUTH2-TOKEN-RESPONSE-WORKSPACE-SIZE ALLOT

: install-token-set  ( view context -- callback-status )
    \ Validate profile policy and copy/install the required values here.
    2DROP 0 ;

source source-u ['] install-token-set context token-response-work
OAUTH2-TOKEN-RESPONSE-WITH
```

## Ephemeral view

The callback can inspect the view with:

```forth
OAUTH2-TOKEN-VIEW-ACCESS-TOKEN@
( view -- address length status )

OAUTH2-TOKEN-VIEW-TOKEN-TYPE@
( view -- address length status )

OAUTH2-TOKEN-VIEW-REFRESH-TOKEN@
( view -- address length status )

OAUTH2-TOKEN-VIEW-SCOPE@
( view -- address length status )

OAUTH2-TOKEN-VIEW-EXPIRES-IN@
( view -- seconds status )
```

The access token and token type accessors succeed for every valid view.
Optional accessors return `OAUTH2-TOKEN-RESPONSE-S-MISSING` when their member
was absent. Missing string accessors return a zero address and zero length;
missing `expires_in` returns zero seconds.

The view and every string span returned from it point inside the operation
workspace. They are valid only during that callback invocation. The final wipe
invalidates the view magic, so retaining the view or one of its field addresses
after the callback is an error; a later accessor call returns
`OAUTH2-TOKEN-RESPONSE-S-INVALID`. A caller that needs credentials after
`WITH` returns must copy or install them into its own protected owner while the
callback is running.

Treat the view as read-only. Mutating it can invalidate subsequent accessors
and does not provide a supported way to alter the parsed response.

## Admission, aliasing, and cleanup

Before writing any byte, `WITH` qualifies the complete source and workspace
spans at the caller-memory boundary. The source must be nonempty, no larger
than the JSON document bound, stable for the entire operation, and disjoint
from the complete workspace. The callback must be a valid execution token;
preflight rejects zero but cannot establish that an arbitrary nonzero cell is
executable. The context is an opaque cell and may be zero.

Preflight failures return `( 0 response-status )` without changing the
workspace. This distinction is intentional: an unqualified workspace cannot
be safely cleared, and a source/workspace alias cannot be cleared without
destroying the input. The caller remains responsible for any sensitive bytes
already present in a workspace rejected during preflight.

Once admitted, the complete workspace is wiped before staging begins and again
before `WITH` returns. That final wipe occurs after successful parsing and
callback return, ordinary parse rejection, callback failure, or a caught
internal throw. An unexpected admitted throw outside the callback is converted
to `OAUTH2-TOKEN-RESPONSE-S-INTERNAL` after cleanup. A failure of the mandatory
wipe itself propagates rather than being reported as a successfully scrubbed
ordinary status.

The input source is borrowed and is never wiped by this component. Token
responses are credentials, so the transport owner must separately scrub or
release its receive buffer. Any credential storage populated by the callback
likewise remains the caller's responsibility.

The module has no mutable global operation state. Concurrent uses require
independent source ownership, workspaces, callback contexts, and credential
destinations.

## Caller responsibilities

A caller must:

- provide an exclusively owned workspace and keep the disjoint source stable
  until `WITH` returns;
- supply a valid callback with the exact documented stack effect;
- consume, copy, or install every credential it needs while the callback view
  remains live;
- apply authorization-server, token-type, scope, identity, clock, and expiry
  policy above this syntax boundary; and
- scrub the transport buffer and any caller-owned credential copies when their
  respective owners release them.

## Status model

Use `OAUTH2-TOKEN-RESPONSE-STATUS-VALID?` to validate a status value.

| Status | Meaning |
| --- | --- |
| `OAUTH2-TOKEN-RESPONSE-S-OK` | The response validated and the callback returned normally |
| `OAUTH2-TOKEN-RESPONSE-S-INVALID` | Invalid argument, empty document, null callback, or invalid/no-longer-live view |
| `OAUTH2-TOKEN-RESPONSE-S-CAPACITY` | Document, member, name, or decoded-field bound exceeded |
| `OAUTH2-TOKEN-RESPONSE-S-ALIAS` | The source overlaps the operation workspace |
| `OAUTH2-TOKEN-RESPONSE-S-JSON` | Strict JSON, UTF-8, Unicode, or nesting rejection |
| `OAUTH2-TOKEN-RESPONSE-S-MISSING` | A required response member or requested optional view member is absent |
| `OAUTH2-TOKEN-RESPONSE-S-TYPE` | A recognized member has the wrong JSON type |
| `OAUTH2-TOKEN-RESPONSE-S-VALUE` | A recognized member is empty or violates its field grammar |
| `OAUTH2-TOKEN-RESPONSE-S-DUPLICATE` | A duplicate decoded JSON member name was found |
| `OAUTH2-TOKEN-RESPONSE-S-CALLBACK` | The callback threw or violated its stack contract |
| `OAUTH2-TOKEN-RESPONSE-S-INTERNAL` | An admitted invariant failed or a non-callback operation threw |
| `OAUTH2-TOKEN-RESPONSE-S-RANGE` | A public span is outside the caller-memory range |
| `OAUTH2-TOKEN-RESPONSE-S-PROTECTED` | A public span aliases protected platform storage |
| `OAUTH2-TOKEN-RESPONSE-S-PLATFORM` | Caller-span qualification failed at the platform boundary |

Consumers should check `response-status` before interpreting
`callback-status`. Provider- or application-specific requirements—such as an
allowed token type, required scopes, identity binding, expiry calculation, or
durable installation—belong in the callback or in a higher-level component.
