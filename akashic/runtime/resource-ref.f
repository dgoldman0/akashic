\ =====================================================================
\  resource-ref.f - Stable pointer-free semantic resource references
\ =====================================================================
\  RREF identifies a semantic resource independently of any live lens,
\  component instance, VFS path, Practice membership, or authority grant.
\  Revision zero means "resolve the current revision"; a positive revision
\  is an optimistic exact-revision requirement.
\ =====================================================================

PROVIDED akashic-runtime-rref

REQUIRE identity.f

0 CONSTANT RREF-S-OK
1 CONSTANT RREF-S-INVALID

0x46455252 CONSTANT RREF-MAGIC       \ "RREF"
1          CONSTANT RREF-ABI-VERSION

\ Pointer-free version-1 resource reference, 10 cells / 80 bytes.
 0 CONSTANT _RREF-MAGIC
 8 CONSTANT _RREF-ABI
16 CONSTANT _RREF-SIZE
24 CONSTANT _RREF-ID                 \ RID-SIZE bytes
56 CONSTANT _RREF-REVISION
64 CONSTANT _RREF-FLAGS
72 CONSTANT _RREF-RESERVED
80 CONSTANT RREF-SIZE

: RREF.MAGIC     ( ref -- a ) _RREF-MAGIC + ;
: RREF.ABI       ( ref -- a ) _RREF-ABI + ;
: RREF.SIZE      ( ref -- a ) _RREF-SIZE + ;
: RREF.ID        ( ref -- id ) _RREF-ID + ;
: RREF.REVISION  ( ref -- a ) _RREF-REVISION + ;
: RREF.FLAGS     ( ref -- a ) _RREF-FLAGS + ;

: RREF-INIT  ( ref -- )
    DUP RREF-SIZE 0 FILL
    RREF-MAGIC OVER RREF.MAGIC !
    RREF-ABI-VERSION OVER RREF.ABI !
    RREF-SIZE SWAP RREF.SIZE ! ;

: RREF-VALID?  ( ref -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP RREF.MAGIC @ RREF-MAGIC =
    OVER RREF.ABI @ RREF-ABI-VERSION = AND
    OVER RREF.SIZE @ RREF-SIZE >= AND
    OVER RREF.ID RID-PRESENT? AND
    OVER RREF.REVISION @ 0< 0= AND
    SWAP RREF.FLAGS @ 0= AND ;

: RREF-COPY  ( source destination -- status )
    DUP 0= IF 2DROP RREF-S-INVALID EXIT THEN
    OVER RREF-VALID? 0= IF 2DROP RREF-S-INVALID EXIT THEN
    2DUP = IF 2DROP RREF-S-OK EXIT THEN
    RREF-SIZE CMOVE RREF-S-OK ;

: RREF-ID=  ( a b -- flag )
    DUP RREF-VALID? 0= IF 2DROP 0 EXIT THEN
    OVER RREF-VALID? 0= IF 2DROP 0 EXIT THEN
    RREF.ID SWAP RREF.ID RID= ;

: RREF=  ( a b -- flag )
    DUP RREF-VALID? 0= IF 2DROP 0 EXIT THEN
    OVER RREF-VALID? 0= IF 2DROP 0 EXIT THEN
    2DUP RREF-ID= 0= IF 2DROP 0 EXIT THEN
    2DUP RREF.REVISION @ SWAP RREF.REVISION @ = >R
    RREF.FLAGS @ SWAP RREF.FLAGS @ = R> AND ;
