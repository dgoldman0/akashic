#!/usr/bin/env python3
"""Akashic pdf/text-tables.f: PDF's simple encodings, glyph names and the
standard fonts' widths, as the generator wrote them.

The checked-in file must be what the generator writes now, and once
loaded, its tables must hold what the generator computed, byte for byte:
the encodings, the sorted glyph names with their code points, and the
width pairs.  Spot checks tie the tables to their sources.
"""

from __future__ import annotations

import subprocess
import sys

import pytest

import generate_pdf_text_tables as gen
from test_uidl_collection_snapshot import AK, KDOS_PATH, _load_forth_lines
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime


class Tables:
    def __init__(self):
        self.runtime = MegaForthRuntime(
            memory=create_one_core_address_space(external_size=16 << 20, hbw_size=1 << 20),
            execution_backend="native",
        )
        self.runtime.evaluate(KDOS_PATH.read_bytes(), source_name="kdos.f")
        self.runtime.evaluate(b"ENTER-USERLAND", source_name="userland")
        source = _load_forth_lines(AK / "pdf/text-tables.f")
        self.runtime.evaluate(("\n".join(source) + "\n").encode(), source_name="pdf-text-tables",
                              step_budget=200_000_000)
        self.runtime.drain_uart_output()

    def word(self, name: str) -> int:
        self.runtime.execute(name)
        return self.runtime.main_context.data.pop()

    def u16s(self, name: str, count: int) -> list[int]:
        raw = self.runtime.memory.read_bytes(self.word(name), 2 * count)
        return [int.from_bytes(raw[i:i + 2], "little") for i in range(0, len(raw), 2)]


@pytest.fixture(scope="module")
def tables():
    return Tables()


@pytest.fixture(scope="module")
def sources():
    agl = gen.glyph_list(gen.AGL)
    return agl, gen.encodings(agl, gen.glyph_list(gen.ZAPF))


def test_checked_in_file_is_current():
    result = subprocess.run([sys.executable, gen.__file__, "--check"], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr


def test_encodings(tables, sources):
    _, encodings = sources
    for name, values in encodings.items():
        assert tables.u16s(f"PDF-ENC-{name}", 256) == values, name
    win = tables.u16s("PDF-ENC-WINANSI", 256)
    assert win[0x80] == 0x20AC and win[0x93] == 0x201C and win[0x41] == 0x41
    standard = tables.u16s("PDF-ENC-STANDARD", 256)
    assert standard[0x27] == 0x2019 and standard[0xAE] == 0xFB01 and standard[0x80] == 0
    assert tables.u16s("PDF-ENC-MACROMAN", 256)[0x8E] == 0xE9
    assert tables.u16s("PDF-ENC-PDFDOC", 256)[0xA0] == 0x20AC
    symbol = tables.u16s("PDF-ENC-SYMBOL", 256)
    assert symbol[0x61] == 0x3B1 and symbol[0x57] == 0x3A9 and symbol[0x44] == 0x394
    assert symbol[0x6D] == 0x3BC


def test_glyph_names(tables, sources):
    agl, _ = sources
    names = gen.names(agl)
    assert tables.word("PDF-GLYPH-COUNT") == len(names)
    pool = tables.word("PDF-GLYPH-NAMES")
    index = tables.word("PDF-GLYPH-INDEX")
    raw = tables.runtime.memory.read_bytes(index, 8 * len(names))
    seen = []
    for i, (name, point) in enumerate(names):
        cell = int.from_bytes(raw[8 * i:8 * i + 8], "little")
        offset, value = cell >> 32, cell & 0xFFFFFFFF
        length = tables.runtime.memory.read_bytes(pool + offset, 1)[0]
        text = tables.runtime.memory.read_bytes(pool + offset + 1, length).decode("ascii")
        assert (text, value) == (name, point)
        seen.append(text.encode())
    assert seen == sorted(seen)
    lookup = dict(names)
    assert lookup["fi"] == 0xFB01 and lookup["Euro"] == 0x20AC and lookup["quoteright"] == 0x2019


def test_widths(tables, sources):
    agl, encodings = sources
    known = {point for key in ("STANDARD", "WINANSI", "MACROMAN", "PDFDOC")
             for point in encodings[key]} | {agl[name] for name in gen.LIGATURES if name in agl}
    for name, font in gen.BASE_FONTS:
        pairs = gen.widths(agl, known, font)
        assert tables.word(f"PDF-WIDTHS-{name}-N") == len(pairs)
        flat = tables.u16s(f"PDF-WIDTHS-{name}", 2 * len(pairs))
        assert list(zip(flat[0::2], flat[1::2])) == pairs, name
    helvetica = dict(gen.widths(agl, known, "NimbusSans-Regular"))
    assert helvetica[0x20] == 278 and helvetica[ord("W")] == 944
    times = dict(gen.widths(agl, known, "NimbusRoman-Regular"))
    assert times[0x20] == 250 and times[ord("W")] == 944
