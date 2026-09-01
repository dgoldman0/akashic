"""Seconds-only structural locks for neutral UIDL-TUI resolved projection state."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
UIDL_TUI = ROOT / "akashic" / "tui" / "uidl-tui.f"
CELL = ROOT / "akashic" / "tui" / "cell.f"
DRAW = ROOT / "akashic" / "tui" / "draw.f"
REGION = ROOT / "akashic" / "tui" / "region.f"
APP_SHELL = ROOT / "akashic" / "tui" / "app-shell.f"


def _definitions(source: str) -> list[tuple[str, str]]:
    return [
        (match.group(1), match.group(0))
        for match in re.finditer(
            r"(?ms)^:\s+(\S+)(?=\s).*?;\s*(?:\\[^\n]*)?$",
            source,
        )
    ]


def _definition(source: str, name: str) -> str:
    matches = [body for word, body in _definitions(source) if word == name]
    assert matches, f"missing Forth definition {name}"
    return matches[0]


def _last_definition(source: str, name: str) -> str:
    matches = [body for word, body in _definitions(source) if word == name]
    assert matches, f"missing Forth definition {name}"
    return matches[-1]


def test_public_abi_is_fixed_explicit_and_renderer_neutral() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")

    assert "0 CONSTANT UTUI-RESOLVED-S-OK" in source
    assert "1 CONSTANT UTUI-RESOLVED-S-UNAVAILABLE" in source
    assert "2 CONSTANT UTUI-RESOLVED-S-INVALID" in source
    assert "72 CONSTANT UTUI-RESOLVED-SIZE" in source

    signatures = {
        "UTUI-RESOLVED-BYTES": "( -- bytes )",
        "UTUI-RESOLVED-STATUS-VALID?": "( status -- flag )",
        "UTUI-ELEM-RESOLVED-STATE@": (
            "( elem -- effective-visible status )"
        ),
        "UTUI-ELEM-RESOLVED-CAPTURE": (
            "( elem destination available -- effective-visible status )"
        ),
        "UTUI-RESOLVED-VALID?": "( record available -- flag )",
        "UTUI-RESOLVED-OBSERVE": "( i*x xt -- j*x )",
        "UTUI-STORAGE-DISJOINT?": "( address length -- flag )",
        "UTUI-VISITED-COLLECTION-CAPTURE": (
            "( root-key destination capacity builder elem -- bytes status )"
        ),
        "UTUI-VISITED-COLLECTION-STORAGE-DISJOINT?": (
            "( address bytes elem -- disjoint status )"
        ),
        "UTUI-COLLECTION-STORAGE-DISJOINT?": (
            "( address bytes -- disjoint status )"
        ),
    }
    for name, signature in signatures.items():
        # Long stack comments may intentionally live on the continuation line.
        assert signature in _definition(source, name)

    offsets = {
        "ROW": 0,
        "COL": 8,
        "H": 16,
        "W": 24,
        "FG": 32,
        "BG": 40,
        "ATTRS": 48,
        "ALIGN": 56,
        "Z": 64,
    }
    for field, offset in offsets.items():
        accessor = _definition(source, f"_UTUI-RS.{field}")
        if offset:
            assert f"{offset} +" in accessor
        else:
            assert "+" not in accessor.split("--", 1)[-1]

    assert "UTUI-RESOLVED-SIZE" in _definition(
        source, "UTUI-RESOLVED-BYTES"
    )
    assert "3 U<" in _definition(source, "UTUI-RESOLVED-STATUS-VALID?")

    # The copied ABI deliberately has no field for the TSC, packed style,
    # widget pointer, visibility, or a provider-specific object identity.
    assert not re.search(
        r"(?m)^:\s+_UTUI-RS\."
        r"(?:TSC|SIDECAR|STYLE|WPTR|FLAGS|VISIBLE|OBJECT)(?=\s)",
        source,
    )


def test_resolve_decodes_sidecar_state_into_explicit_scalar_fields() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")
    resolve = _definition(source, "_UTUI-RS-RESOLVE")

    raw_geometry = (
        "_UTUI-RS-SC @ _UTUI-SC-ROW@ _UTUI-RS-ROW !",
        "_UTUI-RS-SC @ _UTUI-SC-COL@ _UTUI-RS-COL !",
        "_UTUI-RS-SC @ _UTUI-SC-H@ _UTUI-RS-H !",
        "_UTUI-RS-SC @ _UTUI-SC-W@ _UTUI-RS-W !",
    )
    for extraction in raw_geometry:
        assert extraction in resolve

    style_at = resolve.index("_UTUI-SC-STYLE@")
    decoded = (
        "TSC-UNPACK-FG _UTUI-RS-FG !",
        "TSC-UNPACK-BG _UTUI-RS-BG !",
        "TSC-UNPACK-ATTRS _UTUI-RS-ATTRS !",
    )
    assert all(resolve.index(token) > style_at for token in decoded)
    assert "_UTUI-SC-TALIGN@ _UTUI-RS-ALIGN !" in resolve

    # Z is deliberately not copied from the target packed style.  Resolution
    # starts at zero and the ancestor walk assigns the outermost deferred
    # overlay/dialog layer that actually controls paint order.
    assert "0 _UTUI-RS-Z !" in resolve
    assert "TSC-UNPACK-ZIDX _UTUI-RS-Z !" not in resolve
    assert "_UTUI-SC-ZIDX@" in resolve
    assert resolve.index("_UTUI-RS-TARGET-VALID?") > max(
        resolve.index(token) for token in decoded
    )

    writer = _definition(source, "_UTUI-RS-WRITE")
    for field in ("ROW", "COL", "H", "W", "FG", "BG", "ATTRS", "ALIGN", "Z"):
        assert (
            f"_UTUI-RS-{field} @ _UTUI-RS-DST @ _UTUI-RS.{field} !"
            in writer
        )
    assert writer.count("_UTUI-RS.") == 9
    for forbidden in ("TSC-", "_UTUI-SIDECAR", "_UTUI-RS-STYLE", "CMOVE"):
        assert forbidden not in writer


def test_record_validation_rejects_glyph_attrs_and_impossible_values() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")
    cell = CELL.read_text(encoding="utf-8")
    validator = _definition(source, "_UTUI-RESOLVED-VALID-BODY?")
    target = _definition(source, "_UTUI-RS-TARGET-VALID?")

    assert "127 CONSTANT _UTUI-RS-ATTR-MASK" in source
    assert re.search(r"(?m)^128\s+CONSTANT CELL-A-WIDE\b", cell)
    assert re.search(r"(?m)^256\s+CONSTANT CELL-A-CONT\b", cell)
    for body in (validator, target):
        assert "_UTUI-RS-ATTRS-VALID?" in body
        assert "255 U>" in body
        assert "2 U>" in body

    attrs = _definition(source, "_UTUI-RS-ATTRS-VALID?")
    assert "65535 U>" in attrs
    assert "CELL-A-WIDE CELL-A-CONT OR AND 0=" in attrs
    assert "_UTUI-RS-ATTR-MASK INVERT AND 0=" in attrs

    # Geometry may be zero-area or offscreen, but negative lengths and signed
    # endpoint overflow are invalid. Visibility handles the zero intersection.
    axis = _definition(source, "_UTUI-RS-AXIS-END?")
    assert "DUP 0< IF" in axis
    assert "_UTUI-RS-SIGNED-MAX" in axis
    assert "DUP 0= IF" not in axis
    assert target.count("_UTUI-RS-AXIS-END?") == 2
    assert validator.count("_UTUI-RS-AXIS-END?") == 2
    assert "TSC-UNPACK-POS 2 U>" in target
    assert "52 RSHIFT" in target


def test_status_boundary_is_caught_and_all_resolve_scratch_is_scrubbed() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")
    resolve = _definition(source, "_UTUI-RS-RESOLVE")
    call = _definition(source, "_UTUI-RS-CALL")
    result = _definition(source, "_UTUI-RS-RESULT")
    state = _definition(source, "UTUI-ELEM-RESOLVED-STATE@")

    assert "_UTUI-DOC-LOADED @ 0=" in resolve
    assert "UIDL-ELEM-INDEX? 0=" in resolve
    assert "_UTUI-SCF-HAS AND 0=" in resolve
    assert "UTUI-RESOLVED-S-UNAVAILABLE EXIT" in resolve
    assert "_UTUI-RS-TARGET-VALID? 0=" in resolve

    assert "['] _UTUI-RS-RESOLVE-CALL CATCH" in call
    assert "UTUI-RESOLVED-S-INVALID" in call
    assert "DUP UTUI-RESOLVED-S-OK =" in result
    assert "_UTUI-RS-CLEAR" in result
    assert "_UTUI-RS-CALL _UTUI-RS-RESULT" in state

    validator = _definition(source, "UTUI-RESOLVED-VALID?")
    capture = _definition(source, "UTUI-ELEM-RESOLVED-CAPTURE")
    disjoint = _definition(source, "UTUI-STORAGE-DISJOINT?")
    assert "['] _UTUI-RESOLVED-VALID-BODY? CATCH" in validator
    assert "['] _UTUI-ELEM-RESOLVED-CAPTURE-BODY CATCH" in capture
    assert "['] _UTUI-STORAGE-DISJOINT-BODY? CATCH" in disjoint
    assert "_UTUI-RS-CLEAR" in capture
    assert "UTUI-RESOLVED-S-INVALID" in capture

    scratch = set(re.findall(r"(?m)^VARIABLE\s+(_UTUI-RS-[^\s]+)", source))
    cleared = _definition(source, "_UTUI-RS-TARGET-CLEAR") + _definition(
        source, "_UTUI-RS-CLEAR"
    )
    assert scratch
    for variable in scratch:
        assert re.search(rf"(?<!\S)0\s+{re.escape(variable)}\s+!", cleared)


def test_tree_observer_lends_an_aligned_resolved_record() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")

    raw = (
        "CREATE _UTUI-RST-RESOLVED-MEM "
        "UTUI-RESOLVED-SIZE 7 + ALLOT"
    )
    aligned = (
        "_UTUI-RST-RESOLVED-MEM 7 + -8 AND "
        "CONSTANT _UTUI-RST-RESOLVED"
    )
    assert source.index(raw) < source.index(aligned) < source.index(
        "CREATE _UTUI-RST-SEEN"
    )


def test_shared_widget_proxy_region_is_cell_aligned() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")

    raw = "CREATE _UTUI-PROXY-RGN-MEM  _RGN-DESC-SIZE 7 + ALLOT"
    aligned = (
        "_UTUI-PROXY-RGN-MEM 7 + -8 AND "
        "CONSTANT _UTUI-PROXY-RGN"
    )
    assert source.index(raw) < source.index(aligned) < source.index(
        ": _UTUI-SYNC-PROXY"
    )


def test_effective_visibility_uses_ancestors_menus_and_root_intersection() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")
    resolve = _definition(source, "_UTUI-RS-RESOLVE")
    root_geometry = _definition(source, "_UTUI-RS-ROOT-GEOMETRY?")
    intersects = _definition(source, "_UTUI-RS-INTERSECTS-ROOT?")

    # Every ancestor must remain a live HAS sidecar and locally paintable.
    ancestor_at = resolve.index("_UTUI-RS-NODE @ UIDL-ELEM-INDEX?")
    local_vis_at = resolve.index("_UTUI-SC-VIS? 0=", ancestor_at)
    parent_at = resolve.index("_UTUI-RS-NODE @ UIDL-PARENT", local_vis_at)
    assert ancestor_at < local_vis_at < parent_at
    assert "0 _UTUI-RS-VISIBLE !" in resolve[local_vis_at:parent_at]
    assert "_UTUI-VISIBLE @" not in resolve

    # A closed menu suppresses descendants, while the menu node itself remains
    # a coherent record. This follows the existing two-pass paint traversal.
    menu_at = resolve.index("UIDL-TYPE UIDL-T-MENU =", local_vis_at)
    assert "_UTUI-RS-NODE @ _UTUI-RS-ELEM @ <>" in resolve[
        local_vis_at:menu_at
    ]
    assert "_UTUI-MENU-OPEN @ <> AND" in resolve[menu_at:parent_at]

    # Root clipping is an intersection predicate over validated sidecar
    # geometry. It changes paintability, never the full captured rectangle.
    for field in ("ROW", "COL", "H", "W"):
        assert (
            f"_UTUI-SC-{field}@ _UTUI-RS-ROOT-{field} !" in root_geometry
        )
    assert root_geometry.count("_UTUI-RS-AXIS-END?") == 2
    for comparison in (
        "_UTUI-RS-ROW @ _UTUI-RS-ROOT-ROW-END @ <",
        "_UTUI-RS-ROOT-ROW @ _UTUI-RS-ROW-END @ <",
        "_UTUI-RS-COL @ _UTUI-RS-ROOT-COL-END @ <",
        "_UTUI-RS-ROOT-COL @ _UTUI-RS-COL-END @ <",
    ):
        assert comparison in intersects
    for mutator in (
        "_UTUI-RS-ROW !",
        "_UTUI-RS-COL !",
        "_UTUI-RS-H !",
        "_UTUI-RS-W !",
        "_UTUI-SC-ROW!",
        "_UTUI-SC-COL!",
        "_UTUI-SC-H!",
        "_UTUI-SC-W!",
    ):
        assert mutator not in root_geometry + intersects

    root_at = resolve.index("_UTUI-RS-ROOT-GEOMETRY?")
    clip_at = resolve.index("_UTUI-RS-INTERSECTS-ROOT?", root_at)
    ok_at = resolve.index("UTUI-RESOLVED-S-OK", clip_at)
    assert root_at < clip_at < ok_at
    assert "0 _UTUI-RS-VISIBLE !" in resolve[clip_at:ok_at]


def test_effective_z_tracks_the_outermost_deferred_paint_group() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")
    resolve = _definition(source, "_UTUI-RS-RESOLVE")

    dialog_at = resolve.index("UIDL-TYPE UIDL-T-DIALOG =")
    z_store_at = resolve.index("?DUP IF _UTUI-RS-Z ! THEN", dialog_at)
    walk_on_at = resolve.index("_UTUI-RS-NODE @ UIDL-PARENT", z_store_at)
    assert "_UTUI-SC-ZIDX@ DUP 0= IF DROP 255 THEN" in resolve[
        dialog_at:z_store_at
    ]
    assert "MAX" not in resolve[dialog_at:walk_on_at]
    assert "EXIT" not in resolve[z_store_at:walk_on_at]
    assert dialog_at < z_store_at < walk_on_at

    # The target-to-root loop overwrites only for a deferred node, so the last
    # assignment is the outermost dialog/positive-z group used by paint pass 1.
    assert "_UTUI-RS-NODE !" in resolve[walk_on_at:]
    assert "1 _UTUI-RS-DEPTH +!" in resolve[walk_on_at:]


def test_capture_preflights_then_publishes_nine_fields_without_aliases() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")
    span = _definition(source, "_UTUI-RESOLVED-SPAN?")
    capture = _definition(source, "_UTUI-ELEM-RESOLVED-CAPTURE-BODY")
    boundary = _definition(source, "UTUI-ELEM-RESOLVED-CAPTURE")
    writer = _definition(source, "_UTUI-RS-WRITE")

    for preflight in (
        "DUP 0< IF",
        "UTUI-RESOLVED-SIZE U<",
        "OVER 0= IF",
        "OVER 7 AND IF",
        "MSPAN-NONWRAPPING?",
    ):
        assert preflight in span

    span_at = capture.index("_UTUI-RESOLVED-SPAN? 0=")
    disjoint_at = capture.index("UTUI-STORAGE-DISJOINT? 0=", span_at)
    resolve_at = capture.index("_UTUI-RS-CALL", disjoint_at)
    status_at = capture.index("UTUI-RESOLVED-S-OK <>", resolve_at)
    retain_at = capture.index("_UTUI-RS-DST !", status_at)
    write_at = capture.index("_UTUI-RS-WRITE", retain_at)
    assert span_at < disjoint_at < resolve_at < status_at < retain_at < write_at
    assert "OVER UTUI-RESOLVED-SIZE UTUI-STORAGE-DISJOINT?" in capture
    assert "_UTUI-RS-CLEAR 0 _UTUI-RS-DST !" in capture[status_at:write_at]
    assert "0 _UTUI-RS-DST !" in capture[write_at:]
    assert writer.count("_UTUI-RS.") == 9
    assert "CATCH" in boundary
    assert "_UTUI-RS-CLEAR" in boundary

    # No destination operation precedes complete preflight and resolution;
    # ordinary validation failures therefore leave all 72 bytes untouched.
    for forbidden in ("0 FILL", "CMOVE", "_UTUI-SIDECAR", "TSC-"):
        assert forbidden not in capture + writer


def test_storage_boundary_covers_the_provider_and_borrowed_authorities() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")
    disjoint = _definition(source, "_UTUI-STORAGE-DISJOINT-BODY?")

    assert "OVER 0= OVER 0> 0= OR" in disjoint
    assert "MSPAN-NONWRAPPING? 0=" in disjoint
    assert "_UTUI-OWNED-LIMIT @" in disjoint
    assert "_UTUI-SIDECARS -" in disjoint
    assert "_UTUI-RGN @ DUP IF" in disjoint
    assert "RGN-SIZE MSPAN-NONWRAPPING? 0=" in disjoint
    assert "RGN-SIZE MSPAN-OVERLAP?" in disjoint
    assert "_UCTX-LIVE-OWNER @ DUP IF" in disjoint
    assert "UCTX-TOTAL MSPAN-NONWRAPPING? 0=" in disjoint
    assert "UCTX-TOTAL MSPAN-OVERLAP?" in disjoint
    assert "UIDL-STORAGE-DISJOINT? 0=" in disjoint
    assert "UIDL-SEMANTIC-STORAGE-DISJOINT? 0=" in disjoint
    assert "ST-STORAGE-DISJOINT? 0=" in disjoint
    assert "2DROP -1" in disjoint

    # One conservative module-owned span includes every resolved-state scratch
    # cell; the active UCTX and borrowed root region are checked separately.
    sidecars_at = source.index("CREATE _UTUI-SIDECARS")
    owned_end_at = source.index("CREATE _UTUI-OWNED-END")
    assert sidecars_at < source.index("VARIABLE _UTUI-RS-P-ELEM") < owned_end_at
    assert sidecars_at < source.index("VARIABLE _UTUI-RS-DST") < owned_end_at


def test_guarded_observation_acquires_utui_before_uidl() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")

    assert "EXECUTE" in _definition(source, "UTUI-RESOLVED-OBSERVE")
    inner = _definition(source, "_UTUI-RESOLVED-IN-UIDL")
    assert "UIDL-OBSERVE" in inner
    assert "_utui-guard" not in inner

    guarded_observe = _last_definition(source, "UTUI-RESOLVED-OBSERVE")
    assert (
        "['] _UTUI-RESOLVED-IN-UIDL _utui-guard WITH-GUARD"
        in guarded_observe
    )
    wrappers = {
        "UTUI-ELEM-RESOLVED-STATE@": (
            "_utui-elem-resolved-state-at-xt"
        ),
        "UTUI-ELEM-RESOLVED-CAPTURE": (
            "_utui-elem-resolved-capture-xt"
        ),
        "UTUI-STORAGE-DISJOINT?": "_utui-storage-disjoint-q-xt",
    }
    for public, captured in wrappers.items():
        wrapper = _last_definition(source, public)
        assert captured in wrapper
        assert "UTUI-RESOLVED-OBSERVE" in wrapper


def test_collection_observation_is_exact_visitor_scoped_and_alias_safe() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")
    scan = _definition(source, "_UTUI-CS-BODY")
    span = _definition(source, "_UTUI-CS-SPAN?")
    one = _definition(source, "_UTUI-CS-ONE")
    query = _definition(source, "_UTUI-CS-QUERY-WIDGET")
    genuine_area = _definition(source, "_UTUI-MC-GENUINE-TEXTAREA?")
    genuine_grid = _definition(source, "_UTUI-MC-GENUINE-TEXTGRID?")
    genuine_tabs = _definition(source, "_UTUI-MC-GENUINE-TABS?")
    genuine = _definition(source, "_UTUI-MC-GENUINE-COLLECTION?")
    direct_family = _definition(source, "_UTUI-VC-DIRECT-FAMILY@")
    tab_children = _definition(source, "_UTUI-VC-TAB-CHILDREN?")
    prepare_area = _definition(source, "_UTUI-VC-PREPARE-TEXTAREA")
    prepare_tabs = _definition(source, "_UTUI-VC-PREPARE-TABS")
    prepare = _definition(source, "_UTUI-VC-PREPARE")
    capture_current = _definition(source, "_UTUI-VC-CAPTURE-CURRENT")
    capture_tabs = _definition(source, "_UTUI-VC-TABSET-CAPTURE")
    tabs_active = _definition(source, "_UTUI-TABS-ACTIVE@")
    render_tabs = _definition(source, "_UTUI-RENDER-TABS")
    layout_tabs = _definition(source, "_UTUI-LAYOUT-TABS")
    handle_tabs = _definition(source, "_UTUI-H-TABS")
    entry = _definition(source, "_UTUI-VC-ENTRY-SPANS?")
    public = _definition(source, "UTUI-VISITED-COLLECTION-CAPTURE")
    local_body = _definition(source, "_UTUI-VC-CAPTURE-PREFLIGHTED-BODY")

    assert "REQUIRE widgets/text-grid.f" in source
    assert "REQUIRE widgets/tabs.f" in source
    assert "UIDL-ELEM-COUNT" in scan
    assert "UE.TYPE @ IF" in scan
    assert re.search(
        r"DUP 0= IF DROP _UTUI-CS-SPAN-A @ 0= EXIT THEN\s+DROP\s+"
        r"_UTUI-CS-SPAN-A @",
        span,
    )
    for forbidden in ("_UTUI-SC-VIS?", "_UTUI-SCF-HAS", "EFFECTIVE"):
        assert forbidden not in scan
    assert "_UTUI-WOWNER-UIDL" in one
    assert "_UTUI-WOWNER-CALLER" in one
    assert "_UTUI-CS-QUERY-WIDGET" in one
    for check in (
        "TXTA-TEXT-AREA-STORAGE-DISJOINT?",
        "TGRID-TEXT-GRID-STORAGE-DISJOINT?",
        "TAB-TABSET-STORAGE-DISJOINT?",
    ):
        assert check in query
    assert "WDG-T-TEXTAREA" in genuine_area
    assert "['] _TXTA-DRAW" in genuine_area
    assert "['] _TXTA-HANDLE" in genuine_area
    for exact_grid_field in (
        "_TGRID-DESC-SIZE",
        "_WDG-O-TYPE + @",
        "['] _TGRID-DRAW",
        "['] _TGRID-HANDLE",
    ):
        assert exact_grid_field in genuine_grid
    for exact_tabs_field in (
        "_TAB-DESC-SIZE",
        "WDG-T-TABS",
        "['] _TAB-DRAW",
        "['] _TAB-HANDLE",
        "_TAB-O-INSTANCE",
    ):
        assert exact_tabs_field in genuine_tabs
    assert "_UTUI-MC-GENUINE-TEXTAREA?" in genuine
    assert "_UTUI-MC-GENUINE-TEXTGRID?" in genuine
    assert "_UTUI-MC-GENUINE-TABS?" in genuine
    assert "_UTUI-MC-GENUINE-COLLECTION?" in query

    assert "_UTUI-RST-ACTIVE @ 0=" in prepare
    assert "_UTUI-RST-ELEM @ <>" in prepare
    assert "_UTUI-VC-DIRECT-FAMILY@" in prepare
    assert "UIDL-T-TEXTAREA" in direct_family
    assert "UIDL-T-TABS" in direct_family
    assert "_UTUI-WOWNER-CALLER = IF" in prepare
    assert "_UTUI-SYNC-PROXY" in prepare_area
    assert "_UTUI-SYNC-WFOCUS" in prepare_area
    assert "_UTUI-VC-TAB-CHILDREN?" in prepare_tabs
    assert "UIDL-FIRST-CHILD" in tab_children
    assert "UIDL-PARENT" in tab_children
    assert "UIDL-T-TAB <>" in tab_children
    assert "UIDL-NCHILDREN" in tab_children
    assert "3 PICK 3 PICK _UTUI-VC-SPAN-SAFE?" in entry
    assert "['] _UTUI-VC-CAPTURE-BODY CATCH" in public
    assert "_UTUI-VC-CAPTURE-CURRENT" in local_body
    assert "TXTA-TEXT-AREA-CAPTURE" in capture_current
    assert "_UTUI-VC-TABSET-CAPTURE" in capture_current
    assert "USCOL-TABSET-BEGIN" in capture_tabs
    assert "UIDL-ELEM-INDEX?" in capture_tabs
    assert "_UTUI-TABS-ACTIVE@" in capture_tabs
    assert "USCOL-TAB" in capture_tabs
    for clamp in ("UIDL-NCHILDREN", "0 MAX", "1- MIN"):
        assert clamp in tabs_active
    for consumer in (render_tabs, layout_tabs, handle_tabs, capture_tabs):
        assert "_UTUI-TABS-ACTIVE@" in consumer
    assert "_UTUI-VC-SPAN-SAFE?" not in local_body

    section = source.split("Current-visit canonical collection observation", 1)[1]
    section = section.split("In unguarded builds", 1)[0]
    executable = "\n".join(
        line.split("\\", 1)[0] for line in section.splitlines()
    )
    for forbidden in (
        "UTUI-RESOLVED-TREE-EACH",
        "UTUI-RESOLVED-OBSERVE",
        "UTUI-PAINT",
        "WDG-DRAW",
        "EXECUTE",
        "callback",
    ):
        assert forbidden.lower() not in executable.lower()

    guarded_capture = _last_definition(
        source, "UTUI-VISITED-COLLECTION-CAPTURE"
    )
    guarded_visited_query = _last_definition(
        source, "UTUI-VISITED-COLLECTION-STORAGE-DISJOINT?"
    )
    guarded_global_query = _last_definition(
        source, "UTUI-COLLECTION-STORAGE-DISJOINT?"
    )
    assert "_utui-guard WITH-GUARD" in guarded_capture
    assert "_utui-guard WITH-GUARD" in guarded_visited_query
    assert "UTUI-RESOLVED-OBSERVE" in guarded_global_query


def test_relayout_owns_each_resolution_pass_once_and_load_does_not_repeat_it() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")
    relayout = _definition(source, "UTUI-RELAYOUT")
    ordered = (
        "_UTUI-RESET-RESOLVED",
        "_UTUI-PRELAYOUT-STYLES-D",
        "_UTUI-DO-LAYOUT-REC",
        "_UTUI-RESOLVE-STYLES-D",
        "_UTUI-RESOLVE-POSITIONED",
        "_UTUI-FINALIZE-MENU",
        "_UTUI-PROJECTION-RELAYOUT",
    )
    positions = [relayout.index(word) for word in ordered]
    assert positions == sorted(positions)
    assert all(relayout.count(word) == 1 for word in ordered)

    assert "' _UTUI-PRELAYOUT-STYLES IS _UTUI-PRELAYOUT-STYLES-D" in source
    assert "' _UTUI-RESOLVE-STYLES IS _UTUI-RESOLVE-STYLES-D" in source

    load = _definition(source, "UTUI-LOAD")
    assert load.count("UTUI-RELAYOUT") == 1
    for pass_word in ordered:
        assert pass_word not in load

    reset = _definition(source, "_UTUI-RESET-RESOLVED-ELEM")
    for setter in (
        "_UTUI-SC-ROW!",
        "_UTUI-SC-COL!",
        "_UTUI-SC-H!",
        "_UTUI-SC-W!",
        "_UTUI-SC-STYLE!",
        "_UTUI-SC-PAD!",
        "_UTUI-SC-OFFS!",
        "_UTUI-SC-MARGIN!",
    ):
        assert f"0 R@ {setter}" in reset
    assert "_UTUI-SC-WPTR" not in reset
    assert "_UTUI-SC-WOWNER" not in reset


def test_open_menu_geometry_is_finalized_after_authored_layout_state() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")
    open_menu = _definition(source, "_UTUI-MENU-OPEN!")
    layout_menu = _definition(source, "_UTUI-LAYOUT-MENU")
    row_layout = _definition(source, "_UTUI-MENU-ROW?")
    navigable = _definition(source, "_UTUI-MENU-NAVIGABLE?")
    measure = _definition(source, "_UTUI-MENU-MEASURE")
    finalizer = _definition(source, "_UTUI-FINALIZE-MENU")
    close = _definition(source, "_UTUI-MENU-CLOSE")

    assert "DUP _UTUI-FINALIZE-MENU-D" in open_menu
    assert "DROP" in layout_menu
    assert "_UTUI-MENU-MEASURE" not in layout_menu
    for saved in (
        "_UTUI-MENU-SAVE-ROW",
        "_UTUI-MENU-SAVE-H",
        "_UTUI-MENU-SAVE-W",
        "_UTUI-MENU-SAVE-Z",
    ):
        assert saved not in open_menu
        assert saved in finalizer
    assert "_UTUI-MENU-MEASURE" in finalizer
    assert "200 OVER _UTUI-SIDECAR TSC-SET-ZIDX!" in finalizer
    assert "_UTUI-SCF-HAS _UTUI-SCF-VIS OR" in finalizer
    assert "_UTUI-SCF-VIS OR _UTUI-SCF-FOC OR" not in finalizer
    assert "UIDL-EVAL-WHEN 0=" in row_layout
    assert "UIDL-T-ITEM =" in row_layout
    assert "UIDL-T-SEPARATOR =" in row_layout
    assert "_UTUI-SCF-HIDE AND" in row_layout
    assert "_UTUI-SC-POS@ 0=" in row_layout
    assert "UIDL-T-ITEM <>" in navigable
    assert "_UTUI-MENU-ROW?" in navigable
    assert "_UTUI-SC-VIS?" in navigable
    assert "DUP _UTUI-MENU-ROW? IF" in measure
    assert "DUP _UTUI-MENU-ROW? IF" in finalizer
    assert "DUP _UTUI-MENU-NAVIGABLE? 0= IF" in finalizer
    assert "_UTUI-SCF-HAS OVER _UTUI-SC-LAYOUT-FLAGS!" in finalizer
    assert "DUP _UTUI-FOCUS-D = IF 0 _UTUI-FOCUS!-D THEN" in finalizer
    assert "_UTUI-MENU-FIRST-ITEM ?DUP IF _UTUI-FOCUS!-D THEN" in finalizer
    assert "_UTUI-MENU-SAVE-Z @ SWAP TSC-SET-ZIDX!" in close

    for name in (
        "_UTUI-MENU-FIRST-ITEM",
        "_UTUI-MENU-LAST-ITEM",
        "_UTUI-MENU-ITEM-NEXT",
        "_UTUI-MENU-ITEM-PREV",
    ):
        assert "_UTUI-MENU-NAVIGABLE?" in _definition(source, name)
    for name in ("_UTUI-MENU-SWITCH-NEXT", "_UTUI-MENU-SWITCH-PREV"):
        assert "_UTUI-MENU-AVAILABLE?" in _definition(source, name)


def test_runtime_visibility_survives_relayout_without_collapsing_layout() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")
    visible = _definition(source, "_UTUI-SC-VIS?")
    subtree = _definition(source, "_UTUI-VIS-SUBTREE!")
    skip = _definition(source, "_UL-SKIP-LAYOUT?")
    reset = _definition(source, "_UTUI-RESET-RESOLVED-ELEM")

    assert "TSC-O-AUX6  CONSTANT _UTUI-SC-O-RUNTIME" in source
    assert "1 CONSTANT _UTUI-RUNTIME-F-HIDDEN" in source
    assert "_UTUI-SC-RUNTIME@ _UTUI-RUNTIME-F-HIDDEN AND 0= AND" in visible
    assert "_UTUI-SC-RUNTIME!" in subtree
    assert "_UTUI-RUNTIME-F-HIDDEN INVERT AND" in subtree
    assert "_UTUI-RUNTIME-F-HIDDEN OR" in subtree
    assert "RUNTIME" not in skip
    assert "_UTUI-SC-RUNTIME!" not in reset

    layout_flags = _definition(source, "_UTUI-SC-LAYOUT-FLAGS!")
    assert "_UTUI-SCF-DURABLE" in layout_flags
    assert "_UTUI-SC-FLAGS@" in layout_flags


def test_cell_paint_uses_the_same_effective_subtree_and_root_clip_contract() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")
    draw_source = DRAW.read_text(encoding="utf-8")
    region_source = REGION.read_text(encoding="utf-8")
    paint_elem = _definition(source, "_UTUI-PAINT-ELEM")
    subtree = _definition(source, "_UTUI-PAINT-SUBTREE")
    stash = _definition(source, "_UTUI-STASH-SC")
    proxy = _definition(source, "_UTUI-PROXY-FROM-UR")
    region = _definition(source, "_UTUI-RENDER-REGION")
    paint = _definition(source, "UTUI-PAINT")
    finish = _definition(source, "_UTUI-PAINT-FINISH")
    in_bounds = _definition(draw_source, "_DRW-IN-BOUNDS?")
    activate = _definition(region_source, "_RGN-ACTIVATE")

    root_declaration = source.index("VARIABLE _UTUI-RGN")
    assert root_declaration < source.index(": _UTUI-SYNC-PROXY")
    assert root_declaration < source.index(": _UTUI-PROXY-FROM-UR")

    vis_at = paint_elem.index("_UTUI-SC-VIS? 0=")
    dirty_at = paint_elem.index("UIDL-DIRTY? 0=")
    assert vis_at < dirty_at
    assert "-1 _UTUI-SKIP-CHILDREN !" in paint_elem[vis_at:dirty_at]

    assert "_UTUI-SC-VIS? 0=" in subtree
    assert "_UTUI-PAINT-SUBTREE-NEXT" in subtree
    assert "UIDL-TYPE UIDL-T-MENU =" in subtree
    assert "_UTUI-MENU-OPEN @ <> AND" in subtree

    assert "_UR-ABS-ROW" in stash and "RGN-ROW -" in stash
    assert "_UR-ABS-COL" in stash and "RGN-COL -" in stash
    assert "_UR-ABS-ROW @" in proxy and "_UR-ABS-COL @" in proxy
    assert "_UTUI-RGN @ _UTUI-PROXY-RGN _RGN-O-PARENT + !" in proxy
    assert "_UTUI-RGN @ SWAP _RGN-O-PARENT + !" in region
    assert "_DRW-ORIGIN-ROW @ +" in in_bounds
    assert "_DRW-ORIGIN-COL @ +" in in_bounds
    assert "_DRW-CLIP-ROW @ _DRW-CLIP-H @ + WITHIN" in in_bounds
    assert "_DRW-CLIP-COL @ _DRW-CLIP-W @ + WITHIN" in in_bounds
    assert "_RGN-O-PARENT + @" in activate
    assert "MAX _RGN-ACT-TOP" in activate
    assert "MAX _RGN-ACT-LEFT" in activate
    assert "MIN _RGN-ACT-BOTTOM" in activate
    assert "MIN _RGN-ACT-RIGHT" in activate
    assert "_UTUI-RESTORE-DOC-RGN" in paint
    assert paint.count("_UTUI-PAINT-FINISH") == 2
    assert "_UTUI-PAINT-PASS2" in finish and "RGN-ROOT" in finish


def test_menu_lifecycle_state_is_context_local_and_cleared_at_boundaries() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")
    init = _definition(source, "_UCTX-INIT-VARS")
    clear = _definition(source, "_UTUI-MENU-STATE-CLEAR")

    assert "29 CONSTANT _UCTX-NVAR" in source
    assert "232 CONSTANT _UCTX-VAR-SZ" in source
    fields = (
        "_UTUI-MENU-OPEN",
        "_UTUI-MENU-SAVED-FOC",
        "_UTUI-MENU-SAVE-ROW",
        "_UTUI-MENU-SAVE-H",
        "_UTUI-MENU-SAVE-W",
        "_UTUI-MENU-SAVE-Z",
    )
    for slot, field in enumerate(fields, start=21):
        assert f"{field}" in init
        assert f"_UCTX-VARS {slot} CELLS + !" in init
        assert f"0 {field} !" in clear

    assert "_UTUI-SEMANTIC-RESOLVED-GENERATION" not in init
    assert "_UTUI-MC-HEAD" in init
    assert "_UCTX-VARS 27 CELLS + !" in init
    assert "_UTUI-MC-COUNT" in init
    assert "_UCTX-VARS 28 CELLS + !" in init

    assert "_UTUI-MENU-STATE-CLEAR" in _definition(source, "UTUI-LOAD")
    assert "_UTUI-MENU-STATE-CLEAR" in _definition(source, "UTUI-DETACH")
    remove = _definition(source, "UTUI-REMOVE-ELEM")
    assert "_UTUI-ANCESTOR-OF?" in remove
    assert "_UTUI-MENU-CLOSE" in remove


def test_loaded_terminology_is_absent_from_the_resolved_state_slice() -> None:
    code = UIDL_TUI.read_text(encoding="utf-8")
    docs = (ROOT / "docs" / "tui" / "uidl-tui.md").read_text(encoding="utf-8")
    loaded_term = "pres" + "entation"
    assert loaded_term.lower() not in code.lower()
    assert loaded_term.lower() not in docs.lower()


def test_transitional_semantic_record_codec_is_absent() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")

    for token in (
        "UTUI-SEMANTIC-S-",
        "UTUI-SEMANTIC-RECORD-",
        "UTUI-SEMANTIC-ENTRY-",
        "_UTUI-SEMANTIC-RECORD-",
        "_UTUI-SE.",
        "_UTUI-SEE.",
        "_UTUI-SE-SCAN-",
    ):
        assert token not in source


def test_mounted_relation_index_is_canonical_and_ready_only_when_valid() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")
    generation = _definition(source, "_UTUI-MC-GENERATION-VALID?")
    canonical = _definition(source, "_UTUI-MC-RELATIONS-CANONICAL?")
    insert = _definition(source, "_UTUI-MC-REL-INSERT-CANONICAL")
    ready = _definition(source, "_UTUI-MC-RELATIONS-READY?")
    commit = _definition(source, "_UTUI-MC-COMMIT-STAGE")
    upsert = _definition(source, "_UTUI-MC-UPSERT")
    family_predicate = _definition(source, "_UTUI-MC-FAMILY?")

    assert "56 CONSTANT _UTUI-MC-REL-SIZE" in source
    assert "48 CONSTANT _UTUI-MCR-O-FAMILY" in source
    assert "40 CONSTANT _UTUI-MC-STAGE-SIZE" in source
    assert "32 CONSTANT _UTUI-MCT-O-FAMILY" in source
    assert "_UTUI-MCR-O-FAMILY + @" in _definition(
        source, "_UTUI-MCR-FAMILY@"
    )
    assert "_UTUI-MCT-O-FAMILY + @" in _definition(
        source, "_UTUI-MCT-FAMILY@"
    )

    assert "DUP 0<> SWAP -1 <> AND" in generation
    assert (
        "_UTUI-MC-HEAD @ _UTUI-MC-COUNT @ _UTUI-MC-REL-SIZE"
        in canonical
    )
    assert "_UTUI-MC-CHAIN-WELL-FORMED? 0=" in canonical
    for required in (
        "_UTUI-MCR-SOURCE@",
        "_UTUI-MCR-GENERATION@ _UTUI-MC-GENERATION-VALID?",
        "_UTUI-MCR-ROOT-KEY@ DUP 0=",
        "_UTUI-MCR-FAMILY@ _UTUI-MC-FAMILY?",
        "_UTUI-MC-CAN-PRIOR-SOURCE",
        "_UTUI-MC-CAN-PRIOR-KEY @ OVER U< 0=",
        "_UTUI-MC-CAN-SEEN @ _UTUI-MC-COUNT @ =",
    ):
        assert required in canonical
    for family in (
        "USCOL-F-TEXT-AREA",
        "USCOL-F-TEXT-GRID",
        "USCOL-F-TABSET",
    ):
        assert family in family_predicate

    # New and rediscovered relations enter the same strict unsigned
    # (source-index, root-key) order; neither draw order nor heap address is an
    # identity order.
    for field in ("_UTUI-MCR-SOURCE@", "_UTUI-MCR-ROOT-KEY@"):
        assert field in insert
    assert "U< IF" in insert
    assert "1 _UTUI-MC-COUNT +!" in insert
    assert "_UTUI-MC-REL-INSERT-CANONICAL" in commit
    assert "_UTUI-MC-REL-INSERT-CANONICAL" in upsert
    assert "_UTUI-MC-CHAIN-WELL-FORMED? 0=" in commit
    assert "_UTUI-MC-REL-CLEAR-ALL" in commit

    status_at = ready.index("_UTUI-MC-STATUS @")
    quiescent_at = ready.index("_UCTX-STAGE-QUIESCENT?", status_at)
    canonical_at = ready.index("_UTUI-MC-RELATIONS-CANONICAL?", quiescent_at)
    valid_at = ready.index("_UTUI-MC-RELATION-VALID?", canonical_at)
    distinct_at = ready.index("_UTUI-MC-RELATION-DISTINCT?", valid_at)
    count_at = ready.rindex("_UTUI-MC-V-SEEN @ _UTUI-MC-COUNT @ =")
    assert (
        status_at
        < quiescent_at
        < canonical_at
        < valid_at
        < distinct_at
        < count_at
    )


def test_mounted_identity_is_family_qualified_before_root_reuse() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")
    family = _definition(source, "_UTUI-MC-COLLECTION-FAMILY@")
    instance = _definition(source, "_UTUI-MC-COLLECTION-INSTANCE@")
    relation_valid = _definition(source, "_UTUI-MC-RELATION-VALID?")
    distinct = _definition(source, "_UTUI-MC-RELATION-DISTINCT?")
    stage_add = _definition(source, "_UTUI-MC-STAGE-ADD")
    find = _definition(source, "_UTUI-MC-FIND-RELATION")
    prepare = _definition(source, "_UTUI-MC-PREPARE-STAGE")
    upsert = _definition(source, "_UTUI-MC-UPSERT")
    associate = _definition(source, "_UTUI-MC-ASSOCIATE")
    observe = _definition(source, "_UTUI-MC-OBS-CANONICAL")

    assert "USCOL-F-TEXT-AREA" in family
    assert "USCOL-F-TEXT-GRID" in family
    assert "USCOL-F-TABSET" in family
    assert "TXTA-INSTANCE@" in instance or "_TXTA-O-INSTANCE" in instance
    assert "TGRID-INSTANCE@" in instance or "_TGRID-O-INSTANCE" in instance
    assert "TAB-INSTANCE@" in instance or "_TAB-O-INSTANCE" in instance

    for lifecycle in (relation_valid, stage_add, upsert):
        assert "_UTUI-MC-GENUINE-COLLECTION?" in lifecycle
        assert "_UTUI-MC-COLLECTION-FAMILY@" in lifecycle
        assert "_UTUI-MC-COLLECTION-INSTANCE@" in lifecycle
        assert "_TXTA-O-INSTANCE + @" not in lifecycle

    for mounted_entry in (associate, observe):
        assert "_UTUI-MC-GENUINE-COLLECTION?" in mounted_entry

    assert "_UTUI-MCR-FAMILY@" in relation_valid
    assert "_UTUI-MCR-FAMILY@" in distinct
    assert "_UTUI-MCR-INSTANCE@" in distinct
    assert "_UTUI-MCT-FAMILY@" in stage_add
    assert "_UTUI-MCT-INSTANCE@" in stage_add
    assert "_UTUI-MCR-FAMILY@" in find
    assert "_UTUI-MCR-INSTANCE@" in find
    assert "_UTUI-MCT-FAMILY@" in prepare
    assert "_UTUI-MCR-O-FAMILY" in prepare
    assert "_UTUI-MCR-O-FAMILY" in upsert

    # A family change at an allocator-reused address is a replacement, never
    # authority to inherit the old semantic root key.
    root_reuse = find.rindex("_UTUI-MC-F-FOUND !")
    assert find.index("_UTUI-MCR-FAMILY@") < root_reuse
    assert find.index("_UTUI-MCR-INSTANCE@") < root_reuse


def test_mounted_collection_iterator_is_private_aligned_and_outer_scoped() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")
    aligned = _definition(source, "_UTUI-MI-RESOLVED")
    body = _definition(source, "_UTUI-MI-BODY")
    call = _definition(source, "_UTUI-MI-CALL")
    visit = _definition(source, "_UTUI-MI-VISIT")
    each = _definition(
        source, "_UTUI-MOUNTED-COLLECTION-EACH-PREFLIGHTED"
    )
    geometry = _definition(source, "_UTUI-MOUNTED-COLLECTION-GEOMETRY")
    capture = _definition(
        source, "_UTUI-MOUNTED-COLLECTION-CAPTURE-PREFLIGHTED"
    )
    canonical_geometry = _definition(
        source, "_UTUI-CANONICAL-REGION-GEOMETRY"
    )
    visited_clear = _definition(source, "_UTUI-VC-CLEAR")

    assert (
        "CREATE _UTUI-MI-RESOLVED-MEM UTUI-RESOLVED-SIZE 7 + ALLOT"
        in source
    )
    assert "_UTUI-MI-RESOLVED-MEM 7 + -8 AND" in aligned
    assert not re.search(r"(?m)^:\s+UTUI-MOUNTED-COLLECTION", source)
    assert "_UTUI-MI-ACTIVE @ IF" in each
    assert "_UTUI-MI-CALL" in each

    ready_at = body.index("_UTUI-MC-RELATIONS-READY?")
    head_at = body.index("_UTUI-MC-HEAD @", ready_at)
    resolve_at = body.index("_UTUI-RS-RESOLVE", head_at)
    write_at = body.index("_UTUI-RS-WRITE", resolve_at)
    geometry_at = body.index("_UTUI-MI-SOURCE-GEOMETRY?", write_at)
    visible_at = body.index("_UTUI-RS-VISIBLE @ IF", geometry_at)
    visit_at = body.index("_UTUI-MI-VISIT", visible_at)
    count_at = body.rindex("_UTUI-MI-SEEN @ _UTUI-MC-COUNT @ <>")
    assert ready_at < head_at < resolve_at < write_at < geometry_at < visible_at
    assert visible_at < visit_at < count_at
    assert "CATCH" in call
    assert "_UTUI-RS-CLEAR" in call
    assert "_UTUI-MI-CLEAR" in call
    assert "_UTUI-MC-SCRATCH-CLEAR" in _definition(
        source, "_UTUI-MI-CLEAR"
    )

    assert (
        "_UTUI-MI-SOURCE @ _UTUI-MI-GENERATION @ _UTUI-MI-ROOT-KEY @"
        in visit
    )
    assert "_UTUI-MI-RESOLVED UTUI-RESOLVED-SIZE" in visit
    assert "_UTUI-MI-VISITOR @ EXECUTE" in visit
    for private_pointer in ("_UTUI-MI-WIDGET", "_UTUI-MI-CURRENT"):
        assert private_pointer not in visit

    for seam in (geometry, capture):
        assert "_UTUI-MI-CURRENT-VALID? 0=" in seam
    assert "_UTUI-CANONICAL-REGION-GEOMETRY" in geometry
    assert "_UTUI-MC-CAPTURE" in capture
    capture_dispatch = _definition(source, "_UTUI-MC-CAPTURE")
    assert "TXTA-TEXT-AREA-CAPTURE" in capture_dispatch
    assert "TGRID-TEXT-GRID-CAPTURE" in capture_dispatch
    assert "TAB-TABSET-CAPTURE" in capture_dispatch

    assert "UTUI-RESOLVED-VALID? 0=" in canonical_geometry
    assert "_UTUI-MC-RGN-ACYCLIC? 0=" in canonical_geometry
    assert "_UTUI-CG-SAW-DOC" in canonical_geometry
    assert "_UTUI-CG-CLEAR" in _definition(source, "_UTUI-CG-FAIL")
    assert "USCOL-S-OK _UTUI-CG-CLEAR" in canonical_geometry
    for borrowed in (
        "_UTUI-VC-G-RESOLVED-A",
        "_UTUI-VC-G-RESOLVED-U",
        "_UTUI-VC-G-ELEM",
    ):
        assert f"0 {borrowed} !" in visited_clear
    assert canonical_geometry.count("_UTUI-CG-INTERSECT?") >= 2
    for result in (
        "_UTUI-CG-ORIGIN-ROW @",
        "_UTUI-CG-ORIGIN-COL @",
        "_UTUI-CG-EXTENT-H @",
        "_UTUI-CG-EXTENT-W @",
        "_UTUI-CG-CLIP-TOP @",
        "_UTUI-CG-CLIP-LEFT @",
    ):
        assert result in canonical_geometry

    section = source.split(
        "Canonical widget region geometry and mounted collection observation",
        1,
    )[1].split("Check one caller span", 1)[0]
    executable = "\n".join(
        line.split("\\", 1)[0] for line in section.splitlines()
    )
    for forbidden in (
        "UTUI-RESOLVED-OBSERVE",
        "UTUI-RESOLVED-TREE-EACH",
        "UTUI-PAINT",
        "WDG-DRAW",
        "ASHELL-",
        "UTUI-SEMANTIC-",
        "_PAD-",
        "_DB-",
    ):
        assert forbidden not in executable


def test_collection_storage_preflight_covers_mounted_private_authorities() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")
    public = _definition(source, "UTUI-COLLECTION-STORAGE-DISJOINT?")
    scan = _definition(source, "_UTUI-CS-BODY")
    one = _definition(source, "_UTUI-CS-ONE")
    relations = _definition(source, "_UTUI-CS-RELATIONS")
    region_chain = _definition(source, "_UTUI-CS-REGION-CHAIN?")
    safe = _definition(source, "_UTUI-VC-SPAN-SAFE?")

    textarea_at = public.index("TXTA-STORAGE-DISJOINT? 0=")
    grid_at = public.index("TGRID-STORAGE-DISJOINT? 0=")
    tabs_at = public.index("TAB-STORAGE-DISJOINT? 0=")
    scratch_at = public.index("_UTUI-CS-SPAN-U !")
    assert textarea_at < scratch_at
    assert grid_at < scratch_at
    assert tabs_at < scratch_at
    assert "_UTUI-MC-SCRATCH-CLEAR" in _definition(
        source, "_UTUI-CS-CLEAR"
    )
    assert "_UTUI-WOWNER-CALLER <>" in one
    assert "_WDG-HDR-SIZE MSPAN-NONWRAPPING? 0=" in one
    assert "_WDG-HDR-SIZE _UTUI-CS-RANGE-DISJOINT?" in one
    assert one.index(
        "_WDG-HDR-SIZE _UTUI-CS-RANGE-DISJOINT?"
    ) < one.rindex("_UTUI-CS-QUERY-WIDGET")
    assert scan.index("_UTUI-MC-RELATIONS-READY?") < scan.index(
        "_UTUI-DOC-LOADED @"
    )
    assert "_UTUI-CS-RELATIONS" in scan
    for required in (
        "_UTUI-MC-REL-SIZE _UTUI-CS-RANGE-DISJOINT?",
        "_UTUI-CS-REGION-CHAIN?",
        "_UTUI-CS-QUERY-WIDGET",
        "_WDG-HDR-SIZE _UTUI-CS-RANGE-DISJOINT?",
        "_UTUI-CS-REL-SEEN @ _UTUI-MC-COUNT @ <>",
    ):
        assert required in relations
    assert "_UTUI-MC-RGN-ACYCLIC? 0=" in region_chain
    assert "RGN-SIZE _UTUI-CS-RANGE-DISJOINT?" in region_chain
    assert "_RGN-O-PARENT" in region_chain
    for first_line_authority in (
        "USCOL-STORAGE-DISJOINT?",
        "TXTA-STORAGE-DISJOINT?",
        "TGRID-STORAGE-DISJOINT?",
        "TAB-STORAGE-DISJOINT?",
        "_UTUI-STORAGE-DISJOINT-BODY?",
        "UTUI-COLLECTION-STORAGE-DISJOINT?",
    ):
        assert first_line_authority in safe


def test_generic_mounted_relation_uctx_has_no_provider_path() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")
    shell = APP_SHELL.read_text(encoding="utf-8")

    forbidden = (
        "UTUI-SEMANTIC-SET",
        "UTUI-SEMANTIC-REVISION!",
        "UTUI-SEMANTIC-ADVANCE",
        "UTUI-SEMANTIC-TOUCH",
        "UTUI-SEMANTIC-CLEAR",
        "UTUI-SEMANTIC-CAPTURE",
        "UTUI-SEMANTIC-SIZE",
        "UTUI-SEMANTIC-DISPATCH",
        "_UTUI-SEMANTIC-BINDING",
        "_UTUI-SB.",
        "_UTUI-SE-EVENT",
        "_UTUI-SEMANTIC-RESOLVED-GENERATION",
        "_UCTX-O-SEMANTICS",
    )
    for token in forbidden:
        assert token not in source

    assert "29 CONSTANT _UCTX-NVAR" in source
    assert "232 CONSTANT _UCTX-VAR-SZ" in source
    assert "27 CONSTANT _UCTX-NPLAIN" in source
    assert "11 CONSTANT _UCTX-NPOOL" in source
    assert "16 CONSTANT _UTUI-MC-SOURCE-SIZE" in source
    assert (
        "_UTUI-MAX-ELEMS _UTUI-MC-SOURCE-SIZE * "
        "CONSTANT _UTUI-MC-SOURCES-SIZE"
    ) in source
    assert "_UTUI-MC-SOURCES-SIZE CONSTANT _UCTX-MCS-SZ" in source
    assert (
        "_UCTX-O-OVBUF  _UCTX-OVBUF-SZ  +                   "
        "CONSTANT _UCTX-O-MCS"
    ) in source
    assert (
        "_UCTX-O-MCS    _UCTX-MCS-SZ    +                   "
        "CONSTANT UCTX-TOTAL"
    ) in source
    assert "107,752 bytes" in source
    assert 107_752 == (
        232
        + 32_768
        + 20_480
        + 12_288
        + 2_048
        + 4_096
        + 3_072
        + 24_576
        + 1_536
        + 2_048
        + 512
        + 4_096
    )

    init_vars = _definition(source, "_UCTX-INIT-VARS")
    assert "_UTUI-MC-HEAD          _UCTX-VARS 27 CELLS + !" in init_vars
    assert "_UTUI-MC-COUNT         _UCTX-VARS 28 CELLS + !" in init_vars

    init_pools = _definition(source, "_UCTX-INIT-POOLS")
    assert "_UTUI-MC-SOURCES  _UCTX-POOLS 240 + !" in init_pools
    assert "_UCTX-O-MCS       _UCTX-POOLS 248 + !" in init_pools
    assert "_UCTX-MCS-SZ      _UCTX-POOLS 256 + !" in init_pools

    allocate = _definition(source, "UCTX-ALLOC")
    assert allocate.index("UCTX-TOTAL ALLOCATE") < allocate.index(
        "DUP UCTX-TOTAL 0 FILL"
    )

    save = _definition(source, "UCTX-SAVE")
    assert save.index("_UCTX-LIVE-OWNER @ <>") < save.index(
        "_UCTX-STAGE-QUIESCENT?"
    ) < save.index("_UTUI-MC-SCRATCH-CLEAR") < save.index(
        "_UCTX-NPLAIN 0 DO"
    ) < save.index(
        "_UCTX-NPOOL 0 DO"
    ) < save.index("_UTUI-MC-HEAD @ OVER _UCTX-O-MC-HEAD + !")
    assert "_UTUI-MC-COUNT @ OVER _UCTX-O-MC-COUNT + !" in save

    restore = _definition(source, "UCTX-RESTORE")
    assert restore.index("_UCTX-LIVE-OWNER @") < restore.index(
        "_UCTX-STAGE-QUIESCENT?"
    ) < restore.index("_UTUI-MC-SCRATCH-CLEAR") < restore.index(
        "_UCTX-NPLAIN 0 DO"
    ) < restore.index(
        "_UCTX-NPOOL 0 DO"
    ) < restore.index("_UCTX-O-MC-HEAD + @ _UTUI-MC-HEAD !") < restore.index(
        "_UCTX-LIVE-OWNER !"
    )
    assert "_UCTX-O-MC-COUNT + @ _UTUI-MC-COUNT !" in restore

    disown = _definition(source, "UCTX-LIVE-DISOWN")
    assert disown.index("_UCTX-STAGE-QUIESCENT?") < disown.index(
        "_UTUI-MC-SCRATCH-CLEAR"
    ) < disown.index("_UCTX-LIVE-OWNER @ 0=")
    for cleared in (
        "0 _UTUI-MC-HEAD ! 0 _UTUI-MC-COUNT !",
        "_UTUI-MC-SOURCES _UTUI-MC-SOURCES-SIZE 0 FILL",
        "0 _UCTX-LIVE-OWNER !",
    ):
        assert cleared in disown

    live = _definition(source, "UCTX-LIVE?")
    assert "_UCTX-LIVE-OWNER @ =" in live
    assert "_UCTX-LIVE-OWNER" not in shell

    free = _definition(source, "UCTX-FREE")
    clear = _definition(source, "UCTX-CLEAR")
    for lifecycle in (free, clear):
        assert lifecycle.index("_UCTX-LIVE-OWNER @ =") < lifecycle.index(
            "_UCTX-STAGE-QUIESCENT?"
        ) < lifecycle.index(
            "_UCTX-FREE-SAVED-RELATIONS"
        ) < lifecycle.index(
            "_UTUI-MC-SCRATCH-CLEAR"
        )
    assert free.index("_UCTX-FREE-SAVED-RELATIONS") < free.index("\n    FREE ;")
    assert clear.index("_UCTX-FREE-SAVED-RELATIONS") < clear.index(
        "UCTX-TOTAL 0 FILL"
    )

    switch = _definition(shell, "ASHELL-CTX-SWITCH")
    assert "DUP UCTX-LIVE? IF DROP EXIT THEN" in switch
    assert switch.index("UCTX-SAVE") < switch.index(
        "UCTX-LIVE-DISOWN"
    ) < switch.index("0 _ASHELL-ACTIVE-CTX !") < switch.index(
        "UCTX-RESTORE"
    ) < switch.rindex("_ASHELL-ACTIVE-CTX !")
    force_save = _definition(shell, "ASHELL-CTX-SAVE")
    assert force_save.index("_ASHELL-ACTIVE-CTX @ <>") < force_save.index(
        "UCTX-SAVE"
    )
    forget = _definition(shell, "ASHELL-CTX-FORGET")
    assert "DUP UCTX-LIVE? IF" in forget

    detach = _definition(source, "UTUI-DETACH")
    assert detach.index("_UTUI-PROJECTION-DETACH") < detach.index(
        "_UTUI-MC-STAGE-CLEAR"
    ) < detach.index("_UTUI-MC-REL-CLEAR-ALL") < detach.index(
        "_UTUI-DEMATERIALIZE"
    ) < detach.index("_UTUI-MC-SOURCES _UTUI-MC-SOURCES-SIZE 0 FILL")

    remove = _definition(source, "UTUI-REMOVE-ELEM")
    assert remove.index("_UTUI-BEFORE-REMOVE-D") < remove.index(
        "_UTUI-DEMATERIALIZE-ONE"
    )
    assert (
        "' _UTUI-MC-INVALIDATE-SUBTREE IS _UTUI-BEFORE-REMOVE-D"
        in source
    )

    for word in ("UCTX-SAVE", "UCTX-RESTORE", "UTUI-WIDGET-SET", "UTUI-QUIESCE"):
        assert "SEMANTIC" not in _definition(source, word)
