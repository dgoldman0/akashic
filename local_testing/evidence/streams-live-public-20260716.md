# Streams live public TAP qualification — 2026-07-16

This file preserves the chronological qualification of the genuine
`streams-live-public` TAP path after the Streams information-integration
foundation commit `f616011a201114cee2d51e0bd49057a2c9879df0`. The failed runs
are retained as evidence; the final run is the bounded live-network pass and
does not replace the deterministic profiles.

Command, run from the workspace root without `sudo`:

```text
python3 akashic/local_testing/akashic_tui.py smoke \
  --profile streams-live-public --nic-tap mp64tap0 \
  --max-steps 5000000000 --timeout 300
```

Complete bounded harness report:

```text
Built streams-live-public image: /home/kir/Documents/Projects/fantasy-computing/akashic/local_testing/out/akashic-streams-live-public.img
  83 modules linked in 9 chunks, 0 resources, 1 directories
  17 MP64FS entries, 2,097,152 bytes
Smoke streams-live-public: FAIL
  1,950,392,467 steps in 192.91s; screen=100x32; raw=821 bytes; stop=failed
  missing screen markers: STREAMS LIVE PUBLIC PASS
  TAP diagnostics: tx=1 frames/42 bytes; rx=6 frames/909 bytes; errors=0
    first_tx_hex: ff ff ff ff ff ff 02 4d 50 36 34 00 08 06 00 01 08 00 06 04 00 01 02 4d 50 36 34 00 0a 40 00 02 00 00 00 00 00 00 0a 40 00 01
    first_rx_hex: 33 33 00 00 00 16 5a d0 8f 81 d3 16 86 dd 60 00 00 00 00 38 00 01 fe 80 00 00 00 00 00 00 58 d0 8f ff fe 81 d3 16 ff 02 00 00 00 00 00 00 00 00 00 00 00 00 00 16 3a 00 05 02 00 00 01 00 8f 00
    last_tx_hex: ff ff ff ff ff ff 02 4d 50 36 34 00 08 06 00 01 08 00 06 04 00 01 02 4d 50 36 34 00 0a 40 00 02 00 00 00 00 00 00 0a 40 00 01
    last_rx_hex: ff ff ff ff ff ff 5a d0 8f 81 d3 16 08 00 45 00 00 f3 8b 80 40 00 40 11 98 fa 0a 40 00 01 0a 40 00 ff 00 8a 00 8a 00 df cd f5 11 0a 2e 2c 0a 40 00 01 00 8a 00 c9 00 00 20 45 4c 45 4a 46 43 43
    bounded frame trace:
      00 rx len=110: 33 33 00 00 00 16 5a d0 8f 81 d3 16 86 dd 60 00 00 00 00 38 00 01 fe 80 00 00 00 00 00 00 58 d0 8f ff fe 81 d3 16 ff 02 00 00 00 00 00 00 00 00 00 00 00 00 00 16 3a 00 05 02 00 00 01 00 8f 00 de f5 00 00 00 02 04 00 00 00 ff 02 00 00 00 00 00 00 00 00 00 00 00 00 00 fb 04 00 00 00 ff 02
      01 rx len=110: 33 33 00 00 00 16 5a d0 8f 81 d3 16 86 dd 60 00 00 00 00 38 00 01 fe 80 00 00 00 00 00 00 58 d0 8f ff fe 81 d3 16 ff 02 00 00 00 00 00 00 00 00 00 00 00 00 00 16 3a 00 05 02 00 00 01 00 8f 00 de f5 00 00 00 02 04 00 00 00 ff 02 00 00 00 00 00 00 00 00 00 00 00 00 00 fb 04 00 00 00 ff 02
      02 rx len=110: 33 33 00 00 00 16 5a d0 8f 81 d3 16 86 dd 60 00 00 00 00 38 00 01 fe 80 00 00 00 00 00 00 58 d0 8f ff fe 81 d3 16 ff 02 00 00 00 00 00 00 00 00 00 00 00 00 00 16 3a 00 05 02 00 00 01 00 8f 00 de f5 00 00 00 02 04 00 00 00 ff 02 00 00 00 00 00 00 00 00 00 00 00 00 00 fb 04 00 00 00 ff 02
      03 tx len=42: ff ff ff ff ff ff 02 4d 50 36 34 00 08 06 00 01 08 00 06 04 00 01 02 4d 50 36 34 00 0a 40 00 02 00 00 00 00 00 00 0a 40 00 01
      04 rx len=42: 02 4d 50 36 34 00 5a d0 8f 81 d3 16 08 06 00 01 08 00 06 04 00 02 5a d0 8f 81 d3 16 0a 40 00 01 02 4d 50 36 34 00 0a 40 00 02
      05 rx len=280: ff ff ff ff ff ff 5a d0 8f 81 d3 16 08 00 45 00 01 0a 8b 7f 40 00 40 11 98 e4 0a 40 00 01 0a 40 00 ff 00 8a 00 8a 00 f6 db e4 11 0a 2e 2b 0a 40 00 01 00 8a 00 e0 00 00 20 45 4c 45 4a 46 43 43 4e 45 42 45 46 46 43 45 50 43 4e 44 42 44 48 43 4e 46 4a 45 45 43 41 41 41 00 20 46 48 45 50 46
      06 rx len=257: ff ff ff ff ff ff 5a d0 8f 81 d3 16 08 00 45 00 00 f3 8b 80 40 00 40 11 98 fa 0a 40 00 01 0a 40 00 ff 00 8a 00 8a 00 df cd f5 11 0a 2e 2c 0a 40 00 01 00 8a 00 c9 00 00 20 45 4c 45 4a 46 43 43 4e 45 42 45 46 46 43 45 50 43 4e 44 42 44 48 43 4e 46 4a 45 45 43 41 41 41 00 20 41 42 41 43 46
  captures: /home/kir/Documents/Projects/fantasy-computing/akashic/local_testing/out/smoke-streams-live-public.[txt|raw.txt|cells.json|png]
  recent guest output:

    Megapad-64 Forth BIOS v1.0
    RAM: 00100000 bytes
     ok

    ------------------------------------------------------------
      KDOS v1.1 — Kernel Dashboard OS
    ------------------------------------------------------------
     Type HELP for commands, HELP <word> for details.
     Type SCREENS for interactive TUI (or N SCREEN for screen N).
     Type TOPICS or LESSONS for documentation.
     MP64FS loaded
     Running autoexec.f...
    [akashic] loading public Streams qualification
    STREAMS LIVE PUBLIC STARTED
    STREAMS LIVE PUBLIC EXCHANGE FAIL
    STREAMS LIVE PUBLIC DIAG live=3 /0  reqgen=1  source=0  feed=0  items=0  op=1 /0 /0  svc=8492566 /0  paf=2 /0 /0  http=0  paf_cleanup=0  body=0  hbuf=6 /1 /0  parser=0  tls=1 /0 /0  ctx=2760656  native=0 /0  tls_owner=8512310  tcb=0 /256
    STREAMS LIVE PUBLIC FAIL exercise=-1  cleanup=0
    >
```

## Current-tree rerun after foundation cleanup

The same command was rerun after the MP64FS, reusable syndication, and target
admission foundations reached their final qualified state.  It again opened
the real TAP device and failed boundedly, this time with the transport phase
included in the guest diagnostic:

```text
Built streams-live-public image: /home/kir/Documents/Projects/fantasy-computing/akashic/local_testing/out/akashic-streams-live-public.img
  83 modules linked in 9 chunks, 0 resources, 1 directories
  17 MP64FS entries, 2,097,152 bytes, 1509 free sectors
Smoke streams-live-public: FAIL
  1,961,181,435 steps in 286.51s; screen=100x32; raw=817 bytes; stop=failed
  missing screen markers: STREAMS LIVE PUBLIC PASS
  TAP diagnostics: tx=1 frames/42 bytes; rx=7 frames/742 bytes; errors=0
    first_tx_hex: ff ff ff ff ff ff 02 4d 50 36 34 00 08 06 00 01 08 00 06 04 00 01 02 4d 50 36 34 00 0a 40 00 02 00 00 00 00 00 00 0a 40 00 01
    first_rx_hex: 33 33 00 00 00 16 5a d0 8f 81 d3 16 86 dd 60 00 00 00 00 38 00 01 fe 80 00 00 00 00 00 00 58 d0 8f ff fe 81 d3 16 ff 02 00 00 00 00 00 00 00 00 00 00 00 00 00 16 3a 00 05 02 00 00 01 00 8f 00
    last_tx_hex: ff ff ff ff ff ff 02 4d 50 36 34 00 08 06 00 01 08 00 06 04 00 01 02 4d 50 36 34 00 0a 40 00 02 00 00 00 00 00 00 0a 40 00 01
    last_rx_hex: 01 00 5e 00 00 fb 5a d0 8f 81 d3 16 08 00 45 00 00 6a 40 15 40 00 ff 11 50 31 0a 40 00 01 e0 00 00 fb 14 e9 14 e9 00 56 40 9a 00 00 00 00 00 02 00 00 00 00 00 00 25 48 50 20 4f 66 66 69 63 65
    bounded frame trace:
      00 rx len=110: 33 33 00 00 00 16 5a d0 8f 81 d3 16 86 dd 60 00 00 00 00 38 00 01 fe 80 00 00 00 00 00 00 58 d0 8f ff fe 81 d3 16 ff 02 00 00 00 00 00 00 00 00 00 00 00 00 00 16 3a 00 05 02 00 00 01 00 8f 00 de f5 00 00 00 02 04 00 00 00 ff 02 00 00 00 00 00 00 00 00 00 00 00 00 00 fb 04 00 00 00 ff 02
      01 rx len=110: 33 33 00 00 00 16 5a d0 8f 81 d3 16 86 dd 60 00 00 00 00 38 00 01 fe 80 00 00 00 00 00 00 58 d0 8f ff fe 81 d3 16 ff 02 00 00 00 00 00 00 00 00 00 00 00 00 00 16 3a 00 05 02 00 00 01 00 8f 00 de f5 00 00 00 02 04 00 00 00 ff 02 00 00 00 00 00 00 00 00 00 00 00 00 00 fb 04 00 00 00 ff 02
      02 rx len=110: 33 33 00 00 00 16 5a d0 8f 81 d3 16 86 dd 60 00 00 00 00 38 00 01 fe 80 00 00 00 00 00 00 58 d0 8f ff fe 81 d3 16 ff 02 00 00 00 00 00 00 00 00 00 00 00 00 00 16 3a 00 05 02 00 00 01 00 8f 00 de f5 00 00 00 02 04 00 00 00 ff 02 00 00 00 00 00 00 00 00 00 00 00 00 00 fb 04 00 00 00 ff 02
      03 rx len=110: 33 33 00 00 00 16 5a d0 8f 81 d3 16 86 dd 60 00 00 00 00 38 00 01 fe 80 00 00 00 00 00 00 58 d0 8f ff fe 81 d3 16 ff 02 00 00 00 00 00 00 00 00 00 00 00 00 00 16 3a 00 05 02 00 00 01 00 8f 00 de f5 00 00 00 02 04 00 00 00 ff 02 00 00 00 00 00 00 00 00 00 00 00 00 00 fb 04 00 00 00 ff 02
      04 tx len=42: ff ff ff ff ff ff 02 4d 50 36 34 00 08 06 00 01 08 00 06 04 00 01 02 4d 50 36 34 00 0a 40 00 02 00 00 00 00 00 00 0a 40 00 01
      05 rx len=42: 02 4d 50 36 34 00 5a d0 8f 81 d3 16 08 06 00 01 08 00 06 04 00 02 5a d0 8f 81 d3 16 0a 40 00 01 02 4d 50 36 34 00 0a 40 00 02
      06 rx len=140: 33 33 00 00 00 fb 5a d0 8f 81 d3 16 86 dd 60 00 65 67 00 56 11 ff fe 80 00 00 00 00 00 00 58 d0 8f ff fe 81 d3 16 ff 02 00 00 00 00 00 00 00 00 00 00 00 00 00 fb 14 e9 14 e9 00 56 72 ef 00 00 00 00 00 02 00 00 00 00 00 00 25 48 50 20 4f 66 66 69 63 65 4a 65 74 20 50 72 6f 20 38 30 32 30
      07 rx len=120: 01 00 5e 00 00 fb 5a d0 8f 81 d3 16 08 00 45 00 00 6a 40 15 40 00 ff 11 50 31 0a 40 00 01 e0 00 00 fb 14 e9 14 e9 00 56 40 9a 00 00 00 00 00 02 00 00 00 00 00 00 25 48 50 20 4f 66 66 69 63 65 4a 65 74 20 50 72 6f 20 38 30 32 30 20 73 65 72 69 65 73 20 5b 30 33 35 39 37 44 5d 05 5f 69 70
  captures: /home/kir/Documents/Projects/fantasy-computing/akashic/local_testing/out/smoke-streams-live-public.[txt|raw.txt|cells.json|png]
  recent guest output:

    Megapad-64 Forth BIOS v1.0
    RAM: 00100000 bytes
     ok

    ------------------------------------------------------------
      KDOS v1.1 — Kernel Dashboard OS
    ------------------------------------------------------------
     Type HELP for commands, HELP <word> for details.
     Type SCREENS for interactive TUI (or N SCREEN for screen N).
     Type TOPICS or LESSONS for documentation.
     MP64FS loaded
     Running autoexec.f...
    [akashic] loading public Streams qualification
    STREAMS LIVE PUBLIC STARTED
    STREAMS LIVE PUBLIC EXCHANGE FAIL
    STREAMS LIVE PUBLIC DIAG live=3 /0  reqgen=1  source=0  feed=0  items=0  op=1 /0 /0  svc=8496690 /0  paf=2 /0 /0  http=0  paf_cleanup=0  body=0  hbuf=6 /1 /0  parser=0  tls=1 /0 /0  phase=5  native=0 /0  tls_owner=8516434  tcb=0 /256
    STREAMS LIVE PUBLIC FAIL exercise=-1  cleanup=0
    >
```

## Classification

- Both initial runs opened TAP successfully and reported no backend errors.
- Guest ARP transmission reached the host in both runs. The captured 42-byte reply is a
  unicast Ethernet/IPv4 ARP reply from `10.64.0.1` to guest `10.64.0.2` with
  matching Ethernet and ARP hardware addresses.
- The current-tree rerun reports KDOS TLS phase `5`,
  `KDOSTLS-PHASE-DNS-BUILD`. This proves the gateway ARP reply was consumed
  and admitted; the bounded stall is now localized to DNS query construction
  or its immediately following cooperative transition.
- No guest IPv4 packet was transmitted in either run. Therefore DNS send and
  response handling, remote-host ARP, TCP allocation, TLS handshake/certificate/hostname
  verification, HTTP, provider admission, feed decoding, and owner commit were
  not reached.
- Provider state `2` is active; buffered HTTP state `6` is opening with pending
  status `1`; KDOS TLS state `1` is opening with zero connector/native errors;
  TCB usage `0/256` confirms that TCP allocation was not reached.
- The first diagnostic did not print the internal connector phase and was
  conservatively localized to ARP reply consumption or the following step.
  The rerun's phase evidence supersedes that localization without claiming a
  DNS builder root cause.
- Cleanup succeeded in both runs with no retained XIO/provider/TLS ownership
  and no TCB.

The test did not weaken certificate or hostname verification and did not add a
blocking fallback.

## Cooperative pump repair

The connector intentionally advances one local phase per poll. The live loop
previously executed `NET-IDLE` immediately after `XIO-TICK` and the Streams
tick. Once the ARP reply advanced the connector to DNS construction, no packet
was pending to wake the CPU for the following poll. Replacing that idle with
`YIELD?` retained cooperative scheduling while allowing adjacent local phases
to run.

The next real-TAP run progressed through DNS, remote ARP, TCP, the authenticated
TLS 1.3 handshake, and the HTTP request. It then failed boundedly after the
server sent authenticated TLS 1.3 `NewSessionTicket` handshake records:

```text
Smoke streams-live-public: FAIL
  approximately 2.1 billion steps in 25.42s; stop=failed
  TAP diagnostics: tx=35 frames/2462 bytes; rx=24 frames/9144 bytes
  provider error: -4704 (TLS post-handshake message rejected)
```

This was a protocol-interoperability failure rather than a certificate or
hostname-verification failure. MegaPad now reassembles, validates, and discards
bounded authenticated `NewSessionTicket` messages while leaving session
resumption unsupported. `KeyUpdate`, `CertificateRequest`, unknown handshake
types, malformed tickets, and invalid fragmentation/interleaving continue to
fail closed.

## Passing current-tree run

After the cooperative pump, TLS ticket handling, and userland networking-loader
repairs, the exact command at the top of this file passed over `mp64tap0`:

```text
Built streams-live-public image: /home/kir/Documents/Projects/fantasy-computing/akashic/local_testing/out/akashic-streams-live-public.img
  83 modules linked in 9 chunks, MegaPad networking, 0 resources, 1 directories
  18 MP64FS entries, 2,097,152 bytes, 1451 free sectors
Smoke streams-live-public: PASS
  2,309,503,523 steps in 30.72s; screen=108x34; raw=535 bytes; stop=ready
  captures: /home/kir/Documents/Projects/fantasy-computing/akashic/local_testing/out/smoke-streams-live-public.[txt|raw.txt|cells.json|png]
```

The guest completion marker was:

```text
STREAMS LIVE PUBLIC PASS checks=23
```

This final-tree revalidation includes general NewSessionTicket extension-type
uniqueness and exception-safe loader cleanup. It establishes the focused
component path through DNS, TCP, authenticated TLS 1.3, HTTP, provider
admission, feed decoding, owner commit, and cleanup. It does not establish the
later Desk-hosted responsiveness/recovery gate. The native TLS diagnostic latch
also preserves a nonzero context error through connector cleanup, so a future
bounded failure can report the native cause after ownership and sensitive
context state have been released.
