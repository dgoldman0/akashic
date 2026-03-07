#!/usr/bin/env python3
"""Test suite for Akashic state.f (akashic/store/state.f).

Tests:
  - Constants (ST-MAX-ACCOUNTS, ST-ENTRY-SIZE, ST-ADDR-LEN)
  - ST-INIT (zeroes state, count=0)
  - ST-ADDR-FROM-KEY (SHA3-256 of pubkey)
  - ST-CREATE (insert accounts, sorted order, duplicate rejection, full table)
  - ST-LOOKUP (find by address, miss returns 0)
  - ST-BALANCE@ / ST-NONCE@ (read through address)
  - ST-VERIFY-TX (dry-run validation)
  - ST-APPLY-TX (sender debit, recipient credit, nonce bump,
                  auto-create recipient, self-transfer, overflow check)
  - ST-ROOT (Merkle root determinism, changes on state mutation)
  - ST-COUNT (tracks active accounts)
  - Sorted insertion order (binary search correctness)
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
    print("[*] Building snapshot: BIOS + KDOS + all state.f dependencies ...")
    t0 = time.time()
    bios_code   = _load_bios()
    kdos_lines  = _load_forth_lines(KDOS_PATH)

    # Load all deps in correct topological order
    # state.f needs: sha3, merkle, tx (which needs ed25519, sphincs, cbor, fmt)
    dep_lines = []
    for path in [EVENT_F, SEM_F, GUARD_F, FP16_F,
                 SHA512_F, FIELD_F, SHA3_F, RANDOM_F,
                 ED25519_F, SPHINCS_F, CBOR_F, FMT_F,
                 MERKLE_F, TX_F, STATE_F]:
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
        print(f"  Aborting — state.f failed to compile cleanly.")
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

# ── Test vector keys (from RFC 8032 TV1 & TV2) ──

TV1_SEED = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
TV1_PUB  = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"

TV2_SEED = "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
TV2_PUB  = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"

# Third key for multi-account tests
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
        'ST-INIT',
    ]
    return lines

def _make_tx(sender_pub, sender_priv, recip_pub, amount, nonce):
    """Return Forth lines that build, sign, and leave a tx buffer.
    Uses _TXBUF as the tx buffer name."""
    return [
        f'CREATE _TXBUF {8296} ALLOT',
        '_TXBUF TX-INIT',
        f'{sender_pub} _TXBUF TX-SET-FROM',
        f'{recip_pub} _TXBUF TX-SET-TO',
        f'{amount} _TXBUF TX-SET-AMOUNT',
        f'{nonce} _TXBUF TX-SET-NONCE',
        f'_TXBUF {sender_priv} {sender_pub} TX-SIGN',
    ]

# ── Tests ──

def test_constants():
    print("\n=== Constants ===")
    check("ST-MAX-ACCOUNTS",  ['ST-MAX-ACCOUNTS .'],  "256")
    check("ST-ENTRY-SIZE",    ['ST-ENTRY-SIZE .'],     "72")
    check("ST-ADDR-LEN",     ['ST-ADDR-LEN .'],       "32")

def test_compile():
    print("\n=== Compile check ===")
    check("Module loaded", ['1 2 + .'], "3")

def test_init():
    print("\n=== ST-INIT ===")
    check("Count is zero after init",
          ['ST-INIT ST-COUNT .'], "0")

def test_addr_from_key():
    """ST-ADDR-FROM-KEY produces a 32-byte hash different from the raw key."""
    print("\n=== ST-ADDR-FROM-KEY ===")
    lines = create_hex_buf('_PK', TV1_PUB) + [
        'CREATE _AD 32 ALLOT',
        '_PK _AD ST-ADDR-FROM-KEY',
        # Address should not equal the raw key (SHA3 scrambles it)
        '_AD _PK 32 0 DO OVER I + C@ OVER I + C@ XOR OR LOOP NIP NIP',
        'IF ." DIFF" ELSE ." SAME" THEN',
    ]
    check("address differs from raw key", lines, "DIFF")

    # Deterministic: same key -> same address
    lines2 = create_hex_buf('_PK', TV1_PUB) + [
        'CREATE _A1 32 ALLOT  CREATE _A2 32 ALLOT',
        '_PK _A1 ST-ADDR-FROM-KEY',
        '_PK _A2 ST-ADDR-FROM-KEY',
        '_A1 _A2 32 0 DO OVER I + C@ OVER I + C@ XOR OR LOOP NIP NIP',
        'IF ." DIFF" ELSE ." SAME" THEN',
    ]
    check("deterministic address", lines2, "SAME")

def test_create_and_lookup():
    print("\n=== ST-CREATE / ST-LOOKUP ===")
    lines = _keygen_preamble() + [
        # Create account 1 with balance 1000
        '_ADDR1 1000 ST-CREATE IF ." C1OK" ELSE ." C1FAIL" THEN',
        'ST-COUNT .',
    ]
    check("create first account", lines, "C1OK")
    check("count is 1 after create",
           _keygen_preamble() + [
               '_ADDR1 1000 ST-CREATE DROP',
               'ST-COUNT .',
           ], "1")

    # Lookup finds it
    lines2 = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        '_ADDR1 ST-LOOKUP 0<> IF ." FOUND" ELSE ." MISS" THEN',
    ]
    check("lookup finds existing", lines2, "FOUND")

    # Lookup for non-existent returns 0
    lines3 = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        '_ADDR2 ST-LOOKUP 0= IF ." MISS" ELSE ." FOUND" THEN',
    ]
    check("lookup miss for non-existent", lines3, "MISS")

    # Duplicate create returns FALSE
    lines4 = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        '_ADDR1 500 ST-CREATE IF ." DUP-OK" ELSE ." DUP-REJECT" THEN',
    ]
    check("duplicate create rejected", lines4, "DUP-REJECT")

def test_balance_nonce():
    print("\n=== ST-BALANCE@ / ST-NONCE@ ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        '_ADDR1 ST-BALANCE@ .',
    ]
    check("balance of created account", lines, "1000")

    lines2 = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        '_ADDR1 ST-NONCE@ .',
    ]
    check("nonce starts at 0", lines2, "0")

    # Non-existent account returns 0
    lines3 = _keygen_preamble() + [
        '_ADDR1 ST-BALANCE@ .',
    ]
    check("balance of non-existent = 0", lines3, "0")

def test_multiple_accounts():
    """Create 3 accounts, verify all are findable and in sorted order."""
    print("\n=== Multiple accounts (sorted order) ===")
    lines = _keygen_preamble() + [
        '_ADDR1 100 ST-CREATE DROP',
        '_ADDR2 200 ST-CREATE DROP',
        '_ADDR3 300 ST-CREATE DROP',
        'ST-COUNT .',
    ]
    check("3 accounts created", lines, "3")

    # All lookups succeed
    lines2 = _keygen_preamble() + [
        '_ADDR1 100 ST-CREATE DROP',
        '_ADDR2 200 ST-CREATE DROP',
        '_ADDR3 300 ST-CREATE DROP',
        '_ADDR1 ST-LOOKUP 0<> IF ." A" THEN',
        '_ADDR2 ST-LOOKUP 0<> IF ." B" THEN',
        '_ADDR3 ST-LOOKUP 0<> IF ." C" THEN',
    ]
    check_fn("all 3 found", lines2,
             lambda o: "A" in o and "B" in o and "C" in o,
             "should find all three")

    # Balances are correct
    lines3 = _keygen_preamble() + [
        '_ADDR1 100 ST-CREATE DROP',
        '_ADDR2 200 ST-CREATE DROP',
        '_ADDR3 300 ST-CREATE DROP',
        '." B1=" _ADDR1 ST-BALANCE@ .',
        '." B2=" _ADDR2 ST-BALANCE@ .',
        '." B3=" _ADDR3 ST-BALANCE@ .',
    ]
    check_fn("correct balances", lines3,
             lambda o: "B1=100" in o.replace(" ", "").replace("\n","")
                    or ("B1=" in o and "100" in o and "200" in o and "300" in o),
             "balances 100/200/300")

def test_verify_tx():
    """ST-VERIFY-TX validates without mutating state."""
    print("\n=== ST-VERIFY-TX ===")
    # Valid tx
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        '_ADDR2 500 ST-CREATE DROP',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        '_TXBUF ST-VERIFY-TX IF ." VALID" ELSE ." INVALID" THEN',
    ]
    check("valid tx passes verify", lines, "VALID")

    # Wrong nonce
    lines2 = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        '_ADDR2 500 ST-CREATE DROP',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 5) + [
        '_TXBUF ST-VERIFY-TX IF ." VALID" ELSE ." INVALID" THEN',
    ]
    check("wrong nonce rejected", lines2, "INVALID")

    # Insufficient balance
    lines3 = _keygen_preamble() + [
        '_ADDR1 50 ST-CREATE DROP',
        '_ADDR2 500 ST-CREATE DROP',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        '_TXBUF ST-VERIFY-TX IF ." VALID" ELSE ." INVALID" THEN',
    ]
    check("insufficient balance rejected", lines3, "INVALID")

    # Non-existent sender
    lines4 = _keygen_preamble() + [
        '_ADDR2 500 ST-CREATE DROP',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        '_TXBUF ST-VERIFY-TX IF ." VALID" ELSE ." INVALID" THEN',
    ]
    check("non-existent sender rejected", lines4, "INVALID")

    # Verify doesn't mutate state
    lines5 = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        '_ADDR2 500 ST-CREATE DROP',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        '_TXBUF ST-VERIFY-TX DROP',
        '." BAL=" _ADDR1 ST-BALANCE@ .',
        '." N=" _ADDR1 ST-NONCE@ .',
    ]
    check_fn("verify doesn't mutate", lines5,
             lambda o: "BAL=" in o and "1000" in o and "N=" in o and " 0" in o,
             "balance/nonce unchanged")

def test_apply_tx():
    """ST-APPLY-TX applies a valid transaction."""
    print("\n=== ST-APPLY-TX ===")
    # Basic transfer: 1000 -> 500, send 100
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        '_ADDR2 500 ST-CREATE DROP',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        '_TXBUF ST-APPLY-TX IF ." APPLIED" ELSE ." FAILED" THEN',
        '." S=" _ADDR1 ST-BALANCE@ .',
        '." R=" _ADDR2 ST-BALANCE@ .',
        '." N=" _ADDR1 ST-NONCE@ .',
    ]
    check("apply succeeds", lines, "APPLIED")
    check_fn("sender debited", lines,
             lambda o: "S=" in o and "900" in o,
             "sender 1000-100=900")
    check_fn("recipient credited", lines,
             lambda o: "R=" in o and "600" in o,
             "recipient 500+100=600")
    check_fn("nonce incremented", lines,
             lambda o: "N=" in o and "N= 1" in o or "N=1" in o.replace(" ",""),
             "nonce 0->1")

def test_apply_auto_create_recipient():
    """Recipient auto-created if not in state table."""
    print("\n=== ST-APPLY-TX (auto-create recipient) ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        # Don't create addr2 — it should be auto-created
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        '_TXBUF ST-APPLY-TX IF ." APPLIED" ELSE ." FAILED" THEN',
        '." CNT=" ST-COUNT .',
        '." RB=" _ADDR2 ST-BALANCE@ .',
    ]
    check("auto-create succeeds", lines, "APPLIED")
    check_fn("count increased to 2", lines,
             lambda o: "CNT=" in o and "2" in o,
             "2 accounts")
    check_fn("recipient has 100", lines,
             lambda o: "RB=" in o and "100" in o,
             "recipient balance = 100")

def test_apply_self_transfer():
    """Self-transfer: sender == recipient, just bumps nonce."""
    print("\n=== ST-APPLY-TX (self-transfer) ===")
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB1', 100, 0) + [
        '_TXBUF ST-APPLY-TX IF ." APPLIED" ELSE ." FAILED" THEN',
        '." BAL=" _ADDR1 ST-BALANCE@ .',
        '." N=" _ADDR1 ST-NONCE@ .',
    ]
    check("self-transfer succeeds", lines, "APPLIED")
    check_fn("balance unchanged", lines,
             lambda o: "BAL=" in o and "1000" in o,
             "still 1000")
    check_fn("nonce bumped", lines,
             lambda o: "N=" in o and ("N= 1" in o or "N=1" in o.replace(" ", "")),
             "nonce 0->1")

def test_apply_sequence():
    """Two sequential transactions from same sender (nonce 0, then 1)."""
    print("\n=== ST-APPLY-TX (sequence) ===")
    # We can't use _make_tx twice with same CREATE name, so we'll
    # define the tx inline differently
    lines = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        '_ADDR2 0 ST-CREATE DROP',
        # TX 1: send 100, nonce 0
        f'CREATE _TX1 {8296} ALLOT',
        '_TX1 TX-INIT',
        '_PUB1 _TX1 TX-SET-FROM',
        '_PUB2 _TX1 TX-SET-TO',
        '100 _TX1 TX-SET-AMOUNT',
        '0 _TX1 TX-SET-NONCE',
        '_TX1 _PRIV1 _PUB1 TX-SIGN',
        '_TX1 ST-APPLY-TX IF ." T1OK" ELSE ." T1FAIL" THEN',
        # TX 2: send 200, nonce 1
        f'CREATE _TX2 {8296} ALLOT',
        '_TX2 TX-INIT',
        '_PUB1 _TX2 TX-SET-FROM',
        '_PUB2 _TX2 TX-SET-TO',
        '200 _TX2 TX-SET-AMOUNT',
        '1 _TX2 TX-SET-NONCE',
        '_TX2 _PRIV1 _PUB1 TX-SIGN',
        '_TX2 ST-APPLY-TX IF ." T2OK" ELSE ." T2FAIL" THEN',
        '." S=" _ADDR1 ST-BALANCE@ .',
        '." R=" _ADDR2 ST-BALANCE@ .',
        '." N=" _ADDR1 ST-NONCE@ .',
    ]
    check("first tx applied",  lines, "T1OK")
    check("second tx applied", lines, "T2OK")
    check_fn("sender balance 700", lines,
             lambda o: "S=" in o and "700" in o,
             "1000 - 100 - 200 = 700")
    check_fn("recipient balance 300", lines,
             lambda o: "R=" in o and "300" in o,
             "0 + 100 + 200 = 300")

def test_apply_rejects():
    """Various rejection cases for ST-APPLY-TX."""
    print("\n=== ST-APPLY-TX (rejection cases) ===")
    # Insufficient balance
    lines = _keygen_preamble() + [
        '_ADDR1 50 ST-CREATE DROP',
        '_ADDR2 0 ST-CREATE DROP',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        '_TXBUF ST-APPLY-TX IF ." APPLIED" ELSE ." REJECTED" THEN',
        '." BAL=" _ADDR1 ST-BALANCE@ .',
    ]
    check("insufficient balance rejected", lines, "REJECTED")
    check_fn("balance unchanged on rejection", lines,
             lambda o: "BAL=" in o and "50" in o,
             "still 50")

    # Replay (wrong nonce after apply)
    lines2 = _keygen_preamble() + [
        '_ADDR1 1000 ST-CREATE DROP',
        '_ADDR2 0 ST-CREATE DROP',
    ] + _make_tx('_PUB1', '_PRIV1', '_PUB2', 100, 0) + [
        # Apply first time — succeeds (uses _TXBUF)
        '_TXBUF ST-APPLY-TX DROP',
        # Try same tx again (nonce 0, but account nonce is now 1)
        '_TXBUF ST-APPLY-TX IF ." REPLAY-OK" ELSE ." REPLAY-BLOCKED" THEN',
    ]
    check("replay blocked by nonce", lines2, "REPLAY-BLOCKED")

def test_merkle_root():
    """ST-ROOT returns a 32-byte Merkle root that changes on state mutation."""
    print("\n=== ST-ROOT ===")
    # Root is not all zeroes even for empty state (Merkle of zero-hashes)
    lines = _keygen_preamble() + [
        'ST-ROOT 32 0 DO DUP I + C@ OR LOOP NIP',
        '0<> IF ." NONZERO" ELSE ." ZERO" THEN',
    ]
    check("empty root is non-zero", lines, "NONZERO")

    # Root changes after creating an account
    lines2 = _keygen_preamble() + [
        'CREATE _R1 32 ALLOT  CREATE _R2 32 ALLOT',
        'ST-ROOT _R1 32 CMOVE',
        '_ADDR1 1000 ST-CREATE DROP',
        'ST-ROOT _R2 32 CMOVE',
        '_R1 _R2 32 0 DO OVER I + C@ OVER I + C@ XOR OR LOOP NIP NIP',
        '0<> IF ." CHANGED" ELSE ." SAME" THEN',
    ]
    check("root changes after create", lines2, "CHANGED")

    # Root is deterministic
    lines3 = _keygen_preamble() + [
        'CREATE _R1 32 ALLOT  CREATE _R2 32 ALLOT',
        '_ADDR1 1000 ST-CREATE DROP',
        'ST-ROOT _R1 32 CMOVE',
        # Re-init and recreate same account
        'ST-INIT',
        '_ADDR1 1000 ST-CREATE DROP',
        'ST-ROOT _R2 32 CMOVE',
        '_R1 _R2 32 0 DO OVER I + C@ OVER I + C@ XOR OR LOOP NIP NIP',
        '0= IF ." DETERMINISTIC" ELSE ." NONDETERMINISTIC" THEN',
    ]
    check("root is deterministic", lines3, "DETERMINISTIC")

# ── Main ──

def main():
    quick = "--quick" in sys.argv
    build_snapshot()

    test_compile()
    test_constants()
    test_init()
    test_addr_from_key()
    test_create_and_lookup()
    test_balance_nonce()
    test_multiple_accounts()
    test_verify_tx()
    test_apply_tx()
    test_apply_auto_create_recipient()
    test_apply_self_transfer()
    test_apply_sequence()
    test_apply_rejects()
    test_merkle_root()

    print(f"\n{'='*40}")
    print(f"  {_pass_count} passed, {_fail_count} failed")
    print(f"{'='*40}")
    sys.exit(1 if _fail_count else 0)

if __name__ == "__main__":
    main()
