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
    "persistence/btree.f",
    "persistence/blob.f",
    "persistence/reclaim.f",
    "persistence/compaction.f",
)
LIBRARY_ADAPTER = "tui/applets/library/persistence-adapter.f"


def _source(module: str) -> str:
    return (SOURCE_ROOT / module).read_text(encoding="utf-8")


def test_neutral_persistence_has_no_applet_or_backend_policy() -> None:
    for module in NEUTRAL_MODULES:
        source = _source(module)
        assert re.search(r"\bLIB(?:RARY)?[-_.]", source, re.IGNORECASE) is None
        assert re.search(r"\bSTREAMS?[-_.]", source, re.IGNORECASE) is None
        assert re.search(r"\blibrary\b", source, re.IGNORECASE) is None
        assert re.search(r"\bstreams\b", source, re.IGNORECASE) is None
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


def test_l11_index_blob_and_reclaim_boundaries_are_explicit() -> None:
    btree = _source("persistence/btree.f")
    assert "PBTREE-LEAF-CAPACITY" in btree
    assert "PBTREE-BRANCH-CAPACITY" in btree
    assert "PBTREE-THEORETICAL-CAPACITY-FOR-HEIGHT" in btree
    assert "PBTREE-BALANCED-CAPACITY-FOR-HEIGHT" in btree
    assert "PBTREE-HEIGHT-FOR" in btree
    assert "PBTREE-HIGH-WATER-ALLOCATE" in btree
    assert "PBTREE-RETIRED-PAGES$" in btree
    assert "PSTORE-WRITE-PAGE-TX" in btree
    assert "PSTORE-READ-PAGE-TX" in btree
    assert re.search(r"\b_PBTN[-.]NEXT", btree) is None
    assert "REQUIRE reclaim.f" not in btree

    blob = _source("persistence/blob.f")
    assert re.search(r"(?m)^32768\s+CONSTANT PBLOB-CHUNK-SIZE$", blob)
    assert "PBLOB-READ-RANGE" in blob
    assert "PBLOB-READ-RANGE-TX" in blob
    assert "PBLOB-STREAM" in blob
    assert "PSTORE-APPEND-RECORD" in blob
    assert "PSTORE-READ-RECORD-TX" in blob
    assert "PSTORE-BEGIN" not in blob
    assert "PSTORE-COMMIT" not in blob

    reclaim = _source("persistence/reclaim.f")
    assert re.search(r"(?m)^32\s+CONSTANT RECLAIM-MAX-BATCH$", reclaim)
    assert re.search(r"(?m)^64\s+CONSTANT RECLAIM-RETIRED-MAX$", reclaim)
    assert re.search(r"(?m)^64\s+CONSTANT RECLAIM-DISCARD-MAX$", reclaim)
    assert re.search(r"(?m)^128\s+CONSTANT RECLAIM-ALLOCATED-MAX$", reclaim)
    assert re.search(
        r"(?m)^2\s+CONSTANT RECLAIM-STEP-RETIREMENT-MAX$", reclaim
    )
    assert re.search(
        r"(?m)^1\s+CONSTANT RECLAIM-ALLOCATION-RETIREMENT-MAX$", reclaim
    )
    assert re.search(
        r"(?m)^4\s+CONSTANT RECLAIM-FINALIZE-RETIREMENT-MAX$", reclaim
    )
    for word in (
        "RECLAIM-TX-BEGIN",
        "RECLAIM-TX-ROOM?",
        "RECLAIM-CLAIM-HIGH-WATER",
        "RECLAIM-ALLOCATE",
        "RECLAIM-ALLOCATE-PROTECTED",
        "RECLAIM-RETIRE-BATCH",
        "RECLAIM-DISCARD-BATCH",
        "RECLAIM-RELEASE-BATCH",
        "RECLAIM-STEP",
        "RECLAIM-FINALIZE",
        "RECLAIM-ADOPT",
        "RECLAIM-ABORT",
        "RECLAIM-AUDIT-MAP-BYTES?",
        "RECLAIM-AUDIT-WORK-INIT",
        "RECLAIM-AUDIT-APPLICATION-ROOT!",
        "RECLAIM-AUDIT-STATE!",
        "RECLAIM-AUDIT-APPLICATION-PAGE",
        "RECLAIM-AUDIT-APPLICATION-COMPLETE",
        "RECLAIM-AUDIT-CURRENT",
        "RECLAIM-AUDITED-GENERATION@",
    ):
        assert word in reclaim
    assert (
        "( future-retirement-reserve reclaim-context store pstore-work"
        in reclaim
    )
    assert "-- page-id status )" in reclaim
    assert "PROOT-SLOT-GENERATION@" in reclaim
    assert "GPAIR-SLOT-A" in reclaim
    assert "GPAIR-SLOT-B" in reclaim
    assert "PSTORE-ROOT-SLOT@" in reclaim
    assert "PSTORE-READ-PAGE-SNAPSHOT-TX" in reclaim
    assert "PERSIST-PAGE-PAYLOAD-SIZE _RCA-BUCKET +" in reclaim
    assert (
        "( map-a map-u xt ctx reclaim store pstore-work audit-work -- status )"
        in reclaim
    )
    assert "_RCA-M-OLD-LIVE" in reclaim
    assert "_RCA-CLASSIFY-CURRENT" in reclaim
    assert "_RECLAIM-STATE-CANONICAL-EMPTY?" in reclaim
    assert "_RCL.AUDITED-GENERATION" in reclaim
    audit_entry = reclaim[
        reclaim.index(": RECLAIM-AUDIT-CURRENT") :
        reclaim.index(": _RECLAIM-RESERVE-FITS?")
    ]
    assert "R@ ['] _RCA-RUN CATCH" in audit_entry
    assert "DROP DROP PERSIST-S-FAULT" in audit_entry
    assert "R> _RCA-END" in audit_entry
    assert re.search(r"\b_PROOT[-.]", reclaim) is None
    assert re.search(r"(?m)^(?:VARIABLE|CREATE|VALUE|DEFER)\b", reclaim) is None
    assert "PSTORE-BEGIN" not in reclaim
    assert "PSTORE-COMMIT" not in reclaim
    assert "PSTORE-ABORT" not in reclaim
    assert "library" not in reclaim.lower()

    reclaim_runner = (
        Path(__file__).resolve().parent / "test_persistence_reclaim.py"
    ).read_text(encoding="utf-8")
    reclaim_fixture = (
        Path(__file__).resolve().parent / "persist-reclaim-test.f"
    ).read_text(encoding="utf-8")

    def return_stack_words_inside_do(source: str) -> list[str]:
        source = re.sub(r"(?m)\\.*$", "", source)
        source = re.sub(r"\([^)]*\)", "", source, flags=re.DOTALL)
        offenders: list[str] = []
        for definition in re.finditer(
            r"(?ms)^:\s+([^\s]+)(.*?);", source
        ):
            for loop_body in re.finditer(
                r"(?s)(?<!\S)(?:\?DO|DO)(?!\S)(.*?)(?<!\S)LOOP(?!\S)",
                definition.group(2),
            ):
                if re.search(
                    r"(?<!\S)(?:>R|R@|R>)(?!\S)", loop_body.group(1)
                ):
                    offenders.append(definition.group(1))
        return offenders

    assert return_stack_words_inside_do(reclaim) == []
    assert return_stack_words_inside_do(reclaim_fixture) == []
    assert "max_steps=4_000_000_000" in reclaim_runner
    assert "link_chunk_bytes=192 * 1024" in reclaim_runner
    for witness in (
        "_RB-audit-mirrored-once",
        "_RB-audit-cross-bank-max",
        "_RB-audit-role-cross",
        "_RB-audit-healthy-partial-out",
        "_RB-audit-healthy-mid-rotation",
        "_RB-audit-healthy-chained-ready",
        "_RB-audit-overlap-arguments",
        "_RB-audit-pstore-overlap-arguments",
        "_RB-audit-reentry",
        "_RECLAIM-BUCKET-READY _PSTC-page _RCB.KIND !",
        "1 _PSTC-page _RCB.GENERATION !",
    ):
        assert witness in reclaim_fixture


def test_snapshot_slot_and_btree_audit_authority_is_explicit() -> None:
    atomic_root = _source("persistence/atomic-root.f")
    store = _source("persistence/store.f")
    btree = _source("persistence/btree.f")

    assert "PROOT-SLOT@" in atomic_root
    assert (
        "( slot destination-root-value root work -- generation status )"
        in atomic_root
    )
    assert "PSTORE-ROOT-SLOT@" in store
    assert "PSTORE-SNAPSHOT-BOUND-TX?" in store
    assert "PSTORE-READ-PAGE-SNAPSHOT-TX" in store
    assert "_PSW.SNAPSHOT-ROOT-WORK" in store
    assert "_PSW.ROOT-WORK PROOT-SLOT@" not in store

    assert "PBTREE-AUDIT-PENDING-MAX" in btree
    assert "PBTREE-AUDIT-WORK-SIZE" in btree
    assert "PBTREE-AUDIT-WORK-INIT" in btree
    assert "PBTREE-AUDIT-SNAPSHOT-TX" in btree
    assert (
        "tree-root snapshot-generation snapshot-page-count snapshot-data-bank"
        in btree
    )
    assert (
        "visitor-xt visitor-context tree audit-work"
        " -- node-count row-count status"
        in btree
    )
    assert re.search(
        r"6 PICK _PBTR\.GENERATION @ 6 PICK <> IF",
        btree,
    )
    assert "_PBTA.PREVIOUS-KEY" in btree
    assert "_PBTA-CURRENT-HIGH?" in btree
    assert "_PBTA-NODE-OCCUPANCY?" in btree
    assert "_PBTA-SNAPSHOT-STILL-BOUND?" in btree
    assert "PSTORE-READ-PAGE-SNAPSHOT-TX" in btree
    assert (
        "PBTREE-AUDIT-WORK-SIZE OVER _PBTD.WORKING-BYTES @ MAX"
        in btree
    )
    reject = btree.split(": _PBTA-REJECT", 1)[1].split(
        ": _PBTA-PUSH", 1
    )[0]
    assert "R@ _PBTA.BUSY @ 0= IF" in reject
    assert "0 R@ _PBTA.BUSY !" not in reject
    push_children = btree.split(": _PBTA-PUSH-CHILDREN", 1)[1].split(
        ": _PBTA-ACCEPT-CURRENT", 1
    )[0]
    assert "R@" not in push_children
    assert "5 PICK _PBTA-PUSH" in push_children

    runner = (
        Path(__file__).resolve().parent
        / "test_persistence_snapshot_audit.py"
    ).read_text(encoding="utf-8")
    fixture = (
        Path(__file__).resolve().parent
        / "persist-snap-audit.f"
    ).read_text(encoding="utf-8")
    assert "max_steps=4_000_000_000" in runner
    assert "_PBTSA-bound-generation @ 1+" in fixture
    assert "PBTREE-WORKING-BYTES@" in fixture
    assert "PERSIST-DATA-BANK-0 = IF" in fixture
    assert "_PBTSA-bad-tree-root _PBTR.GENERATION +!" in fixture
    assert "PROOT-RECORD-SIZE" in fixture
    assert "PERSIST-S-CORRUPT 1 _PBTSA-audit" in fixture
    assert "PERSIST-S-FAULT 2 _PBTSA-audit" in fixture
    assert "_PBTSA-reentry" in fixture
    assert "PERSIST-S-OK 5 _PBTSA-audit" in fixture
    assert "_PBTSA-audit-work _PBTA.BUSY @ -1 =" in fixture
    assert "_PBTSA-rebinding" in fixture
    assert "PERSIST-S-CONFLICT 6 _PBTSA-audit" in fixture
    assert "_PBTSA-old-slot @ DUP _PBTSA-slot-root _PBTSA-read-slot" in fixture
    assert "_PBTSA-calls @ 1 =" in fixture


def test_l12_compaction_is_neutral_bounded_and_journal_free() -> None:
    source = _source("persistence/compaction.f")
    markers = {
        marker.normalized
        for marker in dependency_markers(source, "persistence/compaction.f")
    }
    assert markers == {"persistence/store.f"}

    for word in (
        "PCOMPACT-INIT",
        "PCOMPACT-WORK-INIT",
        "PCOMPACT-BEGIN",
        "PCOMPACT-STEP",
        "PCOMPACT-FINALIZE",
        "PCOMPACT-PUBLISH",
        "PCOMPACT-MIRROR",
        "PCOMPACT-CLEANUP",
        "PCOMPACT-ABORT",
        "PCOMPACT-RECOVER",
        "PCOMPACT-CLEANUP-ELIGIBLE?",
    ):
        assert word in source

    assert (
        "( source-root builder-store builder-work byte-allowance context"
        in source
    )
    assert (
        "( exact-next-generation builder-store builder-work context -- status )"
        in source
    )
    assert "PROOT-MIRROR" in source
    assert "PCOMPACT-STATE-UNCERTAIN" in source
    assert "PERSIST-S-CAPACITY" in source
    assert "phase journal" in source
    assert "REQUIRE btree.f" not in source
    assert "REQUIRE reclaim.f" not in source


def test_l12_library_slice_is_applet_owned_with_bounded_consumers() -> None:
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
    assert "tui/applets/library/index-keys.f" in markers
    assert "tui/applets/library/record-codec.f" not in markers
    assert "tui/applets/library/repository.f" not in markers
    assert "tui/applets/library/service.f" not in markers

    assert adapter.count(": LIBPA-INDEX-WORK-INIT") == 1
    assert (
        "( audit-map-a audit-map-cap pstore-work adapter work -- status )"
        in adapter
    )
    for witness in (
        "RECLAIM-AUDIT-WORK-SIZE",
        "PBTREE-AUDIT-WORK-SIZE",
        "RECLAIM-AUDIT-CURRENT",
        "PBTREE-AUDIT-SNAPSHOT-TX",
        "RECLAIM-AUDIT-APPLICATION-ROOT!",
        "RECLAIM-AUDIT-STATE!",
        "RECLAIM-AUDIT-APPLICATION-PAGE",
        "RECLAIM-AUDIT-APPLICATION-COMPLETE",
        "RECLAIM-AUDITED-GENERATION@",
        "PSTORE-ROOT-SLOT@",
        "PSTORE-READ-PAGE-SNAPSHOT-TX",
        "LIBPA-INDEX-AUDIT-MAP-CAPACITY@",
        "LIBPA-INDEX-AUDIT-MAP-REQUIRED@",
        "LIBPA-INDEX-AUDITED-GENERATION@",
    ):
        assert witness in adapter
    assert re.search(r"\b_(?:RCA|PBTA|PBTR|PST|PROOT|RCL)[-.]", adapter) is None

    audit_region = adapter[
        adapter.index(": _LIBPIX-AUDIT-ROOT?") :
        adapter.index(": _LIBPIX-LOAD-CURRENT")
    ]
    for definition in re.finditer(r"(?ms)^:\s+(\S+)(.*?);", adapter):
        body = definition.group(2)
        assert not (
            "R@" in body and re.search(r"(?<!\?)\bDO\b|\?DO", body)
        ), definition.group(1)
    assert "_LIBPIX.AUDIT-MAP-CAPACITY @ > IF" in audit_region
    assert "PERSIST-S-CAPACITY EXIT" in audit_region
    assert "PSTORE-ABORT" in audit_region

    open_run = adapter[
        adapter.index(": _LIBPIX-OPEN-RUN") :
        adapter.index(": LIBPA-INDEX-OPEN")
    ]
    root_decode = adapter[
        adapter.index(": _LIBPIX-ROOT>WORK") :
        adapter.index(": _LIBPIX-WORK>ROOT")
    ]
    assert "_LIBPIX-STATE-READY" not in root_decode
    assert "_LIBPIX-COLD-AUDIT" in open_run
    assert "RECLAIM-AUDITED-GENERATION@" in open_run
    assert open_run.index("RECLAIM-AUDITED-GENERATION@") < open_run.index(
        "_LIBPIX-STATE-READY"
    )

    focused_fixture = (
        Path(__file__).resolve().parent / "lib-persist-l12-test.f"
    ).read_text(encoding="utf-8")
    assert "_L12P-audit-map-cold _L12P-audit-map-capacity" in focused_fixture
    assert "LIBPA-INDEX-AUDITED-GENERATION@" in focused_fixture
    assert "LIBPA-INDEX-BEGIN" in focused_fixture
    assert "LIBPA-INDEX-ABORT" in focused_fixture
    assert "LIBPA-S-CAPACITY _L12P-status" in focused_fixture
    assert "_L12P-audit-map-small C@ 0xA5 =" in focused_fixture
    assert "_L12P-pwork-small PSTORE-PROPOSED-ROOT@ 0=" in focused_fixture
    assert "LIBPA-S-INVALID _L12P-status" in focused_fixture
    assert "_L12P-work-invalid C@ 0x5A =" in focused_fixture

    repository = _source("tui/applets/library/repository.f")
    assert repository.count(": LIBRARY-REPOSITORY-WORK-INIT") == 1
    assert "audit-map-a audit-map-cap builder-audit-map-a" in repository
    assert "_LRW.AUDIT-MAP-A @ R@ _LRW.AUDIT-MAP-U @" in repository
    assert (
        "_LRW.BUILDER-AUDIT-MAP-A @\n"
        "    R@ _LRW.BUILDER-AUDIT-MAP-U @"
        in repository
    )

    for path in SOURCE_ROOT.parent.rglob("*.f"):
        source = path.read_text(encoding="utf-8")
        relative = path.relative_to(SOURCE_ROOT.parent).as_posix()
        for word, defining_module in (
            ("LIBPA-INDEX-WORK-INIT", f"akashic/{LIBRARY_ADAPTER}"),
            (
                "LIBRARY-REPOSITORY-WORK-INIT",
                "akashic/tui/applets/library/repository.f",
            ),
        ):
            if relative == defining_module:
                continue
            for call in re.finditer(rf"\b{word}\b", source):
                preceding = source[max(0, call.start() - 320) : call.start()]
                upper = preceding.upper()
                assert (
                    "AUDIT-MAP" in upper or "WORK-INVALID 1" in upper
                ), (relative, word)

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
    assert sorted(production_importers) == [
        "tui/applets/library/query.f",
        "tui/applets/library/repository.f",
    ]
