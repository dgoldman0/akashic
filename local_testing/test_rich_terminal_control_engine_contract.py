"""Focused structural locks for the semantic CONTROL engine seam."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
PROVIDER = ROOT / "akashic/tui/rich-terminal/apt1-engine.f"
ENGINE = ROOT / "akashic/tui/rich-terminal/engine.f"
BRIDGE = ROOT / "akashic/tui/rich-terminal/engine-apt1.f"


def _text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _word(source: str, name: str) -> str:
    match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", source)
    assert match is not None, name
    return match.group(0)


def _ordered(source: str, *needles: str) -> None:
    positions = [source.index(needle) for needle in needles]
    assert positions == sorted(positions)


def _constant(source: str, name: str) -> int:
    match = re.search(
        rf"(?m)^\s*(0x[0-9A-Fa-f]+|[0-9]+)\s+CONSTANT\s+"
        rf"{re.escape(name)}\s*$",
        source,
    )
    assert match is not None, name
    return int(match.group(1), 0)


def _field_offset(source: str, name: str) -> int:
    definition = _word(source, name)
    match = re.search(
        r"\([^)]*--[^)]*\)\s*(?:(\d+)\s+\+)?\s*;\s*$",
        definition,
    )
    assert match is not None, name
    return int(match.group(1) or 0)


def test_apt1_control_capability_extends_fixed_records_explicitly() -> None:
    source = _text(PROVIDER)

    for declaration in (
        "64 CONSTANT RTAPT-F-CONTROLS",
        "128 CONSTANT RTAPT-F-CONTROL-COLLECTIONS",
        "0x100 CONSTANT _RTAPT-PT-F-CONTROLS",
        "0x200 CONSTANT _RTAPT-PT-F-CONTROL-COLLECTIONS",
        "168 CONSTANT RTAPT-LIMITS-SIZE",
        "40 CONSTANT RTAPT-OP-SIZE",
        "464 CONSTANT RTAPT-OWNER-SIZE",
        "64 CONSTANT RTAPT-CONTROL-LEDGER-SIZE",
        "80 CONSTANT RTAPT-CONFIG-SIZE",
        "536 CONSTANT RTAPT-ENGINE-SIZE",
        ": _RTAPT-L.OUTBOUND-PAYLOAD ( l -- a ) 160 + ;",
        ": _RTAPT-O.ACTIVE-CONTROLS ( o -- a ) 208 + ;",
        ": _RTAPT-O.HIDDEN-CONTROLS ( o -- a ) 216 + ;",
        ": _RTAPT-O.CONTROL-HIGH ( o -- a ) 224 + ;",
        ": _RTAPT-O.PENDING-CONTROLS ( o -- a ) 232 + ;",
        ": _RTAPT-O.PENDING-CONTROL-HIGH ( o -- a ) 240 + ;",
        ": _RTAPT-O.ACTIVE-CONTENT-ITEMS ( o -- a ) 248 + ;",
        ": _RTAPT-O.HIDDEN-CONTENT-ITEMS ( o -- a ) 256 + ;",
        ": _RTAPT-O.PENDING-CONTENT-ITEMS ( o -- a ) 264 + ;",
        ": _RTAPT-O.A-RCOUNT    ( o -- a ) 272 + ;",
        ": _RTAPT-O.A-CONTENT-ITEMS ( o -- a ) 328 + ;",
        ": _RTAPT-O.A-CROOT-ID  ( o -- a ) 352 + ;",
        ": _RTAPT-O.A-CSELECTED-ROOT-CHILD ( o -- a ) 400 + ;",
        ": _RTAPT-O.A-OPS       ( o -- a ) 416 + ;",
        ": _RTAPT-O.PENDING-CONTROL-REPLACEMENTS ( o -- a ) 424 + ;",
        ": _RTAPT-O.PENDING-CONTENT-TARGET ( o -- a ) 432 + ;",
        ": _RTAPT-O.PENDING-UTF8-TARGET ( o -- a ) 440 + ;",
        ": _RTAPT-O.ACTIVE-CONTROL-UTF8 ( o -- a ) 448 + ;",
        ": _RTAPT-O.HIDDEN-CONTROL-UTF8 ( o -- a ) 456 + ;",
        ": _RTAPT-P.OWNER-SLOT ( p -- a )  24 + ;",
        ": _RTAPT-P.REGION-OP  ( p -- a )  32 + ;",
        ": _RTAPT-E.LIMITS     ( e -- a ) 336 + ;",
        ": _RTAPT-E.CONTROL-LEDGER-A ( e -- a ) 504 + ;",
        ": _RTAPT-E.CONTROL-LEDGER-U ( e -- a ) 512 + ;",
        ": _RTAPT-E.CONTROL-LEDGER-CAP ( e -- a ) 520 + ;",
        ": _RTAPT-E.CONTROL-LEDGER-USED ( e -- a ) 528 + ;",
    ):
        assert declaration in source

    limits_copy = _word(source, "_RTAPT-LIMITS-COPY")
    assert "0x3F AND" in limits_copy
    assert "_RTAPT-PT-F-CONTROLS AND IF" in limits_copy
    assert "RTAPT-F-CONTROLS OR" in limits_copy
    assert "_RTAPT-PT-F-CONTROL-COLLECTIONS AND IF" in limits_copy
    assert "RTAPT-F-CONTROL-COLLECTIONS OR" in limits_copy
    assert "PT-OUTBOUND-MAX-PAYLOAD@" in limits_copy
    assert "_RTAPT-L.OUTBOUND-PAYLOAD !" in limits_copy


def test_apt1_control_preflight_consumes_aggregates_without_item_walk() -> None:
    source = _text(PROVIDER)
    public = _word(source, "RTAPT-CONTROL-PREFLIGHT")
    body = _word(source, "_RTAPT-CONTROL-PREFLIGHT-BODY")
    arithmetic = _word(source, "_RTAPT-CONTROL-PREFLIGHT-ARITHMETIC?")

    assert "( aggregate scalars engine -- status )" in public
    assert "ITEMS-A" not in public + body + arithmetic
    assert "?DO" not in public + body + arithmetic
    assert "_RTAPT-CONTROL-COPY-FIXED _RTAPT-UMUL?" in arithmetic
    assert "_RTAPT-CONTROL-FRAME-FIXED _RTAPT-UMUL?" in arithmetic
    assert "_RTAPT-UPDATE-ENVELOPE-FRAME-BYTES" in arithmetic
    assert "_RTAPT-REGION-DEFINE-FRAME-BYTES" in arithmetic
    assert "_RTAPT-CPF-MAX-ITEM-TEXT @ 80 _RTAPT-UADD?" in body
    assert "_RTAPT-CONTROL-LEDGER-TARGET-CAPACITY?" in body
    _ordered(
        body,
        "_RTAPT-E.OP-CAP",
        "_RTAPT-E.COPY-U",
        "_RTAPT-CONTROL-LEDGER-TARGET-CAPACITY?",
        "_RTAPT-L.UPDATE-BYTES",
        "_RTAPT-L.UTF8-BYTES",
    )
    assert "_RTAPT-LPF-OWNER-ADMISSION" in body
    for clip_store in (
        "_RTAPT-CPF-CLIP-ROWS !",
        "_RTAPT-CPF-CLIP-COLS !",
        "_RTAPT-CPF-CLIP-Y !",
        "_RTAPT-CPF-CLIP-X !",
    ):
        assert clip_store in public
    _ordered(
        public,
        "_RTAPT-CPF-REGION-FLAGS !",
        "_RTAPT-CPF-REGION-Z !",
        "_RTAPT-CPF-CLIP-ROWS !",
        "_RTAPT-CPF-CLIP-COLS !",
        "_RTAPT-CPF-CLIP-Y !",
        "_RTAPT-CPF-CLIP-X !",
        "_RTAPT-CPF-REGION-ROWS !",
        "_RTAPT-CPF-REGION-COLS !",
        "_RTAPT-CPF-REGION-Y !",
        "_RTAPT-CPF-REGION-X !",
    )
    assert "1 _RTAPT-LPF-REQUESTED-REGIONS !" in body


def test_apt1_control_capture_orders_authority_before_mutable_capacity() -> None:
    source = _text(PROVIDER)
    common = _word(source, "_RTAPT-CONTROL-COMMON?")
    capture = _word(source, "_RTAPT-CONTROL-CAPTURE")

    _ordered(
        common,
        "_RTAPT-ENGINE-STORAGE?",
        "_RTAPT-CONTROL-SHAPE?",
        "_RTAPT-CONTROL-TEXT-SPANS?",
        "_RTAPT-CONTROL-CONTENT-HEADER?",
        "_RTAPT-CONTROL-TEXT?",
        "_RTAPT-READY-STATUS",
        "_RTAPT-CAPTURE-READY?",
        "_RTAPT-CONTROL-CAPACITY?",
        "_RTAPT-CONTROL-LIMITS",
    )
    assert "RTAPT-OP-SIZE 0 FILL" in capture
    assert "_RTAPT-CD-COPY-U @ 0 FILL" in capture
    assert capture.count("MOVE") == 3
    assert "_RTAPT-CONTROL-COPY-CONTENT-HEADER?" in capture
    _ordered(
        capture,
        "_RTAPT-CD-LABEL-A @",
        "MOVE",
        "_RTAPT-CD-CONTENT-A @",
        "_RTAPT-CONTROL-COPY-CONTENT-HEADER?",
        "_RTAPT-CONTROL-COPY-TEXT?",
        "_RTAPT-E.COPY-USED !",
        "_RTAPT-E.OP-COUNT +!",
    )


def test_glyph_and_control_definitions_share_object_and_utf8_quotas() -> None:
    source = _text(PROVIDER)
    object_base = _word(source, "_RTAPT-SHARED-OBJECT-BASE?")
    glyph_define = _word(source, "_RTAPT-GLYPH-RUN-DEFINE-BODY")
    control_quota = _word(source, "_RTAPT-CONTROL-SHARED-QUOTA?")
    control_utf8 = _word(source, "_RTAPT-CONTROL-UTF8-QUOTA?")

    for field in (
        "_RTAPT-O.ACTIVE-OBJECTS",
        "_RTAPT-O.ACTIVE-CONTROLS",
        "_RTAPT-O.ACTIVE-CONTENT-ITEMS",
        "_RTAPT-O.HIDDEN-OBJECTS",
        "_RTAPT-O.HIDDEN-CONTROLS",
        "_RTAPT-O.HIDDEN-CONTENT-ITEMS",
        "_RTAPT-TARGET-BASE",
    ):
        assert field in object_base
    assert "_RTAPT-SHARED-OBJECT-BASE?" in control_quota
    assert "_RTAPT-O.PENDING-OBJECTS" in glyph_define
    assert "_RTAPT-O.PENDING-CONTROLS" in glyph_define
    assert "_RTAPT-O.PENDING-CONTENT-ITEMS" in glyph_define
    assert "_RTAPT-O.PENDING-OBJECTS" in control_quota
    assert "_RTAPT-O.PENDING-CONTROLS" in control_quota
    assert "_RTAPT-O.PENDING-CONTENT-ITEMS" in control_quota
    assert "_RTAPT-UTF8-BASE" in control_utf8
    assert "_RTAPT-O.PENDING-UTF8" in control_utf8


def test_control_delta_replacement_reconciles_exact_identity_quotas() -> None:
    source = _text(PROVIDER)
    replace = _word(source, "_RTAPT-CONTROL-REPLACE-BODY")
    targets = _word(source, "_RTAPT-CONTROL-REPLACE-TARGETS?")
    quota = _word(source, "_RTAPT-CONTROL-REPLACE-QUOTA?")
    prior = _word(source, "_RTAPT-CONTROL-REPLACE-PRIOR?")
    mutable = _word(source, "_RTAPT-MUTABLE-CONTROL-KIND?")
    drop = _word(source, "_RTAPT-CONTROL-DROP-BODY")

    assert "PT-RET-DELTA <>" in replace
    _ordered(
        replace,
        "_RTAPT-CONTROL-LEDGER-VALID?",
        "_RTAPT-CONTROL-REGION?",
        "_RTAPT-CONTROL-LEDGER-FIND",
        "_RTAPT-CONTROL-REPLACE-PRIOR?",
        "_RTAPT-CONTROL-REPLACE-TARGETS?",
        "_RTAPT-CONTROL-REPLACE-QUOTA?",
        "_RTAPT-CONTROL-CAPTURE",
    )
    assert "_RTAPT-CL-ACTIVE" in replace
    assert "_RTAPT-CL-KIND-MASK" in replace
    assert "_RTAPT-MUTABLE-CONTROL-KIND?" in replace
    assert "RTAPT-S-UNSUPPORTED EXIT" in replace
    for kind in ("TEXT-AREA", "TEXT-GRID", "TAB"):
        assert f"RTAPT-CONTROL-{kind}" in mutable
    assert "_RTAPT-OP-CONTROL-REPLACE" in prior
    assert "_RTAPT-CD.CONTROL" in prior
    assert "_RTAPT-CL.ACTIVE-ITEMS" in targets
    assert "_RTAPT-CL.ACTIVE-UTF8" in targets
    assert "_RTAPT-O.PENDING-CONTENT-TARGET" in targets
    assert "_RTAPT-O.PENDING-UTF8-TARGET" in targets
    assert "_RTAPT-O.OBJECTS @ U>" in quota
    assert "_RTAPT-O.UTF8-BYTES @ U>" in quota
    assert replace.index("_RTAPT-CONTROL-CAPTURE") < replace.index(
        "_RTAPT-O.PENDING-CONTROL-REPLACEMENTS !"
    )
    assert "RTAPT-S-UNSUPPORTED" in drop
    assert "_RTAPT-CONTROL-CAPTURE" not in drop
    assert "_RTAPT-OP-CONTROL-DROP" not in drop
    for mutation in ("_RTAPT-O.", "_RTAPT-E.OP-COUNT", "_RTAPT-E.COPY-USED"):
        assert mutation not in drop


def test_control_delta_definition_is_monotonic_and_ack_gated() -> None:
    source = _text(PROVIDER)
    define = _word(source, "_RTAPT-CONTROL-DEFINE-BODY")
    publication = _word(source, "_RTAPT-PUBLICATION-CONTROL-DELTA-DEFINE?")
    parent = _word(source, "_RTAPT-PUBLICATION-CONTROL-DELTA-PARENT?")
    prior_parent = _word(
        source, "_RTAPT-PUBLICATION-CONTROL-DELTA-PARENT-PRIOR?"
    )
    parent_kind = _word(source, "_RTAPT-PUBLICATION-CONTROL-PARENT-KIND?")
    control = _word(source, "_RTAPT-PUBLICATION-CONTROL?")
    insert = _word(source, "_RTAPT-CONTROL-LEDGER-INSERT?")
    apply = _word(source, "_RTAPT-CONTROL-LEDGER-APPLY?")
    owner_audit = _word(source, "_RTAPT-OWNER-AUDIT-MATCH?")
    reconcile = _word(source, "_RTAPT-RECONCILE-OUTPUT")

    assert "PT-RET-REPLACE-START =" in define
    assert "PT-RET-DELTA = OR" in define
    assert "PT-RET-DELTA <>" in define
    _ordered(
        define,
        "_RTAPT-CONTROL-LEDGER-VALID?",
        "_RTAPT-CONTROL-LEDGER-DEFINE-CAPACITY?",
        "_RTAPT-CONTROL-REGION?",
        "_RTAPT-O.CONTROL-HIGH",
        "_RTAPT-O.PENDING-CONTROL-HIGH",
        "_RTAPT-CONTROL-CAPTURE",
    )
    assert "PT-RET-DELTA <> IF 0 EXIT" in publication
    assert "_RTAPT-O.ACTIVE-REGIONS" in publication
    assert "_RTAPT-O.REGION-HIGH" in publication
    assert "_RTAPT-PF-CHIGH @ U> 0=" in publication
    assert "_RTAPT-PUBLICATION-CONTROL-DELTA-PARENT?" in publication
    assert "_RTAPT-PF-CCOUNT" in publication
    assert "_RTAPT-PF-CONTENT-ITEMS" in publication
    assert "_RTAPT-PF-UTF8" in publication
    assert "_RTAPT-PUBLICATION-CONTROL-DELTA-DEFINE?" in control
    assert "_RTAPT-CONTROL-LEDGER-FIND" in parent
    assert "_RTAPT-CL-ACTIVE" in parent
    assert "_RTAPT-O.CONTROL-HIGH" in parent
    assert "_RTAPT-PUBLICATION-CONTROL-DELTA-PARENT-PRIOR?" in parent
    assert "_RTAPT-OP-CONTROL-DEFINE" in prior_parent
    assert "_RTAPT-PA-I @ 0 ?DO" in prior_parent
    for relationship in (
        ("MENU", "MENUBAR"),
        ("ITEM", "MENU"),
        ("SEPARATOR", "MENU"),
        ("TAB", "TABSET"),
    ):
        assert all(f"RTAPT-CONTROL-{kind}" in parent_kind for kind in relationship)

    delta_audit_start = owner_audit.index("PT-RET-DELTA = IF")
    for exact_delta_ledger in (
        "_RTAPT-O.PENDING-CONTROL-REPLACEMENTS",
        "_RTAPT-O.A-CBAR-COUNT",
        "_RTAPT-O.A-CPHASE\n            8 _RTAPT-ZERO-SPAN?",
        "_RTAPT-O.A-CROOT-ID\n            64 _RTAPT-ZERO-SPAN?",
    ):
        assert (
            owner_audit.index(exact_delta_ledger, delta_audit_start)
            > delta_audit_start
        )
    delta_audit_end = owner_audit.index(
        "    ELSE\n        _RTAPT-LV-O @ _RTAPT-O.A-CCOUNT",
        delta_audit_start,
    )
    delta_audit = owner_audit[delta_audit_start:delta_audit_end]
    assert "80 _RTAPT-ZERO-SPAN?" not in delta_audit
    phase_offset = _field_offset(source, "_RTAPT-O.A-CPHASE")
    replacement_offset = _field_offset(source, "_RTAPT-O.A-CBAR-COUNT")
    root_offset = _field_offset(source, "_RTAPT-O.A-CROOT-ID")
    operation_offset = _field_offset(source, "_RTAPT-O.A-OPS")
    assert phase_offset + 8 == replacement_offset
    assert replacement_offset + 8 == root_offset
    assert root_offset + 64 == operation_offset
    assert "_RTAPT-PF-CONTROL-PHASE-COLLECTION" not in publication

    assert "_RTAPT-CLI-ACTIVE @ IF" in insert
    assert "_RTAPT-CL-ACTIVE OR" in insert
    assert "_RTAPT-CL-HIDDEN OR" in insert
    assert "_RTAPT-CONTROL-LEDGER-INSERT-ACTIVE?" in apply
    assert "_RTAPT-CONTROL-LEDGER-INSERT-HIDDEN?" in apply
    assert reconcile.index("PT-TX-RESULT-OK = IF") < reconcile.index(
        "_RTAPT-CONTROL-LEDGER-APPLY?"
    )


def test_final_publication_audit_rechecks_the_complete_define_graph_once() -> None:
    source = _text(PROVIDER)
    next_id = _word(source, "_RTAPT-PF-CONTROL-NEXT-ID?")
    menu = _word(source, "_RTAPT-PF-CONTROL-MENU?")
    item = _word(source, "_RTAPT-PF-CONTROL-ITEM?")
    tab = _word(source, "_RTAPT-PF-CONTROL-TAB?")
    graph = _word(source, "_RTAPT-PF-CONTROL-DEFINE-GRAPH?")
    control = _word(source, "_RTAPT-PUBLICATION-CONTROL?")
    operations = _word(source, "_RTAPT-PUBLICATION-OPS?")
    audit = _word(source, "_RTAPT-PUBLICATION-AUDIT-BODY")

    assert "_RTAPT-PF-CCOUNT @ 0= IF" in next_id
    assert "_RTAPT-PF-CHIGH @ U> 0=" in next_id
    assert "_RTAPT-PF-CHIGH @ 1 _RTAPT-UADD?" in next_id
    assert "_RTAPT-PF-CROOT-ID @ <>" in menu
    assert "_RTAPT-PF-COPEN-MENU" in menu
    assert "_RTAPT-PF-CSELECTED-ROOT-CHILD" in menu
    assert "_RTAPT-PF-CMENU-FIRST @ U<" in item
    assert "_RTAPT-PF-CMENU-LAST @ U>" in item
    assert "_RTAPT-PF-CPARENT @ U<" in item
    assert "_RTAPT-PF-CSELECTED-ITEM-PARENT" in item
    assert "_RTAPT-PF-CONTROL-PHASE-TABSET" in tab
    assert "_RTAPT-PF-CONTROL-PHASE-TAB" in tab
    assert "_RTAPT-PF-CROOT-ID @ <>" in tab
    assert "_RTAPT-PF-CORDER @ U> 0=" in tab
    assert "_RTAPT-PF-CSELECTED-ROOT-CHILD @ IF" in tab
    assert "RTAPT-CONTROL-MENUBAR" in graph
    assert "_RTAPT-CONTROL-TEXT-COLLECTION-KIND?" in graph
    assert "_RTAPT-PF-CONTROL-PHASE-COLLECTION" in graph
    assert "RTAPT-CONTROL-TABSET" in graph
    assert "RTAPT-CONTROL-TAB" in graph
    assert "_RTAPT-PF-CONTROL-ROOT-START" in graph
    assert "_RTAPT-PF-CONTROL-TAB?" in graph
    assert "RTAPT-CONTROL-MENU" in graph
    assert "_RTAPT-PF-CONTROL-ITEM?" in graph
    assert "PT-RET-REPLACE-START <>" in control
    assert "_RTAPT-PF-CONTROL-DEFINE-GRAPH?" in control
    assert operations.count("?DO") == 1
    assert operations.count("_RTAPT-PUBLICATION-CONTROL?") == 0
    assert operations.count("_RTAPT-PUBLICATION-SEMANTICS?") == 1
    assert audit.count("_RTAPT-PUBLICATION-OPS?") == 1
    assert "_RTAPT-OWNER-LEDGERS-FROM?" in audit


def test_captured_controls_are_revalidated_and_serialized_explicitly() -> None:
    source = _text(PROVIDER)
    banks = _word(source, "_RTAPT-CAPTURED-BANKS?")
    shape = _word(source, "_RTAPT-PUBLICATION-OP-SHAPE?")
    control = _word(source, "_RTAPT-PUBLICATION-CONTROL?")
    ledgers = _word(source, "_RTAPT-OWNER-AUDIT-MATCH?")
    sender = _word(source, "_RTAPT-SEND-CONTROL")

    assert "_RTAPT-CONTROL-COPY-FIXED" in banks
    assert "_RTAPT-OP-CONTROL-DROP" not in banks
    assert "_RTAPT-OP-CONTROL-DROP" not in shape
    assert "_RTAPT-CONTROL-COPY-FIXED" in shape
    assert "_RTAPT-CONTROL-COPY-SHAPE?" in control
    assert "_RTAPT-PF-CCOUNT" in control
    assert "_RTAPT-PF-CONTROL-DEFINE-GRAPH?" in control
    assert "_RTAPT-PF-UTF8" in control
    assert "_RTAPT-O.PENDING-CONTROLS" in ledgers
    assert "_RTAPT-O.PENDING-CONTROL-HIGH" in ledgers
    assert "_RTAPT-O.PENDING-CONTENT-ITEMS" in ledgers
    assert "_RTAPT-O.PENDING-UTF8" in ledgers
    assert "_RTAPT-O.PENDING-CONTROL-REPLACEMENTS" in ledgers
    assert "_RTAPT-O.PENDING-CONTENT-TARGET" in ledgers
    assert "_RTAPT-O.PENDING-UTF8-TARGET" in ledgers
    assert "_RTAPT-CD.CONTENT-U @ IF" in sender
    assert "_RTAPT-CS-COPY @ _RTAPT-CD.TEXT" in sender
    assert "_RTAPT-CS-COPY @ _RTAPT-CD.LABEL-U @ +" in sender
    assert "_RTAPT-CD.SHORTCUT-U @ +" in sender
    _ordered(
        sender,
        "_RTAPT-CD.OWNER",
        "_RTAPT-CD.GENERATION",
        "_RTAPT-CD.CONTROL",
        "_RTAPT-CD.KIND",
        "_RTAPT-CD.STATE",
        "_RTAPT-CD.Z",
        "_RTAPT-CD.REGION",
        "_RTAPT-CD.PARENT",
        "_RTAPT-CD.ORDER",
        "_RTAPT-CD.X",
        "_RTAPT-CD.Y",
        "_RTAPT-CD.COLS",
        "_RTAPT-CD.ROWS",
        "_RTAPT-CD.LABEL-U",
        "_RTAPT-CD.SHORTCUT-U",
        "_RTAPT-CD.CONTENT-U",
        "PT-CONTROL-REPLACE ELSE PT-CONTROL-DEFINE",
    )


def test_control_identity_ledger_follows_acknowledged_target_lifecycle() -> None:
    source = _text(PROVIDER)
    valid = _word(source, "_RTAPT-CONTROL-LEDGER-VALID?")
    find = _word(source, "_RTAPT-CONTROL-LEDGER-FIND")
    owner = _word(source, "_RTAPT-CONTROL-LEDGER-OWNER?")
    capacity = _word(source, "_RTAPT-CONTROL-LEDGER-TARGET-CAPACITY?")
    apply = _word(source, "_RTAPT-CONTROL-LEDGER-APPLY?")
    replace_active = _word(source, "_RTAPT-CONTROL-LEDGER-REPLACE-ACTIVE?")
    reconcile = _word(source, "_RTAPT-RECONCILE-OUTPUT")
    owner_clear = _word(source, "_RTAPT-OWNER-CLEAR")
    owner_drop = _word(source, "_RTAPT-RECONCILE-DROP")
    apply_owner = _word(source, "_RTAPT-APPLY-OUTPUT")
    pending_clear = _word(source, "_RTAPT-PENDING-CLEAR")
    fini = _word(source, "RTAPT-FINI")

    for invariant in (
        "_RTAPT-OWNER-POINTER?",
        "_RTAPT-CL.GENERATION",
        "_RTAPT-CL.CONTROL",
        "_RTAPT-CL-KIND-MASK",
        "_RTAPT-CL-ACTIVE",
        "_RTAPT-CL-HIDDEN",
        "_RTAPT-CLV-PRIOR-OWNER",
        "_RTAPT-CLV-PRIOR-CONTROL",
    ):
        assert invariant in valid
    for exact_total in (
        "ACTIVE-CONTROLS",
        "HIDDEN-CONTROLS",
        "ACTIVE-CONTENT-ITEMS",
        "HIDDEN-CONTENT-ITEMS",
        "ACTIVE-CONTROL-UTF8",
        "HIDDEN-CONTROL-UTF8",
    ):
        assert f"_RTAPT-O.{exact_total}" in owner
    assert "_RTAPT-CL-ACTIVE AND" in capacity
    assert "_RTAPT-E.CONTROL-LEDGER-CAP" in capacity
    assert "_RTAPT-CLF-ENTRY @ UNLOOP EXIT" not in find
    assert re.search(r"_RTAPT-CLF-GEN @ = IF\s+UNLOOP EXIT", find)
    assert re.search(r"THEN\s+DROP 0 UNLOOP EXIT", find)
    _ordered(
        replace_active,
        "_RTAPT-CLI-O !",
        "_RTAPT-CLI-O @",
        "_RTAPT-CD.GENERATION",
        "_RTAPT-CD.CONTROL",
        "_RTAPT-CONTROL-LEDGER-FIND",
    )

    for mode_helper in (
        "_RTAPT-CONTROL-LEDGER-CLEAR-HIDDEN",
        "_RTAPT-CONTROL-LEDGER-CLONE-ACTIVE",
        "_RTAPT-CONTROL-LEDGER-INSERT-HIDDEN?",
        "_RTAPT-CONTROL-LEDGER-INSERT-ACTIVE?",
        "_RTAPT-CONTROL-LEDGER-REPLACE-ACTIVE?",
        "_RTAPT-CONTROL-LEDGER-PROMOTE-HIDDEN",
        "_RTAPT-CONTROL-LEDGER-REFRESH-UTF8?",
    ):
        assert mode_helper in apply
    _ordered(
        reconcile,
        "PT-TX-RESULT-OK = IF",
        "_RTAPT-CONTROL-LEDGER-APPLY?",
        "_RTAPT-APPLY-OUTPUT",
        "_RTAPT-CANDIDATE-DISCARD",
    )
    assert "_RTAPT-CONTROL-LEDGER-REMOVE-OWNER" in owner_clear
    assert "_RTAPT-CONTROL-LEDGER-REMOVE-OWNER" in owner_drop
    for staged in (
        "PENDING-CONTROL-REPLACEMENTS",
        "PENDING-CONTENT-TARGET",
        "PENDING-UTF8-TARGET",
    ):
        assert f"_RTAPT-O.{staged}" in apply_owner
        assert f"_RTAPT-O.{staged}" in pending_clear
    assert "_RTAPT-E.CONTROL-LEDGER-A" in fini
    assert "_RTAPT-E.CONTROL-LEDGER-U" in fini


def test_neutral_control_feature_records_and_callbacks_have_exact_layouts() -> None:
    source = _text(ENGINE)

    assert _constant(source, "RTE-F-CONTROLS") == 64
    assert _constant(source, "RTE-F-CONTROL-COLLECTIONS") == 128
    assert _constant(source, "_RTE-FEATURE-MASK") == 0xFF
    assert _constant(source, "RTE-LIMITS-SIZE") == 168
    assert _field_offset(source, "_RTE-L.OUTBOUND-PAYLOAD") == 160

    control_fields = {
        "_RTE-CONTROL.OWNER": 0,
        "_RTE-CONTROL.GENERATION": 8,
        "_RTE-CONTROL.ID": 16,
        "_RTE-CONTROL.KIND": 24,
        "_RTE-CONTROL.STATE": 32,
        "_RTE-CONTROL.Z": 40,
        "_RTE-CONTROL.REGION": 48,
        "_RTE-CONTROL.PARENT": 56,
        "_RTE-CONTROL.ORDER": 64,
        "_RTE-CONTROL.ROW": 72,
        "_RTE-CONTROL.COL": 80,
        "_RTE-CONTROL.HEIGHT": 88,
        "_RTE-CONTROL.WIDTH": 96,
        "_RTE-CONTROL.ROOT-HEIGHT": 104,
        "_RTE-CONTROL.ROOT-WIDTH": 112,
        "_RTE-CONTROL.LABEL-A": 120,
        "_RTE-CONTROL.LABEL-U": 128,
        "_RTE-CONTROL.SHORTCUT-A": 136,
        "_RTE-CONTROL.SHORTCUT-U": 144,
        "_RTE-CONTROL.CONTENT-A": 152,
        "_RTE-CONTROL.CONTENT-U": 160,
        "_RTE-CONTROL.CONTENT-ITEMS": 168,
        "_RTE-CONTROL.CONTENT-UTF8": 176,
        "_RTE-CONTROL.RESERVED": 184,
    }
    assert {
        name: _field_offset(source, name) for name in control_fields
    } == control_fields
    assert _constant(source, "RTE-CONTROL-SIZE") == 192

    plan_fields = {
        "_RTE-CP.OWNER": 0,
        "_RTE-CP.GENERATION": 8,
        "_RTE-CP.SURFACE-COLS": 16,
        "_RTE-CP.SURFACE-ROWS": 24,
        "_RTE-CP.REGION-ID": 32,
        "_RTE-CP.REGION-X": 40,
        "_RTE-CP.REGION-Y": 48,
        "_RTE-CP.REGION-COLS": 56,
        "_RTE-CP.REGION-ROWS": 64,
        "_RTE-CP.CLIP-X": 72,
        "_RTE-CP.CLIP-Y": 80,
        "_RTE-CP.CLIP-COLS": 88,
        "_RTE-CP.CLIP-ROWS": 96,
        "_RTE-CP.REGION-Z": 104,
        "_RTE-CP.REGION-FLAGS": 112,
        "_RTE-CP.ITEMS-A": 120,
        "_RTE-CP.ITEMS-U": 128,
        "_RTE-CP.RESERVED": 136,
    }
    assert {name: _field_offset(source, name) for name in plan_fields} == plan_fields
    assert _constant(source, "RTE-CONTROL-PLAN-SIZE") == 144

    callback_fields = {
        "_RTE-F.CONTROL-PREFLIGHT-XT": 152,
        "_RTE-F.CONTROL-DEF-XT": 160,
        "_RTE-F.CONTROL-REPLACE-XT": 168,
        "_RTE-F.CONTROL-DROP-XT": 176,
    }
    assert {
        name: _field_offset(source, name) for name in callback_fields
    } == callback_fields
    valid = _word(source, "RTE-VALID?")
    for field in callback_fields:
        assert f"{field} @ 0=" in valid


def test_neutral_control_plan_checks_authority_before_one_item_pass() -> None:
    source = _text(ENGINE)
    header = _word(source, "_RTE-CPV-HEADER?")
    byte_authority = _word(source, "_RTE-CPV-BYTES-AUTHORITY?")
    item = _word(source, "_RTE-CPV-ITEM?")
    body = _word(source, "_RTE-CONTROL-PLAN-VALID-BODY")
    public = _word(source, "RTE-CONTROL-PREFLIGHT")

    _ordered(
        header,
        "RTE-CONTROL-PLAN-SIZE _RTE-SPAN?",
        "RTE-STORAGE-DISJOINT?",
        "_RTE-CP.OWNER @",
        "_RTE-CP.ITEMS-A @",
        "_RTE-CP.ITEMS-U @",
        "MSPAN-OVERLAP?",
    )
    assert "_RTE-REGION-GEOMETRY?" in header
    for field in ("CLIP-X", "CLIP-Y", "CLIP-COLS", "CLIP-ROWS"):
        assert f"_RTE-CP.{field} @" in header
    _ordered(
        byte_authority,
        "RTE-CONTROL-PLAN-SIZE MSPAN-OVERLAP?",
        "_RTE-CPV-ITEMS-A @ _RTE-CPV-ITEMS-U @ MSPAN-OVERLAP?",
        "RTE-STORAGE-DISJOINT?",
    )
    _ordered(
        item,
        "_RTE-CPV-ITEM-STRUCTURAL?",
        "_RTE-CPV-ITEM-BYTES-AUTHORITY?",
        "_RTE-CPV-ITEM-TEXT?",
        "_RTE-CPV-ITEM-CORRELATES?",
        "_RTE-CPV-GRAPH?",
        "_RTE-CPV-ITEM-AGGREGATE?",
    )
    assert body.count("?DO") == 1
    assert body.count("_RTE-CPV-ITEM?") == 1
    assert public.count("_RTE-CONTROL-PLAN-VALID-BODY") == 1
    callback = public[public.index("_RTE-CONTROL-PLAN-VALID-BODY") :]
    _ordered(
        callback,
        "_RTE-CPV-PLAN @",
        "_RTE-CPV-COUNT @",
        "_RTE-CPV-BYTES @",
        "_RTE-CPV-ALIGNED-BYTES @",
        "_RTE-CPV-MAX-ITEM-BYTES @",
        "_RTE-CPV-LAST-ID @",
        "_RTE-CPV-COLLECTIONS @",
        "_RTE-CPV-CONTENT-ITEMS @",
        "_RTE-CPV-UTF8-BYTES @",
        "_RTE-F.CONTROL-PREFLIGHT-XT @ EXECUTE",
    )


def test_neutral_collection_predicates_keep_content_feature_and_roots_distinct() -> None:
    source = _text(ENGINE)
    text_kind = _word(source, "_RTE-CONTROL-TEXT-COLLECTION-KIND?")
    feature_kind = _word(source, "_RTE-CONTROL-COLLECTION-KIND?")
    root_kind = _word(source, "_RTE-CONTROL-ROOT-KIND?")
    content = _word(source, "_RTE-CONTROL-COLLECTION-CONTENT?")
    kind = _word(source, "_RTE-CONTROL-KIND?")
    aggregate = _word(source, "_RTE-CPV-ITEM-AGGREGATE?")
    limits = _word(source, "_RTE-LIMITS-VALID-BODY")

    assert _constant(source, "RTE-CONTROL-TEXT-AREA") == 5
    assert _constant(source, "RTE-CONTROL-TEXT-GRID") == 6
    assert _constant(source, "RTE-CONTROL-TABSET") == 7
    assert _constant(source, "RTE-CONTROL-TAB") == 8
    assert "RTE-CONTROL-TEXT-AREA" in text_kind
    assert "RTE-CONTROL-TEXT-GRID" in text_kind
    assert "RTE-CONTROL-TABSET" not in text_kind
    assert "RTE-CONTROL-TAB" not in text_kind
    assert "_RTE-CONTROL-TEXT-COLLECTION-KIND?" in feature_kind
    assert "RTE-CONTROL-TABSET" in feature_kind
    assert "RTE-CONTROL-TAB" in feature_kind
    assert "RTE-CONTROL-MENU-BAR" in root_kind
    assert "_RTE-CONTROL-TEXT-COLLECTION-KIND?" in root_kind
    assert "RTE-CONTROL-TABSET =" in root_kind
    assert "RTE-CONTROL-TAB =" not in root_kind
    _ordered(
        content,
        "_RTE-CONTROL.CONTENT-U @ 72 U<",
        "_RTE-CONTROL.CONTENT-ITEMS @",
        "32 _RTE-UMUL?",
        "72 _RTE-UADD?",
        "_RTE-CONTROL.CONTENT-UTF8 @",
        "_RTE-CONTROL.CONTENT-U @ =",
    )
    assert "_RTE-CONTROL-COLLECTION-STATE-MASK" in kind
    assert "_RTE-CONTROL-TEXT-COLLECTION-KIND?" in kind
    assert "_RTE-CONTROL-COLLECTION-CONTENT?" in kind
    assert "RTE-CONTROL-TABSET" in kind
    assert "_RTE-CONTROL-TABSET-STATE-MASK" in kind
    assert "RTE-CONTROL-TAB" in kind
    assert "_RTE-CONTROL-DESCENDANT?" in kind
    assert "_RTE-CONTROL-COLLECTION-KIND?" in aggregate
    for field in ("CONTENT-U", "CONTENT-ITEMS", "CONTENT-UTF8"):
        assert f"_RTE-CONTROL.{field} @" in aggregate
    for total in ("COLLECTIONS", "CONTENT-ITEMS", "UTF8-BYTES"):
        assert f"_RTE-CPV-{total}" in aggregate
    assert "RTE-F-CONTROL-COLLECTIONS AND" in limits
    assert "RTE-F-CONTROLS AND 0= AND" in limits
    assert "RTE-F-CONTROL-COLLECTIONS AND 0= IF" in limits
    assert "_RTE-L.OUTBOUND-PAYLOAD @ 152 U<" in limits
    assert "352 _RTE-LV-L @ _RTE-LIMIT-FLOOR?" in limits


def test_apt1_collection_predicates_and_pt_mapping_cover_tabs_explicitly() -> None:
    source = _text(PROVIDER)
    text_kind = _word(source, "_RTAPT-CONTROL-TEXT-COLLECTION-KIND?")
    feature_kind = _word(source, "_RTAPT-CONTROL-COLLECTION-KIND?")
    root_kind = _word(source, "_RTAPT-CONTROL-ROOT-KIND?")
    shape = _word(source, "_RTAPT-CONTROL-SHAPE?")
    copy_kind = _word(source, "_RTAPT-CONTROL-COPY-KIND-SHAPE?")
    to_pt = _word(source, "_RTAPT-CONTROL-KIND>PT")

    assert _constant(source, "RTAPT-CONTROL-TEXT-AREA") == 5
    assert _constant(source, "RTAPT-CONTROL-TEXT-GRID") == 6
    assert _constant(source, "RTAPT-CONTROL-TABSET") == 7
    assert _constant(source, "RTAPT-CONTROL-TAB") == 8
    assert "RTAPT-CONTROL-TEXT-AREA" in text_kind
    assert "RTAPT-CONTROL-TEXT-GRID" in text_kind
    assert "RTAPT-CONTROL-TABSET" not in text_kind
    assert "RTAPT-CONTROL-TAB" not in text_kind
    assert "_RTAPT-CONTROL-TEXT-COLLECTION-KIND?" in feature_kind
    assert "RTAPT-CONTROL-TABSET" in feature_kind
    assert "RTAPT-CONTROL-TAB" in feature_kind
    assert "RTAPT-CONTROL-MENUBAR" in root_kind
    assert "_RTAPT-CONTROL-TEXT-COLLECTION-KIND?" in root_kind
    assert "RTAPT-CONTROL-TABSET =" in root_kind
    assert "RTAPT-CONTROL-TAB =" not in root_kind
    assert "_RTAPT-CONTROL-COLLECTION-KIND?" in _word(
        source, "_RTAPT-CONTROL-LIMITS"
    )
    assert "_RTAPT-CONTROL-ROOT-KIND?" in _word(
        source, "_RTAPT-CONTROL-PARENT-PRIOR?"
    )
    for body in (shape, copy_kind):
        assert "_RTAPT-CONTROL-TEXT-COLLECTION-KIND?" in body
        assert "RTAPT-CONTROL-TABSET" in body
        assert "RTAPT-CONTROL-TAB" in body
    for suffix in ("TEXT-AREA", "TEXT-GRID", "TABSET", "TAB"):
        assert f"RTAPT-CONTROL-{suffix}" in to_pt
        assert f"PT-CONTROL-{suffix}" in to_pt


def test_apt1_binds_stx1_envelope_to_retry_quota_metadata() -> None:
    source = _text(PROVIDER)
    header = _word(source, "_RTAPT-STX1-HEADER?")
    metadata = _word(source, "_RTAPT-CONTROL-CONTENT-META?")
    common = _word(source, "_RTAPT-CONTROL-COMMON?")
    captured = _word(source, "_RTAPT-CAPTURED-BANKS?")
    copy_shape = _word(source, "_RTAPT-CONTROL-COPY-SHAPE?")
    publication_shape = _word(source, "_RTAPT-PUBLICATION-OP-SHAPE?")

    assert _constant(source, "_RTAPT-STX1-TAG") == 0x31585453
    assert _constant(source, "_RTAPT-STX1-VERSION") == 1
    assert "_RTAPT-BYTE-LE32@" in header
    assert "_RTAPT-BYTE-LE16@" in header
    _ordered(header, "72 U<", "_RTAPT-STX1-TAG", "4 +", "6 +", "40 +")
    assert "_RTAPT-CONTROL-COPY-CONTENT-HEADER?" not in metadata
    for body in (captured, copy_shape, publication_shape):
        _ordered(
            body,
            "_RTAPT-ZERO-SPAN?",
            "_RTAPT-CONTROL-COPY-CONTENT-HEADER?",
        )
    _ordered(
        common,
        "_RTAPT-CONTROL-TEXT-SPANS?",
        "_RTAPT-CONTROL-CONTENT-HEADER?",
        "_RTAPT-CONTROL-TEXT?",
    )


def test_neutral_control_dispatch_proves_borrowed_storage_before_text_scan() -> None:
    source = _text(ENGINE)
    dispatch = _word(source, "_RTE-CONTROL-DISPATCH-READY?")

    facade = dispatch.index("RTE-VALID?")
    record_span = dispatch.index("RTE-CONTROL-SIZE _RTE-SPAN?", facade)
    record_disjoint = dispatch.index("RTE-STORAGE-DISJOINT?", record_span)
    label_span = dispatch.index("_RTE-CONTROL-TEXT-SPAN?", record_disjoint)
    label_disjoint = dispatch.index("RTE-STORAGE-DISJOINT?", label_span)
    shortcut_span = dispatch.index("_RTE-CONTROL-TEXT-SPAN?", label_span + 1)
    shortcut_disjoint = dispatch.index("RTE-STORAGE-DISJOINT?", shortcut_span)
    content_span = dispatch.index("_RTE-CONTROL-CONTENT-SPAN?", shortcut_disjoint)
    content_disjoint = dispatch.index("RTE-STORAGE-DISJOINT?", content_span)
    text_and_fields = dispatch.index("RTE-CONTROL-VALID?", content_disjoint)
    assert (
        facade
        < record_span
        < record_disjoint
        < label_span
        < label_disjoint
        < shortcut_span
        < shortcut_disjoint
        < content_span
        < content_disjoint
        < text_and_fields
    )


def test_neutral_control_variable_spans_are_pairwise_disjoint() -> None:
    source = _text(ENGINE)
    disjoint = _word(source, "_RTE-CONTROL-SPANS-DISJOINT?")
    valid = _word(source, "RTE-CONTROL-VALID?")
    plan_item = _word(source, "_RTE-CPV-ITEM-BYTES-AUTHORITY?")

    assert disjoint.count("MSPAN-OVERLAP?") == 3
    for field in ("LABEL", "SHORTCUT", "CONTENT"):
        assert f"_RTE-CONTROL.{field}-A" in disjoint
        assert f"_RTE-CONTROL.{field}-U" in disjoint
    assert "_RTE-CONTROL-SPANS-DISJOINT?" in valid
    assert "_RTE-CONTROL-SPANS-DISJOINT?" in plan_item


def test_neutral_control_plan_proves_menu_and_tabset_roots_in_one_pass() -> None:
    source = _text(ENGINE)
    finish = _word(source, "_RTE-CPV-FINISH")
    identity = _word(source, "_RTE-CPV-ID?")
    parent = _word(source, "_RTE-CPV-PARENT-RECORD?")
    graph = _word(source, "_RTE-CPV-GRAPH?")
    root_start = _word(source, "_RTE-CPV-ROOT-START")
    menu_phase = _word(source, "_RTE-CPV-PHASE-MENU?")
    row_phase = _word(source, "_RTE-CPV-PHASE-ROW?")
    tab_phase = _word(source, "_RTE-CPV-PHASE-TAB?")
    group_order = _word(source, "_RTE-CPV-GROUP-ORDER?")
    group_state = _word(source, "_RTE-CPV-GROUP-STATE?")
    body = _word(source, "_RTE-CONTROL-PLAN-VALID-BODY")

    assert "VARIABLE _RTE-CPV-ROOT-ID" in source
    assert "0 _RTE-CPV-ROOT-ID !" in finish
    assert "_RTE-CPV-COUNT @ 0= IF" in identity
    assert "_RTE-CPV-FIRST-ID !" in identity
    assert "_RTE-CPV-PRIOR-ID @ 1 _RTE-UADD?" in identity
    assert "_RTE-CONTROL.ID @ <>" in identity
    _ordered(
        parent,
        "_RTE-CPV-ROOT-ID @ U<",
        "_RTE-CPV-PARENT-ID @ _RTE-CPV-FIRST-ID @ -",
        "_RTE-CPV-COUNT @ U<",
        "RTE-CONTROL-SIZE _RTE-UMUL?",
        "_RTE-CPV-ITEMS-A @ SWAP _RTE-UADD?",
        "_RTE-CONTROL.ID @ _RTE-CPV-PARENT-ID @ =",
    )
    assert "RTE-CONTROL-MENU-BAR" in graph
    assert "_RTE-CONTROL-ROOT-KIND?" in graph
    assert "RTE-CONTROL-TABSET" in graph
    assert "RTE-CONTROL-TAB" in graph
    assert "_RTE-CPV-ROOTS @ 1 _RTE-UADD?" in graph
    assert "_RTE-CPV-ROOT-START" in graph
    assert "_RTE-CONTROL.ID @ _RTE-CPV-ROOT-ID !" in root_start
    assert "_RTE-CPV-PHASE-MENUBAR" in graph
    assert "_RTE-CPV-PHASE-STANDALONE" in graph
    assert "_RTE-CPV-PHASE-TABSET" in graph
    assert "_RTE-CPV-ROOTS @ IF" not in graph
    assert "_RTE-CPV-PHASE-MENU?" in graph
    assert "_RTE-CPV-PHASE-ROW?" in graph
    assert "_RTE-CPV-PHASE-TAB?" in graph
    assert "RTE-CONTROL-MENU-BAR <>" in menu_phase
    assert "RTE-CONTROL-MENU <>" in row_phase
    assert "_RTE-CPV-PHASE-TABSET" in tab_phase
    assert "_RTE-CPV-PHASE-TAB" in tab_phase
    assert "RTE-CONTROL-TABSET <>" in tab_phase
    assert "_RTE-CPV-GROUP?" in tab_phase
    assert "_RTE-CONTROL.ORDER @" in group_order
    assert "_RTE-CPV-PRIOR-ORDER @ U> 0=" in group_order
    assert "_RTE-CPV-OPEN-SEEN @ IF" in group_state
    assert group_state.count("_RTE-CPV-SELECTED-SEEN @ IF") == 2
    assert "0 _RTE-CPV-ROOT-ID !" in body
    assert "_RTE-CPV-ROOTS @ 0<>" in body


def test_final_publication_audit_resets_each_menu_or_tabset_root() -> None:
    source = _text(PROVIDER)
    graph = _word(source, "_RTAPT-PF-CONTROL-DEFINE-GRAPH?")
    root_start = _word(source, "_RTAPT-PF-CONTROL-ROOT-START")
    tab = _word(source, "_RTAPT-PF-CONTROL-TAB?")
    audit = _word(source, "_RTAPT-OWNER-AUDIT-MATCH?")

    assert "_RTAPT-PF-CBAR-COUNT @ 1 _RTAPT-UADD?" in graph
    assert "_RTAPT-PF-CONTROL-PHASE-NONE <>" not in graph
    assert "RTAPT-CONTROL-TABSET" in graph
    assert "RTAPT-CONTROL-TAB" in graph
    assert "_RTAPT-PF-CONTROL-PHASE-TABSET" in graph
    assert "_RTAPT-PF-CONTROL-TAB?" in graph
    assert "_RTAPT-PF-COPY @ _RTAPT-CD.CONTROL @ _RTAPT-PF-CROOT-ID !" in root_start
    for per_root_state in (
        "_RTAPT-PF-CMENU-FIRST",
        "_RTAPT-PF-CMENU-LAST",
        "_RTAPT-PF-CPARENT",
        "_RTAPT-PF-CORDER",
        "_RTAPT-PF-COPEN-MENU",
        "_RTAPT-PF-CSELECTED-ROOT-CHILD",
        "_RTAPT-PF-CSELECTED-ITEM-PARENT",
    ):
        assert f"0 {per_root_state} !" in root_start
    assert "_RTAPT-PF-CROOT-ID @ <>" in tab
    assert "_RTAPT-PF-CORDER @ U> 0=" in tab
    assert "_RTAPT-PF-CSELECTED-ROOT-CHILD @ IF" in tab
    assert "_RTAPT-O.A-CBAR-COUNT @ IF" in audit
    assert "_RTAPT-PF-CONTROL-PHASE-NONE = IF" in audit
    assert "_RTAPT-O.A-CBAR-COUNT @ 1 <>" not in audit


def test_semantic_items_cannot_exist_without_their_control_target() -> None:
    source = _text(PROVIDER)
    ledgers = _word(source, "_RTAPT-OWNER-LEDGERS-FROM?")

    for target in ("ACTIVE", "HIDDEN", "PENDING"):
        assert re.search(
            rf"_RTAPT-O\.{target}-CONTROLS @ 0=\s+"
            rf"_RTAPT-LV-O @ _RTAPT-O\.{target}-CONTENT-ITEMS @ 0<> AND",
            ledgers,
        )


def test_apt1_bridge_maps_limits_explicitly_and_validates_neutral_copy_once() -> None:
    engine = _text(ENGINE)
    bridge = _text(BRIDGE)
    fields = (
        "FEATURES",
        "OWNER-RECORDS",
        "LIVE-OWNERS",
        "REGIONS",
        "RESOURCES",
        "OBJECTS",
        "SERIES",
        "OPS",
        "UPDATE-BYTES",
        "CHUNK-BYTES",
        "RESOURCE-BYTES",
        "IMAGE-WIDTH",
        "IMAGE-HEIGHT",
        "PATH-POINTS",
        "GLYPH-RUN-BYTES",
        "UTF8-BYTES",
        "SAMPLES-APPEND",
        "SERIES-HISTORY",
        "SAMPLE-SLOTS",
        "MIN-INTERVAL-US",
        "OUTBOUND-PAYLOAD",
    )
    copy = _word(bridge, "_RTAPTE-LIMITS-COPY")
    for field in fields:
        assert f"_RTAPT-L.{field} @" in copy
        assert f"_RTE-L.{field} !" in copy

    feature_map = _word(bridge, "_RTAPTE-FEATURES>RTE")
    assert "RTAPT-F-CONTROLS AND" in feature_map
    assert "RTE-F-CONTROLS OR" in feature_map
    assert "RTAPT-F-CONTROL-COLLECTIONS AND" in feature_map
    assert "RTE-F-CONTROL-COLLECTIONS OR" in feature_map
    callback = _word(bridge, "_RTAPTE-LIMITS@")
    assert callback.count("_RTAPTE-LS-ENGINE @ RTAPT-LIMITS@") == 1
    assert "RTAPT-LIMITS-VALID?" not in callback
    assert "RTE-LIMITS-VALID?" not in callback
    outer = _word(engine, "RTE-LIMITS@")
    _ordered(outer, "_RTE-F.LIMITS-XT @ EXECUTE", "RTE-LIMITS-VALID?")


def test_apt1_control_preflight_bridge_is_header_and_aggregate_only() -> None:
    source = _text(BRIDGE)
    preflight = _word(source, "_RTAPTE-CONTROL-PREFLIGHT")

    assert (
        "count variable-bytes aligned-variable max-variable last-id "
        "collection-controls semantic-items utf8-bytes"
    ) in preflight
    for field in (
        "OWNER",
        "GENERATION",
        "SURFACE-COLS",
        "SURFACE-ROWS",
        "REGION-ID",
        "REGION-X",
        "REGION-Y",
        "REGION-COLS",
        "REGION-ROWS",
        "CLIP-X",
        "CLIP-Y",
        "CLIP-COLS",
        "CLIP-ROWS",
        "REGION-Z",
        "REGION-FLAGS",
    ):
        assert f"_RTE-CP.{field} @" in preflight
    assert "_RTE-CP.ITEMS-A" not in preflight
    assert "_RTE-CP.ITEMS-U" not in preflight
    assert "?DO" not in preflight
    assert "LOOP" not in preflight
    assert "RTAPT-CONTROL-PREFLIGHT" in preflight


def test_apt1_bridge_maps_control_kind_and_state_without_shared_values() -> None:
    source = _text(BRIDGE)
    kind = _word(source, "_RTAPTE-CONTROL-KIND>RTAPT")
    state = _word(source, "_RTAPTE-CONTROL-STATE>RTAPT")
    convert = _word(source, "_RTAPTE-CONTROL>RTAPT")

    for neutral, provider in (
        ("MENU-BAR", "MENUBAR"),
        ("MENU", "MENU"),
        ("MENU-ITEM", "ITEM"),
        ("MENU-SEPARATOR", "SEPARATOR"),
        ("TEXT-AREA", "TEXT-AREA"),
        ("TEXT-GRID", "TEXT-GRID"),
        ("TABSET", "TABSET"),
        ("TAB", "TAB"),
    ):
        assert f"RTE-CONTROL-{neutral}" in kind
        assert f"RTAPT-CONTROL-{provider}" in kind
    for bit in ("VISIBLE", "ENABLED", "OPEN", "SELECTED", "CHECKED"):
        assert f"RTE-CONTROL-{bit} AND" in state
        assert f"RTAPT-CONTROL-F-{bit} OR" in state
    _ordered(
        convert,
        "_RTE-CONTROL.KIND @ _RTAPTE-CONTROL-KIND>RTAPT",
        "_RTE-CONTROL.STATE @ _RTAPTE-CONTROL-STATE>RTAPT",
        "_RTE-CONTROL.LABEL-A @",
        "_RTE-CONTROL.SHORTCUT-U @",
        "_RTE-CONTROL.CONTENT-A @",
        "_RTE-CONTROL.CONTENT-U @",
        "_RTE-CONTROL.CONTENT-ITEMS @",
        "_RTE-CONTROL.CONTENT-UTF8 @",
        "R> DROP R>",
    )


def test_apt1_bridge_installs_and_recognizes_every_control_callback() -> None:
    source = _text(BRIDGE)
    init = _word(source, "_RTAPTE-INIT-BODY")
    exact = _word(source, "_RTAPTE-FACADE?")
    callbacks = {
        "CONTROL-PREFLIGHT": "CONTROL-PREFLIGHT",
        "CONTROL-DEF": "CONTROL-DEFINE",
        "CONTROL-REPLACE": "CONTROL-REPLACE",
        "CONTROL-DROP": "CONTROL-DROP",
    }

    for field, callback in callbacks.items():
        assert f"['] _RTAPTE-{callback}" in init
        assert f"_RTE-F.{field}-XT !" in init
        assert f"_RTE-F.{field}-XT @" in exact
        assert f"['] _RTAPTE-{callback} =" in exact
