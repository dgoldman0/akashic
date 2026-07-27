\ =====================================================================
\  sha256.f - Checked hardware SHA-256 one-shot operations
\ =====================================================================
\  Megapad-64 / KDOS Forth      Prefix: SHA256-
\  Depends on: checked BIOS SHA-256 INIT/UPDATE/FINAL/CLEAR words
\
\  The BIOS owns the per-core streaming context.  This library exposes no
\  caller-spanning streaming aliases: each public hash validates all caller
\  geometry, acquires CRYPTO-ACC and the SHA-256 operation guard in that
\  order, then completes one INIT/UPDATE*/FINAL transaction.
\
\  Public API:
\    SHA256-LEN          ( -- 32 )
\    SHA256-HEX-LEN      ( -- 64 )
\    SHA256-STATUS-VALID? ( status -- flag )
\    SHA256-CALLER-SPAN-STATUS ( address length -- status )
\    SHA256-HASH         ( src len dst -- status )
\    SHA256-HASH-2       ( a1 u1 a2 u2 dst -- status )
\    SHA256-HASH-3       ( a1 u1 a2 u2 a3 u3 dst -- status )
\    SHA256->HEX         ( src dst -- n )
\    SHA256-.            ( addr -- )
\    SHA256-COMPARE      ( a b -- flag )
\
\  Status:
\    0 OK, 1 STATE, 2 RANGE, 3 ALIAS, 4 LENGTH-OVERFLOW,
\    5 INVALID, 6 CRYPTO.
\
\  Every returned failure leaves dst unchanged.  BIOS FINAL guarantees that
\  every nonzero status is non-publishing.  A THROW from FINAL is different:
\  Forth CATCH cannot establish whether publication preceded the exception,
\  so cleanup runs and the exception is rethrown instead of being converted
\  into a returned failure.
\ =====================================================================

PROVIDED akashic-sha256

REQUIRE crypto-acc.f
REQUIRE ../utils/memory-span.f

32 CONSTANT SHA256-LEN
64 CONSTANT SHA256-HEX-LEN

0 CONSTANT SHA256-S-OK
1 CONSTANT SHA256-S-STATE
2 CONSTANT SHA256-S-RANGE
3 CONSTANT SHA256-S-ALIAS
4 CONSTANT SHA256-S-LENGTH-OVERFLOW
5 CONSTANT SHA256-S-INVALID
6 CONSTANT SHA256-S-CRYPTO

: SHA256-STATUS-VALID?  ( status -- flag )
    DUP SHA256-S-OK >=
    SWAP SHA256-S-CRYPTO <= AND ;

\ =====================================================================
\  Pure digest helpers
\ =====================================================================

CREATE _SHA256-HEX
  48 C, 49 C, 50 C, 51 C, 52 C, 53 C, 54 C, 55 C,
  56 C, 57 C, 97 C, 98 C, 99 C, 100 C, 101 C, 102 C,

: _SHA256-NIB>C  ( nibble -- char )
    0x0F AND _SHA256-HEX + C@ ;

: SHA256->HEX  ( src dst -- n )
    SHA256-LEN 0 DO
        OVER I + C@
        DUP 4 RSHIFT _SHA256-NIB>C
        2 PICK I 2* + C!
        0x0F AND _SHA256-NIB>C
        OVER I 2* 1+ + C!
    LOOP
    2DROP SHA256-HEX-LEN ;

: SHA256-.  ( addr -- )
    SHA256-LEN 0 DO
        DUP I + C@
        DUP 4 RSHIFT _SHA256-NIB>C EMIT
        0x0F AND _SHA256-NIB>C EMIT
    LOOP
    DROP ;

: SHA256-COMPARE  ( a b -- flag )
    0
    SHA256-LEN 0 DO
        2 PICK I + C@
        2 PICK I + C@
        XOR OR
    LOOP
    NIP NIP 0= ;

\ The guard is part of this unit's writable reserved footprint and must
\ exist before public geometry words are compiled.
GUARD-BLOCKING _sha256-guard

\ =====================================================================
\  Public geometry
\ =====================================================================

: _S256-DROP3  ( x1 x2 x3 -- )
    2DROP DROP ;

: _S256-DROP4  ( x1 x2 x3 x4 -- )
    2DROP 2DROP ;

: _S256-DROP5  ( x1 x2 x3 x4 x5 -- )
    2DROP 2DROP DROP ;

: _S256-DROP6  ( x1 x2 x3 x4 x5 x6 -- )
    2DROP 2DROP 2DROP ;

: _S256-DROP7  ( x1 x2 x3 x4 x5 x6 x7 -- )
    2DROP 2DROP 2DROP DROP ;

: _S256-3DUP  ( x1 x2 x3 -- x1 x2 x3 x1 x2 x3 )
    2 PICK 2 PICK 2 PICK ;

: _S256-5DUP
  ( x1 x2 x3 x4 x5 -- x1 x2 x3 x4 x5 x1 x2 x3 x4 x5 )
    4 PICK 4 PICK 4 PICK 4 PICK 4 PICK ;

: _S256-7DUP
  ( x1 x2 x3 x4 x5 x6 x7 --
    x1 x2 x3 x4 x5 x6 x7 x1 x2 x3 x4 x5 x6 x7 )
    6 PICK 6 PICK 6 PICK 6 PICK 6 PICK 6 PICK 6 PICK ;

\ Empty input is valid and may use address zero.  Every nonempty input must
\ be nonnull and nonwrapping.  This arithmetic check precedes the pure
\ SHA2-SPAN-STATUS physical-window and BIOS-arena check; both run before
\ either ownership scope is acquired and before INIT.
: _S256-INPUT-SPAN?  ( address length -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _S256-LOCAL-RESERVED-OVERLAP?  ( address length -- flag )
    2DUP CRYPTO-ACC-RESERVED-OVERLAP? IF
        2DROP -1 EXIT
    THEN
    _sha256-guard GUARD-BLOCKING-SIZE MSPAN-OVERLAP? ;

\ The BIOS word is pure and pre-INIT, but still sits behind an exception
\ boundary.  CATCH restores address/length on THROW.  Only its documented
\ 0/2/3 results cross the Akashic boundary unchanged.
: _S256-BIOS-SPAN-STATUS  ( address length -- status )
    ['] SHA2-SPAN-STATUS CATCH
    ?DUP IF
        _S256-DROP3 SHA256-S-CRYPTO EXIT
    THEN
    DUP SHA256-S-OK = IF EXIT THEN
    DUP SHA256-S-RANGE = IF EXIT THEN
    DUP SHA256-S-ALIAS = IF EXIT THEN
    DROP SHA256-S-CRYPTO ;

: SHA256-CALLER-SPAN-STATUS  ( address length -- status )
    2DUP _S256-INPUT-SPAN? 0= IF
        2DROP SHA256-S-INVALID EXIT
    THEN
    2DUP _S256-LOCAL-RESERVED-OVERLAP? IF
        2DROP SHA256-S-ALIAS EXIT
    THEN
    _S256-BIOS-SPAN-STATUS ;

: _S256-PREFLIGHT-1  ( src len dst -- status )
    >R
    2DUP SHA256-CALLER-SPAN-STATUS ?DUP IF
        >R 2DROP R> R> DROP EXIT
    THEN
    R@ SHA256-LEN SHA256-CALLER-SPAN-STATUS ?DUP IF
        >R 2DROP R> R> DROP EXIT
    THEN
    2DUP R@ SHA256-LEN MSPAN-OVERLAP? IF
        2DROP R> DROP SHA256-S-ALIAS EXIT
    THEN
    2DROP R> DROP SHA256-S-OK ;

: _S256-PREFLIGHT-2  ( a1 u1 a2 u2 dst -- status )
    >R
    3 PICK 3 PICK SHA256-CALLER-SPAN-STATUS ?DUP IF
        >R _S256-DROP4 R> R> DROP EXIT
    THEN
    1 PICK 1 PICK SHA256-CALLER-SPAN-STATUS ?DUP IF
        >R _S256-DROP4 R> R> DROP EXIT
    THEN
    R@ SHA256-LEN SHA256-CALLER-SPAN-STATUS ?DUP IF
        >R _S256-DROP4 R> R> DROP EXIT
    THEN
    3 PICK 3 PICK R@ SHA256-LEN MSPAN-OVERLAP? IF
        _S256-DROP4 R> DROP SHA256-S-ALIAS EXIT
    THEN
    1 PICK 1 PICK R@ SHA256-LEN MSPAN-OVERLAP? IF
        _S256-DROP4 R> DROP SHA256-S-ALIAS EXIT
    THEN
    _S256-DROP4 R> DROP SHA256-S-OK ;

: _S256-PREFLIGHT-3  ( a1 u1 a2 u2 a3 u3 dst -- status )
    >R
    5 PICK 5 PICK SHA256-CALLER-SPAN-STATUS ?DUP IF
        >R _S256-DROP6 R> R> DROP EXIT
    THEN
    3 PICK 3 PICK SHA256-CALLER-SPAN-STATUS ?DUP IF
        >R _S256-DROP6 R> R> DROP EXIT
    THEN
    1 PICK 1 PICK SHA256-CALLER-SPAN-STATUS ?DUP IF
        >R _S256-DROP6 R> R> DROP EXIT
    THEN
    R@ SHA256-LEN SHA256-CALLER-SPAN-STATUS ?DUP IF
        >R _S256-DROP6 R> R> DROP EXIT
    THEN
    5 PICK 5 PICK R@ SHA256-LEN MSPAN-OVERLAP? IF
        _S256-DROP6 R> DROP SHA256-S-ALIAS EXIT
    THEN
    3 PICK 3 PICK R@ SHA256-LEN MSPAN-OVERLAP? IF
        _S256-DROP6 R> DROP SHA256-S-ALIAS EXIT
    THEN
    1 PICK 1 PICK R@ SHA256-LEN MSPAN-OVERLAP? IF
        _S256-DROP6 R> DROP SHA256-S-ALIAS EXIT
    THEN
    _S256-DROP6 R> DROP SHA256-S-OK ;

\ =====================================================================
\  Checked BIOS transaction
\ =====================================================================

: _S256-BIOS>STATUS  ( bios-status -- status )
    DUP SHA256-S-OK < IF
        DROP SHA256-S-CRYPTO EXIT
    THEN
    DUP SHA256-S-LENGTH-OVERFLOW > IF
        DROP SHA256-S-CRYPTO
    THEN ;

\ CLEAR is idempotent.  Its fixed ABI returns zero; either an unexpected
\ status or a THROW is conservatively reported as CRYPTO.
: _S256-CLEAR-STATUS  ( -- status )
    ['] SHA256-CLEAR CATCH
    ?DUP IF
        DROP SHA256-S-CRYPTO EXIT
    THEN
    _S256-BIOS>STATUS
    DUP SHA256-S-OK <> IF
        DROP SHA256-S-CRYPTO
    THEN ;

: _S256-CLEAR-AFTER-FAILURE  ( status -- status )
    >R
    _S256-CLEAR-STATUS
    DUP SHA256-S-OK = IF
        DROP R> EXIT
    THEN
    DROP R> DROP SHA256-S-CRYPTO ;

\ Prefix words stop before FINAL and always retain dst.  This makes all
\ INIT/UPDATE exceptions unambiguously pre-publication at the enclosing
\ CATCH boundary.
: _S256-PREFIX-1  ( src len dst -- dst bios-status )
    >R
    SHA256-INIT
    DUP IF
        >R 2DROP R> R> SWAP EXIT
    THEN
    DROP
    SHA256-UPDATE
    R> SWAP ;

: _S256-PREFIX-2  ( a1 u1 a2 u2 dst -- dst bios-status )
    >R
    SHA256-INIT
    DUP IF
        >R _S256-DROP4 R> R> SWAP EXIT
    THEN
    DROP
    2SWAP SHA256-UPDATE
    DUP IF
        >R 2DROP R> R> SWAP EXIT
    THEN
    DROP
    SHA256-UPDATE
    R> SWAP ;

: _S256-PREFIX-3  ( a1 u1 a2 u2 a3 u3 dst -- dst bios-status )
    >R
    SHA256-INIT
    DUP IF
        >R _S256-DROP6 R> R> SWAP EXIT
    THEN
    DROP
    2ROT SHA256-UPDATE
    DUP IF
        >R _S256-DROP4 R> R> SWAP EXIT
    THEN
    DROP
    2SWAP SHA256-UPDATE
    DUP IF
        >R 2DROP R> R> SWAP EXIT
    THEN
    DROP
    SHA256-UPDATE
    R> SWAP ;

\ Complete an admitted prefix while the algorithm guard is held.
\ Successful FINAL has already erased the BIOS SHA context and must not be
\ followed by CLEAR.  FINAL failure and FINAL THROW both receive CLEAR.
: _S256-FINISH  ( dst bios-status -- status )
    _S256-BIOS>STATUS
    DUP IF
        NIP
        _S256-CLEAR-AFTER-FAILURE
        _sha256-guard GUARD-RELEASE
        EXIT
    THEN
    DROP

    ['] SHA256-FINAL CATCH
    ?DUP IF
        >R DROP
        _S256-CLEAR-STATUS DROP
        _sha256-guard GUARD-RELEASE
        R> THROW
    THEN
    _S256-BIOS>STATUS
    DUP IF
        _S256-CLEAR-AFTER-FAILURE
        _sha256-guard GUARD-RELEASE
        EXIT
    THEN
    _sha256-guard GUARD-RELEASE ;

: _S256-UNIT-1  ( src len dst -- status )
    _sha256-guard GUARD-ACQUIRE
    ['] _S256-PREFIX-1 CATCH
    ?DUP IF
        >R _S256-DROP3 R> DROP
        SHA256-S-CRYPTO _S256-CLEAR-AFTER-FAILURE
        _sha256-guard GUARD-RELEASE
        EXIT
    THEN
    _S256-FINISH ;

: _S256-UNIT-2  ( a1 u1 a2 u2 dst -- status )
    _sha256-guard GUARD-ACQUIRE
    ['] _S256-PREFIX-2 CATCH
    ?DUP IF
        >R _S256-DROP5 R> DROP
        SHA256-S-CRYPTO _S256-CLEAR-AFTER-FAILURE
        _sha256-guard GUARD-RELEASE
        EXIT
    THEN
    _S256-FINISH ;

: _S256-UNIT-3  ( a1 u1 a2 u2 a3 u3 dst -- status )
    _sha256-guard GUARD-ACQUIRE
    ['] _S256-PREFIX-3 CATCH
    ?DUP IF
        >R _S256-DROP7 R> DROP
        SHA256-S-CRYPTO _S256-CLEAR-AFTER-FAILURE
        _sha256-guard GUARD-RELEASE
        EXIT
    THEN
    _S256-FINISH ;

\ Geometry is rejected before either shared resource is acquired.  Admitted
\ operations acquire the shared accumulator transaction first; the unit
\ bodies acquire the SHA-256 guard second and only then enter the BIOS.
: SHA256-HASH  ( src len dst -- status )
    _S256-3DUP _S256-PREFLIGHT-1
    DUP IF
        >R _S256-DROP3 R> EXIT
    THEN
    DROP
    ['] _S256-UNIT-1 CRYPTO-ACC-WITH-TRANSACTION ;

: SHA256-HASH-2  ( a1 u1 a2 u2 dst -- status )
    _S256-5DUP _S256-PREFLIGHT-2
    DUP IF
        >R _S256-DROP5 R> EXIT
    THEN
    DROP
    ['] _S256-UNIT-2 CRYPTO-ACC-WITH-TRANSACTION ;

: SHA256-HASH-3  ( a1 u1 a2 u2 a3 u3 dst -- status )
    _S256-7DUP _S256-PREFLIGHT-3
    DUP IF
        >R _S256-DROP7 R> EXIT
    THEN
    DROP
    ['] _S256-UNIT-3 CRYPTO-ACC-WITH-TRANSACTION ;
