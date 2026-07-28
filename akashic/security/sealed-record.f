\ =====================================================================
\  sealed-record.f - Generic authenticated sealing for durable secrets
\ =====================================================================
\  This module turns one caller-owned secret byte string into one exact,
\  versioned record.  It owns no key, filesystem, OAuth, AT Protocol, or
\  application policy.  A caller-supplied resolver lends the selected
\  32-byte root key only to a synchronous one-shot consumer.
\
\  Every seal receives a fresh 32-byte salt from ENTROPY-FILL.  RFC 5869
\  HKDF-SHA-256 derives one AES-256 key and one 96-bit IV.  The Megapad
\  AES-GCM engine authenticates the complete canonical header and encrypts
\  the secret.  The full record is staged in the caller workspace before
\  publication; an existing destination magic is invalidated first and the
\  new magic is written last.
\
\  OPEN checks the exact record shape and all caller-expected identity
\  fields before resolving a key.  AES-GCM authenticates into private staging
\  and plaintext is copied to the caller only after successful verification.
\  The complete workspace is wiped on every admitted returned path.
\
\  Resolver contract:
\    ( key-id 32 consumer-xt consumer-context resolver-context -- status )
\
\  The resolver either returns SEALED-RECORD-S-KEY without calling the
\  consumer, or calls the consumer exactly once as:
\    ( root-key 32 consumer-context -- status )
\  and faithfully returns that status.  The root key is borrowed for that
\  callback only.  It is never retained or persisted by this module.
\ =====================================================================

PROVIDED akashic-sealed-record

REQUIRE ../math/aes.f
REQUIRE ../math/hmac-sha256.f
REQUIRE ../math/entropy.f
REQUIRE ../utils/memory-span.f
REQUIRE ../utils/caller-span.f

\ =====================================================================
\  Public constants and status vocabulary
\ =====================================================================

0  CONSTANT SEALED-RECORD-S-OK
1  CONSTANT SEALED-RECORD-S-INVALID
2  CONSTANT SEALED-RECORD-S-CAPACITY
3  CONSTANT SEALED-RECORD-S-ALIAS
4  CONSTANT SEALED-RECORD-S-BUSY
5  CONSTANT SEALED-RECORD-S-KEY
6  CONSTANT SEALED-RECORD-S-CALLBACK
7  CONSTANT SEALED-RECORD-S-ENTROPY
8  CONSTANT SEALED-RECORD-S-CRYPTO
9  CONSTANT SEALED-RECORD-S-AUTH
10 CONSTANT SEALED-RECORD-S-FORMAT
11 CONSTANT SEALED-RECORD-S-MISMATCH
12 CONSTANT SEALED-RECORD-S-RANGE
13 CONSTANT SEALED-RECORD-S-PROTECTED
14 CONSTANT SEALED-RECORD-S-PLATFORM
15 CONSTANT SEALED-RECORD-S-INTERNAL

: SEALED-RECORD-STATUS-VALID?  ( status -- flag )
    DUP SEALED-RECORD-S-OK >=
    SWAP SEALED-RECORD-S-INTERNAL <= AND ;

32    CONSTANT SEALED-RECORD-ID-SIZE
32    CONSTANT SEALED-RECORD-ROOT-KEY-SIZE
32    CONSTANT SEALED-RECORD-SALT-SIZE
160   CONSTANT SEALED-RECORD-HEADER-SIZE
16    CONSTANT SEALED-RECORD-TAG-SIZE
176   CONSTANT SEALED-RECORD-OVERHEAD
65536 CONSTANT SEALED-RECORD-DATA-MAX
65712 CONSTANT SEALED-RECORD-SIZE-MAX

: SEALED-RECORD-SIZE  ( data-u -- record-u|0 )
    DUP 0> 0= IF DROP 0 EXIT THEN
    DUP SEALED-RECORD-DATA-MAX > IF DROP 0 EXIT THEN
    SEALED-RECORD-OVERHEAD + ;

\ =====================================================================
\  Caller-owned operation descriptor
\ =====================================================================

 0 CONSTANT _SR-D-INPUT
 8 CONSTANT _SR-D-INPUT-U
16 CONSTANT _SR-D-KEY-ID
24 CONSTANT _SR-D-RECORD-ID
32 CONSTANT _SR-D-PURPOSE
40 CONSTANT _SR-D-REVISION
48 CONSTANT _SR-D-RESOLVER-XT
56 CONSTANT _SR-D-RESOLVER-CONTEXT
64 CONSTANT _SR-D-OUTPUT
72 CONSTANT _SR-D-OUTPUT-CAP
80 CONSTANT SEALED-RECORD-DESCRIPTOR-SIZE

: SEALED-RECORD-D.INPUT
  ( descriptor -- field ) _SR-D-INPUT + ;
: SEALED-RECORD-D.INPUT-U
  ( descriptor -- field ) _SR-D-INPUT-U + ;
: SEALED-RECORD-D.KEY-ID
  ( descriptor -- field ) _SR-D-KEY-ID + ;
: SEALED-RECORD-D.RECORD-ID
  ( descriptor -- field ) _SR-D-RECORD-ID + ;
: SEALED-RECORD-D.PURPOSE
  ( descriptor -- field ) _SR-D-PURPOSE + ;
: SEALED-RECORD-D.REVISION
  ( descriptor -- field ) _SR-D-REVISION + ;
: SEALED-RECORD-D.RESOLVER-XT
  ( descriptor -- field ) _SR-D-RESOLVER-XT + ;
: SEALED-RECORD-D.RESOLVER-CONTEXT
  ( descriptor -- field ) _SR-D-RESOLVER-CONTEXT + ;
: SEALED-RECORD-D.OUTPUT
  ( descriptor -- field ) _SR-D-OUTPUT + ;
: SEALED-RECORD-D.OUTPUT-CAP
  ( descriptor -- field ) _SR-D-OUTPUT-CAP + ;

\ =====================================================================
\  Canonical record header
\ =====================================================================

0x414B535345414C31 CONSTANT _SR-MAGIC  \ "AKSSEAL1", big endian
1                   CONSTANT _SR-VERSION

  0 CONSTANT _SR-H-MAGIC
  8 CONSTANT _SR-H-VERSION
 16 CONSTANT _SR-H-HEADER-U
 24 CONSTANT _SR-H-TOTAL-U
 32 CONSTANT _SR-H-DATA-U
 40 CONSTANT _SR-H-PURPOSE
 48 CONSTANT _SR-H-REVISION
 56 CONSTANT _SR-H-FLAGS
 64 CONSTANT _SR-H-KEY-ID
 96 CONSTANT _SR-H-RECORD-ID
128 CONSTANT _SR-H-SALT

\ All numeric fields are unsigned, positive where stated, and canonical
\ big-endian.  OPEN rejects the high bit before converting to a Forth cell.
: _SR-BE64!  ( nonnegative-u destination -- )
    >R
    DUP 56 RSHIFT 255 AND R@      C!
    DUP 48 RSHIFT 255 AND R@ 1+   C!
    DUP 40 RSHIFT 255 AND R@ 2 +  C!
    DUP 32 RSHIFT 255 AND R@ 3 +  C!
    DUP 24 RSHIFT 255 AND R@ 4 +  C!
    DUP 16 RSHIFT 255 AND R@ 5 +  C!
    DUP  8 RSHIFT 255 AND R@ 6 +  C!
        255 AND R@ 7 + C!
    R> DROP ;

: _SR-BE64@  ( source -- nonnegative-u )
    >R
    R@     C@ 56 LSHIFT
    R@ 1+  C@ 48 LSHIFT OR
    R@ 2 + C@ 40 LSHIFT OR
    R@ 3 + C@ 32 LSHIFT OR
    R@ 4 + C@ 24 LSHIFT OR
    R@ 5 + C@ 16 LSHIFT OR
    R@ 6 + C@  8 LSHIFT OR
    R> 7 + C@ OR ;

: _SR-BE64-NONNEGATIVE?  ( source -- flag )
    C@ 0x80 AND 0= ;

: _SR-NONZERO-SPAN?  ( address length -- flag )
    BEGIN
        DUP
    WHILE
        OVER C@ IF 2DROP -1 EXIT THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP 0 ;

: _SR-ID=  ( first second -- flag )
    SWAP SEALED-RECORD-ID-SIZE
    ROT SEALED-RECORD-ID-SIZE COMPARE 0= ;

\ =====================================================================
\  Caller-owned workspace
\ =====================================================================

\ The first 128 bytes snapshot every borrowed descriptor value before a
\ resolver is invoked.  The canonical header, staged data, and tag are
\ contiguous, so SEAL can publish one exact record after crypto succeeds.

  0 CONSTANT _SR-W-DESCRIPTOR
  8 CONSTANT _SR-W-INPUT
 16 CONSTANT _SR-W-INPUT-U
 24 CONSTANT _SR-W-KEY-ID
 32 CONSTANT _SR-W-RECORD-ID
 40 CONSTANT _SR-W-PURPOSE
 48 CONSTANT _SR-W-REVISION
 56 CONSTANT _SR-W-RESOLVER-XT
 64 CONSTANT _SR-W-RESOLVER-CONTEXT
 72 CONSTANT _SR-W-OUTPUT
 80 CONSTANT _SR-W-OUTPUT-CAP
 88 CONSTANT _SR-W-DATA-U
 96 CONSTANT _SR-W-TOTAL-U
104 CONSTANT _SR-W-RESOLVER-CALLS
112 CONSTANT _SR-W-CONSUMER-STATUS
120 CONSTANT _SR-W-OPERATION
128 CONSTANT _SR-W-RESOLVER-DEPTH
136 CONSTANT _SR-W-RESERVED
144 CONSTANT _SR-W-HEADER

_SR-W-HEADER SEALED-RECORD-HEADER-SIZE +
    CONSTANT _SR-W-DATA
_SR-W-DATA SEALED-RECORD-DATA-MAX +
SEALED-RECORD-TAG-SIZE +
    CONSTANT _SR-W-PRK
_SR-W-PRK HMAC-SHA256-DIGEST-SIZE +
    CONSTANT _SR-W-KEY
_SR-W-KEY AES-GCM-KEY256-SIZE +
    CONSTANT _SR-W-IV-DIGEST
_SR-W-IV-DIGEST HMAC-SHA256-DIGEST-SIZE +
    CONSTANT _SR-W-KDF-MESSAGE
96 _SR-W-KDF-MESSAGE +
    CONSTANT _SR-W-HMAC
_SR-W-HMAC HMAC-SHA256-WORKSPACE-SIZE +
    CONSTANT _SR-W-AES-DESCRIPTOR
_SR-W-AES-DESCRIPTOR AES-GCM-DESCRIPTOR-SIZE +
    CONSTANT _SR-W-AES-WORKSPACE
_SR-W-AES-WORKSPACE AES-GCM-WORKSPACE-SIZE +
    CONSTANT SEALED-RECORD-WORKSPACE-SIZE

0 CONSTANT _SR-OP-SEAL
1 CONSTANT _SR-OP-OPEN
0x5352425553593031 CONSTANT _SR-WORKSPACE-BUSY

: _SRW.DESCRIPTOR       ( w -- a ) _SR-W-DESCRIPTOR + ;
: _SRW.INPUT            ( w -- a ) _SR-W-INPUT + ;
: _SRW.INPUT-U          ( w -- a ) _SR-W-INPUT-U + ;
: _SRW.KEY-ID           ( w -- a ) _SR-W-KEY-ID + ;
: _SRW.RECORD-ID        ( w -- a ) _SR-W-RECORD-ID + ;
: _SRW.PURPOSE          ( w -- a ) _SR-W-PURPOSE + ;
: _SRW.REVISION         ( w -- a ) _SR-W-REVISION + ;
: _SRW.RESOLVER-XT      ( w -- a ) _SR-W-RESOLVER-XT + ;
: _SRW.RESOLVER-CONTEXT ( w -- a ) _SR-W-RESOLVER-CONTEXT + ;
: _SRW.OUTPUT           ( w -- a ) _SR-W-OUTPUT + ;
: _SRW.OUTPUT-CAP       ( w -- a ) _SR-W-OUTPUT-CAP + ;
: _SRW.DATA-U           ( w -- a ) _SR-W-DATA-U + ;
: _SRW.TOTAL-U          ( w -- a ) _SR-W-TOTAL-U + ;
: _SRW.RESOLVER-CALLS   ( w -- a ) _SR-W-RESOLVER-CALLS + ;
: _SRW.CONSUMER-STATUS  ( w -- a ) _SR-W-CONSUMER-STATUS + ;
: _SRW.OPERATION        ( w -- a ) _SR-W-OPERATION + ;
: _SRW.RESOLVER-DEPTH   ( w -- a ) _SR-W-RESOLVER-DEPTH + ;
: _SRW.HEADER           ( w -- a ) _SR-W-HEADER + ;
: _SRW.DATA             ( w -- a ) _SR-W-DATA + ;
: _SRW.PRK              ( w -- a ) _SR-W-PRK + ;
: _SRW.KEY              ( w -- a ) _SR-W-KEY + ;
: _SRW.IV-DIGEST        ( w -- a ) _SR-W-IV-DIGEST + ;
: _SRW.KDF-MESSAGE      ( w -- a ) _SR-W-KDF-MESSAGE + ;
: _SRW.HMAC             ( w -- a ) _SR-W-HMAC + ;
: _SRW.AES-DESCRIPTOR   ( w -- a ) _SR-W-AES-DESCRIPTOR + ;
: _SRW.AES-WORKSPACE    ( w -- a ) _SR-W-AES-WORKSPACE + ;

: _SRW.TAG  ( w -- tag )
    DUP _SRW.DATA SWAP _SRW.DATA-U @ + ;

\ =====================================================================
\  Span admission and operation geometry
\ =====================================================================

: _SR-REQUIRED-SPAN?  ( address length -- flag )
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _SR-CALLER-SPAN>STATUS  ( address length -- status )
    CALLER-SPAN-STATUS
    DUP CALLER-SPAN-S-OK = IF
        DROP SEALED-RECORD-S-OK EXIT
    THEN
    DUP CALLER-SPAN-S-RANGE = IF
        DROP SEALED-RECORD-S-RANGE EXIT
    THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP SEALED-RECORD-S-PROTECTED EXIT
    THEN
    DROP SEALED-RECORD-S-PLATFORM ;

: _SR-ADMIT-SPAN  ( address length -- status )
    2DUP _SR-REQUIRED-SPAN? 0= IF
        2DROP SEALED-RECORD-S-INVALID EXIT
    THEN
    _SR-CALLER-SPAN>STATUS ;

: _SR-ONE-CONTAINER-ALIASED?  ( descriptor workspace a u -- flag )
    2DUP 5 PICK SEALED-RECORD-DESCRIPTOR-SIZE
        MSPAN-OVERLAP? IF
        2DROP 2DROP -1 EXIT
    THEN
    2DUP 4 PICK SEALED-RECORD-WORKSPACE-SIZE
        MSPAN-OVERLAP?
    >R 2DROP 2DROP R> ;

: _SR-CONTAINERS-ALIASED?  ( descriptor workspace -- flag )
    OVER SEALED-RECORD-DESCRIPTOR-SIZE
    2 PICK SEALED-RECORD-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF 2DROP -1 EXIT THEN

    2DUP OVER SEALED-RECORD-D.INPUT @
        2 PICK SEALED-RECORD-D.INPUT-U @
        _SR-ONE-CONTAINER-ALIASED? IF 2DROP -1 EXIT THEN
    2DUP OVER SEALED-RECORD-D.KEY-ID @
        SEALED-RECORD-ID-SIZE
        _SR-ONE-CONTAINER-ALIASED? IF 2DROP -1 EXIT THEN
    2DUP OVER SEALED-RECORD-D.RECORD-ID @
        SEALED-RECORD-ID-SIZE
        _SR-ONE-CONTAINER-ALIASED? IF 2DROP -1 EXIT THEN
    2DUP OVER SEALED-RECORD-D.OUTPUT @
        2 PICK SEALED-RECORD-D.OUTPUT-CAP @
        _SR-ONE-CONTAINER-ALIASED? IF 2DROP -1 EXIT THEN
    2DROP 0 ;

: _SR-OUTPUT-ALIASED?  ( descriptor -- flag )
    DUP SEALED-RECORD-D.OUTPUT @
    OVER SEALED-RECORD-D.OUTPUT-CAP @
    2 PICK SEALED-RECORD-D.INPUT @
    3 PICK SEALED-RECORD-D.INPUT-U @
    MSPAN-OVERLAP? IF DROP -1 EXIT THEN

    DUP SEALED-RECORD-D.OUTPUT @
    OVER SEALED-RECORD-D.OUTPUT-CAP @
    2 PICK SEALED-RECORD-D.KEY-ID @ SEALED-RECORD-ID-SIZE
    MSPAN-OVERLAP? IF DROP -1 EXIT THEN

    DUP SEALED-RECORD-D.OUTPUT @
    OVER SEALED-RECORD-D.OUTPUT-CAP @
    2 PICK SEALED-RECORD-D.RECORD-ID @ SEALED-RECORD-ID-SIZE
    MSPAN-OVERLAP? NIP ;

: _SR-EXPECTED-IDS-ALIASED?  ( descriptor -- flag )
    DUP SEALED-RECORD-D.INPUT @
    OVER SEALED-RECORD-D.INPUT-U @
    2 PICK SEALED-RECORD-D.KEY-ID @ SEALED-RECORD-ID-SIZE
    MSPAN-OVERLAP? IF DROP -1 EXIT THEN

    DUP SEALED-RECORD-D.INPUT @
    OVER SEALED-RECORD-D.INPUT-U @
    2 PICK SEALED-RECORD-D.RECORD-ID @ SEALED-RECORD-ID-SIZE
    MSPAN-OVERLAP? IF DROP -1 EXIT THEN

    DUP SEALED-RECORD-D.KEY-ID @ SEALED-RECORD-ID-SIZE
    2 PICK SEALED-RECORD-D.RECORD-ID @ SEALED-RECORD-ID-SIZE
    MSPAN-OVERLAP? NIP ;

: _SR-COMMON-PREFLIGHT  ( descriptor workspace -- status )
    OVER SEALED-RECORD-DESCRIPTOR-SIZE _SR-ADMIT-SPAN
        ?DUP IF >R 2DROP R> EXIT THEN
    DUP SEALED-RECORD-WORKSPACE-SIZE _SR-ADMIT-SPAN
        ?DUP IF >R 2DROP R> EXIT THEN
    DUP _SR-W-RESERVED + @ _SR-WORKSPACE-BUSY = IF
        2DROP SEALED-RECORD-S-BUSY EXIT
    THEN

    OVER SEALED-RECORD-D.INPUT @
    2 PICK SEALED-RECORD-D.INPUT-U @ _SR-ADMIT-SPAN
        ?DUP IF >R 2DROP R> EXIT THEN
    OVER SEALED-RECORD-D.KEY-ID @ SEALED-RECORD-ID-SIZE
        _SR-ADMIT-SPAN ?DUP IF >R 2DROP R> EXIT THEN
    OVER SEALED-RECORD-D.RECORD-ID @ SEALED-RECORD-ID-SIZE
        _SR-ADMIT-SPAN ?DUP IF >R 2DROP R> EXIT THEN
    OVER SEALED-RECORD-D.OUTPUT @
    2 PICK SEALED-RECORD-D.OUTPUT-CAP @ _SR-ADMIT-SPAN
        ?DUP IF >R 2DROP R> EXIT THEN

    OVER SEALED-RECORD-D.PURPOSE @ 0> 0= IF
        2DROP SEALED-RECORD-S-INVALID EXIT
    THEN
    OVER SEALED-RECORD-D.REVISION @ 0> 0= IF
        2DROP SEALED-RECORD-S-INVALID EXIT
    THEN
    OVER SEALED-RECORD-D.RESOLVER-XT @ 0= IF
        2DROP SEALED-RECORD-S-INVALID EXIT
    THEN
    OVER SEALED-RECORD-D.KEY-ID @ SEALED-RECORD-ID-SIZE
        _SR-NONZERO-SPAN? 0= IF
        2DROP SEALED-RECORD-S-INVALID EXIT
    THEN
    OVER SEALED-RECORD-D.RECORD-ID @ SEALED-RECORD-ID-SIZE
        _SR-NONZERO-SPAN? 0= IF
        2DROP SEALED-RECORD-S-INVALID EXIT
    THEN

    2DUP _SR-CONTAINERS-ALIASED? IF
        2DROP SEALED-RECORD-S-ALIAS EXIT
    THEN
    OVER _SR-OUTPUT-ALIASED? IF
        2DROP SEALED-RECORD-S-ALIAS EXIT
    THEN
    OVER _SR-EXPECTED-IDS-ALIASED? IF
        2DROP SEALED-RECORD-S-ALIAS EXIT
    THEN
    2DROP SEALED-RECORD-S-OK ;

: _SR-SEAL-PREFLIGHT  ( descriptor workspace -- status )
    2DUP _SR-COMMON-PREFLIGHT
    DUP IF
        >R 2DROP R> EXIT
    THEN
    DROP
    OVER SEALED-RECORD-D.INPUT-U @ SEALED-RECORD-SIZE
    DUP 0= IF
        DROP 2DROP SEALED-RECORD-S-INVALID EXIT
    THEN
    2 PICK SEALED-RECORD-D.OUTPUT-CAP @ > IF
        2DROP SEALED-RECORD-S-CAPACITY EXIT
    THEN
    OVER SEALED-RECORD-D.OUTPUT-CAP @
        SEALED-RECORD-SIZE-MAX U> IF
        2DROP SEALED-RECORD-S-INVALID EXIT
    THEN
    2DROP SEALED-RECORD-S-OK ;

: _SR-OPEN-PREFLIGHT  ( descriptor workspace -- status )
    2DUP _SR-COMMON-PREFLIGHT
    DUP IF
        >R 2DROP R> EXIT
    THEN
    DROP
    OVER SEALED-RECORD-D.INPUT-U @
    DUP SEALED-RECORD-OVERHEAD U> 0= IF
        DROP 2DROP SEALED-RECORD-S-FORMAT EXIT
    THEN
    SEALED-RECORD-SIZE-MAX U> IF
        2DROP SEALED-RECORD-S-FORMAT EXIT
    THEN
    OVER SEALED-RECORD-D.OUTPUT-CAP @
        SEALED-RECORD-DATA-MAX U> IF
        2DROP SEALED-RECORD-S-INVALID EXIT
    THEN
    2DROP SEALED-RECORD-S-OK ;

\ =====================================================================
\  Descriptor/workspace clearing and descriptor snapshot
\ =====================================================================

: SEALED-RECORD-DESCRIPTOR-CLEAR  ( descriptor -- status )
    DUP SEALED-RECORD-DESCRIPTOR-SIZE _SR-ADMIT-SPAN
        ?DUP IF NIP EXIT THEN
    SEALED-RECORD-DESCRIPTOR-SIZE 0 FILL
    SEALED-RECORD-S-OK ;

: SEALED-RECORD-WORKSPACE-CLEAR  ( workspace -- status )
    DUP SEALED-RECORD-WORKSPACE-SIZE _SR-ADMIT-SPAN
        ?DUP IF NIP EXIT THEN
    SEALED-RECORD-WORKSPACE-SIZE 0 FILL
    SEALED-RECORD-S-OK ;

: _SR-BIND  ( descriptor workspace operation -- workspace )
    >R
    DUP SEALED-RECORD-WORKSPACE-SIZE 0 FILL
    _SR-WORKSPACE-BUSY OVER _SR-W-RESERVED + !
    OVER OVER _SRW.DESCRIPTOR !
    OVER SEALED-RECORD-D.INPUT @ OVER _SRW.INPUT !
    OVER SEALED-RECORD-D.INPUT-U @ OVER _SRW.INPUT-U !
    OVER SEALED-RECORD-D.KEY-ID @ OVER _SRW.KEY-ID !
    OVER SEALED-RECORD-D.RECORD-ID @ OVER _SRW.RECORD-ID !
    OVER SEALED-RECORD-D.PURPOSE @ OVER _SRW.PURPOSE !
    OVER SEALED-RECORD-D.REVISION @ OVER _SRW.REVISION !
    OVER SEALED-RECORD-D.RESOLVER-XT @ OVER _SRW.RESOLVER-XT !
    OVER SEALED-RECORD-D.RESOLVER-CONTEXT @
        OVER _SRW.RESOLVER-CONTEXT !
    OVER SEALED-RECORD-D.OUTPUT @ OVER _SRW.OUTPUT !
    OVER SEALED-RECORD-D.OUTPUT-CAP @ OVER _SRW.OUTPUT-CAP !
    R@ OVER _SRW.OPERATION !
    OVER SEALED-RECORD-D.INPUT-U @
    R@ _SR-OP-SEAL = IF
        DUP 2 PICK _SRW.DATA-U !
        SEALED-RECORD-OVERHEAD + OVER _SRW.TOTAL-U !
    ELSE
        OVER _SRW.TOTAL-U !
    THEN
    R> DROP NIP ;

\ =====================================================================
\  Header construction and strict parsing
\ =====================================================================

: _SR-HEADER-BUILD  ( workspace -- status )
    >R
    _SR-MAGIC R@ _SRW.HEADER _SR-H-MAGIC + _SR-BE64!
    _SR-VERSION R@ _SRW.HEADER _SR-H-VERSION + _SR-BE64!
    SEALED-RECORD-HEADER-SIZE
        R@ _SRW.HEADER _SR-H-HEADER-U + _SR-BE64!
    R@ _SRW.TOTAL-U @
        R@ _SRW.HEADER _SR-H-TOTAL-U + _SR-BE64!
    R@ _SRW.DATA-U @
        R@ _SRW.HEADER _SR-H-DATA-U + _SR-BE64!
    R@ _SRW.PURPOSE @
        R@ _SRW.HEADER _SR-H-PURPOSE + _SR-BE64!
    R@ _SRW.REVISION @
        R@ _SRW.HEADER _SR-H-REVISION + _SR-BE64!
    0 R@ _SRW.HEADER _SR-H-FLAGS + _SR-BE64!
    R@ _SRW.KEY-ID @
        R@ _SRW.HEADER _SR-H-KEY-ID + SEALED-RECORD-ID-SIZE MOVE
    R@ _SRW.RECORD-ID @
        R@ _SRW.HEADER _SR-H-RECORD-ID + SEALED-RECORD-ID-SIZE MOVE

    R@ _SRW.HEADER _SR-H-SALT + SEALED-RECORD-SALT-SIZE
        ENTROPY-FILL
    DUP ENTROPY-S-OK <> IF
        DROP R> DROP SEALED-RECORD-S-ENTROPY EXIT
    THEN
    DROP
    R@ _SRW.HEADER _SR-H-SALT + SEALED-RECORD-SALT-SIZE
        _SR-NONZERO-SPAN? 0= IF
        R> DROP SEALED-RECORD-S-ENTROPY EXIT
    THEN
    R> DROP SEALED-RECORD-S-OK ;

: _SR-HEADER-NUMERIC-SHAPE?  ( header -- flag )
    DUP _SR-H-MAGIC + _SR-BE64-NONNEGATIVE?
    OVER _SR-H-VERSION + _SR-BE64-NONNEGATIVE? AND
    OVER _SR-H-HEADER-U + _SR-BE64-NONNEGATIVE? AND
    OVER _SR-H-TOTAL-U + _SR-BE64-NONNEGATIVE? AND
    OVER _SR-H-DATA-U + _SR-BE64-NONNEGATIVE? AND
    OVER _SR-H-PURPOSE + _SR-BE64-NONNEGATIVE? AND
    OVER _SR-H-REVISION + _SR-BE64-NONNEGATIVE? AND
    SWAP _SR-H-FLAGS + _SR-BE64-NONNEGATIVE? AND ;

: _SR-HEADER-PARSE  ( workspace -- status )
    >R
    R@ _SRW.INPUT @ DUP _SR-HEADER-NUMERIC-SHAPE? 0= IF
        DROP R> DROP SEALED-RECORD-S-FORMAT EXIT
    THEN
    DUP _SR-H-MAGIC + _SR-BE64@ _SR-MAGIC <> IF
        DROP R> DROP SEALED-RECORD-S-FORMAT EXIT
    THEN
    DUP _SR-H-VERSION + _SR-BE64@ _SR-VERSION <> IF
        DROP R> DROP SEALED-RECORD-S-FORMAT EXIT
    THEN
    DUP _SR-H-HEADER-U + _SR-BE64@
        SEALED-RECORD-HEADER-SIZE <> IF
        DROP R> DROP SEALED-RECORD-S-FORMAT EXIT
    THEN
    DUP _SR-H-FLAGS + _SR-BE64@ 0<> IF
        DROP R> DROP SEALED-RECORD-S-FORMAT EXIT
    THEN

    DUP _SR-H-DATA-U + _SR-BE64@
    DUP SEALED-RECORD-SIZE DUP 0= IF
        2DROP DROP R> DROP SEALED-RECORD-S-FORMAT EXIT
    THEN
    2 PICK _SR-H-TOTAL-U + _SR-BE64@ OVER <> IF
        2DROP DROP R> DROP SEALED-RECORD-S-FORMAT EXIT
    THEN
    DUP R@ _SRW.INPUT-U @ <> IF
        2DROP DROP R> DROP SEALED-RECORD-S-FORMAT EXIT
    THEN
    OVER R@ _SRW.DATA-U !
    DUP R@ _SRW.TOTAL-U !
    2DROP

    DUP _SR-H-PURPOSE + _SR-BE64@
        R@ _SRW.PURPOSE @ <> IF
        DROP R> DROP SEALED-RECORD-S-MISMATCH EXIT
    THEN
    DUP _SR-H-REVISION + _SR-BE64@
        R@ _SRW.REVISION @ <> IF
        DROP R> DROP SEALED-RECORD-S-MISMATCH EXIT
    THEN
    DUP _SR-H-KEY-ID +
        R@ _SRW.KEY-ID @ _SR-ID= 0= IF
        DROP R> DROP SEALED-RECORD-S-MISMATCH EXIT
    THEN
    DUP _SR-H-RECORD-ID +
        R@ _SRW.RECORD-ID @ _SR-ID= 0= IF
        DROP R> DROP SEALED-RECORD-S-MISMATCH EXIT
    THEN
    DUP _SR-H-SALT + SEALED-RECORD-SALT-SIZE
        _SR-NONZERO-SPAN? 0= IF
        DROP R> DROP SEALED-RECORD-S-FORMAT EXIT
    THEN

    R@ _SRW.HEADER SEALED-RECORD-HEADER-SIZE MOVE
    R@ _SRW.INPUT @ SEALED-RECORD-HEADER-SIZE +
    R@ _SRW.DATA-U @ +
    R@ _SRW.TAG SEALED-RECORD-TAG-SIZE MOVE
    R@ _SRW.DATA-U @ R@ _SRW.OUTPUT-CAP @ > IF
        R> DROP SEALED-RECORD-S-CAPACITY EXIT
    THEN
    R> DROP SEALED-RECORD-S-OK ;

\ =====================================================================
\  RFC 5869 HKDF-SHA-256 root-key consumer
\ =====================================================================

36 CONSTANT _SR-KDF-INFO-U

: _SR-HMAC>STATUS  ( hmac-status -- status )
    HMAC-SHA256-S-OK =
    IF SEALED-RECORD-S-OK ELSE SEALED-RECORD-S-CRYPTO THEN ;

: _SR-KDF-EXTRACT  ( root-key root-key-u workspace -- status )
    >R
    R@ _SRW.HEADER _SR-H-SALT + SEALED-RECORD-SALT-SIZE
    2SWAP
    R@ _SRW.PRK R@ _SRW.HMAC
    HMAC-SHA256 _SR-HMAC>STATUS
    R> DROP ;

: _SR-KDF-EXPAND-KEY  ( workspace -- status )
    >R
    S" Akashic sealed record AES-256-GCM v1"
        R@ _SRW.KDF-MESSAGE SWAP MOVE
    1 R@ _SRW.KDF-MESSAGE _SR-KDF-INFO-U + C!
    R@ _SRW.PRK HMAC-SHA256-DIGEST-SIZE
    R@ _SRW.KDF-MESSAGE _SR-KDF-INFO-U 1+
    R@ _SRW.KEY R@ _SRW.HMAC
    HMAC-SHA256 _SR-HMAC>STATUS
    R> DROP ;

: _SR-KDF-EXPAND-IV  ( workspace -- status )
    >R
    R@ _SRW.KEY R@ _SRW.KDF-MESSAGE
        HMAC-SHA256-DIGEST-SIZE MOVE
    S" Akashic sealed record AES-256-GCM v1"
        R@ _SRW.KDF-MESSAGE HMAC-SHA256-DIGEST-SIZE +
        SWAP MOVE
    2 R@ _SRW.KDF-MESSAGE
        HMAC-SHA256-DIGEST-SIZE _SR-KDF-INFO-U + + C!
    R@ _SRW.PRK HMAC-SHA256-DIGEST-SIZE
    R@ _SRW.KDF-MESSAGE
        HMAC-SHA256-DIGEST-SIZE _SR-KDF-INFO-U + 1+
    R@ _SRW.IV-DIGEST R@ _SRW.HMAC
    HMAC-SHA256 _SR-HMAC>STATUS
    R> DROP ;

: _SR-ROOT-ALIASED?  ( root-key workspace -- flag )
    >R
    DUP SEALED-RECORD-ROOT-KEY-SIZE
        R@ SEALED-RECORD-WORKSPACE-SIZE MSPAN-OVERLAP? IF
        DROP R> DROP -1 EXIT
    THEN
    DUP SEALED-RECORD-ROOT-KEY-SIZE
        R@ _SRW.DESCRIPTOR @ SEALED-RECORD-DESCRIPTOR-SIZE
        MSPAN-OVERLAP? IF DROP R> DROP -1 EXIT THEN
    DUP SEALED-RECORD-ROOT-KEY-SIZE
        R@ _SRW.INPUT @ R@ _SRW.INPUT-U @
        MSPAN-OVERLAP? IF DROP R> DROP -1 EXIT THEN
    DUP SEALED-RECORD-ROOT-KEY-SIZE
        R@ _SRW.KEY-ID @ SEALED-RECORD-ID-SIZE
        MSPAN-OVERLAP? IF DROP R> DROP -1 EXIT THEN
    DUP SEALED-RECORD-ROOT-KEY-SIZE
        R@ _SRW.RECORD-ID @ SEALED-RECORD-ID-SIZE
        MSPAN-OVERLAP? IF DROP R> DROP -1 EXIT THEN
    SEALED-RECORD-ROOT-KEY-SIZE
        R@ _SRW.OUTPUT @ R@ _SRW.OUTPUT-CAP @
        MSPAN-OVERLAP?
    R> DROP ;

: _SR-CONSUMER-RETURN  ( status workspace -- status )
    SWAP DUP ROT _SRW.CONSUMER-STATUS ! ;

: _SR-ROOT-CONSUMER
  ( guard workspace root-key root-key-u context -- guard workspace status )
    \ _SR-RESOLVER-INVOKE retains the original workspace directly beneath
    \ the resolver's five public arguments.  Reject a substituted opaque
    \ context before using it as an address.
    DUP 4 PICK <> IF
        2DROP DROP SEALED-RECORD-S-CALLBACK EXIT
    THEN
    >R
    1 R@ _SRW.RESOLVER-CALLS +!
    R@ _SRW.RESOLVER-CALLS @ 1 <> IF
        2DROP SEALED-RECORD-S-CALLBACK
        R> _SR-CONSUMER-RETURN EXIT
    THEN
    DUP SEALED-RECORD-ROOT-KEY-SIZE <> IF
        2DROP SEALED-RECORD-S-KEY R> _SR-CONSUMER-RETURN EXIT
    THEN
    OVER SEALED-RECORD-ROOT-KEY-SIZE _SR-ADMIT-SPAN
        SEALED-RECORD-S-OK <> IF
        2DROP SEALED-RECORD-S-KEY R> _SR-CONSUMER-RETURN EXIT
    THEN
    OVER R@ _SR-ROOT-ALIASED? IF
        2DROP SEALED-RECORD-S-KEY R> _SR-CONSUMER-RETURN EXIT
    THEN

    2DUP R@ _SR-KDF-EXTRACT
    DUP IF
        >R 2DROP R> R> _SR-CONSUMER-RETURN EXIT
    THEN
    DROP 2DROP
    R@ _SR-KDF-EXPAND-KEY
    DUP IF R> _SR-CONSUMER-RETURN EXIT THEN DROP
    R@ _SR-KDF-EXPAND-IV
    R> _SR-CONSUMER-RETURN ;

-3101 CONSTANT _SR-E-RESOLVER-STACK
0x53525245534F4C56 CONSTANT _SR-RESOLVER-CANARY

: _SR-RESOLVER-INVOKE  ( workspace -- status )
    >R
    DEPTH R@ _SRW.RESOLVER-DEPTH !
    _SR-RESOLVER-CANARY
    R@
    R@ _SRW.KEY-ID @ SEALED-RECORD-ID-SIZE
    ['] _SR-ROOT-CONSUMER R@
    R@ _SRW.RESOLVER-CONTEXT @
    R@ _SRW.RESOLVER-XT @ EXECUTE
    DEPTH R@ _SRW.RESOLVER-DEPTH @ 3 + <> IF
        _SR-E-RESOLVER-STACK THROW
    THEN
    2 PICK _SR-RESOLVER-CANARY <> IF
        _SR-E-RESOLVER-STACK THROW
    THEN
    1 PICK R@ <> IF
        _SR-E-RESOLVER-STACK THROW
    THEN
    >R 2DROP R>
    R> DROP ;

: _SR-RESOLVER-SAFE  ( workspace -- status )
    ['] _SR-RESOLVER-INVOKE CATCH
    DUP IF
        2DROP SEALED-RECORD-S-CALLBACK
    ELSE
        DROP
    THEN ;

: _SR-RESOLVE  ( workspace -- status )
    >R
    0 R@ _SRW.RESOLVER-CALLS !
    SEALED-RECORD-S-KEY R@ _SRW.CONSUMER-STATUS !
    R@ _SR-RESOLVER-SAFE
    DUP SEALED-RECORD-STATUS-VALID? 0= IF
        DROP R> DROP SEALED-RECORD-S-CALLBACK EXIT
    THEN
    R@ _SRW.RESOLVER-CALLS @ 0= IF
        DUP SEALED-RECORD-S-KEY = IF
            R> DROP EXIT
        THEN
        DROP R> DROP SEALED-RECORD-S-CALLBACK EXIT
    THEN
    R@ _SRW.RESOLVER-CALLS @ 1 <> IF
        DROP R> DROP SEALED-RECORD-S-CALLBACK EXIT
    THEN
    DUP R@ _SRW.CONSUMER-STATUS @ <> IF
        DROP R> DROP SEALED-RECORD-S-CALLBACK EXIT
    THEN
    R> DROP ;

\ =====================================================================
\  AES-GCM descriptor binding and operation
\ =====================================================================

: _SR-AES>STATUS  ( aes-status -- status )
    DUP AES-GCM-S-OK = IF
        DROP SEALED-RECORD-S-OK EXIT
    THEN
    AES-GCM-S-AUTH =
    IF SEALED-RECORD-S-AUTH ELSE SEALED-RECORD-S-CRYPTO THEN ;

: _SR-AES-BIND-COMMON  ( workspace -- )
    >R
    R@ _SRW.AES-DESCRIPTOR AES-GCM-DESCRIPTOR-CLEAR DROP
    R@ _SRW.KEY
        R@ _SRW.AES-DESCRIPTOR AES-GCM-D.KEY !
    AES-GCM-KEY256-SIZE
        R@ _SRW.AES-DESCRIPTOR AES-GCM-D.KEY-U !
    R@ _SRW.IV-DIGEST
        R@ _SRW.AES-DESCRIPTOR AES-GCM-D.IV !
    AES-GCM-IV-SIZE
        R@ _SRW.AES-DESCRIPTOR AES-GCM-D.IV-U !
    R@ _SRW.HEADER
        R@ _SRW.AES-DESCRIPTOR AES-GCM-D.AAD !
    SEALED-RECORD-HEADER-SIZE
        R@ _SRW.AES-DESCRIPTOR AES-GCM-D.AAD-U !
    R@ _SRW.DATA-U @
        R@ _SRW.AES-DESCRIPTOR AES-GCM-D.DATA-U !
    R@ _SRW.TAG
        R@ _SRW.AES-DESCRIPTOR AES-GCM-D.TAG !
    SEALED-RECORD-TAG-SIZE
        R@ _SRW.AES-DESCRIPTOR AES-GCM-D.TAG-U !
    R> DROP ;

: _SR-AES-SEAL  ( workspace -- status )
    >R
    R@ _SR-AES-BIND-COMMON
    R@ _SRW.INPUT @
        R@ _SRW.AES-DESCRIPTOR AES-GCM-D.INPUT !
    R@ _SRW.DATA
        R@ _SRW.AES-DESCRIPTOR AES-GCM-D.OUTPUT !
    R@ _SRW.AES-DESCRIPTOR R@ _SRW.AES-WORKSPACE
        AES-GCM-SEAL _SR-AES>STATUS
    R> DROP ;

: _SR-AES-OPEN  ( workspace -- status )
    >R
    R@ _SR-AES-BIND-COMMON
    R@ _SRW.INPUT @ SEALED-RECORD-HEADER-SIZE +
        R@ _SRW.AES-DESCRIPTOR AES-GCM-D.INPUT !
    R@ _SRW.DATA
        R@ _SRW.AES-DESCRIPTOR AES-GCM-D.OUTPUT !
    R@ _SRW.AES-DESCRIPTOR R@ _SRW.AES-WORKSPACE
        AES-GCM-OPEN _SR-AES>STATUS
    R> DROP ;

\ =====================================================================
\  Admitted computation, publication, and cleanup
\ =====================================================================

: _SR-SEAL-COMPUTE  ( descriptor workspace -- workspace status )
    _SR-OP-SEAL _SR-BIND
    DUP _SR-HEADER-BUILD
    DUP IF EXIT THEN DROP
    DUP _SR-RESOLVE
    DUP IF EXIT THEN DROP
    DUP _SR-AES-SEAL ;

: _SR-OPEN-COMPUTE  ( descriptor workspace -- workspace status )
    _SR-OP-OPEN _SR-BIND
    DUP _SR-HEADER-PARSE
    DUP IF EXIT THEN DROP
    DUP _SR-RESOLVE
    DUP IF EXIT THEN DROP
    DUP _SR-AES-OPEN ;

: _SR-COMPUTE-CALL
  ( descriptor workspace xt -- workspace status )
    1 PICK >R
    CATCH
    ?DUP IF
        >R 2DROP R> DROP
        R> SEALED-RECORD-S-INTERNAL EXIT
    THEN
    R> DROP ;

: _SR-WIPE-RETURN  ( workspace status -- status )
    >R
    SEALED-RECORD-WORKSPACE-SIZE 0 FILL
    R> ;

: _SR-PUBLISH-SEAL  ( workspace -- workspace )
    \ Invalidate old output before copying the body and publish the new magic
    \ last.  A publication THROW is still explicitly indeterminate: even the
    \ invalidating or final magic write can itself fault.
    DUP _SRW.OUTPUT @ 8 0 FILL
    DUP _SRW.HEADER 8 +
    OVER _SRW.OUTPUT @ 8 +
    2 PICK _SRW.TOTAL-U @ 8 - MOVE
    DUP _SRW.HEADER
    OVER _SRW.OUTPUT @ 8 MOVE ;

: _SR-PUBLISH-OPEN  ( workspace -- workspace )
    DUP _SRW.OUTPUT @
    OVER _SRW.OUTPUT-CAP @ 0 FILL
    DUP _SRW.DATA
    OVER _SRW.OUTPUT @
    2 PICK _SRW.DATA-U @ MOVE ;

: _SR-INVALIDATE-SEAL-OUTPUT  ( workspace -- )
    _SRW.OUTPUT @ 8 0 FILL ;

: _SR-WIPE-OPEN-OUTPUT  ( workspace -- )
    DUP _SRW.OUTPUT @ SWAP _SRW.OUTPUT-CAP @ 0 FILL ;

: _SR-WIPE-WORKSPACE  ( workspace -- )
    SEALED-RECORD-WORKSPACE-SIZE 0 FILL ;

: _SR-CATCH-IOR  ( argument xt -- ior )
    CATCH
    DUP IF NIP THEN ;

: _SR-RETHROW-AFTER-CLEANUPS
  ( workspace publication-ior output-cleanup-xt -- )
    SWAP >R >R
    DUP R> _SR-CATCH-IOR >R
    ['] _SR-WIPE-WORKSPACE _SR-CATCH-IOR
    DUP IF
        R> DROP R> DROP THROW
    THEN
    DROP
    R>
    DUP IF
        R> DROP THROW
    THEN
    DROP R> THROW ;

: _SR-PUBLISH-SEAL-WIPE  ( workspace -- status | throws )
    ['] _SR-PUBLISH-SEAL CATCH
    ?DUP IF
        ['] _SR-INVALIDATE-SEAL-OUTPUT
        _SR-RETHROW-AFTER-CLEANUPS
    THEN
    _SR-WIPE-WORKSPACE
    SEALED-RECORD-S-OK ;

: _SR-PUBLISH-OPEN-WIPE  ( workspace -- status | throws )
    ['] _SR-PUBLISH-OPEN CATCH
    ?DUP IF
        ['] _SR-WIPE-OPEN-OUTPUT
        _SR-RETHROW-AFTER-CLEANUPS
    THEN
    _SR-WIPE-WORKSPACE
    SEALED-RECORD-S-OK ;

: _SR-SEAL-ADMITTED  ( descriptor workspace -- written status )
    ['] _SR-SEAL-COMPUTE _SR-COMPUTE-CALL
    DUP IF
        _SR-WIPE-RETURN 0 SWAP EXIT
    THEN
    DROP
    DUP _SRW.TOTAL-U @ >R
    _SR-PUBLISH-SEAL-WIPE
    R> SWAP ;

: _SR-OPEN-ADMITTED  ( descriptor workspace -- written status )
    ['] _SR-OPEN-COMPUTE _SR-COMPUTE-CALL
    DUP IF
        _SR-WIPE-RETURN 0 SWAP EXIT
    THEN
    DROP
    DUP _SRW.DATA-U @ >R
    _SR-PUBLISH-OPEN-WIPE
    R> SWAP ;

: SEALED-RECORD-SEAL  ( descriptor workspace -- written status )
    2DUP _SR-SEAL-PREFLIGHT
    DUP IF
        >R 2DROP 0 R> EXIT
    THEN
    DROP _SR-SEAL-ADMITTED ;

: SEALED-RECORD-OPEN  ( descriptor workspace -- written status )
    2DUP _SR-OPEN-PREFLIGHT
    DUP IF
        >R 2DROP 0 R> EXIT
    THEN
    DROP _SR-OPEN-ADMITTED ;

\ =====================================================================
\  Compile-time geometry assertions
\ =====================================================================

: _SR-GEOMETRY-ABORT  ( -- )
    ." Sealed record geometry mismatch" CR ABORT ;

1 CELLS 8 <> [IF]
    _SR-GEOMETRY-ABORT
[THEN]

_SR-D-OUTPUT-CAP 8 + SEALED-RECORD-DESCRIPTOR-SIZE <> [IF]
    _SR-GEOMETRY-ABORT
[THEN]

_SR-W-OPERATION 8 + _SR-W-RESOLVER-DEPTH <> [IF]
    _SR-GEOMETRY-ABORT
[THEN]

_SR-W-RESOLVER-DEPTH 16 + _SR-W-HEADER <> [IF]
    _SR-GEOMETRY-ABORT
[THEN]

_SR-H-SALT SEALED-RECORD-SALT-SIZE +
SEALED-RECORD-HEADER-SIZE <> [IF]
    _SR-GEOMETRY-ABORT
[THEN]

SEALED-RECORD-HEADER-SIZE SEALED-RECORD-TAG-SIZE +
SEALED-RECORD-OVERHEAD <> [IF]
    _SR-GEOMETRY-ABORT
[THEN]

SEALED-RECORD-DATA-MAX SEALED-RECORD-OVERHEAD +
SEALED-RECORD-SIZE-MAX <> [IF]
    _SR-GEOMETRY-ABORT
[THEN]

_SR-W-HEADER SEALED-RECORD-HEADER-SIZE + _SR-W-DATA <> [IF]
    _SR-GEOMETRY-ABORT
[THEN]

_SR-W-DATA SEALED-RECORD-DATA-MAX +
SEALED-RECORD-TAG-SIZE + _SR-W-PRK <> [IF]
    _SR-GEOMETRY-ABORT
[THEN]

_SR-W-PRK HMAC-SHA256-DIGEST-SIZE + _SR-W-KEY <> [IF]
    _SR-GEOMETRY-ABORT
[THEN]

_SR-W-KEY AES-GCM-KEY256-SIZE + _SR-W-IV-DIGEST <> [IF]
    _SR-GEOMETRY-ABORT
[THEN]

_SR-W-IV-DIGEST HMAC-SHA256-DIGEST-SIZE +
_SR-W-KDF-MESSAGE <> [IF]
    _SR-GEOMETRY-ABORT
[THEN]

_SR-W-KDF-MESSAGE 96 + _SR-W-HMAC <> [IF]
    _SR-GEOMETRY-ABORT
[THEN]

_SR-W-HMAC HMAC-SHA256-WORKSPACE-SIZE +
_SR-W-AES-DESCRIPTOR <> [IF]
    _SR-GEOMETRY-ABORT
[THEN]

_SR-W-AES-DESCRIPTOR AES-GCM-DESCRIPTOR-SIZE +
_SR-W-AES-WORKSPACE <> [IF]
    _SR-GEOMETRY-ABORT
[THEN]

_SR-W-AES-WORKSPACE AES-GCM-WORKSPACE-SIZE +
SEALED-RECORD-WORKSPACE-SIZE <> [IF]
    _SR-GEOMETRY-ABORT
[THEN]

_SR-KDF-INFO-U 36 <> [IF]
    _SR-GEOMETRY-ABORT
[THEN]
