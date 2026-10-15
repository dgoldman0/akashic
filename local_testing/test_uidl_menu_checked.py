"""Checked menu items, from UIDL to the retained control state.

A menu item's authored checked=true seeds its state when the document loads,
and UTUI-CHECKED! changes the state afterwards without touching UIDL's string
pool.  CELL gives every menu row a mark column, and the menu snapshot
publishes the state as UMSN-F-CHECKED, which the control planner retains as
RTE-CONTROL-CHECKED.
"""

from native_forth import NativeForth

PRELUDE = (
    "CREATE _TB 4096 ALLOT  VARIABLE _TL",
    ": TR  0 _TL ! ;",
    ": TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;",
    ": TA  ( -- addr u ) _TB _TL @ ;",
    "VARIABLE _RGN_SLOT",
    ": T-RGN  0 0 24 80 RGN-NEW _RGN_SLOT ! ;",
    "80 24 SCR-NEW SCR-USE",
    # Caller banks for one menu capture: 32 work entries and records.
    "CREATE _MW-MEM 32 136 * 8 + ALLOT",
    ": _MW  _MW-MEM 7 + -8 AND ;",
    "CREATE _MR-MEM 32 192 * 8 + ALLOT",
    ": _MR  _MR-MEM 7 + -8 AND ;",
    "CREATE _MWT 512 ALLOT",
    "CREATE _MT 512 ALLOT",
    "VARIABLE _MCOUNT",
    # Capture with GENERATION; leave the record count, or -1 on failure.
    ": T-CAPTURE ( generation -- )",
    "    _MW 32 136 * _MWT 512 _MR 32 192 * _MT 512 UMSN-CAPTURE",
    "    IF 2DROP -1 _MCOUNT ! ELSE DROP _MCOUNT ! THEN ;",
    # Print each captured item's label and whether it is checked.
    ": T-ITEMS ( -- )",
    "    _MCOUNT @ 0< IF .\" FAIL\" EXIT THEN",
    "    _MCOUNT @ 0 ?DO",
    "        _MR I 192 * + DUP UMSN-RECORD-KIND@ UMSN-K-ITEM = IF",
    "            DUP UMSN-RECORD-LABEL-OFFSET@ _MT +",
    "            OVER UMSN-RECORD-LABEL-BYTES@ TYPE",
    "            UMSN-RECORD-STATE@ UMSN-F-CHECKED AND IF",
    "                .\" =on \" ELSE .\" =off \" THEN",
    "        ELSE DROP THEN",
    "    LOOP ;",
    # The codepoint DC cells right of ELEM's cell.
    ": T-AT ( elem dc -- cp )",
    "    SWAP _UTUI-SIDECAR DUP _UTUI-SC-ROW@ SWAP _UTUI-SC-COL@",
    "    ROT + SCR-GET CELL-CP@ ;",
)

SUITE = NativeForth(("tui/rich-terminal/uidl-control-planner.f",), prelude=PRELUDE)

MENU = (
    "<uidl><menubar>"
    "<menu id=view label=View>"
    '<item id=hidden text="Show Hidden" checked=true/>'
    "<item id=refresh text=Refresh/>"
    "<item id=sort text=Sort checked=false/>"
    "</menu>"
    "<menu id=help label=Help><item id=about text=About/></menu>"
    "</menubar></uidl>"
)


def _run(lines, steps=200_000_000):
    out = ["T-RGN", "TR"]
    out.extend(f"{ord(ch)} TC" for ch in MENU)
    out.append("TA _RGN_SLOT @ UTUI-LOAD DROP")
    out.extend(lines)
    raw = SUITE.run(out, steps)
    text = "".join(chr(b) if 0x20 <= b < 0x7F or b == 10 else "" for b in raw)
    assert "??" not in text and "ABORT" not in text, text[-600:]
    return text


def _values(text, marker):
    line = next(line for line in text.splitlines() if line.startswith(marker))
    return line[len(marker):].split()


def test_checked_attribute_seeds_state_and_only_items_change() -> None:
    text = _run([
        '." S:" S" hidden" UTUI-BY-ID UTUI-CHECKED? .',
        'S" sort" UTUI-BY-ID UTUI-CHECKED? .',
        'S" refresh" UTUI-BY-ID UTUI-CHECKED? .',
        '0 S" hidden" UTUI-BY-ID UTUI-CHECKED!',
        '-1 S" sort" UTUI-BY-ID UTUI-CHECKED!',
        '-1 S" refresh" UTUI-BY-ID UTUI-CHECKED!',
        '-1 S" view" UTUI-BY-ID UTUI-CHECKED!',
        'S" hidden" UTUI-BY-ID UTUI-CHECKED? .',
        'S" sort" UTUI-BY-ID UTUI-CHECKED? .',
        'S" refresh" UTUI-BY-ID UTUI-CHECKED? .',
        'S" view" UTUI-BY-ID UTUI-CHECKED? .',
        '0 UTUI-CHECKED? . CR',
    ])
    assert _values(text, "S:") == ["-1", "0", "0", "0", "-1", "-1", "0", "0"]


def test_checking_an_item_leaves_the_string_pool_alone() -> None:
    text = _run([
        "_UDL-SPOS @",
        '0 S" hidden" UTUI-BY-ID UTUI-CHECKED!',
        '-1 S" hidden" UTUI-BY-ID UTUI-CHECKED!',
        '0 S" hidden" UTUI-BY-ID UTUI-CHECKED!',
        '." P:" _UDL-SPOS @ = . CR',
    ])
    assert _values(text, "P:") == ["-1"]


def test_every_menu_row_keeps_a_mark_column() -> None:
    # View's widest label, "Show Hidden", is 11 cells and Help's, "About", 5;
    # every row keeps a two-cell mark column before its label.
    text = _run([
        'S" view" UTUI-BY-ID _UTUI-MENU-OPEN!',
        '." V:" S" view" UTUI-BY-ID _UTUI-SIDECAR _UTUI-SC-W@ .',
        'S" hidden" UTUI-BY-ID _UTUI-SIDECAR _UTUI-SC-W@ .',
        'UIDL-ROOT ?DUP IF _UTUI-DIRTY-SUBTREE THEN UTUI-PAINT',
        'S" hidden" UTUI-BY-ID 1 T-AT .',
        'S" hidden" UTUI-BY-ID 3 T-AT .',
        'S" refresh" UTUI-BY-ID 1 T-AT .',
        'S" refresh" UTUI-BY-ID 3 T-AT .',
        'S" sort" UTUI-BY-ID 1 T-AT .',
        'S" sort" UTUI-BY-ID 3 T-AT . CR',
        'S" help" UTUI-BY-ID _UTUI-MENU-OPEN!',
        '." H:" S" help" UTUI-BY-ID _UTUI-SIDECAR _UTUI-SC-W@ .',
        'UIDL-ROOT ?DUP IF _UTUI-DIRTY-SUBTREE THEN UTUI-PAINT',
        'S" about" UTUI-BY-ID 1 T-AT .',
        'S" about" UTUI-BY-ID 3 T-AT . CR',
    ])
    assert _values(text, "V:") == [
        "17", "15",
        "10003", str(ord("S")),
        "32", str(ord("R")),
        "32", str(ord("S")),
    ]
    assert _values(text, "H:") == ["11", "32", str(ord("A"))]


def test_the_menu_snapshot_publishes_each_items_checked_state() -> None:
    text = _run([
        '1 T-CAPTURE ." A:" T-ITEMS CR',
        '0 S" hidden" UTUI-BY-ID UTUI-CHECKED!',
        '-1 S" sort" UTUI-BY-ID UTUI-CHECKED!',
        '2 T-CAPTURE ." B:" T-ITEMS CR',
    ])
    assert "A:Show Hidden=on Refresh=off Sort=off About=off" in text
    assert "B:Show Hidden=off Refresh=off Sort=on About=off" in text


def test_only_an_item_may_be_checked() -> None:
    text = _run([
        "UMSN-F-VISIBLE UMSN-F-ENABLED OR CONSTANT T-VE",
        '." R:" UMSN-K-ITEM T-VE UMSN-F-CHECKED OR UMSN-STATE-VALID? .',
        "UMSN-K-ITEM T-VE UMSN-F-CHECKED OR UMSN-F-PAINTABLE OR",
        "    UMSN-F-SELECTED OR UMSN-F-FOCUSED OR UMSN-STATE-VALID? .",
        "UMSN-K-MENU T-VE UMSN-F-CHECKED OR UMSN-STATE-VALID? .",
        "UMSN-K-MENUBAR T-VE UMSN-F-CHECKED OR UMSN-STATE-VALID? .",
        "UMSN-K-SEPARATOR UMSN-F-VISIBLE UMSN-F-CHECKED OR",
        "    UMSN-STATE-VALID? . CR",
    ])
    assert _values(text, "R:") == ["-1", "-1", "0", "0", "0"]


def test_the_shared_state_rule_keeps_the_existing_menu_rules() -> None:
    text = _run([
        "UMSN-F-VISIBLE UMSN-F-ENABLED OR CONSTANT T-VE",
        "T-VE UMSN-F-PAINTABLE OR CONSTANT T-VEP",
        '." K:" UMSN-K-MENUBAR T-VEP UMSN-STATE-VALID? .',
        "UMSN-K-MENUBAR T-VEP UMSN-F-FOCUSED OR UMSN-STATE-VALID? .",
        "UMSN-K-MENU T-VEP UMSN-F-OPEN OR UMSN-F-SELECTED OR",
        "    UMSN-F-FOCUSED OR UMSN-STATE-VALID? .",
        "UMSN-K-MENU T-VE UMSN-F-OPEN OR UMSN-STATE-VALID? .",
        "UMSN-K-ITEM T-VEP UMSN-F-OPEN OR UMSN-STATE-VALID? .",
        "UMSN-K-ITEM UMSN-F-ENABLED UMSN-F-PAINTABLE OR UMSN-STATE-VALID? .",
        "UMSN-K-ITEM UMSN-F-VISIBLE UMSN-STATE-VALID? .",
        "UMSN-K-SEPARATOR UMSN-F-VISIBLE UMSN-F-PAINTABLE OR",
        "    UMSN-STATE-VALID? .",
        "UMSN-K-SEPARATOR UMSN-F-VISIBLE UMSN-F-ENABLED OR",
        "    UMSN-STATE-VALID? .",
        "0 T-VE UMSN-STATE-VALID? .",
        "5 T-VE UMSN-STATE-VALID? .",
        "UMSN-K-ITEM T-VE 128 OR UMSN-STATE-VALID? . CR",
    ])
    assert _values(text, "K:") == [
        "-1", "0", "-1", "0", "0", "0", "0", "-1", "0", "0", "0", "0",
    ]


def test_the_retained_control_state_carries_checked() -> None:
    text = _run([
        '." M:" UMSN-F-VISIBLE UMSN-F-ENABLED OR UMSN-F-CHECKED OR',
        "    UMSN-F-FOCUSED OR UMSN-F-PAINTABLE OR RUCP-STATE>RTE",
        "    RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR",
        "    RTE-CONTROL-CHECKED OR = .",
        "UMSN-F-VISIBLE UMSN-F-ENABLED OR RUCP-STATE>RTE",
        "    RTE-CONTROL-CHECKED AND . CR",
    ])
    assert _values(text, "M:") == ["-1", "0"]
