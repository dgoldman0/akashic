\ =====================================================================
\  vfs-module-source.f — KDOS modules from a mounted VFS
\ =====================================================================
\  Megapad-64 / KDOS Forth      Prefix: VMS- / _VMS-
\
\  KDOS's LOAD and REQUIRE find and read a file through the current
\  module source, a record of four operations that MegaPad's
\  docs/module-source-contract.md defines.  This module fills such a
\  record for a mounted VFS, so that modules can come from any volume a
\  binding serves, an ext4 volume among them.
\
\  Public API:
\    VMS-INIT  ( vfs source -- )   Make SOURCE serve modules from VFS.
\
\  SOURCE is /MODULE-SOURCE bytes that the caller owns and keeps while
\  the source is selected.  After VMS-INIT, `source MODULE-SOURCE!`
\  selects it, and `FS-MODULE-SOURCE MODULE-SOURCE!` returns loading to
\  KDOS's own filesystem; do that before the VFS is unmounted.
\
\  A path is resolved as the VFS resolves it: from the VFS's current
\  directory, with a leading / for the root and .. for the parent, which
\  are the forms KDOS's own source takes.  Loading changes that current
\  directory only while a load is under way.
\
\  The VFS evicts cached entries when a mount holds many of them, and a
\  load of one module resolves the paths of others.  A directory the
\  loader will return to is therefore pinned for as long as the loader
\  holds its token, and the file's own entry is pinned while it is being
\  opened.  A pin that another owner set is left as it was.
\ =====================================================================

PROVIDED akashic-vfs-module-source

REQUIRE vfs.f

\ The operation under way.  The loader finishes one call before it makes
\ the next, so one set of cells serves every source.
VARIABLE _VMS-V       \ its VFS
VARIABLE _VMS-FILE    \ the loader's file record
VARIABLE _VMS-D       \ the file's entry
VARIABLE _VMS-FD
VARIABLE _VMS-OWNED   \ true while READ holds the pin on the entry
VARIABLE _VMS-IOR

: _VMS-VFS  ( source -- vfs )  MS.CONTEXT @ ;

\ _VMS-PIN ( dentry -- owned? )  Pin an entry against eviction.  True
\ when this call set the pin, which its caller then clears.
: _VMS-PIN  ( dentry -- owned? )
    IN.FLAGS DUP @ VFS-IF-PINNED AND IF DROP FALSE EXIT THEN
    DUP @ VFS-IF-PINNED OR SWAP ! TRUE ;
: _VMS-UNPIN  ( dentry -- )
    IN.FLAGS DUP @ VFS-IF-PINNED INVERT AND SWAP ! ;

\ ── Identity ────────────────────────────────────────────────────────
\ A binding with stable identities gives each file a number and a
\ generation that survive eviction and remount; they fill the first
\ cell.  The second folds in the file's size and modification time and
\ the volume attachment's cookie, which KDOS makes new for each
\ attachment, so a file that changes, or another volume behind the same
\ source record, gives another identity.  Other bindings number their
\ files as the cache admits them, so their files get no identity and
\ are read on every REQUIRE.
: _VMS-FOLD  ( x y -- z )
    XOR 0x2545F4914F6CDD1D * DUP 29 RSHIFT XOR ;
: _VMS-IDENTITY!  ( -- )
    _VMS-V @ V.BINDING @ VB.FLAGS @ VFS-BF-STABLE-IDS AND 0= IF EXIT THEN
    _VMS-D @ D.VNODE @                      ( vnode )
    DUP VN.GEN @ 32 LSHIFT OVER VN.BID @ XOR
    _VMS-FILE @ MF.ID !
    DUP VN.SIZE-LO @
    OVER VN.MTIME @ _VMS-FOLD
    SWAP VN.MTIME-NS @ _VMS-FOLD
    _VMS-V @ V.VOL-COOKIE @ _VMS-FOLD
    _VMS-FILE @ MF.ID 8 + ! ;

\ ── RESOLVE ─────────────────────────────────────────────────────────
\ _VMS-MISS ( ior -- ior' )  Say in the loader's terms why a path did
\ not resolve.  A missing name and a path through something that is not
\ a directory name no file.  A VFS that is not mounted, or whose medium
\ changed under it, is no filesystem.  Any other failure is the VFS's
\ own and goes to the loader as it is.
: _VMS-MISS  ( ior -- ior' )
    DUP VFS-IOR-REASON
    DUP VFS-R-NOENT = OVER VFS-R-NOTDIR = OR IF
        2DROP MS-E-NOT-FOUND EXIT
    THEN
    DUP VFS-R-BUSY = SWAP VFS-R-STALE = OR IF
        DROP MS-E-NO-FILESYSTEM EXIT
    THEN ;

\ _VMS-RESOLVE ( c-addr u file source -- ior )
\   Find the regular file the path names, make its directory current,
\   and describe it.  The handle is the file's entry, which stays valid
\   until the next call that resolves a path; the loader makes none
\   before READ.
: _VMS-RESOLVE  ( c-addr u file source -- ior )
    _VMS-VFS _VMS-V !  _VMS-FILE !
    _VMS-V @ VFS-RESOLVE?                   ( dentry ior )
    ?DUP IF NIP _VMS-MISS EXIT THEN
    DUP IN.TYPE @ VFS-T-FILE <> IF DROP MS-E-NOT-FOUND EXIT THEN
    DUP IN.SIZE-HI @ 0<> OVER IN.SIZE-LO @ 0< OR IF
        DROP VFS-E-OVERFLOW EXIT
    THEN
    _VMS-D !
    _VMS-D @ D.PARENT @ _VMS-V @ V.CWD !
    _VMS-D @ IN.SIZE-LO @ DUP _VMS-FILE @ MF.USED !
    _VMS-FILE @ MF.RESERVE !
    _VMS-D @ _VMS-FILE @ MF.HANDLE !
    _VMS-IDENTITY!
    0 ;

\ ── READ ────────────────────────────────────────────────────────────
\ The VFS opens a file by path, so READ opens the entry's own name from
\ the current directory, which RESOLVE made the file's.  Opening
\ resolves that name, and resolving may evict; the pin keeps the entry
\ and its name in place until the descriptor holds it.
: _VMS-OPEN  ( -- ior )
    _VMS-D @ _VMS-PIN _VMS-OWNED !
    _VMS-D @ IN.NAME @ _VFS-STR-GET VFS-FF-READ _VMS-V @ VFS-OPEN?
    SWAP _VMS-FD !
    _VMS-OWNED @ IF _VMS-D @ _VMS-UNPIN THEN ;

\ _VMS-READ ( addr file source -- ior )
\   Copy the file's text to ADDR.  The descriptor must hold the entry
\   RESOLVE found, at the size RESOLVE reported; anything else means
\   the directory changed in between.
: _VMS-READ  ( addr file source -- ior )
    _VMS-VFS _VMS-V !  DUP _VMS-FILE !  MF.HANDLE @ _VMS-D !
    0 _VMS-FD !
    _VMS-OPEN ?DUP IF NIP EXIT THEN         ( addr )
    _VMS-FD @ FD.INODE @ _VMS-D @ <>
    _VMS-FD @ VFS-SIZE _VMS-FILE @ MF.USED @ <> OR IF
        DROP VFS-E-STALE
    ELSE
        _VMS-FILE @ MF.USED @ _VMS-FD @ VFS-READ-EXACT
    THEN
    _VMS-IOR !
    _VMS-FD @ VFS-CLOSE?
    _VMS-IOR @ ?DUP IF NIP THEN ;

\ ── Directory tokens ────────────────────────────────────────────────
\ A token is the current directory's entry.  The loader gives each
\ token back exactly once, innermost load first, so the token itself
\ carries whether its DIR@ set the entry's pin: entries are cell-aligned
\ records, and the lowest bit is free for that.
: _VMS-DIR@  ( source -- token )
    _VMS-VFS V.CWD @ DUP _VMS-PIN 1 AND OR ;
: _VMS-DIR!  ( token source -- )
    _VMS-VFS >R
    DUP 1 AND IF 1 XOR DUP _VMS-UNPIN THEN
    R> V.CWD ! ;

\ VMS-INIT ( vfs source -- )  Make SOURCE serve modules from VFS.
: VMS-INIT  ( vfs source -- )
    >R
    ['] _VMS-RESOLVE R@ MS.RESOLVE !
    ['] _VMS-READ    R@ MS.READ !
    ['] _VMS-DIR@    R@ MS.DIR@ !
    ['] _VMS-DIR!    R@ MS.DIR! !
    R> MS.CONTEXT ! ;
