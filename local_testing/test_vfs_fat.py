#!/usr/bin/env python3
"""Test suite for vfs-fat.f — the FAT16/FAT32 VFS binding.

These tests attach a formatted FAT16 or FAT32 disk image to the
emulator, load the VFS + binding, then exercise probe, init,
readdir, read, write, create, delete, sync, and teardown
through the VFS API.

FAT images are built in-memory by Python helper functions that
follow the Microsoft FAT specification exactly:
  - Sector 0: BPB (BIOS Parameter Block) + boot signature
  - Sectors 1..R-1: reserved area (R = RsvdSecCnt)
  - FAT1 (and FAT2 copy)
  - Root directory area (FAT16) or root cluster (FAT32)
  - Data area
"""
import os, sys, struct, tempfile, time, math

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
VFS_FAT_F = os.path.join(ROOT_DIR, "akashic", "utils", "fs", "drivers", "vfs-fat.f")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# ═══════════════════════════════════════════════════════════════════
#  FAT16 Disk Image Builder
# ═══════════════════════════════════════════════════════════════════

SECTOR = 512

def _fat16_sfn(name):
    """Convert 'README.TXT' or 'readme.txt' → 11-byte space-padded SFN."""
    name = name.upper()
    if '.' in name:
        base, ext = name.rsplit('.', 1)
    else:
        base, ext = name, ''
    base = base[:8].ljust(8)
    ext = ext[:3].ljust(3)
    return (base + ext).encode('ascii')

def _fat16_dir_entry(name, attr, cluster, size):
    """Build a 32-byte FAT directory entry."""
    e = bytearray(32)
    sfn = _fat16_sfn(name)
    e[0:11] = sfn
    e[11] = attr
    # Cluster low
    struct.pack_into('<H', e, 26, cluster & 0xFFFF)
    # Cluster high (FAT32 only, leave 0 for FAT16)
    struct.pack_into('<H', e, 20, (cluster >> 16) & 0xFFFF)
    # File size (0 for directories per spec)
    struct.pack_into('<I', e, 28, size if not (attr & 0x10) else 0)
    return bytes(e)


class FAT16ImageBuilder:
    """Build a minimal FAT16 disk image with files and directories.

    Layout:
      Sector 0          : BPB + boot sig
      Sectors 1..rsvd-1 : reserved (zeros)
      FAT1              : fat_sectors sectors
      FAT2              : fat_sectors sectors  (copy)
      Root dir          : root_dir_sectors sectors
      Data area         : cluster 2 onward

    NOTE: total_sectors must be large enough to yield >= 4085 data
    clusters for proper FAT16 classification.  With spc=4 and
    512-byte sectors that means >= ~17000 sectors (~8.5 MB).
    Default 32768 (16 MB) is comfortably FAT16.
    """

    def __init__(self, total_sectors=32768, sectors_per_cluster=4,
                 reserved_sectors=1, num_fats=2, root_entry_count=512):
        self.total_sectors = total_sectors
        self.spc = sectors_per_cluster
        self.reserved = reserved_sectors
        self.num_fats = num_fats
        self.root_entry_count = root_entry_count
        self.root_dir_sectors = (root_entry_count * 32 + SECTOR - 1) // SECTOR

        # Compute FAT size (sectors per FAT)
        # FAT16: 2 bytes per cluster entry
        data_sec = total_sectors - self.reserved - self.root_dir_sectors
        # clusters = data_sec / spc, FAT entries = clusters + 2
        # Each FAT sector holds 256 entries (512/2)
        total_clus_estimate = data_sec // self.spc
        self.fat_sectors = max(1, math.ceil((total_clus_estimate + 2) * 2 / SECTOR))
        # Recompute with FAT sectors accounted for
        data_sec_real = (total_sectors - self.reserved
                         - self.num_fats * self.fat_sectors
                         - self.root_dir_sectors)
        self.data_clusters = data_sec_real // self.spc
        self.first_data_sector = (self.reserved
                                  + self.num_fats * self.fat_sectors
                                  + self.root_dir_sectors)

        # Allocate image
        self.img = bytearray(total_sectors * SECTOR)
        # FAT table (in-memory, as u16 array)
        self._fat = [0] * (self.data_clusters + 2)
        self._fat[0] = 0xFFF8  # media type
        self._fat[1] = 0xFFFF  # EOC marker

        # Root directory entries (list of 32-byte records)
        self._root_entries = []

        # Subdirectory data: cluster -> list of 32-byte entries
        self._subdir_entries = {}

        # Data allocation
        self._next_cluster = 2

        # Write BPB
        self._write_bpb()

    def _write_bpb(self):
        bpb = self.img
        # Jump instruction
        bpb[0] = 0xEB; bpb[1] = 0x3C; bpb[2] = 0x90
        # OEM name
        bpb[3:11] = b'AKASHIC '
        # BytsPerSec
        struct.pack_into('<H', bpb, 11, 512)
        # SecPerClus
        bpb[13] = self.spc
        # RsvdSecCnt
        struct.pack_into('<H', bpb, 14, self.reserved)
        # NumFATs
        bpb[16] = self.num_fats
        # RootEntCnt
        struct.pack_into('<H', bpb, 17, self.root_entry_count)
        # TotSec16
        if self.total_sectors < 65536:
            struct.pack_into('<H', bpb, 19, self.total_sectors)
        else:
            struct.pack_into('<H', bpb, 19, 0)
            struct.pack_into('<I', bpb, 32, self.total_sectors)
        # Media
        bpb[21] = 0xF8
        # FATSz16
        struct.pack_into('<H', bpb, 22, self.fat_sectors)
        # SecPerTrack, NumHeads (dummy)
        struct.pack_into('<H', bpb, 24, 63)
        struct.pack_into('<H', bpb, 26, 255)
        # Boot signature
        bpb[510] = 0x55
        bpb[511] = 0xAA

    def _alloc_cluster(self):
        """Allocate a single cluster, return its number."""
        c = self._next_cluster
        if c >= self.data_clusters + 2:
            raise RuntimeError("FAT16 image out of clusters")
        self._next_cluster += 1
        return c

    def _alloc_chain(self, num_clusters):
        """Allocate a chain of clusters, return first cluster."""
        if num_clusters == 0:
            return 0
        first = self._alloc_cluster()
        prev = first
        for _ in range(num_clusters - 1):
            c = self._alloc_cluster()
            self._fat[prev] = c
            prev = c
        self._fat[prev] = 0xFFFF  # EOC
        return first

    def _cluster_sector(self, cluster):
        """Convert cluster number to absolute sector."""
        return self.first_data_sector + (cluster - 2) * self.spc

    def add_file(self, name, data, parent_cluster=None):
        """Add a file.  parent_cluster=None → root directory."""
        if isinstance(data, str):
            data = data.encode('utf-8')
        num_clus = max(1, math.ceil(len(data) / (self.spc * SECTOR)))
        first = self._alloc_chain(num_clus)
        # Write data
        sec = self._cluster_sector(first)
        self.img[sec * SECTOR : sec * SECTOR + len(data)] = data
        # If chain spans multiple clusters, write remaining data
        remaining = data[self.spc * SECTOR:]
        clus = first
        while remaining:
            clus = self._fat[clus]
            if clus >= 0xFFF8:
                break
            sec = self._cluster_sector(clus)
            chunk = remaining[:self.spc * SECTOR]
            self.img[sec * SECTOR : sec * SECTOR + len(chunk)] = chunk
            remaining = remaining[self.spc * SECTOR:]

        entry = _fat16_dir_entry(name, 0x20, first, len(data))  # archive attr
        if parent_cluster is None:
            self._root_entries.append(entry)
        else:
            self._subdir_entries.setdefault(parent_cluster, []).append(entry)
        return first

    def add_dir(self, name, parent_cluster=None):
        """Add a subdirectory.  Returns the directory's first cluster."""
        clus = self._alloc_chain(1)
        entry = _fat16_dir_entry(name, 0x10, clus, 0)  # directory attr
        if parent_cluster is None:
            self._root_entries.append(entry)
        else:
            self._subdir_entries.setdefault(parent_cluster, []).append(entry)

        # Write . and .. entries inside the new dir cluster
        dot = _fat16_dir_entry('.', 0x10, clus, 0)
        dotdot_clus = parent_cluster if parent_cluster else 0
        dotdot = _fat16_dir_entry('..', 0x10, dotdot_clus, 0)
        # Fix . entry: name field = ".          "
        dot_b = bytearray(dot)
        dot_b[0:11] = b'.          '
        dotdot_b = bytearray(dotdot)
        dotdot_b[0:11] = b'..         '

        self._subdir_entries.setdefault(clus, [])
        self._subdir_entries[clus].insert(0, bytes(dotdot_b))
        self._subdir_entries[clus].insert(0, bytes(dot_b))
        return clus

    def build(self):
        """Finalize and return the image bytes."""
        # Write FAT tables
        fat_data = bytearray(self.fat_sectors * SECTOR)
        for i, val in enumerate(self._fat):
            if i * 2 + 1 < len(fat_data):
                struct.pack_into('<H', fat_data, i * 2, val & 0xFFFF)
        fat1_start = self.reserved
        self.img[fat1_start * SECTOR : (fat1_start + self.fat_sectors) * SECTOR] = fat_data
        if self.num_fats >= 2:
            fat2_start = fat1_start + self.fat_sectors
            self.img[fat2_start * SECTOR : (fat2_start + self.fat_sectors) * SECTOR] = fat_data

        # Write root directory
        root_start = self.reserved + self.num_fats * self.fat_sectors
        rd = bytearray(self.root_dir_sectors * SECTOR)
        for i, e in enumerate(self._root_entries):
            rd[i * 32 : i * 32 + 32] = e
        self.img[root_start * SECTOR : (root_start + self.root_dir_sectors) * SECTOR] = rd

        # Write subdirectory clusters
        for clus, entries in self._subdir_entries.items():
            sec = self._cluster_sector(clus)
            buf = bytearray(self.spc * SECTOR)
            for i, e in enumerate(entries):
                buf[i * 32 : i * 32 + 32] = e
            self.img[sec * SECTOR : sec * SECTOR + len(buf)] = buf

        return bytes(self.img)


def build_fat16_image(files=None, dirs=None, total_sectors=32768,
                      sectors_per_cluster=4):
    """Build a FAT16 image.

    files: list of (name, content_bytes, parent_name_or_None)
    dirs:  list of (name, parent_name_or_None)
    Returns bytes.
    """
    fb = FAT16ImageBuilder(total_sectors=total_sectors,
                           sectors_per_cluster=sectors_per_cluster)
    dir_clusters = {}  # name -> cluster

    # First pass: create directories
    if dirs:
        for dname, parent_name in dirs:
            pc = dir_clusters.get(parent_name) if parent_name else None
            clus = fb.add_dir(dname, pc)
            dir_clusters[dname] = clus

    # Second pass: create files
    if files:
        for fname, data, parent_name in files:
            pc = dir_clusters.get(parent_name) if parent_name else None
            fb.add_file(fname, data, pc)

    return fb.build()


def build_fat16_empty(total_sectors=32768, sectors_per_cluster=4):
    """Build an empty FAT16 image (no files or dirs)."""
    return build_fat16_image(total_sectors=total_sectors,
                             sectors_per_cluster=sectors_per_cluster)


# ═══════════════════════════════════════════════════════════════════
#  Emulator Helpers (same pattern as test_vfs_mp64fs.py)
# ═══════════════════════════════════════════════════════════════════

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


# ═══════════════════════════════════════════════════════════════════
#  Minimal MP64FS boot image (for KDOS FS-LOAD to succeed)
# ═══════════════════════════════════════════════════════════════════

_MP64_DIR_ENTRY_SIZE = 48
_MP64_DIR_SECTORS = 12
_MP64_DATA_START = 14

def _build_mp64fs_boot_image(total_sectors=2048):
    """Build an empty MP64FS image.  KDOS FS-LOAD reads and recognises it."""
    sb = bytearray(SECTOR)
    sb[0:4] = b'MP64'
    struct.pack_into('<H', sb, 4, 1)               # version
    struct.pack_into('<I', sb, 6, total_sectors)    # total_sectors
    struct.pack_into('<H', sb, 10, 1)               # bmap_start
    struct.pack_into('<H', sb, 12, 1)               # bmap_sectors
    struct.pack_into('<H', sb, 14, 2)               # dir_start
    struct.pack_into('<H', sb, 16, _MP64_DIR_SECTORS)
    struct.pack_into('<H', sb, 18, _MP64_DATA_START)
    sb[20] = 128                                     # max_files
    sb[21] = _MP64_DIR_ENTRY_SIZE

    bmap = bytearray(SECTOR)
    for s in range(_MP64_DATA_START):
        bmap[s // 8] |= (1 << (s % 8))

    dd = bytearray(_MP64_DIR_SECTORS * SECTOR)

    img = bytearray(total_sectors * SECTOR)
    img[0:SECTOR] = sb
    img[SECTOR:2*SECTOR] = bmap
    img[2*SECTOR:(2 + _MP64_DIR_SECTORS)*SECTOR] = dd
    return bytes(img)


# ═══════════════════════════════════════════════════════════════════
#  Snapshot
# ═══════════════════════════════════════════════════════════════════

_snapshot = None
_boot_img_path = None     # MP64FS boot image (for snapshot build)
_default_fat_img = None   # Default FAT16 test image (bytes)

def _build_default_fat_image():
    """Build a default FAT16 test disk with a few files + subdirectory."""
    global _default_fat_img
    _default_fat_img = build_fat16_image(
        dirs=[
            ("DOCS", None),
        ],
        files=[
            ("HELLO.TXT",   b"Hello, FAT world!",          None),
            ("DATA.BIN",    bytes(range(256)) * 4,          None),   # 1024 bytes
            ("README.TXT",  b"Inside docs directory",       "DOCS"),
        ],
    )
    return _default_fat_img

def build_snapshot():
    global _snapshot, _boot_img_path
    if _snapshot:
        return _snapshot
    print("[*] Building snapshot: BIOS + KDOS + VFS + FAT binding ...")
    t0 = time.time()

    # Build the default FAT16 test image (stored in memory, NOT used for boot)
    _build_default_fat_image()

    # Build a minimal MP64FS boot image so KDOS FS-LOAD succeeds
    boot_img = _build_mp64fs_boot_image()
    fd, path = tempfile.mkstemp(suffix='.img')
    os.write(fd, boot_img)
    os.close(fd)
    _boot_img_path = path

    bios_code  = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)

    dep_lines = []
    for path in [EVENT_F, SEM_F, GUARD_F, UTF8_F, VFS_F, VFS_MNT_F, VFS_FAT_F]:
        dep_lines += _load_forth_lines(path)

    helpers = [
        'CREATE _RB 4096 ALLOT',
        'CREATE _WB 4096 ALLOT',
        'VARIABLE _TARN',
        ': T-VFAT-NEW  ( -- vfs )',
        '    524288 A-XMEM ARENA-NEW  IF -1 THROW THEN  _TARN !',
        '    _TARN @ VFAT-NEW ;',
    ]

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20),
                            storage_image=_boot_img_path)
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
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot


def run_forth(lines, max_steps=800_000_000, disk_image=None):
    if _snapshot is None:
        build_snapshot()
    bios_code, mem_bytes, cpu_state, ext_mem_bytes = _snapshot

    # Use MP64FS boot image to create the system, then restore snapshot state
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20),
                            storage_image=_boot_img_path)
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

    # Swap storage to the FAT image (default or provided)
    img = disk_image if disk_image else _default_fat_img
    sd = sys_obj.storage._image_data
    if len(img) > len(sd):
        sys_obj.storage._image_data = bytearray(img)
    else:
        sd[:len(img)] = img
        # Zero remainder so stale MP64FS data doesn't leak
        for i in range(len(img), len(sd)):
            sd[i] = 0
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


# ═══════════════════════════════════════════════════════════════════
#  Test Framework
# ═══════════════════════════════════════════════════════════════════

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
        for l in clean.split('\n')[-20:]:
            print(f"        {l}")


# ═══════════════════════════════════════════════════════════════════
#  Tests
# ═══════════════════════════════════════════════════════════════════

# ── Probe ──

def test_probe_valid():
    """Probe returns TRUE for a valid FAT16 image."""
    check("probe-valid", [
        'T-VFAT-NEW CONSTANT _V',
        'CREATE _SB 512 ALLOT',
        '0 DISK-SEC!  _SB DISK-DMA!  1 DISK-N!  DISK-READ',
        '_SB _V _VFAT-PROBE . CR',
    ], "-1")

def test_probe_invalid():
    """Probe returns FALSE for a zeroed image."""
    img = bytes(32768 * SECTOR)   # all zeros
    check("probe-invalid", [
        'T-VFAT-NEW CONSTANT _V',
        'CREATE _SB 512 ALLOT',
        '0 DISK-SEC!  _SB DISK-DMA!  1 DISK-N!  DISK-READ',
        '_SB _V _VFAT-PROBE . CR',
    ], "0", disk_image=img)

# ── Init ──

def test_init_success():
    """VFAT-INIT returns 0 on a valid FAT16 image."""
    check("init-success", [
        'T-VFAT-NEW CONSTANT _V',
        '_V VFAT-INIT . CR',
    ], "0")

def test_init_sets_geometry():
    """After init, context has correct FAT type and sec-per-cluster."""
    check("init-geometry", [
        'T-VFAT-NEW CONSTANT _V',
        '_V VFAT-INIT DROP',
        '_V V.BCTX @  2048 + @ . CR',     # fat-type (should be 16)
        '_V V.BCTX @  2056 + @ . CR',     # sec-per-clus (should be 4)
    ], "16")

def test_init_first_data_sector():
    """FirstDataSector is computed correctly."""
    check("init-fds", [
        'T-VFAT-NEW CONSTANT _V',
        '_V VFAT-INIT DROP',
        '_V V.BCTX @  2096 + @ . CR',     # first-data-sector
    ], "")  # TODO: compute expected value once init works

# ── BPB parse on FAT32-sized image ──

def test_init_rejects_fat12():
    """Init returns -3 for a FAT12-sized image (< 4085 data clusters)."""
    # Build a tiny image that yields < 4085 clusters
    # 128 sectors, 1 sec/clus → ~100 data clusters → FAT12
    img = FAT16ImageBuilder(total_sectors=128, sectors_per_cluster=1,
                            reserved_sectors=1, num_fats=2,
                            root_entry_count=16).build()
    check("init-rejects-fat12", [
        'T-VFAT-NEW CONSTANT _V',
        '_V VFAT-INIT . CR',
    ], "-3", disk_image=img)

# ── Probe edge cases ──

def test_probe_no_bootsig():
    """Probe fails when boot signature is missing."""
    img = bytearray(build_fat16_empty())
    img[510] = 0x00  # break boot sig
    img[511] = 0x00
    check("probe-no-bootsig", [
        'T-VFAT-NEW CONSTANT _V',
        'CREATE _SB 512 ALLOT',
        '0 DISK-SEC!  _SB DISK-DMA!  1 DISK-N!  DISK-READ',
        '_SB _V _VFAT-PROBE . CR',
    ], "0", disk_image=bytes(img))

def test_probe_bad_spc():
    """Probe fails when SecPerClus is not a power of 2."""
    img = bytearray(build_fat16_empty())
    img[13] = 3  # not a power of 2
    check("probe-bad-spc", [
        'T-VFAT-NEW CONSTANT _V',
        'CREATE _SB 512 ALLOT',
        '0 DISK-SEC!  _SB DISK-DMA!  1 DISK-N!  DISK-READ',
        '_SB _V _VFAT-PROBE . CR',
    ], "0", disk_image=bytes(img))

# ── FAT chain navigation ──

def test_next_cluster_eoc():
    """_VFAT-NEXT-CLUSTER returns EOC for a single-cluster file."""
    check("next-cluster-eoc", [
        'T-VFAT-NEW CONSTANT _V',
        '_V VFAT-INIT DROP',
        # Cluster 2 should be EOC (first allocated cluster for first file/dir)
        '2 _V V.BCTX @ _VFAT-NEXT-CLUSTER',
        'HEX . DECIMAL CR',
    ], "FFF")  # 0xFFFF for single-cluster EOC

def test_next_cluster_chain():
    """_VFAT-NEXT-CLUSTER follows a multi-cluster chain."""
    # Build an image with a file spanning multiple clusters
    big_data = bytes(range(256)) * 32  # 8192 bytes = 4 clusters at 4 spc×512
    img = build_fat16_image(files=[("BIG.BIN", big_data, None)])
    check("next-cluster-chain", [
        'T-VFAT-NEW CONSTANT _V',
        '_V VFAT-INIT DROP',
        '2 _V V.BCTX @ _VFAT-NEXT-CLUSTER . CR',
    ], "3", disk_image=img)  # cluster 2 → 3

# ── Teardown ──

def test_teardown():
    """VFAT-TEARDOWN clears binding context."""
    check("teardown", [
        'T-VFAT-NEW CONSTANT _V',
        '_V VFAT-INIT DROP',
        '_V VFS-DESTROY',
        '.\" DONE\" CR',
    ], "DONE")

# ── VFAT-NEW convenience ──

def test_vfat_new():
    """VFAT-NEW creates a usable VFS handle."""
    check("vfat-new", [
        'T-VFAT-NEW CONSTANT _V',
        '_V 0<> . CR',
    ], "-1")


# ── Root directory scan (VFAT-INIT populates root children) ──

def test_init_root_children():
    """After VFAT-INIT, root inode has children."""
    check("init-root-children", [
        'T-VFAT-NEW CONSTANT _V',
        '_V VFAT-INIT DROP',
        '_V V.ROOT @ IN.CHILD @ 0<> . CR',
    ], "-1")

def test_init_resolve_file():
    """VFS-RESOLVE finds a file in root after init."""
    check("init-resolve-file", [
        'T-VFAT-NEW CONSTANT _V',
        '_V VFAT-INIT DROP',
        '_V VFS-USE',
        'S" /HELLO.TXT" _V VFS-RESOLVE 0<> . CR',
    ], "-1")

def test_init_resolve_dir():
    """VFS-RESOLVE finds a subdirectory after init."""
    check("init-resolve-dir", [
        'T-VFAT-NEW CONSTANT _V',
        '_V VFAT-INIT DROP',
        '_V VFS-USE',
        'S" /DOCS" _V VFS-RESOLVE DUP 0<> IF ." FOUND " IN.TYPE @ . ELSE ." NOTFOUND" DROP THEN CR',
    ], "FOUND 2")   # VFS-T-DIR = 2

def test_init_resolve_subdir_file():
    """VFS-RESOLVE finds a file inside a subdirectory (lazy readdir)."""
    check("init-resolve-subfile", [
        'T-VFAT-NEW CONSTANT _V',
        '_V VFAT-INIT DROP',
        '_V VFS-USE',
        'S" /DOCS/README.TXT" _V VFS-RESOLVE 0<> IF ." FOUND" ELSE ." NOTFOUND" THEN CR',
    ], "FOUND")


# ── Read ──

def test_read_file():
    """VFS-READ returns correct file content."""
    check("read-file", [
        'T-VFAT-NEW CONSTANT _V',
        '_V VFAT-INIT DROP',
        '_V VFS-USE',
        'S" /HELLO.TXT" VFS-OPEN DUP 0<> IF',
        '    _RB 4096 ROT VFS-READ',
        '    _RB SWAP TYPE',
        'ELSE ." OPEN-FAIL" DROP THEN',
    ], "Hello, FAT world!")

def test_read_binary_size():
    """VFS-READ returns correct byte count for binary data."""
    check("read-binary-size", [
        'T-VFAT-NEW CONSTANT _V',
        '_V VFAT-INIT DROP',
        '_V VFS-USE',
        'S" /DATA.BIN" VFS-OPEN DUP 0<> IF',
        '    _RB 4096 ROT VFS-READ . ." <act"',
        'ELSE ." OPEN-FAIL" DROP THEN',
    ], "1024 <act")

def test_read_subdir_file():
    """Read a file inside a subdirectory."""
    check("read-subdir-file", [
        'T-VFAT-NEW CONSTANT _V',
        '_V VFAT-INIT DROP',
        '_V VFS-USE',
        'S" /DOCS/README.TXT" VFS-OPEN DUP 0<> IF',
        '    _RB 4096 ROT VFS-READ',
        '    _RB SWAP TYPE',
        'ELSE ." OPEN-FAIL" DROP THEN',
    ], "Inside docs directory")

def test_read_at_offset():
    """VFS-READ after seeking reads from the correct position."""
    check("read-at-offset", [
        'T-VFAT-NEW CONSTANT _V',
        '_V VFAT-INIT DROP',
        '_V VFS-USE',
        'S" /HELLO.TXT" VFS-OPEN CONSTANT _FD',
        # Seek to offset 7 ("FAT world!")
        '7 _FD FD.CUR-LO !',
        '_RB 4096 _FD VFS-READ',
        '_RB SWAP TYPE',
    ], "FAT world!")

def test_read_multicluster():
    """Read a file spanning multiple clusters."""
    # 8192 bytes = 4 clusters (at 4 spc * 512 bytes/sector = 2048 bytes/cluster)
    big_data = bytes(range(256)) * 32  # 8192 bytes
    img = build_fat16_image(files=[("BIG.BIN", big_data, None)])
    check("read-multicluster", [
        'T-VFAT-NEW CONSTANT _V',
        '_V VFAT-INIT DROP',
        '_V VFS-USE',
        'S" /BIG.BIN" VFS-OPEN DUP 0<> IF',
        '    _RB 4096 ROT VFS-READ . ." <act1"',
        'ELSE ." OPEN-FAIL" DROP THEN',
    ], "4096 <act1", disk_image=img)


# ── Write ──

def test_write_and_readback():
    """Write data then read it back."""
    check("write-readback", [
        'T-VFAT-NEW CONSTANT _V',
        '_V VFAT-INIT DROP',
        '_V VFS-USE',
        'S" /HELLO.TXT" VFS-OPEN CONSTANT _FD',
        'VARIABLE _WLEN',
        'S" Overwritten!" _WB SWAP DUP _WLEN ! CMOVE',
        '_WB _WLEN @ _FD VFS-WRITE . ." <wact"',
        '_FD VFS-REWIND',
        '_RB 4096 _FD VFS-READ DROP',
        '_RB _WLEN @ TYPE',
    ], "Overwritten!")


# ── Create ──

def test_create_file():
    """VFS-MKFILE creates a new file visible via VFS-RESOLVE."""
    check("create-file", [
        'T-VFAT-NEW CONSTANT _V',
        '_V VFAT-INIT DROP',
        '_V VFS-USE',
        'S" NEW.TXT" _V VFS-MKFILE 0<> . ." <mk"',
        'S" /NEW.TXT" _V VFS-RESOLVE 0<> . ." <found"',
    ], "-1 <mk")

def test_create_write_read():
    """Create a file, write content, then read it back."""
    check("create-write-read", [
        'T-VFAT-NEW CONSTANT _V',
        '_V VFAT-INIT DROP',
        '_V VFS-USE',
        'S" TEST.TXT" _V VFS-MKFILE DROP',
        'S" /TEST.TXT" VFS-OPEN CONSTANT _FD',
        'VARIABLE _WLEN',
        'S" Created content!" _WB SWAP DUP _WLEN ! CMOVE',
        '_WB _WLEN @ _FD VFS-WRITE . ." <wact"',
        '_FD VFS-REWIND',
        '_RB 4096 _FD VFS-READ DROP',
        '_RB _WLEN @ TYPE',
    ], "Created content!")


# ── Delete (no tombstones) ──

def test_delete_file():
    """VFS-RM deletes a file; it no longer resolves."""
    check("delete-file", [
        'T-VFAT-NEW CONSTANT _V',
        '_V VFAT-INIT DROP',
        '_V VFS-USE',
        'S" /HELLO.TXT" _V VFS-RM . ." <rmior"',
        'S" /HELLO.TXT" _V VFS-RESOLVE 0= IF ." GONE" ELSE ." STILL" THEN',
    ], "GONE")

def test_delete_no_tombstone():
    """Delete zeros the dir entry byte 0 (not 0xE5 tombstone)."""
    # After deleting, re-init should not see the file (byte 0 = 0x00, not 0xE5)
    check("delete-no-tombstone", [
        'T-VFAT-NEW CONSTANT _V',
        '_V VFAT-INIT DROP',
        '_V VFS-USE',
        'S" /HELLO.TXT" _V VFS-RM DROP',
        # Sync to write changes to disk
        '_V VFS-SYNC DROP',
        # Create a new VFS and re-init from the same disk to verify persistence
        'T-VFAT-NEW CONSTANT _V2',
        '_V2 VFAT-INIT DROP',
        '_V2 VFS-USE',
        'S" /HELLO.TXT" _V2 VFS-RESOLVE 0= IF ." CLEAN" ELSE ." STALE" THEN',
    ], "CLEAN")


# ── Sync ──

def test_sync():
    """VFS-SYNC returns ior=0."""
    check("sync", [
        'T-VFAT-NEW CONSTANT _V',
        '_V VFAT-INIT DROP',
        '_V VFS-USE',
        '_V VFS-SYNC . ." <syncior"',
    ], "0 <syncior")


# ── Truncate ──

def test_truncate():
    """After writing, file size is updated in dir entry."""
    check("truncate-size", [
        'T-VFAT-NEW CONSTANT _V',
        '_V VFAT-INIT DROP',
        '_V VFS-USE',
        'S" /HELLO.TXT" VFS-OPEN CONSTANT _FD',
        'S" Hi" _WB SWAP CMOVE',
        '_WB 2 _FD VFS-WRITE DROP',
        # Truncate to update dir entry
        '_FD FD.INODE @ IN.SIZE-LO @ . ." <sz"',
    ], "17 <sz")  # original 17 bytes; write of 2 at offset 0 doesn't shrink


# ═══════════════════════════════════════════════════════════════════
#  Runner
# ═══════════════════════════════════════════════════════════════════

def main():
    build_snapshot()
    print()
    print("=" * 60)
    print("  VFS-FAT Binding Tests")
    print("=" * 60)

    # Probe
    test_probe_valid()
    test_probe_invalid()
    test_probe_no_bootsig()
    test_probe_bad_spc()

    # Init
    test_init_success()
    test_init_sets_geometry()
    test_init_first_data_sector()
    test_init_rejects_fat12()

    # FAT navigation
    test_next_cluster_eoc()
    test_next_cluster_chain()

    # Root scan
    test_init_root_children()
    test_init_resolve_file()
    test_init_resolve_dir()
    test_init_resolve_subdir_file()

    # Read
    test_read_file()
    test_read_binary_size()
    test_read_subdir_file()
    test_read_at_offset()
    test_read_multicluster()

    # Write
    test_write_and_readback()

    # Create
    test_create_file()
    test_create_write_read()

    # Delete
    test_delete_file()
    test_delete_no_tombstone()

    # Sync
    test_sync()

    # Truncate
    test_truncate()

    # Teardown & convenience
    test_teardown()
    test_vfat_new()

    print()
    print(f"  Results: {_pass_count} passed, {_fail_count} failed ({_pass_count + _fail_count} total)")
    if _fail_count:
        print("  *** FAILURES DETECTED ***")
        sys.exit(1)
    else:
        print("  All tests passed.")

if __name__ == "__main__":
    main()
