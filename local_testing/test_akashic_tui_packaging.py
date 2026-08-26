"""Deployment-linker regressions for bootable Akashic images."""

from __future__ import annotations

import json
import re
import struct
import sys
from dataclasses import replace
from pathlib import Path, PurePosixPath
from types import SimpleNamespace
from unittest.mock import patch

import pytest


LOCAL_TESTING = Path(__file__).resolve().parent
if str(LOCAL_TESTING) not in sys.path:
    sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import (  # noqa: E402
    APP_SHELL_MODULE,
    COLD_SOURCE_CHUNK_TEMPLATE,
    COLD_SOURCE_FLAGS,
    COLD_SOURCE_HEADER,
    COLD_SOURCE_HEADER_BYTES,
    COLD_SOURCE_LOADER_PATH,
    COLD_SOURCE_MAGIC,
    COLD_SOURCE_RAW_MAX_BYTES,
    COLD_SOURCE_VERSION,
    DESKTOP_APT1_RICH_TERMINAL,
    DEFAULT_SMOKE_MAX_STEPS,
    DEFAULT_SMOKE_TIMEOUT,
    FORTH_LINE_COALESCE_BARRIERS,
    LINK_CHUNK_BYTES,
    MEGAPAD_EVALUATE_SOURCE_MAX_BYTES,
    MEGAPAD_NETWORKING_BOOT_LINE,
    MEGAPAD_RICH_TERMINAL_BOOT_LINE,
    MEGAPAD_RICH_TERMINAL_CONSUMERS,
    MEGAPAD_RICH_TERMINAL_MODULE,
    MEGAPAD_ROOT,
    MP64FS_VFS_PLATFORM_BOOT_LINE,
    MP64FS_VFS_PLATFORM_MODULE,
    PROFILES,
    PROVIDED_RE,
    REQUIRE_RE,
    SOURCE_ROOT,
    _coalesce_audited_forth_lines,
    _cold_source_lzss_decode,
    _cold_source_lzss_encode,
    _forth_line_tokens,
    _has_forth_error,
    _linked_autoexec,
    _linked_chunks,
    _minify_forth,
    _matched_failure_markers,
    _pack_cold_source,
    _packed_linked_chunks,
    _parser,
    _rich_terminal_server_arguments,
    _rich_terminal_smoke_ready,
    _smoke_limits,
    _requires_megapad_networking,
    _requires_megapad_rich_terminal,
    _unpack_cold_source,
    _validate_image_paths,
    _validate_module_ids,
    _with_megapad_networking,
    _with_megapad_rich_terminal,
    _with_mp64fs_vfs_platform,
    build_image,
    dependency_closure,
    dependency_order,
    smoke,
)
from diskutil import (  # noqa: E402
    FTYPE_DATA,
    FTYPE_FORTH,
    MP64FS,
    PARENT_ROOT,
    pack_forth_source,
)
from forth_dependencies import module_key  # noqa: E402
from rich_terminal import TerminalState  # noqa: E402
from rich_terminal.retained_model import (  # noqa: E402
    RetainedFeature,
    RetainedPolicy,
)


LIBRARY_RENDERER_FREE_PROFILES = (
    "library-projection-owner-contracts",
)

LIBRARY_RENDERER_FREE_APPLET_MODULES = frozenset(
    {
        "tui/applets/library/model.f",
        "tui/applets/library/index-keys.f",
        "tui/applets/library/document-values.f",
        "tui/applets/library/collection-values.f",
        "tui/applets/library/persistence-adapter.f",
        "tui/applets/library/repository.f",
        "tui/applets/library/query.f",
        "tui/applets/library/service.f",
        "tui/applets/library/projection-adapter.f",
    }
)
LIBRARY_APPLET_BOUND_MODULES = frozenset(
    {
        "tui/applets/library/capability-work.f",
        "tui/applets/library/capabilities.f",
        "tui/applets/library/controller.f",
        "tui/applets/library/view.f",
        "tui/applets/library/library.f",
    }
)


def _assert_library_renderer_free_closure(closure: set[str]) -> None:
    tui_modules = {
        module for module in closure if module.startswith("tui/")
    }
    assert tui_modules <= LIBRARY_RENDERER_FREE_APPLET_MODULES
    assert tui_modules.isdisjoint(LIBRARY_APPLET_BOUND_MODULES)


def test_link_unit_lexer_omits_parser_payload_tokens() -> None:
    assert _forth_line_tokens(
        ': audit S" ; target_id_le=" _APPEND ;'
    ) == (":", "audit", 'S"', "_APPEND", ";")
    assert _forth_line_tokens(": quoted [CHAR] ; DROP ;") == (
        ":",
        "quoted",
        "[CHAR]",
        "DROP",
        ";",
    )
    assert _forth_line_tokens(": commented ( ; ) DROP ;") == (
        ":",
        "commented",
        "(",
        "DROP",
        ";",
    )


def test_cold_source_container_is_deterministic_exact_and_crc_checked() -> None:
    source = b"123456789" + (b" overlap-safe source" * 64)
    packed = _pack_cold_source(source)
    assert packed == _pack_cold_source(source)
    assert _unpack_cold_source(packed) == source

    (
        magic,
        version,
        flags,
        header_bytes,
        raw_bytes,
        payload_bytes,
        raw_crc32,
        reserved,
    ) = COLD_SOURCE_HEADER.unpack_from(packed)
    assert magic == COLD_SOURCE_MAGIC == b"AKLZSS01"
    assert version == COLD_SOURCE_VERSION == 1
    assert flags == COLD_SOURCE_FLAGS == 0
    assert header_bytes == COLD_SOURCE_HEADER_BYTES == 40
    assert raw_bytes == len(source) <= COLD_SOURCE_RAW_MAX_BYTES
    assert payload_bytes == len(packed) - COLD_SOURCE_HEADER_BYTES
    assert reserved == 0
    assert _unpack_cold_source(_pack_cold_source(b"123456789")) == b"123456789"
    assert COLD_SOURCE_HEADER.unpack_from(
        _pack_cold_source(b"123456789")
    )[6] == 0xCBF43926
    assert raw_crc32 != 0

    corrupt = bytearray(packed)
    corrupt[32] ^= 0x01
    with pytest.raises(ValueError, match="CRC mismatch"):
        _unpack_cold_source(bytes(corrupt))


def test_cold_source_container_rejects_every_fixed_header_violation() -> None:
    source = b": COLD-HEADER-TEST 1 ;\n"
    valid = _pack_cold_source(source)

    def changed(offset: int, fmt: str, value: int) -> bytes:
        packed = bytearray(valid)
        struct.pack_into(fmt, packed, offset, value)
        return bytes(packed)

    malformed = (
        (bytes([valid[0] ^ 1]) + valid[1:], "magic"),
        (changed(8, "<H", 2), "version"),
        (changed(10, "<H", 1), "flags"),
        (changed(12, "<I", COLD_SOURCE_HEADER_BYTES + 1), "header size"),
        (changed(16, "<Q", 0), "raw size"),
        (
            changed(16, "<Q", COLD_SOURCE_RAW_MAX_BYTES + 1),
            "raw size",
        ),
        (changed(24, "<Q", len(valid)), "payload size"),
        (changed(36, "<I", 1), "flags"),
    )
    for packed, message in malformed:
        with pytest.raises(ValueError, match=message):
            _unpack_cold_source(packed)


def test_cold_source_lzss_enforces_canonical_and_bounded_streams() -> None:
    assert _cold_source_lzss_encode(b"ABCDEFGH") == b"\xffABCDEFGH"
    assert _cold_source_lzss_encode(b"ABCABC") == b"\x07ABC\x20\x00"
    assert _cold_source_lzss_encode(b"A" * 19) == b"\x01A\x0f\x00"
    source = b"A" * 257
    payload = _cold_source_lzss_encode(source)
    assert _cold_source_lzss_decode(payload, len(source)) == source

    # A single literal consumes bit zero; all seven unused control bits must
    # be zero so the same raw source has one canonical token stream shape.
    with pytest.raises(ValueError, match="Non-canonical"):
        _cold_source_lzss_decode(b"\x03A", 1)
    with pytest.raises(ValueError, match="distance"):
        _cold_source_lzss_decode(b"\x00\x00\x00", 3)
    with pytest.raises(ValueError, match="Truncated"):
        _cold_source_lzss_decode(b"\x01", 1)
    with pytest.raises(ValueError, match="Trailing"):
        _cold_source_lzss_decode(b"\x01A\x00", 1)


def test_cold_source_autoexec_is_opt_in_and_preserves_source_order() -> None:
    autoexec = (
        "ENTER-USERLAND\n"
        "REQUIRE one.f\n"
        "REQUIRE local_testing/fixture.f\n"
    )
    ordinary = _linked_autoexec(
        autoexec,
        (".akashic/link-00.f",),
        ("one.f",),
    )
    assert f"REQUIRE {COLD_SOURCE_LOADER_PATH}" not in ordinary
    assert "REQUIRE .akashic/link-00.f" in ordinary

    chunk = COLD_SOURCE_CHUNK_TEMPLATE.format(index=0)
    packed = _linked_autoexec(
        autoexec,
        (chunk,),
        ("one.f",),
        cold_source_packed=True,
    )
    assert packed.count(f"REQUIRE {COLD_SOURCE_LOADER_PATH}") == 1
    assert "COLD SOURCE LOAD FAIL status=" in packed
    assert f"_BOOT-COLD-SOURCE {chunk}" in packed
    assert packed.index(f"REQUIRE {COLD_SOURCE_LOADER_PATH}") < packed.index(
        f"_BOOT-COLD-SOURCE {chunk}"
    ) < packed.index("REQUIRE local_testing/fixture.f")
    assert PROFILES["desktop-library-burrow-capstone"].cold_source_packed
    assert not PROFILES["desktop-library-burrow"].cold_source_packed
    assert PROFILES["desktop"].cold_source_packed
    with pytest.raises(RuntimeError, match="no linked REQUIRE"):
        _linked_autoexec(
            "ENTER-USERLAND\nREQUIRE local_testing/fixture.f\n",
            (chunk,),
            ("one.f",),
            cold_source_packed=True,
        )


def test_cp5_cold_source_image_roundtrips_the_real_linked_closure(
    tmp_path: Path,
) -> None:
    profile_name = "desktop-library-burrow-capstone"
    profile = PROFILES[profile_name]
    profile_modules = dependency_order(profile.roots)
    composition_roots = profile.roots
    if APP_SHELL_MODULE in profile_modules:
        composition_roots = (MP64FS_VFS_PLATFORM_MODULE,) + profile.roots
    modules = dependency_order(composition_roots)
    linked = _linked_chunks(
        modules,
        profile.link_chunk_bytes,
        profile.audited_link_line_bytes,
    )
    packed = _packed_linked_chunks(linked)
    image = build_image(profile_name, tmp_path / "cp5-cold-source.img")
    filesystem = MP64FS(bytearray(image.read_bytes()))

    loader = filesystem.find_file(COLD_SOURCE_LOADER_PATH)
    assert loader is not None
    _, loader_entry = loader
    assert loader_entry.ftype == FTYPE_FORTH
    assert loader_entry.ext1_count == 0
    assert filesystem.read_file(COLD_SOURCE_LOADER_PATH) == (
        LOCAL_TESTING / "cold-source-loader.f"
    ).read_bytes()

    packed_names = tuple(
        COLD_SOURCE_CHUNK_TEMPLATE.format(index=index)
        for index in range(len(linked))
    )
    root_names = {
        entry.name for entry in filesystem.list_files(parent=PARENT_ROOT)
    }
    assert set(packed_names) <= root_names
    assert not any(name.startswith("link-") for name in root_names)
    for name, raw in zip(packed_names, linked.values(), strict=True):
        found = filesystem.find_file(name)
        assert found is not None
        _, entry = found
        assert entry.ftype == FTYPE_DATA
        assert entry.ext1_count == 0
        container = filesystem.read_file(name)
        assert container == packed[name]
        assert _unpack_cold_source(container) == raw

    leaf_names = tuple(
        path for path, _ in profile.cold_source_initial_files
    )
    assert set(leaf_names) <= root_names
    for path, raw in profile.cold_source_initial_files:
        found = filesystem.find_file(path)
        assert found is not None
        _, entry = found
        assert entry.ftype == FTYPE_DATA
        assert entry.ext1_count == 0
        assert _unpack_cold_source(filesystem.read_file(path)) == raw

    loader_source = (LOCAL_TESTING / "cold-source-loader.f").read_text(
        encoding="utf-8"
    )
    executable_tokens = {
        token
        for line in loader_source.splitlines()
        for token in line.split("\\", 1)[0].split()
    }
    assert "PROVIDED akashic-cold-source-loader" in loader_source
    assert "COLD-SOURCE-LOAD" in executable_tokens
    assert "(FCLOSE-NOFS)" in executable_tokens
    assert "FCLOSE" not in executable_tokens
    assert "CRC32-IEEE-BUF" in executable_tokens
    assert "SOURCE-EVALUATE-CHECKED" in executable_tokens

    autoexec = filesystem.read_file("autoexec.f").decode("utf-8")
    assert autoexec.count(f"REQUIRE {COLD_SOURCE_LOADER_PATH}") == 1
    assert "REQUIRE .akashic/link-" not in autoexec
    assert autoexec.index("ENTER-USERLAND") < autoexec.index(
        f"REQUIRE {COLD_SOURCE_LOADER_PATH}"
    ) < autoexec.index(f"_BOOT-COLD-SOURCE {packed_names[0]}")
    positions = [
        autoexec.index(f"_BOOT-COLD-SOURCE {name}") for name in packed_names
    ]
    assert positions == sorted(positions)
    leaf_positions = [
        autoexec.index(f"_BOOT-COLD-SOURCE {name}") for name in leaf_names
    ]
    assert leaf_positions == sorted(leaf_positions)
    assert positions[-1] < leaf_positions[0]
    assert profile.initial_files == ()
    assert filesystem.info()["free_sectors"] * 512 >= 1 << 20


def test_injected_forth_provided_keys_share_module_collision_validation() -> None:
    prefix = "abcdefghijklmnopqrstuvw"
    with pytest.raises(RuntimeError, match="KDOS PROVIDED key collision"):
        _validate_module_ids(
            (),
            (
                ("first.f.lz", f"PROVIDED {prefix}-first\n".encode()),
                ("second.f", f"PROVIDED {prefix}-second\n".encode()),
            ),
        )

    profile = PROFILES["desktop-library-burrow-capstone"]
    _validate_module_ids(
        dependency_order(profile.roots),
        profile.initial_files + profile.cold_source_initial_files,
    )


def test_image_paths_reject_file_directory_aliases() -> None:
    with pytest.raises(RuntimeError, match="both files and directories"):
        _validate_image_paths(
            {"collision", "collision/child.f"},
            ["collision"],
        )


@pytest.mark.parametrize(
    "message",
    (
        "Module not found: tui",
        "Path component not found: tui",
    ),
)
def test_smoke_rejects_module_loader_failures(message: str) -> None:
    assert _has_forth_error(message) == [message]


def test_app_shell_is_vfs_abstract_and_mp64fs_is_platform_composition() -> None:
    shell = (SOURCE_ROOT / APP_SHELL_MODULE).read_text(encoding="utf-8")
    platform = (SOURCE_ROOT / MP64FS_VFS_PLATFORM_MODULE).read_text(
        encoding="utf-8"
    )

    assert "REQUIRE ../utils/fs/vfs.f" in shell
    assert "vfs-mp64fs.f" not in shell
    assert "_ASHELL-VFS" not in shell
    assert "REQUIRE ../../utils/fs/drivers/vfs-mp64fs.f" in platform
    assert "131072 CONSTANT _MP64VFS-ARENA-SIZE" in platform
    assert platform.rstrip().endswith("MP64VFS-ENSURE")


def test_mp64fs_platform_boot_load_is_early_and_idempotent() -> None:
    autoexec = "ENTER-USERLAND\nREQUIRE tui/applets/pad/pad.f\n"
    integrated = _with_mp64fs_vfs_platform(autoexec)
    assert integrated == (
        "ENTER-USERLAND\n"
        f"{MP64FS_VFS_PLATFORM_BOOT_LINE}\n"
        "REQUIRE tui/applets/pad/pad.f\n"
    )
    assert _with_mp64fs_vfs_platform(integrated) == integrated

    networked = (
        "ENTER-USERLAND\n"
        f"{MEGAPAD_NETWORKING_BOOT_LINE}\n"
        "REQUIRE tui/applets/desk/desk.f\n"
    )
    integrated = _with_mp64fs_vfs_platform(networked)
    assert integrated.index(MEGAPAD_NETWORKING_BOOT_LINE) < integrated.index(
        MP64FS_VFS_PLATFORM_BOOT_LINE
    ) < integrated.index("REQUIRE tui/applets/desk/desk.f")


def test_crc_contract_profile_uses_reflected_checked_megapad_surface() -> None:
    source = (SOURCE_ROOT / "math/crc.f").read_text(encoding="utf-8")
    profile = PROFILES["crc-contracts"]
    fixture = profile.autoexec
    executable = "\n".join(
        line.split("\\", 1)[0] for line in source.splitlines()
    )

    assert profile.roots == ("math/crc.f",)
    assert profile.ready_markers == ("CRC CONTRACTS PASS",)
    assert profile.stable_markers == profile.ready_markers
    for removed in (
        "CRC-POLY!",
        "CRC-POLY-CRC32",
        "CRC-POLY-CRC32C",
        "CRC-POLY-CRC64",
    ):
        assert removed not in source
        assert removed not in fixture
    for declaration in (
        "4 CONSTANT CRC-MODE-CRC32",
        "5 CONSTANT CRC-MODE-CRC32C",
        "2 CONSTANT CRC-MODE-CRC64",
        ": CRC32C-RAW  ( seed data len -- raw )",
        ": CRC32C-RAW?  ( seed data len -- raw status )",
    ):
        assert declaration in source
    for primitive in (
        "CRC-MODE!",
        "CRC-RESET",
        "CRC-INIT!",
        "CRC-FEED",
        "CRC-FEED-BYTE",
        "CRC-RAW-FINAL@",
    ):
        calls = [
            line
            for line in executable.splitlines()
            if re.search(
                rf"(?<![A-Z0-9_-]){re.escape(primitive)}"
                r"(?![A-Z0-9_-])",
                line,
            )
        ]
        assert calls
        assert all("_CRC-CHECK-STATUS" in line for line in calls)

    assert "S\" 123456789\" CRC32 0xCBF43926" in fixture
    assert "S\" 123456789\" CRC32C 0xE3069283" in fixture
    assert "CRC32C-RAW" in fixture
    assert "CRC32C-RAW?" in fixture
    assert "0x1CF96D7C = _crc-assert" in fixture
    assert "['] _crc-call-one-shot-during-direct CATCH 2 =" in fixture


def test_sha3_contract_profile_uses_checked_megapad_surface() -> None:
    source = (SOURCE_ROOT / "math/sha3.f").read_text(encoding="utf-8")
    context = (SOURCE_ROOT / "math/sha3-context.f").read_text(encoding="utf-8")
    vfs_snapshot = (
        SOURCE_ROOT / "utils/fs/vfs-fixed-snapshot.f"
    ).read_text(encoding="utf-8")
    spool = (
        SOURCE_ROOT / "tui/applets/streams/operational-spool.f"
    ).read_text(encoding="utf-8")
    profile = PROFILES["sha3-checked-contracts"]
    fixture = profile.initial_files[0][1].decode("utf-8")

    assert profile.roots == ("math/sha3.f",)
    assert profile.ready_markers == ("SHA3 CHECKED CONTRACTS PASS",)
    assert profile.stable_markers == profile.ready_markers
    assert tuple(path for path, _ in profile.initial_files) == (
        "local_testing/sha3-checked-test.f",
    )
    for removed in (
        "SHA3-MODE!",
        "SHA3-INIT",
        "SHA3-SQUEEZE",
        "SHA3-DOUT@",
        "_SHA3-IPAD",
        "_SHA3-OPAD",
        "_SHA3-INNER",
    ):
        assert removed not in source

    for checked_call in (
        "SHA3 _SHA3-CHECK-STATUS",
        "SHA3-512 _SHA3-CHECK-STATUS",
        "HMAC _SHA3-CHECK-STATUS",
        "SHA3-256-MODE SHA3-BEGIN _SHA3-CHECK-STATUS",
        "SHA3-512-MODE SHA3-BEGIN _SHA3-CHECK-STATUS",
        "SHAKE128-MODE SHA3-BEGIN _SHA3-CHECK-STATUS",
        "SHAKE256-MODE SHA3-BEGIN _SHA3-CHECK-STATUS",
        "SHA3-UPDATE _SHA3-CHECK-STATUS",
        "SHA3-FINAL _SHA3-CHECK-STATUS",
        "32 MIN SHAKE-READ",
        "SHA3-CLEAR",
    ):
        assert checked_call in source
    for family in ("SHAKE-128", "SHAKE-256"):
        for suffix in ("BEGIN", "ADD", "END"):
            assert f": {family}-{suffix}" in source

    compare_256 = source.split(": SHA3-256-COMPARE", 1)[1].split(
        ": SHA3-512-COMPARE", 1
    )[0]
    compare_512 = source.split(": SHA3-512-COMPARE", 1)[1].split(
        "CREATE _SHA3-COMPARE-DIGEST", 1
    )[0]
    assert all(word not in compare_256 for word in (">R", "R>"))
    assert all(word not in compare_512 for word in (">R", "R>"))
    assert "CREATE _SHA3-PRIVATE-BEGIN 0 ALLOT" in source
    assert "CREATE _SHA3-PRIVATE-END 0 ALLOT" in source
    assert "2DUP _SHA3-PRIVATE-BEGIN" in vfs_snapshot
    assert "_SHA3-PRIVATE-END" in vfs_snapshot

    for software_round_word in (
        "_SHA3C-THETA",
        "_SHA3C-RHO-PI-STEP",
        "_SHA3C-CHI",
        "_SHA3C-RC",
    ):
        assert software_round_word not in context
    assert "DUP _SHA3C.STATE KECCAK-F1600" in context
    assert "5 CONSTANT SHA3-CONTEXT-S-HARDWARE" in context
    assert "SHA3-256-CONTEXT-SIZE 0 FILL" in context
    assert "SHA3-CONTEXT-S-HARDWARE OF STREAMS-SPOOL-S-FAULT" in spool
    assert "SHA3-CONTEXT-S-HARDWARE OF PERSIST-S-FAULT" in spool

    for length in ("0", "1", "31", "32", "33", "63", "64", "65"):
        assert f"{length} _s3-check-shake128" in fixture
        assert f"{length} _s3-check-shake256" in fixture
    assert "_s3-data 7 + 162 SHAKE-128-ADD" in fixture
    assert "_s3-data 5 + 132 SHAKE-256-ADD" in fixture
    assert "['] _s3-call-one-shot-during-direct CATCH 2 =" in fixture
    assert "['] _s3-call-cross-shake-end CATCH -258 =" in fixture


def test_every_app_shell_profile_composes_the_platform_provider() -> None:
    app_shell_profiles = 0
    linked_profiles = 0
    unlinked_profiles = 0
    for profile in PROFILES.values():
        base_modules = (
            dependency_order(profile.roots)
            if profile.linked
            else dependency_closure(profile.roots)
        )
        if APP_SHELL_MODULE not in base_modules:
            continue
        app_shell_profiles += 1
        linked_profiles += int(profile.linked)
        unlinked_profiles += int(not profile.linked)
        autoexec = _with_mp64fs_vfs_platform(profile.autoexec)
        assert autoexec.count(MP64FS_VFS_PLATFORM_BOOT_LINE) == 1

        composition_roots = (MP64FS_VFS_PLATFORM_MODULE,) + tuple(
            root
            for root in profile.roots
            if root != MP64FS_VFS_PLATFORM_MODULE
        )
        modules = (
            dependency_order(composition_roots)
            if profile.linked
            else dependency_closure(composition_roots)
        )
        assert MP64FS_VFS_PLATFORM_MODULE in modules
        if profile.linked:
            assert modules.index(MP64FS_VFS_PLATFORM_MODULE) < modules.index(
                APP_SHELL_MODULE
            )

    assert app_shell_profiles > 0
    assert linked_profiles > 0
    assert unlinked_profiles > 0


@pytest.mark.parametrize("profile_name", LIBRARY_RENDERER_FREE_PROFILES)
def test_library_renderer_free_profiles_use_linked_loader(
    profile_name: str,
) -> None:
    profile = PROFILES[profile_name]
    assert profile.linked is True
    assert profile.link_chunk_bytes == LINK_CHUNK_BYTES
    _assert_library_renderer_free_closure(set(dependency_closure(profile.roots)))


def test_profile_failure_markers_are_checked_across_raw_and_screen_text() -> None:
    profile = PROFILES["library-projection-owner-contracts"]
    assert _matched_failure_markers(
        profile,
        "old raw output: LIBRARY PROJECTION OWNER ASSERT 9",
        "LIBRARY PROJECTION OWNER PASS 99",
    ) == ("LIBRARY PROJECTION OWNER ASSERT",)


def test_agent_provider_ui_command_profile_uses_public_applet_seams() -> None:
    profile = PROFILES["agent-provider-ui-commands"]
    assert profile.roots == (
        "tui/applets/agent/agent.f",
        "tui/applets/desk/agent-access-policy.f",
    )
    assert profile.resources == ()
    assert tuple(path for path, _ in profile.initial_files) == (
        "local_testing/l7-agent-actions.f",
    )
    closure = set(dependency_closure(profile.roots))
    assert {
        "tui/applets/agent/service.f",
        "tui/applets/agent/runtime.f",
        "tui/applets/agent/widgets/agent-auth.f",
        "tui/applets/agent/widgets/agent-settings.f",
        "tui/applets/desk/agent-access-policy.f",
    } <= closure
    assert all(not module.startswith("agent/") for module in closure)
    assert "tui/widgets/agent-auth.f" not in closure
    assert "tui/widgets/agent-settings.f" not in closure


def test_library_projection_owner_profile_packages_renderer_free_contract() -> None:
    profile = PROFILES["library-projection-owner-contracts"]
    assert profile.roots == (
        "tui/applets/library/projection-adapter.f",
        "interop/resource-client.f",
    )
    assert profile.resources == ()
    assert profile.ready_markers == ("LIBRARY PROJECTION OWNER PASS",)
    assert profile.stable_markers == profile.ready_markers
    assert profile.total_sectors == 8192
    assert profile.include_large_sample is False
    assert profile.linked is True
    assert {
        "LIBRARY PROJECTION OWNER FAIL",
        "LIBRARY PROJECTION OWNER ASSERT",
        "LIBRARY PROJECTION OWNER STACK",
        "EVALUATE depth limit exceeded",
        "dictionary full",
        "exception",
    } <= set(profile.failure_markers)
    assert tuple(path for path, _ in profile.initial_files) == (
        "local_testing/library-projection.f",
    )
    assert "REQUIRE tui/applets/library/projection-adapter.f" in profile.autoexec
    assert "REQUIRE interop/resource-client.f" in profile.autoexec
    assert "REQUIRE tui/applets/library/service.f" in profile.autoexec
    assert "REQUIRE concurrency/guard.f" in profile.autoexec
    assert "REQUIRE interop/request-bus.f" in profile.autoexec
    assert "REQUIRE interop/resource-acquisition.f" in profile.autoexec
    assert profile.autoexec.index("REQUIRE concurrency/guard.f") < (
        profile.autoexec.index("REQUIRE interop/request-bus.f")
    )
    assert profile.autoexec.index("REQUIRE interop/request-bus.f") < (
        profile.autoexec.index("REQUIRE interop/resource-acquisition.f")
    )
    assert profile.autoexec.index("REQUIRE interop/resource-acquisition.f") < (
        profile.autoexec.index("REQUIRE interop/resource-client.f")
    )
    assert profile.autoexec.index("REQUIRE interop/resource-client.f") < (
        profile.autoexec.index("REQUIRE tui/applets/library/service.f")
    )
    assert profile.autoexec.index("REQUIRE tui/applets/library/service.f") < (
        profile.autoexec.index("REQUIRE tui/applets/library/projection-adapter.f")
    )
    assert "REQUIRE local_testing/library-projection.f" in profile.autoexec
    fixture = profile.initial_files[0][1].decode("utf-8")
    assert ": _lpo-run" in fixture
    assert "_lpo-run\n" in fixture

    closure = set(dependency_closure(profile.roots))
    assert {
        "tui/applets/library/model.f",
        "tui/applets/library/index-keys.f",
        "tui/applets/library/document-values.f",
        "tui/applets/library/collection-values.f",
        "tui/applets/library/persistence-adapter.f",
        "tui/applets/library/repository.f",
        "tui/applets/library/query.f",
        "tui/applets/library/service.f",
        "tui/applets/library/projection-adapter.f",
        "interop/resource-acquisition.f",
        "interop/resource-client.f",
        "interop/resource-contract.f",
        "interop/request-bus.f",
        "runtime/resource-registry.f",
    } <= closure
    production_closure = set(
        dependency_closure(("tui/applets/library/projection-adapter.f",))
    )
    assert "tui/applets/library/projection-adapter.f" in production_closure
    assert "interop/resource-client.f" not in production_closure
    assert production_closure <= closure
    _assert_library_renderer_free_closure(closure)


def test_library_applet_profiles_package_the_library_owned_applet() -> None:
    root = "tui/applets/library/library.f"
    resource = "tui/applets/library/library.uidl"
    interactive = PROFILES["library"]
    contracts = PROFILES["library-applet-contracts"]
    functional = PROFILES["library-applet-functional-contracts"]

    for profile in (interactive, contracts, functional):
        assert profile.roots == (root,)
        assert profile.resources == (resource,)
        assert profile.linked is True
        assert profile.link_chunk_bytes == LINK_CHUNK_BYTES
        assert profile.include_large_sample is False
    assert interactive.total_sectors == 8192
    assert contracts.total_sectors == 8192
    assert functional.total_sectors == 8192

    assert "LIBRARY-APPLET-RUN" in interactive.autoexec
    assert contracts.ready_markers == ("LIBRARY APPLET CONTRACTS PASS",)
    assert contracts.stable_markers == contracts.ready_markers
    assert {
        "LIBRARY APPLET CONTRACTS FAIL",
        "LIBRARY APPLET ASSERT",
        "LIBRARY APPLET STACK",
        "EVALUATE depth limit exceeded",
        "dictionary full",
        "exception",
    } <= set(contracts.failure_markers)
    assert "LIBRARY-APPLET-ENTRY" in contracts.autoexec
    assert "LIBRARY-APPLET-RUN" not in contracts.autoexec
    assert functional.ready_markers == (
        "LIBRARY APPLET FUNCTIONAL PASS",
    )
    assert functional.stable_markers == functional.ready_markers
    assert tuple(path for path, _ in functional.initial_files) == (
        "local_testing/library-app-func.f",
    )
    assert {
        "LIBRARY APPLET FUNCTIONAL FAIL",
        "LIBRARY APPLET FUNCTIONAL ASSERT",
        "LIBRARY APPLET FUNCTIONAL STACK",
        "EVALUATE depth limit exceeded",
        "dictionary full",
        "exception",
    } <= set(functional.failure_markers)
    assert "REQUIRE local_testing/library-app-func.f" in (
        functional.autoexec
    )

    closure = set(dependency_closure((root,)))
    expected_library_modules = {
        "tui/applets/library/model.f",
        "tui/applets/library/index-keys.f",
        "tui/applets/library/document-values.f",
        "tui/applets/library/collection-values.f",
        "tui/applets/library/persistence-adapter.f",
        "tui/applets/library/repository.f",
        "tui/applets/library/query.f",
        "tui/applets/library/service.f",
        "tui/applets/library/capability-work.f",
        "tui/applets/library/capabilities.f",
        "tui/applets/library/controller.f",
        "tui/applets/library/view.f",
        root,
    }
    assert expected_library_modules | {
        "tui/app-desc.f",
        "tui/app-shell.f",
    } <= closure
    assert {
        module
        for module in closure
        if module.startswith("tui/applets/")
    } == expected_library_modules
    assert all(not module.startswith("agent/") for module in closure)
    assert all(not module.startswith("practice/") for module in closure)
    assert all(not module.startswith("streams/") for module in closure)

    # This direct test assembly exercises the Library-owned, Desk-hosted applet;
    # it is not a standalone product. Desktop composition remains explicit.
    assert root not in PROFILES["desktop"].roots
    assert resource not in PROFILES["desktop"].resources


def test_library_applet_functional_fixture_covers_cold_and_blocked_open() -> None:
    source = (
        LOCAL_TESTING / "library-applet-functional.f"
    ).read_text(encoding="utf-8")

    assert all(
        word in source
        for word in (
            "LIBRARY-APPLET-ENTRY",
            "LIBRARY-APPLET-INIT-CB",
            "ASHELL-RUN",
            "_LAPP-CONFIGURE-CREATE",
            "_LAPP-DISPATCH-PENDING-CREATE",
            "_LAPP-CREATE-PREPARED",
            "_LAPP-RESET-PAGE",
            "_LAPP-PREVIEW-BYTES",
            "_LAPP-DO-ARCHIVE",
            "_LAPP-DO-SHOW-ARCHIVED",
            "LIBRARY-REPOSITORY-INSPECT",
            "LIBRARY-REPOSITORY-HEALTH-CORRUPT",
            "LIBRARY-REPOSITORY-HEALTH-FUTURE",
            "_LIBREPO-FUTURE-ROOT-RECORD?",
        )
    )
    assert not re.findall(r"\bLIBRARY-VFS-STORE-[A-Z0-9-]+\b", source)
    assert not re.findall(r"\bLIBRARY-VFS-STORE\.[A-Z0-9-]+\b", source)
    assert not re.findall(
        r"\b_LIB(?:MU|VFS)-[A-Z0-9-]+\b",
        source,
    )

    cold = source.split(": _laf-cold-shell-init", 1)[1].split(
        ": _laf-assert-blocked-ui", 1
    )[0]
    blocked_ui = source.split(": _laf-assert-blocked-ui", 1)[1].split(
        ": _laf-refuse-blocked-writes", 1
    )[0]
    refusal = source.split(": _laf-refuse-blocked-writes", 1)[1].split(
        ": _laf-blocked-shell-init", 1
    )[0]
    corrupt_init = source.split(": _laf-blocked-shell-init", 1)[1].split(
        ": _laf-future-shell-init", 1
    )[0]
    future_init = source.split(": _laf-future-shell-init", 1)[1].split(
        ": _laf-outer-stack", 1
    )[0]
    corrupt_roots = source.split(": _laf-corrupt-roots", 1)[1].split(
        ": _laf-future-roots", 1
    )[0]
    future_roots = source.split(": _laf-future-roots", 1)[1].split(
        ": _laf-restore-roots", 1
    )[0]
    runner = source.split(": _laf-run", 1)[1]

    assert "LIBRARY-APPLET-INIT-CB" in cold
    assert "_LAPP-ROW-COUNT @ 2 =" in cold
    assert "_LAPP-SELECTED @ 0=" in cold
    assert "_laf-preview-body?" in cold

    assert "Corrupt - writes blocked" in blocked_ui
    assert "_LAPP-READY? 0=" in blocked_ui
    assert "_LAPP-ROW-COUNT @ 0=" in blocked_ui
    assert "_LAPP-STATUS-U @ 0>" in blocked_ui
    assert "_LAPP-ENSURE-PROVISIONED" in refusal
    assert "_LAPP-DISPATCH-PENDING-CREATE" in refusal
    assert "_laf-inspection-before LRI.SEAL" in refusal
    assert "_laf-inspection-after LRI.SEAL" in refusal

    assert "LIBRARY-APPLET-INIT-CB" in corrupt_init
    assert "_laf-assert-blocked-ui" in corrupt_init
    assert (
        "LIBRARY-REPOSITORY-HEALTH-CORRUPT "
        "_laf-refuse-blocked-writes"
    ) in corrupt_init
    assert "LIBRARY-APPLET-INIT-CB" in future_init
    assert "_laf-assert-blocked-ui" in future_init
    assert (
        "LIBRARY-REPOSITORY-HEALTH-FUTURE "
        "_laf-refuse-blocked-writes"
    ) in future_init

    assert "_LIBREPO-ROOT-0$" in corrupt_roots
    assert "_LIBREPO-ROOT-1$" in corrupt_roots
    assert corrupt_roots.count("_laf-copy-corrupt") == 2
    assert future_roots.count("_laf-copy-future") == 2
    assert future_roots.count("_LIBREPO-FUTURE-ROOT-RECORD?") == 2
    assert runner.count("_laf-desc ASHELL-RUN") == 5
    assert runner.count("['] _laf-cold-shell-init") == 2
    assert "_laf-ran @ 5 =" in runner
    assert "_laf-restore-roots" in runner
    assert "_LAPP-LAST-STATUS !" not in source


def test_library_dependency_chain_and_ui_storage_boundary() -> None:
    sources = {
        name: (SOURCE_ROOT / f"tui/applets/library/{name}").read_text(
            encoding="utf-8"
        )
        for name in (
            "library.f",
            "view.f",
            "controller.f",
            "service.f",
            "query.f",
            "repository.f",
            "persistence-adapter.f",
            "index-keys.f",
            "document-values.f",
            "collection-values.f",
            "capability-work.f",
            "capabilities.f",
        )
    }
    direct_requires = {
        name: set(REQUIRE_RE.findall(source))
        for name, source in sources.items()
    }

    assert direct_requires["library.f"] == {"view.f", "capabilities.f"}
    assert direct_requires["view.f"] == {"controller.f"}
    assert {"service.f", "capability-work.f"} <= direct_requires[
        "controller.f"
    ]
    assert not (
        {"query.f", "repository.f", "capabilities.f"}
        & direct_requires["controller.f"]
    )
    assert direct_requires["capabilities.f"] == {
        "capability-work.f",
        "controller.f",
        "../../../interop/request-bus.f",
        "../../../interop/schema-common.f",
        "../../../interop/profiles/library-read-v1.f",
    }
    assert direct_requires["capability-work.f"] == {
        "service.f",
        "collection-values.f",
        "../../../interop/construction.f",
    }
    assert direct_requires["service.f"] == {
        "repository.f",
        "query.f",
        "document-values.f",
        "collection-values.f",
    }
    assert direct_requires["query.f"] == {"persistence-adapter.f"}
    assert direct_requires["repository.f"] == {
        "persistence-adapter.f",
        "../../../persistence/compaction.f",
        "../../../math/sha3.f",
    }
    assert direct_requires["persistence-adapter.f"] == {
        "../../../persistence/store.f",
        "../../../persistence/btree.f",
        "../../../persistence/blob.f",
        "../../../persistence/reclaim.f",
        "index-keys.f",
        "document-values.f",
        "collection-values.f",
    }
    assert direct_requires["collection-values.f"] == {"model.f"}
    for name in (
        "library.f",
        "view.f",
        "controller.f",
        "service.f",
        "query.f",
        "index-keys.f",
        "document-values.f",
        "collection-values.f",
        "capability-work.f",
        "capabilities.f",
    ):
        assert not any(
            requirement.startswith("../../../utils/fs/")
            for requirement in direct_requires[name]
        )

    ui_sources = "\n".join(
        sources[name] for name in ("library.f", "view.f", "controller.f")
    )
    assert set(
        re.findall(r"(?<![A-Z0-9_-])VFS-[A-Z0-9-]+\b", ui_sources)
    ) <= {"VFS-CUR"}
    assert "VFSNAP-" not in ui_sources
    assert "_LIBVFS-" not in ui_sources
    assert all(
        word not in ui_sources
        for word in (" DESK-", " PAD-", " FEXP-", " STREAMS-")
    )
    all_library_sources = "\n".join(sources.values())
    all_library_requires = set().union(*direct_requires.values())
    assert "record-codec.f" not in all_library_requires
    assert "store-format.f" not in all_library_requires
    assert "L12-DELETION" not in all_library_sources
    assert "_LIBVFS-" not in all_library_sources
    assert "DRW-TEXT-UNTRUSTED" not in sources["library.f"]
    assert "DRW-TEXT-UNTRUSTED" not in sources["controller.f"]
    assert "DRW-TEXT-UNTRUSTED" in sources["view.f"]

    capability_providers = {
        name: PROVIDED_RE.findall(sources[name])
        for name in ("capability-work.f", "capabilities.f")
    }
    assert capability_providers == {
        "capability-work.f": ["akashic-lib-cap-work"],
        "capabilities.f": ["akashic-lib-caps"],
    }
    capability_keys = {
        provider
        for providers in capability_providers.values()
        for provider in providers
    }
    assert len(capability_keys) == 2
    assert all(len(key.encode("ascii")) <= 23 for key in capability_keys)


def test_library_applet_uidl_actions_have_exact_controller_bindings() -> None:
    source = (SOURCE_ROOT / "tui/applets/library/library.f").read_text(
        encoding="utf-8"
    )
    uidl = (SOURCE_ROOT / "tui/applets/library/library.uidl").read_text(
        encoding="utf-8"
    )
    declared_actions = set(re.findall(r"\bdo=([A-Za-z0-9-]+)", uidl))
    bound_actions = set(
        re.findall(
            r'S" ([a-z0-9-]+)" \[\'\] _LAPP-[A-Z0-9-]+ UTUI-DO!',
            source,
        )
    )

    assert declared_actions == bound_actions
    assert {"library-body", "sbar-view", "sbar-page", "sbar-state"} <= set(
        re.findall(r"\bid=([A-Za-z0-9-]+)", uidl)
    )


def test_library_applet_functional_image_links_controller_and_keeps_uidl(
    tmp_path: Path,
) -> None:
    image = build_image(
        "library-applet-functional-contracts",
        tmp_path / "akashic-library-applet-functional-contracts.img",
    )
    assert image.stat().st_size == 8192 * 512

    filesystem = MP64FS(bytearray(image.read_bytes()))
    library_parent = filesystem.resolve_path("/tui/applets/library")
    assert filesystem.find_file("library.f", parent=library_parent) is None
    assert filesystem.read_file("library.uidl", parent=library_parent) == (
        SOURCE_ROOT / "tui/applets/library/library.uidl"
    ).read_bytes()
    linked_parent = filesystem.resolve_path("/.akashic")
    linked_entries = sorted(
        (
            entry
            for entry in filesystem.list_files(parent=linked_parent)
            if entry.name.startswith("link-")
        ),
        key=lambda entry: entry.name,
    )
    assert linked_entries
    linked_source = b"".join(
        filesystem.read_file(entry.name, parent=linked_parent)
        for entry in linked_entries
    ).decode("utf-8")
    assert "PROVIDED akashic-tui-mp64fs-vfs" in linked_source
    assert linked_source.index("PROVIDED akashic-tui-mp64fs-vfs") < (
        linked_source.index("PROVIDED akashic-tui-app-shell")
    )
    fixture_parent = filesystem.resolve_path("/local_testing")
    assert filesystem.read_file(
        "library-app-func.f", parent=fixture_parent
    ) == _minify_forth((
        LOCAL_TESTING / "library-applet-functional.f"
    ).read_text(encoding="utf-8")).encode("utf-8")
    autoexec = filesystem.read_file("autoexec.f").decode("utf-8")
    assert "REQUIRE tui/applets/library/library.f" not in autoexec
    assert MP64FS_VFS_PLATFORM_BOOT_LINE not in autoexec
    assert "REQUIRE .akashic/link-" in autoexec
    assert autoexec.index("ENTER-USERLAND") < autoexec.index(
        "REQUIRE .akashic/link-"
    ) < autoexec.index("REQUIRE local_testing/library-app-func.f")
    assert "REQUIRE local_testing/library-app-func.f" in autoexec
    assert filesystem.info()["free_sectors"] > 0


def test_unlinked_app_shell_profile_packages_and_loads_platform_provider(
    tmp_path: Path,
) -> None:
    image = build_image(
        "pad-contracts",
        tmp_path / "akashic-pad-contracts.img",
    )
    filesystem = MP64FS(bytearray(image.read_bytes()))
    platform_parent = filesystem.resolve_path("/tui/platform")
    assert filesystem.read_file("mp64fs-vfs.f", parent=platform_parent) == (
        SOURCE_ROOT / MP64FS_VFS_PLATFORM_MODULE
    ).read_bytes()
    autoexec = filesystem.read_file("autoexec.f").decode("utf-8")
    assert autoexec.count(MP64FS_VFS_PLATFORM_BOOT_LINE) == 1
    assert autoexec.index("ENTER-USERLAND") < autoexec.index(
        MP64FS_VFS_PLATFORM_BOOT_LINE
    ) < autoexec.index("REQUIRE tui/applets/pad/pad.f")


def test_vfs_ram_capacity_profile_packages_its_exact_contract_leaf() -> None:
    profile = PROFILES["vfs-ram-capacity-contracts"]
    assert profile.roots == ("utils/fs/vfs.f",)
    assert profile.ready_markers == ("VFS RAM CAPACITY PASS",)
    assert profile.stable_markers == profile.ready_markers
    assert {
        "VFS RAM CAPACITY FAIL",
        "VFS RAM CAPACITY ASSERT",
        "VFS RAM CAPACITY STACK",
        "dictionary full",
        "exception",
    } <= set(profile.failure_markers)
    assert tuple(path for path, _ in profile.initial_files) == (
        "local_testing/vfs-ram-capacity.f",
    )
    closure = set(dependency_closure(profile.roots))
    assert "utils/fs/vfs.f" in closure
    assert all(not module.startswith("library/") for module in closure)

    linked_autoexec = _linked_autoexec(
        profile.autoexec,
        (".akashic/link-00.f",),
        ("utils/fs/vfs.f",),
    )
    assert linked_autoexec.index("ENTER-USERLAND") < linked_autoexec.index(
        "REQUIRE .akashic/link-00.f"
    ) < linked_autoexec.index("REQUIRE local_testing/vfs-ram-capacity.f")


def test_ext4_binding_has_a_bounded_headless_dependency_closure() -> None:
    order = dependency_order(("utils/fs/drivers/vfs-ext4.f",))
    assert order == (
        "concurrency/event.f",
        "concurrency/semaphore.f",
        "concurrency/guard.f",
        "text/utf8.f",
        "utils/uint-range.f",
        "utils/memory-span.f",
        "utils/fs/vfs.f",
        "utils/bitset.f",
        "math/crc.f",
        "utils/fs/drivers/ext4/vfs-ext4-admission.f",
        "utils/fs/drivers/ext4/vfs-ext4-descriptor.f",
        "utils/fs/drivers/ext4/vfs-ext4-bitmap.f",
        "utils/fs/drivers/ext4/vfs-ext4-inode.f",
        "utils/fs/drivers/ext4/vfs-ext4-xattr.f",
        "utils/fs/drivers/ext4/vfs-ext4-orphan.f",
        "utils/fs/drivers/ext4/vfs-ext4-backups.f",
        "utils/fs/drivers/ext4/vfs-ext4-dirhash.f",
        "utils/fs/drivers/ext4/vfs-ext4-dirent.f",
        "utils/fs/drivers/ext4/vfs-ext4-jbd2-codec.f",
        "utils/fs/drivers/ext4/vfs-ext4-jbd2-map.f",
        "utils/fs/drivers/ext4/vfs-ext4-jbd2-revoke.f",
        "utils/fs/drivers/vfs-ext4.f",
    )
    assert tuple(dependency_closure(("utils/fs/drivers/vfs-ext4.f",))) == (
        "concurrency/event.f",
        "concurrency/guard.f",
        "concurrency/semaphore.f",
        "math/crc.f",
        "text/utf8.f",
        "utils/bitset.f",
        "utils/fs/drivers/ext4/vfs-ext4-admission.f",
        "utils/fs/drivers/ext4/vfs-ext4-backups.f",
        "utils/fs/drivers/ext4/vfs-ext4-bitmap.f",
        "utils/fs/drivers/ext4/vfs-ext4-descriptor.f",
        "utils/fs/drivers/ext4/vfs-ext4-dirent.f",
        "utils/fs/drivers/ext4/vfs-ext4-dirhash.f",
        "utils/fs/drivers/ext4/vfs-ext4-inode.f",
        "utils/fs/drivers/ext4/vfs-ext4-jbd2-codec.f",
        "utils/fs/drivers/ext4/vfs-ext4-jbd2-map.f",
        "utils/fs/drivers/ext4/vfs-ext4-jbd2-revoke.f",
        "utils/fs/drivers/ext4/vfs-ext4-orphan.f",
        "utils/fs/drivers/ext4/vfs-ext4-xattr.f",
        "utils/fs/drivers/vfs-ext4.f",
        "utils/fs/vfs.f",
        "utils/memory-span.f",
        "utils/uint-range.f",
    )

    identities: list[str] = []
    for module in order:
        matches = PROVIDED_RE.findall(
            (SOURCE_ROOT / module).read_text(encoding="utf-8")
        )
        assert len(matches) == 1, module
        identities.append(matches[0])
    assert len({module_key(identity) for identity in identities}) == len(
        identities
    )


def test_supported_desktop_smoke_defaults_cover_linked_network_boot() -> None:
    args = _parser().parse_args(["smoke", "--profile", "desktop"])
    assert args.max_steps is None
    assert args.timeout is None
    assert _smoke_limits(args.profile, args.max_steps, args.timeout) == (
        15_000_000_000,
        420.0,
    )
    assert DEFAULT_SMOKE_MAX_STEPS == 9_000_000_000
    assert DEFAULT_SMOKE_TIMEOUT == 120.0
    explicit = _parser().parse_args(
        [
            "smoke",
            "--profile",
            "desktop",
            "--max-steps",
            "123",
            "--timeout",
            "4.5",
        ]
    )
    assert _smoke_limits(
        explicit.profile, explicit.max_steps, explicit.timeout
    ) == (123, 4.5)


def test_live_streams_pump_does_not_idle_between_connector_steps() -> None:
    autoexec = PROFILES["streams-live-public"].autoexec
    loop = autoexec.split("MS@ 75000 + _slp-deadline !", 1)[1].split(
        "UNTIL", 1
    )[0]
    executable_lines = [
        code
        for line in loop.splitlines()
        if (code := line.split("\\", 1)[0].strip())
    ]
    assert "NET-IDLE" not in executable_lines
    service_index = executable_lines.index("_slp-service XIO-TICK")
    assert executable_lines[service_index:service_index + 3] == [
        "_slp-service XIO-TICK",
        "_slp-inst @ STREAMS-TICK-CB",
        "YIELD?",
    ]


def test_full_line_comments_follow_megapad_prefix_rule() -> None:
    assert _minify_forth("\\TOKEN DROP\n") == ""
    assert _minify_forth("  \\TOKEN DROP\n") == ""
    assert _minify_forth("S\\TOKEN DROP\n") == "S\\TOKEN DROP\n"


def test_only_ascii_space_is_a_megapad_source_delimiter() -> None:
    assert _minify_forth("\t\\ comment\n") == "\t\\ comment\n"
    assert _minify_forth(" \t\\ comment\n") == "\t\\ comment\n"
    assert _minify_forth("\N{NO-BREAK SPACE}42\n") == "\N{NO-BREAK SPACE}42\n"


def test_dependency_markers_require_ascii_space_separation() -> None:
    assert REQUIRE_RE.match("REQUIRE module.f")
    assert PROVIDED_RE.match("PROVIDED module-id")
    assert REQUIRE_RE.match("REQUIRE\tmodule.f") is None
    assert PROVIDED_RE.match("PROVIDED\tmodule-id") is None


def test_inline_comments_and_parser_word_input_remain_intact() -> None:
    sources = (
        "1 2 + \\ comment\n",
        ": \\ 42 ;\n",
        "CREATE \\ 8 ALLOT\n",
        "1 1 1 BUFFER \\ 8 ALLOT\n",
        "DNS-LOOKUP \\ DROP\n",
        "[CHAR] \\ EMIT ;\n",
        'S" a \\ path" DROP  \\ comment\n',
    )
    for source in sources:
        assert _minify_forth(source) == source


def test_only_flat_colon_header_stack_effect_is_removed() -> None:
    assert _minify_forth(": INC ( n -- n+1 ) 1+ ;\n") == (
        ": INC 1+ ;\n"
    )
    assert _minify_forth(": INC ( n -- n+1 )1+ ;\n") == (
        ": INC 1+ ;\n"
    )
    assert _minify_forth("64 CONSTANT XT \\ ( x -- y )\n") == (
        "64 CONSTANT XT \\ ( x -- y )\n"
    )
    assert _minify_forth("( x -- y )\n") == "( x -- y )\n"
    nested = ": INC ( n ( nested ) -- n+1 ) 1+ ;\n"
    assert _minify_forth(nested) == nested


def test_stack_looking_strings_and_unterminated_strings_are_preserved() -> None:
    source = 'S" literal ( x -- y ) text" DROP  \\ comment\n'
    assert _minify_forth(source) == source
    source = '0 ABORT" literal ( x -- y ) text" \\ comment\n'
    assert _minify_forth(source) == source
    source = 'S" unterminated   \n'
    assert _minify_forth(source) == source
    source = '." unterminated   \n'
    assert _minify_forth(source) == source
    source = '0 ABORT" unterminated   \n'
    assert _minify_forth(source) == source


def test_indentation_removal_does_not_touch_string_spaces() -> None:
    source = '    S"   retained text" DROP  \\ comment\n'
    assert _minify_forth(source) == (
        'S"   retained text" DROP  \\ comment\n'
    )


def test_conditional_control_tokens_are_never_compacted_out() -> None:
    for token in ("[IF]", "[ELSE]", "[THEN]", "[then]"):
        comment = f"  \\ skipped {token} marker\n"
        assert _minify_forth(comment) == comment.lstrip(" ")
        stack_effect = f": WORD ( -- {token} ) ;\n"
        assert _minify_forth(stack_effect) == stack_effect


def test_audited_line_coalescer_preserves_order_and_byte_ceiling() -> None:
    source = b"one two\nthree four\nfive six\nseven eight\n"
    coalesced = _coalesce_audited_forth_lines(source, 20)
    lines = coalesced.splitlines()

    assert coalesced == b"one two three four\nfive six seven eight\n"
    assert all(len(line) <= 20 for line in lines)
    assert b" ".join(lines).split() == source.split()
    assert coalesced.endswith(b"\n")
    with pytest.raises(RuntimeError, match="exceeds 20 bytes"):
        _coalesce_audited_forth_lines(b"x" * 21 + b"\n", 20)
    with pytest.raises(ValueError, match="between 1 and 255"):
        _coalesce_audited_forth_lines(
            source,
            MEGAPAD_EVALUATE_SOURCE_MAX_BYTES + 1,
        )


def test_audited_line_coalescer_isolates_module_and_comment_barriers() -> None:
    source = (
        b"before\n"
        b"PROVIDED exact-module\n"
        b"middle\n"
        b"1 DROP \\ keep the physical end of line\n"
        b"after\n"
    )
    assert _coalesce_audited_forth_lines(source, 240).splitlines() == [
        b"before",
        b"PROVIDED exact-module",
        b"middle",
        b"1 DROP \\ keep the physical end of line",
        b"after",
    ]


def test_audited_line_coalescer_removes_only_split_colon_stack_effects() -> None:
    source = (
        b": EXACT-WORD\n"
        b"( value -- value )\n"
        b"DUP ;\n"
        b"( ordinary parenthesized input ) DROP\n"
    )
    assert _coalesce_audited_forth_lines(source, 240).splitlines() == [
        b": EXACT-WORD DUP ;",
        b"( ordinary parenthesized input ) DROP",
    ]
    for non_comment in (
        b"(value -- value )",
        b"(\tvalue -- value )",
        b"( -- value )\t",
    ):
        source = b": EXACT-WORD\n" + non_comment + b"\nDUP ;\n"
        assert non_comment in _coalesce_audited_forth_lines(source, 240)


@pytest.mark.parametrize(
    "parser_line",
    (
        b"( parenthesized parser input ) DROP",
        b'S" string parser input" 2DROP',
        b'C" counted parser input" DROP',
        b'." output parser input"',
        b'0 ABORT" abort parser input"',
        b".( immediate output parser input )",
    ),
)
def test_audited_line_coalescer_isolates_delimiter_parsers(
    parser_line: bytes,
) -> None:
    source = b"before\n" + parser_line + b"\nafter\n"
    assert _coalesce_audited_forth_lines(source, 240).splitlines() == [
        b"before",
        parser_line,
        b"after",
    ]


@pytest.mark.parametrize(
    "conditional",
    ("[IF]", "[ELSE]", "[THEN]"),
)
def test_audited_line_coalescer_isolates_conditional_tokens(
    conditional: str,
) -> None:
    assert conditional in FORTH_LINE_COALESCE_BARRIERS
    source = f"before\n1 {conditional} DROP\nafter\n".encode("ascii")
    assert _coalesce_audited_forth_lines(source, 240).splitlines() == [
        b"before",
        f"1 {conditional} DROP".encode("ascii"),
        b"after",
    ]


def test_only_stage4_profile_opts_into_audited_line_coalescing() -> None:
    stage4 = PROFILES["sandbox-stage4-desk-service"]
    assert (
        stage4.audited_link_line_bytes
        == MEGAPAD_EVALUATE_SOURCE_MAX_BYTES
    )
    assert (
        stage4.audited_initial_forth_line_bytes
        == MEGAPAD_EVALUATE_SOURCE_MAX_BYTES
    )
    assert all(
        profile.audited_link_line_bytes is None
        for name, profile in PROFILES.items()
        if name != "sandbox-stage4-desk-service"
    )
    assert all(
        profile.audited_initial_forth_line_bytes is None
        for name, profile in PROFILES.items()
        if name != "sandbox-stage4-desk-service"
    )


def test_ordinary_streams_excludes_public_network_composition() -> None:
    closure = dependency_closure(("tui/applets/streams/streams.f",))
    modules = set(closure)
    assert "tui/applets/streams/public-provider.f" in modules
    assert "tui/applets/streams/bluesky-public.f" not in modules
    assert "atproto/public-author-feed.f" not in modules
    assert "atproto/public-trust.f" not in modules
    assert "net/transports/kdos-tls.f" not in modules
    assert not _requires_megapad_networking(closure)


def test_watched_page_composes_reusable_non_networking_boundaries() -> None:
    closure = dependency_closure(("tui/applets/streams/page-snapshot.f",))
    modules = set(closure)
    assert {
        "markup/readable-text.f",
        "net/media-type.f",
        "math/sha3.f",
        "tui/applets/streams/page-snapshot.f",
    } <= modules
    assert not _requires_megapad_networking(closure)

    for reusable_root in ("markup/readable-text.f", "net/media-type.f"):
        reusable = set(dependency_closure((reusable_root,)))
        assert all(not module.startswith("tui/") for module in reusable)
        assert all(not module.startswith("agent/") for module in reusable)
        assert all(not module.startswith("practice/") for module in reusable)
        assert all("vfs" not in module for module in reusable)
        assert not _requires_megapad_networking(tuple(reusable))


def test_http_resource_stays_transport_and_application_neutral() -> None:
    closure = dependency_closure(("net/http-resource.f",))
    modules = set(closure)
    assert {
        "net/external-io.f",
        "net/http-buffered.f",
        "net/http-resource.f",
        "net/http-target.f",
        "net/media-type.f",
    } <= modules
    assert "net/transports/kdos-tls.f" not in modules
    assert "net/tls-trust-registry.f" not in modules
    assert all(not module.startswith("tui/") for module in modules)
    assert all(not module.startswith("agent/") for module in modules)
    assert all(not module.startswith("practice/") for module in modules)
    assert not _requires_megapad_networking(closure)


def test_explicit_bluesky_composition_still_does_not_supply_trust() -> None:
    closure = dependency_closure(("tui/applets/streams/bluesky-public.f",))
    modules = set(closure)
    assert "tui/applets/streams/streams.f" in modules
    assert "atproto/public-author-feed.f" in modules
    assert "net/transports/kdos-tls.f" in modules
    assert "atproto/public-trust.f" not in modules
    assert _requires_megapad_networking(closure)


def test_focused_desktop_streams_uses_online_composition() -> None:
    profile = PROFILES["desktop-streams"]
    assert "tui/applets/streams/streams-online.f" in profile.roots
    assert "_boot-streams-desc STREAMS-ONLINE-ENTRY" in profile.autoexec
    assert "_boot-streams-desc STREAMS-ENTRY\n" not in profile.autoexec


def test_desk_library_burrow_profile_is_product_composed() -> None:
    profile = PROFILES["desktop-library-burrow"]
    rabbit = "tui/applets/streams/rabbit-capabilities.f"
    streams = "tui/applets/streams/streams.f"

    assert profile.roots == (
        "tui/applets/desk/desk.f",
        "tui/applets/library/library.f",
        rabbit,
        streams,
        "tui/applets/agent/agent.f",
        "tui/applets/agent/providers/devtools/scripted.f",
    )
    assert profile.resources == (
        "tui/applets/desk/desk.toml",
        "tui/applets/library/library.uidl",
        "tui/applets/streams/streams.uidl",
        "tui/applets/agent/agent.uidl",
    )
    assert profile.linked is True
    assert profile.include_large_sample is False
    assert profile.total_sectors == PROFILES["desktop"].total_sectors == 8192
    assert tuple(path for path, _ in profile.initial_files) == (
        "local_testing/streams-burrow-prov.f",
        "local_testing/desk-library-burrow.f",
    )
    assert profile.autoexec.index(f"REQUIRE {rabbit}") < (
        profile.autoexec.index(f"REQUIRE {streams}")
    )
    assert profile.autoexec.index("_boot-practice-provision") < (
        profile.autoexec.index("DESK-LIBRARY-BURROW-CONFIGURE")
    ) < profile.autoexec.index("DESK-LIBRARY-BURROW-RUN")
    assert "DESK-QUEUE-LAUNCH" not in profile.autoexec
    assert "Rabbit" not in PROFILES["desktop"].autoexec

    closure = set(dependency_closure(profile.roots))
    assert {
        "tui/applets/desk/desk.f",
        "tui/applets/library/library.f",
        rabbit,
        streams,
        "tui/applets/agent/agent.f",
    } <= closure


def test_streams_vertical_binds_both_reviewed_live_providers() -> None:
    profile = PROFILES["desktop-streams-vertical"]
    reviewed_url = (
        "https://foo-dogsquared.github.io/"
        "hugo-theme-more-contentful/feed.rss"
    )
    assert profile.requires_tap
    assert "atproto/public-trust.f" in profile.roots
    assert "ATPUBLIC-TRUST-REGISTER" in profile.autoexec
    assert (
        "STREAMS-ONLINE-ENTRY-WITH-CONFIGURED" in profile.autoexec
    )
    assert (
        "STREAMS-CONFIGURED-SYNDICATION-NEW-AUTHORIZED"
        in profile.autoexec
    )
    assert reviewed_url in profile.autoexec
    for module in (
        "tui/applets/streams/streams.f",
        "tui/applets/streams/streams-online.f",
        "tui/applets/streams/syndication-http.f",
        "atproto/public-author-feed.f",
    ):
        assert reviewed_url not in (SOURCE_ROOT / module).read_text(
            encoding="utf-8"
        )


def test_networking_boot_load_follows_userland_entry() -> None:
    autoexec = "\\ test autoexec\nENTER-USERLAND\nREQUIRE app.f\n"
    integrated = _with_megapad_networking(autoexec)
    assert integrated == (
        "\\ test autoexec\n"
        "ENTER-USERLAND\n"
        f"{MEGAPAD_NETWORKING_BOOT_LINE}\n"
        "REQUIRE app.f\n"
    )


def test_existing_networking_boot_load_is_idempotent() -> None:
    autoexec = (
        "ENTER-USERLAND\n"
        f"{MEGAPAD_NETWORKING_BOOT_LINE}\n"
        "REQUIRE app.f\n"
    )
    assert _with_megapad_networking(autoexec) == autoexec


def test_existing_networking_boot_load_uses_forth_token_rules() -> None:
    autoexec = (
        "enter-userland \\ enter first\n"
        "require  networking.f \\ canonical userland load\n"
        "REQUIRE app.f\n"
    )
    assert _with_megapad_networking(autoexec) == autoexec


@pytest.mark.parametrize(
    "autoexec",
    (
        "FSLOAD networking.f\nENTER-USERLAND\nREQUIRE app.f\n",
        "ENTER-USERLAND\nREQUIRE app.f\nFSLOAD networking.f\n",
        "ENTER-USERLAND\nfsload  networking.f \\ unsafe\n",
        "ENTER-USERLAND\n0 IF FSLOAD networking.f THEN\n",
        (
            "ENTER-USERLAND\n"
            "FSLOAD networking.f\n"
            "FSLOAD networking.f\n"
        ),
    ),
)
def test_networking_boot_load_rejects_legacy_fsload(autoexec: str) -> None:
    with pytest.raises(RuntimeError, match="FSLOAD networking.f is unsafe"):
        _with_megapad_networking(autoexec)


@pytest.mark.parametrize(
    "autoexec",
    (
        "REQUIRE networking.f\nENTER-USERLAND\nREQUIRE app.f\n",
        "ENTER-USERLAND\nREQUIRE app.f\nREQUIRE networking.f\n",
        "ENTER-USERLAND\nREQUIRE networking.f DROP\n",
        "ENTER-USERLAND\nREQUIRE NETWORKING.F\n",
        (
            "ENTER-USERLAND\n"
            "REQUIRE networking.f\n"
            "REQUIRE networking.f\n"
        ),
    ),
)
def test_networking_boot_load_rejects_unsafe_placement(autoexec: str) -> None:
    with pytest.raises(RuntimeError, match="exactly once"):
        _with_megapad_networking(autoexec)


def test_direct_web_response_requires_native_networking() -> None:
    closure = dependency_closure(("web/response.f",))
    assert _requires_megapad_networking(closure)


def test_rich_terminal_boot_load_follows_networking_and_owns_capacities() -> None:
    autoexec = (
        "ENTER-USERLAND\n"
        f"{MEGAPAD_NETWORKING_BOOT_LINE}\n"
        "REQUIRE coldsrc.f\n"
    )
    integrated = _with_megapad_rich_terminal(
        autoexec, DESKTOP_APT1_RICH_TERMINAL
    )
    expected_prefix = (
        "ENTER-USERLAND\n"
        f"{MEGAPAD_NETWORKING_BOOT_LINE}\n"
        f"{MEGAPAD_RICH_TERMINAL_BOOT_LINE}\n"
        "8192 CONSTANT APT1-DESK-RX-CAPACITY\n"
        "8192 CONSTANT APT1-DESK-TX-CAPACITY\n"
        "32 CONSTANT APT1-DESK-RTAPT-OWNER-RECORDS\n"
        "32 CONSTANT APT1-DESK-RTAPT-OP-RECORDS\n"
        "2304 CONSTANT APT1-DESK-RTAPT-COPY-BYTES\n"
        "32 CONSTANT APT1-DESK-RTERM-BINDING-RECORDS\n"
    )
    assert integrated.startswith(expected_prefix)
    assert integrated.endswith("REQUIRE coldsrc.f\n")
    for line in expected_prefix.splitlines()[2:]:
        assert integrated.count(line) == 1
    assert (
        _with_megapad_rich_terminal(
            integrated, DESKTOP_APT1_RICH_TERMINAL
        )
        == integrated
    )

    changed = integrated.replace(
        "32 CONSTANT APT1-DESK-RTAPT-OP-RECORDS",
        "31 CONSTANT APT1-DESK-RTAPT-OP-RECORDS",
    )
    with pytest.raises(RuntimeError, match="exactly once after networking"):
        _with_megapad_rich_terminal(changed, DESKTOP_APT1_RICH_TERMINAL)


@pytest.mark.parametrize(
    ("field", "value", "error"),
    tuple(
        (field, value, error)
        for field in (
            "guest_owner_records",
            "guest_operation_records",
            "guest_operation_copy_bytes",
            "guest_uidl_binding_records",
        )
        for value, error in (
            (0, ValueError),
            (-1, ValueError),
            (0x1_0000_0000, ValueError),
            (True, TypeError),
            ("1", TypeError),
        )
    ),
)
def test_rich_terminal_profile_rejects_invalid_guest_storage_capacities(
    field: str,
    value: object,
    error: type[Exception],
) -> None:
    with pytest.raises(error):
        replace(DESKTOP_APT1_RICH_TERMINAL, **{field: value})


def test_desktop_apt1_profile_has_complete_additive_rich_closure() -> None:
    baseline = PROFILES["desktop"]
    profile = PROFILES["desktop-apt1"]
    assert baseline.rich_terminal is None
    assert profile.rich_terminal is DESKTOP_APT1_RICH_TERMINAL
    expected_roots = tuple(
        "tui/desk-apt1.f"
        if root == "tui/applets/desk/desk.f"
        else root
        for root in baseline.roots
    )
    assert profile.roots == expected_roots
    assert profile.rich_terminal is not None
    assert profile.rich_terminal.retained_policy is None
    assert "--retained-terminal-policy" not in (
        _rich_terminal_server_arguments(profile)
    )

    rich_modules = {
        "tui/desk-apt1.f",
        "tui/app-shell-apt1.f",
        "tui/screen-backend-apt1.f",
        "tui/rich-terminal/apt1-engine.f",
        "tui/rich-terminal/engine.f",
        "tui/rich-terminal/engine-apt1.f",
        "tui/rich-terminal/screen-adapter-apt1.f",
        "tui/rich-terminal/uidl-driver.f",
        "tui/rich-terminal/uidl-projector.f",
    }
    baseline_closure = set(dependency_order(baseline.roots))
    rich_closure = set(dependency_order(profile.roots))
    assert rich_modules.isdisjoint(baseline_closure)
    assert rich_modules <= rich_closure
    assert rich_closure - baseline_closure == rich_modules
    assert MEGAPAD_RICH_TERMINAL_MODULE not in baseline_closure
    assert MEGAPAD_RICH_TERMINAL_MODULE not in rich_closure


def test_desktop_apt1_build_is_an_external_additive_composition(
    tmp_path: Path,
) -> None:
    baseline = PROFILES["desktop"]
    profile = PROFILES["desktop-apt1"]
    assert baseline.rich_terminal is None
    assert "tui/applets/desk/desk.f" in baseline.roots
    assert "tui/desk-apt1.f" not in baseline.roots
    assert profile.rich_terminal is DESKTOP_APT1_RICH_TERMINAL
    assert "tui/desk-apt1.f" in profile.roots

    closure = dependency_order(profile.roots)
    assert _requires_megapad_rich_terminal(closure)
    assert MEGAPAD_RICH_TERMINAL_MODULE not in closure
    assert "tui/screen-backend-apt1.f" in closure
    assert "tui/app-shell-apt1.f" in closure

    image = build_image(
        "desktop-apt1", tmp_path / "akashic-desktop-apt1.img"
    )
    filesystem = MP64FS(bytearray(image.read_bytes()))
    assert filesystem.read_file(MEGAPAD_RICH_TERMINAL_MODULE) == (
        pack_forth_source(
            (MEGAPAD_ROOT / MEGAPAD_RICH_TERMINAL_MODULE).read_bytes()
        )
    )
    assert filesystem.info()["free_sectors"] * 512 >= profile.minimum_free_bytes

    autoexec = filesystem.read_file("autoexec.f").decode("utf-8")
    ordered_boot = (
        autoexec.index(MEGAPAD_NETWORKING_BOOT_LINE),
        autoexec.index(MEGAPAD_RICH_TERMINAL_BOOT_LINE),
        autoexec.index("8192 CONSTANT APT1-DESK-RX-CAPACITY"),
        autoexec.index("32 CONSTANT APT1-DESK-RTAPT-OWNER-RECORDS"),
        autoexec.index("32 CONSTANT APT1-DESK-RTERM-BINDING-RECORDS"),
        autoexec.index(f"REQUIRE {COLD_SOURCE_LOADER_PATH}"),
    )
    assert ordered_boot == tuple(sorted(ordered_boot))
    assert "BEGIN IDLE AGAIN" in autoexec
    assert "PT-STREAM-OWNED? IF DROP _boot-rich-quarantine THEN" in autoexec
    assert "PT-STREAM-OWNED? IF BYE" not in autoexec

    packed_names = sorted(
        entry.name
        for entry in filesystem.list_files()
        if re.fullmatch(r"source-[0-9]{2}\.lz", entry.name)
    )
    linked_source = b"".join(
        _unpack_cold_source(filesystem.read_file(name))
        for name in packed_names
    ).decode("utf-8")
    assert "PROVIDED akashic-tui-desk-apt1" in linked_source
    assert "PROVIDED akashic-tui-screen-backend-apt1" in linked_source
    assert "PROVIDED rich-terminal.f" not in linked_source


def test_rich_terminal_consumers_select_boot_module_not_source_dependency() -> None:
    profile = PROFILES["desktop-apt1"]
    closure = dependency_order(profile.roots)

    assert _requires_megapad_rich_terminal(closure)
    assert MEGAPAD_RICH_TERMINAL_MODULE not in closure
    assert "tui/rich-terminal/screen-adapter-apt1.f" in (
        MEGAPAD_RICH_TERMINAL_CONSUMERS
    )
    assert "tui/rich-terminal/uidl-driver.f" not in (
        MEGAPAD_RICH_TERMINAL_CONSUMERS
    )
    assert MEGAPAD_RICH_TERMINAL_CONSUMERS <= set(closure)
    for module in MEGAPAD_RICH_TERMINAL_CONSUMERS:
        source = (SOURCE_ROOT / module).read_text(encoding="utf-8")
        assert not re.search(
            r"^\s*REQUIRE\s+\S*rich-terminal\.f\s*$",
            source,
            re.MULTILINE,
        )


def test_desktop_apt1_launchers_transfer_the_same_host_policy() -> None:
    baseline = PROFILES["desktop"]
    profile = PROFILES["desktop-apt1"]
    assert _rich_terminal_server_arguments(baseline) == []
    server_arguments = _rich_terminal_server_arguments(profile)
    assert server_arguments[0] == "--rich-terminal-policy"
    assert json.loads(server_arguments[1]) == (
        profile.rich_terminal.host_policy.to_dict()
    )

    with patch(
        "akashic_tui.MachineSession.from_bios",
        side_effect=RuntimeError("stop after configuration"),
    ) as from_bios:
        with pytest.raises(RuntimeError, match="stop after configuration"):
            smoke(
                "desktop-apt1",
                Path("unused.img"),
                cols=100,
                rows=32,
                max_steps=1,
                timeout=1.0,
            )
    assert from_bios.call_args.kwargs["rich_terminal"] == (
        profile.rich_terminal.configuration(100, 32)
    )


def test_rich_terminal_launchers_carry_explicit_retained_policy() -> None:
    profile = PROFILES["desktop-apt1"]
    assert profile.rich_terminal is not None
    host = profile.rich_terminal.host_policy
    retained = RetainedPolicy(
        features=RetainedFeature.CORE | RetainedFeature.CADENCE,
        max_owner_records=1,
        max_live_owners=1,
        max_regions=1,
        max_resources=0,
        max_objects=0,
        max_series=0,
        max_operations_per_transaction=1,
        max_resource_chunk_bytes=0,
        max_retained_transaction_bytes=host.maximum_transaction_bytes,
        total_resource_bytes=0,
        image_format=0,
        max_image_width=0,
        max_image_height=0,
        max_path_points=0,
        max_glyph_run_bytes=0,
        max_samples_per_append=0,
        max_history_per_series=0,
        minimum_presentation_interval_us=500_000,
        total_sample_slots=0,
        total_utf8_bytes=0,
        client_to_terminal_max_payload=3_212,
        terminal_to_client_max_payload=3_212,
        base_max_transaction_bytes=host.maximum_transaction_bytes,
    )
    enabled = replace(
        profile,
        rich_terminal=replace(
            profile.rich_terminal,
            retained_policy=retained,
        ),
    )

    arguments = _rich_terminal_server_arguments(enabled)
    assert arguments[2] == "--retained-terminal-policy"
    assert json.loads(arguments[3]) == retained.to_dict()
    assert enabled.rich_terminal.configuration(100, 32).retained_policy == retained


def test_desktop_apt1_smoke_rejects_fallback_and_terminal_loss() -> None:
    baseline = PROFILES["desktop"]
    profile = PROFILES["desktop-apt1"]
    assert _rich_terminal_smoke_ready(baseline, SimpleNamespace())

    def terminal(
        state: TerminalState,
        *,
        failure: str | None = None,
        lost: bool = False,
    ) -> SimpleNamespace:
        return SimpleNamespace(
            rich_terminal_state=state,
            rich_terminal_failure=failure,
            rich_terminal_lost=lost,
        )

    assert _rich_terminal_smoke_ready(
        profile, terminal(TerminalState.ACTIVE)
    )
    for rejected in (
        terminal(TerminalState.ANSI),
        terminal(TerminalState.PROBING),
        terminal(TerminalState.FAILED),
        terminal(TerminalState.ACTIVE, failure="host failure"),
        terminal(TerminalState.ACTIVE, lost=True),
    ):
        assert not _rich_terminal_smoke_ready(profile, rejected)


def test_retained_smoke_delegates_to_runtime_physical_gate() -> None:
    configured = SimpleNamespace(
        rich_terminal=SimpleNamespace(retained_policy=object()),
    )
    calls = []

    def session(*, retained_required: bool, ready: bool) -> SimpleNamespace:
        def output_revision_ready() -> bool:
            calls.append(ready)
            return ready

        return SimpleNamespace(
            rich_terminal_state=TerminalState.ACTIVE,
            rich_terminal_failure=None,
            rich_terminal_lost=False,
            retained_display_required=retained_required,
            _output_revision_ready=output_revision_ready,
        )

    assert not _rich_terminal_smoke_ready(
        configured,
        session(retained_required=False, ready=True),
    )
    assert calls == []
    assert not _rich_terminal_smoke_ready(
        configured,
        session(retained_required=True, ready=False),
    )
    assert _rich_terminal_smoke_ready(
        configured,
        session(retained_required=True, ready=True),
    )
    assert calls == [False, True]


def test_abstract_http_profile_omits_native_networking(
    tmp_path: Path,
) -> None:
    image = build_image("http-request", tmp_path / "akashic-http-request.img")
    filesystem = MP64FS(bytearray(image.read_bytes()))
    names = {entry.name for entry in filesystem.list_files()}
    assert "networking.f" not in names
    autoexec = filesystem.read_file("autoexec.f").decode("utf-8")
    assert MEGAPAD_NETWORKING_BOOT_LINE not in autoexec
    assert "FSLOAD networking.f" not in autoexec


def test_complete_desktop_fits_fixed_mp64fs_with_reserve(
    tmp_path: Path,
) -> None:
    image = build_image("desktop", tmp_path / "akashic-desktop.img")
    assert image.stat().st_size == 8192 * 512
    filesystem = MP64FS(bytearray(image.read_bytes()))
    info = filesystem.info()
    assert info["total_sectors"] == 8192
    assert info["free_sectors"] * 512 >= 1 << 20
    assert filesystem.read_file("networking.f") == pack_forth_source(
        (MEGAPAD_ROOT / "networking.f").read_bytes()
    )
    autoexec = filesystem.read_file("autoexec.f").decode("utf-8")
    assert "ENTER-USERLAND\nREQUIRE networking.f\n" in autoexec
    assert "FSLOAD networking.f" not in autoexec
    first_chunk = COLD_SOURCE_CHUNK_TEMPLATE.format(index=0)
    assert autoexec.index("REQUIRE networking.f") < autoexec.index(
        f"REQUIRE {COLD_SOURCE_LOADER_PATH}"
    )
    assert autoexec.index(f"_BOOT-COLD-SOURCE {first_chunk}") < autoexec.index(
        "_boot-practice-provision"
    ) < autoexec.index("DESK-RUN")

    packed_names = sorted(
        entry.name
        for entry in filesystem.list_files()
        if re.fullmatch(r"source-[0-9]{2}\.lz", entry.name)
    )
    assert packed_names and packed_names[0] == first_chunk
    linked_source = b"".join(
        _unpack_cold_source(filesystem.read_file(name))
        for name in packed_names
    ).decode("utf-8")
    assert linked_source.index("PROVIDED akashic-tui-mp64fs-vfs") < (
        linked_source.index("PROVIDED akashic-tui-app-shell")
    )


def test_codex_desktop_profiles_inherit_capacity_and_build(
    tmp_path: Path,
) -> None:
    for profile_name in ("desktop-codex", "desktop-codex-live"):
        profile = PROFILES[profile_name]
        assert profile.total_sectors == PROFILES["desktop"].total_sectors
        assert profile.cold_source_packed
        image = build_image(profile_name, tmp_path / f"{profile_name}.img")
        assert image.stat().st_size == 8192 * 512
        filesystem = MP64FS(bytearray(image.read_bytes()))
        assert filesystem.info()["free_sectors"] * 512 >= 1 << 20
