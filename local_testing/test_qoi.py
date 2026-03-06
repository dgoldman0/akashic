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
"""Test suite for Akashic render/qoi.f — QOI Image Encoder/Decoder.

Uses snapshot-based testing: boots BIOS + KDOS, loads surface.f + qoi.f
via REQUIRE, then replays from snapshot for each test.
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
    #  0: math/       (parent=255)
    #  1: fp16.f      (parent=0)
    #  2: fp16-ext.f  (parent=0)
    #  3: exp.f       (parent=0)
    #  4: color.f     (parent=0)
    #  5: render/     (parent=255)
    #  6: surface.f   (parent=5)
    #  7: qoi.f       (parent=5)

    disk_files = [
        ("math",       255, 8, b''),
        ("fp16.f",       0, 1, read_file_bytes(os.path.join(AK_DIR, "math", "fp16.f"))),
        ("fp16-ext.f",   0, 1, read_file_bytes(os.path.join(AK_DIR, "math", "fp16-ext.f"))),
        ("exp.f",        0, 1, read_file_bytes(os.path.join(AK_DIR, "math", "exp.f"))),
        ("color.f",      0, 1, read_file_bytes(os.path.join(AK_DIR, "math", "color.f"))),
        ("render",     255, 8, b''),
        ("surface.f",    5, 1, read_file_bytes(os.path.join(AK_DIR, "render", "surface.f"))),
        ("qoi.f",        5, 1, read_file_bytes(os.path.join(AK_DIR, "render", "qoi.f"))),
    ]

    image = build_disk_image(disk_files)
    _img_path = os.path.join(tempfile.gettempdir(), 'test_qoi.img')
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

    print("[*] Loading qoi.f via REQUIRE ...")
    buf.clear()
    t0 = time.time()

    load_lines = [
        'ENTER-USERLAND',
        'CD render',
        'REQUIRE qoi.f',
        # scratch variables for tests
        'VARIABLE _S   VARIABLE _B   VARIABLE _LEN',
        'VARIABLE _BUF  VARIABLE _S2',
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


# ── QOI validation helpers ──

def parse_qoi_header(data):
    """Parse QOI 14-byte header. Returns dict or None."""
    if len(data) < 14:
        return None
    magic = data[0:4]
    width = struct.unpack('>I', data[4:8])[0]
    height = struct.unpack('>I', data[8:12])[0]
    channels = data[12]
    colorspace = data[13]
    return {
        'magic': magic, 'width': width, 'height': height,
        'channels': channels, 'colorspace': colorspace,
    }

def qoi_decode_python(data):
    """Pure-Python QOI decoder. Returns list of (R,G,B,A) tuples."""
    hdr = parse_qoi_header(data)
    if hdr is None or hdr['magic'] != b'qoif':
        return None, None
    w, h = hdr['width'], hdr['height']
    total = w * h

    index = [(0,0,0,0)] * 64
    r, g, b, a = 0, 0, 0, 255
    pixels = []
    run = 0
    p = 14
    chunks_end = len(data) - 8  # 8-byte end marker

    for _ in range(total):
        if run > 0:
            run -= 1
        elif p < chunks_end:
            b1 = data[p]; p += 1
            if b1 == 0xFE:  # QOI_OP_RGB
                r = data[p]; g = data[p+1]; b = data[p+2]; p += 3
            elif b1 == 0xFF:  # QOI_OP_RGBA
                r = data[p]; g = data[p+1]; b = data[p+2]; a = data[p+3]; p += 4
            elif (b1 & 0xC0) == 0x00:  # QOI_OP_INDEX
                idx = b1 & 0x3F
                r, g, b, a = index[idx]
            elif (b1 & 0xC0) == 0x40:  # QOI_OP_DIFF
                r = (r + ((b1 >> 4) & 0x03) - 2) & 0xFF
                g = (g + ((b1 >> 2) & 0x03) - 2) & 0xFF
                b = (b + (b1 & 0x03) - 2) & 0xFF
            elif (b1 & 0xC0) == 0x80:  # QOI_OP_LUMA
                b2 = data[p]; p += 1
                vg = (b1 & 0x3F) - 32
                r = (r + vg - 8 + ((b2 >> 4) & 0x0F)) & 0xFF
                g = (g + vg) & 0xFF
                b = (b + vg - 8 + (b2 & 0x0F)) & 0xFF
            elif (b1 & 0xC0) == 0xC0:  # QOI_OP_RUN
                run = b1 & 0x3F  # this pixel plus run more

            hash_idx = (r * 3 + g * 5 + b * 7 + a * 11) % 64
            index[hash_idx] = (r, g, b, a)

        pixels.append((r, g, b, a))

    return hdr, pixels


class TestQoiCodec(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        build_snapshot()

    def _encode_and_read(self, w, h, setup_lines):
        """Create w×h surface, run setup, encode to QOI, return (qoi_bytes, length)."""
        lines = [
            f'{w} {h} SURF-CREATE _S !',
        ] + setup_lines + [
            '_S @ _BUF @ 65536 QOI-ENCODE _LEN !',
            '_BUF @ . _LEN @ .',
        ]
        vals, sys_obj = run_forth_values(lines)
        self.assertEqual(len(vals), 2, f"Expected [addr, len], got {vals}")
        buf_addr, length = vals
        self.assertGreater(length, 0, "QOI-ENCODE returned 0 (failure)")
        qoi_data = read_mem(sys_obj, buf_addr, length)
        return qoi_data, length

    # ── QOI-FILE-SIZE ──

    def test_file_size_1x1(self):
        # 1*1*5 + 14 + 8 = 27
        vals, _ = run_forth_values(['1 1 QOI-FILE-SIZE .'])
        self.assertEqual(vals, [27])

    def test_file_size_10x10(self):
        # 10*10*5 + 14 + 8 = 522
        vals, _ = run_forth_values(['10 10 QOI-FILE-SIZE .'])
        self.assertEqual(vals, [522])

    # ── Header ──

    def test_header_magic(self):
        data, _ = self._encode_and_read(2, 2, [
            '_S @ 0xFF0000FF SURF-CLEAR',
        ])
        self.assertEqual(data[0:4], b'qoif')

    def test_header_dimensions(self):
        data, _ = self._encode_and_read(5, 3, [
            '_S @ 0xFF0000FF SURF-CLEAR',
        ])
        hdr = parse_qoi_header(data)
        self.assertEqual(hdr['width'], 5)
        self.assertEqual(hdr['height'], 3)

    def test_header_channels(self):
        data, _ = self._encode_and_read(2, 2, [
            '_S @ 0xFF0000FF SURF-CLEAR',
        ])
        hdr = parse_qoi_header(data)
        self.assertEqual(hdr['channels'], 4)
        self.assertEqual(hdr['colorspace'], 0)

    # ── End marker ──

    def test_end_marker(self):
        data, length = self._encode_and_read(2, 2, [
            '_S @ 0xFF0000FF SURF-CLEAR',
        ])
        # Last 8 bytes should be 0,0,0,0,0,0,0,1
        self.assertEqual(data[-8:], bytes([0,0,0,0,0,0,0,1]))

    # ── Buffer too small ──

    def test_encode_buffer_too_small(self):
        vals, _ = run_forth_values([
            '4 4 SURF-CREATE _S !',
            '_S @ 0xFF0000FF SURF-CLEAR',
            '_S @ _BUF @ 5 QOI-ENCODE .',   # only 5 bytes, way too small
        ])
        self.assertEqual(vals, [0])

    # ── Encode + Python decode ──

    def test_solid_red(self):
        """Encode solid red surface, decode with Python, verify all pixels."""
        data, _ = self._encode_and_read(4, 4, [
            '_S @ 0xFF0000FF SURF-CLEAR',
        ])
        hdr, pixels = qoi_decode_python(data)
        self.assertIsNotNone(hdr)
        self.assertEqual(len(pixels), 16)
        for i, px in enumerate(pixels):
            self.assertEqual(px, (255, 0, 0, 255), f"pixel {i}: {px}")

    def test_solid_green(self):
        data, _ = self._encode_and_read(4, 4, [
            '_S @ 0x00FF00FF SURF-CLEAR',
        ])
        hdr, pixels = qoi_decode_python(data)
        self.assertEqual(len(pixels), 16)
        for i, px in enumerate(pixels):
            self.assertEqual(px, (0, 255, 0, 255), f"pixel {i}: {px}")

    def test_solid_blue(self):
        data, _ = self._encode_and_read(4, 4, [
            '_S @ 0x0000FFFF SURF-CLEAR',
        ])
        hdr, pixels = qoi_decode_python(data)
        self.assertEqual(len(pixels), 16)
        for i, px in enumerate(pixels):
            self.assertEqual(px, (0, 0, 255, 255), f"pixel {i}: {px}")

    def test_compression_run(self):
        """Solid color should compress well — much smaller than worst case."""
        data, length = self._encode_and_read(10, 10, [
            '_S @ 0xFF0000FF SURF-CLEAR',
        ])
        worst = 10 * 10 * 5 + 14 + 8  # 522
        # A run of 100 identical pixels should be tiny
        self.assertLess(length, worst // 2, f"Length {length} not compressed enough")

    def test_two_colors(self):
        """Two distinct colors — first row red, rest green."""
        data, _ = self._encode_and_read(4, 4, [
            '_S @ 0x00FF00FF SURF-CLEAR',   # all green first
            '_S @ 0 0 4 1 0xFF0000FF SURF-FILL-RECT',  # top row red
        ])
        hdr, pixels = qoi_decode_python(data)
        self.assertEqual(len(pixels), 16)
        # Row 0: red
        for i in range(4):
            self.assertEqual(pixels[i], (255, 0, 0, 255), f"row0 px {i}")
        # Rows 1-3: green
        for i in range(4, 16):
            self.assertEqual(pixels[i], (0, 255, 0, 255), f"rest px {i}")

    def test_individual_pixels(self):
        """Write specific colors to individual pixels."""
        data, _ = self._encode_and_read(3, 1, [
            '_S @ 0 0 0xFF0000FF SURF-PIXEL!',  # red at (0,0)
            '_S @ 1 0 0x00FF00FF SURF-PIXEL!',  # green at (1,0)
            '_S @ 2 0 0x0000FFFF SURF-PIXEL!',  # blue at (2,0)
        ])
        hdr, pixels = qoi_decode_python(data)
        self.assertEqual(len(pixels), 3)
        self.assertEqual(pixels[0], (255, 0, 0, 255))
        self.assertEqual(pixels[1], (0, 255, 0, 255))
        self.assertEqual(pixels[2], (0, 0, 255, 255))

    def test_transparent_pixel(self):
        """Pixel with alpha=0 should roundtrip."""
        data, _ = self._encode_and_read(2, 1, [
            '_S @ 0xFF000080 SURF-PIXEL!',     # semi-transparent at (0,0) — default is already (0,0) so set (0,0)  
            '_S @ 0 0 0xFF000080 SURF-PIXEL!',
            '_S @ 1 0 0x00FF0000 SURF-PIXEL!',  # fully transparent green
        ])
        hdr, pixels = qoi_decode_python(data)
        self.assertEqual(len(pixels), 2)
        self.assertEqual(pixels[0], (255, 0, 0, 128))
        self.assertEqual(pixels[1], (0, 255, 0, 0))

    # ── Roundtrip: encode then decode in Forth ──

    def test_roundtrip_solid(self):
        """Encode a solid color surface, decode it, verify pixel matches."""
        vals, sys_obj = run_forth_values([
            '4 4 SURF-CREATE _S !',
            '_S @ 0xAABBCCDD SURF-CLEAR',
            '_S @ _BUF @ 65536 QOI-ENCODE _LEN !',
            '_BUF @ _LEN @ QOI-DECODE _S2 !',
            '_S2 @ SURF-W .',
            '_S2 @ SURF-H .',
            '_S2 @ 0 0 SURF-PIXEL@ .',
            '_S2 @ 3 3 SURF-PIXEL@ .',
        ])
        self.assertEqual(len(vals), 4, f"Expected 4 vals, got {vals}")
        w, h, px00, px33 = vals
        self.assertEqual(w, 4)
        self.assertEqual(h, 4)
        self.assertEqual(px00, 0xAABBCCDD)
        self.assertEqual(px33, 0xAABBCCDD)

    def test_roundtrip_two_colors(self):
        """Roundtrip with two distinct colors."""
        vals, sys_obj = run_forth_values([
            '4 2 SURF-CREATE _S !',
            '_S @ 0x00FF00FF SURF-CLEAR',
            '_S @ 0 0 4 1 0xFF0000FF SURF-FILL-RECT',
            '_S @ _BUF @ 65536 QOI-ENCODE _LEN !',
            '_BUF @ _LEN @ QOI-DECODE _S2 !',
            '_S2 @ 0 0 SURF-PIXEL@ .',   # should be red
            '_S2 @ 0 1 SURF-PIXEL@ .',   # should be green
        ])
        self.assertEqual(len(vals), 2, f"Expected 2 vals, got {vals}")
        self.assertEqual(vals[0], 0xFF0000FF, f"Expected red, got {vals[0]:#010x}")
        self.assertEqual(vals[1], 0x00FF00FF, f"Expected green, got {vals[1]:#010x}")

    def test_roundtrip_gradient(self):
        """Roundtrip 8 pixels with slightly varying colors (DIFF/LUMA paths)."""
        setup = []
        for i in range(8):
            r = 100 + i * 10
            g = 50 + i * 5
            b = 200 - i * 3
            rgba = (r << 24) | (g << 16) | (b << 8) | 0xFF
            setup.append(f'_S @ {i} 0 0x{rgba:08X} SURF-PIXEL!')
        # Encode, decode, read back
        lines = [
            '8 1 SURF-CREATE _S !',
        ] + setup + [
            '_S @ _BUF @ 65536 QOI-ENCODE _LEN !',
            '_BUF @ _LEN @ QOI-DECODE _S2 !',
        ]
        # Check first and last pixel
        lines += [
            '_S2 @ 0 0 SURF-PIXEL@ .',
            '_S2 @ 7 0 SURF-PIXEL@ .',
        ]
        vals, _ = run_forth_values(lines)
        self.assertEqual(len(vals), 2)
        # pixel 0: r=100 g=50 b=200 a=255
        expected0 = (100 << 24) | (50 << 16) | (200 << 8) | 255
        # pixel 7: r=170 g=85 b=179 a=255
        expected7 = (170 << 24) | (85 << 16) | (179 << 8) | 255
        self.assertEqual(vals[0], expected0, f"px0: got {vals[0]:#010x}")
        self.assertEqual(vals[1], expected7, f"px7: got {vals[1]:#010x}")

    def test_1x1_roundtrip(self):
        """Edge case: 1×1 surface roundtrip."""
        vals, _ = run_forth_values([
            '1 1 SURF-CREATE _S !',
            '_S @ 0 0 0xDEADBEEF SURF-PIXEL!',
            '_S @ _BUF @ 65536 QOI-ENCODE _LEN !',
            '_LEN @ .',
            '_BUF @ _LEN @ QOI-DECODE _S2 !',
            '_S2 @ 0 0 SURF-PIXEL@ .',
        ])
        self.assertEqual(len(vals), 2)
        length, pixel = vals
        self.assertGreater(length, 14 + 8)   # at least header + end
        self.assertEqual(pixel, 0xDEADBEEF)


if __name__ == '__main__':
    unittest.main()
