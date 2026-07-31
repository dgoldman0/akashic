# Authenticated XRPC request construction

`akashic/atproto/xrpc.f` builds one caller-owned authenticated AT Protocol
query or JSON procedure request. It replaces the former process-global host,
bearer, cursor, URL, and response buffers with explicit owners:

- a ready AT OAuth profile selects the account PDS and issuer;
- an immutable AT OAuth client configuration selects one DPoP-only P-256
  binding;
- a durable generic OAuth session lends the access token and its immutable
  issuer/binding metadata;
- a credential vault lends the private P-256 scalar only to the qualified
  DPoP proof constructor;
- a parsed HTTP target selects one exact PDS XRPC method and query;
- the caller supplies the HTTP request descriptor, request arena, input, and
  transient workspace.

The module owns no transport, TLS connection, response, retry loop, clock,
cursor, repository model, Streams state, or UI state. Its successful output
is a sealed `HREQ` ready for a cooperative transport owner.

## Public API

```forth
AT-XRPC-AUTH-REQUEST-INPUT-SIZE

AT-XRPC-AUTH-REQUEST-I.IAT
AT-XRPC-AUTH-REQUEST-I.VAULT
AT-XRPC-AUTH-REQUEST-I.CONFIG
AT-XRPC-AUTH-REQUEST-I.PROFILE
AT-XRPC-AUTH-REQUEST-I.SESSION
AT-XRPC-AUTH-REQUEST-I.TARGET
AT-XRPC-AUTH-REQUEST-I.NONCE-A
AT-XRPC-AUTH-REQUEST-I.NONCE-U
AT-XRPC-AUTH-REQUEST-I.PROXY-A
AT-XRPC-AUTH-REQUEST-I.PROXY-U
AT-XRPC-AUTH-REQUEST-I.REQUEST-A
AT-XRPC-AUTH-REQUEST-I.REQUEST-CAP
AT-XRPC-AUTH-REQUEST-I.REQUEST
AT-XRPC-AUTH-REQUEST-I.METHOD
AT-XRPC-AUTH-REQUEST-I.BODY-A
AT-XRPC-AUTH-REQUEST-I.BODY-U

AT-XRPC-METHOD-GET
AT-XRPC-METHOD-POST

AT-XRPC-AUTH-REQUEST-INPUT-CLEAR      ( input -- status )
AT-XRPC-AUTH-REQUEST-WORKSPACE-SIZE
AT-XRPC-AUTH-REQUEST-WORKSPACE-CLEAR  ( workspace -- status )
AT-XRPC-AUTH-REQUEST-BUILD            ( input workspace -- status )
```

`IAT` is trusted Unix epoch seconds supplied by the higher operation owner.
`NONCE-A/U`, `PROXY-A/U`, and `BODY-A/U` are optional canonical spans: absent
means `0 0`. `TARGET` is an already parsed `HTARGET`. `METHOD` is exactly
`AT-XRPC-METHOD-GET` or `AT-XRPC-METHOD-POST`. GET requires an absent body;
POST copies the supplied bytes as an `application/json` body and excludes a
query component. `REQUEST` must name fresh all-zero `HTTP-REQUEST-SIZE`
storage, and `REQUEST-A/CAP` names its disjoint caller-owned wire arena. No
body-size policy is imposed beyond the actual capacity of that arena.

## Exact request boundary

`AT-XRPC-AUTH-REQUEST-BUILD` admits the complete caller geometry before changing
request storage. It then:

1. qualifies the immutable client configuration against the ready AT OAuth
   profile and requires public-client method `none`, no client assertion
   algorithm, DPoP binding, and exactly one canonical DPoP P-256 slot;
2. requires `TARGET` to have the exact PDS origin and a top-level
   `/xrpc/<valid-nsid>` request path;
3. captures an active durable-session generation;
4. loans and compares the exact session binding and issuer, then requires
   token type `DPoP` and exact `atproto` membership in the OAuth scope;
5. loans the access token once, builds its `ath`-bound P-256 DPoP proof for
   the exact GET or POST method and query-free `HTARGET-HTU$`, and copies both
   values directly into the caller-owned request;
6. seals the request and verifies that the session generation and active
   phase did not change.

The resulting wire request contains the target's complete request target,
including its query, plus:

```text
Host: <exact PDS authority>
Accept: application/json
Authorization: DPoP <access token>
DPoP: <fresh proof>
atproto-proxy: <service DID#fragment>    # only when supplied
Accept-Encoding: identity
User-Agent: akashic-atproto/1
Connection: close
```

POST additionally carries `Content-Type: application/json`, its exact
`Content-Length`, and the copied caller body. GET is sealed without a body.

The proof HTU excludes the query as required by DPoP even though the HTTP
request target retains it. Non-default HTTPS ports are retained in both the
canonical HTU and `Host`.

## Cleanup and failure evidence

The complete workspace contains the copied binding, proof, proof descriptor,
input snapshot, host scratch, and serial child workspace. It is wiped after
every admitted result and caught throw. Any failure after request
initialization clears the complete request arena, including copied token and
proof bytes, and returns the request descriptor to the all-zero shape required
for an immediate rebuild. The closed status vocabulary preserves capacity,
alias, caller-memory, profile, session, binding, token, target, proof, request,
and stale-generation classes.

The caller-owned `AT-XRPC-EXCHANGE-*` transport owner handles exactly one
fresh-proof retry after a strict PDS `400` or `401 use_dpop_nonce` challenge.
It replaces the retained nonce before rebuilding and treats any second
response as terminal. `PREPARE` copies the target and optional proxy while
borrowing a stable procedure body through terminal wipe; the request arena
receives a fresh copy on each authorized build. `WIRE-STATE@` reports `NONE`,
`UNCERTAIN`, or `RESPONSE` for the current attempt so a repository operation
can distinguish a pre-send failure from response loss without mistaking wire
progress for a confirmed repository effect.

```forth
AT-XRPC-EXCHANGE-PREPARE
  ( iat method target proxy-a proxy-u payload-a payload-u owner -- status )

AT-XRPC-EXCHANGE-WIRE-STATE@
  ( owner -- wire-state status )

AT-XRPC-EXCHANGE-WIRE-NONE
AT-XRPC-EXCHANGE-WIRE-UNCERTAIN
AT-XRPC-EXCHANGE-WIRE-RESPONSE
```

The payload span is a stable caller loan, not embedded storage or a fixed-size
slot. It must remain admitted and byte-stable until `XIO-WIPE` releases it.

See the protocol's
[XRPC and PDS service-proxy specification](https://atproto.com/specs/xrpc)
for the wire conventions.
