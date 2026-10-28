"""A pane's prompt: the shell keeps the pane and gives the prompt a modal region."""

import pytest

from test_shell_delta import DELTA
from test_shell_screen_producer import STAGED, staged_run


# The staged pane's document (token 77) paints a prompt over its last content
# row, 8, the full content width of 19 cells.  The base candidate carries it
# as a FIELD control whose correlation names the overlay source, after the
# document's ordinary control.  The static moves up one identity to follow
# the two controls.
PROMPT = r'''
CREATE _SP-CIS RTE-CONTROL-SIZE 2 * 7 + ALLOT
CREATE _SP-CXS RUCP-CORRELATION-SIZE 2 * 7 + ALLOT
: _SP-CI _SP-CIS 7 + -8 AND ; : _SP-CX _SP-CXS 7 + -8 AND ;
: _SP-FIELD ( -- control ) _SP-CI RTE-CONTROL-SIZE + ;
VARIABLE _SP-ROW
: _SP-PAINT 19 0 DO 80 _SP-ROW @ I DRW-CHAR LOOP ;
\ The prompt's TEXT field, as the base producer packs it: label "Open:",
\ value "notes.md", one row of 19 cells.
CREATE _SP-MS 1031 ALLOT CREATE _SP-BS 47 ALLOT CREATE _SP-OS 1031 ALLOT
: _SP-M _SP-MS 7 + -8 AND ; : _SP-B _SP-BS 7 + -8 AND ; : _SP-O _SP-OS 7 + -8 AND ;
VARIABLE _SP-MU VARIABLE _SP-OU VARIABLE _SP-REV VARIABLE _SP-VA VARIABLE _SP-VU
: _SP-LABEL S" Open:" ;
: _SP-VALUE S" notes.md" ;
: _SP-FDC1
    _SP-M 1024 _SP-B UFLD-BUILDER-INIT _SS-OK
    1 UFLD-K-TEXT _SP-REV @ 19 1 3 0 _SP-B UFLD-BEGIN _SS-OK
    0 0 1 5 0 6 1 13 _SP-B UFLD-SLOTS _SS-OK
    _SP-LABEL _SP-B UFLD-LABEL _SS-OK
    _SP-VA @ _SP-VU @ _SP-B UFLD-TEXT _SS-OK
    _SP-B UFLD-FINISH _SS-OK _SP-MU !
    _SP-M _SP-MU @ _SP-O 1024 UFLDC-PACK _SS-OK _SP-OU ! ;
\ The prompt now shows VALUE at REVISION, as typing leaves it.
: _SP-TYPED ( a u revision -- )
    _SP-REV ! _SP-VU ! _SP-VA ! _SP-FDC1
    _SP-OU @ _SP-FIELD _RTE-CONTROL.CONTENT-U ! _SP-VU @ _SP-FIELD _RTE-CONTROL.CONTENT-UTF8 ! ;
: _SP-CANDIDATE ( row -- )
    _SP-ROW ! 1 _SP-REV ! _SP-VALUE _SP-VU ! _SP-VA ! _SP-FDC1
    _SX-CI _SP-CI RTE-CONTROL-SIZE MOVE
    _SP-FIELD RTE-CONTROL-SIZE 0 FILL
    88 _SP-FIELD _RTE-CONTROL.OWNER ! 99 _SP-FIELD _RTE-CONTROL.GENERATION !
    101 _SP-FIELD _RTE-CONTROL.ID ! RTE-CONTROL-FIELD _SP-FIELD _RTE-CONTROL.KIND !
    3 _SP-FIELD _RTE-CONTROL.STATE ! 10 _SP-FIELD _RTE-CONTROL.REGION !
    _SP-ROW @ _SP-FIELD _RTE-CONTROL.ROW ! 0 _SP-FIELD _RTE-CONTROL.COL !
    1 _SP-FIELD _RTE-CONTROL.HEIGHT ! 19 _SP-FIELD _RTE-CONTROL.WIDTH !
    12 _SP-FIELD _RTE-CONTROL.ROOT-HEIGHT ! 32 _SP-FIELD _RTE-CONTROL.ROOT-WIDTH !
    _SP-LABEL _SP-FIELD _RTE-CONTROL.LABEL-U ! _SP-FIELD _RTE-CONTROL.LABEL-A !
    _SP-O _SP-FIELD _RTE-CONTROL.CONTENT-A ! _SP-OU @ _SP-FIELD _RTE-CONTROL.CONTENT-U !
    _SP-VU @ _SP-FIELD _RTE-CONTROL.CONTENT-UTF8 !
    _SP-CI _SX-P _RTHP.CONTROLS-A ! 2 _SX-P _RTHP.CONTROL-COUNT !
    _SP-CX RUCP-CORRELATION-SIZE 2 * 0 FILL
    77 _SP-CX ! 77 _SP-CX RUCP-CORRELATION-SIZE + !
    UFLSN-SOURCE-OVERLAY _SP-CX RUCP-CORRELATION-SIZE + 8 + !
    _SP-CX _SX-P _RTHP.CORR-A !
    102 _SX-SI _RTE-STATIC.ID ! 102 _SX-P _RTHP.STATIC-LAST ! ;
: _SP-DIALOGS RTE-F-DIALOGS _SX-P _RTHP.LIMITS _RTE-L.FEATURES ! ;
: _SP-BATCH ( part -- batch ) DUP RSHSP-PART.BATCH @ + ;
: _SP-CONTROL ( kind part -- control|0 )
    _SP-BATCH DUP _RTE-FB.FAMILIES-A @ SWAP _RTE-FB.FAMILIES-U @ 64 / 0 ?DO
        DUP I 64 * + DUP _RTE-FE.KIND @ RTE-FAMILY-CONTROL = IF
            RTE-FAMILY-ITEMS@ RTE-CONTROL-SIZE / 0 ?DO
                DUP I RTE-CONTROL-SIZE * + DUP _RTE-CONTROL.KIND @ 4 PICK = IF
                    >R DROP 2DROP R> UNLOOP UNLOOP EXIT THEN DROP
            LOOP DROP
        ELSE DROP THEN
    LOOP 2DROP 0 ;
: _SP-REGION ( id part -- row|0 ) _SP-BATCH _RTE-FB.CATALOG-A @ RTE-REGION-CATALOG-FIND ;
\ The catalog's modal regions: how many, and the last.
VARIABLE _SP-MODAL
: _SP-MODALS ( part -- n )
    0 _SP-MODAL ! 0 SWAP _SP-BATCH _RTE-FB.CATALOG-A @
    DUP _RTE-RC.REGIONS-A @ SWAP _RTE-RC.REGIONS-U @ 96 / 0 ?DO
        DUP I 96 * + DUP _RTE-IR.FLAGS @ RTE-REGION-MODAL AND IF
            _SP-MODAL ! SWAP 1+ SWAP ELSE DROP THEN
    LOOP DROP ;
\ The pane's content region holds the document's ordinary control.
: _SP-CONTENT ( part -- row ) 1 OVER _SP-CONTROL _RTE-CONTROL.REGION @ SWAP _SP-REGION ;
'''

STAGED_PROMPT = STAGED + PROMPT


def test_a_pane_prompt_takes_a_modal_region_over_the_pane_content():
    staged_run(STAGED_PROMPT + r'''
_SX-SETUP 8 _SP-CANDIDATE ' _SP-PAINT DRW-OVERLAY _SP-DIALOGS
_RSHSP-PREPARE _SS-OK
_SX-KA _SX-PART-VALID? _SS-A _SX-KA _SP-BATCH RTE-FAMILY-BATCH-VALID? _SS-A
\ One modal region, the catalog's last, over the pane's content and above it.
_SX-KA _SP-MODALS 1 = _SS-A
_SP-MODAL @ _RTE-IR.ID @ _SX-KA RSHSP-PART.NEXT-REGION @ 1- = _SS-A
_SP-MODAL @ _RTE-IR.FLAGS @ RTE-REGION-VISIBLE RTE-REGION-CLIPPED OR RTE-REGION-MODAL OR = _SS-A
_SP-MODAL @ _RTE-IR.X @ 0= _SS-A _SP-MODAL @ _RTE-IR.Y @ 0= _SS-A
_SP-MODAL @ _RTE-IR.COLS @ 32 = _SS-A _SP-MODAL @ _RTE-IR.ROWS @ 12 = _SS-A
_SP-MODAL @ _RTE-IR.CLIP-X @ 0= _SS-A _SP-MODAL @ _RTE-IR.CLIP-Y @ 0= _SS-A
_SP-MODAL @ _RTE-IR.CLIP-COLS @ 19 = _SS-A _SP-MODAL @ _RTE-IR.CLIP-ROWS @ 9 = _SS-A
_SP-MODAL @ _RTE-IR.Z @ 2 = _SS-A
_SX-KA _SP-CONTENT DUP 0<> _SS-A
DUP _RTE-IR.CLIP-ROWS @ 9 = _SS-A _RTE-IR.Z @ 0= _SS-A
\ The prompt is in the modal region, the document's control stays beneath.
RTE-CONTROL-FIELD _SX-KA _SP-CONTROL DUP 0<> _SS-A
DUP _RTE-CONTROL.REGION @ _SP-MODAL @ _RTE-IR.ID @ = _SS-A
_RTE-CONTROL.ID @ 101 = _SS-A
1 _SX-KA _SP-CONTROL _RTE-CONTROL.REGION @ _SP-MODAL @ _RTE-IR.ID @ <> _SS-A
\ The admission emits the modal region with the rest.
_SX-KA _SP-BATCH _SX-FX RTE-FAMILY-BATCH-EMIT _SS-OK
_SX-REGIONS @ 5 = _SS-A
_SS-DONE
''', minimum=28)


def test_without_dialogs_the_prompt_stays_in_its_pane_content():
    staged_run(STAGED_PROMPT + r'''
_SX-SETUP 8 _SP-CANDIDATE ' _SP-PAINT DRW-OVERLAY
_RSHSP-PREPARE _SS-OK
_SX-KA _SX-PART-VALID? _SS-A
_SX-KA _SP-MODALS 0= _SS-A
RTE-CONTROL-FIELD _SX-KA _SP-CONTROL _RTE-CONTROL.REGION @
    1 _SX-KA _SP-CONTROL _RTE-CONTROL.REGION @ = _SS-A
_SS-DONE
''', minimum=6)


REFUSALS = {
    # Paint the prompt does not explain, inside the pane.
    "stray-paint": ": _SP-STRAY 88 7 3 DRW-CHAR ;\n"
    "_SX-SETUP 8 _SP-CANDIDATE ' _SP-PAINT DRW-OVERLAY ' _SP-STRAY DRW-OVERLAY",
    # A prompt over the pane's border row rather than its content.
    "border-row": "_SX-SETUP 9 _SP-CANDIDATE ' _SP-PAINT DRW-OVERLAY",
    # A prompt whose document is in no pane.
    "no-pane": "_SX-SETUP 8 _SP-CANDIDATE ' _SP-PAINT DRW-OVERLAY\n"
    "78 _SP-CX RUCP-CORRELATION-SIZE + !",
    # Two prompts for one pane.
    "two-prompts": "_SX-SETUP 8 _SP-CANDIDATE ' _SP-PAINT DRW-OVERLAY\n"
    "RTE-CONTROL-FIELD _SP-CI _RTE-CONTROL.KIND ! UFLSN-SOURCE-OVERLAY _SP-CX 8 + !",
}


@pytest.mark.parametrize("case", sorted(REFUSALS))
def test_other_paint_or_a_misplaced_prompt_refuses_the_shell_candidate(case):
    staged_run(STAGED_PROMPT + REFUSALS[case] + r'''
_SP-DIALOGS _RSHSP-PREPARE RTE-S-UNAVAILABLE = _SS-A
_RSHSP-PENDING-PART 0= _SS-A
_SS-DONE
''', minimum=2)


DELTA_PROMPT = DELTA + PROMPT + r'''
\ The pending target bank carries both controls with their identities.
: _SP-PENDING ( bank -- )
    DUP 4096 0 FILL DUP _SX-BANK
    2 OVER _RTHP-TB.CONTROL-COUNT !
    _SP-CI OVER _RTHP-PACK-CONTROLS-A RTE-CONTROL-SIZE 2 * MOVE
    _SP-CX OVER _RTHP-PACK-CORR-A RUCP-CORRELATION-SIZE 2 * MOVE
    _SX-P _RTHP.TARGET-PENDING ! ;
: _SP-HELLO-PROMPT _SD-HELLO ['] _SP-PAINT DRW-OVERLAY ;
: _SP-HELLP-PROMPT _SD-HELLP ['] _SP-PAINT DRW-OVERLAY ;
\ The application repaints the row the prompt held once it closes.
: _SP-CLOSED _SD-HELLP 19 0 DO 32 8 I DRW-CHAR LOOP ;
'''


def test_a_delta_keeps_the_prompts_modal_region_and_a_closed_prompt_restarts():
    """While the prompt is open a DELTA keeps its region, and typing replaces
    only its field; closing it restarts."""
    staged_run(DELTA_PROMPT + r'''
_SX-SETUP _SD-HOOKS 8 _SP-CANDIDATE _SP-DIALOGS
' _SP-HELLO-PROMPT _SD-DRAW _RSHSP-PREPARE _SS-OK _SD-ACK
_RSHSP-ACTIVE-PART _SX-KA = _SS-A _SX-KA _SP-MODALS 1 = _SS-A
\ A changed letter in the pane while the prompt stays open is a DELTA.
' _SP-HELLP-PROMPT _SD-DRAW _SD-TA _SP-PENDING
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
_SX-KB _SX-PART-VALID? _SS-A _SD-CATALOGS= _SS-A
_SX-KB _SP-MODALS 1 = _SS-A
RTE-CONTROL-FIELD _SX-KB _SP-CONTROL _RTE-CONTROL.REGION @ _SP-MODAL @ _RTE-IR.ID @ = _SS-A
_SD-EMIT _SS-OK _SD-GREPLACE @ 1 = _SS-A _SD-CREPLACE @ 0= _SS-A
_SD-ACK _RSHSP-ACTIVE-PART _SX-KB = _SS-A
\ A typed character changes only the prompt's content: one CONTROL-REPLACE.
\ The producer packs each frame into the bank the frame on screen is not.
: _SP-NEXT S" notes.mdx" ; _SP-NEXT 2 _SP-TYPED
' _SP-HELLP-PROMPT _SD-DRAW _SD-TB _SP-PENDING
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
_SX-KA _SX-PART-VALID? _SS-A _SD-CATALOGS= _SS-A
_SD-EMIT _SS-OK _SD-CREPLACE @ 1 = _SS-A _SD-GREPLACE @ 0= _SS-A _SD-GDEFINE @ 0= _SS-A
_SD-ACK _RSHSP-ACTIVE-PART _SX-KA = _SS-A
\ With the prompt closed the catalog loses its modal region: a START.
_SX-CI _SX-P _RTHP.CONTROLS-A ! 1 _SX-P _RTHP.CONTROL-COUNT ! _SX-CX _SX-P _RTHP.CORR-A !
' _SP-CLOSED _SD-DRAW _SD-TA _SD-PENDING
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE RTE-S-OK <> _SS-A
_RSHSP-DIAG-STAGE @ 1 = _SS-A
_RSHSP-PENDING-PART 0= _SS-A
_RSHSP-PREPARE _SS-OK _RSHSP-PENDING-PART _SX-KB = _SS-A _SX-KB _SP-MODALS 0= _SS-A
_SS-DONE
''', minimum=20)


# Desk's own Ask prompt.  While it is open Desk hides its taskbar, blocks
# input to its panes, and paints the prompt over the taskbar row, the
# screen's last, as an overlay; its shell model carries the prompt's TEXT
# field after every string.  Each draw here rebuilds the model as Desk does:
# the pane alone, and while _SQ-ON is set the prompt "Ask:" showing VALUE at
# REVISION, one row as wide as the screen.  A closed prompt gives the row
# back to an empty taskbar.
DESK_PROMPT = DELTA_PROMPT + r'''
CREATE _SQ-BS 47 ALLOT : _SQ-B _SQ-BS 7 + -8 AND ;
VARIABLE _SQ-ON VARIABLE _SQ-REV VARIABLE _SQ-VA VARIABLE _SQ-VU
: _SQ-FIELD ( dst cap -- bytes status )
    _SQ-B UFLD-BUILDER-INIT ?DUP IF 0 SWAP EXIT THEN
    1 UFLD-K-TEXT _SQ-REV @ 32 1 7 0 _SQ-B UFLD-BEGIN ?DUP IF 0 SWAP EXIT THEN
    0 1 1 4 0 6 1 26 _SQ-B UFLD-SLOTS ?DUP IF 0 SWAP EXIT THEN
    S" Ask:" _SQ-B UFLD-LABEL ?DUP IF 0 SWAP EXIT THEN
    _SQ-VA @ _SQ-VU @ _SQ-B UFLD-TEXT ?DUP IF 0 SWAP EXIT THEN
    _SQ-B UFLD-FINISH ;
: _SQ-MODEL ( -- )
    _SS-M SHM.EPOCH @ 4096 4 _SS-M SHM-INIT _SS-A _SS-M SHM.EPOCH !
    _SX-I @ CINST.ID @ _SS-M SHM.OWNER-ID !
    _SX-I @ CINST.GENERATION @ _SS-M SHM.OWNER-GEN !
    32 _SS-M SHM.WIDTH ! 12 _SS-M SHM.HEIGHT !
    _SQ-ON @ IF SHM-F-TASKBAR-HIDDEN SHM-F-INPUT-BLOCKED OR _SS-M SHM.FLAGS ! THEN
    _SS-M SHM-APPEND DUP _SS-E !
    11 OVER SHME.KEY ! SHM-K-PANE OVER SHME.KIND ! 1 OVER SHME.FLAGS !
    10 OVER SHME.HEIGHT ! 20 OVER SHME.WIDTH !
    9 OVER SHME.CONTENT-H ! 19 OVER SHME.CONTENT-W !
    _SX-CHILD @ CINST.ID @ OVER SHME.OWNER-ID !
    _SX-CHILD @ CINST.GENERATION @ OVER SHME.OWNER-GEN !
    11 OVER SHME.IDENTITY ! 11 SWAP SHME.ACTION !
    S" Editor" _SS-M SHM-COPY$ _SS-A _SS-E @ SHME.TITLE-OFF ! 6 _SS-E @ SHME.TITLE-U !
    _SQ-ON @ IF
        _SS-M SHM-PROMPT-ROOM _SS-A _SQ-FIELD _SS-OK _SS-M SHM-PROMPT-TAKE _SS-A
    THEN
    _SS-M SHM-SEAL ;
: _SQ-ROW 32 0 DO 65 11 I DRW-CHAR LOOP ;
\ The pane's HELLO, with the prompt over the taskbar row while it is open.
: _SQ-PAINT _SD-HELLO _SQ-MODEL
    _SQ-ON @ IF ['] _SQ-ROW DRW-OVERLAY ELSE 32 0 DO 32 11 I DRW-CHAR LOOP THEN ;
: _SQ-OPEN ( a u revision -- )
    _SQ-REV ! _SQ-VU ! _SQ-VA ! -1 _SQ-ON ! ['] _SQ-PAINT _SD-DRAW ;
: _SQ-CLOSE ( -- ) 0 _SQ-ON ! ['] _SQ-PAINT _SD-DRAW ;
: _SQ-VALUE S" hi" ;
: _SQ-PROMPT ( part -- control|0 ) RTE-CONTROL-FIELD SWAP _SP-CONTROL ;
: _SQ-REGIONS ( part -- n ) _SP-BATCH _RTE-FB.CATALOG-A @ _RTE-RC.REGIONS-U @ 96 / ;
'''


def test_desks_prompt_is_a_field_on_the_taskbar_row_in_a_whole_screen_modal_scope():
    staged_run(DESK_PROMPT + r'''
_SX-SETUP _SD-HOOKS _SP-DIALOGS
_SQ-VALUE 1 _SQ-OPEN _RSHSP-PREPARE _SS-OK
_SX-KA _SX-PART-VALID? _SS-A _SX-KA _SP-BATCH RTE-FAMILY-BATCH-VALID? _SS-A
\ One modal region, the catalog's last, over the whole screen above the rest.
_SX-KA _SP-MODALS 1 = _SS-A
_SP-MODAL @ _RTE-IR.ID @ _SX-KA RSHSP-PART.NEXT-REGION @ 1- = _SS-A
_SP-MODAL @ _RTE-IR.FLAGS @ RTE-REGION-VISIBLE RTE-REGION-CLIPPED OR RTE-REGION-MODAL OR = _SS-A
_SP-MODAL @ _RTE-IR.CLIP-X @ 0= _SS-A _SP-MODAL @ _RTE-IR.CLIP-Y @ 0= _SS-A
_SP-MODAL @ _RTE-IR.CLIP-COLS @ 32 = _SS-A _SP-MODAL @ _RTE-IR.CLIP-ROWS @ 12 = _SS-A
_SP-MODAL @ _RTE-IR.Z @ 3 = _SS-A
\ The prompt is a FIELD across the taskbar row, after the application's
\ control, and the part names it.
_SX-KA _SQ-PROMPT DUP 0<> _SS-A
DUP _RTE-CONTROL.REGION @ _SP-MODAL @ _RTE-IR.ID @ = _SS-A
DUP _RTE-CONTROL.ID @ 101 = _SS-A
DUP _RTE-CONTROL.ID @ _SX-KA RSHSP-PART.PROMPT @ = _SS-A
DUP _RTE-CONTROL.ROW @ 11 = _SS-A DUP _RTE-CONTROL.COL @ 0= _SS-A
DUP _RTE-CONTROL.HEIGHT @ 1 = _SS-A DUP _RTE-CONTROL.WIDTH @ 32 = _SS-A
DUP _RTE-CONTROL.LABEL-A @ OVER _RTE-CONTROL.LABEL-U @ S" Ask:" STR-STR= _SS-A
_RTE-CONTROL.CONTENT-UTF8 @ 2 = _SS-A
\ The application's control stays beneath it, in the pane.
1 _SX-KA _SP-CONTROL _RTE-CONTROL.REGION @ _SP-MODAL @ _RTE-IR.ID @ <> _SS-A
\ The admission emits every region of the catalog.
_SX-KA _SP-BATCH _SX-FX RTE-FAMILY-BATCH-EMIT _SS-OK
_SX-REGIONS @ _SX-KA _SQ-REGIONS = _SS-A
_SS-DONE
''', minimum=26)


def test_without_dialogs_desks_prompt_holds_only_the_taskbar_row():
    staged_run(DESK_PROMPT + r'''
_SX-SETUP _SD-HOOKS
_SQ-VALUE 1 _SQ-OPEN _RSHSP-PREPARE _SS-OK
_SX-KA _SX-PART-VALID? _SS-A _SX-KA _SP-MODALS 0= _SS-A
_SX-KA _SQ-PROMPT DUP 0<> _SS-A
_RTE-CONTROL.REGION @ _SX-KA _SP-REGION DUP 0<> _SS-A
DUP _RTE-IR.FLAGS @ RTE-REGION-VISIBLE RTE-REGION-CLIPPED OR = _SS-A
DUP _RTE-IR.CLIP-X @ 0= _SS-A DUP _RTE-IR.CLIP-Y @ 11 = _SS-A
DUP _RTE-IR.CLIP-COLS @ 32 = _SS-A DUP _RTE-IR.CLIP-ROWS @ 1 = _SS-A
_RTE-IR.Z @ 3 = _SS-A
_SS-DONE
''', minimum=12)


def test_typing_in_desks_prompt_replaces_its_field_and_closing_it_restarts():
    """Positions in the prompt's value are input targets; typing is a DELTA
    that replaces only the field under its acknowledged identity; closing the
    prompt gives the taskbar row back with a START."""
    staged_run(DESK_PROMPT + r'''
_SX-SETUP _SD-HOOKS _SP-DIALOGS
_SQ-VALUE 1 _SQ-OPEN _RSHSP-PREPARE _SS-OK _SD-ACK
_RSHSP-ACTIVE-PART _SX-KA = _SS-A _RSHSP-CURRENT? _SS-A
_SX-KA _SX-PART-VALID? _SS-A
\ PLACE and EXTEND name positions in the value, from its first cell on the
\ taskbar row, against the field's revision; nothing else targets it.
_SX-KA RSHSP-PART.PROMPT @ DUP 0<> _SS-A _RSHSP-INPUT-ID !
_RSHSP-CONTROL-FIND DUP 0<> _SS-A _RTE-CONTROL.KIND @ RTE-CONTROL-FIELD = _SS-A
RTE-INTENT-PLACE _RSHSP-INPUT-INTENT ! _RSHSP-PROMPT-TARGET _SS-A
    1 = _SS-A 6 = _SS-A 11 = _SS-A
RTE-INTENT-EXTEND _RSHSP-INPUT-INTENT ! _RSHSP-PROMPT-TARGET _SS-A 2DROP DROP
RTE-INTENT-ACTIVATE _RSHSP-INPUT-INTENT ! _RSHSP-PROMPT-TARGET 0= _SS-A 2DROP DROP
\ A typed character changes only the prompt's field: one CONTROL-REPLACE
\ under the identity the terminal acknowledged.
: _SQ-NEXT S" hi!" ; _SQ-NEXT 2 _SQ-OPEN _SD-TA _SD-PENDING
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
_SX-KB _SX-PART-VALID? _SS-A _SD-CATALOGS= _SS-A
_SX-KB RSHSP-PART.PROMPT @ _SX-KA RSHSP-PART.PROMPT @ = _SS-A
_SX-KB _SQ-PROMPT _RTE-CONTROL.CONTENT-UTF8 @ 3 = _SS-A
_SD-EMIT _SS-OK _SD-CREPLACE @ 1 = _SS-A _SD-GREPLACE @ 0= _SS-A _SD-GDEFINE @ 0= _SS-A
_SD-ACK _RSHSP-ACTIVE-PART _SX-KB = _SS-A
\ The same field again is a DELTA with nothing to send.
_SQ-NEXT 2 _SQ-OPEN _SD-TB _SD-PENDING
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
_SD-EMIT _SS-OK _SD-CREPLACE @ 0= _SS-A _SD-GREPLACE @ 0= _SS-A
_SD-ACK _RSHSP-ACTIVE-PART _SX-KA = _SS-A
\ With the prompt closed the shell model changes: a START, with no modal
\ region and no prompt.
_SQ-CLOSE _SD-TA _SD-PENDING
_RSHSP-DELTA-PROBE RTE-S-OK <> _SS-A
_RSHSP-PREPARE _SS-OK _RSHSP-PENDING-PART _SX-KB = _SS-A
_SX-KB _SP-MODALS 0= _SS-A _SX-KB RSHSP-PART.PROMPT @ 0= _SS-A
_SX-KB _SQ-PROMPT 0= _SS-A
_SS-DONE
''', minimum=36)
