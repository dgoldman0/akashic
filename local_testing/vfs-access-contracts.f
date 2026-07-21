\ vfs-access-contracts.f - neutral scoped VFS access contracts
\
\ The fixture uses two independent cloned RAM bindings.  It tests byte access
\ and resource cleanup only; no replacement, record, generation, or applet
\ policy is present here.

PROVIDED akashic-vfs-access-contracts

VARIABLE _vfac-fails
VARIABLE _vfac-checks
VARIABLE _vfac-depth
VARIABLE _vfac-byte
VARIABLE _vfac-old-vfs
VARIABLE _vfac-arena-a
VARIABLE _vfac-arena-b
VARIABLE _vfac-vfs-a
VARIABLE _vfac-vfs-b
VARIABLE _vfac-cwd-a
VARIABLE _vfac-cwd-b
VARIABLE _vfac-fd
VARIABLE _vfac-fd-a
VARIABLE _vfac-fd-b
VARIABLE _vfac-ior
VARIABLE _vfac-length
VARIABLE _vfac-total
VARIABLE _vfac-truncated
VARIABLE _vfac-delivered
VARIABLE _vfac-stopped
VARIABLE _vfac-free-before
VARIABLE _vfac-evict-cwd

CREATE _vfac-ops-a VFS-OPS-SIZE ALLOT
CREATE _vfac-ops-b VFS-OPS-SIZE ALLOT
CREATE _vfac-binding-a VFS-BINDING-DESC-SIZE ALLOT
CREATE _vfac-binding-b VFS-BINDING-DESC-SIZE ALLOT
CREATE _vfac-scope-a VFA-SCOPE-SIZE ALLOT
CREATE _vfac-scope-b VFA-SCOPE-SIZE ALLOT
CREATE _vfac-scope-c VFA-SCOPE-SIZE ALLOT
CREATE _vfac-stream VFA-STREAM-SIZE ALLOT
CREATE _vfac-buffer 128 ALLOT
CREATE _vfac-output 128 ALLOT
CREATE _vfac-scratch 8 ALLOT
CREATE _vfac-invalid VFA-SCOPE-SIZE ALLOT

VARIABLE _vfac-old-open-xt
VARIABLE _vfac-old-release-xt
VARIABLE _vfac-old-read-xt
VARIABLE _vfac-open-mode
VARIABLE _vfac-open-calls
VARIABLE _vfac-release-mode
VARIABLE _vfac-release-calls
VARIABLE _vfac-read-fault-at
VARIABLE _vfac-read-calls

VARIABLE _vfac-close-calls
VARIABLE _vfac-use-calls
VARIABLE _vfac-use-fault-at

VARIABLE _vfac-cb-stream
VARIABLE _vfac-cb-a
VARIABLE _vfac-cb-u
VARIABLE _vfac-cb-calls
VARIABLE _vfac-cb-offset
VARIABLE _vfac-cb-copied
VARIABLE _vfac-cb-stop-at
VARIABLE _vfac-cb-throw-at
VARIABLE _vfac-cb-context
VARIABLE _vfac-cb-reinit

: _vfac-assert  ( flag -- )
    1 _vfac-checks +!
    0= IF 1 _vfac-fails +! ." VFAC ASSERT " _vfac-checks @ . CR THEN ;

: _vfac-stack  ( -- )
    DEPTH DUP _vfac-depth @ <> IF
        ." VFAC STACK " _vfac-depth @ . ."  -> " DUP . CR .S CR
    THEN
    _vfac-depth @ = _vfac-assert ;

: _vfac-filled?  ( address length byte -- flag )
    _vfac-byte !
    0 ?DO
        DUP I + C@ _vfac-byte @ <> IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _vfac-overflow?  ( ior -- flag )
    VFS-IOR-REASON VFS-R-OVERFLOW = ;

: _vfac-busy?  ( ior -- flag )
    VFS-IOR-REASON VFS-R-BUSY = ;

\ The wrappers keep the RAM implementation but expose deterministic boundary
\ faults.  Mode 1 throws before the underlying operation; mode 2 throws after
\ the underlying operation has returned successfully.
: _vfac-fault-open  ( inode vfs -- cookie ior )
    1 _vfac-open-calls +!
    _vfac-open-mode @ 1 = IF 2DROP -7901 THROW THEN
    _vfac-old-open-xt @ EXECUTE
    _vfac-open-mode @ 2 = IF 2DROP -7902 THROW THEN ;

: _vfac-fault-release  ( cookie inode vfs -- ior )
    1 _vfac-release-calls +!
    _vfac-release-mode @ 1 = IF DROP 2DROP -7911 THROW THEN
    _vfac-old-release-xt @ EXECUTE
    _vfac-release-mode @ 2 = IF DROP -7912 THROW THEN ;

: _vfac-fault-read  ( buffer length offset inode vfs -- actual ior )
    1 _vfac-read-calls +!
    _vfac-read-fault-at @ 0<>
    _vfac-read-calls @ _vfac-read-fault-at @ = AND IF
        2DROP 2DROP DROP 0 VFS-E-IO EXIT
    THEN
    _vfac-old-read-xt @ EXECUTE ;

: _vfac-count-close  ( fd -- ior )
    1 _vfac-close-calls +! VFS-CLOSE? ;

: _vfac-close-after  ( fd -- ior )
    VFS-CLOSE? DUP IF EXIT THEN DROP
    1 _vfac-close-calls +! -7921 THROW ;

: _vfac-use-after  ( vfs -- )
    VFS-USE
    1 _vfac-use-calls +!
    _vfac-use-fault-at @ 0<>
    _vfac-use-calls @ _vfac-use-fault-at @ = AND IF -7922 THROW THEN ;

: _vfac-body-ok  ( -- ) ;
: _vfac-body-throw  ( -- )  -7931 THROW ;
: _vfac-body-reopen  ( -- )
    _vfac-scope-a VFA-SCOPE-CLOSE? -7921 = _vfac-assert
    S" data.bin" VFS-FF-READ _vfac-scope-a VFA-SCOPE-OPEN?
    _vfac-ior ! _vfac-fd !
    _vfac-ior @ 0= _vfac-assert _vfac-fd @ 0<> _vfac-assert ;

: _vfac-stream-callback  ( stream -- action ior )
    _vfac-cb-stream !
    1 _vfac-cb-calls +!
    _vfac-cb-stream @ VFA-STREAM-CONTEXT@ _vfac-cb-context @ =
        _vfac-assert
    _vfac-cb-stream @ VFA-STREAM-OFFSET@ _vfac-cb-offset @ =
        _vfac-assert
    _vfac-cb-stream @ VFA-STREAM-DATA@
    _vfac-cb-u ! _vfac-cb-a !
    _vfac-cb-u @ 0> _vfac-assert
    _vfac-cb-u @ 4 <= _vfac-assert
    _vfac-cb-a @ _vfac-output _vfac-cb-copied @ +
        _vfac-cb-u @ MOVE
    _vfac-cb-u @ _vfac-cb-copied +!
    _vfac-cb-u @ _vfac-cb-offset +!
    _vfac-cb-reinit @ IF
        0 _vfac-cb-reinit !
        _vfac-fd @ 0 1 _vfac-scratch 4 ['] _vfac-stream-callback 82
            _vfac-stream VFA-STREAM-INIT _vfac-busy? _vfac-assert
    THEN
    _vfac-cb-throw-at @ _vfac-cb-calls @ = IF -7932 THROW THEN
    _vfac-cb-stop-at @ _vfac-cb-calls @ = IF
        VFA-STREAM-STOP 0
    ELSE
        VFA-STREAM-CONTINUE 0
    THEN ;

: _vfac-callback-reset  ( context -- )
    _vfac-cb-context !
    0 _vfac-cb-calls ! 0 _vfac-cb-copied !
    0 _vfac-cb-stop-at ! 0 _vfac-cb-throw-at !
    0 _vfac-cb-reinit !
    _vfac-output 128 [CHAR] ? FILL ;

: _vfac-scope-init-a  ( scope -- )
    _vfac-vfs-a @ SWAP VFA-SCOPE-INIT 0= _vfac-assert ;

: _vfac-scope-init-b  ( scope -- )
    _vfac-vfs-b @ SWAP VFA-SCOPE-INIT 0= _vfac-assert ;

: _vfac-open-a  ( scope -- fd )
    >R S" data.bin" VFS-FF-READ R> VFA-SCOPE-OPEN?
    _vfac-ior ! DUP _vfac-fd !
    _vfac-ior @ 0= _vfac-assert DUP 0<> _vfac-assert ;

: _vfac-open-b  ( scope -- fd )
    >R S" data.bin" VFS-FF-READ R> VFA-SCOPE-OPEN?
    _vfac-ior ! DUP _vfac-fd !
    _vfac-ior @ 0= _vfac-assert DUP 0<> _vfac-assert ;

: _vfac-put-a  ( -- )
    _vfac-vfs-a @ VFS-USE
    S" alpha" _vfac-vfs-a @ VFS-MKDIR 0= _vfac-assert
    S" /alpha" _vfac-vfs-a @ VFS-CD? 0= _vfac-assert
    S" data.bin" _vfac-vfs-a @ VFS-MKFILE 0<> _vfac-assert
    S" data.bin" VFS-FF-READ VFS-FF-WRITE OR _vfac-vfs-a @ VFS-OPEN?
    _vfac-ior ! _vfac-fd !
    _vfac-ior @ 0= _vfac-assert _vfac-fd @ 0<> _vfac-assert
    S" abcdefghijklmnop" _vfac-fd @ VFS-WRITE-EXACT 0= _vfac-assert
    _vfac-fd @ VFS-CLOSE? 0= _vfac-assert
    _vfac-vfs-a @ V.CWD @ _vfac-cwd-a ! ;

: _vfac-put-b  ( -- )
    _vfac-vfs-b @ VFS-USE
    S" beta" _vfac-vfs-b @ VFS-MKDIR 0= _vfac-assert
    S" /beta" _vfac-vfs-b @ VFS-CD? 0= _vfac-assert
    S" data.bin" _vfac-vfs-b @ VFS-MKFILE 0<> _vfac-assert
    S" data.bin" VFS-FF-READ VFS-FF-WRITE OR _vfac-vfs-b @ VFS-OPEN?
    _vfac-ior ! _vfac-fd !
    _vfac-ior @ 0= _vfac-assert _vfac-fd @ 0<> _vfac-assert
    S" ABCDEFGHIJKLMNOP" _vfac-fd @ VFS-WRITE-EXACT 0= _vfac-assert
    _vfac-fd @ VFS-CLOSE? 0= _vfac-assert
    _vfac-vfs-b @ V.CWD @ _vfac-cwd-b ! ;

: _vfac-range-contracts  ( -- )
    0 VFS-USE
    _vfac-scope-a _vfac-scope-init-a
    _vfac-scope-a _vfac-open-a _vfac-fd !
    VFS-CUR _vfac-vfs-a @ = _vfac-assert

    _vfac-buffer 128 [CHAR] ? FILL
    _vfac-buffer 5 3 _vfac-fd @ VFA-READ-RANGE? 0= _vfac-assert
    _vfac-buffer 5 S" defgh" COMPARE 0= _vfac-assert

    \ Empty ranges are valid at EOF and cannot touch the destination.
    _vfac-buffer 128 [CHAR] ? FILL
    _vfac-buffer 0 16 _vfac-fd @ VFA-READ-RANGE? 0= _vfac-assert
    _vfac-buffer 128 [CHAR] ? _vfac-filled? _vfac-assert

    \ A nonempty EOF range, a start past EOF, and an end past EOF are exact
    \ overflow failures and leave caller bytes unchanged.
    _vfac-buffer 128 [CHAR] ? FILL
    _vfac-buffer 1 16 _vfac-fd @ VFA-READ-RANGE?
        _vfac-overflow? _vfac-assert
    _vfac-buffer 0 17 _vfac-fd @ VFA-READ-RANGE?
        _vfac-overflow? _vfac-assert
    _vfac-buffer 2 15 _vfac-fd @ VFA-READ-RANGE?
        _vfac-overflow? _vfac-assert
    _vfac-buffer 128 [CHAR] ? _vfac-filled? _vfac-assert

    \ Unsigned offset-plus-length wrap is rejected before seek or read.
    _vfac-buffer 8 -4 _vfac-fd @ VFA-READ-RANGE?
        _vfac-overflow? _vfac-assert
    _vfac-buffer -1 0 _vfac-fd @ VFA-READ-RANGE?
        _vfac-overflow? _vfac-assert
    _vfac-buffer 128 [CHAR] ? _vfac-filled? _vfac-assert

    _vfac-scope-a VFA-SCOPE-CLOSE? 0= _vfac-assert
    VFS-CUR 0= _vfac-assert
    _vfac-stack ;

: _vfac-file-contracts  ( -- )
    0 VFS-USE
    _vfac-scope-a _vfac-scope-init-a
    _vfac-scope-a _vfac-open-a _vfac-fd !
    _vfac-fd @ VFA-FILE-SIZE? _vfac-ior ! _vfac-total !
    _vfac-ior @ 0= _vfac-assert _vfac-total @ 16 = _vfac-assert
    _vfac-buffer 128 [CHAR] ? FILL
    _vfac-buffer 16 _vfac-fd @ VFA-READ-FILE?
    _vfac-ior ! _vfac-length !
    _vfac-ior @ 0= _vfac-assert _vfac-length @ 16 = _vfac-assert
    _vfac-buffer 16 S" abcdefghijklmnop" COMPARE 0= _vfac-assert
    _vfac-scope-a VFA-SCOPE-CLOSE? 0= _vfac-assert

    \ Complete reads preflight total size.  Over-capacity is nonmutating and
    \ does not advance the descriptor.
    _vfac-scope-a _vfac-scope-init-a
    _vfac-scope-a _vfac-open-a _vfac-fd !
    _vfac-buffer 128 [CHAR] ? FILL
    _vfac-buffer 15 _vfac-fd @ VFA-READ-FILE?
    _vfac-ior ! _vfac-length !
    _vfac-length @ 0= _vfac-assert
    _vfac-ior @ _vfac-overflow? _vfac-assert
    _vfac-buffer 128 [CHAR] ? _vfac-filled? _vfac-assert
    _vfac-fd @ VFS-TELL 0= _vfac-assert
    _vfac-scope-a VFA-SCOPE-CLOSE? 0= _vfac-assert

    \ Prefix reads report both copied and total lengths and make truncation
    \ explicit rather than treating it as complete input.
    _vfac-scope-a _vfac-scope-init-a
    _vfac-scope-a _vfac-open-a _vfac-fd !
    _vfac-buffer 128 [CHAR] ? FILL
    _vfac-buffer 5 _vfac-fd @ VFA-READ-PREFIX?
    _vfac-ior ! _vfac-truncated ! _vfac-total ! _vfac-length !
    _vfac-ior @ 0= _vfac-assert
    _vfac-length @ 5 = _vfac-assert _vfac-total @ 16 = _vfac-assert
    _vfac-truncated @ _vfac-assert
    _vfac-buffer 5 S" abcde" COMPARE 0= _vfac-assert
    _vfac-buffer 5 + 123 [CHAR] ? _vfac-filled? _vfac-assert
    _vfac-scope-a VFA-SCOPE-CLOSE? 0= _vfac-assert

    _vfac-scope-a _vfac-scope-init-a
    _vfac-scope-a _vfac-open-a _vfac-fd !
    _vfac-buffer 16 _vfac-fd @ VFA-READ-PREFIX?
    _vfac-ior ! _vfac-truncated ! _vfac-total ! _vfac-length !
    _vfac-ior @ 0= _vfac-assert
    _vfac-length @ 16 = _vfac-assert _vfac-total @ 16 = _vfac-assert
    _vfac-truncated @ 0= _vfac-assert
    _vfac-scope-a VFA-SCOPE-CLOSE? 0= _vfac-assert

    \ A backend failure reports no accepted prefix bytes.  The preflighted
    \ total and truncation state remain available for diagnosis.
    _vfac-scope-a _vfac-scope-init-a
    _vfac-scope-a _vfac-open-a _vfac-fd !
    _vfac-buffer 128 [CHAR] ? FILL
    0 _vfac-read-calls ! 1 _vfac-read-fault-at !
    _vfac-buffer 5 _vfac-fd @ VFA-READ-PREFIX?
    _vfac-ior ! _vfac-truncated ! _vfac-total ! _vfac-length !
    _vfac-length @ 0= _vfac-assert _vfac-total @ 16 = _vfac-assert
    _vfac-truncated @ _vfac-assert
    _vfac-ior @ VFS-IOR-REASON VFS-R-IO = _vfac-assert
    _vfac-buffer 128 [CHAR] ? _vfac-filled? _vfac-assert
    0 _vfac-read-fault-at !
    _vfac-scope-a VFA-SCOPE-CLOSE? 0= _vfac-assert
    VFS-CUR 0= _vfac-assert
    _vfac-stack ;

: _vfac-stream-open  ( -- )
    0 VFS-USE
    _vfac-scope-c _vfac-scope-init-a
    _vfac-scope-c _vfac-open-a _vfac-fd ! ;

: _vfac-stream-close  ( -- )
    _vfac-scope-c VFA-SCOPE-CLOSE? 0= _vfac-assert
    VFS-CUR 0= _vfac-assert ;

: _vfac-stream-contracts  ( -- )
    \ Exact chunks carry borrowed bytes, absolute offsets, and caller context.
    _vfac-stream-open 77 _vfac-callback-reset 2 _vfac-cb-offset !
    _vfac-fd @ 2 9 _vfac-scratch 4 ['] _vfac-stream-callback 77
        _vfac-stream VFA-STREAM-INIT 0= _vfac-assert
    _vfac-stream VFA-STREAM-RUN
    _vfac-ior ! _vfac-stopped ! _vfac-delivered !
    _vfac-ior @ 0= _vfac-assert _vfac-stopped @ 0= _vfac-assert
    _vfac-delivered @ 9 = _vfac-assert _vfac-cb-calls @ 3 = _vfac-assert
    _vfac-output 9 S" cdefghijk" COMPARE 0= _vfac-assert
    _vfac-stream-close

    \ Zero bytes at EOF invoke no callback.
    _vfac-stream-open 78 _vfac-callback-reset 16 _vfac-cb-offset !
    _vfac-fd @ 16 0 _vfac-scratch 4 ['] _vfac-stream-callback 78
        _vfac-stream VFA-STREAM-INIT 0= _vfac-assert
    _vfac-stream VFA-STREAM-RUN
    _vfac-ior ! _vfac-stopped ! _vfac-delivered !
    _vfac-ior @ 0= _vfac-assert _vfac-delivered @ 0= _vfac-assert
    _vfac-stopped @ 0= _vfac-assert _vfac-cb-calls @ 0= _vfac-assert
    _vfac-stream-close

    \ STOP is a successful early return after the accepted current chunk.
    _vfac-stream-open 79 _vfac-callback-reset 0 _vfac-cb-offset !
    2 _vfac-cb-stop-at !
    _vfac-fd @ 0 16 _vfac-scratch 4 ['] _vfac-stream-callback 79
        _vfac-stream VFA-STREAM-INIT 0= _vfac-assert
    _vfac-stream VFA-STREAM-RUN
    _vfac-ior ! _vfac-stopped ! _vfac-delivered !
    _vfac-ior @ 0= _vfac-assert _vfac-stopped @ _vfac-assert
    _vfac-delivered @ 8 = _vfac-assert _vfac-cb-calls @ 2 = _vfac-assert
    _vfac-output 8 S" abcdefgh" COMPARE 0= _vfac-assert
    _vfac-stream-close

    \ Callback exceptions become a reported primary failure; no later chunk
    \ is delivered and the enclosing scope remains independently closeable.
    _vfac-stream-open 80 _vfac-callback-reset 0 _vfac-cb-offset !
    1 _vfac-cb-throw-at !
    _vfac-fd @ 0 16 _vfac-scratch 4 ['] _vfac-stream-callback 80
        _vfac-stream VFA-STREAM-INIT 0= _vfac-assert
    _vfac-stream VFA-STREAM-RUN
    _vfac-ior ! _vfac-stopped ! _vfac-delivered !
    _vfac-ior @ -7932 = _vfac-assert _vfac-cb-calls @ 1 = _vfac-assert
    _vfac-stream-close

    \ A backend read fault after one chunk retains exact delivered progress.
    _vfac-stream-open 81 _vfac-callback-reset 0 _vfac-cb-offset !
    0 _vfac-read-calls ! 2 _vfac-read-fault-at !
    _vfac-fd @ 0 16 _vfac-scratch 4 ['] _vfac-stream-callback 81
        _vfac-stream VFA-STREAM-INIT 0= _vfac-assert
    _vfac-stream VFA-STREAM-RUN
    _vfac-ior ! _vfac-stopped ! _vfac-delivered !
    _vfac-ior @ VFS-IOR-REASON VFS-R-IO = _vfac-assert
    _vfac-delivered @ 4 = _vfac-assert _vfac-cb-calls @ 1 = _vfac-assert
    0 _vfac-read-fault-at !
    _vfac-stream-close

    \ Reinitializing the running descriptor from its callback is BUSY and
    \ cannot replace the current stream's range, callback, or progress.
    _vfac-stream-open 82 _vfac-callback-reset 0 _vfac-cb-offset !
    -1 _vfac-cb-reinit !
    _vfac-fd @ 0 8 _vfac-scratch 4 ['] _vfac-stream-callback 82
        _vfac-stream VFA-STREAM-INIT 0= _vfac-assert
    _vfac-stream VFA-STREAM-RUN
    _vfac-ior ! _vfac-stopped ! _vfac-delivered !
    _vfac-ior @ 0= _vfac-assert _vfac-stopped @ 0= _vfac-assert
    _vfac-delivered @ 8 = _vfac-assert _vfac-cb-calls @ 2 = _vfac-assert
    _vfac-output 8 S" abcdefgh" COMPARE 0= _vfac-assert
    _vfac-stream-close
    _vfac-stack ;

: _vfac-scope-contracts  ( -- )
    _vfac-invalid VFA-SCOPE-SIZE 0 FILL
    _vfac-invalid VFA-SCOPE-VALID? 0= _vfac-assert
    _vfac-scope-a _vfac-scope-init-a
    _vfac-scope-a VFA-SCOPE-VALID? _vfac-assert
    _vfac-scope-a VFA-SCOPE-VFS@ _vfac-vfs-a @ = _vfac-assert
    _vfac-scope-a VFA-SCOPE-FD@ 0= _vfac-assert

    \ Even an unpinned, empty active CWD is not evictable.  Temporarily expose
    \ targeted-reload capability so that, once another CWD is active, the same
    \ otherwise eligible dentry can be reclaimed.
    _vfac-vfs-b @ VFS-USE
    S" evict-cwd" _vfac-vfs-b @ VFS-MKDIR 0= _vfac-assert
    S" evict-cwd" _vfac-vfs-b @ VFS-CD? 0= _vfac-assert
    _vfac-vfs-b @ V.CWD @ DUP 0<> _vfac-assert _vfac-evict-cwd !
    _vfac-evict-cwd @ IN.FLAGS DUP @ VFS-IF-PINNED INVERT AND SWAP !
    VFS-CAP-LOOKUP _vfac-binding-b VB.CAPS DUP @ ROT OR SWAP !
    _vfac-evict-cwd @ _vfac-vfs-b @ _VFS-EVICT-INODE 0= _vfac-assert
    _vfac-cwd-b @ _vfac-vfs-b @ V.CWD !
    _vfac-evict-cwd @ _vfac-vfs-b @ _VFS-EVICT-INODE _vfac-assert
    _vfac-binding-b VB.CAPS DUP @ VFS-CAP-LOOKUP INVERT AND SWAP !

    \ One scope restores both the prior selector and its target's prior CWD.
    \ Clear the RAM binding's ordinary pin so this also proves the scope's
    \ temporary CWD eviction hold and exact release of that hold.
    _vfac-cwd-b @ IN.FLAGS DUP @ VFS-IF-PINNED INVERT AND SWAP !
    _vfac-cwd-b @ IN.FLAGS @ VFS-IF-PINNED AND 0= _vfac-assert
    0 VFS-USE
    _vfac-scope-b _vfac-scope-init-b
    _vfac-scope-b _vfac-open-b _vfac-fd !
    VFS-CUR _vfac-vfs-b @ = _vfac-assert
    _vfac-cwd-b @ IN.FLAGS @ VFS-IF-PINNED AND _vfac-assert
    S" /" _vfac-vfs-b @ VFS-CD? 0= _vfac-assert
    _vfac-vfs-b @ V.CWD @ _vfac-cwd-b @ <> _vfac-assert
    _vfac-scope-b VFA-SCOPE-CLOSE? 0= _vfac-assert
    VFS-CUR 0= _vfac-assert
    _vfac-vfs-b @ V.CWD @ _vfac-cwd-b @ = _vfac-assert
    _vfac-cwd-b @ IN.FLAGS @ VFS-IF-PINNED AND 0= _vfac-assert
    _vfac-vfs-a @ V.CWD @ _vfac-cwd-a @ = _vfac-assert

    \ Two caller-owned scopes nest without sharing descriptors.  Explicit-FD
    \ access to the outer scope remains correct while the inner VFS is current.
    0 VFS-USE
    _vfac-scope-a _vfac-scope-init-a
    _vfac-scope-b _vfac-scope-init-b
    _vfac-scope-a _vfac-open-a _vfac-fd-a !
    _vfac-scope-b _vfac-open-b _vfac-fd-b !
    _vfac-fd-a @ _vfac-fd-b @ <> _vfac-assert
    VFS-CUR _vfac-vfs-b @ = _vfac-assert
    _vfac-buffer 4 0 _vfac-fd-a @ VFA-READ-RANGE? 0= _vfac-assert
    _vfac-buffer 4 S" abcd" COMPARE 0= _vfac-assert
    _vfac-buffer 4 0 _vfac-fd-b @ VFA-READ-RANGE? 0= _vfac-assert
    _vfac-buffer 4 S" ABCD" COMPARE 0= _vfac-assert
    _vfac-scope-b VFA-SCOPE-CLOSE? 0= _vfac-assert
    VFS-CUR _vfac-vfs-a @ = _vfac-assert
    _vfac-scope-a VFA-SCOPE-CLOSE? 0= _vfac-assert
    VFS-CUR 0= _vfac-assert
    _vfac-vfs-a @ V.OPEN-COUNT @ 0= _vfac-assert
    _vfac-vfs-b @ V.OPEN-COUNT @ 0= _vfac-assert

    \ A second open on one descriptor is BUSY and cannot replace ownership.
    _vfac-scope-a _vfac-scope-init-a
    0 _vfac-close-calls !
    ['] _vfac-count-close _vfac-scope-a VFA-SCOPE-CLOSE-XT!
        0= _vfac-assert
    _vfac-scope-a _vfac-open-a _vfac-fd-a !
    S" data.bin" VFS-FF-READ _vfac-scope-a VFA-SCOPE-OPEN?
    _vfac-ior ! _vfac-fd-b !
    _vfac-fd-b @ 0= _vfac-assert _vfac-ior @ _vfac-busy? _vfac-assert
    _vfac-scope-a VFA-SCOPE-FD@ _vfac-fd-a @ = _vfac-assert
    _vfac-scope-a VFA-SCOPE-CLOSE? 0= _vfac-assert
    _vfac-close-calls @ 1 = _vfac-assert
    _vfac-scope-a VFA-SCOPE-CLOSE? DROP
    _vfac-close-calls @ 1 = _vfac-assert
    _vfac-scope-a VFA-SCOPE-FD@ 0= _vfac-assert
    _vfac-vfs-a @ V.OPEN-COUNT @ 0= _vfac-assert
    _vfac-stack ;

: _vfac-cleanup-fault-contracts  ( -- )
    \ Close-after-success is attempted once.  Ambiguous cleanup is retained,
    \ while the core FD has already been released and cannot be retried.
    0 VFS-USE
    _vfac-scope-a _vfac-scope-init-a
    0 _vfac-close-calls !
    ['] _vfac-close-after _vfac-scope-a VFA-SCOPE-CLOSE-XT!
        0= _vfac-assert
    _vfac-scope-a _vfac-open-a DROP
    _vfac-scope-a VFA-SCOPE-CLOSE? _vfac-ior !
    _vfac-ior @ 0<> _vfac-assert _vfac-close-calls @ 1 = _vfac-assert
    _vfac-scope-a VFA-SCOPE-CLEANUP@ _vfac-ior @ = _vfac-assert
    _vfac-scope-a VFA-SCOPE-PRIMARY@ 0= _vfac-assert
    _vfac-scope-a VFA-SCOPE-FD@ 0= _vfac-assert
    _vfac-vfs-a @ V.OPEN-COUNT @ 0= _vfac-assert
    _vfac-scope-a VFA-SCOPE-CLOSE? DROP
    _vfac-close-calls @ 1 = _vfac-assert

    \ Restore-after-success leaves the prior selector installed, is attempted
    \ once, and remains visible as cleanup uncertainty.
    _vfac-scope-a _vfac-scope-init-a
    0 _vfac-use-calls ! 2 _vfac-use-fault-at !
    ['] _vfac-use-after _vfac-scope-a VFA-SCOPE-USE-XT!
        0= _vfac-assert
    _vfac-scope-a _vfac-open-a DROP
    _vfac-scope-a VFA-SCOPE-CLOSE? _vfac-ior !
    _vfac-ior @ 0<> _vfac-assert _vfac-use-calls @ 2 = _vfac-assert
    VFS-CUR 0= _vfac-assert
    _vfac-vfs-a @ V.CWD @ _vfac-cwd-a @ = _vfac-assert
    _vfac-scope-a VFA-SCOPE-FD@ 0= _vfac-assert
    0 _vfac-use-fault-at !

    \ CALL never lets cleanup replace the primary exception.
    _vfac-scope-a _vfac-scope-init-a
    0 _vfac-close-calls !
    ['] _vfac-close-after _vfac-scope-a VFA-SCOPE-CLOSE-XT!
        0= _vfac-assert
    _vfac-scope-a _vfac-open-a DROP
    ['] _vfac-body-throw _vfac-scope-a VFA-SCOPE-CALL
    _vfac-ior ! _vfac-length !
    _vfac-length @ -7931 = _vfac-assert
    _vfac-ior @ -7921 = _vfac-assert
    _vfac-scope-a VFA-SCOPE-PRIMARY@ -7931 = _vfac-assert
    _vfac-scope-a VFA-SCOPE-CLEANUP@ -7921 = _vfac-assert
    _vfac-close-calls @ 1 = _vfac-assert
    _vfac-vfs-a @ V.OPEN-COUNT @ 0= _vfac-assert

    \ Cleanup uncertainty survives an explicit close and reopen in one CALL;
    \ each owned descriptor is still closed exactly once.
    _vfac-scope-a _vfac-scope-init-a
    0 _vfac-close-calls !
    ['] _vfac-close-after _vfac-scope-a VFA-SCOPE-CLOSE-XT!
        0= _vfac-assert
    _vfac-scope-a _vfac-open-a DROP
    ['] _vfac-body-reopen _vfac-scope-a VFA-SCOPE-CALL
    _vfac-ior ! _vfac-length !
    _vfac-length @ 0= _vfac-assert _vfac-ior @ -7921 = _vfac-assert
    _vfac-scope-a VFA-SCOPE-PRIMARY@ 0= _vfac-assert
    _vfac-scope-a VFA-SCOPE-CLEANUP@ -7921 = _vfac-assert
    _vfac-close-calls @ 2 = _vfac-assert
    _vfac-vfs-a @ V.OPEN-COUNT @ 0= _vfac-assert
    _vfac-stack ;

: _vfac-core-throw-contracts  ( -- )
    \ Binding OPEN exceptions must not consume a core FD or leave a selector.
    0 VFS-USE
    _vfac-vfs-a @ V.FDFREE @ _vfac-free-before !
    0 _vfac-open-calls ! 2 _vfac-open-mode !
    _vfac-scope-a _vfac-scope-init-a
    S" data.bin" VFS-FF-READ _vfac-scope-a VFA-SCOPE-OPEN?
    _vfac-ior ! _vfac-fd !
    _vfac-fd @ 0= _vfac-assert _vfac-ior @ -7902 = _vfac-assert
    _vfac-open-calls @ 1 = _vfac-assert
    _vfac-vfs-a @ V.OPEN-COUNT @ 0= _vfac-assert
    _vfac-vfs-a @ V.FDFREE @ _vfac-free-before @ = _vfac-assert
    _vfac-scope-a VFA-SCOPE-FD@ 0= _vfac-assert
    _vfac-scope-a VFA-SCOPE-PRIMARY@ -7902 = _vfac-assert
    VFS-CUR 0= _vfac-assert
    0 _vfac-open-mode !

    \ The before-effect OPEN throw is also returned exactly and releases the
    \ provisional core descriptor without invoking the binding operation.
    _vfac-vfs-a @ V.FDFREE @ _vfac-free-before !
    0 _vfac-open-calls ! 1 _vfac-open-mode !
    _vfac-scope-a _vfac-scope-init-a
    S" data.bin" VFS-FF-READ _vfac-scope-a VFA-SCOPE-OPEN?
    _vfac-ior ! _vfac-fd !
    _vfac-fd @ 0= _vfac-assert _vfac-ior @ -7901 = _vfac-assert
    _vfac-open-calls @ 1 = _vfac-assert
    _vfac-vfs-a @ V.OPEN-COUNT @ 0= _vfac-assert
    _vfac-vfs-a @ V.FDFREE @ _vfac-free-before @ = _vfac-assert
    _vfac-scope-a VFA-SCOPE-FD@ 0= _vfac-assert
    _vfac-scope-a VFA-SCOPE-PRIMARY@ -7901 = _vfac-assert
    VFS-CUR 0= _vfac-assert
    0 _vfac-open-mode !

    \ Binding RELEASE exceptions are returned only after core ownership is
    \ retired, so an access scope cannot retry an ambiguous release.
    _vfac-vfs-a @ V.FDFREE @ _vfac-free-before !
    _vfac-scope-a _vfac-scope-init-a
    _vfac-scope-a _vfac-open-a DROP
    0 _vfac-release-calls ! 2 _vfac-release-mode !
    _vfac-scope-a VFA-SCOPE-CLOSE? _vfac-ior !
    _vfac-ior @ -7912 = _vfac-assert _vfac-release-calls @ 1 = _vfac-assert
    _vfac-vfs-a @ V.OPEN-COUNT @ 0= _vfac-assert
    _vfac-vfs-a @ V.FDFREE @ _vfac-free-before @ = _vfac-assert
    _vfac-scope-a VFA-SCOPE-FD@ 0= _vfac-assert
    _vfac-scope-a VFA-SCOPE-CLOSE? DROP
    _vfac-release-calls @ 1 = _vfac-assert
    0 _vfac-release-mode !

    \ Core ownership is retired even when RELEASE throws before calling the
    \ binding, and the exact throw remains the cleanup result.
    _vfac-vfs-a @ V.FDFREE @ _vfac-free-before !
    _vfac-scope-a _vfac-scope-init-a
    _vfac-scope-a _vfac-open-a DROP
    0 _vfac-release-calls ! 1 _vfac-release-mode !
    _vfac-scope-a VFA-SCOPE-CLOSE? _vfac-ior !
    _vfac-ior @ -7911 = _vfac-assert _vfac-release-calls @ 1 = _vfac-assert
    _vfac-vfs-a @ V.OPEN-COUNT @ 0= _vfac-assert
    _vfac-vfs-a @ V.FDFREE @ _vfac-free-before @ = _vfac-assert
    _vfac-scope-a VFA-SCOPE-FD@ 0= _vfac-assert
    _vfac-scope-a VFA-SCOPE-CLOSE? DROP
    _vfac-release-calls @ 1 = _vfac-assert
    0 _vfac-release-mode !
    VFS-CUR 0= _vfac-assert
    _vfac-stack ;

: _vfac-target-contracts  ( -- )
    \ A dentry owned by another VFS is not a valid target CWD even though it
    \ is otherwise a well-formed directory.
    0 VFS-USE
    _vfac-cwd-b @ _vfac-vfs-a @ V.CWD !
    _vfac-scope-a _vfac-scope-init-a
    ['] _vfac-body-ok _vfac-scope-a VFA-SCOPE-CALL
    _vfac-ior ! _vfac-length !
    _vfac-length @ VFS-E-CORRUPT = _vfac-assert
    _vfac-ior @ 0= _vfac-assert VFS-CUR 0= _vfac-assert
    _vfac-cwd-a @ _vfac-vfs-a @ V.CWD !

    \ A mounted descriptor with a null CWD is corrupt, but cannot trigger a
    \ null-dentry read or alter the ambient selector.
    0 VFS-USE
    0 _vfac-vfs-a @ V.CWD !
    _vfac-scope-a _vfac-scope-init-a
    ['] _vfac-body-ok _vfac-scope-a VFA-SCOPE-CALL
    _vfac-ior ! _vfac-length !
    _vfac-length @ VFS-E-CORRUPT = _vfac-assert
    _vfac-ior @ 0= _vfac-assert VFS-CUR 0= _vfac-assert
    _vfac-cwd-a @ _vfac-vfs-a @ V.CWD !

    \ A reused direct scope must clear prior cleanup uncertainty before a new
    \ operation, even when target readiness fails before context entry.
    _vfac-scope-b _vfac-scope-init-b
    0 _vfac-close-calls !
    ['] _vfac-close-after _vfac-scope-b VFA-SCOPE-CLOSE-XT!
        0= _vfac-assert
    _vfac-scope-b _vfac-open-b DROP
    _vfac-scope-b VFA-SCOPE-CLOSE? -7921 = _vfac-assert
    _vfac-scope-b VFA-SCOPE-CLEANUP@ -7921 = _vfac-assert
    VFS-UNMOUNT-F-FORCE _vfac-vfs-b @ VFS-UNMOUNT 0= _vfac-assert
    S" data.bin" VFS-FF-READ _vfac-scope-b VFA-SCOPE-OPEN?
    _vfac-ior ! _vfac-fd !
    _vfac-fd @ 0= _vfac-assert _vfac-ior @ _vfac-busy? _vfac-assert
    _vfac-scope-b VFA-SCOPE-PRIMARY@ _vfac-busy? _vfac-assert
    _vfac-scope-b VFA-SCOPE-CLEANUP@ 0= _vfac-assert
    VFS-CUR 0= _vfac-assert
    _vfac-stack ;

: _vfac-setup  ( -- )
    VFS-CUR _vfac-old-vfs !
    0 _vfac-open-mode ! 0 _vfac-open-calls !
    0 _vfac-release-mode ! 0 _vfac-release-calls !
    0 _vfac-read-fault-at ! 0 _vfac-read-calls !

    VFS-RAM-OPS _vfac-ops-a VFS-OPS-SIZE MOVE
    VFS-RAM-OPS _vfac-ops-b VFS-OPS-SIZE MOVE
    _vfac-ops-a VFS-OP-OPEN CELLS + @ _vfac-old-open-xt !
    _vfac-ops-a VFS-OP-RELEASE CELLS + @ _vfac-old-release-xt !
    _vfac-ops-a VFS-OP-READ CELLS + @ _vfac-old-read-xt !
    ['] _vfac-fault-open _vfac-ops-a VFS-OP-OPEN CELLS + !
    ['] _vfac-fault-release _vfac-ops-a VFS-OP-RELEASE CELLS + !
    ['] _vfac-fault-read _vfac-ops-a VFS-OP-READ CELLS + !

    VFS-RAM-BINDING _vfac-binding-a VFS-BINDING-DESC-SIZE MOVE
    VFS-RAM-BINDING _vfac-binding-b VFS-BINDING-DESC-SIZE MOVE
    _vfac-ops-a _vfac-binding-a VB.OPS !
    _vfac-ops-b _vfac-binding-b VB.OPS !

    524288 A-XMEM ARENA-NEW DUP 0= _vfac-assert DROP _vfac-arena-a !
    _vfac-arena-a @ _vfac-binding-a 0 VFS-NEW
    _vfac-ior ! _vfac-vfs-a !
    _vfac-ior @ 0= _vfac-assert _vfac-vfs-a @ 0<> _vfac-assert

    524288 A-XMEM ARENA-NEW DUP 0= _vfac-assert DROP _vfac-arena-b !
    _vfac-arena-b @ _vfac-binding-b 0 VFS-NEW
    _vfac-ior ! _vfac-vfs-b !
    _vfac-ior @ 0= _vfac-assert _vfac-vfs-b @ 0<> _vfac-assert

    _vfac-put-a _vfac-put-b 0 VFS-USE
    _vfac-stack ;

: _vfac-cleanup  ( -- )
    0 _vfac-open-mode ! 0 _vfac-release-mode ! 0 _vfac-read-fault-at !
    _vfac-old-vfs @ VFS-USE
    _vfac-vfs-b @ ?DUP IF VFS-DESTROY 0 _vfac-vfs-b ! THEN
    _vfac-vfs-a @ ?DUP IF VFS-DESTROY 0 _vfac-vfs-a ! THEN ;

: _vfac-report  ( -- )
    _vfac-stack
    _vfac-fails @ 0= IF
        ." VFS ACCESS CONTRACTS PASS " _vfac-checks @ . CR
    ELSE
        ." VFS ACCESS CONTRACTS FAIL " _vfac-fails @ .
        ."  / " _vfac-checks @ . CR
    THEN ;

: _vfac-run  ( -- )
    0 _vfac-fails ! 0 _vfac-checks ! DEPTH _vfac-depth !
    _vfac-setup
    _vfac-range-contracts
    _vfac-file-contracts
    _vfac-stream-contracts
    _vfac-scope-contracts
    _vfac-cleanup-fault-contracts
    _vfac-core-throw-contracts
    _vfac-target-contracts
    _vfac-cleanup
    _vfac-report ;
