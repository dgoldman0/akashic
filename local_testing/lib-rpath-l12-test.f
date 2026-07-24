\ Focused current-topology contracts for the L12 Library repository.

PROVIDED akashic-library-rpath-l12-contracts

VARIABLE _LRP12-fails
VARIABLE _LRP12-checks
VARIABLE _LRP12-depth
VARIABLE _LRP12-arena
VARIABLE _LRP12-vfs
VARIABLE _LRP12-ior
VARIABLE _LRP12-old-vfs
VARIABLE _LRP12-cwd
VARIABLE _LRP12-library-in
VARIABLE _LRP12-target-in

VARIABLE _LRP12-path-a
VARIABLE _LRP12-path-u
VARIABLE _LRP12-leaf-a
VARIABLE _LRP12-leaf-u
VARIABLE _LRP12-target-a
VARIABLE _LRP12-target-u

VARIABLE _LRP12-link-buf
VARIABLE _LRP12-link-cap
VARIABLE _LRP12-link-in
VARIABLE _LRP12-link-target-a
VARIABLE _LRP12-link-target-u
VARIABLE _LRP12-readlink-calls

CREATE _LRP12-ops VFS-OPS-SIZE ALLOT
CREATE _LRP12-binding VFS-BINDING-DESC-SIZE ALLOT

CREATE _LRP12-cache-0 PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE _LRP12-cache-1 PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE _LRP12-builder-cache-0 PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE _LRP12-builder-cache-1 PERSIST-PAGE-CACHE-SIZE ALLOT
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _LRP12-cache-0-memory
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _LRP12-cache-1-memory
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _LRP12-builder-cache-0-memory
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _LRP12-builder-cache-1-memory
GUARD _LRP12-guard
GUARD _LRP12-builder-guard

LIBRARY-REPOSITORY-SIZE XBUF _LRP12-repository
LIBRARY-REPOSITORY-WORK-SIZE XBUF _LRP12-work
LIBRARY-REPOSITORY-RECORD-BUFFER-MIN XBUF _LRP12-record
LIBRARY-REPOSITORY-STAGE-BUFFER-MIN XBUF _LRP12-stage
LIBRARY-REPOSITORY-RECORD-BUFFER-MIN XBUF _LRP12-builder-record
512 XBUF _LRP12-compact-buffer

CREATE _LRP12-bootstrap RID-SIZE ALLOT
LIBRARY-REPOSITORY-INSPECTION-SIZE XBUF _LRP12-report
CREATE _LRP12-repaired-seal SHA3-256-LEN ALLOT

: _LRP12-assert  ( flag -- )
    1 _LRP12-checks +!
    0= IF
        1 _LRP12-fails +!
        ." LIBRARY REPOSITORY PATHS L12 ASSERT "
        _LRP12-checks @ . CR
    THEN ;

: _LRP12-stack  ( -- )
    DEPTH DUP _LRP12-depth @ <> IF
        ." LIBRARY REPOSITORY PATHS L12 STACK "
        _LRP12-depth @ . ." -> " DUP . CR .S CR
    THEN
    _LRP12-depth @ = _LRP12-assert ;

: _LRP12-status  ( actual expected -- )
    2DUP <> IF
        ." LIBRARY REPOSITORY PATHS L12 STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _LRP12-assert _LRP12-stack ;

: _LRP12-cache-init  ( memory cache -- )
    >R
    PERSIST-PAGE-CACHE-FRAME-SIZE 2 * 2 R>
    PPAGE-CACHE-INIT PERSIST-S-OK _LRP12-status ;

: _LRP12-link-return  ( target-a target-u -- actual ior )
    _LRP12-link-target-u ! _LRP12-link-target-a !
    _LRP12-link-cap @ 0= IF
        _LRP12-link-target-u @ 0 EXIT
    THEN
    _LRP12-link-target-u @ _LRP12-link-cap @ > IF
        0 VFS-E-OVERFLOW EXIT
    THEN
    _LRP12-link-target-a @ _LRP12-link-buf @
        _LRP12-link-target-u @ MOVE
    _LRP12-link-target-u @ 0 ;

: _LRP12-readlink  ( buffer capacity inode vfs -- actual ior )
    DROP _LRP12-link-in ! _LRP12-link-cap ! _LRP12-link-buf !
    1 _LRP12-readlink-calls +!
    _LRP12-link-target-a @ _LRP12-link-target-u @
        _LRP12-link-return ;

: _LRP12-binding-init  ( -- )
    VFS-RAM-OPS _LRP12-ops VFS-OPS-SIZE MOVE
    VFS-RAM-BINDING _LRP12-binding VFS-BINDING-DESC-SIZE MOVE
    _LRP12-ops _LRP12-binding VB.OPS !
    _LRP12-binding VB.CAPS DUP @
        VFS-CAP-READLINK OR SWAP !
    ['] _LRP12-readlink
        _LRP12-ops VFS-OP-READLINK CELLS + ! ;

: _LRP12-runtime-init  ( -- )
    VFS-CUR _LRP12-old-vfs !
    _LRP12-binding-init
    67108864 A-XMEM ARENA-NEW
        DUP 0= _LRP12-assert DROP _LRP12-arena !
    _LRP12-arena @ _LRP12-binding 0 VFS-NEW
        _LRP12-ior ! _LRP12-vfs !
    _LRP12-ior @ 0= _LRP12-assert
    _LRP12-vfs @ 0<> _LRP12-assert
    _LRP12-old-vfs @ VFS-USE

    _LRP12-cache-0-memory _LRP12-cache-0 _LRP12-cache-init
    _LRP12-cache-1-memory _LRP12-cache-1 _LRP12-cache-init
    _LRP12-builder-cache-0-memory
        _LRP12-builder-cache-0 _LRP12-cache-init
    _LRP12-builder-cache-1-memory
        _LRP12-builder-cache-1 _LRP12-cache-init

    S" repository-path-cwd" _LRP12-vfs @ VFS-MKDIR
        0= _LRP12-assert
    S" /repository-path-cwd" _LRP12-vfs @ VFS-RESOLVE?
    DUP 0= _LRP12-assert DROP
    DUP 0<> _LRP12-assert
    DUP _LRP12-cwd !
    _LRP12-vfs @ V.CWD !
    _LRP12-bootstrap RID-SIZE 0x52 FILL
    0 _LRP12-readlink-calls !
    _LRP12-stack ;

: _LRP12-repository-init  ( -- )
    _LRP12-vfs @
    _LRP12-cache-0 _LRP12-cache-1
    _LRP12-builder-cache-0 _LRP12-builder-cache-1
    _LRP12-guard _LRP12-builder-guard
    0 0 _LRP12-repository
    LIBRARY-REPOSITORY-INIT
        LIBRARY-REPOSITORY-S-OK _LRP12-status
    _LRP12-record LIBRARY-REPOSITORY-RECORD-BUFFER-MIN
    _LRP12-stage LIBRARY-REPOSITORY-STAGE-BUFFER-MIN
    _LRP12-builder-record LIBRARY-REPOSITORY-RECORD-BUFFER-MIN
    _LRP12-compact-buffer 512
    _LRP12-repository _LRP12-work
    LIBRARY-REPOSITORY-WORK-INIT
        LIBRARY-REPOSITORY-S-OK _LRP12-status
    _LRP12-repository LIBRARY-REPOSITORY-VALID? _LRP12-assert
    _LRP12-work LIBRARY-REPOSITORY-WORK-VALID? _LRP12-assert
    _LRP12-stack ;

: _LRP12-clean?  ( -- flag )
    _LRP12-work _LRW.BUSY @ 0=
    _LRP12-work _LRW.FD @ 0= AND
    _LRP12-work _LRW.ROOT _PROOT-W.FD @ 0= AND
    _LRP12-repository _LR.GUARD @ GUARD-HELD? 0= AND
    _LRP12-repository _LR.BUILDER-GUARD @ GUARD-HELD? 0= AND
    _LRP12-vfs @ V.OPEN-COUNT @ 0= AND
    _LRP12-vfs @ V.CWD @ _LRP12-cwd @ = AND
    VFS-CUR _LRP12-old-vfs @ = AND ;

: _LRP12-owner-reset  ( -- )
    _LRP12-repository _LRP12-work LIBRARY-REPOSITORY-FINI
        LIBRARY-REPOSITORY-S-OK _LRP12-status
    _LRP12-cache-0-memory _LRP12-cache-0 _LRP12-cache-init
    _LRP12-cache-1-memory _LRP12-cache-1 _LRP12-cache-init
    _LRP12-builder-cache-0-memory
        _LRP12-builder-cache-0 _LRP12-cache-init
    _LRP12-builder-cache-1-memory
        _LRP12-builder-cache-1 _LRP12-cache-init
    _LRP12-repository-init ;

: _LRP12-role-leaf$  ( role -- a u flag )
    CASE
        LIBRARY-REPOSITORY-EVIDENCE-ROOT-0 OF
            S" root-0" -1 ENDOF
        LIBRARY-REPOSITORY-EVIDENCE-ROOT-1 OF
            S" root-1" -1 ENDOF
        LIBRARY-REPOSITORY-EVIDENCE-PAGES-0 OF
            S" pages-0" -1 ENDOF
        LIBRARY-REPOSITORY-EVIDENCE-SEGMENTS-0 OF
            S" segments-0" -1 ENDOF
        LIBRARY-REPOSITORY-EVIDENCE-PAGES-1 OF
            S" pages-1" -1 ENDOF
        LIBRARY-REPOSITORY-EVIDENCE-SEGMENTS-1 OF
            S" segments-1" -1 ENDOF
        LIBRARY-REPOSITORY-EVIDENCE-COMPACT-ROOT-0 OF
            S" compact-root-0" -1 ENDOF
        LIBRARY-REPOSITORY-EVIDENCE-COMPACT-ROOT-1 OF
            S" compact-root-1" -1 ENDOF
        0 0 0 ROT
    ENDCASE ;

: _LRP12-role-target$  ( role -- a u flag )
    CASE
        LIBRARY-REPOSITORY-EVIDENCE-ROOT-0 OF
            S" root-0-target" -1 ENDOF
        LIBRARY-REPOSITORY-EVIDENCE-ROOT-1 OF
            S" root-1-target" -1 ENDOF
        LIBRARY-REPOSITORY-EVIDENCE-PAGES-0 OF
            S" pages-0-target" -1 ENDOF
        LIBRARY-REPOSITORY-EVIDENCE-SEGMENTS-0 OF
            S" segments-0-target" -1 ENDOF
        LIBRARY-REPOSITORY-EVIDENCE-PAGES-1 OF
            S" pages-1-target" -1 ENDOF
        LIBRARY-REPOSITORY-EVIDENCE-SEGMENTS-1 OF
            S" segments-1-target" -1 ENDOF
        LIBRARY-REPOSITORY-EVIDENCE-COMPACT-ROOT-0 OF
            S" compact-root-0-target" -1 ENDOF
        LIBRARY-REPOSITORY-EVIDENCE-COMPACT-ROOT-1 OF
            S" compact-root-1-target" -1 ENDOF
        0 0 0 ROT
    ENDCASE ;

: _LRP12-role-names!  ( role -- flag )
    DUP _LIBREPO-EVIDENCE-PATH$ 0= IF
        2DROP DROP 0 EXIT
    THEN
    _LRP12-path-u ! _LRP12-path-a !
    DUP _LRP12-role-leaf$ 0= IF
        2DROP DROP 0 EXIT
    THEN
    _LRP12-leaf-u ! _LRP12-leaf-a !
    _LRP12-role-target$ 0= IF
        2DROP 0 EXIT
    THEN
    _LRP12-target-u ! _LRP12-target-a !
    -1 ;

: _LRP12-resolve-nofollow  ( path-a path-u -- inode|0 )
    VFS-RP-NOFOLLOW-FINAL _LRP12-vfs @
        VFS-RESOLVE-POLICY?
    DUP IF 2DROP 0 EXIT THEN DROP ;

: _LRP12-rename-role-away  ( role -- flag )
    _LRP12-role-names! 0= IF 0 EXIT THEN
    _LRP12-path-a @ _LRP12-path-u @
        _LRP12-resolve-nofollow
    DUP 0= IF DROP 0 EXIT THEN
    DUP IN.TYPE @ VFS-T-FILE <> IF DROP 0 EXIT THEN
    DUP _LRP12-target-in !
    _LRP12-target-a @ _LRP12-target-u @
    ROT _LRP12-vfs @ VFS-RENAME 0= ;

: _LRP12-cache-role-link  ( role -- flag )
    _LRP12-role-names! 0= IF 0 EXIT THEN
    _LRP12-target-a @ _LRP12-link-target-a !
    _LRP12-target-u @ _LRP12-link-target-u !
    _LIBREPO-DIRECTORY$ _LRP12-resolve-nofollow
    DUP 0= IF DROP 0 EXIT THEN _LRP12-library-in !
    _LRP12-leaf-a @ _LRP12-leaf-u @
    VFS-T-SYMLINK 900 1
    _LRP12-library-in @ _LRP12-vfs @ VFS-CACHE-DENTRY
    DUP IF 2DROP 0 EXIT THEN DROP 0<> ;

: _LRP12-role-follows-target?  ( -- flag )
    _LRP12-path-a @ _LRP12-path-u @
        _LRP12-vfs @ VFS-RESOLVE?
    DUP IF 2DROP 0 EXIT THEN DROP
    _LRP12-target-in @ = ;

: _LRP12-make-role-directory  ( role -- flag )
    _LRP12-role-names! 0= IF 0 EXIT THEN
    _LIBREPO-DIRECTORY$ _LRP12-resolve-nofollow
    DUP 0= IF DROP 0 EXIT THEN
    _LRP12-vfs @ V.CWD !
    _LRP12-leaf-a @ _LRP12-leaf-u @
        _LRP12-vfs @ VFS-MKDIR
    _LRP12-cwd @ _LRP12-vfs @ V.CWD !
    0= ;

: _LRP12-restore-role  ( -- flag )
    _LRP12-path-a @ _LRP12-path-u @
        _LRP12-vfs @ VFS-RM
    DUP IF DROP 0 EXIT THEN DROP
    _LRP12-leaf-a @ _LRP12-leaf-u @
    _LRP12-target-in @ _LRP12-vfs @ VFS-RENAME 0= ;

: _LRP12-cold-corrupt  ( -- )
    _LRP12-owner-reset
    _LRP12-repository _LRP12-work LIBRARY-REPOSITORY-LOAD
        LIBRARY-REPOSITORY-S-CORRUPT _LRP12-status
    _LRP12-repository LIBRARY-REPOSITORY-BLOCKED? _LRP12-assert
    _LRP12-repository LIBRARY-REPOSITORY-GENERATION@
        0= _LRP12-assert
    _LRP12-clean? _LRP12-assert ;

: _LRP12-role-link-contract  ( role -- )
    DUP _LRP12-rename-role-away _LRP12-assert
    DUP _LRP12-cache-role-link _LRP12-assert
    DROP
    _LRP12-role-follows-target? _LRP12-assert
    0 _LRP12-readlink-calls !
    _LRP12-cold-corrupt
    _LRP12-readlink-calls @ 0= _LRP12-assert
    _LRP12-restore-role _LRP12-assert
    _LRP12-stack ;

: _LRP12-role-type-contract  ( role -- )
    DUP _LRP12-rename-role-away _LRP12-assert
    _LRP12-make-role-directory _LRP12-assert
    _LRP12-cold-corrupt
    _LRP12-restore-role _LRP12-assert
    _LRP12-stack ;

: _LRP12-cache-library-link  ( -- flag )
    S" library-target"
        _LRP12-link-target-u ! _LRP12-link-target-a !
    S" library" VFS-T-SYMLINK 899 1
    _LRP12-vfs @ V.ROOT @ _LRP12-vfs @ VFS-CACHE-DENTRY
    DUP IF 2DROP 0 EXIT THEN DROP 0<> ;

: _LRP12-provision-link-refusal  ( -- )
    _LRP12-vfs @ V.ROOT @ _LRP12-vfs @ V.CWD !
    S" library-target" _LRP12-vfs @ VFS-MKDIR
        0= _LRP12-assert
    _LRP12-cwd @ _LRP12-vfs @ V.CWD !
    S" /library-target" _LRP12-resolve-nofollow
    DUP 0<> _LRP12-assert _LRP12-library-in !
    _LRP12-cache-library-link _LRP12-assert
    0 _LRP12-readlink-calls !
    _LRP12-repository _LRP12-work LIBRARY-REPOSITORY-PROVISION
        LIBRARY-REPOSITORY-S-CORRUPT _LRP12-status
    _LRP12-readlink-calls @ 0= _LRP12-assert
    S" /library-target/pages-0" _LRP12-resolve-nofollow
        0= _LRP12-assert
    _LRP12-clean? _LRP12-assert
    S" /library" _LRP12-vfs @ VFS-RM 0= _LRP12-assert
    S" /library-target" _LRP12-vfs @ VFS-RM 0= _LRP12-assert

    _LRP12-repository _LIBREPO-ENSURE-DIRECTORY
        LIBRARY-REPOSITORY-S-OK _LRP12-status
    _LIBREPO-DIRECTORY$ _LRP12-resolve-nofollow
    DUP 0<> _LRP12-assert _LRP12-library-in !
    S" /library/pages-0-target" _LRP12-vfs @ VFS-CREATE
        DUP 0<> _LRP12-assert _LRP12-target-in !
    S" pages-0-target"
        _LRP12-link-target-u ! _LRP12-link-target-a !
    S" pages-0" VFS-T-SYMLINK 898 1
    _LRP12-library-in @ _LRP12-vfs @ VFS-CACHE-DENTRY
    DUP 0= _LRP12-assert 2DROP
    0 _LRP12-readlink-calls !
    _LRP12-repository _LRP12-work LIBRARY-REPOSITORY-PROVISION
        LIBRARY-REPOSITORY-S-CORRUPT _LRP12-status
    _LRP12-readlink-calls @ 0= _LRP12-assert
    _LRP12-target-in @ IN.SIZE-LO @ 0= _LRP12-assert
    _LRP12-target-in @ IN.SIZE-HI @ 0= _LRP12-assert
    _LIBREPO-SEGMENTS-0$ _LRP12-resolve-nofollow
        0= _LRP12-assert
    _LRP12-clean? _LRP12-assert
    _LIBREPO-PAGES-0$ _LRP12-vfs @ VFS-RM 0= _LRP12-assert
    S" /library/pages-0-target" _LRP12-vfs @ VFS-RM
        0= _LRP12-assert
    _LRP12-stack ;

: _LRP12-absent-fallback  ( -- )
    _LRP12-repository _LRP12-work LIBRARY-REPOSITORY-PROVISION
        LIBRARY-REPOSITORY-S-OK _LRP12-status
    _LRP12-bootstrap _LRP12-repository _LRP12-work
        LIBRARY-REPOSITORY-BOOTSTRAP
        LIBRARY-REPOSITORY-S-OK _LRP12-status
    _LRP12-repository LIBRARY-REPOSITORY-ACTIVE-BANK@
        PERSIST-DATA-BANK-0 = _LRP12-assert

    _LIBREPO-PAGES-1$ _LRP12-vfs @ VFS-RM 0= _LRP12-assert
    _LIBREPO-SEGMENTS-1$ _LRP12-vfs @ VFS-RM 0= _LRP12-assert
    _LRP12-owner-reset
    _LRP12-repository _LRP12-work LIBRARY-REPOSITORY-LOAD
        LIBRARY-REPOSITORY-S-OK _LRP12-status
    _LRP12-repository LIBRARY-REPOSITORY-ACTIVE-BANK@
        PERSIST-DATA-BANK-0 = _LRP12-assert
    _LRP12-clean? _LRP12-assert

    _LIBREPO-PAGES-1$ _LRP12-vfs @ VFS-CREATE
        0<> _LRP12-assert
    _LIBREPO-SEGMENTS-1$ _LRP12-vfs @ VFS-CREATE
        0<> _LRP12-assert

    _LRP12-report _LRP12-repository _LRP12-work
        LIBRARY-REPOSITORY-INSPECT
        LIBRARY-REPOSITORY-S-OK _LRP12-status
    _LRP12-report LRI.HEALTH @
        LIBRARY-REPOSITORY-HEALTH-FALLBACK = _LRP12-assert
    _LRP12-report _LRP12-repaired-seal
    _LRP12-repository _LRP12-work
        LIBRARY-REPOSITORY-ROOT-MIRROR-REPAIR
        LIBRARY-REPOSITORY-S-OK _LRP12-status

    _LIBREPO-COMPACT-ROOT-0$ _LRP12-vfs @ VFS-CREATE
        0<> _LRP12-assert
    _LIBREPO-COMPACT-ROOT-1$ _LRP12-vfs @ VFS-CREATE
        0<> _LRP12-assert
    _LRP12-repository _LIBREPO-TOPOLOGY-ALLOW-ABSENT
        LIBRARY-REPOSITORY-S-OK _LRP12-status
    _LRP12-stack ;

: _LRP12-rename-library-away  ( -- flag )
    _LIBREPO-DIRECTORY$ _LRP12-resolve-nofollow
    DUP 0= IF DROP 0 EXIT THEN
    DUP IN.TYPE @ VFS-T-DIR <> IF DROP 0 EXIT THEN
    DUP _LRP12-library-in !
    S" library-target" ROT _LRP12-vfs @ VFS-RENAME 0= ;

: _LRP12-restore-library  ( -- flag )
    _LIBREPO-DIRECTORY$ _LRP12-vfs @ VFS-RM
    DUP IF DROP 0 EXIT THEN DROP
    S" library" _LRP12-library-in @
        _LRP12-vfs @ VFS-RENAME 0= ;

: _LRP12-directory-contracts  ( -- )
    _LRP12-rename-library-away _LRP12-assert
    _LRP12-cache-library-link _LRP12-assert
    _LIBREPO-ROOT-0$ _LRP12-vfs @ VFS-RESOLVE?
    DUP 0= _LRP12-assert DROP 0<> _LRP12-assert
    0 _LRP12-readlink-calls !
    _LRP12-cold-corrupt
    _LRP12-readlink-calls @ 0= _LRP12-assert
    _LRP12-restore-library _LRP12-assert

    _LRP12-rename-library-away _LRP12-assert
    _LIBREPO-DIRECTORY$ _LRP12-vfs @ VFS-CREATE
        0<> _LRP12-assert
    _LRP12-cold-corrupt
    _LRP12-restore-library _LRP12-assert
    _LRP12-stack ;

: _LRP12-all-terminal-contracts  ( -- )
    LIBRARY-REPOSITORY-EVIDENCE-COUNT 0 ?DO
        I _LRP12-role-link-contract
        I _LRP12-role-type-contract
    LOOP
    _LRP12-stack ;

: _LRP12-finish  ( -- )
    _LRP12-owner-reset
    _LRP12-repository _LRP12-work LIBRARY-REPOSITORY-LOAD
        LIBRARY-REPOSITORY-S-OK _LRP12-status
    _LRP12-repository LIBRARY-REPOSITORY-GENERATION@
        1 = _LRP12-assert
    _LRP12-clean? _LRP12-assert
    _LRP12-repository _LRP12-work LIBRARY-REPOSITORY-FINI
        LIBRARY-REPOSITORY-S-OK _LRP12-status
    0 _LRP12-vfs @ VFS-UNMOUNT 0= _LRP12-assert
    _LRP12-vfs @ VFS-DESTROY
    _LRP12-old-vfs @ VFS-USE
    _LRP12-arena @ ARENA-DESTROY
    _LRP12-stack ;

: _LRP12-RUN  ( -- )
    0 _LRP12-fails !
    0 _LRP12-checks !
    DEPTH _LRP12-depth !
    _LRP12-runtime-init
    _LRP12-repository-init
    _LRP12-repository _LRP12-work LIBRARY-REPOSITORY-LOAD
        LIBRARY-REPOSITORY-S-ABSENT _LRP12-status
    _LRP12-clean? _LRP12-assert
    _LRP12-provision-link-refusal
    _LRP12-absent-fallback
    _LRP12-directory-contracts
    _LRP12-all-terminal-contracts
    _LRP12-finish
    _LRP12-fails @ IF
        ." LIBRARY REPOSITORY PATHS L12 FAIL "
        _LRP12-fails @ . ." /" _LRP12-checks @ . CR
    ELSE
        ." LIBRARY REPOSITORY PATHS L12 PASS "
        _LRP12-checks @ . CR
    THEN ;
