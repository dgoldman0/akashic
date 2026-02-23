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
    finally:
        log_and_print(f"\n{'='*50}")
        log_and_print(f"Results: {_pass_count} passed, {_fail_count} failed, "
                      f"{_pass_count + _fail_count} total")
        if _log_file:
            _log_file.close()

    sys.exit(1 if _fail_count > 0 else 0)
