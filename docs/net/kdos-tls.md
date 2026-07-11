# KDOS TLS Transport

`akashic/net/transports/kdos-tls.f` binds Akashic's caller-owned `NIO`
byte-stream port to KDOS DNS, TCP, and authenticated TLS 1.3 services.
It contains no HTTP, credential, Agent, provider, Desk, TUI, emulator, or host
bridge code.

```forth
REQUIRE net/transports/kdos-tls.f
```

## Lifecycle

```forth
CREATE transport KDOSTLS-SIZE ALLOT

transport KDOSTLS-INIT
S" api.openai.com" 443 transport KDOSTLS-CONFIGURE THROW

transport KDOSTLS.PORT NIO-OPEN
\ Use transport KDOSTLS.PORT with HREQ-SEND-STEP or HSTR-PUMP.
transport KDOSTLS.PORT NIO-CLOSE
```

`KDOSTLS-CONFIGURE` accepts one validated DNS hostname of at most 64 bytes and a
remote port from 1 through 65535. `NIO-OPEN` copies the hostname into KDOS SNI,
resolves it, selects an ephemeral local port, requests HTTP/1.1 ALPN, and
accepts the connection only when KDOS reports an established, peer-authenticated
TLS context. The KDOS trust store must already contain an applicable anchor.

`NIO-SEND` and `NIO-RECV` preserve partial progress. A zero-byte receive while
the TLS context is established is idle; a clean close alert maps to
`NIO-S-EOF`; malformed records, authentication loss, invalid callback counts,
and transport faults map to `NIO-S-FAILED`.

## Ownership

The adapter descriptor owns configuration and connection state but not the
KDOS trust store. `KDOSTLS-NEW`/`KDOSTLS-FREE` are available for heap ownership;
`KDOSTLS-INIT` supports embedded or static descriptors.

KDOS currently shares its TLS handshake, SNI, record, and receive scratch.
`kdos-tls.f` therefore permits one active adapter at a time and reports
`KDOSTLS-E-BUSY` to another opener. This is an explicit machine-layer limit, not
a provider or Desk policy. Concurrent TLS requires descriptor-owned KDOS record
state in a later KDOS change.

## Diagnostics

`KDOSTLS.STATE`, `KDOSTLS.LAST-ERROR`, `KDOSTLS.CONTEXT`, and `KDOSTLS.LOCAL-PORT`
remain caller-owned and non-secret. Error constants distinguish invalid
configuration, owner contention, absent trust, DNS failure, connect failure,
authentication failure, I/O failure, and a thrown platform callback.

The operation slots (`KDOSTLS.DNS-XT` through `KDOSTLS.STATUS-XT`) default to real
KDOS words. They allow deterministic guest tests of this platform adapter; they
do not create a second product transport. The `tls-port` smoke profile verifies
SNI, trust gating, authenticated open, partial I/O, idle/EOF behavior, owner
release, callback faults, retries, and stack balance without external network
access.
