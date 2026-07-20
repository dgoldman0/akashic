"""Deployment-linker regressions for bootable Akashic images."""

from __future__ import annotations

import re
import sys
from pathlib import Path

import pytest


LOCAL_TESTING = Path(__file__).resolve().parent
if str(LOCAL_TESTING) not in sys.path:
    sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import (  # noqa: E402
    DEFAULT_SMOKE_MAX_STEPS,
    DEFAULT_SMOKE_TIMEOUT,
    LINK_CHUNK_BYTES,
    MEGAPAD_NETWORKING_BOOT_LINE,
    MEGAPAD_ROOT,
    PROFILES,
    PROVIDED_RE,
    REQUIRE_RE,
    SOURCE_ROOT,
    _linked_autoexec,
    _minify_forth,
    _matched_failure_markers,
    _parser,
    _requires_megapad_networking,
    _with_megapad_networking,
    build_image,
    dependency_closure,
)
from diskutil import MP64FS, pack_forth_source  # noqa: E402


def test_profile_failure_markers_are_checked_across_raw_and_screen_text() -> None:
    profile = PROFILES["library-model-codecs-contracts"]
    assert _matched_failure_markers(
        profile,
        "old raw output: LIBRARY MODEL CODECS ASSERT 9",
        "LIBRARY MODEL CODECS PASS 99",
    ) == ("LIBRARY MODEL CODECS ASSERT",)


def test_library_store_format_profile_packages_its_exact_contract_leaf() -> None:
    profile = PROFILES["library-store-format-contracts"]
    assert profile.roots == ("library/store-format.f",)
    assert profile.ready_markers == ("LIBRARY STORE FORMAT PASS",)
    assert profile.stable_markers == profile.ready_markers
    assert {
        "LIBRARY STORE FORMAT FAIL",
        "LIBRARY STORE FORMAT ASSERT",
        "dictionary full",
        "exception",
    } <= set(profile.failure_markers)
    assert tuple(path for path, _ in profile.initial_files) == (
        "local_testing/library-store-format.f",
    )

    closure = set(dependency_closure(profile.roots))
    assert {
        "library/model.f",
        "library/record-codec.f",
        "library/store-format.f",
    } <= closure
    assert all(not module.startswith("tui/") for module in closure)
    assert all(not module.startswith("agent/") for module in closure)
    assert all(not module.startswith("practice/") for module in closure)
    assert all("vfs" not in module for module in closure)


def test_library_vfs_store_profile_packages_its_exact_contract_leaf() -> None:
    profile = PROFILES["library-vfs-store-contracts"]
    assert profile.roots == ("library/vfs-store.f",)
    assert profile.ready_markers == ("LIBRARY VFS STORE PASS",)
    assert profile.stable_markers == profile.ready_markers
    assert profile.total_sectors == 8192
    assert {
        "LIBRARY VFS STORE FAIL",
        "LIBRARY VFS STORE ASSERT",
        "LIBRARY VFS STORE STACK",
        "dictionary full",
        "exception",
    } <= set(profile.failure_markers)
    assert tuple(path for path, _ in profile.initial_files) == (
        "local_testing/library-vfs-store.f",
    )

    closure = set(dependency_closure(profile.roots))
    assert {
        "library/model.f",
        "library/record-codec.f",
        "library/store-format.f",
        "library/vfs-store.f",
        "utils/fs/vfs-fixed-snapshot.f",
    } <= closure
    assert all(not module.startswith("tui/") for module in closure)
    assert all(not module.startswith("agent/") for module in closure)
    assert all(not module.startswith("practice/") for module in closure)


def test_library_managed_document_profile_packages_public_vertical_slice() -> None:
    profile = PROFILES["library-managed-document-contracts"]
    assert profile.roots == ("library/vfs-store.f",)
    assert profile.ready_markers == ("LIBRARY MANAGED PASS",)
    assert profile.stable_markers == profile.ready_markers
    assert profile.total_sectors == 8192
    assert {
        "LIBRARY MANAGED FAIL",
        "LIBRARY MANAGED ASSERT",
        "LIBRARY MANAGED STACK",
        "dictionary full",
        "exception",
    } <= set(profile.failure_markers)
    assert tuple(path for path, _ in profile.initial_files) == (
        "local_testing/library-managed.f",
    )

    closure = set(dependency_closure(profile.roots))
    assert {
        "library/model.f",
        "library/record-codec.f",
        "library/store-format.f",
        "library/vfs-store.f",
        "utils/fs/vfs-fixed-snapshot.f",
    } <= closure
    assert all(not module.startswith("tui/") for module in closure)
    assert all(not module.startswith("agent/") for module in closure)
    assert all(not module.startswith("practice/") for module in closure)


def test_library_managed_capacity_profile_packages_hard_limit_contracts() -> None:
    profile = PROFILES["library-managed-capacity-contracts"]
    assert profile.roots == ("library/vfs-store.f",)
    assert profile.ready_markers == ("LIBRARY MANAGED CAPACITY PASS",)
    assert profile.stable_markers == profile.ready_markers
    assert profile.total_sectors == 8192
    assert {
        "LIBRARY MANAGED CAPACITY FAIL",
        "LIBRARY MANAGED CAPACITY ASSERT",
        "LIBRARY MANAGED CAPACITY STACK",
        "dictionary full",
        "exception",
    } <= set(profile.failure_markers)
    assert tuple(path for path, _ in profile.initial_files) == (
        "local_testing/library-capacity.f",
    )

    closure = set(dependency_closure(profile.roots))
    assert {
        "library/model.f",
        "library/record-codec.f",
        "library/store-format.f",
        "library/vfs-store.f",
        "utils/fs/vfs-fixed-snapshot.f",
    } <= closure
    assert all(not module.startswith("tui/") for module in closure)
    assert all(not module.startswith("agent/") for module in closure)
    assert all(not module.startswith("practice/") for module in closure)


@pytest.mark.parametrize(
    ("profile_name", "marker", "guest_fixture"),
    (
        (
            "library-managed-lifecycle-contracts",
            "LIBRARY MANAGED LIFECYCLE PASS",
            "local_testing/library-lifecycle.f",
        ),
        (
            "library-capture-collection-contracts",
            "LIBRARY CAPTURE COLLECTION PASS",
            "local_testing/library-cc.f",
        ),
    ),
)
def test_library_milestone_two_profiles_package_headless_owner_contracts(
    profile_name: str,
    marker: str,
    guest_fixture: str,
) -> None:
    profile = PROFILES[profile_name]
    assert profile.roots == ("library/vfs-store.f",)
    assert profile.ready_markers == (marker,)
    assert profile.stable_markers == profile.ready_markers
    assert profile.total_sectors == 8192
    assert {
        marker.replace(" PASS", " FAIL"),
        marker.replace(" PASS", " ASSERT"),
        marker.replace(" PASS", " STACK"),
        "EVALUATE depth limit exceeded",
        "dictionary full",
        "exception",
    } <= set(profile.failure_markers)
    assert tuple(path for path, _ in profile.initial_files) == (guest_fixture,)

    closure = set(dependency_closure(profile.roots))
    assert {
        "library/model.f",
        "library/record-codec.f",
        "library/store-format.f",
        "library/vfs-store.f",
        "utils/fs/vfs-fixed-snapshot.f",
    } <= closure
    assert all(not module.startswith("tui/") for module in closure)
    assert all(not module.startswith("agent/") for module in closure)
    assert all(not module.startswith("practice/") for module in closure)
    assert all(not module.startswith("streams/") for module in closure)


def test_library_query_index_profile_packages_exact_headless_contract() -> None:
    profile = PROFILES["library-query-index-contracts"]
    assert profile.roots == ("library/vfs-store.f",)
    assert profile.resources == ()
    assert profile.ready_markers == ("LIBRARY QUERY INDEX PASS",)
    assert profile.stable_markers == profile.ready_markers
    assert profile.total_sectors == 8192
    assert {
        "LIBRARY QUERY INDEX FAIL",
        "LIBRARY QUERY INDEX ASSERT",
        "LIBRARY QUERY INDEX STACK",
        "EVALUATE depth limit exceeded",
        "dictionary full",
        "exception",
    } <= set(profile.failure_markers)
    assert tuple(path for path, _ in profile.initial_files) == (
        "local_testing/library-query-index.f",
    )
    assert "REQUIRE local_testing/library-query-index.f" in profile.autoexec

    closure = set(dependency_closure(profile.roots))
    assert {
        "library/model.f",
        "library/record-codec.f",
        "library/store-format.f",
        "library/vfs-store.f",
        "utils/fs/vfs-fixed-snapshot.f",
    } <= closure
    assert all(not module.startswith("tui/") for module in closure)
    assert all(not module.startswith("agent/") for module in closure)
    assert all(not module.startswith("practice/") for module in closure)
    assert all(not module.startswith("streams/") for module in closure)


def test_library_projection_owner_profile_packages_exact_headless_contract() -> None:
    profile = PROFILES["library-projection-owner-contracts"]
    assert profile.roots == (
        "library/projection-owner.f",
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
    assert "REQUIRE library/projection-owner.f" in profile.autoexec
    assert "REQUIRE interop/resource-client.f" in profile.autoexec
    assert "REQUIRE library/vfs-store.f" in profile.autoexec
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
        profile.autoexec.index("REQUIRE library/vfs-store.f")
    )
    assert profile.autoexec.index("REQUIRE library/vfs-store.f") < (
        profile.autoexec.index("REQUIRE library/projection-owner.f")
    )
    assert "REQUIRE local_testing/library-projection.f" in profile.autoexec
    fixture = profile.initial_files[0][1].decode("utf-8")
    assert ": _lpo-run" in fixture
    assert "_lpo-run\n" in fixture

    closure = set(dependency_closure(profile.roots))
    assert {
        "library/model.f",
        "library/record-codec.f",
        "library/store-format.f",
        "library/vfs-store.f",
        "library/projection-owner.f",
        "interop/resource-acquisition.f",
        "interop/resource-client.f",
        "interop/resource-contract.f",
        "interop/request-bus.f",
        "runtime/resource-registry.f",
        "utils/fs/vfs-fixed-snapshot.f",
    } <= closure
    production_closure = set(dependency_closure(("library/projection-owner.f",)))
    assert "library/projection-owner.f" in production_closure
    assert "interop/resource-client.f" not in production_closure
    assert production_closure <= closure
    assert all(
        not module.startswith("tui/applets/library/") for module in closure
    )
    assert all(
        not module.startswith("tui/applets/desk/") for module in closure
    )
    assert all(
        not module.startswith("tui/applets/pad/") for module in closure
    )
    assert all(
        not module.startswith("tui/applets/streams/") for module in closure
    )


def test_library_applet_profiles_package_a_standalone_public_lens() -> None:
    root = "tui/applets/library/library.f"
    resource = "tui/applets/library/library.uidl"
    interactive = PROFILES["library"]
    contracts = PROFILES["library-applet-contracts"]
    functional = PROFILES["library-applet-functional-contracts"]

    for profile in (interactive, contracts, functional):
        assert profile.roots == (root,)
        assert profile.resources == (resource,)
        assert profile.total_sectors == 8192
        assert profile.linked is True
        assert profile.link_chunk_bytes == LINK_CHUNK_BYTES
        assert profile.include_large_sample is False

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
    assert {
        "library/model.f",
        "library/record-codec.f",
        "library/store-format.f",
        "library/vfs-store.f",
        "tui/app-desc.f",
        "tui/app-shell.f",
        root,
    } <= closure
    assert all(
        module == root or not module.startswith("tui/applets/")
        for module in closure
    )
    assert all(not module.startswith("agent/") for module in closure)
    assert all(not module.startswith("practice/") for module in closure)
    assert all(not module.startswith("streams/") for module in closure)

    # The probe supplies only a TUI lens.  It must not silently become part
    # of the canonical Desktop image before projection ownership and image
    # capacity have their own explicit integration milestone.
    assert root not in PROFILES["desktop"].roots
    assert resource not in PROFILES["desktop"].resources


def test_library_applet_functional_fixture_drives_controller_not_store() -> None:
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
        )
    )
    assert "LIBRARY-VFS-STORE-" not in source


def test_library_applet_source_stays_above_public_storage_boundary() -> None:
    source = (SOURCE_ROOT / "tui/applets/library/library.f").read_text(
        encoding="utf-8"
    )
    direct_requires = set(REQUIRE_RE.findall(source))

    assert "../../../library/vfs-store.f" in direct_requires
    assert {
        requirement
        for requirement in direct_requires
        if requirement.startswith("../../../library/")
    } == {"../../../library/vfs-store.f"}
    assert not any(
        requirement.startswith("../../../utils/fs/")
        for requirement in direct_requires
    )
    assert all(
        word not in source
        for word in (
            " VFS-OPEN",
            " VFS-CREATE",
            " VFS-READ",
            " VFS-WRITE",
            " VFS-REPLACE",
            " DESK-",
            " PAD-",
            " FEXP-",
            " STREAMS-",
        )
    )
    assert "DRW-TEXT-UNTRUSTED" in source


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
    assert any(
        entry.name.startswith("link-")
        for entry in filesystem.list_files(parent=linked_parent)
    )
    fixture_parent = filesystem.resolve_path("/local_testing")
    assert filesystem.read_file(
        "library-app-func.f", parent=fixture_parent
    ) == _minify_forth((
        LOCAL_TESTING / "library-applet-functional.f"
    ).read_text(encoding="utf-8")).encode("utf-8")
    autoexec = filesystem.read_file("autoexec.f").decode("utf-8")
    assert "REQUIRE tui/applets/library/library.f" not in autoexec
    assert "REQUIRE .akashic/link-" in autoexec
    assert "REQUIRE local_testing/library-app-func.f" in autoexec
    assert filesystem.info()["free_sectors"] > 0


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
    assert tuple(dependency_closure(("utils/fs/drivers/vfs-ext4.f",))) == (
        "concurrency/event.f",
        "concurrency/guard.f",
        "concurrency/semaphore.f",
        "text/utf8.f",
        "utils/fs/drivers/vfs-ext4.f",
        "utils/fs/vfs.f",
        "utils/memory-span.f",
    )


def test_supported_desktop_smoke_defaults_cover_linked_network_boot() -> None:
    args = _parser().parse_args(["smoke", "--profile", "desktop"])
    assert args.max_steps == DEFAULT_SMOKE_MAX_STEPS == 8_000_000_000
    assert args.timeout == DEFAULT_SMOKE_TIMEOUT == 120.0


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
    assert autoexec.index("REQUIRE networking.f") < autoexec.index(
        "REQUIRE .akashic/link-"
    )


def test_codex_desktop_profiles_inherit_capacity_and_build(
    tmp_path: Path,
) -> None:
    for profile_name in ("desktop-codex", "desktop-codex-live"):
        profile = PROFILES[profile_name]
        assert profile.total_sectors == PROFILES["desktop"].total_sectors
        image = build_image(profile_name, tmp_path / f"{profile_name}.img")
        assert image.stat().st_size == 8192 * 512
        filesystem = MP64FS(bytearray(image.read_bytes()))
        assert filesystem.info()["free_sectors"] > 0
