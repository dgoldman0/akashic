\ =====================================================================
\  places.f - Volumes, places and place sets
\ =====================================================================
\  Megapad-64 / KDOS Forth      Prefix: PLACES- PVOL- PLSET- PLACE-
\
\  A volume is one mounted VFS instance with a name.  The module that
\  mounts it reports the outcome here: attached, with the instance, or
\  refused, with the reason.  A place is a folder of a volume with a
\  name, a label and an access, declared by system composition.  A place
\  set is what one holder is given: an ordered list of places, each with
\  an access no wider than its declaration's, a home for the holder's
\  own records, an origin for its shipped files and a documents place
\  where a person's documents go.
\
\  A holder works through the PLACE- words.  A path given to them starts
\  at the place's folder, the entry it names must lie under that folder
\  (so neither `..` nor a symbolic link leaves the place), and a word
\  that changes anything is refused on a read-only place.  The words
\  hold the volume's current directory for the length of one call,
\  inside one VFS-TRANSACTION, so callers never touch V.CWD.
\
\  A place keeps no entry of its folder.  It resolves the folder when it
\  is asked, so a folder that another holder renames, or the driver
\  evicts, is found again or reported absent.  A word that is handed a
\  live entry looks nothing up before it uses the entry, since a lookup
\  may evict it: it finds the folder on the entry's own parent chain and
\  matches that chain against the declared folder path, name for name.
\  A folder is therefore declared by its own path, with no symbolic link
\  in it.
\
\  The registry never stops a boot: every word answers a status, and
\  composition decides what an unavailable place means.
\
\  Volumes, places, sets and grants are heap records, so their number
\  follows need.  docs/utils/fs/places.md is the design.
\ =====================================================================

PROVIDED akashic-places

REQUIRE vfs.f
REQUIRE place-name.f
REQUIRE ../string.f

0 CONSTANT PLACE-READ-ONLY
1 CONSTANT PLACE-WRITABLE

\ =====================================================================
\  Records
\ =====================================================================

\ A volume: its instance while attached, the reason its mount was
\ refused, and its name after the fields.
: _PV.NEXT     ( volume -- a ) ;
: _PV.VFS      ( volume -- a )  8 + ;
: _PV.REFUSAL  ( volume -- a ) 16 + ;
: _PV.NAME-U   ( volume -- a ) 24 + ;
: _PV.NAME     ( volume -- a ) 32 + ;

\ A declared place: its name and then its folder follow the fields.  The
\ label is a block of its own, since it may be set after the declaration.
: _PD.NEXT      ( decl -- a ) ;
: _PD.VOLUME    ( decl -- a )  8 + ;
: _PD.ACCESS    ( decl -- a ) 16 + ;
: _PD.REQUIRED  ( decl -- a ) 24 + ;
: _PD.LABEL-A   ( decl -- a ) 32 + ;
: _PD.LABEL-U   ( decl -- a ) 40 + ;
: _PD.NAME-U    ( decl -- a ) 48 + ;
: _PD.FOLDER-U  ( decl -- a ) 56 + ;
: _PD.NAME      ( decl -- a ) 64 + ;

\ A set, and a grant of one place in it.  The grant is the `place` handle
\ a holder works with.
0x54455350 CONSTANT _PLSET-MAGIC     \ "PSET"
0x43414C50 CONSTANT _PLACE-MAGIC     \ "PLAC"

: _PS.MAGIC    ( set -- a ) ;
: _PS.FIRST    ( set -- a )  8 + ;
: _PS.HOME     ( set -- a ) 16 + ;
: _PS.ORIGIN   ( set -- a ) 24 + ;
: _PS.CHANGES  ( set -- a ) 32 + ;
: _PS.DOCUMENTS  ( set -- a ) 40 + ;
48 CONSTANT _PS-SIZE

: _PG.MAGIC   ( place -- a ) ;
: _PG.NEXT    ( place -- a )  8 + ;
: _PG.SET     ( place -- a ) 16 + ;
: _PG.DECL    ( place -- a ) 24 + ;
: _PG.ACCESS  ( place -- a ) 32 + ;
40 CONSTANT _PG-SIZE

VARIABLE _PL-VOLUMES     0 _PL-VOLUMES !
VARIABLE _PL-DECLS       0 _PL-DECLS !
VARIABLE _PL-DECL-LAST   0 _PL-DECL-LAST !
VARIABLE _PL-DEFAULT     0 _PL-DEFAULT !
\ Counts every change of a volume's state or of the declarations, which
\ can change any set's places.
VARIABLE _PL-CHANGES     0 _PL-CHANGES !

: _PL-CHANGED  ( -- )  1 _PL-CHANGES +! ;

: _PLSET?  ( x -- flag )
    DUP 0= IF EXIT THEN  _PS.MAGIC @ _PLSET-MAGIC = ;
: _PLACE?  ( x -- flag )
    DUP 0= IF EXIT THEN  _PG.MAGIC @ _PLACE-MAGIC = ;

: _PD-NAME    ( decl -- a u )  DUP _PD.NAME SWAP _PD.NAME-U @ ;
: _PD-FOLDER  ( decl -- a u )
    DUP _PD.NAME OVER _PD.NAME-U @ + SWAP _PD.FOLDER-U @ ;

\ =====================================================================
\  Volumes
\ =====================================================================

: _PL-VOLUME-FIND  ( name-a name-u -- volume | 0 )
    _PL-VOLUMES @
    BEGIN DUP WHILE
        >R 2DUP R@ _PV.NAME R@ _PV.NAME-U @ STR-STR= IF
            2DROP R> EXIT
        THEN
        R> _PV.NEXT @
    REPEAT
    NIP NIP ;

\ PLACES-VOLUME ( name-a name-u -- volume ior )
\   The volume of that name, made when there is none.  It is unavailable
\   until its mounting module attaches it.
: PLACES-VOLUME  ( name-a name-u -- volume ior )
    2DUP PLACE-NAME-VALID? 0= IF 2DROP 0 VFS-E-INVALID EXIT THEN
    2DUP _PL-VOLUME-FIND ?DUP IF NIP NIP 0 EXIT THEN
    DUP 32 + ALLOCATE IF DROP 2DROP 0 VFS-E-NOMEM EXIT THEN
    >R                                          ( name-a name-u  R: volume )
    0 R@ _PV.VFS !  0 R@ _PV.REFUSAL !
    DUP R@ _PV.NAME-U !
    R@ _PV.NAME SWAP CMOVE
    _PL-VOLUMES @ R@ _PV.NEXT !  R@ _PL-VOLUMES !
    _PL-CHANGED
    R> 0 ;

\ PVOL-ATTACH ( vfs volume -- ior )
\   The volume is mounted as VFS.  A volume attached to another instance
\   answers VFS-E-BUSY until it is detached.
: PVOL-ATTACH  ( vfs volume -- ior )
    OVER 0= OVER 0= OR IF 2DROP VFS-E-INVALID EXIT THEN
    DUP _PV.VFS @ ?DUP IF
        >R DROP R> = IF 0 ELSE VFS-E-BUSY THEN EXIT
    THEN
    0 OVER _PV.REFUSAL !  _PV.VFS !
    _PL-CHANGED 0 ;

\ PVOL-REFUSE ( ior volume -- )   The mount failed, for the reason IOR.
: PVOL-REFUSE  ( ior volume -- )
    DUP 0= IF 2DROP EXIT THEN
    0 OVER _PV.VFS !
    SWAP ?DUP 0= IF VFS-E-IO THEN SWAP _PV.REFUSAL !
    _PL-CHANGED ;

\ PVOL-DETACH ( volume -- )   The volume is no longer mounted.
: PVOL-DETACH  ( volume -- )
    DUP 0= IF DROP EXIT THEN
    0 OVER _PV.VFS !  0 SWAP _PV.REFUSAL !
    _PL-CHANGED ;

: PVOL-VFS   ( volume -- vfs | 0 )  _PV.VFS @ ;
: PVOL-NAME  ( volume -- a u )  DUP _PV.NAME SWAP _PV.NAME-U @ ;

\ =====================================================================
\  Declarations
\ =====================================================================

: _PL-DECL-FIND  ( name-a name-u -- decl | 0 )
    _PL-DECLS @
    BEGIN DUP WHILE
        >R 2DUP R@ _PD-NAME STR-STR= IF 2DROP R> EXIT THEN
        R> _PD.NEXT @
    REPEAT
    NIP NIP ;

\ A folder is "/" or names joined and led by single slashes, none of
\ them `.` or `..`: the path the folder's entry has on its volume.
VARIABLE _PLV-START

: _PL-FOLDER-NAME?  ( a u -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    DUP 1 = IF DROP C@ [CHAR] . <> EXIT THEN
    DUP 2 = IF
        DROP DUP C@ [CHAR] . = SWAP 1+ C@ [CHAR] . = AND 0= EXIT
    THEN
    2DROP -1 ;

: _PL-FOLDER-PATH?  ( a u -- flag )
    OVER C@ [CHAR] / <> IF 2DROP 0 EXIT THEN
    DUP 1 = IF 2DROP -1 EXIT THEN
    1 _PLV-START !
    DUP 1 DO
        OVER I + C@ [CHAR] / = IF
            OVER _PLV-START @ + I _PLV-START @ - _PL-FOLDER-NAME? 0= IF
                2DROP 0 UNLOOP EXIT
            THEN
            I 1+ _PLV-START !
        THEN
    LOOP
    SWAP _PLV-START @ + SWAP _PLV-START @ - _PL-FOLDER-NAME? ;

VARIABLE _PDC-NA   VARIABLE _PDC-NU
VARIABLE _PDC-FA   VARIABLE _PDC-FU
VARIABLE _PDC-ACCESS
VARIABLE _PDC-VOL
VARIABLE _PDC-D

: _PL-ACCESS?  ( access -- flag )
    DUP PLACE-READ-ONLY = SWAP PLACE-WRITABLE = OR ;

\ PLACES-DECLARE ( name-a name-u folder-a folder-u access volume -- decl ior )
\   Declare the place NAME: FOLDER, the folder's own path from the
\   volume's root, with ACCESS.  The volume need not be attached yet.
: PLACES-DECLARE  ( name-a name-u folder-a folder-u access volume -- decl ior )
    _PDC-VOL ! _PDC-ACCESS ! _PDC-FU ! _PDC-FA ! _PDC-NU ! _PDC-NA !
    _PDC-VOL @ 0= IF 0 VFS-E-INVALID EXIT THEN
    _PDC-NA @ _PDC-NU @ PLACE-NAME-VALID? 0= IF 0 VFS-E-INVALID EXIT THEN
    _PDC-ACCESS @ _PL-ACCESS? 0= IF 0 VFS-E-INVALID EXIT THEN
    _PDC-FA @ 0= _PDC-FU @ 1 < OR IF 0 VFS-E-INVALID EXIT THEN
    _PDC-FU @ VFS-PATH-MAX > IF 0 VFS-E-NAMETOOLONG EXIT THEN
    _PDC-FA @ _PDC-FU @ _PL-FOLDER-PATH? 0= IF 0 VFS-E-INVALID EXIT THEN
    _PDC-NA @ _PDC-NU @ _PL-DECL-FIND IF 0 VFS-E-EXISTS EXIT THEN
    64 _PDC-NU @ + _PDC-FU @ + ALLOCATE IF DROP 0 VFS-E-NOMEM EXIT THEN
    _PDC-D !
    0 _PDC-D @ _PD.NEXT !
    _PDC-VOL @ _PDC-D @ _PD.VOLUME !
    _PDC-ACCESS @ _PDC-D @ _PD.ACCESS !
    0 _PDC-D @ _PD.REQUIRED !
    0 _PDC-D @ _PD.LABEL-A !  0 _PDC-D @ _PD.LABEL-U !
    _PDC-NU @ _PDC-D @ _PD.NAME-U !
    _PDC-FU @ _PDC-D @ _PD.FOLDER-U !
    _PDC-NA @ _PDC-D @ _PD.NAME _PDC-NU @ CMOVE
    _PDC-FA @ _PDC-D @ _PD.NAME _PDC-NU @ + _PDC-FU @ CMOVE
    _PL-DECL-LAST @ ?DUP IF
        _PDC-D @ SWAP _PD.NEXT !
    ELSE
        _PDC-D @ _PL-DECLS !
    THEN
    _PDC-D @ _PL-DECL-LAST !
    _PL-CHANGED
    _PDC-D @ 0 ;

\ PLACE-LABEL! ( label-a label-u decl -- ior )
\   What a person reads for the place.  Without one it is the name.
: PLACE-LABEL!  ( label-a label-u decl -- ior )
    DUP 0= IF DROP 2DROP VFS-E-INVALID EXIT THEN
    >R
    OVER 0= OVER 1 < OR IF 2DROP R> DROP VFS-E-INVALID EXIT THEN
    DUP ALLOCATE IF DROP 2DROP R> DROP VFS-E-NOMEM EXIT THEN
                                                ( label-a label-u copy )
    R@ _PD.LABEL-A @ ?DUP IF FREE THEN
    DUP R@ _PD.LABEL-A !
    OVER R> _PD.LABEL-U !
    SWAP CMOVE
    _PL-CHANGED 0 ;

\ PLACE-REQUIRED! ( flag decl -- )
\   Whether PLACES-CHECK reports the place when it is unavailable.
: PLACE-REQUIRED!  ( flag decl -- )
    DUP 0= IF 2DROP EXIT THEN
    SWAP 0<> SWAP _PD.REQUIRED ! ;

\ _PD-ROOT? ( decl -- inode ior )
\   The place's folder as it is now.  The status is VFS-E-NOVOLUME while
\   the volume is missing, the recorded reason when its mount was
\   refused, and the resolver's answer when the folder is absent.
: _PD-ROOT?  ( decl -- inode ior )
    DUP _PD.VOLUME @ _PV.VFS @ ?DUP 0= IF
        _PD.VOLUME @ _PV.REFUSAL @ ?DUP 0= IF VFS-E-NOVOLUME THEN
        0 SWAP EXIT
    THEN                                        ( decl vfs )
    >R _PD-FOLDER R> VFS-RESOLVE?               ( inode ior )
    DUP IF EXIT THEN DROP
    DUP IN.TYPE @ VFS-T-DIR <> IF DROP 0 VFS-E-NOTDIR EXIT THEN
    0 ;

\ PLACES-CHECK ( -- decl ior )
\   The first required place that is unavailable, with its status, or
\   0 0 when every required place is usable.
: PLACES-CHECK  ( -- decl ior )
    _PL-DECLS @
    BEGIN DUP WHILE
        DUP _PD.REQUIRED @ IF
            DUP _PD-ROOT? NIP ?DUP IF EXIT THEN
        THEN
        _PD.NEXT @
    REPEAT
    0 ;

: PDECL-NAME  ( decl -- a u )  _PD-NAME ;

\ =====================================================================
\  Sets
\ =====================================================================

: PLSET-NEW  ( -- set ior )
    _PS-SIZE ALLOCATE IF DROP 0 VFS-E-NOMEM EXIT THEN
    DUP _PS-SIZE 0 FILL
    _PLSET-MAGIC OVER _PS.MAGIC !
    0 ;

: PLACES-DEFAULT   ( -- set | 0 )  _PL-DEFAULT @ ;
: PLACES-DEFAULT!  ( set -- )
    DUP IF DUP _PLSET? 0= IF DROP EXIT THEN THEN
    _PL-DEFAULT ! ;

: PLSET-FREE  ( set -- )
    DUP _PLSET? 0= IF DROP EXIT THEN
    DUP _PL-DEFAULT @ = IF 0 _PL-DEFAULT ! THEN
    DUP _PS.FIRST @
    BEGIN ?DUP WHILE
        DUP _PG.NEXT @ SWAP
        0 OVER _PG.MAGIC !  FREE
    REPEAT
    0 OVER _PS.MAGIC !  FREE ;

: _PLSET-CHANGED  ( set -- )  1 SWAP _PS.CHANGES +! ;

VARIABLE _PGR-SET
VARIABLE _PGR-DECL
VARIABLE _PGR-ACCESS

\ PLSET-GRANT ( access decl set -- place ior )
\   Add the declared place to the set, after its other places, with
\   ACCESS.  An access wider than the declaration's answers
\   VFS-E-READONLY, and a place the set already has, VFS-E-EXISTS.
: PLSET-GRANT  ( access decl set -- place ior )
    _PGR-SET ! _PGR-DECL ! _PGR-ACCESS !
    _PGR-SET @ _PLSET? 0= _PGR-DECL @ 0= OR IF 0 VFS-E-INVALID EXIT THEN
    _PGR-ACCESS @ _PL-ACCESS? 0= IF 0 VFS-E-INVALID EXIT THEN
    _PGR-ACCESS @ PLACE-WRITABLE =
    _PGR-DECL @ _PD.ACCESS @ PLACE-READ-ONLY = AND IF
        0 VFS-E-READONLY EXIT
    THEN
    _PGR-SET @ _PS.FIRST @
    BEGIN ?DUP WHILE
        DUP _PG.DECL @ _PGR-DECL @ = IF DROP 0 VFS-E-EXISTS EXIT THEN
        _PG.NEXT @
    REPEAT
    _PG-SIZE ALLOCATE IF DROP 0 VFS-E-NOMEM EXIT THEN
    _PLACE-MAGIC OVER _PG.MAGIC !
    0 OVER _PG.NEXT !
    _PGR-SET @ OVER _PG.SET !
    _PGR-DECL @ OVER _PG.DECL !
    _PGR-ACCESS @ OVER _PG.ACCESS !             ( place )
    _PGR-SET @ _PS.FIRST @ ?DUP IF
        BEGIN DUP _PG.NEXT @ ?DUP WHILE NIP REPEAT
        OVER SWAP _PG.NEXT !
    ELSE
        DUP _PGR-SET @ _PS.FIRST !
    THEN
    _PGR-SET @ _PLSET-CHANGED
    0 ;

: PLSET-FIRST   ( set -- place | 0 )  _PS.FIRST @ ;
: PLSET-HOME    ( set -- place | 0 )  _PS.HOME @ ;
: PLSET-ORIGIN  ( set -- place | 0 )  _PS.ORIGIN @ ;
: PLSET-DOCUMENTS  ( set -- place | 0 )  _PS.DOCUMENTS @ ;
: PLACE-NEXT    ( place -- place | 0 )  _PG.NEXT @ ;

\ PLSET-MEMBER? ( x set -- flag )
\   Whether X is one of the set's places.  X may be any cell: it is
\   compared and never read.
: PLSET-MEMBER?  ( x set -- flag )
    _PS.FIRST @
    BEGIN DUP WHILE
        2DUP = IF 2DROP -1 EXIT THEN
        _PG.NEXT @
    REPEAT
    NIP ;

\ PLSET-HOME!, PLSET-ORIGIN! and PLSET-DOCUMENTS! ( place set -- )
\   Mark one of the set's places, or none with 0: the home, where the
\   holder keeps its own records; the origin, where its shipped files are
\   read from; and the documents place, where a person's documents go.
: PLSET-HOME!  ( place set -- )
    OVER IF 2DUP PLSET-MEMBER? 0= IF 2DROP EXIT THEN THEN
    TUCK _PS.HOME ! _PLSET-CHANGED ;
: PLSET-ORIGIN!  ( place set -- )
    OVER IF 2DUP PLSET-MEMBER? 0= IF 2DROP EXIT THEN THEN
    TUCK _PS.ORIGIN ! _PLSET-CHANGED ;
: PLSET-DOCUMENTS!  ( place set -- )
    OVER IF 2DUP PLSET-MEMBER? 0= IF 2DROP EXIT THEN THEN
    TUCK _PS.DOCUMENTS ! _PLSET-CHANGED ;

\ PLSET-READ-ONLY! ( set -- )
\   Narrow every place of the set to read-only, as recovery does.
: PLSET-READ-ONLY!  ( set -- )
    DUP _PS.FIRST @
    BEGIN ?DUP WHILE
        PLACE-READ-ONLY OVER _PG.ACCESS !
        _PG.NEXT @
    REPEAT
    _PLSET-CHANGED ;

\ PLSET-REVISION ( set -- n )
\   Moves when the set's membership, marks or access change and when any
\   volume or declaration changes, so a list of places knows to redraw.
: PLSET-REVISION  ( set -- n )  _PS.CHANGES @ _PL-CHANGES @ + ;

: PLACE-NAME  ( place -- a u )  _PG.DECL @ _PD-NAME ;

: PLACE-LABEL  ( place -- a u )
    _PG.DECL @ DUP _PD.LABEL-A @ ?DUP IF
        SWAP _PD.LABEL-U @
    ELSE
        _PD-NAME
    THEN ;

: PLSET-FIND  ( name-a name-u set -- place | 0 )
    _PS.FIRST @
    BEGIN DUP WHILE
        >R 2DUP R@ PLACE-NAME STR-STR= IF 2DROP R> EXIT THEN
        R> _PG.NEXT @
    REPEAT
    NIP NIP ;

\ =====================================================================
\  A place's state
\ =====================================================================

: PLACE-STATUS  ( place -- ior )
    DUP _PLACE? 0= IF DROP VFS-E-INVALID EXIT THEN
    _PG.DECL @ _PD-ROOT? NIP ;

\ PLACE-WHY ( place -- a u )
\   Why the place is unavailable, in a few words a person can read; empty
\   for a usable place.
: PLACE-WHY  ( place -- a u )
    DUP _PLACE? 0= IF DROP 0 0 EXIT THEN
    _PG.DECL @ DUP _PD.VOLUME @ DUP _PV.VFS @ 0= IF
        NIP _PV.REFUSAL @ IF S" mount refused" ELSE S" volume missing" THEN
        EXIT
    THEN
    DROP _PD-ROOT? NIP IF S" folder missing" ELSE 0 0 THEN ;

: PLACE-VFS  ( place -- vfs | 0 )
    DUP _PLACE? 0= IF DROP 0 EXIT THEN
    _PG.DECL @ _PD.VOLUME @ _PV.VFS @ ;

\ PLACE-WRITABLE? ( place -- flag )
\   Whether the holder may change the place: its grant is writable and
\   its volume is not mounted read-only.
: PLACE-WRITABLE?  ( place -- flag )
    DUP _PLACE? 0= IF DROP 0 EXIT THEN
    DUP _PG.ACCESS @ PLACE-WRITABLE <> IF DROP 0 EXIT THEN
    PLACE-VFS ?DUP IF V.FLAGS @ VFS-F-RO AND 0= ELSE -1 THEN ;

\ PLACE-ROOT ( place -- inode | 0 )
\   The place's folder, valid until the next VFS operation.
: PLACE-ROOT  ( place -- inode | 0 )
    DUP _PLACE? 0= IF DROP 0 EXIT THEN
    _PG.DECL @ _PD-ROOT? DROP ;

\ PLACE-NAME-LIMIT ( place -- n )
\   The longest entry name the place's volume takes (VFS-NAME-LIMIT), and
\   the VFS's own limit while the volume is not attached.
: PLACE-NAME-LIMIT  ( place -- n )
    PLACE-VFS ?DUP IF VFS-NAME-LIMIT ELSE VFS-NAME-MAX THEN ;

\ =====================================================================
\  Paths inside a place
\ =====================================================================
\  The words below run inside one VFS-TRANSACTION each, so the state
\  they share is theirs for the length of a call.

VARIABLE _PLB-P        \ the place
VARIABLE _PLB-V        \ its instance
VARIABLE _PLB-ROOT     \ its folder

\ _PL-ENTER ( place -- ior )
\   Note the place, its instance and its folder; its status otherwise.
: _PL-ENTER  ( place -- ior )
    DUP _PLACE? 0= IF DROP VFS-E-INVALID EXIT THEN
    DUP _PLB-P !
    _PG.DECL @ _PD-ROOT? ?DUP IF NIP EXIT THEN
    _PLB-ROOT !
    _PLB-P @ PLACE-VFS _PLB-V !
    0 ;

\ The same, for a word that changes the place.
: _PL-ENTER-WRITE  ( place -- ior )
    DUP _PL-ENTER ?DUP IF NIP EXIT THEN
    PLACE-WRITABLE? IF 0 ELSE VFS-E-READONLY THEN ;

\ _PL-IN ( i*x dir xt -- j*x )
\   Run XT with DIR as the volume's current directory, which is restored
\   whether XT returns or throws.
: _PL-IN  ( i*x dir xt -- j*x )
    SWAP _PLB-V @ V.CWD @ >R
    _PLB-V @ V.CWD !
    CATCH
    R> _PLB-V @ V.CWD !
    ?DUP IF THROW THEN ;

\ The number of names in a folder path, and of steps from an entry up to
\ its volume's root.
: _PL-NAMES  ( a u -- n )
    0 -ROT
    BEGIN DUP 0> WHILE
        OVER C@ [CHAR] / = IF
            1 /STRING
        ELSE
            ROT 1+ -ROT
            BEGIN
                DUP 0> IF OVER C@ [CHAR] / <> ELSE 0 THEN
            WHILE
                1 /STRING
            REPEAT
        THEN
    REPEAT
    2DROP ;

: _PL-DEPTH  ( inode -- n )
    0 SWAP BEGIN IN.PARENT @ ?DUP WHILE SWAP 1+ SWAP REPEAT ;

VARIABLE _PLF-A
VARIABLE _PLF-END

\ _PL-IS-FOLDER? ( dentry folder-a folder-u -- flag )
\   The entry's path from its volume's root is the folder path, name for
\   name from the last one up.
: _PL-IS-FOLDER?  ( dentry folder-a folder-u -- flag )
    OVER + _PLF-END ! _PLF-A !
    BEGIN
        BEGIN
            _PLF-END @ _PLF-A @ > IF
                _PLF-END @ 1- C@ [CHAR] / =
            ELSE 0 THEN
        WHILE
            -1 _PLF-END +!
        REPEAT
        _PLF-END @ _PLF-A @ >
    WHILE
        _PLF-END @
        BEGIN
            DUP _PLF-A @ > IF DUP 1- C@ [CHAR] / <> ELSE 0 THEN
        WHILE
            1-
        REPEAT                                      ( dentry start )
        OVER IN.PARENT @ 0= IF 2DROP 0 EXIT THEN
        DUP _PLF-END @ OVER -                       ( dentry start start len )
        3 PICK IN.NAME @ _VFS-STR-GET STR-STR= 0= IF 2DROP 0 EXIT THEN
        _PLF-END !
        IN.PARENT @
    REPEAT
    IN.PARENT @ 0= ;

\ _PL-ROOT-OF ( inode decl -- root | 0 )
\   The declared folder as a live entry's ancestor, or the entry itself,
\   found on the entry's own parent chain; 0 when the entry is not in
\   the folder.  Nothing is looked up, so the entry stays as it is.
: _PL-ROOT-OF  ( inode decl -- root | 0 )
    >R
    DUP D.OWNER @ R@ _PD.VOLUME @ _PV.VFS @ <> IF DROP R> DROP 0 EXIT THEN
    DUP _PL-DEPTH R@ _PD-FOLDER _PL-NAMES -         ( inode steps )
    DUP 0< IF 2DROP R> DROP 0 EXIT THEN
    0 ?DO IN.PARENT @ LOOP                          ( candidate )
    DUP R> _PD-FOLDER _PL-IS-FOLDER? 0= IF DROP 0 THEN ;

\ _PL-UNDER? ( inode root -- flag )
\   ROOT is INODE or one of its parents.
: _PL-UNDER?  ( inode root -- flag )
    SWAP
    BEGIN DUP WHILE
        2DUP = IF 2DROP -1 EXIT THEN
        IN.PARENT @
    REPEAT
    NIP ;

\ A path's leading slashes name the place's folder, where it starts
\ anyway.
: _PL-TRIM  ( a u -- a' u' )
    BEGIN
        DUP 0> IF OVER C@ [CHAR] / = ELSE 0 THEN
    WHILE
        1 /STRING
    REPEAT ;

VARIABLE _PLK-A
VARIABLE _PLK-U
VARIABLE _PLK-POLICY

: _PL-WALK-BODY  ( -- inode ior )
    _PLK-A @ _PLK-U @ _PLK-POLICY @ _PLB-V @ VFS-RESOLVE-POLICY? ;

\ _PL-WALK ( a u policy -- inode ior )
\   The entry the path names from the place's folder.  An entry that does
\   not lie under the folder answers VFS-E-XDEV.
: _PL-WALK  ( a u policy -- inode ior )
    _PLK-POLICY !  _PL-TRIM _PLK-U ! _PLK-A !
    _PLK-U @ 0= IF _PLB-ROOT @ 0 EXIT THEN
    _PLB-ROOT @ ['] _PL-WALK-BODY _PL-IN
    DUP IF EXIT THEN DROP
    DUP _PLB-ROOT @ _PL-UNDER? 0= IF DROP 0 VFS-E-XDEV EXIT THEN
    0 ;

: _PL-RESOLVE  ( path-a path-u place -- inode ior )
    _PL-ENTER ?DUP IF >R 2DROP 0 R> EXIT THEN
    VFS-RP-FOLLOW-FINAL _PL-WALK ;

\ PLACE-RESOLVE ( path-a path-u place -- inode ior )
\   The entry a path names, following a final symbolic link.  The entry
\   is valid until the next VFS operation.
: PLACE-RESOLVE  ( path-a path-u place -- inode ior )
    ['] _PL-RESOLVE VFS-TRANSACTION ;

: _PL-HOLDS?  ( inode place -- flag )
    OVER 0= OVER _PLACE? 0= OR IF 2DROP 0 EXIT THEN
    _PG.DECL @ _PL-ROOT-OF 0<> ;

\ PLACE-HOLDS? ( inode place -- flag )
\   Whether a live entry lies in the place.  The entry is not disturbed.
: PLACE-HOLDS?  ( inode place -- flag )
    ['] _PL-HOLDS? VFS-TRANSACTION ;

VARIABLE _PLW-BUF
VARIABLE _PLW-CAP
VARIABLE _PLW-LEN
VARIABLE _PLW-STOP
VARIABLE _PLW-IN
VARIABLE _PLW-AT

\ _PL-PATH ( inode stop buf cap -- len ior )
\   The path from STOP, which is not written, down to INODE: "/a/b", or
\   "/" when INODE is STOP.  It is written whole or not at all, and has
\   no depth limit.  VFS-E-XDEV when STOP is not among INODE's parents.
: _PL-PATH  ( inode stop buf cap -- len ior )
    _PLW-CAP ! _PLW-BUF ! _PLW-STOP ! _PLW-IN !
    0 _PLW-LEN !
    _PLW-IN @
    BEGIN
        DUP 0<> OVER _PLW-STOP @ <> AND
    WHILE
        DUP IN.NAME @ _VFS-STR-GET NIP 1+ _PLW-LEN +!
        IN.PARENT @
    REPEAT
    _PLW-STOP @ <> IF 0 VFS-E-XDEV EXIT THEN
    _PLW-LEN @ 0= IF
        _PLW-CAP @ 1 < IF 0 VFS-E-NAMETOOLONG EXIT THEN
        [CHAR] / _PLW-BUF @ C!  1 0 EXIT
    THEN
    _PLW-LEN @ _PLW-CAP @ > IF 0 VFS-E-NAMETOOLONG EXIT THEN
    _PLW-LEN @ _PLW-AT !
    _PLW-IN @
    BEGIN
        DUP _PLW-STOP @ <>
    WHILE
        DUP IN.NAME @ _VFS-STR-GET              ( inode a u )
        DUP NEGATE _PLW-AT +!
        _PLW-BUF @ _PLW-AT @ + SWAP CMOVE
        -1 _PLW-AT +!
        [CHAR] / _PLW-BUF @ _PLW-AT @ + C!
        IN.PARENT @
    REPEAT
    DROP
    _PLW-LEN @ 0 ;

VARIABLE _PLP-BUF
VARIABLE _PLP-CAP

: _PL-PLACE-PATH  ( inode place buf cap -- len ior )
    _PLP-CAP ! _PLP-BUF !
    OVER 0= OVER _PLACE? 0= OR IF 2DROP 0 VFS-E-INVALID EXIT THEN
    DUP PLACE-VFS 0= IF NIP PLACE-STATUS 0 SWAP EXIT THEN
    OVER SWAP _PG.DECL @ _PL-ROOT-OF                ( inode root|0 )
    DUP 0= IF 2DROP 0 VFS-E-XDEV EXIT THEN
    _PLP-BUF @ _PLP-CAP @ _PL-PATH ;

\ PLACE-PATH ( inode place buf cap -- len ior )
\   A live entry's path in the place, "/" for the place's folder, and
\   VFS-E-XDEV for an entry that is not in the place.  The entry is not
\   disturbed.
: PLACE-PATH  ( inode place buf cap -- len ior )
    ['] _PL-PLACE-PATH VFS-TRANSACTION ;

\ =====================================================================
\  Opening and changing
\ =====================================================================

VARIABLE _PLO-A
VARIABLE _PLO-U
VARIABLE _PLO-FLAGS

: _PL-OPEN-BODY  ( -- fd ior )
    _PLO-A @ _PLO-U @ _PLO-FLAGS @ _PLB-V @ VFS-OPEN? ;

: _PL-OPEN  ( path-a path-u flags place -- fd ior )
    OVER _PLO-FLAGS !
    SWAP VFS-FF-WRITE VFS-FF-APPEND OR AND IF
        _PL-ENTER-WRITE
    ELSE
        _PL-ENTER
    THEN
    ?DUP IF >R 2DROP 0 R> EXIT THEN
    _PL-TRIM _PLO-U ! _PLO-A !
    _PLO-A @ _PLO-U @ VFS-RP-FOLLOW-FINAL _PL-WALK
    ?DUP IF EXIT THEN DROP
    _PLB-ROOT @ ['] _PL-OPEN-BODY _PL-IN ;

\ PLACE-OPEN ( path-a path-u flags place -- fd ior )
\   Open the file a path names, with VFS-FF-* flags.  Writing needs a
\   writable place.
: PLACE-OPEN  ( path-a path-u flags place -- fd ior )
    ['] _PL-OPEN VFS-TRANSACTION ;

VARIABLE _PLS-A    VARIABLE _PLS-U      \ a path's folder part
VARIABLE _PLS-NA   VARIABLE _PLS-NU     \ and its final name

\ _PL-SPLIT ( a u -- )
\   Split a path at its last slash.  A path with no slash is a name in
\   the place's folder.
: _PL-SPLIT  ( a u -- )
    _PL-TRIM
    OVER _PLS-A !  0 _PLS-U !
    2DUP _PLS-NU ! _PLS-NA !
    DUP 0 ?DO
        OVER I + C@ [CHAR] / = IF
            I _PLS-U !
            OVER I + 1+ _PLS-NA !
            DUP I - 1- _PLS-NU !
        THEN
    LOOP
    2DROP ;

\ _PL-PARENT ( -- dir ior )   The split path's folder, in the place.
: _PL-PARENT  ( -- dir ior )
    _PLS-A @ _PLS-U @ VFS-RP-FOLLOW-FINAL _PL-WALK
    ?DUP IF EXIT THEN
    DUP IN.TYPE @ VFS-T-DIR <> IF DROP 0 VFS-E-NOTDIR EXIT THEN
    0 ;

: _PL-MKFILE-BODY  ( -- inode ior )
    _PLS-NA @ _PLS-NU @ _PLB-V @ VFS-MKFILE? ;
: _PL-MKDIR-BODY  ( -- ior )
    _PLS-NA @ _PLS-NU @ _PLB-V @ VFS-MKDIR ;

: _PL-CREATE  ( path-a path-u place -- inode ior )
    _PL-ENTER-WRITE ?DUP IF >R 2DROP 0 R> EXIT THEN
    _PL-SPLIT _PL-PARENT ?DUP IF EXIT THEN
    ['] _PL-MKFILE-BODY _PL-IN ;

\ PLACE-CREATE ( path-a path-u place -- inode ior )
\   Create an empty file.  Its folder must exist and its name must not.
: PLACE-CREATE  ( path-a path-u place -- inode ior )
    ['] _PL-CREATE VFS-TRANSACTION ;

: _PL-MKDIR  ( path-a path-u place -- ior )
    _PL-ENTER-WRITE ?DUP IF >R 2DROP R> EXIT THEN
    _PL-SPLIT _PL-PARENT ?DUP IF NIP EXIT THEN
    ['] _PL-MKDIR-BODY _PL-IN ;

\ PLACE-MKDIR ( path-a path-u place -- ior )   Create a folder.
: PLACE-MKDIR  ( path-a path-u place -- ior )
    ['] _PL-MKDIR VFS-TRANSACTION ;

VARIABLE _PLR-IN

: _PL-RM-BODY  ( -- ior )
    _PLR-IN @ IN.NAME @ _VFS-STR-GET _PLB-V @ VFS-RM ;

: _PL-RM  ( path-a path-u place -- ior )
    _PL-ENTER-WRITE ?DUP IF >R 2DROP R> EXIT THEN
    VFS-RP-NOFOLLOW-FINAL _PL-WALK ?DUP IF NIP EXIT THEN
    _PLR-IN !
    _PLR-IN @ _PLB-ROOT @ = IF VFS-E-INVALID EXIT THEN
    \ The entry must not be the directory this call restores afterwards.
    _PLR-IN @ _PLB-V @ V.CWD @ = IF VFS-E-BUSY EXIT THEN
    _PLR-IN @ IN.PARENT @ ['] _PL-RM-BODY _PL-IN ;

\ PLACE-RM ( path-a path-u place -- ior )
\   Remove a file, an empty folder, or a symbolic link itself.  The
\   place's own folder stays.
: PLACE-RM  ( path-a path-u place -- ior )
    ['] _PL-RM VFS-TRANSACTION ;

VARIABLE _PLN-P

: _PL-RENAME  ( new-a new-u inode place -- ior )
    DUP _PLN-P !
    _PLACE? 0= IF DROP 2DROP VFS-E-INVALID EXIT THEN
    DUP 0= IF DROP 2DROP VFS-E-INVALID EXIT THEN
    _PLN-P @ PLACE-VFS 0= IF DROP 2DROP _PLN-P @ PLACE-STATUS EXIT THEN
    _PLN-P @ PLACE-WRITABLE? 0= IF DROP 2DROP VFS-E-READONLY EXIT THEN
    DUP _PLN-P @ _PG.DECL @ _PL-ROOT-OF             ( new-a new-u inode root|0 )
    DUP 0= IF 2DROP 2DROP VFS-E-XDEV EXIT THEN
    OVER = IF DROP 2DROP VFS-E-INVALID EXIT THEN
    _PLN-P @ PLACE-VFS VFS-RENAME ;

\ PLACE-RENAME ( new-a new-u inode place -- ior )
\   Give a live entry of the place another name in its folder.  An
\   existing name is refused.  The entry is found in the place by its own
\   parent chain, so it is not disturbed before it is renamed.
: PLACE-RENAME  ( new-a new-u inode place -- ior )
    ['] _PL-RENAME VFS-TRANSACTION ;

\ PLACE-SYNC ( place -- ior )
\   Make the place's changes durable.  A holder that cannot change the
\   place has nothing to make durable.
: PLACE-SYNC  ( place -- ior )
    DUP PLACE-STATUS ?DUP IF NIP EXIT THEN
    DUP PLACE-WRITABLE? 0= IF DROP 0 EXIT THEN
    PLACE-VFS VFS-SYNC ;

\ =====================================================================
\  Binding a path for a library that keeps its own descriptor
\ =====================================================================

VARIABLE _PLD-BUF
VARIABLE _PLD-CAP
VARIABLE _PLD-A
VARIABLE _PLD-U
VARIABLE _PLD-LEN

: _PL-BOUND  ( len ior -- vfs len ior )
    ?DUP IF NIP 0 0 ROT EXIT THEN
    _PLB-V @ SWAP 0 ;

\ The volume path of a name that does not exist yet, in a folder of the
\ place that does.
: _PL-BIND-NEW  ( -- vfs len ior )
    _PLD-A @ _PLD-U @ VFS-RP-NOFOLLOW-FINAL _PL-WALK NIP 0= IF
        \ The name exists and led nowhere: a symbolic link without its
        \ target.  Writing through it could leave the place.
        0 0 VFS-E-INVALID EXIT
    THEN
    _PLD-A @ _PLD-U @ _PL-SPLIT
    _PLS-NA @ _PLS-NU @ _VFS-VALID-NAME? 0= IF 0 0 VFS-E-INVALID EXIT THEN
    _PL-PARENT ?DUP IF NIP 0 0 ROT EXIT THEN
    _PLB-V @ V.ROOT @ _PLD-BUF @ _PLD-CAP @ _PL-PATH
    ?DUP IF NIP 0 0 ROT EXIT THEN
    DUP 1 = IF DROP 0 THEN _PLD-LEN !          \ the root's "/" is rewritten
    _PLD-LEN @ 1+ _PLS-NU @ + _PLD-CAP @ > IF 0 0 VFS-E-NAMETOOLONG EXIT THEN
    [CHAR] / _PLD-BUF @ _PLD-LEN @ + C!
    _PLS-NA @ _PLD-BUF @ _PLD-LEN @ + 1+ _PLS-NU @ CMOVE
    _PLB-V @ _PLD-LEN @ 1+ _PLS-NU @ + 0 ;

: _PL-BIND-ENTERED  ( path-a path-u buf cap -- vfs len ior )
    _PLD-CAP ! _PLD-BUF ! _PLD-U ! _PLD-A !
    _PLD-A @ _PLD-U @ VFS-RP-FOLLOW-FINAL _PL-WALK
    DUP 0= IF
        DROP _PLB-V @ V.ROOT @ _PLD-BUF @ _PLD-CAP @ _PL-PATH _PL-BOUND
        EXIT
    THEN
    NIP DUP VFS-IOR-REASON VFS-R-NOENT <> IF 0 0 ROT EXIT THEN
    DROP _PL-BIND-NEW ;

VARIABLE _PLD-CAP0
VARIABLE _PLD-BUF0

: _PL-BIND  ( path-a path-u place buf cap -- vfs len ior )
    _PLD-CAP0 ! _PLD-BUF0 !
    _PL-ENTER ?DUP IF >R 2DROP 0 0 R> EXIT THEN
    _PLD-BUF0 @ _PLD-CAP0 @ _PL-BIND-ENTERED ;

: _PL-BIND-WRITE  ( path-a path-u place buf cap -- vfs len ior )
    _PLD-CAP0 ! _PLD-BUF0 !
    _PL-ENTER-WRITE ?DUP IF >R 2DROP 0 0 R> EXIT THEN
    _PLD-BUF0 @ _PLD-CAP0 @ _PL-BIND-ENTERED ;

\ PLACE-BIND ( path-a path-u place buf cap -- vfs len ior )
\   The instance and, in BUF, the volume path of an entry of the place,
\   or of a new name in an existing folder of the place.  The path has
\   no `..` and no symbolic link in it.  It is for a library that reads
\   through a descriptor of its own.
: PLACE-BIND  ( path-a path-u place buf cap -- vfs len ior )
    ['] _PL-BIND VFS-TRANSACTION ;

\ PLACE-BIND-WRITE ( path-a path-u place buf cap -- vfs len ior )
\   The same for a library that will write there, which a read-only place
\   refuses.
: PLACE-BIND-WRITE  ( path-a path-u place buf cap -- vfs len ior )
    ['] _PL-BIND-WRITE VFS-TRANSACTION ;
