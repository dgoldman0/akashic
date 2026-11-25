\ =====================================================================
\  passphrase-keyring.f - A root key sealed under the user's passphrase
\ =====================================================================
\  A keyring holds one random 32-byte root key in a file, sealed under a
\  key derived from the user's passphrase with PBKDF2-HMAC-SHA-256 at the
\  iteration count the file records, so the count can rise for keyrings
\  made later.  While unlocked, the keyring lends its root key through the
\  sealed-record resolver contract, which the credential vault uses; lock
\  wipes it.  A changed passphrase seals the same root key again, so the
\  secrets sealed under it stay readable.
\
\  Deriving the key takes seconds, so unlock, setup and change start a
\  derivation and KEYRING-STEP runs it in steps of a size the caller
\  chooses; an interactive owner such as Desk draws between steps.  A
\  wrong passphrase fails the sealed record's authentication and leaves
\  the keyring locked.
\
\  A resolver call while the keyring is locked answers that no key is
\  there and marks the keyring wanted, so its owner can ask for the
\  passphrase; the vault reports CVAULT-S-LOCKED and its caller retries.
\
\  A file of another size or header reads as damaged, a state of its
\  own.  A damaged keyring, or a locked one whose passphrase is lost,
\  can start over: a new keyring with a new id and root key replaces the
\  file once its key is derived, sealed and written, so a cancel or a
\  failure leaves the old file as it was.  Secrets sealed under the old
\  root key name the old id, which the resolver no longer lends, so they
\  read as an unknown key and their owners ask for them afresh.
\
\  The file is one fixed-size record, written by checked replacement:
\    magic "AKPKRNG1", version, iterations, revision    4 x 8 bytes
\    salt                                                32 bytes
\    keyring id                                          32 bytes
\    the root key's sealed record (sealed-record.f)      208 bytes
\  The sealed record's purpose is the magic, its record id the keyring
\  id, its revision the header's, and its key id the SHA-256 of the
\  header's first 64 bytes, so the derivation's parameters are bound to
\  the record they open: a changed count or salt reads as a corrupt file,
\  never as a wrong passphrase.  The keyring id is the key id the vault
\  names the root key by.
\
\  The keyring owns no prompt, screen or policy for when to ask.
\
\  Public API:
\    KEYRING-SIZE                         ( -- u )
\    KEYRING-INIT   ( path-a path-u place keyring -- status )
\    KEYRING-FINI   ( keyring -- )
\    KEYRING-STATE@ ( keyring -- state )
\    KEYRING-ID     ( keyring -- a u )
\    KEYRING-ITERATIONS@ ( keyring -- u )
\    KEYRING-SETUP  ( pass-a pass-u iterations keyring -- status )
\    KEYRING-UNLOCK ( pass-a pass-u keyring -- status )
\    KEYRING-CHANGE ( pass-a pass-u iterations keyring -- status )
\    KEYRING-START-OVER ( pass-a pass-u iterations keyring -- status )
\    KEYRING-STEP   ( budget keyring -- status )
\    KEYRING-PROGRESS ( keyring -- done total )
\    KEYRING-CANCEL ( keyring -- )
\    KEYRING-LOCK   ( keyring -- )
\    KEYRING-RESOLVER ( key-id u consumer-xt consumer-context keyring
\                       -- status )
\    KEYRING-WANTED? ( keyring -- flag )
\    KEYRING-WANT-CLEAR ( keyring -- )
\ =====================================================================

PROVIDED akashic-pass-keyring

REQUIRE pbkdf2-sha256.f
REQUIRE sealed-record.f
REQUIRE ../math/sha256.f
REQUIRE ../math/entropy.f
REQUIRE ../utils/memory-span.f
REQUIRE ../utils/fs/places.f
REQUIRE ../utils/fs/place-replace.f

0 CONSTANT KEYRING-S-OK
1 CONSTANT KEYRING-S-INVALID
2 CONSTANT KEYRING-S-STATE       \ the keyring's state refuses the call
3 CONSTANT KEYRING-S-PENDING     \ the derivation has iterations left
4 CONSTANT KEYRING-S-WRONG       \ the passphrase does not open the key
5 CONSTANT KEYRING-S-IO
6 CONSTANT KEYRING-S-CORRUPT
7 CONSTANT KEYRING-S-CRYPTO
8 CONSTANT KEYRING-S-ENTROPY
9 CONSTANT KEYRING-S-CAPACITY

0 CONSTANT KEYRING-ABSENT          \ no file yet: set it up first
1 CONSTANT KEYRING-LOCKED
2 CONSTANT KEYRING-UNLOCKING
3 CONSTANT KEYRING-SETTING-UP
4 CONSTANT KEYRING-CHANGING
5 CONSTANT KEYRING-UNLOCKED
6 CONSTANT KEYRING-DAMAGED         \ the file is there but unreadable

\ The count a new keyring takes unless its owner chooses another: about
\ 6.6 s on MegaPad at 100 MHz (docs/security/pbkdf2-sha256.md).
100000 CONSTANT KEYRING-ITERATIONS-DEFAULT
32 CONSTANT KEYRING-ID-SIZE

0x414B504B524E4731 CONSTANT _KR-MAGIC      \ "AKPKRNG1"
1 CONSTANT _KR-VERSION
32 SEALED-RECORD-SIZE CONSTANT _KR-SEALED-U
96 CONSTANT _KR-HEADER-U
_KR-HEADER-U _KR-SEALED-U + CONSTANT KEYRING-FILE-SIZE

\ The file image's fields.
 0 CONSTANT _KRF-MAGIC
 8 CONSTANT _KRF-VERSION
16 CONSTANT _KRF-ITERATIONS
24 CONSTANT _KRF-REVISION
32 CONSTANT _KRF-SALT
64 CONSTANT _KRF-ID
96 CONSTANT _KRF-SEALED

\ =====================================================================
\  The caller-owned keyring
\ =====================================================================
\  Header cells, the file as read and the one being made, the root key
\  while unlocked, a new root key while setup derives, the derived key
\  while a step finishes, the parameters' id, the sealed record's
\  descriptor, a checked replacement and the PBKDF2 workspace.  The
\  sealed record's workspace is borrowed from the heap only while a
\  record is sealed or opened, and wiped before it goes back.

  0 CONSTANT _KR-LIVE
  8 CONSTANT _KR-STATE
 16 CONSTANT _KR-PLACE
 24 CONSTANT _KR-PATH-A
 32 CONSTANT _KR-PATH-U
 40 CONSTANT _KR-WANTED      \ a resolver call found it locked
 48 CONSTANT _KR-TOTAL       \ iterations of the derivation running
 56 CONSTANT _KR-REMAINING   \ of those, still to run
 64 CONSTANT _KR-BEFORE      \ the state a cancelled derivation returns to
 72 CONSTANT _KR-FILE
_KR-FILE KEYRING-FILE-SIZE +             CONSTANT _KR-NEW
_KR-NEW KEYRING-FILE-SIZE +              CONSTANT _KR-ROOT
_KR-ROOT 32 +                            CONSTANT _KR-NEW-ROOT
_KR-NEW-ROOT 32 +                        CONSTANT _KR-KEK
_KR-KEK 32 +                             CONSTANT _KR-KEY-ID
_KR-KEY-ID 32 +                          CONSTANT _KR-DESC
_KR-DESC SEALED-RECORD-DESCRIPTOR-SIZE + CONSTANT _KR-REPL
_KR-REPL VREPL-SIZE +                    CONSTANT _KR-PBKDF2
_KR-PBKDF2 32 PBKDF2-SHA256-WORKSPACE-SIZE + CONSTANT KEYRING-SIZE

0x31474E524B504B5F CONSTANT _KR-LIVE-MAGIC

: _KR-BE64!  ( u a -- )
    8 0 DO
        OVER 56 I 8 * - RSHIFT 255 AND OVER I + C!
    LOOP 2DROP ;

: _KR-BE64@  ( a -- u )
    0 8 0 DO 8 LSHIFT OVER I + C@ OR LOOP NIP ;

: _KR-VALID?  ( keyring -- flag )
    DUP 0= IF EXIT THEN
    DUP KEYRING-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    _KR-LIVE + @ _KR-LIVE-MAGIC = ;

: KEYRING-STATE@  ( keyring -- state )  _KR-STATE + @ ;
: KEYRING-WANTED?  ( keyring -- flag )  _KR-WANTED + @ 0<> ;
: KEYRING-WANT-CLEAR  ( keyring -- )  0 SWAP _KR-WANTED + ! ;
: KEYRING-ID  ( keyring -- a u )  _KR-FILE + _KRF-ID + KEYRING-ID-SIZE ;
: KEYRING-ITERATIONS@  ( keyring -- u )
    _KR-FILE + _KRF-ITERATIONS + _KR-BE64@ ;

: _KR-DERIVING?  ( state -- flag )
    DUP KEYRING-UNLOCKING = OVER KEYRING-SETTING-UP = OR
    SWAP KEYRING-CHANGING = OR ;

\ The keys a derivation holds: a new root key and the derived key.
: _KR-WIPE-DERIVED  ( keyring -- )
    DUP _KR-NEW-ROOT + 32 0 FILL  _KR-KEK + 32 0 FILL ;

\ =====================================================================
\  The file
\ =====================================================================

\ The header names this keyring's format and a count PBKDF2 can run.
: _KR-HEADER-OK?  ( image -- flag )
    DUP _KRF-MAGIC + _KR-BE64@ _KR-MAGIC =
    OVER _KRF-VERSION + _KR-BE64@ _KR-VERSION = AND
    OVER _KRF-ITERATIONS + _KR-BE64@ DUP 0> SWAP 0x7FFFFFFF <= AND AND
    SWAP _KRF-REVISION + _KR-BE64@ 0> AND ;

\ Settle a replacement a crash interrupted, so the read finds the file
\ the last change committed.  A place that refuses writing has none to
\ settle.
: _KR-RECOVER  ( keyring -- status )
    >R
    R@ _KR-PATH-A + @ R@ _KR-PATH-U + @ R@ _KR-PLACE + @ -1
        R@ _KR-REPL + PLACE-VREPL! IF R> DROP KEYRING-S-OK EXIT THEN
    R@ _KR-REPL + VREPL-RECOVER
    R> _KR-REPL + VREPL-FINI DROP
    DUP VREPL-S-OK = OVER VREPL-S-ROLLED-BACK = OR
    SWAP VREPL-S-COMMITTED-CLEANUP = OR
    IF KEYRING-S-OK ELSE KEYRING-S-IO THEN ;

VARIABLE _KRR-FD
VARIABLE _KRR-KR

\ Read the file into the image: KEYRING-ABSENT's state when there is
\ none, and KEYRING-DAMAGED's, with the image wiped, for a file of
\ another size or header.
: _KR-READ  ( keyring -- status state )
    _KRR-KR !
    _KRR-KR @ _KR-PATH-A + @ _KRR-KR @ _KR-PATH-U + @
    VFS-FF-READ _KRR-KR @ _KR-PLACE + @ PLACE-OPEN ?DUP IF
        NIP VFS-IOR-REASON VFS-R-NOENT = IF
            KEYRING-S-OK KEYRING-ABSENT
        ELSE
            KEYRING-S-IO KEYRING-ABSENT
        THEN EXIT
    THEN _KRR-FD !
    _KRR-FD @ VFS-SIZE KEYRING-FILE-SIZE <> IF
        _KRR-FD @ VFS-CLOSE? DROP KEYRING-S-OK KEYRING-DAMAGED EXIT
    THEN
    _KRR-KR @ _KR-FILE + KEYRING-FILE-SIZE _KRR-FD @ VFS-READ-EXACT
    _KRR-FD @ VFS-CLOSE? DROP
    IF KEYRING-S-IO KEYRING-ABSENT EXIT THEN
    _KRR-KR @ _KR-FILE + _KR-HEADER-OK? 0= IF
        _KRR-KR @ _KR-FILE + KEYRING-FILE-SIZE 0 FILL
        KEYRING-S-OK KEYRING-DAMAGED EXIT
    THEN
    KEYRING-S-OK KEYRING-LOCKED ;

\ Publish the new image as the keyring's file, by checked replacement.
: _KR-WRITE  ( keyring -- status )
    >R
    R@ _KR-PATH-A + @ R@ _KR-PATH-U + @ R@ _KR-PLACE + @ -1
        R@ _KR-REPL + PLACE-VREPL! IF R> DROP KEYRING-S-IO EXIT THEN
    R@ _KR-NEW + KEYRING-FILE-SIZE R@ _KR-REPL + VREPL-REPLACE
    R> _KR-REPL + VREPL-FINI DROP
    VREPL-S-OK = IF KEYRING-S-OK ELSE KEYRING-S-IO THEN ;

\ =====================================================================
\  The sealed root key
\ =====================================================================

\ The id the sealed record's key goes by: the SHA-256 of the image's
\ first 64 bytes, its magic, version, count, revision and salt.
: _KR-KEY-ID!  ( image keyring -- status )
    _KR-KEY-ID + >R 64 R> SHA256-HASH
    IF KEYRING-S-CRYPTO ELSE KEYRING-S-OK THEN ;

VARIABLE _KRK-XT
VARIABLE _KRK-CTX

\ The sealed record's resolver: the derived key, for the one call.
: _KR-KEK-RESOLVER  ( key-id u consumer-xt consumer-context keyring -- status )
    _KR-KEK + >R _KRK-CTX ! _KRK-XT ! 2DROP
    R> 32 _KRK-CTX @ _KRK-XT @ EXECUTE ;

VARIABLE _KRD-IMAGE
VARIABLE _KRD-KR

\ The descriptor for IMAGE's record, with INPUT and OUTPUT as given.
: _KR-DESC!  ( input input-u output output-cap image keyring -- )
    _KRD-KR ! _KRD-IMAGE !
    _KRD-KR @ _KR-DESC + >R
    R@ SEALED-RECORD-DESCRIPTOR-SIZE 0 FILL
    R@ SEALED-RECORD-D.OUTPUT-CAP !  R@ SEALED-RECORD-D.OUTPUT !
    R@ SEALED-RECORD-D.INPUT-U !     R@ SEALED-RECORD-D.INPUT !
    _KRD-KR @ _KR-KEY-ID +           R@ SEALED-RECORD-D.KEY-ID !
    _KRD-IMAGE @ _KRF-ID +           R@ SEALED-RECORD-D.RECORD-ID !
    _KR-MAGIC                        R@ SEALED-RECORD-D.PURPOSE !
    _KRD-IMAGE @ _KRF-REVISION + _KR-BE64@
                                     R@ SEALED-RECORD-D.REVISION !
    ['] _KR-KEK-RESOLVER             R@ SEALED-RECORD-D.RESOLVER-XT !
    _KRD-KR @                        R> SEALED-RECORD-D.RESOLVER-CONTEXT ! ;

VARIABLE _KRS-W

\ Run SEAL or OPEN (xt) over the descriptor, with a workspace borrowed
\ from the heap and wiped before it goes back.
: _KR-SEALED-CALL  ( xt keyring -- written status )
    SEALED-RECORD-WORKSPACE-SIZE ALLOCATE IF
        DROP 2DROP 0 SEALED-RECORD-S-CAPACITY EXIT
    THEN _KRS-W !
    _KR-DESC + _KRS-W @ ROT CATCH ?DUP IF
        >R 2DROP _KRS-W @ SEALED-RECORD-WORKSPACE-SIZE 0 FILL
        _KRS-W @ FREE R> THROW
    THEN
    _KRS-W @ SEALED-RECORD-WORKSPACE-SIZE 0 FILL _KRS-W @ FREE ;

\ Seal the 32-byte root key at ROOT-OFFSET in the keyring into the new
\ image.
: _KR-SEAL  ( root-offset keyring -- status )
    >R
    R@ + 32  R@ _KR-NEW + _KRF-SEALED + _KR-SEALED-U
    R@ _KR-NEW + R@ _KR-DESC!
    R@ _KR-NEW + R@ _KR-KEY-ID! ?DUP IF R> DROP EXIT THEN
    ['] SEALED-RECORD-SEAL R> _KR-SEALED-CALL
    SEALED-RECORD-S-OK <> IF DROP KEYRING-S-CRYPTO EXIT THEN
    _KR-SEALED-U <> IF KEYRING-S-CRYPTO ELSE KEYRING-S-OK THEN ;

\ Open the file image's record into the root key.
: _KR-OPEN  ( keyring -- status )
    >R
    R@ _KR-FILE + _KRF-SEALED + _KR-SEALED-U  R@ _KR-ROOT + 32
    R@ _KR-FILE + R@ _KR-DESC!
    R@ _KR-FILE + R@ _KR-KEY-ID! ?DUP IF R> DROP EXIT THEN
    ['] SEALED-RECORD-OPEN R> _KR-SEALED-CALL
    DUP SEALED-RECORD-S-AUTH = IF 2DROP KEYRING-S-WRONG EXIT THEN
    SEALED-RECORD-S-OK <> IF DROP KEYRING-S-CORRUPT EXIT THEN
    32 <> IF KEYRING-S-CORRUPT ELSE KEYRING-S-OK THEN ;

\ A new image for ITERATIONS and REVISION with a fresh salt; its id is a
\ fresh one for a new keyring, or the file's.
: _KR-NEW-IMAGE  ( iterations revision new-id? keyring -- status )
    >R
    R@ _KR-NEW + KEYRING-FILE-SIZE 0 FILL
    _KR-MAGIC R@ _KR-NEW + _KRF-MAGIC + _KR-BE64!
    _KR-VERSION R@ _KR-NEW + _KRF-VERSION + _KR-BE64!
    IF
        R@ _KR-NEW + _KRF-ID + KEYRING-ID-SIZE ENTROPY-FILL IF
            2DROP R> DROP KEYRING-S-ENTROPY EXIT
        THEN
    ELSE
        R@ _KR-FILE + _KRF-ID + R@ _KR-NEW + _KRF-ID + KEYRING-ID-SIZE MOVE
    THEN
    R@ _KR-NEW + _KRF-REVISION + _KR-BE64!
    R@ _KR-NEW + _KRF-ITERATIONS + _KR-BE64!
    R> _KR-NEW + _KRF-SALT + 32 ENTROPY-FILL
    IF KEYRING-S-ENTROPY ELSE KEYRING-S-OK THEN ;

\ Start deriving the key of IMAGE's parameters from the passphrase.
\ BEGIN runs the first iteration of the key's one block, so the steps
\ have one fewer to run.
: _KR-DERIVE  ( pass-a pass-u image keyring -- status )
    >R
    DUP _KRF-SALT + 32 ROT _KRF-ITERATIONS + _KR-BE64@
    DUP R@ _KR-TOTAL + !  DUP 1- R@ _KR-REMAINING + !
    32 R> _KR-PBKDF2 + PBKDF2-SHA256-BEGIN
    IF KEYRING-S-CRYPTO ELSE KEYRING-S-OK THEN ;

VARIABLE _KRS-NEXT

\ Start a derivation of IMAGE's key toward STATE; a cancel or a failure
\ returns to the state it starts from.
: _KR-START  ( pass-a pass-u image state keyring -- status )
    >R _KRS-NEXT !
    R@ KEYRING-STATE@ R@ _KR-BEFORE + !
    R@ _KR-DERIVE ?DUP IF R> _KR-WIPE-DERIVED EXIT THEN
    _KRS-NEXT @ R> _KR-STATE + !  KEYRING-S-PENDING ;

\ =====================================================================
\  Public words
\ =====================================================================

: KEYRING-INIT  ( path-a path-u place keyring -- status )
    DUP 0= IF 2DROP 2DROP KEYRING-S-INVALID EXIT THEN
    DUP KEYRING-SIZE MSPAN-NONWRAPPING? 0= IF
        2DROP 2DROP KEYRING-S-INVALID EXIT
    THEN
    >R
    R@ KEYRING-SIZE 0 FILL
    R@ _KR-PLACE + !  R@ _KR-PATH-U + !  R@ _KR-PATH-A + !
    _KR-LIVE-MAGIC R@ _KR-LIVE + !
    R@ _KR-RECOVER ?DUP IF R> KEYRING-SIZE 0 FILL EXIT THEN
    R@ _KR-READ R@ _KR-STATE + !
    DUP IF R> KEYRING-SIZE 0 FILL ELSE R> DROP THEN ;

: KEYRING-FINI  ( keyring -- )
    DUP _KR-VALID? 0= IF DROP EXIT THEN
    DUP KEYRING-STATE@ _KR-DERIVING? IF
        DUP _KR-PBKDF2 + PBKDF2-SHA256-ABANDON DROP
    THEN
    KEYRING-SIZE 0 FILL ;

\ Start deriving the key of a new keyring, with a new id, salt and root
\ key, in a keyring whose state allows one (FLAG).  The file changes
\ only when the derivation ends (_KR-FINISH).
: _KR-BEGIN-NEW  ( pass-a pass-u iterations keyring flag -- status )
    OVER _KR-VALID? 0= IF DROP 2DROP 2DROP KEYRING-S-INVALID EXIT THEN
    0= IF 2DROP 2DROP KEYRING-S-STATE EXIT THEN
    OVER 1 < IF 2DROP 2DROP KEYRING-S-INVALID EXIT THEN
    >R 1 -1 R@ _KR-NEW-IMAGE ?DUP IF NIP NIP R> DROP EXIT THEN
    R@ _KR-NEW-ROOT + 32 ENTROPY-FILL IF
        2DROP R> DROP KEYRING-S-ENTROPY EXIT
    THEN
    R@ _KR-NEW + KEYRING-SETTING-UP R> _KR-START ;

: KEYRING-SETUP  ( pass-a pass-u iterations keyring -- status )
    DUP DUP _KR-VALID? IF KEYRING-STATE@ KEYRING-ABSENT = ELSE DROP 0 THEN
    _KR-BEGIN-NEW ;

\ A new keyring in place of a damaged one, or of a locked one whose
\ passphrase is lost.  The derivation runs as a setup's does.
: KEYRING-START-OVER  ( pass-a pass-u iterations keyring -- status )
    DUP DUP _KR-VALID? IF
        KEYRING-STATE@ DUP KEYRING-LOCKED = SWAP KEYRING-DAMAGED = OR
    ELSE
        DROP 0
    THEN
    _KR-BEGIN-NEW ;

: KEYRING-UNLOCK  ( pass-a pass-u keyring -- status )
    DUP _KR-VALID? 0= IF DROP 2DROP KEYRING-S-INVALID EXIT THEN
    DUP KEYRING-STATE@ KEYRING-LOCKED <> IF
        DROP 2DROP KEYRING-S-STATE EXIT
    THEN
    >R R@ _KR-FILE + KEYRING-UNLOCKING R> _KR-START ;

: KEYRING-CHANGE  ( pass-a pass-u iterations keyring -- status )
    DUP _KR-VALID? 0= IF 2DROP 2DROP KEYRING-S-INVALID EXIT THEN
    DUP KEYRING-STATE@ KEYRING-UNLOCKED <> IF
        2DROP 2DROP KEYRING-S-STATE EXIT
    THEN
    OVER 1 < IF 2DROP 2DROP KEYRING-S-INVALID EXIT THEN
    >R
    R@ _KR-FILE + _KRF-REVISION + _KR-BE64@ 1+ 0 R@ _KR-NEW-IMAGE
    ?DUP IF NIP NIP R> DROP EXIT THEN
    R@ _KR-NEW + KEYRING-CHANGING R> _KR-START ;

: KEYRING-LOCK  ( keyring -- )
    DUP _KR-VALID? 0= IF DROP EXIT THEN
    DUP KEYRING-STATE@ KEYRING-UNLOCKED <> IF DROP EXIT THEN
    DUP _KR-ROOT + 32 0 FILL  KEYRING-LOCKED SWAP _KR-STATE + ! ;

: KEYRING-CANCEL  ( keyring -- )
    DUP _KR-VALID? 0= IF DROP EXIT THEN
    DUP KEYRING-STATE@ _KR-DERIVING? 0= IF DROP EXIT THEN
    DUP _KR-PBKDF2 + PBKDF2-SHA256-ABANDON DROP
    DUP _KR-WIPE-DERIVED
    DUP _KR-BEFORE + @ SWAP _KR-STATE + ! ;

: KEYRING-PROGRESS  ( keyring -- done total )
    DUP _KR-VALID? 0= IF DROP 0 0 EXIT THEN
    DUP KEYRING-STATE@ _KR-DERIVING? 0= IF DROP 0 0 EXIT THEN
    DUP _KR-TOTAL + @ SWAP _KR-REMAINING + @ OVER SWAP - SWAP ;

\ The derivation ended: open the file's record, or seal and write.
: _KR-FINISH  ( keyring -- status )
    >R
    R@ KEYRING-STATE@ KEYRING-UNLOCKING = IF
        R@ _KR-OPEN  R@ _KR-KEK + 32 0 FILL
        DUP IF
            R@ _KR-ROOT + 32 0 FILL  KEYRING-LOCKED R> _KR-STATE + ! EXIT
        THEN
        KEYRING-UNLOCKED R@ _KR-STATE + !  R> KEYRING-WANT-CLEAR EXIT
    THEN
    R@ KEYRING-STATE@ KEYRING-SETTING-UP = IF _KR-NEW-ROOT ELSE _KR-ROOT THEN
    R@ _KR-SEAL  R@ _KR-KEK + 32 0 FILL
    ?DUP 0= IF R@ _KR-WRITE THEN
    ?DUP IF
        R@ _KR-NEW-ROOT + 32 0 FILL
        R@ _KR-BEFORE + @ R> _KR-STATE + ! EXIT
    THEN
    R@ _KR-NEW + R@ _KR-FILE + KEYRING-FILE-SIZE MOVE
    R@ KEYRING-STATE@ KEYRING-SETTING-UP = IF
        R@ _KR-NEW-ROOT + R@ _KR-ROOT + 32 MOVE
        R@ _KR-NEW-ROOT + 32 0 FILL
    THEN
    KEYRING-UNLOCKED R@ _KR-STATE + !  R> KEYRING-WANT-CLEAR
    KEYRING-S-OK ;

: KEYRING-STEP  ( budget keyring -- status )
    DUP _KR-VALID? 0= IF 2DROP KEYRING-S-INVALID EXIT THEN
    DUP KEYRING-STATE@ _KR-DERIVING? 0= IF 2DROP KEYRING-S-STATE EXIT THEN
    >R R@ _KR-PBKDF2 + PBKDF2-SHA256-STEP ?DUP IF
        \ PBKDF2 wiped its workspace; the derivation is gone.
        2DROP R@ _KR-WIPE-DERIVED
        R@ _KR-BEFORE + @ R> _KR-STATE + ! KEYRING-S-CRYPTO EXIT
    THEN
    DUP R@ _KR-REMAINING + !
    IF R> DROP KEYRING-S-PENDING EXIT THEN
    R@ _KR-KEK + R@ _KR-PBKDF2 + PBKDF2-SHA256-FINISH IF
        R@ _KR-WIPE-DERIVED
        R@ _KR-BEFORE + @ R> _KR-STATE + ! KEYRING-S-CRYPTO EXIT
    THEN
    R> _KR-FINISH ;

\ The vault's resolver: the root key while unlocked, for this keyring's
\ id.  Locked, it lends nothing and marks the keyring wanted.
: KEYRING-RESOLVER  ( key-id u consumer-xt consumer-context keyring -- status )
    DUP _KR-VALID? 0= IF 2DROP 2DROP DROP SEALED-RECORD-S-KEY EXIT THEN
    DUP KEYRING-STATE@ KEYRING-UNLOCKED <> IF
        -1 SWAP _KR-WANTED + ! 2DROP 2DROP SEALED-RECORD-S-KEY EXIT
    THEN
    >R 2SWAP R@ KEYRING-ID COMPARE IF
        2DROP R> DROP SEALED-RECORD-S-KEY EXIT
    THEN
    R> _KR-ROOT + 32 ROT 3 ROLL EXECUTE ;
