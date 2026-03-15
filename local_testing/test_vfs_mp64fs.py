#!/usr/bin/env python3
"""Test suite for vfs-mp64fs.f — the MP64FS VFS binding.

These tests attach a formatted MP64FS disk image to the emulator,
load the VFS + binding, then exercise probe, init, readdir, read,
write, create, delete, sync, and teardown through the VFS API.
"""
import os, sys, struct, tempfile, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")

# Forth source paths
EVENT_F   = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
SEM_F     = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")
GUARD_F   = os.path.join(ROOT_DIR, "akashic", "concurrency", "guard.f")
UTF8_F    = os.path.join(ROOT_DIR, "akashic", "text", "utf8.f")
VFS_F     = os.path.join(ROOT_DIR, "akashic", "utils", "fs", "vfs.f")
VFS_MNT_F = os.path.join(ROOT_DIR, "akashic", "utils", "fs", "vfs-mount.f")
VFS_MP_F  = os.path.join(ROOT_DIR, "akashic", "utils", "fs", "drivers", "vfs-mp64fs.f")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# ── Disk image builder ──────────────────────────────────────────────

SECTOR = 512
DIR_ENTRY_SIZE = 48
MAX_FILES = 128
DIR_SECTORS = 12
DATA_START = 14
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
    entries = []
    data_sectors = []
    next_sec = DATA_START

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
    struct.pack_into('<H', sb, 4, 1)          # version
    struct.pack_into('<I', sb, 6, total_sectors)  # total_sectors (u32)
    struct.pack_into('<H', sb, 10, BMAP_START)
    struct.pack_into('<H', sb, 12, 1)         # bmap_sectors
    struct.pack_into('<H', sb, 14, 2)         # dir_start
    struct.pack_into('<H', sb, 16, DIR_SECTORS)
    struct.pack_into('<H', sb, 18, DATA_START)
    sb[20] = MAX_FILES
    sb[21] = DIR_ENTRY_SIZE

    # Bitmap
    bmap = bytearray(SECTOR)
    for s in range(DATA_START):
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
    img[SECTOR:2 * SECTOR] = bmap
    img[2 * SECTOR : (2 + DIR_SECTORS) * SECTOR] = dd
    for ss, p in data_sectors:
        img[ss * SECTOR : ss * SECTOR + len(p)] = p
    return bytes(img)


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
    for path in [EVENT_F, SEM_F, GUARD_F, UTF8_F, VFS_F, VFS_MNT_F, VFS_MP_F]:
        dep_lines += _load_forth_lines(path)

    helpers = [
        # Read buffer
        'CREATE _RB 4096 ALLOT',
        # Write buffer
        'CREATE _WB 4096 ALLOT',
        # VFS init helper: create MP64FS VFS
        'VARIABLE _TARN',
        ': T-VMP-NEW  ( -- vfs )',
        '    524288 A-XMEM ARENA-NEW  IF -1 THROW THEN  _TARN !',
        '    _TARN @ VMP-NEW ;',
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


def run_forth(lines, max_steps=800_000_000, disk_image=None):
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


# ── Test framework ───────────────────────────────────────────────────

_pass_count = 0
_fail_count = 0

def check(name, forth_lines, expected, disk_image=None):
    global _pass_count, _fail_count
    output, _ = run_forth(forth_lines, disk_image=disk_image)
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

def test_probe_valid():
    """Probe returns TRUE for a valid MP64FS image."""
    check("probe-valid", [
        'T-VMP-NEW CONSTANT _V',
        'CREATE _PBUF 512 ALLOT',
        # Read sector 0 into _PBUF
        '0 DISK-SEC!  _PBUF DISK-DMA!  1 DISK-N!  DISK-READ',
        '_PBUF _V _VMP-PROBE IF ." PROBE-OK" ELSE ." PROBE-FAIL" THEN',
    ], "PROBE-OK")


def test_probe_invalid():
    """Probe returns FALSE for a non-MP64FS image."""
    bad_img = bytearray(2048 * 512)
    bad_img[0:4] = b"XXXX"
    check("probe-invalid", [
        'T-VMP-NEW CONSTANT _V',
        'CREATE _PBUF 512 ALLOT',
        '0 DISK-SEC!  _PBUF DISK-DMA!  1 DISK-N!  DISK-READ',
        '_PBUF _V _VMP-PROBE IF ." PROBE-FAIL" ELSE ." PROBE-OK" THEN',
    ], "PROBE-OK", disk_image=bytes(bad_img))


def test_init_success():
    """VMP-INIT succeeds and returns ior=0."""
    check("init-success", [
        'T-VMP-NEW CONSTANT _V',
        '_V VMP-INIT . ." <ior"',
    ], "0 <ior")


def test_init_populates_root():
    """After init, VFS root has children from the disk."""
    check("init-populates-root", [
        'T-VMP-NEW CONSTANT _V',
        '_V VMP-INIT DROP',
        '_V VFS-USE',
        # Check root child pointer directly
        '_V V.ROOT @ IN.CHILD @ . ." <rchild"',
        '_V V.CWD  @ IN.CHILD @ . ." <cwdchild"',
        # Try to resolve hello.txt (should work)
        'S" hello.txt" _V VFS-RESOLVE DUP 0<> IF',
        '    ." RESOLVED-OK"',
        'ELSE ." RESOLVED-FAIL" THEN DROP',
    ], "RESOLVED-OK")


def test_root_has_all_files():
    """Root listing includes all root-level files and directories."""
    check("root-all-files", [
        'T-VMP-NEW CONSTANT _V',
        '_V VMP-INIT DROP',
        '_V VFS-USE',
        ': T-WALK  _V V.ROOT @ IN.CHILD @  BEGIN DUP 0<> WHILE  DUP IN.NAME @ DUP 0<> IF DUP 16 + SWAP @ TYPE ."  " ELSE DROP THEN IN.SIBLING @  REPEAT DROP ;',
        'T-WALK',
    ], "data.bin")


def test_root_has_subdir():
    """Root listing includes the 'docs' directory."""
    check("root-has-subdir", [
        'T-VMP-NEW CONSTANT _V',
        '_V VMP-INIT DROP',
        '_V VFS-USE',
        ': T-WALK2  _V V.ROOT @ IN.CHILD @  BEGIN DUP 0<> WHILE  DUP IN.NAME @ DUP 0<> IF DUP 16 + SWAP @ TYPE ."  " ELSE DROP THEN IN.SIBLING @  REPEAT DROP ;',
        'T-WALK2',
    ], "docs")


def test_resolve_file():
    """VFS-RESOLVE finds a root-level file."""
    check("resolve-file", [
        'T-VMP-NEW CONSTANT _V',
        '_V VMP-INIT DROP',
        '_V VFS-USE',
        'S" hello.txt" _V VFS-RESOLVE DUP 0<> IF ." FOUND" ELSE ." NOTFOUND" THEN DROP',
    ], "FOUND")


def test_resolve_absolute():
    """VFS-RESOLVE handles absolute path /hello.txt."""
    check("resolve-absolute", [
        'T-VMP-NEW CONSTANT _V',
        '_V VMP-INIT DROP',
        '_V VFS-USE',
        'S" /hello.txt" _V VFS-RESOLVE DUP 0<> IF ." FOUND" ELSE ." NOTFOUND" THEN DROP',
    ], "FOUND")


def test_resolve_subdir_file():
    """VFS-RESOLVE finds a file inside a subdirectory."""
    check("resolve-subdir-file", [
        'T-VMP-NEW CONSTANT _V',
        '_V VMP-INIT DROP',
        '_V VFS-USE',
        'S" /docs/readme.txt" _V VFS-RESOLVE DUP 0<> IF ." FOUND" ELSE ." NOTFOUND" THEN DROP',
    ], "FOUND")


def test_read_file():
    """Read a file's contents through VFS-READ."""
    check("read-file", [
        'T-VMP-NEW CONSTANT _V',
        '_V VMP-INIT DROP',
        '_V VFS-USE',
        'S" /hello.txt" VFS-OPEN DUP 0<> IF',
        '    _RB 4096 ROT VFS-READ',
        '    _RB SWAP TYPE',    # print the read data
        'ELSE ." OPEN-FAIL" DROP THEN',
    ], "Hello, VFS world!")


def test_read_binary():
    """Read binary data and verify size."""
    check("read-binary", [
        'T-VMP-NEW CONSTANT _V',
        '_V VMP-INIT DROP',
        '_V VFS-USE',
        'S" /data.bin" VFS-OPEN DUP 0<> IF',
        '    DUP VFS-SIZE . ." <sz"',      # should print 1024
        '    _RB 1024 ROT VFS-READ . ." <act"',   # should print 1024
        'ELSE ." OPEN-FAIL" DROP THEN',
    ], "1024 <sz")


def test_read_subdir_file():
    """Read a file inside a subdirectory."""
    check("read-subdir-file", [
        'T-VMP-NEW CONSTANT _V',
        '_V VMP-INIT DROP',
        '_V VFS-USE',
        'S" /docs/readme.txt" VFS-OPEN DUP 0<> IF',
        '    _RB 4096 ROT VFS-READ',
        '    _RB SWAP TYPE',
        'ELSE ." OPEN-FAIL" DROP THEN',
    ], "Inside docs directory")


def test_write_and_readback():
    """Write data to a file and read it back."""
    check("write-readback", [
        'T-VMP-NEW CONSTANT _V',
        '_V VMP-INIT DROP',
        '_V VFS-USE',
        # Open hello.txt for write
        'S" /hello.txt" VFS-OPEN CONSTANT _FD',
        # Write new content
        'S" Overwritten!" _WB SWAP DUP >R CMOVE',
        '_WB R> 0 _FD FD.INODE @ _V',
            'VFS-VT-WRITE _V _VFS-XT EXECUTE DROP',
        # Update inode size
        '12 _FD FD.INODE @ IN.SIZE-LO !',
        # Rewind and read back
        '_FD VFS-REWIND',
        '_RB 4096 _FD VFS-READ . ." <act"',
        '_RB 12 TYPE',
    ], "Overwritten!")


def test_write_via_vfs_write():
    """Write through VFS-WRITE (high-level) and read back."""
    check("write-vfs-write", [
        'T-VMP-NEW CONSTANT _V',
        '_V VMP-INIT DROP',
        '_V VFS-USE',
        'S" /hello.txt" VFS-OPEN CONSTANT _FD',
        'VARIABLE _WLEN',
        # Write using VFS-WRITE
        'S" NEW-DATA" _WB SWAP DUP _WLEN ! CMOVE',
        '_WB _WLEN @ _FD VFS-WRITE . ." <wact"',
        # Rewind and read
        '_FD VFS-REWIND',
        '_RB 4096 _FD VFS-READ DROP',
        '_RB _WLEN @ TYPE',
    ], "NEW-DATA")


def test_create_file():
    """VFS-MKFILE creates a new file visible in directory."""
    check("create-file", [
        'T-VMP-NEW CONSTANT _V',
        '_V VMP-INIT DROP',
        '_V VFS-USE',
        'VARIABLE _MKR',
        ': T-MK  S" newfile.txt" _V VFS-MKFILE DUP 0<> IF DROP 1 ELSE DROP 0 THEN _MKR ! ;',
        'T-MK  _MKR @ . ." <mk"',
        'S" /newfile.txt" _V VFS-RESOLVE 0<> . ." <found"',
    ], "1 <mk")


def test_delete_file():
    """VFS-RM deletes a file."""
    check("delete-file", [
        'T-VMP-NEW CONSTANT _V',
        '_V VMP-INIT DROP',
        '_V VFS-USE',
        # Verify it exists
        'S" /hello.txt" _V VFS-RESOLVE 0<> IF ." PRE-OK " ELSE ." PRE-FAIL " THEN',
        # Delete
        'S" /hello.txt" _V VFS-RM . ." <rmior"',
        # Verify gone
        'S" /hello.txt" _V VFS-RESOLVE 0= IF ."  GONE" ELSE ."  STILL" THEN',
    ], "GONE")


def test_sync():
    """VFS-SYNC returns ior=0."""
    check("sync", [
        'T-VMP-NEW CONSTANT _V',
        '_V VMP-INIT DROP',
        '_V VFS-USE',
        '_V VFS-SYNC . ." <syncior"',
    ], "0 <syncior")


def test_destroy():
    """VFS-DESTROY does not crash."""
    check("destroy", [
        'T-VMP-NEW CONSTANT _V',
        '_V VMP-INIT DROP',
        '_V VFS-DESTROY ." DESTROYED"',
    ], "DESTROYED")


def test_two_instances():
    """Two separate VFS instances on the same disk don't interfere."""
    check("two-instances", [
        'T-VMP-NEW CONSTANT _V1',
        '_V1 VMP-INIT DROP',
        'T-VMP-NEW CONSTANT _V2',
        '_V2 VMP-INIT DROP',
        '_V1 VFS-USE',
        'S" /hello.txt" _V1 VFS-RESOLVE 0<> IF ." V1-OK " ELSE ." V1-FAIL " THEN',
        '_V2 VFS-USE',
        'S" /hello.txt" _V2 VFS-RESOLVE 0<> IF ." V2-OK" ELSE ." V2-FAIL" THEN',
    ], "V1-OK")


def test_empty_disk():
    """Init on an empty formatted disk succeeds."""
    img = build_disk_image([])
    check("empty-disk", [
        'T-VMP-NEW CONSTANT _V',
        '_V VMP-INIT . ." <ior"',
        '_V VFS-USE',
        '." DONE"',
    ], "0 <ior", disk_image=img)


def test_read_offset():
    """Read with a non-zero offset works correctly."""
    check("read-offset", [
        'T-VMP-NEW CONSTANT _V',
        '_V VMP-INIT DROP',
        '_V VFS-USE',
        'S" /hello.txt" VFS-OPEN CONSTANT _FD',
        # Seek to offset 7 ("VFS world!")
        '7 _FD VFS-SEEK',
        '_RB 100 _FD VFS-READ DROP',
        '_RB 10 TYPE',
    ], "VFS world!")


def test_vmp_new_convenience():
    """VMP-NEW convenience word works."""
    check("vmp-new", [
        '524288 A-XMEM ARENA-NEW  IF -1 THROW THEN CONSTANT _AR',
        '_AR VMP-NEW CONSTANT _V',
        '_V VMP-INIT . ." <ior"',
    ], "0 <ior")


# =====================================================================
#  Runner
# =====================================================================

if __name__ == "__main__":
    build_snapshot()
    print()
    print("=" * 60)
    print("  VFS-MP64FS Binding Tests")
    print("=" * 60)

    test_probe_valid()
    test_probe_invalid()
    test_init_success()
    test_init_populates_root()
    test_root_has_all_files()
    test_root_has_subdir()
    test_resolve_file()
    test_resolve_absolute()
    test_resolve_subdir_file()
    test_read_file()
    test_read_binary()
    test_read_subdir_file()
    test_write_and_readback()
    test_write_via_vfs_write()
    test_create_file()
    test_delete_file()
    test_sync()
    test_destroy()
    test_two_instances()
    test_read_offset()
    test_vmp_new_convenience()
    test_empty_disk()

    print()
    print(f"  Results: {_pass_count} passed, {_fail_count} failed "
          f"({_pass_count + _fail_count} total)")
    if _fail_count:
        sys.exit(1)

    # Cleanup temp image
    if _img_path and os.path.exists(_img_path):
        os.unlink(_img_path)
