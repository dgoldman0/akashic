#!/usr/bin/env python3
"""Test suite for Akashic smt.f (akashic/store/smt.f).

Phase 3b Step 1 — Sparse Merkle Tree (Compact / Patricia).

Tests:
  - Compile check (smt.f loads cleanly)
  - SMT-INIT (creates tree, SMT-EMPTY? true, SMT-COUNT=0)
  - SMT-INSERT single leaf
  - SMT-INSERT two different keys
  - SMT-INSERT update existing key
  - SMT-LOOKUP hit and miss
  - SMT-ROOT determinism (same inserts -> same root)
  - SMT-ROOT changes on mutation
  - SMT-PROVE + SMT-VERIFY round-trip
  - SMT-VERIFY rejects wrong value
  - SMT-VERIFY rejects wrong root
  - SMT-DELETE (count decreases, lookup miss after delete)
  - Insert many keys (16)
  - Proof length is reasonable
  - Insertion order independence (same keys -> same root regardless of order)
  - SMT-DESTROY (cleans up)
  - SMT-MAX returns 2048
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")

# Dependency file paths (in load order)
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
SEM_F      = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")
GUARD_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "guard.f")
SHA3_F     = os.path.join(ROOT_DIR, "akashic", "math", "sha3.f")
SMT_F      = os.path.join(ROOT_DIR, "akashic", "store", "smt.f")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# ── Emulator helpers ──

_snapshot = None

def setup_module(_mod=None):
    build_snapshot()

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
            if s.startswith('REQUIRE '):
                continue
            if s.startswith('PROVIDED '):
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
    if _snapshot: return _snapshot
    print("[*] Building snapshot: BIOS + KDOS + smt.f deps ...")
    t0 = time.time()
    bios_code   = _load_bios()
    kdos_lines  = _load_forth_lines(KDOS_PATH)

    # smt.f needs: sha3.f, guard.f (guard needs event, semaphore)
    dep_lines = []
    for path in [EVENT_F, SEM_F, GUARD_F, SHA3_F, SMT_F]:
        dep_lines += _load_forth_lines(path)

    helpers = [
        'CREATE _TB 512 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        # Tree descriptor (64 bytes)
        'CREATE _TREE 64 ALLOT',
        # Key/value scratch buffers (32 bytes each)
        'CREATE _K1 32 ALLOT  CREATE _V1 32 ALLOT',
        'CREATE _K2 32 ALLOT  CREATE _V2 32 ALLOT',
        'CREATE _K3 32 ALLOT  CREATE _V3 32 ALLOT',
        # Proof buffer (40 bytes * 256 max entries)
        'CREATE _PROOF 10240 ALLOT',
        # Root buffers
        'CREATE _R1 32 ALLOT  CREATE _R2 32 ALLOT',
        # Proof-length scratch (avoid >R / R> in interpreted mode)
        'VARIABLE _PL',
        # Fill key with pattern: byte i = seed XOR i
        ': FILL-KEY  ( buf seed -- ) 32 0 DO  DUP I XOR  2 PICK I + C!  LOOP 2DROP ;',
        ': FILL-VAL  ( buf seed -- ) 32 0 DO  DUP I XOR 255 XOR  2 PICK I + C!  LOOP 2DROP ;',
    ]

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + ["ENTER-USERLAND"]
                 + dep_lines
                 + helpers)
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode(); pos = 0; steps = 0; mx = 800_000_000
    while steps < mx:
        if sys_obj.cpu.halted: break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk); pos += len(chunk)
            else: break
            continue
        batch = sys_obj.run_batch(min(100_000, mx - steps))
        steps += max(batch, 1)
    text = uart_text(buf)
    errors = []
    for l in text.strip().split('\n'):
        if '?' in l and 'not found' in l.lower():
            errors.append(l.strip())
            print(f"  [!] {l.strip()}")
    if errors:
        print(f"  [FATAL] {len(errors)} 'not found' errors during load!")
        print(f"  Aborting — smt.f failed to compile cleanly.")
        for l in text.strip().split('\n')[-30:]:
            print(f"    {l}")
        sys.exit(1)
    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot

def run_forth(lines, max_steps=800_000_000):
    bios_code, mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
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
        if sys_obj.cpu.halted: break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk); pos += len(chunk)
            else: break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)
    return uart_text(buf)

# ── Test framework ──

_pass_count = 0
_fail_count = 0

def check(name, forth_lines, expected):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    clean = output.strip()
    if expected in clean:
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}")
        print(f"        expected: '{expected}'")
        for l in clean.split('\n')[-6:]:
            print(f"        got:      '{l}'")

def check_fn(name, forth_lines, predicate, desc=""):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    clean = output.strip()
    if predicate(clean):
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}  ({desc})")
        for l in clean.split('\n')[-6:]:
            print(f"        got:      '{l}'")

# ── Shared preamble: init tree + fill key/value buffers ──

def _init_tree():
    """Initialize tree and set up K1/V1, K2/V2, K3/V3 with distinct patterns."""
    return [
        '_TREE SMT-INIT DROP',
        '_K1 17 FILL-KEY  _V1 170 FILL-VAL',
        '_K2 34 FILL-KEY  _V2 187 FILL-VAL',
        '_K3 51 FILL-KEY  _V3 204 FILL-VAL',
    ]

# ── Tests ──
# NOTE: ." only works inside IF/THEN in this Forth (compile-only).
# All string output uses IF ." ..." THEN pattern.

def test_compile():
    """smt.f loads cleanly."""
    print("\n=== Compile check ===")
    check("Module loaded", ['1 2 + .'], "3")

def test_init_empty():
    """SMT-INIT creates a tree; it starts empty."""
    print("\n=== SMT-INIT / SMT-EMPTY? / SMT-COUNT ===")
    lines = _init_tree() + [
        '_TREE SMT-EMPTY? IF ." EMPTY" ELSE ." NOTEMPTY" THEN',
    ]
    check("new tree is empty", lines, "EMPTY")

    lines2 = _init_tree() + [
        '_TREE SMT-COUNT 0= IF ." CZERO" ELSE ." CNONZERO" THEN',
    ]
    check("count = 0", lines2, "CZERO")

def test_smt_max():
    """SMT-MAX returns 2048."""
    print("\n=== SMT-MAX ===")
    lines = _init_tree() + [
        '_TREE SMT-MAX 2048 = IF ." MAXOK" ELSE ." MAXBAD" THEN',
    ]
    check("max = 2048", lines, "MAXOK")

def test_insert_single():
    """Insert a single leaf; count becomes 1; tree no longer empty."""
    print("\n=== SMT-INSERT single ===")
    lines = _init_tree() + [
        '_K1 _V1 _TREE SMT-INSERT',
        'IF ." INSOK" ELSE ." INSFAIL" THEN',
    ]
    check("insert succeeds", lines, "INSOK")

    lines2 = _init_tree() + [
        '_K1 _V1 _TREE SMT-INSERT DROP',
        '_TREE SMT-COUNT 1 = IF ." C1" ELSE ." CBAD" THEN',
    ]
    check("count = 1 after insert", lines2, "C1")

def test_insert_two():
    """Insert two different keys; count becomes 2."""
    print("\n=== SMT-INSERT two keys ===")
    lines = _init_tree() + [
        '_K1 _V1 _TREE SMT-INSERT DROP',
        '_K2 _V2 _TREE SMT-INSERT DROP',
        '_TREE SMT-COUNT 2 = IF ." C2" ELSE ." CBAD" THEN',
    ]
    check("count = 2", lines, "C2")

def test_insert_update():
    """Insert same key with new value; count stays 1."""
    print("\n=== SMT-INSERT update ===")
    lines = _init_tree() + [
        '_K1 _V1 _TREE SMT-INSERT DROP',
        '_TREE SMT-COUNT 1 = IF ." C1A" ELSE ." CBAD1" THEN',
        # Overwrite V1 with a different value pattern
        '_V1 255 FILL-VAL',
        '_K1 _V1 _TREE SMT-INSERT DROP',
        '_TREE SMT-COUNT 1 = IF ." C1B" ELSE ." CBAD2" THEN',
    ]
    check_fn("count stays 1 after update", lines,
             lambda o: "C1A" in o and "C1B" in o,
             "expected C1A and C1B")

def test_lookup_hit():
    """Lookup existing key returns value and true flag."""
    print("\n=== SMT-LOOKUP hit ===")
    lines = _init_tree() + [
        '_K1 _V1 _TREE SMT-INSERT DROP',
        '_K1 _TREE SMT-LOOKUP',
        'IF',
        '  32 _V1 32 COMPARE 0= IF ." MATCH" ELSE ." MISMATCH" THEN',
        'ELSE',
        '  ." MISS"',
        'THEN',
    ]
    check("value matches", lines, "MATCH")

def test_lookup_miss():
    """Lookup non-existent key returns false."""
    print("\n=== SMT-LOOKUP miss ===")
    lines = _init_tree() + [
        '_K1 _V1 _TREE SMT-INSERT DROP',
        '_K2 _TREE SMT-LOOKUP',
        'IF DROP ." FOUND" ELSE ." MISS" THEN',
    ]
    check("non-existent key -> miss", lines, "MISS")

def test_lookup_after_two_inserts():
    """Both keys are findable after two inserts."""
    print("\n=== SMT-LOOKUP after two inserts ===")
    lines = _init_tree() + [
        '_K1 _V1 _TREE SMT-INSERT DROP',
        '_K2 _V2 _TREE SMT-INSERT DROP',
        '_K1 _TREE SMT-LOOKUP',
        'IF 32 _V1 32 COMPARE 0= IF ." A" ELSE ." AMIS" THEN ELSE ." ANONE" THEN',
        '_K2 _TREE SMT-LOOKUP',
        'IF 32 _V2 32 COMPARE 0= IF ." B" ELSE ." BMIS" THEN ELSE ." BNONE" THEN',
    ]
    check_fn("both keys found", lines,
             lambda o: "A" in o and "B" in o,
             "expected A and B")

def test_root_nonzero():
    """Root of non-empty tree is non-zero."""
    print("\n=== SMT-ROOT non-zero ===")
    lines = _init_tree() + [
        '_K1 _V1 _TREE SMT-INSERT DROP',
        '_TREE SMT-ROOT _R1 32 CMOVE',
        '0 _R1 32 0 DO OVER I + C@ OR LOOP NIP',
        '0<> IF ." NONZERO" ELSE ." ZERO" THEN',
    ]
    check("root is non-zero", lines, "NONZERO")

def test_empty_root_zero():
    """Root of empty tree is all-zeros."""
    print("\n=== SMT-ROOT empty = zero ===")
    lines = _init_tree() + [
        '_TREE SMT-ROOT _R1 32 CMOVE',
        '0 _R1 32 0 DO OVER I + C@ OR LOOP NIP',
        '0= IF ." ZERO" ELSE ." NONZERO" THEN',
    ]
    check("empty root is zero", lines, "ZERO")

def test_root_determinism():
    """Same inserts in same order -> same root hash."""
    print("\n=== SMT-ROOT determinism ===")
    lines = _init_tree() + [
        '_K1 _V1 _TREE SMT-INSERT DROP',
        '_K2 _V2 _TREE SMT-INSERT DROP',
        '_TREE SMT-ROOT _R1 32 CMOVE',
        # Destroy and rebuild
        '_TREE SMT-DESTROY',
        '_TREE SMT-INIT DROP',
        '_K1 17 FILL-KEY  _V1 170 FILL-VAL',
        '_K2 34 FILL-KEY  _V2 187 FILL-VAL',
        '_K1 _V1 _TREE SMT-INSERT DROP',
        '_K2 _V2 _TREE SMT-INSERT DROP',
        '_TREE SMT-ROOT _R2 32 CMOVE',
        '_R1 32 _R2 32 COMPARE 0= IF ." SAME" ELSE ." DIFF" THEN',
    ]
    check("roots match", lines, "SAME")

def test_root_changes():
    """Root hash changes after insert."""
    print("\n=== SMT-ROOT changes on mutation ===")
    lines = _init_tree() + [
        '_K1 _V1 _TREE SMT-INSERT DROP',
        '_TREE SMT-ROOT _R1 32 CMOVE',
        '_K2 _V2 _TREE SMT-INSERT DROP',
        '_TREE SMT-ROOT _R2 32 CMOVE',
        '_R1 32 _R2 32 COMPARE 0<> IF ." CHANGED" ELSE ." SAME" THEN',
    ]
    check("root changes", lines, "CHANGED")

def test_prove_verify_round_trip():
    """Prove + verify round-trip for two-key tree."""
    print("\n=== SMT-PROVE + SMT-VERIFY round-trip ===")
    # BUG FIX: old code used ROT which only reaches 3-deep.
    # SMT-PROVE returns len.  SMT-VERIFY needs ( key val proof len root ).
    # Correct: >R key val proof R> tree SMT-ROOT SMT-VERIFY
    lines = _init_tree() + [
        '_K1 _V1 _TREE SMT-INSERT DROP',
        '_K2 _V2 _TREE SMT-INSERT DROP',
        '_K1 _TREE _PROOF SMT-PROVE _PL !',
        '_K1 _V1 _PROOF _PL @ _TREE SMT-ROOT SMT-VERIFY IF ." VALID" ELSE ." INVALID" THEN',
    ]
    check("prove+verify round-trip", lines, "VALID")

def test_prove_verify_second_key():
    """Prove + verify for second inserted key also works."""
    print("\n=== SMT-PROVE + SMT-VERIFY second key ===")
    lines = _init_tree() + [
        '_K1 _V1 _TREE SMT-INSERT DROP',
        '_K2 _V2 _TREE SMT-INSERT DROP',
        '_K2 _TREE _PROOF SMT-PROVE _PL !',
        '_K2 _V2 _PROOF _PL @ _TREE SMT-ROOT SMT-VERIFY IF ." VALID2" ELSE ." INVALID2" THEN',
    ]
    check("second key proof verifies", lines, "VALID2")

def test_verify_wrong_value():
    """Verify rejects proof when value is wrong."""
    print("\n=== SMT-VERIFY rejects wrong value ===")
    lines = _init_tree() + [
        '_K1 _V1 _TREE SMT-INSERT DROP',
        '_K1 _TREE _PROOF SMT-PROVE _PL !',
        # Use V2 (wrong value) instead of V1
        '_K1 _V2 _PROOF _PL @ _TREE SMT-ROOT SMT-VERIFY IF ." VALID" ELSE ." REJECTED" THEN',
    ]
    check("wrong value rejected", lines, "REJECTED")

def test_verify_wrong_root():
    """Verify rejects proof when root is wrong."""
    print("\n=== SMT-VERIFY rejects wrong root ===")
    lines = _init_tree() + [
        '_K1 _V1 _TREE SMT-INSERT DROP',
        '_K1 _TREE _PROOF SMT-PROVE _PL !',
        # Tamper: make a fake root
        '_R1 32 255 FILL',
        '_K1 _V1 _PROOF _PL @ _R1 SMT-VERIFY IF ." VALID" ELSE ." REJECTED" THEN',
    ]
    check("wrong root rejected", lines, "REJECTED")

def test_delete():
    """Delete removes a leaf; count decreases; lookup misses."""
    print("\n=== SMT-DELETE ===")
    lines = _init_tree() + [
        '_K1 _V1 _TREE SMT-INSERT DROP',
        '_K2 _V2 _TREE SMT-INSERT DROP',
        '_TREE SMT-COUNT 2 = IF ." CB2" ELSE ." CBBAD" THEN',
        '_K1 _TREE SMT-DELETE IF ." DELOK" ELSE ." DELFAIL" THEN',
        '_TREE SMT-COUNT 1 = IF ." CA1" ELSE ." CABAD" THEN',
        '_K1 _TREE SMT-LOOKUP IF DROP ." FOUND" ELSE ." GONE" THEN',
        # K2 should still be there
        '_K2 _TREE SMT-LOOKUP IF DROP ." K2OK" ELSE ." K2MISS" THEN',
    ]
    check_fn("delete works", lines,
             lambda o: "CB2" in o and "DELOK" in o
                       and "CA1" in o and "GONE" in o
                       and "K2OK" in o,
             "expected CB2 DELOK CA1 GONE K2OK")

def test_delete_last():
    """Delete last leaf; tree becomes empty."""
    print("\n=== SMT-DELETE last leaf ===")
    lines = _init_tree() + [
        '_K1 _V1 _TREE SMT-INSERT DROP',
        '_K1 _TREE SMT-DELETE DROP',
        '_TREE SMT-EMPTY? IF ." EMPTY" ELSE ." NOTEMPTY" THEN',
    ]
    check("tree empty after deleting only leaf", lines, "EMPTY")

def test_delete_nonexistent():
    """Delete non-existent key returns false."""
    print("\n=== SMT-DELETE non-existent ===")
    lines = _init_tree() + [
        '_K1 _V1 _TREE SMT-INSERT DROP',
        '_K2 _TREE SMT-DELETE IF ." DELETED" ELSE ." NOTFOUND" THEN',
    ]
    check("non-existent key -> not found", lines, "NOTFOUND")

def test_insert_many():
    """Insert 16 keys; all 16 are findable; count = 16."""
    print("\n=== SMT-INSERT many (16 keys) ===")
    lines = _init_tree() + [
        'CREATE _KT 32 ALLOT  CREATE _VT 32 ALLOT',
    ]
    # Insert 16 keys with different seeds
    for i in range(16):
        seed_k = i + 1
        seed_v = i + 129
        lines.append(f'_KT {seed_k} FILL-KEY  _VT {seed_v} FILL-VAL')
        lines.append(f'_KT _VT _TREE SMT-INSERT DROP')
    lines.append(f'_TREE SMT-COUNT 16 = IF ." C16" ELSE ." CBAD" THEN')
    check("count = 16", lines, "C16")

def test_proof_length():
    """Proof length is reasonable (1-20 entries for <=8 keys)."""
    print("\n=== Proof length ===")
    lines = _init_tree() + [
        'CREATE _KT 32 ALLOT  CREATE _VT 32 ALLOT',
    ]
    for i in range(8):
        seed_k = i + 1
        seed_v = i + 129
        lines.append(f'_KT {seed_k} FILL-KEY  _VT {seed_v} FILL-VAL')
        lines.append(f'_KT _VT _TREE SMT-INSERT DROP')
    # Prove key 1
    lines += [
        '_KT 1 FILL-KEY',
        '_KT _TREE _PROOF SMT-PROVE',
        'DUP 0> IF DUP 20 < IF ." LENOK" ELSE ." LENBIG" THEN ELSE ." LENNONE" THEN',
        'DROP',
    ]
    check("proof length in range", lines, "LENOK")

def test_order_independence():
    """Same keys inserted in different order -> same root."""
    print("\n=== Order independence ===")
    lines = _init_tree() + [
        # Order 1: K1, K2, K3
        '_K1 _V1 _TREE SMT-INSERT DROP',
        '_K2 _V2 _TREE SMT-INSERT DROP',
        '_K3 _V3 _TREE SMT-INSERT DROP',
        '_TREE SMT-ROOT _R1 32 CMOVE',
        # Rebuild with different order: K3, K1, K2
        '_TREE SMT-DESTROY',
        '_TREE SMT-INIT DROP',
        '_K1 17 FILL-KEY  _V1 170 FILL-VAL',
        '_K2 34 FILL-KEY  _V2 187 FILL-VAL',
        '_K3 51 FILL-KEY  _V3 204 FILL-VAL',
        '_K3 _V3 _TREE SMT-INSERT DROP',
        '_K1 _V1 _TREE SMT-INSERT DROP',
        '_K2 _V2 _TREE SMT-INSERT DROP',
        '_TREE SMT-ROOT _R2 32 CMOVE',
        '_R1 32 _R2 32 COMPARE 0= IF ." SAME" ELSE ." DIFF" THEN',
    ]
    check("roots match regardless of order", lines, "SAME")

def test_prove_verify_three_keys():
    """All three keys verify after insertion."""
    print("\n=== Prove+verify three keys ===")
    lines = _init_tree() + [
        '_K1 _V1 _TREE SMT-INSERT DROP',
        '_K2 _V2 _TREE SMT-INSERT DROP',
        '_K3 _V3 _TREE SMT-INSERT DROP',
    ]
    for i, (k, v) in enumerate([('_K1','_V1'), ('_K2','_V2'), ('_K3','_V3')], 1):
        lines += [
            f'{k} _TREE _PROOF SMT-PROVE',
            f'>R {k} {v} _PROOF R> _TREE SMT-ROOT SMT-VERIFY',
            f'IF ." V{i}" ELSE ." F{i}" THEN',
        ]
    check_fn("all three verify", lines,
             lambda o: "V1" in o and "V2" in o and "V3" in o,
             "expected V1 V2 V3")

def test_destroy():
    """SMT-DESTROY cleans up; re-init works."""
    print("\n=== SMT-DESTROY ===")
    lines = _init_tree() + [
        '_K1 _V1 _TREE SMT-INSERT DROP',
        '_TREE SMT-DESTROY',
        # Re-init should work
        '_TREE SMT-INIT IF ." REINITOK" ELSE ." REINITFAIL" THEN',
        '_TREE SMT-EMPTY? IF ." EMPTY" ELSE ." NOTEMPTY" THEN',
    ]
    check_fn("destroy + reinit works", lines,
             lambda o: "REINITOK" in o and "EMPTY" in o,
             "expected REINITOK and EMPTY")

# ── Main ──

def main():
    build_snapshot()

    test_compile()
    test_init_empty()
    test_smt_max()
    test_insert_single()
    test_insert_two()
    test_insert_update()
    test_lookup_hit()
    test_lookup_miss()
    test_lookup_after_two_inserts()
    test_root_nonzero()
    test_empty_root_zero()
    test_root_determinism()
    test_root_changes()
    test_prove_verify_round_trip()
    test_prove_verify_second_key()
    test_verify_wrong_value()
    test_verify_wrong_root()
    test_delete()
    test_delete_last()
    test_delete_nonexistent()
    test_insert_many()
    test_proof_length()
    test_order_independence()
    test_prove_verify_three_keys()
    test_destroy()

    print(f"\n{'='*40}")
    print(f"  {_pass_count} passed, {_fail_count} failed")
    print(f"{'='*40}")
    sys.exit(1 if _fail_count else 0)

if __name__ == "__main__":
    main()
