"""Seconds-only structural locks for the focused UIDL hybrid adapter."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
ADAPTER = ROOT / "akashic/tui/rich-terminal/uidl-hybrid-adapter.f"


def _source() -> str:
    return ADAPTER.read_text(encoding="utf-8")


def _word(source: str, name: str) -> str:
    match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", source)
    assert match is not None, name
    return match.group(0)


def _ordered(source: str, *needles: str) -> None:
    positions = [source.index(needle) for needle in needles]
    assert positions == sorted(positions)


def test_adapter_stays_at_the_generic_uidl_snapshot_boundary() -> None:
    source = _source()
    for required in (
        "REQUIRE ../applet-host/host.f",
        "REQUIRE ../uidl-menu-snapshot.f",
        "AHOST-UIDL-READY!",
        "_UTUI-PROJECTION-ADAPTER!",
        "UMSN-CAPTURE",
    ):
        assert required in source
    lowered = source.lower()
    for forbidden in (
        "pad-entry", "daybook-entry", "desk-paint", "rte-owner-open",
        "rte-retained-begin", "rte-control-define", "sha3",
    ):
        assert forbidden not in lowered


def test_capture_uses_inactive_bank_and_publishes_selector_last() -> None:
    source = _source()
    project = _word(source, "_RUHA-PROJECT")
    _ordered(
        project,
        "_RUHA-A.ACTIVE-BANK @ 0= IF 1 ELSE 0 THEN",
        "UMSN-CAPTURE",
        "_RUHA-S.GENERATION !",
        "_RUHA-S.RECORDS-A !",
        "_RUHA-S.TEXT-A !",
        "_RUHA-A.GENERATION !",
        "_RUHA-A.ACTIVE-BANK !",
    )
    assert project.count("UMSN-CAPTURE") == 1
    assert project.index("UMSN-S-OK <>") < project.index(
        "_RUHA-A.ACTIVE-BANK !"
    )


def test_projection_selects_the_normal_focused_visible_host_slot() -> None:
    source = _source()
    selected = _word(source, "_RUHA-RECORD-SELECTED?")
    ready = _word(source, "RUHA-AHOST-UIDL-READY")
    assert "AHS-VISIBLE?" in selected
    assert "AHOST.FOCUS @" in selected
    assert "_RUHA-RECORD-IDENTITY?" in selected
    assert "_UTUI-PROJECTION-ATTACH" in ready
    for forbidden in ("APP.NAME", "APP.ID", "PAD", "DAYBOOK"):
        assert forbidden not in selected + ready


def test_constructor_owns_only_caller_bounded_disjoint_banks() -> None:
    source = _source()
    init = _word(source, "RUHA-INIT")
    header = _word(source, "_RUHA-HEADER?")
    ranges = _word(source, "_RUHA-I-RANGES?")
    pairwise = _word(source, "_RUHA-I-PAIRWISE?")
    assert "XBUF" not in source
    assert "ALLOCATE" not in source
    assert "_RUHA-I-RANGES? 0=" in init
    assert "_RUHA-A.SELF @ 2 PICK = AND" in header
    assert "UMSN-WORK-ENTRY-SIZE MOD" in ranges
    assert "UMSN-RECORD-SIZE MOD" in ranges
    assert pairwise.count("_RUHA-DISJOINT?") == 10


def test_lifecycle_invalidates_borrowed_snapshot_before_state_changes() -> None:
    source = _source()
    relayout = _word(source, "_RUHA-RELAYOUT")
    quiesce = _word(source, "_RUHA-QUIESCE")
    detach = _word(source, "_RUHA-DETACH")
    _ordered(
        relayout,
        "_RUHA-INVALIDATE-TOKEN",
        "_RUHA-R.VISIBLE !",
    )
    _ordered(
        quiesce,
        "_RUHA-INVALIDATE-TOKEN",
        "_RUHA-RECORD-QUIESCED _RUHA-Q-RECORD",
    )
    _ordered(
        detach,
        "_RUHA-INVALIDATE-TOKEN",
        "RUHA-RECORD-SIZE 0 FILL",
    )
    all_free = _word(source, "_RUHA-ALL-FREE?")
    assert "?DO" in all_free
    assert "R@" not in all_free

    host_fini = _word(source, "RUHA-HOST-FINI")
    _ordered(
        host_fini,
        "AHOST.UIDL-READY-XT @",
        "AHOST.UIDL-READY-CONTEXT @",
        "0 0 3 PICK AHOST-UIDL-READY!",
        "_RUHA-A.HOST !",
    )
