"""Seconds-only structural locks for renderer-neutral UIDL semantics."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
UIDL = ROOT / "akashic" / "liraq" / "uidl.f"
LEL = ROOT / "akashic" / "liraq" / "lel.f"
STATE_TREE = ROOT / "akashic" / "liraq" / "state-tree.f"
SEMANTIC = ROOT / "akashic" / "liraq" / "uidl-semantic.f"
UIDL_TUI = ROOT / "akashic" / "tui" / "uidl-tui.f"


def _definition(source: str, name: str) -> str:
    matches = re.findall(
        rf"(?ms)^:\s+{re.escape(name)}(?=\s).*?;\s*(?:\\[^\n]*)?$",
        source,
    )
    assert matches, f"missing Forth definition {name}"
    return matches[0]


def _last_definition(source: str, name: str) -> str:
    matches = re.findall(
        rf"(?ms)^:\s+{re.escape(name)}(?=\s).*?;\s*(?:\\[^\n]*)?$",
        source,
    )
    assert matches, f"missing Forth definition {name}"
    return matches[-1]


def _code_without_comments(source: str) -> str:
    return "\n".join(line.split("\\", 1)[0] for line in source.splitlines())


def _requires(source: str) -> list[str]:
    return re.findall(
        r"(?m)^REQUIRE\s+(\S+)\s*$", _code_without_comments(source)
    )


def test_element_registry_exposes_one_neutral_semantics_hook() -> None:
    source = UIDL.read_text(encoding="utf-8")

    # The formerly reserved final cell becomes a semantic hook without
    # changing the definition record, registry capacity, or DEFINE-ELEMENT
    # calling convention.
    assert ": ED.SEMANTICS ( def -- a ) 56 + ;" in source
    assert "ED.NEXT" not in source
    assert "CREATE _EL-REGISTRY  _EL-REG-SZ 64 * ALLOT" in source
    assert (
        ": DEFINE-ELEMENT  "
        "( render-xt event-xt layout-xt flags \"name\" -- type-id )"
    ) in source

    registration = _definition(source, "_UDL-REG-ELEM")
    assert "0           OVER ED.SEMANTICS !" in registration
    assert registration.index("ED.LAYOUT-XT !") < registration.index(
        "ED.SEMANTICS !"
    ) < registration.index("_EL-DEFS + !")

    setter = _definition(source, "EL-SET-SEMANTICS")
    assert "EL-DEF-BY-TYPE ?DUP IF ED.SEMANTICS ! ELSE DROP THEN" in setter

    # GUARDED builds must expose the new field and setter through the same
    # registry guard as the three pre-existing hooks.
    assert (
        "' ED.SEMANTICS     CONSTANT _ed-dotsemantics-xt" in source
    )
    assert (
        "' EL-SET-SEMANTICS CONSTANT _el-set-semantics-xt" in source
    )
    assert (
        ": ED.SEMANTICS     _ed-dotsemantics-xt _uidl-guard WITH-GUARD ;"
        in source
    )
    assert (
        ": EL-SET-SEMANTICS _el-set-semantics-xt _uidl-guard WITH-GUARD ;"
        in source
    )


def test_uidl_storage_disjoint_covers_every_persistent_document_store() -> None:
    source = UIDL.read_text(encoding="utf-8")

    assert "REQUIRE ../utils/memory-span.f" in source
    disjoint = _definition(source, "UIDL-STORAGE-DISJOINT?")
    assert "( a u -- flag )" in disjoint.splitlines()[0]
    assert "MSPAN-NONWRAPPING? 0=" in disjoint

    persistent_tables = (
        "_EL-REGISTRY _EL-REG-SZ 64 *",
        "_EL-DEFS _EL-REG-SZ CELLS",
        "_EL-REG-STRS 512",
        "_UDL-ELEMS _UDL-MAX-ELEMS _UDL-ELEMSZ *",
        "_UDL-ATTRS _UDL-MAX-ATTRS _UDL-ATTRSZ *",
        "_UDL-STRS _UDL-STR-SZ",
        "_UDL-HASH _UDL-HASH-SZ CELLS",
        "_UDL-HIDS _UDL-HASH-SZ 2 * CELLS",
        "_UDL-SUBS _UDL-MAX-SUBS 24 *",
        "_UDL-VERR 256",
    )
    persistent_scalars = (
        "_UDL-ERR",
        "_EL-REG-CNT",
        "_EL-REG-SPOS",
        "_UDL-ECNT",
        "_UDL-ACNT",
        "_UDL-SPOS",
        "_UDL-ROOT",
        "_UDL-SUB-CNT",
        "_UDL-VCNT",
        "_UDL-DIRTY-HOOK",
    )
    for table in persistent_tables:
        assert f"2DUP {table}" in disjoint
    for scalar in persistent_scalars:
        assert f"2DUP {scalar} 8 MSPAN-OVERLAP?" in disjoint
    assert disjoint.count("MSPAN-OVERLAP?") == (
        len(persistent_tables) + len(persistent_scalars)
    )
    assert "2DROP -1 ;" in disjoint

    assert (
        "' UIDL-STORAGE-DISJOINT? CONSTANT "
        "_uidl-storage-disjoint-q-xt"
    ) in source
    wrapper = _last_definition(source, "UIDL-STORAGE-DISJOINT?")
    assert "_uidl-storage-disjoint-q-xt _uidl-guard WITH-GUARD" in wrapper


def test_semantic_module_is_neutral_allocation_free_and_label_only() -> None:
    source = SEMANTIC.read_text(encoding="utf-8")
    code = _code_without_comments(source)

    assert "PROVIDED akashic-uidl-semantic" in code
    assert _requires(source) == [
        "uidl.f",
        "../text/utf8.f",
        "../utils/memory-span.f",
        "../concurrency/guard.f",
    ]
    guard_if = source.index("[DEFINED] GUARDED [IF] GUARDED [IF]")
    guard_require = source.index("REQUIRE ../concurrency/guard.f", guard_if)
    guard_definition = source.index("GUARD _uidls-guard", guard_require)
    assert guard_if < guard_require < guard_definition

    # The sole fixed byte buffer is the ABI-derived native-cell decimal
    # conversion scratch.  It is not an application capacity or payload
    # arena; every semantic record remains caller-owned.
    assert re.findall(
        r"(?m)^CREATE\s+(\S+)\s+(\d+)\s+ALLOT\s*$", code
    ) == [("_UIDLS-NUM-TEXT", "24")]
    assert len(re.findall(r"(?<![A-Z0-9_-])ALLOT(?![A-Z0-9_-])", code)) == 1
    assert not re.search(
        r"(?m)(?:^|[ \t])(?:ALLOCATE|FREE|RESIZE|XBUF|BUFFER:)"
        r"(?=[ \t]|$)",
        code,
    )
    for forbidden in (
        "PT-",
        "RTE-",
        "RTAPT-",
        "RTERM-",
        "APTSCB-",
        "APTAS-",
        "SCR-",
        "DRW-",
        "RGN-",
        "UCTX-",
        "AHOST-",
        "DESK-",
        "rich-terminal.f",
    ):
        assert forbidden not in code

    installs = re.findall(
        r"(?m)^\s*\[']\s+(\S+)\s+(UIDL-T-\S+)\s+"
        r"EL-SET-SEMANTICS\s*$",
        code,
    )
    assert installs == [("_UIDLS-LABEL-CAPTURE", "UIDL-T-LABEL")]

    dispatch = _definition(source, "_UIDLS-SNAPSHOT-DISPATCH")
    assert "UIDL-TYPE EL-DEF-BY-TYPE" in dispatch
    assert "ED.SEMANTICS @" in dispatch
    assert dispatch.count("UIDL-SNAP-S-UNSUPPORTED") == 2
    assert "EXECUTE" in dispatch
    assert "_UIDLS-CANONICAL-RESULT" in dispatch

    guarded = {
        "UIDL-TEXT@": (
            "_uidls-text-at-xt",
            "_UIDLS-TEXT-AT-GUARDED",
        ),
        "UIDL-SNAPSHOT-CAPTURE": (
            "_uidls-snapshot-capture-xt",
            "_UIDLS-SNAPSHOT-CAPTURE-GUARDED",
        ),
        "UIDL-SNAPSHOT-SIZE": (
            "_uidls-snapshot-size-xt",
            "_UIDLS-SNAPSHOT-SIZE-GUARDED",
        ),
    }
    for public, (captured, guarded_helper) in guarded.items():
        assert re.search(
            rf"(?m)^'\s+{re.escape(public)}\s+CONSTANT\s+"
            rf"{re.escape(captured)}\s*$",
            source,
        )
        helper = _definition(source, guarded_helper)
        assert f"{captured} _uidls-guard WITH-GUARD" in helper
        wrapper = _last_definition(source, public)
        assert f"['] {guarded_helper} UIDL-OBSERVE" in wrapper

    assert (
        "' UIDL-LABEL-SNAPSHOT-VALID?  CONSTANT _uidls-label-valid-q-xt"
        in source
    )
    validator_wrapper = _last_definition(
        source, "UIDL-LABEL-SNAPSHOT-VALID?"
    )
    assert "_uidls-label-valid-q-xt _uidls-guard WITH-GUARD" in (
        validator_wrapper
    )


def test_shared_text_value_semantics_drive_cell_rendering_independently() -> None:
    semantic = SEMANTIC.read_text(encoding="utf-8")
    tui = UIDL_TUI.read_text(encoding="utf-8")

    value = _definition(semantic, "_UIDLS-VALUE>TEXT")
    for value_type in ("ST-T-STRING", "ST-T-INTEGER", "ST-T-BOOLEAN"):
        assert value_type in value
    assert "_UIDLS-NUM>TEXT" in value
    assert "NUM>STR" not in value
    assert 'IF S" true" ELSE S" false" THEN' in value
    assert 'S" "' in value

    number = _definition(semantic, "_UIDLS-NUM>TEXT")
    assert "_UIDLS-NUM-TEXT" in number
    assert "_UIDLS-NUM-POS" in number
    assert "_UIDLS-NUM-NEG" in number

    text = _definition(semantic, "_UIDLS-TEXT@")
    bind_at = text.index("UIDL-BIND IF")
    eval_at = text.index("LEL-EVAL", bind_at)
    fallback_at = text.index('S" text" UIDL-ATTR', eval_at)
    assert bind_at < eval_at < fallback_at
    assert "text-capacity" not in text
    assert "UIDL-SNAPSHOT" not in text
    assert "_UIDLS-VALUE>TEXT" in text
    assert "2DROP 0 0" in text
    text_public = _definition(semantic, "UIDL-TEXT@")
    assert "['] _UIDLS-TEXT-IN-UIDL UIDL-OBSERVE" in text_public

    # uidl-tui consumes the generic text value API, not a retained snapshot.
    # Labels without text-capacity therefore keep their complete CELL path,
    # as do action and toggle consumers of the same value semantics.
    assert _requires(tui)[:3] == [
        "../liraq/uidl.f",
        "../liraq/uidl-semantic.f",
        "../liraq/uidl-chrome.f",
    ]
    display = _definition(tui, "_UTUI-DISPLAY-TEXT")
    assert "UIDL-TEXT@" in display
    for duplicate in ("LEL-EVAL", "ST-T-", "UIDL-BIND", "UIDL-ATTR"):
        assert duplicate not in display

    label = _definition(tui, "_UTUI-RENDER-LABEL")
    action = _definition(tui, "_UTUI-RENDER-ACTION")
    toggle = _definition(tui, "_UTUI-RENDER-TOGGLE")
    indicator = _definition(tui, "_UTUI-RENDER-INDICATOR")
    assert "_UTUI-DISPLAY-TEXT" in label
    assert "_UTUI-DISPLAY-TEXT" in action
    assert "_UTUI-DISPLAY-TEXT" in toggle
    assert "_UTUI-RENDER-LABEL" in indicator

    bind_text = _definition(tui, "_UTUI-BIND-TEXT")
    assert "DROP NIP" not in bind_text
    assert bind_text.count("DROP DROP") == 2

    render_body = _definition(tui, "_UTUI-RENDER-ONE-BODY")
    execute_at = render_body.index("EXECUTE")
    clean_at = render_body.index("UIDL-CLEAN!", execute_at)
    assert execute_at < clean_at
    assert "_UTUI-RENDER-ONE-BODY" in _definition(
        tui, "_UTUI-RENDER-ONE-IN-STATE"
    )
    assert "['] _UTUI-RENDER-ONE-IN-STATE ST-OBSERVE" in _definition(
        tui, "_UTUI-RENDER-ONE-IN-LEL"
    )
    assert "['] _UTUI-RENDER-ONE-IN-LEL LEL-OBSERVE" in _definition(
        tui, "_UTUI-RENDER-ONE-IN-UIDL"
    )
    render_one = _definition(tui, "_UTUI-RENDER-ONE")
    assert "['] _UTUI-RENDER-ONE-IN-UIDL UIDL-OBSERVE" in render_one


def test_observation_order_is_uidl_then_lel_then_state() -> None:
    semantic = SEMANTIC.read_text(encoding="utf-8")
    uidl = UIDL.read_text(encoding="utf-8")
    lel = LEL.read_text(encoding="utf-8")
    state = STATE_TREE.read_text(encoding="utf-8")

    # Public text observation acquires the UIDL document first, then the LEL
    # evaluator, then the state tree.  The innermost body performs the read
    # while all three recursive guards remain held.
    assert "_UIDLS-TEXT@" in _definition(
        semantic, "_UIDLS-TEXT-IN-STATE"
    )
    assert "['] _UIDLS-TEXT-IN-STATE ST-OBSERVE" in _definition(
        semantic, "_UIDLS-TEXT-IN-LEL"
    )
    assert "['] _UIDLS-TEXT-IN-LEL LEL-OBSERVE" in _definition(
        semantic, "_UIDLS-TEXT-IN-UIDL"
    )
    assert "['] _UIDLS-TEXT-IN-UIDL UIDL-OBSERVE" in _definition(
        semantic, "UIDL-TEXT@"
    )
    assert "['] _UIDLS-TEXT-AT-GUARDED UIDL-OBSERVE" in _last_definition(
        semantic, "UIDL-TEXT@"
    )

    # Snapshot dispatch uses the same outer-to-inner authority order.  The
    # stored element/destination tuple is read only inside the state seam.
    snapshot_state = _definition(semantic, "_UIDLS-SNAPSHOT-IN-STATE")
    for borrowed in (
        "_UIDLS-SNAP-P-ELEM @",
        "_UIDLS-SNAP-P-DST @",
        "_UIDLS-SNAP-P-CAP @",
    ):
        assert borrowed in snapshot_state
    assert "_UIDLS-SNAPSHOT-DISPATCH" in snapshot_state
    assert "['] _UIDLS-SNAPSHOT-IN-STATE ST-OBSERVE" in _definition(
        semantic, "_UIDLS-SNAPSHOT-IN-LEL"
    )
    assert "['] _UIDLS-SNAPSHOT-IN-LEL LEL-OBSERVE" in _definition(
        semantic, "_UIDLS-SNAPSHOT-IN-UIDL"
    )
    assert "['] _UIDLS-SNAPSHOT-IN-UIDL UIDL-OBSERVE" in _definition(
        semantic, "_UIDLS-SNAPSHOT-CALL"
    )

    observation_guards = (
        (uidl, "UIDL-OBSERVE", "_uidl-observe-xt", "_uidl-guard"),
        (lel, "LEL-OBSERVE", "_lel-observe-xt", "_lel-guard"),
        (state, "ST-OBSERVE", "_st-observe-xt", "_ltree-guard"),
    )
    for source, public, captured, guard in observation_guards:
        base = _definition(source, public)
        assert "( i*x xt -- j*x )" in base.splitlines()[0]
        assert "EXECUTE" in base
        assert re.search(
            rf"(?m)^'\s+{re.escape(public)}\s+CONSTANT\s+"
            rf"{re.escape(captured)}\s*$",
            source,
        )
        wrapper = _last_definition(source, public)
        assert f"{captured} {guard} WITH-GUARD" in wrapper


def test_caught_public_paths_scrub_every_borrowed_argument() -> None:
    source = SEMANTIC.read_text(encoding="utf-8")

    label = _definition(source, "_UIDLS-LABEL-CAPTURE")
    label_catch = label.index("['] _UIDLS-LABEL-CAPTURE-CALL CATCH")
    label_scrub = label.index("_UIDLS-LABEL-FINISH", label_catch)
    assert label_catch < label_scrub
    assert "DROP 0 UIDL-SNAP-S-INVALID" in label
    label_finish = _definition(source, "_UIDLS-LABEL-FINISH")
    assert "_UIDLS-DEC-CLEAR" in label_finish
    for borrowed in (
        "_UIDLS-LABEL-ELEM",
        "_UIDLS-LABEL-DST",
        "_UIDLS-LABEL-DST-CAP",
        "_UIDLS-LABEL-TEXT-A",
        "_UIDLS-LABEL-TEXT-U",
        "_UIDLS-LABEL-TEXT-CAP",
        "_UIDLS-LABEL-TOTAL",
        "_UIDLS-LABEL-P-ELEM",
        "_UIDLS-LABEL-P-DST",
        "_UIDLS-LABEL-P-CAP",
    ):
        assert f"0 {borrowed} !" in label_finish

    snapshot = _definition(source, "UIDL-SNAPSHOT-CAPTURE")
    snapshot_catch = snapshot.index("['] _UIDLS-SNAPSHOT-CALL CATCH")
    snapshot_scrub = snapshot.index("_UIDLS-SNAP-P-CLEAR", snapshot_catch)
    canonical = snapshot.index("_UIDLS-CANONICAL-RESULT", snapshot_scrub)
    assert snapshot_catch < snapshot_scrub < canonical
    assert "DROP 0 UIDL-SNAP-S-INVALID" in snapshot
    snapshot_clear = _definition(source, "_UIDLS-SNAP-P-CLEAR")
    for borrowed in (
        "_UIDLS-SNAP-P-ELEM",
        "_UIDLS-SNAP-P-DST",
        "_UIDLS-SNAP-P-CAP",
    ):
        assert f"0 {borrowed} !" in snapshot_clear

    validator = _definition(source, "UIDL-LABEL-SNAPSHOT-VALID?")
    validator_catch = validator.index(
        "['] _UIDLS-LABEL-SNAPSHOT-VALID-CALL CATCH"
    )
    exception_scrub = validator.index("_UIDLS-LV-FINISH", validator_catch)
    argument_scrub = validator.index("_UIDLS-LV-P-CLEAR", exception_scrub)
    assert validator_catch < exception_scrub < argument_scrub
    validator_clear = _definition(source, "_UIDLS-LV-P-CLEAR")
    for borrowed in ("_UIDLS-LV-P-SNAPSHOT", "_UIDLS-LV-P-AVAILABLE"):
        assert f"0 {borrowed} !" in validator_clear


def test_label_snapshot_is_caller_sized_copied_and_fail_before_mutation() -> None:
    source = SEMANTIC.read_text(encoding="utf-8")

    signatures = {
        "UIDL-SNAP-STATUS-VALID?": "( status -- flag )",
        "UIDL-TEXT@": "( elem -- a u )",
        "UIDL-LABEL-SNAPSHOT-BYTES": "( text-capacity -- bytes | 0 )",
        "UIDL-LABEL-SNAPSHOT-BYTES@": "( snapshot -- bytes )",
        "UIDL-LABEL-SNAPSHOT-TEXT-CAPACITY@": "( snapshot -- bytes )",
        "UIDL-LABEL-SNAPSHOT-TEXT@": "( snapshot -- a u )",
        "UIDL-SNAPSHOT-CAPTURE": (
            "( elem destination capacity -- bytes status )"
        ),
        "UIDL-SNAPSHOT-SIZE": "( elem -- bytes status )",
        "UIDL-LABEL-SNAPSHOT-VALID?": "( snapshot available -- flag )",
    }
    for name, signature in signatures.items():
        assert signature in _definition(source, name).splitlines()[0]

    assert "64 CONSTANT UIDL-LABEL-SNAPSHOT-HEADER-SIZE" in source
    assert "1 CONSTANT UIDL-SNAPSHOT-K-LABEL" in source
    assert "0x31504E534C444955 CONSTANT _UIDLS-SNAPSHOT-MAGIC" in source
    prepare = _definition(source, "_UIDLS-LABEL-PREPARE")
    assert 'S" text-capacity" UIDL-ATTR IF' in prepare
    assert "_UIDLS-CANONICAL-UDECIMAL" in prepare
    assert "UIDL-SNAP-S-UNSUPPORTED EXIT" in prepare
    assert "_UIDLS-LABEL-TEXT? 0= IF UIDL-SNAP-S-INVALID EXIT" in prepare
    assert "_UIDLS-LABEL-TEXT-CAP @ U> IF" in prepare
    assert "UIDL-SNAP-S-CAPACITY EXIT" in prepare

    decimal = _definition(source, "_UIDLS-CANONICAL-UDECIMAL")
    for checked_rule in (
        "MSPAN-NONWRAPPING?",
        "OVER C@ [CHAR] 0 =",
        "DUP 10 U< 0=",
        "_UIDLS-LENGTH-MAX 10 / U>",
        "_UIDLS-LENGTH-MAX 10 MOD U>",
    ):
        assert checked_rule in decimal

    text_valid = _definition(source, "_UIDLS-LABEL-TEXT?")
    assert "MSPAN-NONWRAPPING?" in text_valid
    assert "UTF8-VALID? 0=" in text_valid
    assert "_UIDLS-LABEL-FORBIDDEN-BYTE?" in text_valid
    assert "UIDL-LABEL-SNAPSHOT-HEADER-SIZE SWAP _UIDLS-UADD?" in (
        _definition(source, "UIDL-LABEL-SNAPSHOT-BYTES")
    )

    capture = _definition(source, "_UIDLS-LABEL-CAPTURE-BODY")
    prepared = capture.index("_UIDLS-LABEL-PREPARE")
    measure = capture.index("_UIDLS-LABEL-DST @ 0= IF", prepared)
    aligned = capture.index("_UIDLS-LABEL-DST @ 7 AND", measure)
    nonwrapping = capture.index("MSPAN-NONWRAPPING? 0= IF", aligned)
    capacity = capture.index("_UIDLS-LABEL-DST-CAP @ U> IF", nonwrapping)
    disjoint = capture.index("UIDL-STORAGE-DISJOINT? 0= IF", capacity)
    overlap = capture.index("MSPAN-OVERLAP? IF", disjoint)
    fill = capture.index("0 FILL", overlap)
    copy = capture.index("CMOVE", fill)
    publish = capture.index("_UIDLS-S.MAGIC !", copy)
    assert (
        prepared
        < measure
        < aligned
        < nonwrapping
        < capacity
        < disjoint
        < overlap
        < fill
        < copy
        < publish
    )
    assert capture.count("0 FILL") == 1
    assert capture.count("CMOVE") == 1

    # Exact (0, 0) is measurement.  Every other callback failure is
    # canonicalized to zero bytes, so no partial recipe can be admitted.
    assert "_UIDLS-LABEL-DST-CAP @ 0= IF" in capture
    canonical = _definition(source, "_UIDLS-CANONICAL-RESULT")
    assert "UIDL-SNAP-STATUS-VALID?" in canonical
    assert "OVER 0> IF EXIT THEN" in canonical
    assert "NIP 0 SWAP" in canonical

    validator = _definition(source, "_UIDLS-LABEL-SNAPSHOT-VALID-BODY?")
    for required in (
        "_UIDLS-S.MAGIC @",
        "_UIDLS-S.ABI @",
        "_UIDLS-S.KIND @",
        "_UIDLS-S.FLAGS @",
        "_UIDLS-SL.RESERVED @",
        "UIDL-LABEL-SNAPSHOT-BYTES",
        "_UIDLS-LABEL-TEXT?",
        "_UIDLS-ZERO-BYTES?",
    ):
        assert required in validator


def test_source_stripping_harnesses_load_semantics_in_dependency_order() -> None:
    harnesses = (
        "local_testing/test_uidl_tui.py",
        "local_testing/test_app_shell.py",
        "local_testing/test_app_compositor.py",
        "local_testing/test_desk.py",
        "local_testing/diag_batch_a.py",
    )
    dependency = re.compile(
        r'os\.path\.join\(AK,\s*"liraq",\s*"'
        r'(uidl(?:-semantic|-chrome)?\.f)"\)'
    )
    for relative in harnesses:
        source = (ROOT / relative).read_text(encoding="utf-8")
        assert dependency.findall(source) == [
            "uidl.f",
            "uidl-semantic.f",
            "uidl-chrome.f",
        ], relative
