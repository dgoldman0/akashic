\ =====================================================================
\  vfs-copy.f - Copying and moving files and folders, between volumes too
\ =====================================================================
\  Megapad-64 / KDOS Forth      Prefix: VCOPY- VFS- PLACE- / _VCP- _VC.
\                                       _VCT- _VW- _VMV-
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
\  A folder copies the same way at the scale of its tree: the whole tree
\  goes under the stage name, one barrier follows, every file is read
\  back, and the stage folder's rename is the commit, so a failure never
\  leaves part of a folder under its final name.  A folder of files and
\  folders copies; a link or a device in it refuses the copy.
\
\  The destination follows its volume's rules, as a replacement's paths
\  do: names as long as the volume takes, and a path of VFS-PATH-MAX.
\
\  The stage's name is the reserved `.s-` name that VREPL-DERIVE-PATHS!
\  (vfs-replace.f) derives from the final path.  A stage a crash leaves
\  is therefore a hidden file, and the same copy, tried again, finds it
\  under the same name and removes it before it writes a new one.
\
\  VCOPY-STEP moves one chunk of a file, so an applet can step a long
\  copy from its tick; VFS-COPY runs a file's or a folder's copy to the
\  end.  VFS-MOVE renames inside one instance, a file or a folder with
\  all it holds, and across two it copies, then removes the source and
\  takes a barrier; a folder first takes its own stage name, so it leaves
\  its folder at once, and is then removed.  PLACE-COPY and PLACE-MOVE
\  bind both paths in their places first, so a read-only place refuses
\  to be written.
\
\  Public API:
\    VCOPY-SIZE   ( -- n )   bytes of a copy record
\    VCOPY-INIT   ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u copy -- ior )
\    VCOPY-STEP   ( copy -- more? ior )
\    VCOPY-CANCEL ( copy -- ior )
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

0x56434F5059303031 CONSTANT _VCOPY-MAGIC     \ "VCOPY001"

\ Where a copy stands between two steps.  PUBLISHED lasts only from the
\ rename to the sync after it, inside the last step.
0 CONSTANT _VCOPY-IDLE
1 CONSTANT _VCOPY-WRITING
2 CONSTANT _VCOPY-COMPARING
3 CONSTANT _VCOPY-PUBLISHED

: _VC.MAGIC      ( copy -- a ) ;
: _VC.STATE      ( copy -- a )  8 + ;
: _VC.SRC-VFS    ( copy -- a ) 16 + ;
: _VC.DST-VFS    ( copy -- a ) 24 + ;
: _VC.SRC-FD     ( copy -- a ) 32 + ;
: _VC.STAGE-FD   ( copy -- a ) 40 + ;
: _VC.SIZE       ( copy -- a ) 48 + ;
: _VC.POS        ( copy -- a ) 56 + ;
: _VC.SCRATCH-A  ( copy -- a ) 64 + ;
: _VC.SCRATCH-U  ( copy -- a ) 72 + ;
\ A replacement descriptor that holds the final path and the stage's
\ while a copy runs.  Its paths are given back when the copy ends.
: _VC.REPL       ( copy -- a ) 80 + ;
80 CONSTANT _VCOPY-HEADER

_VCOPY-HEADER VREPL-SIZE + CONSTANT VCOPY-SIZE

GUARD _vcopy-guard

\ The record a call works on, under the guard.
VARIABLE _VCP-C

: _VCP-REPL  ( -- repl )  _VCP-C @ _VC.REPL ;
: _VCP-SRC   ( -- vfs )   _VCP-C @ _VC.SRC-VFS @ ;
: _VCP-DST   ( -- vfs )   _VCP-C @ _VC.DST-VFS @ ;

: _VCP-NAME$        ( -- a u )  _VCP-REPL VREPL-TARGET-NAME$ ;
: _VCP-STAGE-NAME$  ( -- a u )  _VCP-REPL VREPL-STAGE-NAME$ ;

\ The folder that holds the final name and the stage, "/" for the root.
: _VCP-FOLDER$  ( -- a u )  _VCP-REPL VREPL-FOLDER$ ;

\ _VCP-NAME-PATH ( dst-a dst-u dst-vfs copy -- ior )
\   Point COPY at the final path DST on DST-VFS and derive its stage.
\   VFS-E-INVALID when the replacement library refuses the path.
: _VCP-NAME-PATH  ( dst-a dst-u dst-vfs copy -- ior )
    DUP _VCP-C !
    2DUP _VC.DST-VFS !
    _VC.REPL VREPL-INIT IF 2DROP VFS-E-INVALID EXIT THEN
    _VCP-REPL VREPL-DERIVE-PATHS! IF VFS-E-INVALID EXIT THEN
    0 ;

\ _VCP-RELEASE ( -- )   Give back the paths of the copy's descriptor.
: _VCP-RELEASE  ( -- )  _VCP-REPL VREPL-FINI DROP ;

\ =====================================================================
\  Answers
\ =====================================================================

VFS-IOR-F-PARTIAL 24 LSHIFT CONSTANT _VCP-PARTIAL-BIT

\ A copy that fails leaves nothing, so its answer never carries
\ VFS-IOR-F-PARTIAL, whatever a binding reported.
: _VCP-WHOLE   ( ior -- ior' )  _VCP-PARTIAL-BIT INVERT AND ;

\ The destination file stands though a later step failed.
: _VCP-STANDS  ( ior -- ior' )  _VCP-PARTIAL-BIT OR ;

\ _VCP-CAUGHT ( xt -- ior )
\   Run XT, whose effect is ( -- ior ).  A throw answers VFS-E-IO.
: _VCP-CAUGHT  ( xt -- ior )  CATCH IF VFS-E-IO THEN ;

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
\  Giving a copy up
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
    _VCP-C @ _VC.STATE @ DUP _VCOPY-WRITING = SWAP _VCOPY-COMPARING = OR IF
        ['] _VCX-RM-STAGE _VCP-CAUGHT _VCX-NOTE
        ['] _VCX-SYNC _VCP-CAUGHT _VCX-NOTE
    THEN
    _VCOPY-IDLE _VCP-C @ _VC.STATE !
    _VCX-IOR @ ;

\ _VCP-FAIL ( ior -- ior' )   Give the copy up and answer IOR whole.
: _VCP-FAIL  ( ior -- ior' )  _VCP-DROP DROP _VCP-WHOLE ;

\ =====================================================================
\  Starting a copy
\ =====================================================================

VARIABLE _VCI-SA   VARIABLE _VCI-SU   VARIABLE _VCI-SV
VARIABLE _VCI-DA   VARIABLE _VCI-DU   VARIABLE _VCI-DV
VARIABLE _VCI-XA   VARIABLE _VCI-XU

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
    VFS-SIZE _VCP-C @ _VC.SIZE !
    _VCP-REPL VREPL-TARGET$ _VCP-DST _VCP-ENTRY ?DUP IF NIP EXIT THEN
    IF VFS-E-EXISTS EXIT THEN
    _VCP-REPL VREPL-STAGE$ _VCP-DST _VCP-ENTRY ?DUP IF NIP EXIT THEN
    ?DUP IF _VCI-STALE ?DUP IF EXIT THEN THEN
    _VCP-FOLDER ?DUP IF NIP EXIT THEN
    _VCI-MAKE-STAGE ?DUP IF EXIT THEN
    _VCOPY-WRITING _VCP-C @ _VC.STATE !
    _VCP-REPL VREPL-STAGE$ VFS-FF-WRITE _VCP-DST VFS-OPEN? ?DUP IF NIP EXIT THEN
    _VCP-C @ _VC.STAGE-FD !
    0 ;

: _VCI-BODY  ( -- ior )
    ['] _VCI-START _VCP-CAUGHT DUP IF _VCP-FAIL THEN ;

: _VCP-INIT  ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u copy -- ior )
    _VCP-C ! _VCI-XU ! _VCI-XA ! _VCI-DV ! _VCI-DU ! _VCI-DA !
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
    \ The stage is named before the VFS's guard is taken.
    _VCI-DA @ _VCI-DU @ _VCI-DV @ _VCP-C @ _VCP-NAME-PATH ?DUP IF
        _VCP-RELEASE EXIT
    THEN
    ['] _VCI-BODY VFS-TRANSACTION DUP IF _VCP-RELEASE THEN ;

\ =====================================================================
\  Stepping a copy
\ =====================================================================

VARIABLE _VCS-N
VARIABLE _VCS-HALF

: _VCS-FD-CLOSE  ( field -- ior )  DUP @ 0 ROT ! VFS-CLOSE? ;

\ Move the next chunk, as much as the scratch holds, into the stage.
: _VCS-WRITE  ( -- more? ior )
    _VCP-C @ _VC.SIZE @ _VCP-C @ _VC.POS @ -
    _VCP-C @ _VC.SCRATCH-U @ MIN _VCS-N !
    _VCP-C @ _VC.SCRATCH-A @ _VCS-N @ _VCP-C @ _VC.SRC-FD @ VFS-READ-EXACT
    ?DUP IF 0 SWAP EXIT THEN
    _VCP-C @ _VC.SCRATCH-A @ _VCS-N @ _VCP-C @ _VC.STAGE-FD @ VFS-WRITE-EXACT
    ?DUP IF 0 SWAP EXIT THEN
    _VCS-N @ _VCP-C @ _VC.POS +!
    -1 0 ;

\ Every byte is in the stage: close it, take a barrier, and open it
\ again to read it back against the source from the start.
: _VCS-WRITTEN  ( -- more? ior )
    _VCP-C @ _VC.STAGE-FD _VCS-FD-CLOSE ?DUP IF 0 SWAP EXIT THEN
    _VCP-DST VFS-BARRIER ?DUP IF 0 SWAP EXIT THEN
    _VCP-REPL VREPL-STAGE$ VFS-FF-READ _VCP-DST VFS-OPEN?
    ?DUP IF NIP 0 SWAP EXIT THEN
    DUP _VCP-C @ _VC.STAGE-FD !
    VFS-SIZE _VCP-C @ _VC.SIZE @ <> IF 0 VFS-E-CORRUPT EXIT THEN
    _VCP-C @ _VC.SRC-FD @ VFS-SIZE _VCP-C @ _VC.SIZE @ <> IF
        0 VFS-E-CORRUPT EXIT
    THEN
    0 _VCP-C @ _VC.SRC-FD @ VFS-SEEK? ?DUP IF 0 SWAP EXIT THEN
    0 _VCP-C @ _VC.POS !
    _VCOPY-COMPARING _VCP-C @ _VC.STATE !
    -1 0 ;

\ Compare the next half of the scratch's worth of the stage with the
\ source.
: _VCS-COMPARE  ( -- more? ior )
    _VCP-C @ _VC.SCRATCH-U @ 2 / _VCS-HALF !
    _VCP-C @ _VC.SIZE @ _VCP-C @ _VC.POS @ - _VCS-HALF @ MIN _VCS-N !
    _VCP-C @ _VC.SCRATCH-A @ _VCS-N @ _VCP-C @ _VC.SRC-FD @ VFS-READ-EXACT
    ?DUP IF 0 SWAP EXIT THEN
    _VCP-C @ _VC.SCRATCH-A @ _VCS-HALF @ + _VCS-N @
    _VCP-C @ _VC.STAGE-FD @ VFS-READ-EXACT ?DUP IF 0 SWAP EXIT THEN
    _VCP-C @ _VC.SCRATCH-A @ _VCS-N @
    _VCP-C @ _VC.SCRATCH-A @ _VCS-HALF @ + _VCS-N @
    COMPARE IF 0 VFS-E-CORRUPT EXIT THEN
    _VCS-N @ _VCP-C @ _VC.POS +!
    -1 0 ;

\ The stage reads back as the source: rename it to the final name, which
\ must still be free, and take a barrier.  The rename is the commit.
: _VCS-PUBLISH  ( -- more? ior )
    _VCP-C @ _VC.SRC-FD _VCS-FD-CLOSE ?DUP IF 0 SWAP EXIT THEN
    _VCP-C @ _VC.STAGE-FD _VCS-FD-CLOSE ?DUP IF 0 SWAP EXIT THEN
    _VCP-REPL VREPL-STAGE$ _VCP-DST _VCP-ENTRY ?DUP IF NIP 0 SWAP EXIT THEN
    DUP 0= IF DROP 0 VFS-E-NOENT EXIT THEN
    >R _VCP-NAME$ R@ R> IN.PARENT @ VFS-RN-NOREPLACE _VCP-DST VFS-RENAME-AT
    ?DUP IF 0 SWAP EXIT THEN
    _VCOPY-PUBLISHED _VCP-C @ _VC.STATE !
    _VCP-DST VFS-BARRIER ?DUP IF 0 SWAP EXIT THEN
    _VCOPY-IDLE _VCP-C @ _VC.STATE !
    0 0 ;

: _VCS-WORK  ( -- more? ior )
    _VCP-C @ _VC.STATE @ CASE
        _VCOPY-WRITING OF
            _VCP-C @ _VC.POS @ _VCP-C @ _VC.SIZE @ < IF
                _VCS-WRITE
            ELSE
                _VCS-WRITTEN
            THEN
        ENDOF
        _VCOPY-COMPARING OF
            _VCP-C @ _VC.POS @ _VCP-C @ _VC.SIZE @ < IF
                _VCS-COMPARE
            ELSE
                _VCS-PUBLISH
            THEN
        ENDOF
        >R 0 0 R>
    ENDCASE ;

\ A failure before the rename gives the copy up.  A failure after it,
\ in the barrier, leaves the copy standing, and the answer says so.
: _VCS-BODY  ( -- more? ior )
    ['] _VCS-WORK CATCH IF 0 VFS-E-IO THEN
    DUP 0= IF EXIT THEN
    NIP
    _VCP-C @ _VC.STATE @ _VCOPY-PUBLISHED = IF
        _VCOPY-IDLE _VCP-C @ _VC.STATE !
        _VCP-STANDS 0 SWAP EXIT
    THEN
    _VCP-FAIL 0 SWAP ;

: _VCP-VALID?  ( copy -- flag )
    DUP 0= IF EXIT THEN  _VC.MAGIC @ _VCOPY-MAGIC = ;

\ A copy that has ended, either way, gives its paths back outside the
\ VFS's guard, in the order every replacement takes the two guards.
: _VCP-STEP  ( copy -- more? ior )
    DUP _VCP-C !
    _VCP-VALID? 0= IF 0 VFS-E-INVALID EXIT THEN
    _VCP-C @ _VC.STATE @ _VCOPY-IDLE = IF 0 0 EXIT THEN
    ['] _VCS-BODY VFS-TRANSACTION
    OVER 0= IF _VCP-RELEASE THEN ;

: _VCP-CANCEL  ( copy -- ior )
    DUP _VCP-C !
    _VCP-VALID? 0= IF VFS-E-INVALID EXIT THEN
    _VCP-C @ _VC.STATE @ _VCOPY-IDLE = IF 0 EXIT THEN
    ['] _VCP-DROP VFS-TRANSACTION _VCP-RELEASE ;

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
\  destination folder, whose name limit and path length it checks.

\ One folder of the walk: its entries and the next one to visit, and the
\ lengths of the source and destination paths that name it.
: _VW.UP     ( level -- a ) ;
: _VW.BLOCK  ( level -- a )  8 + ;
: _VW.COUNT  ( level -- a ) 16 + ;
: _VW.NEXT   ( level -- a ) 24 + ;
: _VW.SU     ( level -- a ) 32 + ;
: _VW.DU     ( level -- a ) 40 + ;
48 CONSTANT _VW-LEVEL-SIZE

\ An entry as it was listed: its name and its kind.  The names follow the
\ entries in the same block.
: _VE.A  ( entry -- a ) ;
: _VE.U  ( entry -- a )  8 + ;
: _VE.T  ( entry -- a ) 16 + ;
24 CONSTANT _VE-SIZE

CREATE _VW-SRC  VFS-PATH-MAX ALLOT   VARIABLE _VW-SU
CREATE _VW-DST  VFS-PATH-MAX ALLOT   VARIABLE _VW-DU
VARIABLE _VW-SV      \ the instance the walk lists
VARIABLE _VW-DV      \ the instance the destination paths are on, or 0
VARIABLE _VW-LIMIT   \ its name limit
VARIABLE _VW-SLACK   \ how much a destination path grows when its stage is renamed
VARIABLE _VW-TOP     \ the deepest level; 0 when no walk runs
0 _VW-TOP !
VARIABLE _VW-ENTRY   \ the entry the walk visits

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
: _VW-ABANDON  ( -- )  BEGIN _VW-TOP @ WHILE _VW-POP REPEAT ;

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

VARIABLE _VCP-KIND-T
VARIABLE _VCT-XT

\ _VCT-DO ( xt -- ior )
\   Run XT ( -- ior ) as one VFS transaction; a throw answers VFS-E-IO.
: _VCT-DO-BODY  ( -- ior )  _VCT-XT @ _VCP-CAUGHT ;
: _VCT-DO  ( xt -- ior )  _VCT-XT !  ['] _VCT-DO-BODY VFS-TRANSACTION ;

\ What the walk's source path names, in _VCP-KIND-T.
: _VCT-KIND-BODY  ( -- ior )
    _VW-SRC _VW-SU @ _VW-SV @ _VCP-ENTRY ?DUP IF NIP EXIT THEN
    DUP 0= IF DROP VFS-E-NOENT EXIT THEN
    IN.TYPE @ _VCP-KIND-T !  0 ;

: _VCT-RM-PATH  ( -- ior )  _VW-SRC _VW-SU @ _VW-SV @ VFS-RM ;

VARIABLE _VCR-A  VARIABLE _VCR-U  VARIABLE _VCR-V

\ _VCT-RM-TREE ( a u vfs -- ior )
\   Remove the folder A U on VFS and everything in it, each entry before
\   the folder that holds it, or the file A U.  Each removal is a call of
\   its own, and the first that fails ends the walk, leaving the rest.
: _VCT-RM-TREE  ( a u vfs -- ior )
    _VCR-V ! _VCR-U ! _VCR-A !
    _VW-ABANDON
    _VCR-U @ VFS-PATH-MAX > IF VFS-E-NAMETOOLONG EXIT THEN
    _VCR-A @ _VW-SRC _VCR-U @ CMOVE  _VCR-U @ _VW-SU !  _VCR-V @ _VW-SV !
    ['] _VCT-KIND-BODY _VCT-DO ?DUP IF EXIT THEN
    _VCP-KIND-T @ VFS-T-DIR <> IF ['] _VCT-RM-PATH _VCT-DO EXIT THEN
    _VCR-A @ _VCR-U @ _VCR-V @ 0 0 0 _VW-ROOT ?DUP IF EXIT THEN
    BEGIN
        _VW-NEXT ?DUP IF NIP _VW-ABANDON EXIT THEN
        CASE
            _VW-FOLDER OF _VW-PUSH ENDOF
            _VW-END OF ['] _VCT-RM-PATH _VCT-DO EXIT ENDOF
            \ A file, a link or a device, or a folder now empty.
            >R ['] _VCT-RM-PATH _VCT-DO R>
        ENDCASE
        ?DUP IF _VW-ABANDON EXIT THEN
    AGAIN ;

\ =====================================================================
\  Copying a folder
\ =====================================================================
\
\  A folder copies as a file does, at the scale of its tree.  The tree is
\  written under the stage name in the destination folder, one barrier
\  follows, every file is read back against its source, and only then is
\  the stage folder renamed to its final name, which is the commit, and
\  another barrier taken.  A failure before the rename removes the stage
\  tree, so the final name never holds part of a folder.  A folder holds
\  files and folders only: a link or a device in it refuses the copy, as
\  a name or a path its destination does not take does.

\ The record VFS-COPY steps, and whose replacement descriptor names a
\ move's destination and a folder's stage.  It is idle between calls.
CREATE _VCP-RECORD VCOPY-SIZE ALLOT
_VCP-RECORD VCOPY-SIZE 0 FILL

VARIABLE _VCT-SA  VARIABLE _VCT-SU  VARIABLE _VCT-SV
VARIABLE _VCT-DA  VARIABLE _VCT-DU  VARIABLE _VCT-DV
VARIABLE _VCT-XA  VARIABLE _VCT-XU
VARIABLE _VCT-SFD  VARIABLE _VCT-DFD   \ the file copied or compared, and its copy
VARIABLE _VCT-SIZE  VARIABLE _VCT-POS  VARIABLE _VCT-N  VARIABLE _VCT-HALF
VARIABLE _VCT-STAGED   \ true while the stage folder stands
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
        _VCT-DEPTH @ _VCT-SV @ V.ICOUNT @ U< 0= IF TRUE EXIT THEN
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
    _VCT-SV @ _VCP-DST = IF
        _VCT-INSIDE? IF VFS-E-INVALID EXIT THEN
    ELSE DROP THEN
    _VCP-REPL VREPL-STAGE$ _VCP-DST _VCP-ENTRY ?DUP IF NIP EXIT THEN
    ?DUP IF _VCT-SRC-IN @ = IF VFS-E-INVALID EXIT THEN -1 _VCT-STALE ! THEN
    0 ;

: _VCT-START-BODY  ( -- ior )
    0 _VCT-STALE !
    _VCT-SA @ _VCT-SU @ _VCT-SV @ _VCP-ENTRY ?DUP IF NIP EXIT THEN
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
    >R _VW-DST _VW-TOP @ _VW.DU @ _VCT-DV @ VFS-RESOLVE?
    ?DUP IF NIP R> DROP EXIT THEN
    DUP IN.TYPE @ VFS-T-DIR <> IF DROP R> DROP VFS-E-NOTDIR EXIT THEN
    _VCT-DV @ V.CWD @ _VCT-CWD !  _VCT-DV @ V.CWD !
    R> CATCH
    _VCT-CWD @ _VCT-DV @ V.CWD !
    IF VFS-E-IO THEN ;

: _VCT-NAME$  ( -- a u )  _VW-ENTRY @ DUP _VE.A @ SWAP _VE.U @ ;
: _VCT-MKDIR   ( -- ior )  _VCT-NAME$ _VCT-DV @ VFS-MKDIR ;
: _VCT-MKFILE  ( -- ior )  _VCT-NAME$ _VCT-DV @ VFS-MKFILE? NIP ;

: _VCT-FOLDER-BODY  ( -- ior )  ['] _VCT-MKDIR _VCT-AT-PARENT ;

\ A file of the tree: create its copy, empty, and open both.
: _VCT-FILE-OPEN  ( -- ior )
    ['] _VCT-MKFILE _VCT-AT-PARENT ?DUP IF EXIT THEN
    _VW-SRC _VW-SU @ VFS-FF-READ _VCT-SV @ VFS-OPEN? ?DUP IF NIP EXIT THEN
    DUP _VCT-SFD !  VFS-SIZE _VCT-SIZE !  0 _VCT-POS !
    _VW-DST _VW-DU @ VFS-FF-WRITE _VCT-DV @ VFS-OPEN? ?DUP IF NIP EXIT THEN
    _VCT-DFD !  0 ;

\ Move the next chunk, as much as the scratch holds.
: _VCT-WRITE-CHUNK  ( -- ior )
    _VCT-SIZE @ _VCT-POS @ - _VCT-XU @ MIN _VCT-N !
    _VCT-XA @ _VCT-N @ _VCT-SFD @ VFS-READ-EXACT ?DUP IF EXIT THEN
    _VCT-XA @ _VCT-N @ _VCT-DFD @ VFS-WRITE-EXACT ?DUP IF EXIT THEN
    _VCT-N @ _VCT-POS +!  0 ;

: _VCT-COPY-FILE  ( -- ior )
    ['] _VCT-FILE-OPEN _VCT-DO ?DUP IF EXIT THEN
    BEGIN _VCT-POS @ _VCT-SIZE @ < WHILE
        ['] _VCT-WRITE-CHUNK _VCT-DO ?DUP IF EXIT THEN
    REPEAT
    ['] _VCT-FILES-CLOSE _VCT-DO ;

\ _VCT-WRITE-TREE ( -- ior )   Copy every entry of the tree into the stage.
: _VCT-WRITE-TREE  ( -- ior )
    BEGIN
        _VW-NEXT ?DUP IF NIP EXIT THEN
        CASE
            _VW-END OF 0 EXIT ENDOF
            _VW-FOLDER OF
                ['] _VCT-FOLDER-BODY _VCT-DO ?DUP IF EXIT THEN
                _VW-PUSH ?DUP IF EXIT THEN
            ENDOF
            _VW-FILE OF _VCT-COPY-FILE ?DUP IF EXIT THEN ENDOF
            _VW-OTHER OF VFS-E-UNSUPPORTED EXIT ENDOF
        ENDCASE
    AGAIN ;

\ A copy that differs from its source, or is missing, is corrupt; the
\ source gone is the source gone.
: _VCT-CORRUPT  ( ior -- ior' )
    DUP VFS-IOR-REASON VFS-R-NOENT = IF DROP VFS-E-CORRUPT THEN ;

: _VCT-CHECK-FOLDER  ( -- ior )
    _VW-DST _VW-DU @ _VCT-DV @ _VCP-ENTRY ?DUP IF NIP _VCT-CORRUPT EXIT THEN
    DUP 0= IF DROP VFS-E-CORRUPT EXIT THEN
    IN.TYPE @ VFS-T-DIR <> IF VFS-E-CORRUPT EXIT THEN  0 ;

: _VCT-CHECK-OPEN  ( -- ior )
    _VW-SRC _VW-SU @ VFS-FF-READ _VCT-SV @ VFS-OPEN? ?DUP IF NIP EXIT THEN
    DUP _VCT-SFD !  VFS-SIZE _VCT-SIZE !  0 _VCT-POS !
    _VW-DST _VW-DU @ VFS-FF-READ _VCT-DV @ VFS-OPEN?
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
    _VCT-N @ _VCT-POS +!  0 ;

: _VCT-CHECK-FILE  ( -- ior )
    ['] _VCT-CHECK-OPEN _VCT-DO ?DUP IF EXIT THEN
    BEGIN _VCT-POS @ _VCT-SIZE @ < WHILE
        ['] _VCT-CHECK-CHUNK _VCT-DO ?DUP IF EXIT THEN
    REPEAT
    ['] _VCT-FILES-CLOSE _VCT-DO ;

\ _VCT-CHECK-TREE ( -- ior )
\   Read the whole copy back against its source.  An entry of another
\   kind now is a source that changed after it was copied.
: _VCT-CHECK-TREE  ( -- ior )
    BEGIN
        _VW-NEXT ?DUP IF NIP EXIT THEN
        CASE
            _VW-END OF 0 EXIT ENDOF
            _VW-FOLDER OF
                ['] _VCT-CHECK-FOLDER _VCT-DO ?DUP IF EXIT THEN
                _VW-PUSH ?DUP IF EXIT THEN
            ENDOF
            _VW-FILE OF _VCT-CHECK-FILE ?DUP IF EXIT THEN ENDOF
            _VW-OTHER OF VFS-E-CORRUPT EXIT ENDOF
        ENDCASE
    AGAIN ;

\ Walk the source, mirrored under the stage folder.  A path grows by
\ the final name's length less the stage name's once the stage is
\ renamed, and is checked for that length.
: _VCT-ROOTS  ( -- ior )
    _VCP-REPL VREPL-TARGET$ NIP _VCP-REPL VREPL-STAGE$ NIP - 0 MAX _VW-SLACK !
    _VCT-SA @ _VCT-SU @ _VCT-SV @ _VCP-REPL VREPL-STAGE$ _VCP-DST _VW-ROOT ;

: _VCT-BARRIER  ( -- ior )  _VCP-DST VFS-BARRIER ;

\ The stage reads back as the source: rename it to the final name.
: _VCT-PUBLISH-BODY  ( -- ior )
    _VCP-REPL VREPL-STAGE$ _VCP-DST _VCP-ENTRY ?DUP IF NIP EXIT THEN
    DUP 0= IF DROP VFS-E-NOENT EXIT THEN
    >R _VCP-NAME$ R@ R> IN.PARENT @ VFS-RN-NOREPLACE _VCP-DST VFS-RENAME-AT ;

\ _VCT-GIVE-UP ( ior -- ior' )
\   End a folder's copy before its rename: close its files, leave the
\   walk, remove the stage tree and take a barrier.  The answer is IOR,
\   whole.  A stage that cannot be removed stays a hidden folder until
\   the same copy is tried again.
: _VCT-GIVE-UP  ( ior -- ior' )
    ['] _VCT-FILES-CLOSE _VCP-CAUGHT DROP
    _VW-ABANDON
    _VCT-STAGED @ IF
        0 _VCT-STAGED !
        _VCP-REPL VREPL-STAGE$ _VCP-DST _VCT-RM-TREE DROP
        ['] _VCT-BARRIER _VCP-CAUGHT DROP
    THEN
    _VCP-WHOLE ;

\ _VCT-COPY ( -- ior )
\   Copy the folder _VCT-SA _VCT-SU on _VCT-SV to the destination the
\   record names, through the scratch in _VCT-XA _VCT-XU.
: _VCT-COPY  ( -- ior )
    0 _VCT-STAGED !  0 _VCT-SFD !  0 _VCT-DFD !
    ['] _VCT-START-BODY _VCT-DO ?DUP IF EXIT THEN
    _VCT-STALE @ IF
        _VCP-REPL VREPL-STAGE$ _VCP-DST _VCT-RM-TREE ?DUP IF _VCP-WHOLE EXIT THEN
    THEN
    ['] _VCT-MAKE-STAGE-BODY _VCT-DO ?DUP IF _VCP-WHOLE EXIT THEN
    -1 _VCT-STAGED !
    _VCT-ROOTS ?DUP IF _VCT-GIVE-UP EXIT THEN
    _VCT-WRITE-TREE ?DUP IF _VCT-GIVE-UP EXIT THEN
    ['] _VCT-BARRIER _VCP-CAUGHT ?DUP IF _VCT-GIVE-UP EXIT THEN
    _VCT-ROOTS ?DUP IF _VCT-GIVE-UP EXIT THEN
    _VCT-CHECK-TREE ?DUP IF _VCT-GIVE-UP EXIT THEN
    ['] _VCT-PUBLISH-BODY _VCT-DO ?DUP IF _VCT-GIVE-UP EXIT THEN
    0 _VCT-STAGED !
    ['] _VCT-BARRIER _VCP-CAUGHT ?DUP IF _VCP-STANDS EXIT THEN
    0 ;

: _VCT-ARGS  ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u -- )
    _VCT-XU ! _VCT-XA ! _VCT-DV ! _VCT-DU ! _VCT-DA !
    _VCT-SV ! _VCT-SU ! _VCT-SA ! ;

\ _VCT-FOLDER? ( -- flag ior )   Whether the source is a folder.
: _VCT-FOLDER?  ( -- flag ior )
    _VCT-SU @ VFS-PATH-MAX > IF 0 VFS-E-NAMETOOLONG EXIT THEN
    _VCT-SA @ _VW-SRC _VCT-SU @ CMOVE  _VCT-SU @ _VW-SU !  _VCT-SV @ _VW-SV !
    ['] _VCT-KIND-BODY _VCT-DO ?DUP IF 0 SWAP EXIT THEN
    _VCP-KIND-T @ VFS-T-DIR = 0 ;

\ _VCT-TREE-COPY ( -- ior )   Name the destination, copy, give the names back.
: _VCT-TREE-COPY  ( -- ior )
    _VCT-SV @ 0= _VCT-DV @ 0= OR IF VFS-E-INVALID EXIT THEN
    _VCT-XA @ 0= _VCT-XU @ 2 < OR IF VFS-E-INVALID EXIT THEN
    _VCT-DA @ _VCT-DU @ _VCT-DV @ _VCP-RECORD _VCP-NAME-PATH ?DUP IF
        _VCP-RELEASE EXIT
    THEN
    _VCT-COPY _VCP-RELEASE ;

\ =====================================================================
\  Copying and moving to the end
\ =====================================================================

: _VCP-COPY  ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u -- ior )
    _VCT-ARGS
    _VCT-SV @ 0= IF VFS-E-INVALID EXIT THEN
    _VCT-FOLDER? ?DUP IF NIP EXIT THEN
    IF _VCT-TREE-COPY EXIT THEN
    _VCT-SA @ _VCT-SU @ _VCT-SV @ _VCT-DA @ _VCT-DU @ _VCT-DV @
    _VCT-XA @ _VCT-XU @ _VCP-RECORD _VCP-INIT ?DUP IF EXIT THEN
    BEGIN _VCP-RECORD _VCP-STEP ?DUP IF NIP EXIT THEN 0= UNTIL
    0 ;

VARIABLE _VMV-SA   VARIABLE _VMV-SU   VARIABLE _VMV-SV
VARIABLE _VMV-DA   VARIABLE _VMV-DU   VARIABLE _VMV-DV
VARIABLE _VMV-XA   VARIABLE _VMV-XU
VARIABLE _VMV-FD
VARIABLE _VMV-MOVED
VARIABLE _VMV-IN       \ the source's entry, held until the rename
VARIABLE _VMV-PINNED

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

: _VMV-CHECK  ( -- ior )  _VMV-SOURCE NIP ;

\ Across instances, once the copy stands: the source goes, durably.
: _VMV-REMOVE-BODY  ( -- ior )
    _VMV-SA @ _VMV-SU @ _VMV-SV @ VFS-RM ?DUP IF EXIT THEN
    _VMV-SV @ VFS-BARRIER ;

: _VMV-REMOVE  ( -- ior )
    ['] _VMV-REMOVE-BODY _VCP-CAUGHT DUP IF _VCP-STANDS THEN ;

\ A folder moved across instances leaves its folder first: it takes the
\ stage name that VREPL-DERIVE-PATHS! derives from its own path, so it is
\ hidden at once, and that tree is then removed.  The descriptor holds the
\ hidden path while the move runs.
CREATE _VCT-HIDE VREPL-SIZE ALLOT
_VCT-HIDE VREPL-SIZE 0 FILL

: _VCT-HIDDEN$  ( -- a u )  _VCT-HIDE VREPL-STAGE$ ;

\ Whether a folder a move left before holds the hidden name.
: _VCT-HIDDEN-BODY  ( -- ior )
    0 _VCT-STALE !
    _VCT-HIDDEN$ _VCT-SV @ _VCP-ENTRY ?DUP IF NIP EXIT THEN
    IF -1 _VCT-STALE ! THEN 0 ;

: _VCT-HIDE-BODY  ( -- ior )
    _VCT-SA @ _VCT-SU @ _VCT-SV @ _VCP-ENTRY ?DUP IF NIP EXIT THEN
    DUP 0= IF DROP VFS-E-NOENT EXIT THEN
    >R _VCT-HIDE VREPL-STAGE-NAME$ R@ R> IN.PARENT @ VFS-RN-NOREPLACE
    _VCT-SV @ VFS-RENAME-AT ;

: _VCT-SOURCE-BARRIER  ( -- ior )  _VCT-SV @ VFS-BARRIER ;

\ _VCT-UNSOURCE ( -- ior )
\   Once the folder's copy stands: hide the source, remove it and take a
\   barrier.  A failure leaves the copy standing, and the answer says so;
\   until the hiding, both folders keep their names.
: _VCT-UNSOURCE  ( -- ior )
    ['] _VCT-HIDDEN-BODY _VCT-DO ?DUP IF _VCP-STANDS EXIT THEN
    _VCT-STALE @ IF
        _VCT-HIDDEN$ _VCT-SV @ _VCT-RM-TREE ?DUP IF _VCP-STANDS EXIT THEN
    THEN
    ['] _VCT-HIDE-BODY _VCT-DO ?DUP IF _VCP-STANDS EXIT THEN
    _VCT-HIDDEN$ _VCT-SV @ _VCT-RM-TREE ?DUP IF _VCP-STANDS EXIT THEN
    ['] _VCT-SOURCE-BARRIER _VCP-CAUGHT ?DUP IF _VCP-STANDS EXIT THEN
    0 ;

\ _VCT-TREE-MOVE ( -- ior )   Move the folder in _VCT- across instances.
: _VCT-TREE-MOVE  ( -- ior )
    _VCT-SV @ _VCT-HIDE VREPL-INIT IF VFS-E-INVALID EXIT THEN
    _VCT-SA @ _VCT-SU @ _VCT-HIDE VREPL-DERIVE-PATHS! IF
        _VCT-HIDE VREPL-FINI DROP VFS-E-INVALID EXIT
    THEN
    _VCT-TREE-COPY ?DUP IF _VCT-HIDE VREPL-FINI DROP EXIT THEN
    _VCT-UNSOURCE  _VCT-HIDE VREPL-FINI DROP ;

: _VCP-MOVE  ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u -- ior )
    _VMV-XU ! _VMV-XA ! _VMV-DV ! _VMV-DU ! _VMV-DA !
    _VMV-SV ! _VMV-SU ! _VMV-SA !
    _VMV-SV @ 0= _VMV-DV @ 0= OR IF VFS-E-INVALID EXIT THEN
    _VMV-SV @ _VMV-DV @ = IF
        \ The destination is named as a copy's is, so a move and a copy
        \ take the same destinations.
        _VMV-DA @ _VMV-DU @ _VMV-DV @ _VCP-RECORD _VCP-NAME-PATH
        ?DUP IF _VCP-RELEASE EXIT THEN
        ['] _VMV-RENAME VFS-TRANSACTION _VCP-RELEASE EXIT
    THEN
    _VMV-SA @ _VMV-SU @ _VMV-SV @ _VMV-DA @ _VMV-DU @ _VMV-DV @
    _VMV-XA @ _VMV-XU @ _VCT-ARGS
    _VCT-FOLDER? ?DUP IF NIP EXIT THEN
    IF _VCT-TREE-MOVE EXIT THEN
    ['] _VMV-CHECK VFS-TRANSACTION ?DUP IF EXIT THEN
    _VMV-SA @ _VMV-SU @ _VMV-SV @ _VMV-DA @ _VMV-DU @ _VMV-DV @
    _VMV-XA @ _VMV-XU @ _VCP-COPY ?DUP IF EXIT THEN
    ['] _VMV-REMOVE VFS-TRANSACTION ;

\ =====================================================================
\  Copying and moving between places
\ =====================================================================

\ The volume paths the places bind.
CREATE _VCPL-SRC  VFS-PATH-MAX ALLOT
CREATE _VCPL-DST  VFS-PATH-MAX ALLOT

VARIABLE _VCPL-SA  VARIABLE _VCPL-SN  VARIABLE _VCPL-SP
VARIABLE _VCPL-DA  VARIABLE _VCPL-DN  VARIABLE _VCPL-DP
VARIABLE _VCPL-XA  VARIABLE _VCPL-XU
VARIABLE _VCPL-SV  VARIABLE _VCPL-SU
VARIABLE _VCPL-DV  VARIABLE _VCPL-DU

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

: _VCP-PLACE-COPY  ( src-a src-u src-place dst-a dst-u dst-place scratch-a scratch-u -- ior )
    _VCPL-ARGS ['] PLACE-BIND _VCPL-BIND ?DUP IF EXIT THEN
    _VCPL-BOUND _VCP-COPY ;

\ A move also changes the source's place, so that place must be
\ writable too.
: _VCP-PLACE-MOVE  ( src-a src-u src-place dst-a dst-u dst-place scratch-a scratch-u -- ior )
    _VCPL-ARGS ['] PLACE-BIND-WRITE _VCPL-BIND ?DUP IF EXIT THEN
    _VCPL-BOUND _VCP-MOVE ;

\ =====================================================================
\  Public guarded entry points
\ =====================================================================

' _VCP-INIT        CONSTANT _vcopy-init-xt
' _VCP-STEP        CONSTANT _vcopy-step-xt
' _VCP-CANCEL      CONSTANT _vcopy-cancel-xt
' _VCP-COPY        CONSTANT _vcopy-copy-xt
' _VCP-MOVE        CONSTANT _vcopy-move-xt
' _VCP-PLACE-COPY  CONSTANT _vcopy-place-copy-xt
' _VCP-PLACE-MOVE  CONSTANT _vcopy-place-move-xt

\ VCOPY-INIT ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u copy -- ior )
\   Start copying the file SRC on SRC-VFS to the absolute path DST on
\   DST-VFS, in COPY, a VCOPY-SIZE record, through SCRATCH, at least two
\   bytes, which the caller keeps until the copy ends.  The source is
\   open and the stage created once it answers 0.
: VCOPY-INIT    _vcopy-init-xt _vcopy-guard WITH-GUARD ;

\ VCOPY-STEP ( copy -- more? ior )
\   Do the copy's next step.  MORE? is true while steps remain; a copy
\   that has ended, or failed, answers 0.
: VCOPY-STEP    _vcopy-step-xt _vcopy-guard WITH-GUARD ;

\ VCOPY-CANCEL ( copy -- ior )
\   End a copy before its rename: close its files and remove its stage.
: VCOPY-CANCEL  _vcopy-cancel-xt _vcopy-guard WITH-GUARD ;

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
