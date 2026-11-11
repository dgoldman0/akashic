"""The system volume: KDOS's modules from the ext4 volume on SYSTEM-UNIT.

utils/fs/system-volume.f mounts the ext4 volume on the machine's system
storage unit read-only and fills the module source that reads from it.
These tests run the sequence a boot runs: load the module and the ext4
driver, mount, select the source, and REQUIRE a tree of modules by path.
The boot disk is an MP64FS image on the first unit and the system volume
is the third unit, write-protected, as on a device.  The volume is the
module-source suite's: the pinned profile's primary image with the module
tree written into it by the pinned debugfs.  One test runs the same
sequence on the emulator, where the BIOS itself reaches the unit.  The last
boots a profile the image builder made with --system-volume, on the
emulator: its boot volume, its ext4 volume and its autoexec as built.
"""
from __future__ import annotations

import os
from pathlib import Path

import pytest

import test_vfs_module_source as module_source
from forth_dependencies import dependency_order
from test_textarea import MEGAPAD_ROOT
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime
from simulator.storage import HostedStorageService

ROOT = Path(__file__).resolve().parents[1]
ROOTS = ("utils/fs/system-volume.f",)
STEPS = 400_000_000
TRUE = 2**64 - 1

HELPERS = r"""
VARIABLE T-PRIOR
VARIABLE C-RUNS
VARIABLE SCRIPT-RUNS
VARIABLE BOOT-RUNS
: T-ARENA  ( bytes -- arena )  A-XMEM ARENA-NEW THROW ;
\ Mount as a boot does, from an arena of BYTES, noting the current VFS.
: T-MOUNT  ( bytes -- ior )  VFS-CUR T-PRIOR !  T-ARENA SYSVOL-MOUNT ;
: T-CURRENT-KEPT?  ( -- flag )  VFS-CUR T-PRIOR @ = ;
: T-UNIT-FREE?  ( -- flag )
    _SYSVOL-BD BD-VALID? 0=  _SYSVOL-VOLUME VOL-VALID? 0=  AND ;
"""


@pytest.fixture(scope="session")
def system_volume_path(tmp_path_factory: pytest.TempPathFactory) -> Path:
    return module_source._volume(
        tmp_path_factory.mktemp("system-volume"), module_source.EXT4_FILES
    )


@pytest.fixture(scope="session")
def system_volume(system_volume_path: Path) -> bytes:
    return system_volume_path.read_bytes()


class Machine:
    """KDOS with the system-volume module and all it requires loaded."""

    def __init__(self, volume: bytes | None) -> None:
        self.boot = HostedStorageService(module_source._boot_disk())
        self.volume = (
            None
            if volume is None
            else HostedStorageService(volume, write_protected=True)
        )
        self.runtime = MegaForthRuntime(
            memory=create_one_core_address_space(external_size=128 << 20),
            execution_backend="native",
            storage=self.boot,
            system_storage=self.volume,
        )
        self.runtime.evaluate(
            (MEGAPAD_ROOT / "kdos.f").read_bytes(), source_name="kdos.f"
        )
        self.runtime.evaluate(b"ENTER-USERLAND", source_name="userland")
        for module in dependency_order(ROOT / "akashic", ROOTS):
            text = (ROOT / "akashic" / module).read_text()
            text = "\n".join(
                line
                for line in text.splitlines()
                if not line.strip().startswith(("REQUIRE ", "PROVIDED "))
            )
            self.runtime.evaluate(
                text.encode(), source_name=module, step_budget=STEPS
            )
        self.runtime.evaluate(HELPERS.encode(), source_name="helpers")
        self.runtime.drain_uart_output()

    def run(self, source: str) -> tuple[int, ...]:
        """Evaluate SOURCE and return what it left on the data stack."""

        self.runtime.evaluate(
            source.encode(), source_name="check", step_budget=STEPS
        )
        stack = self.runtime.main_context.data.snapshot()
        self.runtime.main_context.data.clear()
        assert self.runtime.main_context.returns.snapshot() == ()
        return stack


def test_a_boot_mounts_the_volume_and_loads_modules_from_it(
    system_volume: bytes,
) -> None:
    machine = Machine(system_volume)
    assert machine.run("SYSVOL-VFS") == (0,)

    assert machine.run("524288 T-MOUNT") == (0,)
    assert machine.run("SYSVOL-VFS 0<> T-CURRENT-KEPT?") == (TRUE, TRUE)
    # Mounting selects nothing: modules still come from the boot volume.
    assert machine.run("MODULE-SOURCE @ FS-MODULE-SOURCE =") == (TRUE,)
    assert machine.run("REQUIRE boot.f BOOT-WORD BOOT-RUNS @") == (77, 1)

    assert machine.run("SYSVOL-SOURCE MODULE-SOURCE!") == ()
    assert machine.run("REQUIRE mods/a.f") == ()
    assert machine.run("A-WORD B-WORD C-WORD D-WORD C-RUNS @") == (
        101,
        102,
        103,
        104,
        1,
    )
    # boot.module and the tree's four, each with its file.
    assert machine.run("_MOD-COUNT _MOD-FILES") == (5, 5)

    # The boot volume and the system volume by turns: each keeps the files
    # it has loaded, so neither reads a module a second time.
    assert machine.run("FS-MODULE-SOURCE MODULE-SOURCE! REQUIRE boot.f") == ()
    assert machine.run("SYSVOL-SOURCE MODULE-SOURCE! REQUIRE mods/a.f") == ()
    assert machine.run("BOOT-RUNS @ C-RUNS @ _MOD-FILES") == (1, 1, 5)

    # The mount is the driver's read-only one, on a write-protected unit.
    # The binding is checked by name, since on such a unit the writing
    # binding refuses a write as well.
    assert machine.run("SYSVOL-VFS V.BINDING @ EXT4-BINDING =") == (TRUE,)
    assert machine.run('S" made" SYSVOL-VFS VFS-MKDIR VFS-E-READONLY =') == (
        TRUE,
    )
    assert machine.volume.image_bytes == system_volume


def test_the_volume_mounts_once(system_volume: bytes) -> None:
    machine = Machine(system_volume)
    assert machine.run("524288 T-MOUNT") == (0,)
    assert machine.run("SYSVOL-VFS") != (0,)
    (mounted,) = machine.run("SYSVOL-VFS")

    assert machine.run("524288 T-MOUNT VFS-E-BUSY =") == (TRUE,)
    assert machine.run("SYSVOL-VFS T-CURRENT-KEPT?") == (mounted, TRUE)
    assert machine.run("SYSVOL-SOURCE MODULE-SOURCE! REQUIRE mods/c.f") == ()
    assert machine.run("C-WORD") == (103,)


def test_the_source_throws_before_a_mount(system_volume: bytes) -> None:
    machine = Machine(system_volume)

    assert machine.run("' SYSVOL-SOURCE CATCH VFS-E-NOVOLUME =") == (TRUE,)
    assert machine.run("MODULE-SOURCE @ FS-MODULE-SOURCE =") == (TRUE,)


def test_a_failed_mount_gives_the_unit_back(system_volume: bytes) -> None:
    machine = Machine(system_volume)

    # An arena too small for the mount's own records.
    assert machine.run("4096 T-MOUNT VFS-E-NOMEM =") == (TRUE,)
    assert machine.run("SYSVOL-VFS T-CURRENT-KEPT? T-UNIT-FREE?") == (
        0,
        TRUE,
        TRUE,
    )
    assert machine.run("' SYSVOL-SOURCE CATCH VFS-E-NOVOLUME =") == (TRUE,)

    # The unit opens again, which a reference left behind would refuse.
    assert machine.run("524288 T-MOUNT") == (0,)
    assert machine.run("SYSVOL-SOURCE MODULE-SOURCE! REQUIRE mods/c.f") == ()
    assert machine.run("C-WORD") == (103,)


def test_a_machine_without_a_system_volume_reports_it() -> None:
    machine = Machine(None)

    assert machine.run("524288 T-MOUNT BD-E-NO-MEDIA =") == (TRUE,)
    assert machine.run("SYSVOL-VFS T-CURRENT-KEPT? T-UNIT-FREE?") == (
        0,
        TRUE,
        TRUE,
    )


def test_a_volume_that_is_not_ext4_is_refused() -> None:
    machine = Machine(module_source._boot_disk())

    assert machine.run("524288 T-MOUNT 0<>") == (TRUE,)
    assert machine.run("SYSVOL-VFS T-CURRENT-KEPT? T-UNIT-FREE?") == (
        0,
        TRUE,
        TRUE,
    )


# ---- token files on the volume -------------------------------------------------
#
# MegaPad's tests/token_module_cases.py holds the loader's cases on KDOS's
# own filesystem, for the BIOS and for the simulator.  These run the ones
# that depend on the module source through ext4: a token file is found by
# its path with a t added, and the source that ships beside one is found
# again in the file's own folder.  The token files are that suite's, whose
# records give ten times what the source they name gives, so the value a
# word has tells which form was loaded.


def _token_machine(tmp_path: Path, files: dict[str, bytes]) -> Machine:
    volume = module_source._volume(tmp_path, files).read_bytes()
    machine = Machine(volume)
    assert machine.run("524288 T-MOUNT") == (0,)
    assert machine.run("SYSVOL-SOURCE MODULE-SOURCE!  -1 MODULE-TOKENS !") == ()
    return machine


def _said(machine: Machine) -> str:
    return " ".join(machine.runtime.drain_uart_output().decode("latin-1").split())


def _stamp(machine: Machine) -> int:
    (value,) = machine.run("LOAD-STAMP @")
    return value


def test_a_volume_of_token_files_alone_loads_nested_modules(
    tmp_path: Path,
) -> None:
    from tests.token_module_cases import A, B, stamps, tokens
    from shared.token_form import pack_module_name_file

    at = stamps(B, A)
    machine = _token_machine(
        tmp_path,
        {
            "/mods/lib/b.ft": tokens("b", 0, requires="a", stamp=at[0]),
            "/mods/lib/a.ft": tokens("a", 11, stamp=at[1]),
            # A module that was loaded before the volume was mounted.
            "/mods/c.ft": pack_module_name_file(b"vms.early"),
        },
    )

    assert machine.run("PROVIDED vms.early  REQUIRE mods/c.f") == ()
    assert machine.run("REQUIRE mods/lib/b.f  B-WORD A-WORD") == (12, 11)
    assert machine.run("REQUIRE mods/lib/b.f  REQUIRE /mods/lib/a.f") == ()
    said = _said(machine)
    assert said.count("[load-a]") == said.count("[load-b]") == 1
    assert "not found" not in said and "cannot be loaded" not in said
    assert _stamp(machine) == at[2]
    assert machine.run("_LD-SP @ _LD-FROM-SP @") == (0, 0)


def test_a_stale_token_file_on_the_volume_ends_the_load_and_is_named(
    tmp_path: Path,
) -> None:
    from tests.token_module_cases import A, B, STALE, stamps, tokens

    at = stamps(B, A)
    machine = _token_machine(
        tmp_path,
        {
            "/mods/lib/b.ft": tokens("b", 0, requires="a", stamp=at[0]),
            # Recorded under another text of the file loaded before it.
            "/mods/lib/a.ft": tokens("a", 11, stamp=stamps(B + b"\n", A)[1]),
            "/mods/c.ft": tokens("c", 30, stamp=at[0])[:-3],
        },
    )

    assert machine.run("' REQUIRE CATCH mods/lib/b.f") == (7,)
    said = _said(machine)
    assert STALE in said and "Token file a.ft cannot be loaded" in said
    assert "b.ft" not in said
    assert machine.run("[DEFINED] B-WORD [DEFINED] A-WORD") == (0, 0)
    # A file whose sizes do not account for its bytes is refused as loudly.
    assert machine.run("' REQUIRE CATCH mods/c.f") == (6,)
    assert "Token file mods/c.ft cannot be loaded" in _said(machine)
    assert machine.run("[DEFINED] C-WORD _LD-SP @ _LD-FROM-SP @") == (0, 0, 0)


def test_a_source_beside_its_token_file_is_found_in_the_files_own_folder(
    tmp_path: Path,
) -> None:
    from tests.token_module_cases import A, B, module, stamps, tokens

    at = stamps(B, A)
    edited = module("a", 12)
    machine = _token_machine(
        tmp_path,
        {
            "/mods/lib/b.f": B,
            "/mods/lib/b.ft": tokens("b", 0, requires="a", stamp=at[0], beside=True),
            "/mods/lib/a.f": edited,
            "/mods/lib/a.ft": tokens("a", 110, says=11, stamp=at[1], beside=True),
            # Current, with its source beside it: the token file is used.
            "/mods/c.f": module("c", 30),
            "/mods/c.ft": tokens("c", 300, says=30, stamp=stamps()[0], beside=True),
        },
    )

    assert machine.run("REQUIRE mods/c.f  C-WORD") == (300,)
    assert "out of date" not in _said(machine)
    # c.ft was recorded first of all, so b.ft and a.ft are now out of date
    # by their stamps, and a.ft by its source as well.
    assert machine.run("REQUIRE mods/lib/b.f  B-WORD A-WORD") == (13, 12)
    said = _said(machine)
    assert "Token file mods/lib/b.ft is out of date: loading its source" in said
    assert "Token file a.ft is out of date: loading its source" in said
    assert "cannot be loaded" not in said
    assert _stamp(machine) == stamps(module("c", 30), B, edited)[3]
    assert machine.run("_LD-SP @ _LD-FROM-SP @") == (0, 0)


def test_the_boot_sequence_runs_on_the_emulator(
    system_volume_path: Path,
) -> None:
    """The BIOS's own storage path to the third unit under the mount.

    The ext4 suite's harness supplies a machine with the driver loaded from
    source and refuses any write or flush of its first unit.  The system
    volume goes on the third unit, write-protected, before the lines run.
    """

    import test_vfs_ext4 as ext4_harness

    volume = system_volume_path.read_bytes()
    attached = []

    def attach(system) -> None:
        unit = system.system_storage
        unit._replace_media(
            bytearray(volume), str(system_volume_path), file_holds_media=False
        )
        unit.write_protected = True
        attached.append(unit)

    module_lines = [
        line
        for module in ("utils/fs/vfs-module-source.f", "utils/fs/system-volume.f")
        for line in ext4_harness._compact_source_load_lines(
            ext4_harness.fat_harness._load_forth_lines(
                str(ROOT / "akashic" / module)
            )
        )
    ]
    output = ext4_harness.run_forth(
        system_volume_path,
        [
            *module_lines,
            "VARIABLE C-RUNS  VARIABLE SCRIPT-RUNS  VARIABLE T-PRIOR",
            "VFS-CUR T-PRIOR !",
            "524288 A-XMEM ARENA-NEW THROW SYSVOL-MOUNT",
            # One line each: the answer follows its whole input line.
            '." [B0 " . SYSVOL-VFS 0<> . VFS-CUR T-PRIOR @ = . ." ]"',
            "SYSVOL-SOURCE MODULE-SOURCE!",
            "REQUIRE mods/a.f",
            (
                '." [B1 " A-WORD . B-WORD . C-WORD . D-WORD . C-RUNS @ . '
                '_MOD-COUNT . _MOD-FILES . ." ]"'
            ),
            "REQUIRE mods/a.f  REQUIRE /mods/c.f  LOAD mods/script.f",
            (
                '." [B2 " C-RUNS @ . SCRIPT-RUNS @ . '
                '_LD-SP @ . _LD-FROM-SP @ . ." ]"'
            ),
        ],
        configure=attach,
    )

    def marker(name: str) -> str:
        # The machine echoes each input line; its answer starts a line.
        start = output.index(f"\n[{name} ") + len(name) + 3
        return " ".join(output[start : output.index("]", start)].split())

    assert marker("B0") == "0 -1 -1"
    assert marker("B1") == "101 102 103 104 1 4 4"
    assert marker("B2") == "1 1 0 0"
    assert bytes(attached[0]._image_data) == volume


def test_a_profile_built_with_its_modules_on_the_volume_boots_on_the_emulator(
    tmp_path: Path,
) -> None:
    """The image builder's --system-volume path end to end, through the BIOS.

    The profile is not linked, so KDOS loads the mounting module's closure,
    the ext4 driver in it, as plain files from the boot volume.  autoexec.f
    then mounts the volume the build wrote and runs the profile's own
    REQUIREs, which resolve on ext4, and the profile's contract checks must
    pass as they do when its modules sit on the boot volume.
    """

    if not os.environ.get("AKASHIC_E2FSPROGS_TOOL_DIR"):
        pytest.skip("set AKASHIC_E2FSPROGS_TOOL_DIR to build a system volume")
    import akashic_tui

    profile = "media-type-contracts"
    assert not akashic_tui.PROFILES[profile].linked
    image = akashic_tui.build_image(
        profile, tmp_path / "volume-boot.img", system_volume=True
    )
    assert akashic_tui.system_image_path(image).is_file()
    max_steps, timeout = akashic_tui._smoke_limits(profile, None, None)
    assert akashic_tui.smoke(
        profile, image, cols=100, rows=32, max_steps=max_steps, timeout=timeout
    )
