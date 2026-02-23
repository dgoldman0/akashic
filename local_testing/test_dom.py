#!/usr/bin/env python3
"""Test suite for akashic-dom Forth library.

Builds a MP64FS disk image with the real .f files in proper directory
structure, boots KDOS, uses REQUIRE to load from the filesystem,
then runs test expressions via UART.
"""
import os
import sys
import struct
import time
import tempfile
import re

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
CORE_F     = os.path.join(ROOT_DIR, "utils", "markup", "core.f")
HTML_F     = os.path.join(ROOT_DIR, "utils", "markup", "html.f")
CSS_F      = os.path.join(ROOT_DIR, "utils", "css", "css.f")
BRIDGE_F   = os.path.join(ROOT_DIR, "utils", "css", "bridge.f")
DOM_F      = os.path.join(ROOT_DIR, "utils", "dom", "dom.f")

sys.path.insert(0, EMU_DIR)

from asm import assemble
from system import MegapadSystem

BIOS_PATH  = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH  = os.path.join(EMU_DIR, "kdos.f")

SECTOR = 512

# ---------------------------------------------------------------------------
#  Disk image builder
# ---------------------------------------------------------------------------

def make_entry(name, start_sec, sec_count, used_bytes, ftype, parent):
    e = bytearray(48)
    name_b = name.encode('ascii')[:24]
    e[:len(name_b)] = name_b
    struct.pack_into('<HH', e, 24, start_sec, sec_count)
    struct.pack_into('<I', e, 28, used_bytes)
    e[32] = ftype
    e[34] = parent
    return bytes(e)

def build_disk_image(files):
    data_start = 14
    entries = []
    data_sectors = []
    next_sec = data_start

    for name, parent, ftype, content in files:
        if ftype == 8:
            entries.append(make_entry(name, 0, 0, 0, 8, parent))
        else:
            content_bytes = content if isinstance(content, bytes) else content.encode('utf-8')
            n_sec = max(1, (len(content_bytes) + SECTOR - 1) // SECTOR)
            entries.append(make_entry(name, next_sec, n_sec,
                                      len(content_bytes), 1, parent))
            padded = content_bytes + b'\x00' * (n_sec * SECTOR - len(content_bytes))
            data_sectors.append((next_sec, padded))
            next_sec += n_sec

    sb = bytearray(SECTOR)
    sb[0:4] = b'MP64'
    struct.pack_into('<H', sb, 4, 1)
    struct.pack_into('<I', sb, 6, 2048)
    struct.pack_into('<H', sb, 10, 1)
    struct.pack_into('<H', sb, 12, 1)
    struct.pack_into('<H', sb, 14, 2)
    struct.pack_into('<H', sb, 16, 12)
    struct.pack_into('<H', sb, 18, 14)
    sb[20] = 128
    sb[21] = 48

    bmap = bytearray(SECTOR)
    for s in range(data_start):
        bmap[s // 8] |= (1 << (s % 8))
    for sec_start, padded in data_sectors:
        n = len(padded) // SECTOR
        for s in range(sec_start, sec_start + n):
            bmap[s // 8] |= (1 << (s % 8))

    dir_data = bytearray(12 * SECTOR)
    for i, e in enumerate(entries):
        dir_data[i * 48 : i * 48 + 48] = e

    total_sectors = max(next_sec, 2048)
    image = bytearray(total_sectors * SECTOR)
    image[0:SECTOR] = sb
    image[SECTOR:2*SECTOR] = bmap
    image[2*SECTOR:14*SECTOR] = dir_data
    for sec_start, padded in data_sectors:
        off = sec_start * SECTOR
        image[off:off + len(padded)] = padded

    return bytes(image)

def read_file_bytes(path):
    with open(path, 'rb') as f:
        return f.read()

# ---------------------------------------------------------------------------
#  Emulator helpers
# ---------------------------------------------------------------------------

_snapshot = None
_img_path = None

def _load_bios():
    with open(BIOS_PATH) as f:
        return assemble(f.read())

def _load_kdos_lines(path):
    with open(path) as f:
        lines = []
        for line in f.read().splitlines():
            s = line.strip()
            if not s or s.startswith('\\'):
                continue
            if s.startswith('REQUIRE '):
                continue
            lines.append(line)
        return lines

def _next_line_chunk(data, pos):
    nl = data.find(b'\n', pos)
    if nl == -1:
        return data[pos:]
    return data[pos:nl + 1]

def capture_uart(sys_obj):
    buf = []
    sys_obj.uart.on_tx = lambda b: buf.append(b)
    return buf

def uart_text(buf):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9)) else ""
        for b in buf
    )

def save_cpu_state(cpu):
    return {
        'pc': cpu.pc,
        'regs': list(cpu.regs),
        'psel': cpu.psel, 'xsel': cpu.xsel, 'spsel': cpu.spsel,
        'flag_z': cpu.flag_z, 'flag_c': cpu.flag_c,
        'flag_n': cpu.flag_n, 'flag_v': cpu.flag_v,
        'flag_p': cpu.flag_p, 'flag_g': cpu.flag_g,
        'flag_i': cpu.flag_i, 'flag_s': cpu.flag_s,
        'd_reg': cpu.d_reg, 'q_out': cpu.q_out, 't_reg': cpu.t_reg,
        'ivt_base': cpu.ivt_base, 'ivec_id': cpu.ivec_id,
        'trap_addr': cpu.trap_addr,
        'halted': cpu.halted, 'idle': cpu.idle,
        'cycle_count': cpu.cycle_count,
        '_ext_modifier': cpu._ext_modifier,
    }

def restore_cpu_state(cpu, state):
    cpu.pc = state['pc']
    cpu.regs[:] = state['regs']
    for k in ('psel', 'xsel', 'spsel',
              'flag_z', 'flag_c', 'flag_n', 'flag_v',
              'flag_p', 'flag_g', 'flag_i', 'flag_s',
              'd_reg', 'q_out', 't_reg',
              'ivt_base', 'ivec_id', 'trap_addr',
              'halted', 'idle', 'cycle_count', '_ext_modifier'):
        setattr(cpu, k, state[k])


def _feed_and_run(sys_obj, buf, lines, max_steps):
    payload = "\n".join(lines) + "\n"
    data = payload.encode()
    pos = 0
    steps = 0
    while steps < max_steps:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk)
                pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)
    return steps


def build_snapshot():
    global _snapshot, _img_path
    if _snapshot is not None:
        return _snapshot

    print("[*] Building disk image ...")

    disk_files = [
        ("markup",   255, 8, b''),
        ("core.f",     0, 1, read_file_bytes(CORE_F)),
        ("html.f",     0, 1, read_file_bytes(HTML_F)),
        ("css",      255, 8, b''),
        ("css.f",      3, 1, read_file_bytes(CSS_F)),
        ("bridge.f",   3, 1, read_file_bytes(BRIDGE_F)),
        ("dom",      255, 8, b''),
        ("dom.f",      6, 1, read_file_bytes(DOM_F)),
    ]

    image = build_disk_image(disk_files)
    _img_path = os.path.join(tempfile.gettempdir(), 'test_dom.img')
    with open(_img_path, 'wb') as f:
        f.write(image)
    data_secs = sum(max(1, (len(c)+511)//512) for _,_,t,c in disk_files if t != 8)
    print(f"    {len(image)//1024}KB image, {data_secs} data sectors")

    print("[*] Booting KDOS ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_kdos_lines(KDOS_PATH)

    sys_obj = MegapadSystem(ram_size=1024 * 1024, storage_image=_img_path,
                            ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    steps = _feed_and_run(sys_obj, buf, kdos_lines, 400_000_000)
    elapsed = time.time() - t0
    print(f"    KDOS ready — {steps:,} steps, {elapsed:.1f}s")

    print("[*] REQUIRE dom.f from disk ...")
    buf.clear()
    t0 = time.time()

    load_lines = [
        'ENTER-USERLAND',
        'CD dom',
        'REQUIRE dom.f',
        'CD /',
        # Test helpers: build strings byte-by-byte
        'CREATE _TB 512 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        # Second buffer
        'CREATE _UB 512 ALLOT  VARIABLE _UL',
        ': UR  0 _UL ! ;',
        ': UC  ( c -- ) _UB _UL @ + C!  1 _UL +! ;',
        ': UA  ( -- addr u ) _UB _UL @ ;',
        # Output buffer
        'CREATE _OB 1024 ALLOT',
        # Third buffer for stylesheets
        'CREATE _VB 1024 ALLOT  VARIABLE _VL',
        ': VR  0 _VL ! ;',
        ': VC  ( c -- ) _VB _VL @ + C!  1 _VL +! ;',
        ': VA  ( -- addr u ) _VB _VL @ ;',
        # Style result buffer
        'CREATE _SB 2048 ALLOT',
        # Create test arena and document
        '524288 A-XMEM ARENA-NEW DROP CONSTANT _TARN',
        '_TARN 64 64 DOM-DOC-NEW CONSTANT _TDOC',
    ]

    steps = _feed_and_run(sys_obj, buf, load_lines, 800_000_000)
    load_text = uart_text(buf)
    elapsed = time.time() - t0
    print(f"    Loaded — {steps:,} steps, {elapsed:.1f}s")

    load_errs = [l for l in load_text.split('\n')
                 if 'not found' in l.lower() or 'error' in l.lower() or 'abort' in l.lower()]
    if load_errs:
        print("[!] Errors during load:")
        for e in load_errs[-10:]:
            print(f"    {e}")

    _snapshot = (bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print("[*] Snapshot ready.")
    return _snapshot


def run_forth(lines, max_steps=200_000_000):
    mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024 * 1024,
                            ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)

    lines_with_bye = lines + ['BYE']
    steps = _feed_and_run(sys_obj, buf, lines_with_bye, max_steps)
    return uart_text(buf)


def tstr(s):
    """Build string in test buffer _TB using TR/TC, return Forth lines."""
    parts = ['TR']
    for ch in s:
        parts.append(f'{ord(ch)} TC')
    full = " ".join(parts)
    lines = []
    while len(full) > 70:
        split_at = full.rfind(' ', 0, 70)
        if split_at == -1:
            split_at = 70
        lines.append(full[:split_at])
        full = full[split_at:].lstrip()
    if full:
        lines.append(full)
    return lines


def tstr2(s):
    """Build string in second test buffer _UB using UR/UC."""
    parts = ['UR']
    for ch in s:
        parts.append(f'{ord(ch)} UC')
    full = " ".join(parts)
    lines = []
    while len(full) > 70:
        split_at = full.rfind(' ', 0, 70)
        if split_at == -1:
            split_at = 70
        lines.append(full[:split_at])
        full = full[split_at:].lstrip()
    if full:
        lines.append(full)
    return lines


def vstr(s):
    """Build string in third test buffer _VB using VR/VC."""
    parts = ['VR']
    for ch in s:
        parts.append(f'{ord(ch)} VC')
    full = " ".join(parts)
    lines = []
    while len(full) > 70:
        split_at = full.rfind(' ', 0, 70)
        if split_at == -1:
            split_at = 70
        lines.append(full[:split_at])
        full = full[split_at:].lstrip()
    if full:
        lines.append(full)
    return lines


# ---------------------------------------------------------------------------
#  Test framework
# ---------------------------------------------------------------------------

LOG_PATH = '/tmp/dom_test.log'
_log_file = None
_pass_count = 0
_fail_count = 0

def log(msg):
    if _log_file:
        _log_file.write(msg + '\n')
        _log_file.flush()

def log_and_print(msg):
    print(msg)
    log(msg)

def check(name, forth_lines, expected=None, check_fn=None):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    clean = output.strip()

    log(f'\n--- {name} ---')
    log(f'FORTH INPUT:')
    for fl in forth_lines:
        log(f'  {fl}')
    log(f'RAW OUTPUT ({len(output)} chars):')
    log(output)
    log(f'CLEAN OUTPUT:')
    log(clean)

    if check_fn:
        ok = check_fn(clean)
    elif expected is not None:
        ok = expected in clean
    else:
        ok = True

    if ok:
        _pass_count += 1
        log_and_print(f"  PASS  {name}")
    else:
        _fail_count += 1
        log_and_print(f"  FAIL  {name}")
        if expected is not None:
            last_lines = clean.split('\n')[-3:]
            log_and_print(f"        expected: '{expected}'")
            log_and_print(f"        got (last 3): {last_lines}")
        elif check_fn:
            last_lines = clean.split('\n')[-3:]
            log_and_print(f"        check_fn failed")
            log_and_print(f"        got (last 3): {last_lines}")


def _run_diag(label, forth_lines):
    output = run_forth(forth_lines)
    log(f'\n--- DIAG: {label} ---')
    log(f'FORTH INPUT:')
    for fl in forth_lines:
        log(f'  {fl}')
    log(f'FULL OUTPUT:')
    log(output)
    return output


# ---------------------------------------------------------------------------
#  Stage 1 Tests — Document Creation & String Pool
# ---------------------------------------------------------------------------

def test_doc_creation():
    log_and_print("\n=== Document Creation ===")

    # 1. DOM-DOC returns current document (non-zero)
    check("DOM-DOC returns non-zero",
        [': t1 DOM-DOC CR ." [D=" . ." ]" ; t1'],
        check_fn=lambda out: '[D=' in out and '[D=0 ]' not in out)

    # 2. DOM-USE switches document
    check("DOM-USE + DOM-DOC round-trip",
        [': t2 DOM-DOC DOM-USE DOM-DOC CR ." [D=" . ." ]" ; t2'],
        check_fn=lambda out: '[D=' in out and '[D=0 ]' not in out)

    # 3. String free space is positive
    check("String pool has free space",
        [': t3 _DOM-STR-FREE? CR ." [F=" . ." ]" ; t3'],
        check_fn=lambda out: re.search(r'\[F=(\d+)', out) and
                             int(re.search(r'\[F=(\d+)', out).group(1)) > 0)

    # 4. Node pool base is non-zero
    check("Node pool base non-zero",
        [': t4 DOM-DOC D.NODE-BASE @ CR ." [NB=" . ." ]" ; t4'],
        check_fn=lambda out: '[NB=' in out and '[NB=0 ]' not in out)

    # 5. Attr pool base is non-zero
    check("Attr pool base non-zero",
        [': t5 DOM-DOC D.ATTR-BASE @ CR ." [AB=" . ." ]" ; t5'],
        check_fn=lambda out: '[AB=' in out and '[AB=0 ]' not in out)

    # 6. Node max = 64 (what we set)
    check("Node max = 64",
        [': t6 DOM-DOC D.NODE-MAX @ CR ." [NM=" . ." ]" ; t6'],
        '[NM=64 ]')

    # 7. Attr max = 64 (what we set)
    check("Attr max = 64",
        [': t7 DOM-DOC D.ATTR-MAX @ CR ." [AM=" . ." ]" ; t7'],
        '[AM=64 ]')


def test_string_pool():
    log_and_print("\n=== String Pool ===")

    # 1. Alloc + get a simple string "hello"
    check("Alloc+get 'hello'",
        tstr('hello') + [
            ': t1 TA _DOM-STR-ALLOC _DOM-STR-GET',
            '  CR ." [L=" DUP . ." ]"',
            '  CR ." [S=" TYPE ." ]" ; t1'],
        check_fn=lambda out: '[L=5 ]' in out and '[S=hello]' in out)

    # 2. Alloc + get a longer string
    check("Alloc+get longer string",
        tstr('the quick brown fox') + [
            ': t2 TA _DOM-STR-ALLOC _DOM-STR-GET',
            '  CR ." [L=" DUP . ." ]"',
            '  CR ." [S=" TYPE ." ]" ; t2'],
        check_fn=lambda out: '[L=19 ]' in out and '[S=the quick brown fox]' in out)

    # 3. Multiple allocs return different handles
    check("Multiple allocs different handles",
        tstr('abc') + [
            ': t3 TA _DOM-STR-ALLOC',
            '  TA _DOM-STR-ALLOC',
            '  CR ." [EQ=" OVER = . ." ]" DROP ; t3'],
        '[EQ=0 ]')

    # 4. Refcount starts at 1
    check("Refcount starts at 1",
        tstr('test') + [
            ': t4 TA _DOM-STR-ALLOC _DOM-STR-REFCOUNT',
            '  CR ." [RC=" . ." ]" ; t4'],
        '[RC=1 ]')

    # 5. STR-REF increments refcount
    check("STR-REF increments",
        tstr('test') + [
            ': t5 TA _DOM-STR-ALLOC DUP _DOM-STR-REF',
            '  _DOM-STR-REFCOUNT CR ." [RC=" . ." ]" ; t5'],
        '[RC=2 ]')

    # 6. STR-RELEASE decrements refcount
    check("STR-RELEASE decrements",
        tstr('test') + [
            ': t6 TA _DOM-STR-ALLOC',
            '  DUP _DOM-STR-REF',
            '  DUP _DOM-STR-RELEASE',
            '  _DOM-STR-REFCOUNT CR ." [RC=" . ." ]" ; t6'],
        '[RC=1 ]')

    # 7. Handle 0 get returns 0 0
    check("Handle 0 get returns 0 0",
        [': t7 0 _DOM-STR-GET CR ." [A=" . ." ][L=" . ." ]" ; t7'],
        check_fn=lambda out: '[A=0 ]' in out and '[L=0 ]' in out)

    # 8. Handle 0 ref is no-op (no crash)
    check("Handle 0 ref no-op",
        [': t8 0 _DOM-STR-REF CR ." [OK]" ; t8'],
        '[OK]')

    # 9. Handle 0 release is no-op (no crash)
    check("Handle 0 release no-op",
        [': t9 0 _DOM-STR-RELEASE CR ." [OK]" ; t9'],
        '[OK]')

    # 10. Zero-length string
    check("Zero-length string",
        [': t10 _TB 0 _DOM-STR-ALLOC _DOM-STR-GET',
         '  CR ." [L=" . ." ]" DROP ; t10'],
        '[L=0 ]')

    # 11. Free space decreases after alloc
    check("Free space decreases",
        tstr('hello') + [
            ': t11 _DOM-STR-FREE?',
            '  TA _DOM-STR-ALLOC DROP',
            '  _DOM-STR-FREE?',
            '  CR ." [LT=" > . ." ]" ; t11'],
        '[LT=-1 ]')

    # 12. Contents survive multiple allocs (first string intact after second)
    check("First string intact after second alloc",
        tstr('first') + [
            ': t12 TA _DOM-STR-ALLOC',
            '  TR 115 TC 101 TC 99 TC 111 TC 110 TC 100 TC',
            '  TA _DOM-STR-ALLOC DROP',
            '  _DOM-STR-GET CR ." [S=" TYPE ." ]" ; t12'],
        '[S=first]')

    # 13. String with special chars
    check("String with special chars",
        [': t13 TR 60 TC 100 TC 105 TC 118 TC 62 TC',
         '  TA _DOM-STR-ALLOC _DOM-STR-GET',
         '  CR ." [L=" DUP . ." ]" TYPE ; t13'],
        '[L=5 ]')


def test_multi_document():
    log_and_print("\n=== Multi-Document ===")

    # 1. Create second document, switch between them
    check("Second doc has independent string pool",
        tstr('doc1str') + [
            ': t1 TA _DOM-STR-ALLOC',
            '  131072 A-XMEM ARENA-NEW DROP 32 32 DOM-DOC-NEW DROP',
            '  TR 100 TC 111 TC 99 TC 50 TC',
            '  TA _DOM-STR-ALLOC _DOM-STR-GET',
            '  CR ." [S=" TYPE ." ]"',
            '  _TDOC DOM-USE',
            '  _DOM-STR-GET CR ." [S=" TYPE ." ]" ; t1'],
        check_fn=lambda out: '[S=doc2]' in out and '[S=doc1str]' in out)


# ---------------------------------------------------------------------------
#  Stage 2 Tests — Node Allocation & Tree Structure
# ---------------------------------------------------------------------------

def test_node_alloc():
    log_and_print("\n=== Node Allocation ===")

    # 1. Alloc element node returns non-zero
    check("Alloc element returns non-zero",
        [': t1 DOM-T-ELEMENT _DOM-ALLOC CR ." [N=" . ." ]" ; t1'],
        check_fn=lambda out: '[N=' in out and '[N=0 ]' not in out)

    # 2. Alloc element sets type = 1
    check("Alloc element type = 1",
        [': t2 DOM-T-ELEMENT _DOM-ALLOC DOM-TYPE@ CR ." [T=" . ." ]" ; t2'],
        '[T=1 ]')

    # 3. Alloc text node sets type = 2
    check("Alloc text type = 2",
        [': t3 DOM-T-TEXT _DOM-ALLOC DOM-TYPE@ CR ." [T=" . ." ]" ; t3'],
        '[T=2 ]')

    # 4. Alloc comment sets type = 3
    check("Alloc comment type = 3",
        [': t4 DOM-T-COMMENT _DOM-ALLOC DOM-TYPE@ CR ." [T=" . ." ]" ; t4'],
        '[T=3 ]')

    # 5. Two allocs give different addresses
    check("Two allocs different addresses",
        [': t5 DOM-T-ELEMENT _DOM-ALLOC DOM-T-ELEMENT _DOM-ALLOC',
         '  CR ." [EQ=" = . ." ]" ; t5'],
        '[EQ=0 ]')

    # 6. Freshly allocated node has zero parent
    check("Fresh node parent = 0",
        [': t6 DOM-T-ELEMENT _DOM-ALLOC DOM-PARENT',
         '  CR ." [P=" . ." ]" ; t6'],
        '[P=0 ]')

    # 7. Freshly allocated node has no children
    check("Fresh node first-child = 0",
        [': t7 DOM-T-ELEMENT _DOM-ALLOC DOM-FIRST-CHILD',
         '  CR ." [FC=" . ." ]" ; t7'],
        '[FC=0 ]')

    # 8. Freshly allocated node has no siblings
    check("Fresh node next-sib = 0",
        [': t8 DOM-T-ELEMENT _DOM-ALLOC DOM-NEXT',
         '  CR ." [NS=" . ." ]" ; t8'],
        '[NS=0 ]')

    # 9. Free + re-alloc reuses slot
    check("Free then re-alloc reuses slot",
        [': t9 DOM-T-ELEMENT _DOM-ALLOC DUP _DOM-FREE',
         '  DOM-T-TEXT _DOM-ALLOC',
         '  CR ." [EQ=" = . ." ]" ; t9'],
        '[EQ=-1 ]')

    # 10. Re-allocated node has correct new type
    check("Re-alloc node has new type",
        [': t10 DOM-T-ELEMENT _DOM-ALLOC DUP _DOM-FREE',
         '  DOM-T-TEXT _DOM-ALLOC DOM-TYPE@',
         '  CR ." [T=" . ." ]" ; t10'],
        '[T=2 ]')

    # 11. DOM-FLAGS@ starts at 0
    check("Flags start at 0",
        [': t11 DOM-T-ELEMENT _DOM-ALLOC DOM-FLAGS@',
         '  CR ." [F=" . ." ]" ; t11'],
        '[F=0 ]')

    # 12. DOM-FLAGS! sets flags
    check("Flags store/fetch",
        [': t12 DOM-T-ELEMENT _DOM-ALLOC',
         '  42 OVER DOM-FLAGS!  DOM-FLAGS@',
         '  CR ." [F=" . ." ]" ; t12'],
        '[F=42 ]')

    # 13. Node free-list head is non-zero (has free nodes)
    check("Free-list head non-zero",
        [': t13 DOM-DOC D.NODE-FREE @',
         '  CR ." [FL=" . ." ]" ; t13'],
        check_fn=lambda out: '[FL=' in out and '[FL=0 ]' not in out)

    # 14. Alloc 64 nodes exhausts pool (64 = max), next alloc should abort
    check("Pool exhaustion aborts",
        ['VARIABLE _DUMMY',
         ': t14 64 0 DO DOM-T-ELEMENT _DOM-ALLOC _DUMMY ! LOOP',
         '  DOM-DOC D.NODE-FREE @',
         '  CR ." [FL=" . ." ]" ; t14'],
        '[FL=0 ]')


def test_tree_append():
    log_and_print("\n=== Tree Structure — Append ===")

    # 1. Append one child: parent.first = parent.last = child
    check("Append 1 child: first=last=child",
        ['VARIABLE _P  VARIABLE _C',
         ': t1 DOM-T-ELEMENT _DOM-ALLOC _P !',
         '  DOM-T-ELEMENT _DOM-ALLOC _C !',
         '  _C @ _P @ DOM-APPEND',
         '  _P @ DOM-FIRST-CHILD _C @ =',
         '  _P @ DOM-LAST-CHILD  _C @ = AND',
         '  CR ." [OK=" . ." ]" ; t1'],
        '[OK=-1 ]')

    # 2. Child's parent is set
    check("Child parent set after append",
        ['VARIABLE _P  VARIABLE _C',
         ': t2 DOM-T-ELEMENT _DOM-ALLOC _P !',
         '  DOM-T-ELEMENT _DOM-ALLOC _C !',
         '  _C @ _P @ DOM-APPEND',
         '  _C @ DOM-PARENT _P @ =',
         '  CR ." [OK=" . ." ]" ; t2'],
        '[OK=-1 ]')

    # 3. Append two children: first!=last, correct order
    check("Append 2 children order",
        ['VARIABLE _P  VARIABLE _A  VARIABLE _B',
         ': t3 DOM-T-ELEMENT _DOM-ALLOC _P !',
         '  DOM-T-ELEMENT _DOM-ALLOC _A !',
         '  DOM-T-TEXT _DOM-ALLOC _B !',
         '  _A @ _P @ DOM-APPEND',
         '  _B @ _P @ DOM-APPEND',
         '  _P @ DOM-FIRST-CHILD _A @ =',
         '  _P @ DOM-LAST-CHILD  _B @ = AND',
         '  _A @ DOM-NEXT _B @ = AND',
         '  _B @ DOM-PREV _A @ = AND',
         '  CR ." [OK=" . ." ]" ; t3'],
        '[OK=-1 ]')

    # 4. Append three children, child-count = 3
    check("Append 3 children count=3",
        ['VARIABLE _P',
         ': t4 DOM-T-ELEMENT _DOM-ALLOC _P !',
         '  DOM-T-ELEMENT _DOM-ALLOC _P @ DOM-APPEND',
         '  DOM-T-ELEMENT _DOM-ALLOC _P @ DOM-APPEND',
         '  DOM-T-ELEMENT _DOM-ALLOC _P @ DOM-APPEND',
         '  _P @ DOM-CHILD-COUNT',
         '  CR ." [CC=" . ." ]" ; t4'],
        '[CC=3 ]')

    # 5. Empty parent has child-count = 0
    check("Empty parent count=0",
        [': t5 DOM-T-ELEMENT _DOM-ALLOC DOM-CHILD-COUNT',
         '  CR ." [CC=" . ." ]" ; t5'],
        '[CC=0 ]')

    # 6. First child has prev=0, last child has next=0
    check("First.prev=0 Last.next=0",
        ['VARIABLE _P  VARIABLE _A  VARIABLE _B',
         ': t6 DOM-T-ELEMENT _DOM-ALLOC _P !',
         '  DOM-T-ELEMENT _DOM-ALLOC _A !',
         '  DOM-T-ELEMENT _DOM-ALLOC _B !',
         '  _A @ _P @ DOM-APPEND',
         '  _B @ _P @ DOM-APPEND',
         '  _A @ DOM-PREV 0=',
         '  _B @ DOM-NEXT 0= AND',
         '  CR ." [OK=" . ." ]" ; t6'],
        '[OK=-1 ]')


def test_tree_prepend():
    log_and_print("\n=== Tree Structure — Prepend ===")

    # 1. Prepend to empty parent
    check("Prepend to empty parent",
        ['VARIABLE _P  VARIABLE _C',
         ': t1 DOM-T-ELEMENT _DOM-ALLOC _P !',
         '  DOM-T-ELEMENT _DOM-ALLOC _C !',
         '  _C @ _P @ DOM-PREPEND',
         '  _P @ DOM-FIRST-CHILD _C @ =',
         '  _P @ DOM-LAST-CHILD  _C @ = AND',
         '  CR ." [OK=" . ." ]" ; t1'],
        '[OK=-1 ]')

    # 2. Prepend before existing child
    check("Prepend before existing",
        ['VARIABLE _P  VARIABLE _A  VARIABLE _B',
         ': t2 DOM-T-ELEMENT _DOM-ALLOC _P !',
         '  DOM-T-ELEMENT _DOM-ALLOC _A !',
         '  DOM-T-ELEMENT _DOM-ALLOC _B !',
         '  _A @ _P @ DOM-APPEND',
         '  _B @ _P @ DOM-PREPEND',
         '  _P @ DOM-FIRST-CHILD _B @ =',
         '  _P @ DOM-LAST-CHILD  _A @ = AND',
         '  _B @ DOM-NEXT _A @ = AND',
         '  _A @ DOM-PREV _B @ = AND',
         '  CR ." [OK=" . ." ]" ; t2'],
        '[OK=-1 ]')

    # 3. Prepend sets parent
    check("Prepend sets parent",
        ['VARIABLE _P  VARIABLE _C',
         ': t3 DOM-T-ELEMENT _DOM-ALLOC _P !',
         '  DOM-T-ELEMENT _DOM-ALLOC _C !',
         '  _C @ _P @ DOM-PREPEND',
         '  _C @ DOM-PARENT _P @ =',
         '  CR ." [OK=" . ." ]" ; t3'],
        '[OK=-1 ]')


def test_tree_detach():
    log_and_print("\n=== Tree Structure — Detach ===")

    # 1. Detach only child → parent empty
    check("Detach only child",
        ['VARIABLE _P  VARIABLE _C',
         ': t1 DOM-T-ELEMENT _DOM-ALLOC _P !',
         '  DOM-T-ELEMENT _DOM-ALLOC _C !',
         '  _C @ _P @ DOM-APPEND',
         '  _C @ DOM-DETACH',
         '  _P @ DOM-FIRST-CHILD 0=',
         '  _P @ DOM-LAST-CHILD 0= AND',
         '  _P @ DOM-CHILD-COUNT 0= AND',
         '  _C @ DOM-PARENT 0= AND',
         '  CR ." [OK=" . ." ]" ; t1'],
        '[OK=-1 ]')

    # 2. Detach first of two
    check("Detach first of two",
        ['VARIABLE _P  VARIABLE _A  VARIABLE _B',
         ': t2 DOM-T-ELEMENT _DOM-ALLOC _P !',
         '  DOM-T-ELEMENT _DOM-ALLOC _A !',
         '  DOM-T-ELEMENT _DOM-ALLOC _B !',
         '  _A @ _P @ DOM-APPEND',
         '  _B @ _P @ DOM-APPEND',
         '  _A @ DOM-DETACH',
         '  _P @ DOM-FIRST-CHILD _B @ =',
         '  _P @ DOM-LAST-CHILD  _B @ = AND',
         '  _B @ DOM-PREV 0= AND',
         '  _P @ DOM-CHILD-COUNT 1 = AND',
         '  CR ." [OK=" . ." ]" ; t2'],
        '[OK=-1 ]')

    # 3. Detach last of two
    check("Detach last of two",
        ['VARIABLE _P  VARIABLE _A  VARIABLE _B',
         ': t3 DOM-T-ELEMENT _DOM-ALLOC _P !',
         '  DOM-T-ELEMENT _DOM-ALLOC _A !',
         '  DOM-T-ELEMENT _DOM-ALLOC _B !',
         '  _A @ _P @ DOM-APPEND',
         '  _B @ _P @ DOM-APPEND',
         '  _B @ DOM-DETACH',
         '  _P @ DOM-FIRST-CHILD _A @ =',
         '  _P @ DOM-LAST-CHILD  _A @ = AND',
         '  _A @ DOM-NEXT 0= AND',
         '  _P @ DOM-CHILD-COUNT 1 = AND',
         '  CR ." [OK=" . ." ]" ; t3'],
        '[OK=-1 ]')

    # 4. Detach middle of three
    check("Detach middle of three",
        ['VARIABLE _P  VARIABLE _A  VARIABLE _B  VARIABLE _C',
         ': t4 DOM-T-ELEMENT _DOM-ALLOC _P !',
         '  DOM-T-ELEMENT _DOM-ALLOC _A !',
         '  DOM-T-ELEMENT _DOM-ALLOC _B !',
         '  DOM-T-ELEMENT _DOM-ALLOC _C !',
         '  _A @ _P @ DOM-APPEND',
         '  _B @ _P @ DOM-APPEND',
         '  _C @ _P @ DOM-APPEND',
         '  _B @ DOM-DETACH',
         '  _P @ DOM-FIRST-CHILD _A @ =',
         '  _P @ DOM-LAST-CHILD  _C @ = AND',
         '  _A @ DOM-NEXT _C @ = AND',
         '  _C @ DOM-PREV _A @ = AND',
         '  _P @ DOM-CHILD-COUNT 2 = AND',
         '  _B @ DOM-PARENT 0= AND',
         '  CR ." [OK=" . ." ]" ; t4'],
        '[OK=-1 ]')

    # 5. Detach node with no parent is no-op
    check("Detach orphan is no-op",
        [': t5 DOM-T-ELEMENT _DOM-ALLOC DOM-DETACH',
         '  CR ." [OK]" ; t5'],
        '[OK]')

    # 6. Detached node can be re-appended
    check("Re-append after detach",
        ['VARIABLE _P  VARIABLE _A  VARIABLE _B',
         ': t6 DOM-T-ELEMENT _DOM-ALLOC _P !',
         '  DOM-T-ELEMENT _DOM-ALLOC _A !',
         '  DOM-T-ELEMENT _DOM-ALLOC _B !',
         '  _A @ _P @ DOM-APPEND',
         '  _B @ _P @ DOM-APPEND',
         '  _A @ DOM-DETACH',
         '  _A @ _P @ DOM-APPEND',
         '  _P @ DOM-FIRST-CHILD _B @ =',
         '  _P @ DOM-LAST-CHILD  _A @ = AND',
         '  _P @ DOM-CHILD-COUNT 2 = AND',
         '  CR ." [OK=" . ." ]" ; t6'],
        '[OK=-1 ]')


def test_tree_insert_before():
    log_and_print("\n=== Tree Structure — Insert Before ===")

    # 1. Insert before first child (becomes new first)
    check("Insert before first",
        ['VARIABLE _P  VARIABLE _A  VARIABLE _B',
         ': t1 DOM-T-ELEMENT _DOM-ALLOC _P !',
         '  DOM-T-ELEMENT _DOM-ALLOC _A !',
         '  DOM-T-ELEMENT _DOM-ALLOC _B !',
         '  _A @ _P @ DOM-APPEND',
         '  _B @ _A @ DOM-INSERT-BEFORE',
         '  _P @ DOM-FIRST-CHILD _B @ =',
         '  _B @ DOM-NEXT _A @ = AND',
         '  _A @ DOM-PREV _B @ = AND',
         '  _B @ DOM-PARENT _P @ = AND',
         '  CR ." [OK=" . ." ]" ; t1'],
        '[OK=-1 ]')

    # 2. Insert before last child (becomes middle)
    check("Insert before last (middle)",
        ['VARIABLE _P  VARIABLE _A  VARIABLE _B  VARIABLE _C',
         ': t2 DOM-T-ELEMENT _DOM-ALLOC _P !',
         '  DOM-T-ELEMENT _DOM-ALLOC _A !',
         '  DOM-T-ELEMENT _DOM-ALLOC _B !',
         '  DOM-T-ELEMENT _DOM-ALLOC _C !',
         '  _A @ _P @ DOM-APPEND',
         '  _B @ _P @ DOM-APPEND',
         '  _C @ _B @ DOM-INSERT-BEFORE',
         '  _P @ DOM-FIRST-CHILD _A @ =',
         '  _A @ DOM-NEXT _C @ = AND',
         '  _C @ DOM-NEXT _B @ = AND',
         '  _B @ DOM-PREV _C @ = AND',
         '  _C @ DOM-PREV _A @ = AND',
         '  _P @ DOM-CHILD-COUNT 3 = AND',
         '  CR ." [OK=" . ." ]" ; t2'],
        '[OK=-1 ]')


def test_tree_traversal():
    log_and_print("\n=== Tree Structure — Traversal ===")

    # 1. Walk children via DOM-NEXT
    check("Walk children via next",
        ['VARIABLE _P  VARIABLE _A  VARIABLE _B  VARIABLE _C',
         ': t1 DOM-T-ELEMENT _DOM-ALLOC _P !',
         '  DOM-T-ELEMENT _DOM-ALLOC _A !',
         '  DOM-T-TEXT _DOM-ALLOC _B !',
         '  DOM-T-COMMENT _DOM-ALLOC _C !',
         '  _A @ _P @ DOM-APPEND',
         '  _B @ _P @ DOM-APPEND',
         '  _C @ _P @ DOM-APPEND',
         '  _P @ DOM-FIRST-CHILD DOM-TYPE@',
         '  CR ." [T1=" . ." ]"',
         '  _P @ DOM-FIRST-CHILD DOM-NEXT DOM-TYPE@',
         '  CR ." [T2=" . ." ]"',
         '  _P @ DOM-LAST-CHILD DOM-TYPE@',
         '  CR ." [T3=" . ." ]" ; t1'],
        check_fn=lambda out: '[T1=1 ]' in out and '[T2=2 ]' in out and '[T3=3 ]' in out)

    # 2. Walk children via DOM-PREV (reverse)
    check("Walk children via prev",
        ['VARIABLE _P  VARIABLE _A  VARIABLE _B  VARIABLE _C',
         ': t2 DOM-T-ELEMENT _DOM-ALLOC _P !',
         '  DOM-T-ELEMENT _DOM-ALLOC _A !',
         '  DOM-T-TEXT _DOM-ALLOC _B !',
         '  DOM-T-COMMENT _DOM-ALLOC _C !',
         '  _A @ _P @ DOM-APPEND',
         '  _B @ _P @ DOM-APPEND',
         '  _C @ _P @ DOM-APPEND',
         '  _P @ DOM-LAST-CHILD DOM-TYPE@',
         '  CR ." [T3=" . ." ]"',
         '  _P @ DOM-LAST-CHILD DOM-PREV DOM-TYPE@',
         '  CR ." [T2=" . ." ]"',
         '  _P @ DOM-FIRST-CHILD DOM-TYPE@',
         '  CR ." [T1=" . ." ]" ; t2'],
        check_fn=lambda out: '[T1=1 ]' in out and '[T2=2 ]' in out and '[T3=3 ]' in out)

    # 3. Deep nesting: grandchild
    check("Deep nesting grandchild",
        ['VARIABLE _GP  VARIABLE _P  VARIABLE _C',
         ': t3 DOM-T-ELEMENT _DOM-ALLOC _GP !',
         '  DOM-T-ELEMENT _DOM-ALLOC _P !',
         '  DOM-T-TEXT _DOM-ALLOC _C !',
         '  _P @ _GP @ DOM-APPEND',
         '  _C @ _P @ DOM-APPEND',
         '  _GP @ DOM-FIRST-CHILD DOM-FIRST-CHILD _C @ =',
         '  _C @ DOM-PARENT _P @ = AND',
         '  _C @ DOM-PARENT DOM-PARENT _GP @ = AND',
         '  CR ." [OK=" . ." ]" ; t3'],
        '[OK=-1 ]')


# ---------------------------------------------------------------------------
#  Stage 3 Tests — Attribute Storage
# ---------------------------------------------------------------------------

def test_attr_basic():
    log_and_print("\n=== Attribute — Basic ===")

    # 1. Set attr and get it back
    check("Set and get attr",
        tstr('id') + tstr2('main') + [
            'VARIABLE _N',
            ': t1 DOM-T-ELEMENT _DOM-ALLOC _N !',
            '  _N @ TA UA DOM-ATTR!',
            '  _N @ TA DOM-ATTR@',
            '  CR ." [F=" . ." ]"',
            '  CR ." [V=" TYPE ." ]" ; t1'],
        check_fn=lambda out: '[F=-1 ]' in out and '[V=main]' in out)

    # 2. Get non-existent attr returns 0 0 0
    check("Get missing attr",
        tstr('href') + [
            ': t2 DOM-T-ELEMENT _DOM-ALLOC TA DOM-ATTR@',
            '  CR ." [F=" . ." ][A=" . ." ][L=" . ." ]" ; t2'],
        '[F=0 ][A=0 ][L=0 ]')

    # 3. DOM-ATTR-HAS? true
    check("ATTR-HAS? true",
        tstr('id') + tstr2('x') + [
            'VARIABLE _N',
            ': t3 DOM-T-ELEMENT _DOM-ALLOC _N !',
            '  _N @ TA UA DOM-ATTR!',
            '  _N @ TA DOM-ATTR-HAS?',
            '  CR ." [H=" . ." ]" ; t3'],
        '[H=-1 ]')

    # 4. DOM-ATTR-HAS? false
    check("ATTR-HAS? false",
        tstr('href') + [
            ': t4 DOM-T-ELEMENT _DOM-ALLOC TA DOM-ATTR-HAS?',
            '  CR ." [H=" . ." ]" ; t4'],
        '[H=0 ]')

    # 5. DOM-ATTR-COUNT on empty node
    check("Attr count = 0",
        [': t5 DOM-T-ELEMENT _DOM-ALLOC DOM-ATTR-COUNT',
         '  CR ." [AC=" . ." ]" ; t5'],
        '[AC=0 ]')

    # 6. Set one attr, count = 1
    check("Attr count = 1",
        tstr('id') + tstr2('x') + [
            'VARIABLE _N',
            ': t6 DOM-T-ELEMENT _DOM-ALLOC _N !',
            '  _N @ TA UA DOM-ATTR!',
            '  _N @ DOM-ATTR-COUNT',
            '  CR ." [AC=" . ." ]" ; t6'],
        '[AC=1 ]')

    # 7. Set two attrs, count = 2
    check("Attr count = 2",
        tstr('id') + tstr2('x') + [
            'VARIABLE _N',
            ': t7 DOM-T-ELEMENT _DOM-ALLOC _N !',
            '  _N @ TA UA DOM-ATTR!',
            '  TR 99 TC 108 TC 97 TC 115 TC 115 TC',
            '  UR 102 TC 111 TC 111 TC',
            '  _N @ TA UA DOM-ATTR!',
            '  _N @ DOM-ATTR-COUNT',
            '  CR ." [AC=" . ." ]" ; t7'],
        check_fn=lambda out: '[AC=2 ]' in out)

    # 8. Update existing attr
    check("Update existing attr",
        tstr('id') + tstr2('old') + [
            'VARIABLE _N',
            ': t8 DOM-T-ELEMENT _DOM-ALLOC _N !',
            '  _N @ TA UA DOM-ATTR!',
            '  UR 110 UC 101 UC 119 UC',
            '  _N @ TA UA DOM-ATTR!',
            '  _N @ TA DOM-ATTR@',
            '  CR ." [F=" . ." ]"',
            '  CR ." [V=" TYPE ." ]"',
            '  _N @ DOM-ATTR-COUNT',
            '  CR ." [AC=" . ." ]" ; t8'],
        check_fn=lambda out: '[F=-1 ]' in out and '[V=new]' in out and '[AC=1 ]' in out)


def test_attr_case():
    log_and_print("\n=== Attribute — Case Insensitive ===")

    # 1. Case-insensitive get
    check("Case-insensitive get",
        tstr('ID') + tstr2('main') + [
            'VARIABLE _N',
            ': t1 DOM-T-ELEMENT _DOM-ALLOC _N !',
            '  _N @ TA UA DOM-ATTR!',
            '  TR 105 TC 100 TC',
            '  _N @ TA DOM-ATTR@',
            '  CR ." [F=" . ." ]"',
            '  CR ." [V=" TYPE ." ]" ; t1'],
        check_fn=lambda out: '[F=-1 ]' in out and '[V=main]' in out)

    # 2. Case-insensitive has
    check("Case-insensitive has",
        tstr('Class') + tstr2('box') + [
            'VARIABLE _N',
            ': t2 DOM-T-ELEMENT _DOM-ALLOC _N !',
            '  _N @ TA UA DOM-ATTR!',
            '  TR 99 TC 108 TC 97 TC 115 TC 115 TC',
            '  _N @ TA DOM-ATTR-HAS?',
            '  CR ." [H=" . ." ]" ; t2'],
        '[H=-1 ]')

    # 3. Case-insensitive update (set with different case)
    check("Case-insensitive update",
        tstr('id') + tstr2('old') + [
            'VARIABLE _N',
            ': t3 DOM-T-ELEMENT _DOM-ALLOC _N !',
            '  _N @ TA UA DOM-ATTR!',
            '  TR 73 TC 68 TC',
            '  UR 110 UC 101 UC 119 UC',
            '  _N @ TA UA DOM-ATTR!',
            '  _N @ DOM-ATTR-COUNT',
            '  CR ." [AC=" . ." ]"',
            '  TR 105 TC 100 TC',
            '  _N @ TA DOM-ATTR@',
            '  CR ." [F=" . ." ]"',
            '  CR ." [V=" TYPE ." ]" ; t3'],
        check_fn=lambda out: '[AC=1 ]' in out and '[F=-1 ]' in out and '[V=new]' in out)


def test_attr_delete():
    log_and_print("\n=== Attribute — Delete ===")

    # 1. Delete only attr
    check("Delete only attr",
        tstr('id') + tstr2('x') + [
            'VARIABLE _N',
            ': t1 DOM-T-ELEMENT _DOM-ALLOC _N !',
            '  _N @ TA UA DOM-ATTR!',
            '  _N @ TA DOM-ATTR-DEL',
            '  _N @ DOM-ATTR-COUNT',
            '  CR ." [AC=" . ." ]"',
            '  _N @ TA DOM-ATTR-HAS?',
            '  CR ." [H=" . ." ]" ; t1'],
        check_fn=lambda out: '[AC=0 ]' in out and '[H=0 ]' in out)

    # 2. Delete first of two
    check("Delete first of two attrs",
        tstr('id') + tstr2('x') + [
            'VARIABLE _N',
            ': t2 DOM-T-ELEMENT _DOM-ALLOC _N !',
            '  _N @ TA UA DOM-ATTR!',
            '  TR 104 TC 114 TC 101 TC 102 TC',
            '  UR 47 UC',
            '  _N @ TA UA DOM-ATTR!',
            '  TR 104 TC 114 TC 101 TC 102 TC',
            '  _N @ TA DOM-ATTR-DEL',
            '  _N @ DOM-ATTR-COUNT',
            '  CR ." [AC=" . ." ]"',
            '  TR 105 TC 100 TC',
            '  _N @ TA DOM-ATTR-HAS?',
            '  CR ." [H=" . ." ]" ; t2'],
        check_fn=lambda out: '[AC=1 ]' in out and '[H=-1 ]' in out)

    # 3. Delete second of two
    check("Delete second of two attrs",
        tstr('id') + tstr2('x') + [
            'VARIABLE _N',
            ': t3 DOM-T-ELEMENT _DOM-ALLOC _N !',
            '  _N @ TA UA DOM-ATTR!',
            '  TR 104 TC 114 TC 101 TC 102 TC',
            '  UR 47 UC',
            '  _N @ TA UA DOM-ATTR!',
            '  TR 105 TC 100 TC',
            '  _N @ TA DOM-ATTR-DEL',
            '  _N @ DOM-ATTR-COUNT',
            '  CR ." [AC=" . ." ]"',
            '  TR 104 TC 114 TC 101 TC 102 TC',
            '  _N @ TA DOM-ATTR-HAS?',
            '  CR ." [H=" . ." ]" ; t3'],
        check_fn=lambda out: '[AC=1 ]' in out and '[H=-1 ]' in out)

    # 4. Delete non-existent attr is no-op
    check("Delete non-existent no-op",
        tstr('nope') + [
            'VARIABLE _N',
            ': t4 DOM-T-ELEMENT _DOM-ALLOC _N !',
            '  _N @ TA DOM-ATTR-DEL',
            '  CR ." [OK]" ; t4'],
        '[OK]')


def test_attr_iterate():
    log_and_print("\n=== Attribute — Iteration ===")

    # 1. Iterate over attrs (order: last-set is first in list)
    check("Iterate attrs",
        tstr('id') + tstr2('main') + [
            'VARIABLE _N  VARIABLE _AT',
            ': t1 DOM-T-ELEMENT _DOM-ALLOC _N !',
            '  _N @ TA UA DOM-ATTR!',
            '  TR 104 TC 114 TC 101 TC 102 TC',
            '  UR 47 UC',
            '  _N @ TA UA DOM-ATTR!',
            '  _N @ DOM-ATTR-FIRST _AT !',
            '  _AT @ DOM-ATTR-NAME@ CR ." [N1=" TYPE ." ]"',
            '  _AT @ DOM-ATTR-VAL@ CR ." [V1=" TYPE ." ]"',
            '  _AT @ DOM-ATTR-NEXTATTR _AT !',
            '  _AT @ DOM-ATTR-NAME@ CR ." [N2=" TYPE ." ]"',
            '  _AT @ DOM-ATTR-VAL@ CR ." [V2=" TYPE ." ]"',
            '  _AT @ DOM-ATTR-NEXTATTR',
            '  CR ." [END=" . ." ]" ; t1'],
        check_fn=lambda out: '[N1=href]' in out and '[V1=/]' in out and
                             '[N2=id]' in out and '[V2=main]' in out and
                             '[END=0 ]' in out)


def test_attr_shortcuts():
    log_and_print("\n=== Attribute — Shortcuts ===")

    # 1. DOM-ID
    check("DOM-ID returns id value",
        tstr('id') + tstr2('page') + [
            'VARIABLE _N',
            ': t1 DOM-T-ELEMENT _DOM-ALLOC _N !',
            '  _N @ TA UA DOM-ATTR!',
            '  _N @ DOM-ID',
            '  CR ." [L=" DUP . ." ]"',
            '  CR ." [V=" TYPE ." ]" ; t1'],
        check_fn=lambda out: '[L=4 ]' in out and '[V=page]' in out)

    # 2. DOM-ID on node without id
    check("DOM-ID no id returns 0 0",
        [': t2 DOM-T-ELEMENT _DOM-ALLOC DOM-ID',
         '  CR ." [L=" . ." ][A=" . ." ]" ; t2'],
        '[L=0 ][A=0 ]')

    # 3. DOM-CLASS
    check("DOM-CLASS returns class value",
        tstr('class') + tstr2('box red') + [
            'VARIABLE _N',
            ': t3 DOM-T-ELEMENT _DOM-ALLOC _N !',
            '  _N @ TA UA DOM-ATTR!',
            '  _N @ DOM-CLASS',
            '  CR ." [V=" TYPE ." ]" ; t3'],
        '[V=box red]')


# ---------------------------------------------------------------------------
#  Stage 4 Tests — Mutation
# ---------------------------------------------------------------------------

def test_create_nodes():
    log_and_print("\n=== Mutation — Create Nodes ===")

    # 1. Create element
    check("Create element node",
        tstr('div') + [
            ': t1 TA DOM-CREATE-ELEMENT',
            '  DUP DOM-TYPE@ CR ." [T=" . ." ]"',
            '  DOM-TAG-NAME CR ." [N=" TYPE ." ]" ; t1'],
        check_fn=lambda out: '[T=1 ]' in out and '[N=div]' in out)

    # 2. Create text node
    check("Create text node",
        tstr('hello world') + [
            ': t2 TA DOM-CREATE-TEXT',
            '  DUP DOM-TYPE@ CR ." [T=" . ." ]"',
            '  DOM-TEXT CR ." [S=" TYPE ." ]" ; t2'],
        check_fn=lambda out: '[T=2 ]' in out and '[S=hello world]' in out)

    # 3. Create comment node
    check("Create comment node",
        tstr('a comment') + [
            ': t3 TA DOM-CREATE-COMMENT',
            '  DUP DOM-TYPE@ CR ." [T=" . ." ]"',
            '  DOM-TEXT CR ." [S=" TYPE ." ]" ; t3'],
        check_fn=lambda out: '[T=3 ]' in out and '[S=a comment]' in out)

    # 4. Create fragment
    check("Create fragment node",
        [': t4 DOM-CREATE-FRAGMENT DOM-TYPE@',
         '  CR ." [T=" . ." ]" ; t4'],
        '[T=5 ]')

    # 5. Create element + append children
    check("Create + append tree",
        tstr('ul') + [
            'VARIABLE _P',
            ': t5 TA DOM-CREATE-ELEMENT _P !',
            '  TR 108 TC 105 TC',
            '  TA DOM-CREATE-ELEMENT _P @ DOM-APPEND',
            '  _P @ DOM-CHILD-COUNT',
            '  CR ." [CC=" . ." ]"',
            '  _P @ DOM-FIRST-CHILD DOM-TAG-NAME',
            '  CR ." [C=" TYPE ." ]" ; t5'],
        check_fn=lambda out: '[CC=1 ]' in out and '[C=li]' in out)


def test_text_ops():
    log_and_print("\n=== Mutation — Text Operations ===")

    # 1. DOM-TEXT returns text content
    check("DOM-TEXT on text node",
        tstr('initial') + [
            ': t1 TA DOM-CREATE-TEXT DOM-TEXT',
            '  CR ." [S=" TYPE ." ]" ; t1'],
        '[S=initial]')

    # 2. DOM-SET-TEXT changes content
    check("DOM-SET-TEXT updates text",
        tstr('old') + [
            'VARIABLE _N',
            ': t2 TA DOM-CREATE-TEXT _N !',
            '  UR 110 UC 101 UC 119 UC',
            '  _N @ UA DOM-SET-TEXT',
            '  _N @ DOM-TEXT',
            '  CR ." [S=" TYPE ." ]" ; t2'],
        '[S=new]')

    # 3. DOM-TAG-NAME on element
    check("DOM-TAG-NAME returns tag",
        tstr('span') + [
            ': t3 TA DOM-CREATE-ELEMENT DOM-TAG-NAME',
            '  CR ." [N=" TYPE ." ]" ; t3'],
        '[N=span]')

    # 4. DOM-SET-TEXT on text node then read back
    check("SET-TEXT preserves old text gone",
        tstr('aaa') + [
            'VARIABLE _N',
            ': t4 TA DOM-CREATE-TEXT _N !',
            '  TR 98 TC 98 TC 98 TC',
            '  _N @ TA DOM-SET-TEXT',
            '  _N @ DOM-TEXT',
            '  CR ." [S=" TYPE ." ]" ; t4'],
        '[S=bbb]')


def test_dom_remove():
    log_and_print("\n=== Mutation — DOM-REMOVE ===")

    # 1. Remove single leaf node
    check("Remove leaf node",
        ['VARIABLE _P  VARIABLE _C',
         ': t1 DOM-T-ELEMENT _DOM-ALLOC _P !',
         '  DOM-T-ELEMENT _DOM-ALLOC _C !',
         '  _C @ _P @ DOM-APPEND',
         '  _C @ DOM-REMOVE',
         '  _P @ DOM-CHILD-COUNT',
         '  CR ." [CC=" . ." ]" ; t1'],
        '[CC=0 ]')

    # 2. Remove node with children (deep free)
    check("Remove node with children",
        ['VARIABLE _GP  VARIABLE _P  VARIABLE _C',
         ': t2 DOM-T-ELEMENT _DOM-ALLOC _GP !',
         '  DOM-T-ELEMENT _DOM-ALLOC _P !',
         '  DOM-T-ELEMENT _DOM-ALLOC _C !',
         '  _P @ _GP @ DOM-APPEND',
         '  _C @ _P @ DOM-APPEND',
         '  _P @ DOM-REMOVE',
         '  _GP @ DOM-CHILD-COUNT',
         '  CR ." [CC=" . ." ]" ; t2'],
        '[CC=0 ]')

    # 3. Remove frees attrs too
    check("Remove frees attrs",
        tstr('id') + tstr2('x') + [
            'VARIABLE _P  VARIABLE _C',
            ': t3 DOM-T-ELEMENT _DOM-ALLOC _P !',
            '  DOM-T-ELEMENT _DOM-ALLOC _C !',
            '  _C @ TA UA DOM-ATTR!',
            '  _C @ _P @ DOM-APPEND',
            '  _C @ DOM-REMOVE',
            '  _P @ DOM-CHILD-COUNT',
            '  CR ." [CC=" . ." ]" ; t3'],
        '[CC=0 ]')

    # 4. Remove middle child keeps siblings
    check("Remove middle child",
        ['VARIABLE _P  VARIABLE _A  VARIABLE _B  VARIABLE _C',
         ': t4 DOM-T-ELEMENT _DOM-ALLOC _P !',
         '  DOM-T-ELEMENT _DOM-ALLOC _A !',
         '  DOM-T-ELEMENT _DOM-ALLOC _B !',
         '  DOM-T-ELEMENT _DOM-ALLOC _C !',
         '  _A @ _P @ DOM-APPEND',
         '  _B @ _P @ DOM-APPEND',
         '  _C @ _P @ DOM-APPEND',
         '  _B @ DOM-REMOVE',
         '  _P @ DOM-CHILD-COUNT',
         '  CR ." [CC=" . ." ]"',
         '  _A @ DOM-NEXT _C @ =',
         '  CR ." [OK=" . ." ]" ; t4'],
        check_fn=lambda out: '[CC=2 ]' in out and '[OK=-1 ]' in out)

    # 5. Remove orphan node (no parent)
    check("Remove orphan node",
        [': t5 DOM-T-ELEMENT _DOM-ALLOC DOM-REMOVE',
         '  CR ." [OK]" ; t5'],
        '[OK]')

    # 6. Remove deep tree (3 levels)
    check("Remove 3-level deep tree",
        ['VARIABLE _R  VARIABLE _A  VARIABLE _B  VARIABLE _C',
         ': t6 DOM-T-ELEMENT _DOM-ALLOC _R !',
         '  DOM-T-ELEMENT _DOM-ALLOC _A !',
         '  DOM-T-ELEMENT _DOM-ALLOC _B !',
         '  DOM-T-ELEMENT _DOM-ALLOC _C !',
         '  _A @ _R @ DOM-APPEND',
         '  _B @ _A @ DOM-APPEND',
         '  _C @ _B @ DOM-APPEND',
         '  _A @ DOM-REMOVE',
         '  _R @ DOM-CHILD-COUNT',
         '  CR ." [CC=" . ." ]" ; t6'],
        '[CC=0 ]')

    # 7. Remove returns nodes to free-list (can alloc again)
    check("Remove recycles nodes",
        ['VARIABLE _R  VARIABLE _BEFORE  VARIABLE _AFTER',
         ': t7',
         '  DOM-DOC D.NODE-FREE @ _BEFORE !',
         '  DOM-T-ELEMENT _DOM-ALLOC _R !',
         '  DOM-T-ELEMENT _DOM-ALLOC _R @ DOM-APPEND',
         '  DOM-T-ELEMENT _DOM-ALLOC _R @ DOM-APPEND',
         '  _R @ DOM-REMOVE',
         '  DOM-DOC D.NODE-FREE @ _AFTER !',
         '  _BEFORE @ _AFTER @ =',
         '  CR ." [OK=" . ." ]" ; t7'],
        '[OK=-1 ]')

    # 8. Remove wide tree (3 children)
    check("Remove wide tree (3 kids)",
        ['VARIABLE _R',
         ': t8 DOM-T-ELEMENT _DOM-ALLOC _R !',
         '  DOM-T-ELEMENT _DOM-ALLOC _R @ DOM-APPEND',
         '  DOM-T-ELEMENT _DOM-ALLOC _R @ DOM-APPEND',
         '  DOM-T-ELEMENT _DOM-ALLOC _R @ DOM-APPEND',
         '  _R @ DOM-REMOVE',
         '  CR ." [OK]" ; t8'],
        '[OK]')


# ---------------------------------------------------------------------------
#  Stage 5 Tests — Style Resolution
# ---------------------------------------------------------------------------

def test_style_basic():
    log_and_print("\n=== Style — Basic ===")

    # 1. Compute style with tag selector
    check("Compute style tag selector",
        vstr('div { color: red }') + tstr('div') + [
            'VARIABLE _N',
            ': t1 VA DOM-SET-STYLESHEET',
            '  TA DOM-CREATE-ELEMENT _N !',
            '  _N @ _SB 2048 DOM-COMPUTE-STYLE',
            '  CR ." [L=" DUP . ." ]"',
            '  _SB SWAP CR ." [S=" TYPE ." ]" ; t1'],
        check_fn=lambda out: '[L=' in out and 'color: red' in out)

    # 2. No matching rules → 0 bytes
    check("No matching rules",
        vstr('span { color: blue }') + tstr('div') + [
            'VARIABLE _N',
            ': t2 VA DOM-SET-STYLESHEET',
            '  TA DOM-CREATE-ELEMENT _N !',
            '  _N @ _SB 2048 DOM-COMPUTE-STYLE',
            '  CR ." [L=" . ." ]" ; t2'],
        '[L=0 ]')

    # 3. Class selector match
    check("Class selector match",
        vstr('.box { display: flex }') + tstr('div') + [
            'VARIABLE _N',
            ': t3 VA DOM-SET-STYLESHEET',
            '  TA DOM-CREATE-ELEMENT _N !',
            '  TR 99 TC 108 TC 97 TC 115 TC 115 TC',
            '  UR 98 UC 111 UC 120 UC',
            '  _N @ TA UA DOM-ATTR!',
            '  _N @ _SB 2048 DOM-COMPUTE-STYLE',
            '  _SB SWAP CR ." [S=" TYPE ." ]" ; t3'],
        check_fn=lambda out: 'display: flex' in out)

    # 4. ID selector match
    check("ID selector match",
        vstr('#main { margin: 0 }') + tstr('div') + [
            'VARIABLE _N',
            ': t4 VA DOM-SET-STYLESHEET',
            '  TA DOM-CREATE-ELEMENT _N !',
            '  TR 105 TC 100 TC',
            '  UR 109 UC 97 UC 105 UC 110 UC',
            '  _N @ TA UA DOM-ATTR!',
            '  _N @ _SB 2048 DOM-COMPUTE-STYLE',
            '  _SB SWAP CR ." [S=" TYPE ." ]" ; t4'],
        check_fn=lambda out: 'margin: 0' in out)

    # 5. Multiple matching rules cascade
    check("Multiple rules cascade",
        vstr('div { color: red } div { font-size: 14px }') + tstr('div') + [
            'VARIABLE _N',
            ': t5 VA DOM-SET-STYLESHEET',
            '  TA DOM-CREATE-ELEMENT _N !',
            '  _N @ _SB 2048 DOM-COMPUTE-STYLE',
            '  _SB SWAP CR ." [S=" TYPE ." ]" ; t5'],
        check_fn=lambda out: 'color: red' in out and 'font-size: 14px' in out)

    # 6. Non-element node returns 0
    check("Text node returns 0 styles",
        tstr('hello') + [
            ': t6 TA DOM-CREATE-TEXT _SB 2048 DOM-COMPUTE-STYLE',
            '  CR ." [L=" . ." ]" ; t6'],
        '[L=0 ]')


def test_style_inline():
    log_and_print("\n=== Style — Inline ===")

    # 1. Inline style attribute is included
    check("Inline style included",
        vstr('div { color: red }') + tstr('div') + [
            'VARIABLE _N',
            ': t1 VA DOM-SET-STYLESHEET',
            '  TA DOM-CREATE-ELEMENT _N !',
            '  TR 115 TC 116 TC 121 TC 108 TC 101 TC',
            '  UR 102 UC 111 UC 110 UC 116 UC 45 UC 119 UC',
            '  101 UC 105 UC 103 UC 104 UC 116 UC 58 UC',
            '  32 UC 98 UC 111 UC 108 UC 100 UC',
            '  _N @ TA UA DOM-ATTR!',
            '  _N @ _SB 2048 DOM-COMPUTE-STYLE',
            '  _SB SWAP CR ." [S=" TYPE ." ]" ; t1'],
        check_fn=lambda out: 'color: red' in out and 'font-weight: bold' in out)

    # 2. Inline-only (no stylesheet rules)
    check("Inline only no rules",
        ['VARIABLE _N2',
         ': t2',
         '  VR VA DOM-SET-STYLESHEET',
         '  TR 100 TC 105 TC 118 TC',
         '  TA DOM-CREATE-ELEMENT _N2 !',
         '  TR 115 TC 116 TC 121 TC 108 TC 101 TC',
         '  UR 99 UC 111 UC 108 UC 111 UC 114 UC 58 UC',
         '  32 UC 98 UC 108 UC 117 UC 101 UC',
         '  _N2 @ TA UA DOM-ATTR!',
         '  _N2 @ _SB 2048 DOM-COMPUTE-STYLE',
         '  _SB SWAP CR ." [S=" TYPE ." ]" ; t2'],
        check_fn=lambda out: 'color: blue' in out)


def test_style_lookup():
    log_and_print("\n=== Style — Property Lookup ===")

    # 1. DOM-STYLE@ finds property
    check("DOM-STYLE@ finds color",
        vstr('div { color: red; font-size: 14px }') + tstr('div') + [
            'VARIABLE _N',
            ': t1 VA DOM-SET-STYLESHEET',
            '  TA DOM-CREATE-ELEMENT _N !',
            '  _N @ S" color" DOM-STYLE@',
            '  CR ." [F=" . ." ]"',
            '  CR ." [V=" TYPE ." ]" ; t1'],
        check_fn=lambda out: '[F=-1 ]' in out and '[V=red]' in out)

    # 2. DOM-STYLE@ for missing property
    check("DOM-STYLE@ missing prop",
        vstr('div { color: red }') + tstr('div') + [
            'VARIABLE _N',
            ': t2 VA DOM-SET-STYLESHEET',
            '  TA DOM-CREATE-ELEMENT _N !',
            '  _N @ S" margin" DOM-STYLE@',
            '  CR ." [F=" . ." ]" 2DROP ; t2'],
        '[F=0 ]')

    # 3. DOM-STYLE@ second property
    check("DOM-STYLE@ second prop",
        vstr('div { color: red; display: block }') + tstr('div') + [
            'VARIABLE _N',
            ': t3 VA DOM-SET-STYLESHEET',
            '  TA DOM-CREATE-ELEMENT _N !',
            '  _N @ S" display" DOM-STYLE@',
            '  CR ." [F=" . ." ]"',
            '  CR ." [V=" TYPE ." ]" ; t3'],
        check_fn=lambda out: '[F=-1 ]' in out and '[V=block]' in out)

    # 4. DOM-STYLE@ on text node
    check("DOM-STYLE@ on text node",
        tstr('hello') + [
            ': t4 TA DOM-CREATE-TEXT S" color" DOM-STYLE@',
            '  CR ." [F=" . ." ]" 2DROP ; t4'],
        '[F=0 ]')


def test_style_stubs():
    log_and_print("\n=== Style — Cache Stubs ===")

    # 1. DOM-STYLE-CACHED? returns 0
    check("STYLE-CACHED? returns 0",
        [': t1 DOM-T-ELEMENT _DOM-ALLOC DOM-STYLE-CACHED?',
         '  CR ." [C=" . ." ]" ; t1'],
        '[C=0 ]')

    # 2. DOM-INVALIDATE-STYLE is no-op
    check("INVALIDATE-STYLE no crash",
        [': t2 DOM-T-ELEMENT _DOM-ALLOC DOM-INVALIDATE-STYLE',
         '  CR ." [OK]" ; t2'],
        '[OK]')


# ---------------------------------------------------------------------------
#  Stage 6 Tests — Query & Traversal
# ---------------------------------------------------------------------------

# Helper: builds a small DOM tree for query tests
# Tree: root(div) -> [h1#title, p.intro, div.box -> [span, a.link]]
def _query_tree_setup():
    """Return Forth lines that create a test tree with known structure.
    Variables: _QR (root), _QH (h1), _QP (p), _QD (div.box), _QS (span), _QA (a)"""
    return [
        'VARIABLE _QR  VARIABLE _QH  VARIABLE _QP',
        'VARIABLE _QD  VARIABLE _QS  VARIABLE _QA',
        # root div
        'TR 100 TC 105 TC 118 TC',
        'TA DOM-CREATE-ELEMENT _QR !',
        # h1#title
        'TR 104 TC 49 TC',
        'TA DOM-CREATE-ELEMENT _QH !',
        'TR 105 TC 100 TC  UR 116 UC 105 UC 116 UC 108 UC 101 UC',
        '_QH @ TA UA DOM-ATTR!',
        '_QH @ _QR @ DOM-APPEND',
        # p.intro
        'TR 112 TC',
        'TA DOM-CREATE-ELEMENT _QP !',
        'TR 99 TC 108 TC 97 TC 115 TC 115 TC',
        'UR 105 UC 110 UC 116 UC 114 UC 111 UC',
        '_QP @ TA UA DOM-ATTR!',
        '_QP @ _QR @ DOM-APPEND',
        # div.box
        'TR 100 TC 105 TC 118 TC',
        'TA DOM-CREATE-ELEMENT _QD !',
        'TR 99 TC 108 TC 97 TC 115 TC 115 TC',
        'UR 98 UC 111 UC 120 UC',
        '_QD @ TA UA DOM-ATTR!',
        '_QD @ _QR @ DOM-APPEND',
        # span (inside div.box)
        'TR 115 TC 112 TC 97 TC 110 TC',
        'TA DOM-CREATE-ELEMENT _QS !',
        '_QS @ _QD @ DOM-APPEND',
        # a.link (inside div.box)
        'TR 97 TC',
        'TA DOM-CREATE-ELEMENT _QA !',
        'TR 99 TC 108 TC 97 TC 115 TC 115 TC',
        'UR 108 UC 105 UC 110 UC 107 UC',
        '_QA @ TA UA DOM-ATTR!',
        '_QA @ _QD @ DOM-APPEND',
    ]


def test_query_matches():
    log_and_print("\n=== Query — DOM-MATCHES? ===")

    # 1. Tag match
    check("MATCHES? tag",
        tstr('div') + [
            ': t1 TA DOM-CREATE-ELEMENT S" div" DOM-MATCHES? CR ." [M=" . ." ]" ; t1'],
        '[M=-1 ]')

    # 2. Tag no match
    check("MATCHES? tag no match",
        tstr('div') + [
            ': t2 TA DOM-CREATE-ELEMENT S" span" DOM-MATCHES? CR ." [M=" . ." ]" ; t2'],
        '[M=0 ]')

    # 3. Class match
    check("MATCHES? class",
        tstr('div') + tstr2('box') + [
            'VARIABLE _N',
            ': t3 TA DOM-CREATE-ELEMENT _N ! TR 99 TC 108 TC 97 TC 115 TC 115 TC _N @ TA UA DOM-ATTR! _N @ S" .box" DOM-MATCHES? CR ." [M=" . ." ]" ; t3'],
        '[M=-1 ]')

    # 4. Text node never matches
    check("MATCHES? text node",
        tstr('hi') + [
            ': t4 TA DOM-CREATE-TEXT S" div" DOM-MATCHES? CR ." [M=" . ." ]" ; t4'],
        '[M=0 ]')


def test_query_single():
    log_and_print("\n=== Query — DOM-QUERY ===")

    # 1. Find by tag
    check("Query by tag",
        _query_tree_setup() + [
            ': t1 _QR @ S" h1" DOM-QUERY _QH @ = CR ." [OK=" . ." ]" ; t1'],
        '[OK=-1 ]')

    # 2. Find by class
    check("Query by class",
        _query_tree_setup() + [
            ': t2 _QR @ S" .intro" DOM-QUERY _QP @ = CR ." [OK=" . ." ]" ; t2'],
        '[OK=-1 ]')

    # 3. Find nested element
    check("Query finds nested",
        _query_tree_setup() + [
            ': t3 _QR @ S" span" DOM-QUERY _QS @ = CR ." [OK=" . ." ]" ; t3'],
        '[OK=-1 ]')

    # 4. No match returns 0
    check("Query no match returns 0",
        _query_tree_setup() + [
            ': t4 _QR @ S" table" DOM-QUERY CR ." [R=" . ." ]" ; t4'],
        '[R=0 ]')

    # 5. First of multiple matches (depth-first)
    check("Query returns first match",
        _query_tree_setup() + [
            ': t5 _QR @ S" div" DOM-QUERY _QD @ = CR ." [OK=" . ." ]" ; t5'],
        '[OK=-1 ]')


def test_query_all():
    log_and_print("\n=== Query — DOM-QUERY-ALL ===")

    # 1. Find all by tag
    check("Query-all by tag",
        _query_tree_setup() + [
            'CREATE _QB 256 ALLOT',
            ': t1 _QR @ S" div" _QB 32 DOM-QUERY-ALL CR ." [N=" . ." ]" _QB @ _QD @ = CR ." [OK=" . ." ]" ; t1'],
        check_fn=lambda out: '[N=1 ]' in out and '[OK=-1 ]' in out)

    # 2. No matches returns 0
    check("Query-all no matches",
        _query_tree_setup() + [
            'CREATE _QB 256 ALLOT',
            ': t2 _QR @ S" table" _QB 32 DOM-QUERY-ALL CR ." [N=" . ." ]" ; t2'],
        '[N=0 ]')

    # 3. Multiple matches
    check("Query-all multiple",
        _query_tree_setup() + [
            'CREATE _QB 256 ALLOT',
            # Add a text node inside span to make it interesting
            ': t3 _QR @ S" .link" _QB 32 DOM-QUERY-ALL CR ." [N=" DUP . ." ]" 1 = IF _QB @ _QA @ = CR ." [OK=" . ." ]" THEN ; t3'],
        check_fn=lambda out: '[N=1 ]' in out and '[OK=-1 ]' in out)


def test_get_by_id():
    log_and_print("\n=== Query — DOM-GET-BY-ID ===")

    # 1. Find by id
    check("Get by id",
        _query_tree_setup() + [
            ': t1 _QR @ S" title" DOM-GET-BY-ID _QH @ = CR ." [OK=" . ." ]" ; t1'],
        '[OK=-1 ]')

    # 2. No match
    check("Get by id no match",
        _query_tree_setup() + [
            ': t2 _QR @ S" nope" DOM-GET-BY-ID CR ." [R=" . ." ]" ; t2'],
        '[R=0 ]')


def test_get_by_tag():
    log_and_print("\n=== Query — DOM-GET-BY-TAG ===")

    # 1. Find all divs
    check("Get by tag div",
        _query_tree_setup() + [
            'CREATE _QB 256 ALLOT',
            ': t1 _QR @ S" div" _QB 32 DOM-GET-BY-TAG CR ." [N=" . ." ]" ; t1'],
        '[N=1 ]')

    # 2. Find all with no match
    check("Get by tag no match",
        _query_tree_setup() + [
            'CREATE _QB 256 ALLOT',
            ': t2 _QR @ S" table" _QB 32 DOM-GET-BY-TAG CR ." [N=" . ." ]" ; t2'],
        '[N=0 ]')


def test_get_by_class():
    log_and_print("\n=== Query — DOM-GET-BY-CLASS ===")

    # 1. Find by class
    check("Get by class",
        _query_tree_setup() + [
            'CREATE _QB 256 ALLOT',
            ': t1 _QR @ S" box" _QB 32 DOM-GET-BY-CLASS CR ." [N=" . ." ]" _QB @ _QD @ = CR ." [OK=" . ." ]" ; t1'],
        check_fn=lambda out: '[N=1 ]' in out and '[OK=-1 ]' in out)


def test_walk_depth():
    log_and_print("\n=== Query — DOM-WALK-DEPTH ===")

    # 1. Walk counts all nodes
    check("Walk counts nodes",
        _query_tree_setup() + [
            'VARIABLE _WC',
            ': _WINC  ( node -- ) DROP 1 _WC +! ;',
            ": t1 0 _WC !  _QR @ ['] _WINC DOM-WALK-DEPTH _WC @ CR .\" [C=\" . .\" ]\" ; t1"],
        '[C=6 ]')

    # 2. Walk visits in depth-first order
    check("Walk depth-first order",
        ['VARIABLE _WP  VARIABLE _WC',
         'TR 100 TC 105 TC 118 TC',
         'TA DOM-CREATE-ELEMENT _WP !',
         'TR 97 TC  TA DOM-CREATE-ELEMENT _WP @ DOM-APPEND',
         'TR 98 TC  TA DOM-CREATE-ELEMENT _WP @ DOM-APPEND',
         'VARIABLE _WO',
         ': _WLOG  ( node -- ) DOM-TYPE@ DOM-T-ELEMENT = IF _WO @ 1+ _WO ! THEN ;',
         ": t2 0 _WO !  _WP @ ['] _WLOG DOM-WALK-DEPTH _WO @ CR .\" [C=\" . .\" ]\" ; t2"],
        '[C=3 ]')


def test_nth_child():
    log_and_print("\n=== Query — DOM-NTH-CHILD ===")

    # 1. 0th child
    check("Nth child 0",
        _query_tree_setup() + [
            ': t1 _QR @ 0 DOM-NTH-CHILD _QH @ = CR ." [OK=" . ." ]" ; t1'],
        '[OK=-1 ]')

    # 2. 1st child
    check("Nth child 1",
        _query_tree_setup() + [
            ': t2 _QR @ 1 DOM-NTH-CHILD _QP @ = CR ." [OK=" . ." ]" ; t2'],
        '[OK=-1 ]')

    # 3. 2nd child
    check("Nth child 2",
        _query_tree_setup() + [
            ': t3 _QR @ 2 DOM-NTH-CHILD _QD @ = CR ." [OK=" . ." ]" ; t3'],
        '[OK=-1 ]')

    # 4. Out of range
    check("Nth child out of range",
        _query_tree_setup() + [
            ': t4 _QR @ 10 DOM-NTH-CHILD CR ." [R=" . ." ]" ; t4'],
        '[R=0 ]')

    # 5. Empty parent
    check("Nth child empty parent",
        [': t5 DOM-T-ELEMENT _DOM-ALLOC 0 DOM-NTH-CHILD CR ." [R=" . ." ]" ; t5'],
        '[R=0 ]')


def test_serialize():
    log_and_print("\n=== Serialization — DOM-TO-HTML ===")

    # 1. Empty element → <div></div>
    check("Serialize empty element",
        tstr('div') + [
            'VARIABLE _N1',
            'TA DOM-CREATE-ELEMENT _N1 !',
            ': t1 _N1 @ _OB 1024 DOM-TO-HTML CR ." [" _OB SWAP TYPE ." ]" ; t1'],
        '[<div></div>]')

    # 2. Void element → <br> (no close tag)
    check("Serialize void element",
        tstr('br') + [
            'VARIABLE _N1',
            'TA DOM-CREATE-ELEMENT _N1 !',
            ': t2 _N1 @ _OB 1024 DOM-TO-HTML CR ." [" _OB SWAP TYPE ." ]" ; t2'],
        '[<br>]')

    # 3. Text node alone → hello
    check("Serialize text node",
        tstr('hello') + [
            'VARIABLE _N1',
            'TA DOM-CREATE-TEXT _N1 !',
            ': t3 _N1 @ _OB 1024 DOM-TO-HTML CR ." [" _OB SWAP TYPE ." ]" ; t3'],
        '[hello]')

    # 4. Comment → <!-- hello -->
    check("Serialize comment",
        tstr('hello') + [
            'VARIABLE _N1',
            'TA DOM-CREATE-COMMENT _N1 !',
            ': t4 _N1 @ _OB 1024 DOM-TO-HTML CR ." [" _OB SWAP TYPE ." ]" ; t4'],
        '[<!-- hello -->]')

    # 5. Element with text child → <div>hello</div>
    check("Serialize element + text",
        tstr('div') + [
            'VARIABLE _N1  VARIABLE _N2',
            'TA DOM-CREATE-ELEMENT _N1 !',
            'TR 104 TC 101 TC 108 TC 108 TC 111 TC',
            'TA DOM-CREATE-TEXT _N2 !',
            '_N2 @ _N1 @ DOM-APPEND',
            ': t5 _N1 @ _OB 1024 DOM-TO-HTML CR ." [" _OB SWAP TYPE ." ]" ; t5'],
        '[<div>hello</div>]')

    # 6. Nested elements → <div><span></span></div>
    check("Serialize nested elements",
        tstr('div') + [
            'VARIABLE _N1  VARIABLE _N2',
            'TA DOM-CREATE-ELEMENT _N1 !',
            'TR 115 TC 112 TC 97 TC 110 TC',
            'TA DOM-CREATE-ELEMENT _N2 !',
            '_N2 @ _N1 @ DOM-APPEND',
            ': t6 _N1 @ _OB 1024 DOM-TO-HTML CR ." [" _OB SWAP TYPE ." ]" ; t6'],
        '[<div><span></span></div>]')

    # 7. Deep nesting → <div><p><span>txt</span></p></div>
    check("Serialize deep nesting",
        tstr('div') + [
            'VARIABLE _N1  VARIABLE _N2  VARIABLE _N3  VARIABLE _N4',
            'TA DOM-CREATE-ELEMENT _N1 !',
            'TR 112 TC  TA DOM-CREATE-ELEMENT _N2 !',
            '_N2 @ _N1 @ DOM-APPEND',
            'TR 115 TC 112 TC 97 TC 110 TC',
            'TA DOM-CREATE-ELEMENT _N3 !',
            '_N3 @ _N2 @ DOM-APPEND',
            'TR 116 TC 120 TC 116 TC',
            'TA DOM-CREATE-TEXT _N4 !',
            '_N4 @ _N3 @ DOM-APPEND',
            ': t7 _N1 @ _OB 1024 DOM-TO-HTML CR ." [" _OB SWAP TYPE ." ]" ; t7'],
        '[<div><p><span>txt</span></p></div>]')

    # 8. Siblings → <ul><li></li><li></li></ul>
    check("Serialize siblings",
        tstr('ul') + [
            'VARIABLE _N1  VARIABLE _N2  VARIABLE _N3',
            'TA DOM-CREATE-ELEMENT _N1 !',
            'TR 108 TC 105 TC',
            'TA DOM-CREATE-ELEMENT _N2 !',
            '_N2 @ _N1 @ DOM-APPEND',
            'TA DOM-CREATE-ELEMENT _N3 !',
            '_N3 @ _N1 @ DOM-APPEND',
            ': t8 _N1 @ _OB 1024 DOM-TO-HTML CR ." [" _OB SWAP TYPE ." ]" ; t8'],
        '[<ul><li></li><li></li></ul>]')

    # 9. Element with attribute → <div class="box"></div>
    check("Serialize with attr",
        tstr('div') + tstr2('box') + [
            'VARIABLE _N1',
            'TA DOM-CREATE-ELEMENT _N1 !',
            'TR 99 TC 108 TC 97 TC 115 TC 115 TC',
            '_N1 @ TA UA DOM-ATTR!',
            ': t9 _N1 @ _OB 1024 DOM-TO-HTML CR ." [" _OB SWAP TYPE ." ]" ; t9'],
        '[<div class="box"></div>]')

    # 10. Text escaping (< and > in text content)
    check("Serialize text escaping",
        tstr('p') + [
            'VARIABLE _N1  VARIABLE _N2',
            'TA DOM-CREATE-ELEMENT _N1 !',
            'TR 60 TC 101 TC 109 TC 62 TC',
            'TA DOM-CREATE-TEXT _N2 !',
            '_N2 @ _N1 @ DOM-APPEND',
            ': t10 _N1 @ _OB 1024 DOM-TO-HTML CR ." [" _OB SWAP TYPE ." ]" ; t10'],
        '[<p>&lt;em&gt;</p>]')

    # 11. Return value = correct length
    check("TO-HTML returns length",
        tstr('div') + [
            'VARIABLE _N1',
            'TA DOM-CREATE-ELEMENT _N1 !',
            ': t11 _N1 @ _OB 1024 DOM-TO-HTML CR ." [N=" . ." ]" ; t11'],
        '[N=11 ]')

    # 12. Multiple attributes
    check("Serialize multiple attrs",
        tstr('a') + [
            'VARIABLE _N1',
            'TA DOM-CREATE-ELEMENT _N1 !',
            'TR 104 TC 114 TC 101 TC 102 TC',
            'UR 117 UC 114 UC 108 UC',
            '_N1 @ TA UA DOM-ATTR!',
            'TR 99 TC 108 TC 97 TC 115 TC 115 TC',
            'UR 108 UC 105 UC 110 UC 107 UC',
            '_N1 @ TA UA DOM-ATTR!',
            ': t12 _N1 @ _OB 1024 DOM-TO-HTML CR ." [" _OB SWAP TYPE ." ]" ; t12'],
        check_fn=lambda out: 'href="url"' in out and 'class="link"' in out
                             and '</a>]' in out)


def test_inner_outer_html():
    log_and_print("\n=== Serialization — Inner/Outer HTML ===")

    # 1. Inner HTML → children only
    check("Inner HTML",
        tstr('div') + [
            'VARIABLE _N1  VARIABLE _N2',
            'TA DOM-CREATE-ELEMENT _N1 !',
            'TR 115 TC 112 TC 97 TC 110 TC',
            'TA DOM-CREATE-ELEMENT _N2 !',
            '_N2 @ _N1 @ DOM-APPEND',
            ': t1 _N1 @ _OB 1024 DOM-INNER-HTML CR ." [" _OB SWAP TYPE ." ]" ; t1'],
        '[<span></span>]')

    # 2. Inner HTML empty → returns 0
    check("Inner HTML empty",
        tstr('div') + [
            'VARIABLE _N1',
            'TA DOM-CREATE-ELEMENT _N1 !',
            ': t2 _N1 @ _OB 1024 DOM-INNER-HTML CR ." [N=" . ." ]" ; t2'],
        '[N=0 ]')

    # 3. Outer HTML == TO-HTML (same length)
    check("Outer HTML equals TO-HTML",
        tstr('div') + [
            'VARIABLE _N1  VARIABLE _L1',
            'TA DOM-CREATE-ELEMENT _N1 !',
            ': t3 _N1 @ _OB 1024 DOM-TO-HTML _L1 ! _N1 @ _OB 1024 DOM-OUTER-HTML _L1 @ = CR ." [OK=" . ." ]" ; t3'],
        '[OK=-1 ]')

    # 4. Fragment → children only (no wrapping tag)
    check("Serialize fragment",
        ['VARIABLE _F  VARIABLE _N1  VARIABLE _N2',
         'DOM-CREATE-FRAGMENT _F !',
         'TR 100 TC 105 TC 118 TC',
         'TA DOM-CREATE-ELEMENT _N1 !',
         '_N1 @ _F @ DOM-APPEND',
         'TR 112 TC',
         'TA DOM-CREATE-ELEMENT _N2 !',
         '_N2 @ _F @ DOM-APPEND',
         ': t4 _F @ _OB 1024 DOM-TO-HTML CR ." [" _OB SWAP TYPE ." ]" ; t4'],
        '[<div></div><p></p>]')

    # 5. Inner HTML with multiple children
    check("Inner HTML multi children",
        tstr('div') + [
            'VARIABLE _N1  VARIABLE _N2  VARIABLE _N3',
            'TA DOM-CREATE-ELEMENT _N1 !',
            'TR 97 TC  TA DOM-CREATE-ELEMENT _N2 !',
            '_N2 @ _N1 @ DOM-APPEND',
            'TR 98 TC  TA DOM-CREATE-ELEMENT _N3 !',
            '_N3 @ _N1 @ DOM-APPEND',
            ': t5 _N1 @ _OB 1024 DOM-INNER-HTML CR ." [" _OB SWAP TYPE ." ]" ; t5'],
        '[<a></a><b></b>]')


def test_parse_basic():
    log_and_print("\n=== Parser — Basic ===")

    # 1. Simple element
    check("Parse simple element",
        tstr('<div></div>') + [
            'VARIABLE _R',
            ': t1 TA DOM-PARSE-HTML _R ! _R @ DOM-FIRST-CHILD DOM-TAG-NAME CR ." [" TYPE ." ]" ; t1'],
        '[div]')

    # 2. Nested elements
    check("Parse nested",
        tstr('<div><span></span></div>') + [
            'VARIABLE _R',
            ': t2 TA DOM-PARSE-HTML _R ! _R @ DOM-FIRST-CHILD DOM-FIRST-CHILD DOM-TAG-NAME CR ." [" TYPE ." ]" ; t2'],
        '[span]')

    # 3. Text content
    check("Parse text content",
        tstr('<p>hello</p>') + [
            'VARIABLE _R',
            ': t3 TA DOM-PARSE-HTML _R ! _R @ DOM-FIRST-CHILD DOM-FIRST-CHILD DOM-TEXT CR ." [" TYPE ." ]" ; t3'],
        '[hello]')

    # 4. Attribute
    check("Parse attribute",
        tstr('<div class="box"></div>') + [
            'VARIABLE _R',
            ': t4 TA DOM-PARSE-HTML _R ! _R @ DOM-FIRST-CHILD DOM-CLASS CR ." [" TYPE ." ]" ; t4'],
        '[box]')

    # 5. Void element — br has no children, text after it is sibling
    check("Parse void element",
        tstr('<br>') + [
            'VARIABLE _R  VARIABLE _B',
            ': t5 TA DOM-PARSE-HTML _R ! _R @ DOM-FIRST-CHILD _B ! _B @ DOM-TAG-NAME CR ." [" TYPE ." ]" _B @ DOM-CHILD-COUNT CR ." [C=" . ." ]" ; t5'],
        check_fn=lambda out: '[br]' in out and '[C=0 ]' in out)

    # 6. Self-closing tag
    check("Parse self-closing",
        tstr('<img/>') + [
            'VARIABLE _R',
            ': t6 TA DOM-PARSE-HTML _R ! _R @ DOM-FIRST-CHILD DOM-TAG-NAME CR ." [" TYPE ." ]" ; t6'],
        '[img]')

    # 7. Comment
    check("Parse comment",
        tstr('<!-- note -->') + [
            'VARIABLE _R  VARIABLE _C',
            ': t7 TA DOM-PARSE-HTML _R ! _R @ DOM-FIRST-CHILD _C ! _C @ DOM-TYPE@ CR ." [T=" . ." ]" ; t7'],
        '[T=3 ]')

    # 8. DOCTYPE is skipped
    check("Parse skips DOCTYPE",
        tstr('<!DOCTYPE html><p></p>') + [
            'VARIABLE _R',
            ': t8 TA DOM-PARSE-HTML _R ! _R @ DOM-FIRST-CHILD DOM-TAG-NAME CR ." [" TYPE ." ]" ; t8'],
        '[p]')


def test_parse_complex():
    log_and_print("\n=== Parser — Complex ===")

    # 1. Multiple children
    check("Parse multiple children",
        tstr('<ul><li></li><li></li></ul>') + [
            'VARIABLE _R',
            ': t1 TA DOM-PARSE-HTML _R ! _R @ DOM-FIRST-CHILD DOM-CHILD-COUNT CR ." [C=" . ." ]" ; t1'],
        '[C=2 ]')

    # 2. Deep nesting
    check("Parse deep nesting",
        tstr('<div><p><span>x</span></p></div>') + [
            'VARIABLE _R  VARIABLE _D',
            ': t2 TA DOM-PARSE-HTML _R ! _R @ DOM-FIRST-CHILD _D !',
            '  _D @ DOM-FIRST-CHILD DOM-FIRST-CHILD DOM-FIRST-CHILD',
            '  DOM-TEXT CR ." [" TYPE ." ]" ; t2'],
        '[x]')

    # 3. Void inside element — text after br
    check("Parse void inside element",
        tstr('<p>a<br>b</p>') + [
            'VARIABLE _R  VARIABLE _P',
            ': t3 TA DOM-PARSE-HTML _R ! _R @ DOM-FIRST-CHILD _P ! _P @ DOM-CHILD-COUNT CR ." [C=" . ." ]" ; t3'],
        '[C=3 ]')

    # 4. Multiple attributes
    check("Parse multiple attrs",
        tstr('<a href="u" class="l"></a>') + [
            'VARIABLE _R  VARIABLE _A',
            ': t4 TA DOM-PARSE-HTML _R ! _R @ DOM-FIRST-CHILD _A ! _A @ DOM-ATTR-COUNT CR ." [C=" . ." ]" _A @ DOM-CLASS CR ." [" TYPE ." ]" ; t4'],
        check_fn=lambda out: '[C=2 ]' in out and '[l]' in out)

    # 5. Mixed text and elements
    check("Parse mixed text and elements",
        tstr('hi <b>world</b>!') + [
            'VARIABLE _R',
            ': t5 TA DOM-PARSE-HTML _R ! _R @ DOM-CHILD-COUNT CR ." [C=" . ." ]" ; t5'],
        '[C=3 ]')

    # 6. Parse fragment into existing parent
    check("Parse fragment",
        vstr('<a></a><b></b>') + [
            'VARIABLE _P',
            'TR 100 TC 105 TC 118 TC  TA DOM-CREATE-ELEMENT _P !',
            ': t6 VA _P @ DOM-PARSE-FRAGMENT _P @ DOM-CHILD-COUNT CR ." [C=" . ." ]" ; t6'],
        '[C=2 ]')

    # 7. Round-trip: parse then serialize
    check("Parse-serialize round trip",
        tstr('<div><p>hello</p></div>') + [
            'VARIABLE _R',
            ': t7 TA DOM-PARSE-HTML _R ! _R @ DOM-FIRST-CHILD _OB 1024 DOM-TO-HTML CR ." [" _OB SWAP TYPE ." ]" ; t7'],
        '[<div><p>hello</p></div>]')


# ---------------------------------------------------------------------------
#  Main
# ---------------------------------------------------------------------------

if __name__ == '__main__':
    _log_file = open(LOG_PATH, 'w')
    log_and_print(f"DOM test log: {LOG_PATH}")

    try:
        build_snapshot()
        test_doc_creation()
        test_string_pool()
        test_multi_document()
        test_node_alloc()
        test_tree_append()
        test_tree_prepend()
        test_tree_detach()
        test_tree_insert_before()
        test_tree_traversal()
        test_attr_basic()
        test_attr_case()
        test_attr_delete()
        test_attr_iterate()
        test_attr_shortcuts()
        test_create_nodes()
        test_text_ops()
        test_dom_remove()
        test_style_basic()
        test_style_inline()
        test_style_lookup()
        test_style_stubs()
        test_query_matches()
        test_query_single()
        test_query_all()
        test_get_by_id()
        test_get_by_tag()
        test_get_by_class()
        test_walk_depth()
        test_nth_child()
        test_serialize()
        test_inner_outer_html()
        test_parse_basic()
        test_parse_complex()
    finally:
        log_and_print(f"\n{'='*50}")
        log_and_print(f"Results: {_pass_count} passed, {_fail_count} failed, "
                      f"{_pass_count + _fail_count} total")
        if _log_file:
            _log_file.close()

    sys.exit(1 if _fail_count > 0 else 0)
