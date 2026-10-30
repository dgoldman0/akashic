"""A UIDL <dialog> is a framed container.

It keeps the rectangle its parent's layout gives it, draws a single-line
frame with its title on the top edge, and stacks its children inside the
frame: its leading labels, one row each, then the rest.
"""

from native_forth import NativeForth


HELPERS = (
    "CREATE _TB 4096 ALLOT  VARIABLE _TL",
    ": TR  0 _TL ! ;",
    ": TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;",
    ": TA  ( -- addr u ) _TB _TL @ ;",
    "VARIABLE _RGN",
    "40 12 SCR-NEW SCR-USE",
    # One screen row, box drawing shown as #.
    ": ROW.  ( row -- ) [CHAR] | EMIT 40 0 DO DUP I SCR-GET CELL-CP@ "
    "DUP 127 > IF DROP 35 THEN DUP 32 < IF DROP 46 THEN EMIT LOOP DROP "
    "[CHAR] | EMIT CR ;",
    ": SCREEN.  12 0 DO I ROW. LOOP ;",
    # An element's rectangle.
    ": BOX.  ( id-a id-u -- ) UTUI-BY-ID _UTUI-SIDECAR "
    "DUP _UTUI-SC-ROW@ . DUP _UTUI-SC-COL@ . DUP _UTUI-SC-H@ . _UTUI-SC-W@ . CR ;",
    "VARIABLE _N  : COUNT-ONE  ( elem -- ) DROP 1 _N +! ;",
)

SUITE = NativeForth(("tui/uidl-tui.f",), prelude=HELPERS)

DOCUMENT = (
    '<uidl arrange="stack"><dialog id="dlg" title="Applets">'
    '<label id="st" text="select an applet"/>'
    '<label id="hint" text="Esc close"/>'
    '<region id="rows"/>'
    "</dialog></uidl>"
)


def _run(after: list[str]) -> list[str]:
    lines = ["0 0 12 40 RGN-NEW _RGN !", "TR",
             *[f"{ord(ch)} TC" for ch in DOCUMENT],
             "TA _RGN @ UTUI-LOAD DROP", *after]
    raw = SUITE.run(lines, 80_000_000)
    text = "".join(chr(b) if (0x20 <= b < 0x7F or b == 10) else "" for b in raw)
    return text.splitlines()


def test_a_dialog_frames_its_title_and_stacks_its_children() -> None:
    out = _run(["UTUI-PAINT SCREEN.",
                'S" dlg" BOX. S" st" BOX. S" hint" BOX. S" rows" BOX.'])
    rows = [line[1:-1] for line in out if line.startswith("|") and line.endswith("|")]
    assert len(rows) == 12
    assert rows[0].startswith("##Applets#")
    assert rows[0].endswith("#")
    assert rows[1] == "#select an applet" + " " * 22 + "#"
    assert rows[2] == "#Esc close" + " " * 29 + "#"
    assert all(row == "#" + " " * 38 + "#" for row in rows[3:11])
    assert rows[11] == "#" * 40
    boxes = [line.split() for line in out if line and line[0].isdigit()]
    # The dialog fills the document; its labels take a row each inside the
    # frame and its region the rest.
    assert boxes == [["0", "0", "12", "40"], ["1", "1", "1", "38"],
                     ["2", "1", "1", "38"], ["3", "1", "8", "38"]]


def test_each_element_is_visited_parents_first() -> None:
    out = _run(["0 _N ! ' COUNT-ONE UTUI-EACH-ELEM _N @ .",
                '." DONE" CR'])
    # uidl, dialog, two labels and a region.
    assert any(line.strip() == "5 DONE" for line in out)


# Each pass keeps, for each element it visits of the type compared, its
# effective visibility, the bytes available and its resolved record, at the
# element's index; the two tables must be the same.
PASSES = (
    "CREATE _TW 4096 ALLOT  CREATE _TT 4096 ALLOT",
    "VARIABLE _VY  VARIABLE _V-E  VARIABLE _V-I  VARIABLE _V-EFF",
    "VARIABLE _V-RES  VARIABLE _V-AV  VARIABLE _VN",
    ": _KEEP  ( table -- ) _V-I @ 88 * + "
    "_V-EFF @ OVER ! _V-AV @ OVER 8 + ! "
    "_V-AV @ IF _V-RES @ SWAP 16 + 72 MOVE ELSE DROP THEN ;",
    ": _WALK-V  ( elem index ordinal local effective resolved available -- ) "
    "_V-AV ! _V-RES ! _V-EFF ! 2DROP _V-I ! _V-E ! "
    "_V-E @ UIDL-TYPE _VY @ = IF _TW _KEEP THEN ;",
    ": _TYPE-V  ( elem index effective resolved available -- ) "
    "_V-AV ! _V-RES ! _V-EFF ! _V-I ! _V-E ! 1 _VN +! "
    "_V-E @ UIDL-TYPE _VY @ = IF _TT _KEEP THEN ;",
    ": _SAME  ( type -- ) DUP _VY ! 0 _VN ! "
    "_TW 4096 0 FILL _TT 4096 0 FILL "
    "['] _WALK-V UTUI-RESOLVED-TREE-EACH . "
    "['] _TYPE-V UTUI-RESOLVED-TYPE-EACH . _VN @ . "
    "_TW 4096 _TT 4096 COMPARE . CR ;",
)

PASS_SUITE = NativeForth(("tui/uidl-tui.f",), prelude=HELPERS + PASSES)

LAYERED = (
    '<uidl arrange="stack">'
    '<region id="top" style="z-index:3"><label id="a" text="one"/></region>'
    '<dialog id="d1" title="One"><label id="b" text="two"/></dialog>'
    '<region id="gone" style="display:none">'
    '<dialog id="d2" title="Two"/><label id="c" text="three"/></region>'
    '<label id="e" text="four"/>'
    "</uidl>"
)


def test_one_type_pass_gives_each_element_what_the_tree_walk_gives() -> None:
    """The pass over one type resolves each element alone, from itself up
    to the root, and gives it the resolved record, visibility and lineage
    the tree walk gives it: under a positioned depth, inside a dialog, in a
    hidden container, and below the screen.  Both read the layout the load
    made."""
    lines = ["0 0 12 40 RGN-NEW _RGN !", "TR",
             *[f"{ord(ch)} TC" for ch in LAYERED],
             "TA _RGN @ UTUI-LOAD DROP",
             "UIDL-T-DIALOG _SAME", "UIDL-T-LABEL _SAME",
             "UIDL-T-REGION _SAME", '." DONE" CR']
    raw = PASS_SUITE.run(lines, 80_000_000)
    text = "".join(chr(b) if (0x20 <= b < 0x7F or b == 10) else "" for b in raw)
    rows = [line.split() for line in text.splitlines()
            if line.split()[:2] == ["0", "0"]]
    # Each type: both passes OK, the elements visited, and equal tables.
    assert rows == [["0", "0", "2", "0"], ["0", "0", "4", "0"],
                    ["0", "0", "2", "0"]], text
    assert "DONE" in text
