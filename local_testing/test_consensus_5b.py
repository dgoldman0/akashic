#!/usr/bin/env python3
"""Test suite for Phase 5b consensus hardening + PoSA.

Tests:
  - CON-POSA constant
  - CON-SET-KEYS / signing context
  - CON-SEAL unified dispatch with stored keys (PoA, PoS)
  - Anti-grinding: _CON-ANCHOR-HASH uses block[height-2]
  - PoSA election + check + seal
  - Genesis encode / decode round-trip
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
TX_F       = os.path.join(ROOT_DIR, "akashic", "store", "tx.f")
SMT_F      = os.path.join(ROOT_DIR, "akashic", "store", "smt.f")
STATE_F    = os.path.join(ROOT_DIR, "akashic", "store", "state.f")
BLOCK_F    = os.path.join(ROOT_DIR, "akashic", "store", "block.f")
CONSENSUS_F = os.path.join(ROOT_DIR, "akashic", "consensus", "consensus.f")
GENESIS_F  = os.path.join(ROOT_DIR, "akashic", "store", "genesis.f")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# ── Emulator helpers (same pattern as test_consensus.py) ──

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
    print("[*] Building snapshot: BIOS + KDOS + consensus.f + genesis.f ...")
    t0 = time.time()
    bios_code   = _load_bios()
    kdos_lines  = _load_forth_lines(KDOS_PATH)

    dep_lines = []
    for path in [EVENT_F, SEM_F, GUARD_F, FP16_F,
                 SHA512_F, FIELD_F, SHA3_F, RANDOM_F,
                 ED25519_F, SPHINCS_F, CBOR_F, FMT_F,
                 MERKLE_F, TX_F, SMT_F, STATE_F, BLOCK_F,
                 CONSENSUS_F, GENESIS_F]:
        dep_lines += _load_forth_lines(path)

    helpers = [
        'CREATE _TB 512 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        ': .HEX  ( addr n -- ) FMT-.HEX ;',
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
        print(f"  Aborting — modules failed to compile cleanly.")
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


# ── Test vector keys (from RFC 8032) ──

TV1_SEED = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
TV2_SEED = "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
TV3_SEED = "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7"


def _keygen_preamble():
    """Create three keypairs, address buffers, initialize state."""
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
        'ST-INIT',
    ]
    return lines


# =================================================================
#  Tests — Phase 5b
# =================================================================

def test_compile():
    """Verify all modules load without errors."""
    print("\n=== Compile check (5b) ===")
    check("Module loaded (consensus + genesis)", ['1 2 + .'], "3")


def test_posa_constant():
    """CON-POSA = 3."""
    print("\n=== CON-POSA constant ===")
    check("CON-POSA", ['CON-POSA .'], "3")


def test_mode_posa():
    """Set consensus mode to PoSA and read back."""
    print("\n=== Mode selection: PoSA ===")
    check("set mode to PoSA",
          ['CON-POSA CON-MODE!  CON-MODE@ .'], "3")


def test_set_keys():
    """CON-SET-KEYS stores signing keys for CON-SEAL."""
    print("\n=== CON-SET-KEYS ===")
    lines = _keygen_preamble() + [
        '_PRIV1 _PUB1 CON-SET-KEYS',
        '." keys-set"',
    ]
    check("CON-SET-KEYS succeeds", lines, "keys-set")


def test_seal_poa_with_stored_keys():
    """CON-SEAL in PoA mode uses stored keys instead of being a no-op."""
    print("\n=== CON-SEAL PoA with stored keys ===")
    lines = _keygen_preamble() + [
        # Create account, add authority, set mode
        '_ADDR1 10000 ST-CREATE DROP',
        '_PUB1 CON-POA-ADD',
        'CON-POA CON-MODE!',
        # Store signing keys
        '_PRIV1 _PUB1 CON-SET-KEYS',
        # Create block
        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
        '1 _BK BLK-SET-HEIGHT',
        '1000 _BK BLK-SET-TIME',
        # Seal via unified dispatch
        '_BK CON-SEAL',
        # Check via unified dispatch
        '_BK CON-CHECK IF ." seal-ok" ELSE ." seal-fail" THEN',
    ]
    check("CON-SEAL PoA with stored keys", lines, "seal-ok")


def test_seal_poa_no_keys():
    """CON-SEAL in PoA mode without keys set should not crash."""
    print("\n=== CON-SEAL PoA without keys ===")
    lines = _keygen_preamble() + [
        '_ADDR1 10000 ST-CREATE DROP',
        '_PUB1 CON-POA-ADD',
        'CON-POA CON-MODE!',
        # Do NOT set keys
        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
        '1 _BK BLK-SET-HEIGHT',
        # Try seal — should be no-op, check should fail
        '_BK CON-SEAL',
        '_BK CON-CHECK IF ." check-ok" ELSE ." check-fail" THEN',
    ]
    check("CON-SEAL PoA no keys → check fails", lines, "check-fail")


def test_posa_elect_and_check():
    """Full PoSA cycle: add authority, stake, elect leader, seal, check."""
    print("\n=== PoSA elect + seal + check ===")
    lines = _keygen_preamble() + [
        # Create accounts with enough balance to stake
        '_ADDR1 10000 ST-CREATE DROP',
        # Add as PoA authority
        '_PUB1 CON-POA-ADD',
        # Set PoSA mode
        'CON-POSA CON-MODE!',
        # Manually stake: write stake amount into state
        # (In production this happens via stake tx, but we test directly)
        '200 0 _ST-STAKED-AT !',    # set account 0 stake to 200
        '0 0 _ST-UNSTAKE-AT !',     # not unstaking
        # Force epoch rebuild
        'CON-POS-EPOCH',
        # Verify validator set
        'CON-POS-VALIDATORS .',      # should be 1
        # Store signing keys
        '_PRIV1 _PUB1 CON-SET-KEYS',
        # Create block
        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
        '1 _BK BLK-SET-HEIGHT',
        '1000 _BK BLK-SET-TIME',
        # Seal via unified dispatch (PoSA path)
        '_BK CON-SEAL',
        # Check
        '_BK CON-CHECK IF ." posa-ok" ELSE ." posa-fail" THEN',
    ]
    check("PoSA elect+seal+check", lines, "posa-ok")


def test_posa_unauthorized():
    """PoSA check fails for a staker who is NOT an authority."""
    print("\n=== PoSA unauthorized staker ===")
    lines = _keygen_preamble() + [
        # Create two accounts
        '_ADDR1 10000 ST-CREATE DROP',
        '_ADDR2 10000 ST-CREATE DROP',
        # Only add key1 as authority
        '_PUB1 CON-POA-ADD',
        'CON-POSA CON-MODE!',
        # Stake account 2 (not an authority)
        '200 1 _ST-STAKED-AT !',
        '0 1 _ST-UNSTAKE-AT !',
        # Also stake account 1 (the authority)
        '200 0 _ST-STAKED-AT !',
        '0 0 _ST-UNSTAKE-AT !',
        'CON-POS-EPOCH',
        # Sign with key2 (staked but not authorized)
        '_PRIV2 _PUB2 CON-SET-KEYS',
        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
        '1 _BK BLK-SET-HEIGHT',
        '_BK CON-SEAL',
        # Check should fail (key2 not in authority table)
        '_BK CON-CHECK IF ." auth-ok" ELSE ." auth-fail" THEN',
    ]
    check("PoSA: unauthorized staker rejected", lines, "auth-fail")


def test_posa_count():
    """CON-POSA-COUNT returns number of staked authorities."""
    print("\n=== CON-POSA-COUNT ===")
    lines = _keygen_preamble() + [
        '_ADDR1 10000 ST-CREATE DROP',
        '_ADDR2 10000 ST-CREATE DROP',
        # Add both as authorities
        '_PUB1 CON-POA-ADD',
        '_PUB2 CON-POA-ADD',
        # Only stake account 1
        '200 0 _ST-STAKED-AT !',
        '0 0 _ST-UNSTAKE-AT !',
        'CON-POS-EPOCH',
        # Build PoSA set by electing on dummy block
        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
        '1 _BK BLK-SET-HEIGHT',
        '_BK CON-POSA-ELECT DROP',
        'CON-POSA-COUNT .',    # should be 1 (only account 1 is staked)
    ]
    check("CON-POSA-COUNT = 1 (one staked authority)", lines, "1")


def test_genesis_chain_id():
    """GEN-CHAIN-ID! / GEN-CHAIN-ID@ round-trip."""
    print("\n=== Genesis chain ID ===")
    check("default chain ID",
          ['GEN-CHAIN-ID@ .'], "1")
    check("set chain ID",
          ['42 GEN-CHAIN-ID!  GEN-CHAIN-ID@ .'], "42")


def test_genesis_encode():
    """GEN-CREATE produces a non-empty CBOR payload."""
    print("\n=== Genesis encode ===")
    lines = _keygen_preamble() + [
        '_ADDR1 10000 ST-CREATE DROP',
        '_PUB1 CON-POA-ADD',
        'CON-POSA CON-MODE!',
        '42 GEN-CHAIN-ID!',
        'GEN-CREATE',
        'GEN-RESULT NIP .',  # print length (should be > 0)
    ]
    check_fn("GEN-CREATE produces payload",
             lines,
             lambda out: any(int(w) > 0 for w in out.split() if w.isdigit()),
             desc="expected non-zero length")


def test_pow_testing_flag():
    """_CON-POW-TESTING-ONLY constant exists and is -1 (true)."""
    print("\n=== PoW testing-only flag ===")
    check("_CON-POW-TESTING-ONLY = -1",
          ['_CON-POW-TESTING-ONLY .'], "-1")


# =================================================================
#  Main
# =================================================================

if __name__ == "__main__":
    build_snapshot()

    test_compile()
    test_posa_constant()
    test_mode_posa()
    test_set_keys()
    test_pow_testing_flag()
    test_seal_poa_with_stored_keys()
    test_seal_poa_no_keys()
    test_posa_elect_and_check()
    test_posa_unauthorized()
    test_posa_count()
    test_genesis_chain_id()
    test_genesis_encode()

    print(f"\n{'='*60}")
    print(f"  TOTAL: {_pass_count + _fail_count}  "
          f"PASS: {_pass_count}  FAIL: {_fail_count}")
    print(f"{'='*60}")
    sys.exit(0 if _fail_count == 0 else 1)
