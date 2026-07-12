\ =====================================================================
\  practice-head.f - Minimal durable Practice authority head
\ =====================================================================
\  PHEAD is a fixed, pointer-free MP64 record.  All identities and roots
\  are inline 32-byte values.  Runtime pointers, execution tokens,
\  queues, leases, handles, and pending approvals must never be stored
\  in this record.
\
\  PHEAD-VALID? performs structural validation only.  A Practice
\  activator remains responsible for authenticating roots and checking
\  schemas, manifests, grants, exports, and referenced objects.
\ =====================================================================

PROVIDED akashic-runtime-practice-head

REQUIRE identity.f

1095454792 CONSTANT PHEAD-MAGIC       \ "AKPH"
1          CONSTANT PHEAD-FORMAT-V1

1 CONSTANT PHEAD-F-READONLY
2 CONSTANT PHEAD-F-RECOVERY

\ Pointer-free Practice head, 44 cells / 352 bytes.
  0 CONSTANT _PH-MAGIC
  8 CONSTANT _PH-FORMAT
 16 CONSTANT _PH-SIZE
 24 CONSTANT _PH-FLAGS
 32 CONSTANT _PH-ID
 64 CONSTANT _PH-REVISION
 72 CONSTANT _PH-CURRENT-ROOT
104 CONSTANT _PH-PREVIOUS-ROOT
136 CONSTANT _PH-BINDING-ROOT
168 CONSTANT _PH-CELL-ROOT
200 CONSTANT _PH-GRANT-ROOT
232 CONSTANT _PH-MANIFEST-ROOT
264 CONSTANT _PH-SCHEMA-ROOT
296 CONSTANT _PH-EXPORT-ROOT
328 CONSTANT _PH-RETENTION-POLICY
336 CONSTANT _PH-ACTIVATION-POLICY
344 CONSTANT _PH-RESERVED
352 CONSTANT PHEAD-SIZE

: PHEAD.MAGIC              ( head -- a ) _PH-MAGIC + ;
: PHEAD.FORMAT             ( head -- a ) _PH-FORMAT + ;
: PHEAD.SIZE               ( head -- a ) _PH-SIZE + ;
: PHEAD.FLAGS              ( head -- a ) _PH-FLAGS + ;
: PHEAD.ID                 ( head -- id ) _PH-ID + ;
: PHEAD.REVISION           ( head -- a ) _PH-REVISION + ;
: PHEAD.CURRENT-ROOT       ( head -- id ) _PH-CURRENT-ROOT + ;
: PHEAD.PREVIOUS-ROOT      ( head -- id ) _PH-PREVIOUS-ROOT + ;
: PHEAD.BINDING-ROOT       ( head -- id ) _PH-BINDING-ROOT + ;
: PHEAD.CELL-ROOT          ( head -- id ) _PH-CELL-ROOT + ;
: PHEAD.GRANT-ROOT         ( head -- id ) _PH-GRANT-ROOT + ;
: PHEAD.MANIFEST-ROOT      ( head -- id ) _PH-MANIFEST-ROOT + ;
: PHEAD.SCHEMA-ROOT        ( head -- id ) _PH-SCHEMA-ROOT + ;
: PHEAD.EXPORT-ROOT        ( head -- id ) _PH-EXPORT-ROOT + ;
: PHEAD.RETENTION-POLICY   ( head -- a ) _PH-RETENTION-POLICY + ;
: PHEAD.ACTIVATION-POLICY  ( head -- a ) _PH-ACTIVATION-POLICY + ;

: PHEAD-INIT  ( head -- )
    DUP PHEAD-SIZE 0 FILL
    PHEAD-MAGIC OVER PHEAD.MAGIC !
    PHEAD-FORMAT-V1 OVER PHEAD.FORMAT !
    PHEAD-SIZE OVER PHEAD.SIZE !
    1 SWAP PHEAD.REVISION ! ;

: PHEAD-COPY  ( source destination -- )
    2DUP = IF 2DROP EXIT THEN
    PHEAD-SIZE CMOVE ;

: PHEAD-VALID?  ( head -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP PHEAD.MAGIC @ PHEAD-MAGIC =
    OVER PHEAD.FORMAT @ PHEAD-FORMAT-V1 = AND
    OVER PHEAD.SIZE @ PHEAD-SIZE >= AND
    OVER PHEAD.ID RID-PRESENT? AND
    OVER PHEAD.REVISION @ 0> AND
    SWAP PHEAD.CURRENT-ROOT RID-PRESENT? AND ;

: PHEAD-SAME-PRACTICE?  ( a b -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    PHEAD.ID SWAP PHEAD.ID RID= ;

: PHEAD-READONLY?  ( head -- flag )
    PHEAD.FLAGS @ PHEAD-F-READONLY AND 0<> ;
