#!/usr/bin/env python3
"""The picture and media widgets, cell by cell.

A picture's block cells are checked against a Python model: the copy
media/picture.f makes (test_media's model), centred in the area, blended
onto the background, and mapped to the palette by tui/color.f's own
nearest-colour rule.  Each placeholder says why the picture is not shown.
The media widget is checked for every view it chooses, for the memory it
holds, and for giving all of it back.  Every run checks a balanced stack.
"""

from __future__ import annotations

import io
import shutil
import re
import struct

import pytest
from PIL import Image

import qoi_codec
from forth_dependencies import dependency_order
from test_media import _gradient, _interlaced, _noise, _png, _scaled
from test_uidl_collection_snapshot import AK, KDOS_PATH, _load_forth_lines
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime

FILE_BYTES = 1 << 18
HALF_BLOCK = 0x2580
FG, BG = 7, 4                       # the style the widgets draw in
TOP, LEFT = 1, 2                    # where their region starts on screen

SETUP = r"""
VARIABLE MW-SCR  VARIABLE MW-RGN  VARIABLE MW-W
VARIABLE MW-DEPTH
262144 XBUF MW-FILE
CREATE MW-SRC-MEM MEDSRC-SIZE 7 + ALLOT
: MW-SRC  MW-SRC-MEM 7 + -8 AND ;
CREATE MW-MSRC-MEM MSRC-SIZE 7 + ALLOT
: MW-MSRC  MW-MSRC-MEM 7 + -8 AND ;
: MW-ALLOC  ( bytes ctx -- addr|0 )  DROP ALLOCATE IF DROP 0 THEN ;
: MW-FREE  ( addr bytes ctx -- )  2DROP FREE ;
: MW-MSRC-INIT  ( budget -- )
    >R ['] MW-ALLOC ['] MW-FREE 0 R> MW-MSRC MSRC-INIT ;
: MW-RAM-VFS  ( -- vfs )
    524288 A-XMEM ARENA-NEW IF -1 THROW THEN
    VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN ;
VARIABLE MW-V
\ Write U bytes of MW-FILE as the file PATH in the VFS.
: MW-PUT  ( u path-a path-u -- )
    2DUP MW-V @ VFS-CREATE 0= IF -101 THROW THEN
    VFS-FF-WRITE MW-V @ VFS-OPEN? ?DUP IF THROW THEN
    DUP MW-FILE 3 PICK ROT VFS-WRITE-EXACT IF -102 THROW THEN
    VFS-CLOSE DROP ;
\ Every cell of the region, one per line.
: MW-DUMP  ( rows cols -- )
    SWAP 0 ?DO
        DUP 0 ?DO
            ." CELL " J . I .
            J TOP-ROW + I LEFT-COL + SCR-GET
            DUP CELL-CP@ . DUP CELL-FG@ . DUP CELL-BG@ . CELL-ATTRS@ . CR
        LOOP
    LOOP DROP ;
\ The style the widgets draw over, saved as the UIDL paint path saves it.
: MW-STYLE  ( -- )  FG-INDEX BG-INDEX 0 DRW-STYLE! DRW-STYLE-SAVE ;
: MW-DRAW  ( widget -- )  MW-STYLE WDG-DRAW ;
\ Service a widget until nothing is pending; leave the slices taken.
: MW-PICT-SERVICE  ( widget -- slices )
    0 BEGIN OVER PICT-PENDING? WHILE
        1+ PICT-STEP-PIXELS 2 PICK PICT-SERVICE DROP
    REPEAT NIP ;
: MW-MEDIA-SERVICE  ( widget -- slices )
    0 BEGIN OVER MEDIA-PENDING? WHILE 1+ OVER MEDIA-SERVICE DROP REPEAT NIP ;
CREATE MW-EV-MEM 31 ALLOT
: MW-EV  MW-EV-MEM 7 + -8 AND ;
"""


def _runtime(setup_data: bytes = b"", roots: tuple[str, ...] = ("tui/widgets/media.f",)):
    runtime = MegaForthRuntime(
        memory=create_one_core_address_space(external_size=128 << 20, hbw_size=1 << 20),
        execution_backend="native",
    )
    runtime.evaluate(KDOS_PATH.read_bytes(), source_name="kdos.f")
    runtime.evaluate(b"ENTER-USERLAND", source_name="media-widget-userland")
    source = []
    for module in dependency_order(AK, roots):
        source.extend(_load_forth_lines(AK / module))
    runtime.evaluate(("\n".join(source) + "\n").encode(),
                     source_name="media-widget-closure", step_budget=800_000_000)
    constants = (
        f"{TOP} CONSTANT TOP-ROW  {LEFT} CONSTANT LEFT-COL  "
        f"{FG} CONSTANT FG-INDEX  {BG} CONSTANT BG-INDEX"
    )
    runtime.evaluate((constants + "\n" + SETUP).encode(), source_name="media-widget-setup")
    runtime.drain_uart_output()
    if setup_data:
        runtime.execute("MW-FILE")
        runtime.memory.write_bytes(runtime.main_context.data.pop(), setup_data)
    return runtime


def _run(lines: list[str], data: bytes = b"", max_steps: int = 400_000_000,
         roots: tuple[str, ...] = ("tui/widgets/media.f",)) -> str:
    assert len(data) <= FILE_BYTES
    runtime = _runtime(data, roots)
    program = ["DEPTH MW-DEPTH !", *lines,
               'DEPTH MW-DEPTH @ - ." @D:" . CR']
    try:
        runtime.evaluate(("\n".join(program) + "\n").encode(),
                         source_name="media-widget-proof", step_budget=max_steps)
    except Exception as error:
        raise AssertionError(runtime.uart_output.decode(errors="replace")[-6000:]) from error
    output = runtime.drain_uart_output().decode("utf-8", errors="replace")
    assert "@D:0 " in output, output[-3000:]
    return output


def _cells(output: str) -> dict[tuple[int, int], tuple[int, int, int, int]]:
    return {
        (int(r), int(c)): (int(cp), int(fg), int(bg), int(attrs))
        for r, c, cp, fg, bg, attrs in re.findall(
            r"CELL (\d+) (\d+) (\d+) (\d+) (\d+) (\d+)", output)
    }


def _row_text(cells, row: int, cols: int) -> str:
    return "".join(chr(cells[(row, c)][0]) for c in range(cols)).strip()


# --------------------------------------------------------------------------
# tui/color.f, modelled exactly
# --------------------------------------------------------------------------

_CUBE = (0, 95, 135, 175, 215, 255)
_BASE16 = (0x000000, 0xAA0000, 0x00AA00, 0xAA5500, 0x0000AA, 0xAA00AA,
           0x00AAAA, 0xAAAAAA, 0x555555, 0xFF5555, 0x55FF55, 0xFFFF55,
           0x5555FF, 0xFF55FF, 0x55FFFF, 0xFFFFFF)


def _snap(value: int) -> tuple[int, int]:
    # _TC-CUBE-SNAP starts from a best distance of 999.
    best, best_distance = 0, 999
    for index, level in enumerate(_CUBE):
        distance = (level - value) ** 2
        if distance < best_distance:
            best, best_distance = index, distance
    return _CUBE[best], best


def _resolve(r: int, g: int, b: int) -> int:
    (rl, ri), (gl, gi), (bl, bi) = _snap(r), _snap(g), _snap(b)
    cube = (r - rl) ** 2 + (g - gl) ** 2 + (b - bl) ** 2
    average = (r + g + b) // 3
    best, best_distance = 0, 999999
    for index in range(24):
        distance = (index * 10 + 8 - average) ** 2
        if distance < best_distance:
            best, best_distance = index, distance
    level = best * 10 + 8
    gray = (level - r) ** 2 + (level - g) ** 2 + (level - b) ** 2
    return 232 + best if gray <= cube else 16 + 36 * ri + 6 * gi + bi


def _palette_rgb(index: int) -> tuple[int, int, int]:
    if index < 16:
        value = _BASE16[index]
        return value >> 16, (value >> 8) & 255, value & 255
    if index < 232:
        index -= 16
        return _CUBE[index // 36], _CUBE[index // 6 % 6], _CUBE[index % 6]
    level = (index - 232) * 10 + 8
    return level, level, level


def _expected_cells(rows, cols: int, cell_rows: int, bg: int = BG):
    """Every cell of a COLS by CELL_ROWS picture area, as the widget draws it."""

    width, height, pixels = _scaled(rows, cols, cell_rows * 2)
    left = (cols - width) // 2
    top = (cell_rows * 2 - height) // 2
    background = _palette_rgb(bg)

    def index(x: int, y: int) -> int:
        if not (0 <= x < width and 0 <= y < height):
            return bg
        r, g, b, a = pixels[(y * width + x) * 4:(y * width + x) * 4 + 4]
        if a == 0:
            return bg
        if a == 255:
            return _resolve(r, g, b)
        blend = [(c * a + base * (255 - a) + 127) // 255
                 for c, base in zip((r, g, b), background)]
        return _resolve(*blend)

    cells = {}
    for row in range(cell_rows):
        for col in range(cols):
            upper = index(col - left, 2 * row - top)
            lower = index(col - left, 2 * row + 1 - top)
            if upper == bg and lower == bg:
                cells[(row, col)] = (32, FG, bg, 0)
            else:
                cells[(row, col)] = (HALF_BLOCK, upper, lower, 0)
    return cells


def test_the_colour_model_matches_tui_color() -> None:
    samples = [(r, g, b) for r in (0, 30, 47, 48, 63, 64, 95, 115, 200, 255)
               for g in (0, 52, 128, 255) for b in (5, 60, 175)]
    lines = [f'{r} {g} {b} TUI-RESOLVE-COLOR ." RC=" .' for r, g, b in samples]
    lines += [f'{i} TUI-PALETTE>RGBA ." PAL=" .' for i in (0, 4, 9, 16, 59, 231, 232, 255)]
    output = _run(lines)
    resolved = [int(v) for v in re.findall(r"RC=(\d+)", output)]
    assert resolved == [_resolve(*s) for s in samples]
    palette = [int(v) for v in re.findall(r"PAL=(\d+)", output)]
    assert palette == [
        (r << 24) | (g << 16) | (b << 8) | 0xFF
        for r, g, b in map(_palette_rgb, (0, 4, 9, 16, 59, 231, 232, 255))
    ]


# --------------------------------------------------------------------------
# The picture widget
# --------------------------------------------------------------------------

def _picture_lines(size: int, rows: int, cols: int, *, alt: str = "alt",
                   service: bool = True) -> list[str]:
    lines = [
        "0 MW-MSRC-INIT",
        "80 24 SCR-NEW DUP MW-SCR ! SCR-USE",
        f"TOP-ROW LEFT-COL {rows} {cols} RGN-NEW MW-RGN !",
        "MW-RGN @ MW-MSRC PICT-NEW MW-W !",
        f"MW-FILE {size} MW-SRC MEDSRC-MEMORY",
        f'MW-SRC S" {alt}" MW-W @ PICT-SOURCE!',
        "MW-W @ MW-DRAW",
        '." PENDING=" MW-W @ PICT-PENDING? . ." WORK=" PICT-WORK? .',
    ]
    if service:
        lines += [
            'MW-W @ MW-PICT-SERVICE ." SLICES=" .',
            '." AFTER=" MW-W @ PICT-PENDING? . PICT-WORK? .',
            "MW-W @ MW-DRAW",
        ]
    lines.append(f"{rows} {cols} MW-DUMP")
    return lines


def _free_lines() -> list[str]:
    return [
        "MW-W @ PICT-FREE MW-RGN @ RGN-FREE",
        '." HELD=" MW-MSRC MSRC-HELD@ .',
    ]


@pytest.mark.parametrize(
    ("rows", "cell_rows", "cols"),
    (
        (_gradient(6, 4), 3, 8),        # smaller than the area: centred, not enlarged
        (_gradient(40, 30), 4, 10),     # scaled down by averaging
        (_noise(9, 23, 7), 5, 12),      # tall: letterboxed at the sides
        ([[(255, 0, 0, 128), (0, 255, 0, 0)] * 3] * 4, 2, 6),  # blended, and holes
    ),
)
@pytest.mark.parametrize("encode", (qoi_codec.encode, _png), ids=("qoi", "png"))
def test_a_picture_draws_the_model_in_blocks(rows, cell_rows, cols, encode) -> None:
    data = encode(rows)
    output = _run(_picture_lines(len(data), cell_rows, cols) + _free_lines(), data)
    assert "PENDING=-1 WORK=-1 " in output and "AFTER=0 0 " in output, output[-2000:]
    assert _cells(output) == _expected_cells(rows, cols, cell_rows)
    assert "HELD=0 " in output


def test_a_large_picture_decodes_in_several_slices() -> None:
    rows = _gradient(200, 180)
    data = qoi_codec.encode(rows)
    output = _run(_picture_lines(len(data), 4, 10) + _free_lines(), data)
    slices = int(re.search(r"SLICES=(\d+)", output).group(1))
    # 36,000 source pixels at about 16,384 a slice, at least one row each.
    assert slices == 3, output[-2000:]
    assert _cells(output) == _expected_cells(rows, 10, 4)


def _labels(output: str, rows: int, cols: int) -> list[str]:
    cells = _cells(output)
    return [text for text in (_row_text(cells, r, cols) for r in range(rows)) if text]


def test_a_picture_says_it_is_loading_until_it_is_ready() -> None:
    data = qoi_codec.encode(_gradient(30, 20))
    output = _run(_picture_lines(len(data), 4, 30, alt="Sunset", service=False)
                  + ["MW-W @ PICT-FREE", '." WORK=" PICT-WORK? .'], data)
    assert _labels(output, 4, 30) == ["Sunset", "Loading the picture"]
    # Freeing a widget that was still decoding leaves no work behind.
    assert "WORK=0 " in output


@pytest.mark.parametrize(
    ("data", "message"),
    (
        (b"\x89PNG\r\n\x1a\n" + bytes(40), "The picture is damaged"),
        (b"GIF89a" + bytes(40), "This picture's format can't be shown yet"),
        (b"qoif" + struct.pack(">II", 0, 4) + bytes((4, 0)) + bytes(8),
         "The picture is damaged"),
        (qoi_codec.encode(_gradient(12, 8))[:-3], "The picture is damaged"),
    ),
)
def test_a_picture_that_cannot_be_shown_says_why(data, message) -> None:
    output = _run(_picture_lines(len(data), 3, 44, alt="photo.qoi") + _free_lines(), data)
    assert _labels(output, 3, 44) == ["photo.qoi", message], output[-2000:]
    assert "HELD=0 " in output


def test_a_picture_without_memory_says_so_and_holds_nothing() -> None:
    data = qoi_codec.encode(_gradient(40, 30))
    lines = _picture_lines(len(data), 3, 44, alt="") + _free_lines()
    lines[0] = "600 MW-MSRC-INIT"
    output = _run(lines, data)
    assert _labels(output, 3, 44) == ["Not enough memory to show the picture"]
    assert "HELD=0 " in output


def test_a_one_row_area_shows_the_message_without_the_alternative() -> None:
    data = qoi_codec.encode(_gradient(30, 20))
    output = _run(_picture_lines(len(data), 1, 30, alt="Sunset", service=False)
                  + ["MW-W @ PICT-FREE"], data)
    assert _labels(output, 1, 30) == ["Loading the picture"]


def _pillow(fmt: str, size=(37, 21)) -> bytes:
    image = Image.new("RGB" if fmt == "JPEG" else "RGBA", size, (200, 40, 90))
    out = io.BytesIO()
    image.save(out, fmt)
    return out.getvalue()


@pytest.mark.parametrize(("fmt", "number"), (("JPEG", 4),))
def test_a_picture_file_the_guest_cannot_decode_shows_its_format_and_size(
        fmt, number) -> None:
    """CELL decodes QOI and PNG.  A JPEG shows what it is, and decodes
    nothing, while a rich terminal that decodes it may take the file."""

    data = _pillow(fmt)
    output = _run(_picture_lines(len(data), 3, 44, alt="photo") + [
        '." FILE=" MW-W @ PICT-FILE@ ROT . SWAP . .',
        '." BYTES=" MW-W @ PICT-FILE-BYTES@ .',
    ] + _free_lines(), data)
    assert _labels(output, 3, 44) == ["photo", f"{fmt}, 37 × 21"], output[-2000:]
    assert "PENDING=0 WORK=0 " in output and "SLICES=0 " in output
    assert f"FILE={number} 37 21 " in output
    assert f"BYTES={len(data)} " in output
    assert "HELD=0 " in output


def test_a_picture_file_reads_as_it_is_from_its_source() -> None:
    data = qoi_codec.encode(_gradient(17, 9))
    output = _run([
        "CREATE MW-HEAD 8 ALLOT",
        ": MW-HEAD.  8 0 DO MW-HEAD I + C@ . LOOP ;",
        "0 MW-MSRC-INIT",
        "80 24 SCR-NEW DUP MW-SCR ! SCR-USE",
        "TOP-ROW LEFT-COL 3 20 RGN-NEW MW-RGN !",
        "MW-RGN @ MW-MSRC PICT-NEW MW-W !",
        '." NONE=" MW-W @ PICT-FILE@ ROT . SWAP . . MW-W @ PICT-FILE-BYTES@ .',
        f"MW-FILE {len(data)} MW-SRC MEDSRC-MEMORY",
        'MW-SRC S" sunset" MW-W @ PICT-SOURCE!',
        '." FILE=" MW-W @ PICT-FILE@ ROT . SWAP . .',
        # The file's bytes from offset 4: its width and height.
        'MW-HEAD 8 4 MW-W @ PICT-FILE-READ ." IOR=" .',
        '." HEAD=" MW-HEAD.',
        "0 0 0 MW-W @ PICT-SOURCE!",
        '." CLEARED=" MW-W @ PICT-FILE@ ROT . SWAP . .',
        '." GONE=" MW-HEAD 1 0 MW-W @ PICT-FILE-READ 0<> .',
        "MW-W @ PICT-FREE MW-RGN @ RGN-FREE",
    ], data)
    assert "NONE=0 0 0 0 " in output
    assert "FILE=2 17 9 " in output and "IOR=0 " in output
    assert "HEAD=0 0 0 17 0 0 0 9 " in output
    assert "CLEARED=0 0 0 " in output and "GONE=-1 " in output


def _claim_lines(size: int, cols: int = 30) -> list[str]:
    return [
        "0 MW-MSRC-INIT",
        "80 24 SCR-NEW DUP MW-SCR ! SCR-USE",
        f"TOP-ROW LEFT-COL 3 {cols} RGN-NEW MW-RGN !",
        "MW-RGN @ MW-MSRC PICT-NEW MW-W !",
        f"MW-FILE {size} MW-SRC MEDSRC-MEMORY",
        'MW-SRC S" sunset.qoi" MW-W @ PICT-SOURCE!',
    ]


def _split(output: str) -> list[str]:
    return output.split("|SPLIT|")


def test_a_picture_the_rich_side_takes_shows_what_it_is_and_decodes_nothing() -> None:
    """While the rich side shows a picture, or is taking it to show it,
    CELL shows its name and size beneath and decodes nothing.  Once the
    rich side lets go, the placeholder asks for service and CELL decodes
    and draws the picture."""

    rows = _gradient(30, 20)
    data = qoi_codec.encode(rows)
    output = _run(_claim_lines(len(data)) + [
        "-1 MW-W @ PICT-CLAIM!",
        "MW-W @ MW-DRAW",
        '." CLAIMED=" MW-W @ PICT-CLAIMED? . ." PENDING=" MW-W @ PICT-PENDING? .',
        '." WORK=" PICT-WORK? . ." HELD=" MW-MSRC MSRC-HELD@ .',
        "3 30 MW-DUMP",
        '." |SPLIT|"',
        "PICT-RELEASE-ALL",
        '." LAPSED=" MW-W @ PICT-CLAIMED? . MW-W @ PICT-PENDING? . PICT-WORK? .',
        'PICT-STEP-PIXELS MW-W @ PICT-SERVICE ." CHANGED=" . ." DIRTY=" MW-W @ WDG-DIRTY? .',
        "MW-W @ MW-DRAW",
        'MW-W @ MW-PICT-SERVICE ." SLICES=" .',
        "MW-W @ MW-DRAW",
        "3 30 MW-DUMP",
    ] + _free_lines() + ['." AFTER=" PICT-WORK? .'], data)
    claimed, released = _split(output)
    assert _labels(claimed, 3, 30) == ["sunset.qoi", "QOI, 30 × 20"]
    assert "CLAIMED=-1 PENDING=0 " in claimed and "WORK=-1 HELD=0 " in claimed
    assert "LAPSED=0 -1 -1 " in released and "CHANGED=-1 DIRTY=-1 " in released
    assert "SLICES=1 " in released
    assert _cells(released) == _expected_cells(rows, 30, 3)
    assert "HELD=0 " in released and "AFTER=0 " in released


def test_a_claim_stops_a_cell_copy_still_decoding_and_keeps_a_ready_one() -> None:
    rows = _gradient(200, 180)
    data = qoi_codec.encode(rows)
    output = _run(_claim_lines(len(data), 10) + [
        "MW-W @ MW-DRAW",
        '." STARTED=" MW-W @ PICT-PENDING? . MW-MSRC MSRC-HELD@ 0> .',
        "-1 MW-W @ PICT-CLAIM!",
        'PICT-STEP-PIXELS MW-W @ PICT-SERVICE ." CHANGED=" .',
        '." STOPPED=" MW-W @ PICT-PENDING? . ." HELD=" MW-MSRC MSRC-HELD@ .',
        "MW-W @ MW-DRAW",
        # Let go, decode the CELL copy, then claim again: the ready copy
        # stays for when CELL shows the picture once more.
        "PICT-RELEASE-ALL",
        "MW-W @ MW-PICT-SERVICE DROP MW-W @ MW-DRAW MW-W @ MW-PICT-SERVICE DROP",
        "MW-W @ MW-DRAW",
        '." READY=" MW-W @ PICT-CELL-COPY@ PIC-STATE@ .',
        "-1 MW-W @ PICT-CLAIM! MW-W @ MW-DRAW",
        '." KEPT=" MW-W @ PICT-CELL-COPY@ PIC-STATE@ . MW-W @ PICT-PENDING? .',
        "MW-W @ PICT-FREE MW-RGN @ RGN-FREE",
        '." FREED=" MW-MSRC MSRC-HELD@ . PICT-WORK? .',
    ], data)
    assert "STARTED=-1 -1 " in output and "CHANGED=-1 " in output
    assert "STOPPED=0 HELD=0 " in output
    assert "READY=2 " in output and "KEPT=2 0 " in output
    assert "FREED=0 0 " in output


def test_a_new_source_is_no_longer_claimed() -> None:
    data = qoi_codec.encode(_gradient(30, 20))
    output = _run(_claim_lines(len(data)) + [
        "-1 MW-W @ PICT-CLAIM! MW-W @ MW-DRAW",
        '." BEFORE=" MW-W @ PICT-CLAIMED? . PICT-WORK? .',
        'MW-SRC S" again.qoi" MW-W @ PICT-SOURCE!',
        '." AFTER=" MW-W @ PICT-CLAIMED? .',
        "MW-W @ MW-DRAW",
        '." DECODING=" MW-W @ PICT-PENDING? .',
    ] + _free_lines() + ['." WORK=" PICT-WORK? .'], data)
    assert "BEFORE=-1 -1 " in output and "AFTER=0 " in output
    assert "DECODING=-1 " in output and "WORK=0 " in output


def test_a_picture_of_a_format_the_rich_side_takes_shows_what_it_is_first() -> None:
    """With QOI taken by the rich side, a new QOI picture draws its label at
    once and starts no CELL copy.  A capture that claims it keeps it so; a
    picture the rich side then does not take is drawn from its CELL copy at
    the next pass, and is never guessed again."""

    rows = _gradient(30, 20)
    data = qoi_codec.encode(rows)
    taken = "1 PIC-F-QOI 1- LSHIFT PICT-RICH-FORMATS!"
    output = _run(_claim_lines(len(data)) + [
        taken,
        "MW-W @ MW-DRAW",
        '." FIRST=" MW-MSRC MSRC-HELD@ . MW-W @ PICT-CELL-COPY@ .',
        "3 30 MW-DUMP",
        '." |SPLIT|"',
        # Taken: the claim keeps the label and asks for no service.
        "-1 MW-W @ PICT-CLAIM!",
        '." TAKEN=" MW-W @ PICT-PENDING? .',
        '." |SPLIT|"',
        # Not taken after all: the next pass draws it from its CELL copy.
        "0 MW-W @ PICT-CLAIM!",
        'PICT-STEP-PIXELS MW-W @ PICT-SERVICE ." CHANGED=" .',
        "MW-W @ MW-DRAW",
        'MW-W @ MW-PICT-SERVICE ." SLICES=" .',
        "MW-W @ MW-DRAW",
        "3 30 MW-DUMP",
        '." |SPLIT|"',
        # With no format taken, a new picture is drawn from its CELL copy.
        "PICT-RELEASE-ALL",
        'MW-SRC S" again.qoi" MW-W @ PICT-SOURCE!',
        "MW-W @ MW-DRAW",
        '." AGAIN=" MW-W @ PICT-PENDING? .',
    ] + _free_lines() + ['." WORK=" PICT-WORK? .'], data)
    first, taken_out, declined, released = _split(output)
    assert "FIRST=0 0 " in first
    assert _labels(first, 3, 30) == ["sunset.qoi", "QOI, 30 × 20"]
    assert "TAKEN=0 " in taken_out
    assert "CHANGED=-1 " in declined and "SLICES=1 " in declined
    assert _cells(declined) == _expected_cells(rows, 30, 3)
    assert "AGAIN=-1 " in released and "WORK=0 " in released


def test_an_unvisited_first_label_gives_way_to_the_cell_copy() -> None:
    """A guessed label no capture claims by the next pass is redrawn from the
    CELL copy, once: the widget does not guess again."""

    data = qoi_codec.encode(_gradient(30, 20))
    output = _run(_claim_lines(len(data)) + [
        "1 PIC-F-QOI 1- LSHIFT PICT-RICH-FORMATS!",
        "MW-W @ MW-DRAW",
        'PICT-STEP-PIXELS MW-W @ PICT-SERVICE ." CHANGED=" .',
        "MW-W @ MW-DRAW",
        '." DECODING=" MW-W @ PICT-PENDING? . MW-W @ PICT-CELL-COPY@ 0<> .',
        "PICT-RELEASE-ALL",
    ] + _free_lines() + ['." WORK=" PICT-WORK? .'], data)
    assert "CHANGED=-1 " in output and "DECODING=-1 -1 " in output
    assert "WORK=0 " in output


def _rich_lines(mw: int, mh: int, tag: str) -> list[str]:
    return [
        f'{mw} {mh} MW-W @ PICT-RICH-ASK ." {tag}ASK=" .',
        f'." {tag}PENDING=" MW-W @ PICT-PENDING? .',
        f'MW-W @ MW-PICT-SERVICE ." {tag}SLICES=" .',
        f'MW-W @ PICT-RICH@ DUP ." {tag}REC=" . DUP PIC-STATE@ ." {tag}STATE=" .',
        f'DUP PIC-WIDTH@ ." {tag}W=" . PIC-HEIGHT@ ." {tag}H=" .',
    ]


def _field(output: str, name: str) -> int:
    return int(re.search(rf"(?<![A-Z]){name}=(-?\d+)", output).group(1))


def test_a_rich_copy_decodes_after_the_cell_copy_at_the_size_asked() -> None:
    rows = _gradient(60, 40)
    data = qoi_codec.encode(rows)
    output = _run(_picture_lines(len(data), 4, 10)
                  + _rich_lines(30, 30, "A") + _rich_lines(30, 30, "B")
                  + _rich_lines(12, 30, "C")
                  + ['." ST=" PIC-ST-READY .',
                     'MW-SRC S" alt" MW-W @ PICT-SOURCE!',
                     '." GONE=" MW-W @ PICT-RICH@ .']
                  + _free_lines(), data)
    # The CELL copy is unchanged by a rich one.
    assert _cells(output) == _expected_cells(rows, 10, 4)
    ready = _field(output, "ST")
    for tag, bound in (("A", (30, 30)), ("C", (12, 30))):
        assert _field(output, f"{tag}ASK") == -1
        assert _field(output, f"{tag}PENDING") == -1
        assert _field(output, f"{tag}STATE") == ready
        width, height, pixels = _scaled(rows, *bound)
        assert (_field(output, f"{tag}W"), _field(output, f"{tag}H")) == (width, height)
    # The bound asked before keeps the copy there is.
    assert _field(output, "BASK") == -1 and _field(output, "BPENDING") == 0
    assert _field(output, "BSLICES") == 0
    assert _field(output, "BREC") == _field(output, "AREC")
    assert _field(output, "GONE") == 0
    assert "HELD=0 " in output


def test_each_source_is_a_new_revision_that_every_copy_shares() -> None:
    data = qoi_codec.encode(_gradient(60, 40))
    output = _run(_picture_lines(len(data), 4, 10) + [
        '." R1=" MW-W @ PICT-REVISION@ .',
        "30 30 MW-W @ PICT-RICH-ASK DROP MW-W @ MW-PICT-SERVICE DROP",
        "12 30 MW-W @ PICT-RICH-ASK DROP MW-W @ MW-PICT-SERVICE DROP",
        '." R2=" MW-W @ PICT-REVISION@ .',
        'MW-SRC S" alt" MW-W @ PICT-SOURCE!',
        '." R3=" MW-W @ PICT-REVISION@ .',
        "MW-RGN @ MW-MSRC PICT-NEW",
        '." FRESH=" DUP PICT-REVISION@ .',
        'MW-SRC S" alt" 3 PICK PICT-SOURCE!',
        '." OTHER=" DUP PICT-REVISION@ . PICT-FREE',
    ] + _free_lines(), data)
    first = _field(output, "R1")
    # Copies of one picture at any size keep its revision; the same source
    # given again is another picture, and so is any other widget's.
    assert first > 0 and _field(output, "R2") == first
    assert _field(output, "R3") > first
    assert _field(output, "FRESH") == 0
    assert _field(output, "OTHER") > _field(output, "R3")
    assert "HELD=0 " in output


def test_a_rich_copy_holds_the_models_pixels() -> None:
    rows = _noise(23, 17, 3)
    data = qoi_codec.encode(rows)
    lines = _picture_lines(len(data), 3, 8) + [
        "20 9 MW-W @ PICT-RICH-ASK DROP",
        "MW-W @ MW-PICT-SERVICE DROP",
    ]
    runtime = _runtime(data)
    program = ["DEPTH MW-DEPTH !", *lines]
    runtime.evaluate(("\n".join(program) + "\n").encode(),
                     source_name="rich-copy-bytes", step_budget=400_000_000)
    runtime.execute("MW-W")
    widget = runtime.memory.read64(runtime.main_context.data.pop())
    runtime.main_context.data.push(widget)
    runtime.execute("PICT-RICH@")
    pic = runtime.main_context.data.pop()
    runtime.main_context.data.push(pic)
    runtime.execute("PIC-PIXELS")
    length = runtime.main_context.data.pop()
    address = runtime.main_context.data.pop()
    width, height, pixels = _scaled(rows, 20, 9)
    assert runtime.memory.read_bytes(address, length) == pixels
    runtime.evaluate(b"MW-W @ PICT-FREE MW-RGN @ RGN-FREE DEPTH MW-DEPTH @ - .\n",
                     source_name="rich-copy-free")
    assert runtime.drain_uart_output().decode().split()[-1] == "0"


def test_a_rich_copy_without_memory_fails_and_holds_nothing() -> None:
    data = qoi_codec.encode(_gradient(200, 180))
    lines = _picture_lines(len(data), 4, 10) + [
        '200 180 MW-W @ PICT-RICH-ASK ." ASK=" .',
        '." P=" MW-W @ PICT-PENDING? . MW-W @ PICT-RICH@ PIC-STATE@ ." S=" .',
        'MW-W @ PICT-RICH@ PIC-REASON@ ." R=" .',
        '." FAILED=" PIC-ST-FAILED . ." MEMORY=" PIC-R-MEMORY .',
    ] + _free_lines()
    lines[0] = "60000 MW-MSRC-INIT"
    output = _run(lines, data)
    assert _cells(output) == _expected_cells(_gradient(200, 180), 10, 4)
    assert _field(output, "ASK") == -1 and _field(output, "P") == 0
    assert _field(output, "S") == _field(output, "FAILED")
    assert _field(output, "R") == _field(output, "MEMORY")
    assert "HELD=0 " in output


def test_nothing_shown_takes_no_rich_copy() -> None:
    output = _run([
        "0 MW-MSRC-INIT",
        "80 24 SCR-NEW DUP MW-SCR ! SCR-USE",
        "TOP-ROW LEFT-COL 3 8 RGN-NEW MW-RGN !",
        "MW-RGN @ MW-MSRC PICT-NEW MW-W !",
        '40 30 MW-W @ PICT-RICH-ASK ." ASK=" . ." REC=" MW-W @ PICT-RICH@ .',
    ] + _free_lines())
    assert _field(output, "ASK") == 0 and _field(output, "REC") == 0
    assert "HELD=0 " in output


# --------------------------------------------------------------------------
# The media widget
# --------------------------------------------------------------------------

def _media_lines(budget: int = 0) -> list[str]:
    return [
        f"{budget} MW-MSRC-INIT",
        "MW-RAM-VFS MW-V !",
        "80 24 SCR-NEW DUP MW-SCR ! SCR-USE",
        "TOP-ROW LEFT-COL 6 36 RGN-NEW MW-RGN !",
        "MW-RGN @ MW-MSRC MEDIA-NEW MW-W !",
    ]


def _open(path: str) -> str:
    return f'S" {path}" MW-V @ MW-W @ MEDIA-OPEN-VFS ." IOR=" .'


def _state() -> str:
    return ('." VIEW=" MW-W @ MEDIA-VIEW@ . ." KIND=" MW-W @ MEDIA-KIND@ . '
            '." NOTE=" MW-W @ MEDIA-NOTE@ . ." HELD=" MW-MSRC MSRC-HELD@ .')


VIEW_NONE, VIEW_PICTURE, VIEW_TEXT, VIEW_FACTS = range(4)
NOTE_NONE, NOTE_NO_VIEW, NOTE_MEMORY, NOTE_READ = range(4)
BINARY, TEXT, HTML, QOI, PNG, JPEG = range(6)


def test_text_is_shown_whole_in_a_buffer_sized_to_it() -> None:
    text = bytes(65 + i % 26 for i in range(5000))
    output = _run(_media_lines() + [
        'S" docs" MW-V @ VFS-MKDIR THROW',
        '5000 S" /docs/long.txt" MW-PUT',
        _open("/docs/long.txt"), _state(),
        "MW-W @ MEDIA-TEXT@ TXTA-GET-TEXT",
        '." LEN=" DUP . OVER C@ ." FIRST=" . 2DUP + 1- C@ ." LAST=" . DROP FREE',
        '." NAME=" MW-W @ MEDIA-NAME@ TYPE CR',
        "MW-W @ MEDIA-CLEAR", '." CLEARED=" MW-MSRC MSRC-HELD@ .',
        "MW-W @ MEDIA-FREE",
    ], text)
    assert "IOR=0 " in output
    assert f"VIEW={VIEW_TEXT} KIND={TEXT} NOTE={NOTE_NONE} " in output
    # The whole file, past the 4096 bytes the old preview kept, and its path.
    assert "HELD=5014 " in output and "LEN=5000 " in output, output[-2000:]
    assert f"FIRST={text[0]} " in output and f"LAST={text[-1]} " in output
    assert "NAME=long.txt" in output and "CLEARED=0 " in output


def test_text_drawn_while_hidden_shows_as_if_never_hidden() -> None:
    """A preview behind another tab has no cells; drawing it there must not
    scroll its text away, so the tab, once shown, shows what a view never
    hidden shows: the end of the text, where loading leaves the caret."""
    text = b"".join(b"line %d\n" % n for n in range(1, 11))
    output = _run(_media_lines() + [
        f'{len(text)} S" /ten.txt" MW-PUT',
        _open("/ten.txt"),
        "TOP-ROW LEFT-COL 0 0 MW-RGN @ RGN-BOUNDS!", "MW-W @ MW-DRAW",
        "TOP-ROW LEFT-COL 6 36 MW-RGN @ RGN-BOUNDS!", "MW-W @ MW-DRAW",
        '." HIDDEN-THEN-SHOWN" CR', "6 36 MW-DUMP",
        "MW-W @ MEDIA-CLEAR", _open("/ten.txt"), "MW-W @ MW-DRAW",
        '." NEVER-HIDDEN" CR', "6 36 MW-DUMP",
        "MW-W @ MEDIA-FREE",
    ], text)
    hidden, never = output.split("HIDDEN-THEN-SHOWN")[1].split("NEVER-HIDDEN")
    rows = [[_row_text(_cells(part), row, 36) for row in range(6)]
            for part in (hidden, never)]
    assert rows[0] == rows[1] == [f"line {n}" for n in range(6, 11)] + [""]


def test_text_the_memory_refuses_shows_why_instead_of_cutting_it() -> None:
    output = _run(_media_lines(budget=1000) + [
        '3000 S" /long.txt" MW-PUT',
        _open("/long.txt"), _state(),
        "MW-W @ MW-DRAW", "6 36 MW-DUMP",
        "MW-W @ MEDIA-FREE", '." FREED=" MW-MSRC MSRC-HELD@ .',
    ], b"x" * 3000)
    assert f"VIEW={VIEW_FACTS} KIND={TEXT} NOTE={NOTE_MEMORY} HELD=9 " in output
    assert _labels(output, 6, 36) == [
        "long.txt", "text, 2K", "Not enough memory to show this file"]
    assert "FREED=0 " in output


def test_a_kind_without_a_view_shows_its_facts() -> None:
    output = _run(_media_lines() + [
        '7 S" /blob.bin" MW-PUT',
        _open("/blob.bin"), _state(),
        "MW-W @ MW-DRAW", "6 36 MW-DUMP",
        '." VIEWW=" MW-W @ MEDIA-VIEW-WIDGET@ .',
        "MW-W @ MEDIA-FREE",
    ], b"\x00\x01\x02\x03\x04\x05\x06")
    assert f"VIEW={VIEW_FACTS} KIND={BINARY} NOTE={NOTE_NO_VIEW} " in output
    assert _labels(output, 6, 36) == [
        "blob.bin", "binary data, 7 bytes", "No preview for this kind of file yet"]
    assert "VIEWW=0 " in output


def test_a_file_that_cannot_be_opened_says_so() -> None:
    output = _run(_media_lines() + [
        _open("/nowhere/missing.txt"), _state(),
        "MW-W @ MW-DRAW", "6 36 MW-DUMP",
        "MW-W @ MEDIA-FREE", '." FREED=" MW-MSRC MSRC-HELD@ .',
    ])
    assert re.search(r"IOR=-?[1-9]\d* ", output), output[-2000:]
    assert f"VIEW={VIEW_FACTS} KIND=-1 NOTE={NOTE_READ} " in output
    assert _labels(output, 6, 36) == ["missing.txt", "The file could not be read"]
    assert "FREED=0 " in output


def test_a_picture_file_decodes_from_the_service_and_gives_everything_back() -> None:
    rows = _gradient(50, 40)
    data = qoi_codec.encode(rows)
    output = _run(_media_lines() + [
        'S" pictures" MW-V @ VFS-MKDIR THROW',
        f'{len(data)} S" /pictures/sunset.qoi" MW-PUT',
        _open("/pictures/sunset.qoi"), _state(),
        '." BEFORE=" MW-W @ MEDIA-PENDING? .',
        "MW-W @ MW-DRAW",
        '." DRAWN=" MW-W @ MEDIA-PENDING? .',
        'MW-W @ MW-MEDIA-SERVICE ." SLICES=" .',
        '." DONE=" MW-W @ MEDIA-PENDING? . PICT-WORK? .',
        '." DIRTY=" MW-W @ WDG-DIRTY? .',
        "MW-W @ MW-DRAW", "6 36 MW-DUMP",
        '." AGAIN=" MW-W @ MEDIA-SERVICE .',
        "MW-W @ MEDIA-CLEAR", '." CLEARED=" MW-MSRC MSRC-HELD@ .',
        "MW-W @ MEDIA-FREE", '." FREED=" MW-MSRC MSRC-HELD@ .',
    ], data)
    assert f"VIEW={VIEW_PICTURE} KIND={QOI} NOTE={NOTE_NONE} " in output
    # Nothing decodes until the picture is drawn, which asks for its copy.
    assert "BEFORE=0 DRAWN=-1 " in output and "DONE=0 0 " in output, output[-2000:]
    assert "DIRTY=-1 " in output and "AGAIN=0 " in output
    assert _cells(output) == _expected_cells(rows, 36, 6)
    assert "CLEARED=0 " in output and "FREED=0 " in output


@pytest.mark.parametrize(("fmt", "kind"), (("JPEG", JPEG),))
def test_a_jpeg_file_is_shown_as_a_picture(fmt, kind) -> None:
    data = _pillow(fmt, (120, 80))
    output = _run(_media_lines() + [
        f'{len(data)} S" /photo.{fmt.lower()}" MW-PUT',
        _open(f"/photo.{fmt.lower()}"), _state(),
        '." VIEWW=" MW-W @ MEDIA-VIEW-WIDGET@ MW-W @ MEDIA-PICTURE@ = .',
        "MW-W @ MW-DRAW", "6 36 MW-DUMP",
        '." PENDING=" MW-W @ MEDIA-PENDING? .',
        "MW-W @ MEDIA-FREE", '." FREED=" MW-MSRC MSRC-HELD@ .',
    ], data)
    assert f"VIEW={VIEW_PICTURE} KIND={kind} NOTE={NOTE_NONE} " in output
    assert "VIEWW=-1 " in output and "PENDING=0 " in output
    assert _labels(output, 6, 36) == [f"photo.{fmt.lower()}", f"{fmt}, 120 × 80"]
    assert "FREED=0 " in output


def test_a_png_file_decodes_from_the_service_as_a_qoi_file_does() -> None:
    rows = _gradient(50, 40)
    data = _png(rows)
    output = _run(_media_lines() + [
        f'{len(data)} S" /photo.png" MW-PUT',
        _open("/photo.png"), _state(),
        "MW-W @ MW-DRAW",
        'MW-W @ MW-MEDIA-SERVICE ." SLICES=" .',
        "MW-W @ MW-DRAW", "6 36 MW-DUMP",
        "MW-W @ MEDIA-FREE", '." FREED=" MW-MSRC MSRC-HELD@ .',
    ], data)
    assert f"VIEW={VIEW_PICTURE} KIND={PNG} NOTE={NOTE_NONE} " in output, output[-2000:]
    assert _cells(output) == _expected_cells(rows, 36, 6)
    assert "FREED=0 " in output


def test_an_interlaced_png_shows_what_it_is() -> None:
    data = _interlaced(_png(_gradient(30, 20)))
    output = _run(_picture_lines(len(data), 3, 44, alt="photo") + _free_lines(), data)
    assert _labels(output, 3, 44) == ["photo", "PNG, 30 × 20"], output[-2000:]
    assert "HELD=0 " in output


def test_focus_and_keys_go_to_the_text_view() -> None:
    output = _run(_media_lines() + [
        '11 S" /a.txt" MW-PUT',
        _open("/a.txt"),
        "MW-W @ WDG-FOCUS-SET MW-W @ MW-DRAW",
        '." FOCUS=" MW-W @ MEDIA-TEXT@ WDG-FOCUSED? .',
        "MW-W @ WDG-FOCUS-CLR MW-W @ MW-DRAW",
        '." UNFOCUS=" MW-W @ MEDIA-TEXT@ WDG-FOCUSED? .',
        # Home moves the caret, which only the text area can consume.
        "MW-EV 24 0 FILL  KEY-T-SPECIAL MW-EV !  KEY-HOME MW-EV 8 + !",
        '." KEY=" MW-EV MW-W @ WDG-HANDLE . ." COL=" MW-W @ MEDIA-TEXT@ TXTA-CURSOR-COL .',
        "MW-W @ MEDIA-FREE",
    ], b"hello world")
    assert "FOCUS=-1 " in output and "UNFOCUS=0 " in output, output[-2000:]
    assert "KEY=-1 COL=0 " in output


@pytest.mark.parametrize(("reason", "message"), (
    ("PIC-R-DAMAGED", "The picture is damaged"),
    ("PIC-R-READ", "The picture could not be read"),
))
def test_a_picture_the_rich_side_could_not_send_says_why(reason, message) -> None:
    """When the rich side cannot send a picture because of the picture
    itself, the widget remembers why until it is given another source.  The
    rich side takes it no more, and CELL, which decodes no JPEG, says why in
    place of what the picture is.  Another source may be sent again."""

    data = _pillow("JPEG")
    output = _run(_picture_lines(len(data), 3, 44, alt="photo", service=False) + [
        "-1 MW-W @ PICT-CLAIM! MW-W @ MW-DRAW",
        '." TAKEN=" MW-W @ PICT-CLAIMED? . MW-W @ PICT-RICH-FAILED@ .',
        '." |SPLIT|"',
        f'." CODE=" {reason} .',
        f"{reason} MW-W @ PICT-RICH-FAILED!",
        '." FAILED=" MW-W @ PICT-CLAIMED? . MW-W @ PICT-PENDING? .',
        '." REASON=" MW-W @ PICT-RICH-FAILED@ .',
        'PICT-STEP-PIXELS MW-W @ PICT-SERVICE ." CHANGED=" .',
        "MW-W @ MW-DRAW",
        "3 44 MW-DUMP",
        '." |SPLIT|"',
        # A capture that does not take the picture keeps it failed.
        "0 MW-W @ PICT-CLAIM!",
        '." KEPT=" MW-W @ PICT-RICH-FAILED@ .',
        # Another source is a new picture, which the rich side may send.
        'MW-SRC S" again" MW-W @ PICT-SOURCE!',
        '." AGAIN=" MW-W @ PICT-RICH-FAILED@ .',
        "MW-W @ MW-DRAW",
        "3 44 MW-DUMP",
    ] + _free_lines(), data)
    taken, failed, again = _split(output)
    code = int(re.search(r"CODE=(-?\d+)", failed).group(1))
    assert code and "TAKEN=-1 0 " in taken, taken[-2000:]
    assert "FAILED=0 -1 " in failed and f"REASON={code} " in failed
    assert "CHANGED=-1 " in failed
    assert _labels(failed, 3, 44) == ["photo", message]
    assert f"KEPT={code} " in again and "AGAIN=0 " in again
    assert _labels(again, 3, 44) == ["again", "JPEG, 37 × 21"]
    assert "HELD=0 " in again


def test_a_qoi_picture_the_rich_side_could_not_send_shows_its_cell_copy() -> None:
    """CELL decodes QOI, so a QOI picture the rich side could not send is
    drawn from its CELL copy."""

    rows = _gradient(30, 20)
    data = qoi_codec.encode(rows)
    output = _run(_claim_lines(len(data)) + [
        "-1 MW-W @ PICT-CLAIM! MW-W @ MW-DRAW",
        "PIC-R-DAMAGED MW-W @ PICT-RICH-FAILED!",
        'PICT-STEP-PIXELS MW-W @ PICT-SERVICE ." CHANGED=" .',
        "MW-W @ MW-DRAW",
        'MW-W @ MW-PICT-SERVICE ." SLICES=" .',
        "MW-W @ MW-DRAW",
        "3 30 MW-DUMP",
    ] + _free_lines(), data)
    assert "CHANGED=-1 " in output and "SLICES=1 " in output, output[-2000:]
    assert _cells(output) == _expected_cells(rows, 30, 3)
    assert "HELD=0 " in output


# --------------------------------------------------------------------------
# Markdown documents
# --------------------------------------------------------------------------

VIEW_DOCUMENT, MARKDOWN = 4, 9
PATH_OK, PATH_EMPTY, PATH_SCHEME = 0, 1, 2

DOCUMENT = (
    b"# Notes\n\nSee [the other file](other.md) and [up](../up.md).\n\n"
    b"![A sunset](pics/sunset.qoi)\n\nThe end.\n"
)


def _document_lines(markdown: bytes, picture: bytes = b"") -> list[str]:
    """The picture as /docs/pics/sunset.qoi and the Markdown as
    /docs/readme.md, both from MW-FILE, the picture first."""

    lines = ['S" docs" MW-V @ VFS-MKDIR THROW', 'S" /docs" MW-V @ VFS-CD THROW',
             'S" pics" MW-V @ VFS-MKDIR THROW', 'S" /" MW-V @ VFS-CD THROW']
    if picture:
        lines.append(f'{len(picture)} S" /docs/pics/sunset.qoi" MW-PUT')
        lines.append(f"MW-FILE {len(picture)} + MW-FILE {len(markdown)} MOVE")
    lines.append(f'{len(markdown)} S" /docs/readme.md" MW-PUT')
    return lines


def test_a_markdown_file_shows_as_a_document_with_its_figures() -> None:
    """A Markdown file is a document, whose figure's picture comes from the
    document's folder and decodes from the service; clearing the widget
    gives everything back."""

    rows = _gradient(40, 24)
    picture = qoi_codec.encode(rows)
    output = _run(_media_lines() + _document_lines(DOCUMENT, picture) + [
        _open("/docs/readme.md"), _state(),
        '." VIEWW=" MW-W @ MEDIA-VIEW-WIDGET@ MW-W @ MEDIA-DOCUMENT@ = .',
        "MW-W @ MW-DRAW",
        '." PENDING=" MW-W @ MEDIA-PENDING? .',
        'MW-W @ MW-MEDIA-SERVICE ." SLICES=" .',
        "MW-W @ MW-DRAW", "6 36 MW-DUMP",
        "MW-W @ MEDIA-CLEAR", '." CLEARED=" MW-MSRC MSRC-HELD@ .',
        "MW-W @ MEDIA-FREE", '." FREED=" MW-MSRC MSRC-HELD@ .',
    ], picture + DOCUMENT)
    assert f"VIEW={VIEW_DOCUMENT} KIND={MARKDOWN} NOTE={NOTE_NONE} " in output
    assert "VIEWW=-1 " in output and "PENDING=-1 " in output, output[-2000:]
    assert int(re.search(r"SLICES=(\d+)", output).group(1)) >= 1
    cells = _cells(output)
    assert _row_text(cells, 0, 36) == "Notes"
    assert _row_text(cells, 2, 36) == "See the other file and up."
    # The figure's picture takes the view's height at most, and its first
    # two rows show below the paragraph.
    picture_cells = _expected_cells(rows, 36, 6)
    assert any(cell[0] == HALF_BLOCK for cell in picture_cells.values())
    for (row, col), cell in picture_cells.items():
        if row < 2:
            assert cells[(4 + row, col)] == cell, (row, col)
    assert "CLEARED=0 " in output and "FREED=0 " in output


FOLLOW_LINES = [
    ": MW-FOLLOWED  ( path-a path-u status ctx -- )",
    '    DROP ." FOLLOW=" . ." [" TYPE ." ]" CR ;',
]


def test_a_link_in_a_document_goes_to_the_owner_as_the_path_it_names() -> None:
    """A press on a link gives the owner the path it names, from the
    document's folder; a target with a scheme, or with no path, says why it
    names none; and a link to a heading stays with the view."""

    document = b"[go](other.md)\n\n# Notes\n"
    output = _run(_media_lines() + _document_lines(document) + FOLLOW_LINES + [
        _open("/docs/readme.md"),
        "' MW-FOLLOWED 0 MW-W @ MEDIA-FOLLOW!",
        "MW-W @ MW-DRAW",
        "MW-EV 24 0 FILL  KEY-T-MOUSE MW-EV !  KEY-MOUSE-LEFT MW-EV 8 + !",
        "TOP-ROW 16 LSHIFT LEFT-COL OR MW-EV 16 + !",
        'MW-EV MW-W @ WDG-HANDLE ." KEY=" . CR',
        'S" ../up.md" MW-W @ MEDIA-DOCUMENT@ DOCV-FOLLOW',
        'S" https://example.com/" MW-W @ MEDIA-DOCUMENT@ DOCV-FOLLOW',
        'S" sub/file.txt#part" MW-W @ MEDIA-DOCUMENT@ DOCV-FOLLOW',
        'S" ?only" MW-W @ MEDIA-DOCUMENT@ DOCV-FOLLOW',
        'S" #notes" MW-W @ MEDIA-DOCUMENT@ DOCV-FOLLOW',
        "MW-W @ MEDIA-FREE", '." FREED=" MW-MSRC MSRC-HELD@ .',
    ], document)
    followed = re.findall(r"FOLLOW=(\d+) \[([^\]]*)\]", output)
    assert "KEY=-1 " in output
    assert followed == [
        (str(PATH_OK), "/docs/other.md"), (str(PATH_OK), "/up.md"),
        (str(PATH_SCHEME), ""), (str(PATH_OK), "/docs/sub/file.txt"),
        (str(PATH_EMPTY), ""),
    ], output[-2000:]
    assert "FREED=0 " in output


def test_a_document_the_memory_refuses_shows_why() -> None:
    output = _run(_media_lines(budget=1000) + _document_lines(DOCUMENT) + [
        _open("/docs/readme.md"), _state(),
        "MW-W @ MW-DRAW", "6 36 MW-DUMP",
        "MW-W @ MEDIA-FREE", '." FREED=" MW-MSRC MSRC-HELD@ .',
    ], DOCUMENT)
    assert f"VIEW={VIEW_FACTS} KIND={MARKDOWN} NOTE={NOTE_MEMORY} " in output
    assert f"HELD={len('/docs/readme.md')} " in output
    assert _labels(output, 6, 36) == [
        "readme.md", f"Markdown document, {len(DOCUMENT)} bytes",
        "Not enough memory to show this file"]
    assert "FREED=0 " in output


# --------------------------------------------------------------------------
# PDF documents
# --------------------------------------------------------------------------

PDF_ROOTS = ("tui/widgets/media.f", "pdf/document.f")
PDF, NOTE_LOCKED = 10, 4


def _pdf() -> bytes:
    from test_pdf_document import pages_pdf
    return pages_pdf()


def test_a_pdf_shows_its_facts_until_its_reader_is_added_then_its_pages() -> None:
    """A PDF is a PDF document by its first bytes.  Without a reader for
    it, the widget shows its facts; with pdf/document.f's, it shows the
    document, its first page read from the service; clearing the widget
    gives everything back."""

    pdf = _pdf()
    output = _run(_media_lines() + [
        f'{len(pdf)} S" /paper.pdf" MW-PUT',
        _open("/paper.pdf"), _state(), "MW-W @ MW-DRAW", "6 36 MW-DUMP",
        '." @@READER" CR',
        "PDF-DOC-READER MEDIA-K-PDF MW-W @ MEDIA-READER!",
        _open("/paper.pdf"), _state(),
        "MW-W @ MW-DRAW",
        '." PENDING=" MW-W @ MEDIA-PENDING? .',
        'MW-W @ MW-MEDIA-SERVICE ." SLICES=" .',
        "MW-W @ MW-DRAW", "6 36 MW-DUMP",
        '." PARTS=" MW-W @ MEDIA-DOCUMENT@ DOCV-DOCUMENT@ DOC-PARTS .',
        "MW-W @ MEDIA-CLEAR", '." CLEARED=" MW-MSRC MSRC-HELD@ .',
        "MW-W @ MEDIA-FREE", '." FREED=" MW-MSRC MSRC-HELD@ .',
    ], pdf, max_steps=2_000_000_000, roots=PDF_ROOTS)
    facts, shown = output.split("@@READER")
    assert f"VIEW={VIEW_FACTS} KIND={PDF} NOTE={NOTE_NO_VIEW} " in facts
    assert _labels(facts, 6, 36) == [
        "paper.pdf", f"PDF document, {len(pdf) // 1024}K",
        "No preview for this kind of file yet"]
    assert f"VIEW={VIEW_DOCUMENT} KIND={PDF} NOTE={NOTE_NONE} " in shown
    assert "PENDING=-1 " in shown and "PARTS=4 " in shown, shown[-2000:]
    cells = _cells(shown)
    assert _row_text(cells, 0, 36) == "1 " + "\u2500" * 34
    assert _row_text(cells, 2, 36) == "A Title Here"
    assert "CLEARED=0 " in shown and "FREED=0 " in shown


def test_a_pdf_that_needs_a_password_says_so(tmp_path) -> None:
    if shutil.which("qpdf") is None:
        pytest.skip("qpdf is not installed")
    from test_pdf_crypt import encrypt
    pdf = encrypt(tmp_path, "128", "--use-aes=n", user="secret")
    output = _run(_media_lines() + [
        f'{len(pdf)} S" /locked.pdf" MW-PUT',
        "PDF-DOC-READER MEDIA-K-PDF MW-W @ MEDIA-READER!",
        _open("/locked.pdf"), _state(), "MW-W @ MW-DRAW", "6 36 MW-DUMP",
        "MW-W @ MEDIA-FREE", '." FREED=" MW-MSRC MSRC-HELD@ .',
    ], pdf, roots=PDF_ROOTS)
    assert "IOR=0 " in output
    assert f"VIEW={VIEW_FACTS} KIND={PDF} NOTE={NOTE_LOCKED} " in output
    assert _labels(output, 6, 36) == [
        "locked.pdf", f"PDF document, {_size(len(pdf))}",
        "The file is protected by a password"]
    assert "FREED=0 " in output


def _size(n: int) -> str:
    return f"{n} bytes" if n < 1024 else f"{n // 1024}K"


# --------------------------------------------------------------------------
# A document's contents
# --------------------------------------------------------------------------

HEADED = b"".join([
    b"# First\n\n", b"Text under the first heading.\n\n" * 3,
    b"## Second\n\n", b"Text under the second heading.\n\n" * 3,
    b"### Third\n\n", b"#### Too deep for the contents\n\n", b"Text.\n\n" * 6,
])

KEYS = [
    ": MW-CHAR  ( c -- )  MW-EV 24 0 FILL  KEY-T-CHAR MW-EV !  MW-EV 8 + !"
    "  MW-EV MW-W @ WDG-HANDLE .\" K=\" . ;",
    ": MW-SPECIAL  ( code -- )  MW-EV 24 0 FILL  KEY-T-SPECIAL MW-EV !  MW-EV 8 + !"
    "  MW-EV MW-W @ WDG-HANDLE .\" K=\" . ;",
    ": MW-TOP  ( -- )  .\" TOP=\" MW-W @ MEDIA-DOCUMENT@ DOCV-TOP@ SWAP . . CR ;",
    # The part the view's top lies in, and its place in that part.
    ": MW-AT  MW-W @ MEDIA-DOCUMENT@ DUP DOCV-TOP@ DROP SWAP DOCV-DOCUMENT@"
    "  2DUP DOC-PART-OF DUP .\" PART=\" . SWAP DOC-PART-FIRST - .\" PLACE=\" . CR ;",
]
OPEN, CLOSED = "\u25bc", "\u25b6"     # the tree's marks for a branch
SELECTED_BG = 7                       # the tree's selected row


def _shown(output: str, mark: str) -> str:
    """The cells dumped after MARK."""
    return output.split(mark)[1].split("@@END")[0]


def _rows(output: str, mark: str, count: int) -> list[str]:
    """The first COUNT rows dumped after MARK, as drawn."""
    cells = _cells(_shown(output, mark))
    return ["".join(chr(cells[(r, c)][0]) for c in range(36)).rstrip()
            for r in range(count)]


def _selected(output: str, mark: str) -> list[int]:
    """The rows dumped after MARK that are drawn selected."""
    cells = _cells(_shown(output, mark))
    return sorted({r for (r, c), cell in cells.items() if cell[2] == SELECTED_BG})


def test_a_documents_contents_show_as_a_tree_and_go_to_an_entry() -> None:
    """The key c shows a document's contents, its headings of levels 1 to
    3, as a tree in place of the document: each heading under the one
    above it that is less deep, every branch open and the first chosen.
    Left closes the chosen branch, Enter goes to the chosen heading and
    shows the document, c shows the contents again as they were left, and
    Escape shows the document again where it was.  A file with no
    contents keeps showing itself."""

    output = _run(_media_lines() + KEYS + [
        f'{len(HEADED)} S" /notes.md" MW-PUT',
        _open("/notes.md"), "MW-W @ WDG-FOCUS-SET MW-W @ MW-DRAW", "MW-TOP",
        "99 MW-CHAR", '." VIEW=" MW-W @ MEDIA-VIEW@ . CR',
        "MW-W @ MW-DRAW", '." @@TREE" CR', "6 36 MW-DUMP", '." @@END" CR',
        "KEY-DOWN MW-SPECIAL KEY-LEFT MW-SPECIAL",
        "MW-W @ MW-DRAW", '." @@CLOSED" CR', "6 36 MW-DUMP", '." @@END" CR',
        "KEY-ENTER MW-SPECIAL", '." VIEW=" MW-W @ MEDIA-VIEW@ . CR',
        "MW-W @ MW-DRAW", "MW-TOP",
        "99 MW-CHAR MW-W @ MW-DRAW", '." @@AGAIN" CR', "6 36 MW-DUMP", '." @@END" CR',
        "KEY-ESC MW-SPECIAL", '." VIEW=" MW-W @ MEDIA-VIEW@ . CR', "MW-TOP",
        "MW-W @ MEDIA-CLEAR", '." CLEARED=" MW-MSRC MSRC-HELD@ .',
        # A document with no headings has no contents to show.
        'S" Plain." MW-FILE SWAP MOVE  6 S" /plain.md" MW-PUT', _open("/plain.md"),
        '." @@PLAIN" CR 99 MW-CHAR', '." VIEW=" MW-W @ MEDIA-VIEW@ . CR',
        "MW-W @ MEDIA-FREE",
    ], HEADED)
    views = re.findall(r"VIEW=(\d+)", output)
    assert views == ["5", str(VIEW_DOCUMENT), str(VIEW_DOCUMENT), str(VIEW_DOCUMENT)], \
        output[-2000:]
    assert "K=0 " in output.split("@@PLAIN")[1]
    assert _rows(output, "@@TREE", 4) == [
        f"{OPEN} First", f"  {OPEN} Second", "      Third", ""]
    assert _selected(output, "@@TREE") == [0]
    assert _rows(output, "@@CLOSED", 3) == [f"{OPEN} First", f"  {CLOSED} Second", ""]
    assert _selected(output, "@@CLOSED") == [1]
    assert _rows(output, "@@AGAIN", 3) == _rows(output, "@@CLOSED", 3)
    assert _selected(output, "@@AGAIN") == [1]
    tops = re.findall(r"TOP=(\d+) (\d+)", output)
    second = HEADED.split(b"\n\n").index(b"## Second")
    assert tops[0] == ("0", "0") and tops[1] == (str(second), "0") and tops[2] == tops[1]
    assert re.findall(r"K=(-?\d+)", output.split("@@PLAIN")[0]) == ["-1"] * 6
    assert "CLEARED=0 " in output


SKIPPED = b"# A\n\n### B\n\n## C\n\n# D\n\nText.\n"


def test_an_entry_below_a_skipped_level_is_under_the_entry_above_it() -> None:
    """A heading that skips a level is under the heading above it that is
    less deep, beside the entries at the level it skipped."""

    output = _run(_media_lines() + KEYS + [
        f'{len(SKIPPED)} S" /skipped.md" MW-PUT', _open("/skipped.md"),
        "MW-W @ WDG-FOCUS-SET 99 MW-CHAR MW-W @ MW-DRAW",
        '." @@TREE" CR', "6 36 MW-DUMP", '." @@END" CR',
        "MW-W @ MEDIA-FREE",
    ], SKIPPED)
    assert _rows(output, "@@TREE", 5) == [f"{OPEN} A", "    B", "    C", "  D", ""]


def test_a_pdfs_contents_go_to_a_page_not_read_yet() -> None:
    """A PDF without an outline has its pages as contents; choosing one
    reads that page alone and shows it from its top."""

    pdf = _pdf()
    output = _run(_media_lines() + KEYS + [
        f'{len(pdf)} S" /paper.pdf" MW-PUT',
        "PDF-DOC-READER MEDIA-K-PDF MW-W @ MEDIA-READER!",
        _open("/paper.pdf"), "MW-W @ WDG-FOCUS-SET",
        "MW-W @ MW-DRAW MW-W @ MW-MEDIA-SERVICE DROP MW-W @ MW-DRAW",
        "99 MW-CHAR MW-W @ MW-DRAW", '." @@LIST" CR', "6 36 MW-DUMP", '." @@END" CR',
        "KEY-DOWN MW-SPECIAL KEY-DOWN MW-SPECIAL KEY-ENTER MW-SPECIAL",
        "MW-W @ MW-DRAW", "MW-AT",
        "MW-W @ MEDIA-FREE", '." FREED=" MW-MSRC MSRC-HELD@ .',
    ], pdf, max_steps=2_000_000_000, roots=PDF_ROOTS)
    listed = _labels(output.split("@@LIST")[1].split("@@END")[0], 6, 36)
    assert listed == ["Page 1", "Page 2", "Page 3", "Page 4"], listed
    assert "PART=2 PLACE=0 " in output, output[-1500:]
    assert "FREED=0 " in output


def _outlined_pdf() -> bytes:
    """Two pages of paragraphs, each page longer than the view, and an
    outline: a part that starts closed, holding a chapter that starts
    open with a section under it, then a second part."""

    from test_pdf_content import HELVETICA
    from test_pdf_file import stream_object, write_pdf
    from test_pdf_layout import line

    def page(name: str) -> bytes:
        return b"".join(line("F1", 10, 72, 700 - 30 * n, f"{name}, paragraph {n}.")
                        for n in range(8))

    return write_pdf({
        1: b"<< /Type /Catalog /Pages 2 0 R /Outlines 20 0 R >>",
        2: b"<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 /MediaBox [0 0 612 792] "
           b"/Resources << /Font << /F1 10 0 R >> >> >>",
        3: b"<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>",
        4: stream_object(page("The first page")),
        5: b"<< /Type /Page /Parent 2 0 R /Contents 6 0 R >>",
        6: stream_object(page("The second page")),
        10: HELVETICA,
        20: b"<< /Type /Outlines /First 21 0 R /Last 24 0 R /Count 2 >>",
        21: b"<< /Title (Part one) /Parent 20 0 R /Next 24 0 R /First 22 0 R /Last 22 0 R "
            b"/Count -2 /Dest [3 0 R /Fit] >>",
        22: b"<< /Title (Chapter) /Parent 21 0 R /First 23 0 R /Last 23 0 R /Count 1 "
            b"/Dest [3 0 R /Fit] >>",
        23: b"<< /Title (Section) /Parent 22 0 R /Dest [5 0 R /Fit] >>",
        24: b"<< /Title (Part two) /Parent 20 0 R /Prev 21 0 R /Dest [5 0 R /Fit] >>",
    })


def test_a_pdfs_outline_starts_open_or_closed_as_it_says() -> None:
    """A PDF's outline shows as a tree whose branches start open or closed
    as the outline says.  Right opens the closed part, which shows the
    open chapter under it with its section; choosing the section reads
    its page and shows it from its start."""

    pdf = _outlined_pdf()
    output = _run(_media_lines() + KEYS + [
        f'{len(pdf)} S" /parts.pdf" MW-PUT',
        "PDF-DOC-READER MEDIA-K-PDF MW-W @ MEDIA-READER!",
        _open("/parts.pdf"), "MW-W @ WDG-FOCUS-SET",
        "MW-W @ MW-DRAW MW-W @ MW-MEDIA-SERVICE DROP MW-W @ MW-DRAW",
        "99 MW-CHAR MW-W @ MW-DRAW", '." @@START" CR', "6 36 MW-DUMP", '." @@END" CR',
        "KEY-RIGHT MW-SPECIAL MW-W @ MW-DRAW", '." @@OPENED" CR', "6 36 MW-DUMP",
        '." @@END" CR',
        "KEY-DOWN MW-SPECIAL KEY-DOWN MW-SPECIAL KEY-ENTER MW-SPECIAL",
        "MW-W @ MW-DRAW", "MW-AT",
        "MW-W @ MEDIA-FREE", '." FREED=" MW-MSRC MSRC-HELD@ .',
    ], pdf, max_steps=2_000_000_000, roots=PDF_ROOTS)
    assert _rows(output, "@@START", 3) == [f"{CLOSED} Part one", "  Part two", ""]
    assert _rows(output, "@@OPENED", 5) == [
        f"{OPEN} Part one", f"  {OPEN} Chapter", "      Section", "  Part two", ""]
    assert "PART=1 PLACE=0 " in output, output[-1500:]
    assert "FREED=0 " in output


def test_a_claim_and_a_rich_failure_move_the_picture_revision_on_a_change() -> None:
    """Claiming the picture changes what CELL shows, and so does a rich
    failure, which lets the claim go as well; saying the same again changes
    nothing."""
    rows = _gradient(30, 20)
    data = qoi_codec.encode(rows)
    output = _run(_claim_lines(len(data)) + [
        ": _PR  MW-W @ WDG-REVISION ;",
        '_PR -1 MW-W @ PICT-CLAIM! _PR SWAP - ." CLAIM=" .',
        '_PR -1 MW-W @ PICT-CLAIM! _PR SWAP - ." AGAIN=" .',
        '_PR PIC-R-DAMAGED MW-W @ PICT-RICH-FAILED! _PR SWAP - ." FAILED=" .',
        '_PR PIC-R-DAMAGED MW-W @ PICT-RICH-FAILED! _PR SWAP - ." REPEATED=" .',
    ] + _free_lines(), data)
    assert "CLAIM=1 " in output and "AGAIN=0 " in output
    assert "FAILED=2 " in output and "REPEATED=0 " in output
