\ =====================================================================
\  phase-profile.f -- private rich-terminal phase observation
\ =====================================================================
\
\  The acceptance host samples one packed event cell to attribute guest
\  execution without observing a torn phase/sequence pair.  The low byte is
\  the stable phase ID and the high 56 bits are a monotonically advancing
\  sequence.  This diagnostic state is neither application state nor wire
\  payload and is composed only with the optional rich-terminal product.
\
\  Prefix: _RTPROF- (private)

PROVIDED akashic-tui-rterm-phase-profile

 0 CONSTANT _RTPROF-PH-OTHER
 1 CONSTANT _RTPROF-PH-UIDL-AGGREGATE
 2 CONSTANT _RTPROF-PH-SNAPSHOT-IMPORT
 3 CONSTANT _RTPROF-PH-CONTROL-PLAN
 4 CONSTANT _RTPROF-PH-CLAIM-PLAN
 5 CONSTANT _RTPROF-PH-RESIDUAL-PLAN
 6 CONSTANT _RTPROF-PH-RESERVE-WRAP
 7 CONSTANT _RTPROF-PH-HYBRID-PREFLIGHT
 8 CONSTANT _RTPROF-PH-CANDIDATE-VALIDATE
 9 CONSTANT _RTPROF-PH-TARGET-PACK
10 CONSTANT _RTPROF-PH-DELTA-COMPARE-NORMALIZE
11 CONSTANT _RTPROF-PH-RTAPT-CAPTURE
12 CONSTANT _RTPROF-PH-COMMIT-PRECHECK
13 CONSTANT _RTPROF-PH-RTAPT-AUDIT
14 CONSTANT _RTPROF-PH-WIRE-ENCODE

0x00FFFFFFFFFFFFFF CONSTANT _RTPROF-SEQUENCE-MASK

VARIABLE _RTPROF-EVENT
VARIABLE _RTPROF-SEQUENCE

0 _RTPROF-EVENT !
0 _RTPROF-SEQUENCE !

: _RTPROF-MARK  ( phase -- )
    0xFF AND
    DUP _RTPROF-EVENT @ 0xFF AND = IF DROP EXIT THEN
    _RTPROF-SEQUENCE @ 1+ _RTPROF-SEQUENCE-MASK AND
    DUP _RTPROF-SEQUENCE !
    8 LSHIFT OR
    _RTPROF-EVENT ! ;
