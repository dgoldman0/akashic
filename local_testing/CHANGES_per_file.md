# Per-File Change List — Phase 6.6 + Audit

**Date:** 2026-03-08
**Sources:** PLAN_hardening_6.6.md (37 issues) + AUDIT_beyond_6.6.md (30 issues)
**Total:** 66 distinct changes across 17 files (Issue #29 removed — not a bug)

Ordered by execution priority.  Within each file, changes are listed
in the order they should be applied (dependencies first).

Legend:
- `[P##]` = PLAN_hardening_6.6.md issue number
- `[A##]` / `[B##]` / `[C##]` / `[D##]` = AUDIT_beyond_6.6.md finding
- Severity: **CRIT** / **HIGH** / **MED** / **LOW**

---

## Priority 1 — Crypto (must be first; everything signs/verifies through these)

### ~~File 1: `math/ed25519.f`~~ ✅ DONE

| # | ID | Severity | Change | Lines | Status |
|---|-----|----------|--------|-------|--------|
| 1 | P01 | **CRIT** | ~~Constant-time scalar multiply~~ | L191–233 | ✅ `_ED-CT-SELECT` + always-compute SMUL |
| 2 | P02 | **CRIT** | ~~Signature malleability (S < L)~~ | L417 | ✅ `_ED-BYTES-GTE?` check in VERIFY |
| 3 | P04 | **HIGH** | ~~Canonical y decode (y < p)~~ | L286 | ✅ `_ED-BYTES-GTE?` check in DECODE |
| 4 | P03 | **HIGH** | ~~Document `_ED-PINV0` zero-fill~~ | L37–40 | ✅ 3-line comment added |
| 5 | P05 | **MED** | ~~Secret zeroization after sign/verify~~ | L399–438 | ✅ 0 FILL on H64/SC1-3/PA/PB |

**Tests:** 25/25 pass — 15 original + 10 new hardening tests (CT-SMUL, malleability rejection, non-canonical y rejection, zeroization).

---

### ~~File 2: `math/sphincs-plus.f`~~ ✅ DONE

| # | ID | Severity | Change | Lines | Status |
|---|-----|----------|--------|-------|--------|
| 6 | P06 | **CRIT** | ~~WOTS+ checksum nibble extraction~~ | L328 | ✅ Removed `4 LSHIFT`; shifts 8/4/0 now correct |
| 7 | P08 | **MED** | ~~SPX-VERIFY length validation~~ | L749–750 | ✅ Added `sig-len` param; `<> IF FALSE EXIT` |
| 8 | P07 | **MED** | ~~Secret zeroization after keygen~~ | L774 | ✅ `_SPX-RNG-SEED 48 0 FILL` in KEYGEN-RANDOM |
| — | BUG1 | **CRIT** | ~~HT-SIGN buffer clobber~~ | L508 | ✅ Save msg to `_SPX-HT-MSG` before XMSS-SIGN |
| — | BUG2 | **HIGH** | ~~HT-VERIFY wrong OVER~~ | L558 | ✅ Changed `OVER` → `2 PICK` for sig-in |
| — | BUG3 | **HIGH** | ~~XMSS tree-hash ADRS KP residual~~ | L437,L477 | ✅ Added `0 _SPX-ADRS-KP!` after TREE type set |
| — | BUG4 | **HIGH** | ~~FORS-PK-FROM-SIG OVER underflow~~ | L582–617 | ✅ Save sig-in to `_SPX-V-FPKSIG` variable |
| — | BUG5 | **MED** | ~~WOTS-SK-I spurious DUP~~ | L286 | ✅ Removed stack-leaking DUP |

**Tests:** 42/42 pass — 32 original + 4 P06 checksum + 3 P08 sig-len + T33 sign-verify + T34 reject-bad-sig + P07 zeroization.

---

## Priority 2 — Transaction structure (feeds into everything downstream)

### ~~File 3: `store/tx.f`~~ ✅

| # | ID | Severity | Change | Lines | Summary |
|---|-----|----------|--------|-------|---------|
| ~~9~~ | ~~P09~~ | ~~**CRIT**~~ | ~~Hybrid verify: AND not OR~~ | ~~L383–389~~ | ✅ Changed `TX-VERIFY` hybrid path: Ed25519 fail → reject immediately; return SPHINCS+ result. Both must pass. |
| ~~10~~ | ~~A03~~ | ~~**CRIT**~~ | ~~Add `chain_id` to TX structure~~ | ~~struct~~ | ✅ Added 8-byte `chain_id` (offset 112). Layout updated, all offsets shifted, encode/decode updated. |
| ~~11~~ | ~~C05~~ | ~~**MED**~~ | ~~Add fee/gas field to TX structure~~ | ~~struct~~ | ✅ Added 8-byte `fee` (offset 120). TX-SET-FEE rejects negative. |
| ~~12~~ | ~~C06~~ | ~~**MED**~~ | ~~Add TTL / valid-until-block field~~ | ~~struct~~ | ✅ Added 8-byte `valid_until` (offset 128). Combined with chain_id + fee as single layout break. TX-BUF-SIZE 8296→8320. |
| ~~13~~ | ~~P10~~ | ~~**MED**~~ | ~~TX-SET-AMOUNT: reject negative only~~ | ~~~L143~~ | ✅ Added `0<` guard — zero-amount allowed, negative rejected. TX-SET-FEE also guarded. |
| ~~14~~ | ~~P11~~ | ~~**MED**~~ | ~~CBOR encode bounds check~~ | ~~~L200–230~~ | ✅ Added `CBOR-OK?` overflow flag to cbor.f; `_TX-ENCODE-UNSIGNED` checks before returning. |
| — | BUG6 | **HIGH** | ~~Hybrid verify stack clobber~~ | L437–441 | ✅ Save tx to `_TX-HYB-TX` across `_TX-VERIFY-ED` (CATCH clobbers stack cell below return value). |

**Tests:** 40/40 pass.  38 quick + SPX sign-verify + P09 hybrid AND. Test predicate for P09 fixed (line-exact parsing, not full-output split).

---

## Priority 3 — State tree integrity (state and SMT are co-dependent)

### ~~File 4: `store/smt.f`~~ ✅ DONE

| # | ID | Severity | Change | Lines | Status |
|---|-----|----------|--------|-------|--------|
| ~~15~~ | ~~P12~~ | ~~**CRIT**~~ | ~~Raise SMT-MAX-LEAVES to match state~~ | ~~L55~~ | ✅ `SMT-MAX-LEAVES = 4096`, `_SMT-MAX-NODES = 8191`. |
| ~~16~~ | ~~P16~~ | ~~**HIGH**~~ | ~~Node-0 guard in `_SMT-NODE`~~ | ~~L97~~ | ✅ Returns 0 (NULL) if idx=0 before computing offset. |
| ~~17~~ | ~~P17~~ | ~~**HIGH**~~ | ~~`SMT-PROVE` add buf-len parameter~~ | ~~L518~~ | ✅ New API: `( key buf buf-len tree -- proof-len flag )`. Overflow check added. `SMT-VERIFY` depth>256 guard added. |
| ~~18~~ | ~~B11~~ | ~~**HIGH**~~ | ~~`SMT-INSERT` check node count~~ | ~~L303~~ | ✅ Dual capacity guards: leaf count + node count (`ncnt+2 > max`) in both empty-tree and keys-differ paths. |

**Tests:** 27/27 pass — 23 original + 4 new (P12 max-leaves, P16 node-0, P17 prove overflow, B11 insert capacity).

### ~~File 5: `store/state.f`~~ ✅ DONE

| # | ID | Severity | Change | Lines | Status |
|---|-----|----------|--------|-------|--------|
| ~~19~~ | ~~B01~~ | ~~**HIGH**~~ | ~~Raise `_ST-MAX-PAGES`~~ | ~~L87~~ | ✅ Changed 16→256 (production minimum). 65,536 max accounts. SMT capacity matched (P12). |
| ~~20~~ | ~~P13~~ | ~~**HIGH**~~ | ~~`_ST-REBUILD-TREE` error propagation~~ | ~~L271~~ | ✅ Returns flag; `ST-ROOT` now `( -- addr flag )`. Zero buffer + 0 on failure. |
| ~~21~~ | ~~P14~~ | ~~**MED**~~ | ~~Incremental SMT root (dirty flag)~~ | ~~L112~~ | ✅ `_ST-DIRTY` variable. `_ST-REBUILD-TREE` skips if clean. Set dirty in `ST-INIT`, `ST-CREATE`, `ST-APPLY-TX`. |
| ~~22~~ | ~~P15~~ | ~~**HIGH**~~ | ~~Implement staking extension~~ | ~~L420–480~~ | ✅ Real `_ST-TX-EXT`: type 3=stake (debit balance→staked, set unstake height), type 4=unstake (credit balance, zero staking fields if lock elapsed). Forward refs fixed. |

**Tests:** 50/50 pass — 44 existing + 6 new staking tests (stake, unstake, premature unstake reject, insufficient balance, already staked, nothing staked).

---

## Priority 4 — Block & consensus (builds on correct state + tx)

### File 6: `consensus/consensus.f` — ✅ DONE (batch 4, 40/40 tests)

| # | ID | Severity | Change | Lines | Summary | Status |
|---|-----|----------|--------|-------|---------|--------|
| 23 | P18 | **CRIT** | STARK stub fail-closed | L390 | `_CON-STARK-CHECK-STUB`: `DROP -1` → `DROP 0` (fail-closed). | ✅ |
| 24 | P19 | **CRIT** | PoS leader div-by-zero | ~L651 | Guard `_CON-VAL-COUNT @ 0=` before `MOD`. Returns `_CON-SEED-BUF` sentinel. | ✅ |
| 25 | P20 | **CRIT** | PoS leader underflow | ~L651 | Combined with P19 guard. | ✅ |
| 26 | A05 | **CRIT** | Zeroize signing keys | L118 | `CON-CLEAR-KEYS`: zeros priv(64)+pub(32), clears flag. Guard-wrapped. | ✅ |
| 27 | B04 | **HIGH** | Constants → VARIABLEs | L458-461 | `CON-POS-EPOCH-LEN`, `MIN-STAKE`, `LOCK-PERIOD` → VARIABLEs (defaults 32/100/64). All refs updated to use `@`. | ✅ |
| 28 | C08 | **MED** | Cell-sized SA indices | L756,790,825 | `_CON-SA-IDX` → `256 CELLS ALLOT`; `C!`/`C@` → `!`/`@` with CELLS offset. | ✅ |
| 29 | C12 | **MED** | Portable seed extraction | L627-630 | New `_CON-SEED>U64` reads 8 bytes BE. Replaces raw `@` in leader+elect. | ✅ |
| 30 | P21 | **MED** | PoW mine iteration cap | L197,207 | `_CON-POW-MAX-ITER` VARIABLE (1M default). `CON-POW-MINE ( blk -- flag )`. `CON-SEAL` drops flag. | ✅ |

**Extra fixes found during testing:**
- Pre-existing bug: `CON-POS-EPOCH` insertion sort `0 1 ?DO` loops ~2^64 when val_count=0. Fixed with `_CON-VAL-COUNT @ 1 > IF ... THEN` guard.
- Forward-fix for batch 3 `ST-ROOT` API change: added `DROP` after `ST-ROOT` in `store/block.f` at lines 261, 603, 673 (`BLK-FINALIZE`, `BLK-VERIFY`, `CHAIN-INIT`).

### File 7: `store/block.f`

| # | ID | Severity | Change | Lines | Summary |
|---|-----|----------|--------|-------|---------|
| 31 | P22 | **HIGH** | `BLK-FINALIZE` truncate on tx failure | L256 | Replace `ST-APPLY-TX DROP` with failure check. On fail, truncate block to valid prefix (`I` → `_BLK-TXCNT C!`, `LEAVE`). |
| 32 | A02 | **CRIT** | `CHAIN-APPEND` drops `ST-APPLY-TX` failure | L727–729 | Same bug as P22 but in the receive path. Apply identical truncate-on-failure fix. This is the canonical entry for all externally-received blocks. |
| 33 | B06 | **HIGH** | `BLK-DECODE` skips transaction bodies | `BLK-DECODE` | Implement tx-body parsing in `BLK-DECODE`. Currently only decodes header; comment says "Caller can re-parse" but nobody does. Without this, sync (B05), persist-load, and RPC all see `BLK-TX-COUNT@ = 0`. |
| 34 | B09 | **HIGH** | `CHAIN-HISTORY = 64` too small | ~L62 | Raise to at least `256` (8 epochs). Needed for epoch transitions, slashing evidence, light-client proof for older blocks. |
| 35 | C07 | **MED** | `BLK-DECODE` validate `_BLK-VERSION` | `BLK-DECODE` | Read version byte and reject if `<> 1`. Prevents silent misparse on future format changes. |
| 36 | D07 | **LOW** | `_BLK-CBUF = 1024` too small for future proofs | header encode | Raise to 2048+ or dynamically size. Currently barely fits; STARK proofs will overflow. |

### File 8: `store/genesis.f`

| # | ID | Severity | Change | Lines | Summary |
|---|-----|----------|--------|-------|---------|
| 37 | P25 | **HIGH** | Stack discipline in auth key parsing | ~L173 | Fix `2DROP` on `len <> 32` path — should be `DROP` (only `addr` left after `<>` consumes `len`). Stack corruption on any malformed genesis. |
| 38 | P23 | **MED** | CBOR key validation | L137–148 | Add `_GEN-EXPECT-KEY` — validate key strings (`"chain_id"`, `"con_mode"`, etc.) instead of positional parsing. |
| 39 | P24 | **MED** | `GEN-HASH` include state root | L197–203 | After `GEN-LOAD` populates state, copy `ST-ROOT` into block before hashing. Two chains with different balances must produce different genesis hashes. |
| 40 | D09 | **LOW** | `_GEN-BUF-SIZE = 4096` too small | const | Raise to 16384. Large authority lists or many pre-funded accounts overflow 4 KB. |

---

## Priority 5 — Mempool (gatekeeper for tx admission)

### File 9: `store/mempool.f`

| # | ID | Severity | Change | Lines | Summary |
|---|-----|----------|--------|-------|---------|
| 41 | A04 | **CRIT** | Verify signatures on admission | ~L228 | Add `TX-VERIFY` call in `MP-ADD` (after `TX-VALID?`, before slot allocation). Without this, forged txs consume all 256 slots → trivial DoS. |
| 42 | B03 | **HIGH** | Raise `MP-CAPACITY` from 256 | ~L36 | Raise to 4096+. Memory: 4096 × TX-BUF-SIZE ≈ 32 MB (acceptable). Current 256 = one block's worth. |
| 43 | D04 | **LOW** | Linear scan + no eviction + no priority | `_MP-HASH-FIND`, `_MP-ALLOC` | Tolerable at 256, bottleneck at 4096+. Add fee-based eviction when capacity is raised. Hash-index lookup. Lower priority — works for launch. |

---

## Priority 6 — Network layer (gossip + sync)

### File 10: `net/gossip.f`

| # | ID | Severity | Change | Lines | Summary |
|---|-----|----------|--------|-------|---------|
| 44 | P26 | **HIGH** | Peer-id bounds check | L131, L139 | Add `_GSP-VALID-ID? ( id -- flag )` guard to `GSP-CONNECT` / `GSP-DISCONNECT`. Prevents OOB write when `peer-id >= GSP-MAX-PEERS`. |
| 45 | B02 | **HIGH** | Raise `GSP-MAX-PEERS` from 16 | ~L48 | Raise to 64+ for federation scale (dozens of consortium members). 16 is insufficient for partition resistance. |
| 46 | B10 | **HIGH** | Message size validation before CBOR-PARSE | `GSP-ON-MSG` | Check `_GSP-RLEN <= _GSP-BUF-SZ` before passing to `CBOR-PARSE`. Reject oversized messages. |
| 47 | P27 | **MED** | Seen-hash ring size 256 → 1024 | L48 | 256 entries exhausted in 1 second at flood rate. Raise to 1024. |
| 48 | C01 | **MED** | Protocol versioning in wire format | message format | Add 2-byte magic + 1-byte version to wire format. Reject incompatible peers. |
| 49 | C02 | **MED** | Peer authentication (challenge-response) | `GSP-CONNECT` | Add Ed25519 handshake after WS-CONNECT. Without this, eclipse attacks are trivial (16 sybil nodes fill all slots). |
| 50 | D01 | **LOW** | Log unknown message types | `GSP-ON-MSG` ~L320 | Add counter + optional log line for unknown tags. Currently silently drops. |

### File 11: `net/sync.f`

| # | ID | Severity | Change | Lines | Summary |
|---|-----|----------|--------|-------|---------|
| 51 | B05 | **HIGH** | Sync fetches headers only — no tx bodies | entire file | Sync must request full blocks (header + txs). Currently produces a headerchain with no state. Depends on B06 (`BLK-DECODE` tx parsing). |
| 52 | C03 | **MED** | Single-peer sequential sync | `_SYNC-PEER` | Add fallback peer selection after retry exhaustion. Currently stalls permanently in `SYNC-STALLED` if chosen peer fails. |

### File 12: `net/ws.f`

| # | ID | Severity | Change | Lines | Summary |
|---|-----|----------|--------|-------|---------|
| 53 | D08 | **LOW** | `_WS-RBUF = 4096` vs gossip 16384 | L295 | Raise WS receive buffer to match gossip's `_GSP-BUF-SZ = 16384`. Messages >4 KB may truncate or mis-reassemble. |

---

## Priority 7 — RPC / Server (external interface)

### File 13: `web/rpc.f`

| # | ID | Severity | Change | Lines | Summary |
|---|-----|----------|--------|-------|---------|
| 54 | A01 | **CRIT** | `_RPC-PROOF` buffer overflow (256 → 10240+) | L69 | Change `CREATE _RPC-PROOF 256 ALLOT` to `10240 ALLOT` (or derive from SMT max depth). Current allocation corrupts dictionary on every `chain_getProof` call for any non-trivial tree. **One-line fix, prevents memory corruption now.** |
| 55 | P28 | **HIGH** | `sendTransaction` never broadcasts | L154–168 | Add `GSP-BROADCAST-TX` call after successful `MP-ADD`. Currently tx stays local forever. |
| 56 | P30 | **MED** | Rate limiting | top of `RPC-DISPATCH` | Add token-bucket (`_RPC-RATE-CHECK`). Use `DT-NOW-S` from datetime.f. Return HTTP 429 when exhausted. |
| 57 | D02 | **LOW** | No RPC auth/authorization | `_RPC-DISPATCH-METHOD` | All methods open to any client. Add API key or session middleware. Lower priority for consortium (trusted node operators). |

### File 14: `web/server.f`

| # | ID | Severity | Change | Lines | Summary |
|---|-----|----------|--------|-------|---------|
| 58 | C04 | **MED** | Single-threaded, single-connection, no TLS | `SRV-LOOP` | One slow client blocks all others. No TLS = plaintext tx submission. At minimum: non-blocking accept loop. TLS requires KDOS TLS support or stunnel wrapper. |

---

## Priority 8 — Persistence & witness (data durability)

### File 15: `store/persist.f`

| # | ID | Severity | Change | Lines | Summary |
|---|-----|----------|--------|-------|---------|
| 59 | P31 | **HIGH** | Sector sizing: make configurable | L52–56 | Convert `_PST-CHAIN-SECTORS` / `_PST-STATE-SECTORS` to VARIABLEs. Add `PST-SET-CAPACITY`. Add auto-grow via `FTRUNCATE`. |
| 60 | B07 | **HIGH** | No block index — O(n) loading | `PST-LOAD-BLOCK` | Add sector-offset index (in-memory array or index file). Loading block N currently parses 0..N-1. |
| 61 | B08 | **HIGH** | Hardcoded filenames — single chain per node | string literals | Replace `S" chain.dat"` / `S" state.snap"` with chain-id-derived filenames. Federation requires multiple chains per node. |
| 62 | D06 | **LOW** | `_PST-ENC-SZ = 16384` too small | const | A full block (256 txs × 8 KB) = ~2 MB CBOR. 16 KB buffer will truncate. Raise or stream-encode. |

### File 16: `store/witness.f`

| # | ID | Severity | Change | Lines | Summary |
|---|-----|----------|--------|-------|---------|
| 63 | C09 | **MED** | `WIT-MAX-ENTRIES = 512` silent drop | `_WIT-RECORD` | Return error flag on overflow instead of silent no-op. STARK proof over witness set will be incomplete if entries are dropped. |
| 64 | D05 | **LOW** | Linear scan for address lookup | `_WIT-FIND` | O(n) × 32-byte compare. Tolerable at 512 but degrades with larger blocks. Index or hash later. |

### File 17: `store/light.f`

| # | ID | Severity | Change | Lines | Summary |
|---|-----|----------|--------|-------|---------|
| 65 | C10 | **MED** | `LC-STATE-PROOF` calls full rebuild every time | ~L95 | Uses `_ST-REBUILD-TREE` directly, bypassing dirty-flag optimization from P14. After P14 lands, route through `ST-ROOT` first, then call `SMT-PROVE` on the cached tree. |

---

## Priority 9 — Node orchestration (ties everything together)

### File 18: `node/node.f`

| # | ID | Severity | Change | Lines | Summary |
|---|-----|----------|--------|-------|---------|
| 66 | P32 | **CRIT** | `MP-DRAIN` overwrites block header | L104 | Allocate `_NODE-TX-PTRS` buffer (2048 bytes). Drain mempool into temp buffer, then call `BLK-ADD-TX` per entry. |
| 67 | P33 | **CRIT** | Wire `SRV-STEP` into `NODE-STEP` | L137–143 | Add `SRV-STEP` call at top of `NODE-STEP`. Without this, RPC server accepts connections but never processes requests. |
| 68 | P34 | **CRIT** | Real timestamps (`DT-NOW-S`) | L100 | `REQUIRE datetime.f`. Replace `1 _NODE-BLK BLK-SET-TIME` with `DT-NOW-S _NODE-BLK BLK-SET-TIME`. |
| 69 | P35 | **HIGH** | Wire `_NODE-PERSIST-TICK` into `NODE-STEP` | defined but never called | Add `_NODE-PERSIST-TICK` call in `NODE-STEP` after `SYNC-STEP`. |
| 70 | P37 | **MED** | Graceful shutdown | L137–139 | Add to `NODE-STOP`: `PST-SAVE-STATE`, `PST-CLOSE`, disconnect all gossip peers, `_CON-SIGN-PRIV 64 0 FILL` (ties into A05). |
| 71 | P36 | **MED** | Busy loop yield | `NODE-RUN` | Add `_NODE-YIELD ( ms -- )` using `DT-NOW-MS` busy-wait. Call `1 _NODE-YIELD` after each `NODE-STEP`. Limits to ~1000 iter/sec. |
| 72 | D03 | **LOW** | `_NODE-BLK-INTERVAL` is step-based, not time-based | const | Block production rate depends on hardware speed. Switch to wall-clock interval using `DT-NOW-S`. |

---

## Cross-cutting concern: `C11 — Shared static buffers`

Not file-local. Affects `_GSP-RBUF` (gossip.f), `_BLK-CBUF` (block.f),
`_RPC-RAW` / `_RPC-PROOF` (rpc.f), `_PST-ENC-SZ` (persist.f).  A call
chain crossing modules (RPC → state → SMT → block) can re-enter a buffer
the outer frame is still using.  Guards are per-word, not per-buffer.

**Resolution:** Audit all cross-module call chains after individual file
fixes land.  Add per-buffer guards or allocate per-call-frame copies for
the hot paths (RPC → proof is the main one).  This is a sweep task, not
a per-file fix.

---

## Summary by severity

| Severity | Count | Changes |
|----------|-------|---------|
| **CRITICAL** | 16 | P01, P02, P06, P09, A03, P12, P18, P19, P20, A05, A02, A04, A01, P32, P33, P34 |
| **HIGH** | 22 | P04, P03, P13, P15, P16, P17, B11, B01, P22, P25, B06, B09, P26, B02, B10, P28, B05, P31, B07, B08, P35, B04 |
| **MEDIUM** | 18 | P05, P07, P08, P10, P11, P14, C05, C06, P21, P23, P24, P27, C01, C02, C08, C12, P30, P37, P36, C03, C04, C09, C10, C07 |
| **LOW** | 10 | D01–D09, P27 ring |

**Estimated total effort:** ~2,000–2,500 lines of changes + ~800 lines of new tests.

## Execution order (batch view)

| Batch | Files | Duration est. | Gate |
|-------|-------|---------------|------|
| **1** | ed25519.f, sphincs-plus.f | 1–2 days | All crypto tests pass + pyspx interop |
| **2** | tx.f (struct change: chain_id + fee + TTL + hybrid fix) | 1 day | Layout break — ripples into every downstream module |
| **3** | smt.f, state.f | 1–2 days | SMT capacity, error prop, staking. All state tests pass. |
| **4** | consensus.f | 1 day | STARK stub, PoS guards, constants→variables, key zeroize |
| **5** | block.f, genesis.f | 1 day | Finalize/append error handling, decode txs, genesis fixes |
| **6** | mempool.f | 0.5 day | Sig verify on admit, capacity raise |
| **7** | gossip.f, sync.f, ws.f | 1–2 days | Bounds, capacity, msg validation, full-block sync |
| **8** | rpc.f, server.f | 1 day | Proof buffer, broadcast, rate limit |
| **9** | persist.f, witness.f, light.f | 1 day | Sector sizing, block index, filenames, witness overflow |
| **10** | node.f | 1 day | MP-DRAIN, SRV-STEP, timestamps, persist tick, shutdown |
| **11** | Cross-cutting buffer audit | 0.5 day | C11 shared-buffer re-entrancy sweep |

**Total estimated:** ~10–13 working days

---

## Files NOT touched (no issues found)

- `store/vault.f` — key storage, no issues flagged
- `web/middleware.f` — CORS only, D02 (auth) would add to this later
- `web/template.f`, `web/response.f`, `web/request.f`, `web/router.f` — not in blockchain path
- `utils/json.f`, `utils/fmt.f`, `utils/datetime.f` — consumed but not changed
- `cbor/cbor.f` — consumed but not changed
