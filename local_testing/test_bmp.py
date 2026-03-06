#!/usr/bin/env python3
# ┌──────────────────────────────────────────────────────────────┐
# │ HARNESS UPDATE REQUIRED (March 2026)                         │
# │                                                              │
# │ 1. BOOT-TO-IDLE: run_forth() must call boot() on a fresh    │
# │    MegapadSystem before overwriting RAM/CPU state from the   │
# │    snapshot.  Without boot(), the C++ accelerator's MMIO     │
# │    routing (UART writes) is never wired → empty output.      │
# │    Fix: save bios_code in the snapshot tuple, then in        │
# │    run_forth(): load_binary(0, bios_code), boot(), run to    │
# │    idle, THEN overwrite mem/cpu/ext from snapshot.           │
# │                                                              │
# │ 2. NO [: ;] CLOSURES: This BIOS/KDOS does not define the    │
# │    [: ... ;] anonymous quotation words.  Replace all uses    │
# │    with named helper words and ['] ticks.                    │
# │                                                              │
# │ See test_coroutine.py for the corrected pattern.             │
# └──────────────────────────────────────────────────────────────┘
"""Test suite for Akashic render/bmp.f — BMP Image Encoder.

Uses snapshot-based testing: boots BIOS + KDOS, loads surface.f + bmp.f
via REQUIRE, then replays from snapshot for each test.

Validates BMP output by checking headers and pixel data against
Python's struct-based BMP parser.
"""
import os, sys, struct, time, tempfile, unittest

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.dirname(SCRIPT_DIR)
EMU_DIR    = os.path.join(SCRIPT_DIR, "emu")
AK_DIR     = os.path.join(ROOT_DIR, "akashic")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

SECTOR = 512

# ── Disk image builder ──

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

# ── Emulator helpers ──

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

def _feed_and_run(sys_obj, buf, lines, max_steps):
    payload = "\n".join(lines) + "\n"
    data = payload.encode(); pos = 0; steps = 0
    while steps < max_steps:
        if sys_obj.cpu.halted: break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk); pos += len(chunk)
            else: break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)
    return steps

def build_snapshot():
    global _snapshot, _img_path
    if _snapshot is not None:
        return _snapshot

    print("[*] Building disk image ...")

    # Directory layout:
    #  0: math/       (parent=255 → root)
    #  1: fp16.f      (parent=0)
    #  2: fp16-ext.f  (parent=0)
    #  3: exp.f       (parent=0)
    #  4: color.f     (parent=0)
    #  5: render/     (parent=255)
    #  6: surface.f   (parent=5)
    #  7: bmp.f       (parent=5)

    disk_files = [
        ("math",       255, 8, b''),
        ("fp16.f",       0, 1, read_file_bytes(os.path.join(AK_DIR, "math", "fp16.f"))),
        ("fp16-ext.f",   0, 1, read_file_bytes(os.path.join(AK_DIR, "math", "fp16-ext.f"))),
        ("exp.f",        0, 1, read_file_bytes(os.path.join(AK_DIR, "math", "exp.f"))),
        ("color.f",      0, 1, read_file_bytes(os.path.join(AK_DIR, "math", "color.f"))),
        ("render",     255, 8, b''),
        ("surface.f",    5, 1, read_file_bytes(os.path.join(AK_DIR, "render", "surface.f"))),
        ("bmp.f",        5, 1, read_file_bytes(os.path.join(AK_DIR, "render", "bmp.f"))),
    ]

    image = build_disk_image(disk_files)
    _img_path = os.path.join(tempfile.gettempdir(), 'test_bmp.img')
    with open(_img_path, 'wb') as f:
        f.write(image)
    data_secs = sum(max(1, (len(c)+511)//512) for _,_,t,c in disk_files if t != 8)
    print(f"    {len(image)//1024}KB image, {data_secs} data sectors")

    print("[*] Booting KDOS ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_kdos_lines(KDOS_PATH)

    sys_obj = MegapadSystem(ram_size=1024*1024, storage_image=_img_path,
                            ext_mem_size=16*(1<<20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    steps = _feed_and_run(sys_obj, buf, kdos_lines, 400_000_000)
    elapsed = time.time() - t0
    print(f"    KDOS ready — {steps:,} steps, {elapsed:.1f}s")

    print("[*] Loading bmp.f via REQUIRE ...")
    buf.clear()
    t0 = time.time()

    load_lines = [
        'ENTER-USERLAND',
        'CD render',
        'REQUIRE bmp.f',
        # scratch variables for tests
        'VARIABLE _S   VARIABLE _B   VARIABLE _LEN',
        'VARIABLE _BUF',
        # allocate a large output buffer (64KB)
        '65536 ALLOCATE DROP _BUF !',
    ]

    steps = _feed_and_run(sys_obj, buf, load_lines, 800_000_000)
    load_text = uart_text(buf)
    elapsed = time.time() - t0
    print(f"    Loaded — {steps:,} steps, {elapsed:.1f}s")

    load_errs = [l for l in load_text.split('\n')
                 if 'not found' in l.lower() or 'error' in l.lower() or 'abort' in l.lower()]
    if load_errs:
        print("[!] Errors during load:")
        for e in load_errs[-15:]:
            print(f"    {e}")

    _snapshot = (bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print("[*] Snapshot ready.")
    return _snapshot


def run_forth(lines, max_steps=200_000_000):
    mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16*(1<<20))
    buf = capture_uart(sys_obj)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    sys_obj._storage_path = _img_path

    steps = _feed_and_run(sys_obj, buf, lines, max_steps)
    text = uart_text(buf)
    return text, sys_obj

def run_forth_values(lines, max_steps=200_000_000):
    """Run Forth lines and parse output for integers from 'ok' lines."""
    text, sys_obj = run_forth(lines, max_steps)
    vals = []
    for line in text.split('\n'):
        line = line.strip()
        if 'ok' in line:
            for tok in line.replace('ok', '').split():
                try:
                    vals.append(int(tok))
                except ValueError:
                    pass
    return vals, sys_obj

def read_mem(sys_obj, addr, length):
    """Read bytes from emulator memory (handles ext mem transparently)."""
    EXT_BASE = 0x100000
    result = bytearray(length)
    for i in range(length):
        a = addr + i
        if a >= EXT_BASE:
            result[i] = sys_obj._ext_mem[a - EXT_BASE]
        else:
            result[i] = sys_obj.cpu.mem[a]
    return bytes(result)


# ── BMP validation helpers ──

def parse_bmp_header(data):
    """Parse BMP file header + DIB header. Returns dict."""
    if len(data) < 54:
        return None
    sig = data[0:2]
    file_size = struct.unpack_from('<I', data, 2)[0]
    pix_offset = struct.unpack_from('<I', data, 10)[0]
    dib_size = struct.unpack_from('<I', data, 14)[0]
    width = struct.unpack_from('<i', data, 18)[0]
    height = struct.unpack_from('<i', data, 22)[0]
    planes = struct.unpack_from('<H', data, 26)[0]
    bpp = struct.unpack_from('<H', data, 28)[0]
    compression = struct.unpack_from('<I', data, 30)[0]
    return {
        'sig': sig, 'file_size': file_size, 'pix_offset': pix_offset,
        'dib_size': dib_size, 'width': width, 'height': height,
        'planes': planes, 'bpp': bpp, 'compression': compression,
    }

def bmp_pixel_at(data, w, h, x, y):
    """Get pixel (B,G,R,A) from BMP data at (x, y) in image coords (top-down)."""
    # BMP rows are bottom-to-top, so row 0 in BMP = bottom of image
    bmp_row = h - 1 - y
    offset = 54 + (bmp_row * w * 4) + (x * 4)
    b, g, r, a = data[offset], data[offset+1], data[offset+2], data[offset+3]
    return (r, g, b, a)  # return as RGBA


class TestBmpEncoder(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        build_snapshot()

    def _encode_and_read(self, w, h, setup_lines):
        """Create w×h surface, run setup_lines, encode to BMP, return (bmp_bytes, sys_obj)."""
        lines = [
            f'{w} {h} SURF-CREATE _S !',
        ] + setup_lines + [
            '_S @ _BUF @ 65536 BMP-ENCODE _LEN !',
            '_BUF @ . _LEN @ .',
        ]
        vals, sys_obj = run_forth_values(lines)
        self.assertEqual(len(vals), 2, f"Expected [addr, len], got {vals}")
        buf_addr, length = vals
        bmp_data = read_mem(sys_obj, buf_addr, length)
        return bmp_data, length

    # ── BMP-FILE-SIZE ──

    def test_file_size_1x1(self):
        vals, _ = run_forth_values(['1 1 BMP-FILE-SIZE .'])
        self.assertEqual(vals, [54 + 4])

    def test_file_size_2x2(self):
        vals, _ = run_forth_values(['2 2 BMP-FILE-SIZE .'])
        self.assertEqual(vals, [54 + 16])

    def test_file_size_10x10(self):
        vals, _ = run_forth_values(['10 10 BMP-FILE-SIZE .'])
        self.assertEqual(vals, [54 + 400])

    def test_file_size_100x50(self):
        vals, _ = run_forth_values(['100 50 BMP-FILE-SIZE .'])
        self.assertEqual(vals, [54 + 20000])

    # ── BMP-ENCODE basic ──

    def test_encode_returns_correct_length(self):
        vals, _ = run_forth_values([
            '2 2 SURF-CREATE _S !',
            '_S @ _BUF @ 65536 BMP-ENCODE .',
            '_S @ SURF-DESTROY',
        ])
        self.assertEqual(vals, [54 + 16])

    def test_encode_buffer_too_small(self):
        vals, _ = run_forth_values([
            '2 2 SURF-CREATE _S !',
            '_S @ _BUF @ 10 BMP-ENCODE .',
            '_S @ SURF-DESTROY',
        ])
        self.assertEqual(vals, [0])

    # ── BMP header validation ──

    def test_header_signature(self):
        bmp_data, length = self._encode_and_read(4, 3, [])
        self.assertGreater(length, 54)
        hdr = parse_bmp_header(bmp_data)
        self.assertEqual(hdr['sig'], b'BM')

    def test_header_fields(self):
        bmp_data, length = self._encode_and_read(4, 3, [])
        hdr = parse_bmp_header(bmp_data)
        self.assertEqual(hdr['file_size'], 54 + 4*3*4)
        self.assertEqual(hdr['pix_offset'], 54)
        self.assertEqual(hdr['dib_size'], 40)
        self.assertEqual(hdr['width'], 4)
        self.assertEqual(hdr['height'], 3)
        self.assertEqual(hdr['planes'], 1)
        self.assertEqual(hdr['bpp'], 32)
        self.assertEqual(hdr['compression'], 0)

    # ── Pixel data validation ──

    def test_solid_red(self):
        bmp_data, _ = self._encode_and_read(2, 2, [
            '_S @ 0 0 2 2 0xFF0000FF SURF-FILL-RECT',
        ])
        for y in range(2):
            for x in range(2):
                self.assertEqual(bmp_pixel_at(bmp_data, 2, 2, x, y),
                                 (255, 0, 0, 255), f"Pixel ({x},{y})")

    def test_solid_green(self):
        bmp_data, _ = self._encode_and_read(2, 2, [
            '_S @ 0 0 2 2 0x00FF00FF SURF-FILL-RECT',
        ])
        for y in range(2):
            for x in range(2):
                self.assertEqual(bmp_pixel_at(bmp_data, 2, 2, x, y),
                                 (0, 255, 0, 255))

    def test_solid_blue(self):
        bmp_data, _ = self._encode_and_read(2, 2, [
            '_S @ 0 0 2 2 0x0000FFFF SURF-FILL-RECT',
        ])
        for y in range(2):
            for x in range(2):
                self.assertEqual(bmp_pixel_at(bmp_data, 2, 2, x, y),
                                 (0, 0, 255, 255))

    def test_individual_pixels(self):
        bmp_data, _ = self._encode_and_read(3, 2, [
            '_S @ 0 0 3 2 0x000000FF SURF-FILL-RECT',
            '_S @ 0 0 0xFF0000FF SURF-PIXEL!',
            '_S @ 1 0 0x00FF00FF SURF-PIXEL!',
            '_S @ 2 0 0x0000FFFF SURF-PIXEL!',
            '_S @ 0 1 0xFFFFFFFF SURF-PIXEL!',
            '_S @ 1 1 0xFFFF00FF SURF-PIXEL!',
            '_S @ 2 1 0x00FFFFFF SURF-PIXEL!',
        ])
        expected = {
            (0, 0): (255, 0, 0, 255),
            (1, 0): (0, 255, 0, 255),
            (2, 0): (0, 0, 255, 255),
            (0, 1): (255, 255, 255, 255),
            (1, 1): (255, 255, 0, 255),
            (2, 1): (0, 255, 255, 255),
        }
        for (x, y), (er, eg, eb, ea) in expected.items():
            self.assertEqual(bmp_pixel_at(bmp_data, 3, 2, x, y),
                             (er, eg, eb, ea), f"Pixel ({x},{y})")

    def test_transparent_pixels(self):
        bmp_data, _ = self._encode_and_read(1, 1, [
            '_S @ 0 0 0xFF000080 SURF-PIXEL!',
        ])
        self.assertEqual(bmp_pixel_at(bmp_data, 1, 1, 0, 0),
                         (255, 0, 0, 128))

    # ── Row ordering ──

    def test_row_order(self):
        bmp_data, _ = self._encode_and_read(2, 3, [
            '_S @ 0 0 2 3 0x000000FF SURF-FILL-RECT',
            '_S @ 0 0 2 1 0xFF0000FF SURF-FILL-RECT',
            '_S @ 0 1 2 1 0x00FF00FF SURF-FILL-RECT',
            '_S @ 0 2 2 1 0x0000FFFF SURF-FILL-RECT',
        ])
        self.assertEqual(bmp_pixel_at(bmp_data, 2, 3, 0, 0), (255, 0, 0, 255))
        self.assertEqual(bmp_pixel_at(bmp_data, 2, 3, 1, 0), (255, 0, 0, 255))
        self.assertEqual(bmp_pixel_at(bmp_data, 2, 3, 0, 1), (0, 255, 0, 255))
        self.assertEqual(bmp_pixel_at(bmp_data, 2, 3, 0, 2), (0, 0, 255, 255))

    # ── 1x1 edge case ──

    def test_1x1_surface(self):
        bmp_data, length = self._encode_and_read(1, 1, [
            '_S @ 0 0 0xDEADBEEF SURF-PIXEL!',
        ])
        self.assertEqual(length, 58)
        hdr = parse_bmp_header(bmp_data)
        self.assertEqual(hdr['width'], 1)
        self.assertEqual(hdr['height'], 1)
        self.assertEqual(bmp_pixel_at(bmp_data, 1, 1, 0, 0),
                         (0xDE, 0xAD, 0xBE, 0xEF))

    # ── Larger surface ──

    def test_10x10_encode(self):
        bmp_data, length = self._encode_and_read(10, 10, [
            '_S @ 0 0 10 10 0xAABBCCDD SURF-FILL-RECT',
        ])
        self.assertEqual(length, 54 + 400)
        hdr = parse_bmp_header(bmp_data)
        self.assertEqual(hdr['width'], 10)
        self.assertEqual(hdr['height'], 10)
        for y in [0, 5, 9]:
            for x in [0, 5, 9]:
                self.assertEqual(bmp_pixel_at(bmp_data, 10, 10, x, y),
                                 (0xAA, 0xBB, 0xCC, 0xDD), f"Pixel ({x},{y})")


if __name__ == '__main__':
    unittest.main(verbosity=2)
