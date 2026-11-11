"""The image builder's --token-modules: what it writes, and that it loads.

A build with --token-modules boots the image once from source in MegaPad's
simulator, records what the interpreter does with each file, and writes
each file in its token form, built for the system the image boots (MegaPad's
docs/token-modules-proposal-2026-11-11.md).  A system volume then holds
token files and no source, and --keep-module-source writes the source
beside them.

The first tests hold the builder's own part to its rules.  The last two
build Desk with File Explorer both ways, read the volume back, boot it in
the simulator, and plant faults.  On a volume without source a changed KDOS
ends the boot, loudly and by name, and an edited boot script changes
nothing.  Where the source ships, an edited module loads from its source
and every other module still loads from its token file.  Each build boots
the image once to record it, so those two take about a minute each; they
need the pinned e2fsprogs that AKASHIC_E2FSPROGS_TOOL_DIR names.
"""
from __future__ import annotations

import os
import subprocess
import zlib
from pathlib import Path

import pytest

import akashic_tui
from akashic_tui import (
    COLD_SOURCE_CHUNK_TEMPLATE,
    COLD_SOURCE_CODEC_STORED,
    MP64FS_VFS_PLATFORM_MODULE,
    PROFILES,
    SOURCE_ROOT,
    _linked_autoexec,
    build_image,
    dependency_order,
)
from diskutil import FLAG_SYSTEM, FTYPE_FORTH, MP64FS
from forth_dependencies import PROVIDED_RE
from shared.boot_identity import boot_identity
from shared.token_form import is_token_file, unpack_token_file
from tests.token_module_cases import OTHER_SYSTEM, RECORDED_SOURCES, record

PROFILE = "desktop-apt1-fexp"


# ---- the builder's own part -------------------------------------------------


def test_a_token_form_states_the_system_its_image_boots() -> None:
    recorder, _ = record(RECORDED_SOURCES, "top.f")
    token_files = {unit.digest: unit.token_file() for unit in recorder.units}
    lib = RECORDED_SOURCES["lib.f"]

    form = unpack_token_file(akashic_tui._token_form(lib, token_files, 1234))
    assert (form.boot_id, form.source_beside) == (1234, False)
    assert (form.source_bytes, form.source_crc32) == (len(lib), zlib.crc32(lib))
    beside = akashic_tui._token_form(lib, token_files, 1234, source_beside=True)
    assert unpack_token_file(beside).source_beside
    # A text the recording did not load has no form, and a build that
    # recorded nothing has none for any text.
    assert akashic_tui._token_form(b": NEVER-LOADED ;\n", token_files, 1234) is None
    assert akashic_tui._token_form(lib, None, 1234) is None


def test_a_chunk_that_cannot_be_loaded_is_named_by_the_boot_script() -> None:
    chunk = COLD_SOURCE_CHUNK_TEMPLATE.format(index=0)
    packed = _linked_autoexec(
        "ENTER-USERLAND\nREQUIRE one.f\n",
        (chunk,),
        ("one.f",),
        cold_source_codec=COLD_SOURCE_CODEC_STORED,
    )

    assert "COLD SOURCE LOAD FAIL status=" in packed
    assert 'file=" CSL-LAST-NAME TYPE' in packed
    assert packed.index("CSL-LAST-NAME") < packed.index("ABORT")


def test_keeping_module_source_needs_a_system_volume_of_token_modules(
    tmp_path: Path,
) -> None:
    for options in (
        {},
        {"token_modules": True},
        {"system_volume": True},
    ):
        with pytest.raises(ValueError, match="needs a system volume of token modules"):
            build_image(
                PROFILE, tmp_path / "never.img", keep_module_source=True, **options
            )
    assert not (tmp_path / "never.img").exists()


# ---- what a build writes, and that it loads ----------------------------------


def _tools() -> Path:
    value = os.environ.get("AKASHIC_E2FSPROGS_TOOL_DIR")
    if not value:
        pytest.skip("set AKASHIC_E2FSPROGS_TOOL_DIR to build a system volume")
    return Path(value).resolve()


def _debugfs(tool_dir: Path, image: Path, commands: list[str], *, write: bool = False) -> None:
    environment = {"LC_ALL": "C", "TZ": "UTC", "PATH": f"{tool_dir}:/usr/bin:/bin"}
    script = image.with_suffix(".debugfs")
    script.write_text("\n".join(commands) + "\n")
    ran = subprocess.run(
        [str(tool_dir / "debugfs"), *(["-w"] if write else []), "-f", str(script), str(image)],
        env=environment, text=True, capture_output=True, check=False,
    )
    assert ran.returncode == 0, ran.stderr
    checked = subprocess.run(
        [str(tool_dir / "e2fsck"), "-f", "-n", str(image)],
        env=environment, text=True, capture_output=True, check=False,
    )
    assert checked.returncode == 0, checked.stdout + checked.stderr


def _volume_files(tool_dir: Path, system: Path, scratch: Path) -> dict[str, bytes]:
    """Every file the volume holds, by its path."""

    tree = scratch / "tree"
    tree.mkdir(parents=True)
    _debugfs(tool_dir, system, [f"rdump / {tree}"])
    return {
        str(path.relative_to(tree)): path.read_bytes()
        for path in sorted(tree.rglob("*"))
        if path.is_file() and "lost+found" not in path.parts
    }


def _boot(image: Path):
    return akashic_tui._boot_in_simulator(image, PROFILES[PROFILE])


def _said(runtime) -> str:
    return " ".join(bytes(runtime.uart_output).decode("latin-1").split())


def _changed_boot_volume(image: Path, target: Path, name: str, change) -> Path:
    """A copy of IMAGE at TARGET, beside the same settings and system
    disks, with NAME on its boot volume written again with CHANGE applied."""

    target.write_bytes(image.read_bytes())
    for unit in ("settings", "system"):
        companion = image.with_name(f"{image.stem}-{unit}{image.suffix}")
        if companion.is_file():
            os.link(companion, target.with_name(f"{target.stem}-{unit}{target.suffix}"))
    fs = MP64FS(bytearray(target.read_bytes()))
    first = [entry.name for entry in fs.list_files() if entry.ftype == FTYPE_FORTH][0]
    data = fs.read_file(name)
    flags = FLAG_SYSTEM if name == "kdos.f" else 0
    fs.delete_file(name)
    fs.inject_file(name, change(data), ftype=FTYPE_FORTH, flags=flags)
    # The BIOS boots the first Forth file of the directory: still KDOS.
    assert [e.name for e in fs.list_files() if e.ftype == FTYPE_FORTH][0] == first
    fs.save(target)
    return target


def test_a_token_system_volume_holds_token_files_alone_and_boots(
    tmp_path: Path,
) -> None:
    tool_dir = _tools()
    modules = dependency_order((MP64FS_VFS_PLATFORM_MODULE, *PROFILES[PROFILE].roots))
    before_mount = set(dependency_order((akashic_tui.SYSTEM_VOLUME_MODULE,)))
    image = build_image(
        PROFILE, tmp_path / "desktop.img", backend="simulator",
        system_volume=True, token_modules=True,
    )
    system = akashic_tui.system_image_path(image)
    boot = MP64FS(bytearray(image.read_bytes()))
    identity = boot_identity(boot.read_file("kdos.f"))

    # The volume: one file for each module, at its path with a t added, and
    # no source.  A module the boot loads before the mount is only named.
    # Every other file is the module's token form, built for the system
    # that this image's BIOS and KDOS make.
    held = _volume_files(tool_dir, system, tmp_path / "dump")
    assert sorted(held) == sorted(module + "t" for module in modules)
    named_only = set()
    for module in modules:
        form = unpack_token_file(held[module + "t"])
        text = (SOURCE_ROOT / module).read_bytes()
        assert form.module_name.decode() == PROVIDED_RE.search(text.decode()).group(1), module
        assert not form.source_beside
        if form.records:
            assert form.boot_id == identity, module
            assert (form.source_bytes, form.source_crc32) == (len(text), zlib.crc32(text))
        else:
            named_only.add(module)
    assert named_only == set(modules) & before_mount and named_only

    # The boot volume: the script stays source and turns token loading on,
    # and the system modules and chunks state the same system.
    script = boot.read_file("autoexec.f")
    assert akashic_tui.MODULE_TOKENS_BOOT_LINE.encode() in script
    assert not is_token_file(script)
    assert unpack_token_file(boot.read_file("networking.f")).boot_id == identity

    said = _said(_boot(image))
    assert "cannot be loaded" not in said and "out of date" not in said
    assert "not found" not in said.lower()

    # An edit to the boot script changes nothing: every token file is still
    # used.
    edited = _changed_boot_volume(
        image, tmp_path / "edited-script.img", "autoexec.f",
        lambda data: data + b"\\ a line added after the build\n",
    )
    said = _said(_boot(edited))
    assert "cannot be loaded" not in said and "out of date" not in said

    # One changed byte of KDOS, and the volume was built for another
    # system: the boot ends at the first token file.  The refusal unwinds
    # through the boot script's own load, whose rollback then faults,
    # because the script entered userland after its load began; any load
    # that fails inside the script ends that way.
    other = _changed_boot_volume(
        image, tmp_path / "other-kdos.img", "kdos.f",
        lambda data: data.replace(b"KDOS v1.1", b"KDOS v1.2", 1),
    )
    with pytest.raises(RuntimeError) as failed:
        _boot(other)
    assert OTHER_SYSTEM in " ".join(str(failed.value).split())
    assert "Token file networking.f cannot be loaded" in str(failed.value)


def test_keeping_module_source_writes_it_beside_the_token_files(
    tmp_path: Path,
) -> None:
    tool_dir = _tools()
    modules = dependency_order((MP64FS_VFS_PLATFORM_MODULE, *PROFILES[PROFILE].roots))
    image = build_image(
        PROFILE, tmp_path / "desktop.img", backend="simulator",
        system_volume=True, token_modules=True, keep_module_source=True,
    )
    system = akashic_tui.system_image_path(image)

    held = _volume_files(tool_dir, system, tmp_path / "dump")
    for module in modules:
        assert held[module] == (SOURCE_ROOT / module).read_bytes(), module
    forms = {path: unpack_token_file(data) for path, data in held.items() if path.endswith("t")}
    assert set(held) == set(modules) | set(forms)
    assert 0 < len(forms) < len(modules)
    assert all(form.source_beside and form.records and form.boot_id for form in forms.values())

    said = _said(_boot(image))
    assert "cannot be loaded" not in said and "out of date" not in said

    # An edited module loads from its source.  No other module is affected:
    # each still loads from its token file.
    edited = "tui/applets/fexplorer/fexplorer.f"
    assert edited + "t" in forms
    host = tmp_path / "edited.f"
    host.write_bytes(held[edited] + b"\\ a line added on the machine\n")
    _debugfs(
        tool_dir, system,
        [f"rm /{edited}", f"write {host} /{edited}", f"sif /{edited} mode 0100644"],
        write=True,
    )
    said = _said(_boot(image))
    assert said.count("is out of date: loading its source") == 1
    assert "fexplorer.ft is out of date: loading its source" in said
    assert "cannot be loaded" not in said
