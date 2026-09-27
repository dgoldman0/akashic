#!/usr/bin/env python3
"""Unicode tables, grapheme clusters, widths, and UTF-8 decoding in Forth.

These check akashic/text/unicode-props.f, grapheme.f, cell-width.f, and the
UTF-8 decoder against the shared text contract (APT-1-TEXT.md) and Unicode's
own GraphemeBreakTest.txt, using the pinned Unicode 15.1.0 data.
"""

from __future__ import annotations

import re

import pytest

import generate_unicode_text_tables as generator
import unicode_text_reference as reference
from forth_snapshot import ForthSnapshot, program_output


try:
    UCD = reference.ucd()
except generator.UcdError as exc:  # pragma: no cover - depends on the host
    pytest.skip(f"pinned Unicode 15.1.0 data unavailable: {exc}", allow_module_level=True)

SNAPSHOT = ForthSnapshot(("text/cell-width.f",))


def _run(lines: list[str]) -> str:
    return program_output(SNAPSHOT.run(lines), lines)

_PRELUDE = [
    "VARIABLE _UT-FAILS  VARIABLE _UT-CHECKS",
    "0 _UT-FAILS ! 0 _UT-CHECKS !",
    ': _UT-ASSERT ( f -- ) 1 _UT-CHECKS +! 0= IF 1 _UT-FAILS +! ." UT-FAIL " _UT-CHECKS @ . CR THEN ;',
    ': _UT-SUMMARY ." UT-SUMMARY " _UT-CHECKS @ . _UT-FAILS @ . CR ;',
    "CREATE _UT-BUF 4096 ALLOT  VARIABLE _UT-LEN",
    ": _UT-CLEAR 0 _UT-LEN ! ;",
    ": _UT-B ( byte -- ) _UT-BUF _UT-LEN @ + C! 1 _UT-LEN +! ;",
    ": _UT-CP ( cp -- ) _UT-BUF _UT-LEN @ + UTF8-ENCODE _UT-BUF - _UT-LEN ! ;",
    ": _UT-TEXT ( -- a u ) _UT-BUF _UT-LEN @ ;",
    "CREATE _UT-CURSOR GR-CURSOR-SIZE ALLOT",
]


def _summary(output: str) -> tuple[int, int]:
    match = re.search(r"UT-SUMMARY (\d+) (\d+)", output)
    assert match, output[-2000:]
    return int(match[1]), int(match[2])


def _encode_lines(text: bytes) -> list[str]:
    lines = ["_UT-CLEAR"]
    for start in range(0, len(text), 12):
        lines.append(" ".join(f"{byte} _UT-B" for byte in text[start:start + 12]))
    return lines


def test_generated_tables_are_current() -> None:
    assert generator.main(["--check"]) == 0


def test_property_lookup_matches_every_run_boundary() -> None:
    values, runs = generator.property_ranges(UCD)
    probes: list[int] = []
    for index, (first, _value) in enumerate(runs):
        last = runs[index + 1][0] - 1 if index + 1 < len(runs) else generator.MAX_SCALAR
        probes.extend({first, last, (first + last) // 2})
    lines = _PRELUDE + [": _UT-PROP ( cp expected -- ) SWAP UP-PROPS = _UT-ASSERT ;"]
    lines += [f"{cp} {UCD.packed(cp)} _UT-PROP" for cp in probes]
    # Out-of-range and negative inputs read as U+FFFD, never as table garbage.
    lines += [f"{0x110000} {UCD.packed(0xFFFD)} _UT-PROP", f"-5 {UCD.packed(0xFFFD)} _UT-PROP"]
    lines.append("_UT-SUMMARY")
    output = _run(lines)
    checks, fails = _summary(output)
    assert checks == len(probes) + 2
    assert fails == 0, output[-3000:]


def test_mirror_bracket_and_arabic_form_lookups() -> None:
    lines = _PRELUDE + [
        ": _UT-MIRROR ( cp expected -- ) SWAP UP-MIRROR = _UT-ASSERT ;",
        ": _UT-BRACKET ( cp pair type -- ) ROT UP-BRACKET ROT = -ROT = AND _UT-ASSERT ;",
        ": _UT-FORM ( cp form expected -- ) -ROT UP-ARABIC-FORM = _UT-ASSERT ;",
    ]
    for cp, glyph in UCD.mirror.items():
        lines.append(f"{cp} {glyph} _UT-MIRROR")
    for cp in (0x41, 0x5D0, 0x627, 0x1F600):
        lines.append(f"{cp} {cp} _UT-MIRROR")
    for cp, (pair, kind) in UCD.brackets.items():
        lines.append(f"{cp} {generator.canonical_bracket(pair)} {1 if kind == 'o' else 2} _UT-BRACKET")
    lines.append("65 0 0 _UT-BRACKET")
    for base, forms in UCD.arabic_forms.items():
        for form, scalar in enumerate(forms):
            lines.append(f"{base} {form} {scalar} _UT-FORM")
    lines += ["65 0 0 _UT-FORM", "_UT-SUMMARY"]
    output = _run(lines)
    _checks, fails = _summary(output)
    assert fails == 0, output[-3000:]


def test_segmenter_passes_every_grapheme_break_test_case() -> None:
    cases = []
    for line in reference.ucd_path("auxiliary/GraphemeBreakTest.txt").read_text(
        encoding="utf-8"
    ).splitlines():
        body = line.split("#", 1)[0].strip()
        if not body:
            continue
        scalars, breaks = [], []
        for token in body.split():
            if token == "\u00f7":
                breaks.append(len(scalars))
            elif token != "\u00d7":
                scalars.append(int(token, 16))
        cases.append((scalars, [index in breaks for index in range(len(scalars))]))
    lines = _PRELUDE + [
        "CREATE _GB-STATE GR-STATE-SIZE ALLOT",
        ": _GB-BEGIN _GB-STATE GR-RESET .\" GB:\" ;",
        ": _GB ( cp -- ) UP-PROPS _GB-STATE GR-BREAK? IF .\" /\" ELSE .\" x\" THEN ;",
        ": _GB-END CR ;",
    ]
    for scalars, _breaks in cases:
        lines.append("_GB-BEGIN " + " ".join(f"{cp} _GB" for cp in scalars) + " _GB-END")
    output = _run(lines)
    got = re.findall(r"GB:([/x]*)", output)
    assert len(got) == len(cases)
    failures = [
        (scalars, marks)
        for (scalars, breaks), marks in zip(cases, got)
        if marks != "".join("/" if flag else "x" for flag in breaks)
    ]
    assert failures == [], failures[:5]


_SAMPLES = [
    "plain ASCII",
    "\u4e2d\u6587\u5b57",
    "e\u0301 and \u00e9",
    "\U0001F1EF\U0001F1F5\U0001F1FA",
    "\u2764\ufe0f \u2764",
    "\U0001F44D\U0001F3FD \u261d\U0001F3FD",
    "\U0001F468\u200d\U0001F469\u200d\U0001F467!",
    "#\ufe0f\u20e3",
    "\u0301x",
    "a\u200bb\u200fc\u202ed",
    "tab\there",
    "\u1100\u1161\u11a8\uac00",
    "\uff8a\uff21",
    "\u3099",
    "\u05e9\u05dc\u05d5\u05dd \u05e2\u05d5\u05dc\u05dd",
    "\u0645\u0631\u062d\u0628\u0627 \u0628\u0627\u0644\u0639\u0627\u0644\u0645",
    "\u0915\u094d\u0937",
    "\U0001F3F4\U000E0067\U000E0062\U000E0065\U000E006E\U000E0067\U000E007F",
    "\r\n",
]


def test_cursor_characters_and_widths_match_the_contract() -> None:
    lines = _PRELUDE + [
        ": _UT-CHARS ( -- ) _UT-TEXT 0 _UT-CURSOR GR-CURSOR-INIT .\" CH:\"",
        "  BEGIN _UT-CURSOR GR-NEXT WHILE",
        "    _UT-CURSOR GR-C-SCALARS . _UT-CURSOR GR-C-WIDTH . _UT-CURSOR GR-C-CP0 .",
        "  REPEAT .\" ;\" _UT-TEXT GR-SWIDTH . _UT-TEXT GR-COUNT . CR ;",
    ]
    for sample in _SAMPLES:
        lines += _encode_lines(sample.encode("utf-8")) + ["_UT-CHARS"]
    output = _run(lines)
    got = re.findall(r"CH:([^;]*);\s*(-?\d+)\s+(-?\d+)", output)
    assert len(got) == len(_SAMPLES), output[-2000:]
    for sample, (chars, width, count) in zip(_SAMPLES, got):
        clusters = reference.characters(sample)
        expected = []
        for cluster in clusters:
            expected += [len(cluster), reference.char_width(cluster), cluster[0]]
        assert [int(v) for v in chars.split()] == expected, sample
        assert int(width) == reference.string_width(sample), sample
        assert int(count) == len(clusters), sample


def test_boundaries_move_by_whole_characters() -> None:
    sample = "a\u0301\U0001F1EF\U0001F1F5x\U0001F468\u200d\U0001F469"
    data = sample.encode("utf-8")
    starts = [0]
    for cluster in reference.characters(sample):
        starts.append(starts[-1] + len("".join(map(chr, cluster)).encode("utf-8")))
    lines = _PRELUDE + _encode_lines(data) + [
        ": _UT-NB ( off -- ) _UT-TEXT ROT GR-NEXT-BOUNDARY . ;",
        ": _UT-PB ( off -- ) _UT-TEXT ROT GR-PREV-BOUNDARY . ;",
        '." NB:" ' + " ".join(f"{off} _UT-NB" for off in range(len(data) + 1)) + " CR",
        '." PB:" ' + " ".join(f"{off} _UT-PB" for off in range(len(data) + 1)) + " CR",
    ]
    output = _run(lines)
    nb = [int(v) for v in re.search(r"NB:([-\d ]*)", output)[1].split()]
    pb = [int(v) for v in re.search(r"PB:([-\d ]*)", output)[1].split()]
    assert nb == [min(s for s in starts if s > off) if off < len(data) else len(data)
                  for off in range(len(data) + 1)]
    assert pb == [max((s for s in starts if s < off), default=0) for off in range(len(data) + 1)]


_ILL_FORMED = [
    b"\x80",
    b"\xc0\x80",
    b"\xc1\xbf",
    b"\xe0\x80\x80",
    b"\xe0\xa0",
    b"\xe2\x82A",
    b"\xed\xa0\x80",
    b"\xf0\x80\x80\x80",
    b"\xf4\x90\x80\x80",
    b"\xf5\x80\x80\x80",
    b"\xf1\x80\x80",
    b"a\xffb\xfe",
    "ok \u00e9\u4e2d\U0001F600".encode("utf-8"),
]


def test_utf8_decoder_replaces_maximal_subparts() -> None:
    lines = _PRELUDE + [
        "CREATE _UT-DS UTF8-DECODE-STATE-SIZE ALLOT",
        ": _UT-DECODE ( -- ) .\" DEC:\" _UT-TEXT BEGIN DUP 0> WHILE",
        "  _UT-DS UTF8-DECODE-WITH ROT . REPEAT 2DROP CR ;",
    ]
    for data in _ILL_FORMED:
        lines += _encode_lines(data) + ["_UT-DECODE"]
    output = _run(lines)
    got = re.findall(r"DEC:([-\d ]*)", output)
    assert len(got) == len(_ILL_FORMED)
    for data, text in zip(_ILL_FORMED, got):
        expected = [ord(ch) for ch in data.decode("utf-8", errors="replace")]
        assert [int(v) for v in text.split()] == expected, data


def test_cursor_replaces_controls_and_keeps_tabs_on_request() -> None:
    sample = "a\tb\x01\u2028c"
    lines = _PRELUDE + _encode_lines(sample.encode("utf-8")) + [
        ": _UT-FLAGGED ( flags -- ) _UT-TEXT ROT _UT-CURSOR GR-CURSOR-INIT .\" FL:\"",
        "  BEGIN _UT-CURSOR GR-NEXT WHILE _UT-CURSOR GR-C-CP0 . REPEAT CR ;",
        "0 _UT-FLAGGED  GR-F-TAB _UT-FLAGGED",
    ]
    output = _run(lines)
    plain, tabs = [
        [int(v) for v in text.split()] for text in re.findall(r"FL:([-\d ]*)", output)
    ]
    assert plain == reference.display_scalars(sample)
    assert tabs == reference.display_scalars(sample, keep_tab=True)
    assert tabs[1] == 9 and plain[1] == 0xFFFD


def test_scalar_and_one_scalar_character_widths() -> None:
    probes = [0x41, 0x301, 0x4E00, 0x1160, 0x0A, 0x2028, 0x1F600, 0x1F1E6,
              0xFF01, 0x200B, 0x200D, 0xFE0F, 0xAD]
    lines = _PRELUDE + [
        ": _UT-W ( cp expected -- ) SWAP CW-WIDTH = _UT-ASSERT ;",
        ": _UT-CW ( cp expected -- ) SWAP CW-CHAR-WIDTH = _UT-ASSERT ;",
    ]
    for cp in probes:
        invalid = UCD.general_category[cp] in ("Cc", "Zl", "Zp")
        expected = 1 if invalid else UCD.scalar_width(cp)
        lines.append(f"{cp} {expected} _UT-W")
        character = 1 if invalid else reference.char_width([cp])
        lines.append(f"{cp} {character} _UT-CW")
    lines += ["_UT-SUMMARY"]
    output = _run(lines)
    _checks, fails = _summary(output)
    assert fails == 0, output[-2000:]


def _steps_per_scalar(text: str, word: str = "GR-SWIDTH", repeats: int = 10) -> float:
    """Guest steps one call of WORD takes on TEXT, divided by its scalars."""

    setup = _PRELUDE + _encode_lines(text.encode("utf-8")) + [
        f": _UT-LOOP-A {repeats} 0 DO _UT-TEXT 2DROP LOOP ;",
        f": _UT-LOOP-B {repeats} 0 DO _UT-TEXT {word} DROP LOOP ;",
    ]
    SNAPSHOT.run(setup + ["_UT-LOOP-A"])
    baseline = SNAPSHOT.last_steps
    SNAPSHOT.run(setup + ["_UT-LOOP-B"])
    return (SNAPSHOT.last_steps - baseline) / repeats / len(text)


def test_width_cost_keeps_a_cheap_path_for_plain_text() -> None:
    """APT-1-TEXT Section 11: printable ASCII needs no table lookup.

    These are ratchets on measured guest steps, not tight targets: printable
    ASCII costs one byte scan, and other Basic Multilingual Plane text pays
    for decoding, one table load, and the segmentation shortcut.
    """

    ascii_cost = _steps_per_scalar("x" * 200)
    bmp_cost = _steps_per_scalar("\u05d0\u4e2d\u00e9" * 40)
    print(f"GR-SWIDTH steps per scalar: ascii {ascii_cost:.0f}, BMP {bmp_cost:.0f}")
    assert ascii_cost < 250
    assert bmp_cost < 4000
