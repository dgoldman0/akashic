\ =====================================================================
\  vfs-copy.f - Copying and moving files, between volumes too
\ =====================================================================
\  Megapad-64 / KDOS Forth      Prefix: VCOPY- VFS- PLACE- / _VCP- _VC.
\
\  A copy writes the file under a stage name in the destination folder,
\  syncs, reads the stage back against the source in halves of the
\  caller's scratch, and only then renames the stage to its final name
\  and syncs again.  The rename is the commit: before it the final name
\  does not exist, and a failure removes the stage.  The file passes
\  through the scratch a chunk at a time, so it never needs to fit in
\  memory, and the copy refuses a final name that exists.
\
\  The stage's name is the reserved `.s-` name that VREPL-DERIVE-PATHS!
\  (vfs-replace.f) derives from the final path.  A stage a crash leaves
\  is therefore a hidden file, and the same copy, tried again, finds it
\  under the same name and removes it before it writes a new one.
\
\  VCOPY-STEP moves one chunk, so an applet can step a long copy from its
\  tick; VFS-COPY runs the steps to the end.  VFS-MOVE renames inside one
\  instance, and across two it copies, then removes the source and
\  syncs.  PLACE-COPY and PLACE-MOVE bind both paths in their places
\  first, so a read-only place refuses to be written.
\
\  Public API:
\    VCOPY-SIZE   ( -- n )   bytes of a copy record
\    VCOPY-INIT   ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u copy -- ior )
\    VCOPY-STEP   ( copy -- more? ior )
\    VCOPY-CANCEL ( copy -- ior )
\    VFS-COPY  VFS-MOVE      ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u -- ior )
\    PLACE-COPY  PLACE-MOVE  ( src-a src-u src-place dst-a dst-u dst-place scratch-a scratch-u -- ior )
\
\  An answer that carries VFS-IOR-F-PARTIAL means the destination file
\  stands though a later step failed: the sync after the copy's rename,
\  or a move's removal of its source.  Every other failure leaves no
\  destination file and the source as it was.
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
\ A replacement descriptor that holds the final path and the stage's.
: _VC.REPL       ( copy -- a ) 80 + ;
80 CONSTANT _VCOPY-HEADER

_VCOPY-HEADER VREPL-SIZE + CONSTANT VCOPY-SIZE

GUARD _vcopy-guard

\ The record a call works on, under the guard.
VARIABLE _VCP-C

: _VCP-REPL  ( -- repl )  _VCP-C @ _VC.REPL ;
: _VCP-SRC   ( -- vfs )   _VCP-C @ _VC.SRC-VFS @ ;
: _VCP-DST   ( -- vfs )   _VCP-C @ _VC.DST-VFS @ ;

\ The last component of a path whose last component starts at BASE.
: _VCP-COMPONENT  ( path-a path-u base -- a u )  ROT OVER + -ROT - ;

: _VCP-NAME$  ( -- a u )
    _VCP-REPL DUP VREPL-TARGET$ ROT VREPL.TARGET-BASE @ _VCP-COMPONENT ;

: _VCP-STAGE-NAME$  ( -- a u )
    _VCP-REPL DUP VREPL-STAGE$ ROT VREPL.STAGE-BASE @ _VCP-COMPONENT ;

\ The folder that holds the final name and the stage, "/" for the root.
: _VCP-FOLDER$  ( -- a u )
    _VCP-REPL DUP VREPL.TARGET SWAP VREPL.TARGET-BASE @ _VREPL-PARENT-LEN ;

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

: _VCX-SYNC  ( -- ior )  _VCP-DST VFS-SYNC ;

\ _VCP-DROP ( -- ior )
\   Close the copy's files and remove its stage, so the destination
\   holds nothing of it.  Each step is tried whatever the one before
\   answered, and the first failure is the answer.  A stage that cannot
\   be removed stays a hidden file until the same copy is tried again.
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
    _VCI-DA @ _VCI-DU @ _VCI-DV @ _VCP-C @ _VCP-NAME-PATH ?DUP IF EXIT THEN
    ['] _VCI-BODY VFS-TRANSACTION ;

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

\ Every byte is in the stage: close it, sync, and open it again to read
\ it back against the source from the start.
: _VCS-WRITTEN  ( -- more? ior )
    _VCP-C @ _VC.STAGE-FD _VCS-FD-CLOSE ?DUP IF 0 SWAP EXIT THEN
    _VCP-DST VFS-SYNC ?DUP IF 0 SWAP EXIT THEN
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
\ must still be free, and sync.  The rename is the commit.
: _VCS-PUBLISH  ( -- more? ior )
    _VCP-C @ _VC.SRC-FD _VCS-FD-CLOSE ?DUP IF 0 SWAP EXIT THEN
    _VCP-C @ _VC.STAGE-FD _VCS-FD-CLOSE ?DUP IF 0 SWAP EXIT THEN
    _VCP-REPL VREPL-STAGE$ _VCP-DST _VCP-ENTRY ?DUP IF NIP 0 SWAP EXIT THEN
    DUP 0= IF DROP 0 VFS-E-NOENT EXIT THEN
    >R _VCP-NAME$ R@ R> IN.PARENT @ VFS-RN-NOREPLACE _VCP-DST VFS-RENAME-AT
    ?DUP IF 0 SWAP EXIT THEN
    _VCOPY-PUBLISHED _VCP-C @ _VC.STATE !
    _VCP-DST VFS-SYNC ?DUP IF 0 SWAP EXIT THEN
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
\ in the sync, leaves the copy standing, and the answer says so.
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

: _VCP-STEP  ( copy -- more? ior )
    DUP _VCP-C !
    _VCP-VALID? 0= IF 0 VFS-E-INVALID EXIT THEN
    _VCP-C @ _VC.STATE @ _VCOPY-IDLE = IF 0 0 EXIT THEN
    ['] _VCS-BODY VFS-TRANSACTION ;

: _VCP-CANCEL  ( copy -- ior )
    DUP _VCP-C !
    _VCP-VALID? 0= IF VFS-E-INVALID EXIT THEN
    _VCP-C @ _VC.STATE @ _VCOPY-IDLE = IF 0 EXIT THEN
    ['] _VCP-DROP VFS-TRANSACTION ;

\ =====================================================================
\  Copying and moving to the end
\ =====================================================================

\ The record VFS-COPY steps, and whose replacement descriptor names a
\ move's destination.  It is idle between calls.
CREATE _VCP-RECORD VCOPY-SIZE ALLOT
_VCP-RECORD VCOPY-SIZE 0 FILL

: _VCP-COPY  ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u -- ior )
    _VCP-RECORD _VCP-INIT ?DUP IF EXIT THEN
    BEGIN _VCP-RECORD _VCP-STEP ?DUP IF NIP EXIT THEN 0= UNTIL
    0 ;

VARIABLE _VMV-SA   VARIABLE _VMV-SU   VARIABLE _VMV-SV
VARIABLE _VMV-DA   VARIABLE _VMV-DU   VARIABLE _VMV-DV
VARIABLE _VMV-XA   VARIABLE _VMV-XU
VARIABLE _VMV-FD
VARIABLE _VMV-MOVED

\ _VMV-SOURCE ( -- inode ior )
\   What a move takes: a regular file, by its own name rather than
\   through a final link.
: _VMV-SOURCE  ( -- inode ior )
    _VMV-SA @ _VMV-SU @ _VMV-SV @ _VCP-ENTRY ?DUP IF EXIT THEN
    DUP 0= IF VFS-E-NOENT EXIT THEN
    DUP _VCP-FILE? ;

\ Inside one instance: one rename.  The open source holds its entry, so
\ the folder's lookup cannot evict it before the rename.
: _VMV-RENAME-BODY  ( -- ior )
    _VMV-SOURCE NIP ?DUP IF EXIT THEN
    _VCP-REPL VREPL-TARGET$ _VMV-DV @ _VCP-ENTRY ?DUP IF NIP EXIT THEN
    IF VFS-E-EXISTS EXIT THEN
    _VMV-SA @ _VMV-SU @ VFS-FF-READ _VMV-SV @ VFS-OPEN? ?DUP IF NIP EXIT THEN
    _VMV-FD !
    _VCP-FOLDER ?DUP IF NIP EXIT THEN
    >R _VCP-NAME$ _VMV-FD @ FD.INODE @ R> VFS-RN-NOREPLACE _VMV-DV @
    VFS-RENAME-AT ?DUP IF EXIT THEN
    -1 _VMV-MOVED !
    _VMV-DV @ VFS-SYNC ;

: _VMV-RENAME  ( -- ior )
    0 _VMV-FD !  0 _VMV-MOVED !
    ['] _VMV-RENAME-BODY _VCP-CAUGHT
    _VMV-FD @ ?DUP IF 0 _VMV-FD ! VFS-CLOSE? DROP THEN
    DUP _VMV-MOVED @ AND IF _VCP-STANDS ELSE _VCP-WHOLE THEN ;

: _VMV-CHECK  ( -- ior )  _VMV-SOURCE NIP ;

\ Across instances, once the copy stands: the source goes, durably.
: _VMV-REMOVE-BODY  ( -- ior )
    _VMV-SA @ _VMV-SU @ _VMV-SV @ VFS-RM ?DUP IF EXIT THEN
    _VMV-SV @ VFS-SYNC ;

: _VMV-REMOVE  ( -- ior )
    ['] _VMV-REMOVE-BODY _VCP-CAUGHT DUP IF _VCP-STANDS THEN ;

: _VCP-MOVE  ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u -- ior )
    _VMV-XU ! _VMV-XA ! _VMV-DV ! _VMV-DU ! _VMV-DA !
    _VMV-SV ! _VMV-SU ! _VMV-SA !
    _VMV-SV @ 0= _VMV-DV @ 0= OR IF VFS-E-INVALID EXIT THEN
    _VMV-SV @ _VMV-DV @ = IF
        \ The destination is named as a copy's is, so a move and a copy
        \ take the same destinations.
        _VMV-DA @ _VMV-DU @ _VMV-DV @ _VCP-RECORD _VCP-NAME-PATH
        ?DUP IF EXIT THEN
        ['] _VMV-RENAME VFS-TRANSACTION EXIT
    THEN
    ['] _VMV-CHECK VFS-TRANSACTION ?DUP IF EXIT THEN
    _VMV-SA @ _VMV-SU @ _VMV-SV @ _VMV-DA @ _VMV-DU @ _VMV-DV @
    _VMV-XA @ _VMV-XU @ _VCP-COPY ?DUP IF EXIT THEN
    ['] _VMV-REMOVE VFS-TRANSACTION ;

\ =====================================================================
\  Copying and moving between places
\ =====================================================================

\ The volume paths the places bind.  A final path longer than the
\ replacement library takes cannot be copied, so its buffer stops there.
CREATE _VCPL-SRC  VFS-PATH-MAX ALLOT
CREATE _VCPL-DST  VREPL-PATH-MAX 1+ ALLOT

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
    _VCPL-DA @ _VCPL-DN @ _VCPL-DP @ _VCPL-DST VREPL-PATH-MAX
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
\   Copy a file to the end.
: VFS-COPY      _vcopy-copy-xt _vcopy-guard WITH-GUARD ;

\ VFS-MOVE ( src-a src-u src-vfs dst-a dst-u dst-vfs scratch-a scratch-u -- ior )
\   Move a file: one rename inside an instance; across two, a copy, then
\   the source's removal and a sync.
: VFS-MOVE      _vcopy-move-xt _vcopy-guard WITH-GUARD ;

\ PLACE-COPY ( src-a src-u src-place dst-a dst-u dst-place scratch-a scratch-u -- ior )
\   Copy a file of one place to a path of another, or the same, place.
: PLACE-COPY    _vcopy-place-copy-xt _vcopy-guard WITH-GUARD ;

\ PLACE-MOVE ( src-a src-u src-place dst-a dst-u dst-place scratch-a scratch-u -- ior )
\   Move a file between places; both must be writable.
: PLACE-MOVE    _vcopy-place-move-xt _vcopy-guard WITH-GUARD ;
