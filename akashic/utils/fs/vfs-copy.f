\ =====================================================================
\  vfs-copy.f - Copying and moving files and folders, between volumes too
\ =====================================================================
\  Megapad-64 / KDOS Forth      Prefix: VCOPY- VMOVE- VFS- PLACE- / _VCP- _VC.
\                                       _VCT- _VW- _VMV- _VCI- _VCS-
\
\  A copy writes the file under a stage name in the destination folder,
\  takes a barrier, reads the stage back against the source in halves of
\  the caller's scratch, and only then renames the stage to its final
\  name and takes another barrier.  The rename is the commit: before it
\  the final name does not exist, and a failure removes the stage.  The
\  file passes through the scratch a chunk at a time, so it never needs
\  to fit in memory, and the copy refuses a final name that exists.  A
\  barrier is VFS-BARRIER, the one a checked replacement takes: a sync,
\  except on a binding whose every change is durable when it returns.
\
\  A folder copies the same way at the scale of its tree: its files and
\  bytes are counted first, the whole tree goes under the stage name, one
\  barrier follows, every file is read back, and the stage folder's
\  rename is the commit, so a failure never leaves part of a folder under
\  its final name.  A folder of files and folders copies; a link or a
\  device in it refuses the copy before anything is written, as a name or
\  a path its destination does not take does.
\
\  The destination follows its volume's rules, as a replacement's paths
\  do: names as long as the volume takes, and a path of VFS-PATH-MAX.
\
\  The stage's name is the reserved `.s-` name that VREPL-DERIVE-PATHS!
\  (vfs-replace.f) derives from the final path.  A stage a crash leaves
\  is therefore hidden, and the same copy, tried again, finds it under
\  the same name and removes it before it writes a new one.
\
\  Every copy and move runs as steps in a record of VCOPY-SIZE bytes that
\  its caller keeps.  VCOPY-INIT or VMOVE-INIT starts one, VCOPY-STEP does
\  its next piece of work, VCOPY-CANCEL gives it up before its commit,
\  and VCOPY-PROGRESS says how far it has come, so an applet steps a long
\  copy from its loop.  VFS-COPY and VFS-MOVE run the same steps to the
\  end.  A move inside one instance is one rename, of a file or of a
\  folder with all it holds; across two it copies, then removes the
\  source and takes a barrier, and a folder first takes its own stage
\  name, so it leaves its folder at once.  The PLACE- words bind both
\  paths in their places first, so a read-only place refuses to be
\  written.
\
\  Public API:
\    VCOPY-SIZE      ( -- n )   bytes of a copy record
\    VCOPY-INIT  VMOVE-INIT
\      ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u copy -- ior )
\    PLACE-COPY-INIT  PLACE-MOVE-INIT
\      ( src-a src-u src-place dst-a dst-u dst-place scratch-a scratch-u copy -- ior )
\    VCOPY-STEP      ( copy -- more? ior )
\    VCOPY-CANCEL    ( copy -- ior )
\    VCOPY-PROGRESS  ( copy -- files-done files bytes-done bytes phase )
\    VFS-COPY  VFS-MOVE      ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u -- ior )
\    PLACE-COPY  PLACE-MOVE  ( src-a src-u src-place dst-a dst-u dst-place scratch-a scratch-u -- ior )
\
\  An answer that carries VFS-IOR-F-PARTIAL means the destination stands
\  though a later step failed: the barrier after the copy's rename, or a
\  move's removal of its source.  Every other failure leaves nothing at
\  the destination and the source as it was.
\
\  These words take this module's guard, then the replacement library's
\  to name the stage, then the VFS's, the order every replacement takes.
\  A caller must not hold a VFS-TRANSACTION around them.
\
\  docs/utils/fs/vfs-copy.md describes the words and their answers.
\ =====================================================================

PROVIDED akashic-vfs-copy

REQUIRE vfs.f
REQUIRE vfs-replace.f
REQUIRE places.f
REQUIRE ../../concurrency/guard.f

\ =====================================================================
\  The copy record
\ =====================================================================

0x56434F5059303032 CONSTANT _VCOPY-MAGIC     \ "VCOPY002"

\ What a copy's next step does.  PUBLISHED lasts only from a rename to
\ the barrier after it, inside one step.
 0 CONSTANT _VCOPY-IDLE
 1 CONSTANT _VCOPY-WRITING          \ a file: its next chunk into the stage
 2 CONSTANT _VCOPY-COMPARING        \ a file: its next half chunk read back
 3 CONSTANT _VCOPY-PUBLISHED
 4 CONSTANT _VCOPY-COUNTING         \ a folder: count its files and bytes
 5 CONSTANT _VCOPY-CLEARING         \ remove a stage an earlier copy left
 6 CONSTANT _VCOPY-STAGING          \ make the stage folder
 7 CONSTANT _VCOPY-FILLING          \ copy the tree into the stage
 8 CONSTANT _VCOPY-SETTLING         \ the barrier before the tree is read back
 9 CONSTANT _VCOPY-CHECKING         \ read the tree back against its source
10 CONSTANT _VCOPY-PUBLISHING       \ rename the stage folder
11 CONSTANT _VCOPY-GIVING-UP        \ remove what the copy wrote
12 CONSTANT _VCOPY-RENAMING         \ a move inside one instance
13 CONSTANT _VCOPY-UNSOURCING       \ a move across two: the source goes
14 CONSTANT _VCOPY-SWEEPING         \ remove a hidden source an earlier move left
15 CONSTANT _VCOPY-HIDING           \ give the source folder its hidden name
16 CONSTANT _VCOPY-REMOVING         \ remove the hidden source tree
17 CONSTANT _VCOPY-SOURCE-SETTLING  \ the barrier on the source's instance

\ What VCOPY-PROGRESS says a copy is doing.
0 CONSTANT VCOPY-P-IDLE
1 CONSTANT VCOPY-P-COPYING
2 CONSTANT VCOPY-P-CHECKING
3 CONSTANT VCOPY-P-FINISHING       \ past the commit; it cannot be cancelled
4 CONSTANT VCOPY-P-GIVING-UP
5 CONSTANT VCOPY-P-COUNTING        \ a folder's files and bytes are being counted

\ Flags.
1  CONSTANT _VCF-FOLDER    \ the source is a folder
2  CONSTANT _VCF-MOVE      \ a move: the source goes once the copy stands
4  CONSTANT _VCF-STAGED    \ the stage folder stands, so giving up removes it
8  CONSTANT _VCF-STALE     \ a stage an earlier copy left holds the stage name
16 CONSTANT _VCF-HIDE      \ the hiding descriptor holds paths

: _VC.MAGIC      ( copy -- a ) ;
: _VC.STATE      ( copy -- a )   8 + ;
: _VC.SRC-VFS    ( copy -- a )  16 + ;
: _VC.DST-VFS    ( copy -- a )  24 + ;
: _VC.SRC-FD     ( copy -- a )  32 + ;
: _VC.STAGE-FD   ( copy -- a )  40 + ;   \ the stage, or a tree file's copy
: _VC.SIZE       ( copy -- a )  48 + ;
: _VC.POS        ( copy -- a )  56 + ;
: _VC.SCRATCH-A  ( copy -- a )  64 + ;
: _VC.SCRATCH-U  ( copy -- a )  72 + ;
: _VC.FLAGS      ( copy -- a )  80 + ;
: _VC.IOR        ( copy -- a )  88 + ;   \ the answer once the copy ends
: _VC.FILES      ( copy -- a )  96 + ;   \ the files and bytes counted
: _VC.BYTES      ( copy -- a ) 104 + ;
: _VC.FILES-DONE ( copy -- a ) 112 + ;   \ written, or read back
: _VC.BYTES-DONE ( copy -- a ) 120 + ;
: _VC.WALK       ( copy -- a ) 128 + ;   \ a folder's walk record, or 0
: _VC.SRC-A      ( copy -- a ) 136 + ;   \ the source path, a copy the record holds
: _VC.SRC-U      ( copy -- a ) 144 + ;
\ Two replacement descriptors: the final path and the stage's, and for a
\ folder moved across instances the source's path and its hidden name.
\ Their paths are given back when the copy ends either way.
: _VC.REPL       ( copy -- a ) 152 + ;
152 CONSTANT _VCOPY-HEADER
: _VC.HIDE       ( copy -- a ) _VCOPY-HEADER VREPL-SIZE + + ;

_VCOPY-HEADER VREPL-SIZE 2* + CONSTANT VCOPY-SIZE

GUARD _vcopy-guard

\ The record a call works on, under the guard.
VARIABLE _VCP-C

: _VCP-REPL   ( -- repl )  _VCP-C @ _VC.REPL ;
: _VCP-HIDE   ( -- repl )  _VCP-C @ _VC.HIDE ;
: _VCP-SRC    ( -- vfs )   _VCP-C @ _VC.SRC-VFS @ ;
: _VCP-DST    ( -- vfs )   _VCP-C @ _VC.DST-VFS @ ;
: _VCP-PHASE  ( -- a )     _VCP-C @ _VC.STATE ;
: _VCP-SRC$   ( -- a u )   _VCP-C @ DUP _VC.SRC-A @ SWAP _VC.SRC-U @ ;

: _VCP-FLAG?  ( mask -- flag )  _VCP-C @ _VC.FLAGS @ AND 0<> ;
: _VCP-FLAG+  ( mask -- )  _VCP-C @ _VC.FLAGS DUP @ ROT OR SWAP ! ;
: _VCP-FLAG-  ( mask -- )  INVERT _VCP-C @ _VC.FLAGS DUP @ ROT AND SWAP ! ;

: _VCP-NAME$        ( -- a u )  _VCP-REPL VREPL-TARGET-NAME$ ;
: _VCP-STAGE-NAME$  ( -- a u )  _VCP-REPL VREPL-STAGE-NAME$ ;

\ The folder that holds the final name and the stage, "/" for the root.
: _VCP-FOLDER$  ( -- a u )  _VCP-REPL VREPL-FOLDER$ ;

\ The copy's persistent fields, as the folder words name them.
: _VCT-SV    ( -- a )  _VCP-C @ _VC.SRC-VFS ;
: _VCT-DV    ( -- a )  _VCP-C @ _VC.DST-VFS ;
: _VCT-XA    ( -- a )  _VCP-C @ _VC.SCRATCH-A ;
: _VCT-XU    ( -- a )  _VCP-C @ _VC.SCRATCH-U ;
: _VCT-SFD   ( -- a )  _VCP-C @ _VC.SRC-FD ;
: _VCT-DFD   ( -- a )  _VCP-C @ _VC.STAGE-FD ;
: _VCT-SIZE  ( -- a )  _VCP-C @ _VC.SIZE ;
: _VCT-POS   ( -- a )  _VCP-C @ _VC.POS ;

\ _VCP-NAME-PATH ( dst-a dst-u dst-vfs copy -- ior )
\   Point COPY at the final path DST on DST-VFS and derive its stage.
\   VFS-E-INVALID when the replacement library refuses the path.
: _VCP-NAME-PATH  ( dst-a dst-u dst-vfs copy -- ior )
    DUP _VCP-C !
    2DUP _VC.DST-VFS !
    _VC.REPL VREPL-INIT IF 2DROP VFS-E-INVALID EXIT THEN
    _VCP-REPL VREPL-DERIVE-PATHS! IF VFS-E-INVALID EXIT THEN
    0 ;

\ =====================================================================
\  Answers
\ =====================================================================

VFS-IOR-F-PARTIAL 24 LSHIFT CONSTANT _VCP-PARTIAL-BIT

\ A copy that fails leaves nothing, so its answer never carries
\ VFS-IOR-F-PARTIAL, whatever a binding reported.
: _VCP-WHOLE   ( ior -- ior' )  _VCP-PARTIAL-BIT INVERT AND ;

\ The destination stands though a later step failed.
: _VCP-STANDS  ( ior -- ior' )  _VCP-PARTIAL-BIT OR ;

\ _VCP-CAUGHT ( xt -- ior )
\   Run XT, whose effect is ( -- ior ).  A throw answers VFS-E-IO.
: _VCP-CAUGHT  ( xt -- ior )  CATCH IF VFS-E-IO THEN ;

VARIABLE _VCT-XT

\ _VCT-DO ( xt -- ior )
\   Run XT ( -- ior ) as one VFS transaction; a throw answers VFS-E-IO.
: _VCT-DO-BODY  ( -- ior )  _VCT-XT @ _VCP-CAUGHT ;
: _VCT-DO  ( xt -- ior )  _VCT-XT !  ['] _VCT-DO-BODY VFS-TRANSACTION ;

\ _VCP-ENTRY ( a u vfs -- inode|0 ior )
\   The entry a path names, not following a final link; 0 0 when the
\   path names nothing.
: _VCP-ENTRY  ( a u vfs -- inode|0 ior )
    >R VFS-RP-NOFOLLOW-FINAL R> VFS-RESOLVE-POLICY?
    DUP IF DUP VFS-IOR-REASON VFS-R-NOENT = IF 2DROP 0 0 THEN THEN ;

\ _VCP-FILE? ( inode -- ior )   0 for a regular file.
: _VCP-FILE?  ( inode -- ior )
    IN.TYPE @ DUP VFS-T-FILE = IF DROP 0 EXIT THEN
    VFS-T-DIR = IF VFS-E-ISDIR ELSE VFS-E-INVALID THEN ;

\ _VCP-FOLDER ( -- dir ior )   The destination's folder, as it is now.
: _VCP-FOLDER  ( -- dir ior )
    _VCP-FOLDER$ _VCP-DST VFS-RESOLVE? ?DUP IF EXIT THEN
    DUP IN.TYPE @ VFS-T-DIR <> IF DROP 0 VFS-E-NOTDIR EXIT THEN
    0 ;

\ =====================================================================
\  Entries held across lookups
\ =====================================================================

\ _VCP-PIN ( inode -- pinned? )
\   Keep INODE from eviction.  True when this call set the pin, which
\   the matching _VCP-UNPIN then clears; a pin someone else set stays.
: _VCP-PIN  ( inode -- pinned? )
    IN.FLAGS DUP @ VFS-IF-PINNED AND IF DROP FALSE EXIT THEN
    DUP @ VFS-IF-PINNED OR SWAP ! TRUE ;

: _VCP-UNPIN  ( inode pinned? -- )
    IF IN.FLAGS DUP @ VFS-IF-PINNED INVERT AND SWAP ! ELSE DROP THEN ;

\ =====================================================================
\  Walking a folder
\ =====================================================================
\
\  The walk keeps names and paths, never a VFS entry, between its steps.
\  It lists each folder's entries once, into a block of their own, and
\  each step looks its path up again, so another applet's change, or the
\  cache evicting an entry, never leaves the walk holding a stale one.
\  A walk follows a source tree and may mirror each path under a
\  destination folder, whose name limit and path length it checks.  Its
\  state lies in a walk record of the copy's, which _VW-W names while a
\  call works on that copy.

\ One folder of the walk: its entries and the next one to visit, and the
\ lengths of the source and destination paths that name it.
: _VW.UP     ( level -- a ) ;
: _VW.BLOCK  ( level -- a )  8 + ;
: _VW.COUNT  ( level -- a ) 16 + ;
: _VW.NEXT   ( level -- a ) 24 + ;
: _VW.SU     ( level -- a ) 32 + ;
: _VW.DU     ( level -- a ) 40 + ;
48 CONSTANT _VW-LEVEL-SIZE

\ An entry as it was listed: its name, its kind and its size.  The names
\ follow the entries in the same block.
: _VE.A  ( entry -- a ) ;
: _VE.U  ( entry -- a )  8 + ;
: _VE.T  ( entry -- a ) 16 + ;
: _VE.S  ( entry -- a ) 24 + ;
32 CONSTANT _VE-SIZE

\ The walk record: the source and destination paths, then its cells.
VFS-PATH-MAX 2* CONSTANT _VW-PATHS
_VW-PATHS 64 + CONSTANT _VW-SIZE

VARIABLE _VW-W       \ the walk record the call works on, or 0
0 _VW-W !

: _VW-SRC    ( -- a )  _VW-W @ ;
: _VW-DST    ( -- a )  _VW-W @ VFS-PATH-MAX + ;
: _VW-SU     ( -- a )  _VW-W @ _VW-PATHS + ;
: _VW-DU     ( -- a )  _VW-W @ _VW-PATHS + 8 + ;
: _VW-SV     ( -- a )  _VW-W @ _VW-PATHS + 16 + ;   \ the instance the walk lists
: _VW-DV     ( -- a )  _VW-W @ _VW-PATHS + 24 + ;   \ the destination's, or 0
: _VW-LIMIT  ( -- a )  _VW-W @ _VW-PATHS + 32 + ;   \ its name limit
: _VW-SLACK  ( -- a )  _VW-W @ _VW-PATHS + 40 + ;   \ growth when the stage is renamed
: _VW-TOP    ( -- a )  _VW-W @ _VW-PATHS + 48 + ;   \ the deepest level; 0 when idle
: _VW-ENTRY  ( -- a )  _VW-W @ _VW-PATHS + 56 + ;   \ the entry the walk visits

\ What a step of the walk visits.
0 CONSTANT _VW-END      \ the root is done, and the paths name it
1 CONSTANT _VW-FILE
2 CONSTANT _VW-FOLDER   \ a folder, before its entries
3 CONSTANT _VW-LEFT     \ a folder after its entries, which the paths name
4 CONSTANT _VW-OTHER    \ a link or a device

VARIABLE _VWL-DIR  VARIABLE _VWL-N  VARIABLE _VWL-NAMES
VARIABLE _VWL-BLOCK  VARIABLE _VWL-E  VARIABLE _VWL-T

\ _VW-LIST-BODY ( -- block count ior )
\   The entries of the folder the source path names, copied into one
\   allocated block; no block for a folder without entries.
: _VW-LIST-BODY  ( -- block count ior )
    _VW-SRC _VW-SU @ _VW-SV @ _VCP-ENTRY ?DUP IF NIP 0 0 ROT EXIT THEN
    DUP 0= IF DROP 0 0 VFS-E-NOENT EXIT THEN
    DUP IN.TYPE @ VFS-T-DIR <> IF DROP 0 0 VFS-E-NOTDIR EXIT THEN
    DUP _VWL-DIR !  _VW-SV @ _VFS-ENSURE-CHILDREN? ?DUP IF 0 0 ROT EXIT THEN
    0 _VWL-N !  0 _VWL-NAMES !
    _VWL-DIR @ IN.CHILD @
    BEGIN ?DUP WHILE
        1 _VWL-N +!  DUP IN.NAME @ _VFS-STR-GET NIP _VWL-NAMES +!
        IN.SIBLING @
    REPEAT
    _VWL-N @ 0= IF 0 0 0 EXIT THEN
    _VWL-N @ _VE-SIZE * _VWL-NAMES @ + ALLOCATE ?DUP IF NIP 0 0 ROT EXIT THEN
    DUP _VWL-BLOCK !  DUP _VWL-E !  _VWL-N @ _VE-SIZE * + _VWL-T !
    _VWL-DIR @ IN.CHILD @
    BEGIN ?DUP WHILE
        DUP IN.NAME @ _VFS-STR-GET                   ( in a u )
        DUP _VWL-E @ _VE.U !  _VWL-T @ _VWL-E @ _VE.A !
        TUCK _VWL-T @ SWAP CMOVE _VWL-T +!           ( in )
        DUP IN.TYPE @ _VWL-E @ _VE.T !
        DUP IN.SIZE-LO @ _VWL-E @ _VE.S !
        _VE-SIZE _VWL-E +!
        IN.SIBLING @
    REPEAT
    _VWL-BLOCK @ _VWL-N @ 0 ;

VARIABLE _VWP-L

: _VW-LISTED  ( -- block count ior )  ['] _VW-LIST-BODY VFS-TRANSACTION ;

\ _VW-PUSH ( -- ior )
\   List the folder the paths name, and visit its entries next.  A throw
\   from the binding answers VFS-E-IO.
: _VW-PUSH  ( -- ior )
    ['] _VW-LISTED CATCH IF 0 0 VFS-E-IO THEN
    ?DUP IF NIP NIP EXIT THEN
    _VW-LEVEL-SIZE ALLOCATE ?DUP IF
        NIP >R DROP ?DUP IF FREE THEN R> EXIT
    THEN
    _VWP-L !
    _VWP-L @ _VW.COUNT !  _VWP-L @ _VW.BLOCK !
    0 _VWP-L @ _VW.NEXT !
    _VW-SU @ _VWP-L @ _VW.SU !  _VW-DU @ _VWP-L @ _VW.DU !
    _VW-TOP @ _VWP-L @ _VW.UP !  _VWP-L @ _VW-TOP !
    0 ;

\ _VW-POP ( -- )   Leave the deepest folder; the paths name it again.
: _VW-POP  ( -- )
    _VW-TOP @ ?DUP 0= IF EXIT THEN
    DUP _VW.SU @ _VW-SU !  DUP _VW.DU @ _VW-DU !
    DUP _VW.UP @ _VW-TOP !
    DUP _VW.BLOCK @ ?DUP IF FREE THEN
    FREE ;

\ _VW-ABANDON ( -- )   End the walk wherever it stands.
: _VW-ABANDON  ( -- )
    _VW-W @ 0= IF EXIT THEN
    BEGIN _VW-TOP @ WHILE _VW-POP REPEAT ;

VARIABLE _VWJ-A  VARIABLE _VWJ-U  VARIABLE _VWJ-B  VARIABLE _VWJ-L

\ _VW-APPEND ( name-a name-u buf len -- len' ior )
\   The first LEN bytes of BUF name a folder: put "/" and NAME after them.
\   VFS-E-NAMETOOLONG when the path would pass VFS-PATH-MAX.
: _VW-APPEND  ( name-a name-u buf len -- len' ior )
    _VWJ-L ! _VWJ-B ! _VWJ-U ! _VWJ-A !
    \ The root's path is "/", which the name follows directly.
    _VWJ-L @ 1 = IF _VWJ-B @ C@ [CHAR] / = IF 0 _VWJ-L ! THEN THEN
    _VWJ-L @ 1+ _VWJ-U @ + VFS-PATH-MAX > IF 0 VFS-E-NAMETOOLONG EXIT THEN
    [CHAR] / _VWJ-B @ _VWJ-L @ + C!
    _VWJ-A @ _VWJ-B @ _VWJ-L @ 1+ + _VWJ-U @ CMOVE
    _VWJ-L @ 1+ _VWJ-U @ + 0 ;

VARIABLE _VWN-L

\ _VW-NEXT ( -- event ior )
\   Visit the next entry: for FILE, FOLDER and OTHER the paths name it,
\   for LEFT the folder just left, and for END the root.  A name the
\   destination's volume does not take, or a path longer than the VFS
\   takes, answers VFS-E-NAMETOOLONG.
: _VW-NEXT  ( -- event ior )
    _VW-TOP @ DUP 0= IF DROP _VW-END 0 EXIT THEN  _VWN-L !
    _VWN-L @ _VW.NEXT @ _VWN-L @ _VW.COUNT @ < IF
        _VWN-L @ _VW.BLOCK @ _VWN-L @ _VW.NEXT @ _VE-SIZE * + _VW-ENTRY !
        1 _VWN-L @ _VW.NEXT +!
        _VW-ENTRY @ _VE.A @ _VW-ENTRY @ _VE.U @ _VW-SRC _VWN-L @ _VW.SU @
        _VW-APPEND ?DUP IF NIP 0 SWAP EXIT THEN _VW-SU !
        _VW-DV @ IF
            _VW-ENTRY @ _VE.U @ _VW-LIMIT @ > IF 0 VFS-E-NAMETOOLONG EXIT THEN
            _VW-ENTRY @ _VE.A @ _VW-ENTRY @ _VE.U @ _VW-DST _VWN-L @ _VW.DU @
            _VW-APPEND ?DUP IF NIP 0 SWAP EXIT THEN
            DUP _VW-SLACK @ + VFS-PATH-MAX > IF DROP 0 VFS-E-NAMETOOLONG EXIT THEN
            _VW-DU !
        THEN
        _VW-ENTRY @ _VE.T @ CASE
            VFS-T-FILE OF _VW-FILE ENDOF
            VFS-T-DIR  OF _VW-FOLDER ENDOF
            >R _VW-OTHER R>
        ENDCASE 0 EXIT
    THEN
    _VWN-L @ _VW.UP @ 0= IF _VW-POP _VW-END 0 EXIT THEN
    _VW-POP _VW-LEFT 0 ;

VARIABLE _VWR-A  VARIABLE _VWR-U

\ _VW-ROOT ( src-a src-u src-vfs dst-a dst-u dst-vfs -- ior )
\   Start a walk of the folder SRC on SRC-VFS that mirrors each path
\   under DST on DST-VFS, or that walks SRC alone when DST-VFS is 0.
\   _VW-SLACK must be set first for a walk with a destination.
: _VW-ROOT  ( src-a src-u src-vfs dst-a dst-u dst-vfs -- ior )
    _VW-DV !  _VWR-U ! _VWR-A !  _VW-SV !
    _VW-ABANDON
    DUP VFS-PATH-MAX > IF 2DROP VFS-E-NAMETOOLONG EXIT THEN
    DUP _VW-SU !  _VW-SRC SWAP CMOVE
    0 _VW-DU !
    _VW-DV @ IF
        _VWR-U @ VFS-PATH-MAX > IF VFS-E-NAMETOOLONG EXIT THEN
        _VWR-U @ _VW-DU !  _VWR-A @ _VW-DST _VWR-U @ CMOVE
        _VW-DV @ VFS-NAME-LIMIT _VW-LIMIT !
    THEN
    _VW-PUSH ;

\ =====================================================================
\  Removing a folder
\ =====================================================================
\
\  A removal is a walk that removes each entry before the folder that
\  holds it, one removal or one listing a step.

VARIABLE _VCP-KIND-T

\ What the walk's source path names, in _VCP-KIND-T.
: _VCT-KIND-BODY  ( -- ior )
    _VW-SRC _VW-SU @ _VW-SV @ _VCP-ENTRY ?DUP IF NIP EXIT THEN
    DUP 0= IF DROP VFS-E-NOENT EXIT THEN
    IN.TYPE @ _VCP-KIND-T !  0 ;

: _VCT-RM-PATH  ( -- ior )  _VW-SRC _VW-SU @ _VW-SV @ VFS-RM ;

VARIABLE _VCR-A  VARIABLE _VCR-U  VARIABLE _VCR-V

\ _VCT-RM-BEGIN ( a u vfs -- done? ior )
\   Start removing the folder or file A U on VFS.  A file, a link or a
\   device goes at once, and a path that names nothing is done; a folder
\   is listed, and _VCT-RM-STEP removes its tree.
: _VCT-RM-BEGIN  ( a u vfs -- done? ior )
    _VCR-V ! _VCR-U ! _VCR-A !
    _VW-ABANDON
    _VCR-U @ VFS-PATH-MAX > IF -1 VFS-E-NAMETOOLONG EXIT THEN
    _VCR-A @ _VW-SRC _VCR-U @ CMOVE  _VCR-U @ _VW-SU !  _VCR-V @ _VW-SV !
    ['] _VCT-KIND-BODY _VCT-DO ?DUP IF
        DUP VFS-IOR-REASON VFS-R-NOENT = IF DROP -1 0 EXIT THEN
        -1 SWAP EXIT
    THEN
    _VCP-KIND-T @ VFS-T-DIR <> IF -1 ['] _VCT-RM-PATH _VCT-DO EXIT THEN
    _VCR-A @ _VCR-U @ _VCR-V @ 0 0 0 _VW-ROOT ?DUP IF -1 SWAP EXIT THEN
    0 0 ;

\ _VCT-RM-STEP ( -- done? ior )
\   Remove the next entry of the walk: a file, a link or a device, or a
\   folder once it is empty; a folder met is listed.  DONE? once the root
\   itself has gone.  The first failure ends the walk, leaving the rest.
: _VCT-RM-STEP  ( -- done? ior )
    _VW-NEXT ?DUP IF NIP _VW-ABANDON -1 SWAP EXIT THEN
    CASE
        _VW-FOLDER OF
            _VW-PUSH ?DUP IF _VW-ABANDON -1 SWAP EXIT THEN 0 0 EXIT
        ENDOF
        _VW-END OF -1 ['] _VCT-RM-PATH _VCT-DO EXIT ENDOF
        >R ['] _VCT-RM-PATH _VCT-DO R>
    ENDCASE
    ?DUP IF _VW-ABANDON -1 SWAP EXIT THEN  0 0 ;

\ =====================================================================
\  Ending, and what a copy keeps
\ =====================================================================

\ _VCP-RELEASE ( -- )
\   Give back what a copy holds once it has ended: the paths of its two
\   descriptors, its walk and its copy of the source path.  Outside the
\   VFS's guard, in the order every replacement takes the two guards.
: _VCP-RELEASE  ( -- )
    _VCP-REPL VREPL-FINI DROP
    _VCF-HIDE _VCP-FLAG? IF _VCP-HIDE VREPL-FINI DROP _VCF-HIDE _VCP-FLAG- THEN
    _VCP-C @ _VC.WALK @ ?DUP IF
        _VW-W !  _VW-ABANDON  _VW-W @ FREE  0 _VW-W !
        0 _VCP-C @ _VC.WALK !
    THEN
    _VCP-C @ _VC.SRC-A @ ?DUP IF FREE 0 _VCP-C @ _VC.SRC-A ! THEN ;

\ _VCP-END ( ior -- )   The copy has ended, and IOR is its answer.
: _VCP-END  ( ior -- )
    _VCP-C @ _VC.IOR !  _VW-ABANDON  _VCOPY-IDLE _VCP-PHASE ! ;

\ The answer a give-up ends with: the failure that began it, or, when a
\ cancel began it, a failure of the give-up itself.
: _VCP-GIVEN-UP  ( ior -- )
    _VCP-C @ _VC.IOR @ ?DUP IF NIP THEN _VCP-WHOLE _VCP-END ;

\ =====================================================================
\  Starting a file's copy
\ =====================================================================

VARIABLE _VCI-SA   VARIABLE _VCI-SU   VARIABLE _VCI-SV
VARIABLE _VCI-DA   VARIABLE _VCI-DU   VARIABLE _VCI-DV
VARIABLE _VCI-XA   VARIABLE _VCI-XU
VARIABLE _VCI-MOVE  VARIABLE _VCI-KIND

: _VCI-MKFILE  ( -- inode ior )  _VCP-STAGE-NAME$ _VCP-DST VFS-MKFILE? ;

VARIABLE _VCI-CWD

\ _VCI-MAKE-STAGE ( dir -- ior )
\   Create the stage, empty, in DIR.  The instance's current directory is
\   DIR for this one call and is put back however the call ends.
: _VCI-MAKE-STAGE  ( dir -- ior )
    _VCP-DST V.CWD @ _VCI-CWD !
    _VCP-DST V.CWD !
    ['] _VCI-MKFILE CATCH
    _VCI-CWD @ _VCP-DST V.CWD !
    IF VFS-E-IO EXIT THEN NIP ;

\ _VCI-STALE ( inode -- ior )
\   The stage a copy to this final name left: a file that goes.  An entry
\   of another kind keeps the name, and the source itself is never
\   taken for a stage.
: _VCI-STALE  ( inode -- ior )
    DUP _VCP-C @ _VC.SRC-FD @ FD.INODE @ = IF DROP VFS-E-INVALID EXIT THEN
    IN.TYPE @ VFS-T-FILE <> IF VFS-E-EXISTS EXIT THEN
    _VCP-REPL VREPL-STAGE$ _VCP-DST VFS-RM ;

\ _VCI-START ( -- ior )
\   Open the source, check the final name is free, clear a stage left
\   before, and create and open the stage.  The open source holds its
\   entry, so the lookups after it cannot evict it.
: _VCI-START  ( -- ior )
    _VCI-SA @ _VCI-SU @ VFS-FF-READ _VCP-SRC VFS-OPEN? ?DUP IF NIP EXIT THEN
    DUP _VCP-C @ _VC.SRC-FD !
    DUP FD.INODE @ _VCP-FILE? ?DUP IF NIP EXIT THEN
    VFS-SIZE DUP _VCP-C @ _VC.SIZE !  _VCP-C @ _VC.BYTES !
    1 _VCP-C @ _VC.FILES !
    _VCP-REPL VREPL-TARGET$ _VCP-DST _VCP-ENTRY ?DUP IF NIP EXIT THEN
    IF VFS-E-EXISTS EXIT THEN
    _VCP-REPL VREPL-STAGE$ _VCP-DST _VCP-ENTRY ?DUP IF NIP EXIT THEN
    ?DUP IF _VCI-STALE ?DUP IF EXIT THEN THEN
    _VCP-FOLDER ?DUP IF NIP EXIT THEN
    _VCI-MAKE-STAGE ?DUP IF EXIT THEN
    _VCOPY-WRITING _VCP-PHASE !
    _VCP-REPL VREPL-STAGE$ VFS-FF-WRITE _VCP-DST VFS-OPEN? ?DUP IF NIP EXIT THEN
    _VCP-C @ _VC.STAGE-FD !
    0 ;

\ =====================================================================
\  Giving a file's copy up
\ =====================================================================

VARIABLE _VCX-IOR

: _VCX-NOTE  ( ior -- )
    ?DUP IF _VCX-IOR @ IF DROP ELSE _VCX-IOR ! THEN THEN ;

\ Close the descriptor in FIELD.  The field is cleared first, so a
\ descriptor is never closed twice.
: _VCX-CLOSE  ( field -- )
    DUP @ ?DUP IF 0 ROT ! VFS-CLOSE? _VCX-NOTE ELSE DROP THEN ;

: _VCX-RM-STAGE  ( -- ior )
    _VCP-REPL VREPL-STAGE$ _VCP-DST VFS-RM
    DUP VFS-IOR-REASON VFS-R-NOENT = IF DROP 0 THEN ;

: _VCX-SYNC  ( -- ior )  _VCP-DST VFS-BARRIER ;

\ _VCP-DROP ( -- ior )
\   Close the copy's files and remove its stage, so the destination
\   holds nothing of it, then take a barrier.  Each step is tried
\   whatever the one before answered, and the first failure is the
\   answer.  A stage that cannot be removed stays a hidden file until the
\   same copy is tried again.
: _VCP-DROP  ( -- ior )
    0 _VCX-IOR !
    _VCP-C @ _VC.SRC-FD _VCX-CLOSE
    _VCP-C @ _VC.STAGE-FD _VCX-CLOSE
    _VCP-PHASE @ DUP _VCOPY-WRITING = SWAP _VCOPY-COMPARING = OR IF
        ['] _VCX-RM-STAGE _VCP-CAUGHT _VCX-NOTE
        ['] _VCX-SYNC _VCP-CAUGHT _VCX-NOTE
    THEN
    _VCX-IOR @ ;

\ =====================================================================
\  Stepping a file's copy
\ =====================================================================

VARIABLE _VCS-N
VARIABLE _VCS-HALF

: _VCS-FD-CLOSE  ( field -- ior )  DUP @ 0 ROT ! VFS-CLOSE? ;

\ Move the next chunk, as much as the scratch holds, into the stage.
: _VCS-WRITE  ( -- ior )
    _VCP-C @ _VC.SIZE @ _VCP-C @ _VC.POS @ -
    _VCP-C @ _VC.SCRATCH-U @ MIN _VCS-N !
    _VCP-C @ _VC.SCRATCH-A @ _VCS-N @ _VCP-C @ _VC.SRC-FD @ VFS-READ-EXACT
    ?DUP IF EXIT THEN
    _VCP-C @ _VC.SCRATCH-A @ _VCS-N @ _VCP-C @ _VC.STAGE-FD @ VFS-WRITE-EXACT
    ?DUP IF EXIT THEN
    _VCS-N @ _VCP-C @ _VC.POS +!
    _VCS-N @ _VCP-C @ _VC.BYTES-DONE +!
    0 ;

\ Every byte is in the stage: close it, take a barrier, and open it
\ again to read it back against the source from the start.
: _VCS-WRITTEN  ( -- ior )
    _VCP-C @ _VC.STAGE-FD _VCS-FD-CLOSE ?DUP IF EXIT THEN
    _VCP-DST VFS-BARRIER ?DUP IF EXIT THEN
    _VCP-REPL VREPL-STAGE$ VFS-FF-READ _VCP-DST VFS-OPEN?
    ?DUP IF NIP EXIT THEN
    DUP _VCP-C @ _VC.STAGE-FD !
    VFS-SIZE _VCP-C @ _VC.SIZE @ <> IF VFS-E-CORRUPT EXIT THEN
    _VCP-C @ _VC.SRC-FD @ VFS-SIZE _VCP-C @ _VC.SIZE @ <> IF
        VFS-E-CORRUPT EXIT
    THEN
    0 _VCP-C @ _VC.SRC-FD @ VFS-SEEK? ?DUP IF EXIT THEN
    0 _VCP-C @ _VC.POS !
    0 _VCP-C @ _VC.BYTES-DONE !
    _VCOPY-COMPARING _VCP-PHASE !
    0 ;

\ Compare the next half of the scratch's worth of the stage with the
\ source.
: _VCS-COMPARE  ( -- ior )
    _VCP-C @ _VC.SCRATCH-U @ 2 / _VCS-HALF !
    _VCP-C @ _VC.SIZE @ _VCP-C @ _VC.POS @ - _VCS-HALF @ MIN _VCS-N !
    _VCP-C @ _VC.SCRATCH-A @ _VCS-N @ _VCP-C @ _VC.SRC-FD @ VFS-READ-EXACT
    ?DUP IF EXIT THEN
    _VCP-C @ _VC.SCRATCH-A @ _VCS-HALF @ + _VCS-N @
    _VCP-C @ _VC.STAGE-FD @ VFS-READ-EXACT ?DUP IF EXIT THEN
    _VCP-C @ _VC.SCRATCH-A @ _VCS-N @
    _VCP-C @ _VC.SCRATCH-A @ _VCS-HALF @ + _VCS-N @
    COMPARE IF VFS-E-CORRUPT EXIT THEN
    _VCS-N @ _VCP-C @ _VC.POS +!
    _VCS-N @ _VCP-C @ _VC.BYTES-DONE +!
    0 ;

\ After the commit: a move goes on to remove its source; a copy has ended.
: _VCP-COMMITTED  ( -- )
    _VCF-MOVE _VCP-FLAG? IF _VCOPY-UNSOURCING _VCP-PHASE ! ELSE 0 _VCP-END THEN ;

\ The stage reads back as the source: rename it to the final name, which
\ must still be free, and take a barrier.  The rename is the commit.
: _VCS-PUBLISH  ( -- ior )
    _VCP-C @ _VC.SRC-FD _VCS-FD-CLOSE ?DUP IF EXIT THEN
    _VCP-C @ _VC.STAGE-FD _VCS-FD-CLOSE ?DUP IF EXIT THEN
    _VCP-REPL VREPL-STAGE$ _VCP-DST _VCP-ENTRY ?DUP IF NIP EXIT THEN
    DUP 0= IF DROP VFS-E-NOENT EXIT THEN
    >R _VCP-NAME$ R@ R> IN.PARENT @ VFS-RN-NOREPLACE _VCP-DST VFS-RENAME-AT
    ?DUP IF EXIT THEN
    _VCOPY-PUBLISHED _VCP-PHASE !
    1 _VCP-C @ _VC.FILES-DONE !
    _VCP-DST VFS-BARRIER ?DUP IF EXIT THEN
    _VCP-COMMITTED 0 ;

: _VCS-WRITE-STEP  ( -- ior )
    _VCP-C @ _VC.POS @ _VCP-C @ _VC.SIZE @ < IF _VCS-WRITE ELSE _VCS-WRITTEN THEN ;

: _VCS-COMPARE-STEP  ( -- ior )
    _VCP-C @ _VC.POS @ _VCP-C @ _VC.SIZE @ < IF _VCS-COMPARE ELSE _VCS-PUBLISH THEN ;

\ =====================================================================
\  Copying a folder
\ =====================================================================
\
\  A folder copies as a file does, at the scale of its tree.  The tree is
\  counted, written under the stage name in the destination folder, one
\  barrier follows, every file is read back against its source, and only
\  then is the stage folder renamed to its final name, which is the
\  commit, and another barrier taken.  A failure before the rename
\  removes the stage tree, so the final name never holds part of a
\  folder.  A folder holds files and folders only: a link or a device in
\  it refuses the copy, as a name or a path its destination does not take
\  does, and both are found while the tree is counted.

VARIABLE _VCT-N  VARIABLE _VCT-HALF
VARIABLE _VCT-STALE    \ true when a stage left before holds the stage name
VARIABLE _VCT-SRC-IN  VARIABLE _VCT-PINNED
VARIABLE _VCT-WALK  VARIABLE _VCT-DEPTH
VARIABLE _VCT-CWD

: _VCT-CLOSE?  ( field -- ior )
    DUP @ ?DUP IF 0 ROT ! VFS-CLOSE? ELSE DROP 0 THEN ;

\ Close the file and its copy, if open; the first failure is the answer.
: _VCT-FILES-CLOSE  ( -- ior )
    _VCT-SFD _VCT-CLOSE?  _VCT-DFD _VCT-CLOSE?  ?DUP IF NIP THEN ;

\ _VCT-INSIDE? ( dir -- flag )
\   Whether DIR is the source folder or lies inside it.  A walk up that
\   outlasts the cache's count is a cycle, and counts as inside.
: _VCT-INSIDE?  ( dir -- flag )
    _VCT-WALK !  0 _VCT-DEPTH !
    BEGIN _VCT-WALK @ WHILE
        _VCT-WALK @ _VCT-SRC-IN @ = IF TRUE EXIT THEN
        _VCT-DEPTH @ _VCP-SRC V.ICOUNT @ U< 0= IF TRUE EXIT THEN
        _VCT-WALK @ IN.PARENT @ _VCT-WALK !  1 _VCT-DEPTH +!
    REPEAT
    FALSE ;

\ The final name is free, the destination's folder exists and lies
\ outside the source, and whether a stage left before holds the stage
\ name.  The source is the folder pinned in _VCT-SRC-IN.
: _VCT-START-CHECK  ( -- ior )
    _VCP-REPL VREPL-TARGET$ _VCP-DST _VCP-ENTRY ?DUP IF NIP EXIT THEN
    IF VFS-E-EXISTS EXIT THEN
    _VCP-FOLDER ?DUP IF NIP EXIT THEN
    _VCP-SRC _VCP-DST = IF
        _VCT-INSIDE? IF VFS-E-INVALID EXIT THEN
    ELSE DROP THEN
    _VCP-REPL VREPL-STAGE$ _VCP-DST _VCP-ENTRY ?DUP IF NIP EXIT THEN
    ?DUP IF _VCT-SRC-IN @ = IF VFS-E-INVALID EXIT THEN -1 _VCT-STALE ! THEN
    0 ;

: _VCT-START-BODY  ( -- ior )
    0 _VCT-STALE !
    _VCP-SRC$ _VCP-SRC _VCP-ENTRY ?DUP IF NIP EXIT THEN
    DUP 0= IF DROP VFS-E-NOENT EXIT THEN
    DUP IN.TYPE @ VFS-T-DIR <> IF DROP VFS-E-NOTDIR EXIT THEN
    DUP _VCT-SRC-IN !  _VCP-PIN _VCT-PINNED !
    _VCT-START-CHECK
    _VCT-SRC-IN @ _VCT-PINNED @ _VCP-UNPIN ;

: _VCT-MKSTAGE  ( -- ior )  _VCP-STAGE-NAME$ _VCP-DST VFS-MKDIR ;

\ Make the stage folder in the destination's folder.  The instance's
\ current directory is that folder for this one call.
: _VCT-MAKE-STAGE-BODY  ( -- ior )
    _VCP-FOLDER ?DUP IF NIP EXIT THEN
    _VCP-DST V.CWD @ _VCT-CWD !  _VCP-DST V.CWD !
    ['] _VCT-MKSTAGE CATCH
    _VCT-CWD @ _VCP-DST V.CWD !
    IF VFS-E-IO THEN ;

\ _VCT-AT-PARENT ( xt -- ior )
\   Run XT ( -- ior ) with the destination's current directory at the
\   folder that holds the entry the walk visits.  The directory is put
\   back however XT ends.
: _VCT-AT-PARENT  ( xt -- ior )
    >R _VW-DST _VW-TOP @ _VW.DU @ _VCP-DST VFS-RESOLVE?
    ?DUP IF NIP R> DROP EXIT THEN
    DUP IN.TYPE @ VFS-T-DIR <> IF DROP R> DROP VFS-E-NOTDIR EXIT THEN
    _VCP-DST V.CWD @ _VCT-CWD !  _VCP-DST V.CWD !
    R> CATCH
    _VCT-CWD @ _VCP-DST V.CWD !
    IF VFS-E-IO THEN ;

: _VCT-NAME$  ( -- a u )  _VW-ENTRY @ DUP _VE.A @ SWAP _VE.U @ ;
: _VCT-MKDIR   ( -- ior )  _VCT-NAME$ _VCP-DST VFS-MKDIR ;
: _VCT-MKFILE  ( -- ior )  _VCT-NAME$ _VCP-DST VFS-MKFILE? NIP ;

: _VCT-FOLDER-BODY  ( -- ior )  ['] _VCT-MKDIR _VCT-AT-PARENT ;

\ A file of the tree: create its copy, empty, and open both.
: _VCT-FILE-OPEN  ( -- ior )
    ['] _VCT-MKFILE _VCT-AT-PARENT ?DUP IF EXIT THEN
    _VW-SRC _VW-SU @ VFS-FF-READ _VCP-SRC VFS-OPEN? ?DUP IF NIP EXIT THEN
    DUP _VCT-SFD !  VFS-SIZE _VCT-SIZE !  0 _VCT-POS !
    _VW-DST _VW-DU @ VFS-FF-WRITE _VCP-DST VFS-OPEN? ?DUP IF NIP EXIT THEN
    _VCT-DFD !  0 ;

\ Move the next chunk, as much as the scratch holds.
: _VCT-WRITE-CHUNK  ( -- ior )
    _VCT-SIZE @ _VCT-POS @ - _VCT-XU @ MIN _VCT-N !
    _VCT-XA @ _VCT-N @ _VCT-SFD @ VFS-READ-EXACT ?DUP IF EXIT THEN
    _VCT-XA @ _VCT-N @ _VCT-DFD @ VFS-WRITE-EXACT ?DUP IF EXIT THEN
    _VCT-N @ _VCT-POS +!  _VCT-N @ _VCP-C @ _VC.BYTES-DONE +!  0 ;

\ A copy that differs from its source, or is missing, is corrupt; the
\ source gone is the source gone.
: _VCT-CORRUPT  ( ior -- ior' )
    DUP VFS-IOR-REASON VFS-R-NOENT = IF DROP VFS-E-CORRUPT THEN ;

: _VCT-CHECK-FOLDER  ( -- ior )
    _VW-DST _VW-DU @ _VCP-DST _VCP-ENTRY ?DUP IF NIP _VCT-CORRUPT EXIT THEN
    DUP 0= IF DROP VFS-E-CORRUPT EXIT THEN
    IN.TYPE @ VFS-T-DIR <> IF VFS-E-CORRUPT EXIT THEN  0 ;

: _VCT-CHECK-OPEN  ( -- ior )
    _VW-SRC _VW-SU @ VFS-FF-READ _VCP-SRC VFS-OPEN? ?DUP IF NIP EXIT THEN
    DUP _VCT-SFD !  VFS-SIZE _VCT-SIZE !  0 _VCT-POS !
    _VW-DST _VW-DU @ VFS-FF-READ _VCP-DST VFS-OPEN?
    ?DUP IF NIP _VCT-CORRUPT EXIT THEN
    DUP _VCT-DFD !
    VFS-SIZE _VCT-SIZE @ <> IF VFS-E-CORRUPT EXIT THEN  0 ;

\ Compare the next half of the scratch's worth of the copy with the
\ source.
: _VCT-CHECK-CHUNK  ( -- ior )
    _VCT-XU @ 2 / _VCT-HALF !
    _VCT-SIZE @ _VCT-POS @ - _VCT-HALF @ MIN _VCT-N !
    _VCT-XA @ _VCT-N @ _VCT-SFD @ VFS-READ-EXACT ?DUP IF EXIT THEN
    _VCT-XA @ _VCT-HALF @ + _VCT-N @ _VCT-DFD @ VFS-READ-EXACT ?DUP IF EXIT THEN
    _VCT-XA @ _VCT-N @  _VCT-XA @ _VCT-HALF @ + _VCT-N @  COMPARE
    IF VFS-E-CORRUPT EXIT THEN
    _VCT-N @ _VCT-POS +!  _VCT-N @ _VCP-C @ _VC.BYTES-DONE +!  0 ;

\ Walk the source, mirrored under the stage folder.  A path grows by
\ the final name's length less the stage name's once the stage is
\ renamed, and is checked for that length.
: _VCT-ROOTS  ( -- ior )
    _VCP-REPL VREPL-TARGET$ NIP _VCP-REPL VREPL-STAGE$ NIP - 0 MAX _VW-SLACK !
    _VCP-SRC$ _VCP-SRC _VCP-REPL VREPL-STAGE$ _VCP-DST _VW-ROOT ;

: _VCT-BARRIER  ( -- ior )  _VCP-DST VFS-BARRIER ;

\ The stage reads back as the source: rename it to the final name.
: _VCT-PUBLISH-BODY  ( -- ior )
    _VCP-REPL VREPL-STAGE$ _VCP-DST _VCP-ENTRY ?DUP IF NIP EXIT THEN
    DUP 0= IF DROP VFS-E-NOENT EXIT THEN
    >R _VCP-NAME$ R@ R> IN.PARENT @ VFS-RN-NOREPLACE _VCP-DST VFS-RENAME-AT ;

\ The tree is counted: clear a stage left before, or make the stage.
: _VCT-COUNTED  ( -- ior )
    _VCF-STALE _VCP-FLAG? 0= IF _VCOPY-STAGING _VCP-PHASE ! 0 EXIT THEN
    _VCP-REPL VREPL-STAGE$ _VCP-DST _VCT-RM-BEGIN ?DUP IF NIP EXIT THEN
    IF _VCOPY-STAGING ELSE _VCOPY-CLEARING THEN _VCP-PHASE !  0 ;

\ Count the tree's files and bytes, a folder's listing a step and its
\ files with it, and refuse a link, a device, a name or a path the
\ destination does not take.
: _VCT-COUNTING-STEP  ( -- ior )
    BEGIN
        _VW-NEXT ?DUP IF NIP EXIT THEN
        CASE
            _VW-END OF _VCT-COUNTED EXIT ENDOF
            _VW-FOLDER OF _VW-PUSH EXIT ENDOF
            _VW-OTHER OF VFS-E-UNSUPPORTED EXIT ENDOF
            _VW-FILE OF
                1 _VCP-C @ _VC.FILES +!
                _VW-ENTRY @ _VE.S @ _VCP-C @ _VC.BYTES +!
            ENDOF
        ENDCASE
    AGAIN ;

: _VCT-CLEARING-STEP  ( -- ior )
    _VCT-RM-STEP ?DUP IF NIP EXIT THEN
    IF _VCOPY-STAGING _VCP-PHASE ! THEN 0 ;

\ Make the stage folder, and start the walk that fills it.
: _VCT-STAGING-STEP  ( -- ior )
    ['] _VCT-MAKE-STAGE-BODY _VCT-DO ?DUP IF EXIT THEN
    _VCF-STAGED _VCP-FLAG+
    0 _VCP-C @ _VC.FILES-DONE !  0 _VCP-C @ _VC.BYTES-DONE !
    _VCOPY-FILLING _VCP-PHASE !
    _VCT-ROOTS ;

\ Copy the next piece of the tree: a chunk of the open file or its
\ closing, or the next entry: a folder made and listed, a file created
\ and opened.
: _VCT-FILLING-STEP  ( -- ior )
    _VCT-SFD @ IF
        _VCT-POS @ _VCT-SIZE @ < IF ['] _VCT-WRITE-CHUNK _VCT-DO EXIT THEN
        ['] _VCT-FILES-CLOSE _VCT-DO ?DUP IF EXIT THEN
        1 _VCP-C @ _VC.FILES-DONE +!  0 EXIT
    THEN
    BEGIN
        _VW-NEXT ?DUP IF NIP EXIT THEN
        CASE
            _VW-END OF _VCOPY-SETTLING _VCP-PHASE ! 0 EXIT ENDOF
            _VW-FOLDER OF
                ['] _VCT-FOLDER-BODY _VCT-DO ?DUP IF EXIT THEN
                _VW-PUSH EXIT
            ENDOF
            _VW-FILE OF ['] _VCT-FILE-OPEN _VCT-DO EXIT ENDOF
            _VW-OTHER OF VFS-E-UNSUPPORTED EXIT ENDOF
        ENDCASE
    AGAIN ;

\ The tree is written: one barrier, then the walk that reads it back.
: _VCT-SETTLING-STEP  ( -- ior )
    ['] _VCT-BARRIER _VCP-CAUGHT ?DUP IF EXIT THEN
    0 _VCP-C @ _VC.FILES-DONE !  0 _VCP-C @ _VC.BYTES-DONE !
    _VCOPY-CHECKING _VCP-PHASE !
    _VCT-ROOTS ;

\ Read the next piece of the copy back against its source.  An entry of
\ another kind now is a source that changed after it was copied.
: _VCT-CHECKING-STEP  ( -- ior )
    _VCT-SFD @ IF
        _VCT-POS @ _VCT-SIZE @ < IF ['] _VCT-CHECK-CHUNK _VCT-DO EXIT THEN
        ['] _VCT-FILES-CLOSE _VCT-DO ?DUP IF EXIT THEN
        1 _VCP-C @ _VC.FILES-DONE +!  0 EXIT
    THEN
    BEGIN
        _VW-NEXT ?DUP IF NIP EXIT THEN
        CASE
            _VW-END OF _VCOPY-PUBLISHING _VCP-PHASE ! 0 EXIT ENDOF
            _VW-FOLDER OF
                ['] _VCT-CHECK-FOLDER _VCT-DO ?DUP IF EXIT THEN
                _VW-PUSH EXIT
            ENDOF
            _VW-FILE OF ['] _VCT-CHECK-OPEN _VCT-DO EXIT ENDOF
            _VW-OTHER OF VFS-E-CORRUPT EXIT ENDOF
        ENDCASE
    AGAIN ;

\ Rename the stage folder, the commit, and take a barrier.
: _VCT-PUBLISHING-STEP  ( -- ior )
    ['] _VCT-PUBLISH-BODY _VCT-DO ?DUP IF EXIT THEN
    _VCF-STAGED _VCP-FLAG-
    _VCOPY-PUBLISHED _VCP-PHASE !
    ['] _VCT-BARRIER _VCP-CAUGHT ?DUP IF EXIT THEN
    _VCP-COMMITTED 0 ;

\ =====================================================================
\  Giving a copy up
\ =====================================================================
\
\  A failure before the commit gives the copy up: a file's copy closes
\  its files, removes its stage and takes a barrier at once; a folder's
\  closes its files, leaves its walk, and removes the stage tree by the
\  steps that follow, then takes a barrier.  The answer is the failure,
\  whole.  A stage that cannot be removed stays hidden until the same
\  copy is tried again.

: _VCT-GAVE-UP  ( -- )  ['] _VCT-BARRIER _VCP-CAUGHT _VCP-GIVEN-UP ;

\ _VCP-GIVE-UP ( ior -- )   Give the copy up; IOR is its answer, and 0
\   for a cancel.
: _VCP-GIVE-UP  ( ior -- )
    _VCP-WHOLE _VCP-C @ _VC.IOR !
    _VCF-FOLDER _VCP-FLAG? 0= IF _VCP-DROP _VCP-GIVEN-UP EXIT THEN
    ['] _VCT-FILES-CLOSE _VCP-CAUGHT DROP
    _VW-ABANDON
    _VCF-STAGED _VCP-FLAG? 0= IF 0 _VCP-GIVEN-UP EXIT THEN
    _VCF-STAGED _VCP-FLAG-
    _VCOPY-GIVING-UP _VCP-PHASE !
    _VCP-REPL VREPL-STAGE$ _VCP-DST _VCT-RM-BEGIN
    ?DUP IF NIP _VCP-GIVEN-UP EXIT THEN
    IF _VCT-GAVE-UP THEN ;

: _VCT-GIVING-UP-STEP  ( -- ior )
    _VCT-RM-STEP ?DUP IF NIP _VCP-GIVEN-UP 0 EXIT THEN
    IF _VCT-GAVE-UP THEN 0 ;

\ =====================================================================
\  Moving
\ =====================================================================

VARIABLE _VMV-SA   VARIABLE _VMV-SU   VARIABLE _VMV-SV
VARIABLE _VMV-DV
VARIABLE _VMV-FD
VARIABLE _VMV-MOVED
VARIABLE _VMV-IN       \ the source's entry, held until the rename
VARIABLE _VMV-PINNED

: _VMV-ARGS  ( -- )
    _VCP-SRC$ _VMV-SU ! _VMV-SA !  _VCP-SRC _VMV-SV !  _VCP-DST _VMV-DV ! ;

\ _VMV-SOURCE ( -- inode ior )
\   What a move takes: a regular file or a folder, by its own name rather
\   than through a final link.
: _VMV-SOURCE  ( -- inode ior )
    _VMV-SA @ _VMV-SU @ _VMV-SV @ _VCP-ENTRY ?DUP IF EXIT THEN
    DUP 0= IF VFS-E-NOENT EXIT THEN
    DUP IN.TYPE @ DUP VFS-T-FILE = SWAP VFS-T-DIR = OR
    IF 0 ELSE VFS-E-INVALID THEN ;

\ Hold the source's entry until the rename, so the folder's lookup
\ cannot evict it: a file by opening it, a folder by its pin.
: _VMV-HOLD  ( -- ior )
    _VMV-SOURCE ?DUP IF NIP EXIT THEN
    DUP IN.TYPE @ VFS-T-DIR = IF
        DUP _VMV-IN !  _VCP-PIN _VMV-PINNED !  0 EXIT
    THEN
    DROP _VMV-SA @ _VMV-SU @ VFS-FF-READ _VMV-SV @ VFS-OPEN? ?DUP IF NIP EXIT THEN
    DUP _VMV-FD !  FD.INODE @ _VMV-IN !  0 ;

\ Inside one instance: one rename, of a file or of a folder with all it
\ holds.  The VFS refuses to move a folder beneath itself.
: _VMV-RENAME-BODY  ( -- ior )
    _VMV-SOURCE NIP ?DUP IF EXIT THEN
    _VCP-REPL VREPL-TARGET$ _VMV-DV @ _VCP-ENTRY ?DUP IF NIP EXIT THEN
    IF VFS-E-EXISTS EXIT THEN
    _VMV-HOLD ?DUP IF EXIT THEN
    _VCP-FOLDER ?DUP IF NIP EXIT THEN
    >R _VCP-NAME$ _VMV-IN @ R> VFS-RN-NOREPLACE _VMV-DV @
    VFS-RENAME-AT ?DUP IF EXIT THEN
    -1 _VMV-MOVED !
    _VMV-DV @ VFS-BARRIER ;

: _VMV-RENAME  ( -- ior )
    0 _VMV-FD !  0 _VMV-MOVED !  0 _VMV-IN !  0 _VMV-PINNED !
    ['] _VMV-RENAME-BODY _VCP-CAUGHT
    _VMV-FD @ ?DUP IF 0 _VMV-FD ! VFS-CLOSE? DROP THEN
    _VMV-PINNED @ IF _VMV-IN @ TRUE _VCP-UNPIN  0 _VMV-PINNED ! THEN
    DUP _VMV-MOVED @ AND IF _VCP-STANDS ELSE _VCP-WHOLE THEN ;

\ A move inside one instance is one step: its rename and its barrier.
: _VMV-RENAMING-STEP  ( -- ior )  _VMV-ARGS _VMV-RENAME _VCP-END 0 ;

\ Across instances, once a file's copy stands: the source goes, durably.
: _VMV-REMOVE-BODY  ( -- ior )
    _VMV-SA @ _VMV-SU @ _VMV-SV @ VFS-RM ?DUP IF EXIT THEN
    _VMV-SV @ VFS-BARRIER ;

\ A folder moved across instances leaves its folder first: it takes the
\ stage name that VREPL-DERIVE-PATHS! derives from its own path, the
\ hiding descriptor's, so it is hidden at once, and that tree is then
\ removed.

: _VCT-HIDDEN$  ( -- a u )  _VCP-HIDE VREPL-STAGE$ ;

\ Whether a folder a move left before holds the hidden name.
: _VCT-HIDDEN-BODY  ( -- ior )
    0 _VCT-STALE !
    _VCT-HIDDEN$ _VCP-SRC _VCP-ENTRY ?DUP IF NIP EXIT THEN
    IF -1 _VCT-STALE ! THEN 0 ;

: _VCT-HIDE-BODY  ( -- ior )
    _VCP-SRC$ _VCP-SRC _VCP-ENTRY ?DUP IF NIP EXIT THEN
    DUP 0= IF DROP VFS-E-NOENT EXIT THEN
    >R _VCP-HIDE VREPL-STAGE-NAME$ R@ R> IN.PARENT @ VFS-RN-NOREPLACE
    _VCP-SRC VFS-RENAME-AT ;

: _VCT-SOURCE-BARRIER  ( -- ior )  _VCP-SRC VFS-BARRIER ;

\ Once the copy stands, the source goes: a file in one step, a folder by
\ a hidden tree an earlier move left being cleared first, the folder
\ hidden, its tree removed and a barrier taken.  A failure leaves the
\ copy standing, and the answer says so; until the hiding, both keep
\ their names.
: _VCP-UNSOURCING-STEP  ( -- ior )
    _VCF-FOLDER _VCP-FLAG? 0= IF
        _VMV-ARGS ['] _VMV-REMOVE-BODY _VCP-CAUGHT ?DUP IF EXIT THEN
        0 _VCP-END 0 EXIT
    THEN
    ['] _VCT-HIDDEN-BODY _VCT-DO ?DUP IF EXIT THEN
    _VCT-STALE @ 0= IF _VCOPY-HIDING _VCP-PHASE ! 0 EXIT THEN
    _VCT-HIDDEN$ _VCP-SRC _VCT-RM-BEGIN ?DUP IF NIP EXIT THEN
    IF _VCOPY-HIDING ELSE _VCOPY-SWEEPING THEN _VCP-PHASE ! 0 ;

: _VCT-SWEEPING-STEP  ( -- ior )
    _VCT-RM-STEP ?DUP IF NIP EXIT THEN
    IF _VCOPY-HIDING _VCP-PHASE ! THEN 0 ;

: _VCT-HIDING-STEP  ( -- ior )
    ['] _VCT-HIDE-BODY _VCT-DO ?DUP IF EXIT THEN
    _VCT-HIDDEN$ _VCP-SRC _VCT-RM-BEGIN ?DUP IF NIP EXIT THEN
    IF _VCOPY-SOURCE-SETTLING ELSE _VCOPY-REMOVING THEN _VCP-PHASE ! 0 ;

: _VCT-REMOVING-STEP  ( -- ior )
    _VCT-RM-STEP ?DUP IF NIP EXIT THEN
    IF _VCOPY-SOURCE-SETTLING _VCP-PHASE ! THEN 0 ;

: _VCT-SOURCE-SETTLING-STEP  ( -- ior )
    ['] _VCT-SOURCE-BARRIER _VCP-CAUGHT ?DUP IF EXIT THEN
    0 _VCP-END 0 ;

\ =====================================================================
\  Stepping a copy
\ =====================================================================

: _VCP-WORK  ( -- ior )
    _VCP-PHASE @ CASE
        _VCOPY-WRITING          OF _VCS-WRITE-STEP ENDOF
        _VCOPY-COMPARING        OF _VCS-COMPARE-STEP ENDOF
        _VCOPY-COUNTING         OF _VCT-COUNTING-STEP ENDOF
        _VCOPY-CLEARING         OF _VCT-CLEARING-STEP ENDOF
        _VCOPY-STAGING          OF _VCT-STAGING-STEP ENDOF
        _VCOPY-FILLING          OF _VCT-FILLING-STEP ENDOF
        _VCOPY-SETTLING         OF _VCT-SETTLING-STEP ENDOF
        _VCOPY-CHECKING         OF _VCT-CHECKING-STEP ENDOF
        _VCOPY-PUBLISHING       OF _VCT-PUBLISHING-STEP ENDOF
        _VCOPY-GIVING-UP        OF _VCT-GIVING-UP-STEP ENDOF
        _VCOPY-RENAMING         OF _VMV-RENAMING-STEP ENDOF
        _VCOPY-UNSOURCING       OF _VCP-UNSOURCING-STEP ENDOF
        _VCOPY-SWEEPING         OF _VCT-SWEEPING-STEP ENDOF
        _VCOPY-HIDING           OF _VCT-HIDING-STEP ENDOF
        _VCOPY-REMOVING         OF _VCT-REMOVING-STEP ENDOF
        _VCOPY-SOURCE-SETTLING  OF _VCT-SOURCE-SETTLING-STEP ENDOF
        >R 0 R>
    ENDCASE ;

\ Whether a phase lies past the commit: the copy stands, and only the
\ move's removal of its source is left.
: _VCP-COMMITTED?  ( phase -- flag )
    DUP _VCOPY-PUBLISHED = SWAP _VCOPY-UNSOURCING _VCOPY-SOURCE-SETTLING 1+
    WITHIN OR ;

\ A step failed with IOR.  Before the commit the copy is given up; past
\ it the copy stands and the answer says so; a give-up that fails ends
\ with the answer it was to give.
: _VCP-FAILED  ( ior -- )
    _VCP-PHASE @ _VCOPY-GIVING-UP = IF _VCP-GIVEN-UP EXIT THEN
    _VCP-PHASE @ _VCP-COMMITTED? IF _VCP-STANDS _VCP-END EXIT THEN
    _VCP-GIVE-UP ;

: _VCP-BODY  ( -- )
    ['] _VCP-WORK CATCH IF VFS-E-IO THEN
    ?DUP IF _VCP-FAILED THEN ;

: _VCP-VALID?  ( copy -- flag )
    DUP 0= IF EXIT THEN  _VC.MAGIC @ _VCOPY-MAGIC = ;

: _VCP-WALK!  ( -- )  _VCP-C @ _VC.WALK @ _VW-W ! ;

\ A step runs as one VFS transaction.  A copy that has ended, either way,
\ gives back what it holds outside the VFS's guard, in the order every
\ replacement takes the two guards.
: _VCP-STEP  ( copy -- more? ior )
    DUP _VCP-C !
    _VCP-VALID? 0= IF 0 VFS-E-INVALID EXIT THEN
    _VCP-PHASE @ _VCOPY-IDLE = IF 0 0 EXIT THEN
    _VCP-WALK!
    ['] _VCP-BODY VFS-TRANSACTION
    _VCP-PHASE @ _VCOPY-IDLE = IF
        _VCP-RELEASE  0 _VCP-C @ _VC.IOR @ EXIT
    THEN
    -1 0 ;

: _VCP-CANCEL-BODY  ( -- )  0 _VCP-GIVE-UP ;

\ A copy before its commit is given up: a file's at once, whose answer
\ this is, a folder's by the steps that follow, the last of which
\ answers.  A move past its commit removes its source to the end.
: _VCP-CANCEL  ( copy -- ior )
    DUP _VCP-C !
    _VCP-VALID? 0= IF VFS-E-INVALID EXIT THEN
    _VCP-PHASE @ DUP _VCOPY-IDLE = SWAP _VCOPY-GIVING-UP = OR IF 0 EXIT THEN
    _VCP-PHASE @ _VCP-COMMITTED? IF VFS-E-BUSY EXIT THEN
    _VCP-WALK!
    ['] _VCP-CANCEL-BODY VFS-TRANSACTION
    _VCP-PHASE @ _VCOPY-IDLE = IF _VCP-RELEASE _VCP-C @ _VC.IOR @ EXIT THEN
    0 ;

: _VCP-PHASE-CLASS  ( phase -- class )
    DUP _VCOPY-IDLE = IF DROP VCOPY-P-IDLE EXIT THEN
    DUP _VCOPY-GIVING-UP = IF DROP VCOPY-P-GIVING-UP EXIT THEN
    DUP _VCP-COMMITTED? IF DROP VCOPY-P-FINISHING EXIT THEN
    DUP _VCOPY-COUNTING = IF DROP VCOPY-P-COUNTING EXIT THEN
    DUP _VCOPY-COMPARING = OVER _VCOPY-SETTLING = OR
    OVER _VCOPY-CHECKING = OR SWAP _VCOPY-PUBLISHING = OR
    IF VCOPY-P-CHECKING ELSE VCOPY-P-COPYING THEN ;

: _VCP-PROGRESS  ( copy -- files-done files bytes-done bytes phase )
    DUP _VCP-VALID? 0= IF DROP 0 0 0 0 VCOPY-P-IDLE EXIT THEN
    >R R@ _VC.FILES-DONE @ R@ _VC.FILES @ R@ _VC.BYTES-DONE @ R@ _VC.BYTES @
    R> _VC.STATE @ _VCP-PHASE-CLASS ;

\ =====================================================================
\  Starting a copy or a move
\ =====================================================================

\ What the source is, by its own name: a copy follows a final link to a
\ file, and takes a folder; a move takes a regular file or a folder.
: _VCI-KIND-BODY  ( -- ior )
    0 _VCI-KIND !
    _VCI-SA @ _VCI-SU @ _VCI-SV @ _VCP-ENTRY ?DUP IF NIP EXIT THEN
    DUP 0= IF DROP VFS-E-NOENT EXIT THEN
    IN.TYPE @ _VCI-KIND !  0 ;

\ Keep a copy of the source's path for the steps that name it again.
: _VCP-KEEP-SOURCE  ( -- ior )
    _VCP-C @ _VC.SRC-A @ IF 0 EXIT THEN
    _VCI-SU @ 1 MAX ALLOCATE ?DUP IF NIP VFS-E-NOMEM EXIT THEN
    DUP _VCP-C @ _VC.SRC-A !
    _VCI-SA @ SWAP _VCI-SU @ CMOVE
    _VCI-SU @ _VCP-C @ _VC.SRC-U !  0 ;

: _VCI-BODY  ( -- ior )
    ['] _VCI-START _VCP-CAUGHT DUP IF
        _VCP-DROP DROP _VCP-WHOLE _VCOPY-IDLE _VCP-PHASE !
    THEN ;

\ A folder: keep its path, take a walk record, name its hidden path for a
\ move across instances, check the destination, and start counting.
: _VCT-BEGIN  ( -- ior )
    _VCF-FOLDER _VCP-FLAG+
    _VCP-KEEP-SOURCE ?DUP IF EXIT THEN
    _VW-SIZE ALLOCATE ?DUP IF NIP VFS-E-NOMEM EXIT THEN
    DUP _VW-SIZE 0 FILL  DUP _VCP-C @ _VC.WALK !  _VW-W !
    _VCF-MOVE _VCP-FLAG? IF
        _VCP-SRC _VCP-HIDE VREPL-INIT IF VFS-E-INVALID EXIT THEN
        _VCF-HIDE _VCP-FLAG+
        _VCP-SRC$ _VCP-HIDE VREPL-DERIVE-PATHS! IF VFS-E-INVALID EXIT THEN
    THEN
    ['] _VCT-START-BODY _VCT-DO ?DUP IF EXIT THEN
    _VCT-STALE @ IF _VCF-STALE _VCP-FLAG+ THEN
    _VCOPY-COUNTING _VCP-PHASE !
    ['] _VCT-ROOTS _VCT-DO ;

\ _VCP-BEGIN ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u copy move? -- ior )
\   Start copying, or with MOVE? moving, SRC to DST in COPY.  The
\   destination is named before the VFS's guard is taken.  A copy that
\   cannot start leaves the record idle and holds nothing.
: _VCP-BEGIN  ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u copy move? -- ior )
    _VCI-MOVE ! _VCP-C ! _VCI-XU ! _VCI-XA ! _VCI-DV ! _VCI-DU ! _VCI-DA !
    _VCI-SV ! _VCI-SU ! _VCI-SA !
    _VCP-C @ 0= IF VFS-E-INVALID EXIT THEN
    _VCP-C @ _VC.MAGIC @ _VCOPY-MAGIC =
    _VCP-C @ _VC.STATE @ _VCOPY-IDLE <> AND IF VFS-E-BUSY EXIT THEN
    _VCI-SV @ 0= _VCI-DV @ 0= OR IF VFS-E-INVALID EXIT THEN
    _VCI-XA @ 0= _VCI-XU @ 2 < OR IF VFS-E-INVALID EXIT THEN
    _VCP-C @ _VCOPY-HEADER 0 FILL
    _VCOPY-MAGIC _VCP-C @ _VC.MAGIC !
    _VCI-SV @ _VCP-C @ _VC.SRC-VFS !
    _VCI-XA @ _VCP-C @ _VC.SCRATCH-A !
    _VCI-XU @ _VCP-C @ _VC.SCRATCH-U !
    _VCI-MOVE @ IF _VCF-MOVE _VCP-FLAG+ THEN
    0 _VW-W !
    _VCI-DA @ _VCI-DU @ _VCI-DV @ _VCP-C @ _VCP-NAME-PATH ?DUP IF
        _VCP-RELEASE EXIT
    THEN
    ['] _VCI-KIND-BODY _VCT-DO ?DUP IF _VCP-RELEASE EXIT THEN
    _VCI-MOVE @ IF
        _VCI-KIND @ DUP VFS-T-FILE <> SWAP VFS-T-DIR <> AND IF
            _VCP-RELEASE VFS-E-INVALID EXIT
        THEN
        _VCP-KEEP-SOURCE ?DUP IF _VCP-RELEASE EXIT THEN
        _VCI-SV @ _VCI-DV @ = IF _VCOPY-RENAMING _VCP-PHASE ! 0 EXIT THEN
    THEN
    _VCI-KIND @ VFS-T-DIR = IF
        _VCT-BEGIN
    ELSE
        ['] _VCI-BODY VFS-TRANSACTION
    THEN
    DUP IF
        _VW-ABANDON  _VCOPY-IDLE _VCP-PHASE !  _VCP-RELEASE
    THEN ;

\ =====================================================================
\  Copying and moving to the end
\ =====================================================================

\ The record VFS-COPY and VFS-MOVE step.  It is idle between calls.
CREATE _VCP-RECORD VCOPY-SIZE ALLOT
_VCP-RECORD VCOPY-SIZE 0 FILL

\ _VCP-RUN ( copy -- ior )   Step a started copy to its end.
: _VCP-RUN  ( copy -- ior )
    BEGIN DUP _VCP-STEP SWAP WHILE DROP REPEAT NIP ;

: _VCP-COPY-INIT  ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u copy -- ior )
    0 _VCP-BEGIN ;

: _VCP-MOVE-INIT  ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u copy -- ior )
    -1 _VCP-BEGIN ;

: _VCP-COPY  ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u -- ior )
    _VCP-RECORD 0 _VCP-BEGIN ?DUP IF EXIT THEN  _VCP-RECORD _VCP-RUN ;

: _VCP-MOVE  ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u -- ior )
    _VCP-RECORD -1 _VCP-BEGIN ?DUP IF EXIT THEN  _VCP-RECORD _VCP-RUN ;

\ =====================================================================
\  Copying and moving between places
\ =====================================================================

\ The volume paths the places bind.  The copy keeps its own copies once
\ it has started.
CREATE _VCPL-SRC  VFS-PATH-MAX ALLOT
CREATE _VCPL-DST  VFS-PATH-MAX ALLOT

VARIABLE _VCPL-SA  VARIABLE _VCPL-SN  VARIABLE _VCPL-SP
VARIABLE _VCPL-DA  VARIABLE _VCPL-DN  VARIABLE _VCPL-DP
VARIABLE _VCPL-XA  VARIABLE _VCPL-XU
VARIABLE _VCPL-SV  VARIABLE _VCPL-SU
VARIABLE _VCPL-DV  VARIABLE _VCPL-DU
VARIABLE _VCPL-C   VARIABLE _VCPL-MOVE

: _VCPL-ARGS  ( src-a src-u src-place dst-a dst-u dst-place scratch-a scratch-u -- )
    _VCPL-XU ! _VCPL-XA ! _VCPL-DP ! _VCPL-DN ! _VCPL-DA !
    _VCPL-SP ! _VCPL-SN ! _VCPL-SA ! ;

\ _VCPL-BIND ( xt -- ior )
\   Bind the source with XT, PLACE-BIND or PLACE-BIND-WRITE, and the
\   destination for writing, so a read-only place refuses it.
: _VCPL-BIND  ( xt -- ior )
    >R _VCPL-SA @ _VCPL-SN @ _VCPL-SP @ _VCPL-SRC VFS-PATH-MAX R> EXECUTE
    ?DUP IF NIP NIP EXIT THEN _VCPL-SU ! _VCPL-SV !
    _VCPL-DA @ _VCPL-DN @ _VCPL-DP @ _VCPL-DST VFS-PATH-MAX
    PLACE-BIND-WRITE ?DUP IF NIP NIP EXIT THEN _VCPL-DU ! _VCPL-DV !
    0 ;

: _VCPL-BOUND  ( -- src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u )
    _VCPL-SRC _VCPL-SU @ _VCPL-SV @
    _VCPL-DST _VCPL-DU @ _VCPL-DV @
    _VCPL-XA @ _VCPL-XU @ ;

\ A move also changes the source's place, so that place must be
\ writable too.
: _VCPL-BEGIN  ( src-a src-u src-place dst-a dst-u dst-place scratch-a scratch-u copy move? -- ior )
    _VCPL-MOVE ! _VCPL-C !  _VCPL-ARGS
    _VCPL-MOVE @ IF ['] PLACE-BIND-WRITE ELSE ['] PLACE-BIND THEN
    _VCPL-BIND ?DUP IF EXIT THEN
    _VCPL-BOUND _VCPL-C @ _VCPL-MOVE @ _VCP-BEGIN ;

: _VCP-PLACE-COPY-INIT  ( src-a src-u src-place dst-a dst-u dst-place scratch-a scratch-u copy -- ior )
    0 _VCPL-BEGIN ;

: _VCP-PLACE-MOVE-INIT  ( src-a src-u src-place dst-a dst-u dst-place scratch-a scratch-u copy -- ior )
    -1 _VCPL-BEGIN ;

: _VCP-PLACE-COPY  ( src-a src-u src-place dst-a dst-u dst-place scratch-a scratch-u -- ior )
    _VCP-RECORD 0 _VCPL-BEGIN ?DUP IF EXIT THEN  _VCP-RECORD _VCP-RUN ;

: _VCP-PLACE-MOVE  ( src-a src-u src-place dst-a dst-u dst-place scratch-a scratch-u -- ior )
    _VCP-RECORD -1 _VCPL-BEGIN ?DUP IF EXIT THEN  _VCP-RECORD _VCP-RUN ;

\ =====================================================================
\  Public guarded entry points
\ =====================================================================

' _VCP-COPY-INIT        CONSTANT _vcopy-init-xt
' _VCP-MOVE-INIT        CONSTANT _vmove-init-xt
' _VCP-PLACE-COPY-INIT  CONSTANT _vcopy-place-copy-init-xt
' _VCP-PLACE-MOVE-INIT  CONSTANT _vcopy-place-move-init-xt
' _VCP-STEP             CONSTANT _vcopy-step-xt
' _VCP-CANCEL           CONSTANT _vcopy-cancel-xt
' _VCP-PROGRESS         CONSTANT _vcopy-progress-xt
' _VCP-COPY             CONSTANT _vcopy-copy-xt
' _VCP-MOVE             CONSTANT _vcopy-move-xt
' _VCP-PLACE-COPY       CONSTANT _vcopy-place-copy-xt
' _VCP-PLACE-MOVE       CONSTANT _vcopy-place-move-xt

\ VCOPY-INIT ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u copy -- ior )
\   Start copying the file or folder SRC on SRC-VFS to the absolute path
\   DST on DST-VFS, in COPY, a VCOPY-SIZE record, through SCRATCH, at
\   least two bytes, which the caller keeps until the copy ends.
: VCOPY-INIT    _vcopy-init-xt _vcopy-guard WITH-GUARD ;

\ VMOVE-INIT ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u copy -- ior )
\   Start moving the file or folder SRC, by its own name, to DST.
: VMOVE-INIT    _vmove-init-xt _vcopy-guard WITH-GUARD ;

\ PLACE-COPY-INIT  PLACE-MOVE-INIT
\   ( src-a src-u src-place dst-a dst-u dst-place scratch-a scratch-u copy -- ior )
\   Start a copy or a move between places.
: PLACE-COPY-INIT  _vcopy-place-copy-init-xt _vcopy-guard WITH-GUARD ;
: PLACE-MOVE-INIT  _vcopy-place-move-init-xt _vcopy-guard WITH-GUARD ;

\ VCOPY-STEP ( copy -- more? ior )
\   Do the copy's next step.  MORE? is true while steps remain; the step
\   that ends the copy answers its IOR, and a step after that 0 0.
: VCOPY-STEP    _vcopy-step-xt _vcopy-guard WITH-GUARD ;

\ VCOPY-CANCEL ( copy -- ior )
\   Give a copy up before its commit; see _VCP-CANCEL.
: VCOPY-CANCEL  _vcopy-cancel-xt _vcopy-guard WITH-GUARD ;

\ VCOPY-PROGRESS ( copy -- files-done files bytes-done bytes phase )
\   How far the copy has come, and VCOPY-P-* for what it is doing.
: VCOPY-PROGRESS  _vcopy-progress-xt _vcopy-guard WITH-GUARD ;

\ VFS-COPY ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u -- ior )
\   Copy a file, or a folder with all it holds, to the end.
: VFS-COPY      _vcopy-copy-xt _vcopy-guard WITH-GUARD ;

\ VFS-MOVE ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u -- ior )
\   Move a file or a folder: one rename inside an instance; across two, a
\   copy, then the source's removal and a barrier.
: VFS-MOVE      _vcopy-move-xt _vcopy-guard WITH-GUARD ;

\ PLACE-COPY ( src-a src-u src-place dst-a dst-u dst-place scratch-a scratch-u -- ior )
\   Copy a file or a folder of one place to a path of another, or the
\   same, place.
: PLACE-COPY    _vcopy-place-copy-xt _vcopy-guard WITH-GUARD ;

\ PLACE-MOVE ( src-a src-u src-place dst-a dst-u dst-place scratch-a scratch-u -- ior )
\   Move a file or a folder between places; both must be writable.
: PLACE-MOVE    _vcopy-place-move-xt _vcopy-guard WITH-GUARD ;
