#!/usr/bin/env python3
"""Test suite for Akashic persist.f (akashic/store/persist.f).

Disk-backed persistence tests — creates a temporary MP64FS disk image,
attaches it to the emulator, and exercises the full persist API:

  - Module compilation
  - PST-INIT opens/creates files on disk
  - PST-BLOCK-COUNT starts at 0
  - PST-SAVE-BLOCK with genesis → count=1
  - PST-LOAD-BLOCK reads back → matching height
  - Multiple saves → count increments
  - PST-CLEAR resets
  - PST-SAVE-STATE + PST-LOAD-STATE round-trip
  - PST-CLOSE releases file descriptors
  - Records larger than 256 KB: a block and a state snapshot round-trip
  - Repeated saves of mixed sizes leave extended memory where it was
  - A block the chain file cannot hold is refused whole
"""
import os, sys, time, tempfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.environ.get(
    "MEGAPAD_ROOT", os.path.abspath(os.path.join(ROOT_DIR, "..", "megapad"))
)

# Dependency file paths

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem
from forth_snapshot import KDOS_DIAGNOSTICS, _run_input, program_output, run_file_tests, transcript_checks, module_source_lines
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


# =====================================================================
#  Snapshot — loads BIOS + KDOS + full dep chain (no disk needed)
# =====================================================================
#  PST-INIT is NOT called in the snapshot because it requires a disk.
#  Each test calls PST-INIT itself on a fresh formatted image.

_base_disk = None  # bytes of a freshly formatted disk image

def _init_base_disk():
    """Create a formatted MP64FS image in memory."""
    global _base_disk
    fd, path = tempfile.mkstemp(suffix=".img", prefix="pst_base_")
    os.close(fd)
    format_image(path)
    with open(path, 'rb') as f:
        _base_disk = f.read()
    os.unlink(path)


def build_snapshot():
    global _snapshot
    if _snapshot:
        return _snapshot
    _init_base_disk()
    print("[*] Building snapshot: BIOS + KDOS + blockchain deps ...")
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
        "store/smt.f",
        "store/tx.f",
        "store/state.f",
        "store/block.f",
        "consensus/consensus.f",
        "store/mempool.f",
        "store/persist.f",
    ))

    # ST-INIT + CHAIN-INIT + MP-INIT.
    # CHAIN-INIT is needed so CHAIN-HEAD points to a valid genesis block
    # (with version=1).  PST-INIT requires disk, called per-test.
    helpers = [
        'ST-INIT',
        'CHAIN-INIT',
        'MP-INIT',
    ]

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=EXT_MEM_SIZE)
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + [f"{XMEM_RESERVE} U-XMEM-RESERVE!", "ENTER-USERLAND"]
                 + dep_lines
                 + helpers)
    payload = "\n".join(all_lines) + "\n"
    steps = _run_input(sys_obj, payload.encode(), 900_000_000, buf)

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


# =====================================================================
#  run_forth — restore snapshot with a fresh disk image per invocation
# =====================================================================

def run_forth(lines, max_steps=200_000_000):
    """Restore snapshot, attach a fresh formatted disk, run Forth lines."""
    if _snapshot is None:
        build_snapshot()
    bios_code, mem_bytes, cpu_state, ext_mem_bytes = _snapshot

    # Write a fresh copy of the base disk image to a temp file
    fd, disk_path = tempfile.mkstemp(suffix=".img", prefix="pst_run_")
    os.write(fd, _base_disk)
    os.close(fd)

    try:
        sys_obj = MegapadSystem(ram_size=1024*1024,
                                storage_image=disk_path,
                                ext_mem_size=EXT_MEM_SIZE)
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
        try:
            os.unlink(disk_path)
        except OSError:
            pass

# The checks read only what the program printed, and fail their test when a
# check fails or KDOS reports a failed line (forth_snapshot.transcript_checks).
check = transcript_checks(run_forth)[0]


# =====================================================================
#  Tests
# =====================================================================
#  Every test calls PST-INIT DROP at the start to open/create files
#  on the fresh disk.  PST-INIT returns -1 (TRUE) on success.

_PST_PREAMBLE = 'PST-INIT DROP'   # run at start of each test word


def test_compile():
    print("\n── Compile Check ──\n")
    # Only look for Forth compilation errors ("? (not found)"),
    # NOT filesystem "Not found: <file>" which is normal OPEN failure.
    check("persist.f loads without errors",
          [f': _T {_PST_PREAMBLE} PST-BLOCK-COUNT . ; _T'],
          check_fn=lambda t: '? (not found)' not in t.lower())


def test_init():
    print("\n── PST-INIT ──\n")
    check("PST-INIT returns TRUE",
          [': _T PST-INIT IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("PST-BLOCK-COUNT starts at 0",
          [f': _T {_PST_PREAMBLE} PST-BLOCK-COUNT . ; _T'],
          "0 ")

    check("_PST-OK is set after init",
          [f': _T {_PST_PREAMBLE} _PST-OK @ 0<> IF 1 ELSE 0 THEN . ; _T'],
          "1 ")


def test_save_genesis():
    print("\n── Save Genesis Block ──\n")
    check("Save genesis block succeeds",
          [f': _T {_PST_PREAMBLE}',
           '  CHAIN-HEAD PST-SAVE-BLOCK',
           '  IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("Count is 1 after save",
          [f': _T {_PST_PREAMBLE}',
           '  CHAIN-HEAD PST-SAVE-BLOCK DROP',
           '  PST-BLOCK-COUNT . ; _T'],
          "1 ")


def test_load_block():
    print("\n── Load Block ──\n")
    check("Load block 0 succeeds",
          ['CREATE _LB BLK-STRUCT-SIZE ALLOT',
           f': _T {_PST_PREAMBLE}',
           '  CHAIN-HEAD PST-SAVE-BLOCK DROP',
           '  _LB BLK-INIT',
           '  0 _LB PST-LOAD-BLOCK',
           '  IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("Loaded block has correct height (0)",
          ['CREATE _LB2 BLK-STRUCT-SIZE ALLOT',
           f': _T {_PST_PREAMBLE}',
           '  CHAIN-HEAD PST-SAVE-BLOCK DROP',
           '  _LB2 BLK-INIT',
           '  0 _LB2 PST-LOAD-BLOCK DROP',
           '  _LB2 BLK-HEIGHT@ . ; _T'],
          "0 ")


def test_load_out_of_range():
    print("\n── Load Out of Range ──\n")
    check("Load index >= count fails",
          ['CREATE _LB3 BLK-STRUCT-SIZE ALLOT',
           f': _T {_PST_PREAMBLE}',
           '  CHAIN-HEAD PST-SAVE-BLOCK DROP',     # count=1
           '  5 _LB3 PST-LOAD-BLOCK',              # idx 5 > count
           '  IF 1 ELSE 0 THEN . ; _T'],
          "0 ")


def test_multiple_saves():
    print("\n── Multiple Saves ──\n")
    check("Two saves -> count=2",
          [f': _T {_PST_PREAMBLE}',
           '  CHAIN-HEAD PST-SAVE-BLOCK DROP',
           '  CHAIN-HEAD PST-SAVE-BLOCK DROP',
           '  PST-BLOCK-COUNT . ; _T'],
          "2 ")

    check("Load entry 1 also succeeds",
          ['CREATE _LB4 BLK-STRUCT-SIZE ALLOT',
           f': _T {_PST_PREAMBLE}',
           '  CHAIN-HEAD PST-SAVE-BLOCK DROP',
           '  CHAIN-HEAD PST-SAVE-BLOCK DROP',
           '  _LB4 BLK-INIT',
           '  1 _LB4 PST-LOAD-BLOCK',
           '  IF 1 ELSE 0 THEN . ; _T'],
          "1 ")


def test_clear():
    print("\n── PST-CLEAR ──\n")
    check("PST-CLEAR resets count to 0",
          [f': _T {_PST_PREAMBLE}',
           '  CHAIN-HEAD PST-SAVE-BLOCK DROP',
           '  PST-CLEAR',
           '  PST-BLOCK-COUNT . ; _T'],
          "0 ")


def test_save_state():
    print("\n── PST-SAVE-STATE / PST-LOAD-STATE ──\n")
    # New API: PST-SAVE-STATE ( -- flag ), PST-LOAD-STATE ( -- flag )
    # They use the internal _PST-BUF, no user buffer needed.
    check("PST-SAVE-STATE returns TRUE",
          ['CREATE _ADDR 32 ALLOT',
           f': _T {_PST_PREAMBLE}',
           '  _ADDR 32 0 FILL',
           '  _ADDR 1000 ST-CREATE DROP',
           '  PST-SAVE-STATE IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("State round-trip preserves account count",
          ['CREATE _ADDR2 32 ALLOT',
           f': _T {_PST_PREAMBLE}',
           '  _ADDR2 32 0 FILL',
           '  _ADDR2 1000 ST-CREATE DROP',
           '  ST-COUNT .',                  # count before save
           '  PST-SAVE-STATE DROP',
           '  ST-INIT',                     # wipe state
           '  ST-COUNT .',                  # 0
           '  PST-LOAD-STATE DROP',
           '  ST-COUNT . ; _T'],            # should match original
          check_fn=lambda t: '1 0 1' in t)


def test_close_reopen():
    print("\n── PST-CLOSE + reopen ──\n")
    check("Block count survives close/reopen",
          [f': _T {_PST_PREAMBLE}',
           '  CHAIN-HEAD PST-SAVE-BLOCK DROP',
           '  PST-BLOCK-COUNT .',           # 1
           '  PST-CLOSE',
           '  PST-INIT DROP',               # reopen — re-scans chain.dat
           '  PST-BLOCK-COUNT . ; _T'],     # still 1
          check_fn=lambda t: '1 1' in t)


# ── New P8 tests: chain-id filenames, configurable sectors ──

def test_set_chain_id():
    """[FIX B08] PST-SET-CHAIN-ID derives new filenames."""
    print("\n── PST-SET-CHAIN-ID ──\n")
    check("Chain id 42 creates chain_42.dat",
          [': _T 42 PST-SET-CHAIN-ID PST-INIT IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    # If chain_42.dat is independent, saving there should not
    # affect a re-open of the (nonexistent initially) chain_42 log.
    check("Data persists across close/reopen with chain id",
          [': _T 42 PST-SET-CHAIN-ID PST-INIT DROP',
           '  CHAIN-HEAD PST-SAVE-BLOCK DROP',
           '  PST-BLOCK-COUNT .',
           '  PST-CLOSE',
           '  42 PST-SET-CHAIN-ID PST-INIT DROP',
           '  PST-BLOCK-COUNT . ; _T'],
          check_fn=lambda t: '1 1' in t)


def test_set_capacity():
    """[FIX P31] PST-SET-CAPACITY overrides sector counts."""
    print("\n── PST-SET-CAPACITY ──\n")
    # Use a small sector count — still enough for one block
    check("Custom capacity init succeeds",
          [': _T 256 20 PST-SET-CAPACITY',
           '  PST-INIT IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("Custom capacity: save+load works",
          [': _T 256 20 PST-SET-CAPACITY PST-INIT DROP',
           '  CHAIN-HEAD PST-SAVE-BLOCK IF 1 ELSE 0 THEN . ; _T'],
          "1 ")


def test_o1_block_load():
    """[FIX B07] O(1) indexed load — save 3 blocks, load middle one."""
    print("\n── O(1) Block Index ──\n")
    check("Load block 1 of 3 via index",
          ['CREATE _LB5 BLK-STRUCT-SIZE ALLOT',
           f': _T {_PST_PREAMBLE}',
           # Save genesis 3 times (all have height=0, but that's fine)
           '  CHAIN-HEAD PST-SAVE-BLOCK DROP',
           '  CHAIN-HEAD PST-SAVE-BLOCK DROP',
           '  CHAIN-HEAD PST-SAVE-BLOCK DROP',
           '  PST-BLOCK-COUNT .',             # 3
           '  _LB5 BLK-INIT',
           '  1 _LB5 PST-LOAD-BLOCK',        # load middle
           '  IF 1 ELSE 0 THEN . ; _T'],
          check_fn=lambda t: '3 1' in t)


# ── Records larger than the old 256 KB buffer ──
#
# persist.f encoded every block into one 256 KB buffer, which a block of
# 33 hybrid transactions outgrows; a full block of 256 encodes to about
# 2.1 MB.  The record buffer now grows to what a record needs and is
# kept, so these cases build blocks of hybrid-shaped transactions: each
# carries both signatures at their full lengths, patterned bytes in place
# of real signatures, since encoding and decoding do not verify and a
# SPHINCS+ signature costs far more emulator time than this suite has.
# An encoding pass costs about 570 emulator steps per byte it writes, so
# only the case about size uses a block over 256 KB.  _SAME compares two
# blocks field by field: their header bytes, and for each transaction
# every byte before the internal flags, which holds every field
# TX-ENCODE writes.

def _hybrid_blocks(*blocks):
    """Lines that build each (NAME, COUNT, HEIGHT) block from one pool of
    hybrid-shaped transactions, the block holding the pool's first COUNT,
    and the helpers the cases share."""
    most = max(count for _, count, _ in blocks)
    lines = [
        f'CREATE _HPOOL {most} TX-BUF-SIZE * ALLOT',
        'CREATE _HK1 32 ALLOT  _HK1 32 17 FILL',
        'CREATE _HK2 32 ALLOT  _HK2 32 34 FILL',
        'VARIABLE _HT  VARIABLE _HI',
        # _HTX ( i -- tx )  pool transaction i, its fields set from i
        ': _HTX  ( i -- tx )  DUP _HI !  TX-BUF-SIZE * _HPOOL + DUP _HT !',
        '  TX-INIT  _HK1 _HT @ TX-SET-FROM  _HK2 _HT @ TX-SET-TO',
        '  _HI @ 1+ _HT @ TX-SET-AMOUNT  _HI @ _HT @ TX-SET-NONCE',
        '  _HT @ _TX-SIG ED25519-SIG-LEN _HI @ FILL',
        '  _HT @ _TX-SIG-PQ SPX-SIG-LEN _HI @ 101 + FILL',
        '  TX-SIG-HYBRID _HT @ _TX-SIG-MODE C!  _HT @ ;',
        # _HBLK ( n height blk -- )  a block holding pool transactions 0..n-1
        ': _HBLK  ( n height blk -- )  DUP BLK-INIT  TUCK BLK-SET-HEIGHT',
        '  1700000000 OVER BLK-SET-TIME',
        '  SWAP 0 ?DO I _HTX OVER BLK-ADD-TX DROP LOOP DROP ;',
        'VARIABLE _SB1  VARIABLE _SB2',
        # _SAME ( blk1 blk2 -- flag )  TRUE when the blocks match field by field
        ': _SAME  ( blk1 blk2 -- flag )  _SB2 ! _SB1 !',
        '  _SB1 @ BLK-HDR-SIZE _SB2 @ BLK-HDR-SIZE COMPARE IF 0 EXIT THEN',
        '  _SB1 @ BLK-TX-COUNT@ _SB2 @ BLK-TX-COUNT@ <> IF 0 EXIT THEN',
        '  _SB1 @ BLK-TX-COUNT@ 0 ?DO',
        '    I _SB1 @ BLK-TX@ _TX-OFF-FLAGS  I _SB2 @ BLK-TX@ _TX-OFF-FLAGS',
        '    COMPARE IF 0 UNLOOP EXIT THEN',
        '  LOOP -1 ;',
        'CREATE _BL BLK-STRUCT-SIZE ALLOT',
    ]
    for name, count, height in blocks:
        lines.append(f'CREATE {name} BLK-STRUCT-SIZE ALLOT  {count} {height} {name} _HBLK')
    return lines


def test_large_block_round_trip():
    """A block larger than 256 KB saves and loads back intact.

    Its record goes into the chain file whole, the walk at PST-INIT finds
    it again after a close, and the block read back matches the saved
    block field by field."""
    print("\n── Block over 256 KB ──\n")
    lines = _hybrid_blocks(('_BB', 40, 5)) + [
        f': _T {_PST_PREAMBLE}',
        '  ." save=" _BB PST-SAVE-BLOCK .',
        '  ." record=" _PST-CHAIN-FD @ FSIZE 8 - DUP .  262144 > ." over=" .',
        '  PST-CLOSE PST-INIT DROP  ." count=" PST-BLOCK-COUNT .',
        '  ." load=" 0 _BL PST-LOAD-BLOCK .  ." txs=" _BL BLK-TX-COUNT@ .',
        '  ." same=" _BL _BB _SAME . ; _T',
    ]
    check("a 40-transaction block round-trips", lines,
          check_fn=lambda t: "save=-1 record=" in t
          and "over=-1 count=1 load=-1 txs=40 same=-1 " in t,
          max_steps=800_000_000)


def test_mixed_saves_keep_memory():
    """Saves and loads of mixed sizes leave extended memory where it was.

    KDOS's XMEM heap never joins free blocks, so a buffer allocated and
    freed at each record's size would leave holes behind and push
    XMEM-HERE up.  The record buffer grows to the largest block, here one
    of six transactions, and later saves and loads of every size reuse
    it; BLK-DECODE reuses its transaction buffers.  ALLOCATE takes its
    blocks from XMEM here, which HEAP-FREE-BYTES does not count, so the
    measure is XMEM-HERE less the bytes on the XMEM free list."""
    print("\n── Mixed saves ──\n")
    lines = _hybrid_blocks(('_BM', 6, 5), ('_BS', 1, 6)) + [
        ': _XFL  ( -- n )  0 XMEM-FL @ BEGIN ?DUP WHILE DUP @ ROT + SWAP 8 + @ REPEAT ;',
        ': _USED  ( -- n )  XMEM-HERE @ _XFL - ;',
        'VARIABLE _U0  VARIABLE _H0',
        f': _T {_PST_PREAMBLE}',
        '  _BM PST-SAVE-BLOCK DROP  0 _BL PST-LOAD-BLOCK DROP',
        '  _USED _U0 !  XMEM-HERE @ _H0 !',
        '  10 0 DO',
        '    _BS PST-SAVE-BLOCK DROP  CHAIN-HEAD PST-SAVE-BLOCK DROP',
        '    I 1 AND IF _BM PST-SAVE-BLOCK DROP THEN',
        '    PST-BLOCK-COUNT 1- _BL PST-LOAD-BLOCK DROP',
        '  LOOP',
        '  ." count=" PST-BLOCK-COUNT .',
        '  ." used=" _USED _U0 @ - .  ." here=" XMEM-HERE @ _H0 @ - .',
        '  ." load=" PST-BLOCK-COUNT 1- _BL PST-LOAD-BLOCK .',
        '  ." same=" _BL _BM _SAME .',
        '  ." small=" PST-BLOCK-COUNT 3 - _BL PST-LOAD-BLOCK .',
        '  ." same2=" _BL _BS _SAME . ; _T',
    ]
    check("26 saves of three sizes, no memory taken", lines,
          "count=26 used=0 here=0 load=-1 same=-1 small=-1 same2=-1 ",
          max_steps=600_000_000)


def test_full_chain_file_refuses_block():
    """A block the chain file cannot hold is refused whole.

    KDOS's FWRITE writes nothing past a file's sectors, so a save that did
    not fit wrote its length prefix and no block, reported success, and
    left the log holding a record the walk at PST-INIT misreads.  The save
    is refused before anything is written, and a block that fits still
    saves after it.  A chain file of 80 sectors holds two blocks of two
    hybrid transactions, about 16 KB each, and not a third."""
    print("\n── Full chain file ──\n")
    lines = _hybrid_blocks(('_B2', 2, 6)) + [
        ': _T 80 512 PST-SET-CAPACITY PST-INIT DROP',
        '  ." s1=" _B2 PST-SAVE-BLOCK .  ." s2=" _B2 PST-SAVE-BLOCK .',
        '  ." s3=" _B2 PST-SAVE-BLOCK .  ." count=" PST-BLOCK-COUNT .',
        '  ." small=" CHAIN-HEAD PST-SAVE-BLOCK .',
        '  PST-CLOSE PST-INIT DROP  ." reopened=" PST-BLOCK-COUNT .',
        '  ." load=" 2 _BL PST-LOAD-BLOCK .  ." h=" _BL BLK-HEIGHT@ .',
        '  ." load1=" 1 _BL PST-LOAD-BLOCK .  ." same=" _BL _B2 _SAME . ; _T',
    ]
    check("the third block does not fit and is refused", lines,
          "s1=-1 s2=-1 s3=0 count=2 small=-1 reopened=3 load=-1 h=0 "
          "load1=-1 same=-1 ")


def test_large_state_round_trip():
    """A state snapshot larger than 256 KB saves and loads back.

    3,585 accounts fill 15 pages of 256, a snapshot of 278,544 bytes.  The
    addresses count up, so each account goes at the end of the table."""
    print("\n── State over 256 KB ──\n")
    lines = [
        'CREATE _AD 32 ALLOT',
        # _ADDR! ( i -- )  _AD holds i big-endian in its last 8 bytes
        ': _ADDR!  ( i -- )  _AD 32 0 FILL',
        '  8 0 DO DUP 255 AND _AD 31 I - + C!  8 RSHIFT LOOP DROP ;',
        ': _ACCTS  ( n -- )  0 ?DO I _ADDR!  _AD I 1+ ST-CREATE DROP LOOP ;',
        ': _T 16 600 PST-SET-CAPACITY PST-INIT DROP',
        '  3585 _ACCTS  ." count=" ST-COUNT .',
        '  ." snap=" _PST-SNAP-ACTUAL DUP .  262144 > ." over=" .',
        '  ." save=" PST-SAVE-STATE .',
        '  ST-INIT DROP  ." wiped=" ST-COUNT .',
        '  ." load=" PST-LOAD-STATE .  ." count2=" ST-COUNT .',
        '  0 _ADDR! ." first=" _AD ST-BALANCE@ .',
        '  3584 _ADDR! ." last=" _AD ST-BALANCE@ . ; _T',
    ]
    check("a 15-page state round-trips", lines,
          "count=3585 snap=278544 over=-1 save=-1 wiped=0 load=-1 "
          "count2=3585 first=1 last=3585 ",
          max_steps=600_000_000)


# =====================================================================
#  Main
# =====================================================================


if __name__ == "__main__":
    run_file_tests(__file__)
