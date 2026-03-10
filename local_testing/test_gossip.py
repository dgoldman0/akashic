#!/usr/bin/env python3
"""Test suite for Akashic gossip.f (akashic/net/gossip.f).

Tests:
  - Module compilation (loads without error)
  - GSP-INIT + GSP-PEER-COUNT
  - Seen-hash dedup (GSP-SEEN?, _GSP-SEEN-ADD)
  - Message type constants
  - GSP-ON-MSG dispatch: TX-ANNOUNCE → mempool
  - GSP-ON-MSG dispatch: BLOCK-ANNOUNCE → callback
  - GSP-ON-MSG dispatch: STATUS → callback
  - GSP-ON-MSG unknown type → silently ignored
  - GSP-ON-MSG empty buffer → no crash
  - Seen-hash ring buffer wrap-around
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")

# Dependency file paths (in load order)
EVENT_F     = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
SEM_F       = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")
GUARD_F     = os.path.join(ROOT_DIR, "akashic", "concurrency", "guard.f")
FP16_F      = os.path.join(ROOT_DIR, "akashic", "math", "fp16.f")
SHA512_F    = os.path.join(ROOT_DIR, "akashic", "math", "sha512.f")
FIELD_F     = os.path.join(ROOT_DIR, "akashic", "math", "field.f")
SHA3_F      = os.path.join(ROOT_DIR, "akashic", "math", "sha3.f")
RANDOM_F    = os.path.join(ROOT_DIR, "akashic", "math", "random.f")
ED25519_F   = os.path.join(ROOT_DIR, "akashic", "math", "ed25519.f")
SPHINCS_F   = os.path.join(ROOT_DIR, "akashic", "math", "sphincs-plus.f")
CBOR_F      = os.path.join(ROOT_DIR, "akashic", "cbor", "cbor.f")
FMT_F       = os.path.join(ROOT_DIR, "akashic", "utils", "fmt.f")
MERKLE_F    = os.path.join(ROOT_DIR, "akashic", "math", "merkle.f")
TX_F        = os.path.join(ROOT_DIR, "akashic", "store", "tx.f")
SMT_F       = os.path.join(ROOT_DIR, "akashic", "store", "smt.f")
STATE_F     = os.path.join(ROOT_DIR, "akashic", "store", "state.f")
BLOCK_F     = os.path.join(ROOT_DIR, "akashic", "store", "block.f")
CONSENSUS_F = os.path.join(ROOT_DIR, "akashic", "consensus", "consensus.f")
MEMPOOL_F   = os.path.join(ROOT_DIR, "akashic", "store", "mempool.f")

# Network stack dependencies (ws.f needs http.f needs url.f, headers.f, etc.)
STRING_F    = os.path.join(ROOT_DIR, "akashic", "utils", "string.f")
URL_F       = os.path.join(ROOT_DIR, "akashic", "net", "url.f")
HEADERS_F   = os.path.join(ROOT_DIR, "akashic", "net", "headers.f")
BASE64_F    = os.path.join(ROOT_DIR, "akashic", "net", "base64.f")
HTTP_F      = os.path.join(ROOT_DIR, "akashic", "net", "http.f")
WS_F        = os.path.join(ROOT_DIR, "akashic", "net", "ws.f")
GOSSIP_F    = os.path.join(ROOT_DIR, "akashic", "net", "gossip.f")

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
    print("[*] Building snapshot: BIOS + KDOS + all gossip.f dependencies ...")
    t0 = time.time()
    bios_code   = _load_bios()
    kdos_lines  = _load_forth_lines(KDOS_PATH)

    dep_lines = []
    for path in [EVENT_F, SEM_F, GUARD_F, FP16_F,
                 SHA512_F, FIELD_F, SHA3_F, RANDOM_F,
                 ED25519_F, SPHINCS_F, CBOR_F, FMT_F,
                 MERKLE_F, TX_F, SMT_F, STATE_F, BLOCK_F,
                 CONSENSUS_F, MEMPOOL_F,
                 STRING_F, URL_F, HEADERS_F, BASE64_F,
                 HTTP_F, WS_F, GOSSIP_F]:
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
        print(f"  Aborting — gossip.f failed to compile cleanly.")
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

# ── Keys (Ed25519 RFC 8032 TV1, TV2, TV3) ──

TV1_SEED = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
TV1_PUB  = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"

TV2_SEED = "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
TV2_PUB  = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"

TV3_SEED = "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7"
TV3_PUB  = "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025"


def _keygen_preamble():
    """Create keypairs, address buffers, and init state + mempool + gossip."""
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
        '_ADDR1 10000 ST-CREATE DROP',
        '_ADDR2 5000 ST-CREATE DROP',
        '_ADDR3 3000 ST-CREATE DROP',
        'MP-INIT',
        'GSP-INIT',
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

def test_module_loads():
    """gossip.f compiles and basic arithmetic works."""
    check("Module loaded", ['1 2 + . CR'], "3")

def test_constants():
    """Message type constants have expected values."""
    check("GSP-MSG-TX=1",      ['GSP-MSG-TX . CR'],      "1")
    check("GSP-MSG-BLK-ANN=2", ['GSP-MSG-BLK-ANN . CR'], "2")
    check("GSP-MSG-BLK-REQ=3", ['GSP-MSG-BLK-REQ . CR'], "3")
    check("GSP-MSG-BLK-RSP=4", ['GSP-MSG-BLK-RSP . CR'], "4")
    check("GSP-MSG-STATUS=6",  ['GSP-MSG-STATUS . CR'],   "6")
    check("GSP-MAX-PEERS=64",  ['GSP-MAX-PEERS . CR'],    "64")

def test_init_peer_count():
    """GSP-INIT → peer count = 0."""
    check("GSP-INIT → peers=0",
          ['GSP-INIT', 'GSP-PEER-COUNT . CR'], "0")

def test_seen_not_found():
    """GSP-SEEN? on empty cache returns FALSE."""
    lines = _keygen_preamble() + \
        create_hex_buf('_H1', 'aa' * 32) + [
        '_H1 GSP-SEEN? . CR',
    ]
    check("GSP-SEEN? empty → 0", lines, "0")

def test_seen_after_add():
    """A hash manually added via _GSP-SEEN-ADD should be found by GSP-SEEN?."""
    lines = _keygen_preamble() + \
        create_hex_buf('_H1', 'bb' * 32) + [
        # Manually call the internal add (it's not guarded by concurrency
        # at the _ level, but in test snapshot the inner word should still exist)
        # Actually _GSP-SEEN-ADD is internal — use broadcast which calls it.
        # Instead, let's add a tx to mempool and broadcast, which marks it seen.
        # Or we can test via on-msg flow. Let's do a simpler approach:
        # Create a tx, encode it, build a TX-ANNOUNCE message, feed to GSP-ON-MSG.
        # If the tx gets added to mempool, then its hash should be in seen cache.
    ] + _make_tx(1, 2, 100, 0, '_TX1') + [
        # Encode tx to CBOR
        'CREATE _TXCBOR 16384 ALLOT',
        '_TX1 _TXCBOR 1+ 16383 TX-ENCODE',  # encode starting at offset 1
        '1+ CONSTANT _MSGLEN',               # total msg len = cbor_len + 1
        '1 _TXCBOR C!',                      # tag byte = GSP-MSG-TX (1)
        # Feed to GSP-ON-MSG
        '_TXCBOR _MSGLEN 0 GSP-ON-MSG',
        # Now check if the tx hash is in seen cache
        'CREATE _HTMP 32 ALLOT',
        '_TX1 _HTMP TX-HASH',
        '_HTMP GSP-SEEN? . CR',
    ]
    check("GSP-SEEN? after ON-MSG TX → TRUE", lines, "-1")

def test_on_msg_tx_to_mempool():
    """GSP-ON-MSG with TX-ANNOUNCE should add tx to mempool."""
    lines = _keygen_preamble() + \
        _make_tx(1, 2, 100, 0, '_TX1') + [
        # Encode tx to CBOR and build gossip message
        'CREATE _TXCBOR 16384 ALLOT',
        '_TX1 _TXCBOR 1+ 16383 TX-ENCODE',
        '1+ CONSTANT _MSGLEN',
        '1 _TXCBOR C!',
        # Feed to GSP-ON-MSG (peer 0)
        '_TXCBOR _MSGLEN 0 GSP-ON-MSG',
        # Check mempool count
        'MP-COUNT . CR',
    ]
    check("ON-MSG TX → mempool count=1", lines, "1")

def test_on_msg_tx_dedup():
    """Feeding same TX-ANNOUNCE twice should only add to mempool once."""
    lines = _keygen_preamble() + \
        _make_tx(1, 2, 100, 0, '_TX1') + [
        'CREATE _TXCBOR 16384 ALLOT',
        '_TX1 _TXCBOR 1+ 16383 TX-ENCODE',
        '1+ CONSTANT _MSGLEN',
        '1 _TXCBOR C!',
        # Feed same message twice
        '_TXCBOR _MSGLEN 0 GSP-ON-MSG',
        '_TXCBOR _MSGLEN 0 GSP-ON-MSG',
        # Should still be 1
        'MP-COUNT . CR',
    ]
    check("ON-MSG TX dedup → count=1", lines, "1")

def test_on_msg_tx_callback():
    """GSP-ON-TX-XT callback should fire on valid tx."""
    lines = _keygen_preamble() + [
        # Set up callback that prints a marker
        'VARIABLE _CB-FIRED',
        '0 _CB-FIRED !',
        ': _MY-TX-CB  ( tx -- ) DROP  1 _CB-FIRED ! ;',
        "' _MY-TX-CB GSP-ON-TX-XT !",
    ] + _make_tx(1, 2, 100, 0, '_TX1') + [
        'CREATE _TXCBOR 16384 ALLOT',
        '_TX1 _TXCBOR 1+ 16383 TX-ENCODE',
        '1+ CONSTANT _MSGLEN',
        '1 _TXCBOR C!',
        '_TXCBOR _MSGLEN 0 GSP-ON-MSG',
        '_CB-FIRED @ . CR',
    ]
    check("ON-TX callback fired", lines, "1")

def test_on_msg_status_callback():
    """GSP-ON-MSG with STATUS message should fire GSP-ON-STATUS-XT."""
    lines = _keygen_preamble() + [
        # Build a STATUS message: [0x06][CBOR: 2-array [hash(bstr32), height(uint)]]
        'CREATE _SMSG 128 ALLOT',
        '6 _SMSG C!',                              # tag = STATUS
        '_SMSG 1+ 127 CBOR-RESET',
        '2 CBOR-ARRAY',
    ] + create_hex_buf('_FHASH', 'cc' * 32) + [
        '_FHASH 32 CBOR-BSTR',
        '42 CBOR-UINT',
        'CBOR-RESULT NIP 1+',                      # total len
        'CONSTANT _SLEN',
        # Set up callback
        'VARIABLE _GOT-HT',
        '0 _GOT-HT !',
        ': _MY-STATUS-CB  ( height peer -- ) DROP _GOT-HT ! ;',
        "' _MY-STATUS-CB GSP-ON-STATUS-XT !",
        # Dispatch
        '_SMSG _SLEN 5 GSP-ON-MSG',               # peer 5
        '_GOT-HT @ . CR',
    ]
    check("ON-STATUS callback → height=42", lines, "42")

def test_on_msg_blk_ann_callback():
    """GSP-ON-MSG with BLOCK-ANNOUNCE should fire GSP-ON-BLK-ANN-XT."""
    lines = _keygen_preamble() + [
        'CREATE _BMSG 128 ALLOT',
        '2 _BMSG C!',                              # tag = BLK-ANN
        '_BMSG 1+ 127 CBOR-RESET',
        '2 CBOR-ARRAY',
    ] + create_hex_buf('_BHASH', 'dd' * 32) + [
        '_BHASH 32 CBOR-BSTR',
        '99 CBOR-UINT',
        'CBOR-RESULT NIP 1+',
        'CONSTANT _BLEN',
        # Callback
        'VARIABLE _ANN-HT',
        '0 _ANN-HT !',
        ': _MY-BLK-CB  ( height peer -- ) DROP _ANN-HT ! ;',
        "' _MY-BLK-CB GSP-ON-BLK-ANN-XT !",
        '_BMSG _BLEN 3 GSP-ON-MSG',
        '_ANN-HT @ . CR',
    ]
    check("ON-BLK-ANN callback → height=99", lines, "99")

def test_on_msg_unknown_type():
    """GSP-ON-MSG with unknown tag should not crash."""
    lines = _keygen_preamble() + [
        'CREATE _UMSG 4 ALLOT',
        '255 _UMSG C!',                            # unknown tag
        '0 _UMSG 1+ C!',
        '_UMSG 2 0 GSP-ON-MSG',
        '1 . CR',                                  # proof we didn't crash
    ]
    check("ON-MSG unknown type → no crash", lines, "1")

def test_on_msg_empty():
    """GSP-ON-MSG with 0-length buffer should not crash."""
    lines = _keygen_preamble() + [
        'CREATE _EMSG 1 ALLOT',
        '_EMSG 0 0 GSP-ON-MSG',
        '1 . CR',
    ]
    check("ON-MSG empty → no crash", lines, "1")

def test_seen_ring_wrap():
    """Seen-hash ring buffer should wrap at 1024 entries (FIX P27)."""
    lines = _keygen_preamble() + [
        'CREATE _RH 32 ALLOT',
        # Fill 1024 entries
        '1024 0 DO',
        '  _RH 32 0 FILL',
        '  I _RH !',
        '  _RH _GSP-SEEN-ADD',
        'LOOP',
        # Entry 0 should still be present (exactly 1024)
        '_RH 32 0 FILL  0 _RH !',
        '_RH GSP-SEEN? . CR',
    ]
    check("seen ring 1024 entries → first still present", lines, "-1")

def test_seen_ring_evict():
    """After 1025 inserts, entry 0 should be evicted (FIX P27)."""
    lines = _keygen_preamble() + [
        'CREATE _RH 32 ALLOT',
        # Fill 1025 entries — entry 0 should be overwritten
        '1025 0 DO',
        '  _RH 32 0 FILL',
        '  I _RH !',
        '  _RH _GSP-SEEN-ADD',
        'LOOP',
        # Check entry 0: should be evicted
        '_RH 32 0 FILL  0 _RH !',
        '_RH GSP-SEEN? . CR',
    ]
    check("seen ring 1025 entries → first evicted", lines, "0")

def test_on_msg_invalid_tx():
    """GSP-ON-MSG with an invalid TX should not add to mempool."""
    lines = _keygen_preamble() + [
        # Build a malformed TX-ANNOUNCE: tag=1 + garbage CBOR
        'CREATE _BADMSG 64 ALLOT',
        '1 _BADMSG C!',
        '_BADMSG 1+ 63 0 FILL',
        '_BADMSG 64 0 GSP-ON-MSG',
        'MP-COUNT . CR',
    ]
    check("ON-MSG invalid TX → mempool empty", lines, "0")


def test_disconnect_oob_no_crash():
    """GSP-DISCONNECT with out-of-bounds peer-id should not crash (FIX P26)."""
    lines = _keygen_preamble() + [
        # Try disconnecting with various invalid IDs
        '999 GSP-DISCONNECT',
        '-1 GSP-DISCONNECT',
        '64 GSP-DISCONNECT',
        'GSP-PEER-COUNT . CR',
    ]
    check("GSP-DISCONNECT OOB → no crash, peers=0", lines, "0")


def test_valid_id_check():
    """_GSP-VALID-ID? should accept 0..63 and reject everything else (FIX P26)."""
    lines = _keygen_preamble() + [
        '0 _GSP-VALID-ID? . 63 _GSP-VALID-ID? . 64 _GSP-VALID-ID? . -1 _GSP-VALID-ID? . CR',
    ]
    check("_GSP-VALID-ID? bounds", lines, "-1 -1 0 0")


def test_on_msg_oversized_rejected():
    """GSP-ON-MSG should reject messages larger than _GSP-BUF-SZ (FIX B10)."""
    lines = _keygen_preamble() + [
        # Build a STATUS message but claim len > 16384
        'CREATE _OMSG 4 ALLOT',
        '6 _OMSG C!',
        # Set up callback to detect if anything fires
        'VARIABLE _OS-FIRED',
        '0 _OS-FIRED !',
        ': _OS-CB  ( height peer -- ) 2DROP  1 _OS-FIRED ! ;',
        "' _OS-CB GSP-ON-STATUS-XT !",
        # Feed msg with len = 16385 (> 16384 buf size)
        '_OMSG 16385 0 GSP-ON-MSG',
        '_OS-FIRED @ . CR',
    ]
    check("ON-MSG oversized → rejected (callback not fired)", lines, "0")


def test_unknown_msg_counter():
    """Unknown message types should increment GSP-UNKNOWN-COUNT (FIX D01)."""
    lines = _keygen_preamble() + [
        'CREATE _UMSG 4 ALLOT',
        'GSP-UNKNOWN-COUNT VARIABLE _PRE  _PRE !',
        # Send 3 unknown message types
        '255 _UMSG C!  _UMSG 2 0 GSP-ON-MSG',
        '200 _UMSG C!  _UMSG 2 0 GSP-ON-MSG',
        '100 _UMSG C!  _UMSG 2 0 GSP-ON-MSG',
        '_PRE @ . GSP-UNKNOWN-COUNT . CR',
    ]
    check("unknown msg counter 0 → 3", lines, "0 3")


def test_seen_cap_constant():
    """_GSP-SEEN-CAP should be 1024 (FIX P27)."""
    check("_GSP-SEEN-CAP=1024", ['_GSP-SEEN-CAP . CR'], "1024")


# ══════════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    build_snapshot()
    print()

    print("=== Gossip Tests ===")
    test_module_loads()
    test_constants()
    test_init_peer_count()
    test_seen_not_found()
    test_seen_after_add()
    test_on_msg_tx_to_mempool()
    test_on_msg_tx_dedup()
    test_on_msg_tx_callback()
    test_on_msg_status_callback()
    test_on_msg_blk_ann_callback()
    test_on_msg_unknown_type()
    test_on_msg_empty()
    test_seen_ring_wrap()
    test_seen_ring_evict()
    test_on_msg_invalid_tx()
    # New tests for fixes P26, B02, B10, P27, D01
    test_disconnect_oob_no_crash()
    test_valid_id_check()
    test_on_msg_oversized_rejected()
    test_unknown_msg_counter()
    test_seen_cap_constant()

    print()
    total = _pass_count + _fail_count
    print(f"Results: {_pass_count}/{total} passed, {_fail_count} failed")
    sys.exit(0 if _fail_count == 0 else 1)
