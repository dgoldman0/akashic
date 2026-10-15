"""An overlay pane, such as one of Desk's screens, lies over the pane beneath
it, and with dialogs its document goes in a modal region over the screen."""

import pytest

from test_shell_prompt_region import PROMPT
from test_shell_screen_producer import STAGED, staged_run


# The staged pane (slot 11, token 77) shows A over its 9 by 19 content.  An
# overlay slot (-2, token 79) its host paints above it, as foreground, shows
# B over its own rectangle, by default rows 2 to 5 and columns 4 to 13,
# inside the pane's content.  Its document's one control, a menu bar across
# its top row, follows the pane document's control; the static moves up to
# follow both.
OVERLAY = r'''
CREATE _SO-SLOTS AHS-SIZE 7 + ALLOT
CREATE _SO-DIRS RUHA-DOCUMENT-SIZE 2 * 7 + ALLOT
CREATE _SO-CIS RTE-CONTROL-SIZE 2 * 7 + ALLOT
CREATE _SO-CXS RUCP-CORRELATION-SIZE 2 * 7 + ALLOT
: _SO-SLOT _SO-SLOTS 7 + -8 AND ; : _SO-DIR _SO-DIRS 7 + -8 AND ;
: _SO-CI _SO-CIS 7 + -8 AND ; : _SO-CX _SO-CXS 7 + -8 AND ;
VARIABLE _SO-CHILD VARIABLE _SO-E
VARIABLE _SO-ROW VARIABLE _SO-COL VARIABLE _SO-H VARIABLE _SO-W
: _SO-BACK 9 0 DO 19 0 DO 65 J I DRW-CHAR LOOP LOOP ;
: _SO-PAINT
    _SO-ROW @ _SO-H @ OVER + SWAP DO
        _SO-COL @ _SO-W @ OVER + SWAP DO 66 J I DRW-CHAR LOOP
    LOOP ;
: _SO-ENTRY! ( -- )
    2 _SO-E @ SHME.KEY ! SHM-K-PANE _SO-E @ SHME.KIND ! SHM-F-OVERLAY _SO-E @ SHME.FLAGS !
    _SO-ROW @ DUP _SO-E @ SHME.ROW ! _SO-E @ SHME.CONTENT-ROW !
    _SO-COL @ DUP _SO-E @ SHME.COL ! _SO-E @ SHME.CONTENT-COL !
    _SO-H @ DUP _SO-E @ SHME.HEIGHT ! _SO-E @ SHME.CONTENT-H !
    _SO-W @ DUP _SO-E @ SHME.WIDTH ! _SO-E @ SHME.CONTENT-W !
    _SO-CHILD @ CINST.ID @ _SO-E @ SHME.OWNER-ID !
    _SO-CHILD @ CINST.GENERATION @ _SO-E @ SHME.OWNER-GEN !
    -2 _SO-E @ SHME.IDENTITY ! -2 _SO-E @ SHME.ACTION ! ;
\ The overlay slot and its pane, which the canonical model keeps with the
\ panes, before the task and the launcher, its text dense in entry order.
: _SO-MODEL ( -- )
    _SX-D CINST-NEW _SS-OK _SO-CHILD !
    _SO-SLOT AHS-SIZE 0 FILL _SO-CHILD @ _SO-SLOT AHS.INST !
    _SO-ROW @ _SO-COL @ _SO-H @ _SO-W @ RGN-NEW _SO-SLOT AHS.RGN !
    -2 _SO-SLOT AHS.ID ! -1 _SO-SLOT AHS.OVERLAY !
    AHS-S-RUNNING _SO-SLOT AHS.STATE ! _SO-SLOT _SX-SLOT AHS.NEXT !
    0 _SS-M SHM.READY ! _SS-M SHM-APPEND DUP 0<> _SS-A _SO-E ! _SO-ENTRY!
    3 _SS-M SHM-ENTRY _SS-O SHM-ENTRY-SIZE MOVE
    1 _SS-M SHM-ENTRY 2 _SS-M SHM-ENTRY SHM-ENTRY-SIZE 2 * MOVE
    _SS-O 1 _SS-M SHM-ENTRY SHM-ENTRY-SIZE MOVE
    4 0 DO I _SS-M SHM-ENTRY SHME.LABEL-OFF 48 0 FILL LOOP
    SHM-HEADER-SIZE SHM-ENTRY-SIZE 4 * + _SS-M SHM.USED !
    S" Editor" _SS-M SHM-COPY$ _SS-A 0 _SS-M SHM-ENTRY SHME.TITLE-OFF !
    6 0 _SS-M SHM-ENTRY SHME.TITLE-U !
    S" Pick" _SS-M SHM-COPY$ _SS-A 1 _SS-M SHM-ENTRY SHME.TITLE-OFF !
    4 1 _SS-M SHM-ENTRY SHME.TITLE-U !
    S" Edit" _SS-M SHM-COPY$ _SS-A 2 _SS-M SHM-ENTRY SHME.LABEL-OFF !
    4 2 _SS-M SHM-ENTRY SHME.LABEL-U !
    S" Editor" _SS-M SHM-COPY$ _SS-A 2 _SS-M SHM-ENTRY SHME.TITLE-OFF !
    6 2 _SS-M SHM-ENTRY SHME.TITLE-U !
    S" Run" _SS-M SHM-COPY$ _SS-A 3 _SS-M SHM-ENTRY SHME.LABEL-OFF !
    3 3 _SS-M SHM-ENTRY SHME.LABEL-U !
    S" Launch" _SS-M SHM-COPY$ _SS-A 3 _SS-M SHM-ENTRY SHME.TITLE-OFF !
    6 3 _SS-M SHM-ENTRY SHME.TITLE-U !
    S" start" _SS-M SHM-COPY$ _SS-A 3 _SS-M SHM-ENTRY SHME.ACTION-OFF !
    5 3 _SS-M SHM-ENTRY SHME.ACTION-U !
    2 _SS-M SHM.EPOCH ! _SS-M SHM-SEAL
    _SX-OBSERVE
    SCR-DRAW-GENERATION@ DUP _SX-P _RTHP.SOURCE-DRAW ! _SX-P _RTHP.SURFACE-GEN ! ;
\ Both documents, and the overlay document's control after the pane's.
: _SO-CANDIDATE ( -- )
    _SX-DIR _SO-DIR RUHA-DOCUMENT-SIZE MOVE
    _SO-DIR RUHA-DOCUMENT-SIZE + DUP RUHA-DOCUMENT-SIZE 0 FILL _SO-E !
    79 _SO-E @ _RUHA-D.TOKEN ! -2 _SO-E @ _RUHA-D.SLOT-ID !
    _SO-ROW @ _SO-E @ _RUHA-D.ROW ! _SO-COL @ _SO-E @ _RUHA-D.COL !
    _SO-H @ _SO-E @ _RUHA-D.HEIGHT ! _SO-W @ _SO-E @ _RUHA-D.WIDTH !
    _SO-CHILD @ CINST.ID @ _SO-E @ _RUHA-D.OWNER-ID !
    _SO-CHILD @ CINST.GENERATION @ _SO-E @ _RUHA-D.OWNER-GEN !
    _SO-DIR _SX-P _RTHP.SOURCE-DIR-A ! RUHA-DOCUMENT-SIZE 2 * _SX-P _RTHP.SOURCE-DIR-USED !
    _SX-CI _SO-CI RTE-CONTROL-SIZE MOVE
    _SO-CI RTE-CONTROL-SIZE + _SO-E ! _SX-CI _SO-E @ RTE-CONTROL-SIZE MOVE
    101 _SO-E @ _RTE-CONTROL.ID !
    _SO-ROW @ _SO-E @ _RTE-CONTROL.ROW ! _SO-COL @ _SO-E @ _RTE-CONTROL.COL !
    _SO-W @ _SO-E @ _RTE-CONTROL.WIDTH !
    _SO-CI _SX-P _RTHP.CONTROLS-A ! 2 _SX-P _RTHP.CONTROL-COUNT !
    _SO-CX RUCP-CORRELATION-SIZE 2 * 0 FILL
    77 _SO-CX ! 79 _SO-CX RUCP-CORRELATION-SIZE + !
    _SO-CX _SX-P _RTHP.CORR-A !
    102 _SX-SI _RTE-STATIC.ID ! 102 _SX-P _RTHP.STATIC-LAST ! ;
: _SO-SETUP ( row col h w -- )
    _SO-W ! _SO-H ! _SO-COL ! _SO-ROW !
    _SX-SETUP _SO-MODEL _SO-CANDIDATE _SO-BACK ['] _SO-PAINT DRW-OVERLAY ;
: _SO-CONTROL ( id bank -- control|0 )
    _SP-BATCH DUP _RTE-FB.FAMILIES-A @ SWAP _RTE-FB.FAMILIES-U @ 64 / 0 ?DO
        DUP I 64 * + DUP _RTE-FE.KIND @ RTE-FAMILY-CONTROL = IF
            RTE-FAMILY-ITEMS@ RTE-CONTROL-SIZE / 0 ?DO
                DUP I RTE-CONTROL-SIZE * + DUP _RTE-CONTROL.ID @ 4 PICK = IF
                    >R DROP 2DROP R> UNLOOP UNLOOP EXIT THEN DROP
            LOOP DROP
        ELSE DROP THEN
    LOOP 2DROP 0 ;
: _SO-MEMBER ( token bank -- member )
    DUP RSHSP-BANK.MEMBERSHIP @ OVER + SWAP RSHSP-BANK.MEMBERSHIP-U @ RSHMM-FIND ;
\ The content region of a document's pane.
: _SO-CONTENT ( token bank -- row ) TUCK _SO-MEMBER RSHMM.CONTENT-REGION @ SWAP _SP-REGION ;
\ The text of the glyph family planned for a region, or nothing.
: _SO-GLYPHS ( region bank -- a u )
    _SP-BATCH DUP _RTE-FB.FAMILIES-A @ SWAP _RTE-FB.FAMILIES-U @ 64 / 0 ?DO
        DUP I 64 * + DUP _RTE-FE.KIND @ RTE-FAMILY-GLYPH =
        OVER _RTE-FE.PLAN-A @ 32 + @ 4 PICK = AND IF
            NIP NIP DUP _RTE-FE.BYTES-A @ SWAP _RTE-FE.BYTES-U @ UNLOOP EXIT
        THEN DROP
    LOOP 2DROP 0 0 ;
VARIABLE _SO-K
: _SO-COUNT ( a u char -- n )
    _SO-K ! 0 ROT ROT 0 ?DO DUP I + C@ _SO-K @ = IF SWAP 1+ SWAP THEN LOOP DROP ;
'''

STAGED_OVERLAY = STAGED + PROMPT + OVERLAY


def test_an_overlay_pane_takes_a_modal_region_over_the_whole_screen():
    staged_run(STAGED_OVERLAY + r'''
2 4 4 10 _SO-SETUP _SP-DIALOGS
_RSHSP-PREPARE _SS-OK
_SX-KA _SX-S _RSHSP-BANK-VALID? _SS-A _SX-KA _SP-BATCH RTE-FAMILY-BATCH-VALID? _SS-A
\ One modal region, the catalog's last: the whole surface, above the panes.
_SX-KA _SP-MODALS 1 = _SS-A
_SP-MODAL @ _RTE-IR.ID @ _SX-KA RSHSP-BANK.NEXT-REGION @ 1- = _SS-A
_SP-MODAL @ _RTE-IR.FLAGS @ RTE-REGION-VISIBLE RTE-REGION-CLIPPED OR RTE-REGION-MODAL OR = _SS-A
_SP-MODAL @ _RTE-IR.X @ 0= _SS-A _SP-MODAL @ _RTE-IR.Y @ 0= _SS-A
_SP-MODAL @ _RTE-IR.COLS @ 32 = _SS-A _SP-MODAL @ _RTE-IR.ROWS @ 12 = _SS-A
_SP-MODAL @ _RTE-IR.CLIP-X @ 0= _SS-A _SP-MODAL @ _RTE-IR.CLIP-Y @ 0= _SS-A
_SP-MODAL @ _RTE-IR.CLIP-COLS @ 32 = _SS-A _SP-MODAL @ _RTE-IR.CLIP-ROWS @ 12 = _SS-A
_SP-MODAL @ _RTE-IR.Z @ 2 = _SS-A
\ The overlay document's control is in it; the pane's stays beneath.
101 _SX-KA _SO-CONTROL DUP 0<> _SS-A
_RTE-CONTROL.REGION @ _SP-MODAL @ _RTE-IR.ID @ = _SS-A
100 _SX-KA _SO-CONTROL _RTE-CONTROL.REGION @ 77 _SX-KA _SO-CONTENT _RTE-IR.ID @ = _SS-A
\ The overlay pane's content region is its rectangle, one above the pane's.
79 _SX-KA _SO-CONTENT DUP 0<> _SS-A
DUP _RTE-IR.CLIP-X @ 4 = _SS-A DUP _RTE-IR.CLIP-Y @ 2 = _SS-A
DUP _RTE-IR.CLIP-COLS @ 10 = _SS-A DUP _RTE-IR.CLIP-ROWS @ 4 = _SS-A
DUP _RTE-IR.FLAGS @ RTE-REGION-MODAL AND 0= _SS-A _RTE-IR.Z @ 1 = _SS-A
77 _SX-KA _SO-CONTENT _RTE-IR.Z @ 0= _SS-A
\ The pane beneath leaves the overlay's cells to the overlay pane.
77 _SX-KA _SO-CONTENT _RTE-IR.ID @ _SX-KA _SO-GLYPHS
2DUP 65 _SO-COUNT 131 = _SS-A 66 _SO-COUNT 0= _SS-A
79 _SX-KA _SO-CONTENT _RTE-IR.ID @ _SX-KA _SO-GLYPHS
2DUP 66 _SO-COUNT 40 = _SS-A 65 _SO-COUNT 0= _SS-A
\ The admission emits the modal region with the rest.
_SX-KA _SP-BATCH _SX-FX RTE-FAMILY-BATCH-EMIT _SS-OK
_SX-REGIONS @ 6 = _SS-A
_SS-DONE
''', minimum=33)


def test_without_dialogs_the_overlay_documents_controls_stay_in_its_content():
    staged_run(STAGED_OVERLAY + r'''
2 4 4 10 _SO-SETUP
_RSHSP-PREPARE _SS-OK
_SX-KA _SX-S _RSHSP-BANK-VALID? _SS-A
_SX-KA _SP-MODALS 0= _SS-A
101 _SX-KA _SO-CONTROL _RTE-CONTROL.REGION @ 79 _SX-KA _SO-CONTENT _RTE-IR.ID @ = _SS-A
77 _SX-KA _SO-CONTENT _RTE-IR.ID @ _SX-KA _SO-GLYPHS 66 _SO-COUNT 0= _SS-A
_SS-DONE
''', minimum=5)


REFUSALS = {
    # Foreground paint in the pane that no overlay pane explains: below the
    # overlay, beside it on either side in its rows, and above it.
    "below": ": _SO-STRAY 88 7 0 DRW-CHAR ;\n2 4 4 10 _SO-SETUP ' _SO-STRAY DRW-OVERLAY",
    "left": ": _SO-STRAY 88 3 1 DRW-CHAR ;\n2 4 4 10 _SO-SETUP ' _SO-STRAY DRW-OVERLAY",
    "right": ": _SO-STRAY 88 3 15 DRW-CHAR ;\n2 4 4 10 _SO-SETUP ' _SO-STRAY DRW-OVERLAY",
    "above": ": _SO-STRAY 88 1 5 DRW-CHAR ;\n2 4 4 10 _SO-SETUP ' _SO-STRAY DRW-OVERLAY",
    # An overlay over the pane's chrome, its bottom border row.
    "chrome": "6 4 4 10 _SO-SETUP",
    # An overlay pane whose document shows a prompt of its own.
    "own-overlay": "2 4 4 10 _SO-SETUP\n"
    "RTE-CONTROL-FIELD _SO-CI RTE-CONTROL-SIZE + _RTE-CONTROL.KIND !\n"
    "UFLSN-SOURCE-OVERLAY _SO-CX RUCP-CORRELATION-SIZE + 8 + !",
}


@pytest.mark.parametrize("case", sorted(REFUSALS))
def test_unexplained_paint_chrome_or_a_nested_overlay_refuses_the_candidate(case):
    staged_run(STAGED_OVERLAY + REFUSALS[case] + r'''
_SP-DIALOGS _RSHSP-PREPARE RTE-S-UNAVAILABLE = _SS-A
_SX-S _RSHSP.PENDING @ 0= _SS-A
_SS-DONE
''', minimum=2)
