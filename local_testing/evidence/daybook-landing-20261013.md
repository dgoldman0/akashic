# Landing the Daybook scheduler: the runs — 2026-10-13

The Daybook scheduler lands on main as the second of three landings. Its
MegaPad half, the settable wall clock, lands on MegaPad main with it. The
first landing, Akashic's AT/XRPC driver fixes, comes before it, and the
documents pair follows. This note records the runs that qualify the merged
pair.

This is functional regression evidence. The times are the host's, not a
device's, and none of this is UART, panel or touch evidence.

## What lands

| Repository | Commit | Contents |
| --- | --- | --- |
| MegaPad | `71d0d87f` | `feature/daybook-scheduler` (`5f06bc22`) merged into main; the tree is the branch head's |
| Akashic | `0f06693f` | `feature/daybook-scheduler` (`592ee95b`) merged over the AT/XRPC driver fixes; production code is the branch head's |
| Akashic | `910ae100` | the standalone `daybook` and `daybook-contracts` profiles link their modules |
| Akashic | `23c94a71` | the baseline doc records the branch's last two ratchet moves |

The runs used Akashic `23c94a71` and MegaPad `71d0d87f`, both clean.
The physical run's `bindings.json` records the full hashes, the native
extension (SHA-256 `5a06333a…`), the launcher and the font.

Two problems were found and fixed while qualifying:

- **Two standalone Daybook profiles no longer built.** The Daybook
  scheduler's modules push the `daybook` and `daybook-contracts` closures
  past MP64FS's 128-entry directory, at 147 and 146 entries, when each
  module is its own file. The branch was qualified on linked Desk profiles,
  so nothing had built these two. They now link their modules, with the
  same lines `feature/documents` carries for the same reason.
- **The ratchet doc was two moves behind.** The branch's reviewed policy
  moved at `ffef9ef7` and `592ee95b` without a section in
  `docs/refactor/l0-architecture-baseline.md`. The doc now records both.

## Runs

Each run ran alone, after an uncapped wait for other sessions' heavy runs.

| Run | Backend | Result | Steps or time | Peak memory |
| --- | --- | --- | --- | --- |
| MegaPad simulator suite (`make test-simulator`) | host | pass, 2,969 tests | 124 s | 140 MB |
| L0 inventory and L1 functional baseline checks | host | pass | | |
| Structural, journey-logic and packaging tests (8 files) | host | pass, 223 tests | 56 s | 256 MB |
| Image builds, every profile | host | 160 images pass; `daybook` and `daybook-contracts` fixed as above | | |
| `daybook` smoke | emulator | pass | 1,194,200,861 steps, 48.9 s | 239 MB |
| `daybook-contracts` smoke | emulator | pass | 866,279,057 steps, 49.7 s | 227 MB |
| `test_at_xrpc_exchange.py --vertical` | emulator | pass, 72 stages | 1.05 billion steps, 38 s | 200 MB |
| `test_at_xrpc_feed_vertical.py --vertical` | emulator | pass, 183 stages | 1.70 billion steps, 63 s | 205 MB |
| `test_at_bidirectional_vertical.py --vertical` | emulator | pass, 40 stages | 1.60 billion steps, 58 s | 202 MB |
| `test_create_record.py --vertical` | emulator | pass, 29 stages | 1.04 billion steps, 39 s | 202 MB |
| `test_at_xrpc_auth_read.py --vertical` | emulator | pass, 114 stages | 1.38 billion steps, 25 s | 199 MB |
| `test_at_authenticated_provider_vertical.py --vertical` | emulator | pass, 281 stages | 2.55 billion steps, 105 s | 208 MB |
| `test_network_hostname_capacity.py --lifecycle` | emulator | pass, 16 stages | 0.14 billion steps, 5 s | 192 MB |
| `test_at_par_p256.py --vertical` | emulator | pass, 109 stages | 1.04 billion steps, 20 s | 200 MB |
| `test_at_token_p256.py --vertical` | emulator | pass, 141 stages | 1.70 billion steps, 30 s | 199 MB |
| `test_atproto_did_document.py --lifecycle` | emulator | pass, 10 stages | 0.15 billion steps, 6 s | 128 MB |
| `test_atproto_identity_syntax.py --lifecycle` | emulator | pass, 4 stages | 0.07 billion steps, 2 s | 128 MB |
| `test_atproto_nsid.py --lifecycle` | emulator | pass, 6 stages | 0.06 billion steps, 2 s | 129 MB |
| `test_dns_txt_message.py` | emulator | pass, 3 stages | 0.09 billion steps, 4 s | 128 MB |
| `test_kdos_dns.py` | emulator | pass, 42 stages | 0.17 billion steps, 3 s | 128 MB |
| `test_oauth2_p256_key.py --lifecycle` | emulator | pass, 12 stages | 0.33 billion steps, 6 s | 195 MB |
| Canonical Desktop journey | simulator, native executor | pass, 48 frames and 51 inputs | 264.8 s | 523 MB, aggregate |

The AT/XRPC drivers are the ones `fix/at-xrpc-tooling` repaired. Here they
run for the first time over the Daybook scheduler's code, including its
HTTP request that lends its body and its JSON builder that counts what did
not fit. Every stage stayed within its ceiling. Networking boots in its own
stage, at about 258 million of its 300 million steps. The largest other
stages were the OAuth 2 P-256 key lifecycle, at 170.9 million, and the
XRPC exchange, at 156.1 million, both against 180 million.

## Not covered

- The two Library fixtures, `library-projection-owner-contracts` and
  `library-applet-functional-contracts`, at about 60 and 50 billion steps.
  They passed at `ffef9ef7`. This landing adds only the OpenAI sizing
  commit's code to what they ran.
- The emulator `desktop`, `desktop-agent` and `desktop-agent-hardening`
  smokes. They already failed before this work, for reasons this landing
  does not touch.
- A real device, a real model provider, UART, panel and touch.
