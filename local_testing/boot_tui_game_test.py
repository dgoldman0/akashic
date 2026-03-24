#!/usr/bin/env python3
"""Boot-test: load all tui/game modules through the emulator.

Verifies every TUI game component Forth file compiles without errors.
Reports success/failure for each module.
"""
import os, sys, tempfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
AK_DIR     = os.path.join(ROOT_DIR, "akashic")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem
from diskutil import MP64FS, FTYPE_FORTH

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# All files needed on disk, in dependency order.
DISK_FILES = [
    # text
    ("utf8.f", "/text", os.path.join(AK_DIR, "text", "utf8.f")),
    # tui base
    ("ansi.f",      "/tui", os.path.join(AK_DIR, "tui", "ansi.f")),
    ("keys.f",      "/tui", os.path.join(AK_DIR, "tui", "keys.f")),
    ("cell.f",      "/tui", os.path.join(AK_DIR, "tui", "cell.f")),
    ("screen.f",    "/tui", os.path.join(AK_DIR, "tui", "screen.f")),
    ("draw.f",      "/tui", os.path.join(AK_DIR, "tui", "draw.f")),
    ("box.f",       "/tui", os.path.join(AK_DIR, "tui", "box.f")),
    ("region.f",    "/tui", os.path.join(AK_DIR, "tui", "region.f")),
    ("widget.f",    "/tui", os.path.join(AK_DIR, "tui", "widget.f")),
    ("app-desc.f",  "/tui", os.path.join(AK_DIR, "tui", "app-desc.f")),
    # tui widgets needed by game-canvas
    ("canvas.f", "/tui/widgets", os.path.join(AK_DIR, "tui", "widgets", "canvas.f")),
    # standalone game engine (used by world-render for tilemap/sprite formats)
    ("loop.f",    "/tui/game", os.path.join(AK_DIR, "tui", "game", "loop.f")),
    ("input.f",   "/tui/game", os.path.join(AK_DIR, "tui", "game", "input.f")),
    ("tilemap.f", "/tui/game", os.path.join(AK_DIR, "tui", "game", "tilemap.f")),
    ("sprite.f",  "/tui/game", os.path.join(AK_DIR, "tui", "game", "sprite.f")),
    ("scene.f",   "/tui/game", os.path.join(AK_DIR, "tui", "game", "scene.f")),
    # 2d game engine
    ("collide.f", "/game/2d", os.path.join(AK_DIR, "game", "2d", "collide.f")),
    # TUI game components (Phase 0 + Phase 1)
    ("game-view.f",     "/tui/game", os.path.join(AK_DIR, "tui", "game", "game-view.f")),
    ("game-canvas.f",   "/tui/game", os.path.join(AK_DIR, "tui", "game", "game-canvas.f")),
    ("game-applet.f",   "/tui/game", os.path.join(AK_DIR, "tui", "game", "game-applet.f")),
    ("atlas.f",         "/tui/game", os.path.join(AK_DIR, "tui", "game", "atlas.f")),
    ("camera.f",        "/game/2d",   os.path.join(AK_DIR, "game", "2d", "camera.f")),
    ("world-render.f",  "/tui/game", os.path.join(AK_DIR, "tui", "game", "world-render.f")),
]

# Forth test code: load each module and report success
TEST_FORTH = r"""\ boot_tui_game_test.f — compile-check for tui/game modules

REQUIRE tui/game/game-view.f
." [OK] game-view.f" CR

REQUIRE tui/game/game-canvas.f
." [OK] game-canvas.f" CR

REQUIRE tui/game/game-applet.f
." [OK] game-applet.f" CR

REQUIRE tui/game/atlas.f
." [OK] atlas.f" CR

REQUIRE game/2d/camera.f
." [OK] camera.f" CR

REQUIRE tui/game/world-render.f
." [OK] world-render.f" CR

." ALL-TUI-GAME-OK" CR
"""

AUTOEXEC_F = r"""\ autoexec.f
ENTER-USERLAND
LOAD boot_tui_game_test.f
"""


def capture_uart(sys_obj):
    buf = bytearray()
    sys_obj.uart.on_tx = lambda b: buf.append(b)
    return buf


def uart_text(buf):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9, 27)) else ""
        for b in buf)


def run_until_idle(sys_obj, max_steps=500_000_000):
    steps = 0
    while steps < max_steps:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            break
        batch = sys_obj.run_batch(min(5_000_000, max_steps - steps))
        steps += max(batch, 1)
    return steps


def build_disk(img_path):
    fs = MP64FS(total_sectors=4096)
    fs.format()

    kdos_src = open(KDOS_PATH, "rb").read()
    fs.inject_file("kdos.f", kdos_src, ftype=FTYPE_FORTH, flags=0x02)

    dirs_made = set()
    for _, disk_dir, _ in DISK_FILES:
        parts = disk_dir.strip("/").split("/")
        for i in range(len(parts)):
            d = "/" + "/".join(parts[:i+1])
            if d not in dirs_made:
                fs.mkdir(d.lstrip("/"))
                dirs_made.add(d)

    for name, disk_dir, host_path in DISK_FILES:
        src = open(host_path, "rb").read()
        fs.inject_file(name, src, ftype=FTYPE_FORTH, path=disk_dir)

    test_src = TEST_FORTH.encode("utf-8")
    fs.inject_file("boot_tui_game_test.f", test_src, ftype=FTYPE_FORTH)

    auto_src = AUTOEXEC_F.encode("utf-8")
    fs.inject_file("autoexec.f", auto_src, ftype=FTYPE_FORTH)

    fs.save(img_path)


def main():
    tmp = tempfile.NamedTemporaryFile(suffix=".img", delete=False, dir=SCRIPT_DIR)
    img_path = tmp.name
    tmp.close()

    try:
        build_disk(img_path)
        print("[*] Assembling BIOS...")
        with open(BIOS_PATH) as f:
            bios_code = assemble(f.read())

        sys_emu = MegapadSystem(ram_size=1024*1024,
                                ext_mem_size=16*(1 << 20),
                                storage_image=img_path)
        buf = capture_uart(sys_emu)
        sys_emu.load_binary(0, bios_code)
        sys_emu.boot()

        print("[*] Booting KDOS + loading TUI game modules...")
        steps = run_until_idle(sys_emu)
        text = uart_text(buf)

        print(f"[*] Completed in {steps:,} steps\n")

        lines = text.split("\n")
        for line in lines:
            line = line.strip()
            if line.startswith("[OK]") or "ALL-TUI-GAME-OK" in line:
                print(f"  {line}")
            elif "ABORT" in line.upper() or "ERROR" in line.upper():
                print(f"  *** {line}")

        if "ALL-TUI-GAME-OK" in text:
            print("\n=== ALL TUI GAME MODULES COMPILED OK ===")
            return 0
        else:
            print("\n=== COMPILATION FAILED ===")
            print("--- Full UART output ---")
            for line in lines[-40:]:
                print(f"  {line.rstrip()}")
            return 1
    finally:
        os.unlink(img_path)


if __name__ == "__main__":
    sys.exit(main())
