"""An open menu closes on Escape before a shortcut takes the key.

An application may bind Escape to a cancel of its own, as File Explorer
binds it to cancelling a paste and the Agent to cancelling its run.  While
one of its menus is open, Escape closes the menu and the cancel does not
fire; once the menu is closed, Escape fires the cancel.
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
    "VARIABLE _CANCELS",
    ": T-CANCEL ( elem -- )  DROP 1 _CANCELS +! ;",
    "CREATE _EV 3 CELLS ALLOT",
    # Escape, with no modifiers, as the keyboard delivers it.
    ": T-ESC ( -- handled? )",
    "    KEY-T-SPECIAL _EV !  KEY-ESC _EV 8 + !  0 _EV 16 + !",
    "    _EV UTUI-DISPATCH-KEY ;",
    # Open MENU as a press on it does: open it, then focus its first item.
    ": T-OPEN ( menu -- )",
    "    DUP _UTUI-MENU-OPEN! UTUI-FOCUS!",
    "    _UTUI-MENU-FIRST-ITEM ?DUP IF UTUI-FOCUS! THEN ;",
)

SUITE = NativeForth(("tui/uidl-tui.f",), prelude=PRELUDE)

DOCUMENT = (
    "<uidl><menubar>"
    "<menu id=edit label=Edit>"
    "<item id=copy text=Copy/>"
    "<item text=Cancel do=cancel key=Escape/>"
    "</menu>"
    "</menubar>"
    "<action do=cancel key=Escape/>"
    "</uidl>"
)


def _run(lines, steps=200_000_000):
    out = ["T-RGN", "TR"]
    out.extend(f"{ord(ch)} TC" for ch in DOCUMENT)
    out.append("TA _RGN_SLOT @ UTUI-LOAD DROP")
    out.append("S\" cancel\" ' T-CANCEL UTUI-DO!  0 _CANCELS !")
    out.extend(lines)
    raw = SUITE.run(out, steps)
    text = "".join(chr(b) if 0x20 <= b < 0x7F or b == 10 else "" for b in raw)
    assert "??" not in text and "ABORT" not in text, text[-600:]
    return text


def _values(text, marker):
    line = next(line for line in text.splitlines() if line.startswith(marker))
    return line[len(marker):].split()


def test_escape_closes_an_open_menu_before_the_cancel_it_is_bound_to() -> None:
    text = _run([
        'S" edit" UTUI-BY-ID T-OPEN',
        '." O:" _UTUI-MENU-OPEN @ S" edit" UTUI-BY-ID = . CR',
        # The first Escape closes the menu, and the cancel does not fire.
        '." E1:" T-ESC . _UTUI-MENU-OPEN @ 0= . _CANCELS @ . CR',
        # With the menu closed, Escape is the cancel's.
        '." E2:" T-ESC . _UTUI-MENU-OPEN @ 0= . _CANCELS @ . CR',
    ])
    assert _values(text, "O:") == ["-1"]
    assert _values(text, "E1:") == ["-1", "-1", "0"]
    assert _values(text, "E2:") == ["-1", "-1", "1"]
