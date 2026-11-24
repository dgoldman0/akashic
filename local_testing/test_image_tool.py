"""The image tool's own behaviours (toolchain/image): files only the user can
read, a user volume kept across builds, the e2fsprogs check, and the session
manifest.  The tests import the tool, never the harness."""

from __future__ import annotations

import json
import os
import stat
import subprocess
import sys
from pathlib import Path

import pytest

AKASHIC_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(AKASHIC_ROOT))

from toolchain.image import build as image_build  # noqa: E402
from toolchain.image import ext4 as image_ext4  # noqa: E402
from toolchain.image.build import (  # noqa: E402
    APP_SHELL_MODULE,
    E2FSPROGS_MINIMUM,
    SESSION_MANIFEST_FORMAT,
    ImageSpec,
    build,
    session_manifest_path,
    settings_image_path,
    user_image_path,
)
from toolchain.image.desk import DESK_SYSTEM_SETTINGS  # noqa: E402
from toolchain.image.rich import DESKTOP_APT1_RICH_TERMINAL  # noqa: E402

# The smallest image: no modules, Desk's system settings on its settings disk.
SETTINGS_SPEC = ImageSpec(
    roots=(),
    resources=(),
    autoexec="\\ autoexec.f - image tool test\n",
    include_large_sample=False,
    settings_files=(DESK_SYSTEM_SETTINGS,),
)
# A user volume needs the app shell, which declares its places.
APP_SHELL_SPEC = ImageSpec(
    roots=(APP_SHELL_MODULE,),
    resources=(),
    autoexec="\\ autoexec.f - image tool test\nENTER-USERLAND\nREQUIRE tui/app-shell.f\n",
    include_large_sample=False,
)
PINNED = os.environ.get("AKASHIC_E2FSPROGS_TOOL_DIR")
needs_pinned_e2fsprogs = pytest.mark.skipif(
    not PINNED, reason="needs the pinned e2fsprogs in AKASHIC_E2FSPROGS_TOOL_DIR"
)


def _mode(path: Path) -> int:
    return stat.S_IMODE(path.stat().st_mode)


@pytest.mark.parametrize("umask", (0o000, 0o022))
def test_a_build_writes_what_only_the_user_can_read(tmp_path, umask):
    found = tmp_path / "data"
    found.mkdir()
    found.chmod(0o755)
    target = found / "configurations" / "desktop" / "image.img"
    previous = os.umask(umask)
    try:
        build(SETTINGS_SPEC, target, name="private", session_manifest=True)
    finally:
        os.umask(previous)
    # Each folder the build made is private; the one it found keeps its mode.
    assert _mode(target.parent) == _mode(target.parent.parent) == 0o700
    assert _mode(found) == 0o755
    for path in (target, settings_image_path(target), session_manifest_path(target)):
        assert _mode(path) == 0o600, path


def test_a_build_makes_an_existing_image_private(tmp_path):
    target = tmp_path / "image.img"
    for path in (target, settings_image_path(target)):
        path.write_bytes(b"readable")
        path.chmod(0o644)
    build(SETTINGS_SPEC, target, name="private")
    assert _mode(target) == _mode(settings_image_path(target)) == 0o600
    assert target.read_bytes() != b"readable"


@needs_pinned_e2fsprogs
def test_a_build_keeps_the_user_volume_unless_asked_for_a_fresh_one(tmp_path):
    target = tmp_path / "image.img"
    user = user_image_path(target)
    arguments = dict(name="kept", user_volume=True, user_volume_mib=16)
    build(APP_SHELL_SPEC, target, **arguments)
    assert _mode(user) == 0o600

    # A user's own bytes, where a rebuilt volume holds zeros.
    with user.open("r+b") as volume:
        volume.seek(-4, os.SEEK_END)
        volume.write(b"mine")
    build(APP_SHELL_SPEC, target, **arguments)
    assert user.read_bytes()[-4:] == b"mine"
    # A build without the user volume leaves it alone.
    build(APP_SHELL_SPEC, target, name="kept")
    assert user.read_bytes()[-4:] == b"mine"

    build(APP_SHELL_SPEC, target, fresh_user_volume=True, **arguments)
    assert user.read_bytes()[-4:] == bytes(4)
    # A fresh build without the user volume removes the one beside it.
    build(APP_SHELL_SPEC, target, name="kept", fresh_user_volume=True)
    assert not user.exists()


def test_the_session_manifest_says_what_a_server_runs(tmp_path):
    target = tmp_path / "desktop.img"
    spec = ImageSpec(
        roots=(),
        resources=(),
        autoexec="\\ autoexec.f - image tool test\n",
        include_large_sample=False,
        settings_files=(DESK_SYSTEM_SETTINGS,),
        default_ext_mem_mib=320,
        full_cores=2,
    )
    built_from = {
        "components": {"akashic": "c43b39cf", "megapad": "42e09564"},
        "configuration": {"name": "desktop", "sha256": "0" * 64},
    }
    build(spec, target, name="desktop", backend="emulator",
          session_manifest=True, built_from=built_from)
    manifest = json.loads(session_manifest_path(target).read_text())
    assert manifest["format"] == SESSION_MANIFEST_FORMAT
    assert manifest["name"] == "desktop"
    assert manifest["backend"] == "emulator"
    assert manifest["storage"] == {
        "boot": "desktop.img",
        "settings": "desktop-settings.img",
        "system": None,
        "user": None,
    }
    assert manifest["machine"] == {
        "ram_kib": image_build.DEFAULT_RAM_KIB,
        "ext_mem_mib": 320,
        "vram_mib": image_build.DEFAULT_VRAM_MIB,
        "full_cores": 2,
        "clusters": 0,
    }
    assert manifest["rich_terminal"] is None
    assert manifest["built_from"] == built_from

    with pytest.raises(ValueError, match="session manifest"):
        build(spec, target, name="desktop", built_from=built_from)


def test_the_session_manifest_carries_the_rich_terminal_policies(tmp_path):
    spec = ImageSpec(
        roots=(),
        resources=(),
        autoexec="",
        rich_terminal=DESKTOP_APT1_RICH_TERMINAL,
    )
    path = image_build._write_session_manifest(
        spec, tmp_path / "desktop.img", name="desktop", backend="simulator",
        settings=None, system=True, user=True, built_from=None,
    )
    manifest = json.loads(path.read_text())
    assert manifest["rich_terminal"] == {
        "policy": DESKTOP_APT1_RICH_TERMINAL.host_policy.to_dict(),
        "retained_policy": DESKTOP_APT1_RICH_TERMINAL.retained_policy.to_dict(),
    }
    assert manifest["storage"]["system"] == "desktop-system.img"
    assert manifest["storage"]["user"] == "desktop-user.img"
    assert manifest["built_from"] is None
    assert _mode(path) == 0o600


# The toolchain check runs each tool's -V; these tests answer for the tools,
# so no program runs.
def _fake_tools(folder: Path, names) -> Path:
    folder.mkdir(parents=True, exist_ok=True)
    for name in names:
        tool = folder / name
        tool.write_text("#!/bin/sh\nexit 1\n")
        tool.chmod(0o700)
    return folder


def _answer_versions(monkeypatch, tool: str, library: str) -> None:
    """Have every tool's -V print TOOL, a version and its date, and LIBRARY."""

    def run(argv, *, env, expected_status=0):
        name = Path(argv[0]).name
        return subprocess.CompletedProcess(
            argv, 0, "", f"{name} {tool}\n\tUsing EXT2FS Library version {library}\n"
        )

    monkeypatch.setattr(image_ext4, "_run", run)


def test_the_toolchain_check_takes_the_pin_or_the_minimum(tmp_path, monkeypatch):
    manifest = image_ext4.load_manifest(image_ext4.DEFAULT_MANIFEST)
    required = manifest["authorities"]["e2fsprogs"]["required_tools"]
    tools = _fake_tools(tmp_path / "sbin", required)
    env = {"PATH": str(tools)}

    pinned = manifest["authorities"]["e2fsprogs"]["version_banner"]
    _answer_versions(monkeypatch, pinned, "1.47.4")
    evidence = image_ext4.verify_toolchain(manifest, tools, env)
    assert set(evidence) == set(required)

    _answer_versions(monkeypatch, "1.47.0 (5-Feb-2023)", "1.47.0")
    with pytest.raises(image_ext4.ProfileError, match="is not pinned"):
        image_ext4.verify_toolchain(manifest, tools, env)
    assert set(image_ext4.verify_toolchain(
        manifest, tools, env, minimum=E2FSPROGS_MINIMUM)) == set(required)

    _answer_versions(monkeypatch, "1.46.5 (30-Dec-2021)", "1.46.5")
    with pytest.raises(image_ext4.ProfileError, match="1.47.0 or later"):
        image_ext4.verify_toolchain(manifest, tools, env, minimum=E2FSPROGS_MINIMUM)

    _answer_versions(monkeypatch, "1.47.2 (1-Jan-2025)", "1.46.5")
    with pytest.raises(image_ext4.ProfileError, match="its own libext2fs"):
        image_ext4.verify_toolchain(manifest, tools, env, minimum=E2FSPROGS_MINIMUM)


def test_the_host_toolchain_is_the_first_folder_with_every_tool(tmp_path, monkeypatch):
    manifest = image_ext4.load_manifest(image_ext4.DEFAULT_MANIFEST)
    required = manifest["authorities"]["e2fsprogs"]["required_tools"]
    # Another program's lone mke2fs comes first on the path.
    lone = _fake_tools(tmp_path / "platform-tools", ["mke2fs"])
    full = _fake_tools(tmp_path / "e2fsprogs", required)
    monkeypatch.setenv("PATH", os.pathsep.join((str(lone), str(full))))
    assert image_build._host_e2fsprogs(manifest) == full.resolve()

    monkeypatch.setenv("PATH", str(lone))
    monkeypatch.setattr(image_build, "HOST_TOOL_FOLDERS", ())
    with pytest.raises(image_ext4.ProfileError, match="needs e2fsprogs 1.47.0 or later"):
        image_build._host_e2fsprogs(manifest)


def test_a_build_takes_the_pin_when_it_is_named(tmp_path, monkeypatch):
    checked = []

    def verify(manifest, tool_dir, env, *, minimum=None):
        checked.append((tool_dir, minimum))
        return {}

    monkeypatch.setattr(image_ext4, "verify_toolchain", verify)
    monkeypatch.setenv("AKASHIC_E2FSPROGS_TOOL_DIR", str(tmp_path / "pinned"))
    image_build._system_volume_toolchain()
    monkeypatch.delenv("AKASHIC_E2FSPROGS_TOOL_DIR")
    monkeypatch.setattr(image_build, "_host_e2fsprogs", lambda manifest: tmp_path / "host")
    image_build._system_volume_toolchain()
    assert checked == [
        ((tmp_path / "pinned").resolve(), None),
        (tmp_path / "host", E2FSPROGS_MINIMUM),
    ]

