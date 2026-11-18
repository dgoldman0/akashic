"""The user volume: documents and records on the ext4 volume on USER-UNIT.

utils/fs/user-volume.f mounts the ext4 volume on the machine's fourth
storage unit, unit 3, through the staged-write binding and reports it to the
places registry as the volume `user`.  The first tests load the module and
what it requires into KDOS on MegaPad's native simulator, with a boot disk
on unit 0 and, on unit 3, a fresh volume the image builder makes
(akashic_tui._build_user_image), a damaged copy of it, a volume of another
format, or nothing.  The tests that follow boot Desk with Pad as the image
builder makes it with --user-volume: with its user volume, without it, and
with a system volume whose image is missing, the three outcomes of the boot
policy; and a document saved in the documents place, which the host's
e2fsck passes and a second boot reads back.
"""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest

import akashic_tui as tui
from forth_dependencies import dependency_order
from test_textarea import MEGAPAD_ROOT
from test_vfs_module_source import _boot_disk
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime
from simulator.storage import HostedStorageService

ROOT = Path(__file__).resolve().parents[1]
ROOTS = ("utils/fs/user-volume.f", "utils/fs/place-replace.f")
STEPS = 2_000_000_000
TRUE = 2**64 - 1
NOVOLUME = 21           # VFS-R-NOVOLUME
ARENA = tui.USER_VOLUME_ARENA_BYTES
PAD = "desktop-apt1-pad"

# A name of 199 bytes, far past MP64FS's 23, and a folder of 120 bytes in
# which a second document's path passes 255 bytes.  The guest builds both
# in T-PATH, since a string literal that long is not one KDOS reads.
LONG_NAME = "a-document-whose-name-runs-long-" + "n" * 160 + "-end.md"
LONG_FOLDER = "f" * 120
NAME_PATH = (
    'T-P0 S" /a-document-whose-name-runs-long-" T-P+ 160 110 T-PN '
    'S" -end.md" T-P+ T-P$'
)
FOLDER_PATH = 'T-P0 S" /" T-P+ 120 102 T-PN T-P$'
LONG_PATH = (
    'T-P0 S" /" T-P+ 120 102 T-PN S" /a-document-whose-name-runs-long-" T-P+ '
    '160 110 T-PN S" -end.md" T-P+ T-P$'
)
DOCUMENT = "# Kept on ext4. Written by the save Pad makes. " * 3

HELPERS = r"""
CREATE T-REPL VREPL-SIZE ALLOT  T-REPL VREPL-SIZE 0 FILL
CREATE T-BUF 4096 ALLOT
CREATE T-PATH 1024 ALLOT  VARIABLE T-PATH-U
: T-P0  ( -- )  0 T-PATH-U ! ;
: T-P+  ( a u -- )  >R T-PATH T-PATH-U @ + R@ CMOVE R> T-PATH-U +! ;
: T-PN  ( n char -- )  >R T-PATH T-PATH-U @ + OVER R> FILL T-PATH-U +! ;
: T-P$  ( -- a u )  T-PATH T-PATH-U @ ;
""" + f": T-DOC  S\" {DOCUMENT}\" ;" + r"""
VARIABLE T-SET  VARIABLE T-DOCS  VARIABLE T-FD
\ A set with one writable place over the user volume's documents folder.
: T-PLACES  ( -- )
    S" user" PLACES-VOLUME THROW
    >R S" documents" S" /documents" PLACE-WRITABLE R> PLACES-DECLARE THROW
    PLSET-NEW THROW DUP T-SET !  PLACE-WRITABLE -ROT PLSET-GRANT THROW T-DOCS ! ;
\ Save A U at PATH in the documents place the way Pad saves a document:
\ bind it for writing, replace it, and give the binding back.
: T-SAVE  ( a u path-a path-u -- status )
    T-DOCS @ -1 T-REPL PLACE-VREPL! ?DUP IF NIP NIP EXIT THEN
    T-REPL VREPL-REPLACE  T-REPL VREPL-FINI DROP ;
\ The CRC-32 and length of the file at PATH in the documents place.
: T-READ  ( path-a path-u -- crc len ior )
    VFS-FF-READ T-DOCS @ PLACE-OPEN ?DUP IF NIP 0 0 ROT EXIT THEN T-FD !
    T-BUF T-FD @ VFS-SIZE DUP >R T-FD @ VFS-READ-EXACT
    T-FD @ VFS-CLOSE
    T-BUF R@ CRC32 R> ROT ;
: T-WHY=  ( a u -- flag )  T-DOCS @ PLACE-WHY COMPARE 0= ;
"""


def _toolchain():
    if not os.environ.get("AKASHIC_E2FSPROGS_TOOL_DIR"):
        pytest.skip("set AKASHIC_E2FSPROGS_TOOL_DIR to build user volumes")
    return tui._system_volume_toolchain()


def _tool(name: str) -> str:
    return tui._system_volume_toolchain()[2][name]["path"]


def _e2fsck(image: Path) -> subprocess.CompletedProcess[str]:
    manifest, env, tools = tui._system_volume_toolchain()
    return subprocess.run(
        [tools["e2fsck"]["path"], "-f", "-n", str(image)],
        env=env, text=True, capture_output=True, check=False,
    )


def _debugfs_cat(image: Path, path: str) -> bytes:
    manifest, env, tools = tui._system_volume_toolchain()
    result = subprocess.run(
        [tools["debugfs"]["path"], "-R", f"cat {path}", str(image)],
        env=env, capture_output=True, check=False,
    )
    assert result.returncode == 0, result.stderr
    return result.stdout


@pytest.fixture(scope="module")
def fresh_user_volume(tmp_path_factory: pytest.TempPathFactory) -> bytes:
    target = tmp_path_factory.mktemp("user-volume") / "user.img"
    tui._build_user_image(target, 64 << 20, _toolchain(), documents={})
    return target.read_bytes()


class Machine:
    """KDOS with user-volume.f and the replacement's place binding loaded,
    a boot disk on unit 0 and USER, when given, on unit 3."""

    def __init__(self, user: bytes | None) -> None:
        self.user = None if user is None else HostedStorageService(user)
        self.runtime = MegaForthRuntime(
            memory=create_one_core_address_space(external_size=128 << 20),
            execution_backend="native",
            storage=HostedStorageService(_boot_disk()),
            user_storage=self.user,
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


def _reason(ior: int) -> int:
    """VFS-IOR-REASON of an ior the guest left as an unsigned cell."""
    return ior & 0xFF


def test_a_fresh_user_volume_attaches_and_takes_long_names(
    fresh_user_volume: bytes, tmp_path: Path
) -> None:
    machine = Machine(fresh_user_volume)
    assert machine.run("USERVOL-VFS") == (0,)
    assert machine.run(f"{ARENA} USERVOL-MOUNT") == (0,)
    assert machine.run(
        'USERVOL-VFS 0<>  S" user" PLACES-VOLUME DROP PVOL-VFS USERVOL-VFS ='
    ) == (TRUE, TRUE)
    # The writer is ext4's staged one, and the volume takes ext4's names.
    assert machine.run(
        "USERVOL-VFS V.BINDING @ EXT4-STAGED-WRITE-BINDING =  "
        "USERVOL-VFS VFS-NAME-LIMIT"
    ) == (TRUE, 255)
    assert machine.run("T-PLACES  T-DOCS @ PLACE-STATUS  T-DOCS @ PLACE-NAME-LIMIT") == (
        0, 255,
    )
    # A name of 199 bytes, and a path of more than 255.
    assert len(LONG_NAME) == 199 and len(f"/{LONG_FOLDER}/{LONG_NAME}") > 255
    assert machine.run(f"T-DOC {NAME_PATH} T-SAVE") == (0,)
    assert machine.run(f"{FOLDER_PATH} T-DOCS @ PLACE-MKDIR") == (0,)
    assert machine.run(f"T-DOC {LONG_PATH} T-SAVE") == (0,)
    crc, length, ior = machine.run(f"{LONG_PATH} T-READ")
    assert (length, ior) == (len(DOCUMENT), 0)
    # The journal lands, and the host's check passes the volume.
    assert machine.run("USERVOL-VFS VFS-SYNC") == (0,)
    image = tmp_path / "user.img"
    image.write_bytes(machine.user.image_bytes)
    checked = _e2fsck(image)
    assert checked.returncode == 0, checked.stdout + checked.stderr
    assert _debugfs_cat(image, f"/documents/{LONG_NAME}") == DOCUMENT.encode()
    assert _debugfs_cat(
        image, f"/documents/{LONG_FOLDER}/{LONG_NAME}"
    ) == DOCUMENT.encode()


def test_a_unit_without_a_medium_leaves_the_volume_missing() -> None:
    machine = Machine(None)
    (ior,) = machine.run(f"{ARENA} USERVOL-MOUNT")
    assert _reason(ior) == NOVOLUME
    assert machine.run("USERVOL-VFS") == (0,)
    assert machine.run('S" user" PLACES-VOLUME DROP PVOL-VFS') == (0,)
    (status,) = machine.run("T-PLACES T-DOCS @ PLACE-STATUS")
    assert _reason(status) == NOVOLUME
    assert machine.run('S" volume missing" T-WHY=') == (TRUE,)
    # The unit was given back.
    assert machine.run("_USERVOL-BD BD-VALID?") == (0,)


@pytest.mark.parametrize("damage", ["superblock", "other format"])
def test_a_damaged_or_foreign_image_is_refused(
    fresh_user_volume: bytes, damage: str
) -> None:
    if damage == "superblock":
        image = bytearray(fresh_user_volume)
        # The primary superblock's checksum covers its first 1,020 bytes.
        image[1024 + 0x68] ^= 0xFF
        user = bytes(image)
    else:
        user = _boot_disk() + bytes((64 << 20) - len(_boot_disk()))
    machine = Machine(user)
    (ior,) = machine.run(f"{ARENA} USERVOL-MOUNT")
    assert ior != 0
    assert machine.run("USERVOL-VFS") == (0,)
    (status,) = machine.run("T-PLACES T-DOCS @ PLACE-STATUS")
    assert status == ior
    assert machine.run('S" mount refused" T-WHY=') == (TRUE,)
    assert machine.run("_USERVOL-BD BD-VALID? _USERVOL-WRITER @") == (0, 0)
    # Nothing was written to the volume.
    assert machine.user.image_bytes == user


# =====================================================================
#  The boot policy, as the image builder composes it
# =====================================================================

def _build(directory: Path, *, system_volume: bool = False) -> Path:
    _toolchain()
    return tui.build_image(
        PAD, directory / "desk.img", backend="simulator",
        user_volume=True, system_volume=system_volume,
    )


def _uart(runtime) -> str:
    return bytes(runtime.uart_output).decode("utf-8", "replace")


def _evaluate(runtime, source: str) -> tuple[int, ...]:
    runtime.evaluate(source.encode(), source_name="check", step_budget=STEPS)
    stack = runtime.main_context.data.snapshot()
    runtime.main_context.data.clear()
    return stack


POLICY = r"""
CREATE T-PACT PACT-SIZE ALLOT  T-PACT PACT-INIT
\ Whether every place of SET is read-only.
: T-ALL-READ-ONLY?  ( set -- flag )
    -1 SWAP PLSET-FIRST BEGIN ?DUP WHILE
        DUP PLACE-WRITABLE? IF NIP 0 SWAP THEN PLACE-NEXT
    REPEAT ;
"""


def test_a_boot_with_its_user_volume_attaches_and_declares_the_places(
    tmp_path: Path,
) -> None:
    image = _build(tmp_path)
    runtime = tui._boot_in_simulator(image, tui.PROFILES[PAD])
    text = _uart(runtime)
    assert "USER VOLUME ATTACHED" in text and "entering Desk" in text
    runtime.evaluate(POLICY.encode(), source_name="policy")
    # Records are the home, the origin is read-only, and every place is
    # there.
    assert _evaluate(
        runtime,
        'PLACES-DEFAULT PLSET-HOME PLACE-NAME S" records" COMPARE 0= '
        "PLACES-DEFAULT PLSET-HOME PLACE-STATUS "
        "PLACES-DEFAULT PLSET-ORIGIN PLACE-STATUS "
        "PLACES-DEFAULT PLSET-ORIGIN PLACE-WRITABLE? "
        'S" documents" PLACES-DEFAULT PLSET-FIND PLACE-WRITABLE? '
        "PLACES-DEFAULT T-PACT PACT-ACTIVATE",
    ) == (TRUE, 0, 0, 0, TRUE, 0)


def test_a_boot_without_its_user_volume_starts_desk_in_recovery(
    tmp_path: Path,
) -> None:
    image = _build(tmp_path)
    tui.user_image_path(image).unlink()
    runtime = tui._boot_in_simulator(image, tui.PROFILES[PAD])
    text = _uart(runtime)
    assert "USER VOLUME UNAVAILABLE" in text and "entering Desk" in text
    runtime.evaluate(POLICY.encode(), source_name="policy")
    (home,) = _evaluate(runtime, "PLACES-DEFAULT PLSET-HOME PLACE-STATUS")
    assert _reason(home) == NOVOLUME
    assert _evaluate(
        runtime,
        'PLACES-DEFAULT PLSET-HOME PLACE-WHY S" volume missing" COMPARE 0=',
    ) == (TRUE,)
    # The activation finds no usable home: recovery, and every place of the
    # set read-only, the origin's volume as well as the missing one.
    assert _evaluate(
        runtime,
        "PLACES-DEFAULT T-PACT PACT-ACTIVATE  T-PACT PACT-RECOVERY? "
        "PLACES-DEFAULT T-ALL-READ-ONLY?",
    ) == (3, TRUE, TRUE)


def test_a_boot_without_its_origin_stops_with_a_message(tmp_path: Path) -> None:
    image = _build(tmp_path, system_volume=True)
    tui.system_image_path(image).unlink()
    with pytest.raises(RuntimeError) as failure:
        tui._boot_in_simulator(image, tui.PROFILES[PAD])
    assert "SYSTEM VOLUME FAIL mount" in str(failure.value)


def test_a_document_pad_saves_passes_e2fsck_and_a_second_boot_reads_it(
    tmp_path: Path,
) -> None:
    image = _build(tmp_path)
    user = tui.user_image_path(image)
    runtime = tui._boot_in_simulator(image, tui.PROFILES[PAD])
    assert "USER VOLUME ATTACHED" in _uart(runtime)
    runtime.evaluate(HELPERS.encode(), source_name="helpers")
    # The documents place as composition declared it, and a save there the
    # way Pad saves: PLACE-VREPL! for writing and VREPL-REPLACE.
    runtime.evaluate(
        b'S" documents" PLACES-DEFAULT PLSET-FIND T-DOCS !', source_name="place"
    )
    assert _evaluate(runtime, f"T-DOC {NAME_PATH} T-SAVE") == (0,)
    first = _evaluate(runtime, f"{NAME_PATH} T-READ")
    assert first[1:] == (len(DOCUMENT), 0)
    # A clean stop lands the journal.
    assert _evaluate(runtime, "USERVOL-VFS VFS-SYNC") == (0,)
    del runtime
    checked = _e2fsck(user)
    assert checked.returncode == 0, checked.stdout + checked.stderr
    assert _debugfs_cat(user, f"/documents/{LONG_NAME}") == DOCUMENT.encode()
    # The second boot mounts the volume again and reads the document back.
    again = tui._boot_in_simulator(image, tui.PROFILES[PAD])
    assert "USER VOLUME ATTACHED" in _uart(again)
    again.evaluate(HELPERS.encode(), source_name="helpers")
    again.evaluate(
        b'S" documents" PLACES-DEFAULT PLSET-FIND T-DOCS !', source_name="place"
    )
    assert _evaluate(again, f"{NAME_PATH} T-READ") == first
