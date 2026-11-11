\ =====================================================================
\  system-volume.f — the system volume and its modules
\ =====================================================================
\  Megapad-64 / KDOS Forth      Prefix: SYSVOL- / _SYSVOL-
\
\  The system volume is the ext4 volume on the machine's system storage
\  unit, KDOS's SYSTEM-UNIT.  It holds the system's modules as
\  individual files, and nothing writes it while the system runs.  This
\  module mounts it read-only and fills the module source through which
\  KDOS's LOAD and REQUIRE read from it.
\
\  Public API:
\    SYSVOL-MOUNT   ( arena -- ior )  Mount the system volume from ARENA.
\    SYSVOL-VFS     ( -- vfs | 0 )    The mounted volume; 0 before a mount.
\    SYSVOL-SOURCE  ( -- source )     Its module source.
\
\  A boot loads this module and the ext4 driver from the boot volume,
\  mounts, and selects the source:
\
\      524288 A-XMEM ARENA-NEW THROW  SYSVOL-MOUNT THROW
\      SYSVOL-SOURCE MODULE-SOURCE!
\
\  From then on a module name is a path on the system volume.
\  `FS-MODULE-SOURCE MODULE-SOURCE!` returns loading to the boot volume,
\  and SYSVOL-SOURCE selects the system volume again.
\
\  ARENA is the mount's storage and stays the caller's: the VFS and the
\  ext4 driver keep the mount's records and its cache of entries and
\  names inside it.  The volume is mounted once and stays mounted.
\
\  The mount leaves the current VFS as it found it, and a failed mount
\  gives the unit back.  SYSVOL-SOURCE throws VFS-E-NOVOLUME before a
\  mount, so a boot that ignored a failed mount stops there and never
\  selects an empty source.
\ =====================================================================

PROVIDED akashic-system-volume

REQUIRE drivers/vfs-ext4.f
REQUIRE vfs-module-source.f

CREATE _SYSVOL-BD      /BLOCK-DEVICE ALLOT
CREATE _SYSVOL-VOLUME  /VOLUME ALLOT
CREATE _SYSVOL-SOURCE  /MODULE-SOURCE ALLOT
_SYSVOL-BD      /BLOCK-DEVICE  0 FILL
_SYSVOL-VOLUME  /VOLUME        0 FILL
_SYSVOL-SOURCE  /MODULE-SOURCE 0 FILL

VARIABLE _SYSVOL-VFS    0 _SYSVOL-VFS !
VARIABLE _SYSVOL-PRIOR  \ the VFS that was current when the mount began

: SYSVOL-VFS  ( -- vfs | 0 )  _SYSVOL-VFS @ ;

: SYSVOL-SOURCE  ( -- source )
    _SYSVOL-VFS @ 0= IF VFS-E-NOVOLUME THROW THEN
    _SYSVOL-SOURCE ;

\ _SYSVOL-RELEASE ( -- )  Give back the volume and the unit.
: _SYSVOL-RELEASE  ( -- )
    _SYSVOL-VOLUME VOL-CLOSE DROP
    _SYSVOL-BD BD-CLOSE DROP ;

\ SYSVOL-MOUNT ( arena -- ior )  Mount the system volume read-only.
\ VFS-E-BUSY when it is mounted already.  Mounting makes the new VFS
\ current, so the one that was current is selected again either way.
: SYSVOL-MOUNT  ( arena -- ior )
    _SYSVOL-VFS @ IF DROP VFS-E-BUSY EXIT THEN
    _SYSVOL-BD SYSTEM-UNIT BD-OPEN-UNIT ?DUP IF NIP EXIT THEN
    _SYSVOL-BD _SYSVOL-VOLUME VOL-RAW ?DUP IF
        NIP _SYSVOL-BD BD-CLOSE DROP EXIT
    THEN
    VFS-CUR _SYSVOL-PRIOR !
    _SYSVOL-VOLUME EXT4-NEW
    _SYSVOL-PRIOR @ VFS-USE
    ?DUP IF NIP _SYSVOL-RELEASE EXIT THEN
    DUP _SYSVOL-VFS !
    _SYSVOL-SOURCE VMS-INIT
    0 ;
