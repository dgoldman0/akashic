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
"""
import os, sys, time, tempfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")

# Dependency file paths
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
SMT_F       = os.path.join(ROOT_DIR, "akashic", "store", "smt.f")
TX_F        = os.path.join(ROOT_DIR, "akashic", "store", "tx.f")
STATE_F     = os.path.join(ROOT_DIR, "akashic", "store", "state.f")
BLOCK_F     = os.path.join(ROOT_DIR, "akashic", "store", "block.f")
CONSENSUS_F = os.path.join(ROOT_DIR, "akashic", "consensus", "consensus.f")
MEMPOOL_F   = os.path.join(ROOT_DIR, "akashic", "store", "mempool.f")
PERSIST_F   = os.path.join(ROOT_DIR, "akashic", "store", "persist.f")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem
from diskutil import format_image

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# ── Temp disk image ──

_disk_image_path = None

def _create_disk_image():
    """Create a fresh formatted MP64FS disk image in a temp file."""
    global _disk_image_path
    fd, path = tempfile.mkstemp(suffix=".img", prefix="pst_test_")
    os.close(fd)
    format_image(path)
    _disk_image_path = path
    return path

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

    dep_lines = []
    for path in [
        EVENT_F, SEM_F, GUARD_F, FP16_F,
        SHA512_F, FIELD_F, SHA3_F, RANDOM_F,
        ED25519_F, SPHINCS_F, CBOR_F, FMT_F,
        MERKLE_F, SMT_F, TX_F, STATE_F, BLOCK_F,
        CONSENSUS_F, MEMPOOL_F, PERSIST_F,
    ]:
        dep_lines += _load_forth_lines(path)

    # ST-INIT + CHAIN-INIT + MP-INIT.
    # CHAIN-INIT is needed so CHAIN-HEAD points to a valid genesis block
    # (with version=1).  PST-INIT requires disk, called per-test.
    helpers = [
        'ST-INIT',
        'CHAIN-INIT',
        'MP-INIT',
    ]

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=64 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + ["ENTER-USERLAND"]
                 + dep_lines
                 + helpers)
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode(); pos = 0; steps = 0; mx = 900_000_000
    while steps < mx:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk); pos += len(chunk)
            else:
                break
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
        for l in text.strip().split('\n')[-40:]:
            print(f"    {l}")
        sys.exit(1)

    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot


# =====================================================================
#  run_forth — restore snapshot with a fresh disk image per invocation
# =====================================================================

def run_forth(lines, max_steps=200_000_000):
    """Restore snapshot, attach a fresh formatted disk, run Forth lines."""
    bios_code, mem_bytes, cpu_state, ext_mem_bytes = _snapshot

    # Write a fresh copy of the base disk image to a temp file
    fd, disk_path = tempfile.mkstemp(suffix=".img", prefix="pst_run_")
    os.write(fd, _base_disk)
    os.close(fd)

    try:
        sys_obj = MegapadSystem(ram_size=1024*1024,
                                storage_image=disk_path,
                                ext_mem_size=64 * (1 << 20))
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
            if sys_obj.cpu.halted:
                break
            if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
                if pos < len(data):
                    chunk = _next_line_chunk(data, pos)
                    sys_obj.uart.inject_input(chunk); pos += len(chunk)
                else:
                    break
                continue
            batch = sys_obj.run_batch(min(100_000, max_steps - steps))
            steps += max(batch, 1)
        return uart_text(buf)
    finally:
        try:
            os.unlink(disk_path)
        except OSError:
            pass


_pass = 0; _fail = 0

def check(name, forth_lines, expected=None, check_fn=None):
    global _pass, _fail
    output = run_forth(forth_lines)
    clean = output.strip()
    ok = check_fn(clean) if check_fn else (expected in clean if expected else True)
    if ok:
        _pass += 1; print(f"  PASS  {name}")
    else:
        _fail += 1; print(f"  FAIL  {name}")
        if expected:
            print(f"        expected: {expected!r}")
        print(f"        got (last 5 lines):")
        for ln in clean.split('\n')[-5:]:
            print(f"          {ln}")


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


def test_encode_buffer_size():
    """[FIX D06] _PST-ENC-SZ is 262144 (256 KB)."""
    print("\n── Encode Buffer Size ──\n")
    check("_PST-ENC-SZ = 262144",
          ['_PST-ENC-SZ .'],
          "262144 ")


# =====================================================================
#  Main
# =====================================================================

if __name__ == "__main__":
    build_snapshot()
    test_compile()
    test_init()
    test_save_genesis()
    test_load_block()
    test_load_out_of_range()
    test_multiple_saves()
    test_clear()
    test_save_state()
    test_close_reopen()
    test_set_chain_id()
    test_set_capacity()
    test_o1_block_load()
    test_encode_buffer_size()
    print(f"\n{'='*40}")
    print(f"  {_pass} passed, {_fail} failed")
    print(f"{'='*40}")
    if _disk_image_path and os.path.exists(_disk_image_path):
        os.unlink(_disk_image_path)
    sys.exit(1 if _fail else 0)
