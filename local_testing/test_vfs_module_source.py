"""KDOS modules loaded through the VFS, from an ext4 volume.

KDOS's LOAD and REQUIRE find and read a file through a module source
(MegaPad docs/module-source-contract.md).  utils/fs/vfs-module-source.f
makes a mounted VFS such a source.  These tests run KDOS, the ext4 driver
and that module in the native simulator.  The boot disk is an MP64FS image
on the first storage unit, and the ext4 volume is the second unit, whose
medium is write-protected.  The ext4 image is the pinned profile's primary
image with module files written into it by the pinned debugfs.  The last
test loads the same tree on the emulator, where the BIOS itself runs.
"""
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import pytest

import generate_ext4_profile_fixtures as ext4_fixture_generator
from forth_dependencies import dependency_order
from test_textarea import MEGAPAD_ROOT
from diskutil import FTYPE_FORTH, MP64FS
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime
from simulator.storage import HostedStorageService

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "local_testing" / "fixtures" / "ext4-profile" / "manifest.json"
IMAGE_DIR = ROOT / "local_testing" / "out" / "ext4-profile"
BASE_IMAGE = "primary-1k-i256"
ROOTS = (
    "utils/fs/drivers/vfs-ext4.f",
    "utils/fs/drivers/vfs-mp64fs.f",
    "utils/fs/vfs-module-source.f",
)
STEPS = 400_000_000

# The module tree on the ext4 volume.  Every REQUIRE below is relative to
# the file that holds it, except the one d.f writes from the root.
EXT4_FILES = {
    "/mods/a.f": (
        "PROVIDED vms.a\n"
        "REQUIRE lib/b.f\n"
        "REQUIRE c.f\n"
        ": A-WORD 101 ;\n"
    ),
    "/mods/lib/b.f": (
        "PROVIDED vms.b\n"
        "REQUIRE ../c.f\n"
        "REQUIRE deep/d.f\n"
        ": B-WORD 102 ;\n"
    ),
    "/mods/lib/deep/d.f": (
        "PROVIDED vms.d\n"
        "REQUIRE /mods/c.f\n"
        ": D-WORD 104 ;\n"
    ),
    "/mods/c.f": "PROVIDED vms.c\n1 C-RUNS +!\n: C-WORD 103 ;\n",
    "/mods/bad.f": (
        "PROVIDED vms.bad\n"
        "REQUIRE lib/b.f\n"
        ": BAD-WORD 1 ;\n"
        "-77 THROW\n"
    ),
    "/mods/script.f": "1 SCRIPT-RUNS +!\n",
    "/mods/empty.f": "",
    # Another file of c.f's name, which no module requires.
    "/mods/lib/c.f": ": OTHER-C 999 ;\n",
}
EXT4_DIRECTORIES = ("/mods", "/mods/lib", "/mods/lib/deep")
# The same tree after c.f was rewritten at another length.
CHANGED_FILES = {
    **EXT4_FILES,
    "/mods/c.f": "PROVIDED vms.c\n2 C-RUNS +!\n: C-WORD 1103 ;\n",
}

HELPERS = r"""
CREATE T-BD /BLOCK-DEVICE ALLOT
CREATE T-VOL /VOLUME ALLOT
CREATE T-SOURCE /MODULE-SOURCE ALLOT
VARIABLE T-VFS
VARIABLE T-OLD-VFS
VARIABLE C-RUNS
VARIABLE SCRIPT-RUNS
VARIABLE BOOT-RUNS
: T-MOUNT  ( -- ior )
    VFS-CUR T-OLD-VFS !
    T-BD SETTINGS-UNIT BD-OPEN-UNIT ?DUP IF EXIT THEN
    T-BD T-VOL VOL-RAW ?DUP IF EXIT THEN
    524288 A-XMEM ARENA-NEW ?DUP IF NIP EXIT THEN
    T-VOL EXT4-NEW ?DUP IF NIP EXIT THEN
    T-VFS !
    T-OLD-VFS @ VFS-USE
    T-VFS @ T-SOURCE VMS-INIT
    0 ;
: T-AT-ROOT?  ( -- flag )  T-VFS @ V.CWD @ T-VFS @ V.ROOT @ = ;
\ The source's operations, called as the loader calls them.
CREATE T-FILE /MODULE-FILE ALLOT
: T-RESOLVE  ( c-addr u source -- ior )
    T-FILE /MODULE-FILE 0 FILL
    T-FILE SWAP DUP MS.RESOLVE @ EXECUTE ;
: T-READ  ( addr source -- ior )
    T-FILE SWAP DUP MS.READ @ EXECUTE ;
: T-IDENTITY  ( -- low high )  T-FILE MF.ID @ T-FILE MF.ID 8 + @ ;
: T-PINNED?  ( c-addr u -- flag )
    T-VFS @ VFS-RESOLVE? THROW IN.FLAGS @ VFS-IF-PINNED AND 0<> ;
"""


def _volume(directory: Path, files: dict[str, str | bytes]) -> Path:
    """The primary ext4 image with FILES written into it."""

    tool_dir_value = os.environ.get("AKASHIC_E2FSPROGS_TOOL_DIR")
    if not tool_dir_value:
        pytest.skip("set AKASHIC_E2FSPROGS_TOOL_DIR to build the module volume")
    with MANIFEST.open("r", encoding="utf-8") as source:
        profile = json.load(source)
    row = next(row for row in profile["images"] if row["id"] == BASE_IMAGE)
    base = IMAGE_DIR / row["filename"]
    if not base.is_file():
        pytest.skip(
            "the canonical ext4 image is absent; run "
            f"generate_ext4_profile_fixtures.py with the pinned tools: {base}"
        )
    tool_dir = Path(tool_dir_value).resolve()
    env = ext4_fixture_generator.pinned_environment(profile, tool_dir, MANIFEST)
    try:
        tools = ext4_fixture_generator.verify_toolchain(profile, tool_dir, env)
    except ext4_fixture_generator.ProfileError as error:
        pytest.fail(str(error))

    image = directory / "modules.img"
    subprocess.run(["cp", "--sparse=always", str(base), str(image)], check=True)
    commands = [f"mkdir {path}" for path in EXT4_DIRECTORIES]
    for index, (path, text) in enumerate(files.items()):
        host = directory / f"file-{index}"
        host.write_bytes(text if isinstance(text, bytes) else text.encode())
        commands.append(f"write {host} {path}")
    script = directory / "modules.debugfs"
    script.write_text("\n".join(commands) + "\n")
    made = subprocess.run(
        [tools["debugfs"]["path"], "-w", "-f", str(script), str(image)],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert made.returncode == 0, made.stdout + made.stderr
    checked = subprocess.run(
        [tools["e2fsck"]["path"], "-f", "-n", str(image)],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert checked.returncode == 0, checked.stdout + checked.stderr
    return image


@pytest.fixture(scope="session")
def module_volume_path(tmp_path_factory: pytest.TempPathFactory) -> Path:
    return _volume(tmp_path_factory.mktemp("vfs-module-source"), EXT4_FILES)


@pytest.fixture(scope="session")
def module_volume(module_volume_path: Path) -> bytes:
    return module_volume_path.read_bytes()


@pytest.fixture(scope="session")
def changed_volume(tmp_path_factory: pytest.TempPathFactory) -> bytes:
    return _volume(
        tmp_path_factory.mktemp("vfs-module-changed"), CHANGED_FILES
    ).read_bytes()


def _boot_disk() -> bytes:
    fs = MP64FS(total_sectors=2048)
    fs.format()
    fs.inject_file(
        "boot.f",
        b"PROVIDED boot.module\n1 BOOT-RUNS +!\n: BOOT-WORD 77 ;\n",
        ftype=FTYPE_FORTH,
    )
    return bytes(fs.img)


class Machine:
    """KDOS with the ext4 driver and the module source, both disks attached."""

    def __init__(self, volume: bytes) -> None:
        self.boot = HostedStorageService(_boot_disk())
        self.volume = HostedStorageService(volume, write_protected=True)
        self.runtime = MegaForthRuntime(
            memory=create_one_core_address_space(external_size=128 << 20),
            execution_backend="native",
            storage=self.boot,
            settings_storage=self.volume,
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

    def output(self) -> str:
        return self.runtime.drain_uart_output().decode("utf-8", "replace")

    def mount(self) -> None:
        assert self.run("T-MOUNT") == (0,)
        assert self.run("T-SOURCE MODULE-SOURCE!") == ()

    def settled(self) -> None:
        """No load is under way and the volume's directory is its root."""

        assert self.run("T-AT-ROOT? _LD-SP @ _LD-FROM-SP @ CWD @") == (
            2**64 - 1,
            0,
            0,
            255,
        )


def test_require_loads_nested_modules_from_ext4(module_volume: bytes) -> None:
    machine = Machine(module_volume)
    machine.mount()

    assert machine.run("REQUIRE mods/a.f") == ()

    assert machine.run("A-WORD B-WORD C-WORD D-WORD C-RUNS @") == (
        101,
        102,
        103,
        104,
        1,
    )
    assert machine.run("_MOD-COUNT _MOD-FILES") == (4, 4)
    machine.settled()
    assert machine.output() == ""
    assert machine.run("MODULES") == ()
    listed = machine.output().split("\r\n")
    assert sorted(listed[1:-2]) == ["  vms.a", "  vms.b", "  vms.c", "  vms.d"]
    assert listed[-2] == "4  module(s)"

    # Every file is loaded, so each REQUIRE ends when its path has
    # resolved, and each path resolves from the cache: no request reaches
    # the volume.
    requests = machine.volume.completion
    assert machine.run(
        "REQUIRE mods/a.f REQUIRE mods/lib/b.f REQUIRE /mods/c.f "
        "REQUIRE mods/lib/deep/d.f C-RUNS @"
    ) == (1,)
    assert machine.volume.completion == requests
    machine.settled()


def test_load_runs_a_file_every_time_and_misses_are_reported(
    module_volume: bytes,
) -> None:
    machine = Machine(module_volume)
    machine.mount()

    assert machine.run("LOAD mods/script.f LOAD /mods/script.f SCRIPT-RUNS @") == (
        2,
    )
    assert machine.output() == ""
    machine.settled()

    assert machine.run("REQUIRE mods/none.f 7") == (7,)
    assert machine.output() == " Module not found: mods/none.f\r\n"
    # A directory is not a module, and a file is not a directory.
    assert machine.run("REQUIRE mods/lib") == ()
    assert machine.output() == " Module not found: mods/lib\r\n"
    assert machine.run("LOAD mods/c.f/x.f") == ()
    assert machine.output() == " Not found: mods/c.f/x.f\r\n"
    assert machine.run("LOAD mods/empty.f") == ()
    assert machine.output() == " Empty file\r\n"
    assert machine.run("_MOD-COUNT _MOD-FILES") == (0, 0)
    machine.settled()


def test_a_failed_module_leaves_nothing_and_the_tree_loads_afterwards(
    module_volume: bytes,
) -> None:
    machine = Machine(module_volume)
    machine.mount()

    assert machine.run("' REQUIRE CATCH mods/bad.f") == (2**64 - 77,)

    assert machine.run("_MOD-COUNT _MOD-FILES") == (0, 0)
    assert machine.runtime.find("BAD-WORD") is None
    assert machine.runtime.find("B-WORD") is None
    assert machine.run("MODULE-SOURCE @ T-SOURCE =") == (2**64 - 1,)
    machine.settled()
    for path in EXT4_DIRECTORIES:
        assert machine.run(f'S" {path}" T-PINNED?') == (0,)

    assert machine.run("REQUIRE mods/a.f A-WORD C-RUNS @") == (101, 2)
    assert machine.run("_MOD-COUNT _MOD-FILES") == (4, 4)
    machine.settled()


def test_directories_a_load_returns_to_survive_eviction(
    module_volume: bytes,
) -> None:
    machine = Machine(module_volume)
    machine.mount()
    # Let the cache keep two entries, so every path resolved evicts what
    # the loads before it left behind.
    assert machine.run("2 T-VFS @ VFS-SET-HWM") == ()

    assert machine.run("REQUIRE mods/a.f") == ()

    assert machine.run("A-WORD B-WORD C-WORD D-WORD C-RUNS @") == (
        101,
        102,
        103,
        104,
        1,
    )
    machine.settled()
    # The loads' own pins are gone, and the root keeps the mount's.
    for path in EXT4_DIRECTORIES:
        assert machine.run(f'S" {path}" T-PINNED?') == (0,)
    assert machine.run('S" /" T-PINNED?') == (2**64 - 1,)

    # Entries were evicted: resolving the loaded files again has to look
    # them up on the volume, and still no file is read or run again.
    requests = machine.volume.completion
    assert machine.run(
        "REQUIRE mods/a.f REQUIRE mods/lib/deep/d.f C-RUNS @"
    ) == (1,)
    assert machine.volume.completion > requests
    assert machine.run("_MOD-COUNT _MOD-FILES") == (4, 4)
    machine.settled()


def test_kdos_s_own_filesystem_serves_again_when_it_is_selected(
    module_volume: bytes,
) -> None:
    machine = Machine(module_volume)
    machine.mount()
    assert machine.run("REQUIRE mods/c.f C-RUNS @") == (1,)

    assert machine.run("FS-MODULE-SOURCE MODULE-SOURCE!") == ()
    assert machine.run("REQUIRE boot.f BOOT-WORD BOOT-RUNS @") == (77, 1)
    assert machine.output() == ""
    assert machine.run("REQUIRE mods/c.f") == ()
    assert machine.output() == (
        " Path component not found: mods\r\n"
        " Module not found: mods/c.f\r\n"
    )

    assert machine.run("T-SOURCE MODULE-SOURCE!") == ()
    assert machine.run("REQUIRE boot.f") == ()
    assert machine.output() == " Module not found: boot.f\r\n"
    assert machine.run("REQUIRE mods/c.f C-RUNS @ BOOT-RUNS @") == (1, 1)
    assert machine.run("_MOD-COUNT _MOD-FILES") == (2, 2)
    machine.settled()


def test_a_binding_without_stable_identities_gets_none(
    module_volume: bytes,
) -> None:
    machine = Machine(module_volume)
    # The boot disk again, this time through the VFS's MP64FS binding,
    # which numbers its files as the cache admits them.
    assert machine.run(
        "CREATE B-BD /BLOCK-DEVICE ALLOT  CREATE B-VOL /VOLUME ALLOT "
        "CREATE B-SOURCE /MODULE-SOURCE ALLOT  VARIABLE B-VFS "
        "VFS-CUR T-OLD-VFS ! "
        "B-BD BD-OPEN  B-BD B-VOL VOL-RAW "
        "131072 A-XMEM ARENA-NEW SWAP B-VOL VMP-NEW SWAP B-VFS ! "
        "T-OLD-VFS @ VFS-USE "
        "B-VFS @ B-SOURCE VMS-INIT  B-SOURCE MODULE-SOURCE!"
    ) == (0, 0, 0, 0)

    requests = machine.boot.completion
    assert machine.run("REQUIRE boot.f BOOT-WORD BOOT-RUNS @") == (77, 1)
    first = machine.boot.completion
    assert first > requests
    assert machine.run("_MOD-COUNT _MOD-FILES") == (1, 0)

    # No identity: the file is read again, and its PROVIDED line keeps it
    # from running twice.
    assert machine.run("REQUIRE boot.f BOOT-RUNS @") == (1,)
    assert machine.boot.completion > first
    assert machine.run("_MOD-COUNT _MOD-FILES") == (1, 0)
    assert machine.output() == ""


def test_an_unmounted_volume_is_no_filesystem(module_volume: bytes) -> None:
    machine = Machine(module_volume)
    machine.mount()
    assert machine.run("0 T-VFS @ VFS-UNMOUNT") == (0,)

    assert machine.run("REQUIRE mods/a.f LOAD mods/script.f 9") == (9,)

    assert machine.output() == " No filesystem\r\n No filesystem\r\n"
    assert machine.run("_LD-SP @ _LD-FROM-SP @ SCRIPT-RUNS @") == (0, 0, 0)


def test_identities_tell_files_attachments_and_versions_apart(
    module_volume: bytes,
    changed_volume: bytes,
) -> None:
    def identity(machine: Machine, path: str, source: str = "T-SOURCE"):
        assert machine.run(f'S" /" {source} MS.CONTEXT @ VFS-CD?') == (0,)
        result = machine.run(
            f'S" {path}" {source} T-RESOLVE T-IDENTITY '
            "T-FILE MF.USED @ T-FILE MF.RESERVE @"
        )
        assert result[0] == 0
        return result[1:]

    machine = Machine(module_volume)
    machine.mount()
    a_low, a_high, _a_used, _a_reserve = identity(machine, "mods/a.f")
    c_low, c_high, c_used, c_reserve = identity(machine, "mods/c.f")
    assert c_used == c_reserve == len(EXT4_FILES["/mods/c.f"])
    assert a_low != 0 and c_low != 0 and a_low != c_low
    assert identity(machine, "/mods/lib/../c.f") == (
        c_low,
        c_high,
        c_used,
        c_reserve,
    )

    # The same volume attached a second time is another attachment: the
    # file keeps its number and generation, and the identity differs.
    assert machine.run(
        "CREATE U-BD /BLOCK-DEVICE ALLOT  CREATE U-VOL /VOLUME ALLOT "
        "CREATE U-SOURCE /MODULE-SOURCE ALLOT  VARIABLE U-VFS "
        "VFS-CUR T-OLD-VFS ! "
        "U-BD SETTINGS-UNIT BD-OPEN-UNIT  U-BD U-VOL VOL-RAW "
        "524288 A-XMEM ARENA-NEW SWAP U-VOL EXT4-NEW SWAP U-VFS ! "
        "T-OLD-VFS @ VFS-USE  U-VFS @ U-SOURCE VMS-INIT"
    ) == (0, 0, 0, 0)
    again_low, again_high, _used, _reserve = identity(
        machine, "mods/c.f", "U-SOURCE"
    )
    assert again_low == c_low
    assert again_high != c_high

    # The same file rewritten at another length, on a machine that
    # attaches its volume in the same order: only the file changed.
    changed = Machine(changed_volume)
    changed.mount()
    new_low, new_high, new_used, _reserve = identity(changed, "mods/c.f")
    assert new_used == len(CHANGED_FILES["/mods/c.f"]) != c_used
    assert new_low == c_low
    assert new_high != c_high
    assert identity(changed, "mods/a.f")[0] == a_low


def test_read_gives_only_the_file_that_was_resolved(module_volume: bytes) -> None:
    machine = Machine(module_volume)
    machine.mount()
    text = EXT4_FILES["/mods/c.f"].encode()
    assert machine.run('S" mods/c.f" T-SOURCE T-RESOLVE') == (0,)
    buffer, status = machine.run(f"{len(text)} ALLOCATE")
    assert status == 0

    # The loader calls READ next, with the file's directory still current.
    assert machine.run(f"{buffer} T-SOURCE T-READ") == (0,)
    assert machine.runtime.memory.read_bytes(buffer, len(text)) == text

    # Had another call moved the directory to one that holds another file
    # of that name, READ refuses instead of returning that file's text.
    machine.runtime.memory.fill(buffer, len(text), 0xEE)
    assert machine.run('S" /mods/lib" T-VFS @ VFS-CD?') == (0,)
    (refused,) = machine.run(f"{buffer} T-SOURCE T-READ")
    assert machine.run(f"{refused} VFS-IOR-REASON VFS-R-STALE =") == (2**64 - 1,)
    assert machine.runtime.memory.read_bytes(buffer, len(text)) == (
        b"\xEE" * len(text)
    )
    assert machine.run("T-VFS @ V.OPEN-COUNT @") == (0,)


def test_the_same_tree_loads_on_the_emulator(module_volume_path: Path) -> None:
    """The BIOS's own parser, evaluator and storage path under the loader.

    The ext4 suite's harness supplies a machine with the driver loaded from
    source and the volume as its disk, and refuses any write or flush.
    """

    import test_vfs_ext4 as ext4_harness

    module_lines = ext4_harness._compact_source_load_lines(
        ext4_harness.fat_harness._load_forth_lines(
            str(ROOT / "akashic" / "utils/fs/vfs-module-source.f")
        )
    )
    output = ext4_harness.run_forth(
        module_volume_path,
        [
            *module_lines,
            "CREATE T-SOURCE /MODULE-SOURCE ALLOT  VARIABLE T-VFS",
            "VARIABLE C-RUNS  VARIABLE SCRIPT-RUNS",
            "T-ARENA T-VOLUME EXT4-NEW SWAP T-VFS !",
            '." [J0 " . ." ]"',
            "T-VFS @ T-SOURCE VMS-INIT  T-SOURCE MODULE-SOURCE!",
            "REQUIRE mods/a.f",
            # One line each: the answer follows its whole input line.
            (
                '." [J1 " A-WORD . B-WORD . C-WORD . D-WORD . C-RUNS @ . '
                '_MOD-COUNT . _MOD-FILES . ." ]"'
            ),
            "REQUIRE mods/a.f  REQUIRE /mods/c.f  LOAD mods/script.f",
            (
                '." [J2 " C-RUNS @ . SCRIPT-RUNS @ . '
                "T-VFS @ V.CWD @ T-VFS @ V.ROOT @ = . "
                '_LD-SP @ . _LD-FROM-SP @ . ." ]"'
            ),
        ],
    )

    def marker(name: str) -> str:
        # The machine echoes each input line; its answer starts a line.
        start = output.index(f"\n[{name} ") + len(name) + 3
        return " ".join(output[start : output.index("]", start)].split())

    assert marker("J0") == "0"
    assert marker("J1") == "101 102 103 104 1 4 4"
    assert marker("J2") == "1 1 -1 0 0"
