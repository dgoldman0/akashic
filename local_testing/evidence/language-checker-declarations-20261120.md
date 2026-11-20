# Uroko's checker with declared kinds and strict placement — 2026-11-20

This note records the second measurement of Uroko's checker, the prototype
that `docs/language/checker.md` describes, after four changes the first
round called for. Kinds now come only from declarations written inside
stack comments, as in `( buf: span port: nio-port -- count: u )`.
Variables, tables, values, field offsets and the children of defining words
declare what their cells hold, so a token read from such a slot and
executed takes its declared effect. A length compared with a longer span's
length counts as part of that span. A strict run counts the definitions
whose effect the checker works out from code all the way down, which
release plan decision 32 makes the condition for placing a word on LM1. A
pilot declared the token slots of two networking modules. The first round's
measurement is in
[`language-checker-20261120.md`](language-checker-20261120.md), beside this
note.

## Inputs and runs

The Forth read is Akashic's main at 75dfbc81 for the comparison without
the pilot, and the `checker-declarations` branch at 2fb85fb4 for the
measured state, which adds comments to `akashic/net/io-port.f` and
`akashic/net/transports/kdos-tls-port.f` and changes no other Forth. The
base vocabulary came from MegaPad at 60526b21, whose `bios.asm`,
`docs/BIOS-DICTIONARY.md`, `kdos.f`, `networking.f`, `rich-terminal.f`,
`tools.f` and `graphics.f` are unchanged from 2755c238, the commit the
first round read. As in the first round, the main figures leave `GUARDED`
undefined, and one comparison run defines it.

```
MEGAPAD_ROOT=…/megapad python3 -m toolchain.language.measure --groups library,tests --json head.json --placement lm1.txt
MEGAPAD_ROOT=…/megapad python3 -m toolchain.language.measure --groups library --akashic …/akashic --json main.json
MEGAPAD_ROOT=…/megapad python3 -m toolchain.language.measure --groups library --guarded --json guarded.json
```

Each run does an ordinary and a strict analysis in one Python process, 27
to 33 seconds in all, and starts no emulator or simulator. The first run
also covers the 190 Forth test drivers and examples, whose figures say
little for the reason the first round gave. A per-definition comparison
with the first round ran the first round's checker (Akashic main's
`toolchain`) and this branch's over main's Forth and compared each
definition's result.

## Inferred effects

| Library, plain | Round 1 | Round 2, main's Forth | Round 2, with the pilot |
|---|---:|---:|---:|
| Colon definitions | 44,468 | 44,470 | 44,470 |
| Effect inferred | 42,842 (96.3%) | 43,130 (97.0%) | 43,149 (97.0%) |
| Inferred, matching the comment | 41,834 | 42,085 | 42,104 |
| Inferred, matching with pass-through | 316 | 316 | 316 |
| Inferred, mismatching the comment | 245 | 252 | 252 |
| Inferred, no stack comment | 327 | 356 | 356 |
| Strict run: inferred | — | 36,306 (81.6%) | 36,509 (82.1%) |
| Strict run: qualifying for LM1 | 33,575 grounded (75.5%) | 36,218 (81.4%) | 36,218 (81.4%) |

The two extra definitions come from `desk.f`, which changed between the
commits the rounds read. With `GUARDED` defined, the branch has 47,595
definitions, infers 46,222 (97.1 percent), and qualifies 38,400 (80.7
percent) for LM1.

On main's Forth, round 2 infers 298 definitions that round 1 did not and
fails 12 that round 1 inferred. Of the gains, 248 had failed only because a
word they call failed: a definition that hands a token it was given to an
inlined word such as `WITH-GUARD` now counts as running that token, so
`JSON-WITH-BUILDER`, the root of 121 of round 1's failures, is inlined at
its callers. Another 41 called BIOS words whose effects the dictionary
documents in tables that start with the word, which round 1's reader missed
(433 of the BIOS's 565 words had effects then, 490 now). The other 9 had
left varying depths, most of them because a status tested by
`DUP IF NIP THROW THEN` was thrown without being known nonzero; a branch
now tells every copy of the cell it tested which way it went. Of the
losses, 11 run a callback their callers pass, through another word, and are
now inlined at those callers as such words are; the twelfth,
`_CDA-WITH-ACCESS` (`tui/applets/agent/providers/codex/auth.f`), passes a
token read from a variable to one of those words, which round 1 hid by
trusting the inner word's comment.

The 252 mismatches include 119 comments that count cells in words, as in
round 1, and 7 more than round 1 had, all from definitions that now infer:
`_RPC-M-GET-BLOCK-PROOF`, a defect listed below, and the two dispatch
words in `web/rpc.f` that take its effect account for three, the two
`DRAW-PATH-*` defects of round 1's table for two, and the other two lie in
`request-codec.f`, which the `checker-fixes` branch changes.

## Strict placement

The strict run trusts no stack comment: a definition it cannot infer gives
its callers nothing, recursion must confirm the effect it assumed, and
comments lend no zero or nonzero facts. A definition qualifies when the
strict run infers it and nothing at or below it runs a token whose effect
only a declaration states.

| Library, with the pilot | Count |
|---|---:|
| Strict run infers | 36,509 (82.1%) |
| Qualify for LM1 | 36,218 (81.4%) |
| Inferred, but resting on a typed slot's declared effect | 202 |
| Inferred, but resting on a deferred word | 89 |
| Fail directly, by the categories below | 1,026 |
| Fail through a word that fails | 6,935 |

The 202 resting on typed slots are the pilot's: the NIO and TLS port words
and their callers elsewhere, which the strict run infers only through the
slots' declarations. Under the reading that excludes declared token effects
they add nothing to placement, and the pilot leaves the qualifying count
where it was. The direct failures follow the ordinary run's categories,
led by unknown tokens (464 EXECUTE and 14 CATCH), result depths that vary
(137), tokens given by callers (214, inlined at the call sites), and
undefined words (123). What one failure costs shows in the propagation:

| Root cause of strict-run failures through a callee | Definitions |
|---|---:|
| EXECUTE of an unknown token | 4,913 |
| Result depth varies | 1,241 |
| Deferred word without a declared effect | 534 |
| CATCH of an unknown token | 85 |
| Computed PICK or ROLL depth | 43 |
| Undefined word, loop depth, undocumented BIOS words and the rest | 119 |

| Area | Qualify | Definitions |
|---|---:|---:|
| `tui` | 17,134 | 21,349 |
| `utils` | 2,271 | 3,434 |
| `net` | 2,130 | 2,477 |
| `security` | 2,172 | 2,384 |
| `interop` | 1,778 | 2,225 |
| `atproto` | 1,603 | 1,737 |
| `sandbox` | 1,251 | 1,307 |
| `persistence` | 1,021 | 1,252 |
| `math` | 1,189 | 1,241 |
| `pdf` | 659 | 992 |
| the 21 other areas | 5,010 | 6,072 |

`--placement` writes the 36,218 qualifying library definitions, and 2,633
from the test drivers, one per line with module and line, each time the
measurement runs.

## Why the rest was not inferred

| Category, library, plain | Round 1 | Round 2 |
|---|---:|---:|
| EXECUTE of an unknown token | 607 | 583 |
| Result depth varies | 237 | 233 |
| Undefined word | 139 | 139 |
| CATCH of an input token (callers inline it) | 118 | 133 |
| EXECUTE of an input token (callers inline it) | 65 | 93 |
| BIOS word without a documented effect | 56 | 15 |
| CATCH of an unknown token | 42 | 19 |
| Loop changes the stack depth | 31 | 31 |
| Deferred word without a declared effect | 22 | 25 |
| Return-stack, loop and other rules | 13 | 13 |
| Fails through a callee that fails | 296 | 37 |

Unknown tokens remain the largest cause: 526 of the 583 run a cell read
from memory, and 25 run the token `_VFS-XT` picks from a driver's table by
operation, whose effects differ by operation. The 15 undocumented BIOS
words are `_RELOC-COUNT`, `_RELOC-ACTIVE`, `N-FULL`, `HBW-BASE` and the
terminal-size words, which the dictionary's tables omit.

## Kinds from declarations alone

| Finding class, library | Round 1 | Round 2 |
|---|---:|---:|
| Address used as a number, number used as an address | 1,285 | 4 |
| Managed kind meets plain data, managed-data rules | 85 | 0 |
| Execution token mixed with data, flag used as an address | 4 | 0 |
| Span parts from different spans | 4 | 0 |
| `I` reads a cell parked by `>R`, `R>` takes loop cells | 4 | 4 |
| Token effect differs from a declaration | — | 1 |
| Malformed declaration | — | 0 |

Every round 1 report that rested on a name is gone, and with them five real
defects that names had found: three span pairings, a token kept in a data
cell and a flag passed as a buffer's address. Declarations would find them
again where a module declares its spans and buffers. The 4 address reports
come from code alone: `ST-ROOT ( -- addr flag )` returns a flag above the
root's address, and four callers pass the flag to `CMOVE` as its source,
reading 32 bytes from address 0 or -1 and leaving the root's address on the
stack. Round 1 listed one of them, `WIT-END`; the others are new and listed
below. The token report is a latent defect: `uidl-tui.f` line 1592 binds
`NOOP` to `_UTUI-FOCUS-D`, declared `( -- elem | 0 )`, as a placeholder
until line 3511 binds `UTUI-FOCUS`; a call in between would leave one cell
too few, where the neighbouring placeholders keep their words' effects.

The base vocabulary gives 20 BIOS and KDOS words declared kinds, such as
`COMPARE ( s1: span s2: span -- n: n )`, and the memory primitives check
addresses. Without declarations in the library, kind checks rarely fire,
which is the intended result of reading no kind from a name.

## The pilot

The NIO port (`net/io-port.f`) is a record of an adapter's context and
callbacks, and the KDOS TLS port (`net/transports/kdos-tls-port.f`) embeds
one, keeps callbacks of its own for the socket layer, and installs its
handlers into the NIO port. Both described their callbacks' effects in
comment lists that nothing checked. The pilot declared:

| Declaration | io-port.f | kdos-tls-port.f |
|---|---:|---:|
| Kinds (`nio-port`, `nio-status`, `kdos-tls-port`) | 2 | 1 |
| Callback fields on their offset constants | 10 | 8 |
| Variable holding a record | — | 1 |
| Deferred callbacks' effects | — | 7 |
| Word signatures with kinds | 12 | 4 |

It replaced the two informal lists, so the files shrank by 11 lines, and
six lines grew past 90 characters, the longest to 104, because KDOS's `(`
stops at the end of its line. Comments alone changed: read by KDOS's rules,
the tokens outside comments are the same as before in both files, every
comment closes on its line, and the refactor inventory check passes with
only its line count changed.

| | io-port.f, 44 definitions | kdos-tls-port.f, 89 definitions |
|---|---:|---:|
| Inferred before, after | 31, 41 | 79, 88 |
| Strict run infers before, after | 30, 41 | 55, 88 |
| Qualify for LM1 before, after | 30, 30 | 55, 55 |

Every definition in the two modules now infers except the four that run a
token their callers pass. Across the library the pilot adds 19 inferred
definitions and 203 strict-run ones, 159 of them callers in other modules.
The checker compared all 24 tokens stored into the declared slots, 15 in
these modules and 9 in other adapters, with the slots' declarations, and
all agree; the 7 deferred callbacks' IS bindings agree with their declared
effects too. Writing the declarations took the effects the modules'
comments already stated and gave them kinds; the work was mechanical, and
deciding the kinds of status cells and counts was the only judgment it
needed.

## Defects

Each was confirmed by reading the definition and the effects of the words
it calls. Paths are under `akashic/`. None was changed.

| Where | Word | Defect |
|---|---|---|
| `store/witness.f:169` | WIT-BEGIN | `ST-ROOT ( -- addr flag )`: CMOVE copies from the flag and the root address stays, as round 1 found at line 175 |
| `web/rpc.f:237` | _RPC-M-GET-PROOF | The same `ST-ROOT _RPC-ROOT 32 CMOVE` |
| `web/rpc.f:319` | _RPC-M-GET-STATE-ROOT | The same |
| `web/rpc.f:289-300` | _RPC-M-GET-BLOCK-PROOF | `OVER` reaches the key string's address in place of the block for the height, and a cell below the block for the three roots; the timestamp line passes the block as the key's address |
| `web/rpc.f:357-383` | _RPC-M-VERIFY-PROOF | `JSON-GET-STRING ( addr len -- str-addr str-len )` consumes the cursor, so every later `JSON-NEXT-VALUE` reads the caller's cells |
| `tui/uidl-tui.f:1592` | _UTUI-FOCUS-D | Latent: the placeholder `NOOP` returns nothing where the declared effect returns a cell |

The `web/rpc.f` words are the chain's RPC methods. `_MS-TOOL-RESULT`
(`interop/mcp/server.f:420`) now shows two depths through
`MCP-CALL-ERROR!`, the defect round 1 listed in `interop/mcp/protocol.f`.

## Where the checker misleads

- Kind findings need declarations: Akashic declares almost nothing yet, so
  the checker's kind and span checks reach little beyond literals, `S"`
  strings and the base words, and a defect that names once exposed stays
  hidden until a module declares its kinds.
- A token whose effect depends on an operation code, as the VFS driver
  table's does, has no single declared effect; the checker reports it as
  unknown.
- An address computed from a span by arithmetic loses the span, so the
  checker accepts `a n + u TYPE`, which reads past the end.
- The strict run counts recursion only when the body's inferred effect
  confirms the comment, and a deferred word never qualifies, though IS may
  bind it once at load time.
- The first round's limits on comments that count cells in words, on code
  that uses the return stack as a variable-length stack, and on the Forth
  test drivers hold as before.
