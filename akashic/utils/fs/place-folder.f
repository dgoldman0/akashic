\ =====================================================================
\  place-folder.f - the folder a store keeps its layout in
\ =====================================================================
\  Megapad-64 / KDOS Forth      Prefix: PFOLDER- / _PFD-
\
\  A store that keeps a layout of several files, as Streams' and
\  Library's repositories do, binds the folder of the place it is given
\  once when it opens and composes the paths of its files under that
\  folder, so the persistence layer below it keeps taking an instance
\  and a path (docs/utils/fs/places.md, "The words").  The folder is
\  the place's own: a holder's home is a folder of its own under records
\  where the activation's home stands apart from the documents place,
\  and the volume's root in the linked build.
\
\  Public API:
\    PFOLDER-BIND  ( place buf cap -- vfs len ior )
\    PFOLDER-PATH  ( name-a name-u folder-a folder-u buf cap -- len ior )
\ =====================================================================

PROVIDED akashic-place-folder

REQUIRE places.f

VARIABLE _PFD-PLACE

\ PFOLDER-BIND ( place buf cap -- vfs len ior )
\   The instance and, in BUF, the volume path of PLACE's own folder,
\   bound for writing when PLACE is writable and for reading when it is
\   read-only.  An unavailable place answers its status.
: PFOLDER-BIND  ( place buf cap -- vfs len ior )
    ROT DUP _PFD-PLACE ! 0= IF 2DROP 0 0 VFS-E-INVALID EXIT THEN
    >R >R S" /" _PFD-PLACE @ R> R>
    _PFD-PLACE @ PLACE-WRITABLE? IF PLACE-BIND-WRITE ELSE PLACE-BIND THEN ;

VARIABLE _PFD-BUF  VARIABLE _PFD-CAP  VARIABLE _PFD-LEN

: _PFD+  ( a u -- ok? )
    DUP _PFD-LEN @ + _PFD-CAP @ > IF 2DROP 0 EXIT THEN
    TUCK _PFD-BUF @ _PFD-LEN @ + SWAP CMOVE  _PFD-LEN +!  -1 ;

\ PFOLDER-PATH ( name-a name-u folder-a folder-u buf cap -- len ior )
\   The volume path of NAME, one name or names joined by slashes, inside
\   the folder whose volume path is FOLDER, in BUF: FOLDER, a slash and
\   NAME, with no second slash after the volume's root "/".
\   VFS-E-NAMETOOLONG when it does not fit in CAP bytes, VFS-E-INVALID
\   for a FOLDER that is no absolute path or an empty NAME.
: PFOLDER-PATH  ( name-a name-u folder-a folder-u buf cap -- len ior )
    _PFD-CAP ! _PFD-BUF ! 0 _PFD-LEN !
    DUP 0= IF 2DROP 2DROP 0 VFS-E-INVALID EXIT THEN
    OVER C@ [CHAR] / <> IF 2DROP 2DROP 0 VFS-E-INVALID EXIT THEN
    2 PICK 0= IF 2DROP 2DROP 0 VFS-E-INVALID EXIT THEN
    \ The root's "/" already ends in a slash.
    DUP 1 = IF 2DROP ELSE
        _PFD+ 0= IF 2DROP 0 VFS-E-NAMETOOLONG EXIT THEN
    THEN
    S" /" _PFD+ 0= IF 2DROP 0 VFS-E-NAMETOOLONG EXIT THEN
    _PFD+ 0= IF 0 VFS-E-NAMETOOLONG EXIT THEN
    _PFD-LEN @ 0 ;
