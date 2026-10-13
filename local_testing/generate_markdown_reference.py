#!/usr/bin/env python3
"""Record what the CommonMark reference parser makes of a Markdown corpus.

The corpus is ``markdown_corpus.HANDWRITTEN`` and seeded random documents.
commonmark.js 0.30.0, the reference implementation of CommonMark 0.30, reads
each one, and the blocks a document view shows for its tree are written to
``fixtures/markdown/reference.json``.  ``test_markdown.py`` checks the
reader against that file, so the test needs neither node nor commonmark.js.

This is a maintainer command, not part of a test run:

    npm pack commonmark@0.30.0 && tar xzf commonmark-0.30.0.tgz
    (cd package && npm install --omit=dev)
    python3 local_testing/generate_markdown_reference.py --commonmark package

``--check`` exits nonzero when the checked-in file differs from what the
reference parser produces now.

markdown-it-py, the other CommonMark reader at hand, differs from the
reference parser where the specification's examples do not reach: it keeps
a link that holds a picture holding a link, matches emphasis across a pair
already matched, loses code spans after scanning a link's backticks, counts a
link reference definition as a block when it decides a list is loose, and
ends a reference definition at its line.  The reader follows the reference
parser, so the corpus is checked against it, and markdown-it-py checks only
GitHub tables, which the reference parser does not read.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import markdown_corpus
import markdown_harness

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "markdown" / "reference.json"
SEED = 12
COUNT = 120
READER = "commonmark.js 0.30.0"


def corpus() -> list[str]:
    return list(markdown_corpus.HANDWRITTEN) + markdown_corpus.documents(SEED, COUNT)


def encode_block(block: markdown_harness.Block) -> list:
    return [
        block.kind,
        block.level,
        block.rows_before,
        block.inside,
        [[c.kind, c.width, c.number, int(c.start)] for c in block.containers],
        block.text.decode("utf-8"),
        "".join(f"{meaning:x}" for meaning in block.meanings),
        block.figure.decode("utf-8"),
        [[start, end, target.decode("utf-8")] for start, end, target in block.links],
    ]


def decode_block(data: list) -> markdown_harness.Block:
    kind, level, rows, inside, containers, text, meanings, figure, links = data
    return markdown_harness.Block(
        kind,
        level,
        rows,
        inside,
        tuple(markdown_harness.Container(k, w, n, bool(s)) for k, w, n, s in containers),
        text.encode("utf-8"),
        tuple(int(meaning, 16) for meaning in meanings),
        figure.encode("utf-8"),
        tuple((start, end, target.encode("utf-8")) for start, end, target in links),
    )


def render(commonmark_js: str) -> str:
    sources = corpus()
    trees = markdown_harness.reference_trees(sources, commonmark_js)
    documents = [
        {"source": source,
         "blocks": [encode_block(b) for b in markdown_harness.reference_document(tree)]}
        for source, tree in zip(sources, trees)
    ]
    data = {"reader": READER, "seed": SEED, "count": COUNT, "documents": documents}
    return json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n"


def load() -> tuple[list[str], list[list[markdown_harness.Block]]]:
    data = json.loads(FIXTURE.read_text(encoding="utf-8"))
    assert data["reader"] == READER
    sources = [document["source"] for document in data["documents"]]
    blocks = [[decode_block(b) for b in document["blocks"]] for document in data["documents"]]
    return sources, blocks


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--commonmark", required=True,
                        help="commonmark.js 0.30.0's package directory")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    package = json.loads((Path(args.commonmark) / "package.json").read_text())
    if package.get("version") != "0.30.0":
        print(f"commonmark.js 0.30.0 is required, not {package.get('version')}",
              file=sys.stderr)
        return 1
    text = render(str(Path(args.commonmark).resolve()))
    if args.check:
        current = FIXTURE.read_text(encoding="utf-8") if FIXTURE.exists() else ""
        if current != text:
            print(f"{FIXTURE} is stale; rerun the generator", file=sys.stderr)
            return 1
        print(f"{FIXTURE} matches {READER}")
        return 0
    FIXTURE.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE.write_text(text, encoding="utf-8")
    print(f"wrote {FIXTURE}: {len(text.encode('utf-8')):,} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
