#!/usr/bin/env python3
"""Application images on a system whose dictionary holds no machine code.

An MF64 image is the machine code the BIOS compiler emitted
(utils/binimg.f), so it can be built from, and run in, only a dictionary
whose compiled words are MP64 machine code.  BIOS ``DICT-MACHINE-CODE?``
states that fact about a Forth system, and binimg's ``IMG-VERIFY-SYSTEM``
turns a no into ``IMG-E-UNSUPPORTED``.

The native simulator compiles no machine code.  There a build and a load are
refused at once and change nothing: the application builder answers
``ABUILD-E-UNSUPPORTED``, the loader ``ALOAD-E-UNSUPPORTED``, and Pad and
Desk show a message that says why.  Without the check the builder would
install an image of headers that hold no code, and a launch would fail
inside ``LATEST!``.

The emulator builds the applet that these tests try to load, and loads it
itself, which shows the refused image to be a good one.
"""

from __future__ import annotations

import re

import pytest

from forth_snapshot import ForthSnapshot, program_output
from native_forth import AKASHIC_ROOT, NativeForth, SharedMachine

from emulator.system import EXT_MEM_BASE

PROJECT = (AKASHIC_ROOT / "examples/trusted-local/project.toml").read_bytes()
SOURCE = (AKASHIC_ROOT / "examples/trusted-local/hello.f").read_bytes()

# The builder, the loader and the drawing words the example applet imports.
ROOTS = ("tui/app-builder.f", "tui/app-loader.f", "tui/draw.f")

# A RAM filesystem with an application catalog, and file transfer through
# one buffer.  The same words run on both machines.
FIXTURE = (
    "VARIABLE _t-vfs  VARIABLE _t-cat  VARIABLE _t-entry",
    "VARIABLE _t-status  VARIABLE _t-desc  VARIABLE _t-fd",
    "VARIABLE _t-pa  VARIABLE _t-pu",
    "65536 XBUF _t-buf",
    ": _t-setup  ( -- )",
    "    2097152 A-XMEM ARENA-NEW IF -1 THROW THEN",
    "    VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN DUP _t-vfs ! VFS-USE",
    "    _t-vfs @ ACAT-NEW DROP DUP _t-cat ! ACAT-ACTIVATE DROP",
    "    _t-cat @ ABUILD-CATALOG! ;",
    ": _t-put  ( data-a data-u path-a path-u -- )",
    "    2DUP _t-vfs @ VFS-CREATE 0= IF -2 THROW THEN",
    "    VFS-OPEN DUP 0= IF -3 THROW THEN _t-fd !",
    "    _t-fd @ VFS-WRITE-EXACT IF -4 THROW THEN _t-fd @ VFS-CLOSE ;",
    ": _t-get  ( path-a path-u dst -- len )",
    "    >R VFS-OPEN DUP 0= IF -5 THROW THEN _t-fd !",
    "    R> _t-fd @ VFS-SIZE DUP >R _t-fd @ VFS-READ-EXACT IF -6 THROW THEN",
    "    _t-fd @ VFS-CLOSE R> ;",
    # Desk's own resolver: the catalog entry's manifest, through the loader.
    ": _t-resolver  ( entry context -- desc status )",
    "    DROP ACE-MANIFEST$ ALOAD-PATH ;",
    ": _t-catalog  ( manifest-a manifest-u -- status )",
    "    _t-pu ! _t-pa !",
    '    S" local.hello" S" Hello" S" 0.1.0" _t-pa @ _t-pu @',
    "    ACAT-F-ENABLED ACAT-F-PINNED OR _t-cat @ ACAT-UPSERT-PACKAGE ;",
    "_t-setup",
)

# Where the project's files sit in the transfer buffer.
SOURCE_AT = 8192
IMAGE_AT = 8192

SIMULATOR = NativeForth(ROOTS, prelude=FIXTURE)


def _number(text: str, marker: str, index: int = 0) -> int:
    """The INDEX-th number printed after MARKER."""

    found = re.search(rf"{re.escape(marker)}((?:\s+-?\d+)+)", text)
    assert found is not None, f"{marker!r} not in:\n{text[-1500:]}"
    return int(found.group(1).split()[index])


def _run(machine: SharedMachine, lines: list[str]) -> str:
    return machine.run(lines, 2_000_000_000).decode("utf-8", errors="replace")


@pytest.fixture
def simulator() -> SharedMachine:
    """A fresh simulator with the builder, the loader and the fixture."""

    return SIMULATOR.shared()


def _buffer(machine: SharedMachine) -> int:
    machine.runtime.execute("_t-buf")
    return machine.runtime.main_context.data.pop()


def _put(machine: SharedMachine, path: str, data: bytes) -> None:
    machine.runtime.memory.write_bytes(_buffer(machine), data)
    text = _run(machine, [f'_t-buf {len(data)} S" {path}" _t-put ." PUT-OK" CR'])
    assert "PUT-OK" in text, text


def _statuses(machine: SharedMachine) -> dict[str, int]:
    text = _run(machine, [
        '." IMG " IMG-E-UNSUPPORTED . ." ABUILD " ABUILD-E-UNSUPPORTED .',
        '." ALOAD " ALOAD-E-UNSUPPORTED . CR',
    ])
    return {name: _number(text, name) for name in ("IMG", "ABUILD", "ALOAD")}


def _emulator_span(system, address: int, length: int):
    if address >= EXT_MEM_BASE:
        return system._ext_mem, address - EXT_MEM_BASE
    return system.cpu.mem, address


@pytest.fixture(scope="module")
def emulator_applet() -> dict:
    """The example applet, built, installed and loaded on the emulator.

    Gives the installed manifest and the image as bytes with their paths,
    and what the emulator answered about its own dictionary.
    """

    forth = ForthSnapshot(ROOTS, prelude=FIXTURE, ext_mem_size=64 << 20)
    where = ['." BUF " _t-buf . CR']
    base = _number(program_output(forth.run(where), where), "BUF")
    captured: dict[str, bytes] = {}

    def setup(system) -> None:
        for offset, data in ((0, PROJECT), (SOURCE_AT, SOURCE)):
            memory, start = _emulator_span(system, base + offset, len(data))
            memory[start:start + len(data)] = data

    def inspect(system) -> None:
        for name, offset, length in (("manifest", 0, 4096), ("image", IMAGE_AT, 49152)):
            memory, start = _emulator_span(system, base + offset, length)
            captured[name] = bytes(memory[start:start + length])

    lines = [
        '." CODE " DICT-MACHINE-CODE? . ." SYSTEM " IMG-VERIFY-SYSTEM . CR',
        f'_t-buf {len(PROJECT)} S" /hello.toml" _t-put',
        f'_t-buf {SOURCE_AT} + {len(SOURCE)} S" /hello.f" _t-put',
        'S" /hello.toml" ABUILD-INSTALL _t-status ! _t-entry !',
        '." BUILD " _t-status @ . CR',
        '." MPATH " ABUILD-INSTALLED-PATH TYPE ."  ;" CR',
        '." IPATH " _ab-image-path _ab-image-path-u @ TYPE ."  ;" CR',
        'ABUILD-INSTALLED-PATH ALOAD-PATH _t-status ! _t-desc !',
        '." LOAD " _t-status @ . ." DESC " _t-desc @ 0<> . CR',
        '." MFT " ABUILD-INSTALLED-PATH _t-buf _t-get . CR',
        f'." IMAGE " _ab-image-path _ab-image-path-u @ _t-buf {IMAGE_AT} + _t-get . CR',
    ]
    text = program_output(forth.run(lines, setup=setup, inspect=inspect), lines)
    assert _number(text, "BUILD") == 0, text
    assert _number(text, "LOAD") == 0 and _number(text, "DESC") == -1, text
    manifest_path = re.search(r"MPATH (\S+)\s+;", text).group(1)
    image_path = re.search(r"IPATH (\S+)\s+;", text).group(1)
    return {
        "machine_code": _number(text, "CODE"),
        "system": _number(text, "SYSTEM"),
        "manifest": captured["manifest"][:_number(text, "MFT")],
        "manifest_path": manifest_path,
        "image": captured["image"][:_number(text, "IMAGE")],
        "image_path": image_path,
    }


def test_each_system_states_whether_its_dictionary_is_machine_code(
    simulator, emulator_applet,
):
    text = _run(simulator, [
        '." CODE " DICT-MACHINE-CODE? . ." SYSTEM " IMG-VERIFY-SYSTEM . CR',
        '." DEPTH " DEPTH . CR',
    ])
    assert _number(text, "CODE") == 0
    assert _number(text, "SYSTEM") == _statuses(simulator)["IMG"] == -12
    assert _number(text, "DEPTH") == 0

    assert emulator_applet["machine_code"] == -1
    assert emulator_applet["system"] == 0


def test_the_emulator_builds_an_image_that_it_loads_itself(emulator_applet):
    """The control: the applet the simulator refuses is a working image."""

    image = emulator_applet["image"]
    assert image[:4] == b"MF64" and len(image) > 64
    assert emulator_applet["image_path"].encode() in emulator_applet["manifest"]
    assert b'entry = "HELLO-ENTRY"' in emulator_applet["manifest"]


def test_a_build_is_refused_before_a_file_is_read_or_source_compiled(simulator):
    expected = _statuses(simulator)
    _put(simulator, "/hello.toml", PROJECT)
    _put(simulator, "/hello.f", SOURCE)
    text = _run(simulator, [
        "HERE LATEST",
        'S" /hello.toml" ABUILD-INSTALL _t-status ! _t-entry !',
        '." STATUS " _t-status @ . ." ENTRY " _t-entry @ .',
        '." DETAIL " ABUILD-LAST-DETAIL . ." LAST " ABUILD-LAST-STATUS . CR',
        '." LATEST-SAME " LATEST = . ." HERE-SAME " HERE = . CR',
        '." ROWS " _t-cat @ ACAT-COUNT . ." INSTALLED " ABUILD-INSTALLED-PATH NIP . CR',
        '." COMPILED " [DEFINED] HELLO-ENTRY . ." RELOC " _RELOC-ACTIVE @ . CR',
        # A project that is not there gets the same answer, not an I/O error.
        'S" /absent.toml" ABUILD-INSTALL ." ABSENT " . . CR',
        '." DEPTH " DEPTH . CR',
    ])
    assert _number(text, "STATUS") == expected["ABUILD"] == -214
    assert _number(text, "ENTRY") == 0
    assert _number(text, "DETAIL") == expected["IMG"]
    assert _number(text, "LAST") == expected["ABUILD"]
    assert _number(text, "LATEST-SAME") == -1 and _number(text, "HERE-SAME") == -1
    assert _number(text, "ROWS") == 0 and _number(text, "INSTALLED") == 0
    assert _number(text, "COMPILED") == 0 and _number(text, "RELOC") == 0
    assert _number(text, "ABSENT") == expected["ABUILD"]
    assert _number(text, "ABSENT", 1) == 0
    assert _number(text, "DEPTH") == 0


def test_the_image_words_refuse_a_build_and_reserve_nothing(simulator):
    expected = _statuses(simulator)["IMG"]
    text = _run(simulator, [
        "HERE",
        "IMG-MARK",
        '." MARK-HERE-SAME " HERE = . ." RELOC " _RELOC-ACTIVE @ . CR',
        ": _t-word 1 ;",
        "' _t-word S\" _t-word\" IMG-EXPORT .\" EXPORT \" . CR",
        "' _t-word S\" _t-word\" IMG-ENTRY-NAMED .\" NAMED \" . CR",
        'IMG-BUFFER-MAX ." MAX " . . CR',
        '_t-buf 4096 IMG-BUILD-INTO ." INTO " . . CR',
        'IMG-DISCARD ." DISCARD " . CR',
        '." WORD " _t-word . ." DEPTH " DEPTH . CR',
    ])
    assert _number(text, "MARK-HERE-SAME") == -1 and _number(text, "RELOC") == 0
    for word in ("EXPORT", "NAMED", "MAX", "INTO", "DISCARD"):
        assert _number(text, word) == expected, word
    assert _number(text, "MAX", 1) == 0 and _number(text, "INTO", 1) == 0
    # Nothing was marked, so the discard rolled nothing back.
    assert _number(text, "WORD") == 1 and _number(text, "DEPTH") == 0


def test_a_load_of_an_image_the_emulator_built_is_refused(
    simulator, emulator_applet,
):
    expected = _statuses(simulator)["IMG"]
    image = emulator_applet["image"]
    simulator.runtime.memory.write_bytes(_buffer(simulator), image)
    text = _run(simulator, [
        "HERE LATEST",
        f'_t-buf {len(image)} IMG-LOAD-MEM ." MEM " . CR',
        f'_t-buf {len(image)} IMG-LOAD-EXEC-MEM ." EXEC " . . CR',
        f'_t-buf {len(image)} S" HELLO-ENTRY" IMG-LOAD-EXPORT ." EXPORT " . . CR',
        '." LATEST-SAME " LATEST = . ." HERE-SAME " HERE = . CR',
        '." LOADED " [DEFINED] HELLO-ENTRY . ." DEPTH " DEPTH . CR',
        # The image can still be read as data: its structure verifies and
        # its export is found.
        f'_t-buf {len(image)} IMG-VERIFY-MEM ." VERIFY " . CR',
        f'_t-buf {len(image)} S" HELLO-ENTRY" IMG-EXPORT-FIND ." FIND " . 0> . CR',
    ])
    for word in ("MEM", "EXEC", "EXPORT"):
        assert _number(text, word) == expected, word
    assert _number(text, "EXEC", 1) == 0 and _number(text, "EXPORT", 1) == 0
    assert _number(text, "LATEST-SAME") == -1 and _number(text, "HERE-SAME") == -1
    assert _number(text, "LOADED") == 0 and _number(text, "DEPTH") == 0
    assert _number(text, "VERIFY") == 0
    assert _number(text, "FIND") == 0 and _number(text, "FIND", 1) == -1


def test_the_loader_refuses_an_installed_applet_before_it_reads_one(
    simulator, emulator_applet,
):
    expected = _statuses(simulator)["ALOAD"]
    manifest = emulator_applet["manifest"]
    path = emulator_applet["manifest_path"]
    _put(simulator, emulator_applet["image_path"], emulator_applet["image"])
    _put(simulator, path, manifest)
    simulator.runtime.memory.write_bytes(_buffer(simulator), manifest)
    text = _run(simulator, [
        "HERE LATEST",
        f'S" {path}" ALOAD-PATH ." PATH " . . CR',
        f'_t-buf {len(manifest)} ALOAD-MANIFEST ." DOCUMENT " . . CR',
        f"_t-buf {len(manifest)} MFT-PARSE DROP DUP _t-entry !",
        'ALOAD-FROM-MFT ." PARSED " . . CR  _t-entry @ MFT-FREE',
        # A manifest that is not there gets the same answer, not an open error.
        'S" /absent.toml" ALOAD-PATH ." ABSENT " . . CR',
        '." LATEST-SAME " LATEST = . ." HERE-SAME " HERE = . CR',
        '." LOADED " [DEFINED] HELLO-ENTRY . ." DEPTH " DEPTH . CR',
    ])
    assert expected == -141
    for word in ("PATH", "DOCUMENT", "PARSED", "ABSENT"):
        assert _number(text, word) == expected, word
        assert _number(text, word, 1) == 0, word
    assert _number(text, "LATEST-SAME") == -1 and _number(text, "HERE-SAME") == -1
    assert _number(text, "LOADED") == 0 and _number(text, "DEPTH") == 0


def test_the_catalog_hands_desk_the_loaders_status(simulator, emulator_applet):
    """Desk opens an installed applet through the catalog's resolver, and
    shows the status that comes back."""

    path = emulator_applet["manifest_path"]
    _put(simulator, emulator_applet["image_path"], emulator_applet["image"])
    _put(simulator, path, emulator_applet["manifest"])
    text = _run(simulator, [
        f'S" {path}" _t-catalog ." UPSERT " . CR',
        'S" local.hello" _t-cat @ ACAT-FIND-ID _t-entry !',
        "' _t-resolver 0 _t-cat @ ACAT-RESOLVER!",
        '_t-entry @ _t-cat @ ACAT-RESOLVE ." RESOLVE " . . CR',
        '." ERROR " _t-entry @ ACE.ERROR @ . ." DEPTH " DEPTH . CR',
    ])
    expected = _statuses(simulator)["ALOAD"]
    assert _number(text, "UPSERT") == 0
    assert _number(text, "RESOLVE") == expected and _number(text, "RESOLVE", 1) == 0
    assert _number(text, "ERROR") == expected and _number(text, "DEPTH") == 0


# Pad and Desk with their own words for the two messages.  Desk's net
# modules use the constants MegaPad's networking module defines.
APPLETS = NativeForth(
    ("tui/applets/desk/desk.f", "tui/applets/pad/pad.f"),
    system_modules=("networking.f",),
    prelude=(
        "_PAD-STATE-SIZE ALLOCATE THROW CONSTANT _t-pad",
        ": _t-pad-fresh  ( -- )",
        "    _t-pad _PAD-STATE-SIZE 0 FILL  _t-pad _PAD-CURRENT-STATE ! ;",
    ),
    load_steps=3_000_000_000,
)


def test_pad_and_desk_say_why_in_plain_words():
    machine = APPLETS.shared()
    text = _run(machine, [
        "_t-pad-fresh _PAD-OUTPUT-RESET",
        "ABUILD-E-UNSUPPORTED _PAD-BUILD-GENERIC-ERROR",
        '." PAD<" _PAD-OUTPUT-LOG _PAD-OUTPUT-LOG-U @ TYPE ." >" CR',
        '." DESK<" ALOAD-E-UNSUPPORTED _DESK-CATALOG-STATUS$ TYPE ." >" CR',
        # Every other loader failure keeps the launcher's general wording.
        '." OTHER<" ALOAD-E-IMAGE-LOAD _DESK-CATALOG-STATUS$ TYPE ." >" CR',
        '." DEPTH " DEPTH . CR',
    ])
    assert ("PAD<Nothing was built: applets are machine code, "
            "and this system compiles none.>") in text
    assert "DESK<this system cannot run machine-code applets>" in text
    assert "OTHER<launch failed>" in text
    assert _number(text, "DEPTH") == 0
