"""Physical rich-terminal acceptance for the ordinary Akashic Desktop.

This runner is deliberately outside the product renderer and protocol.  It
holds the normal shared-session display lease, uses MegaPad's real pygame
viewer compositor, flips the selected video sink, acknowledges that exact
offer, and only then sends ordinary Desk input carrying the same proof.
"""

from __future__ import annotations

import hashlib
import json
import os
import socket
import struct
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from display import VirtualTerminal
from rich_terminal.pygame_view import (
    composite_draw_plane,
    unorm_high_edge,
    unorm_low_edge,
)
from session import TerminalDisplayOffer
from session_viewer import (
    _GuestKeyboardForwarder,
    _RetainedDisplayState,
    _accept_screen_update,
    _accept_status_update,
    _display_claimed,
    compose_terminal_frame,
    draw_flip_and_present,
)
from shared_session import SessionClient, display_scope_to_wire


PAD_ACCEPTANCE_TEXT = "rich vertical"
DAYBOOK_ACCEPTANCE_TASK = "Rich terminal acceptance"
PAD_FOCUS_MARKER = "[1:Akashic Pa*]"
DAYBOOK_FOCUS_MARKER = "[3:Daybook*]"
DAYBOOK_PROMPT_MARKER = "New task:"
MIN_READABLE_FONT_SIZE = 12


class PhysicalDesktopAcceptanceError(RuntimeError):
    """The physical Desk/Pad/Daybook contract was not completed."""


@dataclass(frozen=True)
class RichScreenProjection:
    """Validated full-screen text reconstructed only from retained glyphs."""

    cols: int
    rows: int
    lines: tuple[str, ...]
    draw_count: int

    @property
    def text(self) -> str:
        return "\n".join(self.lines)


@dataclass(frozen=True)
class PresentedFrameEvidence:
    milestone: str
    offer_id: int
    generation: int
    scope: dict[str, object]
    draw_count: int
    pixel_sha256: str
    retained_text_sha256: str
    retained_only_sha256: str
    retained_only_nonblack_pixels: int
    png_path: Path
    retained_png_path: Path
    retained_text_path: Path

    def to_dict(self) -> dict[str, object]:
        return {
            "milestone": self.milestone,
            "offer_id": self.offer_id,
            "generation": self.generation,
            "scope": self.scope,
            "draw_count": self.draw_count,
            "pixel_sha256": self.pixel_sha256,
            "retained_text_sha256": self.retained_text_sha256,
            "retained_only_sha256": self.retained_only_sha256,
            "retained_only_nonblack_pixels": (
                self.retained_only_nonblack_pixels
            ),
            "png_path": str(self.png_path),
            "retained_png_path": str(self.retained_png_path),
            "retained_text_path": str(self.retained_text_path),
        }


@dataclass(frozen=True)
class AcceptedInputEvidence:
    method: str
    value: str
    offer_id: int
    generation: int
    scope: dict[str, object]

    def to_dict(self) -> dict[str, object]:
        return {
            "method": self.method,
            "value": self.value,
            "offer_id": self.offer_id,
            "generation": self.generation,
            "scope": self.scope,
        }


@dataclass(frozen=True)
class PhysicalDesktopAcceptanceEvidence:
    manifest_path: Path
    video_driver: str
    frames: tuple[PresentedFrameEvidence, ...]
    inputs: tuple[AcceptedInputEvidence, ...]


def reconstruct_full_screen_glyphs(
    offer: TerminalDisplayOffer,
) -> RichScreenProjection:
    """Validate and reconstruct one complete row-major retained screen."""

    if not isinstance(offer, TerminalDisplayOffer):
        raise TypeError("offer must be TerminalDisplayOffer")
    scope = offer.scope
    plane = offer.retained
    cell = offer.cell
    if scope.retained_revision is None:
        raise PhysicalDesktopAcceptanceError(
            "display offer has no retained frame identity"
        )
    if plane is None or not plane.retained_initialized or not plane.retained_visible:
        raise PhysicalDesktopAcceptanceError(
            "display offer does not carry a visible initialized retained plane"
        )
    if len(plane.regions) != 1:
        raise PhysicalDesktopAcceptanceError(
            "retained screen must contain exactly one full-screen region"
        )
    region = plane.regions[0]
    expected_region = (0, 0, cell.cols, cell.rows)
    actual_region = (
        region.cell_x,
        region.cell_y,
        region.cell_cols,
        region.cell_rows,
    )
    if actual_region != expected_region:
        raise PhysicalDesktopAcceptanceError(
            f"retained region {actual_region!r} is not full screen "
            f"{expected_region!r}"
        )
    expected_count = cell.cols * cell.rows
    if len(region.draws) != expected_count:
        raise PhysicalDesktopAcceptanceError(
            f"retained screen has {len(region.draws)} glyph draws; "
            f"expected {expected_count}"
        )

    ordered = sorted(region.draws, key=lambda draw: draw.object_id)
    expected_ids = range(1, expected_count + 1)
    if any(draw.object_id != expected for draw, expected in zip(ordered, expected_ids)):
        raise PhysicalDesktopAcceptanceError(
            "retained glyph object identities are not contiguous row-major cells"
        )

    glyphs: list[str] = []
    covered: set[tuple[int, int]] = set()
    for index, draw in enumerate(ordered):
        if len(draw.text) != 1:
            raise PhysicalDesktopAcceptanceError(
                f"retained cell object {draw.object_id} does not contain one scalar"
            )
        left = unorm_low_edge(draw.bounds.left, cell.cols)
        right = unorm_high_edge(draw.bounds.right, cell.cols)
        top = unorm_low_edge(draw.bounds.top, cell.rows)
        bottom = unorm_high_edge(draw.bounds.bottom, cell.rows)
        coordinate = (left, top)
        expected_coordinate = (index % cell.cols, index // cell.cols)
        if (
            right - left != 1
            or bottom - top != 1
            or coordinate != expected_coordinate
            or coordinate in covered
        ):
            raise PhysicalDesktopAcceptanceError(
                f"retained object {draw.object_id} does not cover its exact "
                f"row-major cell {expected_coordinate!r}"
            )
        covered.add(coordinate)
        glyphs.append(draw.text)
    if len(covered) != expected_count:
        raise PhysicalDesktopAcceptanceError(
            "retained glyph plane does not uniquely cover every screen cell"
        )
    lines = tuple(
        "".join(glyphs[row * cell.cols : (row + 1) * cell.cols])
        for row in range(cell.rows)
    )
    return RichScreenProjection(cell.cols, cell.rows, lines, expected_count)


InputSender = Callable[[str, str, TerminalDisplayOffer, int], str]


@dataclass(frozen=True)
class JourneyProgress:
    milestone: str | None = None
    complete: bool = False


class DesktopAcceptanceJourney:
    """Advance app input only across newly acknowledged physical frames."""

    def __init__(self, ready_markers: tuple[str, ...]):
        if not ready_markers or any(not marker for marker in ready_markers):
            raise ValueError("ready_markers must contain visible strings")
        self.ready_markers = tuple(ready_markers)
        self.stage = 0
        self.frame_barrier = 0
        self._pending: tuple[str, str, int] | None = None
        self._recorded: set[str] = set()

    @property
    def has_pending_input(self) -> bool:
        return self._pending is not None

    def _milestone(self, name: str) -> str | None:
        if name in self._recorded:
            return None
        self._recorded.add(name)
        return name

    def _send(
        self,
        method: str,
        value: str,
        target_stage: int,
        offer: TerminalDisplayOffer,
        generation: int,
        sender: InputSender,
    ) -> None:
        status = sender(method, value, offer, generation)
        if status == "progress":
            self.stage = target_stage
            self._pending = None
        elif status == "backpressured":
            self._pending = (method, value, target_stage)
        else:
            raise PhysicalDesktopAcceptanceError(
                f"viewer-owned {method} input was rejected as {status!r}"
            )
        self.frame_barrier = offer.offer_id

    def retry_pending_current(
        self,
        offer: TerminalDisplayOffer,
        generation: int,
        sender: InputSender,
    ) -> bool:
        """Retry backpressured input against the same acknowledged frame."""

        if self._pending is None:
            return False
        method, value, target_stage = self._pending
        self._send(
            method,
            value,
            target_stage,
            offer,
            generation,
            sender,
        )
        return True

    def after_present(
        self,
        offer: TerminalDisplayOffer,
        generation: int,
        projection: RichScreenProjection,
        sender: InputSender,
    ) -> JourneyProgress:
        """Observe one successfully presented frame and maybe send one action."""

        if offer.offer_id <= self.frame_barrier:
            return JourneyProgress()
        text = projection.text
        if self._pending is not None:
            method, value, target_stage = self._pending
            self._send(
                method,
                value,
                target_stage,
                offer,
                generation,
                sender,
            )
            return JourneyProgress()

        if self.stage == 0 and all(marker in text for marker in self.ready_markers):
            milestone = self._milestone("desk-complete")
            self._send("send_key", "alt+1", 1, offer, generation, sender)
            return JourneyProgress(milestone)
        if self.stage == 1 and PAD_FOCUS_MARKER in text:
            self._send(
                "send_text",
                PAD_ACCEPTANCE_TEXT,
                2,
                offer,
                generation,
                sender,
            )
            return JourneyProgress()
        if self.stage == 2 and PAD_ACCEPTANCE_TEXT in text:
            milestone = self._milestone("pad-edited")
            self._send("send_key", "alt+3", 3, offer, generation, sender)
            return JourneyProgress(milestone)
        if self.stage == 3 and DAYBOOK_FOCUS_MARKER in text:
            self._send("send_key", "ctrl+n", 4, offer, generation, sender)
            return JourneyProgress()
        if self.stage == 4 and DAYBOOK_PROMPT_MARKER in text:
            self._send(
                "send_text",
                DAYBOOK_ACCEPTANCE_TASK,
                5,
                offer,
                generation,
                sender,
            )
            return JourneyProgress()
        if self.stage == 5 and DAYBOOK_ACCEPTANCE_TASK in text:
            self._send("send_key", "enter", 6, offer, generation, sender)
            return JourneyProgress()
        if (
            self.stage == 6
            and DAYBOOK_ACCEPTANCE_TASK in text
            and DAYBOOK_PROMPT_MARKER not in text
        ):
            self.frame_barrier = offer.offer_id
            return JourneyProgress(
                self._milestone("daybook-task-added"),
                True,
            )
        return JourneyProgress()


def _surface_rgba(pygame_module, surface) -> bytes:
    return pygame_module.image.tostring(surface, "RGBA")


def _fit_viewer_font(
    pygame_module,
    font_path: Path | None,
    requested_size: int,
    cols: int,
    rows: int,
):
    """Choose the largest requested font that fits the physical display."""

    display = pygame_module.display.Info()
    max_width = max(1, int(display.current_w * 0.92))
    max_height = max(1, int(display.current_h * 0.86))
    smallest = min(MIN_READABLE_FONT_SIZE, requested_size)
    for size in range(requested_size, smallest - 1, -1):
        font = (
            pygame_module.font.Font(str(font_path), size)
            if font_path is not None
            else pygame_module.font.SysFont("monospace", size)
        )
        cell_width = max(1, font.size("M")[0])
        cell_height = font.get_linesize()
        if cols * cell_width <= max_width and rows * cell_height <= max_height:
            return font, cell_width, cell_height, size
    raise PhysicalDesktopAcceptanceError(
        f"{cols}x{rows} terminal does not fit the {display.current_w}x"
        f"{display.current_h} physical display at readable font size "
        f"{smallest}"
    )


def _keep_window_visible(
    pygame_module,
    seconds: float,
    *,
    closing_is_error: bool,
) -> None:
    until = time.monotonic() + seconds
    while time.monotonic() < until:
        for event in pygame_module.event.get():
            if event.type == pygame_module.QUIT:
                if closing_is_error:
                    raise PhysicalDesktopAcceptanceError(
                        "physical acceptance window was closed"
                    )
                return
        time.sleep(min(0.02, max(0.0, until - time.monotonic())))


def _record_frame(
    pygame_module,
    font,
    cell_width: int,
    cell_height: int,
    artifact_root: Path,
    milestone: str,
    offer: TerminalDisplayOffer,
    generation: int,
    projection: RichScreenProjection,
    composed_surface,
) -> PresentedFrameEvidence:
    png_path = (artifact_root / f"{milestone}.png").resolve()
    retained_path = (artifact_root / f"{milestone}-retained-only.png").resolve()
    text_path = (artifact_root / f"{milestone}-retained.txt").resolve()
    pygame_module.image.save(composed_surface, str(png_path))
    composed_bytes = _surface_rgba(pygame_module, composed_surface)

    retained_surface = pygame_module.Surface(
        composed_surface.get_size(), flags=pygame_module.SRCALPHA
    )
    retained_surface.fill((0, 0, 0, 0))
    composite_draw_plane(
        pygame_module,
        retained_surface,
        offer.retained,
        font,
        cell_width,
        cell_height,
    )
    retained_bytes = _surface_rgba(pygame_module, retained_surface)
    nonblack = sum(
        any(retained_bytes[offset : offset + 3])
        for offset in range(0, len(retained_bytes), 4)
    )
    if nonblack == 0:
        raise PhysicalDesktopAcceptanceError(
            f"{milestone} retained compositor produced no non-black "
            "physical pixels"
        )
    pygame_module.image.save(retained_surface, str(retained_path))
    text_path.write_text(projection.text, encoding="utf-8")
    retained_text_bytes = projection.text.encode("utf-8")
    return PresentedFrameEvidence(
        milestone=milestone,
        offer_id=offer.offer_id,
        generation=generation,
        scope=display_scope_to_wire(offer.scope),
        draw_count=projection.draw_count,
        pixel_sha256=hashlib.sha256(composed_bytes).hexdigest(),
        retained_text_sha256=hashlib.sha256(retained_text_bytes).hexdigest(),
        retained_only_sha256=hashlib.sha256(retained_bytes).hexdigest(),
        retained_only_nonblack_pixels=nonblack,
        png_path=png_path,
        retained_png_path=retained_path,
        retained_text_path=text_path,
    )


def write_acceptance_manifest(
    artifact_root: Path,
    video_driver: str,
    frames: tuple[PresentedFrameEvidence, ...],
    inputs: tuple[AcceptedInputEvidence, ...],
) -> Path:
    artifact_root = Path(artifact_root).resolve()
    artifact_root.mkdir(parents=True, exist_ok=True)
    manifest_path = artifact_root / "manifest.json"
    payload = {
        "video_driver": video_driver,
        "physical_boundary": "pygame.display.flip",
        "frames": [frame.to_dict() for frame in frames],
        "inputs": [event.to_dict() for event in inputs],
    }
    manifest_path.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return manifest_path


def _connected_peer_pid(client: SessionClient) -> int:
    if not hasattr(socket, "SO_PEERCRED"):
        raise PhysicalDesktopAcceptanceError(
            "physical acceptance requires Unix SO_PEERCRED process binding"
        )
    connection = client._socket
    if connection is None:
        raise PhysicalDesktopAcceptanceError(
            "shared-session client has no connected socket"
        )
    credentials = connection.getsockopt(
        socket.SOL_SOCKET,
        socket.SO_PEERCRED,
        struct.calcsize("3i"),
    )
    peer_pid, _peer_uid, _peer_gid = struct.unpack("3i", credentials)
    return peer_pid


def _connect(
    socket_path: str,
    deadline: float,
    expected_server_pid: int,
) -> SessionClient:
    if (
        isinstance(expected_server_pid, bool)
        or not isinstance(expected_server_pid, int)
        or expected_server_pid <= 0
    ):
        raise ValueError("expected_server_pid must be a positive process id")
    last_error: OSError | None = None
    while time.monotonic() < deadline:
        client = SessionClient(socket_path, timeout=2.0)
        try:
            client.connect()
        except OSError as exc:
            last_error = exc
            client.close()
            time.sleep(0.05)
            continue
        peer_pid = _connected_peer_pid(client)
        if peer_pid != expected_server_pid:
            client.close()
            raise PhysicalDesktopAcceptanceError(
                f"shared-session socket belongs to process {peer_pid}, not "
                f"the launched server process {expected_server_pid}"
            )
        return client
    raise PhysicalDesktopAcceptanceError(
        f"shared-session server did not become reachable: {last_error}"
    )


def run_physical_desktop_acceptance(
    socket_path: str,
    artifact_root: Path,
    *,
    expected_server_pid: int,
    cols: int,
    rows: int,
    ready_markers: tuple[str, ...],
    timeout: float = 180.0,
    font_path: Path | None = None,
    font_size: int = 18,
    action_delay: float = 0.75,
    hold_seconds: float = 10.0,
) -> PhysicalDesktopAcceptanceEvidence:
    """Run and record the real Desk/Pad/Daybook physical-view journey."""

    if timeout <= 0:
        raise ValueError("timeout must be positive")
    if cols <= 0 or rows <= 0:
        raise ValueError("terminal dimensions must be positive")
    if font_size <= 0:
        raise ValueError("font_size must be positive")
    if action_delay < 0:
        raise ValueError("action_delay must not be negative")
    if hold_seconds < 0:
        raise ValueError("hold_seconds must not be negative")
    artifact_root = Path(artifact_root).resolve()
    artifact_root.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + timeout
    client = _connect(socket_path, deadline, expected_server_pid)
    pygame_initialized = False
    try:
        try:
            import pygame
        except ImportError as exc:
            raise PhysicalDesktopAcceptanceError(
                "physical desktop acceptance requires pygame"
            ) from exc

        if not _display_claimed(client.request("claim_display")):
            raise PhysicalDesktopAcceptanceError(
                "physical acceptance could not claim the display lease"
            )
        status = client.request("status", detailed=False)
        generation = int(status["generation"])
        display_required = bool(status["rich_terminal"]["display_required"])
        terminal = VirtualTerminal(cols=cols, rows=rows)
        revision = -1
        display_state = _RetainedDisplayState()
        keyboard = _GuestKeyboardForwarder(
            pygame,
            client,
            generation=generation,
            input_enabled=True,
            display_required=display_required,
        )

        os.environ.setdefault("SDL_VIDEO_CENTERED", "1")
        pygame.display.init()
        pygame_initialized = True
        pygame.font.init()
        driver = pygame.display.get_driver()
        if driver.lower() in {"dummy", "offscreen"}:
            raise PhysicalDesktopAcceptanceError(
                f"SDL video driver {driver!r} is not a physical display sink"
            )
        font, cell_width, cell_height, fitted_font_size = _fit_viewer_font(
            pygame,
            font_path,
            font_size,
            terminal.cols,
            terminal.rows,
        )
        window = pygame.display.set_mode(
            (terminal.cols * cell_width, terminal.rows * cell_height)
        )
        print(
            "Physical viewer: "
            f"{terminal.cols}x{terminal.rows} cells, "
            f"{terminal.cols * cell_width}x"
            f"{terminal.rows * cell_height} pixels, "
            f"{fitted_font_size}px font, {driver} driver"
        )
        pygame.display.set_caption(
            "Akashic rich-terminal acceptance — starting "
            f"({fitted_font_size}px)"
        )
        glyph_cache: dict = {}
        journey = DesktopAcceptanceJourney(tuple(ready_markers))
        frames: list[PresentedFrameEvidence] = []
        inputs: list[AcceptedInputEvidence] = []
        last_accepted_offer: TerminalDisplayOffer | None = None
        last_accepted_generation: int | None = None

        def send_input(
            method: str,
            value: str,
            offer: TerminalDisplayOffer,
            input_generation: int,
        ) -> str:
            _keep_window_visible(
                pygame,
                action_delay,
                closing_is_error=True,
            )
            params: dict[str, object] = {
                "generation": input_generation,
                "display_offer_id": offer.offer_id,
                "display_scope": display_scope_to_wire(offer.scope),
            }
            if method == "send_key":
                params["key"] = value
            elif method == "send_text":
                params["text"] = value
            else:
                raise PhysicalDesktopAcceptanceError(
                    f"unsupported acceptance input method {method!r}"
                )
            response = client.request(method, **params)
            input_status = response.get("status")
            if input_status == "progress":
                expected_field = (
                    "accepted_events" if method == "send_key" else "accepted_bytes"
                )
                expected_value = (
                    1
                    if method == "send_key"
                    else len(value.encode("utf-8"))
                )
                if response.get(expected_field) != expected_value:
                    raise PhysicalDesktopAcceptanceError(
                        f"{method} reported partial acceptance"
                    )
                inputs.append(
                    AcceptedInputEvidence(
                        method,
                        value,
                        offer.offer_id,
                        input_generation,
                        display_scope_to_wire(offer.scope),
                    )
                )
            if input_status not in {"progress", "backpressured"}:
                raise PhysicalDesktopAcceptanceError(
                    f"{method} returned invalid status {input_status!r}"
                )
            return str(input_status)

        while time.monotonic() < deadline:
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    raise PhysicalDesktopAcceptanceError(
                        "physical acceptance window was closed"
                    )

            status = client.request("status", detailed=False)
            revision, _ = _accept_status_update(
                status,
                keyboard=keyboard,
                display_state=display_state,
                revision=revision,
            )
            update = client.request(
                "screen",
                since=revision,
                since_offer=display_state.since_offer,
            )
            revision, resized = _accept_screen_update(
                update,
                display_holder=True,
                terminal=terminal,
                keyboard=keyboard,
                display_state=display_state,
                revision=revision,
            )
            if resized:
                font, cell_width, cell_height, fitted_font_size = (
                    _fit_viewer_font(
                        pygame,
                        font_path,
                        font_size,
                        terminal.cols,
                        terminal.rows,
                    )
                )
                glyph_cache.clear()
                window = pygame.display.set_mode(
                    (terminal.cols * cell_width, terminal.rows * cell_height)
                )
                print(
                    "Physical viewer resized: "
                    f"{terminal.cols}x{terminal.rows} cells, "
                    f"{terminal.cols * cell_width}x"
                    f"{terminal.rows * cell_height} pixels, "
                    f"{fitted_font_size}px font"
                )
                pygame.display.set_caption(
                    "Akashic rich-terminal acceptance — running "
                    f"({fitted_font_size}px)"
                )

            frame_offer = display_state.pending_offer
            frame_generation = (
                keyboard.generation
                if display_state.pending_generation is None
                else display_state.pending_generation
            )
            frame_projection = (
                None
                if frame_offer is None
                else reconstruct_full_screen_glyphs(frame_offer)
            )
            composed_surface = None

            def draw_frame() -> None:
                nonlocal composed_surface
                window.fill((0, 0, 0))
                composed_surface = compose_terminal_frame(
                    pygame,
                    terminal,
                    font,
                    cell_width,
                    cell_height,
                    retained_plane=display_state.frame_plane,
                    show_cursor=True,
                    glyph_cache=glyph_cache,
                )
                window.blit(composed_surface, (0, 0))

            presentation = draw_flip_and_present(
                pygame,
                client,
                draw_frame,
                offer=frame_offer,
                generation=frame_generation,
                active=True,
            )
            if frame_offer is None:
                if (
                    journey.has_pending_input
                    and last_accepted_offer is not None
                    and last_accepted_generation is not None
                ):
                    journey.retry_pending_current(
                        last_accepted_offer,
                        last_accepted_generation,
                        send_input,
                    )
                time.sleep(0.01)
                continue
            accepted_revision = display_state.finish_presentation(presentation)
            if accepted_revision is None:
                revision = -1
                keyboard.clear_display_context(waiting=True)
                time.sleep(0.01)
                continue
            revision = accepted_revision
            keyboard.acknowledge_display_offer(
                frame_offer.offer_id,
                frame_offer.scope,
            )
            if frame_projection is None:
                raise PhysicalDesktopAcceptanceError(
                    "accepted display offer lost its retained projection"
                )
            last_accepted_offer = frame_offer
            last_accepted_generation = frame_generation
            progress = journey.after_present(
                frame_offer,
                frame_generation,
                frame_projection,
                send_input,
            )
            pygame.display.set_caption(
                "Akashic rich-terminal acceptance — "
                f"stage {journey.stage}/6 ({fitted_font_size}px)"
            )
            if progress.milestone is not None:
                if composed_surface is None:
                    raise PhysicalDesktopAcceptanceError(
                        "physical compositor produced no frame surface"
                    )
                frames.append(
                    _record_frame(
                        pygame,
                        font,
                        cell_width,
                        cell_height,
                        artifact_root,
                        progress.milestone,
                        frame_offer,
                        frame_generation,
                        frame_projection,
                        composed_surface,
                    )
                )
            if progress.complete:
                manifest = write_acceptance_manifest(
                    artifact_root,
                    driver,
                    tuple(frames),
                    tuple(inputs),
                )
                pygame.display.set_caption(
                    "Akashic rich-terminal acceptance — PASS "
                    f"({fitted_font_size}px)"
                )
                _keep_window_visible(
                    pygame,
                    hold_seconds,
                    closing_is_error=False,
                )
                return PhysicalDesktopAcceptanceEvidence(
                    manifest,
                    driver,
                    tuple(frames),
                    tuple(inputs),
                )
            time.sleep(0.01)
        raise PhysicalDesktopAcceptanceError(
            f"physical Desktop journey timed out at stage {journey.stage}"
        )
    except PhysicalDesktopAcceptanceError:
        raise
    except (ConnectionError, OSError, RuntimeError, TypeError, ValueError) as exc:
        raise PhysicalDesktopAcceptanceError(str(exc)) from exc
    finally:
        client.close()
        if pygame_initialized:
            try:
                pygame.quit()
            except Exception:
                pass


__all__ = [
    "DAYBOOK_ACCEPTANCE_TASK",
    "DesktopAcceptanceJourney",
    "PAD_ACCEPTANCE_TEXT",
    "PhysicalDesktopAcceptanceError",
    "PhysicalDesktopAcceptanceEvidence",
    "PresentedFrameEvidence",
    "AcceptedInputEvidence",
    "RichScreenProjection",
    "reconstruct_full_screen_glyphs",
    "run_physical_desktop_acceptance",
    "write_acceptance_manifest",
]
