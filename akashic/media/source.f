\ =====================================================================
\  media/source.f — the bytes of one thing, read at any offset
\ =====================================================================
\
\  A media source stands for the bytes of a file, a download, or anything
\  else a viewer shows.  Readers ask for an exact span at any offset and
\  never learn where the bytes live.  Whoever made the source releases it,
\  which gives back what it holds, such as an open file.
\
\  A source is a record its creator owns, MEDSRC-SIZE bytes, eight-byte
\  aligned; a kind of source may extend the record after those bytes.
\  READ-XT is ( buf len offset context -- ior ) and either fills BUF with
\  exactly LEN bytes from OFFSET or returns a nonzero ior.  RELEASE-XT is
\  ( context -- ), or 0 when there is nothing to give back.
\
\  Prefix: MEDSRC- (public), _MEDSRC- (private)
\
\  Public API:
\    MEDSRC-SIZE     ( -- bytes )
\    MEDSRC-INIT     ( size read-xt release-xt context source -- )
\    MEDSRC-VALID?   ( source -- flag )
\    MEDSRC-SIZE@    ( source -- bytes )
\    MEDSRC-READ?    ( buf len offset source -- ior )
\    MEDSRC-RELEASE  ( source -- )
\    MEDSRC-MEMORY   ( a u source -- )   bytes already in memory
\ =====================================================================

PROVIDED akashic-media-source

0x4352534944454D41 CONSTANT _MEDSRC-MAGIC   \ "AMEDISRC"

40 CONSTANT MEDSRC-SIZE
: MEDSRC.MAGIC       ( s -- a )      ;
: MEDSRC.READ-XT     ( s -- a )  8 + ;
: MEDSRC.RELEASE-XT  ( s -- a ) 16 + ;
: MEDSRC.CONTEXT     ( s -- a ) 24 + ;
: MEDSRC.SIZE        ( s -- a ) 32 + ;

\ Errors the source itself reports; a reader's own iors pass through.
-1 CONSTANT MEDSRC-E-INVALID    \ not a live source
-2 CONSTANT MEDSRC-E-RANGE      \ the span runs past the end

: MEDSRC-INIT  ( size read-xt release-xt context source -- )
    >R
    R@ MEDSRC.CONTEXT !  R@ MEDSRC.RELEASE-XT !  R@ MEDSRC.READ-XT !
    R@ MEDSRC.SIZE !
    _MEDSRC-MAGIC R> MEDSRC.MAGIC ! ;

: MEDSRC-VALID?  ( source -- flag )
    DUP 0= IF EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP MEDSRC.MAGIC @ _MEDSRC-MAGIC =
    SWAP MEDSRC.READ-XT @ 0<> AND ;

: MEDSRC-SIZE@  ( source -- bytes )  MEDSRC.SIZE @ ;

\ MEDSRC-READ? ( buf len offset source -- ior )
\   Fill BUF with exactly LEN bytes from OFFSET.  A span past the end, or
\   one whose end wraps, is refused before the reader runs.
: MEDSRC-READ?  ( buf len offset source -- ior )
    DUP MEDSRC-VALID? 0= IF 2DROP 2DROP MEDSRC-E-INVALID EXIT THEN
    >R
    2DUP + DUP 2 PICK U< OVER R@ MEDSRC.SIZE @ U> OR IF
        DROP 2DROP DROP R> DROP MEDSRC-E-RANGE EXIT
    THEN DROP
    R@ MEDSRC.CONTEXT @ R> MEDSRC.READ-XT @ EXECUTE ;

\ MEDSRC-RELEASE ( source -- )
\   Give back what the source holds.  The record is no longer a source.
: MEDSRC-RELEASE  ( source -- )
    DUP MEDSRC-VALID? 0= IF DROP EXIT THEN
    DUP MEDSRC.RELEASE-XT @ ?DUP IF OVER MEDSRC.CONTEXT @ SWAP EXECUTE THEN
    0 SWAP MEDSRC.MAGIC ! ;

\ =====================================================================
\  Bytes already in memory
\ =====================================================================
\
\  A memory source reads U bytes at A, which its creator keeps unchanged
\  and alive until it releases the source.  It suits bytes a download or
\  another program already holds.

: _MEDSRC-COPY  ( buf len offset a -- ior )
    + ROT ROT MOVE 0 ;

: MEDSRC-MEMORY  ( a u source -- )
    >R SWAP >R ['] _MEDSRC-COPY 0 R> R> MEDSRC-INIT ;

