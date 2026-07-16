# Conservative public IPv4 admission

`akashic/net/public-address.f` classifies the four network-order bytes used by
KDOS. Its one public word is:

```forth
ipv4-a PUBLIC-IPV4?  \ ( ipv4-a -- flag )
```

The predicate rejects nonpositive pointers and the conservative non-public
ranges used by Akashic's configured-resource boundary: unspecified and
`0.0.0.0/8`, RFC 1918 private space, shared address space, loopback,
link-local, selected protocol-assignment and transition blocks, documentation,
benchmarking, multicast, and reserved/class-E space. Everything else in the
IPv4 address space is classified as public.

This word performs no DNS, routing, transport, trust, or policy mutation. A
caller must apply it to the address actually selected for a connection, after
resolution and before opening TCP. The native KDOS TLS adapter does this in its
dedicated DNS-admission phase and then connects using the same descriptor-owned
bytes.

The predicate is intentionally conservative and IPv4-only. It is not a route
probe, IP reputation service, proof of endpoint ownership, or substitute for
TLS certificate and hostname verification. Access to a local destination
requires a different, explicitly reviewed connector policy; it is never
inferred from source configuration.

Run the deterministic range and integration contracts with:

```sh
python3 local_testing/akashic_tui.py smoke --profile http-target-contracts
python3 local_testing/akashic_tui.py smoke --profile tls-port
```
