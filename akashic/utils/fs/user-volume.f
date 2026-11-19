\ =====================================================================
\  user-volume.f — the user volume, where documents and records live
\ =====================================================================
\  Megapad-64 / KDOS Forth      Prefix: USERVOL- / _USERVOL-
\
\  The user volume is the ext4 volume on the machine's user storage unit,
\  KDOS's USER-UNIT.  It holds the user's documents and the applets'
\  records, and it is the volume the running system writes.  This module
\  mounts it through ext4's staged-write binding, gives the writer its
\  clock and its workspace, and reports the outcome to the places registry
\  (places.f) as the volume `user`: attached, with the instance, or
\  refused, with the reason.  A unit that holds no medium leaves the
\  volume missing.  Nothing here stops a boot; composition decides what
\  the outcome means for the places it declares on the volume.
\
\  Public API:
\    USERVOL-MOUNT  ( arena-bytes -- ior )  Mount the user volume.
\    USERVOL-VFS    ( -- vfs | 0 )          The mounted volume, or 0.
\
\  The mount's arena, ARENA-BYTES of extended memory, holds the VFS's and
\  the driver's records for the mount; the cache of entries and names takes
\  its pages from the heap (vfs.f).  The writer's workspace is an arena of
\  its own, at the size the driver asks for the writer's credits.  Both stay with the mount, and a mount
\  that fails gives both back, and the unit.
\
\  docs/utils/fs/user-volume.md describes the module and the volume.
\ =====================================================================

PROVIDED akashic-user-volume

REQUIRE drivers/vfs-ext4.f
REQUIRE places.f

\ The writer's credits for one transaction: metadata blocks, data blocks
\ and revoke records, the profile the user volume's costs were measured
\ with (local_testing/evidence/user-volume-20261115.md).
16 CONSTANT USERVOL-META-CREDITS
16 CONSTANT USERVOL-DATA-CREDITS
2  CONSTANT USERVOL-REVOKE-CREDITS

CREATE _USERVOL-BD      /BLOCK-DEVICE ALLOT
CREATE _USERVOL-VOLUME  /VOLUME ALLOT
_USERVOL-BD      /BLOCK-DEVICE  0 FILL
_USERVOL-VOLUME  /VOLUME        0 FILL

VARIABLE _USERVOL-VFS      0 _USERVOL-VFS !
VARIABLE _USERVOL-ARENA    0 _USERVOL-ARENA !
VARIABLE _USERVOL-WRITER   0 _USERVOL-WRITER !
VARIABLE _USERVOL-RECORD
VARIABLE _USERVOL-V

: USERVOL-VFS  ( -- vfs | 0 )  _USERVOL-VFS @ ;

\ The writer's clock: the machine's epoch in milliseconds.
: _USERVOL-NOW  ( context -- epoch-ms ior )  DROP EPOCH@ 0 ;

\ _USERVOL-BIND ( -- ior )
\   Give the mounted writer its clock and a workspace for its credits.
: _USERVOL-BIND  ( -- ior )
    ['] _USERVOL-NOW 0 _USERVOL-V @ EXT4-BIND-WRITE-CLOCK? ?DUP IF EXIT THEN
    USERVOL-META-CREDITS USERVOL-DATA-CREDITS USERVOL-REVOKE-CREDITS
        _USERVOL-V @ EXT4-WRITER-WORKSPACE-BYTES? ?DUP IF NIP EXIT THEN
    A-XMEM ARENA-NEW IF DROP VFS-E-NOMEM EXIT THEN
    DUP _USERVOL-WRITER !
    USERVOL-META-CREDITS USERVOL-DATA-CREDITS USERVOL-REVOKE-CREDITS
        _USERVOL-V @ EXT4-BIND-WRITER-ARENA? ;

\ _USERVOL-RELEASE ( -- )
\   Give back what a failed mount took: the writer's workspace, the
\   instance with its arena, the volume and the unit.
: _USERVOL-RELEASE  ( -- )
    _USERVOL-WRITER @ ?DUP IF ARENA-DESTROY 0 _USERVOL-WRITER ! THEN
    _USERVOL-V @ ?DUP IF
        VFS-DESTROY 0 _USERVOL-V !  0 _USERVOL-ARENA !
    THEN
    _USERVOL-ARENA @ ?DUP IF ARENA-DESTROY 0 _USERVOL-ARENA ! THEN
    _USERVOL-VOLUME VOL-CLOSE DROP
    _USERVOL-BD BD-CLOSE DROP ;

\ _USERVOL-REFUSE ( ior -- ior )   Record why the mount failed.
: _USERVOL-REFUSE  ( ior -- ior )
    _USERVOL-RELEASE
    DUP _USERVOL-RECORD @ PVOL-REFUSE ;

\ USERVOL-MOUNT ( arena-bytes -- ior )
\   Mount the user volume writable and report it as `user`.  0 when it
\   is attached; VFS-E-NOVOLUME when the unit holds no medium, which
\   leaves the volume missing; otherwise the reason the mount was
\   refused, which the registry records.  VFS-E-BUSY when it is mounted
\   already.
: USERVOL-MOUNT  ( arena-bytes -- ior )
    _USERVOL-VFS @ IF DROP VFS-E-BUSY EXIT THEN
    S" user" PLACES-VOLUME ?DUP IF NIP NIP EXIT THEN _USERVOL-RECORD !
    0 _USERVOL-V !  0 _USERVOL-WRITER !
    A-XMEM ARENA-NEW IF DROP VFS-E-NOMEM _USERVOL-REFUSE EXIT THEN
    _USERVOL-ARENA !
    _USERVOL-BD USER-UNIT BD-OPEN-UNIT ?DUP IF
        BD-E-NO-MEDIA = IF
            _USERVOL-RELEASE VFS-E-NOVOLUME EXIT
        THEN
        VFS-E-IO _USERVOL-REFUSE EXIT
    THEN
    _USERVOL-BD _USERVOL-VOLUME VOL-RAW IF
        VFS-E-IO _USERVOL-REFUSE EXIT
    THEN
    _USERVOL-ARENA @ _USERVOL-VOLUME EXT4-STAGED-WRITE-NEW
    ?DUP IF NIP _USERVOL-REFUSE EXIT THEN
    _USERVOL-V !
    _USERVOL-BIND ?DUP IF _USERVOL-REFUSE EXIT THEN
    \ A volume `user` attached to another instance keeps it.
    _USERVOL-V @ _USERVOL-RECORD @ PVOL-ATTACH ?DUP IF
        _USERVOL-RELEASE EXIT
    THEN
    _USERVOL-V @ _USERVOL-VFS !
    0 ;
