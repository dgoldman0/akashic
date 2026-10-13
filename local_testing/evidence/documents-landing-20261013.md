# Landing pictures, documents and PDFs: the runs — 2026-10-13

Pictures, documents and PDFs land on main as the third of three landings,
in Akashic and MegaPad together. They follow the AT/XRPC driver fixes and
the Daybook scheduler ([its note](daybook-landing-20261013.md)). This note
records the runs that qualify the merged pair.

This is functional regression evidence. The times are the host's, not a
device's, and none of this is UART, panel or touch evidence.

## What lands

| Repository | Commit | Contents |
| --- | --- | --- |
| MegaPad | `04b26c36` | `feature/documents` (`870848cb`) merged over the settable wall clock |
| MegaPad | `79ac6745` | the KDOS load benchmark pinned to the merged core |
| Akashic | `a0ee1c4a` | the provider vertical takes an unsplittable unit as its own checkpoint |
| Akashic | `5121436f` | the Streams manual-refresh fixture gets an 8 MiB disk |
| Akashic | `4f4b7a0a` | `feature/documents` (`c639f54c`) merged over the Daybook landing |
| Akashic | `64001847` | the baseline doc records the documents work's ratchet move |
The runs used Akashic `64001847` and MegaPad `79ac6745`, both clean.
The physical runs' `bindings.json` record the full hashes, the native
extension (SHA-256 `5a06333a…`), the launcher and the font.

## Conflicts and how they were resolved

Six files conflicted in each repository, and every resolution has a check
behind it:

- **MegaPad**: each conflict was a count that both branches moved. The
  BIOS chain has 550 entries, with a catalogued subtotal of 400. The
  simulator core has 447 words, with the seven new ones at its frontier
  in landing order. The dictionary-index growth test runs 754, 13 filler
  words, then 776. Both branches had given their new words catalog
  numbers 545 and 546, so the AES pair is now 547 and 548. Older
  duplicate numbers in that historical catalog are unchanged from main.
  The simulator suite, the BIOS chain-count and SHA-2 classes, and the
  load test check these counts.
- **Akashic**: `build_image` keeps both branches' new lines. An HTTP
  resource is 48,936 bytes, checked in the guest by
  `http-resource-contracts`. The L0 baseline is measured afresh at 693
  modules and 2,523 edges. Both sets of new applet-journey tests stay.

Found and fixed while qualifying:

- MegaPad's KDOS load benchmark pins its core-word and index counts, and
  no test runs it. The merge left it at 442 and 1,902. Measured, the
  values are 447 and 1,907, and the benchmark passes.
- `streams-manual-refresh-contracts` no longer fit its 4 MiB disk with
  both branches' code in Desk. Each branch alone fit. It now has 8 MiB.
- The provider vertical refused `markup/html-entities.f`'s table, one
  28 KB unit that its 12 KB checkpoints could not split. That table now
  forms a checkpoint of its own, still under the stage's step ceiling.
- The documents branch never wrote its ratchet section. It is written
  now.

## Runs

Each run ran alone, after an uncapped wait for other sessions' heavy
runs.

| Run | Backend | Result | Steps or time | Peak memory |
| --- | --- | --- | --- | --- |
| MegaPad simulator suite | host | pass, 2,979 tests | 126 s | 140 MB |
| MegaPad focused emulator classes (BIOS SHA-2, TACC, entropy, KDOS AES, RTC, epoch, TIME_WAIT, CBC, SHA-384, differentials) | emulator | pass, 110 tests | 29 s | 1.1 GB |
| MegaPad rich-terminal, session and benchmark tests | host | pass, 2,122 tests | 123 s | 1.0 GB |
| MegaPad dual-backend rich-terminal oracles | simulator, emulator | pass, 5 and 3 tests | 5 s | |
| MegaPad KDOS load benchmark | simulator | pass | 0.7 s | |
| L0 inventory and L1 functional baseline checks | host | pass | | |
| Structural, journey-logic and packaging tests (8 files) | host | pass, 237 tests | 61 s | 278 MB |
| Image builds, every profile | host | pass, 166 images | | |
| AT/XRPC static checks (10 drivers) | host | pass | | |
| `http-resource-contracts` smoke | emulator | pass | 0.25 billion steps, 30 s | 228 MB |
| `desk-service-table-contracts` smoke | emulator | pass | 1.63 billion steps, 77 s | 230 MB |
| `test_applet_host.py` (applet host contracts) | emulator | pass | 0.77 billion steps, 46 s | 213 MB |
| `streams-manual-refresh-contracts` smoke, `--timeout 900` | emulator | pass | 2.87 billion steps, 160 s | 238 MB |
| `daybook` smoke | emulator | pass | 1.28 billion steps, 53 s | 239 MB |
| `daybook-contracts` smoke | emulator | pass | 0.96 billion steps, 52 s | 231 MB |
| `grid-eval` smoke | emulator | pass | 0.79 billion steps, 46 s | 230 MB |
| `grid-contracts` smoke | emulator | pass | 0.82 billion steps, 48 s | 232 MB |
| `fexplorer` smoke, `--timeout 900` | emulator | pass | 2.97 billion steps, 165 s | 243 MB |
| `desktop-daybook-reminders` smoke | emulator | pass | 3.00 billion steps, 262 s | 530 MB |
| `desktop-daybook-agent` smoke | emulator | pass | 4.68 billion steps, 273 s | 316 MB |
| `desktop-daybook-agent-recovery` smoke | emulator | pass | 2.65 billion steps, 330 s | 743 MB |
| `desktop-daybook-agent-document` smoke | emulator | pass | 8.53 billion steps, 516 s | 315 MB |
| `test_at_xrpc_exchange.py --vertical` | emulator | pass, 75 stages | 1.17 billion steps, 43 s | 209 MB |
| `test_at_xrpc_feed_vertical.py --vertical` | emulator | pass, 199 stages | 1.81 billion steps, 64 s | 214 MB |
| `test_at_bidirectional_vertical.py --vertical` | emulator | pass, 41 stages | 1.62 billion steps, 59 s | 213 MB |
| `test_create_record.py --vertical` | emulator | pass, 30 stages | 1.05 billion steps, 38 s | 211 MB |
| `test_at_xrpc_auth_read.py --vertical` | emulator | pass, 118 stages | 1.41 billion steps, 26 s | 209 MB |
| `test_at_authenticated_provider_vertical.py --vertical` | emulator | pass, 304 stages | 2.65 billion steps, 102 s | 218 MB |
| `test_network_hostname_capacity.py --lifecycle` | emulator | pass, 16 stages | 0.16 billion steps, 6 s | 201 MB |
| `test_at_par_p256.py --vertical` | emulator | pass, 115 stages | 1.07 billion steps, 19 s | 209 MB |
| `test_at_token_p256.py --vertical` | emulator | pass, 147 stages | 1.74 billion steps, 32 s | 209 MB |
| `test_atproto_did_document.py --lifecycle` | emulator | pass, 10 stages | 0.15 billion steps, 6 s | 139 MB |
| `test_atproto_identity_syntax.py --lifecycle` | emulator | pass, 4 stages | 0.07 billion steps, 3 s | 138 MB |
| `test_atproto_nsid.py --lifecycle` | emulator | pass, 6 stages | 0.06 billion steps, 3 s | 136 MB |
| `test_dns_txt_message.py` | emulator | pass, 3 stages | 0.09 billion steps, 4 s | 137 MB |
| `test_kdos_dns.py` | emulator | pass, 42 stages | 0.17 billion steps, 4 s | 137 MB |
| `test_oauth2_p256_key.py --lifecycle` | emulator | pass, 12 stages | 0.33 billion steps, 6 s | 204 MB |
| `test_streams_authenticated_applet.py --vertical` | emulator | fails at bundle 87, "Userland dictionary full", as on main | | |
| Desk with only Daybook (`--applet daybook`) | simulator, native executor | pass, 10 frames and 8 inputs | 168.1 s | 503 MB, aggregate |
| Desk with only File Explorer (`--applet fexp`) | simulator, native executor | pass, 37 frames and 36 inputs | 149.0 s | 527 MB, aggregate |
| Canonical Desktop journey | simulator, native executor | pass, 55 frames and 67 inputs | 284.9 s | 553 MB, aggregate |

Compared with the Daybook branch's own runs, the scheduled-run Desk smokes
took 1.5 to 4.4% more steps, the Desk service table contracts 8.6% more,
and the standalone Daybook smokes 7 to 11% more. That is the media layer,
which every UIDL applet now loads through the UIDL engine. Every smoke
stayed within its profile's steps. `fexplorer` and
`streams-manual-refresh-contracts` take longer than the 120 s default
wall-clock timeout on this host, as they already did before this work, so
they ran with `--timeout 900`. No step limit changed.

The AT/XRPC drivers gain stages from the documents work's modules, but no
driver's largest stage changed. The provider vertical's entity-table
checkpoint, 28,362 bytes, is its own stage, `bundle-20-part-01`, and took
11.1 million of its 180 million steps. The provider vertical builds 71
bundles, the largest 64,848 bytes.

`test_streams_authenticated_applet.py --vertical` was not among the
drivers `fix/at-xrpc-tooling` repaired. It stops at bundle 87 with
"Userland dictionary full" on Akashic `0de896b8` with MegaPad `888f3af3`,
on the documents branch alone, on the Daybook landing, and here, the same
way each time. This landing neither causes nor fixes it.

## Not covered

- The two Library fixtures, `library-projection-owner-contracts` and
  `library-applet-functional-contracts`, at about 60 and 50 billion steps
  each. This landing changes no Library code, but Library's closure
  carries the UIDL engine and the media widget.
- The emulator `desktop`, `desktop-agent` and `desktop-agent-hardening`
  smokes. They already failed before this work.
- MegaPad's full `make test` suite. The classes the two branches touched
  ran, and they cover every count the merge combined.
- A real device, a real model provider, UART, panel and touch.
