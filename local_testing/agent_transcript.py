"""A long stored conversation, for the Agent alone on Desk.

Desk with only the Agent starts from this conversation, saved at boot
through the Agent's own conversation store as a restart would find it.  Its
answer is taller than the transcript's view, so the physical journey can
scroll the transcript by screen rows before it adds a reviewed exchange at
the end.  The answer wraps a long paragraph, holds text beyond ASCII that
still breaks on its characters, and a right-to-left paragraph.
"""

from __future__ import annotations

QUESTION = "How does the transcript show a long answer?"
WRAPPING = " ".join(
    ["Long paragraphs wrap at spaces into the card's width, and each line "
     "keeps its words whole."] * 7
)
SIMPLE = "Dashes — and “curly quotes” still break on their characters."
HEBREW = "שלום עולם starts at the right edge."
STEPS = tuple(
    f"Step {number:02d} keeps the answer taller than the transcript's view."
    for number in range(1, 91)
)
LAST = "End of the long answer."
ANSWER = "\n".join((WRAPPING, SIMPLE, HEBREW, *STEPS, LAST))
# Each stored message's card: its header, the message's role, and its text.
CARDS = (("YOU", QUESTION), ("AGENT", ANSWER))

_BUFFER = 8192
_PIECE = 72  # bytes of text in each S" of the seed


def _appends(text: str) -> list[str]:
    """Forth that appends TEXT to the seed's buffer, a line feed between
    its paragraphs."""

    lines = []
    for index, paragraph in enumerate(text.split("\n")):
        if index:
            lines.append("    _ags-nl")
        # Each piece ends just after a space, so none starts with one.
        pieces = [""]
        for character in paragraph:
            pieces[-1] += character
            if character == " " and len(pieces[-1].encode()) >= _PIECE:
                pieces.append("")
        for piece in filter(None, pieces):
            assert not piece.startswith(" ")
            lines.append(f'    S" {piece}" _ags,')
    return lines


def forth_seed() -> str:
    """Forth that saves the conversation through the Agent's own store on
    the current filesystem, where Desk's Agent loads it."""

    for _header, text in CARDS:
        assert '"' not in text and len(text.encode()) < _BUFFER
    return "\n".join([
        "\\ The Agent's stored conversation (local_testing/agent_transcript.py).",
        f"CREATE _ags-text {_BUFFER} ALLOT",
        "VARIABLE _ags-u",
        "VARIABLE _ags-conv",
        "VARIABLE _ags-store",
        ": _ags,  ( addr len -- )",
        "    DUP >R _ags-text _ags-u @ + SWAP CMOVE R> _ags-u +! ;",
        ": _ags-nl  ( -- )  10 _ags-text _ags-u @ + C! 1 _ags-u +! ;",
        ": _ags-message  ( role -- )",
        "    AMSG-S-COMPLETE 1 _ags-text _ags-u @ _ags-conv @ ACONV-APPEND",
        '    0<> ABORT" Agent seed message append failed" DROP 0 _ags-u ! ;',
        ": _ags-question  ( -- )",
        *_appends(QUESTION),
        "    ;",
        ": _ags-answer  ( -- )",
        *_appends(ANSWER),
        "    ;",
        ": _ags-seed  ( -- )",
        '    ACONV-NEW 0<> ABORT" Agent seed conversation allocation failed"',
        "    _ags-conv ! 0 _ags-u !",
        "    _ags-question AROLE-USER _ags-message",
        "    _ags-answer AROLE-ASSISTANT _ags-message",
        "    VFS-CUR AVFSSTORE-NEW",
        '    DUP ACSTORE-S-OK <> ABORT" Agent seed store allocation failed"',
        "    DROP _ags-store !",
        "    _ags-conv @ _ags-store @ ACSTORE-SAVE",
        '    ACSTORE-S-OK <> ABORT" Agent seed save failed"',
        "    _ags-store @ ACSTORE-FREE",
        "    _ags-conv @ ACONV-FREE ;",
        "_ags-seed",
        "",
    ])
