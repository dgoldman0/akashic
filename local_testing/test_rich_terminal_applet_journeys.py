"""The journeys for Desk with a single applet, over synthetic frames.

Desk with one applet gives it the whole content area above the taskbar and
its taskbar button is slot 1.  Each test steps a journey through the frames
the physical runner would present and checks the one input each sends.
"""

from __future__ import annotations

from dataclasses import replace
from types import SimpleNamespace

import pytest

import akashic_tui  # noqa: F401  Ensures the selected MegaPad tree is importable.
import agent_transcript
import mixed_text
import physical_desktop_acceptance
import styled_text
import rich_terminal_desktop_acceptance as acceptance_runner
from rich_terminal import text_rules
from rich_terminal.pygame_view import ControlIdentity
from rich_terminal.retained_scene import ControlKind, ControlState, StatusSeverity
from rich_terminal.retained_view import MenuBarDraw
from rich_terminal.semantic_dialogs import ButtonContent, ButtonFlag, DialogContent, DialogFlag
from rich_terminal.semantic_fields import (
    FieldChoice, FieldContent, FieldFlag, FieldKind, FieldRect,
)
from rich_terminal.semantic_content import (
    SemanticContentFlag,
    StyleRun,
    SemanticTextContent,
    SemanticTextItem,
    SemanticTextRole,
    SemanticTextState,
)
from rich_terminal.semantic_items import (
    ItemColumn,
    ItemColumnKind,
    ItemField,
    ItemRole,
    ItemState,
    ItemViewContent,
    ItemViewFlag,
    ItemViewRole,
    ViewItem,
)
from rich_terminal_applet_journeys import (
    AGENT_LONG_CHANGES,
    AGENT_LONG_EXCHANGE,
    AGENT_LONG_LAST,
    AGENT_LONG_REQUEST,
    AGENT_REVIEW_DETENTS,
    AGENT_REVIEW_BUTTONS,
    AGENT_REVIEW_TITLE,
    DIALOG_MORE,
    AGENT_AUDIT,
    AGENT_EXCHANGE,
    AGENT_MENU_SIGNATURE,
    AGENT_REQUEST,
    AGENT_REVIEW_MARKER,
    AGENT_REVIEW_REASON,
    AGENT_SETTINGS_CHOSEN,
    AGENT_SETTINGS_SHOWN,
    DAYBOOK_DAILY_SCHEDULE,
    DAYBOOK_DELETE_QUESTION,
    DAYBOOK_REMINDER_NOTICE,
    DESK_PROMPT_OVER,
    DESK_PROMPT_TEXT,
    SMALL_TERMINAL_LARGE_LINE,
    SMALL_TERMINAL_LARGE_PATH,
    STREAMS_CARDS,
    STREAMS_CONTEXT_MARKER,
    STREAMS_FEED_PROMPT,
    STREAMS_FEED_URL,
    STREAMS_LINK,
    STREAMS_NO_SOURCES,
    STREAMS_REPLY_TEXT,
    STREAMS_ROOT_TEXT,
    STREAMS_SOURCE_CARD,
    FEXP_PHOTO,
    FEXP_PHOTO_FACTS,
    FEXP_PHOTO_SIZE,
    AgentAloneJourney,
    DaybookAloneJourney,
    FexpAloneJourney,
    PadAloneJourney,
    PhotoJourney,
    DamagedPictureJourney,
    SmallTerminalJourney,
    StreamsAloneJourney,
    SoundLabAloneJourney,
    ObservatoryJourney,
    OBSERVATORY_DEMO_SERIES,
    applet_journey,
)
from rich_terminal_desktop_acceptance import (
    SAFE_MODE_BOOT_NOTICE,
    JourneyProgress,
    PhysicalDesktopAcceptanceError,
    RichScreenProjection,
    _require_desk_launcher_dialog,
    _shows_safe_mode_notice,
)
from test_rich_terminal_desktop_acceptance import (
    SOUNDLAB_FIELD_ID,
    _cell_offer,
    _offer,
    _place_cells,
    _soundlab_field_claims,
)

COLS = acceptance_runner.CANONICAL_DESKTOP_COLS
ROWS = acceptance_runner.CANONICAL_DESKTOP_ROWS
PAD_READY = ("Selection", "Untitled")
DAYBOOK_READY = ("Entry",)
STREAMS_READY = ("STREAMS", "T thread")
EDITOR_ROW = 4
EDITOR_COL = 5
PROMPT_ROW = 82
FIELD_COL = len(" New task: ")
PROMPT_ID = 40_000


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
        menu_bar_identities=tuple(
            ControlIdentity(1, 1, 30_100 + index) for index in range(len(menus))
        ),
    )


def _prompt(label: str, typed: str, *, row: int, caret: int | None = None):
    """The shared prompt over ROW: a TEXT field in a modal region, its label
    then TYPED with the caret at CARET, by default its end."""

    start = len(label) + 2
    content = FieldContent(
        1 + len(typed),
        FieldKind.TEXT,
        FieldFlag(0),
        FieldRect(1, 0, len(label), 1),
        FieldRect(start, 0, COLS - start, 1),
        text=typed,
        caret=len(typed) if caret is None else caret,
    )
    return acceptance_runner._SemanticFieldClaim(
        ControlIdentity(1, 1, PROMPT_ID), 0, row, COLS, row + 1, label,
        ControlState.VISIBLE | ControlState.ENABLED | ControlState.SELECTED,
        content, modal=True,
    )


def _held(frame: RichScreenProjection, prompt) -> RichScreenProjection:
    """FRAME with PROMPT open over it: every control beneath is inactive."""

    inactive = set(frame.menu_bar_identities)
    for claims in (
        frame.semantic_collection_claims,
        frame.semantic_item_view_claims,
        frame.semantic_document_claims,
        frame.semantic_tabset_claims,
        frame.semantic_field_claims,
    ):
        inactive.update(claim.identity for claim in claims)
    return replace(
        frame,
        semantic_field_claims=frame.semantic_field_claims + ((prompt,) if prompt else ()),
        inactive_controls=frozenset(inactive),
    )


def _pad_frame(
    text: str,
    primary: tuple[int, int],
    *,
    focused: bool = True,
    lines: tuple[str, ...] | None = None,
    style_runs: tuple[tuple[int, int, int, int], ...] = (),
):
    """Pad's editor showing TEXT, or several LINES with STYLE_RUNS as
    (item key, start, length, meaning), with the caret at PRIMARY."""

    lines = (text,) if lines is None else lines
    caret_line = lines[primary[0] - 1]
    before = len(text_rules.characters(caret_line[: primary[1]], keep_tab=True))
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
        visible_text=lines,
        content_revision=1,
        content_state=_area_state(lines, primary),
        state=state | ControlState.SELECTED,
        style_runs=style_runs,
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
    for row, line in enumerate(lines):
        projection = _place_cells(
            projection, EDITOR_ROW + row, EDITOR_COL, mixed_text.visual(line)
        )
    return projection


def _question(message: str, buttons, *, row: int = 30, col: int = 60):
    """An application's question in a modal region: MESSAGE on one line,
    then BUTTONS, each (label, flags), along the dialog's last row."""

    width = max(len(message) + 4, 12 * len(buttons) + 4)
    content = DialogContent(1, DialogFlag(0), 3, FieldRect(2, 0, 7, 1),
                            FieldRect(2, 2, len(message), 1), message=message)
    state = ControlState.VISIBLE | ControlState.ENABLED
    claims = tuple(
        acceptance_runner._SemanticButtonClaim(
            ControlIdentity(1, 1, PROMPT_ID + 1 + index),
            col + 2 + 12 * index, row + 4, col + 12 + 12 * index, row + 5, label,
            state | (ControlState.SELECTED if flags & ButtonFlag.DEFAULT else 0),
            ButtonContent(flags),
        )
        for index, (label, flags) in enumerate(buttons)
    )
    return acceptance_runner._SemanticDialogClaim(
        ControlIdentity(1, 1, PROMPT_ID), col, row, col + width, row + 6, "Confirm",
        ControlState.VISIBLE, content, modal=True, buttons=claims,
    )


def _notice(message: str, severity: StatusSeverity = StatusSeverity.NEUTRAL):
    """The app shell's notice saying MESSAGE, centred on the bottom row, its
    bar four cells wider than its text."""

    width = len(message) + 4
    left = (COLS - width) // 2
    content = DialogContent(1, DialogFlag.NOTICE, severity, FieldRect(0, 0, 0, 0),
                            FieldRect(2, 0, len(message), 1), message=message)
    return acceptance_runner._SemanticDialogClaim(
        ControlIdentity(1, 1, 40_000), left, ROWS - 1, left + width, ROWS, "",
        ControlState.VISIBLE, content)


def _noticed(frame: RichScreenProjection, notice) -> RichScreenProjection:
    """FRAME with NOTICE over its bottom row, which holds nothing modal."""

    return replace(frame, semantic_dialog_claims=frame.semantic_dialog_claims + (notice,))


def _notice_offer(message: str):
    """CELL with MESSAGE in the notice's bar on the bottom row."""

    width = len(message) + 4
    return _cell_offer(1, ((ROWS - 1, (COLS - width) // 2 + 2, message),))


def _asked(frame: RichScreenProjection, dialog) -> RichScreenProjection:
    """FRAME with DIALOG open over it: every control beneath is inactive."""

    held = _held(frame, None)
    return replace(held, semantic_field_claims=frame.semantic_field_claims,
                   semantic_dialog_claims=(dialog,))


PAD_QUESTION_BUTTONS = (
    ("Discard", ButtonFlag.DESTRUCTIVE),
    ("Cancel", ButtonFlag.DEFAULT | ButtonFlag.CANCEL),
)


def _pad_question_offer(text: str):
    return _cell_offer(1, ((EDITOR_ROW, EDITOR_COL, mixed_text.visual(text)),
                           (32, 62, "Discard unsaved changes?")))


def _pad_prompt_frame(typed: str):
    """Pad's Open prompt over its status row, with Pad's menu bar and text
    areas rich and inactive beneath it."""

    return _held(_pad_frame("", (1, 0)), _prompt("Open:", typed, row=81))


def _pad_prompt_offer(typed: str = ""):
    return _cell_offer(1, ((81, 1, f"Open: {typed}"),))


def _keyed(key: int, runs) -> tuple[tuple[int, int, int, int], ...]:
    return tuple((key, start, length, meaning) for start, length, meaning in runs)


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
        # Ctrl+W asks first; Cancel keeps the buffer.
        (_pad_question_offer(full),
         _asked(_pad_frame(full, (1, lamed)),
                _question("Discard unsaved changes?", PAD_QUESTION_BUTTONS))),
        (_pad_offer(full), _pad_frame(full, (1, lamed))),
        # Ctrl+O opens the prompt over the editor.
        (_pad_prompt_offer(), _pad_prompt_frame("")),
        (_pad_prompt_offer(styled_text.NOTES_PATH), _pad_prompt_frame(styled_text.NOTES_PATH)),
        (_pad_prompt_offer(styled_text.NOTES_PATH), _pad_prompt_frame(styled_text.NOTES_PATH)),
        (
            blank,
            _pad_frame(
                "",
                (3, 0),
                lines=(styled_text.NOTES_HEADING, styled_text.NOTES_LINE, ""),
                style_runs=_keyed(1, styled_text.NOTES_HEADING_RUNS)
                + _keyed(2, styled_text.NOTES_LINE_RUNS),
            ),
        ),
        (
            _pad_offer(styled_text.EXAMPLE_LINE),
            _pad_frame(
                "",
                (3, 0),
                lines=(styled_text.EXAMPLE_LINE, "9 SQUARE .", ""),
                style_runs=_keyed(1, styled_text.EXAMPLE_LINE_RUNS),
            ),
        ),
    )
    results = _run(journey, steps)
    value = "1,1,20000,1,{}".format
    follow = styled_text.NOTES_LINE.index(styled_text.NOTES_LINK_WORD) + 2
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
        ("pad-caret-placed-in-hebrew", [("send_key", "ctrl+w")]),
        ("pad-close-question-shown", [("activate_button", f"1,1,{PROMPT_ID + 2}")]),
        ("pad-close-cancelled", [("send_key", "ctrl+o")]),
        ("pad-open-prompt-shown", [("send_text", styled_text.NOTES_PATH)]),
        ("pad-notes-path-typed", [("send_key", "enter")]),
        # A frame before the prompt closes waits.
        (None, []),
        ("pad-markdown-styled", [("text_follow", f"1,1,20000,2,{follow}")]),
        ("pad-link-followed-to-forth", []),
    ]
    assert results[-1][0].complete
    assert journey.stage == journey.final_stage
    assert journey.final_cell_markers == ("[1:Akashic Pa*]", styled_text.EXAMPLE_LINE)


def test_pad_alone_sends_again_a_key_held_back_until_a_newer_frame() -> None:
    """The terminal holds a key back while a newer frame is on its way, such
    as the one a notice's end sends.  The journey then decides again from
    that frame and sends the key again, bound to it, rather than wait for
    the caret to move as though the key had gone."""

    full = mixed_text.PAD_TEXT
    cluster = full.index(mixed_text.PAD_CLUSTER)
    family = full.index(mixed_text.PAD_FAMILY)
    family_end = family + len(mixed_text.PAD_FAMILY)
    shortened = full[:family] + full[family_end:]
    journey = PadAloneJourney(PAD_READY)
    blank = _cell_offer(1, ())
    frames = (
        (blank, _pad_frame("", (1, 0))),
        (_pad_offer(full), _pad_frame(full, (1, len(full)))),
        (blank, _pad_frame(full, (1, cluster))),
        (blank, _pad_frame(full, (1, cluster + 2))),
        (blank, _pad_frame(full, (1, family_end))),
        # The newer frame, with the caret where it was.
        (blank, _pad_frame(full, (1, family_end))),
        (_pad_offer(shortened), _pad_frame(shortened, (1, family))),
    )
    held = ["backpressured"]
    sent = []

    def sender(method, value, offer, frame_generation):
        sent.append((method, value, offer.offer_id))
        return held.pop() if value == "backspace" and held else "progress"

    milestones = []
    for index, (offer, frame) in enumerate(frames):
        offer = replace(offer, offer_id=index + 1)
        milestones.append(journey.after_present(offer, 9, frame, sender).milestone)
    assert sent[-3:] == [
        ("send_key", "backspace", 5),
        ("send_key", "backspace", 6),
        ("send_key", "ctrl+z", 7),
    ]
    assert milestones[-3:] == [
        "pad-caret-after-emoji-sequence",
        "pad-caret-after-emoji-sequence",
        "pad-emoji-sequence-deleted",
    ]
    assert journey.stage == PadAloneJourney.RESTORED


@pytest.mark.parametrize(
    ("buttons", "held", "message"),
    (
        # Discard as the default, Cancel only a cancel button.
        ((("Discard", ButtonFlag.DEFAULT), ("Cancel", ButtonFlag.CANCEL)), True,
         "Discard is not destructive"),
        ((("Discard", ButtonFlag.DESTRUCTIVE), ("Cancel", ButtonFlag.CANCEL)), True,
         "Cancel is not the default"),
        ((("Discard", ButtonFlag.DESTRUCTIVE),), True, "exactly Discard and Cancel"),
        # The editor beneath the question still takes input.
        (PAD_QUESTION_BUTTONS, False, "controls beneath it active"),
    ),
)
def test_pad_alone_refuses_a_question_that_does_not_hold_pad(buttons, held, message) -> None:
    full = mixed_text.PAD_TEXT
    lamed = full.index(mixed_text.PAD_HEBREW) + 1
    journey = PadAloneJourney(PAD_READY)
    journey.stage = PadAloneJourney.CLOSE_ASKED
    journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
    journey._editor_bounds = (0, 3, 229, 60)
    frame = _asked(_pad_frame(full, (1, lamed)),
                   _question("Discard unsaved changes?", buttons))
    if not held:
        frame = replace(frame, inactive_controls=frozenset())

    def sender(*_args):
        raise AssertionError("no input may be sent")

    with pytest.raises(PhysicalDesktopAcceptanceError, match=message):
        journey.after_present(_pad_question_offer(full), 9, frame, sender)


def test_pad_alone_refuses_a_cancel_that_lost_the_buffer() -> None:
    journey = PadAloneJourney(PAD_READY)
    journey.stage = PadAloneJourney.CLOSE_CANCELLED
    journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
    journey._editor_bounds = (0, 3, 229, 60)

    def sender(*_args):
        raise AssertionError("no input may be sent")

    with pytest.raises(PhysicalDesktopAcceptanceError, match="did not keep"):
        journey.after_present(_pad_offer(""), 9, _pad_frame("", (1, 0)), sender)


def test_pad_alone_refuses_missing_style_runs() -> None:
    journey = PadAloneJourney(PAD_READY)
    journey.stage = PadAloneJourney.NOTES_OPENED
    journey._lineage = None
    journey._editor_bounds = (0, 3, 229, 60)
    frame = _pad_frame(
        "",
        (3, 0),
        lines=(styled_text.NOTES_HEADING, styled_text.NOTES_LINE, ""),
        style_runs=_keyed(1, styled_text.NOTES_HEADING_RUNS),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="style runs"):
        _run(journey, ((_cell_offer(1, ()), frame),))


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
    journey._before = {stage: (1, 0)}
    journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)

    def sender(*_args):
        raise AssertionError("no input may be sent")

    with pytest.raises(PhysicalDesktopAcceptanceError, match=message):
        journey.after_present(_pad_offer(text), 9, _pad_frame(text, primary), sender)


AGENDA_ID = 20_004


def _daybook_agenda(task: str, *, checked: bool = False):
    """Daybook's agenda: three sections, keyed by kind, and one task under
    TASKS, keyed 16."""

    box = ItemState.CHECKABLE | (ItemState.CHECKED if checked else ItemState(0))
    items = (
        ViewItem(2, 0, 0, 0, ItemState(0), ItemRole.SECTION, (ItemField("SCHEDULE"),)),
        ViewItem(1, 0, 1, 0, ItemState(0), ItemRole.SECTION, (ItemField("TASKS"),)),
        ViewItem(16, 1, 2, 1, box, ItemRole.ITEM, (ItemField(task), ItemField(""))),
        ViewItem(3, 0, 3, 0, ItemState(0), ItemRole.SECTION, (ItemField("NOTES"),)),
    )
    return acceptance_runner._SemanticItemViewClaim(
        ControlIdentity(1, 1, AGENDA_ID),
        26,
        4,
        60,
        12,
        ItemViewContent(
            1,
            ItemViewRole.SECTIONS,
            ItemViewFlag(0),
            (ItemColumn(ItemColumnKind.TEXT), ItemColumn(ItemColumnKind.TEXT)),
            len(items),
            0,
            len(items),
            items,
        ),
    )


def _daybook_frame(
    *,
    prompt: str | None = None,
    caret: int | None = None,
    agenda: str | None = None,
    checked: bool = False,
    notice: bool = False,
):
    """Daybook's menu, calendar and agenda, with its task prompt holding
    PROMPT open over them when given."""

    rows = {0: " File  Entry  Go  Reminders  Help", ROWS - 1: "[1:Daybook*]"}
    projection = _screen(rows, (acceptance_runner.DAYBOOK_MENU_SIGNATURE,))
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
    if prompt is not None and agenda is None:
        agenda = "Water the plants"
    if agenda is not None:
        projection = replace(
            projection,
            semantic_item_view_claims=(_daybook_agenda(agenda, checked=checked),),
        )
    if prompt is not None:
        projection = _held(
            projection, _prompt("New task:", prompt, row=PROMPT_ROW, caret=caret)
        )
    if notice:
        projection = _noticed(projection, _notice(DAYBOOK_REMINDER_NOTICE))
    return projection


AUTOMATIONS_ID = 20_005
DAILY_KEY = 9


def _daybook_automations(*, selected: bool = False, daily: bool = True):
    """Daybook's automations: the boot's two reminders under ACTIVE, the
    daily one keyed DAILY_KEY, and SELECTED when SELECTED."""

    state = ItemState.SELECTED if selected else ItemState(0)
    items = (
        ViewItem(1, 0, 0, 0, ItemState(0), ItemRole.SECTION, (ItemField("ACTIVE"),)),
        ViewItem(8, 1, 1, 1, ItemState(0), ItemRole.ITEM,
                 (ItemField("Water the plants"), ItemField("next 12:02"))),
    )
    if daily:
        items += (ViewItem(DAILY_KEY, 1, 2, 1, state, ItemRole.ITEM,
                           (ItemField(DAYBOOK_DAILY_SCHEDULE), ItemField("next 09:00"))),)
    return acceptance_runner._SemanticItemViewClaim(
        ControlIdentity(1, 1, AUTOMATIONS_ID),
        1,
        4,
        60,
        12,
        ItemViewContent(
            1,
            ItemViewRole.SECTIONS,
            ItemViewFlag(0),
            (ItemColumn(ItemColumnKind.TEXT), ItemColumn(ItemColumnKind.TEXT)),
            len(items),
            0,
            len(items),
            items,
        ),
    )


def _automations_frame(*, selected: bool = False, daily: bool = True):
    """Daybook's menu and its automations in place of the calendar."""

    rows = {0: " File  Entry  Go  Automations  Help", ROWS - 1: "[1:Daybook*]"}
    projection = _screen(rows, (acceptance_runner.DAYBOOK_MENU_SIGNATURE,))
    return replace(
        projection,
        semantic_item_view_claims=(_daybook_automations(selected=selected, daily=daily),),
    )


def _automations_offer(*, question: bool = False):
    cells = ((6, 2, DAYBOOK_DAILY_SCHEDULE),)
    if question:
        cells += ((32, 62, DAYBOOK_DELETE_QUESTION),)
    return _cell_offer(1, cells)


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
    han_offset = task.index(mixed_text.DAYBOOK_HAN)
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
        (_prompt_offer(task, han), _daybook_frame(prompt=task, caret=han_offset)),
        (_prompt_offer(entry), _daybook_frame(prompt=entry)),
        # Enter has not closed the prompt yet.
        (_prompt_offer(entry), _daybook_frame(prompt=entry)),
        (
            _cell_offer(1, ((10, 28, "[ ] " + mixed_text.visual(entry)),)),
            _daybook_frame(agenda=entry),
        ),
        # The CHECK has not reached Daybook yet.
        (
            _cell_offer(1, ((10, 28, "[ ] " + mixed_text.visual(entry)),)),
            _daybook_frame(agenda=entry),
        ),
        (
            _cell_offer(1, ((10, 28, "[x] " + mixed_text.visual(entry)),)),
            _daybook_frame(agenda=entry, checked=True),
        ),
        # F4 has not shown the automations yet.
        (
            _cell_offer(1, ((10, 28, "[x] " + mixed_text.visual(entry)),)),
            _daybook_frame(agenda=entry, checked=True),
        ),
        (_automations_offer(), _automations_frame()),
        (_automations_offer(), _automations_frame(selected=True)),
        # Delete has not asked yet.
        (_automations_offer(), _automations_frame(selected=True)),
        (
            _automations_offer(question=True),
            _asked(_automations_frame(selected=True),
                   _question(DAYBOOK_DELETE_QUESTION, DAYBOOK_QUESTION_BUTTONS)),
        ),
        (_automations_offer(), _automations_frame(selected=True)),
        (
            _cell_offer(1, ((10, 28, "[x] " + mixed_text.visual(entry)),)),
            _daybook_frame(agenda=entry, checked=True),
        ),
        # The reminder has not fired yet.
        (
            _cell_offer(1, ((10, 28, "[x] " + mixed_text.visual(entry)),)),
            _daybook_frame(agenda=entry, checked=True),
        ),
        (
            _notice_offer(DAYBOOK_REMINDER_NOTICE),
            _daybook_frame(agenda=entry, checked=True, notice=True),
        ),
    )
    results = _run(journey, steps)
    assert [(result.milestone, sent) for result, sent in results] == [
        ("daybook-ready", [("send_key", "ctrl+n")]),
        ("daybook-prompt-opened", [("send_text", head)]),
        ("daybook-prompt-head-typed", [("send_key", "backspace")]),
        ("daybook-emoji-sequence-deleted", [("send_text", task[len(shortened):])]),
        ("daybook-mixed-task-typed",
         [("text_place", f"1,1,{PROMPT_ID},0,{han_offset}")]),
        (None, []),
        ("daybook-prompt-caret-on-han", [("send_text", mixed_text.DAYBOOK_INSERT)]),
        ("daybook-prompt-text-inserted-at-click", [("send_key", "enter")]),
        (None, []),
        ("daybook-mixed-task-added", [("item_check", f"1,1,{AGENDA_ID},16")]),
        (None, []),
        ("daybook-task-checked", [("send_key", "f4")]),
        (None, []),
        ("daybook-automations-shown",
         [("item_select", f"1,1,{AUTOMATIONS_ID},{DAILY_KEY}")]),
        ("daybook-daily-reminder-selected", [("send_key", "delete")]),
        (None, []),
        ("daybook-delete-question-shown",
         [("activate_button", f"1,1,{PROMPT_ID + 2}")]),
        ("daybook-delete-cancelled", [("send_key", "f4")]),
        ("daybook-calendar-shown-again", []),
        (None, []),
        ("daybook-reminder-notice", []),
    ]
    assert not any(result.complete for result, _ in results[:-1])
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
    journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
    partial = head[:-1]
    with pytest.raises(PhysicalDesktopAcceptanceError, match="whole emoji"):
        journey.after_present(
            _prompt_offer(partial), 9, _daybook_frame(prompt=partial), sender
        )

    # While the prompt is open, everything beneath it is inactive.
    leaked = replace(_daybook_frame(prompt=head), inactive_controls=frozenset())
    journey = DaybookAloneJourney(DAYBOOK_READY)
    journey.stage = DaybookAloneJourney.HEAD_TYPED
    journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
    with pytest.raises(PhysicalDesktopAcceptanceError, match="beneath it active"):
        journey.after_present(_prompt_offer(head), 9, leaked, sender)
    # Nor may it withhold the agenda.
    bare = replace(_daybook_frame(prompt=head), semantic_item_view_claims=())
    with pytest.raises(PhysicalDesktopAcceptanceError, match="calendar or agenda"):
        journey.after_present(_prompt_offer(head), 9, bare, sender)


DAYBOOK_QUESTION_BUTTONS = (
    ("Delete", ButtonFlag.DESTRUCTIVE),
    ("Cancel", ButtonFlag.DEFAULT | ButtonFlag.CANCEL),
)


def test_daybook_alone_refuses_a_cancel_that_lost_the_daily_reminder() -> None:
    def sender(*_args):
        raise AssertionError("no input may be sent")

    journey = DaybookAloneJourney(DAYBOOK_READY)
    journey.stage = DaybookAloneJourney.DELETE_CANCELLED
    journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
    offer = replace(_automations_offer(), offer_id=1)
    with pytest.raises(PhysicalDesktopAcceptanceError, match="keep Daybook's daily"):
        journey.after_present(offer, 9, _automations_frame(daily=False), sender)


def test_daybook_alone_refuses_a_delete_that_is_not_destructive() -> None:
    def sender(*_args):
        raise AssertionError("no input may be sent")

    journey = DaybookAloneJourney(DAYBOOK_READY)
    journey.stage = DaybookAloneJourney.DELETE_ASKED
    journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
    buttons = (
        ("Delete", ButtonFlag(0)),
        ("Cancel", ButtonFlag.DEFAULT | ButtonFlag.CANCEL),
    )
    frame = _asked(_automations_frame(selected=True),
                   _question(DAYBOOK_DELETE_QUESTION, buttons))
    offer = replace(_automations_offer(question=True), offer_id=1)
    with pytest.raises(PhysicalDesktopAcceptanceError, match="is not destructive"):
        journey.after_present(offer, 9, frame, sender)


TIMELINE_ID = 30_001
CONTEXT_ID = 30_002


def _streams_cards(posts, selected: int, control_id: int, *, link: bool = True):
    """Streams' cards for POSTS, keyed by row from 1, with row SELECTED
    selected and the web link a LINK run when LINK."""

    items = []
    for row, (head, text, reply) in enumerate(posts):
        runs = ()
        if link and STREAMS_LINK in text:
            runs = (
                StyleRun(text.index(STREAMS_LINK), len(STREAMS_LINK), styled_text.LINK),
            )
        state = ItemState.SELECTED if row == selected else ItemState(0)
        fields = (ItemField(head), ItemField(text, runs), ItemField(reply))
        items.append(ViewItem(row + 1, 0, row, 0, state, ItemRole.ITEM, fields))
    return acceptance_runner._SemanticItemViewClaim(
        ControlIdentity(1, 1, control_id),
        0,
        3,
        COLS,
        ROWS - 4,
        ItemViewContent(
            1,
            ItemViewRole.CARDS,
            ItemViewFlag(0),
            (ItemColumn(ItemColumnKind.TEXT),) * 3,
            len(items),
            0,
            len(items),
            tuple(items),
        ),
    )


def _streams_frame(cards, *, context: bool = False):
    rows = {
        1: "  STREAMS",
        2: "  offline | arrows select | T thread | / search",
        ROWS - 1: "[1:Streams*]",
    }
    if context:
        rows[3] = "  " + STREAMS_CONTEXT_MARKER
    return replace(_screen(rows, ()), semantic_item_view_claims=(cards,))


def _streams_offer(*, context: bool = False):
    placements = [(5, 3, STREAMS_ROOT_TEXT), (8, 3, STREAMS_REPLY_TEXT)]
    if context:
        placements.append((3, 2, STREAMS_CONTEXT_MARKER))
    return _cell_offer(1, tuple(placements))


def test_streams_alone_selects_and_opens_a_reply_through_its_cards() -> None:
    journey = applet_journey("streams", STREAMS_READY)
    assert isinstance(journey, StreamsAloneJourney)
    timeline = _streams_offer()
    context = _streams_offer(context=True)
    steps = (
        (timeline, _streams_frame(_streams_cards(STREAMS_CARDS, 0, TIMELINE_ID))),
        # The SELECT has not reached Streams yet.
        (timeline, _streams_frame(_streams_cards(STREAMS_CARDS, 0, TIMELINE_ID))),
        (timeline, _streams_frame(_streams_cards(STREAMS_CARDS, 1, TIMELINE_ID))),
        # The OPEN has not reached Streams yet.
        (timeline, _streams_frame(_streams_cards(STREAMS_CARDS, 1, TIMELINE_ID))),
        (
            context,
            _streams_frame(
                _streams_cards(STREAMS_CARDS[:2], 1, CONTEXT_ID), context=True
            ),
        ),
    )
    results = _run(journey, steps)
    assert [(result.milestone, sent) for result, sent in results] == [
        ("streams-cards-shown", [("item_select", f"1,1,{TIMELINE_ID},2")]),
        (None, []),
        ("streams-reply-selected", [("item_open", f"1,1,{TIMELINE_ID},2")]),
        (None, []),
        ("streams-context-opened", [("send_key", "s")]),
    ]
    assert journey.stage == StreamsAloneJourney.SOURCES


SOURCES_ID = 30_003


def _source_cards(*, checked: bool, revision: int):
    """Streams' one source card, a checkable card checked when CHECKED."""

    fields = list(STREAMS_SOURCE_CARD)
    fields[1] = fields[1].replace("revision 1", f"revision {revision}")
    fields[3] = "last never refreshed"
    state = ItemState.SELECTED | ItemState.CHECKABLE
    if checked:
        state |= ItemState.CHECKED
    item = ViewItem(1, 0, 0, 0, state, ItemRole.ITEM,
                    tuple(ItemField(text) for text in fields))
    return acceptance_runner._SemanticItemViewClaim(
        ControlIdentity(1, 1, SOURCES_ID), 0, 3, COLS, ROWS - 4,
        ItemViewContent(
            1, ItemViewRole.CARDS, ItemViewFlag(0),
            (ItemColumn(ItemColumnKind.TEXT),) * 5, 1, 0, 1, (item,),
        ),
    )


def _sources_frame(*, cards=None, prompt=None, empty: bool = False):
    rows = {
        1: "  STREAMS",
        2: "  F feed | P page | B auth AT | R refresh | E toggle",
        ROWS - 1: "[1:Streams*]",
    }
    if empty:
        rows[4] = "  " + STREAMS_NO_SOURCES + ". F feed | P page | B authenticated AT."
    frame = replace(_screen(rows, ()), semantic_item_view_claims=(cards,) if cards else ())
    return _held(frame, prompt) if prompt else frame


def test_streams_alone_adds_a_source_and_switches_it_off_by_its_check_box() -> None:
    journey = StreamsAloneJourney(STREAMS_READY)
    journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
    journey.stage = StreamsAloneJourney.SOURCES
    blank = _cell_offer(1, ())
    checked = _cell_offer(1, ((3, 1, "[x] Syndication feed"),))
    unchecked = _cell_offer(1, ((3, 1, "[ ] Syndication feed"),))
    prompt_row = ROWS - 2
    steps = (
        (blank, _sources_frame(empty=True)),
        (blank, _sources_frame(prompt=_prompt(STREAMS_FEED_PROMPT, "", row=prompt_row))),
        # The typing has not reached the prompt yet.
        (blank, _sources_frame(prompt=_prompt(STREAMS_FEED_PROMPT, "", row=prompt_row))),
        (blank, _sources_frame(
            prompt=_prompt(STREAMS_FEED_PROMPT, STREAMS_FEED_URL, row=prompt_row))),
        (checked, _sources_frame(cards=_source_cards(checked=True, revision=1))),
        # The CHECK has not reached Streams yet.
        (checked, _sources_frame(cards=_source_cards(checked=True, revision=1))),
        (unchecked, _sources_frame(cards=_source_cards(checked=False, revision=2))),
        # Escape has not reached Streams yet.
        (unchecked, _sources_frame(cards=_source_cards(checked=False, revision=2))),
        (_streams_offer(), _streams_frame(_streams_cards(STREAMS_CARDS, 0, TIMELINE_ID))),
    )
    results = _run(journey, steps)
    assert [(result.milestone, sent) for result, sent in results] == [
        ("streams-sources-empty", [("send_key", "f")]),
        ("streams-feed-prompt", [("send_text", STREAMS_FEED_URL)]),
        (None, []),
        ("streams-feed-typed", [("send_key", "enter")]),
        ("streams-source-added", [("item_check", f"1,1,{SOURCES_ID},1")]),
        (None, []),
        ("streams-source-switched-off", [("send_key", "escape")]),
        (None, []),
        ("streams-timeline-again", []),
    ]
    assert results[-1][0].complete
    assert journey.final_cell_markers == ("[1:Streams*]", STREAMS_REPLY_TEXT)


def test_streams_alone_refuses_a_source_card_that_reads_wrong() -> None:
    def sender(*_args):
        raise AssertionError("no input may be sent")

    journey = StreamsAloneJourney(STREAMS_READY)
    journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
    journey.stage = StreamsAloneJourney.SOURCE
    offer = _cell_offer(1, ((3, 1, "[x] Syndication feed"),))
    off = _sources_frame(cards=_source_cards(checked=False, revision=1))
    with pytest.raises(PhysicalDesktopAcceptanceError, match="begin enabled"):
        journey.after_present(offer, 9, off, sender)
    later = _sources_frame(cards=_source_cards(checked=True, revision=2))
    with pytest.raises(PhysicalDesktopAcceptanceError, match="new source card reads"):
        journey.after_present(offer, 9, later, sender)
    stale = _cell_offer(1, ((3, 1, "[x] Syndication feed"),
                            (ROWS - 2, 1, STREAMS_FEED_PROMPT + " " + STREAMS_FEED_URL)))
    added = _sources_frame(cards=_source_cards(checked=True, revision=1))
    with pytest.raises(PhysicalDesktopAcceptanceError, match="closed feed prompt"):
        journey.after_present(stale, 9, added, sender)


def test_streams_alone_requires_the_link_run_and_a_select_that_stays() -> None:
    def sender(*_args):
        raise AssertionError("no input may be sent")

    journey = StreamsAloneJourney(STREAMS_READY)
    journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
    unlinked = _streams_frame(_streams_cards(STREAMS_CARDS, 0, TIMELINE_ID, link=False))
    with pytest.raises(PhysicalDesktopAcceptanceError, match="web link"):
        journey.after_present(_streams_offer(), 9, unlinked, sender)

    # A SELECT selects; only an OPEN opens the context.
    journey.stage = StreamsAloneJourney.SELECTED
    opened = _streams_frame(
        _streams_cards(STREAMS_CARDS, 1, TIMELINE_ID), context=True
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="SELECT"):
        journey.after_present(_streams_offer(context=True), 9, opened, sender)


AGENT_VIEW_ID = 40_001
AGENT_TOP = 1
AGENT_BODY = 80


def _agent_rows(cards) -> list[int]:
    """Each card's screen rows at the full width: its header, and a row for
    each line of its text."""

    return [
        1 + len(text_rules.layout_lines(text, 0, COLS - 4)) for _header, text in cards
    ]


def _agent_view(cards, above: int, *, selected: int | None = None, styled: bool = True):
    """The Agent's transcript of CARDS with ABOVE screen rows above its view,
    carrying the cards with a row in the view."""

    rows = _agent_rows(cards)
    first, row = 0, above
    while row >= rows[first]:
        row -= rows[first]
        first += 1
    used, count = -row, 0
    for card_rows in rows[first:]:
        if used >= AGENT_BODY:
            break
        used += card_rows
        count += 1
    items = []
    for ordinal in range(first, first + count):
        header, text = cards[ordinal]
        runs = (StyleRun(0, len(header), styled_text.HEADING),) if styled else ()
        state = ItemState.SELECTED if ordinal == selected else ItemState(0)
        items.append(ViewItem(ordinal + 1, 0, ordinal, 0, state, ItemRole.ITEM,
                              (ItemField(header, runs), ItemField(text))))
    columns = (ItemColumn(ItemColumnKind.TEXT), ItemColumn(ItemColumnKind.TEXT, wrap=True))
    return acceptance_runner._SemanticItemViewClaim(
        ControlIdentity(1, 1, AGENT_VIEW_ID),
        0,
        AGENT_TOP,
        COLS,
        AGENT_TOP + AGENT_BODY,
        ItemViewContent(1, ItemViewRole.CARDS, ItemViewFlag(0), columns, len(cards),
                        first, count, tuple(items), row),
    )


def _agent_frame(view=None, rows: dict[int, str] | None = None, menus=()):
    rows = {ROWS - 1: "[1:Agent*]", **(rows or {})}
    projection = _screen(rows, menus)
    if view is not None:
        projection = replace(projection, semantic_item_view_claims=(view,))
    return projection


def _agent_prompt_frame(typed: str):
    """The Ask prompt over the Agent's last row, its menu and transcript
    rich and inactive beneath it."""

    frame = _agent_frame(_agent_view(STORED, STORED_END), menus=(AGENT_MENU_SIGNATURE,))
    return _held(frame, _prompt("Ask:", typed, row=82))


DESK_PROMPT_ID = 40_002


def _desk_prompt_frame(typed: str, *, caret: int | None = None, anchor: int | None = None):
    """Desk's Ask prompt across the taskbar row: the taskbar gone, the
    Agent's menu and transcript rich and inactive beneath it."""

    frame = _screen({ROWS - 1: " Ask: " + typed}, (AGENT_MENU_SIGNATURE,))
    frame = replace(frame, semantic_item_view_claims=(_agent_view(STORED, STORED_END),))
    prompt = replace(_prompt("Ask:", typed, row=ROWS - 1, caret=caret),
                     identity=ControlIdentity(1, 1, DESK_PROMPT_ID))
    if anchor is not None:
        prompt = replace(prompt, content=replace(prompt.content, anchor=anchor))
    return _held(frame, prompt)


def _agent_offer(last: str, *placements):
    """CELL with LAST on the transcript's last row, where card text starts."""

    return _cell_offer(1, ((AGENT_TOP + AGENT_BODY - 1, 3, last), *placements))


STORED = agent_transcript.CARDS
STORED_END = sum(_agent_rows(STORED)) - AGENT_BODY
APPROVED = STORED + AGENT_EXCHANGE
APPROVED_END = sum(_agent_rows(APPROVED)) - AGENT_BODY
LONG_APPROVED = APPROVED + AGENT_LONG_EXCHANGE
LONG_APPROVED_END = sum(_agent_rows(LONG_APPROVED)) - AGENT_BODY
REVIEW_ID = 40_010
REVIEW_LINES = ("AGENT", AGENT_REVIEW_REASON, AGENT_REVIEW_MARKER)
# The long review's lines in view: at its top, part way down, and at its end.
LONG_CHANGE_LINES = tuple(f"Simulated change {change} of {AGENT_LONG_CHANGES}."
                          for change in range(1, AGENT_LONG_CHANGES + 1))
LONG_TOP = ("AGENT", AGENT_REVIEW_REASON) + LONG_CHANGE_LINES[:30]
LONG_MIDDLE = LONG_CHANGE_LINES[15:47]
LONG_END = LONG_CHANGE_LINES[-31:] + (AGENT_REVIEW_MARKER,)


SETTINGS_ID = 40_020


def _agent_settings_frame(shown, choices):
    """The Agent's run settings in its transcript's place: a CHOICE field a
    setting, by label, on rows 3, 5, 7 and 9, showing SHOWN's choice of
    CHOICES' labels."""

    claims = []
    for index, label in enumerate(("Model", "Reasoning", "Speed", "Verbosity")):
        labels = choices[label]
        content = FieldContent(
            index + 1, FieldKind.CHOICE, FieldFlag(0), FieldRect(2, 0, 15, 1),
            FieldRect(18, 0, COLS - 21, 1), value=labels.index(shown[label]),
            choices=tuple(FieldChoice(value, choice) for value, choice in enumerate(labels)),
        )
        row = 2 * index + 4
        state = ControlState.VISIBLE | ControlState.ENABLED
        if index == 0:
            state |= ControlState.SELECTED
        claims.append(acceptance_runner._SemanticFieldClaim(
            ControlIdentity(1, 1, SETTINGS_ID + index), 1, row, COLS - 1, row + 1, label,
            state, content,
        ))
    return replace(_agent_frame(menus=(AGENT_MENU_SIGNATURE,)),
                   semantic_field_claims=tuple(claims))


SETTINGS_CHOICES = {
    "Model": ("Swift", "Deliberate"),
    "Reasoning": ("Low", "Medium"),
    "Speed": ("Standard",),
    "Verbosity": ("Auto", "Low", "Medium", "High"),
}
CHOSEN_CHOICES = {**SETTINGS_CHOICES, "Reasoning": ("Low", "High"),
                  "Speed": ("Standard", "Fast")}


def _agent_review(lines=REVIEW_LINES, *, approve=True, buttons=AGENT_REVIEW_BUTTONS,
                  modal=True):
    """The Agent's review over its tile: LINES as its message, then Approve
    once, which F6 chooses and which APPROVE says can be chosen, and Deny,
    which F7 chooses, the default and cancel button."""

    width = max(len(line) for line in lines)
    content = DialogContent(1, DialogFlag(0), 0, FieldRect(2, 0, len(AGENT_REVIEW_TITLE), 1),
                            FieldRect(2, 2, width, len(lines)), message="\n".join(lines))
    enabled = ControlState.VISIBLE | ControlState.ENABLED
    flags = (ButtonFlag(0), ButtonFlag.DEFAULT | ButtonFlag.CANCEL)
    states = (enabled if approve else ControlState.VISIBLE,
              enabled | ControlState.SELECTED)
    claims = tuple(
        acceptance_runner._SemanticButtonClaim(
            ControlIdentity(1, 1, REVIEW_ID + 1 + index),
            4 + 30 * index, 76, 24 + 30 * index, 77, label, states[index],
            ButtonContent(flags[index]), shortcut,
        )
        for index, (label, shortcut) in enumerate(buttons)
    )
    return acceptance_runner._SemanticDialogClaim(
        ControlIdentity(1, 1, REVIEW_ID), 1, 2, COLS - 1, 80, AGENT_REVIEW_TITLE,
        ControlState.VISIBLE, content, modal=modal, buttons=claims,
    )


def _agent_review_frame(review=None):
    """The Agent's review open over its tile, its menu rich and inactive
    beneath it and its transcript withheld under the dialog."""

    return _asked(_agent_frame(menus=(AGENT_MENU_SIGNATURE,)),
                  _agent_review() if review is None else review)


REVIEW_OFFER = _agent_offer("", (31, 2, AGENT_REVIEW_MARKER))


def test_agent_alone_scrolls_its_transcript_and_approves_a_review() -> None:
    journey = applet_journey("agent", ("Agent",))
    assert isinstance(journey, AgentAloneJourney)
    at_end = (_agent_offer(agent_transcript.LAST), _agent_frame(_agent_view(STORED, STORED_END)))
    scrolled = (
        _agent_offer(agent_transcript.STEPS[-3]),
        _agent_frame(_agent_view(STORED, STORED_END - 3)),
    )
    # The request streams before the review, and the reply and its record
    # arrive after the approval.
    streaming = STORED + AGENT_EXCHANGE[:1] + (
        ("AGENT  ...", AGENT_EXCHANGE[1][1].removesuffix(" Approved.")),
    ) + AGENT_EXCHANGE[2:]
    typed_over = DESK_PROMPT_TEXT[:1] + DESK_PROMPT_OVER + DESK_PROMPT_TEXT[4:]
    desk = _agent_offer(agent_transcript.LAST)
    steps = (
        at_end,
        # The wheel has not reached the Agent yet.
        at_end,
        scrolled,
        at_end,
        (desk, _desk_prompt_frame("")),
        # The guest may paint between typed characters.
        (desk, _desk_prompt_frame(DESK_PROMPT_TEXT[:3])),
        (desk, _desk_prompt_frame(DESK_PROMPT_TEXT)),
        # The PLACE has not moved the caret yet.
        (desk, _desk_prompt_frame(DESK_PROMPT_TEXT)),
        (desk, _desk_prompt_frame(DESK_PROMPT_TEXT, caret=1)),
        (desk, _desk_prompt_frame(DESK_PROMPT_TEXT, caret=4, anchor=1)),
        (desk, _desk_prompt_frame(typed_over[:2] + DESK_PROMPT_TEXT[4:])),
        (desk, _desk_prompt_frame(typed_over)),
        # Escape has not closed the prompt yet.
        (desk, _desk_prompt_frame(typed_over)),
        at_end,
        (_agent_offer(""), _agent_prompt_frame("")),
        (_agent_offer(""), _agent_prompt_frame(AGENT_REQUEST)),
        # The review says more lies below, and Approve once waits.
        (REVIEW_OFFER, _agent_review_frame(
            _agent_review(REVIEW_LINES + (DIALOG_MORE,), approve=False))),
        # The paging has not reached the Agent yet.
        (REVIEW_OFFER, _agent_review_frame(
            _agent_review(REVIEW_LINES + (DIALOG_MORE,), approve=False))),
        (REVIEW_OFFER, _agent_review_frame()),
        (
            _agent_offer(AGENT_AUDIT),
            _agent_frame(_agent_view(streaming, APPROVED_END, styled=False)),
        ),
        (_agent_offer(AGENT_AUDIT), _agent_frame(_agent_view(APPROVED, APPROVED_END))),
        (_agent_offer(""), _agent_settings_frame(AGENT_SETTINGS_SHOWN, SETTINGS_CHOICES)),
        # The adjustment has not reached the Agent yet.
        (_agent_offer(""), _agent_settings_frame(AGENT_SETTINGS_SHOWN, SETTINGS_CHOICES)),
        (_agent_offer(""), _agent_settings_frame(
            {**AGENT_SETTINGS_SHOWN, "Reasoning": "Medium"}, SETTINGS_CHOICES)),
        (_agent_offer(""), _agent_settings_frame(AGENT_SETTINGS_CHOSEN, CHOSEN_CHOICES)),
        # Escape has not closed the settings yet.
        (_agent_offer(""), _agent_settings_frame(AGENT_SETTINGS_CHOSEN, CHOSEN_CHOICES)),
        (_agent_offer(AGENT_AUDIT), _agent_frame(_agent_view(APPROVED, APPROVED_END))),
        (_agent_offer(""), _agent_prompt_frame("")),
        (_agent_offer(""), _agent_prompt_frame(AGENT_LONG_REQUEST)),
        # The long review opens at its top, more below, and Approve once waits.
        (REVIEW_OFFER, _agent_review_frame(
            _agent_review(LONG_TOP + (DIALOG_MORE,), approve=False))),
        # The wheel has not reached the Agent yet.
        (REVIEW_OFFER, _agent_review_frame(
            _agent_review(LONG_TOP + (DIALOG_MORE,), approve=False))),
        (REVIEW_OFFER, _agent_review_frame(
            _agent_review(LONG_MIDDLE + (DIALOG_MORE,), approve=False))),
        # The end shows, but no paint has unlocked Approve once yet.
        (REVIEW_OFFER, _agent_review_frame(_agent_review(LONG_END, approve=False))),
        (REVIEW_OFFER, _agent_review_frame(_agent_review(LONG_END))),
        (_agent_offer(AGENT_LONG_LAST),
         _agent_frame(_agent_view(LONG_APPROVED, LONG_APPROVED_END))),
    )
    results = _run(journey, steps)
    desk_value = f"1,1,{DESK_PROMPT_ID},0,{{}}".format
    assert [(result.milestone, sent) for result, sent in results] == [
        ("agent-transcript-at-end", [("item_scroll", f"1,1,{AGENT_VIEW_ID},-1")]),
        (None, []),
        ("agent-transcript-scrolled", [("send_key", "end")]),
        ("agent-transcript-end-again", [("send_key", "alt+a")]),
        ("desk-prompt-opened", [("send_text", DESK_PROMPT_TEXT)]),
        (None, []),
        ("desk-prompt-typed", [("text_place", desk_value(1))]),
        (None, []),
        ("desk-prompt-caret-placed", [("text_extend", desk_value(4))]),
        ("desk-prompt-selected", [("send_text", DESK_PROMPT_OVER)]),
        (None, []),
        ("desk-prompt-replaced", [("send_key", "escape")]),
        (None, []),
        ("desk-prompt-cancelled", [("send_key", "ctrl+l")]),
        ("agent-prompt-opened", [("send_text", AGENT_REQUEST)]),
        ("agent-request-typed", [("send_key", "enter")]),
        ("agent-review-paged", [("send_key", "pagedown")]),
        ("agent-review-paged", [("send_key", "pagedown")]),
        ("agent-review-unlocked", [("activate_button", f"1,1,{REVIEW_ID + 1}")]),
        (None, []),
        ("agent-review-approved", [("send_key", "f8")]),
        ("agent-settings-shown", [("field_adjust", f"1,1,{SETTINGS_ID + 1},1")]),
        (None, []),
        ("agent-reasoning-adjusted", [("field_activate", f"1,1,{SETTINGS_ID}")]),
        ("agent-model-chosen", [("send_key", "escape")]),
        (None, []),
        ("agent-settings-closed", [("send_key", "ctrl+l")]),
        ("agent-long-prompt-opened", [("send_text", AGENT_LONG_REQUEST)]),
        ("agent-long-request-typed", [("send_key", "enter")]),
        ("agent-long-review-scrolled",
         [("dialog_scroll", f"1,1,{REVIEW_ID},{AGENT_REVIEW_DETENTS}")]),
        (None, []),
        ("agent-long-review-scrolled",
         [("dialog_scroll", f"1,1,{REVIEW_ID},{AGENT_REVIEW_DETENTS}")]),
        (None, []),
        ("agent-long-review-unlocked", [("activate_button", f"1,1,{REVIEW_ID + 1}")]),
        ("agent-long-review-approved", []),
    ]
    assert results[-1][0].complete
    assert journey.final_cell_markers == ("[1:Agent*]", AGENT_LONG_LAST)


def test_agent_alone_refuses_a_selection_a_wrong_scroll_and_leaked_semantics() -> None:
    def sender(*_args):
        raise AssertionError("no input may be sent")

    def journey_at(stage: int) -> AgentAloneJourney:
        journey = AgentAloneJourney(("Agent",))
        journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
        journey.stage = stage
        journey._end_row = STORED_END
        return journey

    offer = _agent_offer(agent_transcript.LAST)
    selected = _agent_frame(_agent_view(STORED, STORED_END, selected=1))
    with pytest.raises(PhysicalDesktopAcceptanceError, match="selected a card"):
        journey_at(AgentAloneJourney.READY).after_present(offer, 9, selected, sender)
    plain = _agent_frame(_agent_view(STORED, STORED_END, styled=False))
    with pytest.raises(PhysicalDesktopAcceptanceError, match="is styled"):
        journey_at(AgentAloneJourney.READY).after_present(offer, 9, plain, sender)
    early = _agent_frame(_agent_view(STORED, STORED_END - 1))
    with pytest.raises(PhysicalDesktopAcceptanceError, match="not at its end"):
        journey_at(AgentAloneJourney.READY).after_present(offer, 9, early, sender)
    with pytest.raises(PhysicalDesktopAcceptanceError, match="does not end"):
        journey_at(AgentAloneJourney.READY).after_present(
            _agent_offer(agent_transcript.STEPS[-1]), 9,
            _agent_frame(_agent_view(STORED, STORED_END)), sender,
        )
    one_row = _agent_frame(_agent_view(STORED, STORED_END - 1))
    with pytest.raises(PhysicalDesktopAcceptanceError, match="3 rows"):
        journey_at(AgentAloneJourney.SCROLLED).after_present(offer, 9, one_row, sender)
    # A review that lets Approve once be chosen before its last line, offers
    # other buttons, is not modal, or leaves the Agent's menu active.
    early = _agent_review_frame(_agent_review(REVIEW_LINES + (DIALOG_MORE,)))
    with pytest.raises(PhysicalDesktopAcceptanceError, match="before the review was read"):
        journey_at(AgentAloneJourney.REVIEW).after_present(REVIEW_OFFER, 9, early, sender)
    swapped = _agent_review_frame(_agent_review(buttons=(("Approve once", "F7"), ("Deny", "F6"))))
    with pytest.raises(PhysicalDesktopAcceptanceError, match="offers"):
        journey_at(AgentAloneJourney.REVIEW).after_present(REVIEW_OFFER, 9, swapped, sender)
    loose = _agent_review_frame(_agent_review(modal=False))
    with pytest.raises(PhysicalDesktopAcceptanceError, match="not modal"):
        journey_at(AgentAloneJourney.REVIEW).after_present(REVIEW_OFFER, 9, loose, sender)
    active = replace(_agent_frame(menus=(AGENT_MENU_SIGNATURE,)),
                     semantic_dialog_claims=(_agent_review(),))
    with pytest.raises(PhysicalDesktopAcceptanceError, match="active"):
        journey_at(AgentAloneJourney.REVIEW).after_present(REVIEW_OFFER, 9, active, sender)


def test_agent_alone_refuses_a_desk_prompt_that_is_not_modal_for_all_of_desk() -> None:
    """Desk's prompt takes the whole taskbar row with no taskbar beside it,
    holds every control beneath it inactive, keeps the Agent rich, opens
    only when asked, and shows what was typed into it."""

    def sender(*_args):
        raise AssertionError("no input may be sent")

    def journey_at(stage: int) -> AgentAloneJourney:
        journey = AgentAloneJourney(("Agent",))
        journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
        journey.stage = stage
        journey._end_row = STORED_END
        return journey

    offer = _agent_offer(agent_transcript.LAST)
    opened = _desk_prompt_frame("")
    with pytest.raises(PhysicalDesktopAcceptanceError, match="beneath it active"):
        journey_at(AgentAloneJourney.DESK_PROMPT).after_present(
            offer, 9, replace(opened, inactive_controls=frozenset()), sender)
    bar = acceptance_runner._SemanticTaskBarClaim(
        ControlIdentity(1, 1, 30_200), ControlState.VISIBLE | ControlState.ENABLED,
        acceptance_runner._LogicalRectangle(0, ROWS - 1, 10, ROWS), ())
    with pytest.raises(PhysicalDesktopAcceptanceError, match="taskbar beside it"):
        journey_at(AgentAloneJourney.DESK_PROMPT).after_present(
            offer, 9, replace(opened, semantic_taskbar_claims=(bar,)), sender)
    narrow = replace(opened, semantic_field_claims=tuple(
        replace(claim, right=COLS - 1) for claim in opened.semantic_field_claims))
    with pytest.raises(PhysicalDesktopAcceptanceError, match="whole taskbar row"):
        journey_at(AgentAloneJourney.DESK_PROMPT).after_present(offer, 9, narrow, sender)
    withheld = replace(opened, semantic_item_view_claims=())
    with pytest.raises(PhysicalDesktopAcceptanceError, match="withheld the Agent"):
        journey_at(AgentAloneJourney.DESK_PROMPT).after_present(offer, 9, withheld, sender)
    with pytest.raises(PhysicalDesktopAcceptanceError, match="gave 'hellx'"):
        journey_at(AgentAloneJourney.DESK_TYPED).after_present(
            offer, 9, _desk_prompt_frame("hellx"), sender)
    # Desk's prompt opened unasked hides the taskbar: a lost focus.
    for stage in (AgentAloneJourney.ENDED, AgentAloneJourney.PROMPT):
        with pytest.raises(PhysicalDesktopAcceptanceError, match="lost focus"):
            journey_at(stage).after_present(offer, 9, opened, sender)


def test_every_single_applet_profile_has_a_journey() -> None:
    assert physical_desktop_acceptance.APPLETS == akashic_tui.DESKTOP_APT1_CHECKS
    for name in akashic_tui.DESKTOP_APT1_CHECKS:
        profile = akashic_tui.PROFILES[f"desktop-apt1-{name}"]
        journey = applet_journey(name, profile.ready_markers)
        assert journey.ready_markers == profile.ready_markers
        # Desk and the one applet, nothing else but the Agent's demo provider
        # and the device-flow fixture that gives it a catalog.
        # Observatory is checked beside Worlds, which hands it a run.
        applets = {"small-terminal": ("pad",), "photo": ("fexp",),
                   "damaged": ("fexp",),
                   "observatory": ("observatory", "worlds")}.get(name, (name,))
        provider = (
            (akashic_tui._DESK_AGENT_PROVIDER, akashic_tui._DAYBOOK_AGENT_DEVFLOW)
            if name == "agent" else ()
        )
        assert profile.roots == (
            "tui/desk-apt1.f",
            *(akashic_tui.desk_applet(applet).module for applet in applets),
            *provider,
        )
    assert akashic_tui._DAYBOOK_AGENT_SOURCE_BOOT in (
        akashic_tui.PROFILES["desktop-apt1-agent"].autoexec
    )


def test_daybook_alone_boots_the_reminder_its_journey_waits_for() -> None:
    assert DAYBOOK_REMINDER_NOTICE == f"Reminder: {akashic_tui.DAYBOOK_REMINDER_TITLE}"
    setup = akashic_tui.daybook_reminder_setup(akashic_tui.DAYBOOK_APT1_REMINDER_DELAY_S)
    assert setup in akashic_tui.PROFILES["desktop-apt1-daybook"].autoexec
    assert f"DBSVC-NOW 1000 / {akashic_tui.DAYBOOK_APT1_REMINDER_DELAY_S} +" in setup


def test_the_small_terminal_differs_from_desk_with_pad_only_in_text_room() -> None:
    small = akashic_tui.PROFILES["desktop-apt1-small-terminal"]
    pad = akashic_tui.PROFILES["desktop-apt1-pad"]
    assert replace(small, rich_terminal=pad.rich_terminal) == pad
    policy = small.rich_terminal.retained_policy
    assert replace(policy, total_utf8_bytes=pad.rich_terminal.retained_policy.total_utf8_bytes) == (
        pad.rich_terminal.retained_policy
    )
    # Still a valid terminal: it holds at least one whole glyph run.
    assert policy.max_glyph_run_bytes <= policy.total_utf8_bytes
    assert policy.total_utf8_bytes < pad.rich_terminal.retained_policy.total_utf8_bytes


def _empty_frame(*placements):
    """A frame whose retained scene is empty, so the viewer shows CELL, with
    Pad focused in the taskbar and PLACEMENTS in CELL."""

    offer = _cell_offer(1, (*placements, (ROWS - 1, 0, "[1:Akashic Pa*]")))
    offer = replace(offer, retained=replace(offer.retained, regions=()))
    projection = acceptance_runner.reconstruct_retained_screen(
        offer, require_menu_bar=False, allow_empty=True
    )
    return offer, projection


def test_an_empty_retained_scene_is_rebuilt_only_when_a_journey_expects_it() -> None:
    offer, projection = _empty_frame((5, 3, SMALL_TERMINAL_LARGE_LINE))
    with pytest.raises(PhysicalDesktopAcceptanceError, match="one ordinary base region"):
        acceptance_runner.reconstruct_retained_screen(offer, require_menu_bar=False)
    assert projection.draw_count == 0
    assert projection.lines == tuple(offer.cell.lines())
    assert projection.find_cells(SMALL_TERMINAL_LARGE_LINE, 5, 0, COLS) == [3]
    assert not (projection.menu_signatures or projection.semantic_collection_claims)
    assert SmallTerminalJourney.allows_empty_retained_frames
    assert not PadAloneJourney.allows_empty_retained_frames
    assert not acceptance_runner.DesktopAcceptanceJourney.allows_empty_retained_frames


def test_small_terminal_shows_unfitting_screens_as_cell_and_returns_to_rich() -> None:
    journey = applet_journey("small-terminal", PAD_READY)
    assert isinstance(journey, SmallTerminalJourney)
    ready = (_cell_offer(1, ((2, 1, "Untitled"),)), _pad_frame("", (1, 0)))
    example = (
        _cell_offer(1, ((EDITOR_ROW, EDITOR_COL, styled_text.EXAMPLE_LINE),)),
        _pad_frame(styled_text.EXAMPLE_LINE, (1, 0)),
    )
    steps = (
        ready,
        # Ctrl+O has not reached Pad yet.
        ready,
        # The prompt over Pad's empty editor fits.
        (_pad_prompt_offer(), _pad_prompt_frame("")),
        (_pad_prompt_offer(SMALL_TERMINAL_LARGE_PATH),
         _pad_prompt_frame(SMALL_TERMINAL_LARGE_PATH)),
        _empty_frame((EDITOR_ROW, EDITOR_COL, SMALL_TERMINAL_LARGE_LINE)),
        _empty_frame((PROMPT_ROW, 1, "Open: ")),
        _empty_frame((PROMPT_ROW, 1, f"Open: {styled_text.EXAMPLE_PATH}")),
        # example.f is loading, still as CELL.
        _empty_frame((EDITOR_ROW, EDITOR_COL, styled_text.EXAMPLE_LINE)),
        example,
    )
    results = _run(journey, steps)
    assert [(result.milestone, sent) for result, sent in results] == [
        ("small-terminal-pad-rich", [("send_key", "ctrl+o")]),
        (None, []),
        ("small-terminal-prompt-shown-rich", [("send_text", SMALL_TERMINAL_LARGE_PATH)]),
        ("small-terminal-large-path-typed", [("send_key", "enter")]),
        ("small-terminal-large-file-shown-as-cell", [("send_key", "ctrl+o")]),
        ("small-terminal-prompt-shown-again", [("send_text", styled_text.EXAMPLE_PATH)]),
        ("small-terminal-example-path-typed", [("send_key", "enter")]),
        (None, []),
        ("small-terminal-rich-again", []),
    ]
    assert results[-1][0].complete
    assert journey.final_cell_markers == ("[1:Akashic Pa*]", styled_text.EXAMPLE_LINE)


def test_small_terminal_refuses_a_screen_that_fit_or_a_plain_start() -> None:
    def sender(*_args):
        raise AssertionError("no input may be sent")

    def journey_at(stage: int) -> SmallTerminalJourney:
        journey = SmallTerminalJourney(PAD_READY)
        journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
        journey.stage = stage
        return journey

    # The start must be rich, even when CELL shows all the ready markers.
    offer, empty = _empty_frame((0, 1, "File  Edit  Selection"), (2, 1, "Untitled"))
    with pytest.raises(PhysicalDesktopAcceptanceError, match="not shown rich"):
        journey_at(SmallTerminalJourney.READY).after_present(offer, 9, empty, sender)
    # The prompt over Pad's empty editor shown as CELL did not fit.
    offer, empty = _empty_frame((81, 1, "Open: "))
    with pytest.raises(PhysicalDesktopAcceptanceError, match="did not fit"):
        journey_at(SmallTerminalJourney.PROMPT).after_present(offer, 9, empty, sender)
    # A large file shown rich means the terminal held it.
    large = _pad_frame(SMALL_TERMINAL_LARGE_LINE, (1, 0))
    with pytest.raises(PhysicalDesktopAcceptanceError, match="fit the small terminal"):
        journey_at(SmallTerminalJourney.LARGE).after_present(
            _cell_offer(1, ((EDITOR_ROW, EDITOR_COL, SMALL_TERMINAL_LARGE_LINE),)),
            9, large, sender)


def test_frames_of_desk_with_one_applet_may_lack_a_menu_bar() -> None:
    # A frame of residual glyphs alone, as while a painted overlay, such as
    # the Agent's review, withholds the only applet's menu.
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


def test_daybook_alone_requires_the_notice_in_rich_and_cell() -> None:
    entry = mixed_text.DAYBOOK_ENTRY
    checked = _cell_offer(1, ((10, 28, "[x] " + mixed_text.visual(entry)),))
    journey = applet_journey("daybook", DAYBOOK_READY)
    journey.stage = DaybookAloneJourney.NOTICE_WAIT
    journey._lineage = journey._offer_lineage(checked, 9)

    def sender(*_):
        raise AssertionError("waiting for the notice sends nothing")

    # Only CELL shows the notice: the rich frame lacks it, so wait.
    offer = replace(_notice_offer(DAYBOOK_REMINDER_NOTICE), offer_id=1)
    frame = _daybook_frame(agenda=entry, checked=True)
    assert not journey.after_present(offer, 9, frame, sender).complete
    assert DAYBOOK_REMINDER_NOTICE in journey.waiting
    # The rich frame shows it but CELL does not.
    offer = replace(checked, offer_id=2)
    frame = _daybook_frame(agenda=entry, checked=True, notice=True)
    with pytest.raises(PhysicalDesktopAcceptanceError, match="CELL does not show"):
        journey.after_present(offer, 9, frame, sender)
    # A reminder is neutral; a notice of another meaning, modal, or off the
    # bottom row is not the reminder's.
    for notice, message in (
        (_notice(DAYBOOK_REMINDER_NOTICE, StatusSeverity.WARNING), "WARNING, not NEUTRAL"),
        (replace(_notice(DAYBOOK_REMINDER_NOTICE), modal=True), "not a plain notice"),
        (replace(_notice(DAYBOOK_REMINDER_NOTICE), top=ROWS - 2, bottom=ROWS - 1),
         "not on the bottom row"),
    ):
        offer = replace(_notice_offer(DAYBOOK_REMINDER_NOTICE), offer_id=3)
        frame = _noticed(_daybook_frame(agenda=entry, checked=True), notice)
        with pytest.raises(PhysicalDesktopAcceptanceError, match=message):
            journey.after_present(offer, 9, frame, sender)


def test_a_run_in_safe_mode_finds_its_notice_as_a_warning_in_rich_and_cell() -> None:
    frame = _pad_frame("", (1, 0))
    offer = _notice_offer(SAFE_MODE_BOOT_NOTICE)
    assert not _shows_safe_mode_notice(offer, frame)
    shown = _noticed(frame, _notice(SAFE_MODE_BOOT_NOTICE, StatusSeverity.WARNING))
    assert _shows_safe_mode_notice(offer, shown)
    with pytest.raises(PhysicalDesktopAcceptanceError, match="CELL does not show"):
        _shows_safe_mode_notice(_cell_offer(1, ()), shown)
    neutral = _noticed(frame, _notice(SAFE_MODE_BOOT_NOTICE))
    with pytest.raises(PhysicalDesktopAcceptanceError, match="NEUTRAL, not WARNING"):
        _shows_safe_mode_notice(offer, neutral)


FEXP_READY = ("Details", "Tools")


def _fexp_tree(expanded: bool):
    """File Explorer's folder tree: its root, and one folder once expanded."""

    root = SimpleNamespace(item_key=1, parent_key=0, state=ItemState.EXPANDABLE
                           | (ItemState.EXPANDED if expanded else ItemState(0)))
    folder = SimpleNamespace(item_key=2, parent_key=1, state=ItemState.EXPANDABLE)
    return SimpleNamespace(content=SimpleNamespace(items=(root, folder) if expanded else (root,)),
                           value=lambda key: f"item:{key}")


def _upload_status(begin=0, chunk=0, commit=0, abort=0, present=0) -> dict:
    """A status poll's frame counters for an upload beside the screen."""

    return {"rich_terminal": {"frames_by_type": {
        "0x1000": begin, "0x1001": chunk, "0x1002": commit, "0x000C": abort,
        "0x2001": present,
    }}}


class _UploadProbe:
    """Drive File Explorer's paced-link check through its first preview."""

    def __init__(self, monkeypatch):
        self.journey = FexpAloneJourney(FEXP_READY, paced_link=True)
        self.journey.stage = self.journey.PICTURE_PREVIEWED
        self.tree = _fexp_tree(False)
        self.sent = []
        self.offers = 0
        monkeypatch.setattr(FexpAloneJourney, "_tree",
                            staticmethod(lambda projection: self.tree))

    def frame(self, *, pictures=(), **counts):
        self.journey.observe_status(_upload_status(**counts))
        self.offers += 1

        def sender(method, value, offer, generation):
            self.sent.append((method, value))
            return "progress"

        return self.journey._probe_upload(
            SimpleNamespace(offer_id=self.offers, scope=None), 9, None, sender,
            list(pictures))


def test_fexp_on_a_paced_link_answers_input_while_its_picture_uploads(monkeypatch) -> None:
    probe = _UploadProbe(monkeypatch)
    journey = probe.journey
    # The picture is being prepared; nothing goes until its chunks do.  The
    # screen may not change meanwhile, so the runner shows the journey the
    # frame on screen after each status poll.
    assert journey.acts_between_frames
    assert probe.frame(present=40) == JourneyProgress()
    assert probe.frame(begin=1, present=40) == JourneyProgress()
    assert probe.sent == []
    assert probe.frame(begin=1, chunk=3, present=41).milestone == (
        "fexp-input-sent-during-upload")
    assert probe.sent == [("item_expand", "item:1")]
    assert not journey.acts_between_frames
    # A frame before the answer, then the answer while chunks still go.
    assert probe.frame(begin=1, chunk=6, present=42) == JourneyProgress()
    probe.tree = _fexp_tree(True)
    assert probe.frame(begin=1, chunk=9, present=43).milestone == (
        "fexp-input-answered-during-upload")
    assert journey.frame_barrier == probe.offers
    assert probe.frame(begin=1, chunk=12, present=43) == JourneyProgress()
    assert probe.frame(begin=1, chunk=20, commit=1, present=45,
                       pictures=("sunset",)).milestone == "fexp-picture-shown-after-input"
    assert probe.sent[-1] == ("item_collapse", "item:1")
    assert probe.frame(begin=1, chunk=20, commit=1, present=45,
                       pictures=("sunset",)) == JourneyProgress()
    probe.tree = _fexp_tree(False)
    assert probe.frame(begin=1, chunk=20, commit=1, present=46, pictures=("sunset",)) is None
    assert journey.evidence == {"paced_upload": {
        "sent": dict(resource_begin=1, resource_chunk=3, resource_commit=0,
                     resource_abort=0, present_commit=41),
        "answered": dict(resource_begin=1, resource_chunk=9, resource_commit=0,
                         resource_abort=0, present_commit=43),
        "shown": dict(resource_begin=1, resource_chunk=20, resource_commit=1,
                      resource_abort=0, present_commit=45),
    }}


@pytest.mark.parametrize(("answer", "pictures", "message"), (
    (dict(chunk=20, commit=1, present=45), (), "arrived before the frame answering"),
    (dict(chunk=9, present=43), ("sunset",), "arrived before the frame answering"),
    (dict(chunk=9, abort=1, present=43), (), "upload stopped"),
    (dict(chunk=9, present=41), (), "committed no frame"),
))
def test_fexp_on_a_paced_link_refuses_an_answer_that_waited(
    monkeypatch, answer, pictures, message
) -> None:
    probe = _UploadProbe(monkeypatch)
    probe.frame(begin=1, chunk=3, present=41)
    probe.tree = _fexp_tree(True)
    with pytest.raises(PhysicalDesktopAcceptanceError, match=message):
        probe.frame(begin=1, pictures=pictures, **answer)


def test_fexp_on_a_paced_link_needs_the_upload_to_outlast_the_input(monkeypatch) -> None:
    probe = _UploadProbe(monkeypatch)
    with pytest.raises(PhysicalDesktopAcceptanceError, match="too fast"):
        probe.frame(begin=1, chunk=20, commit=1, present=45, pictures=("sunset",))
    probe = _UploadProbe(monkeypatch)
    probe.frame(begin=1, chunk=3, present=41)
    probe.tree = _fexp_tree(True)
    probe.frame(begin=1, chunk=9, present=43)
    with pytest.raises(PhysicalDesktopAcceptanceError, match="no chunk"):
        probe.frame(begin=1, chunk=9, commit=1, present=45, pictures=("sunset",))


def test_only_a_paced_link_checks_an_upload() -> None:
    plain = applet_journey("fexp", FEXP_READY)
    assert plain._probe is None and plain.evidence is None
    plain.stage = plain.PICTURE_PREVIEWED
    assert not plain.acts_between_frames
    paced = applet_journey("fexp", FEXP_READY, paced_link=True)
    assert paced._probe == "pending" and paced.evidence == {"paced_upload": {}}
    # The other journeys run unchanged on a paced link.
    assert applet_journey("pad", PAD_READY, paced_link=True).evidence is None


def _photo_frame(width, height, *, resource=7):
    """A frame offer carrying one picture resource of WIDTH by HEIGHT."""

    manifest = SimpleNamespace(owner_id=1, owner_generation=2, resource_id=resource,
                               width=width, height=height, byte_length=width * height * 4)
    return SimpleNamespace(retained=SimpleNamespace(resources=(manifest,)))


# File Explorer's preview at its largest: 195 by 78 cells of 11 by 21 pixels.
_PHOTO_SHOWN = SimpleNamespace(left=85, top=3, right=280, bottom=81, owner_id=1,
                               owner_generation=2, resource_id=7)


def test_the_photo_check_needs_the_photo_itself() -> None:
    """The terminal decodes QOI, so it holds the whole photo, decoded from
    the file, and fits it into the preview itself."""

    assert (FEXP_PHOTO, FEXP_PHOTO_SIZE) == (
        akashic_tui.SAMPLE_PHOTO_NAME, akashic_tui.SAMPLE_PHOTO_SIZE)
    width, height = FEXP_PHOTO_SIZE
    assert FEXP_PHOTO_FACTS == f"QOI, {width} \u00d7 {height}"
    journey = PhotoJourney(("Details", "Tools"))
    with pytest.raises(PhysicalDesktopAcceptanceError, match="cell size"):
        journey._require_photo_itself(_photo_frame(2160, 1620), _PHOTO_SHOWN)
    journey.cell_pixels = (11, 21)
    journey._require_photo_itself(_photo_frame(2160, 1620), _PHOTO_SHOWN)
    assert journey.evidence == {"photo": {
        "photo_pixels": [2160, 1620], "area_cells": [195, 78], "cell_pixels": [11, 21],
        "area_pixels": [2145, 1638], "held_pixels": [2160, 1620],
        "held_bytes": 2160 * 1620 * 4,
    }}
    # A copy made for the area, of any size, is not the photo itself.
    for width, height in ((2145, 1609), (160, 120), (1080, 810)):
        with pytest.raises(PhysicalDesktopAcceptanceError, match="not the photo itself"):
            journey._require_photo_itself(_photo_frame(width, height), _PHOTO_SHOWN)
    with pytest.raises(PhysicalDesktopAcceptanceError, match="does not carry"):
        journey._require_photo_itself(_photo_frame(2160, 1620, resource=8), _PHOTO_SHOWN)


def test_the_damaged_check_needs_one_upload_the_terminal_answered() -> None:
    """The damaged file goes to the terminal once: one upload begun, sent and
    committed, which the terminal refused, and none after it."""

    journey = DamagedPictureJourney(FEXP_READY)
    journey.observe_status(_upload_status(begin=2, chunk=5, commit=2, present=30))
    journey._before = dict(journey._frames)
    journey.observe_status(_upload_status(begin=3, chunk=6, commit=2, present=31))
    assert journey._sent_once() is None
    journey.observe_status(_upload_status(begin=3, chunk=6, commit=3, present=32))
    assert journey._sent_once() == dict(resource_begin=1, resource_chunk=1,
                                        resource_commit=1, resource_abort=0)
    # Sent again, stopped, or answered with nothing sent: not one upload.
    for counts in (dict(begin=4, chunk=7, commit=4), dict(begin=3, chunk=6, abort=1, commit=2),
                   dict(begin=2, chunk=5, commit=3)):
        journey.observe_status(_upload_status(present=33, **counts))
        with pytest.raises(PhysicalDesktopAcceptanceError, match="not as one upload"):
            journey._sent_once()


TABLE_ID, TREE_ID = 31_000, 31_001


def _fexp_frame(selected: str = "large.txt", *, status: bool = True, rename: str | None = None,
                caret: int | None = None, anchor: int | None = None, delete: bool = False,
                goto: str | None = None, warned: bool = False, listed: str = "large.txt",
                renamed: bool = False):
    """Desk with File Explorer: its detail table listing LISTED and the
    sample picture with SELECTED selected, its folder tree, its menu bar,
    and the selected path in its status bar; with RENAME, the rename prompt
    holding it over the tile, with GOTO, the Go to prompt holding it, with
    DELETE, its delete question, with WARNED, its warning that the path
    was not found, and with RENAMED, its notice that the file was
    renamed."""

    rows = {0: " File  Edit  View  Tools", ROWS - 1: "[1:File Explo*]"}
    if status:
        rows[81] = f" /{selected}"
    frame = _screen(rows, (acceptance_runner.FEXPLORER_MENU_SIGNATURE,))
    names = (listed, acceptance_runner.FEXPLORER_PICTURE)
    items = tuple(
        ViewItem(ordinal + 1, 0, ordinal, 0,
                 ItemState.SELECTED if name == selected else ItemState(0), ItemRole.ITEM,
                 (ItemField(name), ItemField("2K"), ItemField("file")))
        for ordinal, name in enumerate(names)
    )
    table = acceptance_runner._SemanticItemViewClaim(
        ControlIdentity(1, 1, TABLE_ID), 30, 2, COLS, 60,
        ItemViewContent(1, ItemViewRole.TABLE, ItemViewFlag(0),
                        (ItemColumn(ItemColumnKind.TEXT, "Name"),
                         ItemColumn(ItemColumnKind.NUMBER, "Size"),
                         ItemColumn(ItemColumnKind.TEXT, "Type")),
                        len(items), 0, len(items), items),
    )
    root = ViewItem(1, 0, 0, 0, ItemState.EXPANDABLE, ItemRole.ITEM, (ItemField("/"),))
    tree = acceptance_runner._SemanticItemViewClaim(
        ControlIdentity(1, 1, TREE_ID), 0, 2, 29, 60,
        ItemViewContent(1, ItemViewRole.TREE, ItemViewFlag(0),
                        (ItemColumn(ItemColumnKind.TEXT),), 1, 0, 1, (root,)),
    )
    frame = replace(frame, semantic_item_view_claims=(table, tree))
    if rename is not None:
        prompt = _prompt("Rename:", rename, row=81, caret=caret)
        if anchor is not None:
            prompt = replace(prompt, content=replace(prompt.content, anchor=anchor))
        frame = _held(frame, prompt)
    if goto is not None:
        frame = _held(frame, _prompt("Go to:", goto, row=81))
    if warned:
        frame = _noticed(frame, _notice("Path not found", StatusSeverity.WARNING))
    if renamed:
        frame = _noticed(frame, _notice("Renamed", StatusSeverity.NEUTRAL))
    if delete:
        # The question covers the detail table, which the capture withholds.
        frame = replace(frame, semantic_item_view_claims=(tree,))
        frame = _asked(frame, _question("Delete the selected item?", (
            ("Delete", ButtonFlag.DESTRUCTIVE),
            ("Cancel", ButtonFlag.DEFAULT | ButtonFlag.CANCEL),
        )))
    return frame


def test_fexp_alone_renames_through_its_prompt_and_cancels_its_delete_question() -> None:
    journey = FexpAloneJourney(FEXP_READY)
    journey.stage = FexpAloneJourney.FILE_SELECTED
    journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
    prompt_offer = _cell_offer(1, ((81, 1, "Rename: large.txt"),))
    question_offer = _cell_offer(1, ((32, 62, "Delete the selected item?"),))
    blank = _cell_offer(1, ())
    steps = (
        (blank, _fexp_frame()),
        (prompt_offer, _fexp_frame(status=False, rename="large.txt")),
        # The caret has not moved yet.
        (blank, _fexp_frame(status=False, rename="large.txt")),
        (blank, _fexp_frame(status=False, rename="large.txt", caret=0)),
        (blank, _fexp_frame(status=False, rename="large.txt", caret=5, anchor=0)),
        # The guest may paint between typed characters.
        (blank, _fexp_frame(status=False, rename="no.txt")),
        (blank, _fexp_frame(status=False, rename="notes.txt")),
        # Enter has not closed the prompt yet.
        (blank, _fexp_frame(status=False, rename="notes.txt")),
        # The file is renamed and selected, but the notice is not up yet.
        (blank, _fexp_frame("notes.txt", listed="notes.txt")),
        (_notice_offer("Renamed"), _fexp_frame("notes.txt", listed="notes.txt", renamed=True)),
        (question_offer, _fexp_frame("notes.txt", listed="notes.txt", delete=True)),
        # Cancel has not closed the question yet.
        (question_offer, _fexp_frame("notes.txt", listed="notes.txt", delete=True)),
        (blank, _fexp_frame("notes.txt", listed="notes.txt")),
        (blank, _fexp_frame(status=False, goto="/", listed="notes.txt")),
        # The guest may paint between typed characters.
        (blank, _fexp_frame(status=False, goto="/no-such", listed="notes.txt")),
        (blank, _fexp_frame(status=False, goto="/no-such-folder", listed="notes.txt")),
        # Enter has closed the prompt, and the warning is not up yet.
        (blank, _fexp_frame("notes.txt", listed="notes.txt")),
        (_notice_offer("Path not found"),
         _fexp_frame("notes.txt", listed="notes.txt", warned=True)),
    )
    results = _run(journey, steps)
    value = f"1,1,{PROMPT_ID},0,{{}}".format
    assert [(result.milestone, sent) for result, sent in results] == [
        ("fexp-file-selected", [("send_key", "f2")]),
        ("fexp-rename-prompt-opened", [("text_place", value(0))]),
        (None, []),
        ("fexp-rename-caret-placed", [("text_extend", value(5))]),
        ("fexp-rename-stem-selected", [("send_text", "notes")]),
        (None, []),
        ("fexp-rename-stem-replaced", [("send_key", "enter")]),
        (None, []),
        (None, []),
        ("fexp-renamed", [("send_key", "delete")]),
        ("fexp-delete-question-shown", [("activate_button", f"1,1,{PROMPT_ID + 2}")]),
        (None, []),
        ("fexp-delete-cancelled", [("send_key", "ctrl+g")]),
        ("fexp-goto-opened", [("send_text", "no-such-folder")]),
        (None, []),
        ("fexp-goto-typed", [("send_key", "enter")]),
        (None, []),
        ("fexp-goto-warned", [("item_select", f"1,1,{TABLE_ID},2")]),
    ]
    assert journey.stage == FexpAloneJourney.PICTURE_SELECTED


def test_fexp_alone_retries_its_step_after_a_warning_that_has_ended() -> None:
    """The warning lasts two seconds: input refused for backpressure is sent
    again on a later frame, once the warning has gone."""

    journey = FexpAloneJourney(FEXP_READY)
    journey.stage = FexpAloneJourney.GOTO_WARNED
    journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
    statuses = iter(("backpressured", "progress"))
    sent = []

    def sender(method, value, *_):
        sent.append((method, value))
        return next(statuses)

    offer = replace(_notice_offer("Path not found"), offer_id=1)
    journey.after_present(offer, 9, _fexp_frame("notes.txt", listed="notes.txt", warned=True),
                          sender)
    assert journey.stage == FexpAloneJourney.GOTO_WARNED
    offer = replace(_cell_offer(1, ()), offer_id=2)
    journey.after_present(offer, 9, _fexp_frame("notes.txt", listed="notes.txt"), sender)
    assert sent == [("item_select", f"1,1,{TABLE_ID},2")] * 2
    assert journey.stage == FexpAloneJourney.PICTURE_SELECTED


def test_fexp_alone_refuses_a_rename_that_held_the_wrong_span_or_left_the_table_active() -> None:
    def sender(*_args):
        raise AssertionError("no input may be sent")

    def journey_at(stage):
        journey = FexpAloneJourney(FEXP_READY)
        journey.stage = stage
        journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
        return journey

    with pytest.raises(PhysicalDesktopAcceptanceError, match="gave 'noteslarge.txt'"):
        journey_at(FexpAloneJourney.RENAME_TYPED).after_present(
            _cell_offer(1, ()), 9, _fexp_frame(status=False, rename="noteslarge.txt"), sender)
    active = replace(_fexp_frame(status=False, rename="large.txt"),
                     inactive_controls=frozenset())
    with pytest.raises(PhysicalDesktopAcceptanceError, match="beneath it active"):
        journey_at(FexpAloneJourney.RENAME_PROMPT).after_present(
            _cell_offer(1, ((81, 1, "Rename: large.txt"),)), 9, active, sender)
    # The delete question, likewise, holds the table and tree beneath it.
    asked = replace(_fexp_frame(delete=True), inactive_controls=frozenset())
    with pytest.raises(PhysicalDesktopAcceptanceError, match="beneath it active"):
        journey_at(FexpAloneJourney.DELETE_ASKED).after_present(
            _cell_offer(1, ((32, 62, "Delete the selected item?"),)), 9, asked, sender)


def _launcher(*, modal=True, lines=None, inactive=False, beneath=True, shell=True):
    """Desk's launcher: its dialog titled Applets around its two-column list,
    in the shell's frame, File Explorer's pane and the taskbar inactive
    beneath it, unless BENEATH leaves File Explorer's menu bar active."""

    message = "\n".join(lines or ("select an applet",
                                  "Up/Down PgUp/PgDn Home/End  Enter open  Esc close"))
    rows = message.count("\n") + 1
    content = DialogContent(1, DialogFlag(0), 0, FieldRect(2, 0, 7, 1),
                            FieldRect(1, 1, 50, rows), message=message)
    dialog = acceptance_runner._SemanticDialogClaim(
        ControlIdentity(1, 1, 50_000), 20, 10, 88, 24, "Applets",
        ControlState.VISIBLE, content, modal=modal)
    items = (ViewItem(1, 0, 0, 0, ItemState.SELECTED, ItemRole.ITEM,
                      (ItemField("File Explorer"), ItemField("running"))),)
    view = acceptance_runner._SemanticItemViewClaim(
        ControlIdentity(1, 1, 50_001), 21, 13, 87, 23,
        ItemViewContent(1, ItemViewRole.LIST, ItemViewFlag(0),
                        (ItemColumn(ItemColumnKind.TEXT), ItemColumn(ItemColumnKind.TEXT)),
                        len(items), 0, len(items), items))
    pane = acceptance_runner._SemanticPaneClaim(
        1, 1, 40_000, 1, 2, acceptance_runner._LogicalRectangle(0, 0, COLS, ROWS - 1),
        acceptance_runner._LogicalRectangle(0, 0, COLS, ROWS - 1), "File Explorer", True)
    bar = acceptance_runner._SemanticTaskBarClaim(
        ControlIdentity(1, 1, 30_200), ControlState.VISIBLE,
        acceptance_runner._LogicalRectangle(0, ROWS - 1, 10, ROWS), ())
    projection = _screen({ROWS - 1: "[1:File Explo*]"},
                         (acceptance_runner.FEXPLORER_MENU_SIGNATURE,))
    held = {bar.identity} | ({projection.menu_bar_identities[0]} if beneath else set())
    projection = replace(
        projection,
        semantic_dialog_claims=(dialog,), semantic_item_view_claims=(view,),
        semantic_pane_claims=(pane,) if shell else (),
        semantic_taskbar_claims=(bar,) if shell else (),
        inactive_controls=frozenset(held | ({view.identity} if inactive else set())),
    )
    return projection, view


def test_the_launcher_is_a_modal_dialog_around_its_list() -> None:
    projection, view = _launcher()
    assert _require_desk_launcher_dialog(projection, view).title == "Applets"


@pytest.mark.parametrize("kwargs,message", (
    ({"modal": False}, "not modal"),
    ({"lines": ("select an applet",)}, "launcher says"),
    ({"inactive": True}, "is inactive"),
    ({"beneath": False}, "1 controls beneath it active"),
    ({"shell": False}, "without the shell"),
))
def test_the_launcher_check_refuses_a_launcher_that_is_not_that(kwargs, message) -> None:
    projection, view = _launcher(**kwargs)
    with pytest.raises(PhysicalDesktopAcceptanceError, match=message):
        _require_desk_launcher_dialog(projection, view)


def test_agent_alone_refuses_a_long_review_that_fits_or_unlocks_early() -> None:
    """The long review must be taller than its dialog, so the wheel has
    something to scroll, and Approve once must wait for its end."""

    def sender(*_args):
        raise AssertionError("no input may be sent")

    def journey_at(stage: int) -> AgentAloneJourney:
        journey = AgentAloneJourney(("Agent",))
        journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
        journey.stage = stage
        return journey

    fits = _agent_review_frame(_agent_review(("AGENT",) + LONG_END))
    with pytest.raises(PhysicalDesktopAcceptanceError, match="nothing to scroll"):
        journey_at(AgentAloneJourney.LONG_REVIEW).after_present(REVIEW_OFFER, 9, fits, sender)
    early = _agent_review_frame(_agent_review(LONG_TOP + (DIALOG_MORE,)))
    with pytest.raises(PhysicalDesktopAcceptanceError, match="before the long review"):
        journey_at(AgentAloneJourney.LONG_REVIEW).after_present(REVIEW_OFFER, 9, early, sender)
    elsewhere = _agent_review_frame(_agent_review(LONG_MIDDLE + (DIALOG_MORE,), approve=False))
    with pytest.raises(PhysicalDesktopAcceptanceError, match="does not open at its reason"):
        journey_at(AgentAloneJourney.LONG_REVIEW).after_present(
            REVIEW_OFFER, 9, elsewhere, sender)



# Sound Lab alone: its landmark line across row 60, columns 4 to 90.
SOUNDLAB_READY = ("SOUND LAB", "Waveform")
LANDMARK_ROW, LANDMARK_LEFT, LANDMARK_RIGHT = 60, 4, 90


def _landmarks(frequency: int):
    half, one = 0x7FFFFFFF, 0xFFFFFFFF
    pitch = LANDMARK_LEFT + frequency * (LANDMARK_RIGHT - LANDMARK_LEFT - 1) // 4000

    def line(identity, column, width, color, points):
        return acceptance_runner._InstrumentClaim(
            "POLYLINE", 1, 1, identity, column, LANDMARK_ROW, column + width,
            LANDMARK_ROW + 1, color, points)

    return pitch, (
        line(60_050, LANDMARK_LEFT, LANDMARK_RIGHT - LANDMARK_LEFT,
             (0x80, 0x80, 0x80, 0xFF), ((0, half), (one, half))),
        line(60_051, pitch, 1, (0x5F, 0xD7, 0xFF, 0xFF), ((half, 0), (half, one))),
        line(60_052, pitch + 3, 1, (0xFF, 0xD7, 0x00, 0xFF), ((half, 0), (half, one))),
    )


def _soundlab_frame(frequency: int, *, shown=True, prompt=None):
    rows = {1: "  SOUND LAB", 3: "  Waveform", ROWS - 1: "[1:Sound Lab*]"}
    frame = replace(_screen(rows, ()),
                    semantic_field_claims=_soundlab_field_claims(frequency),
                    instrument_claims=_landmarks(frequency)[1] if shown else ())
    return _held(frame, prompt) if prompt else frame


def _soundlab_cells(frequency: int):
    pitch = _landmarks(frequency)[0]
    drawn = ["─"] * (LANDMARK_RIGHT - LANDMARK_LEFT)
    for column in (pitch, pitch + 3):
        drawn[column - LANDMARK_LEFT] = "│"
    return _cell_offer(1, (
        (LANDMARK_ROW - 2, LANDMARK_LEFT, acceptance_runner.SOUNDLAB_LANDMARK_CAPTION),
        (LANDMARK_ROW - 1, pitch, "P"), (LANDMARK_ROW - 1, pitch + 3, "C"),
        (LANDMARK_ROW, LANDMARK_LEFT, "".join(drawn)),
    ))


def _frequency_prompt(typed: str, *, anchor: int = 0):
    prompt = _prompt(acceptance_runner.SOUNDLAB_FREQUENCY_PROMPT, typed, row=ROWS - 3)
    return replace(prompt, content=replace(prompt.content, anchor=anchor))


def test_soundlab_alone_moves_its_pitch_mark_with_a_new_render() -> None:
    journey = applet_journey("soundlab", SOUNDLAB_READY)
    assert isinstance(journey, SoundLabAloneJourney)
    before, after = _soundlab_cells(440), _soundlab_cells(880)
    held = _soundlab_cells(440)
    steps = (
        (before, _soundlab_frame(440)),
        (held, _soundlab_frame(440, prompt=_frequency_prompt("440", anchor=3))),
        (held, _soundlab_frame(440, prompt=_frequency_prompt("440"))),
        (held, _soundlab_frame(440, prompt=_frequency_prompt("880", anchor=3))),
        # The new setting leaves the analysis stale: no landmarks.
        (held, _soundlab_frame(880, shown=False)),
        (held, _soundlab_frame(880, shown=False)),
        (after, _soundlab_frame(880)),
    )
    results = _run(journey, steps)
    assert [(result.milestone, sent) for result, sent in results] == [
        ("soundlab-landmarks-shown", [("field_activate", f"1,1,{SOUNDLAB_FIELD_ID + 1}")]),
        ("soundlab-frequency-prompt", [("send_key", "ctrl+a")]),
        ("soundlab-frequency-selected", [("send_text", "880")]),
        ("soundlab-frequency-typed", [("send_key", "enter")]),
        ("soundlab-frequency-set", [("send_key", "f5")]),
        (None, []),
        ("soundlab-landmarks-moved", []),
    ]
    assert results[-1][0].complete


def test_soundlab_alone_refuses_cell_that_draws_its_marks_elsewhere() -> None:
    journey = applet_journey("soundlab", SOUNDLAB_READY)
    with pytest.raises(PhysicalDesktopAcceptanceError, match="name Sound Lab's mark"):
        _run(journey, ((_soundlab_cells(880), _soundlab_frame(440)),))


def _observatory_offer(samples, *, table=None, baseline_row=None, offer_id=1):
    """Desk with Observatory on the left: its plot over SAMPLES from row 20,
    its baseline along the row below, and its table listing TABLE."""

    from rich_terminal.retained_scene import ObjectBounds, RGBA, Sample
    from rich_terminal.retained_view import (
        PlotDraw, PolylineDraw, RetainedDrawPlane, RetainedRegionDraw,
        SeriesHistoryDraw, TextGridDraw,
    )

    offer = _cell_offer(offer_id, ((19, 2, "Upper amount projection"),))
    values = [value for _, value in samples]
    low, high = min(values), max(values)
    plot = PlotDraw(70_001, 0, ObjectBounds(2, 20, 70, 10), 1, low, high,
                    RGBA(0x5F, 0xD7, 0xFF, 0xFF), RGBA(0, 0, 0, 0), False,
                    len(samples) <= 70)
    line = PolylineDraw(70_002, 0, ObjectBounds(2, 30 if baseline_row is None else baseline_row,
                                                70, 1),
                        (acceptance_runner_point(0, 0x7FFFFFFF),
                         acceptance_runner_point(0xFFFFFFFF, 0x7FFFFFFF)),
                        0x20000000, RGBA(0x4E, 0x4E, 0x4E, 0xFF), False)
    shown = samples if table is None else table
    items = [SemanticTextItem(1, 0, 0, 1, 1, SemanticTextRole.COLUMN_HEADER,
                              SemanticTextState(0), "tick"),
             SemanticTextItem(2, 0, 1, 1, 1, SemanticTextRole.COLUMN_HEADER,
                              SemanticTextState(0), "upper amount")]
    for index, (tick, value) in enumerate(shown):
        items += [SemanticTextItem(10 + 2 * index, index + 1, 0, 1, 1,
                                   SemanticTextRole.ROW_HEADER, SemanticTextState(0), str(tick)),
                  SemanticTextItem(11 + 2 * index, index + 1, 1, 1, 1,
                                   SemanticTextRole.CONTENT, SemanticTextState(0), str(value))]
    content = SemanticTextContent(1, len(shown) + 1, 2, 0, 0, len(shown) + 1, 2,
                                  SemanticContentFlag(0), 0, 0, 0, 0, tuple(items))
    grid = TextGridDraw(70_003, ControlState.VISIBLE | ControlState.ENABLED, 0, 0,
                        ObjectBounds(2, 12, 40, 6), content)
    region = RetainedRegionDraw(1, 1, 2, 0, 0, 139, 83, 0, 0, 139, 83, 1, True,
                                (plot, line, grid))
    history = SeriesHistoryDraw(1, 1, 1, tuple(Sample(tick, value) for tick, value in samples))
    return replace(offer, retained=RetainedDrawPlane(
        True, True, offer.retained.regions + (region,), (history,)))


def acceptance_runner_point(x, y):
    from rich_terminal.retained_scene import Point
    return Point(x, y)


def test_observatory_plot_is_its_series_and_its_table_lists_the_same_samples() -> None:
    from rich_terminal_applet_journeys import _observatory_plot, _observatory_table

    bounds = (0, 0, 139, 83)
    offer = _observatory_offer(OBSERVATORY_DEMO_SERIES)
    plot, samples = _observatory_plot(offer, bounds)
    assert samples == OBSERVATORY_DEMO_SERIES
    assert (plot.left, plot.top, plot.right, plot.bottom) == (2, 20, 72, 30)
    assert _observatory_table(offer, bounds) == OBSERVATORY_DEMO_SERIES
    with pytest.raises(PhysicalDesktopAcceptanceError, match="baseline"):
        _observatory_plot(_observatory_offer(OBSERVATORY_DEMO_SERIES, baseline_row=31), bounds)


OBSERVATORY_READY = ("OBSERVATORY / SERIES PROFILE", "WORLDS / RESERVOIR FACILITY")
TELEMETRY = ((0, 9000), (1, 8750), (2, 8500), (3, 8250))


def _observatory_frame(focus: str, status: str = "Profiled 8 samples"):
    rows = {0: "  OBSERVATORY / SERIES PROFILE".ljust(140) + "  WORLDS / RESERVOIR FACILITY",
            ROWS - 3: "  " + status,
            ROWS - 1: f"[1:Observator{'*' if focus == 'observatory' else ''}] "
                      f"[2:Worlds{'*' if focus == 'worlds' else ''}]"}
    return _screen(rows, ())


def test_observatory_plots_its_series_then_worlds_telemetry_and_keeps_it_on_rerun() -> None:
    journey = applet_journey("observatory", OBSERVATORY_READY)
    assert isinstance(journey, ObservatoryJourney)
    demo = _observatory_offer(OBSERVATORY_DEMO_SERIES)
    telemetry = _observatory_offer(TELEMETRY)
    steps = (
        (demo, _observatory_frame("observatory")),
        # Focus has not moved yet.
        (demo, _observatory_frame("observatory")),
        (demo, _observatory_frame("worlds")),
        (demo, _observatory_frame("worlds")),
        (demo, _observatory_frame("worlds")),
        (demo, _observatory_frame("worlds")),
        # Desk brings Observatory forward before it has taken the run.
        (demo, _observatory_frame("observatory")),
        (telemetry, _observatory_frame("observatory", "Profiled 4 samples")),
        (telemetry, _observatory_frame("observatory", "Profiled 4 samples")),
    )
    results = _run(journey, steps)
    assert [(result.milestone, sent) for result, sent in results] == [
        ("observatory-plot-shown", [("send_key", "alt+2")]),
        (None, []),
        ("worlds-step-1", [("send_key", "s")]),
        ("worlds-step-2", [("send_key", "s")]),
        ("worlds-step-3", [("send_key", "s")]),
        ("worlds-analyze", [("send_key", "a")]),
        (None, []),
        ("observatory-plots-telemetry", [("send_key", "r")]),
        ("observatory-rerun-kept-plot", []),
    ]
    assert results[-1][0].complete


def test_observatory_takes_focus_back_when_worlds_keeps_it_after_analyze() -> None:
    journey = ObservatoryJourney(OBSERVATORY_READY)
    journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
    journey.stage = ObservatoryJourney.ANALYZE
    telemetry = _observatory_offer(TELEMETRY)
    steps = (
        (telemetry, _observatory_frame("worlds", "Profiled 4 samples")),
        (telemetry, _observatory_frame("observatory", "Profiled 4 samples")),
    )
    results = _run(journey, steps)
    assert [(result.milestone, sent) for result, sent in results] == [
        ("observatory-plots-telemetry", [("send_key", "alt+1")]),
        ("observatory-rerun", [("send_key", "r")]),
    ]


def test_observatory_counts_a_worlds_step_only_once_its_press_is_delivered() -> None:
    """A press refused for backpressure, then dropped for a newer frame, is
    sent again under the same milestone, so Worlds steps three times."""

    journey = ObservatoryJourney(OBSERVATORY_READY)
    journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
    journey.stage = ObservatoryJourney.WORLDS
    statuses = iter(("progress", "backpressured", "progress", "progress", "progress"))
    sent = []

    def sender(method, value, *_):
        sent.append((method, value))
        return next(statuses)

    milestones = [
        journey.after_present(_observatory_offer(OBSERVATORY_DEMO_SERIES, offer_id=offer_id),
                              9, _observatory_frame("worlds"), sender).milestone
        for offer_id in range(1, 6)
    ]
    assert milestones == ["worlds-step-1", "worlds-step-2", "worlds-step-2",
                          "worlds-step-3", "worlds-analyze"]
    assert sent == [("send_key", "s")] * 4 + [("send_key", "a")]
    assert journey.stage == ObservatoryJourney.ANALYZE


def test_observatory_refuses_a_handover_whose_status_lags_its_plot() -> None:
    journey = ObservatoryJourney(OBSERVATORY_READY)
    journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
    journey.stage = ObservatoryJourney.ANALYZE
    with pytest.raises(PhysicalDesktopAcceptanceError, match="lacks 'Profiled 4 samples'"):
        _run(journey, ((_observatory_offer(TELEMETRY), _observatory_frame("observatory")),))


def test_observatory_refuses_a_handover_without_a_sample_for_each_step() -> None:
    journey = ObservatoryJourney(OBSERVATORY_READY)
    journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
    journey.stage = ObservatoryJourney.ANALYZE
    with pytest.raises(PhysicalDesktopAcceptanceError, match="3 samples after 3 steps"):
        _run(journey, ((_observatory_offer(TELEMETRY[:3]),
                        _observatory_frame("observatory", "Profiled 3 samples")),))


def test_observatory_refuses_a_plot_whose_table_lists_other_samples() -> None:
    journey = applet_journey("observatory", OBSERVATORY_READY)
    offer = _observatory_offer(OBSERVATORY_DEMO_SERIES, table=TELEMETRY)
    with pytest.raises(PhysicalDesktopAcceptanceError, match="other samples than its table"):
        _run(journey, ((offer, _observatory_frame("observatory")),))
