\ =====================================================================
\  place-replace.f - A checked replacement pointed at a file of a place
\ =====================================================================
\  Megapad-64 / KDOS Forth      Prefix: PLACE-
\
\  A store or an editor that keeps a file through a checked replacement
\  (vfs-replace.f) names the file by its path in a place.  PLACE-VREPL!
\  binds that path to its volume, through PLACE-BIND-WRITE for a holder
\  that will write and PLACE-BIND otherwise, and points the replacement at
\  the volume path.  The replacement then reads and writes the file
\  through its own descriptor, as it does for any path.  A replacement
\  bound for reading is marked read-only, so it refuses to replace: a
\  store on a read-only place refuses each change here, with
\  VREPL-S-READ-ONLY.
\
\  docs/utils/fs/places.md is the design.
\ =====================================================================

PROVIDED akashic-place-replace

REQUIRE places.f
REQUIRE vfs-replace.f

VARIABLE _PLV-R
VARIABLE _PLV-W
VARIABLE _PLV-V
CREATE _PLV-BUF  VFS-PATH-MAX ALLOT

: _PL-VREPL!  ( path-a path-u place write? replacement -- ior )
    _PLV-R !  _PLV-W !
    _PLV-BUF VFS-PATH-MAX _PLV-W @ IF
        PLACE-BIND-WRITE
    ELSE
        PLACE-BIND
    THEN                                            ( vfs len ior )
    ?DUP IF NIP NIP EXIT THEN
    SWAP _PLV-V !                                   ( len )
    _PLV-R @ VREPL-VALID? IF
        _PLV-R @ VREPL.VFS @ _PLV-V @ <>
    ELSE
        -1
    THEN IF
        _PLV-V @ _PLV-R @ VREPL-INIT IF DROP VFS-E-INVALID EXIT THEN
    THEN
    _PLV-BUF SWAP _PLV-R @ VREPL-DERIVE-PATHS! IF VFS-E-INVALID EXIT THEN
    _PLV-W @ 0= _PLV-R @ VREPL-READ-ONLY! IF VFS-E-INVALID EXIT THEN
    0 ;

\ PLACE-VREPL! ( path-a path-u place write? replacement -- ior )
\   Point REPLACEMENT at the file PATH names in PLACE.  The path is bound
\   for writing when WRITE? is true, and a read-only place refuses that;
\   otherwise it is bound for reading and the replacement is marked
\   read-only.  The replacement is configured on the place's volume when
\   it was on another or none, and its companion paths are derived there.
\   0, the binding's ior, or VFS-E-INVALID when the replacement refuses
\   the path.  The replacement's guard is held throughout, so its order
\   with the VFS's guard is the one every replacement takes.
: PLACE-VREPL!  ( path-a path-u place write? replacement -- ior )
    ['] _PL-VREPL! _vrepl-guard WITH-GUARD ;
