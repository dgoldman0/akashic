\ vfs-ext4-jbd2-revoke.f — ext4 JBD2 recovery revoke index
\
\ Internal dependency of the vfs-ext4.f public facade.

PROVIDED akashic-ext4-jbd2-rvk
REQUIRE vfs-ext4-admission.f

VARIABLE _EXT4-JRW-CTX
VARIABLE _EXT4-JRW-COUNT
VARIABLE _EXT4-JRW-SLOTS
VARIABLE _EXT4-JRW-BYTES

-1 1 RSHIFT 2 CELLS / CONSTANT _EXT4-REVOKE-SLOTS-MAX

\ Recovery workspace survives a failed mount so the same VFS can retry
\ without leaking arena storage.  Treat only the completely empty geometry
\ or a bounded power-of-two table as valid persisted state.
: _EXT4-REVOKE-GEOMETRY?  ( ctx -- flag )
    DUP _EXT4-C.J.REVOKE-TABLE + @
    SWAP _EXT4-C.J.REVOKE-SLOTS + @
    2DUP OR 0= IF 2DROP TRUE EXIT THEN
    OVER 0= OVER 0= OR IF 2DROP FALSE EXIT THEN
    DUP 2 U< IF 2DROP FALSE EXIT THEN
    DUP _EXT4-REVOKE-SLOTS-MAX U> IF 2DROP FALSE EXIT THEN
    DUP 1- AND 0= NIP ;

\ Revoke recovery needs the latest committed transaction ID for each home
\ block.  Size an open-addressed table from the exact number of committed
\ on-disk records found by preflight.  A half-full power-of-two table makes
\ lookup bounded without imposing a journal-size policy.  One binding reuses
\ its first recovery allocation on retry rather than leaking monotonic arena
\ storage; a writer must negotiate separate transaction workspace.
: _EXT4-ENSURE-REVOKE-WORKSPACE  ( count ctx -- ior )
    _EXT4-JRW-CTX ! DUP _EXT4-JRW-COUNT !
    DROP
    0 _EXT4-JRW-CTX @ _EXT4-C.J.REVOKE-READY + !
    _EXT4-JRW-CTX @ _EXT4-REVOKE-GEOMETRY? 0= IF
        EXT4-D-JOURNAL _EXT4-CORRUPT EXIT
    THEN
    _EXT4-JRW-COUNT @ -1 1 RSHIFT 2 / U> IF
        EXT4-D-JOURNAL _EXT4-UNSUPPORTED EXIT
    THEN
    0 _EXT4-JRW-SLOTS !
    _EXT4-JRW-COUNT @ IF
        1 _EXT4-JRW-SLOTS !
        BEGIN
            _EXT4-JRW-SLOTS @ _EXT4-JRW-COUNT @ 2* U<
        WHILE
            _EXT4-JRW-SLOTS @
            _EXT4-REVOKE-SLOTS-MAX 2 / U> IF
                EXT4-D-JOURNAL _EXT4-UNSUPPORTED EXIT
            THEN
            _EXT4-JRW-SLOTS @ 2* _EXT4-JRW-SLOTS !
        REPEAT
    THEN
    _EXT4-JRW-CTX @ _EXT4-C.J.REVOKE-TABLE + @ IF
        _EXT4-JRW-CTX @ _EXT4-C.J.REVOKE-SLOTS + @
        _EXT4-JRW-SLOTS @ U< IF VFS-E-NOMEM EXIT THEN
        _EXT4-JRW-CTX @ _EXT4-C.J.REVOKE-TABLE + @
        _EXT4-JRW-CTX @ _EXT4-C.J.REVOKE-SLOTS + @ 2* CELLS
        0 FILL
        0 EXIT
    THEN
    _EXT4-JRW-COUNT @ 0= IF 0 EXIT THEN
    _EXT4-JRW-SLOTS @ _EXT4-REVOKE-SLOTS-MAX U> IF
        EXT4-D-JOURNAL _EXT4-UNSUPPORTED EXIT
    THEN
    _EXT4-JRW-SLOTS @ 2* CELLS _EXT4-JRW-BYTES !
    _EXT4-JRW-CTX @ _EXT4-C.ARENA + @
    _EXT4-JRW-BYTES @ ARENA-ALLOT? IF DROP VFS-E-NOMEM EXIT THEN
    DUP _EXT4-JRW-CTX @ _EXT4-C.J.REVOKE-TABLE + !
    _EXT4-JRW-BYTES @ 0 FILL
    _EXT4-JRW-SLOTS @
    _EXT4-JRW-CTX @ _EXT4-C.J.REVOKE-SLOTS + !
    0 ;

VARIABLE _EXT4-JRH-BLOCK
VARIABLE _EXT4-JRH-SEQUENCE
VARIABLE _EXT4-JRH-CTX
VARIABLE _EXT4-JRH-KEY
VARIABLE _EXT4-JRH-SLOT
VARIABLE _EXT4-JRH-ENTRY

: _EXT4-JOURNAL-TID-AFTER?  ( candidate previous -- flag )
    - 0xFFFFFFFF AND DUP 0<> SWAP 0x80000000 U< AND ;

: _EXT4-REVOKE-ENTRY  ( slot ctx -- entry )
    _EXT4-C.J.REVOKE-TABLE + @ SWAP 2* CELLS + ;

: _EXT4-REVOKE-PUT  ( block sequence ctx -- ior )
    _EXT4-JRH-CTX ! _EXT4-JRH-SEQUENCE ! _EXT4-JRH-BLOCK !
    _EXT4-JRH-BLOCK @ _EXT4-JRH-CTX @ _EXT4-C.BLOCKS + @ U< 0= IF
        EXT4-D-JOURNAL _EXT4-CORRUPT EXIT
    THEN
    _EXT4-JRH-CTX @ _EXT4-REVOKE-GEOMETRY? 0= IF
        EXT4-D-JOURNAL _EXT4-CORRUPT EXIT
    THEN
    _EXT4-JRH-CTX @ _EXT4-C.J.REVOKE-TABLE + @ 0= IF
        EXT4-D-JOURNAL _EXT4-CORRUPT EXIT
    THEN
    _EXT4-JRH-BLOCK @ 1+ _EXT4-JRH-KEY !
    _EXT4-JRH-BLOCK @
    _EXT4-JRH-CTX @ _EXT4-C.J.REVOKE-SLOTS + @ 1- AND
    _EXT4-JRH-SLOT !
    _EXT4-JRH-CTX @ _EXT4-C.J.REVOKE-SLOTS + @ 0 DO
        _EXT4-JRH-SLOT @ _EXT4-JRH-CTX @ _EXT4-REVOKE-ENTRY
        DUP _EXT4-JRH-ENTRY ! @ DUP 0= IF
            DROP
            _EXT4-JRH-KEY @ _EXT4-JRH-ENTRY @ !
            _EXT4-JRH-SEQUENCE @ _EXT4-JRH-ENTRY @ CELL+ !
            0 UNLOOP EXIT
        THEN
        _EXT4-JRH-KEY @ = IF
            _EXT4-JRH-SEQUENCE @
            _EXT4-JRH-ENTRY @ CELL+ @ _EXT4-JOURNAL-TID-AFTER? IF
                _EXT4-JRH-SEQUENCE @ _EXT4-JRH-ENTRY @ CELL+ !
            THEN
            0 UNLOOP EXIT
        THEN
        _EXT4-JRH-SLOT @ 1+
        _EXT4-JRH-CTX @ _EXT4-C.J.REVOKE-SLOTS + @ 1- AND
        _EXT4-JRH-SLOT !
    LOOP
    EXT4-D-JOURNAL _EXT4-CORRUPT ;

: _EXT4-JOURNAL-REVOKED?  ( block sequence ctx -- flag )
    _EXT4-JRH-CTX ! _EXT4-JRH-SEQUENCE ! _EXT4-JRH-BLOCK !
    _EXT4-JRH-CTX @ _EXT4-C.J.REVOKE-TABLE + @ 0= IF
        FALSE EXIT
    THEN
    _EXT4-JRH-BLOCK @ 1+ _EXT4-JRH-KEY !
    _EXT4-JRH-BLOCK @
    _EXT4-JRH-CTX @ _EXT4-C.J.REVOKE-SLOTS + @ 1- AND
    _EXT4-JRH-SLOT !
    _EXT4-JRH-CTX @ _EXT4-C.J.REVOKE-SLOTS + @ 0 DO
        _EXT4-JRH-SLOT @ _EXT4-JRH-CTX @ _EXT4-REVOKE-ENTRY
        DUP @ DUP 0= IF 2DROP FALSE UNLOOP EXIT THEN
        _EXT4-JRH-KEY @ = IF
            CELL+ @ _EXT4-JRH-SEQUENCE @ SWAP
            _EXT4-JOURNAL-TID-AFTER? 0= UNLOOP EXIT
        THEN
        DROP
        _EXT4-JRH-SLOT @ 1+
        _EXT4-JRH-CTX @ _EXT4-C.J.REVOKE-SLOTS + @ 1- AND
        _EXT4-JRH-SLOT !
    LOOP
    FALSE ;
