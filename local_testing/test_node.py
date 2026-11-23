#!/usr/bin/env python3
"""Test suite for Akashic node.f (akashic/node/node.f).

Priority 9 fixes tested:
 #66 P32  MP-DRAIN buffer (_NODE-TX-PTRS)
 #67 P33  SRV-STEP wired into NODE-STEP
 #68 P34  Real timestamps via DT-NOW-S
 #69 P35  _NODE-PERSIST-TICK wired into NODE-STEP
 #70 P37  Graceful shutdown (persist, disconnect, key zeroize)
 #71 P36  Busy-wait yield (_NODE-YIELD)
 #72 D03  Time-based block production interval

Block production: the producer appends a block that holds a transaction.
"""
import hashlib, os, sys, time, tempfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.environ.get(
    "MEGAPAD_ROOT", os.path.abspath(os.path.join(ROOT_DIR, "..", "megapad"))
)

# All dependencies — full blockchain + net + web + persist + node





sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem
from forth_snapshot import KDOS_DIAGNOSTICS, _run_input, program_output, run_file_tests, transcript_checks, module_source_lines, megapad_module_lines
from diskutil import format_image

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# The mempool keeps 4096 transaction buffers of 8320 bytes in the dictionary,
# about 34 MB with their index and hashes.  KDOS gives the userland
# dictionary half of extended memory unless told otherwise, so the default
# split of 64 MiB could not hold them: ALLOT failed with "Userland
# dictionary full" and the load went on, so a later MP-ADD would copy a
# transaction over the words after the empty pool.  64 MiB with 16 MiB
# reserved for ALLOCATE leaves the dictionary about 48 MiB.
EXT_MEM_SIZE = 64 << 20
XMEM_RESERVE = 16 << 20


def _load_errors(text, lines):
    """The lines KDOS printed while loading LINES that report a refused line.

    The echo of the source is dropped first, since the source itself names
    some of these messages.
    """
    printed = program_output(text, lines)
    return [line.strip() for line in printed.split('\n')
            if ('?' in line and 'not found' in line.lower())
            or 'dictionary full' in line.lower()
            or any(item in line for item in KDOS_DIAGNOSTICS)]

# ── Emulator helpers ──

_snapshot = None
_base_disk = None

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
            if s.startswith('REQUIRE ') or s.startswith('PROVIDED '):
                continue
            lines.append(line)
        return lines

def capture_uart(sys_obj):
    buf = bytearray()
    sys_obj.uart.on_tx = buf.append
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
    global _snapshot, _base_disk
    if _snapshot:
        return _snapshot

    # Pre-format a base disk image for PST-INIT
    fd, dpath = tempfile.mkstemp(suffix=".img", prefix="node_base_")
    os.close(fd)
    format_image(dpath)
    with open(dpath, 'rb') as f:
        _base_disk = f.read()
    os.unlink(dpath)

    print("[*] Building snapshot: BIOS + KDOS + full node stack ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)

    dep_lines = module_source_lines((
        "concurrency/event.f",
        "concurrency/semaphore.f",
        "concurrency/guard.f",
        "math/fp16.f",
        "math/crypto-acc.f",
        "math/sha512.f",
        "math/field.f",
        "math/sha3.f",
        "math/random.f",
        "math/ed25519.f",
        "math/sphincs-plus.f",
        "cbor/cbor.f",
        "utils/fmt.f",
        "math/merkle.f",
        "store/tx.f",
        "store/smt.f",
        "store/state.f",
        "store/block.f",
        "consensus/consensus.f",
        "store/mempool.f",
        "store/light.f",
        "utils/string.f",
        "net/url.f",
        "net/headers.f",
        "net/base64.f",
        "net/http.f",
        "net/ws.f",
        "net/gossip.f",
        "net/sync.f",
        "store/persist.f",
        "utils/datetime.f",
        "utils/table.f",
        "web/request.f",
        "web/response.f",
        "web/router.f",
        "web/server.f",
        "utils/json.f",
        "web/rpc.f",
        "node/node.f",
    ))

    helpers = [
        # Mock socket/response for server.f (no real network)
        ': _RESP-SEND-MOCK  ( addr len -- ) TYPE ;',
        "' _RESP-SEND-MOCK _RESP-SEND-XT !",
        ': _SRV-SOCKET-MOCK  ( type -- sd ) DROP 1 ;',
        "' _SRV-SOCKET-MOCK _SRV-SOCKET-XT !",
        ': _SRV-BIND-MOCK  ( sd port -- ior ) 2DROP 0 ;',
        "' _SRV-BIND-MOCK _SRV-BIND-XT !",
        ': _SRV-LISTEN-MOCK  ( sd -- ior ) DROP 0 ;',
        "' _SRV-LISTEN-MOCK _SRV-LISTEN-XT !",
        ': _SRV-ACCEPT-MOCK  ( sd -- new-sd ) DROP -1 ;',
        "' _SRV-ACCEPT-MOCK _SRV-ACCEPT-XT !",
        ': _SRV-RECV-MOCK  ( sd addr max -- actual ) 2DROP DROP 0 ;',
        "' _SRV-RECV-MOCK _SRV-RECV-XT !",
        ': _SRV-CLOSE-MOCK  ( sd -- ) DROP ;',
        "' _SRV-CLOSE-MOCK _SRV-CLOSE-XT !",
        ': _SRV-POLL-MOCK  ( -- ) ;',
        "' _SRV-POLL-MOCK _SRV-POLL-XT !",
        ': _SRV-IDLE-MOCK  ( -- ) ;',
        "' _SRV-IDLE-MOCK _SRV-IDLE-XT !",
        '0 SRV-LOG-ENABLED !',
        # Initialize core subsystems for snapshot (NOT NODE-INIT — tests do that)
        'ST-INIT',
        'CHAIN-INIT',
        'MP-INIT',
    ]

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=EXT_MEM_SIZE)
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + [f"{XMEM_RESERVE} U-XMEM-RESERVE!", "ENTER-USERLAND"] + megapad_module_lines("networking.f")
                 + dep_lines
                 + helpers)
    payload = "\n".join(all_lines) + "\n"
    steps = _run_input(sys_obj, payload.encode(), 1_200_000_000, buf)

    text = uart_text(buf)
    errors = _load_errors(text, all_lines)
    if errors:
        tail = "\n".join(text.strip().split('\n')[-30:])
        raise AssertionError(
            f"{len(errors)} line(s) failed to load:\n" + "\n".join(errors[-10:])
            + "\n--- transcript tail ---\n" + tail)

    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot


def run_forth(lines, max_steps=200_000_000, rtc_epoch_ms=None):
    """Run LINES on the snapshot with a fresh disk.

    RTC_EPOCH_MS sets the machine's wall clock, which otherwise starts at
    the Unix epoch.
    """
    if _snapshot is None:
        build_snapshot()
    bios_code, mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    fd, disk_path = tempfile.mkstemp(suffix=".img", prefix="node_run_")
    os.write(fd, _base_disk)
    os.close(fd)
    try:
        sys_obj = MegapadSystem(ram_size=1024*1024,
                                storage_image=disk_path,
                                ext_mem_size=EXT_MEM_SIZE,
                                rtc_epoch_ms=rtc_epoch_ms)
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
        _run_input(sys_obj, payload.encode(), max_steps, buf)
        return uart_text(buf)
    finally:
        try: os.unlink(disk_path)
        except OSError: pass

# The checks read only what the program printed, and fail their test when a
# check fails or KDOS reports a failed line (forth_snapshot.transcript_checks).
check = transcript_checks(run_forth)[0]


# ── Key pairs (RFC 8032 test vectors 1 and 2) ──

TV1_SEED = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
TV1_PUB  = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"

TV2_SEED = "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
TV2_PUB  = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"

# A third pair, from test_state.  Its address sorts between the first
# pair's and the second's, so a pool drains the first pair's transactions
# before the third pair's.
TV3_SEED = "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7"
TV3_PUB  = "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025"


def create_hex_buf(var_name, hex_str):
    bs = bytes.fromhex(hex_str)
    lines = [f'CREATE {var_name} {len(bs)} ALLOT']
    for i, b in enumerate(bs):
        lines.append(f'{b} {var_name} {i} + C!')
    return lines


def _ed25519_private(seed_hex):
    """The 64 bytes ED25519-KEYGEN writes as a seed's private key: SHA-512
    of the seed, its first half clamped into the secret scalar (RFC 8032
    section 5.1.5), its second half kept as the signing prefix."""
    digest = bytearray(hashlib.sha512(bytes.fromhex(seed_hex)).digest())
    digest[0] &= 0xF8
    digest[31] &= 0x3F
    digest[31] |= 0x40
    return digest.hex()


def _key_pair(n, seed_hex, pub_hex):
    """Key pair n from an RFC 8032 vector, and the address of its public key.

    The pair is written as ED25519-KEYGEN writes it rather than derived by
    it, which saves about 54M emulator steps; test_ed25519 checks the
    derivation on these vectors."""
    return (create_hex_buf(f'_PUB{n}', pub_hex)
            + create_hex_buf(f'_PRIV{n}', _ed25519_private(seed_hex))
            + [f'CREATE _ADDR{n} 32 ALLOT', f'_PUB{n} _ADDR{n} ST-ADDR-FROM-KEY'])


# =====================================================================
#  Tests
# =====================================================================

def test_compile():
    print("\n── Compile Check ──\n")
    check("node.f loads without errors",
          [': _T NODE-STOPPED . NODE-RUNNING . NODE-SYNCING . ; _T'],
          "0 1 2 ")


def test_constants():
    print("\n── Constants ──\n")
    check("NODE-STOPPED is 0",
          [': _T NODE-STOPPED . ; _T'], "0 ")
    check("NODE-RUNNING is 1",
          [': _T NODE-RUNNING . ; _T'], "1 ")
    check("NODE-SYNCING is 2",
          [': _T NODE-SYNCING . ; _T'], "2 ")


def test_init():
    print("\n── NODE-INIT ──\n")
    check("NODE-INIT runs without crash",
          [': _T 8080 NODE-INIT 42 . ; _T'],
          "42 ")

    check("NODE-STATUS is STOPPED after init",
          [': _T 8080 NODE-INIT NODE-STATUS . ; _T'],
          "0 ")

    check("Chain height is 0 after init",
          [': _T 8080 NODE-INIT CHAIN-HEIGHT . ; _T'],
          "0 ")

    check("Mempool count is 0 after init",
          [': _T 8080 NODE-INIT MP-COUNT . ; _T'],
          "0 ")

    check("Sync is IDLE after init",
          [': _T 8080 NODE-INIT SYNC-STATUS . ; _T'],
          "0 ")

    check("Persist count is 0 after init",
          [': _T 8080 NODE-INIT PST-BLOCK-COUNT . ; _T'],
          "0 ")

    # NODE-INIT ( port -- ) drops what its sub-systems' inits report.
    check("NODE-INIT leaves the cells below it",
          [': _T DEPTH >R 7 8080 NODE-INIT ." below=" .',
           '  ." left=" DEPTH R> - . ; _T'],
          "below=7 left=0 ")


def test_tx_ptrs_buffer():
    """#66 P32: _NODE-TX-PTRS buffer exists and is non-zero address."""
    print("\n── #66 P32: TX Pointer Buffer ──\n")
    check("_NODE-TX-PTRS exists",
          [': _T _NODE-TX-PTRS 0<> IF ." OK" ELSE ." FAIL" THEN ; _T'],
          "OK")


def test_time_based_interval():
    """#72 D03: _NODE-BLK-INTERVAL is time-based, _NODE-LAST-PRODUCE-T exists."""
    print("\n── #72 D03: Time-based Interval ──\n")
    check("_NODE-BLK-INTERVAL defaults to 10 after init",
          [': _T 8080 NODE-INIT _NODE-BLK-INTERVAL @ . ; _T'],
          "10 ")
    check("_NODE-LAST-PRODUCE-T is 0 after init",
          [': _T 8080 NODE-INIT _NODE-LAST-PRODUCE-T @ . ; _T'],
          "0 ")


def test_srv_step():
    """#67 P33: SRV-STEP is callable (mock returns -1 = no client)."""
    print("\n── #67 P33: SRV-STEP ──\n")
    check("SRV-STEP callable without crash",
          [': _T 8080 SRV-INIT -1 _SRV-RUNNING ! SRV-STEP ." OK" ; _T'],
          "OK")


def test_yield():
    """#71 P36: _NODE-YIELD exists and is callable."""
    print("\n── #71 P36: _NODE-YIELD ──\n")
    check("_NODE-YIELD callable with 0 ms",
          [': _T 0 _NODE-YIELD ." OK" ; _T'],
          "OK")


def test_stop():
    """#70 P37: NODE-STOP does full graceful shutdown."""
    print("\n── #70 P37: NODE-STOP ──\n")
    check("NODE-STOP sets STOPPED",
          [': _T 8080 NODE-INIT',
           '  NODE-RUNNING _NODE-STATE !',
           '  NODE-STOP',
           '  NODE-STATUS . ; _T'],
          "0 ")

    # Verify signing key is zeroed after stop
    check("Signing key zeroed after stop",
          [': _KSUM 0 64 0 DO _CON-SIGN-PRIV I + C@ + LOOP ;',
           ': _T 8080 NODE-INIT',
           '  _CON-SIGN-PRIV 64 255 FILL',    # fill with 0xFF first
           '  NODE-STOP _KSUM . ; _T'],
          "0 ")


def test_step():
    """#67 P33 + #69 P35: NODE-STEP calls SRV-STEP + _NODE-PERSIST-TICK."""
    print("\n── NODE-STEP ──\n")
    check("NODE-STEP runs without crash",
          [': _T 8080 NODE-INIT NODE-STEP 42 . ; _T'],
          "42 ")

    # Two steps — shouldn't crash with time-based logic
    check("Multiple NODE-STEP runs",
          [': _T 8080 NODE-INIT',
           '  NODE-STEP NODE-STEP NODE-STEP',
           '  42 . ; _T'],
          "42 ")


def test_produce_toggle():
    print("\n── Block Production Toggle ──\n")
    check("Production disabled by default",
          [': _T 8080 NODE-INIT',
           '  _NODE-PRODUCE? @ . ; _T'],
          "0 ")

    check("NODE-ENABLE-PRODUCE enables",
          [': _T 8080 NODE-INIT',
           '  NODE-ENABLE-PRODUCE',
           '  _NODE-PRODUCE? @ 0<> IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("NODE-DISABLE-PRODUCE disables",
          [': _T 8080 NODE-INIT',
           '  NODE-ENABLE-PRODUCE',
           '  NODE-DISABLE-PRODUCE',
           '  _NODE-PRODUCE? @ . ; _T'],
          "0 ")


def test_timestamp():
    """#68 P34: DT-NOW-S reads the wall clock once it is set.

    The machine's clock starts at the Unix epoch, unset, and reads 0; the
    host sets it here, as the producer test does."""
    print("\n── #68 P34: DT-NOW-S Timestamp ──\n")
    check("DT-NOW-S reads the clock the host set",
          ['." valid=" DT-CLOCK-VALID? .  ." now=" DT-NOW-S .'],
          "valid=-1 now=1700000000 ", rtc_epoch_ms=1_700_000_000_000)
    check("an unset clock is not valid",
          ['." valid=" DT-CLOCK-VALID? .'], "valid=0 ")


def test_produce_block_with_transaction():
    """The producer appends a block that holds a transaction.

    BLK-FINALIZE applied the block's transaction to the state, and
    CHAIN-APPEND's BLK-VERIFY then applied it a second time, on the
    changed state, where the sender's nonce no longer matched.  The append
    failed: the chain stayed at height 0, the block was neither saved nor
    broadcast, and the drained slots were never released, while the sender
    had already paid.  BLK-FINALIZE now leaves the state as it was, and
    CHAIN-APPEND applies the block once.

    BLK-VERIFY refuses a block after genesis whose timestamp is 0, and the
    producer stamps its block with the wall clock, so the machine's clock
    starts at a wall time."""
    print("\n── Block production ──\n")
    lines = _key_pair(1, TV1_SEED, TV1_PUB) + _key_pair(2, TV2_SEED, TV2_PUB) + [
        'CREATE _TX1 TX-BUF-SIZE ALLOT  _TX1 TX-INIT',
        '_PUB1 _TX1 TX-SET-FROM  _PUB2 _TX1 TX-SET-TO',
        '100 _TX1 TX-SET-AMOUNT  0 _TX1 TX-SET-NONCE',
        '_TX1 _PRIV1 _PUB1 TX-SIGN',
        ': _T 8080 NODE-INIT  _ADDR1 10000 ST-CREATE DROP',
        '  ." add=" _TX1 MP-ADD .',
        '  NODE-ENABLE-PRODUCE _NODE-PRODUCE-BLOCK',
        '  ." height=" CHAIN-HEIGHT .',
        '  ." bal1=" _ADDR1 ST-BALANCE@ .  ." bal2=" _ADDR2 ST-BALANCE@ .',
        '  ." nonce1=" _ADDR1 ST-NONCE@ .  ." pool=" MP-COUNT .',
        '  ." saved=" PST-BLOCK-COUNT . ; _T',
    ]
    check("produced block appended, saved, and applied once", lines,
          "add=-1 height=1 bal1=9900 bal2=100 nonce1=1 pool=0 saved=1 ",
          max_steps=800_000_000, rtc_epoch_ms=1_700_000_000_000)


def _signed_tx(name, sender, recipient, amount, nonce):
    """Lines that build transaction NAME from key pair SENDER to RECIPIENT."""
    return [
        f'CREATE {name} TX-BUF-SIZE ALLOT  {name} TX-INIT',
        f'_PUB{sender} {name} TX-SET-FROM  _PUB{recipient} {name} TX-SET-TO',
        f'{amount} {name} TX-SET-AMOUNT  {nonce} {name} TX-SET-NONCE',
        f'{name} _PRIV{sender} _PUB{sender} TX-SIGN',
    ]


def _three_pairs():
    return (_key_pair(1, TV1_SEED, TV1_PUB) + _key_pair(2, TV2_SEED, TV2_PUB)
            + _key_pair(3, TV3_SEED, TV3_PUB) + ['CREATE _H 32 ALLOT'])


def test_produce_waits_for_the_clock():
    """A node whose clock is not set produces nothing and keeps its pool.

    It drained the pool into a block stamped from the unset clock.  While
    the clock still read 0, BLK-VERIFY refused the block and its drained
    transactions never came back; once the clock had counted past a
    second, as here, the block went into the chain dated 1970."""
    print("\n── Production before the clock is set ──\n")
    lines = _three_pairs() + _signed_tx('_TX1', 1, 2, 100, 0) + [
        ': _T 8080 NODE-INIT  _ADDR1 10000 ST-CREATE DROP',
        '  ." add=" _TX1 MP-ADD .',
        '  NODE-ENABLE-PRODUCE _NODE-PRODUCE-BLOCK',
        '  ." height=" CHAIN-HEIGHT .  ." pool=" MP-COUNT .',
        '  _TX1 _H TX-HASH ." has=" _H MP-CONTAINS? . ; _T',
    ]
    check("no block, and the transaction waits in the pool", lines,
          "add=-1 height=0 pool=1 has=-1 ", max_steps=400_000_000)


def test_refused_block_returns_its_transactions():
    """A block the chain refuses gives its transactions back to the pool.

    The consensus check refuses every block here, so CHAIN-APPEND refuses
    the producer's: its transaction goes back to the pool, and nothing is
    applied."""
    print("\n── A refused block ──\n")
    lines = _three_pairs() + _signed_tx('_TX1', 1, 2, 100, 0) + [
        ': _REFUSE  ( blk -- flag )  DROP 0 ;',
        "' _REFUSE _BLK-CON-CHECK-XT !",
        ': _T 8080 NODE-INIT  _ADDR1 10000 ST-CREATE DROP',
        '  ." add=" _TX1 MP-ADD .',
        '  NODE-ENABLE-PRODUCE _NODE-PRODUCE-BLOCK',
        '  ." height=" CHAIN-HEIGHT .  ." pool=" MP-COUNT .',
        '  _TX1 _H TX-HASH ." has=" _H MP-CONTAINS? .',
        '  ." bal1=" _ADDR1 ST-BALANCE@ . ; _T',
    ]
    check("the transaction is pending again", lines,
          "add=-1 height=0 pool=1 has=-1 bal1=10000 ",
          max_steps=800_000_000, rtc_epoch_ms=1_700_000_000_000)


def test_truncated_block_returns_the_rest():
    """The transactions after the one a block was cut at go back to the pool.

    BLK-FINALIZE ends a block before the first transaction the state
    refuses (P22).  Here the first pair's transaction, which drains first,
    has a nonce the state has not reached, so the block is cut before it
    and holds none; the third pair's transaction, drained after it, went
    with it.  Now the refused one is dropped, the other waits in the pool,
    and the next block applies it."""
    print("\n── A truncated block ──\n")
    lines = _three_pairs() + _signed_tx('_TXA', 1, 2, 100, 5) + _signed_tx(
        '_TXB', 3, 2, 50, 0) + [
        ': _T 8080 NODE-INIT  _ADDR1 10000 ST-CREATE DROP  _ADDR3 10000 ST-CREATE DROP',
        '  ." add=" _TXA MP-ADD . _TXB MP-ADD .',
        '  NODE-ENABLE-PRODUCE _NODE-PRODUCE-BLOCK',
        '  ." height=" CHAIN-HEIGHT .  ." pool=" MP-COUNT .',
        '  _TXB _H TX-HASH ." hasB=" _H MP-CONTAINS? .',
        '  _TXA _H TX-HASH ." hasA=" _H MP-CONTAINS? .',
        '  _NODE-PRODUCE-BLOCK',
        '  ." height2=" CHAIN-HEIGHT .  ." pool2=" MP-COUNT .',
        '  ." bal2=" _ADDR2 ST-BALANCE@ .  ." bal3=" _ADDR3 ST-BALANCE@ . ; _T',
    ]
    check("the later transaction lands in the next block", lines,
          "add=-1 -1 height=1 pool=1 hasB=-1 hasA=0 height2=2 pool2=0 "
          "bal2=50 bal3=9950 ",
          max_steps=1_200_000_000, rtc_epoch_ms=1_700_000_000_000)


def test_subsystem_callbacks():
    print("\n── Sub-system Callbacks ──\n")
    check("Sync callbacks wired after NODE-INIT",
          [': _T 8080 NODE-INIT',
           '  GSP-ON-BLK-ANN-XT @ 0<> IF 1 ELSE 0 THEN .',
           '  GSP-ON-BLK-RSP-XT @ 0<> IF 1 ELSE 0 THEN .',
           '  GSP-ON-STATUS-XT @ 0<> IF 1 ELSE 0 THEN . ; _T'],
          "1 1 1 ")

    check("RPC route registered after NODE-INIT",
          [': _T 8080 NODE-INIT',
           '  ROUTE-COUNT . ; _T'],
          check_fn=lambda t: any(c.isdigit() and int(c) >= 1
                                for c in t.strip().split()
                                if c.isdigit()))


# =====================================================================
#  Main
# =====================================================================


if __name__ == "__main__":
    run_file_tests(__file__)
