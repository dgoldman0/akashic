# Retained resource session

`akashic/interop/resource-session.f` is a caller-owned, activation-local client
session for one semantic RID. It replaces the Daybook-specific shared-document
lens mechanics while remaining neutral about resource content and capability
schemas.

An endpoint-backed session discovers the live Context, resource registry,
request bus, and one caller-named resource service. That named service lends a
neutral `ROFFER` containing its exact RID and owning resource pool; there is no
separate generic-pool service. Initialization validates the offer against the
discovered runtime graph, copies the RID and pool, and never retains the offer
pointer. It then retains the RID through `ROPOOL-ATTACH` before resolving or
borrowing the owner instance. A successful session owns one RACQ token, one
exact authoritative binding, one request envelope, and optional candidate
binding state. Missing or inconsistent endpoint services produce a blocked
session and never fall open to ambient VFS access.

Initialization preflights the complete caller-owned session span before any
write. The output must be non-null, nonwrapping, and disjoint from the borrowed
service-identifier bytes, the live `CINST` and endpoint headers, the exact
`ROFFER` returned by the named service, its pool header and fixed ledgers, and
every Context/CREG/resource-registry/request-bus/policy record reached through
the endpoint or pool. Raw containing spans are protected before their nested
pointers are read; all resulting spans are then protected before a semantic
validator or graph comparison follows them. A malformed relationship therefore
cannot hide an output alias behind an earlier `BLOCKED` result.

The three runtime services are each queried once and staged on the call stack.
The caller-named offer is queried once and last, after every other endpoint
callback, then the complete raw graph is preflighted and validated before reset.
No later callback can exchange the checked offer before its RID and pool are
copied. The implementation uses no shared discovery scratch and performs no
second named-service query. A session embedded in the component's separately
allocated state remains the normal layout; the check does not reject that state
relationship. Alias rejection returns `RSES-S-INVALID` without changing a
session byte.

The session accepts both compact owner protocols and the canonical common
resource contract. It requires `resource.snapshot` with observe effects and
accepts an optional mutating/persisting `resource.replace`. When the descriptor
also has the complete exact RCON surface, the embedded `RCLI` arm is marked
canonical. A compact Daybook null-to-string/string-to-bool contract remains
compact; the session does not reinterpret or normalize it.

## Modes and operations

```forth
RSES-M-DIRECT   RSES-M-ACTIVE   RSES-M-BLOCKED   RSES-M-STALE

RSES-CLEAR       ( session -- )
RSES-INIT        ( service-a service-u instance session -- status )
RSES-FINI        ( session -- status )
RSES-VALID?      ( session -- flag )
RSES-HELD?       ( session -- flag )

RSES-PREPARE            ( capability principal session -- status )
RSES-CANDIDATE-PREPARE  ( capability principal session -- status )
RSES-DISPATCH           ( session -- cbus-status )
RSES-ADVANCE            ( session -- status )

RSES-CANDIDATE-ATTACH ( reference session -- status )
RSES-CANDIDATE-COMMIT ( session -- status )
RSES-REFRESH-N        ( session attempts -- status )
RSES-REFRESH          ( session -- status )
```

`RSES-CLEAR` is safe initialization for fresh or already-finalized caller
storage, not a substitute for `RSES-FINI`. It is null- and span-safe and becomes
a no-op when a valid session still contains either an allocated request or a
held/releasing acquisition token. `RSES-INIT` independently rejects such live
storage with `RSES-S-INVALID`, preserving it byte for byte so the caller can
finalize it normally. The unconditional byte reset is private to the session
implementation and is used only after successful release or validated fresh
storage.

An instance without an endpoint is `DIRECT`, preserving an applet's explicit
non-Desk control path. A complete endpoint produces `ACTIVE`; an attached but
incomplete or invalid runtime produces `BLOCKED`. `STALE` is sticky for normal
requests. Only explicit refresh or a successfully committed exact candidate
can make it active again.

Candidate attachment lets an editor snapshot another exact revision before
replacing its authoritative binding. The candidate is restricted to the
retained RID and exact retained owner instance. This supports Pad's transactional
open/switch behavior without putting buffer, tab, selection, or UI policy into
interop.

`RSES-PREPARE` stamps the reusable request from the authoritative binding;
`RSES-DISPATCH` still traverses the ordinary request bus and its policy,
authority, schema, generation, and revision checks. The session does not grant
authority merely because discovery or retention succeeded.

## Commit and recovery boundary

After a successful owner operation, `RSES-ADVANCE` advances the local binding
and copies its exact reference. The advance callback is replaceable so tests
and specialized clients can characterize the post-commit failure boundary.
If replacement committed but local advancement fails, the session returns
`RSES-S-COMMITTED-STALE`, clears the unusable local binding/reference, enters
`STALE`, and retains its token. The caller must not repeat the already-durable
mutation; explicit refresh recovers the authoritative revision.

Finalization delegates to `RACQ-DETACH`. A release failure returns
`RSES-S-RELEASE` while preserving the exact request, token, and binding for
retry. The session is cleared only after release succeeds. All storage is
caller-owned except the one request envelope allocated for an active session.
