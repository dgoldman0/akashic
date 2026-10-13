#!/usr/bin/env python3
"""Run markup/markdown.f in the guest and read back the documents it makes.

``read_documents`` opens Markdown sources as documents in one guest session,
asks every block for its content, and returns the blocks as Python values.
``expected_document`` reads the same Markdown with markdown-it-py, a
CommonMark reader, and applies the rules a document shows text by, so the
two can be compared block for block and byte for byte.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from forth_snapshot import ForthSnapshot, program_output

FILE_BYTES = 1 << 20

# Kinds, as media/document.f and SEMANTIC-CONTENT-1's DOC1 number them.
PARAGRAPH, HEADING, CODE, RULE, FIGURE = 1, 2, 3, 4, 5
QUOTE, BULLET, NUMBERED = 1, 2, 3
# Meanings, as text/text-style.f numbers them.
PLAIN, EMPHASIS, STRONG, CODE_MEANING, LINK = 0, 6, 7, 8, 9

SNAPSHOT = ForthSnapshot(
    ("markup/markdown.f",),
    prelude=(
        f"{FILE_BYTES} XBUF MKT-FILE",
        "VARIABLE MKT-SRC   MEDSRC-SIZE ALLOCATE DROP MKT-SRC !",
        "VARIABLE MKT-MSRC  MSRC-SIZE ALLOCATE DROP MKT-MSRC !",
        "VARIABLE MKT-DOC   DOC-SIZE ALLOCATE DROP MKT-DOC !",
        ": MKT-ALLOC  ( bytes ctx -- addr|0 )  DROP ALLOCATE IF DROP 0 THEN ;",
        ": MKT-FREE  ( addr bytes ctx -- )  2DROP FREE ;",
        ": MKT-MSRC-INIT  ( budget -- )",
        "  >R ['] MKT-ALLOC ['] MKT-FREE 0 R> MKT-MSRC @ MSRC-INIT ;",
        ": MKT-NIB  ( n -- )  DUP 10 < IF 48 + ELSE 87 + THEN EMIT ;",
        ": MKT-HEX  ( a u -- )",
        "  0 ?DO DUP I + C@ DUP 4 RSHIFT MKT-NIB 15 AND MKT-NIB LOOP DROP ;",
        "VARIABLE MKT-I",
        ": MKT-CONTAINERS  ( block -- )",
        "  MKT-DOC @ DOC-CONTAINERS DUP . 0 ?DO",
        "    DUP I CNT-SIZE * + DUP CNT-KIND@ . DUP CNT-WIDTH@ .",
        "    DUP CNT-NUMBER@ . CNT-START? .",
        "  LOOP DROP ;",
        ": MKT-LINKS  ( content -- )",
        "  DUP DCT-LINK-COUNT 0 ?DO",
        '    ." L=" I OVER DCT-LINK@ 2SWAP SWAP . . MKT-HEX',
        "  LOOP DROP ;",
        ": MKT-BLOCK  ( i -- )",
        "  DUP MKT-I ! MKT-DOC @ DOC-BLOCK",
        '  ." B " DUP BLK-KIND@ . DUP BLK-LEVEL@ . DUP BLK-ROWS-BEFORE@ .',
        "  DUP BLK-INSIDE@ . MKT-CONTAINERS",
        '  MKT-I @ MKT-DOC @ DOC-CONTENT ." S=" DUP . IF DROP CR EXIT THEN',
        '  ." K=" DUP DCT-KIND@ . ." V=" DUP DCT-LEVEL@ .',
        '  ." T=" DUP DCT-TEXT MKT-HEX',
        '  ." M=" DUP DCT-MAP OVER DCT-TEXT NIP MKT-HEX',
        '  ." F=" DUP DCT-FIGURE MKT-HEX',
        "  MKT-LINKS CR ;",
        # Open the document at A, read every block, close it.
        ": MKT-DUMP  ( a u budget -- )",
        '  ." @@DOC" CR',
        "  MKT-MSRC-INIT MKT-SRC @ MEDSRC-MEMORY",
        '  MKT-SRC @ MD-READER MKT-MSRC @ MKT-DOC @ DOC-OPEN ." OPEN=" . CR',
        '  ." N=" MKT-DOC @ DOC-COUNT . CR',
        "  MKT-DOC @ DOC-COUNT 0 ?DO I MKT-BLOCK LOOP",
        '  MKT-DOC @ DOC-CLOSE ." HELD=" MKT-MSRC @ MSRC-HELD@ . CR ;',
    ),
)

_FILE_ADDRESS: list[int] = []


def _file_address() -> int:
    if not _FILE_ADDRESS:
        lines = ["MKT-FILE U."]
        text = program_output(SNAPSHOT.run(lines), lines)
        _FILE_ADDRESS.append(int(re.findall(r"\d+", text)[0]))
    return _FILE_ADDRESS[0]


@dataclass(frozen=True)
class Container:
    kind: int
    width: int
    number: int
    start: bool


@dataclass(frozen=True)
class Block:
    kind: int
    level: int
    rows_before: int
    inside: int
    containers: tuple[Container, ...]
    text: bytes = b""
    meanings: tuple[int, ...] = ()
    figure: bytes = b""
    links: tuple[tuple[int, int, bytes], ...] = ()


@dataclass
class Read:
    status: int
    blocks: list[Block] = field(default_factory=list)
    held_after_close: int = 0
    output: str = ""


_BLOCK = re.compile(
    r"B (?P<head>[-\d ]+?) S=(?P<s>-?\d+)\s*"
    r"(?:K=(?P<k>-?\d+)\s+V=(?P<v>-?\d+)\s+T=(?P<t>[0-9a-f]*)\s*M=(?P<m>[0-9a-f]*)\s*"
    r"F=(?P<f>[0-9a-f]*)\s*(?P<links>(?:L=\s*-?\d+\s+-?\d+\s*[0-9a-f]*\s*)*))?$"
)


def _parse(output: str) -> Read:
    status = int(re.search(r"OPEN=(-?\d+)", output).group(1))
    held = int(re.search(r"HELD=(-?\d+)", output).group(1))
    result = Read(status, [], held, output)
    for line in output.splitlines():
        line = line.strip()
        if not line.startswith("B "):
            continue
        match = _BLOCK.match(line)
        assert match is not None, line
        head = [int(value) for value in match.group("head").split()]
        kind, level, rows, inside, count = head[:5]
        assert len(head) == 5 + 4 * count, line
        containers = tuple(
            Container(head[5 + 4 * i], head[6 + 4 * i], head[7 + 4 * i], head[8 + 4 * i] != 0)
            for i in range(count)
        )
        if int(match.group("s")) != 0:
            raise AssertionError(f"content status {match.group('s')}: {line}")
        links = tuple(
            (int(start), int(end), bytes.fromhex(target))
            for start, end, target in re.findall(
                r"L=\s*(-?\d+)\s+(-?\d+)\s*([0-9a-f]*)", match.group("links") or ""
            )
        )
        block = Block(
            int(match.group("k")),
            int(match.group("v")),
            rows,
            inside,
            containers,
            bytes.fromhex(match.group("t")),
            tuple(bytes.fromhex(match.group("m"))),
            bytes.fromhex(match.group("f")),
            links,
        )
        # A block's content says the kind its structure did, but that a
        # paragraph may turn out to be a figure.
        assert kind == block.kind or (kind == PARAGRAPH and block.kind == FIGURE), line
        assert level == block.level, line
        result.blocks.append(block)
    return result


def read_documents(
    documents: list[bytes], *, budget: int = 0, max_steps: int = 50_000_000_000
) -> list[Read]:
    """Open each document in turn in one guest session and read it."""

    data = b"".join(documents)
    assert len(data) <= FILE_BYTES

    def setup(system) -> None:
        if data:
            system._raw_mem_write_span(_file_address(), data)

    lines = []
    offset = 0
    for document in documents:
        lines.append(f"MKT-FILE {offset} + {len(document)} {budget} MKT-DUMP")
        offset += len(document)
    lines.append('DEPTH ." @D:" . CR')
    output = program_output(SNAPSHOT.run(lines, max_steps, setup=setup), lines)
    assert "@D:0 " in output, output[-2000:]
    assert "not found" not in output and "underflow" not in output, output[-2000:]
    reads = [_parse(part) for part in output.split("@@DOC")[1:]]
    assert len(reads) == len(documents), output[-2000:]
    return reads


def read_document(markdown: bytes, *, budget: int = 0) -> Read:
    return read_documents([markdown], budget=budget)[0]


# ---------------------------------------------------------------------------
# The same document from markdown-it-py
# ---------------------------------------------------------------------------

def _markdown_it():
    from markdown_it import MarkdownIt
    import markdown_it.rules_block.list as list_rule

    # A list token does not say whether its list is tight; markdown-it marks
    # a tight list's paragraphs instead.  Record it on the list token.
    if not getattr(list_rule.markTightParagraphs, "_records_tight", False):
        mark = list_rule.markTightParagraphs

        def recording(state, index):
            state.tokens[index].meta["tight"] = True
            mark(state, index)

        recording._records_tight = True
        list_rule.markTightParagraphs = recording
    md = MarkdownIt("commonmark").enable("table")

    # markdown-it 2.2.0 caches where backtick runs lie, and the cache it
    # fills while scanning a link's text loses code spans the reference
    # parser finds.  Each run is scanned afresh instead.
    from markdown_it.rules_inline.backticks import backtick

    def backtick_afresh(state, silent):
        state.backticks = {}
        state.backticksScanned = False
        return backtick(state, silent)

    md.inline.ruler.at("backticks", backtick_afresh)
    return md


_MD = None


def markdown_it():
    global _MD
    if _MD is None:
        _MD = _markdown_it()
    return _MD


class _Node:
    def __init__(self, role, parent=None, **data):
        self.kind = role
        self.parent = parent
        self.children = []
        self.data = data
        if parent is not None:
            parent.children.append(self)


def _digits(n: int) -> int:
    return len(str(n))


_SPACE = " \t\n\v\f\r"


class _Text:
    """Text as a document shows it: whitespace collapsed, controls replaced."""

    def __init__(self) -> None:
        self.out = bytearray()
        self.meanings: list[int] = []
        self.link_of: list[int] = []
        self.pending = None

    def _bytes(self, data: bytes, meaning: int, link: int) -> None:
        self.out += data
        self.meanings += [meaning] * len(data)
        self.link_of += [link] * len(data)

    def char(self, character: str, meaning: int, link: int) -> None:
        if self.pending is not None:
            self._bytes(b" ", *self.pending)
            self.pending = None
        self._bytes(character.encode("utf-8"), meaning, link)

    def space(self, meaning: int, link: int) -> None:
        if self.pending is not None or not self.out or self.out[-1] == 10:
            return
        self.pending = (meaning, link)

    def hard_break(self) -> None:
        self.pending = None
        self._bytes(b"\n", PLAIN, 0)

    def text(self, content: str, meaning: int, link: int, keep: bool) -> None:
        for character in content:
            code = ord(character)
            if character in _SPACE:
                if keep:
                    self.char(" ", meaning, link)
                else:
                    self.space(meaning, link)
            elif code < 32 or code == 127:
                self.char("�", meaning, link)
            else:
                self.char(character, meaning, link)


def _ranges(text: _Text, hrefs: dict[int, str]) -> tuple:
    links = []
    start = None
    for index, link in enumerate(text.link_of + [0]):
        previous = text.link_of[index - 1] if index else 0
        if link != previous:
            if previous:
                links.append((start, index, hrefs[previous].encode("utf-8")))
            if link:
                start = index
    return tuple(links)


def _meaning(link: int, code: bool, strong: int, em: int) -> int:
    if link:
        return LINK
    if code:
        return CODE_MEANING
    if strong:
        return STRONG
    if em:
        return EMPHASIS
    return PLAIN


def _markdown_it_inline(children, figure: bool) -> tuple[bytes, tuple, tuple]:
    """markdown-it's inline tokens as a document shows them."""

    text = _Text()
    hrefs: dict[int, str] = {}
    counter = [0]

    def walk(tokens, em: int, strong: int, link: int) -> None:
        # The outermost link or picture names every character in it.
        outer = []
        for token in tokens:
            kind = token.type
            if kind == "em_open":
                em += 1
            elif kind == "em_close":
                em -= 1
            elif kind == "strong_open":
                strong += 1
            elif kind == "strong_close":
                strong -= 1
            elif kind == "link_open":
                outer.append(link)
                if link == 0:
                    counter[0] += 1
                    link = counter[0]
                    hrefs[link] = token.attrs["href"]
            elif kind == "link_close":
                link = outer.pop()
            elif kind == "image":
                inner = link
                if inner == 0:
                    counter[0] += 1
                    inner = counter[0]
                    hrefs[inner] = token.attrs["src"]
                walk(token.children or [], em, strong, inner)
            else:
                shown = 0 if figure else link
                meaning = _meaning(shown, kind == "code_inline", strong, em)
                if kind in ("text", "html_inline"):
                    text.text(token.content, meaning, shown, False)
                elif kind == "code_inline":
                    text.text(token.content, meaning, shown, True)
                elif kind == "softbreak":
                    text.space(meaning, shown)
                elif kind == "hardbreak":
                    text.hard_break()
                else:
                    raise AssertionError(f"unexpected inline token {kind}")

    walk(children, 0, 0, 0)
    return bytes(text.out), tuple(text.meanings), _ranges(text, hrefs)


def _reference_inline(children, figure: bool) -> tuple[bytes, tuple, tuple]:
    """commonmark.js's inline nodes as a document shows them."""

    text = _Text()
    hrefs: dict[int, str] = {}
    counter = [0]

    def walk(nodes, em: int, strong: int, link: int) -> None:
        for node in nodes:
            kind = node["t"]
            if kind == "emph":
                walk(node.get("c", []), em + 1, strong, link)
            elif kind == "strong":
                walk(node.get("c", []), em, strong + 1, link)
            elif kind in ("link", "image"):
                inner = link
                if inner == 0:
                    counter[0] += 1
                    inner = counter[0]
                    hrefs[inner] = node["d"]
                walk(node.get("c", []), em, strong, inner)
            else:
                shown = 0 if figure else link
                meaning = _meaning(shown, kind == "code", strong, em)
                if kind in ("text", "html_inline"):
                    text.text(node["l"], meaning, shown, False)
                elif kind == "code":
                    text.text(node["l"], meaning, shown, True)
                elif kind == "softbreak":
                    text.space(meaning, shown)
                elif kind == "linebreak":
                    text.hard_break()
                else:
                    raise AssertionError(f"unexpected inline node {kind}")

    walk(children, 0, 0, 0)
    return bytes(text.out), tuple(text.meanings), _ranges(text, hrefs)


def _code_text(content: str) -> bytes:
    lines = []
    for line in content.split("\n"):
        out = []
        column = 0
        for character in line:
            if character == "\t":
                width = 4 - column % 4
                out.append(" " * width)
                column += width
            elif ord(character) < 32 or ord(character) == 127:
                out.append("�")
                column += 1
            else:
                out.append(character)
                column += 1
        lines.append("".join(out))
    return "\n".join(lines).encode("utf-8")


def _blocks(root: _Node) -> list[Block]:
    """A block tree's blocks, with the rows, containers and text a document
    gives them.  A leaf carries the text it shows as ``shown``, a function
    of whether it is a figure."""

    blocks: list[Block] = []
    previous_chain: list[_Node] = []
    started: set[int] = set()

    def chain(node: _Node) -> list[_Node]:
        nodes = []
        while node is not None:
            nodes.append(node)
            node = node.parent
        return nodes

    def emit(leaf: _Node, kind: int, level: int, text=b"", meanings=(), figure=b"", links=()):
        nonlocal previous_chain
        nodes = chain(leaf)
        rows = inside = 0
        if previous_chain:
            common = next(n for n in nodes if any(n is p for p in previous_chain))
            gap_node = common.parent if common.kind == "item" else common
            rows = 0 if gap_node.kind == "list" and gap_node.data["tight"] else 1
            if rows:
                inside = sum(1 for n in chain(common) if n.kind in ("quote", "item"))
        containers = []
        for n in reversed(nodes):
            if n.kind == "quote":
                containers.append(Container(QUOTE, 2, 0, False))
            elif n.kind == "item":
                parent = n.parent
                if parent.data["ordered"]:
                    last = parent.data["start"] + len(parent.children) - 1
                    number = parent.data["start"] + parent.children.index(n)
                    container = Container(NUMBERED, _digits(last) + 2, number, id(n) not in started)
                else:
                    container = Container(BULLET, 2, 0, id(n) not in started)
                started.add(id(n))
                containers.append(container)
        blocks.append(Block(kind, level, rows, inside, tuple(containers), text, meanings,
                            figure, links))
        previous_chain = nodes

    def visit(n: _Node) -> None:
        if n.kind == "leaf":
            kind = n.data["kind"]
            if kind in (PARAGRAPH, HEADING):
                picture = n.data["picture"] if kind == PARAGRAPH else None
                if picture is not None:
                    text, meanings, _links = n.data["shown"](True)
                    emit(n, FIGURE, 0, text, meanings, picture.encode("utf-8"))
                else:
                    text, meanings, links = n.data["shown"](False)
                    emit(n, kind, n.data["level"], text, meanings, b"", links)
            elif kind == CODE:
                text = _code_text(n.data["code"])
                emit(n, CODE, 0, text, (PLAIN,) * len(text))
            else:
                emit(n, RULE, 0)
            return
        if n.kind == "item" and not n.children:
            emit(n, PARAGRAPH, 0)
            return
        for child in n.children:
            visit(child)

    visit(root)
    return blocks


def expected_document(source: str) -> list[Block]:
    """The blocks markdown-it-py reads, shown by a document's rules."""

    md = markdown_it()
    tokens = md.parse(source)
    source_lines = source.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    root = _Node("doc")
    node = root
    index = 0

    def prose(kind: int, level: int, inline) -> None:
        children = inline.children or []
        picture = None
        if len(children) == 1 and children[0].type == "image":
            picture = children[0].attrs["src"]
            shown = lambda figure, c=children: (
                _markdown_it_inline(c[0].children or [], True) if figure
                else _markdown_it_inline(c, False)
            )
        else:
            shown = lambda figure, c=children: _markdown_it_inline(c, False)
        _Node("leaf", node, kind=kind, level=level, picture=picture, shown=shown)

    while index < len(tokens):
        token = tokens[index]
        kind = token.type
        if kind == "blockquote_open":
            node = _Node("quote", node)
        elif kind in ("blockquote_close", "bullet_list_close", "ordered_list_close",
                      "list_item_close"):
            node = node.parent
        elif kind in ("bullet_list_open", "ordered_list_open"):
            node = _Node(
                "list", node,
                ordered=kind == "ordered_list_open",
                start=int(token.attrs.get("start", 1)),
                tight=bool(token.meta.get("tight")),
            )
        elif kind == "list_item_open":
            node = _Node("item", node)
        elif kind == "paragraph_open":
            prose(PARAGRAPH, 0, tokens[index + 1])
            index += 2
        elif kind == "heading_open":
            prose(HEADING, int(token.tag[1]), tokens[index + 1])
            index += 2
        elif kind in ("code_block", "fence"):
            content = token.content[:-1] if token.content.endswith("\n") else token.content
            _Node("leaf", node, kind=CODE, level=0, code=content)
        elif kind == "html_block":
            content = re.sub(r"(\n *)+$", "", token.content)
            _Node("leaf", node, kind=CODE, level=0, code=content)
        elif kind == "hr":
            _Node("leaf", node, kind=RULE, level=0)
        elif kind == "table_open":
            first, end = token.map
            lines = [line.lstrip(" \t") for line in source_lines[first:end]]
            _Node("leaf", node, kind=CODE, level=0, code="\n".join(lines))
            while tokens[index].type != "table_close":
                index += 1
        else:
            raise AssertionError(f"unexpected block token {kind}")
        index += 1
    return _blocks(root)


# The CommonMark reference parser, commonmark.js, run by node: each source's
# tree as JSON, with only what a document shows.
_REFERENCE_DUMP = r"""
const cm = require(process.argv[1]);
function dump(n) {
  const o = {t: n.type};
  if (n.literal !== null && n.literal !== undefined) o.l = n.literal;
  if (n.type === "link" || n.type === "image") o.d = n.destination;
  if (n.type === "heading") o.level = n.level;
  if (n.type === "list") {
    o.ordered = n.listType === "ordered"; o.start = n.listStart; o.tight = n.listTight;
  }
  const kids = [];
  for (let c = n.firstChild; c; c = c.next) kids.push(dump(c));
  if (kids.length) o.c = kids;
  return o;
}
let input = "";
process.stdin.on("data", d => input += d).on("end", () => {
  const parser = new cm.Parser();
  process.stdout.write(JSON.stringify(JSON.parse(input).map(s => dump(parser.parse(s)))));
});
"""


def reference_trees(sources: list[str], commonmark_js: str) -> list[dict]:
    """commonmark.js's trees for SOURCES; COMMONMARK_JS is its package."""

    import json
    import subprocess

    result = subprocess.run(
        ["node", "-e", _REFERENCE_DUMP, commonmark_js],
        input=json.dumps(sources).encode("utf-8"),
        capture_output=True,
        check=True,
    )
    return json.loads(result.stdout)


def reference_document(tree: dict) -> list[Block]:
    """The blocks of a commonmark.js tree, shown by a document's rules.

    commonmark.js 0.30 keeps a paragraph left empty when a setext underline
    took its link reference definitions; such a paragraph shows nothing, as
    markdown-it, which drops it, and the reader agree."""

    root = _Node("doc")

    def build(node: dict, parent: _Node) -> None:
        kind = node["t"]
        children = node.get("c", [])
        if kind == "block_quote":
            quote = _Node("quote", parent)
            for child in children:
                build(child, quote)
        elif kind == "list":
            lst = _Node("list", parent, ordered=node["ordered"],
                        start=node["start"] if node["ordered"] else 1, tight=node["tight"])
            for child in children:
                build(child, lst)
        elif kind == "item":
            item = _Node("item", parent)
            for child in children:
                build(child, item)
        elif kind in ("paragraph", "heading"):
            if kind == "paragraph" and not children:
                return
            level = node.get("level", 0)
            picture = None
            if kind == "paragraph" and len(children) == 1 and children[0]["t"] == "image":
                picture = children[0]["d"]
            shown = lambda figure, c=children: (
                _reference_inline(c[0].get("c", []), True) if figure
                else _reference_inline(c, False)
            )
            _Node("leaf", parent, kind=PARAGRAPH if kind == "paragraph" else HEADING,
                  level=level, picture=picture, shown=shown)
        elif kind == "code_block":
            literal = node.get("l", "")
            _Node("leaf", parent, kind=CODE, level=0,
                  code=literal[:-1] if literal.endswith("\n") else literal)
        elif kind == "html_block":
            _Node("leaf", parent, kind=CODE, level=0, code=node.get("l", ""))
        elif kind == "thematic_break":
            _Node("leaf", parent, kind=RULE, level=0)
        else:
            raise AssertionError(f"unexpected block node {kind}")

    for child in tree.get("c", []):
        build(child, root)
    return _blocks(root)


def normalized(read_blocks: list[Block], normalize) -> list[Block]:
    """The guest's blocks with link targets written as NORMALIZE writes them."""

    out = []
    for block in read_blocks:
        links = tuple(
            (start, end, normalize(target.decode("utf-8")).encode("utf-8"))
            for start, end, target in block.links
        )
        figure = (
            normalize(block.figure.decode("utf-8")).encode("utf-8")
            if block.kind == FIGURE else block.figure
        )
        out.append(Block(block.kind, block.level, block.rows_before, block.inside,
                         block.containers, block.text, block.meanings, figure, links))
    return out
