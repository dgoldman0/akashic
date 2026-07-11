# MegaPad TLS Transport

`akashic/net/transports/megapad-tls.f` binds Akashic's caller-owned `NIO`
byte-stream port to MegaPad/KDOS DNS, TCP, and authenticated TLS 1.3 services.
It contains no HTTP, credential, Agent, provider, Desk, TUI, emulator, or host
bridge code.

```forth
REQUIRE net/transports/megapad-tls.f
```

## Lifecycle

```forth
CREATE transport MPTLS-SIZE ALLOT

transport MPTLS-INIT
S" api.openai.com" 443 transport MPTLS-CONFIGURE THROW

transport MPTLS.PORT NIO-OPEN
\ Use transport MPTLS.PORT with HREQ-SEND-STEP or HSTR-PUMP.
transport MPTLS.PORT NIO-CLOSE
```

`MPTLS-CONFIGURE` accepts one validated DNS hostname of at most 64 bytes and a
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
KDOS trust store. `MPTLS-NEW`/`MPTLS-FREE` are available for heap ownership;
`MPTLS-INIT` supports embedded or static descriptors.

KDOS currently shares its TLS handshake, SNI, record, and receive scratch.
`megapad-tls.f` therefore permits one active adapter at a time and reports
`MPTLS-E-BUSY` to another opener. This is an explicit machine-layer limit, not
a provider or Desk policy. Concurrent TLS requires descriptor-owned KDOS record
state in a later MegaPad change.

## Diagnostics

`MPTLS.STATE`, `MPTLS.LAST-ERROR`, `MPTLS.CONTEXT`, and `MPTLS.LOCAL-PORT`
remain caller-owned and non-secret. Error constants distinguish invalid
configuration, owner contention, absent trust, DNS failure, connect failure,
authentication failure, I/O failure, and a thrown platform callback.

The operation slots (`MPTLS.DNS-XT` through `MPTLS.STATUS-XT`) default to real
KDOS words. They allow deterministic guest tests of this platform adapter; they
do not create a second product transport. The `tls-port` smoke profile verifies
SNI, trust gating, authenticated open, partial I/O, idle/EOF behavior, owner
release, callback faults, retries, and stack balance without external network
access.
