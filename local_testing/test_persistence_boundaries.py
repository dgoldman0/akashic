"""Ownership and state-boundary ratchets for neutral persistence."""

from __future__ import annotations

import re
from pathlib import Path

from forth_dependencies import dependency_markers
from refactor_inventory import _lexical_definitions


SOURCE_ROOT = Path(__file__).resolve().parents[1] / "akashic"
NEUTRAL_MODULES = (
    "persistence/core.f",
    "persistence/page-file.f",
    "persistence/segment.f",
    "persistence/atomic-root.f",
    "persistence/store.f",
)
LIBRARY_ADAPTER = "tui/applets/library/persistence-adapter.f"


def _source(module: str) -> str:
    return (SOURCE_ROOT / module).read_text(encoding="utf-8")


def test_neutral_persistence_has_no_applet_or_backend_policy() -> None:
    for module in NEUTRAL_MODULES:
        source = _source(module)
        assert re.search(r"\bLIB(?:RARY)?[-_.]", source, re.IGNORECASE) is None
        assert re.search(r"\bSTREAMS?[-_.]", source, re.IGNORECASE) is None
        assert re.search(r'S"\s*/', source) is None
        assert "ext4" not in source.lower()
        assert all(
            not marker.normalized.startswith("tui/")
            for marker in dependency_markers(source, module)
        )


def test_neutral_persistence_owns_no_hidden_operation_state() -> None:
    for module in NEUTRAL_MODULES:
        definitions = _lexical_definitions(_source(module))
        assert definitions["variable"] == []
        assert definitions["value"] == []
        assert definitions["defer"] == []
        assert definitions["xbuf"] == []
        assert definitions["guard"] == []
        assert all("MAGIC" in name for name in definitions["create"])


def test_store_uses_the_public_guard_contract() -> None:
    source = _source("persistence/store.f")
    assert "GUARD-SPIN-SIZE" in source
    assert "GUARD-SPIN?" in source
    assert re.search(r"\b_GRD[-.]", source) is None


def test_store_publishes_a_complete_layering_alias_boundary() -> None:
    store = _source("persistence/store.f")
    predicate = re.search(
        r":\s+PSTORE-SPAN-DISJOINT\?.*?;",
        store,
        re.DOTALL,
    )
    assert predicate is not None
    body = predicate.group(0)
    assert "PSTORE-SIZE" in body
    assert "VFS-DESC-SIZE" in body
    assert "PERSIST-STATS-SIZE" in body
    assert "PERSIST-PAGE-CACHE-SIZE" in body
    assert "PSTORE-SPIN-GUARD-SIZE" in body
    assert "_PSTORE-SPAN-DISJOINT-WORK?" in body

    adapter = _source(LIBRARY_ADAPTER)
    assert adapter.count("PSTORE-SPAN-DISJOINT?") >= 4
    assert re.search(r"\b_PST[-.]", adapter) is None


def test_segment_descriptor_rejects_vfs_stats_aliases() -> None:
    source = _source("persistence/segment.f")
    helper = re.search(
        r":\s+_PSEG-VFS-STATS-DISJOINT\?.*?;",
        source,
        re.DOTALL,
    )
    assert helper is not None
    assert "VFS-DESC-SIZE" in helper.group(0)
    assert "PERSIST-STATS-SIZE" in helper.group(0)
    assert "MSPAN-OVERLAP?" in helper.group(0)

    init_guard = source[
        source.index(": _PSEG-FILE-ARGS?") :
        source.index(": PSEG-FILE-VALID?")
    ]
    valid_guard = source[
        source.index(": PSEG-FILE-VALID?") :
        source.index(": PSEG-FILE-INIT")
    ]
    assert "_PSEG-VFS-STATS-DISJOINT?" in init_guard
    assert "_PSEG-VFS-STATS-DISJOINT?" in valid_guard


def test_l10_library_slice_is_applet_owned_and_non_authoritative() -> None:
    adapter = _source(LIBRARY_ADAPTER)
    definitions = _lexical_definitions(adapter)
    assert definitions["variable"] == []
    assert definitions["value"] == []
    assert definitions["defer"] == []
    assert definitions["xbuf"] == []
    assert definitions["guard"] == []
    assert definitions["create"] == ["_LIBPA-ROOT-MAGIC"]

    markers = {
        marker.normalized
        for marker in dependency_markers(adapter, LIBRARY_ADAPTER)
    }
    assert "persistence/store.f" in markers
    assert "tui/applets/library/record-codec.f" in markers
    assert "tui/applets/library/repository.f" not in markers
    assert "tui/applets/library/service.f" not in markers

    production_importers = []
    for path in SOURCE_ROOT.rglob("*.f"):
        module = path.relative_to(SOURCE_ROOT).as_posix()
        if module == LIBRARY_ADAPTER:
            continue
        if any(
            marker.normalized == LIBRARY_ADAPTER
            for marker in dependency_markers(path.read_text(encoding="utf-8"), module)
        ):
            production_importers.append(module)
    assert production_importers == []
