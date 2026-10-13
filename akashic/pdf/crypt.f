\ =================================================================
\  crypt.f  —  PDF's standard security handler, with the empty password
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: PDF-CRYPT- (public), _PDCR- (private)
\  Depends on: pdf/lexer.f, math/md5.f, math/rc4.f, math/aes.f,
\              math/sha256.f, math/sha512.f, utils/memory-source.f
\
\  Public API:
\   PDF-S-LOCKED        ( -- 6 )        a status: a password is needed
\   PDF-CRYPT-SIZE      ( -- bytes )    a file's encryption's record
\   PDF-CRYPT-SETUP     ( ea eu ida idu msrc crypt -- status )
\   PDF-CRYPT-STREAMS?  ( crypt -- flag )   streams to decrypt
\   PDF-CRYPT-STRINGS?  ( crypt -- flag )   strings to decrypt
\   PDF-CRYPT-LOCKED?   ( crypt -- flag )
\   PDF-CRYPT-STRING    ( a u num gen crypt -- a' u' ok? )   in place
\   PDF-CRYPT-STREAM    ( a u num gen crypt -- a' u' ok? )   in place
\   PDF-CRYPT-READER-SIZE  ( -- bytes )   a stream decrypted in pieces
\   PDF-CRYPT-READER-START ( num gen crypt reader -- block )
\   PDF-CRYPT-READER-RUN   ( a u last? reader -- a' u' ok? )
\
\  PDF-CRYPT-SETUP reads an /Encrypt dictionary EA EU with the first
\  string of the trailer's /ID, IDA IDU, and opens the file with the empty
\  user password, as the standard security handler has it, PDF 32000-1
\  section 7.6.3 and ISO 32000-2 section 7.6.4.  Revisions 2 to 4 take
\  the key from algorithm 2 and check it against /U by algorithm 4 or 5.
\  Revisions 2 and 3 encrypt with RC4 keys of 40 to 128 bits, revision 4
\  through its /StmF and /StrF crypt filters: RC4 (/V2), AES-128 with a
\  key for each object (/AESV2), or nothing (/None, /Identity).
\  Revisions 5 and 6 check the password's hash against /U and decrypt
\  the 256-bit key from /UE (algorithm 2.A), with revision 6's hash of
\  algorithm 2.B; they encrypt with AES-256 (/AESV3).  A file whose empty
\  password is not its user password, or encrypted by a handler other
\  than the standard one, is locked: PDF-CRYPT-SETUP says PDF-S-LOCKED.
\  Algorithm 2.B borrows its working bytes from MSRC.
\
\  PDF-CRYPT-STRING and PDF-CRYPT-STREAM decrypt a string's or a stream's
\  bytes, in place, by their method with object NUM GEN's key, giving the
\  span of the plain bytes: AES data starts with its 16-byte IV and ends
\  padded to a whole block.  OK? is false when the AES engine refuses.
\  A PDF-CRYPT-READER-SIZE record, eight-byte aligned, decrypts a
\  stream's bytes a piece at a time.  READER-START begins object NUM GEN's
\  stream and says the pieces' BLOCK: 1, or 16 for AES.  READER-RUN
\  decrypts the next piece in place, a whole number of blocks but for the
\  last, giving the plain bytes' span: an AES stream's first 16 bytes
\  are its IV, not data, and its last piece's padding is taken off.
\  The caller leaves alone what is not encrypted: the /Encrypt dictionary,
\  cross-reference streams, and the objects inside object streams, whose
\  stream was decrypted whole.  One call runs at a time.
\ =================================================================

PROVIDED akashic-pdf-crypt

REQUIRE lexer.f
REQUIRE ../math/md5.f
REQUIRE ../math/rc4.f
REQUIRE ../math/aes.f
REQUIRE ../math/sha256.f
REQUIRE ../math/sha512.f
REQUIRE ../utils/memory-source.f

6 CONSTANT PDF-S-LOCKED

\ The methods: nothing, RC4, AES-128 with each object's key, AES-256
\ with the file's key.
0 CONSTANT _PDCR-M-NONE
1 CONSTANT _PDCR-M-RC4
2 CONSTANT _PDCR-M-AESV2
3 CONSTANT _PDCR-M-AESV3

\ The record: the methods streams and strings take, whether the file is
\ locked, the key's length and the key.
: _PDCR.STM     ( c -- a )        ;
: _PDCR.STR     ( c -- a )    8 + ;
: _PDCR.LOCKED  ( c -- a )   16 + ;
: _PDCR.N       ( c -- a )   24 + ;
: _PDCR.KEY     ( c -- a )   32 + ;
64 CONSTANT PDF-CRYPT-SIZE

: PDF-CRYPT-STREAMS?  ( crypt -- flag )  _PDCR.STM @ 0<> ;
: PDF-CRYPT-STRINGS?  ( crypt -- flag )  _PDCR.STR @ 0<> ;
: PDF-CRYPT-LOCKED?   ( crypt -- flag )  _PDCR.LOCKED @ 0<> ;

\ A reader: its method, whether its IV is taken, its key's length, its
\ key, the chain, and RC4's key stream.
: _PDCRR.METHOD  ( r -- a )        ;
: _PDCRR.IV?     ( r -- a )    8 + ;
: _PDCRR.N       ( r -- a )   16 + ;
: _PDCRR.KEY     ( r -- a )   24 + ;
: _PDCRR.CHAIN   ( r -- a )   56 + ;
: _PDCRR.RC4     ( r -- a )   72 + ;
72 RC4-SIZE + CONSTANT PDF-CRYPT-READER-SIZE

\ The password padding (algorithm 2, step a), all of it for the empty one.
CREATE _PDCR-PAD
    0x28 C, 0xBF C, 0x4E C, 0x5E C, 0x4E C, 0x75 C, 0x8A C, 0x41 C,
    0x64 C, 0x00 C, 0x4E C, 0x56 C, 0xFF C, 0xFA C, 0x01 C, 0x08 C,
    0x2E C, 0x2E C, 0x00 C, 0xB6 C, 0xD0 C, 0x68 C, 0x3E C, 0x80 C,
    0x2F C, 0x0C C, 0xA9 C, 0xFE C, 0x64 C, 0x53 C, 0x69 C, 0x7A C,

\ What algorithm 1 adds to an AES-128 object's key.
CREATE _PDCR-SALT  0x73 C, 0x41 C, 0x6C C, 0x54 C,

CREATE _PDCR-MD5-S MD5-SIZE 7 + ALLOT
: _PDCR-MD5  ( -- md5 )  _PDCR-MD5-S 7 + -8 AND ;
CREATE _PDCR-RC4-S RC4-SIZE 7 + ALLOT
: _PDCR-RC4  ( -- rc4 )  _PDCR-RC4-S 7 + -8 AND ;
CREATE _PDCR-CBC-D-S AES-CBC-DESCRIPTOR-SIZE 7 + ALLOT
: _PDCR-CBC-D  ( -- d )  _PDCR-CBC-D-S 7 + -8 AND ;
CREATE _PDCR-CBC-W-S AES-CBC-WORKSPACE-SIZE 7 + ALLOT
: _PDCR-CBC-W  ( -- w )  _PDCR-CBC-W-S 7 + -8 AND ;
CREATE _PDCR-READER-S PDF-CRYPT-READER-SIZE 7 + ALLOT
: _PDCR-READER  ( -- r )  _PDCR-READER-S 7 + -8 AND ;
CREATE _PDCR-DIGEST 16 ALLOT
CREATE _PDCR-O 32 ALLOT       \ /O
CREATE _PDCR-U 48 ALLOT       \ /U
CREATE _PDCR-UE 32 ALLOT      \ /UE
CREATE _PDCR-T 32 ALLOT       \ scratch
CREATE _PDCR-K 25 ALLOT       \ a key with an object's number and the salt
CREATE _PDCR-H 64 ALLOT       \ a password's hash, algorithm 2.B's K
CREATE _PDCR-IV 16 ALLOT

VARIABLE _PDCR-C      \ the record
VARIABLE _PDCR-EA   VARIABLE _PDCR-EU     \ the /Encrypt dictionary
VARIABLE _PDCR-R      \ its revision
VARIABLE _PDCR-V      \ its version
VARIABLE _PDCR-MSRC   \ the memory source
VARIABLE _PDCR-RD     \ the reader running
VARIABLE _PDCR-LAST   \ whether its piece is the last

: _PDCR-INT@  ( key-a key-u -- n | -1 )
    _PDCR-EA @ _PDCR-EU @ PDF-DICT@ PDF-T-INT = IF PDF-INT ELSE 2DROP -1 THEN ;

\ A string entry's bytes, at most MAX of them, into DST: how many.
: _PDCR-STRING@  ( key-a key-u dst max -- u )
    2>R _PDCR-EA @ _PDCR-EU @ PDF-DICT@ 2R@ PDF-STRING 2R> NIP MIN ;

\ U bytes at A, a whole number of blocks, through AES in CBC, in place,
\ with the KU bytes of KEY and the chain at IV, which becomes the last
\ ciphertext block.
: _PDCR-CBC  ( a u key ku iv decrypt? -- ok? )
    >R
    _PDCR-CBC-D AES-CBC-DESCRIPTOR-SIZE 0 FILL
    _PDCR-CBC-D AES-CBC-D.IV !
    _PDCR-CBC-D AES-CBC-D.KEY-U !
    _PDCR-CBC-D AES-CBC-D.KEY !
    _PDCR-CBC-D AES-CBC-D.DATA-U !
    DUP _PDCR-CBC-D AES-CBC-D.INPUT !
    _PDCR-CBC-D AES-CBC-D.OUTPUT !
    _PDCR-CBC-D _PDCR-CBC-W
    R> IF AES-CBC-DECRYPT ELSE AES-CBC-ENCRYPT THEN
    AES-S-OK = ;

\ =====================================================================
\  Revisions 2 to 4
\ =====================================================================

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

\ Open the file with the empty password by algorithms 2 and 4 or 5.
: _PDCR-V4  ( ida idu -- status )
    \ the key's length: 5 bytes for revision 2, else /Length bits, 128 by
    \ default with crypt filters and 40 without
    _PDCR-R @ 2 = IF 5 ELSE
        S" Length" _PDCR-INT@ DUP 0< IF DROP _PDCR-V @ 4 = IF 128 ELSE 40 THEN THEN
        3 RSHIFT
    THEN
    5 MAX 16 MIN _PDCR-C @ _PDCR.N !
    _PDCR-O 32 0 FILL  _PDCR-U 48 0 FILL
    S" O" _PDCR-O 32 _PDCR-STRING@ 32 <> IF 2DROP PDF-S-LOCKED EXIT THEN
    S" U" _PDCR-U 32 _PDCR-STRING@ 16 < IF 2DROP PDF-S-LOCKED EXIT THEN
    2DUP _PDCR-KEY
    _PDCR-USER? 0= IF PDF-S-LOCKED EXIT THEN
    0 _PDCR-C @ _PDCR.LOCKED !  PDF-S-OK ;

\ =====================================================================
\  Revisions 5 and 6
\ =====================================================================

\ Algorithm 2.B's E is K 64 times, K at most SHA-512's 64 bytes: the
\ empty password and no user data add nothing to it.
64 64 * CONSTANT _PDCR-E-SIZE

VARIABLE _PDCR-HU     \ K's length
VARIABLE _PDCR-E      \ E's bytes, from the memory source
VARIABLE _PDCR-EN     \ E's length
VARIABLE _PDCR-ROUNDS

\ One round of algorithm 2.B: E is K 64 times, encrypted in place by
\ AES-128 in CBC with K's first 16 bytes the key and its next 16 the IV;
\ then K is E's SHA-256, SHA-384 or SHA-512 as E's first 16 bytes, a
\ big-endian number, are 0, 1 or 2 modulo 3.  Each byte is itself modulo
\ 3 as 256 is 1, so the bytes' sum is.
: _PDCR-ROUND  ( -- ok? )
    _PDCR-HU @ 64 * _PDCR-EN !
    64 0 DO _PDCR-H _PDCR-E @ I _PDCR-HU @ * + _PDCR-HU @ MOVE LOOP
    _PDCR-H 16 + _PDCR-IV 16 MOVE
    _PDCR-E @ _PDCR-EN @ _PDCR-H 16 _PDCR-IV 0 _PDCR-CBC 0= IF 0 EXIT THEN
    0  16 0 DO _PDCR-E @ I + C@ + LOOP  3 MOD
    DUP 0= IF DROP _PDCR-E @ _PDCR-EN @ _PDCR-H SHA256-HASH 32 ELSE
        1 = IF _PDCR-E @ _PDCR-EN @ _PDCR-H SHA384-HASH 48
        ELSE _PDCR-E @ _PDCR-EN @ _PDCR-H SHA512-HASH 64 THEN
    THEN
    _PDCR-HU !  0= ;

: _PDCR-E-FREE  ( -- )
    _PDCR-E @ _PDCR-E-SIZE 0 FILL
    _PDCR-E @ _PDCR-E-SIZE _PDCR-MSRC @ MSRC-FREE ;

\ Algorithm 2.B from K at _PDCR-H: at least 64 rounds, and then until
\ E's last byte is at most the rounds run less 32.  K's first 32 bytes
\ are the hash.
: _PDCR-2B  ( -- ok? )
    _PDCR-E-SIZE _PDCR-MSRC @ MSRC-ALLOC DUP _PDCR-E ! 0= IF 0 EXIT THEN
    0 _PDCR-ROUNDS !
    BEGIN
        _PDCR-ROUND 0= IF _PDCR-E-FREE 0 EXIT THEN
        1 _PDCR-ROUNDS +!
        _PDCR-ROUNDS @ 64 < 0=
        _PDCR-E @ _PDCR-EN @ + 1- C@ _PDCR-ROUNDS @ 32 - > 0= AND
    UNTIL
    _PDCR-E-FREE -1 ;

\ The empty password's hash with the 8-byte SALT and no user data, into
\ _PDCR-H: SHA-256 in revision 5, algorithm 2.B from it in revision 6.
: _PDCR-PW-HASH  ( salt -- ok? )
    8 _PDCR-H SHA256-HASH IF 0 EXIT THEN
    32 _PDCR-HU !
    _PDCR-R @ 6 = IF _PDCR-2B ELSE -1 THEN ;

\ Open the file with the empty password by algorithm 2.A: its hash with
\ /U's validation salt must be /U's first 32 bytes, and its hash with the
\ key salt decrypts /UE, AES-256 in CBC from an IV of zeros, to the key.
: _PDCR-V5  ( -- status )
    _PDCR-U 48 0 FILL  _PDCR-UE 32 0 FILL
    S" U" _PDCR-U 48 _PDCR-STRING@ 48 < IF PDF-S-LOCKED EXIT THEN
    S" UE" _PDCR-UE 32 _PDCR-STRING@ 32 < IF PDF-S-LOCKED EXIT THEN
    _PDCR-U 32 + _PDCR-PW-HASH 0= IF PDF-S-LOCKED EXIT THEN
    _PDCR-H 32 _PDCR-U 32 COMPARE IF PDF-S-LOCKED EXIT THEN
    _PDCR-U 40 + _PDCR-PW-HASH 0= IF PDF-S-LOCKED EXIT THEN
    _PDCR-IV 16 0 FILL
    _PDCR-UE 32 _PDCR-H 32 _PDCR-IV -1 _PDCR-CBC 0= IF PDF-S-LOCKED EXIT THEN
    _PDCR-UE _PDCR-C @ _PDCR.KEY 32 MOVE  32 _PDCR-C @ _PDCR.N !
    _PDCR-H 64 0 FILL  _PDCR-UE 32 0 FILL
    0 _PDCR-C @ _PDCR.LOCKED !  PDF-S-OK ;

\ =====================================================================
\  Setting up
\ =====================================================================

\ What a crypt filter named at VA VU does: its method, or -1 one this
\ handler cannot read.
: _PDCR-FILTER  ( va vu type -- method )
    PDF-T-NAME <> IF 2DROP _PDCR-M-NONE EXIT THEN
    2DUP S" Identity" PDF-NAME= IF 2DROP _PDCR-M-NONE EXIT THEN
    1- SWAP 1+ SWAP
    S" CF" _PDCR-EA @ _PDCR-EU @ PDF-DICT@ PDF-T-DICT <> IF 2DROP 2DROP -1 EXIT THEN
    PDF-DICT@ PDF-T-DICT <> IF 2DROP -1 EXIT THEN
    S" CFM" 2SWAP PDF-DICT@ PDF-T-NAME <> IF 2DROP -1 EXIT THEN
    2DUP S" V2" PDF-NAME= IF 2DROP _PDCR-M-RC4 EXIT THEN
    2DUP S" AESV2" PDF-NAME= IF 2DROP _PDCR-M-AESV2 EXIT THEN
    2DUP S" AESV3" PDF-NAME= IF 2DROP _PDCR-M-AESV3 EXIT THEN
    S" None" PDF-NAME= IF _PDCR-M-NONE ELSE -1 THEN ;

\ Whether METHOD is one the version's key serves: AES-256 alone takes
\ the 256-bit key of version 5.
: _PDCR-METHOD-OK?  ( method -- flag )
    DUP 0< IF DROP 0 EXIT THEN
    DUP _PDCR-M-NONE = IF DROP -1 EXIT THEN
    _PDCR-M-AESV3 = _PDCR-V @ 5 = = ;

\ PDF-CRYPT-SETUP ( ea eu ida idu msrc crypt -- status )
\   Open the file the /Encrypt dictionary EA EU describes with the empty
\   user password.
: PDF-CRYPT-SETUP  ( ea eu ida idu msrc crypt -- status )
    DUP _PDCR-C !  PDF-CRYPT-SIZE 0 FILL  _PDCR-MSRC !
    2SWAP _PDCR-EU ! _PDCR-EA !
    -1 _PDCR-C @ _PDCR.LOCKED !
    S" Filter" _PDCR-EA @ _PDCR-EU @ PDF-DICT@ PDF-T-NAME = IF
        S" Standard" PDF-NAME= 0= IF 2DROP PDF-S-LOCKED EXIT THEN
    ELSE 2DROP 2DROP PDF-S-LOCKED EXIT THEN
    S" R" _PDCR-INT@ _PDCR-R !  S" V" _PDCR-INT@ _PDCR-V !
    \ versions 1, 2 and 4 with revisions 2 to 4, version 5 with 5 and 6
    _PDCR-V @ 5 = IF _PDCR-R @ 5 7 WITHIN ELSE
        _PDCR-R @ 2 5 WITHIN  _PDCR-V @ 1 5 WITHIN AND  _PDCR-V @ 3 <> AND
    THEN 0= IF 2DROP PDF-S-LOCKED EXIT THEN
    \ the methods: RC4 throughout before version 4, its crypt filters after
    _PDCR-V @ 4 < IF
        _PDCR-M-RC4 _PDCR-C @ _PDCR.STM !  _PDCR-M-RC4 _PDCR-C @ _PDCR.STR !
    ELSE
        S" StmF" _PDCR-EA @ _PDCR-EU @ PDF-DICT@ _PDCR-FILTER _PDCR-C @ _PDCR.STM !
        S" StrF" _PDCR-EA @ _PDCR-EU @ PDF-DICT@ _PDCR-FILTER _PDCR-C @ _PDCR.STR !
        _PDCR-C @ _PDCR.STM @ _PDCR-METHOD-OK?
        _PDCR-C @ _PDCR.STR @ _PDCR-METHOD-OK? AND 0= IF 2DROP PDF-S-LOCKED EXIT THEN
    THEN
    _PDCR-V @ 5 = IF 2DROP _PDCR-V5 EXIT THEN
    _PDCR-V4 ;

\ =====================================================================
\  Decrypting
\ =====================================================================

\ Object NUM GEN's key for METHOD: algorithm 1's MD5 of the file's key,
\ the number's three bytes and the generation's two, with the salt for
\ AES-128, at most 16 bytes of it; for AES-256, the file's key itself.
: _PDCR-OBJECT-KEY  ( num gen method -- key u )
    DUP _PDCR-M-AESV3 = IF DROP 2DROP _PDCR-C @ _PDCR.KEY 32 EXIT THEN
    >R
    _PDCR-C @ DUP _PDCR.KEY _PDCR-K ROT _PDCR.N @ MOVE
    _PDCR-K _PDCR-C @ _PDCR.N @ + >R
    SWAP DUP R@ C!  DUP 8 RSHIFT R@ 1+ C!  16 RSHIFT R@ 2 + C!
    DUP R@ 3 + C!  8 RSHIFT R> 4 + C!
    _PDCR-C @ _PDCR.N @ 5 +
    R@ _PDCR-M-AESV2 = IF _PDCR-SALT _PDCR-K 2 PICK + 4 MOVE 4 + THEN
    _PDCR-K SWAP _PDCR-DIGEST MD5
    _PDCR-DIGEST R> _PDCR-M-AESV2 = IF 16 ELSE _PDCR-C @ _PDCR.N @ 5 + 16 MIN THEN ;

\ Begin decrypting object NUM GEN's data by METHOD in READER: its block.
: _PDCR-START  ( num gen method reader -- block )
    >R
    R@ PDF-CRYPT-READER-SIZE 0 FILL
    DUP R@ _PDCRR.METHOD !
    DUP _PDCR-M-NONE = IF DROP 2DROP R> DROP 1 EXIT THEN
    _PDCR-OBJECT-KEY
    R@ _PDCRR.METHOD @ _PDCR-M-RC4 = IF R> _PDCRR.RC4 RC4-INIT 1 EXIT THEN
    DUP R@ _PDCRR.N !  R> _PDCRR.KEY SWAP MOVE  16 ;

\ PDF-CRYPT-READER-START ( num gen crypt reader -- block )
\   Begin decrypting object NUM GEN's stream in READER.
: PDF-CRYPT-READER-START  ( num gen crypt reader -- block )
    >R DUP _PDCR-C ! _PDCR.STM @ R> _PDCR-START ;

\ The plain bytes of the last blocks without their padding: the last byte
\ says how many bytes pad, 1 to 16, and each of them says so too.
\ Padding that does not is taken to be data.
: _PDCR-UNPAD  ( a u -- a u' )
    DUP 0= IF EXIT THEN
    2DUP + 1- C@ DUP 1 17 WITHIN 0= IF DROP EXIT THEN
    2DUP < IF DROP EXIT THEN
    2 PICK 2 PICK + OVER -
    OVER 0 DO DUP I + C@ 2 PICK <> IF 2DROP UNLOOP EXIT THEN LOOP
    DROP - ;

\ PDF-CRYPT-READER-RUN ( a u last? reader -- a' u' ok? )
\   Decrypt the next piece of U bytes at A in place: the span of its plain
\   bytes.  An AES piece is cut to whole blocks; one too short for the IV
\   still to be taken has none.
: PDF-CRYPT-READER-RUN  ( a u last? reader -- a' u' ok? )
    _PDCR-RD ! _PDCR-LAST !
    _PDCR-RD @ _PDCRR.METHOD @
    DUP _PDCR-M-NONE = IF DROP -1 EXIT THEN
    _PDCR-M-RC4 = IF 2DUP _PDCR-RD @ _PDCRR.RC4 RC4-XOR -1 EXIT THEN
    _PDCR-RD @ _PDCRR.IV? @ 0= IF
        DUP 16 < IF DROP 0 -1 EXIT THEN
        OVER _PDCR-RD @ _PDCRR.CHAIN 16 MOVE
        -1 _PDCR-RD @ _PDCRR.IV? !
        16 - SWAP 16 + SWAP
    THEN
    -16 AND  DUP 0= IF -1 EXIT THEN
    2DUP _PDCR-RD @ DUP _PDCRR.KEY SWAP DUP _PDCRR.N @ SWAP _PDCRR.CHAIN
    -1 _PDCR-CBC 0= IF 0 EXIT THEN
    _PDCR-LAST @ IF _PDCR-UNPAD THEN
    -1 ;

\ A string's or a stream's bytes decrypted whole by METHOD.
: _PDCR-DATA  ( a u num gen method -- a' u' ok? )
    _PDCR-READER _PDCR-START DROP
    -1 _PDCR-READER PDF-CRYPT-READER-RUN ;

\ PDF-CRYPT-STRING ( a u num gen crypt -- a' u' ok? )
\   Decrypt object NUM GEN's string of U bytes at A, in place.
: PDF-CRYPT-STRING  ( a u num gen crypt -- a' u' ok? )
    DUP _PDCR-C ! _PDCR.STR @ _PDCR-DATA ;

\ PDF-CRYPT-STREAM ( a u num gen crypt -- a' u' ok? )
\   Decrypt object NUM GEN's stream data of U bytes at A, in place.
: PDF-CRYPT-STREAM  ( a u num gen crypt -- a' u' ok? )
    DUP _PDCR-C ! _PDCR.STM @ _PDCR-DATA ;
