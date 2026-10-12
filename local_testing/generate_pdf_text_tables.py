#!/usr/bin/env python3
"""Write akashic/pdf/text-tables.f: PDF's simple encodings, glyph names and
the widths of the standard fonts.

Sources, all on the host:

- PDF 32000-1 Annex D for the four Latin encodings: StandardEncoding as
  fontTools lists it, MacRomanEncoding as Python's mac_roman codec has it,
  WinAnsiEncoding as cp1252 with the annex's notes, and PDFDocEncoding as
  Table D.2 gives it;
- the Symbol and ZapfDingbats fonts' own encodings, from URW's metrics for
  StandardSymbolsPS and D050000L, through their glyph lists;
- the Adobe Glyph List for New Fonts, the ligatures and the names the
  encodings use, from /usr/share/aglfn;
- the widths of the Helvetica and Times fonts from URW's metrics for Nimbus
  Sans and Nimbus Roman, which share their widths, for the characters the
  Latin encodings and the ligatures hold.  Helvetica's oblique faces share
  its upright faces' widths, and Courier's are all 600.

Bytes are packed eight to a cell, little-endian, to keep the source small.

Usage: generate_pdf_text_tables.py [--check]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from fontTools.encodings.StandardEncoding import StandardEncoding

HERE = Path(__file__).resolve().parent
TARGET = HERE.parent / "akashic" / "pdf" / "text-tables.f"
AGL = Path("/usr/share/aglfn/glyphlist.txt")
AGLFN = Path("/usr/share/aglfn/aglfn.txt")
ZAPF = Path("/usr/share/aglfn/zapfdingbats.txt")
URW = Path("/usr/share/fonts/type1/urw-base35")

# Helvetica's oblique faces have its upright faces' widths, so they share
# their tables.
BASE_FONTS = (
    ("HELVETICA", "NimbusSans-Regular"),
    ("HELVETICA-BOLD", "NimbusSans-Bold"),
    ("TIMES-ROMAN", "NimbusRoman-Regular"),
    ("TIMES-BOLD", "NimbusRoman-Bold"),
    ("TIMES-ITALIC", "NimbusRoman-Italic"),
    ("TIMES-BOLDITALIC", "NimbusRoman-BoldItalic"),
)

LIGATURES = ("ff", "fi", "fl", "ffi", "ffl", "dotlessj", "st", "longs")

# PDF 32000-1 Table D.2: PDFDocEncoding where it differs from Latin-1.
PDFDOC = {
    0x18: 0x02D8, 0x19: 0x02C7, 0x1A: 0x02C6, 0x1B: 0x02D9, 0x1C: 0x02DD,
    0x1D: 0x02DB, 0x1E: 0x02DA, 0x1F: 0x02DC,
    0x80: 0x2022, 0x81: 0x2020, 0x82: 0x2021, 0x83: 0x2026, 0x84: 0x2014,
    0x85: 0x2013, 0x86: 0x0192, 0x87: 0x2044, 0x88: 0x2039, 0x89: 0x203A,
    0x8A: 0x2212, 0x8B: 0x2030, 0x8C: 0x201E, 0x8D: 0x201C, 0x8E: 0x201D,
    0x8F: 0x2018, 0x90: 0x2019, 0x91: 0x201A, 0x92: 0x2122, 0x93: 0xFB01,
    0x94: 0xFB02, 0x95: 0x0141, 0x96: 0x0152, 0x97: 0x0160, 0x98: 0x0178,
    0x99: 0x017D, 0x9A: 0x0131, 0x9B: 0x0142, 0x9C: 0x0153, 0x9D: 0x0161,
    0x9E: 0x017E, 0x9F: 0, 0xA0: 0x20AC, 0xAD: 0,
}


def glyph_list(path: Path) -> dict[str, int]:
    names = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        name, codes = line.split(";")[:2]
        first = codes.split()[0]
        names.setdefault(name, int(first, 16))
    return names


def aglfn() -> dict[str, int]:
    names = {}
    for line in AGLFN.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        code, name = line.split(";")[:2]
        names[name] = int(code, 16)
    return names


def afm(name: str) -> list[tuple[int, int, str]]:
    """(code, width, glyph name) for each character of a font's metrics."""

    out = []
    for line in (URW / f"{name}.afm").read_text(encoding="latin-1").splitlines():
        if not line.startswith("C "):
            continue
        fields = dict(part.strip().split(" ", 1) for part in line.split(";") if part.strip())
        out.append((int(fields["C"]), int(fields["WX"]), fields["N"].strip()))
    return out


def encodings(agl: dict[str, int], zapf: dict[str, int]) -> dict[str, list[int]]:
    standard = [agl.get(name, 0) if name != ".notdef" else 0 for name in StandardEncoding]
    mac = [0] * 256
    for code in range(32, 256):
        if code == 127:
            continue
        mac[code] = ord(bytes([code]).decode("mac_roman"))
    win = [0] * 256
    for code in range(32, 256):
        try:
            win[code] = ord(bytes([code]).decode("cp1252"))
        except UnicodeDecodeError:
            win[code] = 0x2022 if code > 0x40 else 0
    win[127] = 0x2022
    win[0xA0] = 0x0020
    win[0xAD] = 0x002D
    doc = [code if 0x20 <= code < 0x7F or code >= 0xA1 else 0 for code in range(256)]
    for code in (9, 10, 13):
        doc[code] = code
    for code, point in PDFDOC.items():
        doc[code] = point
    symbol = [0] * 256
    for code, _, name in afm("StandardSymbolsPS"):
        if 0 <= code < 256:
            symbol[code] = agl.get(name, 0)
    dingbats = [0] * 256
    for code, _, name in afm("D050000L"):
        if 0 <= code < 256:
            dingbats[code] = zapf.get(name, agl.get(name, 0))
    return {"STANDARD": standard, "WINANSI": win, "MACROMAN": mac, "PDFDOC": doc,
            "SYMBOL": symbol, "ZAPF": dingbats}


def names(agl: dict[str, int]) -> list[tuple[str, int]]:
    """The glyph names to know: AGLFN's, the ligatures, and every name the
    Latin encodings and the Symbol font use."""

    wanted = dict(aglfn())
    for name in LIGATURES:
        if name in agl:
            wanted[name] = agl[name]
    for name in StandardEncoding:
        if name in agl:
            wanted[name] = agl[name]
    for _, _, name in afm("StandardSymbolsPS"):
        if name in agl:
            wanted[name] = agl[name]
    for code in range(0x80, 0x100):
        for codec in ("mac_roman", "cp1252"):
            try:
                point = ord(bytes([code]).decode(codec))
            except UnicodeDecodeError:
                continue
            for name, value in agl.items():
                if value == point and (name in wanted or len(name) < 16):
                    wanted.setdefault(name, value)
                    break
    return sorted(wanted.items(), key=lambda item: item[0].encode())


def widths(agl: dict[str, int], known: set[int], font: str) -> list[tuple[int, int]]:
    out = {}
    for _, width, name in afm(font):
        point = agl.get(name)
        if point is not None and point in known and point < 0x10000:
            out.setdefault(point, width)
    return sorted(out.items())


def bytes_lines(values: list[int], per_line: int = 3) -> list[str]:
    """VALUES, bytes, packed eight to a cell, little-endian."""

    data = bytes(values) + bytes(-len(values) % 8)
    cells = [int.from_bytes(data[i:i + 8], "little") for i in range(0, len(data), 8)]
    lines = []
    for start in range(0, len(cells), per_line):
        lines.append("  " + " ".join(f"0x{cell:016X} ," for cell in cells[start:start + per_line]))
    return lines


def u16(values: list[int]) -> list[int]:
    out = []
    for value in values:
        out += [value & 255, value >> 8]
    return out


def generate() -> str:
    agl = glyph_list(AGL)
    zapf = glyph_list(ZAPF)
    out = [
        "\\ =================================================================",
        "\\  text-tables.f — PDF's simple encodings, glyph names and the",
        "\\  widths of the standard fonts",
        "\\ =================================================================",
        "\\  GENERATED by local_testing/generate_pdf_text_tables.py from PDF",
        "\\  32000-1 Annex D, the Adobe Glyph List and the Adobe Glyph List",
        "\\  for New Fonts, and URW's base-35 font metrics.  Do not edit.",
        "\\",
        "\\  PDF-ENC-xxx       256 code points, two bytes each, little-endian,",
        "\\                    0 for a code with none.",
        "\\  _PDT-NAMES        the glyph names, sorted by their bytes, each a",
        "\\                    length byte then the name.",
        "\\  Byte tables are packed eight bytes to a cell, little-endian.",
        "\\  _PDT-NAME-AT      cells: offset in _PDT-NAMES << 32 | code point.",
        "\\  _PDT-W-xxx        two-byte pairs, sorted: code point, width.",
        "\\ =================================================================",
        "",
        "PROVIDED akashic-pdf-text-tables",
        "",
    ]
    tables = encodings(agl, zapf)
    for name, values in tables.items():
        out.append(f"CREATE PDF-ENC-{name}")
        out += bytes_lines(u16(values))
    pairs = names(agl)
    pool, index = [], []
    for name, point in pairs:
        index.append((len(pool), point))
        raw = name.encode("ascii")
        pool += [len(raw)] + list(raw)
    out.append("CREATE _PDT-NAMES")
    out += bytes_lines(pool)
    out.append("CREATE _PDT-NAME-AT")
    for start in range(0, len(index), 4):
        out.append("  " + " ".join(f"{offset << 32 | point} ," for offset, point in index[start:start + 4]))
    out.append(f"{len(index)} CONSTANT _PDT-NAME-N")
    known = {point for key in ("STANDARD", "WINANSI", "MACROMAN", "PDFDOC")
             for point in tables[key]} | {agl[name] for name in LIGATURES if name in agl}
    for name, font in BASE_FONTS:
        pairs16 = widths(agl, known, font)
        out.append(f"CREATE _PDT-W-{name}")
        flat = []
        for point, width in pairs16:
            flat += [point, width]
        out += bytes_lines(u16(flat))
        out.append(f"{len(pairs16)} CONSTANT _PDT-W-{name}-N")
    out.append("")
    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true",
                        help="fail if the checked-in tables differ")
    args = parser.parse_args()
    text = generate()
    if args.check:
        if TARGET.read_text(encoding="utf-8") != text:
            print("akashic/pdf/text-tables.f is out of date", file=sys.stderr)
            return 1
        return 0
    TARGET.write_text(text, encoding="utf-8")
    print(f"wrote {TARGET} ({len(text):,} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
