\ =====================================================================
\ shell-model.f — Ordinary shell chrome, copied completed-frame model
\ =====================================================================
\ The caller builds an inactive bank, paints and hit-tests its entries,
\ then publishes the bank at its completed draw boundary. All strings are
\ copied into the bank. Offsets are relative to the bank, never pointers
\ into app descriptors, host slots or a catalog. A bank is immutable until
\ the caller next selects it for construction; observers copy synchronously.
\ Bounds are screen CELL coordinates. PANE content stays exactly where the
\ ordinary child paints; its outer rectangle may own existing right/bottom
\ divider cells. No title row or terminal-specific fields are introduced.

PROVIDED akashic-tui-shell-model
REQUIRE ../text/grapheme.f
REQUIRE ../utils/memory-span.f

CREATE _SHM-OWNED-START
VARIABLE _SHM-OWNED-LIMIT
0 _SHM-OWNED-LIMIT !

1 CONSTANT SHM-ABI
1 CONSTANT SHM-K-PANE
2 CONSTANT SHM-K-TASK
3 CONSTANT SHM-K-LAUNCHER
1 CONSTANT SHM-F-SELECTED
2 CONSTANT SHM-F-MINIMIZED
4 CONSTANT SHM-F-DISABLED
8 CONSTANT SHM-F-OVERLAY
16 CONSTANT SHM-F-ERROR
32 CONSTANT SHM-F-RUNNING
1 CONSTANT SHM-F-TASKBAR-HIDDEN
2 CONSTANT SHM-F-INPUT-BLOCKED

128 CONSTANT SHM-HEADER-SIZE
168 CONSTANT SHM-ENTRY-SIZE
: SHM.ABI          ( m -- a ) ;
: SHM.CAPACITY     ( m -- a ) 8 + ;
: SHM.ENTRY-LIMIT  ( m -- a ) 16 + ;
: SHM.COUNT        ( m -- a ) 24 + ;
: SHM.USED         ( m -- a ) 32 + ;
: SHM.OWNER-ID     ( m -- a ) 40 + ;
: SHM.OWNER-GEN    ( m -- a ) 48 + ;
: SHM.EPOCH        ( m -- a ) 56 + ;
: SHM.WIDTH        ( m -- a ) 64 + ;
: SHM.HEIGHT       ( m -- a ) 72 + ;
: SHM.FLAGS        ( m -- a ) 80 + ;
: SHM.DIVIDER-COL  ( m -- a ) 88 + ;
: SHM.END-COL      ( m -- a ) 96 + ;
: SHM.READY        ( m -- a ) 104 + ;

: SHME.KEY         ( e -- a ) ;
: SHME.KIND        ( e -- a ) 8 + ;
: SHME.FLAGS       ( e -- a ) 16 + ;
: SHME.ROW         ( e -- a ) 24 + ;
: SHME.COL         ( e -- a ) 32 + ;
: SHME.HEIGHT      ( e -- a ) 40 + ;
: SHME.WIDTH       ( e -- a ) 48 + ;
: SHME.CONTENT-ROW ( e -- a ) 56 + ;
: SHME.CONTENT-COL ( e -- a ) 64 + ;
: SHME.CONTENT-H   ( e -- a ) 72 + ;
: SHME.CONTENT-W   ( e -- a ) 80 + ;
: SHME.OWNER-ID    ( e -- a ) 88 + ;
: SHME.OWNER-GEN   ( e -- a ) 96 + ;
: SHME.IDENTITY    ( e -- a ) 104 + ;
: SHME.ACTION      ( e -- a ) 112 + ;
: SHME.LABEL-OFF   ( e -- a ) 120 + ;
: SHME.LABEL-U     ( e -- a ) 128 + ;
: SHME.TITLE-OFF   ( e -- a ) 136 + ;
: SHME.TITLE-U     ( e -- a ) 144 + ;
: SHME.ACTION-OFF  ( e -- a ) 152 + ;
: SHME.ACTION-U    ( e -- a ) 160 + ;

: SHM-ENTRY  ( index model -- entry )
    SHM-HEADER-SIZE + SWAP SHM-ENTRY-SIZE * + ;

\ Validate geometry and reject aliases of module scratch before storing any
\ input there. The caller still owns readable/writable memory for the span.
: SHM-STORAGE-DISJOINT? ( a u -- flag )
    DUP 0< IF 2DROP FALSE EXIT THEN
    DUP 0= IF 2DROP TRUE EXIT THEN
    OVER 0= IF 2DROP FALSE EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP FALSE EXIT THEN
    _SHM-OWNED-LIMIT @ _SHM-OWNED-START -
    _SHM-OWNED-START SWAP MSPAN-OVERLAP? 0= ;

: SHM-VALID? ( model -- flag )
    DUP 0= OVER 7 AND 0<> OR IF DROP FALSE EXIT THEN
    DUP SHM-HEADER-SIZE SHM-STORAGE-DISJOINT? 0= IF DROP FALSE EXIT THEN
    DUP SHM.ABI @ SHM-ABI <> IF DROP FALSE EXIT THEN
    DUP SHM.CAPACITY @ DUP SHM-HEADER-SIZE < IF 2DROP FALSE EXIT THEN
    OVER SWAP SHM-STORAGE-DISJOINT? 0= IF DROP FALSE EXIT THEN
    DUP SHM.ENTRY-LIMIT @ DUP 0< IF 2DROP FALSE EXIT THEN
    OVER SHM.CAPACITY @ SHM-HEADER-SIZE - SHM-ENTRY-SIZE / > IF DROP FALSE EXIT THEN
    DUP SHM.COUNT @ DUP 0< IF 2DROP FALSE EXIT THEN
    OVER SHM.ENTRY-LIMIT @ > IF DROP FALSE EXIT THEN
    DUP SHM.USED @ OVER SHM.CAPACITY @ > IF DROP FALSE EXIT THEN
    DUP SHM.USED @ SWAP SHM.ENTRY-LIMIT @ SHM-ENTRY-SIZE * SHM-HEADER-SIZE + >= ;

VARIABLE _SHMI-M
VARIABLE _SHMI-CAP
VARIABLE _SHMI-N
\ Zero the first CLEAR bytes, then write the empty header.
: _SHM-FORMAT  ( clear -- )
    _SHMI-M @ SWAP 0 FILL
    SHM-ABI _SHMI-M @ SHM.ABI !
    _SHMI-CAP @ _SHMI-M @ SHM.CAPACITY !
    _SHMI-N @ _SHMI-M @ SHM.ENTRY-LIMIT !
    _SHMI-N @ SHM-ENTRY-SIZE * SHM-HEADER-SIZE + _SHMI-M @ SHM.USED !
    -1 _SHMI-M @ SHM.DIVIDER-COL ! ;

\ SHM-INIT formats a bank once, zeroing all of it.
: SHM-INIT  ( bytes entries model -- ok? )
    DUP 0= OVER 7 AND 0<> OR IF DROP 2DROP FALSE EXIT THEN
    DUP 3 PICK SHM-STORAGE-DISJOINT? 0= IF DROP 2DROP FALSE EXIT THEN
    _SHMI-M ! _SHMI-N ! _SHMI-CAP !
    _SHMI-N @ 0< _SHMI-CAP @ SHM-HEADER-SIZE < OR IF FALSE EXIT THEN
    _SHMI-N @ _SHMI-CAP @ SHM-HEADER-SIZE - SHM-ENTRY-SIZE / > IF
        FALSE EXIT
    THEN
    _SHMI-CAP @ _SHM-FORMAT TRUE ;

\ SHM-BEGIN ( model -- ok? )
\   Start a new build in a bank SHM-INIT formatted.  Entries at or past
\   COUNT are always zero: SHM-INIT zeroes them, SHM-APPEND hands out only
\   those and SHM-UNAPPEND zeroes the one it takes back.  String bytes past
\   USED are never read, since SHM-COPY$ writes them before USED covers
\   them.  So zeroing the header and the COUNT entries in use leaves every
\   readable byte as SHM-INIT would, without clearing the whole bank.
: SHM-BEGIN  ( model -- ok? )
    DUP SHM-VALID? 0= IF DROP FALSE EXIT THEN
    DUP _SHMI-M ! DUP SHM.CAPACITY @ _SHMI-CAP !
    DUP SHM.ENTRY-LIMIT @ _SHMI-N !
    SHM.COUNT @ SHM-ENTRY-SIZE * SHM-HEADER-SIZE + _SHM-FORMAT TRUE ;

: SHM-APPEND  ( model -- entry | 0 )
    DUP SHM-VALID? 0= IF DROP 0 EXIT THEN
    DUP SHM.READY @ IF DROP 0 EXIT THEN
    DUP SHM.COUNT @ OVER SHM.ENTRY-LIMIT @ >= IF DROP 0 EXIT THEN
    DUP SHM.COUNT @ OVER SHM-ENTRY
    1 ROT SHM.COUNT +! ;

\ SHM-UNAPPEND ( used model -- )
\   Take back the last appended entry, zeroing it, and every string byte
\   copied since SHM.USED was USED.  USED must lie between the end of the
\   entry table and the current SHM.USED; otherwise only the entry goes.
VARIABLE _SHMU-U
: SHM-UNAPPEND  ( used model -- )
    DUP SHM-VALID? 0= IF 2DROP EXIT THEN
    DUP SHM.READY @ IF 2DROP EXIT THEN
    DUP SHM.COUNT @ 0= IF 2DROP EXIT THEN
    SWAP _SHMU-U !
    -1 OVER SHM.COUNT +!
    DUP SHM.COUNT @ OVER SHM-ENTRY SHM-ENTRY-SIZE 0 FILL
    _SHMU-U @ OVER SHM.USED @ U> IF DROP EXIT THEN
    _SHMU-U @ OVER SHM.ENTRY-LIMIT @ SHM-ENTRY-SIZE * SHM-HEADER-SIZE +
        U< IF DROP EXIT THEN
    _SHMU-U @ SWAP SHM.USED ! ;

VARIABLE _SHMC-M
VARIABLE _SHMC-U
VARIABLE _SHMC-A
: SHM-COPY$  ( addr len model -- offset ok? )
    DUP SHM-VALID? 0= IF DROP 2DROP 0 FALSE EXIT THEN
    2 PICK 2 PICK SHM-STORAGE-DISJOINT? 0= IF DROP 2DROP 0 FALSE EXIT THEN
    2 PICK 2 PICK 2 PICK DUP SHM.CAPACITY @ MSPAN-OVERLAP? IF
        DROP 2DROP 0 FALSE EXIT
    THEN
    _SHMC-M ! _SHMC-U ! _SHMC-A !
    _SHMC-M @ SHM.READY @ IF 0 FALSE EXIT THEN
    _SHMC-U @ 0< IF 0 FALSE EXIT THEN
    _SHMC-U @ _SHMC-M @ SHM.CAPACITY @ _SHMC-M @ SHM.USED @ - > IF
        0 FALSE EXIT
    THEN
    _SHMC-M @ SHM.USED @
    _SHMC-A @ OVER _SHMC-M @ + _SHMC-U @ CMOVE
    _SHMC-U @ _SHMC-M @ SHM.USED +! TRUE ;

: SHME-LABEL$  ( entry model -- a u )
    OVER SHME.LABEL-OFF @ + SWAP SHME.LABEL-U @ ;
: SHME-TITLE$  ( entry model -- a u )
    OVER SHME.TITLE-OFF @ + SWAP SHME.TITLE-U @ ;
: SHME-ACTION$  ( entry model -- a u )
    OVER SHME.ACTION-OFF @ + SWAP SHME.ACTION-U @ ;

: SHM-SEAL  ( model -- )
    DUP SHM-VALID? IF TRUE SWAP SHM.READY ! ELSE DROP THEN ;

VARIABLE _SHMH-ROW
VARIABLE _SHMH-COL
VARIABLE _SHMH-M
: SHME-CONTAINS?  ( row col entry -- flag )
    >R _SHMH-COL ! _SHMH-ROW !
    _SHMH-ROW @ R@ SHME.ROW @ >=
    _SHMH-ROW @ R@ SHME.ROW @ - R@ SHME.HEIGHT @ < AND
    _SHMH-COL @ R@ SHME.COL @ >= AND
    _SHMH-COL @ R@ SHME.COL @ - R> SHME.WIDTH @ < AND ;

\ Only interactive taskbar entries are hit targets; separators, partial
\ labels, panes, hidden prompt rows and modal backgrounds are not targets.
: SHM-HIT  ( row col model -- entry | 0 )
    DUP SHM-VALID? 0= IF DROP 2DROP 0 EXIT THEN
    _SHMH-M ! _SHMH-COL ! _SHMH-ROW !
    _SHMH-M @ SHM.READY @ 0= IF 0 EXIT THEN
    _SHMH-M @ SHM.FLAGS @ IF 0 EXIT THEN
    _SHMH-M @ SHM.COUNT @ 0 ?DO
        I _SHMH-M @ SHM-ENTRY
        DUP SHME.KIND @ SHM-K-PANE <>
        OVER SHME.FLAGS @ SHM-F-DISABLED AND 0= AND IF
            _SHMH-ROW @ _SHMH-COL @ 2 PICK SHME-CONTAINS? IF UNLOOP EXIT THEN
        THEN DROP
    LOOP 0 ;

\ A grapheme-safe prefix constrained by both byte storage and CELL width.
\ The whole prefix is still fed to the ordinary shared text renderer.
CREATE _SHMT-CURSOR GR-CURSOR-SIZE ALLOT
VARIABLE _SHMT-A
VARIABLE _SHMT-BYTES
VARIABLE _SHMT-CELLS
VARIABLE _SHMT-LIMIT-B
VARIABLE _SHMT-LIMIT-C
: SHM-TEXT-PREFIX  ( a u byte-limit cell-limit -- prefix-u cells )
    _SHMT-LIMIT-C ! _SHMT-LIMIT-B ! OVER _SHMT-A !
    0 _SHMT-BYTES ! 0 _SHMT-CELLS !
    0 _SHMT-CURSOR GR-CURSOR-INIT
    BEGIN _SHMT-CURSOR GR-NEXT WHILE
        _SHMT-CURSOR GR-C-ADDR _SHMT-A @ - _SHMT-CURSOR GR-C-BYTES +
        DUP _SHMT-LIMIT-B @ > IF DROP _SHMT-BYTES @ _SHMT-CELLS @ EXIT THEN
        _SHMT-CELLS @ _SHMT-CURSOR GR-C-WIDTH +
        DUP _SHMT-LIMIT-C @ > IF 2DROP _SHMT-BYTES @ _SHMT-CELLS @ EXIT THEN
        _SHMT-CELLS ! _SHMT-BYTES !
    REPEAT
    _SHMT-BYTES @ _SHMT-CELLS @ ;

HERE _SHM-OWNED-LIMIT !
