"""Typed text that mixes scripts, for the Pad and Daybook journeys.

Each text mixes English, Chinese, an accent built from a combining mark, an
emoji sequence, a flag, Hebrew, and Arabic, as APT-1-TEXT lays them out.
The standalone Pad and Daybook smoke journeys check them applet by applet,
and the physical Desktop journey types the same text as regression.
"""

from __future__ import annotations

from rich_terminal import text_rules

PAD_TEXT = (
    "Hi \u4e2d\u6587 e\u0301 \U0001F468\u200d\U0001F469\u200d\U0001F467 "
    "\U0001F1EF\U0001F1F5 \u05e9\u05dc\u05d5\u05dd \u0645\u0631\u062d\u0628\u0627"
)
PAD_HAN = "\u4e2d"
PAD_CLUSTER = "e\u0301"
PAD_FAMILY = "\U0001F468\u200d\U0001F469\u200d\U0001F467"
PAD_HEBREW = "\u05e9\u05dc\u05d5\u05dd"

DAYBOOK_TASK = (
    "Tea \u8336 ne\u0301e \U0001F469\u200d\U0001F4BB \U0001F1EE\U0001F1F1 "
    "\u05e9\u05dc\u05d5\u05dd \u0634\u0627\u064a"
)
DAYBOOK_HAN = "\u8336"
DAYBOOK_EMOJI = "\U0001F469\u200d\U0001F4BB"
# Typed at the clicked Han character, giving DAYBOOK_ENTRY.
DAYBOOK_INSERT = "!"
DAYBOOK_ENTRY = DAYBOOK_TASK.replace(DAYBOOK_HAN, DAYBOOK_INSERT + DAYBOOK_HAN, 1)


def visual(text: str) -> str:
    """TEXT as its cells show it: one AUTO paragraph's characters in visual
    order, each its display scalars (APT-1-TEXT Sections 3 to 8)."""

    return "".join(placed.text for placed in text_rules.layout_row(text).characters)
