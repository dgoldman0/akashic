\ =================================================================
\  rc4.f  —  RC4, the stream cipher
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: RC4- (public), _RC4- (private)
\  Depends on: nothing
\
\  Public API:
\   RC4-SIZE  ( -- bytes )           a key stream's record
\   RC4-INIT  ( key-a key-u rc4 -- ) start the stream of a key
\   RC4-XOR   ( a u rc4 -- )         xor the stream's next U bytes into A
\
\  RC4 is broken as a cipher.  It is here because PDF's standard
\  security handler encrypts with it.  The key is 1 to 256 bytes; a key
\  of no bytes starts the stream of the permutation alone.  RC4-XOR
\  encrypts and decrypts alike, in place, and a stream continues across
\  calls.  The caller owns the record; the module keeps no state.
\ =================================================================

PROVIDED akashic-rc4

\ The record: the two indices, then the permutation of 256 bytes.
: _RC4.I  ( r -- a )      ;
: _RC4.J  ( r -- a )   8 + ;
: _RC4.S  ( r -- a )  16 + ;
272 CONSTANT RC4-SIZE

\ RC4-INIT ( key-a key-u rc4 -- )   Start the key stream of KEY-U bytes.
: RC4-INIT  ( key-a key-u rc4 -- )
    0 OVER _RC4.I !  0 OVER _RC4.J !  _RC4.S          ( ka ku s )
    256 0 DO I OVER I + C! LOOP
    0 256 0 DO                                        ( ka ku s j )
        OVER I + C@ +
        2 PICK IF 3 PICK I 4 PICK MOD + C@ + THEN
        255 AND
        2DUP + C@  2 PICK I + C@                      ( ka ku s j sj si )
        3 PICK 3 PICK + C!  2 PICK I + C!             ( ka ku s j )
    LOOP DROP DROP 2DROP ;

\ RC4-XOR ( a u rc4 -- )   Xor the key stream's next U bytes into A.
: RC4-XOR  ( a u rc4 -- )
    >R  R@ _RC4.I @  R@ _RC4.J @  R@ _RC4.S           ( a u i j s )
    4 ROLL 4 ROLL OVER + SWAP ?DO                     ( i j s )
        ROT 1+ 255 AND                                ( j s i )
        2DUP + C@ 3 ROLL + 255 AND                    ( s i j )
        2 PICK 2 PICK + C@  3 PICK 2 PICK + C@        ( s i j si sj )
        DUP 5 PICK 5 PICK + C!  OVER 5 PICK 4 PICK + C!
        + 255 AND 3 PICK + C@  I C@ XOR I C!          ( s i j )
        ROT                                           ( i j s )
    LOOP
    DROP R@ _RC4.J !  R> _RC4.I ! ;
