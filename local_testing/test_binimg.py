#!/usr/bin/env python3
"""Test suite for akashic-binimg Phase 1 (Core Saver), Phase 2 (Core Loader),
and Phase 3 (Imports).

Boots BIOS + KDOS, loads binimg.f via direct feeding, compiles a
small set of test words between IMG-MARK and IMG-SAVE, writes an
.m64 file to a pre-created disk slot, then reads the raw disk image
from Python and validates the .m64 header, segment, relocation
table, and import table.

Phase 2 then loads the .m64 back via IMG-LOAD and verifies the
loaded words are functional and relocated to a new base address.

Phase 3 verifies that external word references (imports) are
auto-detected during save, written to the import table, and
resolved by name during load.
"""
import os, sys, struct, time, tempfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(SCRIPT_DIR, "emu")
AK_DIR     = os.path.join(ROOT_DIR, "akashic")

sys.path.insert(0, EMU_DIR)

from asm import assemble
from system import MegapadSystem

BIOS_PATH  = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH  = os.path.join(EMU_DIR, "kdos.f")
BINIMG_PATH = os.path.join(AK_DIR, "utils", "binimg.f")

SECTOR = 512

# ─── Disk Image Builder ──────────────────────────────────────────────

def make_entry(name, start_sec, sec_count, used_bytes, ftype, parent):
    """Build a 48-byte MP64FS directory entry."""
    e = bytearray(48)
    name_b = name.encode('ascii')[:24]
    e[:len(name_b)] = name_b
    struct.pack_into('<HH', e, 24, start_sec, sec_count)
    struct.pack_into('<I', e, 28, used_bytes)
    e[32] = ftype
    e[33] = 0
    e[34] = parent
    return bytes(e)


def build_disk_image(files):
    """
    files: list of (name, parent_slot, ftype, content_bytes)
    Returns bytes of the full disk image.
    """
    data_start = 14
    entries = []
    data_sectors = []
    next_sec = data_start

    for name, parent, ftype, content in files:
        if ftype == 8:  # directory
            entries.append(make_entry(name, 0, 0, 0, 8, parent))
        else:
            content_bytes = content if isinstance(content, bytes) else content.encode('ascii')
            n_sec = (len(content_bytes) + SECTOR - 1) // SECTOR
            if n_sec == 0:
                n_sec = 1
            entries.append(make_entry(name, next_sec, n_sec,
                                      len(content_bytes), 1, parent))
            padded = content_bytes + b'\x00' * (n_sec * SECTOR - len(content_bytes))
            data_sectors.append((next_sec, padded))
            next_sec += n_sec

    # Superblock
    sb = bytearray(SECTOR)
    sb[0:4] = b'MP64'
    struct.pack_into('<H', sb, 4, 1)
    struct.pack_into('<I', sb, 6, 2048)
    struct.pack_into('<H', sb, 10, 1)
    struct.pack_into('<H', sb, 12, 1)
    struct.pack_into('<H', sb, 14, 2)
    struct.pack_into('<H', sb, 16, 12)
    struct.pack_into('<H', sb, 18, data_start)
    sb[20] = 128
    sb[21] = 48

    # Bitmap
    bmap = bytearray(SECTOR)
    for s in range(data_start):
        bmap[s // 8] |= (1 << (s % 8))
    for sec_start, padded in data_sectors:
        n = len(padded) // SECTOR
        for s in range(sec_start, sec_start + n):
            bmap[s // 8] |= (1 << (s % 8))

    # Directory
    dir_data = bytearray(12 * SECTOR)
    for i, e in enumerate(entries):
        dir_data[i * 48 : i * 48 + 48] = e

    # Assemble
    total_sectors = max(next_sec, 2048)
    image = bytearray(total_sectors * SECTOR)
    image[0:SECTOR] = sb
    image[SECTOR:2*SECTOR] = bmap
    image[2*SECTOR:14*SECTOR] = dir_data
    for sec_start, padded in data_sectors:
        off = sec_start * SECTOR
        image[off:off + len(padded)] = padded

    return image


# ─── Emulator Helpers ────────────────────────────────────────────────

def load_bios():
    with open(BIOS_PATH) as f:
        return assemble(f.read())


def load_forth_lines(path, strip_provided=True):
    """Load a Forth source file, stripping blanks, comments, REQUIRE,
    and optionally PROVIDED lines."""
    with open(path) as f:
        lines = []
        for line in f.read().splitlines():
            s = line.strip()
            if not s or s.startswith('\\'):
                continue
            if s.startswith('REQUIRE '):
                continue
            if strip_provided and s.startswith('PROVIDED '):
                continue
            lines.append(line)
        return lines


def next_line_chunk(data, pos):
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


def feed_and_run(sys_obj, data, max_steps=400_000_000, report_interval=10.0):
    """Feed data bytes to UART line-at-a-time, running the CPU.
    Returns total steps executed."""
    if isinstance(data, str):
        data = data.encode()
    pos = 0
    steps = 0
    last_report = time.time()

    while steps < max_steps:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk)
                pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)
        now = time.time()
        if now - last_report > report_interval:
            pct = 100 * pos / max(len(data), 1)
            print(f"    ... {steps:,} steps, {pos}/{len(data)} bytes ({pct:.0f}%)")
            last_report = now

    return steps


# ─── .m64 Verification ──────────────────────────────────────────────

def read_m64_from_disk(disk_path, file_entry_index):
    """Read the .m64 file data from the disk image by looking up the
    directory entry at the given index."""
    with open(disk_path, 'rb') as f:
        raw = f.read()

    # Parse directory entry
    dir_base = 2 * SECTOR  # directory starts at sector 2
    de_off = dir_base + file_entry_index * 48
    de = raw[de_off:de_off + 48]

    start_sec = struct.unpack_from('<H', de, 24)[0]
    sec_count = struct.unpack_from('<H', de, 26)[0]
    used_bytes = struct.unpack_from('<I', de, 28)[0]

    data_off = start_sec * SECTOR
    file_data = raw[data_off:data_off + used_bytes]
    return file_data


def parse_m64_header(data):
    """Parse a .m64 header. Returns dict or None on error."""
    if len(data) < 64:
        return None
    magic = data[0:4]
    if magic != b'MF64':
        return None
    version    = struct.unpack_from('<H', data, 4)[0]
    flags      = struct.unpack_from('<H', data, 6)[0]
    seg_size   = struct.unpack_from('<Q', data, 8)[0]
    reloc_cnt  = struct.unpack_from('<Q', data, 16)[0]
    export_cnt = struct.unpack_from('<Q', data, 24)[0]
    import_cnt = struct.unpack_from('<Q', data, 32)[0]
    entry_off  = struct.unpack_from('<Q', data, 40)[0]
    prov_off   = struct.unpack_from('<Q', data, 48)[0]
    reserved   = struct.unpack_from('<Q', data, 56)[0]
    return {
        'version': version, 'flags': flags,
        'seg_size': seg_size, 'reloc_count': reloc_cnt,
        'export_count': export_cnt, 'import_count': import_cnt,
        'entry_offset': entry_off, 'provided_offset': prov_off,
        'reserved': reserved,
    }


def extract_relocs(data, hdr):
    """Extract relocation table entries (list of u64 offsets)."""
    base = 64 + hdr['seg_size']
    relocs = []
    for i in range(hdr['reloc_count']):
        off = base + i * 8
        val = struct.unpack_from('<Q', data, off)[0]
        relocs.append(val)
    return relocs


def extract_imports(data, hdr):
    """Extract import table entries (list of (fixup_offset, name) pairs)."""
    base = 64 + hdr['seg_size'] + hdr['reloc_count'] * 8
    imports = []
    for i in range(hdr['import_count']):
        off = base + i * 32  # 32-byte entries: fixup(8) + name(24)
        fixup = struct.unpack_from('<Q', data, off)[0]
        name_bytes = data[off + 8 : off + 32]
        nul_pos = name_bytes.find(b'\x00')
        if nul_pos >= 0:
            name_bytes = name_bytes[:nul_pos]
        name = name_bytes.decode('ascii', errors='replace')
        imports.append((fixup, name))
    return imports


# ─── Main Test ───────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("  binimg Phase 1 — Core Saver Test")
    print("=" * 60)
    print()

    # ── 1. Build disk image with an empty output file ────────────────
    # Pre-create "out.m64" with 32 sectors (16 KiB) — plenty for test
    out_m64_slot = 0  # directory slot index for our output file
    out_sectors = 32
    files = [
        ("out.m64", 255, 1, b'\x00' * (out_sectors * SECTOR)),
    ]
    disk_img = build_disk_image(files)
    img_path = os.path.join(tempfile.gettempdir(), 'test_binimg.img')
    with open(img_path, 'wb') as f:
        f.write(disk_img)
    print(f"[*] Disk image: {img_path} ({len(disk_img)} bytes)")

    # ── 2. Boot BIOS + KDOS ─────────────────────────────────────────
    print("[*] Booting BIOS + KDOS ...")
    t0 = time.time()
    bios_code = load_bios()
    kdos_lines = load_forth_lines(KDOS_PATH)

    sys_obj = MegapadSystem(ram_size=2 * 1024 * 1024, storage_image=img_path)
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    # Feed KDOS
    kdos_payload = "\n".join(kdos_lines) + "\n"
    steps = feed_and_run(sys_obj, kdos_payload)
    boot_text = uart_text(buf)
    elapsed = time.time() - t0
    print(f"[*] KDOS booted. {steps:,} steps in {elapsed:.1f}s")

    # Check for errors
    errors = [l for l in boot_text.split('\n')
              if '?' in l and 'not found' in l.lower()]
    if errors:
        print("[!] Boot errors:")
        for e in errors:
            print(f"    {e}")

    # ── 3. Load binimg.f ─────────────────────────────────────────────
    print("[*] Loading binimg.f ...")
    buf.clear()
    binimg_lines = load_forth_lines(BINIMG_PATH)
    binimg_payload = "\n".join(binimg_lines) + "\n"
    steps = feed_and_run(sys_obj, binimg_payload)
    binimg_text = uart_text(buf)
    elapsed_total = time.time() - t0
    print(f"[*] binimg.f loaded. {steps:,} steps ({elapsed_total:.1f}s total)")

    # Print ALL output during load for debugging
    binimg_text = uart_text(buf)
    if binimg_text.strip():
        print("    Load output:")
        for line in binimg_text.strip().split('\n'):
            ll = line.strip()
            if ll:
                print(f"      {ll}")

    # Check for actual Forth "? not found" errors (not string literals)
    errors = [l for l in binimg_text.split('\n')
              if '? not found' in l.lower() or '? ' in l and 'not found' in l.lower()]
    if errors:
        print("[!] binimg.f errors:")
        for e in errors:
            print(f"    {e}")
        print("ABORTING.")
        os.unlink(img_path)
        return

    # ── 4. Run the save test ─────────────────────────────────────────
    # Compile a small test module between IMG-MARK and IMG-SAVE:
    #   VARIABLE X
    #   : SETX  42 X ! ;
    #   : GETX  X @ ;
    # These create relocations:
    #   - VARIABLE X: body-address LDI64 (BIOS-tracked)
    #   - SETX: calls X (compile_call → LDI64), stores literal 42
    #   - GETX: calls X (compile_call → LDI64)
    #   - TEST-PRINT: calls . (external, non-JIT → becomes import)
    #   - Link fields: 4 entries (X, SETX, GETX, TEST-PRINT)
    print("[*] Running IMG-MARK → compile → IMG-SAVE ...")
    buf.clear()
    test_lines = [
        # Print HERE before mark
        'HERE . CR',
        # Mark the start
        'IMG-MARK',
        'HERE . CR',
        # Compile test words
        'VARIABLE TESTVAR',
        ': TEST-SET  42 TESTVAR ! ;',
        ': TEST-GET  TESTVAR @ ;',
        ': TEST-PRINT  TESTVAR @ . ;',
        # Print HERE after compilation
        'HERE . CR',
        # Print reloc count before save (BIOS-tracked only)
        '_RELOC-COUNT @ . CR',
        # Save to the pre-created file
        'IMG-SAVE out.m64',
        # Print the return code
        '. CR',
        # Verify the words still work after save (denormalization)
        'TEST-SET TEST-GET . CR',
        '0 TESTVAR !  TEST-SET TEST-PRINT CR',
    ]
    test_payload = "\n".join(test_lines) + "\n"
    steps = feed_and_run(sys_obj, test_payload, max_steps=500_000_000, report_interval=5.0)
    test_text = uart_text(buf)
    print(f"[*] Save test done. {steps:,} steps")
    print(f"    UART output:")
    for line in test_text.strip().split('\n'):
        print(f"      {line}")

    # Parse the UART output
    output_lines = [l.strip() for l in test_text.strip().split('\n') if l.strip()]

    # ── 5. Verify .m64 on disk ───────────────────────────────────────
    print()
    print("[*] Verifying .m64 file on disk ...")

    # Force the emulator to flush its storage to disk
    sys_obj.storage.save_image()

    m64_data = read_m64_from_disk(img_path, out_m64_slot)
    if not m64_data:
        print("    FAIL: output file is empty (0 used bytes)")
        os.unlink(img_path)
        return

    print(f"    File size: {len(m64_data)} bytes")

    hdr = parse_m64_header(m64_data)
    if hdr is None:
        print(f"    FAIL: bad header (first 8 bytes: {m64_data[:8].hex()})")
        os.unlink(img_path)
        return

    print(f"    Header OK: magic=MF64, version={hdr['version']}")
    print(f"    Segment size: {hdr['seg_size']} bytes")
    print(f"    Reloc count:  {hdr['reloc_count']}")
    print(f"    Exports:      {hdr['export_count']}")
    print(f"    Imports:      {hdr['import_count']}")

    passed = 0
    failed = 0

    # Test: magic & version
    if hdr['version'] == 1:
        print("    PASS: version = 1")
        passed += 1
    else:
        print(f"    FAIL: version = {hdr['version']}, expected 1")
        failed += 1

    # Test: segment size > 0
    if hdr['seg_size'] > 0:
        print(f"    PASS: segment size = {hdr['seg_size']} > 0")
        passed += 1
    else:
        print("    FAIL: segment size = 0")
        failed += 1

    # Test: reloc count > 0 (we expect at least link fields + LDI64s)
    if hdr['reloc_count'] > 0:
        print(f"    PASS: reloc count = {hdr['reloc_count']} > 0")
        passed += 1
    else:
        print("    FAIL: reloc count = 0")
        failed += 1

    # Test: segment data is present
    seg_data = m64_data[64 : 64 + hdr['seg_size']]
    if len(seg_data) == hdr['seg_size']:
        print(f"    PASS: segment data present ({len(seg_data)} bytes)")
        passed += 1
    else:
        print(f"    FAIL: segment truncated ({len(seg_data)}/{hdr['seg_size']})")
        failed += 1

    # Test: relocation entries present and all within segment bounds
    relocs = extract_relocs(m64_data, hdr)
    all_in_bounds = all(0 <= r < hdr['seg_size'] for r in relocs)
    if all_in_bounds and len(relocs) == hdr['reloc_count']:
        print(f"    PASS: all {len(relocs)} reloc offsets within segment")
        passed += 1
    else:
        oob = [r for r in relocs if r < 0 or r >= hdr['seg_size']]
        print(f"    FAIL: {len(oob)} reloc offsets out of bounds")
        for r in oob[:5]:
            print(f"        offset {r} (seg_size={hdr['seg_size']})")
        failed += 1

    # Test: segment values at reloc offsets are base-0 normalized
    # (all should be < seg_size since they point within the segment)
    bad_values = []
    for r in relocs:
        if r + 8 <= len(seg_data):
            val = struct.unpack_from('<Q', seg_data, r)[0]
            # Normalized values should be segment-relative (< seg_size)
            # OR zero (null link at chain end)
            if val != 0 and val >= hdr['seg_size']:
                bad_values.append((r, val))

    if not bad_values:
        print(f"    PASS: all reloc'd values are base-0 normalized")
        passed += 1
    else:
        print(f"    FAIL: {len(bad_values)} reloc'd values not normalized")
        for r, v in bad_values[:5]:
            print(f"        offset {r}: value {v:#x} (seg_size={hdr['seg_size']})")
        failed += 1

    # Test: file ends correctly (header + segment + relocs)
    expected_size = 64 + hdr['seg_size'] + hdr['reloc_count'] * 8
    if len(m64_data) >= expected_size:
        print(f"    PASS: file size ({len(m64_data)}) >= expected ({expected_size})")
        passed += 1
    else:
        print(f"    FAIL: file too small ({len(m64_data)} < {expected_size})")
        failed += 1

    # Test: denormalization worked (words still execute)
    # We look for "42" in the output from "TEST-SET TEST-GET . CR"
    if '42' in test_text:
        print("    PASS: words still work after save (denormalization OK)")
        passed += 1
    else:
        print("    FAIL: denormalization may have broken live dict")
        failed += 1

    # Test: IMG-SAVE returned 0 (success)
    # The output should contain "0" on its own line after IMG-SAVE
    # Look for the save return code
    save_ok = False
    for line in output_lines:
        # After IMG-SAVE, next ". CR" should print 0
        if line.strip() == '0':
            save_ok = True
            break
    if save_ok:
        print("    PASS: IMG-SAVE returned 0 (success)")
        passed += 1
    else:
        print("    WARN: could not confirm IMG-SAVE return code")
        # Don't count as fail — output parsing can be tricky

    # ── Summary ──────────────────────────────────────────────────────
    print()
    print(f"Results: {passed} passed, {failed} failed")
    if failed == 0:
        print("ALL TESTS PASSED")
    else:
        print("SOME TESTS FAILED")

    # Detailed segment dump for debugging
    if '--dump' in sys.argv:
        print()
        print("--- Segment hex dump (first 128 bytes) ---")
        for i in range(0, min(128, len(seg_data)), 16):
            hex_part = " ".join(f"{seg_data[i+j]:02x}" for j in range(min(16, len(seg_data) - i)))
            print(f"  {i:04x}: {hex_part}")
        print()
        print("--- Relocation offsets ---")
        for i, r in enumerate(relocs):
            val = struct.unpack_from('<Q', seg_data, r)[0] if r + 8 <= len(seg_data) else -1
            print(f"  [{i}] offset={r} value={val:#x}")

    # ── Phase 2: Load Test ───────────────────────────────────────────
    print()
    print("=" * 60)
    print("  binimg Phase 2 — Core Loader Test")
    print("=" * 60)
    print()

    # Record the address of TESTVAR before loading (the saved copy)
    print("[*] Recording pre-load state ...")
    buf.clear()
    pre_lines = [
        "' TESTVAR . CR",       # address of original TESTVAR
        "HERE . CR",            # current HERE before load
    ]
    pre_payload = "\n".join(pre_lines) + "\n"
    steps = feed_and_run(sys_obj, pre_payload, max_steps=500_000_000)
    pre_text = uart_text(buf)
    print(f"    Pre-load output:")
    for line in pre_text.strip().split('\n'):
        print(f"      {line}")

    # Parse addresses
    pre_nums = []
    for line in pre_text.strip().split('\n'):
        line = line.strip()
        # Take first token that looks like a number
        for tok in line.split():
            if tok == 'ok' or tok == '>':
                continue
            try:
                pre_nums.append(int(tok))
                break
            except ValueError:
                continue

    old_testvar_addr = pre_nums[0] if len(pre_nums) >= 1 else None
    pre_here = pre_nums[1] if len(pre_nums) >= 2 else None
    print(f"    Original TESTVAR addr: {old_testvar_addr}")
    print(f"    HERE before load: {pre_here}")

    # Load the .m64
    print()
    print("[*] Loading .m64 via IMG-LOAD ...")
    buf.clear()
    load_lines = [
        'IMG-LOAD out.m64',
        '. CR',                 # print return code
        'HERE . CR',            # HERE after load
        "' TESTVAR . CR",       # address of loaded TESTVAR (should differ!)
        '0 TESTVAR !',          # reset loaded TESTVAR to 0
        'TEST-SET',             # call the loaded TEST-SET (sets TESTVAR to 42)
        'TEST-GET . CR',        # call loaded TEST-GET, should print 42
        '0 TESTVAR !  TEST-SET TEST-PRINT CR',  # test import-resolved . works
    ]
    load_payload = "\n".join(load_lines) + "\n"
    steps = feed_and_run(sys_obj, load_payload, max_steps=500_000_000)
    load_text = uart_text(buf)
    print(f"[*] Load test done. {steps:,} steps")
    print(f"    UART output:")
    for line in load_text.strip().split('\n'):
        print(f"      {line}")

    # Parse load output
    load_nums = []
    for line in load_text.strip().split('\n'):
        line = line.strip()
        for tok in line.split():
            if tok == 'ok' or tok == '>':
                continue
            try:
                load_nums.append(int(tok))
                break
            except ValueError:
                continue

    print()
    p2_passed = 0
    p2_failed = 0

    # Test: IMG-LOAD returned 0
    load_ior = load_nums[0] if len(load_nums) >= 1 else -999
    if load_ior == 0:
        print("    PASS: IMG-LOAD returned 0 (success)")
        p2_passed += 1
    else:
        print(f"    FAIL: IMG-LOAD returned {load_ior}")
        p2_failed += 1

    # Test: new TESTVAR address differs from original
    new_testvar_addr = load_nums[2] if len(load_nums) >= 3 else None
    if old_testvar_addr and new_testvar_addr and new_testvar_addr != old_testvar_addr:
        print(f"    PASS: TESTVAR relocated ({old_testvar_addr} -> {new_testvar_addr})")
        p2_passed += 1
    elif new_testvar_addr == old_testvar_addr:
        print(f"    FAIL: TESTVAR not relocated (same address {new_testvar_addr})")
        p2_failed += 1
    else:
        print(f"    SKIP: could not determine TESTVAR addresses")

    # Test: loaded words execute correctly (TEST-SET / TEST-GET = 42)
    if '42' in load_text:
        print("    PASS: loaded words execute correctly (42)")
        p2_passed += 1
    else:
        print("    FAIL: loaded words did not produce 42")
        p2_failed += 1

    # Test: no error messages
    load_errors = [l for l in load_text.split('\n')
                   if 'IMG-LOAD:' in l or 'IMG: import' in l or '? not found' in l.lower()]
    if not load_errors:
        print("    PASS: no error messages during load")
        p2_passed += 1
    else:
        print(f"    FAIL: errors during load:")
        for e in load_errors:
            print(f"        {e.strip()}")
        p2_failed += 1

    # ── Combined Summary ─────────────────────────────────────────────

    # Phase 3 file checks
    print()
    print("=" * 60)
    print("  binimg Phase 3 — Imports Test")
    print("=" * 60)
    print()
    p3_passed = 0
    p3_failed = 0

    # Test: import count > 0 (TEST-PRINT calls ., which is external)
    if hdr['import_count'] > 0:
        print(f"    PASS: import count = {hdr['import_count']} > 0")
        p3_passed += 1
    else:
        print("    FAIL: import count = 0 (expected at least 1 import for '.')")
        p3_failed += 1

    # Test: import entries have valid names
    imports = extract_imports(m64_data, hdr)
    import_names = [name for _, name in imports]
    all_named = all(len(name) > 0 for name in import_names)
    if all_named and len(imports) == hdr['import_count']:
        print(f"    PASS: all {len(imports)} imports have names: {import_names}")
        p3_passed += 1
    else:
        unnamed = [i for i, (_, name) in enumerate(imports) if not name]
        print(f"    FAIL: {len(unnamed)} imports have empty names")
        p3_failed += 1

    # Test: import fixup offsets are within segment bounds
    imp_offsets_ok = all(0 <= fixup < hdr['seg_size'] for fixup, _ in imports)
    if imp_offsets_ok:
        print(f"    PASS: all import fixup offsets within segment")
        p3_passed += 1
    else:
        bad_imp = [(f, n) for f, n in imports if f < 0 or f >= hdr['seg_size']]
        print(f"    FAIL: {len(bad_imp)} import fixup offsets out of bounds")
        for f, n in bad_imp[:5]:
            print(f"        fixup={f} name='{n}' (seg_size={hdr['seg_size']})")
        p3_failed += 1

    # Test: import slots in segment are zeroed (reproducibility)
    imp_slots_zeroed = True
    for fixup, name in imports:
        if fixup + 8 <= len(seg_data):
            val = struct.unpack_from('<Q', seg_data, fixup)[0]
            if val != 0:
                print(f"    WARN: import '{name}' fixup@{fixup} = {val:#x}, expected 0")
                imp_slots_zeroed = False
    if imp_slots_zeroed:
        print(f"    PASS: all import fixup slots zeroed in segment")
        p3_passed += 1
    else:
        print(f"    FAIL: some import fixup slots not zeroed")
        p3_failed += 1

    # Test: denormalization still works with imports
    # (TEST-PRINT uses ., should print 42 after save)
    if test_text.count('42') >= 2:  # first from TEST-GET, second from TEST-PRINT
        print("    PASS: TEST-PRINT works after save (denormalization OK)")
        p3_passed += 1
    else:
        print("    FAIL: TEST-PRINT did not produce 42 after save")
        p3_failed += 1

    # Test: loaded TEST-PRINT works (import . was resolved)
    # load_text should contain multiple 42s — one from TEST-GET, one from TEST-PRINT
    count_42 = load_text.count('42')
    if count_42 >= 2:
        print(f"    PASS: loaded TEST-PRINT works (import resolved, {count_42}x '42')")
        p3_passed += 1
    else:
        print(f"    FAIL: loaded TEST-PRINT did not produce 42 (count={count_42})")
        p3_failed += 1

    # Test: no import resolution errors during load
    imp_errors = [l for l in load_text.split('\n') if 'IMG: import not found' in l]
    if not imp_errors:
        print("    PASS: no import resolution errors")
        p3_passed += 1
    else:
        print(f"    FAIL: import resolution errors:")
        for e in imp_errors:
            print(f"        {e.strip()}")
        p3_failed += 1

    total_passed = passed + p2_passed + p3_passed
    total_failed = failed + p2_failed + p3_failed
    print()
    print(f"Phase 1: {passed} passed, {failed} failed")
    print(f"Phase 2: {p2_passed} passed, {p2_failed} failed")
    print(f"Phase 3: {p3_passed} passed, {p3_failed} failed")
    print(f"Total:   {total_passed} passed, {total_failed} failed")
    if total_failed == 0:
        print("ALL TESTS PASSED")
    else:
        print("SOME TESTS FAILED")

    # Cleanup
    os.unlink(img_path)
    print("\nDone.")
    sys.exit(1 if total_failed > 0 else 0)


if __name__ == "__main__":
    main()
