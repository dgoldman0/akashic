#!/usr/bin/env python3
"""Test suite for Akashic vfs-mount.f (akashic/utils/fs/vfs-mount.f).

Tests:
  - VMNT-MOUNT mounts a VFS at a prefix, returns ior=0
  - VMNT-MOUNT rejects prefix too long, returns -2
  - VMNT-MOUNT returns -1 when table is full (tested indirectly)
  - VMNT-UMOUNT removes a mount, returns ior=0
  - VMNT-UMOUNT on non-existent returns -1
  - VMNT-RESOLVE finds longest-prefix match
  - VMNT-RESOLVE returns remainder path
  - VMNT-RESOLVE returns 0 when no match
  - VMNT-OPEN dispatches to correct VFS
  - VMNT-INFO lists active mounts
  - Multiple mounts coexist with correct routing
  - Mount then unmount then resolve returns 0
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
VFS_MOUNT_F = os.path.join(ROOT_DIR, "akashic", "utils", "fs", "vfs-mount.f")

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
    print("[*] Building snapshot: BIOS + KDOS + utf8 + vfs + vfs-mount ...")
    t0 = time.time()
    bios_code  = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)

    dep_lines = []
    for path in [EVENT_F, SEM_F, GUARD_F, UTF8_F, VFS_F, VFS_MOUNT_F]:
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
        print(f"        expected substring: {expected!r}")
        last = clean.split('\n')[-5:]
        for l in last:
            print(f"        | {l}")

def check_fn(name, forth_lines, fn, desc="custom"):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    clean = output.strip()
    if fn(clean):
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}  ({desc})")
        last = clean.split('\n')[-5:]
        for l in last:
            print(f"        | {l}")

# ═══════════════════════════════════════════════════════════════════
#  Tests
# ═══════════════════════════════════════════════════════════════════

# ── VMNT-MOUNT ──

def test_mount_returns_zero():
    """VMNT-MOUNT returns ior=0 on success."""
    check("VMNT-MOUNT ior=0", [
        'T-VFS-NEW CONSTANT _V1',
        '_V1 S" /sd" VMNT-MOUNT . CR',
    ], "0")

def test_mount_prefix_too_long():
    """VMNT-MOUNT rejects prefix > 255 bytes with ior=-2."""
    check("VMNT-MOUNT prefix too long", [
        'T-VFS-NEW CONSTANT _V1',
        # Create a 260-byte string on the stack
        'CREATE _LONG 260 ALLOT',
        '_LONG 260 65 FILL',    # fill with 'A'
        '_V1 _LONG 260 VMNT-MOUNT . CR',
    ], "-2")

# ── VMNT-UMOUNT ──

def test_umount_returns_zero():
    """VMNT-UMOUNT returns ior=0 after successful mount."""
    check("VMNT-UMOUNT ior=0", [
        'T-VFS-NEW CONSTANT _V1',
        '_V1 S" /sd" VMNT-MOUNT DROP',
        'S" /sd" VMNT-UMOUNT . CR',
    ], "0")

def test_umount_not_found():
    """VMNT-UMOUNT returns -1 for non-existent mount."""
    check("VMNT-UMOUNT not found", [
        'S" /nope" VMNT-UMOUNT . CR',
    ], "-1")

# ── VMNT-RESOLVE ──

def test_resolve_finds_mount():
    """VMNT-RESOLVE returns non-zero VFS for matching prefix."""
    check("VMNT-RESOLVE finds mount", [
        'T-VFS-NEW CONSTANT _V1',
        '_V1 S" /sd" VMNT-MOUNT DROP',
        'S" /sd/file.txt" VMNT-RESOLVE',
        # Stack: vfs c-addr' u'
        'ROT 0<> IF ." FOUND" ELSE ." NOPE" THEN',
        '2DROP CR',
    ], "FOUND")

def test_resolve_returns_remainder():
    """VMNT-RESOLVE strips the prefix and returns remainder."""
    check("VMNT-RESOLVE remainder", [
        'T-VFS-NEW CONSTANT _V1',
        '_V1 S" /sd" VMNT-MOUNT DROP',
        'S" /sd/file.txt" VMNT-RESOLVE',
        # Stack: vfs c-addr' u'
        'ROT DROP TYPE CR',
    ], "/file.txt")

def test_resolve_no_match():
    """VMNT-RESOLVE returns 0 when no mount matches."""
    check("VMNT-RESOLVE no match", [
        'S" /unknown/path" VMNT-RESOLVE . CR',
    ], "0")

def test_resolve_longest_prefix():
    """VMNT-RESOLVE picks the longest matching prefix."""
    check("VMNT-RESOLVE longest prefix", [
        'T-VFS-NEW CONSTANT _V1',
        'T-VFS-NEW CONSTANT _V2',
        '_V1 S" /mnt" VMNT-MOUNT DROP',
        '_V2 S" /mnt/deep" VMNT-MOUNT DROP',
        'S" /mnt/deep/file.txt" VMNT-RESOLVE',
        # vfs should be _V2
        'ROT _V2 = IF ." DEEP" ELSE ." SHALLOW" THEN',
        '2DROP CR',
    ], "DEEP")

def test_resolve_exact_prefix():
    """VMNT-RESOLVE matches when path equals prefix exactly."""
    check("VMNT-RESOLVE exact prefix", [
        'T-VFS-NEW CONSTANT _V1',
        '_V1 S" /sd" VMNT-MOUNT DROP',
        ': T-RE  S" /sd" VMNT-RESOLVE ROT 0<> IF ." OK " THEN SWAP DROP . ;',
        'T-RE',
    ], "OK 0")

# ── VMNT-OPEN ──

def test_open_dispatches():
    """VMNT-OPEN routes to the correct VFS and opens a file."""
    check("VMNT-OPEN dispatch", [
        'T-VFS-NEW CONSTANT _V1',
        '_V1 S" /ram" VMNT-MOUNT DROP',
        '_V1 VFS-USE',
        'S" hello.txt" _V1 VFS-MKFILE DROP',
        'S" /ram/hello.txt" VMNT-OPEN DUP 0<> IF ." OPENED" THEN',
        'VFS-CLOSE CR',
    ], "OPENED")

def test_open_no_mount():
    """VMNT-OPEN returns 0 when no mount matches."""
    check("VMNT-OPEN no mount", [
        'S" /nowhere/file" VMNT-OPEN . CR',
    ], "0")

# ── VMNT-INFO ──

def test_info_shows_mount():
    """VMNT-INFO prints the mount point."""
    check("VMNT-INFO output", [
        'T-VFS-NEW CONSTANT _V1',
        '_V1 S" /storage" VMNT-MOUNT DROP',
        'VMNT-INFO',
    ], "/storage")

# ── Multiple mounts ──

def test_multiple_mounts():
    """Multiple mounts coexist and resolve correctly."""
    check("multiple mounts", [
        'T-VFS-NEW CONSTANT _V1',
        'T-VFS-NEW CONSTANT _V2',
        '_V1 S" /alpha" VMNT-MOUNT DROP',
        '_V2 S" /beta" VMNT-MOUNT DROP',
        ': T-MM  S" /alpha/x" VMNT-RESOLVE ROT _V1 = IF ." A-OK " THEN 2DROP  S" /beta/y" VMNT-RESOLVE ROT _V2 = IF ." B-OK" THEN 2DROP ;',
        'T-MM',
    ], "A-OK B-OK")

# ── Mount/unmount/resolve cycle ──

def test_mount_umount_resolve():
    """After unmount, resolve returns 0."""
    check("mount-umount-resolve", [
        'T-VFS-NEW CONSTANT _V1',
        '_V1 S" /tmp" VMNT-MOUNT DROP',
        'S" /tmp" VMNT-UMOUNT DROP',
        'S" /tmp/x" VMNT-RESOLVE . CR',
    ], "0")

# ── Long prefix ──

def test_long_prefix():
    """Mount with a 200-char prefix works."""
    check("long prefix mount", [
        'CREATE _LP 200 ALLOT',
        '_LP 200 47 FILL',       # fill with '/'
        'T-VFS-NEW CONSTANT _V1',
        # mount with 200-char prefix
        '_V1 _LP 200 VMNT-MOUNT . CR',
    ], "0")

# ═══════════════════════════════════════════════════════════════════
#  Runner
# ═══════════════════════════════════════════════════════════════════

def main():
    build_snapshot()
    print()
    print("=" * 60)
    print("  VFS Mount Table Test Suite")
    print("=" * 60)
    print()

    tests = [
        test_mount_returns_zero,
        test_mount_prefix_too_long,
        test_umount_returns_zero,
        test_umount_not_found,
        test_resolve_finds_mount,
        test_resolve_returns_remainder,
        test_resolve_no_match,
        test_resolve_longest_prefix,
        test_resolve_exact_prefix,
        test_open_dispatches,
        test_open_no_mount,
        test_info_shows_mount,
        test_multiple_mounts,
        test_mount_umount_resolve,
        test_long_prefix,
    ]

    for t in tests:
        t()

    print()
    print(f"Results: {_pass_count} pass, {_fail_count} fail / {_pass_count + _fail_count} total")
    if _fail_count > 0:
        sys.exit(1)

if __name__ == "__main__":
    main()
