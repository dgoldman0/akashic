# OAuth 2 error-response callback

`akashic/security/oauth2/error-response.f` is a generic, standalone decoder
for OAuth 2 JSON error responses in the RFC 6749 token-error format. It
performs strict JSON and field validation, exposes the decoded result only
through a callback, and wipes its complete caller-owned workspace before
returning from every admitted operation.

The component does not perform HTTP, select an endpoint, classify status
codes, follow redirects, retry requests, manage DPoP nonces, or interpret
provider-specific error codes. It contains no AT Protocol or Streams policy.
PAR and token-exchange owners can therefore apply the same syntax boundary
without coupling this library to either flow.

## Recognized members

The input must be one complete JSON object:

| Member | Requirement and validation |
| --- | --- |
| `error` | Required, nonempty JSON string; 1–256 decoded RFC 6749 `NQSCHAR` bytes |
| `error_description` | Optional; when present, a nonempty JSON string of at most 1024 decoded `NQSCHAR` bytes |
| `error_uri` | Optional; when present, an RFC 3986 URI-reference of at most 4096 decoded bytes; the empty reference is valid |

The published capacity constants are:

```forth
OAUTH2-ERROR-VIEW-ERROR-CAPACITY
OAUTH2-ERROR-VIEW-DESCRIPTION-CAPACITY
OAUTH2-ERROR-VIEW-URI-CAPACITY
```

`NQSCHAR` is ASCII `0x20`–`0x21`, `0x23`–`0x5b`, or `0x5d`–`0x7e`.
It excludes the quote and reverse-solidus bytes; JSON escapes are decoded
before this grammar is applied. The decoder never truncates a field. An
over-capacity decoded field is a capacity failure. An empty `error` or
`error_description`, or an invalid recognized-field grammar, is a value
failure.

`error_uri` is validated as an RFC 3986 URI-reference, not merely as printable
text. The validator checks scheme, authority, path, query, fragment,
percent-triplet, IPv4, bracketed IPv6, and IPvFuture syntax. Relative,
query-only, fragment-only, and present-empty references are valid because
RFC 6749 specifies `URI-reference`; explicit presence metadata distinguishes
an empty reference from an absent member. Deciding whether to resolve,
display, or allow a particular scheme remains caller policy. Consumers must
not automatically fetch an untrusted `error_uri`.

All other members are unknown extensions. They are ignored only after their
names and complete values have passed strict JSON validation. The parser still
rejects malformed UTF-8, invalid escapes or Unicode scalar values, trailing
input, excessive nesting, and duplicate decoded member names. Duplicate
checking also applies to unknown members and nested extension objects.

The root object is limited to 16 members, 1024 aggregate decoded member-name
bytes, and the JOSE JSON document bound of 65536 source bytes. Exceeding a
resource bound is a capacity failure.

## Callback API

Allocate an 8-byte-aligned workspace of at least the published size:

```forth
OAUTH2-ERROR-RESPONSE-WORKSPACE-SIZE  \ 15864 bytes

OAUTH2-ERROR-RESPONSE-WORKSPACE-CLEAR
( workspace -- status )
```

Then invoke:

```forth
OAUTH2-ERROR-RESPONSE-WITH
( source source-u callback context workspace
  -- callback-status response-status )
```

The callback has this stack effect:

```forth
( view context -- callback-status )
```

`OAUTH2-ERROR-RESPONSE-WORKSPACE-CLEAR` explicitly clears a dormant
workspace. It first qualifies the complete span and checks 8-byte alignment.
An admitted workspace is wiped and returns
`OAUTH2-ERROR-RESPONSE-S-OK`; an unqualified or misaligned address returns its
admission status without changing memory. The caller must provide exclusive
ownership just as it does for `WITH`.

After the complete response has validated, `WITH` invokes the callback exactly
once. The callback receives the supplied context cell unchanged and may return
any one-cell application status. `WITH` does not interpret that cell: after a
normal callback return it becomes `callback-status`, and `response-status` is
`OAUTH2-ERROR-RESPONSE-S-OK`.

If admission or parsing fails, the callback is not invoked and
`callback-status` is zero. If the callback throws or does not consume exactly
its two arguments and return exactly one cell, `callback-status` is zero and
`response-status` is `OAUTH2-ERROR-RESPONSE-S-CALLBACK`. The boundary checks
both net depth and a private guard immediately below the callback arguments,
so over-consuming a caller cell and returning compensating cells is rejected.

For example:

```forth
CREATE oauth-error-work-storage
    OAUTH2-ERROR-RESPONSE-WORKSPACE-SIZE 7 + ALLOT

: oauth-error-work  ( -- aligned-address )
    oauth-error-work-storage 7 + -8 AND ;

: classify-oauth-error  ( view exchange -- callback-status )
    \ Inspect/copy the error and optional diagnostic fields here.
    2DROP 0 ;

source source-u ['] classify-oauth-error exchange oauth-error-work
OAUTH2-ERROR-RESPONSE-WITH
```

## Ephemeral view

The callback can inspect the view with:

```forth
OAUTH2-ERROR-VIEW-ERROR@
( view -- address length status )

OAUTH2-ERROR-VIEW-DESCRIPTION@
( view -- address length status )

OAUTH2-ERROR-VIEW-URI@
( view -- address length status )
```

The required error accessor succeeds for every valid view. Optional accessors
return `OAUTH2-ERROR-RESPONSE-S-MISSING` with a zero address and zero length
when their member was absent. A present-empty `error_uri` instead returns
`OAUTH2-ERROR-RESPONSE-S-OK` with a zero length; its address remains borrowed
and must not be used after the callback.

The view and every returned span point inside the operation workspace and are
valid only during the callback. The final wipe invalidates the view magic, so
retaining the view or field addresses after the callback is an error; a later
accessor call returns `OAUTH2-ERROR-RESPONSE-S-INVALID`. Copy any value needed
by an exchange owner while the callback runs. Treat the view as read-only.

## Admission, aliasing, and cleanup

Before writing any byte, `WITH` qualifies the complete source and workspace
spans at the caller-memory boundary. The source must be nonempty, no larger
than the JSON document bound, stable for the whole operation, and disjoint
from the complete workspace. The workspace address must be 8-byte aligned.
The callback must be a valid execution token; preflight rejects zero but
cannot establish that an arbitrary nonzero cell is executable. The context is
an opaque cell and may be zero.

Preflight failures return `( 0 response-status )` without changing the
workspace. This is deliberate: an unqualified workspace cannot be safely
cleared, and clearing an aliased workspace would destroy the input.

Once admitted, the complete workspace is wiped before staging and again before
`WITH` returns. The final wipe occurs after successful parsing and callback
return, ordinary parse rejection, callback failure, or a caught internal
throw. An unexpected admitted throw outside the callback is converted to
`OAUTH2-ERROR-RESPONSE-S-INTERNAL` after cleanup. A failure of the mandatory
wipe itself propagates rather than being reported as successful cleanup.

The borrowed source is never wiped by this component. The HTTP owner remains
responsible for its receive buffer, and the callback owner remains responsible
for any copies it retains. The module has no mutable global operation state;
concurrent uses require independent sources, workspaces, contexts, and
destinations.

## HTTP and profile responsibilities

The exchange owner must decide whether a response is eligible for this
decoder. For OAuth authorization-server endpoints this normally means first
applying the endpoint's allowed HTTP status and JSON media-type policy. The
decoder intentionally does not infer success or failure from an HTTP status.

After decoding, higher layers decide:

- which standard or extension error codes are meaningful;
- whether a particular error permits a protocol-defined retry;
- whether and how to surface the description to a user;
- whether an error URI is safe to resolve or display; and
- how the failure changes transaction, grant, credential, and nonce state.

In particular, recognizing `use_dpop_nonce` and enforcing a one-retry budget
belong to a DPoP-capable exchange owner, not this syntax component.

## Status model

Use `OAUTH2-ERROR-RESPONSE-STATUS-VALID?` to validate a status value.

| Status | Meaning |
| --- | --- |
| `OAUTH2-ERROR-RESPONSE-S-OK` | The response validated and the callback returned normally |
| `OAUTH2-ERROR-RESPONSE-S-INVALID` | Invalid argument, empty document, misaligned workspace, null callback, or invalid/no-longer-live view |
| `OAUTH2-ERROR-RESPONSE-S-CAPACITY` | Document, member, name, or decoded-field bound exceeded |
| `OAUTH2-ERROR-RESPONSE-S-ALIAS` | The source overlaps the operation workspace |
| `OAUTH2-ERROR-RESPONSE-S-JSON` | Strict JSON, UTF-8, Unicode, or nesting rejection |
| `OAUTH2-ERROR-RESPONSE-S-MISSING` | Required `error` is absent, or a requested optional view member was absent |
| `OAUTH2-ERROR-RESPONSE-S-TYPE` | A recognized member has the wrong JSON type |
| `OAUTH2-ERROR-RESPONSE-S-VALUE` | A recognized member is empty or violates its RFC field grammar |
| `OAUTH2-ERROR-RESPONSE-S-DUPLICATE` | A duplicate decoded JSON member name was found |
| `OAUTH2-ERROR-RESPONSE-S-CALLBACK` | The callback threw or violated its stack contract |
| `OAUTH2-ERROR-RESPONSE-S-INTERNAL` | An admitted invariant failed or a non-callback operation threw |
| `OAUTH2-ERROR-RESPONSE-S-RANGE` | A public span is outside the caller-memory range |
| `OAUTH2-ERROR-RESPONSE-S-PROTECTED` | A public span aliases protected platform storage |
| `OAUTH2-ERROR-RESPONSE-S-PLATFORM` | Caller-span qualification failed at the platform boundary |

Consumers must check `response-status` before interpreting
`callback-status`.
