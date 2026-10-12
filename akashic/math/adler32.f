\ =================================================================
\  adler32.f  —  Adler-32 checksum (RFC 1950)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: ADLER32-
\  Depends on: (none)
\
\  Public API:
\   ADLER32-INIT    ( -- 1 )                 the sum of no bytes
\   ADLER32-UPDATE  ( adler a u -- adler' )  continue a sum over U bytes
\   ADLER32         ( a u -- adler )         the sum of U bytes at A
\
\  The sum is S2 * 65536 + S1: S1 is one plus the bytes and S2 the sum of
\  S1 after each byte, both modulo 65521.  A zlib stream carries it after
\  its deflate data.  ADLER32-UPDATE continues from a sum it returned, so a
\  stream is summed a piece at a time.  It keeps no state of its own, so
\  any number of sums may be under way at once.
\ =================================================================

PROVIDED akashic-adler32

\ The largest prime below 65536.
65521 CONSTANT ADLER32-BASE

\ ADLER32-INIT ( -- 1 )   The sum of no bytes.
: ADLER32-INIT  ( -- 1 )  1 ;

\ Bytes summed between reductions.  From sums below ADLER32-BASE, S2 then
\ stays below 65,521 + 2^20 * 65,521 + 255 * 2^39, far below a cell's 2^63.
1048576 CONSTANT _ADLER32-BLOCK

\ Add U bytes at A to S1 and S2, U at most _ADLER32-BLOCK, unreduced.
: _ADLER32-SUM  ( s1 s2 a u -- s1' s2' )
    OVER + SWAP ?DO
        SWAP I C@ + TUCK +
    LOOP ;

\ ADLER32-UPDATE ( adler a u -- adler' )
\   The sum ADLER continued over U bytes at A.
: ADLER32-UPDATE  ( adler a u -- adler' )
    ROT DUP 0xFFFF AND SWAP 16 RSHIFT 0xFFFF AND
    2SWAP
    BEGIN DUP WHILE
        2DUP _ADLER32-BLOCK MIN >R >R 2SWAP R> R@ _ADLER32-SUM
        ADLER32-BASE MOD SWAP ADLER32-BASE MOD SWAP
        2SWAP R> TUCK - >R + R>
    REPEAT 2DROP
    16 LSHIFT OR ;

\ ADLER32 ( a u -- adler )   The sum of U bytes at A.
: ADLER32  ( a u -- adler )  ADLER32-INIT -ROT ADLER32-UPDATE ;
