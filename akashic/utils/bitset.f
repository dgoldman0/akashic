\ =====================================================================
\  bitset.f - Checked caller-bounded LSB0 bitmap algebra
\ =====================================================================
\  A view is a byte buffer plus a nonnegative logical bit count.  Bits
\  are numbered least-significant-first within each byte.  The logical
\  count bounds every query and mutation; padding bits are never implied
\  members of the set.
\
\  Query words return validity separately from their value.  Mutation
\  words return a validity flag and validate a whole range before changing
\  its first bit.  A null empty view is valid; a null nonempty view is not.
\ =====================================================================

PROVIDED akashic-bitset

REQUIRE uint-range.f

: BITSET-BYTES?  ( bit-count -- byte-count valid? )
    DUP 0< IF DROP 0 FALSE EXIT THEN
    8 /MOD SWAP 0<> IF 1+ THEN TRUE ;

: _BITSET-VALID?  ( buffer bit-count -- valid? )
    DUP BITSET-BYTES? 0= IF DROP 2DROP FALSE EXIT THEN
    >R
    OVER 0= OVER 0<> AND IF
        2DROP R> DROP FALSE EXIT
    THEN
    DROP R> URANGE-VALID? ;

: _BITSET-RANGE-VALID?  ( buffer bit-count first count -- valid? )
    2OVER _BITSET-VALID? 0= IF 2DROP 2DROP FALSE EXIT THEN
    2DUP URANGE-VALID? 0= IF 2DROP 2DROP FALSE EXIT THEN
    + OVER U> 0= NIP NIP ;

: _BITSET-RAW@  ( buffer bit -- set? )
    DUP 8 / ROT + C@
    SWAP 8 MOD 1 SWAP LSHIFT AND 0<> ;

: _BITSET-RAW-SET  ( buffer bit -- )
    DUP 8 / ROT +
    DUP C@ ROT 8 MOD 1 SWAP LSHIFT OR SWAP C! ;

: _BITSET-RAW-CLEAR  ( buffer bit -- )
    DUP 8 / ROT +
    DUP C@ ROT 8 MOD 1 SWAP LSHIFT INVERT AND SWAP C! ;

: BITSET-ALL-SET?  ( buffer bit-count first count -- all-set? valid? )
    2OVER 2OVER _BITSET-RANGE-VALID? 0= IF
        2DROP 2DROP FALSE FALSE EXIT
    THEN
    ROT DROP
    0 ?DO
        2DUP I + _BITSET-RAW@ 0= IF
            2DROP FALSE TRUE UNLOOP EXIT
        THEN
    LOOP
    2DROP TRUE TRUE ;

: BITSET-ALL-CLEAR?  ( buffer bit-count first count -- all-clear? valid? )
    2OVER 2OVER _BITSET-RANGE-VALID? 0= IF
        2DROP 2DROP FALSE FALSE EXIT
    THEN
    ROT DROP
    0 ?DO
        2DUP I + _BITSET-RAW@ IF
            2DROP FALSE TRUE UNLOOP EXIT
        THEN
    LOOP
    2DROP TRUE TRUE ;

: BITSET-RANGE-SET?  ( buffer bit-count first count -- valid? )
    2OVER 2OVER _BITSET-RANGE-VALID? 0= IF
        2DROP 2DROP FALSE EXIT
    THEN
    ROT DROP
    0 ?DO
        2DUP I + _BITSET-RAW-SET
    LOOP
    2DROP TRUE ;

: BITSET-RANGE-CLEAR?  ( buffer bit-count first count -- valid? )
    2OVER 2OVER _BITSET-RANGE-VALID? 0= IF
        2DROP 2DROP FALSE EXIT
    THEN
    ROT DROP
    0 ?DO
        2DUP I + _BITSET-RAW-CLEAR
    LOOP
    2DROP TRUE ;

: BITSET-TEST?  ( buffer bit-count bit -- set? valid? )
    1 BITSET-ALL-SET? ;

: BITSET-BIT-SET?  ( buffer bit-count bit -- valid? )
    1 BITSET-RANGE-SET? ;

: BITSET-BIT-CLEAR?  ( buffer bit-count bit -- valid? )
    1 BITSET-RANGE-CLEAR? ;

: _BITSET-BYTE-POPCOUNT  ( byte -- set-count )
    DUP 1 RSHIFT 0x55 AND -
    DUP 0x33 AND SWAP 2 RSHIFT 0x33 AND +
    DUP 4 RSHIFT + 0x0F AND ;

: _BITSET-LOW-MASK  ( bit-count -- mask )
    1 SWAP LSHIFT 1- ;

: BITSET-COUNT-SET?  ( buffer bit-count -- set-count valid? )
    2DUP _BITSET-VALID? 0= IF 2DROP 0 FALSE EXIT THEN
    8 /MOD
    DUP 0 SWAP
    0 ?DO
        3 PICK I + C@ _BITSET-BYTE-POPCOUNT +
    LOOP
    2 PICK IF
        2 PICK _BITSET-LOW-MASK
        4 PICK 3 PICK + C@ AND _BITSET-BYTE-POPCOUNT +
    THEN
    NIP NIP NIP TRUE ;

: BITSET-FIND-CLEAR?  ( buffer bit-count first -- bit found? valid? )
    2 PICK 2 PICK 2 PICK 0 _BITSET-RANGE-VALID? 0= IF
        2DROP DROP 0 FALSE FALSE EXIT
    THEN
    0 FALSE 2SWAP
    ?DO
        2 PICK I _BITSET-RAW@ 0= IF
            2DROP I TRUE LEAVE
        THEN
    LOOP
    ROT DROP TRUE ;
