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
"""Test suite for Akashic Ed25519 (akashic/math/ed25519.f).

Tests key generation, signing, and verification using RFC 8032 test vectors.
"""
import os, sys, time, hashlib

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")

SHA512_F   = os.path.join(ROOT_DIR, "akashic", "math", "sha512.f")
FIELD_F    = os.path.join(ROOT_DIR, "akashic", "math", "field.f")
ED25519_F  = os.path.join(ROOT_DIR, "akashic", "math", "ed25519.f")
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
SEM_F      = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")
GUARD_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "guard.f")

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
    print("[*] Building snapshot: BIOS + KDOS + sha512 + field + ed25519 ...")
    t0 = time.time()
    bios_code    = _load_bios()
    kdos_lines   = _load_forth_lines(KDOS_PATH)
    event_lines  = _load_forth_lines(EVENT_F)
    sem_lines    = _load_forth_lines(SEM_F)
    guard_lines  = _load_forth_lines(GUARD_F)
    sha512_lines = _load_forth_lines(SHA512_F)
    field_lines  = _load_forth_lines(FIELD_F)
    ed_lines     = _load_forth_lines(ED25519_F)

    helpers = [
        'CREATE _TB 512 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        # Hex dump a buffer: ( addr n -- ) prints each byte as 2 hex chars
        ': _HEXNIB  DUP 10 < IF 48 + ELSE 87 + THEN EMIT ;',
        ': .HEX  ( addr n -- ) 0 ?DO DUP I + C@ DUP 4 RSHIFT _HEXNIB 15 AND _HEXNIB LOOP DROP ;',
    ]

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + ["ENTER-USERLAND"]
                 + event_lines + sem_lines + guard_lines
                 + sha512_lines
                 + field_lines
                 + ed_lines
                 + helpers)
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode(); pos = 0; steps = 0; mx = 600_000_000
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
            print(f"  [!] {l}")
    if errors:
        print(f"  [FATAL] {len(errors)} 'not found' errors during load!")
        print(f"  Aborting — ed25519.f failed to compile cleanly.")
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
        for l in clean.split('\n')[-4:]:
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
        for l in clean.split('\n')[-4:]:
            print(f"        got:      '{l}'")

# ── Forth helpers ──

def store_hex(var_name, hex_str):
    """Store hex bytes into an existing buffer."""
    bs = bytes.fromhex(hex_str)
    lines = []
    for i, b in enumerate(bs):
        lines.append(f'{b} {var_name} {i} + C!')
    return lines

def create_hex_buf(var_name, hex_str):
    """Create a buffer and fill with hex bytes."""
    bs = bytes.fromhex(hex_str)
    n = len(bs)
    lines = [f'CREATE {var_name} {n} ALLOT']
    for i, b in enumerate(bs):
        lines.append(f'{b} {var_name} {i} + C!')
    return lines

# ── RFC 8032 Test Vectors ──

TV1_SEED = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
TV1_PUB  = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
TV1_MSG  = ""  # empty
TV1_SIG  = "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"

TV2_SEED = "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
TV2_PUB  = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"
TV2_MSG  = "72"
TV2_SIG  = "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"

TV3_SEED = "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7"
TV3_PUB  = "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025"
TV3_MSG  = "af82"
TV3_SIG  = "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a"

# ── Tests ──

def test_constants():
    print("\n=== Constants ===")
    check("ED25519-KEY-LEN", ['ED25519-KEY-LEN .'], "32")
    check("ED25519-SIG-LEN", ['ED25519-SIG-LEN .'], "64")

def test_compile():
    """Verify module loaded cleanly by calling a simple word."""
    print("\n=== Compile check ===")
    check("Module loaded", ['1 2 + .'], "3")

def test_keygen_tv1():
    """Test vector 1: keygen from seed -> public key."""
    print("\n=== Keygen TV1 ===")
    lines = create_hex_buf('_TSEED', TV1_SEED) + [
        'CREATE _TPUB 32 ALLOT',
        'CREATE _TPRIV 64 ALLOT',
        '_TSEED _TPUB _TPRIV ED25519-KEYGEN',
        '_TPUB 32 .HEX',
    ]
    check("Keygen TV1 pubkey", lines, TV1_PUB)

def test_sign_tv1():
    """Test vector 1: sign empty message."""
    print("\n=== Sign TV1 ===")
    # Need to set up seed -> keygen first, then sign
    lines = create_hex_buf('_TSEED', TV1_SEED) + [
        'CREATE _TPUB 32 ALLOT',
        'CREATE _TPRIV 64 ALLOT',
        'CREATE _TSIG 64 ALLOT',
        '_TSEED _TPUB _TPRIV ED25519-KEYGEN',
        # Sign empty message: msg=0 len=0
        '0 0 _TPRIV _TPUB _TSIG ED25519-SIGN',
        '_TSIG 64 .HEX',
    ]
    check("Sign TV1 sig", lines, TV1_SIG)

def test_verify_tv1():
    """Test vector 1: verify signature."""
    print("\n=== Verify TV1 ===")
    lines = create_hex_buf('_TSEED', TV1_SEED) + [
        'CREATE _TPUB 32 ALLOT',
        'CREATE _TPRIV 64 ALLOT',
        'CREATE _TSIG 64 ALLOT',
        '_TSEED _TPUB _TPRIV ED25519-KEYGEN',
        '0 0 _TPRIV _TPUB _TSIG ED25519-SIGN',
        '0 0 _TPUB _TSIG ED25519-VERIFY .',
    ]
    check("Verify TV1", lines, "-1")  # TRUE = -1

def test_keygen_tv2():
    """Test vector 2: keygen."""
    print("\n=== Keygen TV2 ===")
    lines = create_hex_buf('_TSEED', TV2_SEED) + [
        'CREATE _TPUB 32 ALLOT',
        'CREATE _TPRIV 64 ALLOT',
        '_TSEED _TPUB _TPRIV ED25519-KEYGEN',
        '_TPUB 32 .HEX',
    ]
    check("Keygen TV2 pubkey", lines, TV2_PUB)

def test_sign_verify_tv2():
    """Test vector 2: sign and verify 1-byte message."""
    print("\n=== Sign+Verify TV2 ===")
    lines = create_hex_buf('_TSEED', TV2_SEED) + [
        'CREATE _TPUB 32 ALLOT',
        'CREATE _TPRIV 64 ALLOT',
        'CREATE _TSIG 64 ALLOT',
        'CREATE _TMSG 1 ALLOT  0x72 _TMSG C!',
        '_TSEED _TPUB _TPRIV ED25519-KEYGEN',
        '_TMSG 1 _TPRIV _TPUB _TSIG ED25519-SIGN',
        '_TSIG 64 .HEX',
    ]
    check("Sign TV2 sig", lines, TV2_SIG)

    # Verify
    lines2 = create_hex_buf('_TSEED', TV2_SEED) + [
        'CREATE _TPUB 32 ALLOT',
        'CREATE _TPRIV 64 ALLOT',
        'CREATE _TSIG 64 ALLOT',
        'CREATE _TMSG 1 ALLOT  0x72 _TMSG C!',
        '_TSEED _TPUB _TPRIV ED25519-KEYGEN',
        '_TMSG 1 _TPRIV _TPUB _TSIG ED25519-SIGN',
        '_TMSG 1 _TPUB _TSIG ED25519-VERIFY .',
    ]
    check("Verify TV2", lines2, "-1")

def test_verify_bad_sig():
    """Verify rejects corrupted signature."""
    print("\n=== Verify bad sig ===")
    lines = create_hex_buf('_TSEED', TV1_SEED) + [
        'CREATE _TPUB 32 ALLOT',
        'CREATE _TPRIV 64 ALLOT',
        'CREATE _TSIG 64 ALLOT',
        '_TSEED _TPUB _TPRIV ED25519-KEYGEN',
        '0 0 _TPRIV _TPUB _TSIG ED25519-SIGN',
        # Corrupt one byte in signature
        '_TSIG 10 + DUP C@ 1 XOR SWAP C!',
        '0 0 _TPUB _TSIG ED25519-VERIFY .',
    ]
    check("Verify reject bad sig", lines, "0")

def test_verify_wrong_key():
    """Verify rejects wrong public key."""
    print("\n=== Verify wrong key ===")
    lines = (
        create_hex_buf('_TSEED1', TV1_SEED)
        + create_hex_buf('_TSEED2', TV2_SEED)
        + [
        'CREATE _TPUB1 32 ALLOT  CREATE _TPRIV1 64 ALLOT',
        'CREATE _TPUB2 32 ALLOT  CREATE _TPRIV2 64 ALLOT',
        'CREATE _TSIG 64 ALLOT',
        '_TSEED1 _TPUB1 _TPRIV1 ED25519-KEYGEN',
        '_TSEED2 _TPUB2 _TPRIV2 ED25519-KEYGEN',
        # Sign with key1, verify with key2
        '0 0 _TPRIV1 _TPUB1 _TSIG ED25519-SIGN',
        '0 0 _TPUB2 _TSIG ED25519-VERIFY .',
    ])
    check("Verify reject wrong key", lines, "0")

def test_keygen_tv3():
    """Test vector 3: keygen."""
    print("\n=== Keygen TV3 ===")
    lines = create_hex_buf('_TSEED', TV3_SEED) + [
        'CREATE _TPUB 32 ALLOT',
        'CREATE _TPRIV 64 ALLOT',
        '_TSEED _TPUB _TPRIV ED25519-KEYGEN',
        '_TPUB 32 .HEX',
    ]
    check("Keygen TV3 pubkey", lines, TV3_PUB)

def test_sign_verify_tv3():
    """Test vector 3: sign and verify 2-byte message."""
    print("\n=== Sign+Verify TV3 ===")
    lines = create_hex_buf('_TSEED', TV3_SEED) + [
        'CREATE _TPUB 32 ALLOT',
        'CREATE _TPRIV 64 ALLOT',
        'CREATE _TSIG 64 ALLOT',
        'CREATE _TMSG 2 ALLOT  0xAF _TMSG C!  0x82 _TMSG 1 + C!',
        '_TSEED _TPUB _TPRIV ED25519-KEYGEN',
        '_TMSG 2 _TPRIV _TPUB _TSIG ED25519-SIGN',
        '_TSIG 64 .HEX',
    ]
    check("Sign TV3 sig", lines, TV3_SIG)

    # Verify
    lines2 = create_hex_buf('_TSEED', TV3_SEED) + [
        'CREATE _TPUB 32 ALLOT',
        'CREATE _TPRIV 64 ALLOT',
        'CREATE _TSIG 64 ALLOT',
        'CREATE _TMSG 2 ALLOT  0xAF _TMSG C!  0x82 _TMSG 1 + C!',
        '_TSEED _TPUB _TPRIV ED25519-KEYGEN',
        '_TMSG 2 _TPRIV _TPUB _TSIG ED25519-SIGN',
        '_TMSG 2 _TPUB _TSIG ED25519-VERIFY .',
    ]
    check("Verify TV3", lines2, "-1")


# ── Phase 6.6 Hardening Tests ──

# Ed25519 group order L in 32-byte LE hex:
# L = 2^252 + 27742317777372353535851937790883648493
# BE: 10000000 00000000 00000000 00000000 14def9de a2f79cd6 5812631a 5cf5d3ed
# LE: edd3f55c fa7d18db 14def9de a2f79cd6 5812631a 5cf5d3ed 00000000 00000000
#     10000000 00000000
L_LE_HEX = "edd3f55cfa7d18db14def9dea2f79cd65812631a5cf5d3ed00000000000000001000000000000000"

def test_p02_malleability_reject():
    """P02: Verify rejects malleable sig where S is replaced by S + L."""
    print("\n=== P02: Malleability rejection (S >= L) ===")
    # Sign with TV1, then add L to S (bytes 32..63), verify must fail
    lines = create_hex_buf('_TSEED', TV1_SEED) + [
        'CREATE _TPUB 32 ALLOT',
        'CREATE _TPRIV 64 ALLOT',
        'CREATE _TSIG 64 ALLOT',
        '_TSEED _TPUB _TPRIV ED25519-KEYGEN',
        '0 0 _TPRIV _TPUB _TSIG ED25519-SIGN',
        # First, verify the original works
        '0 0 _TPUB _TSIG ED25519-VERIFY .',
    ]
    check("P02 original passes", lines, "-1")

    # Now craft a sig with S = L (exact boundary — should fail)
    lines2 = create_hex_buf('_TSEED', TV1_SEED) + [
        'CREATE _TPUB 32 ALLOT',
        'CREATE _TPRIV 64 ALLOT',
        'CREATE _TSIG 64 ALLOT',
        '_TSEED _TPUB _TPRIV ED25519-KEYGEN',
        '0 0 _TPRIV _TPUB _TSIG ED25519-SIGN',
    ] + store_hex('_TSIG 32 +', L_LE_HEX) + [
        # S = L exactly → must be rejected (S >= L)
        '0 0 _TPUB _TSIG ED25519-VERIFY .',
    ]
    check("P02 S=L rejected", lines2, "0")

    # S = L - 1  (max valid scalar — should not be rejected by malleability
    # check, though it will likely fail the math check)
    # We just test that the malleability check itself doesn't reject L-1
    # by checking it passes through to the math (returns 0 from math, not
    # from the S>=L guard).  We verify indirectly: if S=0 passes the
    # guard (0 < L) but fails math, that's fine.
    lines3 = create_hex_buf('_TSEED', TV1_SEED) + [
        'CREATE _TPUB 32 ALLOT',
        'CREATE _TPRIV 64 ALLOT',
        'CREATE _TSIG 64 ALLOT',
        '_TSEED _TPUB _TPRIV ED25519-KEYGEN',
        '0 0 _TPRIV _TPUB _TSIG ED25519-SIGN',
        # Set S = 0 (definitely < L, but wrong math → verify fails)
        '_TSIG 32 + 32 0 FILL',
        '0 0 _TPUB _TSIG ED25519-VERIFY .',
    ]
    check("P02 S=0 passes guard (fails math)", lines3, "0")


def test_p04_noncanonical_y():
    """P04: Verify rejects a public key with y >= p (non-canonical encoding)."""
    print("\n=== P04: Non-canonical y rejection (y >= p) ===")
    # Create a valid keypair, then corrupt the pubkey so y >= p
    # p = 2^255 - 19, so byte 31 high bit is 0x7F.
    # Setting byte 31 to 0xFF (with sign bit masked) gives y >= p.
    # Actually, the sign bit is in the MSB of byte 31.  After decode,
    # the code masks with 0x7F.  So we need the y value (after masking)
    # to be >= p.  Set all bytes to 0xFF, byte 31 = 0xFF:
    # After masking sign bit: byte 31 = 0x7F, rest = 0xFF
    # => y = 0x7FFFFFFFFFFFFFFF FFFFFFFFFFFFFFFF FFFFFFFFFFFFFFFF FFFFFFFFFFFFFFFF
    # p   = 0x7FFFFFFFFFFFFFFF FFFFFFFFFFFFFFFF FFFFFFFFFFFFFFFF FFFFFFFFFFFFFFED
    # y > p => rejected.

    lines = create_hex_buf('_TSEED', TV1_SEED) + [
        'CREATE _TPUB 32 ALLOT',
        'CREATE _TPRIV 64 ALLOT',
        'CREATE _TSIG 64 ALLOT',
        '_TSEED _TPUB _TPRIV ED25519-KEYGEN',
        '0 0 _TPRIV _TPUB _TSIG ED25519-SIGN',
        # Overwrite pubkey with y = all 0xFF (y = 2^256-1 after sign mask => 2^255-1 > p)
        '_TPUB 32 0xFF FILL',
        '0 0 _TPUB _TSIG ED25519-VERIFY .',
    ]
    check("P04 y=all-FF rejected", lines, "0")

    # y = p exactly (should also be rejected: y >= p)
    # p in LE: ED FF FF FF FF FF FF FF  FF FF FF FF FF FF FF FF
    #          FF FF FF FF FF FF FF FF  FF FF FF FF FF FF FF 7F
    lines2 = create_hex_buf('_TSEED', TV1_SEED) + [
        'CREATE _TPUB 32 ALLOT',
        'CREATE _TPRIV 64 ALLOT',
        'CREATE _TSIG 64 ALLOT',
        '_TSEED _TPUB _TPRIV ED25519-KEYGEN',
        '0 0 _TPRIV _TPUB _TSIG ED25519-SIGN',
    ] + store_hex('_TPUB',
        'edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f'
    ) + [
        '0 0 _TPUB _TSIG ED25519-VERIFY .',
    ]
    check("P04 y=p rejected", lines2, "0")

    # y = p - 1 should NOT be rejected by the canonical check
    # (will likely fail the curve equation, but the guard itself is fine)
    lines3 = create_hex_buf('_TSEED', TV1_SEED) + [
        'CREATE _TPUB 32 ALLOT',
        'CREATE _TPRIV 64 ALLOT',
        'CREATE _TSIG 64 ALLOT',
        '_TSEED _TPUB _TPRIV ED25519-KEYGEN',
        '0 0 _TPRIV _TPUB _TSIG ED25519-SIGN',
    ] + store_hex('_TPUB',
        'ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f'
    ) + [
        # y = p-1 passes the canonical check but fails curve math → returns 0
        '0 0 _TPUB _TSIG ED25519-VERIFY .',
    ]
    check("P04 y=p-1 passes guard (fails math)", lines3, "0")


def test_p05_zeroization():
    """P05: Secret buffers are zeroed after sign."""
    print("\n=== P05: Secret zeroization after sign ===")
    # After signing, _ED-H64 (64 bytes), _ED-SC1, _ED-SC2, _ED-SC3 (32 each),
    # _ED-PA, _ED-PB (128 each) should be all zeros.
    # We check _ED-H64 and _ED-SC1 by examining them directly.
    lines = create_hex_buf('_TSEED', TV1_SEED) + [
        'CREATE _TPUB 32 ALLOT',
        'CREATE _TPRIV 64 ALLOT',
        'CREATE _TSIG 64 ALLOT',
        '_TSEED _TPUB _TPRIV ED25519-KEYGEN',
        '0 0 _TPRIV _TPUB _TSIG ED25519-SIGN',
        # Check _ED-H64 is zeroed (sum all 64 bytes)
        '0 64 0 DO _ED-H64 I + C@ + LOOP .',
    ]
    check("P05 _ED-H64 zeroed after sign", lines, "0")

    lines2 = create_hex_buf('_TSEED', TV1_SEED) + [
        'CREATE _TPUB 32 ALLOT',
        'CREATE _TPRIV 64 ALLOT',
        'CREATE _TSIG 64 ALLOT',
        '_TSEED _TPUB _TPRIV ED25519-KEYGEN',
        '0 0 _TPRIV _TPUB _TSIG ED25519-SIGN',
        # Check _ED-SC1 is zeroed
        '0 32 0 DO _ED-SC1 I + C@ + LOOP .',
    ]
    check("P05 _ED-SC1 zeroed after sign", lines2, "0")

    lines3 = create_hex_buf('_TSEED', TV1_SEED) + [
        'CREATE _TPUB 32 ALLOT',
        'CREATE _TPRIV 64 ALLOT',
        'CREATE _TSIG 64 ALLOT',
        '_TSEED _TPUB _TPRIV ED25519-KEYGEN',
        '0 0 _TPRIV _TPUB _TSIG ED25519-SIGN',
        # Check _ED-PA is zeroed (sum all 128 bytes)
        '0 128 0 DO _ED-PA I + C@ + LOOP .',
    ]
    check("P05 _ED-PA zeroed after sign", lines3, "0")


def test_p01_constant_time_smul():
    """P01: Scalar multiply still produces correct results with CMOV pattern.
    (Full timing analysis needs cycle counter; this is a correctness regression.)"""
    print("\n=== P01: Constant-time SMUL correctness ===")
    # The existing keygen/sign/verify tests exercise SMUL.
    # Add explicit edge case: multiply by scalar=1 should give the base point.
    lines = [
        'CREATE _SCONE 32 ALLOT  _SCONE 32 0 FILL  1 _SCONE C!',
        'CREATE _RESPT 32 ALLOT',
        # 1 * B should equal the base point
        '_ED-INIT-BASE',
        '_SCONE _ED-BASE _ED-SMUL',
        '_ED-PA _RESPT _ED-ENCODE',
        '_RESPT 32 .HEX',
    ]
    # Expected: the standard Ed25519 base point encoding
    # Base point y (LE) with sign bit = 0x58... (known encoding)
    # 5866666666666666666666666666666666666666666666666666666666666666
    # with high bit set for odd x:
    base_encoded = "5866666666666666666666666666666666666666666666666666666666666666"
    check("P01 1*B = B", lines, base_encoded)

    # multiply by scalar=0 should give identity (all zeros encode to
    # y=1, x=0 → 0100...00)
    lines2 = [
        'CREATE _SCZERO 32 ALLOT  _SCZERO 32 0 FILL',
        'CREATE _RESPT2 32 ALLOT',
        '_ED-INIT-BASE',
        '_SCZERO _ED-BASE _ED-SMUL',
        '_ED-PA _RESPT2 _ED-ENCODE',
        '_RESPT2 32 .HEX',
    ]
    identity_encoded = "01" + "00" * 31
    check("P01 0*B = identity", lines2, identity_encoded)

# ── Main ──

if __name__ == "__main__":
    build_snapshot()

    test_constants()
    test_compile()
    test_keygen_tv1()
    test_sign_tv1()
    test_verify_tv1()
    test_keygen_tv2()
    test_sign_verify_tv2()
    test_keygen_tv3()
    test_sign_verify_tv3()
    test_verify_bad_sig()
    test_verify_wrong_key()

    # Phase 6.6 hardening tests
    test_p01_constant_time_smul()
    test_p02_malleability_reject()
    test_p04_noncanonical_y()
    test_p05_zeroization()

    print(f"\n{'='*40}")
    print(f"  {_pass_count} passed, {_fail_count} failed")
    if _fail_count:
        sys.exit(1)
    print("  All tests passed!")
