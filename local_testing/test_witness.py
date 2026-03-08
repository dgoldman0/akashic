#!/usr/bin/env python3
"""Test suite for Akashic witness.f (akashic/store/witness.f).

Phase 3b Step 3 — State Transition Witness.

Tests:
  - Compile check (witness.f loads cleanly)
  - WIT-INIT (returns -1, count = 0)
  - WIT-BEGIN captures pre-root matching ST-ROOT
  - WIT-END captures post-root matching ST-ROOT
  - Single tx → 2 entries (sender + recipient)
  - Single tx pre-values match state before tx
  - Single tx post-values match state after tx
  - CREATED flag for new recipient
  - Existing recipient has no CREATED flag
  - Self-transfer → 1 entry, nonce bumped, balance same
  - Dedup: 2 txs from same sender → 1 sender entry
  - Dedup post-values reflect cumulative change
  - Failed tx → 0 entries
  - Mixed success/failure → only good tx's entries
  - WIT-VERIFY honest → -1
  - WIT-VERIFY tampered post-balance → 0
  - WIT-PROVE returns len > 0
  - WIT-PROVE + SMT-VERIFY round-trip → TRUE
  - Empty block → 0 entries, roots equal
  - Multi-tx block → correct entry count
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
WITNESS_F  = os.path.join(ROOT_DIR, "akashic", "store", "witness.f")

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
    print("[*] Building snapshot: BIOS + KDOS + witness.f deps ...")
    t0 = time.time()
    bios_code   = _load_bios()
    kdos_lines  = _load_forth_lines(KDOS_PATH)

    # Load all deps in correct topological order
    dep_lines = []
    for path in [EVENT_F, SEM_F, GUARD_F, FP16_F,
                 SHA512_F, FIELD_F, SHA3_F, RANDOM_F,
                 ED25519_F, SPHINCS_F, CBOR_F, FMT_F,
                 MERKLE_F, SMT_F, TX_F, STATE_F, WITNESS_F]:
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
        print(f"  Aborting — witness.f failed to compile cleanly.")
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

def store_hex(var_name, hex_str):
    bs = bytes.fromhex(hex_str)
    lines = []
    for i, b in enumerate(bs):
        lines.append(f'{b} {var_name} {i} + C!')
    return lines

def create_hex_buf(var_name, hex_str):
    bs = bytes.fromhex(hex_str)
    n = len(bs)
    lines = [f'CREATE {var_name} {n} ALLOT']
    for i, b in enumerate(bs):
        lines.append(f'{b} {var_name} {i} + C!')
    return lines

# ── Test vector keys (RFC 8032 TV1, TV2, TV3) ──

TV1_SEED = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
TV1_PUB  = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"

TV2_SEED = "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
TV2_PUB  = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"

TV3_SEED = "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7"
TV3_PUB  = "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025"


def _keygen_preamble():
    """Create three keypairs, address buffers, and initialize state + witness."""
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
        # Init state + witness
        'ST-INIT DROP',
        'WIT-INIT DROP',
    ]
    return lines


def _make_tx(sender_pub, sender_priv, recip_pub, amount, nonce, buf_name='_TXBUF'):
    """Return Forth lines that build, sign, and leave a tx buffer."""
    return [
        f'CREATE {buf_name} {8296} ALLOT',
        f'{buf_name} TX-INIT',
        f'{sender_pub} {buf_name} TX-SET-FROM',
        f'{recip_pub} {buf_name} TX-SET-TO',
        f'{amount} {buf_name} TX-SET-AMOUNT',
        f'{nonce} {buf_name} TX-SET-NONCE',
        f'{buf_name} {sender_priv} {sender_pub} TX-SIGN',
    ]


# ── Tests ──

def test_compile():
    """witness.f loads cleanly."""
    print("\n=== Compile check ===")
    check("Module loaded", ['1 2 + .'], "3")


def test_constants():
    """Basic constants are correct."""
    print("\n=== Constants ===")
    check("WIT-ENTRY-SIZE",    ['WIT-ENTRY-SIZE .'],    "72")
    check("WIT-MAX-ENTRIES",   ['WIT-MAX-ENTRIES .'],   "512")


def test_init():
    """WIT-INIT returns -1, count = 0."""
    print("\n=== WIT-INIT ===")
    check("init returns -1",
          ['ST-INIT DROP WIT-INIT IF ." YES" ELSE ." NO" THEN'], "YES")
    check("count is 0 after init",
          ['ST-INIT DROP WIT-INIT DROP WIT-COUNT .'], "0")


def test_begin_captures_root():
    """WIT-BEGIN stores pre-root matching ST-ROOT."""
    print("\n=== WIT-BEGIN captures pre-root ===")
    lines = _keygen_preamble() + [
        # Create an account so root is non-trivial
        '_ADDR1 1000 ST-CREATE DROP',
        # Capture current root in RAM
        'CREATE _R1 32 ALLOT',
        'ST-ROOT _R1 32 CMOVE',
        # Begin witness
        'WIT-BEGIN',
        # Compare WIT-PRE-ROOT with saved root
        'WIT-PRE-ROOT _R1 32 0 DO OVER I + C@ OVER I + C@ XOR OR LOOP NIP NIP',
        'IF ." DIFF" ELSE ." SAME" THEN',
    ]
    check("pre-root matches ST-ROOT", lines, "SAME")


def test_end_captures_post_root():
    """WIT-END stores post-root matching ST-ROOT."""
    print("\n=== WIT-END captures post-root ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        '_TXBUF WIT-APPLY-TX DROP',
        'WIT-END',
        # Capture current root
        'CREATE _R2 32 ALLOT',
        'ST-ROOT _R2 32 CMOVE',
        # Compare
        'WIT-POST-ROOT _R2 32 0 DO OVER I + C@ OVER I + C@ XOR OR LOOP NIP NIP',
        'IF ." DIFF" ELSE ." SAME" THEN',
    ]
    check("post-root matches ST-ROOT", lines, "SAME")


def test_single_tx_entries():
    """One tx → 2 entries (sender + recipient)."""
    print("\n=== Single tx → 2 entries ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        '_TXBUF WIT-APPLY-TX DROP',
        'WIT-COUNT .',
    ]
    check("2 entries for normal tx", lines, "2")


def test_single_tx_pre_values():
    """Pre-balance/nonce match state before tx."""
    print("\n=== Single tx pre-values ===")
    # Sender had balance 1000, nonce 0 before tx
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        '_TXBUF WIT-APPLY-TX DROP',
        # Entry 0 is sender; read pre_balance at offset 32
        '0 WIT-ENTRY 32 + @ .',
    ]
    check("sender pre-balance = 1000", lines, "1000")

    lines2 = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        '_TXBUF WIT-APPLY-TX DROP',
        # Sender pre_nonce at offset 40
        '0 WIT-ENTRY 40 + @ .',
    ]
    check("sender pre-nonce = 0", lines2, "0")


def test_single_tx_post_values():
    """Post-balance/nonce match state after tx."""
    print("\n=== Single tx post-values ===")
    # After tx: sender balance = 1000 - 100 = 900, nonce = 1
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        '_TXBUF WIT-APPLY-TX DROP',
        # Entry 0 sender post_balance at offset 48
        '0 WIT-ENTRY 48 + @ .',
    ]
    check("sender post-balance = 900", lines, "900")

    lines2 = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        '_TXBUF WIT-APPLY-TX DROP',
        '0 WIT-ENTRY 56 + @ .',
    ]
    check("sender post-nonce = 1", lines2, "1")

    # Recipient post-balance = 100
    lines3 = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        '_TXBUF WIT-APPLY-TX DROP',
        # Entry 1 is recipient, post_balance at offset 48
        '1 WIT-ENTRY 48 + @ .',
    ]
    check("recipient post-balance = 100", lines3, "100")


def test_created_flag():
    """New recipient has CREATED flag set."""
    print("\n=== CREATED flag ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        '_TXBUF WIT-APPLY-TX DROP',
        # Entry 1 = recipient, should have CREATED flag
        '1 WIT-CREATED? IF ." YES" ELSE ." NO" THEN',
    ]
    check("new recipient has CREATED flag", lines, "YES")


def test_existing_recipient_no_flag():
    """Pre-existing recipient has CREATED = 0."""
    print("\n=== Existing recipient no CREATED flag ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        '_ADDR2 500 ST-CREATE DROP',   # pre-create recipient
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        '_TXBUF WIT-APPLY-TX DROP',
        '1 WIT-CREATED? IF ." YES" ELSE ." NO" THEN',
    ]
    check("existing recipient: CREATED = 0", lines, "NO")


def test_self_transfer():
    """Self-transfer → 1 entry, nonce bumped, balance same."""
    print("\n=== Self-transfer ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB1', 100, 0) + [
        '_TXBUF WIT-APPLY-TX DROP',
        'WIT-COUNT .',
    ]
    check("self-transfer → 1 entry", lines, "1")

    lines2 = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB1', 100, 0) + [
        '_TXBUF WIT-APPLY-TX DROP',
        # Post-balance should still be 1000 (self-transfer)
        '0 WIT-ENTRY 48 + @ .',
    ]
    check("self-transfer post-balance = 1000", lines2, "1000")

    lines3 = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB1', 100, 0) + [
        '_TXBUF WIT-APPLY-TX DROP',
        # Post-nonce should be 1
        '0 WIT-ENTRY 56 + @ .',
    ]
    check("self-transfer post-nonce = 1", lines3, "1")


def test_dedup():
    """2 txs from same sender → 1 sender entry."""
    print("\n=== Dedup ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0, '_TX1') + [
        '_TX1 WIT-APPLY-TX DROP',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB3', 200, 1, '_TX2') + [
        '_TX2 WIT-APPLY-TX DROP',
        # 3 entries: sender, recip2, recip3 (sender deduped)
        'WIT-COUNT .',
    ]
    check("dedup: 3 entries (sender + 2 recipients)", lines, "3")


def test_dedup_post_values():
    """After 2 txs, post-values reflect cumulative change."""
    print("\n=== Dedup post-values ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0, '_TX1') + [
        '_TX1 WIT-APPLY-TX DROP',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB3', 200, 1, '_TX2') + [
        '_TX2 WIT-APPLY-TX DROP',
        # Sender pre-balance should still be 1000
        '0 WIT-ENTRY 32 + @ .',
    ]
    check("sender pre-balance still 1000", lines, "1000")

    lines2 = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0, '_TX1') + [
        '_TX1 WIT-APPLY-TX DROP',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB3', 200, 1, '_TX2') + [
        '_TX2 WIT-APPLY-TX DROP',
        # Sender post-balance = 1000 - 100 - 200 = 700
        '0 WIT-ENTRY 48 + @ .',
    ]
    check("sender post-balance = 700", lines2, "700")

    lines3 = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0, '_TX1') + [
        '_TX1 WIT-APPLY-TX DROP',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB3', 200, 1, '_TX2') + [
        '_TX2 WIT-APPLY-TX DROP',
        # Sender post-nonce = 2
        '0 WIT-ENTRY 56 + @ .',
    ]
    check("sender post-nonce = 2", lines3, "2")


def test_failed_tx():
    """Failed tx (bad nonce) → 0 entries."""
    print("\n=== Failed tx → 0 entries ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 99) + [  # bad nonce
        '_TXBUF WIT-APPLY-TX DROP',
        'WIT-COUNT .',
    ]
    check("failed tx → 0 entries", lines, "0")


def test_mixed_success_failure():
    """1 good tx + 1 bad tx → only good tx's entries."""
    print("\n=== Mixed success/failure ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0, '_TX1') + [
        '_TX1 WIT-APPLY-TX DROP',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB3', 100, 99, '_TX2') + [  # bad nonce
        '_TX2 WIT-APPLY-TX DROP',
        'WIT-COUNT .',
    ]
    check("good + bad = 2 entries", lines, "2")


def test_verify_honest():
    """WIT-VERIFY returns -1 for honest witness."""
    print("\n=== WIT-VERIFY honest ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        '_TXBUF WIT-APPLY-TX DROP',
        'WIT-END',
        'WIT-VERIFY IF ." VALID" ELSE ." INVALID" THEN',
    ]
    check("honest witness verifies", lines, "VALID")


def test_verify_tampered_post():
    """Tamper post-balance → WIT-VERIFY returns 0."""
    print("\n=== WIT-VERIFY tampered post-balance ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        '_TXBUF WIT-APPLY-TX DROP',
        'WIT-END',
        # Tamper: change post-balance of sender entry
        '999999 0 WIT-ENTRY 48 + !',
        'WIT-VERIFY IF ." VALID" ELSE ." INVALID" THEN',
    ]
    check("tampered witness fails verify", lines, "INVALID")


def test_prove_returns_len():
    """WIT-PROVE returns len > 0 for existing account."""
    print("\n=== WIT-PROVE returns len > 0 ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        '_TXBUF WIT-APPLY-TX DROP',
        'WIT-END',
        'CREATE _PRF 4096 ALLOT',
        'WIT-PROVE-BEGIN',
        '0 _PRF WIT-PROVE',
        '_PL !',
        'WIT-PROVE-END',
        '_PL @ 0> IF ." HASLEN" ELSE ." NOLEN" THEN',
    ]
    check("proof has positive length", lines, "HASLEN")


def test_prove_verify_round_trip():
    """SMT-VERIFY(key, leaf, proof, len, pre-root) = TRUE."""
    print("\n=== WIT-PROVE + SMT-VERIFY round-trip ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        '_TXBUF WIT-APPLY-TX DROP',
        'WIT-END',
        # Generate proof for entry 0 (sender)
        'CREATE _PRF 4096 ALLOT',
        'WIT-PROVE-BEGIN',
        '0 _PRF WIT-PROVE',
        '_PL !',
        'WIT-PROVE-END',
        # Verify the proof against the pre-root
        # ST-VERIFY-PROOF ( addr proof len root -- flag )
        'CREATE _PRE_R 32 ALLOT',
        'WIT-PRE-ROOT _PRE_R 32 CMOVE',
        # Get address from entry 0
        'CREATE _E0ADDR 32 ALLOT',
        '0 WIT-ENTRY _E0ADDR 32 CMOVE',
        '_E0ADDR _PRF _PL @ _PRE_R ST-VERIFY-PROOF',
        'IF ." VERIFIED" ELSE ." BADPROOF" THEN',
    ]
    check("proof verifies against pre-root", lines, "VERIFIED")


def test_empty_block():
    """WIT-BEGIN + WIT-END, 0 entries, roots equal."""
    print("\n=== Empty block ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'WIT-BEGIN',
        'WIT-END',
        'WIT-COUNT .',
    ]
    check("empty block → 0 entries", lines, "0")

    lines2 = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        'WIT-BEGIN',
        'WIT-END',
        # Pre-root should equal post-root (no changes)
        'WIT-PRE-ROOT WIT-POST-ROOT 32 0 DO OVER I + C@ OVER I + C@ XOR OR LOOP NIP NIP',
        'IF ." DIFF" ELSE ." SAME" THEN',
    ]
    check("empty block: pre-root = post-root", lines2, "SAME")


def test_multi_tx_block():
    """4 txs touching multiple accounts → correct entry count."""
    print("\n=== Multi-tx block ===")
    lines = _keygen_preamble() + [
        '_ADDR1 5000 ST-CREATE DROP',
        '_ADDR2 3000 ST-CREATE DROP',
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0, '_TX1') + [
        '_TX1 WIT-APPLY-TX DROP',
    ] + _make_tx('_PUB2', '_PRIV2', '_PUB3', 50, 0, '_TX2') + [
        '_TX2 WIT-APPLY-TX DROP',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB3', 200, 1, '_TX3') + [
        '_TX3 WIT-APPLY-TX DROP',
    ] + _make_tx('_PUB2', '_PRIV2', '_PUB1', 75, 1, '_TX4') + [
        '_TX4 WIT-APPLY-TX DROP',
        'WIT-END',
        # 3 accounts touched: ADDR1, ADDR2, ADDR3 (all deduped)
        'WIT-COUNT .',
    ]
    check("multi-tx block: 3 entries", lines, "3")


def test_multi_tx_verify():
    """Multi-tx block passes WIT-VERIFY."""
    print("\n=== Multi-tx block verifies ===")
    lines = _keygen_preamble() + [
        '_ADDR1 5000 ST-CREATE DROP',
        '_ADDR2 3000 ST-CREATE DROP',
        'WIT-BEGIN',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0, '_TX1') + [
        '_TX1 WIT-APPLY-TX DROP',
    ] + _make_tx('_PUB2', '_PRIV2', '_PUB3', 50, 0, '_TX2') + [
        '_TX2 WIT-APPLY-TX DROP',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB3', 200, 1, '_TX3') + [
        '_TX3 WIT-APPLY-TX DROP',
        'WIT-END',
        'WIT-VERIFY IF ." VALID" ELSE ." INVALID" THEN',
    ]
    check("multi-tx block verifies", lines, "VALID")


# ── Main ──

def main():
    global _pass_count, _fail_count
    build_snapshot()

    test_compile()
    test_constants()
    test_init()
    test_begin_captures_root()
    test_end_captures_post_root()
    test_single_tx_entries()
    test_single_tx_pre_values()
    test_single_tx_post_values()
    test_created_flag()
    test_existing_recipient_no_flag()
    test_self_transfer()
    test_dedup()
    test_dedup_post_values()
    test_failed_tx()
    test_mixed_success_failure()
    test_verify_honest()
    test_verify_tampered_post()
    test_prove_returns_len()
    test_prove_verify_round_trip()
    test_empty_block()
    test_multi_tx_block()
    test_multi_tx_verify()

    total = _pass_count + _fail_count
    print(f"\n{'='*50}")
    print(f"  witness.f:  {_pass_count}/{total} passed")
    if _fail_count:
        print(f"  *** {_fail_count} FAILURES ***")
        sys.exit(1)
    else:
        print("  All tests passed!")

if __name__ == '__main__':
    main()
