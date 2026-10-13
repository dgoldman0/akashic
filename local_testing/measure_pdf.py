#!/usr/bin/env python3
"""What a long PDF costs the device's document view, in guest steps.

This counts the steps on the MegaPad simulator, natively, for a PDF of
about a hundred pages that xelatex writes from a generated TeX source: a
table of contents whose entries link to their sections, fifty sections of
paragraphs, a reference from each section to the next, and an outline.
The document is shown in a document view of each area given, and each
phase is counted on its own, each page read and each draw apart:

- opening it: the cross-reference, the page tree's count and the page
  labels, and the view, with no page read;
- its first page: reading it, with the fonts it uses, and drawing it;
- settling: reading each page within a screen below, a page a service
  call, and the draw after each;
- scrolling a screen, then settling: the pages that come within reach;
- following the contents' link to the last section, which reads its page
  alone and puts its heading at the top, then settling around it;
- making the contents, then going to the outline's middle entry, a page
  not read yet, and settling around it.

After each phase it records how many pages are read and the bytes the
view's memory source holds: the document, its reader's state with each
read page's text, meanings and spans, the fonts read, and the view, which
gives back the content of blocks it no longer shows.

A semantic step is one guest instruction or primitive the simulator
counts.  The counts depend on the document and the area, not on the host,
though another TeX may write a different file.

Usage: measure_pdf.py [--area COLSxROWS ...] [--json PATH]
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import test_document_view as view  # noqa: E402

SECTIONS = 50
PARAGRAPHS = 14

SENTENCES = (
    "A document grows as it is read, so opening a long file costs its first pages alone.",
    "Each page keeps its text and what each part of it means, never laid out again.",
    "The view asks for a page when it comes within a screen of it, one page a call.",
    "A link names a page and a place on it, and following one reads that page alone.",
    "Pictures become files the terminal shows, made a step at a time while in view.",
    "Fonts read for one page serve the pages after it, so later pages cost less.",
    "The outline lists the sections, and choosing one shows its heading at the top.",
    "Words split at a line's end are joined, and the page's number is left out.",
)


def tex_source() -> str:
    """The TeX source: contents, then sections of paragraphs that each
    refer to the next section."""

    parts = [r"\documentclass{article}\usepackage{hyperref}\begin{document}",
             r"\title{A long document}\author{measure\_pdf.py}\maketitle",
             r"\tableofcontents\newpage"]
    for s in range(SECTIONS):
        parts.append(rf"\section{{Section {s + 1}}}\label{{sec:{s}}}")
        following = (s + 1) % SECTIONS
        parts.append(rf"Section~\ref{{sec:{following}}} comes after this one.")
        for p in range(PARAGRAPHS):
            sentences = [SENTENCES[(s + p + k) % len(SENTENCES)] for k in range(6)]
            parts.append(" ".join(sentences) + "\n")
    parts.append(r"\end{document}")
    return "\n\n".join(parts)


def write_pdf() -> tuple[bytes, str]:
    """The PDF xelatex writes, and xelatex's version."""

    with tempfile.TemporaryDirectory() as work:
        root = Path(work)
        (root / "long.tex").write_text(tex_source(), encoding="utf-8")
        for _ in range(2):
            subprocess.run(["xelatex", "-interaction=batchmode", "long.tex"], cwd=root,
                           capture_output=True, check=True)
        version = subprocess.run(["xelatex", "--version"], capture_output=True,
                                 text=True).stdout.splitlines()[0]
        return (root / "long.pdf").read_bytes(), version


HELPERS = r"""
: MP-READ#  ( -- n )
    0 DV-DOC DOC-PARTS 0 ?DO I DV-DOC DOC-PART-READ? IF 1+ THEN LOOP ;
: MP-STATE  ( -- )
    ." STATE " MP-READ# . DV-DOC DOC-PARTS . DV-DOC DOC-COUNT . DV-MSRC MSRC-HELD@ . CR ;
\ Block I's links: each target in hex.
: MP-LINKS  ( i -- )
    DV-DOC DOC-CONTENT IF DROP EXIT THEN
    DUP DCT-LINK-COUNT 0 ?DO
        I OVER DCT-LINK@ ." L " DV-HEX 2DROP CR
    LOOP DROP ;
256 XBUF MP-TARGET
"""


class Measure:
    def __init__(self, pdf: bytes, cols: int, rows: int):
        self.runtime = view._runtime(b"", b"", roots=("pdf/document.f",))
        self.run(HELPERS)
        self.run(f"{len(pdf)} XBUF MP-FILE")
        self.runtime.execute("MP-FILE")
        self.file = self.runtime.main_context.data.pop()
        self.runtime.memory.write_bytes(self.file, pdf)
        self.runtime.execute("MP-TARGET")
        self.target = self.runtime.main_context.data.pop()
        self.size = len(pdf)
        for line in ("0 DV-MSRC-INIT", "300 100 SCR-NEW SCR-USE",
                     f"0 0 {rows} {cols} RGN-NEW DV-RGN !  {rows} DV-H !"):
            self.run(line)
        self.rows = rows

    def run(self, line: str) -> int:
        result = self.runtime.evaluate((line + "\n").encode(), source_name="measure",
                                       step_budget=4_000_000_000)
        return result.semantic_steps

    def output(self) -> str:
        return self.runtime.drain_uart_output().decode("utf-8", errors="replace")

    def state(self) -> dict:
        self.output()
        self.run("MP-STATE")
        read, parts, blocks, held = map(int, re.search(
            r"STATE (\d+) (\d+) (\d+) (\d+)", self.output()).groups())
        return {"pages_read": read, "pages": parts, "blocks": blocks, "bytes_held": held}

    def phase(self, line: str) -> dict:
        steps = self.run(line)
        return {"steps": steps, **self.state()}

    def pending(self) -> bool:
        self.output()
        self.run("DV-W @ DOCV-PENDING? .")
        return int(self.output().split()[0]) != 0

    def settle(self) -> dict:
        """Draw, then serve and draw while the view needs a page: the steps
        of each read and of each draw."""

        reads, draws = [], [self.run("DV-DRAW")]
        while self.pending():
            reads.append(self.run("DV-W @ DOCV-SERVICE DROP"))
            draws.append(self.run("DV-DRAW"))
        return {"reads": reads, "draws": draws, **self.state()}

    def links(self) -> list[bytes]:
        """The targets of the links in the blocks read, in order."""

        self.output()
        for index in range(self.state()["blocks"]):
            self.run(f"{index} MP-LINKS")
        return [bytes.fromhex(hexed) for hexed in re.findall(r"L ([0-9a-f]*)", self.output())]


def measure(pdf: bytes, cols: int, rows: int) -> dict:
    m = Measure(pdf, cols, rows)
    phases = {"open": m.phase(f"MP-FILE {m.size} PDF-DOC-READER DV-OPEN-WITH")}
    m.run("DV-DRAW")
    phases["first page"] = {"read": m.run("DV-W @ DOCV-SERVICE DROP"),
                            "draw": m.run("DV-DRAW"), **m.state()}
    phases["settle"] = m.settle()
    phases["scroll a screen"] = {"scroll": m.run(f"{rows} DV-W @ DOCV-SCROLL"),
                                 **m.settle()}
    # The contents' link to the last section: hyperref names each section's
    # destination "section." and its number.
    sections = {}
    for target in m.links():
        found = re.fullmatch(rb"#.\(section\.(\d+)\)", target)
        if found:
            sections[int(found.group(1))] = target
    if SECTIONS not in sections:
        raise SystemExit("the pages read show no link to the last section")
    target = sections[SECTIONS]
    m.runtime.memory.write_bytes(m.target, target)
    phases["follow the link to the last section"] = {
        "follow": m.run(f"MP-TARGET {len(target)} DV-W @ DOCV-FOLLOW"), **m.settle()}
    phases["make the contents"] = m.phase("DV-DOC DOC-CONTENTS 2DROP")
    m.output()
    m.run("DV-DOC DOC-CONTENTS DROP .")
    entries = int(m.output().split()[0])
    phases["go to the outline's middle entry"] = {
        "go": m.run(f"{entries // 2} DV-W @ DOCV-GO-ENTRY"), **m.settle()}
    m.output()
    m.run("DV-CLOSE")
    closed = m.output()
    return {
        "area": [cols, rows],
        "file_bytes": len(pdf),
        "phases": phases,
        "outline_entries": entries,
        "held_after_close": int(re.search(r"HELD=(\d+)", closed).group(1)),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--area", action="append", default=[], metavar="COLSxROWS",
                        help="a view's size in cells; File Explorer's previews by default")
    parser.add_argument("--json", type=Path, help="also write the counts here")
    args = parser.parse_args()
    if shutil.which("xelatex") is None:
        raise SystemExit("xelatex writes the PDF this measures; it is not installed")
    pdf, version = write_pdf()
    areas = [tuple(int(part) for part in area.split("x")) for area in args.area]
    report = {"tex": version,
              "areas": [measure(pdf, cols, rows) for cols, rows in areas or ((195, 78), (64, 36))]}
    text = json.dumps(report, indent=2)
    print(text)
    if args.json is not None:
        args.json.write_text(text + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
