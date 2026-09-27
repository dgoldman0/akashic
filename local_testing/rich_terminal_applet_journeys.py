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

import mixed_text
from rich_terminal_desktop_acceptance import (
    DAYBOOK_MENU_SIGNATURE,
    DAYBOOK_PROMPT_MARKER,
    PAD_MENU_SIGNATURE,
    FrameBoundJourney,
    JourneyProgress,
    PhysicalDesktopAcceptanceError,
    RichScreenProjection,
    _claim_item_text,
    _collection_claims_in,
    _desk_content_bounds,
    _require_cell_text_in,
    _require_pad_readout,
    _residual_contains,
    _text_area_pointer_state,
    _text_cell_in,
)

PAD_ALONE_FOCUS_MARKER = "[1:Akashic Pa*]"
DAYBOOK_ALONE_FOCUS_MARKER = "[1:Daybook*]"
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

        lineage = self._offer_lineage(offer, generation)
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
            if self.focus_marker not in self._taskbar_line(projection):
                # Desk starts its applet without focus; Alt+1 gives it.
                self.waiting = f"{self.focus_marker} after Alt+1"
                self._send("send_key", "alt+1", 0, offer, generation, sender)
                return False
        elif self.focus_marker not in self._taskbar_line(projection):
            raise PhysicalDesktopAcceptanceError(
                f"the applet lost focus: {self._taskbar_line(projection).strip()!r}"
            )
        return True

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
    """Desk with Pad: type text that mixes scripts into its empty buffer.

    Pad's TEXT_AREA must carry the line logically and its CELL cells show it
    in visual order.  A click on the combined accent places the caret at its
    start; Right moves over both its scalars; Backspace after the emoji
    sequence deletes all of it, and Ctrl+Z restores it; and a click inside
    the Hebrew word lands on that letter.  The terminal sends the typed line,
    longer than one TEXT event allows, as several events.  Pad's Ln/Col
    readout counts characters in every frame that moves the caret.
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
    ) = range(8)

    def __init__(self, ready_markers: tuple[str, ...]):
        super().__init__(ready_markers)
        self._editor_bounds: tuple[int, int, int, int] | None = None
        self._before: tuple[int, int] | None = None

    @property
    def final_stage(self) -> int:
        return self.IN_HEBREW

    @property
    def final_cell_markers(self) -> tuple[str, ...]:
        return (self.focus_marker, mixed_text.visual(mixed_text.PAD_TEXT))

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
        return self._done("pad-caret-placed-in-hebrew", offer)

    def _send_from(self, state, milestone, method, value, target, offer, generation,
                   sender) -> JourneyProgress:
        """Send one input, remembering the caret it starts from."""

        self._before = state.primary
        return self._step(milestone, method, value, target, offer, generation, sender)


class DaybookAloneJourney(_AppletJourney):
    """Desk with Daybook: add a task that mixes scripts through its prompt.

    The prompt shows the typed text in visual order.  Backspace after an
    emoji sequence deletes all of it; a click on a Han character's second
    cell puts the caret before that character, where one typed character
    lands; and Enter adds the task, which the agenda then shows.  While the
    prompt is open, Daybook's menu and calendar grid are withheld, as the
    document-atomic fallback requires, and its cells stay complete.
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
    ) = range(8)

    def __init__(self, ready_markers: tuple[str, ...]):
        super().__init__(ready_markers)
        self._field: tuple[int, int] | None = None  # (column, row)
        self._han_column = 0

    @property
    def final_stage(self) -> int:
        return self.ADDED

    @property
    def final_cell_markers(self) -> tuple[str, ...]:
        return (self.focus_marker, mixed_text.visual(mixed_text.DAYBOOK_ENTRY))

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
            if projection.menu_signatures or collections:
                raise PhysicalDesktopAcceptanceError(
                    "Daybook's prompt did not withhold its menu and collections"
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
            return self._added(offer, projection, bounds, entry)
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

    def _added(self, offer, projection, bounds, entry) -> JourneyProgress:
        visual = mixed_text.visual(entry)
        left, top, right, bottom = bounds
        if not any(
            projection.find_cells(visual, row, left, right) for row in range(top, bottom)
        ):
            return JourneyProgress()
        _require_cell_text_in(offer, visual, bounds, _WHERE)
        return self._done("daybook-mixed-task-added", offer)


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
    """The journey for Desk holding only the applet NAME."""

    journeys = {"pad": PadAloneJourney, "daybook": DaybookAloneJourney}
    if name not in journeys:
        raise ValueError(f"no journey for Desk with only {name!r}")
    return journeys[name](ready_markers)
