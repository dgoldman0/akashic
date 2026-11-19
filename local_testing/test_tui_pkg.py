#!/usr/bin/env python3
"""Tests for tui/app-image.f: an applet image saved to an MP64FS file and
loaded back, on one system booted with a disk.

The manifest reader (tui/app-manifest.f) has contracts of its own in the
manifest-contracts profile, which local_testing/test_manifest_contracts.py
runs as a test.
"""
import os
import sys
import struct
import time
import tempfile
import re

# ──────── paths ────────
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.environ.get(
    "MEGAPAD_ROOT", os.path.abspath(os.path.join(ROOT_DIR, "..", "megapad"))
)
AK         = os.path.join(ROOT_DIR, "akashic")

sys.path.insert(0, EMU_DIR)

from asm import assemble
from system import MegapadSystem
from forth_snapshot import failure_message, run_file_tests, transcript_checks, module_source_lines

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")
SECTOR = 512

# ═══════════════════════════════════════════════════════════════════
#  Dependency lists
# ═══════════════════════════════════════════════════════════════════

# App-image tests load these modules with their REQUIRE closure.
_IMG_ROOTS = (
    "text/utf8.f",
    "utils/string.f",
    "utils/toml.f",
    "tui/ansi.f",
    "tui/keys.f",
    "tui/cell.f",
    "tui/screen.f",
    "tui/draw.f",
    "tui/box.f",
    "tui/region.f",
    "tui/layout.f",
    "tui/widget.f",
    "tui/focus.f",
    "utils/term.f",
    "tui/event.f",
    "tui/app.f",
    "utils/uint-range.f",
    "utils/binimg.f",
    "tui/app-image.f",
    "tui/app-manifest.f",
)

# ═══════════════════════════════════════════════════════════════════
#  Emulator helpers (shared)
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
            if s.startswith('REQUIRE ') or s.startswith('PROVIDED '):
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
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9, 27)) else ""
        for b in buf
    )

def feed_and_run(sys_obj, data, max_steps=400_000_000):
    """Feed Forth source and run until idle.  Returns step count."""
    if isinstance(data, str):
        data = data.encode()
    pos = 0; steps = 0
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

# ═══════════════════════════════════════════════════════════════════
#  Disk builder (for app-image tests)
# ═══════════════════════════════════════════════════════════════════

def make_entry(name, start_sec, sec_count, used_bytes, ftype, parent):
    e = bytearray(48)
    name_b = name.encode('ascii')[:24]
    e[:len(name_b)] = name_b
    struct.pack_into('<HH', e, 24, start_sec, sec_count)
    struct.pack_into('<I', e, 28, used_bytes)
    e[32] = ftype; e[33] = 0; e[34] = parent
    return bytes(e)

def build_disk_image(files):
    data_start = 14; entries = []; data_sectors = []; next_sec = data_start
    for name, parent, ftype, content in files:
        if ftype == 8:
            entries.append(make_entry(name, 0, 0, 0, 8, parent))
        else:
            cb = content if isinstance(content, bytes) else content.encode('ascii')
            n_sec = max((len(cb) + SECTOR - 1) // SECTOR, 1)
            entries.append(make_entry(name, next_sec, n_sec, len(cb), 1, parent))
            padded = cb + b'\x00' * (n_sec * SECTOR - len(cb))
            data_sectors.append((next_sec, padded))
            next_sec += n_sec
    sb = bytearray(SECTOR)
    sb[0:4] = b'MP64'; struct.pack_into('<H', sb, 4, 1)
    struct.pack_into('<I', sb, 6, 2048)
    struct.pack_into('<H', sb, 10, 1); struct.pack_into('<H', sb, 12, 1)
    struct.pack_into('<H', sb, 14, 2); struct.pack_into('<H', sb, 16, 12)
    struct.pack_into('<H', sb, 18, data_start); sb[20] = 128; sb[21] = 48
    bmap = bytearray(SECTOR)
    for s in range(data_start):
        bmap[s // 8] |= (1 << (s % 8))
    for ss, p in data_sectors:
        for s in range(ss, ss + len(p) // SECTOR):
            bmap[s // 8] |= (1 << (s % 8))
    dir_data = bytearray(12 * SECTOR)
    for i, e in enumerate(entries):
        dir_data[i * 48 : i * 48 + 48] = e
    total = max(next_sec, 2048)
    image = bytearray(total * SECTOR)
    image[0:SECTOR] = sb
    image[SECTOR : 2 * SECTOR] = bmap
    image[2 * SECTOR : 14 * SECTOR] = dir_data
    for ss, p in data_sectors:
        image[ss * SECTOR : ss * SECTOR + len(p)] = p
    return image


# ═══════════════════════════════════════════════════════════════════
#  Section G: App-image — Disk-based tests
# ═══════════════════════════════════════════════════════════════════

def test_app_image_save_and_load():
    """App-image tests using a real filesystem.

    One system boots with a disk image holding two pre-allocated .m64 file
    slots, and every step runs on it: G3 loads the image G2 saved, and G7
    the one G6 saved.
    """
    # Build disk with empty file slots for saving images
    out_sectors = 32  # 16KB per slot
    files = [
        ("test1.m64", 255, 1, b'\x00' * (out_sectors * SECTOR)),
        ("test2.m64", 255, 1, b'\x00' * (out_sectors * SECTOR)),
    ]
    disk_img = build_disk_image(files)
    img_path = os.path.join(tempfile.gettempdir(), 'test_appi.img')
    with open(img_path, 'wb') as f:
        f.write(disk_img)

    try:
        # Boot BIOS + KDOS
        print("  [*] Booting BIOS + KDOS with disk ...")
        t0 = time.time()
        bios_code = _load_bios()
        sys_obj = MegapadSystem(ram_size=2 * 1024 * 1024,
                                storage_image=img_path,
                                ext_mem_size=16 * 1024 * 1024)
        buf = capture_uart(sys_obj)
        sys_obj.load_binary(0, bios_code)
        sys_obj.boot()

        kdos_payload = "\n".join(_load_forth_lines(KDOS_PATH)) + "\n"
        steps = feed_and_run(sys_obj, kdos_payload, max_steps=800_000_000)
        print(f"  [*] KDOS booted. {steps:,} steps in {time.time()-t0:.1f}s")

        # Load deps (everything through app-image.f + app-manifest.f)
        buf.clear()
        dep_lines = module_source_lines(_IMG_ROOTS)

        dep_payload = "\n".join(["ENTER-USERLAND"] + dep_lines) + "\n"
        steps = feed_and_run(sys_obj, dep_payload, max_steps=400_000_000)
        text = uart_text(buf)
        errs = [l for l in text.split('\n')
                if '?' in l and ('not found' in l.lower() or 'undefined' in l.lower())]
        print(f"  [*] All deps loaded. {steps:,} steps")

        # G1: Both files compile clean
        assert not errs, failure_message(
            "G1-compile-clean", "compile errors: " + " | ".join(errs[-20:]), text
        )

        def run_on_disk(forth_lines, max_steps):
            buf.clear()
            feed_and_run(sys_obj, "\n".join(forth_lines) + "\n",
                         max_steps=max_steps)
            return re.sub(r'\x1b\[[0-9;]*[a-zA-Z?]', '', uart_text(buf))

        check_img, _, _ = transcript_checks(run_on_disk)

        # G2: APPI-MARK + APPI-ENTRY + APPI-SAVE round-trip
        check_img("G2-save-returns-zero", [
            'APPI-MARK',
            ': MY-TEST-APP  77 . CR ;',
            "' MY-TEST-APP APPI-ENTRY",
            'APPI-SAVE test1.m64',
            '." R=" . CR',
        ], expected="R=0", max_steps=200_000_000)

        # G3: APPI-LOAD returns xt + 0
        check_img("G3-load-exec-77", [
            'APPI-LOAD test1.m64',
            '." R=" . CR',          # print ior (should be 0)
            'EXECUTE',              # execute the loaded xt — should print 77
        ], check_fn=lambda t: "R=0" in t and "77" in t, max_steps=200_000_000)

        # G4: _APPI-ERR-LOAD constant exists
        check_img("G4-err-load-constant", [
            '_APPI-ERR-LOAD ." R=" . CR',
        ], expected="R=-100", max_steps=50_000_000)

        # G5: APPI-MARK is callable (doesn't crash)
        check_img("G5-mark-callable", [
            'APPI-MARK ." R=OK" CR',
        ], expected="R=OK", max_steps=50_000_000)

        # G6: Save a second app, load it
        check_img("G6-save-second-app", [
            'APPI-MARK',
            ': APP2  42 . CR ;',
            "' APP2 APPI-ENTRY",
            'APPI-SAVE test2.m64',
            '." R=" . CR',
        ], expected="R=0", max_steps=200_000_000)

        check_img("G7-load-second-app-42", [
            'APPI-LOAD test2.m64',
            '." R=" . CR',
            'EXECUTE',
        ], check_fn=lambda t: "R=0" in t and "42" in t, max_steps=200_000_000)

    finally:
        if os.path.exists(img_path):
            os.unlink(img_path)


if __name__ == "__main__":
    run_file_tests(__file__)
