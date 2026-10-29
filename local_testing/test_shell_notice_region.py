"""The app shell's notice: the shell gives it a region of its own above the
taskbar, as a DIALOG with the NOTICE flag, and keeps the taskbar it covers."""

from test_shell_prompt_region import DESK_PROMPT
from test_shell_screen_producer import staged_run


# The staged model's taskbar holds a task over columns 0 to 3 and a launcher
# over 6 to 8 of the bottom row, row 11.  A notice "Saved" nine cells wide
# lies over columns 2 to 10, so it covers part of the task band, the gap
# after the divider and the whole launcher band.  Each draw takes the notice
# out of the model and, while _SN-ON is set, puts it back with SEVERITY and
# TEXT, and paints its bar over those cells as the app shell does.
NOTICE = DESK_PROMPT + r'''
VARIABLE _SN-ON VARIABLE _SN-USED VARIABLE _SN-SEVERITY VARIABLE _SN-COL
VARIABLE _SN-TA VARIABLE _SN-TU
: _SN-SAVED S" Saved" ;
: _SN-NOTICE ( dst -- bytes )
    >R 5 1 _SN-TU @ 4 + 1 UDLG-F-NOTICE _SN-SEVERITY @ R@ UDLG-START
    0 2 1 _SN-TU @ R@ UDLG-MESSAGE-SLOT! _SN-TA @ _SN-TU @ R@ UDLG-LINE+
    R> UDLG-BYTES@ ;
\ The model without its notice, unsealed.
: _SN-STRIP ( -- )
    0 _SS-M SHM.READY !
    _SS-M SHM.NOTICE-U @ IF _SN-USED @ _SS-M SHM.USED ! THEN
    0 _SS-M SHM.NOTICE-OFF ! 0 _SS-M SHM.NOTICE-U !
    0 _SS-M SHM.NOTICE-ROW ! 0 _SS-M SHM.NOTICE-COL ! ;
: _SN-PUT ( -- )
    _SS-M SHM-NOTICE-ROOM _SS-A DROP _SN-NOTICE >R
    11 _SN-COL @ R> _SS-M SHM-NOTICE-TAKE _SS-A ;
: _SN-BAR _SN-TU @ 4 + 0 DO 61 11 _SN-COL @ I + DRW-CHAR LOOP ;
\ Each draw paints the taskbar row afresh, as Desk does, then the bar.
: _SN-PAINT ( -- )
    _SD-HELLO 32 0 DO 32 11 I DRW-CHAR LOOP _SN-STRIP
    _SN-ON @ IF _SN-PUT ['] _SN-BAR DRW-OVERLAY THEN _SS-M SHM-SEAL ;
: _SN-SHOW ( a u severity -- ) _SN-SEVERITY ! _SN-TU ! _SN-TA ! -1 _SN-ON ! ;
: _SN-HIDE ( -- ) 0 _SN-ON ! ;
: _SN-SETUP ( -- )
    _SX-SETUP _SD-HOOKS _SS-M SHM.USED @ _SN-USED ! 2 _SN-COL ! ;
\ The catalog's notice region: VISIBLE and CLIPPED, not modal, its clip the
\ notice.
VARIABLE _SN-REGION
: _SN-REGIONS ( part -- n )
    0 _SN-REGION ! 0 SWAP _SP-BATCH _RTE-FB.CATALOG-A @
    DUP _RTE-RC.REGIONS-A @ SWAP _RTE-RC.REGIONS-U @ 96 / 0 ?DO
        DUP I 96 * + DUP _RTE-IR.CLIP-Y @ 11 = OVER _RTE-IR.CLIP-ROWS @ 1 = AND
        OVER _RTE-IR.CLIP-COLS @ 9 = AND IF
            _SN-REGION ! SWAP 1+ SWAP ELSE DROP THEN
    LOOP DROP ;
: _SN-DIALOG ( part -- control|0 ) RTE-CONTROL-DIALOG SWAP _SP-CONTROL ;
: _SN-TASK ( part -- control|0 ) RTE-CONTROL-TASK SWAP _SP-CONTROL ;
: _SN-LAUNCHER ( part -- control|0 ) RTE-CONTROL-LAUNCHER SWAP _SP-CONTROL ;
'''


def test_a_notice_lies_in_a_region_of_its_own_above_the_taskbar_it_covers():
    staged_run(NOTICE + r'''
_SN-SETUP _SP-DIALOGS
_SN-SAVED 3 _SN-SHOW ' _SN-PAINT _SD-DRAW _SX-PACK-PREPARE _SS-OK
_SX-KA _SX-PART-VALID? _SS-A _SX-KA _SP-BATCH RTE-FAMILY-BATCH-VALID? _SS-A
\ One region of the notice's cells, the catalog's last, above the rest and
\ no modal scope.
_SX-KA _SN-REGIONS 1 = _SS-A
_SN-REGION @ _RTE-IR.ID @ _SX-KA RSHSP-PART.NEXT-REGION @ 1- = _SS-A
_SN-REGION @ _RTE-IR.FLAGS @ RTE-REGION-VISIBLE RTE-REGION-CLIPPED OR = _SS-A
_SN-REGION @ _RTE-IR.COLS @ 32 = _SS-A _SN-REGION @ _RTE-IR.ROWS @ 12 = _SS-A
_SN-REGION @ _RTE-IR.CLIP-X @ 2 = _SS-A _SN-REGION @ _RTE-IR.Z @ 4 = _SS-A
_SX-KA _SP-MODALS 0= _SS-A
\ The notice is a DIALOG there, with its DLG1, after the application's
\ control and the taskbar's.
_SX-KA _SN-DIALOG DUP 0<> _SS-A
DUP _RTE-CONTROL.REGION @ _SN-REGION @ _RTE-IR.ID @ = _SS-A
DUP _RTE-CONTROL.STATE @ RTE-CONTROL-VISIBLE = _SS-A
DUP _RTE-CONTROL.ROW @ 11 = _SS-A DUP _RTE-CONTROL.COL @ 2 = _SS-A
DUP _RTE-CONTROL.HEIGHT @ 1 = _SS-A DUP _RTE-CONTROL.WIDTH @ 9 = _SS-A
DUP _RTE-CONTROL.LABEL-U @ 0= _SS-A DUP _RTE-CONTROL.CONTENT-UTF8 @ 5 = _SS-A
DUP _RTE-CONTROL.ID @ _SX-KA _SN-LAUNCHER _RTE-CONTROL.ID @ > _SS-A
DUP _RTE-CONTROL.CONTENT-A @ OVER _RTE-CONTROL.CONTENT-U @ 0 0 9 1 DLG1-VALIDATE
    _SS-A 5 = _SS-A
_RTE-CONTROL.CONTENT-A @ 6 + C@ 1 = _SS-A
\ The taskbar it covers stays semantic beneath it.
_SX-KA _SN-TASK 0<> _SS-A _SX-KA _SN-LAUNCHER 0<> _SS-A
\ The admission emits every region of the catalog.
_SX-KA _SP-BATCH _SX-FX RTE-FAMILY-BATCH-EMIT _SS-OK
_SX-REGIONS @ _SX-KA _SQ-REGIONS = _SS-A
_SS-DONE
''', minimum=48)


def test_without_dialogs_a_notice_is_paint_and_the_taskbar_under_it_residual():
    staged_run(NOTICE + r'''
_SN-SETUP
_SN-SAVED 3 _SN-SHOW ' _SN-PAINT _SD-DRAW _SX-PACK-PREPARE _SS-OK
_SX-KA _SX-PART-VALID? _SS-A
_SX-KA _SN-REGIONS 0= _SS-A _SX-KA _SN-DIALOG 0= _SS-A
_SX-KA _SN-TASK 0= _SS-A _SX-KA _SN-LAUNCHER 0= _SS-A
_SS-DONE
''', minimum=26)


def test_paint_beside_the_notice_leaves_the_taskbar_residual():
    staged_run(NOTICE + r'''
_SN-SETUP _SP-DIALOGS
: _SN-STRAY-CELL 88 11 1 DRW-CHAR ;
: _SN-STRAY _SN-PAINT ['] _SN-STRAY-CELL DRW-OVERLAY ;
_SN-SAVED 3 _SN-SHOW ' _SN-STRAY _SD-DRAW _SX-PACK-PREPARE _SS-OK
_SX-KA _SN-DIALOG 0<> _SS-A _SX-KA _SN-TASK 0= _SS-A _SX-KA _SN-LAUNCHER 0= _SS-A
_SS-DONE
''', minimum=24)


def test_a_notice_stays_a_delta_and_one_that_comes_or_goes_restarts():
    staged_run(NOTICE + r'''
_SN-SETUP _SP-DIALOGS
_SN-SAVED 3 _SN-SHOW ' _SN-PAINT _SD-DRAW _SX-PACK-PREPARE _SS-OK _SD-ACK
_RSHSP-ACTIVE-PART _SX-KA = _SS-A
\ A changed letter in the pane with the same notice is a DELTA that keeps
\ the notice's region and identity and sends nothing for it.
: _SN-HELLP _SN-PAINT 80 5 6 DRW-CHAR ;
' _SN-HELLP _SD-DRAW _SD-TA _SD-PENDING
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
_SX-KB _SX-PART-VALID? _SS-A _SD-CATALOGS= _SS-A
_SX-KB _SN-DIALOG _RTE-CONTROL.ID @ _SX-KA _SN-DIALOG _RTE-CONTROL.ID @ = _SS-A
_SD-EMIT _SS-OK _SD-GREPLACE @ 1 = _SS-A _SD-CREPLACE @ 0= _SS-A
_SD-ACK _RSHSP-ACTIVE-PART _SX-KB = _SS-A
\ Another notice in its place is a START.
: _SN-FAILED S" Fail!" ; _SN-FAILED 4 _SN-SHOW
' _SN-HELLP _SD-DRAW _SD-TB _SD-PENDING
_RSHSP-DELTA-PROBE RTE-S-OK <> _SS-A
_SX-PACK-PREPARE _SS-OK _RSHSP-PENDING-PART _SX-KA = _SS-A
_SX-KA _SN-DIALOG _RTE-CONTROL.CONTENT-A @ 16 + C@ 4 = _SS-A _SD-ACK
\ A notice that ends is a START with no notice region.
_SN-HIDE ' _SN-HELLP _SD-DRAW _SD-TA _SD-PENDING
_RSHSP-DELTA-PROBE RTE-S-OK <> _SS-A
_SX-PACK-PREPARE _SS-OK _SX-KB _SN-REGIONS 0= _SS-A _SX-KB _SN-DIALOG 0= _SS-A
_SX-KB _SN-TASK 0<> _SS-A
_SS-DONE
''', minimum=53)


# Desk's prompt and a notice together: the prompt's model is built by the
# prompt test's own words, and the notice follows it.
def test_a_notice_lies_above_desks_prompt_and_typing_keeps_both():
    staged_run(NOTICE + r'''
_SX-SETUP _SD-HOOKS _SP-DIALOGS 2 _SN-COL !
: _SN-PROMPT-PAINT _SQ-PAINT
    0 _SS-M SHM.READY ! _SS-M SHM.USED @ _SN-USED !
    _SN-PUT ['] _SN-BAR DRW-OVERLAY _SS-M SHM-SEAL ;
_SN-SAVED 0 _SN-SHOW
_SQ-VALUE _SQ-VU ! _SQ-VA ! 1 _SQ-REV ! -1 _SQ-ON !
' _SN-PROMPT-PAINT _SD-DRAW _SX-PACK-PREPARE _SS-OK _SD-ACK
_SX-KA _SX-PART-VALID? _SS-A
\ The prompt's whole-screen modal region, and the notice's above it.
_SX-KA _SP-MODALS 1 = _SS-A _SP-MODAL @ _RTE-IR.Z @ 3 = _SS-A
_SX-KA _SN-REGIONS 1 = _SS-A _SN-REGION @ _RTE-IR.Z @ 4 = _SS-A
_SX-KA _SQ-PROMPT 0<> _SS-A _SX-KA _SN-DIALOG 0<> _SS-A
_SX-KA _SN-DIALOG _RTE-CONTROL.ID @ _SX-KA _SQ-PROMPT _RTE-CONTROL.ID @ 1+ = _SS-A
\ A typed character moves the notice in the model, but only the prompt's
\ field is replaced.
: _SN-NEXT S" hello there" ; _SN-NEXT _SQ-VU ! _SQ-VA ! 2 _SQ-REV !
' _SN-PROMPT-PAINT _SD-DRAW _SD-TA _SD-PENDING
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
_SX-KB _SX-PART-VALID? _SS-A _SD-CATALOGS= _SS-A
_SX-KB DUP RSHSP-PART.MODEL @ + SHM.NOTICE-OFF @
    _SX-KA DUP RSHSP-PART.MODEL @ + SHM.NOTICE-OFF @ <> _SS-A
_SD-EMIT _SS-OK _SD-CREPLACE @ 1 = _SS-A _SD-GREPLACE @ 0= _SS-A _SD-GDEFINE @ 0= _SS-A
_SS-DONE
''', minimum=53)
