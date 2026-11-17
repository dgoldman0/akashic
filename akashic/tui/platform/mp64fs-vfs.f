\ =====================================================================
\  mp64fs-vfs.f — MegaPad-64 VFS composition
\ =====================================================================
\  Megapad-64 / KDOS Forth      Prefix: MP64VFS- / _MP64VFS-
\
\  Concrete TUI-platform composition for the MegaPad-64 boot disk.
\  Shared applet infrastructure consumes the abstract VFS interface and
\  must not import this module.  A product image selects this provider by
\  loading it before any applet performs filesystem provisioning.
\
\  Loading is intentionally eager.  Desk provisions Practice resources
\  before ASHELL-RUN, so deferring the mount to the shell lifecycle would
\  leave that composition-time work without the boot volume.
\ =====================================================================

PROVIDED akashic-tui-mp64fs-vfs

REQUIRE ../../utils/fs/drivers/vfs-mp64fs.f
REQUIRE ../../utils/fs/places.f

131072 CONSTANT _MP64VFS-ARENA-SIZE

VARIABLE _MP64VFS-VFS
0 _MP64VFS-VFS !

CREATE _MP64VFS-BLOCK-DEVICE /BLOCK-DEVICE ALLOT
CREATE _MP64VFS-VOLUME /VOLUME ALLOT

\ The instance this module owns or adopted is the volume `boot` of the
\ places registry (utils/fs/places.f), which composition declares places
\ over.
: _MP64VFS-REPORT  ( -- )
    S" boot" PLACES-VOLUME ABORT" mp64vfs: boot volume record failed"
    _MP64VFS-VFS @ SWAP PVOL-ATTACH
    ABORT" mp64vfs: boot volume is attached elsewhere" ;

\ MP64VFS-ENSURE ( -- )
\   Mount the MegaPad-64 boot disk and report it as the volume `boot`.  A
\   composition that attached an instance as `boot` before this module
\   loaded has that instance adopted instead.  Repeated calls change
\   nothing.
: MP64VFS-ENSURE  ( -- )
    _MP64VFS-VFS @ IF EXIT THEN
    S" boot" PLACES-VOLUME ABORT" mp64vfs: boot volume record failed"
    PVOL-VFS ?DUP IF _MP64VFS-VFS ! EXIT THEN
    0 _MP64VFS-BLOCK-DEVICE !
    _MP64VFS-BLOCK-DEVICE BD-OPEN
    ABORT" mp64vfs: block device open failed"
    0 _MP64VFS-VOLUME !
    _MP64VFS-BLOCK-DEVICE _MP64VFS-VOLUME VOL-RAW
    ABORT" mp64vfs: raw volume init failed"
    _MP64VFS-ARENA-SIZE A-XMEM ARENA-NEW
    ABORT" mp64vfs: VFS arena alloc failed"
    _MP64VFS-VOLUME VMP-NEW
    ABORT" mp64vfs: VMP mount failed"
    _MP64VFS-VFS !
    _MP64VFS-REPORT
;

\ Composition-time availability is part of this module's contract.
MP64VFS-ENSURE
