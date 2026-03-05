#!/usr/bin/env python3
"""Focused Phase 4 test: exec2, noexec, XMEM only.
Boots KDOS, loads binimg.f, enters userland, then runs ONLY the three
operations that previously hung (infinite DO loop, now fixed with ?DO).
"""
import os, sys, struct, time, tempfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(SCRIPT_DIR, "emu")
AK_DIR     = os.path.join(ROOT_DIR, "akashic")
sys.path.insert(0, EMU_DIR)

from asm import assemble
from system import MegapadSystem

BIOS_PATH   = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH   = os.path.join(EMU_DIR, "kdos.f")
BINIMG_PATH = os.path.join(AK_DIR, "utils", "binimg.f")
SECTOR = 512

# ── helpers (copied from test_binimg.py) ──

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
    for s in range(data_start): bmap[s//8] |= (1<<(s%8))
    for ss, p in data_sectors:
        for s in range(ss, ss+len(p)//SECTOR): bmap[s//8] |= (1<<(s%8))
    dir_data = bytearray(12*SECTOR)
    for i, e in enumerate(entries): dir_data[i*48:i*48+48] = e
    total = max(next_sec, 2048)
    image = bytearray(total*SECTOR)
    image[0:SECTOR] = sb; image[SECTOR:2*SECTOR] = bmap
    image[2*SECTOR:14*SECTOR] = dir_data
    for ss, p in data_sectors: image[ss*SECTOR:ss*SECTOR+len(p)] = p
    return image

def load_bios():
    with open(BIOS_PATH) as f: return assemble(f.read())

def load_forth_lines(path):
    with open(path) as f:
        lines = []
        for line in f.read().splitlines():
            s = line.strip()
            if not s or s.startswith('\\') or s.startswith('REQUIRE ') or s.startswith('PROVIDED '):
                continue
            lines.append(line)
        return lines

def next_line_chunk(data, pos):
    nl = data.find(b'\n', pos)
    return data[pos:] if nl == -1 else data[pos:nl+1]

def capture_uart(sys_obj):
    buf = []
    sys_obj.uart.on_tx = lambda b: buf.append(b)
    return buf

def uart_text(buf):
    return "".join(chr(b) if (0x20<=b<0x7F or b in (10,13,9)) else "" for b in buf)

def feed_and_run(sys_obj, data, max_steps=400_000_000):
    if isinstance(data, str): data = data.encode()
    pos = 0; steps = 0
    while steps < max_steps:
        if sys_obj.cpu.halted: break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk); pos += len(chunk)
            else: break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)
    return steps

# ── main ──

def main():
    out_sectors = 32  # 16KB per slot
    files = [
        ("exec2.m64",  255, 1, b'\x00' * (out_sectors*SECTOR)),
        ("noexec.m64", 255, 1, b'\x00' * (out_sectors*SECTOR)),
        ("xmem.m64",   255, 1, b'\x00' * (out_sectors*SECTOR)),
    ]
    disk_img = build_disk_image(files)
    img_path = os.path.join(tempfile.gettempdir(), 'test_binimg_p4x.img')
    with open(img_path, 'wb') as f: f.write(disk_img)

    # Boot
    print("[*] Booting BIOS + KDOS ...")
    t0 = time.time()
    bios_code = load_bios()
    sys_obj = MegapadSystem(ram_size=2*1024*1024, storage_image=img_path,
                             ext_mem_size=16*1024*1024)
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    kdos_payload = "\n".join(load_forth_lines(KDOS_PATH)) + "\n"
    steps = feed_and_run(sys_obj, kdos_payload, max_steps=800_000_000)
    print(f"[*] KDOS booted. {steps:,} steps in {time.time()-t0:.1f}s")

    # Load binimg.f
    buf.clear()
    binimg_payload = "\n".join(load_forth_lines(BINIMG_PATH)) + "\n"
    steps = feed_and_run(sys_obj, binimg_payload)
    load_text = uart_text(buf)
    errs = [l for l in load_text.split('\n') if '? not found' in l.lower()]
    if errs:
        print(f"[!] binimg.f errors: {errs}")
        os.unlink(img_path); return
    print(f"[*] binimg.f loaded. {steps:,} steps")

    # Enter userland
    buf.clear()
    feed_and_run(sys_obj, 'ENTER-USERLAND\n', max_steps=100_000_000)

    passed = 0; failed = 0

    # ── TEST 1: IMG-SAVE-EXEC + IMG-LOAD-EXEC ──
    print("\n--- TEST 1: exec2 (IMG-SAVE-EXEC + IMG-LOAD-EXEC) ---")
    buf.clear()
    forth = '\n'.join([
        'IMG-MARK',
        ': RUN-ME  77 . CR ;',
        "' RUN-ME IMG-SAVE-EXEC exec2.m64",
        '. CR',                          # save ior
    ]) + '\n'
    t1 = time.time()
    steps = feed_and_run(sys_obj, forth, max_steps=200_000_000)
    save_text = uart_text(buf)
    print(f"    save: {steps:,} steps ({time.time()-t1:.1f}s)")
    print(f"    output: {save_text.strip()!r}")

    if '0' in [l.strip() for l in save_text.strip().split('\n')]:
        print("    PASS: exec2 save returned 0")
        passed += 1
    else:
        print(f"    FAIL: exec2 save did not return 0")
        failed += 1

    # Load + exec
    buf.clear()
    forth = '\n'.join([
        'IMG-LOAD-EXEC exec2.m64',
        '. CR',                          # print ior (xt stays on stack)
        'EXECUTE',                       # execute the xt — should print 77
    ]) + '\n'
    t1 = time.time()
    steps = feed_and_run(sys_obj, forth, max_steps=200_000_000)
    load_text = uart_text(buf)
    print(f"    load+exec: {steps:,} steps ({time.time()-t1:.1f}s)")
    print(f"    output: {load_text.strip()!r}")

    if '77' in load_text:
        print("    PASS: IMG-LOAD-EXEC produced 77")
        passed += 1
    else:
        print(f"    FAIL: no 77 in output")
        failed += 1

    # ── TEST 2: IMG-LOAD-EXEC on non-exec (.m64 without EXEC flag) ──
    print("\n--- TEST 2: noexec (IMG-LOAD-EXEC on non-exec binary) ---")
    buf.clear()
    forth = '\n'.join([
        'IMG-MARK',
        'VARIABLE DUMMY-VAR',
        'IMG-SAVE noexec.m64',
        '. CR',                          # save ior
    ]) + '\n'
    t1 = time.time()
    steps = feed_and_run(sys_obj, forth, max_steps=200_000_000)
    save_text = uart_text(buf)
    print(f"    save: {steps:,} steps ({time.time()-t1:.1f}s)")
    print(f"    output: {save_text.strip()!r}")

    buf.clear()
    forth = '\n'.join([
        'IMG-LOAD-EXEC noexec.m64',
        '. . CR',                        # print ior then dummy-xt
    ]) + '\n'
    t1 = time.time()
    steps = feed_and_run(sys_obj, forth, max_steps=200_000_000)
    load_text = uart_text(buf)
    print(f"    load: {steps:,} steps ({time.time()-t1:.1f}s)")
    print(f"    output: {load_text.strip()!r}")

    if '-6' in load_text:
        print("    PASS: IMG-LOAD-EXEC returns -6 on non-exec")
        passed += 1
    else:
        print(f"    FAIL: expected -6 in output")
        failed += 1

    # ── TEST 3: XMEM save + load ──
    print("\n--- TEST 3: XMEM (save with XMEM flag, load into ext mem) ---")
    buf.clear()
    forth = '\n'.join([
        'IMG-MARK',
        'VARIABLE XV',
        ': XSET  55 XV ! ;',
        ': XGET  XV @ ;',
        'IMG-XMEM',
        'IMG-SAVE xmem.m64',
        '. CR',
    ]) + '\n'
    t1 = time.time()
    steps = feed_and_run(sys_obj, forth, max_steps=200_000_000)
    save_text = uart_text(buf)
    print(f"    save: {steps:,} steps ({time.time()-t1:.1f}s)")
    print(f"    output: {save_text.strip()!r}")

    buf.clear()
    forth = '\n'.join([
        'IMG-LOAD xmem.m64',
        '. CR',                          # load ior
        '0 XV !  XSET XGET . CR',       # should print 55
    ]) + '\n'
    t1 = time.time()
    steps = feed_and_run(sys_obj, forth, max_steps=200_000_000)
    load_text = uart_text(buf)
    print(f"    load+exec: {steps:,} steps ({time.time()-t1:.1f}s)")
    print(f"    output: {load_text.strip()!r}")

    if '55' in load_text and '0' in [l.strip() for l in load_text.strip().split('\n')]:
        print("    PASS: XMEM load + execute works (55)")
        passed += 1
    else:
        print(f"    FAIL: expected 0 + 55 in output")
        failed += 1

    # ── Summary ──
    print(f"\n{'='*40}")
    print(f"Results: {passed} passed, {failed} failed out of 4")
    if failed == 0:
        print("ALL FOCUSED P4 TESTS PASSED")
    else:
        print("SOME TESTS FAILED")

    os.unlink(img_path)
    sys.exit(1 if failed else 0)

if __name__ == "__main__":
    main()
