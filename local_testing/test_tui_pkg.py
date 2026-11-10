#!/usr/bin/env python3
"""Combined test suite for tui/app-image.f and tui/app-manifest.f.

Two test sections with different setups:
  Sections A–F (manifest):  Snapshot-based, no disk required.
  Section G    (app-image): Disk-based, sequential on one system.
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

# Manifest tests load these modules with their REQUIRE closure.
_MFT_ROOTS = (
    "text/utf8.f",
    "utils/string.f",
    "utils/toml.f",
    "tui/app-manifest.f",
)

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

def uart_text_clean(buf):
    """Return text with ANSI escapes stripped."""
    raw = uart_text(buf)
    return re.sub(r'\x1b\[[0-9;]*[a-zA-Z?]', '', raw)

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
#  Manifest snapshot (no disk)
# ═══════════════════════════════════════════════════════════════════

_mft_snapshot = None

def build_mft_snapshot():
    global _mft_snapshot
    if _mft_snapshot is not None:
        return _mft_snapshot

    print("[*] Building manifest snapshot: BIOS + KDOS + utf8 + string + toml + app-manifest ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)

    dep_lines = module_source_lines(_MFT_ROOTS)

    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = kdos_lines + ["ENTER-USERLAND"] + dep_lines
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode()
    pos = 0; steps = 0; max_steps = 800_000_000

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

    text = uart_text(buf)
    err_lines = [l for l in text.strip().split('\n')
                 if '?' in l and ('not found' in l.lower() or 'undefined' in l.lower())]
    if err_lines:
        print("[!] Possible compilation errors:")
        for ln in err_lines[-20:]:
            print(f"    {ln}")

    _mft_snapshot = (bios_code, bytes(sys_obj.cpu.mem),
                     save_cpu_state(sys_obj.cpu),
                     bytes(sys_obj._ext_mem))
    elapsed = time.time() - t0
    print(f"[*] Manifest snapshot ready.  {steps:,} steps in {elapsed:.1f}s")
    return _mft_snapshot


def run_mft_forth(lines, max_steps=80_000_000):
    """Run Forth lines from the manifest snapshot, return UART text (ANSI-stripped)."""
    if _mft_snapshot is None:
        build_mft_snapshot()
    bios_code, mem_bytes, cpu_state, ext_mem_bytes = _mft_snapshot
    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
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
    data = payload.encode()
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

    raw = uart_text(buf)
    return re.sub(r'\x1b\[[0-9;]*[a-zA-Z?]', '', raw)


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
#  Test framework
# ═══════════════════════════════════════════════════════════════════

# The checks read only what the program printed, and fail their test when
# a check fails or KDOS reports a failed line
# (forth_snapshot.transcript_checks).

check, _, _ = transcript_checks(run_mft_forth)


# ═══════════════════════════════════════════════════════════════════
#  Helper: create a TOML manifest in Forth memory
# ═══════════════════════════════════════════════════════════════════

# We use a CREATE buffer to hold the TOML text, then pass addr+len
# to MFT-PARSE.  Each Forth line writes one byte at a time using C,.
# To avoid that verbosity we store the string from a counted-string
# approach:  CREATE BUF  <chars> ,  then pass BUF <len> to MFT-PARSE.
#
# Simplest: build a helper word _MKBUF that stores a TOML string into
# memory and leaves (addr len) on the stack.

def toml_in_forth(toml_str):
    r"""Return Forth lines that leave (addr len) of the TOML string on the stack.
    Uses HERE + raw byte storage via C, — then adjust HERE back."""
    forth_lines = []
    # Store the string at HERE, byte by byte
    forth_lines.append("HERE")  # addr on stack
    for ch in toml_str:
        b = ord(ch)
        forth_lines.append(f"{b} C,")
    forth_lines.append(f"HERE OVER -")  # ( addr len )
    return forth_lines


# ═══════════════════════════════════════════════════════════════════
#  Section A: Manifest — Compilation
# ═══════════════════════════════════════════════════════════════════

def test_manifest_compilation():
    check("A1-compile-clean",
          ['." R=MFTOK "'],
          expected="R=MFTOK")

    check("A2-mft-size-constant",
          ['_MFT-SIZE ." R=" . CR'],
          expected="R=96")

    check("A3-error-constants",
          ['MFT-E-NO-APP . ."  " MFT-E-NO-NAME . ."  " MFT-E-NO-ENTRY . CR'],
          expected="-110")


# ═══════════════════════════════════════════════════════════════════
#  Section B: Manifest — Basic parse
# ═══════════════════════════════════════════════════════════════════

SAMPLE_TOML = """\
[app]
name = "test-app"
title = "Test Application"
version = "1.2.3"
width = 80
height = 24
entry = "test-main"

[deps]
uidl = true
css = false
"""

def test_manifest_basic_parse():
    setup = toml_in_forth(SAMPLE_TOML)

    # B1: MFT-PARSE returns non-zero
    check("B1-parse-returns-mft",
          setup + ['MFT-PARSE ." R=" DUP 0<> IF ." Y" ELSE ." N" THEN CR'],
          expected="R=Y")

    # B2: MFT-NAME
    check("B2-name",
          setup + [
              'MFT-PARSE',
              'DUP MFT-NAME ." R=" TYPE CR',
          ],
          expected="R=test-app")

    # B3: MFT-TITLE
    check("B3-title",
          setup + [
              'MFT-PARSE',
              'DUP MFT-TITLE ." R=" TYPE CR',
          ],
          expected="R=Test Application")

    # B4: MFT-VERSION
    check("B4-version",
          setup + [
              'MFT-PARSE',
              'DUP MFT-VERSION ." R=" TYPE CR',
          ],
          expected="R=1.2.3")

    # B5: MFT-ENTRY
    check("B5-entry",
          setup + [
              'MFT-PARSE',
              'DUP MFT-ENTRY ." R=" TYPE CR',
          ],
          expected="R=test-main")

    # B6: MFT-WIDTH
    check("B6-width",
          setup + [
              'MFT-PARSE',
              'DUP MFT-WIDTH ." R=" . CR',
          ],
          expected="R=80")

    # B7: MFT-HEIGHT
    check("B7-height",
          setup + [
              'MFT-PARSE',
              'DUP MFT-HEIGHT ." R=" . CR',
          ],
          expected="R=24")


# ═══════════════════════════════════════════════════════════════════
#  Section C: Manifest — Optional field defaults
# ═══════════════════════════════════════════════════════════════════

MINIMAL_TOML = """\
[app]
name = "minimal"
entry = "go"
"""

def test_manifest_optional_defaults():
    setup = toml_in_forth(MINIMAL_TOML)

    # C1: title defaults to name
    check("C1-title-defaults-to-name",
          setup + [
              'MFT-PARSE',
              'DUP MFT-TITLE ." R=" TYPE CR',
          ],
          expected="R=minimal")

    # C2: version defaults to empty (0 0)
    check("C2-version-default-empty",
          setup + [
              'MFT-PARSE',
              'DUP MFT-VERSION NIP ." R=" . CR',
          ],
          expected="R=0")

    # C3: width defaults to 0
    check("C3-width-default-zero",
          setup + [
              'MFT-PARSE',
              'DUP MFT-WIDTH ." R=" . CR',
          ],
          expected="R=0")

    # C4: height defaults to 0
    check("C4-height-default-zero",
          setup + [
              'MFT-PARSE',
              'DUP MFT-HEIGHT ." R=" . CR',
          ],
          expected="R=0")


# ═══════════════════════════════════════════════════════════════════
#  Section D: Manifest — Dependency checks
# ═══════════════════════════════════════════════════════════════════

def test_manifest_dependency_checks():
    setup = toml_in_forth(SAMPLE_TOML)

    # D1: dep present and true
    check("D1-dep-uidl-true",
          setup + [
              'MFT-PARSE',
              'DUP S" uidl" MFT-DEP? ." R=" IF ." Y" ELSE ." N" THEN CR',
          ],
          expected="R=Y")

    # D2: dep present and false
    check("D2-dep-css-false",
          setup + [
              'MFT-PARSE',
              'DUP S" css" MFT-DEP? ." R=" IF ." Y" ELSE ." N" THEN CR',
          ],
          expected="R=N")

    # D3: dep not present
    check("D3-dep-missing-key",
          setup + [
              'MFT-PARSE',
              'DUP S" audio" MFT-DEP? ." R=" IF ." Y" ELSE ." N" THEN CR',
          ],
          expected="R=N")

    # D4: no [deps] section at all
    setup_no_deps = toml_in_forth(MINIMAL_TOML)
    check("D4-no-deps-section",
          setup_no_deps + [
              'MFT-PARSE',
              'DUP S" uidl" MFT-DEP? ." R=" IF ." Y" ELSE ." N" THEN CR',
          ],
          expected="R=N")


# ═══════════════════════════════════════════════════════════════════
#  Section E: Manifest — Error cases
# ═══════════════════════════════════════════════════════════════════

def test_manifest_error_cases():
    # E1: missing [app] section
    no_app = toml_in_forth("[other]\nfoo = 1\n")
    check("E1-no-app-section",
          no_app + ['MFT-PARSE ." R=" . CR'],
          expected="R=0")

    # E2: missing name key
    no_name = toml_in_forth("[app]\nentry = \"go\"\n")
    check("E2-no-name-key",
          no_name + ['MFT-PARSE ." R=" . CR'],
          expected="R=0")

    # E3: missing entry key
    no_entry = toml_in_forth("[app]\nname = \"x\"\n")
    check("E3-no-entry-key",
          no_entry + ['MFT-PARSE ." R=" . CR'],
          expected="R=0")

    # E4: empty string returns 0
    check("E4-empty-string",
          ['0 0 MFT-PARSE ." R=" . CR'],
          expected="R=0")


# ═══════════════════════════════════════════════════════════════════
#  Section F: Manifest — MFT-FREE
# ═══════════════════════════════════════════════════════════════════

def test_manifest_free():
    setup = toml_in_forth(SAMPLE_TOML)

    # F1: MFT-FREE reclaims when at top of HERE
    check("F1-free-reclaims",
          setup + [
              'MFT-PARSE',
              'HERE >R',
              'MFT-FREE',
              'HERE R> = ." R=" IF ." N" ELSE ." Y" THEN CR',
          ],
          expected="R=Y")

    # F2: Extra unknown keys are ignored
    extra_toml = toml_in_forth('[app]\nname = "x"\nentry = "e"\nextra = 42\nfoo = "bar"\n')
    check("F2-unknown-keys-ignored",
          extra_toml + [
              'MFT-PARSE DUP MFT-NAME ." R=" TYPE CR',
          ],
          expected="R=x")


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
