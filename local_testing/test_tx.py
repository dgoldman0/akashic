#!/usr/bin/env python3
"""Test suite for Akashic tx.f (akashic/store/tx.f).

Tests transaction init, setters/getters, hashing, Ed25519 signing &
verification, CBOR encode/decode round-trip, structural validation,
and hash comparison.

SPHINCS+ signing/verification tests are included but are much slower
(~200M steps per sign).  Run with --quick to skip PQ tests.
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
TX_F       = os.path.join(ROOT_DIR, "akashic", "store", "tx.f")

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
    print("[*] Building snapshot: BIOS + KDOS + all tx.f dependencies ...")
    t0 = time.time()
    bios_code   = _load_bios()
    kdos_lines  = _load_forth_lines(KDOS_PATH)

    # Load all deps in correct topological order
    dep_lines = []
    for path in [EVENT_F, SEM_F, GUARD_F, FP16_F,
                 SHA512_F, FIELD_F, SHA3_F, RANDOM_F,
                 ED25519_F, SPHINCS_F, CBOR_F, FMT_F, TX_F]:
        dep_lines += _load_forth_lines(path)

    helpers = [
        'CREATE _TB 512 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        ': .HEX  ( addr n -- ) FMT-.HEX ;',  # alias to fmt.f
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
        print(f"  Aborting — tx.f failed to compile cleanly.")
        # Print last 30 lines for context
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

# ── Test vector keys (from RFC 8032 TV1) ──

TV1_SEED = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
TV1_PUB  = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"

TV2_SEED = "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
TV2_PUB  = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"

# ── Common Forth preamble: create two keypairs and a tx buffer ──

def _keygen_preamble():
    """Return Forth lines that create SEED1/PUB1/PRIV1, SEED2/PUB2/PRIV2, and TX1."""
    lines = create_hex_buf('_SEED1', TV1_SEED) + [
        'CREATE _PUB1 32 ALLOT',
        'CREATE _PRIV1 64 ALLOT',
        '_SEED1 _PUB1 _PRIV1 ED25519-KEYGEN',
    ] + create_hex_buf('_SEED2', TV2_SEED) + [
        'CREATE _PUB2 32 ALLOT',
        'CREATE _PRIV2 64 ALLOT',
        '_SEED2 _PUB2 _PRIV2 ED25519-KEYGEN',
        f'CREATE _TX1 {8296} ALLOT',
        '_TX1 TX-INIT',
    ]
    return lines

# ── Tests ──

def test_constants():
    print("\n=== Constants ===")
    check("TX-BUF-SIZE",    ['TX-BUF-SIZE .'],    "8296")
    check("TX-SIG-ED25519", ['TX-SIG-ED25519 .'], "0")
    check("TX-SIG-SPHINCS", ['TX-SIG-SPHINCS .'], "1")
    check("TX-SIG-HYBRID",  ['TX-SIG-HYBRID .'],  "2")
    check("TX-MAX-DATA",    ['TX-MAX-DATA .'],     "256")

def test_compile():
    """Verify module loaded cleanly."""
    print("\n=== Compile check ===")
    check("Module loaded", ['1 2 + .'], "3")

def test_init():
    """TX-INIT zeros the buffer."""
    print("\n=== TX-INIT ===")
    lines = [
        f'CREATE _TX1 {8296} ALLOT',
        # Put some junk in the buffer first
        '255 _TX1 C!  255 _TX1 100 + C!',
        '_TX1 TX-INIT',
        '_TX1 C@ . _TX1 100 + C@ .',
    ]
    check("TX-INIT zeroes buffer", lines, "0 0")

def test_setters_getters():
    """Set and read back all fields."""
    print("\n=== Setters/Getters ===")
    lines = _keygen_preamble() + [
        # Set from (sender = PUB1)
        '_PUB1 _TX1 TX-SET-FROM',
        # Set to (recipient = PUB2)
        '_PUB2 _TX1 TX-SET-TO',
        # Set amount
        '1000 _TX1 TX-SET-AMOUNT',
        # Set nonce
        '42 _TX1 TX-SET-NONCE',
        # Read back
        '_TX1 TX-AMOUNT@ . _TX1 TX-NONCE@ .',
    ]
    check("amount and nonce", lines, "1000 42")

    # Check from key matches
    lines2 = _keygen_preamble() + [
        '_PUB1 _TX1 TX-SET-FROM',
        '_TX1 TX-FROM@ 8 .HEX',
    ]
    check_fn("from key set", lines2,
             lambda out: TV1_PUB[:16] in out,
             "first 8 bytes of from key")

    # Check to key matches
    lines3 = _keygen_preamble() + [
        '_PUB2 _TX1 TX-SET-TO',
        '_TX1 TX-TO@ 8 .HEX',
    ]
    check_fn("to key set", lines3,
             lambda out: TV2_PUB[:16] in out,
             "first 8 bytes of to key")

def test_set_data():
    """Set and retrieve data payload."""
    print("\n=== TX-SET-DATA ===")
    lines = _keygen_preamble() + [
        'CREATE _DTEST 4 ALLOT',
        '0xDE _DTEST C!  0xAD _DTEST 1+ C!  0xBE _DTEST 2 + C!  0xEF _DTEST 3 + C!',
        '_DTEST 4 _TX1 TX-SET-DATA',
        '_TX1 TX-DATA-LEN@ .',
        '_TX1 TX-DATA@ 4 .HEX',
    ]
    check("data len", lines, "4")
    check_fn("data content", _keygen_preamble() + [
        'CREATE _DTEST 4 ALLOT',
        '0xDE _DTEST C!  0xAD _DTEST 1+ C!  0xBE _DTEST 2 + C!  0xEF _DTEST 3 + C!',
        '_DTEST 4 _TX1 TX-SET-DATA',
        '_TX1 TX-DATA@ 4 .HEX',
    ], lambda out: "deadbeef" in out, "data = deadbeef")

def test_hash_deterministic():
    """Same tx fields produce the same hash."""
    print("\n=== TX-HASH deterministic ===")
    lines = _keygen_preamble() + [
        '_PUB1 _TX1 TX-SET-FROM',
        '_PUB2 _TX1 TX-SET-TO',
        '500 _TX1 TX-SET-AMOUNT',
        '1 _TX1 TX-SET-NONCE',
        'CREATE _H1 32 ALLOT  CREATE _H2 32 ALLOT',
        '_TX1 _H1 TX-HASH',
        '_TX1 _H2 TX-HASH',
        '_H1 _H2 SHA3-256-COMPARE .',
    ]
    check("same hash twice", lines, "-1")

def test_hash_differs():
    """Different amount produces different hash."""
    print("\n=== TX-HASH differs ===")
    lines = _keygen_preamble() + [
        f'CREATE _TX2 {8296} ALLOT  _TX2 TX-INIT',
        # TX1: amount=500
        '_PUB1 _TX1 TX-SET-FROM',
        '_PUB2 _TX1 TX-SET-TO',
        '500 _TX1 TX-SET-AMOUNT',
        '1 _TX1 TX-SET-NONCE',
        # TX2: amount=501, everything else same
        '_PUB1 _TX2 TX-SET-FROM',
        '_PUB2 _TX2 TX-SET-TO',
        '501 _TX2 TX-SET-AMOUNT',
        '1 _TX2 TX-SET-NONCE',
        'CREATE _H1 32 ALLOT  CREATE _H2 32 ALLOT',
        '_TX1 _H1 TX-HASH',
        '_TX2 _H2 TX-HASH',
        '_H1 _H2 SHA3-256-COMPARE .',
    ]
    check("different amount => different hash", lines, "0")

def test_hash_equals():
    """TX-HASH= compares two identical txs."""
    print("\n=== TX-HASH= ===")
    lines = _keygen_preamble() + [
        f'CREATE _TX2 {8296} ALLOT  _TX2 TX-INIT',
        '_PUB1 _TX1 TX-SET-FROM  _PUB2 _TX1 TX-SET-TO',
        '100 _TX1 TX-SET-AMOUNT  0 _TX1 TX-SET-NONCE',
        '_PUB1 _TX2 TX-SET-FROM  _PUB2 _TX2 TX-SET-TO',
        '100 _TX2 TX-SET-AMOUNT  0 _TX2 TX-SET-NONCE',
        '_TX1 _TX2 TX-HASH= .',
    ]
    check("TX-HASH= same", lines, "-1")

    lines2 = _keygen_preamble() + [
        f'CREATE _TX2 {8296} ALLOT  _TX2 TX-INIT',
        '_PUB1 _TX1 TX-SET-FROM  _PUB2 _TX1 TX-SET-TO',
        '100 _TX1 TX-SET-AMOUNT  0 _TX1 TX-SET-NONCE',
        '_PUB1 _TX2 TX-SET-FROM  _PUB2 _TX2 TX-SET-TO',
        '999 _TX2 TX-SET-AMOUNT  0 _TX2 TX-SET-NONCE',
        '_TX1 _TX2 TX-HASH= .',
    ]
    check("TX-HASH= different", lines2, "0")

def test_sign_verify_ed25519():
    """Sign with Ed25519, then verify."""
    print("\n=== TX-SIGN + TX-VERIFY (Ed25519) ===")
    lines = _keygen_preamble() + [
        '_PUB1 _TX1 TX-SET-FROM',
        '_PUB2 _TX1 TX-SET-TO',
        '1000 _TX1 TX-SET-AMOUNT',
        '1 _TX1 TX-SET-NONCE',
        '_TX1 _PRIV1 _PUB1 TX-SIGN',
        '_TX1 TX-SIG-MODE@ .',
    ]
    check("sig_mode = 0 (Ed25519)", lines, "0")

    lines2 = _keygen_preamble() + [
        '_PUB1 _TX1 TX-SET-FROM',
        '_PUB2 _TX1 TX-SET-TO',
        '1000 _TX1 TX-SET-AMOUNT',
        '1 _TX1 TX-SET-NONCE',
        '_TX1 _PRIV1 _PUB1 TX-SIGN',
        '_TX1 TX-VERIFY .',
    ]
    check("TX-VERIFY after Ed25519 sign", lines2, "-1")

def test_verify_bad_ed25519():
    """Corrupted Ed25519 sig fails verification."""
    print("\n=== TX-VERIFY reject bad Ed25519 sig ===")
    lines = _keygen_preamble() + [
        '_PUB1 _TX1 TX-SET-FROM',
        '_PUB2 _TX1 TX-SET-TO',
        '1000 _TX1 TX-SET-AMOUNT',
        '1 _TX1 TX-SET-NONCE',
        '_TX1 _PRIV1 _PUB1 TX-SIGN',
        # Corrupt one byte in the sig field (offset 370)
        '_TX1 370 + DUP C@ 1 XOR SWAP C!',
        '_TX1 TX-VERIFY .',
    ]
    check("reject corrupted Ed25519 sig", lines, "0")

def test_verify_wrong_key():
    """Sign with key1 but FROM is set to key2 — fails."""
    print("\n=== TX-VERIFY reject wrong key ===")
    lines = _keygen_preamble() + [
        # Set FROM to PUB2 but sign with PRIV1/PUB1
        '_PUB2 _TX1 TX-SET-FROM',
        '_PUB1 _TX1 TX-SET-TO',
        '1000 _TX1 TX-SET-AMOUNT',
        '0 _TX1 TX-SET-NONCE',
        '_TX1 _PRIV1 _PUB1 TX-SIGN',
        '_TX1 TX-VERIFY .',
    ]
    check("reject wrong signer key", lines, "0")

def test_verify_tampered_amount():
    """Sign tx, then change amount — hash changes, sig invalid."""
    print("\n=== TX-VERIFY reject tampered amount ===")
    lines = _keygen_preamble() + [
        '_PUB1 _TX1 TX-SET-FROM',
        '_PUB2 _TX1 TX-SET-TO',
        '1000 _TX1 TX-SET-AMOUNT',
        '0 _TX1 TX-SET-NONCE',
        '_TX1 _PRIV1 _PUB1 TX-SIGN',
        # Tamper with amount after signing
        '9999 _TX1 TX-SET-AMOUNT',
        '_TX1 TX-VERIFY .',
    ]
    check("reject tampered amount", lines, "0")

def test_valid_check():
    """TX-VALID? structural checks."""
    print("\n=== TX-VALID? ===")
    # Empty (zeroed) tx should fail — from key is all-zero
    lines = [
        f'CREATE _TX1 {8296} ALLOT  _TX1 TX-INIT',
        '_TX1 TX-VALID? .',
    ]
    check("zeroed tx invalid", lines, "0")

    # Properly set tx should pass
    lines2 = _keygen_preamble() + [
        '_PUB1 _TX1 TX-SET-FROM',
        '_PUB2 _TX1 TX-SET-TO',
        '100 _TX1 TX-SET-AMOUNT',
        '0 _TX1 TX-SET-NONCE',
        '_TX1 TX-VALID? .',
    ]
    check("valid tx struct", lines2, "-1")

def test_encode_decode_roundtrip():
    """Encode to CBOR, decode back, compare fields."""
    print("\n=== TX-ENCODE / TX-DECODE round-trip ===")
    lines = _keygen_preamble() + [
        '_PUB1 _TX1 TX-SET-FROM',
        '_PUB2 _TX1 TX-SET-TO',
        '777 _TX1 TX-SET-AMOUNT',
        '5 _TX1 TX-SET-NONCE',
        # Sign it (Ed25519)
        '_TX1 _PRIV1 _PUB1 TX-SIGN',
        # Encode
        'CREATE _CBUF 16384 ALLOT',
        '_TX1 _CBUF 16384 TX-ENCODE',   # -- len
        # Decode into a fresh tx
        f'CREATE _TX2 {8296} ALLOT',
        'DUP _CBUF SWAP _TX2 TX-DECODE .',  # -- len; print decode flag
        # Compare fields
        '_TX2 TX-AMOUNT@ .',
        '_TX2 TX-NONCE@ .',
        '_TX2 TX-SIG-MODE@ .',
    ]
    check("decode flag", lines, "-1")
    check_fn("roundtrip fields", _keygen_preamble() + [
        '_PUB1 _TX1 TX-SET-FROM',
        '_PUB2 _TX1 TX-SET-TO',
        '777 _TX1 TX-SET-AMOUNT',
        '5 _TX1 TX-SET-NONCE',
        '_TX1 _PRIV1 _PUB1 TX-SIGN',
        'CREATE _CBUF 16384 ALLOT',
        '_TX1 _CBUF 16384 TX-ENCODE',
        f'CREATE _TX2 {8296} ALLOT',
        '_CBUF SWAP _TX2 TX-DECODE DROP',
        '_TX2 TX-AMOUNT@ .',
        '_TX2 TX-NONCE@ .',
    ], lambda out: "777" in out and "5" in out.split("777")[-1],
       "amount=777 nonce=5 after roundtrip")

def test_encode_decode_verify():
    """Encode signed tx, decode it, verify signature on decoded copy."""
    print("\n=== Encode → Decode → Verify ===")
    lines = _keygen_preamble() + [
        '_PUB1 _TX1 TX-SET-FROM',
        '_PUB2 _TX1 TX-SET-TO',
        '500 _TX1 TX-SET-AMOUNT',
        '3 _TX1 TX-SET-NONCE',
        '_TX1 _PRIV1 _PUB1 TX-SIGN',
        'CREATE _CBUF 16384 ALLOT',
        '_TX1 _CBUF 16384 TX-ENCODE',
        f'CREATE _TX2 {8296} ALLOT',
        '_CBUF SWAP _TX2 TX-DECODE DROP',
        '_TX2 TX-VERIFY .',
    ]
    check("verify after decode", lines, "-1")

def test_encode_size():
    """Check encoded size is reasonable for Ed25519-only tx."""
    print("\n=== TX-ENCODE size ===")
    lines = _keygen_preamble() + [
        '_PUB1 _TX1 TX-SET-FROM',
        '_PUB2 _TX1 TX-SET-TO',
        '100 _TX1 TX-SET-AMOUNT',
        '0 _TX1 TX-SET-NONCE',
        '_TX1 _PRIV1 _PUB1 TX-SIGN',
        'CREATE _CBUF 16384 ALLOT',
        '_TX1 _CBUF 16384 TX-ENCODE .',
    ]
    # Ed25519-only tx with no data: ~200-500 bytes
    check_fn("encoded size reasonable", lines,
             lambda out: any(100 < int(w) < 600
                            for w in out.strip().split()
                            if w.lstrip('-').isdigit()),
             "size between 100-600 bytes")

def test_data_roundtrip():
    """Data payload survives encode/decode."""
    print("\n=== Data payload round-trip ===")
    lines = _keygen_preamble() + [
        'CREATE _DTEST 4 ALLOT',
        '0xCA _DTEST C!  0xFE _DTEST 1+ C!  0xBA _DTEST 2 + C!  0xBE _DTEST 3 + C!',
        '_PUB1 _TX1 TX-SET-FROM',
        '_PUB2 _TX1 TX-SET-TO',
        '100 _TX1 TX-SET-AMOUNT',
        '0 _TX1 TX-SET-NONCE',
        '_DTEST 4 _TX1 TX-SET-DATA',
        '_TX1 _PRIV1 _PUB1 TX-SIGN',
        'CREATE _CBUF 16384 ALLOT',
        '_TX1 _CBUF 16384 TX-ENCODE',
        f'CREATE _TX2 {8296} ALLOT',
        '_CBUF SWAP _TX2 TX-DECODE DROP',
        '_TX2 TX-DATA-LEN@ .',
        '_TX2 TX-DATA@ 4 .HEX',
    ]
    check_fn("data preserved", lines,
             lambda out: "cafebabe" in out and "4" in out,
             "data len=4, content=cafebabe")

def test_tx_print():
    """TX-PRINT doesn't crash."""
    print("\n=== TX-PRINT ===")
    lines = _keygen_preamble() + [
        '_PUB1 _TX1 TX-SET-FROM',
        '_PUB2 _TX1 TX-SET-TO',
        '1000 _TX1 TX-SET-AMOUNT',
        '7 _TX1 TX-SET-NONCE',
        '_TX1 _PRIV1 _PUB1 TX-SIGN',
        '_TX1 TX-PRINT',
        '." DONE"',
    ]
    check("TX-PRINT runs", lines, "DONE")

# ── SPHINCS+ tests (slow — skipped with --quick) ──

def test_sign_verify_sphincs():
    """Sign with SPHINCS+, verify."""
    print("\n=== TX-SIGN-PQ + TX-VERIFY (SPHINCS+) ===")
    lines = _keygen_preamble() + [
        # Generate SPHINCS+ keypair from a deterministic seed
        'CREATE _SPXSEED 48 ALLOT',
        '1 _SPXSEED !  2 _SPXSEED 8 + !  3 _SPXSEED 16 + !',
        '4 _SPXSEED 24 + !  5 _SPXSEED 32 + !  6 _SPXSEED 40 + !',
        'CREATE _SPXPUB 32 ALLOT',
        'CREATE _SPXSEC 64 ALLOT',
        # Use deterministic signing for reproducibility
        '1 SPX-SIGN-MODE !',
        '_SPXSEED _SPXPUB _SPXSEC SPX-KEYGEN',
        # Build tx
        '_PUB1 _TX1 TX-SET-FROM',
        '_SPXPUB _TX1 TX-SET-FROM-PQ',
        '_PUB2 _TX1 TX-SET-TO',
        '500 _TX1 TX-SET-AMOUNT',
        '0 _TX1 TX-SET-NONCE',
        # Sign with SPHINCS+
        '_TX1 _SPXSEC TX-SIGN-PQ',
        '_TX1 TX-SIG-MODE@ .',
        '_TX1 TX-VERIFY .',
    ]
    check_fn("SPX sign+verify", lines,
             lambda out: "1" in out and "-1" in out,
             "sig_mode=1 and verify=TRUE")

# ── Main ──

if __name__ == "__main__":
    quick = "--quick" in sys.argv

    build_snapshot()

    test_constants()
    test_compile()
    test_init()
    test_setters_getters()
    test_set_data()
    test_hash_deterministic()
    test_hash_differs()
    test_hash_equals()
    test_sign_verify_ed25519()
    test_verify_bad_ed25519()
    test_verify_wrong_key()
    test_verify_tampered_amount()
    test_valid_check()
    test_encode_decode_roundtrip()
    test_encode_decode_verify()
    test_encode_size()
    test_data_roundtrip()
    test_tx_print()

    if not quick:
        print("\n" + "="*40)
        print("  SPHINCS+ tests (slow) ...")
        print("="*40)
        test_sign_verify_sphincs()
    else:
        print("\n  [SKIP] SPHINCS+ tests (--quick)")

    print(f"\n{'='*40}")
    print(f"  {_pass_count} passed, {_fail_count} failed")
    if _fail_count:
        sys.exit(1)
    print("  All tests passed!")
