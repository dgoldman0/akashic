#!/usr/bin/env python3
"""Test suite for akashic-tui-fexplorer applet (fexplorer.f).

Full-featured file explorer applet tests: compilation, descriptor entry,
title and sort constants, and the clipboard's paste between places on two
volumes.  Every check runs on a fresh native machine (native_forth.py) with
fexplorer.f's closure loaded.
"""
from native_forth import NativeForth

# The app-shell's real terminal lifecycle is outside this unit test, so the
# app-shell words fexplorer uses stand in for app-shell.f itself.  A toast
# or a notice prints its text in brackets.
APP_SHELL_STANDIN = (
    ': ASHELL-DIRTY!  ( -- ) ;',
    ': ASHELL-QUIT    ( -- ) ;',
    ': ASHELL-RUN     ( desc -- ) DROP ;',
    '3 CONSTANT ASHELL-SEVERITY-WARNING',
    '4 CONSTANT ASHELL-SEVERITY-ERROR',
    ': ASHELL-NOTICE  ( addr len ms severity -- ) 2DROP',
    '    ." [notice " TYPE ."  ] " ;',
    ': ASHELL-TOAST   ( addr len ms -- ) DROP ." [toast " TYPE ."  ] " ;',
    ': ASHELL-TOAST-WARNING ( addr len ms -- ) ASHELL-TOAST ;',
    ': ASHELL-TOAST-ERROR ( addr len ms -- ) ASHELL-TOAST ;',
)

SUITE = NativeForth(
    ("tui/applets/fexplorer/fexplorer.f",),
    replace={"tui/app-shell.f": APP_SHELL_STANDIN},
    load_steps=1_500_000_000,
)


def uart_text(raw):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9)) else ""
        for b in raw)


def run_forth(lines, max_steps=80_000_000):
    return uart_text(SUITE.run(lines, max_steps))


def check(name, forth_lines, expected):
    output = run_forth(forth_lines)
    tail = "\n".join(output.strip().split("\n")[-8:])
    assert expected in output, f"{name}: expected {expected!r}, got:\n{tail}"


# ═══════════════════════════════════════════════════════════════════
#  Tests
# ═══════════════════════════════════════════════════════════════════

def test_compilation():
    """Verify fexplorer.f compiled with no errors."""
    check("fexplorer compiles: FEXP-ENTRY exists",
          ["CREATE TD-C APP-DESC ALLOT  TD-C FEXP-ENTRY  TD-C APP.INIT-XT @ 0<> ."],
          "-1")

def test_fexp_run_exists():
    check("FEXP-RUN word exists",
          [": T-RUN  FEXP-DESC FEXP-ENTRY ; T-RUN  FEXP-DESC APP.INIT-XT @ 0<> ."],
          "-1")

def test_entry_fills_desc():
    """FEXP-ENTRY should fill the descriptor callbacks."""
    check("FEXP-ENTRY fills init-xt",
          ["CREATE TD APP-DESC ALLOT  TD FEXP-ENTRY  TD APP.INIT-XT @ 0<> .",],
          "-1")

def test_entry_fills_paint():
    check("FEXP-ENTRY fills paint-xt",
          ["CREATE TD2 APP-DESC ALLOT  TD2 FEXP-ENTRY  TD2 APP.PAINT-XT @ 0<> .",],
          "-1")

def test_entry_fills_event():
    check("FEXP-ENTRY fills event-xt",
          ["CREATE TD3 APP-DESC ALLOT  TD3 FEXP-ENTRY  TD3 APP.EVENT-XT @ 0<> .",],
          "-1")

def test_entry_fills_shutdown():
    check("FEXP-ENTRY fills shutdown-xt",
          ["CREATE TD4 APP-DESC ALLOT  TD4 FEXP-ENTRY  TD4 APP.SHUTDOWN-XT @ 0<> .",],
          "-1")

def test_entry_title():
    """Title should be 'File Explorer'."""
    check("FEXP-ENTRY sets title",
          ["CREATE TD5 APP-DESC ALLOT  TD5 FEXP-ENTRY",
           "TD5 APP.TITLE-A @ TD5 APP.TITLE-U @ TYPE"],
          "File Explorer")

def test_constants_sort():
    check("Sort constants defined",
          ["FEXP-SORT-NAME FEXP-SORT-SIZE FEXP-SORT-TYPE . . .",],
          "2 1 0")


# ═══════════════════════════════════════════════════════════════════
#  Paste between places
# ═══════════════════════════════════════════════════════════════════

# Two RAM volumes, the first on a copy of the RAM binding whose removals
# fail while F-UNLINK is set, and a set of three places: `one` over the
# first volume, `two` over the second, and `ro`, a read-only place over the
# second volume's /ro.  File Explorer's state is an instance's, with the
# set and no widgets, so a paste lists the directory again but draws
# nothing.
PASTE_HELPERS = (
    'CREATE T-OPS VFS-OPS-SIZE ALLOT  CREATE T-BINDING VFS-BINDING-DESC-SIZE ALLOT',
    'VARIABLE F-UNLINK  0 F-UNLINK !',
    ': T-UNLINK  ( inode vfs -- ior )',
    '    F-UNLINK @ IF 2DROP VFS-E-IO EXIT THEN _VFS-RAM-UNLINK ;',
    'VFS-RAM-OPS T-OPS VFS-OPS-SIZE MOVE',
    'VFS-RAM-BINDING T-BINDING VFS-BINDING-DESC-SIZE MOVE',
    'T-OPS T-BINDING VB.OPS !',
    "' T-UNLINK T-OPS VFS-OP-UNLINK CELLS + !",
    ': T-VFS  ( binding -- vfs )',
    '    1048576 A-XMEM ARENA-NEW THROW SWAP 0 VFS-NEW THROW ;',
    'VARIABLE VA  VARIABLE VB',
    'T-BINDING T-VFS VA !  VFS-RAM-BINDING T-VFS VB !',
    'S" d" VA @ VFS-MKDIR THROW',
    'S" sub" VB @ VFS-MKDIR THROW  S" ro" VB @ VFS-MKDIR THROW',
    'VARIABLE SET  VARIABLE P-ONE  VARIABLE P-TWO  VARIABLE P-RO',
    ': T-PLACES  ( -- )',
    '    PLSET-NEW THROW SET !',
    '    S" va" PLACES-VOLUME THROW  VA @ OVER PVOL-ATTACH THROW >R',
    '    S" one" S" /" PLACE-WRITABLE R> PLACES-DECLARE THROW',
    '    PLACE-WRITABLE SWAP SET @ PLSET-GRANT THROW P-ONE !',
    '    S" vb" PLACES-VOLUME THROW  VB @ OVER PVOL-ATTACH THROW >R',
    '    S" two" S" /" PLACE-WRITABLE R@ PLACES-DECLARE THROW',
    '    PLACE-WRITABLE SWAP SET @ PLSET-GRANT THROW P-TWO !',
    '    S" ro" S" /ro" PLACE-READ-ONLY R> PLACES-DECLARE THROW',
    '    PLACE-READ-ONLY SWAP SET @ PLSET-GRANT THROW P-RO ! ;',
    'T-PLACES',
    '_FEXP-STATE-SIZE ALLOCATE THROW DUP _FEXP-STATE-SIZE 0 FILL',
    '_FEXP-CURRENT-STATE !',
    'SET @ _FEXP-SET !  _FEXP-CLIP-CLEAR',
    ': T-LIST  S" /" _FEXP-DIR-PATH! DROP  P-ONE @ _FEXP-DIR-PLACE ! ;  T-LIST',
    ': SEL  ( path-a path-u place -- )  _FEXP-SEL-PLACE ! _FEXP-SEL-PATH! DROP ;',
    'VARIABLE P-FD',
    ': PUT  ( a u path-a path-u vfs -- )',
    '    >R 2DUP R@ VFS-CREATE 0= ABORT" PUT: create failed"',
    '    VFS-FF-WRITE R> VFS-OPEN? THROW P-FD !',
    '    P-FD @ VFS-WRITE-EXACT THROW  P-FD @ VFS-CLOSE? THROW ;',
    'CREATE BACK 256 ALLOT  VARIABLE S-FD',
    ': SAME?  ( path-a path-u vfs a u -- flag )',
    '    2>R VFS-FF-READ SWAP VFS-OPEN? IF DROP 2R> 2DROP 0 EXIT THEN S-FD !',
    '    S-FD @ VFS-SIZE R@ <> IF S-FD @ VFS-CLOSE? DROP 2R> 2DROP 0 EXIT THEN',
    '    BACK R@ S-FD @ VFS-READ-EXACT IF S-FD @ VFS-CLOSE? DROP 2R> 2DROP 0 EXIT THEN',
    '    S-FD @ VFS-CLOSE? DROP  BACK R@ 2R> COMPARE 0= ;',
    ': HAS?  ( path-a path-u vfs -- flag )',
    '    >R VFS-RP-NOFOLLOW-FINAL R> VFS-RESOLVE-POLICY? NIP 0= ;',
)

PASTE = NativeForth(
    ("tui/applets/fexplorer/fexplorer.f",),
    replace={"tui/app-shell.f": APP_SHELL_STANDIN},
    prelude=PASTE_HELPERS,
    load_steps=1_500_000_000,
)


def pasted(lines):
    """What LINES printed after the RESULT: marker, as single-spaced words."""
    raw = PASTE.run(['." RESULT: "', *lines, 'CR'], 200_000_000)
    text = uart_text(raw)
    assert "RESULT:" in text, text[-800:]
    tail = text.rsplit("RESULT:", 1)[1]
    assert "??" not in tail, tail
    return " ".join(tail.split())


def test_paste_copies_a_file_between_places_on_two_volumes():
    assert pasted([
        ': T  FEXP-CLIP-PASTE',
        '     S" alpha bytes" S" /a.txt" VA @ PUT',
        '     S" /d" P-ONE @ SEL  FEXP-CLIP-COPY',
        '     S" /a.txt" P-ONE @ SEL  FEXP-CLIP-COPY',
        '     S" /" P-TWO @ SEL  FEXP-CLIP-PASTE',
        '     S" /a.txt" VB @ S" alpha bytes" SAME? .  S" /a.txt" VA @ HAS? .',
        '     FEXP-CLIP-PASTE',
        '     S" /" P-RO @ SEL  FEXP-CLIP-PASTE  S" /ro/a.txt" VB @ HAS? .',
        # A selected folder, or a selected file's folder, takes the paste.
        '     S" /sub" P-TWO @ SEL  FEXP-CLIP-PASTE',
        '     S" /sub/a.txt" VB @ S" alpha bytes" SAME? .',
        '     S" z" S" /d/z.txt" VA @ PUT  S" /d/z.txt" P-ONE @ SEL  FEXP-CLIP-PASTE',
        '     S" /d/a.txt" VA @ HAS? . ;',
        'T',
    ]) == " ".join([
        "[toast Clipboard empty ]",
        "[toast Directory clipboard operations are not supported ]",
        "[toast Copied to clipboard ]",
        "[toast Pasted! ]", "-1 -1",
        "[notice Paste refused: destination exists ]",
        "[notice Paste refused: this place is read-only ]", "0",
        "[toast Pasted! ]", "-1",
        "[toast Pasted! ]", "-1",
    ])


def test_cut_moves_a_file_between_places_and_says_what_stands():
    assert pasted([
        ': T  S" beta" S" /b.txt" VA @ PUT',
        '     S" /b.txt" P-ONE @ SEL  FEXP-CLIP-CUT',
        '     S" /sub" P-TWO @ SEL  FEXP-CLIP-PASTE',
        '     S" /b.txt" VA @ HAS? .  S" /sub/b.txt" VB @ S" beta" SAME? .',
        '     _FEXP-CLIP-OP @ .',
        # A read-only place gives no file to a cut.
        '     S" gamma" S" /ro/c.txt" VB @ PUT',
        '     S" /c.txt" P-RO @ SEL  FEXP-CLIP-CUT',
        '     S" /" P-ONE @ SEL  FEXP-CLIP-PASTE',
        '     S" /ro/c.txt" VB @ HAS? .  S" /c.txt" VA @ HAS? .',
        # The copy stands when the source cannot be removed.
        '     S" delta" S" /e.txt" VA @ PUT  -1 F-UNLINK !',
        '     S" /e.txt" P-ONE @ SEL  FEXP-CLIP-CUT',
        '     S" /" P-TWO @ SEL  FEXP-CLIP-PASTE  0 F-UNLINK !',
        '     S" /e.txt" VA @ HAS? .  S" /e.txt" VB @ S" delta" SAME? .',
        '     _FEXP-CLIP-OP @ .',
        # Inside one volume a cut is a rename.
        '     S" eps" S" /m.txt" VA @ PUT',
        '     S" /m.txt" P-ONE @ SEL  FEXP-CLIP-CUT',
        '     S" /d" P-ONE @ SEL  FEXP-CLIP-PASTE',
        '     S" /m.txt" VA @ HAS? .  S" /d/m.txt" VA @ S" eps" SAME? . ;',
        'T',
    ]) == " ".join([
        "[toast Cut to clipboard ]", "[toast Pasted! ]", "0 -1 0",
        "[toast Cut to clipboard ]",
        "[notice Paste refused: the source's place is read-only ]", "-1 0",
        "[toast Cut to clipboard ]",
        "[toast Pasted, but the source could not be removed ]", "-1 -1 0",
        "[toast Cut to clipboard ]", "[toast Pasted! ]", "0 -1",
    ])
