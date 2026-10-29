"""Immutable copied family graphs: exact extent, rebasing and prewrite refusal."""
from test_data_graphics_series import run_series
from test_rich_region_catalog import PRELUDE

MODULES = ("tui/rich-terminal/shell-family-clone.f",)
CLONE = PRELUDE + r'''
CREATE _FC-DS 32775 ALLOT CREATE _FC-SS 32775 ALLOT CREATE _FC-ES 32775 ALLOT
: _FC-D _FC-DS 7 + -8 AND ; : _FC-S _FC-SS 7 + -8 AND ; : _FC-E _FC-ES 7 + -8 AND ;
VARIABLE _FC-U VARIABLE _FC-N VARIABLE _FC-A0
\ The copied graph's bytes: one static record and 2472 of the rest.
: _FC-WHOLE 2472 RTE-STATIC-SIZE + ;
: _FC-FAMILY ( index -- family ) 64 * _FC-D _RTE-FB.FAMILIES-A @ + ;
: _FC-ITEM ( index -- item ) _FC-FAMILY RTE-FAMILY-ITEMS@ DROP ;
: _FC-BYTES ( index -- a u ) _FC-FAMILY DUP _RTE-FE.BYTES-A @ SWAP _RTE-FE.BYTES-U @ ;
: _FC-WITHIN? ( a u -- flag ) OVER _FC-D U< IF 2DROP 0 EXIT THEN
    + _FC-D _FC-U @ + U> 0= ;
: _FC-ALL-OWNED _FC-D RTE-FAMILY-BATCH-SPAN-COUNT 0 ?DO
    I _FC-D RTE-FAMILY-BATCH-SPAN@ DUP IF _FC-WITHIN? _RC-A ELSE 2DROP THEN LOOP ;
: _FC-CLEARED _RSHFC-B @ _RSHFC-D @ OR _RSHFC-FAMILY @ OR
    _RSHFC-PLAN @ OR _RSHFC-ITEM @ OR _RSHFC-OLD @ OR _RSHFC-NEW @ OR 0= _RC-A ;
: _FC-REFUSE _RC-BATCH _FC-D 32768 RSHFC-COPY RSHFC-S-INVALID = _RC-A 0= _RC-A
    _FC-D 32768 _FC-S 32768 COMPARE 0= _RC-A ;
: _FC-BAD ( value field -- ) DUP @ >R DUP >R ! _FC-REFUSE R> R> SWAP ! ;
: _FC-ZERO-SOURCE
    _RC-BATCH RTE-FAMILY-BATCH-SPAN-COUNT DUP _FC-N ! 0 ?DO
        _FC-N @ 1- I - _RC-BATCH RTE-FAMILY-BATCH-SPAN@ 0 FILL
    LOOP ;
-9223372036854775808 _RC-YT ! 9223372036854775807 _RC-YT 8 + !
'''


def run(program, minimum=1):
    run_series(program, minimum=minimum, extra_sources=MODULES, marker="CATALOG")


def test_complete_graph_copy_rebases_all_families_and_survives_source_reuse():
    run(CLONE + r'''
_RC-BATCH RSHFC-MEASURE 0= _RC-A DUP _FC-U ! _FC-WHOLE = _RC-A
_FC-D 32768 165 FILL
_RC-BATCH _FC-D _FC-WHOLE RSHFC-COPY 0= _RC-A _FC-U @ = _RC-A
_FC-D RTE-FAMILY-BATCH-VALID? _RC-A _FC-ALL-OWNED
_FC-D _FC-U @ + C@ 165 = _RC-A
0 _FC-BYTES 1 = _RC-A C@ 67 = _RC-A
1 _FC-BYTES 1 = _RC-A C@ 71 = _RC-A
2 _FC-BYTES 1 = _RC-A C@ 73 = _RC-A
3 _FC-BYTES 1 = _RC-A C@ 83 = _RC-A
4 _FC-BYTES 16 = _RC-A DUP @ -9223372036854775808 = _RC-A 8 + @ 9223372036854775807 = _RC-A
5 _FC-BYTES 1 = _RC-A C@ 80 = _RC-A
0 _FC-ITEM _RTE-CONTROL.LABEL-A @ 0 _FC-BYTES DROP = _RC-A
1 _FC-FAMILY _RTE-FE.REFS-A @ DUP @ 0= _RC-A 8 + @ 1 = _RC-A
2 _FC-ITEM _RTE-INSTRUMENT.UNIT-A @ 2 _FC-BYTES DROP = _RC-A
3 _FC-ITEM _RTE-STATIC.VALUE-A @ 3 _FC-BYTES DROP = _RC-A
4 _FC-ITEM _RTE-SERIES.SAMPLES-A @ 4 _FC-BYTES DROP = _RC-A
5 _FC-ITEM _RTE-PANE.TITLE-A @ 5 _FC-BYTES DROP = _RC-A
\ Explicit pad bytes, distinct from source tail, are canonical zero.
: _FC-PAD? 0 _FC-BYTES + 7 0 DO DUP I + C@ 0= _RC-A LOOP DROP ; _FC-PAD?
\ The copied graph can itself be copied; every pointer moves to the new bank.
_FC-D _FC-E 32768 RSHFC-COPY 0= _RC-A _FC-U @ = _RC-A
_FC-E RTE-FAMILY-BATCH-VALID? _RC-A
_FC-ZERO-SOURCE
_FC-D RTE-FAMILY-BATCH-VALID? _RC-A _FC-E RTE-FAMILY-BATCH-VALID? _RC-A
0 _FC-BYTES DROP C@ 67 = _RC-A 4 _FC-BYTES DROP @ -9223372036854775808 = _RC-A
_FC-CLEARED
_RC-DONE
''', minimum=62)


def test_capacity_alias_and_malformed_graph_refuse_without_destination_writes():
    run(CLONE + r'''
_FC-D 32768 165 FILL _FC-D _FC-S 32768 MOVE
_RC-BATCH _FC-D _FC-WHOLE 1- RSHFC-COPY RSHFC-S-CAPACITY = _RC-A 0= _RC-A
_FC-D 32768 _FC-S 32768 COMPARE 0= _RC-A
_RC-BATCH _FC-D 1+ 32767 RSHFC-COPY RSHFC-S-INVALID = _RC-A 0= _RC-A
_FC-D 32768 _FC-S 32768 COMPARE 0= _RC-A
9 _RC-CI _RTE-CONTROL.REGION _FC-BAD
_RC-CT 1+ _RC-CI _RTE-CONTROL.LABEL-A _FC-BAD
_RC-GT _RC-FAM _RTE-FE.BYTES-A _FC-BAD
_RSHFC-U _RC-FAM _RTE-FE.BYTES-A _FC-BAD
_RTE-RC-BATCH _RC-FAM _RTE-FE.BYTES-A _FC-BAD
_RTE-HPV-OWNED-START _RC-FAM _RTE-FE.BYTES-A _FC-BAD
1 _RC-PI _RTE-PANE.RESERVED _FC-BAD
\ Source/output overlap is rejected before either graph is touched.
_RC-BATCH _RC-CAT 56 RSHFC-COPY RSHFC-S-INVALID = _RC-A 0= _RC-A
_RC-BATCH _RC-GT 8 RSHFC-COPY RSHFC-S-INVALID = _RC-A 0= _RC-A
_RC-BATCH RTE-FAMILY-BATCH-VALID? _RC-A
_RSHFC-B @ _FC-A0 !
_RSHFC-B RSHFC-MEASURE RSHFC-S-INVALID = _RC-A 0= _RC-A
_RSHFC-B @ _FC-A0 @ = _RC-A
_RC-BATCH RSHFC-MEASURE 0= _RC-A _FC-WHOLE = _RC-A
_FC-D 32768 _FC-S 32768 COMPARE 0= _RC-A
_FC-CLEARED
_RC-DONE
''', minimum=38)


def test_empty_series_catalog_and_all_variable_control_static_pointers():
    run(CLONE + r'''
\ Dense CONTROL label/shortcut/content fields all rebase, including binary bytes.
67 _RC-CT C! 72 _RC-CT 1+ C! 0 _RC-CT 2 + C!
_RC-CT 1+ _RC-CI _RTE-CONTROL.SHORTCUT-A ! 1 _RC-CI _RTE-CONTROL.SHORTCUT-U !
_RC-CT 2 + _RC-CI _RTE-CONTROL.CONTENT-A ! 1 _RC-CI _RTE-CONTROL.CONTENT-U !
3 _RC-FAM _RTE-FE.BYTES-U !
76 _RC-ST C! 86 _RC-ST 1+ C!
_RC-ST _RC-SI _RTE-STATIC.LABEL-A ! 1 _RC-SI _RTE-STATIC.LABEL-U !
_RC-ST 1+ _RC-SI _RTE-STATIC.VALUE-A ! 2 _RC-FAM 192 + _RTE-FE.BYTES-U !
_RC-BATCH _FC-D 32768 RSHFC-COPY 0= _RC-A _FC-U !
_FC-D RTE-FAMILY-BATCH-VALID? _RC-A
0 _FC-ITEM _RTE-CONTROL.SHORTCUT-A @ 0 _FC-BYTES DROP 1+ = _RC-A
0 _FC-ITEM _RTE-CONTROL.CONTENT-A @ 0 _FC-BYTES DROP 2 + = _RC-A
3 _FC-ITEM _RTE-STATIC.LABEL-A @ 3 _FC-BYTES DROP = _RC-A
3 _FC-ITEM _RTE-STATIC.VALUE-A @ 3 _FC-BYTES DROP 1+ = _RC-A
\ Canonical zero spans stay null instead of acquiring dangling arena pointers.
_RC-FAM 256 + _RC-FAM 64 MOVE 64 _RC-BATCH _RTE-FB.FAMILIES-U !
0 _RC-CAT _RTE-RC.REGIONS-A ! 0 _RC-CAT _RTE-RC.REGIONS-U !
0 _RC-YI _RTE-SERIES.SAMPLES-A ! 0 _RC-YI _RTE-SERIES.SAMPLES-U !
0 _RC-FAM _RTE-FE.BYTES-A ! 0 _RC-FAM _RTE-FE.BYTES-U !
_RC-BATCH RSHFC-MEASURE 0= _RC-A 328 = _RC-A
_RC-BATCH _FC-D 328 RSHFC-COPY 0= _RC-A 328 = _RC-A
_FC-D RTE-FAMILY-BATCH-VALID? _RC-A
_FC-D _RTE-FB.CATALOG-A @ _RTE-RC.REGIONS-A @ 0= _RC-A
0 _FC-FAMILY _RTE-FE.BYTES-A @ 0= _RC-A
0 _FC-ITEM _RTE-SERIES.SAMPLES-A @ 0= _RC-A
_FC-CLEARED
_RC-DONE
''', minimum=14)


def test_proved_peers_match_public_words_and_keep_alias_checks():
    run(CLONE + r'''
\ After the caller's own graph check, the proved peers give the same result.
_RC-BATCH RTE-FAMILY-BATCH-VALID? _RC-A
_RC-BATCH 0 0 _RSHFC-MEASURE-PROVED 0= _RC-A _FC-WHOLE = _RC-A
_FC-D 32768 165 FILL _FC-E 32768 165 FILL
_RC-BATCH _FC-D _FC-WHOLE RSHFC-COPY 0= _RC-A _FC-WHOLE = _RC-A
_RC-BATCH _FC-E _FC-WHOLE 0 0 _RSHFC-COPY-PROVED 0= _RC-A _FC-WHOLE = _RC-A
_FC-E RTE-FAMILY-BATCH-VALID? _RC-A
0 _FC-BYTES DROP _FC-D - _FC-E + C@ 67 = _RC-A
\ Capacity is still refused before any write, and with every-frame checks
\ on so are source/output aliases.
_FC-E _FC-S 32768 MOVE
_RC-BATCH _FC-E _FC-WHOLE 1- 0 0 _RSHFC-COPY-PROVED RSHFC-S-CAPACITY = _RC-A 0= _RC-A
-1 CHK-EVERY-FRAME !
_RC-BATCH _RC-GT 8 0 0 _RSHFC-COPY-PROVED RSHFC-S-INVALID = _RC-A 0= _RC-A
0 CHK-EVERY-FRAME !
_FC-E 32768 _FC-S 32768 COMPARE 0= _RC-A
\ A range is outside the batch only when it misses every span.
_RC-BATCH _FC-E 32768 _RSHFC-BATCH-OUTSIDE? _RC-A
_RC-BATCH _RC-GT 8 _RSHFC-BATCH-OUTSIDE? 0= _RC-A
_RC-BATCH _RC-BATCH 8 _RSHFC-BATCH-OUTSIDE? 0= _RC-A
_FC-CLEARED
_RC-DONE
''', minimum=18)


def test_proved_peers_leave_a_kept_range_where_it_lies():
    """A copy may leave a family's items and text where they lie: the
    destination takes no bytes for them and the copied graph points at
    them.  The caller lays the kept families out; with every-frame checks
    on, a range holding a family's items without their text, a plan, or part
    of a span is refused before any write."""
    run(CLONE + r'''
VARIABLE _FC-KA VARIABLE _FC-KU
: _FC-SPAN ( index -- a u ) _FC-D RTE-FAMILY-BATCH-SPAN@ ;
\ A canonical copy lays family 0's items and text side by side.
_RC-BATCH _FC-D 32768 RSHFC-COPY 0= _RC-A DROP
_FC-D RTE-FAMILY-BATCH-VALID? _RC-A
5 _FC-SPAN DROP _FC-KA ! 6 _FC-SPAN + _FC-KA @ - _FC-KU !
5 _FC-SPAN + 6 _FC-SPAN DROP = _RC-A
_FC-D _FC-KA @ _FC-KU @ _RSHFC-MEASURE-PROVED 0= _RC-A
    _FC-WHOLE RTE-CONTROL-SIZE - 8 - = _RC-A
_FC-E 32768 165 FILL
_FC-D _FC-E 32768 _FC-KA @ _FC-KU @ _RSHFC-COPY-PROVED 0= _RC-A
    _FC-WHOLE RTE-CONTROL-SIZE - 8 - = _RC-A
_FC-E RTE-FAMILY-BATCH-VALID? _RC-A
_FC-E _RTE-FB.FAMILIES-A @ RTE-FAMILY-ITEMS@ DROP _FC-KA @ = _RC-A
_FC-E _RTE-FB.FAMILIES-A @ _RTE-FE.BYTES-A @ 6 _FC-SPAN DROP = _RC-A
\ The kept items still point at their kept text.
_FC-KA @ _RTE-CONTROL.LABEL-A @ 6 _FC-SPAN DROP = _RC-A
\ Refused with every-frame checks on: items without their text, a plan,
\ and a span cut in two.
_FC-E 32768 165 FILL -1 CHK-EVERY-FRAME !
_FC-D _FC-E 32768 5 _FC-SPAN _RSHFC-COPY-PROVED RSHFC-S-INVALID = _RC-A 0= _RC-A
_FC-D _FC-E 32768 4 _FC-SPAN _RSHFC-COPY-PROVED RSHFC-S-INVALID = _RC-A 0= _RC-A
_FC-D _FC-E 32768 _FC-KA @ 8 + _FC-KU @ _RSHFC-COPY-PROVED
    RSHFC-S-INVALID = _RC-A 0= _RC-A
0 CHK-EVERY-FRAME !
_FC-E C@ 165 = _RC-A
_FC-CLEARED
_RC-DONE
''', minimum=19)
