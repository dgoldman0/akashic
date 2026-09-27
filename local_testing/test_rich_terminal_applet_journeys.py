"""The journeys for Desk with a single applet, over synthetic frames.

Desk with one applet gives it the whole content area above the taskbar and
its taskbar button is slot 1.  Each test steps a journey through the frames
the physical runner would present and checks the one input each sends.
"""

from __future__ import annotations

from dataclasses import replace

import pytest

import akashic_tui  # noqa: F401  Ensures the selected MegaPad tree is importable.
import mixed_text
import rich_terminal_desktop_acceptance as acceptance_runner
from rich_terminal import text_rules
from rich_terminal.pygame_view import ControlIdentity
from rich_terminal.retained_scene import ControlKind, ControlState
from rich_terminal.retained_view import MenuBarDraw
from rich_terminal.semantic_content import (
    SemanticContentFlag,
    SemanticTextContent,
    SemanticTextItem,
    SemanticTextRole,
    SemanticTextState,
)
from rich_terminal_applet_journeys import (
    DaybookAloneJourney,
    PadAloneJourney,
    applet_journey,
)
from rich_terminal_desktop_acceptance import (
    PhysicalDesktopAcceptanceError,
    RichScreenProjection,
)
from test_rich_terminal_desktop_acceptance import _cell_offer, _offer, _place_cells

COLS = acceptance_runner.CANONICAL_DESKTOP_COLS
ROWS = acceptance_runner.CANONICAL_DESKTOP_ROWS
PAD_READY = ("Selection", "Untitled")
DAYBOOK_READY = ("Entry",)
EDITOR_ROW = 4
EDITOR_COL = 5
PROMPT_ROW = 82
FIELD_COL = len(" New task: ")


def _area_state(lines: tuple[str, ...], primary: tuple[int, int]) -> tuple:
    """Pad's STX1 value for LINES with the caret at PRIMARY."""

    columns = max(1, *(text_rules.string_width(line) for line in lines))
    content = SemanticTextContent(
        1,
        len(lines),
        columns,
        0,
        0,
        len(lines),
        columns,
        SemanticContentFlag(0),
        primary[0],
        primary[1],
        0,
        0,
        tuple(
            SemanticTextItem(
                row + 1,
                row,
                0,
                1,
                columns,
                SemanticTextRole.CONTENT,
                SemanticTextState(0),
                line,
            )
            for row, line in enumerate(lines)
        ),
    )
    return acceptance_runner._semantic_text_content_state(content)


def _screen(rows: dict[int, str], menus: tuple) -> RichScreenProjection:
    lines = tuple(rows.get(row, "").ljust(COLS) for row in range(ROWS))
    return RichScreenProjection(
        COLS,
        ROWS,
        lines,
        COLS * ROWS,
        menu_bar_count=len(menus),
        menu_signatures=menus,
    )


def _pad_frame(text: str, primary: tuple[int, int], *, focused: bool = True):
    before = len(text_rules.characters(text[: primary[1]], keep_tab=True))
    projection = _screen(
        {
            0: " File  Build  Edit  Selection  View  Go  Help",
            2: " Untitled",
            81: f" Ln {primary[0]}, Col {before + 1}",
            ROWS - 1: "[1:Akashic Pa*]" if focused else "[1:Akashic Pa]",
        },
        (acceptance_runner.PAD_MENU_SIGNATURE,),
    )
    state = ControlState.VISIBLE | ControlState.ENABLED
    # The search results panel beside the editor starts higher up.
    results = acceptance_runner._SemanticCollectionClaim(
        ControlKind.TEXT_AREA,
        ControlIdentity(1, 1, 20_003),
        230,
        1,
        COLS,
        60,
        visible_text=(),
        content_revision=1,
        content_state=_area_state(("",), (1, 0)),
        state=state,
    )
    editor = acceptance_runner._SemanticCollectionClaim(
        ControlKind.TEXT_AREA,
        ControlIdentity(1, 1, 20_000),
        0,
        3,
        229,
        60,
        visible_text=(text,),
        content_revision=1,
        content_state=_area_state((text,), primary),
        state=state | ControlState.SELECTED,
    )
    output = acceptance_runner._SemanticCollectionClaim(
        ControlKind.TEXT_AREA,
        ControlIdentity(1, 1, 20_002),
        0,
        60,
        COLS,
        80,
        visible_text=(),
        content_revision=1,
        content_state=_area_state(("",), (1, 0)),
        state=state,
    )
    projection = replace(
        projection, semantic_collection_claims=(results, editor, output)
    )
    return _place_cells(projection, EDITOR_ROW, EDITOR_COL, mixed_text.visual(text))


def _run(journey, steps, *, generation: int = 9) -> list:
    sent = []

    def sender(method, value, offer, frame_generation):
        assert frame_generation == generation
        sent.append((method, value))
        return "progress"

    progress = []
    for index, (offer, frame) in enumerate(steps):
        offer = replace(offer, offer_id=index + 1)
        before = len(sent)
        result = journey.after_present(offer, generation, frame, sender)
        progress.append((result, sent[before:]))
    return progress


def _pad_offer(text: str):
    return _cell_offer(1, ((EDITOR_ROW, EDITOR_COL, mixed_text.visual(text)),))


def test_pad_alone_types_mixed_text_and_moves_by_whole_characters() -> None:
    full = mixed_text.PAD_TEXT
    cluster = full.index(mixed_text.PAD_CLUSTER)
    family = full.index(mixed_text.PAD_FAMILY)
    family_end = family + len(mixed_text.PAD_FAMILY)
    shortened = full[:family] + full[family_end:]
    lamed = full.index(mixed_text.PAD_HEBREW) + 1
    journey = applet_journey("pad", PAD_READY)
    assert isinstance(journey, PadAloneJourney)
    blank = _cell_offer(1, ())
    steps = (
        # Desk starts Pad without focus; Alt+1 gives it.
        (blank, _pad_frame("", (1, 0), focused=False)),
        (blank, _pad_frame("", (1, 0))),
        # The guest may paint between typed characters.
        (_pad_offer(full[:4]), _pad_frame(full[:4], (1, 4))),
        (_pad_offer(full), _pad_frame(full, (1, len(full)))),
        (blank, _pad_frame(full, (1, cluster))),
        (blank, _pad_frame(full, (1, cluster + 2))),
        (blank, _pad_frame(full, (1, family_end))),
        (_pad_offer(shortened), _pad_frame(shortened, (1, family))),
        (_pad_offer(full), _pad_frame(full, (1, family_end))),
        (blank, _pad_frame(full, (1, lamed))),
    )
    results = _run(journey, steps)
    value = "1,1,20000,1,{}".format
    assert [(result.milestone, sent) for result, sent in results] == [
        (None, [("send_key", "alt+1")]),
        ("pad-ready", [("send_text", full)]),
        (None, []),
        ("pad-mixed-text-typed", [("text_place", value(cluster))]),
        ("pad-caret-placed-on-cluster", [("send_key", "right")]),
        ("pad-caret-moved-over-cluster", [("text_place", value(family_end))]),
        ("pad-caret-after-emoji-sequence", [("send_key", "backspace")]),
        ("pad-emoji-sequence-deleted", [("send_key", "ctrl+z")]),
        ("pad-emoji-sequence-restored", [("text_place", value(lamed))]),
        ("pad-caret-placed-in-hebrew", []),
    ]
    assert results[-1][0].complete
    assert journey.stage == journey.final_stage
    assert journey.final_cell_markers == ("[1:Akashic Pa*]", mixed_text.visual(full))


@pytest.mark.parametrize(
    ("stage", "text", "primary", "message"),
    (
        # Right moved one scalar, into the middle of the combined accent.
        (
            PadAloneJourney.PAST_CLUSTER,
            mixed_text.PAD_TEXT,
            (1, mixed_text.PAD_TEXT.index(mixed_text.PAD_CLUSTER) + 1),
            "caret",
        ),
        # Backspace deleted only the emoji sequence's last scalar.
        (
            PadAloneJourney.FAMILY_DELETED,
            mixed_text.PAD_TEXT.replace(mixed_text.PAD_FAMILY, mixed_text.PAD_FAMILY[:-1]),
            (1, 0),
            "all of it",
        ),
        (PadAloneJourney.TYPED, "Hx ", (1, 3), "diverged"),
    ),
)
def test_pad_alone_refuses_wrong_results(stage, text, primary, message) -> None:
    journey = PadAloneJourney(PAD_READY)
    journey.stage = stage
    journey._before = (1, 0)
    journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)

    def sender(*_args):
        raise AssertionError("no input may be sent")

    with pytest.raises(PhysicalDesktopAcceptanceError, match=message):
        journey.after_present(_pad_offer(text), 9, _pad_frame(text, primary), sender)


def _daybook_frame(*, prompt: str | None = None, agenda: str | None = None):
    rows = {0: " File  Entry  Go  Help", ROWS - 1: "[1:Daybook*]"}
    menus = () if prompt is not None else (acceptance_runner.DAYBOOK_MENU_SIGNATURE,)
    projection = _screen(rows, menus)
    if prompt is None:
        grid = acceptance_runner._SemanticCollectionClaim(
            ControlKind.TEXT_GRID,
            ControlIdentity(1, 1, 20_001),
            0,
            1,
            25,
            11,
            content_revision=1,
            primary_key=1,
            content_state=_area_state(("1",), (1, 0)),
        )
        projection = replace(projection, semantic_collection_claims=(grid,))
    if agenda is not None:
        projection = _place_cells(projection, 10, 28, "[ ] " + mixed_text.visual(agenda))
    if prompt is not None:
        projection = _place_cells(projection, PROMPT_ROW, 1, "New task: ")
        projection = _place_cells(projection, PROMPT_ROW, FIELD_COL, mixed_text.visual(prompt))
    return projection


def _prompt_offer(text: str, caret: int | None = None):
    reversed_cells = () if caret is None else ((PROMPT_ROW, caret),)
    return _cell_offer(
        1, ((PROMPT_ROW, FIELD_COL, mixed_text.visual(text)),), reversed_cells
    )


def test_daybook_alone_adds_a_mixed_task_through_its_prompt() -> None:
    task = mixed_text.DAYBOOK_TASK
    emoji_end = task.index(mixed_text.DAYBOOK_EMOJI) + len(mixed_text.DAYBOOK_EMOJI)
    head, shortened = task[:emoji_end], task[: emoji_end - len(mixed_text.DAYBOOK_EMOJI)]
    entry = mixed_text.DAYBOOK_ENTRY
    visual_task = mixed_text.visual(task)
    han = FIELD_COL + text_rules.string_width(
        visual_task[: visual_task.index(mixed_text.DAYBOOK_HAN)]
    )
    journey = applet_journey("daybook", DAYBOOK_READY)
    assert isinstance(journey, DaybookAloneJourney)
    blank = _cell_offer(1, ())
    steps = (
        (blank, _daybook_frame()),
        (blank, _daybook_frame(prompt="")),
        (_prompt_offer(head), _daybook_frame(prompt=head)),
        (_prompt_offer(shortened), _daybook_frame(prompt=shortened)),
        (_prompt_offer(task), _daybook_frame(prompt=task)),
        # The caret has not reached the Han character yet.
        (_prompt_offer(task), _daybook_frame(prompt=task)),
        (_prompt_offer(task, han), _daybook_frame(prompt=task)),
        (_prompt_offer(entry), _daybook_frame(prompt=entry)),
        # Enter has not closed the prompt yet.
        (_prompt_offer(entry), _daybook_frame(prompt=entry)),
        (
            _cell_offer(1, ((10, 28, "[ ] " + mixed_text.visual(entry)),)),
            _daybook_frame(agenda=entry),
        ),
    )
    results = _run(journey, steps)
    assert [(result.milestone, sent) for result, sent in results] == [
        ("daybook-ready", [("send_key", "ctrl+n")]),
        ("daybook-prompt-opened", [("send_text", head)]),
        ("daybook-prompt-head-typed", [("send_key", "backspace")]),
        ("daybook-emoji-sequence-deleted", [("send_text", task[len(shortened):])]),
        ("daybook-mixed-task-typed", [("pointer_click", f"{han + 1},{PROMPT_ROW}")]),
        (None, []),
        ("daybook-prompt-caret-on-han", [("send_text", mixed_text.DAYBOOK_INSERT)]),
        ("daybook-prompt-text-inserted-at-click", [("send_key", "enter")]),
        (None, []),
        ("daybook-mixed-task-added", []),
    ]
    assert results[-1][0].complete
    assert journey.final_cell_markers == ("[1:Daybook*]", mixed_text.visual(entry))


def test_daybook_alone_refuses_a_partial_backspace_and_leaked_semantics() -> None:
    task = mixed_text.DAYBOOK_TASK
    emoji_end = task.index(mixed_text.DAYBOOK_EMOJI) + len(mixed_text.DAYBOOK_EMOJI)
    head = task[:emoji_end]

    def sender(*_args):
        raise AssertionError("no input may be sent")

    journey = DaybookAloneJourney(DAYBOOK_READY)
    journey.stage = DaybookAloneJourney.EMOJI_DELETED
    journey._field = (FIELD_COL, PROMPT_ROW)
    journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
    partial = head[:-1]
    with pytest.raises(PhysicalDesktopAcceptanceError, match="whole emoji"):
        journey.after_present(
            _prompt_offer(partial), 9, _daybook_frame(prompt=partial), sender
        )

    # While the prompt is open, Daybook's menu must be withheld.
    leaked = replace(
        _daybook_frame(prompt=head),
        menu_bar_count=1,
        menu_signatures=(acceptance_runner.DAYBOOK_MENU_SIGNATURE,),
    )
    journey = DaybookAloneJourney(DAYBOOK_READY)
    journey.stage = DaybookAloneJourney.HEAD_TYPED
    journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
    with pytest.raises(PhysicalDesktopAcceptanceError, match="withhold"):
        journey.after_present(_prompt_offer(head), 9, leaked, sender)


def test_every_single_applet_profile_has_a_journey() -> None:
    for name in akashic_tui.DESKTOP_APT1_APPLETS:
        profile = akashic_tui.PROFILES[f"desktop-apt1-{name}"]
        journey = applet_journey(name, profile.ready_markers)
        assert journey.ready_markers == profile.ready_markers
        # Desk and the one applet, nothing else.
        assert profile.roots == ("tui/desk-apt1.f", akashic_tui.desk_applet(name).module)


def test_frames_of_desk_with_one_applet_may_lack_a_menu_bar() -> None:
    # A frame of residual glyphs alone, as while Daybook's prompt withholds
    # the only applet's menu.
    offer = _offer("xxxxx\nyyyyy")
    region = offer.retained.regions[0]
    draws = tuple(draw for draw in region.draws if not isinstance(draw, MenuBarDraw))
    offer = replace(
        offer,
        retained=replace(offer.retained, regions=(replace(region, draws=draws),)),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="no semantic menu bar"):
        acceptance_runner.reconstruct_retained_screen(offer)
    projection = acceptance_runner.reconstruct_retained_screen(
        offer, require_menu_bar=False
    )
    assert projection.menu_bar_count == 0
    assert acceptance_runner.DesktopAcceptanceJourney.requires_menu_bar
    assert not PadAloneJourney.requires_menu_bar
    assert not DaybookAloneJourney.requires_menu_bar
