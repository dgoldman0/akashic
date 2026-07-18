#!/usr/bin/env python3
"""Test suite for vfs-fat.f — the FAT16/FAT32 VFS binding.

These tests attach a formatted FAT16 or FAT32 image through the checked
block-device/volume API, then exercise the read-only VFS binding.

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
MEGAPAD_ROOT = os.path.abspath(os.path.join(ROOT_DIR, "..", "megapad"))

# Forth source paths
EVENT_F   = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
SEM_F     = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")
GUARD_F   = os.path.join(ROOT_DIR, "akashic", "concurrency", "guard.f")
UTF8_F    = os.path.join(ROOT_DIR, "akashic", "text", "utf8.f")
MEMORY_SPAN_F = os.path.join(ROOT_DIR, "akashic", "utils", "memory-span.f")
VFS_F     = os.path.join(ROOT_DIR, "akashic", "utils", "fs", "vfs.f")
VFS_MNT_F = os.path.join(ROOT_DIR, "akashic", "utils", "fs", "vfs-mount.f")
VFS_FAT_F = os.path.join(ROOT_DIR, "akashic", "utils", "fs", "drivers", "vfs-fat.f")

sys.path.insert(0, MEGAPAD_ROOT)
from asm import assemble
from devices import STORAGE_CMD_READ, STORAGE_RESULT_MEDIA_FAILURE
from system import MegapadSystem

BIOS_PATH = os.path.join(MEGAPAD_ROOT, "bios.asm")
KDOS_PATH = os.path.join(MEGAPAD_ROOT, "kdos.f")

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


def build_fat32_high_cluster_image(content=b"FAT32 high cluster data",
                                   high_cluster=66000,
                                   total_sectors=70000):
    """Build a minimal real FAT32 image with a file above cluster 0xffff."""
    reserved = 32
    num_fats = 1
    spc = 1
    fat_sectors = 1
    while True:
        first_data = reserved + num_fats * fat_sectors
        data_clusters = (total_sectors - first_data) // spc
        needed = math.ceil((data_clusters + 2) * 4 / SECTOR)
        if needed <= fat_sectors:
            break
        fat_sectors = needed
    first_data = reserved + num_fats * fat_sectors
    data_clusters = total_sectors - first_data
    if not (2 < high_cluster < data_clusters + 2):
        raise ValueError("high cluster is outside FAT32 data geometry")

    image = bytearray(total_sectors * SECTOR)
    image[0:3] = b'\xEB\x58\x90'
    image[3:11] = b'AKASHIC '
    struct.pack_into('<H', image, 11, SECTOR)
    image[13] = spc
    struct.pack_into('<H', image, 14, reserved)
    image[16] = num_fats
    struct.pack_into('<H', image, 17, 0)       # RootEntCnt
    struct.pack_into('<H', image, 19, 0)       # TotSec16
    image[21] = 0xF8
    struct.pack_into('<H', image, 22, 0)       # FATSz16
    struct.pack_into('<I', image, 32, total_sectors)
    struct.pack_into('<I', image, 36, fat_sectors)
    struct.pack_into('<I', image, 44, 2)       # RootClus
    image[510:512] = b'\x55\xAA'

    fat = bytearray(fat_sectors * SECTOR)
    struct.pack_into('<I', fat, 0 * 4, 0x0FFFFFF8)
    struct.pack_into('<I', fat, 1 * 4, 0x0FFFFFFF)
    struct.pack_into('<I', fat, 2 * 4, 0x0FFFFFFF)
    struct.pack_into('<I', fat, high_cluster * 4, 0x0FFFFFFF)
    fat_start = reserved * SECTOR
    image[fat_start:fat_start + len(fat)] = fat

    root_sector = first_data
    entry = _fat16_dir_entry("HIGH.BIN", 0x20, high_cluster, len(content))
    image[root_sector * SECTOR:root_sector * SECTOR + 32] = entry
    # The following all-zero entry is the required end marker.
    file_sector = first_data + (high_cluster - 2) * spc
    image[file_sector * SECTOR:file_sector * SECTOR + len(content)] = content
    return bytes(image), {
        "first_data": first_data,
        "data_clusters": data_clusters,
        "fat_sectors": fat_sectors,
        "high_cluster": high_cluster,
        "content": content,
    }


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
    struct.pack_into('<H', sb, 4, 1)               # marker
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
    for path in [
        EVENT_F, SEM_F, GUARD_F, UTF8_F, MEMORY_SPAN_F,
        VFS_F, VFS_MNT_F, VFS_FAT_F,
    ]:
        dep_lines += _load_forth_lines(path)

    helpers = [
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
        ': T-VFAT-NEW  ( -- vfs )',
        '    T-ARENA _TARN !',
        '    _TARN @ T-VOLUME VFAT-NEW THROW ;',
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


def run_forth(lines, max_steps=800_000_000, disk_image=None,
              storage_faults=None):
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


# ═══════════════════════════════════════════════════════════════════
#  Test Framework
# ═══════════════════════════════════════════════════════════════════

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
        for l in clean.split('\n')[-20:]:
            print(f"        {l}")


# ═══════════════════════════════════════════════════════════════════
# ═══════════════════════════════════════════════════════════════════
#  Tests
# ═══════════════════════════════════════════════════════════════════

def test_constructor_binds_read_only_volume():
    """The public constructor mounts once and exposes an honest descriptor."""
    check("constructor binds read-only volume", [
        'T-ARENA CONSTANT _AR',
        '_AR T-VOLUME VFAT-NEW CONSTANT _IOR CONSTANT _V',
        '_IOR 0=',
        '_V 0<> AND',
        '_V V.LIFECYCLE @ VFS-L-MOUNTED = AND',
        '_V V.VOLUME @ T-VOLUME = AND',
        '_V V.FLAGS @ VFS-F-RO AND 0<> AND',
        'VFAT-BINDING VFS-BINDING-VALID? AND',
        '_V VFS-CAPS@ VFS-CAP-PROBE AND 0<> AND',
        '_V V.BINDING @ VB.FLAGS @ VFS-BF-STABLE-IDS AND 0= AND',
        '_V V.BINDING @ VB.FLAGS @ VFS-BF-CASE-INSENSITIVE AND 0= AND',
        'IF ." FAT-CONSTRUCTOR-OK" THEN',
    ], "FAT-CONSTRUCTOR-OK")


def test_volume_probe_match_nonmatch_and_io_error():
    """FAT PROBE reads the supplied volume and returns structured failures."""
    check("FAT probe match", [
        'VFAT-BINDING T-VOLUME VFS-PROBE CONSTANT _IOR CONSTANT _SCORE',
        '_IOR 0= _SCORE VFAT-PROBE-SCORE = AND IF '
        '." FAT-PROBE-MATCH" THEN',
    ], "FAT-PROBE-MATCH")

    check("FAT probe nonmatch", [
        'VFAT-BINDING T-VOLUME VFS-PROBE CONSTANT _IOR CONSTANT _SCORE',
        '_IOR 0= _SCORE 0= AND IF ." FAT-PROBE-NOMATCH" THEN',
    ], "FAT-PROBE-NOMATCH", disk_image=bytes(32768 * SECTOR))

    check("FAT probe checked I/O error", [
        'VFAT-BINDING T-VOLUME VFS-PROBE CONSTANT _IOR CONSTANT _SCORE',
        '_SCORE 0=',
        '_IOR VFS-IOR-REASON VFS-R-IO = AND',
        '_IOR VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = AND',
        '_IOR VFS-IOR-DETAIL 0<> AND',
        'IF ." FAT-PROBE-IO-ERROR" THEN',
    ], "FAT-PROBE-IO-ERROR", storage_faults=[{
        "stage": "start",
        "result": STORAGE_RESULT_MEDIA_FAILURE,
        "command": STORAGE_CMD_READ,
    }])


def test_constructor_requires_volume():
    """The FAT binding cannot be created without an explicit attachment."""
    check("constructor requires volume", [
        'T-ARENA 0 VFAT-NEW CONSTANT _IOR CONSTANT _V',
        '_V 0= _IOR VFS-IOR-REASON VFS-R-NOVOLUME = AND',
        'IF ." FAT-NOVOLUME-OK" THEN',
    ], "FAT-NOVOLUME-OK")


def test_constructor_propagates_checked_read_failure():
    """Mount exposes a checked volume read failure with backend detail."""
    check("constructor checked-read failure", [
        'T-ARENA T-VOLUME VFAT-NEW CONSTANT _IOR CONSTANT _V',
        '_V 0<>',
        '_IOR VFS-IOR-REASON VFS-R-IO = AND',
        '_IOR VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = AND',
        '_IOR VFS-IOR-DETAIL 0<> AND',
        'IF ." FAT-CHECKED-READ-ERROR-OK" THEN',
    ], "FAT-CHECKED-READ-ERROR-OK", storage_faults=[{
        "stage": "start",
        "result": STORAGE_RESULT_MEDIA_FAILURE,
        "command": STORAGE_CMD_READ,
    }])


def test_constructor_rejects_invalid_formats():
    """Probe and BPB failures are reported by the constructor itself."""
    zeroed = bytes(32768 * SECTOR)

    bad_signature = bytearray(build_fat16_empty())
    bad_signature[510:512] = b"\x00\x00"

    bad_spc = bytearray(build_fat16_empty())
    bad_spc[13] = 3

    fat12 = FAT16ImageBuilder(
        total_sectors=128,
        sectors_per_cluster=1,
        reserved_sectors=1,
        num_fats=2,
        root_entry_count=16,
    ).build()

    total_mismatch = bytearray(build_fat16_empty())
    struct.pack_into('<H', total_mismatch, 19, 32767)

    cases = (
        ("zeroed", zeroed, 11, 1),
        ("boot-signature", bytes(bad_signature), 11, 1),
        ("sector-per-cluster", bytes(bad_spc), 11, 1),
        ("fat12", fat12, 11, 1),
        ("volume-geometry", bytes(total_mismatch), 10, 16),
    )
    for name, image, reason, detail in cases:
        corrupt_flag_check = (
            '_IOR VFS-IOR-FLAGS VFS-IOR-F-CORRUPT AND 0<> AND'
            if reason == 10 else ''
        )
        check(f"constructor rejects {name}", [
            'T-ARENA T-VOLUME VFAT-NEW CONSTANT _IOR CONSTANT _V',
            '_V 0<>',
            f'_IOR VFS-IOR-REASON {reason} = AND',
            '_IOR VFS-IOR-DOMAIN VFS-IOR-D-FORMAT = AND',
            f'_IOR VFS-IOR-DETAIL {detail} = AND',
            corrupt_flag_check,
            'IF ." FAT-FORMAT-REJECT-OK" THEN',
        ], "FAT-FORMAT-REJECT-OK", disk_image=image)


def test_geometry_is_derived_from_bpb_and_volume():
    """The mounted context stores exact FAT16 geometry."""
    builder = FAT16ImageBuilder()
    image = builder.build()
    check("FAT geometry", [
        'T-ARENA T-VOLUME VFAT-NEW CONSTANT _IOR CONSTANT _V',
        '_IOR 0=',
        '_V V.BCTX @ DUP _VFAT-C.TYPE + @ _VFAT-TYPE-FAT16 = AND',
        f'DUP _VFAT-C.SPC + @ {builder.spc} = AND',
        f'DUP _VFAT-C.FDS + @ {builder.first_data_sector} = AND',
        f'_VFAT-C.TOTSEC + @ {builder.total_sectors} = AND',
        'IF ." FAT-GEOMETRY-OK" THEN',
    ], "FAT-GEOMETRY-OK", disk_image=image)


def test_root_and_lazy_subdirectory_reads():
    """FAT16 fixed-root and cluster-backed subdirectory scans both work."""
    check("root and lazy subdirectory reads", [
        'T-VFAT-NEW CONSTANT _V',
        'S" /HELLO.TXT" VFS-FF-READ _V VFS-OPEN? THROW CONSTANT _HF',
        '_RB 17 _HF VFS-READ? THROW 17 =',
        '_RB 17 S" Hello, FAT world!" COMPARE 0= AND',
        'S" /DOCS/README.TXT" VFS-FF-READ _V '
        'VFS-OPEN? THROW CONSTANT _RF',
        '_RB 21 _RF VFS-READ? THROW 21 = AND',
        '_RB 21 S" Inside docs directory" COMPARE 0= AND',
        'S" /hello.txt" _V VFS-RESOLVE 0= AND',
        'IF ." FAT-TREE-READ-OK" THEN',
    ], "FAT-TREE-READ-OK")


def test_binary_read_offset_and_chain_navigation():
    """Binary offsets and checked FAT16 chain lookup preserve data."""
    check("binary offset and chain navigation", [
        'T-VFAT-NEW CONSTANT _V',
        'S" /DATA.BIN" VFS-FF-READ _V VFS-OPEN? THROW CONSTANT _FD',
        '_FD VFS-SIZE 1024 =',
        '250 _FD VFS-SEEK',
        '_RB 20 _FD VFS-READ? THROW 20 = AND',
        '_RB C@ 250 = AND _RB 6 + C@ 0= AND',
        '2 _V V.BCTX @ _VFAT-NEXT-CLUSTER _VFAT-EOC16 = AND',
        'IF ." FAT-OFFSET-OK" THEN',
    ], "FAT-OFFSET-OK")


def test_multicluster_read():
    """Reads traverse a multi-cluster FAT chain across callback calls."""
    data = bytes(range(256)) * 32
    image = build_fat16_image(files=[("BIG.BIN", data, None)])
    check("multicluster read", [
        'T-VFAT-NEW CONSTANT _V',
        '2 _V V.BCTX @ _VFAT-NEXT-CLUSTER 3 =',
        'S" /BIG.BIN" VFS-FF-READ _V VFS-OPEN? THROW CONSTANT _FD',
        '_RB 4096 _FD VFS-READ? THROW 4096 = AND',
        '_RB C@ 0= AND _RB 4095 + C@ 255 = AND',
        '_RB 4096 _FD VFS-READ? THROW 4096 = AND',
        '_RB C@ 0= AND _RB 4095 + C@ 255 = AND',
        'IF ." FAT-MULTICLUSTER-OK" THEN',
    ], "FAT-MULTICLUSTER-OK", disk_image=image)


def test_zero_entry_terminates_fixed_and_cluster_directories():
    """Entries after the first 0x00 marker are never published."""
    builder = FAT16ImageBuilder()
    docs = builder.add_dir("DOCS")
    live_cluster = builder.add_file("LIVE.TXT", b"live")
    builder.add_file("CHILD.TXT", b"child", docs)
    image = bytearray(builder.build())

    root_start = builder.reserved + builder.num_fats * builder.fat_sectors
    root_ghost = _fat16_dir_entry("GHOST.TXT", 0x20, live_cluster, 4)
    # Root slots 0..1 are live, slot 2 is 0x00, so slot 3 is unreachable.
    image[root_start * SECTOR + 3 * 32:root_start * SECTOR + 4 * 32] = root_ghost

    sub_start = builder._cluster_sector(docs) * SECTOR
    sub_ghost = _fat16_dir_entry("GHOST.BIN", 0x20, live_cluster, 4)
    # Cluster slots 0..2 are . / .. / CHILD, slot 3 is the terminator.
    image[sub_start + 4 * 32:sub_start + 5 * 32] = sub_ghost

    check("FAT 0x00 directory terminator", [
        'T-VFAT-NEW CONSTANT _V',
        'S" /LIVE.TXT" _V VFS-RESOLVE 0<>',
        'S" /DOCS/CHILD.TXT" _V VFS-RESOLVE 0<> AND',
        'S" /GHOST.TXT" _V VFS-RESOLVE 0= AND',
        'S" /DOCS/GHOST.BIN" _V VFS-RESOLVE 0= AND',
        'IF ." FAT-TERMINATOR-OK" THEN',
    ], "FAT-TERMINATOR-OK", disk_image=bytes(image))


def test_fat32_root_high_cluster_and_read():
    """Mount and read a FAT32 root file whose cluster uses high 16 bits."""
    image, info = build_fat32_high_cluster_image()
    content = info["content"]
    check("FAT32 root high-cluster read", [
        'VARIABLE _OK',
        'T-ARENA T-VOLUME VFAT-NEW CONSTANT _IOR CONSTANT _V',
        '_IOR 0=',
        '_V V.BCTX @ _VFAT-C.TYPE + @ _VFAT-TYPE-FAT32 = AND',
        '_V V.ROOT @ IN.BID @ 2 = AND',
        '_OK !',
        'S" /HIGH.BIN" _V VFS-RESOLVE DUP IF',
        f'  IN.BID @ {info["high_cluster"]} = _OK @ AND _OK !',
        'ELSE DROP 0 _OK ! THEN',
        'S" /HIGH.BIN" VFS-FF-READ _V VFS-OPEN? THROW CONSTANT _FD',
        f'_OK @ _RB {len(content)} _FD VFS-READ? THROW {len(content)} = AND',
        f'_RB {len(content)} S" {content.decode()}" COMPARE 0= AND',
        'IF ." FAT32-HIGH-READ-OK" THEN',
    ], "FAT32-HIGH-READ-OK", disk_image=image)


def test_read_only_caps_and_mutations_leave_media_unchanged():
    """No mutation capability is advertised or able to alter the image."""
    global _pass_count, _fail_count
    before = bytes(_default_fat_img)
    output, sys_obj = run_forth([
        'T-VFAT-NEW CONSTANT _V',
        'VARIABLE _C VARIABLE _O VARIABLE _R',
        'VFS-CAP-WRITE VFS-CAP-CREATE OR VFS-CAP-MKDIR OR',
        'VFS-CAP-UNLINK OR VFS-CAP-RMDIR OR VFS-CAP-RENAME OR',
        'VFS-CAP-TRUNCATE OR _V VFS-CAPS@ AND 0=',
        'S" NEW.TXT" _V VFS-MKFILE? NIP VFS-IOR-REASON _C !',
        'S" /HELLO.TXT" VFS-FF-WRITE _V VFS-OPEN? NIP '
        'VFS-IOR-REASON _O !',
        'S" /HELLO.TXT" _V VFS-RM VFS-IOR-REASON _R !',
        '_C @ VFS-R-READONLY = AND',
        '_O @ VFS-R-READONLY = AND',
        '_R @ VFS-R-READONLY = AND',
        '_V VFS-SYNC 0= AND',
        'IF ." FAT-READONLY-OK" THEN',
    ])
    after = bytes(sys_obj.storage._image_data[:len(before)])
    ok = "FAT-READONLY-OK" in output and after == before
    if ok:
        _pass_count += 1
        print("  PASS  read-only caps and immutable media")
    else:
        _fail_count += 1
        print("  FAIL  read-only caps and immutable media")
        print("        media unchanged:", after == before)
        print("        output:", output[-1500:])


def test_unmount_and_destroy_lifecycle():
    """Required unmount support transitions cleanly before destruction."""
    check("unmount and destroy lifecycle", [
        'T-VFAT-NEW CONSTANT _V',
        '0 _V VFS-UNMOUNT 0=',
        '_V V.LIFECYCLE @ VFS-L-UNMOUNTED = AND',
        'IF _V VFS-DESTROY ." FAT-DESTROY-OK" THEN',
    ], "FAT-DESTROY-OK")


def test_nonzero_bounded_volume_slice_read():
    """FAT reads a nonzero slice without touching either guard region."""
    global _pass_count, _fail_count
    base = 3
    suffix = 4
    inner = bytes(_default_fat_img)
    sectors = len(inner) // SECTOR
    prefix_bytes = bytes([0xC3]) * (base * SECTOR)
    suffix_bytes = bytes([0x3C]) * (suffix * SECTOR)
    parent_image = prefix_bytes + inner + suffix_bytes
    output, sys_obj = run_forth([
        'CREATE _SBD /BLOCK-DEVICE ALLOT',
        'CREATE _SVOL /VOLUME ALLOT',
        '_SBD BD-OPEN THROW',
        f'{base} {sectors} VOL-SCHEME-RAW 0 _SBD _SVOL VOL-SLICE THROW',
        'T-ARENA _SVOL VFAT-NEW THROW CONSTANT _SV',
        'S" /HELLO.TXT" VFS-FF-READ _SV VFS-OPEN? THROW CONSTANT _FD',
        '_RB 17 _FD VFS-READ? THROW DROP _RB 17 TYPE',
    ], disk_image=parent_image)
    media = bytes(sys_obj.storage._image_data)
    slice_end = (base + sectors) * SECTOR
    guards_ok = (
        media[:base * SECTOR] == prefix_bytes
        and media[slice_end:slice_end + len(suffix_bytes)] == suffix_bytes
    )
    ok = "Hello, FAT world!" in output and guards_ok
    if ok:
        _pass_count += 1
        print("  PASS  nonzero bounded FAT volume slice")
    else:
        _fail_count += 1
        print("  FAIL  nonzero bounded FAT volume slice")
        print("        guards:", guards_ok)
        print("        output:", output[-1500:])


def test_structured_volume_error_translation():
    """Backend detail/flags survive translation and stale latches the VFS."""
    check("structured FAT volume error translation", [
        'T-VFAT-NEW CONSTANT _V',
        '_V _VFAT-IO-V !',
        '7 7 IOR-D-BLOCK IOR-F-PARTIAL IOR-F-RETRYABLE OR '
        'IOR-MAKE CONSTANT _BE',
        '2 _VFAT-IO-EXPECTED ! 1 _VFAT-IO-COMPLETED !',
        '_BE _VFAT-MAP-IOR CONSTANT _E',
        '_E VFS-IOR-REASON VFS-R-IO =',
        '_E VFS-IOR-DOMAIN VFS-IOR-D-VOLUME = AND',
        '_E VFS-IOR-FLAGS VFS-IOR-F-PARTIAL AND 0<> AND',
        '_E VFS-IOR-FLAGS VFS-IOR-F-RETRYABLE AND 0<> AND',
        '_E VFS-IOR-DETAIL _BE = AND',
        '1 _VFAT-IO-EXPECTED ! 0 _VFAT-IO-COMPLETED !',
        'VOL-E-STALE _VFAT-MAP-IOR CONSTANT _SE',
        '_SE VFS-IOR-REASON VFS-R-STALE = AND',
        '_SE VFS-IOR-FLAGS VFS-IOR-F-STALE AND 0<> AND',
        '_V V.LIFECYCLE @ VFS-L-STALE = AND',
        'IF ." FAT-ERROR-MAP-OK" THEN',
    ], "FAT-ERROR-MAP-OK")


def test_mount_population_nomem_rolls_back():
    """Mount reports NOMEM without publishing a partial FAT root."""
    check("FAT mount population NOMEM rollback", [
        ': _OOM-MOUNT  ( vfs -- ior )',
        '  DUP V.STR-PTR @ OVER V.STR-END ! VFAT-INIT ;',
        'CREATE _OOM-OPS VFS-OPS-SIZE ALLOT',
        'VFAT-OPS _OOM-OPS VFS-OPS-SIZE CMOVE',
        "' _OOM-MOUNT _OOM-OPS VFS-OP-MOUNT CELLS + !",
        'CREATE _OOM-BINDING',
        'VFS-BINDING-MAGIC , VFS-BINDING-ABI-MAJOR ,',
        'VFS-BINDING-ABI-MINOR , VFS-BINDING-DESC-SIZE ,',
        'VFS-OPS-SIZE , VFAT-CAPS ,',
        'VFS-BF-NEEDS-VOLUME VFS-BF-READ-ONLY OR ,',
        '_OOM-OPS , 0 , 0 ,',
        'T-ARENA CONSTANT _OAR',
        '_OAR _OOM-BINDING T-VOLUME VFS-NEW CONSTANT _OI CONSTANT _OV',
        '_OI VFS-IOR-REASON VFS-R-NOMEM =',
        '_OV V.ROOT @ IN.CHILD @ 0= AND',
        '_OV V.ICOUNT @ 1 = AND',
        '_OV V.VCOUNT @ 1 = AND',
        '_OV V.ROOT @ IN.FLAGS @ VFS-IF-CHILDREN AND 0= AND',
        '_OV V.BCTX @ _VFAT-C.TYPE + @ 0= AND',
        'VARIABLE _AP _OAR A.PTR @ _AP !',
        '_OV VFAT-INIT _OI = AND',
        '_OAR A.PTR @ _AP @ = AND',
        '_OV V.LAST-IOR @ _OI = AND',
        'IF ." FAT-MOUNT-NOMEM-OK" THEN',
    ], "FAT-MOUNT-NOMEM-OK")


def test_readdir_population_nomem_rolls_back():
    """A failed lazy scan restores child/count/string observations."""
    check("FAT readdir population NOMEM rollback", [
        'T-VFAT-NEW CONSTANT _V',
        'S" /DOCS" _V VFS-RESOLVE CONSTANT _D',
        'VARIABLE _IC VARIABLE _VC VARIABLE _SP',
        '_V V.ICOUNT @ _IC ! _V V.VCOUNT @ _VC ! _V V.STR-PTR @ _SP !',
        '_SP @ _V V.STR-END !',
        '_D _V _VFAT-READDIR VFS-IOR-REASON VFS-R-NOMEM =',
        '_D IN.CHILD @ 0= AND',
        '_V V.ICOUNT @ _IC @ = AND',
        '_V V.VCOUNT @ _VC @ = AND',
        '_V V.STR-PTR @ _SP @ = AND',
        '_D IN.FLAGS @ VFS-IF-CHILDREN AND 0= AND',
        'IF ." FAT-READDIR-NOMEM-OK" THEN',
    ], "FAT-READDIR-NOMEM-OK")


def test_fat16_root_refill_uses_fixed_root_area():
    """After invalidation, FAT16 root readdir uses BID 0, not a cluster."""
    check("FAT16 root refill", [
        'T-VFAT-NEW CONSTANT _V',
        ': _CLEAR-ROOT',
        '  BEGIN _V V.ROOT @ IN.CHILD @ ?DUP WHILE',
        '    DUP _V V.ROOT @ _VFS-REMOVE-CHILD',
        '    TRUE _V _VFS-DENTRY-RELEASE',
        '    -1 _V V.ICOUNT +!',
        '  REPEAT',
        '  _V V.ROOT @ IN.FLAGS DUP @ VFS-IF-CHILDREN INVERT AND SWAP ! ;',
        '_CLEAR-ROOT',
        '_V V.ROOT @ IN.BID @ 0=',
        '_V V.ROOT @ _V _VFS-ENSURE-CHILDREN? 0= AND',
        'S" /HELLO.TXT" _V VFS-RESOLVE 0<> AND',
        'IF ." FAT16-ROOT-REFILL-OK" THEN',
    ], "FAT16-ROOT-REFILL-OK")


# ═══════════════════════════════════════════════════════════════════
#  Runner
# ═══════════════════════════════════════════════════════════════════

def main():
    build_snapshot()
    print()
    print("=" * 60)
    print("  VFS-FAT Read-Only Volume-Binding Tests")
    print("=" * 60)

    test_constructor_binds_read_only_volume()
    test_volume_probe_match_nonmatch_and_io_error()
    test_constructor_requires_volume()
    test_constructor_propagates_checked_read_failure()
    test_constructor_rejects_invalid_formats()
    test_geometry_is_derived_from_bpb_and_volume()
    test_root_and_lazy_subdirectory_reads()
    test_binary_read_offset_and_chain_navigation()
    test_multicluster_read()
    test_zero_entry_terminates_fixed_and_cluster_directories()
    test_fat32_root_high_cluster_and_read()
    test_read_only_caps_and_mutations_leave_media_unchanged()
    test_unmount_and_destroy_lifecycle()
    test_nonzero_bounded_volume_slice_read()
    test_structured_volume_error_translation()
    test_mount_population_nomem_rolls_back()
    test_readdir_population_nomem_rolls_back()
    test_fat16_root_refill_uses_fixed_root_area()

    print()
    total = _pass_count + _fail_count
    print(f"  Results: {_pass_count} passed, {_fail_count} failed ({total} total)")
    if _fail_count:
        sys.exit(1)


if __name__ == "__main__":
    try:
        main()
    finally:
        if _boot_img_path and os.path.exists(_boot_img_path):
            os.unlink(_boot_img_path)
