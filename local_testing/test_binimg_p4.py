#!/usr/bin/env python3
"""Minimal Phase 4 test — boot, load binimg, enter userland, save one .m64."""
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

def make_entry(name, start_sec, sec_count, used_bytes, ftype, parent):
    e = bytearray(48)
    nb = name.encode('ascii')[:24]
    e[:len(nb)] = nb
    struct.pack_into('<HH', e, 24, start_sec, sec_count)
    struct.pack_into('<I', e, 28, used_bytes)
    e[32] = ftype; e[34] = parent
    return bytes(e)

def build_disk_image(files):
    data_start = 14; entries = []; data_sectors = []; next_sec = data_start
    for name, parent, ftype, content in files:
        content_bytes = content if isinstance(content, bytes) else content.encode('ascii')
        n_sec = max((len(content_bytes) + SECTOR - 1) // SECTOR, 1)
        entries.append(make_entry(name, next_sec, n_sec, len(content_bytes), 1, parent))
        padded = content_bytes + b'\x00' * (n_sec * SECTOR - len(content_bytes))
        data_sectors.append((next_sec, padded)); next_sec += n_sec
    sb = bytearray(SECTOR); sb[0:4] = b'MP64'
    struct.pack_into('<H', sb, 4, 1); struct.pack_into('<I', sb, 6, 2048)
    struct.pack_into('<H', sb, 10, 1); struct.pack_into('<H', sb, 12, 1)
    struct.pack_into('<H', sb, 14, 2); struct.pack_into('<H', sb, 16, 12)
    struct.pack_into('<H', sb, 18, data_start); sb[20] = 128; sb[21] = 48
    bmap = bytearray(SECTOR)
    for s in range(data_start): bmap[s//8] |= (1 << (s%8))
    for ss, p in data_sectors:
        for s in range(ss, ss + len(p)//SECTOR): bmap[s//8] |= (1 << (s%8))
    dir_data = bytearray(12 * SECTOR)
    for i, e in enumerate(entries): dir_data[i*48:i*48+48] = e
    total = max(next_sec, 2048); image = bytearray(total * SECTOR)
    image[0:SECTOR] = sb; image[SECTOR:2*SECTOR] = bmap
    image[2*SECTOR:14*SECTOR] = dir_data
    for ss, p in data_sectors: image[ss*SECTOR:ss*SECTOR+len(p)] = p
    return image

def load_forth_lines(path):
    with open(path) as f:
        return [l for l in f.read().splitlines()
                if l.strip() and not l.strip().startswith('\\')
                and not l.strip().startswith('REQUIRE ')
                and not l.strip().startswith('PROVIDED ')]

def next_line_chunk(data, pos):
    nl = data.find(b'\n', pos)
    return data[pos:] if nl == -1 else data[pos:nl+1]

def feed_and_run(sys_obj, data, buf, label="", max_steps=400_000_000):
    if isinstance(data, str): data = data.encode()
    pos = 0; steps = 0; t0 = time.time()
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
        if time.time() - t0 > 10:
            pct = 100*pos/max(len(data),1)
            print(f"    [{label}] {steps:,} steps, {pos}/{len(data)} ({pct:.0f}%)")
            t0 = time.time()
    return steps

def uart_text(buf):
    return "".join(chr(b) if (0x20 <= b < 0x7F or b in (10,13,9)) else "" for b in buf)

def main():
    # Disk
    files = [("prov.m64", 255, 1, b'\x00' * (32 * SECTOR))]
    disk_img = build_disk_image(files)
    img_path = os.path.join(tempfile.gettempdir(), 'test_binimg_p4.img')
    with open(img_path, 'wb') as f: f.write(disk_img)

    # Boot
    print("[*] Booting...")
    with open(BIOS_PATH) as f: bios_code = assemble(f.read())
    sys_obj = MegapadSystem(ram_size=2*1024*1024, storage_image=img_path,
                             ext_mem_size=16*1024*1024)
    buf = []
    sys_obj.uart.on_tx = lambda b: buf.append(b)
    sys_obj.load_binary(0, bios_code); sys_obj.boot()

    kdos_payload = "\n".join(load_forth_lines(KDOS_PATH)) + "\n"
    feed_and_run(sys_obj, kdos_payload, buf, "KDOS", max_steps=800_000_000)
    print(f"[*] KDOS done.")

    # Load binimg.f
    buf.clear()
    binimg_payload = "\n".join(load_forth_lines(BINIMG_PATH)) + "\n"
    feed_and_run(sys_obj, binimg_payload, buf, "binimg")
    bt = uart_text(buf)
    if bt.strip(): print(f"    binimg output: {bt.strip()[:200]}")

    # Enter userland
    buf.clear()
    feed_and_run(sys_obj, 'ENTER-USERLAND\n', buf, "uland", max_steps=50_000_000)
    ut = uart_text(buf)
    print(f"[*] ENTER-USERLAND: {ut.strip()}")

    # Phase 4 save — feed one line at a time to find hang point
    lines = [
        ('.\" [A] HERE=\" HERE . CR',           'A: HERE before mark'),
        ('IMG-MARK',                            'B: IMG-MARK'),
        ('.\" [B] post-mark HERE=\" HERE . CR', 'C: HERE after mark'),
        ('IMG-PROVIDED test-binimg-mod',        'D: IMG-PROVIDED'),
        ('.\" [D] post-prov HERE=\" HERE . CR', 'E: HERE after prov'),
        ('VARIABLE P4V',                        'F: VARIABLE'),
        ('.\" [F] post-var HERE=\" HERE . CR',  'G: HERE after var'),
        (': P4SET  99 P4V ! ;',                 'H: P4SET'),
        (': P4RUN  P4SET P4V @ . CR ;',         'I: P4RUN'),
        (".\" [I] pre-entry\" CR",              'J: pre-entry'),
        ("' P4RUN IMG-ENTRY",                   'K: IMG-ENTRY'),
        ('.\" [K] pre-save\" CR',               'L: pre-save'),
        ('IMG-SAVE prov.m64',                   'M: IMG-SAVE'),
        ('. CR',                                'N: print ior'),
    ]
    for forth_line, label in lines:
        buf.clear()
        print(f"    >> {label}: {forth_line[:60]}")
        steps = feed_and_run(sys_obj, forth_line + '\n', buf, label[:8], max_steps=50_000_000)
        out = uart_text(buf)
        if out.strip():
            print(f"       {out.strip()[:120]}")
        if steps >= 49_000_000:
            print(f"    *** HUNG at {label} ({steps:,} steps) ***")
            break

    os.unlink(img_path)
    print("\nDone.")

if __name__ == "__main__":
    main()
