#!/usr/bin/env python3
"""Test suite for Akashic vfs.f (akashic/utils/fs/vfs.f).

Tests:
  - VFS-NEW creates a valid VFS instance (descriptor fields non-zero)
  - Root inode exists and has type VFS-T-DIR
  - VFS-USE / VFS-CUR context management
  - VFS-MKFILE creates a file in cwd
  - VFS-MKDIR creates a subdirectory
  - VFS-OPEN / VFS-CLOSE / VFS-READ / VFS-WRITE file I/O round-trip
  - VFS-SEEK / VFS-REWIND / VFS-TELL cursor management
  - VFS-SIZE returns correct file size
  - VFS-RESOLVE path resolution (absolute, relative, dot, dotdot)
  - VFS-DIR lists directory contents
  - VFS-CD changes cwd
  - VFS-STAT prints file/dir metadata
  - VFS-RM removes files and empty directories
  - VFS-SYNC flushes dirty inodes
  - VFS-SET-HWM adjusts eviction threshold
  - VFS-DESTROY tears down without crash
  - Multiple VFS instances coexist
  - Write-then-read round-trip through ramdisk binding
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
if not os.path.isdir(EMU_DIR):
    EMU_DIR = os.path.abspath(os.path.join(ROOT_DIR, "..", "megapad"))
TEST_STORAGE = "/tmp/akashic-vfs-contract-volume.img"

# Dependency file paths (in topological load order)
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
SEM_F      = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")
GUARD_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "guard.f")
UTF8_F     = os.path.join(ROOT_DIR, "akashic", "text", "utf8.f")
MEMORY_SPAN_F = os.path.join(ROOT_DIR, "akashic", "utils", "memory-span.f")
VFS_F      = os.path.join(ROOT_DIR, "akashic", "utils", "fs", "vfs.f")

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
    if _snapshot:
        return _snapshot
    print("[*] Building snapshot: BIOS + KDOS + utf8 + vfs ...")
    t0 = time.time()
    bios_code  = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)

    dep_lines = []
    for path in [EVENT_F, SEM_F, GUARD_F, UTF8_F, MEMORY_SPAN_F, VFS_F]:
        dep_lines += _load_forth_lines(path)

    helpers = [
        # Temp buffer for I/O tests
        'CREATE _TB 4096 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        # Read buffer
        'CREATE _RB 4096 ALLOT',
        # VFS init helper: create a ramdisk VFS in ext-mem arena
        'VARIABLE _TARN',
        'VARIABLE _TC-BIND VARIABLE _TC-VOL',
        'CREATE _TC-OPS VFS-OPS-SIZE ALLOT',
        'CREATE _TC-BINDING VFS-BINDING-DESC-SIZE ALLOT',
        ': T-BINDING-CLONE  ( -- binding )',
        '    VFS-RAM-OPS _TC-OPS VFS-OPS-SIZE MOVE',
        '    VFS-RAM-BINDING _TC-BINDING VFS-BINDING-DESC-SIZE MOVE',
        '    _TC-OPS _TC-BINDING VB.OPS !  _TC-BINDING ;',
        ': T-VFS-NEW-WITH  ( binding volume -- vfs )',
        '    _TC-VOL ! _TC-BIND !',
        '    524288 A-XMEM ARENA-NEW  IF -1 THROW THEN  _TARN !',
        '    _TARN @ _TC-BIND @ _TC-VOL @ VFS-NEW ?DUP IF THROW THEN ;',
        ': T-VFS-NEW  ( -- vfs )  VFS-RAM-BINDING 0 T-VFS-NEW-WITH ;',
    ]

    sys_obj = MegapadSystem(ram_size=1024*1024,
                            ext_mem_size=16 * (1 << 20),
                            storage_image=TEST_STORAGE)
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + ["ENTER-USERLAND"]
                 + dep_lines + helpers)
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
        for l in text.strip().split('\n')[-30:]:
            print(f"    {l}")
        sys.exit(1)
    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot

def run_forth(lines, max_steps=800_000_000):
    if _snapshot is None:
        build_snapshot()
    bios_code, mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024*1024,
                            ext_mem_size=16 * (1 << 20),
                            storage_image=TEST_STORAGE)
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

# ═══════════════════════════════════════════════════════════════════
#  Test Cases
# ═══════════════════════════════════════════════════════════════════

# ── VFS-NEW / basic descriptor ──

def test_vfs_new():
    """VFS-NEW returns a non-zero handle, sets root and cwd."""
    check("vfs-new returns non-zero", [
        'T-VFS-NEW',
        'DUP 0<> IF ." OK" ELSE ." FAIL" THEN DROP',
    ], "OK")

def test_root_inode_type():
    """Root inode has type VFS-T-DIR (2)."""
    check("root inode type = VFS-T-DIR", [
        'T-VFS-NEW',
        'V.ROOT @ IN.TYPE @ . CR',
    ], "2")

def test_root_inode_name():
    """Root inode name is '/'."""
    check("root inode name = /", [
        'T-VFS-NEW',
        'V.ROOT @ IN.NAME @',
        'DUP 16 + SWAP @ TYPE CR',
    ], "/")

def test_cwd_equals_root():
    """After VFS-NEW, cwd = root."""
    check("cwd = root after new", [
        'T-VFS-NEW',
        'DUP V.CWD @  OVER V.ROOT @  = IF ." OK" ELSE ." FAIL" THEN DROP',
    ], "OK")

def test_binding_descriptor_validation():
    """The ABI major is exact; same-major additive minors use caps and sizes."""
    check("binding descriptor validation", [
        'CREATE _BAD-OPS VFS-OPS-SIZE ALLOT',
        '_BAD-OPS VFS-OPS-SIZE 0 FILL',
        'CREATE _BAD-BIND',
        'VFS-BINDING-MAGIC , VFS-BINDING-ABI-MAJOR , 0 ,',
        'VFS-BINDING-DESC-SIZE , VFS-OPS-SIZE , VFS-CAP-MOUNT ,',
        '0 , _BAD-OPS , 0 , 0 ,',
        'T-BINDING-CLONE CONSTANT _VERSIONED-BIND',
        ': T-BIND-VALID',
        '  VFS-RAM-BINDING VFS-BINDING-VALID? IF ." RAM " THEN',
        '  7 _VERSIONED-BIND VB.MINOR !',
        '  _VERSIONED-BIND VFS-BINDING-VALID? IF ." MINOR " THEN',
        '  VFS-BINDING-ABI-MAJOR 1+ _VERSIONED-BIND VB.MAJOR !',
        '  _VERSIONED-BIND VFS-BINDING-VALID? 0= IF ." MAJOR " THEN',
        '  _BAD-BIND VFS-BINDING-VALID? 0= IF ." MISSING-XT " THEN',
        '  0 _BAD-BIND VB.MAGIC !',
        '  _BAD-BIND VFS-BINDING-VALID? 0= IF ." MAGIC" THEN ;',
        'T-BIND-VALID CR',
    ], "RAM MINOR MAJOR MISSING-XT MAGIC")

def test_binding_semantic_capability_validation():
    """Semantic claims and namespace flags require their ABI prerequisites."""
    check("binding semantic capability validation", [
        'T-BINDING-CLONE CONSTANT _BIND',
        ': T-SEMANTIC-VALIDATION',
        '  _BIND VB.CAPS DUP @ VFS-CAP-RENAME INVERT AND SWAP !',
        '  _BIND VFS-BINDING-VALID? 0= IF ." RENAME " THEN',
        '  T-BINDING-CLONE DROP',
        '  _BIND VB.CAPS DUP @ VFS-CAP-FSYNC INVERT AND VFS-CAP-DATA-ONLY-FSYNC OR SWAP !',
        '  _BIND VFS-BINDING-VALID? 0= IF ." DATA-FSYNC " THEN',
        '  T-BINDING-CLONE DROP',
        '  0 _BIND VB.FLAGS !',
        '  _BIND VFS-BINDING-VALID? 0= IF ." STABLE-HANDLE " THEN',
        '  T-BINDING-CLONE DROP',
        '  _BIND VB.CAPS DUP @ VFS-CAP-GETATTR INVERT AND SWAP !',
        '  _BIND VFS-BINDING-VALID? 0= IF ." STABLE-ID " THEN',
        '  T-BINDING-CLONE DROP',
        '  _BIND VB.FLAGS DUP @ VFS-BF-CASE-INSENSITIVE OR SWAP !',
        '  _BIND VFS-BINDING-VALID? 0= IF ." CASE-FOLD" THEN ;',
        'T-SEMANTIC-VALIDATION CR',
    ], "RENAME DATA-FSYNC STABLE-HANDLE STABLE-ID CASE-FOLD")

def test_probe_capability_and_dispatch():
    """PROBE dispatch is cap-gated and validates the standardized score."""
    check("probe capability and dispatch", [
        'VARIABLE _PROBE-CALLS',
        ': T-PROBE  DROP 1 _PROBE-CALLS +! 42 0 ;',
        ': T-BAD-PROBE  DROP 1 _PROBE-CALLS +! 101 0 ;',
        'T-BINDING-CLONE CONSTANT _BIND',
        "' T-PROBE _BIND VB.OPS @ VFS-OP-PROBE CELLS + !",
        ': T-PROBE-ABI',
        '  _BIND 0 VFS-PROBE DUP VFS-IOR-REASON 11 = IF ." UNSUPPORTED " THEN SWAP 0= IF ." ZERO " THEN DROP',
        '  _PROBE-CALLS @ 0= IF ." NO-CALL " THEN',
        '  _BIND VB.CAPS DUP @ VFS-CAP-PROBE OR SWAP !',
        '  _BIND 0 VFS-PROBE 0= SWAP 42 = AND IF ." SCORE " THEN',
        '  _PROBE-CALLS @ 1 = IF ." CALLED " THEN',
        "  ['] T-BAD-PROBE _BIND VB.OPS @ VFS-OP-PROBE CELLS + !",
        '  _BIND 0 VFS-PROBE DUP VFS-IOR-REASON 10 = IF ." RANGE " THEN SWAP 0= IF ." BAD-ZERO" THEN DROP ;',
        'T-PROBE-ABI CR',
    ], "UNSUPPORTED ZERO NO-CALL SCORE CALLED RANGE BAD-ZERO")

def test_structured_ior_round_trip():
    """Distinct nonzero fields survive VFS ior packing without transposition."""
    check("structured ior asymmetric round trip", [
        '0xAA12345678 0x1A5 0x13C 0x1BEEF VFS-IOR-MAKE CONSTANT _IOR',
        ': T-IOR-ROUNDTRIP  _IOR VFS-IOR-DETAIL 0x12345678 = IF ." DETAIL " THEN  _IOR VFS-IOR-FLAGS 0xA5 = IF ." FLAGS " THEN  _IOR VFS-IOR-DOMAIN 0x3C = IF ." DOMAIN " THEN  _IOR VFS-IOR-REASON 0xBEEF = IF ." REASON" THEN ;',
        'T-IOR-ROUNDTRIP CR',
    ], "DETAIL FLAGS DOMAIN REASON")

def test_volume_required_rejects_null_attachment():
    """A binding that requires a volume cannot mount with volume=0."""
    check("volume-required binding rejects null", [
        'T-BINDING-CLONE CONSTANT _BIND',
        '_BIND VB.FLAGS DUP @ VFS-BF-NEEDS-VOLUME OR SWAP !',
        '131072 A-XMEM ARENA-NEW IF -1 THROW THEN',
        '_BIND 0 VFS-NEW',
        'SWAP DROP VFS-IOR-REASON . CR',
    ], "21")

def test_volume_attachment_snapshot_and_stale_transition():
    """A required volume is snapshotted and attachment drift is terminal."""
    check("volume snapshot and stale transition", [
        'CREATE _BD /BLOCK-DEVICE ALLOT CREATE _VOL /VOLUME ALLOT',
        '_BD BD-OPEN ?DUP IF THROW THEN _BD _VOL VOL-RAW ?DUP IF THROW THEN',
        'T-BINDING-CLONE CONSTANT _BIND',
        '_BIND VB.FLAGS DUP @ VFS-BF-NEEDS-VOLUME OR SWAP !',
        '_BIND _VOL T-VFS-NEW-WITH CONSTANT _V1',
        ': T-VOLUME-SNAPSHOT  _V1 V.VOLUME @ _VOL = IF ." VOLUME " THEN  _V1 V.VOL-COOKIE @ _VOL VOL.COOKIE = IF ." COOKIE " THEN  _V1 V.MEDIA-GEN @ _VOL VOL.MEDIA-GEN = IF ." GEN " THEN  _VOL 40 + DUP @ 1+ SWAP !  _V1 VFS-SYNC VFS-IOR-REASON 13 = IF ." STALE " THEN  _V1 V.LIFECYCLE @ VFS-L-STALE = IF ." TERMINAL" THEN ;',
        'T-VOLUME-SNAPSHOT CR',
    ], "VOLUME COOKIE GEN STALE TERMINAL")

def test_volume_readonly_authority_propagates():
    """A read-only volume makes the VFS read-only even with a writable binding."""
    check("volume read-only authority propagates", [
        'CREATE _BD /BLOCK-DEVICE ALLOT CREATE _VOL /VOLUME ALLOT',
        '_BD BD-OPEN ?DUP IF THROW THEN _BD _VOL VOL-RAW ?DUP IF THROW THEN',
        '_VOL 72 + DUP @ VOL-F-READONLY OR SWAP !',
        'T-BINDING-CLONE CONSTANT _BIND',
        '_BIND VB.FLAGS DUP @ VFS-BF-NEEDS-VOLUME OR SWAP !',
        '_BIND _VOL T-VFS-NEW-WITH CONSTANT _V1',
        ': T-VOL-RO  _V1 V.FLAGS @ VFS-F-RO AND IF ." RO " THEN  S" f" _V1 VFS-MKFILE? DUP VFS-IOR-REASON 7 = IF ." BLOCKED " THEN  SWAP 0= IF ." NO-FILE" THEN DROP ;',
        'T-VOL-RO CR',
    ], "RO BLOCKED NO-FILE")

def test_lookup_capability_and_dispatch():
    """LOOKUP cannot call an unadvertised XT and publishes one cached dentry."""
    check("lookup capability and dispatch", [
        'VARIABLE _LOOKUP-CALLS VARIABLE _LOOKUP-A VARIABLE _LOOKUP-U',
        'VARIABLE _LOOKUP-P VARIABLE _LOOKUP-V',
        ': T-LOOKUP  _LOOKUP-V ! _LOOKUP-P ! _LOOKUP-U ! _LOOKUP-A !',
        '  1 _LOOKUP-CALLS +!',
        '  _LOOKUP-A @ _LOOKUP-U @ VFS-T-FILE 99 7 _LOOKUP-P @ _LOOKUP-V @ VFS-CACHE-DENTRY ;',
        'T-BINDING-CLONE CONSTANT _BIND',
        "' T-LOOKUP _BIND VB.OPS @ VFS-OP-LOOKUP CELLS + !",
        '_BIND 0 T-VFS-NEW-WITH CONSTANT _V1',
        ': T-LOOKUP-ABI',
        '  S" disk" _V1 V.ROOT @ _V1 VFS-LOOKUP DUP VFS-IOR-REASON 11 = IF ." UNSUPPORTED " THEN SWAP 0= IF ." ZERO " THEN DROP',
        '  _LOOKUP-CALLS @ 0= IF ." NO-CALL " THEN',
        '  _BIND VB.CAPS DUP @ VFS-CAP-LOOKUP OR SWAP !',
        '  S" disk" _V1 V.ROOT @ _V1 VFS-LOOKUP ?DUP IF THROW THEN',
        '  DUP IN.BID @ 99 = OVER D.VNODE @ VN.GEN @ 7 = AND IF ." FOUND " THEN DROP',
        '  S" disk" _V1 V.ROOT @ _V1 VFS-LOOKUP ?DUP IF THROW THEN DROP',
        '  _LOOKUP-CALLS @ 1 = IF ." CACHED" THEN ;',
        'T-LOOKUP-ABI CR',
    ], "UNSUPPORTED ZERO NO-CALL FOUND CACHED")

def test_unadvertised_operation_is_unsupported():
    """A populated XT is unavailable when its capability is not advertised."""
    check("unadvertised operation is unsupported", [
        'T-BINDING-CLONE CONSTANT _BIND',
        '_BIND VB.CAPS DUP @ VFS-CAP-LINK INVERT AND SWAP !',
        '_BIND 0 T-VFS-NEW-WITH CONSTANT _V1',
        'S" source" _V1 VFS-MKFILE CONSTANT _SRC',
        'S" alias" _SRC _V1 V.ROOT @ _V1 VFS-LINK',
        'SWAP 0= IF VFS-IOR-REASON . ELSE DROP ." BAD" THEN CR',
    ], "11")

def test_absent_metadata_cap_does_not_invoke_xt():
    """Capability refusal wins even when a private table contains an XT."""
    check("absent metadata cap does not invoke", [
        'VARIABLE _META-CALLS',
        ': T-GETXATTR  2DROP 2DROP 2DROP 1 _META-CALLS +! 0 0 ;',
        'T-BINDING-CLONE CONSTANT _BIND',
        "' T-GETXATTR _BIND VB.OPS @ VFS-OP-GETXATTR CELLS + !",
        '_BIND 0 T-VFS-NEW-WITH CONSTANT _V1 S" f" _V1 VFS-MKFILE CONSTANT _IN',
        ': T-NO-META-CAP  S" user.test" 0 0 _IN _V1 VFS-GETXATTR  DUP VFS-IOR-REASON 11 = IF ." UNSUPPORTED " THEN  SWAP 0= IF ." ZERO " THEN  DROP  _META-CALLS @ 0= IF ." NO-CALL" THEN ;',
        'T-NO-META-CAP CR',
    ], "UNSUPPORTED ZERO NO-CALL")

def test_mount_error_keeps_instance_unmounted():
    """A mount failure is returned and never publishes a mounted instance."""
    check("mount failure is not published", [
        ': T-MOUNT-FAIL  DROP VFS-E-IO ;',
        'T-BINDING-CLONE CONSTANT _BIND',
        "' T-MOUNT-FAIL _BIND VB.OPS @ VFS-OP-MOUNT CELLS + !",
        '131072 A-XMEM ARENA-NEW IF -1 THROW THEN',
        '_BIND 0 VFS-NEW',
        ': T-MOUNT-STATE  DUP VFS-IOR-REASON 9 = IF ." IOR " THEN  DROP DUP V.LIFECYCLE @ VFS-L-NEW = IF ." NEW " THEN  V.LAST-IOR @ VFS-IOR-REASON 9 = IF ." LAST" THEN ;',
        'T-MOUNT-STATE CR',
    ], "IOR NEW LAST")

def test_constructor_nospace_rolls_back_arena():
    """Pre-mount allocation failure returns NOMEM with no arena consumption."""
    check("constructor NOMEM rolls back arena", [
        '512 A-XMEM ARENA-NEW IF -1 THROW THEN CONSTANT _AR',
        '_AR ARENA-USED CONSTANT _BEFORE',
        '_AR VFS-RAM-BINDING 0 VFS-NEW',
        ': T-SMALL-ARENA  DUP VFS-IOR-REASON 20 = IF ." NOMEM " THEN  DROP 0= IF ." NO-VFS " THEN  _AR ARENA-USED _BEFORE = IF ." ROLLED-BACK" THEN ;',
        'T-SMALL-ARENA CR',
    ], "NOMEM NO-VFS ROLLED-BACK")

def test_slab_growth_nospace_is_transactional():
    """A failed second slab allocation leaves the tree and count unchanged."""
    check("slab growth NOMEM is transactional", [
        '40000 A-XMEM ARENA-NEW IF -1 THROW THEN CONSTANT _AR',
        '_AR VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN CONSTANT _V1',
        'CREATE _NAME 2 ALLOT',
        ': T-FILL-SLAB  63 0 DO  102 _NAME C! I 64 + _NAME 1+ C!  _NAME 2 _V1 VFS-MKFILE? ?DUP IF THROW THEN DROP  LOOP ;',
        'T-FILL-SLAB',
        ': T-SLAB-NOMEM  S" overflow" _V1 VFS-MKFILE? DUP VFS-IOR-REASON 20 = IF ." NOMEM " THEN  DROP 0= IF ." NO-INODE " THEN  _V1 V.ICOUNT @ 64 = IF ." COUNT " THEN  S" overflow" _V1 VFS-RESOLVE 0= IF ." NO-NAME" THEN ;',
        'T-SLAB-NOMEM CR',
    ], "NOMEM NO-INODE COUNT NO-NAME")

def test_multi_slab_chain_is_traversed_by_sync():
    """A grown slab retains the older-page link used by full-cache walks."""
    check("multi-slab chain survives and sync traverses it", [
        'T-VFS-NEW CONSTANT _V1',
        'S" first" _V1 VFS-MKFILE CONSTANT _FIRST',
        'CREATE _SLAB-NAME 3 ALLOT 120 _SLAB-NAME C!',
        'VARIABLE _LAST',
        ': T-GROW-SLAB  69 0 DO  I 26 / 65 + _SLAB-NAME 1+ C!  I 26 MOD 65 + _SLAB-NAME 2 + C!  _SLAB-NAME 3 _V1 VFS-MKFILE? ?DUP IF THROW THEN _LAST !  LOOP ;',
        'T-GROW-SLAB',
        ': T-SLAB-WALK  _V1 V.ISLAB @ @ 0<> IF ." LINK " THEN  VFS-IF-DIRTY _FIRST IN.FLAGS DUP @ ROT OR SWAP !  VFS-IF-DIRTY _LAST @ IN.FLAGS DUP @ ROT OR SWAP !  _V1 VFS-SYNC 0= IF ." SYNC " THEN  _FIRST IN.FLAGS @ VFS-IF-DIRTY AND 0= IF ." OLD-CLEAN " THEN  _LAST @ IN.FLAGS @ VFS-IF-DIRTY AND 0= IF ." NEW-CLEAN" THEN ;',
        'T-SLAB-WALK CR',
    ], "LINK SYNC OLD-CLEAN NEW-CLEAN")

def test_setattr_mask_publishes_zero_and_preserves_unselected():
    """VA.MASK distinguishes selected zero values from untouched fields."""
    check("setattr mask handles zero values", [
        'VARIABLE _SETATTR-CALLS',
        ': T-SETATTR  2DROP DROP 1 _SETATTR-CALLS +! 0 ;',
        'T-BINDING-CLONE CONSTANT _BIND',
        "' T-SETATTR _BIND VB.OPS @ VFS-OP-SETATTR CELLS + !",
        '_BIND VB.CAPS DUP @ VFS-CAP-SETATTR OR SWAP !',
        '_BIND 0 T-VFS-NEW-WITH CONSTANT _V1 S" f" _V1 VFS-MKFILE CONSTANT _IN',
        '123 _IN IN.MODE ! 77 _IN D.VNODE @ VN.UID ! 88 _IN D.VNODE @ VN.GID !',
        'CREATE _ATTR VFS-ATTR-SIZE ALLOT _ATTR VFS-ATTR-SIZE 0 FILL',
        'VFS-SA-MODE VFS-SA-UID OR _ATTR VA.MASK ! 999 _ATTR VA.GID !',
        ': T-SETATTR-ZERO  _ATTR _IN _V1 VFS-SETATTR 0= IF ." OK " THEN  _SETATTR-CALLS @ 1 = IF ." CALLED " THEN  _IN IN.MODE @ 0= _IN D.VNODE @ VN.UID @ 0= AND IF ." ZERO " THEN  _IN D.VNODE @ VN.GID @ 88 = IF ." PRESERVED" THEN ;',
        'T-SETATTR-ZERO CR',
    ], "OK CALLED ZERO PRESERVED")

def test_ext4_facing_dispatch_surface():
    """Private-cap callbacks receive metadata, symlink, xattr, and statfs calls."""
    check("ext4-facing dispatch surface", [
        'VARIABLE _DISPATCH-CALLS : T-HIT  1 _DISPATCH-CALLS +! ;',
        ': T-GETATTR  2DROP T-HIT 0 ;',
        ': T-SETATTR  2DROP DROP T-HIT 0 ;',
        ': T-SYMLINK  2DROP 2DROP T-HIT 0 ;',
        ': T-READLINK  2DROP 2DROP T-HIT 4 0 ;',
        ': T-LISTXATTR  2DROP 2DROP T-HIT 2 0 ;',
        ': T-GETXATTR  2DROP 2DROP 2DROP T-HIT 3 0 ;',
        ': T-SETXATTR  2DROP 2DROP 2DROP DROP T-HIT 0 ;',
        ': T-REMOVEXATTR  2DROP 2DROP T-HIT 0 ;',
        ': T-STATFS  2DROP DROP T-HIT 0 ;',
        'T-BINDING-CLONE CONSTANT _BIND',
        "' T-GETATTR _BIND VB.OPS @ VFS-OP-GETATTR CELLS + !",
        "' T-SETATTR _BIND VB.OPS @ VFS-OP-SETATTR CELLS + !",
        "' T-SYMLINK _BIND VB.OPS @ VFS-OP-SYMLINK CELLS + !",
        "' T-READLINK _BIND VB.OPS @ VFS-OP-READLINK CELLS + !",
        "' T-LISTXATTR _BIND VB.OPS @ VFS-OP-LISTXATTR CELLS + !",
        "' T-GETXATTR _BIND VB.OPS @ VFS-OP-GETXATTR CELLS + !",
        "' T-SETXATTR _BIND VB.OPS @ VFS-OP-SETXATTR CELLS + !",
        "' T-REMOVEXATTR _BIND VB.OPS @ VFS-OP-REMOVEXATTR CELLS + !",
        "' T-STATFS _BIND VB.OPS @ VFS-OP-STATFS CELLS + !",
        'VFS-CAP-GETATTR VFS-CAP-SETATTR OR VFS-CAP-SYMLINK OR VFS-CAP-READLINK OR VFS-CAP-LISTXATTR OR VFS-CAP-GETXATTR OR VFS-CAP-SETXATTR OR VFS-CAP-REMOVEXATTR OR VFS-CAP-STATFS OR CONSTANT _META-CAPS',
        '_BIND VB.CAPS DUP @ _META-CAPS OR SWAP !',
        '_BIND 0 T-VFS-NEW-WITH CONSTANT _V1 S" f" _V1 VFS-MKFILE CONSTANT _IN',
        'CREATE _ATTR VFS-ATTR-SIZE ALLOT _ATTR VFS-ATTR-SIZE 0 FILL VFS-SA-MODE _ATTR VA.MASK !',
        'CREATE _SFS VFS-STATFS-SIZE ALLOT',
        'S" target" S" sym" _V1 V.ROOT @ _V1 VFS-SYMLINK ?DUP IF THROW THEN CONSTANT _SYM',
        ': T-META-DISPATCH  _IN _V1 VFS-GETATTR 0= IF ." GA " THEN  _ATTR _IN _V1 VFS-SETATTR 0= IF ." SA " THEN  _RB 8 _SYM _V1 VFS-READLINK 0= SWAP 4 = AND IF ." RL " THEN  _RB 8 _IN _V1 VFS-LISTXATTR 0= SWAP 2 = AND IF ." LX " THEN  S" user.t" _RB 8 _IN _V1 VFS-GETXATTR 0= SWAP 3 = AND IF ." GX " THEN  S" user.t" S" v" 0 _IN _V1 VFS-SETXATTR 0= IF ." SX " THEN  S" user.t" _IN _V1 VFS-REMOVEXATTR 0= IF ." RX " THEN  _SFS VFS-STATFS-SIZE _V1 VFS-STATFS 0= IF ." SF " THEN  _DISPATCH-CALLS @ 9 = IF ." NINE" THEN ;',
        'T-META-DISPATCH CR',
    ], "GA SA RL LX GX SX RX SF NINE")

# ── VFS-USE / VFS-CUR ──

def test_vfs_use_cur():
    """VFS-USE sets the context, VFS-CUR retrieves it."""
    check("VFS-USE / VFS-CUR", [
        'T-VFS-NEW  CONSTANT _V1',
        '_V1 VFS-USE',
        'VFS-CUR _V1 = IF ." OK" ELSE ." FAIL" THEN',
    ], "OK")

# ── VFS-MKFILE ──

def test_mkfile():
    """VFS-MKFILE creates a file in cwd, returns non-zero inode."""
    check("VFS-MKFILE returns non-zero", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" test.txt" _V1 VFS-MKFILE',
        'DUP 0<> IF ." OK" ELSE ." FAIL" THEN DROP',
    ], "OK")

def test_mkfile_type():
    """Created file has type VFS-T-FILE (1)."""
    check("MKFILE inode type = VFS-T-FILE", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" test.txt" _V1 VFS-MKFILE',
        'IN.TYPE @ . CR',
    ], "1")

def test_mkfile_name():
    """Created file has correct name."""
    check("MKFILE inode name", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" hello.dat" _V1 VFS-MKFILE',
        'IN.NAME @  DUP 16 + SWAP @ TYPE CR',
    ], "hello.dat")

def test_mkfile_initial_size():
    """New file starts at size 0."""
    check("MKFILE initial size = 0", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" empty.bin" _V1 VFS-MKFILE',
        'IN.SIZE-LO @ . CR',
    ], "0")

# ── VFS-MKDIR ──

def test_mkdir():
    """VFS-MKDIR creates a directory, returns ior=0."""
    check("VFS-MKDIR ior = 0", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" subdir" _V1 VFS-MKDIR',
        '. CR',
    ], "0")

def test_mkdir_child_is_dir():
    """Created directory has type VFS-T-DIR and is findable."""
    check("MKDIR creates child dir", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" docs" _V1 VFS-MKDIR',
        'S" docs" _V1 VFS-RESOLVE',
        'DUP 0<> IF IN.TYPE @ . ELSE ." -1" THEN CR',
    ], "2")

def test_reserved_and_nul_names_are_rejected():
    """Mutation names reject dot entries, separators, and embedded NUL bytes."""
    check("reserved and NUL names rejected", [
        'T-VFS-NEW CONSTANT _V1 CREATE _NUL-NAME 3 ALLOT',
        '97 _NUL-NAME C! 0 _NUL-NAME 1+ C! 98 _NUL-NAME 2 + C!',
        ': T-NAME-RULES',
        '  S" ." _V1 VFS-MKFILE? DUP VFS-IOR-REASON 1 = IF ." DOT " THEN SWAP 0= IF ." DOT-ZERO " THEN DROP',
        '  S" .." _V1 VFS-MKDIR VFS-IOR-REASON 1 = IF ." DOTDOT " THEN',
        '  S" a/b" _V1 VFS-MKFILE? DUP VFS-IOR-REASON 1 = IF ." SLASH " THEN SWAP 0= IF ." SLASH-ZERO " THEN DROP',
        '  _NUL-NAME 3 _V1 VFS-MKFILE? DUP VFS-IOR-REASON 1 = IF ." NUL " THEN SWAP 0= IF ." NUL-ZERO " THEN DROP',
        '  0 1 _V1 VFS-MKFILE? DUP VFS-IOR-REASON 1 = IF ." NULL " THEN SWAP 0= IF ." NULL-ZERO " THEN DROP',
        '  -2 4 _V1 VFS-MKFILE? DUP VFS-IOR-REASON 1 = IF ." WRAP " THEN SWAP 0= IF ." WRAP-ZERO " THEN DROP',
        '  S" .x" _V1 VFS-MKFILE? ?DUP IF THROW THEN DROP',
        '  S" x." _V1 VFS-MKFILE? ?DUP IF THROW THEN DROP',
        '  _V1 V.ICOUNT @ 3 = IF ." VALID-EDGES" THEN ;',
        'T-NAME-RULES CR',
    ], "DOT DOT-ZERO DOTDOT SLASH SLASH-ZERO NUL NUL-ZERO NULL NULL-ZERO WRAP WRAP-ZERO VALID-EDGES")

# ── VFS-OPEN / VFS-CLOSE ──

def test_open_close():
    """Open a file, get non-zero FD, close without error."""
    check("OPEN/CLOSE round-trip", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" fo.txt" _V1 VFS-MKFILE DROP',
        '_V1 VFS-USE',
        'S" fo.txt" VFS-OPEN  DUP 0<> IF ." OPEN-OK" THEN  VFS-CLOSE ." CLOSED" CR',
    ], "OPEN-OKCLOSED")

def test_open_nonexistent():
    """Opening a file that doesn't exist returns 0."""
    check("OPEN non-existent = 0", [
        'T-VFS-NEW  CONSTANT _V1',
        '_V1 VFS-USE',
        'S" nope.txt" VFS-OPEN',
        '. CR',
    ], "0")

# ── VFS-WRITE / VFS-READ round-trip ──

def test_write_read_roundtrip():
    """Write bytes then read them back."""
    check("WRITE/READ round-trip", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" data.bin" _V1 VFS-MKFILE DROP',
        '_V1 VFS-USE',
        # Write "Hello" (5 bytes)
        'S" data.bin" VFS-OPEN  CONSTANT _FD',
        'S" Hello" _FD VFS-WRITE DROP',
        # Rewind and read back
        '_FD VFS-REWIND',
        '_RB 5 _FD VFS-READ',         # actual bytes read
        '5 = IF',
        '  _RB 5 TYPE CR',            # should print "Hello"
        'ELSE ." READ-LEN-FAIL" CR THEN',
        '_FD VFS-CLOSE',
    ], "Hello")

def test_write_extends_size():
    """After writing N bytes, VFS-SIZE reports N."""
    # Diagnostic: print actual from write, cursor, inode size directly
    check_fn("WRITE extends size", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" sz.bin" _V1 VFS-MKFILE DROP  _V1 VFS-USE',
        'S" sz.bin" VFS-OPEN  CONSTANT _FD',
        'S" ABCDEFGHIJ" _FD VFS-WRITE',
        '." W=" . ." C=" _FD FD.CUR-LO @ . ." S=" _FD FD.INODE @ IN.SIZE-LO @ . CR',
        '_FD VFS-CLOSE',
    ], lambda out: "S=10" in out or "S=10 " in out.replace(" ", ""),
    desc="expected S=10 in output")

def test_checked_write_preserves_partial_progress():
    """WRITE? reports progress and error together and advances by progress."""
    check("checked write preserves partial progress", [
        ': T-PARTIAL-WRITE  2DROP 2DROP DROP  2 0 VFS-IOR-F-PARTIAL VFS-IOR-D-BINDING 9 VFS-IOR-MAKE ;',
        'T-BINDING-CLONE CONSTANT _BIND',
        "' T-PARTIAL-WRITE _BIND VB.OPS @ VFS-OP-WRITE CELLS + !",
        '_BIND 0 T-VFS-NEW-WITH CONSTANT _V1',
        'S" p.bin" _V1 VFS-MKFILE DROP _V1 VFS-USE',
        'S" p.bin" VFS-OPEN CONSTANT _FD',
        ': T-PWRITE  S" hello" _FD VFS-WRITE? DUP VFS-IOR-REASON 9 = IF ." IOR " THEN  DUP VFS-IOR-FLAGS VFS-IOR-F-PARTIAL AND IF ." PARTIAL " THEN  DROP 2 = IF ." ACTUAL " THEN  _FD VFS-TELL 2 = IF ." CURSOR " THEN  _FD VFS-SIZE 2 = IF ." SIZE" THEN ;',
        'T-PWRITE CR',
    ], "IOR PARTIAL ACTUAL CURSOR SIZE")

def test_checked_read_preserves_partial_progress():
    """READ? also advances the cursor when a backend reports partial error."""
    check("checked read preserves partial progress", [
        ': T-PARTIAL-READ  2DROP 2DROP DROP  3 0 VFS-IOR-F-PARTIAL VFS-IOR-D-BINDING 9 VFS-IOR-MAKE ;',
        'T-BINDING-CLONE CONSTANT _BIND',
        "' T-PARTIAL-READ _BIND VB.OPS @ VFS-OP-READ CELLS + !",
        '_BIND 0 T-VFS-NEW-WITH CONSTANT _V1',
        'S" p.bin" _V1 VFS-MKFILE DROP _V1 VFS-USE',
        'S" p.bin" VFS-OPEN CONSTANT _FD',
        ': T-PREAD  _RB 5 _FD VFS-READ? DUP VFS-IOR-REASON 9 = IF ." IOR " THEN  DUP VFS-IOR-FLAGS VFS-IOR-F-PARTIAL AND IF ." PARTIAL " THEN  DROP 3 = IF ." ACTUAL " THEN  _FD VFS-TELL 3 = IF ." CURSOR" THEN ;',
        'T-PREAD CR',
    ], "IOR PARTIAL ACTUAL CURSOR")

def test_source_write_wrapper_throws_after_progress():
    """The source wrapper throws the same ior after canonical progress."""
    check("source write wrapper throws after progress", [
        ': T-PARTIAL-WRITE  2DROP 2DROP DROP  2 0 VFS-IOR-F-PARTIAL VFS-IOR-D-BINDING 9 VFS-IOR-MAKE ;',
        'T-BINDING-CLONE CONSTANT _BIND',
        "' T-PARTIAL-WRITE _BIND VB.OPS @ VFS-OP-WRITE CELLS + !",
        '_BIND 0 T-VFS-NEW-WITH CONSTANT _V1',
        'S" p.bin" _V1 VFS-MKFILE DROP _V1 VFS-USE',
        'S" p.bin" VFS-OPEN CONSTANT _FD',
        ': T-WRAPPER  S" hello" _FD VFS-WRITE DROP ;',
        ": T-CATCH-WRAPPER  ['] T-WRAPPER CATCH VFS-IOR-REASON 9 = IF .\" THROW \" THEN  _FD VFS-TELL 2 = IF .\" CURSOR\" THEN ;",
        'T-CATCH-WRAPPER CR',
    ], "THROW CURSOR")

def test_fd_access_modes_and_append():
    """Checked I/O enforces access modes and append writes at current EOF."""
    check_fn("fd access modes and append", [
        'T-VFS-NEW CONSTANT _V1 S" mode.bin" _V1 VFS-MKFILE DROP',
        'S" mode.bin" VFS-FF-READ _V1 VFS-OPEN? ?DUP IF THROW THEN CONSTANT _RFD',
        'S" x" _RFD VFS-WRITE? VFS-IOR-REASON 16 = SWAP 0= AND IF ." NOWRITE " THEN _RFD VFS-CLOSE',
        'S" mode.bin" VFS-FF-WRITE _V1 VFS-OPEN? ?DUP IF THROW THEN CONSTANT _WFD',
        '_RB 1 _WFD VFS-READ? VFS-IOR-REASON 16 = SWAP 0= AND IF ." NOREAD " THEN S" A" _WFD VFS-WRITE DROP _WFD VFS-CLOSE',
        'S" mode.bin" VFS-FF-WRITE VFS-FF-APPEND OR _V1 VFS-OPEN? ?DUP IF THROW THEN CONSTANT _AFD',
        '0 _AFD VFS-SEEK S" B" _AFD VFS-WRITE DROP _AFD VFS-CLOSE',
        'S" mode.bin" VFS-FF-READ _V1 VFS-OPEN? ?DUP IF THROW THEN CONSTANT _CFD',
        '_RB 2 _CFD VFS-READ DROP _RB 2 TYPE CR',
    ], lambda out: all(marker in out for marker in ("NOWRITE", "NOREAD", "AB")),
    desc="expected both access errors and appended bytes")

# ── VFS-SEEK / VFS-TELL ──

def test_seek_tell():
    """SEEK moves cursor, TELL reports it."""
    check("SEEK/TELL", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" sk.bin" _V1 VFS-MKFILE DROP',
        '_V1 VFS-USE',
        'S" sk.bin" VFS-OPEN  CONSTANT _FD',
        'S" 0123456789" _FD VFS-WRITE DROP',
        '5 _FD VFS-SEEK',
        '_FD VFS-TELL . CR',
        '_FD VFS-CLOSE',
    ], "5")

def test_seek_read():
    """SEEK to middle, read from there."""
    check("SEEK then READ", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" sk2.bin" _V1 VFS-MKFILE DROP',
        '_V1 VFS-USE',
        'S" sk2.bin" VFS-OPEN  CONSTANT _FD',
        'S" ABCDE" _FD VFS-WRITE DROP',
        '2 _FD VFS-SEEK',
        '_RB 3 _FD VFS-READ DROP',
        '_RB 3 TYPE CR',
        '_FD VFS-CLOSE',
    ], "CDE")

def test_rewind():
    """REWIND sets cursor to 0."""
    check("REWIND", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" rw.bin" _V1 VFS-MKFILE DROP',
        '_V1 VFS-USE',
        'S" rw.bin" VFS-OPEN  CONSTANT _FD',
        'S" XY" _FD VFS-WRITE DROP',
        '_FD VFS-REWIND',
        '_FD VFS-TELL . CR',
        '_FD VFS-CLOSE',
    ], "0")

def test_invalid_offsets_never_reach_binding():
    """High-bit seek/cursor/truncate inputs fail without mutation or dispatch."""
    check("invalid offsets do not dispatch", [
        'VARIABLE _BAD-IO-CALLS',
        ': T-BAD-RW-CB  2DROP 2DROP DROP 1 _BAD-IO-CALLS +! 0 0 ;',
        ': T-BAD-TR-CB  2DROP 1 _BAD-IO-CALLS +! 0 ;',
        'T-BINDING-CLONE CONSTANT _BIND',
        "' T-BAD-RW-CB _BIND VB.OPS @ VFS-OP-READ CELLS + !",
        "' T-BAD-RW-CB _BIND VB.OPS @ VFS-OP-WRITE CELLS + !",
        "' T-BAD-TR-CB _BIND VB.OPS @ VFS-OP-TRUNCATE CELLS + !",
        '_BIND 0 T-VFS-NEW-WITH CONSTANT _V1 S" f" _V1 VFS-MKFILE DROP _V1 VFS-USE S" f" VFS-OPEN CONSTANT _FD',
        ': T-SEEK-THROW  -1 _FD VFS-SEEK ;',
        ': T-BAD-OFFSETS  -1 _FD VFS-SEEK? VFS-IOR-REASON 15 = IF ." SEEK? " THEN  _FD VFS-TELL 0= IF ." CURSOR0 " THEN  [\'] T-SEEK-THROW CATCH VFS-IOR-REASON 15 = IF ." THROW " THEN  -1 _FD FD.CUR-LO !  _RB 1 _FD VFS-READ? VFS-IOR-REASON 15 = SWAP 0= AND IF ." READ " THEN  S" x" _FD VFS-WRITE? VFS-IOR-REASON 15 = SWAP 0= AND IF ." WRITE " THEN  0x7FFFFFFFFFFFFFFF _FD FD.CUR-LO !  _RB 1 _FD VFS-READ? VFS-IOR-REASON 15 = SWAP 0= AND IF ." READ-CAP " THEN  S" x" _FD VFS-WRITE? VFS-IOR-REASON 15 = SWAP 0= AND IF ." WRITE-CAP " THEN  _FD VFS-TELL 0x7FFFFFFFFFFFFFFF = IF ." CEILING " THEN  0 _FD FD.CUR-LO !  VFS-FF-READ VFS-FF-WRITE OR VFS-FF-APPEND OR _FD FD.FLAGS !  -1 _FD FD.INODE @ IN.SIZE-LO !  S" x" _FD VFS-WRITE? VFS-IOR-REASON 15 = SWAP 0= AND IF ." APPEND " THEN  _FD VFS-TELL 0= IF ." APPEND-CURSOR " THEN  5 _FD FD.INODE @ IN.SIZE-LO !  -1 _FD VFS-TRUNCATE VFS-IOR-REASON 15 = IF ." TRUNC " THEN  _FD VFS-SIZE 5 = IF ." SIZE " THEN  _BAD-IO-CALLS @ 0= IF ." NO-CALL" THEN ;',
        'T-BAD-OFFSETS CR',
    ], "SEEK? CURSOR0 THROW READ WRITE READ-CAP WRITE-CAP CEILING APPEND APPEND-CURSOR TRUNC SIZE NO-CALL")

# ── VFS-RESOLVE ──

def test_resolve_root():
    """Resolve '/' returns root inode."""
    check("RESOLVE /", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" /" _V1 VFS-RESOLVE',
        '_V1 V.ROOT @ = IF ." OK" ELSE ." FAIL" THEN CR',
    ], "OK")

def test_resolve_absolute():
    """Resolve absolute path to a file."""
    check("RESOLVE absolute /sub/f.txt", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" sub" _V1 VFS-MKDIR DROP',
        'S" sub" _V1 VFS-CD DROP',
        'S" f.txt" _V1 VFS-MKFILE DROP',
        '  S" /" _V1 VFS-CD DROP',
        'S" /sub/f.txt" _V1 VFS-RESOLVE',
        'DUP 0<> IF IN.TYPE @ . ELSE ." 0" THEN CR',
    ], "1")

def test_resolve_dot():
    """Resolve '.' returns cwd."""
    check("RESOLVE .", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" ." _V1 VFS-RESOLVE',
        '_V1 V.CWD @ = IF ." OK" ELSE ." FAIL" THEN CR',
    ], "OK")

def test_resolve_dotdot():
    """Resolve '..' from subdirectory returns parent."""
    check("RESOLVE ..", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" child" _V1 VFS-MKDIR DROP',
        'S" child" _V1 VFS-CD DROP',
        'S" .." _V1 VFS-RESOLVE',
        '_V1 V.ROOT @ = IF ." OK" ELSE ." FAIL" THEN CR',
    ], "OK")

def test_resolve_nonexistent():
    """Resolve non-existent path returns 0."""
    check("RESOLVE non-existent", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" /no/such/path" _V1 VFS-RESOLVE',
        '. CR',
    ], "0")

def test_readdir_failure_does_not_publish_completion():
    """A failed readdir remains retryable; only success marks children loaded."""
    check("readdir failure does not publish completion", [
        'VARIABLE _RD-CALLS',
        ': T-READDIR  2DROP 1 _RD-CALLS +!  _RD-CALLS @ 1 = IF VFS-E-IO ELSE 0 THEN ;',
        'T-BINDING-CLONE CONSTANT _BIND',
        "' T-READDIR _BIND VB.OPS @ VFS-OP-READDIR CELLS + !",
        '_BIND 0 T-VFS-NEW-WITH CONSTANT _V1',
        ': T-RD-RETRY  S" ghost" _V1 VFS-RESOLVE? SWAP DROP VFS-IOR-REASON 9 = IF ." ERROR " THEN  _V1 V.ROOT @ IN.FLAGS @ VFS-IF-CHILDREN AND 0= IF ." UNPUBLISHED " THEN  S" ghost" _V1 VFS-RESOLVE? SWAP DROP VFS-IOR-REASON 2 = IF ." NOENT " THEN  _RD-CALLS @ 2 = IF ." RETRIED " THEN  _V1 V.ROOT @ IN.FLAGS @ VFS-IF-CHILDREN AND IF ." PUBLISHED" THEN ;',
        'T-RD-RETRY CR',
    ], "ERROR UNPUBLISHED NOENT RETRIED PUBLISHED")

def test_checked_resolve_preserves_errors_and_lifecycle():
    """Checked resolution distinguishes NOTDIR and refuses terminal VFS states."""
    check("checked resolve errors and lifecycle", [
        'T-VFS-NEW CONSTANT _V1 S" file" _V1 VFS-MKFILE DROP',
        'T-VFS-NEW CONSTANT _V2',
        ': T-RESOLVE-CHECKS',
        '  S" file/child" _V1 VFS-RESOLVE? DUP VFS-IOR-REASON 4 = IF ." NOTDIR " THEN SWAP 0= IF ." NO-INODE " THEN DROP',
        '  0 1 _V1 VFS-RESOLVE? DUP VFS-IOR-REASON 1 = IF ." NULL " THEN SWAP 0= IF ." NULL-ZERO " THEN DROP',
        '  0 -1 _V1 VFS-RESOLVE? DUP VFS-IOR-REASON 1 = IF ." NEGATIVE " THEN SWAP 0= IF ." NEG-ZERO " THEN DROP',
        '  -2 4 _V1 VFS-RESOLVE? DUP VFS-IOR-REASON 1 = IF ." WRAP " THEN SWAP 0= IF ." WRAP-ZERO " THEN DROP',
        '  0 0 _V1 VFS-RESOLVE? ?DUP IF THROW THEN _V1 V.CWD @ = IF ." EMPTY-CWD " THEN',
        '  0 _V1 VFS-UNMOUNT DROP',
        '  S" /" _V1 VFS-RESOLVE? DUP VFS-IOR-REASON 14 = IF ." UNMOUNTED " THEN SWAP 0= IF ." NO-ROOT " THEN DROP',
        '  VFS-L-STALE _V2 V.LIFECYCLE !',
        '  S" /" _V2 VFS-RESOLVE? DUP VFS-IOR-REASON 13 = IF ." STALE " THEN SWAP 0= IF ." NO-STALE-ROOT" THEN DROP ;',
        'T-RESOLVE-CHECKS CR',
    ], "NOTDIR NO-INODE NULL NULL-ZERO NEGATIVE NEG-ZERO WRAP WRAP-ZERO EMPTY-CWD UNMOUNTED NO-ROOT STALE NO-STALE-ROOT")

def test_lookup_backed_eviction_reloads_entry():
    """Automatic eviction can reconstruct a clean dentry through LOOKUP."""
    check("lookup-backed eviction reloads entry", [
        'VARIABLE _LOOKUP-CALLS VARIABLE _LOOKUP-A VARIABLE _LOOKUP-U',
        'VARIABLE _LOOKUP-P VARIABLE _LOOKUP-V',
        ': T-LOOKUP  _LOOKUP-V ! _LOOKUP-P ! _LOOKUP-U ! _LOOKUP-A !',
        '  1 _LOOKUP-CALLS +!',
        '  _LOOKUP-A @ _LOOKUP-U @ VFS-T-FILE 99 7 _LOOKUP-P @ _LOOKUP-V @ VFS-CACHE-DENTRY ;',
        'T-BINDING-CLONE CONSTANT _BIND',
        "' T-LOOKUP _BIND VB.OPS @ VFS-OP-LOOKUP CELLS + !",
        '_BIND VB.CAPS DUP @ VFS-CAP-LOOKUP OR SWAP !',
        '_BIND 0 T-VFS-NEW-WITH CONSTANT _V1',
        ': T-EVICT-RELOAD',
        '  S" disk" _V1 VFS-RESOLVE? ?DUP IF THROW THEN DUP IN.BID @ 99 = IF ." FIRST " THEN DROP',
        '  1 _V1 VFS-SET-HWM',
        '  S" disk" _V1 VFS-RESOLVE? ?DUP IF THROW THEN DUP IN.BID @ 99 = OVER D.VNODE @ VN.GEN @ 7 = AND IF ." RELOADED " THEN DROP',
        '  _LOOKUP-CALLS @ 2 = IF ." TWICE " THEN',
        '  _V1 V.ICOUNT @ 2 = _V1 V.VCOUNT @ 2 = AND IF ." BOUNDED" THEN ;',
        'T-EVICT-RELOAD CR',
    ], "FIRST RELOADED TWICE BOUNDED")

# ── VFS-CD ──

def test_cd():
    """CD into a subdirectory, cwd changes."""
    check("VFS-CD", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" mydir" _V1 VFS-MKDIR DROP',
        'S" mydir" _V1 VFS-CD . CR',   # should print 0 (ior)
    ], "0")

def test_cd_fail():
    """CD to non-existent directory returns -1."""
    check("VFS-CD fail", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" nope" _V1 VFS-CD',
        '. CR',
    ], "-1")

def test_checked_cd_preserves_error_class():
    """CD? distinguishes a missing path from a non-directory path."""
    check("checked CD preserves error class", [
        'T-VFS-NEW CONSTANT _V1 S" file" _V1 VFS-MKFILE DROP',
        ': T-CD-ERRORS  S" missing" _V1 VFS-CD? VFS-IOR-REASON 2 = IF ." NOENT " THEN  S" file" _V1 VFS-CD? VFS-IOR-REASON 4 = IF ." NOTDIR " THEN  _V1 V.CWD @ _V1 V.ROOT @ = IF ." UNCHANGED" THEN ;',
        'T-CD-ERRORS CR',
    ], "NOENT NOTDIR UNCHANGED")

# ── VFS-DIR ──

def test_dir_listing():
    """VFS-DIR shows created files and directories."""
    check("VFS-DIR lists entries", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" alpha.txt" _V1 VFS-MKFILE DROP',
        'S" beta" _V1 VFS-MKDIR DROP',
        '_V1 VFS-DIR',
    ], "alpha.txt")

def test_dir_shows_dirtype():
    """VFS-DIR marks directories with [DIR]."""
    check("VFS-DIR [DIR] marker", [
        'T-VFS-NEW CONSTANT _V1',
        'S" sub" _V1 VFS-MKDIR DROP',
        '_V1 VFS-DIR',
    ], "[DIR]")

# ── VFS-STAT ──

def test_stat_file():
    """VFS-STAT prints file metadata."""
    check("VFS-STAT file", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" info.txt" _V1 VFS-MKFILE DROP',
        'S" info.txt" _V1 VFS-STAT',
    ], "Type:  file")

def test_stat_dir():
    """VFS-STAT prints directory metadata."""
    check("VFS-STAT directory", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" ddd" _V1 VFS-MKDIR DROP',
        'S" ddd" _V1 VFS-STAT',
    ], "Type:  dir")

def test_stat_nonexistent():
    """VFS-STAT on non-existent path prints 'not found'."""
    check("VFS-STAT not found", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" nope" _V1 VFS-STAT',
    ], "not found")

# ── VFS-RM ──

def test_rm_file():
    """VFS-RM removes a file, ior=0."""
    check("VFS-RM file", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" gone.txt" _V1 VFS-MKFILE DROP',
        'S" gone.txt" _V1 VFS-RM',
        '. CR',
    ], "0")

def test_rm_then_resolve():
    """After VFS-RM, the file is no longer resolvable."""
    check("VFS-RM then RESOLVE = 0", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" del.txt" _V1 VFS-MKFILE DROP',
        'S" del.txt" _V1 VFS-RM DROP',
        'S" del.txt" _V1 VFS-RESOLVE',
        '. CR',
    ], "0")

def test_rm_nonempty_dir():
    """VFS-RM reports NOTEMPTY for a non-empty directory."""
    check("VFS-RM non-empty dir fails", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" parent" _V1 VFS-MKDIR DROP',
        'S" parent" _V1 VFS-CD DROP',
        'S" child.txt" _V1 VFS-MKFILE DROP',
        'S" /" _V1 VFS-CD DROP',
        'S" parent" _V1 VFS-RM',
        'VFS-IOR-REASON . CR',
    ], "6")

def test_rm_root_fails():
    """VFS-RM reports INVALID for the root."""
    check("VFS-RM root fails", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" /" _V1 VFS-RM',
        'VFS-IOR-REASON . CR',
    ], "1")

def test_rm_nonexistent():
    """VFS-RM reports NOENT for a missing path."""
    check("VFS-RM non-existent", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" ghost" _V1 VFS-RM',
        'VFS-IOR-REASON . CR',
    ], "2")

# ── Vnode / dentry semantics ──

def test_hard_link_shares_vnode_and_data():
    """Two dentries for a hard link share identity, metadata, and bytes."""
    check("hard link shares vnode and data", [
        'T-VFS-NEW CONSTANT _V1',
        'S" original" _V1 VFS-MKFILE CONSTANT _A',
        'S" alias" _A _V1 V.ROOT @ _V1 VFS-LINK ?DUP IF THROW THEN CONSTANT _B',
        '_V1 VFS-USE S" original" VFS-OPEN CONSTANT _FD',
        'S" shared" _FD VFS-WRITE DROP _FD VFS-CLOSE',
        ': T-LINK-META  _A D.VNODE @ _B D.VNODE @ = IF ." VNODE " THEN  _A D.VNODE @ VN.NLINK @ 2 = IF ." NLINK " THEN  _A IN.SIZE-LO @ _B IN.SIZE-LO @ = IF ." SIZE " THEN ;',
        'T-LINK-META S" alias" VFS-OPEN CONSTANT _AFD _RB 6 _AFD VFS-READ 6 = IF _RB 6 TYPE THEN CR',
    ], "VNODE NLINK SIZE shared")

def test_cached_hard_links_share_vnode_identity():
    """Reloaded aliases with one BID/generation share a vnode and evict cleanly."""
    check("cached hard links share vnode identity", [
        'T-VFS-NEW CONSTANT _V1',
        'S" first" VFS-T-FILE 55 9 _V1 V.ROOT @ _V1 VFS-CACHE-DENTRY ?DUP IF THROW THEN CONSTANT _A',
        '_A D.VNODE @ CONSTANT _VN 2 _VN VN.NLINK !',
        'S" second" VFS-T-FILE 55 9 _V1 V.ROOT @ _V1 VFS-CACHE-DENTRY ?DUP IF THROW THEN CONSTANT _B',
        ': T-CACHED-LINKS',
        '  _A D.VNODE @ _B D.VNODE @ = IF ." SHARED " THEN',
        '  _VN VN.DREFS @ 2 = _VN VN.NLINK @ 2 = AND IF ." REFS " THEN',
        '  _V1 V.ICOUNT @ 3 = _V1 V.VCOUNT @ 2 = AND IF ." COUNTS " THEN',
        '  S" first" VFS-T-DIR 55 9 _V1 V.ROOT @ _V1 VFS-CACHE-DENTRY DUP VFS-IOR-REASON 10 = IF ." TYPE-CHECK " THEN SWAP 0= IF ." TYPE-ZERO " THEN DROP',
        '  _A _V1 VFS-CACHE-DROP 0= IF ." DROP1 " THEN',
        '  _VN VN.DREFS @ 1 = _V1 V.VCOUNT @ 2 = AND IF ." RETAINED " THEN',
        '  _B _V1 VFS-CACHE-DROP 0= IF ." DROP2 " THEN',
        '  _V1 V.ICOUNT @ 1 = _V1 V.VCOUNT @ 1 = AND IF ." REAPED" THEN ;',
        'T-CACHED-LINKS CR',
    ], "SHARED REFS COUNTS TYPE-CHECK TYPE-ZERO DROP1 RETAINED DROP2 REAPED")

def test_unlink_one_hard_link_keeps_other_name():
    """Unlink removes one dentry without retiring the shared vnode."""
    check("unlink one hard link keeps other", [
        'T-VFS-NEW CONSTANT _V1',
        'S" original" _V1 VFS-MKFILE CONSTANT _A',
        'S" alias" _A _V1 V.ROOT @ _V1 VFS-LINK ?DUP IF THROW THEN CONSTANT _B',
        'S" original" _V1 VFS-RM DROP',
        ': T-LINK-UNLINK  S" original" _V1 VFS-RESOLVE 0= IF ." GONE " THEN  S" alias" _V1 VFS-RESOLVE _B = IF ." ALIAS " THEN  _B D.VNODE @ VN.NLINK @ 1 = IF ." NLINK" THEN ;',
        'T-LINK-UNLINK CR',
    ], "GONE ALIAS NLINK")

def test_rename_between_same_vnode_aliases_is_noop():
    """Renaming onto another hard link to the same vnode retains both names."""
    check("rename same-vnode aliases is no-op", [
        'T-VFS-NEW CONSTANT _V1',
        'S" first" _V1 VFS-MKFILE CONSTANT _A',
        'S" second" _A _V1 V.ROOT @ _V1 VFS-LINK ?DUP IF THROW THEN CONSTANT _B',
        'S" second" _A _V1 V.ROOT @ 0 _V1 VFS-RENAME-AT ?DUP IF THROW THEN',
        ': T-SAME-VNODE-RENAME  S" first" _V1 VFS-RESOLVE _A = IF ." FIRST " THEN  S" second" _V1 VFS-RESOLVE _B = IF ." SECOND " THEN  _A D.VNODE @ VN.NLINK @ 2 = IF ." NLINK " THEN  _V1 V.ICOUNT @ 3 = IF ." COUNT" THEN ;',
        'T-SAME-VNODE-RENAME CR',
    ], "FIRST SECOND NLINK COUNT")

def test_unlink_while_open_keeps_file_alive():
    """An open descriptor retains an unlinked dentry and vnode until close."""
    check("unlink while open keeps file alive", [
        'T-VFS-NEW CONSTANT _V1',
        'S" live" _V1 VFS-MKFILE DROP _V1 VFS-USE',
        'S" live" VFS-OPEN CONSTANT _FD S" bytes" _FD VFS-WRITE DROP _FD VFS-REWIND',
        'S" live" _V1 VFS-RM DROP',
        ': T-OPEN-UNLINK  S" live" _V1 VFS-RESOLVE 0= IF ." GONE " THEN  _V1 V.VCOUNT @ 2 = IF ." RETAINED " THEN  _RB 5 _FD VFS-READ 5 = IF _RB 5 TYPE SPACE THEN  _FD VFS-CLOSE  _V1 V.VCOUNT @ 1 = IF ." REAPED" THEN ;',
        'T-OPEN-UNLINK CR',
    ], "GONE RETAINED bytes REAPED")

def test_cross_directory_rename_is_atomic_in_cache():
    """Cross-directory rename publishes the same dentry at the new path."""
    check("cross-directory rename moves one dentry", [
        'T-VFS-NEW CONSTANT _V1',
        'S" dst" _V1 VFS-MKDIR DROP S" dst" _V1 VFS-RESOLVE CONSTANT _DST',
        'S" source" _V1 VFS-MKFILE CONSTANT _SRC',
        'S" moved" _SRC _DST VFS-RN-NOREPLACE _V1 VFS-RENAME-AT ?DUP IF THROW THEN',
        ': T-MOVED  S" source" _V1 VFS-RESOLVE 0= IF ." OLD-GONE " THEN  S" /dst/moved" _V1 VFS-RESOLVE _SRC = IF ." SAME-DENTRY " THEN  _SRC IN.PARENT @ _DST = IF ." PARENT" THEN ;',
        'T-MOVED CR',
    ], "OLD-GONE SAME-DENTRY PARENT")

def test_rename_replacement_keeps_open_victim_alive():
    """Replacement switches the namespace while an old destination FD survives."""
    check("rename replacement keeps open victim", [
        'T-VFS-NEW CONSTANT _V1 _V1 VFS-USE',
        'S" src" _V1 VFS-MKFILE CONSTANT _SRC S" dst" _V1 VFS-MKFILE CONSTANT _OLD',
        'S" src" VFS-OPEN CONSTANT _SFD S" new" _SFD VFS-WRITE DROP _SFD VFS-CLOSE',
        'S" dst" VFS-OPEN CONSTANT _OFD S" old" _OFD VFS-WRITE DROP _OFD VFS-REWIND',
        'S" dst" _SRC _V1 V.ROOT @ 0 _V1 VFS-RENAME-AT ?DUP IF THROW THEN',
        'S" dst" VFS-OPEN CONSTANT _NFD',
        ': T-REPLACE  S" src" _V1 VFS-RESOLVE 0= IF ." SRC-GONE " THEN  S" dst" _V1 VFS-RESOLVE _SRC = IF ." DST-SRC " THEN  _RB 3 _OFD VFS-READ DROP _RB 3 TYPE SPACE  _RB 3 _NFD VFS-READ DROP _RB 3 TYPE SPACE  _V1 V.VCOUNT @ 3 = IF ." RETAINED " THEN  _OFD VFS-CLOSE _V1 V.VCOUNT @ 2 = IF ." REAPED" THEN ;',
        'T-REPLACE CR',
    ], "SRC-GONE DST-SRC old new RETAINED REAPED")

def test_directory_rename_cycle_is_rejected():
    """A directory cannot be renamed beneath one of its descendants."""
    check("directory rename cycle rejected", [
        'T-VFS-NEW CONSTANT _V1',
        'S" a" _V1 VFS-MKDIR DROP S" a" _V1 VFS-RESOLVE CONSTANT _A',
        'S" a" _V1 VFS-CD DROP S" b" _V1 VFS-MKDIR DROP S" b" _V1 VFS-RESOLVE CONSTANT _B',
        'S" loop" _A _B VFS-RN-NOREPLACE _V1 VFS-RENAME-AT VFS-IOR-REASON . CR',
    ], "1")

# ── VFS-SYNC ──

def test_sync_clean():
    """VFS-SYNC on clean VFS returns ior=0."""
    check("VFS-SYNC clean ior=0", [
        'T-VFS-NEW  CONSTANT _V1',
        '_V1 VFS-SYNC . CR',
    ], "0")

def test_sync_after_write():
    """VFS-SYNC after writing returns ior=0 (ramdisk always succeeds)."""
    check("VFS-SYNC after write", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" w.bin" _V1 VFS-MKFILE DROP',
        '_V1 VFS-USE',
        'S" w.bin" VFS-OPEN  CONSTANT _FD',
        'S" data" _FD VFS-WRITE DROP',
        '_FD VFS-CLOSE',
        '_V1 VFS-SYNC . CR',
    ], "0")

def test_syncfs_is_binding_owned_once():
    """One syncfs callback owns ordering for the complete filesystem."""
    check("syncfs callback runs once", [
        'VARIABLE _SYNC-CALLS',
        ': T-SYNCFS  DROP 1 _SYNC-CALLS +! 0 ;',
        'T-BINDING-CLONE CONSTANT _BIND',
        "' T-SYNCFS _BIND VB.OPS @ VFS-OP-SYNCFS CELLS + !",
        '_BIND 0 T-VFS-NEW-WITH CONSTANT _V1 _V1 VFS-USE',
        'S" a" _V1 VFS-MKFILE CONSTANT _A S" b" _V1 VFS-MKFILE CONSTANT _B',
        'S" a" VFS-OPEN CONSTANT _AFD S" x" _AFD VFS-WRITE DROP _AFD VFS-CLOSE',
        'S" b" VFS-OPEN CONSTANT _BFD S" y" _BFD VFS-WRITE DROP _BFD VFS-CLOSE',
        ': T-SYNC-ONCE  _V1 VFS-SYNC 0= IF ." OK " THEN  _SYNC-CALLS @ 1 = IF ." ONCE " THEN  _A IN.FLAGS @ VFS-IF-DIRTY AND 0= _B IN.FLAGS @ VFS-IF-DIRTY AND 0= AND IF ." CLEAN" THEN ;',
        'T-SYNC-ONCE CR',
    ], "OK ONCE CLEAN")

def test_unmount_is_binding_owned_once():
    """A successful unmount callback runs once and the lifecycle is terminal."""
    check("unmount callback runs once", [
        'VARIABLE _UNMOUNT-CALLS',
        ': T-UNMOUNT  2DROP 1 _UNMOUNT-CALLS +! 0 ;',
        'T-BINDING-CLONE CONSTANT _BIND',
        "' T-UNMOUNT _BIND VB.OPS @ VFS-OP-UNMOUNT CELLS + !",
        '_BIND 0 T-VFS-NEW-WITH CONSTANT _V1',
        ': T-UNMOUNT-ONCE  0 _V1 VFS-UNMOUNT 0= IF ." FIRST " THEN  0 _V1 VFS-UNMOUNT 0= IF ." IDEMPOTENT " THEN  _UNMOUNT-CALLS @ 1 = IF ." ONCE " THEN  _V1 V.LIFECYCLE @ VFS-L-UNMOUNTED = IF ." STATE" THEN ;',
        'T-UNMOUNT-ONCE CR',
    ], "FIRST IDEMPOTENT ONCE STATE")

def test_unmount_rejects_open_descriptors():
    """Ordinary unmount is busy while FDs are open and succeeds after close."""
    check("unmount rejects open descriptors", [
        'T-VFS-NEW CONSTANT _V1 S" f" _V1 VFS-MKFILE DROP _V1 VFS-USE S" f" VFS-OPEN CONSTANT _FD',
        ': T-UNMOUNT-BUSY  0 _V1 VFS-UNMOUNT VFS-IOR-REASON 14 = IF ." BUSY " THEN  _V1 V.LIFECYCLE @ VFS-L-MOUNTED = IF ." MOUNTED " THEN  _FD VFS-CLOSE  0 _V1 VFS-UNMOUNT 0= IF ." DONE" THEN ;',
        'T-UNMOUNT-BUSY CR',
    ], "BUSY MOUNTED DONE")

def test_unmount_preserves_stale_latch():
    """An unmount callback's stale transition is never overwritten to mounted."""
    check("unmount preserves stale latch", [
        ': T-STALE-UNMOUNT  DUP VFS-L-STALE SWAP V.LIFECYCLE ! 2DROP VFS-E-STALE ;',
        'T-BINDING-CLONE CONSTANT _BIND',
        "' T-STALE-UNMOUNT _BIND VB.OPS @ VFS-OP-UNMOUNT CELLS + !",
        '_BIND 0 T-VFS-NEW-WITH CONSTANT _V1',
        ': T-STALE-LATCH  0 _V1 VFS-UNMOUNT VFS-IOR-REASON 13 = IF ." STALE-IOR " THEN  _V1 V.LIFECYCLE @ VFS-L-STALE = IF ." LATCHED " THEN  0 _V1 VFS-UNMOUNT VFS-IOR-REASON 13 = IF ." STAYS-STALE" THEN ;',
        'T-STALE-LATCH CR',
    ], "STALE-IOR LATCHED STAYS-STALE")

def test_unmount_latches_attachment_drift_before_callback():
    """Unmount never dispatches through a replaced or generation-drifted volume."""
    check("unmount latches attachment drift", [
        'CREATE _BD /BLOCK-DEVICE ALLOT CREATE _VOL /VOLUME ALLOT',
        '_BD BD-OPEN ?DUP IF THROW THEN _BD _VOL VOL-RAW ?DUP IF THROW THEN',
        'VARIABLE _UNMOUNT-CALLS : T-UNMOUNT  2DROP 1 _UNMOUNT-CALLS +! 0 ;',
        'T-BINDING-CLONE CONSTANT _BIND',
        '_BIND VB.FLAGS DUP @ VFS-BF-NEEDS-VOLUME OR SWAP !',
        "' T-UNMOUNT _BIND VB.OPS @ VFS-OP-UNMOUNT CELLS + !",
        '_BIND _VOL T-VFS-NEW-WITH CONSTANT _V1',
        '_VOL 40 + DUP @ 1+ SWAP !',
        ': T-DRIFT-UNMOUNT  0 _V1 VFS-UNMOUNT VFS-IOR-REASON 13 = IF ." STALE " THEN  _V1 V.LIFECYCLE @ VFS-L-STALE = IF ." LATCHED " THEN  _UNMOUNT-CALLS @ 0= IF ." NO-CALL" THEN ;',
        'T-DRIFT-UNMOUNT CR',
    ], "STALE LATCHED NO-CALL")

def test_post_unmount_checked_open_is_busy():
    """Checked operations do not use a filesystem after unmount."""
    check("post-unmount checked open is busy", [
        'T-VFS-NEW CONSTANT _V1 S" f" _V1 VFS-MKFILE DROP 0 _V1 VFS-UNMOUNT DROP',
        'S" f" VFS-FF-READ _V1 VFS-OPEN? SWAP 0= IF VFS-IOR-REASON . ELSE DROP ." BAD" THEN CR',
    ], "14")

# ── Read-only enforcement ──

def test_read_only_rejects_tree_mutations():
    """Read-only VFS rejects every tree mutation without changing the tree."""
    check("read-only rejects tree mutations", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" parent" _V1 VFS-MKDIR DROP',
        'S" keep.txt" _V1 VFS-MKFILE CONSTANT _KEEP',
        '_V1 V.ICOUNT @ CONSTANT _COUNT',
        'VFS-F-RO _V1 V.FLAGS DUP @ ROT OR SWAP !',
        ': T-RO-TREE-A  S" new.txt" _V1 VFS-MKFILE 0= IF ." MF " THEN  S" parent/new.txt" _V1 VFS-CREATE 0= IF ." CR " THEN  S" newdir" _V1 VFS-MKDIR VFS-IOR-REASON 7 = IF ." MD " THEN ;',
        ': T-RO-TREE-B  S" changed.txt" _KEEP _V1 VFS-RENAME VFS-IOR-REASON 7 = IF ." RN " THEN  S" keep.txt" _V1 VFS-RM VFS-IOR-REASON 7 = IF ." RM " THEN  _V1 V.ICOUNT @ _COUNT = IF ." COUNT " THEN ;',
        ': T-RO-TREE-C  S" keep.txt" _V1 VFS-RESOLVE _KEEP = IF ." KEEP " THEN  S" changed.txt" _V1 VFS-RESOLVE 0= IF ." NO-RENAME " THEN  S" new.txt" _V1 VFS-RESOLVE 0= IF ." NO-FILE " THEN ;',
        ': T-RO-TREE-D  S" parent/new.txt" _V1 VFS-RESOLVE 0= IF ." NO-CREATE " THEN  S" newdir" _V1 VFS-RESOLVE 0= IF ." NO-DIR" THEN ;',
        ': T-RO-TREE  T-RO-TREE-A T-RO-TREE-B T-RO-TREE-C T-RO-TREE-D ;',
        'T-RO-TREE CR',
    ], "MF CR MD RN RM COUNT KEEP NO-RENAME NO-FILE NO-CREATE NO-DIR")

def test_read_only_rejects_data_mutations():
    """Read-only writes/truncates leave file bytes, size, and cursor unchanged."""
    check("read-only preserves file data", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" keep.bin" _V1 VFS-MKFILE DROP',
        '_V1 VFS-USE',
        'S" keep.bin" VFS-OPEN CONSTANT _FD',
        'S" stable" _FD VFS-WRITE DROP',
        '_FD VFS-REWIND',
        'VFS-F-RO _V1 V.FLAGS DUP @ ROT OR SWAP !',
        ': T-RO-DATA  S" damage" _FD VFS-WRITE? VFS-IOR-REASON 7 = SWAP 0= AND IF ." WRITE " THEN  _FD VFS-TELL 0= IF ." CURSOR " THEN  2 _FD VFS-TRUNCATE VFS-IOR-REASON 7 = IF ." TRUNC " THEN  _FD VFS-SIZE 6 = IF ." SIZE " THEN  _RB 6 _FD VFS-READ 6 = IF _RB 6 TYPE THEN ;',
        'T-RO-DATA CR',
        '_FD VFS-CLOSE',
    ], "WRITE CURSOR TRUNC SIZE stable")

def test_read_only_allows_sync():
    """Read-only policy blocks mutation, not durability of prior dirty state."""
    check("read-only allows sync", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" dirty.bin" _V1 VFS-MKFILE CONSTANT _IN',
        '_V1 VFS-USE',
        'S" dirty.bin" VFS-OPEN CONSTANT _FD',
        'S" data" _FD VFS-WRITE DROP _FD VFS-CLOSE',
        'VFS-F-RO _V1 V.FLAGS DUP @ ROT OR SWAP !',
        ': T-RO-SYNC  _V1 VFS-SYNC 0= IF ." SYNC " THEN  _IN IN.FLAGS @ VFS-IF-DIRTY AND 0= IF ." CLEAN " THEN  S" dirty.bin" _V1 VFS-RESOLVE _IN = IF ." TREE" THEN ;',
        'T-RO-SYNC CR',
    ], "SYNC CLEAN TREE")

def test_read_only_legacy_open_is_readable():
    """Legacy VFS-OPEN requests read-only access on a read-only VFS."""
    check_fn("read-only legacy open remains readable", [
        'T-VFS-NEW CONSTANT _V1 _V1 VFS-USE',
        'S" readable" _V1 VFS-MKFILE DROP S" readable" VFS-OPEN CONSTANT _WFD',
        'S" ok" _WFD VFS-WRITE DROP _WFD VFS-CLOSE',
        'VFS-F-RO _V1 V.FLAGS DUP @ ROT OR SWAP !',
        'S" readable" VFS-FF-WRITE _V1 VFS-OPEN? VFS-IOR-REASON 7 = SWAP 0= AND IF ." WRITE-BLOCKED " THEN',
        'S" readable" VFS-OPEN CONSTANT _RFD',
        ': T-RO-LEGACY  _RFD 0<> IF ." OPEN " THEN  _RFD FD.FLAGS @ VFS-FF-READ = IF ." READ-ONLY " THEN  _RB 2 _RFD VFS-READ 2 = _RB C@ [CHAR] o = AND _RB 1+ C@ [CHAR] k = AND IF ." DATA" THEN ;',
        'T-RO-LEGACY CR',
    ], lambda out: all(marker in out for marker in
                       ("WRITE-BLOCKED", "OPEN", "READ-ONLY", "DATA")),
    desc="expected explicit write refusal and successful legacy read")

# ── VFS-SET-HWM ──

def test_set_hwm():
    """VFS-SET-HWM changes the eviction threshold."""
    check("VFS-SET-HWM", [
        'T-VFS-NEW  CONSTANT _V1',
        '512 _V1 VFS-SET-HWM',
        '_V1 V.IHWM @ . CR',
    ], "512")

# ── VFS-DESTROY ──

def test_destroy():
    """VFS-DESTROY completes and clears a current handle into its arena."""
    check("VFS-DESTROY", [
        'T-VFS-NEW  CONSTANT _V1',
        '_V1 VFS-USE',
        '_V1 VFS-DESTROY',
        'VFS-CUR 0= IF ." CLEARED " THEN ." OK" CR',
    ], "CLEARED OK")

def test_cross_vfs_dentries_are_rejected():
    """Namespace and metadata operations cannot pass a foreign dentry to a binding."""
    check("cross-VFS dentries rejected", [
        'T-VFS-NEW CONSTANT _V1 T-VFS-NEW CONSTANT _V2',
        'S" source" _V1 VFS-MKFILE CONSTANT _A',
        ': T-XDEV',
        '  _A D.OWNER @ _V1 = IF ." OWNER " THEN',
        '  S" foreign" _A _V2 V.ROOT @ _V2 VFS-LINK DUP VFS-IOR-REASON 19 = IF ." LINK " THEN SWAP 0= IF ." LINK-ZERO " THEN DROP',
        '  S" moved" _A _V2 V.ROOT @ 0 _V2 VFS-RENAME-AT VFS-IOR-REASON 19 = IF ." RENAME " THEN',
        '  _A _V2 VFS-GETATTR VFS-IOR-REASON 19 = IF ." GETATTR " THEN',
        '  _A _V2 VFS-CACHE-DROP VFS-IOR-REASON 19 = IF ." DROP " THEN',
        '  S" cached" VFS-T-FILE 88 1 _V1 V.ROOT @ _V2 VFS-CACHE-DENTRY DUP VFS-IOR-REASON 19 = IF ." CACHE " THEN SWAP 0= IF ." CACHE-ZERO" THEN DROP ;',
        'T-XDEV CR',
    ], "OWNER LINK LINK-ZERO RENAME GETATTR DROP CACHE CACHE-ZERO")

# ── Multiple VFS instances ──

def test_two_instances():
    """Two VFS instances coexist with separate roots."""
    # Use a colon definition to emit all markers on one line.
    check("two VFS instances", [
        'VARIABLE _V1  VARIABLE _V2',
        '131072 A-XMEM ARENA-NEW  IF -1 THROW THEN  VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN _V1 !',
        '131072 A-XMEM ARENA-NEW  IF -1 THROW THEN  VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN _V2 !',
        'S" a.txt" _V1 @ VFS-MKFILE DROP',
        'S" b.txt" _V2 @ VFS-MKFILE DROP',
        ': T-2V  S" a.txt" _V1 @ VFS-RESOLVE 0<> IF ." V1-A " THEN  S" a.txt" _V2 @ VFS-RESOLVE 0= IF ." V2-NO-A " THEN  S" b.txt" _V2 @ VFS-RESOLVE 0<> IF ." V2-B " THEN  S" b.txt" _V1 @ VFS-RESOLVE 0= IF ." V1-NO-B" THEN ;',
        'T-2V',
    ], "V1-A V2-NO-A V2-B V1-NO-B")

# ── Larger write/read ──

def test_large_write_read():
    """Write and read back 256 bytes."""
    check("256-byte write/read", [
        'T-VFS-NEW  CONSTANT _V1',
        '  S" big.bin" _V1 VFS-MKFILE DROP',
        '  _V1 VFS-USE',
        '  S" big.bin" VFS-OPEN  CONSTANT _FD',
        # Fill _TB with 256 bytes (all 0x41 = 'A')
        '  256 0 DO  65 _TB I + C!  LOOP',
        '  _TB 256 _FD VFS-WRITE DROP',
        '  _FD VFS-REWIND',
        '  _RB 256 _FD VFS-READ . CR',    # should print "256"
        '  _FD VFS-CLOSE',
    ], "256")

# ── Nested directory navigation ──

def test_nested_dirs():
    """Create nested directories and navigate."""
    check("nested dir creation & navigation", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" a" _V1 VFS-MKDIR DROP',
        'S" a" _V1 VFS-CD DROP',
        'S" b" _V1 VFS-MKDIR DROP',
        'S" b" _V1 VFS-CD DROP',
        'S" c" _V1 VFS-MKDIR DROP',
        'S" /a/b/c" _V1 VFS-RESOLVE',
        'DUP 0<> IF IN.TYPE @ . ELSE ." 0" THEN CR',
    ], "2")

# ── Inode count tracking ──

def test_inode_count():
    """Inode count increments on MKFILE/MKDIR."""
    check("inode count tracking", [
        'T-VFS-NEW  CONSTANT _V1  _V1 V.ICOUNT @ .  S" f1" _V1 VFS-MKFILE DROP  _V1 V.ICOUNT @ .  S" d1" _V1 VFS-MKDIR DROP  _V1 V.ICOUNT @ . CR',
    ], "1 2 3")

def test_inode_count_after_rm():
    """Inode count decrements on VFS-RM."""
    check("inode count after RM", [
        'T-VFS-NEW  CONSTANT _V1  S" tmp" _V1 VFS-MKFILE DROP  _V1 V.ICOUNT @ .  S" tmp" _V1 VFS-RM DROP  _V1 V.ICOUNT @ . CR',
    ], "2 1")

# ═══════════════════════════════════════════════════════════════════
#  Runner
# ═══════════════════════════════════════════════════════════════════

def main():
    build_snapshot()
    print()
    print("=" * 60)
    print("  VFS Test Suite")
    print("=" * 60)
    print()

    tests = [
        # VFS-NEW / descriptor
        test_vfs_new,
        test_root_inode_type,
        test_root_inode_name,
        test_cwd_equals_root,
        test_binding_descriptor_validation,
        test_binding_semantic_capability_validation,
        test_probe_capability_and_dispatch,
        test_structured_ior_round_trip,
        test_volume_required_rejects_null_attachment,
        test_volume_attachment_snapshot_and_stale_transition,
        test_volume_readonly_authority_propagates,
        test_lookup_capability_and_dispatch,
        test_unadvertised_operation_is_unsupported,
        test_absent_metadata_cap_does_not_invoke_xt,
        test_mount_error_keeps_instance_unmounted,
        test_constructor_nospace_rolls_back_arena,
        test_slab_growth_nospace_is_transactional,
        test_multi_slab_chain_is_traversed_by_sync,
        test_setattr_mask_publishes_zero_and_preserves_unselected,
        test_ext4_facing_dispatch_surface,
        # Context
        test_vfs_use_cur,
        # MKFILE
        test_mkfile,
        test_mkfile_type,
        test_mkfile_name,
        test_mkfile_initial_size,
        # MKDIR
        test_mkdir,
        test_mkdir_child_is_dir,
        test_reserved_and_nul_names_are_rejected,
        # OPEN / CLOSE
        test_open_close,
        test_open_nonexistent,
        # WRITE / READ
        test_write_read_roundtrip,
        test_write_extends_size,
        test_checked_write_preserves_partial_progress,
        test_checked_read_preserves_partial_progress,
        test_source_write_wrapper_throws_after_progress,
        test_fd_access_modes_and_append,
        # SEEK / TELL
        test_seek_tell,
        test_seek_read,
        test_rewind,
        test_invalid_offsets_never_reach_binding,
        # RESOLVE
        test_resolve_root,
        test_resolve_absolute,
        test_resolve_dot,
        test_resolve_dotdot,
        test_resolve_nonexistent,
        test_readdir_failure_does_not_publish_completion,
        test_checked_resolve_preserves_errors_and_lifecycle,
        test_lookup_backed_eviction_reloads_entry,
        # CD
        test_cd,
        test_cd_fail,
        test_checked_cd_preserves_error_class,
        # DIR
        test_dir_listing,
        test_dir_shows_dirtype,
        # STAT
        test_stat_file,
        test_stat_dir,
        test_stat_nonexistent,
        # RM
        test_rm_file,
        test_rm_then_resolve,
        test_rm_nonempty_dir,
        test_rm_root_fails,
        test_rm_nonexistent,
        # Vnode / dentry semantics
        test_hard_link_shares_vnode_and_data,
        test_cached_hard_links_share_vnode_identity,
        test_unlink_one_hard_link_keeps_other_name,
        test_rename_between_same_vnode_aliases_is_noop,
        test_unlink_while_open_keeps_file_alive,
        test_cross_directory_rename_is_atomic_in_cache,
        test_rename_replacement_keeps_open_victim_alive,
        test_directory_rename_cycle_is_rejected,
        # SYNC
        test_sync_clean,
        test_sync_after_write,
        test_syncfs_is_binding_owned_once,
        test_unmount_is_binding_owned_once,
        test_unmount_rejects_open_descriptors,
        test_unmount_preserves_stale_latch,
        test_unmount_latches_attachment_drift_before_callback,
        test_post_unmount_checked_open_is_busy,
        # Read-only enforcement
        test_read_only_rejects_tree_mutations,
        test_read_only_rejects_data_mutations,
        test_read_only_allows_sync,
        test_read_only_legacy_open_is_readable,
        # SET-HWM
        test_set_hwm,
        # DESTROY
        test_destroy,
        test_cross_vfs_dentries_are_rejected,
        # Multi-instance
        test_two_instances,
        # Larger I/O
        test_large_write_read,
        # Nested dirs
        test_nested_dirs,
        # Inode counting
        test_inode_count,
        test_inode_count_after_rm,
    ]

    for t in tests:
        t()

    print()
    total = _pass_count + _fail_count
    print(f"  {_pass_count}/{total} passed, {_fail_count} failed")
    if _fail_count:
        print("  *** FAILURES DETECTED ***")
        sys.exit(1)
    else:
        print("  All tests passed.")

if __name__ == "__main__":
    main()
