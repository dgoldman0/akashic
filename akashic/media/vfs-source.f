\ =====================================================================
\  media/vfs-source.f — a media source for one file in a VFS
\ =====================================================================
\
\  Opens a file read-only, keeps it open until the source is released, and
\  reads exact spans at any offset.  If the file system changes under the
\  open file, reads fail (VFS-E-STALE) and the viewer says so; a new source
\  sees the new file.
\
\  A VFS source is a media source record followed by its file, so the
\  record itself is the source every reader takes.
\
\  Public API:
\    MEDSRC-VFS-SIZE  ( -- bytes )
\    MEDSRC-VFS-OPEN  ( path-a path-u vfs source -- ior )
\ =====================================================================

REQUIRE ../utils/fs/vfs.f
REQUIRE ../utils/fs/vfs-access.f
REQUIRE source.f

PROVIDED akashic-media-vfs-source

MEDSRC-SIZE      CONSTANT _MVS.FD
MEDSRC-SIZE 8 +  CONSTANT MEDSRC-VFS-SIZE

: _MVS-CLOSE  ( fd -- )  VFS-CLOSE? DROP ;

\ MEDSRC-VFS-OPEN ( path-a path-u vfs source -- ior )
\   Open PATH in VFS as SOURCE, a record of MEDSRC-VFS-SIZE bytes.  On a
\   nonzero ior nothing is open and SOURCE is not a source.
: MEDSRC-VFS-OPEN  ( path-a path-u vfs source -- ior )
    >R
    0 R@ MEDSRC.MAGIC !
    VFS-FF-READ SWAP VFS-OPEN?               ( fd ior )
    ?DUP IF NIP R> DROP EXIT THEN            ( fd )
    DUP VFA-FILE-SIZE?                       ( fd size ior )
    ?DUP IF >R DROP _MVS-CLOSE R> R> DROP EXIT THEN
    ['] VFA-READ-RANGE? ['] _MVS-CLOSE 3 PICK R@ MEDSRC-INIT
    R> _MVS.FD + !  0 ;
