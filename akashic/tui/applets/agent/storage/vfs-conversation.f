\ =====================================================================
\  vfs-conversation.f - Dual-generation VFS conversation snapshots
\ =====================================================================
\  Saves always target the inactive slot. Startup validates both complete
\  checksummed snapshots and chooses the newest valid generation.  Slot I/O
\  is exact and each publication is one guarded VFS transaction.  A store
\  guard also covers the module scratch state and generation selection, so
\  owner-core callers cannot interleave before the VFS transaction begins.
\  Allocation and VFS selection keep this adapter core-affine; the runtime
\  must separately serialize object lifetime against AVFSSTORE-FREE.
\ =====================================================================

PROVIDED akashic-agent-vfs-store

REQUIRE ../conversation-store.f
REQUIRE thread-codec.f
REQUIRE ../../../../utils/fs/vfs.f
REQUIRE ../../../../utils/generation-pair.f
REQUIRE ../../../../concurrency/guard.f

GUARD _avfs-store-guard

0 CONSTANT _AVS-STORE
_AVS-STORE AGENT-CONVERSATION-STORE-SIZE + CONSTANT _AVS-VFS
_AVS-VFS 8 + CONSTANT _AVS-PAIR
_AVS-PAIR GPAIR-SIZE + CONSTANT _AVS-FLAGS
_AVS-FLAGS 8 + CONSTANT _AVS-CANDIDATE-A
_AVS-CANDIDATE-A GPAIR-CANDIDATE-SIZE + CONSTANT _AVS-CANDIDATE-B
_AVS-CANDIDATE-B GPAIR-CANDIDATE-SIZE + CONSTANT AVFSSTORE-SIZE

: AVFSSTORE.VFS         ( store -- a ) _AVS-VFS + ;
: AVFSSTORE.PAIR        ( store -- pair ) _AVS-PAIR + ;
: AVFSSTORE.GENERATION  ( store -- a )
    AVFSSTORE.PAIR GPAIR.GENERATION ;
: AVFSSTORE.ACTIVE-SLOT ( store -- a )
    AVFSSTORE.PAIR GPAIR.ACTIVE-SLOT ;
: AVFSSTORE.FLAGS       ( store -- a ) _AVS-FLAGS + ;
: _AVFSSTORE-CANDIDATE-A  ( store -- candidate ) _AVS-CANDIDATE-A + ;
: _AVFSSTORE-CANDIDATE-B  ( store -- candidate ) _AVS-CANDIDATE-B + ;

: _AVFS-PATH-A  ( -- addr len ) S" /agent-thread-a.bin" ;
: _AVFS-PATH-B  ( -- addr len ) S" /agent-thread-b.bin" ;

\ Internal dependency vectors make every potentially-throwing boundary
\ explicit.  Production uses the ordinary VFS and codec words; deterministic
\ fault tests replace one vector at a time while the store guard is held.
VARIABLE _AVFS-USE-XT
VARIABLE _AVFS-OPEN-XT
VARIABLE _AVFS-CREATE-XT
VARIABLE _AVFS-READ-XT
VARIABLE _AVFS-WRITE-XT
VARIABLE _AVFS-CLOSE-XT
VARIABLE _AVFS-SYNC-XT
VARIABLE _AVFS-DECODE-XT
VARIABLE _AVFS-ENCODE-SIZE-XT
VARIABLE _AVFS-ENCODE-XT
VARIABLE _AVFS-CONV-FREE-XT
VARIABLE _AVFS-GUARD-RELEASE-XT

: _AVFS-RESET-DEPENDENCIES  ( -- )
    ['] VFS-USE             _AVFS-USE-XT !
    ['] VFS-OPEN            _AVFS-OPEN-XT !
    ['] VFS-CREATE          _AVFS-CREATE-XT !
    ['] VFS-READ-EXACT      _AVFS-READ-XT !
    ['] VFS-WRITE-EXACT     _AVFS-WRITE-XT !
    ['] VFS-CLOSE           _AVFS-CLOSE-XT !
    ['] VFS-SYNC            _AVFS-SYNC-XT !
    ['] ATHREAD-DECODE      _AVFS-DECODE-XT !
    ['] ATHREAD-ENCODE-SIZE _AVFS-ENCODE-SIZE-XT !
    ['] ATHREAD-ENCODE      _AVFS-ENCODE-XT !
    ['] ACONV-FREE          _AVFS-CONV-FREE-XT !
    ['] GUARD-RELEASE       _AVFS-GUARD-RELEASE-XT ! ;

_AVFS-RESET-DEPENDENCIES

VARIABLE _AVFS-CLEAN-IOR

: _AVFS-CLEAN-BEGIN  ( -- ) 0 _AVFS-CLEAN-IOR ! ;

: _AVFS-CLEAN-NOTE  ( ior -- )
    _AVFS-CLEAN-IOR @ 0= IF _AVFS-CLEAN-IOR ! ELSE DROP THEN ;

: _AVFS-CLEAN-PREFER-FIRST  ( first-ior next-ior -- ior )
    OVER IF DROP ELSE NIP THEN ;

: _AVFS-CODEC-STATUS  ( codec-status -- store-status )
    DUP ATHREAD-S-OK = IF DROP ACSTORE-S-OK EXIT THEN
    DUP ATHREAD-S-CAPACITY = IF DROP ACSTORE-S-CAPACITY EXIT THEN
    DUP ATHREAD-S-NOMEM = IF DROP ACSTORE-S-NOMEM EXIT THEN
    DROP ACSTORE-S-INVALID ;

VARIABLE _AVR-PA
VARIABLE _AVR-PU
VARIABLE _AVR-S
VARIABLE _AVR-OLD-VFS
VARIABLE _AVR-FD
VARIABLE _AVR-SIZE
VARIABLE _AVR-BUF
VARIABLE _AVR-CONV
VARIABLE _AVR-GEN
VARIABLE _AVR-STATUS
VARIABLE _AVR-CODEC-STATUS
VARIABLE _AVR-HAVE-OLD-VFS
VARIABLE _AVR-PRIMARY-IOR
VARIABLE _AVR-CLEAN-FD

: _AVR-CLEAN-CLOSE  ( -- ) _AVR-CLEAN-FD @ VFS-CLOSE ;
: _AVR-CLEAN-RESTORE  ( -- ) _AVR-OLD-VFS @ VFS-USE ;
: _AVR-CLEAN-FREE  ( -- ) _AVR-BUF @ FREE ;
: _AVR-CLEAN-CONV  ( -- ) _AVR-CONV @ ACONV-FREE ;

: _AVR-CLEAN-IO  ( -- cleanup-ior )
    _AVFS-CLEAN-BEGIN
    _AVR-FD @ IF
        _AVR-FD @ _AVR-CLEAN-FD !
        0 _AVR-FD !
        ['] _AVR-CLEAN-CLOSE CATCH
        ?DUP IF _AVFS-CLEAN-NOTE THEN
    THEN
    _AVR-HAVE-OLD-VFS @ IF
        0 _AVR-HAVE-OLD-VFS !
        ['] _AVR-CLEAN-RESTORE CATCH
        ?DUP IF _AVFS-CLEAN-NOTE THEN
    THEN
    _AVFS-CLEAN-IOR @ ;

: _AVR-CLEAN-BUFFER  ( -- cleanup-ior )
    _AVFS-CLEAN-BEGIN
    _AVR-BUF @ IF
        ['] _AVR-CLEAN-FREE CATCH
        0 _AVR-BUF !
        ?DUP IF _AVFS-CLEAN-NOTE THEN
    THEN
    _AVFS-CLEAN-IOR @ ;

: _AVR-CLEAN-CONVERSATION  ( -- cleanup-ior )
    _AVFS-CLEAN-BEGIN
    _AVR-CONV @ IF
        ['] _AVR-CLEAN-CONV CATCH
        0 _AVR-CONV ! 0 _AVR-GEN !
        ?DUP IF _AVFS-CLEAN-NOTE THEN
    THEN
    _AVFS-CLEAN-IOR @ ;

: _AVFS-READ-BYTES-BODY  ( -- )
    ACSTORE-S-IO _AVR-STATUS !
    VFS-CUR _AVR-OLD-VFS !
    -1 _AVR-HAVE-OLD-VFS !
    _AVR-S @ AVFSSTORE.VFS @ _AVFS-USE-XT @ EXECUTE
    _AVR-PA @ _AVR-PU @ _AVFS-OPEN-XT @ EXECUTE _AVR-FD !
    _AVR-FD @ 0= IF ACSTORE-S-NOT-FOUND _AVR-STATUS ! EXIT THEN
    _AVR-FD @ VFS-SIZE DUP _AVR-SIZE !
    DUP ATHREAD-HEADER-SIZE < SWAP ATHREAD-MAX-SNAPSHOT > OR IF
        ACSTORE-S-INVALID _AVR-STATUS ! EXIT
    THEN
    _AVR-SIZE @ ALLOCATE DUP IF
        2DROP ACSTORE-S-NOMEM _AVR-STATUS ! EXIT
    THEN
    DROP _AVR-BUF !
    _AVR-BUF @ _AVR-SIZE @ _AVR-FD @ _AVFS-READ-XT @ EXECUTE
    IF EXIT THEN
    _AVR-FD @ 0 _AVR-FD ! _AVFS-CLOSE-XT @ EXECUTE
    _AVR-OLD-VFS @ 0 _AVR-HAVE-OLD-VFS ! _AVFS-USE-XT @ EXECUTE
    ACSTORE-S-OK _AVR-STATUS ! ;

: _AVFS-READ-TRANSACTION  ( -- )
    ['] _AVFS-READ-BYTES-BODY CATCH _AVR-PRIMARY-IOR !
    _AVR-CLEAN-IO
    _AVR-STATUS @ IF
        _AVR-CLEAN-BUFFER _AVFS-CLEAN-PREFER-FIRST
    THEN
    _AVR-PRIMARY-IOR @ ?DUP IF NIP THROW THEN
    ?DUP IF THROW THEN ;

: _AVFS-READ-TRANSACTION-CALL  ( -- )
    ['] _AVFS-READ-TRANSACTION VFS-TRANSACTION ;

: _AVFS-READ-BYTES  ( -- status )
    ACSTORE-S-IO _AVR-STATUS !
    ['] _AVFS-READ-TRANSACTION-CALL CATCH ?DUP IF
        >R
        _AVR-CLEAN-IO _AVR-CLEAN-BUFFER
        _AVFS-CLEAN-PREFER-FIRST DROP
        R> THROW
    THEN
    _AVR-STATUS @ ;

: _AVFS-DECODE-BODY  ( -- )
    _AVR-BUF @ _AVR-SIZE @ _AVFS-DECODE-XT @ EXECUTE
    _AVR-CODEC-STATUS ! _AVR-GEN ! _AVR-CONV ! ;

: _AVFS-READ-SLOT
  ( path-a path-u store -- conversation generation bytes-a bytes-u status )
    _AVR-S ! _AVR-PU ! _AVR-PA !
    0 _AVR-FD ! 0 _AVR-BUF ! 0 _AVR-HAVE-OLD-VFS !
    _AVFS-READ-BYTES DUP IF
        >R 0 0 0 0 R> EXIT
    THEN DROP
    0 _AVR-CONV ! 0 _AVR-GEN ! ATHREAD-S-INVALID _AVR-CODEC-STATUS !
    ['] _AVFS-DECODE-BODY CATCH ?DUP IF
        >R
        _AVR-CLEAN-BUFFER _AVR-CLEAN-CONVERSATION
        _AVFS-CLEAN-PREFER-FIRST DROP
        R> THROW
    THEN
    _AVR-CODEC-STATUS @ IF
        _AVR-CLEAN-BUFFER _AVR-CLEAN-CONVERSATION
        _AVFS-CLEAN-PREFER-FIRST ?DUP IF THROW THEN
        0 0 0 0 _AVR-CODEC-STATUS @ _AVFS-CODEC-STATUS EXIT
    THEN
    \ Transfer the verified source bytes with the decoded object.  Pair
    \ selection compares equal-generation candidates byte-for-byte before
    \ either buffer is released; normalized conversation objects are not a
    \ sufficient split-brain identity.
    _AVR-CONV @ _AVR-GEN @ _AVR-BUF @ _AVR-SIZE @ ACSTORE-S-OK
    0 _AVR-BUF ! ;

VARIABLE _AVL-S
VARIABLE _AVL-A-CONV
VARIABLE _AVL-A-GEN
VARIABLE _AVL-A-BUF
VARIABLE _AVL-A-U
VARIABLE _AVL-A-STATUS
VARIABLE _AVL-B-CONV
VARIABLE _AVL-B-GEN
VARIABLE _AVL-B-BUF
VARIABLE _AVL-B-U
VARIABLE _AVL-B-STATUS

: _AVL-CLEAN-A-BODY  ( -- ) _AVL-A-CONV @ ACONV-FREE ;
: _AVL-CLEAN-B-BODY  ( -- ) _AVL-B-CONV @ ACONV-FREE ;
: _AVL-CLEAN-A-BUFFER-BODY  ( -- ) _AVL-A-BUF @ FREE ;
: _AVL-CLEAN-B-BUFFER-BODY  ( -- ) _AVL-B-BUF @ FREE ;

: _AVL-CLEAN-A  ( -- cleanup-ior )
    _AVFS-CLEAN-BEGIN
    _AVL-A-CONV @ IF
        ['] _AVL-CLEAN-A-BODY CATCH
        0 _AVL-A-CONV !
        ?DUP IF _AVFS-CLEAN-NOTE THEN
    THEN
    _AVL-A-BUF @ IF
        ['] _AVL-CLEAN-A-BUFFER-BODY CATCH
        0 _AVL-A-BUF ! 0 _AVL-A-U !
        ?DUP IF _AVFS-CLEAN-NOTE THEN
    THEN
    _AVFS-CLEAN-IOR @ ;

: _AVL-CLEAN-B  ( -- cleanup-ior )
    _AVFS-CLEAN-BEGIN
    _AVL-B-CONV @ IF
        ['] _AVL-CLEAN-B-BODY CATCH
        0 _AVL-B-CONV !
        ?DUP IF _AVFS-CLEAN-NOTE THEN
    THEN
    _AVL-B-BUF @ IF
        ['] _AVL-CLEAN-B-BUFFER-BODY CATCH
        0 _AVL-B-BUF ! 0 _AVL-B-U !
        ?DUP IF _AVFS-CLEAN-NOTE THEN
    THEN
    _AVFS-CLEAN-IOR @ ;

: _AVL-CLEAN-CANDIDATES  ( -- cleanup-ior )
    _AVL-CLEAN-A _AVL-CLEAN-B _AVFS-CLEAN-PREFER-FIRST ;

: _AVL-FREE-A-BUFFER  ( -- )
    _AVL-A-BUF @ ?DUP IF 0 _AVL-A-BUF ! 0 _AVL-A-U ! FREE THEN ;

: _AVL-FREE-B-BUFFER  ( -- )
    _AVL-B-BUF @ ?DUP IF 0 _AVL-B-BUF ! 0 _AVL-B-U ! FREE THEN ;

: _AVL-DISCARD-A  ( -- )
    _AVL-FREE-A-BUFFER
    _AVL-A-CONV @ ?DUP IF
        0 _AVL-A-CONV ! _AVFS-CONV-FREE-XT @ EXECUTE
    THEN ;

: _AVL-DISCARD-B  ( -- )
    _AVL-FREE-B-BUFFER
    _AVL-B-CONV @ ?DUP IF
        0 _AVL-B-CONV ! _AVFS-CONV-FREE-XT @ EXECUTE
    THEN ;

: _AVL-TAKE-A  ( -- conversation status )
    _AVL-FREE-A-BUFFER
    _AVL-A-CONV @ 0 _AVL-A-CONV ! ACSTORE-S-OK ;

: _AVL-TAKE-B  ( -- conversation status )
    _AVL-FREE-B-BUFFER
    _AVL-B-CONV @ 0 _AVL-B-CONV ! ACSTORE-S-OK ;

: _AVFS-PAIR-EQUAL  ( value-a value-b store -- equal? detail )
    DROP 2DROP
    _AVL-A-U @ _AVL-B-U @ = IF
        _AVL-A-BUF @ _AVL-A-U @ _AVL-B-BUF @ _AVL-B-U @ COMPARE 0=
    ELSE
        0
    THEN
    0 ;

: _AVL-A-CANDIDATE!  ( -- )
    _AVL-A-STATUS @ ACSTORE-S-OK = IF
        \ Candidate VALUE is stable descriptor identity, not the transient
        \ decoded conversation whose ownership leaves this load operation.
        _AVL-S @ _AVFSSTORE-CANDIDATE-A
        _AVL-A-GEN @ _AVL-A-STATUS @
        _AVL-S @ _AVFSSTORE-CANDIDATE-A GPAIR-CANDIDATE-VALUE! DROP
    ELSE
        _AVL-A-STATUS @ ACSTORE-S-NOT-FOUND = IF
            _AVL-A-STATUS @ _AVL-S @ _AVFSSTORE-CANDIDATE-A
                GPAIR-CANDIDATE-ABSENT! DROP
        ELSE
            _AVL-A-STATUS @ _AVL-S @ _AVFSSTORE-CANDIDATE-A
                GPAIR-CANDIDATE-CORRUPT! DROP
        THEN
    THEN ;

: _AVL-B-CANDIDATE!  ( -- )
    _AVL-B-STATUS @ ACSTORE-S-OK = IF
        _AVL-S @ _AVFSSTORE-CANDIDATE-B
        _AVL-B-GEN @ _AVL-B-STATUS @
        _AVL-S @ _AVFSSTORE-CANDIDATE-B GPAIR-CANDIDATE-VALUE! DROP
    ELSE
        _AVL-B-STATUS @ ACSTORE-S-NOT-FOUND = IF
            _AVL-B-STATUS @ _AVL-S @ _AVFSSTORE-CANDIDATE-B
                GPAIR-CANDIDATE-ABSENT! DROP
        ELSE
            _AVL-B-STATUS @ _AVL-S @ _AVFSSTORE-CANDIDATE-B
                GPAIR-CANDIDATE-CORRUPT! DROP
        THEN
    THEN ;

: _AVFS-FREE-ONE-NOTHROW  ( conversation -- )
    ['] ACONV-FREE CATCH IF DROP THEN ;

: _AVFS-STORE-GUARD-RELEASE  ( -- )
    _avfs-store-guard _AVFS-GUARD-RELEASE-XT @ EXECUTE ;

: _AVFS-LOAD-BODY  ( -- conversation status )
    _AVFS-PATH-A _AVL-S @ _AVFS-READ-SLOT
    _AVL-A-STATUS ! _AVL-A-U ! _AVL-A-BUF !
    _AVL-A-GEN ! _AVL-A-CONV !
    _AVFS-PATH-B _AVL-S @ _AVFS-READ-SLOT
    _AVL-B-STATUS ! _AVL-B-U ! _AVL-B-BUF !
    _AVL-B-GEN ! _AVL-B-CONV !
    _AVL-A-CANDIDATE! _AVL-B-CANDIDATE!
    _AVL-S @ _AVFSSTORE-CANDIDATE-A
    _AVL-S @ _AVFSSTORE-CANDIDATE-B
    _AVL-S @ AVFSSTORE.PAIR GPAIR-SELECT
    DUP IF 2DROP _AVL-CLEAN-CANDIDATES ?DUP IF THROW THEN
        0 ACSTORE-S-IO EXIT
    THEN DROP
    CASE
        GPAIR-R-FALLBACK OF
            _AVL-S @ AVFSSTORE.PAIR GPAIR-SELECTED@
            _AVL-S @ _AVFSSTORE-CANDIDATE-A = IF
                _AVL-DISCARD-B _AVL-TAKE-A
            ELSE
                _AVL-DISCARD-A _AVL-TAKE-B
            THEN
        ENDOF
        GPAIR-R-NEWEST OF
            _AVL-S @ AVFSSTORE.PAIR GPAIR-SELECTED@
            _AVL-S @ _AVFSSTORE-CANDIDATE-A = IF
                _AVL-DISCARD-B _AVL-TAKE-A
            ELSE
                _AVL-DISCARD-A _AVL-TAKE-B
            THEN
        ENDOF
        GPAIR-R-EQUAL OF
            \ Equal verified bytes are interchangeable; choose A as the
            \ deterministic owner and release B exactly once.
            _AVL-DISCARD-B _AVL-TAKE-A
        ENDOF
        GPAIR-R-ABSENT OF
            _AVL-CLEAN-CANDIDATES ?DUP IF THROW THEN
            0 ACSTORE-S-NOT-FOUND
        ENDOF
        \ Corrupt and equal-generation divergent pairs both fail closed.
        _AVL-CLEAN-CANDIDATES ?DUP IF THROW THEN
        0 ACSTORE-S-INVALID ROT
    ENDCASE ;

: _AVFS-LOAD-LOCKED  ( store -- conversation status )
    _AVL-S !
    \ A new inspection revokes the preceding RAM authority before any slot
    \ can fail.  Only a successful pair classification may publish it again.
    _AVL-S @ AVFSSTORE.PAIR GPAIR-RESET DUP IF
        DROP 0 ACSTORE-S-IO EXIT
    THEN DROP
    0 _AVL-A-CONV ! 0 _AVL-B-CONV !
    0 _AVL-A-BUF ! 0 _AVL-A-U ! 0 _AVL-B-BUF ! 0 _AVL-B-U !
    ['] _AVFS-LOAD-BODY CATCH ?DUP IF
        >R _AVL-CLEAN-CANDIDATES DROP
        _AVL-S @ AVFSSTORE.PAIR GPAIR-RESET DROP
        R> THROW
    THEN ;

: _AVFS-LOAD-GUARDED  ( store -- conversation status )
    _avfs-store-guard GUARD-ACQUIRE
    ['] _AVFS-LOAD-LOCKED CATCH ?DUP IF
        >R DROP
        ['] _AVFS-STORE-GUARD-RELEASE CATCH DROP
        R> DROP 0 ACSTORE-S-IO EXIT
    THEN
    ['] _AVFS-STORE-GUARD-RELEASE CATCH ?DUP IF
        DROP SWAP _AVFS-FREE-ONE-NOTHROW DROP
        _AVL-S @ AVFSSTORE.PAIR GPAIR-RESET DROP
        0 ACSTORE-S-IO
    THEN ;

: _AVFS-LOAD  ( store -- conversation status )
    ['] _AVFS-LOAD-GUARDED CATCH ?DUP IF
        2DROP 0 ACSTORE-S-IO
    THEN ;

VARIABLE _AVW-CONV
VARIABLE _AVW-S
VARIABLE _AVW-GEN
VARIABLE _AVW-SLOT
VARIABLE _AVW-PA
VARIABLE _AVW-PU
VARIABLE _AVW-BUF
VARIABLE _AVW-SIZE
VARIABLE _AVW-LEN
VARIABLE _AVW-STATUS
VARIABLE _AVW-FD
VARIABLE _AVW-OLD-VFS
VARIABLE _AVW-HAVE-OLD-VFS
VARIABLE _AVW-RESULT
VARIABLE _AVW-PRIMARY-IOR
VARIABLE _AVW-CLEAN-FD
VARIABLE _AVW-PUBLICATION-MAYBE

: _AVFS-PAIR-MAYBE!  ( -- )
    _AVW-PUBLICATION-MAYBE @ IF EXIT THEN
    _AVW-S @ AVFSSTORE.PAIR GPAIR-SAVE-MAYBE! ?DUP IF THROW THEN
    -1 _AVW-PUBLICATION-MAYBE ! ;

: _AVFS-PAIR-DURABLE!  ( -- )
    _AVW-S @ AVFSSTORE.PAIR GPAIR-SAVE-DURABLE! ?DUP IF THROW THEN ;

: _AVFS-SELECT-WRITE-PATH  ( slot -- )
    IF _AVFS-PATH-B ELSE _AVFS-PATH-A THEN
    _AVW-PU ! _AVW-PA ! ;

: _AVFS-OPEN-WRITE-LOCKED  ( -- fd | 0 )
    _AVW-PA @ _AVW-PU @ _AVFS-OPEN-XT @ EXECUTE DUP 0= IF
        DROP
        \ Creating the inactive path is already an externally visible effect,
        \ even if the later snapshot write never reaches durability.
        _AVFS-PAIR-MAYBE!
        _AVW-PA @ _AVW-PU @ _AVW-S @ AVFSSTORE.VFS @
        _AVFS-CREATE-XT @ EXECUTE
        DUP 0= IF
            DROP 0 EXIT
        THEN
        DROP _AVW-PA @ _AVW-PU @ _AVFS-OPEN-XT @ EXECUTE
    THEN ;

: _AVW-CLEAN-CLOSE  ( -- ) _AVW-CLEAN-FD @ VFS-CLOSE ;
: _AVW-CLEAN-RESTORE  ( -- ) _AVW-OLD-VFS @ VFS-USE ;
: _AVW-CLEAN-FREE  ( -- ) _AVW-BUF @ FREE ;

: _AVW-CLEAN-IO  ( -- cleanup-ior )
    _AVFS-CLEAN-BEGIN
    _AVW-FD @ IF
        _AVW-FD @ _AVW-CLEAN-FD !
        0 _AVW-FD !
        ['] _AVW-CLEAN-CLOSE CATCH
        ?DUP IF _AVFS-CLEAN-NOTE THEN
    THEN
    _AVW-HAVE-OLD-VFS @ IF
        0 _AVW-HAVE-OLD-VFS !
        ['] _AVW-CLEAN-RESTORE CATCH
        ?DUP IF _AVFS-CLEAN-NOTE THEN
    THEN
    _AVFS-CLEAN-IOR @ ;

: _AVW-CLEAN-BUFFER  ( -- cleanup-ior )
    _AVFS-CLEAN-BEGIN
    _AVW-BUF @ IF
        ['] _AVW-CLEAN-FREE CATCH
        0 _AVW-BUF !
        ?DUP IF _AVFS-CLEAN-NOTE THEN
    THEN
    _AVFS-CLEAN-IOR @ ;

: _AVFS-WRITE-SLOT-BODY  ( -- )
    ACSTORE-S-IO _AVW-STATUS !
    VFS-CUR _AVW-OLD-VFS ! -1 _AVW-HAVE-OLD-VFS !
    _AVW-S @ AVFSSTORE.VFS @ _AVFS-USE-XT @ EXECUTE
    _AVFS-OPEN-WRITE-LOCKED DUP _AVW-FD ! 0= IF EXIT THEN
    _AVW-FD @ VFS-REWIND
    _AVFS-PAIR-MAYBE!
    0 _AVW-FD @ VFS-TRUNCATE IF EXIT THEN
    _AVW-BUF @ _AVW-LEN @ _AVW-FD @ _AVFS-WRITE-XT @ EXECUTE
    IF EXIT THEN
    _AVW-FD @ 0 _AVW-FD ! _AVFS-CLOSE-XT @ EXECUTE
    ACSTORE-S-UNCERTAIN _AVW-STATUS !
    _AVW-S @ AVFSSTORE.VFS @ _AVFS-SYNC-XT @ EXECUTE IF EXIT THEN
    _AVFS-PAIR-DURABLE!
    _AVW-OLD-VFS @ 0 _AVW-HAVE-OLD-VFS ! _AVFS-USE-XT @ EXECUTE
    ACSTORE-S-OK _AVW-STATUS ! ;

: _AVFS-WRITE-TRANSACTION  ( -- )
    ['] _AVFS-WRITE-SLOT-BODY CATCH _AVW-PRIMARY-IOR !
    _AVW-CLEAN-IO
    _AVW-STATUS @ IF
        _AVW-CLEAN-BUFFER _AVFS-CLEAN-PREFER-FIRST
    THEN
    _AVW-PRIMARY-IOR @ ?DUP IF NIP THROW THEN
    ?DUP IF THROW THEN ;

: _AVFS-WRITE-TRANSACTION-CALL  ( -- )
    ['] _AVFS-WRITE-TRANSACTION VFS-TRANSACTION ;

: _AVFS-WRITE-SLOT  ( -- status )
    ACSTORE-S-IO _AVW-STATUS !
    ['] _AVFS-WRITE-TRANSACTION-CALL CATCH ?DUP IF
        >R
        _AVW-CLEAN-IO _AVW-CLEAN-BUFFER
        _AVFS-CLEAN-PREFER-FIRST DROP
        R> THROW
    THEN
    _AVW-STATUS @ ;

: _AVFS-ENCODE-SIZE-BODY  ( -- )
    _AVW-CONV @ _AVFS-ENCODE-SIZE-XT @ EXECUTE
    _AVW-STATUS ! _AVW-SIZE ! ;

: _AVFS-ENCODE-BODY  ( -- )
    _AVW-GEN @ _AVW-CONV @ _AVW-BUF @ _AVW-SIZE @
    _AVFS-ENCODE-XT @ EXECUTE _AVW-STATUS ! _AVW-LEN ! ;

: _AVFS-PAIR-SAVE
  ( conversation target-slot generation pair store -- detail )
    _AVW-S ! DROP _AVW-GEN !
    DUP _AVW-SLOT ! _AVFS-SELECT-WRITE-PATH
    _AVW-CONV !
    0 _AVW-BUF ! 0 _AVW-FD ! 0 _AVW-HAVE-OLD-VFS !
    ATHREAD-S-INVALID _AVW-STATUS !
    ['] _AVFS-ENCODE-SIZE-BODY CATCH ?DUP IF
        THROW
    THEN
    _AVW-STATUS @ IF
        _AVW-STATUS @ _AVFS-CODEC-STATUS EXIT
    THEN
    _AVW-SIZE @ ALLOCATE DUP IF
        2DROP ACSTORE-S-NOMEM EXIT
    THEN
    DROP _AVW-BUF !
    ATHREAD-S-INVALID _AVW-STATUS !
    ['] _AVFS-ENCODE-BODY CATCH ?DUP IF
        >R _AVW-CLEAN-BUFFER DROP R> THROW
    ELSE
        _AVW-STATUS @ _AVFS-CODEC-STATUS _AVW-RESULT !
    THEN
    _AVW-RESULT @ IF
        _AVW-CLEAN-BUFFER ?DUP IF THROW THEN
        _AVW-RESULT @ EXIT
    THEN
    _AVFS-WRITE-SLOT _AVW-STATUS !
    _AVW-CLEAN-BUFFER ?DUP IF THROW THEN
    _AVW-STATUS @ ;

VARIABLE _AVP-OUTCOME
VARIABLE _AVP-STATUS

: _AVFS-PAIR-DETAIL-STATUS  ( detail -- status )
    DUP ACSTORE-S-OK < OVER ACSTORE-S-UNCERTAIN > OR IF
        DROP ACSTORE-S-IO
    THEN ;

: _AVFS-SAVE-LOCKED  ( conversation store -- status )
    DUP _AVW-S !
    0 _AVW-PUBLICATION-MAYBE !
    SWAP OVER AVFSSTORE.PAIR GPAIR-SAVE
    _AVP-STATUS ! _AVP-OUTCOME !
    _AVP-STATUS @ GPAIR-S-CAPACITY = IF
        DROP ACSTORE-S-CAPACITY EXIT
    THEN
    DUP AVFSSTORE.PAIR GPAIR-DETAIL@
    SWAP DROP _AVFS-PAIR-DETAIL-STATUS
    _AVP-OUTCOME @ GPAIR-W-DURABLE = IF
        _AVP-STATUS @ GPAIR-S-OK <> IF
            DROP ACSTORE-S-UNCERTAIN EXIT
        THEN
        DUP ACSTORE-S-OK = IF EXIT THEN
        DROP ACSTORE-S-UNCERTAIN EXIT
    THEN
    _AVP-OUTCOME @ GPAIR-W-MAYBE = IF
        DROP ACSTORE-S-UNCERTAIN EXIT
    THEN
    _AVP-STATUS @ GPAIR-S-OK <> IF DROP ACSTORE-S-IO THEN ;

: _AVFS-SAVE-CONTAINED  ( conversation store -- status )
    0 _AVW-PUBLICATION-MAYBE !
    ['] _AVFS-SAVE-LOCKED CATCH ?DUP IF
        DROP 2DROP
        _AVW-PUBLICATION-MAYBE @ IF
            ACSTORE-S-UNCERTAIN
        ELSE
            ACSTORE-S-IO
        THEN
    THEN ;

: _AVFS-SAVE-FAULT-STATUS  ( -- status )
    _AVW-PUBLICATION-MAYBE @ IF
        ACSTORE-S-UNCERTAIN
    ELSE
        ACSTORE-S-IO
    THEN ;

: _AVFS-SAVE-GUARDED  ( conversation store -- status )
    _avfs-store-guard GUARD-ACQUIRE
    ['] _AVFS-SAVE-CONTAINED CATCH ?DUP IF
        >R 2DROP
        ['] _AVFS-STORE-GUARD-RELEASE CATCH DROP
        R> DROP _AVFS-SAVE-FAULT-STATUS EXIT
    THEN
    ['] _AVFS-STORE-GUARD-RELEASE CATCH ?DUP IF
        2DROP _AVFS-SAVE-FAULT-STATUS
    THEN ;

: _AVFS-SAVE  ( conversation store -- status )
    ['] _AVFS-SAVE-GUARDED CATCH ?DUP IF
        DROP 2DROP ACSTORE-S-IO
    THEN ;

: _AVFSSTORE-FREE-LOCKED  ( store -- )
    DUP AVFSSTORE-SIZE 0 FILL FREE ;

: AVFSSTORE-FREE  ( store -- )
    ['] _AVFSSTORE-FREE-LOCKED _avfs-store-guard WITH-GUARD ;

VARIABLE _AVN-S

: _AVFSSTORE-NEW-LOCKED  ( vfs -- store status )
    DUP 0= IF DROP 0 ACSTORE-S-INVALID EXIT THEN
    >R AVFSSTORE-SIZE ALLOCATE
    DUP IF 2DROP R> DROP 0 ACSTORE-S-NOMEM EXIT THEN
    DROP DUP _AVN-S ! AVFSSTORE-SIZE 0 FILL
    _AVN-S @ ACSTORE-INIT
    R> _AVN-S @ AVFSSTORE.VFS !
    _AVN-S @ _AVFSSTORE-CANDIDATE-A GPAIR-CANDIDATE-INIT DROP
    _AVN-S @ _AVFSSTORE-CANDIDATE-B GPAIR-CANDIDATE-INIT DROP
    ['] _AVFS-PAIR-EQUAL ['] _AVFS-PAIR-SAVE _AVN-S @
    _AVN-S @ AVFSSTORE.PAIR GPAIR-INIT ?DUP IF
        >R _AVN-S @ AVFSSTORE-SIZE 0 FILL _AVN-S @ FREE
        0 R> EXIT
    THEN
    _AVN-S @ _AVN-S @ ACSTORE.CONTEXT !
    ['] _AVFS-LOAD _AVN-S @ ACSTORE.LOAD-XT !
    ['] _AVFS-SAVE _AVN-S @ ACSTORE.SAVE-XT !
    ['] AVFSSTORE-FREE _AVN-S @ ACSTORE.FREE-XT !
    _AVN-S @ ACSTORE-S-OK ;

: AVFSSTORE-NEW  ( vfs -- store status )
    ['] _AVFSSTORE-NEW-LOCKED _avfs-store-guard WITH-GUARD ;
