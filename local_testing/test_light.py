#!/usr/bin/env python3
"""Test suite for Akashic light.f (akashic/store/light.f).

Phase 3b Step 2 — Light Client Protocol (SMT-backed).

Tests:
  - Compile check (light.f loads cleanly)
  - LC-STATE-LEAF (finds account, returns flag, hashes entry)
  - LC-STATE-LEAF miss (returns 0 for unknown address)
  - LC-STATE-PROOF (generates SMT proof for existing account)
  - LC-STATE-PROOF miss (returns 0 for unknown account)
  - LC-VERIFY-STATE (verify SMT proof against root)
  - Round-trip (prove + verify = TRUE)
  - Proof changes after state mutation
  - Different accounts get different proofs
  - LC-STATE-ROOT-AT (returns root for genesis block)
  - LC-BLOCK-HEADER (returns block header at height 0)
  - Two-account round-trip (both proofs verify independently)
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")

# Dependency file paths (in load order)
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
SEM_F      = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")
GUARD_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "guard.f")
FP16_F     = os.path.join(ROOT_DIR, "akashic", "math", "fp16.f")
SHA512_F   = os.path.join(ROOT_DIR, "akashic", "math", "sha512.f")
FIELD_F    = os.path.join(ROOT_DIR, "akashic", "math", "field.f")
SHA3_F     = os.path.join(ROOT_DIR, "akashic", "math", "sha3.f")
RANDOM_F   = os.path.join(ROOT_DIR, "akashic", "math", "random.f")
ED25519_F  = os.path.join(ROOT_DIR, "akashic", "math", "ed25519.f")
SPHINCS_F  = os.path.join(ROOT_DIR, "akashic", "math", "sphincs-plus.f")
CBOR_F     = os.path.join(ROOT_DIR, "akashic", "cbor", "cbor.f")
FMT_F      = os.path.join(ROOT_DIR, "akashic", "utils", "fmt.f")
MERKLE_F   = os.path.join(ROOT_DIR, "akashic", "math", "merkle.f")
SMT_F      = os.path.join(ROOT_DIR, "akashic", "store", "smt.f")
TX_F       = os.path.join(ROOT_DIR, "akashic", "store", "tx.f")
STATE_F    = os.path.join(ROOT_DIR, "akashic", "store", "state.f")
BLOCK_F    = os.path.join(ROOT_DIR, "akashic", "store", "block.f")
LIGHT_F    = os.path.join(ROOT_DIR, "akashic", "store", "light.f")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# ── Emulator helpers ──

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
    print("[*] Building snapshot: BIOS + KDOS + light.f deps ...")
    t0 = time.time()
    bios_code   = _load_bios()
    kdos_lines  = _load_forth_lines(KDOS_PATH)

    # Load all deps in correct topological order
    # light.f needs: state.f + block.f (both need sha3, merkle, tx, etc.)
    dep_lines = []
    for path in [EVENT_F, SEM_F, GUARD_F, FP16_F,
                 SHA512_F, FIELD_F, SHA3_F, RANDOM_F,
                 ED25519_F, SPHINCS_F, CBOR_F, FMT_F,
                 MERKLE_F, SMT_F, TX_F, STATE_F, BLOCK_F, LIGHT_F]:
        dep_lines += _load_forth_lines(path)

    helpers = [
        'CREATE _TB 512 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        ': .HEX  ( addr n -- ) FMT-.HEX ;',
        'VARIABLE _PL',
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
        print(f"  Aborting — light.f failed to compile cleanly.")
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

# ── Forth helpers ──

def create_hex_buf(var_name, hex_str):
    bs = bytes.fromhex(hex_str)
    n = len(bs)
    lines = [f'CREATE {var_name} {n} ALLOT']
    for i, b in enumerate(bs):
        lines.append(f'{b} {var_name} {i} + C!')
    return lines

# ── Test vector keys (from RFC 8032 TV1, TV2, TV3) ──

TV1_SEED = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
TV1_PUB  = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"

TV2_SEED = "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
TV2_PUB  = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"

TV3_SEED = "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7"
TV3_PUB  = "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025"

def _keygen_preamble():
    """Create three keypairs, address buffers, and initialize state."""
    lines = create_hex_buf('_SEED1', TV1_SEED) + [
        'CREATE _PUB1 32 ALLOT',
        'CREATE _PRIV1 64 ALLOT',
        '_SEED1 _PUB1 _PRIV1 ED25519-KEYGEN',
        'CREATE _ADDR1 32 ALLOT',
        '_PUB1 _ADDR1 ST-ADDR-FROM-KEY',
    ] + create_hex_buf('_SEED2', TV2_SEED) + [
        'CREATE _PUB2 32 ALLOT',
        'CREATE _PRIV2 64 ALLOT',
        '_SEED2 _PUB2 _PRIV2 ED25519-KEYGEN',
        'CREATE _ADDR2 32 ALLOT',
        '_PUB2 _ADDR2 ST-ADDR-FROM-KEY',
    ] + create_hex_buf('_SEED3', TV3_SEED) + [
        'CREATE _PUB3 32 ALLOT',
        'CREATE _PRIV3 64 ALLOT',
        '_SEED3 _PUB3 _PRIV3 ED25519-KEYGEN',
        'CREATE _ADDR3 32 ALLOT',
        '_PUB3 _ADDR3 ST-ADDR-FROM-KEY',
        # Init state
        'ST-INIT DROP',
    ]
    return lines

# ── Tests ──

def test_compile():
    """light.f loads cleanly."""
    print("\n=== Compile check ===")
    check("Module loaded", ['1 2 + .'], "3")

def test_lc_state_leaf():
    """LC-STATE-LEAF finds an account and returns TRUE."""
    print("\n=== LC-STATE-LEAF ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'CREATE _LEAF 32 ALLOT',
        '_ADDR1 _LEAF LC-STATE-LEAF',
        'IF ." FOUND" ELSE ." MISS" THEN',
    ]
    check("finds existing account", lines, "FOUND")

    # Two accounts: both should be findable
    lines2 = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        '_ADDR2 2000 ST-CREATE DROP',
        'CREATE _LEAF 32 ALLOT',
        '." A=" _ADDR1 _LEAF LC-STATE-LEAF .',
        '." B=" _ADDR2 _LEAF LC-STATE-LEAF .',
    ]
    check_fn("both accounts found", lines2,
             lambda o: "A=-1" in o.replace(" ", "") and "B=-1" in o.replace(" ", ""),
             "should find both (TRUE=-1)")

    # Leaf hash is non-zero
    lines3 = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'CREATE _LEAF 32 ALLOT',
        '_ADDR1 _LEAF LC-STATE-LEAF DROP',
        '_LEAF 32 0 DO DUP I + C@ OR LOOP NIP',
        '0<> IF ." NONZERO" ELSE ." ZERO" THEN',
    ]
    check("leaf hash is non-zero", lines3, "NONZERO")

def test_lc_state_leaf_miss():
    """LC-STATE-LEAF returns FALSE (0) for unknown address."""
    print("\n=== LC-STATE-LEAF miss ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'CREATE _LEAF 32 ALLOT',
        '_ADDR2 _LEAF LC-STATE-LEAF',
        '0= IF ." MISS" ELSE ." FOUND" THEN',
    ]
    check("unknown address returns 0", lines, "MISS")

def test_lc_state_proof():
    """LC-STATE-PROOF generates an SMT proof with variable length."""
    print("\n=== LC-STATE-PROOF ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'CREATE _PROOF 10240 ALLOT',
        '_ADDR1 _PROOF LC-STATE-PROOF .',
    ]
    check_fn("proof len > 0", lines,
             lambda o: any(int(w) > 0 for w in o.strip().split() if w.lstrip('-').isdigit()),
             "expected positive proof length")

    # Proof buffer is non-zero (at least some siblings are populated)
    lines2 = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'CREATE _PROOF 10240 ALLOT',
        '_ADDR1 _PROOF LC-STATE-PROOF DROP',
        '_PROOF 256 0 DO DUP I + C@ OR LOOP NIP',
        '0<> IF ." NONZERO" ELSE ." ZERO" THEN',
    ]
    check("proof buffer non-zero", lines2, "NONZERO")

def test_lc_state_proof_miss():
    """LC-STATE-PROOF returns 0 for unknown address."""
    print("\n=== LC-STATE-PROOF miss ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'CREATE _PROOF 10240 ALLOT',
        '_ADDR2 _PROOF LC-STATE-PROOF .',
    ]
    check("missing account returns 0", lines, " 0")

def test_lc_verify_state():
    """LC-VERIFY-STATE wraps SMT-VERIFY."""
    print("\n=== LC-VERIFY-STATE ===")
    # Generate proof for account, then verify
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'CREATE _PROOF 10240 ALLOT',
        'CREATE _LEAF 32 ALLOT',
        'CREATE _ROOT 32 ALLOT',
        # Generate proof and save len
        '_ADDR1 _PROOF LC-STATE-PROOF _PL !',
        # Get leaf hash
        '_ADDR1 _LEAF LC-STATE-LEAF DROP',
        # Get current root
        'ST-ROOT _ROOT 32 CMOVE',
        # Verify: ( key leaf proof len root -- flag )
        '_ADDR1 _LEAF _PROOF _PL @ _ROOT LC-VERIFY-STATE IF ." VALID" ELSE ." INVALID" THEN',
    ]
    check("proof verifies", lines, "VALID")

def test_round_trip():
    """Full round-trip: create account, prove, verify."""
    print("\n=== Round-trip proof ===")
    lines = _keygen_preamble() + [
        '_ADDR1 5000 ST-CREATE DROP',
        '_ADDR2 3000 ST-CREATE DROP',
        'CREATE _PROOF 10240 ALLOT',
        'CREATE _LEAF 32 ALLOT',
        'CREATE _ROOT 32 ALLOT',
        # Prove account 1
        '_ADDR1 _PROOF LC-STATE-PROOF _PL !',
        '_ADDR1 _LEAF LC-STATE-LEAF DROP',
        'ST-ROOT _ROOT 32 CMOVE',
        '_ADDR1 _LEAF _PROOF _PL @ _ROOT LC-VERIFY-STATE IF ." RT1-OK" ELSE ." RT1-FAIL" THEN',
    ]
    check("account 1 round-trip", lines, "RT1-OK")

    # Same for account 2
    lines2 = _keygen_preamble() + [
        '_ADDR1 5000 ST-CREATE DROP',
        '_ADDR2 3000 ST-CREATE DROP',
        'CREATE _PROOF 10240 ALLOT',
        'CREATE _LEAF 32 ALLOT',
        'CREATE _ROOT 32 ALLOT',
        # Prove account 2
        '_ADDR2 _PROOF LC-STATE-PROOF _PL !',
        '_ADDR2 _LEAF LC-STATE-LEAF DROP',
        'ST-ROOT _ROOT 32 CMOVE',
        '_ADDR2 _LEAF _PROOF _PL @ _ROOT LC-VERIFY-STATE IF ." RT2-OK" ELSE ." RT2-FAIL" THEN',
    ]
    check("account 2 round-trip", lines2, "RT2-OK")

def test_proof_changes_on_mutation():
    """Proof root changes after state mutation."""
    print("\n=== Proof changes on mutation ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'CREATE _R1 32 ALLOT  CREATE _R2 32 ALLOT',
        # Root before adding second account
        'ST-ROOT _R1 32 CMOVE',
        # Add second account
        '_ADDR2 2000 ST-CREATE DROP',
        # Root after
        'ST-ROOT _R2 32 CMOVE',
        # Compare
        '_R1 _R2 32 0 DO OVER I + C@ OVER I + C@ XOR OR LOOP NIP NIP',
        '0<> IF ." CHANGED" ELSE ." SAME" THEN',
    ]
    check("root changes after mutation", lines, "CHANGED")

    # Old proof no longer verifies against new root
    lines2 = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'CREATE _PROOF 10240 ALLOT',
        'CREATE _LEAF 32 ALLOT',
        'CREATE _ROOT1 32 ALLOT  CREATE _ROOT2 32 ALLOT',
        # Prove under old state
        '_ADDR1 _PROOF LC-STATE-PROOF _PL !',
        '_ADDR1 _LEAF LC-STATE-LEAF DROP',
        'ST-ROOT _ROOT1 32 CMOVE',
        # Mutate state
        '_ADDR2 9999 ST-CREATE DROP',
        # New root
        'ST-ROOT _ROOT2 32 CMOVE',
        # Proof now fails against new root
        '_ADDR1 _LEAF _PROOF _PL @ _ROOT2 LC-VERIFY-STATE IF ." STILL-VALID" ELSE ." INVALID" THEN',
    ]
    check("old proof fails with new root", lines2, "INVALID")

def test_different_proofs():
    """Different accounts produce different proof buffers."""
    print("\n=== Different proofs ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        '_ADDR2 2000 ST-CREATE DROP',
        'CREATE _P1 10240 ALLOT  CREATE _P2 10240 ALLOT',
        '_ADDR1 _P1 LC-STATE-PROOF DROP',
        '_ADDR2 _P2 LC-STATE-PROOF DROP',
        # Compare proof buffers (first 256 bytes)
        '_P1 _P2 256 0 DO OVER I + C@ OVER I + C@ XOR OR LOOP NIP NIP',
        '0<> IF ." DIFF" ELSE ." SAME" THEN',
    ]
    check("different accounts → different proofs", lines, "DIFF")

def test_lc_state_root_at():
    """LC-STATE-ROOT-AT returns the state root from a block header."""
    print("\n=== LC-STATE-ROOT-AT ===")
    # After CHAIN-INIT, height 0 (genesis) should have a state root
    lines = _keygen_preamble() + [
        'CHAIN-INIT',
        '0 LC-STATE-ROOT-AT DUP 0<> IF',
        '  32 0 DO DUP I + C@ OR LOOP NIP',
        '  0<> IF ." ROOT-OK" ELSE ." ROOT-ZERO" THEN',
        'ELSE DROP ." NO-BLOCK" THEN',
    ]
    check("genesis state root available", lines, "ROOT-OK")

    # Future block returns 0
    lines2 = _keygen_preamble() + [
        'CHAIN-INIT',
        '999 LC-STATE-ROOT-AT 0= IF ." NOBLOCK" ELSE ." FOUND" THEN',
    ]
    check("future block returns 0", lines2, "NOBLOCK")

def test_lc_block_header():
    """LC-BLOCK-HEADER returns block header at height."""
    print("\n=== LC-BLOCK-HEADER ===")
    lines = _keygen_preamble() + [
        'CHAIN-INIT',
        '0 LC-BLOCK-HEADER DUP 0<> IF',
        '  BLK-HEIGHT@ 0= IF ." HEIGHT-0" ELSE ." WRONG-H" THEN',
        'ELSE DROP ." NO-BLOCK" THEN',
    ]
    check("genesis header at height 0", lines, "HEIGHT-0")

def test_two_account_round_trip():
    """Both accounts verify independently with the same root."""
    print("\n=== Two-account round-trip ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        '_ADDR2 2000 ST-CREATE DROP',
        '_ADDR3 3000 ST-CREATE DROP',
        'CREATE _P 10240 ALLOT  CREATE _L 32 ALLOT  CREATE _R 32 ALLOT',
        'VARIABLE _LEN',
        'ST-ROOT _R 32 CMOVE',
        # Account 1
        '_ADDR1 _P LC-STATE-PROOF _LEN !',
        '_ADDR1 _L LC-STATE-LEAF DROP',
        '_ADDR1 _L _P _LEN @ _R LC-VERIFY-STATE',
        'IF ." V1" ELSE ." F1" THEN',
        # Account 2 (reuse buffers)
        '_ADDR2 _P LC-STATE-PROOF _LEN !',
        '_ADDR2 _L LC-STATE-LEAF DROP',
        '_ADDR2 _L _P _LEN @ _R LC-VERIFY-STATE',
        'IF ." V2" ELSE ." F2" THEN',
        # Account 3
        '_ADDR3 _P LC-STATE-PROOF _LEN !',
        '_ADDR3 _L LC-STATE-LEAF DROP',
        '_ADDR3 _L _P _LEN @ _R LC-VERIFY-STATE',
        'IF ." V3" ELSE ." F3" THEN',
    ]
    check_fn("all 3 accounts verify", lines,
             lambda o: "V1" in o and "V2" in o and "V3" in o,
             "expected V1 V2 V3")

# ── Main ──

def main():
    build_snapshot()

    test_compile()
    test_lc_state_leaf()
    test_lc_state_leaf_miss()
    test_lc_state_proof()
    test_lc_state_proof_miss()
    test_lc_verify_state()
    test_round_trip()
    test_proof_changes_on_mutation()
    test_different_proofs()
    test_lc_state_root_at()
    test_lc_block_header()
    test_two_account_round_trip()

    print(f"\n{'='*40}")
    print(f"  {_pass_count} passed, {_fail_count} failed")
    print(f"{'='*40}")
    sys.exit(1 if _fail_count else 0)

if __name__ == "__main__":
    main()
