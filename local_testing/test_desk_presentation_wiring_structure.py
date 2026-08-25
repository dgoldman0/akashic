#!/usr/bin/env python3
"""Static contracts for optional Desk presentation-broker wiring."""

from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DESK = REPO_ROOT / "akashic" / "tui" / "applets" / "desk" / "desk.f"
DESK_APT1 = REPO_ROOT / "akashic" / "tui" / "desk-apt1.f"
HOST = REPO_ROOT / "akashic" / "tui" / "applet-host" / "host.f"


def _source(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _definition(source: str, word: str) -> str:
    match = re.search(
        rf"^:\s+{re.escape(word)}(?:\s|$).*?;\s*$",
        source,
        re.MULTILINE | re.DOTALL,
    )
    assert match is not None, word
    return match.group(0)


def test_baseline_desk_keeps_presentation_injection_zero_and_optional() -> None:
    source = _source(DESK)
    requires = re.findall(r"^REQUIRE\s+(.+?)\s*$", source, re.MULTILINE)

    assert not any("presentation/" in dependency for dependency in requires)
    assert "presentation-terminal.f" not in source
    assert "PT-SESSION" not in source
    for field in (
        "_DESK-PENDING-PRES-SERVICE",
        "_DESK-PENDING-PRES-BOUNDS-XT",
        "_DESK-PENDING-PRES-RETIRE-XT",
        "_DESK-PENDING-PRES-CONTEXT",
    ):
        assert f"0 {field} !" in source

    inject = _definition(source, "DESK-PRESENTATION-INJECT")
    assert "_DESK-CURRENT-STATE @" in inject
    assert "_DESK-PENDING-PRES-SERVICE @" in inject
    assert "_DPIC-SERVICE @ 0=" in inject
    assert "_DPIC-BOUNDS-XT @ 0=" in inject
    assert "_DPIC-RETIRE-XT @ 0=" in inject
    assert "_DPIC-CONTEXT @ 0=" not in inject
    assert "ALLOCATE" not in inject
    assert "XBUF" not in inject


def test_desk_publishes_exactly_one_optional_global_service() -> None:
    source = _source(DESK)
    setup = _definition(source, "_DESK-SERVICE-TABLE-SETUP")
    getter = _definition(source, "_DESK-SERVICE-PRESENTATION@")
    endpoint = _definition(source, "_DESK-ENDPOINT-SERVICE")
    exact_id = 'S" org.akashic.tui.presentation.v1"'

    assert source.count(exact_id) == 1
    assert "_DESK-PRES-SERVICE @ IF" in setup
    assert exact_id in setup
    assert "['] _DESK-SERVICE-PRESENTATION@ _DESK-SERVICE+" in setup
    assert "_DESK-PRES-SERVICE @" in getter
    assert "_DESK-SERVICE@" in endpoint
    assert "_DESK-USE-STATE" in endpoint


def test_every_complete_relayout_reports_all_live_child_activations() -> None:
    source = _source(DESK)
    relayout = _definition(source, "DESK-RELAYOUT")
    publish = _definition(source, "_DESK-PRES-RELAYOUT")
    remember = _definition(source, "_DESK-PRES-REMEMBER")
    status = _definition(source, "DESK-PRESENTATION-STATUS@")

    assert relayout.count("_DESK-PRES-RELAYOUT") == 2
    empty_path = relayout.split("_DESK-VIS-N @ DUP 0= IF", 1)[1].split(
        "THEN", 1
    )[0]
    assert "_DESK-PRES-RELAYOUT" in empty_path
    assert relayout.index("_DESK-EXPAND-FULLFRAME") < relayout.rindex(
        "_DESK-PRES-RELAYOUT"
    )
    assert relayout.rindex("UTUI-RELAYOUT") < relayout.rindex(
        "_DESK-PRES-RELAYOUT"
    )

    assert "_DESK-HEAD @" in publish
    assert "_SL-NEXT @" in publish
    assert "_SL-INST @" in publish
    assert "_DESK-PRES-BOUNDS-XT @ EXECUTE" in publish
    assert "_DESK-PRES-STATUS @ 0=" in remember
    assert "_DESK-PRES-STATUS !" in remember
    assert "_DESK-CURRENT-STATE @ IF" in status


def test_retirement_precedes_every_other_child_owner_release_and_free() -> None:
    desk = _source(DESK)
    release = _definition(desk, "_DESK-HOST-RELEASE")
    host = _source(HOST)
    close = _definition(host, "_AHOST-CLOSE-SLOT-FORCE")

    retire = release.index("_DESK-PRES-RETIRE-XT @")
    sandbox = release.index("DESK-SBOX-JOB-OWNER-DRAIN")
    xio = release.index("_DESK-XIO-RELEASE-OWNER")
    assert retire < sandbox < xio
    assert "_DESK-PRES-REMEMBER" in release
    assert "_DHR-REMEMBER" in release

    assert close.index("_AHC-SHUTDOWN") < close.index("_AHC-RELEASE")
    assert close.index("_AHC-RELEASE") < close.index("_AHC-FREE-REGION")
    assert close.index("_AHC-RELEASE") < close.index("_AHC-FREE-INST")


def test_apt1_composition_alone_owns_and_initializes_broker_storage() -> None:
    desk = _source(DESK)
    apt1 = _source(DESK_APT1)
    setup = _definition(apt1, "_A1D-PRES-SETUP")

    assert "REQUIRE presentation/broker.f" in apt1
    assert "PRES-SCOPED-BROKER-SIZE 7 + XBUF" in apt1
    assert "PRES-BROKER-CONFIG-SIZE 7 + XBUF" in apt1
    assert "PRES-ACTIVATION-DESC-SIZE 7 + XBUF" in apt1
    assert "APT1-DESK-PRES-SCOPE-COUNT PRES-SCOPE-RECORD-SIZE *" in apt1
    assert "[UNDEFINED] APT1-DESK-PRES-SCOPE-COUNT [IF]" in apt1
    assert "CREG-MAX-INSTANCES CONSTANT APT1-DESK-PRES-SCOPE-COUNT" in apt1
    assert "XBUF" not in desk

    bind = setup.index("PRES-SCOPED-BROKER-BIND")
    initialize = setup.index("PRES-SERVICE-INIT")
    inject = setup.index("DESK-PRESENTATION-INJECT")
    assert bind < initialize < inject
    assert "PRES-BROKER-C.SCOPE-RECORD-BYTES !" in setup
    assert "PRES-BROKER-C.SCOPE-RECORD-COUNT !" in setup
    assert "0 _A1D-PRES-CONFIG PRES-BROKER-C.SUPPORTED !" in setup


def test_resolver_authenticates_slot_endpoint_registry_and_exact_generation() -> None:
    source = _source(DESK_APT1)
    find = _definition(source, "_A1D-PRES-FIND-CALLER")
    resolve = _definition(source, "_A1D-PRES-RESOLVE")
    bounds = _definition(source, "_A1D-PRES-DESC-BOUNDS!")

    assert "_DESK-CURRENT-STATE @ 0=" in find
    assert find.index("_SL-INST @") < find.index("_SL-STATE @")
    assert "_A1D-PRES-LIVE-STATE?" in find

    found = resolve.index("_A1D-PRES-FIND-CALLER")
    endpoint = resolve.index("CINST.ENDPOINT @")
    identity = resolve.index("CINST.ID @")
    generation = resolve.index("CINST.GENERATION @")
    registry = resolve.index("CREG-INST-FIND")
    descriptor = resolve.index("PRES-ACTIVATION-DESC-INIT")
    assert found < endpoint < identity < generation < registry < descriptor
    assert "_DESK-ENDPOINT <>" in resolve
    assert "_A1D-PRES-BROKER <>" in resolve
    assert "PRES-S-STALE" in resolve

    assert "_SL-VISIBLE?" in bounds
    assert "_SL-RGN @" in bounds
    for accessor in ("RGN-ROW", "RGN-COL", "RGN-H", "RGN-W"):
        assert accessor in bounds
    assert "PRES-ACTIVATION.VISIBLE !" in bounds


def test_apt1_close_keeps_broker_storage_until_terminal_owner_is_settled() -> None:
    source = _source(DESK_APT1)
    uninstall = _definition(source, "_A1D-UNINSTALL")

    owner_close = uninstall.index("APTAS-UNINSTALL")
    owner_latch = uninstall.index("FALSE _A1D-INSTALLED !")
    broker_fini = uninstall.index("PRES-SERVICE-FINI")
    broker_latch = uninstall.index("FALSE _A1D-PRES-READY !")
    assert owner_close < owner_latch < broker_fini < broker_latch
    assert "DUP SCB-S-OK <> IF EXIT THEN" in uninstall
    assert "DUP PRES-S-OK <> IF EXIT THEN" in uninstall
