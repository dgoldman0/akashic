"""Shell DELTA: a changed draw with the acknowledged layout republishes only what changed."""

from pathlib import Path

from test_shell_screen_producer import INSTRUMENTS, STAGED, staged_run


# The staged producer reads its START candidate from its own fields. A DELTA
# reads the base candidate from the pending target bank, where the base
# producer has already matched controls to their acknowledged identities, so
# these fixtures pack the candidate's one control into such a bank.
DELTA_HELPERS = r'''
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
    SCR-DRAW-GENERATION@ DUP _SX-P _RTHP.SOURCE-DRAW ! _SX-P _RTHP.SURFACE-GEN !
    \ A bank already pending is the one the producer packs for this draw.
    _SX-P _RTHP.TARGET-PENDING @ ?DUP IF
        _SX-P _RTHP.SOURCE-DRAW @ SWAP _RTHP-TB.DRAW !
    THEN _SX-NUMBER ;
\ The producer's pending target bank for the next draw.
: _SD-PENDING ( bank -- )
    DUP 4096 0 FILL DUP _SX-BANK
    1 OVER _RTHP-TB.CONTROL-COUNT !
    _SX-CI OVER _RTHP-PACK-CONTROLS-A RTE-CONTROL-SIZE MOVE
    _SX-CX OVER _RTHP-PACK-CORR-A RUCP-CORRELATION-SIZE MOVE
    _SX-P _RTHP.TARGET-PENDING ! ;
\ The frame is sent and the terminal acknowledges it: the screen producer
\ seals its pending bank, part and all, with every check on, and publishes
\ it as the active one.
: _SD-ACK
    _SX-P _RTHP-SEAL-PENDING
    _SX-P _RTHP.PENDING-SEAL @ _SX-P _RTHP.ACTIVE-SEAL ! 0 _SX-P _RTHP.PENDING-SEAL !
    _SX-PUBLISH ;
: _SD-BATCH ( part -- batch ) DUP RSHSP-PART.BATCH @ + ;
\ The pending bank's part: whole, and the bytes it uses.
: _SD-PENDING-VALID? ( -- flag ) _SX-P _RTHP.TARGET-PENDING @ _RSHSP-PART-VALID? ;
: _SD-PENDING-BYTES ( -- u ) _SX-P _RTHP.TARGET-PENDING @ _RTHP-TB.XBLOCK-BYTES @ ;
: _SD-EMIT ( -- status )
    _SD-CLEAR _RSHSP-PENDING-PART _SD-BATCH _RSHSP-ACTIVE-PART _SD-BATCH
    _SX-FX RTE-FAMILY-BATCH-DELTA-EMIT ;
: _SD-CATALOGS= ( -- flag )
    _RSHSP-PENDING-PART _SD-BATCH _RTE-FB.CATALOG-A @
        DUP _RTE-RC.REGIONS-A @ SWAP _RTE-RC.REGIONS-U @
    _RSHSP-ACTIVE-PART _SD-BATCH _RTE-FB.CATALOG-A @
        DUP _RTE-RC.REGIONS-A @ SWAP _RTE-RC.REGIONS-U @ COMPARE 0= ;
: _SD-FIND ( kind part -- control|0 )
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
DELTA = STAGED + DELTA_HELPERS


def test_changed_text_replaces_only_its_run_and_keeps_acknowledged_identities():
    staged_run(DELTA + r'''
_SX-SETUP _SD-HOOKS
' _SD-HELLO _SD-DRAW _RSHSP-PREPARE _SS-OK _SD-ACK
_RSHSP-ACTIVE-PART _SX-KA = _SS-A
\ The next draw changes one letter in the pane.
' _SD-HELLP _SD-DRAW _SD-TA _SD-PENDING
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
_RSHSP-PENDING-PART _SX-KB = _SS-A
_SD-PENDING-VALID? _SS-A
_SD-CATALOGS= _SS-A
_SX-KB RSHSP-PART.NEXT-OBJECT @ _SX-KA RSHSP-PART.NEXT-OBJECT @ = _SS-A
_SD-EMIT _SS-OK
_SD-GREPLACE @ 1 = _SS-A _SD-GDEFINE @ 0= _SS-A
_SD-CREPLACE @ 0= _SS-A _SD-PREPLACE @ 0= _SS-A
_SD-ACK _RSHSP-ACTIVE-PART _SX-KB = _SS-A _RSHSP-PENDING-PART 0= _SS-A
\ The taskbar keeps its acknowledged identities, so a task click resolves.
_RSHSP-CURRENT? _SS-A
11 _SX-KB _SD-FIND _RTE-CONTROL.ID @ DUP 11 _SX-KA _SD-FIND _RTE-CONTROL.ID @ = _SS-A
_RSHSP-INPUT-ID ! RTE-INTENT-ACTIVATE _RSHSP-INPUT-INTENT !
_RSHSP-CONTROL-FIND DUP 0<> _SS-A _RSHSP-INPUT-CONTROL ! _RSHSP-SHELL-TARGET? _SS-A
_SS-DONE
''', minimum=19)


def test_a_click_reads_the_batch_of_the_part_it_routes_through():
    """A click finds its control in the part of the frame the terminal
    acknowledged, which it found current, not in whichever part a check read
    last.  Normal mode checks a frozen part only when a START is
    acknowledged, so a click after later frames read a batch whose block a
    newer frame might have rewritten in another layout.  Here no check
    reads either part."""
    staged_run(DELTA + r'''
: _SR-FIND ( -- control|0 )
    _RSHSP-CURRENT? 0= IF 0 EXIT THEN
    11 _RSHSP-ACTIVE-PART _SD-FIND _RTE-CONTROL.ID @ _RSHSP-INPUT-ID !
    _RSHSP-CONTROL-FIND ;
: _SR-IN? ( control block -- flag ) 2DUP U< 0= >R 131072 + U< R> AND ;
_SX-SETUP _SD-HOOKS
' _SD-HELLO _SD-DRAW _RSHSP-PREPARE _SS-OK _SD-ACK
_SR-FIND DUP 0<> _SS-A _SX-KA _SR-IN? _SS-A
' _SD-HELLP _SD-DRAW _SD-TA _SD-PENDING
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK _SD-ACK
_RSHSP-ACTIVE-PART _SX-KB = _SS-A
_SR-FIND DUP 0<> _SS-A _SX-KB _SR-IN? _SS-A
_SS-DONE
''', minimum=8)

def test_more_and_fewer_runs_define_new_slots_and_hide_unused_ones():
    staged_run(DELTA + r'''
VARIABLE _SD-FRONTIER
_SX-SETUP _SD-HOOKS
' _SD-HELLP _SD-DRAW _RSHSP-PREPARE _SS-OK _SD-ACK
\ Two more runs in one row: they get identities above every published one.
' _SD-SPLIT _SD-DRAW _SD-TA _SD-PENDING
_SX-P _RTHP.NEXT-OBJECT @ _SD-FRONTIER !
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
_SD-PENDING-VALID? _SS-A
\ The mapped batch still passes the graph check the freeze takes as proved.
_RSHSP-BATCH @ RTE-FAMILY-BATCH-VALID? _SS-A
_SD-EMIT _SS-OK
_SD-GDEFINE @ 2 = _SS-A _SD-GREPLACE @ 0> _SS-A
_SD-LAST-OBJECT @ _SD-FRONTIER @ 1+ = _SS-A
_SX-KB RSHSP-PART.NEXT-OBJECT @ _SD-FRONTIER @ 2 + = _SS-A
_SD-ACK _SX-P _RTHP.NEXT-OBJECT @ _SD-FRONTIER @ 2 + = _SS-A
\ Back to one run in the row: the two extra slots become hidden empty runs.
' _SD-UNSPLIT _SD-DRAW _SD-TB _SD-PENDING
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
_RSHSP-PENDING-PART _SX-KA = _SS-A
_SD-PENDING-VALID? _SS-A
_RSHSP-BATCH @ RTE-FAMILY-BATCH-VALID? _SS-A
_SD-EMIT _SS-OK _SD-GDEFINE @ 0= _SS-A _SD-GREPLACE @ 2 > _SS-A
_SX-KA RSHSP-PART.NEXT-OBJECT @ _SX-KB RSHSP-PART.NEXT-OBJECT @ = _SS-A
_SD-ACK
\ The same draw again changes nothing; one pane replaced with itself still
\ gives the commit an operation.
' _SD-UNSPLIT _SD-DRAW _SD-TA _SD-PENDING
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
_SD-EMIT _SS-OK
_SD-PREPLACE @ 1 = _SS-A _SD-GREPLACE @ 0= _SS-A _SD-GDEFINE @ 0= _SS-A
_SS-DONE
''', minimum=24)


def test_taskbar_or_layout_changes_and_start_candidates_stay_on_start():
    staged_run(DELTA + r'''
VARIABLE _SD-SAVED
_SX-SETUP _SD-HOOKS
' _SD-HELLO _SD-DRAW _RSHSP-PREPARE _SS-OK _SD-ACK
\ A frame on screen with no part of the shell's, as one sent alone has:
\ no DELTA.
_SX-P _RTHP.TARGET-ACTIVE @ _RTHP-TB.XBLOCK DUP @ _SD-SAVED ! 0 SWAP !
_RSHSP-DELTA-PROBE RTE-S-UNAVAILABLE = _SS-A
_RSHSP-DELTA-PREPARE RTE-S-UNAVAILABLE = _SS-A
_SD-SAVED @ _SX-P _RTHP.TARGET-ACTIVE @ _RTHP-TB.XBLOCK !
\ A renamed task alters the shell model itself.
: _SD-LABEL ( -- a ) 1 _SS-M SHM-ENTRY SHME.LABEL-OFF @ _SS-M + 1+ ;
_SD-LABEL C@ _SD-SAVED ! 120 _SD-LABEL C!
' _SD-HELLP _SD-DRAW _SD-TA _SD-PENDING
_RSHSP-DELTA-PROBE RTE-S-UNAVAILABLE = _SS-A
_SD-SAVED @ _SD-LABEL C!
\ Fresh region identities, as a complete START candidate has, cannot be
\ matched to the acknowledged part, and such a candidate cannot be sent as
\ a DELTA of it.
' _SD-HELLP _SD-DRAW _SD-TA _SD-PENDING
_SX-P _RTHP.REGION @ 100 + _SX-P _RTHP.REGION !
_RSHSP-DELTA-PREPARE RTE-S-UNAVAILABLE = _SS-A
_RSHSP-PENDING-PART 0= _SS-A
_RSHSP-PREPARE _SS-OK _SD-EMIT RTE-S-INVALID = _SS-A
_SS-DONE
''', minimum=8)


def test_unchanged_rows_are_copied_and_give_the_part_planning_gives():
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
_SD-PENDING-VALID? _SS-A
_SD-PENDING-BYTES DUP _SD-USED ! _SX-KB _SD-SAVE ROT MOVE
_SD-EMIT _SS-OK _SD-GREPLACE @ 1 = _SS-A _SD-GDEFINE @ 0= _SS-A
\ Planning every row gives exactly the same part.
_SX-P _RTHP-XBLOCK-DROP -1 _SD-MAP
_RSHSP-DELTA-PREPARE _SS-OK
_SD-PENDING-BYTES _SD-USED @ = _SS-A
_SX-KB _SD-USED @ _SD-SAVE _SD-USED @ COMPARE 0= _SS-A
\ A row the producer did not rebuild is copied, not read from the screen.
_SX-P _RTHP-XBLOCK-DROP 0 _SD-MAP
_RSHSP-DELTA-PREPARE _SS-OK
_SD-EMIT _SS-OK _SD-GREPLACE @ 0= _SS-A _SD-PREPLACE @ 1 = _SS-A
_SS-DONE
''', minimum=13)


def test_a_reused_region_reserves_slots_for_its_rows_not_its_cells():
    """A DELTA reserves glyph slots for the acknowledged runs it copies and
    one per cell of each changed row, not one per cell of the region. The
    pane is the last glyph region built, so its figures are the ones left in
    the producer's variables."""
    staged_run(DELTA + r'''
CREATE _SD-ROWS 64 ALLOT CREATE _SD-SAVE 131072 ALLOT VARIABLE _SD-USED
VARIABLE _SD-START-WORK VARIABLE _SD-ROW-WORK
: _SD-MAP ( flag -- ) _SD-ROWS 64 ROT FILL ;
\ Every cell of row 5 differs in style from its neighbours: one run a cell,
\ the most a changed row can take.
: _SD-STRIPES _SD-HELLO DRW-STYLE-SAVE
    32 0 DO I 1 AND 1+ 0 0 DRW-STYLE! 65 I + 5 I DRW-CHAR LOOP
    DRW-STYLE-RESTORE ;
_SX-SETUP _SD-HOOKS
_SD-ROWS _SX-P _RTHP.ROW-DAMAGE-A ! 64 _SX-P _RTHP.ROW-DAMAGE-U !
' _SD-HELLO _SD-DRAW _RSHSP-PREPARE _SS-OK _SD-ACK
_SX-S RSHSP-WORK-USED@ _SD-START-WORK !
' _SD-STRIPES _SD-DRAW _SD-TA _SD-PENDING
0 _SD-MAP -1 _SD-ROWS 5 + C!
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
_SD-PENDING-VALID? _SS-A
\ The pane's 9 x 19 cells: its acknowledged runs and the changed row's 19
\ cells, every slot used but the one of row 5's acknowledged run.
_RSHSP-GCELLS @ 171 = _SS-A
_RSHSP-GSLOTS @ _RSHSP-GA-N @ 19 + = _SS-A
_RSHSP-GCOUNT @ 1+ _RSHSP-GSLOTS @ = _SS-A
_SX-S RSHSP-WORK-USED@ DUP _SD-ROW-WORK ! _SD-START-WORK @ U< _SS-A
_SD-PENDING-BYTES DUP _SD-USED ! _SX-KB _SD-SAVE ROT MOVE
\ With every row changed the reservation is a START's, one slot a cell,
\ and the part is the same.
_SX-P _RTHP-XBLOCK-DROP -1 _SD-MAP
_RSHSP-DELTA-PREPARE _SS-OK
_RSHSP-GSLOTS @ 171 = _SS-A
_SX-S RSHSP-WORK-USED@ _SD-START-WORK @ = _SS-A
_SD-PENDING-BYTES _SD-USED @ = _SS-A
_SX-KB _SD-USED @ _SD-SAVE _SD-USED @ COMPARE 0= _SS-A
." SHELL GLYPH WORK " _SD-START-WORK @ . _SD-ROW-WORK @ . CR
_SS-DONE
''', minimum=11)


def test_a_glyph_family_lays_out_its_spans_in_the_order_the_batch_lists_them():
    """The batch lists a family's spans as plan, items, text and references.
    A glyph family lays them out in that order, so the family preflight's
    pairwise span check passes over them in one pass."""
    staged_run(DELTA + r'''
VARIABLE _SD-GLYPHS
: _SD-IN-ORDER? ( batch -- flag )
    0 _SD-GLYPHS !
    DUP _RTE-FB.FAMILIES-A @ SWAP _RTE-FB.FAMILIES-U @ 64 / 0 ?DO
        DUP I 64 * + DUP _RTE-FE.KIND @ RTE-FAMILY-GLYPH = IF
            1 _SD-GLYPHS +!
            DUP RTE-FAMILY-ITEMS@ + OVER _RTE-FE.BYTES-A @ U> IF
                2DROP 0 UNLOOP EXIT THEN
            DUP _RTE-FE.BYTES-A @ OVER _RTE-FE.BYTES-U @ +
                OVER _RTE-FE.REFS-A @ U> IF 2DROP 0 UNLOOP EXIT THEN
        THEN DROP
    LOOP DROP -1 ;
_SX-SETUP _SD-HOOKS
' _SD-SPLIT _SD-DRAW _RSHSP-PREPARE _SS-OK
_RSHSP-BATCH @ _SD-IN-ORDER? _SS-A _SD-GLYPHS @ 0> _SS-A
_SS-DONE
''', minimum=3)


def test_a_live_candidate_numbers_its_series_afresh_and_the_delta_reads_the_bank_s():
    """A live candidate numbers its series afresh, while the base producer's
    pending bank carries the series and instruments under their acknowledged
    identities. The DELTA reads both from the bank, so its batch is
    consistent when it is checked, before the remaining identities are
    mapped, and the DELTA is prepared rather than refused."""
    staged_run(INSTRUMENTS + DELTA_HELPERS + r'''
CREATE _SDI-ACKS RTE-INSTRUMENT-SIZE 2 * 7 + ALLOT : _SDI-ACK _SDI-ACKS 7 + -8 AND ;
CREATE _SDI-TAS 140007 ALLOT : _SDI-TA _SDI-TAS 7 + -8 AND ;
\ The base producer's pending bank: its control, instruments and series,
\ matched to the acknowledged ones, the series' samples as an offset into
\ the bank's copy.
: _SDI-PENDING ( bank -- )
    DUP 140000 0 FILL DUP _SX-BANK
    1 OVER _RTHP-TB.CONTROL-COUNT !
    1 OVER _RTHP-TB.INSTRUMENT-REGION-COUNT ! 2 OVER _RTHP-TB.INSTRUMENT-COUNT !
    1 OVER _RTHP-TB.SERIES-COUNT ! 128000 OVER _RTHP-TB.SERIES-SAMPLE-BYTES !
    _SX-CI OVER _RTHP-PACK-CONTROLS-A RTE-CONTROL-SIZE MOVE
    _SX-CX OVER _RTHP-PACK-CORR-A RUCP-CORRELATION-SIZE MOVE
    _SI-IR OVER _RTHP-PACK-INSTRUMENT-REGIONS-A 96 MOVE
    _SDI-ACK OVER _RTHP-PACK-INSTRUMENTS-A RTE-INSTRUMENT-SIZE 2 * MOVE
    _SI-C OVER _RTHP-PACK-INSTRUMENT-CORR-A RUIP-CORRELATION-SIZE 2 * MOVE
    _SI-Y OVER _RTHP-PACK-SERIES-A RTE-SERIES-SIZE MOVE
    7 OVER _RTHP-PACK-SERIES-A _RTE-SERIES.ID ! 0 OVER _RTHP-PACK-SERIES-A _RTE-SERIES.SAMPLES-A !
    _SI-SAMPLES OVER _RTHP-PACK-SERIES-SAMPLES-A 128000 MOVE
    _SX-P _RTHP.TARGET-PENDING ! ;
: _SDI-FIRST ( kind bank -- item )
    DUP RSHSP-PART.BATCH @ + _SI-BATCH ! _SI-FIND DUP 0<> _SS-A RTE-FAMILY-ITEMS@ DROP ;
_SI-SETUP _SD-HOOKS
' _SD-HELLO _SD-DRAW _RSHSP-PREPARE _SS-OK _SD-ACK
_RSHSP-ACTIVE-PART _SI-A = _SS-A
_SI-I _SDI-ACK RTE-INSTRUMENT-SIZE 2 * MOVE
\ The next live candidate's series and waveform name a fresh series.
8 _SI-Y _RTE-SERIES.ID ! 8 _SI-I _RTE-INSTRUMENT.SERIES-ID !
' _SD-HELLP _SD-DRAW _SDI-TA _SDI-PENDING
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
_RSHSP-PENDING-PART _SI-B = _SS-A _SD-PENDING-VALID? _SS-A
\ The DELTA keeps the acknowledged series and instrument identities, and
\ every sample.
RTE-FAMILY-SERIES _SI-B _SDI-FIRST DUP _RTE-SERIES.ID @ 7 = _SS-A _SI-FROZEN-Y !
_SI-SAMPLES-EXACT
RTE-FAMILY-INSTRUMENT _SI-B _SDI-FIRST DUP _RTE-INSTRUMENT.SERIES-ID @ 7 = _SS-A
_RTE-INSTRUMENT.ID @ RTE-FAMILY-INSTRUMENT _SI-A _SDI-FIRST _RTE-INSTRUMENT.ID @ = _SS-A
0 _SI-EMIT-I ! 0 _SI-EMIT-Y !
_SD-EMIT _SS-OK _SD-GREPLACE @ 1 = _SS-A _SD-GDEFINE @ 0= _SS-A
_SI-EMIT-I @ 0= _SS-A _SI-EMIT-Y @ 0= _SS-A
_SS-DONE
''', minimum=16014)


def test_every_frame_checks_validate_the_model_copy_and_the_frozen_bank():
    """The shell snapshot validates its model when it publishes it. With
    every-frame checks on, the producer validates its copy of the model
    again, and the frozen bank after it; in normal mode it builds and freezes
    from the copy as published."""
    staged_run(DELTA + r'''
\ A nonzero byte in an entry past the published model's count, where the
\ shell snapshot's validation wants zeros and nothing else reads.
: _SC-DAMAGE ( -- )
    _SX-P _RTHP.SOURCE-DRAW @ _SX-C SHSN-SNAPSHOT-FOR@ _SS-OK DROP
    DUP SHM.COUNT @ SWAP SHM-ENTRY 1 SWAP C! ;
_SX-SETUP _SD-HOOKS
-1 CHK-EVERY-FRAME !
' _SD-HELLO _SD-DRAW _SC-DAMAGE
_RSHSP-PREPARE RTE-S-OK <> _SS-A
\ The producer refused its copy of the model, and named it.
_RSHSP-DIAG-PREPARE-STAGE @ 5 = _SS-A
CHK-DAMAGE S" the shell's model copy" COMPARE 0= _SS-A CHK-DAMAGE-COUNT @ 1 = _SS-A
0 CHK-EVERY-FRAME !
' _SD-HELLO _SD-DRAW _SC-DAMAGE
_RSHSP-PREPARE _SS-OK CHK-DAMAGE-COUNT @ 1 = _SS-A
_SS-DONE
''', minimum=29)


def test_safe_mode_checks_the_acknowledged_part_again_before_using_it():
    """Part 4's damage test.  A bug writes into the record of the frame the
    terminal holds after the record was frozen and checked; here, into the
    bytes of the shell's part its bank names, which only the part's full
    check reads.  Normal mode does not look at the record again, so a click
    still routes through it and the next changed draw becomes a DELTA built
    on it.  Safe mode checks the record again first: the click goes nowhere,
    the DELTA is refused, which leaves the draw to a START that reads
    nothing from the record, and the check names the shell's part."""
    staged_run(DELTA + r'''
: _SB-DAMAGE ( -- ) _SX-P _RTHP.TARGET-ACTIVE @ _RTHP-TB.XBLOCK-BYTES DUP @ 8 + SWAP ! ;
: _SB-NAMED? ( -- flag ) CHK-DAMAGE S" the shell's part of the frame" COMPARE 0= ;
\ A click on the taskbar's task, routed through the acknowledged part as
\ RSHSP-CONTROL-TARGET@ routes it once the sidecar is proved.
: _SB-CLICK ( -- found? )
    _RSHSP-CURRENT? 0= IF 0 EXIT THEN
    _RSHSP-ACTIVE-INTACT? 0= IF 0 EXIT THEN
    _SX-P _RTHP-ACTIVE-SEALED? 0= IF 0 EXIT THEN
    11 _RSHSP-ACTIVE-PART _SD-FIND _RTE-CONTROL.ID @ _RSHSP-INPUT-ID !
    RTE-INTENT-ACTIVATE _RSHSP-INPUT-INTENT !
    _RSHSP-CONTROL-FIND DUP 0= IF EXIT THEN _RSHSP-INPUT-CONTROL !
    _RSHSP-SHELL-TARGET? ;
_SX-SETUP _SD-HOOKS
' _SD-HELLO _SD-DRAW _RSHSP-PREPARE _SS-OK _SD-ACK
_SB-CLICK _SS-A
\ Normal mode: the damage goes unseen.
_SB-DAMAGE _SB-CLICK _SS-A CHK-DAMAGE-COUNT @ 0= _SS-A
\ Safe mode: the click goes nowhere, and the check names the part.
CHK-WHY-BOOT CHK-SAFE-ON
_SB-CLICK 0= _SS-A CHK-DAMAGE-COUNT @ 1 = _SS-A _SB-NAMED? _SS-A
\ Back in normal mode, as the test compares them: the next changed draw
\ becomes a DELTA on the damaged record.
0 CHK-SAFE-MODE !
' _SD-HELLP _SD-DRAW _SD-TA _SD-PENDING
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
CHK-DAMAGE-COUNT @ 1 = _SS-A
_SX-P _RTHP-XBLOCK-DROP
\ Safe mode: the draw checks the record again and refuses the DELTA.
CHK-WHY-BOOT CHK-SAFE-ON
_RSHSP-DELTA-PREPARE RTE-S-UNAVAILABLE = _SS-A
_RSHSP-PENDING-PART 0= _SS-A
CHK-DAMAGE-COUNT @ 2 = _SS-A _SB-NAMED? _SS-A
\ The START freezes into the other block, with every check, and replaces
\ the damaged record once the terminal has it.
_RSHSP-PREPARE _SS-OK _RSHSP-PENDING-PART _SX-KB = _SS-A
_SD-ACK _RSHSP-ACTIVE-PART _SX-KB = _SS-A
_RSHSP-ACTIVE-INTACT? _SS-A _SB-CLICK _SS-A CHK-DAMAGE-COUNT @ 2 = _SS-A
_SS-DONE
''', minimum=22)
    # The public entry checks the part, and then the seal of the bank that
    # names it, right after it finds the part current.
    source = (Path(__file__).resolve().parents[1]
              / "akashic/tui/rich-terminal/shell-screen-producer.f").read_text()
    target = source[source.index(": RSHSP-CONTROL-TARGET@"):]
    target = target[:target.index("\n;") if "\n;" in target else len(target)]
    assert ("_RSHSP-CURRENT? 0= IF _RSHSP-INPUT-NONE EXIT THEN\n"
            "    _RSHSP-ACTIVE-INTACT? 0= IF _RSHSP-INPUT-NONE EXIT THEN\n"
            "    _RSHSP-P @ _RTHP-ACTIVE-SEALED? 0= IF _RSHSP-INPUT-NONE EXIT THEN") in target


def test_safe_mode_seals_the_frame_s_bank_with_its_part_and_finds_its_text_changed():
    """Decision 9.  Damage that keeps the acknowledged part well formed but
    changes what it holds passes the part's structure checks.  Here a bug
    writes the next draw's letter over a run of the frame on screen.  In
    normal mode the next DELTA then sends nothing for that run, and the
    screen keeps the old text.  In safe mode the frame's bank took a seal
    when the frame was sent, and the seal covers the shell's part the bank
    names: it no longer matches, the check names the producer's banks, and
    the comparison every DELTA starts with refuses the bank, so the draw
    goes out as a START.  A bank sent before safe mode was on has no seal,
    so it is refused too, though nothing is named."""
    staged_run(DELTA + r'''
\ Where the part of the frame on screen first holds the text.
VARIABLE _SE-A VARIABLE _SE-U
: _SE-RUN ( c-addr u -- a )
    _SE-U ! _SE-A !
    _SX-P _RTHP.TARGET-ACTIVE @ _RTHP-XBLOCK@
    _SE-U @ - 1+ 0 DO
        DUP I + _SE-U @ _SE-A @ _SE-U @ COMPARE 0= IF I + UNLOOP EXIT THEN
    LOOP TRUE ABORT" no run" ;
_SX-SETUP _SD-HOOKS
\ Normal mode: HELLO is on screen, and its run is overwritten with the
\ next draw's text, HELLP.
' _SD-HELLO _SD-DRAW _RSHSP-PREPARE _SS-OK _SD-ACK
_SX-P _RTHP.ACTIVE-SEAL @ 0= _SS-A
80 S" HELLO" _SE-RUN 4 + C!
' _SD-HELLP _SD-DRAW _SD-TA _SD-PENDING
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
\ The DELTA sends no run: the screen keeps HELLO.
_SD-EMIT _SS-OK _SD-GREPLACE @ 0= _SS-A _SD-GDEFINE @ 0= _SS-A
_SX-P _RTHP-XBLOCK-DROP
\ Safe mode from here: the bank on screen has no seal, so it is no base
\ for a DELTA, and nothing is named.
CHK-WHY-BOOT CHK-SAFE-ON
_SX-P _RTHP-ACTIVE-SEALED? 0= _SS-A CHK-DAMAGE-COUNT @ 0= _SS-A
_RSHSP-PREPARE _SS-OK _SD-ACK
_RSHSP-ACTIVE-PART _SX-KB = _SS-A _SX-P _RTHP.ACTIVE-SEAL @ 0<> _SS-A
_RSHSP-ACTIVE-INTACT? _SS-A _SX-P _RTHP-ACTIVE-SEALED? _SS-A
\ The same damage to the sealed frame: HELLP on screen becomes HELLO, the
\ next draw's text.  The part's structure still holds; the seal does not.
79 S" HELLP" _SE-RUN 4 + C!
_RSHSP-ACTIVE-INTACT? _SS-A CHK-DAMAGE-COUNT @ 0= _SS-A
_SX-P _RTHP-ACTIVE-SEALED? 0= _SS-A
CHK-DAMAGE-COUNT @ 1 = _SS-A
CHK-DAMAGE S" the screen producer's frame banks" COMPARE 0= _SS-A
\ The START that follows sends HELLO whole, from the live draw.
' _SD-HELLO _SD-DRAW _SD-TB _SD-PENDING
_RSHSP-PREPARE _SS-OK _RSHSP-PENDING-PART _SX-KA = _SS-A
_SS-DONE
''', minimum=17)


def test_normal_mode_freezes_and_sends_a_delta_through_the_proved_emission():
    """The shell sends its frozen parts through the proved emission. With
    every-frame checks on it still proves the parts and the shell facade
    before it writes; in normal mode the freeze and the emission take the
    parts as proved copies of admitted batches, and send the same change."""
    staged_run(DELTA + r'''
: _SN-EMIT ( -- status )
    _SD-CLEAR _RSHSP-PENDING-PART _SD-BATCH _RSHSP-ACTIVE-PART _SD-BATCH
    _SX-FX _RTE-FAMILY-BATCH-DELTA-EMIT-PROVED ;
_SX-SETUP _SD-HOOKS
-1 CHK-EVERY-FRAME !
' _SD-HELLO _SD-DRAW _RSHSP-PREPARE _SS-OK _SD-ACK
\ Every-frame checks: the changed run, through the proved emission.
' _SD-HELLP _SD-DRAW _SD-TA _SD-PENDING
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
_SN-EMIT _SS-OK _SD-GREPLACE @ 1 = _SS-A _SD-GDEFINE @ 0= _SS-A _SD-ACK
\ Normal mode: the next change freezes into a part the test still finds
\ valid, and is sent the same way.
0 CHK-EVERY-FRAME !
' _SD-HELLO _SD-DRAW _SD-TB _SD-PENDING
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
_SD-PENDING-VALID? _SS-A
_SN-EMIT _SS-OK _SD-GREPLACE @ 1 = _SS-A _SD-GDEFINE @ 0= _SS-A
\ A shell facade that does not name itself: in normal mode the frozen
\ parts are sent without proving it again; every-frame checks refuse it.
_SX-FX _RTE-SH.SELF DUP @ 1+ SWAP !
_SN-EMIT _SS-OK
-1 CHK-EVERY-FRAME !
_SN-EMIT RTE-S-INVALID = _SS-A
_SX-FX _RTE-SH.SELF DUP @ 1- SWAP !
_SN-EMIT _SS-OK
0 CHK-EVERY-FRAME !
_SS-DONE
''', minimum=39)


def test_the_shadow_check_plans_reused_regions_whole_and_catches_stale_row_damage():
    """With the shadow check on, a region whose unchanged rows were copied
    is also planned whole. When the producer's row damage misses a changed
    row, the copied row differs from the screen, and the check says so."""
    staged_run(DELTA + r'''
CREATE _SD-ROWS 64 ALLOT
: _SD-MAP ( flag -- ) _SD-ROWS 64 ROT FILL ;
_SX-SETUP _SD-HOOKS
_SD-ROWS _SX-P _RTHP.ROW-DAMAGE-A ! 64 _SX-P _RTHP.ROW-DAMAGE-U !
' _SD-HELLO _SD-DRAW _RSHSP-PREPARE _SS-OK _SD-ACK
-1 FSHD-ON ! FSHD-RESET
\ Row 5 changed and is marked: each reused region matches its whole plan.
' _SD-HELLP _SD-DRAW _SD-TA _SD-PENDING
0 _SD-MAP -1 _SD-ROWS 5 + C!
_RSHSP-DELTA-PROBE _SS-OK _RSHSP-DELTA-PREPARE _SS-OK
FSHD-CHECKS @ 0> _SS-A FSHD-MISMATCHES @ 0= _SS-A FSHD-SKIPPED @ 0= _SS-A
\ Row 5 changed but is not marked: its copied runs are the acknowledged
\ ones, which the screen no longer shows.
_SX-P _RTHP-XBLOCK-DROP 0 _SD-MAP FSHD-RESET
_RSHSP-DELTA-PREPARE _SS-OK
FSHD-MISMATCHES @ 1 = _SS-A
FSHD-FIRST-STAGE @ FSHD-STAGE-SHELL-GLYPHS = _SS-A
\ Item 4R+2 of region R: the runs and references agree, the text does not.
FSHD-FIRST-ITEM @ 3 AND 2 = _SS-A
0 FSHD-ON !
_SS-DONE
''', minimum=31)
