"""Highlighted files and a Markdown link, for the Pad journeys.

Pad highlights Markdown and Forth by file name.  NOTES_MD is a Markdown
sample with a heading, a link to the Forth sample, and strong text.  The
standalone Pad smoke checks their CELL looks and follows the link with Ctrl
and a click; the rich journeys check the same text areas' style runs and
follow the link with FOLLOW.

Meanings and their numbers are the shared list of SEMANTIC-CONTENT-1 and
Akashic's text/text-style.f.  The CELL looks are Pad's default palette
(tui/style-palette.f), in xterm-256 colours on the SGR attribute bits.
"""

from __future__ import annotations

NOTES_NAME = "notes.md"
NOTES_PATH = "/notes.md"
NOTES_HEADING = "# Notes"
NOTES_LINK = "[the example](example.f)"
NOTES_LINK_WORD = "example"           # clicked inside the link's text
NOTES_STRONG = "**try it**"
NOTES_LINE = f"Read {NOTES_LINK} and {NOTES_STRONG}."
NOTES_MD = f"{NOTES_HEADING}\n{NOTES_LINE}\n".encode()

# The link's target: the Forth sample every image carries.
EXAMPLE_NAME = "example.f"
EXAMPLE_PATH = "/example.f"
EXAMPLE_LINE = ": SQUARE DUP * ;"

KEYWORD, COMMENT, STRING, NUMBER, HEADING = 1, 2, 3, 4, 5
EMPHASIS, STRONG, CODE, LINK, ERROR = 6, 7, 8, 9, 10

BOLD, ITALIC, UNDERLINE = 1, 4, 8
# Meaning: (xterm-256 foreground, SGR attributes) in the default palette.
CELL_LOOKS = {
    KEYWORD: (81, BOLD),
    COMMENT: (245, ITALIC),
    STRING: (186, 0),
    NUMBER: (141, 0),
    HEADING: (215, BOLD),
    EMPHASIS: (223, ITALIC),
    STRONG: (231, BOLD),
    CODE: (114, 0),
    LINK: (75, UNDERLINE),
    ERROR: (203, UNDERLINE),
}
# Pad's editor text is xterm-256 colour 253 (its theme's editor-fg).
PAD_EDITOR_FG = 253


def xterm_rgb(index: int) -> tuple[int, int, int]:
    """The RGB colour of an xterm-256 index from 16 up."""

    if index >= 232:
        level = 8 + (index - 232) * 10
        return (level, level, level)
    index -= 16
    levels = (0, 95, 135, 175, 215, 255)
    return (levels[index // 36], levels[index // 6 % 6], levels[index % 6])


def runs(text: str, pieces: list[tuple[str, int]]) -> list[tuple[int, int, int]]:
    """The style runs (start, length, meaning) in scalars that mark each
    piece of TEXT, searching on from the previous one."""

    result = []
    cursor = 0
    for piece, meaning in pieces:
        start = text.index(piece, cursor)
        result.append((start, len(piece), meaning))
        cursor = start + len(piece)
    return result


NOTES_HEADING_RUNS = runs(NOTES_HEADING, [(NOTES_HEADING, HEADING)])
NOTES_LINE_RUNS = runs(NOTES_LINE, [(NOTES_LINK, LINK), (NOTES_STRONG, STRONG)])
EXAMPLE_LINE_RUNS = runs(EXAMPLE_LINE, [(":", KEYWORD), (";", KEYWORD)])
