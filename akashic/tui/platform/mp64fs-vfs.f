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
\  leave that composition-time work without an active VFS.
\ =====================================================================

PROVIDED akashic-tui-mp64fs-vfs

REQUIRE ../../utils/fs/drivers/vfs-mp64fs.f

131072 CONSTANT _MP64VFS-ARENA-SIZE

VARIABLE _MP64VFS-VFS
0 _MP64VFS-VFS !

CREATE _MP64VFS-BLOCK-DEVICE /BLOCK-DEVICE ALLOT
CREATE _MP64VFS-VOLUME /VOLUME ALLOT

\ MP64VFS-ENSURE ( -- )
\   Select the process VFS when already composed, adopt another active VFS,
\   or mount the MegaPad-64 boot disk.  Repeated calls reselect the instance
\   owned or adopted by this composition module.
: MP64VFS-ENSURE  ( -- )
    _MP64VFS-VFS @ ?DUP IF VFS-USE EXIT THEN
    VFS-CUR ?DUP IF DUP _MP64VFS-VFS ! VFS-USE EXIT THEN
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
;

\ Composition-time availability is part of this module's contract.
MP64VFS-ENSURE
