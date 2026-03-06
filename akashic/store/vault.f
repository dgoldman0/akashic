\ =================================================================
\  vault.f  —  Content-Addressed Encrypted Vault
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: VAULT-  / _VLT-
\
\  Self-hosted encrypted knowledge base.  Each blob is:
\   1. Content-addressed (SHA3-256 of entire envelope)
\   2. Encrypted at rest (AES-256-GCM, per-blob derived key)
\   3. Integrity-protected (CRC-32C + SHA3-256 + GCM tag)
\   4. Committed to a Merkle tree
\   5. Optionally embedding-indexed (64-dim FP16 cosine search)
\
\  Public API — Lifecycle:
\   VAULT-OPEN       ( key max-blobs arena-bytes -- flag )
\   VAULT-CLOSE      ( -- )
\
\  Public API — Store:
\   VAULT-PUT        ( pt ptlen aad alen -- blob-id )
\   VAULT-PUT-EMB    ( pt ptlen aad alen emb -- blob-id )
\
\  Public API — Retrieve:
\   VAULT-GET        ( blob-id buf buflen -- ptlen flag )
\   VAULT-GET-AAD    ( blob-id buf buflen -- alen )
\   VAULT-GET-EMB    ( blob-id dst -- flag )
\   VAULT-HAS?       ( blob-id -- flag )
\   VAULT-SIZE       ( blob-id -- ptlen )
\
\  Public API — Delete:
\   VAULT-DELETE      ( blob-id -- flag )
\
\  Public API — Integrity:
\   VAULT-CHECK       ( blob-id -- n )
\   VAULT-ROOT        ( -- addr )
\   VAULT-PROVE       ( blob-id proof -- depth )
\   VAULT-VERIFY      ( blob-id proof depth root -- flag )
\
\  Public API — Search:
\   VAULT-SEARCH       ( query k results -- n )
\   VAULT-SEARCH-SCORE ( query k results scores -- n )
\
\  Public API — Compaction:
\   VAULT-COMPACT     ( -- flag )
\   VAULT-SPACE       ( -- bytes )
\   VAULT-FRAG        ( -- dead-bytes )
\
\  Public API — Serialization:
\   VAULT-SAVE-SIZE   ( -- n )
\   VAULT-SAVE        ( buf buflen -- actual )
\   VAULT-LOAD        ( key buf len max-blobs arena-bytes -- flag )
\
\  Public API — Inspection:
\   VAULT-COUNT       ( -- n )
\   VAULT-DUMP        ( -- )
\   VAULT-BLOB.       ( blob-id -- )
\
\  All dynamic structures in XMEM.  Tile scratch in HBW (256 bytes).
\  Not reentrant.
\ =================================================================

REQUIRE ../math/sha3.f
REQUIRE ../math/aes.f
REQUIRE ../math/crc.f
REQUIRE ../math/merkle.f
REQUIRE ../math/random.f
REQUIRE ../math/fp16-ext.f

PROVIDED akashic-vault

\ =====================================================================
\  Constants
\ =====================================================================

0x564C5400 CONSTANT _VLT-MAGIC

 0 CONSTANT _VLT-H-MAGIC
 4 CONSTANT _VLT-H-FLAGS
 8 CONSTANT _VLT-H-IV
20 CONSTANT _VLT-H-ALEN
24 CONSTANT _VLT-H-PTLEN
28 CONSTANT _VLT-H-SIZE

1 CONSTANT _VLT-F-HAS-EMB
2 CONSTANT _VLT-F-TOMBSTONE

16 CONSTANT _VLT-TAG-SZ
12 CONSTANT _VLT-IV-SZ
32 CONSTANT _VLT-HASH-SZ
128 CONSTANT _VLT-EMB-SZ
144 CONSTANT _VLT-EMBCT-SZ

 0 CONSTANT _VLT-S-HASH
32 CONSTANT _VLT-S-OFF
40 CONSTANT _VLT-S-LEN
48 CONSTANT _VLT-S-MKI
56 CONSTANT _VLT-S-FLG
64 CONSTANT _VLT-SLOT-SZ

0 CONSTANT _VLT-OK
1 CONSTANT _VLT-E-NOTFOUND
2 CONSTANT _VLT-E-CRC
3 CONSTANT _VLT-E-SHA3
4 CONSTANT _VLT-E-GCM

56 CONSTANT _VLT-SER-HDR

\ =====================================================================
\  32-bit Little-Endian helpers
\ =====================================================================

: _VLT-L@  ( addr -- u32 )
    DUP C@
    OVER 1 + C@  8 LSHIFT OR
    OVER 2 + C@ 16 LSHIFT OR
    SWAP 3 + C@ 24 LSHIFT OR ;

: _VLT-L!  ( u32 addr -- )
    OVER           OVER     C!
    OVER  8 RSHIFT OVER 1 + C!
    OVER 16 RSHIFT OVER 2 + C!
    SWAP 24 RSHIFT SWAP 3 + C! ;

\ =====================================================================
\  Buffers & Variables
\ =====================================================================

CREATE _VLT-KEY-BUF    32 ALLOT
CREATE _VLT-BLOB-ID    32 ALLOT
CREATE _VLT-DK-BUF     32 ALLOT
CREATE _VLT-EMPTY-HASH 32 ALLOT
CREATE _VLT-KDF-IN     13 ALLOT
CREATE _VLT-EMB-TAG    16 ALLOT
CREATE _VLT-TMP-HASH   32 ALLOT
CREATE _VLT-HDR-BUF    28 ALLOT

VARIABLE _VLT-ARENA   VARIABLE _VLT-PTR    VARIABLE _VLT-CAP
VARIABLE _VLT-COUNT    VARIABLE _VLT-MAX
VARIABLE _VLT-INDEX    VARIABLE _VLT-IDX-CAP
VARIABLE _VLT-MERKLE   VARIABLE _VLT-MK-CAP
VARIABLE _VLT-EMBEDS   VARIABLE _VLT-EMB-CT
VARIABLE _VLT-LEAF-SEQ VARIABLE _VLT-OPEN?

\ Shared temporaries (non-overlapping scopes)
VARIABLE _VT-A  VARIABLE _VT-B  VARIABLE _VT-C
VARIABLE _VT-D  VARIABLE _VT-E

\ =====================================================================
\  HBW tile scratch (256 bytes)
\ =====================================================================

VARIABLE _VLT-QA  VARIABLE _VLT-QB
VARIABLE _VLT-CA  VARIABLE _VLT-CB

: _VLT-INIT-HBW  ( -- )
    64 HBW-ALLOT _VLT-QA !   64 HBW-ALLOT _VLT-QB !
    64 HBW-ALLOT _VLT-CA !   64 HBW-ALLOT _VLT-CB ! ;

_VLT-INIT-HBW

\ =====================================================================
\  Utilities
\ =====================================================================

: _VLT-NEXTPOW2  ( n -- p )
    1 BEGIN 2DUP > WHILE 2* REPEAT NIP ;

: _VLT-BLOB-SIZE  ( alen ptlen flags -- size )
    >R + _VLT-H-SIZE + _VLT-TAG-SZ +
    R> _VLT-F-HAS-EMB AND IF _VLT-EMBCT-SZ + THEN
    4 + ;

: _VLT-AADDR  ( off -- addr )  _VLT-ARENA @ + ;

\ =====================================================================
\  Key Derivation
\ =====================================================================

: _VLT-DERIVE-KEY  ( iv -- )
    _VLT-KEY-BUF 32 ROT _VLT-IV-SZ _VLT-DK-BUF SHA3-256-HMAC ;

: _VLT-DERIVE-EMB-KEY  ( iv -- )
    0x01 _VLT-KDF-IN C!
    _VLT-KDF-IN 1+ _VLT-IV-SZ CMOVE
    _VLT-KEY-BUF 32 _VLT-KDF-IN 13 _VLT-DK-BUF SHA3-256-HMAC ;

: _VLT-ZERO-DK  ( -- )  _VLT-DK-BUF 32 0 FILL ;

\ =====================================================================
\  Embedding helpers  (defined before _VLT-REBUILD which calls them)
\ =====================================================================

: _VLT-NORMALIZE  ( addr -- )
    _VT-A !
    0 _VT-B !
    64 0 DO
        _VT-A @ I 2* + W@  DUP FP16-MUL
        _VT-B @ FP16-ADD _VT-B !
    LOOP
    _VT-B @ FP16-SQRT FP16-RECIP
    64 0 DO
        DUP _VT-A @ I 2* + W@ FP16-MUL
        _VT-A @ I 2* + W!
    LOOP DROP ;

: _VLT-STORE-EMB  ( embsrc dst iv -- )
    _VT-C ! _VT-B ! _VT-A !
    _VT-C @ _VLT-DERIVE-EMB-KEY
    _VLT-DK-BUF _VT-C @ _VT-A @ _VT-B @ _VLT-EMB-SZ AES-GCM-ENCRYPT
    _VT-B @ _VLT-EMB-SZ + AES-GCM-TAG@
    _VLT-ZERO-DK ;

: _VLT-LOAD-EMB  ( blobaddr leaf -- )
    _VT-B ! _VT-A !
    _VT-A @ _VLT-H-ALEN + _VLT-L@
    _VT-A @ _VLT-H-PTLEN + _VLT-L@
    + _VLT-H-SIZE + _VLT-TAG-SZ +
    _VT-A @ + _VT-C !
    _VT-A @ _VLT-H-IV + _VLT-DERIVE-EMB-KEY
    _VLT-DK-BUF
    _VT-A @ _VLT-H-IV +
    _VT-C @
    _VT-B @ _VLT-EMB-SZ * _VLT-EMBEDS @ +
    _VLT-EMB-SZ
    _VT-C @ _VLT-EMB-SZ +
    AES-GCM-DECRYPT DROP
    _VLT-ZERO-DK ;

\ =====================================================================
\  Dot product (scalar, 64-dim FP16)
\ =====================================================================

: _VLT-DOT64  ( addr-a addr-b -- score )
    _VT-B ! _VT-A !
    0 _VT-C !
    64 0 DO
        _VT-A @ I 2* + W@
        _VT-B @ I 2* + W@
        FP16-MUL _VT-C @ FP16-ADD _VT-C !
    LOOP _VT-C @ ;

\ =====================================================================
\  Index Table — open addressing, linear probing
\ =====================================================================

: _VLT-HASH-SLOT  ( blob-id -- slot# )
    @ _VLT-IDX-CAP @ MOD
    DUP 0< IF _VLT-IDX-CAP @ + THEN ;

: _VLT-SLOT  ( slot# -- addr )
    _VLT-SLOT-SZ * _VLT-INDEX @ + ;

: _VLT-SLOT-EMPTY?  ( slot-addr -- flag )
    TRUE 32 0 DO OVER I + C@ IF DROP FALSE LEAVE THEN LOOP NIP ;

: _VLT-SLOT-TOMB?  ( slot-addr -- flag )
    _VLT-S-FLG + @ _VLT-F-TOMBSTONE AND 0<> ;

VARIABLE _VIF-ID  VARIABLE _VIF-SI

: _VLT-IDX-FIND  ( blob-id -- slot-addr | 0 )
    DUP _VIF-ID !
    _VLT-HASH-SLOT _VIF-SI !
    _VLT-IDX-CAP @ 0 DO
        _VIF-SI @ _VLT-SLOT
        DUP _VLT-SLOT-EMPTY? IF DROP 0 UNLOOP EXIT THEN
        DUP _VLT-SLOT-TOMB? IF
            DROP
        ELSE
            DUP _VIF-ID @ SHA3-256-COMPARE IF UNLOOP EXIT THEN
            DROP
        THEN
        _VIF-SI @ 1+ _VLT-IDX-CAP @ MOD _VIF-SI !
    LOOP 0 ;

VARIABLE _VII-OFF  VARIABLE _VII-LEN
VARIABLE _VII-MKI  VARIABLE _VII-FLG  VARIABLE _VII-ID

: _VLT-IDX-INSERT  ( blob-id offset length mki flags -- )
    _VII-FLG ! _VII-MKI ! _VII-LEN ! _VII-OFF !
    DUP _VII-ID !
    _VLT-HASH-SLOT _VIF-SI !
    BEGIN
        _VIF-SI @ _VLT-SLOT
        DUP _VLT-SLOT-EMPTY? IF
            DUP _VII-ID @ SWAP _VLT-HASH-SZ CMOVE
            _VIF-SI @ _VLT-SLOT
            _VII-OFF @ OVER _VLT-S-OFF + !
            _VII-LEN @ OVER _VLT-S-LEN + !
            _VII-MKI @ OVER _VLT-S-MKI + !
            _VII-FLG @ SWAP _VLT-S-FLG + !
            EXIT
        THEN DROP
        _VIF-SI @ 1+ _VLT-IDX-CAP @ MOD _VIF-SI !
    AGAIN ;

\ =====================================================================
\  Rebuild — walk arena, rebuild index + Merkle + embeddings
\ =====================================================================

VARIABLE _VRB-OFF  VARIABLE _VRB-BA  VARIABLE _VRB-BS  VARIABLE _VRB-BF

: _VLT-REBUILD  ( -- )
    _VLT-INDEX @ _VLT-IDX-CAP @ _VLT-SLOT-SZ * 0 FILL
    0 _VLT-COUNT !  0 _VLT-LEAF-SEQ !  0 _VLT-EMB-CT !
    _VLT-MK-CAP @ 0 DO
        _VLT-EMPTY-HASH I _VLT-MERKLE @ MERKLE-LEAF!
    LOOP
    _VLT-EMBEDS @ _VLT-MAX @ _VLT-EMB-SZ * 0 FILL
    0 _VRB-OFF !
    BEGIN _VRB-OFF @ _VLT-PTR @ < WHILE
        _VRB-OFF @ _VLT-AADDR _VRB-BA !
        _VRB-BA @ _VLT-H-ALEN  + _VLT-L@
        _VRB-BA @ _VLT-H-PTLEN + _VLT-L@
        _VRB-BA @ _VLT-H-FLAGS + _VLT-L@
        DUP _VRB-BF !
        _VLT-BLOB-SIZE _VRB-BS !
        _VRB-BF @ _VLT-F-TOMBSTONE AND 0= IF
            _VRB-BA @ _VRB-BS @ _VLT-BLOB-ID SHA3-256-HASH
            _VLT-BLOB-ID _VRB-OFF @ _VRB-BS @ _VLT-LEAF-SEQ @ _VRB-BF @
            _VLT-IDX-INSERT
            _VLT-BLOB-ID _VLT-LEAF-SEQ @ _VLT-MERKLE @ MERKLE-LEAF!
            _VRB-BF @ _VLT-F-HAS-EMB AND IF
                _VRB-BA @ _VLT-LEAF-SEQ @ _VLT-LOAD-EMB
                _VLT-EMB-CT @ 1+ _VLT-EMB-CT !
            THEN
            _VLT-LEAF-SEQ @ 1+ _VLT-LEAF-SEQ !
            _VLT-COUNT @ 1+ _VLT-COUNT !
        THEN
        _VRB-BS @ _VRB-OFF @ + _VRB-OFF !
    REPEAT
    _VLT-MERKLE @ MERKLE-BUILD ;

\ =====================================================================
\  Lifecycle
\ =====================================================================

: VAULT-OPEN  ( key max-blobs arena-bytes -- flag )
    _VLT-CAP ! _VLT-MAX ! _VT-A !
    _VT-A @ _VLT-KEY-BUF 32 CMOVE
    _VLT-MAX @ _VLT-NEXTPOW2 _VLT-MK-CAP !
    _VLT-MAX @ 2* _VLT-IDX-CAP !
    _VLT-CAP @ XMEM-ALLOT _VLT-ARENA !
    _VLT-ARENA @ 0= IF FALSE EXIT THEN
    _VLT-IDX-CAP @ _VLT-SLOT-SZ * XMEM-ALLOT _VLT-INDEX !
    _VLT-INDEX @ 0= IF
        _VLT-ARENA @ _VLT-CAP @ XMEM-FREE-BLOCK FALSE EXIT THEN
    _VLT-INDEX @ _VLT-IDX-CAP @ _VLT-SLOT-SZ * 0 FILL
    _VLT-MK-CAP @ 2* 1- 32 * CELL+ XMEM-ALLOT _VLT-MERKLE !
    _VLT-MERKLE @ 0= IF
        _VLT-INDEX @ _VLT-IDX-CAP @ _VLT-SLOT-SZ * XMEM-FREE-BLOCK
        _VLT-ARENA @ _VLT-CAP @ XMEM-FREE-BLOCK FALSE EXIT THEN
    _VLT-MK-CAP @ _VLT-MERKLE @ !
    _VLT-MAX @ _VLT-EMB-SZ * XMEM-ALLOT _VLT-EMBEDS !
    _VLT-EMBEDS @ 0= IF
        _VLT-MERKLE @ _VLT-MK-CAP @ 2* 1- 32 * CELL+ XMEM-FREE-BLOCK
        _VLT-INDEX @ _VLT-IDX-CAP @ _VLT-SLOT-SZ * XMEM-FREE-BLOCK
        _VLT-ARENA @ _VLT-CAP @ XMEM-FREE-BLOCK FALSE EXIT THEN
    _VLT-EMBEDS @ _VLT-MAX @ _VLT-EMB-SZ * 0 FILL
    S" VAULT-EMPTY" _VLT-EMPTY-HASH SHA3-256-HASH
    _VLT-MK-CAP @ 0 DO
        _VLT-EMPTY-HASH I _VLT-MERKLE @ MERKLE-LEAF!
    LOOP
    _VLT-MERKLE @ MERKLE-BUILD
    0 _VLT-PTR !  0 _VLT-COUNT !  0 _VLT-LEAF-SEQ !  0 _VLT-EMB-CT !
    TRUE _VLT-OPEN? !  TRUE ;

: VAULT-CLOSE  ( -- )
    _VLT-OPEN? @ 0= IF EXIT THEN
    _VLT-KEY-BUF 32 0 FILL   _VLT-DK-BUF 32 0 FILL
    _VLT-EMBEDS @ _VLT-MAX @ _VLT-EMB-SZ * 0 FILL
    _VLT-EMBEDS @ _VLT-MAX @ _VLT-EMB-SZ * XMEM-FREE-BLOCK
    _VLT-MERKLE @ _VLT-MK-CAP @ 2* 1- 32 * CELL+ XMEM-FREE-BLOCK
    _VLT-INDEX @ _VLT-IDX-CAP @ _VLT-SLOT-SZ * XMEM-FREE-BLOCK
    _VLT-ARENA @ _VLT-CAP @ XMEM-FREE-BLOCK
    0 _VLT-ARENA !  0 _VLT-PTR !   0 _VLT-CAP !
    0 _VLT-COUNT !  0 _VLT-MAX !
    0 _VLT-INDEX !  0 _VLT-IDX-CAP !
    0 _VLT-MERKLE ! 0 _VLT-MK-CAP !
    0 _VLT-EMBEDS ! 0 _VLT-EMB-CT !  0 _VLT-LEAF-SEQ !
    FALSE _VLT-OPEN? ! ;

\ =====================================================================
\  VAULT-PUT
\ =====================================================================

VARIABLE _VP-PT   VARIABLE _VP-PTL  VARIABLE _VP-AAD  VARIABLE _VP-AADL
VARIABLE _VP-EMB  VARIABLE _VP-DST  VARIABLE _VP-BLEN VARIABLE _VP-FLAGS
VARIABLE _VP-LEAF VARIABLE _VP-AADTOT

: _VLT-PUT-CORE  ( pt ptlen aad alen embsrc -- blob-id | 0 )
    _VP-EMB ! _VP-AADL ! _VP-AAD ! _VP-PTL ! _VP-PT !
    _VP-EMB @ 0<> IF _VLT-F-HAS-EMB ELSE 0 THEN _VP-FLAGS !
    _VP-AADL @ _VP-PTL @ _VP-FLAGS @ _VLT-BLOB-SIZE _VP-BLEN !
    _VLT-PTR @ _VP-BLEN @ + _VLT-CAP @ > IF 0 EXIT THEN
    _VLT-COUNT @ _VLT-MAX @ >= IF 0 EXIT THEN
    _VLT-PTR @ _VLT-AADDR _VP-DST !
    \ Header
    _VLT-MAGIC _VP-DST @                   _VLT-L!
    _VP-FLAGS @ _VP-DST @ _VLT-H-FLAGS +   _VLT-L!
    _VP-DST @ _VLT-H-IV + _VLT-IV-SZ RNG-BYTES
    _VP-AADL @ _VP-DST @ _VLT-H-ALEN  +   _VLT-L!
    _VP-PTL @  _VP-DST @ _VLT-H-PTLEN +   _VLT-L!
    \ Copy AAD plaintext
    _VP-AAD @ _VP-DST @ _VLT-H-SIZE + _VP-AADL @ CMOVE
    \ Derive key, encrypt payload
    _VP-DST @ _VLT-H-IV + _VLT-DERIVE-KEY
    _VLT-H-SIZE _VP-AADL @ + _VP-AADTOT !
    _VLT-DK-BUF _VP-DST @ _VLT-H-IV + _VP-AADTOT @ _VP-PTL @ 0
    AES-GCM-BEGIN
    _VP-DST @ _VP-AADTOT @ AES-GCM-FEED-AAD
    _VP-PT @ _VP-DST @ _VLT-H-SIZE + _VP-AADL @ + _VP-PTL @
    AES-GCM-FEED-DATA
    AES-GCM-FINISH
    _VP-DST @ _VLT-H-SIZE + _VP-AADL @ + _VP-PTL @ + AES-GCM-TAG@
    _VLT-ZERO-DK
    \ Embedding
    _VP-EMB @ 0<> IF
        _VP-EMB @
        _VP-DST @ _VLT-H-SIZE + _VP-AADL @ + _VP-PTL @ + _VLT-TAG-SZ +
        _VP-DST @ _VLT-H-IV +
        _VLT-STORE-EMB
    THEN
    \ CRC
    _VP-DST @ _VP-BLEN @ 4 - CRC32C
    _VP-DST @ _VP-BLEN @ + 4 - _VLT-L!
    \ Blob ID
    _VP-DST @ _VP-BLEN @ _VLT-BLOB-ID SHA3-256-HASH
    \ Index + Merkle
    _VLT-LEAF-SEQ @ _VP-LEAF !
    _VLT-LEAF-SEQ @ 1+ _VLT-LEAF-SEQ !
    _VLT-BLOB-ID _VLT-PTR @ _VP-BLEN @ _VP-LEAF @ _VP-FLAGS @
    _VLT-IDX-INSERT
    _VLT-BLOB-ID _VP-LEAF @ _VLT-MERKLE @ MERKLE-LEAF!
    _VLT-MERKLE @ MERKLE-BUILD
    \ Search buffer
    _VP-EMB @ 0<> IF
        _VP-EMB @
        _VP-LEAF @ _VLT-EMB-SZ * _VLT-EMBEDS @ +
        _VLT-EMB-SZ CMOVE
        _VP-LEAF @ _VLT-EMB-SZ * _VLT-EMBEDS @ + _VLT-NORMALIZE
        _VLT-EMB-CT @ 1+ _VLT-EMB-CT !
    THEN
    _VP-BLEN @ _VLT-PTR @ + _VLT-PTR !
    _VLT-COUNT @ 1+ _VLT-COUNT !
    _VLT-BLOB-ID ;

: VAULT-PUT  ( pt ptlen aad alen -- blob-id )  0 _VLT-PUT-CORE ;
: VAULT-PUT-EMB  ( pt ptlen aad alen emb -- blob-id )  _VLT-PUT-CORE ;

\ =====================================================================
\  VAULT-GET
\ =====================================================================

VARIABLE _VG-SLOT   VARIABLE _VG-BADDR  VARIABLE _VG-BLEN
VARIABLE _VG-ALEN   VARIABLE _VG-PTLEN  VARIABLE _VG-AADTOT
VARIABLE _VG-BUF    VARIABLE _VG-BUFL

: VAULT-GET  ( blob-id buf buflen -- ptlen flag )
    _VG-BUFL ! _VG-BUF !
    DUP _VLT-IDX-FIND DUP 0= IF 2DROP 0 FALSE EXIT THEN
    DUP _VLT-SLOT-TOMB? IF 2DROP 0 FALSE EXIT THEN
    _VG-SLOT ! DROP
    _VG-SLOT @ _VLT-S-OFF + @ _VLT-AADDR _VG-BADDR !
    _VG-SLOT @ _VLT-S-LEN + @ _VG-BLEN !
    _VG-BADDR @ _VLT-H-ALEN  + _VLT-L@ _VG-ALEN !
    _VG-BADDR @ _VLT-H-PTLEN + _VLT-L@ _VG-PTLEN !
    _VG-PTLEN @ _VG-BUFL @ > IF _VG-PTLEN @ FALSE EXIT THEN
    \ CRC
    _VG-BADDR @ _VG-BLEN @ 4 - CRC32C
    _VG-BADDR @ _VG-BLEN @ + 4 - _VLT-L@
    <> IF _VG-PTLEN @ FALSE EXIT THEN
    \ SHA3
    _VG-BADDR @ _VG-BLEN @ _VLT-TMP-HASH SHA3-256-HASH
    _VG-SLOT @ _VLT-TMP-HASH SHA3-256-COMPARE 0= IF
        _VG-PTLEN @ FALSE EXIT THEN
    \ Decrypt
    _VG-BADDR @ _VLT-H-IV + _VLT-DERIVE-KEY
    _VG-BADDR @ _VLT-H-SIZE + _VG-ALEN @ + _VG-PTLEN @ + AES-TAG!
    _VLT-H-SIZE _VG-ALEN @ + _VG-AADTOT !
    _VLT-DK-BUF _VG-BADDR @ _VLT-H-IV + _VG-AADTOT @ _VG-PTLEN @ 1
    AES-GCM-BEGIN
    _VG-BADDR @ _VG-AADTOT @ AES-GCM-FEED-AAD
    _VG-BADDR @ _VLT-H-SIZE + _VG-ALEN @ + _VG-BUF @ _VG-PTLEN @
    AES-GCM-FEED-DATA
    AES-GCM-FINISH  _VLT-ZERO-DK
    AES-GCM-STATUS 2 = IF _VG-PTLEN @ TRUE
    ELSE _VG-BUF @ _VG-PTLEN @ 0 FILL _VG-PTLEN @ FALSE THEN ;

\ =====================================================================
\  VAULT-GET-AAD
\ =====================================================================

VARIABLE _VGA-SLOT  VARIABLE _VGA-BUF  VARIABLE _VGA-BUFL

: VAULT-GET-AAD  ( blob-id buf buflen -- alen )
    _VGA-BUFL ! _VGA-BUF !
    _VLT-IDX-FIND DUP 0= IF DROP 0 EXIT THEN
    DUP _VLT-SLOT-TOMB? IF DROP 0 EXIT THEN
    _VGA-SLOT !
    _VGA-SLOT @ _VLT-S-OFF + @ _VLT-AADDR
    DUP _VLT-H-ALEN + _VLT-L@
    SWAP _VLT-H-SIZE +
    OVER _VGA-BUFL @ MIN
    _VGA-BUF @ SWAP CMOVE ;

\ =====================================================================
\  VAULT-GET-EMB
\ =====================================================================

VARIABLE _VGE-SLOT  VARIABLE _VGE-DST  VARIABLE _VGE-BA  VARIABLE _VGE-EA

: VAULT-GET-EMB  ( blob-id dst -- flag )
    _VGE-DST !
    _VLT-IDX-FIND DUP 0= IF DROP FALSE EXIT THEN
    DUP _VLT-SLOT-TOMB? IF DROP FALSE EXIT THEN
    _VGE-SLOT !
    _VGE-SLOT @ _VLT-S-FLG + @ _VLT-F-HAS-EMB AND 0= IF FALSE EXIT THEN
    _VGE-SLOT @ _VLT-S-OFF + @ _VLT-AADDR _VGE-BA !
    _VGE-BA @ _VLT-H-ALEN + _VLT-L@
    _VGE-BA @ _VLT-H-PTLEN + _VLT-L@
    + _VLT-H-SIZE + _VLT-TAG-SZ +
    _VGE-BA @ + _VGE-EA !
    _VGE-BA @ _VLT-H-IV + _VLT-DERIVE-EMB-KEY
    _VLT-DK-BUF _VGE-BA @ _VLT-H-IV +
    _VGE-EA @ _VGE-DST @ _VLT-EMB-SZ _VGE-EA @ _VLT-EMB-SZ +
    AES-GCM-DECRYPT  _VLT-ZERO-DK ;

\ =====================================================================
\  VAULT-HAS? / VAULT-SIZE
\ =====================================================================

: VAULT-HAS?  ( blob-id -- flag )
    _VLT-IDX-FIND DUP 0= IF DROP FALSE EXIT THEN
    _VLT-SLOT-TOMB? 0= ;

: VAULT-SIZE  ( blob-id -- ptlen )
    _VLT-IDX-FIND DUP 0= IF DROP 0 EXIT THEN
    DUP _VLT-SLOT-TOMB? IF DROP 0 EXIT THEN
    _VLT-S-OFF + @ _VLT-AADDR _VLT-H-PTLEN + _VLT-L@ ;

\ =====================================================================
\  VAULT-DELETE
\ =====================================================================

VARIABLE _VDL-SLOT

: VAULT-DELETE  ( blob-id -- flag )
    _VLT-IDX-FIND DUP 0= IF DROP FALSE EXIT THEN
    DUP _VLT-SLOT-TOMB? IF DROP FALSE EXIT THEN
    _VDL-SLOT !
    _VDL-SLOT @ _VLT-S-OFF + @ _VLT-AADDR
    DUP _VLT-H-FLAGS + _VLT-L@ _VLT-F-TOMBSTONE OR
    SWAP _VLT-H-FLAGS + _VLT-L!
    _VDL-SLOT @ _VLT-S-FLG + @ _VLT-F-TOMBSTONE OR
    _VDL-SLOT @ _VLT-S-FLG + !
    _VLT-EMPTY-HASH _VDL-SLOT @ _VLT-S-MKI + @ _VLT-MERKLE @ MERKLE-LEAF!
    _VLT-MERKLE @ MERKLE-BUILD
    _VDL-SLOT @ _VLT-S-MKI + @ _VLT-EMB-SZ *
    _VLT-EMBEDS @ + _VLT-EMB-SZ 0 FILL
    _VLT-COUNT @ 1- _VLT-COUNT ! TRUE ;

\ =====================================================================
\  VAULT-CHECK — full integrity (CRC + SHA3 + GCM)
\ =====================================================================

VARIABLE _VC-SLOT  VARIABLE _VC-BA  VARIABLE _VC-BLEN
VARIABLE _VC-ALEN  VARIABLE _VC-PTLEN  VARIABLE _VC-AADTOT
CREATE _VC-DEVNULL 256 ALLOT

: VAULT-CHECK  ( blob-id -- n )
    DUP _VLT-IDX-FIND DUP 0= IF 2DROP _VLT-E-NOTFOUND EXIT THEN
    DUP _VLT-SLOT-TOMB? IF 2DROP _VLT-E-NOTFOUND EXIT THEN
    _VC-SLOT !
    _VC-SLOT @ _VLT-S-OFF + @ _VLT-AADDR _VC-BA !
    _VC-SLOT @ _VLT-S-LEN + @ _VC-BLEN !
    _VC-BA @ _VLT-H-ALEN + _VLT-L@ _VC-ALEN !
    _VC-BA @ _VLT-H-PTLEN + _VLT-L@ _VC-PTLEN !
    \ CRC
    _VC-BA @ _VC-BLEN @ 4 - CRC32C
    _VC-BA @ _VC-BLEN @ + 4 - _VLT-L@
    <> IF DROP _VLT-E-CRC EXIT THEN
    \ SHA3
    _VC-BA @ _VC-BLEN @ _VLT-TMP-HASH SHA3-256-HASH
    DUP _VLT-TMP-HASH SHA3-256-COMPARE 0= IF DROP _VLT-E-SHA3 EXIT THEN
    DROP
    \ GCM auth check (decrypt to devnull in 256-byte chunks)
    _VC-BA @ _VLT-H-IV + _VLT-DERIVE-KEY
    _VC-BA @ _VLT-H-SIZE + _VC-ALEN @ + _VC-PTLEN @ + AES-TAG!
    _VLT-H-SIZE _VC-ALEN @ + _VC-AADTOT !
    _VLT-DK-BUF _VC-BA @ _VLT-H-IV + _VC-AADTOT @ _VC-PTLEN @ 1
    AES-GCM-BEGIN
    _VC-BA @ _VC-AADTOT @ AES-GCM-FEED-AAD
    _VC-PTLEN @ _VT-A !
    _VC-BA @ _VLT-H-SIZE + _VC-ALEN @ + _VT-B !
    BEGIN _VT-A @ 0> WHILE
        _VT-A @ 256 MIN _VT-C !
        _VT-B @ _VC-DEVNULL _VT-C @ AES-GCM-FEED-DATA
        _VT-C @ _VT-B @ + _VT-B !
        _VT-A @ _VT-C @ - _VT-A !
    REPEAT
    AES-GCM-FINISH  _VLT-ZERO-DK
    AES-GCM-STATUS 2 = IF _VLT-OK ELSE _VLT-E-GCM THEN ;

\ =====================================================================
\  Merkle wiring
\ =====================================================================

: VAULT-ROOT  ( -- addr )  _VLT-MERKLE @ MERKLE-ROOT ;

VARIABLE _VPR-SLOT

: VAULT-PROVE  ( blob-id proof -- depth )
    SWAP _VLT-IDX-FIND DUP 0= IF DROP DROP 0 EXIT THEN
    _VPR-SLOT !
    _VPR-SLOT @ _VLT-S-MKI + @
    _VLT-MERKLE @ ROT MERKLE-OPEN ;

VARIABLE _VV-ID  VARIABLE _VV-PROOF  VARIABLE _VV-DEPTH  VARIABLE _VV-ROOT

: VAULT-VERIFY  ( blob-id proof depth root -- flag )
    _VV-ROOT ! _VV-DEPTH ! _VV-PROOF !
    DUP _VV-ID !
    _VLT-IDX-FIND DUP 0= IF DROP FALSE EXIT THEN
    _VLT-S-MKI + @
    _VV-ID @ SWAP
    _VV-PROOF @ _VV-DEPTH @ _VV-ROOT @ MERKLE-VERIFY ;

\ =====================================================================
\  Search
\ =====================================================================

VARIABLE _VS-K  VARIABLE _VS-RES  VARIABLE _VS-SCR  VARIABLE _VS-N
VARIABLE _VS-QUERY
VARIABLE _VSM-MIN  VARIABLE _VSM-IDX
VARIABLE _VSS-LEAF  VARIABLE _VSS-SCORE  VARIABLE _VSS-EA

: _VLT-MIN-IDX  ( -- idx )
    _VS-SCR @ W@ _VSM-MIN !  0 _VSM-IDX !
    _VS-N @ 1 DO
        _VS-SCR @ I 2* + W@
        DUP _VSM-MIN @ FP16-LT IF
            _VSM-MIN ! I _VSM-IDX !
        ELSE DROP THEN
    LOOP _VSM-IDX @ ;

CREATE _VSS-TMP-SCORES 40 ALLOT

: _VLT-SEARCH-CORE  ( query k results scores -- n )
    _VS-SCR ! _VS-RES ! _VS-K ! _VS-QUERY !
    0 _VS-N !
    _VS-SCR @ 0<> IF
        _VS-K @ 0 DO 0 _VS-SCR @ I 2* + W! LOOP THEN
    _VS-K @ 0 DO -1 _VS-RES @ I CELLS + ! LOOP
    _VLT-LEAF-SEQ @ 0 DO
        I _VSS-LEAF !
        I _VLT-EMB-SZ * _VLT-EMBEDS @ + _VSS-EA !
        \ Skip empty rows: check first + last cell
        _VSS-EA @ @ _VSS-EA @ 120 + @ OR 0= IF
        ELSE
            _VS-QUERY @ _VSS-EA @ _VLT-DOT64 _VSS-SCORE !
            _VS-N @ _VS-K @ < IF
                _VSS-LEAF @ _VS-RES @ _VS-N @ CELLS + !
                _VS-SCR @ 0<> IF
                    _VSS-SCORE @ _VS-SCR @ _VS-N @ 2* + W!
                THEN
                _VS-N @ 1+ _VS-N !
            ELSE
                _VS-SCR @ 0<> IF
                    _VLT-MIN-IDX _VT-A !
                    _VSS-SCORE @ _VS-SCR @ _VT-A @ 2* + W@
                    FP16-GT IF
                        _VSS-LEAF @ _VS-RES @ _VT-A @ CELLS + !
                        _VSS-SCORE @ _VS-SCR @ _VT-A @ 2* + W!
                    THEN
                THEN
            THEN
        THEN
    LOOP _VS-N @ ;

: VAULT-SEARCH  ( query k results -- n )
    _VSS-TMP-SCORES _VLT-SEARCH-CORE ;
: VAULT-SEARCH-SCORE  ( query k results scores -- n )
    _VLT-SEARCH-CORE ;

\ =====================================================================
\  Compaction
\ =====================================================================

VARIABLE _VCC-NB  VARIABLE _VCC-NP  VARIABLE _VCC-OO
VARIABLE _VCC-BA  VARIABLE _VCC-BS

: VAULT-COMPACT  ( -- flag )
    _VLT-CAP @ XMEM-ALLOT DUP 0= IF DROP FALSE EXIT THEN
    _VCC-NB !  0 _VCC-NP !  0 _VCC-OO !
    BEGIN _VCC-OO @ _VLT-PTR @ < WHILE
        _VCC-OO @ _VLT-AADDR _VCC-BA !
        _VCC-BA @ _VLT-H-ALEN + _VLT-L@
        _VCC-BA @ _VLT-H-PTLEN + _VLT-L@
        _VCC-BA @ _VLT-H-FLAGS + _VLT-L@
        _VLT-BLOB-SIZE _VCC-BS !
        _VCC-BA @ _VLT-H-FLAGS + _VLT-L@ _VLT-F-TOMBSTONE AND 0= IF
            _VCC-BA @ _VCC-NB @ _VCC-NP @ + _VCC-BS @ CMOVE
            _VCC-NP @ _VCC-BS @ + _VCC-NP !
        THEN
        _VCC-OO @ _VCC-BS @ + _VCC-OO !
    REPEAT
    _VLT-ARENA @ _VLT-CAP @ XMEM-FREE-BLOCK
    _VCC-NB @ _VLT-ARENA !
    _VCC-NP @ _VLT-PTR !
    _VLT-REBUILD TRUE ;

: VAULT-SPACE  ( -- bytes )  _VLT-CAP @ _VLT-PTR @ - ;

VARIABLE _VFR-OFF  VARIABLE _VFR-BA  VARIABLE _VFR-BS  VARIABLE _VFR-TOT

: VAULT-FRAG  ( -- dead-bytes )
    0 _VFR-TOT !  0 _VFR-OFF !
    BEGIN _VFR-OFF @ _VLT-PTR @ < WHILE
        _VFR-OFF @ _VLT-AADDR _VFR-BA !
        _VFR-BA @ _VLT-H-ALEN + _VLT-L@
        _VFR-BA @ _VLT-H-PTLEN + _VLT-L@
        _VFR-BA @ _VLT-H-FLAGS + _VLT-L@
        DUP >R _VLT-BLOB-SIZE _VFR-BS !
        R> _VLT-F-TOMBSTONE AND IF
            _VFR-BS @ _VFR-TOT @ + _VFR-TOT !
        THEN
        _VFR-BS @ _VFR-OFF @ + _VFR-OFF !
    REPEAT _VFR-TOT @ ;

\ =====================================================================
\  Serialization
\ =====================================================================

: VAULT-SAVE-SIZE  ( -- n )  _VLT-SER-HDR _VLT-PTR @ + ;

VARIABLE _VSV-BUF  VARIABLE _VSV-BUFL

: VAULT-SAVE  ( buf buflen -- actual )
    _VSV-BUFL ! _VSV-BUF !
    VAULT-SAVE-SIZE DUP _VSV-BUFL @ > IF DROP 0 EXIT THEN
    0x41 _VSV-BUF @ 0 + C!   0x4B _VSV-BUF @ 1 + C!
    0x41 _VSV-BUF @ 2 + C!   0x53 _VSV-BUF @ 3 + C!
    0x48 _VSV-BUF @ 4 + C!   0x56 _VSV-BUF @ 5 + C!
    0x4C _VSV-BUF @ 6 + C!   0x54 _VSV-BUF @ 7 + C!
    1 _VSV-BUF @ 8 + _VLT-L!
    _VLT-MAX @ _VSV-BUF @ 12 + _VLT-L!
    _VLT-PTR @ _VSV-BUF @ 16 + !
    _VLT-KEY-BUF 32 _VSV-BUF @ 24 + SHA3-256-HASH
    _VLT-ARENA @ _VSV-BUF @ _VLT-SER-HDR + _VLT-PTR @ CMOVE ;

\ =====================================================================
\  VAULT-LOAD
\ =====================================================================

VARIABLE _VLD-KEY  VARIABLE _VLD-BUF  VARIABLE _VLD-LEN
VARIABLE _VLD-MAX  VARIABLE _VLD-ARENA  VARIABLE _VLD-ULEN

: VAULT-LOAD  ( key buf len max-blobs arena-bytes -- flag )
    _VLD-ARENA ! _VLD-MAX ! _VLD-LEN ! _VLD-BUF ! _VLD-KEY !
    _VLD-LEN @ _VLT-SER-HDR < IF FALSE EXIT THEN
    _VLD-BUF @ C@       0x41 <> IF FALSE EXIT THEN
    _VLD-BUF @ 1 + C@   0x4B <> IF FALSE EXIT THEN
    _VLD-BUF @ 2 + C@   0x41 <> IF FALSE EXIT THEN
    _VLD-BUF @ 3 + C@   0x53 <> IF FALSE EXIT THEN
    _VLD-BUF @ 4 + C@   0x48 <> IF FALSE EXIT THEN
    _VLD-BUF @ 5 + C@   0x56 <> IF FALSE EXIT THEN
    _VLD-BUF @ 6 + C@   0x4C <> IF FALSE EXIT THEN
    _VLD-BUF @ 7 + C@   0x54 <> IF FALSE EXIT THEN
    _VLD-KEY @ 32 _VLT-TMP-HASH SHA3-256-HASH
    _VLT-TMP-HASH _VLD-BUF @ 24 + SHA3-256-COMPARE 0= IF FALSE EXIT THEN
    _VLD-BUF @ 16 + @ _VLD-ULEN !
    _VLD-KEY @ _VLD-MAX @ _VLD-ARENA @ VAULT-OPEN 0= IF FALSE EXIT THEN
    _VLD-BUF @ _VLT-SER-HDR + _VLT-ARENA @ _VLD-ULEN @ CMOVE
    _VLD-ULEN @ _VLT-PTR !
    _VLT-REBUILD TRUE ;

\ =====================================================================
\  Inspection
\ =====================================================================

: VAULT-COUNT  ( -- n )  _VLT-COUNT @ ;

: VAULT-DUMP  ( -- )
    ." VAULT: " _VLT-COUNT @ . ." blobs, "
    _VLT-PTR @ . ." / " _VLT-CAP @ . ." bytes used" CR
    ." Root: " VAULT-ROOT SHA3-256-. CR ;

: VAULT-BLOB.  ( blob-id -- )
    DUP _VLT-IDX-FIND DUP 0= IF 2DROP ." (not found)" CR EXIT THEN
    >R
    ." ID: " DUP SHA3-256-. CR
    ." Off: " R@ _VLT-S-OFF + @ . CR
    ." Len: " R@ _VLT-S-LEN + @ . CR
    ." Lf:  " R@ _VLT-S-MKI + @ . CR
    ." Flg: " R@ _VLT-S-FLG + @ . CR
    R@ _VLT-S-OFF + @ _VLT-AADDR
    ." AAD: " DUP _VLT-H-ALEN + _VLT-L@ . CR
    ." PT:  " DUP _VLT-H-PTLEN + _VLT-L@ . CR
    DROP R> DROP DROP ;

\ ── Concurrency Guard ─────────────────────────────────────
\ VAULT-OPEN / VAULT-LOAD acquire the guard.
\ VAULT-CLOSE releases it.
\ All other ops assert the guard is held (fail-loud with -258).
REQUIRE ../concurrency/guard.f
GUARD _vlt-guard

: _VLT-CHK  _vlt-guard GUARD-MINE? 0= IF -258 THROW THEN ;

' VAULT-OPEN         CONSTANT _vlt-open-xt
' VAULT-LOAD         CONSTANT _vlt-load-xt
' VAULT-CLOSE        CONSTANT _vlt-close-xt
' VAULT-PUT          CONSTANT _vlt-put-xt
' VAULT-PUT-EMB      CONSTANT _vlt-putemb-xt
' VAULT-GET          CONSTANT _vlt-get-xt
' VAULT-GET-AAD      CONSTANT _vlt-getaad-xt
' VAULT-GET-EMB      CONSTANT _vlt-getemb-xt
' VAULT-HAS?         CONSTANT _vlt-has-xt
' VAULT-SIZE         CONSTANT _vlt-size-xt
' VAULT-DELETE       CONSTANT _vlt-del-xt
' VAULT-CHECK        CONSTANT _vlt-chk2-xt
' VAULT-ROOT         CONSTANT _vlt-root-xt
' VAULT-PROVE        CONSTANT _vlt-prove-xt
' VAULT-VERIFY       CONSTANT _vlt-vfy-xt
' VAULT-SEARCH       CONSTANT _vlt-search-xt
' VAULT-SEARCH-SCORE CONSTANT _vlt-sscore-xt
' VAULT-COMPACT      CONSTANT _vlt-compact-xt
' VAULT-SPACE        CONSTANT _vlt-space-xt
' VAULT-FRAG         CONSTANT _vlt-frag-xt
' VAULT-SAVE-SIZE    CONSTANT _vlt-savsz-xt
' VAULT-SAVE         CONSTANT _vlt-save-xt
' VAULT-COUNT        CONSTANT _vlt-count-xt
' VAULT-DUMP         CONSTANT _vlt-dump-xt
' VAULT-BLOB.        CONSTANT _vlt-blob-xt

\ session open (acquire guard)
: VAULT-OPEN  ( key max-blobs arena-bytes -- flag )
    _vlt-guard GUARD-ACQUIRE
    _vlt-open-xt CATCH
    ?DUP IF _vlt-guard GUARD-RELEASE THROW THEN ;

: VAULT-LOAD  ( key buf len max-blobs arena-bytes -- flag )
    _vlt-guard GUARD-ACQUIRE
    _vlt-load-xt CATCH
    ?DUP IF _vlt-guard GUARD-RELEASE THROW THEN ;

\ session close (release guard, always)
: VAULT-CLOSE  ( -- )
    _VLT-CHK
    _vlt-close-xt CATCH
    _vlt-guard GUARD-RELEASE
    ?DUP IF THROW THEN ;

\ all remaining ops — assert guard held
: VAULT-PUT          _VLT-CHK _vlt-put-xt     EXECUTE ;
: VAULT-PUT-EMB      _VLT-CHK _vlt-putemb-xt  EXECUTE ;
: VAULT-GET          _VLT-CHK _vlt-get-xt     EXECUTE ;
: VAULT-GET-AAD      _VLT-CHK _vlt-getaad-xt  EXECUTE ;
: VAULT-GET-EMB      _VLT-CHK _vlt-getemb-xt  EXECUTE ;
: VAULT-HAS?         _VLT-CHK _vlt-has-xt     EXECUTE ;
: VAULT-SIZE         _VLT-CHK _vlt-size-xt    EXECUTE ;
: VAULT-DELETE       _VLT-CHK _vlt-del-xt     EXECUTE ;
: VAULT-CHECK        _VLT-CHK _vlt-chk2-xt    EXECUTE ;
: VAULT-ROOT         _VLT-CHK _vlt-root-xt    EXECUTE ;
: VAULT-PROVE        _VLT-CHK _vlt-prove-xt   EXECUTE ;
: VAULT-VERIFY       _VLT-CHK _vlt-vfy-xt     EXECUTE ;
: VAULT-SEARCH       _VLT-CHK _vlt-search-xt  EXECUTE ;
: VAULT-SEARCH-SCORE _VLT-CHK _vlt-sscore-xt  EXECUTE ;
: VAULT-COMPACT      _VLT-CHK _vlt-compact-xt EXECUTE ;
: VAULT-SPACE        _VLT-CHK _vlt-space-xt   EXECUTE ;
: VAULT-FRAG         _VLT-CHK _vlt-frag-xt    EXECUTE ;
: VAULT-SAVE-SIZE    _VLT-CHK _vlt-savsz-xt   EXECUTE ;
: VAULT-SAVE         _VLT-CHK _vlt-save-xt    EXECUTE ;
: VAULT-COUNT        _VLT-CHK _vlt-count-xt   EXECUTE ;
: VAULT-DUMP         _VLT-CHK _vlt-dump-xt    EXECUTE ;
: VAULT-BLOB.        _VLT-CHK _vlt-blob-xt    EXECUTE ;