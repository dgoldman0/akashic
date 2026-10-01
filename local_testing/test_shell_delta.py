"""Shell DELTA: a changed draw with the acknowledged layout republishes only what changed."""

from test_shell_screen_producer import STAGED, staged_run


# The staged producer reads its START candidate from its own fields. A DELTA
# reads the base candidate from the pending target bank, where the base
# producer has already matched controls to their acknowledged identities, so
# these fixtures pack the candidate's one control into such a bank.
DELTA = STAGED + r'''
CREATE _SD-TAS 4103 ALLOT CREATE _SD-TBS 4103 ALLOT
: _SD-TA _SD-TAS 7 + -8 AND ; : _SD-TB _SD-TBS 7 + -8 AND ;
VARIABLE _SD-PAINT VARIABLE _SD-LAST-OBJECT
VARIABLE _SD-GREPLACE VARIABLE _SD-GDEFINE VARIABLE _SD-CREPLACE VARIABLE _SD-PREPLACE
: _SD-GLYPH-REPLACE ( run context -- status )
    DROP _RTE-GLYPH-RUN.OBJECT @ _SD-LAST-OBJECT ! 1 _SD-GREPLACE +! RTE-S-OK ;
: _SD-GLYPH-DEFINE ( run context -- status )
    DROP _RTE-GLYPH-RUN.OBJECT @ _SD-LAST-OBJECT ! 1 _SD-GDEFINE +! RTE-S-OK ;
: _SD-CONTROL-REPLACE ( control context -- status ) 2DROP 1 _SD-CREPLACE +! RTE-S-OK ;
: _SD-PANE-REPLACE ( pane context -- status ) 2DROP 1 _SD-PREPLACE +! RTE-S-OK ;
: _SD-CLEAR 0 _SD-GREPLACE ! 0 _SD-GDEFINE ! 0 _SD-CREPLACE ! 0 _SD-PREPLACE ! ;
: _SD-HOOKS
    ['] _SD-GLYPH-REPLACE _SX-F _RTE-F.GLYPH-RUN-REPLACE-XT !
    ['] _SD-GLYPH-DEFINE _SX-F _RTE-F.GLYPH-RUN-DEF-XT !
    ['] _SD-CONTROL-REPLACE _SX-F _RTE-F.CONTROL-REPLACE-XT !
    ['] _SD-PANE-REPLACE _SX-FX _RTE-SH.PANE-REPLACE-XT ! ;
\ One completed draw whose painting is the xt; every paint advances the epoch.
: _SD-DRAW ( xt -- )
    _SD-PAINT !
    _SS-M SHM.EPOCH DUP @ 1+ SWAP !
    ASHELL-DRAW-BEGIN _ASHELL-DRAW-OBSERVE _SS-OK
    _SD-PAINT @ EXECUTE _SX-H AHOST-SHELL-DRAW-COMPLETE _SS-OK
    SCR-DRAW-COMPLETE ASHELL-DRAW-COMPLETE _ASHELL-DRAW-OBSERVE _SS-OK
    SCR-DRAW-GENERATION@ DUP _SX-P _RTHP.SOURCE-DRAW ! _SX-P _RTHP.SURFACE-GEN ! ;
\ The producer's pending target bank for the next draw.
: _SD-PENDING ( bank -- )
    DUP 4096 0 FILL
    1 OVER _RTHP-TB.CONTROL-COUNT !
    _SX-CI OVER _RTHP-PACK-CONTROLS-A RTE-CONTROL-SIZE MOVE
    _SX-CX OVER _RTHP-PACK-CORR-A RUCP-CORRELATION-SIZE MOVE
    _SX-P _RTHP.TARGET-PENDING ! ;
\ The physical acknowledgement publishes the pending bank as the active one.
: _SD-ACK
    _SX-P _RTHP.TARGET-PENDING @ _SX-P _RTHP.TARGET-ACTIVE !
    _SX-P _RTHP.SOURCE-DRAW @ _SX-P _RTHP.ACTIVE-DRAW ! _RSHSP-PUBLISH ;
: _SD-BATCH ( bank -- batch ) DUP RSHSP-BANK.BATCH @ + ;
: _SD-EMIT ( -- status )
    _SD-CLEAR _SX-S _RSHSP.PENDING @ _SD-BATCH _SX-S _RSHSP.ACTIVE @ _SD-BATCH
    _SX-FX RTE-FAMILY-BATCH-DELTA-EMIT ;
: _SD-CATALOGS= ( -- flag )
    _SX-S _RSHSP.PENDING @ _SD-BATCH _RTE-FB.CATALOG-A @
        DUP _RTE-RC.REGIONS-A @ SWAP _RTE-RC.REGIONS-U @
    _SX-S _RSHSP.ACTIVE @ _SD-BATCH _RTE-FB.CATALOG-A @
        DUP _RTE-RC.REGIONS-A @ SWAP _RTE-RC.REGIONS-U @ COMPARE 0= ;
: _SD-FIND ( kind bank -- control|0 )
    _SD-BATCH DUP _RTE-FB.FAMILIES-A @ SWAP _RTE-FB.FAMILIES-U @ 64 / 0 ?DO
        DUP I 64 * + DUP _RTE-FE.KIND @ RTE-FAMILY-CONTROL = IF
            RTE-FAMILY-ITEMS@ RTE-CONTROL-SIZE / 0 ?DO
                DUP I RTE-CONTROL-SIZE * + DUP _RTE-CONTROL.KIND @ 4 PICK = IF
                    >R DROP 2DROP R> UNLOOP UNLOOP EXIT THEN DROP
            LOOP DROP
        ELSE DROP THEN
    LOOP 2DROP 0 ;
: _SD-HELLO 72 5 2 DRW-CHAR 69 5 3 DRW-CHAR 76 5 4 DRW-CHAR 76 5 5 DRW-CHAR 79 5 6 DRW-CHAR ;
: _SD-HELLP _SD-HELLO 80 5 6 DRW-CHAR ;
\ A differently styled cell splits its row into three runs.
: _SD-SPLIT _SD-HELLP DRW-STYLE-SAVE 1 0 0 DRW-STYLE! 88 6 2 DRW-CHAR DRW-STYLE-RESTORE ;
: _SD-UNSPLIT _SD-HELLP 32 6 2 DRW-CHAR ;
'''


def test_changed_text_replaces_only_its_run_and_keeps_acknowledged_identities():
    staged_run(DELTA + r'''
_SX-SETUP _SD-HOOKS
' _SD-HELLO _SD-DRAW _RSHSP-PREPARE _SS-OK _SD-ACK
_SX-S _RSHSP.ACTIVE @ _SX-KA = _SS-A
\ The next draw changes one letter in the pane.
' _SD-HELLP _SD-DRAW _SD-TA _SD-PENDING
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
_SX-S _RSHSP.PENDING @ _SX-KB = _SS-A
_SX-KB _SX-S _RSHSP-BANK-VALID? _SS-A _RSHSP-PENDING? _SS-A
_SD-CATALOGS= _SS-A
_SX-KB RSHSP-BANK.NEXT-OBJECT @ _SX-KA RSHSP-BANK.NEXT-OBJECT @ = _SS-A
_SD-EMIT _SS-OK
_SD-GREPLACE @ 1 = _SS-A _SD-GDEFINE @ 0= _SS-A
_SD-CREPLACE @ 0= _SS-A _SD-PREPLACE @ 0= _SS-A
_SD-ACK _SX-S _RSHSP.ACTIVE @ _SX-KB = _SS-A _SX-S _RSHSP.PENDING @ 0= _SS-A
\ The taskbar keeps its acknowledged identities, so a task click resolves.
_RSHSP-CURRENT? _SS-A
11 _SX-KB _SD-FIND _RTE-CONTROL.ID @ DUP 11 _SX-KA _SD-FIND _RTE-CONTROL.ID @ = _SS-A
_RSHSP-INPUT-ID ! RTE-INTENT-ACTIVATE _RSHSP-INPUT-INTENT !
_RSHSP-CONTROL-FIND DUP 0<> _SS-A _RSHSP-INPUT-CONTROL ! _RSHSP-SHELL-TARGET? _SS-A
_SS-DONE
''', minimum=20)


def test_more_and_fewer_runs_define_new_slots_and_hide_unused_ones():
    staged_run(DELTA + r'''
VARIABLE _SD-FRONTIER
_SX-SETUP _SD-HOOKS
' _SD-HELLP _SD-DRAW _RSHSP-PREPARE _SS-OK _SD-ACK
\ Two more runs in one row: they get identities above every published one.
' _SD-SPLIT _SD-DRAW _SD-TA _SD-PENDING
_SX-P _RTHP.NEXT-OBJECT @ _SD-FRONTIER !
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
_SX-KB _SX-S _RSHSP-BANK-VALID? _SS-A
_SD-EMIT _SS-OK
_SD-GDEFINE @ 2 = _SS-A _SD-GREPLACE @ 0> _SS-A
_SD-LAST-OBJECT @ _SD-FRONTIER @ 1+ = _SS-A
_SX-KB RSHSP-BANK.NEXT-OBJECT @ _SD-FRONTIER @ 2 + = _SS-A
_SD-ACK _SX-P _RTHP.NEXT-OBJECT @ _SD-FRONTIER @ 2 + = _SS-A
\ Back to one run in the row: the two extra slots become hidden empty runs.
' _SD-UNSPLIT _SD-DRAW _SD-TB _SD-PENDING
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
_SX-S _RSHSP.PENDING @ _SX-KA = _SS-A
_SX-KA _SX-S _RSHSP-BANK-VALID? _SS-A
_SD-EMIT _SS-OK _SD-GDEFINE @ 0= _SS-A _SD-GREPLACE @ 2 > _SS-A
_SX-KA RSHSP-BANK.NEXT-OBJECT @ _SX-KB RSHSP-BANK.NEXT-OBJECT @ = _SS-A
_SD-ACK
\ The same draw again changes nothing; one pane replaced with itself still
\ gives the commit an operation.
' _SD-UNSPLIT _SD-DRAW _SD-TA _SD-PENDING
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
_SD-EMIT _SS-OK
_SD-PREPLACE @ 1 = _SS-A _SD-GREPLACE @ 0= _SS-A _SD-GDEFINE @ 0= _SS-A
_SS-DONE
''', minimum=22)


def test_taskbar_or_layout_changes_and_start_candidates_stay_on_start():
    staged_run(DELTA + r'''
_SX-SETUP _SD-HOOKS
' _SD-HELLO _SD-DRAW _RSHSP-PREPARE _SS-OK _SD-ACK
\ No acknowledged bank paired with the active target: no DELTA.
_SX-P _RTHP.TARGET-ACTIVE @ 8 + _SX-P _RTHP.TARGET-ACTIVE !
_RSHSP-DELTA-PROBE RTE-S-UNAVAILABLE = _SS-A
_RSHSP-DELTA-PREPARE RTE-S-UNAVAILABLE = _SS-A
_SX-P _RTHP.TARGET-ACTIVE @ 8 - _SX-P _RTHP.TARGET-ACTIVE !
\ A renamed task alters the shell model itself.
VARIABLE _SD-SAVED
: _SD-LABEL ( -- a ) 1 _SS-M SHM-ENTRY SHME.LABEL-OFF @ _SS-M + 1+ ;
_SD-LABEL C@ _SD-SAVED ! 120 _SD-LABEL C!
' _SD-HELLP _SD-DRAW _SD-TA _SD-PENDING
_RSHSP-DELTA-PROBE RTE-S-UNAVAILABLE = _SS-A
_SD-SAVED @ _SD-LABEL C!
\ Fresh region identities, as a complete START candidate has, cannot be
\ matched to the acknowledged bank, and such a candidate cannot be sent as
\ a DELTA of it.
' _SD-HELLP _SD-DRAW _SD-TA _SD-PENDING
_SX-P _RTHP.REGION @ 100 + _SX-P _RTHP.REGION !
_RSHSP-DELTA-PREPARE RTE-S-UNAVAILABLE = _SS-A
_SX-S _RSHSP.PENDING @ 0= _SS-A
_RSHSP-PREPARE _SS-OK _SD-EMIT RTE-S-INVALID = _SS-A
_SS-DONE
''', minimum=8)


def test_unchanged_rows_are_copied_and_give_the_bank_planning_gives():
    staged_run(DELTA + r'''
CREATE _SD-ROWS 64 ALLOT CREATE _SD-SAVE 131072 ALLOT VARIABLE _SD-USED
: _SD-MAP ( flag -- ) _SD-ROWS 64 ROT FILL ;
_SX-SETUP _SD-HOOKS
_SD-ROWS _SX-P _RTHP.ROW-DAMAGE-A ! 64 _SX-P _RTHP.ROW-DAMAGE-U !
' _SD-HELLO _SD-DRAW _RSHSP-PREPARE _SS-OK _SD-ACK
\ The producer rebuilt only row 5, so only row 5 is planned again.
' _SD-HELLP _SD-DRAW _SD-TA _SD-PENDING
0 _SD-MAP -1 _SD-ROWS 5 + C!
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
_SX-KB _SX-S _RSHSP-BANK-VALID? _SS-A
_SX-KB RSHSP-BANK.USED @ DUP _SD-USED ! _SX-KB _SD-SAVE ROT MOVE
_SD-EMIT _SS-OK _SD-GREPLACE @ 1 = _SS-A _SD-GDEFINE @ 0= _SS-A
\ Planning every row gives exactly the same bank.
_SX-S _RSHSP-ABORT -1 _SD-MAP
_RSHSP-DELTA-PREPARE _SS-OK
_SX-KB RSHSP-BANK.USED @ _SD-USED @ = _SS-A
_SX-KB _SD-USED @ _SD-SAVE _SD-USED @ COMPARE 0= _SS-A
\ A row the producer did not rebuild is copied, not read from the screen.
_SX-S _RSHSP-ABORT 0 _SD-MAP
_RSHSP-DELTA-PREPARE _SS-OK
_SD-EMIT _SS-OK _SD-GREPLACE @ 0= _SS-A _SD-PREPLACE @ 1 = _SS-A
_SS-DONE
''', minimum=13)
