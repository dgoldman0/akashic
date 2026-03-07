#!/usr/bin/env python3
"""Test suite for Akashic block.f (akashic/store/block.f).

Tests:
  - Constants (BLK-MAX-TXS, BLK-HDR-SIZE, BLK-PROOF-MAX, CHAIN-HISTORY,
               BLK-STRUCT-SIZE, ST-SNAPSHOT-SIZE)
  - BLK-INIT (zeroes struct, sets version)
  - Setters / getters (height, prev_hash, timestamp, proof, version)
  - BLK-ADD-TX (add txs, count increments, retrieval via BLK-TX@)
  - BLK-FINALIZE (produces tx root + state root, mutates state)
  - BLK-HASH (non-zero, deterministic, changes when header changes)
  - BLK-VERIFY (full non-destructive validation)
  - BLK-ENCODE / BLK-DECODE (round-trip header fields)
  - ST-SNAPSHOT / ST-RESTORE (save/restore state)
  - CHAIN-INIT (genesis block, height=0)
  - CHAIN-APPEND (validate and apply)
  - CHAIN-HEIGHT / CHAIN-HEAD / CHAIN-BLOCK@
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
STATE_F    = os.path.join(ROOT_DIR, "akashic", "store", "state.f")
BLOCK_F    = os.path.join(ROOT_DIR, "akashic", "store", "block.f")

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
    print("[*] Building snapshot: BIOS + KDOS + all block.f dependencies ...")
    t0 = time.time()
    bios_code   = _load_bios()
    kdos_lines  = _load_forth_lines(KDOS_PATH)

    dep_lines = []
    for path in [EVENT_F, SEM_F, GUARD_F, FP16_F,
                 SHA512_F, FIELD_F, SHA3_F, RANDOM_F,
                 ED25519_F, SPHINCS_F, CBOR_F, FMT_F,
                 MERKLE_F, TX_F, STATE_F, BLOCK_F]:
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
        print(f"  Aborting — block.f failed to compile cleanly.")
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

# ── Test vector keys (from RFC 8032 TV1 & TV2) ──

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


def _blk_preamble():
    """Keygen + state init + create block buffer."""
    return _keygen_preamble() + [
        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
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


# =================================================================
#  Tests
# =================================================================

def test_compile():
    print("\n=== Compile check ===")
    check("Module loaded", ['1 2 + .'], "3")


def test_constants():
    print("\n=== Constants ===")
    check("BLK-MAX-TXS",     ['BLK-MAX-TXS .'],     "256")
    check("BLK-HDR-SIZE",    ['BLK-HDR-SIZE .'],     "248")
    check("BLK-PROOF-MAX",   ['BLK-PROOF-MAX .'],    "128")
    check("CHAIN-HISTORY",   ['CHAIN-HISTORY .'],     "64")
    check("BLK-STRUCT-SIZE", ['BLK-STRUCT-SIZE .'],   "2304")
    check("ST-SNAPSHOT-SIZE",['ST-SNAPSHOT-SIZE .'],   "18440")


def test_init():
    print("\n=== BLK-INIT ===")
    lines = [
        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
        '_BK BLK-VERSION@ .',
    ]
    check("version is 1", lines, "1")

    lines2 = [
        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
        '_BK BLK-HEIGHT@ .',
    ]
    check("height is 0", lines2, "0")

    lines3 = [
        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
        '_BK BLK-TX-COUNT@ .',
    ]
    check("tx count is 0", lines3, "0")

    lines4 = [
        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
        '_BK BLK-TIME@ .',
    ]
    check("timestamp is 0", lines4, "0")


def test_setters():
    print("\n=== Setters / Getters ===")
    # Height
    check("set/get height", [
        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
        '42 _BK BLK-SET-HEIGHT',
        '_BK BLK-HEIGHT@ .',
    ], "42")

    # Timestamp
    check("set/get timestamp", [
        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
        '1700000000 _BK BLK-SET-TIME',
        '_BK BLK-TIME@ .',
    ], "1700000000")

    # Prev hash — set 32 bytes, check first byte
    check("set/get prev_hash", [
        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
        'CREATE _PH 32 ALLOT',
        '_PH 32 0 FILL',
        '171 _PH C!',
        '_PH _BK BLK-SET-PREV',
        '_BK BLK-PREV-HASH@ C@ .',
    ], "171")

    # Proof
    check("set/get proof", [
        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
        'CREATE _PR 10 ALLOT',
        '_PR 10 0 FILL  99 _PR C!',
        '_PR 10 _BK BLK-SET-PROOF',
        '_BK BLK-PROOF@ . .',
    ], "10")

    # Proof too long rejected
    check("proof >128 rejected", [
        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
        'CREATE _PR 200 ALLOT',
        '_PR 200 _BK BLK-SET-PROOF',
        '_BK BLK-PROOF@ NIP .',
    ], "0")


def test_add_tx():
    print("\n=== BLK-ADD-TX ===")
    lines = _funded_blk() + _make_tx_lines(
        '_TX1', '_PUB1', '_PRIV1', '_PUB2', 100, 0
    ) + [
        '_TX1 _BK BLK-ADD-TX IF ." ADDOK" ELSE ." ADDFAIL" THEN',
        '_BK BLK-TX-COUNT@ .',
    ]
    check("add first tx", lines, "ADDOK")
    check("count is 1 after add", lines, "1")

    # Retrieve tx pointer
    lines2 = _funded_blk() + _make_tx_lines(
        '_TX1', '_PUB1', '_PRIV1', '_PUB2', 100, 0
    ) + [
        '_TX1 _BK BLK-ADD-TX DROP',
        '0 _BK BLK-TX@ _TX1 = IF ." PTROK" ELSE ." PTRFAIL" THEN',
    ]
    check("tx pointer matches", lines2, "PTROK")

    # Add two txs
    lines3 = _funded_blk() + _make_tx_lines(
        '_TX1', '_PUB1', '_PRIV1', '_PUB2', 100, 0
    ) + _make_tx_lines(
        '_TX2', '_PUB1', '_PRIV1', '_PUB2', 200, 1
    ) + [
        '_TX1 _BK BLK-ADD-TX DROP',
        '_TX2 _BK BLK-ADD-TX DROP',
        '_BK BLK-TX-COUNT@ .',
    ]
    check("count is 2 after two adds", lines3, "2")


def test_finalize():
    print("\n=== BLK-FINALIZE ===")
    # Finalize sets tx_root (non-zero with txs)
    lines = _funded_blk() + _make_tx_lines(
        '_TX1', '_PUB1', '_PRIV1', '_PUB2', 100, 0
    ) + [
        '_TX1 _BK BLK-ADD-TX DROP',
        # Set required header fields
        '1 _BK BLK-SET-HEIGHT',
        '1700000000 _BK BLK-SET-TIME',
        'CREATE _PH 32 ALLOT  _PH 32 0 FILL  _PH _BK BLK-SET-PREV',
        # Finalize
        '_BK BLK-FINALIZE',
        # Check tx_root not all zero
        '_BK BLK-TX-ROOT@ 32 0 DO DUP I + C@ OR LOOP',
        'IF ." TXRNZ" ELSE ." TXRZ" THEN',
    ]
    check("tx root non-zero after finalize", lines, "TXRNZ")

    # State root non-zero
    lines2 = _funded_blk() + _make_tx_lines(
        '_TX1', '_PUB1', '_PRIV1', '_PUB2', 100, 0
    ) + [
        '_TX1 _BK BLK-ADD-TX DROP',
        '1 _BK BLK-SET-HEIGHT',
        '1700000000 _BK BLK-SET-TIME',
        'CREATE _PH 32 ALLOT  _PH 32 0 FILL  _PH _BK BLK-SET-PREV',
        '_BK BLK-FINALIZE',
        '_BK BLK-STATE-ROOT@ 32 0 DO DUP I + C@ OR LOOP',
        'IF ." SRNZ" ELSE ." SRZ" THEN',
    ]
    check("state root non-zero after finalize", lines2, "SRNZ")

    # Finalize applied txs — sender balance should have decreased
    lines3 = _funded_blk() + _make_tx_lines(
        '_TX1', '_PUB1', '_PRIV1', '_PUB2', 100, 0
    ) + [
        '_TX1 _BK BLK-ADD-TX DROP',
        '1 _BK BLK-SET-HEIGHT',
        '1700000000 _BK BLK-SET-TIME',
        'CREATE _PH 32 ALLOT  _PH 32 0 FILL  _PH _BK BLK-SET-PREV',
        '_BK BLK-FINALIZE',
        '_ADDR1 ST-BALANCE@ .',
    ]
    check("sender debited after finalize", lines3, "9900")


def test_hash():
    print("\n=== BLK-HASH ===")
    # Hash is non-zero
    lines = [
        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
        'CREATE _H 32 ALLOT',
        '_BK _H BLK-HASH',
        '_H 32 0 DO DUP I + C@ OR LOOP',
        'IF ." HNZ" ELSE ." HZ" THEN',
    ]
    check("hash is non-zero", lines, "HNZ")

    # Deterministic
    lines2 = [
        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT  42 _BK BLK-SET-HEIGHT',
        'CREATE _H1 32 ALLOT  CREATE _H2 32 ALLOT',
        '_BK _H1 BLK-HASH  _BK _H2 BLK-HASH',
        '_H1 _H2 32 0 DO OVER I + C@ OVER I + C@ XOR OR LOOP NIP NIP',
        'IF ." DIFF" ELSE ." SAME" THEN',
    ]
    check("hash is deterministic", lines2, "SAME")

    # Different height -> different hash
    lines3 = [
        f'CREATE _BK1 {2304} ALLOT  CREATE _BK2 {2304} ALLOT',
        '_BK1 BLK-INIT  1 _BK1 BLK-SET-HEIGHT',
        '_BK2 BLK-INIT  2 _BK2 BLK-SET-HEIGHT',
        'CREATE _H1 32 ALLOT  CREATE _H2 32 ALLOT',
        '_BK1 _H1 BLK-HASH  _BK2 _H2 BLK-HASH',
        '_H1 _H2 32 0 DO OVER I + C@ OVER I + C@ XOR OR LOOP NIP NIP',
        'IF ." DIFF" ELSE ." SAME" THEN',
    ]
    check("different height -> different hash", lines3, "DIFF")


def test_snapshot_restore():
    print("\n=== ST-SNAPSHOT / ST-RESTORE ===")
    # Basic: snapshot, mutate, restore, check original value
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        f'CREATE _SNAP {18440} ALLOT',
        '_SNAP ST-SNAPSHOT',
        # Mutate: create another account
        '_ADDR2 500 ST-CREATE DROP',
        'ST-COUNT .',   # should be 2
    ]
    check("count=2 before restore", lines, "2")

    lines2 = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        f'CREATE _SNAP {18440} ALLOT',
        '_SNAP ST-SNAPSHOT',
        '_ADDR2 500 ST-CREATE DROP',
        '_SNAP ST-RESTORE',
        'ST-COUNT .',   # should be back to 1
    ]
    check("count=1 after restore", lines2, "1")

    # Balance preserved after restore
    lines3 = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        f'CREATE _SNAP {18440} ALLOT',
        '_SNAP ST-SNAPSHOT',
    ] + _make_tx_lines('_TX1', '_PUB1', '_PRIV1', '_PUB2', 500, 0) + [
        '_TX1 ST-APPLY-TX DROP',
        '_ADDR1 ST-BALANCE@ .',       # 500 after tx
    ]
    check("balance after tx is 500", lines3, "500")

    lines4 = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        f'CREATE _SNAP {18440} ALLOT',
        '_SNAP ST-SNAPSHOT',
    ] + _make_tx_lines('_TX1', '_PUB1', '_PRIV1', '_PUB2', 500, 0) + [
        '_TX1 ST-APPLY-TX DROP',
        '_SNAP ST-RESTORE',
        '_ADDR1 ST-BALANCE@ .',       # back to 1000
    ]
    check("balance restored to 1000", lines4, "1000")


def test_verify_valid():
    """Build a valid block (via finalize) and verify it."""
    print("\n=== BLK-VERIFY (valid block) ===")
    lines = _funded_state() + _make_tx_lines(
        '_TX1', '_PUB1', '_PRIV1', '_PUB2', 100, 0
    ) + [
        # Save state before finalize (we need original state for verify)
        f'CREATE _SNAP {18440} ALLOT',
        '_SNAP ST-SNAPSHOT',

        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
        '1 _BK BLK-SET-HEIGHT',
        '1700000000 _BK BLK-SET-TIME',
        'CREATE _PH 32 ALLOT  _PH 32 0 FILL  _PH _BK BLK-SET-PREV',
        '_TX1 _BK BLK-ADD-TX DROP',
        '_BK BLK-FINALIZE',

        # Restore state (undo the finalize mutation)
        '_SNAP ST-RESTORE',

        # Now verify should succeed (non-destructive)
        '_BK _PH BLK-VERIFY IF ." VOK" ELSE ." VFAIL" THEN',

        # State should be unchanged after verify (snapshot-and-restore)
        '_ADDR1 ST-BALANCE@ .',
    ]
    check("valid block verifies", lines, "VOK")
    check("state unchanged after verify", lines, "10000")


def test_verify_bad_prev():
    """Verify rejects block with wrong prev_hash."""
    print("\n=== BLK-VERIFY (bad prev_hash) ===")
    lines = _funded_state() + _make_tx_lines(
        '_TX1', '_PUB1', '_PRIV1', '_PUB2', 100, 0
    ) + [
        f'CREATE _SNAP {18440} ALLOT',
        '_SNAP ST-SNAPSHOT',

        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
        '1 _BK BLK-SET-HEIGHT',
        '1700000000 _BK BLK-SET-TIME',
        'CREATE _PH 32 ALLOT  _PH 32 0 FILL  _PH _BK BLK-SET-PREV',
        '_TX1 _BK BLK-ADD-TX DROP',
        '_BK BLK-FINALIZE',
        '_SNAP ST-RESTORE',

        # Try verify with WRONG prev hash -> should fail
        'CREATE _BAD 32 ALLOT  _BAD 32 0 FILL  255 _BAD C!',
        '_BK _BAD BLK-VERIFY IF ." VOK" ELSE ." VFAIL" THEN',
    ]
    check("wrong prev_hash rejected", lines, "VFAIL")


def test_verify_bad_state_root():
    """Verify rejects block with tampered state root."""
    print("\n=== BLK-VERIFY (bad state_root) ===")
    lines = _funded_state() + _make_tx_lines(
        '_TX1', '_PUB1', '_PRIV1', '_PUB2', 100, 0
    ) + [
        f'CREATE _SNAP {18440} ALLOT',
        '_SNAP ST-SNAPSHOT',

        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
        '1 _BK BLK-SET-HEIGHT',
        '1700000000 _BK BLK-SET-TIME',
        'CREATE _PH 32 ALLOT  _PH 32 0 FILL  _PH _BK BLK-SET-PREV',
        '_TX1 _BK BLK-ADD-TX DROP',
        '_BK BLK-FINALIZE',
        '_SNAP ST-RESTORE',

        # Tamper with state root
        '0 _BK BLK-STATE-ROOT@ C!',

        '_BK _PH BLK-VERIFY IF ." VOK" ELSE ." VFAIL" THEN',
    ]
    check("tampered state root rejected", lines, "VFAIL")


def test_verify_no_mutation():
    """Verify that BLK-VERIFY does not mutate state."""
    print("\n=== BLK-VERIFY (no mutation) ===")
    lines = _funded_state() + _make_tx_lines(
        '_TX1', '_PUB1', '_PRIV1', '_PUB2', 100, 0
    ) + [
        f'CREATE _SNAP {18440} ALLOT',
        '_SNAP ST-SNAPSHOT',

        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
        '1 _BK BLK-SET-HEIGHT',
        '1700000000 _BK BLK-SET-TIME',
        'CREATE _PH 32 ALLOT  _PH 32 0 FILL  _PH _BK BLK-SET-PREV',
        '_TX1 _BK BLK-ADD-TX DROP',
        '_BK BLK-FINALIZE',
        '_SNAP ST-RESTORE',

        # Check balance before verify
        '_ADDR1 ST-BALANCE@ .',           # 10000
        '_BK _PH BLK-VERIFY DROP',
        # Check balance after verify — should still be 10000
        '_ADDR1 ST-BALANCE@ .',           # 10000
    ]
    check("balance unchanged after verify", lines, "10000")


def test_encode_decode():
    print("\n=== BLK-ENCODE / BLK-DECODE ===")
    # Round-trip header fields
    lines = [
        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
        '42 _BK BLK-SET-HEIGHT',
        '1700000000 _BK BLK-SET-TIME',
        'CREATE _PH 32 ALLOT  _PH 32 0 FILL  171 _PH C!  _PH _BK BLK-SET-PREV',
        'CREATE _PR 5 ALLOT  _PR 5 0 FILL  99 _PR C!  _PR 5 _BK BLK-SET-PROOF',

        # Encode
        'CREATE _EBUF 4096 ALLOT',
        '_BK _EBUF 4096 BLK-ENCODE',
        'VARIABLE _ELEN  _ELEN !',

        # Decode into new block
        f'CREATE _BK2 {2304} ALLOT',
        '_EBUF _ELEN @ _BK2 BLK-DECODE IF ." DECOK" ELSE ." DECFAIL" THEN',

        # Check fields
        '_BK2 BLK-HEIGHT@ .',
        '_BK2 BLK-TIME@ .',
        '_BK2 BLK-VERSION@ .',
        '_BK2 BLK-PREV-HASH@ C@ .',
        '_BK2 BLK-PROOF@ . .',          # len first, then addr (we check len)
    ]
    check("decode succeeds", lines, "DECOK")
    check("height round-trips", lines, "42")
    check("timestamp round-trips", lines, "1700000000")
    check("prev_hash first byte", lines, "171")


def test_chain_init():
    print("\n=== CHAIN-INIT ===")
    lines = _keygen_preamble() + [
        'CHAIN-INIT',
        'CHAIN-HEIGHT .',
    ]
    check("genesis height is 0", lines, "0")

    # Chain head exists
    lines2 = _keygen_preamble() + [
        'CHAIN-INIT',
        'CHAIN-HEAD 0<> IF ." HEADOK" ELSE ." HEADNIL" THEN',
    ]
    check("chain head is non-null", lines2, "HEADOK")

    # Block at height 0 exists
    lines3 = _keygen_preamble() + [
        'CHAIN-INIT',
        '0 CHAIN-BLOCK@ 0<> IF ." B0OK" ELSE ." B0NIL" THEN',
    ]
    check("block@0 exists", lines3, "B0OK")

    # Block at height 1 doesn't exist yet
    lines4 = _keygen_preamble() + [
        'CHAIN-INIT',
        '1 CHAIN-BLOCK@ 0= IF ." B1NIL" ELSE ." B1OK" THEN',
    ]
    check("block@1 doesn't exist", lines4, "B1NIL")


def test_chain_append():
    """Build a valid block 1 and append it to the chain."""
    print("\n=== CHAIN-APPEND ===")
    lines = _funded_state() + [
        'CHAIN-INIT',

        # Get genesis hash for prev_hash of block 1
        'CREATE _GH 32 ALLOT',
        'CHAIN-HEAD _GH BLK-HASH',
    ] + _make_tx_lines('_TX1', '_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        # Build block 1
        f'CREATE _BK1 {2304} ALLOT',
        '_BK1 BLK-INIT',
        '1 _BK1 BLK-SET-HEIGHT',
        '1700000000 _BK1 BLK-SET-TIME',
        '_GH _BK1 BLK-SET-PREV',
        '_TX1 _BK1 BLK-ADD-TX DROP',

        # Snapshot state since finalize mutates it
        f'CREATE _SN {18440} ALLOT',
        '_SN ST-SNAPSHOT',
        '_BK1 BLK-FINALIZE',
        # Restore so CHAIN-APPEND can re-apply
        '_SN ST-RESTORE',

        # Append
        '_BK1 CHAIN-APPEND IF ." APPOK" ELSE ." APPFAIL" THEN',
        'CHAIN-HEIGHT .',
    ]
    check("append succeeds", lines, "APPOK")
    check("height is 1 after append", lines, "1")


def test_chain_append_mutates():
    """CHAIN-APPEND should permanently apply txs to state."""
    print("\n=== CHAIN-APPEND (state mutation) ===")
    lines = _funded_state() + [
        'CHAIN-INIT',
        'CREATE _GH 32 ALLOT',
        'CHAIN-HEAD _GH BLK-HASH',
    ] + _make_tx_lines('_TX1', '_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        f'CREATE _BK1 {2304} ALLOT',
        '_BK1 BLK-INIT',
        '1 _BK1 BLK-SET-HEIGHT',
        '1700000000 _BK1 BLK-SET-TIME',
        '_GH _BK1 BLK-SET-PREV',
        '_TX1 _BK1 BLK-ADD-TX DROP',
        f'CREATE _SN {18440} ALLOT',
        '_SN ST-SNAPSHOT',
        '_BK1 BLK-FINALIZE',
        '_SN ST-RESTORE',
        '_BK1 CHAIN-APPEND DROP',
        '_ADDR1 ST-BALANCE@ .',
    ]
    check("sender balance 9900 after append", lines, "9900")


def test_chain_append_bad_height():
    """CHAIN-APPEND rejects block with wrong height."""
    print("\n=== CHAIN-APPEND (bad height) ===")
    lines = _funded_state() + [
        'CHAIN-INIT',
        'CREATE _GH 32 ALLOT',
        'CHAIN-HEAD _GH BLK-HASH',
    ] + _make_tx_lines('_TX1', '_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        f'CREATE _BK1 {2304} ALLOT',
        '_BK1 BLK-INIT',
        '5 _BK1 BLK-SET-HEIGHT',        # wrong height (should be 1)
        '1700000000 _BK1 BLK-SET-TIME',
        '_GH _BK1 BLK-SET-PREV',
        '_TX1 _BK1 BLK-ADD-TX DROP',
        f'CREATE _SN {18440} ALLOT',
        '_SN ST-SNAPSHOT',
        '_BK1 BLK-FINALIZE',
        '_SN ST-RESTORE',
        '_BK1 CHAIN-APPEND IF ." APPOK" ELSE ." APPFAIL" THEN',
    ]
    check("wrong height rejected", lines, "APPFAIL")


def test_chain_two_blocks():
    """Append two consecutive blocks."""
    print("\n=== CHAIN two blocks ===")
    lines = _funded_state() + [
        'CHAIN-INIT',
        'CREATE _GH 32 ALLOT',
        'CHAIN-HEAD _GH BLK-HASH',
    ] + _make_tx_lines('_TX1', '_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        # Block 1
        f'CREATE _BK1 {2304} ALLOT',
        '_BK1 BLK-INIT',
        '1 _BK1 BLK-SET-HEIGHT',
        '1700000000 _BK1 BLK-SET-TIME',
        '_GH _BK1 BLK-SET-PREV',
        '_TX1 _BK1 BLK-ADD-TX DROP',
        f'CREATE _SN {18440} ALLOT',
        '_SN ST-SNAPSHOT',
        '_BK1 BLK-FINALIZE',
        '_SN ST-RESTORE',
        '_BK1 CHAIN-APPEND DROP',

        # Get block 1 hash for block 2's prev_hash
        'CREATE _H1 32 ALLOT',
        'CHAIN-HEAD _H1 BLK-HASH',
    ] + _make_tx_lines('_TX2', '_PUB1', '_PRIV1', '_PUB2', 200, 1) + [
        # Block 2
        f'CREATE _BK2 {2304} ALLOT',
        '_BK2 BLK-INIT',
        '2 _BK2 BLK-SET-HEIGHT',
        '1700000100 _BK2 BLK-SET-TIME',
        '_H1 _BK2 BLK-SET-PREV',
        '_TX2 _BK2 BLK-ADD-TX DROP',
        '_SN ST-SNAPSHOT',
        '_BK2 BLK-FINALIZE',
        '_SN ST-RESTORE',
        '_BK2 CHAIN-APPEND IF ." APP2OK" ELSE ." APP2FAIL" THEN',
        'CHAIN-HEIGHT .',
        '_ADDR1 ST-BALANCE@ .',
    ]
    check("block 2 appended", lines, "APP2OK")
    check("chain height is 2", lines, "2")
    check("sender balance after 2 blocks", lines, "9700")


def test_empty_block():
    """A block with zero transactions should still work."""
    print("\n=== Empty block ===")
    lines = _keygen_preamble() + [
        'CHAIN-INIT',
        'CREATE _GH 32 ALLOT',
        'CHAIN-HEAD _GH BLK-HASH',

        f'CREATE _BK {2304} ALLOT',
        '_BK BLK-INIT',
        '1 _BK BLK-SET-HEIGHT',
        '1700000000 _BK BLK-SET-TIME',
        '_GH _BK BLK-SET-PREV',
        # No txs added
        f'CREATE _SN {18440} ALLOT',
        '_SN ST-SNAPSHOT',
        '_BK BLK-FINALIZE',
        '_SN ST-RESTORE',
        '_BK CHAIN-APPEND IF ." EMPTYOK" ELSE ." EMPTYFAIL" THEN',
        'CHAIN-HEIGHT .',
    ]
    check("empty block appended", lines, "EMPTYOK")
    check("height 1 after empty block", lines, "1")


# =================================================================
#  Main
# =================================================================

if __name__ == "__main__":
    build_snapshot()

    test_compile()
    test_constants()
    test_init()
    test_setters()
    test_add_tx()
    test_finalize()
    test_hash()
    test_snapshot_restore()
    test_verify_valid()
    test_verify_bad_prev()
    test_verify_bad_state_root()
    test_verify_no_mutation()
    test_encode_decode()
    test_chain_init()
    test_chain_append()
    test_chain_append_mutates()
    test_chain_append_bad_height()
    test_chain_two_blocks()
    test_empty_block()

    print(f"\n{'='*40}")
    print(f"  {_pass_count} passed, {_fail_count} failed")
    print(f"{'='*40}")
    sys.exit(1 if _fail_count else 0)
