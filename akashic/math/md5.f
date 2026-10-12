\ =================================================================
\  md5.f  —  MD5 (RFC 1321)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: MD5- (public), _MD5- (private)
\  Depends on: nothing
\
\  Public API:
\   MD5-SIZE     ( -- bytes )         a sum's record
\   MD5-INIT     ( md5 -- )           start a sum
\   MD5-UPDATE   ( a u md5 -- )       continue it over U bytes at A
\   MD5-FINAL    ( digest md5 -- )    end it, its 16 bytes at DIGEST
\   MD5          ( a u digest -- )    the sum of U bytes at A
\
\  MD5 is broken for signatures and certificates.  It is here because
\  PDF's standard security handler derives its keys with it.
\
\  The caller owns a sum's record, MD5-SIZE bytes.  A block's working
\  state lives in module variables, so one call runs at a time, though
\  any number of sums may take turns.  MD5 itself uses the module's own
\  record.
\ =================================================================

PROVIDED akashic-md5

\ The record: the state's four words, the bytes summed, the bytes waiting
\ in the block, and the block.
: _MD5.A      ( r -- a )      ;
: _MD5.B      ( r -- a )   8 + ;
: _MD5.C      ( r -- a )  16 + ;
: _MD5.D      ( r -- a )  24 + ;
: _MD5.TOTAL  ( r -- a )  32 + ;
: _MD5.N      ( r -- a )  40 + ;
: _MD5.BLOCK  ( r -- a )  48 + ;
112 CONSTANT MD5-SIZE

0xFFFFFFFF CONSTANT _MD5-MASK

\ Each step's sine constant, its shift, and the byte offset of its word
\ of the block (RFC 1321 section 3.4).
CREATE _MD5-K
  0xd76aa478 , 0xe8c7b756 , 0x242070db , 0xc1bdceee ,
  0xf57c0faf , 0x4787c62a , 0xa8304613 , 0xfd469501 ,
  0x698098d8 , 0x8b44f7af , 0xffff5bb1 , 0x895cd7be ,
  0x6b901122 , 0xfd987193 , 0xa679438e , 0x49b40821 ,
  0xf61e2562 , 0xc040b340 , 0x265e5a51 , 0xe9b6c7aa ,
  0xd62f105d , 0x02441453 , 0xd8a1e681 , 0xe7d3fbc8 ,
  0x21e1cde6 , 0xc33707d6 , 0xf4d50d87 , 0x455a14ed ,
  0xa9e3e905 , 0xfcefa3f8 , 0x676f02d9 , 0x8d2a4c8a ,
  0xfffa3942 , 0x8771f681 , 0x6d9d6122 , 0xfde5380c ,
  0xa4beea44 , 0x4bdecfa9 , 0xf6bb4b60 , 0xbebfbc70 ,
  0x289b7ec6 , 0xeaa127fa , 0xd4ef3085 , 0x04881d05 ,
  0xd9d4d039 , 0xe6db99e5 , 0x1fa27cf8 , 0xc4ac5665 ,
  0xf4292244 , 0x432aff97 , 0xab9423a7 , 0xfc93a039 ,
  0x655b59c3 , 0x8f0ccc92 , 0xffeff47d , 0x85845dd1 ,
  0x6fa87e4f , 0xfe2ce6e0 , 0xa3014314 , 0x4e0811a1 ,
  0xf7537e82 , 0xbd3af235 , 0x2ad7d2bb , 0xeb86d391 ,
CREATE _MD5-S
  7 C, 12 C, 17 C, 22 C, 7 C, 12 C, 17 C, 22 C,
  7 C, 12 C, 17 C, 22 C, 7 C, 12 C, 17 C, 22 C,
  5 C, 9 C, 14 C, 20 C, 5 C, 9 C, 14 C, 20 C,
  5 C, 9 C, 14 C, 20 C, 5 C, 9 C, 14 C, 20 C,
  4 C, 11 C, 16 C, 23 C, 4 C, 11 C, 16 C, 23 C,
  4 C, 11 C, 16 C, 23 C, 4 C, 11 C, 16 C, 23 C,
  6 C, 10 C, 15 C, 21 C, 6 C, 10 C, 15 C, 21 C,
  6 C, 10 C, 15 C, 21 C, 6 C, 10 C, 15 C, 21 C,
CREATE _MD5-G
  0 C, 4 C, 8 C, 12 C, 16 C, 20 C, 24 C, 28 C,
  32 C, 36 C, 40 C, 44 C, 48 C, 52 C, 56 C, 60 C,
  4 C, 24 C, 44 C, 0 C, 20 C, 40 C, 60 C, 16 C,
  36 C, 56 C, 12 C, 32 C, 52 C, 8 C, 28 C, 48 C,
  20 C, 32 C, 44 C, 56 C, 4 C, 16 C, 28 C, 40 C,
  52 C, 0 C, 12 C, 24 C, 36 C, 48 C, 60 C, 8 C,
  0 C, 28 C, 56 C, 20 C, 48 C, 12 C, 40 C, 4 C,
  32 C, 60 C, 24 C, 52 C, 16 C, 44 C, 8 C, 36 C,

VARIABLE _MD5-R    \ the record
VARIABLE _MD5-M    \ the block being summed
VARIABLE _MD5-A  VARIABLE _MD5-B  VARIABLE _MD5-C  VARIABLE _MD5-D

: _MD5-ROTL  ( x s -- x' )
    2DUP LSHIFT -ROT 32 SWAP - RSHIFT OR _MD5-MASK AND ;

\ Step I with F, the round's function of B, C and D.
: _MD5-STEP  ( f i -- )
    >R
    _MD5-A @ +  R@ CELLS _MD5-K + @ +  R@ _MD5-G + C@ _MD5-M @ + L@ +
    _MD5-MASK AND  R> _MD5-S + C@ _MD5-ROTL  _MD5-B @ + _MD5-MASK AND
    _MD5-D @ _MD5-A !  _MD5-C @ _MD5-D !  _MD5-B @ _MD5-C !  _MD5-B ! ;

\ Sum the 64 bytes at M into the record's state.
: _MD5-SUM  ( m -- )
    _MD5-M !
    _MD5-R @ DUP _MD5.A @ _MD5-A !  DUP _MD5.B @ _MD5-B !
    DUP _MD5.C @ _MD5-C !  _MD5.D @ _MD5-D !
    16 0 DO
        _MD5-B @ DUP _MD5-C @ AND SWAP INVERT _MD5-D @ AND OR  I _MD5-STEP
    LOOP
    32 16 DO
        _MD5-D @ DUP _MD5-B @ AND SWAP INVERT _MD5-C @ AND OR  I _MD5-STEP
    LOOP
    48 32 DO  _MD5-B @ _MD5-C @ XOR _MD5-D @ XOR  I _MD5-STEP  LOOP
    64 48 DO  _MD5-D @ INVERT _MD5-B @ OR _MD5-C @ XOR  I _MD5-STEP  LOOP
    _MD5-R @ >R
    _MD5-A @ R@ _MD5.A @ + _MD5-MASK AND R@ _MD5.A !
    _MD5-B @ R@ _MD5.B @ + _MD5-MASK AND R@ _MD5.B !
    _MD5-C @ R@ _MD5.C @ + _MD5-MASK AND R@ _MD5.C !
    _MD5-D @ R@ _MD5.D @ + _MD5-MASK AND R> _MD5.D ! ;

\ MD5-INIT ( md5 -- )   Start a sum.
: MD5-INIT  ( md5 -- )
    DUP MD5-SIZE 0 FILL
    0x67452301 OVER _MD5.A !  0xefcdab89 OVER _MD5.B !
    0x98badcfe OVER _MD5.C !  0x10325476 SWAP _MD5.D ! ;

\ MD5-UPDATE ( a u md5 -- )   Continue the sum over U bytes at A.
: MD5-UPDATE  ( a u md5 -- )
    _MD5-R !  DUP _MD5-R @ _MD5.TOTAL +!
    BEGIN DUP WHILE
        _MD5-R @ _MD5.N @ 0= OVER 64 < 0= AND IF
            OVER _MD5-SUM  64 - SWAP 64 + SWAP
        ELSE
            64 _MD5-R @ _MD5.N @ - OVER MIN               ( a u k )
            2 PICK _MD5-R @ DUP _MD5.BLOCK SWAP _MD5.N @ + 2 PICK MOVE
            DUP _MD5-R @ _MD5.N +!
            TUCK - >R + R>
            _MD5-R @ _MD5.N @ 64 = IF
                _MD5-R @ _MD5.BLOCK _MD5-SUM  0 _MD5-R @ _MD5.N !
            THEN
        THEN
    REPEAT 2DROP ;

CREATE _MD5-PAD 72 ALLOT
VARIABLE _MD5-P

\ MD5-FINAL ( digest md5 -- )   End the sum and write its 16 bytes.
: MD5-FINAL  ( digest md5 -- )
    DUP _MD5-R !  _MD5.TOTAL @                            ( digest total )
    _MD5-PAD 72 0 FILL  128 _MD5-PAD C!
    DUP 55 SWAP - 63 AND 1+ _MD5-P !                      ( digest total )
    3 LSHIFT DUP _MD5-MASK AND _MD5-PAD _MD5-P @ + L!
    32 RSHIFT _MD5-MASK AND _MD5-PAD _MD5-P @ + 4 + L!
    _MD5-PAD _MD5-P @ 8 + _MD5-R @ MD5-UPDATE
    _MD5-R @ _MD5.A @ OVER L!  _MD5-R @ _MD5.B @ OVER 4 + L!
    _MD5-R @ _MD5.C @ OVER 8 + L!  _MD5-R @ _MD5.D @ SWAP 12 + L! ;

CREATE _MD5-ONE MD5-SIZE ALLOT

\ MD5 ( a u digest -- )   The sum of U bytes at A, 16 bytes at DIGEST.
: MD5  ( a u digest -- )
    >R _MD5-ONE MD5-INIT  _MD5-ONE MD5-UPDATE  R> _MD5-ONE MD5-FINAL ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _md5-guard

' MD5-UPDATE  CONSTANT _md5-update-xt
' MD5-FINAL   CONSTANT _md5-final-xt
' MD5         CONSTANT _md5-xt

: MD5-UPDATE  _md5-update-xt _md5-guard WITH-GUARD ;
: MD5-FINAL   _md5-final-xt _md5-guard WITH-GUARD ;
: MD5         _md5-xt _md5-guard WITH-GUARD ;
[THEN] [THEN]
