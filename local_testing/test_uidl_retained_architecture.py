"""Structural guards for the UIDL-first rich-terminal architecture."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
AKASHIC = ROOT / "akashic"


def _text(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def _word(source: str, name: str) -> str:
    match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", source)
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
    install = _word(tui, "_UTUI-RICH-TERM-DRIVER!")
    assert "context attach project relayout quiesce detach -- flag" in install
    assert "_UTUI-RT-DRIVER-CONTEXT @ _UTUI-RTI-CONTEXT @ =" in install
    assert "_UTUI-RTI-CONTEXT @ 0<>" in install
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

    # Every callback receives the same explicit composition context.  It is
    # immutable driver authority, not a singleton closure or UCTX field.
    for word in (
        "_UTUI-RT-DO-ATTACH",
        "_UTUI-RT-DO-PROJECT",
        "_UTUI-RT-DO-RELAYOUT",
        "_UTUI-RT-DO-QUIESCE",
        "_UTUI-RT-DO-DETACH",
    ):
        assert "_UTUI-RT-DRIVER-CONTEXT @" in _word(tui, word)
    assert "_UTUI-RT-DRIVER-CONTEXT" not in _word(tui, "_UTUI-RICH-TERM-CLEAR")

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


def test_generic_host_uidl_ready_hook_is_neutral_and_exactly_placed() -> None:
    host = _text("akashic/tui/applet-host/host.f")

    # The composition seam is exactly an xt plus an opaque caller context.
    # The generic host neither allocates backend state nor names a backend.
    assert "80 CONSTANT _AH-O-UIDL-READY-XT" in host
    assert "88 CONSTANT _AH-O-UIDL-READY-CONTEXT" in host
    assert "96 CONSTANT AHOST-SIZE" in host
    setter = _word(host, "AHOST-UIDL-READY!")
    body = _word(host, "_AHUR-BODY")
    invoke = _word(host, "_AHOST-UIDL-READY")
    assert "DUP >R AHOST.UIDL-READY-CONTEXT !" in setter
    assert "R> AHOST.UIDL-READY-XT !" in setter
    assert body.index("_AHUR-HOST @ _AHUR-SLOT @") < body.index(
        "_AHUR-HOST @ AHOST.UIDL-READY-CONTEXT @"
    ) < body.index("R> EXECUTE _AHUR-RESULT !")
    assert "['] _AHUR-BODY CATCH ?DUP IF _AHUR-RESULT ! THEN" in invoke
    for hook_word in (setter, body, invoke):
        for forbidden in (
            "APTSCB",
            "RTAPT",
            "RTERM-",
            "ALLOCATE",
            "UCTX-ALLOC",
            "RGN-NEW",
        ):
            assert forbidden not in hook_word

    # A successful region and loaded UIDL exist before composition is
    # notified.  Notification completes before APP.INIT is even looked up.
    launch = _word(host, "_AHL-BODY")
    ready_at = launch.index("_AHOST-UIDL-READY")
    assert launch.count("_AHOST-UIDL-READY") == 1
    assert launch.index("_AHOST-RELAYOUT") < launch.index(
        "AHS.RGN @ 0="
    ) < ready_at
    assert launch.index("UTUI-LOAD") < ready_at
    assert launch.index("ASHELL-LOAD-UIDL") < ready_at
    assert "\n    THEN\n    -1 _AHL-INIT-STARTED !" in launch[ready_at:]
    assert ready_at < launch.index("-1 _AHL-SLOT @ AHS.INIT-STARTED !")
    assert ready_at < launch.index("APP.INIT-XT @")


def test_generic_host_close_phases_and_init_boundary_are_persistent() -> None:
    host = _text("akashic/tui/applet-host/host.f")

    for declaration in (
        "0 CONSTANT AHS-CLOSE-S-LIVE",
        "1 CONSTANT AHS-CLOSE-S-QUIESCING",
        "2 CONSTANT AHS-CLOSE-S-QUIESCED",
        "3 CONSTANT AHS-CLOSE-S-SHUTDOWN-CLAIMED",
        "4 CONSTANT AHS-CLOSE-S-DETACHED",
    ):
        assert declaration in host
    assert "88 CONSTANT _AHS-O-CLOSE-PHASE" in host
    assert "96 CONSTANT _AHS-O-INIT-STARTED" in host
    assert "104 CONSTANT AHS-SIZE" in host
    assert "5 U<" in _word(host, "AHS-CLOSE-PHASE-VALID?")
    assert (
        "AHS.CLOSE-PHASE @ AHS-CLOSE-S-LIVE ="
        in _word(host, "AHS-CALLABLE?")
    )

    # INIT-STARTED is slot lifetime state, not only launch scratch.  Store it
    # before looking up the optional callback so a zero xt still counts as a
    # successfully crossed application-init boundary.
    launch = _word(host, "_AHL-BODY")
    init_started_at = launch.index("-1 _AHL-SLOT @ AHS.INIT-STARTED !")
    assert launch.index("-1 _AHL-INIT-STARTED !") < init_started_at
    assert init_started_at < launch.index("APP.INIT-XT @")

    # Shutdown ownership is claimed before inspecting INIT-STARTED.  A false
    # field skips both application callbacks, but leaves the phase claimed so
    # the force path can still perform the independent UIDL detach.
    shutdown = _word(host, "_AHC-SHUTDOWN")
    claim_at = shutdown.index(
        "AHS-CLOSE-S-SHUTDOWN-CLAIMED _AHC-SLOT @ AHS.CLOSE-PHASE !"
    )
    init_guard_at = shutdown.index("AHS.INIT-STARTED @ 0= OR IF EXIT THEN")
    assert claim_at < init_guard_at < shutdown.index("AHS-ACTIVATE")
    assert init_guard_at < shutdown.index("APP.SHUTDOWN-XT @")

    force = _word(host, "_AHOST-CLOSE-SLOT-FORCE")
    assert force.index("['] _AHC-SHUTDOWN CATCH") < force.index(
        "AHS-CLOSE-S-SHUTDOWN-CLAIMED = IF"
    ) < force.index("['] _AHC-DETACH CATCH")
    assert "INIT-STARTED" not in _word(host, "_AHC-DETACH")


def test_generic_host_quiesces_and_detaches_before_releasing_children() -> None:
    host = _text("akashic/tui/applet-host/host.f")

    quiesce = _word(host, "_AHQS-BODY")
    assert quiesce.index(
        "AHS-CLOSE-S-QUIESCING _AHQS-SLOT @ AHS.CLOSE-PHASE !"
    ) < quiesce.index("UTUI-RICH-TERM-QUIESCE")
    assert quiesce.index("UTUI-RICH-TERM-QUIESCE") < quiesce.index(
        "_AHQS-SLOT @ AHS-CTX-SAVE"
    ) < quiesce.index(
        "AHS-CLOSE-S-QUIESCED _AHQS-SLOT @ AHS.CLOSE-PHASE !"
    )

    # Restore the caller's original context even if traversal or an individual
    # quiesce throws; preserve the first error from either operation.
    quiesce_all = _word(host, "AHOST-QUIESCE-ALL")
    quiesce_all_body = _word(host, "_AHQA-BODY")
    assert "_AHQA-HOST @ AHOST.HEAD @" in quiesce_all_body
    assert "DUP _AHOST-QUIESCE-SLOT ?DUP IF THROW THEN" in quiesce_all_body
    assert quiesce_all_body.index("_AHOST-QUIESCE-SLOT") < quiesce_all_body.index(
        "AHS.NEXT @"
    )
    assert quiesce_all.index(
        "ASHELL-ACTIVE-CTX _AHQA-ORIGINAL-CTX !"
    ) < quiesce_all.index("['] _AHQA-BODY CATCH _AHQA-REMEMBER")
    assert quiesce_all.index(
        "['] _AHQA-BODY CATCH _AHQA-REMEMBER"
    ) < quiesce_all.index("['] _AHQA-RESTORE CATCH _AHQA-REMEMBER")
    assert (
        "_AHQA-ORIGINAL-CTX @ ASHELL-CTX-SWITCH"
        in _word(host, "_AHQA-RESTORE")
    )

    detach = _word(host, "_AHC-DETACH")
    assert detach.index("AHS-CLOSE-S-SHUTDOWN-CLAIMED <>") < detach.index(
        "UTUI-DETACH"
    )
    assert detach.index("AHS-CTX-RESTORE") < detach.index(
        "UTUI-DETACH"
    ) < detach.index("AHS-CTX-SAVE")
    assert detach.index("UTUI-DETACH") < detach.index(
        "AHS-CLOSE-S-DETACHED _AHC-SLOT @ AHS.CLOSE-PHASE !"
    ) < detach.index("0 _AHC-SLOT @ AHS.HAS-UIDL !")

    # The force path realizes the cross-word ordering: quiesce, shutdown
    # (which claims before APP.SHUTDOWN), detach, HAS clear, then destruction.
    shutdown = _word(host, "_AHC-SHUTDOWN")
    assert shutdown.index("AHS-CLOSE-S-SHUTDOWN-CLAIMED") < shutdown.index(
        "APP.SHUTDOWN-XT @"
    )
    force = _word(host, "_AHOST-CLOSE-SLOT-FORCE")
    ordered = (
        "_AHOST-QUIESCE-SLOT",
        "['] _AHC-SHUTDOWN CATCH",
        "['] _AHC-DETACH CATCH",
        "AHS-CLOSE-S-DETACHED <> IF",
        "['] _AHC-RELEASE CATCH",
        "['] _AHC-CLOSED CATCH",
        "_AHOST-UNLINK",
        "['] _AHC-FREE-UIDL-BUF CATCH",
        "['] _AHC-FREE-UCTX CATCH",
        "['] _AHC-FREE-REGION CATCH",
        "['] _AHC-UNREGISTER CATCH",
        "['] _AHC-FREE-INST CATCH",
        "['] _AHC-FREE-SLOT CATCH",
    )
    assert [force.index(token) for token in ordered] == sorted(
        force.index(token) for token in ordered
    )


def test_preserved_close_drain_and_launch_rollback_do_not_relayout_early() -> None:
    host = _text("akashic/tui/applet-host/host.f")

    request = _word(host, "AHOST-REQUEST-CLOSE-ID")
    closed_at = request.index("_AHI-CLOSED @ IF")
    preserved_at = request.index("ELSE", closed_at)
    assert request.count("_AHI-RELAYOUT") == 1
    assert "_AHI-RELAYOUT" in request[closed_at:preserved_at]
    assert "APP-CLOSE-D-DEFER _AHI-DECISION !" in request[preserved_at:]
    assert "_AHI-RELAYOUT" not in request[preserved_at:]
    assert "_AHI-HOST @ _AHOST-RELAYOUT" in _word(host, "_AHI-RELAYOUT")

    drain = _word(host, "AHOST-DRAIN")
    assert drain.count("_AHOST-CLOSE-SLOT-FORCE") == 1
    assert drain.index("_AHOST-CLOSE-SLOT-FORCE") < drain.index(
        "_AHD-REMEMBER"
    ) < drain.index("0= IF _AHD-IOR @ EXIT THEN")

    rollback = _word(host, "_AHL-ROLLBACK")
    assert "_AHL-SLOT @ _AHL-HOST @ _AHOST-CLOSE-SLOT-FORCE" in rollback
    assert "_AHR-REMEMBER _AHR-CLOSED !" in rollback
    assert rollback.count("_AHR-RELAYOUT") == 1
    assert (
        "_AHR-CLOSED @ IF\n"
        "        ['] _AHR-RELAYOUT CATCH _AHR-REMEMBER\n"
        "    THEN"
    ) in rollback
    assert "_AHL-HOST @ _AHOST-RELAYOUT" in _word(host, "_AHR-RELAYOUT")


def test_non_live_host_slots_are_gated_from_callbacks_and_dispatch() -> None:
    host = _text("akashic/tui/applet-host/host.f")

    for word in ("AHOST-VCOUNT", "_AHOST-AUTOFOCUS", "AHOST-PAINT"):
        assert (
            "DUP AHS-CALLABLE? OVER AHS-VISIBLE? AND IF"
            in _word(host, word)
        )
    assert (
        "DUP AHS-CALLABLE? IF AHS.INST @ ELSE DROP 0 THEN"
        in _word(host, "AHOST-FOCUSED-INSTANCE")
    )
    for word in ("AHOST-FOCUS-ID", "AHOST-MINIMIZE-ID", "AHOST-RESTORE"):
        source = _word(host, word)
        assert source.index("AHS-CALLABLE? 0= IF") < source.index("AHS.STATE !")

    contains = _word(host, "_AHT-SLOT-CONTAINS?")
    assert contains.index("AHS-CALLABLE? 0= IF") < contains.index("AHS.RGN @")
    tile_at = _word(host, "AHOST-TILE-AT")
    assert tile_at.count("_AHT-SLOT-CONTAINS?") == 2
    mouse = _word(host, "AHOST-DISPATCH-MOUSE")
    assert mouse.index("AHOST-TILE-AT") < mouse.index("UTUI-DISPATCH-MOUSE")

    key = _word(host, "AHOST-DISPATCH-KEY")
    key_gate = key.index("AHS-CALLABLE? 0= IF 0 EXIT THEN")
    assert key_gate < key.index("APP.EVENT-XT @")
    assert key_gate < key.index("UTUI-DISPATCH-KEY")

    tick = _word(host, "AHOST-TICK")
    tick_gate = tick.index("OVER AHS-CALLABLE? AND IF")
    assert tick_gate < tick.index("AHS-ACTIVATE")
    assert tick_gate < tick.index("APP.TICK-XT @")
    paint = _word(host, "AHOST-PAINT")
    assert paint.index("AHS-CALLABLE?") < paint.index("ASHELL-PAINT-CHILD")

    close_one = _word(host, "AHOST-REQUEST-CLOSE-ID")
    assert re.search(
        r"AHS-CALLABLE\? IF\s+"
        r"_AHI-SLOT @ _AHI-REASON @ _AHOST-REQUEST-CLOSE-SLOT\s+"
        r"ELSE\s+APP-CLOSE-D-ALLOW",
        close_one,
    )
    close_all = _word(host, "AHOST-REQUEST-CLOSE-ALL")
    assert re.search(
        r"DUP AHS-CALLABLE\? IF\s+"
        r"DUP _AHALL-REASON @ _AHOST-REQUEST-CLOSE-SLOT\s+"
        r"ELSE\s+APP-CLOSE-D-ALLOW",
        close_all,
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
