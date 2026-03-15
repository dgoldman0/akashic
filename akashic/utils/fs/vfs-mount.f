\ vfs-mount.f — Optional global mount table for VFS instances
\
\ A thin routing layer that maps path prefixes to VFS instances.
\ Provides the traditional OPEN "/sd/readme.txt" experience
\ across multiple VFS instances.  Not required — applications
\ that pass VFS instances explicitly never need this module.
\
\ Prefix: VMNT-   (public API)
\         _VMNT-  (internal helpers)
\
\ Load with:   REQUIRE utils/fs/vfs-mount.f

PROVIDED akashic-vfs-mount
REQUIRE vfs.f

\ =====================================================================
\  Constants
\ =====================================================================

64  CONSTANT VMNT-MAX-ENTRIES    \ max simultaneous mount points
256 CONSTANT VMNT-PREFIX-SIZE    \ max bytes per mount-point prefix

\ Entry layout:
\   +0              256 B  NUL-terminated prefix string
\   +256            cell   cached prefix length
\   +264            cell   VFS instance pointer (0 = unused)
\ = 272 bytes per entry

: _VMNT-ENTRY-SIZE  272 ;       \ bytes per mount table entry

\ =====================================================================
\  Mount Table Storage
\ =====================================================================
\
\ Static table in dictionary space: 64 × 272 = 17408 bytes.
\ A slot with vfs = 0 is unused.

CREATE _VMNT-TABLE  VMNT-MAX-ENTRIES _VMNT-ENTRY-SIZE * ALLOT
_VMNT-TABLE VMNT-MAX-ENTRIES _VMNT-ENTRY-SIZE * 0 FILL

\ =====================================================================
\  Entry Field Accessors
\ =====================================================================

: _VMNT-PREFIX  ( entry -- c-addr )  ;                  \ +0
: _VMNT-PLEN    ( entry -- addr   )  256 + ;            \ +256
: _VMNT-VFS     ( entry -- addr   )  264 + ;            \ +264

\ Get entry address by index
: _VMNT-ENTRY   ( i -- entry )
    _VMNT-ENTRY-SIZE *  _VMNT-TABLE + ;

\ =====================================================================
\  Internal: prefix matching
\ =====================================================================

\ _VMNT-PREFIX=?  ( c-addr u entry -- flag )
\   True if the first `prefix-len` bytes of (c-addr u) match
\   the entry's prefix exactly, AND the path is at least as long
\   as the prefix.

VARIABLE _VMPE-CA
VARIABLE _VMPE-U
VARIABLE _VMPE-E

: _VMNT-PREFIX=?  ( c-addr u entry -- flag )
    _VMPE-E !  _VMPE-U !  _VMPE-CA !
    _VMPE-E @ _VMNT-PLEN @ DUP 0= IF
        \ Empty prefix matches everything
        DROP TRUE EXIT
    THEN                              ( plen )
    DUP _VMPE-U @ > IF
        \ Path shorter than prefix — no match
        DROP FALSE EXIT
    THEN                              ( plen )
    \ Compare plen bytes
    0 DO
        _VMPE-CA @ I + C@
        _VMPE-E @ _VMNT-PREFIX I + C@
        <> IF  FALSE UNLOOP EXIT  THEN
    LOOP
    TRUE ;

\ =====================================================================
\  VMNT-MOUNT  ( vfs c-addr u -- ior )
\ =====================================================================
\
\  Bind a VFS instance to a mount-point prefix string.
\  Returns 0 on success, -1 if the table is full, -2 if the
\  prefix is too long.

VARIABLE _VMM-VFS
VARIABLE _VMM-CA
VARIABLE _VMM-U

: VMNT-MOUNT  ( vfs c-addr u -- ior )
    _VMM-U !  _VMM-CA !  _VMM-VFS !

    \ Check prefix length
    _VMM-U @ VMNT-PREFIX-SIZE 1- > IF  -2 EXIT  THEN

    \ Find first free slot
    VMNT-MAX-ENTRIES 0 DO
        I _VMNT-ENTRY  _VMNT-VFS @  0= IF
            \ Found free slot at index I
            I _VMNT-ENTRY                   ( entry )
            \ Copy prefix string
            DUP _VMNT-PREFIX  VMNT-PREFIX-SIZE 0 FILL
            _VMM-CA @  OVER _VMNT-PREFIX  _VMM-U @  CMOVE
            \ Store prefix length
            _VMM-U @  OVER _VMNT-PLEN !
            \ Store VFS pointer
            _VMM-VFS @  SWAP _VMNT-VFS !
            0 UNLOOP EXIT
        THEN
    LOOP
    \ No free slot
    -1 ;

\ =====================================================================
\  VMNT-UMOUNT  ( c-addr u -- ior )
\ =====================================================================
\
\  Remove the mount entry whose prefix exactly matches (c-addr u).
\  Returns 0 on success, -1 if not found.

VARIABLE _VMU-CA
VARIABLE _VMU-U

: VMNT-UMOUNT  ( c-addr u -- ior )
    _VMU-U !  _VMU-CA !
    VMNT-MAX-ENTRIES 0 DO
        I _VMNT-ENTRY DUP _VMNT-VFS @ 0<> IF
            \ Active entry — compare prefix
            DUP _VMNT-PLEN @  _VMU-U @ = IF
                _VMU-CA @  _VMU-U @  ROT  _VMNT-PREFIX=? IF
                    \ Match: zero the entry
                    I _VMNT-ENTRY  _VMNT-ENTRY-SIZE 0 FILL
                    0 UNLOOP EXIT
                THEN
            ELSE
                DROP
            THEN
        ELSE
            DROP
        THEN
    LOOP
    -1 ;

\ =====================================================================
\  VMNT-RESOLVE  ( c-addr u -- vfs c-addr' u' | 0 )
\ =====================================================================
\
\  Find the longest-prefix match.  Returns the matched VFS and the
\  remainder of the path after stripping the prefix.
\  Returns 0 (single cell) if no mount point matches.

VARIABLE _VMR-CA
VARIABLE _VMR-U
VARIABLE _VMR-BEST-VFS
VARIABLE _VMR-BEST-LEN

: VMNT-RESOLVE  ( c-addr u -- vfs c-addr' u' | 0 )
    _VMR-U !  _VMR-CA !
    0 _VMR-BEST-VFS !
    0 _VMR-BEST-LEN !

    VMNT-MAX-ENTRIES 0 DO
        I _VMNT-ENTRY DUP _VMNT-VFS @ 0<> IF
            \ Active entry — check prefix match
            _VMR-CA @  _VMR-U @  ROT  DUP >R
            _VMNT-PREFIX=? IF
                R@ _VMNT-PLEN @
                DUP _VMR-BEST-LEN @ > IF
                    \ New longest match
                    _VMR-BEST-LEN !
                    R@ _VMNT-VFS @  _VMR-BEST-VFS !
                ELSE
                    DROP
                THEN
            THEN
            R> DROP
        ELSE
            DROP
        THEN
    LOOP

    _VMR-BEST-VFS @ DUP 0= IF
        EXIT                              \ return 0
    THEN
    \ Return: vfs  remainder-addr  remainder-len
    _VMR-CA @  _VMR-BEST-LEN @ +
    _VMR-U @   _VMR-BEST-LEN @ -
    ;

\ =====================================================================
\  VMNT-OPEN  ( c-addr u -- fd | 0 )
\ =====================================================================
\
\  Longest-prefix match → VFS-OPEN on the matched instance.
\  The remainder path (after stripping the mount prefix) is passed
\  to VFS-OPEN.

: VMNT-OPEN  ( c-addr u -- fd | 0 )
    VMNT-RESOLVE                  ( vfs c-addr' u' | 0 )
    DUP 0= IF  EXIT  THEN        \ no match → return 0
    \ Stack: vfs c-addr' u'
    ROT DUP >R  VFS-USE           ( c-addr' u' )  ( R: vfs )
    VFS-OPEN                      ( fd | 0 )
    R> DROP ;

\ =====================================================================
\  VMNT-INFO  ( -- )
\ =====================================================================
\
\  Print all active mount entries.

: VMNT-INFO  ( -- )
    ." Mount Table:" CR
    ." ─────────────────────────────────────────" CR
    VMNT-MAX-ENTRIES 0 DO
        I _VMNT-ENTRY DUP _VMNT-VFS @ 0<> IF
            ."   "
            DUP _VMNT-PREFIX  OVER _VMNT-PLEN @  TYPE
            ."  → VFS@"
            DUP _VMNT-VFS @ .
            CR
        THEN
        DROP
    LOOP ;

\ =====================================================================
\  Guard Section (opt-in concurrency)
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _vmnt-guard

' VMNT-MOUNT     CONSTANT _vmnt-mount-xt
' VMNT-UMOUNT    CONSTANT _vmnt-umount-xt
' VMNT-RESOLVE   CONSTANT _vmnt-resolve-xt
' VMNT-OPEN      CONSTANT _vmnt-open-xt
' VMNT-INFO      CONSTANT _vmnt-info-xt

: VMNT-MOUNT     _vmnt-mount-xt    _vmnt-guard WITH-GUARD ;
: VMNT-UMOUNT    _vmnt-umount-xt   _vmnt-guard WITH-GUARD ;
: VMNT-RESOLVE   _vmnt-resolve-xt  _vmnt-guard WITH-GUARD ;
: VMNT-OPEN      _vmnt-open-xt     _vmnt-guard WITH-GUARD ;
: VMNT-INFO      _vmnt-info-xt     _vmnt-guard WITH-GUARD ;

[THEN] [THEN]
