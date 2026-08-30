"""Seconds-only structural locks for neutral UIDL-TUI resolved projection state."""

from __future__ import annotations

import re
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
UIDL_TUI = ROOT / "akashic" / "tui" / "uidl-tui.f"
CELL = ROOT / "akashic" / "tui" / "cell.f"
DRAW = ROOT / "akashic" / "tui" / "draw.f"
REGION = ROOT / "akashic" / "tui" / "region.f"


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
    assert "UIDL-STORAGE-DISJOINT? 0=" in disjoint
    assert "UIDL-SEMANTIC-STORAGE-DISJOINT? 0=" in disjoint
    assert "ST-STORAGE-DISJOINT? 0=" in disjoint
    assert "2DROP -1" in disjoint

    # One conservative provider span includes every resolved-state scratch cell.
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

    assert "28 CONSTANT _UCTX-NVAR" in source
    assert "224 CONSTANT _UCTX-VAR-SZ" in source
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

    assert "_UTUI-SEMANTIC-RESOLVED-GENERATION" in init
    assert "_UCTX-VARS 27 CELLS + !" in init

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


def test_mounted_semantic_collection_is_tagged_pointer_free_and_byte_exact() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")

    assert "0x314D455349555455 CONSTANT _UTUI-SEMANTIC-RECORD-MAGIC" in source
    assert "1 CONSTANT _UTUI-SEMANTIC-RECORD-ABI" in source
    assert "56 CONSTANT UTUI-SEMANTIC-RECORD-HEADER-SIZE" in source
    assert "32 CONSTANT UTUI-SEMANTIC-ENTRY-HEADER-SIZE" in source
    assert (0x314D455349555455).to_bytes(8, "little") == b"UTUISEM1"

    fields = {
        "MAGIC": 0,
        "ABI": 8,
        "BYTES": 16,
        "INDEX": 24,
        "REVISION": 32,
        "RESOLVED-GEN": 40,
        "ENTRY-COUNT": 48,
        "PAYLOAD": 56,
    }
    for field, offset in fields.items():
        body = _definition(source, f"_UTUI-SE.{field}")
        if offset:
            assert f"{offset} +" in body
        else:
            assert "+" not in body.split("--", 1)[-1]

    entry_fields = {
        "BYTES": 0,
        "FAMILY": 8,
        "FAMILY-ABI": 16,
        "KEY": 24,
        "PAYLOAD": 32,
    }
    for field, offset in entry_fields.items():
        body = _definition(source, f"_UTUI-SEE.{field}")
        if offset:
            assert f"{offset} +" in body
        else:
            assert "+" not in body.split("--", 1)[-1]

    tabs = struct.pack("<4Q", 40, 3, 1, 1) + b"tabs\0\0\0\0"
    text = struct.pack("<4Q", 40, 4, 1, 2) + b"text\0\0\0\0"
    record = struct.pack(
        "<7Q",
        0x314D455349555455,
        1,
        56 + len(tabs) + len(text),
        17,
        44,
        9,
        2,
    ) + tabs + text
    assert record[:8] == b"UTUISEM1"
    assert len(record) == 136
    assert struct.unpack_from("<Q", record, 16)[0] == len(record)
    assert struct.unpack_from("<Q", record, 24)[0] == 17
    assert struct.unpack_from("<Q", record, 48)[0] == 2
    assert struct.unpack_from("<Q", record, 56 + 24)[0] == 1
    assert struct.unpack_from("<Q", record, 96 + 24)[0] == 2

    semantic_section = source.split(
        "§1c — Per-element renderer-neutral semantic providers", 1
    )[1].split("§1d — Dynamic Sidecar Helpers", 1)[0]
    assert "N.AUX" not in semantic_section
    assert "TSC-AUX" not in semantic_section


def test_semantic_intent_is_fixed_copied_and_revision_fenced() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")

    assert "1 CONSTANT UTUI-SEMANTIC-EVENT-ACTIVATE" in source
    assert "0x3F CONSTANT UTUI-SEMANTIC-MODIFIER-MASK" in source
    assert "64 CONSTANT UTUI-SEMANTIC-INTENT-SIZE" in source
    fields = {
        "FAMILY": 0,
        "ROOT-KEY": 8,
        "CHILD-KEY": 16,
        "KIND": 24,
        "MODIFIERS": 32,
        "REVISION": 40,
        "SCALAR-OFFSET": 48,
        "RESERVED": 56,
    }
    for field, offset in fields.items():
        body = _definition(source, f"_UTUI-SEI.{field}")
        if offset:
            assert f"{offset} +" in body
        else:
            assert "+" not in body.split("--", 1)[-1]

    accessors = {
        "FAMILY@": "( intent -- family )",
        "ROOT-KEY@": "( intent -- key )",
        "CHILD-KEY@": "( intent -- key | 0 )",
        "KIND@": "( intent -- kind )",
        "MODIFIERS@": "( intent -- modifiers )",
        "REVISION@": "( intent -- revision )",
        "SCALAR-OFFSET@": "( intent -- offset )",
    }
    for suffix, stack_effect in accessors.items():
        body = _definition(source, f"UTUI-SEMANTIC-INTENT-{suffix}")
        assert stack_effect in body
    assert "UTUI-SEMANTIC-INTENT-RESERVED@" not in source

    span = _definition(source, "_UTUI-SEMANTIC-EVENT-SPAN?")
    assert "UTUI-SEMANTIC-INTENT-SIZE U<" in span
    assert "UTUI-SEMANTIC-INTENT-SIZE MSPAN-NONWRAPPING?" in span
    assert "UTUI-SEMANTIC-INTENT-SIZE UTUI-STORAGE-DISJOINT?" in span

    validate = _definition(source, "_UTUI-SEMANTIC-EVENT-INTENT-VALID?")
    for field in (
        "FAMILY",
        "ROOT-KEY",
        "KIND",
        "MODIFIERS",
        "REVISION",
        "SCALAR-OFFSET",
        "RESERVED",
    ):
        assert f"_UTUI-SEI.{field}" in validate
    assert "_UTUI-SEI.CHILD-KEY" not in validate
    assert "UTUI-SEMANTIC-EVENT-ACTIVATE <>" in validate
    assert "UTUI-SEMANTIC-MODIFIER-MASK INVERT AND" in validate

    event = _definition(source, "_UTUI-SEMANTIC-EVENT-BODY")
    copied = event.index("UTUI-SEMANTIC-INTENT-SIZE MOVE")
    intent_valid = event.index("_UTUI-SEMANTIC-EVENT-INTENT-VALID?", copied)
    revision = event.index("_UTUI-SEI.REVISION @ <>", intent_valid)
    generation = event.index("_UTUI-SE-EVENT-P-RESOLVED @ <>", revision)
    callback = event.index("_UTUI-SE-EVENT-DISPATCH-XT @ EXECUTE", generation)
    assert copied < intent_valid < revision < generation < callback
    for forbidden in (
        "_UTUI-SEMANTIC-PROVIDER-CALL",
        "_UTUI-SEMANTIC-PAYLOAD-VALID?",
        "_UTUI-SEMANTIC-BINDING-CURRENT?",
        "UTUI-SEMANTIC-CAPTURE",
        " BEGIN ",
        " DO ",
        "RECURSE",
    ):
        assert forbidden not in event
    assert "_UTUI-SB." not in event[callback:]

    dispatch = _definition(source, "UTUI-SEMANTIC-DISPATCH")
    assert "( elem resolved-generation intent available -- status )" in dispatch
    assert "_UTUI-SE-EVENT-ACTIVE @ _UTUI-SE-ACTIVE @ OR" in dispatch
    assert dispatch.index("_UTUI-SE-EVENT-ACTIVE !") < dispatch.index("CATCH")
    assert dispatch.index("CATCH") < dispatch.index("_UTUI-SEMANTIC-EVENT-CLEAR")
    assert "_UTUI-SE-EVENT-INDEX" not in source
    assert "_UTUI-SE-EVENT-BINDING" not in source


def test_mounted_semantic_capture_refuses_capacity_before_any_write() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")
    capture = _definition(source, "_UTUI-SEMANTIC-CAPTURE-BODY")

    measure = capture.index("0 0 _UTUI-SEMANTIC-PROVIDER-CALL")
    total = capture.index("_UTUI-SEMANTIC-TOTAL?", measure)
    capacity = capture.index("_UTUI-SE-TOTAL @ _UTUI-SE-CAP @ U> IF", total)
    disjoint = capture.index("UTUI-STORAGE-DISJOINT?", capacity)
    invalidate = capture.index("0 _UTUI-SE-DST @ _UTUI-SE.MAGIC !", disjoint)
    copy = capture.index("_UTUI-SE.PAYLOAD", invalidate)
    publish = capture.index("_UTUI-SEMANTIC-WRITE-HEADER", copy)
    assert measure < total < capacity < disjoint < invalidate < copy < publish

    assert capture.count("_UTUI-SEMANTIC-BINDING-CURRENT?") == 2
    assert "_UTUI-SE-PAYLOAD-U @ <>" in capture
    validate = capture.index("_UTUI-SEMANTIC-PAYLOAD-VALID?", copy)
    assert copy < validate < publish
    header = _definition(source, "_UTUI-SEMANTIC-WRITE-HEADER")
    assert "_UTUI-SB.SNAPSHOT-XT" not in header
    assert "_UTUI-SB.CONTEXT" not in header
    assert header.index("_UTUI-SE.ENTRY-COUNT !") < header.index(
        "_UTUI-SE.MAGIC !"
    )

    validator = _definition(source, "_UTUI-SEMANTIC-RECORD-VALID-BODY?")
    for field in (
        "MAGIC",
        "ABI",
        "BYTES",
        "INDEX",
        "REVISION",
        "RESOLVED-GEN",
        "ENTRY-COUNT",
    ):
        assert f"_UTUI-SE.{field}" in validator
    assert "_UTUI-SEMANTIC-PAYLOAD-VALID?" in validator
    assert "UTUI-STORAGE-DISJOINT?" in validator

    scan = _definition(source, "_UTUI-SEMANTIC-SCAN-BODY")
    for field in ("BYTES", "FAMILY", "FAMILY-ABI", "KEY"):
        assert f"_UTUI-SEE.{field}" in scan
    assert "UTUI-SEMANTIC-ENTRY-HEADER-SIZE" in scan
    assert "_UTUI-SE-SCAN-PRIOR-KEY @ U> 0=" in scan
    total_check = _definition(source, "_UTUI-SEMANTIC-TOTAL?")
    assert "DUP 7 AND" in total_check
    assert "UTUI-SEMANTIC-ENTRY-HEADER-SIZE U<" in total_check
    assert (
        "DUP _UTUI-RS-SIGNED-MAX UTUI-SEMANTIC-RECORD-HEADER-SIZE - U>"
        in total_check
    )
    assert "IF\n        DROP 0 0 EXIT" in total_check
    assert "DROP 0 UTUI-SEMANTIC-S-INVALID EXIT" in capture

    header = _definition(source, "_UTUI-SEMANTIC-WRITE-HEADER")
    assert " FILL" not in header


def test_mounted_semantics_have_exact_uctx_and_lifecycle_ownership() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")

    assert "32 CONSTANT _UTUI-SEMANTIC-BINDING-SIZE" in source
    assert "111,840 bytes (~109 KiB)" in source
    assert "_UTUI-MAX-ELEMS _UTUI-SEMANTIC-BINDING-SIZE *" in source
    assert "_UTUI-SB.FAMILY" not in source
    binding_fields = {
        "REVISION": 0,
        "SNAPSHOT-XT": 8,
        "EVENT-XT": 16,
        "CONTEXT": 24,
    }
    for field, offset in binding_fields.items():
        body = _definition(source, f"_UTUI-SB.{field}")
        if offset:
            assert f"{offset} +" in body
        else:
            assert "+" not in body.split("--", 1)[-1]
    setter = _definition(source, "_UTUI-SEMANTIC-SET-BODY")
    assert "UIDL-ELEM-INDEX?" in setter
    assert "_UTUI-SIDECAR _UTUI-SC-WPTR@ 0=" in setter
    assert "_UTUI-SE-SET-REVISION @ OVER U> 0=" in setter
    assert "_UTUI-SEMANTIC-BINDING-SIZE 0 FILL" not in setter
    dirty = setter.index("UIDL-DIRTY!")
    first_unpublish = setter.index("0 _UTUI-SE-SET-BINDING @ _UTUI-SB.SNAPSHOT-XT !")
    publish = setter.rindex("_UTUI-SB.SNAPSHOT-XT !")
    assert dirty < first_unpublish < setter.index("_UTUI-SB.REVISION !") < publish
    assert first_unpublish < setter.index("0 _UTUI-SE-SET-BINDING @ _UTUI-SB.EVENT-XT !")
    assert setter.rindex("_UTUI-SB.EVENT-XT !") < publish
    assert setter.rindex("_UTUI-SB.CONTEXT !") < publish
    setter_public = _definition(source, "UTUI-SEMANTIC-SET")
    assert "( revision snapshot-xt event-xt context elem -- status )" in setter_public
    assert "_UTUI-SE-SET-EVENT-XT !" in setter_public
    revision = _definition(source, "_UTUI-SEMANTIC-REVISION-BODY")
    assert "_UTUI-SE-SET-REVISION @ SWAP U> 0=" in revision
    assert "_UTUI-SB.REVISION !" in revision
    assert "_UTUI-SB.SNAPSHOT-XT @ 0=" in revision
    assert "UIDL-DIRTY!" in revision
    assert revision.index("UIDL-DIRTY!") < revision.index("_UTUI-SB.REVISION !")
    revision_public = _definition(source, "UTUI-SEMANTIC-REVISION!")
    assert "_UTUI-SEMANTIC-REVISION-CLEAR" in revision_public
    assert "_UTUI-SEMANTIC-SCRATCH-CLEAR" not in revision_public
    assert "_UTUI-SE-ACTIVE @ IF" not in revision_public
    assert "_UTUI-SE-ACTIVE @ IF" not in _definition(
        source, "UTUI-SEMANTIC-SET"
    )

    semantic_clear = _definition(source, "_UTUI-SEMANTIC-CLEAR-BODY")
    assert "_UTUI-SEMANTIC-UNBIND-BINDING" in semantic_clear
    assert semantic_clear.index("UIDL-DIRTY!") < semantic_clear.index(
        "_UTUI-SEMANTIC-UNBIND-BINDING"
    )
    assert "_UTUI-SEMANTIC-BINDING-SIZE 0 FILL" not in semantic_clear
    assert "_UTUI-SE-ACTIVE @ IF" not in _definition(
        source, "UTUI-SEMANTIC-CLEAR"
    )
    assert "_UTUI-SE-ACTIVE @ _UTUI-SE-EVENT-ACTIVE @ OR IF" in (
        _definition(source, "UTUI-SEMANTIC-CAPTURE")
    )

    assert "_UTUI-SEMANTIC-CLEAR-ALL" in _definition(source, "UTUI-LOAD")
    detach = _definition(source, "UTUI-DETACH")
    assert "_UTUI-SEMANTIC-CLEAR-ALL" in detach
    assert detach.index("_UTUI-SEMANTIC-CLEAR-ALL") < detach.index(
        "_UTUI-DEMATERIALIZE"
    )
    assert "_UTUI-SEMANTIC-CLEAR-ELEM" in _definition(
        source, "UTUI-ADD-ELEM"
    )
    add = _definition(source, "UTUI-ADD-ELEM")
    remove = _definition(source, "UTUI-REMOVE-ELEM")
    assert "_UTUI-SEMANTIC-RESOLVED-BOUNDARY" in add
    assert "_UTUI-SEMANTIC-CLEAR-SUBTREE" in remove
    assert "_UTUI-SEMANTIC-RESOLVED-BOUNDARY" in remove
    clear_subtree = _definition(source, "_UTUI-SEMANTIC-CLEAR-SUBTREE")
    assert "_UTUI-SEMANTIC-CLEAR-ELEM" in clear_subtree
    assert "UIDL-FIRST-CHILD" in clear_subtree
    assert "UIDL-NEXT-SIB" in clear_subtree
    assert "RECURSE" in clear_subtree
    assert "_UTUI-SEMANTIC-UNBIND-BINDING" in _definition(
        source, "UTUI-WIDGET-SET"
    )
    quiesce = _definition(source, "UTUI-QUIESCE")
    assert quiesce.count("_UTUI-SEMANTIC-UNBIND-ALL") == 2
    relayout = _definition(source, "UTUI-RELAYOUT")
    assert "_UTUI-SEMANTIC-RESOLVED-BOUNDARY" in relayout
    assert "_UTUI-SEMANTIC-CLEAR-ALL" not in relayout
    tab_keys = _definition(source, "_UTUI-H-TABS")
    tab_mouse = _definition(source, "UTUI-DISPATCH-MOUSE")
    tab_select = _definition(source, "UTUI-TAB-SELECT")
    assert tab_keys.count("_UTUI-SEMANTIC-RESOLVED-BOUNDARY") == 2
    assert "_UTUI-SEMANTIC-RESOLVED-BOUNDARY" in tab_mouse
    assert "_UTUI-SEMANTIC-RESOLVED-BOUNDARY" in tab_select
    assert "_UTUI-SEMANTIC-RESOLVED-BOUNDARY" in _definition(
        source, "_UTUI-MENU-OPEN!"
    )
    assert "_UTUI-SEMANTIC-RESOLVED-BOUNDARY" in _definition(
        source, "_UTUI-MENU-CLOSE"
    )
    assert "_UTUI-SEMANTIC-RESOLVED-BOUNDARY" in _definition(
        source, "_UTUI-SHOW-ELEM"
    )
    assert "_UTUI-SEMANTIC-RESOLVED-BOUNDARY" in _definition(
        source, "_UTUI-HIDE-ELEM"
    )

    save = _definition(source, "UCTX-SAVE")
    restore = _definition(source, "UCTX-RESTORE")
    identity = save.index("_UTUI-SEMANTIC-BINDINGS @ _UCP-DST @ <> IF")
    clear = save.index("_UTUI-SEMANTIC-BINDINGS-SIZE 0 FILL", identity)
    assert identity < clear
    assert "_UTUI-SEMANTIC-BINDINGS-SIZE CMOVE" not in save
    assert "DUP _UCTX-O-SEMANTICS + _UTUI-SEMANTIC-BINDINGS !" in restore
    invalidated = restore.index("_UTUI-SE-RESTORE-INVALIDATED !")
    first_restore_copy = restore.index("_UCTX-NVAR 0 DO")
    assert invalidated < first_restore_copy
    binding_current = _definition(source, "_UTUI-SEMANTIC-BINDING-CURRENT?")
    assert binding_current.index("_UTUI-SE-RESTORE-INVALIDATED @") < (
        binding_current.index("_UTUI-DOC-LOADED @")
    )
    assert "_UTUI-SEMANTIC-SCRATCH-CLEAR-IDLE" not in source
    assert "_UTUI-SB.EVENT-XT @ _UTUI-SE-SNAPSHOT-EVENT-XT @ = AND" in (
        binding_current
    )
    assert "_UTUI-SEMANTIC-BINDINGS-SIZE" in _definition(
        source, "_UTUI-STORAGE-DISJOINT-BODY?"
    )
    unbind = _definition(source, "_UTUI-SEMANTIC-UNBIND-BINDING")
    assert unbind.index("_UTUI-SB.SNAPSHOT-XT !") < unbind.index(
        "_UTUI-SB.EVENT-XT !"
    )
    assert unbind.index("_UTUI-SB.EVENT-XT !") < unbind.index(
        "_UTUI-SB.CONTEXT !"
    )
    assert (
        "_UCTX-O-SEMANTICS _UTUI-SEMANTIC-BINDINGS-SIZE +  "
        "CONSTANT UCTX-TOTAL"
    ) in source
    assert 103_648 + 256 * 32 == 111_840

    touch = _definition(source, "_UTUI-SEMANTIC-TOUCH-BODY")
    assert "1+ DUP 0=" in touch
    assert touch.index("UIDL-DIRTY!") < touch.index("_UTUI-SB.REVISION !")
    assert "_UTUI-SB.SNAPSHOT-XT @ 0=" in touch


def test_guarded_mounted_capture_uses_the_coherent_resolved_observation() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")

    assert "' UTUI-SEMANTIC-SET CONSTANT _utui-semantic-set-xt" in source
    assert (
        "' UTUI-SEMANTIC-REVISION! CONSTANT _utui-semantic-revision-s-xt"
        in source
    )
    assert "' UTUI-SEMANTIC-TOUCH CONSTANT _utui-semantic-touch-xt" in source
    assert (
        "' UTUI-SEMANTIC-DISPATCH CONSTANT _utui-semantic-dispatch-xt"
        in source
    )
    assert "' UTUI-SEMANTIC-CAPTURE CONSTANT _utui-semantic-capture-xt" in source
    assert (
        ": UTUI-SEMANTIC-SET   _utui-semantic-set-xt   _utui-guard WITH-GUARD ;"
        in source
    )
    revision = _last_definition(source, "UTUI-SEMANTIC-REVISION!")
    assert "_utui-semantic-revision-s-xt _utui-guard WITH-GUARD" in revision
    touch = _last_definition(source, "UTUI-SEMANTIC-TOUCH")
    assert "_utui-semantic-touch-xt _utui-guard WITH-GUARD" in touch
    dispatch = _last_definition(source, "UTUI-SEMANTIC-DISPATCH")
    assert "_utui-semantic-dispatch-xt EXECUTE" in dispatch
    assert "WITH-GUARD" not in dispatch
    assert "UTUI-RESOLVED-OBSERVE" not in dispatch
    capture = _last_definition(source, "UTUI-SEMANTIC-CAPTURE")
    size = _last_definition(source, "UTUI-SEMANTIC-SIZE")
    assert "_utui-semantic-capture-xt UTUI-RESOLVED-OBSERVE" in capture
    assert "_utui-semantic-size-xt UTUI-RESOLVED-OBSERVE" in size
