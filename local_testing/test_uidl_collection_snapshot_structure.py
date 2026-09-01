#!/usr/bin/env python3
"""Seconds-scale architecture locks for canonical UIDL collection freezing."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "akashic/tui/uidl-collection-snapshot.f"


def _word(source: str, name: str) -> str:
    match = re.search(rf"(?ms)^:\s+{re.escape(name)}(?=\s).*?;", source)
    assert match, f"missing Forth word {name}"
    return match.group(0)


def _executable(source: str) -> str:
    return "\n".join(line.split("\\", 1)[0] for line in source.splitlines())


def test_snapshot_contract_is_pointer_free_uidl_keyed_and_renderer_neutral():
    source = SOURCE.read_text(encoding="utf-8")
    executable = _executable(source)

    assert re.findall(r"(?m)^REQUIRE (.+)$", source) == [
        "uidl-tui.f",
        "semantic-collections.f",
        "widgets/text-grid.f",
        "widgets/tabs.f",
        "../utils/memory-span.f",
    ]
    for declaration in (
        "0 CONSTANT UCSN-S-OK",
        "1 CONSTANT UCSN-S-CAPACITY",
        "2 CONSTANT UCSN-S-UNAVAILABLE",
        "3 CONSTANT UCSN-S-INVALID",
        "1 CONSTANT UCSN-SOURCE-UIDL",
        "152 CONSTANT UCSN-DESCRIPTOR-SIZE",
        "16 CONSTANT UCSN-WORK-SOURCE-ENTRY-SIZE",
        "UCSN-DESCRIPTOR-SIZE CONSTANT UCSN-WORK-NODE-SIZE",
    ):
        assert declaration in source

    descriptor_offsets = {
        "_UCSN-D.SOURCE": 0,
        "_UCSN-D.INDEX": 8,
        "_UCSN-D.GENERATION": 16,
        "_UCSN-D.NATIVE-O": 24,
        "_UCSN-D.ROW": 32,
        "_UCSN-D.COLUMN": 40,
        "_UCSN-D.HEIGHT": 48,
        "_UCSN-D.WIDTH": 56,
        "_UCSN-D.CLIP-ROW": 64,
        "_UCSN-D.CLIP-COLUMN": 72,
        "_UCSN-D.CLIP-HEIGHT": 80,
        "_UCSN-D.CLIP-WIDTH": 88,
        "_UCSN-D.Z": 96,
        "_UCSN-D.SUMMARY": 104,
    }
    for name, offset in descriptor_offsets.items():
        body = _word(source, name)
        if offset:
            assert f"{offset} +" in body
        else:
            assert "+" not in body.split("--", 1)[-1]

    public_fields = {
        "UCSN-DESCRIPTOR-SOURCE-GENERATION@": "_UCSN-D.GENERATION @",
        "UCSN-DESCRIPTOR-CLIP-ROW@": "_UCSN-D.CLIP-ROW @",
        "UCSN-DESCRIPTOR-CLIP-COLUMN@": "_UCSN-D.CLIP-COLUMN @",
        "UCSN-DESCRIPTOR-CLIP-HEIGHT@": "_UCSN-D.CLIP-HEIGHT @",
        "UCSN-DESCRIPTOR-CLIP-WIDTH@": "_UCSN-D.CLIP-WIDTH @",
    }
    for name, read in public_fields.items():
        assert read in _word(source, name)

    for forbidden in (
        "ALLOCATE",
        " FREE",
        "rich-terminal/",
        "applets/",
        "UTUI-PAINT",
        "UTUI-DRAW-COMPLETE",
        "ASHELL-PAINT",
        "WDG-DRAW",
        "WDG-DRAW-OBSERVE",
        "UTUI-SEMANTIC-",
        "APT-",
        "RTE-",
        "RUHA-",
        "PAD-",
        "DAYBOOK-",
        "WPTR",
    ):
        assert forbidden not in executable


def test_work_is_linear_by_source_with_dense_multi_root_runs():
    source = SOURCE.read_text(encoding="utf-8")
    sizing = _word(source, "UCSN-WORK-BYTES")
    link = _word(source, "_UCSN-V-LINK?")
    emit = _word(source, "_UCSN-EMIT-CANONICAL")
    emit_source = _word(source, "_UCSN-EMIT-SOURCE")

    assert "element-high-water descriptor-capacity" in sizing
    assert "UCSN-WORK-SOURCE-ENTRY-SIZE" in sizing
    assert "UCSN-WORK-NODE-SIZE" in sizing
    assert "_UCSN-WS.FIRST" in link
    assert "_UCSN-WS.COUNT" in link
    assert "UCSN-DESCRIPTOR-SOURCE-GENERATION@" in link
    assert "UCSN-DESCRIPTOR-ROOT-KEY@ U< 0=" in link
    assert "_UCSN-WORK-SOURCE-CAP @ U<" in emit
    assert "_UCSN-E-RUN-COUNT" in emit_source
    assert "_UCSN-WORK-NODE-AT" in emit_source
    emit_one = _word(source, "_UCSN-EMIT-ONE")
    assert "_UCSN-E-PRIOR-GENERATION" in emit_one
    assert "_UCSN-E-PRIOR-ROOT @ OVER U< 0=" in emit_one
    for forbidden in ("SORT", "HEAP", "_UCSN-KEY<", "_UCSN-SWAP"):
        assert forbidden not in _executable(source).upper()


def test_descriptor_freezes_generation_root_geometry_and_exact_clip():
    source = SOURCE.read_text(encoding="utf-8")
    metadata = _word(source, "_UCSN-V-WRITE-METADATA")
    root_fit = _word(source, "_UCSN-V-ROOT-FIT?")
    clip = _word(source, "_UCSN-V-CLIP-ROOT?")
    emitted_geometry = _word(source, "_UCSN-E-GEOMETRY?")
    emitted_work = _word(source, "_UCSN-E-WORK?")

    metadata_fields = {
        "_UCSN-V-GENERATION": "_UCSN-D.GENERATION",
        "_UCSN-V-ROW": "_UCSN-D.ROW",
        "_UCSN-V-COLUMN": "_UCSN-D.COLUMN",
        "_UCSN-V-HEIGHT": "_UCSN-D.HEIGHT",
        "_UCSN-V-WIDTH": "_UCSN-D.WIDTH",
        "_UCSN-V-CLIP-ROW": "_UCSN-D.CLIP-ROW",
        "_UCSN-V-CLIP-COLUMN": "_UCSN-D.CLIP-COLUMN",
        "_UCSN-V-CLIP-HEIGHT": "_UCSN-D.CLIP-HEIGHT",
        "_UCSN-V-CLIP-WIDTH": "_UCSN-D.CLIP-WIDTH",
        "_UCSN-V-Z": "_UCSN-D.Z",
    }
    for value, field in metadata_fields.items():
        assert f"{value} @ _UCSN-V-WORK @ {field} !" in metadata

    assert "_UCSN-V-EXTENT-HEIGHT" in root_fit
    assert "_UCSN-V-EXTENT-WIDTH" in root_fit
    assert "_UCSN-V-ORIGIN-ROW" in root_fit
    assert "_UCSN-V-ORIGIN-COLUMN" in root_fit
    assert "_UCSN-V-CLIP-ROOT?" in root_fit
    assert clip.count("_UCSN-IADD-NONNEG?") == 4
    assert "_UCSN-V-ROW @ _UCSN-V-CLIP-ROW @ MAX" in clip
    assert "_UCSN-V-ROOT-BOTTOM @ _UCSN-V-CLIP-BOTTOM @ MIN" in clip
    assert "_UCSN-V-COLUMN @ _UCSN-V-CLIP-COLUMN @ MAX" in clip
    assert "_UCSN-V-ROOT-RIGHT @ _UCSN-V-CLIP-RIGHT @ MIN" in clip

    assert "UCSN-DESCRIPTOR-SOURCE-GENERATION@" in emitted_work
    assert "-1 = IF 0 EXIT" in emitted_work
    assert "_UCSN-E-GEOMETRY? AND" in emitted_work
    for clip_reader in (
        "UCSN-DESCRIPTOR-CLIP-ROW@",
        "UCSN-DESCRIPTOR-CLIP-COLUMN@",
        "UCSN-DESCRIPTOR-CLIP-HEIGHT@",
        "UCSN-DESCRIPTOR-CLIP-WIDTH@",
    ):
        assert clip_reader in emitted_geometry
    assert "_UCSN-E-CLIP-BOTTOM @ _UCSN-E-ROOT-BOTTOM @ >" in emitted_geometry
    assert "_UCSN-E-CLIP-RIGHT @ _UCSN-E-ROOT-RIGHT @ >" in emitted_geometry


def test_one_observation_measures_copies_validates_and_freezes_once():
    source = SOURCE.read_text(encoding="utf-8")
    executable = _executable(source)
    visitor = _word(source, "_UCSN-TREE-VISITOR")
    mounted_visitor = _word(source, "_UCSN-MOUNTED-VISITOR")
    capture = _word(source, "_UCSN-V-CAPTURE")
    produce = _word(source, "_UCSN-V-PRODUCE")
    validate = _word(source, "_UCSN-V-VALIDATE?")
    collection_family = _word(source, "_UCSN-COLLECTION-FAMILY?")
    emitted_work = _word(source, "_UCSN-E-WORK?")
    body = _word(source, "_UCSN-CAPTURE-BODY")
    call = _word(source, "_UCSN-CAPTURE-CALL")

    assert executable.count("UTUI-RESOLVED-TREE-EACH") == 1
    assert executable.count("USCOL-ENTRY-VALIDATE") == 1
    assert capture.count("_UCSN-V-PRODUCE") == 2
    assert "_UTUI-VISITED-COLLECTION-CAPTURE-PREFLIGHTED" in produce
    assert "_UTUI-MOUNTED-COLLECTION-CAPTURE-PREFLIGHTED" in produce
    assert "UTUI-VISITED-COLLECTION-STORAGE-DISJOINT?" in visitor + _word(
        source, "_UCSN-V-PROBE?"
    )
    assert "0 _UCSN-V-GENERATION !" in visitor
    assert "1 _UCSN-V-ROOT-KEY !" in visitor
    for required in (
        "_UCSN-V-GENERATION @ _UTUI-MC-GENERATION-VALID? 0=",
        "_UCSN-V-ROOT-KEY @ 0=",
        "UTUI-RESOLVED-VALID?",
        "-1 _UCSN-V-MOUNTED !",
        "_UCSN-V-MOUNTED-GEOMETRY?",
    ):
        assert required in mounted_visitor
    assert "_UCSN-V-ROOT-FIT?" in validate
    assert "USCOL-F-TEXT-AREA" in collection_family
    assert "USCOL-F-TEXT-GRID" in collection_family
    assert "USCOL-F-TABSET" in collection_family
    assert "_UCSN-COLLECTION-FAMILY?" in validate
    assert "_UCSN-COLLECTION-FAMILY?" in emitted_work
    assert body.index("UTUI-RESOLVED-TREE-EACH") < body.index(
        "_UTUI-MOUNTED-COLLECTION-EACH-PREFLIGHTED"
    ) < body.index("_UCSN-EMIT-CANONICAL")
    assert "UTUI-RESOLVED-OBSERVE" in call
    assert "CATCH" in _word(source, "_UCSN-CAPTURE-OBSERVED-CATCH")
    assert "CATCH" in _word(source, "UCSN-CAPTURE")

    # Mounted enumeration is deliberately an internal UIDL-TUI seam.  UCSN
    # calls it only from the already-held resolved observation; it never owns
    # a relation/widget pointer or asks the ordinary draw loop to rediscover it.
    assert not re.search(r"(?m)^:\s+UCSN-MOUNTED", source)
    for forbidden in ("_UTUI-MCR-", "_UTUI-MC-HEAD", "WDG-DRAW", "EXECUTE"):
        assert forbidden not in executable


def test_all_caller_banks_are_preflighted_before_any_scratch_clear():
    source = SOURCE.read_text(encoding="utf-8")
    authority = _word(source, "_UCSN-AUTHORITY-DISJOINT?")
    ranges = _word(source, "_UCSN-RANGES?")
    observed = _word(source, "_UCSN-CAPTURE-OBSERVED")

    for check in (
        "_UCSN-OWNED-DISJOINT?",
        "USCOL-STORAGE-DISJOINT?",
        "TXTA-STORAGE-DISJOINT?",
        "TGRID-STORAGE-DISJOINT?",
        "TAB-STORAGE-DISJOINT?",
        "_UTUI-STORAGE-DISJOINT-BODY?",
        "_UTUI-CS-OBSERVED?",
    ):
        assert check in authority
    assert " UTUI-STORAGE-DISJOINT?" not in authority
    assert " UTUI-COLLECTION-STORAGE-DISJOINT?" not in authority
    for bank in (
        "_UCSN-BUILDER",
        "_UCSN-VALIDATION-A",
        "_UCSN-WORK-A",
        "_UCSN-DESCRIPTORS-A",
        "_UCSN-NATIVE-A",
    ):
        assert bank in ranges
    assert ranges.count("_UCSN-DISJOINT?") == 10
    assert observed.index("_UCSN-RANGES?") < observed.index(
        "_UCSN-WORK-LAYOUT?"
    )
    assert "_UCSN-CLEAR-SCRATCH" not in observed


def test_scratch_cleanup_tracks_only_transactionally_dirtied_prefixes():
    source = SOURCE.read_text(encoding="utf-8")
    clear = _word(source, "_UCSN-CLEAR-SCRATCH")
    body = _word(source, "_UCSN-CAPTURE-BODY")
    capacity = _word(source, "_UCSN-V-CAPACITY?")
    validate = _word(source, "_UCSN-V-VALIDATE?")
    fail = _word(source, "_UCSN-FAIL-RESULT")
    scrub = _word(source, "_UCSN-SCRUB")

    assert "_UCSN-DIRTY-VALIDATION-U @ ?DUP" in clear
    assert "_UCSN-DIRTY-WORK-U @ ?DUP" in clear
    assert "_UCSN-VALIDATION-U @ ?DUP" not in clear
    assert "_UCSN-WORK-U @ ?DUP" not in clear

    # Every source entry can be read during canonical emission, so the exact
    # current UIDL source-directory prefix is initialized. Dense nodes are
    # initialized one at a time and extend the dirty prefix before FILL.
    assert body.index(
        "_UCSN-WORK-SOURCE-U @ _UCSN-DIRTY-WORK-U !"
    ) < body.index("_UCSN-CLEAR-SCRATCH")
    assert body.count("_UCSN-CLEAR-SCRATCH") == 2
    assert "_UCSN-COUNT @ 1+ UCSN-WORK-NODE-SIZE * +" in capacity
    assert capacity.index("_UCSN-DIRTY-WORK-U !") < capacity.index(
        "_UCSN-V-WORK @ UCSN-WORK-NODE-SIZE 0 FILL"
    )
    assert "UCSN-DESCRIPTOR-SOURCE@" not in capacity

    # Validation receives only its measured need. Its maximum touched prefix
    # is committed before the fallible validator call, including need zero's
    # canonical 0 0 optional span.
    measured = validate.index("USCOL-VALIDATION-WORK-BYTES")
    dirty = validate.index("_UCSN-DIRTY-VALIDATION-U !", measured)
    call = validate.index("USCOL-ENTRY-VALIDATE", dirty)
    assert measured < dirty < call
    assert "_UCSN-V-VALIDATION-U @ ?DUP" in validate
    assert "ELSE\n        0 0" in validate

    assert fail.index("_UCSN-CLEAR-OUTPUT") < fail.index(
        "_UCSN-CLEAR-SCRATCH"
    )
    assert "0 _UCSN-DIRTY-VALIDATION-U !" in scrub
    assert "0 _UCSN-DIRTY-WORK-U !" in scrub


def test_mounted_capture_remains_below_applets_and_outside_the_draw_loop():
    source = SOURCE.read_text(encoding="utf-8")
    executable = _executable(source)
    mounted = _word(source, "_UCSN-MOUNTED-VISITOR")
    body = _word(source, "_UCSN-CAPTURE-BODY")

    assert "source-generation" in mounted
    assert "_UCSN-V-MOUNTED-GEOMETRY?" in mounted
    assert "_UTUI-MOUNTED-COLLECTION-EACH-PREFLIGHTED" in body
    assert "applet callback" in source
    for forbidden in (
        "UTUI-WIDGET-SET",
        "UTUI-DRAW-COMPLETE",
        "ASHELL-PAINT-CHILD",
        "WDG-DRAW",
        "WDG-DRAW-OBSERVE",
        "UTUI-SEMANTIC-",
        "_PAD-",
        "_DB-",
    ):
        assert forbidden not in executable
