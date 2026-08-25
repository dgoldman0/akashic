"""Structural guards for the UIDL-first rich-terminal architecture."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
AKASHIC = ROOT / "akashic"


def _text(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def _word(source: str, name: str) -> str:
    match = re.search(rf"(?ms)^: {re.escape(name)}\b.*?;\s*$", source)
    assert match is not None, name
    return match.group(0)


def test_rich_terminal_is_not_an_applet_facing_scene_service() -> None:
    assert not (AKASHIC / "tui/presentation/api.f").exists()
    assert not (AKASHIC / "tui/presentation/broker.f").exists()

    desk = _text("akashic/tui/applets/desk/desk.f")
    composition = _text("akashic/tui/desk-apt1.f")
    assert "org.akashic.tui.presentation" not in desk
    assert "DESK-PRESENTATION-INJECT" not in desk
    assert "presentation/broker.f" not in composition
    assert "PRES-BROKER-DISCOVER" not in composition

    for applet in (AKASHIC / "tui/applets").rglob("*.f"):
        source = applet.read_text(encoding="utf-8")
        assert "presentation/" not in source, applet
        assert "PRES-BROKER-DISCOVER" not in source, applet
        assert "PT-RETAINED" not in source, applet


def test_uidl_context_remains_the_hosted_application_ui_authority() -> None:
    uidl = _text("akashic/liraq/uidl.f")
    tui = _text("akashic/tui/uidl-tui.f")
    shell = _text("akashic/tui/app-shell.f")
    host = _text("akashic/tui/applet-host/host.f")

    assert ": DEFINE-ELEMENT" in uidl
    assert ": EL-SET-RENDER" in uidl
    assert ": UIDL-DIRTY!" in uidl
    assert ": UTUI-PAINT" in tui
    assert ": UCTX-ALLOC" in tui
    assert ": UCTX-FREE" in tui
    assert ": ASHELL-PAINT-CHILD" in shell
    assert "REQUIRE ../uidl-tui.f" in host
    assert "UCTX-ALLOC" in host
    assert "AHS.UCTX" in host


def test_uidl_rich_terminal_lifecycle_is_ordered_and_context_local() -> None:
    tui = _text("akashic/tui/uidl-tui.f")

    for word in (
        "UTUI-RICH-TERM-ATTACH",
        "UTUI-RICH-TERM-VISIBLE!",
        "UTUI-RICH-TERM-STATUS",
        "UTUI-RICH-TERM-QUIESCE",
        "UTUI-RICH-TERM-DETACH",
    ):
        assert f": {word}" in tui

    # Composition installs one exact callback table; applications cannot
    # discover or replace it and the no-driver path remains unavailable.
    assert ": _UTUI-RICH-TERM-DRIVER!" in tui
    assert "_UTUI-RT-DRIVER-INSTALLED @ IF" in tui
    assert "_UTUI-RT-S-UNAVAILABLE DUP _UTUI-RT-STATUS !" in tui
    assert "CINST-SERVICE" not in tui
    assert "PRES-BROKER" not in tui

    # Only the backend token and lifecycle scalars enter UCTX.  The attach
    # descriptor is call-borrowed and every callback scratch cell is scrubbed.
    assert "_UTUI-RT-TOKEN      _UCTX-VARS 15 CELLS + !" in tui
    assert "_UTUI-RT-STATUS     _UCTX-VARS 16 CELLS + !" in tui
    assert "_UTUI-RT-VISIBLE    _UCTX-VARS 17 CELLS + !" in tui
    assert "_UTUI-RT-ATTACHED   _UCTX-VARS 18 CELLS + !" in tui
    assert "_UTUI-RT-QUIESCING  _UCTX-VARS 19 CELLS + !" in tui
    assert "_UTUI-RT-QUIESCED   _UCTX-VARS 20 CELLS + !" in tui
    assert "0 _UTUI-RTA-BINDING !" in tui
    assert "0 _UTUI-RT-ARG0 ! 0 _UTUI-RT-ARG1 ! 0 _UTUI-RT-ARG2 !" in tui

    # Rich projection observes UIDL dirt before the CELL renderer clears it.
    paint = _word(tui, "UTUI-PAINT")
    assert paint.index("_UTUI-RICH-TERM-PROJECT") < paint.index(
        "_UTUI-PAINT-ELEM"
    )

    # Relayout publishes only resolved geometry; hidden documents explicitly
    # carry region zero so a freed Desk tile can never be retained.
    relayout = _word(tui, "UTUI-RELAYOUT")
    assert relayout.index("_UTUI-DO-LAYOUT-REC") < relayout.index(
        "_UTUI-RICH-TERM-RELAYOUT"
    )
    assert "FALSE 0" in _word(tui, "_UTUI-RICH-TERM-RELAYOUT")

    # Quiesce erects the teardown barrier before invoking the backend.  Final
    # detach is independently retryable and gates every ordinary UIDL free.
    quiesce = _word(tui, "UTUI-RICH-TERM-QUIESCE")
    assert quiesce.index("-1 _UTUI-RT-QUIESCING !") < quiesce.index(
        "_UTUI-RT-CALL-QUIESCE"
    )
    detach = _word(tui, "UTUI-DETACH")
    assert detach.index("UTUI-RICH-TERM-DETACH ?DUP IF THROW THEN") < detach.index(
        "_UTUI-DEMATERIALIZE"
    )


def test_retained_contract_requires_internal_uidl_projection_now() -> None:
    contract = _text("docs/rich-terminal/AKASHIC-RICH-TERMINAL.md")
    cell_contract = _text("docs/rich-terminal/AKASHIC-CELL-BACKEND.md")
    ownership = _text(
        "docs/rich-terminal/APT-1-RETAINED-1-OWNERSHIP.md"
    )

    assert "UIDL is the sole application-facing UI description" in contract
    assert "There is therefore no rich-terminal service identifier" in contract
    assert "UIDL/UCTX integration is Phase 3, not deferred work" in contract
    assert "RTERM-HOST-BINDING-SIZE" in contract
    assert "RTERM-UCTX-QUIESCE" in contract
    assert "generic, consumer-neutral Akashic" in contract
    assert "may compose the same engine without" in contract
    assert "never source-`REQUIRE`s or copies" in contract
    assert "Pre-vertical qualification gate" in contract
    assert "before arbitrary `APP.SHUTDOWN`" in contract
    assert "Applications receive no" in ownership
    assert "private per-UCTX projection" in ownership
    assert "rich-terminal output coordinator" in cell_contract
    assert "PRESENT_BEGIN" in cell_contract
    assert "Phase 3 uses a handwritten SoundLab projection" not in contract
    assert "First production consumer: SoundLab" not in contract
