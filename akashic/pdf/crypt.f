\ =================================================================
\  crypt.f  —  PDF's standard security handler, with the empty password
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: PDF-CRYPT- (public), _PDCR- (private)
\  Depends on: pdf/lexer.f, math/md5.f, math/rc4.f
\
\  Public API:
\   PDF-S-LOCKED       ( -- 6 )        a status: a password is needed
\   PDF-CRYPT-SIZE     ( -- bytes )    a file's encryption's record
\   PDF-CRYPT-SETUP    ( ea eu ida idu crypt -- status )
\   PDF-CRYPT-STREAMS? ( crypt -- flag )   streams to decrypt
\   PDF-CRYPT-STRINGS? ( crypt -- flag )   strings to decrypt
\   PDF-CRYPT-LOCKED?  ( crypt -- flag )
\   PDF-CRYPT-DATA     ( a u num gen crypt -- )   decrypt, in place
\
\  PDF-CRYPT-SETUP reads an /Encrypt dictionary EA EU with the first
\  string of the trailer's /ID, IDA IDU, and opens the file with the empty
\  user password, as PDF 32000-1 section 7.6.3 has the standard security
\  handler do: the key from algorithm 2, checked against /U by algorithm
\  4 or 5.  It reads revisions 2 to 4 with RC4 keys of 40 to 128 bits,
\  through /StmF and /StrF crypt filters in revision 4, where /Identity
\  leaves data as it is.  A file whose empty password is not its user
\  password, or that is encrypted with AES or by a handler other than
\  the standard one, is locked: PDF-CRYPT-SETUP says PDF-S-LOCKED.
\
\  PDF-CRYPT-DATA decrypts a string's or a stream's bytes, in place, with
\  object NUM GEN's key (algorithm 1).  The caller leaves alone what is
\  not encrypted: the /Encrypt dictionary, cross-reference streams, and
\  the objects inside object streams, whose stream was decrypted whole.
\  One call runs at a time.
\ =================================================================

PROVIDED akashic-pdf-crypt

REQUIRE lexer.f
REQUIRE ../math/md5.f
REQUIRE ../math/rc4.f

6 CONSTANT PDF-S-LOCKED

\ The record: what streams and strings take (0 nothing, 1 RC4), whether
\ the file is locked, the key's length and the key.
: _PDCR.STM     ( c -- a )        ;
: _PDCR.STR     ( c -- a )    8 + ;
: _PDCR.LOCKED  ( c -- a )   16 + ;
: _PDCR.N       ( c -- a )   24 + ;
: _PDCR.KEY     ( c -- a )   32 + ;
48 CONSTANT PDF-CRYPT-SIZE

: PDF-CRYPT-STREAMS?  ( crypt -- flag )  _PDCR.STM @ 0<> ;
: PDF-CRYPT-STRINGS?  ( crypt -- flag )  _PDCR.STR @ 0<> ;
: PDF-CRYPT-LOCKED?   ( crypt -- flag )  _PDCR.LOCKED @ 0<> ;

\ The password padding (algorithm 2, step a), all of it for the empty one.
CREATE _PDCR-PAD
    0x28 C, 0xBF C, 0x4E C, 0x5E C, 0x4E C, 0x75 C, 0x8A C, 0x41 C,
    0x64 C, 0x00 C, 0x4E C, 0x56 C, 0xFF C, 0xFA C, 0x01 C, 0x08 C,
    0x2E C, 0x2E C, 0x00 C, 0xB6 C, 0xD0 C, 0x68 C, 0x3E C, 0x80 C,
    0x2F C, 0x0C C, 0xA9 C, 0xFE C, 0x64 C, 0x53 C, 0x69 C, 0x7A C,

CREATE _PDCR-MD5-S MD5-SIZE 7 + ALLOT
: _PDCR-MD5  ( -- md5 )  _PDCR-MD5-S 7 + -8 AND ;
CREATE _PDCR-RC4-S RC4-SIZE 7 + ALLOT
: _PDCR-RC4  ( -- rc4 )  _PDCR-RC4-S 7 + -8 AND ;
CREATE _PDCR-DIGEST 16 ALLOT
CREATE _PDCR-O 32 ALLOT       \ /O
CREATE _PDCR-U 32 ALLOT       \ /U
CREATE _PDCR-T 32 ALLOT       \ scratch
CREATE _PDCR-K 21 ALLOT       \ a key with an object's number

VARIABLE _PDCR-C      \ the record
VARIABLE _PDCR-EA   VARIABLE _PDCR-EU     \ the /Encrypt dictionary
VARIABLE _PDCR-R      \ its revision

: _PDCR-INT@  ( key-a key-u -- n | -1 )
    _PDCR-EA @ _PDCR-EU @ PDF-DICT@ PDF-T-INT = IF PDF-INT ELSE 2DROP -1 THEN ;

\ A string entry's bytes, at most 32 of them, into DST: how many.
: _PDCR-STRING@  ( key-a key-u dst -- u )
    >R _PDCR-EA @ _PDCR-EU @ PDF-DICT@ R> 32 PDF-STRING 32 MIN ;

\ The encryption key: algorithm 2, for revisions 2 to 4.
: _PDCR-KEY  ( ida idu -- )
    _PDCR-MD5 MD5-INIT
    _PDCR-PAD 32 _PDCR-MD5 MD5-UPDATE
    _PDCR-O 32 _PDCR-MD5 MD5-UPDATE
    S" P" _PDCR-INT@ _PDCR-T L!  _PDCR-T 4 _PDCR-MD5 MD5-UPDATE
    _PDCR-MD5 MD5-UPDATE
    _PDCR-R @ 4 < 0= IF
        S" EncryptMetadata" _PDCR-EA @ _PDCR-EU @ PDF-DICT@ PDF-T-KEYWORD = IF
            S" false" COMPARE 0= IF
                -1 _PDCR-T L!  _PDCR-T 4 _PDCR-MD5 MD5-UPDATE
            THEN
        ELSE 2DROP THEN
    THEN
    _PDCR-DIGEST _PDCR-MD5 MD5-FINAL
    _PDCR-R @ 3 < 0= IF
        50 0 DO _PDCR-DIGEST _PDCR-C @ _PDCR.N @ _PDCR-DIGEST MD5 LOOP
    THEN
    _PDCR-DIGEST _PDCR-C @ _PDCR.KEY 16 MOVE ;

\ Whether the key opens the file: algorithm 4 for revision 2, 5 for
\ revisions 3 and 4.
: _PDCR-USER?  ( ida idu -- flag )
    _PDCR-C @ DUP _PDCR.KEY SWAP _PDCR.N @ _PDCR-RC4 RC4-INIT
    _PDCR-R @ 2 = IF
        2DROP _PDCR-PAD _PDCR-T 32 MOVE  _PDCR-T 32 _PDCR-RC4 RC4-XOR
        _PDCR-T 32 _PDCR-U 32 COMPARE 0= EXIT
    THEN
    _PDCR-MD5 MD5-INIT  _PDCR-PAD 32 _PDCR-MD5 MD5-UPDATE  _PDCR-MD5 MD5-UPDATE
    _PDCR-T _PDCR-MD5 MD5-FINAL
    _PDCR-T 16 _PDCR-RC4 RC4-XOR
    20 1 DO
        _PDCR-C @ _PDCR.N @ 0 DO
            _PDCR-C @ _PDCR.KEY I + C@ J XOR _PDCR-K I + C!
        LOOP
        _PDCR-K _PDCR-C @ _PDCR.N @ _PDCR-RC4 RC4-INIT
        _PDCR-T 16 _PDCR-RC4 RC4-XOR
    LOOP
    _PDCR-T 16 _PDCR-U 16 COMPARE 0= ;

\ What a crypt filter named at VA VU does in revision 4: 0 nothing, 1
\ RC4, or -1 a method this handler cannot read.
: _PDCR-FILTER  ( va vu type -- method )
    PDF-T-NAME <> IF 2DROP 0 EXIT THEN
    2DUP S" Identity" PDF-NAME= IF 2DROP 0 EXIT THEN
    1- SWAP 1+ SWAP
    S" CF" _PDCR-EA @ _PDCR-EU @ PDF-DICT@ PDF-T-DICT <> IF 2DROP 2DROP -1 EXIT THEN
    PDF-DICT@ PDF-T-DICT <> IF 2DROP -1 EXIT THEN
    S" CFM" 2SWAP PDF-DICT@ PDF-T-NAME <> IF 2DROP -1 EXIT THEN
    2DUP S" V2" PDF-NAME= IF 2DROP 1 EXIT THEN
    S" None" PDF-NAME= IF 0 ELSE -1 THEN ;

\ PDF-CRYPT-SETUP ( ea eu ida idu crypt -- status )
\   Open the file the /Encrypt dictionary EA EU describes with the empty
\   user password.
: PDF-CRYPT-SETUP  ( ea eu ida idu crypt -- status )
    DUP _PDCR-C !  PDF-CRYPT-SIZE 0 FILL
    2SWAP _PDCR-EU ! _PDCR-EA !
    -1 _PDCR-C @ _PDCR.LOCKED !
    S" Filter" _PDCR-EA @ _PDCR-EU @ PDF-DICT@ PDF-T-NAME = IF
        S" Standard" PDF-NAME= 0= IF 2DROP PDF-S-LOCKED EXIT THEN
    ELSE 2DROP 2DROP PDF-S-LOCKED EXIT THEN
    S" R" _PDCR-INT@ DUP _PDCR-R !  2 5 WITHIN 0= IF 2DROP PDF-S-LOCKED EXIT THEN
    S" V" _PDCR-INT@ DUP 1 5 WITHIN 0= SWAP 3 = OR IF 2DROP PDF-S-LOCKED EXIT THEN
    \ the methods: RC4 throughout before revision 4, its crypt filters in 4
    S" V" _PDCR-INT@ 4 = IF
        S" StmF" _PDCR-EA @ _PDCR-EU @ PDF-DICT@ _PDCR-FILTER _PDCR-C @ _PDCR.STM !
        S" StrF" _PDCR-EA @ _PDCR-EU @ PDF-DICT@ _PDCR-FILTER _PDCR-C @ _PDCR.STR !
        _PDCR-C @ _PDCR.STM @ 0< _PDCR-C @ _PDCR.STR @ 0< OR IF 2DROP PDF-S-LOCKED EXIT THEN
    ELSE
        1 _PDCR-C @ _PDCR.STM !  1 _PDCR-C @ _PDCR.STR !
    THEN
    \ the key's length: 5 bytes for revision 2, else /Length bits
    _PDCR-R @ 2 = IF 5 ELSE S" Length" _PDCR-INT@ DUP 0< IF DROP 40 THEN 3 RSHIFT THEN
    5 MAX 16 MIN _PDCR-C @ _PDCR.N !
    _PDCR-O 32 0 FILL  _PDCR-U 32 0 FILL
    S" O" _PDCR-O _PDCR-STRING@ 32 <> IF 2DROP PDF-S-LOCKED EXIT THEN
    S" U" _PDCR-U _PDCR-STRING@ 16 < IF 2DROP PDF-S-LOCKED EXIT THEN
    2DUP _PDCR-KEY
    _PDCR-USER? 0= IF PDF-S-LOCKED EXIT THEN
    0 _PDCR-C @ _PDCR.LOCKED !  PDF-S-OK ;

\ PDF-CRYPT-DATA ( a u num gen crypt -- )
\   Decrypt U bytes at A, in place, with object NUM GEN's key.
: PDF-CRYPT-DATA  ( a u num gen crypt -- )
    _PDCR-C !
    _PDCR-C @ DUP _PDCR.KEY _PDCR-K ROT _PDCR.N @ MOVE
    _PDCR-K _PDCR-C @ _PDCR.N @ + >R
    SWAP DUP R@ C!  DUP 8 RSHIFT R@ 1+ C!  16 RSHIFT R@ 2 + C!
    DUP R@ 3 + C!  8 RSHIFT R> 4 + C!
    _PDCR-K _PDCR-C @ _PDCR.N @ 5 + _PDCR-DIGEST MD5
    _PDCR-DIGEST _PDCR-C @ _PDCR.N @ 5 + 16 MIN _PDCR-RC4 RC4-INIT
    _PDCR-RC4 RC4-XOR ;
