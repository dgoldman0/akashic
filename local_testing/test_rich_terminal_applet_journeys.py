"""The journeys for Desk with a single applet, over synthetic frames.

Desk with one applet gives it the whole content area above the taskbar and
its taskbar button is slot 1.  Each test steps a journey through the frames
the physical runner would present and checks the one input each sends.
"""

from __future__ import annotations

from dataclasses import replace

import pytest

import akashic_tui  # noqa: F401  Ensures the selected MegaPad tree is importable.
import agent_transcript
import mixed_text
import physical_desktop_acceptance
import styled_text
import rich_terminal_desktop_acceptance as acceptance_runner
from rich_terminal import text_rules
from rich_terminal.pygame_view import ControlIdentity
from rich_terminal.retained_scene import ControlKind, ControlState
from rich_terminal.retained_view import MenuBarDraw
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
    AGENT_APPROVE_MARKER,
    AGENT_AUDIT,
    AGENT_EXCHANGE,
    AGENT_REQUEST,
    AGENT_REVIEW_MARKER,
    AGENT_REVIEW_REASON,
    STREAMS_CARDS,
    STREAMS_CONTEXT_MARKER,
    STREAMS_LINK,
    STREAMS_REPLY_TEXT,
    STREAMS_ROOT_TEXT,
    AgentAloneJourney,
    DaybookAloneJourney,
    PadAloneJourney,
    StreamsAloneJourney,
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
STREAMS_READY = ("STREAMS", "T thread")
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


def _pad_prompt_frame(typed: str):
    """Pad's Open prompt, which withholds its menu and text areas."""

    return _screen({81: f" Open: {typed}", ROWS - 1: "[1:Akashic Pa*]"}, ())


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
        # Ctrl+O opens the prompt, which withholds the editor.
        (blank, _pad_prompt_frame("")),
        (blank, _pad_prompt_frame(styled_text.NOTES_PATH)),
        (blank, _pad_prompt_frame(styled_text.NOTES_PATH)),
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
        ("pad-caret-placed-in-hebrew", [("send_key", "ctrl+o")]),
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
    journey._before = (1, 0)
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
    agenda: str | None = None,
    checked: bool = False,
):
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
        projection = replace(
            projection,
            semantic_item_view_claims=(_daybook_agenda(agenda, checked=checked),),
        )
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
        # The CHECK has not reached Daybook yet.
        (
            _cell_offer(1, ((10, 28, "[ ] " + mixed_text.visual(entry)),)),
            _daybook_frame(agenda=entry),
        ),
        (
            _cell_offer(1, ((10, 28, "[x] " + mixed_text.visual(entry)),)),
            _daybook_frame(agenda=entry, checked=True),
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
        ("daybook-mixed-task-added", [("item_check", f"1,1,{AGENDA_ID},16")]),
        (None, []),
        ("daybook-task-checked", []),
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
        ("streams-context-opened", []),
    ]
    assert results[-1][0].complete
    assert journey.final_cell_markers == (
        "[1:Streams*]", STREAMS_CONTEXT_MARKER, STREAMS_REPLY_TEXT
    )


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


def _agent_offer(last: str, *placements):
    """CELL with LAST on the transcript's last row, where card text starts."""

    return _cell_offer(1, ((AGENT_TOP + AGENT_BODY - 1, 3, last), *placements))


STORED = agent_transcript.CARDS
STORED_END = sum(_agent_rows(STORED)) - AGENT_BODY
APPROVED = STORED + AGENT_EXCHANGE
APPROVED_END = sum(_agent_rows(APPROVED)) - AGENT_BODY
REVIEW_ROWS = {
    30: "  " + AGENT_REVIEW_REASON,
    31: "  " + AGENT_REVIEW_MARKER,
    33: "  " + AGENT_APPROVE_MARKER + "  [F7] Deny",
}


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
    steps = (
        at_end,
        # The wheel has not reached the Agent yet.
        at_end,
        scrolled,
        at_end,
        (_agent_offer(""), _agent_frame(rows={82: " Ask: "})),
        (_agent_offer(""), _agent_frame(rows={82: f" Ask: {AGENT_REQUEST}"})),
        (_agent_offer("", (31, 2, AGENT_REVIEW_MARKER)), _agent_frame(rows=REVIEW_ROWS)),
        (
            _agent_offer(AGENT_AUDIT),
            _agent_frame(_agent_view(streaming, APPROVED_END, styled=False)),
        ),
        (_agent_offer(AGENT_AUDIT), _agent_frame(_agent_view(APPROVED, APPROVED_END))),
    )
    results = _run(journey, steps)
    assert [(result.milestone, sent) for result, sent in results] == [
        ("agent-transcript-at-end", [("item_scroll", f"1,1,{AGENT_VIEW_ID},-1")]),
        (None, []),
        ("agent-transcript-scrolled", [("send_key", "end")]),
        ("agent-transcript-end-again", [("send_key", "ctrl+l")]),
        ("agent-prompt-opened", [("send_text", AGENT_REQUEST)]),
        ("agent-request-typed", [("send_key", "enter")]),
        ("agent-review-unlocked", [("send_key", "f6")]),
        (None, []),
        ("agent-review-approved", []),
    ]
    assert results[-1][0].complete
    assert journey.final_cell_markers == ("[1:Agent*]", AGENT_AUDIT)


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
    leaked = _agent_frame(_agent_view(STORED, STORED_END), rows=REVIEW_ROWS)
    with pytest.raises(PhysicalDesktopAcceptanceError, match="did not withhold"):
        journey_at(AgentAloneJourney.REVIEW).after_present(offer, 9, leaked, sender)


def test_every_single_applet_profile_has_a_journey() -> None:
    assert physical_desktop_acceptance.APPLETS == akashic_tui.DESKTOP_APT1_APPLETS
    for name in akashic_tui.DESKTOP_APT1_APPLETS:
        profile = akashic_tui.PROFILES[f"desktop-apt1-{name}"]
        journey = applet_journey(name, profile.ready_markers)
        assert journey.ready_markers == profile.ready_markers
        # Desk and the one applet, nothing else but the Agent's demo provider.
        provider = (akashic_tui._DESK_AGENT_PROVIDER,) if name == "agent" else ()
        assert profile.roots == (
            "tui/desk-apt1.f", akashic_tui.desk_applet(name).module, *provider
        )


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
