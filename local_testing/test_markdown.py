#!/usr/bin/env python3
"""markup/markdown.f: Markdown read as a document.

Every block's kind, level, blank rows, quotes and list items, and its text,
meanings, links and figure must equal what the CommonMark reference parser
(commonmark.js 0.30.0) makes of the same Markdown, shown by a document's
rules; ``fixtures/markdown/reference.json`` records that for handwritten
and random documents.  GitHub tables, which the reference parser does not
read, are checked against markdown-it-py.  Each document's memory must all
come back when it closes.
"""

from __future__ import annotations

import re

import pytest

import generate_markdown_reference as reference
import markdown_corpus
import markdown_harness as h
from forth_snapshot import program_output

S_OK, S_MEMORY, S_READ, S_INVALID = 0, 1, 2, 3


def _encode(url: str) -> str:
    from mdurl import encode

    return encode(url)


def test_documents_match_the_commonmark_reference() -> None:
    sources, expected = reference.load()
    reads = h.read_documents([source.encode("utf-8") for source in sources])
    for source, read, blocks in zip(sources, reads, expected):
        assert read.status == S_OK, source
        assert read.held_after_close == 0, source
        assert h.normalized(read.blocks, _encode) == blocks, source


def test_tables_match_markdown_it() -> None:
    pytest.importorskip("markdown_it")
    sources = markdown_corpus.table_documents(7, 120)
    reads = h.read_documents([source.encode("utf-8") for source in sources])
    normalize = h.markdown_it().normalizeLink
    for source, read in zip(sources, reads):
        assert read.status == S_OK and read.held_after_close == 0, source
        assert h.normalized(read.blocks, normalize) == h.expected_document(source), source


def _text(read: h.Read) -> list[bytes]:
    return [block.text for block in read.blocks]


def test_line_endings_and_damaged_text() -> None:
    """CR, LF and CRLF end lines alike; controls and ill-formed UTF-8 show
    as U+FFFD, and NUL too, as CommonMark asks."""

    documents = [
        b"a\r\nb\rc\n\rd",
        b"x\x00y \x01z \x7f w",
        b"bad \xff byte \xe2\x82 cut \xed\xa0\x80 surrogate \xf0\x9f\x98",
        b"```\n\x00\x02\tz\n```",
    ]
    reads = h.read_documents(documents)
    assert _text(reads[0]) == [b"a b c", b"d"]
    assert _text(reads[1]) == ["x�y �z � w".encode()]
    assert _text(reads[2]) == [
        "bad � byte � cut ��� surrogate �".encode()
    ]
    assert _text(reads[3]) == ["��  z".encode()]
    assert all(read.held_after_close == 0 for read in reads)


def test_figures_and_lists() -> None:
    reads = h.read_documents([
        b"![A *sunset*](sunset.qoi)\n\n![](bare.qoi)\n\n![a](b) ![c](d)\n\n[![x](y)](z)",
        b"9. nine\n10. ten\n\n- \n\n> - a\n>\n>   b\n",
    ])
    figures = reads[0].blocks
    assert [b.kind for b in figures] == [h.FIGURE, h.FIGURE, h.PARAGRAPH, h.PARAGRAPH]
    assert figures[0].figure == b"sunset.qoi" and figures[0].text == b"A sunset"
    assert figures[0].meanings == (0, 0) + (h.EMPHASIS,) * 6 and figures[0].links == ()
    assert figures[1].text == b"" and figures[1].figure == b"bare.qoi"
    # A picture within text shows its description as a link to the picture,
    # and a linked picture as the link.
    assert figures[2].links == ((0, 1, b"b"), (2, 3, b"d"))
    assert figures[3].links == ((0, 1, b"z"),)

    blocks = reads[1].blocks
    # Numbers take the width of the widest, right-aligned with ". ".
    assert [c.width for b in blocks[:2] for c in b.containers] == [4, 4]
    assert [c.number for b in blocks[:2] for c in b.containers] == [9, 10]
    # An empty item shows its bullet beside an empty paragraph.
    assert blocks[2].kind == h.PARAGRAPH and blocks[2].text == b""
    assert blocks[2].containers == (h.Container(h.BULLET, 2, 0, True),)
    # A loose list in a quote: the blank row lies inside both.
    assert blocks[4].rows_before == 1 and blocks[4].inside == 2
    assert blocks[4].containers == (h.Container(h.QUOTE, 2, 0, False),
                                   h.Container(h.BULLET, 2, 0, False))


def _forth(lines: list[str], data: bytes = b"") -> str:
    def setup(system) -> None:
        if data:
            system._raw_mem_write_span(h._file_address(), data)

    lines = lines + ['DEPTH ." @D:" . CR']
    output = program_output(h.SNAPSHOT.run(lines, setup=setup), lines)
    assert "@D:0 " in output, output[-2000:]
    assert "not found" not in output and "underflow" not in output, output[-2000:]
    return output


SAMPLE = (
    b"# Notes\n\nSome *text* with a [link](other.md) and `code`.\n\n"
    b"> A quote\n> - with an item\n\n```\ncode\n```\n\n## Notes\n\n---\n"
)


def test_memory_comes_only_from_the_caller_and_all_comes_back() -> None:
    """Every budget too small to open the document fails with DOC-S-MEMORY
    and takes nothing; a budget large enough opens it."""

    lines = [": MKT-TRY  ( budget -- )",
             f"  MKT-MSRC-INIT MKT-FILE {len(SAMPLE)} MKT-SRC @ MEDSRC-MEMORY",
             "  MKT-SRC @ MD-READER MKT-MSRC @ MKT-DOC @ DOC-OPEN",
             '  ." S=" . ." H=" MKT-MSRC @ MSRC-HELD@ .',
             '  MKT-DOC @ DOC-CLOSE ." C=" MKT-MSRC @ MSRC-HELD@ . CR ;']
    budgets = (64, 512, 1024, 2048, 4096, 8192, 16384, 1 << 20)
    lines += [f"{budget} MKT-TRY" for budget in budgets]
    output = _forth(lines, SAMPLE)
    results = [tuple(int(v) for v in m)
               for m in re.findall(r"S=(-?\d+)\s+H=(-?\d+)\s+C=(-?\d+)", output)]
    assert len(results) == len(budgets), output[-2000:]
    statuses = [status for status, _held, _closed in results]
    assert statuses[-1] == S_OK and S_MEMORY in statuses
    assert set(statuses) <= {S_OK, S_MEMORY}
    # Once a budget suffices, every larger one does.
    assert statuses == sorted(statuses, reverse=True)
    for status, held, closed in results:
        assert closed == 0
        if status != S_OK:
            assert held == 0


def test_a_source_that_cannot_be_read_says_so() -> None:
    lines = [
        ": MKT-BAD-READ  ( buf len offset ctx -- ior )  2DROP 2DROP -1 ;",
        ": MKT-BAD-RELEASE  ( ctx -- )  DROP ;",
        "0 MKT-MSRC-INIT",
        "100 ' MKT-BAD-READ ' MKT-BAD-RELEASE 0 MKT-SRC @ MEDSRC-INIT",
        "MKT-SRC @ MD-READER MKT-MSRC @ MKT-DOC @ DOC-OPEN",
        '." S=" . ." H=" MKT-MSRC @ MSRC-HELD@ . CR',
    ]
    output = _forth(lines)
    assert re.search(r"S=(-?\d+)\s+H=(-?\d+)", output).groups() == (str(S_READ), "0")


def test_content_is_read_on_demand_kept_and_given_back() -> None:
    """A block's content is read when asked for, the same content is given
    again while kept, and DOC-KEEP gives back what lies outside its range
    (the reader keeps its own buffers for the next block); headings are
    found by their anchors."""

    lines = [
        "0 MKT-MSRC-INIT",
        f"MKT-FILE {len(SAMPLE)} MKT-SRC @ MEDSRC-MEMORY",
        "MKT-SRC @ MD-READER MKT-MSRC @ MKT-DOC @ DOC-OPEN DROP",
        '." N=" MKT-DOC @ DOC-COUNT . CR',
        "VARIABLE MKT-H0  MKT-MSRC @ MSRC-HELD@ MKT-H0 !",
        "VARIABLE MKT-C1",
        '1 MKT-DOC @ DOC-CONTENT DROP MKT-C1 !',
        '." GROWN=" MKT-MSRC @ MSRC-HELD@ MKT-H0 @ > . CR',
        '." SAME=" 1 MKT-DOC @ DOC-CONTENT DROP MKT-C1 @ = . CR',
        "0 MKT-DOC @ DOC-CONTENT 2DROP 2 MKT-DOC @ DOC-CONTENT 2DROP",
        "1 2 MKT-DOC @ DOC-KEEP",
        "VARIABLE MKT-H1  MKT-MSRC @ MSRC-HELD@ MKT-H1 !",
        "1 2 MKT-DOC @ DOC-KEEP",
        '." STEADY=" MKT-MSRC @ MSRC-HELD@ MKT-H1 @ = . CR',
        '." KEPT=" 1 MKT-DOC @ DOC-CONTENT DROP MKT-C1 @ = . CR',
        "0 0 MKT-DOC @ DOC-KEEP",
        '." FREED=" MKT-MSRC @ MSRC-HELD@ MKT-H1 @ < . CR',
        '." A1=" S" notes" MKT-DOC @ DOC-ANCHOR . CR',
        '." A2=" S" notes-1" MKT-DOC @ DOC-ANCHOR . CR',
        '." A3=" S" nothing" MKT-DOC @ DOC-ANCHOR . CR',
        "MKT-DOC @ DOC-CLOSE",
        '." HELD=" MKT-MSRC @ MSRC-HELD@ . CR',
    ]
    output = _forth(lines, SAMPLE)
    values = dict(re.findall(r"([A-Z0-9]+)=(-?\d+)", output))
    assert values["N"] == "7"
    assert values["GROWN"] == "-1" and values["SAME"] == "-1"
    assert values["STEADY"] == "-1" and values["KEPT"] == "-1"
    assert values["FREED"] == "-1"
    # Two headings named "Notes": the first is notes, the second notes-1.
    assert (values["A1"], values["A2"], values["A3"]) == ("0", "5", "-1")
    assert values["HELD"] == "0"


def test_a_long_document_and_long_lines() -> None:
    """Lines span the reader's chunks, and a long document reads whole."""

    line = ("word " * 2000).strip()
    long_lines = f"# {line}\n\n{line}\n\n```\n{line}\n```\n".encode()
    many = b"".join(b"Paragraph %d with *emphasis* and `code`.\n\n" % n for n in range(1500))
    reads = h.read_documents([long_lines, many])
    assert [len(b.text) for b in reads[0].blocks] == [len(line)] * 3
    assert len(reads[1].blocks) == 1500
    assert reads[1].blocks[1499].text == b"Paragraph 1499 with emphasis and code."
    assert all(read.held_after_close == 0 for read in reads)
