\ OAuth-session dependency doubles.
\
\ Load this file before the real oauth2/token-set.f and the runner-packaged
\ oauth2/session.f bodies.  It supplies only the small platform contracts
\ those sources need plus one caller-owned, single-RID credential-vault
\ double.  The real credential-vault lifecycle suite owns multi-RID,
\ cryptographic, VFS, and crash-durability qualification.
\
\ The vault double deliberately preserves the production status values and
\ public operation ABIs.  Its secret borrow is copied to a separate arena and
\ wiped after the synchronous five-argument consumer returns or throws.

PROVIDED o2session-test-deps
PROVIDED akashic-memory-span
PROVIDED akashic-caller-span
PROVIDED akashic-runtime-identity
PROVIDED akashic-guard
PROVIDED akashic-cred-vault

\ =====================================================================
\  Checked memory and caller spans
\ =====================================================================

: MSPAN-NONWRAPPING?  ( address length -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    >R DUP R@ + SWAP U< 0= R> DROP ;

: MSPAN-OVERLAP?  ( a1 u1 a2 u2 -- flag )
    2OVER MSPAN-NONWRAPPING? 0= IF 2DROP 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 2DROP 0 EXIT THEN
    DUP 0= IF 2DROP 2DROP 0 EXIT THEN
    2 PICK 0= IF 2DROP 2DROP 0 EXIT THEN
    2OVER + >R OVER R> U< >R
    + >R DROP R> U< R> AND ;

0 CONSTANT CALLER-SPAN-S-OK
2 CONSTANT CALLER-SPAN-S-RANGE
3 CONSTANT CALLER-SPAN-S-PROTECTED
4 CONSTANT CALLER-SPAN-S-PLATFORM

: CALLER-SPAN-STATUS-VALID?  ( status -- flag )
    DUP CALLER-SPAN-S-OK = IF DROP -1 EXIT THEN
    DUP CALLER-SPAN-S-RANGE = IF DROP -1 EXIT THEN
    DUP CALLER-SPAN-S-PROTECTED = IF DROP -1 EXIT THEN
    CALLER-SPAN-S-PLATFORM = ;

: CALLER-SPAN-STATUS  ( address length -- status )
    2DUP MSPAN-NONWRAPPING? 0= IF
        2DROP CALLER-SPAN-S-RANGE EXIT
    THEN
    DUP 0> IF
        OVER 0= IF 2DROP CALLER-SPAN-S-RANGE EXIT THEN
    THEN
    2DROP CALLER-SPAN-S-OK ;

\ =====================================================================
\  Deterministic caller-owned spinning guards
\ =====================================================================

32 CONSTANT GUARD-SPIN-SIZE
-257 CONSTANT GUARD-E-NOT-OWNER

: GUARD  ( "name" -- )
    CREATE
        0 , 0 , 0 , 0 ,
    DOES> ;

: GUARD-SPIN?  ( guard -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    24 + @ 0= ;

\ The lifecycle fixture is single-threaded.  A positive depth therefore
\ denotes recursive ownership by that one deterministic execution context.
: GUARD-TRY-ACQUIRE  ( guard -- flag )
    DUP GUARD-SPIN? 0= IF DROP 0 EXIT THEN
    DUP @ DUP 0< IF 2DROP 0 EXIT THEN
    DROP
    1 OVER +!
    DROP -1 ;

: GUARD-ACQUIRE  ( guard -- )
    DUP GUARD-TRY-ACQUIRE 0= IF
        DROP GUARD-E-NOT-OWNER THROW
    THEN
    DROP ;

: GUARD-RELEASE  ( guard -- )
    DUP 0= IF DROP GUARD-E-NOT-OWNER THROW THEN
    DUP @ 0> 0= IF DROP GUARD-E-NOT-OWNER THROW THEN
    -1 SWAP +! ;

: WITH-GUARD  ( ... xt guard -- ... )
    DUP >R GUARD-ACQUIRE
    CATCH
    R> GUARD-RELEASE
    DUP IF THROW THEN
    DROP ;

\ =====================================================================
\  RID vocabulary
\ =====================================================================

32 CONSTANT RID-SIZE

: RID-CLEAR  ( id -- )
    RID-SIZE 0 FILL ;

: RID-COPY  ( source destination -- )
    2DUP = IF 2DROP EXIT THEN
    RID-SIZE CMOVE ;

: RID=  ( first second -- flag )
    2DUP = IF 2DROP -1 EXIT THEN
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    SWAP RID-SIZE ROT RID-SIZE COMPARE 0= ;

: RID-ZERO?  ( id -- flag )
    DUP 0= IF DROP -1 EXIT THEN
    DUP @ 0=
    OVER 8 + @ 0= AND
    OVER 16 + @ 0= AND
    SWAP 24 + @ 0= AND ;

: RID-PRESENT?  ( id -- flag )
    RID-ZERO? 0= ;

\ =====================================================================
\  Production-identical credential-vault vocabulary
\ =====================================================================

0  CONSTANT CVAULT-S-OK
1  CONSTANT CVAULT-S-INVALID
2  CONSTANT CVAULT-S-CAPACITY
3  CONSTANT CVAULT-S-ABSENT
4  CONSTANT CVAULT-S-REVOKED
5  CONSTANT CVAULT-S-CONFLICT
6  CONSTANT CVAULT-S-LOCKED
7  CONSTANT CVAULT-S-CALLBACK
8  CONSTANT CVAULT-S-ENTROPY
9  CONSTANT CVAULT-S-CRYPTO
10 CONSTANT CVAULT-S-AUTH
11 CONSTANT CVAULT-S-CORRUPT
12 CONSTANT CVAULT-S-UNSUPPORTED
13 CONSTANT CVAULT-S-IO
14 CONSTANT CVAULT-S-RECOVERY
15 CONSTANT CVAULT-S-BUSY
16 CONSTANT CVAULT-S-ROLLBACK
17 CONSTANT CVAULT-S-RANGE
18 CONSTANT CVAULT-S-PROTECTED
19 CONSTANT CVAULT-S-PLATFORM
20 CONSTANT CVAULT-S-INTERNAL

: CVAULT-STATUS-VALID?  ( status -- flag )
    DUP CVAULT-S-OK >= SWAP CVAULT-S-INTERNAL <= AND ;

1 CONSTANT CVAULT-STATE-PRESENT
2 CONSTANT CVAULT-STATE-TOMBSTONE

128 CONSTANT CVAULT-PLAINTEXT-HEADER-SIZE
65408 CONSTANT CVAULT-SECRET-CAPACITY-MAX

\ One descriptor contains an authoritative secret arena and a distinct
\ callback-borrow arena.  Keeping both caller-owned makes reboot simulation
\ a matter of discarding only the OAuth session object.
0x4F325354564C5431 CONSTANT _O2STD-VAULT-MAGIC  \ "O2STVLT1"

1 CONSTANT _O2STD-VF-CONFIGURED
2 CONSTANT _O2STD-VF-BUSY
4 CONSTANT _O2STD-VF-BLOCKED
7 CONSTANT _O2STD-VF-KNOWN

  0 CONSTANT _O2STD-V-MAGIC
  8 CONSTANT _O2STD-V-FLAGS
 16 CONSTANT _O2STD-V-LAST-STATUS
 24 CONSTANT _O2STD-V-CAPACITY
 32 CONSTANT _O2STD-V-GENERATION
 40 CONSTANT _O2STD-V-STATE
 48 CONSTANT _O2STD-V-KIND
 56 CONSTANT _O2STD-V-SECRET-U
 64 CONSTANT _O2STD-V-BLOCK-STATUS
 72 CONSTANT _O2STD-V-EXPECTED
 80 CONSTANT _O2STD-V-INPUT-A
 88 CONSTANT _O2STD-V-INPUT-U
 96 CONSTANT _O2STD-V-CALLBACK-XT
104 CONSTANT _O2STD-V-CALLBACK-CONTEXT
112 CONSTANT _O2STD-V-CALLBACK-DEPTH
120 CONSTANT _O2STD-V-CALLBACK-RESULT
128 CONSTANT _O2STD-V-RESERVED0
136 CONSTANT _O2STD-V-RESERVED1
144 CONSTANT _O2STD-V-RESERVED2
152 CONSTANT _O2STD-V-RESERVED3
160 CONSTANT _O2STD-V-RESERVED4
168 CONSTANT _O2STD-V-RESERVED5
176 CONSTANT _O2STD-V-RESERVED6
184 CONSTANT _O2STD-V-RESERVED7

192 CONSTANT _O2STD-V-RID
_O2STD-V-RID RID-SIZE + CONSTANT _O2STD-V-SECRET
_O2STD-V-SECRET CVAULT-SECRET-CAPACITY-MAX +
    CONSTANT _O2STD-V-BORROW
_O2STD-V-BORROW CVAULT-SECRET-CAPACITY-MAX +
    CONSTANT CVAULT-SIZE

: _O2STD-V.MAGIC          ( vault -- field ) _O2STD-V-MAGIC + ;
: _O2STD-V.FLAGS          ( vault -- field ) _O2STD-V-FLAGS + ;
: _O2STD-V.LAST-STATUS    ( vault -- field )
    _O2STD-V-LAST-STATUS + ;
: _O2STD-V.CAPACITY       ( vault -- field ) _O2STD-V-CAPACITY + ;
: _O2STD-V.GENERATION     ( vault -- field )
    _O2STD-V-GENERATION + ;
: _O2STD-V.STATE          ( vault -- field ) _O2STD-V-STATE + ;
: _O2STD-V.KIND           ( vault -- field ) _O2STD-V-KIND + ;
: _O2STD-V.SECRET-U       ( vault -- field ) _O2STD-V-SECRET-U + ;
: _O2STD-V.BLOCK-STATUS   ( vault -- field )
    _O2STD-V-BLOCK-STATUS + ;
: _O2STD-V.EXPECTED       ( vault -- field ) _O2STD-V-EXPECTED + ;
: _O2STD-V.INPUT-A        ( vault -- field ) _O2STD-V-INPUT-A + ;
: _O2STD-V.INPUT-U        ( vault -- field ) _O2STD-V-INPUT-U + ;
: _O2STD-V.CALLBACK-XT    ( vault -- field )
    _O2STD-V-CALLBACK-XT + ;
: _O2STD-V.CALLBACK-CONTEXT
  ( vault -- field )
    _O2STD-V-CALLBACK-CONTEXT + ;
: _O2STD-V.CALLBACK-DEPTH ( vault -- field )
    _O2STD-V-CALLBACK-DEPTH + ;
: _O2STD-V.CALLBACK-RESULT
  ( vault -- field )
    _O2STD-V-CALLBACK-RESULT + ;

: _O2STD-V.RID     ( vault -- address ) _O2STD-V-RID + ;
: _O2STD-V.SECRET  ( vault -- address ) _O2STD-V-SECRET + ;
: _O2STD-V.BORROW  ( vault -- address ) _O2STD-V-BORROW + ;

: CVAULT-PLAINTEXT-SIZE  ( secret-capacity -- plaintext-u|0 )
    DUP 0> 0= IF DROP 0 EXIT THEN
    DUP CVAULT-SECRET-CAPACITY-MAX U> IF DROP 0 EXIT THEN
    CVAULT-PLAINTEXT-HEADER-SIZE + ;

\ These two geometry words are sufficient for fixtures that size generic
\ storage while remaining independent of the production sealed/VFS backing.
: CVAULT-RECORD-SIZE  ( secret-capacity -- record-u|0 )
    CVAULT-PLAINTEXT-SIZE ;

: CVAULT-BACKING-SIZE  ( secret-capacity -- backing-u|0 )
    CVAULT-PLAINTEXT-SIZE ;

\ =====================================================================
\  Vault validation and operation admission
\ =====================================================================

: _O2STD-CALLER>VAULT  ( caller-status -- vault-status )
    DUP CALLER-SPAN-S-OK = IF DROP CVAULT-S-OK EXIT THEN
    DUP CALLER-SPAN-S-RANGE = IF DROP CVAULT-S-RANGE EXIT THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP CVAULT-S-PROTECTED EXIT
    THEN
    DROP CVAULT-S-PLATFORM ;

: _O2STD-ADMIT-SPAN  ( address length -- status )
    CALLER-SPAN-STATUS _O2STD-CALLER>VAULT ;

: _O2STD-BLOCKING?  ( status -- flag )
    DUP CVAULT-S-CORRUPT =
    OVER CVAULT-S-UNSUPPORTED = OR
    OVER CVAULT-S-IO = OR
    OVER CVAULT-S-RECOVERY = OR
    OVER CVAULT-S-ROLLBACK = OR
    SWAP CVAULT-S-INTERNAL = OR ;

: _O2STD-BLOCKING-NORMALIZE  ( status -- blocking-status )
    DUP CVAULT-STATUS-VALID? 0= IF
        DROP CVAULT-S-INTERNAL EXIT
    THEN
    DUP _O2STD-BLOCKING? IF EXIT THEN
    DROP CVAULT-S-RECOVERY ;

: _O2STD-VAULT-SHAPE?  ( vault -- flag )
    DUP _O2STD-V.MAGIC @ _O2STD-VAULT-MAGIC <> IF
        DROP 0 EXIT
    THEN
    DUP _O2STD-V.FLAGS @ DUP _O2STD-VF-CONFIGURED AND 0= IF
        2DROP 0 EXIT
    THEN
    _O2STD-VF-KNOWN INVERT AND IF DROP 0 EXIT THEN
    DUP _O2STD-V.CAPACITY @ DUP 0> 0= IF
        2DROP 0 EXIT
    THEN
    CVAULT-SECRET-CAPACITY-MAX U> IF DROP 0 EXIT THEN
    DUP _O2STD-V.FLAGS @ _O2STD-VF-BLOCKED AND IF
        DUP _O2STD-V.BLOCK-STATUS @ _O2STD-BLOCKING? 0= IF
            DROP 0 EXIT
        THEN
    ELSE
        DUP _O2STD-V.BLOCK-STATUS @ IF DROP 0 EXIT THEN
    THEN

    DUP _O2STD-V.STATE @ 0= IF
        DUP _O2STD-V.GENERATION @ 0=
        OVER _O2STD-V.KIND @ 0= AND
        OVER _O2STD-V.SECRET-U @ 0= AND
        SWAP _O2STD-V.RID RID-ZERO? AND EXIT
    THEN
    DUP _O2STD-V.STATE @ CVAULT-STATE-PRESENT = IF
        DUP _O2STD-V.GENERATION @ 0>
        OVER _O2STD-V.KIND @ 0> AND
        OVER _O2STD-V.SECRET-U @ DUP 0> >R
        2 PICK _O2STD-V.CAPACITY @ U> 0= R> AND AND
        SWAP _O2STD-V.RID RID-PRESENT? AND EXIT
    THEN
    DUP _O2STD-V.STATE @ CVAULT-STATE-TOMBSTONE = IF
        DUP _O2STD-V.GENERATION @ 0>
        OVER _O2STD-V.KIND @ 0> AND
        OVER _O2STD-V.SECRET-U @ 0= AND
        SWAP _O2STD-V.RID RID-PRESENT? AND EXIT
    THEN
    DROP 0 ;

: _O2STD-VAULT-STATUS  ( vault -- status )
    DUP CVAULT-SIZE _O2STD-ADMIT-SPAN
    ?DUP IF NIP EXIT THEN
    _O2STD-VAULT-SHAPE? IF
        CVAULT-S-OK
    ELSE
        CVAULT-S-INVALID
    THEN ;

: CVAULT-VALID?  ( vault -- flag )
    _O2STD-VAULT-STATUS CVAULT-S-OK = ;

: CVAULT-BLOCKED?  ( vault -- flag )
    DUP _O2STD-VAULT-STATUS CVAULT-S-OK <> IF
        DROP 0 EXIT
    THEN
    _O2STD-V.FLAGS @ _O2STD-VF-BLOCKED AND 0<> ;

: CVAULT-LAST-STATUS@  ( vault -- status )
    DUP _O2STD-VAULT-STATUS ?DUP IF NIP EXIT THEN
    _O2STD-V.LAST-STATUS @ ;

: CVAULT-SECRET-CAPACITY@
  ( vault -- secret-capacity status )
    DUP _O2STD-VAULT-STATUS ?DUP IF
        NIP 0 SWAP EXIT
    THEN
    DUP _O2STD-V.FLAGS @ _O2STD-VF-BUSY AND IF
        DROP 0 CVAULT-S-BUSY EXIT
    THEN
    _O2STD-V.CAPACITY @ CVAULT-S-OK ;

: _O2STD-TRANSIENT-CLEAR  ( vault -- )
    DUP _O2STD-V.EXPECTED 0 SWAP !
    DUP _O2STD-V.INPUT-A 0 SWAP !
    DUP _O2STD-V.INPUT-U 0 SWAP !
    DUP _O2STD-V.CALLBACK-XT 0 SWAP !
    DUP _O2STD-V.CALLBACK-CONTEXT 0 SWAP !
    DUP _O2STD-V.CALLBACK-DEPTH 0 SWAP !
    _O2STD-V.CALLBACK-RESULT 0 SWAP ! ;

: _O2STD-FINISH  ( status vault -- status )
    >R
    DUP CVAULT-STATUS-VALID? 0= IF
        DROP CVAULT-S-INTERNAL
    THEN
    R@ _O2STD-TRANSIENT-CLEAR
    R@ _O2STD-V.FLAGS DUP @
        _O2STD-VF-BUSY INVERT AND SWAP !
    DUP _O2STD-BLOCKING? IF
        DUP _O2STD-BLOCKING-NORMALIZE
            R@ _O2STD-V.BLOCK-STATUS !
        R@ _O2STD-V.FLAGS DUP @
            _O2STD-VF-BLOCKED OR SWAP !
    THEN
    DUP R@ _O2STD-V.LAST-STATUS !
    R> DROP ;

: _O2STD-OP-BEGIN  ( vault -- status )
    DUP _O2STD-VAULT-STATUS ?DUP IF NIP EXIT THEN
    DUP _O2STD-V.FLAGS @ _O2STD-VF-BUSY AND IF
        DROP CVAULT-S-BUSY EXIT
    THEN
    DUP _O2STD-V.FLAGS @ _O2STD-VF-BLOCKED AND IF
        _O2STD-V.BLOCK-STATUS @ EXIT
    THEN
    DUP _O2STD-V.FLAGS DUP @
        _O2STD-VF-BUSY OR SWAP !
    DROP CVAULT-S-OK ;

: _O2STD-RID-STATUS  ( rid vault -- status )
    >R
    DUP RID-SIZE _O2STD-ADMIT-SPAN ?DUP IF
        NIP R> DROP EXIT
    THEN
    DUP RID-PRESENT? 0= IF
        DROP R> DROP CVAULT-S-INVALID EXIT
    THEN
    DUP RID-SIZE R@ CVAULT-SIZE MSPAN-OVERLAP? IF
        DROP R> DROP CVAULT-S-INVALID EXIT
    THEN
    DROP R> DROP CVAULT-S-OK ;

: _O2STD-SECRET-STATUS
  ( secret-a secret-u vault -- status )
    >R
    DUP 0> 0= IF
        2DROP R> DROP CVAULT-S-INVALID EXIT
    THEN
    DUP R@ _O2STD-V.CAPACITY @ U> IF
        2DROP R> DROP CVAULT-S-CAPACITY EXIT
    THEN
    2DUP _O2STD-ADMIT-SPAN ?DUP IF
        >R 2DROP R> R> DROP EXIT
    THEN
    2DUP R@ CVAULT-SIZE MSPAN-OVERLAP? IF
        2DROP R> DROP CVAULT-S-INVALID EXIT
    THEN
    2DROP R> DROP CVAULT-S-OK ;

: _O2STD-LOOKUP-STATUS  ( rid vault -- status )
    >R
    DUP R@ _O2STD-RID-STATUS ?DUP IF
        NIP R> DROP EXIT
    THEN
    R@ _O2STD-V.STATE @ 0= IF
        DROP R> DROP CVAULT-S-ABSENT EXIT
    THEN
    DUP R@ _O2STD-V.RID RID= 0= IF
        DROP R> DROP CVAULT-S-ABSENT EXIT
    THEN
    DROP
    R@ _O2STD-V.STATE @ CVAULT-STATE-TOMBSTONE = IF
        R> DROP CVAULT-S-REVOKED EXIT
    THEN
    R> DROP CVAULT-S-OK ;

: _O2STD-NEXT-GENERATION  ( generation -- next|0 )
    DUP -1 1 RSHIFT = IF DROP 0 ELSE 1+ THEN ;

: _O2STD-DROP4  ( x1 x2 x3 x4 -- )
    2DROP 2DROP ;

: _O2STD-ZERO-GENERATION  ( status -- 0 status )
    0 SWAP ;

: _O2STD-ZERO-WITH  ( status -- 0 0 0 status )
    >R 0 0 0 R> ;

: _O2STD-ZERO-RECOVERY  ( status -- 0 0 status )
    >R 0 0 R> ;

\ =====================================================================
\  Stable test setup and blocked-state injection
\ =====================================================================

: O2S-TEST-CVAULT-INIT
  ( secret-capacity vault -- status )
    >R
    DUP 0> 0= IF
        DROP R> DROP CVAULT-S-INVALID EXIT
    THEN
    DUP CVAULT-SECRET-CAPACITY-MAX U> IF
        DROP R> DROP CVAULT-S-CAPACITY EXIT
    THEN
    R@ CVAULT-SIZE _O2STD-ADMIT-SPAN ?DUP IF
        NIP R> DROP EXIT
    THEN
    R@ CVAULT-SIZE 0 FILL
    _O2STD-VAULT-MAGIC R@ _O2STD-V.MAGIC !
    _O2STD-VF-CONFIGURED R@ _O2STD-V.FLAGS !
    DUP R@ _O2STD-V.CAPACITY !
    CVAULT-S-OK R@ _O2STD-V.LAST-STATUS !
    DROP R> DROP CVAULT-S-OK ;

: O2S-TEST-CVAULT-BLOCK  ( status vault -- )
    DUP _O2STD-VAULT-STATUS CVAULT-S-OK <> IF
        2DROP EXIT
    THEN
    DUP _O2STD-V.FLAGS @ _O2STD-VF-BUSY AND IF
        2DROP EXIT
    THEN
    >R
    _O2STD-BLOCKING-NORMALIZE
    DUP R@ _O2STD-V.BLOCK-STATUS !
    R@ _O2STD-V.LAST-STATUS !
    R@ _O2STD-V.FLAGS DUP @
        _O2STD-VF-BLOCKED OR SWAP !
    R> DROP ;

\ =====================================================================
\  In-memory vault mutation and borrow operations
\ =====================================================================

: CVAULT-CREATE
  ( rid kind secret-a secret-u vault -- generation status )
    >R
    R@ _O2STD-OP-BEGIN DUP IF
        >R _O2STD-DROP4 R> R> DROP
        _O2STD-ZERO-GENERATION EXIT
    THEN
    DROP
    3 PICK R@ _O2STD-RID-STATUS ?DUP IF
        >R _O2STD-DROP4 R> R@ _O2STD-FINISH
        R> DROP _O2STD-ZERO-GENERATION EXIT
    THEN
    2 PICK 0> 0= IF
        _O2STD-DROP4
        CVAULT-S-INVALID R@ _O2STD-FINISH
        R> DROP _O2STD-ZERO-GENERATION EXIT
    THEN
    OVER OVER R@ _O2STD-SECRET-STATUS ?DUP IF
        >R _O2STD-DROP4 R> R@ _O2STD-FINISH
        R> DROP _O2STD-ZERO-GENERATION EXIT
    THEN
    R@ _O2STD-V.STATE @ IF
        _O2STD-DROP4
        CVAULT-S-CONFLICT R@ _O2STD-FINISH
        R> DROP _O2STD-ZERO-GENERATION EXIT
    THEN

    3 PICK R@ _O2STD-V.RID RID-COPY
    2 PICK R@ _O2STD-V.KIND !
    OVER R@ _O2STD-V.INPUT-A !
    DUP R@ _O2STD-V.INPUT-U !
    R@ _O2STD-V.INPUT-A @
    R@ _O2STD-V.SECRET
    R@ _O2STD-V.INPUT-U @ MOVE
    R@ _O2STD-V.INPUT-U @ R@ _O2STD-V.SECRET-U !
    1 R@ _O2STD-V.GENERATION !
    CVAULT-STATE-PRESENT R@ _O2STD-V.STATE !
    _O2STD-DROP4

    R@ _O2STD-V.GENERATION @
    CVAULT-S-OK R@ _O2STD-FINISH
    R> DROP ;

: CVAULT-REPLACE
  \ ( rid expected-generation secret-a secret-u vault
  \   -- generation status )
    >R
    R@ _O2STD-OP-BEGIN DUP IF
        >R _O2STD-DROP4 R> R> DROP
        _O2STD-ZERO-GENERATION EXIT
    THEN
    DROP
    3 PICK R@ _O2STD-RID-STATUS ?DUP IF
        >R _O2STD-DROP4 R> R@ _O2STD-FINISH
        R> DROP _O2STD-ZERO-GENERATION EXIT
    THEN
    2 PICK 0> 0= IF
        _O2STD-DROP4
        CVAULT-S-INVALID R@ _O2STD-FINISH
        R> DROP _O2STD-ZERO-GENERATION EXIT
    THEN
    OVER OVER R@ _O2STD-SECRET-STATUS ?DUP IF
        >R _O2STD-DROP4 R> R@ _O2STD-FINISH
        R> DROP _O2STD-ZERO-GENERATION EXIT
    THEN
    3 PICK R@ _O2STD-LOOKUP-STATUS ?DUP IF
        >R _O2STD-DROP4 R> R@ _O2STD-FINISH
        R> DROP _O2STD-ZERO-GENERATION EXIT
    THEN
    2 PICK R@ _O2STD-V.GENERATION @ <> IF
        _O2STD-DROP4
        CVAULT-S-CONFLICT R@ _O2STD-FINISH
        R> DROP _O2STD-ZERO-GENERATION EXIT
    THEN
    R@ _O2STD-V.GENERATION @
        _O2STD-NEXT-GENERATION DUP 0= IF
        DROP _O2STD-DROP4
        CVAULT-S-RANGE R@ _O2STD-FINISH
        R> DROP _O2STD-ZERO-GENERATION EXIT
    THEN
    R@ _O2STD-V.EXPECTED !

    OVER R@ _O2STD-V.INPUT-A !
    DUP R@ _O2STD-V.INPUT-U !
    R@ _O2STD-V.SECRET
        R@ _O2STD-V.CAPACITY @ 0 FILL
    R@ _O2STD-V.INPUT-A @
    R@ _O2STD-V.SECRET
    R@ _O2STD-V.INPUT-U @ MOVE
    R@ _O2STD-V.INPUT-U @ R@ _O2STD-V.SECRET-U !
    R@ _O2STD-V.EXPECTED @ R@ _O2STD-V.GENERATION !
    _O2STD-DROP4

    R@ _O2STD-V.GENERATION @
    CVAULT-S-OK R@ _O2STD-FINISH
    R> DROP ;

: CVAULT-REVOKE
  ( rid expected-generation vault -- generation status )
    >R
    R@ _O2STD-OP-BEGIN DUP IF
        >R 2DROP R> R> DROP
        _O2STD-ZERO-GENERATION EXIT
    THEN
    DROP
    OVER R@ _O2STD-RID-STATUS ?DUP IF
        >R 2DROP R> R@ _O2STD-FINISH
        R> DROP _O2STD-ZERO-GENERATION EXIT
    THEN
    DUP 0> 0= IF
        2DROP
        CVAULT-S-INVALID R@ _O2STD-FINISH
        R> DROP _O2STD-ZERO-GENERATION EXIT
    THEN
    OVER R@ _O2STD-LOOKUP-STATUS ?DUP IF
        >R 2DROP R> R@ _O2STD-FINISH
        R> DROP _O2STD-ZERO-GENERATION EXIT
    THEN
    DUP R@ _O2STD-V.GENERATION @ <> IF
        2DROP
        CVAULT-S-CONFLICT R@ _O2STD-FINISH
        R> DROP _O2STD-ZERO-GENERATION EXIT
    THEN
    R@ _O2STD-V.GENERATION @
        _O2STD-NEXT-GENERATION DUP 0= IF
        DROP 2DROP
        CVAULT-S-RANGE R@ _O2STD-FINISH
        R> DROP _O2STD-ZERO-GENERATION EXIT
    THEN
    R@ _O2STD-V.EXPECTED !
    2DROP

    R@ _O2STD-V.SECRET
        R@ _O2STD-V.CAPACITY @ 0 FILL
    0 R@ _O2STD-V.SECRET-U !
    CVAULT-STATE-TOMBSTONE R@ _O2STD-V.STATE !
    R@ _O2STD-V.EXPECTED @ R@ _O2STD-V.GENERATION !

    R@ _O2STD-V.GENERATION @
    CVAULT-S-OK R@ _O2STD-FINISH
    R> DROP ;

-3202 CONSTANT _O2STD-E-CONSUMER-STACK
0x4F325354434F4E53 CONSTANT _O2STD-CONSUMER-CANARY

: _O2STD-CONSUMER-INVOKE  ( vault -- consumer-result )
    >R
    DEPTH R@ _O2STD-V.CALLBACK-DEPTH !
    _O2STD-CONSUMER-CANARY
    R@
    R@ _O2STD-V.BORROW
    R@ _O2STD-V.SECRET-U @
    R@ _O2STD-V.KIND @
    R@ _O2STD-V.GENERATION @
    R@ _O2STD-V.CALLBACK-CONTEXT @
    R@ _O2STD-V.CALLBACK-XT @ EXECUTE
    DEPTH R@ _O2STD-V.CALLBACK-DEPTH @ 3 + <> IF
        _O2STD-E-CONSUMER-STACK THROW
    THEN
    2 PICK _O2STD-CONSUMER-CANARY <> IF
        _O2STD-E-CONSUMER-STACK THROW
    THEN
    1 PICK R@ <> IF
        _O2STD-E-CONSUMER-STACK THROW
    THEN
    >R 2DROP R>
    R> DROP ;

: _O2STD-CONSUMER-SAFE  ( vault -- consumer-result status )
    ['] _O2STD-CONSUMER-INVOKE CATCH
    DUP IF
        2DROP 0 CVAULT-S-CALLBACK
    ELSE
        DROP CVAULT-S-OK
    THEN ;

: CVAULT-WITH
  \ ( rid consumer-xt consumer-context vault
  \   -- generation kind consumer-result status )
    >R
    R@ _O2STD-OP-BEGIN DUP IF
        >R 2DROP DROP R> R> DROP
        _O2STD-ZERO-WITH EXIT
    THEN
    DROP
    2 PICK R@ _O2STD-RID-STATUS ?DUP IF
        >R 2DROP DROP R> R@ _O2STD-FINISH
        R> DROP _O2STD-ZERO-WITH EXIT
    THEN
    OVER 0= IF
        2DROP DROP
        CVAULT-S-INVALID R@ _O2STD-FINISH
        R> DROP _O2STD-ZERO-WITH EXIT
    THEN
    2 PICK R@ _O2STD-LOOKUP-STATUS ?DUP IF
        >R 2DROP DROP R> R@ _O2STD-FINISH
        R> DROP _O2STD-ZERO-WITH EXIT
    THEN

    OVER R@ _O2STD-V.CALLBACK-XT !
    DUP R@ _O2STD-V.CALLBACK-CONTEXT !
    2DROP DROP
    R@ _O2STD-V.BORROW
        R@ _O2STD-V.CAPACITY @ 0 FILL
    R@ _O2STD-V.SECRET
    R@ _O2STD-V.BORROW
    R@ _O2STD-V.SECRET-U @ MOVE

    R@ _O2STD-CONSUMER-SAFE
    R@ _O2STD-V.BORROW
        R@ _O2STD-V.CAPACITY @ 0 FILL
    DUP IF
        NIP
        R@ _O2STD-FINISH
        R> DROP _O2STD-ZERO-WITH EXIT
    THEN
    DROP
    DUP R@ _O2STD-V.CALLBACK-RESULT !
    DROP

    R@ _O2STD-V.GENERATION @
    R@ _O2STD-V.KIND @
    R@ _O2STD-V.CALLBACK-RESULT @
    CVAULT-S-OK R@ _O2STD-FINISH
    R> DROP ;

: CVAULT-RECOVER
  ( expected-rid vault -- generation state status )
    >R
    R@ _O2STD-VAULT-STATUS ?DUP IF
        NIP R> DROP _O2STD-ZERO-RECOVERY EXIT
    THEN
    R@ _O2STD-V.FLAGS @ _O2STD-VF-BUSY AND IF
        DROP R> DROP
        CVAULT-S-BUSY _O2STD-ZERO-RECOVERY EXIT
    THEN
    R@ _O2STD-V.FLAGS @ _O2STD-VF-BLOCKED AND 0= IF
        DROP R> DROP
        CVAULT-S-INVALID _O2STD-ZERO-RECOVERY EXIT
    THEN
    DUP R@ _O2STD-RID-STATUS ?DUP IF
        NIP R> DROP _O2STD-ZERO-RECOVERY EXIT
    THEN
    DUP R@ _O2STD-V.RID RID= 0= IF
        DROP R> DROP
        CVAULT-S-CONFLICT _O2STD-ZERO-RECOVERY EXIT
    THEN
    DROP
    R@ _O2STD-V.FLAGS DUP @
        _O2STD-VF-BUSY OR SWAP !

    R@ _O2STD-V.STATE @ CVAULT-STATE-PRESENT = IF
        R@ _O2STD-V.FLAGS DUP @
            _O2STD-VF-BLOCKED _O2STD-VF-BUSY OR
            INVERT AND SWAP !
        0 R@ _O2STD-V.BLOCK-STATUS !
        CVAULT-S-OK R@ _O2STD-V.LAST-STATUS !
        R@ _O2STD-V.GENERATION @
        R@ _O2STD-V.STATE @
        CVAULT-S-OK
        R> DROP EXIT
    THEN
    R@ _O2STD-V.STATE @ CVAULT-STATE-TOMBSTONE = IF
        R@ _O2STD-V.FLAGS DUP @
            _O2STD-VF-BLOCKED _O2STD-VF-BUSY OR
            INVERT AND SWAP !
        0 R@ _O2STD-V.BLOCK-STATUS !
        CVAULT-S-REVOKED R@ _O2STD-V.LAST-STATUS !
        R@ _O2STD-V.GENERATION @
        R@ _O2STD-V.STATE @
        CVAULT-S-REVOKED
        R> DROP EXIT
    THEN

    R@ _O2STD-V.FLAGS DUP @
        _O2STD-VF-BUSY INVERT AND SWAP !
    CVAULT-S-RECOVERY DUP
        R@ _O2STD-V.BLOCK-STATUS !
    R@ _O2STD-V.LAST-STATUS !
    R> DROP
    CVAULT-S-RECOVERY _O2STD-ZERO-RECOVERY ;

\ =====================================================================
\  Geometry checks
\ =====================================================================

1 CELLS 8 <> [IF]
    ." OAuth session dependency cell-size mismatch" CR ABORT
[THEN]

_O2STD-V-BORROW CVAULT-SECRET-CAPACITY-MAX +
    CVAULT-SIZE <> [IF]
    ." OAuth session dependency vault geometry mismatch" CR ABORT
[THEN]
