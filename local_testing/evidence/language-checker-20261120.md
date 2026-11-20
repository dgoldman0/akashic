# The language checker on all of Akashic's Forth — 2026-11-20

This note records the first measurement of the checker core of Uroko, the
prototype that `docs/language/checker.md` describes. The checker read every
Forth file in Akashic, inferred each colon definition's stack effect,
compared it with the definition's stack comment, and reported misused
kinds, spans and return-stack cells. Samples of each category were
then read to learn which reports are real defects and where the checker's
own rules mislead. The defects are listed with file and line below; none
was changed.

## Inputs and runs

The Forth read is Akashic's at 6d8f5bff, the main commit the
`language-checker` branch starts from; the branch adds only the checker,
whose measured state is c1d02fea. The base vocabulary came from MegaPad at
2755c238, with `bios.asm`, `docs/BIOS-DICTIONARY.md`, `kdos.f`,
`networking.f`, `rich-terminal.f`, `tools.f` and `graphics.f` unmodified in
that checkout. The main figures leave `GUARDED` undefined, as the Desktop
builds do, so the guarded wrappers that `[DEFINED] GUARDED [IF]` blocks
define are skipped; one comparison run defines `-1 CONSTANT GUARDED`, as
some test profiles do.

```
MEGAPAD_ROOT=…/megapad python3 -m toolchain.language.measure --groups library,tests --json plain.json
MEGAPAD_ROOT=…/megapad python3 -m toolchain.language.measure --groups library,tests --guarded --json guarded.json
```

Each run takes about 12 seconds in one Python process and starts no
emulator or simulator. Samples for review were drawn with
`--sample CATEGORY --count N --seed S`, which prints each sampled
definition with its source.

## Inferred effects

The library is the 711 files under `akashic/`. A module is checked against
the base vocabulary and the modules its REQUIRE lines load.

| | Plain | Guarded |
|---|---:|---:|
| Colon definitions | 44,468 | 47,593 |
| Effect inferred | 42,842 (96.3%) | 45,833 (96.3%) |
| Inferred with no comment-only word anywhere below | 33,575 | 37,788 |
| Inferred, matching the comment | 41,834 | 43,726 |
| Inferred, matching with pass-through | 316 | 317 |
| Inferred, mismatching the comment | 245 | 293 |
| Inferred, no stack comment | 327 | 1,374 |
| Inferred, comment declares a variable effect | 73 | 76 |
| Inferred, never returns | 47 | 47 |

The guarded run adds 3,125 wrappers, nearly all without comments, and
infers each from the word it wraps by running `WITH-GUARD`'s body at the
call site. 44,100 library definitions, 99.2 percent, carry a stack comment;
77 of those comments sit on a `\ NAME ( effect )` line above the definition.
1,590 inferred definitions call a word whose effect came only from its
comment, and 9,267 have such a word somewhere below them, which is why the
share inferred all the way down is 75.5 percent of all definitions.

Of the 245 plain mismatches, 119 have comments that count cells in words,
such as `( eight-values -- )` or `( ten-arguments -- persist-status )`;
in the 15 read, the inferred effect was right and the comment could not be
compared cell for cell. The other 126 are wrong comments or real defects.

## Why the rest was not inferred

| Category | Plain | What it means |
|---|---:|---|
| EXECUTE of an unknown xt | 607 | Runs a token read from memory (533), given to an inlined word (17), or returned by a word or joined from two branches (57) |
| Result depth varies | 237 | Paths leave different depths that no known cell tells apart |
| Undefined word | 139 | Uses a word its REQUIRE closure does not define |
| CATCH of an input xt | 118 | Runs a token it was given; callers inline it |
| EXECUTE of an input xt | 65 | The same, through EXECUTE |
| BIOS word without a documented effect | 56 | Calls CRC, NTT, SHA and similar BIOS words the dictionary tables omit |
| CATCH of an unknown xt | 42 | Catches a token read from memory (28) or given to an inlined word (13) |
| Loop changes the stack depth | 31 | A pass leaves a depth other than the one it entered with |
| Deferred word without a declared effect | 22 | Calls a DEFER word that IS has not bound to a known word |
| Computed PICK or ROLL depth | 3 | The depth is not a constant |
| EVALUATE of text | 3 | Runs source text |
| Return stack beyond the definition | 2 | `R>` or `R@` takes the caller's return address |
| Other return-stack and loop rules | 5 | LEAVE outside DO, `R>` inside a loop, a loop that changes the return-stack depth, `SP@`, recursion without a comment |
| Calls a word whose effect is unknown | 296 | Fails because a callee failed; by root cause, 215 CATCH and 60 EXECUTE of unknown tokens |

The 183 words that run a token they are given are not failures for their
callers: 728 inferred definitions call one, and the checker infers each
call by running the word's body with the caller's cells. Of the 139
undefined-word failures, 130 are in `akashic/audio`, where 26 REQUIRE paths
such as `audio/pcm.f` do not resolve against the requiring file's folder,
which is the rule KDOS's loader and `forth_dependencies.py` both apply.

## Findings

| Class | Plain | Reviewed |
|---|---:|---|
| Address used as a number | 527 | 12 sampled with the next class, seed 11: none real |
| Number used as an address | 758 | |
| Managed kind meets plain data | 85 | Comment names `ref` and `handle`; Akashic holds no managed data yet |
| Execution token mixed with data | 3 | All read: 1 real defect, 2 tokens kept in generic cells |
| Flag used as an address | 1 | Read: a real defect |
| Span parts from different spans | 4 | All read: 3 real defects, 1 prefix comparison |
| `I` reads a cell parked by `>R` | 3 | All read: 3 real defects |
| `R>` takes a loop's control cells | 1 | Read: harmless here, as all three cells are dropped |

The number-and-address classes come from names, not code: `cap` names a
capability record in the capability modules and a capacity elsewhere, and
field accessors applied to a zero base compute offsets that then serve as
addresses. Akashic already uses `ref` for resource references (`RREF`) and
`handle` for authority and sandbox value handles, so the 9d kinds collide
with current names.

## Samples read

Every defect below was confirmed by reading the definition, the effects of
the words it calls, and where it mattered the BIOS code for the word in
question (`w_i`, `w_endcase`, `w_leave`, the `'` entry's flags) or KDOS's
definition (`FREE`, `CATCH`).

- **Mismatches other than comments in words**, 20 drawn at seed 20261120
  from the final run: 15 are real defects with 12 distinct causes, 3 are
  comments that write one cell as two words (`glyph run`) or several cells
  as one (`model/u`, `scalars`), and 2 remain unresolved (SOM-NEXT and
  ST-VERIFY-PROOF, whose callees read a cell the reading did not locate).
- **Result depth varies**, 12 drawn at seed 7: 8 real defects, 1 latent
  (a CASE without a default for kinds its callers never pass), and 3
  unresolved in audio and image-builder words whose callees were not read.
- **Return-stack, span, flag and execution-token findings and failures**,
  all read: listed below where real.
- Earlier samples drawn while the checker's rules were being corrected
  found further defects, each reconfirmed against the final rules.

## Real defects

The table holds 46 defects in 36 modules. Paths are under `akashic/`.
Areas that decision 35 leaves out of the first release are marked: audio
and Sound Lab, Worlds (`game/`, `tui/game/`) and data graphics
(`render/visualization/`). The other 40 defects lie in modules the release
may carry, though not every one of those modules is in the Desktop's image,
and several defects sit on error paths that a passing test may never take.

| Where | Word | Defect |
|---|---|---|
| `utils/string.f:370` | STR-PARSE-TOKEN | Blank input exits with 2 cells; the comment promises 4 |
| `math/stats.f:560-562` | STAT-ONLINE-MERGE | When ctx1 is empty, a second `R>` follows one `>R` and takes the return address |
| `utils/yaml.f:1492-1493` | YAML-BUILD-RESET | `'` inside a definition is not immediate: it compiles a call that parses at run time, and `_YAML-DEFAULT-EMIT` and `_YAML-DEFAULT-TYPE` are called instead of named; runs at load, line 1495 |
| `utils/yaml.f:890`, `utils/toml.f:569` | YAML-GET-FLOAT-STR, TOML-GET-FLOAT-STR | `OVER` makes ( a u a ), so the loop walks ( u a ) as a span |
| `utils/json.f:40` | JSON-FAIL | `IF ABORT" …"` takes a second flag from the caller's stack |
| `css/css.f:1219` | CSS-SKIP-VALUE | `_CSS-IDENT-START? ( c -- flag )` already consumed the character, so `DROP` drops the length |
| `css/css.f:1260-1261` | CSS-EXPAND-TRBL | An empty value leaves the cursor under nine zeros: 11 cells, not 9 |
| `net/url.f:500` | URL-QUERY-FIND | Not found leaves `a'` under `0 0 0`: 4 cells, not 3 |
| `net/ws.f:329, 358-359, 363` | WS-FRAME-RECV | `>R >R` leaves buf above max, so the payload is read into the address `max`; a masked frame's third `R>` takes the return address |
| `net/ws.f:234, 236` | WS-FRAME-SEND | `R@` reads the payload address where the comments expect the length; ctx stays on the stack |
| `net/ws.f:527` | WS-RECV | `>R OVER >R` parks max and ctx, not buf and max |
| `web/server.f:104` | _SRV-CLOSE-DEFAULT | `CLOSE ( sd -- ior )`'s status is never dropped, so every close leaves a cell |
| `web/server.f:160` | SRV-INIT | `DUP _SRV-PORT !` leaves the port on every path |
| `interop/codecs/json-schema.f:27` | _CSJ-TYPE-NAME | The CASE default drops the selector and ENDCASE then drops the string length |
| `interop/mcp/protocol.f:117` | MCP-CALL-ERROR! | `MIN DUP _MCERR-N !` leaves the length |
| `sandbox/value.f:1005, 1011` | _SVW-SHAPE-AGGREGATE | Overflow paths `NIP R> DROP 0 …` keep the arithmetic status: 3 cells, not 2 |
| `liraq/uidl.f:837, 839` | UIDL-EVAL-WHEN | `DROP NIP NIP 0` for a null or unknown result overwrites the caller's cell below `elem` |
| `liraq/lel.f:601-603` | _LEL-FN-MOD | The float path's stack picture ( b a floor ) cannot exist after FP32-DIV; ROT takes a cell from below |
| `tui/uidl-tui.f:3837` | _UTUI-CSS-INT | CSS-PARSE-NUMBER always returns 6 cells; the failure path returns 5, not 2 |
| `tui/uidl-tui.f:3984` | _UTUI-CSS-SET-DIM | The same failure path leaves 3 cells |
| `tui/uidl-tui.f:2109` | _UTUI-LAYOUT-MBAR | UIDL-ATTR always returns 3 cells, so a child without a label writes flags through address 0 and leaves cells |
| `tui/widgets/scroll.f:283-287, 320, 337` | SCRL-SCROLL-TO, SCRL-ENSURE-VISIBLE | `R@ SWAP R@` gives the clamp words ( x widget ) for ( widget x ) and leaves cells |
| `tui/widgets/scroll.f:171` | _SCRL-HANDLE | Calls SCRL-SCROLL-BY, which is defined at line 291, so KDOS cannot compile the call; the comments beside it say as much |
| `tui/applets/agent/tool-gateway.f:754-758` | _ATOOLG-POST-ROLLBACK-BODY | The gateway is never dropped: returns ( gateway status ) |
| `tui/applets/agent/auth/api-key.f:31` | _AAK-SET | The CASE default drops the selector, so ENDCASE drops the status |
| `tui/applets/agent/model-context.f:141` | ACTX-NEW | Allocation failure returns 3 cells: `SWAP DROP` keeps the ior |
| `tui/applets/agent/providers/openai/request-codec.f:174` | _OAIB-PREPARE-TOOLS | The `?DUP`'d refresh status stays under `0` |
| `tui/applets/library/persistence-adapter.f:5826` | _LIBPIX-RANGE-ROW | `3 PICK 2 PICK` passes value-a as key-u, so the prefix length check always passes |
| `sml/tree.f:529` | _SOM-SCOPE-INDEX | A stray SWAP stores the caller's cell as the target and leaves the node |
| `sml/tree.f:327, 386` | SML-LAST, SML-PREV | `_DFS-UP DUP _SNL-CUR !` leaves a cell at each upward step |
| `dom/event.f:353` | _DOME-LISTEN-INNER | `DUP >R` leaves the listener address, so DOME-LISTEN and DOME-LISTEN-CAPTURE leak a cell |
| `markup/xml.f:98-99, 105-106` | XML-GET-CDATA | Both CDATA paths leave the cursor under the text: 4 cells, not 2 |
| `math/color.f:572, 578` | COLOR-HEX-PARSE | Malformed `#RGB` returns 5 or 3 cells, not 4 |
| `knowledge/taxonomy.f:548-549` | TAX-CREATE | The descriptor address stays under the returned taxonomy |
| `render/draw.f:659, 677` | DRAW-PATH-QUAD, DRAW-PATH-CUBIC | The flatten words consume the destination, so the cursor is set from the caller's cells |
| `store/smt.f:106-107` | _SMT-INIT | `DUP _smt-init-tree !` then `DUP >R` keeps the tree under the flag, so ST-INIT and NODE-INIT leak cells |
| `store/smt.f:407` | _SMT-INSERT | LEAVE in a BEGIN loop with no DO compiles an UNLOOP that drops the return address |
| `store/smt.f:540` | _SMT-PROVE | An empty tree returns 3 cells: `NIP 0 0` keeps the root |
| `store/light.f:97` | _LC-STATE-PROOF | The rebuild flag stays on the stack and `_SMT-PROVE ( key buf buf-len tree -- proof-len flag )` gets the flag as buf and the proof as tree |
| `store/witness.f:175` | WIT-END | `ST-ROOT ( -- addr flag )`: CMOVE copies from the flag and the root address stays |
| `game/2d/pathfind.f:313` (Worlds) | _AS-BUILD-PATH | Allocation failure returns gx under `0 0` |
| `tui/game/widgets/dialog-box.f:158` (Worlds) | DBOX-RESET | `DUP >R` leaves the widget |
| `tui/game/game-canvas.f:120` (Worlds) | GCVS-NEW | The note "rgn stored" follows a stack picture without a backslash, so KDOS reads `rgn` as a word and the definition does not compile |
| `render/visualization/meter.f:472` (data graphics) | METER-ENERGY-CHART | `I` after `>R` reads the parked colour (BIOS `I` reads a fixed return-stack offset) |
| `render/visualization/waveform.f:386, 392` (data graphics) | _WV-DRAW-ENVELOPE | `I` after `>R` reads the parked y |
| `render/visualization/meter.f:122`, `spectrum.f:133-137`, `waveform.f:115` (data graphics) | METER-, SPEC-, WAVE-CONFIG-FREE | `FREE DROP`: KDOS `FREE ( addr -- )` returns nothing, so DROP takes the caller's cell |

Four modules use a word from a module they never REQUIRE, so loaded alone,
as the image builder's closure would load them, they fail: `pdf/crypt.f`
uses PDF-S-OK from `pdf/filter.f`, `tui/widgets/menu.f` uses KEY-T-SPECIAL
from `tui/keys.f`, `net/ws.f` uses B64-ENCODE from `net/base64.f`, and
`game/2d/tile-physics.f` uses SYS-C-POS.

The checker read KDOS as well, and its inferences there found defects in
MegaPad's `kdos.f`: B.MIN and B.MAX (lines 3098 and 3119) keep the running
minimum or maximum on the stack after the first tile, so later tiles pass
it to TSRC0! instead of the address; DOC and TUTORIAL (lines 6925 and 6930)
leave the 0 from a failed OPEN on the stack; and P.BENCH-PAR (line 7457)
leaves its pipeline.

## Where the checker misleads

- Comments that count cells in words, write one cell as two words, or
  write several cells as one cannot be compared cell for cell; the
  measurement separates the first kind, and the reviews found the others.
- Kinds read from names: the address and number classes are noise, as
  above, and `ref` and `handle` already mean other things in Akashic.
- A prefix of one span compared against another span's length is a real
  idiom (`_SPC-PREFIX?` in `sandbox/profile-codec.f`) that the span rule
  reports.
- Code that is correct but has no fixed effect: YAML-INT uses the return
  stack as a variable-length stack across two loops, and
  `_MTR-CALL-EMITTER` drops cells until DEPTH returns to a saved value.
- STREAMS-PAYLOAD-INIT runs `R> DROP` and then UNLOOP inside a loop; the
  order is wrong, but all three cells are dropped, so it works.
- A THROW whose code is not known to be nonzero is treated as possibly
  returning, so a word that throws only on a path the checker cannot prove,
  such as KDOS's `_KDOS-FAULT`, shows two depths.
- The 190 Forth test drivers and examples (7,454 definitions) lean on words
  their harness profiles load without a REQUIRE, so 59 percent of their
  definitions are undefined to the checker; their figures say little.
