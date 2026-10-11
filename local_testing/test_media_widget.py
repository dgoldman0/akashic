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

import re
import struct

import pytest

import qoi_codec
from forth_dependencies import dependency_order
from test_media import _gradient, _noise, _scaled
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
: MW-STYLE  ( -- )  FG-INDEX BG-INDEX 0 DRW-STYLE! ;
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


def _runtime(setup_data: bytes = b""):
    runtime = MegaForthRuntime(
        memory=create_one_core_address_space(external_size=128 << 20, hbw_size=1 << 20),
        execution_backend="native",
    )
    runtime.evaluate(KDOS_PATH.read_bytes(), source_name="kdos.f")
    runtime.evaluate(b"ENTER-USERLAND", source_name="media-widget-userland")
    source = []
    for module in dependency_order(AK, ("tui/widgets/media.f",)):
        source.extend(_load_forth_lines(AK / module))
    runtime.evaluate(("\n".join(source) + "\n").encode(),
                     source_name="media-widget-closure", step_budget=400_000_000)
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


def _run(lines: list[str], data: bytes = b"", max_steps: int = 400_000_000) -> str:
    assert len(data) <= FILE_BYTES
    runtime = _runtime(data)
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
def test_a_picture_draws_the_model_in_blocks(rows, cell_rows, cols) -> None:
    data = qoi_codec.encode(rows)
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
        (b"\x89PNG\r\n\x1a\n" + bytes(40), "This picture's format can't be shown yet"),
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


def test_a_rich_copy_holds_the_models_pixels_and_digest() -> None:
    import hashlib

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
    runtime.main_context.data.push(pic)
    runtime.execute("PIC-DIGEST")
    digest = runtime.main_context.data.pop()
    width, height, pixels = _scaled(rows, 20, 9)
    assert runtime.memory.read_bytes(address, length) == pixels
    assert runtime.memory.read_bytes(digest, 32) == hashlib.sha3_256(pixels).digest()
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
BINARY, TEXT, HTML, QOI = range(4)


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
    # The whole file, past the 4096 bytes the old preview kept, and the name.
    assert "HELD=5008 " in output and "LEN=5000 " in output, output[-2000:]
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
    assert f"VIEW={VIEW_FACTS} KIND={TEXT} NOTE={NOTE_MEMORY} HELD=8 " in output
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
