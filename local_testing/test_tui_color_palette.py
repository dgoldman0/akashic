"""Seconds-only structural and byte-oracle locks for TUI palette expansion."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "akashic" / "tui" / "color.f"

MEGAPAD_BASE16 = [
    (0x00, 0x00, 0x00),
    (0xAA, 0x00, 0x00),
    (0x00, 0xAA, 0x00),
    (0xAA, 0x55, 0x00),
    (0x00, 0x00, 0xAA),
    (0xAA, 0x00, 0xAA),
    (0x00, 0xAA, 0xAA),
    (0xAA, 0xAA, 0xAA),
    (0x55, 0x55, 0x55),
    (0xFF, 0x55, 0x55),
    (0x55, 0xFF, 0x55),
    (0xFF, 0xFF, 0x55),
    (0x55, 0x55, 0xFF),
    (0xFF, 0x55, 0xFF),
    (0x55, 0xFF, 0xFF),
    (0xFF, 0xFF, 0xFF),
]
XTERM_CUBE_LEVELS = [0, 95, 135, 175, 215, 255]


def _definition(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:\s+{re.escape(name)}(?=\s).*?;\s*(?:\\[^\n]*)?$",
        source,
    )
    assert match is not None, f"missing Forth definition {name}"
    return match.group(0)


def _packed_rgba(red: int, green: int, blue: int) -> int:
    return (red << 24) | (green << 16) | (blue << 8) | 0xFF


def _source_base16(source: str) -> list[int]:
    match = re.search(
        r"(?ms)^CREATE\s+_TC-BASE16-RGBA\s*(.*?)^(?=VARIABLE|CREATE|:)",
        source,
    )
    assert match is not None, "missing _TC-BASE16-RGBA table"
    return [
        int(token, 16)
        for token in re.findall(r"(0x[0-9A-Fa-f]+)\s*,", match.group(1))
    ]


def _source_cube_levels(source: str) -> list[int]:
    match = re.search(r"(?m)^CREATE\s+_TC-CUBE-LEVELS\s+([^\n]+)$", source)
    assert match is not None, "missing _TC-CUBE-LEVELS table"
    return [int(token) for token in re.findall(r"(\d+)\s+C,", match.group(1))]


def _oracle_palette() -> list[int]:
    palette = [_packed_rgba(*rgb) for rgb in MEGAPAD_BASE16]
    for red in XTERM_CUBE_LEVELS:
        for green in XTERM_CUBE_LEVELS:
            for blue in XTERM_CUBE_LEVELS:
                palette.append(_packed_rgba(red, green, blue))
    for step in range(24):
        gray = 8 + 10 * step
        palette.append(_packed_rgba(gray, gray, gray))
    assert len(palette) == 256
    return palette


def test_palette_expansion_matches_all_256_megapad_terminal_entries() -> None:
    source = SOURCE.read_text(encoding="utf-8")

    base16 = _source_base16(source)
    levels = _source_cube_levels(source)
    assert base16 == [_packed_rgba(*rgb) for rgb in MEGAPAD_BASE16]
    assert levels == XTERM_CUBE_LEVELS

    source_palette = list(base16)
    for red in levels:
        for green in levels:
            for blue in levels:
                source_palette.append(_packed_rgba(red, green, blue))
    for step in range(24):
        gray = 8 + 10 * step
        source_palette.append(_packed_rgba(gray, gray, gray))

    assert source_palette == _oracle_palette()
    assert source_palette[0] == 0x000000FF
    assert source_palette[15] == 0xFFFFFFFF
    assert source_palette[16] == 0x000000FF
    assert source_palette[231] == 0xFFFFFFFF
    assert source_palette[232] == 0x080808FF
    assert source_palette[255] == 0xEEEEEEFF


def test_palette_expansion_is_neutral_bounded_and_allocation_free() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    pack = _definition(source, "_TC-PACK-RGBA")
    cube = _definition(source, "_TC-PALETTE-CUBE>RGBA")
    public = _definition(source, "TUI-PALETTE>RGBA")

    assert "( index -- rgba )" in public.splitlines()[0]
    assert "8 LSHIFT 0xFF OR" in pack
    assert "SWAP 16 LSHIFT OR" in pack
    assert "SWAP 24 LSHIFT OR" in pack
    assert "16 - 6 /MOD  _TCPI-Q !  _TCPI-BI !" in cube
    assert "_TCPI-Q @ 6 /MOD  _TCPI-RI !  _TCPI-GI !" in cube
    assert cube.count("_TC-CUBE-LEVELS") == 3

    assert public.index("DUP 16 U<") < public.index("DUP 232 U<")
    assert "232 - 10 * 8 +  DUP DUP  _TC-PACK-RGBA" in public
    assert "255 AND" not in public

    converter = "\n".join((pack, cube, public))
    for forbidden in (
        "ALLOCATE",
        "ALLOT",
        "FREE",
        "RESIZE",
        "RTAPT-",
        "RTE-",
        "PRESENT-",
        "UART-",
        "FB-PAL",
    ):
        assert forbidden not in converter
