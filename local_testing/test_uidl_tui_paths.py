"""UIDL-TUI paths that left the wrong cells, held to their stack comments.

The stack-effect checker of toolchain/language found three words here whose
uncommon paths broke their effects:

- _UTUI-CSS-INT ( a u -- n flag ) gave five cells for a value that is not
  a number, since CSS-PARSE-NUMBER always gives six;
- _UTUI-CSS-SET-DIM ( val-a val-u parent-dim offset -- ) left three cells
  for such a width or height;
- _UTUI-LAYOUT-MBAR ( elem -- ) read UIDL-ATTR's three cells as two for a
  menu without a label, wrote the menu's layout flags through address 0,
  and stopped laying out the menus after it.

The words are checked directly, and through UTUI-LOAD of a document whose
menubar holds a menu without a label and whose label's width and padding
are not numbers.
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
    "VARIABLE T-DEPTH",
    ": T{  ( -- )  DEPTH T-DEPTH ! ;",
    ': }T  ( -- )  DEPTH T-DEPTH @ - ." cells=" . ;',
    ": T-COL  ( id-a id-u -- col )  UIDL-BY-ID _UTUI-SIDECAR _UTUI-SC-COL@ ;",
)

SUITE = NativeForth(("tui/uidl-tui.f",), prelude=PRELUDE)

DOCUMENT = (
    "<uidl><menubar>"
    "<menu id=file label=File><item text=Open/></menu>"
    "<menu id=bare><item text=Nothing/></menu>"
    "<menu id=edit label=Edit><item text=Undo/></menu>"
    "</menubar>"
    '<label id=note text=hi style="width: wide; padding: thin"/>'
    "</uidl>"
)


def _printed(lines, steps=300_000_000):
    raw = SUITE.run(lines, steps)
    text = "".join(chr(b) if 0x20 <= b < 0x7F or b == 10 else "" for b in raw)
    assert "??" not in text and "ABORT" not in text, text[-600:]
    return text


def test_css_int_gives_two_cells():
    text = _printed([
        ': T1  S" wide" T{ _UTUI-CSS-INT }T ." flag=" . ." n=" .',
        '      S" 42px" T{ _UTUI-CSS-INT }T ." flag=" . ." n=" . ;',
        "T1",
    ])
    assert "cells=0 flag=0 n=0 cells=0 flag=-1 n=42" in text.replace("\n", " "), text[-400:]


def test_css_set_dim_takes_its_four_cells():
    text = _printed([
        ': T1  S" wide" 80 0 T{ _UTUI-CSS-SET-DIM }T ;',
        "T1",
    ])
    assert "cells=-4" in text, text[-400:]


def test_document_with_a_bare_menu_and_bad_lengths_lays_out():
    lines = ["T-RGN", "TR"]
    lines.extend(f"{ord(ch)} TC" for ch in DOCUMENT)
    lines += [
        ": T1  TA _RGN_SLOT @ T{ UTUI-LOAD }T ." + '" loaded=" .',
        '      S" edit" T-COL S" file" T-COL - ." step=" . ;',
        "T1",
    ]
    text = _printed(lines)
    # "File" is four cells wide; the menu after it starts six cells on.
    assert "cells=-2 loaded=-1 step=6" in text, text[-400:]
