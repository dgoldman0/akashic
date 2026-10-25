"""Seconds-only structural lock: a widget's own words stay in its own module.

A canonical widget's fields, by offset, and every other word its module keeps
private (a name that starts with ``_``) are used only in that module.  The
shared header that ``widget.f`` lays out is filled and read by the modules
that implement widget kinds: the canonical widgets and the game widgets.
Everything else, UIDL and the applications included, goes through public
words: ``WDG-REGION``, ``WDG-INIT``, ``TXTA-GENUINE?`` and the like.
"""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "akashic"
WIDGET = "akashic/tui/widget.f"
WIDGETS = "akashic/tui/widgets/"
# Libraries that implement widget kinds, and so fill and read the header.
IMPLEMENTATIONS = ("akashic/tui/widgets/", "akashic/tui/game/")

_DEFINITION = re.compile(
    r"(?:^|\s)(?::|CONSTANT|2CONSTANT|VARIABLE|2VARIABLE|CREATE|DEFER|VALUE)"
    r"\s+(_\S+)",
    re.MULTILINE | re.IGNORECASE,
)
_LINE_COMMENT = re.compile(r"(?:^|\s)\\(?:\s.*)?$")
_STACK_COMMENT = re.compile(r"(?:^|\s)\(\s[^)]*\)")


def _code(text: str) -> str:
    """The source without its comments."""
    lines = []
    for line in text.splitlines():
        line = _LINE_COMMENT.sub("", line)
        lines.append(_STACK_COMMENT.sub(" ", line))
    return "\n".join(lines)


def _defined(text: str) -> set[str]:
    return {match.group(1).upper() for match in _DEFINITION.finditer(text)}


def _sources() -> dict[str, str]:
    return {
        path.relative_to(ROOT).as_posix(): path.read_text(encoding="utf-8")
        for path in sorted(SOURCES.rglob("*.f"))
    }


def _widget_modules(sources: dict[str, str]) -> list[str]:
    return [WIDGET] + [path for path in sources if path.startswith(WIDGETS)]


def _violations(sources: dict[str, str]) -> list[str]:
    owners: dict[str, str] = {}
    for module in _widget_modules(sources):
        for name in _defined(sources[module]):
            owners.setdefault(name, module)
    found = []
    for path, text in sources.items():
        own = _defined(text)
        implements = path.startswith(IMPLEMENTATIONS)
        for number, line in enumerate(_code(text).splitlines(), 1):
            for token in line.split():
                name = token.upper()
                owner = owners.get(name)
                if owner is None or owner == path or name in own:
                    continue
                if owner == WIDGET and implements:
                    continue
                found.append(f"{path}:{number}: {token} belongs to {owner}")
    return found


def test_no_module_uses_another_widgets_private_words() -> None:
    assert _violations(_sources()) == []


def test_the_check_finds_a_private_field_read_outside_its_widget() -> None:
    sources = _sources()
    probe = {
        WIDGET: sources[WIDGET],
        WIDGETS + "textarea.f": sources[WIDGETS + "textarea.f"],
        "akashic/tui/uidl-probe.f": (
            ": PROBE ( widget -- caret )  \\ _TXTA-O-SCROLL-Y in a comment\n"
            "    DUP _WDG-O-REGION + @ DROP _TXTA-O-CURSOR + @ ;\n"
        ),
        "akashic/tui/game/probe.f": ": GAME-PROBE  _WDG-O-REGION + @ ;\n",
    }
    assert _violations(probe) == [
        "akashic/tui/uidl-probe.f:2: _WDG-O-REGION belongs to akashic/tui/widget.f",
        "akashic/tui/uidl-probe.f:2: _TXTA-O-CURSOR belongs to "
        "akashic/tui/widgets/textarea.f",
    ]


def test_uidl_checks_mounted_widgets_through_their_own_words() -> None:
    source = (ROOT / "akashic" / "tui" / "uidl-tui.f").read_text(encoding="utf-8")
    code = _code(source)
    for word in (
        "TXTA-GENUINE?",
        "TGRID-GENUINE?",
        "TAB-GENUINE?",
        "LST-GENUINE?",
        "TREE-GENUINE?",
        "DGRAPH-GENUINE?",
        "FLD-GENUINE?",
        "PRM-GENUINE?",
        "MEDIA-GENUINE?",
    ):
        assert word in code
    for gone in ("_TXTA-", "_TGRID-", "_TAB-", "_MEDIA-", "_INP-", "_WDG-"):
        assert gone not in code
