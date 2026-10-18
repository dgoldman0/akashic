"""Journeys for Desk with a single applet, through the physical viewer.

While an applet's work is under way, Desk runs with just that applet (the
desktop-apt1-<name> profiles) and one of these journeys checks the work
through the same reference-sink runner as the canonical Desktop journey.
The canonical journey then runs once, across every applet, as regression.

With one applet, Desk gives it the whole content area above the taskbar,
and its taskbar button is slot 1.
"""

from __future__ import annotations

from rich_terminal.pygame_view import ATTR_REVERSE
from rich_terminal.retained_scene import ControlKind, ControlState, StatusSeverity
from rich_terminal.retained_wire import RetainedMessageType
from rich_terminal.semantic_documents import BlockKind
from rich_terminal.semantic_fields import FieldKind
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
    SOUNDLAB_FREQUENCY_FIELD,
    SOUNDLAB_FREQUENCY_PROMPT,
    SOUNDLAB_LANDMARK_CAPTION,
    DAYBOOK_MENU_SIGNATURE,
    DAYBOOK_PROMPT_MARKER,
    FEXPLORER_DELETE,
    FEXPLORER_DELETE_QUESTION,
    FEXPLORER_MENU_SIGNATURE,
    FEXPLORER_PICTURE,
    FEXPLORER_PICTURE_FACTS,
    PAD_MENU_SIGNATURE,
    FrameBoundJourney,
    JourneyProgress,
    PhysicalDesktopAcceptanceError,
    RichScreenProjection,
    _claim_item_runs,
    _cancel_of_confirm,
    _claim_item_text,
    _collection_claims_in,
    _desk_content_bounds,
    _desk_prompt_claim,
    _field_claims_in,
    _dialog_claim,
    _image_claims_in,
    _notice_claim,
    _prompt_claim,
    _require_cell_text_in,
    _require_desk_launcher_dialog,
    _require_held_beneath_overlay,
    _require_notice,
    _require_pad_readout,
    _require_picture_facts_in,
    _require_soundlab_landmark_cells,
    _soundlab_landmarks,
    _visible_draw_rectangle,
    _residual_contains,
    _status_field_claims_in,
    _tab_in,
    _tab_value,
    _taskbar_has_focus,
    _text_area_pointer_state,
)
from rich_terminal.retained_view import PlotDraw, PolylineDraw, TextGridDraw

PAD_ALONE_FOCUS_MARKER = "[1:Akashic Pa*]"
# A confirm question offers its verb, destructive, beside Cancel, the
# default; the journeys answer Cancel.  Ctrl+W on Pad's edited buffer asks
# before discarding it, and Delete in File Explorer before deleting the
# selected item, as in the full Desktop journey.
PAD_CLOSE_QUESTION = "Discard unsaved changes?"
PAD_CLOSE_DISCARD = "Discard"
DAYBOOK_DELETE_QUESTION = "Delete the selected automation?"
DAYBOOK_DELETE = "Delete"
FEXP_ALONE_FOCUS_MARKER = "[1:File Explo*]"
# The canonical Desktop image's large sample sits in the root directory,
# beside its sample picture.
FEXP_FILE = "large.txt"
# F2 renames the selected file through a prompt labelled so; the journey
# selects the name's stem, types over it, and enters the new name, which
# File Explorer then keeps selected while its notice says it was renamed.
FEXP_RENAME_LABEL = "Rename:"
# File Explorer's Go to prompt opens holding the folder shown, the root; the
# path typed after it names nothing, so File Explorer warns.
FEXP_GOTO_LABEL = "Go to:"
FEXP_GOTO_MISSING = "no-such-folder"
FEXP_GOTO_NOTICE = "Path not found"
FEXP_RENAME_STEM = "large"
FEXP_RENAME_TYPED = "notes"
FEXP_RENAMED = FEXP_RENAME_TYPED + FEXP_FILE[len(FEXP_RENAME_STEM):]
FEXP_RENAMED_NOTICE = "Renamed"
# The photo check's picture, a real photograph wider than File Explorer's
# preview at its largest on the physical viewer (assets/pictures/README.md),
# and what its CELL view says it is while the rich side shows it.
FEXP_PHOTO = "spice-market.qoi"
FEXP_PHOTO_SIZE = (2160, 1620)
FEXP_PHOTO_FACTS = "QOI, 2160 \u00d7 1620"
# A picture file the terminal cannot decode (akashic_tui.py's damaged
# check), and what CELL says of it once the terminal has refused it.
FEXP_DAMAGED = "damaged.png"
FEXP_DAMAGED_REASON = "The picture is damaged"
# Every line of large.txt starts so; its preview opens at the end of the
# text, where loading leaves the caret.
FEXP_TEXT_LINE = "Large fixture line"
# The canonical image's sample Markdown document (akashic_tui.py), which
# File Explorer previews as a document: its first block, the text of its
# last, holding a link back to the first heading, and its link to notes.md,
# whose paragraph shows once File Explorer previews that file.
FEXP_DOCUMENT = "guide.md"
FEXP_DOCUMENT_HEADING = "A guide to Akashic"
FEXP_DOCUMENT_END = "Back to the top"
FEXP_DOCUMENT_TOP_LINK = "the top"
FEXP_DOCUMENT_FILE_LINK = "Notes"
FEXP_LINKED_NAME = "notes.md"
FEXP_LINKED_TEXT = "Read the example and try it."
# The canonical image's sample PDF (sample_pdf.py), which File Explorer
# previews as a document read a page at a time: its first page's title, its
# link to its last page and that page's code, its outline as the contents'
# tree shows it (each entry's depth and title, the title's entry open, as
# the file says), the entry that shows its second page, the facts CELL
# shows beneath that page's JPEG photograph while the rich side shows it,
# and the copy encrypted with the empty password.
FEXP_PDF = "sample.pdf"
FEXP_PDF_ENCRYPTED = "encrypted.pdf"
FEXP_PDF_TITLE = "A sample PDF"
FEXP_PDF_LAST_LINK = "the last page"
FEXP_PDF_CODE = "Some code, in a fixed-pitch font:"
FEXP_PDF_OUTLINE = ((0, "A sample PDF"), (1, "Lists"), (0, "Pictures"), (0, "The end"))
FEXP_PDF_PICTURES = "Pictures"
FEXP_PDF_PHOTO_FACTS = "JPEG, 160 \u00d7 100"
# Wheel detents a scroll step sends; the document view scrolls three rows
# a detent.
FEXP_DOCUMENT_DETENTS = 3
FEXP_TABLE_COLUMNS = (
    (ItemColumnKind.TEXT, "Name"),
    (ItemColumnKind.NUMBER, "Size"),
    (ItemColumnKind.TEXT, "Type"),
)
PAD_OPEN_PROMPT_MARKER = "Open:"
DAYBOOK_ALONE_FOCUS_MARKER = "[1:Daybook*]"
# The notice Desk shows when the reminder the Daybook-alone boot makes
# fires (akashic_tui.DAYBOOK_REMINDER_TITLE).
DAYBOOK_REMINDER_NOTICE = "Reminder: Water the plants"
# The daily reminder that boot makes too (akashic_tui.DAYBOOK_DAILY_TITLE),
# first due tomorrow, and the section of Daybook's automations it is in.
DAYBOOK_DAILY_SCHEDULE = "Stretch"
DAYBOOK_ACTIVE_SECTION = "ACTIVE"
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
# A feed source the journey adds in Streams' Sources view: its card's
# fields, enabled at revision 1 and then switched off at revision 2.  The
# fourth says how its last refresh went, which depends on the refreshes
# Desk composes, not on the card.
STREAMS_NO_SOURCES = "No sources configured"
STREAMS_FEED_PROMPT = "HTTPS feed URL:"
STREAMS_FEED_URL = "https://example.test/streams/feed.xml"
STREAMS_SOURCE_CARD = (
    "Syndication feed",
    "syndication / auto  revision 1",
    STREAMS_FEED_URL,
    "last ",
    "no retained observations",
)


def _source_card_reads(fields: tuple[str, ...], card: tuple[str, ...]) -> bool:
    return (
        len(fields) == len(card)
        and all(f == c for i, (f, c) in enumerate(zip(fields, card)) if i != 3)
        and fields[3].startswith(card[3])
    )
AGENT_ALONE_FOCUS_MARKER = "[1:Agent*]"
AGENT_PROMPT_MARKER = "Ask:"
AGENT_MENU_SIGNATURE = ("Agent", "Run", "Connection", "Access", "Review", "Help")
# The demo provider asks for approval when a request names one.
AGENT_REQUEST = "approval check"
AGENT_REVIEW_MARKER = "Provider approval request (no local tool envelope)"
AGENT_REVIEW_REASON = "Persist the simulated change?"
# The Agent's review: a dialog titled Review required whose Approve once,
# which F6 chooses, waits for the review's last line, beside Deny, which F7
# chooses, the default and cancel button.  While more of the review lies
# below, the last line in view says so.
AGENT_REVIEW_TITLE = "Review required"
AGENT_REVIEW_BUTTONS = (("Approve once", "F6"), ("Deny", "F7"))
DIALOG_MORE = "PgDn: more below"
# The Agent alone runs on the device-flow fixture, whose provider records
# the approval under its own ID.
AGENT_AUDIT = (
    "Approved agent action: provider org.akashic.agent.testing.device-flow: "
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
# A long request asks for a review whose reason has a line for each of a
# hundred simulated changes, taller than the review's dialog: the wheel
# scrolls it, and Approve once waits until its last line has been shown.
AGENT_LONG_REQUEST = "long approval check"
AGENT_LONG_CHANGES = 100
AGENT_LONG_REASON = AGENT_REVIEW_REASON + "".join(
    f"\nSimulated change {change} of {AGENT_LONG_CHANGES}."
    for change in range(1, AGENT_LONG_CHANGES + 1)
)
AGENT_LONG_LAST = f"Simulated change {AGENT_LONG_CHANGES} of {AGENT_LONG_CHANGES}."
AGENT_LONG_EXCHANGE = (
    ("YOU", AGENT_LONG_REQUEST),
    (
        "AGENT",
        "Connected through Akashic's provider-neutral runtime. "
        f"You asked: {AGENT_LONG_REQUEST} Approved.",
    ),
    ("SYSTEM", AGENT_LONG_REASON),
    ("SYSTEM", "Approved agent action: provider org.akashic.agent.testing.device-flow: "
     + AGENT_LONG_REASON),
)
# Wheel detents a step over the long review sends; a dialog scrolls three
# rows a detent.
AGENT_REVIEW_DETENTS = 5
# One wheel detent scrolls a list three screen rows.
AGENT_WHEEL_ROWS = 3
# The Agent alone runs on the device-flow fixture's catalog: Swift, with Low
# or Medium reasoning and no speed tiers, then Deliberate, with Low or High
# reasoning and a Fast tier.  Its run settings are four CHOICE fields.
AGENT_SETTINGS_LABELS = ("Model", "Reasoning", "Speed", "Verbosity")
AGENT_SETTINGS_SHOWN = {
    "Model": "Swift", "Reasoning": "Low", "Speed": "Standard", "Verbosity": "Auto",
}
AGENT_SETTINGS_CHOSEN = {
    "Model": "Deliberate", "Reasoning": "High", "Speed": "Standard", "Verbosity": "Auto",
}
# Typed into Desk's own Ask prompt, whose second to fourth characters are
# then selected and typed over before Escape cancels it.
DESK_PROMPT_TEXT = "hello"
DESK_PROMPT_OVER = "EL"
# The canonical image's large sample: 48 lines, too much text for the small
# terminal once Pad shows it.
SMALL_TERMINAL_LARGE_PATH = "/large.txt"
SMALL_TERMINAL_LARGE_LINE = "Large fixture line 001"
_WHERE = "Desk's single tile"
# Sound Lab alone sets a new frequency through its prompt, as the Desktop
# journey does: 880, or 660 if it already shows 880.
SOUNDLAB_ALONE_FOCUS_MARKER = "[1:Sound Lab*]"
SOUNDLAB_ALONE_FREQUENCIES = (880, 660)
# Desk holds Observatory, then Worlds, each in half the screen.  Observatory
# starts with its own eight-sample series, ticks 0 to 7 falling from 8000 by
# 500; Worlds steps its run three times and hands the run's telemetry to
# Observatory through Analyze, which Observatory then profiles again on R.
OBSERVATORY_FOCUS_MARKER = "[1:Observatory*]"
WORLDS_FOCUS_MARKER = "[2:Worlds*]"
OBSERVATORY_DEMO_SERIES = tuple((tick, 8000 - 500 * tick) for tick in range(8))
OBSERVATORY_PLOT_CAPTION = "Upper amount projection"
OBSERVATORY_PLOT_LINE = (0x5F, 0xD7, 0xFF, 0xFF)
OBSERVATORY_BASELINE = (0x4E, 0x4E, 0x4E, 0xFF)
WORLDS_STEPS = 3
OBSERVATORY_PROFILED = "Profiled "
# The frames the terminal counts that show a picture's upload beside the
# screen's own frames (APT-1-RETAINED-1 section 8).
_UPLOAD_FRAMES = {
    "resource_begin": RetainedMessageType.RESOURCE_BEGIN,
    "resource_chunk": RetainedMessageType.RESOURCE_CHUNK,
    "resource_commit": RetainedMessageType.RESOURCE_COMMIT,
    "resource_abort": RetainedMessageType.RESOURCE_ABORT,
    "present_commit": RetainedMessageType.PRESENT_COMMIT,
}


def _status_shows(projection: RichScreenProjection, marker: str, bounds) -> bool:
    """MARKER in a status bar within BOUNDS: in residual glyphs, or in the
    authored label or value of a status field the rich frame carries."""

    return _residual_contains(projection, marker, bounds) or any(
        marker in claim.label or marker in claim.value
        for claim in _status_field_claims_in(projection, bounds)
    )


class _AppletJourney(FrameBoundJourney):
    """A journey through Desk holding the one applet FOCUS_MARKER names."""

    focus_marker = ""
    # A painted overlay, such as the Agent's review, withholds the applet's
    # only menu bar; each journey checks the menu itself.
    requires_menu_bar = False

    def _desk_prompt_expected(self) -> bool:
        """Whether Desk's own prompt may hold the taskbar row now."""

        return False

    def _admit(self, offer, generation, projection, sender) -> bool:
        """Whether the journey may act on this frame: one newer than its last
        input's frame, in the session's lineage, once any pointer gesture the
        guest owes is complete, with the applet up and focused.  While Desk's
        own prompt is expected it may hold the taskbar row instead."""

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
        elif not _taskbar_has_focus(projection, self.focus_marker) and not (
            self._desk_prompt_expected() and _desk_prompt_claim(projection) is not None
        ):
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

    def _step(self, milestone, method, value, target, offer, generation, sender):
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

    Ctrl+W on the edited buffer asks first: Pad's dialog, in a modal region
    over its tile with Pad's menu bar and every root it does not cover rich
    and inactive beneath it, offers Discard, destructive, and Cancel, the
    default.  Pressing Cancel closes the dialog and keeps the buffer.

    Pad then opens notes.md through its Open prompt, a TEXT field in a
    modal region over Pad's tile while Pad's menu bar and editor stay rich
    and inactive beneath it.  Its TEXT_AREA carries the heading's, link's,
    and strong text's style runs, and a FOLLOW on the link, sent where the
    viewer finds the link as a Ctrl press would, opens example.f, whose
    keywords its runs mark.
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
        CLOSE_ASKED,
        CLOSE_CANCELLED,
        OPEN_PROMPT,
        PATH_TYPED,
        NOTES_OPENED,
        LINK_FOLLOWED,
    ) = range(14)

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
        if self.stage >= self.CLOSE_ASKED:
            return self._close_question(offer, generation, projection, sender)
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
                               "ctrl+w", self.CLOSE_ASKED, offer, generation, sender)

    def _close_question(self, offer, generation, projection, sender) -> JourneyProgress:
        """Ctrl+W asks before it discards the edited buffer; Cancel keeps it."""

        bounds = _desk_content_bounds(projection)
        dialog = _dialog_claim(projection, PAD_CLOSE_QUESTION, bounds)
        if self.stage == self.CLOSE_ASKED:
            if dialog is None:
                return self._wait("Pad's question after Ctrl+W")
            value = _cancel_of_confirm(offer, projection, dialog, bounds, PAD_CLOSE_DISCARD,
                                       PAD_MENU_SIGNATURE, "Pad", _WHERE)
            return self._step("pad-close-question-shown", "activate_button", value,
                              self.CLOSE_CANCELLED, offer, generation, sender)
        if dialog is not None:
            return self._wait("Pad's question to close after Cancel")
        if projection.menu_signatures != (PAD_MENU_SIGNATURE,):
            return self._wait("Pad's menu bar after its question")
        claim = self._editor(projection)
        if claim is None:
            return self._wait("Pad's editor after its question")
        if _claim_item_text(claim, 1) != mixed_text.PAD_TEXT:
            raise PhysicalDesktopAcceptanceError(
                f"Cancel did not keep Pad's buffer: {_claim_item_text(claim, 1)!r}"
            )
        return self._step("pad-close-cancelled", "send_key", "ctrl+o",
                          self.OPEN_PROMPT, offer, generation, sender)

    def _styled(self, offer, generation, projection, sender) -> JourneyProgress:
        """Open notes.md, check its style runs, and follow its link."""

        bounds = _desk_content_bounds(projection)
        prompt = _prompt_claim(projection, PAD_OPEN_PROMPT_MARKER, bounds)
        if prompt is not None:
            _require_held_beneath_overlay(projection, prompt, bounds, PAD_MENU_SIGNATURE, "Pad")
            if not _collection_claims_in(projection, ControlKind.TEXT_AREA, bounds):
                raise PhysicalDesktopAcceptanceError(
                    "Pad's prompt withheld its editor"
                )
        if self.stage == self.OPEN_PROMPT:
            if prompt is None:
                return self._wait("Pad's Open prompt after Ctrl+O")
            if prompt.content.text:
                raise PhysicalDesktopAcceptanceError(
                    f"Pad's Open prompt opened holding {prompt.content.text!r}"
                )
            _require_cell_text_in(offer, PAD_OPEN_PROMPT_MARKER, bounds, _WHERE)
            return self._step("pad-open-prompt-shown", "send_text",
                              styled_text.NOTES_PATH, self.PATH_TYPED, offer,
                              generation, sender)
        if self.stage == self.PATH_TYPED:
            if prompt is None:
                raise PhysicalDesktopAcceptanceError(
                    "Pad's Open prompt closed before its path was entered"
                )
            if prompt.content.text != styled_text.NOTES_PATH:
                return self._wait("the typed path in Pad's Open prompt")
            if prompt.content.caret != len(styled_text.NOTES_PATH):
                raise PhysicalDesktopAcceptanceError(
                    f"Pad's Open prompt has its caret at {prompt.content.caret}"
                )
            return self._step("pad-notes-path-typed", "send_key", "enter",
                              self.NOTES_OPENED, offer, generation, sender)
        if prompt is not None:
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
    check it off in the agenda, ask to delete the daily reminder and keep it,
    then see the notice of the reminder the boot made when Desk fires it.

    The prompt is a TEXT field in a modal region over Daybook's tile: it
    carries the typed text logically while its CELL cells show it in visual
    order.  Backspace after an emoji sequence deletes all of it; a PLACE at
    a Han character, sent where the viewer lays that character out, puts the
    caret before it, where one typed character lands; and Enter adds the
    task.  The agenda is a SECTIONS item view, and the task is an unchecked
    checkable item under the TASKS heading; a CHECK on it marks it done.
    While the prompt is open, Daybook's menu, calendar grid and agenda stay
    rich beneath it and inactive, and its cells stay complete.  F4 then
    shows Daybook's automations, a SECTIONS item view too; a SELECT on the
    daily reminder and Delete ask first, in a DIALOG whose Delete is
    destructive and whose Cancel is the default, and an ACTIVATE on Cancel
    keeps the reminder.  F4 returns to the calendar, and the reminder's
    notice must then reach the physical frame: the app shell's notice, a
    neutral DIALOG with the NOTICE flag on the bottom row, in a region of its
    own over Desk's taskbar, as CELL shows it there too.
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
        AUTOMATIONS,
        SCHEDULE_SELECTED,
        DELETE_ASKED,
        DELETE_CANCELLED,
        CALENDAR,
        NOTICE_WAIT,
        NOTICE,
    ) = range(16)

    def __init__(self, ready_markers: tuple[str, ...]):
        super().__init__(ready_markers)
        self._han_cell: tuple[int, int] | None = None  # (row, column) in CELL

    @property
    def final_stage(self) -> int:
        return self.NOTICE

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
        if self.AUTOMATIONS <= self.stage <= self.CALENDAR:
            return self._automations(offer, generation, projection, bounds, sender)
        prompt = _prompt_claim(projection, DAYBOOK_PROMPT_MARKER, bounds)
        collections = tuple(
            claim
            for kind in (ControlKind.TEXT_AREA, ControlKind.TEXT_GRID)
            for claim in _collection_claims_in(projection, kind, bounds)
        )
        if prompt is not None:
            _require_held_beneath_overlay(
                projection, prompt, bounds, DAYBOOK_MENU_SIGNATURE, "Daybook"
            )
            if (
                not any(claim.kind is ControlKind.TEXT_GRID for claim in collections)
                or self._agenda(projection, bounds) is None
            ):
                raise PhysicalDesktopAcceptanceError(
                    "Daybook's prompt withheld its calendar or agenda"
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
            if prompt is not None:
                raise PhysicalDesktopAcceptanceError("Daybook's prompt was already open")
            return self._step("daybook-ready", "send_key", "ctrl+n", self.PROMPT,
                              offer, generation, sender)
        if self.stage == self.ADDED:
            # Enter closes the prompt; the agenda then shows the task.
            if prompt is not None:
                return JourneyProgress()
            return self._added(offer, generation, projection, bounds, entry, sender)
        if self.stage == self.CHECKED:
            agenda = self._agenda(projection, bounds)
            task = None if agenda is None else self._task(agenda, entry)
            if task is None or not task.state & ItemState.CHECKED:
                return JourneyProgress()
            _require_cell_text_in(offer, "[x]", bounds, _WHERE)
            return self._step("daybook-task-checked", "send_key", "f4",
                              self.AUTOMATIONS, offer, generation, sender)
        if self.stage == self.NOTICE_WAIT:
            notice = _notice_claim(projection, DAYBOOK_REMINDER_NOTICE)
            if notice is None:
                return self._wait(f"Desk's notice {DAYBOOK_REMINDER_NOTICE!r}")
            _require_notice(offer, notice, StatusSeverity.NEUTRAL)
            return self._done("daybook-reminder-notice", offer)
        if prompt is None:
            if self.stage == self.PROMPT:
                return JourneyProgress()
            raise PhysicalDesktopAcceptanceError("Daybook's prompt closed early")
        text = prompt.content.text
        if self.stage == self.PROMPT:
            if text:
                raise PhysicalDesktopAcceptanceError(
                    f"Daybook's prompt opened holding {text!r}"
                )
            return self._step("daybook-prompt-opened", "send_text", head,
                              self.HEAD_TYPED, offer, generation, sender)
        if self.stage == self.HEAD_TYPED:
            if text != head:
                return JourneyProgress()
            return self._step("daybook-prompt-head-typed", "send_key", "backspace",
                              self.EMOJI_DELETED, offer, generation, sender)
        if self.stage == self.EMOJI_DELETED:
            if text == head:
                return JourneyProgress()
            if text != shortened:
                raise PhysicalDesktopAcceptanceError(
                    "Backspace in Daybook's prompt did not delete the whole emoji "
                    f"sequence: {text!r}"
                )
            return self._step("daybook-emoji-sequence-deleted", "send_text",
                              task[len(shortened):], self.TASK_TYPED, offer,
                              generation, sender)
        if self.stage == self.TASK_TYPED:
            # The guest may paint between typed characters.
            if text != task:
                return JourneyProgress()
            _require_cell_text_in(offer, mixed_text.visual(task), bounds, _WHERE)
            cells = [
                (row, column)
                for row, column in offer.cell.find(mixed_text.DAYBOOK_HAN)
                if row == prompt.top
            ]
            if len(cells) != 1:
                raise PhysicalDesktopAcceptanceError(
                    "Daybook's prompt does not show its Han character once"
                )
            self._han_cell = cells[0]
            identity = prompt.identity
            value = (f"{identity.owner_id},{identity.owner_generation},"
                     f"{identity.control_id},0,{task.index(mixed_text.DAYBOOK_HAN)}")
            return self._step("daybook-mixed-task-typed", "text_place", value,
                              self.CLICKED, offer, generation, sender)
        if self.stage == self.CLICKED:
            # The caret is now before the Han character, and CELL's focused
            # caret marks its cells.
            row, column = self._han_cell
            if prompt.content.caret != task.index(mixed_text.DAYBOOK_HAN):
                return JourneyProgress()
            if not offer.cell.cells[row][column].attrs & ATTR_REVERSE:
                return JourneyProgress()
            return self._step("daybook-prompt-caret-on-han", "send_text",
                              mixed_text.DAYBOOK_INSERT, self.INSERTED, offer,
                              generation, sender)
        if text != entry:
            return JourneyProgress()
        return self._step("daybook-prompt-text-inserted-at-click", "send_key", "enter",
                          self.ADDED, offer, generation, sender)

    def _automations(self, offer, generation, projection, bounds, sender):
        """Ask to delete the daily reminder from Daybook's automations, keep
        it through Cancel, and return to the calendar."""

        dialog = _dialog_claim(projection, DAYBOOK_DELETE_QUESTION, bounds)
        if self.stage == self.DELETE_ASKED:
            if dialog is None:
                return self._wait("Daybook's question after Delete")
            value = _cancel_of_confirm(offer, projection, dialog, bounds, DAYBOOK_DELETE,
                                       DAYBOOK_MENU_SIGNATURE, "Daybook", _WHERE)
            return self._step("daybook-delete-question-shown", "activate_button", value,
                              self.DELETE_CANCELLED, offer, generation, sender)
        if dialog is not None:
            return self._wait("Daybook's question to close after Cancel")
        if self.stage == self.CALENDAR:
            agenda = self._agenda(projection, bounds)
            task = None if agenda is None else self._task(agenda, mixed_text.DAYBOOK_ENTRY)
            if task is None or not _collection_claims_in(
                projection, ControlKind.TEXT_GRID, bounds
            ):
                return self._wait("Daybook's calendar after F4")
            if not task.state & ItemState.CHECKED:
                raise PhysicalDesktopAcceptanceError(
                    "Daybook's task lost its check in the automations"
                )
            self.stage = self.NOTICE_WAIT
            self.frame_barrier = offer.offer_id
            return JourneyProgress(self._milestone("daybook-calendar-shown-again"))
        automations = self._agenda(projection, bounds)
        schedule = None if automations is None else automations.named(DAYBOOK_DAILY_SCHEDULE)
        if schedule is None:
            if (
                self.stage == self.DELETE_CANCELLED
                and automations is not None
                and automations.named(DAYBOOK_ACTIVE_SECTION) is not None
            ):
                raise PhysicalDesktopAcceptanceError(
                    "Cancel did not keep Daybook's daily reminder"
                )
            return self._wait(f"Daybook's automations listing {DAYBOOK_DAILY_SCHEDULE!r}")
        if self.stage == self.AUTOMATIONS:
            return self._step("daybook-automations-shown", "item_select",
                              automations.value(schedule.item_key),
                              self.SCHEDULE_SELECTED, offer, generation, sender)
        if self.stage == self.SCHEDULE_SELECTED:
            selected = automations.selected
            if selected is None or selected.item_key != schedule.item_key:
                return self._wait(f"{DAYBOOK_DAILY_SCHEDULE!r} selected")
            return self._step("daybook-daily-reminder-selected", "send_key", "delete",
                              self.DELETE_ASKED, offer, generation, sender)
        _require_cell_text_in(offer, DAYBOOK_DAILY_SCHEDULE, bounds, _WHERE)
        return self._step("daybook-delete-cancelled", "send_key", "f4",
                          self.CALENDAR, offer, generation, sender)

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
    """Desk with File Explorer: select a file, then preview a picture, and
    open a directory in its detail table, then expand, select, and collapse
    in its folder tree, all through item and tab events.

    The detail table is a TABLE item view with Name, Size (a number column),
    and Type columns, and the sidebar a TREE whose root is "/".  A SELECT
    on large.txt's row selects it and the status bar shows its path.  F2
    opens the rename prompt holding the name, a TEXT field in a modal region
    over the tile with the table and tree rich and inactive beneath it; a
    PLACE at the name's start and an EXTEND to the end of its stem, as the
    viewer sends a drag, select the stem, typing replaces it, and Enter
    renames large.txt to notes.txt, which stays selected while File
    Explorer says it was renamed in a neutral notice.  Delete then asks
    before it deletes the file: File Explorer's dialog, in a modal region
    over the tile with its menu bar and every root it does not cover rich
    and inactive beneath it, offers Delete, destructive, and Cancel, the
    default, and pressing Cancel closes it and leaves the file listed and
    selected.  Ctrl+G opens the Go to prompt holding the folder shown, the
    root, and a path typed after it names nothing: Enter closes the prompt,
    and File Explorer warns that the path was not found, in the app shell's
    notice, a DIALOG with the NOTICE flag and the warning's meaning on the
    bottom row, as CELL shows it there too.  A
    SELECT on sunset.qoi's row loads its preview, and activating the
    Preview tab shows it: the rich frame shows it as an IMAGE once the
    terminal holds it, while CELL beneath shows what the picture is and
    draws none of it.  Activating the Details tab brings the table back
    and the picture goes.  The Preview tab shows it again; notes.txt's
    preview is text, with no picture; and guide.md's is a DOCUMENT from its
    first heading, with its figure, the same picture, in view and shown
    rich as an IMAGE in the picture rows the document leaves it.  SCROLL
    moves it down until its last block shows, on the way showing the figure
    partly scrolled out: the IMAGE keeps the figure's whole rectangle and
    paints only the part the document shows.  A FOLLOW on the last block's
    link to the first heading puts the heading back at the top, and a
    FOLLOW on its link to notes.md selects that file and previews it as a
    document too.  sample.pdf's preview is a DOCUMENT from its first
    page's start; a FOLLOW on its link to the last page shows that page;
    the key c shows its outline as a LIST in the document's place, and an
    OPEN on its Pictures entry shows the second page from its start, its
    JPEG photograph and its picture of samples each shown rich as an IMAGE,
    with CELL beneath saying what the photograph is.  encrypted.pdf, read
    with the empty password, shows the same title.  sunset.qoi, selected
    once more, shows rich again.  An OPEN on a directory's row lists that
    directory.  An EXPAND on the
    tree's root shows its entries, a SELECT on one of its directories lists
    that directory, and a COLLAPSE on the root hides them, which moves the
    selection back to the root and lists it again.  CELL shows the rows
    throughout.

    Last, Alt+H opens Desk's launcher, an overlay document that is a
    dialog titled Applets, modal over the whole screen, whose status and
    hint lines are its message and whose catalog, a two-column item view,
    lies active inside it; while it is open File Explorer's lists fall back
    beneath it.  An OPEN on its File Explorer row focuses the running
    applet and closes the launcher, and the lists come back.

    On a paced link the first preview's upload takes long enough to check
    that the screen keeps answering input while a picture uploads.  Once
    the terminal has taken some of the picture's chunks, an EXPAND on the
    tree's root must be answered by a frame the terminal commits while the
    upload is still open, before the picture arrives; more chunks follow
    it, and the picture then shows.  A COLLAPSE on the root puts the tree
    back before the journey goes on.
    """

    focus_marker = FEXP_ALONE_FOCUS_MARKER
    (
        READY,
        FILE_SELECTED,
        RENAME_PROMPT,
        RENAME_PLACED,
        RENAME_SELECTED,
        RENAME_TYPED,
        RENAMED,
        DELETE_ASKED,
        DELETE_CANCELLED,
        GOTO_PROMPT,
        GOTO_TYPED,
        GOTO_WARNED,
        PICTURE_SELECTED,
        PICTURE_PREVIEWED,
        PICTURE_DETAILS,
        PICTURE_PREVIEWED_AGAIN,
        PICTURE_DETAILS_AGAIN,
        TEXT_SELECTED,
        TEXT_PREVIEWED,
        TEXT_DETAILS,
        DOCUMENT_SELECTED,
        DOCUMENT_PREVIEWED,
        DOCUMENT_SCROLLED,
        DOCUMENT_TOP,
        LINKED_DOCUMENT,
        DOCUMENT_DETAILS,
        PDF_SELECTED,
        PDF_PREVIEWED,
        PDF_LAST_PAGE,
        PDF_CONTENTS,
        PDF_OUTLINE_CLOSED,
        PDF_PICTURES,
        PDF_DETAILS,
        ENCRYPTED_SELECTED,
        ENCRYPTED_PREVIEWED,
        ENCRYPTED_DETAILS,
        PICTURE_RESELECTED,
        PICTURE_PREVIEWED_LAST,
        DETAILS_SHOWN,
        DIRECTORY_OPENED,
        TREE_EXPANDED,
        TREE_CHILD_SELECTED,
        TREE_COLLAPSED,
        LAUNCHER_OPENED,
        LAUNCHER_CLOSED,
    ) = range(45)
    _DOCUMENT_STAGES = (DOCUMENT_PREVIEWED, DOCUMENT_SCROLLED, DOCUMENT_TOP,
                        LINKED_DOCUMENT)
    _PDF_STAGES = (PDF_PREVIEWED, PDF_LAST_PAGE, PDF_CONTENTS, PDF_OUTLINE_CLOSED,
                   PDF_PICTURES, ENCRYPTED_PREVIEWED)
    # Each Preview tab stage: what it shows, and the Details stage after it.
    _PREVIEWS = {
        PICTURE_PREVIEWED: (True, PICTURE_DETAILS),
        PICTURE_PREVIEWED_AGAIN: (True, PICTURE_DETAILS_AGAIN),
        TEXT_PREVIEWED: (False, TEXT_DETAILS),
        PICTURE_PREVIEWED_LAST: (True, DETAILS_SHOWN),
    }

    def __init__(self, ready_markers: tuple[str, ...], *, paced_link: bool = False):
        super().__init__(ready_markers)
        self._directory: str | None = None
        # The document's top, as (block key, rows above), before the last
        # scroll step.
        self._scrolled_from: tuple[int, int] | None = None
        # Whether a scroll step has shown the document's figure partly
        # scrolled out.
        self._figure_clipped = False
        # Whether a frame has shown File Explorer's notices, that the file
        # was renamed and the warning.  Each lasts a second or two, so the
        # input after it may be retried once it is gone.
        self._renamed = False
        self._warned = False
        # The upload check's step: pending, sent, answered, shown, or None
        # when there is none or it is over.
        self._probe = "pending" if paced_link else None
        self._frames: dict[str, int] | None = None
        self.evidence = {"paced_upload": {}} if paced_link else None

    @property
    def final_stage(self) -> int:
        return self.LAUNCHER_CLOSED

    @property
    def acts_between_frames(self) -> bool:
        # The screen may not change while the picture uploads, so the check
        # sends its input on the status that shows the upload under way.
        return self._probe == "pending" and self.stage == self.PICTURE_PREVIEWED

    def observe_status(self, status) -> None:
        rich = status.get("rich_terminal") if isinstance(status, dict) else None
        counts = rich.get("frames_by_type") if isinstance(rich, dict) else None
        if isinstance(counts, dict):
            self._frames = {
                name: int(counts.get(f"0x{int(kind):04X}", 0))
                for name, kind in _UPLOAD_FRAMES.items()
            }

    def _uploading(self) -> bool:
        """The terminal holds one upload open and has taken some chunks."""

        frames = self._frames
        return frames is not None and (
            frames["resource_begin"]
            == frames["resource_commit"] + frames["resource_abort"] + 1
        ) and frames["resource_chunk"] > 0

    def _record(self, step: str) -> dict[str, int]:
        frames = dict(self._frames)
        self.evidence["paced_upload"][step] = frames
        return frames

    def _probe_upload(self, offer, generation, projection, sender, pictures):
        """The upload check, while the first preview's picture uploads; None
        once it is over."""

        tree = self._tree(projection)
        if tree is None:
            return self._wait("File Explorer's folder tree")
        root = tree.content.items[0]
        expanded = bool(root.state & ItemState.EXPANDED) and any(
            item.parent_key == root.item_key for item in tree.content.items
        )
        if self._probe == "pending":
            if pictures:
                raise PhysicalDesktopAcceptanceError(
                    f"{FEXPLORER_PICTURE} arrived before input could be sent during "
                    "its upload; the paced link is too fast for this check"
                )
            if expanded:
                raise PhysicalDesktopAcceptanceError("the tree's root began expanded")
            if not self._uploading():
                return self._wait(f"{FEXPLORER_PICTURE}'s upload under way")
            self._record("sent")
            self._probe = "sent"
            return self._step("fexp-input-sent-during-upload", "item_expand",
                              tree.value(root.item_key), self.stage, offer,
                              generation, sender)
        sent = self.evidence["paced_upload"]["sent"]
        if self._probe == "sent":
            if not expanded:
                return self._wait("the tree's root expanded during the upload")
            answered = self._record("answered")
            if pictures or answered["resource_commit"] != sent["resource_commit"]:
                raise PhysicalDesktopAcceptanceError(
                    f"{FEXPLORER_PICTURE} arrived before the frame answering "
                    "input sent during its upload"
                )
            if answered["resource_abort"] != sent["resource_abort"]:
                raise PhysicalDesktopAcceptanceError(
                    f"{FEXPLORER_PICTURE}'s upload stopped while it still showed"
                )
            if answered["present_commit"] <= sent["present_commit"]:
                raise PhysicalDesktopAcceptanceError(
                    "the terminal committed no frame while the picture uploaded"
                )
            self._probe = "answered"
            self.frame_barrier = offer.offer_id
            return JourneyProgress(self._milestone("fexp-input-answered-during-upload"))
        if self._probe == "answered":
            if not pictures:
                return self._wait(f"{FEXPLORER_PICTURE} shown rich after its upload")
            shown = self._record("shown")
            answered = self.evidence["paced_upload"]["answered"]
            if shown["resource_commit"] <= sent["resource_commit"]:
                raise PhysicalDesktopAcceptanceError(
                    f"{FEXPLORER_PICTURE} shows with no committed upload"
                )
            if shown["resource_chunk"] <= answered["resource_chunk"]:
                raise PhysicalDesktopAcceptanceError(
                    "no chunk of the picture followed the frame answering input"
                )
            self._probe = "shown"
            return self._step("fexp-picture-shown-after-input", "item_collapse",
                              tree.value(root.item_key), self.stage, offer,
                              generation, sender)
        if expanded:
            return self._wait("the tree's root collapsed again")
        self._probe = None
        return None

    @property
    def final_cell_markers(self) -> tuple[str, ...]:
        return (self.focus_marker, FEXP_RENAMED)

    def _goto(self, offer, generation, sender, goto) -> JourneyProgress:
        """The Go to prompt: it opens holding the root; type a path that
        names nothing after it, and Enter."""

        if goto is None:
            if self.stage == self.GOTO_PROMPT:
                return self._wait("File Explorer's Go to prompt after Ctrl+G")
            raise PhysicalDesktopAcceptanceError("File Explorer's Go to prompt closed early")
        text = goto.content.text
        if self.stage == self.GOTO_PROMPT:
            if text != "/":
                raise PhysicalDesktopAcceptanceError(
                    f"File Explorer's Go to prompt opened holding {text!r}"
                )
            return self._step("fexp-goto-opened", "send_text", FEXP_GOTO_MISSING,
                              self.GOTO_TYPED, offer, generation, sender)
        typed = "/" + FEXP_GOTO_MISSING
        if text != typed:
            if typed.startswith(text):
                return self._wait("the path typed into the Go to prompt")
            raise PhysicalDesktopAcceptanceError(
                f"typing into File Explorer's Go to prompt gave {text!r}"
            )
        return self._step("fexp-goto-typed", "send_key", "enter", self.GOTO_WARNED,
                          offer, generation, sender)

    def _rename(self, offer, generation, projection, sender, rename) -> JourneyProgress:
        """The rename prompt: select the name's stem, type over it, enter it."""

        if rename is None:
            if self.stage == self.RENAME_PROMPT:
                return self._wait("File Explorer's rename prompt after F2")
            raise PhysicalDesktopAcceptanceError("the rename prompt closed early")
        content = rename.content
        identity = rename.identity
        value = f"{identity.owner_id},{identity.owner_generation},{identity.control_id},0,{{}}"
        if self.stage == self.RENAME_PROMPT:
            if content.text != FEXP_FILE:
                raise PhysicalDesktopAcceptanceError(
                    f"the rename prompt holds {content.text!r}, not {FEXP_FILE!r}"
                )
            _require_cell_text_in(offer, FEXP_RENAME_LABEL, _desk_content_bounds(projection),
                                  _WHERE)
            return self._step("fexp-rename-prompt-opened", "text_place", value.format(0),
                              self.RENAME_PLACED, offer, generation, sender)
        if content.text != FEXP_FILE and self.stage != self.RENAME_TYPED:
            raise PhysicalDesktopAcceptanceError(
                f"selecting in the rename prompt changed its text to {content.text!r}"
            )
        if self.stage == self.RENAME_PLACED:
            if content.caret != 0:
                return self._wait("the rename prompt's caret at its start")
            return self._step("fexp-rename-caret-placed", "text_extend",
                              value.format(len(FEXP_RENAME_STEM)), self.RENAME_SELECTED,
                              offer, generation, sender)
        if self.stage == self.RENAME_SELECTED:
            if (content.anchor, content.caret) != (0, len(FEXP_RENAME_STEM)):
                return self._wait("the name's stem selected")
            return self._step("fexp-rename-stem-selected", "send_text", FEXP_RENAME_TYPED,
                              self.RENAME_TYPED, offer, generation, sender)
        suffix = FEXP_FILE[len(FEXP_RENAME_STEM):]
        typed = FEXP_RENAME_TYPED + suffix
        # The guest may paint after each typed scalar.
        if content.text == FEXP_FILE or content.text in {
            FEXP_RENAME_TYPED[:length] + suffix for length in range(1, len(FEXP_RENAME_TYPED))
        }:
            return self._wait("the typed name")
        if content.text != typed:
            raise PhysicalDesktopAcceptanceError(
                f"typing over the selected stem gave {content.text!r}, not {typed!r}"
            )
        return self._step("fexp-rename-stem-replaced", "send_key", "enter",
                          self.RENAMED, offer, generation, sender)

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
    def _content_views(projection: RichScreenProjection, role):
        left, top, right, bottom = _desk_content_bounds(projection)
        return [
            claim
            for claim in projection.semantic_item_view_claims
            if left <= claim.left < claim.right <= right
            and top <= claim.top < claim.bottom <= bottom
            and claim.content.role is role
        ]

    @classmethod
    def _tree(cls, projection: RichScreenProjection):
        trees = cls._content_views(projection, ItemViewRole.TREE)
        return trees[0] if len(trees) == 1 else None

    @classmethod
    def _outline(cls, projection: RichScreenProjection, bounds):
        """The contents' tree shown in the document's place: the one TREE
        within the columns of the tabset holding the Preview tab, apart
        from the folder tree beside it; or None."""

        left, top, right, bottom = bounds
        tabsets = [
            tabset
            for tabset in projection.semantic_tabset_claims
            if left <= tabset.left < tabset.right <= right
            and top <= tabset.top < tabset.bottom <= bottom
            and any(tab.label == "Preview" for tab in tabset.tabs)
        ]
        if len(tabsets) != 1:
            return None
        trees = [
            view
            for view in cls._content_views(projection, ItemViewRole.TREE)
            if tabsets[0].left <= view.left < view.right <= tabsets[0].right
        ]
        return trees[0] if len(trees) == 1 else None

    @classmethod
    def _views(cls, projection: RichScreenProjection):
        tables = cls._content_views(projection, ItemViewRole.TABLE)
        trees = cls._content_views(projection, ItemViewRole.TREE)
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

    def _preview(self, offer, generation, projection, sender) -> JourneyProgress:
        """The Preview tab shows the picture rich, over what CELL says it is,
        or notes.txt's text with no picture; then the Details tab brings the
        table back."""

        picture, details_stage = self._PREVIEWS[self.stage]
        bounds = _desk_content_bounds(projection)
        _tab, selected = _tab_in(projection, bounds, "Preview", _WHERE)
        if not selected:
            return self._wait("the Preview tab selected")
        pictures = _image_claims_in(projection, bounds)
        if self._probe is not None and self.stage == self.PICTURE_PREVIEWED:
            progress = self._probe_upload(offer, generation, projection, sender, pictures)
            if progress is not None:
                return progress
        if picture:
            if not pictures:
                return self._wait(f"{FEXPLORER_PICTURE} shown rich")
            if len(pictures) != 1:
                raise PhysicalDesktopAcceptanceError(
                    f"File Explorer shows {len(pictures)} pictures for {FEXPLORER_PICTURE}"
                )
            shown, = pictures
            _require_picture_facts_in(
                offer, FEXPLORER_PICTURE_FACTS,
                (shown.left, shown.top, shown.right, shown.bottom), _WHERE,
            )
            milestone = f"fexp-picture-shown-{self.stage}"
        else:
            if pictures:
                return self._wait(f"{FEXPLORER_PICTURE} gone from the preview")
            if not any(
                FEXP_TEXT_LINE in line
                for claim in _collection_claims_in(projection, ControlKind.TEXT_AREA, bounds)
                for line in claim.visible_text
            ):
                return self._wait(f"{FEXP_RENAMED}'s text in the preview")
            milestone = "fexp-text-shown"
        details, _selected = _tab_in(projection, bounds, "Details", _WHERE)
        return self._step(milestone, "activate_tab", _tab_value(details),
                          details_stage, offer, generation, sender)

    @staticmethod
    def _document_claim(projection: RichScreenProjection, bounds):
        left, top, right, bottom = bounds
        documents = [
            claim
            for claim in projection.semantic_document_claims
            if left <= claim.left < claim.right <= right
            and top <= claim.top < claim.bottom <= bottom
        ]
        return documents[0] if len(documents) == 1 else None

    @staticmethod
    def _figure(projection: RichScreenProjection, document):
        """The document's figure with a row in view, as (block key, the
        rectangle its picture rows fill, the part shown), or None; and the
        IMAGE painting that part, or None while CELL shows it."""

        figures = [figure for figure in document.figures if figure[2] is not None]
        if not figures:
            return None, None
        if len(figures) != 1:
            raise PhysicalDesktopAcceptanceError(
                f"{FEXP_DOCUMENT} shows {len(figures)} figures"
            )
        figure = figures[0]
        images = [
            claim
            for claim in projection.semantic_image_claims
            if claim.figure == (document.identity, figure[0])
        ]
        return figure, images[0] if len(images) == 1 else None

    def _document(self, offer, generation, projection, sender) -> JourneyProgress:
        """guide.md's preview: a DOCUMENT from its first heading, with its
        figure shown rich, which the wheel scrolls to its end, showing the
        figure partly scrolled out on the way, whose link to that heading
        scrolls back, and whose link to notes.md selects and previews that
        file."""

        bounds = _desk_content_bounds(projection)
        _tab, selected = _tab_in(projection, bounds, "Preview", _WHERE)
        if not selected:
            return self._wait("the Preview tab selected")
        document = self._document_claim(projection, bounds)
        if self.stage == self.LINKED_DOCUMENT:
            if (
                document is None
                or document.block_with(FEXP_LINKED_TEXT) is None
                or not _status_shows(projection, "/" + FEXP_LINKED_NAME, bounds)
            ):
                return self._wait(f"{FEXP_LINKED_NAME} selected and previewed as a document")
            details, _selected = _tab_in(projection, bounds, "Details", _WHERE)
            return self._step("fexp-document-file-link-followed", "activate_tab",
                              _tab_value(details), self.DOCUMENT_DETAILS, offer,
                              generation, sender)
        if document is None:
            return self._wait(f"{FEXP_DOCUMENT} previewed as a document")
        top = document.top_block
        at_top = (
            top is not None
            and top.kind is BlockKind.HEADING
            and top.text == FEXP_DOCUMENT_HEADING
            and document.content.viewport_row == 0
        )
        if self.stage == self.DOCUMENT_PREVIEWED:
            if not at_top:
                return self._wait(f"{FEXP_DOCUMENT} shown from its first heading")
            _require_cell_text_in(offer, FEXP_DOCUMENT_HEADING, bounds, _WHERE)
            figure, image = self._figure(projection, document)
            if figure is None or figure[1] != figure[2]:
                raise PhysicalDesktopAcceptanceError(
                    f"{FEXP_DOCUMENT}'s figure is not wholly in view at its top"
                )
            if image is None:
                return self._wait(f"{FEXP_DOCUMENT}'s figure shown rich")
            # CELL beneath shows what the picture is and draws none of it.
            shown = figure[2]
            _require_picture_facts_in(
                offer, FEXPLORER_PICTURE_FACTS,
                (shown.left, shown.top, shown.right, shown.bottom), _WHERE,
            )
            self._figure_clipped = False
            self._scrolled_from = (top.block_key, 0)
            return self._step("fexp-document-shown", "document_scroll",
                              document.value(FEXP_DOCUMENT_DETENTS),
                              self.DOCUMENT_SCROLLED, offer, generation, sender)
        if self.stage == self.DOCUMENT_SCROLLED:
            now = None if top is None else (top.block_key, document.content.viewport_row)
            if now is None or now == self._scrolled_from:
                return self._wait(f"{FEXP_DOCUMENT} scrolled")
            figure, image = self._figure(projection, document)
            if figure is not None and image is None:
                return self._wait(f"{FEXP_DOCUMENT}'s figure shown rich after the scroll")
            milestone = None
            if figure is not None and figure[1] != figure[2] and not self._figure_clipped:
                # The projection holds the IMAGE to the figure's whole
                # rectangle and to the part the document shows.
                self._figure_clipped = True
                milestone = "fexp-document-figure-clipped"
            end = document.block_with(FEXP_DOCUMENT_END)
            link = None if end is None else document.link(end, FEXP_DOCUMENT_TOP_LINK)
            if link is None:
                self._scrolled_from = now
                return self._step(milestone or "fexp-document-scrolled", "document_scroll",
                                  document.value(FEXP_DOCUMENT_DETENTS),
                                  self.DOCUMENT_SCROLLED, offer, generation, sender)
            if not self._figure_clipped:
                raise PhysicalDesktopAcceptanceError(
                    f"{FEXP_DOCUMENT}'s figure never showed partly scrolled out"
                )
            self._scrolled_from = None
            return self._step(milestone or "fexp-document-end-shown", "document_follow",
                              document.value(link.item_key, link.scalar_offset),
                              self.DOCUMENT_TOP, offer, generation, sender)
        if not at_top:
            return self._wait(f"{FEXP_DOCUMENT}'s first heading back at the top")
        item = document.block_with(f"{FEXP_DOCUMENT_FILE_LINK}, another document")
        link = None if item is None else document.link(item, FEXP_DOCUMENT_FILE_LINK)
        if link is None:
            raise PhysicalDesktopAcceptanceError(
                f"{FEXP_DOCUMENT} shows no link to {FEXP_LINKED_NAME}"
            )
        return self._step("fexp-document-heading-link-followed", "document_follow",
                          document.value(link.item_key, link.scalar_offset),
                          self.LINKED_DOCUMENT, offer, generation, sender)

    @staticmethod
    def _page_shown(document, label: str) -> bool:
        """Whether the root shows a row of the start of the page LABEL."""

        height = document.bottom - document.top
        return any(
            placed.block.kind is BlockKind.PAGE
            and placed.block.text == label
            and placed.top < height
            and placed.top + placed.rows > 0
            for placed in document.placed
        )

    def _pdf(self, offer, generation, projection, sender) -> JourneyProgress:
        """sample.pdf's preview: a DOCUMENT from its first page's start, whose
        link to the last page shows that page; the key c shows its outline
        as a TREE in the document's place, the title's entry open as the
        file says, and a COLLAPSE closes it; its Pictures entry then shows
        the second page from its start with its two pictures shown rich;
        and encrypted.pdf, read with the empty password, shows the same
        title."""

        bounds = _desk_content_bounds(projection)
        _tab, selected = _tab_in(projection, bounds, "Preview", _WHERE)
        if not selected:
            return self._wait("the Preview tab selected")
        document = self._document_claim(projection, bounds)
        if self.stage in (self.PDF_CONTENTS, self.PDF_OUTLINE_CLOSED):
            outline = self._outline(projection, bounds)
            shown = () if outline is None else tuple(
                (item.depth, item.fields[0].text) for item in outline.content.items
            )
            if self.stage == self.PDF_CONTENTS:
                expected, waiting = FEXP_PDF_OUTLINE, "shown as a tree"
            else:
                expected = tuple(entry for entry in FEXP_PDF_OUTLINE if entry[0] == 0)
                waiting = "shown with its title's entry closed"
            if shown != expected:
                return self._wait(f"{FEXP_PDF}'s outline {waiting}")
            if document is not None:
                raise PhysicalDesktopAcceptanceError(
                    f"{FEXP_PDF}'s outline did not take the document's place"
                )
            _require_cell_text_in(offer, FEXP_PDF_PICTURES, bounds, _WHERE)
            title = outline.named(FEXP_PDF_TITLE)
            if not title.state & ItemState.EXPANDABLE:
                raise PhysicalDesktopAcceptanceError(
                    f"{FEXP_PDF}'s outline cannot open or close its title's entry"
                )
            if self.stage == self.PDF_CONTENTS:
                lists = outline.content.items[1]
                if not title.state & ItemState.EXPANDED or lists.parent_key != title.item_key:
                    raise PhysicalDesktopAcceptanceError(
                        f"{FEXP_PDF}'s outline does not show its title's entry open"
                    )
                return self._step("fexp-pdf-outline-shown", "item_collapse",
                                  outline.value(title.item_key), self.PDF_OUTLINE_CLOSED,
                                  offer, generation, sender)
            if title.state & ItemState.EXPANDED:
                raise PhysicalDesktopAcceptanceError(
                    f"{FEXP_PDF}'s closed title entry still says it is open"
                )
            entry = outline.named(FEXP_PDF_PICTURES)
            return self._step("fexp-pdf-outline-closed", "item_open",
                              outline.value(entry.item_key), self.PDF_PICTURES,
                              offer, generation, sender)
        name = FEXP_PDF_ENCRYPTED if self.stage == self.ENCRYPTED_PREVIEWED else FEXP_PDF
        if document is None:
            return self._wait(f"{name} previewed as a document")
        top = document.top_block

        def at_start(label: str) -> bool:
            return (
                top is not None
                and top.kind is BlockKind.PAGE
                and top.text == label
                and document.content.viewport_row == 0
            )

        if self.stage in (self.PDF_PREVIEWED, self.ENCRYPTED_PREVIEWED):
            title = document.block_with(FEXP_PDF_TITLE)
            if not at_start("1") or title is None:
                return self._wait(f"{name} shown from its first page's start")
            if title.kind is not BlockKind.HEADING or title.level != 1:
                raise PhysicalDesktopAcceptanceError(
                    f"{name}'s title is not a heading of level 1"
                )
            _require_cell_text_in(offer, FEXP_PDF_TITLE, bounds, _WHERE)
            if self.stage == self.ENCRYPTED_PREVIEWED:
                details, _selected = _tab_in(projection, bounds, "Details", _WHERE)
                return self._step("fexp-pdf-encrypted-shown", "activate_tab",
                                  _tab_value(details), self.ENCRYPTED_DETAILS,
                                  offer, generation, sender)
            block = document.block_with(FEXP_PDF_LAST_LINK)
            link = None if block is None else document.link(block, FEXP_PDF_LAST_LINK)
            if link is None:
                raise PhysicalDesktopAcceptanceError(
                    f"{FEXP_PDF} shows no link to its last page"
                )
            return self._step("fexp-pdf-shown", "document_follow",
                              document.value(link.item_key, link.scalar_offset),
                              self.PDF_LAST_PAGE, offer, generation, sender)
        if self.stage == self.PDF_LAST_PAGE:
            if (
                at_start("1")
                or document.block_with(FEXP_PDF_CODE) is None
                or not self._page_shown(document, "3")
            ):
                return self._wait(f"{FEXP_PDF}'s last page shown")
            _require_cell_text_in(offer, FEXP_PDF_CODE, bounds, _WHERE)
            # The follow focused the preview, so the key reaches it.
            return self._step("fexp-pdf-link-followed", "send_text", "c",
                              self.PDF_CONTENTS, offer, generation, sender)
        if not at_start("2"):
            return self._wait(f"{FEXP_PDF}'s second page shown from its start")
        figures = [figure for figure in document.figures if figure[2] is not None]
        if len(figures) != 2:
            raise PhysicalDesktopAcceptanceError(
                f"{FEXP_PDF}'s second page shows {len(figures)} pictures from its start"
            )
        for key, _whole, _shown in figures:
            if not any(
                claim.figure == (document.identity, key)
                for claim in projection.semantic_image_claims
            ):
                return self._wait(f"{FEXP_PDF}'s pictures shown rich")
        # The photograph is the first, wholly in view.
        _key, whole, shown = figures[0]
        if whole != shown:
            raise PhysicalDesktopAcceptanceError(
                f"{FEXP_PDF}'s photograph is not wholly in view at its page's start"
            )
        _require_picture_facts_in(
            offer, FEXP_PDF_PHOTO_FACTS,
            (shown.left, shown.top, shown.right, shown.bottom), _WHERE,
        )
        details, _selected = _tab_in(projection, bounds, "Details", _WHERE)
        return self._step("fexp-pdf-pictures-shown", "activate_tab", _tab_value(details),
                          self.PDF_DETAILS, offer, generation, sender)

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
            _require_desk_launcher_dialog(projection, launcher)
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
        if self.stage in self._PREVIEWS:
            return self._preview(offer, generation, projection, sender)
        if self.stage in self._DOCUMENT_STAGES:
            return self._document(offer, generation, projection, sender)
        if self.stage in self._PDF_STAGES:
            return self._pdf(offer, generation, projection, sender)
        if self.stage in (self.DELETE_ASKED, self.DELETE_CANCELLED):
            # The question may cover the detail table, which the capture
            # then withholds until it closes.
            bounds = _desk_content_bounds(projection)
            delete = _dialog_claim(projection, FEXPLORER_DELETE_QUESTION, bounds)
            if self.stage == self.DELETE_ASKED:
                if delete is None:
                    return self._wait("File Explorer's question after Delete")
                value = _cancel_of_confirm(offer, projection, delete, bounds, FEXPLORER_DELETE,
                                           FEXPLORER_MENU_SIGNATURE, "File Explorer", _WHERE)
                return self._step("fexp-delete-question-shown", "activate_button", value,
                                  self.DELETE_CANCELLED, offer, generation, sender)
            if delete is not None:
                return self._wait("File Explorer's question to close after Cancel")
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
        rename = _prompt_claim(projection, FEXP_RENAME_LABEL, bounds)
        if rename is not None:
            _require_held_beneath_overlay(
                projection, rename, bounds, FEXPLORER_MENU_SIGNATURE, "File Explorer"
            )
        if self.RENAME_PROMPT <= self.stage <= self.RENAME_TYPED:
            return self._rename(offer, generation, projection, sender, rename)
        goto = _prompt_claim(projection, FEXP_GOTO_LABEL, bounds)
        if goto is not None:
            _require_held_beneath_overlay(
                projection, goto, bounds, FEXPLORER_MENU_SIGNATURE, "File Explorer"
            )
        if self.stage in (self.GOTO_PROMPT, self.GOTO_TYPED):
            return self._goto(offer, generation, sender, goto)
        if self.stage in (self.FILE_SELECTED, self.RENAMED, self.DELETE_CANCELLED,
                          self.GOTO_WARNED):
            if rename is not None:
                return self._wait("the rename prompt closed")
            if goto is not None:
                return self._wait("the Go to prompt closed")
            name = FEXP_FILE if self.stage == self.FILE_SELECTED else FEXP_RENAMED
            selected = table.selected
            if selected is None or selected.fields[0].text != name:
                return self._wait(f"{name}'s row selected")
            if not _status_shows(projection, "/" + name, bounds):
                return self._wait("the selected file's path in the status bar")
            if _image_claims_in(projection, bounds):
                raise PhysicalDesktopAcceptanceError(
                    f"File Explorer shows a picture for {name}"
                )
            if self.stage == self.FILE_SELECTED:
                return self._step("fexp-file-selected", "send_key", "f2",
                                  self.RENAME_PROMPT, offer, generation, sender)
            if table.named(FEXP_FILE) is not None:
                raise PhysicalDesktopAcceptanceError(
                    f"File Explorer still lists {FEXP_FILE} after renaming it"
                )
            if self.stage == self.RENAMED:
                if not self._renamed:
                    notice = _notice_claim(projection, FEXP_RENAMED_NOTICE)
                    if notice is None:
                        return self._wait(f"File Explorer's notice {FEXP_RENAMED_NOTICE!r}")
                    _require_notice(offer, notice, StatusSeverity.NEUTRAL)
                    self._renamed = True
                return self._step("fexp-renamed", "send_key", "delete",
                                  self.DELETE_ASKED, offer, generation, sender)
            if self.stage == self.DELETE_CANCELLED:
                return self._step("fexp-delete-cancelled", "send_key", "ctrl+g",
                                  self.GOTO_PROMPT, offer, generation, sender)
            if not self._warned:
                notice = _notice_claim(projection, FEXP_GOTO_NOTICE)
                if notice is None:
                    return self._wait(f"File Explorer's warning {FEXP_GOTO_NOTICE!r}")
                _require_notice(offer, notice, StatusSeverity.WARNING)
                self._warned = True
            row = table.named(FEXPLORER_PICTURE)
            if row is None:
                raise PhysicalDesktopAcceptanceError(
                    f"File Explorer's root lists no {FEXPLORER_PICTURE}"
                )
            if not self._shown(table, row):
                return self._step("fexp-table-scrolled", "item_scroll", table.value(1),
                                  self.GOTO_WARNED, offer, generation, sender)
            return self._step("fexp-goto-warned", "item_select",
                              table.value(row.item_key), self.PICTURE_SELECTED,
                              offer, generation, sender)
        if self.stage in (self.PICTURE_SELECTED, self.TEXT_SELECTED,
                          self.DOCUMENT_SELECTED, self.PDF_SELECTED,
                          self.ENCRYPTED_SELECTED, self.PICTURE_RESELECTED):
            name = {self.TEXT_SELECTED: FEXP_RENAMED,
                    self.DOCUMENT_SELECTED: FEXP_DOCUMENT,
                    self.PDF_SELECTED: FEXP_PDF,
                    self.ENCRYPTED_SELECTED: FEXP_PDF_ENCRYPTED}.get(
                        self.stage, FEXPLORER_PICTURE)
            selected = table.selected
            if selected is None or selected.fields[0].text != name:
                return self._wait(f"{name}'s row selected")
            if not _status_shows(projection, "/" + name, bounds):
                return self._wait(f"{name}'s path in the status bar")
            tab, selected_tab = _tab_in(projection, bounds, "Preview", _WHERE)
            if selected_tab:
                raise PhysicalDesktopAcceptanceError("the Preview tab is already selected")
            preview = {self.PICTURE_SELECTED: self.PICTURE_PREVIEWED,
                       self.TEXT_SELECTED: self.TEXT_PREVIEWED,
                       self.DOCUMENT_SELECTED: self.DOCUMENT_PREVIEWED,
                       self.PDF_SELECTED: self.PDF_PREVIEWED,
                       self.ENCRYPTED_SELECTED: self.ENCRYPTED_PREVIEWED,
                       self.PICTURE_RESELECTED: self.PICTURE_PREVIEWED_LAST}[self.stage]
            return self._step(f"fexp-selected-{self.stage}", "activate_tab",
                              _tab_value(tab), preview, offer, generation, sender)
        if self.stage in (self.PICTURE_DETAILS, self.PICTURE_DETAILS_AGAIN,
                          self.TEXT_DETAILS, self.DOCUMENT_DETAILS, self.PDF_DETAILS,
                          self.ENCRYPTED_DETAILS, self.DETAILS_SHOWN):
            if _image_claims_in(projection, bounds):
                return self._wait("the picture gone with the Preview tab")
            if self._document_claim(projection, bounds) is not None:
                return self._wait("the document gone with the Preview tab")
            if self.stage == self.PICTURE_DETAILS:
                # The same picture, shown again.
                tab, _selected = _tab_in(projection, bounds, "Preview", _WHERE)
                return self._step("fexp-details-shown", "activate_tab",
                                  _tab_value(tab), self.PICTURE_PREVIEWED_AGAIN,
                                  offer, generation, sender)
            # The file each Details stage selects next, and the stage after.
            follows = {
                self.PICTURE_DETAILS_AGAIN: (FEXP_RENAMED, self.TEXT_SELECTED),
                self.TEXT_DETAILS: (FEXP_DOCUMENT, self.DOCUMENT_SELECTED),
                self.DOCUMENT_DETAILS: (FEXP_PDF, self.PDF_SELECTED),
                self.PDF_DETAILS: (FEXP_PDF_ENCRYPTED, self.ENCRYPTED_SELECTED),
                self.ENCRYPTED_DETAILS: (FEXPLORER_PICTURE, self.PICTURE_RESELECTED),
            }
            if self.stage in follows:
                name, target = follows[self.stage]
                row = table.named(name)
                if row is None:
                    raise PhysicalDesktopAcceptanceError(
                        f"File Explorer's root does not list {name}"
                    )
                if not self._shown(table, row):
                    toward = -1 if row.ordinal < table.content.viewport_first else 1
                    return self._step("fexp-table-scrolled", "item_scroll",
                                      table.value(toward), self.stage, offer,
                                      generation, sender)
                return self._step(f"fexp-details-{self.stage}", "item_select",
                                  table.value(row.item_key), target, offer,
                                  generation, sender)
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
            return self._step("fexp-details-last", "item_open",
                              table.value(directories[0].item_key),
                              self.DIRECTORY_OPENED, offer, generation, sender)
        if self.stage == self.DIRECTORY_OPENED:
            if table.named(FEXP_RENAMED) is not None or not _status_shows(
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
                or not _status_shows(projection, "/" + self._directory, bounds)
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
        if table.named(FEXP_RENAMED) is None:
            return self._wait("the table listing the root again")
        return self._step("fexp-tree-collapsed", "send_key", "alt+h",
                          self.LAUNCHER_OPENED, offer, generation, sender)


class PhotoJourney(_AppletJourney):
    """Desk with File Explorer holding a real photograph: select it, show its
    Preview, and see the terminal show the photograph itself.

    The terminal decodes QOI, so the producer sends the photo's file as it
    is and the terminal holds the whole 2160 by 1620 picture, which the
    renderer fits into the preview.  The guest decodes nothing for it: CELL
    beneath shows only what the picture is.  The picture's size and the
    area's are kept as journey evidence.
    """

    focus_marker = FEXP_ALONE_FOCUS_MARKER
    READY, SELECTED, PREVIEWED = range(3)

    def __init__(self, ready_markers: tuple[str, ...]):
        super().__init__(ready_markers)
        self.evidence = {"photo": None}

    @property
    def final_stage(self) -> int:
        return self.PREVIEWED

    @property
    def final_cell_markers(self) -> tuple[str, ...]:
        return (self.focus_marker, FEXP_PHOTO)

    def _require_photo_itself(self, offer, shown) -> None:
        """The terminal holds the photo at its own size, decoded from the
        file, not a copy the guest made for the area."""

        if self.cell_pixels is None:
            raise PhysicalDesktopAcceptanceError("the viewer's cell size is unknown")
        cell_w, cell_h = self.cell_pixels
        area = ((shown.right - shown.left) * cell_w, (shown.bottom - shown.top) * cell_h)
        named = (shown.owner_id, shown.owner_generation, shown.resource_id)
        manifests = [
            resource for resource in offer.retained.resources
            if (resource.owner_id, resource.owner_generation, resource.resource_id) == named
        ]
        if len(manifests) != 1:
            raise PhysicalDesktopAcceptanceError(
                f"{FEXP_PHOTO} names a resource the frame does not carry"
            )
        held = (manifests[0].width, manifests[0].height)
        self.evidence["photo"] = {
            "photo_pixels": list(FEXP_PHOTO_SIZE),
            "area_cells": [shown.right - shown.left, shown.bottom - shown.top],
            "cell_pixels": [cell_w, cell_h],
            "area_pixels": list(area),
            "held_pixels": list(held),
            "held_bytes": manifests[0].byte_length,
        }
        if held != FEXP_PHOTO_SIZE:
            raise PhysicalDesktopAcceptanceError(
                f"{FEXP_PHOTO} shows a {held[0]}x{held[1]} copy, not the photo itself"
            )

    def after_present(self, offer, generation, projection, sender) -> JourneyProgress:
        if not self._admit(offer, generation, projection, sender):
            return JourneyProgress()
        bounds = _desk_content_bounds(projection)
        if self.stage == self.PREVIEWED:
            _tab, selected = _tab_in(projection, bounds, "Preview", _WHERE)
            if not selected:
                return self._wait("the Preview tab selected")
            pictures = _image_claims_in(projection, bounds)
            if not pictures:
                return self._wait(f"{FEXP_PHOTO} shown rich")
            if len(pictures) != 1:
                raise PhysicalDesktopAcceptanceError(
                    f"File Explorer shows {len(pictures)} pictures for {FEXP_PHOTO}"
                )
            shown, = pictures
            _require_picture_facts_in(
                offer, FEXP_PHOTO_FACTS,
                (shown.left, shown.top, shown.right, shown.bottom), _WHERE,
            )
            self._require_photo_itself(offer, shown)
            return self._done("photo-shown-itself", offer)
        table, _tree = FexpAloneJourney._views(projection)
        if table is None:
            return self._wait("File Explorer's detail table and folder tree")
        row = table.named(FEXP_PHOTO)
        if self.stage == self.READY:
            if row is None:
                raise PhysicalDesktopAcceptanceError(
                    f"File Explorer's root lists no {FEXP_PHOTO}"
                )
            if not FexpAloneJourney._shown(table, row):
                return self._step("photo-table-scrolled", "item_scroll", table.value(1),
                                  self.READY, offer, generation, sender)
            return self._step("photo-table-shown", "item_select",
                              table.value(row.item_key), self.SELECTED, offer,
                              generation, sender)
        selected = table.selected
        if selected is None or selected.fields[0].text != FEXP_PHOTO:
            return self._wait(f"{FEXP_PHOTO}'s row selected")
        if not _status_shows(projection, "/" + FEXP_PHOTO, bounds):
            return self._wait(f"{FEXP_PHOTO}'s path in the status bar")
        tab, selected_tab = _tab_in(projection, bounds, "Preview", _WHERE)
        if selected_tab:
            raise PhysicalDesktopAcceptanceError("the Preview tab is already selected")
        return self._step("photo-selected", "activate_tab", _tab_value(tab),
                          self.PREVIEWED, offer, generation, sender)


class DamagedPictureJourney(_AppletJourney):
    """Desk with File Explorer holding a picture file the terminal cannot
    decode: a PNG whose header names a 64 by 48 picture and whose data is
    none.  Its Preview sends the file once, the terminal refuses it, and CELL
    says the picture is damaged.  The Details tab and the Preview again draw
    the same picture, which is not sent again, and every input is answered.
    The terminal's frame counts at each step are kept as journey evidence.
    """

    focus_marker = FEXP_ALONE_FOCUS_MARKER
    READY, SELECTED, PREVIEWED, DETAILS, PREVIEWED_AGAIN = range(5)

    def __init__(self, ready_markers: tuple[str, ...]):
        super().__init__(ready_markers)
        self._frames: dict[str, int] | None = None
        # The terminal's upload frames before the Preview first showed.
        self._before: dict[str, int] | None = None
        self.evidence = {"damaged": {}}

    @property
    def final_stage(self) -> int:
        return self.PREVIEWED_AGAIN

    @property
    def final_cell_markers(self) -> tuple[str, ...]:
        return (self.focus_marker, FEXP_DAMAGED_REASON)

    def observe_status(self, status) -> None:
        rich = status.get("rich_terminal") if isinstance(status, dict) else None
        counts = rich.get("frames_by_type") if isinstance(rich, dict) else None
        if isinstance(counts, dict):
            self._frames = {
                name: int(counts.get(f"0x{int(kind):04X}", 0))
                for name, kind in _UPLOAD_FRAMES.items()
            }

    def _sent_once(self) -> dict[str, int] | None:
        """The upload frames the terminal took since the Preview first
        showed, once it has answered the damaged file's one upload: begun,
        sent and committed once, never aborted.  None while that answer is
        still to come."""

        uploads = {name: self._frames[name] - self._before[name]
                   for name in ("resource_begin", "resource_chunk", "resource_commit",
                                "resource_abort")}
        if uploads["resource_commit"] == 0 and uploads["resource_abort"] == 0:
            return None
        if (uploads["resource_begin"], uploads["resource_commit"],
                uploads["resource_abort"]) != (1, 1, 0) or not uploads["resource_chunk"]:
            raise PhysicalDesktopAcceptanceError(
                f"{FEXP_DAMAGED} was sent as {uploads!r}, not as one upload"
            )
        return uploads

    def _preview(self, offer, generation, projection, sender) -> JourneyProgress:
        bounds = _desk_content_bounds(projection)
        _tab, selected = _tab_in(projection, bounds, "Preview", _WHERE)
        if not selected:
            return self._wait("the Preview tab selected")
        if _image_claims_in(projection, bounds):
            raise PhysicalDesktopAcceptanceError(f"{FEXP_DAMAGED} shows rich")
        left, top, right, bottom = bounds
        if not any(
            top <= row < bottom and left <= column < right
            for row, column in offer.cell.find(FEXP_DAMAGED_REASON)
        ):
            return self._wait(f"CELL saying {FEXP_DAMAGED} is damaged")
        if self._frames is None:
            return self._wait("the terminal's frame counts")
        uploads = self._sent_once()
        if uploads is None:
            return self._wait(f"the terminal's answer to {FEXP_DAMAGED}'s upload")
        if self.stage == self.PREVIEWED_AGAIN:
            self.evidence["damaged"]["previewed-again"] = uploads
            return self._done("damaged-not-sent-again", offer)
        self.evidence["damaged"]["previewed"] = uploads
        details, _selected = _tab_in(projection, bounds, "Details", _WHERE)
        return self._step("damaged-refused", "activate_tab", _tab_value(details),
                          self.DETAILS, offer, generation, sender)

    def after_present(self, offer, generation, projection, sender) -> JourneyProgress:
        if not self._admit(offer, generation, projection, sender):
            return JourneyProgress()
        if self.stage in (self.PREVIEWED, self.PREVIEWED_AGAIN):
            return self._preview(offer, generation, projection, sender)
        bounds = _desk_content_bounds(projection)
        if self.stage == self.DETAILS:
            _tab, selected = _tab_in(projection, bounds, "Details", _WHERE)
            if not selected:
                return self._wait("the Details tab selected")
            preview, _selected = _tab_in(projection, bounds, "Preview", _WHERE)
            return self._step("damaged-details-shown", "activate_tab", _tab_value(preview),
                              self.PREVIEWED_AGAIN, offer, generation, sender)
        table, _tree = FexpAloneJourney._views(projection)
        if table is None:
            return self._wait("File Explorer's detail table and folder tree")
        row = table.named(FEXP_DAMAGED)
        if self.stage == self.READY:
            if row is None:
                raise PhysicalDesktopAcceptanceError(
                    f"File Explorer's root lists no {FEXP_DAMAGED}"
                )
            if not FexpAloneJourney._shown(table, row):
                return self._step("damaged-table-scrolled", "item_scroll", table.value(1),
                                  self.READY, offer, generation, sender)
            return self._step("damaged-table-shown", "item_select",
                              table.value(row.item_key), self.SELECTED, offer,
                              generation, sender)
        selected = table.selected
        if selected is None or selected.fields[0].text != FEXP_DAMAGED:
            return self._wait(f"{FEXP_DAMAGED}'s row selected")
        if not _status_shows(projection, "/" + FEXP_DAMAGED, bounds):
            return self._wait(f"{FEXP_DAMAGED}'s path in the status bar")
        if self._frames is None:
            return self._wait("the terminal's frame counts")
        tab, selected_tab = _tab_in(projection, bounds, "Preview", _WHERE)
        if selected_tab:
            raise PhysicalDesktopAcceptanceError("the Preview tab is already selected")
        self._before = dict(self._frames)
        self.evidence["damaged"]["before"] = dict(self._frames)
        return self._step("damaged-selected", "activate_tab", _tab_value(tab),
                          self.PREVIEWED, offer, generation, sender)


class StreamsAloneJourney(_AppletJourney):
    """Desk with Streams and a fixed feed: select a reply and open its
    context, through item events on Streams' cards, then add a feed source
    and switch it off through its card's check box.

    The timeline is a CARDS item view of three text fields per post: its
    author and time, its text, and "reply" when it replies.  The web link
    in the first post's text is a LINK style run.  A SELECT on the reply's
    card selects it; an OPEN on it opens its context, a second CARDS view
    holding only the thread's two posts with the reply selected.  CELL shows
    the cards throughout.

    S opens the Sources view, empty at first; F asks for a feed's address
    in a prompt.  The new source is a checkable card, checked because it
    is enabled; a CHECK on it disables it, at its next revision.  Escape
    returns to the timeline.
    """

    focus_marker = STREAMS_ALONE_FOCUS_MARKER
    (READY, SELECTED, OPENED, SOURCES, PROMPT, TYPED, SOURCE, UNCHECKED,
     BACK) = range(9)

    @property
    def final_stage(self) -> int:
        return self.BACK

    @property
    def final_cell_markers(self) -> tuple[str, ...]:
        return (self.focus_marker, STREAMS_REPLY_TEXT)

    @staticmethod
    def _sources(projection, bounds):
        """The Sources view's cards: one checkable card per source."""

        left, top, right, bottom = bounds
        views = [
            claim
            for claim in projection.semantic_item_view_claims
            if left <= claim.left < claim.right <= right
            and top <= claim.top < claim.bottom <= bottom
            and claim.content.role is ItemViewRole.CARDS
            and any(item.state & ItemState.CHECKABLE for item in claim.content.items)
        ]
        return views[0] if len(views) == 1 else None

    def _source_steps(self, offer, generation, projection, sender, bounds) -> JourneyProgress:
        if self.stage == self.BACK:
            cards = self._cards(projection)
            if cards is None or self._posts(cards) != list(STREAMS_CARDS):
                return self._wait("the timeline after Escape")
            _require_cell_text_in(offer, STREAMS_REPLY_TEXT, bounds, _WHERE)
            return self._done("streams-timeline-again", offer)
        prompt = _prompt_claim(projection, STREAMS_FEED_PROMPT, bounds)
        if self.stage == self.SOURCES:
            if not _residual_contains(projection, STREAMS_NO_SOURCES, bounds):
                return self._wait("Streams' empty Sources view")
            return self._step("streams-sources-empty", "send_key", "f",
                              self.PROMPT, offer, generation, sender)
        if self.stage == self.PROMPT:
            if prompt is None:
                return self._wait("Streams' feed address prompt")
            return self._step("streams-feed-prompt", "send_text", STREAMS_FEED_URL,
                              self.TYPED, offer, generation, sender)
        if self.stage == self.TYPED:
            if prompt is None:
                raise PhysicalDesktopAcceptanceError("Streams' feed prompt closed early")
            if prompt.content.text != STREAMS_FEED_URL:
                return self._wait("the typed feed address")
            return self._step("streams-feed-typed", "send_key", "enter",
                              self.SOURCE, offer, generation, sender)
        if prompt is not None:
            return self._wait("Streams' feed prompt closed")
        sources = self._sources(projection, bounds)
        if sources is None:
            return self._wait("Streams' source cards")
        (item,) = sources.content.items
        fields = tuple(field.text for field in item.fields)
        if self.stage == self.SOURCE:
            # The status bar repaints the row the closed prompt covered.
            if offer.cell.find(STREAMS_FEED_PROMPT):
                raise PhysicalDesktopAcceptanceError(
                    "CELL kept Streams' closed feed prompt"
                )
            if not _source_card_reads(fields, STREAMS_SOURCE_CARD):
                raise PhysicalDesktopAcceptanceError(
                    f"Streams' new source card reads {fields!r}"
                )
            if not item.state & ItemState.CHECKED:
                raise PhysicalDesktopAcceptanceError(
                    "Streams' new source did not begin enabled"
                )
            _require_cell_text_in(offer, "[x] Syndication feed", bounds, _WHERE)
            return self._step("streams-source-added", "item_check",
                              sources.value(item.item_key), self.UNCHECKED, offer,
                              generation, sender)
        if item.state & ItemState.CHECKED:
            return self._wait("the source switched off by its check box")
        switched = (STREAMS_SOURCE_CARD[0],
                    STREAMS_SOURCE_CARD[1].replace("revision 1", "revision 2"),
                    *STREAMS_SOURCE_CARD[2:])
        if not _source_card_reads(fields, switched):
            raise PhysicalDesktopAcceptanceError(
                f"Streams' switched-off source card reads {fields!r}"
            )
        _require_cell_text_in(offer, "[ ] Syndication feed", bounds, _WHERE)
        return self._step("streams-source-switched-off", "send_key", "escape",
                          self.BACK, offer, generation, sender)

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
        if self.stage >= self.SOURCES:
            return self._source_steps(offer, generation, projection, sender, bounds)
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
        return self._step("streams-context-opened", "send_key", "s",
                          self.SOURCES, offer, generation, sender)


class AgentAloneJourney(_AppletJourney):
    """Desk with the Agent and a long stored conversation: scroll the
    transcript, return to its end, then ask for a reviewed change and
    approve it.

    The transcript is a CARDS item view of two text fields per message: a
    header, the message's role styled as a heading, and the message's text,
    whose column wraps.  It is a log, so no card is selected and the view
    follows the end.  The stored answer is taller than the view, so the
    transcript starts cut inside it; one wheel detent scrolls three screen
    rows up, and End returns to the end.  Alt+A opens Desk's own Ask
    prompt, a TEXT field across the taskbar row in a modal region over the
    whole screen, with the taskbar gone and the Agent's menu and transcript
    rich and inactive beneath it.  Text typed into it, a PLACE and an EXTEND
    that select three of its characters, and text typed over them show in
    the field; Escape cancels it and the taskbar returns.  Ctrl+L opens the
    Agent's Ask prompt, a TEXT field in a modal region over the Agent's
    tile, with the Agent's menu and transcript rich and inactive beneath
    it.  The request makes the
    demo provider ask for approval in a dialog over the Agent: a DIALOG
    titled Review required in a modal region over its tile, with the
    Agent's menu rich and inactive beneath it.  Its message shows the
    request; Approve once, which F6 chooses, cannot be chosen until the
    message's last line has been shown, and PgDn moves the message while
    it says more lies below.  Deny, which F7 chooses, is the default and
    cancel button.  Its Approve once BUTTON approves, and the transcript
    then ends with the approved exchange.  CELL shows each end of the
    transcript on its last row.  F8 then shows the run settings in the
    transcript's place: Model, Reasoning, Speed and Verbosity are CHOICE
    fields holding Swift, Low, Standard and Auto.  An ADJUST moves Reasoning
    to Medium, an ACTIVATE takes Model to Deliberate, whose own reasoning,
    High, it then holds, and whose speeds are Standard and Fast; Escape
    returns to the transcript.  Last, Ctrl+L asks a long request, whose
    review is taller than its dialog: the wheel over the dialog scrolls the
    message while it says more lies below, Approve once waits until its
    last line has been shown and then approves, and the transcript ends
    with the long exchange.
    """

    focus_marker = AGENT_ALONE_FOCUS_MARKER
    (READY, SCROLLED, ENDED, DESK_PROMPT, DESK_TYPED, DESK_PLACED, DESK_SELECTED,
     DESK_REPLACED, DESK_CLOSED, PROMPT, TYPED, REVIEW, APPROVED, SETTINGS,
     REASONED, CHOSEN, SETTINGS_CLOSED, LONG_PROMPT, LONG_TYPED, LONG_REVIEW,
     LONG_APPROVED) = range(21)
    DESK_STAGES = range(DESK_PROMPT, DESK_CLOSED + 1)

    def __init__(self, ready_markers: tuple[str, ...]):
        super().__init__(ready_markers)
        self._end_row = 0  # screen rows above the view at the stored end
        # The long review's first line in view when the wheel last turned,
        # or None before it has.
        self._review_top: str | None = None

    @property
    def final_stage(self) -> int:
        return self.LONG_APPROVED

    @property
    def final_cell_markers(self) -> tuple[str, ...]:
        return (self.focus_marker, AGENT_LONG_LAST)

    def _desk_prompt_expected(self) -> bool:
        return self.stage in self.DESK_STAGES

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
    def _review(projection: RichScreenProjection, bounds):
        """The Agent's review in its tile, or None."""

        left, top, right, bottom = bounds
        found = [
            claim
            for claim in projection.semantic_dialog_claims
            if claim.title == AGENT_REVIEW_TITLE
            and left <= claim.left and claim.right <= right
            and top <= claim.top and claim.bottom <= bottom
        ]
        if not found:
            return None
        if len(found) != 1:
            raise PhysicalDesktopAcceptanceError(f"{len(found)} reviews in the Agent's tile")
        return found[0]

    @staticmethod
    def _approve_of_review(projection: RichScreenProjection, review, bounds,
                           markers=(AGENT_REVIEW_MARKER, AGENT_REVIEW_REASON)):
        """Approve once on REVIEW: the review is modal and active over the
        Agent, which stays rich and inactive beneath it; the lines in view
        say MARKERS, the request and why it asks; and it offers Approve
        once, which F6 chooses, and Deny, which F7 chooses, the default and
        cancel button."""

        if not review.modal:
            raise PhysicalDesktopAcceptanceError("the Agent's review is not modal")
        if any(part.identity in projection.inactive_controls
               for part in (review, *review.buttons)):
            raise PhysicalDesktopAcceptanceError("the Agent's review is inactive")
        _require_held_beneath_overlay(projection, review, bounds, AGENT_MENU_SIGNATURE,
                                      "the Agent")
        message = " ".join(review.content.lines)
        for marker in markers:
            if marker not in message:
                raise PhysicalDesktopAcceptanceError(
                    f"the Agent's review does not say {marker!r}"
                )
        offered = tuple((button.label, button.shortcut) for button in review.buttons)
        if offered != AGENT_REVIEW_BUTTONS:
            raise PhysicalDesktopAcceptanceError(f"the Agent's review offers {offered!r}")
        approve, deny = review.buttons
        if approve.content.default or approve.content.cancel or approve.content.destructive:
            raise PhysicalDesktopAcceptanceError("the Agent's Approve once has a role")
        if not (deny.content.default and deny.content.cancel):
            raise PhysicalDesktopAcceptanceError(
                "the Agent's Deny is not the default cancel button"
            )
        return approve

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
        prompt = _prompt_claim(projection, AGENT_PROMPT_MARKER, bounds)
        review = self._review(projection, bounds)
        if prompt is not None:
            _require_held_beneath_overlay(
                projection, prompt, bounds, AGENT_MENU_SIGNATURE, "the Agent"
            )
            if transcript is None:
                raise PhysicalDesktopAcceptanceError(
                    "the Agent's prompt withheld its transcript"
                )
        # Admission refuses Desk's prompt outside its stages, since it hides
        # the taskbar; beneath it the Agent stays rich, and inactive.
        desk_prompt = _desk_prompt_claim(projection)
        if desk_prompt is not None:
            if transcript is None or projection.menu_signatures.count(AGENT_MENU_SIGNATURE) != 1:
                raise PhysicalDesktopAcceptanceError(
                    "Desk's Ask prompt withheld the Agent's menu or transcript"
                )
        stored = agent_transcript.CARDS
        if self.stage in (self.READY, self.SCROLLED, self.ENDED, *self.DESK_STAGES):
            if prompt is not None or review is not None:
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
            return self._step("agent-transcript-end-again", "send_key", "alt+a",
                              self.DESK_PROMPT, offer, generation, sender)
        if self.stage == self.DESK_CLOSED:
            if desk_prompt is not None:
                return self._wait("Desk's Ask prompt closed by Escape")
            if self._rows(transcript, stored)[0] != self._end_row:
                raise PhysicalDesktopAcceptanceError(
                    "Desk's Ask prompt moved the Agent's transcript"
                )
            return self._step("desk-prompt-cancelled", "send_key", "ctrl+l",
                              self.PROMPT, offer, generation, sender)
        if self.stage in self.DESK_STAGES:
            return self._desk_prompt(offer, generation, sender, desk_prompt)
        if self.stage == self.PROMPT:
            if prompt is None:
                return self._wait("the Agent's Ask prompt")
            return self._step("agent-prompt-opened", "send_text", AGENT_REQUEST,
                              self.TYPED, offer, generation, sender)
        if self.stage == self.TYPED:
            if prompt is None:
                raise PhysicalDesktopAcceptanceError("the Agent's Ask prompt closed early")
            if prompt.content.text != AGENT_REQUEST:
                return self._wait("the typed request")
            return self._step("agent-request-typed", "send_key", "enter",
                              self.REVIEW, offer, generation, sender)
        if self.stage == self.REVIEW:
            if review is None:
                return self._wait("the Agent's review")
            approve = self._approve_of_review(projection, review, bounds)
            _require_cell_text_in(offer, AGENT_REVIEW_MARKER, bounds, _WHERE)
            chosen = bool(approve.state & ControlState.ENABLED)
            if review.content.lines[-1:] == (DIALOG_MORE,):
                if chosen:
                    raise PhysicalDesktopAcceptanceError(
                        "Approve once could be chosen before the review was read"
                    )
                return self._step("agent-review-paged", "send_key", "pagedown",
                                  self.REVIEW, offer, generation, sender)
            if not chosen:
                return self._wait("Approve once after the review's last line")
            identity = approve.identity
            value = f"{identity.owner_id},{identity.owner_generation},{identity.control_id}"
            return self._step("agent-review-unlocked", "activate_button", value,
                              self.APPROVED, offer, generation, sender)
        if self.SETTINGS <= self.stage <= self.SETTINGS_CLOSED:
            return self._settings(offer, generation, projection, sender, bounds, transcript)
        if self.stage >= self.LONG_PROMPT:
            return self._long(offer, generation, projection, sender, bounds, transcript,
                              prompt, review)
        cards = stored + AGENT_EXCHANGE
        if review is not None or transcript is None or not self._shows(transcript, cards):
            return self._wait("the approved exchange")
        self._check(transcript, cards)
        self._at_end(transcript, cards)
        self._require_last_row(offer, transcript, AGENT_AUDIT)
        return self._step("agent-review-approved", "send_key", "f8", self.SETTINGS,
                          offer, generation, sender)

    @staticmethod
    def _settings_fields(projection: RichScreenProjection, bounds):
        """The run settings' fields in the Agent's tile, by label, or none."""

        left, top, right, bottom = bounds
        found = [
            claim
            for claim in projection.semantic_field_claims
            if left <= claim.left and claim.right <= right
            and top <= claim.top and claim.bottom <= bottom
        ]
        if not found:
            return {}
        labels = tuple(claim.label for claim in found)
        if sorted(labels) != sorted(AGENT_SETTINGS_LABELS):
            raise PhysicalDesktopAcceptanceError(
                f"the Agent's tile carries the fields {labels!r}"
            )
        for claim in found:
            if claim.content.kind is not FieldKind.CHOICE or claim.modal:
                raise PhysicalDesktopAcceptanceError(
                    f"the Agent's {claim.label} setting is not a plain CHOICE field"
                )
        return {claim.label: claim for claim in found}

    @staticmethod
    def _field_value(claim, count: int | None = None) -> str:
        identity = claim.identity
        value = f"{identity.owner_id},{identity.owner_generation},{identity.control_id}"
        return value if count is None else f"{value},{count}"

    def _settings(self, offer, generation, projection, sender, bounds,
                  transcript) -> JourneyProgress:
        """The run settings in the transcript's place: an ADJUST moves
        Reasoning, an ACTIVATE takes Model to its next choice, and Escape
        returns to the transcript."""

        fields = self._settings_fields(projection, bounds)
        if self.stage == self.SETTINGS_CLOSED:
            if fields:
                return self._wait("the run settings closed by Escape")
            cards = agent_transcript.CARDS + AGENT_EXCHANGE
            if transcript is None or not self._shows(transcript, cards):
                return self._wait("the transcript after the run settings")
            self._require_last_row(offer, transcript, AGENT_AUDIT)
            return self._step("agent-settings-closed", "send_key", "ctrl+l",
                              self.LONG_PROMPT, offer, generation, sender)
        if not fields:
            return self._wait("the Agent's run settings after F8")
        if transcript is not None:
            raise PhysicalDesktopAcceptanceError(
                "the Agent's run settings left its transcript shown"
            )
        shown = {label: claim.content.display_text for label, claim in fields.items()}
        if self.stage == self.SETTINGS:
            choices = tuple(choice.label for choice in fields["Reasoning"].content.choices)
            if shown != AGENT_SETTINGS_SHOWN or choices != ("Low", "Medium"):
                raise PhysicalDesktopAcceptanceError(
                    f"the Agent's run settings show {shown!r}, reasoning {choices!r}"
                )
            return self._step("agent-settings-shown", "field_adjust",
                              self._field_value(fields["Reasoning"], 1), self.REASONED,
                              offer, generation, sender)
        if self.stage == self.REASONED:
            if shown["Reasoning"] == "Low":
                return self._wait("Reasoning after the adjustment")
            if shown != {**AGENT_SETTINGS_SHOWN, "Reasoning": "Medium"}:
                raise PhysicalDesktopAcceptanceError(
                    f"adjusting Reasoning showed {shown!r}"
                )
            return self._step("agent-reasoning-adjusted", "field_activate",
                              self._field_value(fields["Model"]), self.CHOSEN,
                              offer, generation, sender)
        if shown["Model"] == "Swift":
            return self._wait("the next model after the activation")
        speeds = tuple(choice.label for choice in fields["Speed"].content.choices)
        if shown != AGENT_SETTINGS_CHOSEN or speeds != ("Standard", "Fast"):
            raise PhysicalDesktopAcceptanceError(
                f"activating Model showed {shown!r}, speeds {speeds!r}"
            )
        return self._step("agent-model-chosen", "send_key", "escape",
                          self.SETTINGS_CLOSED, offer, generation, sender)

    def _long(self, offer, generation, projection, sender, bounds, transcript, prompt,
              review) -> JourneyProgress:
        """The long request: its review is taller than its dialog, so the
        wheel over the dialog scrolls it while it says more lies below, and
        Approve once waits until its last line has been shown."""

        if self.stage == self.LONG_PROMPT:
            if prompt is None:
                return self._wait("the Agent's Ask prompt for the long request")
            return self._step("agent-long-prompt-opened", "send_text", AGENT_LONG_REQUEST,
                              self.LONG_TYPED, offer, generation, sender)
        if self.stage == self.LONG_TYPED:
            if prompt is None:
                raise PhysicalDesktopAcceptanceError("the Agent's Ask prompt closed early")
            if prompt.content.text != AGENT_LONG_REQUEST:
                return self._wait("the typed long request")
            return self._step("agent-long-request-typed", "send_key", "enter",
                              self.LONG_REVIEW, offer, generation, sender)
        if self.stage == self.LONG_REVIEW:
            if review is None:
                return self._wait("the long request's review")
            approve = self._approve_of_review(projection, review, bounds, markers=())
            chosen = bool(approve.state & ControlState.ENABLED)
            lines = review.content.lines
            if lines[-1:] == (DIALOG_MORE,):
                if chosen:
                    raise PhysicalDesktopAcceptanceError(
                        "Approve once could be chosen before the long review was read"
                    )
                if self._review_top is None:
                    if AGENT_REVIEW_REASON not in lines:
                        raise PhysicalDesktopAcceptanceError(
                            "the long review does not open at its reason"
                        )
                elif lines[0] == self._review_top:
                    return self._wait("the long review scrolled by the wheel")
                self._review_top = lines[0]
                identity = review.identity
                value = (f"{identity.owner_id},{identity.owner_generation},"
                         f"{identity.control_id},{AGENT_REVIEW_DETENTS}")
                return self._step("agent-long-review-scrolled", "dialog_scroll", value,
                                  self.LONG_REVIEW, offer, generation, sender)
            if self._review_top is None:
                raise PhysicalDesktopAcceptanceError(
                    "the long review fit its dialog, so the wheel had nothing to scroll"
                )
            if lines[-1:] != (AGENT_REVIEW_MARKER,) or AGENT_LONG_LAST not in lines:
                raise PhysicalDesktopAcceptanceError(
                    f"the long review's end in view is {lines[-3:]!r}"
                )
            if not chosen:
                return self._wait("Approve once after the long review's last line")
            _require_cell_text_in(offer, AGENT_REVIEW_MARKER, bounds, _WHERE)
            identity = approve.identity
            value = f"{identity.owner_id},{identity.owner_generation},{identity.control_id}"
            return self._step("agent-long-review-unlocked", "activate_button", value,
                              self.LONG_APPROVED, offer, generation, sender)
        cards = agent_transcript.CARDS + AGENT_EXCHANGE + AGENT_LONG_EXCHANGE
        if review is not None or transcript is None or not self._shows(transcript, cards):
            return self._wait("the approved long exchange")
        self._check(transcript, cards)
        self._at_end(transcript, cards)
        self._require_last_row(offer, transcript, AGENT_LONG_LAST)
        return self._done("agent-long-review-approved", offer)

    def _desk_prompt(self, offer, generation, sender, prompt) -> JourneyProgress:
        """Desk's Ask prompt: type, select three characters, type over
        them, cancel."""

        if prompt is None:
            if self.stage == self.DESK_PROMPT:
                return self._wait("Desk's Ask prompt after Alt+A")
            raise PhysicalDesktopAcceptanceError("Desk's Ask prompt closed early")
        content = prompt.content
        identity = prompt.identity
        value = f"{identity.owner_id},{identity.owner_generation},{identity.control_id},0,{{}}"
        if self.stage == self.DESK_PROMPT:
            if content.text:
                raise PhysicalDesktopAcceptanceError(
                    f"Desk's Ask prompt opened holding {content.text!r}"
                )
            return self._step("desk-prompt-opened", "send_text", DESK_PROMPT_TEXT,
                              self.DESK_TYPED, offer, generation, sender)
        if self.stage == self.DESK_TYPED:
            # The guest may paint after each typed scalar.
            if content.text != DESK_PROMPT_TEXT:
                if DESK_PROMPT_TEXT.startswith(content.text):
                    return self._wait("the text typed into Desk's Ask prompt")
                raise PhysicalDesktopAcceptanceError(
                    f"typing into Desk's Ask prompt gave {content.text!r}"
                )
            return self._step("desk-prompt-typed", "text_place", value.format(1),
                              self.DESK_PLACED, offer, generation, sender)
        if content.text != DESK_PROMPT_TEXT and self.stage != self.DESK_REPLACED:
            raise PhysicalDesktopAcceptanceError(
                f"selecting in Desk's Ask prompt changed its text to {content.text!r}"
            )
        if self.stage == self.DESK_PLACED:
            if content.caret != 1:
                return self._wait("the caret after the first character of Desk's prompt")
            return self._step("desk-prompt-caret-placed", "text_extend", value.format(4),
                              self.DESK_SELECTED, offer, generation, sender)
        if self.stage == self.DESK_SELECTED:
            if (content.anchor, content.caret) != (1, 4):
                return self._wait("three characters of Desk's prompt selected")
            return self._step("desk-prompt-selected", "send_text", DESK_PROMPT_OVER,
                              self.DESK_REPLACED, offer, generation, sender)
        head, tail = DESK_PROMPT_TEXT[:1], DESK_PROMPT_TEXT[4:]
        typed = head + DESK_PROMPT_OVER + tail
        if content.text == DESK_PROMPT_TEXT or content.text in {
            head + DESK_PROMPT_OVER[:length] + tail for length in range(1, len(DESK_PROMPT_OVER))
        }:
            return self._wait("the text typed over the selection in Desk's prompt")
        if content.text != typed:
            raise PhysicalDesktopAcceptanceError(
                f"typing over the selection in Desk's Ask prompt gave {content.text!r}, "
                f"not {typed!r}"
            )
        return self._step("desk-prompt-replaced", "send_key", "escape",
                          self.DESK_CLOSED, offer, generation, sender)


class SmallTerminalJourney(_AppletJourney):
    """Desk with Pad on a terminal with little room for retained text: a
    screen that cannot fit is shown as CELL, Desk and Pad carry on, and the
    rich frame returns once a screen fits again.

    Pad's empty editor fits, so the journey starts rich: Pad's menu bar and
    its editor as a text area.  Ctrl+O opens Pad's Open prompt, a TEXT field
    over the editor, which still fits, and the large sample's path is typed
    into it.  The 48-line large sample is more text than the terminal holds:
    the producer replaces the rich frame with an empty one and the viewer
    shows CELL.  Every frame is either complete rich output or an empty
    retained scene over complete CELL, never older rich output over a newer
    CELL frame.  The prompt over the large sample is too much as well, and
    stays CELL.  Opening the two-line example.f through it brings the rich
    frame back, with example.f in Pad's text area.
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
        if not empty and (projection.draw_count == 0 or not projection.menu_signatures):
            # A rich frame is complete: Pad's menu is in every one.
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
        if self.stage in (self.PROMPT, self.TYPED):
            if empty:
                if self._cell_shows(offer, PAD_OPEN_PROMPT_MARKER, bounds):
                    raise PhysicalDesktopAcceptanceError(
                        "Pad's Open prompt over its empty editor did not fit"
                    )
                return self._wait("Pad's Open prompt")
            prompt = _prompt_claim(projection, PAD_OPEN_PROMPT_MARKER, bounds)
            if prompt is None:
                return self._wait("Pad's Open prompt")
            _require_held_beneath_overlay(projection, prompt, bounds, PAD_MENU_SIGNATURE, "Pad")
            if self.stage == self.PROMPT:
                return self._step("small-terminal-prompt-shown-rich", "send_text",
                                  SMALL_TERMINAL_LARGE_PATH, self.TYPED, offer,
                                  generation, sender)
            if prompt.content.text != SMALL_TERMINAL_LARGE_PATH:
                return self._wait("the typed path in the Open prompt")
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


class SoundLabAloneJourney(_AppletJourney):
    """Desk with Sound Lab alone: its frequency landmarks go out as three
    lines that move when it renders new settings.

    Sound Lab renders its starting settings as it opens.  With room below
    its analysis, its graph carries a line from 0 Hz to 4 kHz and on it a
    mark at the pitch and one at the spectral centroid, which CELL draws
    the same way and names P and C in the row above.  Activating the
    Frequency field opens its exact-value prompt; a new frequency is typed
    over the value and Enter sets it, which leaves the analysis stale until
    F5 renders again.  The new render moves the pitch mark along the same
    line, in the terminal and in CELL alike.
    """

    focus_marker = SOUNDLAB_ALONE_FOCUS_MARKER
    (READY, PROMPT, SELECTED, TYPED, SET, RENDERED) = range(6)

    def __init__(self, ready_markers):
        super().__init__(ready_markers)
        self._landmarks_before = None
        self._frequency_before = None
        self._frequency = None

    @property
    def final_stage(self) -> int:
        return self.RENDERED

    @property
    def final_cell_markers(self) -> tuple[str, ...]:
        return (self.focus_marker, SOUNDLAB_LANDMARK_CAPTION)

    def after_present(self, offer, generation, projection, sender) -> JourneyProgress:
        if not self._admit(offer, generation, projection, sender):
            return JourneyProgress()
        bounds = _desk_content_bounds(projection)
        prompt = _prompt_claim(projection, SOUNDLAB_FREQUENCY_PROMPT, bounds)
        fields = {claim.label: claim for claim in _field_claims_in(projection, bounds)
                  if prompt is None or claim.identity != prompt.identity}
        frequency = fields.get(SOUNDLAB_FREQUENCY_FIELD)
        if self.stage == self.READY:
            landmarks = _soundlab_landmarks(projection, bounds)
            if landmarks is None or frequency is None:
                return self._wait("Sound Lab's landmarks from its first render")
            _require_soundlab_landmark_cells(offer, landmarks)
            self._landmarks_before = landmarks
            self._frequency_before = frequency.content.value
            self._frequency = next(value for value in SOUNDLAB_ALONE_FREQUENCIES
                                   if value != self._frequency_before)
            identity = frequency.identity
            return self._step(
                "soundlab-landmarks-shown", "field_activate",
                f"{identity.owner_id},{identity.owner_generation},{identity.control_id}",
                self.PROMPT, offer, generation, sender)
        if self.stage == self.PROMPT:
            if prompt is None:
                return self._wait("Sound Lab's frequency prompt")
            if prompt.content.text != str(self._frequency_before):
                raise PhysicalDesktopAcceptanceError(
                    f"Sound Lab's prompt opened holding {prompt.content.text!r}")
            return self._step("soundlab-frequency-prompt", "send_key", "ctrl+a",
                              self.SELECTED, offer, generation, sender)
        if self.stage in (self.SELECTED, self.TYPED) and prompt is None:
            raise PhysicalDesktopAcceptanceError("Sound Lab's prompt closed early")
        if self.stage == self.SELECTED:
            content = prompt.content
            if content.anchor == content.caret or {content.anchor, content.caret} != {
                    0, len(content.text)}:
                return self._wait("the prompt's whole value selected")
            return self._step("soundlab-frequency-selected", "send_text",
                              str(self._frequency), self.TYPED, offer, generation, sender)
        if self.stage == self.TYPED:
            if prompt.content.text != str(self._frequency):
                return self._wait("the typed frequency")
            return self._step("soundlab-frequency-typed", "send_key", "enter",
                              self.SET, offer, generation, sender)
        if prompt is not None:
            return self._wait("Sound Lab's prompt closed")
        if self.stage == self.SET:
            if frequency is None or frequency.content.value != self._frequency:
                return self._wait("Sound Lab's new frequency")
            return self._step("soundlab-frequency-set", "send_key", "f5",
                              self.RENDERED, offer, generation, sender)
        if frequency is None or frequency.content.value != self._frequency:
            raise PhysicalDesktopAcceptanceError("Sound Lab's frequency changed while it rendered")
        landmarks = _soundlab_landmarks(projection, bounds)
        before = self._landmarks_before
        if landmarks is None or landmarks.pitch == before.pitch:
            return self._wait("the pitch mark moved by the new render")
        if (landmarks.row, landmarks.left, landmarks.right) != (
                before.row, before.left, before.right):
            raise PhysicalDesktopAcceptanceError("Sound Lab's landmark line moved")
        _require_soundlab_landmark_cells(offer, landmarks)
        return self._done("soundlab-landmarks-moved", offer)


def _desk_halves(projection) -> tuple[tuple[int, int, int, int], tuple[int, int, int, int]]:
    """Desk's two tiles when it holds two applets: the screen above the
    taskbar split in two columns, one divider cell between them."""

    width = (projection.cols - 1) // 2
    bottom = max(1, projection.rows - 1)
    return (0, 0, width, bottom), (width + 1, 0, projection.cols, bottom)


def _observatory_plot(offer, bounds):
    """Observatory's plot inside BOUNDS: the plot's rectangle and its
    series' samples as (tick, value) pairs, once its baseline lies along
    the row below it; or None while it shows none."""

    plane = offer.retained
    if plane is None:
        return None
    left, top, right, bottom = bounds
    plots, lines = [], []
    for region in plane.regions:
        for draw in region.draws:
            if not isinstance(draw, (PlotDraw, PolylineDraw)):
                continue
            logical, visible = _visible_draw_rectangle(
                region, draw, offer.cell.cols, offer.cell.rows)
            if not (left <= logical.left and logical.right <= right
                    and top <= logical.top and logical.bottom <= bottom):
                continue
            if visible != logical:
                raise PhysicalDesktopAcceptanceError("Observatory's plot is clipped")
            (plots if isinstance(draw, PlotDraw) else lines).append((region, logical, draw))
    if not plots and not lines:
        return None
    if len(plots) != 1 or len(lines) != 1:
        raise PhysicalDesktopAcceptanceError(
            f"Observatory shows {len(plots)} plots and {len(lines)} lines")
    (region, plot, draw), (_, baseline, line) = plots[0], lines[0]
    color = (draw.line.red, draw.line.green, draw.line.blue, draw.line.alpha)
    if color != OBSERVATORY_PLOT_LINE or draw.fill_to_minimum:
        raise PhysicalDesktopAcceptanceError("Observatory's plot changed its style")
    shade = (line.color.red, line.color.green, line.color.blue, line.color.alpha)
    if (shade != OBSERVATORY_BASELINE or line.closed
            or (baseline.left, baseline.right, baseline.top) != (plot.left, plot.right, plot.bottom)
            or baseline.bottom - baseline.top != 1
            or [(point.x, point.y) for point in line.points]
            != [(0, 0x7FFFFFFF), (0xFFFFFFFF, 0x7FFFFFFF)]):
        raise PhysicalDesktopAcceptanceError("Observatory's baseline is not the row below its plot")
    histories = [history for history in plane.series
                 if history.key == (region.owner_id, region.owner_generation, draw.series_id)]
    if len(histories) != 1:
        raise PhysicalDesktopAcceptanceError("Observatory's plot names no series of its own")
    samples = tuple((sample.timestamp_us, sample.value) for sample in histories[0].samples)
    if samples:
        values = [value for _, value in samples]
        low, high = min(values), max(values)
        if low == high:
            low, high = low - 1, high + 1
        if (draw.minimum, draw.maximum) != (low, high):
            raise PhysicalDesktopAcceptanceError("Observatory's plot range is not its series' own")
        if draw.draw_points != (len(samples) <= plot.right - plot.left):
            raise PhysicalDesktopAcceptanceError("Observatory's plot marks the wrong samples")
    return plot, samples


def _observatory_table(offer, bounds) -> tuple[tuple[int, int], ...]:
    """The samples Observatory's table shows inside BOUNDS, as (tick, value)."""

    plane = offer.retained
    grids = [draw for region in plane.regions for draw in region.draws
             if isinstance(draw, TextGridDraw)
             and bounds[0] <= _visible_draw_rectangle(region, draw, offer.cell.cols,
                                                      offer.cell.rows)[0].left < bounds[2]]
    if len(grids) != 1:
        raise PhysicalDesktopAcceptanceError(f"Observatory shows {len(grids)} tables")
    cells = {(item.row, item.column): item.text for item in grids[0].content.items}
    rows = sorted({row for row, _ in cells if row > 0})
    return tuple((int(cells[row, 0]), int(cells[row, 1])) for row in rows)


class ObservatoryJourney(_AppletJourney):
    """Desk with Observatory and Worlds: Observatory's plot goes out as a
    PLOT over an exact series, its baseline a line along the row below.

    Observatory first plots its own starting series.  Worlds then steps its
    run and Analyze hands the run's telemetry over: Observatory's series is
    replaced, and the plot's series holds exactly the samples its table
    shows.  R profiles the series again and the plot stays.
    """

    focus_marker = OBSERVATORY_FOCUS_MARKER
    (READY, WORLDS, STEPPED, ANALYZE, ANALYZED, RERUN) = range(6)

    def __init__(self, ready_markers):
        super().__init__(ready_markers)
        self._steps = 0
        self._analyzed = None

    @property
    def final_stage(self) -> int:
        return self.RERUN

    @property
    def final_cell_markers(self) -> tuple[str, ...]:
        return (OBSERVATORY_FOCUS_MARKER, OBSERVATORY_PLOT_CAPTION)

    def _admit(self, offer, generation, projection, sender) -> bool:
        """As every applet journey admits a frame, except that focus moves
        to Worlds and back, which each stage checks for itself."""

        if self.stage == self.READY:
            return super()._admit(offer, generation, projection, sender)
        if self._frame_lineage(offer, generation) != self._lineage:
            raise PhysicalDesktopAcceptanceError(
                "physical acceptance frame left its original session lineage")
        if offer.offer_id <= self.frame_barrier:
            return False
        self._pending = None
        if not self._deliver_owed_pointer(offer, generation, sender):
            self.waiting = "the rest of a pointer gesture"
            return False
        return True

    def _shown(self, offer, observatory):
        shown = _observatory_plot(offer, observatory)
        if shown is None:
            return None
        plot, samples = shown
        table = _observatory_table(offer, observatory)
        if samples[:len(table)] != table:
            raise PhysicalDesktopAcceptanceError(
                "Observatory's plot holds other samples than its table shows")
        _require_cell_text_in(offer, OBSERVATORY_PLOT_CAPTION, observatory, "Observatory's tile")
        return samples

    def after_present(self, offer, generation, projection, sender) -> JourneyProgress:
        if not self._admit(offer, generation, projection, sender):
            return JourneyProgress()
        observatory, worlds = _desk_halves(projection)
        if self.stage == self.READY:
            samples = self._shown(offer, observatory)
            if samples is None:
                return self._wait("Observatory's plot of its starting series")
            if samples != OBSERVATORY_DEMO_SERIES:
                raise PhysicalDesktopAcceptanceError(
                    f"Observatory's starting plot holds {samples!r}")
            return self._step("observatory-plot-shown", "send_key", "alt+2",
                              self.WORLDS, offer, generation, sender)
        if self.stage in (self.WORLDS, self.STEPPED, self.ANALYZE):
            if not _taskbar_has_focus(projection, WORLDS_FOCUS_MARKER):
                if self.stage == self.WORLDS:
                    return self._wait(f"{WORLDS_FOCUS_MARKER} after Alt+2")
                raise PhysicalDesktopAcceptanceError("Worlds lost focus")
        if self.stage in (self.WORLDS, self.STEPPED):
            if self._steps < WORLDS_STEPS:
                self._steps += 1
                return self._step(f"worlds-step-{self._steps}", "send_key", "s",
                                  self.STEPPED, offer, generation, sender)
            return self._step("worlds-analyze", "send_key", "a",
                              self.ANALYZE, offer, generation, sender)
        if self.stage == self.ANALYZE:
            # Worlds' notice that Observatory accepted the run lasts a moment
            # only; the plot itself shows the handover.
            samples = self._shown(offer, observatory)
            if samples is None or samples == OBSERVATORY_DEMO_SERIES:
                return self._wait("Observatory's plot of Worlds' telemetry")
            if len(samples) < 2:
                raise PhysicalDesktopAcceptanceError("Worlds handed over one sample")
            self._analyzed = samples
            return self._step("observatory-plots-telemetry", "send_key", "alt+1",
                              self.ANALYZED, offer, generation, sender)
        if not _taskbar_has_focus(projection, OBSERVATORY_FOCUS_MARKER):
            if self.stage == self.ANALYZED:
                return self._wait(f"{OBSERVATORY_FOCUS_MARKER} after Alt+1")
            raise PhysicalDesktopAcceptanceError("Observatory lost focus")
        samples = self._shown(offer, observatory)
        if samples != self._analyzed:
            raise PhysicalDesktopAcceptanceError("Observatory's plot changed before its rerun")
        if self.stage == self.ANALYZED:
            return self._step("observatory-rerun", "send_key", "r",
                              self.RERUN, offer, generation, sender)
        profiled = OBSERVATORY_PROFILED + f"{len(samples)} samples"
        if not _status_shows(projection, profiled, observatory):
            return self._wait(f"Observatory's status {profiled!r}")
        return self._done("observatory-rerun-kept-plot", offer)


def applet_journey(
    name: str, ready_markers: tuple[str, ...], *, paced_link: bool = False
) -> FrameBoundJourney:
    """The journey for Desk holding only the applet NAME, or for the check
    NAME of Desk holding one applet.  On a PACED_LINK, File Explorer's also
    checks that the screen answers input while a picture uploads."""

    journeys = {
        "pad": PadAloneJourney,
        "fexp": FexpAloneJourney,
        "daybook": DaybookAloneJourney,
        "streams": StreamsAloneJourney,
        "agent": AgentAloneJourney,
        "soundlab": SoundLabAloneJourney,
        "observatory": ObservatoryJourney,
        "small-terminal": SmallTerminalJourney,
        "photo": PhotoJourney,
        "damaged": DamagedPictureJourney,
    }
    if name not in journeys:
        raise ValueError(f"no journey for Desk with only {name!r}")
    if name == "fexp":
        return FexpAloneJourney(ready_markers, paced_link=paced_link)
    return journeys[name](ready_markers)
