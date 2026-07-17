\ Deterministic contracts for RAM-VFS backing capacity and zero tails.

PROVIDED akashic-vfs-ram-capacity-contracts

VARIABLE _vrct-fails
VARIABLE _vrct-checks
VARIABLE _vrct-depth
VARIABLE _vrct-byte
VARIABLE _vrct-old-vfs
VARIABLE _vrct-arena
VARIABLE _vrct-vfs
VARIABLE _vrct-main-vfs
VARIABLE _vrct-fail-arena
VARIABLE _vrct-fail-vfs
VARIABLE _vrct-in
VARIABLE _vrct-in-a
VARIABLE _vrct-in-b
VARIABLE _vrct-fd
VARIABLE _vrct-fd-a
VARIABLE _vrct-fd-b
VARIABLE _vrct-buffer
VARIABLE _vrct-output
VARIABLE _vrct-pointer
VARIABLE _vrct-pointer-b
VARIABLE _vrct-capacity
VARIABLE _vrct-free

: _vrct-assert  ( flag -- )
    1 _vrct-checks +!
    0= IF
        1 _vrct-fails +!
        ." VFS RAM CAPACITY ASSERT " _vrct-checks @ . CR
    THEN ;

: _vrct-stack  ( -- )
    DEPTH DUP _vrct-depth @ <> IF
        ." VFS RAM CAPACITY STACK " _vrct-depth @ . ." -> " DUP . CR .S CR
    THEN
    _vrct-depth @ = _vrct-assert ;

: _vrct-filled?  ( address length byte -- flag )
    _vrct-byte !
    0 ?DO
        DUP I + C@ _vrct-byte @ <> IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

VARIABLE _vrct-a1
VARIABLE _vrct-u1
VARIABLE _vrct-a2
VARIABLE _vrct-u2

: _vrct-overlap?  ( a1 u1 a2 u2 -- flag )
    _vrct-u2 ! _vrct-a2 ! _vrct-u1 ! _vrct-a1 !
    _vrct-u1 @ 0= _vrct-u2 @ 0= OR IF 0 EXIT THEN
    _vrct-a1 @ _vrct-u1 @ + _vrct-a2 @ U>
    _vrct-a2 @ _vrct-u2 @ + _vrct-a1 @ U> AND ;

: _vrct-allocate  ( size variable -- )
    >R ALLOCATE ABORT" VFS RAM CAPACITY FAIL allocation" R> ! ;

: _vrct-free-buffer  ( variable -- )
    DUP @ ?DUP IF FREE 0 SWAP ! ELSE DROP THEN ;

: _vrct-open  ( path-a path-u -- fd )
    2DUP _vrct-vfs @ VFS-MKFILE DUP 0<> _vrct-assert _vrct-in !
    _vrct-vfs @ VFS-USE VFS-OPEN DUP 0<> _vrct-assert ;

: _vrct-growth  ( -- )
    S" growth.bin" _vrct-open _vrct-fd !
    _vrct-buffer @ 3000 65 FILL
    _vrct-buffer @ 3000 + 3000 66 FILL
    _vrct-buffer @ 6000 + 3000 67 FILL

    _vrct-buffer @ 3000 _vrct-fd @ VFS-WRITE 3000 = _vrct-assert
    _vrct-in @ IN.BDATA @ 0<> _vrct-assert
    _vrct-in @ IN.BDATA 8 + @ _VFS-RAM-CAP-MIN = _vrct-assert
    _vrct-buffer @ 3000 + 3000 _vrct-fd @ VFS-WRITE
        3000 = _vrct-assert
    _vrct-in @ IN.BDATA 8 + @ 8192 = _vrct-assert
    _vrct-buffer @ 6000 + 3000 _vrct-fd @ VFS-WRITE
        3000 = _vrct-assert
    _vrct-in @ IN.BDATA 8 + @ 16384 = _vrct-assert
    _vrct-fd @ VFS-SIZE 9000 = _vrct-assert

    _vrct-output @ 10000 0xCC FILL
    _vrct-fd @ VFS-REWIND
    _vrct-output @ 9000 _vrct-fd @ VFS-READ 9000 = _vrct-assert
    _vrct-output @ 3000 65 _vrct-filled? _vrct-assert
    _vrct-output @ 3000 + 3000 66 _vrct-filled? _vrct-assert
    _vrct-output @ 6000 + 3000 67 _vrct-filled? _vrct-assert
    _vrct-in @ IN.BDATA @ 9000 +
        _vrct-in @ IN.BDATA 8 + @ 9000 - 0 _vrct-filled? _vrct-assert
    _vrct-fd @ VFS-CLOSE
    _vrct-stack ;

: _vrct-file-isolation  ( -- )
    S" alpha.bin" _vrct-open _vrct-fd-a !
    _vrct-in @ _vrct-in-a !
    _vrct-buffer @ 4096 0x11 FILL
    _vrct-buffer @ 4096 _vrct-fd-a @ VFS-WRITE 4096 = _vrct-assert

    S" beta.bin" _vrct-open _vrct-fd-b !
    _vrct-in @ _vrct-in-b !
    _vrct-buffer @ 4096 0x22 FILL
    _vrct-buffer @ 4096 _vrct-fd-b @ VFS-WRITE 4096 = _vrct-assert
    _vrct-in-b @ IN.BDATA @ _vrct-pointer-b !

    _vrct-buffer @ 4096 0x33 FILL
    4096 _vrct-fd-a @ VFS-SEEK
    _vrct-buffer @ 4096 _vrct-fd-a @ VFS-WRITE 4096 = _vrct-assert
    _vrct-in-a @ IN.BDATA 8 + @ 8192 = _vrct-assert
    _vrct-in-b @ IN.BDATA @ _vrct-pointer-b @ = _vrct-assert
    _vrct-in-b @ IN.BDATA 8 + @ 4096 = _vrct-assert
    _vrct-in-a @ IN.BDATA @ _vrct-in-a @ IN.BDATA 8 + @
        _vrct-in-b @ IN.BDATA @ _vrct-in-b @ IN.BDATA 8 + @
        _vrct-overlap? 0= _vrct-assert

    _vrct-output @ 8192 0 FILL
    _vrct-fd-a @ VFS-REWIND
    _vrct-output @ 8192 _vrct-fd-a @ VFS-READ 8192 = _vrct-assert
    _vrct-output @ 4096 0x11 _vrct-filled? _vrct-assert
    _vrct-output @ 4096 + 4096 0x33 _vrct-filled? _vrct-assert
    _vrct-output @ 4096 0 FILL
    _vrct-fd-b @ VFS-REWIND
    _vrct-output @ 4096 _vrct-fd-b @ VFS-READ 4096 = _vrct-assert
    _vrct-output @ 4096 0x22 _vrct-filled? _vrct-assert
    _vrct-fd-a @ VFS-CLOSE _vrct-fd-b @ VFS-CLOSE
    _vrct-stack ;

: _vrct-shrink-regrow  ( -- )
    S" truncate.bin" _vrct-open _vrct-fd !
    _vrct-buffer @ 8 0x5A FILL
    _vrct-buffer @ 8 _vrct-fd @ VFS-WRITE 8 = _vrct-assert
    _vrct-in @ IN.BDATA 8 + @ _vrct-capacity !
    3 _vrct-fd @ VFS-TRUNCATE 0= _vrct-assert
    _vrct-fd @ VFS-SIZE 3 = _vrct-assert
    _vrct-in @ IN.BDATA @ 3 + _vrct-capacity @ 3 -
        0 _vrct-filled? _vrct-assert
    8 _vrct-fd @ VFS-TRUNCATE 0= _vrct-assert
    _vrct-in @ IN.BDATA 8 + @ _vrct-capacity @ = _vrct-assert
    _vrct-output @ 8 0xCC FILL
    _vrct-fd @ VFS-REWIND
    _vrct-output @ 8 _vrct-fd @ VFS-READ 8 = _vrct-assert
    _vrct-output @ 3 0x5A _vrct-filled? _vrct-assert
    _vrct-output @ 3 + 5 0 _vrct-filled? _vrct-assert
    _vrct-fd @ VFS-CLOSE
    _vrct-stack ;

: _vrct-sparse-gap  ( -- )
    S" sparse.bin" _vrct-open _vrct-fd !
    S" A" _vrct-fd @ VFS-WRITE 1 = _vrct-assert
    5000 _vrct-fd @ VFS-SEEK
    S" Z" _vrct-fd @ VFS-WRITE 1 = _vrct-assert
    _vrct-fd @ VFS-SIZE 5001 = _vrct-assert
    _vrct-in @ IN.BDATA 8 + @ 8192 = _vrct-assert
    _vrct-output @ 5001 0xCC FILL
    _vrct-fd @ VFS-REWIND
    _vrct-output @ 5001 _vrct-fd @ VFS-READ 5001 = _vrct-assert
    _vrct-output @ C@ [CHAR] A = _vrct-assert
    _vrct-output @ 1+ 4999 0 _vrct-filled? _vrct-assert
    _vrct-output @ 5000 + C@ [CHAR] Z = _vrct-assert
    _vrct-in @ IN.BDATA @ 5001 +
        _vrct-in @ IN.BDATA 8 + @ 5001 - 0 _vrct-filled? _vrct-assert
    _vrct-fd @ VFS-CLOSE
    _vrct-stack ;

: _vrct-failure  ( -- )
    65536 A-XMEM ARENA-NEW DUP 0= _vrct-assert DROP _vrct-fail-arena !
    _vrct-fail-arena @ VFS-RAM-VTABLE VFS-NEW
        DUP 0<> _vrct-assert _vrct-fail-vfs !
    _vrct-fail-vfs @ _vrct-vfs !
    S" stable.bin" _vrct-open _vrct-fd !
    S" stable" _vrct-fd @ VFS-WRITE 6 = _vrct-assert
    _vrct-in @ IN.BDATA @ _vrct-pointer !
    _vrct-in @ IN.BDATA 8 + @ _vrct-capacity !

    _vrct-fail-arena @ ARENA-FREE DUP 1024 > _vrct-assert
    1024 - _vrct-fail-arena @ SWAP ARENA-ALLOT?
    DUP 0= _vrct-assert DROP DROP
    _vrct-fail-arena @ ARENA-FREE _vrct-free !

    5000 _vrct-fd @ VFS-SEEK
    S" X" _vrct-fd @ VFS-WRITE 0= _vrct-assert
    _vrct-fd @ VFS-TELL 5000 = _vrct-assert
    _vrct-fd @ VFS-SIZE 6 = _vrct-assert
    _vrct-in @ IN.BDATA @ _vrct-pointer @ = _vrct-assert
    _vrct-in @ IN.BDATA 8 + @ _vrct-capacity @ = _vrct-assert
    _vrct-fail-arena @ ARENA-FREE _vrct-free @ = _vrct-assert
    77 _vrct-in @ IN.SIZE-HI !
    9000 _vrct-fd @ VFS-TRUNCATE -1 = _vrct-assert
    _vrct-fd @ VFS-SIZE 6 = _vrct-assert
    _vrct-in @ IN.SIZE-HI @ 77 = _vrct-assert
    _vrct-fd @ VFS-TELL 5000 = _vrct-assert
    _vrct-in @ IN.BDATA @ _vrct-pointer @ = _vrct-assert
    _vrct-in @ IN.BDATA 8 + @ _vrct-capacity @ = _vrct-assert
    _vrct-fail-arena @ ARENA-FREE _vrct-free @ = _vrct-assert

    -1 _vrct-fd @ VFS-TRUNCATE -1 = _vrct-assert
    _vrct-fd @ VFS-SIZE 6 = _vrct-assert
    _vrct-in @ IN.SIZE-HI @ 77 = _vrct-assert
    _vrct-fd @ VFS-TELL 5000 = _vrct-assert
    _vrct-fail-arena @ ARENA-FREE _vrct-free @ = _vrct-assert

    _vrct-buffer @ 1 -1 _vrct-in @ _vrct-fail-vfs @
        _VFS-RAM-WRITE 0= _vrct-assert
    _vrct-fd @ VFS-SIZE 6 = _vrct-assert
    _vrct-in @ IN.BDATA @ _vrct-pointer @ = _vrct-assert
    _vrct-in @ IN.BDATA 8 + @ _vrct-capacity @ = _vrct-assert
    _vrct-fail-arena @ ARENA-FREE _vrct-free @ = _vrct-assert

    2 _vrct-fd @ VFS-SEEK
    _vrct-buffer @ -1 _vrct-fd @ VFS-WRITE 0= _vrct-assert
    _vrct-fd @ VFS-TELL 2 = _vrct-assert
    0 1 _vrct-fd @ VFS-WRITE 0= _vrct-assert
    _vrct-fd @ VFS-TELL 2 = _vrct-assert
    0x7FFFFFFFFFFFFFFC _vrct-fd @ VFS-SEEK
    _vrct-buffer @ 8 _vrct-fd @ VFS-WRITE 0= _vrct-assert
    _vrct-fd @ VFS-TELL 0x7FFFFFFFFFFFFFFC = _vrct-assert
    _vrct-fd @ VFS-SIZE 6 = _vrct-assert
    _vrct-in @ IN.BDATA @ _vrct-pointer @ = _vrct-assert
    _vrct-in @ IN.BDATA 8 + @ _vrct-capacity @ = _vrct-assert
    _vrct-fail-arena @ ARENA-FREE _vrct-free @ = _vrct-assert

    _vrct-output @ 6 0 FILL
    _vrct-fd @ VFS-REWIND
    _vrct-output @ 6 _vrct-fd @ VFS-READ 6 = _vrct-assert
    _vrct-output @ 6 S" stable" COMPARE 0= _vrct-assert
    _vrct-fd @ VFS-CLOSE
    _vrct-fail-vfs @ VFS-DESTROY
    _vrct-main-vfs @ _vrct-vfs !
    _vrct-vfs @ VFS-USE
    _vrct-stack ;

: _vrct-setup  ( -- )
    VFS-CUR _vrct-old-vfs !
    10000 _vrct-buffer _vrct-allocate
    10000 _vrct-output _vrct-allocate
    262144 A-XMEM ARENA-NEW DUP 0= _vrct-assert DROP _vrct-arena !
    _vrct-arena @ VFS-RAM-VTABLE VFS-NEW
        DUP 0<> _vrct-assert DUP _vrct-vfs ! _vrct-main-vfs !
    _vrct-vfs @ VFS-USE ;

: _vrct-cleanup  ( -- )
    _vrct-old-vfs @ VFS-USE
    _vrct-vfs @ VFS-DESTROY
    _vrct-output _vrct-free-buffer
    _vrct-buffer _vrct-free-buffer ;

: _vrct-run  ( -- )
    0 _vrct-fails ! 0 _vrct-checks ! DEPTH _vrct-depth !
    _vrct-setup _vrct-stack
    _vrct-growth
    _vrct-file-isolation
    _vrct-shrink-regrow
    _vrct-sparse-gap
    _vrct-failure
    _vrct-cleanup _vrct-stack
    _vrct-fails @ 0= IF
        ." VFS RAM CAPACITY PASS " _vrct-checks @ . CR
    ELSE
        ." VFS RAM CAPACITY FAIL " _vrct-fails @ .
        ." /" _vrct-checks @ . CR
    THEN ;

_vrct-run
