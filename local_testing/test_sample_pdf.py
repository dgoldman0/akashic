#!/usr/bin/env python3
"""The sample PDFs on the Desktop disk (sample_pdf.py), read by Akashic.

Each copy is the same file every time it is written.  Akashic's PDF reader
reads the plain, the tagged and the encrypted copy as the same document:
three pages of headings, paragraphs, two lists, two pictures and code; its
links to a page and to the web; its outline as its contents; and each
picture made into a file a view shows.
"""

from __future__ import annotations

import importlib

import pytest

import sample_pdf
from test_pdf_document import (CODE, FIGURE, HEADING, OK, PAGE, PARAGRAPH, Reader,
                               _anchor, _contents, _links)

BULLET, NUMBERED = 2, 3


@pytest.fixture(scope="module")
def reader():
    return Reader()


def test_each_copy_is_the_same_file_each_time() -> None:
    again = importlib.reload(sample_pdf)
    for name, data in sample_pdf.SAMPLES.items():
        assert again._document(tagged=name == "tagged.pdf",
                               encrypted=name == "encrypted.pdf") == data


EXPECTED = [
    (PAGE, 0, "1"),
    (HEADING, 1, "A sample PDF"),
    (PARAGRAPH, 0, "This document shows how Akashic reads a PDF: its text flows to the width "
                   "of the view, a page at a time, as you scroll. A small program wrote it, so "
                   "it is the same file on every disk."),
    (PARAGRAPH, 0, "The pictures are on the next page, and the last page has some code. "
                   "Akashic is described at akashic.example on the web."),
    (HEADING, 2, "Lists"),
    (PARAGRAPH, 0, "Select a file in File Explorer."),
    (PARAGRAPH, 0, "Press c to see its contents."),
    (PARAGRAPH, 0, "Follow a link to read the page it names."),
    (PARAGRAPH, 0, "Open the document."),
    (PARAGRAPH, 0, "Scroll to the end."),
    (PARAGRAPH, 0, "Go back to the top."),
    (PAGE, 0, "2"),
    (HEADING, 2, "Pictures"),
    (PARAGRAPH, 0, "A photograph, kept as the JPEG file it was, which a rich terminal shows:"),
    (FIGURE, 0, "picture 110"),
    (PARAGRAPH, 0, "The same sky, kept as samples that Akashic turns into a QOI file:"),
    (FIGURE, 0, "picture 111"),
    (PARAGRAPH, 0, "Both pictures are 160 by 100 pixels."),
    (PAGE, 0, "3"),
    (HEADING, 2, "The end"),
    (PARAGRAPH, 0, "Some code, in a fixed-pitch font:"),
    (CODE, 0, ": SQUARE  ( n -- n*n )  DUP * ;\n9 SQUARE ."),
    (PARAGRAPH, 0, "Back to the first page."),
]


@pytest.mark.parametrize("name", ["sample.pdf", "tagged.pdf", "encrypted.pdf"])
def test_each_copy_reads_as_the_same_document(reader, name) -> None:
    assert reader.open(sample_pdf.SAMPLES[name]) == OK
    contents = _contents(reader)
    for part in range(3):
        assert reader.read(part) == OK
    blocks = reader.blocks()
    got = [(b["kind"], b["level"],
            (b["figure"] if b["kind"] == FIGURE else b["text"]).decode()) for b in blocks]
    assert got == EXPECTED, name
    items = [b["containers"][0][:3] for b in blocks if b["containers"]]
    assert items == [(BULLET, 2, 0)] * 3 + [(NUMBERED, 3, n) for n in (1, 2, 3)], name
    found = {}
    for index in range(len(blocks)):
        for text, target in _links(reader, index):
            found[text] = _anchor(reader, target) if target.startswith(b"#") else target
    assert found == {b"the last page": 2, b"akashic.example": b"https://akashic.example/",
                     b"the first page": 0}, name
    assert contents == [(0, "A sample PDF", 0), (1, "Lists", 0), (0, "Pictures", 1),
                        (0, "The end", 2)], name
    assert reader.close() == 0
