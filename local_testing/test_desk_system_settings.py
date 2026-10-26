"""Desk's system settings, read from the settings disk.

The settings disk is MegaPad's second storage unit, whose medium is
write-protected.  tui/platform/settings-disk.f mounts it for one read, and
tui/desk-system-settings.f turns safe mode on, with the system settings as
its reason, when system.toml asks for it.  These tests run KDOS and both
modules in the native simulator against real MP64FS settings images.
"""
from __future__ import annotations

from pathlib import Path

import pytest

from forth_dependencies import dependency_order
from test_textarea import MEGAPAD_ROOT
from diskutil import FTYPE_TEXT, MP64FS
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime
from simulator.storage import HostedStorageService

ROOT = Path(__file__).resolve().parents[1]
SYSTEM_TOML = (ROOT / "akashic/tui/applets/desk/system.toml").read_text(encoding="utf-8")
CHK_WHY_CONFIG = 1


def _settings_image(files: dict[str, bytes], sectors: int = 64) -> bytes:
    fs = MP64FS(total_sectors=sectors)
    fs.format()
    for name, data in files.items():
        fs.inject_file(name, data, ftype=FTYPE_TEXT)
    return bytes(fs.img)


def _runtime(settings: bytes | None) -> MegaForthRuntime:
    runtime = MegaForthRuntime(
        memory=create_one_core_address_space(external_size=128 << 20),
        execution_backend="native",
        settings_storage=(
            None if settings is None
            else HostedStorageService(settings, write_protected=True)
        ),
    )
    runtime.evaluate((MEGAPAD_ROOT / "kdos.f").read_bytes(), source_name="kdos.f")
    runtime.evaluate(b"ENTER-USERLAND", source_name="settings-init")
    for module in dependency_order(ROOT / "akashic", ("tui/desk-system-settings.f",)):
        text = (ROOT / "akashic" / module).read_text()
        text = "\n".join(line for line in text.splitlines()
                         if not line.strip().startswith(("REQUIRE ", "PROVIDED ")))
        runtime.evaluate(text.encode(), source_name=module, step_budget=40_000_000)
    runtime.drain_uart_output()
    return runtime


def _results(runtime: MegaForthRuntime, source: str) -> tuple[int, ...]:
    runtime.evaluate(source.encode(), source_name="settings-check", step_budget=40_000_000)
    stack = runtime.main_context.data.snapshot()
    runtime.main_context.data.clear()
    return stack


def _safe_mode(runtime: MegaForthRuntime) -> int:
    return _results(runtime, "DSET-APPLY CHK-SAFE-MODE @")[0]


def test_the_settings_ask_for_safe_mode_and_give_it_their_reason() -> None:
    asked = SYSTEM_TOML.replace("safe-mode = false\n", "safe-mode = true\n")
    assert asked != SYSTEM_TOML
    runtime = _runtime(_settings_image({"system.toml": asked.encode()}))
    assert _safe_mode(runtime) == CHK_WHY_CONFIG
    # Every check runs in safe mode.
    assert _results(runtime, "CHK-EVERY-FRAME?")[0] != 0


@pytest.mark.parametrize(
    "files",
    (
        {"system.toml": SYSTEM_TOML.encode()},
        {"other.toml": SYSTEM_TOML.replace("= false", "= true").encode()},
        {"system.toml": b"[desk.rich-terminal]\nsafe-mode = \"yes\"\n"},
        {"system.toml": b"[desk.rich-terminal\nsafe-mode = true\n"},
        {"system.toml": b""},
    ),
    ids=("off", "no-file", "not-a-boolean", "malformed", "empty"),
)
def test_settings_that_do_not_ask_leave_normal_mode(files) -> None:
    """The template, a disk without system.toml, a setting that is not a
    boolean, broken text and an empty file all ask for nothing: they are
    outside data, so none is an anomaly."""
    runtime = _runtime(_settings_image(files))
    assert _safe_mode(runtime) == 0
    assert _results(runtime, "CHK-DAMAGE-COUNT @")[0] == 0


def test_without_a_settings_disk_desk_reads_nothing() -> None:
    runtime = _runtime(None)
    assert _results(runtime, "S\" system.toml\" SETDISK-READ NIP NIP")[0] != 0
    assert _safe_mode(runtime) == 0


def test_a_read_returns_the_file_whole_and_gives_back_what_it_took() -> None:
    """SETDISK-READ returns the file's bytes in a buffer the caller frees,
    and leaves the settings disk's volume and block device closed; the
    medium is never written.  The mount's extended memory comes back, and
    a read adds nothing to the dictionary."""
    image = _settings_image({"system.toml": SYSTEM_TOML.encode()})
    runtime = _runtime(image)
    here = _results(runtime, "HERE")
    buffer, length, ior = _results(runtime, "S\" system.toml\" SETDISK-READ")
    assert ior == 0
    assert runtime.memory.read_bytes(buffer, length) == SYSTEM_TOML.encode()
    assert _results(runtime, f"{buffer} FREE") == ()
    assert _results(runtime, "SETTINGS-VOLUME VOL-VALID? SETTINGS-BD BD-VALID?") == (0, 0)
    assert runtime.settings_storage.image_bytes == image
    # A second read mounts afresh in the extended memory the first gave
    # back: a mount arena kept would take fresh space past XMEM-HERE.
    extended = _results(runtime, "XMEM-HERE @")
    buffer, _length, ior = _results(runtime, "S\" system.toml\" SETDISK-READ")
    assert ior == 0
    assert _results(runtime, f"{buffer} FREE") == ()
    assert _results(runtime, "XMEM-HERE @") == extended
    assert _results(runtime, "HERE") == here
