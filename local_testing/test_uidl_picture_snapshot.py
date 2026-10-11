#!/usr/bin/env python3
"""A <media> element's picture, described for the rich side and pulled.

UIDL-TUI's picture observation and uidl-picture-snapshot.f run natively on a
real document: the descriptor's rectangle, the rich copy asked for from the
surface's pixel size and a byte budget, the copy's format and size once
ready, and its pixels pulled back while the picture still shows them.
"""

from __future__ import annotations

import re

import qoi_codec
from forth_dependencies import dependency_order
from test_media import _gradient, _scaled
from test_uidl_collection_snapshot import (
    AK, COLOR_ABI_STUBS, KDOS_PATH, STYLE_ABI_STUBS, _load_forth_lines,
)
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime

_STUBBED = {"css/css.f", "tui/color.f"}
_CLOSURE = dependency_order(AK, ("tui/uidl-picture-snapshot.f",))
_COLOR_BEFORE = next(module for module in _CLOSURE[_CLOSURE.index("tui/color.f") + 1:]
                     if module not in _STUBBED)


def _source() -> str:
    lines = []
    for module in _CLOSURE:
        if module in _STUBBED:
            continue
        if module == _COLOR_BEFORE:
            lines.extend(COLOR_ABI_STUBS)
        if module == "tui/uidl-tui.f":
            lines.extend(STYLE_ABI_STUBS)
        lines.extend(_load_forth_lines(AK / module))
    return "\n".join(lines) + "\n"


ROWS = _gradient(60, 40)
QOI = qoi_codec.encode(ROWS)


def _runtime():
    runtime = MegaForthRuntime(
        memory=create_one_core_address_space(external_size=128 << 20, hbw_size=1 << 20),
        execution_backend="native",
    )
    runtime.evaluate(KDOS_PATH.read_bytes(), source_name="kdos.f")
    runtime.evaluate(b"ENTER-USERLAND", source_name="picture-userland")
    runtime.evaluate(_source().encode(), source_name="picture-closure",
                     step_budget=300_000_000)
    runtime.drain_uart_output()
    return runtime


SETUP = [
    "VARIABLE _UP-RGN  VARIABLE _UP-V  VARIABLE _UP-EM  VARIABLE _UP-WM",
    "VARIABLE _UP-COUNT  VARIABLE _UP-STATUS  VARIABLE _UP-DEPTH",
    f"CREATE _UP-QOI {' '.join(f'{b} C,' for b in QOI)}",
    f"{len(QOI)} CONSTANT _UP-QOI-U",
    "CREATE _UP-BIN 0 C, 1 C, 2 C, 3 C,",
    "CREATE _UP-D-MEM 2 UPICSN-DESCRIPTOR-SIZE * 7 + ALLOT",
    ": _UP-D  _UP-D-MEM 7 + -8 AND ;",
    "16384 XBUF _UP-PIXELS",
    ": _UP-PUT ( a u path-a path-u -- )",
    "  2DUP _UP-V @ VFS-CREATE 0= IF -101 THROW THEN",
    "  VFS-FF-WRITE _UP-V @ VFS-OPEN? ?DUP IF THROW THEN",
    "  DUP >R VFS-WRITE-EXACT IF -102 THROW THEN R> VFS-CLOSE ;",
    ": _UP-OPEN ( path-a path-u -- ) _UP-V @ _UP-WM @ MEDIA-OPEN-VFS DROP",
    "  _UP-EM @ UIDL-DIRTY! ;",
    ": _UP-SERVICE  BEGIN UTUI-SERVICE 0= UNTIL ;",
    "CREATE _UP-ASK-S UPICSN-ASK-SIZE 7 + ALLOT",
    ": _UP-ASK  _UP-ASK-S 7 + -8 AND ;",
    "_UP-ASK UPICSN-ASK-SIZE 0 FILL",
    ": _UP-PIXELS! ( cols rows pw ph budget -- )",
    "  _UP-ASK UPICSN-ASK.BUDGET ! _UP-ASK UPICSN-ASK.PIXEL-H !",
    "  _UP-ASK UPICSN-ASK.PIXEL-W ! _UP-ASK UPICSN-ASK.SURFACE-ROWS !",
    "  _UP-ASK UPICSN-ASK.SURFACE-COLS ! ;",
    ": _UP-LIMITS! ( max-w max-h -- )",
    "  _UP-ASK UPICSN-ASK.MAX-H ! _UP-ASK UPICSN-ASK.MAX-W ! ;",
    ": _UP-CAPTURE ( d-u cols rows pw ph budget -- )",
    "  _UP-PIXELS! _UP-D SWAP _UP-ASK UPICSN-CAPTURE",
    "  _UP-STATUS ! _UP-COUNT ! ;",
    ": _UP-BOUND. ( cols rows -- ) _UP-ASK UPICSN-BOUND",
    '  ." BOUND=" SWAP . ." ," . CR ;',
    ": _UP-SHOW ( -- )",
    '  ." N=" _UP-COUNT @ . ." S=" _UP-STATUS @ .',
    "  _UP-COUNT @ IF",
    '    ." IDX=" _UP-D UPICSN-SOURCE-INDEX@ . ." ROW=" _UP-D UPICSN-ROW@ .',
    '    ." COL=" _UP-D UPICSN-COLUMN@ . ." H=" _UP-D UPICSN-HEIGHT@ .',
    '    ." W=" _UP-D UPICSN-WIDTH@ . ." ST=" _UP-D UPICSN-STATE@ .',
    '    ." CW=" _UP-D UPICSN-COPY-WIDTH@ . ." CH=" _UP-D UPICSN-COPY-HEIGHT@ .',
    '    ." CU=" _UP-D UPICSN-COPY-BYTES@ . ." FMT=" _UP-D UPICSN-FORMAT@ .',
    '    ." AW=" _UP-D UPICSN-ASK-WIDTH@ . ." AH=" _UP-D UPICSN-ASK-HEIGHT@ .',
    "  THEN CR ;",
    "DEPTH _UP-DEPTH !",
    "80 24 SCR-NEW SCR-USE",
    "0 0 24 80 RGN-NEW _UP-RGN !",
    "524288 A-XMEM ARENA-NEW IF -1 THROW THEN",
    "VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN _UP-V !",
    '_UP-QOI _UP-QOI-U S" /logo.qoi" _UP-PUT',
    '_UP-BIN 4 S" /data.bin" _UP-PUT',
    "_UP-V @ VFS-USE",
    'S" <uidl><region arrange=flex><media id=m/></region></uidl>" _UP-RGN @ UTUI-LOAD DROP',
    'S" m" UTUI-BY-ID DUP _UP-EM ! UTUI-WIDGET@ _UP-WM !',
    '." INDEX=" _UP-EM @ UIDL-ELEM-INDEX? DROP . CR',
    'S" /logo.qoi" _UP-OPEN UTUI-PAINT _UP-SERVICE UTUI-PAINT',
]


def _run(lines: list[str]) -> tuple[str, MegaForthRuntime]:
    runtime = _runtime()
    program = SETUP + lines + ['DEPTH _UP-DEPTH @ - ." @D:" . CR']
    try:
        runtime.evaluate(("\n".join(program) + "\n").encode(),
                         source_name="picture-proof", step_budget=300_000_000)
    except Exception as error:
        raise AssertionError(runtime.uart_output.decode(errors="replace")[-6000:]) from error
    output = runtime.drain_uart_output().decode("utf-8", errors="replace")
    assert "@D:0 " in output, output[-3000:]
    return output, runtime


def _shows(output: str) -> list[dict[str, int]]:
    return [dict((k, int(v)) for k, v in re.findall(r"([A-Z]+)=(-?\d+)", line))
            for line in output.splitlines() if line.startswith("N=")]


def _constant(runtime, name: str) -> int:
    runtime.execute(name)
    return runtime.main_context.data.pop()


def test_a_picture_is_described_asked_for_and_pulled() -> None:
    output, runtime = _run([
        # No pixel size: described, nothing asked.
        "UPICSN-DESCRIPTOR-SIZE 80 24 0 0 0 _UP-CAPTURE _UP-SHOW",
        # 8 by 16 pixels a cell: asked, then decoded by the per-pass service.
        "UPICSN-DESCRIPTOR-SIZE 80 24 640 384 0 _UP-CAPTURE _UP-SHOW",
        "_UP-SERVICE",
        "UPICSN-DESCRIPTOR-SIZE 80 24 640 384 0 _UP-CAPTURE _UP-SHOW",
        '_UP-D _UP-PIXELS 9600 UPICSN-PULL ." PULL=" . CR',
        # A budget of 1,000 bytes asks again, for a smaller copy.
        "UPICSN-DESCRIPTOR-SIZE 80 24 640 384 1000 _UP-CAPTURE _UP-SHOW",
        "_UP-SERVICE",
        "UPICSN-DESCRIPTOR-SIZE 80 24 640 384 1000 _UP-CAPTURE _UP-SHOW",
        # No room in the bank: nothing is written.
        "0 80 24 640 384 0 _UP-CAPTURE _UP-SHOW",
        # The terminal's largest picture bounds the copy, in its own shape.
        "80 24 640 384 0 _UP-PIXELS! 100 0 _UP-LIMITS! 40 12 _UP-BOUND.",
        "100 50 _UP-LIMITS! 40 12 _UP-BOUND.",
        # A pixel size beyond what any surface has is no answer.
        "0 0 _UP-LIMITS! 80 24 1073741824 384 0 _UP-PIXELS! 40 12 _UP-BOUND.",
    ])
    index = int(re.search(r"INDEX=(\d+)", output).group(1))
    shown = _shows(output)
    ok, capacity = _constant(runtime, "UPICSN-S-OK"), _constant(runtime, "UPICSN-S-CAPACITY")
    none, pending, ready = (_constant(runtime, f"UPICSN-C-{name}")
                            for name in ("NONE", "PENDING", "READY"))
    first = shown[0]
    assert (first["N"], first["S"], first["IDX"], first["ST"]) == (1, ok, index, none)
    rows, cols = first["H"], first["W"]
    assert rows > 0 and cols > 0
    assert (first["AW"], first["AH"]) == (0, 0)

    # The bound is the rectangle's share of the surface's pixels.
    assert shown[1]["ST"] == pending
    assert (shown[1]["AW"], shown[1]["AH"]) == (cols * 8, rows * 16)
    ready_copy = shown[2]
    assert ready_copy["ST"] == ready
    width, height, pixels = _scaled(ROWS, cols * 8, rows * 16)
    assert (ready_copy["CW"], ready_copy["CH"], ready_copy["CU"]) == (width, height, len(pixels))
    assert ready_copy["FMT"] == _constant(runtime, "PIC-F-RGBA8")
    assert re.search(r"PULL=(\d+)", output).group(1) == str(ok)
    runtime.execute("_UP-PIXELS")
    assert runtime.memory.read_bytes(runtime.main_context.data.pop(), len(pixels)) == pixels

    # Within 1,000 bytes, keeping the rectangle's shape.
    budgeted = shown[3]
    assert budgeted["ST"] == pending
    def height_for(w):
        return max(1, w * rows * 16 // (cols * 8))
    assert budgeted["AH"] == height_for(budgeted["AW"])
    assert budgeted["AW"] * budgeted["AH"] * 4 <= 1000
    assert (budgeted["AW"] + 1) * height_for(budgeted["AW"] + 1) * 4 > 1000
    smaller = shown[4]
    assert smaller["ST"] == ready and smaller["CU"] <= 1000
    width, height, _ = _scaled(ROWS, budgeted["AW"], budgeted["AH"])
    assert (smaller["CW"], smaller["CH"]) == (width, height)
    # A bank with no room says how many descriptors it would take.
    assert (shown[5]["N"], shown[5]["S"]) == (1, capacity)
    # 40 by 12 cells cover 320 by 192 pixels: at most 100 across keeps
    # 5:3, and at most 50 down then narrows it again.
    bounds = re.findall(r"BOUND=(-?\d+) ,(-?\d+)", output)
    assert bounds == [("100", "60"), ("83", "50"), ("0", "0")]


def test_a_picture_keeps_its_revision_at_every_size_until_another_is_shown() -> None:
    output, runtime = _run([
        "VARIABLE _UP-REV",
        "UPICSN-DESCRIPTOR-SIZE 80 24 640 384 0 _UP-CAPTURE",
        '." REV1=" _UP-D UPICSN-REVISION@ . CR',
        "UPICSN-DESCRIPTOR-SIZE 80 24 640 384 1000 _UP-CAPTURE",
        '." REV2=" _UP-D UPICSN-REVISION@ . CR',
        "_UP-D UPICSN-REVISION@ _UP-REV !",
        '_UP-D UPICSN-SOURCE-INDEX@ _UP-REV @ UPICSN-SHOWS? ." SAME=" . CR',
        '_UP-D UPICSN-SOURCE-INDEX@ _UP-REV @ 1+ UPICSN-SHOWS? ." NEWER=" . CR',
        '_UP-D UPICSN-SOURCE-INDEX@ 1+ _UP-REV @ UPICSN-SHOWS? ." ELSEWHERE=" . CR',
        # The same file opened again is another picture.
        'S" /logo.qoi" _UP-OPEN UTUI-PAINT',
        '_UP-D UPICSN-SOURCE-INDEX@ _UP-REV @ UPICSN-SHOWS? ." REOPENED=" . CR',
        "UPICSN-DESCRIPTOR-SIZE 80 24 640 384 0 _UP-CAPTURE",
        '." REV3=" _UP-D UPICSN-REVISION@ . CR',
        "_UP-D UPICSN-REVISION@ _UP-REV !",
        'S" /data.bin" _UP-OPEN UTUI-PAINT',
        '_UP-D UPICSN-SOURCE-INDEX@ _UP-REV @ UPICSN-SHOWS? ." FACTS=" . CR',
    ])
    fields = dict((k, int(v)) for k, v in re.findall(r"([A-Z]+\d?)=(-?\d+)", output))
    ok, stale = _constant(runtime, "UPICSN-S-OK"), _constant(runtime, "UPICSN-S-STALE")
    assert fields["REV1"] > 0 and fields["REV2"] == fields["REV1"]
    assert (fields["SAME"], fields["NEWER"], fields["ELSEWHERE"]) == (ok, stale, stale)
    assert fields["REOPENED"] == stale and fields["REV3"] > fields["REV1"]
    # The facts view shows no picture.
    assert fields["FACTS"] == stale


def test_a_pull_of_a_picture_no_longer_shown_is_stale() -> None:
    output, runtime = _run([
        "UPICSN-DESCRIPTOR-SIZE 80 24 640 384 0 _UP-CAPTURE",
        "_UP-SERVICE",
        "UPICSN-DESCRIPTOR-SIZE 80 24 640 384 0 _UP-CAPTURE _UP-SHOW",
        'S" /data.bin" _UP-OPEN UTUI-PAINT',
        '_UP-D _UP-PIXELS _UP-D UPICSN-COPY-BYTES@ UPICSN-PULL ." PULL=" . CR',
        "UPICSN-DESCRIPTOR-SIZE 80 24 640 384 0 _UP-CAPTURE _UP-SHOW",
    ])
    shown = _shows(output)
    assert shown[0]["ST"] == _constant(runtime, "UPICSN-C-READY")
    assert re.search(r"PULL=(\d+)", output).group(1) == str(
        _constant(runtime, "UPICSN-S-STALE"))
    # The facts view shows no picture.
    assert shown[1]["N"] == 0


def test_a_pull_of_a_copy_of_another_size_is_stale() -> None:
    """A copy is the picture decoded at one size: once the widget holds a
    copy of another size, a descriptor of the old one pulls nothing."""

    output, runtime = _run([
        "CREATE _UP-OLD-MEM UPICSN-DESCRIPTOR-SIZE 7 + ALLOT",
        ": _UP-OLD  _UP-OLD-MEM 7 + -8 AND ;",
        "UPICSN-DESCRIPTOR-SIZE 80 24 640 384 0 _UP-CAPTURE",
        "_UP-SERVICE",
        "UPICSN-DESCRIPTOR-SIZE 80 24 640 384 0 _UP-CAPTURE _UP-SHOW",
        "_UP-D _UP-OLD UPICSN-DESCRIPTOR-SIZE MOVE",
        # A budget asks for a smaller copy of the same picture.
        "UPICSN-DESCRIPTOR-SIZE 80 24 640 384 1000 _UP-CAPTURE",
        "_UP-SERVICE",
        "UPICSN-DESCRIPTOR-SIZE 80 24 640 384 1000 _UP-CAPTURE _UP-SHOW",
        '_UP-OLD _UP-PIXELS _UP-OLD UPICSN-COPY-BYTES@ UPICSN-PULL ." OLD=" . CR',
        '_UP-D _UP-PIXELS _UP-D UPICSN-COPY-BYTES@ UPICSN-PULL ." NEW=" . CR',
    ])
    shown = _shows(output)
    ready = _constant(runtime, "UPICSN-C-READY")
    assert shown[0]["ST"] == shown[1]["ST"] == ready
    assert shown[1]["CU"] < shown[0]["CU"]
    assert re.search(r"OLD=(\d+)", output).group(1) == str(
        _constant(runtime, "UPICSN-S-STALE"))
    assert re.search(r"NEW=(\d+)", output).group(1) == str(
        _constant(runtime, "UPICSN-S-OK"))


def test_a_file_the_terminal_decodes_is_described_as_itself() -> None:
    """With QOI among the formats the terminal decodes, the picture goes as
    its file: ready at once at its own size, with no copy made and no pixel
    size needed, and pulled byte for byte."""

    output, runtime = _run([
        ": _UP-FORMATS!  _UP-ASK UPICSN-ASK.FORMATS ! ;",
        "1 PIC-F-QOI 1- LSHIFT _UP-FORMATS!",
        "UPICSN-DESCRIPTOR-SIZE 80 24 0 0 0 _UP-CAPTURE _UP-SHOW",
        '_UP-D _UP-PIXELS _UP-D UPICSN-COPY-BYTES@ UPICSN-PULL ." PULL=" . CR',
        # Beyond the terminal's largest picture, a copy is asked for instead.
        "30 0 _UP-LIMITS!",
        "UPICSN-DESCRIPTOR-SIZE 80 24 640 384 0 _UP-CAPTURE _UP-SHOW",
        # So it is when the terminal decodes no QOI.
        "0 0 _UP-LIMITS! 0 _UP-FORMATS!",
        "UPICSN-DESCRIPTOR-SIZE 80 24 640 384 0 _UP-CAPTURE _UP-SHOW",
    ])
    shown = _shows(output)
    ready = _constant(runtime, "UPICSN-C-READY")
    qoi, raw = _constant(runtime, "PIC-F-QOI"), _constant(runtime, "PIC-F-RGBA8")
    file = shown[0]
    assert (file["ST"], file["FMT"]) == (ready, qoi)
    assert (file["CW"], file["CH"], file["CU"]) == (60, 40, len(QOI))
    assert (file["AW"], file["AH"]) == (60, 40)
    assert re.search(r"PULL=(\d+)", output).group(1) == str(_constant(runtime, "UPICSN-S-OK"))
    runtime.execute("_UP-PIXELS")
    assert runtime.memory.read_bytes(runtime.main_context.data.pop(), len(QOI)) == QOI
    for copy in shown[1:]:
        assert copy["FMT"] == raw and copy["CU"] != len(QOI)


def test_a_png_goes_as_its_file_only_to_a_terminal_that_decodes_it() -> None:
    import io
    from PIL import Image

    image = Image.new("RGBA", (50, 30), (10, 200, 30, 255))
    out = io.BytesIO()
    image.save(out, "PNG")
    png = out.getvalue()
    output, runtime = _run([
        f"CREATE _UP-PNG {' '.join(f'{b} C,' for b in png)}",
        f'_UP-PNG {len(png)} S" /photo.png" _UP-PUT',
        'S" /photo.png" _UP-OPEN UTUI-PAINT',
        ": _UP-FORMATS!  _UP-ASK UPICSN-ASK.FORMATS ! ;",
        "1 PIC-F-PNG 1- LSHIFT _UP-FORMATS!",
        "UPICSN-DESCRIPTOR-SIZE 80 24 640 384 0 _UP-CAPTURE _UP-SHOW",
        '_UP-D _UP-PIXELS _UP-D UPICSN-COPY-BYTES@ UPICSN-PULL ." PULL=" . CR',
        # The guest decodes no PNG, so with no terminal to decode it the
        # copy it is asked for fails.
        "0 _UP-FORMATS!",
        "UPICSN-DESCRIPTOR-SIZE 80 24 640 384 0 _UP-CAPTURE _UP-SERVICE",
        "UPICSN-DESCRIPTOR-SIZE 80 24 640 384 0 _UP-CAPTURE _UP-SHOW",
        '." REASON=" _UP-D UPICSN-REASON@ . CR',
    ])
    shown = _shows(output)
    file, refused = shown[0], shown[1]
    assert (file["ST"], file["FMT"]) == (_constant(runtime, "UPICSN-C-READY"),
                                         _constant(runtime, "PIC-F-PNG"))
    assert (file["CW"], file["CH"], file["CU"]) == (50, 30, len(png))
    assert re.search(r"PULL=(\d+)", output).group(1) == str(_constant(runtime, "UPICSN-S-OK"))
    runtime.execute("_UP-PIXELS")
    assert runtime.memory.read_bytes(runtime.main_context.data.pop(), len(png)) == png
    assert refused["ST"] == _constant(runtime, "UPICSN-C-FAILED")
    assert refused["FMT"] == _constant(runtime, "PIC-F-RGBA8")
    assert re.search(r"REASON=(\d+)", output).group(1) == str(
        _constant(runtime, "PIC-R-UNSUPPORTED"))


def test_a_capture_claims_the_pictures_the_rich_side_takes() -> None:
    """A picture the rich side shows, or is taking to show, is claimed, so
    its CELL view shows what it is and decodes nothing; one it does not
    take, or cannot yet, is not."""

    output, runtime = _run([
        ": _UP-FORMATS!  _UP-ASK UPICSN-ASK.FORMATS ! ;",
        ": _UP-CLAIM!  _UP-ASK UPICSN-ASK.CLAIM ! ;",
        ": _UP-CLAIMED.  _UP-WM @ MEDIA-PICTURE@ PICT-CLAIMED? . ;",
        # A file the terminal decodes, with the rich side taking pictures.
        "1 PIC-F-QOI 1- LSHIFT _UP-FORMATS! -1 _UP-CLAIM!",
        'UPICSN-DESCRIPTOR-SIZE 80 24 0 0 0 _UP-CAPTURE ." FILE=" _UP-CLAIMED.',
        # Taking none lets it go.
        '0 _UP-CLAIM! UPICSN-DESCRIPTOR-SIZE 80 24 0 0 0 _UP-CAPTURE ." NONE=" _UP-CLAIMED.',
        # A copy that cannot be asked for yet, with no pixel size, is not taken.
        "-1 _UP-CLAIM! 0 _UP-FORMATS!",
        'UPICSN-DESCRIPTOR-SIZE 80 24 0 0 0 _UP-CAPTURE ." NOSIZE=" _UP-CLAIMED.',
        # A copy being made is.
        'UPICSN-DESCRIPTOR-SIZE 80 24 640 384 0 _UP-CAPTURE ." COPY=" _UP-CLAIMED.',
        # A bank too small only counts: the claim stays as it was.
        '0 _UP-CLAIM! 0 80 24 640 384 0 _UP-CAPTURE ." COUNTED=" _UP-CLAIMED.',
        # Every claim lapses at once.
        'UPICSN-RELEASE-ALL ." RELEASED=" _UP-CLAIMED.',
    ])
    assert "FILE=-1 " in output and "NONE=0 " in output, output[-2000:]
    assert "NOSIZE=0 " in output and "COPY=-1 " in output
    assert "COUNTED=-1 " in output and "RELEASED=0 " in output
