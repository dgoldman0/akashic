# Shared KDOS network owner

`akashic/net/kdos-network-owner.f` is the minimal machine-layer
serialization boundary for transports that operate KDOS's shared NIC receive,
transmit, TCP-table, TLS-record, and handshake state.

```forth
token KDOSNET-CLAIM    \ KDOSNET-S-OK or an exact status
token KDOSNET-OWNER?   \ true only for the exact current owner
token KDOSNET-OPERATE? \ exact owner on core 0
KDOSNET-OWNER@         \ current token, or zero when unowned
token KDOSNET-RELEASE
token xt KDOSNET-WITH  \ claim-status throw release-status
```

A token is a nonzero opaque identity, normally the address of the
caller-owned transport descriptor. The module compares tokens but never dereferences
them. It owns no DNS query, TLS context, socket, credential,
protocol, retry, or application state.

`KDOSNET-CLAIM` and `KDOSNET-RELEASE` are core-0-only mutations. They reject
the zero token. `KDOSNET-CLAIM` returns
`KDOSNET-S-BUSY` whenever any token is already installed—including a repeated
claim by the same token—and otherwise installs the exact token.
`KDOSNET-RELEASE` clears the gate only for that exact token. A missing or
different owner returns `KDOSNET-S-NOT-OWNER` without changing the installed
token. Mutations away from core 0 return `KDOSNET-S-PLATFORM`.

`KDOSNET-OWNER@` and `KDOSNET-OWNER?` are coherent read-only queries on every core.
This lets any lifecycle entry point fail closed when a descriptor remains
owned or quarantined; an off-core query must never be mistaken for proof that
the machine-global transport is detached.

`KDOSNET-OPERATE?` additionally requires core 0. Participating transports use
that predicate immediately before consuming frames or mutating NIC, TCP, or TLS
state. Identity inspection and operational authority are deliberately separate.

`KDOSNET-WITH` is the narrow scope helper for one stack-neutral lower
operation. Its callback has stack effect `( -- )`. A zero execution token is
rejected as `KDOSNET-S-INVALID` before any claim is attempted. For a nonzero
execution token, the helper first claims the supplied owner token. If the claim
fails, the callback is not executed and the result is `( claim-status 0 0 )`.
If the claim succeeds, the helper executes the callback under `CATCH`, then
always attempts `KDOSNET-RELEASE` with the original exact token. Its result is
`( KDOSNET-S-OK throw release-status )`.

The three result cells are intentionally independent. A callback throw does
not hide a release failure, and a release failure does not replace the throw
code. If a callback releases its lease and installs a different token, the
helper reports `KDOSNET-S-NOT-OWNER` for release and leaves that different
owner untouched. Callers must decide how each diagnostic maps into their own
lifecycle status; the owner module does not arbitrate cleanup or recovery.

| Operation | Success | Rejection |
| --- | --- | --- |
| `KDOSNET-CLAIM` | `KDOSNET-S-OK` | `INVALID` for zero, `BUSY` when occupied, `PLATFORM` off core 0 |
| `KDOSNET-RELEASE` | `KDOSNET-S-OK` | `INVALID` for zero, `NOT-OWNER` for a missing/different token, `PLATFORM` off core 0 |
| `KDOSNET-OWNER?` | exact nonzero-token flag | false for zero or a different token |
| `KDOSNET-OPERATE?` | exact-token flag on core 0 | false for the wrong token or any other core |
| `KDOSNET-WITH` | `OK`, callback throw code, exact-release status | `INVALID 0 0` for a zero XT; failed claim, callback throw, and release failure remain separate |

The gate is intentionally nonrecursive and has no queue, forced-release path,
or recovery override. A caller chooses the narrowest lease matching the lower
operation. Independent lower operations should use `KDOSNET-WITH`; transports
that truly require uninterrupted ownership across a multi-step lower lifetime
may use explicit `KDOSNET-CLAIM` and `KDOSNET-RELEASE`. Such a transport claims
only after all fallible preflight work that can occur without lower ownership
and releases only after successful close/abort has detached its lower state.
If cleanup throws, a TCB fingerprint cannot be proven, or release itself cannot
be proven, the descriptor retains enough cleanup evidence and the shared owner
remains quarantined. Another transport must not consume frames or mutate KDOS
network state in that condition.

This is cooperative serialization among code in one image, not a security or
capability boundary. The current token is intentionally observable, and a
misbehaving module can call the public words. Safety depends on every
machine-global KDOS network consumer participating in the contract.

This boundary serializes Akashic's `kdos-dns` and `kdos-tls` adapters against
each other. It does not make the unregistered legacy direct consumers
`net/http.f` and `net/ws.f` safe; production composition must route
machine-global NIC/TCP work through participating transports. Porting those
legacy consumers is outside this owner landing.
