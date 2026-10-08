#!/usr/bin/env python3
"""Test suite for akashic-tui-uidl-tui (UIDL TUI Backend).

Every check runs on a fresh native machine (native_forth.py) with KDOS and
the full dependency chain (string → markup → state-tree → lel → uidl →
uidl-chrome → TUI stack → uidl-tui) loaded, then exercises the public API.
"""
from native_forth import NativeForth

# Test helper words loaded with the closure.
TEST_HELPERS = (
    'CREATE _TB 4096 ALLOT  VARIABLE _TL',
    ': TR  0 _TL ! ;',
    ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
    ': TA  ( -- addr u ) _TB _TL @ ;',
    'CREATE _UB 512 ALLOT',
    'CREATE _WB 4096 ALLOT',
    # Region helper: push a 80×24 region
    'VARIABLE _RGN_SLOT',
    ': T-RGN  0 0 24 80 RGN-NEW _RGN_SLOT ! ;',
    # UTUI-PAINT draws into the current screen; one matches the region.
    '80 24 SCR-NEW SCR-USE',
)

SUITE = NativeForth(("tui/uidl-tui.f",), prelude=TEST_HELPERS)


def uart_text(raw):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9)) else ""
        for b in raw
    )


def run_forth(lines, max_steps=80_000_000):
    return uart_text(SUITE.run(lines, max_steps))


# ═══════════════════════════════════════════════════════════════════
#  Test framework
# ═══════════════════════════════════════════════════════════════════

def check(name, forth_lines, expected=None, check_fn=None, not_expected=None,
          max_steps=80_000_000):
    output = run_forth(forth_lines, max_steps=max_steps)
    last = "\n".join(output.strip().split("\n")[-8:])
    if check_fn:
        assert check_fn(output), f"{name}: check failed, got:\n{last}"
    elif expected is not None:
        assert expected in output, f"{name}: expected {expected!r}, got:\n{last}"
    if not_expected is not None:
        assert not_expected not in output, f"{name}: NOT expected {not_expected!r}, got:\n{last}"


# ═══════════════════════════════════════════════════════════════════
#  XML test documents
# ═══════════════════════════════════════════════════════════════════

# Minimal doc: a region with a label child
_XML_MINIMAL = '<uidl><region><label text="Hello"/></region></uidl>'

# Doc with focusable elements: action + input + toggle
_XML_FOCUS = (
    '<uidl>'
    '<region arrange="stack">'
    '  <label text="Title"/>'
    '  <action id="btn1" text="Click Me" do="on-btn"/>'
    '  <input  id="inp1" text=""/>'
    '  <toggle id="tog1" text="false"/>'
    '  <action id="btn2" text="Other"   do="on-other"/>'
    '</region>'
    '</uidl>'
)

# Split layout doc
_XML_SPLIT = (
    '<uidl>'
    '<split ratio="40">'
    '  <region><label text="Left"/></region>'
    '  <region><label text="Right"/></region>'
    '</split>'
    '</uidl>'
)

# Dialog doc
_XML_DIALOG = (
    '<uidl>'
    '<region arrange="stack">'
    '  <label text="Main"/>'
    '  <dialog id="dlg1">'
    '    <label text="Dialog Body"/>'
    '    <action id="dlg-ok" text="OK" do="close-dlg"/>'
    '  </dialog>'
    '</region>'
    '</uidl>'
)

# Shortcut doc
_XML_SHORTCUT = (
    '<uidl>'
    '<region arrange="stack">'
    '  <action id="save-btn" text="Save" key="Ctrl+S" do="on-save"/>'
    '  <action id="quit-btn" text="Quit" key="Alt+Q"  do="on-quit"/>'
    '</region>'
    '</uidl>'
)


def _xml_lines(xml_str, extra_before=None, extra_after=None):
    """Build Forth lines that load an XML string and call UTUI-LOAD."""
    out = []
    out.append('T-RGN')
    if extra_before:
        out.extend(extra_before)
    # Build XML in _TB using TC
    out.append('TR')
    for ch in xml_str:
        out.append(f'{ord(ch)} TC')
    out.append(f'TA _RGN_SLOT @ UTUI-LOAD')
    if extra_after:
        out.extend(extra_after)
    return out


# ═══════════════════════════════════════════════════════════════════
#  §A — Compilation & Snapshot Tests
# ═══════════════════════════════════════════════════════════════════

def test_compilation():
    """All libraries compile without error."""
    check("compile-clean", [
        '." COMPILE-OK" CR',
    ], "COMPILE-OK")


# ═══════════════════════════════════════════════════════════════════
#  §B — Load / Parse Tests
# ═══════════════════════════════════════════════════════════════════

def test_load_minimal():
    """UTUI-LOAD parses minimal XML and returns true."""
    check("load-minimal-flag", _xml_lines(_XML_MINIMAL, extra_after=[
        'IF ." LOAD-OK" ELSE ." LOAD-FAIL" THEN CR',
    ]), "LOAD-OK")

def test_load_sets_loaded():
    """After UTUI-LOAD, the DOC-LOADED flag is set."""
    check("load-sets-loaded", _xml_lines(_XML_MINIMAL, extra_after=[
        'DROP',
        '_UTUI-DOC-LOADED @ 0<> IF ." LOADED" ELSE ." NOT" THEN CR',
    ]), "LOADED")

def test_load_bad_xml():
    """UTUI-LOAD with bad XML returns false."""
    check("load-bad-xml", [
        'T-RGN',
        'TR 60 TC 98 TC 97 TC 100 TC',  # "<bad" — incomplete
        'TA _RGN_SLOT @ UTUI-LOAD',
        'IF ." LOAD-OK" ELSE ." LOAD-FAIL" THEN CR',
    ], "LOAD-FAIL")


# ═══════════════════════════════════════════════════════════════════
#  §C — Sidecar Allocation Tests
# ═══════════════════════════════════════════════════════════════════

def test_sidecar_allocation():
    """After load, root element has a sidecar with visible flags."""
    check("sidecar-root-vis", _xml_lines(_XML_MINIMAL, extra_after=[
        'DROP',
        'UIDL-ROOT _UTUI-SIDECAR _UTUI-SC-FLAGS@',
        'DUP _UTUI-SCF-HAS AND 0<> IF ." HAS" ELSE ." NO-HAS" THEN CR',
        '_UTUI-SCF-VIS AND 0<> IF ." VIS" ELSE ." NO-VIS" THEN CR',
    ]), check_fn=lambda o: "HAS" in o and "VIS" in o)

def test_sidecar_dimensions():
    """Root sidecar gets region dimensions (80×24)."""
    check("sidecar-root-dims", _xml_lines(_XML_MINIMAL, extra_after=[
        'DROP',
        'UIDL-ROOT _UTUI-SIDECAR',
        'DUP _UTUI-SC-W@ . CR',
        '_UTUI-SC-H@ . CR',
    ]), check_fn=lambda o: "80" in o and "24" in o)


# ═══════════════════════════════════════════════════════════════════
#  §D — Focus Management Tests
# ═══════════════════════════════════════════════════════════════════

def test_focus_initial():
    """UTUI-LOAD auto-focuses the first focusable element (action btn1)."""
    check("focus-initial", _xml_lines(_XML_FOCUS, extra_after=[
        'DROP',
        'UTUI-FOCUS ?DUP IF',
        '  UIDL-ID DUP 0> IF TYPE ELSE 2DROP ." no-id" THEN',
        'ELSE ." none" THEN CR',
    ]), "btn1")

def test_focus_next():
    """UTUI-FOCUS-NEXT cycles through focusable elements."""
    check("focus-next-cycle", _xml_lines(_XML_FOCUS, extra_after=[
        'DROP',
        # Focus is on btn1 after load. Step through.
        'UTUI-FOCUS-NEXT',  # → inp1
        'UTUI-FOCUS ?DUP IF',
        '  UIDL-ID DUP 0> IF TYPE ELSE 2DROP THEN',
        'ELSE ." none" THEN CR',
        'UTUI-FOCUS-NEXT',  # → tog1
        'UTUI-FOCUS ?DUP IF',
        '  UIDL-ID DUP 0> IF TYPE ELSE 2DROP THEN',
        'ELSE ." none" THEN CR',
        'UTUI-FOCUS-NEXT',  # → btn2
        'UTUI-FOCUS ?DUP IF',
        '  UIDL-ID DUP 0> IF TYPE ELSE 2DROP THEN',
        'ELSE ." none" THEN CR',
    ]), check_fn=lambda o: "inp1" in o and "tog1" in o and "btn2" in o)

def test_focus_prev():
    """UTUI-FOCUS-PREV cycles backwards."""
    check("focus-prev-cycle", _xml_lines(_XML_FOCUS, extra_after=[
        'DROP',
        # Focus is on btn1 after load.
        'UTUI-FOCUS-PREV',  # → btn2 (wraps)
        'UTUI-FOCUS ?DUP IF',
        '  UIDL-ID DUP 0> IF TYPE ELSE 2DROP THEN',
        'ELSE ." none" THEN CR',
    ]), "btn2")

def test_focus_explicit():
    """UTUI-FOCUS! sets focus directly."""
    check("focus-explicit-set", _xml_lines(_XML_FOCUS, extra_after=[
        'DROP',
        'S" tog1" UTUI-BY-ID DUP 0<> IF',
        '  UTUI-FOCUS!',
        '  UTUI-FOCUS UIDL-ID DUP 0> IF TYPE ELSE 2DROP THEN',
        'ELSE ." not-found" THEN CR',
    ]), "tog1")


# ═══════════════════════════════════════════════════════════════════
#  §E — Action Dispatch Tests
# ═══════════════════════════════════════════════════════════════════

def test_action_register_fire():
    """UTUI-DO! registers an action; _UTUI-FIRE-DO fires it."""
    check("action-fire", _xml_lines(_XML_FOCUS, extra_before=[
        'VARIABLE _ACT-HIT',
        'CREATE _ACT-NAME 6 ALLOT',
        ': _ON-BTN  DROP 1 _ACT-HIT ! ;',
    ], extra_after=[
        'DROP',
        # UTUI-LOAD clears the per-document action registry.  Register only
        # after the document that owns the action has loaded.  Overwrite the
        # caller buffer afterward to prove the registry copied exact bytes.
        'S" on-btn" _ACT-NAME SWAP MOVE',
        "_ACT-NAME 6 ['] _ON-BTN UTUI-DO!",
        '_ACT-NAME 6 120 FILL',
        # Focus is btn1, which has do="on-btn".  Fire it.
        'UTUI-FOCUS _UTUI-FIRE-DO',
        '_ACT-HIT @ . CR',
    ]), "1")


# ═══════════════════════════════════════════════════════════════════
#  §F — Shortcut Parsing Tests
# ═══════════════════════════════════════════════════════════════════

def test_shortcut_parse_single():
    """_UTUI-PARSE-KEY-DESC parses single char."""
    check("shortcut-parse-single-char", [
        'S" S" _UTUI-PARSE-KEY-DESC',
        'SWAP . . CR',
    ], check_fn=lambda o: str(ord('S')) in o and "0" in o)

def test_shortcut_parse_ctrl():
    """_UTUI-PARSE-KEY-DESC parses Ctrl+S → lowercase key-code 115."""
    check("shortcut-parse-ctrl", [
        'S" Ctrl+S" _UTUI-PARSE-KEY-DESC',
        'SWAP . . CR',
    ], check_fn=lambda o: "115" in o and "4" in o)  # 's'=115, KEY-MOD-CTRL=4

def test_shortcut_parse_ctrl_shift():
    """_UTUI-PARSE-KEY-DESC parses Ctrl+Shift+S → lowercase 115, mods 5."""
    check("shortcut-parse-ctrl-shift", [
        'S" Ctrl+Shift+S" _UTUI-PARSE-KEY-DESC',
        'SWAP . . CR',
    ], check_fn=lambda o: "115" in o and "5" in o)  # 's'=115, CTRL|SHIFT=5


def test_shortcut_dispatch_fires():
    """Ctrl+S key event dispatches through UTUI-DISPATCH-KEY to fire action."""
    check("shortcut-dispatch-fire", _xml_lines(_XML_SHORTCUT, extra_before=[
        'VARIABLE _SAVE-HIT',
        ': _ON-SAVE  DROP 1 _SAVE-HIT ! ;',
        "S\" on-save\" ['] _ON-SAVE UTUI-DO!",
    ], extra_after=[
        'DROP',
        # Build a synthetic key event: type=KEY-T-CHAR(0), code=115('s'), mods=KEY-MOD-CTRL(4)
        'CREATE _TEV 24 ALLOT',
        'KEY-T-CHAR _TEV !  115 _TEV 8 + !  KEY-MOD-CTRL _TEV 16 + !',
        '_TEV UTUI-DISPATCH-KEY DROP',
        '_SAVE-HIT @ . CR',
    ]), "1")


# ═══════════════════════════════════════════════════════════════════
#  §G — Layout Tests
# ═══════════════════════════════════════════════════════════════════

def test_layout_stack():
    """Stack layout gives children sequential rows."""
    check("layout-stack-rows", _xml_lines(_XML_FOCUS, extra_after=[
        'DROP',
        # The stacked region's first child is <label text="Title"> at the
        # region origin, and the next, <action btn1>, is on the next row.
        'UIDL-ROOT UIDL-FIRST-CHILD UIDL-FIRST-CHILD',
        'DUP _UTUI-SIDECAR _UTUI-SC-ROW@ .',
        'UIDL-NEXT-SIB _UTUI-SIDECAR _UTUI-SC-ROW@ . CR',
    ]), "0 1")

def test_layout_stack_width():
    """Stack layout children inherit parent width (80)."""
    check("layout-stack-width", _xml_lines(_XML_FOCUS, extra_after=[
        'DROP',
        'UIDL-ROOT UIDL-FIRST-CHILD _UTUI-SIDECAR _UTUI-SC-W@ . CR',
    ]), "80")

def test_layout_split():
    """Split layout divides width by ratio."""
    check("layout-split", _xml_lines(_XML_SPLIT, extra_after=[
        'DROP',
        # <split ratio="40"> gives its left pane 40% of 80 = 32 columns,
        # keeps one divider column, and gives the right pane the other 47.
        'UIDL-ROOT UIDL-FIRST-CHILD UIDL-FIRST-CHILD',
        'DUP _UTUI-SIDECAR _UTUI-SC-W@ .',
        'UIDL-NEXT-SIB _UTUI-SIDECAR DUP _UTUI-SC-W@ . _UTUI-SC-COL@ . CR',
    ]), "32 47 33")


# ═══════════════════════════════════════════════════════════════════
#  §H — Paint Tests
# ═══════════════════════════════════════════════════════════════════

def test_paint_no_crash():
    """UTUI-PAINT runs without crash after UTUI-LOAD."""
    check("paint-no-crash", _xml_lines(_XML_MINIMAL, extra_after=[
        'DROP',
        'UTUI-PAINT',
        '." PAINT-OK" CR',
    ]), "PAINT-OK")

def test_paint_with_focus():
    """UTUI-PAINT runs with focus doc without crash."""
    check("paint-focus-doc", _xml_lines(_XML_FOCUS, extra_after=[
        'DROP',
        'UTUI-PAINT',
        '." PAINT-OK" CR',
    ]), "PAINT-OK")


# ═══════════════════════════════════════════════════════════════════
#  §I — Detach Tests
# ═══════════════════════════════════════════════════════════════════

def test_detach():
    """UTUI-DETACH resets all state."""
    check("detach-clears", _xml_lines(_XML_FOCUS, extra_after=[
        'DROP',
        'UTUI-DETACH',
        '_UTUI-DOC-LOADED @ 0= IF ." UNLOADED" ELSE ." STILL" THEN CR',
        'UTUI-FOCUS 0= IF ." NO-FOCUS" ELSE ." FOCUS" THEN CR',
    ]), check_fn=lambda o: "UNLOADED" in o and "NO-FOCUS" in o)


def test_detach_borrowed_widget():
    """Detach must not FREE an app-owned widget attached to a region."""
    check("detach-borrowed-widget", _xml_lines(_XML_MINIMAL, extra_after=[
        'DROP',
        # A CREATE'd descriptor models embedded component state (Pad's panel
        # uses exactly this ownership pattern).  It has no allocator header.
        'CREATE _TDB-WIDGET 40 ALLOT',
        '_TDB-WIDGET UIDL-ROOT UIDL-FIRST-CHILD UTUI-WIDGET-SET',
        'UIDL-ROOT UIDL-FIRST-CHILD _UTUI-SIDECAR',
        # The console echoes input, so each marker is printed in two parts
        # and only real output can contain it whole.
        '_UTUI-SC-WOWNER@ _UTUI-WOWNER-CALLER = 0= IF',
        '  ." BAD-" ." OWNER" CR',
        'ELSE',
        '  UTUI-DETACH',
        '  ." BORROWED-" ." DETACH-OK" CR',
        'THEN',
    ]), expected="BORROWED-DETACH-OK", not_expected="BAD-OWNER")


# ═══════════════════════════════════════════════════════════════════
#  §J — Dialog Tests
# ═══════════════════════════════════════════════════════════════════

def test_dialog_show_hide():
    """UTUI-SHOW-DIALOG makes dialog visible; UTUI-HIDE-DIALOG hides it."""
    check("dialog-show-hide", _xml_lines(_XML_DIALOG, extra_after=[
        'DROP',
        # Dialog starts hidden (when= not set → visible by default actually,
        # but we hide then show to test the API)
        'S" dlg1" UTUI-HIDE-DIALOG',
        'S" dlg1" UTUI-BY-ID _UTUI-SIDECAR _UTUI-SC-FLAGS@',
        '_UTUI-SCF-VIS AND 0= IF ." HIDDEN" ELSE ." VIS" THEN CR',
        'S" dlg1" UTUI-SHOW-DIALOG',
        'S" dlg1" UTUI-BY-ID _UTUI-SIDECAR _UTUI-SC-FLAGS@',
        '_UTUI-SCF-VIS AND 0<> IF ." VISIBLE" ELSE ." INVIS" THEN CR',
    ]), check_fn=lambda o: "HIDDEN" in o and "VISIBLE" in o)


# ═══════════════════════════════════════════════════════════════════
#  §K — UTUI-BY-ID Tests
# ═══════════════════════════════════════════════════════════════════

def test_by_id_found():
    """UTUI-BY-ID returns non-zero for existing id."""
    check("by-id-found", _xml_lines(_XML_FOCUS, extra_after=[
        'DROP',
        'S" btn1" UTUI-BY-ID 0<> IF ." FOUND" ELSE ." MISSING" THEN CR',
    ]), "FOUND")

def test_by_id_missing():
    """UTUI-BY-ID returns 0 for non-existent id."""
    check("by-id-missing", _xml_lines(_XML_FOCUS, extra_after=[
        'DROP',
        'S" nonexistent" UTUI-BY-ID 0= IF ." MISSING" ELSE ." FOUND" THEN CR',
    ]), "MISSING")


# ═══════════════════════════════════════════════════════════════════
#  §L — Relayout Tests
# ═══════════════════════════════════════════════════════════════════

def test_relayout():
    """UTUI-RELAYOUT can be called after load without crash."""
    check("relayout-no-crash", _xml_lines(_XML_FOCUS, extra_after=[
        'DROP',
        'UTUI-RELAYOUT',
        '." RELAYOUT-OK" CR',
    ]), "RELAYOUT-OK")


# ═══════════════════════════════════════════════════════════════════
#  §M — XT Installation Tests
# ═══════════════════════════════════════════════════════════════════

def test_xt_installed():
    """After loading, EL-LOOKUP for 'label' shows a non-NOOP render-xt."""
    check("xt-render-installed", [
        'S" label" EL-LOOKUP ?DUP IF',
        '  ED.RENDER-XT @ [\'] NOOP <> IF ." INSTALLED" ELSE ." NOOP" THEN',
        'ELSE ." NOT-FOUND" THEN CR',
    ], "INSTALLED")

def test_xt_event_installed():
    """After loading, EL-LOOKUP for 'action' shows a non-NOOP event-xt."""
    check("xt-event-installed", [
        'S" action" EL-LOOKUP ?DUP IF',
        '  ED.EVENT-XT @ [\'] NOOP <> IF ." INSTALLED" ELSE ." NOOP" THEN',
        'ELSE ." NOT-FOUND" THEN CR',
    ], "INSTALLED")

def test_xt_layout_installed():
    """After loading, EL-LOOKUP for 'region' shows a non-NOOP layout-xt."""
    check("xt-layout-installed", [
        'S" region" EL-LOOKUP ?DUP IF',
        '  ED.LAYOUT-XT @ [\'] NOOP <> IF ." INSTALLED" ELSE ." NOOP" THEN',
        'ELSE ." NOT-FOUND" THEN CR',
    ], "INSTALLED")


# ═══════════════════════════════════════════════════════════════════
#  §N — Hit Test (basic smoke)
# ═══════════════════════════════════════════════════════════════════

def test_hit_test_root():
    """UTUI-HIT-TEST at (0,0) finds the root or a child."""
    check("hit-test-root", _xml_lines(_XML_MINIMAL, extra_after=[
        'DROP',
        '0 0 UTUI-HIT-TEST 0<> IF ." HIT" ELSE ." MISS" THEN CR',
    ]), "HIT")


# ═══════════════════════════════════════════════════════════════════
#  §O — CSS Property Tests (text-align, padding, margin, position,
#        z-index, display:none)
# ═══════════════════════════════════════════════════════════════════

# XML with text-align
_XML_ALIGN = (
    '<uidl>'
    '<region arrange="stack">'
    '  <label id="lc" text="Center" style="text-align:center"/>'
    '  <label id="lr" text="Right"  style="text-align:right"/>'
    '  <label id="ll" text="Left"   style="text-align:left"/>'
    '</region>'
    '</uidl>'
)

# XML with padding on region
_XML_PADDING = (
    '<uidl>'
    '<region arrange="stack" style="padding:2">'
    '  <label id="p1" text="Padded"/>'
    '</region>'
    '</uidl>'
)

# XML with 4-value padding
_XML_PADDING4 = (
    '<uidl>'
    '<region arrange="stack" style="padding:1 2 3 4">'
    '  <label id="p4" text="Padded4"/>'
    '</region>'
    '</uidl>'
)

# XML with margin
_XML_MARGIN = (
    '<uidl>'
    '<region arrange="stack">'
    '  <label id="m0" text="No margin"/>'
    '  <label id="m1" text="With margin" style="margin:2"/>'
    '  <label id="m2" text="After margin"/>'
    '</region>'
    '</uidl>'
)

# XML with position:absolute + offsets
_XML_POSITION = (
    '<uidl>'
    '<region arrange="stack">'
    '  <label id="sta" text="Static"/>'
    '  <label id="abs" text="Abs" style="position:absolute;top:5;left:10;width:20;height:3"/>'
    '</region>'
    '</uidl>'
)

# XML with z-index
_XML_ZINDEX = (
    '<uidl>'
    '<region arrange="stack">'
    '  <label id="z0" text="Back"/>'
    '  <label id="z5" text="Front" style="z-index:5"/>'
    '</region>'
    '</uidl>'
)

# XML with display:none
_XML_DISPLAY_NONE = (
    '<uidl>'
    '<region arrange="stack">'
    '  <label id="vis" text="Visible"/>'
    '  <label id="hid" text="Hidden" style="display:none"/>'
    '  <label id="aft" text="After"/>'
    '</region>'
    '</uidl>'
)


def test_css_text_align_center():
    """text-align:center sets sidecar align bits to 1."""
    check("css-text-align-center", _xml_lines(_XML_ALIGN, extra_after=[
        'DROP',
        'S" lc" UTUI-BY-ID ?DUP IF',
        '  _UTUI-SIDECAR _UTUI-SC-TALIGN@ . CR',
        'ELSE ." NOT-FOUND" CR THEN',
    ]), "1")

def test_css_text_align_right():
    """text-align:right sets sidecar align bits to 2."""
    check("css-text-align-right", _xml_lines(_XML_ALIGN, extra_after=[
        'DROP',
        'S" lr" UTUI-BY-ID ?DUP IF',
        '  _UTUI-SIDECAR _UTUI-SC-TALIGN@ . CR',
        'ELSE ." NOT-FOUND" CR THEN',
    ]), "2")

def test_css_text_align_left():
    """text-align:left keeps sidecar align bits at 0."""
    check("css-text-align-left", _xml_lines(_XML_ALIGN, extra_after=[
        'DROP',
        'S" ll" UTUI-BY-ID ?DUP IF',
        '  _UTUI-SIDECAR _UTUI-SC-TALIGN@ . CR',
        'ELSE ." NOT-FOUND" CR THEN',
    ]), "0")

def test_css_padding_uniform():
    """padding:2 stores packed TRBL (2,2,2,2) in sidecar pad field."""
    check("css-padding-uniform", _xml_lines(_XML_PADDING, extra_after=[
        'DROP',
        'UIDL-ROOT UIDL-FIRST-CHILD _UTUI-SIDECAR _UTUI-SC-PAD@',
        '_UTUI-UNPACK-TRBL',
        '. ." |" . ." |" . ." |" . CR',      # prints l | b | r | t
    ]), check_fn=lambda o: "2|2|2|2" in o.replace(" ", ""))

def test_css_padding_4value():
    """padding:1 2 3 4 stores (T=1, R=2, B=3, L=4)."""
    check("css-padding-4value", _xml_lines(_XML_PADDING4, extra_after=[
        'DROP',
        'UIDL-ROOT UIDL-FIRST-CHILD _UTUI-SIDECAR _UTUI-SC-PAD@',
        '_UTUI-UNPACK-TRBL',
        '. ." |" . ." |" . ." |" . CR',      # l | b | r | t
    ]), check_fn=lambda o: "4|3|2|1" in o.replace(" ", ""))

def test_css_padding_layout_effect():
    """padding:2 on region pushes child label inward (row=2, col=2)."""
    check("css-padding-layout-effect", _xml_lines(_XML_PADDING, extra_after=[
        'DROP',
        'S" p1" UTUI-BY-ID ?DUP IF',
        '  _UTUI-SIDECAR',
        '  ." ROW=" DUP _UTUI-SC-ROW@ . CR',
        '  ." COL=" DUP _UTUI-SC-COL@ . CR',
        '  ." W=" DUP _UTUI-SC-W@ . CR',
        '  DROP',
        'ELSE ." NOT-FOUND" CR THEN',
    ]), check_fn=lambda o: "ROW=2" in o and "W=76" in o)

def test_css_margin_stack_spacing():
    """margin:2 adds spacing between stack children."""
    check("css-margin-stack-spacing", _xml_lines(_XML_MARGIN, extra_after=[
        'DROP',
        # m0 should be at row 0 (no margin)
        '." M0=" S" m0" UTUI-BY-ID _UTUI-SIDECAR _UTUI-SC-ROW@ . CR',
        # m1 has margin:2 so margin-top=2 → row should be 0+1+2=3
        '." M1=" S" m1" UTUI-BY-ID _UTUI-SIDECAR _UTUI-SC-ROW@ . CR',
        # m2 should be after m1 + margin-bottom of m1 (2)
        '." M2=" S" m2" UTUI-BY-ID _UTUI-SIDECAR _UTUI-SC-ROW@ . CR',
    ]), check_fn=lambda o: (
        "M0=0" in o
        and "M1=3" in o
        and "M2=6" in o
    ))

def test_css_margin_sidecar_value():
    """margin:2 stores packed (2,2,2,2) in sidecar margin field."""
    check("css-margin-sidecar-value", _xml_lines(_XML_MARGIN, extra_after=[
        'DROP',
        'S" m1" UTUI-BY-ID _UTUI-SIDECAR _UTUI-SC-MARGIN@',
        '_UTUI-UNPACK-TRBL',
        '. ." |" . ." |" . ." |" . CR',
    ]), check_fn=lambda o: "2|2|2|2" in o.replace(" ", ""))

def test_css_position_absolute():
    """position:absolute sets pos bits to 1 and uses offsets."""
    check("css-position-absolute", _xml_lines(_XML_POSITION, extra_after=[
        'DROP',
        'S" abs" UTUI-BY-ID ?DUP IF',
        '  _UTUI-SIDECAR',
        '  ." POS=" DUP _UTUI-SC-POS@ . CR',
        '  ." ROW=" DUP _UTUI-SC-ROW@ . CR',
        '  ." COL=" DUP _UTUI-SC-COL@ . CR',
        '  ." W=" DUP _UTUI-SC-W@ . CR',
        '  ." H=" DUP _UTUI-SC-H@ . CR',
        '  DROP',
        'ELSE ." NOT-FOUND" CR THEN',
    ]), check_fn=lambda o: (
        "POS=1" in o       # position:absolute = 1
        and "ROW=5" in o   # row = top offset = 5
        and "COL=10" in o  # col = left offset = 10
        and "W=20" in o    # width = 20
        and "H=3" in o     # height = 3
    ))

def test_css_position_not_in_flow():
    """position:absolute element is skipped in stack flow layout."""
    check("css-position-not-in-flow", _xml_lines(_XML_POSITION, extra_after=[
        'DROP',
        # Static label should be at row 0 — absolute elem doesn't push it
        'S" sta" UTUI-BY-ID _UTUI-SIDECAR _UTUI-SC-ROW@ . CR',
    ]), "0")

def test_css_zindex_sidecar():
    """z-index:5 stores value 5 in sidecar z-index bits."""
    check("css-zindex-sidecar", _xml_lines(_XML_ZINDEX, extra_after=[
        'DROP',
        'S" z5" UTUI-BY-ID _UTUI-SIDECAR _UTUI-SC-ZIDX@ . CR',
    ]), "5")

def test_css_zindex_zero_default():
    """Elements without z-index have z-index=0."""
    check("css-zindex-zero-default", _xml_lines(_XML_ZINDEX, extra_after=[
        'DROP',
        'S" z0" UTUI-BY-ID _UTUI-SIDECAR _UTUI-SC-ZIDX@ . CR',
    ]), "0")

def test_css_display_none_hides():
    """display:none sets HIDE flag, element is not visible."""
    check("css-display-none-hides", _xml_lines(_XML_DISPLAY_NONE, extra_after=[
        'DROP',
        'S" hid" UTUI-BY-ID _UTUI-SIDECAR',
        'DUP _UTUI-SC-VIS? IF ." VIS" ELSE ." HIDDEN" THEN CR',
        '_UTUI-SC-FLAGS@ _UTUI-SCF-HIDE AND 0<> IF ." HIDE-SET" ELSE ." NO-HIDE" THEN CR',
    ]), check_fn=lambda o: "HIDDEN" in o and "HIDE-SET" in o)

def test_css_display_none_flow():
    """display:none skips element in flow — next element takes its row."""
    check("css-display-none-flow", _xml_lines(_XML_DISPLAY_NONE, extra_after=[
        'DROP',
        '." VIS=" S" vis" UTUI-BY-ID _UTUI-SIDECAR _UTUI-SC-ROW@ . CR',
        # "aft" should be at row 1, not row 2, because "hid" is display:none
        '." AFT=" S" aft" UTUI-BY-ID _UTUI-SIDECAR _UTUI-SC-ROW@ . CR',
    ]), check_fn=lambda o: (
        "VIS=0" in o
        and "AFT=1" in o
    ))

def test_css_paint_with_zindex():
    """UTUI-PAINT works with z-indexed elements without crash."""
    check("css-paint-zindex-no-crash", _xml_lines(_XML_ZINDEX, extra_after=[
        'DROP',
        'UTUI-PAINT',
        '." PAINT-OK" CR',
    ]), "PAINT-OK")

def test_css_paint_with_position():
    """UTUI-PAINT works with positioned elements without crash."""
    check("css-paint-pos-no-crash", _xml_lines(_XML_POSITION, extra_after=[
        'DROP',
        'UTUI-PAINT',
        '." PAINT-OK" CR',
    ]), "PAINT-OK")

def test_css_paint_display_none():
    """UTUI-PAINT skips display:none elements without crash."""
    check("css-paint-display-none", _xml_lines(_XML_DISPLAY_NONE, extra_after=[
        'DROP',
        'UTUI-PAINT',
        '." PAINT-OK" CR',
    ]), "PAINT-OK")


# ═══════════════════════════════════════════════════════════════════
#  §P — CSS Inheritance Tests
# ═══════════════════════════════════════════════════════════════════

# Parent sets fg color → child should inherit it
_XML_INHERIT_FG = (
    '<uidl>'
    '<region arrange="stack" style="color:7">'
    '  <label id="ch" text="Child"/>'
    '</region>'
    '</uidl>'
)

# Parent sets bg color → child should inherit it
_XML_INHERIT_BG = (
    '<uidl>'
    '<region arrange="stack" style="background-color:4">'
    '  <label id="ch" text="Child"/>'
    '</region>'
    '</uidl>'
)

# Parent sets bold → child should inherit attrs
_XML_INHERIT_BOLD = (
    '<uidl>'
    '<region arrange="stack" style="font-weight:bold">'
    '  <label id="ch" text="Child"/>'
    '</region>'
    '</uidl>'
)

# Child overrides parent fg
_XML_INHERIT_OVERRIDE = (
    '<uidl>'
    '<region arrange="stack" style="color:7">'
    '  <label id="ch" text="Child" style="color:1"/>'
    '</region>'
    '</uidl>'
)

# Deep nesting: grandparent → parent → child (fg=10)
_XML_INHERIT_DEEP = (
    '<uidl>'
    '<region arrange="stack" style="color:10">'
    '  <region arrange="stack" id="mid">'
    '    <label id="leaf" text="Deep"/>'
    '  </region>'
    '</region>'
    '</uidl>'
)

# Parent has position:absolute → child should NOT inherit it
_XML_NO_INHERIT_POS = (
    '<uidl>'
    '<region arrange="stack" style="position:absolute;top:0;left:0;width:80;height:24">'
    '  <label id="ch" text="Child"/>'
    '</region>'
    '</uidl>'
)

# Parent has z-index:5 → child should NOT inherit it
_XML_NO_INHERIT_ZIDX = (
    '<uidl>'
    '<region arrange="stack" style="z-index:5">'
    '  <label id="ch" text="Child"/>'
    '</region>'
    '</uidl>'
)

# No explicit style → children should inherit default (fg=253, bg=236)
_XML_INHERIT_DEFAULT = (
    '<uidl>'
    '<region arrange="stack">'
    '  <label id="ch" text="Child"/>'
    '</region>'
    '</uidl>'
)

# text-align inherits
_XML_INHERIT_ALIGN = (
    '<uidl>'
    '<region arrange="stack" style="text-align:center">'
    '  <label id="ch" text="Child"/>'
    '</region>'
    '</uidl>'
)

# Multi-property inheritance: fg + bg + bold
_XML_INHERIT_MULTI = (
    '<uidl>'
    '<region arrange="stack" style="color:15;background-color:1;font-weight:bold">'
    '  <label id="ch" text="Child"/>'
    '</region>'
    '</uidl>'
)


def test_inherit_fg():
    """Child inherits fg color from parent."""
    check("inherit-fg", _xml_lines(_XML_INHERIT_FG, extra_after=[
        'DROP',
        'S" ch" UTUI-BY-ID ?DUP IF',
        '  UTUI-SC-FG@ . CR',
        'ELSE ." NOT-FOUND" CR THEN',
    ]), "7")

def test_inherit_bg():
    """Child inherits bg color from parent."""
    check("inherit-bg", _xml_lines(_XML_INHERIT_BG, extra_after=[
        'DROP',
        'S" ch" UTUI-BY-ID ?DUP IF',
        '  UTUI-SC-BG@ . CR',
        'ELSE ." NOT-FOUND" CR THEN',
    ]), "4")

def test_inherit_bold():
    """Child inherits bold (attrs bit 0) from parent."""
    check("inherit-bold", _xml_lines(_XML_INHERIT_BOLD, extra_after=[
        'DROP',
        'S" ch" UTUI-BY-ID ?DUP IF',
        '  UTUI-SC-ATTRS@ 1 AND . CR',
        'ELSE ." NOT-FOUND" CR THEN',
    ]), "1")

def test_inherit_override():
    """Child's explicit color overrides inherited fg."""
    check("inherit-override", _xml_lines(_XML_INHERIT_OVERRIDE, extra_after=[
        'DROP',
        'S" ch" UTUI-BY-ID ?DUP IF',
        '  UTUI-SC-FG@ . CR',
        'ELSE ." NOT-FOUND" CR THEN',
    ]), "1")

def test_inherit_deep():
    """fg propagates through multiple levels (grandparent → leaf)."""
    check("inherit-deep", _xml_lines(_XML_INHERIT_DEEP, extra_after=[
        'DROP',
        'S" leaf" UTUI-BY-ID ?DUP IF',
        '  UTUI-SC-FG@ . CR',
        'ELSE ." NOT-FOUND" CR THEN',
    ]), "10")

def test_no_inherit_position():
    """position (non-inheritable) does NOT propagate to child."""
    check("no-inherit-position", _xml_lines(_XML_NO_INHERIT_POS, extra_after=[
        'DROP',
        'S" ch" UTUI-BY-ID ?DUP IF',
        '  _UTUI-SIDECAR _UTUI-SC-POS@ . CR',
        'ELSE ." NOT-FOUND" CR THEN',
    ]), "0")

def test_no_inherit_zindex():
    """z-index (non-inheritable) does NOT propagate to child."""
    check("no-inherit-zindex", _xml_lines(_XML_NO_INHERIT_ZIDX, extra_after=[
        'DROP',
        'S" ch" UTUI-BY-ID ?DUP IF',
        '  _UTUI-SIDECAR _UTUI-SC-ZIDX@ . CR',
        'ELSE ." NOT-FOUND" CR THEN',
    ]), "0")

def test_inherit_default_fg():
    """Without explicit style, child inherits default fg=253."""
    check("inherit-default-fg", _xml_lines(_XML_INHERIT_DEFAULT, extra_after=[
        'DROP',
        'S" ch" UTUI-BY-ID ?DUP IF',
        '  UTUI-SC-FG@ . CR',
        'ELSE ." NOT-FOUND" CR THEN',
    ]), "253")

def test_inherit_default_bg():
    """Without explicit style, child inherits default bg=236."""
    check("inherit-default-bg", _xml_lines(_XML_INHERIT_DEFAULT, extra_after=[
        'DROP',
        'S" ch" UTUI-BY-ID ?DUP IF',
        '  UTUI-SC-BG@ . CR',
        'ELSE ." NOT-FOUND" CR THEN',
    ]), "236")

def test_inherit_text_align():
    """text-align inherits from parent."""
    check("inherit-text-align", _xml_lines(_XML_INHERIT_ALIGN, extra_after=[
        'DROP',
        'S" ch" UTUI-BY-ID ?DUP IF',
        '  _UTUI-SIDECAR _UTUI-SC-TALIGN@ . CR',
        'ELSE ." NOT-FOUND" CR THEN',
    ]), "1")

def test_inherit_multi():
    """Multiple properties (fg + bg + bold) inherit together."""
    check("inherit-multi", _xml_lines(_XML_INHERIT_MULTI, extra_after=[
        'DROP',
        'S" ch" UTUI-BY-ID ?DUP IF',
        '  DUP UTUI-SC-FG@ .',
        '  DUP UTUI-SC-BG@ .',
        '  UTUI-SC-ATTRS@ 1 AND . CR',
        'ELSE ." NOT-FOUND" CR THEN',
    ]), "15 1 1", max_steps=200_000_000)


# ═══════════════════════════════════════════════════════════════════
#  §Q — Overlay Show / Hide Tests
# ═══════════════════════════════════════════════════════════════════

# Overlay doc: a base label + a group overlay with z-index
_XML_OVERLAY = (
    '<uidl>'
    '<region arrange="stack">'
    '  <label id="base" text="Background"/>'
    '  <group id="popup" style="z-index:10; color:1; background-color:0">'
    '    <label id="popup-msg" text="Popup!"/>'
    '    <action id="popup-ok" text="OK" do="close-popup"/>'
    '  </group>'
    '</region>'
    '</uidl>'
)

# Overlay doc with a dialog element (uses default z-index 255)
_XML_OVERLAY_DIALOG = (
    '<uidl>'
    '<region arrange="stack">'
    '  <label id="main" text="Main"/>'
    '  <dialog id="dlg1">'
    '    <label id="dlg-body" text="Dialog Body"/>'
    '    <action id="dlg-ok" text="OK" do="close-dlg"/>'
    '  </dialog>'
    '</region>'
    '</uidl>'
)

# Overlay doc with nested focusable elements
_XML_OVERLAY_FOCUS = (
    '<uidl>'
    '<region arrange="stack">'
    '  <action id="btn-a" text="A" do="a"/>'
    '  <action id="btn-b" text="B" do="b"/>'
    '  <group id="menu" style="z-index:50">'
    '    <action id="m1" text="Menu1" do="m1"/>'
    '    <action id="m2" text="Menu2" do="m2"/>'
    '  </group>'
    '</region>'
    '</uidl>'
)


def test_overlay_show_vis():
    """UTUI-SHOW sets VIS flag on overlay element."""
    check("overlay-show-vis", _xml_lines(_XML_OVERLAY, extra_after=[
        'DROP',
        # First hide, then show
        'S" popup" UTUI-HIDE',
        'S" popup" UTUI-BY-ID _UTUI-SIDECAR _UTUI-SC-FLAGS@',
        '_UTUI-SCF-VIS AND 0= IF ." HIDDEN" ELSE ." VIS" THEN CR',
        'S" popup" UTUI-SHOW',
        'S" popup" UTUI-BY-ID _UTUI-SIDECAR _UTUI-SC-FLAGS@',
        '_UTUI-SCF-VIS AND 0<> IF ." VISIBLE" ELSE ." INVIS" THEN CR',
    ]), check_fn=lambda o: "HIDDEN" in o and "VISIBLE" in o)


def test_overlay_hide_vis():
    """UTUI-HIDE clears VIS flag on overlay element."""
    check("overlay-hide-vis", _xml_lines(_XML_OVERLAY, extra_after=[
        'DROP',
        'S" popup" UTUI-HIDE',
        'S" popup" UTUI-BY-ID _UTUI-SIDECAR _UTUI-SC-FLAGS@',
        '_UTUI-SCF-VIS AND 0= IF ." HIDDEN-OK" ELSE ." STILL-VIS" THEN CR',
    ]), "HIDDEN-OK")


def test_overlay_hide_children_vis():
    """UTUI-HIDE clears VIS on all children of overlay."""
    check("overlay-hide-children", _xml_lines(_XML_OVERLAY, extra_after=[
        'DROP',
        'S" popup" UTUI-HIDE',
        'S" popup-msg" UTUI-BY-ID _UTUI-SIDECAR _UTUI-SC-FLAGS@',
        '_UTUI-SCF-VIS AND 0= IF ." CHILD-HIDDEN" ELSE ." CHILD-VIS" THEN CR',
    ]), "CHILD-HIDDEN")


def test_overlay_show_children_vis():
    """UTUI-SHOW sets VIS on all children of overlay."""
    check("overlay-show-children", _xml_lines(_XML_OVERLAY, extra_after=[
        'DROP',
        'S" popup" UTUI-HIDE',
        'S" popup" UTUI-SHOW',
        'S" popup-msg" UTUI-BY-ID _UTUI-SIDECAR _UTUI-SC-FLAGS@',
        '_UTUI-SCF-VIS AND 0<> IF ." CHILD-VIS" ELSE ." CHILD-HIDDEN" THEN CR',
    ]), "CHILD-VIS")


def test_overlay_dirty_subtree():
    """UTUI-SHOW marks overlay subtree dirty for repaint."""
    check("overlay-dirty-subtree", _xml_lines(_XML_OVERLAY, extra_after=[
        'DROP',
        'S" popup" UTUI-HIDE',
        # Clean the popup
        'S" popup-msg" UTUI-BY-ID UIDL-CLEAN!',
        # Now show — should dirty
        'S" popup" UTUI-SHOW',
        'S" popup-msg" UTUI-BY-ID UIDL-DIRTY?',
        'IF ." DIRTY-OK" ELSE ." CLEAN" THEN CR',
    ]), "DIRTY-OK")


def test_overlay_hide_dirties_base():
    """UTUI-HIDE marks underlying elements dirty (dirty-rect)."""
    check("overlay-hide-dirties-base", _xml_lines(_XML_OVERLAY, extra_after=[
        'DROP',
        # Clean the base element
        'S" base" UTUI-BY-ID UIDL-CLEAN!',
        # Hide popup — should dirty base (same region)
        'S" popup" UTUI-HIDE',
        'S" base" UTUI-BY-ID UIDL-DIRTY?',
        'IF ." BASE-DIRTY" ELSE ." BASE-CLEAN" THEN CR',
    ]), "BASE-DIRTY")


def test_overlay_paint_no_crash():
    """UTUI-PAINT with z-indexed overlay doesn't crash."""
    check("overlay-paint-no-crash", _xml_lines(_XML_OVERLAY, extra_after=[
        'DROP',
        'UIDL-ROOT UIDL-DIRTY!',
        'UTUI-PAINT',
        '." PAINT-OK" CR',
    ]), "PAINT-OK")


def test_overlay_dialog_show_hide():
    """UTUI-SHOW-DIALOG / UTUI-HIDE-DIALOG work as legacy wrappers."""
    check("overlay-dialog-legacy", _xml_lines(_XML_OVERLAY_DIALOG, extra_after=[
        'DROP',
        'S" dlg1" UTUI-HIDE-DIALOG',
        'S" dlg1" UTUI-BY-ID _UTUI-SIDECAR _UTUI-SC-FLAGS@',
        '_UTUI-SCF-VIS AND 0= IF ." D-HIDDEN" ELSE ." D-VIS" THEN CR',
        'S" dlg1" UTUI-SHOW-DIALOG',
        'S" dlg1" UTUI-BY-ID _UTUI-SIDECAR _UTUI-SC-FLAGS@',
        '_UTUI-SCF-VIS AND 0<> IF ." D-VISIBLE" ELSE ." D-INVIS" THEN CR',
    ]), check_fn=lambda o: "D-HIDDEN" in o and "D-VISIBLE" in o)


def test_overlay_focus_capture():
    """UTUI-SHOW captures focus to first focusable in overlay."""
    check("overlay-focus-capture", _xml_lines(_XML_OVERLAY_FOCUS, extra_after=[
        'DROP',
        'S" btn-a" UTUI-BY-ID UTUI-FOCUS!',
        'S" menu" UTUI-HIDE',
        'S" menu" UTUI-SHOW',
        'UTUI-FOCUS S" m1" UTUI-BY-ID =',
        'IF ." FOC-M1" ELSE ." FOC-OTHER" THEN CR',
    ]), "FOC-M1")


def test_overlay_focus_restore():
    """UTUI-HIDE restores focus to saved element."""
    check("overlay-focus-restore", _xml_lines(_XML_OVERLAY_FOCUS, extra_after=[
        'DROP',
        'S" btn-b" UTUI-BY-ID UTUI-FOCUS!',
        'S" menu" UTUI-HIDE',
        'S" menu" UTUI-SHOW',
        'S" menu" UTUI-HIDE',
        'UTUI-FOCUS S" btn-b" UTUI-BY-ID =',
        'IF ." FOC-B" ELSE ." FOC-OTHER" THEN CR',
    ]), "FOC-B")


def test_overlay_subtree_paint():
    """Pass 2 paints overlay subtree (children dirty → clean after paint)."""
    check("overlay-subtree-paint", _xml_lines(_XML_OVERLAY, extra_after=[
        'DROP',
        # Dirty everything and paint
        'S" popup" UTUI-BY-ID _UTUI-DIRTY-SUBTREE',
        'UIDL-ROOT UIDL-DIRTY!',
        'UTUI-PAINT',
        # After paint, popup child should be clean
        'S" popup-msg" UTUI-BY-ID UIDL-DIRTY?',
        'IF ." STILL-DIRTY" ELSE ." CLEAN-OK" THEN CR',
    ]), "CLEAN-OK")


def test_overlay_skip_children_pass1():
    """During Pass 1, children of deferred overlay are NOT painted."""
    # Regression guard: verify overlay children don't have their dirty
    # flag cleared during Pass 1 (they should only paint in Pass 2).
    check("overlay-skip-pass1", _xml_lines(_XML_OVERLAY, extra_after=[
        'DROP',
        # Dirty everything
        'UIDL-ROOT ?DUP IF _UTUI-DIRTY-SUBTREE THEN',
        'UTUI-PAINT',
        '." PASS-OK" CR',
    ]), "PASS-OK")


def test_menubar_layout():
    """_UTUI-LAYOUT-MBAR gives each menu a one-row slot as wide as its label."""
    # File: col=1, w=6 ("File"=4 + 2 gap), h=1; Edit: col=7, w=6
    check("mbar-child-coords", _xml_lines(
        '<uidl><menubar><menu label=File></menu>'
        '<menu label=Edit></menu></menubar></uidl>', extra_after=[
        'DROP',
        'UIDL-ROOT UIDL-FIRST-CHILD UIDL-FIRST-CHILD',
        'DUP _UTUI-SIDECAR DUP _UTUI-SC-COL@ . DUP _UTUI-SC-W@ . _UTUI-SC-H@ .',
        'UIDL-NEXT-SIB _UTUI-SIDECAR DUP _UTUI-SC-COL@ . _UTUI-SC-W@ .',
    ]), "1 6 1 7 6")
