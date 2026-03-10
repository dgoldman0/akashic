#!/usr/bin/env python3
# ┌──────────────────────────────────────────────────────────────┐
# │ HARNESS UPDATE REQUIRED (March 2026)                         │
# │                                                              │
# │ 1. BOOT-TO-IDLE: run_forth() must call boot() on a fresh    │
# │    MegapadSystem before overwriting RAM/CPU state from the   │
# │    snapshot.  Without boot(), the C++ accelerator's MMIO     │
# │    routing (UART writes) is never wired → empty output.      │
# │    Fix: save bios_code in the snapshot tuple, then in        │
# │    run_forth(): load_binary(0, bios_code), boot(), run to    │
# │    idle, THEN overwrite mem/cpu/ext from snapshot.           │
# │                                                              │
# │ 2. NO [: ;] CLOSURES: This BIOS/KDOS does not define the    │
# │    [: ... ;] anonymous quotation words.  Replace all uses    │
# │    with named helper words and ['] ticks.                    │
# │                                                              │
# │ See test_coroutine.py for the corrected pattern.             │
# └──────────────────────────────────────────────────────────────┘
"""Test suite for akashic-taxonomy (knowledge/taxonomy.f).

Tests the hierarchical taxonomy engine: concept CRUD, tree structure,
synonym rings, facet bits, item classification, traversal, search,
and diagnostics.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
STR_F      = os.path.join(ROOT_DIR, "akashic", "utils", "string.f")
TAX_F      = os.path.join(ROOT_DIR, "akashic", "knowledge", "taxonomy.f")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# ── Emulator helpers ──────────────────────────────────────────────

_snapshot = None

def _load_bios():
    with open(BIOS_PATH) as f:
        return assemble(f.read())

def _load_forth_lines(path):
    with open(path) as f:
        lines = []
        for line in f.read().splitlines():
            s = line.strip()
            if not s or s.startswith('\\'):
                continue
            if s.startswith('REQUIRE ') or s.startswith('PROVIDED '):
                continue
            lines.append(line)
        return lines

def _next_line_chunk(data, pos):
    nl = data.find(b'\n', pos)
    return data[pos:nl+1] if nl != -1 else data[pos:]

def capture_uart(sys_obj):
    buf = []
    sys_obj.uart.on_tx = lambda b: buf.append(b)
    return buf

def uart_text(buf):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9)) else ""
        for b in buf)

def save_cpu_state(cpu):
    return {k: getattr(cpu, k) for k in
            ['pc','psel','xsel','spsel','flag_z','flag_c','flag_n','flag_v',
             'flag_p','flag_g','flag_i','flag_s','d_reg','q_out','t_reg',
             'ivt_base','ivec_id','trap_addr','halted','idle','cycle_count',
             '_ext_modifier']} | {'regs': list(cpu.regs)}

def restore_cpu_state(cpu, state):
    cpu.regs[:] = state['regs']
    for k, v in state.items():
        if k != 'regs':
            setattr(cpu, k, v)

def build_snapshot():
    global _snapshot
    if _snapshot:
        return _snapshot
    print("[*] Building snapshot: BIOS + KDOS + string + taxonomy ...")
    t0 = time.time()
    bios_code  = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    str_lines  = _load_forth_lines(STR_F)
    tax_lines  = _load_forth_lines(TAX_F)

    # Test helpers:
    #   T-INIT  — create arena (131072 bytes in XMEM) + taxonomy, set as current
    #   _TX     — VARIABLE holding the taxonomy handle (set by T-INIT)
    #   _TB / _TL / TR / TC / TA — text buffer for building strings char-by-char
    helpers = [
        'VARIABLE _TX',
        'CREATE _TB 4096 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        ': T-INIT  131072 A-XMEM ARENA-NEW ABORT" arena fail"  TAX-CREATE  DUP _TX ! TAX-USE ;',
    ]

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16*(1<<20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    all_lines = kdos_lines + ["ENTER-USERLAND"] + str_lines + tax_lines + helpers
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode(); pos = 0; steps = 0; mx = 800_000_000
    while steps < mx:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk); pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, mx - steps))
        steps += max(batch, 1)
    text = uart_text(buf)
    err_lines = [l for l in text.strip().split('\n') if '?' in l]
    if err_lines:
        print("[!] Possible compilation errors:")
        for ln in err_lines[-20:]:
            print(f"    {ln}")
    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot

def run_forth(lines, max_steps=50_000_000):
    bios_code, mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16*(1<<20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    for _ in range(5_000_000):
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            break
        sys_obj.run_batch(10_000)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)
    buf.clear()
    payload = "\n".join(lines) + "\nBYE\n"
    data = payload.encode(); pos = 0; steps = 0
    while steps < max_steps:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk); pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)
    return uart_text(buf)

# ── Test runner ───────────────────────────────────────────────────

_pass = 0
_fail = 0

def check(name, forth_lines, expected=None, check_fn=None):
    global _pass, _fail
    output = run_forth(forth_lines)
    clean = output.strip()
    if check_fn:
        ok = check_fn(clean)
    elif expected is not None:
        ok = expected in clean
    else:
        ok = True
    if ok:
        _pass += 1
        print(f"  PASS  {name}")
    else:
        _fail += 1
        print(f"  FAIL  {name}")
        if expected is not None:
            print(f"        expected: {expected!r}")
        last = clean.split('\n')[-5:]
        print(f"        got (last lines): {last}")

# ── Tests ─────────────────────────────────────────────────────────

if __name__ == '__main__':
    build_snapshot()

    # ================================================================
    print("\n── TAX-CREATE / TAX-DESTROY ──\n")
    # ================================================================

    check("create returns non-zero handle",
          [': _T T-INIT  _TX @ 0<> IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("stats after create: 0 concepts 0 links",
          [': _T T-INIT  TAX-STATS . . ; _T'],
          "0 0 ")

    check("TAX-OK? after fresh create",
          [': _T T-INIT  TAX-OK? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("TAX-COUNT is 0 after create",
          [': _T T-INIT  TAX-COUNT . ; _T'],
          "0 ")

    # ================================================================
    print("\n── TAX-ADD (top-level concepts) ──\n")
    # ================================================================

    check("add one concept returns non-zero",
          [': _T T-INIT  S" Animals" TAX-ADD  0<> IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("concept-count after add = 1",
          [': _T T-INIT  S" Animals" TAX-ADD DROP  TAX-COUNT . ; _T'],
          "1 ")

    check("added concept has correct ID (=1)",
          [': _T T-INIT  S" Animals" TAX-ADD  TAX-ID . ; _T'],
          "1 ")

    check("added concept label round-trip",
          [': _T T-INIT  S" Fruits" TAX-ADD  TAX-LABEL TYPE CR ; _T'],
          "Fruits")

    check("add two concepts, count=2",
          [': _T T-INIT',
           '  S" Animals" TAX-ADD DROP',
           '  S" Plants" TAX-ADD DROP',
           '  TAX-COUNT . ;',
           '_T'],
          "2 ")

    check("two concepts have different IDs",
          [': _T T-INIT',
           '  S" A" TAX-ADD TAX-ID',
           '  S" B" TAX-ADD TAX-ID',
           '  <> IF 1 ELSE 0 THEN . ;',
           '_T'],
          "1 ")

    # ================================================================
    print("\n── TAX-ADD-UNDER (child concepts) ──\n")
    # ================================================================

    check("add-under returns non-zero",
          ['VARIABLE P',
           ': _T T-INIT',
           '  S" Animals" TAX-ADD P !',
           '  S" Cats" P @ TAX-ADD-UNDER  0<> IF 1 ELSE 0 THEN . ;',
           '_T'],
          "1 ")

    check("parent has 1 child after add-under",
          ['VARIABLE P',
           ': _T T-INIT',
           '  S" Animals" TAX-ADD P !',
           '  S" Cats" P @ TAX-ADD-UNDER DROP',
           '  P @ TAX-CHILDREN NIP . ;',
           '_T'],
          "1 ")

    check("add two children, parent has 2",
          ['VARIABLE P',
           ': _T T-INIT',
           '  S" Animals" TAX-ADD P !',
           '  S" Cats" P @ TAX-ADD-UNDER DROP',
           '  S" Dogs" P @ TAX-ADD-UNDER DROP',
           '  P @ TAX-CHILDREN NIP . ;',
           '_T'],
          "2 ")

    check("child knows its parent",
          ['VARIABLE P',
           ': _T T-INIT',
           '  S" Animals" TAX-ADD P !',
           '  S" Cats" P @ TAX-ADD-UNDER',
           '  TAX-PARENT P @ = IF 1 ELSE 0 THEN . ;',
           '_T'],
          "1 ")

    check("child depth = 1",
          ['VARIABLE P',
           ': _T T-INIT',
           '  S" A" TAX-ADD P !',
           '  S" B" P @ TAX-ADD-UNDER  TAX-DEPTH . ;',
           '_T'],
          "1 ")

    check("grandchild depth = 2",
          ['VARIABLE P  VARIABLE C',
           ': _T T-INIT',
           '  S" A" TAX-ADD P !',
           '  S" B" P @ TAX-ADD-UNDER  C !',
           '  S" D" C @ TAX-ADD-UNDER  TAX-DEPTH . ;',
           '_T'],
          "2 ")

    # ================================================================
    print("\n── TAX-ROOTS ──\n")
    # ================================================================

    check("roots returns 0 on empty",
          [': _T T-INIT  TAX-ROOTS NIP . ; _T'],
          "0 ")

    check("roots returns 1 after one add",
          [': _T T-INIT  S" X" TAX-ADD DROP  TAX-ROOTS NIP . ; _T'],
          "1 ")

    check("roots returns 2 after two adds",
          [': _T T-INIT',
           '  S" X" TAX-ADD DROP  S" Y" TAX-ADD DROP',
           '  TAX-ROOTS NIP . ;',
           '_T'],
          "2 ")

    check("children not in roots",
          ['VARIABLE P',
           ': _T T-INIT',
           '  S" X" TAX-ADD P !',
           '  S" Y" P @ TAX-ADD-UNDER DROP',
           '  TAX-ROOTS NIP . ;',
           '_T'],
          "1 ")

    # ================================================================
    print("\n── TAX-CHILDREN / TAX-ANCESTORS ──\n")
    # ================================================================

    check("children of leaf is 0",
          [': _T T-INIT',
           '  S" X" TAX-ADD  TAX-CHILDREN NIP . ;',
           '_T'],
          "0 ")

    check("ancestors of root is 0",
          [': _T T-INIT',
           '  S" X" TAX-ADD  TAX-ANCESTORS NIP . ;',
           '_T'],
          "0 ")

    check("ancestors of child has 1 entry",
          ['VARIABLE P',
           ': _T T-INIT',
           '  S" A" TAX-ADD P !',
           '  S" B" P @ TAX-ADD-UNDER',
           '  TAX-ANCESTORS NIP . ;',
           '_T'],
          "1 ")

    check("ancestors of grandchild has 2 entries",
          ['VARIABLE P  VARIABLE C',
           ': _T T-INIT',
           '  S" A" TAX-ADD P !',
           '  S" B" P @ TAX-ADD-UNDER C !',
           '  S" D" C @ TAX-ADD-UNDER',
           '  TAX-ANCESTORS NIP . ;',
           '_T'],
          "2 ")

    # ================================================================
    print("\n── TAX-DESCENDANTS ──\n")
    # ================================================================

    check("descendants of leaf = 0",
          [': _T T-INIT',
           '  S" X" TAX-ADD  TAX-DESCENDANTS NIP . ;',
           '_T'],
          "0 ")

    check("descendants = 1 with one child",
          ['VARIABLE P',
           ': _T T-INIT',
           '  S" A" TAX-ADD P !',
           '  S" B" P @ TAX-ADD-UNDER DROP',
           '  P @ TAX-DESCENDANTS NIP . ;',
           '_T'],
          "1 ")

    check("descendants = 2 with child+grandchild",
          ['VARIABLE P  VARIABLE C',
           ': _T T-INIT',
           '  S" A" TAX-ADD P !',
           '  S" B" P @ TAX-ADD-UNDER C !',
           '  S" D" C @ TAX-ADD-UNDER DROP',
           '  P @ TAX-DESCENDANTS NIP . ;',
           '_T'],
          "2 ")

    check("descendants = 3 with 2 children + 1 grandchild",
          ['VARIABLE P  VARIABLE C',
           ': _T T-INIT',
           '  S" A" TAX-ADD P !',
           '  S" B" P @ TAX-ADD-UNDER C !',
           '  S" D" P @ TAX-ADD-UNDER DROP',
           '  S" E" C @ TAX-ADD-UNDER DROP',
           '  P @ TAX-DESCENDANTS NIP . ;',
           '_T'],
          "3 ")

    # ================================================================
    print("\n── TAX-REMOVE ──\n")
    # ================================================================

    check("remove top-level concept, count=0",
          [': _T T-INIT',
           '  S" X" TAX-ADD  TAX-REMOVE',
           '  TAX-COUNT . ;',
           '_T'],
          "0 ")

    check("remove child, parent children=0",
          ['VARIABLE P',
           ': _T T-INIT',
           '  S" A" TAX-ADD P !',
           '  S" B" P @ TAX-ADD-UNDER  TAX-REMOVE',
           '  P @ TAX-CHILDREN NIP . ;',
           '_T'],
          "0 ")

    check("remove subtree: parent+child removed, count=0",
          ['VARIABLE P',
           ': _T T-INIT',
           '  S" A" TAX-ADD P !',
           '  S" B" P @ TAX-ADD-UNDER DROP',
           '  P @ TAX-REMOVE',
           '  TAX-COUNT . ;',
           '_T'],
          "0 ")

    check("remove leaves sibling intact",
          ['VARIABLE P',
           ': _T T-INIT',
           '  S" A" TAX-ADD P !',
           '  S" B" TAX-ADD DROP',
           '  P @ TAX-REMOVE',
           '  TAX-ROOTS NIP . ;',
           '_T'],
          "1 ")

    check("remove middle child preserves others",
          ['VARIABLE R  VARIABLE M',
           ': _T T-INIT',
           '  S" P" TAX-ADD R !',
           '  S" A" R @ TAX-ADD-UNDER DROP',
           '  S" B" R @ TAX-ADD-UNDER M !',
           '  S" C" R @ TAX-ADD-UNDER DROP',
           '  M @ TAX-REMOVE',
           '  R @ TAX-CHILDREN NIP . ;',
           '_T'],
          "2 ")

    # ================================================================
    print("\n── TAX-MOVE (reparenting) ──\n")
    # ================================================================

    check("move top-level under another",
          ['VARIABLE PA  VARIABLE PB',
           ': _T T-INIT',
           '  S" A" TAX-ADD PA !',
           '  S" B" TAX-ADD PB !',
           '  PB @ PA @ TAX-MOVE',
           '  PA @ TAX-CHILDREN NIP .',    # A has 1 child
           '  TAX-ROOTS NIP . ;',          # only 1 root left
           '_T'],
          "1 1 ")

    check("move child to top-level (parent=0)",
          ['VARIABLE PA  VARIABLE CB',
           ': _T T-INIT',
           '  S" A" TAX-ADD PA !',
           '  S" B" PA @ TAX-ADD-UNDER CB !',
           '  CB @ 0 TAX-MOVE',
           '  TAX-ROOTS NIP .',            # now 2 roots
           '  PA @ TAX-CHILDREN NIP . ;',  # A has 0 children
           '_T'],
          "2 0 ")

    check("move detects cycle",
          ['VARIABLE PA  VARIABLE CB',
           ': _T T-INIT',
           '  S" A" TAX-ADD PA !',
           '  S" B" PA @ TAX-ADD-UNDER CB !',
           '  PA @ CB @ TAX-MOVE',         # try move parent under child
           '  TAX-OK? IF 0 ELSE 1 THEN . ;',  # should fail
           '_T'],
          "1 ")

    # ================================================================
    print("\n── TAX-RENAME ──\n")
    # ================================================================

    check("rename changes label",
          ['VARIABLE C',
           ': _T T-INIT',
           '  S" Old" TAX-ADD C !',
           '  S" New" C @ TAX-RENAME',
           '  C @ TAX-LABEL TYPE CR ;',
           '_T'],
          "New")

    check("rename preserves tree structure",
          ['VARIABLE R  VARIABLE CA',
           ': _T T-INIT',
           '  S" P" TAX-ADD R !',
           '  S" A" R @ TAX-ADD-UNDER CA !',
           '  S" B" CA @ TAX-RENAME',
           '  R @ TAX-CHILDREN NIP . ;',   # still 1 child
           '_T'],
          "1 ")

    # ================================================================
    print("\n── TAX-ADD-SYNONYM / TAX-REMOVE-SYNONYM / TAX-SYNONYMS ──\n")
    # ================================================================

    check("synonyms of isolated concept = 1 (self)",
          [': _T T-INIT',
           '  S" A" TAX-ADD  TAX-SYNONYMS NIP . ;',
           '_T'],
          "1 ")

    check("link two synonyms, ring size = 2",
          ['VARIABLE C1  VARIABLE C2',
           ': _T T-INIT',
           '  S" Cat" TAX-ADD C1 !',
           '  S" Feline" TAX-ADD C2 !',
           '  C1 @ C2 @ TAX-ADD-SYNONYM',
           '  C1 @ TAX-SYNONYMS NIP . ;',
           '_T'],
          "2 ")

    check("synonym ring includes both concepts",
          ['VARIABLE C1  VARIABLE C2',
           ': _T T-INIT',
           '  S" Cat" TAX-ADD C1 !',
           '  S" Feline" TAX-ADD C2 !',
           '  C1 @ C2 @ TAX-ADD-SYNONYM',
           '  C1 @ TAX-SYNONYMS',          # ( addr n )
           '  DUP . CR',                    # count
           '  0 DO  DUP I 8 * + @ TAX-LABEL TYPE 32 EMIT  LOOP DROP CR ;',
           '_T'],
          check_fn=lambda out: "Cat" in out and "Feline" in out)

    check("remove synonym breaks ring",
          ['VARIABLE C1  VARIABLE C2',
           ': _T T-INIT',
           '  S" A" TAX-ADD C1 !',
           '  S" B" TAX-ADD C2 !',
           '  C1 @ C2 @ TAX-ADD-SYNONYM',
           '  C1 @ TAX-REMOVE-SYNONYM',
           '  C2 @ TAX-SYNONYMS NIP . ;',  # C2 alone in ring
           '_T'],
          "1 ")

    check("three-way synonym ring size = 3",
          ['VARIABLE C1  VARIABLE C2  VARIABLE C3',
           ': _T T-INIT',
           '  S" A" TAX-ADD C1 !',
           '  S" B" TAX-ADD C2 !',
           '  S" C" TAX-ADD C3 !',
           '  C1 @ C2 @ TAX-ADD-SYNONYM',
           '  C2 @ C3 @ TAX-ADD-SYNONYM',
           '  C1 @ TAX-SYNONYMS NIP . ;',
           '_T'],
          "3 ")

    # ================================================================
    print("\n── TAX-SET-FACET / TAX-CLEAR-FACET / TAX-HAS-FACET? ──\n")
    # ================================================================

    check("fresh concept has no facets",
          [': _T T-INIT',
           '  S" X" TAX-ADD  TAX-FACETS@ . ;',
           '_T'],
          "0 ")

    check("set facet bit 0",
          ['VARIABLE C',
           ': _T T-INIT',
           '  S" X" TAX-ADD C !',
           '  0 C @ TAX-SET-FACET',
           '  0 C @ TAX-HAS-FACET? IF 1 ELSE 0 THEN . ;',
           '_T'],
          "1 ")

    check("set multiple facet bits",
          ['VARIABLE C',
           ': _T T-INIT',
           '  S" X" TAX-ADD C !',
           '  0 C @ TAX-SET-FACET',
           '  3 C @ TAX-SET-FACET',
           '  5 C @ TAX-SET-FACET',
           '  0 C @ TAX-HAS-FACET? IF 1 ELSE 0 THEN .',
           '  3 C @ TAX-HAS-FACET? IF 1 ELSE 0 THEN .',
           '  5 C @ TAX-HAS-FACET? IF 1 ELSE 0 THEN .',
           '  1 C @ TAX-HAS-FACET? IF 1 ELSE 0 THEN . ;',
           '_T'],
          "1 1 1 0 ")

    check("clear facet bit",
          ['VARIABLE C',
           ': _T T-INIT',
           '  S" X" TAX-ADD C !',
           '  0 C @ TAX-SET-FACET',
           '  3 C @ TAX-SET-FACET',
           '  0 C @ TAX-CLEAR-FACET',
           '  0 C @ TAX-HAS-FACET? IF 1 ELSE 0 THEN .',
           '  3 C @ TAX-HAS-FACET? IF 1 ELSE 0 THEN . ;',
           '_T'],
          "0 1 ")

    # ================================================================
    print("\n── TAX-FILTER-FACET ──\n")
    # ================================================================

    check("filter-facet returns matching concepts",
          ['VARIABLE CA  VARIABLE CB  VARIABLE CC',
           ': _T T-INIT',
           '  S" A" TAX-ADD CA !',
           '  S" B" TAX-ADD CB !',
           '  S" C" TAX-ADD CC !',
           '  0 CA @ TAX-SET-FACET',       # A has bit 0
           '  0 CB @ TAX-SET-FACET',       # B has bit 0
           '  1 CC @ TAX-SET-FACET',       # C has bit 1 only
           '  1 TAX-FILTER-FACET NIP . ;', # mask=1 → bit 0 → A,B
           '_T'],
          "2 ")

    check("filter-facet with compound mask",
          ['VARIABLE CA  VARIABLE CB',
           ': _T T-INIT',
           '  S" A" TAX-ADD CA !',
           '  S" B" TAX-ADD CB !',
           '  0 CA @ TAX-SET-FACET  1 CA @ TAX-SET-FACET',  # A: bits 0+1
           '  0 CB @ TAX-SET-FACET',                         # B: bit 0 only
           '  3 TAX-FILTER-FACET NIP . ;',  # mask=3 (bits 0+1) → only A
           '_T'],
          "1 ")

    # ================================================================
    print("\n── TAX-FIND / TAX-FIND-PREFIX ──\n")
    # ================================================================

    check("find existing concept",
          [': _T T-INIT',
           '  S" Animals" TAX-ADD DROP',
           '  S" Plants" TAX-ADD DROP',
           '  S" Animals" TAX-FIND  TAX-LABEL TYPE CR ;',
           '_T'],
          "Animals")

    check("find is case-insensitive",
          [': _T T-INIT',
           '  S" Animals" TAX-ADD DROP',
           '  S" animals" TAX-FIND  0<> IF 1 ELSE 0 THEN . ;',
           '_T'],
          "1 ")

    check("find non-existent returns 0",
          [': _T T-INIT',
           '  S" Animals" TAX-ADD DROP',
           '  S" Rocks" TAX-FIND  . ;',
           '_T'],
          "0 ")

    check("find nested concept",
          ['VARIABLE P',
           ': _T T-INIT',
           '  S" A" TAX-ADD P !',
           '  S" B" P @ TAX-ADD-UNDER DROP',
           '  S" B" TAX-FIND  0<> IF 1 ELSE 0 THEN . ;',
           '_T'],
          "1 ")

    check("find-prefix matches",
          [': _T T-INIT',
           '  S" Animals" TAX-ADD DROP',
           '  S" Animate" TAX-ADD DROP',
           '  S" Plants" TAX-ADD DROP',
           '  S" Ani" TAX-FIND-PREFIX NIP . ;',
           '_T'],
          "2 ")

    check("find-prefix no match returns 0",
          [': _T T-INIT',
           '  S" Animals" TAX-ADD DROP',
           '  S" Xyz" TAX-FIND-PREFIX NIP . ;',
           '_T'],
          "0 ")

    # ================================================================
    print("\n── TAX-CLASSIFY / TAX-UNCLASSIFY ──\n")
    # ================================================================

    check("classify item under concept",
          ['VARIABLE C',
           ': _T T-INIT',
           '  S" Animals" TAX-ADD C !',
           '  42 C @ TAX-CLASSIFY',
           '  C @ TAX-ITEMS NIP . ;',
           '_T'],
          "1 ")

    check("classify 2 items, items count = 2",
          ['VARIABLE C',
           ': _T T-INIT',
           '  S" A" TAX-ADD C !',
           '  100 C @ TAX-CLASSIFY',
           '  200 C @ TAX-CLASSIFY',
           '  C @ TAX-ITEMS NIP . ;',
           '_T'],
          "2 ")

    check("classify same item twice is no-op",
          ['VARIABLE C',
           ': _T T-INIT',
           '  S" A" TAX-ADD C !',
           '  42 C @ TAX-CLASSIFY',
           '  42 C @ TAX-CLASSIFY',
           '  C @ TAX-ITEMS NIP . ;',
           '_T'],
          "1 ")

    check("unclassify removes item",
          ['VARIABLE C',
           ': _T T-INIT',
           '  S" A" TAX-ADD C !',
           '  42 C @ TAX-CLASSIFY',
           '  42 C @ TAX-UNCLASSIFY',
           '  C @ TAX-ITEMS NIP . ;',
           '_T'],
          "0 ")

    check("items returns the actual item IDs",
          ['VARIABLE C',
           ': _T T-INIT',
           '  S" A" TAX-ADD C !',
           '  42 C @ TAX-CLASSIFY',
           '  C @ TAX-ITEMS',               # ( addr n )
           '  0 DO  DUP I 8 * + @ .  LOOP DROP CR ;',
           '_T'],
          "42 ")

    # ================================================================
    print("\n── TAX-CATEGORIES (item → concepts) ──\n")
    # ================================================================

    check("categories for unclassified item = 0",
          [': _T T-INIT',
           '  S" A" TAX-ADD DROP',
           '  42 TAX-CATEGORIES NIP . ;',
           '_T'],
          "0 ")

    check("categories returns 1 when item in 1 concept",
          ['VARIABLE C',
           ': _T T-INIT',
           '  S" A" TAX-ADD C !',
           '  42 C @ TAX-CLASSIFY',
           '  42 TAX-CATEGORIES NIP . ;',
           '_T'],
          "1 ")

    check("categories returns 2 when item in 2 concepts",
          ['VARIABLE CA  VARIABLE CB',
           ': _T T-INIT',
           '  S" A" TAX-ADD CA !',
           '  S" B" TAX-ADD CB !',
           '  42 CA @ TAX-CLASSIFY',
           '  42 CB @ TAX-CLASSIFY',
           '  42 TAX-CATEGORIES NIP . ;',
           '_T'],
          "2 ")

    # ================================================================
    print("\n── TAX-ITEMS-DEEP ──\n")
    # ================================================================

    check("items-deep includes child items",
          ['VARIABLE P  VARIABLE C',
           ': _T T-INIT',
           '  S" A" TAX-ADD P !',
           '  S" B" P @ TAX-ADD-UNDER C !',
           '  100 P @ TAX-CLASSIFY',        # item on parent
           '  200 C @ TAX-CLASSIFY',         # item on child
           '  P @ TAX-ITEMS-DEEP NIP . ;',
           '_T'],
          "2 ")

    check("items-deep with grandchild items",
          ['VARIABLE P  VARIABLE C  VARIABLE G',
           ': _T T-INIT',
           '  S" A" TAX-ADD P !',
           '  S" B" P @ TAX-ADD-UNDER C !',
           '  S" D" C @ TAX-ADD-UNDER G !',
           '  100 P @ TAX-CLASSIFY',
           '  200 C @ TAX-CLASSIFY',
           '  300 G @ TAX-CLASSIFY',
           '  P @ TAX-ITEMS-DEEP NIP . ;',
           '_T'],
          "3 ")

    # ================================================================
    print("\n── TAX-EACH-CHILD / TAX-EACH-ROOT ──\n")
    # ================================================================

    check("each-child visits all children",
          ['VARIABLE _EACC  VARIABLE R',
           ': _EINC  TAX-ID _EACC @ + _EACC ! ;',
           ': _T T-INIT',
           '  0 _EACC !',
           '  S" P" TAX-ADD R !',
           '  S" A" R @ TAX-ADD-UNDER DROP',    # ID=2
           '  S" B" R @ TAX-ADD-UNDER DROP',    # ID=3
           "  ['] _EINC R @ TAX-EACH-CHILD",
           '  _EACC @ . ;',                     # 2+3=5
           '_T'],
          "5 ")

    check("each-root visits all roots",
          ['VARIABLE _EACC2',
           ': _EINC2  TAX-ID _EACC2 @ + _EACC2 ! ;',
           ': _T T-INIT',
           '  0 _EACC2 !',
           '  S" A" TAX-ADD DROP',              # ID=1
           '  S" B" TAX-ADD DROP',              # ID=2
           '  S" C" TAX-ADD DROP',              # ID=3
           "  ['] _EINC2 TAX-EACH-ROOT",
           '  _EACC2 @ . ;',                   # 1+2+3=6
           '_T'],
          "6 ")

    # ================================================================
    print("\n── TAX-DFS / TAX-DFS-ALL ──\n")
    # ================================================================

    check("dfs visits root + children",
          ['VARIABLE _DCNT  VARIABLE R',
           ': _DINC  DROP 1 _DCNT +! ;',
           ': _T T-INIT',
           '  0 _DCNT !',
           '  S" P" TAX-ADD R !',
           '  S" A" R @ TAX-ADD-UNDER DROP',
           '  S" B" R @ TAX-ADD-UNDER DROP',
           "  ['] _DINC R @ TAX-DFS",
           '  _DCNT @ . ;',                    # P + A + B = 3
           '_T'],
          "3 ")

    check("dfs-all visits entire taxonomy",
          ['VARIABLE _DCNT2  VARIABLE RA',
           ': _DINC2  DROP 1 _DCNT2 +! ;',
           ': _T T-INIT',
           '  0 _DCNT2 !',
           '  S" A" TAX-ADD RA !',
           '  S" B" TAX-ADD DROP',
           '  S" C" RA @ TAX-ADD-UNDER DROP',
           "  ['] _DINC2 TAX-DFS-ALL",
           '  _DCNT2 @ . ;',                   # A, C, B = 3
           '_T'],
          "3 ")

    # ================================================================
    print("\n── TAX-STATS ──\n")
    # ================================================================

    check("stats after classify",
          ['VARIABLE C',
           ': _T T-INIT',
           '  S" A" TAX-ADD C !',
           '  42 C @ TAX-CLASSIFY',
           '  TAX-STATS . . ;',                # links concepts
           '_T'],
          "1 1 ")

    check("stats after remove concept + links",
          ['VARIABLE C',
           ': _T T-INIT',
           '  S" A" TAX-ADD C !',
           '  42 C @ TAX-CLASSIFY',
           '  C @ TAX-REMOVE',
           '  TAX-STATS . . ;',                # 0 links 0 concepts
           '_T'],
          "0 0 ")

    # ================================================================
    print("\n── TAX-FIND-SYNONYM ──\n")
    # ================================================================

    check("find-synonym finds by own label",
          ['VARIABLE C1',
           ': _T T-INIT',
           '  S" Cat" TAX-ADD C1 !',
           '  S" cat" TAX-FIND-SYNONYM  0<> IF 1 ELSE 0 THEN . ;',
           '_T'],
          "1 ")

    check("find-synonym finds via ring-member label",
          ['VARIABLE C1  VARIABLE C2',
           ': _T T-INIT',
           '  S" Cat" TAX-ADD C1 !',
           '  S" Feline" TAX-ADD C2 !',
           '  C1 @ C2 @ TAX-ADD-SYNONYM',
           '  S" Feline" TAX-FIND-SYNONYM  0<> IF 1 ELSE 0 THEN . ;',
           '_T'],
          "1 ")

    # ================================================================
    print("\n── Edge cases ──\n")
    # ================================================================

    check("remove from synonym ring cleans up",
          ['VARIABLE C1  VARIABLE C2',
           ': _T T-INIT',
           '  S" A" TAX-ADD C1 !',
           '  S" B" TAX-ADD C2 !',
           '  C1 @ C2 @ TAX-ADD-SYNONYM',
           '  C1 @ TAX-REMOVE',
           '  C2 @ TAX-SYNONYMS NIP . ;',   # C2 alone
           '_T'],
          "1 ")

    check("classify then remove concept clears links",
          ['VARIABLE C',
           ': _T T-INIT',
           '  S" A" TAX-ADD C !',
           '  42 C @ TAX-CLASSIFY',
           '  C @ TAX-REMOVE',
           '  TAX-STATS . . ;',             # 0 0
           '_T'],
          "0 0 ")

    check("move preserves children",
          ['VARIABLE PA  VARIABLE PB',
           ': _T T-INIT',
           '  S" A" TAX-ADD PA !',
           '  S" B" TAX-ADD PB !',
           '  S" C" PA @ TAX-ADD-UNDER DROP',
           '  PA @ PB @ TAX-MOVE',            # move A under B
           '  PA @ TAX-CHILDREN NIP .',        # A still has child C
           '  PB @ TAX-CHILDREN NIP . ;',      # B has child A
           '_T'],
          "1 1 ")

    check("double remove is safe (0 arg)",
          [': _T T-INIT',
           '  0 TAX-REMOVE',                  # should not crash
           '  TAX-COUNT . ;',
           '_T'],
          "0 ")

    # ────────────────────────────────────────────────────────────────

    print()
    print("=" * 40)
    print(f"  {_pass} passed, {_fail} failed")
    print("=" * 40)
    sys.exit(1 if _fail else 0)
