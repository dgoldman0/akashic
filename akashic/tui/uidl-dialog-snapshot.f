\ =====================================================================
\  uidl-dialog-snapshot.f -- a document's dialog, frozen
\ =====================================================================
\
\  One coherent UIDL-TUI observation captures the dialog the current
\  document shows, as its last paint laid it out, into a caller-owned
\  native bank as one UDLG model, with a pointer-free descriptor.  A
\  document shows at most one dialog, so a capture has no record or one.
\  A dialog not yet painted, not wholly on the screen, or one its widget
\  cannot describe stays painted text: the capture records nothing for it.
\  A refused capture reports no bytes used, and the caller publishes none
\  of what it may have written.  Caller banks must be disjoint from each
\  other, from module scratch and from UIDL authority.
\
\  UDLSN-CAPTURE ( descriptors-a descriptors-u native-a native-u
\                  -- descriptor-count native-used status )
\  UDLSN-FROZEN-VALIDATE ( descriptors-a descriptors-u native-a native-u
\                          -- status )
\
\  Frozen validation never consults the live tree.  It validates the
\  model and checks it against its descriptor and the bank's exact extent.
\  Prefix: UDLSN- (public), _UDLSN- (private).

PROVIDED akashic-tui-uidl-dialog-snapshot

REQUIRE uidl-tui.f
REQUIRE dialog-model.f
REQUIRE widgets/dialog.f
REQUIRE ../utils/memory-span.f

0 CONSTANT UDLSN-S-OK
1 CONSTANT UDLSN-S-CAPACITY
2 CONSTANT UDLSN-S-UNAVAILABLE
3 CONSTANT UDLSN-S-INVALID

: UDLSN-STATUS-VALID?  ( status -- flag )  4 U< ;

\ The document's dialog, drawn over it after everything else it paints.
1 CONSTANT UDLSN-SOURCE-OVERLAY

\ Descriptor fields are native cells and contain no pointer.
\
\   +0   source kind
\   +8   the dialog's instance, its identity while it lives
\   +16  native offset relative to this document's native bank
\   +24  root row on the screen
\   +32  root column
\   +40  root height
\   +48  root width
\   +56  native entry bytes

: _UDLSN-D.SOURCE    ( descriptor -- address )       ;
: _UDLSN-D.KEY       ( descriptor -- address )   8 + ;
: _UDLSN-D.NATIVE-O  ( descriptor -- address )  16 + ;
: _UDLSN-D.ROW       ( descriptor -- address )  24 + ;
: _UDLSN-D.COLUMN    ( descriptor -- address )  32 + ;
: _UDLSN-D.HEIGHT    ( descriptor -- address )  40 + ;
: _UDLSN-D.WIDTH     ( descriptor -- address )  48 + ;
: _UDLSN-D.ENTRY-U   ( descriptor -- address )  56 + ;

64 CONSTANT UDLSN-DESCRIPTOR-SIZE

: UDLSN-DESCRIPTOR-BYTES  ( -- bytes )  UDLSN-DESCRIPTOR-SIZE ;
: UDLSN-DESCRIPTOR-SOURCE@  ( descriptor -- value )  _UDLSN-D.SOURCE @ ;
: UDLSN-DESCRIPTOR-KEY@  ( descriptor -- value )  _UDLSN-D.KEY @ ;
: UDLSN-DESCRIPTOR-NATIVE-OFFSET@  ( descriptor -- value )
    _UDLSN-D.NATIVE-O @ ;
: UDLSN-DESCRIPTOR-ROW@  ( descriptor -- value )  _UDLSN-D.ROW @ ;
: UDLSN-DESCRIPTOR-COLUMN@  ( descriptor -- value )  _UDLSN-D.COLUMN @ ;
: UDLSN-DESCRIPTOR-HEIGHT@  ( descriptor -- value )  _UDLSN-D.HEIGHT @ ;
: UDLSN-DESCRIPTOR-WIDTH@  ( descriptor -- value )  _UDLSN-D.WIDTH @ ;
: UDLSN-DESCRIPTOR-ENTRY-BYTES@  ( descriptor -- value )
    _UDLSN-D.ENTRY-U @ ;
: UDLSN-DESCRIPTOR-NATIVE  ( descriptor native-base -- model bytes )
    OVER UDLSN-DESCRIPTOR-NATIVE-OFFSET@ +
    SWAP UDLSN-DESCRIPTOR-ENTRY-BYTES@ ;

CREATE _UDLSN-OWNED-START

VARIABLE _UDLSN-DESCRIPTORS-A
VARIABLE _UDLSN-DESCRIPTORS-U
VARIABLE _UDLSN-NATIVE-A
VARIABLE _UDLSN-NATIVE-U
VARIABLE _UDLSN-W
VARIABLE _UDLSN-KEY
VARIABLE _UDLSN-ROW
VARIABLE _UDLSN-COLUMN
VARIABLE _UDLSN-HEIGHT
VARIABLE _UDLSN-WIDTH
VARIABLE _UDLSN-NEED
VARIABLE _UDLSN-OWNED-LIMIT

: _UDLSN-OPTIONAL-SPAN?  ( address bytes -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF DROP 0= EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    OVER 7 AND IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _UDLSN-OWNED-DISJOINT?  ( address bytes -- flag )
    DUP 0= IF 2DROP -1 EXIT THEN
    _UDLSN-OWNED-LIMIT @ DUP _UDLSN-OWNED-START U< IF
        DROP 2DROP 0 EXIT
    THEN
    _UDLSN-OWNED-START - >R
    _UDLSN-OWNED-START R> MSPAN-OVERLAP? 0= ;

\ Pure preflight for owners that reserve snapshot banks inside larger arenas.
: UDLSN-STORAGE-DISJOINT?  ( address bytes -- flag )
    2DUP _UDLSN-OPTIONAL-SPAN? 0= IF 2DROP 0 EXIT THEN
    _UDLSN-OWNED-DISJOINT? ;

\ A caller bank lies apart from this module, the model's scratch and the
\ document's UIDL authority.  The dialog's own storage is checked by its
\ capture.
: _UDLSN-AUTHORITY-DISJOINT?  ( address bytes -- flag )
    DUP 0= IF 2DROP -1 EXIT THEN
    2DUP _UDLSN-OWNED-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DUP UDLG-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    UTUI-STORAGE-DISJOINT? ;

: _UDLSN-SHAPES?  ( -- flag )
    _UDLSN-DESCRIPTORS-A @ _UDLSN-DESCRIPTORS-U @
        _UDLSN-OPTIONAL-SPAN? 0= IF 0 EXIT THEN
    _UDLSN-DESCRIPTORS-U @ UDLSN-DESCRIPTOR-SIZE MOD IF 0 EXIT THEN
    _UDLSN-NATIVE-A @ _UDLSN-NATIVE-U @
        _UDLSN-OPTIONAL-SPAN? 0= IF 0 EXIT THEN
    _UDLSN-DESCRIPTORS-U @ 0= _UDLSN-NATIVE-U @ 0= OR IF -1 EXIT THEN
    _UDLSN-DESCRIPTORS-A @ _UDLSN-DESCRIPTORS-U @
        _UDLSN-NATIVE-A @ _UDLSN-NATIVE-U @ MSPAN-OVERLAP? 0= ;

: _UDLSN-AUTHORITY?  ( -- flag )
    _UDLSN-DESCRIPTORS-A @ _UDLSN-DESCRIPTORS-U @
        _UDLSN-AUTHORITY-DISJOINT? 0= IF 0 EXIT THEN
    _UDLSN-NATIVE-A @ _UDLSN-NATIVE-U @ _UDLSN-AUTHORITY-DISJOINT? ;

\ The dialog the document shows, wholly on the screen as its last paint
\ laid it out; false for none, or one left to CELL.
: _UDLSN-SHOWN?  ( -- flag )
    DLG-SHOWN DUP _UDLSN-W ! 0= IF 0 EXIT THEN
    _UDLSN-W @ DLG-INSTANCE@ DUP _UDLSN-KEY ! 0= IF 0 EXIT THEN
    _UDLSN-W @ DLG-ROOT
        _UDLSN-WIDTH ! _UDLSN-HEIGHT ! _UDLSN-COLUMN ! _UDLSN-ROW !
    _UDLSN-HEIGHT @ 0> 0= _UDLSN-WIDTH @ 0> 0= OR IF 0 EXIT THEN
    _UDLSN-ROW @ 0< _UDLSN-COLUMN @ 0< OR IF 0 EXIT THEN
    _UDLSN-ROW @ _UDLSN-HEIGHT @ + SCR-H >
    _UDLSN-COLUMN @ _UDLSN-WIDTH @ + SCR-W > OR 0= ;

: _UDLSN-DESCRIBE  ( -- )
    _UDLSN-DESCRIPTORS-A @ UDLSN-DESCRIPTOR-SIZE 0 FILL
    UDLSN-SOURCE-OVERLAY _UDLSN-DESCRIPTORS-A @ _UDLSN-D.SOURCE !
    _UDLSN-KEY @ _UDLSN-DESCRIPTORS-A @ _UDLSN-D.KEY !
    _UDLSN-ROW @ _UDLSN-DESCRIPTORS-A @ _UDLSN-D.ROW !
    _UDLSN-COLUMN @ _UDLSN-DESCRIPTORS-A @ _UDLSN-D.COLUMN !
    _UDLSN-HEIGHT @ _UDLSN-DESCRIPTORS-A @ _UDLSN-D.HEIGHT !
    _UDLSN-WIDTH @ _UDLSN-DESCRIPTORS-A @ _UDLSN-D.WIDTH !
    _UDLSN-NEED @ _UDLSN-DESCRIPTORS-A @ _UDLSN-D.ENTRY-U ! ;

: _UDLSN-CAPTURE-BODY  ( -- descriptor-count native-used status )
    _UDLSN-SHAPES? 0= IF 0 0 UDLSN-S-INVALID EXIT THEN
    _UDLSN-AUTHORITY? 0= IF 0 0 UDLSN-S-INVALID EXIT THEN
    _UDLSN-SHOWN? 0= IF 0 0 UDLSN-S-OK EXIT THEN
    0 0 _UDLSN-W @ DLG-MODEL-CAPTURE
    DUP UDLG-S-UNSUPPORTED = IF 2DROP 0 0 UDLSN-S-OK EXIT THEN
    IF DROP 0 0 UDLSN-S-INVALID EXIT THEN
    _UDLSN-NEED !
    _UDLSN-DESCRIPTORS-U @ UDLSN-DESCRIPTOR-SIZE U<
    _UDLSN-NATIVE-U @ _UDLSN-NEED @ U< OR IF 0 0 UDLSN-S-CAPACITY EXIT THEN
    _UDLSN-NATIVE-A @ _UDLSN-NATIVE-U @ _UDLSN-W @ DLG-MODEL-CAPTURE
    DUP IF
        NIP UDLG-S-CAPACITY = IF UDLSN-S-CAPACITY ELSE UDLSN-S-INVALID THEN
        0 0 ROT EXIT
    THEN DROP
    _UDLSN-NEED @ <> IF 0 0 UDLSN-S-INVALID EXIT THEN
    _UDLSN-DESCRIBE
    1 _UDLSN-NEED @ UDLSN-S-OK ;

: _UDLSN-SCRUB  ( -- )
    0 _UDLSN-DESCRIPTORS-A ! 0 _UDLSN-DESCRIPTORS-U !
    0 _UDLSN-NATIVE-A ! 0 _UDLSN-NATIVE-U ! 0 _UDLSN-W !
    0 _UDLSN-KEY ! 0 _UDLSN-ROW ! 0 _UDLSN-COLUMN !
    0 _UDLSN-HEIGHT ! 0 _UDLSN-WIDTH ! 0 _UDLSN-NEED ! ;

\ UDLSN-CAPTURE ( descriptors-a descriptors-u native-a native-u
\                 -- descriptor-count native-used status )
\   Capture the current document's dialog.  Nothing is written for a
\   document that shows none, or one left to CELL.
: UDLSN-CAPTURE  ( descriptors-a descriptors-u native-a native-u -- n used status )
    _UDLSN-NATIVE-U ! _UDLSN-NATIVE-A !
    _UDLSN-DESCRIPTORS-U ! _UDLSN-DESCRIPTORS-A !
    ['] _UDLSN-CAPTURE-BODY CATCH ?DUP IF DROP 0 0 UDLSN-S-INVALID THEN
    _UDLSN-SCRUB ;

\ =====================================================================
\  Frozen validation
\ =====================================================================

VARIABLE _UDLSN-F-D
VARIABLE _UDLSN-F-M

: _UDLSN-F-COORD?  ( n -- flag )  0x80000000 U< ;
: _UDLSN-F-POS?  ( n -- flag )  DUP 0<> SWAP 0x100000000 U< AND ;

: _UDLSN-F-ONE?  ( -- flag )
    _UDLSN-F-D @ UDLSN-DESCRIPTOR-SOURCE@ UDLSN-SOURCE-OVERLAY <> IF 0 EXIT THEN
    _UDLSN-F-D @ UDLSN-DESCRIPTOR-KEY@ 0= IF 0 EXIT THEN
    _UDLSN-F-D @ UDLSN-DESCRIPTOR-NATIVE-OFFSET@ IF 0 EXIT THEN
    _UDLSN-F-D @ UDLSN-DESCRIPTOR-ENTRY-BYTES@ _UDLSN-NATIVE-U @ <> IF
        0 EXIT
    THEN
    _UDLSN-F-D @ UDLSN-DESCRIPTOR-ROW@ _UDLSN-F-COORD? 0=
    _UDLSN-F-D @ UDLSN-DESCRIPTOR-COLUMN@ _UDLSN-F-COORD? 0= OR
    _UDLSN-F-D @ UDLSN-DESCRIPTOR-HEIGHT@ _UDLSN-F-POS? 0= OR
    _UDLSN-F-D @ UDLSN-DESCRIPTOR-WIDTH@ _UDLSN-F-POS? 0= OR IF 0 EXIT THEN
    _UDLSN-NATIVE-A @ _UDLSN-NATIVE-U @ UDLG-VALIDATE UDLG-S-OK <> IF
        0 EXIT
    THEN
    _UDLSN-NATIVE-A @ _UDLSN-F-M !
    _UDLSN-F-M @ UDLG-KEY@ _UDLSN-F-D @ UDLSN-DESCRIPTOR-KEY@ =
    _UDLSN-F-M @ UDLG-HEIGHT@ _UDLSN-F-D @ UDLSN-DESCRIPTOR-HEIGHT@ = AND
    _UDLSN-F-M @ UDLG-WIDTH@ _UDLSN-F-D @ UDLSN-DESCRIPTOR-WIDTH@ = AND ;

: _UDLSN-FROZEN-BODY  ( -- status )
    _UDLSN-SHAPES? 0= IF UDLSN-S-INVALID EXIT THEN
    _UDLSN-DESCRIPTORS-A @ _UDLSN-DESCRIPTORS-U @
        _UDLSN-OWNED-DISJOINT? 0= IF UDLSN-S-INVALID EXIT THEN
    _UDLSN-NATIVE-A @ _UDLSN-NATIVE-U @
        _UDLSN-OWNED-DISJOINT? 0= IF UDLSN-S-INVALID EXIT THEN
    _UDLSN-DESCRIPTORS-U @ 0= IF
        _UDLSN-NATIVE-U @ IF UDLSN-S-INVALID ELSE UDLSN-S-OK THEN EXIT
    THEN
    _UDLSN-DESCRIPTORS-U @ UDLSN-DESCRIPTOR-SIZE <> IF UDLSN-S-INVALID EXIT THEN
    _UDLSN-DESCRIPTORS-A @ _UDLSN-F-D !
    _UDLSN-F-ONE? IF UDLSN-S-OK ELSE UDLSN-S-INVALID THEN ;

\ UDLSN-FROZEN-VALIDATE ( descriptors-a descriptors-u native-a native-u
\                         -- status )
\   One document's frozen slice: no descriptor and no native bytes, or one
\   descriptor naming the one valid model that fills the native bank.
: UDLSN-FROZEN-VALIDATE  ( descriptors-a descriptors-u native-a native-u -- status )
    _UDLSN-NATIVE-U ! _UDLSN-NATIVE-A !
    _UDLSN-DESCRIPTORS-U ! _UDLSN-DESCRIPTORS-A !
    ['] _UDLSN-FROZEN-BODY CATCH ?DUP IF DROP UDLSN-S-INVALID THEN
    0 _UDLSN-F-D ! 0 _UDLSN-F-M ! _UDLSN-SCRUB ;

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _udlsn-guard
' UDLSN-CAPTURE CONSTANT _udlsn-capture-xt
' UDLSN-FROZEN-VALIDATE CONSTANT _udlsn-frozen-xt
: UDLSN-CAPTURE _udlsn-capture-xt _udlsn-guard WITH-GUARD ;
: UDLSN-FROZEN-VALIDATE _udlsn-frozen-xt _udlsn-guard WITH-GUARD ;
[THEN] [THEN]

CREATE _UDLSN-OWNED-END
_UDLSN-OWNED-END _UDLSN-OWNED-LIMIT !
