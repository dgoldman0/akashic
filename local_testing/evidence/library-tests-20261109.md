# Tests that judge their libraries — 2026-11-09

The release plan's library inventory (fantasy-engine's `dev/PLAN.md`, Part
1d) gives every Akashic library a status by loading it on the current system
and running its tests. This records what that pass found when the test files
first ran through the test tool (`python3 -m fantasy_engine.testing`): the
test files that could not judge their libraries and how they were repaired,
the libraries that fail and why, and the SPHINCS+ library's two defects and
their repair.

Sixty-nine Akashic test files could not judge their
libraries: fifty counted failures without failing a test, nineteen held no test
that pytest collects, and most matched their expected text against KDOS's echo
of the program. They now fail a test whose check fails, reading only what the
program printed (Akashic 1188fd77, f61886a9, 2bb7ffdc). Thirty-three of them
load their modules from the modules' own REQUIRE lines, which in turn needed
thirteen of the chain's REQUIRE lines to name the folders they meant (Akashic
5648118e). Under the test tool, 43 of the 63 suites run pass, and test_tx passes
its 24 lighter tests. Among the passes are the concurrency primitives, base64,
URL, headers, HTTP, WebSocket, the web server, router and middleware, templates,
string, fmt, UTF-8, the font stack, FFT, tile compositing, the STARK AIR,
Ed25519, consensus, persistence, RPC, sync and cross-chain verification. Twenty
fail on what their libraries do:

- utils/string.f's STR-PARSE-TOKEN returns two cells for empty input where it
  promises four, so the ITC compiler underflows at the end of every source: 18
  ITC tests, and probably the contract VM's eight, which compiles through it.
  The fix is one line.
- concurrency/cvar.f's CV@ consumes its variable before UNLOCK, which then
  releases a garbage lock number. MegaPad's emulator raises a Python TypeError
  for that MMIO offset instead of a bus fault.
- The STARK verifier accepts three tampered traces. Either it leaves the
  boundary constraints unchecked or the tests' tampering still yields a valid
  trace; it needs a careful look.
- The sparse Merkle tree's prove and verify checks run to their step limits, and
  two of its tests call words that no longer exist. The light client and witness
  suites, which use it, fail too, as do block (nine tests), state (two) and node
  (two). The gossip and mempool suites exceed the tool's fifteen-minute limit.
- Taxonomy lookups and the TUI package manifest print memory from wild
  addresses, and the TUI package suite names a constant its module no longer
  defines.
- The SML tree (three tests), state tree (four), LEL (two), profile (two), SIMD
  tile transpose (one) and web request (one) suites expect values their
  libraries no longer give.

The four audio suites still cannot load their modules: their lists are stale,
and 65 REQUIRE lines in the audio modules name the wrong folder (37 write audio/
from inside audio/, 28 name a math module bare).

The SPHINCS+ suite's long runs were a stalled machine, and the library had two
defects (Akashic 81cec03e). SLH-DSA-SHAKE-128s could make neither a key nor a
signature once it was loaded into the userland dictionary, which is how its
tests load it: the BIOS's WOTS accelerator reads its context record from Bank
0, and the module had placed that record in extended memory. Every chain was
refused and the status thrown. An uncaught THROW at KDOS's prompt leaves the
machine idle and silent, and the suite's own run loop went on stepping that
machine toward a budget of 50 or 100 billion steps. With the record moved, the
library verified only its own signatures, because three details of its hash
addresses differed from FIPS 205. With those corrected, its key pair and its
signature of fixed inputs are byte for byte the ones OpenSSL 3.5.2 makes, and
it accepts OpenSSL's signature and refuses an altered one. On the emulator a
key pair costs 142 million guest steps (2 s at the SoC's 100 MHz clock), a
signature 1.94 billion (27 s) and a verification 2.3 million (0.03 s). The
suite now runs on ForthSnapshot: its lighter tests take 43 seconds and the
full roundtrip six minutes, and the transaction suite's two SPHINCS+ tests
pass in about seven minutes each. Two tests of the refactor inventory had kept
the import graph's counts from before 5648118e and failed on main; they expect
the present graph (Akashic 62f42a60).

The other suites' own run loops still lack forth_snapshot.py's stall
detection, so a hung load costs the tool's whole limit; moving them onto
ForthSnapshot would remove about sixty copies of that loop.
