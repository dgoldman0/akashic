#!/usr/bin/env python3
"""Akashic pdf/content.f: a page's content read for its runs of text.

Pages written by hand check each part of the interpreter: runs that
continue and runs that a gap starts, positions and sizes through the text
matrix, the graphics matrix, saves and restores; character and word
spacing, horizontal scale, leading, rise and the quoting operators;
invisible text; marked content with MCIDs and artifacts; form XObjects
under their matrices, with their own resources, and one that draws
itself; and an inline image passed over.  Documents xelatex, pdflatex,
LibreOffice and Ghostscript write are read too, and their text compared with
what pdftotext reads from the same pages.  Every byte is given back.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import unicodedata
import zlib
from pathlib import Path

import pytest

from forth_dependencies import dependency_order
from test_pdf_file import stream_object, write_pdf
from test_uidl_collection_snapshot import AK, KDOS_PATH, _load_forth_lines
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime

OK, MEMORY, DAMAGED = 0, 1, 2
BOLD, ITALIC, FIXED, SERIF = 1, 2, 4, 8
INVISIBLE, ARTIFACT = 256, 512
FILE_BYTES = 8 << 20
ONE = 1 << 16

PRELUDE = f"""
{FILE_BYTES} XBUF CN-BYTES
CREATE CN-SRCS MEDSRC-SIZE 7 + ALLOT  : CN-SRC  CN-SRCS 7 + -8 AND ;
CREATE CN-MSRCS MSRC-SIZE 7 + ALLOT  : CN-MSRC  CN-MSRCS 7 + -8 AND ;
CREATE CN-FILES PDF-FILE-SIZE 7 + ALLOT  : CN-FILE  CN-FILES 7 + -8 AND ;
CREATE CN-PAGES PDF-PAGE-SIZE 7 + ALLOT  : CN-PAGE  CN-PAGES 7 + -8 AND ;
CREATE CN-CONTS PDF-CONTENT-SIZE 7 + ALLOT  : CN-CONT  CN-CONTS 7 + -8 AND ;
CREATE CN-SETS PDF-FONTS-SIZE 7 + ALLOT  : CN-SET  CN-SETS 7 + -8 AND ;
: CN-ALLOC  ( bytes ctx -- addr|0 )  DROP ALLOCATE IF DROP 0 THEN ;
: CN-FREE  ( addr bytes ctx -- )  2DROP FREE ;
: CN-OPEN  ( u -- status )
    CN-BYTES SWAP CN-SRC MEDSRC-MEMORY
    ['] CN-ALLOC ['] CN-FREE 0 0 CN-MSRC MSRC-INIT
    CN-PAGE PDF-PAGE-SIZE 0 FILL  CN-CONT PDF-CONTENT-SIZE 0 FILL  CN-SET PDF-FONTS-SIZE 0 FILL
    CN-SRC CN-MSRC CN-FILE PDF-OPEN ;
: CN-CLOSE  ( -- held )
    CN-CONT PDF-CONTENT-FREE  CN-PAGE PDF-PAGE-END  CN-SET PDF-FONTS-FREE
    CN-FILE PDF-CLOSE  CN-MSRC MSRC-HELD@ ;
: CN-COUNT  ( -- n status )  CN-FILE PDF-PAGE-COUNT ;
: CN-READ  ( i -- status )
    CN-CONT PDF-CONTENT-FREE
    CN-FILE CN-PAGE PDF-PAGE-OPEN ?DUP IF EXIT THEN
    CN-PAGE CN-SET CN-CONT PDF-CONTENT-READ  CN-PAGE PDF-PAGE-CLOSE ;
: CN-RUNS  ( -- n )  CN-CONT PDF-CONTENT-RUNS ;
: CN-RUN  ( i -- a u x0 y0 x1 y1 size style mcid )
    CN-CONT PDF-CONTENT-RUN >R
    R@ CN-CONT PDF-RUN-TEXT  R@ PDF-RUN-START  R@ PDF-RUN-END
    R@ PDF-RUN-SIZE  R@ PDF-RUN-STYLE  R> PDF-RUN-MCID ;
: CN-FIGS  ( -- n )  CN-CONT PDF-CONTENT-FIGURES ;
: CN-FIG  ( i -- num x0 y0 x1 y1 at mcid style )
    CN-CONT PDF-CONTENT-FIGURE >R
    R@ PDF-FIG-NUM  R@ PDF-FIG-BOX  R@ PDF-FIG-AT  R@ PDF-FIG-MCID  R> PDF-FIG-STYLE ;
"""


def signed(value: int) -> int:
    return value - (1 << 64) if value >= 1 << 63 else value


class Content:
    def __init__(self):
        self.runtime = MegaForthRuntime(
            memory=create_one_core_address_space(external_size=96 << 20, hbw_size=1 << 20),
            execution_backend="native",
        )
        self.runtime.evaluate(KDOS_PATH.read_bytes(), source_name="kdos.f")
        self.runtime.evaluate(b"ENTER-USERLAND", source_name="userland")
        source = []
        for module in dependency_order(AK, ("pdf/content.f",)):
            source.extend(_load_forth_lines(AK / module))
        source.append(PRELUDE)
        self.runtime.evaluate(("\n".join(source) + "\n").encode(), source_name="pdf-content",
                              step_budget=400_000_000)
        self.runtime.drain_uart_output()
        self.bytes = self.word("CN-BYTES")
        self.steps = 0

    def word(self, name: str) -> int:
        self.runtime.execute(name)
        return self.runtime.main_context.data.pop()

    def call(self, name: str, *args: int) -> tuple[int, ...]:
        stack = self.runtime.main_context.data
        assert stack.depth() == 0, stack.snapshot()
        for value in args:
            stack.push(value)
        self.steps = self.runtime.execute(name, step_budget=8_000_000_000).semantic_steps
        result = tuple(stack.snapshot())
        while stack.depth():
            stack.pop()
        return result

    def open(self, pdf: bytes) -> None:
        assert len(pdf) <= FILE_BYTES
        self.runtime.memory.write_bytes(self.bytes, pdf)
        assert self.call("CN-OPEN", len(pdf)) == (OK,)

    def close(self) -> None:
        assert self.call("CN-CLOSE") == (0,)

    def read(self, index: int = 0) -> int:
        return self.call("CN-READ", index)[0]

    def runs(self) -> list[dict]:
        out = []
        for i in range(self.call("CN-RUNS")[0]):
            a, u, x0, y0, x1, y1, size, style, mcid = self.call("CN-RUN", i)
            out.append({
                "text": self.runtime.memory.read_bytes(a, u).decode("utf-8"),
                "start": (signed(x0) / ONE, signed(y0) / ONE),
                "end": (signed(x1) / ONE, signed(y1) / ONE),
                "size": size / ONE, "style": style, "mcid": signed(mcid),
            })
        return out

    def texts(self) -> list[str]:
        return [run["text"] for run in self.runs()]

    def figures(self) -> list[tuple]:
        out = []
        for i in range(self.call("CN-FIGS")[0]):
            num, x0, y0, x1, y1, at, mcid, style = self.call("CN-FIG", i)
            out.append((num, tuple(round(signed(v) / ONE, 3) for v in (x0, y0, x1, y1)), at,
                        signed(mcid), style))
        return out


@pytest.fixture(scope="module")
def content():
    return Content()


HELVETICA = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"
TIMES = b"<< /Type /Font /Subtype /Type1 /BaseFont /Times-Bold /Encoding /WinAnsiEncoding >>"


def page_pdf(stream: bytes, *, resources: bytes = b"<< /Font << /F1 10 0 R /F2 11 0 R >> >>",
             extra: dict[int, bytes] | None = None) -> bytes:
    objects = {
        1: b"<< /Type /Catalog /Pages 2 0 R >>",
        2: b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        3: b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources " + resources +
           b" /Contents 4 0 R >>",
        4: stream_object(zlib.compress(stream), b"/Filter /FlateDecode"),
        10: HELVETICA, 11: TIMES,
    }
    objects.update(extra or {})
    return write_pdf(objects)


# Helvetica's widths for the characters these pages show.
HW = {" ": 278, "H": 722, "e": 556, "l": 222, "o": 556, "w": 722, "r": 333, "d": 556,
      "W": 944, "A": 667, "g": 556, "a": 556, "p": 556}


def width(text: str, size: float) -> float:
    return sum(HW[c] for c in text) * size / 1000


def near(a: tuple[float, float], b: tuple[float, float]) -> bool:
    return abs(a[0] - b[0]) < 0.01 and abs(a[1] - b[1]) < 0.01


def test_runs_continue_and_gaps_start_others(content):
    content.open(page_pdf(b"BT /F1 12 Tf 72 700 Td (Hello) Tj ( world) Tj 0 -14 Td (Hello) Tj ET\n"
                          b"BT /F1 10 Tf 72 600 Td [(Wo) 80 (rd) -500 (gap)] TJ ET"))
    assert content.read() == OK
    runs = content.runs()
    assert [r["text"] for r in runs] == ["Hello world", "Hello", "Word", "gap"]
    first = runs[0]
    assert near(first["start"], (72, 700)) and first["size"] == 12
    assert near(first["end"], (72 + width("Hello world", 12), 700))
    assert near(runs[1]["start"], (72, 686))
    word_end = 72 + width("Word", 10) - 0.8
    assert near(runs[2]["end"], (word_end, 600))
    assert near(runs[3]["start"], (word_end + 5, 600))
    content.close()


def test_matrices_saves_and_spacing(content):
    stream = (b"q 2 0 0 2 10 20 cm BT /F1 1 Tf 6 0 0 6 30 40 Tm (A) Tj ET Q\n"
              b"BT /F1 10 Tf 100 500 Td 2 Tc 5 Tw 50 Tz (A A) Tj ET\n"
              b"BT /F1 10 Tf 15 TL 100 400 Td (A) Tj T* (A) Tj (A) ' 7 0 (A) \" ET\n"
              b"BT /F1 10 Tf 100 300 Td 3 Ts (A) Tj ET\n"
              b"BT 0 Ts /F2 8 Tf 100 200 Td (A) Tj ET Q Q")
    content.open(page_pdf(stream))
    assert content.read() == OK
    runs = content.runs()
    assert [r["text"] for r in runs] == ["A", "A A", "A", "A", "A", "A", "A", "A"]
    a = runs[0]
    assert near(a["start"], (70, 100)) and a["size"] == 12
    assert near(a["end"], (70 + 2 * 6 * 0.667, 100))
    spaced = runs[1]
    advance = ((667 * 10 / 1000 + 2) * 2 + (278 * 10 / 1000 + 2 + 5)) * 0.5
    assert near(spaced["end"], (100 + advance, 500))
    assert [r["start"][1] for r in runs[2:6]] == [400, 385, 370, 355]
    assert near(runs[6]["start"], (100, 303))
    times = runs[7]
    assert near(times["start"], (100, 200)) and times["style"] & BOLD and times["size"] == 8
    content.close()


def test_invisible_marked_and_artifact_text(content):
    stream = (b"/P << /MCID 3 >> BDC BT /F1 10 Tf 100 700 Td (He) Tj ET EMC\n"
              b"/Artifact BMC BT /F1 10 Tf 100 20 Td (1) Tj ET EMC\n"
              b"/Span << /Lang (en) >> BDC /P << /MCID 4 >> BDC BT /F1 10 Tf 100 600 Td (lo) Tj ET "
              b"EMC EMC\nBT 3 Tr /F1 10 Tf 100 500 Td (ghost) Tj ET")
    content.open(page_pdf(stream))
    assert content.read() == OK
    runs = content.runs()
    assert [(r["text"], r["mcid"]) for r in runs] == [("He", 3), ("1", -1), ("lo", 4), ("ghost", -1)]
    assert runs[1]["style"] & ARTIFACT and not runs[0]["style"] & ARTIFACT
    assert runs[3]["style"] & INVISIBLE
    content.close()


def form(stream: bytes, extra: bytes = b"") -> bytes:
    return stream_object(stream, b"/Type /XObject /Subtype /Form /BBox [0 0 500 500] " + extra)


def test_forms_and_inline_images(content):
    stream = (b"BT /F1 10 Tf 100 700 Td (A) Tj ET\n"
              b"q 1 0 0 1 0 -100 cm /Fm1 Do Q\n"
              b"BI /W 4 /H 4 /BPC 8 /CS /G ID \x00EI\x01\xffZZ EI\n"
              b"BT /F1 10 Tf 100 300 Td (A) Tj ET /Loop Do")
    resources = b"<< /Font << /F1 10 0 R >> /XObject << /Fm1 20 0 R /Loop 22 0 R >> >>"
    extra = {
        20: form(b"BT /F9 10 Tf 0 0 Td (B) Tj ET /Fm2 Do",
                 b"/Matrix [1 0 0 1 50 50] /Resources << /Font << /F9 11 0 R >> "
                 b"/XObject << /Fm2 21 0 R >> >>"),
        21: form(b"BT /F9 10 Tf 0 20 Td (C) Tj ET"),
        22: form(b"BT /F1 10 Tf 5 5 Td (D) Tj ET /Me Do",
                 b"/Resources << /Font << /F1 10 0 R >> /XObject << /Me 22 0 R >> >>"),
    }
    content.open(page_pdf(stream, resources=resources, extra=extra))
    assert content.read() == OK
    runs = content.runs()
    assert [r["text"] for r in runs] == ["A", "B", "C", "A", "D"]
    assert near(runs[1]["start"], (50, -50)) and runs[1]["style"] & BOLD
    assert near(runs[2]["start"], (50, -30))
    assert near(runs[4]["start"], (5, 5))
    content.close()


def normalized(text: str) -> str:
    return re.sub(r"\s+", "", unicodedata.normalize("NFKC", text))


def compare_with_pdftotext(content: Content, pdf: Path) -> int:
    """Read every page; its runs' text, joined, must be what pdftotext reads."""

    content.open(pdf.read_bytes())
    count, status = content.call("CN-COUNT")
    assert status == OK and count > 0
    steps = 0
    for index in range(count):
        assert content.read(index) == OK, index
        steps += content.steps
        ours = normalized("".join(content.texts()))
        theirs = normalized(subprocess.run(
            ["pdftotext", "-raw", "-f", str(index + 1), "-l", str(index + 1), str(pdf), "-"],
            check=True, capture_output=True, text=True).stdout)
        assert ours == theirs, (index, ours[:300], theirs[:300])
    content.close()
    return steps


needs = pytest.mark.skipif(shutil.which("pdftotext") is None, reason="pdftotext is not installed")

TEX = r"""\documentclass{article}
\usepackage{fontspec}
\setmainfont{DejaVu Serif}
\begin{document}
\section{Reading order}
Office affine fluffy — “quoted” café 𝔸 Ωmega. Ligatures: ffi ffl fi fl.
\textbf{Bold words} and \emph{emphasis}, with \texttt{code} too.
\begin{itemize}\item First point\item Second point\end{itemize}
\end{document}
"""


@needs
@pytest.mark.skipif(shutil.which("xelatex") is None, reason="xelatex is not installed")
def test_a_document_xelatex_wrote(content, tmp_path):
    (tmp_path / "doc.tex").write_text(TEX)
    subprocess.run(["xelatex", "-interaction=batchmode", "doc.tex"], cwd=tmp_path,
                   check=True, capture_output=True)
    compare_with_pdftotext(content, tmp_path / "doc.pdf")


PDFTEX = r"""\documentclass{article}
\begin{document}
\section{Computer Modern}
Office affine fluffy ``quoted'' -- and --- dashes, \textbf{bold} and \emph{emphasis}.
\end{document}
"""


@needs
@pytest.mark.skipif(shutil.which("pdflatex") is None, reason="pdflatex is not installed")
def test_a_document_pdflatex_wrote(content, tmp_path):
    (tmp_path / "doc.tex").write_text(PDFTEX)
    subprocess.run(["pdflatex", "-interaction=batchmode", "doc.tex"], cwd=tmp_path,
                   check=True, capture_output=True)
    compare_with_pdftotext(content, tmp_path / "doc.pdf")


@needs
@pytest.mark.skipif(shutil.which("soffice") is None, reason="LibreOffice is not installed")
def test_a_document_libreoffice_wrote(content, tmp_path):
    (tmp_path / "doc.html").write_text(
        "<html><body><h1>A heading</h1><p>Paragraph one, with <b>bold</b> and <i>italic</i>"
        " words; “quotes” and an em dash — here. Ünïcödé café.</p>"
        "<ul><li>first</li><li>second</li></ul><p>Last paragraph.</p></body></html>",
        encoding="utf-8")
    subprocess.run(["soffice", f"-env:UserInstallation=file://{tmp_path}/profile", "--headless",
                    "--convert-to", "pdf", "--outdir", str(tmp_path), str(tmp_path / "doc.html")],
                   check=True, capture_output=True, timeout=120)
    compare_with_pdftotext(content, tmp_path / "doc.pdf")


POSTSCRIPT = rb"""%!PS
/reencode { findfont dup length dict begin { 1 index /FID ne { def } { pop pop } ifelse } forall
  /Encoding ISOLatin1Encoding def currentdict end definefont pop } def
/TB /Times-Bold reencode  /TR /Times-Roman reencode  /HO /Helvetica-Oblique reencode
/TB findfont 18 scalefont setfont 72 720 moveto (A heading) show
/TR findfont 11 scalefont setfont 72 690 moveto (Some text in Times, with \(parentheses\) and quotes.) show
72 676 moveto (Caf\351 na\357ve -- \253guillemets\273 and \265 micro.) show
/HO findfont 10 scalefont setfont 72 650 moveto (Oblique sans on its own line.) show
/Courier findfont 10 scalefont setfont 72 630 moveto (code\(\); x = 1;) show
showpage
"""


@needs
@pytest.mark.skipif(shutil.which("ps2pdf") is None, reason="Ghostscript is not installed")
@pytest.mark.parametrize("options", ((), ("-dEmbedAllFonts=true", "-dSubsetFonts=false")))
def test_a_document_ghostscript_wrote(content, tmp_path, options):
    (tmp_path / "doc.ps").write_bytes(POSTSCRIPT)
    subprocess.run(["ps2pdf", *options, str(tmp_path / "doc.ps"), str(tmp_path / "doc.pdf")],
                   check=True, capture_output=True)
    compare_with_pdftotext(content, tmp_path / "doc.pdf")


def picture(width: int = 2, height: int = 2) -> bytes:
    return stream_object(bytes(width * height), b"/Type /XObject /Subtype /Image /Width %d /Height %d "
                         b"/ColorSpace /DeviceGray /BitsPerComponent 8" % (width, height))


def test_pictures_drawn_are_figures(content):
    stream = (b"BT /F1 10 Tf 100 700 Td (A) Tj ET\n"
              b"q 200 0 0 100 72 500 cm /Im1 Do Q\n"
              b"BT /F1 10 Tf 100 400 Td (B) Tj ET\n"
              b"/Artifact BMC q 10 0 0 10 0 0 cm /Im1 Do Q EMC\n"
              b"/Figure << /MCID 7 >> BDC q 1 0 0 1 300 300 cm /Fm1 Do Q EMC\n"
              b"BI /W 1 /H 1 /BPC 8 /CS /G ID \x00 EI\n"
              b"BT /F1 10 Tf 100 100 Td (C) Tj ET /Fm9 Do")
    resources = (b"<< /Font << /F1 10 0 R >> /XObject << /Im1 30 0 R /Fm1 20 0 R /Fm9 21 0 R >> >>")
    extra = {
        20: form(b"q 0 50 -40 0 0 0 cm /Im2 Do Q", b"/Resources << /XObject << /Im2 31 0 R >> >>"),
        21: form(b"BT /F1 10 Tf 0 0 Td (D) Tj ET", b"/Resources << /Font << /F1 10 0 R >> >>"),
        30: picture(), 31: picture(4, 2),
    }
    content.open(page_pdf(stream, resources=resources, extra=extra))
    assert content.read() == OK
    assert content.texts() == ["A", "B", "C", "D"]
    assert content.figures() == [
        (30, (72.0, 500.0, 272.0, 600.0), 1, -1, 0),
        (30, (0.0, 0.0, 10.0, 10.0), 2, -1, ARTIFACT),
        (31, (260.0, 300.0, 300.0, 350.0), 2, 7, 0),
    ]
    content.close()
