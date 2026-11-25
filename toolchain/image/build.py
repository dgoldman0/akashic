"""The image tool: a machine's volumes, built from its description.

build() turns an ImageSpec into the volumes a session attaches: the MP64FS
boot volume, which holds KDOS and what the boot script loads before it can
mount ext4; the read-only settings disk; and, as asked, the ext4 system
volume, which holds Akashic's modules as plain files or their token forms,
and the ext4 user volume.  An image's modules are the REQUIRE closure of its
roots (closure.py).  A linked image packs them into chunks on the boot
volume instead, plain or as checked cold-source containers.  Token forms are
recorded by booting the image once from source in MegaPad's simulator.
"""

from __future__ import annotations

import contextlib
import hashlib
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
import time
import uuid
import zlib
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

from .megapad import AKASHIC_ROOT, MEGAPAD_ROOT, SOURCE_ROOT

from diskutil import (
    FLAG_SYSTEM,
    FTYPE_DATA,
    FTYPE_FORTH,
    FTYPE_TEXT,
    MAX_FILES,
    MAX_NAME_LEN,
    MP64FS,
    pack_forth_source,
)

from .closure import (
    PROVIDED_RE,
    REQUIRE_RE,
    dependency_closure as _shared_dependency_closure,
    dependency_order as _shared_dependency_order,
    module_key,
    normalize_module as _shared_normalize_module,
)
from .desk import DESK_SYSTEM_SETTINGS, SETTINGS_DISK_SECTORS, _with_practice_home_guard
from .forth import (
    _coalesce_audited_forth_lines,
    _forth_line_contains_module_load,
    _forth_line_tokens,
    _minify_forth,
    _strip_forth_noncode_lines,
)
from .rich import RichTerminalProfile


# Keep deployment chunks modest even though KDOS now batches large module
# transfers.  This bounds source prescan/evaluation work and leaves room for
# profile growth without changing the generated chunk topology on every edit.
LINK_CHUNK_BYTES = 120 * 1024
COLD_SOURCE_MAGIC = b"AKSRC001"
COLD_SOURCE_VERSION = 1
COLD_SOURCE_CODEC_LZSS = 0
COLD_SOURCE_CODEC_STORED = 1
COLD_SOURCE_CODECS = frozenset(
    (COLD_SOURCE_CODEC_LZSS, COLD_SOURCE_CODEC_STORED)
)
COLD_SOURCE_CODEC_NAMES = {
    COLD_SOURCE_CODEC_LZSS: "lzss",
    COLD_SOURCE_CODEC_STORED: "stored",
}
COLD_SOURCE_HEADER_BYTES = 40
COLD_SOURCE_RAW_MAX_BYTES = LINK_CHUNK_BYTES
COLD_SOURCE_LOADER_PATH = "coldsrc.f"
COLD_SOURCE_CHUNK_TEMPLATE = "source-{index:02d}.src"
COLD_SOURCE_HEADER = struct.Struct("<8sHHIQQII")
DEFAULT_EXT_MEM_MIB = 128
DEFAULT_RAM_KIB = 1024
DEFAULT_VRAM_MIB = 4
MACHINE_BACKENDS = ("emulator", "simulator", "hybrid")
# The terminal a token-recording boot runs on: the canonical Desktop's.
RECORDING_COLS = 280
RECORDING_ROWS = 84
# Both semantic backends boot the same prepared image as one semantic session;
# hybrid also runs declared machine routines on a native core.
SEMANTIC_BACKENDS = ("simulator", "hybrid")


@dataclass(frozen=True, kw_only=True)
class ImageSpec:
    """What build() makes an image from: the REQUIRE roots, the resources
    and files the image carries, its boot script, the form its modules take,
    the machine its token forms are recorded on, and its session's rich
    terminal bounds."""

    roots: tuple[str, ...]
    resources: tuple[str, ...]
    autoexec: str
    linked: bool = False
    # A profile that stages its Akashic modules as initial files, not
    # roots, declares here whether they consume KDOS networking; the image
    # then carries MegaPad's networking.f, required after ENTER-USERLAND.
    megapad_networking: bool = False
    # Files the profile ships for its own code: on the boot volume, or on
    # the system volume when that volume is the origin of a build with the
    # user volume, at their paths.
    initial_files: tuple[tuple[str, bytes], ...] = ()
    # Samples of the profile's own, files a person works with, such as a
    # picture a check previews.  They go where the build puts the image's
    # samples (build's SAMPLES): the boot volume's root, or with the user
    # volume its documents.
    sample_files: tuple[tuple[str, bytes], ...] = ()
    # Raw Forth sources deployed as checked AKSRC001 data containers.  Each
    # tuple names the on-image container, not the host source.  This keeps
    # qualification leaves on the same checked cold-compile path as linked
    # production modules instead of routing them through KDOS's unchecked
    # line walker.
    cold_source_initial_files: tuple[tuple[str, bytes], ...] = ()
    include_large_sample: bool = True
    # Focused development images hold their module closure plus samples.
    # 4 MiB leaves room for the generated Unicode text tables that every
    # TUI closure now carries; it is a development default, not a limit.
    total_sectors: int = 8192
    link_chunk_bytes: int = LINK_CHUNK_BYTES
    # A cold-source codec opts linked source into the checked container path.
    # The guest validates and compiles each source chunk through the checked
    # evaluator; this is not a compiled dictionary cache.  Stored containers
    # avoid guest decompression while retaining the same integrity and
    # failure-atomic evaluation contract.
    cold_source_codec: int | None = None
    # Physical-line joining is safe only for a source closure audited for
    # line-sensitive custom parsing words.  It is never a default transform.
    audited_link_line_bytes: int | None = None
    audited_initial_forth_line_bytes: int | None = None
    rich_terminal: RichTerminalProfile | None = None
    rich_boot_progress: bool = False
    minimum_free_bytes: int = 0
    default_ext_mem_mib: int = DEFAULT_EXT_MEM_MIB
    # The machine a session boots by default: full cores, and micro-core
    # clusters beside them.  The simulator runs one to four full cores and
    # no cluster, the hybrid backend one full core, and only the emulator
    # accepts clusters.
    full_cores: int = 1
    clusters: int = 0
    # A profile opts into semantic execution by naming the ordinary Forth
    # entry boundary that the simulator may defer until after autoexec has
    # returned to its outer dispatch.  Emulator images invoke this word in
    # place as usual; no alternate application composition is permitted.
    session_entry: str | None = None
    # Zero preserves KDOS's default dictionary/general-XMEM partition.
    general_xmem_reserve_bytes: int = 0
    # The system settings, Akashic paths that go on the settings disk: the
    # second storage unit, whose medium the machine reads and never writes.
    # A profile with none gets no settings disk.
    settings_files: tuple[str, ...] = ()

    def __post_init__(self) -> None:
        if (
            isinstance(self.default_ext_mem_mib, bool)
            or not isinstance(self.default_ext_mem_mib, int)
            or self.default_ext_mem_mib <= 0
        ):
            raise ValueError("default_ext_mem_mib must be a positive integer")
        if (
            isinstance(self.full_cores, bool)
            or not isinstance(self.full_cores, int)
            or self.full_cores <= 0
        ):
            raise ValueError("full_cores must be a positive integer")
        if (
            isinstance(self.clusters, bool)
            or not isinstance(self.clusters, int)
            or self.clusters < 0
        ):
            raise ValueError("clusters must be a non-negative integer")
        if (
            isinstance(self.general_xmem_reserve_bytes, bool)
            or not isinstance(self.general_xmem_reserve_bytes, int)
        ):
            raise TypeError("general_xmem_reserve_bytes must be an integer")
        if (
            not 0 <= self.general_xmem_reserve_bytes <= 0xFFFFFFFF
            or self.general_xmem_reserve_bytes & 15
            or self.general_xmem_reserve_bytes >= self.default_ext_mem_mib << 20
        ):
            raise ValueError("general_xmem_reserve_bytes must be aligned and leave dictionary memory")
        if (
            self.cold_source_codec is not None
            and (
                isinstance(self.cold_source_codec, bool)
                or self.cold_source_codec not in COLD_SOURCE_CODECS
            )
        ):
            raise ValueError(
                "cold_source_codec must be None, "
                "COLD_SOURCE_CODEC_LZSS, or COLD_SOURCE_CODEC_STORED"
            )
        if self.session_entry is not None and (
            not isinstance(self.session_entry, str)
            or not self.session_entry
            or any(character.isspace() for character in self.session_entry)
        ):
            raise ValueError("session_entry must be one nonempty Forth token")


# Akashic modules that bind directly to the networking surface exported by
# MegaPad's loadable networking.f module.  Checking the resolved profile
# closure keeps parser-only and abstract-I/O net modules lightweight while
# making each native KDOS transport pull in the one canonical system module.
MEGAPAD_NETWORKING_CONSUMERS = frozenset(
    {
        "atproto/public-author-feed.f",
        "net/http.f",
        "net/tls-trust-registry.f",
        "net/transports/kdos-tls.f",
        "net/transports/kdos-tls-inbound.f",
        "net/transports/kdos-tls-port.f",
        "net/ws.f",
        "web/response.f",
        "web/server.f",
    }
)
MEGAPAD_NETWORKING_BOOT_LINE = "REQUIRE networking.f"
# Data files a module reads from its origin at run time.  Every image whose
# module closure holds the module carries them at these paths, beside the
# profile's own resources: net/web-roots.f reads the pinned global TLS root
# set (docs/net/web-roots.md).
MODULE_DATA_FILES: dict[str, tuple[str, ...]] = {
    "net/web-roots.f": ("net/web-roots/web-roots.mpta",),
}
MEGAPAD_RICH_TERMINAL_MODULE = "rich-terminal.f"
MEGAPAD_RICH_TERMINAL_BOOT_LINE = (
    f"REQUIRE {MEGAPAD_RICH_TERMINAL_MODULE}"
)
# Like the native networking consumers above, these Akashic modules compile
# against an already-loaded MegaPad system ABI.  They must never REQUIRE or
# copy the MegaPad source into the Akashic dependency graph.
MEGAPAD_RICH_TERMINAL_CONSUMERS = frozenset(
    {
        "tui/app-shell-apt1.f",
        "tui/desk-apt1.f",
        "tui/rich-terminal/apt1-engine.f",
        "tui/rich-terminal/screen-adapter-apt1.f",
        "tui/screen-backend-apt1.f",
    }
)
APP_SHELL_MODULE = "tui/app-shell.f"
MP64FS_VFS_PLATFORM_MODULE = "tui/platform/mp64fs-vfs.f"
MP64FS_VFS_PLATFORM_BOOT_LINE = f"REQUIRE {MP64FS_VFS_PLATFORM_MODULE}"
# The places this build declares (docs/utils/fs/places.md).  The platform
# module reports the boot volume; composition declares one writable place
# over its root and a default set in which that place is both the home,
# where records are written, and the origin, where shipped files are read.
# The origin is required, so a boot without it stops here with a message.
# Applets ask the set for its home, its origin and its list, so the names
# below appear nowhere else.
PLACES_BOOT_ENTRY = "_boot-places-declare"
# The name composition gives the build's one place.  A check that reads a
# file's locator on the screen builds it from this.
PLACES_BOOT_PLACE = "files"
# What a person reads for it, as the first row of an explorer's tree.
PLACES_BOOT_LABEL = "Files"
PLACES_BOOT_LINES = (
    "VARIABLE _boot-place  VARIABLE _boot-places",
    f": {PLACES_BOOT_ENTRY}  ( -- )",
    '    S" boot" PLACES-VOLUME ABORT" PLACES FAIL volume"',
    f'    >R S" {PLACES_BOOT_PLACE}" S" /" PLACE-WRITABLE R> PLACES-DECLARE',
    '        ABORT" PLACES FAIL place"  _boot-place !',
    f'    S" {PLACES_BOOT_LABEL}" _boot-place @ PLACE-LABEL! ABORT" PLACES FAIL label"',
    "    -1 _boot-place @ PLACE-REQUIRED!",
    "    PLACES-CHECK ?DUP IF",
    '        NIP ." PLACES FAIL origin ior=" . CR TX-FLUSH ABORT',
    "    THEN DROP",
    '    PLSET-NEW ABORT" PLACES FAIL set"  _boot-places !',
    "    PLACE-WRITABLE _boot-place @ _boot-places @ PLSET-GRANT",
    '        ABORT" PLACES FAIL grant"',
    "    DUP _boot-places @ PLSET-HOME!  DUP _boot-places @ PLSET-ORIGIN!",
    "    _boot-places @ PLSET-DOCUMENTS!",
    "    _boot-places @ PLACES-DEFAULT! ;",
    PLACES_BOOT_ENTRY,
)
# With --system-volume a profile's modules are plain files on the system
# volume, the ext4 volume on the machine's third storage unit.  The boot
# volume then carries only the closure of the module that mounts it,
# deployed as the profile deploys its source, and autoexec.f mounts the
# volume and makes it the source of LOAD and REQUIRE before the profile's
# own REQUIREs run (docs/utils/fs/system-volume.md).  The arena is the
# mount's storage, its records; the cache of entries and names takes its
# pages from the heap.
SYSTEM_VOLUME_MODULE = "utils/fs/system-volume.f"
SYSTEM_VOLUME_ARENA_BYTES = 524288
SYSTEM_VOLUME_BOOT_ENTRY = "_BOOT-SYSTEM-VOLUME"
SYSTEM_VOLUME_BOOT_LINES = (
    f": {SYSTEM_VOLUME_BOOT_ENTRY}  ( -- )",
    f"    {SYSTEM_VOLUME_ARENA_BYTES} A-XMEM ARENA-NEW ?DUP IF",
    '        NIP ." SYSTEM VOLUME FAIL arena ior=" . CR TX-FLUSH ABORT',
    "    THEN",
    "    SYSVOL-MOUNT ?DUP IF",
    '        ." SYSTEM VOLUME FAIL mount ior=" . CR TX-FLUSH ABORT',
    "    THEN",
    "    SYSVOL-SOURCE MODULE-SOURCE! ;",
    SYSTEM_VOLUME_BOOT_ENTRY,
)
# With --user-volume the build adds the user volume, the ext4 volume on the
# machine's fourth storage unit, unit 3, and declares the shipping form's
# places (docs/utils/fs/places.md): a read-only place over the root of the
# volume that holds the profile's shipped files, which is the origin, and
# two writable places on the user volume, documents and records, in folders
# of their own, records being the home.  That volume is the system volume
# when the build has one and the boot volume otherwise.  utils/fs/
# user-volume.f mounts the user volume and reports it to the registry; a
# boot without its image, or with one the driver refuses, goes on, and Desk
# starts in recovery because its home is missing.  The layout below is the
# only place it is written: the boot lines declare it and the user image is
# built with its folders.
USER_VOLUME_MODULE = "utils/fs/user-volume.f"
USER_VOLUME_ARENA_BYTES = 524288
USER_VOLUME_DEFAULT_MIB = 64
USER_VOLUME_BLOCK_BYTES = 1024
USER_VOLUME_LABEL = "AKASHIC-USER"
# (name, folder, label) of the places the shipping form declares.
USER_VOLUME_ORIGIN = ("system", "/", "System")
USER_VOLUME_DOCUMENTS = ("documents", "/documents", "Documents")
USER_VOLUME_RECORDS = ("records", "/records", "Records")
USER_VOLUME_FOLDERS = (USER_VOLUME_DOCUMENTS[1], USER_VOLUME_RECORDS[1])


def _user_volume_boot_lines(system_volume: bool) -> tuple[str, ...]:
    """The lines that load and mount the user volume and declare the
    shipping form's places over it, in PLACES_BOOT_LINES' place.  The boot
    says how the mount went and goes on whatever it answered: only a missing
    origin stops it."""

    origin_name, origin_folder, origin_label = USER_VOLUME_ORIGIN
    documents_name, documents_folder, documents_label = USER_VOLUME_DOCUMENTS
    records_name, records_folder, records_label = USER_VOLUME_RECORDS
    if system_volume:
        # The system volume's module mounted it before this; composition
        # reports it to the registry, where the origin is declared over it.
        origin_volume = [
            '    S" system" PLACES-VOLUME ABORT" PLACES FAIL volume"',
            "    SYSVOL-VFS OVER PVOL-ATTACH ABORT\" PLACES FAIL system volume\"",
        ]
    else:
        origin_volume = ['    S" boot" PLACES-VOLUME ABORT" PLACES FAIL volume"']
    return (
        f"REQUIRE {USER_VOLUME_MODULE}",
        ": _boot-user-volume  ( -- )",
        f"    {USER_VOLUME_ARENA_BYTES} USERVOL-MOUNT ?DUP IF",
        '        ." USER VOLUME UNAVAILABLE ior=" . CR TX-FLUSH',
        "    ELSE",
        '        ." USER VOLUME ATTACHED" CR',
        "    THEN ;",
        "_boot-user-volume",
        "VARIABLE _boot-origin  VARIABLE _boot-documents",
        "VARIABLE _boot-records  VARIABLE _boot-places",
        f": {PLACES_BOOT_ENTRY}  ( -- )",
        *origin_volume,
        f'    >R S" {origin_name}" S" {origin_folder}" PLACE-READ-ONLY R> PLACES-DECLARE',
        '        ABORT" PLACES FAIL place"  _boot-origin !',
        f'    S" {origin_label}" _boot-origin @ PLACE-LABEL! ABORT" PLACES FAIL label"',
        "    -1 _boot-origin @ PLACE-REQUIRED!",
        "    PLACES-CHECK ?DUP IF",
        '        NIP ." PLACES FAIL origin ior=" . CR TX-FLUSH ABORT',
        "    THEN DROP",
        '    S" user" PLACES-VOLUME ABORT" PLACES FAIL volume"',
        f'    >R S" {documents_name}" S" {documents_folder}" PLACE-WRITABLE R@ PLACES-DECLARE',
        '        ABORT" PLACES FAIL place"  _boot-documents !',
        f'    S" {records_name}" S" {records_folder}" PLACE-WRITABLE R> PLACES-DECLARE',
        '        ABORT" PLACES FAIL place"  _boot-records !',
        f'    S" {documents_label}" _boot-documents @ PLACE-LABEL! ABORT" PLACES FAIL label"',
        f'    S" {records_label}" _boot-records @ PLACE-LABEL! ABORT" PLACES FAIL label"',
        '    PLSET-NEW ABORT" PLACES FAIL set"  _boot-places !',
        "    PLACE-WRITABLE _boot-documents @ _boot-places @ PLSET-GRANT",
        '        ABORT" PLACES FAIL grant"  _boot-places @ PLSET-DOCUMENTS!',
        "    PLACE-WRITABLE _boot-records @ _boot-places @ PLSET-GRANT",
        '        ABORT" PLACES FAIL grant"  _boot-places @ PLSET-HOME!',
        "    PLACE-READ-ONLY _boot-origin @ _boot-places @ PLSET-GRANT",
        '        ABORT" PLACES FAIL grant"  _boot-places @ PLSET-ORIGIN!',
        "    _boot-places @ PLACES-DEFAULT! ;",
        PLACES_BOOT_ENTRY,
    )


def _normalize_module(module: str, requiring: str | None = None) -> str:
    return _shared_normalize_module(module, requiring)


def dependency_closure(roots: tuple[str, ...]) -> tuple[str, ...]:
    """Return the deterministic transitive REQUIRE closure for *roots*."""
    return _shared_dependency_closure(SOURCE_ROOT, roots)


def dependency_order(roots: tuple[str, ...]) -> tuple[str, ...]:
    """Return dependencies before their requiring modules."""
    return _shared_dependency_order(SOURCE_ROOT, roots)


def _requires_megapad_networking(modules: tuple[str, ...]) -> bool:
    """Return whether an Akashic module closure consumes KDOS networking."""
    return not MEGAPAD_NETWORKING_CONSUMERS.isdisjoint(modules)


def _requires_megapad_rich_terminal(
    modules: tuple[str, ...],
) -> bool:
    """Return whether an Akashic closure consumes the boot-loaded PT ABI."""
    return not MEGAPAD_RICH_TERMINAL_CONSUMERS.isdisjoint(modules)


def _forth_line_contains_networking_load(
    tokens: tuple[str, ...], command: str
) -> bool:
    return _forth_line_contains_module_load(tokens, command, "networking.f")


def _without_places_boot_lines(lines: list[str]) -> list[str]:
    """LINES without the places declaration, wherever it stands."""
    block = list(PLACES_BOOT_LINES)
    for index in range(len(lines) - len(block) + 1):
        if lines[index:index + len(block)] == block:
            return lines[:index] + lines[index + len(block):]
    return lines


def _with_mp64fs_vfs_platform(
    autoexec: str, places_lines: tuple[str, ...] = PLACES_BOOT_LINES
) -> str:
    """Compose the eager MP64FS VFS, and declare the build's places over
    it with PLACES_LINES, before any applet module is loaded."""
    lines = _without_places_boot_lines(autoexec.splitlines())
    token_lines = [_forth_line_tokens(line) for line in lines]
    userland_lines = [
        index
        for index, tokens in enumerate(token_lines)
        if len(tokens) == 1 and tokens[0].upper() == "ENTER-USERLAND"
    ]
    if len(userland_lines) != 1:
        raise RuntimeError(
            "App-shell profiles must enter userland exactly once before "
            "loading the MP64FS VFS platform"
        )
    platform_lines = [
        index
        for index, tokens in enumerate(token_lines)
        if len(tokens) == 2
        and tokens[0].upper() == "REQUIRE"
        and tokens[1] == MP64FS_VFS_PLATFORM_MODULE
    ]
    if len(platform_lines) > 1:
        raise RuntimeError(
            "App-shell profiles must load the MP64FS VFS platform exactly once"
        )
    if platform_lines:
        old_index = platform_lines[0]
        lines.pop(old_index)
        token_lines.pop(old_index)

    userland_index = next(
        index
        for index, tokens in enumerate(token_lines)
        if len(tokens) == 1 and tokens[0].upper() == "ENTER-USERLAND"
    )
    insert_index = userland_index + 1
    if (
        insert_index < len(token_lines)
        and len(token_lines[insert_index]) == 2
        and token_lines[insert_index][0].upper() == "REQUIRE"
        and token_lines[insert_index][1].lower() == "networking.f"
    ):
        insert_index += 1
    lines[insert_index:insert_index] = [
        MP64FS_VFS_PLATFORM_BOOT_LINE, *places_lines
    ]
    suffix = "\n" if autoexec.endswith("\n") else ""
    return "\n".join(lines) + suffix


def _with_megapad_networking(autoexec: str) -> str:
    """Require canonical networking.f immediately after entering userland."""
    lines = autoexec.splitlines()
    token_lines = [_forth_line_tokens(line) for line in lines]
    if any(
        _forth_line_contains_networking_load(tokens, "FSLOAD")
        for tokens in token_lines
    ):
        raise RuntimeError(
            "FSLOAD networking.f is unsafe during KDOS autoboot; use the "
            "KDOS module loader"
        )
    userland_lines = [
        index
        for index, tokens in enumerate(token_lines)
        if len(tokens) == 1 and tokens[0].upper() == "ENTER-USERLAND"
    ]
    if len(userland_lines) != 1:
        raise RuntimeError(
            "Networking profiles must enter userland exactly once before "
            "loading networking.f"
    )
    expected_index = userland_lines[0] + 1
    networking_lines = [
        index
        for index, tokens in enumerate(token_lines)
        if _forth_line_contains_networking_load(tokens, "REQUIRE")
    ]
    if networking_lines:
        if (
            networking_lines != [expected_index]
            or len(token_lines[expected_index]) != 2
            or token_lines[expected_index][0].upper() != "REQUIRE"
            or token_lines[expected_index][1] != "networking.f"
        ):
            raise RuntimeError(
                "Networking profiles must load networking.f exactly once, "
                "immediately after entering userland"
            )
        return autoexec
    lines.insert(expected_index, MEGAPAD_NETWORKING_BOOT_LINE)
    suffix = "\n" if autoexec.endswith("\n") else ""
    return "\n".join(lines) + suffix


def _with_userland_xmem_reserve(autoexec: str, reserve_bytes: int) -> str:
    """Select KDOS's existing partition before the first userland entry."""
    if isinstance(reserve_bytes, bool) or not isinstance(reserve_bytes, int):
        raise TypeError("general XMEM reserve must be an integer")
    if not 0 <= reserve_bytes <= 0xFFFFFFFF or reserve_bytes & 15:
        raise ValueError("general XMEM reserve must be an aligned u32")
    if reserve_bytes == 0:
        return autoexec
    lines = autoexec.splitlines()
    tokens = [_forth_line_tokens(line) for line in lines]
    entries = [i for i, words in enumerate(tokens)
               if len(words) == 1 and words[0].upper() == "ENTER-USERLAND"]
    if len(entries) != 1:
        raise RuntimeError("XMEM partition requires exactly one ENTER-USERLAND")
    entry = entries[0]
    declaration = f"{reserve_bytes} U-XMEM-RESERVE !"
    existing = [i for i, words in enumerate(tokens)
                if any(word.upper() == "U-XMEM-RESERVE" for word in words)]
    if existing:
        if existing != [entry - 1] or lines[entry - 1] != declaration:
            raise RuntimeError("XMEM reserve must appear exactly once immediately before ENTER-USERLAND")
        return autoexec
    lines.insert(entry, declaration)
    return "\n".join(lines) + ("\n" if autoexec.endswith("\n") else "")


def _with_megapad_rich_terminal(
    autoexec: str,
    rich_terminal: RichTerminalProfile,
) -> str:
    """Load and configure the external APT module before Akashic sources."""
    if not isinstance(rich_terminal, RichTerminalProfile):
        raise TypeError("rich_terminal must be a RichTerminalProfile")
    lines = autoexec.splitlines()
    token_lines = [_forth_line_tokens(line) for line in lines]
    if any(
        _forth_line_contains_module_load(
            tokens, "FSLOAD", MEGAPAD_RICH_TERMINAL_MODULE
        )
        for tokens in token_lines
    ):
        raise RuntimeError(
            "FSLOAD rich-terminal.f is unsafe during KDOS autoboot; "
            "use the KDOS module loader"
        )
    userland_lines = [
        index
        for index, tokens in enumerate(token_lines)
        if len(tokens) == 1 and tokens[0].upper() == "ENTER-USERLAND"
    ]
    if len(userland_lines) != 1:
        raise RuntimeError(
            "Rich-terminal profiles must enter userland exactly once before "
            "loading rich-terminal.f"
        )
    expected_index = userland_lines[0] + 1
    if (
        expected_index < len(token_lines)
        and len(token_lines[expected_index]) == 2
        and token_lines[expected_index][0].upper() == "REQUIRE"
        and token_lines[expected_index][1] == "networking.f"
    ):
        expected_index += 1
    canonical_block = [
        MEGAPAD_RICH_TERMINAL_BOOT_LINE,
        (
            f"{rich_terminal.guest_rx_bytes} CONSTANT "
            "APT1-DESK-RX-CAPACITY"
        ),
        (
            f"{rich_terminal.guest_tx_bytes} CONSTANT "
            "APT1-DESK-TX-CAPACITY"
        ),
        (
            f"{rich_terminal.guest_collection_native_bytes} CONSTANT "
            "APT1-DESK-COLLECTION-NATIVE-CAPACITY"
        ),
        (
            f"{rich_terminal.guest_data_graphics_native_bytes} CONSTANT "
            "APT1-DESK-DATA-GRAPHICS-NATIVE-CAPACITY"
        ),
        (
            f"{rich_terminal.guest_status_field_native_bytes} CONSTANT "
            "APT1-DESK-STATUS-FIELDS-NATIVE-CAPACITY"
        ),
        (
            f"{rich_terminal.guest_field_native_bytes} CONSTANT "
            "APT1-DESK-FIELDS-NATIVE-CAPACITY"
        ),
    ]
    if rich_terminal.shell:
        canonical_block.append("-1 CONSTANT APT1-DESK-SHELL-ENABLED")
    rich_terminal_lines = [
        index
        for index, tokens in enumerate(token_lines)
        if _forth_line_contains_module_load(
            tokens, "REQUIRE", MEGAPAD_RICH_TERMINAL_MODULE
        )
    ]
    shell_bound_lines = [
        index for index, tokens in enumerate(token_lines)
        if any(token.upper() == "APT1-DESK-SHELL-ENABLED" for token in tokens)
    ]
    expected_shell_bound_lines = (
        [expected_index + len(canonical_block) - 1]
        if rich_terminal_lines and rich_terminal.shell else []
    )
    if shell_bound_lines != expected_shell_bound_lines:
        raise RuntimeError(
            "Rich-terminal shell selection must match the selected profile exactly once"
        )
    if rich_terminal_lines:
        if (
            rich_terminal_lines != [expected_index]
            or lines[expected_index : expected_index + len(canonical_block)]
            != canonical_block
        ):
            raise RuntimeError(
                "Rich-terminal profiles must load and configure "
                "rich-terminal.f exactly once after networking"
            )
        return autoexec
    lines[expected_index:expected_index] = canonical_block
    suffix = "\n" if autoexec.endswith("\n") else ""
    return "\n".join(lines) + suffix


def _rich_desktop_boot_line(message: str) -> str:
    """Return one promptly visible pre-ownership Desk boot marker."""
    return f'." [akashic boot] {message}" CR TX-FLUSH'


def _with_rich_desktop_boot_progress(
    autoexec: str,
    rich_terminal: RichTerminalProfile,
    chunk_names: tuple[str, ...],
    *,
    volume_modules: tuple[str, ...] = (),
) -> str:
    """Instrument the generated rich Desk cold-load path before PT-START.

    VOLUME_MODULES are the modules a system-volume image loads from that
    volume.  Its chunks hold the volume's driver, and the framework is ready
    once the last REQUIRE of one of those modules has run.
    """
    if not chunk_names:
        raise RuntimeError("Rich Desktop boot progress requires source chunks")
    chunk_label = "volume driver" if volume_modules else "framework"
    if f"[akashic boot] {chunk_label} source " in autoexec:
        raise RuntimeError("Rich Desktop boot progress is already installed")

    lines = autoexec.splitlines()
    userland_line = "ENTER-USERLAND"
    rich_bounds_last_line = (
        f"{rich_terminal.guest_field_native_bytes} CONSTANT "
        "APT1-DESK-FIELDS-NATIVE-CAPACITY"
    )
    if rich_terminal.shell:
        rich_bounds_last_line = "-1 CONSTANT APT1-DESK-SHELL-ENABLED"
    loader_line = f"REQUIRE {COLD_SOURCE_LOADER_PATH}"
    chunk_lines = tuple(
        f"_BOOT-COLD-SOURCE {name}" for name in chunk_names
    )
    required_lines = (
        userland_line,
        MEGAPAD_NETWORKING_BOOT_LINE,
        MEGAPAD_RICH_TERMINAL_BOOT_LINE,
        rich_bounds_last_line,
        loader_line,
        *chunk_lines,
    )
    for required in required_lines:
        if lines.count(required) != 1:
            raise RuntimeError(
                "Rich Desktop boot progress expected exactly one line: "
                f"{required}"
            )

    positions = tuple(lines.index(line) for line in required_lines)
    if positions != tuple(sorted(positions)):
        raise RuntimeError(
            "Rich Desktop boot progress requires canonical boot ordering"
        )
    volume_module_set = set(volume_modules)
    volume_requires = [
        index
        for index, line in enumerate(lines)
        if (match := REQUIRE_RE.match(line))
        and match.group(1) in volume_module_set
    ]
    if volume_modules and (
        lines.count(SYSTEM_VOLUME_BOOT_ENTRY) != 1
        or not volume_requires
        or not positions[-1]
        < lines.index(SYSTEM_VOLUME_BOOT_ENTRY)
        < volume_requires[0]
    ):
        raise RuntimeError(
            "Rich Desktop boot progress expected the system volume mounted "
            "once, after its driver and before the modules it holds"
        )

    width = max(2, len(str(len(chunk_names))))
    output: list[str] = []
    chunk_number_by_line = {
        line: number
        for number, line in enumerate(chunk_lines, start=1)
    }
    for index, line in enumerate(lines):
        if line == userland_line:
            output.append(
                _rich_desktop_boot_line(
                    "loading networking and rich-terminal modules"
                )
            )
        if line in chunk_number_by_line:
            number = chunk_number_by_line[line]
            output.append(
                _rich_desktop_boot_line(
                    f"{chunk_label} source "
                    f"{number:0{width}d}/{len(chunk_names):0{width}d}"
                )
            )
        output.append(line)
        if line == rich_bounds_last_line:
            output.append(
                _rich_desktop_boot_line("system modules ready")
            )
        elif line == loader_line:
            output.append(
                _rich_desktop_boot_line("checked source loader ready")
            )
        elif line == chunk_lines[-1]:
            output.append(
                _rich_desktop_boot_line(f"{chunk_label} ready")
            )
        elif volume_modules and line == SYSTEM_VOLUME_BOOT_ENTRY:
            output.append(
                _rich_desktop_boot_line("system volume mounted")
            )
        elif volume_requires and index == volume_requires[-1]:
            output.append(
                _rich_desktop_boot_line("framework ready")
            )

    suffix = "\n" if autoexec.endswith("\n") else ""
    return "\n".join(output) + suffix


def _linked_chunks(
    modules: tuple[str, ...],
    maximum_bytes: int = LINK_CHUNK_BYTES,
    audited_maximum_line_bytes: int | None = None,
) -> dict[str, bytes]:
    """Pack ordered source units into loader-safe native Forth chunks.

    Oversized modules may cross chunk boundaries only while the interpreter
    is back at top level: never inside a colon definition or a conditional
    compilation region.  KDOS retains dictionary state between loads, so
    top-level data declarations remain contiguous without exposing a partial
    definition to the next chunk's ``REQUIRE`` line.

    Opt-in physical-line coalescing is applied only after those chunk
    boundaries are fixed.  The caller must have audited the complete closure
    for custom words that observe physical input-line boundaries.
    """
    chunks: list[bytearray] = []
    current = bytearray()
    for module in modules:
        source = _minify_forth(
            (SOURCE_ROOT / module).read_text(encoding="utf-8"),
            remove_requires=True,
        ).encode("utf-8")
        units: list[bytearray] = []
        unit = bytearray()
        definition_depth = 0
        conditional_depth = 0
        for line in source.splitlines(keepends=True):
            unit.extend(line)
            text = line.decode("utf-8").rstrip("\r\n")
            tokens = _forth_line_tokens(text)
            if tokens and (tokens[0] == ":" or tokens[0].upper() == ":NONAME"):
                definition_depth = 1
            if definition_depth and any(
                token == ";"
                and (index == 0 or tokens[index - 1].upper() not in {"CHAR", "[CHAR]"})
                for index, token in enumerate(tokens)
            ):
                definition_depth = 0
            for token in tokens:
                upper = token.upper()
                if upper == "[IF]":
                    conditional_depth += 1
                elif upper == "[THEN]" and conditional_depth:
                    conditional_depth -= 1
            if definition_depth == 0 and conditional_depth == 0:
                units.append(unit)
                unit = bytearray()
        if unit:
            raise RuntimeError(f"Linked module ends inside source unit: {module}")
        for source_unit in units:
            if len(source_unit) > maximum_bytes:
                raise RuntimeError(
                    f"Linked source unit exceeds {maximum_bytes} bytes: "
                    f"{module}"
                )
            if current and len(current) + len(source_unit) > maximum_bytes:
                chunks.append(current)
                current = bytearray()
            current.extend(source_unit)
    if current:
        chunks.append(current)
    linked_chunks: dict[str, bytes] = {}
    for index, content in enumerate(chunks):
        source = bytes(content)
        if audited_maximum_line_bytes is not None:
            source = _coalesce_audited_forth_lines(
                source,
                audited_maximum_line_bytes,
            )
        linked_chunks[f".akashic/link-{index:02d}.f"] = source
    return linked_chunks


def _cold_source_lzss_encode(source: bytes) -> bytes:
    """Encode one bounded source chunk with deterministic LZSS tokens.

    Control groups describe at most eight tokens, least-significant bit
    first.  A set bit is one literal.  A clear bit is a two-byte little-endian
    ``((distance - 1) << 4) | (length - 3)`` match with a 4 KiB window and a
    3..18 byte length.  Greedy longest-match selection prefers the nearest
    equal-length match and does not impose a candidate-count heuristic.
    """
    if not source:
        raise ValueError("Cold source chunks must not be empty")

    encoded = bytearray()
    cursor = 0
    while cursor < len(source):
        control_offset = len(encoded)
        encoded.append(0)
        control = 0
        for bit in range(8):
            if cursor == len(source):
                break

            best_length = 0
            best_distance = 0
            maximum_length = min(18, len(source) - cursor)
            if maximum_length >= 3:
                window_start = max(0, cursor - 4096)
                for distance in range(1, min(2, cursor) + 1):
                    length = 0
                    while (
                        length < maximum_length
                        and source[cursor + length - distance]
                        == source[cursor + length]
                    ):
                        length += 1
                    if length >= 3 and length > best_length:
                        best_length = length
                        best_distance = distance
                        if length == maximum_length:
                            break

                needle = source[cursor : cursor + 3]
                candidate = (
                    -1
                    if best_length == maximum_length
                    else source.rfind(needle, window_start, cursor)
                )
                while candidate >= window_start:
                    distance = cursor - candidate
                    length = 3
                    while (
                        length < maximum_length
                        and source[cursor + length - distance]
                        == source[cursor + length]
                    ):
                        length += 1
                    if length >= 3 and length > best_length:
                        best_length = length
                        best_distance = distance
                        if length == maximum_length:
                            break
                    candidate = source.rfind(
                        needle, window_start, candidate
                    )

            if best_length >= 3:
                code = ((best_distance - 1) << 4) | (best_length - 3)
                encoded.extend(struct.pack("<H", code))
                cursor += best_length
            else:
                control |= 1 << bit
                encoded.append(source[cursor])
                cursor += 1
        encoded[control_offset] = control
    return bytes(encoded)


def _cold_source_lzss_decode(payload: bytes, raw_bytes: int) -> bytes:
    """Host-side exact decoder used to validate every generated payload."""
    if raw_bytes <= 0:
        raise ValueError("Cold source raw size must be positive")

    decoded = bytearray()
    cursor = 0
    while len(decoded) < raw_bytes:
        if cursor >= len(payload):
            raise ValueError("Truncated cold source control group")
        control = payload[cursor]
        cursor += 1
        for _ in range(8):
            if len(decoded) == raw_bytes:
                if control:
                    raise ValueError("Non-canonical cold source control bits")
                if cursor != len(payload):
                    raise ValueError("Trailing cold source payload")
                return bytes(decoded)

            if control & 1:
                if cursor >= len(payload):
                    raise ValueError("Truncated cold source literal")
                decoded.append(payload[cursor])
                cursor += 1
            else:
                if cursor + 2 > len(payload):
                    raise ValueError("Truncated cold source match")
                code = payload[cursor] | (payload[cursor + 1] << 8)
                cursor += 2
                distance = (code >> 4) + 1
                length = (code & 0x0F) + 3
                if distance > 4096 or distance > len(decoded):
                    raise ValueError("Invalid cold source match distance")
                if length > raw_bytes - len(decoded):
                    raise ValueError("Cold source match overruns output")
                for _ in range(length):
                    decoded.append(decoded[-distance])
            control >>= 1

    if cursor != len(payload):
        raise ValueError("Trailing cold source payload")
    return bytes(decoded)


def _pack_cold_source(
    source: bytes,
    maximum_raw_bytes: int = COLD_SOURCE_RAW_MAX_BYTES,
    *,
    codec: int = COLD_SOURCE_CODEC_LZSS,
) -> bytes:
    """Wrap one linked source chunk in the checked AKSRC001 container."""
    if not 0 < len(source) <= maximum_raw_bytes:
        raise ValueError(
            "Cold source raw size must be between 1 and "
            f"{maximum_raw_bytes} bytes"
        )
    if isinstance(codec, bool):
        raise ValueError(f"Unsupported cold source codec: {codec}")
    if codec == COLD_SOURCE_CODEC_LZSS:
        payload = _cold_source_lzss_encode(source)
    elif codec == COLD_SOURCE_CODEC_STORED:
        payload = source
    else:
        raise ValueError(f"Unsupported cold source codec: {codec}")
    header = COLD_SOURCE_HEADER.pack(
        COLD_SOURCE_MAGIC,
        COLD_SOURCE_VERSION,
        codec,
        COLD_SOURCE_HEADER_BYTES,
        len(source),
        len(payload),
        zlib.crc32(source) & 0xFFFFFFFF,
        0,
    )
    packed = header + payload
    if _unpack_cold_source(packed, maximum_raw_bytes) != source:
        raise RuntimeError("Cold source packer failed its exact round trip")
    return packed


def _unpack_cold_source(
    packed: bytes,
    maximum_raw_bytes: int = COLD_SOURCE_RAW_MAX_BYTES,
) -> bytes:
    """Validate and expand one AKSRC001 container on the host."""
    if len(packed) < COLD_SOURCE_HEADER_BYTES:
        raise ValueError("Truncated cold source header")
    (
        magic,
        version,
        codec,
        header_bytes,
        raw_bytes,
        payload_bytes,
        raw_crc32,
        reserved,
    ) = COLD_SOURCE_HEADER.unpack_from(packed)
    if magic != COLD_SOURCE_MAGIC:
        raise ValueError("Invalid cold source magic")
    if version != COLD_SOURCE_VERSION:
        raise ValueError("Unsupported cold source version")
    if codec not in COLD_SOURCE_CODECS or reserved != 0:
        raise ValueError("Unsupported cold source codec or reserved flags")
    if header_bytes != COLD_SOURCE_HEADER_BYTES:
        raise ValueError("Invalid cold source header size")
    if not 0 < raw_bytes <= maximum_raw_bytes:
        raise ValueError("Invalid cold source raw size")
    if payload_bytes <= 0 or payload_bytes != len(packed) - header_bytes:
        raise ValueError("Invalid cold source payload size")
    payload = packed[header_bytes:]
    if codec == COLD_SOURCE_CODEC_LZSS:
        maximum_payload_bytes = raw_bytes + (raw_bytes + 7) // 8
        if payload_bytes > maximum_payload_bytes:
            raise ValueError("Invalid compressed cold source payload size")
        source = _cold_source_lzss_decode(payload, raw_bytes)
    else:
        if payload_bytes != raw_bytes:
            raise ValueError("Stored cold source payload size mismatch")
        source = payload
    if zlib.crc32(source) & 0xFFFFFFFF != raw_crc32:
        raise ValueError("Cold source CRC mismatch")
    return source


def _container_linked_chunks(
    linked_chunks: dict[str, bytes],
    maximum_raw_bytes: int = COLD_SOURCE_RAW_MAX_BYTES,
    *,
    codec: int,
) -> dict[str, bytes]:
    """Replace linked source files with checked root-level containers."""
    return {
        COLD_SOURCE_CHUNK_TEMPLATE.format(index=index): _pack_cold_source(
            source, maximum_raw_bytes, codec=codec
        )
        for index, source in enumerate(linked_chunks.values())
    }


def _linked_autoexec(
    autoexec: str,
    chunk_names: tuple[str, ...],
    modules: tuple[str, ...],
    *,
    cold_source_codec: int | None = None,
    system_volume: bool = False,
    module_tokens: bool = False,
) -> str:
    """Replace linked source REQUIREs while retaining injected test leaves.

    With SYSTEM_VOLUME the chunks hold only what mounts the system volume,
    and MODULES are files on it.  Their REQUIREs then stay, after the chunks
    and the lines that mount the volume and select it as the module source.
    A profile that is not linked has no chunks: the mounting module is a
    file on the boot volume, and its REQUIRE takes their place.
    """
    load_lines = [f"REQUIRE {name}" for name in chunk_names]
    if cold_source_codec is not None:
        load_lines = [
            f"REQUIRE {COLD_SOURCE_LOADER_PATH}",
            "VARIABLE _BOOT-COLD-SOURCE-STATUS",
            # A chunk that cannot be loaded ends the boot, named, and
            # nothing is loaded in its place.
            ': _BOOT-COLD-SOURCE  ( "filename" -- )',
            "    COLD-SOURCE-LOAD DUP _BOOT-COLD-SOURCE-STATUS ! ?DUP IF",
            '        ." COLD SOURCE LOAD FAIL status=" .',
            '        ." eval=" CSL-LAST-EVAL@ .',
            '        ." line=" EVAL-LINE @ .',
            '        ." column=" EVAL-COLUMN @ .',
            '        ." throw=" CSL-LAST-THROW@ .',
            '        ." token=" EVAL-TOKEN TYPE',
            '        ."  file=" CSL-LAST-NAME TYPE CR TX-FLUSH ABORT',
            "    THEN ;",
        ] + [
            (
                f"_BOOT-COLD-SOURCE {name}"
            )
            for name in chunk_names
        ]
    if system_volume:
        if not chunk_names:
            load_lines = [f"REQUIRE {SYSTEM_VOLUME_MODULE}"]
        load_lines.extend(SYSTEM_VOLUME_BOOT_LINES)
        if module_tokens:
            # The volume's modules have their token forms beside them.
            load_lines.append(MODULE_TOKENS_BOOT_LINE)
    lines: list[str] = []
    inserted = False
    linked_modules = set(modules)
    for line in autoexec.splitlines():
        match = REQUIRE_RE.match(line)
        if match and match.group(1) in linked_modules:
            if not inserted:
                lines.extend(load_lines)
                inserted = True
            if not system_volume:
                continue
        lines.append(line)
    if not inserted:
        if cold_source_codec is not None or system_volume:
            raise RuntimeError(
                "Profile autoexec has no linked REQUIRE insertion point"
                if system_volume
                else "Cold source profile autoexec has no linked REQUIRE "
                "insertion point"
            )
        lines[0:0] = load_lines
    if system_volume and not chunk_names:
        # A profile that is not linked keeps its autoexec as it wrote it.
        return "\n".join(lines) + "\n"
    linked_autoexec = _minify_forth("\n".join(lines) + "\n")
    if cold_source_codec is not None:
        enter = linked_autoexec.find("ENTER-USERLAND")
        loader = linked_autoexec.find(f"REQUIRE {COLD_SOURCE_LOADER_PATH}")
        if enter < 0 or loader < enter:
            raise RuntimeError(
                "Cold source loader must run after ENTER-USERLAND"
            )
    return linked_autoexec


def _directories(paths: set[str]) -> list[str]:
    directories: set[str] = set()
    for path in paths:
        parts = PurePosixPath(path).parts[:-1]
        for depth in range(1, len(parts) + 1):
            directories.add("/".join(parts[:depth]))
    return sorted(directories, key=lambda value: (value.count("/"), value))


def _validate_image_paths(
    paths: set[str],
    directories: list[str],
    *,
    include_networking: bool = False,
    external_system_files: frozenset[str] = frozenset(),
    sample_names: frozenset[str],
):
    system_files = set(external_system_files)
    if include_networking:
        system_files.add("networking.f")
    system_aliases = paths & system_files
    if system_aliases:
        raise RuntimeError(
            "Profile files collide with separately injected system modules: "
            + ", ".join(sorted(system_aliases))
        )
    all_paths = paths | system_files
    file_directory_aliases = all_paths & set(directories)
    if file_directory_aliases:
        raise RuntimeError(
            "Image paths collide as both files and directories: "
            + ", ".join(sorted(file_directory_aliases))
        )
    # Include kdos/autoexec and two temporary fragmentation fixtures.  The
    # separately injected system modules participate as ordinary file entries.
    entries = (
        len(all_paths)
        + len(directories)
        + len(sample_names)
        + 4
    )
    if entries > MAX_FILES:
        raise RuntimeError(
            f"Profile needs {entries} MP64FS entries; filesystem limit is "
            f"{MAX_FILES}."
        )
    for path in all_paths | set(directories) | set(sample_names):
        name = PurePosixPath(path).name
        if len(name.encode("utf-8")) > MAX_NAME_LEN:
            raise RuntimeError(
                f"MP64FS name is too long ({len(name)} > {MAX_NAME_LEN}): {path}"
            )


def _validate_module_ids(
    modules: tuple[str, ...],
    initial_files: tuple[tuple[str, bytes], ...] = (),
):
    """Reject PROVIDED names that alias in KDOS's bounded module table.

    Injected Forth leaves participate in the same runtime module table as the
    linked Akashic closure, so validating only ``SOURCE_ROOT`` modules would
    miss collisions that make a later REQUIRE silently skip its fixture.
    """
    keys: dict[bytes, tuple[str, str]] = {}
    sources = [
        (
            module,
            (SOURCE_ROOT / module).read_text(encoding="utf-8"),
        )
        for module in modules
    ]
    sources.extend(
        (path, content.decode("utf-8"))
        for path, content in initial_files
        if path.lower().endswith((".f", ".f.src"))
    )
    for source_path, text in sources:
        for match in PROVIDED_RE.finditer(text):
            module_id = match.group(1)
            key = module_key(module_id)
            previous = keys.get(key)
            identity = (source_path, module_id)
            if previous and previous != identity:
                other_path, other_id = previous
                raise RuntimeError(
                    "KDOS PROVIDED key collision: "
                    f"{other_id!r} ({other_path}) and "
                    f"{module_id!r} ({source_path})"
                )
            keys[key] = identity


def _machine_backend(backend: str) -> str:
    """Validate one explicit execution backend name."""

    if not isinstance(backend, str):
        raise TypeError("backend must be a string")
    if backend not in MACHINE_BACKENDS:
        raise ValueError(
            "backend must be one of " + ", ".join(MACHINE_BACKENDS)
        )
    return backend


def _simulator_session_autoexec(autoexec: str, session_entry: str) -> str:
    """Defer only the final ordinary session invocation to the simulator.

    The simulator defines ``_SIMULATOR-SESSION-ENTRY`` before evaluating this
    file.  Everything before the last line remains byte-identical, so source
    loading, app construction, descriptors, and boot diagnostics stay shared
    with the emulator image.
    """

    if not isinstance(autoexec, str):
        raise TypeError("autoexec must be a string")
    if (
        not isinstance(session_entry, str)
        or not session_entry
        or any(character.isspace() for character in session_entry)
    ):
        raise ValueError("session_entry must be one nonempty Forth token")
    lines = autoexec.splitlines(keepends=True)
    invocations = [
        index
        for index, line in enumerate(lines)
        if line.strip() == session_entry
    ]
    nonempty = [index for index, line in enumerate(lines) if line.strip()]
    if not nonempty or invocations != nonempty[-1:]:
        raise RuntimeError(
            "semantic session entry must be the one final autoexec invocation"
        )
    index = invocations[0]
    ending = "\n" if lines[index].endswith("\n") else ""
    lines[index] = (
        f"' {session_entry} IS _SIMULATOR-SESSION-ENTRY{ending}"
    )
    return "".join(lines)


def settings_image_path(image_path: Path) -> Path:
    """The settings disk's image built beside the system disk's IMAGE_PATH."""

    return image_path.with_name(f"{image_path.stem}-settings{image_path.suffix}")


def _settings_image_for(profile: ImageSpec, image_path: Path) -> Path | None:
    """The settings image a launch of PROFILE's IMAGE_PATH attaches, or None
    for a profile with no system settings."""

    return settings_image_path(image_path) if profile.settings_files else None


# A settings file's table header and a key's line: indentation, key, the
# equals sign, the value, and any comment after it.
_SETTINGS_TABLE = re.compile(r"^\s*\[([^\[\]]+)\]\s*(?:#.*)?$")
_SETTINGS_KEY = re.compile(
    r"^(?P<lead>\s*)(?P<key>[A-Za-z0-9_-]+)(?P<equals>\s*=\s*)"
    r"(?P<value>[^#]*?)(?P<tail>\s*(?:#.*)?)$"
)


def _toml_value(value: object) -> str:
    """VALUE written as TOML: a boolean, a whole number or a string."""

    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    raise TypeError(f"a setting is a boolean, a whole number or a string, not {value!r}")


def with_settings_values(text: str, values: Mapping[str, Mapping[str, object]]) -> str:
    """TEXT, a settings file, with VALUES, {table: {key: value}}, in place of
    the values its keys hold.  Comments and layout stay as the file has
    them.  Every table and key named must be in TEXT, each once."""

    pending = {table: dict(keys) for table, keys in values.items()}
    lines = []
    table = None
    for line in text.splitlines(keepends=True):
        body = line.rstrip("\n")
        header = _SETTINGS_TABLE.match(body)
        if header:
            table = header.group(1).strip()
        elif table in pending:
            setting = _SETTINGS_KEY.match(body)
            if setting and setting.group("key") in pending[table]:
                value = _toml_value(pending[table].pop(setting.group("key")))
                line = (
                    setting.group("lead") + setting.group("key") + setting.group("equals")
                    + value + setting.group("tail") + line[len(body):]
                )
        lines.append(line)
    missing = [f"{table}.{key}" for table, keys in pending.items() for key in keys]
    if missing:
        raise ValueError("the settings file holds no " + ", ".join(sorted(missing)))
    return "".join(lines)


def _build_settings_image(
    profile: ImageSpec,
    target: Path,
    *,
    values: Mapping[str, Mapping[str, Mapping[str, object]]],
) -> Path:
    """Write PROFILE's settings disk beside TARGET: its system settings
    files on an MP64FS volume, each with the values VALUES gives it by its
    path, {path: {table: {key: value}}}, in place of its own."""

    fs = MP64FS(total_sectors=SETTINGS_DISK_SECTORS)
    fs.format()
    for relative in profile.settings_files:
        text = (AKASHIC_ROOT / "akashic" / relative).read_text(encoding="utf-8")
        if relative in values:
            text = with_settings_values(text, values[relative])
        fs.inject_file(Path(relative).name, text.encode("utf-8"), ftype=FTYPE_TEXT)
    settings = settings_image_path(target)
    fs.save(_private_file(settings))
    return settings


def system_image_path(image_path: Path) -> Path:
    """The system volume's image built beside the boot disk's IMAGE_PATH."""

    return image_path.with_name(f"{image_path.stem}-system{image_path.suffix}")


def _system_image_for(image_path: Path) -> Path | None:
    """The system volume a launch of IMAGE_PATH attaches as the third
    storage unit, or None.  A --system-volume build writes it beside the boot
    image and a build without the option removes it, so its presence is what
    the last build of IMAGE_PATH chose."""

    system = system_image_path(image_path)
    return system if system.is_file() else None


def user_image_path(image_path: Path) -> Path:
    """The user volume's image built beside the boot disk's IMAGE_PATH."""

    return image_path.with_name(f"{image_path.stem}-user{image_path.suffix}")


def _user_image_for(image_path: Path) -> Path | None:
    """The user volume a launch of IMAGE_PATH attaches as the fourth storage
    unit, or None.  A --user-volume build writes it beside the boot image and
    a build without the option removes it, so its presence is what the last
    build of IMAGE_PATH chose."""

    user = user_image_path(image_path)
    return user if user.is_file() else None


# The system volume's ext4 geometry.  The pinned profile fixes the rest
# (toolchain/image/ext4-profile/manifest.json): 256-byte inodes, a
# 4 MiB journal, the feature set the driver is qualified against, and one
# inode for every 16,384 bytes of a full block group, which the driver's
# admission requires of each group whatever the volume's size.
SYSTEM_VOLUME_BLOCK_BYTES = 4096
SYSTEM_VOLUME_LABEL = "AKASHIC-SYSTEM"
_SYSTEM_VOLUME_INODE_RATIO_BYTES = 16384
_SYSTEM_VOLUME_INODE_BYTES = 256
_SYSTEM_VOLUME_JOURNAL_BYTES = 4 << 20


def system_volume_geometry(
    file_sizes: tuple[int, ...], directories: int, block_bytes: int
) -> tuple[int, int, int]:
    """The bytes, block groups and inodes of a system volume that holds
    files of FILE_SIZES in DIRECTORIES directories, from its content alone.

    Each file takes its bytes rounded up to whole blocks and each directory
    one block.  The journal takes 4 MiB.  An eighth of that sum is added for
    the filesystem's own structures apart from its inode tables: the bitmaps,
    the group descriptors with their reserve, and the orphan file.  A block
    group spans eight times the block size in blocks, and each group carries
    an inode table for one inode per 16,384 bytes of a full group.  The
    volume has as many groups as its content and their inode tables fill and
    as give every file and directory an inode, with sixteen over for the
    reserved ones, and never fewer than two: the driver takes the backup
    superblock of the second group as its witness when it checks the
    journal.  Its size is rounded up to a whole MiB.
    """

    mib = 1 << 20
    group_bytes = 8 * block_bytes * block_bytes
    group_inodes = group_bytes // _SYSTEM_VOLUME_INODE_RATIO_BYTES
    table_bytes = group_inodes * _SYSTEM_VOLUME_INODE_BYTES
    data = sum(-(-size // block_bytes) for size in file_sizes) + directories
    content = data * block_bytes + _SYSTEM_VOLUME_JOURNAL_BYTES
    needed = content + content // 8
    groups = max(
        2,
        -(-needed // (group_bytes - table_bytes)),
        -(-(len(file_sizes) + directories + 16) // group_inodes),
    )
    # A volume reaches far enough into its last group for that group to
    # hold its own inode table.
    volume = max(
        needed + groups * table_bytes,
        (groups - 1) * group_bytes + table_bytes + mib,
    )
    return -(-volume // mib) * mib, groups, groups * group_inodes


# The e2fsprogs release that brought orphan_file, which the profile uses.
# This computer's own 1.47.0 builds the same system volume as the pinned
# 1.47.4.  Its user volume differs only in marking the block groups that hold
# superblock backups BLOCK_UNINIT, which the ext4 driver takes as it takes
# any uninitialized group.
E2FSPROGS_MINIMUM = (1, 47, 0)


# Where e2fsprogs lives on most systems, searched after the PATH, which an
# ordinary account's often leaves out.
HOST_TOOL_FOLDERS = ("/usr/sbin", "/sbin")


def _host_e2fsprogs(manifest: dict) -> Path:
    """The folder of this computer's own e2fsprogs tools."""

    from . import ext4 as ext4_profile

    required = manifest["authorities"]["e2fsprogs"]["required_tools"]
    # The first folder that holds every tool: another program's lone mke2fs,
    # such as Android's platform tools carry, comes first on some paths.
    folders = os.environ.get("PATH", "").split(os.pathsep) + list(HOST_TOOL_FOLDERS)
    for entry in folders:
        if entry and all(os.access(Path(entry) / tool, os.X_OK) for tool in required):
            return Path(entry).resolve()
    raise ext4_profile.ProfileError(
        "building ext4 volumes needs e2fsprogs "
        + ".".join(map(str, E2FSPROGS_MINIMUM))
        + " or later (" + ", ".join(required) + "), which this computer lacks"
    )


def _system_volume_toolchain() -> tuple[dict, dict[str, str], dict]:
    """The ext4 profile, its environment and the checked e2fsprogs a volume
    is built with: the pinned copy that AKASHIC_E2FSPROGS_TOOL_DIR names, as
    tests build with, or else this computer's own from E2FSPROGS_MINIMUM on.
    A build asks for them before it writes anything."""

    from . import ext4 as ext4_profile

    manifest_path = ext4_profile.DEFAULT_MANIFEST
    manifest = ext4_profile.load_manifest(manifest_path)
    configured = os.environ.get("AKASHIC_E2FSPROGS_TOOL_DIR")
    try:
        if configured:
            tool_dir, minimum = Path(configured).resolve(), None
        else:
            tool_dir, minimum = _host_e2fsprogs(manifest), E2FSPROGS_MINIMUM
        env = ext4_profile.pinned_environment(manifest, tool_dir, manifest_path)
        tools = ext4_profile.verify_toolchain(manifest, tool_dir, env, minimum=minimum)
    except ext4_profile.ProfileError as error:
        raise RuntimeError(str(error)) from error
    return manifest, env, tools


def _private_folder(path: Path) -> Path:
    """PATH as a folder, each folder the build creates on the way open to
    the user's own account alone.  A folder that is already there keeps its
    mode, since it is the user's."""

    missing = []
    folder = path
    while not folder.exists():
        missing.append(folder)
        folder = folder.parent
    for folder in reversed(missing):
        folder.mkdir(mode=0o700, exist_ok=True)
        os.chmod(folder, 0o700)
    return path


def _private_file(path: Path) -> Path:
    """PATH as a file only the user's own account can read or write, made
    empty when missing.  A file written over afterwards keeps that mode."""

    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT, 0o600)
    try:
        os.fchmod(descriptor, 0o600)
    finally:
        os.close(descriptor)
    return path


def _write_ext4_image(
    target: Path,
    spec: dict,
    inodes: int,
    volume_bytes: int,
    toolchain: tuple[dict, dict[str, str], dict],
    *,
    directories: list[str],
    source_paths: tuple[str, ...],
    staged: dict[str, bytes],
    what: str,
) -> None:
    """Write an ext4 image of VOLUME_BYTES to TARGET from SPEC, the
    geometry and identity of one of the ext4 profile's images, with INODES
    inodes: DIRECTORIES made, each of SOURCE_PATHS written at its path from
    the source root, each of STAGED written from its bytes, every file with
    the same permission bits.  The host's e2fsck then checks it and the
    driver's admission facts are checked against its superblock.  WHAT names
    the volume in an error.

    TOOLCHAIN (:func:`_system_volume_toolchain`) makes it, with the
    arguments, feature set and fixed time of the ext4 fixtures' profile.
    """

    from . import ext4 as ext4_profile

    manifest, env, tools = toolchain
    context = dict(spec)
    context.update(
        tool_dir=Path(tools["mke2fs"]["path"]).parent,
        image=target,
        feature_names=",".join(ext4_profile.profile_feature_names(manifest, spec)),
    )

    def run(
        argv: list[str], step: str, cwd: Path | None = None
    ) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            argv, env=env, cwd=cwd, text=True, capture_output=True, check=False
        )
        if result.returncode != 0:
            raise RuntimeError(
                f"{step} failed for {what} {target}:\n"
                + result.stdout
                + result.stderr
            )
        return result

    _private_folder(target.parent)
    with _private_file(target).open("r+b") as image:
        image.truncate(0)
        image.truncate(volume_bytes)
    # The profile's arguments end with the image and its block count.  The
    # inode count goes before them: mke2fs would otherwise scale a group's
    # inodes down with a volume smaller than one group.
    mkfs_argv = ext4_profile.render_argv(manifest["generator"]["mkfs_argv"], context)
    run([*mkfs_argv[:-2], "-N", str(inodes), *mkfs_argv[-2:]], "mke2fs")
    # debugfs splits a command on spaces, so it runs in the source root and
    # takes each source file by its path from there.  It gives a written
    # file its host file's permission bits, which follow the checkout; every
    # file is set to the same ones.
    commands = [f"mkdir /{directory}" for directory in directories]
    for path in (*source_paths, *staged):
        if any(character.isspace() for character in path):
            raise RuntimeError(f"path holds white space: {path!r}")
    for path in source_paths:
        commands.append(f"write {path} /{path}")
        commands.append(f"sif /{path} mode 0100644")
    with tempfile.TemporaryDirectory(prefix="akashic-ext4-volume-") as scratch:
        for number, (path, content) in enumerate(staged.items()):
            if any(character.isspace() for character in scratch):
                raise RuntimeError(f"scratch path holds white space: {scratch!r}")
            staged_file = Path(scratch) / f"{number}.ft"
            staged_file.write_bytes(content)
            commands.append(f"write {staged_file} /{path}")
            commands.append(f"sif /{path} mode 0100644")
        script = Path(scratch) / "populate.debugfs"
        script.write_text("\n".join(commands) + "\n", encoding="utf-8")
        populated = run(
            [tools["debugfs"]["path"], "-w", "-f", str(script), str(target)],
            "debugfs",
            SOURCE_ROOT,
        )
    # debugfs reports a command that failed on stderr and still exits zero.
    complaints = [
        line
        for line in populated.stderr.splitlines()
        if line.strip() and not line.startswith("debugfs ")
    ]
    if complaints:
        raise RuntimeError(
            f"debugfs could not populate {what} {target}:\n"
            + "\n".join(complaints[:20])
        )
    run([tools["e2fsck"]["path"], "-f", "-n", str(target)], "e2fsck")
    # The facts the driver's admission checks, as the fixtures are checked.
    try:
        ext4_profile.validate_observed_superblock(
            manifest, spec, ext4_profile.read_superblock(target)
        )
    except ext4_profile.ProfileError as error:
        raise RuntimeError(str(error)) from error


def _build_system_image(
    modules: tuple[str, ...],
    target: Path,
    toolchain: tuple[dict, dict[str, str], dict],
    *,
    block_bytes: int = SYSTEM_VOLUME_BLOCK_BYTES,
    token_files: dict[str, bytes] | None = None,
    boot_id: int = 0,
    keep_source: bool = False,
    loaded_before: frozenset[str] = frozenset(),
    extra_sources: tuple[str, ...] = (),
    extra_files: dict[str, bytes] | None = None,
) -> dict[str, object]:
    """Write the system volume to TARGET: an ext4 image that holds each of
    MODULES as a plain file at its module path, the repository's text
    unchanged.  EXTRA_SOURCES are other files of the source root it holds
    at their paths, such as a profile's resources when the volume is its
    origin, and EXTRA_FILES files it holds by path with their bytes, such
    as the profile's initial files then.

    With TOKEN_FILES the volume holds each module's token form instead, at
    the module's path with a t added, built for the system whose BOOT-ID is
    BOOT_ID, and no source.  A module of LOADED_BEFORE,
    which the boot loads before it mounts the volume, has no token form of
    its own; a file that only names its module stands at its path, so that
    a REQUIRE of that path finds the module loaded.  Any other module
    without a token form is absent.  KEEP_SOURCE writes every module's
    source as well, beside its token form: the volume of a system that
    edits its own modules, on which KDOS checks each token file against its
    source and loads the source of a module that was edited.

    TOOLCHAIN (:func:`_system_volume_toolchain`) makes it, with the
    arguments, feature set and fixed time of the ext4 fixtures' profile.  The
    volume's identity follows from its content, so the same modules give the
    same image.  Returns facts about the volume for the build's report.
    """

    from . import ext4 as ext4_profile

    manifest, env, tools = toolchain
    if block_bytes not in manifest["platform_bounds"]["filesystem_block_bytes"]:
        raise ValueError(f"the ext4 profile has no {block_bytes}-byte blocks")

    from shared.token_form import pack_module_name_file

    texts = {module: (SOURCE_ROOT / module).read_bytes() for module in modules}
    # Each module's token form, or the file that names a module loaded
    # before the volume is mounted.  Both stand at the module's path with a
    # t added.
    token_forms: dict[str, bytes] = {}
    name_files: dict[str, bytes] = {}
    absent: list[str] = []
    if token_files:
        for module, text in texts.items():
            form = _token_form(text, token_files, boot_id, source_beside=keep_source)
            if form is not None:
                token_forms[module] = form
            elif keep_source:
                continue
            elif module in loaded_before and (
                provided := PROVIDED_RE.search(text.decode("utf-8", "replace"))
            ):
                name_files[module] = pack_module_name_file(
                    provided.group(1).encode("utf-8")
                )
            else:
                absent.append(module)
    source_modules = modules if not token_files or keep_source else ()
    extra_files = dict(extra_files or {})
    held = {
        **{module: texts[module] for module in source_modules},
        **{path: (SOURCE_ROOT / path).read_bytes() for path in extra_sources},
        **extra_files,
        **{
            module + TOKEN_FORM_SUFFIX: form
            for module, form in (token_forms | name_files).items()
        },
    }
    taken = set(extra_files) & {*source_modules, *extra_sources}
    if taken:
        raise RuntimeError(
            "Initial files take paths of the system volume's modules or "
            "resources: " + ", ".join(sorted(taken))
        )
    sizes = tuple(map(len, held.values()))
    directories = _directories(set(held))
    identity = hashlib.sha256(f"{block_bytes}\n".encode())
    for path, content in held.items():
        identity.update(
            f"{path}\0{hashlib.sha256(content).hexdigest()}\n".encode()
        )
    digest = identity.digest()
    volume_bytes, groups, inodes = system_volume_geometry(
        sizes, len(directories), block_bytes
    )
    spec = {
        "id": "system volume",
        "profile": "primary",
        "block_size": block_bytes,
        "inode_size": manifest["profiles"]["primary"]["inode_size"],
        "blocks_per_group": 8 * block_bytes,
        "block_count": volume_bytes // block_bytes,
        "expected_groups": groups,
        "expected_inodes": inodes,
        "uuid": str(uuid.UUID(bytes=digest[:16], version=4)),
        "hash_seed": str(uuid.UUID(bytes=digest[16:], version=4)),
        "label": SYSTEM_VOLUME_LABEL,
    }
    _write_ext4_image(
        target,
        spec,
        inodes,
        volume_bytes,
        toolchain,
        directories=directories,
        source_paths=(*source_modules, *extra_sources),
        staged={
            **extra_files,
            **{
                module + TOKEN_FORM_SUFFIX: form
                for module, form in (token_forms | name_files).items()
            },
        },
        what="the system volume",
    )
    return {
        "path": target,
        "bytes": volume_bytes,
        "block_bytes": block_bytes,
        "files": len(held),
        "file_bytes": sum(sizes),
        "source_files": len(source_modules),
        "source_bytes": sum(len(texts[module]) for module in source_modules),
        "token_files": len(token_forms),
        "token_bytes": sum(map(len, token_forms.values())),
        "name_files": len(name_files),
        "absent": tuple(absent),
        "directories": len(directories),
        "uuid": spec["uuid"],
    }


def _build_user_image(
    target: Path,
    volume_bytes: int,
    toolchain: tuple[dict, dict[str, str], dict],
    *,
    documents: dict[str, bytes],
) -> dict[str, object]:
    """Write the user volume to TARGET: a fresh ext4 image of VOLUME_BYTES in
    the format the staged writer takes, 1 KiB blocks and 256-byte inodes with
    the ext4 profile's features, holding the folders the shipping form's
    places name and, in the documents folder, DOCUMENTS by name.

    Every block group carries one inode for each 16 KiB of a full group, as
    the driver's admission requires, and the volume has at least two groups,
    16 MiB: the driver takes the backup superblock of the second group as
    its witness when it checks the journal.  The volume's identity follows
    from its size and content.  Returns facts for the build's report.
    """

    block_bytes = USER_VOLUME_BLOCK_BYTES
    group_bytes = 8 * block_bytes * block_bytes
    if volume_bytes % (1 << 20) or volume_bytes < 2 * group_bytes:
        raise ValueError(
            f"a user volume is a whole number of MiB of at least "
            f"{2 * group_bytes >> 20} MiB, not {volume_bytes} bytes"
        )
    manifest, _env, _tools = toolchain
    block_count = volume_bytes // block_bytes
    groups = -(-block_count // (8 * block_bytes))
    inodes = groups * (group_bytes // _SYSTEM_VOLUME_INODE_RATIO_BYTES)
    folder = USER_VOLUME_DOCUMENTS[1].strip("/")
    staged = {f"{folder}/{name}": content for name, content in sorted(documents.items())}
    identity = hashlib.sha256(f"user\n{volume_bytes}\n".encode())
    for path, content in staged.items():
        identity.update(f"{path}\0{hashlib.sha256(content).hexdigest()}\n".encode())
    digest = identity.digest()
    spec = {
        "id": "user volume",
        "profile": "primary",
        "block_size": block_bytes,
        "inode_size": manifest["profiles"]["primary"]["inode_size"],
        "blocks_per_group": 8 * block_bytes,
        "block_count": block_count,
        "expected_groups": groups,
        "expected_inodes": inodes,
        "uuid": str(uuid.UUID(bytes=digest[:16], version=4)),
        "hash_seed": str(uuid.UUID(bytes=digest[16:], version=4)),
        "label": USER_VOLUME_LABEL,
    }
    _write_ext4_image(
        target,
        spec,
        inodes,
        volume_bytes,
        toolchain,
        directories=[folder.strip("/") for folder in USER_VOLUME_FOLDERS],
        source_paths=(),
        staged=staged,
        what="the user volume",
    )
    return {
        "path": target,
        "bytes": volume_bytes,
        "groups": groups,
        "documents": len(staged),
        "uuid": spec["uuid"],
    }


# A module's token form stands on a volume at the module's path with a t
# added: utils/string.f, utils/string.ft.  KDOS reads it in the module's
# place once MODULE-TOKENS is set.
TOKEN_FORM_SUFFIX = "t"
MODULE_TOKENS_BOOT_LINE = "-1 MODULE-TOKENS !"
# The boot script stays source: it is the file a person edits to change
# what the machine loads.
TOKEN_FORM_SOURCE_ONLY = frozenset({"autoexec.f"})


def _token_form(
    content: bytes,
    token_files: dict[str, bytes] | None,
    boot_id: int,
    *,
    source_beside: bool = False,
) -> bytes | None:
    """The token form recorded for a source file with CONTENT, if any,
    built for the system whose BOOT-ID is BOOT_ID.  SOURCE_BESIDE says that
    the source ships beside it."""

    if not token_files:
        return None
    form = token_files.get(hashlib.sha256(content).hexdigest())
    if form is None:
        return None
    from shared.token_form import with_boot_id

    return with_boot_id(form, boot_id, source_beside=source_beside)


def _boot_in_simulator(image_path: Path, profile: ImageSpec, *, recorder=None):
    """Boot IMAGE_PATH in MegaPad's simulator, on the profile's full cores,
    until its boot script has run, and return the runtime.  RECORDER, a token
    recorder, is attached before KDOS loads.  A profile without a session
    entry, such as a contract profile, does its work in the boot script and
    binds no live entry.  A boot that fails raises, with the end of what the
    guest printed."""

    from shared.storage import STORAGE_UNIT_TABLE
    from simulator.image_bootstrap import prepare_image_bootstrap
    from simulator.platform import Topology, create_address_space
    from simulator.runtime import MegaForthRuntime
    from simulator.server import _CANONICAL_HBW_MIB
    from simulator.storage import HostedStorageService

    paths = (
        image_path,
        _settings_image_for(profile, image_path),
        _system_image_for(image_path),
        _user_image_for(image_path),
    )
    services = {
        unit.host_name: None
        if unit_path is None
        else HostedStorageService(
            image_path=unit_path, write_protected=unit.write_protected
        )
        for unit, unit_path in zip(STORAGE_UNIT_TABLE, paths, strict=True)
    }
    # The profile's machine: the simulator refuses a shape it cannot run.
    memory = create_address_space(
        topology=Topology(
            full_cores=profile.full_cores, clusters=profile.clusters,
        ),
        bank0_size=DEFAULT_RAM_KIB << 10,
        external_size=profile.default_ext_mem_mib << 20,
        vram_size=DEFAULT_VRAM_MIB << 20,
        hbw_size=_CANONICAL_HBW_MIB << 20,
        initial_epoch_ms=time.time_ns() // 1_000_000,
    )
    memory.mmio.rtc.bind_monotonic_clock(time.monotonic_ns)
    runtime = MegaForthRuntime(
        memory=memory, **services, execution_backend="native"
    )
    if recorder is not None:
        recorder.attach(runtime)
    try:
        prepare_image_bootstrap(
            memory=memory,
            **services,
            terminal_cols=RECORDING_COLS,
            terminal_rows=RECORDING_ROWS,
            runtime=runtime,
            session=profile.session_entry is not None,
        )
    except (KeyboardInterrupt, SystemExit):
        raise
    except BaseException as error:
        # A guest fault leaves the runtime as an exception of its own kind.
        raise RuntimeError(
            f"The boot of {image_path.name} in the simulator failed: "
            f"{type(error).__name__}: {str(error)[:600]}\n"
            + bytes(runtime.uart_output[-1200:]).decode("utf-8", "replace")
        ) from error
    return runtime


def _record_token_files(image_path: Path, profile: ImageSpec) -> dict[str, bytes]:
    """Boot IMAGE_PATH from source in MegaPad's simulator with its token
    recorder attached, and return each loaded source file's token form by
    the SHA-256 of its text.

    The record is made by the interpreter that loads the source, so the
    builder keeps no reader of Forth for it.  A file whose load cannot be
    replayed has no entry and stays source.
    """

    from shared.token_form import TokenFormError
    from simulator.token_recorder import TokenRecorder

    recorder = TokenRecorder()
    _boot_in_simulator(image_path, profile, recorder=recorder)
    token_files: dict[str, bytes] = {}
    for unit in recorder.units:
        try:
            token_files[unit.digest] = unit.token_file()
        except TokenFormError:
            continue
    return token_files


def session_manifest_path(image_path: Path) -> Path:
    """The session manifest written beside the boot disk's IMAGE_PATH."""

    return image_path.with_name(f"{image_path.stem}-session.json")


SESSION_MANIFEST_FORMAT = 1


def _write_session_manifest(
    spec: ImageSpec,
    target: Path,
    *,
    name: str,
    backend: str,
    settings: Path | None,
    system: bool,
    user: bool,
    built_from: Mapping[str, object] | None,
    facts: Mapping[str, object] | None = None,
) -> Path:
    """Write what a server needs to run TARGET's images: each storage unit's
    image by file name, the machine's memory and cores, the boot's backend,
    and the rich terminal's policies; BUILT_FROM, what the caller built them
    from, as given; and FACTS, the caller's further facts, such as the
    viewer's and the network's settings, which may not replace any of
    these."""

    rich = spec.rich_terminal
    manifest = {
        "format": SESSION_MANIFEST_FORMAT,
        "name": name,
        "backend": backend,
        "storage": {
            "boot": target.name,
            "settings": None if settings is None else settings.name,
            "system": system_image_path(target).name if system else None,
            "user": user_image_path(target).name if user else None,
        },
        "machine": {
            "ram_kib": DEFAULT_RAM_KIB,
            "ext_mem_mib": spec.default_ext_mem_mib,
            "vram_mib": DEFAULT_VRAM_MIB,
            "full_cores": spec.full_cores,
            "clusters": spec.clusters,
        },
        "rich_terminal": None if rich is None else {
            "policy": rich.host_policy.to_dict(),
            "retained_policy": (
                None if rich.retained_policy is None else rich.retained_policy.to_dict()
            ),
        },
        "built_from": None if built_from is None else dict(built_from),
    }
    taken = sorted(manifest.keys() & (facts or {}).keys())
    if taken:
        raise ValueError("session facts may not replace " + ", ".join(taken))
    manifest.update(facts or {})
    path = _private_file(session_manifest_path(target))
    path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return path


# What build() asks its caller for the files a person works with:
# SAMPLES_FOR(spec, modules, documents) returns the image's samples by name and
# the names of those that are data rather than text.  DOCUMENTS says the build
# keeps its samples in a documents place rather than the boot volume's root.
Samples = Callable[
    [ImageSpec, tuple[str, ...], bool], tuple[dict[str, bytes], frozenset[str]]
]
# ADJUST_AUTOEXEC(autoexec, modules) returns the boot script with a caller's
# lines added once the image's modules are known, as a check turned on at boot.
Adjust = Callable[[str, tuple[str, ...]], str]


def build(
    spec: ImageSpec,
    target: Path,
    *,
    name: str,
    backend: str = "emulator",
    samples_for: Samples | None = None,
    adjust_autoexec: Adjust | None = None,
    settings_safe_mode: bool = False,
    settings_values: Mapping[str, Mapping[str, Mapping[str, object]]] | None = None,
    system_volume: bool = False,
    token_modules: bool = False,
    keep_module_source: bool = False,
    user_volume: bool = False,
    user_volume_mib: int = USER_VOLUME_DEFAULT_MIB,
    fresh_user_volume: bool = False,
    session_manifest: bool = False,
    built_from: Mapping[str, object] | None = None,
    session_facts: Mapping[str, object] | None = None,
) -> Path:
    """Build SPEC's boot image at TARGET and the images of its other disks
    beside it, for BACKEND.  NAME names the image in errors and the report.

    SAMPLES_FOR gives the files a person works with that the image carries
    (Samples), and ADJUST_AUTOEXEC adds a caller's lines to the boot script
    once the modules are known (Adjust).

    With SYSTEM_VOLUME the spec's Akashic modules are plain files on an
    ext4 system volume written beside the boot image
    (:func:`system_image_path`), and the boot image holds the closure of
    utils/fs/system-volume.f in their place, deployed as the spec deploys
    its source.  autoexec.f then mounts the volume and keeps the spec's
    REQUIREs, which KDOS resolves as paths on it.

    With TOKEN_MODULES the image is first built from source for the
    simulator and booted there once with MegaPad's token recorder attached.
    Every source file that boot loaded then goes into the image in its token
    form, in the source file's place: a linked chunk and a system module of
    the boot volume, and a module of the system volume, which then holds no
    source.  Each token file states the system this image boots, by the
    BOOT-ID that its BIOS gives once it has loaded the image's KDOS, and
    KDOS uses the file on that system only.  KEEP_MODULE_SOURCE writes the
    system volume's source as well, beside the token files: the volume of a
    system that edits its own modules, where KDOS loads the source of a
    token file whose source has changed.

    With USER_VOLUME the build writes the user volume beside the boot image
    (:func:`user_image_path`), a fresh ext4 image of USER_VOLUME_MIB MiB with
    the folders of the shipping form's places, and autoexec.f mounts it and
    declares those places in place of the one place over the boot volume:
    the origin, read-only over the root of the volume that holds the
    spec's shipped files, and documents and records on the user volume,
    records being the home.  With a system volume as well, the spec's
    resources and initial files move onto the system volume, the origin's
    volume.  Every sample, the large one included, moves into the user
    volume's documents, and the boot volume keeps none.  A user volume that
    is already there is kept as it is, documents and all, unless
    FRESH_USER_VOLUME asks for a new one; FRESH_USER_VOLUME also removes a
    user volume beside an image built without one.

    Every file the build writes can be read and written by the user's own
    account alone.  SESSION_MANIFEST writes beside the images what a server
    needs to run them (:func:`session_manifest_path`), with BUILT_FROM, what
    the caller built SPEC from, such as its components' commits and its
    configuration's digest, as given, and SESSION_FACTS, the caller's
    further facts.  The build runs no program to find them, since the
    caller knows them.  SETTINGS_VALUES gives values for the settings
    files, {path: {table: {key: value}}}, in place of the files' own
    (with_settings_values); SETTINGS_SAFE_MODE sets Desk's safe-mode to true.
    """
    if (built_from is not None or session_facts is not None) and not session_manifest:
        raise ValueError("built_from and session_facts go into the session manifest; ask for one")
    if keep_module_source and not (token_modules and system_volume):
        raise ValueError(
            "keeping module source beside token files needs a system volume "
            "of token modules"
        )
    token_files: dict[str, bytes] | None = None
    if token_modules:
        with tempfile.TemporaryDirectory(prefix="akashic-token-record-") as scratch:
            with contextlib.redirect_stdout(sys.stderr):
                recorded = build(
                    spec,
                    Path(scratch) / "source.img",
                    name=name,
                    backend="simulator",
                    samples_for=samples_for,
                    adjust_autoexec=adjust_autoexec,
                    settings_safe_mode=settings_safe_mode,
                    settings_values=settings_values,
                    system_volume=system_volume,
                    user_volume=user_volume,
                    user_volume_mib=user_volume_mib,
                )
            token_files = _record_token_files(recorded, spec)
        if not token_files:
            raise RuntimeError("The recording boot loaded no source file")
    # KDOS as the image holds it.  The BIOS loads it first, so it is part of
    # the identity of the system the image boots, which every token file's
    # header states.
    kdos_boot_file = _strip_forth_noncode_lines(
        (MEGAPAD_ROOT / "kdos.f").read_text(encoding="utf-8")
    ).encode("utf-8")
    boot_id = 0
    if token_files:
        from shared.boot_identity import boot_identity

        boot_id = boot_identity(kdos_boot_file)
    token_bytes = [0, 0, 0]  # files, source bytes, token bytes

    def tokens_for(name: str, content: bytes) -> bytes:
        """CONTENT, or its token form when the build has one."""

        form = (
            None
            if name in TOKEN_FORM_SOURCE_ONLY
            else _token_form(content, token_files, boot_id)
        )
        if form is None:
            return content
        token_bytes[0] += 1
        token_bytes[1] += len(content)
        token_bytes[2] += len(form)
        return form

    backend = _machine_backend(backend)
    if backend in SEMANTIC_BACKENDS and spec.session_entry is None:
        raise RuntimeError(f"{name!r} has no semantic session entry")
    profile = spec
    system_volume_toolchain = (
        _system_volume_toolchain() if system_volume or user_volume else None
    )
    if settings_safe_mode and DESK_SYSTEM_SETTINGS not in profile.settings_files:
        raise RuntimeError(
            "--settings-safe-mode needs a profile whose settings disk holds "
            f"{DESK_SYSTEM_SETTINGS}"
        )
    settings_by_file = {
        path: {table: dict(keys) for table, keys in tables.items()}
        for path, tables in (settings_values or {}).items()
    }
    outside = sorted(settings_by_file.keys() - set(profile.settings_files))
    if outside:
        raise RuntimeError(
            "settings values for files the settings disk does not hold: "
            + ", ".join(outside)
        )
    if settings_safe_mode:
        settings_by_file.setdefault(DESK_SYSTEM_SETTINGS, {}).setdefault(
            "desk.rich-terminal", {}
        )["safe-mode"] = True
    autoexec = profile.autoexec
    profile_modules = (
        dependency_order(profile.roots)
        if profile.linked
        else dependency_closure(profile.roots)
    )
    uses_app_shell = APP_SHELL_MODULE in profile_modules
    composition_roots = profile.roots
    if user_volume and not uses_app_shell:
        raise RuntimeError("--user-volume needs a profile that composes the app shell")
    if uses_app_shell:
        platform_roots = (MP64FS_VFS_PLATFORM_MODULE,)
        if user_volume:
            platform_roots += (USER_VOLUME_MODULE,)
        composition_roots = platform_roots + tuple(
            root
            for root in profile.roots
            if _normalize_module(root) not in platform_roots
        )
        autoexec = _with_mp64fs_vfs_platform(
            autoexec,
            _user_volume_boot_lines(system_volume)
            if user_volume
            else PLACES_BOOT_LINES,
        )
        if user_volume:
            autoexec = _with_practice_home_guard(autoexec)
    modules = (
        dependency_order(composition_roots)
        if profile.linked
        else dependency_closure(composition_roots)
    )
    akashic_modules = modules
    # What the boot volume deploys: the profile's modules, or what mounts
    # the system volume that holds them.
    deployed_modules = akashic_modules
    if system_volume:
        deployed_modules = (
            dependency_order((SYSTEM_VOLUME_MODULE,))
            if profile.linked
            else dependency_closure((SYSTEM_VOLUME_MODULE,))
        )
    if adjust_autoexec is not None:
        autoexec = adjust_autoexec(autoexec, modules)
    samples, data_samples = (
        samples_for(profile, modules, system_volume or user_volume)
        if samples_for is not None
        else ({}, frozenset())
    )
    # With the user volume the samples are documents there, and the boot
    # volume holds none of them: not the large sample either, whose growth
    # check is one of the boot volume's own (Profile.include_large_sample).
    user_documents = samples if user_volume else {}
    if user_volume:
        samples = {}
    large_sample = profile.include_large_sample and not user_volume
    requires_networking = (
        profile.megapad_networking or _requires_megapad_networking(modules)
    )
    requires_rich_terminal = _requires_megapad_rich_terminal(modules)
    if requires_rich_terminal != (profile.rich_terminal is not None):
        raise RuntimeError(
            "Rich-terminal module closure and profile-owned host bounds must "
            "be enabled together"
        )
    resources = set(profile.resources)
    resources.update(
        path for module in modules for path in MODULE_DATA_FILES.get(module, ())
    )
    # With both volumes the origin is the system volume, which then holds
    # the profile's resources and initial files in the boot volume's place.
    origin_resources: tuple[str, ...] = ()
    origin_files: dict[str, bytes] = {}
    initial_files = profile.initial_files
    if user_volume and system_volume:
        origin_resources = tuple(sorted(resources))
        resources = set()
        origin_files = dict(initial_files)
        initial_files = ()
    linked_chunks = (
        _linked_chunks(
            deployed_modules,
            profile.link_chunk_bytes,
            profile.audited_link_line_bytes,
        )
        if profile.linked
        else {}
    )
    deployed_chunks = linked_chunks
    generated_files: dict[str, bytes] = (
        {
            name: tokens_for(name, source)
            for name, source in linked_chunks.items()
        }
        if profile.cold_source_codec is None
        else {}
    )
    generated_validation_files: tuple[tuple[str, bytes], ...] = ()
    cold_source_initial_files: dict[str, bytes] = {}
    cold_source_raw_bytes = 0
    cold_source_container_bytes = 0
    if profile.cold_source_codec is not None:
        if not profile.linked:
            raise RuntimeError(
                "Checked cold source requires a linked profile"
            )
        if profile.link_chunk_bytes > COLD_SOURCE_RAW_MAX_BYTES:
            raise RuntimeError(
                "Cold source chunk limit exceeds the audited guest decoder "
                f"bound of {COLD_SOURCE_RAW_MAX_BYTES} bytes"
            )
        deployed_chunks = {
            COLD_SOURCE_CHUNK_TEMPLATE.format(index=index): (
                _pack_cold_source(
                    source, COLD_SOURCE_RAW_MAX_BYTES,
                    codec=profile.cold_source_codec,
                )
                if (form := tokens_for(name, source)) is source
                # A token form is binary already; it is stored as it is.
                else _pack_cold_source(
                    form, COLD_SOURCE_RAW_MAX_BYTES,
                    codec=COLD_SOURCE_CODEC_STORED,
                )
            )
            for index, (name, source) in enumerate(linked_chunks.items())
        }
        cold_source_raw_bytes = sum(map(len, linked_chunks.values()))
        cold_source_container_bytes = sum(map(len, deployed_chunks.values()))
        loader_source = (
            AKASHIC_ROOT / "local_testing" / "cold-source-loader.f"
        )
        if not loader_source.is_file():
            raise FileNotFoundError(
                f"Missing cold source loader: {loader_source}"
            )
        generated_files = dict(deployed_chunks)
        loader_content = loader_source.read_bytes()
        generated_files[COLD_SOURCE_LOADER_PATH] = tokens_for(
            COLD_SOURCE_LOADER_PATH, loader_content
        )
        generated_validation_files = (
            (COLD_SOURCE_LOADER_PATH, loader_content),
        )
    if profile.cold_source_initial_files:
        if profile.cold_source_codec is None:
            raise RuntimeError(
                "Checked cold-source leaves require a cold source codec"
            )
        for path, source in profile.cold_source_initial_files:
            if not path.endswith(".f.src"):
                raise RuntimeError(
                    "Checked cold-source leaf names must end in .f.src: "
                    f"{path}"
                )
            if path in cold_source_initial_files:
                raise RuntimeError(
                    f"Duplicate checked cold-source leaf path: {path}"
                )
            cold_source_initial_files[path] = _pack_cold_source(
                source,
                COLD_SOURCE_RAW_MAX_BYTES,
                codec=profile.cold_source_codec,
            )
        cold_source_raw_bytes += sum(
            len(source) for _, source in profile.cold_source_initial_files
        )
        cold_source_container_bytes += sum(
            map(len, cold_source_initial_files.values())
        )
    if profile.linked or system_volume:
        autoexec = _linked_autoexec(
            autoexec,
            tuple(deployed_chunks),
            akashic_modules,
            cold_source_codec=profile.cold_source_codec,
            system_volume=system_volume,
            module_tokens=bool(token_files) and system_volume,
        )
    autoexec = _with_userland_xmem_reserve(
        autoexec, profile.general_xmem_reserve_bytes,
    )
    if requires_networking:
        autoexec = _with_megapad_networking(autoexec)
    if requires_rich_terminal:
        autoexec = _with_megapad_rich_terminal(
            autoexec, profile.rich_terminal
        )
        if profile.rich_boot_progress:
            autoexec = _with_rich_desktop_boot_progress(
                autoexec,
                profile.rich_terminal,
                tuple(deployed_chunks),
                volume_modules=akashic_modules if system_volume else (),
            )
    elif profile.rich_boot_progress:
        raise RuntimeError(
            "Rich boot progress requires a rich-terminal profile"
        )
    if backend in SEMANTIC_BACKENDS:
        assert profile.session_entry is not None
        autoexec = _simulator_session_autoexec(
            autoexec, profile.session_entry
        )
    paths = (
        set(generated_files) | resources
        if profile.linked
        else set(deployed_modules) | resources
    )
    regular_initial_paths = {path for path, _ in initial_files}
    cold_initial_paths = set(cold_source_initial_files)
    initial_aliases = regular_initial_paths & cold_initial_paths
    if initial_aliases:
        raise RuntimeError(
            "Regular and checked cold-source leaves collide: "
            + ", ".join(sorted(initial_aliases))
        )
    initial_paths = regular_initial_paths | cold_initial_paths
    overlap = set(generated_files) & (resources | initial_paths)
    if overlap:
        raise RuntimeError(
            "Generated image paths collide with profile files: "
            + ", ".join(sorted(overlap))
        )
    if profile.cold_source_codec is not None:
        reserved_root_paths = set(samples) | {
            "autoexec.f",
            "kdos.f",
        }
        if requires_networking:
            reserved_root_paths.add("networking.f")
        if requires_rich_terminal:
            reserved_root_paths.add(MEGAPAD_RICH_TERMINAL_MODULE)
        root_generated = {
            path
            for path in set(generated_files) | cold_initial_paths
            if PurePosixPath(path).parent == PurePosixPath(".")
        }
        reserved_overlap = root_generated & reserved_root_paths
        if reserved_overlap:
            raise RuntimeError(
                "Cold source paths collide with image boot/sample files: "
                + ", ".join(sorted(reserved_overlap))
            )
    image_paths = paths | initial_paths
    directories = _directories(image_paths)
    _validate_module_ids(
        tuple(dict.fromkeys((*deployed_modules, *modules))),
        profile.initial_files
        + profile.cold_source_initial_files
        + generated_validation_files,
    )
    _validate_image_paths(
        image_paths,
        directories,
        include_networking=requires_networking,
        external_system_files=(
            frozenset({MEGAPAD_RICH_TERMINAL_MODULE})
            if requires_rich_terminal
            else frozenset()
        ),
        sample_names=frozenset(samples),
    )

    target = Path(target).resolve()
    _private_folder(target.parent)

    fs = MP64FS(total_sectors=profile.total_sectors)
    fs.format()
    fs.inject_file(
        "kdos.f",
        kdos_boot_file,
        ftype=FTYPE_FORTH,
        flags=FLAG_SYSTEM,
    )
    if requires_networking:
        fs.inject_file(
            "networking.f",
            tokens_for(
                "networking.f",
                pack_forth_source((MEGAPAD_ROOT / "networking.f").read_bytes()),
            ),
            ftype=FTYPE_FORTH,
        )
    if requires_rich_terminal:
        fs.inject_file(
            MEGAPAD_RICH_TERMINAL_MODULE,
            tokens_for(
                MEGAPAD_RICH_TERMINAL_MODULE,
                pack_forth_source(
                    (
                        MEGAPAD_ROOT / MEGAPAD_RICH_TERMINAL_MODULE
                    ).read_bytes()
                ),
            ),
            ftype=FTYPE_FORTH,
        )

    for directory in directories:
        fs.mkdir(directory)

    for path in sorted(paths):
        source = SOURCE_ROOT / path
        if path in generated_files:
            content = generated_files[path]
        else:
            if not source.is_file():
                raise FileNotFoundError(f"Missing Akashic resource: {path}")
            content = source.read_bytes()
            if path.endswith(".f"):
                content = tokens_for(path, content)
        disk_path = PurePosixPath(path)
        is_cold_source_chunk = (
            profile.cold_source_codec is not None
            and path in deployed_chunks
        )
        if is_cold_source_chunk:
            file_type = FTYPE_DATA
        else:
            file_type = (
                FTYPE_FORTH if disk_path.suffix == ".f" else FTYPE_TEXT
            )
        parent = "/" if str(disk_path.parent) == "." else "/" + str(disk_path.parent)
        entry = fs.inject_file(
            disk_path.name,
            content,
            ftype=file_type,
            path=parent,
        )
        if is_cold_source_chunk and entry.ext1_count:
            raise RuntimeError(
                "Cold source payload must occupy one MP64FS extent for "
                f"checked guest FREAD: {path}"
            )

    for path, content in initial_files:
        disk_path = PurePosixPath(path)
        if (
            profile.audited_initial_forth_line_bytes is not None
            and disk_path.suffix.lower() == ".f"
        ):
            content = _coalesce_audited_forth_lines(
                content,
                profile.audited_initial_forth_line_bytes,
            )
        parent = "/" if str(disk_path.parent) == "." else "/" + str(disk_path.parent)
        fs.inject_file(disk_path.name, content, path=parent)

    for path, content in cold_source_initial_files.items():
        disk_path = PurePosixPath(path)
        parent = "/" if str(disk_path.parent) == "." else "/" + str(disk_path.parent)
        entry = fs.inject_file(
            disk_path.name,
            content,
            ftype=FTYPE_DATA,
            path=parent,
        )
        if entry.ext1_count:
            raise RuntimeError(
                "Checked cold-source leaf must occupy one MP64FS extent: "
                f"{path}"
            )

    if large_sample:
        if "large.txt" not in samples:
            raise RuntimeError(f"{name!r} carries the large sample, which its samples lack")
        fs.inject_file("large.txt", samples["large.txt"], ftype=FTYPE_TEXT)

        # Leave two isolated one-sector holes in the generated test image.
        # Guest-created smoke.txt uses the first; the large Save As copy uses
        # the second and must grow through MP64FS's secondary extent.
        fs.inject_file(".growth-hole-1", bytes(512), flags=FLAG_SYSTEM)

    fs.inject_file(
        "autoexec.f",
        autoexec.encode("utf-8"),
        ftype=FTYPE_FORTH,
    )
    if large_sample:
        fs.inject_file(".growth-hole-2", bytes(512), flags=FLAG_SYSTEM)

    # The pictures, the sample one and a profile's own, are data; the other
    # samples are text.
    pictures = data_samples | {file_name for file_name, _ in profile.sample_files}
    for name in sorted(samples.keys() - {"large.txt"}):
        fs.inject_file(
            name,
            samples[name],
            ftype=FTYPE_DATA if name in pictures else FTYPE_TEXT,
        )

    if large_sample:
        fs.delete_file(".growth-hole-1")
        fs.delete_file(".growth-hole-2")
    fs.save(_private_file(target))
    settings = (
        _build_settings_image(profile, target, values=settings_by_file)
        if profile.settings_files
        else None
    )
    system = (
        _build_system_image(
            akashic_modules,
            system_image_path(target),
            system_volume_toolchain,
            token_files=token_files,
            boot_id=boot_id,
            keep_source=keep_module_source,
            loaded_before=frozenset(deployed_modules),
            extra_sources=origin_resources,
            extra_files=origin_files,
        )
        if system_volume
        else None
    )
    if system is None:
        system_image_path(target).unlink(missing_ok=True)
    # The user volume holds the user's own documents and records, so a build
    # keeps one that is there unless asked for a fresh one.
    user_path = user_image_path(target)
    kept_user = user_volume and user_path.exists() and not fresh_user_volume
    user = (
        _build_user_image(
            user_path,
            user_volume_mib << 20,
            system_volume_toolchain,
            documents=user_documents,
        )
        if user_volume and not kept_user
        else None
    )
    if not user_volume and fresh_user_volume:
        user_path.unlink(missing_ok=True)
    if session_manifest:
        _write_session_manifest(
            spec, target, name=name, backend=backend,
            settings=settings, system=system is not None, user=user_volume,
            built_from=built_from, facts=session_facts,
        )

    info = fs.info()
    if info["free_sectors"] * 512 < profile.minimum_free_bytes:
        raise RuntimeError(
            f"Profile {name!r} must retain at least "
            f"{profile.minimum_free_bytes:,} bytes of mutable MP64FS space; "
            f"only {info['free_sectors'] * 512:,} bytes remain"
        )
    cold_source_summary = (
        "checked cold-source "
        f"{COLD_SOURCE_CODEC_NAMES[profile.cold_source_codec]}, "
        if profile.cold_source_codec is not None
        else ""
    )
    print(
        f"Built {name} image: {target}\n"
        f"  {len(modules)} modules"
        f"{' on the system volume, ' + str(len(deployed_modules)) + ' to mount it' if system_volume else ''}"
        f"{f' linked in {len(linked_chunks)} chunks' if profile.linked else ''}, "
        f"{cold_source_summary}"
        f"{'MegaPad networking, ' if requires_networking else ''}"
        f"{'MegaPad rich terminal, ' if requires_rich_terminal else ''}"
        f"{len(resources)} resources, "
        f"{len(directories)} directories\n"
        + (
            "  cold source: "
            f"{cold_source_raw_bytes:,} raw bytes -> "
            f"{cold_source_container_bytes:,} container bytes "
            f"({cold_source_container_bytes / cold_source_raw_bytes:.1%}, "
            f"{cold_source_container_bytes - cold_source_raw_bytes:+,} "
            "bytes versus raw)\n"
            if profile.cold_source_codec is not None
            else ""
        )
        +
        f"  {info['files']} MP64FS entries, {target.stat().st_size:,} bytes, "
        f"{info['free_sectors']} free sectors"
        + (
            f"\n  settings disk: {settings}"
            f"{' (asks for safe mode)' if settings_safe_mode else ''}"
            if settings is not None
            else ""
        )
        + (
            f"\n  system volume: {system['path']}, ext4, "
            f"{system['bytes']:,} bytes in {system['block_bytes']}-byte "
            f"blocks, {system['files']} files of {system['file_bytes']:,} "
            f"bytes in {system['directories']} directories"
            + (
                f": {system['token_files']} token forms of "
                f"{system['token_bytes']:,} bytes, "
                + (
                    f"{system['source_files']} source files of "
                    f"{system['source_bytes']:,} bytes beside them"
                    if system["source_files"]
                    else "no source"
                )
                + (
                    f", {system['name_files']} files that name a module "
                    "loaded before the volume is mounted"
                    if system["name_files"]
                    else ""
                )
                + (
                    f", {len(system['absent'])} modules without a token "
                    "form left out: " + " ".join(system["absent"])
                    if system["absent"]
                    else ""
                )
                if token_files
                else ""
            )
            if system is not None
            else ""
        )
        + (f"\n  user volume: {user_path}, kept as it was" if kept_user else "")
        + (
            f"\n  user volume: {user['path']}, ext4, {user['bytes']:,} bytes "
            f"in {USER_VOLUME_BLOCK_BYTES}-byte blocks, {user['groups']} groups, "
            f"{user['documents']} documents"
            if user is not None
            else ""
        )
        + (
            f"\n  token forms on the boot volume: {token_bytes[0]} files, "
            f"{token_bytes[1]:,} source bytes -> {token_bytes[2]:,} bytes"
            if token_files
            else ""
        )
    )
    return target
