\ =====================================================================
\  sandbox-module-store.f - Durable storage for installed sandbox modules
\ =====================================================================
\  The store keeps every module revision a host installs in two files,
\  each replaced atomically through vfs-replace.f:
\
\    catalog  one record per module revision ever installed, with its
\             declaration and artifact digests and whether it was
\             revoked or removed; the operation key of each install;
\             and the grants that let other components use a module
\             revision in a Practice.  It is a CRC-checked record
\             (utils/checked-record.f) whose tag is its generation.
\    pack     the declaration and artifact bytes.  Each object is
\             addressed by its digest and framed by a CRC-checked header.
\
\  An install writes the pack before the catalog and a removal writes the
\  catalog before the pack, so the catalog never names an object the pack
\  lacks; the next pack write drops an object no record names.  A removed
\  revision keeps its record, so a revision that was revoked or removed
\  can never be installed again, and an install repeated with the same
\  operation key changes nothing.
\
\  OPEN recovers both files, reads the catalog, indexes the pack, and adds
\  each live module to an empty module owner as DECLARED, retiring the
\  revoked ones.  VERIFY reads a module's artifact on first use.  A
\  declaration that is missing, corrupt or not the recorded one
\  quarantines its module by key, and its bytes stay in the pack until the
\  module is removed.  A catalog or pack the store cannot read puts it in
\  recovery: what can be read still loads, and nothing is written.
\
\  The store is caller-serialized, like the owner it fills.
\ =====================================================================

PROVIDED akashic-sbox-mod-store

REQUIRE identity.f
REQUIRE sandbox-module-owner.f
REQUIRE sandbox-declaration.f
REQUIRE ../math/crc.f
REQUIRE ../utils/checked-record.f
REQUIRE ../utils/fs/vfs.f
REQUIRE ../utils/fs/vfs-replace.f
REQUIRE ../utils/caller-span.f
REQUIRE ../utils/memory-span.f

 0 CONSTANT SBOX-STORE-S-OK
 1 CONSTANT SBOX-STORE-S-INVALID
 2 CONSTANT SBOX-STORE-S-NOMEM
 3 CONSTANT SBOX-STORE-S-IO
 4 CONSTANT SBOX-STORE-S-RECOVERY
 5 CONSTANT SBOX-STORE-S-STATE
 6 CONSTANT SBOX-STORE-S-BUSY
 7 CONSTANT SBOX-STORE-S-CONFLICT
 8 CONSTANT SBOX-STORE-S-DUPLICATE
 9 CONSTANT SBOX-STORE-S-REVOKED
10 CONSTANT SBOX-STORE-S-REMOVED
11 CONSTANT SBOX-STORE-S-MODULE

\ Catalog record flags.
1 CONSTANT SBOX-STORE-F-REVOKED
2 CONSTANT SBOX-STORE-F-REMOVED

\ Pack object kinds.
1 CONSTANT _SST-K-DECLARATION
2 CONSTANT _SST-K-ARTIFACT

\ =====================================================================
\  Formats
\ =====================================================================

\ A catalog record:
\   +0 RID   +32 u64 revision   +40 u32 flags   +44 u32 0
\   +48 declaration digest   +80 artifact digest
112 CONSTANT _SST-RECORD-SIZE
\ An operation key: +0 key   +32 RID   +64 u64 revision
 72 CONSTANT _SST-KEY-SIZE
\ A grant:
\   +0 Practice RID   +32 module RID   +64 u64 revision
\   +72 u16 grantee length   +74 zero to 80   +80 grantee, zero-padded to 144
\ Grants increase by Practice, module RID, revision, then grantee bytes,
\ and each names a record that is not removed.
144 CONSTANT _SST-GRANT-SIZE
\ The catalog payload: u64 record, key and grant counts, the records in
\ key order, the operation keys in byte order, then the grants.
 24 CONSTANT _SST-CATALOG-HEAD

\ A grantee is a component id of 1 through 64 bytes without zero bytes,
\ the size of an interop identifier (CAP-ID-MAX).
64 CONSTANT SBOX-STORE-GRANTEE-MAX

\ The pack header:
\   +0 "AKSBXPAK"   +8 u16 format 1   +10 u16 header 64   +12 u32 CRC
\   +16 u64 total bytes   +24 u64 object count   +32 zero to 64
\ Each object is a header, then its bytes zero-padded to 8:
\   +0 u32 kind   +4 u32 CRC   +8 u64 length   +16 digest
\ Objects strictly increase by kind, then digest.  Each CRC is the CRC-32
\ of its header with the CRC field zero.
64 CONSTANT _SST-PACK-HEAD
48 CONSTANT _SST-OBJECT-HEAD

\ An index entry in memory: kind, file offset of the bytes, length,
\ digest.  While a pack is written, the offset names where the bytes come
\ from: the old pack, or 0 for an install's new object.
56 CONSTANT _SST-INDEX-SIZE

: _SST-CATALOG-MAGIC  ( -- address length ) S" AKSBXCAT" ;
: _SST-PACK-MAGIC  ( -- address length ) S" AKSBXPAK" ;

\ =====================================================================
\  The store record
\ =====================================================================

0x5342585354524F52 CONSTANT _SST-MAGIC  \ "SBXSTROR"

1 CONSTANT _SST-OPEN
2 CONSTANT _SST-RECOVERING

   0 CONSTANT _SST-MAGIC-OFF
   8 CONSTANT _SST-SELF
  16 CONSTANT _SST-VFS
  24 CONSTANT _SST-OWNER
  32 CONSTANT _SST-FLAGS
  40 CONSTANT _SST-GENERATION
\ Five growing tables, each [array, count, room].
  48 CONSTANT _SST-RECORDS
  72 CONSTANT _SST-KEYS
  96 CONSTANT _SST-INDEX
 120 CONSTANT _SST-NEW-INDEX
 144 CONSTANT _SST-GRANTS
 168 CONSTANT _SST-MODULE-STATUS
\ An install's new objects: their bytes and digests.
 176 CONSTANT _SST-NEW-DECL
 184 CONSTANT _SST-NEW-DECL-U
 192 CONSTANT _SST-NEW-DECL-DIGEST
 200 CONSTANT _SST-NEW-ART
 208 CONSTANT _SST-NEW-ART-U
 216 CONSTANT _SST-NEW-ART-DIGEST
 224 CONSTANT _SST-HEADER
\ The catalog callbacks see the store up to here.
 288 CONSTANT _SST-CONTEXT-U
 288 CONSTANT _SST-CAT-REPL
_SST-CAT-REPL VREPL-SIZE + CONSTANT _SST-PACK-REPL
_SST-PACK-REPL VREPL-SIZE + CONSTANT _SST-SPEC
_SST-SPEC CREC-SPEC-SIZE + 7 + -8 AND CONSTANT _SST-WORK
_SST-WORK CREC-WORK-SIZE + 7 + -8 AND CONSTANT _SST-DECL-WS
_SST-DECL-WS SBOX-DECL-WORKSPACE-SIZE + CONSTANT _SST-DIGEST
\ The grant a call names, in canonical form.
_SST-DIGEST 32 + CONSTANT _SST-PROBE
_SST-PROBE _SST-GRANT-SIZE + CONSTANT SBOX-STORE-SIZE

: _SST.MAGIC       ( store -- a ) _SST-MAGIC-OFF + ;
: _SST.SELF        ( store -- a ) _SST-SELF + ;
: _SST.VFS         ( store -- a ) _SST-VFS + ;
: _SST.OWNER       ( store -- a ) _SST-OWNER + ;
: _SST.FLAGS       ( store -- a ) _SST-FLAGS + ;
: _SST.GENERATION  ( store -- a ) _SST-GENERATION + ;
: _SST.RECORDS     ( store -- table ) _SST-RECORDS + ;
: _SST.KEYS        ( store -- table ) _SST-KEYS + ;
: _SST.INDEX       ( store -- table ) _SST-INDEX + ;
: _SST.NEW-INDEX   ( store -- table ) _SST-NEW-INDEX + ;
: _SST.GRANTS      ( store -- table ) _SST-GRANTS + ;
: _SST.MODULE-STATUS  ( store -- a ) _SST-MODULE-STATUS + ;
: _SST.NEW-DECL    ( store -- a ) _SST-NEW-DECL + ;
: _SST.NEW-DECL-U  ( store -- a ) _SST-NEW-DECL-U + ;
: _SST.NEW-DECL-DIGEST  ( store -- a ) _SST-NEW-DECL-DIGEST + ;
: _SST.NEW-ART     ( store -- a ) _SST-NEW-ART + ;
: _SST.NEW-ART-U   ( store -- a ) _SST-NEW-ART-U + ;
: _SST.NEW-ART-DIGEST  ( store -- a ) _SST-NEW-ART-DIGEST + ;
: _SST.HEADER      ( store -- a ) _SST-HEADER + ;
: _SST.CAT-REPL    ( store -- replacement ) _SST-CAT-REPL + ;
: _SST.PACK-REPL   ( store -- replacement ) _SST-PACK-REPL + ;
: _SST.SPEC        ( store -- spec ) _SST-SPEC + ;
: _SST.WORK        ( store -- work ) _SST-WORK + ;
: _SST.DECL-WS     ( store -- workspace ) _SST-DECL-WS + ;
: _SST.DIGEST      ( store -- digest ) _SST-DIGEST + ;
: _SST.PROBE       ( store -- grant ) _SST-PROBE + ;

: _SST-SPAN?  ( address length -- flag )
    OVER 0= IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    CALLER-SPAN-STATUS CALLER-SPAN-S-OK = ;

: SBOX-STORE-VALID?  ( store -- flag )
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP SBOX-STORE-SIZE _SST-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _SST.MAGIC @ _SST-MAGIC <> IF DROP 0 EXIT THEN
    DUP _SST.SELF @ = ;

: _SST-OPEN?  ( store -- flag )
    DUP SBOX-STORE-VALID? 0= IF DROP 0 EXIT THEN
    _SST.FLAGS @ _SST-OPEN AND 0<> ;

: SBOX-STORE-RECOVERY?  ( store -- flag )
    DUP SBOX-STORE-VALID? 0= IF DROP 0 EXIT THEN
    _SST.FLAGS @ _SST-RECOVERING AND 0<> ;

: _SST-RECOVER!  ( store -- ) _SST.FLAGS DUP @ _SST-RECOVERING OR SWAP ! ;

\ The module owner's status behind the latest SBOX-STORE-S-MODULE.
: SBOX-STORE-MODULE-STATUS@  ( store -- module-status )
    _SST.MODULE-STATUS @ ;

\ The catalog's generation: how many times it has been written.
: SBOX-STORE-GENERATION@  ( store -- n ) _SST.GENERATION @ ;

: _SST-DROP7  ( x1 x2 x3 x4 x5 x6 x7 -- ) 2DROP 2DROP 2DROP DROP ;
: _SST-FAIL5  ( x1 x2 x3 x4 x5 status -- 0 status ) >R 2DROP 2DROP DROP 0 R> ;

: _SST-DISCARD  ( address length -- )
    OVER 0= IF 2DROP EXIT THEN
    OVER SWAP 0 FILL FREE ;

: _SST-ZERO?  ( address length -- flag )
    0 ?DO DUP I + C@ IF DROP 0 UNLOOP EXIT THEN LOOP DROP -1 ;

\ The CRC-32 of a header with its CRC field, at OFFSET, read as zero.
\ Checking zeroes the field.
: _SST-CRC-OK?  ( header length offset -- flag )
    2 PICK + DUP SBOX-BYTE-U32-LE@ >R
    0 SWAP SBOX-BYTE-U32-LE!
    CRC32 R> = ;

\ Seals a header whose CRC field is zero.
: _SST-CRC!  ( header length offset -- )
    >R 2DUP CRC32 ROT R> + SBOX-BYTE-U32-LE! DROP ;

\ =====================================================================
\  Growing tables
\ =====================================================================

\ Room for one more element of ELEMENT-U bytes in TABLE.
: _SST-ROOM  ( table element-u -- status )
    OVER 8 + @ 2 PICK 16 + @ < IF 2DROP SBOX-STORE-S-OK EXIT THEN
    OVER 16 + @ 2 * 8 MAX
    2DUP * DUP ALLOCATE IF
        2DROP 2DROP DROP SBOX-STORE-S-NOMEM EXIT
    THEN
    TUCK SWAP 0 FILL
    3 PICK @ ?DUP IF
        DUP 2 PICK 6 PICK 8 + @ 6 PICK * MOVE
        DUP 5 PICK 16 + @ 5 PICK * 0 FILL
        FREE
    THEN
    3 PICK !
    ROT 16 + ! DROP
    SBOX-STORE-S-OK ;

\ Opens a zeroed slot at INDEX; the table has room.
: _SST-INSERT  ( index table element-u -- slot )
    >R
    DUP @ 2 PICK R@ * +
    DUP DUP R@ +
    3 PICK 8 + @ 5 PICK - R@ *
    MOVE
    DUP R> 0 FILL
    SWAP 8 + 1 SWAP +!
    NIP ;

: _SST-DELETE  ( index table element-u -- )
    >R
    DUP @ 2 PICK R@ * +
    DUP R@ + SWAP
    2 PICK 8 + @ 4 PICK - 1- R@ *
    MOVE
    NIP
    DUP 8 + -1 SWAP +!
    DUP @ SWAP 8 + @ R@ * + R> 0 FILL ;

: _SST-TABLE-FREE  ( table element-u -- )
    OVER @ ?DUP IF
        OVER 3 PICK 16 + @ * _SST-DISCARD
    THEN
    DROP 24 0 FILL ;

\ =====================================================================
\  Searching
\ =====================================================================

: _SST-RECORD  ( index store -- record )
    _SST.RECORDS @ SWAP _SST-RECORD-SIZE * + ;
: _SST-KEY  ( index store -- key-record )
    _SST.KEYS @ SWAP _SST-KEY-SIZE * + ;
: _SST-ENTRY  ( index store -- entry )
    _SST.INDEX @ SWAP _SST-INDEX-SIZE * + ;
: _SST-NEW-ENTRY  ( index store -- entry )
    _SST.NEW-INDEX @ SWAP _SST-INDEX-SIZE * + ;

: _SST-RECORD-REVISION@  ( record -- revision ) 32 + SBOX-BYTE-U64-LE@ ;
: _SST-RECORD-FLAGS@  ( record -- flags ) 40 + SBOX-BYTE-U32-LE@ ;
: _SST-RECORD-FLAGS!  ( flags record -- ) 40 + SBOX-BYTE-U32-LE! ;
: _SST-RECORD-DECL  ( record -- digest ) 48 + ;
: _SST-RECORD-ART  ( record -- digest ) 80 + ;
: _SST-LIVE?  ( record -- flag )
    _SST-RECORD-FLAGS@ SBOX-STORE-F-REMOVED AND 0= ;

\ Orders (RID, REVISION) against RECORD's key.
: _SST-RECORD-COMPARE  ( rid revision record -- n )
    ROT RID-SIZE 2 PICK RID-SIZE COMPARE ?DUP IF NIP NIP EXIT THEN
    _SST-RECORD-REVISION@ 2DUP = IF 2DROP 0 EXIT THEN
    < IF -1 ELSE 1 THEN ;

\ Where (RID, REVISION) is or belongs among N ordered records.
: _SST-SEARCH  ( rid revision records n -- index found? )
    SWAP >R 0 SWAP
    BEGIN 2DUP < WHILE
        2DUP + 1 RSHIFT
        4 PICK 4 PICK 2 PICK _SST-RECORD-SIZE * R@ + _SST-RECORD-COMPARE
        DUP 0= IF DROP NIP NIP NIP NIP R> DROP -1 EXIT THEN
        0< IF NIP ELSE 1+ ROT DROP SWAP THEN
    REPEAT
    DROP NIP NIP R> DROP 0 ;

: _SST-FIND-RECORD  ( rid revision store -- index found? )
    DUP _SST.RECORDS @ SWAP _SST.RECORDS 8 + @ _SST-SEARCH ;

: _SST-FIND-KEY  ( key store -- index found? )
    >R 0 R@ _SST.KEYS 8 + @
    BEGIN 2DUP < WHILE
        2DUP + 1 RSHIFT
        3 PICK 32 2 PICK R@ _SST-KEY 32 COMPARE
        DUP 0= IF DROP NIP NIP NIP R> DROP -1 EXIT THEN
        0< IF NIP ELSE 1+ ROT DROP SWAP THEN
    REPEAT
    DROP NIP R> DROP 0 ;

: _SST-GRANT  ( index store -- grant )
    _SST.GRANTS @ SWAP _SST-GRANT-SIZE * + ;

\ Orders PROBE against GRANT: Practice and module RID bytes, revision,
\ then grantee bytes.
: _SST-GRANT-COMPARE  ( probe grant -- n )
    OVER 64 2 PICK 64 COMPARE ?DUP IF NIP NIP EXIT THEN
    OVER 64 + SBOX-BYTE-U64-LE@ OVER 64 + SBOX-BYTE-U64-LE@
    2DUP <> IF < IF -1 ELSE 1 THEN NIP NIP EXIT THEN
    2DROP
    80 + 64 ROT 80 + 64 2SWAP COMPARE ;

: _SST-FIND-GRANT  ( probe store -- index found? )
    >R 0 R@ _SST.GRANTS 8 + @
    BEGIN 2DUP < WHILE
        2DUP + 1 RSHIFT
        3 PICK OVER R@ _SST-GRANT _SST-GRANT-COMPARE
        DUP 0= IF DROP NIP NIP NIP R> DROP -1 EXIT THEN
        0< IF NIP ELSE 1+ ROT DROP SWAP THEN
    REPEAT
    DROP NIP R> DROP 0 ;

\ Orders (KIND, DIGEST) against an index entry.
: _SST-OBJECT-COMPARE  ( kind digest entry -- n )
    ROT OVER @ 2DUP <> IF
        < IF -1 ELSE 1 THEN NIP NIP EXIT
    THEN
    2DROP 24 + >R 32 R> 32 COMPARE ;

\ Where (KIND, DIGEST) is or belongs in an index TABLE.
: _SST-FIND-IN  ( kind digest table -- index found? )
    >R 0 R@ 8 + @
    BEGIN 2DUP < WHILE
        2DUP + 1 RSHIFT
        4 PICK 4 PICK 2 PICK _SST-INDEX-SIZE * R@ @ + _SST-OBJECT-COMPARE
        DUP 0= IF DROP NIP NIP NIP NIP R> DROP -1 EXIT THEN
        0< IF NIP ELSE 1+ ROT DROP SWAP THEN
    REPEAT
    DROP NIP NIP R> DROP 0 ;

: _SST-FIND-OBJECT  ( kind digest store -- index found? )
    _SST.INDEX _SST-FIND-IN ;

\ =====================================================================
\  The catalog
\ =====================================================================

\ RID present, positive revision, known flags, a zero reserved field,
\ and both digests present.
: _SST-RECORD-OK?  ( record -- flag )
    DUP RID-PRESENT? 0= IF DROP 0 EXIT THEN
    DUP _SST-RECORD-REVISION@ 1 < IF DROP 0 EXIT THEN
    DUP _SST-RECORD-FLAGS@
        SBOX-STORE-F-REVOKED SBOX-STORE-F-REMOVED OR INVERT AND IF
        DROP 0 EXIT
    THEN
    DUP 44 + SBOX-BYTE-U32-LE@ IF DROP 0 EXIT THEN
    DUP _SST-RECORD-DECL RID-PRESENT? 0= IF DROP 0 EXIT THEN
    _SST-RECORD-ART RID-PRESENT? ;

: _SST-RECORDS-CANONICAL?  ( records n -- flag )
    0 ?DO
        I _SST-RECORD-SIZE * OVER +
        DUP _SST-RECORD-OK? 0= IF 2DROP 0 UNLOOP EXIT THEN
        I IF
            DUP DUP _SST-RECORD-REVISION@ 2 PICK _SST-RECORD-SIZE -
                _SST-RECORD-COMPARE
            0> 0= IF 2DROP 0 UNLOOP EXIT THEN
        THEN
        DROP
    LOOP
    DROP -1 ;

\ Keys strictly increase, are present, and each names a record.
: _SST-KEYS-CANONICAL?  ( keys m records n -- flag )
    2SWAP 0 ?DO
        I _SST-KEY-SIZE * OVER +
        DUP RID-PRESENT? 0= IF 2DROP 2DROP 0 UNLOOP EXIT THEN
        I IF
            DUP 32 OVER _SST-KEY-SIZE - 32 COMPARE 0> 0= IF
                2DROP 2DROP 0 UNLOOP EXIT
            THEN
        THEN
        DUP 32 + OVER 64 + SBOX-BYTE-U64-LE@ 5 PICK 5 PICK _SST-SEARCH
        NIP 0= IF 2DROP 2DROP 0 UNLOOP EXIT THEN
        DROP
    LOOP
    DROP 2DROP -1 ;

: _SST-GRANTEE?  ( grantee grantee-u -- flag )
    DUP 1 < OVER SBOX-STORE-GRANTEE-MAX > OR IF 2DROP 0 EXIT THEN
    2DUP _SST-SPAN? 0= IF 2DROP 0 EXIT THEN
    0 ?DO DUP I + C@ 0= IF DROP 0 UNLOOP EXIT THEN LOOP DROP -1 ;

: _SST-GRANT-OK?  ( grant -- flag )
    DUP RID-PRESENT? 0= IF DROP 0 EXIT THEN
    DUP 32 + RID-PRESENT? 0= IF DROP 0 EXIT THEN
    DUP 64 + SBOX-BYTE-U64-LE@ 1 < IF DROP 0 EXIT THEN
    DUP 74 + 6 _SST-ZERO? 0= IF DROP 0 EXIT THEN
    DUP 72 + SBOX-BYTE-U16-LE@
    DUP 1 < OVER SBOX-STORE-GRANTEE-MAX > OR IF 2DROP 0 EXIT THEN
    OVER 80 + OVER + SBOX-STORE-GRANTEE-MAX 2 PICK - _SST-ZERO? 0= IF
        2DROP 0 EXIT
    THEN
    SWAP 80 + SWAP _SST-GRANTEE? ;

\ Grants strictly increase, are well formed, and each names a record that
\ is not removed.
: _SST-GRANTS-CANONICAL?  ( grants g records n -- flag )
    2SWAP 0 ?DO
        I _SST-GRANT-SIZE * OVER +
        DUP _SST-GRANT-OK? 0= IF 2DROP 2DROP 0 UNLOOP EXIT THEN
        I IF
            DUP DUP _SST-GRANT-SIZE - _SST-GRANT-COMPARE 0> 0= IF
                2DROP 2DROP 0 UNLOOP EXIT
            THEN
        THEN
        DUP 32 + OVER 64 + SBOX-BYTE-U64-LE@ 5 PICK 5 PICK _SST-SEARCH
        IF 4 PICK SWAP _SST-RECORD-SIZE * + _SST-LIVE? ELSE DROP 0 THEN
        0= IF 2DROP 2DROP 0 UNLOOP EXIT THEN
        DROP
    LOOP
    DROP 2DROP -1 ;

\ A grant whose module revision is removed is not written.
: _SST-GRANT-LIVE?  ( grant store -- flag )
    >R DUP 32 + SWAP 64 + SBOX-BYTE-U64-LE@ R@ _SST-FIND-RECORD
    IF R> _SST-RECORD _SST-LIVE? ELSE DROP R> DROP 0 THEN ;

: _SST-LIVE-GRANT-N  ( store -- n )
    0 OVER _SST.GRANTS 8 + @ 0 ?DO
        I 2 PICK _SST-GRANT 2 PICK _SST-GRANT-LIVE? IF 1+ THEN
    LOOP
    NIP ;

\ The checked-record callbacks.  The context is the store's head.
: _SST-CATALOG-ENCODE  ( store store-u payload payload-u tag -- status )
    2DROP NIP
    OVER _SST.RECORDS 8 + @ OVER SBOX-BYTE-U64-LE!
    OVER _SST.KEYS 8 + @ OVER 8 + SBOX-BYTE-U64-LE!
    OVER _SST-LIVE-GRANT-N OVER 16 + SBOX-BYTE-U64-LE!
    _SST-CATALOG-HEAD +
    OVER _SST.RECORDS @ OVER 3 PICK _SST.RECORDS 8 + @
        _SST-RECORD-SIZE * MOVE
    OVER _SST.RECORDS 8 + @ _SST-RECORD-SIZE * +
    OVER _SST.KEYS @ OVER 3 PICK _SST.KEYS 8 + @ _SST-KEY-SIZE * MOVE
    OVER _SST.KEYS 8 + @ _SST-KEY-SIZE * +
    OVER _SST.GRANTS 8 + @ 0 ?DO
        I 2 PICK _SST-GRANT DUP 3 PICK _SST-GRANT-LIVE? IF
            OVER _SST-GRANT-SIZE MOVE _SST-GRANT-SIZE +
        ELSE
            DROP
        THEN
    LOOP
    2DROP CREC-S-OK ;

: _SST-CATALOG-VALID  ( store store-u payload payload-u tag -- status )
    DROP 2SWAP 2DROP
    DUP _SST-CATALOG-HEAD < IF 2DROP CREC-S-SEMANTIC EXIT THEN
    OVER SBOX-BYTE-U64-LE@ OVER _SST-RECORD-SIZE / U> IF
        2DROP CREC-S-SEMANTIC EXIT
    THEN
    OVER 8 + SBOX-BYTE-U64-LE@ OVER _SST-KEY-SIZE / U> IF
        2DROP CREC-S-SEMANTIC EXIT
    THEN
    OVER 16 + SBOX-BYTE-U64-LE@ OVER _SST-GRANT-SIZE / U> IF
        2DROP CREC-S-SEMANTIC EXIT
    THEN
    OVER SBOX-BYTE-U64-LE@ _SST-RECORD-SIZE *
    2 PICK 8 + SBOX-BYTE-U64-LE@ _SST-KEY-SIZE * +
    2 PICK 16 + SBOX-BYTE-U64-LE@ _SST-GRANT-SIZE * + _SST-CATALOG-HEAD +
    OVER <> IF 2DROP CREC-S-SEMANTIC EXIT THEN
    DROP
    DUP _SST-CATALOG-HEAD + OVER SBOX-BYTE-U64-LE@
        _SST-RECORDS-CANONICAL? 0= IF DROP CREC-S-SEMANTIC EXIT THEN
    DUP _SST-CATALOG-HEAD + OVER SBOX-BYTE-U64-LE@ _SST-RECORD-SIZE * +
    OVER 8 + SBOX-BYTE-U64-LE@
    2 PICK _SST-CATALOG-HEAD + 3 PICK SBOX-BYTE-U64-LE@
    _SST-KEYS-CANONICAL? 0= IF DROP CREC-S-SEMANTIC EXIT THEN
    DUP _SST-CATALOG-HEAD + OVER SBOX-BYTE-U64-LE@ _SST-RECORD-SIZE * +
        OVER 8 + SBOX-BYTE-U64-LE@ _SST-KEY-SIZE * +
    OVER 16 + SBOX-BYTE-U64-LE@
    2 PICK _SST-CATALOG-HEAD + 3 PICK SBOX-BYTE-U64-LE@
    _SST-GRANTS-CANONICAL? NIP
    IF CREC-S-OK ELSE CREC-S-SEMANTIC THEN ;

\ =====================================================================
\  Files
\ =====================================================================

\ PATH open for reading, or 0 when it does not exist.
: _SST-OPEN-READ  ( path path-u store -- fd|0 status )
    >R VFS-FF-READ R> _SST.VFS @ VFS-OPEN?
    ?DUP IF
        NIP VFS-IOR-REASON VFS-R-NOENT = IF
            0 SBOX-STORE-S-OK
        ELSE
            0 SBOX-STORE-S-IO
        THEN
        EXIT
    THEN
    SBOX-STORE-S-OK ;

\ LENGTH bytes at POSITION in FD.
: _SST-PREAD  ( buffer length position fd -- status )
    TUCK VFS-SEEK? IF 2DROP DROP SBOX-STORE-S-IO EXIT THEN
    VFS-READ-EXACT IF SBOX-STORE-S-IO ELSE SBOX-STORE-S-OK THEN ;

: _SST-CLOSE  ( fd|0 -- ) ?DUP IF VFS-CLOSE? DROP THEN ;

\ ENTRY's object read from FD into a fresh buffer the caller frees.
: _SST-READ-OBJECT  ( entry fd -- buffer length status )
    OVER 16 + @ DUP ALLOCATE IF
        2DROP 2DROP 0 0 SBOX-STORE-S-NOMEM EXIT
    THEN
    DUP 2 PICK 5 PICK 8 + @ 5 PICK _SST-PREAD
    >R SWAP 2SWAP 2DROP R>
    DUP IF >R _SST-DISCARD 0 0 R> THEN ;

: _SST-REPLACED>STATUS  ( vrepl-status store -- status )
    OVER VREPL-S-OK = 2 PICK VREPL-S-COMMITTED-CLEANUP = OR IF
        2DROP SBOX-STORE-S-OK EXIT
    THEN
    SWAP VREPL-S-UNCERTAIN = IF
        _SST-RECOVER! SBOX-STORE-S-RECOVERY
    ELSE
        DROP SBOX-STORE-S-IO
    THEN ;

\ Replaces a file.  An outcome nobody can be sure of puts the store in
\ recovery.
: _SST-REPLACE  ( data length replacement store -- status )
    >R ['] VREPL-REPLACE CATCH IF
        2DROP DROP R> DUP _SST-RECOVER! DROP SBOX-STORE-S-RECOVERY EXIT
    THEN
    R> _SST-REPLACED>STATUS ;

: _SST-RECOVERED?  ( vrepl-status -- flag )
    DUP VREPL-S-OK = OVER VREPL-S-ROLLED-BACK = OR
    SWAP VREPL-S-COMMITTED-CLEANUP = OR ;

\ Finishes or undoes an interrupted replacement of one file.
: _SST-RECOVER-FILE  ( replacement store -- )
    >R ['] VREPL-RECOVER CATCH IF DROP 0 ELSE _SST-RECOVERED? THEN
    0= IF R@ _SST-RECOVER! THEN
    R> DROP ;

\ =====================================================================
\  Reading the catalog
\ =====================================================================

\ Validates the catalog file's bytes and takes its tables and generation.
\ A refused catalog puts the store in recovery.
: _SST-TAKE-CATALOG  ( record record-u store -- status )
    >R
    R@ _SST-CONTEXT-U 2SWAP R@ _SST.SPEC R@ _SST.WORK CREC-VALIDATE IF
        R@ _SST-RECOVER! R> DROP SBOX-STORE-S-OK EXIT
    THEN
    R@ _SST.WORK CREC-TAG@ R@ _SST.GENERATION !
    R@ _SST.WORK CREC-PAYLOAD$ DROP
    \ The records.
    DUP SBOX-BYTE-U64-LE@ ?DUP IF
        DUP _SST-RECORD-SIZE * ALLOCATE IF
            2DROP DROP R> DROP SBOX-STORE-S-NOMEM EXIT
        THEN
        R@ _SST.RECORDS !
        DUP R@ _SST.RECORDS 8 + ! R@ _SST.RECORDS 16 + !
        DUP _SST-CATALOG-HEAD + R@ _SST.RECORDS @
            R@ _SST.RECORDS 8 + @ _SST-RECORD-SIZE * MOVE
    THEN
    \ The operation keys.
    DUP 8 + SBOX-BYTE-U64-LE@ ?DUP IF
        DUP _SST-KEY-SIZE * ALLOCATE IF
            2DROP DROP R> DROP SBOX-STORE-S-NOMEM EXIT
        THEN
        R@ _SST.KEYS !
        DUP R@ _SST.KEYS 8 + ! R@ _SST.KEYS 16 + !
        DUP _SST-CATALOG-HEAD + R@ _SST.RECORDS 8 + @ _SST-RECORD-SIZE * +
            R@ _SST.KEYS @ R@ _SST.KEYS 8 + @ _SST-KEY-SIZE * MOVE
    THEN
    \ The grants.
    DUP 16 + SBOX-BYTE-U64-LE@ ?DUP IF
        DUP _SST-GRANT-SIZE * ALLOCATE IF
            2DROP DROP R> DROP SBOX-STORE-S-NOMEM EXIT
        THEN
        R@ _SST.GRANTS !
        DUP R@ _SST.GRANTS 8 + ! R@ _SST.GRANTS 16 + !
        DUP _SST-CATALOG-HEAD + R@ _SST.RECORDS 8 + @ _SST-RECORD-SIZE * +
            R@ _SST.KEYS 8 + @ _SST-KEY-SIZE * +
            R@ _SST.GRANTS @ R@ _SST.GRANTS 8 + @ _SST-GRANT-SIZE * MOVE
    THEN
    DROP R> DROP SBOX-STORE-S-OK ;

: _SST-LOAD-CATALOG  ( store -- status )
    >R
    R@ _SST.CAT-REPL VREPL-TARGET$ R@ _SST-OPEN-READ ?DUP IF
        NIP R> DROP EXIT
    THEN
    ?DUP 0= IF R> DROP SBOX-STORE-S-OK EXIT THEN
    DUP VFS-SIZE DUP CREC-HEADER-SIZE < IF
        DROP _SST-CLOSE R@ _SST-RECOVER! R> DROP SBOX-STORE-S-OK EXIT
    THEN
    DUP ALLOCATE IF
        2DROP _SST-CLOSE R> DROP SBOX-STORE-S-NOMEM EXIT
    THEN
    SWAP
    2DUP 0 5 PICK _SST-PREAD
    3 PICK _SST-CLOSE 2>R NIP 2R>
    IF _SST-DISCARD R> DROP SBOX-STORE-S-IO EXIT THEN
    2DUP R@ _SST-TAKE-CATALOG
    >R _SST-DISCARD R> R> DROP ;

\ =====================================================================
\  Indexing the pack
\ =====================================================================

: _SST-PACK-HEADER-OK?  ( store -- flag )
    _SST.HEADER >R
    R@ 8 _SST-PACK-MAGIC COMPARE IF R> DROP 0 EXIT THEN
    R@ 8 + SBOX-BYTE-U16-LE@ 1 <> IF R> DROP 0 EXIT THEN
    R@ 10 + SBOX-BYTE-U16-LE@ _SST-PACK-HEAD <> IF R> DROP 0 EXIT THEN
    R@ 16 + SBOX-BYTE-U64-LE@ _SST-PACK-HEAD < IF R> DROP 0 EXIT THEN
    R@ 32 + 32 _SST-ZERO? 0= IF R> DROP 0 EXIT THEN
    R> _SST-PACK-HEAD 12 _SST-CRC-OK? ;

\ Indexes the object whose header is at POSITION.  RECOVERY means the
\ pack is malformed from there on.
: _SST-INDEX-OBJECT  ( position total fd store -- next status )
    >R
    2 PICK _SST-OBJECT-HEAD + 2 PICK > IF
        DROP NIP SBOX-STORE-S-RECOVERY R> DROP EXIT
    THEN
    R@ _SST.HEADER _SST-OBJECT-HEAD 4 PICK 3 PICK _SST-PREAD ?DUP IF
        >R DROP NIP R> R> DROP EXIT
    THEN
    DROP
    R@ _SST.HEADER _SST-OBJECT-HEAD 4 _SST-CRC-OK?
    R@ _SST.HEADER SBOX-BYTE-U32-LE@
        DUP _SST-K-DECLARATION = SWAP _SST-K-ARTIFACT = OR AND
    0= IF NIP SBOX-STORE-S-RECOVERY R> DROP EXIT THEN
    \ The bytes fit, padded, before the end.
    R@ _SST.HEADER 8 + SBOX-BYTE-U64-LE@
    DUP 1 < OVER 3 PICK 5 PICK - _SST-OBJECT-HEAD - > OR IF
        DROP NIP SBOX-STORE-S-RECOVERY R> DROP EXIT
    THEN
    DUP 7 + -8 AND 3 PICK + _SST-OBJECT-HEAD +
    DUP 3 PICK > IF 2DROP NIP SBOX-STORE-S-RECOVERY R> DROP EXIT THEN
    \ After the previous object.
    R@ _SST.INDEX 8 + @ IF
        R@ _SST.HEADER SBOX-BYTE-U32-LE@ R@ _SST.HEADER 16 +
        R@ _SST.INDEX 8 + @ 1- R@ _SST-ENTRY _SST-OBJECT-COMPARE
        0> 0= IF 2DROP NIP SBOX-STORE-S-RECOVERY R> DROP EXIT THEN
    THEN
    R@ _SST.INDEX _SST-INDEX-SIZE _SST-ROOM ?DUP IF
        >R 2DROP NIP R> R> DROP EXIT
    THEN
    R@ _SST.INDEX 8 + @ R@ _SST.INDEX _SST-INDEX-SIZE _SST-INSERT
    R@ _SST.HEADER SBOX-BYTE-U32-LE@ OVER !
    4 PICK _SST-OBJECT-HEAD + OVER 8 + !
    2 PICK OVER 16 + !
    R@ _SST.HEADER 16 + SWAP 24 + 32 MOVE
    NIP NIP NIP SBOX-STORE-S-OK R> DROP ;

: _SST-SCAN-PACK  ( store -- status )
    DUP _SST.PACK-REPL VREPL-TARGET$ 2 PICK _SST-OPEN-READ ?DUP IF
        NIP NIP EXIT
    THEN
    ?DUP 0= IF DROP SBOX-STORE-S-OK EXIT THEN
    DUP VFS-SIZE
    DUP _SST-PACK-HEAD < IF
        DROP _SST-CLOSE _SST-RECOVER! SBOX-STORE-S-OK EXIT
    THEN
    2 PICK _SST.HEADER _SST-PACK-HEAD 0 4 PICK _SST-PREAD IF
        DROP _SST-CLOSE DROP SBOX-STORE-S-IO EXIT
    THEN
    2 PICK _SST-PACK-HEADER-OK? 0= IF
        DROP _SST-CLOSE _SST-RECOVER! SBOX-STORE-S-OK EXIT
    THEN
    \ A file longer or shorter than its header says is damaged, but the
    \ objects that fit in both still load.
    2 PICK _SST.HEADER 16 + SBOX-BYTE-U64-LE@
    2DUP <> IF 3 PICK _SST-RECOVER! THEN
    MIN
    _SST-PACK-HEAD
    3 PICK _SST.HEADER 24 + SBOX-BYTE-U64-LE@ 0 ?DO
        DUP 2 PICK 4 PICK 6 PICK _SST-INDEX-OBJECT
        ?DUP IF
            NIP NIP NIP SWAP _SST-CLOSE
            DUP SBOX-STORE-S-RECOVERY = IF
                DROP _SST-RECOVER! SBOX-STORE-S-OK
            ELSE
                NIP
            THEN
            UNLOOP EXIT
        THEN
        NIP
    LOOP
    \ The last object ends the file.
    <> IF OVER _SST-RECOVER! THEN
    _SST-CLOSE DROP SBOX-STORE-S-OK ;

\ =====================================================================
\  Loading modules into the owner
\ =====================================================================

\ Adds RECORD's module to the owner quarantined by its key.
: _SST-QUARANTINE-RECORD  ( reason record store -- status )
    >R
    DUP _SST-RECORD-REVISION@ ROT R> _SST.OWNER @
    SBOX-MODULE-ADD-QUARANTINED NIP
    SBOX-MODULE-S-NOMEM = IF SBOX-STORE-S-NOMEM ELSE SBOX-STORE-S-OK THEN ;

\ Adds the module RECORD names to the owner: DECLARED, retired when
\ revoked, or quarantined when its declaration is missing, corrupt, not
\ the recorded one, or for another profile.
: _SST-LOAD-RECORD  ( record fd store -- status )
    >R
    _SST-K-DECLARATION 2 PICK _SST-RECORD-DECL R@ _SST-FIND-OBJECT 0= IF
        2DROP SBOX-MODULE-Q-STORE SWAP R> _SST-QUARANTINE-RECORD EXIT
    THEN
    R@ _SST-ENTRY SWAP _SST-READ-OBJECT
    ?DUP IF
        NIP NIP SBOX-STORE-S-NOMEM = IF DROP R> DROP SBOX-STORE-S-NOMEM EXIT THEN
        SBOX-MODULE-Q-STORE SWAP R> _SST-QUARANTINE-RECORD EXIT
    THEN
    \ The recorded declaration, for the recorded revision and artifact.
    2DUP R@ _SST.DIGEST R@ _SST.DECL-WS SBOX-DECL-DIGEST
    R@ _SST.DIGEST 32 5 PICK _SST-RECORD-DECL 32 COMPARE OR IF
        _SST-DISCARD SBOX-MODULE-Q-STORE SWAP R> _SST-QUARANTINE-RECORD EXIT
    THEN
    OVER SBOX-DECL-MODULE@ 4 PICK _SST-RECORD-REVISION@ <>
    SWAP RID-SIZE 5 PICK RID-SIZE COMPARE OR
    2 PICK SBOX-DECL-ARTIFACT-DIGEST@ 32 5 PICK _SST-RECORD-ART 32 COMPARE OR
    IF
        _SST-DISCARD SBOX-MODULE-Q-STORE SWAP R> _SST-QUARANTINE-RECORD EXIT
    THEN
    2DUP 0 R@ _SST.OWNER @ SBOX-MODULE-ADD
    >R >R _SST-DISCARD R> R>
    DUP SBOX-MODULE-S-OK = IF
        DROP SWAP _SST-RECORD-FLAGS@ SBOX-STORE-F-REVOKED AND IF
            SBOX-MODULE-RETIRE DROP
        ELSE
            DROP
        THEN
        R> DROP SBOX-STORE-S-OK EXIT
    THEN
    NIP
    DUP SBOX-MODULE-S-NOMEM = IF 2DROP R> DROP SBOX-STORE-S-NOMEM EXIT THEN
    SBOX-MODULE-S-PROFILE = IF SBOX-MODULE-Q-PROFILE ELSE SBOX-MODULE-Q-STORE THEN
    SWAP R> _SST-QUARANTINE-RECORD ;

: _SST-LOAD-MODULES  ( store -- status )
    DUP _SST.PACK-REPL VREPL-TARGET$ 2 PICK _SST-OPEN-READ ?DUP IF
        NIP NIP EXIT
    THEN
    OVER _SST.RECORDS 8 + @ 0 ?DO
        I 2 PICK _SST-RECORD DUP _SST-LIVE? IF
            OVER 3 PICK _SST-LOAD-RECORD ?DUP IF
                SWAP _SST-CLOSE NIP UNLOOP EXIT
            THEN
        ELSE
            DROP
        THEN
    LOOP
    _SST-CLOSE DROP SBOX-STORE-S-OK ;

\ =====================================================================
\  Writing
\ =====================================================================

: _SST-NEW-FREE  ( store -- ) _SST.NEW-INDEX _SST-INDEX-SIZE _SST-TABLE-FREE ;
: _SST-NEW-CLEAR  ( store -- ) _SST.NEW-DECL 48 0 FILL ;

\ Where a needed object's bytes come from: an offset in the old pack, or
\ 0 for an install's new object.  LENGTH is 0 when nothing has it.
: _SST-SOURCE  ( kind digest store -- offset length )
    >R
    2DUP R@ _SST-FIND-OBJECT IF
        NIP NIP R> _SST-ENTRY DUP 8 + @ SWAP 16 + @ EXIT
    THEN
    DROP
    SWAP _SST-K-DECLARATION = IF
        R@ _SST.NEW-DECL-DIGEST @ ?DUP IF 32 SWAP 32 COMPARE 0= ELSE DROP 0 THEN
        IF 0 R> _SST.NEW-DECL-U @ EXIT THEN
    ELSE
        R@ _SST.NEW-ART-DIGEST @ ?DUP IF 32 SWAP 32 COMPARE 0= ELSE DROP 0 THEN
        IF 0 R> _SST.NEW-ART-U @ EXIT THEN
    THEN
    R> DROP 0 0 ;

\ Adds an object to the new pack's index, once.
: _SST-NEED  ( kind digest store -- status )
    >R
    2DUP R@ _SST.NEW-INDEX _SST-FIND-IN IF
        DROP 2DROP R> DROP SBOX-STORE-S-OK EXIT
    THEN
    DROP
    2DUP R@ _SST-SOURCE
    DUP 0= IF 2DROP 2DROP R> DROP SBOX-STORE-S-OK EXIT THEN
    R@ _SST.NEW-INDEX _SST-INDEX-SIZE _SST-ROOM ?DUP IF
        >R 2DROP 2DROP R> R> DROP EXIT
    THEN
    3 PICK 3 PICK R@ _SST.NEW-INDEX _SST-FIND-IN DROP
    R@ _SST.NEW-INDEX _SST-INDEX-SIZE _SST-INSERT
    TUCK 16 + ! TUCK 8 + !
    TUCK 24 + 32 MOVE !
    R> DROP SBOX-STORE-S-OK ;

\ The new pack's index: every object a live record names.
: _SST-NEEDED  ( store -- status )
    DUP _SST-NEW-FREE
    DUP _SST.RECORDS 8 + @ 0 ?DO
        I OVER _SST-RECORD DUP _SST-LIVE? IF
            _SST-K-DECLARATION OVER _SST-RECORD-DECL 3 PICK _SST-NEED ?DUP IF
                NIP NIP UNLOOP EXIT
            THEN
            _SST-K-ARTIFACT SWAP _SST-RECORD-ART 2 PICK _SST-NEED ?DUP IF
                NIP UNLOOP EXIT
            THEN
        ELSE
            DROP
        THEN
    LOOP
    DROP SBOX-STORE-S-OK ;

: _SST-PACK-SIZE  ( store -- total )
    _SST-PACK-HEAD SWAP
    DUP _SST.NEW-INDEX 8 + @ 0 ?DO
        I OVER _SST-NEW-ENTRY 16 + @ 7 + -8 AND _SST-OBJECT-HEAD +
        ROT + SWAP
    LOOP
    DROP ;

\ Writes ENTRY's object at AT, its bytes copied from FD or from the
\ install's new object.
: _SST-PUT-OBJECT  ( at entry fd store -- status )
    >R >R
    DUP @ 2 PICK SBOX-BYTE-U32-LE!
    DUP 16 + @ 2 PICK 8 + SBOX-BYTE-U64-LE!
    DUP 24 + 2 PICK 16 + 32 MOVE
    OVER _SST-OBJECT-HEAD 4 _SST-CRC!
    DUP 8 + @ ?DUP IF
        >R SWAP _SST-OBJECT-HEAD + SWAP 16 + @ R> R> _SST-PREAD
        R> DROP EXIT
    THEN
    R> DROP R>
    OVER @ _SST-K-DECLARATION = IF _SST.NEW-DECL @ ELSE _SST.NEW-ART @ THEN
    ROT _SST-OBJECT-HEAD + ROT 16 + @ MOVE
    SBOX-STORE-S-OK ;

\ Writes the new pack into BUFFER, TOTAL zero bytes.
: _SST-FILL-PACK  ( buffer total fd store -- status )
    _SST-PACK-MAGIC 5 PICK SWAP MOVE
    1 4 PICK 8 + SBOX-BYTE-U16-LE!
    _SST-PACK-HEAD 4 PICK 10 + SBOX-BYTE-U16-LE!
    2 PICK 4 PICK 16 + SBOX-BYTE-U64-LE!
    DUP _SST.NEW-INDEX 8 + @ 4 PICK 24 + SBOX-BYTE-U64-LE!
    3 PICK _SST-PACK-HEAD 12 _SST-CRC!
    _SST-PACK-HEAD
    OVER _SST.NEW-INDEX 8 + @ 0 ?DO
        4 PICK OVER +
        I 3 PICK _SST-NEW-ENTRY
        4 PICK 4 PICK _SST-PUT-OBJECT ?DUP IF
            >R 2DROP 2DROP DROP R> UNLOOP EXIT
        THEN
        \ The entry now names its place in the new pack.
        I 2 PICK _SST-NEW-ENTRY
        OVER _SST-OBJECT-HEAD + OVER 8 + !
        16 + @ 7 + -8 AND _SST-OBJECT-HEAD + +
    LOOP
    2DROP 2DROP DROP SBOX-STORE-S-OK ;

: _SST-INDEX-SWAP  ( store -- )
    DUP _SST.INDEX _SST-INDEX-SIZE _SST-TABLE-FREE
    DUP _SST.NEW-INDEX OVER _SST.INDEX 24 MOVE
    _SST.NEW-INDEX 24 0 FILL ;

\ Replaces the pack with one holding exactly the objects the live records
\ name.  Old objects are copied as they are, checked or not.
: _SST-WRITE-PACK  ( store -- status )
    DUP _SST-NEEDED ?DUP IF OVER _SST-NEW-FREE NIP EXIT THEN
    DUP _SST-PACK-SIZE
    DUP ALLOCATE IF 2DROP _SST-NEW-FREE SBOX-STORE-S-NOMEM EXIT THEN
    2DUP SWAP 0 FILL
    2 PICK _SST.PACK-REPL VREPL-TARGET$ 4 PICK _SST-OPEN-READ ?DUP IF
        NIP >R SWAP _SST-DISCARD _SST-NEW-FREE R> EXIT
    THEN
    >R SWAP R>
    2 PICK 2 PICK 2 PICK 6 PICK _SST-FILL-PACK
    SWAP _SST-CLOSE
    ?DUP IF >R _SST-DISCARD _SST-NEW-FREE R> EXIT THEN
    2DUP 4 PICK _SST.PACK-REPL 5 PICK _SST-REPLACE
    >R _SST-DISCARD R>
    ?DUP IF OVER _SST-NEW-FREE NIP EXIT THEN
    _SST-INDEX-SWAP SBOX-STORE-S-OK ;

: _SST-CATALOG-U  ( store -- payload-u )
    DUP _SST.RECORDS 8 + @ _SST-RECORD-SIZE *
    OVER _SST.KEYS 8 + @ _SST-KEY-SIZE * +
    SWAP _SST-LIVE-GRANT-N _SST-GRANT-SIZE * + _SST-CATALOG-HEAD + ;

\ Replaces the catalog with the tables in memory, one generation on.
: _SST-WRITE-CATALOG  ( store -- status )
    DUP _SST-CATALOG-U OVER _SST.SPEC CREC-MEASURE IF
        2DROP SBOX-STORE-S-INVALID EXIT
    THEN
    DUP ALLOCATE IF 2DROP DROP SBOX-STORE-S-NOMEM EXIT THEN
    SWAP
    2 PICK _SST-CONTEXT-U 4 PICK _SST-CATALOG-U 5 PICK _SST.GENERATION @ 1+
    5 PICK 5 PICK 8 PICK _SST.SPEC 9 PICK _SST.WORK CREC-ENCODE
    NIP IF _SST-DISCARD DROP SBOX-STORE-S-INVALID EXIT THEN
    2DUP 4 PICK _SST.CAT-REPL 5 PICK _SST-REPLACE
    >R _SST-DISCARD R>
    DUP 0= IF 1 2 PICK _SST.GENERATION +! THEN NIP ;

\ =====================================================================
\  Lifecycle
\ =====================================================================

\ Configures STORE, SBOX-STORE-SIZE cell-aligned bytes, to keep the
\ modules OWNER holds in two files of VFS, at absolute paths in one
\ directory.  The owner stays the caller's.
: SBOX-STORE-INIT
  ( vfs catalog-path catalog-u pack-path pack-u owner store -- status )
    DUP 0= OVER 7 AND OR IF _SST-DROP7 SBOX-STORE-S-INVALID EXIT THEN
    DUP SBOX-STORE-SIZE _SST-SPAN? 0= IF
        _SST-DROP7 SBOX-STORE-S-INVALID EXIT
    THEN
    DUP SBOX-STORE-VALID? IF _SST-DROP7 SBOX-STORE-S-STATE EXIT THEN
    OVER SBOX-MODULE-OWNER-VALID? 0= IF
        _SST-DROP7 SBOX-STORE-S-INVALID EXIT
    THEN
    6 PICK 0= IF _SST-DROP7 SBOX-STORE-S-INVALID EXIT THEN
    DUP SBOX-STORE-SIZE 0 FILL
    >R R@ _SST.OWNER !
    4 PICK R@ _SST.VFS !
    4 PICK R@ _SST.PACK-REPL VREPL-INIT IF
        2DROP 2DROP DROP R> DROP SBOX-STORE-S-INVALID EXIT
    THEN
    R@ _SST.PACK-REPL VREPL-DERIVE-PATHS! IF
        2DROP DROP R> SBOX-STORE-SIZE 0 FILL SBOX-STORE-S-INVALID EXIT
    THEN
    2 PICK R@ _SST.CAT-REPL VREPL-INIT IF
        2DROP DROP R> SBOX-STORE-SIZE 0 FILL SBOX-STORE-S-INVALID EXIT
    THEN
    R@ _SST.CAT-REPL VREPL-DERIVE-PATHS! IF
        DROP R> SBOX-STORE-SIZE 0 FILL SBOX-STORE-S-INVALID EXIT
    THEN
    DROP
    _SST-CATALOG-MAGIC 1 CREC-TAG-POSITIVE
        ['] _SST-CATALOG-ENCODE ['] _SST-CATALOG-VALID
        R@ _SST.SPEC CREC-SPEC-INIT
    \ The catalog grows with its records; memory, not the format, bounds it.
    _SST-CATALOG-HEAD 1 62 LSHIFT 8 R@ _SST.SPEC CREC-SPEC-FRAMED! OR
    R@ _SST.SPEC CREC-SPEC-SEAL OR
    R@ _SST.WORK CREC-WORK-INIT OR IF
        R> SBOX-STORE-SIZE 0 FILL SBOX-STORE-S-INVALID EXIT
    THEN
    R@ DUP _SST.SELF !
    _SST-MAGIC R> _SST.MAGIC !
    SBOX-STORE-S-OK ;

\ Frees what OPEN read.  The store stays configured, and the owner keeps
\ its modules.
: SBOX-STORE-CLOSE  ( store -- status )
    DUP SBOX-STORE-VALID? 0= IF DROP SBOX-STORE-S-INVALID EXIT THEN
    DUP _SST.RECORDS _SST-RECORD-SIZE _SST-TABLE-FREE
    DUP _SST.KEYS _SST-KEY-SIZE _SST-TABLE-FREE
    DUP _SST.INDEX _SST-INDEX-SIZE _SST-TABLE-FREE
    DUP _SST.GRANTS _SST-GRANT-SIZE _SST-TABLE-FREE
    DUP _SST-NEW-FREE
    DUP _SST-NEW-CLEAR
    0 OVER _SST.FLAGS !
    0 SWAP _SST.GENERATION !
    SBOX-STORE-S-OK ;

: _SST-OPEN-BODY  ( store -- status )
    DUP _SST.CAT-REPL OVER _SST-RECOVER-FILE
    DUP _SST.PACK-REPL OVER _SST-RECOVER-FILE
    DUP _SST-LOAD-CATALOG ?DUP IF NIP EXIT THEN
    DUP _SST-SCAN-PACK ?DUP IF NIP EXIT THEN
    _SST-LOAD-MODULES ;

\ Recovers both files, reads them and fills the owner, which must be
\ empty.  On a refusal the store stays closed, and the caller releases
\ any modules the owner was given.
: SBOX-STORE-OPEN  ( store -- status )
    DUP SBOX-STORE-VALID? 0= IF DROP SBOX-STORE-S-INVALID EXIT THEN
    DUP _SST.FLAGS @ IF DROP SBOX-STORE-S-STATE EXIT THEN
    DUP _SST.OWNER @ SBOX-MODULE-COUNT@ IF DROP SBOX-STORE-S-STATE EXIT THEN
    DUP ['] _SST-OPEN-BODY CATCH IF DROP SBOX-STORE-S-IO THEN
    ?DUP IF OVER SBOX-STORE-CLOSE DROP NIP EXIT THEN
    _SST.FLAGS DUP @ _SST-OPEN OR SWAP !
    SBOX-STORE-S-OK ;

\ =====================================================================
\  Installing
\ =====================================================================

\ An install repeated with KEY-RECORD's operation key: the same module
\ revision and declaration, or a conflict.
: _SST-REPLAY  ( declaration key-record store -- module|0 status )
    >R
    DUP 32 + OVER 64 + SBOX-BYTE-U64-LE@ R@ _SST-FIND-RECORD 0= IF
        DROP 2DROP R> DROP 0 SBOX-STORE-S-CONFLICT EXIT
    THEN
    R@ _SST-RECORD
    DUP _SST-RECORD-DECL 32 R@ _SST.DIGEST 32 COMPARE
    3 PICK SBOX-DECL-MODULE@ 3 PICK _SST-RECORD-REVISION@ <>
    SWAP RID-SIZE 4 PICK RID-SIZE COMPARE OR OR IF
        DROP 2DROP R> DROP 0 SBOX-STORE-S-CONFLICT EXIT
    THEN
    NIP NIP
    DUP _SST-LIVE? 0= IF DROP R> DROP 0 SBOX-STORE-S-REMOVED EXIT THEN
    DUP _SST-RECORD-REVISION@ R> _SST.OWNER @ SBOX-MODULE-FIND
    DUP IF SBOX-STORE-S-OK ELSE SBOX-STORE-S-STATE THEN ;

: _SST-RECORD-FILL  ( module record -- )
    OVER SBOX-MODULE-KEY@ 2 PICK 32 + SBOX-BYTE-U64-LE!
    OVER RID-SIZE MOVE
    OVER SBOX-MODULE-DECLARATION-DIGEST@ OVER _SST-RECORD-DECL 32 MOVE
    SWAP SBOX-MODULE-DECLARATION$ DROP SBOX-DECL-ARTIFACT-DIGEST@
    SWAP _SST-RECORD-ART 32 MOVE ;

\ Forgets an install that could not be made durable.
: _SST-UNDO-INSTALL  ( record-index module key store -- )
    >R
    R@ _SST-FIND-KEY IF R@ _SST.KEYS _SST-KEY-SIZE _SST-DELETE ELSE DROP THEN
    R@ _SST.OWNER @ SBOX-MODULE-REMOVE DROP
    R> _SST.RECORDS _SST-RECORD-SIZE _SST-DELETE ;

\ Records the module the owner just took, with KEY, and writes the pack
\ and then the catalog.
: _SST-COMMIT-INSTALL  ( record-index module key store -- module|0 status )
    >R
    R@ _SST.RECORDS _SST-RECORD-SIZE _SST-ROOM
    R@ _SST.KEYS _SST-KEY-SIZE _SST-ROOM OR IF
        DROP NIP R@ _SST.OWNER @ SBOX-MODULE-REMOVE DROP
        R> DROP 0 SBOX-STORE-S-NOMEM EXIT
    THEN
    2 PICK R@ _SST.RECORDS _SST-RECORD-SIZE _SST-INSERT
    2 PICK SWAP _SST-RECORD-FILL
    DUP R@ _SST-FIND-KEY DROP R@ _SST.KEYS _SST-KEY-SIZE _SST-INSERT
    OVER OVER 32 MOVE
    2 PICK SBOX-MODULE-KEY@ 2 PICK 64 + SBOX-BYTE-U64-LE!
    OVER 32 + RID-SIZE MOVE
    DROP
    \ The new objects: the declaration and the plan's artifact.
    OVER SBOX-MODULE-DECLARATION$ R@ _SST.NEW-DECL-U ! R@ _SST.NEW-DECL !
    OVER SBOX-MODULE-DECLARATION-DIGEST@ R@ _SST.NEW-DECL-DIGEST !
    OVER SBOX-MODULE-PIN DROP SBOX-PLAN-ARTIFACT$
        R@ _SST.NEW-ART-U ! R@ _SST.NEW-ART !
    R@ _SST.NEW-DECL @ SBOX-DECL-ARTIFACT-DIGEST@ R@ _SST.NEW-ART-DIGEST !
    R@ _SST-WRITE-PACK
    ?DUP 0= IF R@ _SST-WRITE-CATALOG THEN
    2 PICK SBOX-MODULE-UNPIN DROP
    R@ _SST-NEW-CLEAR
    ?DUP IF
        R@ SWAP >R
        _SST-UNDO-INSTALL
        R> R> DROP 0 SWAP EXIT
    THEN
    DROP NIP R> DROP SBOX-STORE-S-OK ;

\ Installs the module DECLARATION describes and BUILD holds verified, as
\ the operation KEY, a 32-byte identity the caller gives each install.
\ The module is VERIFIED, durable, and reused by a repeated KEY.
: SBOX-STORE-INSTALL
  ( key declaration declaration-u build store -- module|0 status )
    DUP _SST-OPEN? 0= IF SBOX-STORE-S-STATE _SST-FAIL5 EXIT THEN
    DUP SBOX-STORE-RECOVERY? IF SBOX-STORE-S-RECOVERY _SST-FAIL5 EXIT THEN
    4 PICK RID-SIZE _SST-SPAN? 0= IF SBOX-STORE-S-INVALID _SST-FAIL5 EXIT THEN
    4 PICK RID-PRESENT? 0= IF SBOX-STORE-S-INVALID _SST-FAIL5 EXIT THEN
    >R
    2 PICK 2 PICK R@ _SST.DIGEST R@ _SST.DECL-WS SBOX-DECL-DIGEST IF
        2DROP 2DROP R> DROP 0 SBOX-STORE-S-INVALID EXIT
    THEN
    \ The same operation again changes nothing.
    3 PICK R@ _SST-FIND-KEY IF
        R@ _SST-KEY 3 PICK SWAP R@ _SST-REPLAY
        2>R 2DROP 2DROP 2R> R> DROP EXIT
    THEN
    DROP
    \ A revision installs once.
    2 PICK SBOX-DECL-MODULE@ R@ _SST-FIND-RECORD IF
        R@ _SST-RECORD _SST-RECORD-FLAGS@ IF
            SBOX-STORE-S-REVOKED
        ELSE
            SBOX-STORE-S-DUPLICATE
        THEN
        >R 2DROP 2DROP R> R> DROP 0 SWAP EXIT
    THEN
    \ The owner checks the build against the declaration and takes it.
    3 PICK 3 PICK 3 PICK R@ _SST.OWNER @ SBOX-MODULE-ADD
    ?DUP IF
        R@ _SST.MODULE-STATUS ! DROP 2DROP 2DROP DROP
        R> DROP 0 SBOX-STORE-S-MODULE EXIT
    THEN
    >R >R 2DROP DROP R> R>
    ROT R> _SST-COMMIT-INSTALL ;

\ =====================================================================
\  Revoking, removing and verifying
\ =====================================================================

\ Stops MODULE for good: durably revoked, then retired.
: SBOX-STORE-REVOKE  ( module store -- status )
    DUP _SST-OPEN? 0= IF 2DROP SBOX-STORE-S-STATE EXIT THEN
    DUP SBOX-STORE-RECOVERY? IF 2DROP SBOX-STORE-S-RECOVERY EXIT THEN
    OVER SBOX-MODULE-STATE@ 0= IF 2DROP SBOX-STORE-S-INVALID EXIT THEN
    >R
    DUP SBOX-MODULE-KEY@ R@ _SST-FIND-RECORD 0= IF
        2DROP R> DROP SBOX-STORE-S-STATE EXIT
    THEN
    R@ _SST-RECORD
    DUP _SST-RECORD-FLAGS@
    DUP SBOX-STORE-F-REMOVED AND IF DROP 2DROP R> DROP SBOX-STORE-S-STATE EXIT THEN
    SBOX-STORE-F-REVOKED AND IF
        DROP SBOX-MODULE-RETIRE DROP R> DROP SBOX-STORE-S-OK EXIT
    THEN
    SBOX-STORE-F-REVOKED OVER _SST-RECORD-FLAGS!
    R@ _SST-WRITE-CATALOG ?DUP IF
        >R 0 SWAP _SST-RECORD-FLAGS! DROP R> R> DROP EXIT
    THEN
    DROP SBOX-MODULE-RETIRE DROP
    R> DROP SBOX-STORE-S-OK ;

\ Drops the grants for (RID, REVISION) from memory, once the catalog no
\ longer holds them.
: _SST-PRUNE-GRANTS  ( rid revision store -- )
    >R
    0 BEGIN DUP R@ _SST.GRANTS 8 + @ < WHILE
        DUP R@ _SST-GRANT
        DUP 32 + 32 5 PICK 32 COMPARE 0=
        SWAP 64 + SBOX-BYTE-U64-LE@ 3 PICK = AND IF
            DUP R@ _SST.GRANTS _SST-GRANT-SIZE _SST-DELETE
        ELSE
            1+
        THEN
    REPEAT
    DROP 2DROP R> DROP ;

\ Forgets an unpinned MODULE: durably removed with its grants, its bytes
\ dropped from the pack, and removed from the owner.  Its handle is then
\ invalid.
: SBOX-STORE-REMOVE  ( module store -- status )
    DUP _SST-OPEN? 0= IF 2DROP SBOX-STORE-S-STATE EXIT THEN
    DUP SBOX-STORE-RECOVERY? IF 2DROP SBOX-STORE-S-RECOVERY EXIT THEN
    OVER SBOX-MODULE-STATE@ 0= IF 2DROP SBOX-STORE-S-INVALID EXIT THEN
    OVER SBOX-MODULE-PINS@ IF 2DROP SBOX-STORE-S-BUSY EXIT THEN
    >R
    DUP SBOX-MODULE-KEY@ R@ _SST-FIND-RECORD 0= IF
        2DROP R> DROP SBOX-STORE-S-STATE EXIT
    THEN
    R@ _SST-RECORD
    DUP _SST-LIVE? 0= IF 2DROP R> DROP SBOX-STORE-S-STATE EXIT THEN
    DUP _SST-RECORD-FLAGS@ SWAP
    OVER SBOX-STORE-F-REMOVED OR OVER _SST-RECORD-FLAGS!
    R@ _SST-WRITE-CATALOG ?DUP IF
        >R _SST-RECORD-FLAGS! DROP R> R> DROP EXIT
    THEN
    2DROP
    DUP SBOX-MODULE-KEY@ R@ _SST-PRUNE-GRANTS
    R@ _SST.OWNER @ SBOX-MODULE-REMOVE DROP
    \ A failed cleanup leaves only objects no record names.
    R@ _SST-WRITE-PACK DROP
    R> DROP SBOX-STORE-S-OK ;

\ Verifies a DECLARED module from its stored artifact, on first use.  A
\ module whose artifact fails ends quarantined; SBOX-MODULE-REASON@ says
\ why.  A read that fails leaves it DECLARED.
: SBOX-STORE-VERIFY  ( module store -- status )
    DUP _SST-OPEN? 0= IF 2DROP SBOX-STORE-S-STATE EXIT THEN
    OVER SBOX-MODULE-STATE@ SBOX-MODULE-DECLARED <> IF
        2DROP SBOX-STORE-S-STATE EXIT
    THEN
    >R
    DUP SBOX-MODULE-KEY@ R@ _SST-FIND-RECORD 0= IF
        2DROP R> DROP SBOX-STORE-S-STATE EXIT
    THEN
    R@ _SST-RECORD _SST-RECORD-ART _SST-K-ARTIFACT SWAP R@ _SST-FIND-OBJECT
    0= IF
        DROP SBOX-MODULE-Q-STORE 0 ROT SBOX-MODULE-QUARANTINE DROP
        SBOX-MODULE-S-MISMATCH R@ _SST.MODULE-STATUS !
        R> DROP SBOX-STORE-S-MODULE EXIT
    THEN
    R@ _SST-ENTRY
    R@ _SST.PACK-REPL VREPL-TARGET$ R@ _SST-OPEN-READ ?DUP IF
        NIP NIP NIP R> DROP EXIT
    THEN
    ?DUP 0= IF 2DROP R> DROP SBOX-STORE-S-IO EXIT THEN
    DUP >R _SST-READ-OBJECT R> _SST-CLOSE
    ?DUP IF NIP NIP NIP R> DROP EXIT THEN
    2DUP 4 PICK R@ _SST.OWNER @ SBOX-MODULE-VERIFY
    DUP R@ _SST.MODULE-STATUS !
    >R _SST-DISCARD DROP R>
    R> DROP
    DUP SBOX-MODULE-S-OK = IF DROP SBOX-STORE-S-OK EXIT THEN
    SBOX-MODULE-S-NOMEM = IF SBOX-STORE-S-NOMEM ELSE SBOX-STORE-S-MODULE THEN ;

\ FLAGS for the module revision the catalog records, or -1.
: SBOX-STORE-RECORD-FLAGS@  ( rid revision store -- flags|-1 )
    DUP _SST-OPEN? 0= IF DROP 2DROP -1 EXIT THEN
    >R R@ _SST-FIND-RECORD IF
        R> _SST-RECORD _SST-RECORD-FLAGS@
    ELSE
        DROP R> DROP -1
    THEN ;

\ =====================================================================
\  Grants
\ =====================================================================

\ The probe for (PRACTICE, GRANTEE, RID, REVISION), checked.
: _SST-PROBE!  ( practice grantee grantee-u rid revision store -- status )
    >R
    DUP 1 < IF 2DROP 2DROP DROP R> DROP SBOX-STORE-S-INVALID EXIT THEN
    OVER RID-SIZE _SST-SPAN? 0= IF
        2DROP 2DROP DROP R> DROP SBOX-STORE-S-INVALID EXIT
    THEN
    OVER RID-PRESENT? 0= IF 2DROP 2DROP DROP R> DROP SBOX-STORE-S-INVALID EXIT THEN
    3 PICK 3 PICK _SST-GRANTEE? 0= IF
        2DROP 2DROP DROP R> DROP SBOX-STORE-S-INVALID EXIT
    THEN
    4 PICK RID-SIZE _SST-SPAN? 0= IF
        2DROP 2DROP DROP R> DROP SBOX-STORE-S-INVALID EXIT
    THEN
    4 PICK RID-PRESENT? 0= IF 2DROP 2DROP DROP R> DROP SBOX-STORE-S-INVALID EXIT THEN
    R@ _SST.PROBE _SST-GRANT-SIZE 0 FILL
    R@ _SST.PROBE 64 + SBOX-BYTE-U64-LE!
    R@ _SST.PROBE 32 + RID-SIZE MOVE
    DUP R@ _SST.PROBE 72 + SBOX-BYTE-U16-LE!
    R@ _SST.PROBE 80 + SWAP MOVE
    R> _SST.PROBE RID-SIZE MOVE
    SBOX-STORE-S-OK ;

: _SST-DROP6>STATUS  ( x1 x2 x3 x4 x5 x6 status -- status ) >R 2DROP 2DROP 2DROP R> ;

\ (RID, REVISION) is installed and not removed.
: _SST-LIVE-RECORD?  ( rid revision store -- flag )
    >R R@ _SST-FIND-RECORD IF R> _SST-RECORD _SST-LIVE? ELSE DROP R> DROP 0 THEN ;

\ Durably lets GRANTEE, a component id, use the module revision (RID,
\ REVISION) in PRACTICE.  Granting again changes nothing.
: SBOX-STORE-GRANT  ( practice grantee grantee-u rid revision store -- status )
    DUP _SST-OPEN? 0= IF SBOX-STORE-S-STATE _SST-DROP6>STATUS EXIT THEN
    DUP SBOX-STORE-RECOVERY? IF SBOX-STORE-S-RECOVERY _SST-DROP6>STATUS EXIT THEN
    >R
    2DUP R@ _SST-LIVE-RECORD? 0= IF
        2DROP 2DROP DROP R> DROP SBOX-STORE-S-STATE EXIT
    THEN
    R@ _SST-PROBE! ?DUP IF R> DROP EXIT THEN
    R@ _SST.PROBE R@ _SST-FIND-GRANT IF DROP R> DROP SBOX-STORE-S-OK EXIT THEN
    R@ _SST.GRANTS _SST-GRANT-SIZE _SST-ROOM ?DUP IF NIP R> DROP EXIT THEN
    DUP R@ _SST.GRANTS _SST-GRANT-SIZE _SST-INSERT
    R@ _SST.PROBE SWAP _SST-GRANT-SIZE MOVE
    R@ _SST-WRITE-CATALOG ?DUP IF
        SWAP R@ _SST.GRANTS _SST-GRANT-SIZE _SST-DELETE R> DROP EXIT
    THEN
    DROP R> DROP SBOX-STORE-S-OK ;

\ Durably withdraws a grant.  Withdrawing one that is not there changes
\ nothing.
: SBOX-STORE-UNGRANT  ( practice grantee grantee-u rid revision store -- status )
    DUP _SST-OPEN? 0= IF SBOX-STORE-S-STATE _SST-DROP6>STATUS EXIT THEN
    DUP SBOX-STORE-RECOVERY? IF SBOX-STORE-S-RECOVERY _SST-DROP6>STATUS EXIT THEN
    >R
    R@ _SST-PROBE! ?DUP IF R> DROP EXIT THEN
    R@ _SST.PROBE R@ _SST-FIND-GRANT 0= IF DROP R> DROP SBOX-STORE-S-OK EXIT THEN
    DUP R@ _SST.GRANTS _SST-GRANT-SIZE _SST-DELETE
    R@ _SST-WRITE-CATALOG ?DUP IF
        \ The probe is the grant, so it goes back as it was.
        SWAP R@ _SST.GRANTS _SST-GRANT-SIZE _SST-INSERT
        R@ _SST.PROBE SWAP _SST-GRANT-SIZE MOVE
        R> DROP EXIT
    THEN
    DROP R> DROP SBOX-STORE-S-OK ;

\ Whether GRANTEE may use the module revision (RID, REVISION) in PRACTICE.
: SBOX-STORE-GRANTED?  ( practice grantee grantee-u rid revision store -- flag )
    DUP _SST-OPEN? 0= IF 0 _SST-DROP6>STATUS EXIT THEN
    >R
    2DUP R@ _SST-LIVE-RECORD? 0= IF 2DROP 2DROP DROP R> DROP 0 EXIT THEN
    R@ _SST-PROBE! IF R> DROP 0 EXIT THEN
    R@ _SST.PROBE R@ _SST-FIND-GRANT NIP R> DROP ;

: SBOX-STORE-GRANT-COUNT@  ( store -- n )
    DUP _SST-OPEN? IF _SST.GRANTS 8 + @ ELSE DROP 0 THEN ;

\ Grant INDEX, in order.
: SBOX-STORE-GRANT@  ( index store -- practice grantee grantee-u rid revision )
    _SST-GRANT >R
    R@ R@ 80 + R@ 72 + SBOX-BYTE-U16-LE@ R@ 32 + R> 64 + SBOX-BYTE-U64-LE@ ;
