\ =================================================================
\  sort.f  —  Sorting & rank operations for FP16 arrays in HBW
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: SORT-
\  Depends on: fp16.f  fp16-ext.f
\
\  Public API:
\   SORT-FP16       ( addr n -- )        in-place ascending sort
\   SORT-FP16-DESC  ( addr n -- )        in-place descending sort
\   SORT-NTH        ( addr n k -- val )  k-th smallest (quickselect)
\   SORT-IS-SORTED? ( addr n -- flag )   check ascending order
\   SORT-REVERSE    ( addr n -- )        reverse in-place
\   SORT-ARGSORT    ( src idx n -- )     index permutation (stable)
\   SORT-RANK       ( src dst n -- )     rank elements (1-based, avg ties)
\
\  All addresses are HBW pointers.  Elements are 16-bit FP16
\  values accessed via W@ / W!.
\
\  SORT-FP16 uses Shell sort with Knuth's gap sequence
\  (1, 4, 13, 40, 121, 364, 1093, …), giving O(n^1.5) average.
\
\  SORT-NTH uses iterative quickselect with Lomuto partition.
\  O(n) average.  DESTRUCTIVE — rearranges the array.
\ =================================================================

REQUIRE fp16.f
REQUIRE fp16-ext.f

PROVIDED akashic-sort

\ =====================================================================
\  Internal helpers
\ =====================================================================

VARIABLE _SORT-TMP

\ Swap 16-bit values at two HBW addresses
: _SORT-SWAP  ( addr1 addr2 -- )
    OVER W@ _SORT-TMP !
    DUP  W@ ROT W!
    _SORT-TMP @ SWAP W! ;

\ =====================================================================
\  SORT-IS-SORTED? — check ascending order
\ =====================================================================

VARIABLE _SIS-ADDR

: SORT-IS-SORTED?  ( addr n -- flag )
    DUP 2 < IF 2DROP TRUE EXIT THEN
    SWAP _SIS-ADDR !
    1- 0 DO
        _SIS-ADDR @ I 2 * + W@
        _SIS-ADDR @ I 1+ 2 * + W@
        FP16-GT IF FALSE UNLOOP EXIT THEN
    LOOP
    TRUE ;

\ =====================================================================
\  SORT-REVERSE — reverse array in-place
\ =====================================================================

: SORT-REVERSE  ( addr n -- )
    DUP 2 < IF 2DROP EXIT THEN
    OVER SWAP 1- 2 * OVER +           ( lo-addr hi-addr )
    BEGIN 2DUP < WHILE
        2DUP _SORT-SWAP
        SWAP 2 + SWAP 2 -
    REPEAT
    2DROP ;

\ =====================================================================
\  Shell sort — ascending
\ =====================================================================
\  Gap sequence: Knuth's h = 3h + 1  →  1, 4, 13, 40, 121, 364, …
\  We find the largest gap < n, then descend.

VARIABLE _SH-BASE
VARIABLE _SH-LEN
VARIABLE _SH-GAP
VARIABLE _SH-KEY
VARIABLE _SH-J

: SORT-FP16  ( addr n -- )
    DUP 2 < IF 2DROP EXIT THEN
    _SH-LEN !  _SH-BASE !

    \ Find starting gap: largest h = 3h+1 that is < n
    1 BEGIN DUP _SH-LEN @ < WHILE 3 * 1+ REPEAT
    1- 3 / _SH-GAP !

    BEGIN _SH-GAP @ 0> WHILE
        _SH-LEN @ _SH-GAP @ DO        \ i = gap … n-1
            _SH-BASE @ I 2 * + W@ _SH-KEY !
            I _SH-J !
            BEGIN
                _SH-J @ _SH-GAP @ >=
                IF
                    _SH-KEY @
                    _SH-BASE @ _SH-J @ _SH-GAP @ - 2 * + W@
                    FP16-LT
                ELSE
                    FALSE
                THEN
            WHILE
                _SH-BASE @ _SH-J @ _SH-GAP @ - 2 * + W@
                _SH-BASE @ _SH-J @ 2 * + W!
                _SH-J @ _SH-GAP @ - _SH-J !
            REPEAT
            _SH-KEY @ _SH-BASE @ _SH-J @ 2 * + W!
        LOOP
        _SH-GAP @ 1- 3 / _SH-GAP !
    REPEAT ;

\ =====================================================================
\  SORT-FP16-DESC — descending sort (sort ascending then reverse)
\ =====================================================================

: SORT-FP16-DESC  ( addr n -- )
    2DUP SORT-FP16
    SORT-REVERSE ;

\ =====================================================================
\  Quickselect internals (Lomuto partition)
\ =====================================================================

VARIABLE _QS-BASE
VARIABLE _QS-LO
VARIABLE _QS-HI
VARIABLE _QS-K
VARIABLE _QS-I
VARIABLE _QS-PIVOT-VAL

: _QS-ELEM  ( idx -- val )
    2 * _QS-BASE @ + W@ ;

: _QS-SWAP-IDX  ( i j -- )
    2 * _QS-BASE @ +
    SWAP 2 * _QS-BASE @ +
    _SORT-SWAP ;

\ Partition around pivot = arr[hi].  Returns final pivot index.
: _QS-PARTITION  ( lo hi -- pivot-pos )
    DUP _QS-ELEM _QS-PIVOT-VAL !
    OVER 1- _QS-I !
    DUP ROT                            ( hi hi lo )
    ?DO
        I _QS-ELEM _QS-PIVOT-VAL @ FP16-LE IF
            _QS-I @ 1+ _QS-I !
            _QS-I @ I _QS-SWAP-IDX
        THEN
    LOOP                                ( hi )
    _QS-I @ 1+                          ( hi pivot-pos )
    TUCK _QS-SWAP-IDX ;                ( pivot-pos )

\ =====================================================================
\  SORT-NTH — k-th order statistic (0-based) via quickselect
\ =====================================================================
\  Finds the k-th smallest element.  DESTRUCTIVE.

: SORT-NTH  ( addr n k -- val )
    ROT _QS-BASE !
    SWAP 1- _QS-HI !
    _QS-K !
    0 _QS-LO !
    BEGIN
        _QS-LO @ _QS-HI @ <
    WHILE
        _QS-LO @ _QS-HI @ _QS-PARTITION   ( pivot-pos )
        DUP _QS-K @ = IF
            _QS-ELEM EXIT
        THEN
        DUP _QS-K @ > IF
            1- _QS-HI !
        ELSE
            1+ _QS-LO !
        THEN
    REPEAT
    _QS-LO @ _QS-ELEM ;

\ =====================================================================
\  SORT-ARGSORT — Index permutation for ascending FP16 sort
\ =====================================================================
\  Fills idx[0..n-1] with the indices that would sort src ascendingly.
\  Uses insertion sort on index array — stable, O(n²) but sufficient
\  for typical dataset sizes (n ≤ 2048).
\  idx is an array of 64-bit cells (8 bytes each).

VARIABLE _SA-SRC
VARIABLE _SA-IDX
VARIABLE _SA-LEN
VARIABLE _SA-KEY
VARIABLE _SA-J

: SORT-ARGSORT  ( src idx n -- )
    DUP 0= IF DROP 2DROP EXIT THEN
    _SA-LEN !  _SA-IDX !  _SA-SRC !

    \ Initialize idx[i] = i
    _SA-LEN @ 0 DO
        I _SA-IDX @ I 8 * + !
    LOOP

    \ Insertion sort on idx, comparing src[idx[i]]
    _SA-LEN @ 1 DO
        _SA-IDX @ I 8 * + @ _SA-KEY !     \ key = idx[i]
        I 1- _SA-J !
        BEGIN
            _SA-J @ 0 >=
            IF
                \ Compare src[idx[j]] > src[key]?
                _SA-SRC @ _SA-IDX @ _SA-J @ 8 * + @ 2 * + W@
                _SA-SRC @ _SA-KEY @ 2 * + W@
                FP16-GT
            ELSE
                FALSE
            THEN
        WHILE
            \ idx[j+1] = idx[j]
            _SA-IDX @ _SA-J @ 8 * + @
            _SA-IDX @ _SA-J @ 1+ 8 * + !
            _SA-J @ 1- _SA-J !
        REPEAT
        _SA-KEY @ _SA-IDX @ _SA-J @ 1+ 8 * + !
    LOOP ;

\ =====================================================================
\  SORT-RANK — Rank elements (1-based, average ties)
\ =====================================================================
\  Assigns ranks to each element of src.  Tied elements receive the
\  average of their positional ranks.
\
\  dst is an array of FP16 values (ranks as FP16).
\
\  Algorithm:
\    1. Argsort src → index permutation
\    2. Walk sorted order, detect tie groups, assign average rank
\    3. Scatter ranks back to original positions via index array
\
\  Uses _SORT-RANKBUF for the index array (8 bytes per element,
\  supports n ≤ 512).  Rank computation uses integer + FP16 math
\  (no FP32 dependency).

512 CONSTANT _SORT-MAX-RANK-N
_SORT-MAX-RANK-N 8 * HBW-ALLOT CONSTANT _SORT-RANKBUF

VARIABLE _SR-SRC
VARIABLE _SR-DST
VARIABLE _SR-LEN
VARIABLE _SR-I
VARIABLE _SR-J

: SORT-RANK  ( src dst n -- )
    DUP 0= IF DROP 2DROP EXIT THEN
    DUP 1 = IF
        DROP SWAP DROP   \ ( dst )
        FP16-POS-ONE SWAP W!
        EXIT
    THEN
    _SR-LEN !  _SR-DST !  _SR-SRC !

    \ Argsort into dedicated rank buffer
    _SR-SRC @ _SORT-RANKBUF _SR-LEN @ SORT-ARGSORT

    \ Walk sorted order, detect ties, assign average ranks
    0 _SR-I !
    BEGIN _SR-I @ _SR-LEN @ < WHILE
        \ Find tie group: all elements equal to src[idx[i]]
        _SR-SRC @ _SORT-RANKBUF _SR-I @ 8 * + @ 2 * + W@   \ val at rank i
        _SR-I @ _SR-J !
        BEGIN
            _SR-J @ 1+ _SR-LEN @ <
            IF
                _SR-SRC @ _SORT-RANKBUF _SR-J @ 1+ 8 * + @ 2 * + W@
                OVER FP16-EQ
            ELSE
                FALSE
            THEN
        WHILE
            _SR-J @ 1+ _SR-J !
        REPEAT
        DROP   \ drop the value we were comparing

        \ Tie group is [i .. j] inclusive
        \ Average rank = (i+1 + j+1) / 2 = (i+j+2) / 2
        \ If (i+j) is even → integer rank; if odd → half-integer rank
        _SR-I @ _SR-J @ + 2 +       \ i+j+2 (integer)
        DUP 1 AND IF                 \ odd → result is x.5
            1- 2/ INT>FP16           \ integer part
            0x3800 FP16-ADD          \ + 0.5 in FP16
        ELSE
            2/ INT>FP16              \ exact integer rank
        THEN

        \ Scatter to all positions in the tie group
        _SR-J @ 1+ _SR-I @ DO
            DUP                              ( avg-rank avg-rank )
            _SR-DST @                        ( avg-rank avg-rank dst )
            _SORT-RANKBUF I 8 * + @          ( avg-rank avg-rank dst orig-idx )
            2 * + W!                         ( avg-rank )
        LOOP
        DROP   \ drop avg-rank

        _SR-J @ 1+ _SR-I !
    REPEAT ;

\ ── Concurrency Guard ───────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _sort-guard

' SORT-IS-SORTED? CONSTANT _sort-issorted-xt
' SORT-REVERSE     CONSTANT _sort-reverse-xt
' SORT-FP16        CONSTANT _sort-fp16-xt
' SORT-FP16-DESC   CONSTANT _sort-fp16desc-xt
' SORT-NTH         CONSTANT _sort-nth-xt
' SORT-ARGSORT     CONSTANT _sort-argsort-xt
' SORT-RANK        CONSTANT _sort-rank-xt

: SORT-IS-SORTED? _sort-issorted-xt _sort-guard WITH-GUARD ;
: SORT-REVERSE    _sort-reverse-xt  _sort-guard WITH-GUARD ;
: SORT-FP16       _sort-fp16-xt     _sort-guard WITH-GUARD ;
: SORT-FP16-DESC  _sort-fp16desc-xt _sort-guard WITH-GUARD ;
: SORT-NTH        _sort-nth-xt      _sort-guard WITH-GUARD ;
: SORT-ARGSORT    _sort-argsort-xt  _sort-guard WITH-GUARD ;
: SORT-RANK       _sort-rank-xt     _sort-guard WITH-GUARD ;
[THEN] [THEN]
