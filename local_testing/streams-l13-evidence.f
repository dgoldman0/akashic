\ Focused contracts for exact checked legacy evidence used by L13 migration.

PROVIDED akashic-streams-l13-evidence-contracts

VARIABLE _SL13E-checks
VARIABLE _SL13E-fails
VARIABLE _SL13E-depth
VARIABLE _SL13E-arena
VARIABLE _SL13E-vfs
VARIABLE _SL13E-old-vfs
VARIABLE _SL13E-ior
VARIABLE _SL13E-record-u
VARIABLE _SL13E-generation
VARIABLE _SL13E-status-value
VARIABLE _SL13E-read-a
VARIABLE _SL13E-read-u
VARIABLE _SL13E-path-a
VARIABLE _SL13E-path-u
VARIABLE _SL13E-fd

CREATE _SL13E-ops VFS-OPS-SIZE ALLOT
CREATE _SL13E-binding VFS-BINDING-DESC-SIZE ALLOT
CREATE _SL13E-source-digest SHA3-256-LEN ALLOT
CREATE _SL13E-observation-digest SHA3-256-LEN ALLOT

STREAMS-SOURCE-STORE-SIZE XBUF _SL13E-source-store
STREAMS-OBSERVATION-STORE-SIZE XBUF _SL13E-observation-store
STREAMS-SOURCE-REGISTRY-SIZE XBUF _SL13E-source-candidate
STREAMS-SOURCE-REGISTRY-SIZE XBUF _SL13E-source-loaded
STREAMS-OBSERVATION-CHECKPOINT-SIZE XBUF _SL13E-observation-candidate
STREAMS-OBSERVATION-CHECKPOINT-SIZE XBUF _SL13E-observation-loaded
STREAMS-SOURCE-STORE-RECORD-MAX XBUF _SL13E-source-raw
STREAMS-OBSERVATION-STORE-RECORD-MAX XBUF _SL13E-observation-raw

: _SL13E-assert  ( flag -- )
    1 _SL13E-checks +!
    0= IF
        1 _SL13E-fails +!
        ." STREAMS L13 EVIDENCE ASSERT " _SL13E-checks @ . CR
    THEN ;

: _SL13E-stack  ( -- )
    DEPTH DUP _SL13E-depth @ <> IF
        ." STREAMS L13 EVIDENCE STACK "
        _SL13E-depth @ . ." -> " DUP . CR .S CR
    THEN
    _SL13E-depth @ = _SL13E-assert ;

: _SL13E-status  ( actual expected -- )
    2DUP <> IF
        ." STREAMS L13 EVIDENCE STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _SL13E-assert _SL13E-stack ;

: _SL13E-zero?  ( a u -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _SL13E-results!  ( record-u generation status -- )
    _SL13E-status-value !
    _SL13E-generation !
    _SL13E-record-u ! ;

: _SL13E-results  ( record-u generation status -- )
    _SL13E-results!
    _SL13E-record-u @ 0= _SL13E-assert
    _SL13E-generation @ 0= _SL13E-assert ;

: _SL13E-read-exact  ( destination expected-u path-a path-u -- flag )
    _SL13E-path-u ! _SL13E-path-a !
    _SL13E-read-u ! _SL13E-read-a !
    _SL13E-path-a @ _SL13E-path-u @ VFS-OPEN
    DUP _SL13E-fd ! 0= IF 0 EXIT THEN
    _SL13E-fd @ VFS-SIZE _SL13E-read-u @ =
    DUP IF
        DROP
        _SL13E-read-a @ _SL13E-read-u @ _SL13E-fd @
            VFS-READ-EXACT 0=
    THEN
    _SL13E-fd @ VFS-CLOSE
    0 _SL13E-fd ! ;

: _SL13E-setup  ( -- )
    VFS-CUR _SL13E-old-vfs !
    VFS-RAM-OPS _SL13E-ops VFS-OPS-SIZE MOVE
    VFS-RAM-BINDING _SL13E-binding VFS-BINDING-DESC-SIZE MOVE
    _SL13E-ops _SL13E-binding VB.OPS !
    4194304 A-XMEM ARENA-NEW
    DUP 0= _SL13E-assert DROP _SL13E-arena !
    _SL13E-arena @ _SL13E-binding 0 VFS-NEW
    _SL13E-ior ! _SL13E-vfs !
    _SL13E-ior @ 0= _SL13E-assert
    _SL13E-vfs @ 0<> _SL13E-assert
    _SL13E-vfs @ VFS-USE
    _SL13E-vfs @ _SL13E-source-store STREAMS-SOURCE-STORE-INIT
        SSSTORE-S-OK _SL13E-status
    _SL13E-vfs @ _SL13E-observation-store
        STREAMS-OBSERVATION-STORE-INIT
        OSTORE-S-OK _SL13E-status ;

: _SL13E-absent  ( -- )
    _SL13E-source-loaded STREAMS-SOURCE-REGISTRY-SIZE 0xA5 FILL
    _SL13E-source-digest SHA3-256-LEN 0xA5 FILL
    _SL13E-source-loaded STREAMS-SOURCE-REGISTRY-SIZE
        _SL13E-source-digest _SL13E-source-store
        STREAMS-SOURCE-STORE-LOAD-EVIDENCE
        _SL13E-results
    _SL13E-status-value @ SSSTORE-S-ABSENT _SL13E-status
    _SL13E-source-digest SHA3-256-LEN _SL13E-zero? _SL13E-assert
    _SL13E-source-loaded C@ 0xA5 = _SL13E-assert

    _SL13E-observation-loaded
        STREAMS-OBSERVATION-CHECKPOINT-SIZE 0xA6 FILL
    _SL13E-observation-digest SHA3-256-LEN 0xA6 FILL
    _SL13E-observation-loaded STREAMS-OBSERVATION-CHECKPOINT-SIZE
        _SL13E-observation-digest _SL13E-observation-store
        STREAMS-OBSERVATION-STORE-LOAD-EVIDENCE
        _SL13E-results
    _SL13E-status-value @ OSTORE-S-ABSENT _SL13E-status
    _SL13E-observation-digest SHA3-256-LEN
        _SL13E-zero? _SL13E-assert
    _SL13E-observation-loaded C@ 0xA6 = _SL13E-assert
    _SL13E-stack ;

: _SL13E-save  ( -- )
    _SL13E-source-candidate STREAMS-SOURCE-REGISTRY-INIT
    1 _SL13E-source-candidate SSREG.GENERATION !
    _SL13E-source-candidate STREAMS-SOURCE-REGISTRY-VALID?
        _SL13E-assert
    _SL13E-source-candidate 0 _SL13E-source-store
        STREAMS-SOURCE-STORE-SAVE
        SSSTORE-S-OK _SL13E-status

    _SL13E-observation-candidate OCHK-INIT
    1 _SL13E-observation-candidate OCHK.GENERATION !
    _SL13E-observation-candidate OCHK-SEAL
    _SL13E-observation-candidate OCHK-VALID? _SL13E-assert
    _SL13E-observation-candidate 0 _SL13E-observation-store
        STREAMS-OBSERVATION-STORE-SAVE
        OSTORE-S-OK _SL13E-status
    _SL13E-stack ;

: _SL13E-source-preflight  ( -- )
    _SL13E-source-loaded STREAMS-SOURCE-REGISTRY-SIZE 0xB5 FILL
    _SL13E-source-loaded STREAMS-SOURCE-REGISTRY-SIZE
        _SL13E-source-loaded 8 + _SL13E-source-store
        STREAMS-SOURCE-STORE-LOAD-EVIDENCE
        _SL13E-results
    _SL13E-status-value @ SSSTORE-S-INVALID _SL13E-status
    _SL13E-source-loaded 8 + C@ 0xB5 = _SL13E-assert

    _SL13E-source-digest SHA3-256-LEN 0xB6 FILL
    _SL13E-source-loaded STREAMS-SOURCE-REGISTRY-SIZE 1-
        _SL13E-source-digest _SL13E-source-store
        STREAMS-SOURCE-STORE-LOAD-EVIDENCE
        _SL13E-results
    _SL13E-status-value @ SSSTORE-S-CAPACITY _SL13E-status
    _SL13E-source-digest SHA3-256-LEN _SL13E-zero? _SL13E-assert
    _SL13E-stack ;

: _SL13E-observation-preflight  ( -- )
    _SL13E-observation-loaded
        STREAMS-OBSERVATION-CHECKPOINT-SIZE 0xC5 FILL
    _SL13E-observation-loaded STREAMS-OBSERVATION-CHECKPOINT-SIZE
        _SL13E-observation-loaded 8 + _SL13E-observation-store
        STREAMS-OBSERVATION-STORE-LOAD-EVIDENCE
        _SL13E-results
    _SL13E-status-value @ OSTORE-S-INVALID _SL13E-status
    _SL13E-observation-loaded 8 + C@ 0xC5 = _SL13E-assert

    _SL13E-observation-digest SHA3-256-LEN 0xC6 FILL
    _SL13E-observation-loaded
        STREAMS-OBSERVATION-CHECKPOINT-SIZE 1-
        _SL13E-observation-digest _SL13E-observation-store
        STREAMS-OBSERVATION-STORE-LOAD-EVIDENCE
        _SL13E-results
    _SL13E-status-value @ OSTORE-S-CAPACITY _SL13E-status
    _SL13E-observation-digest SHA3-256-LEN
        _SL13E-zero? _SL13E-assert
    _SL13E-stack ;

: _SL13E-source-evidence  ( -- )
    _SL13E-source-loaded STREAMS-SOURCE-REGISTRY-SIZE 0 FILL
    _SL13E-source-digest SHA3-256-LEN 0 FILL
    _SL13E-source-loaded STREAMS-SOURCE-REGISTRY-SIZE
        _SL13E-source-digest _SL13E-source-store
        STREAMS-SOURCE-STORE-LOAD-EVIDENCE
        _SL13E-results!
    _SL13E-status-value @ SSSTORE-S-OK _SL13E-status
    _SL13E-record-u @ STREAMS-SOURCE-STORE-RECORD-MAX =
        _SL13E-assert
    _SL13E-generation @ 1 = _SL13E-assert
    _SL13E-source-loaded STREAMS-SOURCE-REGISTRY-SIZE
        _SL13E-source-candidate STREAMS-SOURCE-REGISTRY-SIZE
        COMPARE 0= _SL13E-assert
    _SL13E-source-loaded STREAMS-SOURCE-REGISTRY-VALID?
        _SL13E-assert
    _SL13E-source-digest SHA3-256-LEN _SL13E-zero? 0=
        _SL13E-assert
    _SL13E-source-raw STREAMS-SOURCE-STORE-RECORD-MAX
        STREAMS-SOURCE-STORE-TARGET$ _SL13E-read-exact
        _SL13E-assert
    _SL13E-source-raw STREAMS-SOURCE-STORE-RECORD-MAX
        _SL13E-source-digest SHA3-256-HASH-COMPARE
        _SL13E-assert
    _SL13E-stack ;

: _SL13E-observation-evidence  ( -- )
    _SL13E-observation-loaded
        STREAMS-OBSERVATION-CHECKPOINT-SIZE 0 FILL
    _SL13E-observation-digest SHA3-256-LEN 0 FILL
    _SL13E-observation-loaded STREAMS-OBSERVATION-CHECKPOINT-SIZE
        _SL13E-observation-digest _SL13E-observation-store
        STREAMS-OBSERVATION-STORE-LOAD-EVIDENCE
        _SL13E-results!
    _SL13E-status-value @ OSTORE-S-OK _SL13E-status
    _SL13E-record-u @ STREAMS-OBSERVATION-STORE-RECORD-MAX =
        _SL13E-assert
    _SL13E-generation @ 1 = _SL13E-assert
    _SL13E-observation-loaded STREAMS-OBSERVATION-CHECKPOINT-SIZE
        _SL13E-observation-candidate
        STREAMS-OBSERVATION-CHECKPOINT-SIZE
        COMPARE 0= _SL13E-assert
    _SL13E-observation-loaded OCHK-VALID? _SL13E-assert
    _SL13E-observation-digest SHA3-256-LEN _SL13E-zero? 0=
        _SL13E-assert
    _SL13E-observation-raw STREAMS-OBSERVATION-STORE-RECORD-MAX
        STREAMS-OBSERVATION-STORE-TARGET$ _SL13E-read-exact
        _SL13E-assert
    _SL13E-observation-raw STREAMS-OBSERVATION-STORE-RECORD-MAX
        _SL13E-observation-digest SHA3-256-HASH-COMPARE
        _SL13E-assert
    _SL13E-stack ;

: _SL13E-finish  ( -- )
    _SL13E-old-vfs @ VFS-USE
    _SL13E-vfs @ VFS-DESTROY
    0 _SL13E-vfs !
    _SL13E-arena @ ARENA-DESTROY
    0 _SL13E-arena !
    _SL13E-stack
    _SL13E-fails @ IF
        ." STREAMS L13 EVIDENCE FAIL "
            _SL13E-fails @ . ." / " _SL13E-checks @ . CR
    ELSE
        ." STREAMS L13 EVIDENCE PASS " _SL13E-checks @ . CR
    THEN ;

: _SL13E-RUN  ( -- )
    0 _SL13E-checks ! 0 _SL13E-fails !
    DEPTH _SL13E-depth !
    _SL13E-setup
    _SL13E-absent
    _SL13E-save
    _SL13E-source-preflight
    _SL13E-observation-preflight
    _SL13E-source-evidence
    _SL13E-observation-evidence
    _SL13E-finish ;
