\ =================================================================
\  sha512.f  —  SHA-512 cryptographic hash (software, 64-bit)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: SHA512-
\  Depends on: (none)
\
\  Public API:
\   SHA512-HASH     ( src len dst -- )    one-shot hash, 64 bytes to dst
\   SHA512-BEGIN    ( -- )                start streaming hash
\   SHA512-ADD      ( addr len -- )       feed data to streaming hash
\   SHA512-END      ( dst -- )            finalize, 64 bytes to dst
\   SHA512-.        ( addr -- )           print 64-byte hash as 128 hex chars
\   SHA512->HEX     ( src dst -- n )      convert 64-byte hash to hex string
\   SHA512-COMPARE  ( a b -- flag )       compare two 64-byte hashes
\
\  Constants:
\   SHA512-LEN      ( -- 64 )            hash length in bytes
\   SHA512-HEX-LEN  ( -- 128 )           hex-encoded hash length
\
\  Full software FIPS 180-4 SHA-512 implementation.
\  Megapad-64 is natively 64-bit, so all SHA-512 word operations
\  map directly to cell operations — no masking needed (+, AND, OR,
\  XOR, LSHIFT, RSHIFT all operate on full 64-bit cells).
\ =================================================================

PROVIDED akashic-sha512

\ =====================================================================
\  Constants
\ =====================================================================

64  CONSTANT SHA512-LEN
128 CONSTANT SHA512-HEX-LEN
128 CONSTANT _S512-BLOCK

\ =====================================================================
\  Round constants K[0..79]
\ =====================================================================

CREATE _S512-K
  0x428A2F98D728AE22 , 0x7137449123EF65CD ,
  0xB5C0FBCFEC4D3B2F , 0xE9B5DBA58189DBBC ,
  0x3956C25BF348B538 , 0x59F111F1B605D019 ,
  0x923F82A4AF194F9B , 0xAB1C5ED5DA6D8118 ,
  0xD807AA98A3030242 , 0x12835B0145706FBE ,
  0x243185BE4EE4B28C , 0x550C7DC3D5FFB4E2 ,
  0x72BE5D74F27B896F , 0x80DEB1FE3B1696B1 ,
  0x9BDC06A725C71235 , 0xC19BF174CF692694 ,
  0xE49B69C19EF14AD2 , 0xEFBE4786384F25E3 ,
  0x0FC19DC68B8CD5B5 , 0x240CA1CC77AC9C65 ,
  0x2DE92C6F592B0275 , 0x4A7484AA6EA6E483 ,
  0x5CB0A9DCBD41FBD4 , 0x76F988DA831153B5 ,
  0x983E5152EE66DFAB , 0xA831C66D2DB43210 ,
  0xB00327C898FB213F , 0xBF597FC7BEEF0EE4 ,
  0xC6E00BF33DA88FC2 , 0xD5A79147930AA725 ,
  0x06CA6351E003826F , 0x142929670A0E6E70 ,
  0x27B70A8546D22FFC , 0x2E1B21385C26C926 ,
  0x4D2C6DFC5AC42AED , 0x53380D139D95B3DF ,
  0x650A73548BAF63DE , 0x766A0ABB3C77B2A8 ,
  0x81C2C92E47EDAEE6 , 0x92722C851482353B ,
  0xA2BFE8A14CF10364 , 0xA81A664BBC423001 ,
  0xC24B8B70D0F89791 , 0xC76C51A30654BE30 ,
  0xD192E819D6EF5218 , 0xD69906245565A910 ,
  0xF40E35855771202A , 0x106AA07032BBD1B8 ,
  0x19A4C116B8D2D0C8 , 0x1E376C085141AB53 ,
  0x2748774CDF8EEB99 , 0x34B0BCB5E19B48A8 ,
  0x391C0CB3C5C95A63 , 0x4ED8AA4AE3418ACB ,
  0x5B9CCA4F7763E373 , 0x682E6FF3D6B2B8A3 ,
  0x748F82EE5DEFB2FC , 0x78A5636F43172F60 ,
  0x84C87814A1F0AB72 , 0x8CC702081A6439EC ,
  0x90BEFFFA23631E28 , 0xA4506CEBDE82BDE9 ,
  0xBEF9A3F7B2C67915 , 0xC67178F2E372532B ,
  0xCA273ECEEA26619C , 0xD186B8C721C0C207 ,
  0xEADA7DD6CDE0EB1E , 0xF57D4F7FEE6ED178 ,
  0x06F067AA72176FBA , 0x0A637DC5A2C898A6 ,
  0x113F9804BEF90DAE , 0x1B710B35131C471B ,
  0x28DB77F523047D84 , 0x32CAAB7B40C72493 ,
  0x3C9EBE0A15C9BEBC , 0x431D67C49C100D4C ,
  0x4CC5D4BECB3E42B6 , 0x597F299CFC657E2A ,
  0x5FCB6FAB3AD6FAEC , 0x6C44198C4A475817 ,

\ =====================================================================
\  Initial hash values H[0..7]
\ =====================================================================

CREATE _S512-IV
  0x6A09E667F3BCC908 , 0xBB67AE8584CAA73B ,
  0x3C6EF372FE94F82B , 0xA54FF53A5F1D36F1 ,
  0x510E527FADE682D1 , 0x9B05688C2B3E6C1F ,
  0x1F83D9ABFB41BD6B , 0x5BE0CD19137E2179 ,

\ =====================================================================
\  State & working memory
\ =====================================================================

CREATE _S512-H   8 CELLS ALLOT        \ current hash H[0..7]
CREATE _S512-W  80 CELLS ALLOT        \ message schedule W[0..79]
CREATE _S512-BUF 128 ALLOT            \ input buffer (one block)
VARIABLE _S512-BLEN                   \ bytes in buffer (0..127)
VARIABLE _S512-MLEN                   \ total message length in bytes

\ Working variables for compression round loop
VARIABLE _S512-A   VARIABLE _S512-B
VARIABLE _S512-C   VARIABLE _S512-D
VARIABLE _S512-E   VARIABLE _S512-F
VARIABLE _S512-G   VARIABLE _S512-HH

\ Temporaries for MAJ
VARIABLE _S512-TMP1   VARIABLE _S512-TMP2

\ Variables for SHA512-ADD loop
VARIABLE _S512-SRC   VARIABLE _S512-REM

\ Variable for SHA512->HEX destination
VARIABLE _S512-HDST

\ Variable for SHA512-END output address
VARIABLE _S512-DST

\ =====================================================================
\  64-bit right rotation
\ =====================================================================

: _S512-ROTR  ( x n -- x>>>n )
    >R DUP R@ RSHIFT SWAP 64 R> - LSHIFT OR ;

\ =====================================================================
\  SHA-512 functions
\ =====================================================================

: _S512-CH  ( e f g -- result )
    >R OVER AND SWAP INVERT R> AND XOR ;

: _S512-MAJ  ( a b c -- result )
    _S512-TMP2 ! _S512-TMP1 !
    DUP _S512-TMP1 @ AND
    OVER _S512-TMP2 @ AND XOR
    SWAP DROP
    _S512-TMP1 @ _S512-TMP2 @ AND XOR ;

: _S512-BSIG0  ( a -- result )
    DUP 28 _S512-ROTR OVER 34 _S512-ROTR XOR SWAP 39 _S512-ROTR XOR ;

: _S512-BSIG1  ( e -- result )
    DUP 14 _S512-ROTR OVER 18 _S512-ROTR XOR SWAP 41 _S512-ROTR XOR ;

: _S512-SSIG0  ( x -- result )
    DUP 1 _S512-ROTR OVER 8 _S512-ROTR XOR SWAP 7 RSHIFT XOR ;

: _S512-SSIG1  ( x -- result )
    DUP 19 _S512-ROTR OVER 61 _S512-ROTR XOR SWAP 6 RSHIFT XOR ;

\ =====================================================================
\  Big-endian 64-bit byte I/O
\ =====================================================================

: _S512-LOAD64BE  ( addr -- u64 )
    DUP     C@ 56 LSHIFT >R
    DUP 1 + C@ 48 LSHIFT R> OR >R
    DUP 2 + C@ 40 LSHIFT R> OR >R
    DUP 3 + C@ 32 LSHIFT R> OR >R
    DUP 4 + C@ 24 LSHIFT R> OR >R
    DUP 5 + C@ 16 LSHIFT R> OR >R
    DUP 6 + C@  8 LSHIFT R> OR >R
        7 + C@             R> OR ;

: _S512-STORE64BE  ( u64 addr -- )
    OVER 56 RSHIFT          OVER     C!
    OVER 48 RSHIFT 0xFF AND OVER 1 + C!
    OVER 40 RSHIFT 0xFF AND OVER 2 + C!
    OVER 32 RSHIFT 0xFF AND OVER 3 + C!
    OVER 24 RSHIFT 0xFF AND OVER 4 + C!
    OVER 16 RSHIFT 0xFF AND OVER 5 + C!
    OVER  8 RSHIFT 0xFF AND OVER 6 + C!
    SWAP           0xFF AND SWAP 7 + C! ;

\ =====================================================================
\  Compression — process one 128-byte block
\ =====================================================================

: _S512-COMPRESS  ( addr -- )
    \ W[0..15] from block
    16 0 DO
        DUP I 8 * + _S512-LOAD64BE
        _S512-W I CELLS + !
    LOOP DROP

    \ W[16..79] schedule expansion
    80 16 DO
        _S512-W I 2 -  CELLS + @ _S512-SSIG1
        _S512-W I 7 -  CELLS + @ +
        _S512-W I 15 - CELLS + @ _S512-SSIG0 +
        _S512-W I 16 - CELLS + @ +
        _S512-W I CELLS + !
    LOOP

    \ Init a..h from H
    _S512-H            @ _S512-A  !
    _S512-H 1 CELLS + @ _S512-B  !
    _S512-H 2 CELLS + @ _S512-C  !
    _S512-H 3 CELLS + @ _S512-D  !
    _S512-H 4 CELLS + @ _S512-E  !
    _S512-H 5 CELLS + @ _S512-F  !
    _S512-H 6 CELLS + @ _S512-G  !
    _S512-H 7 CELLS + @ _S512-HH !

    \ 80 rounds
    80 0 DO
        \ T1 = h + Sig1(e) + Ch(e,f,g) + K[i] + W[i]
        _S512-HH @
        _S512-E @ _S512-BSIG1 +
        _S512-E @ _S512-F @ _S512-G @ _S512-CH +
        _S512-K I CELLS + @ +
        _S512-W I CELLS + @ +
        \ T2 = Sig0(a) + Maj(a,b,c)
        _S512-A @ _S512-BSIG0
        _S512-A @ _S512-B @ _S512-C @ _S512-MAJ +
        \ Stack: T1 T2
        _S512-G  @ _S512-HH !
        _S512-F  @ _S512-G  !
        _S512-E  @ _S512-F  !
        OVER _S512-D @ + _S512-E !
        _S512-C  @ _S512-D  !
        _S512-B  @ _S512-C  !
        _S512-A  @ _S512-B  !
        + _S512-A !
    LOOP

    \ Add back to H
    _S512-A  @ _S512-H            @ + _S512-H            !
    _S512-B  @ _S512-H 1 CELLS + @ + _S512-H 1 CELLS + !
    _S512-C  @ _S512-H 2 CELLS + @ + _S512-H 2 CELLS + !
    _S512-D  @ _S512-H 3 CELLS + @ + _S512-H 3 CELLS + !
    _S512-E  @ _S512-H 4 CELLS + @ + _S512-H 4 CELLS + !
    _S512-F  @ _S512-H 5 CELLS + @ + _S512-H 5 CELLS + !
    _S512-G  @ _S512-H 6 CELLS + @ + _S512-H 6 CELLS + !
    _S512-HH @ _S512-H 7 CELLS + @ + _S512-H 7 CELLS + ! ;

\ =====================================================================
\  Streaming API
\ =====================================================================

: SHA512-BEGIN  ( -- )
    8 0 DO
        _S512-IV I CELLS + @
        _S512-H  I CELLS + !
    LOOP
    0 _S512-BLEN !
    0 _S512-MLEN ! ;

: SHA512-ADD  ( addr len -- )
    DUP _S512-MLEN +!
    _S512-REM ! _S512-SRC !
    BEGIN _S512-REM @ 0 > WHILE
        _S512-BLOCK _S512-BLEN @ -
        _S512-REM @ MIN
        DUP >R
        _S512-SRC @ _S512-BUF _S512-BLEN @ + R@ CMOVE
        R@ _S512-BLEN +!
        R@ _S512-SRC +!
        R> NEGATE _S512-REM +!
        _S512-BLEN @ _S512-BLOCK = IF
            _S512-BUF _S512-COMPRESS
            0 _S512-BLEN !
        THEN
    REPEAT ;

: SHA512-END  ( dst -- )
    _S512-DST !
    \ Bit length = MLEN * 8
    _S512-MLEN @ 3 LSHIFT              ( bits_lo )
    _S512-MLEN @ 61 RSHIFT             ( bits_lo bits_hi )

    \ Append 0x80
    0x80 _S512-BUF _S512-BLEN @ + C!
    1 _S512-BLEN +!

    \ If buffer past byte 112, pad+compress, then restart
    _S512-BLEN @ 112 > IF
        BEGIN _S512-BLEN @ _S512-BLOCK < WHILE
            0 _S512-BUF _S512-BLEN @ + C!
            1 _S512-BLEN +!
        REPEAT
        _S512-BUF _S512-COMPRESS
        0 _S512-BLEN !
    THEN

    \ Zero-pad to byte 112
    BEGIN _S512-BLEN @ 112 < WHILE
        0 _S512-BUF _S512-BLEN @ + C!
        1 _S512-BLEN +!
    REPEAT

    \ Append 128-bit length BE: bits_hi at 112, bits_lo at 120
    ( bits_lo bits_hi )
    _S512-BUF 112 + _S512-STORE64BE
    _S512-BUF 120 + _S512-STORE64BE

    \ Compress final block
    _S512-BUF _S512-COMPRESS

    \ Write 64-byte hash BE
    8 0 DO
        _S512-H I CELLS + @
        _S512-DST @ I 8 * + _S512-STORE64BE
    LOOP ;

\ =====================================================================
\  One-shot API
\ =====================================================================

: SHA512-HASH  ( src len dst -- )
    >R SHA512-BEGIN SHA512-ADD R> SHA512-END ;

\ =====================================================================
\  Hex conversion & display
\ =====================================================================

CREATE _S512-HEX
  48 C, 49 C, 50 C, 51 C, 52 C, 53 C, 54 C, 55 C,
  56 C, 57 C, 97 C, 98 C, 99 C, 100 C, 101 C, 102 C,

: _S512-NIB>C  ( n -- c )  0x0F AND _S512-HEX + C@ ;

: SHA512->HEX  ( src dst -- n )
    _S512-HDST !
    64 0 DO
        DUP I + C@
        DUP 4 RSHIFT _S512-NIB>C _S512-HDST @ I 2* + C!
        0x0F AND _S512-NIB>C _S512-HDST @ I 2* 1+ + C!
    LOOP
    DROP SHA512-HEX-LEN ;

: SHA512-.  ( addr -- )
    64 0 DO
        DUP I + C@
        DUP 4 RSHIFT _S512-NIB>C EMIT
        0x0F AND _S512-NIB>C EMIT
    LOOP DROP ;

\ =====================================================================
\  Constant-time comparison
\ =====================================================================

: SHA512-COMPARE  ( a b -- flag )
    0
    64 0 DO
        >R OVER I + C@ OVER I + C@ XOR R> OR
    LOOP
    >R 2DROP R>
    0= IF TRUE ELSE FALSE THEN ;
