\ =====================================================================
\  settings-disk.f — Files on the MegaPad-64 settings disk
\ =====================================================================
\  Megapad-64 / KDOS Forth      Prefix: SETDISK- / _SDK-
\
\  The settings disk is MegaPad's second storage unit.  Its medium is
\  write-protected, so only the host changes it, by rebuilding or editing
\  the settings image.  KDOS opens its raw volume read-only
\  (SETTINGS-OPEN).  This module mounts that volume for one read, and
\  gives back the mount, its arena and the volume after it.
\ =====================================================================

PROVIDED akashic-tui-settings-disk

REQUIRE ../../utils/fs/drivers/vfs-mp64fs.f

\ The mount's working storage, as the boot disk's mount takes, and the
\ arena descriptor it lies under: four cells kept here, so that a read
\ adds nothing to the dictionary (ARENA-NEW-AT).
131072 CONSTANT _SDK-ARENA-SIZE
CREATE _SDK-ARENA-DESC  4 CELLS ALLOT

VARIABLE _SDK-ARENA   \ the descriptor, while it holds an arena
VARIABLE _SDK-VFS
VARIABLE _SDK-FD
VARIABLE _SDK-BUF
VARIABLE _SDK-LEN

\ Give back what a read took, in reverse: the file, the mount with its
\ arena (or the arena alone, when the mount failed), and the volume.
: _SDK-RELEASE  ( -- )
    _SDK-FD @ ?DUP IF VFS-CLOSE? DROP THEN  0 _SDK-FD !
    _SDK-VFS @ ?DUP IF
        VFS-DESTROY
    ELSE
        _SDK-ARENA @ ?DUP IF ARENA-DESTROY THEN
    THEN
    0 _SDK-VFS !  0 _SDK-ARENA !
    SETTINGS-VOLUME VOL-CLOSE DROP
    SETTINGS-BD BD-CLOSE DROP ;

: _SDK-READ  ( name-a name-u -- ior )
    SETTINGS-OPEN ?DUP IF NIP NIP EXIT THEN
    _SDK-ARENA-DESC _SDK-ARENA-SIZE A-XMEM ARENA-NEW-AT ?DUP IF NIP NIP EXIT THEN
    _SDK-ARENA-DESC _SDK-ARENA !
    _SDK-ARENA @ SETTINGS-VOLUME VMP-NEW ?DUP IF NIP NIP NIP EXIT THEN
    _SDK-VFS !
    VFS-FF-READ _SDK-VFS @ VFS-OPEN? ?DUP IF NIP EXIT THEN
    _SDK-FD !
    _SDK-FD @ VFS-SIZE DUP _SDK-LEN !
    ALLOCATE ?DUP IF NIP EXIT THEN _SDK-BUF !
    _SDK-BUF @ _SDK-LEN @ _SDK-FD @ VFS-READ-EXACT ?DUP IF
        _SDK-BUF @ FREE  0 _SDK-BUF !
        EXIT
    THEN
    0 ;

\ SETDISK-READ ( name-a name-u -- buf len ior )
\   Read the whole named file from the settings disk into a buffer
\   ALLOCATEd to its size, which the caller FREEs.  A nonzero ior, for no
\   settings disk, no such file or a failed read, leaves no buffer.
: SETDISK-READ  ( name-a name-u -- buf len ior )
    0 _SDK-ARENA !  0 _SDK-VFS !  0 _SDK-FD !  0 _SDK-BUF !  0 _SDK-LEN !
    _SDK-READ _SDK-RELEASE
    ?DUP IF 0 0 ROT EXIT THEN
    _SDK-BUF @ _SDK-LEN @ 0 ;
