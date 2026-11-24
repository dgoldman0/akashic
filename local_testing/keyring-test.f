\ Contract for akashic/security/passphrase-keyring.f, which
\ local_testing/test_passphrase_keyring.py runs: load passphrase-keyring.f
\ and test-root-place.f first.  The keyring keeps its file on a RAM volume
\ of the check's own, at small iteration counts.

VARIABLE _kt-fails  VARIABLE _kt-checks  VARIABLE _kt-depth
VARIABLE _kt-place  VARIABLE _kt-vfs  VARIABLE _kt-kr  VARIABLE _kt-kr2
VARIABLE _kt-consumed  VARIABLE _kt-seen-u  VARIABLE _kt-ws  VARIABLE _kt-fd
CREATE _kt-seen 32 ALLOT
CREATE _kt-root 32 ALLOT
CREATE _kt-other-id 32 ALLOT
CREATE _kt-image KEYRING-FILE-SIZE ALLOT
CREATE _kt-repl VREPL-SIZE ALLOT
CREATE _kt-secret 16 ALLOT
CREATE _kt-plain 16 ALLOT
CREATE _kt-record-id 32 ALLOT
CREATE _kt-desc SEALED-RECORD-DESCRIPTOR-SIZE ALLOT
16 SEALED-RECORD-SIZE CONSTANT _kt-record-u
CREATE _kt-record _kt-record-u ALLOT

: _kt-assert  ( flag -- )
    1 _kt-checks +!
    0= IF 1 _kt-fails +! ." KT ASSERT " _kt-checks @ . CR THEN ;

: _kt-path  ( -- a u )  S" /keyring" ;

\ Run a derivation to its end, in steps of 16 iterations.
: _kt-run  ( keyring -- status )
    BEGIN 16 OVER KEYRING-STEP DUP KEYRING-S-PENDING = WHILE DROP REPEAT
    NIP ;

\ A consumer that copies the key it is lent.
: _kt-consume  ( key u context -- status )
    DROP DUP _kt-seen-u ! _kt-seen SWAP MOVE 1 _kt-consumed +!
    SEALED-RECORD-S-OK ;

: _kt-borrow  ( keyring -- status )
    0 _kt-consumed ! >R
    R@ KEYRING-ID ['] _kt-consume 0 R> KEYRING-RESOLVER ;

: _kt-new  ( -- keyring )
    KEYRING-SIZE ALLOCATE 0= _kt-assert ;

: _kt-volume  ( -- )
    2097152 A-XMEM ARENA-NEW 0= _kt-assert
    VFS-RAM-BINDING 0 VFS-NEW 0= _kt-assert DUP _kt-vfs !
    S" kt" _t-root-place _kt-place ! ;

\ Setup, the key it lends, and the resolver's refusals.
: _kt-test-setup  ( -- )
    _kt-path _kt-place @ _kt-kr @ KEYRING-INIT KEYRING-S-OK = _kt-assert
    _kt-kr @ KEYRING-STATE@ KEYRING-ABSENT = _kt-assert
    S" secret" _kt-kr @ KEYRING-UNLOCK KEYRING-S-STATE = _kt-assert
    S" correct horse" 0 _kt-kr @ KEYRING-SETUP KEYRING-S-INVALID = _kt-assert
    S" correct horse" 64 _kt-kr @ KEYRING-SETUP KEYRING-S-PENDING = _kt-assert
    _kt-kr @ KEYRING-STATE@ KEYRING-SETTING-UP = _kt-assert
    \ The start runs the first iteration; each step runs its budget.
    _kt-kr @ KEYRING-PROGRESS 64 = SWAP 1 = AND _kt-assert
    16 _kt-kr @ KEYRING-STEP KEYRING-S-PENDING = _kt-assert
    _kt-kr @ KEYRING-PROGRESS 64 = SWAP 17 = AND _kt-assert
    _kt-kr @ _kt-run KEYRING-S-OK = _kt-assert
    _kt-kr @ KEYRING-STATE@ KEYRING-UNLOCKED = _kt-assert
    _kt-kr @ KEYRING-ITERATIONS@ 64 = _kt-assert
    _kt-kr @ _kt-borrow SEALED-RECORD-S-OK = _kt-assert
    _kt-consumed @ 1 = _kt-assert  _kt-seen-u @ 32 = _kt-assert
    _kt-seen _kt-root 32 MOVE
    \ Another key id gets nothing.
    _kt-kr @ KEYRING-ID _kt-other-id SWAP MOVE
    _kt-other-id DUP C@ 1 XOR SWAP C!
    0 _kt-consumed !
    _kt-other-id 32 ['] _kt-consume 0 _kt-kr @ KEYRING-RESOLVER
        SEALED-RECORD-S-KEY = _kt-assert
    _kt-consumed @ 0= _kt-assert
    \ Locked, it lends nothing and wants the passphrase.
    _kt-kr @ KEYRING-WANTED? 0= _kt-assert
    _kt-kr @ KEYRING-LOCK
    _kt-kr @ KEYRING-STATE@ KEYRING-LOCKED = _kt-assert
    _kt-kr @ _kt-borrow SEALED-RECORD-S-KEY = _kt-assert
    _kt-consumed @ 0= _kt-assert
    _kt-kr @ KEYRING-WANTED? _kt-assert
    _kt-kr @ KEYRING-WANT-CLEAR _kt-kr @ KEYRING-WANTED? 0= _kt-assert ;

\ Another keyring over the same file: wrong and right passphrases, a
\ change, and a cancel.
: _kt-test-reopen  ( -- )
    _kt-path _kt-place @ _kt-kr2 @ KEYRING-INIT KEYRING-S-OK = _kt-assert
    _kt-kr2 @ KEYRING-STATE@ KEYRING-LOCKED = _kt-assert
    _kt-kr2 @ KEYRING-ITERATIONS@ 64 = _kt-assert
    _kt-kr2 @ KEYRING-ID _kt-kr @ KEYRING-ID COMPARE 0= _kt-assert
    S" wrong horse" _kt-kr2 @ KEYRING-UNLOCK KEYRING-S-PENDING = _kt-assert
    _kt-kr2 @ _kt-run KEYRING-S-WRONG = _kt-assert
    _kt-kr2 @ KEYRING-STATE@ KEYRING-LOCKED = _kt-assert
    S" correct horse" _kt-kr2 @ KEYRING-UNLOCK KEYRING-S-PENDING = _kt-assert
    _kt-kr2 @ _kt-run KEYRING-S-OK = _kt-assert
    _kt-kr2 @ _kt-borrow SEALED-RECORD-S-OK = _kt-assert
    _kt-seen 32 _kt-root 32 COMPARE 0= _kt-assert
    \ A change seals the same key under the new passphrase and count.
    S" battery staple" 96 _kt-kr2 @ KEYRING-CHANGE
        KEYRING-S-PENDING = _kt-assert
    _kt-kr2 @ _kt-run KEYRING-S-OK = _kt-assert
    _kt-kr2 @ KEYRING-STATE@ KEYRING-UNLOCKED = _kt-assert
    _kt-kr2 @ KEYRING-ITERATIONS@ 96 = _kt-assert
    _kt-kr2 @ KEYRING-FINI
    _kt-path _kt-place @ _kt-kr2 @ KEYRING-INIT KEYRING-S-OK = _kt-assert
    S" correct horse" _kt-kr2 @ KEYRING-UNLOCK DROP
    _kt-kr2 @ _kt-run KEYRING-S-WRONG = _kt-assert
    S" battery staple" _kt-kr2 @ KEYRING-UNLOCK DROP
    _kt-kr2 @ _kt-run KEYRING-S-OK = _kt-assert
    _kt-kr2 @ _kt-borrow SEALED-RECORD-S-OK = _kt-assert
    _kt-seen 32 _kt-root 32 COMPARE 0= _kt-assert
    \ A cancel returns to where the derivation started.
    _kt-kr2 @ KEYRING-LOCK
    S" battery staple" _kt-kr2 @ KEYRING-UNLOCK KEYRING-S-PENDING = _kt-assert
    16 _kt-kr2 @ KEYRING-STEP KEYRING-S-PENDING = _kt-assert
    _kt-kr2 @ KEYRING-CANCEL
    _kt-kr2 @ KEYRING-STATE@ KEYRING-LOCKED = _kt-assert
    16 _kt-kr2 @ KEYRING-STEP KEYRING-S-STATE = _kt-assert ;

\ The sealed-record contract through the keyring's resolver.
: _kt-desc!  ( input input-u output output-cap -- )
    _kt-desc SEALED-RECORD-DESCRIPTOR-SIZE 0 FILL
    _kt-desc SEALED-RECORD-D.OUTPUT-CAP !  _kt-desc SEALED-RECORD-D.OUTPUT !
    _kt-desc SEALED-RECORD-D.INPUT-U !     _kt-desc SEALED-RECORD-D.INPUT !
    _kt-kr2 @ KEYRING-ID DROP     _kt-desc SEALED-RECORD-D.KEY-ID !
    _kt-record-id                 _kt-desc SEALED-RECORD-D.RECORD-ID !
    0x4B5452454354534D            _kt-desc SEALED-RECORD-D.PURPOSE !
    1                             _kt-desc SEALED-RECORD-D.REVISION !
    ['] KEYRING-RESOLVER          _kt-desc SEALED-RECORD-D.RESOLVER-XT !
    _kt-kr2 @                     _kt-desc SEALED-RECORD-D.RESOLVER-CONTEXT ! ;

: _kt-test-sealed  ( -- )
    SEALED-RECORD-WORKSPACE-SIZE ALLOCATE 0= _kt-assert _kt-ws !
    _kt-secret 16 0x5A FILL  _kt-record-id 32 0x33 FILL
    S" battery staple" _kt-kr2 @ KEYRING-UNLOCK DROP
    _kt-kr2 @ _kt-run KEYRING-S-OK = _kt-assert
    _kt-secret 16 _kt-record _kt-record-u _kt-desc!
    _kt-desc _kt-ws @ SEALED-RECORD-SEAL
        SEALED-RECORD-S-OK = _kt-assert _kt-record-u = _kt-assert
    _kt-kr2 @ KEYRING-LOCK
    _kt-record _kt-record-u _kt-plain 16 _kt-desc!
    _kt-desc _kt-ws @ SEALED-RECORD-OPEN
        SEALED-RECORD-S-KEY = _kt-assert DROP
    _kt-kr2 @ KEYRING-WANTED? _kt-assert
    S" battery staple" _kt-kr2 @ KEYRING-UNLOCK DROP
    _kt-kr2 @ _kt-run KEYRING-S-OK = _kt-assert
    _kt-kr2 @ KEYRING-WANTED? 0= _kt-assert
    _kt-record _kt-record-u _kt-plain 16 _kt-desc!
    _kt-desc _kt-ws @ SEALED-RECORD-OPEN
        SEALED-RECORD-S-OK = _kt-assert 16 = _kt-assert
    _kt-plain 16 _kt-secret 16 COMPARE 0= _kt-assert
    _kt-ws @ FREE ;

\ A count changed in the file reads as corrupt, not as a wrong passphrase.
: _kt-test-tamper  ( -- )
    _kt-path VFS-FF-READ _kt-place @ PLACE-OPEN 0= _kt-assert _kt-fd !
    _kt-image KEYRING-FILE-SIZE _kt-fd @ VFS-READ-EXACT 0= _kt-assert
    _kt-fd @ VFS-CLOSE? DROP
    _kt-image 23 + DUP C@ 1 XOR SWAP C!
    _kt-repl VREPL-SIZE 0 FILL
    _kt-path _kt-place @ -1 _kt-repl PLACE-VREPL! 0= _kt-assert
    _kt-image KEYRING-FILE-SIZE _kt-repl VREPL-REPLACE
        VREPL-S-OK = _kt-assert
    _kt-repl VREPL-FINI DROP
    _kt-kr2 @ KEYRING-FINI
    _kt-path _kt-place @ _kt-kr2 @ KEYRING-INIT KEYRING-S-OK = _kt-assert
    S" battery staple" _kt-kr2 @ KEYRING-UNLOCK DROP
    _kt-kr2 @ _kt-run KEYRING-S-CORRUPT = _kt-assert
    _kt-kr2 @ KEYRING-STATE@ KEYRING-LOCKED = _kt-assert ;

: _KT-RUN  ( -- )
    0 _kt-fails ! 0 _kt-checks ! DEPTH _kt-depth !
    _kt-volume
    _kt-new _kt-kr !  _kt-new _kt-kr2 !
    _kt-test-setup
    _kt-test-reopen
    _kt-test-sealed
    _kt-test-tamper
    _kt-kr @ KEYRING-FINI  _kt-kr2 @ KEYRING-FINI
    DEPTH _kt-depth @ = _kt-assert
    _kt-fails @ 0= IF
        ." KEYRING PASS " _kt-checks @ .
    ELSE
        ." KEYRING FAIL " _kt-fails @ . ." / " _kt-checks @ .
    THEN CR ;
