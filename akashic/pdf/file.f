\ =================================================================
\  file.f  —  a PDF file's objects, read as they are asked for
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: PDF- (public), _PDFF- (private)
\  Depends on: pdf/lexer.f, pdf/filter.f, pdf/crypt.f, media/source.f
\
\  Public API:
\   PDF-FILE-SIZE     ( -- bytes )                 a file's record
\   PDF-OPEN          ( source msrc file -- status )
\   PDF-CLOSE         ( file -- )
\   PDF-TRAILER@      ( key-a key-u file -- va vu type )
\   PDF-OBJECT-COUNT  ( file -- n )
\   PDF-GET           ( num file -- obj status )
\   PDF-OBJ-FREE      ( obj file -- )
\   PDF-OBJ-VALUE     ( obj -- va vu type )
\   PDF-OBJ-NUM       ( obj -- num gen )
\   PDF-OBJ-STREAM?   ( obj -- flag )
\   PDF-STREAM        ( obj buf file -- status )
\   PDF-STREAM-IMAGE  ( obj buf file -- coding status )   as far as a
\                                                         picture's coding
\   PDF-RAW-SIZE      ( -- bytes )                 a stream read in pieces
\   PDF-RAW-START     ( obj file raw -- status )
\   PDF-RAW-READ      ( a u raw -- n status )
\   PDF-RAW-SPAN      ( raw -- offset u stored? )
\   PDF-RESOLVE       ( va vu type file -- obj va' vu' type' status )
\   PDF-REPAIRED?     ( file -- flag )
\   PDF-FILE-MSRC     ( file -- msrc )             its memory source
\   PDF-FILE-SOURCE   ( file -- source )           its media source
\   PDF-FILE-LOCKED?  ( file -- flag )             a password is needed
\
\  PDF-OPEN reads the cross-reference sections from the last, following
\  each one's /Prev and a hybrid file's /XRefStm, so a newer section's
\  entry for an object stands over an older one's.  It keeps the
\  newest trailer, or a section's dictionary when it is a cross-reference
\  stream.  When a section cannot be read, or no trailer names a /Root,
\  it reads the file again by scanning it for its objects, the objects of
\  its object streams and its last trailer, or else its catalog; so does
\  PDF-GET, once, when an object is not where its entry says.
\
\  PDF-GET reads one object, from the file or from an object stream, into
\  a record of its own that the caller gives back with PDF-OBJ-FREE.  The
\  object's value is a span of that record, valid until it is given back.
\  The file holds each object stream it decodes, with an index of where
\  its objects lie, until it is closed, so objects that lie in several
\  streams, read in turn, decode each stream once; when memory refuses a
\  stream, it gives back the others and decodes it again.
\  A stream object's data is read only by PDF-STREAM, which decodes it
\  through its filters.  PDF-RESOLVE follows a reference: it gives back an
\  object to free, or 0 for a value that was no reference.
\
\  PDF-STREAM-IMAGE decodes a picture's stream as far as its own coding
\  (pdf/filter.f's PDF-DECODE-IMAGE).  A PDF-RAW-SIZE record reads a
\  stream's bytes as the file stores them, before its filters, a piece at
\  a time: PDF-RAW-START begins, and PDF-RAW-READ gives the next bytes,
\  decrypted, none at the end.  PDF-RAW-SPAN says where the bytes left lie
\  in the file's media source, and whether they are as stored, not
\  encrypted, so a reader may take them from the source itself.
\
\  An encrypted file is opened with the empty user password through
\  pdf/crypt.f.  Its objects' strings are decrypted as they are read, so
\  a value holds each string as a hex string of its plain bytes, and its
\  streams' data before their filters; the /Encrypt dictionary, cross-
\  reference streams and the objects in object streams are left as they
\  are.  A file that needs a password, or that AES encrypts, still opens,
\  but PDF-FILE-LOCKED? says so and its encrypted streams are
\  PDF-S-LOCKED.
\
\  Every buffer comes from the caller's memory source.  The file borrows
\  its media source.  One call runs at a time.
\ =================================================================

PROVIDED akashic-pdf-file

REQUIRE lexer.f
REQUIRE filter.f
REQUIRE crypt.f
REQUIRE ../media/source.f

5 CONSTANT PDF-S-MISSING      \ an object that is free or has no entry

\ =====================================================================
\  The file's record
\ =====================================================================
\   +0   source              +8   memory source       +16  file size
\   +24  entries             +32  object numbers      +40  entries' bytes
\   +48  trailer bytes       +56  their room          +64  trailer length
\   +72  the object streams held decoded, the one used last first, or 0
\   +80  work bytes (a buffer, 24)                    +104 repaired?
\   +112 open?              +120 its encryption (PDF-CRYPT-SIZE, 48)
\   +168 the /Encrypt dictionary's object, or 0       +176 a value with its
\   strings decrypted (a buffer, 24)    +200 a string's bytes (a buffer, 24)
\   +224 encrypted?

: _PDFF.SRC       ( f -- a )        ;
: _PDFF.MSRC      ( f -- a )    8 + ;
: _PDFF.SIZE      ( f -- a )   16 + ;
: _PDFF.ENTRIES   ( f -- a )   24 + ;
: _PDFF.COUNT     ( f -- a )   32 + ;
: _PDFF.EBYTES    ( f -- a )   40 + ;
: _PDFF.TRAILER   ( f -- a )   48 + ;
: _PDFF.TCAP      ( f -- a )   56 + ;
: _PDFF.TLEN      ( f -- a )   64 + ;
: _PDFF.HELD      ( f -- a )   72 + ;
: _PDFF.WORK      ( f -- a )   80 + ;
: _PDFF.REPAIRED  ( f -- a )  104 + ;
: _PDFF.OPEN      ( f -- a )  112 + ;
: _PDFF.CRYPT     ( f -- c )  120 + ;
: _PDFF.ENCNUM    ( f -- a )  168 + ;
: _PDFF.CBUF      ( f -- a )  176 + ;
: _PDFF.SBUF      ( f -- a )  200 + ;
: _PDFF.ENCRYPTED ( f -- a )  224 + ;
232 CONSTANT PDF-FILE-SIZE

\ An entry: its type (0 free, 1 in the file, 2 in an object stream,
\ 255 none yet), its generation or index, and its offset or stream.
16 CONSTANT _PDFF-ENTRY
255 CONSTANT _PDFF-UNSET

: _PDFF-ENTRY@  ( num file -- e )  _PDFF.ENTRIES @ SWAP _PDFF-ENTRY * + ;

\ =====================================================================
\  An object's record
\ =====================================================================
\   +0  value's offset in the record   +8  value's length
\   +16 value's type                   +24 object number
\   +32 generation                     +40 stream data offset, or -1
\   +48 stream data length             +56 bytes in all
\   +64 the value's bytes

: _PDFO.VOFF   ( o -- a )      ;
: _PDFO.VLEN   ( o -- a )   8 + ;
: _PDFO.VTYPE  ( o -- a )  16 + ;
: _PDFO.NUM    ( o -- a )  24 + ;
: _PDFO.GEN    ( o -- a )  32 + ;
: _PDFO.SOFF   ( o -- a )  40 + ;
: _PDFO.SLEN   ( o -- a )  48 + ;
: _PDFO.BYTES  ( o -- a )  56 + ;
64 CONSTANT _PDFO-HEAD

: PDF-OBJ-VALUE  ( obj -- va vu type )
    DUP _PDFO.VOFF @ OVER + OVER _PDFO.VLEN @ ROT _PDFO.VTYPE @ ;
: PDF-OBJ-NUM  ( obj -- num gen )  DUP _PDFO.NUM @ SWAP _PDFO.GEN @ ;
: PDF-OBJ-STREAM?  ( obj -- flag )  _PDFO.SOFF @ 0< 0= ;

: PDF-OBJ-FREE  ( obj file -- )
    OVER 0= IF 2DROP EXIT THEN
    _PDFF.MSRC @ >R DUP _PDFO.BYTES @ R> MSRC-FREE ;

VARIABLE _PDFN-A  VARIABLE _PDFN-U

\ A record holding a copy of the U value bytes at A.
: _PDFF-NEW-OBJ  ( a u type num gen file -- obj | 0 )
    >R >R >R >R  _PDFN-U ! _PDFN-A !
    _PDFN-U @ _PDFO-HEAD + DUP R> R> R> R> _PDFF.MSRC @   ( n n type num gen msrc )
    5 PICK SWAP MSRC-ALLOC                                ( n n type num gen obj )
    DUP 0= IF >R 2DROP 2DROP DROP R> EXIT THEN
    TUCK _PDFO.GEN !  TUCK _PDFO.NUM !  TUCK _PDFO.VTYPE !  TUCK _PDFO.BYTES !
    NIP
    _PDFO-HEAD OVER _PDFO.VOFF !  -1 OVER _PDFO.SOFF !  0 OVER _PDFO.SLEN !
    _PDFN-U @ OVER _PDFO.VLEN !
    _PDFN-A @ OVER _PDFO-HEAD + _PDFN-U @ MOVE ;

\ =====================================================================
\  Reading
\ =====================================================================

\ Read up to LEN bytes at OFFSET into the work buffer: fewer at the end.
\ The span is valid until the next read.
: _PDFF-READ  ( offset len file -- a u status )
    >R OVER R@ _PDFF.SIZE @ SWAP - 0 MAX MIN               ( offset len' )
    DUP 0= IF 2DROP R> _PDFF.WORK PDF-BUF.A @ 0 PDF-S-OK EXIT THEN
    DUP R@ _PDFF.WORK R@ _PDFF.MSRC @ PDF-BUF-GROW 0= IF
        2DROP R> DROP 0 0 PDF-S-MEMORY EXIT
    THEN
    R@ _PDFF.WORK PDF-BUF.A @ -ROT SWAP                     ( a len offset )
    >R 2DUP R> R> _PDFF.SRC @ MEDSRC-READ? IF
        2DROP 0 0 PDF-S-READ EXIT
    THEN
    PDF-S-OK ;

\ =====================================================================
\  Entries
\ =====================================================================

\ Make room for entries up to NUM, every new one unset.
: _PDFF-ROOM  ( num file -- ok? )
    2DUP _PDFF.COUNT @ < IF 2DROP -1 EXIT THEN
    >R 1+ R@ _PDFF.COUNT @ 2* MAX                           ( count' )
    DUP _PDFF-ENTRY * R@ _PDFF.MSRC @ MSRC-ALLOC             ( count' new )
    DUP 0= IF 2DROP R> DROP 0 EXIT THEN
    OVER _PDFF-ENTRY * OVER SWAP _PDFF-UNSET FILL
    R@ _PDFF.ENTRIES @ ?DUP IF
        OVER R@ _PDFF.COUNT @ _PDFF-ENTRY * MOVE
        R@ _PDFF.ENTRIES @ R@ _PDFF.EBYTES @ R@ _PDFF.MSRC @ MSRC-FREE
    THEN
    R@ _PDFF.ENTRIES !  DUP R@ _PDFF.COUNT !  _PDFF-ENTRY * R> _PDFF.EBYTES !
    -1 ;

\ Set an entry unless a newer section has: TYPE, then its offset or
\ stream number, and its generation or index.
: _PDFF-SET  ( num type field2 field3 file -- ok? )
    >R 3 PICK R@ _PDFF-ROOM 0= IF 2DROP 2DROP R> DROP 0 EXIT THEN
    3 PICK R> _PDFF-ENTRY@                                  ( num type f2 f3 e )
    DUP C@ _PDFF-UNSET <> IF 2DROP 2DROP DROP -1 EXIT THEN
    TUCK 4 + L!  TUCK 8 + !  C!  DROP -1 ;

\ =====================================================================
\  The trailer
\ =====================================================================

\ Keep a copy of the dictionary at DA as the trailer, unless one with a
\ /Root is kept already.
: _PDFF-KEEP-TRAILER  ( da du file -- ok? )
    >R R@ _PDFF.TLEN @ IF
        S" Root" R@ _PDFF.TRAILER @ R@ _PDFF.TLEN @ PDF-DICT@ NIP NIP
        PDF-T-END <> IF 2DROP R> DROP -1 EXIT THEN
        R@ _PDFF.TRAILER @ R@ _PDFF.TCAP @ R@ _PDFF.MSRC @ MSRC-FREE
        0 R@ _PDFF.TLEN !  0 R@ _PDFF.TRAILER !
    THEN
    DUP R@ _PDFF.MSRC @ MSRC-ALLOC DUP 0= IF DROP 2DROP R> DROP 0 EXIT THEN
    DUP R@ _PDFF.TRAILER !  OVER R@ _PDFF.TCAP !  OVER R@ _PDFF.TLEN !
    SWAP MOVE R> DROP -1 ;

\ PDF-TRAILER@ ( key-a key-u file -- va vu type )   A trailer entry.
: PDF-TRAILER@  ( key-a key-u file -- va vu type )
    DUP _PDFF.TLEN @ 0= IF DROP 2DROP 0 0 PDF-T-END EXIT THEN
    DUP _PDFF.TRAILER @ SWAP _PDFF.TLEN @ PDF-DICT@ ;

\ PDF-OBJECT-COUNT ( file -- n )   Object numbers from 0 the table spans.
: PDF-OBJECT-COUNT  ( file -- n )  _PDFF.COUNT @ ;

\ =====================================================================
\  Parsing at a position
\ =====================================================================

VARIABLE _PDFF-F      \ the file
VARIABLE _PDFF-POS    \ where the span left to parse starts in the file
VARIABLE _PDFF-A      \ the span left to parse, in the work buffer
VARIABLE _PDFF-U

\ Read LEN bytes at the position as the span to parse.
: _PDFF-LOAD  ( len -- status )
    _PDFF-POS @ SWAP _PDFF-F @ _PDFF-READ >R _PDFF-U ! _PDFF-A ! R> ;

\ The span left is now A U: move the position past what was parsed.
: _PDFF-USED  ( a u -- )
    OVER _PDFF-A @ - _PDFF-POS +!  _PDFF-U ! _PDFF-A ! ;

\ The next token of the span, moving past it.
: _PDFF-TOKEN  ( -- ta tu type )
    _PDFF-A @ _PDFF-U @ PDF-TOKEN >R 2>R _PDFF-USED 2R> R> ;

\ The value at the position, read in growing pieces until it is whole or
\ the file ends.  Its span is valid until the next read.
: _PDFF-VALUE  ( -- va vu type status )
    256 BEGIN
        DUP _PDFF-LOAD ?DUP IF NIP >R 0 0 PDF-T-BAD R> EXIT THEN
        _PDFF-A @ _PDFF-U @ PDF-VALUE                      ( n a' u' va vu type )
        DUP PDF-T-BAD = 6 PICK _PDFF-U @ = AND
        _PDFF-POS @ 7 PICK + _PDFF-F @ _PDFF.SIZE @ < AND
    WHILE
        2DROP DROP 2DROP 4 *
    REPEAT
    >R 2>R _PDFF-USED 2R> R> >R ROT DROP R> PDF-S-OK ;

\ The next token at the position, a few bytes read.
: _PDFF-NEXT  ( -- ta tu type status )
    64 _PDFF-LOAD ?DUP IF >R 0 0 PDF-T-END R> EXIT THEN
    _PDFF-TOKEN PDF-S-OK ;

: _PDFF-KEYWORD?  ( ta tu type name-a name-u -- flag )
    2>R PDF-T-KEYWORD = IF 2R> COMPARE 0= ELSE 2DROP 2R> 2DROP 0 THEN ;

\ =====================================================================
\  An object in the file
\ =====================================================================

\ Where "endstream" starts at or after FROM, within the file, or -1.
: _PDFF-ENDSTREAM  ( from file -- offset | -1 )
    >R BEGIN
        DUP R@ _PDFF.SIZE @ < WHILE
        DUP 4096 R@ _PDFF-READ IF 2DROP DROP R> DROP -1 EXIT THEN   ( from a u )
        DUP 9 < IF 2DROP DROP R> DROP -1 EXIT THEN
        DUP 8 - 0 ?DO
            OVER I + 9 S" endstream" COMPARE 0= IF
                2DROP I + UNLOOP R> DROP EXIT
            THEN
        LOOP
        NIP 8 - +
    REPEAT DROP R> DROP -1 ;

\ Leave out the data's last byte when it is C.
: _PDFF-TRIM  ( obj len c file -- obj len' )
    >R >R DUP 0= IF R> R> 2DROP EXIT THEN
    OVER _PDFO.SOFF @ OVER + 1- 1 R> R> SWAP >R _PDFF-READ IF
        2DROP R> DROP EXIT
    THEN
    DROP C@ R> = IF 1- THEN ;

\ The stream data's length: /Length when "endstream" follows it, after
\ an optional line end; otherwise up to the next "endstream".
: _PDFF-STREAM-LENGTH  ( length obj file -- )
    >R
    OVER 0< 0= IF
        OVER OVER _PDFO.SOFF @ + 16 R@ _PDFF-READ IF 2DROP 2DROP R> DROP EXIT THEN
        BEGIN DUP IF OVER C@ DUP 13 = SWAP 10 = OR ELSE 0 THEN WHILE 1 _PDL-ADV REPEAT
        DUP 9 < 0= IF DROP 9 S" endstream" COMPARE 0= ELSE 2DROP 0 THEN
        IF _PDFO.SLEN ! R> DROP EXIT THEN
    THEN
    NIP DUP _PDFO.SOFF @ R@ _PDFF-ENDSTREAM                  ( obj end )
    DUP 0< IF DROP R@ _PDFF.SIZE @ THEN
    OVER _PDFO.SOFF @ -                                     ( obj len )
    \ Leave out the line end before "endstream".
    10 R@ _PDFF-TRIM 13 R@ _PDFF-TRIM
    SWAP _PDFO.SLEN !  R> DROP ;

VARIABLE _PDFF-NUM  VARIABLE _PDFF-GEN
VARIABLE _PDFF-GET-XT   \ PDF-GET, which an object's /Length may need

\ =====================================================================
\  Strings decrypted
\ =====================================================================

VARIABLE _PDFF-CA   VARIABLE _PDFF-CE   VARIABLE _PDFF-SN
VARIABLE _PDFF-TA   VARIABLE _PDFF-TU   VARIABLE _PDFF-TT
CREATE _PDFF-HEXD  48 C, 49 C, 50 C, 51 C, 52 C, 53 C, 54 C, 55 C,
                   56 C, 57 C, 65 C, 66 C, 67 C, 68 C, 69 C, 70 C,

: _PDFF-CBUF+  ( a u -- ok? )  _PDFF-F @ _PDFF.CBUF _PDFF-F @ _PDFF.MSRC @ PDF-BUF-APPEND ;

\ A string token's bytes, decrypted with the object's key, onto the
\ value being written as a hex string.
: _PDFF-HEX+  ( ta tu type -- ok? )
    >R 2DUP R@ 0 0 PDF-STRING _PDFF-SN !
    _PDFF-SN @ _PDFF-F @ _PDFF.SBUF _PDFF-F @ _PDFF.MSRC @ PDF-BUF-GROW 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    R> _PDFF-F @ _PDFF.SBUF PDF-BUF.A @ _PDFF-SN @ PDF-STRING DROP
    _PDFF-F @ _PDFF.SBUF PDF-BUF.A @ _PDFF-SN @ _PDFF-NUM @ _PDFF-GEN @
    _PDFF-F @ _PDFF.CRYPT PDF-CRYPT-DATA
    _PDFF-F @ _PDFF.CBUF DUP PDF-BUF.U @ _PDFF-SN @ 2* 2 + + SWAP
    _PDFF-F @ _PDFF.MSRC @ PDF-BUF-GROW 0= IF 0 EXIT THEN
    _PDFF-F @ _PDFF.CBUF DUP PDF-BUF.A @ SWAP PDF-BUF.U @ +
    60 OVER C! 1+
    _PDFF-SN @ 0 ?DO
        _PDFF-F @ _PDFF.SBUF PDF-BUF.A @ I + C@
        DUP 4 RSHIFT _PDFF-HEXD + C@ 2 PICK C!
        15 AND _PDFF-HEXD + C@ OVER 1+ C!  2 +
    LOOP
    62 SWAP C!
    _PDFF-SN @ 2* 2 + _PDFF-F @ _PDFF.CBUF PDF-BUF.U +!  -1 ;

\ An object's value as the file holds it, or, when the file's strings
\ are encrypted, rewritten with each string decrypted.
: _PDFF-DECRYPTED  ( va vu type -- va' vu' type status )
    _PDFF-F @ _PDFF.CRYPT PDF-CRYPT-STRINGS? 0= IF PDF-S-OK EXIT THEN
    _PDFF-F @ _PDFF.CRYPT PDF-CRYPT-LOCKED? IF PDF-S-OK EXIT THEN
    _PDFF-NUM @ _PDFF-F @ _PDFF.ENCNUM @ = IF PDF-S-OK EXIT THEN
    >R  0 _PDFF-F @ _PDFF.CBUF PDF-BUF.U !
    OVER _PDFF-CA !  2DUP + _PDFF-CE !
    BEGIN PDF-TOKEN DUP PDF-T-END <> WHILE
        DUP PDF-T-STRING = OVER PDF-T-HEX = OR IF
            _PDFF-TT ! _PDFF-TU ! _PDFF-TA !
            _PDFF-CA @ _PDFF-TA @ OVER - _PDFF-CBUF+
            _PDFF-TA @ _PDFF-TU @ _PDFF-TT @ _PDFF-HEX+ AND 0= IF
                2DROP R> DROP 0 0 0 PDF-S-MEMORY EXIT
            THEN
            _PDFF-TA @ _PDFF-TU @ + _PDFF-CA !
        ELSE DROP 2DROP THEN
    REPEAT DROP 2DROP 2DROP
    _PDFF-CA @ _PDFF-CE @ OVER - _PDFF-CBUF+ 0= IF R> DROP 0 0 0 PDF-S-MEMORY EXIT THEN
    _PDFF-F @ _PDFF.CBUF DUP PDF-BUF.A @ SWAP PDF-BUF.U @ R> PDF-S-OK ;

\ The object NUM, generation GEN, at OFFSET in the file; NUM -1 takes
\ whichever object is there.
: _PDFF-OBJECT-AT  ( offset num gen file -- obj status )
    _PDFF-F ! _PDFF-GEN ! _PDFF-NUM ! _PDFF-POS !
    _PDFF-NEXT ?DUP IF >R 2DROP DROP 0 R> EXIT THEN
    PDF-T-INT <> IF 2DROP 0 PDF-S-DAMAGED EXIT THEN
    PDF-INT _PDFF-NUM @ 0< IF _PDFF-NUM ! ELSE
        _PDFF-NUM @ <> IF 0 PDF-S-DAMAGED EXIT THEN
    THEN
    _PDFF-TOKEN PDF-T-INT <> IF 2DROP 0 PDF-S-DAMAGED EXIT THEN 2DROP
    _PDFF-TOKEN S" obj" _PDFF-KEYWORD? 0= IF 0 PDF-S-DAMAGED EXIT THEN
    _PDFF-VALUE ?DUP IF >R 2DROP DROP 0 R> EXIT THEN
    DUP PDF-T-BAD = IF DROP 2DROP 0 PDF-S-DAMAGED EXIT THEN
    _PDFF-DECRYPTED ?DUP IF >R 2DROP DROP 0 R> EXIT THEN
    _PDFF-NUM @ _PDFF-GEN @ _PDFF-F @ _PDFF-NEW-OBJ
    DUP 0= IF PDF-S-MEMORY EXIT THEN                         ( obj )
    _PDFF-NEXT IF 2DROP DROP PDF-S-OK EXIT THEN
    S" stream" _PDFF-KEYWORD? 0= IF PDF-S-OK EXIT THEN
    \ The data starts after the keyword's line end.
    _PDFF-POS @ 2 _PDFF-F @ _PDFF-READ IF 2DROP PDF-S-OK EXIT THEN
    OVER C@ 13 = IF 1 _PDL-ADV THEN
    DUP IF OVER C@ 10 = IF 1 _PDL-ADV THEN THEN
    DROP _PDFF-F @ _PDFF.WORK PDF-BUF.A @ - _PDFF-POS @ +
    OVER _PDFO.SOFF !
    \ /Length, followed to its object if it is a reference.
    DUP PDF-OBJ-VALUE DROP S" Length" 2SWAP PDF-DICT@        ( obj va vu type )
    DUP PDF-T-INT = IF DROP PDF-INT ELSE
        PDF-T-REF = IF
            PDF-REF@ DROP _PDFF-F @ >R R@ _PDFF-GET-XT @ EXECUTE   ( obj lobj status )
            IF DROP -1 ELSE
                DUP PDF-OBJ-VALUE PDF-T-INT = IF PDF-INT ELSE 2DROP -1 THEN
                SWAP R@ PDF-OBJ-FREE
            THEN R> DROP
        ELSE 2DROP -1 THEN
    THEN
    OVER _PDFF-F @ _PDFF-STREAM-LENGTH  PDF-S-OK ;

\ =====================================================================
\  Streams
\ =====================================================================

VARIABLE _PDFS-O  VARIABLE _PDFS-B  VARIABLE _PDFS-F
VARIABLE _PDFS-RAW  VARIABLE _PDFS-N

: _PDFS-FREE  ( -- )  _PDFS-RAW @ _PDFS-N @ _PDFS-F @ _PDFF.MSRC @ MSRC-FREE ;

\ Whether stream OBJ's stored bytes are encrypted: not in a file that is
\ not, nor for a cross-reference stream or the /Encrypt dictionary's.  A
\ locked file's encrypted streams cannot be read: PDF-S-LOCKED.
: _PDFS-CIPHER?  ( obj file -- flag status )
    DUP _PDFF.ENCRYPTED @ 0= IF 2DROP 0 PDF-S-OK EXIT THEN
    OVER PDF-OBJ-NUM DROP OVER _PDFF.ENCNUM @ = IF 2DROP 0 PDF-S-OK EXIT THEN
    S" Type" 3 PICK PDF-OBJ-VALUE DROP PDF-DICT@ PDF-T-NAME = IF
        S" XRef" PDF-NAME= IF 2DROP 0 PDF-S-OK EXIT THEN
    ELSE 2DROP THEN
    NIP _PDFF.CRYPT DUP PDF-CRYPT-LOCKED? IF DROP 0 PDF-S-LOCKED EXIT THEN
    PDF-CRYPT-STREAMS? PDF-S-OK ;

\ The stream's raw bytes decrypted, when they are encrypted.
: _PDFS-DECRYPT  ( -- status )
    _PDFS-O @ _PDFS-F @ _PDFS-CIPHER? ?DUP IF NIP EXIT THEN
    0= IF PDF-S-OK EXIT THEN
    _PDFS-RAW @ _PDFS-O @ _PDFO.SLEN @ _PDFS-O @ PDF-OBJ-NUM
    _PDFS-F @ _PDFF.CRYPT PDF-CRYPT-DATA  PDF-S-OK ;

VARIABLE _PDFS-PICTURE?   \ decoded as far as a picture's coding
VARIABLE _PDFS-CODING     \ that coding

\ A stream object's data, decoded into BUF.
: _PDFS-READ  ( obj buf file -- status )
    _PDFS-F ! _PDFS-B ! _PDFS-O !  PDF-IMG-SAMPLES _PDFS-CODING !
    _PDFS-O @ PDF-OBJ-STREAM? 0= IF PDF-S-DAMAGED EXIT THEN
    _PDFS-O @ _PDFO.SLEN @ 1 MAX DUP _PDFS-N !
    _PDFS-F @ _PDFF.MSRC @ MSRC-ALLOC DUP _PDFS-RAW ! 0= IF PDF-S-MEMORY EXIT THEN
    _PDFS-RAW @ _PDFS-O @ _PDFO.SLEN @ _PDFS-O @ _PDFO.SOFF @
    _PDFS-F @ _PDFF.SRC @ MEDSRC-READ? IF _PDFS-FREE PDF-S-READ EXIT THEN
    _PDFS-DECRYPT ?DUP IF _PDFS-FREE EXIT THEN
    _PDFS-RAW @ _PDFS-O @ _PDFO.SLEN @ _PDFS-O @ PDF-OBJ-VALUE DROP
    _PDFS-B @ _PDFS-F @ _PDFF.MSRC @
    _PDFS-PICTURE? @ IF PDF-DECODE-IMAGE SWAP _PDFS-CODING ! ELSE PDF-DECODE THEN
    _PDFS-FREE ;

\ PDF-STREAM ( obj buf file -- status )
\   A stream object's data, decoded through its filters into BUF.
: PDF-STREAM  ( obj buf file -- status )  0 _PDFS-PICTURE? ! _PDFS-READ ;

\ PDF-STREAM-IMAGE ( obj buf file -- coding status )
\   A picture's stream decoded into BUF as far as its own coding.
: PDF-STREAM-IMAGE  ( obj buf file -- coding status )
    -1 _PDFS-PICTURE? ! _PDFS-READ  0 _PDFS-PICTURE? !  _PDFS-CODING @ SWAP ;

\ =====================================================================
\  A stream's stored bytes, read in pieces
\ =====================================================================

\ The record: the file, where the bytes left start in its source and how
\ many there are, whether they are decrypted, and the key stream.
: _PDRW.FILE  ( r -- a )        ;
: _PDRW.POS   ( r -- a )    8 + ;
: _PDRW.LEFT  ( r -- a )   16 + ;
: _PDRW.RC4?  ( r -- a )   24 + ;
: _PDRW.RC4   ( r -- a )   32 + ;
32 RC4-SIZE + CONSTANT PDF-RAW-SIZE

\ PDF-RAW-START ( obj file raw -- status )
\   Read stream OBJ's stored bytes, decrypted, in pieces.  OBJ may be given
\   back once it starts.
: PDF-RAW-START  ( obj file raw -- status )
    DUP 32 0 FILL  >R
    DUP R@ _PDRW.FILE !
    OVER PDF-OBJ-STREAM? 0= IF 2DROP R> DROP PDF-S-DAMAGED EXIT THEN
    OVER _PDFO.SOFF @ R@ _PDRW.POS !  OVER _PDFO.SLEN @ R@ _PDRW.LEFT !
    2DUP _PDFS-CIPHER? ?DUP IF NIP NIP NIP R> DROP EXIT THEN
    IF
        -1 R@ _PDRW.RC4? !
        SWAP PDF-OBJ-NUM ROT _PDFF.CRYPT R> _PDRW.RC4 PDF-CRYPT-START
    ELSE 2DROP R> DROP THEN
    PDF-S-OK ;

\ PDF-RAW-READ ( a u raw -- n status )
\   The next of the stream's bytes, at most U, into A; N is 0 at the end.
: PDF-RAW-READ  ( a u raw -- n status )
    >R  R@ _PDRW.LEFT @ MIN
    DUP 0= IF NIP R> DROP PDF-S-OK EXIT THEN
    2DUP R@ _PDRW.POS @ R@ _PDRW.FILE @ _PDFF.SRC @ MEDSRC-READ? IF
        2DROP R> DROP 0 PDF-S-READ EXIT
    THEN
    R@ _PDRW.RC4? @ IF 2DUP R@ _PDRW.RC4 RC4-XOR THEN
    NIP DUP R@ _PDRW.POS +!  DUP NEGATE R> _PDRW.LEFT +!  PDF-S-OK ;

\ PDF-RAW-SPAN ( raw -- offset u stored? )
\   Where the bytes left lie in the file's media source, and whether they
\   are as it stores them.
: PDF-RAW-SPAN  ( raw -- offset u stored? )
    DUP _PDRW.POS @ OVER _PDRW.LEFT @ ROT _PDRW.RC4? @ 0= ;

\ =====================================================================
\  Objects in object streams
\ =====================================================================

\ An integer entry of a dictionary, or -1.
: _PDFF-INT@  ( key-a key-u da du -- n | -1 )
    PDF-DICT@ PDF-T-INT = IF PDF-INT ELSE 2DROP -1 THEN ;

\ An object stream held decoded: the next held, its object number (-1
\ while it is being decoded), its /N and /First, its decoded bytes, and
\ its table of numbers and offsets, read once into an index, a pair of
\ cells for each object.  The file holds each object stream it decodes,
\ for as long as it is open, so objects that lie in several streams, read
\ in turn, decode each stream once.  A stream held is never moved; the
\ one used last is first.
: _PDFH.NEXT   ( h -- a )        ;
: _PDFH.NUM    ( h -- a )    8 + ;
: _PDFH.N      ( h -- a )   16 + ;
: _PDFH.FIRST  ( h -- a )   24 + ;
: _PDFH.BYTES  ( h -- buf ) 32 + ;
: _PDFH.INDEX  ( h -- buf ) 56 + ;
80 CONSTANT _PDFF-HELD

CREATE _PDFF-PAIR 16 ALLOT
VARIABLE _PDFF-IH   VARIABLE _PDFF-IM   VARIABLE _PDFF-HP
\ True while an object stream is being decoded: the stream's own entries,
\ such as its /Length, lie in none (PDF 32000-1 7.5.7).
VARIABLE _PDFF-DECODING   0 _PDFF-DECODING !

\ Give back held stream H.
: _PDFF-HELD-FREE  ( h file -- )
    _PDFF.MSRC @ >R
    DUP _PDFH.BYTES R@ PDF-BUF-FREE  DUP _PDFH.INDEX R@ PDF-BUF-FREE
    _PDFF-HELD R> MSRC-FREE ;

\ Give back every object stream held.
: _PDFF-UNHOLD  ( file -- )
    DUP _PDFF.HELD @ 0 2 PICK _PDFF.HELD !          ( file h )
    BEGIN DUP WHILE
        DUP _PDFH.NEXT @ SWAP 2 PICK _PDFF-HELD-FREE
    REPEAT 2DROP ;

\ Held stream STM, made the first held; or 0.
: _PDFF-HELD@  ( stm file -- h | 0 )
    DUP _PDFF.HELD _PDFF-HP !  SWAP                  ( file stm )
    BEGIN _PDFF-HP @ @ DUP WHILE                     ( file stm h )
        DUP _PDFH.NUM @ 2 PICK = IF
            NIP DUP _PDFH.NEXT @ _PDFF-HP @ !            ( file h )
            OVER _PDFF.HELD @ OVER _PDFH.NEXT !
            DUP ROT _PDFF.HELD ! EXIT
        THEN
        _PDFH.NEXT _PDFF-HP !
    REPEAT NIP NIP ;

\ A new held stream, the first held, being decoded; or 0.
: _PDFF-NEW-HELD  ( file -- h | 0 )
    _PDFF-HELD OVER _PDFF.MSRC @ MSRC-ALLOC ?DUP 0= IF DROP 0 EXIT THEN
    DUP _PDFF-HELD 0 FILL  -1 OVER _PDFH.NUM !
    OVER _PDFF.HELD @ OVER _PDFH.NEXT !
    DUP ROT _PDFF.HELD ! ;

\ Held stream H's table of numbers and offsets, read into its index.
\ The table ends at a pair that is not two integers.
: _PDFF-INDEX  ( h file -- status )
    _PDFF.MSRC @ _PDFF-IM !  _PDFF-IH !
    _PDFF-IH @ _PDFH.BYTES PDF-BUF.A @
    _PDFF-IH @ _PDFH.FIRST @ _PDFF-IH @ _PDFH.BYTES PDF-BUF.U @ MIN
    _PDFF-IH @ _PDFH.N @ 0 MAX 0 ?DO
        PDF-TOKEN PDF-T-INT <> IF 2DROP LEAVE THEN PDF-INT _PDFF-PAIR !
        PDF-TOKEN PDF-T-INT <> IF 2DROP LEAVE THEN PDF-INT _PDFF-PAIR 8 + !
        _PDFF-PAIR 16 _PDFF-IH @ _PDFH.INDEX _PDFF-IM @ PDF-BUF-APPEND
        0= IF 2DROP UNLOOP PDF-S-MEMORY EXIT THEN
    LOOP 2DROP PDF-S-OK ;

\ Decode object stream STM into held stream H: its bytes, its /N and
\ /First, and its index.
: _PDFF-DECODE  ( stm h file -- status )
    >R SWAP R@ _PDFF-GET-XT @ EXECUTE                ( h obj status )
    ?DUP IF NIP NIP R> DROP EXIT THEN
    2DUP SWAP _PDFH.BYTES R@ PDF-STREAM               ( h obj status )
    ?DUP IF SWAP R> PDF-OBJ-FREE NIP EXIT THEN
    S" N" 2 PICK PDF-OBJ-VALUE DROP _PDFF-INT@ 2 PICK _PDFH.N !
    S" First" 2 PICK PDF-OBJ-VALUE DROP _PDFF-INT@ 2 PICK _PDFH.FIRST !
    R@ PDF-OBJ-FREE  R> _PDFF-INDEX ;

\ Hold object stream STM decoded, as a new held stream; given back when
\ it cannot be.
: _PDFF-HOLD  ( stm file -- h status )
    DUP _PDFF-NEW-HELD ?DUP 0= IF 2DROP 0 PDF-S-MEMORY EXIT THEN   ( stm file h )
    >R -1 _PDFF-DECODING !
    2DUP R@ SWAP _PDFF-DECODE                         ( stm file status )
    0 _PDFF-DECODING !
    ?DUP 0= IF DROP R@ _PDFH.NUM ! R> PDF-S-OK EXIT THEN
    SWAP R@ _PDFH.NEXT @ OVER _PDFF.HELD !  R> SWAP _PDFF-HELD-FREE
    NIP 0 SWAP ;

\ Object stream STM, held decoded: decoded now when it is not held, and
\ when memory refuses it, decoded again once the others are given back.
: _PDFF-OBJSTM  ( stm file -- h status )
    _PDFF-DECODING @ IF 2DROP 0 PDF-S-DAMAGED EXIT THEN
    2DUP _PDFF-HELD@ ?DUP IF NIP NIP PDF-S-OK EXIT THEN
    2DUP _PDFF-HOLD DUP PDF-S-MEMORY <> IF 2SWAP 2DROP EXIT THEN 2DROP
    DUP _PDFF-UNHOLD _PDFF-HOLD ;

\ Where object NUM starts in held stream H, after its /First: the index's
\ pair INDEX when it is NUM's, else the pair that is; or -1.
: _PDFF-WHERE  ( num index h -- offset | -1 )
    _PDFH.INDEX >R
    DUP 0< 0= OVER R@ PDF-BUF.U @ 16 / < AND IF
        16 * R@ PDF-BUF.A @ +  2DUP @ = IF NIP 8 + @ R> DROP EXIT THEN
    THEN DROP
    R@ PDF-BUF.A @ DUP R> PDF-BUF.U @ + SWAP                 ( num end a )
    BEGIN 2DUP > WHILE
        DUP @ 3 PICK = IF NIP NIP 8 + @ EXIT THEN
        16 +
    REPEAT 2DROP DROP -1 ;

VARIABLE _PDFF-SNUM  VARIABLE _PDFF-SOFF  VARIABLE _PDFF-SH

\ The object NUM in the object stream STM, at INDEX in its table.
: _PDFF-IN-STREAM  ( num stm index file -- obj status )
    >R SWAP R@ _PDFF-OBJSTM ?DUP IF NIP NIP NIP 0 SWAP R> DROP EXIT THEN   ( num index h )
    _PDFF-SH !  OVER SWAP _PDFF-SH @ _PDFF-WHERE
    DUP 0< IF 2DROP R> DROP 0 PDF-S-DAMAGED EXIT THEN
    _PDFF-SOFF ! _PDFF-SNUM !
    _PDFF-SH @ _PDFH.FIRST @ _PDFF-SOFF @ +
    DUP _PDFF-SH @ _PDFH.BYTES PDF-BUF.U @ < 0= IF DROP R> DROP 0 PDF-S-DAMAGED EXIT THEN
    _PDFF-SH @ _PDFH.BYTES PDF-BUF.A @ OVER +  SWAP _PDFF-SH @ _PDFH.BYTES PDF-BUF.U @ SWAP -
    PDF-VALUE >R 2>R 2DROP 2R> R>
    DUP PDF-T-BAD = IF DROP 2DROP R> DROP 0 PDF-S-DAMAGED EXIT THEN
    _PDFF-SNUM @ 0 R> _PDFF-NEW-OBJ DUP IF PDF-S-OK ELSE PDF-S-MEMORY THEN ;

\ =====================================================================
\  Getting an object
\ =====================================================================

\ The object NUM where its entry says.
: _PDFF-GET  ( num file -- obj status )
    2DUP _PDFF.COUNT @ < 0= IF 2DROP 0 PDF-S-MISSING EXIT THEN
    2DUP _PDFF-ENTRY@                                     ( num file e )
    DUP C@ 1 = IF
        DUP 8 + @ SWAP 4 + L@                             ( num file off gen )
        2SWAP >R SWAP R> _PDFF-OBJECT-AT EXIT
    THEN
    DUP C@ 2 = IF
        DUP 8 + @ SWAP 4 + L@                             ( num file stm index )
        ROT _PDFF-IN-STREAM EXIT
    THEN
    DROP 2DROP 0 PDF-S-MISSING ;

\ =====================================================================
\  Repair: the objects found by scanning the file
\ =====================================================================

\ Set an entry whatever was there: a later object in the file stands over
\ an earlier one.
: _PDFF-FORCE  ( num type field2 field3 file -- ok? )
    >R 3 PICK R@ _PDFF-ROOM 0= IF 2DROP 2DROP R> DROP 0 EXIT THEN
    3 PICK R> _PDFF-ENTRY@  TUCK 4 + L!  TUCK 8 + !  C!  DROP -1 ;

: _PDFF-EDGE?  ( c -- flag )  _PDL-CLASS@ 0<> ;

VARIABLE _PDFR-A    VARIABLE _PDFR-U    \ the chunk read
VARIABLE _PDFR-BASE                     \ its offset in the file
VARIABLE _PDFR-TRAILER                  \ where the last "trailer" ends, or -1
VARIABLE _PDFR-V    VARIABLE _PDFR-M    VARIABLE _PDFR-T

\ The digits that end just before I in the chunk: where they start and
\ their value, or -1 when there are none.
: _PDFR-DIGITS  ( i -- start n | -1 )
    0 _PDFR-V !  1 _PDFR-M !
    DUP BEGIN DUP 0> IF DUP 1- _PDFR-A @ + C@ _PDL-DIGIT? ELSE 0 THEN WHILE
        1- DUP _PDFR-A @ + C@ 48 - _PDFR-M @ * _PDFR-V +!
        _PDFR-M @ 10 * _PDFR-M !
    REPEAT
    TUCK = IF DROP -1 EXIT THEN
    _PDFR-V @ ;

\ The white space just before I in the chunk, skipped: where it starts,
\ or -1 when there is none.
: _PDFR-SPACE  ( i -- i' | -1 )
    DUP BEGIN DUP 0> IF DUP 1- _PDFR-A @ + C@ _PDL-CLASS@ 1 = ELSE 0 THEN WHILE
        1-
    REPEAT
    TUCK = IF DROP -1 THEN ;

\ "num gen obj", with "obj" at I in the chunk: the object's entry.
: _PDFR-OBJ  ( i -- ok? )
    DUP 3 + _PDFR-U @ < IF
        DUP 3 + _PDFR-A @ + C@ _PDFF-EDGE? 0= IF DROP -1 EXIT THEN
    THEN
    _PDFR-SPACE DUP 0< IF DROP -1 EXIT THEN
    _PDFR-DIGITS DUP 0< IF DROP -1 EXIT THEN >R
    _PDFR-SPACE DUP 0< IF DROP R> DROP -1 EXIT THEN
    _PDFR-DIGITS DUP 0< IF DROP R> DROP -1 EXIT THEN         ( start num )
    OVER 0> IF
        OVER 1- _PDFR-A @ + C@ _PDFF-EDGE? 0= IF 2DROP R> DROP -1 EXIT THEN
    THEN
    SWAP _PDFR-BASE @ + R> 1 -ROT _PDFF-F @ _PDFF-FORCE ;

\ Whether NAME's bytes are at I in the chunk.
: _PDFR-AT?  ( i name-a name-u -- flag )
    ROT DUP 2 PICK + _PDFR-U @ > IF DROP 2DROP 0 EXIT THEN
    _PDFR-A @ + OVER 2SWAP COMPARE 0= ;

65536 CONSTANT _PDFR-CHUNK

\ Scan the whole file for its objects and its last trailer.  Each chunk
\ looks at the bytes it holds 40 bytes after its start and 64 before its
\ end, so every keyword is seen whole with the numbers before it.
: _PDFR-SCAN  ( -- status )
    -1 _PDFR-TRAILER !
    0 BEGIN DUP _PDFF-F @ _PDFF.SIZE @ < WHILE                ( pos )
        DUP 40 - 0 MAX DUP _PDFR-BASE !
        _PDFR-CHUNK _PDFF-F @ _PDFF-READ ?DUP IF NIP NIP NIP EXIT THEN
        _PDFR-U ! _PDFR-A !
        _PDFR-BASE @ _PDFR-U @ + DUP _PDFF-F @ _PDFF.SIZE @ < IF 64 - THEN   ( pos end )
        SWAP _PDFR-BASE @ - OVER _PDFR-BASE @ - SWAP ?DO
            I _PDFR-A @ + C@ 111 = IF
                I S" obj" _PDFR-AT? IF
                    I _PDFR-OBJ 0= IF DROP UNLOOP PDF-S-MEMORY EXIT THEN
                THEN
            THEN
            I _PDFR-A @ + C@ 116 = IF
                I S" trailer" _PDFR-AT? IF I 7 + _PDFR-BASE @ + _PDFR-TRAILER ! THEN
            THEN
        LOOP
    REPEAT DROP PDF-S-OK ;

\ Whether the object's /Type is NAME.
: _PDFR-TYPE?  ( obj name-a name-u -- flag )
    ROT PDF-OBJ-VALUE DROP S" Type" 2SWAP PDF-DICT@
    PDF-T-NAME = IF 2SWAP PDF-NAME= ELSE 2DROP 2DROP 0 THEN ;

VARIABLE _PDFR-NUM   VARIABLE _PDFR-H

\ Add the objects of each object stream found, unless the file holds
\ them itself.
: _PDFR-STREAMS  ( -- status )
    0 _PDFR-NUM !
    BEGIN _PDFR-NUM @ _PDFF-F @ _PDFF.COUNT @ < WHILE
        _PDFR-NUM @ _PDFF-F @ _PDFF-ENTRY@ C@ 1 = IF
            _PDFR-NUM @ _PDFF-F @ _PDFF-GET 0= IF
                DUP S" ObjStm" _PDFR-TYPE? SWAP _PDFF-F @ PDF-OBJ-FREE
                IF _PDFR-NUM @ _PDFF-F @ _PDFF-OBJSTM 0= IF
                    _PDFR-H !
                    _PDFR-H @ _PDFH.INDEX PDF-BUF.U @ 16 / 0 ?DO
                        _PDFR-H @ _PDFH.INDEX PDF-BUF.A @ I 16 * + @ _PDFR-T !
                        _PDFR-T @ _PDFF-F @ _PDFF-ROOM 0= IF UNLOOP PDF-S-MEMORY EXIT THEN
                        _PDFR-T @ _PDFF-F @ _PDFF-ENTRY@ C@ 1 <> IF
                            _PDFR-T @ 2 _PDFR-NUM @ I _PDFF-F @ _PDFF-FORCE DROP
                        THEN
                    LOOP
                ELSE DROP THEN THEN
            ELSE DROP THEN
        THEN
        1 _PDFR-NUM +!
    REPEAT PDF-S-OK ;

\ The first object whose /Type is /Catalog, or -1.
: _PDFR-CATALOG  ( -- num | -1 )
    0 BEGIN DUP _PDFF-F @ _PDFF.COUNT @ < WHILE
        DUP _PDFF-F @ _PDFF-ENTRY@ C@ DUP 1 = SWAP 2 = OR IF
            DUP _PDFF-F @ _PDFF-GET 0= IF
                DUP S" Catalog" _PDFR-TYPE? SWAP _PDFF-F @ PDF-OBJ-FREE
                IF EXIT THEN
            ELSE DROP THEN
        THEN 1+
    REPEAT DROP -1 ;

CREATE _PDFR-ROOT 64 ALLOT

\ Keep a trailer of only /Root, naming the catalog NUM.
: _PDFR-ROOT!  ( num -- ok? )
    _PDFR-ROOT 40 + SWAP
    BEGIN 10 /MOD SWAP 48 + ROT 1- TUCK C! SWAP DUP 0= UNTIL DROP   ( start )
    9 - S" << /Root " 2 PICK SWAP MOVE
    S"  0 R >>" _PDFR-ROOT 40 + SWAP MOVE
    _PDFR-ROOT 47 + OVER - _PDFF-F @ _PDFF-KEEP-TRAILER ;

\ Read the file again by scanning it: every object, the objects of its
\ object streams, and its last trailer, or else a trailer naming its
\ catalog.
: _PDFF-REPAIR  ( -- status )
    -1 _PDFF-F @ _PDFF.REPAIRED !
    _PDFF-F @ _PDFF.ENTRIES @ ?DUP IF
        _PDFF-F @ _PDFF.EBYTES @ _PDFF-F @ _PDFF.MSRC @ MSRC-FREE
    THEN
    0 _PDFF-F @ _PDFF.ENTRIES !  0 _PDFF-F @ _PDFF.COUNT !  0 _PDFF-F @ _PDFF.EBYTES !
    _PDFF-F @ _PDFF-UNHOLD
    _PDFR-SCAN ?DUP IF EXIT THEN
    _PDFR-TRAILER @ 0< 0= IF
        _PDFR-TRAILER @ _PDFF-POS !
        _PDFF-VALUE ?DUP IF >R 2DROP DROP R> EXIT THEN
        PDF-T-DICT = IF
            _PDFF-F @ _PDFF-KEEP-TRAILER 0= IF PDF-S-MEMORY EXIT THEN
        ELSE 2DROP THEN
    THEN
    _PDFR-STREAMS ?DUP IF EXIT THEN
    S" Root" _PDFF-F @ PDF-TRAILER@ NIP NIP PDF-T-END = IF
        _PDFR-CATALOG DUP 0< IF DROP PDF-S-DAMAGED EXIT THEN
        _PDFR-ROOT! 0= IF PDF-S-MEMORY EXIT THEN
    THEN
    PDF-S-OK ;

\ PDF-GET ( num file -- obj status )
\   The object NUM in a record of its own.  When an open file's object is
\   not where its entry says, the file is read again by scanning, once.
: PDF-GET  ( num file -- obj status )
    2DUP _PDFF-GET DUP PDF-S-DAMAGED = IF
        2 PICK _PDFF.OPEN @ 3 PICK _PDFF.REPAIRED @ 0= AND IF
            2DROP DUP _PDFF-F !
            _PDFF-REPAIR ?DUP IF >R 2DROP 0 R> EXIT THEN
            _PDFF-GET EXIT
        THEN
    THEN
    2SWAP 2DROP ;

' PDF-GET _PDFF-GET-XT !

\ PDF-REPAIRED? ( file -- flag )   Whether the file was read by scanning.
: PDF-REPAIRED?  ( file -- flag )  _PDFF.REPAIRED @ 0<> ;

\ PDF-FILE-MSRC ( file -- msrc )   The memory source the file draws on.
: PDF-FILE-MSRC  ( file -- msrc )  _PDFF.MSRC @ ;

\ PDF-FILE-SOURCE ( file -- source )   The media source it reads.
: PDF-FILE-SOURCE  ( file -- source )  _PDFF.SRC @ ;

\ PDF-FILE-LOCKED? ( file -- flag )   Whether the file needs a password.
: PDF-FILE-LOCKED?  ( file -- flag )
    DUP _PDFF.ENCRYPTED @ IF _PDFF.CRYPT PDF-CRYPT-LOCKED? ELSE DROP 0 THEN ;

\ PDF-RESOLVE ( va vu type file -- obj va' vu' type' status )
\   A value, its reference followed: OBJ is the object to give back, or 0.
: PDF-RESOLVE  ( va vu type file -- obj va' vu' type' status )
    OVER PDF-T-REF <> IF DROP >R 0 -ROT R> PDF-S-OK EXIT THEN
    >R DROP PDF-REF@ DROP R> PDF-GET
    ?DUP IF >R 0 0 PDF-T-END R> EXIT THEN
    DUP PDF-OBJ-VALUE PDF-S-OK ;

\ =====================================================================
\  Cross-reference sections
\ =====================================================================

VARIABLE _PDFF-PREV   \ the section's /Prev, or -1
VARIABLE _PDFF-XSTM   \ its /XRefStm, or -1

\ The section's dictionary: kept as the trailer when it is the first
\ with a /Root, and its /Prev and /XRefStm noted.
: _PDFF-SECTION-DICT  ( da du -- status )
    S" Prev" 2OVER _PDFF-INT@ _PDFF-PREV !
    S" XRefStm" 2OVER _PDFF-INT@ _PDFF-XSTM !
    _PDFF-F @ _PDFF-KEEP-TRAILER IF PDF-S-OK ELSE PDF-S-MEMORY THEN ;

VARIABLE _PDFF-START  VARIABLE _PDFF-N  VARIABLE _PDFF-I

\ A subsection's lines: an offset, a generation, and "n" or "f" each.
: _PDFF-LINES  ( -- status )
    _PDFF-N @ 20 * 64 + _PDFF-LOAD ?DUP IF EXIT THEN
    0 _PDFF-I !
    BEGIN _PDFF-I @ _PDFF-N @ < WHILE
        _PDFF-TOKEN PDF-T-INT <> IF 2DROP PDF-S-DAMAGED EXIT THEN PDF-INT
        _PDFF-TOKEN PDF-T-INT <> IF 2DROP DROP PDF-S-DAMAGED EXIT THEN PDF-INT
        _PDFF-TOKEN PDF-T-KEYWORD <> IF 2DROP 2DROP PDF-S-DAMAGED EXIT THEN
        DROP C@ 110 = IF 1 ELSE 0 THEN >R                 ( off gen )
        _PDFF-START @ _PDFF-I @ + R> 2SWAP                ( num type off gen )
        _PDFF-F @ _PDFF-SET 0= IF PDF-S-MEMORY EXIT THEN
        1 _PDFF-I +!
    REPEAT PDF-S-OK ;

\ A cross-reference table, after its keyword: its subsections, then its
\ trailer.
: _PDFF-TABLE  ( -- status )
    BEGIN
        _PDFF-NEXT ?DUP IF >R 2DROP DROP R> EXIT THEN
        DUP PDF-T-KEYWORD = IF
            S" trailer" _PDFF-KEYWORD? 0= IF PDF-S-DAMAGED EXIT THEN
            _PDFF-VALUE ?DUP IF >R 2DROP DROP R> EXIT THEN
            PDF-T-DICT <> IF 2DROP PDF-S-DAMAGED EXIT THEN
            _PDFF-SECTION-DICT EXIT
        THEN
        PDF-T-INT <> IF 2DROP PDF-S-DAMAGED EXIT THEN
        PDF-INT _PDFF-START !
        _PDFF-TOKEN PDF-T-INT <> IF 2DROP PDF-S-DAMAGED EXIT THEN
        PDF-INT _PDFF-N !
        _PDFF-LINES ?DUP IF EXIT THEN
    AGAIN ;

CREATE _PDFF-XBUF PDF-BUF-SIZE ALLOT
VARIABLE _PDFF-XO   VARIABLE _PDFF-XP   VARIABLE _PDFF-XE
VARIABLE _PDFF-W1   VARIABLE _PDFF-W2   VARIABLE _PDFF-W3
VARIABLE _PDFF-XT   VARIABLE _PDFF-X2   VARIABLE _PDFF-X3

: _PDFF-XDICT  ( -- da du )  _PDFF-XO @ PDF-OBJ-VALUE DROP ;

: _PDFF-XFREE  ( -- )
    _PDFF-XBUF _PDFF-F @ _PDFF.MSRC @ PDF-BUF-FREE
    _PDFF-XO @ _PDFF-F @ PDF-OBJ-FREE  0 _PDFF-XO ! ;

\ A big-endian field of W bytes at A, or DEFAULT when W is 0.
: _PDFF-FIELD  ( a w default -- a' n )
    OVER 0= IF NIP EXIT THEN DROP
    2DUP + -ROT 0 SWAP 0 ?DO OVER I + C@ SWAP 8 LSHIFT OR LOOP NIP ;

: _PDFF-W@  ( i wa wu -- w )
    PDF-ARRAY@ PDF-T-INT = IF PDF-INT ELSE 2DROP -1 THEN ;

\ /W's three widths, each 0 to 8 bytes.
: _PDFF-WIDTHS  ( -- ok? )
    S" W" _PDFF-XDICT PDF-DICT@ PDF-T-ARRAY <> IF 2DROP 0 EXIT THEN
    0 2 PICK 2 PICK _PDFF-W@ _PDFF-W1 !
    1 2 PICK 2 PICK _PDFF-W@ _PDFF-W2 !
    2 2 PICK 2 PICK _PDFF-W@ _PDFF-W3 !  2DROP
    _PDFF-W1 @ 0 9 WITHIN _PDFF-W2 @ 0 9 WITHIN AND _PDFF-W3 @ 0 9 WITHIN AND ;

\ COUNT entries from object START: false when the memory source refuses.
: _PDFF-XRANGE  ( start count -- ok? )
    0 ?DO
        _PDFF-XP @ _PDFF-W1 @ + _PDFF-W2 @ + _PDFF-W3 @ + _PDFF-XE @ > IF
            DROP UNLOOP -1 EXIT
        THEN
        _PDFF-XP @ _PDFF-W1 @ 1 _PDFF-FIELD _PDFF-XT !
        _PDFF-W2 @ 0 _PDFF-FIELD _PDFF-X2 !
        _PDFF-W3 @ 0 _PDFF-FIELD _PDFF-X3 !  _PDFF-XP !
        _PDFF-XT @ 2 > IF 0 _PDFF-XT ! THEN
        DUP I + _PDFF-XT @ _PDFF-X2 @ _PDFF-X3 @ _PDFF-F @ _PDFF-SET 0= IF
            DROP UNLOOP 0 EXIT
        THEN
    LOOP DROP -1 ;

: _PDFF-XINDEX@  ( i ia iu -- n )
    PDF-ARRAY@ PDF-T-INT = IF PDF-INT ELSE 2DROP 0 THEN ;

\ A cross-reference stream: the object at OFFSET.
: _PDFF-XSTREAM  ( offset -- status )
    -1 0 _PDFF-F @ _PDFF-OBJECT-AT ?DUP IF NIP EXIT THEN
    _PDFF-XO !
    _PDFF-XO @ PDF-OBJ-STREAM? 0= _PDFF-WIDTHS 0= OR IF
        _PDFF-XFREE PDF-S-DAMAGED EXIT
    THEN
    _PDFF-XO @ _PDFF-XBUF _PDFF-F @ PDF-STREAM ?DUP IF _PDFF-XFREE EXIT THEN
    _PDFF-XBUF PDF-BUF.A @ DUP _PDFF-XP !  _PDFF-XBUF PDF-BUF.U @ + _PDFF-XE !
    S" Index" _PDFF-XDICT PDF-DICT@ PDF-T-ARRAY = IF          ( ia iu )
        2DUP PDF-ARRAY-N 2/ 0 ?DO
            I 2* 2 PICK 2 PICK _PDFF-XINDEX@
            I 2* 1+ 3 PICK 3 PICK _PDFF-XINDEX@
            _PDFF-XRANGE 0= IF 2DROP UNLOOP _PDFF-XFREE PDF-S-MEMORY EXIT THEN
        LOOP 2DROP
    ELSE
        2DROP 0 S" Size" _PDFF-XDICT _PDFF-INT@ 0 MAX
        _PDFF-XRANGE 0= IF _PDFF-XFREE PDF-S-MEMORY EXIT THEN
    THEN
    _PDFF-XDICT _PDFF-SECTION-DICT  _PDFF-XFREE ;

\ The section at OFFSET: a table or a cross-reference stream.
: _PDFF-SECTION  ( offset -- status )
    DUP _PDFF-POS !
    _PDFF-NEXT ?DUP IF >R 2DROP 2DROP R> EXIT THEN
    DUP PDF-T-KEYWORD = IF
        S" xref" _PDFF-KEYWORD? NIP IF _PDFF-TABLE ELSE PDF-S-DAMAGED THEN EXIT
    THEN
    2DROP DROP _PDFF-XSTREAM ;

\ Where "startxref" says the last section starts, or -1.
: _PDFF-STARTXREF  ( file -- offset | -1 )
    DUP _PDFF.SIZE @ 1024 MIN SWAP >R
    R@ _PDFF.SIZE @ OVER - SWAP R> _PDFF-READ IF 2DROP -1 EXIT THEN
    DUP 9 - BEGIN DUP 0< 0= WHILE                            ( a u i )
        2 PICK OVER + 9 S" startxref" COMPARE 0= IF
            9 + TUCK - >R + R>
            PDF-TOKEN PDF-T-INT = IF PDF-INT NIP NIP EXIT THEN
            2DROP 2DROP -1 EXIT
        THEN 1-
    REPEAT DROP 2DROP -1 ;

\ =====================================================================
\  Opening and closing
\ =====================================================================

VARIABLE _PDFF-LEFT   \ sections a file this long can hold
VARIABLE _PDFF-BROKEN \ true once a section could not be read

\ The file's encryption, from the trailer's /Encrypt and the first of its
\ /ID: opened with the empty password, or locked.
: _PDFF-ENCRYPTION  ( -- status )
    S" Encrypt" _PDFF-F @ PDF-TRAILER@ DUP PDF-T-END = IF DROP 2DROP PDF-S-OK EXIT THEN
    -1 _PDFF-F @ _PDFF.ENCRYPTED !
    DUP PDF-T-REF = IF >R 2DUP PDF-REF@ DROP _PDFF-F @ _PDFF.ENCNUM ! R> THEN
    _PDFF-F @ PDF-RESOLVE
    IF 2DROP DROP S" <<>>" PDF-T-DICT THEN
    PDF-T-DICT <> IF 2DROP S" <<>>" THEN
    S" ID" _PDFF-F @ PDF-TRAILER@ PDF-T-ARRAY = IF
        0 -ROT PDF-ARRAY@
    ELSE 2DROP 0 0 PDF-T-END THEN
    >R 2DUP R@ 0 0 PDF-STRING _PDFF-SN !
    _PDFF-SN @ _PDFF-F @ _PDFF.SBUF _PDFF-F @ _PDFF.MSRC @ PDF-BUF-GROW 0= IF
        R> DROP 2DROP 2DROP _PDFF-F @ PDF-OBJ-FREE PDF-S-MEMORY EXIT
    THEN
    R> _PDFF-F @ _PDFF.SBUF PDF-BUF.A @ _PDFF-SN @ PDF-STRING DROP
    _PDFF-F @ _PDFF.SBUF PDF-BUF.A @ _PDFF-SN @
    _PDFF-F @ _PDFF.CRYPT PDF-CRYPT-SETUP DROP
    _PDFF-F @ PDF-OBJ-FREE  PDF-S-OK ;

\ PDF-OPEN ( source msrc file -- status )
\   Read the file's cross-reference sections and trailer, or when they
\   cannot be read, scan the file for its objects.  Close it with
\   PDF-CLOSE whatever the status.
: PDF-OPEN  ( source msrc file -- status )
    DUP PDF-FILE-SIZE 0 FILL  DUP _PDFF-F !
    TUCK _PDFF.MSRC !  TUCK _PDFF.SRC !
    _PDFF.SRC @ MEDSRC-SIZE@ _PDFF-F @ _PDFF.SIZE !
    _PDFF-F @ _PDFF.SIZE @ 16 / 1+ _PDFF-LEFT !  0 _PDFF-BROKEN !
    _PDFF-F @ _PDFF-STARTXREF  DUP 0< _PDFF-BROKEN !
    BEGIN DUP 0< 0= WHILE
        -1 _PDFF-LEFT +!  _PDFF-LEFT @ 0< IF DROP -1 -1 _PDFF-BROKEN ! ELSE
        _PDFF-SECTION IF -1 -1 _PDFF-BROKEN ! ELSE
        _PDFF-PREV @
        _PDFF-XSTM @ DUP 0< IF DROP ELSE
            SWAP >R _PDFF-SECTION IF R> DROP -1 -1 _PDFF-BROKEN ! ELSE R> THEN
        THEN THEN THEN
    REPEAT DROP
    _PDFF-BROKEN @  S" Root" _PDFF-F @ PDF-TRAILER@ NIP NIP PDF-T-END =  OR IF
        _PDFF-REPAIR ?DUP IF EXIT THEN
    THEN
    _PDFF-ENCRYPTION ?DUP IF EXIT THEN
    -1 _PDFF-F @ _PDFF.OPEN !  PDF-S-OK ;

\ PDF-CLOSE ( file -- )   Give back everything the file holds.
: PDF-CLOSE  ( file -- )
    >R
    R@ _PDFF.ENTRIES @ ?DUP IF R@ _PDFF.EBYTES @ R@ _PDFF.MSRC @ MSRC-FREE THEN
    R@ _PDFF.TRAILER @ ?DUP IF R@ _PDFF.TCAP @ R@ _PDFF.MSRC @ MSRC-FREE THEN
    R@ _PDFF-UNHOLD
    R@ _PDFF.WORK R@ _PDFF.MSRC @ PDF-BUF-FREE
    R@ _PDFF.CBUF R@ _PDFF.MSRC @ PDF-BUF-FREE
    R@ _PDFF.SBUF R@ _PDFF.MSRC @ PDF-BUF-FREE
    R> PDF-FILE-SIZE 0 FILL ;
