#!/usr/bin/env python3
"""Build, smoke-test, and serve bootable Akashic TUI environments.

This is the supported cross-repository harness.  It imports the sibling
MegaPad checkout (or ``MEGAPAD_ROOT``), computes the transitive REQUIRE
closure for the selected app profile, and preserves Akashic's paths in an
MP64FS image.  No private emulator copy is required.
"""

from __future__ import annotations

import argparse
import os
import posixpath
import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path, PurePosixPath


AKASHIC_ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = AKASHIC_ROOT / "akashic"
DEFAULT_MEGAPAD_ROOT = AKASHIC_ROOT.parent / "megapad"
OUTPUT_ROOT = AKASHIC_ROOT / "local_testing" / "out"
REQUIRE_RE = re.compile(r"^\s*REQUIRE\s+(\S+)", re.MULTILINE)


def _megapad_root() -> Path:
    configured = os.environ.get("MEGAPAD_ROOT")
    root = Path(configured).expanduser() if configured else DEFAULT_MEGAPAD_ROOT
    root = root.resolve()
    required = ("bios.asm", "kdos.f", "diskutil.py", "session.py")
    missing = [name for name in required if not (root / name).is_file()]
    if missing:
        detail = ", ".join(missing)
        raise RuntimeError(
            f"MegaPad checkout not found at {root} (missing: {detail}). "
            "Set MEGAPAD_ROOT to the emulator repository."
        )
    return root


MEGAPAD_ROOT = _megapad_root()
sys.path.insert(0, str(MEGAPAD_ROOT))

from diskutil import (  # noqa: E402
    FLAG_SYSTEM,
    FTYPE_FORTH,
    FTYPE_TEXT,
    MAX_FILES,
    MAX_NAME_LEN,
    MP64FS,
)
from session import MachineSession  # noqa: E402


@dataclass(frozen=True)
class Profile:
    roots: tuple[str, ...]
    resources: tuple[str, ...]
    autoexec: str
    ready_markers: tuple[str, ...]
    stable_markers: tuple[str, ...]


PROFILES = {
    "desktop": Profile(
        roots=(
            "tui/applets/desk/desk.f",
            "tui/applets/pad/pad.f",
            "tui/applets/fexplorer/fexplorer.f",
        ),
        resources=(
            "tui/applets/desk/desk.toml",
            "tui/applets/pad/pad.uidl",
            "tui/applets/pad/pad.toml",
            "tui/applets/fexplorer/fexplorer.uidl",
            "tui/applets/fexplorer/fexplorer.toml",
        ),
        autoexec=r"""\ autoexec.f - Akashic desktop profile
ENTER-USERLAND
." [akashic] loading desktop" CR
REQUIRE tui/applets/desk/desk.f
REQUIRE tui/applets/pad/pad.f
REQUIRE tui/applets/fexplorer/fexplorer.f

CREATE _boot-pad-desc APP-DESC ALLOT
_boot-pad-desc PAD-ENTRY
_boot-pad-desc DESK-QUEUE-LAUNCH

CREATE _boot-fexp-desc APP-DESC ALLOT
_boot-fexp-desc FEXP-ENTRY
_boot-fexp-desc DESK-QUEUE-LAUNCH

." [akashic] starting desktop" CR
DESK-RUN
." [akashic] desktop exited" CR
""",
        ready_markers=("Selection", "Untitled", "Details", "Preview", "Tools"),
        stable_markers=("Selection", "UTF-8", "Details", "Preview", "Tools"),
    ),
    "pad": Profile(
        roots=("tui/applets/pad/pad.f",),
        resources=(
            "tui/applets/pad/pad.uidl",
            "tui/applets/pad/pad.toml",
        ),
        autoexec=r"""\ autoexec.f - standalone Akashic Pad profile
ENTER-USERLAND
." [akashic] loading pad" CR
REQUIRE tui/applets/pad/pad.f
." [akashic] starting pad" CR
PAD-RUN
." [akashic] pad exited" CR
""",
        ready_markers=("File", "Edit", "UTF-8"),
        stable_markers=("File", "Edit", "UTF-8"),
    ),
    "fexplorer": Profile(
        roots=("tui/applets/fexplorer/fexplorer.f",),
        resources=(
            "tui/applets/fexplorer/fexplorer.uidl",
            "tui/applets/fexplorer/fexplorer.toml",
        ),
        autoexec=r"""\ autoexec.f - standalone File Explorer profile
ENTER-USERLAND
." [akashic] loading file explorer" CR
REQUIRE tui/applets/fexplorer/fexplorer.f
." [akashic] starting file explorer" CR
FEXP-RUN
." [akashic] file explorer exited" CR
""",
        ready_markers=("File", "Edit", "View", "Tools"),
        stable_markers=("File", "Edit", "View", "Tools"),
    ),
}


LARGE_SAMPLE = b"".join(
    f"Large fixture line {line:03d}: Pad crosses MP64FS sector boundaries.\n".encode()
    for line in range(1, 49)
)

SAMPLE_FILES = {
    "welcome.txt": b"Welcome to Akashic.\nThis file is editable in Pad.\n",
    "example.f": b": SQUARE DUP * ;\n9 SQUARE .\n",
    "large.txt": LARGE_SAMPLE,
}


def _normalize_module(module: str, requiring: str | None = None) -> str:
    if module.startswith("/"):
        normalized = posixpath.normpath(module.lstrip("/"))
    else:
        base = posixpath.dirname(requiring) if requiring else ""
        normalized = posixpath.normpath(posixpath.join(base, module))
    if normalized == ".." or normalized.startswith("../"):
        raise ValueError(f"REQUIRE escapes Akashic source root: {module!r}")
    return normalized


def dependency_closure(roots: tuple[str, ...]) -> tuple[str, ...]:
    """Return the deterministic transitive REQUIRE closure for *roots*."""
    pending = [_normalize_module(root) for root in reversed(roots)]
    seen: set[str] = set()

    while pending:
        module = pending.pop()
        if module in seen:
            continue
        host_path = SOURCE_ROOT / module
        if not host_path.is_file():
            raise FileNotFoundError(f"Missing Akashic module: {module}")
        seen.add(module)
        text = host_path.read_text(encoding="utf-8")
        dependencies = [
            _normalize_module(match.group(1), module)
            for match in REQUIRE_RE.finditer(text)
        ]
        pending.extend(reversed(dependencies))

    return tuple(sorted(seen))


def _directories(paths: set[str]) -> list[str]:
    directories: set[str] = set()
    for path in paths:
        parts = PurePosixPath(path).parts[:-1]
        for depth in range(1, len(parts) + 1):
            directories.add("/".join(parts[:depth]))
    return sorted(directories, key=lambda value: (value.count("/"), value))


def _validate_image_paths(paths: set[str], directories: list[str]):
    # Include kdos/autoexec and two temporary fragmentation fixtures.
    entries = len(paths) + len(directories) + len(SAMPLE_FILES) + 4
    if entries > MAX_FILES:
        raise RuntimeError(
            f"Profile needs {entries} MP64FS entries; filesystem limit is "
            f"{MAX_FILES}."
        )
    for path in paths | set(directories) | set(SAMPLE_FILES):
        name = PurePosixPath(path).name
        if len(name.encode("utf-8")) > MAX_NAME_LEN:
            raise RuntimeError(
                f"MP64FS name is too long ({len(name)} > {MAX_NAME_LEN}): {path}"
            )


def default_image_path(profile: str) -> Path:
    return OUTPUT_ROOT / f"akashic-{profile}.img"


def build_image(profile_name: str, output: Path | None = None) -> Path:
    profile = PROFILES[profile_name]
    modules = dependency_closure(profile.roots)
    resources = set(profile.resources)
    paths = set(modules) | resources
    directories = _directories(paths)
    _validate_image_paths(paths, directories)

    target = (output or default_image_path(profile_name)).resolve()
    target.parent.mkdir(parents=True, exist_ok=True)

    fs = MP64FS(total_sectors=4096)
    fs.format()
    fs.inject_file(
        "kdos.f",
        (MEGAPAD_ROOT / "kdos.f").read_bytes(),
        ftype=FTYPE_FORTH,
        flags=FLAG_SYSTEM,
    )

    for directory in directories:
        fs.mkdir(directory)

    for path in sorted(paths):
        source = SOURCE_ROOT / path
        if not source.is_file():
            raise FileNotFoundError(f"Missing Akashic resource: {path}")
        disk_path = PurePosixPath(path)
        file_type = FTYPE_FORTH if source.suffix == ".f" else FTYPE_TEXT
        parent = "/" + str(disk_path.parent)
        fs.inject_file(
            disk_path.name,
            source.read_bytes(),
            ftype=file_type,
            path=parent,
        )

    fs.inject_file("large.txt", LARGE_SAMPLE, ftype=FTYPE_TEXT)

    # Leave two isolated one-sector holes in the generated test image.
    # Guest-created smoke.txt uses the first; the large Save As copy uses
    # the second and must grow through MP64FS's secondary extent.
    fs.inject_file(".growth-hole-1", bytes(512), flags=FLAG_SYSTEM)

    fs.inject_file(
        "autoexec.f",
        profile.autoexec.encode("utf-8"),
        ftype=FTYPE_FORTH,
    )
    fs.inject_file(".growth-hole-2", bytes(512), flags=FLAG_SYSTEM)

    for name in ("welcome.txt", "example.f"):
        fs.inject_file(name, SAMPLE_FILES[name], ftype=FTYPE_TEXT)

    fs.delete_file(".growth-hole-1")
    fs.delete_file(".growth-hole-2")
    fs.save(target)

    info = fs.info()
    print(
        f"Built {profile_name} image: {target}\n"
        f"  {len(modules)} modules, {len(resources)} resources, "
        f"{len(directories)} directories\n"
        f"  {info['files']} MP64FS entries, {target.stat().st_size:,} bytes"
    )
    return target


def _has_forth_error(raw: str) -> list[str]:
    patterns = (
        re.compile(r"(?i)\b(abort|undefined word|stack underflow)\b"),
        re.compile(r"(?m)^\s*\?\s*$"),
    )
    return [line for line in raw.splitlines() if any(p.search(line) for p in patterns)]


def smoke(
    profile_name: str,
    image_path: Path,
    *,
    cols: int,
    rows: int,
    max_steps: int,
    timeout: float,
) -> bool:
    profile = PROFILES[profile_name]
    started = time.perf_counter()
    total_steps = 0

    with MachineSession.from_bios(
        MEGAPAD_ROOT / "bios.asm",
        storage_image=image_path,
        cols=cols,
        rows=rows,
        batch_steps=500_000,
    ) as session:
        session.boot()
        deadline = time.monotonic() + timeout
        screen = session.snapshot()
        journey_errors: list[str] = []

        while total_steps < max_steps and time.monotonic() < deadline:
            remaining = max_steps - total_steps
            report = session.run(
                max_steps=min(50_000_000, remaining),
                wall_timeout_s=min(2.0, max(0.05, deadline - time.monotonic())),
            )
            total_steps += report.steps
            screen = session.snapshot()
            screen_text = screen.text()
            if all(marker in screen_text for marker in profile.ready_markers):
                break
            if report.reason in ("halted", "idle", "stalled"):
                break

        initial_text = screen.text()
        initial_ready = all(
            marker in initial_text for marker in profile.ready_markers
        )

        def wait_screen(
            marker: str,
            failure: str,
            *,
            step_budget: int = 250_000_000,
            wall_timeout: float = 8.0,
        ) -> bool:
            nonlocal total_steps, screen
            remaining = min(step_budget, max_steps - total_steps)
            if remaining <= 0 or time.monotonic() >= deadline:
                journey_errors.append(f"{failure} (journey budget exhausted)")
                return False
            report = session.wait_for_text(
                marker,
                scope="screen",
                max_steps=remaining,
                wall_timeout_s=min(
                    wall_timeout, max(0.05, deadline - time.monotonic())
                ),
            )
            total_steps += report.steps
            screen = session.snapshot()
            if not report.matched:
                journey_errors.append(failure)
            return report.matched

        def wait_screen_gone(
            marker: str,
            failure: str,
            *,
            step_budget: int = 250_000_000,
            wall_timeout: float = 8.0,
        ) -> bool:
            nonlocal total_steps, screen
            remaining = min(step_budget, max_steps - total_steps)
            local_deadline = min(deadline, time.monotonic() + wall_timeout)
            while remaining > 0 and time.monotonic() < local_deadline:
                screen = session.snapshot()
                if marker not in screen.text():
                    return True
                chunk = min(10_000_000, remaining)
                report = session.run(
                    max_steps=chunk,
                    wall_timeout_s=min(
                        0.75, max(0.05, local_deadline - time.monotonic())
                    ),
                )
                total_steps += report.steps
                remaining -= report.steps
                if report.reason in ("halted", "idle", "stalled"):
                    break
            screen = session.snapshot()
            if marker not in screen.text():
                return True
            journey_errors.append(failure)
            return False

        if initial_ready and profile_name in ("desktop", "pad"):
            if profile_name == "desktop":
                session.send_key("alt+1")
            session.send_text("smoke")
            if wait_screen("smoke", "typing did not reach Pad's textarea"):
                content_hits = [
                    (row, col)
                    for row, col in screen.find("smoke")
                    if row >= 3
                ]
                if not content_hits:
                    journey_errors.append("Pad content was not present in the editor grid")
                else:
                    row, col = content_hits[0]
                    caret_col = col + len("smoke")
                    if not (screen.cells[row][caret_col].attrs & 32):
                        journey_errors.append("Pad did not paint its software caret")
                    if screen.lines()[row][max(0, col - 4):col] != "  1 ":
                        journey_errors.append("Pad's compact line-number gutter is malformed")
                session.send_key("ctrl+z")
                if wait_screen_gone("smoke", "Ctrl+Z did not undo Pad input"):
                    session.send_key("ctrl+y")
                    if wait_screen("smoke", "Ctrl+Y did not redo Pad input"):
                        session.send_key("tab")
                        if wait_screen(
                            "Ln 1, Col 9",
                            "Pad Tab did not advance to a four-column stop",
                        ):
                            session.send_key("ctrl+z")
                            wait_screen(
                                "Ln 1, Col 6",
                                "Pad Tab indentation did not undo as one edit",
                            )
                        session.send_key("ctrl+s")
                        if wait_screen(
                            "Save as:", "Ctrl+S did not open Pad's Save As prompt"
                        ):
                            session.send_text("smoke.txt")
                            session.send_key("enter")
                            if wait_screen("Saved", "Pad did not complete Save As"):
                                if "Save as:" in screen.text():
                                    journey_errors.append(
                                        "Pad's Save As prompt remained active after Enter"
                                    )
                                live_fs = MP64FS(
                                    bytearray(session.system.storage._image_data)
                                )
                                try:
                                    saved = live_fs.read_file("smoke.txt")
                                except FileNotFoundError:
                                    saved = None
                                if saved != b"smoke":
                                    journey_errors.append(
                                        "Pad Save As did not persist exact file bytes"
                                    )
                                try:
                                    welcome = live_fs.read_file("welcome.txt")
                                except FileNotFoundError:
                                    welcome = None
                                if welcome != SAMPLE_FILES["welcome.txt"]:
                                    journey_errors.append(
                                        "Pad Save As damaged an existing disk file"
                                    )
                                if live_fs.find_file("kdos.f") is None:
                                    journey_errors.append(
                                        "Pad Save As damaged the MP64FS directory"
                                    )

        if initial_ready:
            session.resize(cols + 8, rows + 2)
            resize_budget = min(250_000_000, max_steps - total_steps)
            if resize_budget > 0 and time.monotonic() < deadline:
                report = session.run(
                    max_steps=resize_budget,
                    wall_timeout_s=min(
                        8.0, max(0.05, deadline - time.monotonic())
                    ),
                )
                total_steps += report.steps
            screen = session.snapshot()
            resized_text = screen.text()
            if (screen.cols, screen.rows) != (cols + 8, rows + 2):
                journey_errors.append("host terminal did not resize")
            missing_after_resize = [
                marker
                for marker in profile.stable_markers
                if marker not in resized_text
            ]
            if missing_after_resize:
                journey_errors.append(
                    "layout lost after resize: " + ", ".join(missing_after_resize)
                )
            if profile_name in ("desktop", "pad") and "smoke" not in resized_text:
                journey_errors.append("Pad text was lost after resize")
            if (
                profile_name == "desktop"
                and resized_text.count("[1:Akashic Pa") != 1
            ):
                journey_errors.append("Desk left a stale taskbar after resize")

        if initial_ready and profile_name in ("desktop", "pad"):
            session.send_key("ctrl+o")
            if wait_screen("Open:", "Ctrl+O did not open Pad's path prompt"):
                session.send_text("/welcome.txt")
                session.send_key("enter")
                if wait_screen(
                    "Welcome to Akashic.", "Pad could not open /welcome.txt"
                ):
                    session.send_key("ctrl+f")
                    if wait_screen("Find:", "Ctrl+F did not open Find"):
                        session.send_text("editable")
                        session.send_key("enter")
                        wait_screen(
                            "Ln 2",
                            "Pad did not move to the matched search line",
                        )
                    session.send_key("ctrl+g")
                    if wait_screen(
                        "Go to line:", "Ctrl+G did not open Go to Line"
                    ):
                        session.send_text("2")
                        session.send_key("enter")
                        wait_screen_gone(
                            "Go to line:", "Pad did not close Go to Line"
                        )

        if initial_ready and profile_name == "pad":
            session.send_key("ctrl+o")
            if wait_screen("Open:", "Pad did not reopen its path prompt"):
                session.send_text("/large.txt")
                session.send_key("enter")
                if wait_screen(
                    "Large fixture line 048",
                    "Pad could not open the large MP64FS fixture",
                ):
                    session.send_key("ctrl+shift+s")
                    if wait_screen(
                        "Save as:", "Ctrl+Shift+S did not open Save As"
                    ):
                        for _ in range(len("/large.txt")):
                            session.send_key("backspace")
                        session.send_text("large-copy.txt")
                        session.send_key("enter")
                        if wait_screen_gone(
                            "Save as:", "large Save As did not finish"
                        ) and wait_screen(
                            "large-copy.txt",
                            "Pad did not adopt the large copy filename",
                        ):
                            live_fs = MP64FS(
                                bytearray(session.system.storage._image_data)
                            )
                            try:
                                copied = live_fs.read_file("large-copy.txt")
                            except FileNotFoundError:
                                copied = None
                            if copied != LARGE_SAMPLE:
                                journey_errors.append(
                                    "fragmented Save As did not persist exact bytes"
                                )
                            found = live_fs.find_file("large-copy.txt")
                            if found is None or found[1].ext1_count == 0:
                                journey_errors.append(
                                    "large Save As did not exercise a secondary extent"
                                )

                            session.send_key("ctrl+g")
                            if wait_screen(
                                "Go to line:",
                                "word-selection setup did not open Go to Line",
                            ):
                                session.send_text("1")
                                session.send_key("enter")
                                wait_screen_gone(
                                    "Go to line:",
                                    "word-selection setup did not finish",
                                )
                            session.send_key("ctrl+d")
                            session.send_text("Wide")
                            word_expected = LARGE_SAMPLE.replace(
                                b"Large", b"Wide", 1
                            )
                            if wait_screen(
                                "Wide fixture line 001",
                                "Ctrl+D did not select exactly the current word",
                            ):
                                session.send_key("ctrl+s")
                                if wait_screen_gone(
                                    "large-copy.txt*",
                                    "word replacement did not save",
                                ):
                                    live_fs = MP64FS(
                                        bytearray(
                                            session.system.storage._image_data
                                        )
                                    )
                                    if live_fs.read_file(
                                        "large-copy.txt"
                                    ) != word_expected:
                                        journey_errors.append(
                                            "word replacement saved incorrect bytes"
                                        )

                            session.send_key("ctrl+g")
                            if wait_screen(
                                "Go to line:",
                                "line-selection setup did not open Go to Line",
                            ):
                                session.send_text("2")
                                session.send_key("enter")
                                wait_screen_gone(
                                    "Go to line:",
                                    "line-selection setup did not finish",
                                )
                            session.send_key("ctrl+l")
                            session.send_text("Replacement line.")
                            if wait_screen(
                                "Replacement line.",
                                "Ctrl+L did not replace the current line",
                            ):
                                session.send_key("enter")
                                if wait_screen(
                                    "Ln 3, Col 1",
                                    "line replacement did not retain a line break",
                                ):
                                    session.send_key("ctrl+s")
                                    if wait_screen_gone(
                                        "large-copy.txt*",
                                        "line replacement did not save",
                                    ):
                                        lines = word_expected.splitlines(
                                            keepends=True
                                        )
                                        lines[1] = b"Replacement line.\n"
                                        line_expected = b"".join(lines)
                                        live_fs = MP64FS(
                                            bytearray(
                                                session.system.storage._image_data
                                            )
                                        )
                                        if live_fs.read_file(
                                            "large-copy.txt"
                                        ) != line_expected:
                                            journey_errors.append(
                                                "line replacement saved incorrect bytes"
                                            )

        if initial_ready and profile_name in ("desktop", "fexplorer"):
            if profile_name == "desktop":
                session.send_key("alt+2")
            session.send_key("ctrl+g")
            if wait_screen(
                "Go to:", "File Explorer's Go to Path prompt did not open"
            ):
                session.send_text("example.f")
                session.send_key("enter")
                wait_screen("SQUARE", "File Explorer could not preview /example.f")

            if profile_name == "fexplorer":
                session.send_key("ctrl+n")
                if wait_screen(
                    "New file:", "Ctrl+N did not open New File"
                ):
                    session.send_text("journey.txt")
                    session.send_key("enter")
                    if wait_screen_gone(
                        "New file:", "File Explorer did not create a file"
                    ):
                        wait_screen(
                            "journey.txt",
                            "created file did not appear in the detail list",
                        )

                session.send_key("f2")
                if wait_screen("Rename:", "F2 did not open Rename"):
                    for _ in range(len("journey.txt")):
                        session.send_key("backspace")
                    session.send_text("renamed.txt")
                    session.send_key("enter")
                    if wait_screen_gone(
                        "Rename:", "File Explorer did not finish Rename"
                    ):
                        wait_screen(
                            "renamed.txt",
                            "renamed file did not appear in the detail list",
                        )

                session.send_key("ctrl+c")
                wait_screen(
                    "Copied to clipboard",
                    "Ctrl+C did not capture the active file",
                )
                session.send_key("ctrl+shift+n")
                if wait_screen(
                    "New folder:", "Ctrl+Shift+N did not open New Folder"
                ):
                    session.send_text("dest")
                    session.send_key("enter")
                    if wait_screen_gone(
                        "New folder:", "File Explorer did not create a folder"
                    ):
                        wait_screen(
                            "dest", "created folder did not appear in the detail list"
                        )
                session.send_key("ctrl+v")
                wait_screen("Pasted!", "Ctrl+V did not copy into the new folder")

                live_fs = MP64FS(bytearray(session.system.storage._image_data))
                old_entry = live_fs.find_file("journey.txt")
                renamed_entry = live_fs.find_file("renamed.txt")
                dest_slot = None
                try:
                    dest_slot = live_fs.resolve_path("/dest")
                    nested = live_fs.read_file("renamed.txt", parent=dest_slot)
                except FileNotFoundError:
                    nested = None
                if old_entry is not None or renamed_entry is None:
                    root_names = [
                        entry.name
                        for entry in live_fs.list_files(parent=0xFF)
                    ]
                    journey_errors.append(
                        "Explorer rename was not persisted to MP64FS "
                        f"(root={root_names})"
                    )
                if nested != b"":
                    nested_names = []
                    if dest_slot is not None:
                        nested_names = [
                            entry.name
                            for entry in live_fs.list_files(parent=dest_slot)
                        ]
                    journey_errors.append(
                        "Explorer copy/paste did not persist the nested file "
                        f"(dest={nested_names})"
                    )

                session.send_key("ctrl+g")
                if wait_screen(
                    "Go to:", "delete setup did not open Go To"
                ):
                    session.send_text("dest/renamed.txt")
                    session.send_key("enter")
                    if wait_screen_gone(
                        "Go to:", "delete setup did not resolve the nested file"
                    ):
                        session.send_key("delete")
                        if wait_screen(
                            "Delete the selected item?",
                            "Delete did not open its confirmation dialog",
                        ):
                            session.send_key("enter")
                            wait_screen_gone(
                                "Delete the selected item?",
                                "nested file deletion did not finish",
                            )

                live_fs = MP64FS(bytearray(session.system.storage._image_data))
                try:
                    dest_slot = live_fs.resolve_path("/dest")
                    live_fs.read_file("renamed.txt", parent=dest_slot)
                except FileNotFoundError:
                    pass
                else:
                    journey_errors.append(
                        "Explorer delete did not remove the nested file"
                    )

                session.send_key("delete")
                if wait_screen(
                    "Delete the selected item?",
                    "empty-folder Delete did not open confirmation",
                ):
                    session.send_key("enter")
                    wait_screen_gone(
                        "Delete the selected item?",
                        "empty-folder deletion did not finish",
                    )
                live_fs = MP64FS(bytearray(session.system.storage._image_data))
                try:
                    live_fs.resolve_path("/dest")
                except FileNotFoundError:
                    pass
                else:
                    journey_errors.append(
                        "Explorer delete did not remove the empty destination folder"
                    )

                session.send_key("alt+1")
                wait_screen(
                    "renamed.txt",
                    "File Explorer did not return to the populated Details view",
                )
                wait_screen_gone(
                    "Pasted!",
                    "File Explorer toast did not expire",
                    step_budget=150_000_000,
                    wall_timeout=3.0,
                )
            screen = session.snapshot()
            if profile_name == "desktop":
                final_text = screen.text()
                if "1smoke2" in final_text or "smoke2" in final_text:
                    journey_errors.append(
                        "Desk global app shortcuts leaked digits into Pad"
                    )
                if "[2:File Explo*]" not in final_text:
                    journey_errors.append(
                        "Desk did not leave File Explorer focused after Alt+2"
                    )

        capture_root = OUTPUT_ROOT / f"smoke-{profile_name}"
        screen.write_text(capture_root.with_suffix(".txt"))
        screen.write_json(capture_root.with_suffix(".cells.json"))
        screen.write_png(
            capture_root.with_suffix(".png"),
            font_path=AKASHIC_ROOT / "assets/fonts/DejaVuSansMono.ttf",
        )

        raw = session.raw_text()
        capture_root.with_suffix(".raw.txt").write_text(
            raw, encoding="utf-8"
        )
        errors = _has_forth_error(raw)
        missing = [m for m in profile.stable_markers if m not in screen.text()]
        elapsed = time.perf_counter() - started
        ok = not errors and not missing and not journey_errors

        print(
            f"Smoke {profile_name}: {'PASS' if ok else 'FAIL'}\n"
            f"  {total_steps:,} steps in {elapsed:.2f}s; "
            f"screen={screen.cols}x{screen.rows}; raw={len(session.raw_output):,} bytes"
        )
        if missing:
            print(f"  missing screen markers: {', '.join(missing)}")
        if errors:
            print("  guest errors:")
            for line in errors[-12:]:
                print(f"    {line}")
        if journey_errors:
            print("  journey errors:")
            for error in journey_errors:
                print(f"    {error}")
        print(f"  captures: {capture_root}.[txt|raw.txt|cells.json|png]")
        if not ok:
            print("  recent guest output:")
            excerpt = raw[-3000:].replace("\r", "")
            for line in excerpt.splitlines()[-30:]:
                print(f"    {line[:500]}")
        return ok


def serve(
    profile_name: str,
    image_path: Path,
    *,
    socket_path: str,
    cols: int,
    rows: int,
):
    os.execv(
        sys.executable,
        [
            sys.executable,
            str(MEGAPAD_ROOT / "session_server.py"),
            "--bios",
            str(MEGAPAD_ROOT / "bios.asm"),
            "--storage",
            str(image_path),
            "--socket",
            socket_path,
            "--cols",
            str(cols),
            "--rows",
            str(rows),
            "--batch-steps",
            "500000",
        ],
    )


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    for name in ("build", "smoke", "serve"):
        command = commands.add_parser(name)
        command.add_argument(
            "--profile", choices=tuple(PROFILES), default="desktop"
        )
        command.add_argument("--output", type=Path)
        if name in ("smoke", "serve"):
            command.add_argument("--cols", type=int, default=100)
            command.add_argument("--rows", type=int, default=32)
        if name == "smoke":
            command.add_argument("--max-steps", type=int, default=3_000_000_000)
            command.add_argument("--timeout", type=float, default=75.0)
        if name == "serve":
            command.add_argument("--socket", default="/tmp/akashic-tui.sock")

    return parser


def main() -> int:
    args = _parser().parse_args()
    image_path = build_image(args.profile, args.output)
    if args.command == "build":
        return 0
    if args.command == "smoke":
        return 0 if smoke(
            args.profile,
            image_path,
            cols=args.cols,
            rows=args.rows,
            max_steps=args.max_steps,
            timeout=args.timeout,
        ) else 1
    serve(
        args.profile,
        image_path,
        socket_path=args.socket,
        cols=args.cols,
        rows=args.rows,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
