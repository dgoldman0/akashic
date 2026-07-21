\ =====================================================================
\  vfs-access.f - Caller-owned scoped and bounded VFS access
\ =====================================================================
\  One scope borrows one VFS, owns at most one FD, and retains primary
\  failure separately from cleanup uncertainty.  Byte helpers are policy
\  neutral: callers still decide path meaning, size limits, parsing, commit
\  order, and recovery authority.
\ =====================================================================

PROVIDED akashic-vfs-access

REQUIRE vfs.f

\ =====================================================================
\  Common checked geometry
\ =====================================================================

: _VFA-BUFFER?  ( address length -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0> 2 PICK 0= AND IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _VFA-RANGE?  ( offset length size -- flag )
    >R
    DUP 0< IF 2DROP R> DROP 0 EXIT THEN
    OVER 0< IF 2DROP R> DROP 0 EXIT THEN
    2DUP + DUP 0< IF DROP 2DROP R> DROP 0 EXIT THEN
    DUP 3 PICK U< IF DROP 2DROP R> DROP 0 EXIT THEN
    >R 2DROP R> R> <= ;

: _VFA-DROP8  ( x1 x2 x3 x4 x5 x6 x7 x8 -- )
    2DROP 2DROP 2DROP 2DROP ;

: _VFA-VFS-OWNS-SPAN?  ( address length vfs -- flag )
    DUP 0= IF 2DROP DROP 0 EXIT THEN
    V.ARENA @ DUP 0= IF 2DROP DROP 0 EXIT THEN
    DUP 32 MSPAN-NONWRAPPING? 0= IF 2DROP DROP 0 EXIT THEN
    DUP A.SIZE @ >R
    A.BASE @ >R
    R>                              ( address length base ; R: size )
    R@ 0< IF DROP 2DROP R> DROP 0 EXIT THEN
    DUP 0= IF DROP 2DROP R> DROP 0 EXIT THEN
    2 PICK OVER U< IF DROP 2DROP R> DROP 0 EXIT THEN
    ROT SWAP - SWAP R> _VFA-RANGE? ;

: _VFA-VFS-CWD?  ( vfs -- flag )
    DUP V.CWD @ DUP 0= IF 2DROP 0 EXIT THEN
    DUP VFS-INODE-SIZE 3 PICK _VFA-VFS-OWNS-SPAN? 0= IF
        2DROP 0 EXIT
    THEN
    DUP 2 PICK _VFS-DENTRY-OWNED? 0= IF 2DROP 0 EXIT THEN
    DUP D.VNODE @ DUP 0= IF DROP 2DROP 0 EXIT THEN
    DUP VFS-VNODE-SIZE 4 PICK _VFA-VFS-OWNS-SPAN? 0= IF
        2DROP DROP 0 EXIT
    THEN
    VN.TYPE @ VFS-T-DIR = >R 2DROP R> ;

\ =====================================================================
\  Caller-owned VFS/CWD/FD scope
\ =====================================================================
\  The saved CWD is a borrowed dentry.  Bodies may perform byte access and
\  change CWD, but must not unlink, rename, or otherwise invalidate either
\  the saved or active CWD while the scope is live.

0x56464153434F5031 CONSTANT VFA-SCOPE-MAGIC  \ "VFASCOP1"

  0 CONSTANT _VFA-S-MAGIC
  8 CONSTANT _VFA-S-VFS
 16 CONSTANT _VFA-S-FD
 24 CONSTANT _VFA-S-CLOSING-FD
 32 CONSTANT _VFA-S-OLD-VFS
 40 CONSTANT _VFA-S-OLD-CWD
 48 CONSTANT _VFA-S-FLAGS
 56 CONSTANT _VFA-S-BODY-XT
 64 CONSTANT _VFA-S-PRIMARY
 72 CONSTANT _VFA-S-CLEANUP
 80 CONSTANT _VFA-S-CLOSE-IOR
 88 CONSTANT _VFA-S-CLOSE-XT
 96 CONSTANT _VFA-S-USE-XT
104 CONSTANT _VFA-S-CWD-PIN-OWNED
112 CONSTANT VFA-SCOPE-SIZE

1 CONSTANT _VFA-SF-INITIALIZED
2 CONSTANT _VFA-SF-CONTEXT
4 CONSTANT _VFA-SF-RUNNING
8 CONSTANT _VFA-SF-RUN-DONE
15 CONSTANT _VFA-SF-ALL

: _VFA-S.MAGIC       ( scope -- a ) _VFA-S-MAGIC + ;
: _VFA-S.VFS         ( scope -- a ) _VFA-S-VFS + ;
: _VFA-S.FD          ( scope -- a ) _VFA-S-FD + ;
: _VFA-S.CLOSING-FD  ( scope -- a ) _VFA-S-CLOSING-FD + ;
: _VFA-S.OLD-VFS     ( scope -- a ) _VFA-S-OLD-VFS + ;
: _VFA-S.OLD-CWD     ( scope -- a ) _VFA-S-OLD-CWD + ;
: _VFA-S.FLAGS       ( scope -- a ) _VFA-S-FLAGS + ;
: _VFA-S.BODY-XT     ( scope -- a ) _VFA-S-BODY-XT + ;
: _VFA-S.PRIMARY     ( scope -- a ) _VFA-S-PRIMARY + ;
: _VFA-S.CLEANUP     ( scope -- a ) _VFA-S-CLEANUP + ;
: _VFA-S.CLOSE-IOR   ( scope -- a ) _VFA-S-CLOSE-IOR + ;
: _VFA-S.CLOSE-XT    ( scope -- a ) _VFA-S-CLOSE-XT + ;
: _VFA-S.USE-XT      ( scope -- a ) _VFA-S-USE-XT + ;
: _VFA-S.CWD-PIN-OWNED ( scope -- a ) _VFA-S-CWD-PIN-OWNED + ;

: VFA-SCOPE-VALID?  ( scope -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP VFA-SCOPE-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP _VFA-S.MAGIC @ VFA-SCOPE-MAGIC <> IF DROP 0 EXIT THEN
    DUP _VFA-S.VFS @ 0= IF DROP 0 EXIT THEN
    DUP _VFA-S.FLAGS @ DUP _VFA-SF-INITIALIZED AND 0= IF
        2DROP 0 EXIT
    THEN
    _VFA-SF-ALL INVERT AND IF DROP 0 EXIT THEN
    DUP _VFA-S.CLOSE-XT @ 0= IF DROP 0 EXIT THEN
    _VFA-S.USE-XT @ 0<> ;

: VFA-SCOPE-VFS@  ( scope -- vfs|0 )
    DUP VFA-SCOPE-VALID? 0= IF DROP 0 EXIT THEN _VFA-S.VFS @ ;

: VFA-SCOPE-FD@  ( scope -- fd|0 )
    DUP VFA-SCOPE-VALID? 0= IF DROP 0 EXIT THEN _VFA-S.FD @ ;

: VFA-SCOPE-PRIMARY@  ( scope -- primary )
    DUP VFA-SCOPE-VALID? 0= IF DROP VFS-E-INVALID EXIT THEN
    _VFA-S.PRIMARY @ ;

: VFA-SCOPE-CLEANUP@  ( scope -- cleanup )
    DUP VFA-SCOPE-VALID? 0= IF DROP VFS-E-INVALID EXIT THEN
    _VFA-S.CLEANUP @ ;

: _VFA-SCOPE-ACTIVE?  ( scope -- flag )
    DUP _VFA-S.FD @ 0<>
    OVER _VFA-S.CLOSING-FD @ 0<> OR
    SWAP _VFA-S.FLAGS @
    _VFA-SF-CONTEXT _VFA-SF-RUNNING OR AND 0<> OR ;

: VFA-SCOPE-INIT  ( vfs scope -- ior )
    >R
    DUP 0= IF DROP R> DROP VFS-E-INVALID EXIT THEN
    R@ 0= IF DROP R> DROP VFS-E-INVALID EXIT THEN
    R@ VFA-SCOPE-SIZE MSPAN-NONWRAPPING? 0= IF
        DROP R> DROP VFS-E-INVALID EXIT
    THEN
    DUP VFS-DESC-SIZE MSPAN-NONWRAPPING? 0= IF
        DROP R> DROP VFS-E-INVALID EXIT
    THEN
    DUP VFS-DESC-SIZE R@ VFA-SCOPE-SIZE MSPAN-OVERLAP? IF
        DROP R> DROP VFS-E-INVALID EXIT
    THEN
    R@ VFA-SCOPE-VALID? IF
        R@ _VFA-SCOPE-ACTIVE? IF DROP R> DROP VFS-E-BUSY EXIT THEN
    THEN
    R@ VFA-SCOPE-SIZE 0 FILL
    VFA-SCOPE-MAGIC R@ _VFA-S.MAGIC !
    DUP R@ _VFA-S.VFS ! DROP
    _VFA-SF-INITIALIZED R@ _VFA-S.FLAGS !
    ['] VFS-CLOSE? R@ _VFA-S.CLOSE-XT !
    ['] VFS-USE R@ _VFA-S.USE-XT !
    R> DROP 0 ;

: _VFA-SCOPE-CONFIGURABLE?  ( scope -- flag )
    DUP VFA-SCOPE-VALID? 0= IF DROP 0 EXIT THEN
    _VFA-SCOPE-ACTIVE? 0= ;

: VFA-SCOPE-CLOSE-XT!  ( close-xt scope -- ior )
    >R
    DUP 0= IF DROP R> DROP VFS-E-INVALID EXIT THEN
    R@ _VFA-SCOPE-CONFIGURABLE? 0= IF
        DROP R> DROP VFS-E-BUSY EXIT
    THEN
    R@ _VFA-S.CLOSE-XT ! R> DROP 0 ;

: VFA-SCOPE-USE-XT!  ( use-xt scope -- ior )
    >R
    DUP 0= IF DROP R> DROP VFS-E-INVALID EXIT THEN
    R@ _VFA-SCOPE-CONFIGURABLE? 0= IF
        DROP R> DROP VFS-E-BUSY EXIT
    THEN
    R@ _VFA-S.USE-XT ! R> DROP 0 ;

: _VFA-SCOPE-RESET-RESULTS  ( scope -- )
    0 OVER _VFA-S.PRIMARY !
    0 OVER _VFA-S.CLEANUP !
    0 OVER _VFA-S.CLOSE-IOR !
    0 SWAP _VFA-S.CLOSING-FD ! ;

: _VFA-SCOPE-NOTE-CLEANUP  ( ior scope -- )
    >R
    DUP IF
        R@ _VFA-S.CLEANUP @ 0= IF R@ _VFA-S.CLEANUP ! ELSE DROP THEN
    ELSE
        DROP
    THEN
    R> DROP ;

: _VFA-SCOPE-USE-TARGET-CALL  ( scope -- scope )
    DUP _VFA-S.VFS @ OVER _VFA-S.USE-XT @ EXECUTE ;

: _VFA-SCOPE-USE-OLD-CALL  ( scope -- scope )
    DUP _VFA-S.OLD-VFS @ OVER _VFA-S.USE-XT @ EXECUTE ;

: _VFA-SCOPE-ENTER  ( scope -- ior )
    DUP VFA-SCOPE-VALID? 0= IF DROP VFS-E-INVALID EXIT THEN
    DUP _VFA-S.FLAGS @ _VFA-SF-CONTEXT AND IF DROP 0 EXIT THEN
    DUP _VFA-S.FLAGS @ _VFA-SF-RUNNING AND 0= IF
        DUP _VFA-SCOPE-RESET-RESULTS
    THEN
    DUP _VFA-S.VFS @ DUP _VFS-READY ?DUP IF
        >R 2DROP R> EXIT
    THEN
    DUP _VFA-VFS-CWD? 0= IF 2DROP VFS-E-CORRUPT EXIT THEN
    DROP
    VFS-CUR OVER _VFA-S.OLD-VFS !
    DUP _VFA-S.VFS @ V.CWD @ OVER _VFA-S.OLD-CWD !
    DUP _VFA-S.OLD-CWD @ IN.FLAGS @ VFS-IF-PINNED AND 0= IF
        VFS-IF-PINNED OVER _VFA-S.OLD-CWD @ IN.FLAGS DUP @ ROT OR SWAP !
        -1 OVER _VFA-S.CWD-PIN-OWNED !
    THEN
    _VFA-SF-CONTEXT OVER _VFA-S.FLAGS DUP @ ROT OR SWAP !
    ['] _VFA-SCOPE-USE-TARGET-CALL CATCH NIP ;

: _VFA-SCOPE-CLOSE-CALL  ( scope -- scope )
    >R
    R@ _VFA-S.CLOSING-FD @ R@ _VFA-S.CLOSE-XT @ EXECUTE
    R@ _VFA-S.CLOSE-IOR !
    R> ;

: VFA-SCOPE-CLOSE?  ( scope -- cleanup )
    DUP VFA-SCOPE-VALID? 0= IF DROP VFS-E-INVALID EXIT THEN
    >R
    R@ _VFA-S.FD @ ?DUP IF
        R@ _VFA-S.CLOSING-FD !
        0 R@ _VFA-S.FD !
        0 R@ _VFA-S.CLOSE-IOR !
        R@ ['] _VFA-SCOPE-CLOSE-CALL CATCH
        NIP DUP IF
            R@ _VFA-SCOPE-NOTE-CLEANUP
        ELSE
            DROP R@ _VFA-S.CLOSE-IOR @ R@ _VFA-SCOPE-NOTE-CLEANUP
        THEN
        0 R@ _VFA-S.CLOSING-FD !
    THEN
    R@ _VFA-S.FLAGS @ _VFA-SF-CONTEXT AND IF
        \ Clear the obligation before either after-effect boundary.
        R@ _VFA-S.FLAGS DUP @ _VFA-SF-CONTEXT INVERT AND SWAP !
        R@ _VFA-S.OLD-CWD @ R@ _VFA-S.VFS @ V.CWD !
        R@ _VFA-S.CWD-PIN-OWNED @ IF
            R@ _VFA-S.OLD-CWD @ IN.FLAGS DUP @
                VFS-IF-PINNED INVERT AND SWAP !
            0 R@ _VFA-S.CWD-PIN-OWNED !
        THEN
        R@ ['] _VFA-SCOPE-USE-OLD-CALL CATCH
        NIP R@ _VFA-SCOPE-NOTE-CLEANUP
        0 R@ _VFA-S.OLD-CWD ! 0 R@ _VFA-S.OLD-VFS !
    THEN
    R@ _VFA-S.CLEANUP @ R> DROP ;

: _VFA-SCOPE-DIRECT-OPEN-FAILED  ( ior scope -- fd ior )
    >R
    R@ _VFA-S.FLAGS @ _VFA-SF-RUNNING AND 0= IF
        DUP R@ _VFA-S.PRIMARY !
        R@ VFA-SCOPE-CLOSE? DROP
    THEN
    0 SWAP R> DROP ;

: VFA-SCOPE-OPEN?  ( path-a path-u flags scope -- fd ior )
    DUP VFA-SCOPE-VALID? 0= IF DROP 2DROP DROP 0 VFS-E-INVALID EXIT THEN
    DUP _VFA-S.FD @ IF DROP 2DROP DROP 0 VFS-E-BUSY EXIT THEN
    DUP _VFA-S.FLAGS @ _VFA-SF-CONTEXT AND 0= IF
        DUP _VFA-SCOPE-ENTER DUP IF
            >R DUP _VFA-S.PRIMARY R@ SWAP !
            R> SWAP _VFA-SCOPE-DIRECT-OPEN-FAILED
            >R >R 2DROP DROP R> R> EXIT
        THEN DROP
    THEN
    DUP >R _VFA-S.VFS @ VFS-OPEN?
    DUP IF
        NIP
        R@ _VFA-SCOPE-DIRECT-OPEN-FAILED
        R> DROP EXIT
    THEN
    DROP
    DUP 0= IF
        DROP VFS-E-CORRUPT R@ _VFA-SCOPE-DIRECT-OPEN-FAILED
        R> DROP EXIT
    THEN
    DUP R@ _VFA-S.FD ! 0 R> DROP ;

: _VFA-SCOPE-BODY-CALL  ( scope -- scope )
    >R R@ _VFA-S.BODY-XT @ EXECUTE R> ;

: _VFA-SCOPE-RUN  ( scope -- scope )
    DUP >R
    R@ _VFA-S.FLAGS DUP @
        _VFA-SF-RUN-DONE INVERT AND _VFA-SF-RUNNING OR SWAP !
    R@ _VFA-S.FLAGS @ _VFA-SF-CONTEXT AND 0= IF
        R@ _VFA-SCOPE-ENTER DUP IF
            R@ _VFA-S.PRIMARY !
        ELSE
            DROP R@ ['] _VFA-SCOPE-BODY-CALL CATCH
            NIP R@ _VFA-S.PRIMARY !
        THEN
    ELSE
        R@ ['] _VFA-SCOPE-BODY-CALL CATCH
        NIP R@ _VFA-S.PRIMARY !
    THEN
    R@ VFA-SCOPE-CLOSE? DROP
    R@ _VFA-S.FLAGS DUP @
        _VFA-SF-RUNNING INVERT AND _VFA-SF-RUN-DONE OR SWAP !
    R> DROP ;

: _VFA-SCOPE-TRANSACTION-CALL  ( scope -- scope )
    ['] _VFA-SCOPE-RUN VFS-TRANSACTION ;

: _VFA-SCOPE-NOTE-OUTER  ( throw scope -- )
    >R
    R@ _VFA-S.FLAGS @ _VFA-SF-RUN-DONE AND IF
        R@ _VFA-SCOPE-NOTE-CLEANUP
    ELSE
        R@ _VFA-S.PRIMARY @ 0= IF
            R@ _VFA-S.PRIMARY !
        ELSE
            DROP
        THEN
        R@ VFA-SCOPE-CLOSE? DROP
        R@ _VFA-S.FLAGS DUP @
            _VFA-SF-RUNNING INVERT AND _VFA-SF-RUN-DONE OR SWAP !
    THEN
    R> DROP ;

: VFA-SCOPE-CALL  ( body-xt scope -- primary cleanup )
    >R
    DUP 0= IF DROP R> DROP VFS-E-INVALID 0 EXIT THEN
    R@ VFA-SCOPE-VALID? 0= IF DROP R> DROP VFS-E-INVALID 0 EXIT THEN
    R@ _VFA-S.FLAGS @ _VFA-SF-RUNNING AND IF
        DROP R> DROP VFS-E-BUSY 0 EXIT
    THEN
    R@ _VFA-S.FLAGS @ _VFA-SF-CONTEXT AND 0= IF
        R@ _VFA-SCOPE-RESET-RESULTS
    THEN
    R@ _VFA-S.BODY-XT !
    R@ ['] _VFA-SCOPE-TRANSACTION-CALL CATCH
    NIP ?DUP IF R@ _VFA-SCOPE-NOTE-OUTER THEN
    R@ _VFA-S.PRIMARY @ R@ _VFA-S.CLEANUP @
    R> DROP ;

\ =====================================================================
\  Bounded, prefix, and exact ranged reads
\ =====================================================================

: VFA-FILE-SIZE?  ( fd -- size ior )
    DUP 0= IF DROP 0 VFS-E-BADF EXIT THEN
    DUP FD.VFS @ DUP 0= IF 2DROP 0 VFS-E-BADF EXIT THEN
    DUP _VFS-READY ?DUP IF >R 2DROP 0 R> EXIT THEN
    OVER FD.FLAGS @ VFS-FF-READ AND 0= IF
        2DROP 0 VFS-E-BADF EXIT
    THEN
    OVER FD.INODE @ DUP 0= IF DROP 2DROP 0 VFS-E-BADF EXIT THEN
    DUP IN.TYPE @ VFS-T-DIR = IF DROP 2DROP 0 VFS-E-ISDIR EXIT THEN
    2 PICK FD.GEN @ 2 PICK V.MEDIA-GEN @ <> IF
        2DROP DROP 0 VFS-E-STALE EXIT
    THEN
    DUP IN.SIZE-HI @ 0<> IF 2DROP DROP 0 VFS-E-OVERFLOW EXIT THEN
    IN.SIZE-LO @ >R 2DROP R>
    DUP 0< IF DROP 0 VFS-E-OVERFLOW EXIT THEN 0 ;

: VFA-READ-RANGE?  ( buffer length offset fd -- ior )
    2 PICK 0< IF 2DROP 2DROP VFS-E-OVERFLOW EXIT THEN
    3 PICK 3 PICK _VFA-BUFFER? 0= IF
        2DROP 2DROP VFS-E-INVALID EXIT
    THEN
    DUP VFA-FILE-SIZE?
    DUP IF
        >R 2DROP 2DROP DROP R> EXIT
    THEN DROP
    2 PICK 4 PICK 2 PICK _VFA-RANGE? 0= IF
        2DROP 2DROP DROP VFS-E-OVERFLOW EXIT
    THEN
    DROP
    2DUP VFS-SEEK? ?DUP IF
        >R 2DROP 2DROP R> EXIT
    THEN
    SWAP DROP VFS-READ-EXACT ;

: VFA-READ-FILE?  ( buffer capacity fd -- length ior )
    2 PICK 2 PICK _VFA-BUFFER? 0= IF
        2DROP DROP 0 VFS-E-INVALID EXIT
    THEN
    DUP VFA-FILE-SIZE?
    DUP IF
        >R 2DROP 2DROP 0 R> EXIT
    THEN DROP
    DUP 3 PICK > IF
        2DROP 2DROP 0 VFS-E-OVERFLOW EXIT
    THEN
    >R SWAP DROP
    R@ SWAP 0 SWAP VFA-READ-RANGE?
    DUP IF R> DROP 0 SWAP ELSE R> SWAP THEN ;

: VFA-READ-PREFIX?  ( buffer capacity fd -- length total truncated? ior )
    2 PICK 2 PICK _VFA-BUFFER? 0= IF
        2DROP DROP 0 0 0 VFS-E-INVALID EXIT
    THEN
    DUP VFA-FILE-SIZE?
    DUP IF
        >R 2DROP 2DROP 0 0 0 R> EXIT
    THEN DROP
    DUP 3 PICK > >R
    DUP 3 PICK MIN
    SWAP >R >R
    SWAP DROP
    R@ SWAP 0 SWAP VFA-READ-RANGE?
    DUP IF
        R> DROP 0 SWAP
    ELSE
        R> SWAP
    THEN
    R> SWAP R> SWAP ;

\ =====================================================================
\  Caller-owned callback stream
\ =====================================================================

0 CONSTANT VFA-STREAM-CONTINUE
1 CONSTANT VFA-STREAM-STOP

0x5646415354524D31 CONSTANT VFA-STREAM-MAGIC  \ "VFASTRM1"

  0 CONSTANT _VFA-T-MAGIC
  8 CONSTANT _VFA-T-FD
 16 CONSTANT _VFA-T-START
 24 CONSTANT _VFA-T-LENGTH
 32 CONSTANT _VFA-T-SCRATCH
 40 CONSTANT _VFA-T-SCRATCH-CAP
 48 CONSTANT _VFA-T-CALLBACK-XT
 56 CONSTANT _VFA-T-CONTEXT
 64 CONSTANT _VFA-T-DELIVERED
 72 CONSTANT _VFA-T-STOPPED
 80 CONSTANT _VFA-T-IOR
 88 CONSTANT _VFA-T-DATA-U
 96 CONSTANT _VFA-T-OFFSET
104 CONSTANT _VFA-T-FLAGS
112 CONSTANT _VFA-T-ACTION
120 CONSTANT _VFA-T-CALLBACK-IOR
128 CONSTANT VFA-STREAM-SIZE

1 CONSTANT _VFA-TF-INITIALIZED
2 CONSTANT _VFA-TF-ACTIVE
4 CONSTANT _VFA-TF-DONE
7 CONSTANT _VFA-TF-ALL

: _VFA-T.MAGIC        ( stream -- a ) _VFA-T-MAGIC + ;
: _VFA-T.FD           ( stream -- a ) _VFA-T-FD + ;
: _VFA-T.START        ( stream -- a ) _VFA-T-START + ;
: _VFA-T.LENGTH       ( stream -- a ) _VFA-T-LENGTH + ;
: _VFA-T.SCRATCH      ( stream -- a ) _VFA-T-SCRATCH + ;
: _VFA-T.SCRATCH-CAP  ( stream -- a ) _VFA-T-SCRATCH-CAP + ;
: _VFA-T.CALLBACK-XT  ( stream -- a ) _VFA-T-CALLBACK-XT + ;
: _VFA-T.CONTEXT      ( stream -- a ) _VFA-T-CONTEXT + ;
: _VFA-T.DELIVERED    ( stream -- a ) _VFA-T-DELIVERED + ;
: _VFA-T.STOPPED      ( stream -- a ) _VFA-T-STOPPED + ;
: _VFA-T.IOR          ( stream -- a ) _VFA-T-IOR + ;
: _VFA-T.DATA-U       ( stream -- a ) _VFA-T-DATA-U + ;
: _VFA-T.OFFSET       ( stream -- a ) _VFA-T-OFFSET + ;
: _VFA-T.FLAGS        ( stream -- a ) _VFA-T-FLAGS + ;
: _VFA-T.ACTION       ( stream -- a ) _VFA-T-ACTION + ;
: _VFA-T.CALLBACK-IOR ( stream -- a ) _VFA-T-CALLBACK-IOR + ;

: _VFA-STREAM-VALID?  ( stream -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP VFA-STREAM-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP _VFA-T.MAGIC @ VFA-STREAM-MAGIC <> IF DROP 0 EXIT THEN
    DUP _VFA-T.FLAGS @ DUP _VFA-TF-INITIALIZED AND 0= IF
        2DROP 0 EXIT
    THEN
    _VFA-TF-ALL INVERT AND IF DROP 0 EXIT THEN
    DUP _VFA-T.CALLBACK-XT @ 0= IF DROP 0 EXIT THEN
    DUP _VFA-T.SCRATCH @ OVER _VFA-T.SCRATCH-CAP @
        _VFA-BUFFER? 0= IF DROP 0 EXIT THEN
    DUP _VFA-T.SCRATCH @ OVER _VFA-T.SCRATCH-CAP @
        2 PICK VFA-STREAM-SIZE MSPAN-OVERLAP? IF DROP 0 EXIT THEN
    DROP -1 ;

: VFA-STREAM-INIT  ( fd offset length scratch-a scratch-u callback-xt context stream -- ior )
    DUP 0= IF _VFA-DROP8 VFS-E-INVALID EXIT THEN
    DUP VFA-STREAM-SIZE MSPAN-NONWRAPPING? 0= IF
        _VFA-DROP8 VFS-E-INVALID EXIT
    THEN
    DUP _VFA-STREAM-VALID? IF
        DUP _VFA-T.FLAGS @ _VFA-TF-ACTIVE AND IF
            _VFA-DROP8 VFS-E-BUSY EXIT
        THEN
    THEN
    2 PICK 0= IF _VFA-DROP8 VFS-E-INVALID EXIT THEN
    4 PICK 4 PICK _VFA-BUFFER? 0= IF
        _VFA-DROP8 VFS-E-INVALID EXIT
    THEN
    4 PICK 4 PICK 2 PICK VFA-STREAM-SIZE MSPAN-OVERLAP? IF
        _VFA-DROP8 VFS-E-INVALID EXIT
    THEN
    5 PICK 0< IF _VFA-DROP8 VFS-E-OVERFLOW EXIT THEN
    6 PICK 0< IF _VFA-DROP8 VFS-E-OVERFLOW EXIT THEN
    5 PICK 0> 4 PICK 0= AND IF _VFA-DROP8 VFS-E-INVALID EXIT THEN
    7 PICK VFA-FILE-SIZE?
    DUP IF
        >R DROP _VFA-DROP8 R> EXIT
    THEN DROP
    7 PICK 7 PICK 2 PICK _VFA-RANGE? 0= IF
        DROP _VFA-DROP8 VFS-E-OVERFLOW EXIT
    THEN
    DROP
    >R
    R@ VFA-STREAM-SIZE 0 FILL
    R@ _VFA-T.CONTEXT !
    R@ _VFA-T.CALLBACK-XT !
    R@ _VFA-T.SCRATCH-CAP !
    R@ _VFA-T.SCRATCH !
    R@ _VFA-T.LENGTH !
    R@ _VFA-T.START !
    R@ _VFA-T.FD !
    VFA-STREAM-MAGIC R@ _VFA-T.MAGIC !
    _VFA-TF-INITIALIZED R@ _VFA-T.FLAGS !
    R> DROP 0 ;

: VFA-STREAM-DATA@  ( stream -- chunk-a chunk-u )
    DUP _VFA-STREAM-VALID? 0= IF DROP 0 0 EXIT THEN
    DUP _VFA-T.SCRATCH @ SWAP _VFA-T.DATA-U @ ;

: VFA-STREAM-OFFSET@  ( stream -- absolute-offset )
    DUP _VFA-STREAM-VALID? 0= IF DROP 0 EXIT THEN _VFA-T.OFFSET @ ;

: VFA-STREAM-CONTEXT@  ( stream -- context )
    DUP _VFA-STREAM-VALID? 0= IF DROP 0 EXIT THEN _VFA-T.CONTEXT @ ;

: _VFA-STREAM-READ-CALL  ( stream -- stream )
    >R
    R@ _VFA-T.SCRATCH @ R@ _VFA-T.DATA-U @ R@ _VFA-T.FD @
        VFS-READ-EXACT R@ _VFA-T.IOR !
    R> ;

: _VFA-STREAM-CALLBACK-CALL  ( stream -- stream )
    >R
    R@
    R@ _VFA-T.CALLBACK-XT @ EXECUTE
    R@ _VFA-T.CALLBACK-IOR !
    R@ _VFA-T.ACTION !
    R> ;

: _VFA-STREAM-FINISH  ( stream -- delivered stopped? ior )
    DUP _VFA-T.FLAGS DUP @
        _VFA-TF-ACTIVE INVERT AND _VFA-TF-DONE OR SWAP !
    DUP _VFA-T.DELIVERED @
    OVER _VFA-T.STOPPED @
    ROT _VFA-T.IOR @ ;

: VFA-STREAM-RUN  ( stream -- delivered stopped? ior )
    DUP _VFA-STREAM-VALID? 0= IF DROP 0 0 VFS-E-INVALID EXIT THEN
    DUP _VFA-T.FLAGS @ _VFA-TF-ACTIVE AND IF
        DROP 0 0 VFS-E-BUSY EXIT
    THEN
    DUP _VFA-T.FLAGS @ _VFA-TF-DONE AND IF
        _VFA-STREAM-FINISH EXIT
    THEN
    >R
    0 R@ _VFA-T.DELIVERED ! 0 R@ _VFA-T.STOPPED !
    0 R@ _VFA-T.IOR ! 0 R@ _VFA-T.DATA-U !
    _VFA-TF-ACTIVE R@ _VFA-T.FLAGS DUP @ ROT OR SWAP !
    R@ _VFA-T.START @ R@ _VFA-T.FD @ VFS-SEEK?
    DUP IF R@ _VFA-T.IOR ! R> _VFA-STREAM-FINISH EXIT THEN DROP
    BEGIN
        R@ _VFA-T.DELIVERED @ R@ _VFA-T.LENGTH @ <
        R@ _VFA-T.STOPPED @ 0= AND
        R@ _VFA-T.IOR @ 0= AND
    WHILE
        R@ _VFA-T.LENGTH @ R@ _VFA-T.DELIVERED @ -
        R@ _VFA-T.SCRATCH-CAP @ MIN R@ _VFA-T.DATA-U !
        R@ _VFA-T.START @ R@ _VFA-T.DELIVERED @ +
        R@ _VFA-T.OFFSET !
        0 R@ _VFA-T.IOR !
        R@ ['] _VFA-STREAM-READ-CALL CATCH
        NIP ?DUP IF R@ _VFA-T.IOR ! THEN
        R@ _VFA-T.IOR @ 0= IF
            0 R@ _VFA-T.ACTION ! 0 R@ _VFA-T.CALLBACK-IOR !
            R@ ['] _VFA-STREAM-CALLBACK-CALL CATCH
            NIP ?DUP IF R@ _VFA-T.IOR ! THEN
        THEN
        R@ _VFA-T.IOR @ 0= IF
            R@ _VFA-T.CALLBACK-IOR @ ?DUP IF
                R@ _VFA-T.IOR !
            ELSE
                R@ _VFA-T.ACTION @ DUP VFA-STREAM-CONTINUE =
                OVER VFA-STREAM-STOP = OR 0= IF
                    DROP VFS-E-CORRUPT R@ _VFA-T.IOR !
                ELSE
                    VFA-STREAM-STOP = IF -1 R@ _VFA-T.STOPPED ! THEN
                    R@ _VFA-T.DATA-U @ R@ _VFA-T.DELIVERED +!
                THEN
            THEN
        THEN
    REPEAT
    R> _VFA-STREAM-FINISH ;
