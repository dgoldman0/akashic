"""Structural guards for neutral TUI and rich-terminal composition."""

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


def _forth_code(source: str) -> str:
    return "\n".join(line.split("\\", 1)[0] for line in source.splitlines())


def _registered_action_names(relative: str) -> tuple[str, ...]:
    source = _text(relative)
    return tuple(
        re.findall(r'S"\s+([^"\n]+)"\s+\[\'\]\s+\S+\s+UTUI-DO!', source)
    )


def test_rich_terminal_is_not_an_applet_facing_scene_service() -> None:
    assert not (AKASHIC / "tui/presentation/api.f").exists()
    assert not (AKASHIC / "tui/presentation/broker.f").exists()

    desk = _text("akashic/tui/applets/desk/desk.f")
    composition = _text("akashic/tui/desk-apt1.f")
    assert "org.akashic.tui.presentation" not in desk
    assert "DESK-PRESENTATION-INJECT" not in desk
    assert "presentation/broker.f" not in composition
    assert "PRES-BROKER-DISCOVER" not in composition

    forbidden_require = re.compile(
        r"(?m)^\s*REQUIRE\s+\S*(?:"
        r"rich-terminal\.f|rich-terminal/|desk-apt1\.f|"
        r"app-shell-apt1\.f|screen-backend-apt1\.f|"
        r"apt1-engine\.f|screen-adapter-apt1\.f)\s*$"
    )
    protocol_word = re.compile(
        r"(?<![A-Z0-9_])(?:PT|_PT|APTSCB|_APTSCB|APTAS|_APTAS|"
        r"RTAPT|_RTAPT|RTAPTSCB|_RTAPTSCB|RTERM|_RTERM)-"
    )

    for applet in (AKASHIC / "tui/applets").rglob("*.f"):
        source = applet.read_text(encoding="utf-8")
        code = _forth_code(source)
        assert "presentation/" not in source, applet
        assert "PRES-BROKER-DISCOVER" not in source, applet
        assert "PT-RETAINED" not in source, applet
        assert forbidden_require.search(code) is None, applet
        assert protocol_word.search(code) is None, applet


def test_lower_uidl_lifecycle_has_no_renderer_vocabulary() -> None:
    lower_paths = (
        "akashic/tui/uidl-tui.f",
        "akashic/liraq/uidl-semantic.f",
        "akashic/tui/app-shell.f",
        "akashic/tui/applet-host/host.f",
        "akashic/tui/applets/desk/desk.f",
    )
    neutral_docs = (
        "docs/tui/uidl-tui.md",
        "docs/tui/app-shell.md",
        "docs/tui/applet-host.md",
        "docs/tui/applets/desk/desk.md",
    )
    renderer_vocabulary = re.compile(
        r"(?i)(?:rich[- ]terminal|"
        r"(?<![A-Z0-9_])_?(?:RTERM|RTAPT|APTSCB|APTAS)(?:-|\b)|"
        r"(?<![A-Z0-9_])_?PT-|\bAPT(?:-?1)?\b)"
    )
    for relative in lower_paths + neutral_docs:
        assert renderer_vocabulary.search(_text(relative)) is None, relative

    # Ordinary consumers know only the generic UIDL lifecycle.  Composition
    # and provider attachment stay below uidl-tui's private projection seam.
    for relative in lower_paths[1:]:
        source = _text(relative)
        assert "UTUI-PROJECTION" not in source, relative
        assert "_UTUI-PROJ" not in source, relative


def test_superseded_uidl_projection_prototypes_and_providers_are_absent() -> None:
    prototypes = (
        "akashic/tui/rich-terminal/uidl-projector.f",
        "akashic/tui/rich-terminal/uidl-driver.f",
        "akashic/tui/rich-terminal/screen-plane.f",
    )
    for relative in prototypes:
        assert not (ROOT / relative).exists(), relative

    remaining_source = "\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted(AKASHIC.rglob("*.f"))
    )
    for provider in (
        "akashic-tui-rterm-uidl-projector",
        "akashic-tui-rterm-uidl1",
        "akashic-tui-rich-screen-plane",
    ):
        assert f"PROVIDED {provider}" not in remaining_source
    for retired_prefix in ("RUPJ-", "RTSCREEN-", "RTERM-S-"):
        assert retired_prefix not in remaining_source

    engine = _text("akashic/tui/rich-terminal/engine.f")
    assert "PROVIDED akashic-tui-rte" in engine
    for status in (
        "RTE-S-OK",
        "RTE-S-WOULD-BLOCK",
        "RTE-S-UNAVAILABLE",
        "RTE-S-CAPACITY",
        "RTE-S-STALE",
        "RTE-S-INVALID",
        "RTE-S-SESSION-LOST",
        "RTE-S-SOURCE",
    ):
        assert f"CONSTANT {status}" in engine


def test_uidl_action_registry_owns_and_compares_exact_names() -> None:
    tui = _text("akashic/tui/uidl-tui.f")
    register = _word(tui, "_UTUI-DO-BODY")
    public_register = _word(tui, "UTUI-DO!")
    find = _word(tui, "_UTUI-ACT-FIND-BODY")

    assert "1536 CONSTANT _UTUI-ACTS-SZ" in tui
    assert "24 CONSTANT _UTUI-ACT-ENTRY-SIZE" in tui
    assert "_UTUI-MAX-ACTS" not in tui
    assert "_UTUI-ACT-HASH" not in tui
    assert "MSPAN-NONWRAPPING?" in register
    assert "MSPAN-OVERLAP?" in register
    assert register.index("CMOVE") < register.index("_UTUI-ACT-CNT +!")
    assert register.index("_UTUI-ACT-ENTRY-OFF @ OVER !") < register.index(
        "_UTUI-ACT-CNT +!"
    )
    assert "_UTUI-ACT-REG-CLEAR" in public_register
    assert "STR-STR=" in find
    assert "0 ?DO" in find
    assert "UNLOOP EXIT" in find
    assert "_UTUI-ACT-FRONTIER?" in register
    assert "_UTUI-ACTS-SZ CONSTANT _UCTX-ACTS-SZ" in tui

    expected = {
        "akashic/tui/applets/pad/pad.f": (32, 1025),
        "akashic/tui/applets/daybook/daybook.f": (14, 441),
    }
    for relative, (count, arena_bytes) in expected.items():
        names = _registered_action_names(relative)
        used = count * 24 + sum(len(name.encode("utf-8")) for name in names)
        assert len(names) == count
        assert used == arena_bytes
        assert used <= 1536


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


def test_uidl_projection_lifecycle_is_ordered_and_context_local() -> None:
    tui = _text("akashic/tui/uidl-tui.f")
    shell = _text("akashic/tui/app-shell.f")

    for word in ("UTUI-VISIBLE!", "UTUI-QUIESCE", "UTUI-DETACH"):
        assert f": {word}" in tui
    for private_word in (
        "_UTUI-PROJECTION-ATTACH",
        "_UTUI-PROJECTION-ADAPTER!",
        "_UTUI-PROJECTION-DETACH",
    ):
        assert f": {private_word}" in tui
    assert ": UTUI-PROJECTION-STATUS" not in tui
    for legacy_name in (
        "UTUI-RICH-TERM-ATTACH",
        "UTUI-RICH-TERM-VISIBLE!",
        "UTUI-RICH-TERM-STATUS",
        "UTUI-RICH-TERM-QUIESCE",
        "UTUI-RICH-TERM-DETACH",
        "_UTUI-RICH-TERM-DRIVER!",
        "_UTUI-RT-",
        "_UTUI-RTA-",
    ):
        assert legacy_name not in tui

    # Composition installs one exact callback table; applications cannot
    # discover or replace it and the no-driver path remains unavailable.
    assert ": _UTUI-PROJECTION-ADAPTER!" in tui
    assert "_UTUI-PROJ-ADAPTER-INSTALLED @ IF" in tui
    install = _word(tui, "_UTUI-PROJECTION-ADAPTER!")
    assert "context attach project relayout quiesce detach -- flag" in install
    assert "_UTUI-PROJ-ADAPTER-CONTEXT @ _UTUI-PAI-CONTEXT @ =" in install
    assert "_UTUI-PAI-CONTEXT @ 0<>" in install
    assert "_UTUI-PROJ-S-UNAVAILABLE DUP _UTUI-PROJ-STATUS !" in tui
    assert "CINST-SERVICE" not in tui
    assert "PRES-BROKER" not in tui

    # Only the adapter token and lifecycle scalars from projection authority
    # enter UCTX.  Menu lifecycle is also document-local; the attach descriptor
    # remains call-borrowed and every callback scratch cell is scrubbed.
    context_init = _word(tui, "_UCTX-INIT-VARS")
    context_fields = (
        ("_UTUI-PROJ-TOKEN", 15),
        ("_UTUI-PROJ-STATUS", 16),
        ("_UTUI-VISIBLE", 17),
        ("_UTUI-PROJ-ATTACHED", 18),
        ("_UTUI-QUIESCING", 19),
        ("_UTUI-QUIESCED", 20),
    )
    for field, slot in context_fields:
        assert re.search(
            rf"(?m)^\s*{re.escape(field)}\s+_UCTX-VARS {slot} CELLS \+ !",
            context_init,
        )
    menu_fields = (
        ("_UTUI-MENU-OPEN", 21),
        ("_UTUI-MENU-SAVED-FOC", 22),
        ("_UTUI-MENU-SAVE-ROW", 23),
        ("_UTUI-MENU-SAVE-H", 24),
        ("_UTUI-MENU-SAVE-W", 25),
        ("_UTUI-MENU-SAVE-Z", 26),
    )
    for field, slot in menu_fields:
        assert re.search(
            rf"(?m)^\s*{re.escape(field)}\s+_UCTX-VARS {slot} CELLS \+ !",
            context_init,
        )
    assert "29 CONSTANT _UCTX-NVAR" in tui
    assert "232 CONSTANT _UCTX-VAR-SZ" in tui
    assert "11 CONSTANT _UCTX-NPOOL" in tui
    assert "107,752 bytes" in tui
    assert "107,752" in _text("docs/tui/uidl-tui.md")
    assert "0 _UTUI-PAA-BINDING !" in tui
    assert "0 _UTUI-PROJ-ARG0 ! 0 _UTUI-PROJ-ARG1 ! 0 _UTUI-PROJ-ARG2 !" in tui

    # Every callback receives the same explicit composition context.  It is
    # immutable adapter authority, not a singleton closure or UCTX field.
    for word in (
        "_UTUI-PROJ-DO-ATTACH",
        "_UTUI-PROJ-DO-PROJECT",
        "_UTUI-PROJ-DO-RELAYOUT",
        "_UTUI-PROJ-DO-QUIESCE",
        "_UTUI-PROJ-DO-DETACH",
    ):
        assert "_UTUI-PROJ-ADAPTER-CONTEXT @" in _word(tui, word)
    assert "_UTUI-PROJ-ADAPTER-CONTEXT" not in _word(tui, "_UTUI-PROJECTION-CLEAR")

    # A derived projection observes the completed ordinary draw while its
    # exact UCTX remains active.  UTUI painting itself has one renderer-neutral
    # job and never publishes a partial pre-app frame.
    paint = _word(tui, "UTUI-PAINT")
    assert "_UTUI-PROJECTION-PUBLISH" not in paint
    draw_complete = _word(tui, "UTUI-DRAW-COMPLETE")
    assert "_UTUI-PROJECTION-PUBLISH" in draw_complete
    child_body = _word(shell, "_ASPC-DRAW-BODY")
    assert child_body.index("APP.ACTIVATE-XT") < child_body.index(
        "UTUI-PAINT"
    ) < child_body.index("APP.PAINT-XT")
    child_paint = _word(shell, "ASHELL-PAINT-CHILD")
    assert child_paint.index("ASHELL-CTX-SWITCH") < child_paint.index(
        "RGN-USE"
    ) < child_paint.index("UTUI-DRAW-OBSERVE") < child_paint.index(
        "UTUI-DRAW-COMPLETE"
    )
    assert "['] _ASPC-DRAW-BODY UTUI-DRAW-OBSERVE 0= IF" in child_paint
    top_paint = _word(shell, "_ASHELL-PAINT")
    assert top_paint.index("UTUI-PAINT") < top_paint.index(
        "APP.PAINT-XT"
    ) < top_paint.index(
        "_ASHELL-DRAW-CURSOR"
    ) < top_paint.index("UTUI-DRAW-COMPLETE")
    assert "UTUI-DRAW-OBSERVE" not in top_paint
    assert child_paint.count("UTUI-DRAW-COMPLETE") == 1
    assert top_paint.count("UTUI-DRAW-COMPLETE") == 1

    # Relayout publishes only resolved geometry; hidden documents explicitly
    # carry region zero so a freed Desk tile can never be retained.
    relayout = _word(tui, "UTUI-RELAYOUT")
    assert relayout.index("_UTUI-DO-LAYOUT-REC") < relayout.index(
        "_UTUI-PROJECTION-RELAYOUT"
    )
    assert "FALSE 0" in _word(tui, "_UTUI-PROJECTION-RELAYOUT")

    # Quiesce erects the teardown barrier before invoking the adapter.  Final
    # detach is independently retryable and gates every ordinary UIDL free.
    quiesce = _word(tui, "UTUI-QUIESCE")
    assert quiesce.index("-1 _UTUI-QUIESCING !") < quiesce.index(
        "_UTUI-PROJ-CALL-QUIESCE"
    )
    detach = _word(tui, "UTUI-DETACH")
    assert detach.index("_UTUI-PROJECTION-DETACH ?DUP IF THROW THEN") < detach.index(
        "_UTUI-DEMATERIALIZE"
    )


def test_resolved_tree_observation_is_one_pass_coherent_and_semantic() -> None:
    tui = _text("akashic/tui/uidl-tui.f")
    docs = _text("docs/tui/uidl-tui.md")
    normalized_docs = " ".join(docs.split())

    walk = _word(tui, "_UTUI-RST-WALK")
    node = _word(tui, "_UTUI-RST-NODE")
    load = _word(tui, "_UTUI-RST-LOAD-NODE")
    single_capture = _word(tui, "_UTUI-ELEM-RESOLVED-CAPTURE-BODY")
    complete = _word(tui, "_UTUI-RST-COMPLETE?")
    semantic = _word(tui, "_UTUI-RST-EACH-SEMANTIC")
    public = _word(tui, "UTUI-RESOLVED-TREE-EACH")

    assert walk.count("RECURSE") == 1
    assert "_UTUI-RST-NODE" in walk
    assert "_UTUI-RS-RESOLVE" not in walk + node + load
    assert "_UTUI-RS-TARGET-CLEAR" in load
    assert "_UTUI-RS-TARGET-VALID?" in load
    assert "_UTUI-RS-WRITE" in load
    assert "ALLOCATE" not in walk + node + load
    assert single_capture.index("_UTUI-RS-CALL") < single_capture.index(
        "_UTUI-RS-DST !"
    ) < single_capture.index("_UTUI-RS-WRITE")

    # Stable pool holes are allowed, but a duplicated, cyclic, or unreachable
    # live entry cannot be silently omitted from an authoritative tree visit.
    assert "_UTUI-RST-SEEN + DUP C@" in node
    assert "_UTUI-RST-SEEN + C@" in complete
    assert "UE.TYPE @" in complete
    assert "UIDL-PARENT 5 PICK <>" in walk
    assert walk.index("UIDL-ELEM-INDEX?") < walk.index("UIDL-PARENT")
    assert walk.index("UIDL-ELEM-INDEX?") < walk.index("UIDL-NEXT-SIB")

    # A missing resolved lineage is a normal per-node condition: the element
    # is still visited, with no borrowed record, while malformed state aborts.
    unavailable_at = node.index("UTUI-RESOLVED-S-UNAVAILABLE = IF")
    assert "0 _UTUI-RST-VISIT" in node[unavailable_at:]
    assert "UTUI-RESOLVED-SIZE _UTUI-RST-VISIT" in node
    assert "UIDL-SEMANTIC-OBSERVE" in semantic
    assert "CATCH" in public
    assert "_UTUI-RST-CLEAR" in public
    for single_reader in (
        "UTUI-ELEM-RESOLVED-STATE@",
        "UTUI-ELEM-RESOLVED-CAPTURE",
    ):
        assert "_UTUI-RST-ACTIVE @ IF" in _word(tui, single_reader)

    # Closing a dropdown owns the raw VIS bit.  Neutral local visibility for
    # its rows instead retains all durable hiding and admission authorities.
    local = _word(tui, "_UTUI-MENU-ROW-LOCAL-VISIBLE-BODY?")
    select_local = _word(tui, "_UTUI-RST-LOCAL-VISIBLE?")
    assert "_UTUI-MENU-ROW?" in local
    assert "TSC-F-HIDDEN _UTUI-SCF-HIDE OR" in local
    assert "_UTUI-RUNTIME-F-HIDDEN" in local
    assert "_UTUI-SCF-VIS" not in local
    assert "UIDL-T-ITEM" in select_local
    assert "UIDL-T-SEPARATOR" in select_local
    assert "UIDL-PARENT ?DUP IF" in select_local
    assert "UIDL-TYPE UIDL-T-MENU = IF" in select_local
    assert "sidecar visibility predicate" in normalized_docs
    assert "VIS bit cleared merely because its menu is closed" in normalized_docs

    # Focused byte-oracle for the visibility equations.  A closed menu leaves
    # its row locally visible but not paintable; an offscreen parent does not
    # clip a positioned child which re-enters the root.
    root = (0, 0, 20, 40)

    def intersects(rect: tuple[int, int, int, int]) -> bool:
        row, col, height, width = rect
        rr, rc, rh, rw = root
        return (
            height > 0
            and width > 0
            and rh > 0
            and rw > 0
            and row < rr + rh
            and rr < row + height
            and col < rc + rw
            and rc < col + width
        )

    def projected(
        *,
        raw_visible: bool,
        durable_row_visible: bool | None,
        rect: tuple[int, int, int, int],
        ancestor_visible: bool,
        ancestor_available: bool = True,
        own_available: bool = True,
    ) -> tuple[bool, bool, bool]:
        available = ancestor_available and own_available
        local_visible = (
            raw_visible if durable_row_visible is None else durable_row_visible
        )
        lineage_visible = available and ancestor_visible and raw_visible
        return local_visible, lineage_visible and intersects(rect), available

    assert projected(
        raw_visible=False,
        durable_row_visible=True,
        rect=(2, 2, 1, 12),
        ancestor_visible=False,
    ) == (True, False, True)
    assert projected(
        raw_visible=True,
        durable_row_visible=None,
        rect=(3, 3, 1, 8),
        ancestor_visible=True,
        ancestor_available=False,
    ) == (True, False, False)
    parent_rect = (21, 0, 1, 40)
    child_rect = (1, 1, 1, 8)
    assert not intersects(parent_rect)
    assert projected(
        raw_visible=True,
        durable_row_visible=None,
        rect=child_rect,
        ancestor_visible=True,
    ) == (True, True, True)


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


def test_desk_wraps_child_hosting_in_a_neutral_composition_lifecycle() -> None:
    desk = _text("akashic/tui/applets/desk/desk.f")

    setter = _word(desk, "DESK-HOST-LIFECYCLE!")
    assert "_DESK-CURRENT-STATE @ IF 3DROP EXIT THEN" in setter
    ordered_stores = (
        "_DESK-PENDING-HOST-LIFECYCLE-CTX !",
        "_DESK-PENDING-HOST-FINI-XT !",
        "_DESK-PENDING-HOST-INIT-XT !",
    )
    assert [setter.index(token) for token in ordered_stores] == sorted(
        setter.index(token) for token in ordered_stores
    )

    init = _word(desk, "DESK-INIT-CB")
    host_init = init.index("_DESK-HOST AHOST-INIT")
    compose = init.index("_DESK-HOST-COMPOSE")
    autostart = init.index("_DESK-AUTOSTART-CATALOG")
    assert host_init < compose < autostart
    pending_copies = (
        "_DESK-PENDING-HOST-INIT-XT @ _DESK-HOST-INIT-XT !",
        "_DESK-PENDING-HOST-FINI-XT @ _DESK-HOST-FINI-XT !",
        "_DESK-PENDING-HOST-LIFECYCLE-CTX @",
        "0 _DESK-HOST-LIFECYCLE-PHASE !",
    )
    assert all(init.index(token) < host_init for token in pending_copies)

    compose_word = _word(desk, "_DESK-HOST-COMPOSE")
    phase = compose_word.index("1 _DESK-HOST-LIFECYCLE-PHASE !")
    execute = compose_word.index("_DESK-HOST-INIT-XT @ EXECUTE")
    assert phase < execute
    zero_pair = compose_word.index("_DESK-HOST-INIT-XT @ 0= IF")
    partial_fini = compose_word.index("_DESK-HOST-FINI-XT @", zero_pair)
    zero_exit = compose_word.index("EXIT", partial_fini)
    partial_init = compose_word.index("_DESK-HOST-FINI-XT @ 0=", zero_exit)
    assert zero_pair < partial_fini < zero_exit < partial_init < phase
    assert compose_word.count('ABORT" desk: incomplete host lifecycle hooks"') == 2
    assert (
        "_DESK-HOST _DESK-HOST-LIFECYCLE-CTX @\n"
        "    _DESK-HOST-INIT-XT @ EXECUTE ?DUP IF THROW THEN"
    ) in compose_word

    decompose = _word(desk, "_DESK-HOST-DECOMPOSE")
    fini_execute = decompose.index("_DESK-HOST-FINI-XT @ EXECUTE")
    finalized = decompose.index("2 _DESK-HOST-LIFECYCLE-PHASE !")
    assert fini_execute < finalized
    assert (
        "_DESK-HOST _DESK-HOST-LIFECYCLE-CTX @\n"
        "    _DESK-HOST-FINI-XT @ EXECUTE ?DUP IF THROW THEN"
    ) in decompose

    shutdown = _word(desk, "DESK-SHUTDOWN-CB")
    drain = shutdown.index("_DESK-HOST AHOST-DRAIN")
    fini = shutdown.index("['] _DSD-HOST-FINI CATCH")
    interop = shutdown.index("['] _DSD-INTEROP-FINI CATCH")
    practice = shutdown.index("['] _DSD-PRACTICE-FINI CATCH")
    assert drain < fini < interop < practice
    assert (
        "['] _DSD-HOST-FINI CATCH DUP _DSD-REMEMBER\n"
        "    0= IF\n"
        "        ['] _DSD-INTEROP-FINI CATCH DUP _DSD-REMEMBER\n"
        "        0= IF\n"
        "            ['] _DSD-PRACTICE-FINI CATCH _DSD-REMEMBER\n"
        "        THEN\n"
        "    THEN"
    ) in shutdown

    for forbidden in (
        "APTSCB",
        "RTAPT",
        "RTERM-",
        "PT-RETAINED",
        "rich-terminal/",
    ):
        assert forbidden not in setter
        assert forbidden not in init
        assert forbidden not in shutdown
        assert forbidden not in compose_word
        assert forbidden not in decompose


def test_desktop_apt1_leaf_composes_the_generic_hybrid_screen_producer() -> None:
    composition = _text("akashic/tui/desk-apt1.f")
    code = _forth_code(composition)
    normalized_composition = " ".join(composition.split())

    requirements = re.findall(r"(?m)^REQUIRE\s+(\S+)\s*$", code)
    for required in (
        "app-shell-apt1.f",
        "rich-terminal/screen-adapter-apt1.f",
        "rich-terminal/engine-apt1.f",
        "rich-terminal/hybrid-screen-producer.f",
        "applets/desk/desk.f",
    ):
        assert required in requirements
    for retired in (
        "rich-terminal/uidl-projector.f",
        "rich-terminal/uidl-driver.f",
        "rich-terminal/screen-plane.f",
    ):
        assert retired not in requirements
    assert "REQUIRE rich-terminal.f" not in code
    assert "same ordinary Desk/UIDL draw lifecycle" in normalized_composition
    assert "cells not claimed by those controls" in normalized_composition

    public_overrides = re.findall(
        r"(?m)^\[UNDEFINED\] (APT1-DESK-[A-Z0-9-]+) \[IF\]$", code
    )
    assert public_overrides == [
        "APT1-DESK-RX-CAPACITY",
        "APT1-DESK-MAX-COLS",
        "APT1-DESK-MAX-ROWS",
        "APT1-DESK-COLLECTION-NATIVE-CAPACITY",
        "APT1-DESK-TX-CAPACITY",
    ]
    assert (
        "APT1-DESK-MAX-COLS APT1-DESK-MAX-ROWS _A1D-CAPACITY*\n"
        "    CONSTANT _A1D-SCREEN-CELLS"
    ) in code
    assert "_DESK-MAX-INSTALLED CONSTANT _A1D-UIDL-BINDINGS" in code
    assert "_UTUI-MAX-ELEMS CONSTANT _A1D-UIDL-RECORDS" in code
    assert "_UCTX-STRS-SZ CONSTANT _A1D-UIDL-TEXT-U" in code
    assert (
        "_A1D-UIDL-BINDINGS _A1D-UIDL-RECORDS _A1D-CAPACITY*\n"
        "    CONSTANT _A1D-UIDL-AGGREGATE-RECORDS"
    ) in code
    assert (
        "_A1D-UIDL-BINDINGS _A1D-UIDL-TEXT-U _A1D-CAPACITY*\n"
        "    CONSTANT _A1D-UIDL-AGGREGATE-TEXT-U"
    ) in code
    assert (
        "[UNDEFINED] APT1-DESK-COLLECTION-NATIVE-CAPACITY [IF]\n"
        "_A1D-UIDL-AGGREGATE-TEXT-U\n"
        "    CONSTANT APT1-DESK-COLLECTION-NATIVE-CAPACITY\n"
        "[THEN]"
    ) in code
    assert (
        "APT1-DESK-MAX-COLS 8 _A1D-CAPACITY*\n"
        "    12 _A1D-CAPACITY+ CONSTANT _A1D-MAX-ROW-PAYLOAD-U"
    ) in code
    assert (
        "APT1-DESK-COLLECTION-NATIVE-CAPACITY\n"
        "    _A1D-CONTROL-PAYLOAD-FIXED-U _A1D-CAPACITY+\n"
        "    CONSTANT _A1D-MAX-COLLECTION-PAYLOAD-U"
    ) in code
    assert (
        "_A1D-MAX-ROW-PAYLOAD-U _A1D-MAX-COLLECTION-PAYLOAD-U MAX\n"
        "    CONSTANT _A1D-SELECTED-MAX-PAYLOAD-U"
    ) in code
    assert (
        "_A1D-FRAME-HEADER-U _A1D-SELECTED-MAX-PAYLOAD-U _A1D-CAPACITY+\n"
        "    CONSTANT _A1D-MIN-TX-CAPACITY"
    ) in code
    assert (
        "[UNDEFINED] APT1-DESK-TX-CAPACITY [IF]\n"
        "_A1D-MIN-TX-CAPACITY CONSTANT APT1-DESK-TX-CAPACITY\n"
        "[THEN]"
    ) in code
    assert (
        "APT1-DESK-COLLECTION-NATIVE-CAPACITY USCOL-ENTRY-HEADER-SIZE /\n"
        "    _A1D-REQUIRE-POSITIVE-CAPACITY\n"
        "    CONSTANT _A1D-RUHA-COLLECTION-DESCRIPTOR-CAPACITY"
    ) in code
    assert (
        "_A1D-RUHA-COLLECTION-DESCRIPTOR-CAPACITY\n"
        "    UCSN-DESCRIPTOR-SIZE _A1D-CAPACITY*\n"
        "    2 _A1D-CAPACITY*\n"
        "    CONSTANT _A1D-RUHA-SNAPSHOT-DESCRIPTORS-U"
    ) in code
    assert (
        "APT1-DESK-COLLECTION-NATIVE-CAPACITY 2 _A1D-CAPACITY*\n"
        "    CONSTANT _A1D-RUHA-SNAPSHOT-NATIVE-U"
    ) in code
    assert (
        "APT1-DESK-COLLECTION-NATIVE-CAPACITY\n"
        "    CONSTANT _A1D-RUHA-COLLECTION-VALIDATION-U"
    ) in code
    assert (
        "_A1D-UIDL-RECORDS _A1D-RUHA-COLLECTION-DESCRIPTOR-CAPACITY\n"
        "    UCSN-WORK-BYTES\n"
        "    _A1D-REQUIRE-POSITIVE-CAPACITY\n"
        "    CONSTANT _A1D-RUHA-COLLECTION-WORK-U"
    ) in code
    assert "_A1D-UIDL-RECORDS _A1D-UIDL-RECORDS UCSN-WORK-BYTES" not in code
    assert (
        "_A1D-UIDL-BINDINGS RUHA-DOCUMENT-BYTES _A1D-CAPACITY*\n"
        "    2 _A1D-CAPACITY*"
    ) in code
    assert (
        "APT1-DESK-COLLECTION-NATIVE-CAPACITY\n"
        "    RTHP-COLLECTION-CONTROL-CAPACITY\n"
        "    _A1D-REQUIRE-POSITIVE-CAPACITY\n"
        "    CONSTANT _A1D-RTAPT-SEMANTIC-CONTROLS"
    ) in code
    assert "_A1D-MIN-SEMANTIC-CONTROL-U" not in code
    assert "USCOL-TEXT-FIXED-SIZE /" not in code
    assert (
        "APT1-DESK-COLLECTION-NATIVE-CAPACITY USCOL-ITEM-HEADER-SIZE /\n"
        "    _A1D-REQUIRE-POSITIVE-CAPACITY\n"
        "    CONSTANT _A1D-RTAPT-CONTENT-ITEMS"
    ) in code
    assert (
        "_A1D-UIDL-AGGREGATE-RECORDS _A1D-RTAPT-SEMANTIC-CONTROLS\n"
        "    _A1D-CAPACITY+ CONSTANT _A1D-RTAPT-CONTROL-RECORDS"
    ) in code
    assert (
        "_A1D-SCREEN-CELLS _A1D-RTAPT-CONTROL-RECORDS _A1D-CAPACITY+\n"
        "    _A1D-RTAPT-CONTENT-ITEMS _A1D-CAPACITY+\n"
        "    CONSTANT _A1D-RTAPT-OBJECT-RECORDS"
    ) in code
    assert "1 RTAPT-OWNER-SIZE _A1D-CAPACITY*" in code
    assert (
        "_A1D-SCREEN-CELLS _A1D-RTAPT-CONTROL-RECORDS _A1D-CAPACITY+\n"
        "    1 _A1D-CAPACITY+\n"
        "    CONSTANT _A1D-RTAPT-OP-RECORDS"
    ) in code
    assert "_A1D-SCREEN-CELLS 128 _A1D-CAPACITY*" in code
    assert (
        "_A1D-RTAPT-CONTROL-RECORDS 152 _A1D-CAPACITY*\n"
        "        _A1D-CAPACITY+"
    ) in code
    assert "_A1D-UIDL-AGGREGATE-TEXT-U _A1D-CAPACITY+" in code
    assert "APT1-DESK-COLLECTION-NATIVE-CAPACITY _A1D-CAPACITY+" in code
    assert "72 _A1D-CAPACITY+" in code
    assert (
        "_A1D-UIDL-BINDINGS\n"
        "    _A1D-UIDL-AGGREGATE-RECORDS _A1D-UIDL-AGGREGATE-TEXT-U\n"
        "    APT1-DESK-COLLECTION-NATIVE-CAPACITY\n"
        "    APT1-DESK-MAX-COLS APT1-DESK-MAX-ROWS RTHP-STORAGE-BYTES\n"
        "    _A1D-REQUIRE-HYBRID-ARENA"
    ) in code
    transport_guard = _word(composition, "_A1D-VALIDATE-TRANSPORT-BOUNDS")
    assert "APT1-DESK-RX-CAPACITY" in transport_guard
    assert "APT1-DESK-TX-CAPACITY" in transport_guard
    assert "APT1-DESK-TX-CAPACITY _A1D-MIN-TX-CAPACITY U<" in (
        transport_guard
    )
    assert "transmit capacity below selected frame bound" in transport_guard
    assert "ABORT\"" in transport_guard
    collection_guard = _word(composition, "_A1D-VALIDATE-COLLECTION-BOUND")
    assert "APT1-DESK-COLLECTION-NATIVE-CAPACITY _A1D-U32-POSITIVE?" in (
        collection_guard
    )
    assert "APT1-DESK-COLLECTION-NATIVE-CAPACITY 7 AND" in collection_guard
    assert 'ABORT" desk-apt1: unaligned collection native capacity"' in (
        collection_guard
    )
    arena_guard = _word(composition, "_A1D-REQUIRE-HYBRID-ARENA")
    assert 'DUP 0= ABORT" desk-apt1: invalid hybrid arena capacity"' in arena_guard
    derived_guard = _word(composition, "_A1D-REQUIRE-POSITIVE-CAPACITY")
    assert "DUP _A1D-U32-POSITIVE? 0=" in derived_guard
    assert 'ABORT" desk-apt1: invalid derived capacity"' in derived_guard
    assert code.count("_A1D-REQUIRE-POSITIVE-CAPACITY") == 5
    for stale_interpretation_guard in (
        "DUP 0= ABORT\" desk-apt1: collection native capacity "
        'below one entry"',
        'ABORT" desk-apt1: invalid collection work capacity"',
        "DUP 0= ABORT\" desk-apt1: collection native capacity "
        'below one item"',
    ):
        assert stale_interpretation_guard not in code
    assert (
        "\n_A1D-VALIDATE-COLLECTION-BOUND\n"
        "_A1D-VALIDATE-TRANSPORT-BOUNDS\n"
    ) in code
    assert "RUHA-SIZE 7 + XBUF _A1D-RUHA-MEM" in code
    assert (
        "_A1D-RUHA-COLLECTION-VALIDATION-U _A1D-ALIGNMENT-SLOP+\n"
        "    XBUF _A1D-RUHA-COLLECTION-VALIDATION-MEM"
    ) in code
    assert (
        "_A1D-RUHA-COLLECTION-WORK-U _A1D-ALIGNMENT-SLOP+\n"
        "    XBUF _A1D-RUHA-COLLECTION-WORK-MEM"
    ) in code
    assert "_A1D-RUHA-DIRECTORY-U _A1D-ALIGNMENT-SLOP+" in code
    assert (
        "_A1D-RUHA-SNAPSHOT-DESCRIPTORS-U _A1D-ALIGNMENT-SLOP+\n"
        "    XBUF _A1D-RUHA-SNAPSHOT-DESCRIPTORS-MEM"
    ) in code
    assert (
        "_A1D-RUHA-SNAPSHOT-NATIVE-U _A1D-ALIGNMENT-SLOP+\n"
        "    XBUF _A1D-RUHA-SNAPSHOT-NATIVE-MEM"
    ) in code
    assert "RTHP-SIZE 7 + XBUF _A1D-SCREEN-MEM" in code
    assert "_A1D-SCREEN-ARENA-U _A1D-ALIGNMENT-SLOP+" in code
    assert "_A1D-SCREEN-MEM 7 + -8 AND CONSTANT _A1D-SCREEN" in code
    assert (
        "_A1D-SCREEN-ARENA-MEM 7 + -8 AND CONSTANT _A1D-SCREEN-ARENA"
        in code
    )

    setup = _word(composition, "_A1D-SETUP")
    setup_order = (
        "PT-INIT",
        "APTSCB-INIT",
        "RTAPT-CONFIG-INIT",
        "RTAPT-INIT",
        "RTAPTE-INIT",
        "RTAPTSCB-INIT",
        "RTAPTSCB-ATTACH",
        "RUHA-INIT",
        "RTHP-INIT",
        "RTAPTSCB-OUTPUT-PRODUCER!",
        "RUHA-INSTALL",
        "DESK-HOST-LIFECYCLE!",
        "APTAS-INIT",
        "APTAS-CONTROL-ROUTE!",
        "APTAS-INSTALL",
    )
    assert [setup.index(token) for token in setup_order] == sorted(
        setup.index(token) for token in setup_order
    )
    for identity in (
        "_A1D-SCREEN-OWNER-ID",
        "_A1D-SCREEN-OWNER-GENERATION",
        "_A1D-SCREEN-REGION-ID",
        "_A1D-SCREEN-FIRST-OBJECT-ID",
    ):
        assert f"1 CONSTANT {identity}" in code
    producer_bind = setup[setup.index("RTHP-INIT") :]
    assert (
        "_A1D-RUHA-RECORDS _A1D-RUHA-RECORDS-U\n"
        "    _A1D-RUHA-WORK _A1D-RUHA-WORK-U\n"
        "    _A1D-RUHA-WORK-TEXT _A1D-UIDL-TEXT-U\n"
        "    _A1D-RUHA-COLLECTION-VALIDATION\n"
        "        _A1D-RUHA-COLLECTION-VALIDATION-U\n"
        "    _A1D-RUHA-COLLECTION-WORK _A1D-RUHA-COLLECTION-WORK-U\n"
        "    _A1D-RUHA-DIRECTORY _A1D-RUHA-DIRECTORY-U\n"
        "    _A1D-RUHA-SNAPSHOT-RECORDS _A1D-RUHA-SNAPSHOT-RECORDS-U\n"
        "    _A1D-RUHA-SNAPSHOT-TEXT _A1D-RUHA-SNAPSHOT-TEXT-U\n"
        "    _A1D-RUHA-SNAPSHOT-DESCRIPTORS\n"
        "        _A1D-RUHA-SNAPSHOT-DESCRIPTORS-U\n"
        "    _A1D-RUHA-SNAPSHOT-NATIVE _A1D-RUHA-SNAPSHOT-NATIVE-U\n"
        "    _A1D-RUHA RUHA-INIT"
    ) in setup
    assert (
        "_A1D-UIDL-BINDINGS\n"
        "    _A1D-UIDL-AGGREGATE-RECORDS _A1D-UIDL-AGGREGATE-TEXT-U"
    ) in setup
    assert "['] RTHP-STEP ['] RTHP-PREPARE" in producer_bind
    assert (
        "['] RUHA-HOST-INIT ['] RUHA-HOST-FINI _A1D-RUHA\n"
        "        DESK-HOST-LIFECYCLE!"
    ) in setup
    assert (
        "_A1D-SCREEN ['] RTHP-CONTROL-TARGET@ _A1D-OWNER\n"
        "        APTAS-CONTROL-ROUTE!"
    ) in setup

    clear_inert = _word(composition, "_A1D-CLEAR-INERT")
    for record in (
        "_A1D-SESSION",
        "_A1D-ADAPTER",
        "_A1D-OWNER",
        "_A1D-RTAPT-CONFIG",
        "_A1D-RTAPT-ENGINE",
        "_A1D-RTE-FACADE",
        "_A1D-RTAPTSCB",
        "_A1D-RUHA",
        "_A1D-SCREEN",
    ):
        assert f"{record} " in clear_inert
    assert "_A1D-SCREEN-ARENA" not in clear_inert

    uninstall = _word(composition, "_A1D-UNINSTALL")
    teardown_order = ("APTAS-UNINSTALL", "RTAPTE-FINI", "RTAPT-FINI")
    assert [uninstall.index(token) for token in teardown_order] == sorted(
        uninstall.index(token) for token in teardown_order
    )
    run_body = _word(composition, "_A1D-RUN-BODY")
    assert run_body.index("_A1D-SETUP") < run_body.index("DESK-RUN")
    assert "DESK-HOST-LIFECYCLE!" not in run_body
    public_run = _word(composition, "APT1-DESK-RUN")
    assert "['] _A1D-RUN-BODY CATCH _A1D-RUN-IOR !" in public_run
    assert public_run.index("CATCH") < public_run.index(
        "0 0 0 DESK-HOST-LIFECYCLE!"
    ) < public_run.index("_A1D-CAPTURE-FAILURE")
    assert public_run.index("_A1D-CAPTURE-FAILURE") < public_run.index(
        "_A1D-UNINSTALL"
    )
    assert public_run.index("CATCH") < public_run.index("_A1D-UNINSTALL")

    failure_capture = _word(composition, "_A1D-CAPTURE-FAILURE")
    for live, snapshot, size in (
        ("_A1D-RTAPTSCB", "_A1D-FAILURE-PUBLISHER", "RTAPTSCB-SIZE"),
        ("_A1D-SCREEN", "_A1D-FAILURE-SCREEN", "RTHP-SIZE"),
        (
            "_A1D-RTAPT-ENGINE",
            "_A1D-FAILURE-ENGINE",
            "RTAPT-ENGINE-SIZE",
        ),
    ):
        assert f"{live} {snapshot} {size} MOVE" in failure_capture

    lowered = code.lower()
    for forbidden in ("pad-entry", "daybook-entry", "sha3"):
        assert forbidden not in lowered


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
    ) < quiesce.index("UTUI-QUIESCE")
    uidl_at = quiesce.index("UTUI-QUIESCE")
    save_at = quiesce.index("_AHQS-SLOT @ AHS-CTX-SAVE")
    init_at = quiesce.index("AHS.INIT-STARTED @ IF")
    activate_at = quiesce.index("_AHQS-SLOT @ AHS-ACTIVATE")
    app_at = quiesce.index("APP.QUIESCE-XT @")
    assert uidl_at < save_at < init_at < app_at < activate_at
    assert "SWAP EXECUTE ?DUP IF THROW THEN" in quiesce[app_at:]
    assert "AHS-CLOSE-S-QUIESCED _AHQS-SLOT @ AHS.CLOSE-PHASE !" not in quiesce

    publish = _word(host, "_AHQS-PUBLISH")
    assert publish.index("_AHQS-IOR @ IF EXIT THEN") < publish.index(
        "AHS-CLOSE-PHASE-VALID?"
    ) < publish.index("AHS-CLOSE-S-QUIESCING = IF") < publish.index(
        "AHS-CLOSE-S-QUIESCED _AHQS-SLOT @ AHS.CLOSE-PHASE !"
    )
    quiesce_slot = _word(host, "_AHOST-QUIESCE-SLOT")
    assert quiesce_slot.index("['] _AHQS-BODY CATCH") < quiesce_slot.index(
        "['] _AHQS-SAVE CATCH"
    ) < quiesce_slot.index("_AHQS-PUBLISH")

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
    shutdown_guard_at = force.index("AHS-CLOSE-S-QUIESCED = IF")
    shutdown_call_at = force.index("['] _AHC-SHUTDOWN CATCH")
    detach_guard_at = force.index("AHS-CLOSE-S-SHUTDOWN-CLAIMED = IF")
    detach_call_at = force.index("['] _AHC-DETACH CATCH")
    assert shutdown_guard_at < shutdown_call_at < detach_guard_at < detach_call_at
    exit_at = force.index("['] _AHC-EXIT CATCH DUP _AHC-REMEMBER IF")
    phase_gate_at = force.index("AHS-CLOSE-S-DETACHED <> IF")
    assert detach_call_at < exit_at < phase_gate_at
    exit_refusal = force[exit_at:phase_gate_at]
    assert "0 _AHC-IOR @" in exit_refusal
    assert "EXIT" in exit_refusal
    assert "ASHELL-CTX-FORGET" not in force
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
    request_slot = _word(host, "_AHOST-REQUEST-CLOSE-SLOT")
    assert "['] _AHQ-EXIT CATCH IF" in request_slot
    request_exit = request_slot[request_slot.index("['] _AHQ-EXIT CATCH IF") :]
    assert "APP-CLOSE-D-CANCEL _AHQ-DECISION !" in request_exit
    assert "ASHELL-CTX-FORGET" not in request_slot
    close_all_exit = close_all[close_all.index("['] _AHQ-EXIT CATCH IF") :]
    assert "APP-CLOSE-D-CANCEL _AHALL-DECISION !" in close_all_exit
    assert "ASHELL-CTX-FORGET" not in close_all


def test_app_quiesce_is_a_public_pre_shutdown_descriptor_phase() -> None:
    desc = _text("akashic/tui/app-desc.f")
    shell = _text("akashic/tui/app-shell.f")
    game = _text("akashic/tui/game/game-applet.f")

    assert "160 CONSTANT _AD-QUIESCE" in desc
    assert "168 CONSTANT APP-DESC" in desc
    assert ": APP.QUIESCE-XT" in desc
    assert "DUP APP-DESC 0 FILL" in _word(desc, "APP-DESC-INIT")
    assert "APP.SIZE @ APP-DESC >=" in _word(desc, "APP-DESC-VALID?")

    setup = shell[
        shell.index(": _ASHELL-SETUP") : shell.index(
            "\\  §11 — Lifecycle: Shutdown"
        )
    ]
    init_at = setup.index("TRUE _ASHELL-APP-INIT-STARTED !")
    assert setup.index("_ASHELL-ACTIVATE") < init_at < setup.index("APP.INIT-XT @")

    quiesce = _word(shell, "_ASHELL-TD-QUIESCE")
    uidl_at = quiesce.index("UTUI-QUIESCE")
    init_guard_at = quiesce.index("_ASHELL-APP-INIT-STARTED @ 0=")
    repeat_guard_at = quiesce.index("_ASHELL-APP-QUIESCED @ IF EXIT THEN")
    activate_at = quiesce.index("_ASHELL-ACTIVATE")
    callback_at = quiesce.index("APP.QUIESCE-XT @")
    success_at = quiesce.index("TRUE _ASHELL-APP-QUIESCED !", callback_at)
    assert quiesce.index("_ASHELL-HAS-UIDL @ IF") < uidl_at < quiesce.index(
        "THEN", uidl_at
    ) < init_guard_at
    assert uidl_at < init_guard_at < repeat_guard_at < callback_at < activate_at
    assert callback_at < success_at
    shutdown = _word(shell, "_ASHELL-TD-APP")
    shutdown_init_at = shutdown.index("_ASHELL-APP-INIT-STARTED @ 0=")
    shutdown_repeat_at = shutdown.index(
        "_ASHELL-APP-SHUTDOWN-CLAIMED @ IF EXIT THEN"
    )
    shutdown_claim_at = shutdown.index("TRUE _ASHELL-APP-SHUTDOWN-CLAIMED !")
    shutdown_callback_at = shutdown.index("APP.SHUTDOWN-XT @")
    assert (
        shutdown_init_at
        < shutdown_repeat_at
        < shutdown_claim_at
        < shutdown_callback_at
    )

    # Game descriptors extend the complete current ABI instead of aliasing a
    # newly appended standard lifecycle cell.
    assert "APP-DESC      CONSTANT _GAPP-O-USER-INIT" in game
    assert "APP-DESC 48 + CONSTANT _GAPP-O-GV" in game
    assert "APP-DESC 56 + CONSTANT _GAPP-DESC-SZ" in game
    assert "160 CONSTANT _GAPP-O-GV" not in game


def test_app_shell_dependent_failures_quarantine_before_the_next_stage() -> None:
    shell = _text("akashic/tui/app-shell.f")
    shell_doc = _text("docs/tui/app-shell.md")
    rich_contract = _text("docs/rich-terminal/AKASHIC-RICH-TERMINAL.md")
    teardown = _word(shell, "_ASHELL-TEARDOWN")

    quiesce_call = "['] _ASHELL-TD-QUIESCE CATCH _ASHELL-TD-REMEMBER"
    close_call = "['] _ASHELL-TD-TERM-CLOSE CATCH _ASHELL-TD-REMEMBER"
    shutdown_call = "['] _ASHELL-TD-APP      CATCH _ASHELL-TD-REMEMBER"
    uidl_call = "['] _ASHELL-TD-UIDL     CATCH _ASHELL-TD-REMEMBER"
    ordered = (
        quiesce_call,
        close_call,
        shutdown_call,
        uidl_call,
        "['] _ASHELL-TD-REGION   CATCH",
        "['] _ASHELL-TD-INST     CATCH",
    )
    assert [teardown.index(token) for token in ordered] == sorted(
        teardown.index(token) for token in ordered
    )

    dependent_calls = (quiesce_call, close_call, shutdown_call, uidl_call)
    next_calls = (
        close_call,
        shutdown_call,
        uidl_call,
        "['] _ASHELL-TD-UIDL-BUF CATCH",
    )
    for call, next_call in zip(dependent_calls, next_calls):
        refusal = teardown[teardown.index(call) : teardown.index(next_call)]
        assert "_ASHELL-TD-IOR @ IF" in refusal
        assert "_ASHELL-TD-QUARANTINE _ASHELL-TD-IOR @ EXIT" in refusal

    quarantine = _word(shell, "_ASHELL-TD-QUARANTINE")
    assert "_ASHELL-INST @ _ASHELL-QUARANTINED-INST !" in quarantine
    for cleared in (
        "_ASHELL-DESC !",
        "_ASHELL-INST !",
        "_ASHELL-RGN !",
        "_ASHELL-HAS-UIDL !",
        "_ASHELL-UIDL-BUF !",
        "_ASHELL-ACTIVE-CTX !",
        "_ASHELL-APP-INIT-STARTED !",
        "_ASHELL-APP-QUIESCED !",
        "_ASHELL-APP-SHUTDOWN-CLAIMED !",
        "_ASHELL-TERM-OWNER !",
        "_ASHELL-TERM-OWNS !",
        "_ASHELL-TERM-STARTED !",
        "_ASHELL-TERM-ANSI-SAFE !",
        "_ASHELL-POST-HEAD !",
        "_ASHELL-POST-TAIL !",
        "_ASHELL-OUTPUT-PENDING !",
    ):
        assert cleared not in quarantine

    uidl = _word(shell, "_ASHELL-TD-UIDL")
    assert uidl.index("UTUI-DETACH") < uidl.index("0 _ASHELL-HAS-UIDL !")
    for gated_word in ("ASHELL-TERMINAL!", "ASHELL-TERMINAL-RELEASE-CHECK"):
        assert "ASHELL-TERMINAL-QUARANTINED? OR" in _word(shell, gated_word)
    preflight = _word(shell, "_ASHELL-TERM-PREFLIGHT")
    assert "ASHELL-TERMINAL-QUARANTINED? IF" in preflight
    setup = shell[
        shell.index(": _ASHELL-SETUP") : shell.index(
            "\\  §11 — Lifecycle: Shutdown"
        )
    ]
    assert setup.index("_ASHELL-TERM-PREFLIGHT") < setup.index(
        "FALSE _ASHELL-APP-INIT-STARTED !"
    )
    assert "_ASHELL-TD-IOR @ _ASHELL-QUARANTINE-IOR !" in quarantine
    assert teardown.index("ASHELL-TERMINAL-QUARANTINED? IF") < teardown.index(
        quiesce_call
    )
    assert shell.count("0 _ASHELL-QUARANTINED-INST !") == 1

    normalized_shell_doc = " ".join(shell_doc.split())
    normalized_contract = " ".join(rich_contract.split())
    assert "projection-provider soft reset" in normalized_shell_doc
    assert "APT soft reset" not in normalized_shell_doc
    assert "APT soft reset" in normalized_contract
    for prose in (normalized_shell_doc, normalized_contract):
        assert (
            "attachment hard-reset/drain" in prose
            or "attachment hard reset/drain" in prose
        )
        assert "fresh module or image initialization" in prose
        assert "terminal-owner release" in prose
        assert "clear API" in prose
    assert "in-process shell retry" in normalized_shell_doc
    assert "`ASHELL-RUN` retry" in normalized_contract
    assert "always restores" not in shell.lower()
    assert "all state is reset to defaults" not in shell_doc.lower()


def test_desk_quiesce_and_layout_preserve_retiring_slot_authority() -> None:
    desk = _text("akashic/tui/applets/desk/desk.f")

    assert "DUP _SL-CALLABLE? SWAP _SL-VISIBLE? AND" in _word(
        desk, "_SL-LAYOUT?"
    )
    assert "DUP _SL-LAYOUT? IF" in _word(desk, "_DESK-COLLECT-VISIBLE")

    hidden = _word(desk, "_DESK-SYNC-HIDDEN")
    assert hidden.index("_SL-CALLABLE?") < hidden.index(
        "_DESK-CTX-SWITCH"
    ) < hidden.index("FALSE UTUI-VISIBLE!") < hidden.index(
        "_DESK-CTX-SAVE"
    )
    assert "FALSE UTUI-VISIBLE! DROP" not in hidden
    assign = _word(desk, "_DESK-ASSIGN-TILE")
    region_at = assign.index("_SL-RGN @ ?DUP IF")
    bounds_at = assign.index("RGN-BOUNDS!", region_at)
    else_at = assign.index("ELSE", bounds_at)
    assert region_at < bounds_at < else_at < assign.index("RGN-NEW", else_at)
    assert "RGN-FREE" not in assign

    fullframe = _word(desk, "_DESK-EXPAND-FULLFRAME")
    assert fullframe.index("_DESK-FULLFRAME-ACTIVE? 0=") < fullframe.index(
        "_SL-RGN @"
    ) < fullframe.index("RGN-BOUNDS!")
    assert "RGN-FREE" not in fullframe
    assert "RGN-NEW" not in fullframe
    assert "_DESK-FREE-REGIONS" not in desk

    relayout = _word(desk, "DESK-RELAYOUT")
    ordered = (
        "_DESK-SYNC-HIDDEN",
        "_DESK-COLLECT-VISIBLE",
        "_DESK-ASSIGN-TILE",
        "_DESK-EXPAND-FULLFRAME",
        "UTUI-RGN!",
        "UTUI-RELAYOUT",
        "TRUE UTUI-VISIBLE!",
        "_DESK-CTX-SAVE",
    )
    assert [relayout.index(token) for token in ordered] == sorted(
        relayout.index(token) for token in ordered
    )
    assert "TRUE UTUI-VISIBLE! DROP" not in relayout

    effective = _word(desk, "_DESK-FULLFRAME-ACTIVE?")
    assert "_DESK-FOCUS-SA @ ?DUP IF _SL-LAYOUT?" in effective
    assert _word(desk, "DESK-PAINT-CB").count("_DESK-FULLFRAME-ACTIVE?") == 2

    quiesce = _word(desk, "DESK-QUIESCE-CB")
    assert "_DESK-USE-STATE" in quiesce
    assert "_DESK-HOST AHOST-QUIESCE-ALL" in quiesce
    for forbidden in ("APT", "RTERM", "TERMINAL", "PT-"):
        assert forbidden not in quiesce
    fill = _word(desk, "_DESK-FILL-DESC")
    assert "['] DESK-QUIESCE-CB  DESK-DESC APP.QUIESCE-XT !" in fill
    shutdown = _word(desk, "DESK-SHUTDOWN-CB")
    assert shutdown.index("AHOST-DRAIN ?DUP IF THROW THEN") < shutdown.index(
        "_DSD-INTEROP-FINI"
    ) < shutdown.index("_DSD-PRACTICE-FINI")


def test_region_identity_is_stable_across_shell_and_desk_relayout() -> None:
    region = _text("akashic/tui/region.f")
    shell = _text("akashic/tui/app-shell.f")

    bounds = _word(region, "RGN-BOUNDS!")
    for field in ("_RGN-O-ROW", "_RGN-O-COL", "_RGN-O-H", "_RGN-O-W"):
        assert field in bounds
    assert "_RGN-O-PARENT" not in bounds
    assert "_RGNB-RGN @ _RGN-ACTIVE-DEPENDS? IF" in bounds
    assert "_RGN-CUR @ _RGN-ACTIVATE" in bounds
    assert "RGN-FREE" not in bounds
    assert "ALLOCATE" not in bounds

    resize = _word(shell, "_ASHELL-ON-RESIZE")
    assert resize.index("RGN-BOUNDS!") < resize.index("UTUI-RELAYOUT")
    assert "RGN-FREE" not in resize


def test_retained_contract_requires_internal_uidl_projection_now() -> None:
    contract = _text("docs/rich-terminal/AKASHIC-RICH-TERMINAL.md")
    candidate = _text(
        "docs/rich-terminal/UIDL-PROJECTION-CANDIDATE.md"
    )
    normalized_contract = " ".join(contract.split())
    normalized_candidate = " ".join(candidate.split())
    cell_contract = _text("docs/rich-terminal/AKASHIC-CELL-BACKEND.md")
    ownership = _text(
        "docs/rich-terminal/APT-1-RETAINED-1-OWNERSHIP.md"
    )

    assert "UIDL is the sole application-facing UI description" in contract
    assert "There is therefore no rich-terminal service identifier" in contract
    assert "UIDL/UCTX integration is Phase 3, not deferred work" in contract
    assert "one aggregate screen owner" in contract
    assert "UTUI-QUIESCE" in contract
    assert "generic, consumer-neutral Akashic" in contract
    assert "may compose the same engine without" in normalized_contract
    assert "never source-`REQUIRE`s or copies" in contract
    assert "The selected Desk/Pad/Daybook contractual checkpoint is closed" in (
        normalized_contract
    )
    assert "Desk, Pad, and Daybook acceptance checkpoint" in contract
    assert "normal TUI draw lifecycle" in contract
    assert "came only from CELL does not qualify the rich path" in normalized_contract
    assert "semantic UIDL menus plus residual `GLYPH_RUN` coverage" in normalized_contract
    assert "draw-keyed aggregate projection of every visible attached UCTX" in normalized_contract
    assert "compatible later draws use `RET_DELTA`" in normalized_contract
    assert "historical qualification record" in normalized_contract
    assert "Recorded display-backed qualification" in normalized_contract
    assert "Daybook-to-Pad shared-resource handoff" in normalized_contract
    assert "Slow-refresh and e-paper endpoints" in contract
    assert (
        "A full-screen one-object-per-cell frame is specifically forbidden "
        "as product proof"
        in normalized_contract
    )
    assert "residual glyph spans only for visible" in normalized_contract
    assert "one final mutation-safety validation" in normalized_contract
    assert "must not be revived or installed as parallel product paths" in normalized_contract
    assert "genuine control semantics" in normalized_candidate
    assert (
        "The residual encoder must not emit the claimed cells"
        in normalized_candidate
    )
    assert (
        "maximal contiguous sequence of unclaimed cells"
        in normalized_candidate
    )
    assert "worst-case storage does not make per-cell topology the policy" in normalized_candidate
    assert "Exact preflight admits only the candidate actually constructed" in normalized_candidate
    assert (
        "This is `O(new-items + old-items + source-high-water)`"
        in normalized_candidate
    )
    assert "only allowed repeated full traversal" in normalized_candidate
    assert "visible-UCTX aggregate adapter" in normalized_candidate
    assert (
        "`desk-apt1.f` no longer composes the per-cell producer"
        in normalized_candidate
    )
    assert "First visible root-LABEL checkpoint" not in contract
    assert "before arbitrary `APP.SHUTDOWN`" in contract
    assert "Applications receive no" in ownership
    assert "private per-UCTX projection" in ownership
    assert "neutral aggregate screen producer" in cell_contract
    assert "`TOUCHED`" in cell_contract
    assert "`DAMAGE`" in cell_contract
    assert "PRESENT_BEGIN" in cell_contract
    assert "Phase 3 uses a handwritten SoundLab projection" not in contract
    assert "First production consumer: SoundLab" not in contract


def _assert_phase_marked(body: str, phase: str, call: str) -> None:
    marker = re.compile(r"(_RTPROF-PH-[A-Z0-9-]+)\s+_RTPROF-MARK")
    call_at = body.index(call)
    before = [match for match in marker.finditer(body) if match.start() < call_at]
    after = [match for match in marker.finditer(body) if match.start() > call_at]
    assert before and before[-1].group(1) == phase
    assert after and after[0].group(1) == "_RTPROF-PH-OTHER"


def _assert_phase_exits_are_neutral(body: str) -> None:
    marker = re.compile(r"(_RTPROF-PH-[A-Z0-9-]+)\s+_RTPROF-MARK")
    for exit_match in re.finditer(r"\bEXIT\b", body):
        phases = marker.findall(body[: exit_match.start()])
        assert phases
        assert phases[-1] == "_RTPROF-PH-OTHER"


def test_rich_phase_profile_has_one_atomic_event_and_stable_ids() -> None:
    source = _text("akashic/tui/rich-terminal/phase-profile.f")
    expected = (
        (0, "OTHER"),
        (1, "UIDL-AGGREGATE"),
        (2, "SNAPSHOT-IMPORT"),
        (3, "CONTROL-PLAN"),
        (4, "CLAIM-PLAN"),
        (5, "RESIDUAL-PLAN"),
        (6, "RESERVE-WRAP"),
        (7, "HYBRID-PREFLIGHT"),
        (8, "CANDIDATE-VALIDATE"),
        (9, "TARGET-PACK"),
        (10, "DELTA-COMPARE-NORMALIZE"),
        (11, "RTAPT-CAPTURE"),
        (12, "COMMIT-PRECHECK"),
        (13, "RTAPT-AUDIT"),
        (14, "WIRE-ENCODE"),
    )

    assert "PROVIDED akashic-tui-rterm-phase-profile" in source
    assert re.findall(r"(?m)^VARIABLE\s+(\S+)", source) == [
        "_RTPROF-EVENT",
        "_RTPROF-SEQUENCE",
    ]
    assert "0x00FFFFFFFFFFFFFF CONSTANT _RTPROF-SEQUENCE-MASK" in source
    for phase_id, name in expected:
        assert re.search(
            rf"(?m)^\s*{phase_id}\s+CONSTANT\s+_RTPROF-PH-{name}\s*$",
            source,
        )

    mark = _word(source, "_RTPROF-MARK")
    assert "( phase -- )" in mark
    assert "DUP _RTPROF-EVENT @ 0xFF AND = IF DROP EXIT THEN" in mark
    assert "_RTPROF-SEQUENCE @ 1+ _RTPROF-SEQUENCE-MASK AND" in mark
    assert "DUP _RTPROF-SEQUENCE !" in mark
    assert "8 LSHIFT OR" in mark
    assert mark.count("_RTPROF-EVENT !") == 1
    assert mark.rstrip().endswith("_RTPROF-EVENT ! ;")
    assert not {">R", "R@", "R>"} & set(mark.split())


def test_rich_phase_profile_is_private_and_brackets_generic_work() -> None:
    producer = _text("akashic/tui/rich-terminal/hybrid-screen-producer.f")
    engine = _text("akashic/tui/rich-terminal/apt1-engine.f")
    profile = _text("akashic/tui/rich-terminal/phase-profile.f")
    assert "REQUIRE phase-profile.f" in producer
    assert "REQUIRE phase-profile.f" in engine
    assert not re.search(r"(?<![A-Z0-9_])PT-", profile)
    assert not re.search(r"(?<![A-Z0-9_])RTE-", profile)

    users = {
        path.relative_to(AKASHIC).as_posix()
        for path in (AKASHIC / "tui").rglob("*.f")
        if "_RTPROF-" in path.read_text(encoding="utf-8")
    }
    assert users == {
        "tui/rich-terminal/phase-profile.f",
        "tui/rich-terminal/hybrid-screen-producer.f",
        "tui/rich-terminal/apt1-engine.f",
    }
    assert "_RTPROF-EVENT" not in producer + engine

    build = _word(producer, "_RTHP-BUILD-CANDIDATE")
    for phase, call in (
        ("_RTPROF-PH-UIDL-AGGREGATE", "RUHA-SNAPSHOT-FOR@"),
        ("_RTPROF-PH-SNAPSHOT-IMPORT", "RTE-LIMITS@"),
        ("_RTPROF-PH-SNAPSHOT-IMPORT", "_RTHP-COPY-SNAPSHOT?"),
        ("_RTPROF-PH-SNAPSHOT-IMPORT", "_RTHP-SELECT-NEXT-IDS?"),
        ("_RTPROF-PH-CONTROL-PLAN", "_RTHP-BUILD-CONTROLS"),
        ("_RTPROF-PH-CLAIM-PLAN", "_RTHP-BUILD-CLAIMS?"),
        ("_RTPROF-PH-RESIDUAL-PLAN", "_RTHP-BUILD-GLYPHS?"),
        ("_RTPROF-PH-RESERVE-WRAP", "_RTHP-RESERVE-GLYPHS?"),
    ):
        _assert_phase_marked(build, phase, call)

    hybrid_preflight = _word(producer, "_RTHP-W-PREFLIGHT-HYBRID")
    _assert_phase_marked(
        hybrid_preflight,
        "_RTPROF-PH-HYBRID-PREFLIGHT",
        "RTE-HYBRID-PREFLIGHT",
    )

    start = _word(producer, "_RTHP-PREPARE-START")
    staged = _word(producer, "_RTHP-STAGE-LIVE-CANDIDATE")
    delta = _word(producer, "_RTHP-PREPARE-DELTA")
    reveal = _word(producer, "_RTHP-PREPARE-REVEAL")
    live = _word(producer, "_RTHP-PREPARE-LIVE")
    for body in (start, staged):
        _assert_phase_marked(
            body, "_RTPROF-PH-CANDIDATE-VALIDATE", "_RTHP-FIXED?"
        )
        _assert_phase_marked(
            body, "_RTPROF-PH-TARGET-PACK", "_RTHP-TARGET-CANDIDATE?"
        )
    _assert_phase_marked(
        live,
        "_RTPROF-PH-DELTA-COMPARE-NORMALIZE",
        "_RTHP-DELTA-CANDIDATE?",
    )
    for body in (start, delta, reveal):
        capture = body.index("_RTPROF-PH-RTAPT-CAPTURE _RTPROF-MARK")
        begin = body.index("RTE-RETAINED-BEGIN", capture)
        seal = body.index("RTE-RETAINED-SEAL", begin)
        neutral = body.index("_RTPROF-PH-OTHER _RTPROF-MARK", seal)
        assert capture < begin < seal < neutral
    for body in (build, hybrid_preflight, start, staged, delta, reveal, live):
        _assert_phase_exits_are_neutral(body)

    for entrypoint, first_private in (
        ("RTHP-STEP", "_RTHP-S-P"),
        ("RTHP-PREPARE", "_RTHP-P-P"),
    ):
        body = _word(producer, entrypoint)
        assert body.index("_RTPROF-PH-OTHER _RTPROF-MARK") < body.index(
            first_private
        )


def test_rich_phase_wire_excludes_cell_and_ack_wait() -> None:
    engine = _text("akashic/tui/rich-terminal/apt1-engine.f")
    commit = _word(engine, "RTAPT-CELL-COMMIT")
    _assert_phase_marked(
        commit, "_RTPROF-PH-COMMIT-PRECHECK", "_RTAPT-COMMIT-READY?"
    )
    _assert_phase_marked(
        commit, "_RTPROF-PH-RTAPT-AUDIT", "_RTAPT-PUBLICATION-AUDIT?"
    )
    rich_gate = commit.index("_RTAPT-E.RET-MODE @ PT-RET-NONE <> IF")
    wire = commit.index("_RTPROF-PH-WIRE-ENCODE _RTPROF-MARK")
    present = commit.index("PT-PRESENT-COMMIT", wire)
    neutral = commit.index("_RTPROF-PH-OTHER _RTPROF-MARK", present)
    awaiting = commit.index("RTAPT-UPDATE-AWAITING", neutral)
    assert rich_gate < wire < present < neutral < awaiting
    assert commit.count("_RTPROF-PH-WIRE-ENCODE _RTPROF-MARK") == 1
    _assert_phase_exits_are_neutral(commit)
