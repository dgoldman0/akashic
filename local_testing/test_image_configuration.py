"""Configurations for the image tool (toolchain/image/configuration.py): the
reader's checks, the Desktop it composes, and a build into volumes and a
session manifest.  The tests import the tool, never the harness."""

from __future__ import annotations

import json
import os
import stat
import sys
import tomllib
from pathlib import Path

import pytest

AKASHIC_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(AKASHIC_ROOT))

from toolchain.image import configuration as config  # noqa: E402
from toolchain.image.__main__ import main  # noqa: E402
from toolchain.image.build import (  # noqa: E402
    session_manifest_path,
    settings_image_path,
    user_image_path,
    with_settings_values,
)
from toolchain.image.desk import (  # noqa: E402
    DESK_APPLETS,
    DESK_SYSTEM_SETTINGS,
    desktop_autoexec,
    desktop_resources,
    desktop_roots,
)
from toolchain.image.megapad import SOURCE_ROOT  # noqa: E402

CANONICAL = """\
[configuration]
format = 1
title = "Desktop"
description = "Desk with Pad, File Explorer, Daybook, Grid and the Agent."

[practice]
offer = ["streams"]

[[practice.entry]]
applet = "pad"

[[practice.entry]]
applet = "file-explorer"

[[practice.entry]]
applet = "daybook"

[[practice.entry]]
applet = "grid"

[[practice.entry]]
applet = "agent"

[agent]
provider = "scripted"

[machine]
memory-mib = 384
cores = 1

[volumes.user]
size-mib = 64
documents = "akashic:assets/samples/desktop"

[volumes.system]
keep-source = false

[viewer]
cols = 160
rows = 48
font-size = 16

[network]
enabled = false

[desk.rich-terminal]
safe-mode = false
full-refresh-quiet-ms = 1000
full-refresh-interval-ms = 5000
"""
MINIMAL = """\
[configuration]
format = 1
title = "Pad"

[[practice.entry]]
applet = "pad"
"""
SYSTEM_TOML = (SOURCE_ROOT / DESK_SYSTEM_SETTINGS).read_text(encoding="utf-8")
PINNED = os.environ.get("AKASHIC_E2FSPROGS_TOOL_DIR")


def _read(tmp_path: Path, text: str) -> config.Configuration:
    path = tmp_path / "configuration.toml"
    path.write_text(text, encoding="utf-8")
    return config.read(path)


def _refused(tmp_path: Path, text: str, message: str) -> None:
    with pytest.raises(config.ConfigurationError, match=message):
        _read(tmp_path, text)


def test_the_desktop_reads_as_written(tmp_path):
    desktop = _read(tmp_path, CANONICAL)
    assert desktop.title == "Desktop"
    assert desktop.entries == ("pad", "file-explorer", "daybook", "grid", "agent")
    assert desktop.offers == ("streams",)
    assert desktop.provider == "scripted"
    assert (desktop.memory_mib, desktop.cores, desktop.user_mib) == (384, 1, 64)
    assert desktop.documents == AKASHIC_ROOT / "assets" / "samples" / "desktop"
    assert not desktop.keep_source and not desktop.network and not desktop.local_access
    assert dict(desktop.viewer) == {"cols": 160, "rows": 48, "font-size": 16}
    assert desktop.desk == {
        "rich-terminal": {
            "safe-mode": False,
            "full-refresh-quiet-ms": 1000,
            "full-refresh-interval-ms": 5000,
        }
    }


def test_left_out_values_take_their_defaults(tmp_path):
    pad = _read(tmp_path, MINIMAL)
    assert pad.entries == ("pad",) and pad.offers == ()
    assert pad.provider is None and pad.documents is None
    assert (pad.memory_mib, pad.cores) == (config.DEFAULT_MEMORY_MIB, config.DEFAULT_CORES)
    assert dict(pad.viewer) == config.DEFAULT_VIEWER
    assert pad.desk == {}


@pytest.mark.parametrize(
    ("extra", "message"),
    (
        ("[machine]\nmemroy-mib = 384\n", "unknown key machine.memroy-mib"),
        ("[practice]\ntitle = \"Desktop\"\n", "unknown key practice.title"),
        ("[sound]\nvolume = 3\n", "unknown table sound"),
        ("[volumes.user]\nsize = 64\n", "unknown key volumes.user.size"),
        ("[desk.rich-terminal]\nturbo = true\n", "unknown key desk.rich-terminal.turbo"),
        ("[desk.audio]\nlevel = 3\n", "unknown table desk.audio"),
        ("[desk.network]\nlocal-access = true\n", r"set through \[network\]"),
    ),
)
def test_unknown_tables_and_keys_are_refused_by_name(tmp_path, extra, message):
    _refused(tmp_path, MINIMAL + extra, message)
    entry = MINIMAL.replace('applet = "pad"', 'applet = "pad"\ntile = true')
    _refused(tmp_path, entry, r"unknown key practice\.entry\[0\]\.tile")


@pytest.mark.parametrize(
    ("extra", "message"),
    (
        ("[machine]\ncores = \"2\"\n", "machine.cores must be a whole number"),
        ("[machine]\nmemory-mib = true\n", "machine.memory-mib must be a whole number"),
        ("[network]\nenabled = 1\n", "network.enabled must be a boolean"),
        ("[desk.rich-terminal]\nsafe-mode = 1\n", "desk.rich-terminal.safe-mode must be a boolean"),
        ("[machine]\ncores = 5\n", "machine.cores must be 1 to 4"),
        ("[volumes.user]\nsize-mib = 0\n", "volumes.user.size-mib must be above zero"),
    ),
)
def test_values_of_the_wrong_kind_are_refused(tmp_path, extra, message):
    _refused(tmp_path, MINIMAL + extra, message)


def test_the_file_names_its_format_and_title(tmp_path):
    _refused(tmp_path, MINIMAL.replace("format = 1", "format = 2"), "takes format 1")
    _refused(tmp_path, MINIMAL.replace('title = "Pad"\n', ""), "missing key configuration.title")


def test_the_practice_names_known_applets_once(tmp_path):
    _refused(tmp_path, MINIMAL.replace('"pad"', '"paint"'), "names no applet Desk can open")
    _refused(tmp_path, MINIMAL + '\n[[practice.entry]]\napplet = "pad"\n', "names twice: pad")
    _refused(tmp_path, MINIMAL + '\n[practice]\noffer = ["pad"]\n', "names twice: pad")
    _refused(
        tmp_path,
        "[configuration]\nformat = 1\ntitle = \"Empty\"\n",
        "practice opens no applet",
    )


def test_the_agent_needs_a_provider_there_is(tmp_path):
    with_agent = MINIMAL + '\n[[practice.entry]]\napplet = "agent"\n'
    _refused(tmp_path, with_agent, r"the Agent needs \[agent\] provider")
    _refused(tmp_path, with_agent + '[agent]\nprovider = "openai"\n', "is not one of scripted")
    assert _read(tmp_path, with_agent + '[agent]\nprovider = "scripted"\n').provider == "scripted"
    _refused(tmp_path, MINIMAL + '[agent]\nprovider = "scripted"\n', "practice does not name")


def test_local_access_needs_the_network(tmp_path):
    _refused(tmp_path, MINIMAL + "[network]\nlocal-access = true\n", "needs network.enabled")
    opened = _read(tmp_path, MINIMAL + "[network]\nenabled = true\nlocal-access = true\n")
    assert opened.network and opened.local_access


def test_documents_resolve_in_a_component_or_beside_the_file(tmp_path):
    beside = tmp_path / "mine"
    beside.mkdir()
    (beside / "note.txt").write_bytes(b"mine\n")
    local = _read(tmp_path, MINIMAL + '[volumes.user]\ndocuments = "mine"\n')
    assert local.documents == beside
    assert config.documents(local) == {"note.txt": b"mine\n"}
    _refused(tmp_path, MINIMAL + '[volumes.user]\ndocuments = "absent"\n', "is not a folder")
    _refused(tmp_path, MINIMAL + '[volumes.user]\ndocuments = "lm2:samples"\n', "names no component")
    (beside / "folder").mkdir()
    with pytest.raises(config.ConfigurationError, match="holds a folder"):
        config.documents(local)


def test_settings_are_rewritten_in_place(tmp_path):
    desktop = _read(tmp_path, CANONICAL)
    values = config.settings_values(desktop)[DESK_SYSTEM_SETTINGS]
    # The Desktop's values are the file's own, so its text is the file's.
    assert with_settings_values(SYSTEM_TOML, values) == SYSTEM_TOML

    opened = _read(
        tmp_path,
        CANONICAL.replace("enabled = false", "enabled = true\nlocal-access = true")
        .replace("safe-mode = false", "safe-mode = true"),
    )
    text = with_settings_values(SYSTEM_TOML, config.settings_values(opened)[DESK_SYSTEM_SETTINGS])
    changed = [
        (before, after)
        for before, after in zip(SYSTEM_TOML.splitlines(), text.splitlines())
        if before != after
    ]
    assert changed == [
        ("safe-mode = false", "safe-mode = true"),
        ("local-access = false", "local-access = true"),
    ]
    assert tomllib.loads(text)["desk"]["network"]["local-access"] is True
    with pytest.raises(ValueError, match="holds no desk.network.ports"):
        with_settings_values(SYSTEM_TOML, {"desk.network": {"ports": 3}})


def test_the_desktop_composes_desk_in_the_order_given(tmp_path):
    spec = config.image_spec(_read(tmp_path, CANONICAL))
    assert spec.roots == desktop_roots(DESK_APPLETS, rich=True)
    assert spec.resources == desktop_resources(DESK_APPLETS)
    assert spec.autoexec == desktop_autoexec(DESK_APPLETS, rich=True)
    assert spec.settings_files == (DESK_SYSTEM_SETTINGS,)
    assert (spec.default_ext_mem_mib, spec.full_cores) == (384, 1)
    assert spec.session_entry == config.DESKTOP_SESSION_ENTRY


def test_the_command_line_checks_a_file(tmp_path, capsys):
    path = tmp_path / "configuration.toml"
    path.write_text(MINIMAL, encoding="utf-8")
    assert main(["check", str(path)]) == 0
    assert json.loads(capsys.readouterr().out)["entries"] == ["pad"]
    path.write_text(MINIMAL + "[sound]\n", encoding="utf-8")
    assert main(["check", str(path)]) == 1
    assert "unknown table sound" in capsys.readouterr().err


@pytest.mark.skipif(not PINNED, reason="needs the pinned e2fsprogs in AKASHIC_E2FSPROGS_TOOL_DIR")
def test_a_configuration_builds_its_volumes_and_manifest(tmp_path):
    documents = tmp_path / "documents"
    documents.mkdir()
    (documents / "note.txt").write_bytes(b"a note\n")
    path = tmp_path / "configuration.toml"
    path.write_text(
        MINIMAL
        + '[volumes.user]\nsize-mib = 16\ndocuments = "documents"\n'
        + "[network]\nenabled = true\nlocal-access = true\n"
        + "[viewer]\ncols = 120\n",
        encoding="utf-8",
    )
    built_from = tmp_path / "built-from.json"
    built_from.write_text(json.dumps({"components": {"akashic": "0" * 40}}))
    image = tmp_path / "machine" / "machine.img"
    assert main(["build", str(path), str(image), "--built-from", str(built_from)]) == 0

    for volume in (image, settings_image_path(image), user_image_path(image),
                   image.with_name("machine-system.img"), session_manifest_path(image)):
        assert stat.S_IMODE(volume.stat().st_mode) == 0o600, volume
    manifest = json.loads(session_manifest_path(image).read_text())
    assert manifest["title"] == "Pad"
    assert manifest["backend"] == "simulator"
    assert manifest["viewer"] == {"cols": 120, "rows": 48, "font_size": 16}
    assert manifest["network"] == {"enabled": True, "local_access": True}
    assert manifest["storage"]["user"] == "machine-user.img"
    assert manifest["built_from"]["components"] == {"akashic": "0" * 40}
    assert manifest["built_from"]["configuration"]["sha256"] == config.read(path).sha256
    assert user_image_path(image).stat().st_size == 16 << 20

    from diskutil import MP64FS

    settings = MP64FS(bytearray(settings_image_path(image).read_bytes()))
    text = settings.read_file("system.toml").decode()
    assert tomllib.loads(text)["desk"]["network"]["local-access"] is True
