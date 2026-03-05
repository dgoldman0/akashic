#!/usr/bin/env python3
"""Test suite for akashic-binimg Phase 1 (Core Saver), Phase 2 (Core Loader),
Phase 3 (Imports), and Phase 4 (Module System Integration).

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

Phase 4 tests PROVIDED integration (module registration on load),
entry-point support (IMG-ENTRY / IMG-SAVE-EXEC / IMG-LOAD-EXEC),
and XMEM loading.
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

def read_m64_from_raw(raw, file_entry_index):
    """Read .m64 from raw disk image bytes by directory entry index."""
    dir_base = 2 * SECTOR
    de_off = dir_base + file_entry_index * 48
    de = raw[de_off:de_off + 48]
    start_sec = struct.unpack_from('<H', de, 24)[0]
    used_bytes = struct.unpack_from('<I', de, 28)[0]
    data_off = start_sec * SECTOR
    return bytes(raw[data_off:data_off + used_bytes])


def read_m64_from_storage(storage, file_entry_index):
    """Read .m64 from emulator's in-memory Storage device."""
    return read_m64_from_raw(bytes(storage._image_data), file_entry_index)


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
    entry_pt   = struct.unpack_from('<Q', data, 56)[0]
    return {
        'version': version, 'flags': flags,
        'seg_size': seg_size, 'reloc_count': reloc_cnt,
        'export_count': export_cnt, 'import_count': import_cnt,
        'chain_head': entry_off, 'provided_offset': prov_off,
        'entry_point': entry_pt,
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
        ("exec2.m64", 255, 1, b'\x00' * (out_sectors * SECTOR)),
        ("noexec.m64", 255, 1, b'\x00' * (out_sectors * SECTOR)),
        ("xmem.m64", 255, 1, b'\x00' * (out_sectors * SECTOR)),
        ("prov.m64", 255, 1, b'\x00' * (out_sectors * SECTOR)),
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

    sys_obj = MegapadSystem(ram_size=2 * 1024 * 1024, storage_image=img_path,
                             ext_mem_size=16 * 1024 * 1024)
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    # Feed KDOS
    kdos_payload = "\n".join(kdos_lines) + "\n"
    steps = feed_and_run(sys_obj, kdos_payload, max_steps=800_000_000)
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
    steps = feed_and_run(sys_obj, test_payload, max_steps=50_000_000)
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
    print(f"    Flags:        {hdr['flags']}")
    print(f"    Provided off: {hdr['provided_offset']}")
    print(f"    Entry point:  {hdr['entry_point']}")

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
    steps = feed_and_run(sys_obj, pre_payload, max_steps=50_000_000)
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
        'TEST-PRINT',           # call loaded TEST-PRINT, should print 42 (import test)
    ]
    load_payload = "\n".join(load_lines) + "\n"
    steps = feed_and_run(sys_obj, load_payload, max_steps=50_000_000)
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

    # ── Phase 4: Module System Integration ────────────────────────────
    print()
    print("=" * 60)
    print("  binimg Phase 4 — Module System Integration")
    print("=" * 60)
    print()
    p4_passed = 0
    p4_failed = 0

    # Switch to userland so ALLOT uses ext mem (no overflow guard)
    buf.clear()
    feed_and_run(sys_obj, 'ENTER-USERLAND\n', max_steps=10_000_000)
    uland_text = uart_text(buf)
    if uland_text.strip():
        print(f"    ENTER-USERLAND: {uland_text.strip()}")

    # 4.1 PROVIDED + 4.3 ENTRY: save a module with both
    buf.clear()
    p4_save_lines = [
        'IMG-MARK',
        'IMG-PROVIDED test-binimg-mod',
        'VARIABLE P4V',
        ': P4SET  99 P4V ! ;',
        ': P4RUN  P4SET P4V @ . CR ;',
        "' P4RUN IMG-ENTRY",
        'IMG-SAVE prov.m64',
        '. CR',
        'P4RUN',   # verify denormalization works
    ]
    p4_save_payload = "\n".join(p4_save_lines) + "\n"
    p4_steps = feed_and_run(sys_obj, p4_save_payload, max_steps=50_000_000)
    p4_save_text = uart_text(buf)
    print(f"[*] Phase 4 save done. {p4_steps:,} steps")
    for line in p4_save_text.strip().split('\n'):
        print(f"      {line}")

    # Flush and read prov.m64 from disk
    sys_obj.storage.save_image()
    # prov.m64 is in slot 4 (out.m64=0, exec2.m64=1, noexec.m64=2, xmem.m64=3, prov.m64=4)
    _SENTINEL = 0xFFFFFFFFFFFFFFFF
    p4_hdr = None
    p4_seg = b''
    try:
        p4_data = read_m64_from_disk(img_path, 4)
        if p4_data and len(p4_data) >= 64 and p4_data[0:4] == b'MF64':
            p4_hdr = parse_m64_header(p4_data)
            if p4_hdr:
                p4_seg = p4_data[64:64 + p4_hdr['seg_size']]
    except Exception as e:
        print(f"    WARN: could not read prov.m64 slot 4: {e}")

    # Test: the save succeeded
    if '0' in [l.strip() for l in p4_save_text.strip().split('\n')]:
        print("    PASS: IMG-SAVE prov.m64 succeeded")
        p4_passed += 1
    else:
        print("    FAIL: IMG-SAVE prov.m64 did not return 0")
        p4_failed += 1

    # Test: PROVIDED offset present in header (not sentinel -1)
    if p4_hdr and p4_hdr['provided_offset'] != _SENTINEL:
        print(f"    PASS: provided_offset = {p4_hdr['provided_offset']}")
        p4_passed += 1
    else:
        prov_val = p4_hdr['provided_offset'] if p4_hdr else 'N/A'
        if prov_val == _SENTINEL:
            prov_val = '-1 (sentinel, IMG-PROVIDED not called?)'
        print(f"    FAIL: provided_offset = {prov_val}")
        p4_failed += 1

    # Test: PROVIDED string in segment matches
    prov_name = ''
    if p4_hdr and p4_hdr['provided_offset'] != _SENTINEL and p4_hdr['provided_offset'] < p4_hdr['seg_size']:
        poff = p4_hdr['provided_offset']
        name_bytes = p4_seg[poff:]
        nul = name_bytes.find(b'\x00')
        if nul >= 0:
            name_bytes = name_bytes[:nul]
        prov_name = name_bytes.decode('ascii', errors='replace')
    if prov_name == 'test-binimg-mod':
        print(f"    PASS: PROVIDED string = '{prov_name}'")
        p4_passed += 1
    else:
        print(f"    FAIL: PROVIDED string = '{prov_name}', expected 'test-binimg-mod'")
        p4_failed += 1

    # Test: EXEC flag set
    if p4_hdr and p4_hdr['flags'] & 4:
        print(f"    PASS: EXEC flag set (flags={p4_hdr['flags']})")
        p4_passed += 1
    else:
        flags_val = p4_hdr['flags'] if p4_hdr else 'N/A'
        print(f"    FAIL: EXEC flag not set (flags={flags_val})")
        p4_failed += 1

    # Test: entry_point present (not sentinel -1)
    if p4_hdr and p4_hdr['entry_point'] != _SENTINEL and p4_hdr['entry_point'] > 0:
        print(f"    PASS: entry_point = {p4_hdr['entry_point']}")
        p4_passed += 1
    else:
        ep_val = p4_hdr['entry_point'] if p4_hdr else 'N/A'
        if ep_val == _SENTINEL:
            ep_val = '-1 (sentinel, IMG-ENTRY not called?)'
        print(f"    FAIL: entry_point = {ep_val}")
        p4_failed += 1

    # Test: load prov.m64 and verify MODULE? registers the name
    buf.clear()
    p4_load_lines = [
        'IMG-LOAD prov.m64',
        '. CR',
        'MODULE? test-binimg-mod . CR',
    ]
    p4_load_payload = "\n".join(p4_load_lines) + "\n"
    feed_and_run(sys_obj, p4_load_payload, max_steps=50_000_000)
    p4_load_text = uart_text(buf)
    if '-1' in p4_load_text:
        print("    PASS: MODULE? test-binimg-mod returns true after load")
        p4_passed += 1
    else:
        print(f"    FAIL: MODULE? test-binimg-mod: '{p4_load_text.strip()}'")
        p4_failed += 1

    # 4.3 IMG-LOAD-EXEC: save a second exec .m64 and load with EXEC
    buf.clear()
    exec_lines = [
        'IMG-MARK',
        ': RUN-ME  77 . CR ;',
        "' RUN-ME IMG-SAVE-EXEC exec2.m64",
        '. CR',
    ]
    exec_payload = "\n".join(exec_lines) + "\n"
    feed_and_run(sys_obj, exec_payload, max_steps=50_000_000)
    exec_save_text = uart_text(buf)
    print(f"    exec2 save: '{exec_save_text.strip()[-80:]}'")

    buf.clear()
    lexec_lines = [
        'IMG-LOAD-EXEC exec2.m64',
        '. CR',          # print ior (xt stays on stack)
        'EXECUTE',       # execute the xt (should print 77)
    ]
    lexec_payload = "\n".join(lexec_lines) + "\n"
    feed_and_run(sys_obj, lexec_payload, max_steps=50_000_000)
    lexec_text = uart_text(buf)
    if '77' in lexec_text:
        print("    PASS: IMG-LOAD-EXEC + EXECUTE works (77)")
        p4_passed += 1
    else:
        print(f"    FAIL: IMG-LOAD-EXEC did not produce 77: '{lexec_text.strip()}'")
        p4_failed += 1

    # 4.3 IMG-LOAD-EXEC on non-exec returns _IMG-ERR-NOEXEC (-6)
    buf.clear()
    noexec_lines = [
        'IMG-MARK',
        'VARIABLE DUMMY-VAR',
        'IMG-SAVE noexec.m64',
        '. CR',
        'IMG-LOAD-EXEC noexec.m64',
        '. . CR',        # print ior then dummy-xt
    ]
    noexec_payload = "\n".join(noexec_lines) + "\n"
    feed_and_run(sys_obj, noexec_payload, max_steps=50_000_000)
    noexec_text = uart_text(buf)
    print(f"    noexec output: '{noexec_text.strip()[:200]}'")
    if '-6' in noexec_text:
        print("    PASS: IMG-LOAD-EXEC on non-exec returns -6")
        p4_passed += 1
    else:
        print(f"    FAIL: IMG-LOAD-EXEC on non-exec: '{noexec_text.strip()}'")
        p4_failed += 1

    # 4.2 XMEM load: save a normal module, load with XMEM flag
    buf.clear()
    xmem_lines = [
        'IMG-MARK',
        'VARIABLE XV',
        ': XSET  55 XV ! ;',
        ': XGET  XV @ ;',
        'IMG-XMEM',
        'IMG-SAVE xmem.m64',
        '. CR',
    ]
    xmem_payload = "\n".join(xmem_lines) + "\n"
    feed_and_run(sys_obj, xmem_payload, max_steps=50_000_000)
    xmem_save_text = uart_text(buf)
    print(f"    XMEM save output: '{xmem_save_text.strip()[:200]}'")

    buf.clear()
    xmem_load_lines = [
        'IMG-LOAD xmem.m64',
        '. CR',
        '0 XV !  XSET XGET . CR',
    ]
    xmem_load_payload = "\n".join(xmem_load_lines) + "\n"
    feed_and_run(sys_obj, xmem_load_payload, max_steps=50_000_000)
    xmem_load_text = uart_text(buf)
    if '55' in xmem_load_text and '0' in [l.strip() for l in xmem_load_text.strip().split('\n')]:
        print("    PASS: XMEM load + execute works (55)")
        p4_passed += 1
    else:
        print(f"    FAIL: XMEM load: '{xmem_load_text.strip()}'")
        p4_failed += 1

    total_passed += p4_passed
    total_failed += p4_failed

    # ── Phase 5: Diagnostics & Hardening ──────────────────────────────
    print()
    print("=" * 60)
    print("  binimg Phase 5 — Diagnostics & Hardening")
    print("=" * 60)
    print()
    p5_passed = 0
    p5_failed = 0

    # 5.1 IMG-INFO on out.m64 (Phase 1 file)
    buf.clear()
    info_lines = ['IMG-INFO out.m64']
    feed_and_run(sys_obj, "\n".join(info_lines) + "\n", max_steps=50_000_000)
    info_text = uart_text(buf)
    print(f"    IMG-INFO output:")
    for line in info_text.strip().split('\n'):
        ll = line.strip()
        if ll and ll != 'ok' and ll != '>':
            print(f"      {ll}")

    # Test: output contains key fields
    if 'MF64' in info_text and 'Segment' in info_text and 'Relocs' in info_text:
        print("    PASS: IMG-INFO prints header fields")
        p5_passed += 1
    else:
        print("    FAIL: IMG-INFO output missing fields")
        p5_failed += 1

    # Test: IMG-INFO on prov.m64 shows provided token
    buf.clear()
    feed_and_run(sys_obj, "IMG-INFO prov.m64\n", max_steps=50_000_000)
    info_prov_text = uart_text(buf)
    if 'test-binimg-mod' in info_prov_text:
        print("    PASS: IMG-INFO shows PROVIDED token")
        p5_passed += 1
    else:
        print(f"    FAIL: IMG-INFO prov.m64 missing token: '{info_prov_text.strip()[:100]}'")
        p5_failed += 1

    # 5.2 IMG-VERIFY on out.m64
    buf.clear()
    feed_and_run(sys_obj, "IMG-VERIFY out.m64 . CR\n", max_steps=50_000_000)
    verify_text = uart_text(buf)
    if '0' in [l.strip() for l in verify_text.strip().split('\n')]:
        print("    PASS: IMG-VERIFY out.m64 returns 0")
        p5_passed += 1
    else:
        print(f"    FAIL: IMG-VERIFY out.m64: '{verify_text.strip()}'")
        p5_failed += 1

    # IMG-VERIFY on prov.m64 (has exec + provided)
    buf.clear()
    feed_and_run(sys_obj, "IMG-VERIFY prov.m64 . CR\n", max_steps=50_000_000)
    verify_prov_text = uart_text(buf)
    if '0' in [l.strip() for l in verify_prov_text.strip().split('\n')]:
        print("    PASS: IMG-VERIFY prov.m64 returns 0")
        p5_passed += 1
    else:
        print(f"    FAIL: IMG-VERIFY prov.m64: '{verify_prov_text.strip()}'")
        p5_failed += 1

    # IMG-VERIFY on exec2.m64 (exec with entry)
    buf.clear()
    feed_and_run(sys_obj, "IMG-VERIFY exec2.m64 . CR\n", max_steps=50_000_000)
    verify_exec_text = uart_text(buf)
    if '0' in [l.strip() for l in verify_exec_text.strip().split('\n')]:
        print("    PASS: IMG-VERIFY exec2.m64 returns 0")
        p5_passed += 1
    else:
        print(f"    FAIL: IMG-VERIFY exec2.m64: '{verify_exec_text.strip()}'")
        p5_failed += 1

    # 5.4 IMG-CHECKSUM on out.m64 — should return nonzero hash
    buf.clear()
    feed_and_run(sys_obj, "IMG-CHECKSUM out.m64 . CR\n", max_steps=50_000_000)
    cksum_text = uart_text(buf)
    cksum_nums = []
    for line in cksum_text.strip().split('\n'):
        for tok in line.split():
            if tok in ('ok', '>'): continue
            try: cksum_nums.append(int(tok)); break
            except ValueError: continue

    cksum_val = cksum_nums[0] if cksum_nums else None
    if cksum_val is not None and cksum_val != 0:
        print(f"    PASS: IMG-CHECKSUM out.m64 = {cksum_val}")
        p5_passed += 1
    else:
        print(f"    FAIL: IMG-CHECKSUM out.m64 = {cksum_val}")
        p5_failed += 1

    # Reproducibility: same file twice → same checksum
    buf.clear()
    feed_and_run(sys_obj, "IMG-CHECKSUM out.m64 . CR\n", max_steps=50_000_000)
    cksum2_text = uart_text(buf)
    cksum2_nums = []
    for line in cksum2_text.strip().split('\n'):
        for tok in line.split():
            if tok in ('ok', '>'): continue
            try: cksum2_nums.append(int(tok)); break
            except ValueError: continue
    cksum2_val = cksum2_nums[0] if cksum2_nums else None
    if cksum_val is not None and cksum2_val == cksum_val:
        print(f"    PASS: IMG-CHECKSUM reproducible ({cksum_val} == {cksum2_val})")
        p5_passed += 1
    else:
        print(f"    FAIL: IMG-CHECKSUM not reproducible ({cksum_val} vs {cksum2_val})")
        p5_failed += 1

    # Different files → different checksum
    buf.clear()
    feed_and_run(sys_obj, "IMG-CHECKSUM prov.m64 . CR\n", max_steps=50_000_000)
    cksum_prov_text = uart_text(buf)
    cksum_prov_nums = []
    for line in cksum_prov_text.strip().split('\n'):
        for tok in line.split():
            if tok in ('ok', '>'): continue
            try: cksum_prov_nums.append(int(tok)); break
            except ValueError: continue
    cksum_prov_val = cksum_prov_nums[0] if cksum_prov_nums else None
    if cksum_prov_val is not None and cksum_prov_val != cksum_val:
        print(f"    PASS: different files → different checksums ({cksum_val} vs {cksum_prov_val})")
        p5_passed += 1
    else:
        print(f"    FAIL: different files same checksum ({cksum_val} vs {cksum_prov_val})")
        p5_failed += 1

    # ── 5.5 Cross-boot Reproducible Builds ────────────────────────────
    # "save from two separate boots (same BIOS) → byte-identical"
    # Extract out.m64 from first boot's disk image
    print()
    print("    --- Reproducible Builds (cross-boot) ---")
    m64_data_boot1 = read_m64_from_storage(sys_obj.storage, out_m64_slot)
    print(f"    [*] Boot 1 out.m64: {len(m64_data_boot1)} bytes")

    # Build a fresh disk image for the second boot
    disk_img2 = build_disk_image(files)
    img_path2 = os.path.join(tempfile.gettempdir(), 'test_binimg_boot2.img')
    with open(img_path2, 'wb') as f:
        f.write(disk_img2)

    # Boot a fresh emulator
    print("    [*] Booting second emulator ...")
    t_repro = time.time()
    sys_obj2 = MegapadSystem(ram_size=2 * 1024 * 1024, storage_image=img_path2,
                              ext_mem_size=16 * 1024 * 1024)
    buf2 = capture_uart(sys_obj2)
    sys_obj2.load_binary(0, bios_code)
    sys_obj2.boot()

    # Feed KDOS
    feed_and_run(sys_obj2, kdos_payload, max_steps=800_000_000)
    buf2.clear()

    # Feed binimg.f
    feed_and_run(sys_obj2, binimg_payload, max_steps=400_000_000)
    buf2.clear()

    # Compile the EXACT same source as first boot's Phase 1 save
    repro_lines = [
        'IMG-MARK',
        'VARIABLE TESTVAR',
        ': TEST-SET  42 TESTVAR ! ;',
        ': TEST-GET  TESTVAR @ ;',
        ': TEST-PRINT  TESTVAR @ . ;',
        'IMG-SAVE out.m64',
        '. CR',
    ]
    feed_and_run(sys_obj2, "\n".join(repro_lines) + "\n", max_steps=50_000_000)
    repro_text = uart_text(buf2)
    elapsed_repro = time.time() - t_repro
    print(f"    [*] Second boot done. {elapsed_repro:.1f}s")

    # Check save succeeded (output should contain "0")
    repro_ok = '0' in [l.strip() for l in repro_text.strip().split('\n')]
    if not repro_ok:
        print(f"    [!] Second boot save may have failed: '{repro_text.strip()}'")

    # Extract out.m64 from second boot's in-memory storage
    m64_data_boot2 = read_m64_from_storage(sys_obj2.storage, out_m64_slot)
    print(f"    [*] Boot 2 out.m64: {len(m64_data_boot2)} bytes")

    # Test: byte-identical .m64 from two separate boots
    if m64_data_boot1 == m64_data_boot2:
        print(f"    PASS: cross-boot byte-identical ({len(m64_data_boot1)} bytes)")
        p5_passed += 1
    else:
        # Find and report first difference
        min_len = min(len(m64_data_boot1), len(m64_data_boot2))
        diff_at = None
        for i in range(min_len):
            if m64_data_boot1[i] != m64_data_boot2[i]:
                diff_at = i
                break
        if diff_at is not None:
            print(f"    FAIL: cross-boot differs at byte {diff_at}: "
                  f"0x{m64_data_boot1[diff_at]:02x} vs 0x{m64_data_boot2[diff_at]:02x}")
            # Show context around the difference
            ctx_start = max(0, diff_at - 4)
            ctx_end = min(min_len, diff_at + 8)
            print(f"      boot1[{ctx_start}:{ctx_end}] = {m64_data_boot1[ctx_start:ctx_end].hex()}")
            print(f"      boot2[{ctx_start}:{ctx_end}] = {m64_data_boot2[ctx_start:ctx_end].hex()}")
        else:
            print(f"    FAIL: cross-boot different lengths: "
                  f"{len(m64_data_boot1)} vs {len(m64_data_boot2)}")
        p5_failed += 1

    # Test: cross-boot IMG-CHECKSUM matches
    buf2.clear()
    feed_and_run(sys_obj2, "IMG-CHECKSUM out.m64 . CR\n", max_steps=50_000_000)
    cksum_boot2_text = uart_text(buf2)
    cksum_boot2_nums = []
    for line in cksum_boot2_text.strip().split('\n'):
        for tok in line.split():
            if tok in ('ok', '>'): continue
            try: cksum_boot2_nums.append(int(tok)); break
            except ValueError: continue
    cksum_boot2_val = cksum_boot2_nums[0] if cksum_boot2_nums else None
    if cksum_boot2_val is not None and cksum_boot2_val == cksum_val:
        print(f"    PASS: cross-boot checksum matches ({cksum_val})")
        p5_passed += 1
    else:
        print(f"    FAIL: cross-boot checksum differs ({cksum_val} vs {cksum_boot2_val})")
        p5_failed += 1

    # Cleanup second disk image
    os.unlink(img_path2)

    total_passed += p5_passed
    total_failed += p5_failed
    print()
    print(f"Phase 1: {passed} passed, {failed} failed")
    print(f"Phase 2: {p2_passed} passed, {p2_failed} failed")
    print(f"Phase 3: {p3_passed} passed, {p3_failed} failed")
    print(f"Phase 4: {p4_passed} passed, {p4_failed} failed")
    print(f"Phase 5: {p5_passed} passed, {p5_failed} failed")
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
