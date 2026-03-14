#!/usr/bin/env python3
"""Build a bootable disk image for the DOM-based Akashic Pad editor
and optionally boot it in the emulator with an interactive terminal.

Uses the DOM-TUI rendering stack (dom-render.f / dom-tui.f) instead
of the UIDL-TUI layer.  The BIOS auto-loads kdos.f, KDOS runs
autoexec.f which loads akashic-pad-dom.f.

Usage:
    python local_testing/boot_editor_dom.py                # build + boot
    python local_testing/boot_editor_dom.py --build-only   # image only
    python local_testing/boot_editor_dom.py --keep-image   # keep .img
"""
import argparse
import os
import select
import sys
import tempfile
import termios
import time
import tty

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(SCRIPT_DIR, "emu")
AK_DIR     = os.path.join(ROOT_DIR, "akashic")

BIOS_PATH  = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH  = os.path.join(EMU_DIR, "kdos.f")

sys.path.insert(0, EMU_DIR)
from asm import assemble                      # noqa: E402
from system import MegapadSystem              # noqa: E402
from diskutil import MP64FS, FTYPE_FORTH      # noqa: E402

# ---------------------------------------------------------------------------
#  Disk layout — DOM-TUI dependency chain + editor app
#
#  /kdos.f                  — auto-loaded by BIOS
#  /autoexec.f              — auto-run by KDOS
#  /markup/core.f
#  /markup/html.f
#  /css/css.f
#  /css/bridge.f
#  /dom/dom.f
#  /dom/html5.f
#  /utils/string.f
#  /utils/clipboard.f
#  /text/utf8.f
#  /tui/cell.f
#  /tui/ansi.f
#  /tui/screen.f
#  /tui/draw.f
#  /tui/box.f
#  /tui/region.f
#  /tui/keys.f
#  /tui/widget.f
#  /tui/dom-tui.f
#  /tui/dom-render.f
#  /tui/widgets/textarea.f
#  /akashic-pad-dom.f       — editor application
# ---------------------------------------------------------------------------

DISK_FILES = [
    # markup
    ("core.f",       "/markup",
     os.path.join(AK_DIR, "markup", "core.f")),
    ("html.f",       "/markup",
     os.path.join(AK_DIR, "markup", "html.f")),
    # css
    ("css.f",        "/css",
     os.path.join(AK_DIR, "css", "css.f")),
    ("bridge.f",     "/css",
     os.path.join(AK_DIR, "css", "bridge.f")),
    # dom
    ("dom.f",        "/dom",
     os.path.join(AK_DIR, "dom", "dom.f")),
    ("html5.f",      "/dom",
     os.path.join(AK_DIR, "dom", "html5.f")),
    # utils
    ("string.f",     "/utils",
     os.path.join(AK_DIR, "utils", "string.f")),
    ("clipboard.f",  "/utils",
     os.path.join(AK_DIR, "utils", "clipboard.f")),
    # text
    ("utf8.f",       "/text",
     os.path.join(AK_DIR, "text", "utf8.f")),
    # tui core
    ("cell.f",       "/tui",
     os.path.join(AK_DIR, "tui", "cell.f")),
    ("ansi.f",       "/tui",
     os.path.join(AK_DIR, "tui", "ansi.f")),
    ("screen.f",     "/tui",
     os.path.join(AK_DIR, "tui", "screen.f")),
    ("draw.f",       "/tui",
     os.path.join(AK_DIR, "tui", "draw.f")),
    ("box.f",        "/tui",
     os.path.join(AK_DIR, "tui", "box.f")),
    ("region.f",     "/tui",
     os.path.join(AK_DIR, "tui", "region.f")),
    ("keys.f",       "/tui",
     os.path.join(AK_DIR, "tui", "keys.f")),
    ("widget.f",     "/tui",
     os.path.join(AK_DIR, "tui", "widget.f")),
    ("dom-tui.f",    "/tui",
     os.path.join(AK_DIR, "tui", "dom-tui.f")),
    ("dom-render.f", "/tui",
     os.path.join(AK_DIR, "tui", "dom-render.f")),
    # tui widgets
    ("textarea.f",   "/tui/widgets",
     os.path.join(AK_DIR, "tui", "widgets", "textarea.f")),
]

EDITOR_PATH = os.path.join(AK_DIR, "examples", "pad", "akashic-pad-dom.f")

AUTOEXEC_F = r"""\ autoexec.f — boot script for Akashic Pad (DOM Edition)
ENTER-USERLAND
LOAD akashic-pad-dom.f
"""

# ---------------------------------------------------------------------------
#  Build disk image
# ---------------------------------------------------------------------------

def build_disk_image(img_path: str):
    """Create an MP64FS disk image with KDOS + DOM-TUI stack + editor."""
    print("[*] Building disk image (DOM edition)...")

    fs = MP64FS(total_sectors=4096)
    fs.format()

    # 1. kdos.f — must be first Forth file (BIOS auto-loads it)
    kdos_src = open(KDOS_PATH, "rb").read()
    fs.inject_file("kdos.f", kdos_src, ftype=FTYPE_FORTH, flags=0x02)
    print(f"  kdos.f ({len(kdos_src):,} bytes)")

    # 2. Create directories
    fs.mkdir("markup")
    fs.mkdir("css")
    fs.mkdir("dom")
    fs.mkdir("utils")
    fs.mkdir("text")
    fs.mkdir("tui")
    fs.mkdir("tui/widgets")

    # 3. Library source files (DOM-TUI dependency chain)
    for name, disk_dir, host_path in DISK_FILES:
        src = open(host_path, "rb").read()
        fs.inject_file(name, src, ftype=FTYPE_FORTH, path=disk_dir)
        print(f"  {disk_dir}/{name} ({len(src):,} bytes)")

    # 4. Editor application
    editor_src = open(EDITOR_PATH, "rb").read()
    fs.inject_file("akashic-pad-dom.f", editor_src, ftype=FTYPE_FORTH)
    print(f"  /akashic-pad-dom.f ({len(editor_src):,} bytes)")

    # 5. autoexec.f
    autoexec_src = AUTOEXEC_F.encode("utf-8")
    fs.inject_file("autoexec.f", autoexec_src, ftype=FTYPE_FORTH)
    print(f"  /autoexec.f ({len(autoexec_src):,} bytes)")

    fs.save(img_path)
    info = fs.info()
    print(f"[*] Disk image: {img_path}")
    print(f"    {info['files']} files, "
          f"{info['free_sectors']} free sectors")
    return img_path


# ---------------------------------------------------------------------------
#  Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Akashic Pad (DOM Edition) — build + boot")
    parser.add_argument("--scale", type=int, default=2,
                        help="Display scale factor (default: 2)")
    parser.add_argument("--no-display", action="store_true",
                        help="Run headless (print UART to stdout)")
    parser.add_argument("--keep-image", action="store_true",
                        help="Keep the disk image after exit")
    parser.add_argument("--build-only", action="store_true",
                        help="Build the disk image but don't boot")
    args = parser.parse_args()

    if args.keep_image or args.build_only:
        img_path = os.path.join(SCRIPT_DIR, "akashic-pad-dom.img")
    else:
        tmp = tempfile.NamedTemporaryFile(suffix=".img", delete=False,
                                          dir=SCRIPT_DIR)
        img_path = tmp.name
        tmp.close()

    try:
        build_disk_image(img_path)

        if args.build_only:
            print(f"[*] Image ready: {img_path}")
            return

        # -- Assemble BIOS --
        print("[*] Assembling BIOS...")
        with open(BIOS_PATH) as f:
            bios_code = assemble(f.read())

        # -- Create system --
        sys_emu = MegapadSystem(ram_size=1024*1024,
                                ext_mem_size=16 * (1 << 20),
                                storage_image=img_path)
        sys_emu.load_binary(0, bios_code)
        sys_emu.boot()

        # -- UART → stdout --
        out_fd = sys.stdout.fileno()
        sys_emu.uart.on_tx = lambda b: os.write(out_fd, bytes([b]))

        # -- Optional display window --
        display = None
        if not args.no_display:
            try:
                from display import FramebufferDisplay
                def _on_close():
                    sys_emu.cpu.halted = True
                    print("\n[display] Window closed.")
                display = FramebufferDisplay(sys_emu, scale=args.scale,
                                             title="Akashic Pad (DOM)",
                                             on_close=_on_close)
                display.start()
                print(f"[display] Window opened (scale={args.scale}x)")
            except ImportError as e:
                print(f"[display] pygame not available: {e}",
                      file=sys.stderr)

        # -- Run --
        print("[*] Booting Akashic Pad (DOM Edition)...")

        _BATCH = 50_000

        stdin_fd = sys.stdin.fileno()
        old_termios = termios.tcgetattr(stdin_fd)
        try:
            tty.setraw(stdin_fd)

            while not sys_emu.cpu.halted:
                rlist, _, _ = select.select([stdin_fd], [], [], 0)
                if rlist:
                    raw = os.read(stdin_fd, 64)
                    if raw:
                        if b'\x03' in raw:
                            break
                        sys_emu.uart.inject_input(raw)

                if display is not None and not display.running:
                    break

                if sys_emu.cpu.idle and not sys_emu.uart.has_rx_data:
                    sys_emu.bus.tick(200_000)
                    sys_emu.cpu.idle = False
                    time.sleep(0.01)
                    continue

                try:
                    sys_emu.run_batch(_BATCH)
                except Exception:
                    break

                time.sleep(0.0001)
        except KeyboardInterrupt:
            pass
        finally:
            termios.tcsetattr(stdin_fd, termios.TCSADRAIN, old_termios)
            if display is not None:
                display.stop()
            print("\n[*] Done.")
    finally:
        if not (args.keep_image or args.build_only):
            if os.path.exists(img_path):
                os.unlink(img_path)


if __name__ == "__main__":
    main()
