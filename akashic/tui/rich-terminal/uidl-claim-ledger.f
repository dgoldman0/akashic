\ =====================================================================
\  uidl-claim-ledger.f -- admitted UIDL semantic paint claims
\ =====================================================================
\
\  Converts one complete admitted UMSN menu family into a canonical,
\  pointer-free bank of absolute half-open screen rectangles.  Admission is
\  all or none: ADMITTED-COUNT zero means refusal and performs no UMSN record
\  read; otherwise it must equal the exact source record count.  Only
\  PAINTABLE records claim cells, after intersection with both the signed
\  source clip and the positive surface rectangle.
\
\  This is a pure synchronous construction rung.  It allocates nothing and
\  calls no facade, transport, lifecycle, screen, Desk, or application word.
\  Source validation, clipping, selection, and emission share one canonical
\  UMSN pass.  Capacity is demanded only when a nonempty claim is emitted.
\
\  Public build API:
\    RUCL-BUILD  ( request -- claim-count status )
\
\  Prefix: RUCL- (contract), _RUCL- (implementation)

PROVIDED akashic-tui-rterm-uidl-claim-ledger

REQUIRE ../uidl-menu-snapshot.f
REQUIRE ../../utils/memory-span.f

0 CONSTANT RUCL-S-OK
1 CONSTANT RUCL-S-CAPACITY
2 CONSTANT RUCL-S-INVALID

: RUCL-STATUS-VALID?  ( status -- flag )  3 U< ;

\ Request fields are native cells.  RECORDS and CLAIMS are independently
\ caller-sized.  A zero-sized optional span has address zero.
\
\   +0   attachment token       +56  clip height
\   +8   source generation      +64  clip width
\   +16  admitted record count  +72  UMSN records address
\   +24  surface columns        +80  UMSN records bytes
\   +32  surface rows           +88  claim bank address
\   +40  signed clip row        +96  claim bank bytes
\   +48  signed clip column     +104 reserved zero

: _RUCL-Q.ATTACHMENT  ( q -- a )       ;
: _RUCL-Q.SOURCE-GEN  ( q -- a )   8 + ;
: _RUCL-Q.ADMITTED    ( q -- a )  16 + ;
: _RUCL-Q.SURFACE-W   ( q -- a )  24 + ;
: _RUCL-Q.SURFACE-H   ( q -- a )  32 + ;
: _RUCL-Q.CLIP-ROW    ( q -- a )  40 + ;
: _RUCL-Q.CLIP-COL    ( q -- a )  48 + ;
: _RUCL-Q.CLIP-H      ( q -- a )  56 + ;
: _RUCL-Q.CLIP-W      ( q -- a )  64 + ;
: _RUCL-Q.RECORDS-A   ( q -- a )  72 + ;
: _RUCL-Q.RECORDS-U   ( q -- a )  80 + ;
: _RUCL-Q.CLAIMS-A    ( q -- a )  88 + ;
: _RUCL-Q.CLAIMS-U    ( q -- a )  96 + ;
: _RUCL-Q.RESERVED    ( q -- a ) 104 + ;

112 CONSTANT RUCL-REQUEST-SIZE

: RUCL-REQUEST-BYTES  ( -- bytes )  RUCL-REQUEST-SIZE ;

: RUCL-REQUEST-CLEAR  ( request -- )
    RUCL-REQUEST-SIZE 0 FILL ;

: RUCL-REQUEST-ADMISSION!
    ( attachment source-generation admitted-record-count request -- )
    >R
    R@ _RUCL-Q.ADMITTED !
    R@ _RUCL-Q.SOURCE-GEN !
    R> _RUCL-Q.ATTACHMENT ! ;

: RUCL-REQUEST-GEOMETRY!
    ( surface-cols surface-rows clip-row clip-col clip-height clip-width
      request -- )
    >R
    R@ _RUCL-Q.CLIP-W !
    R@ _RUCL-Q.CLIP-H !
    R@ _RUCL-Q.CLIP-COL !
    R@ _RUCL-Q.CLIP-ROW !
    R@ _RUCL-Q.SURFACE-H !
    R> _RUCL-Q.SURFACE-W ! ;

: RUCL-REQUEST-STORAGE!
    ( records-a records-u claims-a claims-u request -- )
    >R
    R@ _RUCL-Q.CLAIMS-U !
    R@ _RUCL-Q.CLAIMS-A !
    R@ _RUCL-Q.RECORDS-U !
    R> _RUCL-Q.RECORDS-A ! ;

\ Claims are pointer-free, absolute, half-open rectangles.  ATTACHMENT plus
\ the UMSN stable key remains exact across independently hosted UCTX sources.
\
\   +0   attachment token       +40  resolved paint z
\   +8   source generation      +48  row0
\   +16  source kind            +56  col0
\   +24  source index           +64  row1 exclusive
\   +32  semantic subkey        +72  col1 exclusive

: _RUCL-C.ATTACHMENT  ( claim -- a )       ;
: _RUCL-C.GENERATION  ( claim -- a )   8 + ;
: _RUCL-C.SOURCE      ( claim -- a )  16 + ;
: _RUCL-C.INDEX       ( claim -- a )  24 + ;
: _RUCL-C.SUBKEY      ( claim -- a )  32 + ;
: _RUCL-C.Z           ( claim -- a )  40 + ;
: _RUCL-C.ROW0        ( claim -- a )  48 + ;
: _RUCL-C.COL0        ( claim -- a )  56 + ;
: _RUCL-C.ROW1        ( claim -- a )  64 + ;
: _RUCL-C.COL1        ( claim -- a )  72 + ;

80 CONSTANT RUCL-CLAIM-SIZE

: RUCL-CLAIM-BYTES  ( -- bytes )  RUCL-CLAIM-SIZE ;

: RUCL-CLAIM-ATTACHMENT@  ( claim -- token )
    _RUCL-C.ATTACHMENT @ ;
: RUCL-CLAIM-SOURCE-GENERATION@  ( claim -- generation )
    _RUCL-C.GENERATION @ ;
: RUCL-CLAIM-SOURCE@  ( claim -- source-kind )
    _RUCL-C.SOURCE @ ;
: RUCL-CLAIM-SOURCE-INDEX@  ( claim -- source-index )
    _RUCL-C.INDEX @ ;
: RUCL-CLAIM-SUBKEY@  ( claim -- semantic-subkey )
    _RUCL-C.SUBKEY @ ;
: RUCL-CLAIM-Z@  ( claim -- z )  _RUCL-C.Z @ ;
: RUCL-CLAIM-ROW0@  ( claim -- row )  _RUCL-C.ROW0 @ ;
: RUCL-CLAIM-COL0@  ( claim -- col )  _RUCL-C.COL0 @ ;
: RUCL-CLAIM-ROW1@  ( claim -- row )  _RUCL-C.ROW1 @ ;
: RUCL-CLAIM-COL1@  ( claim -- col )  _RUCL-C.COL1 @ ;

\ Local read-only view of the versioned UMSN record contract.
: _RUCL-R.MAGIC       ( r -- a )       ;
: _RUCL-R.ABI         ( r -- a )   8 + ;
: _RUCL-R.BYTES       ( r -- a )  16 + ;
: _RUCL-R.GENERATION  ( r -- a )  24 + ;
: _RUCL-R.SOURCE      ( r -- a )  32 + ;
: _RUCL-R.INDEX       ( r -- a )  40 + ;
: _RUCL-R.SUBKEY      ( r -- a )  48 + ;
: _RUCL-R.PARENT      ( r -- a )  56 + ;
: _RUCL-R.KIND        ( r -- a )  64 + ;
: _RUCL-R.STATE       ( r -- a )  72 + ;
: _RUCL-R.ORDINAL     ( r -- a )  80 + ;
: _RUCL-R.RESOLVED    ( r -- a ) 120 + ;

-1 1 RSHIFT CONSTANT _RUCL-SIGNED-MAX
_RUCL-SIGNED-MAX INVERT CONSTANT _RUCL-SIGNED-MIN
0xFFFFFFFF CONSTANT _RUCL-U32-MAX

CREATE _RUCL-OWNED-START

VARIABLE _RUCL-Q
VARIABLE _RUCL-ATTACHMENT
VARIABLE _RUCL-SOURCE-GEN
VARIABLE _RUCL-ADMITTED
VARIABLE _RUCL-SURFACE-W
VARIABLE _RUCL-SURFACE-H
VARIABLE _RUCL-CLIP-ROW
VARIABLE _RUCL-CLIP-COL
VARIABLE _RUCL-CLIP-H
VARIABLE _RUCL-CLIP-W
VARIABLE _RUCL-RECORDS-A
VARIABLE _RUCL-RECORDS-U
VARIABLE _RUCL-CLAIMS-A
VARIABLE _RUCL-CLAIMS-U

VARIABLE _RUCL-RECORD-COUNT
VARIABLE _RUCL-CLAIM-CAP
VARIABLE _RUCL-CLAIM-COUNT
VARIABLE _RUCL-STATUS
VARIABLE _RUCL-RANGES-VALID
VARIABLE _RUCL-CLIP-ROW-END
VARIABLE _RUCL-CLIP-COL-END

VARIABLE _RUCL-RECORD
VARIABLE _RUCL-PRIOR-INDEX
VARIABLE _RUCL-HAVE-PRIOR
VARIABLE _RUCL-INDEX
VARIABLE _RUCL-PARENT
VARIABLE _RUCL-KIND
VARIABLE _RUCL-STATE
VARIABLE _RUCL-ROW
VARIABLE _RUCL-COL
VARIABLE _RUCL-H
VARIABLE _RUCL-W
VARIABLE _RUCL-Z
VARIABLE _RUCL-ROW-END
VARIABLE _RUCL-COL-END
VARIABLE _RUCL-ROW0
VARIABLE _RUCL-COL0
VARIABLE _RUCL-ROW1
VARIABLE _RUCL-COL1
VARIABLE _RUCL-CLAIM
VARIABLE _RUCL-OWNED-LIMIT

: _RUCL-ALIGNED?  ( a -- flag )  7 AND 0= ;

: _RUCL-SPAN?  ( a u -- flag )
    OVER 0<> OVER 0> AND 0= IF 2DROP 0 EXIT THEN
    OVER _RUCL-ALIGNED? 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _RUCL-OPTIONAL-SPAN?  ( a u -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF DROP 0= EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    OVER _RUCL-ALIGNED? 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _RUCL-PAIR-DISJOINT?  ( a u b v -- flag )
    MSPAN-OVERLAP? 0= ;

: _RUCL-OWNED-DISJOINT?  ( a u -- flag )
    DUP 0= IF 2DROP -1 EXIT THEN
    _RUCL-OWNED-LIMIT @ DUP _RUCL-OWNED-START U< IF
        DROP 2DROP 0 EXIT
    THEN
    _RUCL-OWNED-START - >R
    2DUP _RUCL-OWNED-START R> MSPAN-OVERLAP? 0= NIP NIP ;

: _RUCL-U32?  ( u -- flag )
    DUP 0< IF DROP 0 EXIT THEN _RUCL-U32-MAX U> 0= ;

: _RUCL-SIGNED?  ( n -- flag )
    DUP _RUCL-SIGNED-MIN < IF DROP 0 EXIT THEN
    _RUCL-SIGNED-MAX > 0= ;

\ Signed start plus a nonnegative signed length, including an empty clip.
: _RUCL-IEND0?  ( start length -- end flag )
    DUP 0< IF 2DROP 0 0 EXIT THEN
    DUP _RUCL-SIGNED-MAX > IF 2DROP 0 0 EXIT THEN
    OVER _RUCL-SIGNED? 0= IF 2DROP 0 0 EXIT THEN
    _RUCL-SIGNED-MAX OVER - 2 PICK < IF 2DROP 0 0 EXIT THEN
    + -1 ;

: _RUCL-RECORD-AT  ( ordinal -- record )
    UMSN-RECORD-SIZE * _RUCL-RECORDS-A @ + ;

: _RUCL-CLAIM-AT  ( ordinal -- claim )
    RUCL-CLAIM-SIZE * _RUCL-CLAIMS-A @ + ;

: _RUCL-SET-CAPACITY  ( -- )
    _RUCL-STATUS @ RUCL-S-OK = IF RUCL-S-CAPACITY _RUCL-STATUS ! THEN ;

: _RUCL-SET-INVALID  ( -- )  RUCL-S-INVALID _RUCL-STATUS ! ;

: _RUCL-LOAD-REQUEST  ( -- )
    _RUCL-Q @ DUP _RUCL-Q.ATTACHMENT @ _RUCL-ATTACHMENT !
    DUP _RUCL-Q.SOURCE-GEN @ _RUCL-SOURCE-GEN !
    DUP _RUCL-Q.ADMITTED @ _RUCL-ADMITTED !
    DUP _RUCL-Q.SURFACE-W @ _RUCL-SURFACE-W !
    DUP _RUCL-Q.SURFACE-H @ _RUCL-SURFACE-H !
    DUP _RUCL-Q.CLIP-ROW @ _RUCL-CLIP-ROW !
    DUP _RUCL-Q.CLIP-COL @ _RUCL-CLIP-COL !
    DUP _RUCL-Q.CLIP-H @ _RUCL-CLIP-H !
    DUP _RUCL-Q.CLIP-W @ _RUCL-CLIP-W !
    DUP _RUCL-Q.RECORDS-A @ _RUCL-RECORDS-A !
    DUP _RUCL-Q.RECORDS-U @ _RUCL-RECORDS-U !
    DUP _RUCL-Q.CLAIMS-A @ _RUCL-CLAIMS-A !
    _RUCL-Q.CLAIMS-U @ _RUCL-CLAIMS-U ! ;

: _RUCL-SPANS-SHAPED?  ( -- flag )
    _RUCL-RECORDS-A @ _RUCL-RECORDS-U @
        _RUCL-OPTIONAL-SPAN? 0= IF 0 EXIT THEN
    _RUCL-RECORDS-U @ UMSN-RECORD-SIZE MOD IF 0 EXIT THEN
    _RUCL-CLAIMS-A @ _RUCL-CLAIMS-U @
        _RUCL-OPTIONAL-SPAN? 0= IF 0 EXIT THEN
    _RUCL-CLAIMS-U @ RUCL-CLAIM-SIZE MOD IF 0 EXIT THEN
    -1 ;

: _RUCL-RANGE-AUTHORITY?  ( -- flag )
    _RUCL-SPANS-SHAPED? 0= IF 0 EXIT THEN
    _RUCL-Q @ RUCL-REQUEST-SIZE
        _RUCL-RECORDS-A @ _RUCL-RECORDS-U @
        _RUCL-PAIR-DISJOINT? 0= IF 0 EXIT THEN
    _RUCL-Q @ RUCL-REQUEST-SIZE
        _RUCL-CLAIMS-A @ _RUCL-CLAIMS-U @
        _RUCL-PAIR-DISJOINT? 0= IF 0 EXIT THEN
    _RUCL-RECORDS-A @ _RUCL-RECORDS-U @
        _RUCL-CLAIMS-A @ _RUCL-CLAIMS-U @
        _RUCL-PAIR-DISJOINT? 0= IF 0 EXIT THEN
    _RUCL-Q @ RUCL-REQUEST-SIZE _RUCL-OWNED-DISJOINT? 0= IF 0 EXIT THEN
    _RUCL-RECORDS-A @ _RUCL-RECORDS-U @
        _RUCL-OWNED-DISJOINT? 0= IF 0 EXIT THEN
    _RUCL-CLAIMS-A @ _RUCL-CLAIMS-U @
        _RUCL-OWNED-DISJOINT? 0= IF 0 EXIT THEN
    -1 _RUCL-RANGES-VALID !
    -1 ;

: _RUCL-SCALARS?  ( -- flag )
    _RUCL-Q @ _RUCL-Q.RESERVED @ IF 0 EXIT THEN
    _RUCL-ATTACHMENT @ 0= _RUCL-SOURCE-GEN @ 0= OR IF 0 EXIT THEN
    _RUCL-ADMITTED @ 0< IF 0 EXIT THEN
    _RUCL-SURFACE-W @ DUP 0= IF DROP 0 EXIT THEN
    DUP _RUCL-U32? 0= IF DROP 0 EXIT THEN
    _RUCL-SIGNED-MAX U> IF 0 EXIT THEN
    _RUCL-SURFACE-H @ DUP 0= IF DROP 0 EXIT THEN
    DUP _RUCL-U32? 0= IF DROP 0 EXIT THEN
    _RUCL-SIGNED-MAX U> IF 0 EXIT THEN
    _RUCL-CLIP-ROW @ _RUCL-CLIP-H @ _RUCL-IEND0? 0= IF
        DROP 0 EXIT
    THEN _RUCL-CLIP-ROW-END !
    _RUCL-CLIP-COL @ _RUCL-CLIP-W @ _RUCL-IEND0? 0= IF
        DROP 0 EXIT
    THEN _RUCL-CLIP-COL-END !
    -1 ;

: _RUCL-SOURCE-SHAPE?  ( -- flag )
    _RUCL-RECORDS-U @ UMSN-RECORD-SIZE / _RUCL-RECORD-COUNT !
    _RUCL-CLAIMS-U @ RUCL-CLAIM-SIZE / _RUCL-CLAIM-CAP !
    _RUCL-ADMITTED @ 0= IF -1 EXIT THEN
    _RUCL-RECORDS-U @ 0= IF 0 EXIT THEN
    _RUCL-ADMITTED @ _RUCL-RECORD-COUNT @ = ;

: _RUCL-CLEAR-CLAIMS  ( -- )
    _RUCL-RANGES-VALID @ 0= IF EXIT THEN
    _RUCL-CLAIMS-U @ ?DUP IF _RUCL-CLAIMS-A @ SWAP 0 FILL THEN ;

: _RUCL-STATE?  ( -- flag )
    _RUCL-STATE @ 63 INVERT AND IF 0 EXIT THEN
    _RUCL-STATE @ UMSN-F-PAINTABLE AND
    _RUCL-STATE @ UMSN-F-VISIBLE AND 0= AND IF 0 EXIT THEN
    _RUCL-STATE @ UMSN-F-OPEN UMSN-F-SELECTED OR AND
    _RUCL-STATE @ UMSN-F-PAINTABLE AND 0= AND IF 0 EXIT THEN
    _RUCL-KIND @ UMSN-K-MENUBAR = IF
        _RUCL-STATE @
        UMSN-F-VISIBLE UMSN-F-ENABLED OR UMSN-F-PAINTABLE OR
        INVERT AND IF 0 EXIT THEN
        _RUCL-STATE @ UMSN-F-ENABLED AND 0<> EXIT
    THEN
    _RUCL-KIND @ UMSN-K-MENU = IF
        _RUCL-STATE @ UMSN-F-ENABLED AND 0<> EXIT
    THEN
    _RUCL-KIND @ UMSN-K-ITEM = IF
        _RUCL-STATE @
        UMSN-F-VISIBLE UMSN-F-ENABLED OR UMSN-F-FOCUSED OR
        UMSN-F-SELECTED OR UMSN-F-PAINTABLE OR INVERT AND IF
            0 EXIT
        THEN
        _RUCL-STATE @ UMSN-F-ENABLED AND 0<> EXIT
    THEN
    _RUCL-KIND @ UMSN-K-SEPARATOR = IF
        _RUCL-STATE @
        UMSN-F-VISIBLE UMSN-F-PAINTABLE OR INVERT AND 0= EXIT
    THEN
    0 ;

: _RUCL-VALIDATE-ONE?  ( -- flag )
    _RUCL-RECORD @ _RUCL-R.MAGIC @ _UMSN-RECORD-MAGIC <> IF 0 EXIT THEN
    _RUCL-RECORD @ _RUCL-R.ABI @ _UMSN-RECORD-ABI <> IF 0 EXIT THEN
    _RUCL-RECORD @ _RUCL-R.BYTES @ UMSN-RECORD-SIZE <> IF 0 EXIT THEN
    _RUCL-RECORD @ _RUCL-R.GENERATION @
        _RUCL-SOURCE-GEN @ <> IF 0 EXIT THEN
    _RUCL-RECORD @ _RUCL-R.SOURCE @ UMSN-SOURCE-UIDL <> IF 0 EXIT THEN
    _RUCL-RECORD @ _RUCL-R.SUBKEY @ IF 0 EXIT THEN
    _RUCL-RECORD @ _RUCL-R.INDEX @ DUP 0< IF DROP 0 EXIT THEN
    DUP _RUCL-INDEX !
    _RUCL-HAVE-PRIOR @ IF
        _RUCL-INDEX @ _RUCL-PRIOR-INDEX @ U> 0= IF 0 EXIT THEN
    THEN
    _RUCL-INDEX @ _RUCL-PRIOR-INDEX !
    -1 _RUCL-HAVE-PRIOR !
    _RUCL-RECORD @ _RUCL-R.PARENT @ DUP 0< IF DROP 0 EXIT THEN
    _RUCL-PARENT !
    _RUCL-RECORD @ _RUCL-R.KIND @ DUP _RUCL-KIND !
    DUP UMSN-K-MENUBAR < SWAP UMSN-K-SEPARATOR > OR IF 0 EXIT THEN
    _RUCL-KIND @ UMSN-K-MENUBAR = IF
        _RUCL-PARENT @ IF 0 EXIT THEN
    ELSE
        _RUCL-PARENT @ 0= IF 0 EXIT THEN
    THEN
    _RUCL-RECORD @ _RUCL-R.STATE @ _RUCL-STATE !
    _RUCL-STATE? 0= IF 0 EXIT THEN
    _RUCL-RECORD @ _RUCL-R.ORDINAL @ 0< IF 0 EXIT THEN
    _RUCL-RECORD @ _RUCL-R.RESOLVED UTUI-RESOLVED-BYTES
        UTUI-RESOLVED-VALID? ;

: _RUCL-CLIP-ONE?  ( -- nonempty? )
    _RUCL-RECORD @ _RUCL-R.RESOLVED DUP @ _RUCL-ROW !
    DUP 8 + @ _RUCL-COL !
    DUP 16 + @ _RUCL-H !
    DUP 24 + @ _RUCL-W !
    64 + @ _RUCL-Z !
    _RUCL-ROW @ _RUCL-H @ _RUCL-IEND0? 0= IF
        DROP _RUCL-SET-INVALID 0 EXIT
    THEN _RUCL-ROW-END !
    _RUCL-COL @ _RUCL-W @ _RUCL-IEND0? 0= IF
        DROP _RUCL-SET-INVALID 0 EXIT
    THEN _RUCL-COL-END !
    _RUCL-ROW @ _RUCL-CLIP-ROW @ MAX 0 MAX _RUCL-ROW0 !
    _RUCL-COL @ _RUCL-CLIP-COL @ MAX 0 MAX _RUCL-COL0 !
    _RUCL-ROW-END @ _RUCL-CLIP-ROW-END @ MIN
        _RUCL-SURFACE-H @ MIN _RUCL-ROW1 !
    _RUCL-COL-END @ _RUCL-CLIP-COL-END @ MIN
        _RUCL-SURFACE-W @ MIN _RUCL-COL1 !
    _RUCL-ROW1 @ _RUCL-ROW0 @ >
    _RUCL-COL1 @ _RUCL-COL0 @ > AND ;

: _RUCL-EMIT?  ( -- flag )
    _RUCL-CLAIM-COUNT @ _RUCL-CLAIM-CAP @ U< 0= IF
        _RUCL-SET-CAPACITY 0 EXIT
    THEN
    _RUCL-CLAIM-COUNT @ _RUCL-CLAIM-AT DUP _RUCL-CLAIM !
    _RUCL-ATTACHMENT @ OVER _RUCL-C.ATTACHMENT !
    _RUCL-SOURCE-GEN @ OVER _RUCL-C.GENERATION !
    _RUCL-RECORD @ _RUCL-R.SOURCE @ OVER _RUCL-C.SOURCE !
    _RUCL-INDEX @ OVER _RUCL-C.INDEX !
    _RUCL-RECORD @ _RUCL-R.SUBKEY @ OVER _RUCL-C.SUBKEY !
    _RUCL-Z @ OVER _RUCL-C.Z !
    _RUCL-ROW0 @ OVER _RUCL-C.ROW0 !
    _RUCL-COL0 @ OVER _RUCL-C.COL0 !
    _RUCL-ROW1 @ OVER _RUCL-C.ROW1 !
    _RUCL-COL1 @ SWAP _RUCL-C.COL1 !
    1 _RUCL-CLAIM-COUNT +!
    -1 ;

\ This is the only UMSN traversal.  Validation and possible emission happen
\ together, so canonicality is established without a second source pass.
: _RUCL-BUILD-CLAIMS?  ( -- flag )
    0 _RUCL-CLAIM-COUNT !
    0 _RUCL-PRIOR-INDEX ! 0 _RUCL-HAVE-PRIOR !
    _RUCL-RECORD-COUNT @ 0 ?DO
        I _RUCL-RECORD-AT _RUCL-RECORD !
        _RUCL-VALIDATE-ONE? 0= IF 0 UNLOOP EXIT THEN
        _RUCL-STATE @ UMSN-F-PAINTABLE AND IF
            _RUCL-CLIP-ONE? IF
                _RUCL-EMIT? 0= IF 0 UNLOOP EXIT THEN
            ELSE
                _RUCL-STATUS @ RUCL-S-OK <> IF 0 UNLOOP EXIT THEN
            THEN
        THEN
    LOOP
    -1 ;

: _RUCL-FAIL-RESULT  ( -- 0 status )
    _RUCL-CLEAR-CLAIMS
    0 _RUCL-STATUS @ ;

: _RUCL-REFUSED-RESULT  ( -- 0 status )
    _RUCL-CLEAR-CLAIMS
    0 RUCL-S-OK ;

: _RUCL-BUILD-BODY  ( -- claim-count status )
    RUCL-S-OK _RUCL-STATUS !
    0 _RUCL-RANGES-VALID !
    _RUCL-LOAD-REQUEST
    _RUCL-RANGE-AUTHORITY? 0= IF
        _RUCL-SET-INVALID _RUCL-FAIL-RESULT EXIT
    THEN
    _RUCL-SCALARS? 0= IF _RUCL-SET-INVALID _RUCL-FAIL-RESULT EXIT THEN
    _RUCL-SOURCE-SHAPE? 0= IF
        _RUCL-SET-INVALID _RUCL-FAIL-RESULT EXIT
    THEN
    _RUCL-ADMITTED @ 0= IF _RUCL-REFUSED-RESULT EXIT THEN
    _RUCL-BUILD-CLAIMS? 0= IF
        _RUCL-STATUS @ RUCL-S-OK = IF _RUCL-SET-INVALID THEN
        _RUCL-FAIL-RESULT EXIT
    THEN
    _RUCL-CLAIM-COUNT @ RUCL-S-OK ;

: _RUCL-SCRUB  ( -- )
    0 _RUCL-Q ! 0 _RUCL-ATTACHMENT ! 0 _RUCL-SOURCE-GEN !
    0 _RUCL-ADMITTED ! 0 _RUCL-SURFACE-W ! 0 _RUCL-SURFACE-H !
    0 _RUCL-CLIP-ROW ! 0 _RUCL-CLIP-COL !
    0 _RUCL-CLIP-H ! 0 _RUCL-CLIP-W !
    0 _RUCL-RECORDS-A ! 0 _RUCL-RECORDS-U !
    0 _RUCL-CLAIMS-A ! 0 _RUCL-CLAIMS-U !
    0 _RUCL-RECORD-COUNT ! 0 _RUCL-CLAIM-CAP !
    0 _RUCL-CLAIM-COUNT ! 0 _RUCL-STATUS !
    0 _RUCL-RANGES-VALID !
    0 _RUCL-CLIP-ROW-END ! 0 _RUCL-CLIP-COL-END !
    0 _RUCL-RECORD ! 0 _RUCL-PRIOR-INDEX ! 0 _RUCL-HAVE-PRIOR !
    0 _RUCL-INDEX ! 0 _RUCL-PARENT ! 0 _RUCL-KIND !
    0 _RUCL-STATE !
    0 _RUCL-ROW ! 0 _RUCL-COL ! 0 _RUCL-H ! 0 _RUCL-W ! 0 _RUCL-Z !
    0 _RUCL-ROW-END ! 0 _RUCL-COL-END !
    0 _RUCL-ROW0 ! 0 _RUCL-COL0 ! 0 _RUCL-ROW1 ! 0 _RUCL-COL1 !
    0 _RUCL-CLAIM ! ;

: RUCL-BUILD  ( request -- claim-count status )
    _RUCL-Q !
    _RUCL-Q @ RUCL-REQUEST-SIZE _RUCL-SPAN? 0= IF
        _RUCL-SCRUB 0 RUCL-S-INVALID EXIT
    THEN
    ['] _RUCL-BUILD-BODY CATCH ?DUP IF
        DROP _RUCL-SET-INVALID _RUCL-FAIL-RESULT
    THEN
    _RUCL-SCRUB ;

CREATE _RUCL-OWNED-END
_RUCL-OWNED-END _RUCL-OWNED-LIMIT !
