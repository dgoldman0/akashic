#!/usr/bin/env python3
"""Test suite for vfs-mp64fs.f — the MP64FS VFS binding.

These tests attach a formatted MP64FS disk image to the emulator,
load the VFS + binding, then exercise probe, init, readdir, read,
write, create, delete, sync, and teardown through the VFS API.
"""
import os, subprocess, sys, struct, tempfile, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
MEGAPAD_ROOT = os.path.abspath(os.path.join(ROOT_DIR, "..", "megapad"))

# Forth source paths
EVENT_F   = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
SEM_F     = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")
GUARD_F   = os.path.join(ROOT_DIR, "akashic", "concurrency", "guard.f")
UTF8_F    = os.path.join(ROOT_DIR, "akashic", "text", "utf8.f")
MEMORY_SPAN_F = os.path.join(ROOT_DIR, "akashic", "utils", "memory-span.f")
VFS_F     = os.path.join(ROOT_DIR, "akashic", "utils", "fs", "vfs.f")
VFS_MNT_F = os.path.join(ROOT_DIR, "akashic", "utils", "fs", "vfs-mount.f")
VFS_MP_F  = os.path.join(ROOT_DIR, "akashic", "utils", "fs", "drivers", "vfs-mp64fs.f")

sys.path.insert(0, MEGAPAD_ROOT)
from asm import assemble
from devices import (
    STORAGE_CMD_FLUSH,
    STORAGE_CMD_READ,
    STORAGE_CMD_WRITE,
    STORAGE_RESULT_FLUSH_FAILURE,
    STORAGE_RESULT_MEDIA_FAILURE,
)
from system import MegapadSystem

BIOS_PATH = os.path.join(MEGAPAD_ROOT, "bios.asm")
KDOS_PATH = os.path.join(MEGAPAD_ROOT, "kdos.f")

# ── Disk image builder ──────────────────────────────────────────────

SECTOR = 512
DIR_ENTRY_SIZE = 48
MAX_FILES = 128
DIR_SECTORS = 12
BMAP_START = 1
PARENT_ROOT = 0xFF
FTYPE_DIR = 8
FTYPE_RAW = 1
FTYPE_TEXT = 2
FTYPE_FORTH = 3

def make_entry(name, start_sec, sec_count, used_bytes, ftype, parent):
    """Build a 48-byte directory entry."""
    e = bytearray(DIR_ENTRY_SIZE)
    name_b = name.encode('ascii')[:23]
    e[:len(name_b)] = name_b
    struct.pack_into('<HH', e, 24, start_sec, sec_count)
    struct.pack_into('<I', e, 28, used_bytes)
    e[32] = ftype
    e[33] = 0  # flags
    e[34] = parent
    return bytes(e)

def build_disk_image(files, total_sectors=2048):
    """Build an MP64FS disk image.

    files: list of (name, parent, ftype, content_bytes)
    Returns bytes of the disk image.
    """
    bmap_sectors = (total_sectors + 4095) // 4096
    dir_start = BMAP_START + bmap_sectors
    data_start = dir_start + DIR_SECTORS
    entries = []
    data_sectors = []
    next_sec = data_start

    for name, parent, ftype, content in files:
        if ftype == FTYPE_DIR:
            entries.append(make_entry(name, 0, 0, 0, FTYPE_DIR, parent))
        else:
            cb = content if isinstance(content, bytes) else content.encode('utf-8')
            n = max(1, (len(cb) + SECTOR - 1) // SECTOR)
            entries.append(make_entry(name, next_sec, n, len(cb), ftype, parent))
            data_sectors.append((next_sec, cb + b'\x00' * (n * SECTOR - len(cb))))
            next_sec += n

    # Superblock
    sb = bytearray(SECTOR)
    sb[0:4] = b'MP64'
    struct.pack_into('<H', sb, 4, 1)
    struct.pack_into('<I', sb, 6, total_sectors)  # total_sectors (u32)
    struct.pack_into('<H', sb, 10, BMAP_START)
    struct.pack_into('<H', sb, 12, bmap_sectors)
    struct.pack_into('<H', sb, 14, dir_start)
    struct.pack_into('<H', sb, 16, DIR_SECTORS)
    struct.pack_into('<H', sb, 18, data_start)
    sb[20] = MAX_FILES
    sb[21] = DIR_ENTRY_SIZE

    # Bitmap
    bmap = bytearray(bmap_sectors * SECTOR)
    for s in range(data_start):
        bmap[s // 8] |= (1 << (s % 8))
    for ss, p in data_sectors:
        for s in range(ss, ss + len(p) // SECTOR):
            bmap[s // 8] |= (1 << (s % 8))

    # Directory
    dd = bytearray(DIR_SECTORS * SECTOR)
    for i, e in enumerate(entries):
        dd[i * DIR_ENTRY_SIZE : i * DIR_ENTRY_SIZE + DIR_ENTRY_SIZE] = e

    ts = max(next_sec, total_sectors)
    img = bytearray(ts * SECTOR)
    img[0:SECTOR] = sb
    img[SECTOR:(1 + bmap_sectors) * SECTOR] = bmap
    img[dir_start * SECTOR : (dir_start + DIR_SECTORS) * SECTOR] = dd
    for ss, p in data_sectors:
        img[ss * SECTOR : ss * SECTOR + len(p)] = p
    return bytes(img)


def build_malformed_entry_image(kind):
    """Build one geometry-valid image with a specifically invalid dirent."""
    is_dir = kind == "directory-data"
    image = bytearray(build_disk_image([
        ("bad-dir" if is_dir else "victim", PARENT_ROOT,
         FTYPE_DIR if is_dir else FTYPE_RAW,
         b"" if is_dir else b"protected"),
    ]))
    total = len(image) // SECTOR
    bmap_sectors = (total + 4095) // 4096
    data_start = 1 + bmap_sectors + DIR_SECTORS
    de = (1 + bmap_sectors) * SECTOR
    start = struct.unpack_from('<H', image, de + 24)[0]

    if kind == "start-before-data":
        struct.pack_into('<H', image, de + 24, data_start - 1)
    elif kind == "end-after-media":
        struct.pack_into('<HH', image, de + 24, total - 1, 2)
    elif kind == "used-over-capacity":
        struct.pack_into('<I', image, de + 28, SECTOR + 1)
    elif kind == "secondary-zero-pair":
        struct.pack_into('<H', image, de + 44, start + 1)
    elif kind == "invalid-parent":
        image[de + 34] = MAX_FILES - 1
    elif kind == "bitmap-unclaimed":
        image[SECTOR + start // 8] &= ~(1 << (start % 8)) & 0xFF
    elif kind == "directory-data":
        struct.pack_into('<HHI', image, de + 24, data_start, 1, 1)
        image[SECTOR + data_start // 8] |= 1 << (data_start % 8)
    else:
        raise ValueError(kind)
    return bytes(image)


def build_overlapping_extent_image(kind):
    """Build an otherwise-valid image with duplicate sector ownership."""
    image = bytearray(build_disk_image([
        ("first.bin", PARENT_ROOT, FTYPE_RAW, b"first"),
        ("second.bin", PARENT_ROOT, FTYPE_RAW, b"second"),
    ]))
    total = len(image) // SECTOR
    bmap_sectors = (total + 4095) // 4096
    directory = (1 + bmap_sectors) * SECTOR
    first = directory
    second = directory + DIR_ENTRY_SIZE
    first_start = struct.unpack_from('<H', image, first + 24)[0]
    if kind == "within-file":
        struct.pack_into('<HH', image, first + 44, first_start, 1)
    elif kind == "between-files":
        struct.pack_into('<H', image, second + 24, first_start)
    else:
        raise ValueError(kind)
    return bytes(image)


def build_stale_tail_image(fill=0xA5):
    """Build a short file whose allocated-but-invisible tail is nonzero."""
    image = bytearray(build_disk_image([
        ("hello.txt", PARENT_ROOT, FTYPE_TEXT, b"Hello, VFS world!"),
    ]))
    bmap_sectors = (len(image) // SECTOR + 4095) // 4096
    directory = (1 + bmap_sectors) * SECTOR
    start = struct.unpack_from('<H', image, directory + 24)[0]
    used = struct.unpack_from('<I', image, directory + 28)[0]
    image[start * SECTOR + used:(start + 1) * SECTOR] = bytes([fill]) * (SECTOR - used)
    return bytes(image), start, used


def build_stale_free_sector_image(fill=0xCC):
    """Build a volume whose first free sector contains old media bytes."""
    image, start, _ = build_stale_tail_image()
    image = bytearray(image)
    free_sector = start + 1
    image[free_sector * SECTOR:(free_sector + 1) * SECTOR] = bytes([fill]) * SECTOR
    return bytes(image), free_sector


def build_last_slot_image():
    """Move one valid root entry to the final directory slot."""
    image = bytearray(build_disk_image([
        ("last.bin", PARENT_ROOT, FTYPE_RAW, b"last"),
    ]))
    bmap_sectors = (len(image) // SECTOR + 4095) // 4096
    directory = (1 + bmap_sectors) * SECTOR
    entry = bytes(image[directory:directory + DIR_ENTRY_SIZE])
    image[directory:directory + DIR_ENTRY_SIZE] = bytes(DIR_ENTRY_SIZE)
    final = directory + (MAX_FILES - 1) * DIR_ENTRY_SIZE
    image[final:final + DIR_ENTRY_SIZE] = entry
    return bytes(image)


# ── Emulator helpers ─────────────────────────────────────────────────

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


# ── Snapshot ──

_snapshot = None
_img_path = None   # disk image path shared by all tests

def _build_default_image():
    """Build a default test disk with a few files + subdirectory."""
    global _img_path
    files = [
        ("hello.txt",  PARENT_ROOT, FTYPE_TEXT,  b"Hello, VFS world!"),
        ("data.bin",   PARENT_ROOT, FTYPE_RAW,   bytes(range(256)) * 4),  # 1024 bytes
        ("docs",       PARENT_ROOT, FTYPE_DIR,   b""),
        ("readme.txt", 2,           FTYPE_TEXT,  b"Inside docs directory"),
    ]
    img = build_disk_image(files)
    fd, path = tempfile.mkstemp(suffix='.img')
    os.write(fd, img)
    os.close(fd)
    _img_path = path
    return img

def build_snapshot():
    global _snapshot
    if _snapshot:
        return _snapshot
    print("[*] Building snapshot: BIOS + KDOS + VFS + MP64FS binding ...")
    t0 = time.time()

    _build_default_image()

    bios_code  = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)

    dep_lines = []
    for path in [
        EVENT_F, SEM_F, GUARD_F, UTF8_F, MEMORY_SPAN_F,
        VFS_F, VFS_MNT_F, VFS_MP_F,
    ]:
        dep_lines += _load_forth_lines(path)

    helpers = [
        # Read buffer
        'CREATE _RB 4096 ALLOT',
        # Write buffer
        'CREATE _WB 4096 ALLOT',
        # VFS init helper: create MP64FS VFS
        'CREATE _TBD /BLOCK-DEVICE ALLOT',
        'CREATE _TVOL /VOLUME ALLOT',
        'VARIABLE _TVOL-READY',
        'VARIABLE _TARN',
        ': T-VOLUME  ( -- volume )',
        '    _TVOL-READY @ 0= IF',
        '        _TBD BD-OPEN THROW',
        '        _TBD _TVOL VOL-RAW THROW',
        '        -1 _TVOL-READY !',
        '    THEN',
        '    _TVOL ;',
        ': T-ARENA  ( -- arena )',
        '    524288 A-XMEM ARENA-NEW THROW ;',
        ': T-VMP-NEW  ( -- vfs )',
        '    T-ARENA _TARN !',
        '    _TARN @ T-VOLUME VMP-NEW THROW ;',
    ]

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20),
                            storage_image=_img_path)
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = kdos_lines + ["ENTER-USERLAND"] + dep_lines + helpers
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode(); pos = 0; steps = 0; mx = 800_000_000
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
        lo = l.lower()
        if '?' in l and ('not found' in lo or 'undefined' in lo):
            errors.append(l.strip())
            print(f"  [!] {l.strip()}")
    if errors:
        print(f"  [FATAL] {len(errors)} errors during load!")
        for l in text.strip().split('\n')[-40:]:
            print(f"    {l}")
        sys.exit(1)
    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem), bytes(sys_obj.storage._image_data))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot


def run_forth(lines, max_steps=800_000_000, disk_image=None,
              storage_faults=None):
    """Run Forth code from the saved snapshot.

    If disk_image (bytes) is provided, replace the storage image before running.
    Otherwise uses the snapshot's saved disk image.
    """
    if _snapshot is None:
        build_snapshot()
    bios_code, mem_bytes, cpu_state, ext_mem_bytes, storage_bytes = _snapshot

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20),
                            storage_image=_img_path)
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
    # Restore or replace disk image
    img = disk_image if disk_image else storage_bytes
    sys_obj.storage._image_data[:len(img)] = img
    sys_obj.storage._capacity_sectors = len(img) // SECTOR
    sys_obj.storage.media_generation = (
        sys_obj.storage.media_generation + 1
    ) & 0xFFFF_FFFF
    for fault in storage_faults or ():
        sys_obj.storage.inject_fault(**fault)
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
    return uart_text(buf), sys_obj


def run_fresh_forth(image_path, lines, max_steps=800_000_000):
    """Boot and load the complete MP64FS test stack without a saved snapshot.

    This deliberately owns only ``MegapadSystem`` rather than a
    ``MachineSession``.  Process exit therefore cannot persist storage through
    the session-close convenience path; any bytes visible to another process
    crossed the guest's checked FLUSH boundary.
    """
    bios_code = _load_bios()
    load_lines = _load_forth_lines(KDOS_PATH) + ["ENTER-USERLAND"]
    for path in [
        EVENT_F, SEM_F, GUARD_F, UTF8_F, MEMORY_SPAN_F,
        VFS_F, VFS_MNT_F, VFS_MP_F,
    ]:
        load_lines += _load_forth_lines(path)
    load_lines += [
        'CREATE _RB 4096 ALLOT',
        'CREATE _WB 4096 ALLOT',
        'CREATE _TBD /BLOCK-DEVICE ALLOT',
        'CREATE _TVOL /VOLUME ALLOT',
        'VARIABLE _TVOL-READY',
        'VARIABLE _TARN',
        ': T-VOLUME  ( -- volume )',
        '    _TVOL-READY @ 0= IF',
        '        _TBD BD-OPEN THROW',
        '        _TBD _TVOL VOL-RAW THROW',
        '        -1 _TVOL-READY !',
        '    THEN',
        '    _TVOL ;',
        ': T-ARENA  ( -- arena )',
        '    524288 A-XMEM ARENA-NEW THROW ;',
        ': T-VMP-NEW  ( -- vfs )',
        '    T-ARENA _TARN !',
        '    _TARN @ T-VOLUME VMP-NEW THROW ;',
    ]

    sys_obj = MegapadSystem(
        ram_size=1024 * 1024,
        ext_mem_size=16 * (1 << 20),
        storage_image=image_path,
    )
    output = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    payload = ("\n".join(load_lines + list(lines) + ["BYE"]) + "\n").encode()
    pos = 0
    steps = 0
    while steps < max_steps:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(payload):
                chunk = _next_line_chunk(payload, pos)
                sys_obj.uart.inject_input(chunk)
                pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)
    return uart_text(output)


def _cold_worker(phase, image_path):
    if phase == "write":
        lines = [
            'T-VMP-NEW CONSTANT _V',
            '_V VFS-USE',
            'S" /hello.txt" VFS-OPEN CONSTANT _FD',
            'S" COLD-PERSISTED" _FD VFS-WRITE . ." <wrote "',
            '_V VFS-SYNC . ." <sync WRITE-DONE"',
        ]
    elif phase == "read":
        lines = [
            'T-VMP-NEW CONSTANT _V',
            '_V VFS-USE',
            'S" /hello.txt" VFS-OPEN CONSTANT _FD',
            '_RB 14 _FD VFS-READ . ." <read "',
            '_RB 14 TYPE ."  READ-DONE"',
        ]
    else:
        raise ValueError(f"unknown cold-worker phase {phase!r}")
    print(run_fresh_forth(image_path, lines), end="")


def _run_cold_subprocess(phase, image_path):
    result = subprocess.run(
        [sys.executable, os.path.abspath(__file__), "--cold-worker", phase,
         image_path],
        check=False,
        capture_output=True,
        text=True,
        timeout=180,
    )
    if result.returncode:
        raise AssertionError(
            f"cold {phase} worker failed ({result.returncode}):\n"
            f"{result.stdout}\n{result.stderr}"
        )
    return result.stdout


# ── Test framework ───────────────────────────────────────────────────

_pass_count = 0
_fail_count = 0

def check(name, forth_lines, expected, disk_image=None, storage_faults=None):
    global _pass_count, _fail_count
    output, _ = run_forth(
        forth_lines,
        disk_image=disk_image,
        storage_faults=storage_faults,
    )
    clean = output.strip()
    if expected in clean:
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}")
        # Show last 20 lines for debugging
        for l in clean.split('\n')[-20:]:
            print(f"        {l}")


# =====================================================================
#  Tests
# =====================================================================

def test_constructor_binds_and_mounts_volume():
    """The public constructor is the single successful mount boundary."""
    check("constructor binds and mounts volume", [
        'T-ARENA CONSTANT _AR',
        '_AR T-VOLUME VMP-NEW CONSTANT _IOR CONSTANT _V',
        '_IOR 0=',
        '_V 0<> AND',
        '_V V.LIFECYCLE @ VFS-L-MOUNTED = AND',
        '_V V.VOLUME @ T-VOLUME = AND',
        'VMP-BINDING VFS-BINDING-VALID? AND',
        '_V VFS-CAPS@ VFS-CAP-PROBE AND 0<> AND',
        '_V V.BINDING @ VB.FLAGS @ VFS-BF-STABLE-IDS AND 0= AND',
        'IF ." CONSTRUCTOR-OK" THEN',
    ], "CONSTRUCTOR-OK")


def test_volume_probe_match_nonmatch_and_io_error():
    """ABI-1 PROBE reads only its volume and preserves checked failures."""
    check("MP probe match", [
        'VMP-BINDING T-VOLUME VFS-PROBE CONSTANT _IOR CONSTANT _SCORE',
        '_IOR 0= _SCORE VMP-PROBE-SCORE = AND IF ." MP-PROBE-MATCH" THEN',
    ], "MP-PROBE-MATCH")

    nonmatch = bytearray(build_disk_image([]))
    nonmatch[:4] = b"NOPE"
    check("MP probe nonmatch", [
        'VMP-BINDING T-VOLUME VFS-PROBE CONSTANT _IOR CONSTANT _SCORE',
        '_IOR 0= _SCORE 0= AND IF ." MP-PROBE-NOMATCH" THEN',
    ], "MP-PROBE-NOMATCH", disk_image=bytes(nonmatch))

    check("MP probe checked I/O error", [
        'VMP-BINDING T-VOLUME VFS-PROBE CONSTANT _IOR CONSTANT _SCORE',
        '_SCORE 0=',
        '_IOR VFS-IOR-REASON VFS-R-IO = AND',
        '_IOR VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = AND',
        '_IOR VFS-IOR-DETAIL 0<> AND',
        'IF ." MP-PROBE-IO-ERROR" THEN',
    ], "MP-PROBE-IO-ERROR", storage_faults=[{
        "stage": "start",
        "result": STORAGE_RESULT_MEDIA_FAILURE,
        "command": STORAGE_CMD_READ,
    }])


def test_constructor_requires_volume():
    """A volume-required binding rejects an absent attachment directly."""
    check("constructor requires volume", [
        'T-ARENA 0 VMP-NEW CONSTANT _IOR CONSTANT _V',
        '_V 0= _IOR VFS-IOR-REASON VFS-R-NOVOLUME = AND',
        'IF ." NOVOLUME-OK" THEN',
    ], "NOVOLUME-OK")


def test_constructor_propagates_checked_read_failure():
    """Mount exposes the checked-volume error instead of parsing stale bytes."""
    check("constructor checked-read failure", [
        'T-ARENA T-VOLUME VMP-NEW CONSTANT _IOR CONSTANT _V',
        '_V 0<>',
        '_IOR VFS-IOR-REASON VFS-R-IO = AND',
        '_IOR VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = AND',
        '_IOR VFS-IOR-DETAIL 0<> AND',
        'IF ." CHECKED-READ-ERROR-OK" THEN',
    ], "CHECKED-READ-ERROR-OK", storage_faults=[{
        "stage": "start",
        "result": STORAGE_RESULT_MEDIA_FAILURE,
        "command": STORAGE_CMD_READ,
    }])


def test_constructor_adopts_volume_geometry():
    """Mount adopts geometry from an explicitly sized 8192-sector volume."""
    image = build_disk_image([], total_sectors=8192)
    check("constructor adopts geometry", [
        'T-ARENA T-VOLUME VMP-NEW CONSTANT _IOR CONSTANT _V',
        '_IOR 0=',
        '_V V.BCTX @ DUP _VMP-C.TOTAL + @ 8192 = AND',
        'DUP _VMP-C.BN + @ 2 = AND',
        'DUP _VMP-C.DIRSTART + @ 3 = AND',
        '_VMP-C.DSTART + @ 15 = AND',
        'IF ." GEOMETRY-OK" THEN',
    ], "GEOMETRY-OK", disk_image=image)


def test_constructor_rejects_malformed_media():
    """Every on-disk invariant is rejected at constructor time."""
    bad_magic = bytearray(build_disk_image([], total_sectors=8192))
    bad_magic[:4] = b"NOPE"

    bad_geometry = bytearray(build_disk_image([], total_sectors=8192))
    struct.pack_into('<H', bad_geometry, 14, 4)

    bad_marker = bytearray(build_disk_image([], total_sectors=8192))
    struct.pack_into('<H', bad_marker, 4, 2)

    unreserved = bytearray(build_disk_image([], total_sectors=8192))
    unreserved[SECTOR] &= 0xFE

    cases = [
        ("magic", bytes(bad_magic), 11, 1),
        ("geometry", bytes(bad_geometry), 10, 2),
        ("marker", bytes(bad_marker), 10, 2),
        ("unreserved-metadata", bytes(unreserved), 10, 3),
    ]
    cases.extend(
        (f"dirent-{kind}", build_malformed_entry_image(kind), 10, 4)
        for kind in (
            "start-before-data",
            "end-after-media",
            "used-over-capacity",
            "secondary-zero-pair",
            "invalid-parent",
            "bitmap-unclaimed",
            "directory-data",
        )
    )
    cases.extend((
        ("extent-overlap-within-file",
         build_overlapping_extent_image("within-file"), 10, 4),
        ("extent-overlap-between-files",
         build_overlapping_extent_image("between-files"), 10, 4),
    ))
    for name, image, reason, detail in cases:
        corrupt_flag_check = (
            '_IOR VFS-IOR-FLAGS VFS-IOR-F-CORRUPT AND 0<> AND'
            if reason == 10 else ''
        )
        check(f"constructor rejects {name}", [
            'T-ARENA T-VOLUME VMP-NEW CONSTANT _IOR CONSTANT _V',
            '_V 0<>',
            f'_IOR VFS-IOR-REASON {reason} = AND',
            '_IOR VFS-IOR-DOMAIN VFS-IOR-D-FORMAT = AND',
            f'_IOR VFS-IOR-DETAIL {detail} = AND',
            corrupt_flag_check,
            'IF ." FORMAT-REJECT-OK" THEN',
        ], "FORMAT-REJECT-OK", disk_image=image)


def test_constructor_reports_core_arena_exhaustion():
    """Core allocation failure is returned as structured NOMEM."""
    check("constructor core arena exhaustion", [
        '8192 A-XMEM ARENA-NEW THROW CONSTANT _AR',
        '_AR T-VOLUME VMP-NEW CONSTANT _IOR CONSTANT _V',
        '_V 0= _IOR VFS-IOR-REASON VFS-R-NOMEM = AND',
        'IF ." CORE-NOMEM-OK" THEN',
    ], "CORE-NOMEM-OK")


def test_final_directory_slot_mounts_without_pair_loop_wrap():
    """The overlap pair scan handles an occupied final slot safely."""
    check("final directory slot", [
        'T-VMP-NEW CONSTANT _V',
        'S" /last.bin" _V VFS-RESOLVE DUP IF',
        f'  IN.BID @ {MAX_FILES - 1} =',
        'ELSE DROP FALSE THEN',
        'IF ." FINAL-SLOT-OK" THEN',
    ], "FINAL-SLOT-OK", disk_image=build_last_slot_image())


def test_root_and_lazy_subdirectory_reads():
    """Mounted root and lazy subdirectory dentries resolve and read."""
    check("root and lazy subdirectory reads", [
        'T-VMP-NEW CONSTANT _V',
        'S" /hello.txt" VFS-FF-READ _V VFS-OPEN? THROW CONSTANT _HF',
        '_RB 17 _HF VFS-READ? THROW 17 =',
        '_RB 17 S" Hello, VFS world!" COMPARE 0= AND',
        'S" /docs/readme.txt" VFS-FF-READ _V VFS-OPEN? THROW CONSTANT _RF',
        '_RB 21 _RF VFS-READ? THROW 21 = AND',
        '_RB 21 S" Inside docs directory" COMPARE 0= AND',
        'IF ." TREE-READ-OK" THEN',
    ], "TREE-READ-OK")


def test_binary_read_and_offset():
    """Binary sizes and nonzero offsets survive the binding callback ABI."""
    check("binary read and offset", [
        'T-VMP-NEW CONSTANT _V',
        'S" /data.bin" VFS-FF-READ _V VFS-OPEN? THROW CONSTANT _BF',
        '_BF VFS-SIZE 1024 =',
        '250 _BF VFS-SEEK',
        '_RB 20 _BF VFS-READ? THROW 20 = AND',
        '_RB C@ 250 = AND _RB 6 + C@ 0= AND',
        'IF ." OFFSET-READ-OK" THEN',
    ], "OFFSET-READ-OK")


def test_create_write_read_delete_and_sync():
    """The writable binding completes a normal mutation lifecycle."""
    check("create write read delete sync", [
        'T-VMP-NEW CONSTANT _V',
        'S" made.txt" _V VFS-MKFILE? THROW DROP',
        'S" /made.txt" VFS-FF-READ VFS-FF-WRITE OR _V '
        'VFS-OPEN? THROW CONSTANT _FD',
        'S" persisted" _FD VFS-WRITE? THROW 9 =',
        '_FD VFS-REWIND',
        '_RB 9 _FD VFS-READ? THROW 9 = AND',
        '_RB 9 S" persisted" COMPARE 0= AND',
        '_FD VFS-CLOSE? THROW',
        '_V VFS-SYNC 0= AND',
        'S" /made.txt" _V VFS-RM 0= AND',
        'S" /made.txt" _V VFS-RESOLVE 0= AND',
        'IF ." MUTATION-OK" THEN',
    ], "MUTATION-OK")


def test_create_zeroes_newly_allocated_sector():
    """Create claims a sector only after old media bytes are zeroed."""
    global _pass_count, _fail_count
    image, free_sector = build_stale_free_sector_image()
    output, sys_obj = run_forth([
        'T-VMP-NEW CONSTANT _V',
        'S" fresh.bin" _V VFS-MKFILE? THROW DUP',
        f'IN.BDATA @ {free_sector} = IF ." CREATE-SECTOR-OK" THEN DROP',
    ], disk_image=image)
    media = bytes(sys_obj.storage._image_data)
    sector = media[free_sector * SECTOR:(free_sector + 1) * SECTOR]
    ok = "CREATE-SECTOR-OK" in output and sector == bytes(SECTOR)
    if ok:
        _pass_count += 1
        print("  PASS  create zeroes allocated sector")
    else:
        _fail_count += 1
        print("  FAIL  create zeroes allocated sector")
        print("        sector zero:", sector == bytes(SECTOR))
        print("        output:", output[-1500:])


def test_seek_gap_and_truncate_growth_zero_visible_ranges():
    """Neither sparse writes nor truncate growth expose an old sector tail."""
    image, _, used = build_stale_tail_image()
    zero_word = (
        ': _ZERO? ( a u -- f ) TRUE -ROT 0 DO '
        'DUP I + C@ IF 2DROP FALSE UNLOOP EXIT THEN LOOP DROP ;'
    )
    check("seek gap zero fill", [
        zero_word,
        'T-VMP-NEW CONSTANT _V',
        'S" /hello.txt" VFS-FF-READ VFS-FF-WRITE OR _V '
        'VFS-OPEN? THROW CONSTANT _FD',
        '100 _FD VFS-SEEK',
        'S" Z" _FD VFS-WRITE? THROW 1 =',
        '_FD VFS-REWIND',
        '_RB 101 _FD VFS-READ? THROW 101 = AND',
        f'_RB {used} + {100 - used} _ZERO? AND',
        '_RB 100 + C@ [CHAR] Z = AND',
        'IF ." SEEK-GAP-ZERO-OK" THEN',
    ], "SEEK-GAP-ZERO-OK", disk_image=image)

    check("truncate growth zero fill", [
        zero_word,
        'T-VMP-NEW CONSTANT _V',
        'S" /hello.txt" VFS-FF-READ VFS-FF-WRITE OR _V '
        'VFS-OPEN? THROW CONSTANT _FD',
        '1024 _FD VFS-TRUNCATE 0=',
        '_FD VFS-REWIND',
        '_RB 1024 _FD VFS-READ? THROW 1024 = AND',
        f'_RB {used} + {1024 - used} _ZERO? AND',
        'IF ." TRUNCATE-ZERO-OK" THEN',
    ], "TRUNCATE-ZERO-OK", disk_image=image)


def test_zeroing_failures_do_not_publish_size_or_extent():
    """Failed gap/allocation zeroing leaves logical metadata unchanged."""
    image, _, used = build_stale_tail_image()
    fault = [{
        "stage": "start",
        "result": STORAGE_RESULT_MEDIA_FAILURE,
        "command": STORAGE_CMD_WRITE,
    }]
    check("gap zero failure is not published", [
        'T-VMP-NEW CONSTANT _V',
        'S" /hello.txt" VFS-FF-READ VFS-FF-WRITE OR _V '
        'VFS-OPEN? THROW CONSTANT _FD',
        '100 _FD VFS-SEEK',
        'S" Z" _FD VFS-WRITE? CONSTANT _IOR CONSTANT _ACT',
        '_ACT 0= _IOR VFS-IOR-REASON VFS-R-IO = AND',
        f'_FD VFS-SIZE {used} = AND',
        f'_FD FD.INODE @ IN.BID @ _V V.BCTX @ _VMP-DIRENT '
        f'_VMP-DE.USED {used} = AND',
        'IF ." GAP-FAIL-NOT-PUBLISHED" THEN',
    ], "GAP-FAIL-NOT-PUBLISHED", disk_image=image, storage_faults=fault)

    check("allocation zero failure is not published", [
        'T-VMP-NEW CONSTANT _V',
        'S" /hello.txt" VFS-FF-READ VFS-FF-WRITE OR _V '
        'VFS-OPEN? THROW CONSTANT _FD',
        '1024 _FD VFS-TRUNCATE CONSTANT _IOR',
        '_IOR VFS-IOR-REASON VFS-R-IO =',
        f'_FD VFS-SIZE {used} = AND',
        '_FD FD.INODE @ IN.BID @ _V V.BCTX @ _VMP-DIRENT',
        f'DUP _VMP-DE.USED {used} = AND',
        '_VMP-DE.COUNT 1 = AND',
        'IF ." ALLOC-FAIL-NOT-PUBLISHED" THEN',
    ], "ALLOC-FAIL-NOT-PUBLISHED", disk_image=image, storage_faults=fault)


def test_second_bitmap_sector_sync_and_remount():
    """Allocation above sector 4096 survives sync and a second mount."""
    image = build_disk_image([
        ("prefix.bin", PARENT_ROOT, FTYPE_RAW, bytes(4100 * SECTOR)),
    ], total_sectors=8192)
    check("second bitmap sector sync and remount", [
        'T-VMP-NEW CONSTANT _V',
        'S" high.bin" _V VFS-MKFILE? THROW DUP IN.BDATA @ 4115 = SWAP DROP',
        '_V VFS-SYNC 0= AND',
        'T-VMP-NEW CONSTANT _VR',
        'S" /high.bin" _VR VFS-RESOLVE DUP 0<> IF',
        '  IN.BDATA @ 4115 = AND',
        'ELSE DROP FALSE THEN',
        'IF ." HIGH-ALLOC-OK" THEN',
    ], "HIGH-ALLOC-OK", disk_image=image)


def test_sync_retains_dirty_metadata_until_flush_succeeds():
    """A failed checked FLUSH leaves metadata retryable and dirty."""
    check("sync retains dirty metadata", [
        'T-VMP-NEW CONSTANT _V',
        'S" /hello.txt" VFS-FF-READ VFS-FF-WRITE OR _V '
        'VFS-OPEN? THROW CONSTANT _FD',
        'S" RETRY" _FD VFS-WRITE? THROW DROP',
        'VARIABLE _S1 VARIABLE _D1 VARIABLE _S2 VARIABLE _D2',
        '_FD FD.INODE @ _V _VMP-SYNC DUP _S1 ! DROP',
        '_V V.BCTX @ _VMP-C.DDIR + @ _D1 !',
        '_FD FD.INODE @ _V _VMP-SYNC DUP _S2 ! DROP',
        '_V V.BCTX @ _VMP-C.DDIR + @ _D2 !',
        '_S1 @ VFS-IOR-REASON VFS-R-IO =',
        '_S1 @ VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = AND',
        '_D1 @ 0<> AND _S2 @ 0= AND _D2 @ 0= AND',
        'IF ." FLUSH-RETRY-OK" THEN',
    ], "FLUSH-RETRY-OK", storage_faults=[{
        "stage": "flush",
        "result": STORAGE_RESULT_FLUSH_FAILURE,
        "command": STORAGE_CMD_FLUSH,
    }])


def test_two_instances_share_only_explicit_volume():
    """Two contexts independently mount the same explicit volume object."""
    check("two explicit-volume instances", [
        'T-VMP-NEW CONSTANT _VA',
        'T-VMP-NEW CONSTANT _VB',
        '_VA V.VOLUME @ _VB V.VOLUME @ =',
        '_VA V.BCTX @ _VB V.BCTX @ <> AND',
        'S" /hello.txt" _VA VFS-RESOLVE 0<> AND',
        'S" /hello.txt" _VB VFS-RESOLVE 0<> AND',
        'IF ." TWO-VOLUME-BOUND-OK" THEN',
    ], "TWO-VOLUME-BOUND-OK")


def test_empty_formatted_volume_mounts():
    """An empty but valid MP64FS volume mounts with an empty root."""
    check("empty formatted volume", [
        'T-ARENA T-VOLUME VMP-NEW CONSTANT _IOR CONSTANT _V',
        '_IOR 0= _V V.ROOT @ IN.CHILD @ 0= AND',
        'IF ." EMPTY-MOUNT-OK" THEN',
    ], "EMPTY-MOUNT-OK", disk_image=build_disk_image([]))


def test_checked_sync_survives_fresh_process_without_session_close():
    """Guest WRITE+FLUSH is visible after destroying the emulator process."""
    global _pass_count, _fail_count
    fd, image_path = tempfile.mkstemp(suffix=".img")
    try:
        image = build_disk_image([
            ("hello.txt", PARENT_ROOT, FTYPE_TEXT, b"original-contents"),
        ])
        os.write(fd, image)
        os.close(fd)
        fd = -1

        first = _run_cold_subprocess("write", image_path)
        second = _run_cold_subprocess("read", image_path)
        ok = (
            "14 <wrote" in first
            and "0 <sync WRITE-DONE" in first
            and "14 <read" in second
            and "COLD-PERSISTED READ-DONE" in second
        )
        if ok:
            _pass_count += 1
            print("  PASS  checked sync cold process")
        else:
            _fail_count += 1
            print("  FAIL  checked sync cold process")
            print("        writer:", first[-1000:])
            print("        reader:", second[-1000:])
    finally:
        if fd >= 0:
            os.close(fd)
        if os.path.exists(image_path):
            os.unlink(image_path)


def test_nonzero_bounded_volume_slice_end_to_end():
    """A nonzero VOL-SLICE bounds reads, writes, and metadata sync."""
    global _pass_count, _fail_count
    base = 7
    suffix = 5
    inner = build_disk_image([
        ("hello.txt", PARENT_ROOT, FTYPE_TEXT, b"inside-slice"),
    ], total_sectors=2048)
    prefix_bytes = bytes([0xA5]) * (base * SECTOR)
    suffix_bytes = bytes([0x5A]) * (suffix * SECTOR)
    parent_image = prefix_bytes + inner + suffix_bytes
    output, sys_obj = run_forth([
        'CREATE _SBD /BLOCK-DEVICE ALLOT',
        'CREATE _SVOL /VOLUME ALLOT',
        '_SBD BD-OPEN THROW',
        f'{base} 2048 VOL-SCHEME-RAW 0 _SBD _SVOL VOL-SLICE THROW',
        'T-ARENA _SVOL VMP-NEW THROW CONSTANT _SV',
        'S" /hello.txt" VFS-FF-READ VFS-FF-WRITE OR _SV '
        'VFS-OPEN? THROW CONSTANT _SFD',
        'S" SLICE" DROP 5 _SFD VFS-WRITE? THROW 5 = IF '
        '." WRITE-OK " THEN',
        '_SV VFS-SYNC THROW ." SYNC-OK "',
        '_SFD VFS-REWIND',
        '_RB 5 _SFD VFS-READ? THROW DROP _RB 5 TYPE',
    ], disk_image=parent_image)
    media = bytes(sys_obj.storage._image_data)
    slice_end = (base + 2048) * SECTOR
    guards_ok = (
        media[:base * SECTOR] == prefix_bytes
        and media[slice_end:slice_end + len(suffix_bytes)] == suffix_bytes
    )
    ok = all(marker in output for marker in ("WRITE-OK", "SYNC-OK", "SLICE"))
    ok = ok and guards_ok
    if ok:
        _pass_count += 1
        print("  PASS  nonzero bounded volume slice")
    else:
        _fail_count += 1
        print("  FAIL  nonzero bounded volume slice")
        print("        guards:", guards_ok)
        print("        output:", output[-1500:])


def test_open_unlink_is_busy_until_close():
    """A reusable directory slot cannot retire while an FD references it."""
    check("open unlink is busy", [
        'T-VMP-NEW CONSTANT _V',
        'VARIABLE _BUSY VARIABLE _PRESENT VARIABLE _REMOVED',
        'S" /hello.txt" VFS-FF-READ _V VFS-OPEN? THROW CONSTANT _FD',
        'S" /hello.txt" _V VFS-RM VFS-IOR-REASON _BUSY !',
        'S" /hello.txt" _V VFS-RESOLVE 0<> _PRESENT !',
        '_FD VFS-CLOSE? THROW',
        'S" /hello.txt" _V VFS-RM _REMOVED !',
        '_BUSY @ VFS-R-BUSY = _PRESENT @ AND _REMOVED @ 0= AND IF',
        '  ." BUSY-GUARD-OK"',
        'THEN',
    ], "BUSY-GUARD-OK")


def test_open_rename_victim_is_busy():
    """Rename-replace cannot reuse an open victim's directory slot."""
    check("open rename victim is busy", [
        'T-VMP-NEW CONSTANT _V',
        'VARIABLE _BUSY VARIABLE _SOURCE VARIABLE _VICTIM',
        'S" source.txt" _V VFS-MKFILE? THROW CONSTANT _SRC',
        'S" /hello.txt" VFS-FF-READ _V VFS-OPEN? THROW CONSTANT _FD',
        'S" hello.txt" _SRC _V V.ROOT @ 0 _V VFS-RENAME-AT '
        'VFS-IOR-REASON _BUSY !',
        'S" /source.txt" _V VFS-RESOLVE 0<> _SOURCE !',
        'S" /hello.txt" _V VFS-RESOLVE 0<> _VICTIM !',
        '_BUSY @ VFS-R-BUSY = _SOURCE @ AND _VICTIM @ AND IF',
        '  ." REPLACE-GUARD-OK"',
        'THEN',
    ], "REPLACE-GUARD-OK")


def test_structured_volume_error_translation():
    """Backend detail/flags survive translation and stale latches the VFS."""
    check("structured volume error translation", [
        'T-VMP-NEW CONSTANT _V',
        '_V _VMP-IO-V !',
        '7 7 IOR-D-BLOCK IOR-F-PARTIAL IOR-F-RETRYABLE OR '
        'IOR-MAKE CONSTANT _BE',
        '2 _VMP-IO-EXPECTED ! 1 _VMP-IO-COMPLETED !',
        '_BE _VMP-MAP-IOR CONSTANT _E',
        '_E VFS-IOR-REASON VFS-R-IO =',
        '_E VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = AND',
        '_E VFS-IOR-FLAGS VFS-IOR-F-PARTIAL AND 0<> AND',
        '_E VFS-IOR-FLAGS VFS-IOR-F-RETRYABLE AND 0<> AND',
        '_E VFS-IOR-DETAIL _BE = AND',
        '1 _VMP-IO-EXPECTED ! 0 _VMP-IO-COMPLETED !',
        'VOL-E-STALE _VMP-MAP-IOR CONSTANT _SE',
        '_SE VFS-IOR-REASON VFS-R-STALE = AND',
        '_SE VFS-IOR-FLAGS VFS-IOR-F-STALE AND 0<> AND',
        '_V V.LIFECYCLE @ VFS-L-STALE = AND',
        'IF ." ERROR-MAP-OK" THEN',
    ], "ERROR-MAP-OK")


def test_mount_population_nomem_rolls_back():
    """Mount-time string exhaustion returns NOMEM with an empty root."""
    check("mount population NOMEM rollback", [
        ': _OOM-MOUNT  ( vfs -- ior )',
        '  DUP V.STR-PTR @ OVER V.STR-END ! VMP-INIT ;',
        'CREATE _OOM-OPS VFS-OPS-SIZE ALLOT',
        'VMP-OPS _OOM-OPS VFS-OPS-SIZE CMOVE',
        "' _OOM-MOUNT _OOM-OPS VFS-OP-MOUNT CELLS + !",
        'CREATE _OOM-BINDING',
        'VFS-BINDING-MAGIC , VFS-BINDING-ABI-MAJOR ,',
        'VFS-BINDING-ABI-MINOR , VFS-BINDING-DESC-SIZE ,',
        'VFS-OPS-SIZE , VMP-CAPS , VFS-BF-NEEDS-VOLUME ,',
        '_OOM-OPS , 0 , 0 ,',
        'T-ARENA CONSTANT _OAR',
        '_OAR _OOM-BINDING T-VOLUME VFS-NEW CONSTANT _OI CONSTANT _OV',
        '_OI VFS-IOR-REASON VFS-R-NOMEM =',
        '_OV V.ROOT @ IN.CHILD @ 0= AND',
        '_OV V.ICOUNT @ 1 = AND',
        '_OV V.VCOUNT @ 1 = AND',
        '_OV V.ROOT @ IN.FLAGS @ VFS-IF-CHILDREN AND 0= AND',
        '_OV V.BCTX @ _VMP-C.READY + @ 0= AND',
        'VARIABLE _AP _OAR A.PTR @ _AP !',
        '_OV VMP-INIT _OI = AND',
        '_OAR A.PTR @ _AP @ = AND',
        '_OV V.LAST-IOR @ _OI = AND',
        'IF ." MOUNT-NOMEM-ROLLBACK-OK" THEN',
    ], "MOUNT-NOMEM-ROLLBACK-OK")


def test_readdir_population_nomem_rolls_back():
    """Lazy population restores children, counts, and the string cursor."""
    check("readdir population NOMEM rollback", [
        'T-VMP-NEW CONSTANT _V',
        'S" /docs" _V VFS-RESOLVE CONSTANT _D',
        'VARIABLE _IC VARIABLE _VC VARIABLE _SP',
        '_V V.ICOUNT @ _IC ! _V V.VCOUNT @ _VC ! _V V.STR-PTR @ _SP !',
        '_SP @ _V V.STR-END !',
        '_D _V _VMP-READDIR VFS-IOR-REASON VFS-R-NOMEM =',
        '_D IN.CHILD @ 0= AND',
        '_V V.ICOUNT @ _IC @ = AND',
        '_V V.VCOUNT @ _VC @ = AND',
        '_V V.STR-PTR @ _SP @ = AND',
        '_D IN.FLAGS @ VFS-IF-CHILDREN AND 0= AND',
        'IF ." READDIR-NOMEM-ROLLBACK-OK" THEN',
    ], "READDIR-NOMEM-ROLLBACK-OK")


# =====================================================================
#  Runner
# =====================================================================

def main():
    build_snapshot()
    print()
    print("=" * 60)
    print("  VFS-MP64FS Volume-Binding Tests")
    print("=" * 60)

    test_constructor_binds_and_mounts_volume()
    test_volume_probe_match_nonmatch_and_io_error()
    test_constructor_requires_volume()
    test_constructor_propagates_checked_read_failure()
    test_constructor_adopts_volume_geometry()
    test_constructor_rejects_malformed_media()
    test_constructor_reports_core_arena_exhaustion()
    test_final_directory_slot_mounts_without_pair_loop_wrap()
    test_root_and_lazy_subdirectory_reads()
    test_binary_read_and_offset()
    test_create_write_read_delete_and_sync()
    test_create_zeroes_newly_allocated_sector()
    test_seek_gap_and_truncate_growth_zero_visible_ranges()
    test_zeroing_failures_do_not_publish_size_or_extent()
    test_second_bitmap_sector_sync_and_remount()
    test_sync_retains_dirty_metadata_until_flush_succeeds()
    test_two_instances_share_only_explicit_volume()
    test_empty_formatted_volume_mounts()
    test_checked_sync_survives_fresh_process_without_session_close()
    test_nonzero_bounded_volume_slice_end_to_end()
    test_open_unlink_is_busy_until_close()
    test_open_rename_victim_is_busy()
    test_structured_volume_error_translation()
    test_mount_population_nomem_rolls_back()
    test_readdir_population_nomem_rolls_back()

    print()
    total = _pass_count + _fail_count
    print(f"  Results: {_pass_count} passed, {_fail_count} failed ({total} total)")
    if _fail_count:
        sys.exit(1)


if __name__ == "__main__" and len(sys.argv) >= 4 and sys.argv[1] == "--cold-worker":
    _cold_worker(sys.argv[2], sys.argv[3])
elif __name__ == "__main__":
    try:
        main()
    finally:
        if _img_path and os.path.exists(_img_path):
            os.unlink(_img_path)
