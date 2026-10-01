"""Journeys for Desk with a single applet, through the physical viewer.

While an applet's work is under way, Desk runs with just that applet (the
desktop-apt1-<name> profiles) and one of these journeys checks the work
through the same reference-sink runner as the canonical Desktop journey.
The canonical journey then runs once, across every applet, as regression.

With one applet, Desk gives it the whole content area above the taskbar,
and its taskbar button is slot 1.
"""

from __future__ import annotations

from rich_terminal import text_rules
from rich_terminal.pygame_view import ATTR_REVERSE
from rich_terminal.retained_scene import ControlKind, ControlState
from rich_terminal.semantic_items import (
    ItemColumnKind,
    ItemField,
    ItemRole,
    ItemState,
    ItemViewRole,
    ViewItem,
    card_row_count,
)

import agent_transcript
import mixed_text
import styled_text
from rich_terminal_desktop_acceptance import (
    DAYBOOK_MENU_SIGNATURE,
    DAYBOOK_PROMPT_MARKER,
    PAD_MENU_SIGNATURE,
    FrameBoundJourney,
    JourneyProgress,
    PhysicalDesktopAcceptanceError,
    RichScreenProjection,
    _claim_item_runs,
    _claim_item_text,
    _collection_claims_in,
    _desk_content_bounds,
    _require_cell_text_in,
    _require_pad_readout,
    _residual_contains,
    _taskbar_has_focus,
    _text_area_pointer_state,
    _text_cell_in,
)

PAD_ALONE_FOCUS_MARKER = "[1:Akashic Pa*]"
FEXP_ALONE_FOCUS_MARKER = "[1:File Explo*]"
# The canonical Desktop image's large sample sits in the root directory.
FEXP_FILE = "large.txt"
FEXP_TABLE_COLUMNS = (
    (ItemColumnKind.TEXT, "Name"),
    (ItemColumnKind.NUMBER, "Size"),
    (ItemColumnKind.TEXT, "Type"),
)
PAD_OPEN_PROMPT_MARKER = "Open:"
DAYBOOK_ALONE_FOCUS_MARKER = "[1:Daybook*]"
STREAMS_ALONE_FOCUS_MARKER = "[1:Streams*]"
# Streams' feed alone on Desk (fixtures/streams/desk-timeline.json), in
# feed order: a post with a web link, a reply to it, and another post.
STREAMS_LINK = "https://example.test/streams/fixtures"
STREAMS_ROOT_TEXT = (
    f"Injected fixtures make network behavior reviewable. Notes at {STREAMS_LINK}."
)
STREAMS_REPLY_TEXT = "Does the thread retain identity across a cached restart?"
STREAMS_OTHER_TEXT = "Cards share one list widget with the rest of the Desk."
STREAMS_CARDS = (
    ("mira.test  2026-07-14T10:42:00-04:00", STREAMS_ROOT_TEXT, ""),
    ("rowan.test  2026-07-14T10:38:00-04:00", STREAMS_REPLY_TEXT, "reply"),
    ("kai.test  2026-07-14T10:31:00-04:00", STREAMS_OTHER_TEXT, ""),
)
STREAMS_CONTEXT_MARKER = "Retained timeline context (partial)"
AGENT_ALONE_FOCUS_MARKER = "[1:Agent*]"
AGENT_PROMPT_MARKER = "Ask:"
# The demo provider asks for approval when a request names one.
AGENT_REQUEST = "approval check"
AGENT_REVIEW_MARKER = "Provider approval request (no local tool envelope)"
AGENT_REVIEW_REASON = "Persist the simulated change?"
AGENT_APPROVE_MARKER = "[F6] Approve once"
AGENT_AUDIT = (
    "Approved agent action: provider org.akashic.agent.testing.scripted: "
    + AGENT_REVIEW_REASON
)
# The cards an approved request adds: the request, the reply, the review,
# and the record of the approval.
AGENT_EXCHANGE = (
    ("YOU", AGENT_REQUEST),
    (
        "AGENT",
        "Connected through Akashic's provider-neutral runtime. "
        f"You asked: {AGENT_REQUEST} Approved.",
    ),
    ("SYSTEM", AGENT_REVIEW_REASON),
    ("SYSTEM", AGENT_AUDIT),
)
# One wheel detent scrolls a list three screen rows.
AGENT_WHEEL_ROWS = 3
# The canonical image's large sample: 48 lines, too much text for the small
# terminal once Pad shows it.
SMALL_TERMINAL_LARGE_PATH = "/large.txt"
SMALL_TERMINAL_LARGE_LINE = "Large fixture line 001"
_WHERE = "Desk's single tile"


class _AppletJourney(FrameBoundJourney):
    """A journey through Desk holding the one applet FOCUS_MARKER names."""

    focus_marker = ""
    # The applet's modal prompt withholds its only menu bar; each journey
    # checks the menu itself.
    requires_menu_bar = False

    def _admit(self, offer, generation, projection, sender) -> bool:
        """Whether the journey may act on this frame: one newer than its last
        input's frame, in the session's lineage, once any pointer gesture the
        guest owes is complete, with the applet up and focused."""

        lineage = self._frame_lineage(offer, generation)
        if self._lineage is not None and lineage != self._lineage:
            raise PhysicalDesktopAcceptanceError(
                "physical acceptance frame left its original session lineage"
            )
        if offer.offer_id <= self.frame_barrier:
            return False
        # A newer acknowledged frame discards an old backpressured
        # authorization; the current stage must hold again before input.
        self._pending = None
        if not self._deliver_owed_pointer(offer, generation, sender):
            self.waiting = "the rest of a pointer gesture"
            return False
        if self.stage == 0:
            if not all(marker in projection.text for marker in self.ready_markers):
                self.waiting = f"the ready markers {self.ready_markers!r}"
                return False
            self._lineage = lineage
            if not _taskbar_has_focus(projection, self.focus_marker):
                # Desk starts its applet without focus; Alt+1 gives it.
                self.waiting = f"{self.focus_marker} after Alt+1"
                self._send("send_key", "alt+1", 0, offer, generation, sender)
                return False
        elif not _taskbar_has_focus(projection, self.focus_marker):
            raise PhysicalDesktopAcceptanceError(
                f"the applet lost focus: {self._taskbar_line(projection).strip()!r}"
            )
        return True

    def _frame_lineage(self, offer, generation):
        """The offer's session lineage.  An empty retained scene names no
        owner, so it keeps the owner of the lineage already established and
        must match everything else about it."""

        plane = offer.retained
        if (
            self.allows_empty_retained_frames
            and plane is not None
            and not plane.regions
        ):
            if self._lineage is None:
                raise PhysicalDesktopAcceptanceError(
                    "an empty retained scene came before any rich frame"
                )
            scope = offer.scope
            return (
                generation,
                scope.attachment_epoch,
                scope.session_id,
                scope.presentation_epoch,
                scope.geometry_generation,
                *self._lineage[5:],
            )
        return self._offer_lineage(offer, generation)

    def _wait(self, reason: str) -> JourneyProgress:
        """Wait for a newer frame, remembering why for timeout diagnostics."""

        self.waiting = reason
        return JourneyProgress()

    def _step(self, milestone, method, value, target, offer, generation, sender):
        self.waiting = None
        milestone = self._milestone(milestone)
        self._send(method, value, target, offer, generation, sender)
        return JourneyProgress(milestone)

    def _done(self, milestone: str, offer) -> JourneyProgress:
        self.stage = self.final_stage
        self.frame_barrier = offer.offer_id
        return JourneyProgress(self._milestone(milestone), True)


class PadAloneJourney(_AppletJourney):
    """Desk with Pad: type text that mixes scripts into its empty buffer,
    then follow a Markdown link to a Forth file.

    Pad's TEXT_AREA must carry the line logically and its CELL cells show it
    in visual order.  A click on the combined accent places the caret at its
    start; Right moves over both its scalars; Backspace after the emoji
    sequence deletes all of it, and Ctrl+Z restores it; and a click inside
    the Hebrew word lands on that letter.  The terminal sends the typed line,
    longer than one TEXT event allows, as several events.  Pad's Ln/Col
    readout counts characters in every frame that moves the caret.

    Pad then opens notes.md through its Open prompt.  Its TEXT_AREA carries
    the heading's, link's, and strong text's style runs, and a FOLLOW on the
    link, sent where the viewer finds the link as a Ctrl press would, opens
    example.f, whose keywords its runs mark.
    """

    focus_marker = PAD_ALONE_FOCUS_MARKER
    (
        READY,
        TYPED,
        ON_CLUSTER,
        PAST_CLUSTER,
        AFTER_FAMILY,
        FAMILY_DELETED,
        RESTORED,
        IN_HEBREW,
        OPEN_PROMPT,
        PATH_TYPED,
        NOTES_OPENED,
        LINK_FOLLOWED,
    ) = range(12)

    def __init__(self, ready_markers: tuple[str, ...]):
        super().__init__(ready_markers)
        self._editor_bounds: tuple[int, int, int, int] | None = None
        self._before: tuple[int, int] | None = None

    @property
    def final_stage(self) -> int:
        return self.LINK_FOLLOWED

    @property
    def final_cell_markers(self) -> tuple[str, ...]:
        return (self.focus_marker, styled_text.EXAMPLE_LINE)

    def _editor(self, projection: RichScreenProjection):
        """Pad's editor: of its text areas (it also has panels for build
        output and search results), the one with keyboard focus, where typed
        text goes; found again later by the bounds it first had."""

        claims = _collection_claims_in(
            projection, ControlKind.TEXT_AREA, _desk_content_bounds(projection)
        )
        if self._editor_bounds is None:
            focused = [claim for claim in claims if claim.state & ControlState.SELECTED]
            return focused[0] if len(focused) == 1 else None
        found = [
            claim
            for claim in claims
            if (claim.left, claim.top, claim.right, claim.bottom) == self._editor_bounds
        ]
        return found[0] if len(found) == 1 else None

    def after_present(self, offer, generation, projection, sender) -> JourneyProgress:
        if not self._admit(offer, generation, projection, sender):
            return JourneyProgress()
        if self.stage >= self.OPEN_PROMPT:
            return self._styled(offer, generation, projection, sender)
        if projection.menu_signatures != (PAD_MENU_SIGNATURE,):
            raise PhysicalDesktopAcceptanceError(
                f"Desk with Pad shows menus {projection.menu_signatures!r}"
            )
        claim = self._editor(projection)
        if claim is None:
            areas = [
                (area.left, area.top, area.right, area.bottom)
                for area in projection.semantic_collection_claims
                if area.kind is ControlKind.TEXT_AREA
            ]
            return self._wait(
                f"Pad's editor at {self._editor_bounds!r}; text areas {areas!r}"
            )
        bounds = _desk_content_bounds(projection)
        state = _text_area_pointer_state(claim)
        if state.anchor != (0, 0):
            raise PhysicalDesktopAcceptanceError("Pad gained a selection")
        text = _claim_item_text(claim, 1)
        full = mixed_text.PAD_TEXT
        cluster = full.index(mixed_text.PAD_CLUSTER)
        family = full.index(mixed_text.PAD_FAMILY)
        family_end = family + len(mixed_text.PAD_FAMILY)
        shortened = full[:family] + full[family_end:]
        # The second letter of the Hebrew word, away from its edges.
        lamed = full.index(mixed_text.PAD_HEBREW) + 1

        if self.stage == self.READY:
            if text != "" or state.primary != (1, 0):
                raise PhysicalDesktopAcceptanceError(
                    f"Pad did not start with an empty buffer: {text!r}"
                )
            self._editor_bounds = (claim.left, claim.top, claim.right, claim.bottom)
            return self._send_from(state, "pad-ready", "send_text", full, self.TYPED,
                                   offer, generation, sender)
        if self.stage == self.TYPED:
            text = text or ""
            if not full.startswith(text):
                raise PhysicalDesktopAcceptanceError(
                    f"Pad's typed line diverged from the text sent: {text!r}"
                )
            # The guest may paint between typed characters.
            if text != full or state.primary != (1, len(full)):
                return self._wait(
                    f"the typed line with the caret at its end: {text!r} "
                    f"at {state.primary!r}"
                )
            _require_pad_readout(projection, claim, bounds)
            _require_cell_text_in(offer, mixed_text.visual(full), bounds, _WHERE)
            return self._send_from(state, "pad-mixed-text-typed", "text_place",
                                   self._text_value(claim, 1, cluster), self.ON_CLUSTER,
                                   offer, generation, sender)
        if self.stage == self.FAMILY_DELETED:
            if text == full:
                return self._wait("Backspace to delete the emoji sequence")
            if text != shortened or state.primary != (1, family):
                raise PhysicalDesktopAcceptanceError(
                    "Backspace after the emoji sequence did not delete all of it: "
                    f"{text!r} at {state.primary!r}"
                )
            _require_pad_readout(projection, claim, bounds)
            _require_cell_text_in(offer, mixed_text.visual(shortened), bounds, _WHERE)
            return self._send_from(state, "pad-emoji-sequence-deleted", "send_key",
                                   "ctrl+z", self.RESTORED, offer, generation, sender)
        if self.stage == self.RESTORED:
            if text == shortened:
                return self._wait("Ctrl+Z to restore the emoji sequence")
            if text != full:
                raise PhysicalDesktopAcceptanceError(
                    f"Ctrl+Z did not restore the emoji sequence: {text!r}"
                )
            _require_cell_text_in(offer, mixed_text.visual(full), bounds, _WHERE)
            return self._send_from(state, "pad-emoji-sequence-restored", "text_place",
                                   self._text_value(claim, 1, lamed), self.IN_HEBREW,
                                   offer, generation, sender)
        if text != full:
            raise PhysicalDesktopAcceptanceError(f"Pad's line changed: {text!r}")
        expected = {
            self.ON_CLUSTER: (1, cluster),
            self.PAST_CLUSTER: (1, cluster + len(mixed_text.PAD_CLUSTER)),
            self.AFTER_FAMILY: (1, family_end),
            self.IN_HEBREW: (1, lamed),
        }[self.stage]
        if state.primary == self._before:
            return self._wait(f"the caret to move from {self._before!r}")
        if state.primary != expected:
            raise PhysicalDesktopAcceptanceError(
                f"Pad's caret is at {state.primary!r}, not {expected!r}, after "
                f"stage {self.stage}"
            )
        _require_pad_readout(projection, claim, bounds)
        if self.stage == self.ON_CLUSTER:
            return self._send_from(state, "pad-caret-placed-on-cluster", "send_key",
                                   "right", self.PAST_CLUSTER, offer, generation, sender)
        if self.stage == self.PAST_CLUSTER:
            return self._send_from(state, "pad-caret-moved-over-cluster", "text_place",
                                   self._text_value(claim, 1, family_end),
                                   self.AFTER_FAMILY, offer, generation, sender)
        if self.stage == self.AFTER_FAMILY:
            return self._send_from(state, "pad-caret-after-emoji-sequence", "send_key",
                                   "backspace", self.FAMILY_DELETED, offer, generation,
                                   sender)
        return self._send_from(state, "pad-caret-placed-in-hebrew", "send_key",
                               "ctrl+o", self.OPEN_PROMPT, offer, generation, sender)

    def _styled(self, offer, generation, projection, sender) -> JourneyProgress:
        """Open notes.md, check its style runs, and follow its link."""

        bounds = _desk_content_bounds(projection)
        prompt = _residual_contains(projection, PAD_OPEN_PROMPT_MARKER, bounds)
        if prompt and (
            projection.menu_signatures
            or _collection_claims_in(projection, ControlKind.TEXT_AREA, bounds)
        ):
            raise PhysicalDesktopAcceptanceError(
                "Pad's prompt did not withhold its menu and text areas"
            )
        if self.stage == self.OPEN_PROMPT:
            if not prompt:
                return self._wait("Pad's Open prompt after Ctrl+O")
            return self._step("pad-open-prompt-shown", "send_text",
                              styled_text.NOTES_PATH, self.PATH_TYPED, offer,
                              generation, sender)
        if self.stage == self.PATH_TYPED:
            if not prompt:
                raise PhysicalDesktopAcceptanceError(
                    "Pad's Open prompt closed before its path was entered"
                )
            if not _residual_contains(projection, styled_text.NOTES_PATH, bounds):
                return self._wait("the typed path in Pad's Open prompt")
            return self._step("pad-notes-path-typed", "send_key", "enter",
                              self.NOTES_OPENED, offer, generation, sender)
        if prompt:
            return self._wait("Pad's Open prompt to close")
        if projection.menu_signatures != (PAD_MENU_SIGNATURE,):
            return self._wait("Pad's menu bar after its prompt")
        claim = self._editor(projection)
        if claim is None:
            return self._wait("Pad's editor after its prompt")
        if self.stage == self.NOTES_OPENED:
            if _claim_item_text(claim, 2) != styled_text.NOTES_LINE:
                return self._wait("notes.md in Pad's editor")
            heading = _claim_item_runs(claim, 1)
            line = _claim_item_runs(claim, 2)
            if heading != styled_text.NOTES_HEADING_RUNS or line != styled_text.NOTES_LINE_RUNS:
                raise PhysicalDesktopAcceptanceError(
                    f"notes.md's style runs are {heading!r} and {line!r}"
                )
            # Follow the link from inside its text.
            offset = styled_text.NOTES_LINE.index(styled_text.NOTES_LINK_WORD) + 2
            return self._step("pad-markdown-styled", "text_follow",
                              self._text_value(claim, 2, offset), self.LINK_FOLLOWED,
                              offer, generation, sender)
        if _claim_item_text(claim, 1) != styled_text.EXAMPLE_LINE:
            return self._wait("example.f in Pad's editor after the FOLLOW")
        runs = _claim_item_runs(claim, 1)
        if runs != styled_text.EXAMPLE_LINE_RUNS:
            raise PhysicalDesktopAcceptanceError(f"example.f's style runs are {runs!r}")
        _require_cell_text_in(offer, styled_text.EXAMPLE_LINE, bounds, _WHERE)
        return self._done("pad-link-followed-to-forth", offer)

    def _send_from(self, state, milestone, method, value, target, offer, generation,
                   sender) -> JourneyProgress:
        """Send one input, remembering the caret it starts from."""

        self._before = state.primary
        return self._step(milestone, method, value, target, offer, generation, sender)


class DaybookAloneJourney(_AppletJourney):
    """Desk with Daybook: add a task that mixes scripts through its prompt,
    then check it off in the agenda.

    The prompt shows the typed text in visual order.  Backspace after an
    emoji sequence deletes all of it; a click on a Han character's second
    cell puts the caret before that character, where one typed character
    lands; and Enter adds the task.  The agenda is a SECTIONS item view,
    and the task is an unchecked checkable item under the TASKS heading; a
    CHECK on it marks it done.  While the prompt is open, Daybook's menu,
    calendar grid and agenda are withheld, as the document-atomic fallback
    requires, and its cells stay complete.
    """

    focus_marker = DAYBOOK_ALONE_FOCUS_MARKER
    (
        READY,
        PROMPT,
        HEAD_TYPED,
        EMOJI_DELETED,
        TASK_TYPED,
        CLICKED,
        INSERTED,
        ADDED,
        CHECKED,
    ) = range(9)

    def __init__(self, ready_markers: tuple[str, ...]):
        super().__init__(ready_markers)
        self._field: tuple[int, int] | None = None  # (column, row)
        self._han_column = 0

    @property
    def final_stage(self) -> int:
        return self.CHECKED

    @property
    def final_cell_markers(self) -> tuple[str, ...]:
        return (self.focus_marker, mixed_text.visual(mixed_text.DAYBOOK_ENTRY))

    @staticmethod
    def _agenda(projection, bounds):
        """Daybook's agenda, when the tile carries exactly one."""

        left, top, right, bottom = bounds
        agendas = [
            claim
            for claim in projection.semantic_item_view_claims
            if left <= claim.left < claim.right <= right
            and top <= claim.top < claim.bottom <= bottom
            and claim.content.role is ItemViewRole.SECTIONS
        ]
        return agendas[0] if len(agendas) == 1 else None

    @staticmethod
    def _task(agenda, entry: str):
        """The agenda's item for ENTRY, required to be a task."""

        task = agenda.named(entry)
        if task is None:
            return None
        sections = {
            item.item_key: item.fields[0].text
            for item in agenda.content.items
            if item.role is ItemRole.SECTION
        }
        if (
            not task.state & ItemState.CHECKABLE
            or sections.get(task.parent_key, "TASKS") != "TASKS"
        ):
            raise PhysicalDesktopAcceptanceError(
                "Daybook's new task is not a checkable item of its TASKS section"
            )
        return task

    def after_present(self, offer, generation, projection, sender) -> JourneyProgress:
        if not self._admit(offer, generation, projection, sender):
            return JourneyProgress()
        bounds = _desk_content_bounds(projection)
        prompt = _residual_contains(projection, DAYBOOK_PROMPT_MARKER, bounds)
        collections = tuple(
            claim
            for kind in (ControlKind.TEXT_AREA, ControlKind.TEXT_GRID)
            for claim in _collection_claims_in(projection, kind, bounds)
        )
        if prompt:
            if (
                projection.menu_signatures
                or collections
                or projection.semantic_item_view_claims
            ):
                raise PhysicalDesktopAcceptanceError(
                    "Daybook's prompt did not withhold its menu, collections "
                    "and agenda"
                )
        elif projection.menu_signatures != (DAYBOOK_MENU_SIGNATURE,) or not any(
            claim.kind is ControlKind.TEXT_GRID for claim in collections
        ):
            # A frame between the prompt and its document may lack them.
            return JourneyProgress()

        task = mixed_text.DAYBOOK_TASK
        emoji_end = task.index(mixed_text.DAYBOOK_EMOJI) + len(mixed_text.DAYBOOK_EMOJI)
        head = task[:emoji_end]
        shortened = task[: emoji_end - len(mixed_text.DAYBOOK_EMOJI)]
        entry = mixed_text.DAYBOOK_ENTRY

        if self.stage == self.READY:
            if prompt:
                raise PhysicalDesktopAcceptanceError("Daybook's prompt was already open")
            return self._step("daybook-ready", "send_key", "ctrl+n", self.PROMPT,
                              offer, generation, sender)
        if self.stage == self.ADDED:
            # Enter closes the prompt; the agenda then shows the task.
            if prompt:
                return JourneyProgress()
            return self._added(offer, generation, projection, bounds, entry, sender)
        if self.stage == self.CHECKED:
            agenda = self._agenda(projection, bounds)
            task = None if agenda is None else self._task(agenda, entry)
            if task is None or not task.state & ItemState.CHECKED:
                return JourneyProgress()
            _require_cell_text_in(offer, "[x]", bounds, _WHERE)
            return self._done("daybook-task-checked", offer)
        if not prompt:
            if self.stage == self.PROMPT:
                return JourneyProgress()
            raise PhysicalDesktopAcceptanceError("Daybook's prompt closed early")
        label = _text_cell_in(projection, DAYBOOK_PROMPT_MARKER, bounds, _WHERE)
        if label is None:
            return JourneyProgress()
        _column, row = label
        left, _top, right, _bottom = bounds
        if self.stage == self.PROMPT:
            return self._step("daybook-prompt-opened", "send_text", head,
                              self.HEAD_TYPED, offer, generation, sender)
        if self.stage == self.HEAD_TYPED:
            columns = projection.find_cells(mixed_text.visual(head), row, left, right)
            if not columns:
                return JourneyProgress()
            self._field = (columns[0], row)
            return self._step("daybook-prompt-head-typed", "send_key", "backspace",
                              self.EMOJI_DELETED, offer, generation, sender)
        column, field_row = self._field
        if field_row != row:
            raise PhysicalDesktopAcceptanceError("Daybook's prompt moved")

        def shows(line: str) -> bool:
            return _field_shows(projection, column, row, line, entry)

        if self.stage == self.EMOJI_DELETED:
            if shows(head):
                return JourneyProgress()
            if not shows(shortened):
                raise PhysicalDesktopAcceptanceError(
                    "Backspace in Daybook's prompt did not delete the whole emoji "
                    f"sequence: {projection.row_text(row, column, right)!r}"
                )
            return self._step("daybook-emoji-sequence-deleted", "send_text",
                              task[len(shortened):], self.TASK_TYPED, offer,
                              generation, sender)
        if self.stage == self.TASK_TYPED:
            # The guest may paint between typed characters.
            if not shows(task):
                return JourneyProgress()
            _require_cell_text_in(offer, mixed_text.visual(task), bounds, _WHERE)
            columns = projection.find_cells(mixed_text.DAYBOOK_HAN, row, left, right)
            if len(columns) != 1:
                raise PhysicalDesktopAcceptanceError(
                    "Daybook's prompt does not show its Han character once"
                )
            self._han_column = columns[0]
            # The character's second cell names its start (APT-1-TEXT 9.1).
            return self._step("daybook-mixed-task-typed", "pointer_click",
                              f"{columns[0] + 1},{row}", self.CLICKED, offer,
                              generation, sender)
        if self.stage == self.CLICKED:
            # The focused caret now marks the Han character's cells.
            if not offer.cell.cells[row][self._han_column].attrs & ATTR_REVERSE:
                return JourneyProgress()
            return self._step("daybook-prompt-caret-on-han", "send_text",
                              mixed_text.DAYBOOK_INSERT, self.INSERTED, offer,
                              generation, sender)
        if not shows(entry):
            return JourneyProgress()
        return self._step("daybook-prompt-text-inserted-at-click", "send_key", "enter",
                          self.ADDED, offer, generation, sender)

    def _added(self, offer, generation, projection, bounds, entry, sender):
        agenda = self._agenda(projection, bounds)
        task = None if agenda is None else self._task(agenda, entry)
        if task is None:
            return JourneyProgress()
        if task.state & ItemState.CHECKED:
            raise PhysicalDesktopAcceptanceError("Daybook's new task started checked")
        _require_cell_text_in(offer, mixed_text.visual(entry), bounds, _WHERE)
        return self._step("daybook-mixed-task-added", "item_check",
                          agenda.value(task.item_key), self.CHECKED, offer,
                          generation, sender)


class FexpAloneJourney(_AppletJourney):
    """Desk with File Explorer: select a file and open a directory in its
    detail table, then expand, select, and collapse in its folder tree, all
    through item events.

    The detail table is a TABLE item view with Name, Size (a number column),
    and Type columns, and the sidebar a TREE whose root is "/".  A SELECT
    on large.txt's row selects it and the status bar shows its path; an
    OPEN on a directory's row lists that directory.  An EXPAND on the
    tree's root shows its entries, a SELECT on one of its directories lists
    that directory, and a COLLAPSE on the root hides them, which moves the
    selection back to the root and lists it again.  CELL shows the rows
    throughout.

    Last, Alt+H opens Desk's launcher, an overlay document whose catalog is
    a two-column item view; while it is open File Explorer's lists fall
    back beneath it.  An OPEN on its File Explorer row focuses the running
    applet and closes the launcher, and the lists come back.
    """

    focus_marker = FEXP_ALONE_FOCUS_MARKER
    (
        READY,
        FILE_SELECTED,
        DIRECTORY_OPENED,
        TREE_EXPANDED,
        TREE_CHILD_SELECTED,
        TREE_COLLAPSED,
        LAUNCHER_OPENED,
        LAUNCHER_CLOSED,
    ) = range(8)

    def __init__(self, ready_markers: tuple[str, ...]):
        super().__init__(ready_markers)
        self._directory: str | None = None

    @property
    def final_stage(self) -> int:
        return self.LAUNCHER_CLOSED

    @property
    def final_cell_markers(self) -> tuple[str, ...]:
        return (self.focus_marker, FEXP_FILE)

    @staticmethod
    def _launcher(projection: RichScreenProjection):
        """Desk's launcher: the one item view of two columns listing File
        Explorer."""

        views = [
            claim
            for claim in projection.semantic_item_view_claims
            if len(claim.content.columns) == 2
            and claim.named("File Explorer") is not None
        ]
        return views[0] if len(views) == 1 else None

    @staticmethod
    def _views(projection: RichScreenProjection):
        left, top, right, bottom = _desk_content_bounds(projection)
        views = [
            claim
            for claim in projection.semantic_item_view_claims
            if left <= claim.left < claim.right <= right
            and top <= claim.top < claim.bottom <= bottom
        ]
        tables = [view for view in views if view.content.role is ItemViewRole.TABLE]
        trees = [view for view in views if view.content.role is ItemViewRole.TREE]
        if len(tables) != 1 or len(trees) != 1:
            return None, None
        return tables[0], trees[0]

    @staticmethod
    def _shown(view, item) -> bool:
        content = view.content
        return (
            content.viewport_first
            <= item.ordinal
            < content.viewport_first + content.viewport_count
        )

    def after_present(self, offer, generation, projection, sender) -> JourneyProgress:
        if not self._admit(offer, generation, projection, sender):
            return JourneyProgress()
        launcher = self._launcher(projection)
        if self.stage == self.LAUNCHER_OPENED:
            if launcher is None:
                return self._wait("Desk's launcher listing File Explorer")
            if len(projection.semantic_item_view_claims) != 1:
                raise PhysicalDesktopAcceptanceError(
                    "File Explorer's lists stayed rich beneath the launcher"
                )
            row = launcher.named("File Explorer")
            if not row.state & ItemState.SELECTED:
                raise PhysicalDesktopAcceptanceError(
                    "the launcher did not open on its first entry"
                )
            return self._step("desk-launcher-opened", "item_open",
                              launcher.value(row.item_key), self.LAUNCHER_CLOSED,
                              offer, generation, sender)
        if self.stage == self.LAUNCHER_CLOSED and launcher is not None:
            return self._wait("the launcher closed")
        table, tree = self._views(projection)
        if table is None:
            return self._wait("File Explorer's detail table and folder tree")
        if self.stage == self.LAUNCHER_CLOSED:
            return self._done("desk-launcher-closed", offer)
        columns = tuple((column.kind, column.label) for column in table.content.columns)
        if columns != FEXP_TABLE_COLUMNS:
            raise PhysicalDesktopAcceptanceError(
                f"File Explorer's detail table has columns {columns!r}"
            )
        bounds = _desk_content_bounds(projection)
        root = tree.content.items[0]
        if root.fields[0].text != "/" or not root.state & ItemState.EXPANDABLE:
            raise PhysicalDesktopAcceptanceError(
                f"File Explorer's tree starts with {root.fields[0].text!r}"
            )

        if self.stage == self.READY:
            row = table.named(FEXP_FILE)
            if row is None or not self._shown(table, row):
                content = table.content
                if content.viewport_first + content.viewport_count >= content.item_total:
                    raise PhysicalDesktopAcceptanceError(
                        f"File Explorer's root lists no {FEXP_FILE}"
                    )
                return self._step("fexp-table-scrolled", "item_scroll", table.value(1),
                                  self.READY, offer, generation, sender)
            _require_cell_text_in(offer, FEXP_FILE, bounds, _WHERE)
            return self._step("fexp-table-shown", "item_select",
                              table.value(row.item_key), self.FILE_SELECTED, offer,
                              generation, sender)
        if self.stage == self.FILE_SELECTED:
            selected = table.selected
            if selected is None or selected.fields[0].text != FEXP_FILE:
                return self._wait(f"{FEXP_FILE}'s row selected")
            if not _residual_contains(projection, "/" + FEXP_FILE, bounds):
                return self._wait("the selected file's path in the status bar")
            directories = [
                item
                for item in table.content.shown_items()
                if item.fields[-1].text == "dir"
            ]
            if not directories:
                raise PhysicalDesktopAcceptanceError(
                    "File Explorer's root shows no directory to open"
                )
            self._directory = directories[0].fields[0].text
            return self._step("fexp-file-selected", "item_open",
                              table.value(directories[0].item_key),
                              self.DIRECTORY_OPENED, offer, generation, sender)
        if self.stage == self.DIRECTORY_OPENED:
            if table.named(FEXP_FILE) is not None or not _residual_contains(
                projection, "/" + self._directory, bounds
            ):
                return self._wait(f"the table listing /{self._directory}")
            if root.state & ItemState.EXPANDED:
                raise PhysicalDesktopAcceptanceError("the tree's root began expanded")
            return self._step("fexp-directory-opened", "item_expand",
                              tree.value(root.item_key), self.TREE_EXPANDED, offer,
                              generation, sender)
        children = [
            item for item in tree.content.items if item.parent_key == root.item_key
        ]
        if self.stage == self.TREE_EXPANDED:
            if not root.state & ItemState.EXPANDED or not children:
                return self._wait("the tree's root expanded")
            folders = [
                item
                for item in children
                if item.state & ItemState.EXPANDABLE and self._shown(tree, item)
            ]
            if not folders:
                raise PhysicalDesktopAcceptanceError(
                    "the expanded tree shows no directory"
                )
            self._directory = folders[0].fields[0].text
            _require_cell_text_in(offer, self._directory, bounds, _WHERE)
            return self._step("fexp-tree-expanded", "item_select",
                              tree.value(folders[0].item_key),
                              self.TREE_CHILD_SELECTED, offer, generation, sender)
        if self.stage == self.TREE_CHILD_SELECTED:
            selected = tree.selected
            if (
                selected is None
                or selected.fields[0].text != self._directory
                or not _residual_contains(projection, "/" + self._directory, bounds)
            ):
                return self._wait(f"/{self._directory} selected in the tree")
            return self._step("fexp-tree-directory-selected", "item_collapse",
                              tree.value(root.item_key), self.TREE_COLLAPSED, offer,
                              generation, sender)
        if root.state & ItemState.EXPANDED or children:
            return self._wait("the tree's root collapsed")
        selected = tree.selected
        if selected is None or selected.item_key != root.item_key:
            raise PhysicalDesktopAcceptanceError(
                "collapsing the root did not move the selection to it"
            )
        if table.named(FEXP_FILE) is None:
            return self._wait("the table listing the root again")
        return self._step("fexp-tree-collapsed", "send_key", "alt+h",
                          self.LAUNCHER_OPENED, offer, generation, sender)


class StreamsAloneJourney(_AppletJourney):
    """Desk with Streams and a fixed feed: select a reply and open its
    context, through item events on Streams' cards.

    The timeline is a CARDS item view of three text fields per post: its
    author and time, its text, and "reply" when it replies.  The web link
    in the first post's text is a LINK style run.  A SELECT on the reply's
    card selects it; an OPEN on it opens its context, a second CARDS view
    holding only the thread's two posts with the reply selected.  CELL shows
    the cards throughout.
    """

    focus_marker = STREAMS_ALONE_FOCUS_MARKER
    READY, SELECTED, OPENED = range(3)

    @property
    def final_stage(self) -> int:
        return self.OPENED

    @property
    def final_cell_markers(self) -> tuple[str, ...]:
        return (self.focus_marker, STREAMS_CONTEXT_MARKER, STREAMS_REPLY_TEXT)

    @staticmethod
    def _cards(projection):
        """Streams' cards, when the tile carries exactly one CARDS view."""

        left, top, right, bottom = _desk_content_bounds(projection)
        views = [
            claim
            for claim in projection.semantic_item_view_claims
            if left <= claim.left < claim.right <= right
            and top <= claim.top < claim.bottom <= bottom
            and claim.content.role is ItemViewRole.CARDS
        ]
        return views[0] if len(views) == 1 else None

    @staticmethod
    def _posts(cards) -> list[tuple[str, ...]]:
        return [
            tuple(field.text for field in item.fields) for item in cards.content.items
        ]

    @staticmethod
    def _check_timeline(cards) -> None:
        columns = tuple(
            (column.kind, column.label) for column in cards.content.columns
        )
        if columns != ((ItemColumnKind.TEXT, ""),) * 3:
            raise PhysicalDesktopAcceptanceError(
                f"Streams' cards have columns {columns!r}"
            )
        posts = StreamsAloneJourney._posts(cards)
        if posts != list(STREAMS_CARDS):
            raise PhysicalDesktopAcceptanceError(
                f"Streams' timeline cards read {posts!r}"
            )
        root = cards.content.items[0]
        runs = [
            (run.start, run.length, int(run.meaning)) for run in root.fields[1].runs
        ]
        link = (STREAMS_ROOT_TEXT.index(STREAMS_LINK), len(STREAMS_LINK),
                styled_text.LINK)
        if runs != [link]:
            raise PhysicalDesktopAcceptanceError(
                f"the web link in Streams' first post has runs {runs!r}"
            )
        if any(run for item in cards.content.items[1:] for f in item.fields
               for run in f.runs) or any(root.fields[i].runs for i in (0, 2)):
            raise PhysicalDesktopAcceptanceError(
                "Streams' cards style text that is not a link"
            )
        if not root.state & ItemState.SELECTED:
            raise PhysicalDesktopAcceptanceError(
                "Streams did not start with its first post selected"
            )

    def after_present(self, offer, generation, projection, sender) -> JourneyProgress:
        if not self._admit(offer, generation, projection, sender):
            return JourneyProgress()
        bounds = _desk_content_bounds(projection)
        cards = self._cards(projection)
        if cards is None:
            return self._wait("Streams' cards")
        context = _residual_contains(projection, STREAMS_CONTEXT_MARKER, bounds)
        reply = next(
            (
                item
                for item in cards.content.items
                if item.fields[1].text == STREAMS_REPLY_TEXT
            ),
            None,
        )
        if self.stage == self.READY:
            if context:
                raise PhysicalDesktopAcceptanceError("Streams started in a context")
            self._check_timeline(cards)
            _require_cell_text_in(offer, STREAMS_REPLY_TEXT, bounds, _WHERE)
            _require_cell_text_in(offer, STREAMS_LINK, bounds, _WHERE)
            return self._step("streams-cards-shown", "item_select",
                              cards.value(reply.item_key), self.SELECTED, offer,
                              generation, sender)
        if self.stage == self.SELECTED:
            selected = cards.selected
            if selected is None or selected.item_key != reply.item_key:
                return self._wait("the reply's card selected")
            if context:
                raise PhysicalDesktopAcceptanceError(
                    "a SELECT on the reply opened its context"
                )
            return self._step("streams-reply-selected", "item_open",
                              cards.value(reply.item_key), self.OPENED, offer,
                              generation, sender)
        if not context:
            return self._wait("the reply's context")
        posts = self._posts(cards)
        if posts != list(STREAMS_CARDS[:2]):
            raise PhysicalDesktopAcceptanceError(
                f"the reply's context cards read {posts!r}"
            )
        selected = cards.selected
        if selected is None or selected.fields[1].text != STREAMS_REPLY_TEXT:
            raise PhysicalDesktopAcceptanceError(
                "the reply is not selected in its context"
            )
        _require_cell_text_in(offer, STREAMS_REPLY_TEXT, bounds, _WHERE)
        return self._done("streams-context-opened", offer)


class AgentAloneJourney(_AppletJourney):
    """Desk with the Agent and a long stored conversation: scroll the
    transcript, return to its end, then ask for a reviewed change and
    approve it.

    The transcript is a CARDS item view of two text fields per message: a
    header, the message's role styled as a heading, and the message's text,
    whose column wraps.  It is a log, so no card is selected and the view
    follows the end.  The stored answer is taller than the view, so the
    transcript starts cut inside it; one wheel detent scrolls three screen
    rows up, and End returns to the end.  Ctrl+L opens the Ask prompt; the
    request makes the demo provider ask for approval, in a dialog over the
    transcript that shows its request and unlocks F6 once it has shown its
    last row.  While the prompt or the dialog is open, the Agent's menu and
    transcript are withheld and CELL shows it.  F6 approves, and the
    transcript then ends with the approved exchange.  CELL shows each end
    of the transcript on its last row.
    """

    focus_marker = AGENT_ALONE_FOCUS_MARKER
    READY, SCROLLED, ENDED, PROMPT, TYPED, REVIEW, APPROVED = range(7)

    def __init__(self, ready_markers: tuple[str, ...]):
        super().__init__(ready_markers)
        self._end_row = 0  # screen rows above the view at the stored end

    @property
    def final_stage(self) -> int:
        return self.APPROVED

    @property
    def final_cell_markers(self) -> tuple[str, ...]:
        return (self.focus_marker, AGENT_AUDIT)

    @staticmethod
    def _transcript(projection, bounds):
        """The Agent's transcript, when the tile carries it."""

        left, top, right, bottom = bounds
        views = [
            claim
            for claim in projection.semantic_item_view_claims
            if left <= claim.left < claim.right <= right
            and top <= claim.top < claim.bottom <= bottom
        ]
        if not views:
            return None
        if len(views) != 1 or views[0].content.role is not ItemViewRole.CARDS:
            raise PhysicalDesktopAcceptanceError(
                "the Agent's tile carries an item view other than its transcript"
            )
        return views[0]

    @staticmethod
    def _shows(transcript, cards) -> bool:
        """Whether the carried cards read as the (header, text) CARDS do."""

        content = transcript.content
        return content.item_total == len(cards) and all(
            (item.fields[0].text, item.fields[1].text) == cards[item.ordinal]
            for item in content.items
        )

    @staticmethod
    def _check(transcript, cards) -> None:
        """The transcript is a log of CARDS, each styled as the Agent styles
        it, and shows them."""

        content = transcript.content
        columns = tuple(
            (column.kind, column.label, column.wrap) for column in content.columns
        )
        if columns != (
            (ItemColumnKind.TEXT, "", False),
            (ItemColumnKind.TEXT, "", True),
        ):
            raise PhysicalDesktopAcceptanceError(
                f"the Agent's transcript has columns {columns!r}"
            )
        if not AgentAloneJourney._shows(transcript, cards):
            shown = [
                (item.fields[0].text, item.fields[1].text[:40])
                for item in content.items
            ]
            raise PhysicalDesktopAcceptanceError(
                f"the Agent's transcript of {content.item_total} cards shows {shown!r}"
            )
        for item in content.items:
            if item.state & ItemState.SELECTED:
                raise PhysicalDesktopAcceptanceError(
                    "the Agent's transcript selected a card"
                )
            header = item.fields[0]
            runs = [(run.start, run.length, int(run.meaning)) for run in header.runs]
            if runs != [(0, len(header.text), styled_text.HEADING)] or item.fields[1].runs:
                raise PhysicalDesktopAcceptanceError(
                    f"the Agent's card {header.text!r} is styled {runs!r}"
                )

    @staticmethod
    def _rows(transcript, cards) -> tuple[int, int]:
        """The screen rows above the view and in all, as MegaPad counts
        each card's rows at the transcript's width."""

        content = transcript.content
        width = transcript.right - transcript.left
        rows = [
            card_row_count(
                content,
                ViewItem(ordinal + 1, 0, ordinal, 0, ItemState(0), ItemRole.ITEM,
                         (ItemField(header), ItemField(text))),
                width,
            )
            for ordinal, (header, text) in enumerate(cards)
        ]
        above = sum(rows[: content.viewport_first]) + content.viewport_row
        return above, sum(rows)

    @staticmethod
    def _at_end(transcript, cards) -> int:
        """The rows above the view, which must end with the transcript."""

        above, total = AgentAloneJourney._rows(transcript, cards)
        body = transcript.bottom - transcript.top
        if total <= body or above != total - body:
            raise PhysicalDesktopAcceptanceError(
                f"the Agent's transcript of {total} rows in {body} is not at "
                f"its end: {above} rows above the view"
            )
        return above

    @staticmethod
    def _require_last_row(offer, transcript, line: str) -> None:
        """CELL shows LINE as the transcript's last row, where a card's
        text starts."""

        place = (transcript.bottom - 1, transcript.left + 3)
        if place not in offer.cell.find(line):
            raise PhysicalDesktopAcceptanceError(
                f"CELL does not end the Agent's transcript with {line!r}"
            )

    def after_present(self, offer, generation, projection, sender) -> JourneyProgress:
        if not self._admit(offer, generation, projection, sender):
            return JourneyProgress()
        bounds = _desk_content_bounds(projection)
        transcript = self._transcript(projection, bounds)
        prompt = _residual_contains(projection, AGENT_PROMPT_MARKER, bounds)
        review = _residual_contains(projection, AGENT_REVIEW_MARKER, bounds)
        if (prompt or review) and (transcript is not None or projection.menu_signatures):
            raise PhysicalDesktopAcceptanceError(
                "the Agent's prompt or review did not withhold its menu and transcript"
            )
        stored = agent_transcript.CARDS
        if self.stage in (self.READY, self.SCROLLED, self.ENDED):
            if prompt or review:
                raise PhysicalDesktopAcceptanceError(
                    "the Agent opened its prompt or a review unasked"
                )
            if transcript is None:
                return self._wait("the Agent's transcript")
            self._check(transcript, stored)
        if self.stage == self.READY:
            self._end_row = self._at_end(transcript, stored)
            self._require_last_row(offer, transcript, agent_transcript.LAST)
            return self._step("agent-transcript-at-end", "item_scroll",
                              transcript.value(-1), self.SCROLLED, offer,
                              generation, sender)
        if self.stage == self.SCROLLED:
            above, _total = self._rows(transcript, stored)
            if above == self._end_row:
                return self._wait("the transcript scrolled by the wheel")
            if above != self._end_row - AGENT_WHEEL_ROWS:
                raise PhysicalDesktopAcceptanceError(
                    "one wheel detent did not scroll the Agent's transcript "
                    f"{AGENT_WHEEL_ROWS} rows: {self._end_row} rows above became {above}"
                )
            self._require_last_row(offer, transcript, agent_transcript.STEPS[-3])
            return self._step("agent-transcript-scrolled", "send_key", "end",
                              self.ENDED, offer, generation, sender)
        if self.stage == self.ENDED:
            above, _total = self._rows(transcript, stored)
            if above != self._end_row:
                return self._wait("the transcript back at its end")
            self._require_last_row(offer, transcript, agent_transcript.LAST)
            return self._step("agent-transcript-end-again", "send_key", "ctrl+l",
                              self.PROMPT, offer, generation, sender)
        if self.stage == self.PROMPT:
            if not prompt:
                return self._wait("the Agent's Ask prompt")
            return self._step("agent-prompt-opened", "send_text", AGENT_REQUEST,
                              self.TYPED, offer, generation, sender)
        if self.stage == self.TYPED:
            if not prompt:
                raise PhysicalDesktopAcceptanceError("the Agent's Ask prompt closed early")
            if not _residual_contains(projection, AGENT_REQUEST, bounds):
                return self._wait("the typed request")
            return self._step("agent-request-typed", "send_key", "enter",
                              self.REVIEW, offer, generation, sender)
        if self.stage == self.REVIEW:
            if not review:
                return self._wait("the Agent's review")
            for marker in (AGENT_REVIEW_REASON, AGENT_APPROVE_MARKER):
                if not _residual_contains(projection, marker, bounds):
                    return self._wait(f"{marker!r} in the review")
            _require_cell_text_in(offer, AGENT_REVIEW_MARKER, bounds, _WHERE)
            return self._step("agent-review-unlocked", "send_key", "f6",
                              self.APPROVED, offer, generation, sender)
        cards = stored + AGENT_EXCHANGE
        if review or transcript is None or not self._shows(transcript, cards):
            return self._wait("the approved exchange")
        self._check(transcript, cards)
        self._at_end(transcript, cards)
        self._require_last_row(offer, transcript, AGENT_AUDIT)
        return self._done("agent-review-approved", offer)


class SmallTerminalJourney(_AppletJourney):
    """Desk with Pad on a terminal with little room for retained text: a
    screen that cannot fit is shown as CELL, Desk and Pad carry on, and the
    rich frame returns once a screen fits again.

    Pad's empty editor fits, so the journey starts rich: Pad's menu bar and
    its editor as a text area.  Ctrl+O opens Pad's Open prompt, which leaves
    the whole screen to residual glyphs, more text than the terminal holds;
    the producer replaces the rich frame with an empty one and the viewer
    shows CELL.  Every frame is either complete rich output or an empty
    retained scene over complete CELL, never older rich output over a newer
    CELL frame.  The 48-line large sample is too much as well, and stays
    CELL.  Opening the two-line example.f through the same prompt brings the
    rich frame back, with example.f in Pad's text area.
    """

    focus_marker = PAD_ALONE_FOCUS_MARKER
    allows_empty_retained_frames = True
    READY, PROMPT, TYPED, LARGE, PROMPT_AGAIN, TYPED_AGAIN, RICH = range(7)

    @property
    def final_stage(self) -> int:
        return self.RICH

    @property
    def final_cell_markers(self) -> tuple[str, ...]:
        return (self.focus_marker, styled_text.EXAMPLE_LINE)

    @staticmethod
    def _empty(projection) -> bool:
        """Whether the retained scene is empty, so the viewer shows CELL."""

        return projection.draw_count == 0 and not (
            projection.menu_signatures
            or projection.semantic_collection_claims
            or projection.semantic_item_view_claims
        )

    @staticmethod
    def _editor(projection, bounds):
        """Pad's editor, when the frame is rich and shows it."""

        areas = _collection_claims_in(projection, ControlKind.TEXT_AREA, bounds)
        editors = [claim for claim in areas if claim.state & ControlState.SELECTED]
        return editors[0] if len(editors) == 1 else None

    @staticmethod
    def _cell_shows(offer, text: str, bounds) -> bool:
        left, top, right, bottom = bounds
        return any(
            top <= row < bottom and left <= column < right
            for row, column in offer.cell.find(text)
        )

    def _empty_showing(self, offer, projection, text: str, bounds, what: str) -> bool:
        """Whether this frame is the empty scene with CELL showing TEXT; a
        rich frame showing it means the screen fit, which it must not."""

        if not self._empty(projection):
            if _residual_contains(projection, text, bounds) or self._editor(
                projection, bounds
            ) is not None and text in "\n".join(
                self._editor(projection, bounds).visible_text
            ):
                raise PhysicalDesktopAcceptanceError(
                    f"{what} fit the small terminal and was shown rich"
                )
            return False
        return self._cell_shows(offer, text, bounds)

    def after_present(self, offer, generation, projection, sender) -> JourneyProgress:
        if not self._admit(offer, generation, projection, sender):
            return JourneyProgress()
        bounds = _desk_content_bounds(projection)
        empty = self._empty(projection)
        if not empty and (projection.draw_count == 0 or not projection.menu_signatures
                          and not _residual_contains(projection, PAD_OPEN_PROMPT_MARKER,
                                                     bounds)):
            # A rich frame is complete: Pad's menu, or its prompt as residual.
            raise PhysicalDesktopAcceptanceError(
                "a rich frame on the small terminal was incomplete"
            )
        if self.stage == self.READY:
            editor = self._editor(projection, bounds)
            if empty or editor is None or projection.menu_signatures != (
                PAD_MENU_SIGNATURE,
            ):
                raise PhysicalDesktopAcceptanceError(
                    "Pad's empty editor was not shown rich on the small terminal"
                )
            _require_cell_text_in(offer, "Untitled", bounds, _WHERE)
            return self._step("small-terminal-pad-rich", "send_key", "ctrl+o",
                              self.PROMPT, offer, generation, sender)
        if self.stage == self.PROMPT:
            if not self._empty_showing(offer, projection, PAD_OPEN_PROMPT_MARKER,
                                       bounds, "Pad's Open prompt"):
                return self._wait("the Open prompt shown as CELL")
            return self._step("small-terminal-prompt-shown-as-cell", "send_text",
                              SMALL_TERMINAL_LARGE_PATH, self.TYPED, offer,
                              generation, sender)
        if self.stage == self.TYPED:
            if not self._empty_showing(offer, projection, SMALL_TERMINAL_LARGE_PATH,
                                       bounds, "the typed path"):
                return self._wait("the typed path shown as CELL")
            return self._step("small-terminal-large-path-typed", "send_key", "enter",
                              self.LARGE, offer, generation, sender)
        if self.stage == self.LARGE:
            if not self._empty_showing(offer, projection, SMALL_TERMINAL_LARGE_LINE,
                                       bounds, "the large sample"):
                return self._wait("the large sample shown as CELL")
            return self._step("small-terminal-large-file-shown-as-cell", "send_key",
                              "ctrl+o", self.PROMPT_AGAIN, offer, generation, sender)
        if self.stage == self.PROMPT_AGAIN:
            if not (empty and self._cell_shows(offer, PAD_OPEN_PROMPT_MARKER, bounds)):
                return self._wait("the Open prompt again")
            return self._step("small-terminal-prompt-shown-again", "send_text",
                              styled_text.EXAMPLE_PATH, self.TYPED_AGAIN, offer,
                              generation, sender)
        if self.stage == self.TYPED_AGAIN:
            if not (empty and self._cell_shows(offer, styled_text.EXAMPLE_PATH, bounds)):
                return self._wait("the example path shown as CELL")
            return self._step("small-terminal-example-path-typed", "send_key", "enter",
                              self.RICH, offer, generation, sender)
        editor = None if empty else self._editor(projection, bounds)
        if editor is None or styled_text.EXAMPLE_LINE not in editor.visible_text:
            return self._wait("example.f shown rich again")
        _require_cell_text_in(offer, styled_text.EXAMPLE_LINE, bounds, _WHERE)
        return self._done("small-terminal-rich-again", offer)


def _field_shows(projection, column, row, line: str, longest: str) -> bool:
    """Whether a field from COLUMN of ROW shows LINE's cells, then only
    blanks as far as the longest line LONGEST would reach."""

    width = text_rules.string_width(line)
    end = column + text_rules.string_width(longest) + 1
    return (
        projection.row_text(row, column, column + width) == mixed_text.visual(line)
        and not projection.row_text(row, column + width, end).strip()
    )


def applet_journey(name: str, ready_markers: tuple[str, ...]) -> FrameBoundJourney:
    """The journey for Desk holding only the applet NAME, or for the check
    NAME of Desk holding one applet."""

    journeys = {
        "pad": PadAloneJourney,
        "fexp": FexpAloneJourney,
        "daybook": DaybookAloneJourney,
        "streams": StreamsAloneJourney,
        "agent": AgentAloneJourney,
        "small-terminal": SmallTerminalJourney,
    }
    if name not in journeys:
        raise ValueError(f"no journey for Desk with only {name!r}")
    return journeys[name](ready_markers)
