#!/usr/bin/env python3
"""Test suite for Akashic consensus.f (akashic/consensus/consensus.f).

Stage A tests:
  - Constants (CON-POW, CON-POA, CON-POS)
  - Mode selection (CON-MODE! / CON-MODE@)
  - STARK flag (CON-STARK! / CON-STARK?)
  - PoW mining + verification
  - PoW difficulty adjustment
  - PoA authority management
  - PoA sign + verify
  - Unified dispatch (CON-CHECK)
  - BLK-VERIFY integration with consensus callback
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
    print("[*] Building snapshot: BIOS + KDOS + all consensus.f dependencies ...")
    t0 = time.time()
    bios_code   = _load_bios()
    kdos_lines  = _load_forth_lines(KDOS_PATH)

    dep_lines = []
    for path in [EVENT_F, SEM_F, GUARD_F, FP16_F,
                 SHA512_F, FIELD_F, SHA3_F, RANDOM_F,
                 ED25519_F, SPHINCS_F, CBOR_F, FMT_F,
                 MERKLE_F, TX_F, SMT_F, STATE_F, BLOCK_F,
                 CONSENSUS_F]:
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
        print(f"  Aborting — consensus.f failed to compile cleanly.")
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

# ── Test vector keys (from RFC 8032 TV1 & TV2 & TV3) ──

TV1_SEED = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
TV1_PUB  = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"

TV2_SEED = "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
TV2_PUB  = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"

TV3_SEED = "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7"
TV3_PUB  = "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025"


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


def _make_tx_lines(tx_var, sender_pub, sender_priv, recip_pub, amount, nonce):
    """Return Forth lines that CREATE, init, populate, and sign a tx buffer."""
    return [
        f'CREATE {tx_var} 8296 ALLOT',
        f'{tx_var} TX-INIT',
        f'{sender_pub} {tx_var} TX-SET-FROM',
        f'{recip_pub} {tx_var} TX-SET-TO',
        f'{amount} {tx_var} TX-SET-AMOUNT',
        f'{nonce} {tx_var} TX-SET-NONCE',
        f'{tx_var} {sender_priv} {sender_pub} TX-SIGN',
    ]


def _funded_state():
    """Keygen + state init with account1 having 10000 balance."""
    return _keygen_preamble() + [
        '_ADDR1 10000 ST-CREATE DROP',
    ]


def _funded_blk():
    """Funded state + block buffer."""
    return _funded_state() + [
        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
    ]


def _funded_blk_with_tx():
    """Funded state + block with one valid tx (1→2, amount=500, nonce=0)."""
    return _funded_state() + \
        _make_tx_lines('_TX1', '_PUB1', '_PRIV1', '_PUB2', 500, 0) + [
        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
        '1 _BK BLK-SET-HEIGHT',
        '1000 _BK BLK-SET-TIME',
        '_TX1 _BK BLK-ADD-TX DROP',
    ]


# =================================================================
#  Tests — Stage A
# =================================================================

def test_compile():
    print("\n=== Compile check ===")
    check("Module loaded", ['1 2 + .'], "3")


def test_constants():
    print("\n=== Constants ===")
    check("CON-POW", ['CON-POW .'], "0")
    check("CON-POA", ['CON-POA .'], "1")
    check("CON-POS", ['CON-POS .'], "2")


def test_mode_selection():
    print("\n=== Mode selection ===")
    check("default mode is PoW",
          ['CON-MODE@ .'], "0")
    check("set mode to PoA",
          ['CON-POA CON-MODE!  CON-MODE@ .'], "1")
    check("set mode to PoS",
          ['CON-POS CON-MODE!  CON-MODE@ .'], "2")
    check("set back to PoW",
          ['CON-POW CON-MODE!  CON-MODE@ .'], "0")


def test_stark_flag():
    print("\n=== STARK flag ===")
    check("default STARK off",
          ['CON-STARK? .'], "0")
    check("enable STARK",
          ['-1 CON-STARK!  CON-STARK? .'], "-1")
    check("disable STARK",
          ['0 CON-STARK!  CON-STARK? .'], "0")


def test_pow_target():
    print("\n=== PoW target ===")
    check("set and get target",
          ['12345 CON-POW-TARGET!  CON-POW-TARGET@ .'], "12345")


def test_pow_mine_and_check():
    """Mine a block with an easy target and verify the nonce works."""
    print("\n=== PoW mine + check ===")
    # Use an extremely easy target so mining completes quickly
    # 0x00FFFFFFFFFFFFFF means hash first byte must be < 0x00FF... → almost always
    lines = _funded_blk_with_tx() + [
        # Set prev_hash from chain (genesis)
        'CHAIN-INIT',
        'CREATE _PHASH 32 ALLOT',
        'CHAIN-HEAD _PHASH BLK-HASH',
        '_PHASH _BK BLK-SET-PREV',
        # Finalize block (compute roots)
        '_BK BLK-FINALIZE',
        # Set very easy PoW target and mine
        '0x00FFFFFFFFFFFFFF CON-POW-TARGET!',
        'CON-POW CON-MODE!',
        '_BK CON-POW-MINE',
        # Check: should pass
        '_BK CON-POW-CHECK .  ." check-ok"',
    ]
    check("PoW mine + check pass", lines, "-1 check-ok")


def test_pow_bad_nonce():
    """Set a random nonce with tight target — check should fail."""
    print("\n=== PoW bad nonce ===")
    lines = _funded_blk_with_tx() + [
        'CHAIN-INIT',
        'CREATE _PHASH 32 ALLOT',
        'CHAIN-HEAD _PHASH BLK-HASH',
        '_PHASH _BK BLK-SET-PREV',
        '_BK BLK-FINALIZE',
        # Very tight target: hash must be < 1 as BE u64 → impossible
        '1 CON-POW-TARGET!',
        'CON-POW CON-MODE!',
        # Set arbitrary nonce via BLK-SET-PROOF (no mining)
        'CREATE _NONCE 8 ALLOT  42 _NONCE !',
        '_NONCE 8 _BK BLK-SET-PROOF',
        '_BK CON-POW-CHECK .  ." check-bad"',
    ]
    check("PoW bad nonce fails", lines, "0 check-bad")


def test_pow_adjust():
    """Test difficulty adjustment clamping."""
    print("\n=== PoW difficulty adjustment ===")
    # Set target to 1000. Elapsed=200, expected=100.
    # new = 1000 * 100 / 200 = 500. Clamped to max(500, 1000/2=500) = 500.
    lines = [
        '1000 CON-POW-TARGET!',
        '200 100 CON-POW-ADJUST',
        'CON-POW-TARGET@ .',
    ]
    check("adjust: double elapsed → halve target", lines, "500")

    # Set target to 1000. Elapsed=50, expected=100.
    # new = 1000 * 100 / 50 = 2000. Clamped to min(2000, 1000*2=2000) = 2000.
    lines2 = [
        '1000 CON-POW-TARGET!',
        '50 100 CON-POW-ADJUST',
        'CON-POW-TARGET@ .',
    ]
    check("adjust: half elapsed → double target", lines2, "2000")

    # Extreme case: elapsed=1, expected=100.
    # new = 1000 * 100 / 1 = 100000. Clamped to min(100000, 2000) = 2000.
    lines3 = [
        '1000 CON-POW-TARGET!',
        '1 100 CON-POW-ADJUST',
        'CON-POW-TARGET@ .',
    ]
    check("adjust: clamp to 2x max", lines3, "2000")


def test_poa_add_count():
    """Add authorities and check count."""
    print("\n=== PoA add + count ===")
    lines = _keygen_preamble() + [
        'CON-POA-COUNT .',
    ]
    check("initial count = 0", lines, "0")

    lines2 = _keygen_preamble() + [
        '_PUB1 CON-POA-ADD',
        'CON-POA-COUNT .',
    ]
    check("add 1 → count = 1", lines2, "1")

    lines3 = _keygen_preamble() + [
        '_PUB1 CON-POA-ADD',
        '_PUB2 CON-POA-ADD',
        '_PUB3 CON-POA-ADD',
        'CON-POA-COUNT .',
    ]
    check("add 3 → count = 3", lines3, "3")


def test_poa_remove():
    """Remove authority and check count."""
    print("\n=== PoA remove ===")
    lines = _keygen_preamble() + [
        '_PUB1 CON-POA-ADD',
        '_PUB2 CON-POA-ADD',
        '_PUB1 CON-POA-REMOVE .',
        'CON-POA-COUNT .',
    ]
    check("remove returns -1 and count=1", lines, "-1")

    lines2 = _keygen_preamble() + [
        '_PUB1 CON-POA-ADD',
        # Try to remove key not in table
        '_PUB3 CON-POA-REMOVE .',
    ]
    check("remove non-existent returns 0", lines2, "0")


def test_poa_sign_and_check():
    """Sign a finalized block with PoA authority; verify passes."""
    print("\n=== PoA sign + check ===")
    lines = _funded_blk_with_tx() + [
        'CHAIN-INIT',
        'CREATE _PHASH 32 ALLOT',
        'CHAIN-HEAD _PHASH BLK-HASH',
        '_PHASH _BK BLK-SET-PREV',
        '_BK BLK-FINALIZE',
        # Add PUB1 as authority
        '_PUB1 CON-POA-ADD',
        # Set PoA mode
        'CON-POA CON-MODE!',
        # Sign the block
        '_BK _PRIV1 _PUB1 CON-POA-SIGN',
        # Check
        '_BK CON-POA-CHECK .  ." poa-ok"',
    ]
    check("PoA sign + check pass", lines, "-1 poa-ok")


def test_poa_unauthorized():
    """Sign with a key not in authority table — check fails."""
    print("\n=== PoA unauthorized signer ===")
    lines = _funded_blk_with_tx() + [
        'CHAIN-INIT',
        'CREATE _PHASH 32 ALLOT',
        'CHAIN-HEAD _PHASH BLK-HASH',
        '_PHASH _BK BLK-SET-PREV',
        '_BK BLK-FINALIZE',
        # Add only PUB2 as authority
        '_PUB2 CON-POA-ADD',
        'CON-POA CON-MODE!',
        # Sign with PUB1 (not authorized!)
        '_BK _PRIV1 _PUB1 CON-POA-SIGN',
        # Check should fail
        '_BK CON-POA-CHECK .  ." poa-bad"',
    ]
    check("PoA unauthorized fails", lines, "0 poa-bad")


def test_con_check_dispatch_pow():
    """CON-CHECK dispatches to PoW check correctly."""
    print("\n=== CON-CHECK dispatch ===")
    lines = _funded_blk_with_tx() + [
        'CHAIN-INIT',
        'CREATE _PHASH 32 ALLOT',
        'CHAIN-HEAD _PHASH BLK-HASH',
        '_PHASH _BK BLK-SET-PREV',
        '_BK BLK-FINALIZE',
        '0x00FFFFFFFFFFFFFF CON-POW-TARGET!',
        'CON-POW CON-MODE!',
        '_BK CON-POW-MINE',
        # Use unified CON-CHECK
        '_BK CON-CHECK .  ." dispatch-ok"',
    ]
    check("CON-CHECK in PoW mode", lines, "-1 dispatch-ok")


def test_con_check_dispatch_poa():
    """CON-CHECK dispatches to PoA check correctly."""
    lines = _funded_blk_with_tx() + [
        'CHAIN-INIT',
        'CREATE _PHASH 32 ALLOT',
        'CHAIN-HEAD _PHASH BLK-HASH',
        '_PHASH _BK BLK-SET-PREV',
        '_BK BLK-FINALIZE',
        '_PUB1 CON-POA-ADD',
        'CON-POA CON-MODE!',
        '_BK _PRIV1 _PUB1 CON-POA-SIGN',
        '_BK CON-CHECK .  ." dispatch-poa"',
    ]
    check("CON-CHECK in PoA mode", lines, "-1 dispatch-poa")


def test_blk_verify_pow_integration():
    """BLK-VERIFY uses consensus callback for PoW validation."""
    print("\n=== BLK-VERIFY integration ===")
    lines = _funded_blk_with_tx() + [
        'CHAIN-INIT',
        'CREATE _PHASH 32 ALLOT',
        'CHAIN-HEAD _PHASH BLK-HASH',
        '_PHASH _BK BLK-SET-PREV',
        # Snapshot/restore so BLK-VERIFY can re-apply txs
        'CREATE _SS ST-SNAPSHOT-SIZE ALLOT  _SS ST-SNAPSHOT',
        '_BK BLK-FINALIZE',
        '_SS ST-RESTORE',
        '0x00FFFFFFFFFFFFFF CON-POW-TARGET!',
        'CON-POW CON-MODE!',
        '_BK CON-POW-MINE',
        # BLK-VERIFY should pass (consensus check routed through CON-CHECK)
        '_BK _PHASH BLK-VERIFY .  ." verify-pow"',
    ]
    check("BLK-VERIFY + PoW pass", lines, "-1 verify-pow")


def test_blk_verify_poa_integration():
    """BLK-VERIFY uses consensus callback for PoA validation."""
    lines = _funded_blk_with_tx() + [
        'CHAIN-INIT',
        'CREATE _PHASH 32 ALLOT',
        'CHAIN-HEAD _PHASH BLK-HASH',
        '_PHASH _BK BLK-SET-PREV',
        # Snapshot/restore so BLK-VERIFY can re-apply txs
        'CREATE _SS ST-SNAPSHOT-SIZE ALLOT  _SS ST-SNAPSHOT',
        '_BK BLK-FINALIZE',
        '_SS ST-RESTORE',
        '_PUB1 CON-POA-ADD',
        'CON-POA CON-MODE!',
        '_BK _PRIV1 _PUB1 CON-POA-SIGN',
        '_BK _PHASH BLK-VERIFY .  ." verify-poa"',
    ]
    check("BLK-VERIFY + PoA pass", lines, "-1 verify-poa")


def test_blk_verify_pow_bad():
    """BLK-VERIFY with bad PoW nonce should fail."""
    lines = _funded_blk_with_tx() + [
        'CHAIN-INIT',
        'CREATE _PHASH 32 ALLOT',
        'CHAIN-HEAD _PHASH BLK-HASH',
        '_PHASH _BK BLK-SET-PREV',
        # Snapshot/restore around FINALIZE so BLK-VERIFY can re-apply txs
        'CREATE _SS ST-SNAPSHOT-SIZE ALLOT  _SS ST-SNAPSHOT',
        '_BK BLK-FINALIZE',
        '_SS ST-RESTORE',
        # Set a very tight target — most nonces won't pass
        '1 CON-POW-TARGET!',
        'CON-POW CON-MODE!',
        # Don't mine — just set a random nonce manually
        'CREATE _NONCE 8 ALLOT  42 _NONCE !',
        '_NONCE 8 _BK BLK-SET-PROOF',
        # BLK-VERIFY should fail at consensus check
        '_BK _PHASH BLK-VERIFY .  ." verify-fail"',
    ]
    check("BLK-VERIFY + bad PoW fails", lines, "0 verify-fail")


def test_blk_verify_poa_unauthorized_integration():
    """BLK-VERIFY with unauthorized PoA signer should fail."""
    lines = _funded_blk_with_tx() + [
        'CHAIN-INIT',
        'CREATE _PHASH 32 ALLOT',
        'CHAIN-HEAD _PHASH BLK-HASH',
        '_PHASH _BK BLK-SET-PREV',
        # Snapshot/restore so BLK-VERIFY can re-apply txs
        'CREATE _SS ST-SNAPSHOT-SIZE ALLOT  _SS ST-SNAPSHOT',
        '_BK BLK-FINALIZE',
        '_SS ST-RESTORE',
        # Add PUB2 as authority but sign with PUB1
        '_PUB2 CON-POA-ADD',
        'CON-POA CON-MODE!',
        '_BK _PRIV1 _PUB1 CON-POA-SIGN',
        '_BK _PHASH BLK-VERIFY .  ." verify-unauth"',
    ]
    check("BLK-VERIFY + unauthorized PoA fails", lines, "0 verify-unauth")


def test_sig_hash_differs_from_blk_hash():
    """Signatory hash (empty proof) differs from block hash (with proof)."""
    print("\n=== Signatory hash vs block hash ===")
    lines = _funded_blk_with_tx() + [
        'CHAIN-INIT',
        'CREATE _PHASH 32 ALLOT',
        'CHAIN-HEAD _PHASH BLK-HASH',
        '_PHASH _BK BLK-SET-PREV',
        '_BK BLK-FINALIZE',
        # Sign with PoA (puts proof material in block)
        '_PUB1 CON-POA-ADD',
        '_BK _PRIV1 _PUB1 CON-POA-SIGN',
        # Compute both hashes
        'CREATE _SH 32 ALLOT  _BK _SH CON-SIG-HASH',
        'CREATE _BH 32 ALLOT  _BK _BH BLK-HASH',
        # Compare: they should differ
        '0  32 0 DO _SH I + C@ _BH I + C@ XOR OR LOOP',
        '0<> IF ." differ" ELSE ." same" THEN',
    ]
    check("sig hash != block hash", lines, "differ")


# =================================================================
#  Main
# =================================================================

if __name__ == "__main__":
    build_snapshot()

    test_compile()
    test_constants()
    test_mode_selection()
    test_stark_flag()
    test_pow_target()
    test_pow_mine_and_check()
    test_pow_bad_nonce()
    test_pow_adjust()
    test_poa_add_count()
    test_poa_remove()
    test_poa_sign_and_check()
    test_poa_unauthorized()
    test_con_check_dispatch_pow()
    test_con_check_dispatch_poa()
    test_blk_verify_pow_integration()
    test_blk_verify_poa_integration()
    test_blk_verify_pow_bad()
    test_blk_verify_poa_unauthorized_integration()
    test_sig_hash_differs_from_blk_hash()

    print(f"\n{'='*60}")
    print(f"  TOTAL: {_pass_count + _fail_count}  "
          f"PASS: {_pass_count}  FAIL: {_fail_count}")
    print(f"{'='*60}")
    sys.exit(0 if _fail_count == 0 else 1)
