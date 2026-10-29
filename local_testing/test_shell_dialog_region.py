"""A pane's dialog: the shell keeps the pane and gives the dialog a modal region."""

import pytest

from test_shell_prompt_region import DELTA_PROMPT, PROMPT
from test_shell_screen_producer import STAGED, staged_run


# The staged pane's document (token 77) shows a 12 by 4 dialog over rows 5
# to 8 and columns 7 to 18 of its content, beside the pane's text: "Close"
# on its top edge, "Save edits", and the buttons OK, the selected default,
# and No, the cancel button.  The base candidate carries it as a DIALOG and
# its two BUTTONs after the document's ordinary control, their correlations
# naming the dialog's source and key.  The static moves up three
# identities.
DIALOG = r'''
CREATE _SG-CIS RTE-CONTROL-SIZE 4 * 7 + ALLOT
CREATE _SG-CXS RUCP-CORRELATION-SIZE 4 * 7 + ALLOT
CREATE _SG-MS 1031 ALLOT CREATE _SG-OS 1031 ALLOT CREATE _SG-BS 23 ALLOT
: _SG-CI _SG-CIS 7 + -8 AND ; : _SG-CX _SG-CXS 7 + -8 AND ;
: _SG-M _SG-MS 7 + -8 AND ; : _SG-O _SG-OS 7 + -8 AND ; : _SG-B _SG-BS 7 + -8 AND ;
: _SG-C ( i -- control ) RTE-CONTROL-SIZE * _SG-CI + ;
: _SG-X ( i -- correlation ) RUCP-CORRELATION-SIZE * _SG-CX + ;
VARIABLE _SG-DU VARIABLE _SG-REV
: _SG-PAINT 9 5 DO 19 7 DO 68 J I DRW-CHAR LOOP LOOP ;
: _SG-MODEL ( -- )
    9 _SG-REV @ 12 4 0 1 _SG-M UDLG-START
    0 2 1 5 S" Close" _SG-M UDLG-TITLE!
    1 1 1 10 _SG-M UDLG-MESSAGE-SLOT!
    S" Save edits" _SG-M UDLG-LINE+
    3 1 1 4 UDLG-B-DEFAULT 7 S" OK" 0 0 _SG-M UDLG-BUTTON+
    3 6 1 4 UDLG-B-CANCEL 3 S" No" 0 0 _SG-M UDLG-BUTTON+
    _SG-M DUP UDLG-BYTES@ _SG-O 1024 UDLGC-DIALOG-PACK _SS-OK _SG-DU !
    _SG-M UDLG-BUTTON-FIRST DUP _SG-B 8 UDLGC-BUTTON-PACK _SS-OK DROP
    UDLG-BUTTON-NEXT _SG-B 8 + 8 UDLGC-BUTTON-PACK _SS-OK DROP ;
: _SG-ROOT ( kind state row col height width index -- )
    _SG-C >R R@ RTE-CONTROL-SIZE 0 FILL
    R@ _RTE-CONTROL.WIDTH ! R@ _RTE-CONTROL.HEIGHT !
    R@ _RTE-CONTROL.COL ! R@ _RTE-CONTROL.ROW !
    R@ _RTE-CONTROL.STATE ! R@ _RTE-CONTROL.KIND !
    88 R@ _RTE-CONTROL.OWNER ! 99 R@ _RTE-CONTROL.GENERATION !
    255 R@ _RTE-CONTROL.Z ! 10 R@ _RTE-CONTROL.REGION !
    12 R@ _RTE-CONTROL.ROOT-HEIGHT ! 32 R> _RTE-CONTROL.ROOT-WIDTH ! ;
: _SG-TEXT! ( label-a label-u content-a content-u index -- )
    _SG-C >R R@ _RTE-CONTROL.CONTENT-U ! R@ _RTE-CONTROL.CONTENT-A !
    R@ _RTE-CONTROL.LABEL-U ! R> _RTE-CONTROL.LABEL-A ! ;
: _SG-CANDIDATE ( -- )
    1 _SG-REV ! _SG-MODEL
    _SX-CI 0 _SG-C RTE-CONTROL-SIZE MOVE
    RTE-CONTROL-DIALOG RTE-CONTROL-VISIBLE 5 7 4 12 1 _SG-ROOT
    RTE-CONTROL-BUTTON 11 8 8 1 4 2 _SG-ROOT
    RTE-CONTROL-BUTTON 3 8 13 1 4 3 _SG-ROOT
    4 1 DO 100 I + I _SG-C _RTE-CONTROL.ID ! LOOP
    S" Close" _SG-O _SG-DU @ 1 _SG-TEXT! 10 1 _SG-C _RTE-CONTROL.CONTENT-UTF8 !
    S" OK" _SG-B 8 2 _SG-TEXT! S" No" _SG-B 8 + 8 3 _SG-TEXT!
    _SG-CI _SX-P _RTHP.CONTROLS-A ! 4 _SX-P _RTHP.CONTROL-COUNT !
    _SG-CX RUCP-CORRELATION-SIZE 4 * 0 FILL
    4 0 DO 77 I _SG-X ! LOOP
    4 1 DO
        UDLSN-SOURCE-OVERLAY I _SG-X 8 + ! I 1- I _SG-X 16 + !
        9 I _SG-X 24 + ! 100 I + I _SG-X 32 + ! 1 I _SG-X 40 + ! 9 I _SG-X 48 + !
    LOOP
    _SG-CX _SX-P _RTHP.CORR-A ! ;
\ Every BUTTON of a part's control families, in order.
VARIABLE _SG-SEEN
: _SG-BUTTONS-IN ( region part -- n )
    0 _SG-SEEN ! _SP-BATCH DUP _RTE-FB.FAMILIES-A @ SWAP _RTE-FB.FAMILIES-U @ 64 / 0 ?DO
        DUP I 64 * + DUP _RTE-FE.KIND @ RTE-FAMILY-CONTROL = IF
            RTE-FAMILY-ITEMS@ RTE-CONTROL-SIZE / 0 ?DO
                DUP I RTE-CONTROL-SIZE * + DUP _RTE-CONTROL.KIND @ RTE-CONTROL-BUTTON = IF
                    _RTE-CONTROL.REGION @ 3 PICK = IF 1 _SG-SEEN +! THEN
                ELSE DROP THEN
            LOOP DROP
        ELSE DROP THEN
    LOOP 2DROP _SG-SEEN @ ;
'''

STAGED_DIALOG = STAGED + PROMPT + DIALOG


def test_a_pane_dialog_and_its_buttons_take_a_modal_region_over_the_pane():
    staged_run(STAGED_DIALOG + r'''
_SX-SETUP _SG-CANDIDATE ' _SG-PAINT DRW-OVERLAY _SP-DIALOGS
_SX-PREPARE _SS-OK
_SX-KA _SX-PART-VALID? _SS-A _SX-KA _SP-BATCH RTE-FAMILY-BATCH-VALID? _SS-A
\ One modal region, the catalog's last, over the pane's content and above it.
_SX-KA _SP-MODALS 1 = _SS-A
_SP-MODAL @ _RTE-IR.ID @ _SX-KA RSHSP-PART.NEXT-REGION @ 1- = _SS-A
_SP-MODAL @ _RTE-IR.FLAGS @ RTE-REGION-VISIBLE RTE-REGION-CLIPPED OR RTE-REGION-MODAL OR = _SS-A
_SP-MODAL @ _RTE-IR.CLIP-X @ 0= _SS-A _SP-MODAL @ _RTE-IR.CLIP-Y @ 0= _SS-A
_SP-MODAL @ _RTE-IR.CLIP-COLS @ 19 = _SS-A _SP-MODAL @ _RTE-IR.CLIP-ROWS @ 9 = _SS-A
_SP-MODAL @ _RTE-IR.Z @ 2 = _SS-A
\ The dialog and both its buttons are in the modal region; the document's
\ control stays beneath, in the pane's content.
RTE-CONTROL-DIALOG _SX-KA _SP-CONTROL DUP 0<> _SS-A
DUP _RTE-CONTROL.REGION @ _SP-MODAL @ _RTE-IR.ID @ = _SS-A
_RTE-CONTROL.ID @ 101 = _SS-A
_SP-MODAL @ _RTE-IR.ID @ _SX-KA _SG-BUTTONS-IN 2 = _SS-A
1 _SX-KA _SP-CONTROL _RTE-CONTROL.REGION @ _SP-MODAL @ _RTE-IR.ID @ <> _SS-A
\ The admission emits the modal region with the rest.
_SX-KA _SP-BATCH _SX-FX RTE-FAMILY-BATCH-EMIT _SS-OK
_SX-REGIONS @ 5 = _SS-A
_SS-DONE
''', minimum=20)


REFUSALS = {
    # Paint the dialog does not explain, inside the pane.
    "stray-paint": ": _SG-STRAY 88 8 0 DRW-CHAR ;\n"
    "_SX-SETUP _SG-CANDIDATE ' _SG-PAINT DRW-OVERLAY ' _SG-STRAY DRW-OVERLAY",
    # A dialog that reaches the pane's border row.
    "border-row": "_SX-SETUP _SG-CANDIDATE ' _SG-PAINT DRW-OVERLAY\n"
    "6 1 _SG-C _RTE-CONTROL.ROW !",
    # Buttons whose pane shows no dialog.
    "no-dialog": "_SX-SETUP _SG-CANDIDATE ' _SG-PAINT DRW-OVERLAY\n"
    "RTE-CONTROL-TEXT-AREA 1 _SG-C _RTE-CONTROL.KIND !",
    # A dialog and a prompt for one pane.
    "dialog-and-prompt": "_SX-SETUP _SG-CANDIDATE ' _SG-PAINT DRW-OVERLAY\n"
    "RTE-CONTROL-FIELD 0 _SG-C _RTE-CONTROL.KIND ! UFLSN-SOURCE-OVERLAY 0 _SG-X 8 + !",
}


@pytest.mark.parametrize("case", sorted(REFUSALS))
def test_other_paint_or_a_misplaced_dialog_refuses_the_shell_candidate(case):
    staged_run(STAGED_DIALOG + REFUSALS[case] + r'''
_SP-DIALOGS _SX-PREPARE RTE-S-UNAVAILABLE = _SS-A
_RSHSP-PENDING-PART 0= _SS-A
_SS-DONE
''', minimum=2)


DELTA_DIALOG = DELTA_PROMPT + DIALOG + r'''
\ The pending target bank carries the four controls with their identities.
: _SG-PENDING ( bank -- )
    DUP 4096 0 FILL DUP _SX-BANK _SX-P _RTHP.TARGET-PENDING ! ;
: _SG-HELLO-DIALOG _SD-HELLO ['] _SG-PAINT DRW-OVERLAY ;
: _SG-HELLP-DIALOG _SD-HELLP ['] _SG-PAINT DRW-OVERLAY ;
\ The application repaints the cells the dialog held once it closes.
: _SG-CLOSED _SD-HELLP 9 5 DO 19 7 DO 32 J I DRW-CHAR LOOP LOOP ;
'''


def test_a_delta_keeps_the_dialogs_modal_region_and_a_closed_dialog_restarts():
    staged_run(DELTA_DIALOG + r'''
_SX-SETUP _SD-HOOKS _SG-CANDIDATE _SP-DIALOGS
' _SG-HELLO-DIALOG _SD-DRAW _SX-PREPARE _SS-OK _SD-ACK
_RSHSP-ACTIVE-PART _SX-KA = _SS-A _SX-KA _SP-MODALS 1 = _SS-A
\ A changed letter in the pane while the dialog stays open is a DELTA.
' _SG-HELLP-DIALOG _SD-DRAW _SD-TA _SG-PENDING
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
_SX-KB _SX-PART-VALID? _SS-A _SD-CATALOGS= _SS-A
_SX-KB _SP-MODALS 1 = _SS-A
RTE-CONTROL-DIALOG _SX-KB _SP-CONTROL _RTE-CONTROL.REGION @ _SP-MODAL @ _RTE-IR.ID @ = _SS-A
_SP-MODAL @ _RTE-IR.ID @ _SX-KB _SG-BUTTONS-IN 2 = _SS-A
_SD-EMIT _SS-OK _SD-GREPLACE @ 1 = _SS-A _SD-CREPLACE @ 0= _SS-A
_SD-ACK _RSHSP-ACTIVE-PART _SX-KB = _SS-A
\ With the dialog closed the catalog loses its modal region: a START.
_SX-CI _SX-P _RTHP.CONTROLS-A ! 1 _SX-P _RTHP.CONTROL-COUNT ! _SX-CX _SX-P _RTHP.CORR-A !
' _SG-CLOSED _SD-DRAW _SD-TB _SD-PENDING
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE RTE-S-OK <> _SS-A
_RSHSP-PENDING-PART 0= _SS-A
_SX-PREPARE _SS-OK _RSHSP-PENDING-PART _SX-KA = _SS-A _SX-KA _SP-MODALS 0= _SS-A
_SS-DONE
''', minimum=18)


def test_a_dialog_element_and_its_buttons_stay_in_the_panes_content():
    """A dialog element is the document's own paint, not an overlay: it and
    its buttons stay in the pane's content region, with no modal region."""
    staged_run(STAGED_DIALOG + r'''
: _SG-ELEMENT ( -- ) 4 1 DO UDLSN-SOURCE-ELEMENT I _SG-X 8 + ! LOOP ;
_SX-SETUP _SG-CANDIDATE _SP-DIALOGS _SG-ELEMENT
_SX-PREPARE _SS-OK
_SX-KA _SP-MODALS 0= _SS-A
RTE-CONTROL-DIALOG _SX-KA _SP-CONTROL DUP 0<> _SS-A
_RTE-CONTROL.REGION @ _SX-KA _SP-CONTENT _RTE-IR.ID @ = _SS-A
_SX-KA _SP-CONTENT _RTE-IR.ID @ _SX-KA _SG-BUTTONS-IN 2 = _SS-A
_SS-DONE
''', minimum=4)
