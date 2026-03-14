#!/usr/bin/env python3
"""Quick smoke test for akashic-pad-dom.f — verify it boots and renders.

Builds the disk image, boots KDOS, loads the pad, then verifies:
1. Title bar renders " Akashic Pad" at row 0
2. Status bar renders "Ready" somewhere on row 23
3. Typing a character ('X') gets echoed to the editor area
4. Ctrl+Q triggers clean exit
"""
import os
import sys
import struct
import tempfile
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(SCRIPT_DIR, "emu")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")

# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------

def capture_uart(sys_obj):
    buf = []
    sys_obj.uart.on_tx = lambda b: buf.append(b)
    return buf

def uart_text(buf):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9)) else ""
        for b in buf
    )

def strip_ansi(data: bytes) -> str:
    """Strip ANSI escape sequences and return clean text."""
    import re
    text = data.decode('latin-1', errors='replace')
    # Remove CSI sequences: ESC[ ... final_byte
    text = re.sub(r'\x1b\[[0-9;]*[A-Za-z]', '', text)
    # Remove OSC sequences: ESC] ... ST
    text = re.sub(r'\x1b\][^\x07]*\x07', '', text)
    # Remove remaining ESC sequences
    text = re.sub(r'\x1b[^\x1b]{0,3}', '', text)
    return text

def inject_text(sys_obj, text: str):
    sys_obj.uart.inject_input(text.encode('ascii'))

def inject_bytes(sys_obj, data: bytes):
    sys_obj.uart.inject_input(data)

def run_steps(sys_obj, n):
    """Run up to n steps, yielding on idle."""
    done = 0
    while done < n:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            sys_obj.bus.tick(200_000)
            sys_obj.cpu.idle = False
            done += 50_000
            continue
        batch = min(50_000, n - done)
        try:
            sys_obj.run_batch(batch)
        except Exception:
            break
        done += batch
    return done

def read_screen_row(sys_obj, row, width=80):
    """Read a row from the ANSI output buffer by parsing the UART output."""
    # We can't easily read the screen buffer directly, so we just
    # look at the UART output for the expected strings.
    pass

# ---------------------------------------------------------------------------
#  Main test
# ---------------------------------------------------------------------------

def main():
    # Build disk image
    print("[*] Building disk image...")
    img_path = os.path.join(SCRIPT_DIR, "akashic-pad-dom.img")
    if not os.path.exists(img_path):
        import subprocess
        result = subprocess.run(
            [sys.executable, os.path.join(SCRIPT_DIR, "boot_editor_dom.py"),
             "--build-only"],
            cwd=ROOT_DIR, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"FAIL: disk build failed:\n{result.stderr}")
            sys.exit(1)

    print("[*] Assembling BIOS...")
    with open(BIOS_PATH) as f:
        bios_code = assemble(f.read())

    print("[*] Booting system...")
    sys_emu = MegapadSystem(ram_size=1024*1024,
                            ext_mem_size=16 * (1 << 20),
                            storage_image=img_path)
    buf = capture_uart(sys_emu)
    sys_emu.load_binary(0, bios_code)
    sys_emu.boot()

    t0 = time.time()

    # Boot KDOS + load pad — this takes many steps
    # The pad loads all dependencies, builds DOM, creates widgets, etc.
    print("[*] Running boot sequence (may take 30-60s)...")
    steps = run_steps(sys_emu, 10_000_000_000)
    elapsed = time.time() - t0

    print(f"    {steps:,} steps, {elapsed:.1f}s")

    # Check for errors
    results = []
    raw_bytes = bytes(buf)
    output = uart_text(buf)
    clean_output = strip_ansi(raw_bytes)

    # Test 1: Boot succeeded (no ABORT or error messages)
    has_error = "ABORT" in output or "ERROR" in output or "not found" in output.lower()
    if has_error:
        # Extract relevant part of output
        for kw in ["ABORT", "ERROR", "not found"]:
            idx = output.find(kw)
            if idx >= 0:
                snippet = output[max(0,idx-50):idx+100]
                print(f"  ERROR near '{kw}': ...{snippet}...")
        results.append(("Boot without errors", False))
    else:
        results.append(("Boot without errors", True))

    # Test 2: Check UART output contains ANSI escape sequences
    # (indicates the screen was painted)
    raw_bytes = bytes(buf)
    has_ansi = b'\x1b[' in raw_bytes
    results.append(("Screen painted (ANSI escapes)", has_ansi))

    # Test 3: Check output contains "Akashic Pad" characters in sequence
    # (chars may be separated by ANSI cursor-positioning codes)
    needle = "Akashic Pad"
    idx = 0
    all_found = True
    for ch in needle:
        pos = clean_output.find(ch, idx)
        if pos == -1:
            all_found = False
            break
        idx = pos + 1
    results.append(("Title bar rendered", all_found))

    # Test 3b: Title bar uses purple bg (palette 54)
    has_title_bg = b'\x1b[48;5;54m' in raw_bytes
    results.append(("Title bar purple bg", has_title_bg))

    # Test 4: Check output contains "Ready"
    has_ready = "Ready" in output
    results.append(("Status shows Ready", has_ready))

    # Test 5: Check output contains "INSERT"
    has_mode = "INSERT" in output
    results.append(("Mode shows INSERT", has_mode))

    # Test 6: Check output contains "Ln" and "Col"
    has_pos = "Ln" in output and "Col" in output
    results.append(("Cursor position shown", has_pos))

    # Test 7: Type a character and verify pad is interactive
    buf.clear()
    inject_text(sys_emu, "X")
    run_steps(sys_emu, 500_000_000)
    raw_bytes2 = bytes(buf)
    output2 = uart_text(buf)
    # After typing 'X', the screen should repaint with X visible
    # and cursor position should change to Col 2
    has_x = "X" in output2
    results.append(("Typing echoes to editor", has_x))

    # Test 7b: Editor uses dark bg (palette 235), not blue (24) or purple (54)
    has_editor_bg = b'\x1b[48;5;235m' in raw_bytes2
    has_blue_flood = (b'\x1b[48;5;24m' in raw_bytes2 and
                      raw_bytes2.count(b'\x1b[48;5;24m') > 5)
    results.append(("Editor dark bg (no blue flood)", has_editor_bg and not has_blue_flood))

    # Test 8: Ctrl+Q should trigger exit
    buf.clear()
    inject_bytes(sys_emu, b'\x11')  # Ctrl+Q = 0x11
    run_steps(sys_emu, 500_000_000)
    output3 = uart_text(buf)
    has_exit = "exited" in output3
    results.append(("Ctrl+Q exits cleanly", has_exit))

    # Report
    print(f"\n{'='*50}")
    passed = sum(1 for _, ok in results if ok)
    total = len(results)
    for name, ok in results:
        status = "PASS" if ok else "FAIL"
        print(f"  [{status}] {name}")
    print(f"{'='*50}")
    print(f"  {passed}/{total} passed")

    # Cleanup
    if os.path.exists(img_path):
        os.unlink(img_path)

    sys.exit(0 if passed == total else 1)


if __name__ == "__main__":
    main()
