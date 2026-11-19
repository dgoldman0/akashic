\ =====================================================================
\  held-files.f - which file each hosted document is kept in
\ =====================================================================
\  Megapad-64 / KDOS Forth      Prefix: HELD- / _HELD- / _HE- / _HH-
\
\  A document that one applet owns and others edit through Desk lives in
\  a file of a place.  Desk records here, for each document it hosts,
\  the place and path of that file and the service that lends the
\  document, from what the owner says of its own file, and lends the
\  table to the applets it runs under the service id org.akashic.fs.held.
\  An applet about to open or write a file by its path asks the table
\  first: a held file is reached through the owner's service, never
\  written directly (docs/utils/fs/places.md, "Who may write a file").
\
\  A place is recorded by its declared name, which is the same in every
\  set it is granted to, and a path as it reads from the folder that
\  declaration names (PLACE-DECLARED-PATH), so the table answers alike for
\  a holder whose place is a folder of its own inside that folder and for
\  one over the folder itself.  Callers give and take paths as the PLACE-
\  words do, from their own place's folder with its slash.  Entries are
\  heap records, so their number follows need.
\
\  Public API:
\    HELD-SIZE                                   bytes of a table
\    HELD-INIT    ( table -- )                    make it empty
\    HELD-HOLD    ( path-a path-u place svc-a svc-u table -- ior )
\    HELD-RELEASE ( svc-a svc-u table -- )        forget a service's files
\    HELD-CLEAR   ( table -- )                    forget every file
\    HELD-HOLDER  ( path-a path-u place table -- svc-a svc-u | 0 0 )
\    HELD-FILE    ( svc-a svc-u table -- path-a path-u name-a name-u
\                                             | 0 0 0 0 )
\ =====================================================================

PROVIDED akashic-held-files

REQUIRE places.f
REQUIRE ../string.f

\ A table is one cell: its first entry.
8 CONSTANT HELD-SIZE

\ An entry: the next entry, the lengths of its place's name, its path and
\ its service id, then the three strings end to end.
: _HE.NEXT    ( entry -- a ) ;
: _HE.NAME-U  ( entry -- a )  8 + ;
: _HE.PATH-U  ( entry -- a ) 16 + ;
: _HE.SVC-U   ( entry -- a ) 24 + ;
32 CONSTANT _HE-HEAD
: _HE-NAME$  ( entry -- a u )  DUP _HE-HEAD + SWAP _HE.NAME-U @ ;
: _HE-PATH$  ( entry -- a u )  DUP _HE-NAME$ + SWAP _HE.PATH-U @ ;
: _HE-SVC$   ( entry -- a u )  DUP _HE-PATH$ + SWAP _HE.SVC-U @ ;

: HELD-INIT  ( table -- )  0 SWAP ! ;

VARIABLE _HH-PA  VARIABLE _HH-PU  VARIABLE _HH-PLACE
VARIABLE _HH-SA  VARIABLE _HH-SU  VARIABLE _HH-TABLE  VARIABLE _HH-AT
CREATE _HH-PATH VFS-PATH-MAX ALLOT

: _HH-PUT  ( a u -- )  >R _HH-AT @ R@ CMOVE  R> _HH-AT +! ;

\ HELD-HOLD ( path-a path-u place svc-a svc-u table -- ior )
\   Record that the file at PATH in PLACE keeps the document the service
\   SVC lends.
: HELD-HOLD  ( path-a path-u place svc-a svc-u table -- ior )
    _HH-TABLE ! _HH-SU ! _HH-SA ! _HH-PLACE ! _HH-PU ! _HH-PA !
    _HH-PLACE @ 0= _HH-PU @ 0= OR _HH-SU @ 0= OR IF VFS-E-INVALID EXIT THEN
    _HH-PA @ _HH-PU @ _HH-PLACE @ _HH-PATH VFS-PATH-MAX PLACE-DECLARED-PATH
    ?DUP IF NIP EXIT THEN  _HH-PU !  _HH-PATH _HH-PA !
    _HH-PLACE @ PLACE-NAME NIP _HH-PU @ + _HH-SU @ + _HE-HEAD +
    ALLOCATE IF DROP VFS-E-NOMEM EXIT THEN          ( entry )
    _HH-PLACE @ PLACE-NAME NIP OVER _HE.NAME-U !
    _HH-PU @ OVER _HE.PATH-U !
    _HH-SU @ OVER _HE.SVC-U !
    DUP _HE-HEAD + _HH-AT !
    _HH-PLACE @ PLACE-NAME _HH-PUT
    _HH-PA @ _HH-PU @ _HH-PUT
    _HH-SA @ _HH-SU @ _HH-PUT
    _HH-TABLE @ @ OVER _HE.NEXT !
    _HH-TABLE @ !  0 ;

VARIABLE _HR-SA  VARIABLE _HR-SU

\ HELD-RELEASE ( svc-a svc-u table -- )   Forget the files of SVC.
: HELD-RELEASE  ( svc-a svc-u table -- )
    >R _HR-SU ! _HR-SA ! R>                          ( link )
    BEGIN DUP @ WHILE
        DUP @ _HE-SVC$ _HR-SA @ _HR-SU @ STR-STR= IF
            DUP DUP @ DUP _HE.NEXT @ ROT !  FREE
        ELSE
            @ _HE.NEXT
        THEN
    REPEAT
    DROP ;

\ HELD-CLEAR ( table -- )   Forget every file.
: HELD-CLEAR  ( table -- )
    DUP @ 0 ROT !
    BEGIN ?DUP WHILE DUP _HE.NEXT @ SWAP FREE REPEAT ;

VARIABLE _HD-PA  VARIABLE _HD-PU  VARIABLE _HD-PLACE
CREATE _HD-PATH VFS-PATH-MAX ALLOT

\ HELD-HOLDER ( path-a path-u place table -- svc-a svc-u | 0 0 )
\   The service whose document the file at PATH in PLACE keeps, or 0 0
\   for a file that keeps no hosted document.
: HELD-HOLDER  ( path-a path-u place table -- svc-a svc-u | 0 0 )
    >R _HD-PLACE ! _HD-PU ! _HD-PA ! R> @
    _HD-PLACE @ 0= IF DROP 0 0 EXIT THEN
    _HD-PA @ _HD-PU @ _HD-PLACE @ _HD-PATH VFS-PATH-MAX PLACE-DECLARED-PATH
    IF 2DROP 0 0 EXIT THEN  _HD-PU !  _HD-PATH _HD-PA !
    BEGIN DUP WHILE
        DUP _HE-PATH$ _HD-PA @ _HD-PU @ STR-STR= IF
            DUP _HE-NAME$ _HD-PLACE @ PLACE-NAME STR-STR= IF
                _HE-SVC$ EXIT
            THEN
        THEN
        _HE.NEXT @
    REPEAT
    DROP 0 0 ;

VARIABLE _HF-SA  VARIABLE _HF-SU

\ HELD-FILE ( svc-a svc-u table -- path-a path-u name-a name-u | 0 0 0 0 )
\   The file that keeps the document SVC lends: its path from the folder
\   its place's declaration names, and that place's name, which
\   PLSET-FIND-PATH turns into the place of any set that holds the file
\   and the path as it reads there.
: HELD-FILE  ( svc-a svc-u table -- path-a path-u name-a name-u | 0 0 0 0 )
    @ >R _HF-SU ! _HF-SA ! R>
    BEGIN DUP WHILE
        DUP _HE-SVC$ _HF-SA @ _HF-SU @ STR-STR= IF
            DUP _HE-PATH$ ROT _HE-NAME$ EXIT
        THEN
        _HE.NEXT @
    REPEAT
    DROP 0 0 0 0 ;
