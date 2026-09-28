#!/usr/bin/env python3
"""Syntax highlighting by meaning (text/syntax.f, text/text-style.f).

The scanners fill a style map with one meaning per byte of a line, and
TSTY-RUNS turns a map into runs of Unicode scalars, the form semantic text
carries (SEMANTIC-CONTENT-1, style runs).  Each case prints the map, or the
runs, and compares them with the expected meanings.
"""

from __future__ import annotations

import re

from test_widget_pointer import _run_forth

ROOTS = ("text/syntax.f",)

# Meanings, as text-style.f and SEMANTIC-CONTENT-1 number them.
PLAIN, KEYWORD, COMMENT, STRING, NUMBER, HEADING = 0, 1, 2, 3, 4, 5
EMPHASIS, STRONG, CODE, LINK, ERROR = 6, 7, 8, 9, 10

_WORDS = [
    "CREATE _MAP 512 ALLOT",
    ": _SHOWMAP  ( u -- )  18 EMIT 0 ?DO _MAP I + C@ . LOOP 19 EMIT ;",
    ": _RUN.  ( start length meaning -- ok? )  18 EMIT ROT . SWAP . . 19 EMIT -1 ;",
    ": _N  ( n -- )  2 EMIT . 3 EMIT ;",
]


def _bytes_word(name: str, text: str) -> list[str]:
    data = text.encode("utf-8")
    body = " ".join(f"{byte} C," for byte in data) if data else ""
    return [f"CREATE {name} {body}", f": {name}$  {name} {len(data)} ;"]


def _run(lines: list[str]) -> tuple[list[list[int]], list[int]]:
    output = _run_forth(_WORDS + lines, roots=ROOTS).decode("utf-8", errors="replace")
    assert "not found" not in output and "underflow" not in output, output[-2000:]
    groups = [
        [int(token) for token in body.split()]
        for body in re.findall("\x12(.*?)\x13", output, re.S)
    ]
    numbers = [int(value) for value in re.findall(r"\x02\s*(-?\d+)\s*\x03", output)]
    return groups, numbers


def _scan(scanner: str, *texts: str) -> list[list[int]]:
    lines: list[str] = []
    for index, text in enumerate(texts):
        name = f"_T{index}"
        lines += _bytes_word(name, text)
        lines.append(
            f"{name}$ _MAP {scanner} {len(text.encode('utf-8'))} _SHOWMAP"
        )
    groups, _numbers = _run(lines)
    assert len(groups) == len(texts)
    return groups


def _map(text: str, spans: list[tuple[str, int]]) -> list[int]:
    """The expected map: each (substring, meaning) marks the first
    occurrence of that substring, searching on from the previous one."""

    data = text.encode("utf-8")
    result = [PLAIN] * len(data)
    cursor = 0
    for piece, meaning in spans:
        encoded = piece.encode("utf-8")
        start = data.index(encoded, cursor)
        for index in range(start, start + len(encoded)):
            result[index] = meaning
        cursor = start + len(encoded)
    return result


def test_forth_scanner_marks_keywords_comments_strings_and_numbers() -> None:
    texts = [
        ": SQUARE ( n -- n*n ) DUP * ; \\ square it",
        'S" hello world" TYPE ." hi" ABORT" no"',
        "42 $FF 0x1F -7 %101 12ab 0x",
        "BEGIN dup WHILE 1- REPEAT if",
        "\\ a whole-line comment",
        "(no-space) \\no-space ( open",
    ]
    maps = _scan("SYN-SCAN-FORTH", *texts)
    assert maps[0] == _map(texts[0], [
        (":", KEYWORD), ("( n -- n*n )", COMMENT), (";", KEYWORD),
        ("\\ square it", COMMENT),
    ])
    assert maps[1] == _map(texts[1], [
        ('S"', STRING), ('hello world"', STRING),
        ('."', STRING), ('hi"', STRING),
        ('ABORT"', STRING), ('no"', STRING),
    ])
    assert maps[2] == _map(texts[2], [
        ("42", NUMBER), ("$FF", NUMBER), ("0x1F", NUMBER), ("-7", NUMBER),
        ("%101", NUMBER),
    ])
    assert maps[3] == _map(texts[3], [
        ("BEGIN", KEYWORD), ("WHILE", KEYWORD), ("REPEAT", KEYWORD),
        ("if", KEYWORD),
    ])
    assert maps[4] == [COMMENT] * len(texts[4])
    # A backslash or paren glued to a word is an ordinary word; an open
    # paren at the end runs to the line's end.
    assert maps[5] == _map(texts[5], [("( open", COMMENT)])


def test_markdown_scanner_marks_headings_code_emphasis_and_links() -> None:
    texts = [
        "## Notes for today",
        "Use `SYN-SCAN` with **care** and *thought*, see [Plan](plan.md).",
        "snake_case_name and _whole_ word, but * not emphasis *",
        "- [ ] tea [broken](missing and ** nothing",
        "#hashtag is not a heading",
        "é **ünïcode** [文](a.md)",
    ]
    maps = _scan("SYN-SCAN-MD", *texts)
    assert maps[0] == [HEADING] * len(texts[0])
    assert maps[1] == _map(texts[1], [
        ("`SYN-SCAN`", CODE), ("**care**", STRONG), ("*thought*", EMPHASIS),
        ("[Plan](plan.md)", LINK),
    ])
    assert maps[2] == _map(texts[2], [("_whole_", EMPHASIS)])
    assert maps[3] == [PLAIN] * len(texts[3].encode())
    assert maps[4] == [PLAIN] * len(texts[4])
    assert maps[5] == _map(texts[5], [("**ünïcode**", STRONG), ("[文](a.md)", LINK)])


def test_url_scanner_marks_web_links_in_prose() -> None:
    texts = [
        "See https://example.org/a?b=1 for more.",
        "(HTTP://Example.org/x), and <https://ü.example/é>!",
        "xhttps://no.example nohttp://no.example https:// http://.",
        "two: http://a.example http://b.example/path/",
        "https://end.example",
    ]
    maps = _scan("SYN-SCAN-URLS", *texts)
    assert maps[0] == _map(texts[0], [("https://example.org/a?b=1", LINK)])
    assert maps[1] == _map(texts[1], [
        ("HTTP://Example.org/x", LINK), ("https://ü.example/é", LINK),
    ])
    # A scheme glued to a word, or with nothing after it, is not a link.
    assert maps[2] == [PLAIN] * len(texts[2])
    assert maps[3] == _map(texts[3], [
        ("http://a.example", LINK), ("http://b.example/path/", LINK),
    ])
    assert maps[4] == [LINK] * len(texts[4])


def test_runs_count_scalars_and_merge_neighbours() -> None:
    text = "é中 ok"             # 2 + 3 + 1 + 2 bytes; 5 scalars
    data = text.encode("utf-8")
    meanings = [STRONG, 99, STRONG, 0, 0, 0, LINK, LINK]
    assert len(meanings) == len(data)
    lines = _bytes_word("_R", text) + [
        " ".join(f"{m} _MAP {i} + C!" for i, m in enumerate(meanings)),
        "_R$ _MAP ' _RUN. TSTY-RUNS _N",
    ]
    groups, numbers = _run(lines)
    # The continuation byte's 99 is never read: é and 中 are one STRONG run.
    assert groups == [[0, 2, STRONG], [3, 2, LINK]]
    assert numbers == [-1]

    # An unknown meaning at a scalar's first byte is plain.
    lines = _bytes_word("_Q", "abc") + [
        "11 _MAP C!  3 _MAP 1+ C!  3 _MAP 2 + C!",
        "_Q$ _MAP ' _RUN. TSTY-RUNS _N",
    ]
    groups, numbers = _run(lines)
    assert groups == [[1, 2, STRING]]
    assert numbers == [-1]


def test_markdown_link_target_and_scanner_by_file_name() -> None:
    text = 'See [the plan](docs/plan.md "Title") or `[x](y)` then [b](c.md).'
    data = text.encode()
    inside = data.index(b"the plan")
    code = data.index(b"[x]")
    second = data.index(b"[b]") + 1
    lines = _bytes_word("_L", text) + [
        f"_L$ {inside} SYN-MD-LINK-AT _N 18 EMIT TYPE 19 EMIT",
        f"_L$ {code} SYN-MD-LINK-AT _N 2DROP",
        f"_L$ {second} SYN-MD-LINK-AT _N 18 EMIT TYPE 19 EMIT",
        "_L$ 0 SYN-MD-LINK-AT _N 2DROP",
        'S" words.f" SYN-FOR-FILE SYN-LANG-FORTH = _N',
        'S" NOTES.MD" SYN-FOR-FILE SYN-LANG-MD = _N',
        'S" large.txt" SYN-FOR-FILE _N',
    ]
    output = _run_forth(_WORDS + lines, roots=ROOTS).decode("utf-8", errors="replace")
    assert "not found" not in output, output[-2000:]
    targets = re.findall("\x12(.*?)\x13", output, re.S)
    numbers = [int(value) for value in re.findall(r"\x02\s*(-?\d+)\s*\x03", output)]
    assert targets == ["docs/plan.md", "c.md"]
    assert numbers == [-1, 0, -1, 0, -1, -1, 0]
