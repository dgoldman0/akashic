"""Desk's status: the shell gives it a region of its own across the taskbar's
right end, as a STATUS_FIELD, and keeps it across DELTAs."""

from test_shell_notice_region import NOTICE
from test_shell_screen_producer import staged_run


# The staged model's taskbar ends at column 10 of the bottom row, row 11.
# Each draw takes Desk's status out of the model and, while _SF-ON is set,
# puts it back as "[Agent: VALUE]" with SEVERITY, its label's slot the eight
# cells of "[Agent: ", one cell before the row's right end, and paints its
# cells as Desk does.  "ready" lies over columns 17 to 30.
STATUS = NOTICE + r'''
VARIABLE _SF-ON VARIABLE _SF-USED VARIABLE _SF-SEVERITY
VARIABLE _SF-VA VARIABLE _SF-VU VARIABLE _SF-SREPLACE
: _SF-AGENT S" Agent" ;
: _SF-READY S" ready" ;
: _SF-W ( -- cells ) _SF-VU @ 9 + ;
: _SF-COL ( -- col ) 31 _SF-W - ;
: _SF-STATUS ( dst cap -- bytes )
    >R >R 1 _SF-W 8 _SF-SEVERITY @ USF-F-VISIBLE _SF-AGENT _SF-VA @ _SF-VU @
    R> R> USF-INIT _SS-OK ;
\ The model without its status, unsealed.
: _SF-STRIP ( -- )
    0 _SS-M SHM.READY !
    _SS-M SHM.STATUS-U @ IF _SF-USED @ _SS-M SHM.USED ! THEN
    0 _SS-M SHM.STATUS-OFF ! 0 _SS-M SHM.STATUS-U !
    0 _SS-M SHM.STATUS-ROW ! 0 _SS-M SHM.STATUS-COL ! ;
: _SF-PUT ( -- )
    _SS-M SHM-STATUS-ROOM _SS-A _SF-STATUS >R
    11 _SF-COL R> _SS-M SHM-STATUS-TAKE _SS-A ;
: _SF-TEXT ( a u col -- ) SWAP 0 ?DO OVER I + C@ 11 2 PICK I + DRW-CHAR LOOP 2DROP ;
: _SF-CELLS ( -- )
    91 11 _SF-COL DRW-CHAR _SF-AGENT _SF-COL 1+ _SF-TEXT
    58 11 _SF-COL 6 + DRW-CHAR 32 11 _SF-COL 7 + DRW-CHAR
    _SF-VA @ _SF-VU @ _SF-COL 8 + _SF-TEXT 93 11 _SF-COL _SF-W + 1- DRW-CHAR ;
\ Each draw paints the taskbar row afresh, as Desk does, then the status.
: _SF-PAINT ( -- )
    _SD-HELLO 32 0 DO 32 11 I DRW-CHAR LOOP _SF-STRIP
    _SF-ON @ IF _SF-PUT _SF-CELLS THEN _SS-M SHM-SEAL ;
: _SF-SHOW ( a u severity -- ) _SF-SEVERITY ! _SF-VU ! _SF-VA ! -1 _SF-ON ! ;
: _SF-HIDE ( -- ) 0 _SF-ON ! ;
: _SF-FIELDS ( -- )
    _SX-P _RTHP.LIMITS _RTE-L.FEATURES DUP @ RTE-F-STATUS-FIELDS OR SWAP ! ;
: _SF-STATIC-REPLACE ( static context -- status ) 2DROP 1 _SF-SREPLACE +! RTE-S-OK ;
: _SF-SETUP ( -- )
    _SN-SETUP _SS-M SHM.USED @ _SF-USED ! 0 _SF-SREPLACE !
    ['] _SF-STATIC-REPLACE _SX-F _RTE-F.STATIC-REPLACE-XT ! ;
\ The catalog's status region: VISIBLE and CLIPPED, not modal, its clip the
\ taskbar row past its entries.
VARIABLE _SF-REGION
: _SF-REGIONS ( part -- n )
    0 _SF-REGION ! 0 SWAP _SP-BATCH _RTE-FB.CATALOG-A @
    DUP _RTE-RC.REGIONS-A @ SWAP _RTE-RC.REGIONS-U @ 96 / 0 ?DO
        DUP I 96 * + DUP _RTE-IR.CLIP-Y @ 11 = OVER _RTE-IR.CLIP-ROWS @ 1 = AND
        OVER _RTE-IR.CLIP-X @ 10 = AND OVER _RTE-IR.CLIP-COLS @ 22 = AND IF
            _SF-REGION ! SWAP 1+ SWAP ELSE DROP THEN
    LOOP DROP ;
\ The first STATUS_FIELD static on ROW, or 0.
: _SF-STATIC-ON ( row part -- static|0 )
    _SP-BATCH DUP _RTE-FB.FAMILIES-A @ SWAP _RTE-FB.FAMILIES-U @ 64 / 0 ?DO
        DUP I 64 * + DUP _RTE-FE.KIND @ RTE-FAMILY-STATIC = IF
            RTE-FAMILY-ITEMS@ RTE-STATIC-SIZE / 0 ?DO
                DUP I RTE-STATIC-SIZE * + DUP _RTE-STATIC.ROW @ 4 PICK =
                OVER _RTE-STATIC.KIND @ RTE-STATIC-STATUS-FIELD = AND IF
                    >R DROP 2DROP R> UNLOOP UNLOOP EXIT THEN DROP
            LOOP DROP
        ELSE DROP THEN
    LOOP 2DROP 0 ;
: _SF-STATIC ( part -- static|0 ) 11 SWAP _SF-STATIC-ON ;
: _SF-APP-STATIC ( part -- static|0 ) 2 SWAP _SF-STATIC-ON ;
: _SF-PANE-ID ( part -- id )
    _SP-BATCH DUP _RTE-FB.FAMILIES-A @ SWAP _RTE-FB.FAMILIES-U @ 64 / 0 ?DO
        DUP I 64 * + DUP _RTE-FE.KIND @ RTE-FAMILY-PANE = IF
            RTE-FAMILY-ITEMS@ DROP _RTE-PANE.ID @ NIP UNLOOP EXIT
        THEN DROP
    LOOP DROP 0 ;
: _SF-PEND ( -- part ) _RSHSP-PENDING-PART ;
: _SF-TEXT= ( a u static -- flag )
    DUP _RTE-STATIC.VALUE-A @ SWAP _RTE-STATIC.VALUE-U @ COMPARE 0= ;
'''


def test_desks_status_lies_in_a_region_of_its_own_across_the_taskbars_right_end():
    staged_run(STATUS + r'''
_SF-SETUP _SF-FIELDS
_SF-READY 0 _SF-SHOW ' _SF-PAINT _SD-DRAW _SX-PACK-PREPARE _SS-OK
_SX-KA _SX-PART-VALID? _SS-A _SX-KA _SP-BATCH RTE-FAMILY-BATCH-VALID? _SS-A
\ One region across the taskbar row past its entries, the catalog's last,
\ at the taskbar's z and no modal scope.
_SX-KA _SF-REGIONS 1 = _SS-A
_SF-REGION @ _RTE-IR.ID @ _SX-KA RSHSP-PART.NEXT-REGION @ 1- = _SS-A
_SF-REGION @ _RTE-IR.FLAGS @ RTE-REGION-VISIBLE RTE-REGION-CLIPPED OR = _SS-A
_SF-REGION @ _RTE-IR.COLS @ 32 = _SS-A _SF-REGION @ _RTE-IR.ROWS @ 12 = _SS-A
_SF-REGION @ _RTE-IR.Z @ 1 = _SS-A _SX-KA _SP-MODALS 0= _SS-A
\ The status is a STATUS_FIELD there, its label in its slot and its value
\ in the rest.
_SX-KA _SF-STATIC DUP 0<> _SS-A
DUP _RTE-STATIC.REGION @ _SF-REGION @ _RTE-IR.ID @ = _SS-A
DUP _RTE-STATIC.COL @ 17 = _SS-A DUP _RTE-STATIC.HEIGHT @ 1 = _SS-A
DUP _RTE-STATIC.WIDTH @ 14 = _SS-A DUP _RTE-STATIC.LABEL-COLS @ 8 = _SS-A
DUP _RTE-STATIC.LABEL-A @ OVER _RTE-STATIC.LABEL-U @ _SF-AGENT COMPARE 0= _SS-A
_SF-READY 2 PICK _SF-TEXT= _SS-A
DUP _RTE-STATIC.SEVERITY @ 0= _SS-A DUP _RTE-STATIC.EMPHASIZED @ 0= _SS-A
DUP RTE-STATIC-VALID? _SS-A
\ Its identity follows the application's static and comes before the pane.
_RTE-STATIC.ID @ DUP _SX-KA _SF-APP-STATIC _RTE-STATIC.ID @ 1+ = _SS-A
_SX-KA _SF-PANE-ID < _SS-A
\ The taskbar stays semantic beside it.
_SX-KA _SN-TASK 0<> _SS-A _SX-KA _SN-LAUNCHER 0<> _SS-A
\ The admission emits every region of the catalog.
_SX-KA _SP-BATCH _SX-FX RTE-FAMILY-BATCH-EMIT _SS-OK
_SX-REGIONS @ _SX-KA _SQ-REGIONS = _SS-A
_SS-DONE
''', minimum=30)


def test_without_status_fields_or_with_paint_over_it_the_status_is_residual():
    staged_run(STATUS + r'''
_SF-SETUP
_SF-READY 0 _SF-SHOW ' _SF-PAINT _SD-DRAW _SX-PACK-PREPARE _SS-OK
_SX-KA _SX-PART-VALID? _SS-A
_SX-KA _SF-REGIONS 0= _SS-A _SX-KA _SF-STATIC 0= _SS-A
_SX-KA _SN-TASK 0<> _SS-A
\ A foreground cell over the status leaves it residual, and the taskbar
\ beside it semantic.
_SF-FIELDS
: _SF-STRAY-CELL 88 11 20 DRW-CHAR ;
: _SF-STRAY _SF-PAINT ['] _SF-STRAY-CELL DRW-OVERLAY ;
' _SF-STRAY _SD-DRAW _SX-PACK-PREPARE _SS-OK
_SF-PEND _SX-PART-VALID? _SS-A
_SF-PEND _SF-REGIONS 0= _SS-A _SF-PEND _SF-STATIC 0= _SS-A
_SF-PEND _SN-TASK 0<> _SS-A _SF-PEND _SN-LAUNCHER 0<> _SS-A
_SS-DONE
''', minimum=11)


def test_a_changed_status_is_a_delta_and_one_that_comes_or_goes_restarts():
    staged_run(STATUS + r'''
_SF-SETUP _SF-FIELDS
_SF-READY 0 _SF-SHOW ' _SF-PAINT _SD-DRAW _SX-PACK-PREPARE _SS-OK _SD-ACK
_RSHSP-ACTIVE-PART _SX-KA = _SS-A
\ Working, a wider value in another severity, moves the status left: a
\ DELTA that keeps the catalog and the status's identity and replaces it.
: _SF-WORKING S" working" ; _SF-WORKING 1 _SF-SHOW
' _SF-PAINT _SD-DRAW _SD-TA _SD-PENDING
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
_SX-KB _SX-PART-VALID? _SS-A _SD-CATALOGS= _SS-A
_SX-KB _SF-STATIC DUP _RTE-STATIC.ID @ _SX-KA _SF-STATIC _RTE-STATIC.ID @ = _SS-A
DUP _RTE-STATIC.COL @ 15 = _SS-A DUP _RTE-STATIC.WIDTH @ 16 = _SS-A
DUP _RTE-STATIC.SEVERITY @ 1 = _SS-A _SF-WORKING ROT _SF-TEXT= _SS-A
_SD-EMIT _SS-OK _SF-SREPLACE @ 1 = _SS-A _SD-CREPLACE @ 0= _SS-A _SD-PREPLACE @ 0= _SS-A
_SD-ACK _RSHSP-ACTIVE-PART _SX-KB = _SS-A
\ A status that goes is a START with no status region.
_SF-HIDE ' _SF-PAINT _SD-DRAW _SD-TB _SD-PENDING
_RSHSP-DELTA-PROBE RTE-S-OK <> _SS-A
_SX-PACK-PREPARE _SS-OK _SX-KA _SF-REGIONS 0= _SS-A _SX-KA _SF-STATIC 0= _SS-A _SD-ACK
\ And one that comes back.
_SF-READY 0 _SF-SHOW ' _SF-PAINT _SD-DRAW _SD-TA _SD-PENDING
_RSHSP-DELTA-PROBE RTE-S-OK <> _SS-A
_SX-PACK-PREPARE _SS-OK _SX-KB _SF-REGIONS 1 = _SS-A _SX-KB _SF-STATIC 0<> _SS-A
_SS-DONE
''', minimum=28)


# The notice over the status: "Saved" at column 15 covers columns 15 to 23,
# the status's first nine cells.  The model takes the notice, then the
# status after it; the notice's bar is painted over the status's cells.
def test_a_notice_over_the_status_leaves_it_semantic_beneath():
    staged_run(STATUS + r'''
_SF-SETUP _SP-DIALOGS _SF-FIELDS 15 _SN-COL !
: _SF-UNDER ( -- )
    _SD-HELLO 32 0 DO 32 11 I DRW-CHAR LOOP _SF-STRIP _SN-STRIP
    _SN-PUT _SF-PUT _SF-CELLS ['] _SN-BAR DRW-OVERLAY _SS-M SHM-SEAL ;
_SN-SAVED 3 _SN-SHOW _SF-READY 0 _SF-SHOW
' _SF-UNDER _SD-DRAW _SX-PACK-PREPARE _SS-OK
_SX-KA _SX-PART-VALID? _SS-A _SX-KA _SP-BATCH RTE-FAMILY-BATCH-VALID? _SS-A
_SX-KA _SF-STATIC 0<> _SS-A _SX-KA _SN-DIALOG 0<> _SS-A
\ The notice's region lies above the status's.
_SX-KA _SF-REGIONS 1 = _SS-A _SF-REGION @ _RTE-IR.Z @ 1 = _SS-A
_SX-KA _SN-DIALOG _RTE-CONTROL.REGION @ _SX-KA _SP-REGION _RTE-IR.Z @ 4 = _SS-A
\ Paint over the status's cells the notice leaves still leaves it residual.
: _SF-STRAY-CELL 88 11 26 DRW-CHAR ;
: _SF-STRAY _SF-UNDER ['] _SF-STRAY-CELL DRW-OVERLAY ;
' _SF-STRAY _SD-DRAW _SX-PACK-PREPARE _SS-OK
_SF-PEND _SF-STATIC 0= _SS-A _SF-PEND _SN-DIALOG 0<> _SS-A
_SS-DONE
''', minimum=14)
