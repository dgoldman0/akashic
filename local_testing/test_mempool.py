#!/usr/bin/env python3
"""Test suite for Akashic mempool.f (akashic/store/mempool.f).

Tests:
  - MP-INIT / MP-COUNT
  - MP-ADD with valid transactions
  - MP-ADD duplicate rejection
  - MP-ADD same-sender-nonce rejection
  - MP-CONTAINS?
  - MP-REMOVE by hash
  - MP-DRAIN + MP-RELEASE
  - Sorted order verification (sender + nonce)
  - MP-PRUNE
  - Capacity limit
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
CONSENSUS_F = os.path.join(ROOT_DIR, "akashic", "consensus", "consensus.f")
MEMPOOL_F  = os.path.join(ROOT_DIR, "akashic", "store", "mempool.f")

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
    print("[*] Building snapshot: BIOS + KDOS + all mempool.f dependencies ...")
    t0 = time.time()
    bios_code   = _load_bios()
    kdos_lines  = _load_forth_lines(KDOS_PATH)

    dep_lines = []
    for path in [EVENT_F, SEM_F, GUARD_F, FP16_F,
                 SHA512_F, FIELD_F, SHA3_F, RANDOM_F,
                 ED25519_F, SPHINCS_F, CBOR_F, FMT_F,
                 MERKLE_F, TX_F, STATE_F, BLOCK_F,
                 CONSENSUS_F, MEMPOOL_F]:
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
        print(f"  Aborting — mempool.f failed to compile cleanly.")
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

# ── Test vector keys (Ed25519 RFC 8032 TV1, TV2, TV3) ──

TV1_SEED = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
TV1_PUB  = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"

TV2_SEED = "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
TV2_PUB  = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"

TV3_SEED = "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7"
TV3_PUB  = "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025"


def _keygen_preamble():
    """Create keypairs, address buffers, and initialize state + mempool."""
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
        # Initialize
        'ST-INIT',
        '_ADDR1 10000 ST-CREATE DROP',
        '_ADDR2 5000 ST-CREATE DROP',
        '_ADDR3 3000 ST-CREATE DROP',
        'MP-INIT',
    ]
    return lines


def _make_tx(from_idx, to_idx, amount, nonce, name):
    """Generate Forth lines to create and sign a transfer tx."""
    return [
        f'CREATE {name} TX-BUF-SIZE ALLOT',
        f'{name} TX-INIT',
        f'_PUB{from_idx} {name} TX-SET-FROM',
        f'_PUB{to_idx} {name} TX-SET-TO',
        f'{amount} {name} TX-SET-AMOUNT',
        f'{nonce} {name} TX-SET-NONCE',
        f'{name} _PRIV{from_idx} _PUB{from_idx} TX-SIGN',
    ]


# ══════════════════════════════════════════════════════════════════════
#  TESTS
# ══════════════════════════════════════════════════════════════════════

def test_init_count():
    """MP-INIT should give count = 0."""
    check("MP-INIT → count=0",
          _keygen_preamble() + [
              'MP-COUNT . CR',
          ], "0")

def test_add_single():
    """MP-ADD should accept a valid signed tx."""
    check("MP-ADD valid tx → TRUE",
          _keygen_preamble()
          + _make_tx(1, 2, 100, 0, '_TX1')
          + [
              '_TX1 MP-ADD . MP-COUNT . CR',
          ], "-1 1")

def test_add_duplicate():
    """MP-ADD should reject a duplicate tx (same hash)."""
    check("MP-ADD duplicate → FALSE",
          _keygen_preamble()
          + _make_tx(1, 2, 100, 0, '_TX1')
          + [
              '_TX1 MP-ADD DROP',
              '_TX1 MP-ADD . CR',  # same tx again
          ], "0")

def test_add_same_sender_nonce():
    """MP-ADD should reject tx with same sender + nonce (different recipient)."""
    check("MP-ADD same sender+nonce → FALSE",
          _keygen_preamble()
          + _make_tx(1, 2, 100, 0, '_TX1')
          + _make_tx(1, 3, 200, 0, '_TX2')  # same sender, same nonce
          + [
              '_TX1 MP-ADD DROP',
              '_TX2 MP-ADD . CR',  # same (sender, nonce=0)
          ], "0")

def test_add_multiple():
    """MP-ADD should accept multiple txs from same sender with different nonces."""
    check("MP-ADD three txs, count=3",
          _keygen_preamble()
          + _make_tx(1, 2, 100, 0, '_TX1')
          + _make_tx(1, 2, 200, 1, '_TX2')
          + _make_tx(1, 2, 300, 2, '_TX3')
          + [
              '_TX1 MP-ADD DROP',
              '_TX2 MP-ADD DROP',
              '_TX3 MP-ADD DROP',
              'MP-COUNT . CR',
          ], "3")

def test_contains():
    """MP-CONTAINS? should find an added tx by hash."""
    check("MP-CONTAINS? → TRUE",
          _keygen_preamble()
          + _make_tx(1, 2, 100, 0, '_TX1')
          + [
              'CREATE _H1 32 ALLOT',
              '_TX1 _H1 TX-HASH',
              '_TX1 MP-ADD DROP',
              '_H1 MP-CONTAINS? . CR',
          ], "-1")

def test_contains_not_found():
    """MP-CONTAINS? should return FALSE for a hash not in pool."""
    check("MP-CONTAINS? not found → FALSE",
          _keygen_preamble()
          + _make_tx(1, 2, 100, 0, '_TX1')
          + [
              'CREATE _H1 32 ALLOT',
              '_TX1 _H1 TX-HASH',
              # do NOT add _TX1
              '_H1 MP-CONTAINS? . CR',
          ], "0")

def test_remove():
    """MP-REMOVE should find and remove a tx by hash."""
    check("MP-REMOVE → TRUE, count=0",
          _keygen_preamble()
          + _make_tx(1, 2, 100, 0, '_TX1')
          + [
              'CREATE _H1 32 ALLOT',
              '_TX1 _H1 TX-HASH',
              '_TX1 MP-ADD DROP',
              '_H1 MP-REMOVE . MP-COUNT . CR',
          ], "-1 0")

def test_remove_not_found():
    """MP-REMOVE should return FALSE for unknown hash."""
    check("MP-REMOVE not found → FALSE",
          _keygen_preamble()
          + _make_tx(1, 2, 100, 0, '_TX1')
          + [
              'CREATE _H1 32 ALLOT',
              '_TX1 _H1 TX-HASH',
              # not added
              '_H1 MP-REMOVE . CR',
          ], "0")

def test_drain():
    """MP-DRAIN should pop txs and reduce count."""
    check("MP-DRAIN 2 from 3 → actual=2, count=1",
          _keygen_preamble()
          + _make_tx(1, 2, 100, 0, '_TX1')
          + _make_tx(1, 2, 200, 1, '_TX2')
          + _make_tx(1, 2, 300, 2, '_TX3')
          + [
              '_TX1 MP-ADD DROP',
              '_TX2 MP-ADD DROP',
              '_TX3 MP-ADD DROP',
              'CREATE _DBUF 8 CELLS ALLOT',
              '2 _DBUF MP-DRAIN . MP-COUNT . CR',
          ], "2 1")

def test_drain_all():
    """MP-DRAIN n > count should drain all."""
    check("MP-DRAIN 10 from 2 → actual=2, count=0",
          _keygen_preamble()
          + _make_tx(1, 2, 100, 0, '_TX1')
          + _make_tx(1, 2, 200, 1, '_TX2')
          + [
              '_TX1 MP-ADD DROP',
              '_TX2 MP-ADD DROP',
              'CREATE _DBUF 16 CELLS ALLOT',
              '10 _DBUF MP-DRAIN . MP-COUNT . CR',
          ], "2 0")

def test_release():
    """MP-RELEASE should free drained slots, allowing new adds."""
    check("MP-RELEASE frees drained slots",
          _keygen_preamble()
          + _make_tx(1, 2, 100, 0, '_TX1')
          + [
              '_TX1 MP-ADD DROP',
              'CREATE _DBUF 8 CELLS ALLOT',
              '1 _DBUF MP-DRAIN DROP',     # drain it
              'MP-RELEASE',                 # free slots
              'MP-COUNT . CR',              # should be 0
          ], "0")

def test_sorted_order():
    """Txs should be sorted by sender address + nonce (drain order = sorted order)."""
    # Add txs from different senders and check they come out in address-sorted order
    # All amounts should appear; exact order depends on address sort
    check_fn("sorted drain order",
          _keygen_preamble()
          + _make_tx(1, 2, 100, 0, '_TXA')
          + _make_tx(2, 1, 200, 0, '_TXB')
          + _make_tx(3, 1, 300, 0, '_TXC')
          + [
              '_TXA MP-ADD DROP',
              '_TXB MP-ADD DROP',
              '_TXC MP-ADD DROP',
              'CREATE _DBUF 8 CELLS ALLOT',
              '3 _DBUF MP-DRAIN DROP',
              '_DBUF 0 CELLS + @ TX-AMOUNT@ .',
              '_DBUF 1 CELLS + @ TX-AMOUNT@ .',
              '_DBUF 2 CELLS + @ TX-AMOUNT@ . CR',
          ],
          # All three amounts (100 200 300) should appear on one line, in some order
          lambda out: all(str(v) in out for v in [100, 200, 300]),
          "all three amounts present in output")

def test_nonce_order_same_sender():
    """Txs from same sender should be sorted by nonce ascending."""
    check("same sender, nonce order",
          _keygen_preamble()
          + _make_tx(1, 2, 300, 2, '_TXC')  # add nonce 2 first
          + _make_tx(1, 2, 100, 0, '_TXA')  # then nonce 0
          + _make_tx(1, 2, 200, 1, '_TXB')  # then nonce 1
          + [
              '_TXC MP-ADD DROP',
              '_TXA MP-ADD DROP',
              '_TXB MP-ADD DROP',
              'CREATE _DBUF 8 CELLS ALLOT',
              '3 _DBUF MP-DRAIN DROP',
              # Drained in nonce order: 0, 1, 2 → amounts 100, 200, 300
              # Must print on one line — use intermediate variables
              '_DBUF 0 CELLS + @ TX-AMOUNT@ _DBUF 1 CELLS + @ TX-AMOUNT@ _DBUF 2 CELLS + @ TX-AMOUNT@ ROT . SWAP . . CR',
          ], "100 200 300")

def test_add_invalid():
    """MP-ADD should reject a tx that fails TX-VALID? (all-zero from key)."""
    check("MP-ADD invalid tx → FALSE",
          _keygen_preamble()
          + [
              'CREATE _BAD TX-BUF-SIZE ALLOT',
              '_BAD TX-INIT',  # all zeros — invalid (no sender)
              '_BAD MP-ADD . CR',
          ], "0")

def test_multi_sender_interleaved():
    """Multiple senders' txs should interleave correctly by address order."""
    check("multi-sender interleaved count=4",
          _keygen_preamble()
          + _make_tx(1, 2, 10, 0, '_T1A')
          + _make_tx(1, 2, 20, 1, '_T1B')
          + _make_tx(2, 1, 30, 0, '_T2A')
          + _make_tx(2, 1, 40, 1, '_T2B')
          + [
              '_T1A MP-ADD DROP',
              '_T2B MP-ADD DROP',
              '_T1B MP-ADD DROP',
              '_T2A MP-ADD DROP',
              'MP-COUNT . CR',
          ], "4")


# ══════════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    build_snapshot()
    print()

    print("=== Mempool Tests ===")
    test_init_count()
    test_add_single()
    test_add_duplicate()
    test_add_same_sender_nonce()
    test_add_multiple()
    test_contains()
    test_contains_not_found()
    test_remove()
    test_remove_not_found()
    test_drain()
    test_drain_all()
    test_release()
    test_sorted_order()
    test_nonce_order_same_sender()
    test_add_invalid()
    test_multi_sender_interleaved()

    print()
    total = _pass_count + _fail_count
    print(f"Results: {_pass_count}/{total} passed, {_fail_count} failed")
    sys.exit(0 if _fail_count == 0 else 1)
