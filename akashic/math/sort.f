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
