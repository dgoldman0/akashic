#!/usr/bin/env python3
"""What decompression costs the device, in guest steps.

This counts the steps on the MegaPad simulator, natively:

- the inflater, per byte it gives, for 200,000 bytes of English-like text in
  stored, fixed-code and dynamic-code blocks (zlib's level 0, its fixed
  strategy, and levels 1, 6 and 9), as bare deflate, zlib and gzip, and for
  random bytes stored and one byte repeated;
- the sample picture the Desktop image carries (sunset.qoi, 160 by 100
  pixels) decoded to RGBA rows from its QOI file and from PNG files of the
  same pixels: as Pillow writes them, and as zlib writes them with each of
  PNG's five filters on every row.

Each output is checked against Python's zlib or the QOI reference decoder.
A semantic step is one guest instruction or primitive the simulator counts;
the counts depend on the data, not on the host.

Usage: measure_decompression.py [--json PATH]
"""

from __future__ import annotations

import argparse
import io
import json
import random
import sys
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from PIL import Image  # noqa: E402

import akashic_tui  # noqa: E402
import qoi_codec  # noqa: E402
import test_png  # noqa: E402
from forth_dependencies import dependency_order  # noqa: E402
from simulator.platform import create_one_core_address_space  # noqa: E402
from simulator.runtime import MegaForthRuntime  # noqa: E402
from test_inflate import _text, _zlib  # noqa: E402
from test_uidl_collection_snapshot import AK, KDOS_PATH, _load_forth_lines  # noqa: E402

IN_BYTES = 2 << 20
OUT_BYTES = 4 << 20
RAW, ZLIB, GZIP = 0, 1, 2
INFL_DONE = 2
PIC_DONE = 2

PRELUDE = f"""
{IN_BYTES} XBUF MD-IN
{OUT_BYTES} XBUF MD-OUT
32768 XBUF MD-WIN
65536 XBUF MD-ROW
1048576 XBUF MD-PDEC
CREATE MD-RECS INFL-SIZE 7 + ALLOT
: MD-REC  MD-RECS 7 + -8 AND ;
CREATE MD-QDEC QOI-DEC-SIZE ALLOT
VARIABLE MD-P  VARIABLE MD-LEFT  VARIABLE MD-O  VARIABLE MD-W

\\ Inflate IN-U bytes at MD-IN into MD-OUT in one feed.
: MD-INFLATE  ( in-u wrapper -- out-u status )
    >R MD-WIN 32768 R> MD-REC INFL-INIT
    MD-IN SWAP MD-OUT {OUT_BYTES} MD-REC INFL-FEED  ROT DROP ;

\\ Decode a picture's rows into MD-OUT, one after another.  The whole file
\\ is given at once, so any status but a row ends the loop: done, damaged,
\\ or cut short.
: MD-ROW-OUT  ( -- )
    MD-ROW MD-O @ MD-W @ 4 * MOVE  MD-W @ 4 * MD-O +! ;

: MD-QOI  ( file-u -- rows status )
    MD-IN OVER QOI-HEADER 0= IF DROP 0 -1 EXIT THEN
    2DROP OVER MD-W ! MD-QDEC QOI-DEC-INIT
    14 - MD-LEFT !  MD-IN 14 + MD-P !  MD-OUT MD-O !
    BEGIN
        MD-P @ MD-LEFT @ MD-ROW MD-QDEC QOI-DEC-FEED
        SWAP DUP MD-P +! NEGATE MD-LEFT +!
        DUP QOI-S-ROW = IF DROP MD-ROW-OUT ELSE MD-QDEC QOI-DEC-ROWS@ SWAP EXIT THEN
    AGAIN ;

: MD-PNG  ( file-u -- rows status )
    MD-IN OVER PNG-HEADER PNG-H-OK <> IF DROP 2DROP 0 -1 EXIT THEN
    DROP DUP MD-W ! MD-PDEC PNG-DEC-INIT
    MD-LEFT !  MD-IN MD-P !  MD-OUT MD-O !
    BEGIN
        MD-P @ MD-LEFT @ MD-ROW MD-PDEC PNG-DEC-FEED
        SWAP DUP MD-P +! NEGATE MD-LEFT +!
        DUP PNG-S-ROW = IF DROP MD-ROW-OUT ELSE MD-PDEC PNG-DEC-ROWS@ SWAP EXIT THEN
    AGAIN ;
"""


class Machine:
    def __init__(self):
        self.runtime = MegaForthRuntime(
            memory=create_one_core_address_space(external_size=32 << 20, hbw_size=1 << 20),
            execution_backend="native",
        )
        self.runtime.evaluate(KDOS_PATH.read_bytes(), source_name="kdos.f")
        self.runtime.evaluate(b"ENTER-USERLAND", source_name="userland")
        source = []
        for module in dependency_order(AK, ("utils/inflate.f", "render/qoi.f", "render/png.f")):
            source.extend(_load_forth_lines(AK / module))
        source.append(PRELUDE)
        self.runtime.evaluate(("\n".join(source) + "\n").encode(), source_name="measure",
                              step_budget=200_000_000)
        self.runtime.drain_uart_output()
        self.input = self.value("MD-IN")
        self.output = self.value("MD-OUT")

    def value(self, word: str) -> int:
        self.runtime.execute(word)
        return self.runtime.main_context.data.pop()

    def run(self, word: str, *args: int) -> tuple[int, tuple[int, ...]]:
        """The steps WORD takes on ARGS, and the stack it leaves."""

        stack = self.runtime.main_context.data
        assert stack.depth() == 0
        for value in args:
            stack.push(value)
        result = self.runtime.execute(word, step_budget=4_000_000_000)
        values = tuple(stack.snapshot())
        while stack.depth():
            stack.pop()
        return result.semantic_steps, values

    def inflate(self, stream: bytes, wrapper: int, expected: bytes) -> int:
        self.runtime.memory.write_bytes(self.input, stream)
        steps, (given, status) = self.run("MD-INFLATE", len(stream), wrapper)
        assert status == INFL_DONE and given == len(expected)
        assert self.runtime.memory.read_bytes(self.output, given) == expected
        return steps

    def picture(self, word: str, data: bytes, expected: bytes, rows: int) -> int:
        self.runtime.memory.write_bytes(self.input, data)
        steps, (decoded, status) = self.run(word, len(data))
        assert status == PIC_DONE and decoded == rows, (word, decoded, status)
        assert self.runtime.memory.read_bytes(self.output, len(expected)) == expected
        return steps


def inflater_costs(machine: Machine) -> list[dict]:
    text = _text(200_000, seed=1)
    noise = random.Random(2).randbytes(200_000)
    run = b"x" * 200_000
    cases = [
        ("text", "stored (level 0)", RAW, _zlib(text, 0, wbits=-15), text),
        ("text", "fixed codes (level 6, Z_FIXED)", RAW,
         _zlib(text, 6, zlib.Z_FIXED, wbits=-15), text),
        ("text", "dynamic codes, level 1", RAW, _zlib(text, 1, wbits=-15), text),
        ("text", "dynamic codes, level 6", RAW, _zlib(text, 6, wbits=-15), text),
        ("text", "dynamic codes, level 9", RAW, _zlib(text, 9, wbits=-15), text),
        ("text", "dynamic codes, level 6, zlib", ZLIB, _zlib(text, 6), text),
        ("text", "dynamic codes, level 6, gzip", GZIP, _zlib(text, 6, wbits=31), text),
        ("random", "stored (level 0)", RAW, _zlib(noise, 0, wbits=-15), noise),
        ("random", "stored (level 0), zlib", ZLIB, _zlib(noise, 0), noise),
        ("one byte repeated", "level 9", RAW, _zlib(run, 9, wbits=-15), run),
    ]
    rows = []
    for data, blocks, wrapper, stream, expected in cases:
        steps = machine.inflate(stream, wrapper, expected)
        rows.append({"data": data, "blocks": blocks, "stream_bytes": len(stream),
                     "output_bytes": len(expected), "steps": steps,
                     "steps_per_byte": steps / len(expected)})
    return rows


def picture_costs(machine: Machine) -> list[dict]:
    qoi = akashic_tui.SAMPLE_PICTURE
    width, height, pixels = qoi_codec.decode(qoi)
    expected = qoi_codec.rgba_bytes(pixels)
    assert (width, height) == (160, 100) and len(expected) == width * height * 4
    image = Image.frombytes("RGBA", (width, height), expected)
    files = [("QOI", "MD-QOI", qoi)]
    for label, options in (("PNG, Pillow", {}), ("PNG, Pillow optimize", {"optimize": True})):
        buffer = io.BytesIO()
        image.save(buffer, "PNG", **options)
        files.append((label, "MD-PNG", buffer.getvalue()))
    rows_of_pixels = [[tuple(expected[(y * width + x) * 4:(y * width + x) * 4 + 4])
                       for x in range(width)] for y in range(height)]
    for kind, name in enumerate(("None", "Sub", "Up", "Average", "Paeth")):
        data = test_png.png_file(width, height, 8, 6, rows_of_pixels, filters=(kind,))
        files.append((f"PNG, filter {name}, zlib level 6", "MD-PNG", data))
    rows = []
    for label, word, data in files:
        steps = machine.picture(word, data, expected, height)
        rows.append({"file": label, "file_bytes": len(data), "steps": steps,
                     "steps_per_pixel": steps / (width * height)})
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--json", type=Path)
    args = parser.parse_args()
    machine = Machine()
    inflater = inflater_costs(machine)
    pictures = picture_costs(machine)
    print("Inflater, steps per byte given:")
    for row in inflater:
        print(f"  {row['data']:<18} {row['blocks']:<34} {row['stream_bytes']:>7,} -> "
              f"{row['output_bytes']:>7,} bytes  {row['steps_per_byte']:7.2f}")
    print("Sample picture, 160 x 100, steps per pixel:")
    for row in pictures:
        print(f"  {row['file']:<36} {row['file_bytes']:>6,} bytes  {row['steps']:>11,} steps  "
              f"{row['steps_per_pixel']:7.1f}")
    if args.json:
        args.json.write_text(json.dumps({"inflater": inflater, "pictures": pictures},
                                        indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
