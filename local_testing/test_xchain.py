#!/usr/bin/env python3
"""Test suite for Akashic xchain.f (akashic/net/xchain.f).

Phase 7.5 — Cross-Chain Verification.

Tests:
  01  Compile check
  02  XCH-INIT + XCH-CHAIN-COUNT
  03  XCH-REGISTER
  04  XCH-REGISTER duplicate (idempotent)
  05  XCH-REGISTER full registry
  06  XCH-SET-AUTH
  07  XCH-SET-AIR
  08  XCH-UNREGISTER
  09  XCH-CHAIN-INFO
  10  XCH-SUBMIT-HEADER (PoA, accepted)
  11  XCH-SUBMIT-HEADER bad signature
  12  XCH-SUBMIT-HEADER unknown authority
  13  XCH-SUBMIT-HEADER sequential headers
  14  XCH-SUBMIT-HEADER wrong height
  15  XCH-SUBMIT-HEADER wrong prev_hash
  16  XCH-VERIFY-STATE (valid proof)
  17  XCH-VERIFY-STATE (tampered leaf)
  18  XCH-VERIFY-STATE (no verified header)
  19  XCH-SUBMIT-HEADER unsupported mode (PoW)
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")

# Dependency file paths (topological order)
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
XCHAIN_F   = os.path.join(ROOT_DIR, "akashic", "net", "xchain.f")

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
    print("[*] Building snapshot: BIOS + KDOS + xchain.f deps ...")
    t0 = time.time()
    bios_code   = _load_bios()
    kdos_lines  = _load_forth_lines(KDOS_PATH)

    dep_lines = []
    for path in [EVENT_F, SEM_F, GUARD_F, FP16_F,
                 SHA512_F, FIELD_F, SHA3_F, RANDOM_F,
                 ED25519_F, SPHINCS_F, CBOR_F, FMT_F,
                 MERKLE_F, SMT_F, TX_F, STATE_F, BLOCK_F,
                 LIGHT_F, XCHAIN_F]:
        dep_lines += _load_forth_lines(path)

    # Keygen seeds (RFC 8032 TV1, TV2)
    TV1_SEED = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
    TV2_SEED = "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"

    keygen_lines = []
    for seed_hex, pub_name, priv_name, seed_name in [
        (TV1_SEED, '_PUB1', '_PRIV1', '_SEED1'),
        (TV2_SEED, '_PUB2', '_PRIV2', '_SEED2'),
    ]:
        bs = bytes.fromhex(seed_hex)
        keygen_lines.append(f'CREATE {seed_name} 32 ALLOT')
        for i, b in enumerate(bs):
            keygen_lines.append(f'{b} {seed_name} {i} + C!')
        keygen_lines += [
            f'CREATE {pub_name} 32 ALLOT  CREATE {priv_name} 64 ALLOT',
            f'{seed_name} {pub_name} {priv_name} ED25519-KEYGEN',
        ]

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
                 + keygen_lines
                 + helpers)
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode(); pos = 0; steps = 0; mx = 1_500_000_000
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
        for l in text.strip().split('\n')[-30:]:
            print(f"    {l}")
        sys.exit(1)
    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot

# Per-test cycle limit: keygen is in snapshot, so tests only need sign+verify
MAX_STEPS = 800_000_000
SIGN2_MAX_STEPS = 1_200_000_000  # for tests with 2 sign operations

def run_forth(lines, max_steps=MAX_STEPS):
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

def check(name, forth_lines, expected, max_steps=MAX_STEPS):
    global _pass_count, _fail_count
    output = run_forth(forth_lines, max_steps=max_steps)
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

def check_fn(name, forth_lines, predicate, desc="", max_steps=MAX_STEPS):
    global _pass_count, _fail_count
    output = run_forth(forth_lines, max_steps=max_steps)
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

# Keys _PUB1/_PRIV1/_PUB2/_PRIV2 are created during snapshot build.
# No per-test keygen needed.

def _xchain_preamble():
    """xchain scratch buffers + XCH-INIT (keys already in snapshot)."""
    return [
        'CREATE _FBLK BLK-STRUCT-SIZE ALLOT',
        'CREATE _SHASH 32 ALLOT  CREATE _FSIG 64 ALLOT',
        'CREATE _FENC 4096 ALLOT  VARIABLE _FLEN',
        'CREATE _PREV 32 ALLOT  _PREV 32 0 FILL  1 _PREV C!',
        'CREATE _SROOT 32 ALLOT  _SROOT 32 0 FILL  2 _SROOT C!',
        'CREATE _TXROOT 32 ALLOT  _TXROOT 32 0 FILL',
        'XCH-INIT',
    ]

def _build_poa_block(blk, height, time_val, prev_var, sroot_var, pub_var, priv_var):
    """Return Forth lines: build PoA block, sign, encode to _FENC/_FLEN."""
    return [
        f'{blk} BLK-INIT  {height} {blk} BLK-SET-HEIGHT  {time_val} {blk} BLK-SET-TIME',
        f'{prev_var} {blk} BLK-SET-PREV',
        f'{sroot_var} {blk} 41 + 32 CMOVE  _TXROOT {blk} 73 + 32 CMOVE',
        f'0 {blk} 113 + C!  {blk} _SHASH BLK-HASH',
        f'_SHASH 32 {priv_var} {pub_var} _FSIG ED25519-SIGN',
        f'{pub_var} {blk} 114 + 32 CMOVE  _FSIG {blk} 114 + 32 + 64 CMOVE  96 {blk} 113 + C!',
        f'{blk} _FENC 4096 BLK-ENCODE _FLEN !',
    ]


# ====================================================================
#  Tests
# ====================================================================

def test_01_compile():
    print("\n=== 01 Compile check ===")
    check("xchain.f loaded", ['1 2 + .'], "3")

def test_02_init():
    print("\n=== 02 XCH-INIT + count ===")
    check("init count=0", [
        'XCH-INIT  ." [C=" XCH-CHAIN-COUNT . ." ]"',
    ], "[C=0 ]")

def test_03_register():
    print("\n=== 03 XCH-REGISTER ===")
    check("register", [
        'XCH-INIT',
        '." [R=" 42 1 XCH-REGISTER . ." ][C=" XCH-CHAIN-COUNT . ." ]"',
    ], "[R=0 ][C=1 ]")

def test_04_register_dup():
    print("\n=== 04 XCH-REGISTER duplicate ===")
    check("dup register", [
        'XCH-INIT',
        '42 1 XCH-REGISTER DROP',
        '." [R=" 42 1 XCH-REGISTER . ." ][C=" XCH-CHAIN-COUNT . ." ]"',
    ], "[R=0 ][C=1 ]")

def test_05_register_full():
    print("\n=== 05 XCH-REGISTER full ===")
    lines = ['XCH-INIT']
    for i in range(16):
        lines.append(f'{i+1} 1 XCH-REGISTER DROP')
    lines.append('." [R=" 17 1 XCH-REGISTER . ." ][C=" XCH-CHAIN-COUNT . ." ]"')
    check("full registry", lines, "[R=1 ][C=16 ]")

def test_06_set_auth():
    print("\n=== 06 XCH-SET-AUTH ===")
    lines = [
        'XCH-INIT  42 1 XCH-REGISTER DROP',
        '." [A=" _PUB1 42 0 XCH-SET-AUTH . ." ][B=" _PUB2 42 1 XCH-SET-AUTH . ." ][C=" _PUB1 99 0 XCH-SET-AUTH . ." ][D=" _PUB1 42 8 XCH-SET-AUTH . ." ]"',
    ]
    check("set_auth", lines, "[A=0 ][B=0 ][C=2 ][D=9 ]")

def test_07_set_air():
    print("\n=== 07 XCH-SET-AIR ===")
    check("set_air", [
        'XCH-INIT  42 1 XCH-REGISTER DROP',
        '." [A=" 100 42 XCH-SET-AIR . ." ][B=" 100 99 XCH-SET-AIR . ." ]"',
    ], "[A=0 ][B=2 ]")

def test_08_unregister():
    print("\n=== 08 XCH-UNREGISTER ===")
    check("unregister", [
        'XCH-INIT  42 1 XCH-REGISTER DROP  43 3 XCH-REGISTER DROP',
        '." [C=" XCH-CHAIN-COUNT . ." ][U=" 42 XCH-UNREGISTER . ." ][C=" XCH-CHAIN-COUNT . ." ][U=" 42 XCH-UNREGISTER . ." ][U=" 43 XCH-UNREGISTER . ." ][C=" XCH-CHAIN-COUNT . ." ]"',
    ], "[C=2 ][U=0 ][C=1 ][U=2 ][U=0 ][C=0 ]")

def test_09_chain_info():
    print("\n=== 09 XCH-CHAIN-INFO ===")
    check("chain_info", [
        'XCH-INIT  42 1 XCH-REGISTER DROP  200 42 XCH-SET-AIR DROP',
        '42 XCH-CHAIN-INFO ." [H=" . ." ][A=" . ." ][M=" . ." ]" 99 XCH-CHAIN-INFO ." [H=" . ." ][A=" . ." ][M=" . ." ]"',
    ], "[H=-1 ][A=200 ][M=1 ][H=-1 ][A=0 ][M=0 ]")

def test_10_submit_header_poa():
    """Submit a valid PoA-signed foreign block header."""
    print("\n=== 10 XCH-SUBMIT-HEADER (PoA) ===")
    lines = _xchain_preamble() + [
        '42 1 XCH-REGISTER DROP  _PUB1 42 0 XCH-SET-AUTH DROP',
    ] + _build_poa_block('_FBLK', 1, 1000, '_PREV', '_SROOT', '_PUB1', '_PRIV1') + [
        '." [S=" _FENC _FLEN @ 42 XCH-SUBMIT-HEADER . ." ][H=" 42 XCH-HEIGHT . ." ]"',
    ]
    check("submit_poa", lines, "[S=0 ][H=1 ]")

def test_11_submit_bad_sig():
    """Tampered CBOR should cause decode fail or signature rejection."""
    print("\n=== 11 XCH-SUBMIT-HEADER bad sig ===")
    lines = _xchain_preamble() + [
        '42 1 XCH-REGISTER DROP  _PUB1 42 0 XCH-SET-AUTH DROP',
    ] + _build_poa_block('_FBLK', 1, 1000, '_PREV', '_SROOT', '_PUB1', '_PRIV1') + [
        '_FLEN @ 10 - _FENC + DUP C@ 255 XOR SWAP C!',
        '." [S=" _FENC _FLEN @ 42 XCH-SUBMIT-HEADER . ." ]"',
    ]
    check_fn("bad_sig", lines,
             lambda o: "[S=6 ]" in o or "[S=3 ]" in o,
             "expected [S=6] or [S=3]")

def test_12_submit_bad_auth():
    """Valid signature from non-authority key → ERR-AUTH."""
    print("\n=== 12 XCH-SUBMIT-HEADER unknown authority ===")
    lines = _xchain_preamble() + [
        '42 1 XCH-REGISTER DROP  _PUB1 42 0 XCH-SET-AUTH DROP',
    ] + _build_poa_block('_FBLK', 1, 1000, '_PREV', '_SROOT', '_PUB2', '_PRIV2') + [
        '." [S=" _FENC _FLEN @ 42 XCH-SUBMIT-HEADER . ." ]"',
    ]
    check("bad_auth", lines, "[S=7 ]")

def test_13_submit_sequence():
    """Two sequential headers should both be accepted."""
    print("\n=== 13 XCH-SUBMIT-HEADER sequence ===")
    lines = _xchain_preamble() + [
        '42 1 XCH-REGISTER DROP  _PUB1 42 0 XCH-SET-AUTH DROP',
    ] + _build_poa_block('_FBLK', 1, 1000, '_PREV', '_SROOT', '_PUB1', '_PRIV1') + [
        '." [S1=" _FENC _FLEN @ 42 XCH-SUBMIT-HEADER . ." ]"',
        'CREATE _H1 32 ALLOT  _FBLK _H1 BLK-HASH',
    ] + _build_poa_block('_FBLK', 2, 2000, '_H1', '_SROOT', '_PUB1', '_PRIV1') + [
        '." [S2=" _FENC _FLEN @ 42 XCH-SUBMIT-HEADER . ." ][H=" 42 XCH-HEIGHT . ." ]"',
    ]
    check_fn("sequence", lines,
             lambda o: "[S1=0 ]" in o and "[S2=0 ]" in o and "[H=2 ]" in o,
             "expected [S1=0] [S2=0] [H=2]",
             max_steps=SIGN2_MAX_STEPS)

def test_14_submit_bad_height():
    """Non-sequential height → ERR-HEIGHT after first header."""
    print("\n=== 14 XCH-SUBMIT-HEADER wrong height ===")
    lines = _xchain_preamble() + [
        '42 1 XCH-REGISTER DROP  _PUB1 42 0 XCH-SET-AUTH DROP',
    ] + _build_poa_block('_FBLK', 1, 1000, '_PREV', '_SROOT', '_PUB1', '_PRIV1') + [
        '_FENC _FLEN @ 42 XCH-SUBMIT-HEADER DROP',
        'CREATE _H1 32 ALLOT  _FBLK _H1 BLK-HASH',
    ] + _build_poa_block('_FBLK', 3, 2000, '_H1', '_SROOT', '_PUB1', '_PRIV1') + [
        '." [S=" _FENC _FLEN @ 42 XCH-SUBMIT-HEADER . ." ]"',
    ]
    check("bad_height", lines, "[S=4 ]", max_steps=SIGN2_MAX_STEPS)

def test_15_submit_bad_prev():
    """Wrong prev_hash → ERR-PREV."""
    print("\n=== 15 XCH-SUBMIT-HEADER wrong prev ===")
    lines = _xchain_preamble() + [
        '42 1 XCH-REGISTER DROP  _PUB1 42 0 XCH-SET-AUTH DROP',
    ] + _build_poa_block('_FBLK', 1, 1000, '_PREV', '_SROOT', '_PUB1', '_PRIV1') + [
        '_FENC _FLEN @ 42 XCH-SUBMIT-HEADER DROP',
    ] + _build_poa_block('_FBLK', 2, 2000, '_PREV', '_SROOT', '_PUB1', '_PRIV1') + [
        '." [S=" _FENC _FLEN @ 42 XCH-SUBMIT-HEADER . ." ]"',
    ]
    check("bad_prev", lines, "[S=5 ]", max_steps=SIGN2_MAX_STEPS)

def test_16_verify_state():
    """Valid SMT proof against verified foreign state root."""
    print("\n=== 16 XCH-VERIFY-STATE (valid) ===")
    lines = _xchain_preamble() + [
        'CREATE _ADDR1 32 ALLOT  _PUB1 _ADDR1 ST-ADDR-FROM-KEY',
        'ST-INIT DROP  _ADDR1 1000 ST-CREATE DROP',
        'CREATE _RROOT 32 ALLOT  ST-ROOT DROP _RROOT 32 CMOVE',
        'CREATE _PROOF 10240 ALLOT  VARIABLE _PLEN',
        '_ADDR1 _PROOF LC-STATE-PROOF _PLEN !',
        'CREATE _LEAF 32 ALLOT  _ADDR1 _LEAF LC-STATE-LEAF DROP',
        '42 1 XCH-REGISTER DROP  _PUB1 42 0 XCH-SET-AUTH DROP',
    ] + _build_poa_block('_FBLK', 1, 1000, '_PREV', '_RROOT', '_PUB1', '_PRIV1') + [
        '." [S=" _FENC _FLEN @ 42 XCH-SUBMIT-HEADER . ." ][V=" _ADDR1 _LEAF _PROOF _PLEN @ 42 XCH-VERIFY-STATE . ." ]"',
    ]
    check("verify_state", lines, "[S=0 ][V=-1 ]")

def test_17_verify_state_bad():
    """Tampered leaf should fail verification."""
    print("\n=== 17 XCH-VERIFY-STATE (bad leaf) ===")
    lines = _xchain_preamble() + [
        'CREATE _ADDR1 32 ALLOT  _PUB1 _ADDR1 ST-ADDR-FROM-KEY',
        'ST-INIT DROP  _ADDR1 1000 ST-CREATE DROP',
        'CREATE _RROOT 32 ALLOT  ST-ROOT DROP _RROOT 32 CMOVE',
        'CREATE _PROOF 10240 ALLOT  VARIABLE _PLEN',
        '_ADDR1 _PROOF LC-STATE-PROOF _PLEN !',
        'CREATE _LEAF 32 ALLOT  _ADDR1 _LEAF LC-STATE-LEAF DROP',
        '_LEAF C@ 255 XOR _LEAF C!',
        '42 1 XCH-REGISTER DROP  _PUB1 42 0 XCH-SET-AUTH DROP',
    ] + _build_poa_block('_FBLK', 1, 1000, '_PREV', '_RROOT', '_PUB1', '_PRIV1') + [
        '_FENC _FLEN @ 42 XCH-SUBMIT-HEADER DROP',
        '." [V=" _ADDR1 _LEAF _PROOF _PLEN @ 42 XCH-VERIFY-STATE . ." ]"',
    ]
    check("verify_bad_leaf", lines, "[V=0 ]")

def test_18_verify_no_header():
    """Verify should fail before any header is submitted."""
    print("\n=== 18 XCH-VERIFY-STATE (no header) ===")
    lines = _xchain_preamble() + [
        'CREATE _ADDR1 32 ALLOT  _PUB1 _ADDR1 ST-ADDR-FROM-KEY',
        'ST-INIT DROP  _ADDR1 1000 ST-CREATE DROP',
        'CREATE _PROOF 10240 ALLOT  VARIABLE _PLEN',
        '_ADDR1 _PROOF LC-STATE-PROOF _PLEN !',
        'CREATE _LEAF 32 ALLOT  _ADDR1 _LEAF LC-STATE-LEAF DROP',
        '42 1 XCH-REGISTER DROP  _PUB1 42 0 XCH-SET-AUTH DROP',
        '." [V=" _ADDR1 _LEAF _PROOF _PLEN @ 42 XCH-VERIFY-STATE . ." ]"',
    ]
    check("no_header", lines, "[V=0 ]")

def test_19_submit_pow_mode():
    """PoW mode (0) → ERR-MODE."""
    print("\n=== 19 XCH-SUBMIT-HEADER PoW mode ===")
    lines = _xchain_preamble() + [
        '42 0 XCH-REGISTER DROP  _PUB1 42 0 XCH-SET-AUTH DROP',
    ] + _build_poa_block('_FBLK', 1, 1000, '_PREV', '_SROOT', '_PUB1', '_PRIV1') + [
        '." [S=" _FENC _FLEN @ 42 XCH-SUBMIT-HEADER . ." ]"',
    ]
    check("pow_mode", lines, "[S=8 ]")


# ====================================================================

def main():
    build_snapshot()
    print("\n── Cross-Chain Verification Tests ──")

    test_01_compile()
    test_02_init()
    test_03_register()
    test_04_register_dup()
    test_05_register_full()
    test_06_set_auth()
    test_07_set_air()
    test_08_unregister()
    test_09_chain_info()
    test_10_submit_header_poa()
    test_11_submit_bad_sig()
    test_12_submit_bad_auth()
    test_13_submit_sequence()
    test_14_submit_bad_height()
    test_15_submit_bad_prev()
    test_16_verify_state()
    test_17_verify_state_bad()
    test_18_verify_no_header()
    test_19_submit_pow_mode()

    total = _pass_count + _fail_count
    print(f"\n{'='*40}")
    print(f"  {_pass_count}/{total} passed")
    if _fail_count:
        print(f"  {_fail_count} FAILED")
    print(f"{'='*40}")
    return 1 if _fail_count else 0

if __name__ == "__main__":
    sys.exit(main())
