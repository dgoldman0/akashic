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

# Dependency file paths (in topological load order)
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
SEM_F      = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")
GUARD_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "guard.f")
UTF8_F     = os.path.join(ROOT_DIR, "akashic", "text", "utf8.f")
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
    for path in [EVENT_F, SEM_F, GUARD_F, UTF8_F, VFS_F]:
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
        ': T-VFS-NEW  ( -- vfs )',
        '    524288 A-XMEM ARENA-NEW  IF -1 THROW THEN  _TARN !',
        '    _TARN @ VFS-RAM-VTABLE VFS-NEW ;',
    ]

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
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
    """VFS-RM refuses to delete a non-empty directory."""
    check("VFS-RM non-empty dir fails", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" parent" _V1 VFS-MKDIR DROP',
        'S" parent" _V1 VFS-CD DROP',
        'S" child.txt" _V1 VFS-MKFILE DROP',
        'S" /" _V1 VFS-CD DROP',
        'S" parent" _V1 VFS-RM',
        '. CR',
    ], "-1")

def test_rm_root_fails():
    """VFS-RM refuses to delete root."""
    check("VFS-RM root fails", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" /" _V1 VFS-RM',
        '. CR',
    ], "-1")

def test_rm_nonexistent():
    """VFS-RM on non-existent path returns -1."""
    check("VFS-RM non-existent", [
        'T-VFS-NEW  CONSTANT _V1',
        'S" ghost" _V1 VFS-RM',
        '. CR',
    ], "-1")

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
    """VFS-DESTROY completes without crash."""
    check("VFS-DESTROY", [
        'T-VFS-NEW  CONSTANT _V1',
        '_V1 VFS-DESTROY',
        '." OK" CR',
    ], "OK")

# ── Multiple VFS instances ──

def test_two_instances():
    """Two VFS instances coexist with separate roots."""
    # Use a colon definition to emit all markers on one line.
    check("two VFS instances", [
        'VARIABLE _V1  VARIABLE _V2',
        '131072 A-XMEM ARENA-NEW  IF -1 THROW THEN  VFS-RAM-VTABLE VFS-NEW _V1 !',
        '131072 A-XMEM ARENA-NEW  IF -1 THROW THEN  VFS-RAM-VTABLE VFS-NEW _V2 !',
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
        # OPEN / CLOSE
        test_open_close,
        test_open_nonexistent,
        # WRITE / READ
        test_write_read_roundtrip,
        test_write_extends_size,
        # SEEK / TELL
        test_seek_tell,
        test_seek_read,
        test_rewind,
        # RESOLVE
        test_resolve_root,
        test_resolve_absolute,
        test_resolve_dot,
        test_resolve_dotdot,
        test_resolve_nonexistent,
        # CD
        test_cd,
        test_cd_fail,
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
        # SYNC
        test_sync_clean,
        test_sync_after_write,
        # SET-HWM
        test_set_hwm,
        # DESTROY
        test_destroy,
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
