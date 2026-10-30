\ =====================================================================
\  uidl-hybrid-adapter.f -- visible UIDL aggregate snapshot lifecycle
\ =====================================================================
\
\  This optional composition adapter follows the ordinary AHOST / UCTX
\  lifecycle and assembles every visible document's renderer-neutral menu,
\  canonical widget-collection, DATA_GRAPHICS, and STATUS_FIELD models into
\  caller-owned A/B banks at a completed draw boundary.  Documents dirtied by
\  their own lifecycle are recaptured; every unchanged document slice is
\  copied from the prior published bank once its bounds are checked, and with
\  every-frame checks on (check-mode.f) its snapshot module first validates
\  it in full.  Each
\  directory entry carries exact and topology-only menu lineage so a downstream
\  renderer may reuse an unchanged CONTROL projection and patch state without
\  treating a state transition as structural identity.  It does not open a
\  terminal owner, inspect CELL values, or publish retained objects.  It does
\  consult the screen's renderer-neutral final-writer occlusion plane: the
\  semantic slices of a document touched by a later foreground layer are
\  omitted atomically for that draw so residual CELL projection owns both
\  its pixels and hit area.
\
\  Directory entries cover visible documents with a nonempty menu, collection
\  forest, DATA_GRAPHICS forest, or STATUS_FIELD list.  A document hidden by foreground paint
\  retains a directory-only identity with zero semantic slices for that draw;
\  documents intrinsically empty in all enabled families contribute nothing.
\  A consumer may borrow
\  RUHA-SNAPSHOT-FOR@ only until lifecycle invalidation or the next successful
\  aggregate publication.  The hybrid screen producer copies that snapshot
\  into its own attempt before any asynchronous owner work begins.
\
\  Prefix: RUHA- (public), _RUHA- (private)

PROVIDED akashic-tui-rterm-ruha

REQUIRE ../applet-host/host.f
REQUIRE ../screen.f
REQUIRE ../uidl-menu-snapshot.f
REQUIRE ../uidl-collection-snapshot.f
REQUIRE ../uidl-data-graphics-snapshot.f
REQUIRE ../uidl-status-field-snapshot.f
REQUIRE ../uidl-picture-snapshot.f
REQUIRE ../uidl-field-snapshot.f
REQUIRE ../uidl-dialog-snapshot.f
REQUIRE ../uidl-root-facts.f
REQUIRE ../../utils/memory-span.f
REQUIRE ../../utils/memory-source.f
REQUIRE frame-shadow.f
REQUIRE ../check-mode.f

0 CONSTANT RUHA-S-OK
1 CONSTANT RUHA-S-CAPACITY
2 CONSTANT RUHA-S-UNAVAILABLE
4 CONSTANT RUHA-S-STALE
5 CONSTANT RUHA-S-INVALID

0 CONSTANT _RUHA-RECORD-FREE
1 CONSTANT _RUHA-RECORD-ATTACHED
2 CONSTANT _RUHA-RECORD-QUIESCED

: _RUHA-R.STATE    ( record -- a )       ;
: _RUHA-R.TOKEN    ( record -- a )   8 + ;
: _RUHA-R.SLOT     ( record -- a )  16 + ;
: _RUHA-R.SLOT-ID  ( record -- a )  24 + ;
: _RUHA-R.UCTX     ( record -- a )  32 + ;
: _RUHA-R.VISIBLE  ( record -- a )  40 + ;
: _RUHA-R.REGION   ( record -- a )  48 + ;
: _RUHA-R.ROW      ( record -- a )  56 + ;
: _RUHA-R.COL      ( record -- a )  64 + ;
: _RUHA-R.HEIGHT   ( record -- a )  72 + ;
: _RUHA-R.WIDTH    ( record -- a )  80 + ;
: _RUHA-R.FLAGS    ( record -- a )  88 + ;
\ The screen cells of the overlay the document's last draw painted, the
\ dialog it shows or its prompt's field, or all zero: its own foreground
\ paint.  Its kind is in FLAGS.
: _RUHA-R.OV-ROW     ( record -- a )  96 + ;
: _RUHA-R.OV-COL     ( record -- a ) 104 + ;
: _RUHA-R.OV-HEIGHT  ( record -- a ) 112 + ;
: _RUHA-R.OV-WIDTH   ( record -- a ) 120 + ;
\ The count of element changes when the document's menus were last captured,
\ or found unchanged, and the generation of the snapshot whose menu slice
\ that capture is, or zero: a later draw takes that slice while nothing the
\ menus read has changed since (URF-MENUS-SINCE?).
: _RUHA-R.MENU-STAMP ( record -- a ) 128 + ;
: _RUHA-R.MENU-GEN   ( record -- a ) 136 + ;

1 CONSTANT _RUHA-RF-DIRTY
2 CONSTANT _RUHA-RF-EMPTY
4 CONSTANT _RUHA-RF-STAGED
8 CONSTANT _RUHA-RF-STAGED-EMPTY
16 CONSTANT _RUHA-RF-OV-FIELD
32 CONSTANT _RUHA-RF-OV-DIALOG
63 CONSTANT _RUHA-RF-MASK

144 CONSTANT RUHA-RECORD-SIZE

: RUHA-RECORD-BYTES  ( -- bytes )  RUHA-RECORD-SIZE ;

\ Aggregate directory entries identify one ordinary visible UIDL document.
: _RUHA-D.TOKEN       ( entry -- a )       ;
: _RUHA-D.SLOT-ID     ( entry -- a )   8 + ;
: _RUHA-D.ROW         ( entry -- a )  16 + ;
: _RUHA-D.COL         ( entry -- a )  24 + ;
: _RUHA-D.HEIGHT      ( entry -- a )  32 + ;
: _RUHA-D.WIDTH       ( entry -- a )  40 + ;
: _RUHA-D.RECORD-OFF  ( entry -- a )  48 + ;
: _RUHA-D.RECORD-U    ( entry -- a )  56 + ;
: _RUHA-D.TEXT-OFF    ( entry -- a )  64 + ;
: _RUHA-D.TEXT-U      ( entry -- a )  72 + ;
: _RUHA-D.COLLECTION-DESCRIPTOR-OFF ( entry -- a ) 80 + ;
: _RUHA-D.COLLECTION-DESCRIPTOR-U   ( entry -- a ) 88 + ;
: _RUHA-D.COLLECTION-NATIVE-OFF     ( entry -- a ) 96 + ;
: _RUHA-D.COLLECTION-NATIVE-U       ( entry -- a ) 104 + ;
: _RUHA-D.DGRAPH-DESCRIPTOR-OFF     ( entry -- a ) 112 + ;
: _RUHA-D.DGRAPH-DESCRIPTOR-U       ( entry -- a ) 120 + ;
: _RUHA-D.DGRAPH-NATIVE-OFF         ( entry -- a ) 128 + ;
: _RUHA-D.DGRAPH-NATIVE-U           ( entry -- a ) 136 + ;
: _RUHA-D.MENU-EPOCH                 ( entry -- a ) 144 + ;
: _RUHA-D.MENU-TOPOLOGY-EPOCH        ( entry -- a ) 152 + ;

: _RUHA-D.SFIELD-DESCRIPTOR-OFF ( entry -- a ) 160 + ;
: _RUHA-D.SFIELD-DESCRIPTOR-U   ( entry -- a ) 168 + ;
: _RUHA-D.SFIELD-NATIVE-OFF     ( entry -- a ) 176 + ;
: _RUHA-D.SFIELD-NATIVE-U       ( entry -- a ) 184 + ;
: _RUHA-D.FIELD-DESCRIPTOR-OFF ( entry -- a ) 192 + ;
: _RUHA-D.FIELD-DESCRIPTOR-U   ( entry -- a ) 200 + ;
: _RUHA-D.FIELD-NATIVE-OFF     ( entry -- a ) 208 + ;
: _RUHA-D.FIELD-NATIVE-U       ( entry -- a ) 216 + ;

: _RUHA-D.OWNER-ID    ( entry -- a ) 224 + ;
: _RUHA-D.OWNER-GEN   ( entry -- a ) 232 + ;
: _RUHA-D.DIALOG-DESCRIPTOR-OFF ( entry -- a ) 240 + ;
: _RUHA-D.DIALOG-DESCRIPTOR-U   ( entry -- a ) 248 + ;
: _RUHA-D.DIALOG-NATIVE-OFF     ( entry -- a ) 256 + ;
: _RUHA-D.DIALOG-NATIVE-U       ( entry -- a ) 264 + ;
\ The cells of the document's own overlay when its roots may lie beneath it
\ (RUHA-LAYERS!), else all zero.
: _RUHA-D.OV-ROW      ( entry -- a ) 272 + ;
: _RUHA-D.OV-COL      ( entry -- a ) 280 + ;
: _RUHA-D.OV-HEIGHT   ( entry -- a ) 288 + ;
: _RUHA-D.OV-WIDTH    ( entry -- a ) 296 + ;
\ 1 for an overlay slot's document, which its host paints above the others,
\ else 0.
: _RUHA-D.LAYER       ( entry -- a ) 304 + ;

312 CONSTANT RUHA-DOCUMENT-SIZE
: RUHA-DOCUMENT-BYTES ( -- bytes ) RUHA-DOCUMENT-SIZE ;
: RUHA-DOCUMENT-OWNER-ID@ ( entry -- owner-id ) _RUHA-D.OWNER-ID @ ;
: RUHA-DOCUMENT-OWNER-GENERATION@ ( entry -- generation ) _RUHA-D.OWNER-GEN @ ;
: RUHA-DOCUMENT-TOKEN@ ( entry -- u ) _RUHA-D.TOKEN @ ;
: RUHA-DOCUMENT-SLOT-ID@ ( entry -- u ) _RUHA-D.SLOT-ID @ ;
: RUHA-DOCUMENT-ROW@ ( entry -- u ) _RUHA-D.ROW @ ;
: RUHA-DOCUMENT-COL@ ( entry -- u ) _RUHA-D.COL @ ;
: RUHA-DOCUMENT-HEIGHT@ ( entry -- u ) _RUHA-D.HEIGHT @ ;
: RUHA-DOCUMENT-WIDTH@ ( entry -- u ) _RUHA-D.WIDTH @ ;
\ RUHA-DOCUMENT-OVERLAY@ ( entry -- row col height width )
\   The cells of the document's own overlay, a dialog or a prompt's field,
\   when its roots may lie beneath it; a zero height and width otherwise.
: RUHA-DOCUMENT-OVERLAY@ ( entry -- row col height width )
    >R R@ _RUHA-D.OV-ROW @ R@ _RUHA-D.OV-COL @
    R@ _RUHA-D.OV-HEIGHT @ R> _RUHA-D.OV-WIDTH @ ;
\ RUHA-DOCUMENT-LAYER@ ( entry -- layer )
\   1 for an overlay slot's document, which its host paints above every
\   other, else 0.
: RUHA-DOCUMENT-LAYER@ ( entry -- layer ) _RUHA-D.LAYER @ ;
: RUHA-DOCUMENT-RECORD-OFFSET@ ( entry -- u ) _RUHA-D.RECORD-OFF @ ;
: RUHA-DOCUMENT-RECORD-BYTES@ ( entry -- u ) _RUHA-D.RECORD-U @ ;
: RUHA-DOCUMENT-TEXT-OFFSET@ ( entry -- u ) _RUHA-D.TEXT-OFF @ ;
: RUHA-DOCUMENT-TEXT-BYTES@ ( entry -- u ) _RUHA-D.TEXT-U @ ;
: RUHA-DOCUMENT-COLLECTION-DESCRIPTOR-OFFSET@ ( entry -- u )
    _RUHA-D.COLLECTION-DESCRIPTOR-OFF @ ;
: RUHA-DOCUMENT-COLLECTION-DESCRIPTOR-BYTES@ ( entry -- u )
    _RUHA-D.COLLECTION-DESCRIPTOR-U @ ;
: RUHA-DOCUMENT-COLLECTION-NATIVE-OFFSET@ ( entry -- u )
    _RUHA-D.COLLECTION-NATIVE-OFF @ ;
: RUHA-DOCUMENT-COLLECTION-NATIVE-BYTES@ ( entry -- u )
    _RUHA-D.COLLECTION-NATIVE-U @ ;
: RUHA-DOCUMENT-DATA-GRAPHICS-DESCRIPTOR-OFFSET@ ( entry -- u )
    _RUHA-D.DGRAPH-DESCRIPTOR-OFF @ ;
: RUHA-DOCUMENT-DATA-GRAPHICS-DESCRIPTOR-BYTES@ ( entry -- u )
    _RUHA-D.DGRAPH-DESCRIPTOR-U @ ;
: RUHA-DOCUMENT-DATA-GRAPHICS-NATIVE-OFFSET@ ( entry -- u )
    _RUHA-D.DGRAPH-NATIVE-OFF @ ;
: RUHA-DOCUMENT-DATA-GRAPHICS-NATIVE-BYTES@ ( entry -- u )
    _RUHA-D.DGRAPH-NATIVE-U @ ;
: RUHA-DOCUMENT-STATUS-FIELDS-DESCRIPTOR-OFFSET@ ( entry -- u )
    _RUHA-D.SFIELD-DESCRIPTOR-OFF @ ;
: RUHA-DOCUMENT-STATUS-FIELDS-DESCRIPTOR-BYTES@ ( entry -- u )
    _RUHA-D.SFIELD-DESCRIPTOR-U @ ;
: RUHA-DOCUMENT-STATUS-FIELDS-NATIVE-OFFSET@ ( entry -- u )
    _RUHA-D.SFIELD-NATIVE-OFF @ ;
: RUHA-DOCUMENT-STATUS-FIELDS-NATIVE-BYTES@ ( entry -- u )
    _RUHA-D.SFIELD-NATIVE-U @ ;

: RUHA-DOCUMENT-FIELDS-DESCRIPTOR-OFFSET@ ( entry -- u )
    _RUHA-D.FIELD-DESCRIPTOR-OFF @ ;
: RUHA-DOCUMENT-FIELDS-DESCRIPTOR-BYTES@ ( entry -- u )
    _RUHA-D.FIELD-DESCRIPTOR-U @ ;
: RUHA-DOCUMENT-FIELDS-NATIVE-OFFSET@ ( entry -- u )
    _RUHA-D.FIELD-NATIVE-OFF @ ;
: RUHA-DOCUMENT-FIELDS-NATIVE-BYTES@ ( entry -- u )
    _RUHA-D.FIELD-NATIVE-U @ ;
: RUHA-DOCUMENT-DIALOGS-DESCRIPTOR-OFFSET@ ( entry -- u )
    _RUHA-D.DIALOG-DESCRIPTOR-OFF @ ;
: RUHA-DOCUMENT-DIALOGS-DESCRIPTOR-BYTES@ ( entry -- u )
    _RUHA-D.DIALOG-DESCRIPTOR-U @ ;
: RUHA-DOCUMENT-DIALOGS-NATIVE-OFFSET@ ( entry -- u )
    _RUHA-D.DIALOG-NATIVE-OFF @ ;
: RUHA-DOCUMENT-DIALOGS-NATIVE-BYTES@ ( entry -- u )
    _RUHA-D.DIALOG-NATIVE-U @ ;
: RUHA-DOCUMENT-MENU-EPOCH@ ( entry -- generation )
    _RUHA-D.MENU-EPOCH @ ;
: RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@ ( entry -- generation )
    _RUHA-D.MENU-TOPOLOGY-EPOCH @ ;

\ Snapshot metadata is pointer-bearing and call-borrowed.  Used fields are
\ byte counts.  Directory geometry is absolute in the complete surface.
: _RUHA-S.GENERATION ( snapshot -- a )       ;
: _RUHA-S.DRAW-GENERATION ( snapshot -- a ) 8 + ;
: _RUHA-S.DIRECTORY-A ( snapshot -- a ) 16 + ;
: _RUHA-S.DIRECTORY-U ( snapshot -- a ) 24 + ;
: _RUHA-S.RECORDS-A  ( snapshot -- a ) 32 + ;
: _RUHA-S.RECORDS-U  ( snapshot -- a ) 40 + ;
: _RUHA-S.TEXT-A     ( snapshot -- a ) 48 + ;
: _RUHA-S.TEXT-U     ( snapshot -- a ) 56 + ;
: _RUHA-S.DOCUMENT-COUNT ( snapshot -- a ) 64 + ;
: _RUHA-S.CONTENT-EPOCH ( snapshot -- a ) 72 + ;
: _RUHA-S.COLLECTION-DESCRIPTORS-A ( snapshot -- a ) 80 + ;
: _RUHA-S.COLLECTION-DESCRIPTORS-U ( snapshot -- a ) 88 + ;
: _RUHA-S.COLLECTION-NATIVE-A ( snapshot -- a ) 96 + ;
: _RUHA-S.COLLECTION-NATIVE-U ( snapshot -- a ) 104 + ;
: _RUHA-S.DGRAPH-DESCRIPTORS-A ( snapshot -- a ) 112 + ;
: _RUHA-S.DGRAPH-DESCRIPTORS-U ( snapshot -- a ) 120 + ;
: _RUHA-S.DGRAPH-NATIVE-A ( snapshot -- a ) 128 + ;
: _RUHA-S.DGRAPH-NATIVE-U ( snapshot -- a ) 136 + ;

: _RUHA-S.SFIELD-DESCRIPTORS-A ( snapshot -- a ) 144 + ;
: _RUHA-S.SFIELD-DESCRIPTORS-U ( snapshot -- a ) 152 + ;
: _RUHA-S.SFIELD-NATIVE-A ( snapshot -- a ) 160 + ;
: _RUHA-S.SFIELD-NATIVE-U ( snapshot -- a ) 168 + ;
: _RUHA-S.FIELD-DESCRIPTORS-A ( snapshot -- a ) 176 + ;
: _RUHA-S.FIELD-DESCRIPTORS-U ( snapshot -- a ) 184 + ;
: _RUHA-S.FIELD-NATIVE-A ( snapshot -- a ) 192 + ;
: _RUHA-S.FIELD-NATIVE-U ( snapshot -- a ) 200 + ;
: _RUHA-S.DIALOG-DESCRIPTORS-A ( snapshot -- a ) 208 + ;
: _RUHA-S.DIALOG-DESCRIPTORS-U ( snapshot -- a ) 216 + ;
: _RUHA-S.DIALOG-NATIVE-A ( snapshot -- a ) 224 + ;
: _RUHA-S.DIALOG-NATIVE-U ( snapshot -- a ) 232 + ;

240 CONSTANT RUHA-SNAPSHOT-SIZE

: RUHA-SNAPSHOT-BYTES  ( -- bytes )  RUHA-SNAPSHOT-SIZE ;
: RUHA-SNAPSHOT-GENERATION@  ( snapshot -- generation )
    _RUHA-S.GENERATION @ ;
: RUHA-SNAPSHOT-DRAW-GENERATION@ ( snapshot -- generation )
    _RUHA-S.DRAW-GENERATION @ ;
: RUHA-SNAPSHOT-DIRECTORY@ ( snapshot -- a u )
    DUP _RUHA-S.DIRECTORY-A @ SWAP _RUHA-S.DIRECTORY-U @ ;
: RUHA-SNAPSHOT-RECORDS@  ( snapshot -- a u )
    DUP _RUHA-S.RECORDS-A @ SWAP _RUHA-S.RECORDS-U @ ;
: RUHA-SNAPSHOT-TEXT@  ( snapshot -- a u )
    DUP _RUHA-S.TEXT-A @ SWAP _RUHA-S.TEXT-U @ ;
: RUHA-SNAPSHOT-DOCUMENT-COUNT@ ( snapshot -- u )
    _RUHA-S.DOCUMENT-COUNT @ ;
: RUHA-SNAPSHOT-CONTENT-EPOCH@ ( snapshot -- generation )
    _RUHA-S.CONTENT-EPOCH @ ;
: RUHA-SNAPSHOT-COLLECTION-DESCRIPTORS@ ( snapshot -- a u )
    DUP _RUHA-S.COLLECTION-DESCRIPTORS-A @
    SWAP _RUHA-S.COLLECTION-DESCRIPTORS-U @ ;
: RUHA-SNAPSHOT-COLLECTION-NATIVE@ ( snapshot -- a u )
    DUP _RUHA-S.COLLECTION-NATIVE-A @
    SWAP _RUHA-S.COLLECTION-NATIVE-U @ ;
: RUHA-SNAPSHOT-COLLECTION-COUNT@ ( snapshot -- count )
    _RUHA-S.COLLECTION-DESCRIPTORS-U @ UCSN-DESCRIPTOR-SIZE / ;
: RUHA-SNAPSHOT-DATA-GRAPHICS-DESCRIPTORS@ ( snapshot -- a u )
    DUP _RUHA-S.DGRAPH-DESCRIPTORS-A @
    SWAP _RUHA-S.DGRAPH-DESCRIPTORS-U @ ;
: RUHA-SNAPSHOT-DATA-GRAPHICS-NATIVE@ ( snapshot -- a u )
    DUP _RUHA-S.DGRAPH-NATIVE-A @
    SWAP _RUHA-S.DGRAPH-NATIVE-U @ ;
: RUHA-SNAPSHOT-DATA-GRAPHICS-COUNT@ ( snapshot -- count )
    _RUHA-S.DGRAPH-DESCRIPTORS-U @ UDGSN-DESCRIPTOR-SIZE / ;

: RUHA-SNAPSHOT-STATUS-FIELDS-DESCRIPTORS@ ( snapshot -- a u )
    DUP _RUHA-S.SFIELD-DESCRIPTORS-A @
    SWAP _RUHA-S.SFIELD-DESCRIPTORS-U @ ;
: RUHA-SNAPSHOT-STATUS-FIELDS-NATIVE@ ( snapshot -- a u )
    DUP _RUHA-S.SFIELD-NATIVE-A @
    SWAP _RUHA-S.SFIELD-NATIVE-U @ ;
: RUHA-SNAPSHOT-STATUS-FIELDS-COUNT@ ( snapshot -- count )
    _RUHA-S.SFIELD-DESCRIPTORS-U @ USFSN-DESCRIPTOR-SIZE / ;

: RUHA-SNAPSHOT-FIELDS-DESCRIPTORS@ ( snapshot -- a u )
    DUP _RUHA-S.FIELD-DESCRIPTORS-A @
    SWAP _RUHA-S.FIELD-DESCRIPTORS-U @ ;
: RUHA-SNAPSHOT-FIELDS-NATIVE@ ( snapshot -- a u )
    DUP _RUHA-S.FIELD-NATIVE-A @
    SWAP _RUHA-S.FIELD-NATIVE-U @ ;
: RUHA-SNAPSHOT-FIELDS-COUNT@ ( snapshot -- count )
    _RUHA-S.FIELD-DESCRIPTORS-U @ UFLSN-DESCRIPTOR-SIZE / ;
: RUHA-SNAPSHOT-DIALOGS-DESCRIPTORS@ ( snapshot -- a u )
    DUP _RUHA-S.DIALOG-DESCRIPTORS-A @
    SWAP _RUHA-S.DIALOG-DESCRIPTORS-U @ ;
: RUHA-SNAPSHOT-DIALOGS-NATIVE@ ( snapshot -- a u )
    DUP _RUHA-S.DIALOG-NATIVE-A @
    SWAP _RUHA-S.DIALOG-NATIVE-U @ ;
: RUHA-SNAPSHOT-DIALOGS-COUNT@ ( snapshot -- count )
    _RUHA-S.DIALOG-DESCRIPTORS-U @ UDLSN-DESCRIPTOR-SIZE / ;

11 CONSTANT _RUHA-ABI
0x3131485544495552 CONSTANT _RUHA-MAGIC  \ "RUIDUH11"

: _RUHA-A.MAGIC          ( adapter -- a )       ;
: _RUHA-A.ABI            ( adapter -- a )   8 + ;
: _RUHA-A.SIZE           ( adapter -- a )  16 + ;
: _RUHA-A.SELF           ( adapter -- a )  24 + ;
: _RUHA-A.HOST           ( adapter -- a )  32 + ;
: _RUHA-A.RECORDS-A      ( adapter -- a )  40 + ;
: _RUHA-A.RECORDS-U      ( adapter -- a )  48 + ;
: _RUHA-A.CAPACITY       ( adapter -- a )  56 + ;
: _RUHA-A.WORK-A         ( adapter -- a )  64 + ;
: _RUHA-A.WORK-U         ( adapter -- a )  72 + ;
: _RUHA-A.WORK-TEXT-A    ( adapter -- a )  80 + ;
: _RUHA-A.WORK-TEXT-U    ( adapter -- a )  88 + ;
: _RUHA-A.SNAP-DIRECTORY-A ( adapter -- a ) 96 + ;
: _RUHA-A.SNAP-DIRECTORY-U ( adapter -- a ) 104 + ;
: _RUHA-A.SNAP-DIRECTORY-BANK-U ( adapter -- a ) 112 + ;
: _RUHA-A.SNAP-RECORDS-A ( adapter -- a ) 120 + ;
: _RUHA-A.SNAP-RECORDS-U ( adapter -- a ) 128 + ;
: _RUHA-A.SNAP-RECORD-BANK-U ( adapter -- a ) 136 + ;
: _RUHA-A.SNAP-TEXT-A    ( adapter -- a ) 144 + ;
: _RUHA-A.SNAP-TEXT-U    ( adapter -- a ) 152 + ;
: _RUHA-A.SNAP-TEXT-BANK-U ( adapter -- a ) 160 + ;
: _RUHA-A.ACTIVE-BANK    ( adapter -- a ) 168 + ;
: _RUHA-A.NEXT-TOKEN     ( adapter -- a ) 176 + ;
: _RUHA-A.GENERATION     ( adapter -- a ) 184 + ;
: _RUHA-A.LAST-STATUS    ( adapter -- a ) 192 + ;
: _RUHA-A.LAST-DRAW      ( adapter -- a ) 200 + ;
: _RUHA-A.INSTALLED      ( adapter -- a ) 208 + ;
: _RUHA-A.COLLECTION-VALIDATION-A ( adapter -- a ) 216 + ;
: _RUHA-A.COLLECTION-VALIDATION-U ( adapter -- a ) 224 + ;
: _RUHA-A.COLLECTION-WORK-A ( adapter -- a ) 232 + ;
: _RUHA-A.COLLECTION-WORK-U ( adapter -- a ) 240 + ;
: _RUHA-A.SNAP-DESCRIPTORS-A ( adapter -- a ) 248 + ;
: _RUHA-A.SNAP-DESCRIPTORS-U ( adapter -- a ) 256 + ;
: _RUHA-A.SNAP-DESCRIPTOR-BANK-U ( adapter -- a ) 264 + ;
: _RUHA-A.SNAP-NATIVE-A  ( adapter -- a ) 272 + ;
: _RUHA-A.SNAP-NATIVE-U  ( adapter -- a ) 280 + ;
: _RUHA-A.SNAP-NATIVE-BANK-U ( adapter -- a ) 288 + ;
: _RUHA-A.COLLECTION-BUILDER ( adapter -- a ) 296 + ;
\ The fields after each embedded builder or snapshot take their offsets
\ from its size, so a builder that grows cannot overwrite them.
296 USCOL-BUILDER-SIZE + CONSTANT _RUHA-O.DGRAPH
: _RUHA-A.SNAP-DGRAPH-DESCRIPTORS-A ( adapter -- a ) _RUHA-O.DGRAPH + ;
: _RUHA-A.SNAP-DGRAPH-DESCRIPTORS-U ( adapter -- a ) _RUHA-O.DGRAPH 8 + + ;
: _RUHA-A.SNAP-DGRAPH-DESCRIPTOR-BANK-U ( adapter -- a )
    _RUHA-O.DGRAPH 16 + + ;
: _RUHA-A.SNAP-DGRAPH-NATIVE-A ( adapter -- a ) _RUHA-O.DGRAPH 24 + + ;
: _RUHA-A.SNAP-DGRAPH-NATIVE-U ( adapter -- a ) _RUHA-O.DGRAPH 32 + + ;
: _RUHA-A.SNAP-DGRAPH-NATIVE-BANK-U ( adapter -- a ) _RUHA-O.DGRAPH 40 + + ;
_RUHA-O.DGRAPH 48 + CONSTANT _RUHA-O.DGRAPH-BUILDER
: _RUHA-A.DATA-GRAPHICS-BUILDER ( adapter -- a ) _RUHA-O.DGRAPH-BUILDER + ;
_RUHA-O.DGRAPH-BUILDER UDG-BUILDER-SIZE + CONSTANT _RUHA-O.SFIELD
: _RUHA-A.SNAP-SFIELD-DESCRIPTORS-A ( adapter -- a ) _RUHA-O.SFIELD + ;
: _RUHA-A.SNAP-SFIELD-DESCRIPTORS-U ( adapter -- a ) _RUHA-O.SFIELD 8 + + ;
: _RUHA-A.SNAP-SFIELD-DESCRIPTOR-BANK-U ( adapter -- a ) _RUHA-O.SFIELD 16 + + ;
: _RUHA-A.SNAP-SFIELD-NATIVE-A ( adapter -- a ) _RUHA-O.SFIELD 24 + + ;
: _RUHA-A.SNAP-SFIELD-NATIVE-U ( adapter -- a ) _RUHA-O.SFIELD 32 + + ;
: _RUHA-A.SNAP-SFIELD-NATIVE-BANK-U ( adapter -- a ) _RUHA-O.SFIELD 40 + + ;
_RUHA-O.SFIELD 48 + CONSTANT _RUHA-O.FIELD
: _RUHA-A.SNAP-FIELD-DESCRIPTORS-A ( adapter -- a ) _RUHA-O.FIELD + ;
: _RUHA-A.SNAP-FIELD-DESCRIPTORS-U ( adapter -- a ) _RUHA-O.FIELD 8 + + ;
: _RUHA-A.SNAP-FIELD-DESCRIPTOR-BANK-U ( adapter -- a ) _RUHA-O.FIELD 16 + + ;
: _RUHA-A.SNAP-FIELD-NATIVE-A ( adapter -- a ) _RUHA-O.FIELD 24 + + ;
: _RUHA-A.SNAP-FIELD-NATIVE-U ( adapter -- a ) _RUHA-O.FIELD 32 + + ;
: _RUHA-A.SNAP-FIELD-NATIVE-BANK-U ( adapter -- a ) _RUHA-O.FIELD 40 + + ;
_RUHA-O.FIELD 48 + CONSTANT _RUHA-O.DIALOG
: _RUHA-A.SNAP-DIALOG-DESCRIPTORS-A ( adapter -- a ) _RUHA-O.DIALOG + ;
: _RUHA-A.SNAP-DIALOG-DESCRIPTORS-U ( adapter -- a ) _RUHA-O.DIALOG 8 + + ;
: _RUHA-A.SNAP-DIALOG-DESCRIPTOR-BANK-U ( adapter -- a ) _RUHA-O.DIALOG 16 + + ;
: _RUHA-A.SNAP-DIALOG-NATIVE-A ( adapter -- a ) _RUHA-O.DIALOG 24 + + ;
: _RUHA-A.SNAP-DIALOG-NATIVE-U ( adapter -- a ) _RUHA-O.DIALOG 32 + + ;
: _RUHA-A.SNAP-DIALOG-NATIVE-BANK-U ( adapter -- a ) _RUHA-O.DIALOG 40 + + ;
_RUHA-O.DIALOG 48 + CONSTANT _RUHA-O.SNAPSHOT-A
: _RUHA-A.SNAPSHOT-A     ( adapter -- a ) _RUHA-O.SNAPSHOT-A + ;
_RUHA-O.SNAPSHOT-A RUHA-SNAPSHOT-SIZE + CONSTANT _RUHA-O.SNAPSHOT-B
: _RUHA-A.SNAPSHOT-B     ( adapter -- a ) _RUHA-O.SNAPSHOT-B + ;

_RUHA-O.SNAPSHOT-B RUHA-SNAPSHOT-SIZE + CONSTANT _RUHA-O.LAYERS
\ Which layers a document's roots may lie beneath (RUHA-LAYERS!).
: _RUHA-A.LAYERS         ( adapter -- a ) _RUHA-O.LAYERS + ;
\ The memory source RUHA's storage comes from, the block it holds, and the
\ copy of the document records that a build which ran short starts again
\ from.
: _RUHA-A.MEMORY         ( adapter -- a ) _RUHA-O.LAYERS 8 + + ;
: _RUHA-A.BLOCK-A        ( adapter -- a ) _RUHA-O.LAYERS 16 + + ;
: _RUHA-A.BLOCK-U        ( adapter -- a ) _RUHA-O.LAYERS 24 + + ;
: _RUHA-A.SAVE-A         ( adapter -- a ) _RUHA-O.LAYERS 32 + + ;

_RUHA-O.LAYERS 40 + CONSTANT RUHA-SIZE

: RUHA-BYTES  ( -- bytes )  RUHA-SIZE ;

: _RUHA-SPAN?  ( a u -- flag )
    OVER 0<> OVER 0> AND 0= IF 2DROP 0 EXIT THEN
    OVER 7 AND IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _RUHA-BYTE-SPAN?  ( a u -- flag )
    OVER 0<> OVER 0> AND 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _RUHA-HEADER?  ( adapter -- flag )
    DUP RUHA-SIZE _RUHA-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RUHA-A.MAGIC @ _RUHA-MAGIC =
    OVER _RUHA-A.ABI @ _RUHA-ABI = AND
    OVER _RUHA-A.SIZE @ RUHA-SIZE = AND
    OVER _RUHA-A.SELF @ 2 PICK = AND
    OVER _RUHA-A.COLLECTION-BUILDER USCOL-BUILDER-SIZE
        MSPAN-NONWRAPPING? AND
    SWAP _RUHA-A.DATA-GRAPHICS-BUILDER UDG-BUILDER-SIZE
        MSPAN-NONWRAPPING? AND ;

\ The status, field and dialog families' banks are complete A/B banks, each
\ native half holding at least one model's header.
: _RUHA-STATUS-STORAGE?  ( descriptors-a descriptors-u native-a native-u -- flag )
    2DUP _RUHA-SPAN? 0= IF 2DROP 2DROP 0 EXIT THEN
    DUP 16 MOD IF 2DROP 2DROP 0 EXIT THEN
    DUP 2 / USF-HEADER-SIZE U< IF 2DROP 2DROP 0 EXIT THEN
    2DROP
    2DUP _RUHA-SPAN? 0= IF 2DROP 0 EXIT THEN
    NIP 2 USFSN-DESCRIPTOR-SIZE * MOD 0= ;

: _RUHA-FIELD-STORAGE?  ( descriptors-a descriptors-u native-a native-u -- flag )
    2DUP _RUHA-SPAN? 0= IF 2DROP 2DROP 0 EXIT THEN
    DUP 16 MOD IF 2DROP 2DROP 0 EXIT THEN
    DUP 2 / UFLD-HEADER-SIZE U< IF 2DROP 2DROP 0 EXIT THEN
    2DROP
    2DUP _RUHA-SPAN? 0= IF 2DROP 0 EXIT THEN
    NIP 2 UFLSN-DESCRIPTOR-SIZE * MOD 0= ;

: _RUHA-DIALOG-STORAGE?  ( descriptors-a descriptors-u native-a native-u -- flag )
    2DUP _RUHA-SPAN? 0= IF 2DROP 2DROP 0 EXIT THEN
    DUP 16 MOD IF 2DROP 2DROP 0 EXIT THEN
    DUP 2 / UDLG-HEADER-SIZE U< IF 2DROP 2DROP 0 EXIT THEN
    2DROP
    2DUP _RUHA-SPAN? 0= IF 2DROP 0 EXIT THEN
    NIP 2 UDLSN-DESCRIPTOR-SIZE * MOD 0= ;

: _RUHA-STORAGE-SHAPE?  ( adapter -- flag )
    DUP _RUHA-A.RECORDS-A @ OVER _RUHA-A.RECORDS-U @
        _RUHA-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RUHA-A.RECORDS-U @ RUHA-RECORD-SIZE MOD IF DROP 0 EXIT THEN
    DUP _RUHA-A.RECORDS-U @ RUHA-RECORD-SIZE /
        OVER _RUHA-A.CAPACITY @ =
    OVER _RUHA-A.CAPACITY @ 0> AND 0= IF DROP 0 EXIT THEN
    DUP _RUHA-A.WORK-A @ OVER _RUHA-A.WORK-U @
        _RUHA-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RUHA-A.WORK-U @ UMSN-WORK-ENTRY-SIZE MOD IF DROP 0 EXIT THEN
    DUP _RUHA-A.WORK-TEXT-A @ OVER _RUHA-A.WORK-TEXT-U @
        _RUHA-BYTE-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-DIRECTORY-A @ OVER _RUHA-A.SNAP-DIRECTORY-U @
        _RUHA-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-DIRECTORY-U @ 2 MOD IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-DIRECTORY-U @ 2 /
        OVER _RUHA-A.SNAP-DIRECTORY-BANK-U @ <> IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-DIRECTORY-BANK-U @ RUHA-DOCUMENT-SIZE MOD IF
        DROP 0 EXIT
    THEN
    DUP _RUHA-A.SNAP-DIRECTORY-BANK-U @ RUHA-DOCUMENT-SIZE /
        OVER _RUHA-A.CAPACITY @ <> IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-RECORDS-A @ OVER _RUHA-A.SNAP-RECORDS-U @
        _RUHA-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-RECORDS-U @ 2 MOD IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-RECORDS-U @ 2 /
        OVER _RUHA-A.SNAP-RECORD-BANK-U @ <> IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-RECORD-BANK-U @ UMSN-RECORD-SIZE MOD IF
        DROP 0 EXIT
    THEN
    DUP _RUHA-A.SNAP-TEXT-A @ OVER _RUHA-A.SNAP-TEXT-U @
        _RUHA-BYTE-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-TEXT-U @ 2 MOD IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-TEXT-U @ 2 /
        OVER _RUHA-A.SNAP-TEXT-BANK-U @ <> IF DROP 0 EXIT THEN
    DUP _RUHA-A.COLLECTION-VALIDATION-A @
        OVER _RUHA-A.COLLECTION-VALIDATION-U @
        _RUHA-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RUHA-A.COLLECTION-WORK-A @
        OVER _RUHA-A.COLLECTION-WORK-U @
        _RUHA-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-DESCRIPTORS-A @
        OVER _RUHA-A.SNAP-DESCRIPTORS-U @
        _RUHA-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-DESCRIPTORS-U @ 2 MOD IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-DESCRIPTORS-U @ 2 /
        OVER _RUHA-A.SNAP-DESCRIPTOR-BANK-U @ <> IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-DESCRIPTOR-BANK-U @
        UCSN-DESCRIPTOR-SIZE MOD IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-DESCRIPTOR-BANK-U @ 0= IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-NATIVE-A @ OVER _RUHA-A.SNAP-NATIVE-U @
        _RUHA-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-NATIVE-U @ 2 MOD IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-NATIVE-U @ 2 /
        OVER _RUHA-A.SNAP-NATIVE-BANK-U @ <> IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-NATIVE-BANK-U @ DUP 0= SWAP 7 AND OR IF
        DROP 0 EXIT
    THEN
    DUP _RUHA-A.SNAP-DGRAPH-DESCRIPTORS-A @
        OVER _RUHA-A.SNAP-DGRAPH-DESCRIPTORS-U @
        _RUHA-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-DGRAPH-DESCRIPTORS-U @ 2 MOD IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-DGRAPH-DESCRIPTORS-U @ 2 /
        OVER _RUHA-A.SNAP-DGRAPH-DESCRIPTOR-BANK-U @ <> IF
        DROP 0 EXIT
    THEN
    DUP _RUHA-A.SNAP-DGRAPH-DESCRIPTOR-BANK-U @
        UDGSN-DESCRIPTOR-SIZE MOD IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-DGRAPH-DESCRIPTOR-BANK-U @ 0= IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-DGRAPH-NATIVE-A @
        OVER _RUHA-A.SNAP-DGRAPH-NATIVE-U @
        _RUHA-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-DGRAPH-NATIVE-U @ 2 MOD IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-DGRAPH-NATIVE-U @ 2 /
        OVER _RUHA-A.SNAP-DGRAPH-NATIVE-BANK-U @ <> IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-DGRAPH-NATIVE-BANK-U @ DUP 0= SWAP 7 AND OR IF
        DROP 0 EXIT
    THEN
    DUP _RUHA-A.SNAP-SFIELD-DESCRIPTORS-A @
    OVER _RUHA-A.SNAP-SFIELD-DESCRIPTORS-U @
    2 PICK _RUHA-A.SNAP-SFIELD-NATIVE-A @
    3 PICK _RUHA-A.SNAP-SFIELD-NATIVE-U @
        _RUHA-STATUS-STORAGE? 0= IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-SFIELD-DESCRIPTORS-U @ 2 /
        OVER _RUHA-A.SNAP-SFIELD-DESCRIPTOR-BANK-U @ <> IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-SFIELD-NATIVE-U @ 2 /
        OVER _RUHA-A.SNAP-SFIELD-NATIVE-BANK-U @ <> IF DROP 0 EXIT THEN

    DUP _RUHA-A.SNAP-FIELD-DESCRIPTORS-A @
    OVER _RUHA-A.SNAP-FIELD-DESCRIPTORS-U @
    2 PICK _RUHA-A.SNAP-FIELD-NATIVE-A @
    3 PICK _RUHA-A.SNAP-FIELD-NATIVE-U @
        _RUHA-FIELD-STORAGE? 0= IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-FIELD-DESCRIPTORS-U @ 2 /
        OVER _RUHA-A.SNAP-FIELD-DESCRIPTOR-BANK-U @ <> IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-FIELD-NATIVE-U @ 2 /
        OVER _RUHA-A.SNAP-FIELD-NATIVE-BANK-U @ <> IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-DIALOG-DESCRIPTORS-A @
    OVER _RUHA-A.SNAP-DIALOG-DESCRIPTORS-U @
    2 PICK _RUHA-A.SNAP-DIALOG-NATIVE-A @
    3 PICK _RUHA-A.SNAP-DIALOG-NATIVE-U @
        _RUHA-DIALOG-STORAGE? 0= IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-DIALOG-DESCRIPTORS-U @ 2 /
        OVER _RUHA-A.SNAP-DIALOG-DESCRIPTOR-BANK-U @ <> IF DROP 0 EXIT THEN
    DUP _RUHA-A.SNAP-DIALOG-NATIVE-U @ 2 /
        OVER _RUHA-A.SNAP-DIALOG-NATIVE-BANK-U @ <> IF DROP 0 EXIT THEN
    DROP -1 ;

: RUHA-VALID?  ( adapter -- flag )
    DUP _RUHA-HEADER? 0= IF DROP 0 EXIT THEN
    _RUHA-STORAGE-SHAPE? ;

: _RUHA-RECORD-AT  ( index adapter -- record )
    _RUHA-A.RECORDS-A @ SWAP RUHA-RECORD-SIZE * + ;

: _RUHA-SNAPSHOT-AT  ( bank adapter -- snapshot )
    SWAP IF _RUHA-A.SNAPSHOT-B ELSE _RUHA-A.SNAPSHOT-A THEN ;

: _RUHA-SNAPSHOT-DIRECTORY-A ( bank adapter -- a )
    DUP _RUHA-A.SNAP-DIRECTORY-BANK-U @ 2 PICK *
    SWAP _RUHA-A.SNAP-DIRECTORY-A @ + NIP ;

: _RUHA-SNAPSHOT-RECORD-A  ( bank adapter -- a )
    DUP _RUHA-A.SNAP-RECORD-BANK-U @ 2 PICK *
    SWAP _RUHA-A.SNAP-RECORDS-A @ + NIP ;

: _RUHA-SNAPSHOT-TEXT-A  ( bank adapter -- a )
    DUP _RUHA-A.SNAP-TEXT-BANK-U @ 2 PICK *
    SWAP _RUHA-A.SNAP-TEXT-A @ + NIP ;

: _RUHA-SNAPSHOT-DESCRIPTOR-A  ( bank adapter -- a )
    DUP _RUHA-A.SNAP-DESCRIPTOR-BANK-U @ 2 PICK *
    SWAP _RUHA-A.SNAP-DESCRIPTORS-A @ + NIP ;

: _RUHA-SNAPSHOT-NATIVE-A  ( bank adapter -- a )
    DUP _RUHA-A.SNAP-NATIVE-BANK-U @ 2 PICK *
    SWAP _RUHA-A.SNAP-NATIVE-A @ + NIP ;

: _RUHA-SNAPSHOT-DGRAPH-DESCRIPTOR-A  ( bank adapter -- a )
    DUP _RUHA-A.SNAP-DGRAPH-DESCRIPTOR-BANK-U @ 2 PICK *
    SWAP _RUHA-A.SNAP-DGRAPH-DESCRIPTORS-A @ + NIP ;

: _RUHA-SNAPSHOT-SFIELD-DESCRIPTOR-A  ( bank adapter -- a )
    DUP _RUHA-A.SNAP-SFIELD-DESCRIPTOR-BANK-U @ 2 PICK *
    SWAP _RUHA-A.SNAP-SFIELD-DESCRIPTORS-A @ + NIP ;

: _RUHA-SNAPSHOT-FIELD-DESCRIPTOR-A  ( bank adapter -- a )
    DUP _RUHA-A.SNAP-FIELD-DESCRIPTOR-BANK-U @ 2 PICK *
    SWAP _RUHA-A.SNAP-FIELD-DESCRIPTORS-A @ + NIP ;

: _RUHA-SNAPSHOT-DIALOG-DESCRIPTOR-A  ( bank adapter -- a )
    DUP _RUHA-A.SNAP-DIALOG-DESCRIPTOR-BANK-U @ 2 PICK *
    SWAP _RUHA-A.SNAP-DIALOG-DESCRIPTORS-A @ + NIP ;

: _RUHA-SNAPSHOT-DGRAPH-NATIVE-A  ( bank adapter -- a )
    DUP _RUHA-A.SNAP-DGRAPH-NATIVE-BANK-U @ 2 PICK *
    SWAP _RUHA-A.SNAP-DGRAPH-NATIVE-A @ + NIP ;

: _RUHA-SNAPSHOT-SFIELD-NATIVE-A  ( bank adapter -- a )
    DUP _RUHA-A.SNAP-SFIELD-NATIVE-BANK-U @ 2 PICK *
    SWAP _RUHA-A.SNAP-SFIELD-NATIVE-A @ + NIP ;

: _RUHA-SNAPSHOT-FIELD-NATIVE-A  ( bank adapter -- a )
    DUP _RUHA-A.SNAP-FIELD-NATIVE-BANK-U @ 2 PICK *
    SWAP _RUHA-A.SNAP-FIELD-NATIVE-A @ + NIP ;

: _RUHA-SNAPSHOT-DIALOG-NATIVE-A  ( bank adapter -- a )
    DUP _RUHA-A.SNAP-DIALOG-NATIVE-BANK-U @ 2 PICK *
    SWAP _RUHA-A.SNAP-DIALOG-NATIVE-A @ + NIP ;

\ Every mutable caller span must be disjoint from the complete authority of
\ the current UCTX, including canonical widgets mounted below UIDL-TUI.  The
\ semantic-widget query is status-bearing because malformed source state must
\ not be mistaken for a proof of disjointness.
: _RUHA-CURRENT-AUTHORITY-DISJOINT?  ( address bytes -- flag )
    2DUP USCOL-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DUP TXTA-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DUP TGRID-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DUP UDG-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DUP DGRAPH-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DUP USF-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DUP USFSN-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN

    2DUP UFLD-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DUP FLD-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DUP UFLSN-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DUP UDLG-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DUP UDLSN-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DUP DGF-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DUP UTUI-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    UTUI-COLLECTION-STORAGE-DISJOINT?
    DUP USCOL-S-OK <> IF 2DROP 0 EXIT THEN
    DROP ;

\ Begin the protected module-owned range before the first mutable scratch
\ cell.  Constructor validation must reject aliases before any helper stores.
CREATE _RUHA-OWNED-START
VARIABLE _RUHA-OWNED-LIMIT

VARIABLE _RUHA-SAFE-ADAPTER

: _RUHA-STORAGE-SPANS?  ( predicate-xt -- flag )
    >R
    _RUHA-SAFE-ADAPTER @ _RUHA-A.RECORDS-A @
        _RUHA-SAFE-ADAPTER @ _RUHA-A.RECORDS-U @
        R@ EXECUTE 0= IF R> DROP 0 EXIT THEN
    _RUHA-SAFE-ADAPTER @ _RUHA-A.WORK-A @
        _RUHA-SAFE-ADAPTER @ _RUHA-A.WORK-U @
        R@ EXECUTE 0= IF R> DROP 0 EXIT THEN
    _RUHA-SAFE-ADAPTER @ _RUHA-A.WORK-TEXT-A @
        _RUHA-SAFE-ADAPTER @ _RUHA-A.WORK-TEXT-U @
        R@ EXECUTE 0= IF R> DROP 0 EXIT THEN
    _RUHA-SAFE-ADAPTER @ _RUHA-A.COLLECTION-VALIDATION-A @
        _RUHA-SAFE-ADAPTER @ _RUHA-A.COLLECTION-VALIDATION-U @
        R@ EXECUTE 0= IF R> DROP 0 EXIT THEN
    _RUHA-SAFE-ADAPTER @ _RUHA-A.COLLECTION-WORK-A @
        _RUHA-SAFE-ADAPTER @ _RUHA-A.COLLECTION-WORK-U @
        R@ EXECUTE 0= IF R> DROP 0 EXIT THEN
    _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-DIRECTORY-A @
        _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-DIRECTORY-U @
        R@ EXECUTE 0= IF R> DROP 0 EXIT THEN
    _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-RECORDS-A @
        _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-RECORDS-U @
        R@ EXECUTE 0= IF R> DROP 0 EXIT THEN
    _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-TEXT-A @
        _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-TEXT-U @
        R@ EXECUTE 0= IF R> DROP 0 EXIT THEN
    _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-DESCRIPTORS-A @
        _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-DESCRIPTORS-U @
        R@ EXECUTE 0= IF R> DROP 0 EXIT THEN
    _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-NATIVE-A @
        _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-NATIVE-U @
        R@ EXECUTE 0= IF R> DROP 0 EXIT THEN
    _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-DGRAPH-DESCRIPTORS-A @
        _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-DGRAPH-DESCRIPTORS-U @
        R@ EXECUTE 0= IF R> DROP 0 EXIT THEN
    _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-DGRAPH-NATIVE-A @
        _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-DGRAPH-NATIVE-U @
        R@ EXECUTE 0= IF R> DROP 0 EXIT THEN
    _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-SFIELD-DESCRIPTORS-A @
        _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-SFIELD-DESCRIPTORS-U @
        R@ EXECUTE 0= IF R> DROP 0 EXIT THEN
    _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-SFIELD-NATIVE-A @
        _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-SFIELD-NATIVE-U @
        R@ EXECUTE 0= IF R> DROP 0 EXIT THEN
    _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-FIELD-DESCRIPTORS-A @
        _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-FIELD-DESCRIPTORS-U @
        R@ EXECUTE 0= IF R> DROP 0 EXIT THEN
    _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-FIELD-NATIVE-A @
        _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-FIELD-NATIVE-U @
        R@ EXECUTE 0= IF R> DROP 0 EXIT THEN
    _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-DIALOG-DESCRIPTORS-A @
        _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-DIALOG-DESCRIPTORS-U @
        R@ EXECUTE 0= IF R> DROP 0 EXIT THEN
    _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-DIALOG-NATIVE-A @
        _RUHA-SAFE-ADAPTER @ _RUHA-A.SNAP-DIALOG-NATIVE-U @
        R@ EXECUTE 0= IF R> DROP 0 EXIT THEN
    _RUHA-SAFE-ADAPTER @ _RUHA-A.SAVE-A @
        _RUHA-SAFE-ADAPTER @ _RUHA-A.RECORDS-U @
        R@ EXECUTE 0= IF R> DROP 0 EXIT THEN
    _RUHA-SAFE-ADAPTER @ RUHA-SIZE
        R> EXECUTE ;


20 CONSTANT _RUHA-SAFE-SPAN-CAPACITY
CREATE _RUHA-SAFE-SPANS _RUHA-SAFE-SPAN-CAPACITY MSPAN-SET-BYTES ALLOT

\ RUHA admits no span at address zero and no empty or negative length.
: _RUHA-SAFE-ADMIT?  ( address bytes -- flag )
    OVER 0= OVER 0> 0= OR IF 2DROP 0 EXIT THEN
    _RUHA-SAFE-SPANS MSPAN-SET-PUSH MSPAN-SET-S-OK = ;

\ Prove every adapter span, including the adapter itself, with PROOF.
\ MSPAN-SET-PROVE-DISJOINT? queries the enclosure of clustered storage once
\ and splits fragmented storage until an actual span proves unsafe or every
\ group is disjoint.  A successful broad proof still covers all spans.
: _RUHA-SAFE-PROVE?  ( adapter proof-xt -- flag )
    SWAP _RUHA-SAFE-ADAPTER !
    _RUHA-SAFE-SPAN-CAPACITY _RUHA-SAFE-SPANS MSPAN-SET-INIT
        MSPAN-SET-S-OK <> IF DROP 0 EXIT THEN
    ['] _RUHA-SAFE-ADMIT? _RUHA-STORAGE-SPANS? 0= IF DROP 0 EXIT THEN
    _RUHA-SAFE-SPANS SWAP MSPAN-SET-PROVE-DISJOINT? ;

\ Rebuild every proof in the current UCTX.
: _RUHA-STORAGE-DISJOINT-CURRENT?  ( adapter -- flag )
    ['] _RUHA-CURRENT-AUTHORITY-DISJOINT? _RUHA-SAFE-PROVE? ;

\ The aggregate capture reads screen-owned painter-order provenance while it
\ writes the inactive caller-owned snapshot bank.  Prove that every mutable
\ adapter span is outside the complete active-screen storage graph once per
\ draw, before any record switch or bank mutation.  Full A/B snapshot spans
\ are checked because publication swaps their active roles.  Clustered
\ adapter storage needs one screen query; fragments split exactly as above.
: _RUHA-SCREEN-STORAGE-DISJOINT?  ( adapter -- flag )
    ['] SCR-STORAGE-DISJOINT? _RUHA-SAFE-PROVE? ;

\ What a check that runs only with every-frame checks on names when it
\ fails (check-mode.f): RUHA's banks, when a proof that they lie apart from
\ the storage a draw reads fails, and the slices stored in them, when a
\ stored slice or menu record fails its validation before reuse.
: _RUHA-BANKS-DAMAGED  ( -- c-addr u )  S" the snapshot adapter's banks" ;
: _RUHA-SLICES-DAMAGED  ( -- c-addr u )
    S" the snapshot adapter's stored slices" ;

\ =====================================================================
\  Storage
\ =====================================================================
\
\ RUHA keeps its two snapshot banks, its work spans and a copy of its
\ document records in one block it takes from the memory source its caller
\ gives it (memory-source.f).  Each of the thirteen bank spans holds both
\ banks, A then B, each of the bank's bytes; each work span and the copy
\ hold one.  A bank's growable spans start from the capacities RUHA-INIT is
\ given, and the other spans follow from them and the records' count:
\
\   directory               an entry for every document record
\   dialog descriptors      one for every document record
\   menu work and text      one document's elements and strings
\   collection validation   the collection native bank
\   collection work         the collection descriptors' work, or the status
\                           fields' or fields' frozen work, whichever is most
\
\ A build that runs short in a family doubles that family's growable spans
\ and builds again (_RUHA-G-GROW?), so a bank grows to what its snapshots
\ need and up to as much again.

: _RUHA-UADD?  ( a b -- sum flag )
    OVER + DUP ROT U< 0= ;

-1 1 RSHIFT CONSTANT _RUHA-SIGNED-MAX

: _RUHA-UMUL?  ( a b -- product flag )
    2DUP 0< SWAP 0< OR IF 2DROP 0 0 EXIT THEN
    2DUP 0= SWAP 0= OR IF 2DROP 0 -1 EXIT THEN
    _RUHA-SIGNED-MAX 2 PICK / OVER U< IF 2DROP 0 0 EXIT THEN
    * -1 ;

\ The families of a document's capture, as bits.
1  CONSTANT RUHA-F-MENUS
2  CONSTANT RUHA-F-COLLECTIONS
4  CONSTANT RUHA-F-DATA-GRAPHICS
8  CONSTANT RUHA-F-STATUS-FIELDS
16 CONSTANT RUHA-F-FIELDS
32 CONSTANT RUHA-F-DIALOGS

\ The capacities a bank's growable spans take, in this order: menu records,
\ menu text, collection descriptors and native, data-graphics descriptors
\ and native, status-field descriptors and native, field descriptors and
\ native, and dialog native.  Each is whole in its records and holds at
\ least one; RUHA-FIRST-CAPACITIES are the ones a caller starts from.
11 CONSTANT RUHA-CAPACITY-COUNT
CREATE RUHA-FIRST-CAPACITIES
    8 UMSN-RECORD-SIZE * ,        1024 ,
    8 UCSN-DESCRIPTOR-SIZE * ,    4096 ,
    2 UDGSN-DESCRIPTOR-SIZE * ,   1024 ,
    8 USFSN-DESCRIPTOR-SIZE * ,   1024 ,
    4 UFLSN-DESCRIPTOR-SIZE * ,   1024 ,
    1024 ,

\ Each growable capacity's unit and least value.
CREATE _RUHA-G-UNITS
    UMSN-RECORD-SIZE , UMSN-RECORD-SIZE ,      8 , 8 ,
    UCSN-DESCRIPTOR-SIZE , UCSN-DESCRIPTOR-SIZE ,  8 , 8 ,
    UDGSN-DESCRIPTOR-SIZE , UDGSN-DESCRIPTOR-SIZE ,  8 , 8 ,
    USFSN-DESCRIPTOR-SIZE , USFSN-DESCRIPTOR-SIZE ,  8 , USF-HEADER-SIZE ,
    UFLSN-DESCRIPTOR-SIZE , UFLSN-DESCRIPTOR-SIZE ,  8 , UFLD-HEADER-SIZE ,
    8 , UDLG-HEADER-SIZE ,

\ The spans in their order in the block, by the adapter field that holds
\ each one's address; its total bytes follow that field, and a bank span's
\ bank bytes follow those.  The first thirteen are bank spans.
17 CONSTANT _RUHA-G-SPANS
13 CONSTANT _RUHA-G-BANKED
CREATE _RUHA-G-FIELDS
    0 _RUHA-A.SNAP-DIRECTORY-A ,          0 _RUHA-A.SNAP-RECORDS-A ,
    0 _RUHA-A.SNAP-TEXT-A ,               0 _RUHA-A.SNAP-DESCRIPTORS-A ,
    0 _RUHA-A.SNAP-NATIVE-A ,             0 _RUHA-A.SNAP-DGRAPH-DESCRIPTORS-A ,
    0 _RUHA-A.SNAP-DGRAPH-NATIVE-A ,      0 _RUHA-A.SNAP-SFIELD-DESCRIPTORS-A ,
    0 _RUHA-A.SNAP-SFIELD-NATIVE-A ,      0 _RUHA-A.SNAP-FIELD-DESCRIPTORS-A ,
    0 _RUHA-A.SNAP-FIELD-NATIVE-A ,       0 _RUHA-A.SNAP-DIALOG-DESCRIPTORS-A ,
    0 _RUHA-A.SNAP-DIALOG-NATIVE-A ,      0 _RUHA-A.WORK-A ,
    0 _RUHA-A.WORK-TEXT-A ,               0 _RUHA-A.COLLECTION-VALIDATION-A ,
    0 _RUHA-A.COLLECTION-WORK-A ,
\ The bank spans' address fields in a snapshot record, in the same order.
CREATE _RUHA-G-SNAP-FIELDS
    0 _RUHA-S.DIRECTORY-A ,               0 _RUHA-S.RECORDS-A ,
    0 _RUHA-S.TEXT-A ,                    0 _RUHA-S.COLLECTION-DESCRIPTORS-A ,
    0 _RUHA-S.COLLECTION-NATIVE-A ,       0 _RUHA-S.DGRAPH-DESCRIPTORS-A ,
    0 _RUHA-S.DGRAPH-NATIVE-A ,           0 _RUHA-S.SFIELD-DESCRIPTORS-A ,
    0 _RUHA-S.SFIELD-NATIVE-A ,           0 _RUHA-S.FIELD-DESCRIPTORS-A ,
    0 _RUHA-S.FIELD-NATIVE-A ,            0 _RUHA-S.DIALOG-DESCRIPTORS-A ,
    0 _RUHA-S.DIALOG-NATIVE-A ,
\ The span each growable capacity sizes.
CREATE _RUHA-G-GROWABLE  1 , 2 , 3 , 4 , 5 , 6 , 7 , 8 , 9 , 10 , 12 ,

: _RUHA-G-FIELD  ( span adapter -- a )  SWAP CELLS _RUHA-G-FIELDS + @ + ;
: _RUHA-G-SNAP-FIELD  ( span snapshot -- a )
    SWAP CELLS _RUHA-G-SNAP-FIELDS + @ + ;

\ The capacity a layout gives each span: a bank span's bank bytes, or the
\ span's bytes.  OLD keeps the capacities of the block being replaced.
CREATE _RUHA-G-CAP _RUHA-G-SPANS CELLS ALLOT
CREATE _RUHA-G-OLD _RUHA-G-SPANS CELLS ALLOT
: _RUHA-G-CAP@  ( span -- u )  CELLS _RUHA-G-CAP + @ ;
: _RUHA-G-CAP!  ( u span -- )  CELLS _RUHA-G-CAP + ! ;
: _RUHA-G-ALIGN  ( u -- u' )  7 + -8 AND ;

\ Whether U fits growable capacity K: whole in its unit, at least its least.
: _RUHA-G-FIT?  ( u k -- flag )
    2* CELLS _RUHA-G-UNITS + DUP @ SWAP CELL+ @
    2 PICK SWAP U< IF 2DROP 0 EXIT THEN
    MOD 0= ;

\ The capacities the adapter's fields hold now.
: _RUHA-G-READ  ( adapter -- )
    _RUHA-G-SPANS 0 ?DO
        I OVER _RUHA-G-FIELD I _RUHA-G-BANKED < IF 16 ELSE 8 THEN + @
        I _RUHA-G-CAP!
    LOOP DROP ;

\ The capacities that follow from the growable ones and from COUNT records.
: _RUHA-G-DERIVE  ( count -- flag )
    DUP RUHA-DOCUMENT-SIZE _RUHA-UMUL? 0= IF 2DROP 0 EXIT THEN
        0 _RUHA-G-CAP!
    UDLSN-DESCRIPTOR-SIZE _RUHA-UMUL? 0= IF DROP 0 EXIT THEN 11 _RUHA-G-CAP!
    _UTUI-MAX-ELEMS UMSN-WORK-ENTRY-SIZE * 13 _RUHA-G-CAP!
    _UCTX-STRS-SZ 14 _RUHA-G-CAP!
    4 _RUHA-G-CAP@ 15 _RUHA-G-CAP!
    _UTUI-MAX-ELEMS 3 _RUHA-G-CAP@ UCSN-DESCRIPTOR-SIZE / UCSN-WORK-BYTES
    DUP 0= IF DROP 0 EXIT THEN
    7 _RUHA-G-CAP@ USFSN-DESCRIPTOR-SIZE / USFSN-FROZEN-WORK-BYTES MAX
    9 _RUHA-G-CAP@ UFLSN-DESCRIPTOR-SIZE / UFLSN-FROZEN-WORK-BYTES MAX
    _RUHA-G-ALIGN 16 _RUHA-G-CAP! -1 ;

\ The bytes a layout of _RUHA-G-CAP takes with a copy of RECORDS-U bytes of
\ records, or 0 when they overflow.
: _RUHA-G-BYTES  ( records-u -- bytes )
    _RUHA-G-ALIGN
    _RUHA-G-SPANS 0 ?DO
        I _RUHA-G-CAP@ _RUHA-G-ALIGN
        I _RUHA-G-BANKED < IF DUP _RUHA-UADD? 0= IF 2DROP 0 UNLOOP EXIT THEN THEN
        _RUHA-UADD? 0= IF DROP 0 UNLOOP EXIT THEN
    LOOP ;

\ Lay the spans out in BLOCK from _RUHA-G-CAP, in their order, with the
\ records' copy after them.
VARIABLE _RUHA-G-ADAPTER
VARIABLE _RUHA-G-AT
VARIABLE _RUHA-G-F
: _RUHA-G-PLACE  ( block adapter -- )
    _RUHA-G-ADAPTER ! _RUHA-G-AT !
    _RUHA-G-SPANS 0 ?DO
        I _RUHA-G-ADAPTER @ _RUHA-G-FIELD _RUHA-G-F !
        _RUHA-G-AT @ _RUHA-G-F @ !
        I _RUHA-G-CAP@
        I _RUHA-G-BANKED < IF DUP _RUHA-G-F @ 16 + ! 2* THEN
        DUP _RUHA-G-F @ 8 + !
        _RUHA-G-ALIGN _RUHA-G-AT +!
    LOOP
    _RUHA-G-AT @ _RUHA-G-ADAPTER @ _RUHA-A.SAVE-A ! ;

\ =====================================================================
\  Construction
\ =====================================================================

: _RUHA-I-OWNED-DISJOINT?  ( address bytes -- flag )
    DUP 0= IF 2DROP -1 EXIT THEN
    _RUHA-OWNED-LIMIT @ DUP _RUHA-OWNED-START U< IF
        DROP 2DROP 0 EXIT
    THEN
    _RUHA-OWNED-START - >R
    _RUHA-OWNED-START R> MSPAN-OVERLAP? 0= ;

VARIABLE _RUHA-I-RECORDS-A
VARIABLE _RUHA-I-RECORDS-U
VARIABLE _RUHA-I-CAPS
VARIABLE _RUHA-I-MEMORY
VARIABLE _RUHA-I-ADAPTER
VARIABLE _RUHA-I-BLOCK
VARIABLE _RUHA-I-BYTES

\ A span the caller lends, or the block RUHA takes, lies apart from RUHA's
\ own storage and from the current UCTX's authority.
: _RUHA-I-APART?  ( address bytes -- flag )
    2DUP _RUHA-I-OWNED-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    _RUHA-CURRENT-AUTHORITY-DISJOINT? ;

\ The records and the adapter are whole, apart from each other and from
\ RUHA's storage and the current authority, MEMORY is a memory source, and
\ every capacity fits.
: _RUHA-I-ARGUMENTS?  ( -- flag )
    _RUHA-I-ADAPTER @ RUHA-SIZE _RUHA-SPAN? 0= IF 0 EXIT THEN
    _RUHA-I-RECORDS-A @ _RUHA-I-RECORDS-U @ _RUHA-SPAN? 0= IF 0 EXIT THEN
    _RUHA-I-RECORDS-U @ RUHA-RECORD-SIZE MOD IF 0 EXIT THEN
    _RUHA-I-MEMORY @ MSRC-VALID? 0= IF 0 EXIT THEN
    \ The capacities are only read, and a CREATE table need not lie on a cell.
    _RUHA-I-CAPS @ RUHA-CAPACITY-COUNT CELLS _RUHA-BYTE-SPAN? 0= IF 0 EXIT THEN
    RUHA-CAPACITY-COUNT 0 ?DO
        _RUHA-I-CAPS @ I CELLS + @ I _RUHA-G-FIT? 0= IF 0 UNLOOP EXIT THEN
    LOOP
    _RUHA-I-RECORDS-A @ _RUHA-I-RECORDS-U @
        _RUHA-I-ADAPTER @ RUHA-SIZE MSPAN-OVERLAP? IF 0 EXIT THEN
    _RUHA-I-RECORDS-A @ _RUHA-I-RECORDS-U @ _RUHA-I-APART? 0= IF 0 EXIT THEN
    _RUHA-I-ADAPTER @ RUHA-SIZE _RUHA-I-APART? ;

\ The layout the capacities give, in _RUHA-G-CAP, and its bytes, or 0.
: _RUHA-I-LAYOUT  ( -- bytes )
    RUHA-CAPACITY-COUNT 0 ?DO
        _RUHA-I-CAPS @ I CELLS + @
        I CELLS _RUHA-G-GROWABLE + @ _RUHA-G-CAP!
    LOOP
    _RUHA-I-RECORDS-U @ RUHA-RECORD-SIZE / _RUHA-G-DERIVE 0= IF 0 EXIT THEN
    _RUHA-I-RECORDS-U @ _RUHA-G-BYTES ;

: _RUHA-I-SCRUB  ( -- )
    0 _RUHA-I-RECORDS-A ! 0 _RUHA-I-RECORDS-U ! 0 _RUHA-I-CAPS !
    0 _RUHA-I-MEMORY ! 0 _RUHA-I-ADAPTER ! 0 _RUHA-I-BLOCK !
    0 _RUHA-I-BYTES ! ;

\ RUHA-INIT ( records-a records-u capacities memory adapter -- status )
\   Make ADAPTER with RECORDS-U bytes of document records at RECORDS-A, a
\   record for each document it can hold, and its storage taken from MEMORY:
\   one block whose banks' growable spans have the RUHA-CAPACITY-COUNT
\   capacities at CAPACITIES, and grow as captures need.  INVALID when a
\   span is malformed or lies over storage RUHA keeps apart, or a capacity
\   does not fit; CAPACITY when MEMORY refuses the block.
: RUHA-INIT  ( records-a records-u capacities memory adapter -- status )
    _RUHA-I-ADAPTER ! _RUHA-I-MEMORY ! _RUHA-I-CAPS !
    _RUHA-I-RECORDS-U ! _RUHA-I-RECORDS-A !
    _RUHA-I-ARGUMENTS? 0= IF _RUHA-I-SCRUB RUHA-S-INVALID EXIT THEN
    _RUHA-I-LAYOUT DUP 0= IF DROP _RUHA-I-SCRUB RUHA-S-INVALID EXIT THEN
    DUP _RUHA-I-BYTES ! _RUHA-I-MEMORY @ MSRC-ALLOC DUP _RUHA-I-BLOCK !
    0= IF _RUHA-I-SCRUB RUHA-S-CAPACITY EXIT THEN
    _RUHA-I-BLOCK @ _RUHA-I-BYTES @ _RUHA-I-APART?
    _RUHA-I-BLOCK @ _RUHA-I-BYTES @
        _RUHA-I-RECORDS-A @ _RUHA-I-RECORDS-U @ MSPAN-OVERLAP? 0= AND
    _RUHA-I-BLOCK @ _RUHA-I-BYTES @
        _RUHA-I-ADAPTER @ RUHA-SIZE MSPAN-OVERLAP? 0= AND
    _RUHA-BANKS-DAMAGED CHK-HANDOVER 0= IF
        _RUHA-I-BLOCK @ _RUHA-I-BYTES @ _RUHA-I-MEMORY @ MSRC-FREE
        _RUHA-I-SCRUB RUHA-S-INVALID EXIT
    THEN

    \ Host records are the one capacity-scanned bank and therefore require a
    \ known FREE state.  Scratch is initialized through exact dirty prefixes,
    \ inactive snapshot payload is append-only and published only through its
    \ used lengths.  Neither class makes unused capacity adapter state.
    _RUHA-I-RECORDS-A @ _RUHA-I-RECORDS-U @ 0 FILL
    _RUHA-I-ADAPTER @ RUHA-SIZE 0 FILL

    _RUHA-ABI _RUHA-I-ADAPTER @ _RUHA-A.ABI !
    RUHA-SIZE _RUHA-I-ADAPTER @ _RUHA-A.SIZE !
    _RUHA-I-ADAPTER @ DUP _RUHA-A.SELF !
    _RUHA-I-RECORDS-A @ _RUHA-I-ADAPTER @ _RUHA-A.RECORDS-A !
    _RUHA-I-RECORDS-U @ _RUHA-I-ADAPTER @ _RUHA-A.RECORDS-U !
    _RUHA-I-RECORDS-U @ RUHA-RECORD-SIZE /
        _RUHA-I-ADAPTER @ _RUHA-A.CAPACITY !
    _RUHA-I-MEMORY @ _RUHA-I-ADAPTER @ _RUHA-A.MEMORY !
    _RUHA-I-BLOCK @ _RUHA-I-ADAPTER @ _RUHA-A.BLOCK-A !
    _RUHA-I-BYTES @ _RUHA-I-ADAPTER @ _RUHA-A.BLOCK-U !
    _RUHA-I-BLOCK @ _RUHA-I-ADAPTER @ _RUHA-G-PLACE
    -1 _RUHA-I-ADAPTER @ _RUHA-A.ACTIVE-BANK !
    1 _RUHA-I-ADAPTER @ _RUHA-A.NEXT-TOKEN !
    RUHA-S-UNAVAILABLE _RUHA-I-ADAPTER @ _RUHA-A.LAST-STATUS !
    _RUHA-MAGIC _RUHA-I-ADAPTER @ _RUHA-A.MAGIC !
    _RUHA-I-SCRUB RUHA-S-OK ;

\ RUHA-FINI ( adapter -- )
\   Give back the block ADAPTER took from its memory source and clear it.
\   Call it once nothing will query the adapter or read its snapshots; the
\   producer copies a snapshot when it takes one, so it holds none of them.
: RUHA-FINI  ( adapter -- )
    DUP _RUHA-HEADER? IF
        DUP _RUHA-A.MEMORY @ ?DUP IF
            OVER _RUHA-A.BLOCK-A @ ?DUP IF
                2 PICK _RUHA-A.BLOCK-U @ ROT MSRC-FREE
            ELSE DROP THEN
        THEN
    THEN
    RUHA-SIZE 0 FILL ;

\ =====================================================================
\  Binding lookup and live identity
\ =====================================================================

VARIABLE _RUHA-CHECK-SLOT
VARIABLE _RUHA-CHECK-HOST
VARIABLE _RUHA-CHECK-RECORD
\ Source provenance is read only after every mutable adapter span is proved
\ disjoint from the actual CINST, complete descriptor and state. No allocation
\ registry exists at the component layer: use its canonical descriptor checks.
VARIABLE _RUHA-O-ADAPTER
VARIABLE _RUHA-O-INSTANCE
VARIABLE _RUHA-O-DESC
VARIABLE _RUHA-O-A
VARIABLE _RUHA-O-U
: _RUHA-O-DISJOINT? ( a u -- flag )
    _RUHA-O-A @ _RUHA-O-U @ MSPAN-OVERLAP? 0= ;
: _RUHA-O-SPAN? ( a u -- flag )
    OVER 0= OVER 0> 0= OR IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    2DUP _RUHA-I-OWNED-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    _RUHA-O-U ! _RUHA-O-A !
    _RUHA-O-ADAPTER @ _RUHA-SAFE-ADAPTER !
    ['] _RUHA-O-DISJOINT? _RUHA-STORAGE-SPANS? ;
\ A slot's owner as a draw needs it: an instance with a valid descriptor,
\ whose state size is not negative, and a live identity.
: _RUHA-OWNER-NAMED? ( slot -- flag )
    AHS.INST @ DUP 0= IF EXIT THEN
    DUP CINST.DESC @ DUP 0= IF NIP EXIT THEN
    DUP COMP-DESC-VALID? 0= IF 2DROP 0 EXIT THEN
    COMP.STATE-SIZE @ 0< IF DROP 0 EXIT THEN
    DUP CINST.ID @ 0= SWAP CINST.GENERATION @ 0= OR 0= ;
: _RUHA-LIVE-OWNER? ( slot adapter -- flag )
    _RUHA-O-ADAPTER ! AHS.INST @
    DUP COMP-INST _RUHA-O-SPAN? 0= IF DROP 0 EXIT THEN
    _RUHA-O-INSTANCE !
    _RUHA-O-INSTANCE @ CINST.DESC @
    DUP COMP-DESC _RUHA-O-SPAN? 0= IF DROP 0 EXIT THEN
    DUP COMP-DESC-VALID? 0= IF DROP 0 EXIT THEN _RUHA-O-DESC !
    _RUHA-O-DESC @ DUP COMP.SIZE @ _RUHA-O-SPAN? 0= IF 0 EXIT THEN
    _RUHA-O-INSTANCE @ CINST.ID @ 0=
    _RUHA-O-INSTANCE @ CINST.GENERATION @ 0= OR IF 0 EXIT THEN
    _RUHA-O-DESC @ COMP.STATE-SIZE @ DUP 0< IF DROP 0 EXIT THEN
    DUP IF _RUHA-O-INSTANCE @ CINST.STATE @ SWAP _RUHA-O-SPAN?
    ELSE DROP -1 THEN ;

VARIABLE _RUHA-CHECK-ADAPTER

: _RUHA-HOST-HAS-SLOT?  ( slot host -- flag )
    _RUHA-CHECK-HOST ! _RUHA-CHECK-SLOT !
    _RUHA-CHECK-HOST @ AHOST.HEAD @
    BEGIN ?DUP WHILE
        DUP _RUHA-CHECK-SLOT @ = IF DROP -1 EXIT THEN
        AHS.NEXT @
    REPEAT
    0 ;

VARIABLE _RUHA-L-TOKEN
VARIABLE _RUHA-L-ADAPTER
VARIABLE _RUHA-L-RECORD
VARIABLE _RUHA-L-MATCHES

: _RUHA-LOOKUP  ( token adapter -- record status )
    _RUHA-L-ADAPTER ! _RUHA-L-TOKEN !
    _RUHA-L-ADAPTER @ RUHA-VALID? 0= IF 0 RUHA-S-INVALID EXIT THEN
    _RUHA-L-TOKEN @ 0= IF 0 RUHA-S-INVALID EXIT THEN
    0 _RUHA-L-RECORD ! 0 _RUHA-L-MATCHES !
    _RUHA-L-ADAPTER @ _RUHA-A.CAPACITY @ 0 ?DO
        I _RUHA-L-ADAPTER @ _RUHA-RECORD-AT
        DUP _RUHA-R.STATE @ _RUHA-RECORD-FREE <> IF
            DUP _RUHA-R.TOKEN @ _RUHA-L-TOKEN @ = IF
                DUP _RUHA-L-RECORD ! 1 _RUHA-L-MATCHES +!
            THEN
        THEN
        DROP
    LOOP
    _RUHA-L-MATCHES @ 1 <> IF 0 RUHA-S-STALE EXIT THEN
    _RUHA-L-RECORD @ RUHA-S-OK ;

: _RUHA-RECORD-IDENTITY?  ( record adapter -- flag )
    _RUHA-CHECK-ADAPTER ! _RUHA-CHECK-RECORD !
    _RUHA-CHECK-RECORD @ _RUHA-R.FLAGS @ _RUHA-RF-MASK INVERT AND IF
        0 EXIT
    THEN
    _RUHA-CHECK-RECORD @ _RUHA-R.SLOT @ DUP
    _RUHA-CHECK-ADAPTER @ _RUHA-A.HOST @
        _RUHA-HOST-HAS-SLOT? 0= IF DROP 0 EXIT THEN
    DUP AHS.ID @ _RUHA-CHECK-RECORD @ _RUHA-R.SLOT-ID @ =
    OVER AHS.UCTX @ _RUHA-CHECK-RECORD @ _RUHA-R.UCTX @ = AND
    OVER AHS.HAS-UIDL @ 0<> AND
    SWAP AHS-CALLABLE? AND ;

: _RUHA-RECORD-VISIBLE?  ( record adapter -- flag )
    2DUP _RUHA-RECORD-IDENTITY? 0= IF 2DROP 0 EXIT THEN
    DROP
    DUP _RUHA-R.STATE @ _RUHA-RECORD-ATTACHED =
    OVER _RUHA-R.VISIBLE @ 0<> AND
    OVER _RUHA-R.SLOT @ AHS-VISIBLE? AND
    NIP ;

VARIABLE _RUHA-IT-ADAPTER

: _RUHA-INVALIDATE ( adapter -- )
    _RUHA-IT-ADAPTER !
    \ Keep the selector as a private reuse source.  LAST-STATUS is the public
    \ borrow gate, so no caller can reacquire it after this lifecycle edge.
    RUHA-S-STALE _RUHA-IT-ADAPTER @ _RUHA-A.LAST-STATUS ! ;

: _RUHA-RECORD-DIRTY!  ( record -- )
    DUP _RUHA-R.FLAGS @
    _RUHA-RF-STAGED _RUHA-RF-STAGED-EMPTY OR INVERT AND
    _RUHA-RF-DIRTY OR SWAP _RUHA-R.FLAGS ! ;

: _RUHA-RECORD-DIRTY?  ( record -- flag )
    _RUHA-R.FLAGS @ _RUHA-RF-DIRTY AND 0<> ;

: _RUHA-RECORD-EMPTY?  ( record -- flag )
    _RUHA-R.FLAGS @ _RUHA-RF-EMPTY AND 0<> ;

\ Layers a document's roots may lie beneath.  A renderer shows a prompt's
\ field only with fields, and a dialog only with dialogs; an overlay pane
\ needs a candidate that puts it in a region of its own.  The producer says
\ which it can show.
1 CONSTANT RUHA-LAYER-FIELDS
2 CONSTANT RUHA-LAYER-DIALOGS
\ The overlay panes above a document: overlay slots, such as Desk's screens,
\ which the producer can put in a layer above the panes beneath them.
4 CONSTANT RUHA-LAYER-PANES
7 CONSTANT _RUHA-LAYER-MASK

\ RUHA-LAYERS! ( flags adapter -- status )
\   Let a document keep its roots beneath its own overlay, or beneath the
\   overlay panes above it, only where FLAGS says the renderer can show
\   that layer above them; anywhere else foreground paint over a document
\   falls the document back whole.  A
\   change closes the borrow gate, so no snapshot captured under the other
\   setting is handed out again.  The adapter is proved valid when the
\   setting changes; the producer passes its own on every build.
: RUHA-LAYERS!  ( flags adapter -- status )
    OVER _RUHA-LAYER-MASK INVERT AND IF 2DROP RUHA-S-INVALID EXIT THEN
    DUP 0= IF 2DROP RUHA-S-INVALID EXIT THEN
    2DUP _RUHA-A.LAYERS @ = IF 2DROP RUHA-S-OK EXIT THEN
    DUP RUHA-VALID? 0= IF 2DROP RUHA-S-INVALID EXIT THEN
    TUCK _RUHA-A.LAYERS ! _RUHA-INVALIDATE RUHA-S-OK ;

\ A record's document is the current UCTX, and RUHA's banks lie apart from
\ its storage.  The banks were proved apart from it when the document
\ attached; the document's storage that came later comes from allocators,
\ whose live blocks never overlap the banks Desk lent, so the proof is made
\ again only with every-frame checks on (check-mode.f).
: _RUHA-RECORD-STORAGE-CURRENT?  ( record adapter -- flag )
    OVER _RUHA-R.UCTX @ ASHELL-ACTIVE-CTX <> IF 2DROP 0 EXIT THEN
    NIP CHK-EVERY-FRAME? IF
        _RUHA-STORAGE-DISJOINT-CURRENT? _RUHA-BANKS-DAMAGED CHK-NAME
    ELSE DROP -1 THEN ;

\ =====================================================================
\  UCTX projection callbacks
\ =====================================================================

VARIABLE _RUHA-A-SLOT
VARIABLE _RUHA-A-ADAPTER
VARIABLE _RUHA-A-FREE

: _RUHA-ATTACH  ( slot adapter -- token status )
    _RUHA-A-ADAPTER ! _RUHA-A-SLOT !
    _RUHA-A-ADAPTER @ RUHA-VALID? 0= IF 0 RUHA-S-INVALID EXIT THEN
    _RUHA-A-ADAPTER @ _RUHA-A.INSTALLED @ 0= IF
        0 RUHA-S-INVALID EXIT
    THEN
    _RUHA-A-ADAPTER @ _RUHA-A.HOST @ DUP 0= IF
        DROP 0 RUHA-S-INVALID EXIT
    THEN
    _RUHA-A-SLOT @ SWAP _RUHA-HOST-HAS-SLOT? 0= IF
        0 RUHA-S-STALE EXIT
    THEN
    _RUHA-A-SLOT @ AHS.HAS-UIDL @ 0=
    _RUHA-A-SLOT @ AHS.UCTX @ 0= OR
    _RUHA-A-SLOT @ AHS.RGN @ 0= OR IF 0 RUHA-S-INVALID EXIT THEN
    _RUHA-A-SLOT @ AHS.UCTX @ ASHELL-ACTIVE-CTX <> IF
        0 RUHA-S-STALE EXIT
    THEN
    _RUHA-A-ADAPTER @ _RUHA-STORAGE-DISJOINT-CURRENT?
        _RUHA-BANKS-DAMAGED CHK-HANDOVER 0= IF 0 RUHA-S-INVALID EXIT THEN
    _RUHA-A-SLOT @ _RUHA-OWNER-NAMED? 0= IF 0 RUHA-S-INVALID EXIT THEN
    _RUHA-A-SLOT @ _RUHA-A-ADAPTER @ _RUHA-LIVE-OWNER?
        _RUHA-BANKS-DAMAGED CHK-HANDOVER 0= IF 0 RUHA-S-INVALID EXIT THEN
    0 _RUHA-A-FREE !
    _RUHA-A-ADAPTER @ _RUHA-A.CAPACITY @ 0 ?DO
        I _RUHA-A-ADAPTER @ _RUHA-RECORD-AT DUP _RUHA-R.STATE @
        _RUHA-RECORD-FREE = IF
            _RUHA-A-FREE @ 0= IF DUP _RUHA-A-FREE ! THEN
        ELSE
            DUP _RUHA-R.SLOT @ _RUHA-A-SLOT @ = IF
                DROP 0 RUHA-S-STALE UNLOOP EXIT
            THEN
        THEN
        DROP
    LOOP
    _RUHA-A-FREE @ 0= IF 0 RUHA-S-UNAVAILABLE EXIT THEN
    _RUHA-A-ADAPTER @ _RUHA-A.NEXT-TOKEN @ DUP 0= IF
        DROP 0 RUHA-S-UNAVAILABLE EXIT
    THEN
    DUP 1+ _RUHA-A-ADAPTER @ _RUHA-A.NEXT-TOKEN !
    _RUHA-A-FREE @ RUHA-RECORD-SIZE 0 FILL
    DUP _RUHA-A-FREE @ _RUHA-R.TOKEN !
    _RUHA-A-SLOT @ _RUHA-A-FREE @ _RUHA-R.SLOT !
    _RUHA-A-SLOT @ AHS.ID @ _RUHA-A-FREE @ _RUHA-R.SLOT-ID !
    _RUHA-A-SLOT @ AHS.UCTX @ _RUHA-A-FREE @ _RUHA-R.UCTX !
    _RUHA-RECORD-ATTACHED _RUHA-A-FREE @ _RUHA-R.STATE !
    _RUHA-A-FREE @ _RUHA-RECORD-DIRTY!
    _RUHA-A-ADAPTER @ _RUHA-INVALIDATE
    RUHA-S-OK ;

VARIABLE _RUHA-RL-VISIBLE
VARIABLE _RUHA-RL-REGION
VARIABLE _RUHA-RL-TOKEN
VARIABLE _RUHA-RL-ADAPTER
VARIABLE _RUHA-RL-RECORD
VARIABLE _RUHA-RL-ROW
VARIABLE _RUHA-RL-COL
VARIABLE _RUHA-RL-HEIGHT
VARIABLE _RUHA-RL-WIDTH

: _RUHA-RELAYOUT  ( visible region token adapter -- status )
    _RUHA-RL-ADAPTER ! _RUHA-RL-TOKEN !
    _RUHA-RL-REGION ! _RUHA-RL-VISIBLE !
    _RUHA-RL-TOKEN @ _RUHA-RL-ADAPTER @ _RUHA-LOOKUP
    DUP RUHA-S-OK <> IF NIP EXIT THEN DROP _RUHA-RL-RECORD !
    _RUHA-RL-RECORD @ _RUHA-R.STATE @
        _RUHA-RECORD-ATTACHED <> IF RUHA-S-STALE EXIT THEN
    _RUHA-RL-RECORD @ _RUHA-RL-ADAPTER @
        _RUHA-RECORD-IDENTITY? 0= IF RUHA-S-STALE EXIT THEN
    _RUHA-RL-RECORD @ _RUHA-RL-ADAPTER @
        _RUHA-RECORD-STORAGE-CURRENT? 0= IF RUHA-S-INVALID EXIT THEN
    _RUHA-RL-ADAPTER @ _RUHA-INVALIDATE
    _RUHA-RL-RECORD @ _RUHA-RECORD-DIRTY!
    _RUHA-RL-VISIBLE @ 0= IF
        0 _RUHA-RL-RECORD @ _RUHA-R.VISIBLE !
        0 _RUHA-RL-RECORD @ _RUHA-R.REGION !
        0 _RUHA-RL-RECORD @ _RUHA-R.ROW !
        0 _RUHA-RL-RECORD @ _RUHA-R.COL !
        0 _RUHA-RL-RECORD @ _RUHA-R.HEIGHT !
        0 _RUHA-RL-RECORD @ _RUHA-R.WIDTH !
        RUHA-S-OK EXIT
    THEN
    _RUHA-RL-REGION @ RGN-SIZE _RUHA-SPAN? 0= IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-RL-RECORD @ _RUHA-R.SLOT @ AHS.RGN @
        _RUHA-RL-REGION @ <> IF RUHA-S-STALE EXIT THEN
    _RUHA-RL-REGION @ RGN-ROW DUP 0< IF DROP RUHA-S-INVALID EXIT THEN
        _RUHA-RL-ROW !
    _RUHA-RL-REGION @ RGN-COL DUP 0< IF DROP RUHA-S-INVALID EXIT THEN
        _RUHA-RL-COL !
    _RUHA-RL-REGION @ RGN-H DUP 0> 0= IF DROP RUHA-S-INVALID EXIT THEN
        _RUHA-RL-HEIGHT !
    _RUHA-RL-REGION @ RGN-W DUP 0> 0= IF DROP RUHA-S-INVALID EXIT THEN
        _RUHA-RL-WIDTH !
    _RUHA-RL-ROW @ _RUHA-RL-RECORD @ _RUHA-R.ROW !
    _RUHA-RL-COL @ _RUHA-RL-RECORD @ _RUHA-R.COL !
    _RUHA-RL-HEIGHT @ _RUHA-RL-RECORD @ _RUHA-R.HEIGHT !
    _RUHA-RL-WIDTH @ _RUHA-RL-RECORD @ _RUHA-R.WIDTH !
    _RUHA-RL-REGION @ _RUHA-RL-RECORD @ _RUHA-R.REGION !
    -1 _RUHA-RL-RECORD @ _RUHA-R.VISIBLE !
    RUHA-S-OK ;

VARIABLE _RUHA-P-TOKEN
VARIABLE _RUHA-P-ADAPTER
VARIABLE _RUHA-P-RECORD
: _RUHA-NEXT-GENERATION  ( adapter -- generation|0 )
    DUP _RUHA-A.GENERATION @ 1+ DUP 0= IF 2DROP 0 EXIT THEN
    NIP ;

: _RUHA-PROJECT  ( token adapter -- status )
    _RUHA-P-ADAPTER ! _RUHA-P-TOKEN !
    _RUHA-P-TOKEN @ _RUHA-P-ADAPTER @ _RUHA-LOOKUP
    DUP RUHA-S-OK <> IF NIP EXIT THEN DROP _RUHA-P-RECORD !
    _RUHA-P-RECORD @ _RUHA-P-ADAPTER @
        _RUHA-RECORD-IDENTITY? 0= IF RUHA-S-STALE EXIT THEN
    _RUHA-P-RECORD @ _RUHA-P-ADAPTER @
        _RUHA-RECORD-STORAGE-CURRENT? 0= IF RUHA-S-INVALID EXIT THEN
    _RUHA-P-ADAPTER @ _RUHA-INVALIDATE
    _RUHA-P-RECORD @ _RUHA-RECORD-DIRTY!
    UTUI-OVERLAY-ROOT@ DROP
    _RUHA-P-RECORD @ _RUHA-R.OV-WIDTH !
    _RUHA-P-RECORD @ _RUHA-R.OV-HEIGHT !
    _RUHA-P-RECORD @ _RUHA-R.OV-COL !
    _RUHA-P-RECORD @ _RUHA-R.OV-ROW !
    _RUHA-P-RECORD @ _RUHA-R.FLAGS @
        _RUHA-RF-OV-FIELD _RUHA-RF-OV-DIALOG OR INVERT AND
    UTUI-OVERLAY-KIND@ DUP UTUI-OVERLAY-FIELD = IF
        DROP _RUHA-RF-OV-FIELD OR
    ELSE
        UTUI-OVERLAY-DIALOG = IF _RUHA-RF-OV-DIALOG OR THEN
    THEN
    _RUHA-P-RECORD @ _RUHA-R.FLAGS !
    RUHA-S-OK ;

VARIABLE _RUHA-Q-TOKEN
VARIABLE _RUHA-Q-ADAPTER
VARIABLE _RUHA-Q-RECORD

: _RUHA-QUIESCE  ( token adapter -- status )
    _RUHA-Q-ADAPTER ! _RUHA-Q-TOKEN !
    _RUHA-Q-TOKEN @ _RUHA-Q-ADAPTER @ _RUHA-LOOKUP
    DUP RUHA-S-OK <> IF NIP EXIT THEN DROP _RUHA-Q-RECORD !
    _RUHA-Q-RECORD @ _RUHA-Q-ADAPTER @
        _RUHA-RECORD-STORAGE-CURRENT? 0= IF RUHA-S-INVALID EXIT THEN
    _RUHA-Q-RECORD @ _RUHA-R.STATE @ DUP
        _RUHA-RECORD-QUIESCED = IF DROP RUHA-S-OK EXIT THEN
    _RUHA-RECORD-ATTACHED <> IF RUHA-S-STALE EXIT THEN
    _RUHA-Q-ADAPTER @ _RUHA-INVALIDATE
    _RUHA-RECORD-QUIESCED _RUHA-Q-RECORD @ _RUHA-R.STATE !
    RUHA-S-OK ;

: _RUHA-DETACH  ( token adapter -- status )
    _RUHA-Q-ADAPTER ! _RUHA-Q-TOKEN !
    _RUHA-Q-TOKEN @ _RUHA-Q-ADAPTER @ _RUHA-LOOKUP
    DUP RUHA-S-OK <> IF NIP EXIT THEN DROP _RUHA-Q-RECORD !
    _RUHA-Q-RECORD @ _RUHA-Q-ADAPTER @
        _RUHA-RECORD-STORAGE-CURRENT? 0= IF RUHA-S-INVALID EXIT THEN
    _RUHA-Q-RECORD @ _RUHA-R.STATE @
        _RUHA-RECORD-QUIESCED <> IF RUHA-S-STALE EXIT THEN
    _RUHA-Q-ADAPTER @ _RUHA-INVALIDATE
    _RUHA-Q-RECORD @ RUHA-RECORD-SIZE 0 FILL
    RUHA-S-OK ;

\ =====================================================================
\  Composition and host lifecycle
\ =====================================================================

VARIABLE _RUHA-INSTALL-ADAPTER

\ Neutral source-family classification follows the same ordinary element
\ ancestry as the menu snapshot.  Classifying each render, rather than only
\ the deferred root, covers a dirty item beneath a clean open menu.  Other
\ families and unsupported overlays continue updating the ordinary residue.
: _RUHA-REPLACEABLE-PAINT?  ( elem -- flag )
    _UTUI-PROJ-ATTACHED @ 0= IF DROP 0 EXIT THEN
    DUP _UTUI-STATUS-LABEL-CANONICAL? IF DROP -1 EXIT THEN
    BEGIN DUP WHILE
        DUP UIDL-TYPE DUP UIDL-T-MENUBAR = SWAP UIDL-T-MENU = OR IF
            DROP -1 EXIT
        THEN
        UIDL-PARENT
    REPEAT
    DROP 0 ;

: RUHA-INSTALL  ( adapter -- status )
    DUP RUHA-VALID? 0= IF DROP RUHA-S-INVALID EXIT THEN
    DUP _RUHA-STORAGE-DISJOINT-CURRENT? _RUHA-BANKS-DAMAGED CHK-HANDOVER
        0= IF DROP RUHA-S-INVALID EXIT THEN
    DUP _RUHA-INSTALL-ADAPTER !
    ['] _RUHA-ATTACH ['] _RUHA-PROJECT ['] _RUHA-RELAYOUT
    ['] _RUHA-QUIESCE ['] _RUHA-DETACH _UTUI-PROJECTION-ADAPTER!
    0= IF 0 _RUHA-INSTALL-ADAPTER ! RUHA-S-INVALID EXIT THEN
    ['] _RUHA-REPLACEABLE-PAINT? _UTUI-PAINT-LAYER-OBSERVER! 0= IF
        0 _RUHA-INSTALL-ADAPTER ! RUHA-S-INVALID EXIT
    THEN
    -1 _RUHA-INSTALL-ADAPTER @ _RUHA-A.INSTALLED !
    0 _RUHA-INSTALL-ADAPTER ! RUHA-S-OK ;

VARIABLE _RUHA-HR-HOST
VARIABLE _RUHA-HR-SLOT
VARIABLE _RUHA-HR-ADAPTER

: RUHA-AHOST-UIDL-READY  ( host slot adapter -- ior )
    _RUHA-HR-ADAPTER ! _RUHA-HR-SLOT ! _RUHA-HR-HOST !
    _RUHA-HR-ADAPTER @ RUHA-VALID? 0= IF RUHA-S-INVALID EXIT THEN
    _RUHA-HR-ADAPTER @ _RUHA-A.HOST @
        _RUHA-HR-HOST @ <> IF RUHA-S-STALE EXIT THEN
    _RUHA-HR-SLOT @ DUP AHS-VISIBLE? _UTUI-PROJECTION-ATTACH ;

VARIABLE _RUHA-AF-ADAPTER

: _RUHA-ALL-FREE?  ( adapter -- flag )
    DUP _RUHA-AF-ADAPTER ! _RUHA-A.CAPACITY @ 0 ?DO
        I _RUHA-AF-ADAPTER @ _RUHA-RECORD-AT _RUHA-R.STATE @
            _RUHA-RECORD-FREE <> IF 0 UNLOOP EXIT THEN
    LOOP
    -1 ;

: RUHA-HOST-INIT  ( host adapter -- ior )
    DUP RUHA-VALID? 0= IF 2DROP RUHA-S-INVALID EXIT THEN
    DUP _RUHA-STORAGE-DISJOINT-CURRENT? _RUHA-BANKS-DAMAGED CHK-HANDOVER
        0= IF 2DROP RUHA-S-INVALID EXIT THEN
    DUP _RUHA-A.INSTALLED @ 0= IF 2DROP RUHA-S-INVALID EXIT THEN
    DUP _RUHA-ALL-FREE? 0= IF 2DROP RUHA-S-STALE EXIT THEN
    DUP _RUHA-A.HOST @ ?DUP IF
        2 PICK <> IF 2DROP RUHA-S-STALE EXIT THEN
    ELSE
        2DUP _RUHA-A.HOST !
    THEN
    ['] RUHA-AHOST-UIDL-READY OVER 3 PICK AHOST-UIDL-READY!
    2DROP RUHA-S-OK ;

: RUHA-HOST-FINI  ( host adapter -- ior )
    DUP RUHA-VALID? 0= IF 2DROP RUHA-S-INVALID EXIT THEN
    DUP _RUHA-STORAGE-DISJOINT-CURRENT? 0= IF
        2DROP RUHA-S-INVALID EXIT
    THEN
    DUP _RUHA-A.HOST @ 2 PICK <> IF 2DROP RUHA-S-STALE EXIT THEN
    DUP _RUHA-ALL-FREE? 0= IF 2DROP RUHA-S-STALE EXIT THEN
    OVER AHOST.UIDL-READY-XT @
        ['] RUHA-AHOST-UIDL-READY <> IF 2DROP RUHA-S-STALE EXIT THEN
    OVER AHOST.UIDL-READY-CONTEXT @
        OVER <> IF 2DROP RUHA-S-STALE EXIT THEN
    0 0 3 PICK AHOST-UIDL-READY!
    DUP _RUHA-INVALIDATE
    0 SWAP _RUHA-A.HOST ! DROP
    RUHA-S-OK ;

\ =====================================================================
\  Completed-draw aggregate capture
\ =====================================================================

: RUHA-DOCUMENT-CAPACITY@ ( adapter -- count )
    _RUHA-A.SNAP-DIRECTORY-BANK-U @ RUHA-DOCUMENT-SIZE / ;

VARIABLE _RUHA-B-ADAPTER
VARIABLE _RUHA-B-DRAW
VARIABLE _RUHA-B-BANK
VARIABLE _RUHA-B-GENERATION
VARIABLE _RUHA-B-ORIGINAL-CTX
VARIABLE _RUHA-B-RECORD
VARIABLE _RUHA-B-DIRECTORY-A
VARIABLE _RUHA-B-RECORDS-A
VARIABLE _RUHA-B-TEXT-A
VARIABLE _RUHA-B-DESCRIPTORS-A
VARIABLE _RUHA-B-NATIVE-A
VARIABLE _RUHA-B-DGRAPH-DESCRIPTORS-A
VARIABLE _RUHA-B-SFIELD-DESCRIPTORS-A
VARIABLE _RUHA-B-FIELD-DESCRIPTORS-A
VARIABLE _RUHA-B-DGRAPH-NATIVE-A
VARIABLE _RUHA-B-SFIELD-NATIVE-A
VARIABLE _RUHA-B-FIELD-NATIVE-A
VARIABLE _RUHA-B-DIRECTORY-U
VARIABLE _RUHA-B-RECORDS-U
VARIABLE _RUHA-B-TEXT-U
VARIABLE _RUHA-B-DESCRIPTORS-U
VARIABLE _RUHA-B-NATIVE-U
VARIABLE _RUHA-B-DGRAPH-DESCRIPTORS-U
VARIABLE _RUHA-B-SFIELD-DESCRIPTORS-U
VARIABLE _RUHA-B-FIELD-DESCRIPTORS-U
VARIABLE _RUHA-B-DGRAPH-NATIVE-U
VARIABLE _RUHA-B-SFIELD-NATIVE-U
VARIABLE _RUHA-B-FIELD-NATIVE-U
VARIABLE _RUHA-B-DOCUMENTS
VARIABLE _RUHA-B-CONTENT-EPOCH
VARIABLE _RUHA-B-EXACT-REUSE
VARIABLE _RUHA-B-COUNT
VARIABLE _RUHA-B-CAPTURE-RECORD-U
VARIABLE _RUHA-B-CAPTURE-TEXT-U
VARIABLE _RUHA-B-COLLECTION-COUNT
VARIABLE _RUHA-B-CAPTURE-DESCRIPTOR-U
VARIABLE _RUHA-B-CAPTURE-NATIVE-U
VARIABLE _RUHA-B-DGRAPH-COUNT
VARIABLE _RUHA-B-SFIELD-COUNT
VARIABLE _RUHA-B-FIELD-COUNT
VARIABLE _RUHA-B-CAPTURE-DGRAPH-DESCRIPTOR-U
VARIABLE _RUHA-B-CAPTURE-SFIELD-DESCRIPTOR-U
VARIABLE _RUHA-B-CAPTURE-FIELD-DESCRIPTOR-U
VARIABLE _RUHA-B-CAPTURE-DGRAPH-NATIVE-U
VARIABLE _RUHA-B-CAPTURE-SFIELD-NATIVE-U
VARIABLE _RUHA-B-CAPTURE-FIELD-NATIVE-U
VARIABLE _RUHA-B-STATUS
VARIABLE _RUHA-B-ENTRY
VARIABLE _RUHA-B-NEXT

VARIABLE _RUHA-B-PRIOR-BANK
VARIABLE _RUHA-B-PRIOR-SNAPSHOT
VARIABLE _RUHA-B-PRIOR-GENERATION
VARIABLE _RUHA-B-PRIOR-DIRECTORY-A
VARIABLE _RUHA-B-PRIOR-DIRECTORY-U
VARIABLE _RUHA-B-PRIOR-RECORDS-A
VARIABLE _RUHA-B-PRIOR-RECORDS-U
VARIABLE _RUHA-B-PRIOR-TEXT-A
VARIABLE _RUHA-B-PRIOR-TEXT-U
VARIABLE _RUHA-B-PRIOR-DESCRIPTORS-A
VARIABLE _RUHA-B-PRIOR-DESCRIPTORS-U
VARIABLE _RUHA-B-PRIOR-NATIVE-A
VARIABLE _RUHA-B-PRIOR-NATIVE-U
VARIABLE _RUHA-B-PRIOR-DGRAPH-DESCRIPTORS-A
VARIABLE _RUHA-B-PRIOR-SFIELD-DESCRIPTORS-A
VARIABLE _RUHA-B-PRIOR-FIELD-DESCRIPTORS-A
VARIABLE _RUHA-B-PRIOR-DGRAPH-DESCRIPTORS-U
VARIABLE _RUHA-B-PRIOR-SFIELD-DESCRIPTORS-U
VARIABLE _RUHA-B-PRIOR-FIELD-DESCRIPTORS-U
VARIABLE _RUHA-B-PRIOR-DGRAPH-NATIVE-A
VARIABLE _RUHA-B-PRIOR-SFIELD-NATIVE-A
VARIABLE _RUHA-B-PRIOR-FIELD-NATIVE-A
VARIABLE _RUHA-B-PRIOR-DGRAPH-NATIVE-U
VARIABLE _RUHA-B-PRIOR-SFIELD-NATIVE-U
VARIABLE _RUHA-B-PRIOR-FIELD-NATIVE-U
VARIABLE _RUHA-B-PRIOR-DOCUMENTS
VARIABLE _RUHA-B-PRIOR-CONTENT-EPOCH
VARIABLE _RUHA-B-HAS-PRIOR

VARIABLE _RUHA-B-FIND-RECORD
VARIABLE _RUHA-B-FIND-ENTRY
VARIABLE _RUHA-B-FIND-MATCHES

VARIABLE _RUHA-B-REUSE-ENTRY
VARIABLE _RUHA-B-REUSE-RECORD-U
VARIABLE _RUHA-B-REUSE-TEXT-U
VARIABLE _RUHA-B-REUSE-RECORD-O
VARIABLE _RUHA-B-REUSE-TEXT-O
VARIABLE _RUHA-B-REUSE-DESCRIPTOR-U
VARIABLE _RUHA-B-REUSE-NATIVE-U
VARIABLE _RUHA-B-REUSE-DESCRIPTOR-O
VARIABLE _RUHA-B-REUSE-NATIVE-O
VARIABLE _RUHA-B-REUSE-DGRAPH-DESCRIPTOR-U
VARIABLE _RUHA-B-REUSE-SFIELD-DESCRIPTOR-U
VARIABLE _RUHA-B-REUSE-FIELD-DESCRIPTOR-U
VARIABLE _RUHA-B-REUSE-DGRAPH-NATIVE-U
VARIABLE _RUHA-B-REUSE-SFIELD-NATIVE-U
VARIABLE _RUHA-B-REUSE-FIELD-NATIVE-U
VARIABLE _RUHA-B-REUSE-DGRAPH-DESCRIPTOR-O
VARIABLE _RUHA-B-REUSE-SFIELD-DESCRIPTOR-O
VARIABLE _RUHA-B-REUSE-FIELD-DESCRIPTOR-O
VARIABLE _RUHA-B-REUSE-DGRAPH-NATIVE-O
VARIABLE _RUHA-B-REUSE-SFIELD-NATIVE-O
VARIABLE _RUHA-B-REUSE-FIELD-NATIVE-O
VARIABLE _RUHA-B-REUSE-MENU-EPOCH
VARIABLE _RUHA-B-REUSE-MENU-TOPOLOGY-EPOCH
VARIABLE _RUHA-B-REUSE-COUNT
VARIABLE _RUHA-B-REUSE-I
VARIABLE _RUHA-B-REUSE-SOURCE
VARIABLE _RUHA-B-REUSE-RECORD-TARGET
VARIABLE _RUHA-B-REUSE-TEXT-TARGET
VARIABLE _RUHA-B-REUSE-DESCRIPTOR-TARGET
VARIABLE _RUHA-B-REUSE-NATIVE-TARGET
VARIABLE _RUHA-B-REUSE-DGRAPH-DESCRIPTOR-TARGET
VARIABLE _RUHA-B-REUSE-SFIELD-DESCRIPTOR-TARGET
VARIABLE _RUHA-B-REUSE-FIELD-DESCRIPTOR-TARGET
VARIABLE _RUHA-B-REUSE-DGRAPH-NATIVE-TARGET
VARIABLE _RUHA-B-REUSE-SFIELD-NATIVE-TARGET
VARIABLE _RUHA-B-REUSE-FIELD-NATIVE-TARGET

VARIABLE _RUHA-B-APPEND-RECORD-U
VARIABLE _RUHA-B-APPEND-TEXT-U
VARIABLE _RUHA-B-APPEND-DESCRIPTOR-U
VARIABLE _RUHA-B-APPEND-NATIVE-U
VARIABLE _RUHA-B-APPEND-DGRAPH-DESCRIPTOR-U
VARIABLE _RUHA-B-APPEND-SFIELD-DESCRIPTOR-U
VARIABLE _RUHA-B-APPEND-FIELD-DESCRIPTOR-U
VARIABLE _RUHA-B-APPEND-DGRAPH-NATIVE-U
VARIABLE _RUHA-B-APPEND-SFIELD-NATIVE-U
VARIABLE _RUHA-B-APPEND-FIELD-NATIVE-U
VARIABLE _RUHA-B-APPEND-OWNER-ID
VARIABLE _RUHA-B-APPEND-OWNER-GEN
VARIABLE _RUHA-B-APPEND-MENU-EPOCH
VARIABLE _RUHA-B-APPEND-MENU-TOPOLOGY-EPOCH
VARIABLE _RUHA-B-APPEND-DESCRIPTOR-NEXT
VARIABLE _RUHA-B-APPEND-NATIVE-NEXT
VARIABLE _RUHA-B-APPEND-DGRAPH-DESCRIPTOR-NEXT
VARIABLE _RUHA-B-APPEND-SFIELD-DESCRIPTOR-NEXT
VARIABLE _RUHA-B-APPEND-FIELD-DESCRIPTOR-NEXT
VARIABLE _RUHA-B-APPEND-DGRAPH-NATIVE-NEXT
VARIABLE _RUHA-B-APPEND-SFIELD-NATIVE-NEXT
VARIABLE _RUHA-B-APPEND-FIELD-NATIVE-NEXT
VARIABLE _RUHA-B-DIALOG-DESCRIPTORS-A
VARIABLE _RUHA-B-DIALOG-NATIVE-A
VARIABLE _RUHA-B-DIALOG-DESCRIPTORS-U
VARIABLE _RUHA-B-DIALOG-NATIVE-U
VARIABLE _RUHA-B-DIALOG-COUNT
VARIABLE _RUHA-B-CAPTURE-DIALOG-DESCRIPTOR-U
VARIABLE _RUHA-B-CAPTURE-DIALOG-NATIVE-U
VARIABLE _RUHA-B-PRIOR-DIALOG-DESCRIPTORS-A
VARIABLE _RUHA-B-PRIOR-DIALOG-DESCRIPTORS-U
VARIABLE _RUHA-B-PRIOR-DIALOG-NATIVE-A
VARIABLE _RUHA-B-PRIOR-DIALOG-NATIVE-U
VARIABLE _RUHA-B-REUSE-DIALOG-DESCRIPTOR-U
VARIABLE _RUHA-B-REUSE-DIALOG-NATIVE-U
VARIABLE _RUHA-B-REUSE-DIALOG-DESCRIPTOR-O
VARIABLE _RUHA-B-REUSE-DIALOG-NATIVE-O
VARIABLE _RUHA-B-REUSE-DIALOG-DESCRIPTOR-TARGET
VARIABLE _RUHA-B-REUSE-DIALOG-NATIVE-TARGET
VARIABLE _RUHA-B-APPEND-DIALOG-DESCRIPTOR-U
VARIABLE _RUHA-B-APPEND-DIALOG-NATIVE-U
VARIABLE _RUHA-B-APPEND-DIALOG-DESCRIPTOR-NEXT
VARIABLE _RUHA-B-APPEND-DIALOG-NATIVE-NEXT
VARIABLE _RUHA-B-STAGE-EMPTY
VARIABLE _RUHA-B-STAGE-RECORD
VARIABLE _RUHA-B-MENU-PRIOR-RECORD
VARIABLE _RUHA-B-MENU-CURRENT-RECORD
VARIABLE _RUHA-B-MENU-EXACT
VARIABLE _RUHA-B-MENU-TOPOLOGY
VARIABLE _RUHA-B-CAPTURE-MENU-EPOCH
VARIABLE _RUHA-B-CAPTURE-MENU-TOPOLOGY-EPOCH


\ UMSN records are a public fixed ABI, but their public API intentionally
\ exposes no mutators.  Aggregate reuse changes only the caller-issued
\ generation cell while retaining every document-local text offset.
: _RUHA-UMSN.MAGIC       ( record -- a )       ;
: _RUHA-UMSN.ABI         ( record -- a )   8 + ;
: _RUHA-UMSN.BYTES       ( record -- a )  16 + ;
: _RUHA-UMSN.GENERATION  ( record -- a )  24 + ;

: _RUHA-B-PRIOR-CLEAR  ( -- )
    0 _RUHA-B-PRIOR-BANK ! 0 _RUHA-B-PRIOR-SNAPSHOT !
    0 _RUHA-B-PRIOR-GENERATION !
    0 _RUHA-B-PRIOR-DIRECTORY-A ! 0 _RUHA-B-PRIOR-DIRECTORY-U !
    0 _RUHA-B-PRIOR-RECORDS-A ! 0 _RUHA-B-PRIOR-RECORDS-U !
    0 _RUHA-B-PRIOR-TEXT-A ! 0 _RUHA-B-PRIOR-TEXT-U !
    0 _RUHA-B-PRIOR-DESCRIPTORS-A ! 0 _RUHA-B-PRIOR-DESCRIPTORS-U !
    0 _RUHA-B-PRIOR-NATIVE-A ! 0 _RUHA-B-PRIOR-NATIVE-U !
    0 _RUHA-B-PRIOR-DGRAPH-DESCRIPTORS-A !
    0 _RUHA-B-PRIOR-DGRAPH-DESCRIPTORS-U !
    0 _RUHA-B-PRIOR-DGRAPH-NATIVE-A !
    0 _RUHA-B-PRIOR-DGRAPH-NATIVE-U !
    0 _RUHA-B-PRIOR-SFIELD-DESCRIPTORS-A !
    0 _RUHA-B-PRIOR-SFIELD-DESCRIPTORS-U !
    0 _RUHA-B-PRIOR-SFIELD-NATIVE-A !
    0 _RUHA-B-PRIOR-SFIELD-NATIVE-U !

    0 _RUHA-B-PRIOR-FIELD-DESCRIPTORS-A !
    0 _RUHA-B-PRIOR-FIELD-DESCRIPTORS-U !
    0 _RUHA-B-PRIOR-FIELD-NATIVE-A !
    0 _RUHA-B-PRIOR-FIELD-NATIVE-U !
    0 _RUHA-B-PRIOR-DIALOG-DESCRIPTORS-A !
    0 _RUHA-B-PRIOR-DIALOG-DESCRIPTORS-U !
    0 _RUHA-B-PRIOR-DIALOG-NATIVE-A !
    0 _RUHA-B-PRIOR-DIALOG-NATIVE-U !
    0 _RUHA-B-PRIOR-DOCUMENTS !
    0 _RUHA-B-PRIOR-CONTENT-EPOCH ! 0 _RUHA-B-HAS-PRIOR ! ;

: _RUHA-B-LOAD-PRIOR  ( -- )
    \ Internal reuse deliberately ignores LAST-STATUS after validating the
    \ exact active bank, generation, fixed bases, and caller-owned bounds.
    _RUHA-B-PRIOR-CLEAR
    _RUHA-B-ADAPTER @ _RUHA-A.ACTIVE-BANK @ DUP 0< IF DROP EXIT THEN
    DUP 1 U> IF DROP EXIT THEN DUP _RUHA-B-PRIOR-BANK !
    _RUHA-B-ADAPTER @ _RUHA-SNAPSHOT-AT DUP _RUHA-B-PRIOR-SNAPSHOT !
    DUP RUHA-SNAPSHOT-GENERATION@ DUP 0= IF 2DROP EXIT THEN
    DUP _RUHA-B-ADAPTER @ _RUHA-A.GENERATION @ <> IF 2DROP EXIT THEN
    _RUHA-B-PRIOR-GENERATION ! DROP
    _RUHA-B-PRIOR-SNAPSHOT @ RUHA-SNAPSHOT-CONTENT-EPOCH@
        DUP 0= IF DROP EXIT THEN _RUHA-B-PRIOR-CONTENT-EPOCH !

    _RUHA-B-PRIOR-SNAPSHOT @ RUHA-SNAPSHOT-DIRECTORY@
        _RUHA-B-PRIOR-DIRECTORY-U ! _RUHA-B-PRIOR-DIRECTORY-A !
    _RUHA-B-PRIOR-DIRECTORY-A @
    _RUHA-B-PRIOR-BANK @ _RUHA-B-ADAPTER @ _RUHA-SNAPSHOT-DIRECTORY-A
        <> IF EXIT THEN
    _RUHA-B-PRIOR-DIRECTORY-U @
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-DIRECTORY-BANK-U @ U> IF EXIT THEN
    _RUHA-B-PRIOR-SNAPSHOT @ RUHA-SNAPSHOT-DOCUMENT-COUNT@
        DUP _RUHA-B-PRIOR-DOCUMENTS !
    DUP 0> 0= IF DROP EXIT THEN
    DUP _RUHA-B-ADAPTER @ _RUHA-A.CAPACITY @ U> IF DROP EXIT THEN
    RUHA-DOCUMENT-SIZE * _RUHA-B-PRIOR-DIRECTORY-U @ <> IF EXIT THEN

    _RUHA-B-PRIOR-SNAPSHOT @ RUHA-SNAPSHOT-RECORDS@
        _RUHA-B-PRIOR-RECORDS-U ! _RUHA-B-PRIOR-RECORDS-A !
    _RUHA-B-PRIOR-RECORDS-A @
    _RUHA-B-PRIOR-BANK @ _RUHA-B-ADAPTER @ _RUHA-SNAPSHOT-RECORD-A
        <> IF EXIT THEN
    _RUHA-B-PRIOR-RECORDS-U @ DUP
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-RECORD-BANK-U @ U> IF DROP EXIT THEN
    UMSN-RECORD-SIZE MOD IF EXIT THEN

    _RUHA-B-PRIOR-SNAPSHOT @ RUHA-SNAPSHOT-TEXT@
        _RUHA-B-PRIOR-TEXT-U ! _RUHA-B-PRIOR-TEXT-A !
    _RUHA-B-PRIOR-TEXT-A @
    _RUHA-B-PRIOR-BANK @ _RUHA-B-ADAPTER @ _RUHA-SNAPSHOT-TEXT-A
        <> IF EXIT THEN
    _RUHA-B-PRIOR-TEXT-U @
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-TEXT-BANK-U @ U> IF EXIT THEN

    _RUHA-B-PRIOR-SNAPSHOT @ RUHA-SNAPSHOT-COLLECTION-DESCRIPTORS@
        _RUHA-B-PRIOR-DESCRIPTORS-U ! _RUHA-B-PRIOR-DESCRIPTORS-A !
    _RUHA-B-PRIOR-DESCRIPTORS-A @
    _RUHA-B-PRIOR-BANK @ _RUHA-B-ADAPTER @
        _RUHA-SNAPSHOT-DESCRIPTOR-A <> IF EXIT THEN
    _RUHA-B-PRIOR-DESCRIPTORS-U @ DUP
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-DESCRIPTOR-BANK-U @ U> IF
            DROP EXIT
        THEN
    UCSN-DESCRIPTOR-SIZE MOD IF EXIT THEN

    _RUHA-B-PRIOR-SNAPSHOT @ RUHA-SNAPSHOT-COLLECTION-NATIVE@
        _RUHA-B-PRIOR-NATIVE-U ! _RUHA-B-PRIOR-NATIVE-A !
    _RUHA-B-PRIOR-NATIVE-A @
    _RUHA-B-PRIOR-BANK @ _RUHA-B-ADAPTER @
        _RUHA-SNAPSHOT-NATIVE-A <> IF EXIT THEN
    _RUHA-B-PRIOR-NATIVE-U @ DUP
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-NATIVE-BANK-U @ U> IF
            DROP EXIT
        THEN
    7 AND IF EXIT THEN

    _RUHA-B-PRIOR-SNAPSHOT @
        RUHA-SNAPSHOT-DATA-GRAPHICS-DESCRIPTORS@
        _RUHA-B-PRIOR-DGRAPH-DESCRIPTORS-U !
        _RUHA-B-PRIOR-DGRAPH-DESCRIPTORS-A !
    _RUHA-B-PRIOR-DGRAPH-DESCRIPTORS-A @
    _RUHA-B-PRIOR-BANK @ _RUHA-B-ADAPTER @
        _RUHA-SNAPSHOT-DGRAPH-DESCRIPTOR-A <> IF EXIT THEN
    _RUHA-B-PRIOR-DGRAPH-DESCRIPTORS-U @ DUP
        _RUHA-B-ADAPTER @
            _RUHA-A.SNAP-DGRAPH-DESCRIPTOR-BANK-U @ U> IF
            DROP EXIT
        THEN
    UDGSN-DESCRIPTOR-SIZE MOD IF EXIT THEN

    _RUHA-B-PRIOR-SNAPSHOT @ RUHA-SNAPSHOT-DATA-GRAPHICS-NATIVE@
        _RUHA-B-PRIOR-DGRAPH-NATIVE-U !
        _RUHA-B-PRIOR-DGRAPH-NATIVE-A !
    _RUHA-B-PRIOR-DGRAPH-NATIVE-A @
    _RUHA-B-PRIOR-BANK @ _RUHA-B-ADAPTER @
        _RUHA-SNAPSHOT-DGRAPH-NATIVE-A <> IF EXIT THEN
    _RUHA-B-PRIOR-DGRAPH-NATIVE-U @ DUP
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-DGRAPH-NATIVE-BANK-U @ U> IF
            DROP EXIT
        THEN
    7 AND IF EXIT THEN
    _RUHA-B-PRIOR-SNAPSHOT @
        RUHA-SNAPSHOT-STATUS-FIELDS-DESCRIPTORS@
        _RUHA-B-PRIOR-SFIELD-DESCRIPTORS-U !
        _RUHA-B-PRIOR-SFIELD-DESCRIPTORS-A !
    _RUHA-B-PRIOR-SFIELD-DESCRIPTORS-A @
    _RUHA-B-PRIOR-BANK @ _RUHA-B-ADAPTER @
        _RUHA-SNAPSHOT-SFIELD-DESCRIPTOR-A <> IF EXIT THEN
    _RUHA-B-PRIOR-SFIELD-DESCRIPTORS-U @ DUP
        _RUHA-B-ADAPTER @
            _RUHA-A.SNAP-SFIELD-DESCRIPTOR-BANK-U @ U> IF
            DROP EXIT
        THEN
    USFSN-DESCRIPTOR-SIZE MOD IF EXIT THEN

    _RUHA-B-PRIOR-SNAPSHOT @ RUHA-SNAPSHOT-STATUS-FIELDS-NATIVE@
        _RUHA-B-PRIOR-SFIELD-NATIVE-U !
        _RUHA-B-PRIOR-SFIELD-NATIVE-A !
    _RUHA-B-PRIOR-SFIELD-NATIVE-A @
    _RUHA-B-PRIOR-BANK @ _RUHA-B-ADAPTER @
        _RUHA-SNAPSHOT-SFIELD-NATIVE-A <> IF EXIT THEN
    _RUHA-B-PRIOR-SFIELD-NATIVE-U @ DUP
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-SFIELD-NATIVE-BANK-U @ U> IF
            DROP EXIT
        THEN
    7 AND IF EXIT THEN

    _RUHA-B-PRIOR-SNAPSHOT @
        RUHA-SNAPSHOT-FIELDS-DESCRIPTORS@
        _RUHA-B-PRIOR-FIELD-DESCRIPTORS-U !
        _RUHA-B-PRIOR-FIELD-DESCRIPTORS-A !
    _RUHA-B-PRIOR-FIELD-DESCRIPTORS-A @
    _RUHA-B-PRIOR-BANK @ _RUHA-B-ADAPTER @
        _RUHA-SNAPSHOT-FIELD-DESCRIPTOR-A <> IF EXIT THEN
    _RUHA-B-PRIOR-FIELD-DESCRIPTORS-U @ DUP
        _RUHA-B-ADAPTER @
            _RUHA-A.SNAP-FIELD-DESCRIPTOR-BANK-U @ U> IF
            DROP EXIT
        THEN
    UFLSN-DESCRIPTOR-SIZE MOD IF EXIT THEN

    _RUHA-B-PRIOR-SNAPSHOT @ RUHA-SNAPSHOT-FIELDS-NATIVE@
        _RUHA-B-PRIOR-FIELD-NATIVE-U !
        _RUHA-B-PRIOR-FIELD-NATIVE-A !
    _RUHA-B-PRIOR-FIELD-NATIVE-A @
    _RUHA-B-PRIOR-BANK @ _RUHA-B-ADAPTER @
        _RUHA-SNAPSHOT-FIELD-NATIVE-A <> IF EXIT THEN
    _RUHA-B-PRIOR-FIELD-NATIVE-U @ DUP
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-FIELD-NATIVE-BANK-U @ U> IF
            DROP EXIT
        THEN
    7 AND IF EXIT THEN

    _RUHA-B-PRIOR-SNAPSHOT @
        RUHA-SNAPSHOT-DIALOGS-DESCRIPTORS@
        _RUHA-B-PRIOR-DIALOG-DESCRIPTORS-U !
        _RUHA-B-PRIOR-DIALOG-DESCRIPTORS-A !
    _RUHA-B-PRIOR-DIALOG-DESCRIPTORS-A @
    _RUHA-B-PRIOR-BANK @ _RUHA-B-ADAPTER @
        _RUHA-SNAPSHOT-DIALOG-DESCRIPTOR-A <> IF EXIT THEN
    _RUHA-B-PRIOR-DIALOG-DESCRIPTORS-U @ DUP
        _RUHA-B-ADAPTER @
            _RUHA-A.SNAP-DIALOG-DESCRIPTOR-BANK-U @ U> IF
            DROP EXIT
        THEN
    UDLSN-DESCRIPTOR-SIZE MOD IF EXIT THEN

    _RUHA-B-PRIOR-SNAPSHOT @ RUHA-SNAPSHOT-DIALOGS-NATIVE@
        _RUHA-B-PRIOR-DIALOG-NATIVE-U !
        _RUHA-B-PRIOR-DIALOG-NATIVE-A !
    _RUHA-B-PRIOR-DIALOG-NATIVE-A @
    _RUHA-B-PRIOR-BANK @ _RUHA-B-ADAPTER @
        _RUHA-SNAPSHOT-DIALOG-NATIVE-A <> IF EXIT THEN
    _RUHA-B-PRIOR-DIALOG-NATIVE-U @ DUP
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-DIALOG-NATIVE-BANK-U @ U> IF
            DROP EXIT
        THEN
    7 AND IF EXIT THEN
    -1 _RUHA-B-HAS-PRIOR ! ;

: _RUHA-B-FIND-PRIOR  ( record -- entry found? )
    _RUHA-B-FIND-RECORD ! 0 _RUHA-B-FIND-ENTRY !
    0 _RUHA-B-FIND-MATCHES !
    _RUHA-B-HAS-PRIOR @ 0= IF 0 0 EXIT THEN
    _RUHA-B-PRIOR-DOCUMENTS @ 0 ?DO
        _RUHA-B-PRIOR-DIRECTORY-A @ I RUHA-DOCUMENT-SIZE * +
        DUP RUHA-DOCUMENT-TOKEN@
            _RUHA-B-FIND-RECORD @ _RUHA-R.TOKEN @ =
        OVER RUHA-DOCUMENT-SLOT-ID@
            _RUHA-B-FIND-RECORD @ _RUHA-R.SLOT-ID @ = AND
        OVER RUHA-DOCUMENT-OWNER-ID@
            _RUHA-B-FIND-RECORD @ _RUHA-R.SLOT @ AHS.INST @ CINST.ID @ = AND
        OVER RUHA-DOCUMENT-OWNER-GENERATION@
            _RUHA-B-FIND-RECORD @ _RUHA-R.SLOT @ AHS.INST @
                CINST.GENERATION @ = AND IF
            DUP _RUHA-B-FIND-ENTRY ! 1 _RUHA-B-FIND-MATCHES +!
        THEN
        DROP
    LOOP
    _RUHA-B-FIND-MATCHES @ 1 = IF
        _RUHA-B-FIND-ENTRY @ -1
    ELSE
        0 0
    THEN ;

: _RUHA-B-LOCAL-TEXT?  ( offset length -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    OVER 0< IF 2DROP 0 EXIT THEN
    _RUHA-UADD? 0= IF DROP 0 EXIT THEN
    _RUHA-B-REUSE-TEXT-U @ U> 0= ;

: _RUHA-B-PRIOR-RECORD?  ( record -- flag )
    _RUHA-B-REUSE-SOURCE !
    _RUHA-B-REUSE-SOURCE @ _RUHA-UMSN.MAGIC @ _UMSN-RECORD-MAGIC =
    _RUHA-B-REUSE-SOURCE @ _RUHA-UMSN.ABI @ _UMSN-RECORD-ABI = AND
    _RUHA-B-REUSE-SOURCE @ _RUHA-UMSN.BYTES @
        UMSN-RECORD-SIZE = AND
    _RUHA-B-REUSE-SOURCE @ UMSN-RECORD-GENERATION@
        _RUHA-B-PRIOR-GENERATION @ = AND
    _RUHA-B-REUSE-SOURCE @ UMSN-RECORD-LABEL-OFFSET@
    _RUHA-B-REUSE-SOURCE @ UMSN-RECORD-LABEL-BYTES@
        _RUHA-B-LOCAL-TEXT? AND
    _RUHA-B-REUSE-SOURCE @ UMSN-RECORD-SHORTCUT-OFFSET@
    _RUHA-B-REUSE-SOURCE @ UMSN-RECORD-SHORTCUT-BYTES@
        _RUHA-B-LOCAL-TEXT? AND ;

: _RUHA-B-PRIOR-MENU?  ( -- flag )
    _RUHA-B-REUSE-ENTRY @ RUHA-DOCUMENT-RECORD-OFFSET@
        _RUHA-B-REUSE-RECORD-O !
    _RUHA-B-REUSE-ENTRY @ RUHA-DOCUMENT-RECORD-BYTES@
        _RUHA-B-REUSE-RECORD-U !
    _RUHA-B-REUSE-RECORD-U @ 0< IF 0 EXIT THEN
    _RUHA-B-REUSE-RECORD-U @ UMSN-RECORD-SIZE MOD IF 0 EXIT THEN
    _RUHA-B-REUSE-RECORD-O @ DUP 0< IF DROP 0 EXIT THEN
    DUP UMSN-RECORD-SIZE MOD IF DROP 0 EXIT THEN DROP
    _RUHA-B-REUSE-RECORD-O @ _RUHA-B-REUSE-RECORD-U @
        _RUHA-UADD? 0= IF DROP 0 EXIT THEN
    _RUHA-B-PRIOR-RECORDS-U @ U> IF 0 EXIT THEN
    _RUHA-B-REUSE-RECORD-U @ UMSN-RECORD-SIZE /
        _RUHA-B-REUSE-COUNT !

    _RUHA-B-REUSE-ENTRY @ RUHA-DOCUMENT-TEXT-OFFSET@
        _RUHA-B-REUSE-TEXT-O !
    _RUHA-B-REUSE-ENTRY @ RUHA-DOCUMENT-TEXT-BYTES@
        _RUHA-B-REUSE-TEXT-U !
    _RUHA-B-REUSE-TEXT-U @ 0< IF 0 EXIT THEN
    _RUHA-B-REUSE-TEXT-O @ 0< IF 0 EXIT THEN
    _RUHA-B-REUSE-TEXT-O @ _RUHA-B-REUSE-TEXT-U @
        _RUHA-UADD? 0= IF DROP 0 EXIT THEN
    _RUHA-B-PRIOR-TEXT-U @ U> IF 0 EXIT THEN
    _RUHA-B-REUSE-RECORD-U @ 0=
        _RUHA-B-REUSE-TEXT-U @ 0<> AND IF 0 EXIT THEN

    _RUHA-B-REUSE-ENTRY @ RUHA-DOCUMENT-MENU-EPOCH@
        _RUHA-B-REUSE-MENU-EPOCH !
    _RUHA-B-REUSE-ENTRY @ RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@
        _RUHA-B-REUSE-MENU-TOPOLOGY-EPOCH !
    _RUHA-B-REUSE-RECORD-U @ 0=
        _RUHA-B-REUSE-MENU-EPOCH @ 0= <> IF 0 EXIT THEN
    _RUHA-B-REUSE-RECORD-U @ 0=
        _RUHA-B-REUSE-MENU-TOPOLOGY-EPOCH @ 0= <> IF 0 EXIT THEN
    _RUHA-B-REUSE-MENU-EPOCH @
        _RUHA-B-PRIOR-GENERATION @ U> IF 0 EXIT THEN
    _RUHA-B-REUSE-MENU-TOPOLOGY-EPOCH @
        _RUHA-B-PRIOR-GENERATION @ U> IF 0 EXIT THEN
    _RUHA-B-REUSE-MENU-TOPOLOGY-EPOCH @
        _RUHA-B-REUSE-MENU-EPOCH @ U> IF 0 EXIT THEN

    CHK-EVERY-FRAME? IF
        0 _RUHA-B-REUSE-I !
        BEGIN _RUHA-B-REUSE-I @ _RUHA-B-REUSE-COUNT @ < WHILE
            _RUHA-B-PRIOR-RECORDS-A @ _RUHA-B-REUSE-RECORD-O @ +
            _RUHA-B-REUSE-I @ UMSN-RECORD-SIZE * +
            _RUHA-B-PRIOR-RECORD? _RUHA-SLICES-DAMAGED CHK-NAME
                0= IF 0 EXIT THEN
            1 _RUHA-B-REUSE-I +!
        REPEAT
    THEN
    -1 ;

\ Whether a document's stored slices can be copied into this draw.  Their
\ offsets and lengths are checked against the prior bank on every reuse,
\ since the copy relies on them.  The slices themselves were validated when
\ they were captured, and only RUHA writes its banks, so the snapshot
\ modules' full validation of each slice, and of each stored menu record,
\ runs only with every-frame checks on.
: _RUHA-B-PRIOR-ENTRY?  ( entry -- flag )
    _RUHA-B-REUSE-ENTRY !
    _RUHA-B-REUSE-ENTRY @
        RUHA-DOCUMENT-COLLECTION-DESCRIPTOR-OFFSET@
        _RUHA-B-REUSE-DESCRIPTOR-O !
    _RUHA-B-REUSE-ENTRY @
        RUHA-DOCUMENT-COLLECTION-DESCRIPTOR-BYTES@
        _RUHA-B-REUSE-DESCRIPTOR-U !
    _RUHA-B-REUSE-ENTRY @ RUHA-DOCUMENT-COLLECTION-NATIVE-OFFSET@
        _RUHA-B-REUSE-NATIVE-O !
    _RUHA-B-REUSE-ENTRY @ RUHA-DOCUMENT-COLLECTION-NATIVE-BYTES@
        _RUHA-B-REUSE-NATIVE-U !
    _RUHA-B-REUSE-DESCRIPTOR-U @ 0=
        _RUHA-B-REUSE-NATIVE-U @ 0= <> IF 0 EXIT THEN
    _RUHA-B-REUSE-DESCRIPTOR-O @ DUP 0< IF DROP 0 EXIT THEN
    DUP UCSN-DESCRIPTOR-SIZE MOD IF DROP 0 EXIT THEN DROP
    _RUHA-B-REUSE-DESCRIPTOR-U @ DUP 0< IF DROP 0 EXIT THEN
    DUP UCSN-DESCRIPTOR-SIZE MOD IF DROP 0 EXIT THEN DROP
    _RUHA-B-REUSE-DESCRIPTOR-O @ _RUHA-B-REUSE-DESCRIPTOR-U @
        _RUHA-UADD? 0= IF DROP 0 EXIT THEN
    _RUHA-B-PRIOR-DESCRIPTORS-U @ U> IF 0 EXIT THEN
    _RUHA-B-REUSE-NATIVE-O @ DUP 0< IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN DROP
    _RUHA-B-REUSE-NATIVE-U @ DUP 0< IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN DROP
    _RUHA-B-REUSE-NATIVE-O @ _RUHA-B-REUSE-NATIVE-U @
        _RUHA-UADD? 0= IF DROP 0 EXIT THEN
    _RUHA-B-PRIOR-NATIVE-U @ U> IF 0 EXIT THEN
    _RUHA-B-REUSE-DESCRIPTOR-U @ CHK-EVERY-FRAME? AND IF
        _RUHA-B-ADAPTER @ _RUHA-A.COLLECTION-VALIDATION-A @
        _RUHA-B-ADAPTER @ _RUHA-A.COLLECTION-VALIDATION-U @
        _RUHA-B-ADAPTER @ _RUHA-A.COLLECTION-WORK-A @
        _RUHA-B-ADAPTER @ _RUHA-A.COLLECTION-WORK-U @
        _RUHA-B-PRIOR-DESCRIPTORS-A @
            _RUHA-B-REUSE-DESCRIPTOR-O @ +
        _RUHA-B-REUSE-DESCRIPTOR-U @
        _RUHA-B-PRIOR-NATIVE-A @ _RUHA-B-REUSE-NATIVE-O @ +
        _RUHA-B-REUSE-NATIVE-U @ UCSN-FROZEN-VALIDATE
        UCSN-S-OK = _RUHA-SLICES-DAMAGED CHK-NAME 0= IF 0 EXIT THEN
    THEN

    _RUHA-B-REUSE-ENTRY @
        RUHA-DOCUMENT-DATA-GRAPHICS-DESCRIPTOR-OFFSET@
        _RUHA-B-REUSE-DGRAPH-DESCRIPTOR-O !
    _RUHA-B-REUSE-ENTRY @
        RUHA-DOCUMENT-DATA-GRAPHICS-DESCRIPTOR-BYTES@
        _RUHA-B-REUSE-DGRAPH-DESCRIPTOR-U !
    _RUHA-B-REUSE-ENTRY @ RUHA-DOCUMENT-DATA-GRAPHICS-NATIVE-OFFSET@
        _RUHA-B-REUSE-DGRAPH-NATIVE-O !
    _RUHA-B-REUSE-ENTRY @ RUHA-DOCUMENT-DATA-GRAPHICS-NATIVE-BYTES@
        _RUHA-B-REUSE-DGRAPH-NATIVE-U !
    _RUHA-B-REUSE-DGRAPH-DESCRIPTOR-U @ 0=
        _RUHA-B-REUSE-DGRAPH-NATIVE-U @ 0= <> IF 0 EXIT THEN
    _RUHA-B-REUSE-DGRAPH-DESCRIPTOR-O @ DUP 0< IF DROP 0 EXIT THEN
    DUP UDGSN-DESCRIPTOR-SIZE MOD IF DROP 0 EXIT THEN DROP
    _RUHA-B-REUSE-DGRAPH-DESCRIPTOR-U @ DUP 0< IF DROP 0 EXIT THEN
    DUP UDGSN-DESCRIPTOR-SIZE MOD IF DROP 0 EXIT THEN DROP
    _RUHA-B-REUSE-DGRAPH-DESCRIPTOR-O @
        _RUHA-B-REUSE-DGRAPH-DESCRIPTOR-U @
        _RUHA-UADD? 0= IF DROP 0 EXIT THEN
    _RUHA-B-PRIOR-DGRAPH-DESCRIPTORS-U @ U> IF 0 EXIT THEN
    _RUHA-B-REUSE-DGRAPH-NATIVE-O @ DUP 0< IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN DROP
    _RUHA-B-REUSE-DGRAPH-NATIVE-U @ DUP 0< IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN DROP
    _RUHA-B-REUSE-DGRAPH-NATIVE-O @ _RUHA-B-REUSE-DGRAPH-NATIVE-U @
        _RUHA-UADD? 0= IF DROP 0 EXIT THEN
    _RUHA-B-PRIOR-DGRAPH-NATIVE-U @ U> IF 0 EXIT THEN
    _RUHA-B-REUSE-DGRAPH-DESCRIPTOR-U @ CHK-EVERY-FRAME? AND IF
        _RUHA-B-ADAPTER @ _RUHA-A.COLLECTION-WORK-A @
        _RUHA-B-ADAPTER @ _RUHA-A.COLLECTION-WORK-U @
        _RUHA-B-PRIOR-DGRAPH-DESCRIPTORS-A @
            _RUHA-B-REUSE-DGRAPH-DESCRIPTOR-O @ +
        _RUHA-B-REUSE-DGRAPH-DESCRIPTOR-U @
        _RUHA-B-PRIOR-DGRAPH-NATIVE-A @
            _RUHA-B-REUSE-DGRAPH-NATIVE-O @ +
        _RUHA-B-REUSE-DGRAPH-NATIVE-U @ UDGSN-FROZEN-VALIDATE
        UDGSN-S-OK = _RUHA-SLICES-DAMAGED CHK-NAME 0= IF 0 EXIT THEN
    THEN

    _RUHA-B-REUSE-ENTRY @
        RUHA-DOCUMENT-STATUS-FIELDS-DESCRIPTOR-OFFSET@
        _RUHA-B-REUSE-SFIELD-DESCRIPTOR-O !
    _RUHA-B-REUSE-ENTRY @
        RUHA-DOCUMENT-STATUS-FIELDS-DESCRIPTOR-BYTES@
        _RUHA-B-REUSE-SFIELD-DESCRIPTOR-U !
    _RUHA-B-REUSE-ENTRY @ RUHA-DOCUMENT-STATUS-FIELDS-NATIVE-OFFSET@
        _RUHA-B-REUSE-SFIELD-NATIVE-O !
    _RUHA-B-REUSE-ENTRY @ RUHA-DOCUMENT-STATUS-FIELDS-NATIVE-BYTES@
        _RUHA-B-REUSE-SFIELD-NATIVE-U !
    _RUHA-B-REUSE-SFIELD-DESCRIPTOR-U @ 0=
        _RUHA-B-REUSE-SFIELD-NATIVE-U @ 0= <> IF 0 EXIT THEN
    _RUHA-B-REUSE-SFIELD-DESCRIPTOR-O @ DUP 0< IF DROP 0 EXIT THEN
    DUP USFSN-DESCRIPTOR-SIZE MOD IF DROP 0 EXIT THEN DROP
    _RUHA-B-REUSE-SFIELD-DESCRIPTOR-U @ DUP 0< IF DROP 0 EXIT THEN
    DUP USFSN-DESCRIPTOR-SIZE MOD IF DROP 0 EXIT THEN DROP
    _RUHA-B-REUSE-SFIELD-DESCRIPTOR-O @
        _RUHA-B-REUSE-SFIELD-DESCRIPTOR-U @
        _RUHA-UADD? 0= IF DROP 0 EXIT THEN
    _RUHA-B-PRIOR-SFIELD-DESCRIPTORS-U @ U> IF 0 EXIT THEN
    _RUHA-B-REUSE-SFIELD-NATIVE-O @ DUP 0< IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN DROP
    _RUHA-B-REUSE-SFIELD-NATIVE-U @ DUP 0< IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN DROP
    _RUHA-B-REUSE-SFIELD-NATIVE-O @ _RUHA-B-REUSE-SFIELD-NATIVE-U @
        _RUHA-UADD? 0= IF DROP 0 EXIT THEN
    _RUHA-B-PRIOR-SFIELD-NATIVE-U @ U> IF 0 EXIT THEN
    _RUHA-B-REUSE-SFIELD-DESCRIPTOR-U @ CHK-EVERY-FRAME? AND IF
        _RUHA-B-ADAPTER @ _RUHA-A.COLLECTION-WORK-A @
        _RUHA-B-ADAPTER @ _RUHA-A.COLLECTION-WORK-U @
        _RUHA-B-PRIOR-SFIELD-DESCRIPTORS-A @
            _RUHA-B-REUSE-SFIELD-DESCRIPTOR-O @ +
        _RUHA-B-REUSE-SFIELD-DESCRIPTOR-U @
        _RUHA-B-PRIOR-SFIELD-NATIVE-A @
            _RUHA-B-REUSE-SFIELD-NATIVE-O @ +
        _RUHA-B-REUSE-SFIELD-NATIVE-U @ USFSN-FROZEN-VALIDATE
        USFSN-S-OK = _RUHA-SLICES-DAMAGED CHK-NAME 0= IF 0 EXIT THEN
    THEN

    _RUHA-B-REUSE-ENTRY @
        RUHA-DOCUMENT-FIELDS-DESCRIPTOR-OFFSET@
        _RUHA-B-REUSE-FIELD-DESCRIPTOR-O !
    _RUHA-B-REUSE-ENTRY @
        RUHA-DOCUMENT-FIELDS-DESCRIPTOR-BYTES@
        _RUHA-B-REUSE-FIELD-DESCRIPTOR-U !
    _RUHA-B-REUSE-ENTRY @ RUHA-DOCUMENT-FIELDS-NATIVE-OFFSET@
        _RUHA-B-REUSE-FIELD-NATIVE-O !
    _RUHA-B-REUSE-ENTRY @ RUHA-DOCUMENT-FIELDS-NATIVE-BYTES@
        _RUHA-B-REUSE-FIELD-NATIVE-U !
    _RUHA-B-REUSE-FIELD-DESCRIPTOR-U @ 0=
        _RUHA-B-REUSE-FIELD-NATIVE-U @ 0= <> IF 0 EXIT THEN
    _RUHA-B-REUSE-FIELD-DESCRIPTOR-O @ DUP 0< IF DROP 0 EXIT THEN
    DUP UFLSN-DESCRIPTOR-SIZE MOD IF DROP 0 EXIT THEN DROP
    _RUHA-B-REUSE-FIELD-DESCRIPTOR-U @ DUP 0< IF DROP 0 EXIT THEN
    DUP UFLSN-DESCRIPTOR-SIZE MOD IF DROP 0 EXIT THEN DROP
    _RUHA-B-REUSE-FIELD-DESCRIPTOR-O @
        _RUHA-B-REUSE-FIELD-DESCRIPTOR-U @
        _RUHA-UADD? 0= IF DROP 0 EXIT THEN
    _RUHA-B-PRIOR-FIELD-DESCRIPTORS-U @ U> IF 0 EXIT THEN
    _RUHA-B-REUSE-FIELD-NATIVE-O @ DUP 0< IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN DROP
    _RUHA-B-REUSE-FIELD-NATIVE-U @ DUP 0< IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN DROP
    _RUHA-B-REUSE-FIELD-NATIVE-O @ _RUHA-B-REUSE-FIELD-NATIVE-U @
        _RUHA-UADD? 0= IF DROP 0 EXIT THEN
    _RUHA-B-PRIOR-FIELD-NATIVE-U @ U> IF 0 EXIT THEN
    _RUHA-B-REUSE-FIELD-DESCRIPTOR-U @ CHK-EVERY-FRAME? AND IF
        _RUHA-B-ADAPTER @ _RUHA-A.COLLECTION-WORK-A @
        _RUHA-B-ADAPTER @ _RUHA-A.COLLECTION-WORK-U @
        _RUHA-B-PRIOR-FIELD-DESCRIPTORS-A @
            _RUHA-B-REUSE-FIELD-DESCRIPTOR-O @ +
        _RUHA-B-REUSE-FIELD-DESCRIPTOR-U @
        _RUHA-B-PRIOR-FIELD-NATIVE-A @
            _RUHA-B-REUSE-FIELD-NATIVE-O @ +
        _RUHA-B-REUSE-FIELD-NATIVE-U @ UFLSN-FROZEN-VALIDATE
        UFLSN-S-OK = _RUHA-SLICES-DAMAGED CHK-NAME 0= IF 0 EXIT THEN
    THEN

    _RUHA-B-REUSE-ENTRY @
        RUHA-DOCUMENT-DIALOGS-DESCRIPTOR-OFFSET@
        _RUHA-B-REUSE-DIALOG-DESCRIPTOR-O !
    _RUHA-B-REUSE-ENTRY @
        RUHA-DOCUMENT-DIALOGS-DESCRIPTOR-BYTES@
        _RUHA-B-REUSE-DIALOG-DESCRIPTOR-U !
    _RUHA-B-REUSE-ENTRY @ RUHA-DOCUMENT-DIALOGS-NATIVE-OFFSET@
        _RUHA-B-REUSE-DIALOG-NATIVE-O !
    _RUHA-B-REUSE-ENTRY @ RUHA-DOCUMENT-DIALOGS-NATIVE-BYTES@
        _RUHA-B-REUSE-DIALOG-NATIVE-U !
    _RUHA-B-REUSE-DIALOG-DESCRIPTOR-U @ 0=
        _RUHA-B-REUSE-DIALOG-NATIVE-U @ 0= <> IF 0 EXIT THEN
    _RUHA-B-REUSE-DIALOG-DESCRIPTOR-O @ DUP 0< IF DROP 0 EXIT THEN
    DUP UDLSN-DESCRIPTOR-SIZE MOD IF DROP 0 EXIT THEN DROP
    _RUHA-B-REUSE-DIALOG-DESCRIPTOR-U @ DUP 0< IF DROP 0 EXIT THEN
    DUP UDLSN-DESCRIPTOR-SIZE MOD IF DROP 0 EXIT THEN DROP
    _RUHA-B-REUSE-DIALOG-DESCRIPTOR-O @
        _RUHA-B-REUSE-DIALOG-DESCRIPTOR-U @
        _RUHA-UADD? 0= IF DROP 0 EXIT THEN
    _RUHA-B-PRIOR-DIALOG-DESCRIPTORS-U @ U> IF 0 EXIT THEN
    _RUHA-B-REUSE-DIALOG-NATIVE-O @ DUP 0< IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN DROP
    _RUHA-B-REUSE-DIALOG-NATIVE-U @ DUP 0< IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN DROP
    _RUHA-B-REUSE-DIALOG-NATIVE-O @ _RUHA-B-REUSE-DIALOG-NATIVE-U @
        _RUHA-UADD? 0= IF DROP 0 EXIT THEN
    _RUHA-B-PRIOR-DIALOG-NATIVE-U @ U> IF 0 EXIT THEN
    _RUHA-B-REUSE-DIALOG-DESCRIPTOR-U @ CHK-EVERY-FRAME? AND IF
        _RUHA-B-PRIOR-DIALOG-DESCRIPTORS-A @
            _RUHA-B-REUSE-DIALOG-DESCRIPTOR-O @ +
        _RUHA-B-REUSE-DIALOG-DESCRIPTOR-U @
        _RUHA-B-PRIOR-DIALOG-NATIVE-A @
            _RUHA-B-REUSE-DIALOG-NATIVE-O @ +
        _RUHA-B-REUSE-DIALOG-NATIVE-U @ UDLSN-FROZEN-VALIDATE
        UDLSN-S-OK = _RUHA-SLICES-DAMAGED CHK-NAME 0= IF 0 EXIT THEN
    THEN

    _RUHA-B-PRIOR-MENU? ;

: _RUHA-B-MENU-RECORD=?  ( prior current -- flag )
    _RUHA-B-MENU-CURRENT-RECORD ! _RUHA-B-MENU-PRIOR-RECORD !
    _RUHA-B-MENU-PRIOR-RECORD @ 24
    _RUHA-B-MENU-CURRENT-RECORD @ 24 COMPARE IF 0 EXIT THEN
    _RUHA-B-MENU-PRIOR-RECORD @ 32 + UMSN-RECORD-SIZE 32 -
    _RUHA-B-MENU-CURRENT-RECORD @ 32 + UMSN-RECORD-SIZE 32 -
        COMPARE 0= ;

: _RUHA-B-MENU-TOPOLOGY-RECORD=?  ( prior current -- flag )
    _RUHA-B-MENU-CURRENT-RECORD ! _RUHA-B-MENU-PRIOR-RECORD !
    _RUHA-B-MENU-PRIOR-RECORD @ 24
    _RUHA-B-MENU-CURRENT-RECORD @ 24 COMPARE IF 0 EXIT THEN
    _RUHA-B-MENU-PRIOR-RECORD @ 32 + 40
    _RUHA-B-MENU-CURRENT-RECORD @ 32 + 40 COMPARE IF 0 EXIT THEN
    _RUHA-B-MENU-PRIOR-RECORD @ 80 + 40
    _RUHA-B-MENU-CURRENT-RECORD @ 80 + 40 COMPARE IF 0 EXIT THEN
    _RUHA-B-MENU-PRIOR-RECORD @ UMSN-RECORD-KIND@
        UMSN-K-MENUBAR <> IF -1 EXIT THEN
    _RUHA-B-MENU-PRIOR-RECORD @ 120 + 32
    _RUHA-B-MENU-CURRENT-RECORD @ 120 + 32 COMPARE IF 0 EXIT THEN
    _RUHA-B-MENU-PRIOR-RECORD @ 184 + 8
    _RUHA-B-MENU-CURRENT-RECORD @ 184 + 8 COMPARE 0= ;

\ Derive both collision-free lineage decisions in one prior-slice traversal.
\ Exact identity ignores only caller-issued generation.  CONTROL-topology
\ identity additionally ignores UMSN state and descendant resolved geometry;
\ it retains exact text, graph/order fields, and the menubar geometry that
\ RUCP projects into CONTROL.  These epochs are provenance certificates, not
\ hashes.
: _RUHA-B-MENU-LINEAGE  ( prior-entry -- )
    0 _RUHA-B-MENU-EXACT ! 0 _RUHA-B-MENU-TOPOLOGY !
    _RUHA-B-REUSE-ENTRY !
    _RUHA-B-PRIOR-MENU? 0= IF EXIT THEN
    _RUHA-B-REUSE-RECORD-U @ _RUHA-B-CAPTURE-RECORD-U @ <> IF
        EXIT
    THEN
    _RUHA-B-REUSE-TEXT-U @ _RUHA-B-CAPTURE-TEXT-U @ <> IF EXIT THEN
    _RUHA-B-REUSE-TEXT-U @ IF
        _RUHA-B-PRIOR-TEXT-A @ _RUHA-B-REUSE-TEXT-O @ +
        _RUHA-B-REUSE-TEXT-U @
        _RUHA-B-TEXT-A @ _RUHA-B-TEXT-U @ +
        _RUHA-B-CAPTURE-TEXT-U @ COMPARE IF EXIT THEN
    THEN
    -1 _RUHA-B-MENU-EXACT ! -1 _RUHA-B-MENU-TOPOLOGY !
    _RUHA-B-REUSE-COUNT @ 0 ?DO
        _RUHA-B-PRIOR-RECORDS-A @ _RUHA-B-REUSE-RECORD-O @ +
            I UMSN-RECORD-SIZE * +
        _RUHA-B-RECORDS-A @ _RUHA-B-RECORDS-U @ +
            I UMSN-RECORD-SIZE * +
        _RUHA-B-MENU-EXACT @ IF
            2DUP _RUHA-B-MENU-RECORD=? 0= IF
                0 _RUHA-B-MENU-EXACT !
            THEN
        THEN
        _RUHA-B-MENU-TOPOLOGY-RECORD=? 0= IF
            0 _RUHA-B-MENU-EXACT ! 0 _RUHA-B-MENU-TOPOLOGY !
            UNLOOP EXIT
        THEN
    LOOP
    ;

: _RUHA-B-CAPTURE-MENU-EPOCHS  ( -- )
    _RUHA-B-COUNT @ 0= IF
        0 _RUHA-B-CAPTURE-MENU-EPOCH !
        0 _RUHA-B-CAPTURE-MENU-TOPOLOGY-EPOCH ! EXIT
    THEN
    _RUHA-B-GENERATION @ DUP _RUHA-B-CAPTURE-MENU-EPOCH !
        _RUHA-B-CAPTURE-MENU-TOPOLOGY-EPOCH !
    _RUHA-B-RECORD @ _RUHA-B-FIND-PRIOR IF
        _RUHA-B-MENU-LINEAGE
        _RUHA-B-MENU-EXACT @ IF
            _RUHA-B-REUSE-MENU-EPOCH @
                _RUHA-B-CAPTURE-MENU-EPOCH !
        THEN
        _RUHA-B-MENU-TOPOLOGY @ IF
            _RUHA-B-REUSE-MENU-TOPOLOGY-EPOCH @
                _RUHA-B-CAPTURE-MENU-TOPOLOGY-EPOCH !
        THEN
    ELSE
        DROP
    THEN ;

: _RUHA-B-STAGE  ( empty? record -- )
    _RUHA-B-STAGE-RECORD ! _RUHA-B-STAGE-EMPTY !
    _RUHA-B-STAGE-RECORD @ _RUHA-R.FLAGS @
    _RUHA-RF-STAGED _RUHA-RF-STAGED-EMPTY OR INVERT AND
    _RUHA-RF-STAGED OR
    _RUHA-B-STAGE-EMPTY @ IF _RUHA-RF-STAGED-EMPTY OR THEN
    _RUHA-B-STAGE-RECORD @ _RUHA-R.FLAGS ! ;

: _RUHA-B-CLEAR-STAGED  ( -- )
    _RUHA-B-ADAPTER @ _RUHA-A.CAPACITY @ 0 ?DO
        I _RUHA-B-ADAPTER @ _RUHA-RECORD-AT DUP _RUHA-R.FLAGS @
        _RUHA-RF-STAGED _RUHA-RF-STAGED-EMPTY OR INVERT AND
        SWAP _RUHA-R.FLAGS !
    LOOP ;

: _RUHA-B-FINALIZE-STAGED  ( -- )
    _RUHA-B-ADAPTER @ _RUHA-A.CAPACITY @ 0 ?DO
        I _RUHA-B-ADAPTER @ _RUHA-RECORD-AT DUP _RUHA-R.FLAGS @
        DUP _RUHA-RF-STAGED AND IF
            DUP _RUHA-RF-STAGED-EMPTY AND _RUHA-B-STAGE-EMPTY !
            _RUHA-RF-DIRTY _RUHA-RF-EMPTY OR
            _RUHA-RF-STAGED OR _RUHA-RF-STAGED-EMPTY OR INVERT AND
            _RUHA-B-STAGE-EMPTY @ IF _RUHA-RF-EMPTY OR THEN
        THEN
        SWAP _RUHA-R.FLAGS !
    LOOP ;

\ The document has an overlay, and it lies inside the document, where the
\ overlay's own lane places it.
: _RUHA-OWN-INSIDE?  ( record -- flag )
    >R
    R@ _RUHA-R.OV-HEIGHT @ 0> R@ _RUHA-R.OV-WIDTH @ 0> AND
    R@ _RUHA-R.OV-ROW @ R@ _RUHA-R.ROW @ < 0= AND
    R@ _RUHA-R.OV-COL @ R@ _RUHA-R.COL @ < 0= AND
    R@ _RUHA-R.OV-ROW @ R@ _RUHA-R.OV-HEIGHT @ +
        R@ _RUHA-R.ROW @ R@ _RUHA-R.HEIGHT @ + > 0= AND
    R@ _RUHA-R.OV-COL @ R@ _RUHA-R.OV-WIDTH @ +
        R> DUP _RUHA-R.COL @ SWAP _RUHA-R.WIDTH @ + > 0= AND ;

\ _RUHA-OWN-LAYER? ( record adapter -- flag )
\   The document's roots may lie beneath its own overlay: it has one inside
\   it, and the renderer can show that kind of overlay above them.
: _RUHA-OWN-LAYER?  ( record adapter -- flag )
    _RUHA-A.LAYERS @ SWAP
    DUP _RUHA-OWN-INSIDE? 0= IF 2DROP 0 EXIT THEN
    _RUHA-R.FLAGS @ DUP _RUHA-RF-OV-FIELD AND IF
        DROP RUHA-LAYER-FIELDS AND 0<> EXIT
    THEN
    _RUHA-RF-OV-DIALOG AND IF RUHA-LAYER-DIALOGS AND 0<> EXIT THEN
    DROP 0 ;

\ _RUHA-LAYERED? ( record adapter -- flag )
\   Every cell of the document that foreground paint covers lies under a
\   layer the producer puts above the document: its own overlay, when
\   _RUHA-OWN-LAYER? allows it, and each visible overlay slot's document,
\   which its host paints over the whole of its rectangle, when the policy
\   allows overlay panes.  The document's rows are taken in bands between
\   the edges of those layers, and each band in the spans they leave, which
\   must hold no foreground paint.
VARIABLE _RUHA-LY-R VARIABLE _RUHA-LY-OWN VARIABLE _RUHA-LY-XT
VARIABLE _RUHA-LY-ADAPTER VARIABLE _RUHA-LY-PANES
VARIABLE _RUHA-LY-ROW VARIABLE _RUHA-LY-BOTTOM VARIABLE _RUHA-LY-BAND-END
VARIABLE _RUHA-LY-COL VARIABLE _RUHA-LY-END VARIABLE _RUHA-LY-TO
VARIABLE _RUHA-LY-NEXT VARIABLE _RUHA-LY-A0 VARIABLE _RUHA-LY-A1

\ XT ( row col height width -- ) for each layer above the document.
\ A visible overlay slot's document other than the document itself.
: _RUHA-LY-PANE?  ( record -- flag )
    DUP _RUHA-LY-R @ = IF DROP 0 EXIT THEN
    DUP _RUHA-R.STATE @ _RUHA-RECORD-ATTACHED <> IF DROP 0 EXIT THEN
    DUP _RUHA-R.SLOT @ AHS-OVERLAY? 0= IF DROP 0 EXIT THEN
    _RUHA-LY-ADAPTER @ _RUHA-RECORD-VISIBLE? ;

: _RUHA-LY-EACH  ( xt -- )
    _RUHA-LY-XT !
    _RUHA-LY-OWN @ IF
        _RUHA-LY-R @ _RUHA-R.OV-ROW @ _RUHA-LY-R @ _RUHA-R.OV-COL @
        _RUHA-LY-R @ _RUHA-R.OV-HEIGHT @ _RUHA-LY-R @ _RUHA-R.OV-WIDTH @
        _RUHA-LY-XT @ EXECUTE
    THEN
    _RUHA-LY-PANES @ 0= IF EXIT THEN
    _RUHA-LY-ADAPTER @ _RUHA-A.CAPACITY @ 0 ?DO
        I _RUHA-LY-ADAPTER @ _RUHA-RECORD-AT DUP _RUHA-LY-PANE? IF
            DUP _RUHA-R.ROW @ OVER _RUHA-R.COL @
            2 PICK _RUHA-R.HEIGHT @ 3 PICK _RUHA-R.WIDTH @
            _RUHA-LY-XT @ EXECUTE
        THEN DROP
    LOOP ;

\ A layer's top or bottom edge inside the band from ROW ends the band.
: _RUHA-LY-EDGE  ( row -- )
    DUP _RUHA-LY-ROW @ > OVER _RUHA-LY-BAND-END @ < AND IF
        _RUHA-LY-BAND-END !
    ELSE DROP THEN ;
: _RUHA-LY-EDGES  ( row col height width -- )
    DROP NIP OVER + _RUHA-LY-EDGE _RUHA-LY-EDGE ;

\ In the band, a layer covering COL extends TO, and one starting after it
\ bounds NEXT.
: _RUHA-LY-SPAN  ( row col height width -- )
    ROT DUP _RUHA-LY-A0 ! + _RUHA-LY-A1 !
    OVER _RUHA-LY-ROW @ > IF 2DROP EXIT THEN
    + _RUHA-LY-ROW @ > 0= IF EXIT THEN
    _RUHA-LY-A1 @ _RUHA-LY-A0 @ > 0= IF EXIT THEN
    _RUHA-LY-A0 @ _RUHA-LY-COL @ > IF
        _RUHA-LY-A0 @ _RUHA-LY-NEXT @ MIN _RUHA-LY-NEXT ! EXIT
    THEN
    _RUHA-LY-A1 @ _RUHA-LY-COL @ > IF
        _RUHA-LY-A1 @ _RUHA-LY-TO @ MAX _RUHA-LY-TO !
    THEN ;

: _RUHA-LAYERED?  ( record adapter -- flag )
    OVER _RUHA-LY-R ! DUP _RUHA-LY-ADAPTER !
    DUP _RUHA-A.LAYERS @ RUHA-LAYER-PANES AND 0<> _RUHA-LY-PANES !
    _RUHA-OWN-LAYER? _RUHA-LY-OWN !
    _RUHA-LY-OWN @ _RUHA-LY-PANES @ OR 0= IF 0 EXIT THEN
    _RUHA-LY-R @ _RUHA-R.ROW @ _RUHA-LY-ROW !
    _RUHA-LY-R @ _RUHA-R.ROW @ _RUHA-LY-R @ _RUHA-R.HEIGHT @ + _RUHA-LY-BOTTOM !
    BEGIN _RUHA-LY-ROW @ _RUHA-LY-BOTTOM @ < WHILE
        _RUHA-LY-BOTTOM @ _RUHA-LY-BAND-END !
        ['] _RUHA-LY-EDGES _RUHA-LY-EACH
        _RUHA-LY-R @ _RUHA-R.COL @ _RUHA-LY-COL !
        _RUHA-LY-R @ _RUHA-R.COL @ _RUHA-LY-R @ _RUHA-R.WIDTH @ + _RUHA-LY-END !
        BEGIN _RUHA-LY-COL @ _RUHA-LY-END @ < WHILE
            _RUHA-LY-COL @ _RUHA-LY-TO ! _RUHA-LY-END @ _RUHA-LY-NEXT !
            ['] _RUHA-LY-SPAN _RUHA-LY-EACH
            _RUHA-LY-TO @ _RUHA-LY-COL @ > IF
                _RUHA-LY-TO @ _RUHA-LY-COL !
            ELSE
                _RUHA-LY-ROW @ _RUHA-LY-COL @
                _RUHA-LY-BAND-END @ _RUHA-LY-ROW @ -
                _RUHA-LY-NEXT @ _RUHA-LY-COL @ -
                SCR-OCCLUSION-RECT? 0= IF DROP 0 EXIT THEN
                IF 0 EXIT THEN
                _RUHA-LY-NEXT @ _RUHA-LY-COL !
            THEN
        REPEAT
        _RUHA-LY-BAND-END @ _RUHA-LY-ROW !
    REPEAT -1 ;

: _RUHA-B-APPEND-DOCUMENT
    ( menu-epoch topology-epoch record-u text-u descriptor-u native-u dgraph-descriptor-u dgraph-native-u sfield-descriptor-u sfield-native-u field-descriptor-u field-native-u dialog-descriptor-u dialog-native-u -- status )
    _RUHA-B-APPEND-DIALOG-NATIVE-U !
        _RUHA-B-APPEND-DIALOG-DESCRIPTOR-U !
    _RUHA-B-APPEND-FIELD-NATIVE-U !
        _RUHA-B-APPEND-FIELD-DESCRIPTOR-U !
    _RUHA-B-APPEND-SFIELD-NATIVE-U !
        _RUHA-B-APPEND-SFIELD-DESCRIPTOR-U !
    _RUHA-B-APPEND-DGRAPH-NATIVE-U !
        _RUHA-B-APPEND-DGRAPH-DESCRIPTOR-U !
    _RUHA-B-APPEND-NATIVE-U ! _RUHA-B-APPEND-DESCRIPTOR-U !
    _RUHA-B-APPEND-TEXT-U ! _RUHA-B-APPEND-RECORD-U !
    _RUHA-B-APPEND-MENU-TOPOLOGY-EPOCH ! _RUHA-B-APPEND-MENU-EPOCH !
    _RUHA-B-RECORD @ _RUHA-R.SLOT @ AHS.INST @
    DUP CINST.ID @ _RUHA-B-APPEND-OWNER-ID !
    CINST.GENERATION @ _RUHA-B-APPEND-OWNER-GEN !
    _RUHA-B-APPEND-OWNER-ID @ 0=
    _RUHA-B-APPEND-OWNER-GEN @ 0= OR IF RUHA-S-INVALID EXIT THEN
    _RUHA-B-APPEND-RECORD-U @ 0=
        _RUHA-B-APPEND-MENU-EPOCH @ 0= <> IF RUHA-S-INVALID EXIT THEN
    _RUHA-B-APPEND-RECORD-U @ 0=
        _RUHA-B-APPEND-MENU-TOPOLOGY-EPOCH @ 0= <> IF
            RUHA-S-INVALID EXIT
        THEN
    _RUHA-B-APPEND-MENU-TOPOLOGY-EPOCH @
        _RUHA-B-APPEND-MENU-EPOCH @ U> IF RUHA-S-INVALID EXIT THEN
    _RUHA-B-APPEND-MENU-EPOCH @
        _RUHA-B-GENERATION @ U> IF RUHA-S-INVALID EXIT THEN
    _RUHA-B-APPEND-MENU-TOPOLOGY-EPOCH @
        _RUHA-B-GENERATION @ U> IF RUHA-S-INVALID EXIT THEN
    _RUHA-B-APPEND-RECORD-U @ 0=
        _RUHA-B-APPEND-TEXT-U @ 0<> AND IF RUHA-S-INVALID EXIT THEN
    _RUHA-B-DIRECTORY-U @ RUHA-DOCUMENT-SIZE _RUHA-UADD?
        0= IF DROP RUHA-S-CAPACITY EXIT THEN
    DUP _RUHA-B-ADAPTER @ _RUHA-A.SNAP-DIRECTORY-BANK-U @ U> IF
        DROP RUHA-S-CAPACITY EXIT
    THEN _RUHA-B-NEXT !
    _RUHA-B-RECORDS-U @ _RUHA-B-APPEND-RECORD-U @ _RUHA-UADD?
        0= IF DROP RUHA-S-CAPACITY EXIT THEN
    DUP _RUHA-B-ADAPTER @ _RUHA-A.SNAP-RECORD-BANK-U @ U> IF
        DROP RUHA-S-CAPACITY EXIT
    THEN _RUHA-B-COUNT !
    _RUHA-B-TEXT-U @ _RUHA-B-APPEND-TEXT-U @ _RUHA-UADD?
        0= IF DROP RUHA-S-CAPACITY EXIT THEN
    DUP _RUHA-B-ADAPTER @ _RUHA-A.SNAP-TEXT-BANK-U @ U> IF
        DROP RUHA-S-CAPACITY EXIT
    THEN _RUHA-B-CAPTURE-TEXT-U !
    _RUHA-B-DESCRIPTORS-U @ _RUHA-B-APPEND-DESCRIPTOR-U @
        _RUHA-UADD? 0= IF DROP RUHA-S-CAPACITY EXIT THEN
    DUP _RUHA-B-ADAPTER @ _RUHA-A.SNAP-DESCRIPTOR-BANK-U @ U> IF
        DROP RUHA-S-CAPACITY EXIT
    THEN _RUHA-B-APPEND-DESCRIPTOR-NEXT !
    _RUHA-B-NATIVE-U @ _RUHA-B-APPEND-NATIVE-U @
        _RUHA-UADD? 0= IF DROP RUHA-S-CAPACITY EXIT THEN
    DUP _RUHA-B-ADAPTER @ _RUHA-A.SNAP-NATIVE-BANK-U @ U> IF
        DROP RUHA-S-CAPACITY EXIT
    THEN _RUHA-B-APPEND-NATIVE-NEXT !
    _RUHA-B-DGRAPH-DESCRIPTORS-U @
        _RUHA-B-APPEND-DGRAPH-DESCRIPTOR-U @
        _RUHA-UADD? 0= IF DROP RUHA-S-CAPACITY EXIT THEN
    DUP _RUHA-B-ADAPTER @
        _RUHA-A.SNAP-DGRAPH-DESCRIPTOR-BANK-U @ U> IF
        DROP RUHA-S-CAPACITY EXIT
    THEN _RUHA-B-APPEND-DGRAPH-DESCRIPTOR-NEXT !
    _RUHA-B-DGRAPH-NATIVE-U @ _RUHA-B-APPEND-DGRAPH-NATIVE-U @
        _RUHA-UADD? 0= IF DROP RUHA-S-CAPACITY EXIT THEN
    DUP _RUHA-B-ADAPTER @ _RUHA-A.SNAP-DGRAPH-NATIVE-BANK-U @ U> IF
        DROP RUHA-S-CAPACITY EXIT
    THEN _RUHA-B-APPEND-DGRAPH-NATIVE-NEXT !

    _RUHA-B-SFIELD-DESCRIPTORS-U @
        _RUHA-B-APPEND-SFIELD-DESCRIPTOR-U @
        _RUHA-UADD? 0= IF DROP RUHA-S-CAPACITY EXIT THEN
    DUP _RUHA-B-ADAPTER @
        _RUHA-A.SNAP-SFIELD-DESCRIPTOR-BANK-U @ U> IF
        DROP RUHA-S-CAPACITY EXIT
    THEN _RUHA-B-APPEND-SFIELD-DESCRIPTOR-NEXT !
    _RUHA-B-SFIELD-NATIVE-U @ _RUHA-B-APPEND-SFIELD-NATIVE-U @
        _RUHA-UADD? 0= IF DROP RUHA-S-CAPACITY EXIT THEN
    DUP _RUHA-B-ADAPTER @ _RUHA-A.SNAP-SFIELD-NATIVE-BANK-U @ U> IF
        DROP RUHA-S-CAPACITY EXIT
    THEN _RUHA-B-APPEND-SFIELD-NATIVE-NEXT !

    _RUHA-B-FIELD-DESCRIPTORS-U @
        _RUHA-B-APPEND-FIELD-DESCRIPTOR-U @
        _RUHA-UADD? 0= IF DROP RUHA-S-CAPACITY EXIT THEN
    DUP _RUHA-B-ADAPTER @
        _RUHA-A.SNAP-FIELD-DESCRIPTOR-BANK-U @ U> IF
        DROP RUHA-S-CAPACITY EXIT
    THEN _RUHA-B-APPEND-FIELD-DESCRIPTOR-NEXT !
    _RUHA-B-FIELD-NATIVE-U @ _RUHA-B-APPEND-FIELD-NATIVE-U @
        _RUHA-UADD? 0= IF DROP RUHA-S-CAPACITY EXIT THEN
    DUP _RUHA-B-ADAPTER @ _RUHA-A.SNAP-FIELD-NATIVE-BANK-U @ U> IF
        DROP RUHA-S-CAPACITY EXIT
    THEN _RUHA-B-APPEND-FIELD-NATIVE-NEXT !
    _RUHA-B-DIALOG-DESCRIPTORS-U @
        _RUHA-B-APPEND-DIALOG-DESCRIPTOR-U @
        _RUHA-UADD? 0= IF DROP RUHA-S-CAPACITY EXIT THEN
    DUP _RUHA-B-ADAPTER @
        _RUHA-A.SNAP-DIALOG-DESCRIPTOR-BANK-U @ U> IF
        DROP RUHA-S-CAPACITY EXIT
    THEN _RUHA-B-APPEND-DIALOG-DESCRIPTOR-NEXT !
    _RUHA-B-DIALOG-NATIVE-U @ _RUHA-B-APPEND-DIALOG-NATIVE-U @
        _RUHA-UADD? 0= IF DROP RUHA-S-CAPACITY EXIT THEN
    DUP _RUHA-B-ADAPTER @ _RUHA-A.SNAP-DIALOG-NATIVE-BANK-U @ U> IF
        DROP RUHA-S-CAPACITY EXIT
    THEN _RUHA-B-APPEND-DIALOG-NATIVE-NEXT !

    _RUHA-B-DIRECTORY-A @ _RUHA-B-DIRECTORY-U @ + DUP
        _RUHA-B-ENTRY ! RUHA-DOCUMENT-SIZE 0 FILL
    _RUHA-B-RECORD @ _RUHA-R.TOKEN @ _RUHA-B-ENTRY @ _RUHA-D.TOKEN !
    _RUHA-B-RECORD @ _RUHA-R.SLOT-ID @ _RUHA-B-ENTRY @ _RUHA-D.SLOT-ID !
    _RUHA-B-RECORD @ _RUHA-R.ROW @ _RUHA-B-ENTRY @ _RUHA-D.ROW !
    _RUHA-B-RECORD @ _RUHA-R.COL @ _RUHA-B-ENTRY @ _RUHA-D.COL !
    _RUHA-B-RECORD @ _RUHA-R.HEIGHT @ _RUHA-B-ENTRY @ _RUHA-D.HEIGHT !
    _RUHA-B-RECORD @ _RUHA-R.WIDTH @ _RUHA-B-ENTRY @ _RUHA-D.WIDTH !
    _RUHA-B-RECORDS-U @ _RUHA-B-ENTRY @ _RUHA-D.RECORD-OFF !
    _RUHA-B-APPEND-RECORD-U @ _RUHA-B-ENTRY @ _RUHA-D.RECORD-U !
    _RUHA-B-TEXT-U @ _RUHA-B-ENTRY @ _RUHA-D.TEXT-OFF !
    _RUHA-B-APPEND-TEXT-U @ _RUHA-B-ENTRY @ _RUHA-D.TEXT-U !
    _RUHA-B-DESCRIPTORS-U @ _RUHA-B-ENTRY @
        _RUHA-D.COLLECTION-DESCRIPTOR-OFF !
    _RUHA-B-APPEND-DESCRIPTOR-U @ _RUHA-B-ENTRY @
        _RUHA-D.COLLECTION-DESCRIPTOR-U !
    _RUHA-B-NATIVE-U @ _RUHA-B-ENTRY @ _RUHA-D.COLLECTION-NATIVE-OFF !
    _RUHA-B-APPEND-NATIVE-U @ _RUHA-B-ENTRY @
        _RUHA-D.COLLECTION-NATIVE-U !
    _RUHA-B-DGRAPH-DESCRIPTORS-U @ _RUHA-B-ENTRY @
        _RUHA-D.DGRAPH-DESCRIPTOR-OFF !
    _RUHA-B-APPEND-DGRAPH-DESCRIPTOR-U @ _RUHA-B-ENTRY @
        _RUHA-D.DGRAPH-DESCRIPTOR-U !
    _RUHA-B-DGRAPH-NATIVE-U @ _RUHA-B-ENTRY @
        _RUHA-D.DGRAPH-NATIVE-OFF !
    _RUHA-B-APPEND-DGRAPH-NATIVE-U @ _RUHA-B-ENTRY @
        _RUHA-D.DGRAPH-NATIVE-U !
    _RUHA-B-SFIELD-DESCRIPTORS-U @ _RUHA-B-ENTRY @
        _RUHA-D.SFIELD-DESCRIPTOR-OFF !
    _RUHA-B-APPEND-SFIELD-DESCRIPTOR-U @ _RUHA-B-ENTRY @
        _RUHA-D.SFIELD-DESCRIPTOR-U !
    _RUHA-B-SFIELD-NATIVE-U @ _RUHA-B-ENTRY @
        _RUHA-D.SFIELD-NATIVE-OFF !
    _RUHA-B-APPEND-SFIELD-NATIVE-U @ _RUHA-B-ENTRY @
        _RUHA-D.SFIELD-NATIVE-U !

    _RUHA-B-FIELD-DESCRIPTORS-U @ _RUHA-B-ENTRY @
        _RUHA-D.FIELD-DESCRIPTOR-OFF !
    _RUHA-B-APPEND-FIELD-DESCRIPTOR-U @ _RUHA-B-ENTRY @
        _RUHA-D.FIELD-DESCRIPTOR-U !
    _RUHA-B-FIELD-NATIVE-U @ _RUHA-B-ENTRY @
        _RUHA-D.FIELD-NATIVE-OFF !
    _RUHA-B-APPEND-FIELD-NATIVE-U @ _RUHA-B-ENTRY @
        _RUHA-D.FIELD-NATIVE-U !
    _RUHA-B-DIALOG-DESCRIPTORS-U @ _RUHA-B-ENTRY @
        _RUHA-D.DIALOG-DESCRIPTOR-OFF !
    _RUHA-B-APPEND-DIALOG-DESCRIPTOR-U @ _RUHA-B-ENTRY @
        _RUHA-D.DIALOG-DESCRIPTOR-U !
    _RUHA-B-DIALOG-NATIVE-U @ _RUHA-B-ENTRY @
        _RUHA-D.DIALOG-NATIVE-OFF !
    _RUHA-B-APPEND-DIALOG-NATIVE-U @ _RUHA-B-ENTRY @
        _RUHA-D.DIALOG-NATIVE-U !
    _RUHA-B-APPEND-MENU-EPOCH @ _RUHA-B-ENTRY @ _RUHA-D.MENU-EPOCH !
    _RUHA-B-APPEND-MENU-TOPOLOGY-EPOCH @ _RUHA-B-ENTRY @
        _RUHA-D.MENU-TOPOLOGY-EPOCH !
    _RUHA-B-APPEND-OWNER-ID @ _RUHA-B-ENTRY @ _RUHA-D.OWNER-ID !
    _RUHA-B-APPEND-OWNER-GEN @ _RUHA-B-ENTRY @ _RUHA-D.OWNER-GEN !
    _RUHA-B-RECORD @ _RUHA-R.SLOT @ AHS-OVERLAY? IF 1 ELSE 0 THEN
        _RUHA-B-ENTRY @ _RUHA-D.LAYER !
    _RUHA-B-RECORD @ _RUHA-B-ADAPTER @ _RUHA-OWN-LAYER? IF
        _RUHA-B-RECORD @ _RUHA-R.OV-ROW @ _RUHA-B-ENTRY @ _RUHA-D.OV-ROW !
        _RUHA-B-RECORD @ _RUHA-R.OV-COL @ _RUHA-B-ENTRY @ _RUHA-D.OV-COL !
        _RUHA-B-RECORD @ _RUHA-R.OV-HEIGHT @ _RUHA-B-ENTRY @ _RUHA-D.OV-HEIGHT !
        _RUHA-B-RECORD @ _RUHA-R.OV-WIDTH @ _RUHA-B-ENTRY @ _RUHA-D.OV-WIDTH !
    THEN
    _RUHA-B-NEXT @ _RUHA-B-DIRECTORY-U !
    _RUHA-B-COUNT @ _RUHA-B-RECORDS-U !
    _RUHA-B-CAPTURE-TEXT-U @ _RUHA-B-TEXT-U !
    _RUHA-B-APPEND-DESCRIPTOR-NEXT @ _RUHA-B-DESCRIPTORS-U !
    _RUHA-B-APPEND-NATIVE-NEXT @ _RUHA-B-NATIVE-U !
    _RUHA-B-APPEND-DGRAPH-DESCRIPTOR-NEXT @
        _RUHA-B-DGRAPH-DESCRIPTORS-U !
    _RUHA-B-APPEND-DGRAPH-NATIVE-NEXT @ _RUHA-B-DGRAPH-NATIVE-U !
    _RUHA-B-APPEND-SFIELD-DESCRIPTOR-NEXT @
        _RUHA-B-SFIELD-DESCRIPTORS-U !
    _RUHA-B-APPEND-SFIELD-NATIVE-NEXT @ _RUHA-B-SFIELD-NATIVE-U !

    _RUHA-B-APPEND-FIELD-DESCRIPTOR-NEXT @
        _RUHA-B-FIELD-DESCRIPTORS-U !
    _RUHA-B-APPEND-FIELD-NATIVE-NEXT @ _RUHA-B-FIELD-NATIVE-U !
    _RUHA-B-APPEND-DIALOG-DESCRIPTOR-NEXT @
        _RUHA-B-DIALOG-DESCRIPTORS-U !
    _RUHA-B-APPEND-DIALOG-NATIVE-NEXT @ _RUHA-B-DIALOG-NATIVE-U !
    1 _RUHA-B-DOCUMENTS +!
    RUHA-S-OK ;

: _RUHA-B-MAP-STATUS ( umsn-status -- ruha-status )
    DUP UMSN-S-CAPACITY = IF DROP RUHA-S-CAPACITY EXIT THEN
    DUP UMSN-S-INVALID = IF DROP RUHA-S-INVALID EXIT THEN
    DROP RUHA-S-UNAVAILABLE ;

: _RUHA-B-MAP-COLLECTION-STATUS ( ucsn-status -- ruha-status )
    DUP UCSN-S-CAPACITY = IF DROP RUHA-S-CAPACITY EXIT THEN
    DUP UCSN-S-UNAVAILABLE = IF DROP RUHA-S-UNAVAILABLE EXIT THEN
    DUP UCSN-S-INVALID = IF DROP RUHA-S-INVALID EXIT THEN
    DROP RUHA-S-INVALID ;

: _RUHA-B-MAP-DATA-GRAPHICS-STATUS ( udgsn-status -- ruha-status )
    DUP UDGSN-S-CAPACITY = IF DROP RUHA-S-CAPACITY EXIT THEN
    DUP UDGSN-S-UNAVAILABLE = IF DROP RUHA-S-UNAVAILABLE EXIT THEN
    DUP UDGSN-S-INVALID = IF DROP RUHA-S-INVALID EXIT THEN
    DROP RUHA-S-INVALID ;

: _RUHA-B-MAP-STATUS-FIELDS-STATUS ( usfsn-status -- ruha-status )
    DUP USFSN-S-CAPACITY = IF DROP RUHA-S-CAPACITY EXIT THEN
    DUP USFSN-S-UNAVAILABLE = IF DROP RUHA-S-UNAVAILABLE EXIT THEN
    DUP USFSN-S-INVALID = IF DROP RUHA-S-INVALID EXIT THEN
    DROP RUHA-S-INVALID ;

: _RUHA-B-MAP-FIELDS-STATUS ( uflsn-status -- ruha-status )
    DUP UFLSN-S-CAPACITY = IF DROP RUHA-S-CAPACITY EXIT THEN
    DUP UFLSN-S-UNAVAILABLE = IF DROP RUHA-S-UNAVAILABLE EXIT THEN
    DUP UFLSN-S-INVALID = IF DROP RUHA-S-INVALID EXIT THEN
    DROP RUHA-S-INVALID ;

: _RUHA-B-MAP-DIALOGS-STATUS ( uflsn-status -- ruha-status )
    DUP UDLSN-S-CAPACITY = IF DROP RUHA-S-CAPACITY EXIT THEN
    DUP UDLSN-S-UNAVAILABLE = IF DROP RUHA-S-UNAVAILABLE EXIT THEN
    DUP UDLSN-S-INVALID = IF DROP RUHA-S-INVALID EXIT THEN
    DROP RUHA-S-INVALID ;

\ Snapshot collectors use canonical optional spans: an empty tail is `0 0`,
\ never a one-past-end address paired with zero bytes.  CAPACITY >= USED is
\ proved before this helper is reached.
: _RUHA-B-TAIL-SPAN  ( base used capacity -- tail-a tail-u )
    OVER - DUP 0= IF DROP 2DROP 0 0 EXIT THEN
    >R + R> ;

: _RUHA-B-REUSE?  ( prior-entry -- status reused? )
    _RUHA-B-PRIOR-ENTRY? 0= IF RUHA-S-OK 0 EXIT THEN
    _RUHA-B-RECORDS-A @ _RUHA-B-RECORDS-U @ +
        _RUHA-B-REUSE-RECORD-TARGET !
    _RUHA-B-TEXT-A @ _RUHA-B-TEXT-U @ +
        _RUHA-B-REUSE-TEXT-TARGET !
    _RUHA-B-DESCRIPTORS-A @ _RUHA-B-DESCRIPTORS-U @ +
        _RUHA-B-REUSE-DESCRIPTOR-TARGET !
    _RUHA-B-NATIVE-A @ _RUHA-B-NATIVE-U @ +
        _RUHA-B-REUSE-NATIVE-TARGET !
    _RUHA-B-DGRAPH-DESCRIPTORS-A @
        _RUHA-B-DGRAPH-DESCRIPTORS-U @ +
        _RUHA-B-REUSE-DGRAPH-DESCRIPTOR-TARGET !
    _RUHA-B-DGRAPH-NATIVE-A @ _RUHA-B-DGRAPH-NATIVE-U @ +
        _RUHA-B-REUSE-DGRAPH-NATIVE-TARGET !
    _RUHA-B-SFIELD-DESCRIPTORS-A @
        _RUHA-B-SFIELD-DESCRIPTORS-U @ +
        _RUHA-B-REUSE-SFIELD-DESCRIPTOR-TARGET !
    _RUHA-B-SFIELD-NATIVE-A @ _RUHA-B-SFIELD-NATIVE-U @ +
        _RUHA-B-REUSE-SFIELD-NATIVE-TARGET !

    _RUHA-B-FIELD-DESCRIPTORS-A @
        _RUHA-B-FIELD-DESCRIPTORS-U @ +
        _RUHA-B-REUSE-FIELD-DESCRIPTOR-TARGET !
    _RUHA-B-FIELD-NATIVE-A @ _RUHA-B-FIELD-NATIVE-U @ +
        _RUHA-B-REUSE-FIELD-NATIVE-TARGET !
    _RUHA-B-DIALOG-DESCRIPTORS-A @
        _RUHA-B-DIALOG-DESCRIPTORS-U @ +
        _RUHA-B-REUSE-DIALOG-DESCRIPTOR-TARGET !
    _RUHA-B-DIALOG-NATIVE-A @ _RUHA-B-DIALOG-NATIVE-U @ +
        _RUHA-B-REUSE-DIALOG-NATIVE-TARGET !
    _RUHA-B-REUSE-MENU-EPOCH @
    _RUHA-B-REUSE-MENU-TOPOLOGY-EPOCH @
    _RUHA-B-REUSE-RECORD-U @ _RUHA-B-REUSE-TEXT-U @
    _RUHA-B-REUSE-DESCRIPTOR-U @ _RUHA-B-REUSE-NATIVE-U @
    _RUHA-B-REUSE-DGRAPH-DESCRIPTOR-U @
        _RUHA-B-REUSE-DGRAPH-NATIVE-U @
    _RUHA-B-REUSE-SFIELD-DESCRIPTOR-U @
        _RUHA-B-REUSE-SFIELD-NATIVE-U @

    _RUHA-B-REUSE-FIELD-DESCRIPTOR-U @
        _RUHA-B-REUSE-FIELD-NATIVE-U @
    _RUHA-B-REUSE-DIALOG-DESCRIPTOR-U @
        _RUHA-B-REUSE-DIALOG-NATIVE-U @
        _RUHA-B-APPEND-DOCUMENT
    \ Reuse is only a shortcut.  When the prior slices no longer fit behind
    \ the documents already captured in this draw, the document is captured
    \ afresh, where each family falls back within the space that is left.
    \ A refused append changes nothing, so the fresh capture starts clean.
    DUP RUHA-S-CAPACITY = IF DROP RUHA-S-OK 0 EXIT THEN
    DUP RUHA-S-OK <> IF -1 EXIT THEN DROP

    _RUHA-B-PRIOR-RECORDS-A @ _RUHA-B-REUSE-RECORD-O @ +
    _RUHA-B-REUSE-RECORD-TARGET @ _RUHA-B-REUSE-RECORD-U @ MOVE
    _RUHA-B-PRIOR-TEXT-A @ _RUHA-B-REUSE-TEXT-O @ +
    _RUHA-B-REUSE-TEXT-TARGET @ _RUHA-B-REUSE-TEXT-U @ MOVE
    _RUHA-B-PRIOR-DESCRIPTORS-A @ _RUHA-B-REUSE-DESCRIPTOR-O @ +
    _RUHA-B-REUSE-DESCRIPTOR-TARGET @
        _RUHA-B-REUSE-DESCRIPTOR-U @ MOVE
    _RUHA-B-PRIOR-NATIVE-A @ _RUHA-B-REUSE-NATIVE-O @ +
    _RUHA-B-REUSE-NATIVE-TARGET @ _RUHA-B-REUSE-NATIVE-U @ MOVE
    _RUHA-B-PRIOR-DGRAPH-DESCRIPTORS-A @
        _RUHA-B-REUSE-DGRAPH-DESCRIPTOR-O @ +
    _RUHA-B-REUSE-DGRAPH-DESCRIPTOR-TARGET @
        _RUHA-B-REUSE-DGRAPH-DESCRIPTOR-U @ MOVE
    _RUHA-B-PRIOR-DGRAPH-NATIVE-A @
        _RUHA-B-REUSE-DGRAPH-NATIVE-O @ +
    _RUHA-B-REUSE-DGRAPH-NATIVE-TARGET @
        _RUHA-B-REUSE-DGRAPH-NATIVE-U @ MOVE
    _RUHA-B-PRIOR-SFIELD-DESCRIPTORS-A @
        _RUHA-B-REUSE-SFIELD-DESCRIPTOR-O @ +
    _RUHA-B-REUSE-SFIELD-DESCRIPTOR-TARGET @
        _RUHA-B-REUSE-SFIELD-DESCRIPTOR-U @ MOVE
    _RUHA-B-PRIOR-SFIELD-NATIVE-A @
        _RUHA-B-REUSE-SFIELD-NATIVE-O @ +
    _RUHA-B-REUSE-SFIELD-NATIVE-TARGET @
        _RUHA-B-REUSE-SFIELD-NATIVE-U @ MOVE

    _RUHA-B-PRIOR-FIELD-DESCRIPTORS-A @
        _RUHA-B-REUSE-FIELD-DESCRIPTOR-O @ +
    _RUHA-B-REUSE-FIELD-DESCRIPTOR-TARGET @
        _RUHA-B-REUSE-FIELD-DESCRIPTOR-U @ MOVE
    _RUHA-B-PRIOR-FIELD-NATIVE-A @
        _RUHA-B-REUSE-FIELD-NATIVE-O @ +
    _RUHA-B-REUSE-FIELD-NATIVE-TARGET @
        _RUHA-B-REUSE-FIELD-NATIVE-U @ MOVE
    _RUHA-B-PRIOR-DIALOG-DESCRIPTORS-A @
        _RUHA-B-REUSE-DIALOG-DESCRIPTOR-O @ +
    _RUHA-B-REUSE-DIALOG-DESCRIPTOR-TARGET @
        _RUHA-B-REUSE-DIALOG-DESCRIPTOR-U @ MOVE
    _RUHA-B-PRIOR-DIALOG-NATIVE-A @
        _RUHA-B-REUSE-DIALOG-NATIVE-O @ +
    _RUHA-B-REUSE-DIALOG-NATIVE-TARGET @
        _RUHA-B-REUSE-DIALOG-NATIVE-U @ MOVE
    _RUHA-B-REUSE-COUNT @ 0 ?DO
        _RUHA-B-GENERATION @
        _RUHA-B-REUSE-RECORD-TARGET @ I UMSN-RECORD-SIZE * +
            _RUHA-UMSN.GENERATION !
    LOOP
    \ The menu slice copied is the capture the menus' count describes.
    _RUHA-B-RECORD @ _RUHA-R.MENU-GEN @ _RUHA-B-PRIOR-GENERATION @ = IF
        _RUHA-B-GENERATION @ _RUHA-B-RECORD @ _RUHA-R.MENU-GEN !
    THEN
    0 _RUHA-B-RECORD @ _RUHA-B-STAGE
    RUHA-S-OK -1 ;

VARIABLE _RUHA-B-FALL-BACK-REUSE
\ The family capturing now, and the families a build ran short of room in,
\ as RUHA-F-* bits (_RUHA-G-GROW?).
VARIABLE _RUHA-B-FAMILY
VARIABLE _RUHA-B-SHORT

\ _RUHA-B-FALL-BACK ( ruha-status -- status )
\   A family refused this document's own content, found nothing it could
\   publish, or ran out of bank.  Rather than fail every document, this one
\   falls back as a foreground-covered one does: a directory-only identity
\   with no semantic slices, so its residual CELL projection shows it, and
\   a dirty record, so the next draw captures it again.  As for a covered
\   document, the directory comparison marks the change of provenance.
: _RUHA-B-FALL-BACK  ( ruha-status -- status )
    RUHA-S-CAPACITY = IF _RUHA-B-SHORT @ _RUHA-B-FAMILY @ OR _RUHA-B-SHORT ! THEN
    RUHA-S-OK _RUHA-B-STATUS !
    _RUHA-B-FALL-BACK-REUSE @ _RUHA-B-EXACT-REUSE !
    _RUHA-B-RECORD @ _RUHA-RECORD-DIRTY!
    0 0 0 0 0 0 0 0 0 0 0 0 0 0 _RUHA-B-APPEND-DOCUMENT ;

\ While a full capture runs, in safe mode, for the shadow check or for the
\ full refresh, every visible document is captured live: none is reused,
\ and none is passed over as known empty.
VARIABLE _RUHA-B-FULL
0 _RUHA-B-FULL !

\ A painted document's menus take the slice of the snapshot before when
\ that slice was captured, or found unchanged, at a count that nothing the
\ menus read has passed since (URF-MENUS-SINCE?); each record then takes
\ this snapshot's generation.  Otherwise they are captured.  Safe mode, the
\ shadow check's full capture and the full refresh capture them always.
VARIABLE _RUHA-B-MK-GEN
VARIABLE _RUHA-B-MK-RECORDS-A
VARIABLE _RUHA-B-MK-RECORDS-U
VARIABLE _RUHA-B-MK-TEXT-A
VARIABLE _RUHA-B-MK-TEXT-U
VARIABLE _RUHA-DIAG-MENUS-KEPT
0 _RUHA-DIAG-MENUS-KEPT !

: _RUHA-B-MENUS-KEPT?  ( -- flag )
    _RUHA-B-FULL @ IF 0 EXIT THEN
    _RUHA-B-RECORD @ _RUHA-R.MENU-GEN @ DUP 0= IF DROP 0 EXIT THEN
        _RUHA-B-PRIOR-GENERATION @ <> IF 0 EXIT THEN
    _RUHA-B-RECORD @ _RUHA-B-FIND-PRIOR 0= IF DROP 0 EXIT THEN
    _RUHA-B-REUSE-ENTRY ! _RUHA-B-PRIOR-MENU? 0= IF 0 EXIT THEN
    _RUHA-B-REUSE-RECORD-U @ _RUHA-B-MK-RECORDS-U @ U> IF 0 EXIT THEN
    _RUHA-B-REUSE-TEXT-U @ _RUHA-B-MK-TEXT-U @ U> IF 0 EXIT THEN
    _RUHA-B-PRIOR-RECORDS-A @ _RUHA-B-REUSE-RECORD-O @ +
    _RUHA-B-REUSE-COUNT @
    _RUHA-B-RECORD @ _RUHA-R.MENU-STAMP @ URF-MENUS-SINCE? ;

: _RUHA-B-MENUS  ( UMSN-CAPTURE's arguments -- record-count text-used status )
    _RUHA-B-MK-TEXT-U ! _RUHA-B-MK-TEXT-A !
    _RUHA-B-MK-RECORDS-U ! _RUHA-B-MK-RECORDS-A !
    _RUHA-B-MENUS-KEPT? 0= IF
        _RUHA-B-MK-RECORDS-A @ _RUHA-B-MK-RECORDS-U @
        _RUHA-B-MK-TEXT-A @ _RUHA-B-MK-TEXT-U @ UMSN-CAPTURE EXIT
    THEN
    2DROP 2DROP _RUHA-B-MK-GEN !
    _RUHA-B-PRIOR-RECORDS-A @ _RUHA-B-REUSE-RECORD-O @ +
        _RUHA-B-MK-RECORDS-A @ _RUHA-B-REUSE-RECORD-U @ MOVE
    _RUHA-B-PRIOR-TEXT-A @ _RUHA-B-REUSE-TEXT-O @ +
        _RUHA-B-MK-TEXT-A @ _RUHA-B-REUSE-TEXT-U @ MOVE
    _RUHA-B-REUSE-COUNT @ 0 ?DO
        _RUHA-B-MK-GEN @
        _RUHA-B-MK-RECORDS-A @ I UMSN-RECORD-SIZE * + _RUHA-UMSN.GENERATION !
    LOOP
    1 _RUHA-DIAG-MENUS-KEPT +!
    _RUHA-B-REUSE-COUNT @ _RUHA-B-REUSE-TEXT-U @ UMSN-S-OK ;

\ The families of the document now current, captured in turn.
: _RUHA-B-CAPTURE-FAMILIES  ( -- status )
    _RUHA-B-GENERATION @
    _RUHA-B-ADAPTER @ _RUHA-A.WORK-A @
    _RUHA-B-ADAPTER @ _RUHA-A.WORK-U @
    _RUHA-B-ADAPTER @ _RUHA-A.WORK-TEXT-A @
    _RUHA-B-ADAPTER @ _RUHA-A.WORK-TEXT-U @
    _RUHA-B-RECORDS-A @ _RUHA-B-RECORDS-U @
    _RUHA-B-ADAPTER @ _RUHA-A.SNAP-RECORD-BANK-U @
        _RUHA-B-TAIL-SPAN
    _RUHA-B-TEXT-A @ _RUHA-B-TEXT-U @
    _RUHA-B-ADAPTER @ _RUHA-A.SNAP-TEXT-BANK-U @
        _RUHA-B-TAIL-SPAN
    RUHA-F-MENUS _RUHA-B-FAMILY ! _RUHA-B-MENUS
    _RUHA-B-STATUS ! _RUHA-B-CAPTURE-TEXT-U ! _RUHA-B-COUNT !
    _RUHA-B-STATUS @ UMSN-S-OK <> IF
        _RUHA-B-STATUS @ _RUHA-B-MAP-STATUS _RUHA-B-FALL-BACK EXIT
    THEN
    _RUHA-B-COUNT @ 0< _RUHA-B-CAPTURE-TEXT-U @ 0< OR IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-COUNT @ 0= _RUHA-B-CAPTURE-TEXT-U @ 0<> AND IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-COUNT @
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-RECORD-BANK-U @
            UMSN-RECORD-SIZE / U> IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-COUNT @ UMSN-RECORD-SIZE _RUHA-UMUL?
        0= IF DROP RUHA-S-INVALID EXIT THEN
        _RUHA-B-CAPTURE-RECORD-U !
    _RUHA-B-FULL @ 0= IF
        URF-NOW _RUHA-B-RECORD @ _RUHA-R.MENU-STAMP !
        _RUHA-B-GENERATION @ _RUHA-B-RECORD @ _RUHA-R.MENU-GEN !
    THEN

    _RUHA-B-ADAPTER @ _RUHA-A.COLLECTION-BUILDER
    _RUHA-B-ADAPTER @ _RUHA-A.COLLECTION-VALIDATION-A @
    _RUHA-B-ADAPTER @ _RUHA-A.COLLECTION-VALIDATION-U @
    _RUHA-B-ADAPTER @ _RUHA-A.COLLECTION-WORK-A @
    _RUHA-B-ADAPTER @ _RUHA-A.COLLECTION-WORK-U @
    _RUHA-B-DESCRIPTORS-A @ _RUHA-B-DESCRIPTORS-U @
    _RUHA-B-ADAPTER @ _RUHA-A.SNAP-DESCRIPTOR-BANK-U @
        _RUHA-B-TAIL-SPAN
    _RUHA-B-NATIVE-A @ _RUHA-B-NATIVE-U @
    _RUHA-B-ADAPTER @ _RUHA-A.SNAP-NATIVE-BANK-U @
        _RUHA-B-TAIL-SPAN
    RUHA-F-COLLECTIONS _RUHA-B-FAMILY ! UCSN-CAPTURE
    _RUHA-B-STATUS ! _RUHA-B-CAPTURE-NATIVE-U !
        _RUHA-B-COLLECTION-COUNT !
    _RUHA-B-STATUS @ UCSN-S-OK <> IF
        _RUHA-B-STATUS @ _RUHA-B-MAP-COLLECTION-STATUS _RUHA-B-FALL-BACK EXIT
    THEN
    _RUHA-B-COLLECTION-COUNT @ 0<
        _RUHA-B-CAPTURE-NATIVE-U @ 0< OR IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-COLLECTION-COUNT @ 0=
        _RUHA-B-CAPTURE-NATIVE-U @ 0= <> IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-COLLECTION-COUNT @ UCSN-DESCRIPTOR-SIZE _RUHA-UMUL?
        0= IF DROP RUHA-S-INVALID EXIT THEN
        _RUHA-B-CAPTURE-DESCRIPTOR-U !
    _RUHA-B-CAPTURE-DESCRIPTOR-U @
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-DESCRIPTOR-BANK-U @
            _RUHA-B-DESCRIPTORS-U @ - U> IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-CAPTURE-NATIVE-U @
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-NATIVE-BANK-U @
            _RUHA-B-NATIVE-U @ - U> IF
        RUHA-S-INVALID EXIT
    THEN

    _RUHA-B-ADAPTER @ _RUHA-A.DATA-GRAPHICS-BUILDER
    _RUHA-B-DGRAPH-DESCRIPTORS-A @
        _RUHA-B-DGRAPH-DESCRIPTORS-U @
    _RUHA-B-ADAPTER @ _RUHA-A.SNAP-DGRAPH-DESCRIPTOR-BANK-U @
        _RUHA-B-TAIL-SPAN
    _RUHA-B-DGRAPH-NATIVE-A @ _RUHA-B-DGRAPH-NATIVE-U @
    _RUHA-B-ADAPTER @ _RUHA-A.SNAP-DGRAPH-NATIVE-BANK-U @
        _RUHA-B-TAIL-SPAN
    RUHA-F-DATA-GRAPHICS _RUHA-B-FAMILY ! UDGSN-CAPTURE
    _RUHA-B-STATUS ! _RUHA-B-CAPTURE-DGRAPH-NATIVE-U !
        _RUHA-B-DGRAPH-COUNT !
    _RUHA-B-STATUS @ UDGSN-S-OK <> IF
        _RUHA-B-STATUS @ _RUHA-B-MAP-DATA-GRAPHICS-STATUS _RUHA-B-FALL-BACK EXIT
    THEN
    _RUHA-B-DGRAPH-COUNT @ 0<
        _RUHA-B-CAPTURE-DGRAPH-NATIVE-U @ 0< OR IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-DGRAPH-COUNT @ 0=
        _RUHA-B-CAPTURE-DGRAPH-NATIVE-U @ 0= <> IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-DGRAPH-COUNT @ UDGSN-DESCRIPTOR-SIZE _RUHA-UMUL?
        0= IF DROP RUHA-S-INVALID EXIT THEN
        _RUHA-B-CAPTURE-DGRAPH-DESCRIPTOR-U !
    _RUHA-B-CAPTURE-DGRAPH-DESCRIPTOR-U @
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-DGRAPH-DESCRIPTOR-BANK-U @
            _RUHA-B-DGRAPH-DESCRIPTORS-U @ - U> IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-CAPTURE-DGRAPH-NATIVE-U @
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-DGRAPH-NATIVE-BANK-U @
            _RUHA-B-DGRAPH-NATIVE-U @ - U> IF
        RUHA-S-INVALID EXIT
    THEN

    _RUHA-B-SFIELD-DESCRIPTORS-A @
        _RUHA-B-SFIELD-DESCRIPTORS-U @
    _RUHA-B-ADAPTER @ _RUHA-A.SNAP-SFIELD-DESCRIPTOR-BANK-U @
        _RUHA-B-TAIL-SPAN
    _RUHA-B-SFIELD-NATIVE-A @ _RUHA-B-SFIELD-NATIVE-U @
    _RUHA-B-ADAPTER @ _RUHA-A.SNAP-SFIELD-NATIVE-BANK-U @
        _RUHA-B-TAIL-SPAN
    RUHA-F-STATUS-FIELDS _RUHA-B-FAMILY ! USFSN-CAPTURE
    _RUHA-B-STATUS ! _RUHA-B-CAPTURE-SFIELD-NATIVE-U !
        _RUHA-B-SFIELD-COUNT !
    _RUHA-B-STATUS @ USFSN-S-OK <> IF
        _RUHA-B-STATUS @ _RUHA-B-MAP-STATUS-FIELDS-STATUS _RUHA-B-FALL-BACK EXIT
    THEN
    _RUHA-B-SFIELD-COUNT @ 0<
        _RUHA-B-CAPTURE-SFIELD-NATIVE-U @ 0< OR IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-SFIELD-COUNT @ 0=
        _RUHA-B-CAPTURE-SFIELD-NATIVE-U @ 0= <> IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-SFIELD-COUNT @ USFSN-DESCRIPTOR-SIZE _RUHA-UMUL?
        0= IF DROP RUHA-S-INVALID EXIT THEN
        _RUHA-B-CAPTURE-SFIELD-DESCRIPTOR-U !
    _RUHA-B-CAPTURE-SFIELD-DESCRIPTOR-U @
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-SFIELD-DESCRIPTOR-BANK-U @
            _RUHA-B-SFIELD-DESCRIPTORS-U @ - U> IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-CAPTURE-SFIELD-NATIVE-U @
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-SFIELD-NATIVE-BANK-U @
            _RUHA-B-SFIELD-NATIVE-U @ - U> IF
        RUHA-S-INVALID EXIT
    THEN

    _RUHA-B-FIELD-DESCRIPTORS-A @
        _RUHA-B-FIELD-DESCRIPTORS-U @
    _RUHA-B-ADAPTER @ _RUHA-A.SNAP-FIELD-DESCRIPTOR-BANK-U @
        _RUHA-B-TAIL-SPAN
    _RUHA-B-FIELD-NATIVE-A @ _RUHA-B-FIELD-NATIVE-U @
    _RUHA-B-ADAPTER @ _RUHA-A.SNAP-FIELD-NATIVE-BANK-U @
        _RUHA-B-TAIL-SPAN
    RUHA-F-FIELDS _RUHA-B-FAMILY ! UFLSN-CAPTURE
    _RUHA-B-STATUS ! _RUHA-B-CAPTURE-FIELD-NATIVE-U !
        _RUHA-B-FIELD-COUNT !
    _RUHA-B-STATUS @ UFLSN-S-OK <> IF
        _RUHA-B-STATUS @ _RUHA-B-MAP-FIELDS-STATUS _RUHA-B-FALL-BACK EXIT
    THEN
    _RUHA-B-FIELD-COUNT @ 0<
        _RUHA-B-CAPTURE-FIELD-NATIVE-U @ 0< OR IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-FIELD-COUNT @ 0=
        _RUHA-B-CAPTURE-FIELD-NATIVE-U @ 0= <> IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-FIELD-COUNT @ UFLSN-DESCRIPTOR-SIZE _RUHA-UMUL?
        0= IF DROP RUHA-S-INVALID EXIT THEN
        _RUHA-B-CAPTURE-FIELD-DESCRIPTOR-U !
    _RUHA-B-CAPTURE-FIELD-DESCRIPTOR-U @
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-FIELD-DESCRIPTOR-BANK-U @
            _RUHA-B-FIELD-DESCRIPTORS-U @ - U> IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-CAPTURE-FIELD-NATIVE-U @
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-FIELD-NATIVE-BANK-U @
            _RUHA-B-FIELD-NATIVE-U @ - U> IF
        RUHA-S-INVALID EXIT
    THEN

    _RUHA-B-DIALOG-DESCRIPTORS-A @
        _RUHA-B-DIALOG-DESCRIPTORS-U @
    _RUHA-B-ADAPTER @ _RUHA-A.SNAP-DIALOG-DESCRIPTOR-BANK-U @
        _RUHA-B-TAIL-SPAN
    _RUHA-B-DIALOG-NATIVE-A @ _RUHA-B-DIALOG-NATIVE-U @
    _RUHA-B-ADAPTER @ _RUHA-A.SNAP-DIALOG-NATIVE-BANK-U @
        _RUHA-B-TAIL-SPAN
    RUHA-F-DIALOGS _RUHA-B-FAMILY ! UDLSN-CAPTURE
    _RUHA-B-STATUS ! _RUHA-B-CAPTURE-DIALOG-NATIVE-U !
        _RUHA-B-DIALOG-COUNT !
    _RUHA-B-STATUS @ UDLSN-S-OK <> IF
        _RUHA-B-STATUS @ _RUHA-B-MAP-DIALOGS-STATUS _RUHA-B-FALL-BACK EXIT
    THEN
    _RUHA-B-DIALOG-COUNT @ 0<
        _RUHA-B-CAPTURE-DIALOG-NATIVE-U @ 0< OR IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-DIALOG-COUNT @ 0=
        _RUHA-B-CAPTURE-DIALOG-NATIVE-U @ 0= <> IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-DIALOG-COUNT @ UDLSN-DESCRIPTOR-SIZE _RUHA-UMUL?
        0= IF DROP RUHA-S-INVALID EXIT THEN
        _RUHA-B-CAPTURE-DIALOG-DESCRIPTOR-U !
    _RUHA-B-CAPTURE-DIALOG-DESCRIPTOR-U @
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-DIALOG-DESCRIPTOR-BANK-U @
            _RUHA-B-DIALOG-DESCRIPTORS-U @ - U> IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-CAPTURE-DIALOG-NATIVE-U @
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-DIALOG-NATIVE-BANK-U @
            _RUHA-B-DIALOG-NATIVE-U @ - U> IF
        RUHA-S-INVALID EXIT
    THEN

    _RUHA-B-COUNT @ 0=
        _RUHA-B-COLLECTION-COUNT @ 0= AND
        _RUHA-B-DGRAPH-COUNT @ 0= AND
        _RUHA-B-SFIELD-COUNT @ 0= AND
        _RUHA-B-FIELD-COUNT @ 0= AND
        _RUHA-B-DIALOG-COUNT @ 0= AND IF
        -1 _RUHA-B-RECORD @ _RUHA-B-STAGE
        RUHA-S-OK EXIT
    THEN
    _RUHA-B-CAPTURE-MENU-EPOCHS
    _RUHA-B-CAPTURE-MENU-EPOCH @
    _RUHA-B-CAPTURE-MENU-TOPOLOGY-EPOCH @
    _RUHA-B-CAPTURE-RECORD-U @ _RUHA-B-CAPTURE-TEXT-U @
    _RUHA-B-CAPTURE-DESCRIPTOR-U @ _RUHA-B-CAPTURE-NATIVE-U @
    _RUHA-B-CAPTURE-DGRAPH-DESCRIPTOR-U @
    _RUHA-B-CAPTURE-DGRAPH-NATIVE-U @
    _RUHA-B-CAPTURE-SFIELD-DESCRIPTOR-U @
    _RUHA-B-CAPTURE-SFIELD-NATIVE-U @

    _RUHA-B-CAPTURE-FIELD-DESCRIPTOR-U @
    _RUHA-B-CAPTURE-FIELD-NATIVE-U @
    _RUHA-B-CAPTURE-DIALOG-DESCRIPTOR-U @
    _RUHA-B-CAPTURE-DIALOG-NATIVE-U @
        _RUHA-B-APPEND-DOCUMENT
    DUP RUHA-S-OK = IF
        DROP 0 _RUHA-B-RECORD @ _RUHA-B-STAGE RUHA-S-OK
    THEN ;

\ A capture holds the relations it checks for all the families it makes
\ (UTUI-HOLD): between their passes nothing runs but the captures, which
\ run no application code and write only the storage each proves apart
\ from UIDL's.  Every-frame checks, the shadow check's full capture, the
\ full refresh and safe mode check them in every pass.
: _RUHA-B-HOLD?  ( -- flag )  _RUHA-B-FULL @ 0= CHK-EVERY-FRAME? 0= AND ;

: _RUHA-B-CAPTURE-CURRENT  ( -- status )
    \ A live capture always changes whole-document provenance.  Its menu
    \ family may independently retain lineage only after exact normalized
    \ comparison with an authenticated prior menu slice.
    _RUHA-B-EXACT-REUSE @ _RUHA-B-FALL-BACK-REUSE !
    0 _RUHA-B-EXACT-REUSE !
    _RUHA-B-DIRECTORY-U @ RUHA-DOCUMENT-SIZE _RUHA-UADD?
        0= IF DROP RUHA-S-CAPACITY EXIT THEN
    _RUHA-B-ADAPTER @ _RUHA-A.SNAP-DIRECTORY-BANK-U @ U> IF
        RUHA-S-CAPACITY EXIT
    THEN
    _RUHA-B-RECORDS-U @
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-RECORD-BANK-U @ U> IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-TEXT-U @
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-TEXT-BANK-U @ U> IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-DESCRIPTORS-U @
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-DESCRIPTOR-BANK-U @ U> IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-NATIVE-U @
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-NATIVE-BANK-U @ U> IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-DGRAPH-DESCRIPTORS-U @
        _RUHA-B-ADAPTER @
            _RUHA-A.SNAP-DGRAPH-DESCRIPTOR-BANK-U @ U> IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-DGRAPH-NATIVE-U @
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-DGRAPH-NATIVE-BANK-U @ U> IF
        RUHA-S-INVALID EXIT
    THEN

    _RUHA-B-SFIELD-DESCRIPTORS-U @
        _RUHA-B-ADAPTER @
            _RUHA-A.SNAP-SFIELD-DESCRIPTOR-BANK-U @ U> IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-SFIELD-NATIVE-U @
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-SFIELD-NATIVE-BANK-U @ U> IF
        RUHA-S-INVALID EXIT
    THEN

    _RUHA-B-FIELD-DESCRIPTORS-U @
        _RUHA-B-ADAPTER @
            _RUHA-A.SNAP-FIELD-DESCRIPTOR-BANK-U @ U> IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-FIELD-NATIVE-U @
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-FIELD-NATIVE-BANK-U @ U> IF
        RUHA-S-INVALID EXIT
    THEN

    _RUHA-B-DIALOG-DESCRIPTORS-U @
        _RUHA-B-ADAPTER @
            _RUHA-A.SNAP-DIALOG-DESCRIPTOR-BANK-U @ U> IF
        RUHA-S-INVALID EXIT
    THEN
    _RUHA-B-DIALOG-NATIVE-U @
        _RUHA-B-ADAPTER @ _RUHA-A.SNAP-DIALOG-NATIVE-BANK-U @ U> IF
        RUHA-S-INVALID EXIT
    THEN

    \ All enabled generic captures observe the exact document UCTX
    \ synchronously.  None publishes; the directory is appended only after
    \ every family has completed and its returned extents are proven.
    _RUHA-B-RECORD @ _RUHA-R.UCTX @ ASHELL-CTX-SWITCH
    _RUHA-B-HOLD? IF ['] _RUHA-B-CAPTURE-FAMILIES UTUI-HOLD EXIT THEN
    _RUHA-B-CAPTURE-FAMILIES ;

: _RUHA-B-CAPTURE-RECORD ( record -- status )
    _RUHA-B-RECORD !
    _RUHA-B-RECORD @ _RUHA-B-ADAPTER @ _RUHA-RECORD-VISIBLE? 0= IF
        RUHA-S-OK EXIT
    THEN
    \ A clean EMPTY bit was authenticated by an earlier capture and remains
    \ authoritative until lifecycle invalidation marks the record dirty.
    \ Such a document contributes nothing even when foreground paint covers
    \ its geometry; a dirty record must still take the conservative path.
    _RUHA-B-RECORD @ _RUHA-RECORD-DIRTY? 0= IF
        _RUHA-B-RECORD @ _RUHA-RECORD-EMPTY? IF
            \ The shadow check's full capture looks again, wherever the
            \ document lies: a document still empty stages empty there too.
            _RUHA-B-FULL @ IF _RUHA-B-CAPTURE-CURRENT EXIT THEN
            -1 _RUHA-B-RECORD @ _RUHA-B-STAGE RUHA-S-OK EXIT
        THEN
    THEN
    \ Foreground paint is later than the complete child semantic draw.  Fall
    \ back the whole intersected document rather than publish a control or
    \ instrument below pixels that also need residual ownership.  Do not
    \ stage the record: leaving it dirty forces a fresh semantic capture
    \ after exposure instead of reusing this directory-only zero-slice state.
    \ An overlay slot's document is itself foreground paint, the final writer
    \ of its own cells, so it is the one document the test passes over.
    \ When all the paint over a document is its own overlay, the prompt it
    \ drew or the dialog it shows, the document keeps every root, those the
    \ overlay meets too: the producer puts the overlay in the layer above
    \ them, and the prompt joins its fields or the dialog its dialogs.
    _RUHA-B-RECORD @ _RUHA-R.ROW @
    _RUHA-B-RECORD @ _RUHA-R.COL @
    _RUHA-B-RECORD @ _RUHA-R.HEIGHT @
    _RUHA-B-RECORD @ _RUHA-R.WIDTH @
        SCR-OCCLUSION-RECT? 0= IF DROP RUHA-S-INVALID EXIT THEN
    _RUHA-B-RECORD @ _RUHA-R.SLOT @ AHS-OVERLAY? 0= AND
    IF
        _RUHA-B-RECORD @ _RUHA-B-ADAPTER @ _RUHA-LAYERED? 0= IF
            _RUHA-B-RECORD @ _RUHA-RECORD-DIRTY!
            0 0 0 0 0 0 0 0 0 0 0 0 0 0 _RUHA-B-APPEND-DOCUMENT EXIT
        THEN
    THEN
    _RUHA-B-RECORD @ _RUHA-RECORD-DIRTY? _RUHA-B-FULL @ OR IF
        _RUHA-B-CAPTURE-CURRENT EXIT
    THEN
    _RUHA-B-RECORD @ _RUHA-B-FIND-PRIOR IF
        _RUHA-B-REUSE? IF EXIT THEN DROP
    ELSE
        DROP
    THEN
    _RUHA-B-CAPTURE-CURRENT ;

VARIABLE _RUHA-B-PREFLIGHT-RECORD
VARIABLE _RUHA-B-PREFLIGHT-SLOT
VARIABLE _RUHA-B-PREFLIGHT-CTX

\ Each record names a live slot of this host that is still its own, with
\ its own UCTX, and an owner that names itself.  The proofs that RUHA's
\ banks lie apart from the record's owner and its document's storage were
\ made when it attached, and are made again on each draw only with
\ every-frame checks on (check-mode.f).
: _RUHA-B-PREFLIGHT-RECORD?  ( record -- flag )
    _RUHA-B-PREFLIGHT-RECORD !
    _RUHA-B-PREFLIGHT-RECORD @ _RUHA-R.STATE @ DUP
        _RUHA-RECORD-FREE = IF DROP -1 EXIT THEN
    DUP _RUHA-RECORD-ATTACHED =
    SWAP _RUHA-RECORD-QUIESCED = OR 0= IF 0 EXIT THEN
    _RUHA-B-PREFLIGHT-RECORD @ _RUHA-R.SLOT @ DUP
        _RUHA-B-PREFLIGHT-SLOT !
    _RUHA-B-ADAPTER @ _RUHA-A.HOST @
        _RUHA-HOST-HAS-SLOT? 0= IF 0 EXIT THEN
    _RUHA-B-PREFLIGHT-SLOT @ AHS.ID @
        _RUHA-B-PREFLIGHT-RECORD @ _RUHA-R.SLOT-ID @ <> IF 0 EXIT THEN
    _RUHA-B-PREFLIGHT-SLOT @ _RUHA-OWNER-NAMED? 0= IF 0 EXIT THEN
    CHK-EVERY-FRAME? IF
        _RUHA-B-PREFLIGHT-SLOT @ _RUHA-B-ADAPTER @ _RUHA-LIVE-OWNER?
            _RUHA-BANKS-DAMAGED CHK-NAME 0= IF 0 EXIT THEN
    THEN
    _RUHA-B-PREFLIGHT-SLOT @ AHS.HAS-UIDL @ 0= IF 0 EXIT THEN
    _RUHA-B-PREFLIGHT-SLOT @ AHS.UCTX @ DUP 0= IF DROP 0 EXIT THEN
        _RUHA-B-PREFLIGHT-CTX !
    _RUHA-B-PREFLIGHT-CTX @
        _RUHA-B-PREFLIGHT-RECORD @ _RUHA-R.UCTX @ <> IF 0 EXIT THEN
    _RUHA-B-PREFLIGHT-CTX @ ASHELL-CTX-SWITCH
    ASHELL-ACTIVE-CTX _RUHA-B-PREFLIGHT-CTX @ <> IF 0 EXIT THEN
    CHK-EVERY-FRAME? 0= IF -1 EXIT THEN
    _RUHA-B-ADAPTER @ _RUHA-STORAGE-DISJOINT-CURRENT?
        _RUHA-BANKS-DAMAGED CHK-NAME ;

\ The screen's storage and the current UCTX's were proved apart from RUHA's
\ banks when the banks were lent and the documents attached, and what they
\ allocate later comes from allocators, so a draw proves them again only
\ with every-frame checks on.
: _RUHA-B-PREFLIGHT  ( -- status )
    CHK-EVERY-FRAME? IF
        _RUHA-B-ADAPTER @ _RUHA-SCREEN-STORAGE-DISJOINT?
            _RUHA-BANKS-DAMAGED CHK-NAME 0= IF RUHA-S-INVALID EXIT THEN
        _RUHA-B-ADAPTER @ _RUHA-STORAGE-DISJOINT-CURRENT?
            _RUHA-BANKS-DAMAGED CHK-NAME 0= IF RUHA-S-INVALID EXIT THEN
    THEN
    _RUHA-B-ADAPTER @ _RUHA-A.CAPACITY @ 0 ?DO
        I _RUHA-B-ADAPTER @ _RUHA-RECORD-AT
            _RUHA-B-PREFLIGHT-RECORD? 0= IF
            RUHA-S-INVALID UNLOOP EXIT
        THEN
    LOOP
    RUHA-S-OK ;

: _RUHA-B-PREFLIGHT-GUARDED  ( -- status )
    ['] _RUHA-B-PREFLIGHT CATCH ?DUP IF
        DROP RUHA-S-INVALID
    THEN ;

: _RUHA-B-CAPTURE ( -- status )
    _RUHA-B-CLEAR-STAGED
    RUHA-S-OK _RUHA-B-STATUS !
    _RUHA-B-ADAPTER @ _RUHA-A.CAPACITY @ 0 ?DO
        I _RUHA-B-ADAPTER @ _RUHA-RECORD-AT _RUHA-B-CAPTURE-RECORD
        DUP RUHA-S-OK <> IF _RUHA-B-STATUS ! LEAVE THEN DROP
    LOOP
    _RUHA-B-STATUS @ ;

\ CONTENT-EPOCH is a provenance certificate, not a hash.  Every nonempty
\ emitted document must have reached the candidate through validated prior
\ whole-document slice reuse; the complete directory and every aggregate byte
\ total must also be identical.  UMSN generation cells are deliberately
\ excluded because reuse rebases only those cells to the new generation.
: _RUHA-B-CONTENT-UNCHANGED?  ( -- flag )
    _RUHA-B-EXACT-REUSE @ 0= IF 0 EXIT THEN
    _RUHA-B-HAS-PRIOR @ 0= IF 0 EXIT THEN
    _RUHA-B-PRIOR-CONTENT-EPOCH @ 0= IF 0 EXIT THEN
    _RUHA-B-DOCUMENTS @ _RUHA-B-PRIOR-DOCUMENTS @ <> IF 0 EXIT THEN
    _RUHA-B-DIRECTORY-U @ _RUHA-B-PRIOR-DIRECTORY-U @ <> IF 0 EXIT THEN
    _RUHA-B-RECORDS-U @ _RUHA-B-PRIOR-RECORDS-U @ <> IF 0 EXIT THEN
    _RUHA-B-TEXT-U @ _RUHA-B-PRIOR-TEXT-U @ <> IF 0 EXIT THEN
    _RUHA-B-DESCRIPTORS-U @ _RUHA-B-PRIOR-DESCRIPTORS-U @ <> IF
        0 EXIT
    THEN
    _RUHA-B-NATIVE-U @ _RUHA-B-PRIOR-NATIVE-U @ <> IF 0 EXIT THEN
    _RUHA-B-DGRAPH-DESCRIPTORS-U @
        _RUHA-B-PRIOR-DGRAPH-DESCRIPTORS-U @ <> IF 0 EXIT THEN
    _RUHA-B-DGRAPH-NATIVE-U @
        _RUHA-B-PRIOR-DGRAPH-NATIVE-U @ <> IF 0 EXIT THEN
    _RUHA-B-SFIELD-DESCRIPTORS-U @
        _RUHA-B-PRIOR-SFIELD-DESCRIPTORS-U @ <> IF 0 EXIT THEN
    _RUHA-B-SFIELD-NATIVE-U @
        _RUHA-B-PRIOR-SFIELD-NATIVE-U @ <> IF 0 EXIT THEN

    _RUHA-B-FIELD-DESCRIPTORS-U @
        _RUHA-B-PRIOR-FIELD-DESCRIPTORS-U @ <> IF 0 EXIT THEN
    _RUHA-B-FIELD-NATIVE-U @
        _RUHA-B-PRIOR-FIELD-NATIVE-U @ <> IF 0 EXIT THEN
    _RUHA-B-DIALOG-DESCRIPTORS-U @
        _RUHA-B-PRIOR-DIALOG-DESCRIPTORS-U @ <> IF 0 EXIT THEN
    _RUHA-B-DIALOG-NATIVE-U @
        _RUHA-B-PRIOR-DIALOG-NATIVE-U @ <> IF 0 EXIT THEN
    _RUHA-B-DIRECTORY-A @ _RUHA-B-DIRECTORY-U @
    _RUHA-B-PRIOR-DIRECTORY-A @ _RUHA-B-PRIOR-DIRECTORY-U @
        COMPARE 0= ;

: _RUHA-B-FINALIZE-CONTENT  ( -- )
    _RUHA-B-CONTENT-UNCHANGED? IF
        _RUHA-B-PRIOR-CONTENT-EPOCH @
    ELSE
        _RUHA-B-GENERATION @
    THEN _RUHA-B-CONTENT-EPOCH ! ;

: _RUHA-B-RESTORE ( -- )
    _RUHA-B-ORIGINAL-CTX @ ASHELL-CTX-SWITCH ;

: _RUHA-B-PUBLISH ( -- snapshot status )
    _RUHA-B-BANK @ _RUHA-B-ADAPTER @ _RUHA-SNAPSHOT-AT
    DUP RUHA-SNAPSHOT-SIZE 0 FILL
    _RUHA-B-GENERATION @ OVER _RUHA-S.GENERATION !
    _RUHA-B-DRAW @ OVER _RUHA-S.DRAW-GENERATION !
    _RUHA-B-DIRECTORY-A @ OVER _RUHA-S.DIRECTORY-A !
    _RUHA-B-DIRECTORY-U @ OVER _RUHA-S.DIRECTORY-U !
    _RUHA-B-RECORDS-A @ OVER _RUHA-S.RECORDS-A !
    _RUHA-B-RECORDS-U @ OVER _RUHA-S.RECORDS-U !
    _RUHA-B-TEXT-A @ OVER _RUHA-S.TEXT-A !
    _RUHA-B-TEXT-U @ OVER _RUHA-S.TEXT-U !
    _RUHA-B-DESCRIPTORS-A @ OVER _RUHA-S.COLLECTION-DESCRIPTORS-A !
    _RUHA-B-DESCRIPTORS-U @ OVER _RUHA-S.COLLECTION-DESCRIPTORS-U !
    _RUHA-B-NATIVE-A @ OVER _RUHA-S.COLLECTION-NATIVE-A !
    _RUHA-B-NATIVE-U @ OVER _RUHA-S.COLLECTION-NATIVE-U !
    _RUHA-B-DGRAPH-DESCRIPTORS-A @ OVER _RUHA-S.DGRAPH-DESCRIPTORS-A !
    _RUHA-B-DGRAPH-DESCRIPTORS-U @ OVER _RUHA-S.DGRAPH-DESCRIPTORS-U !
    _RUHA-B-DGRAPH-NATIVE-A @ OVER _RUHA-S.DGRAPH-NATIVE-A !
    _RUHA-B-DGRAPH-NATIVE-U @ OVER _RUHA-S.DGRAPH-NATIVE-U !
    _RUHA-B-SFIELD-DESCRIPTORS-A @ OVER _RUHA-S.SFIELD-DESCRIPTORS-A !
    _RUHA-B-SFIELD-DESCRIPTORS-U @ OVER _RUHA-S.SFIELD-DESCRIPTORS-U !
    _RUHA-B-SFIELD-NATIVE-A @ OVER _RUHA-S.SFIELD-NATIVE-A !
    _RUHA-B-SFIELD-NATIVE-U @ OVER _RUHA-S.SFIELD-NATIVE-U !

    _RUHA-B-FIELD-DESCRIPTORS-A @ OVER _RUHA-S.FIELD-DESCRIPTORS-A !
    _RUHA-B-FIELD-DESCRIPTORS-U @ OVER _RUHA-S.FIELD-DESCRIPTORS-U !
    _RUHA-B-FIELD-NATIVE-A @ OVER _RUHA-S.FIELD-NATIVE-A !
    _RUHA-B-FIELD-NATIVE-U @ OVER _RUHA-S.FIELD-NATIVE-U !
    _RUHA-B-DIALOG-DESCRIPTORS-A @ OVER _RUHA-S.DIALOG-DESCRIPTORS-A !
    _RUHA-B-DIALOG-DESCRIPTORS-U @ OVER _RUHA-S.DIALOG-DESCRIPTORS-U !
    _RUHA-B-DIALOG-NATIVE-A @ OVER _RUHA-S.DIALOG-NATIVE-A !
    _RUHA-B-DIALOG-NATIVE-U @ OVER _RUHA-S.DIALOG-NATIVE-U !
    _RUHA-B-DOCUMENTS @ OVER _RUHA-S.DOCUMENT-COUNT !
    _RUHA-B-CONTENT-EPOCH @ OVER _RUHA-S.CONTENT-EPOCH !
    _RUHA-B-GENERATION @ _RUHA-B-ADAPTER @ _RUHA-A.GENERATION !
    RUHA-S-OK _RUHA-B-ADAPTER @ _RUHA-A.LAST-STATUS !
    _RUHA-B-FINALIZE-STAGED
    _RUHA-B-BANK @ _RUHA-B-ADAPTER @ _RUHA-A.ACTIVE-BANK !
    RUHA-S-OK ;

\ Start a capture into the inactive bank: no document yet, and the
\ prior's content epoch kept until a live capture changes provenance.
: _RUHA-B-START  ( -- )
    0 _RUHA-B-DIRECTORY-U ! 0 _RUHA-B-RECORDS-U !
    0 _RUHA-B-TEXT-U ! 0 _RUHA-B-DESCRIPTORS-U !
    0 _RUHA-B-NATIVE-U !
    0 _RUHA-B-DGRAPH-DESCRIPTORS-U !
    0 _RUHA-B-DGRAPH-NATIVE-U !
    0 _RUHA-B-SFIELD-DESCRIPTORS-U !
    0 _RUHA-B-SFIELD-NATIVE-U !
    0 _RUHA-B-FIELD-DESCRIPTORS-U !
    0 _RUHA-B-FIELD-NATIVE-U !
    0 _RUHA-B-DIALOG-DESCRIPTORS-U !
    0 _RUHA-B-DIALOG-NATIVE-U ! 0 _RUHA-B-DOCUMENTS !
    _RUHA-B-GENERATION @ _RUHA-B-CONTENT-EPOCH !
    0 _RUHA-B-EXACT-REUSE !
    _RUHA-B-HAS-PRIOR @ IF
        _RUHA-B-PRIOR-CONTENT-EPOCH @ _RUHA-B-CONTENT-EPOCH !
        -1 _RUHA-B-EXACT-REUSE !
    THEN ;

\ Capture every record into the inactive bank, then return to the caller's
\ context.
: _RUHA-B-CAPTURE-ALL  ( -- )
    ['] _RUHA-B-CAPTURE CATCH DUP IF
        DROP RUHA-S-INVALID _RUHA-B-STATUS !
    ELSE
        DROP _RUHA-B-STATUS !
    THEN
    ['] _RUHA-B-RESTORE CATCH IF
        RUHA-S-INVALID _RUHA-B-STATUS !
    THEN ;

\ Point the capture at bank _RUHA-B-BANK's spans.
: _RUHA-B-BANK-SPANS  ( -- )
    _RUHA-B-BANK @ _RUHA-B-ADAPTER @ _RUHA-SNAPSHOT-DIRECTORY-A
        _RUHA-B-DIRECTORY-A !
    _RUHA-B-BANK @ _RUHA-B-ADAPTER @ _RUHA-SNAPSHOT-RECORD-A
        _RUHA-B-RECORDS-A !
    _RUHA-B-BANK @ _RUHA-B-ADAPTER @ _RUHA-SNAPSHOT-TEXT-A
        _RUHA-B-TEXT-A !
    _RUHA-B-BANK @ _RUHA-B-ADAPTER @ _RUHA-SNAPSHOT-DESCRIPTOR-A
        _RUHA-B-DESCRIPTORS-A !
    _RUHA-B-BANK @ _RUHA-B-ADAPTER @ _RUHA-SNAPSHOT-NATIVE-A
        _RUHA-B-NATIVE-A !
    _RUHA-B-BANK @ _RUHA-B-ADAPTER @
        _RUHA-SNAPSHOT-DGRAPH-DESCRIPTOR-A
        _RUHA-B-DGRAPH-DESCRIPTORS-A !
    _RUHA-B-BANK @ _RUHA-B-ADAPTER @ _RUHA-SNAPSHOT-DGRAPH-NATIVE-A
        _RUHA-B-DGRAPH-NATIVE-A !
    _RUHA-B-BANK @ _RUHA-B-ADAPTER @
        _RUHA-SNAPSHOT-SFIELD-DESCRIPTOR-A
        _RUHA-B-SFIELD-DESCRIPTORS-A !
    _RUHA-B-BANK @ _RUHA-B-ADAPTER @ _RUHA-SNAPSHOT-SFIELD-NATIVE-A
        _RUHA-B-SFIELD-NATIVE-A !

    _RUHA-B-BANK @ _RUHA-B-ADAPTER @
        _RUHA-SNAPSHOT-FIELD-DESCRIPTOR-A
        _RUHA-B-FIELD-DESCRIPTORS-A !
    _RUHA-B-BANK @ _RUHA-B-ADAPTER @ _RUHA-SNAPSHOT-FIELD-NATIVE-A
        _RUHA-B-FIELD-NATIVE-A !
    _RUHA-B-BANK @ _RUHA-B-ADAPTER @
        _RUHA-SNAPSHOT-DIALOG-DESCRIPTOR-A
        _RUHA-B-DIALOG-DESCRIPTORS-A !
    _RUHA-B-BANK @ _RUHA-B-ADAPTER @ _RUHA-SNAPSHOT-DIALOG-NATIVE-A
        _RUHA-B-DIALOG-NATIVE-A !
    ;

\ ---------------------------------------------------------------------
\ Growth
\ ---------------------------------------------------------------------
\
\ Each family answers CAPACITY only when the spans RUHA lends it are too
\ small.  A build that ran short in the families of _RUHA-B-SHORT takes a
\ block whose growable spans of those families are twice the size, copies
\ the snapshot on screen and the records' copy into it, and gives the old
\ block back.  The snapshot on screen then names its spans where they lie
\ now; nothing else holds them, since the producer copies a snapshot when
\ it takes one.  The new block is proved apart from the screen's storage
\ and each attached document's, as the banks were when they were lent; a
\ proof that fails is a handover anomaly (check-mode.f), and the old block
\ stays.  The bank being built is then built again from the start.

CREATE _RUHA-G-OLD-BASE _RUHA-G-BANKED CELLS ALLOT
VARIABLE _RUHA-G-OLD-SAVE
VARIABLE _RUHA-G-NEW
VARIABLE _RUHA-G-NEW-U
VARIABLE _RUHA-G-ACTIVE
VARIABLE _RUHA-G-SNAP
VARIABLE _RUHA-DIAG-GROWTHS
0 _RUHA-DIAG-GROWTHS !

: _RUHA-G-DOUBLE?  ( span -- flag )
    DUP _RUHA-G-CAP@ 2 _RUHA-UMUL? 0= IF 2DROP 0 EXIT THEN
    SWAP _RUHA-G-CAP! -1 ;

\ Double the growable spans of the families in SHORT.
: _RUHA-G-WIDEN?  ( short -- flag )
    DUP RUHA-F-MENUS AND IF
        1 _RUHA-G-DOUBLE? 2 _RUHA-G-DOUBLE? AND 0= IF DROP 0 EXIT THEN
    THEN
    DUP RUHA-F-COLLECTIONS AND IF
        3 _RUHA-G-DOUBLE? 4 _RUHA-G-DOUBLE? AND 0= IF DROP 0 EXIT THEN
    THEN
    DUP RUHA-F-DATA-GRAPHICS AND IF
        5 _RUHA-G-DOUBLE? 6 _RUHA-G-DOUBLE? AND 0= IF DROP 0 EXIT THEN
    THEN
    DUP RUHA-F-STATUS-FIELDS AND IF
        7 _RUHA-G-DOUBLE? 8 _RUHA-G-DOUBLE? AND 0= IF DROP 0 EXIT THEN
    THEN
    DUP RUHA-F-FIELDS AND IF
        9 _RUHA-G-DOUBLE? 10 _RUHA-G-DOUBLE? AND 0= IF DROP 0 EXIT THEN
    THEN
    RUHA-F-DIALOGS AND IF 12 _RUHA-G-DOUBLE? EXIT THEN -1 ;

\ Where each bank span and the records' copy lie in the block replaced.
: _RUHA-G-KEEP-OLD  ( adapter -- )
    _RUHA-G-BANKED 0 ?DO
        I OVER _RUHA-G-FIELD @ I CELLS _RUHA-G-OLD-BASE + !
    LOOP _RUHA-A.SAVE-A @ _RUHA-G-OLD-SAVE ! ;

\ Every attached document's storage lies apart from RUHA's, each proved in
\ its own UCTX.
: _RUHA-G-DOCUMENTS-APART?  ( -- flag )
    _RUHA-B-ADAPTER @ _RUHA-A.CAPACITY @ 0 ?DO
        I _RUHA-B-ADAPTER @ _RUHA-RECORD-AT
        DUP _RUHA-R.STATE @ _RUHA-RECORD-FREE = IF DROP ELSE
            _RUHA-R.UCTX @ ?DUP IF
                ASHELL-CTX-SWITCH
                _RUHA-B-ADAPTER @ _RUHA-STORAGE-DISJOINT-CURRENT?
                0= IF 0 UNLOOP EXIT THEN
            THEN
        THEN
    LOOP -1 ;

\ The new block lies apart from the screen's storage and every attached
\ document's; the caller's context is put back after.
: _RUHA-G-PROVED?  ( -- flag )
    _RUHA-B-ADAPTER @ _RUHA-SCREEN-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    ['] _RUHA-G-DOCUMENTS-APART? CATCH IF 0 THEN
    ['] _RUHA-B-RESTORE CATCH IF DROP 0 THEN ;

\ Copy the snapshot on screen into the new block, which it then names; the
\ other bank's snapshot names nothing until it is published.
: _RUHA-G-MOVE-ACTIVE  ( -- )
    _RUHA-B-ADAPTER @ _RUHA-A.ACTIVE-BANK @ DUP _RUHA-G-ACTIVE !
    DUP 0< IF DROP EXIT THEN
    0= IF 1 ELSE 0 THEN _RUHA-B-ADAPTER @ _RUHA-SNAPSHOT-AT
        RUHA-SNAPSHOT-SIZE 0 FILL
    _RUHA-G-ACTIVE @ _RUHA-B-ADAPTER @ _RUHA-SNAPSHOT-AT _RUHA-G-SNAP !
    _RUHA-G-BANKED 0 ?DO
        I CELLS _RUHA-G-OLD-BASE + @
            I CELLS _RUHA-G-OLD + @ _RUHA-G-ACTIVE @ * +
        I _RUHA-B-ADAPTER @ _RUHA-G-FIELD @
            I _RUHA-G-CAP@ _RUHA-G-ACTIVE @ * +
        DUP I _RUHA-G-SNAP @ _RUHA-G-SNAP-FIELD !
        I CELLS _RUHA-G-OLD + @ MOVE
    LOOP ;

: _RUHA-G-GROW?  ( -- flag )
    _RUHA-B-ADAPTER @ _RUHA-A.MEMORY @ 0= IF 0 EXIT THEN
    _RUHA-B-ADAPTER @ _RUHA-G-READ
    _RUHA-G-CAP _RUHA-G-OLD _RUHA-G-SPANS CELLS MOVE
    _RUHA-B-SHORT @ _RUHA-G-WIDEN? 0= IF 0 EXIT THEN
    _RUHA-B-ADAPTER @ _RUHA-A.CAPACITY @ _RUHA-G-DERIVE 0= IF 0 EXIT THEN
    _RUHA-B-ADAPTER @ _RUHA-A.RECORDS-U @ _RUHA-G-BYTES
        DUP _RUHA-G-NEW-U ! DUP 0= IF EXIT THEN
    _RUHA-B-ADAPTER @ _RUHA-A.MEMORY @ MSRC-ALLOC DUP _RUHA-G-NEW !
        0= IF 0 EXIT THEN
    _RUHA-B-ADAPTER @ _RUHA-G-KEEP-OLD
    _RUHA-G-NEW @ _RUHA-B-ADAPTER @ _RUHA-G-PLACE
    _RUHA-G-PROVED? _RUHA-BANKS-DAMAGED CHK-HANDOVER 0= IF
        _RUHA-G-OLD _RUHA-G-CAP _RUHA-G-SPANS CELLS MOVE
        _RUHA-B-ADAPTER @ _RUHA-A.BLOCK-A @ _RUHA-B-ADAPTER @ _RUHA-G-PLACE
        _RUHA-G-NEW @ _RUHA-G-NEW-U @ _RUHA-B-ADAPTER @ _RUHA-A.MEMORY @
            MSRC-FREE
        0 EXIT
    THEN
    _RUHA-G-MOVE-ACTIVE
    _RUHA-G-OLD-SAVE @ _RUHA-B-ADAPTER @ _RUHA-A.SAVE-A @
        _RUHA-B-ADAPTER @ _RUHA-A.RECORDS-U @ MOVE
    _RUHA-B-ADAPTER @ DUP _RUHA-A.BLOCK-A @ SWAP _RUHA-A.BLOCK-U @
        _RUHA-B-ADAPTER @ _RUHA-A.MEMORY @ MSRC-FREE
    _RUHA-G-NEW @ _RUHA-B-ADAPTER @ _RUHA-A.BLOCK-A !
    _RUHA-G-NEW-U @ _RUHA-B-ADAPTER @ _RUHA-A.BLOCK-U !
    1 _RUHA-DIAG-GROWTHS +!
    -1 ;

\ Build the bank _RUHA-B-BANK-SPANS points at: start it and capture every
\ record.  A build that ran short of room is made again, from the records
\ as they were before it, once the block has grown; when the memory source
\ refuses, the build stands, each document that did not fit fallen back.
: _RUHA-B-SAVE-RECORDS  ( -- )
    _RUHA-B-ADAPTER @ DUP _RUHA-A.RECORDS-A @ OVER _RUHA-A.SAVE-A @
    ROT _RUHA-A.RECORDS-U @ MOVE ;
: _RUHA-B-RESTORE-RECORDS  ( -- )
    _RUHA-B-ADAPTER @ DUP _RUHA-A.SAVE-A @ OVER _RUHA-A.RECORDS-A @
    ROT _RUHA-A.RECORDS-U @ MOVE ;
: _RUHA-B-BUILD  ( -- )
    _RUHA-B-SAVE-RECORDS
    BEGIN
        0 _RUHA-B-SHORT !
        _RUHA-B-START _RUHA-B-CAPTURE-ALL
        _RUHA-B-SHORT @ IF _RUHA-G-GROW? ELSE 0 THEN
    WHILE
        _RUHA-B-RESTORE-RECORDS _RUHA-B-LOAD-PRIOR _RUHA-B-BANK-SPANS
    REPEAT ;

\ ---------------------------------------------------------------------
\ Shadow check (frame-shadow.f)
\ ---------------------------------------------------------------------
\
\ While the shadow check is on, a draw's snapshot is captured twice into the
\ inactive bank.  The full capture comes first and captures every visible
\ document live; its result goes to a scratch block, and the records' flags,
\ which a capture stages and may mark dirty, are put back.  The ordinary
\ capture then runs as it always does, and is the one published.  Its
\ status, document count, every span's length and every span's bytes must
\ equal the full capture's.

13 CONSTANT _RUHA-SH-SPAN-COUNT

\ The capture's INDEX-th output span.
: _RUHA-SH-SPAN  ( index -- a u )
    DUP 0 = IF DROP _RUHA-B-DIRECTORY-A @ _RUHA-B-DIRECTORY-U @ EXIT THEN
    DUP 1 = IF DROP _RUHA-B-RECORDS-A @ _RUHA-B-RECORDS-U @ EXIT THEN
    DUP 2 = IF DROP _RUHA-B-TEXT-A @ _RUHA-B-TEXT-U @ EXIT THEN
    DUP 3 = IF DROP _RUHA-B-DESCRIPTORS-A @ _RUHA-B-DESCRIPTORS-U @ EXIT THEN
    DUP 4 = IF DROP _RUHA-B-NATIVE-A @ _RUHA-B-NATIVE-U @ EXIT THEN
    DUP 5 = IF
        DROP _RUHA-B-DGRAPH-DESCRIPTORS-A @ _RUHA-B-DGRAPH-DESCRIPTORS-U @ EXIT
    THEN
    DUP 6 = IF DROP _RUHA-B-DGRAPH-NATIVE-A @ _RUHA-B-DGRAPH-NATIVE-U @ EXIT THEN
    DUP 7 = IF
        DROP _RUHA-B-SFIELD-DESCRIPTORS-A @ _RUHA-B-SFIELD-DESCRIPTORS-U @ EXIT
    THEN
    DUP 8 = IF DROP _RUHA-B-SFIELD-NATIVE-A @ _RUHA-B-SFIELD-NATIVE-U @ EXIT THEN
    DUP 9 = IF
        DROP _RUHA-B-FIELD-DESCRIPTORS-A @ _RUHA-B-FIELD-DESCRIPTORS-U @ EXIT
    THEN
    DUP 10 = IF DROP _RUHA-B-FIELD-NATIVE-A @ _RUHA-B-FIELD-NATIVE-U @ EXIT THEN
    DUP 11 = IF
        DROP _RUHA-B-DIALOG-DESCRIPTORS-A @ _RUHA-B-DIALOG-DESCRIPTORS-U @ EXIT
    THEN
    DROP _RUHA-B-DIALOG-NATIVE-A @ _RUHA-B-DIALOG-NATIVE-U @ ;

\ A result's header: its status, its document count and each span's length.
_RUHA-SH-SPAN-COUNT 2 + CELLS CONSTANT _RUHA-SH-HEADER-BYTES

VARIABLE _RUHA-SH-KEPT
VARIABLE _RUHA-SH-RESULT-A
VARIABLE _RUHA-SH-RESULT-U
VARIABLE _RUHA-SH-FLAGS-A
VARIABLE _RUHA-SH-FLAGS-U
VARIABLE _RUHA-SH-HEADER-A
VARIABLE _RUHA-SH-HEADER-U
VARIABLE _RUHA-SH-AT
VARIABLE _RUHA-SH-SPAN-U

: _RUHA-SH-HEADER!  ( dest -- )
    _RUHA-B-STATUS @ OVER !
    _RUHA-B-DOCUMENTS @ OVER CELL+ !
    _RUHA-SH-SPAN-COUNT 0 ?DO
        I _RUHA-SH-SPAN NIP OVER I 2 + CELLS + !
    LOOP DROP ;

: _RUHA-SH-RESULT-BYTES  ( -- u )
    _RUHA-SH-HEADER-BYTES
    _RUHA-SH-SPAN-COUNT 0 ?DO I _RUHA-SH-SPAN NIP + LOOP ;

\ Keep the full capture's result: its header, then every span.
: _RUHA-SH-KEEP?  ( -- flag )
    _RUHA-SH-RESULT-BYTES _RUHA-SH-RESULT-A _RUHA-SH-RESULT-U FSHD-GROW
    DUP 0= IF EXIT THEN
    DUP _RUHA-SH-HEADER!
    _RUHA-SH-HEADER-BYTES + _RUHA-SH-AT !
    _RUHA-SH-SPAN-COUNT 0 ?DO
        I _RUHA-SH-SPAN DUP _RUHA-SH-SPAN-U !
        _RUHA-SH-AT @ SWAP MOVE
        _RUHA-SH-SPAN-U @ _RUHA-SH-AT +!
    LOOP -1 ;

: _RUHA-SH-SAVE-FLAGS?  ( -- flag )
    _RUHA-B-ADAPTER @ _RUHA-A.CAPACITY @ CELLS
        _RUHA-SH-FLAGS-A _RUHA-SH-FLAGS-U FSHD-GROW
    0= IF 0 EXIT THEN
    _RUHA-B-ADAPTER @ _RUHA-A.CAPACITY @ 0 ?DO
        I _RUHA-B-ADAPTER @ _RUHA-RECORD-AT _RUHA-R.FLAGS @
        _RUHA-SH-FLAGS-A @ I CELLS + !
    LOOP -1 ;

: _RUHA-SH-RESTORE-FLAGS  ( -- )
    _RUHA-B-ADAPTER @ _RUHA-A.CAPACITY @ 0 ?DO
        _RUHA-SH-FLAGS-A @ I CELLS + @
        I _RUHA-B-ADAPTER @ _RUHA-RECORD-AT _RUHA-R.FLAGS !
    LOOP ;

: _RUHA-SH-FULL  ( -- )
    0 _RUHA-SH-KEPT !
    _RUHA-SH-SAVE-FLAGS? 0= IF FSHD-SKIP EXIT THEN
    -1 _RUHA-B-FULL !
    _RUHA-B-BUILD
    0 _RUHA-B-FULL !
    _RUHA-SH-KEEP? IF -1 _RUHA-SH-KEPT ! ELSE FSHD-SKIP THEN
    _RUHA-SH-RESTORE-FLAGS ;

\ Compare the ordinary capture with the full one: the headers as item 0,
\ then, when they agree, each span as item 1 to 13.
: _RUHA-SH-CHECK  ( -- )
    _RUHA-SH-KEPT @ 0= IF EXIT THEN
    _RUHA-B-DRAW @ FSHD-DRAW !
    _RUHA-SH-HEADER-BYTES _RUHA-SH-HEADER-A _RUHA-SH-HEADER-U FSHD-GROW
    DUP 0= IF DROP FSHD-SKIP EXIT THEN
    DUP _RUHA-SH-HEADER!
    _RUHA-SH-HEADER-BYTES _RUHA-SH-RESULT-A @ _RUHA-SH-HEADER-BYTES
    0 FSHD-STAGE-SNAPSHOT FSHD-SAME? 0= IF EXIT THEN
    _RUHA-SH-RESULT-A @ _RUHA-SH-HEADER-BYTES + _RUHA-SH-AT !
    _RUHA-SH-SPAN-COUNT 0 ?DO
        I _RUHA-SH-SPAN DUP _RUHA-SH-SPAN-U !
        _RUHA-SH-AT @ _RUHA-SH-SPAN-U @
        I 1+ FSHD-STAGE-SNAPSHOT FSHD-SAME? DROP
        _RUHA-SH-SPAN-U @ _RUHA-SH-AT +!
    LOOP ;

: RUHA-SNAPSHOT-FOR@ ( draw-generation adapter -- snapshot status )
    _RUHA-B-ADAPTER ! _RUHA-B-DRAW !
    _RUHA-B-ADAPTER @ RUHA-VALID? 0= IF 0 RUHA-S-INVALID EXIT THEN
    _RUHA-B-DRAW @ 0= IF 0 RUHA-S-INVALID EXIT THEN
    \ Prove every caller span against every attached UCTX before mutating
    \ LAST-DRAW, LAST-STATUS, lifecycle records, or an inactive payload bank.
    ASHELL-ACTIVE-CTX _RUHA-B-ORIGINAL-CTX !
    _RUHA-B-PREFLIGHT-GUARDED _RUHA-B-STATUS !
    ['] _RUHA-B-RESTORE CATCH IF
        RUHA-S-INVALID _RUHA-B-STATUS !
    THEN
    _RUHA-B-STATUS @ RUHA-S-OK <> IF
        0 _RUHA-B-STATUS @ EXIT
    THEN
    _RUHA-B-DRAW @ _RUHA-B-ADAPTER @ _RUHA-A.LAST-DRAW @ = IF
        _RUHA-B-ADAPTER @ _RUHA-A.LAST-STATUS @ DUP RUHA-S-OK <> IF
            0 SWAP EXIT
        THEN DROP
        _RUHA-B-ADAPTER @ _RUHA-A.ACTIVE-BANK @ DUP 0< IF
            DROP 0 RUHA-S-STALE EXIT
        THEN
        _RUHA-B-ADAPTER @ _RUHA-SNAPSHOT-AT
        DUP _RUHA-S.DRAW-GENERATION @ _RUHA-B-DRAW @ <> IF
            DROP 0 RUHA-S-STALE EXIT
        THEN
        DUP _RUHA-S.GENERATION @
            _RUHA-B-ADAPTER @ _RUHA-A.GENERATION @ <> IF
            DROP 0 RUHA-S-STALE EXIT
        THEN
        DUP RUHA-SNAPSHOT-CONTENT-EPOCH@ 0= IF
            DROP 0 RUHA-S-STALE EXIT
        THEN
        RUHA-S-OK EXIT
    THEN
    _RUHA-B-DRAW @ _RUHA-B-ADAPTER @ _RUHA-A.LAST-DRAW !
    _RUHA-B-LOAD-PRIOR
    RUHA-S-INVALID _RUHA-B-ADAPTER @ _RUHA-A.LAST-STATUS !
    _RUHA-B-ADAPTER @ _RUHA-A.ACTIVE-BANK @ 0= IF 1 ELSE 0 THEN
        _RUHA-B-BANK !
    _RUHA-B-ADAPTER @ _RUHA-NEXT-GENERATION DUP 0= IF
        DROP RUHA-S-UNAVAILABLE
        DUP _RUHA-B-ADAPTER @ _RUHA-A.LAST-STATUS !
        0 SWAP EXIT
    THEN _RUHA-B-GENERATION !
    _RUHA-B-BANK-SPANS
    \ Safe mode (check-mode.f) captures every document afresh, as the
    \ shadow check's full capture does, so there is no reuse to compare.
    CHK-SAFE? 0= FSHD? AND IF _RUHA-SH-FULL THEN
    CHK-SAFE? _RUHA-B-FULL !
    _RUHA-B-BUILD
    0 _RUHA-B-FULL !
    CHK-SAFE? 0= FSHD? AND IF _RUHA-SH-CHECK THEN
    _RUHA-B-STATUS @ RUHA-S-OK <> IF
        _RUHA-B-CLEAR-STAGED
        _RUHA-B-STATUS @ DUP _RUHA-B-ADAPTER @ _RUHA-A.LAST-STATUS !
        0 SWAP EXIT
    THEN
    _RUHA-B-DOCUMENTS @ 0= IF
        _RUHA-B-CLEAR-STAGED
        RUHA-S-UNAVAILABLE DUP _RUHA-B-ADAPTER @ _RUHA-A.LAST-STATUS !
        0 SWAP EXIT
    THEN
    _RUHA-B-FINALIZE-CONTENT
    _RUHA-B-PUBLISH ;

\ Bind every provenance query and all caller-bank validation to one selected
\ screen and completed draw.  The screen authority guard remains held across
\ the synchronous aggregate capture; recursive SCR queries are permitted,
\ but capture callbacks may not yield or switch screens.
' RUHA-SNAPSHOT-FOR@ CONSTANT _ruha-snapshot-for-body-xt

: _RUHA-SNAPSHOT-FOR-IN-DRAW
  ( requested-draw adapter actual-draw -- snapshot status )
    >R
    OVER R@ <> IF
        2DROP R> DROP 0 RUHA-S-STALE EXIT
    THEN
    R> DROP _ruha-snapshot-for-body-xt EXECUTE ;

: RUHA-SNAPSHOT-FOR@  ( draw-generation adapter -- snapshot status )
    ['] _RUHA-SNAPSHOT-FOR-IN-DRAW _SCR-WITH-DRAW-AUTHORITY ;

\ RUHA-SNAPSHOT-IDENTITY@
\   ( draw-generation adapter -- generation content-epoch documents status )
\ Report the identity of the snapshot RUHA-SNAPSHOT-FOR@ holds for this
\ completed draw without capturing, proving caller storage, or borrowing its
\ payload.  OK only when the last aggregate is for exactly this draw, was
\ published, and no lifecycle edge has closed the borrow gate since.  A
\ caller that reads the payload must still use RUHA-SNAPSHOT-FOR@, which
\ re-proves every caller span before returning it; every capture remains
\ behind that full proof.
VARIABLE _RUHA-ID-ADAPTER
VARIABLE _RUHA-ID-DRAW

: _RUHA-ID-REFUSE  ( status -- 0 0 0 status )
    >R 0 0 0 R>
    0 _RUHA-ID-ADAPTER ! 0 _RUHA-ID-DRAW ! ;

: _RUHA-SNAPSHOT-IDENTITY-BODY
  ( draw-generation adapter -- generation content-epoch documents status )
    _RUHA-ID-ADAPTER ! _RUHA-ID-DRAW !
    _RUHA-ID-ADAPTER @ RUHA-VALID? 0= IF RUHA-S-INVALID _RUHA-ID-REFUSE EXIT THEN
    _RUHA-ID-DRAW @ 0= IF RUHA-S-INVALID _RUHA-ID-REFUSE EXIT THEN
    _RUHA-ID-DRAW @ _RUHA-ID-ADAPTER @ _RUHA-A.LAST-DRAW @ <> IF
        RUHA-S-STALE _RUHA-ID-REFUSE EXIT
    THEN
    _RUHA-ID-ADAPTER @ _RUHA-A.LAST-STATUS @ DUP RUHA-S-OK <> IF
        _RUHA-ID-REFUSE EXIT
    THEN DROP
    _RUHA-ID-ADAPTER @ _RUHA-A.ACTIVE-BANK @ DUP 0< IF
        DROP RUHA-S-STALE _RUHA-ID-REFUSE EXIT
    THEN
    _RUHA-ID-ADAPTER @ _RUHA-SNAPSHOT-AT
    DUP _RUHA-S.DRAW-GENERATION @ _RUHA-ID-DRAW @ <>
    OVER _RUHA-S.GENERATION @ _RUHA-ID-ADAPTER @ _RUHA-A.GENERATION @ <> OR
    OVER RUHA-SNAPSHOT-CONTENT-EPOCH@ 0= OR IF
        DROP RUHA-S-STALE _RUHA-ID-REFUSE EXIT
    THEN
    DUP RUHA-SNAPSHOT-GENERATION@
    OVER RUHA-SNAPSHOT-CONTENT-EPOCH@
    ROT RUHA-SNAPSHOT-DOCUMENT-COUNT@
    0 _RUHA-ID-ADAPTER ! 0 _RUHA-ID-DRAW !
    RUHA-S-OK ;

: _RUHA-SNAPSHOT-IDENTITY-IN-DRAW
  ( requested adapter actual -- generation content-epoch documents status )
    >R
    OVER R@ <> IF
        2DROP R> DROP 0 0 0 RUHA-S-STALE EXIT
    THEN
    R> DROP _RUHA-SNAPSHOT-IDENTITY-BODY ;

: RUHA-SNAPSHOT-IDENTITY@
  ( draw-generation adapter -- generation content-epoch documents status )
    ['] _RUHA-SNAPSHOT-IDENTITY-IN-DRAW _SCR-WITH-DRAW-AUTHORITY ;

\ =====================================================================
\  Refresh check (frame-refresh.f)
\ =====================================================================
\
\ Between draws, once no paint is pending, the snapshot of the screen's
\ last draw holds what a full capture of every visible document would
\ hold now: every change counted since asked for a paint, and that
\ paint's draw would have been captured again.  RUHA-REFRESH-CHECK makes
\ that full capture into the inactive bank, under the snapshot's own
\ generation, as the shadow check's full capture does, and compares it
\ with the snapshot document by document.  It publishes nothing: the
\ active bank, the generation, the last draw and its status stay as they
\ were, and the records' flags, which a capture stages and may mark
\ dirty, are put back.
\
\ A difference is a change nothing reported.  RUHA-RC-* name the first:
\ its family, its document's owner and slot, and, where the family says
\ which element a record came from, the element's index, id and
\ revision.  That revision did not move since the snapshot, or the paint
\ it asks for would have drawn the element again.

1 CONSTANT RUHA-RC-DOCUMENTS
2 CONSTANT RUHA-RC-MENUS
3 CONSTANT RUHA-RC-COLLECTIONS
4 CONSTANT RUHA-RC-DATA-GRAPHICS
5 CONSTANT RUHA-RC-STATUS-FIELDS
6 CONSTANT RUHA-RC-FIELDS
7 CONSTANT RUHA-RC-DIALOGS

\ RUHA-RC-FAMILY-NAME ( family -- a u )  The family's name, for a report.
: RUHA-RC-FAMILY-NAME  ( family -- a u )
    CASE
        RUHA-RC-DOCUMENTS OF S" the documents shown" ENDOF
        RUHA-RC-MENUS OF S" menus" ENDOF
        RUHA-RC-COLLECTIONS OF S" collections" ENDOF
        RUHA-RC-DATA-GRAPHICS OF S" data graphics" ENDOF
        RUHA-RC-STATUS-FIELDS OF S" status fields" ENDOF
        RUHA-RC-FIELDS OF S" fields" ENDOF
        RUHA-RC-DIALOGS OF S" dialogs" ENDOF
        >R S" nothing" R>
    ENDCASE ;

\ The first difference: its family, or 0; its document's owner, a
\ component instance's ID, and the host slot that shows it, or 0; and the
\ element's index, or -1, with its revision and id.  UIDL ids are at most
\ 64 bytes (liraq/uidl.f).
64 CONSTANT _RUHA-RC-ID-CAP
VARIABLE RUHA-RC-FAMILY
VARIABLE RUHA-RC-OWNER
VARIABLE RUHA-RC-SLOT
VARIABLE RUHA-RC-ELEMENT
VARIABLE RUHA-RC-REVISION
CREATE RUHA-RC-ID _RUHA-RC-ID-CAP ALLOT
VARIABLE RUHA-RC-ID-U

: _RUHA-RC-CLEAR  ( -- )
    0 RUHA-RC-FAMILY ! 0 RUHA-RC-OWNER ! 0 RUHA-RC-SLOT !
    -1 RUHA-RC-ELEMENT ! 0 RUHA-RC-REVISION ! 0 RUHA-RC-ID-U ! ;
_RUHA-RC-CLEAR

VARIABLE _RUHA-RC-OLD      \ the snapshot of the screen's last draw
VARIABLE _RUHA-RC-I        \ the document compared
VARIABLE _RUHA-RC-OE       \ its entry in that snapshot's directory, or 0
VARIABLE _RUHA-RC-NE       \ its entry in the full capture's, or 0
VARIABLE _RUHA-RC-F        \ the family compared

\ The family's descriptors (a menu's records) and native bytes (a menu's
\ text), in the snapshot (O) and in the full capture (N).
VARIABLE _RUHA-RC-DOA  VARIABLE _RUHA-RC-DOU
VARIABLE _RUHA-RC-DNA  VARIABLE _RUHA-RC-DNU
VARIABLE _RUHA-RC-NOA  VARIABLE _RUHA-RC-NOU
VARIABLE _RUHA-RC-NNA  VARIABLE _RUHA-RC-NNU
\ A descriptor's size, and its words for the element it came from and for
\ its native bytes' offset in the document's slice and length; 0 where the
\ family has none.
VARIABLE _RUHA-RC-STRIDE
VARIABLE _RUHA-RC-SOURCE-XT
VARIABLE _RUHA-RC-NOFF-XT
VARIABLE _RUHA-RC-NBYTES-XT

VARIABLE _RUHA-RC-A1  VARIABLE _RUHA-RC-U1
VARIABLE _RUHA-RC-A2  VARIABLE _RUHA-RC-U2

\ The first offset at which two slices differ, or -1 when they are equal.
: _RUHA-RC-DIFF  ( a1 u1 a2 u2 -- offset|-1 )
    _RUHA-RC-U2 ! _RUHA-RC-A2 ! _RUHA-RC-U1 ! _RUHA-RC-A1 !
    _RUHA-RC-U1 @ _RUHA-RC-U2 @ = IF
        _RUHA-RC-U1 @ 0= IF -1 EXIT THEN
        _RUHA-RC-A1 @ _RUHA-RC-U1 @ _RUHA-RC-A2 @ _RUHA-RC-U2 @ COMPARE
        0= IF -1 EXIT THEN
    THEN
    _RUHA-RC-U1 @ _RUHA-RC-U2 @ MIN DUP 0 ?DO
        _RUHA-RC-A1 @ I + C@ _RUHA-RC-A2 @ I + C@ <> IF
            DROP I UNLOOP EXIT
        THEN
    LOOP ;

\ Document I's entries; an index beyond a directory has none.
: _RUHA-RC-ENTRIES  ( i -- )
    DUP _RUHA-RC-I !
    DUP _RUHA-RC-OLD @ RUHA-SNAPSHOT-DOCUMENT-COUNT@ < IF
        DUP RUHA-DOCUMENT-SIZE * _RUHA-RC-OLD @ RUHA-SNAPSHOT-DIRECTORY@ DROP +
    ELSE 0 THEN _RUHA-RC-OE !
    DUP _RUHA-B-DOCUMENTS @ < IF
        RUHA-DOCUMENT-SIZE * _RUHA-B-DIRECTORY-A @ +
    ELSE DROP 0 THEN _RUHA-RC-NE ! ;

\ Whether the document shows elsewhere, or is another document.
: _RUHA-RC-PLACE-DIFFERS?  ( -- flag )
    _RUHA-RC-OE @ RUHA-DOCUMENT-OWNER-ID@
        _RUHA-RC-NE @ RUHA-DOCUMENT-OWNER-ID@ <>
    _RUHA-RC-OE @ RUHA-DOCUMENT-OWNER-GENERATION@
        _RUHA-RC-NE @ RUHA-DOCUMENT-OWNER-GENERATION@ <> OR
    _RUHA-RC-OE @ RUHA-DOCUMENT-TOKEN@
        _RUHA-RC-NE @ RUHA-DOCUMENT-TOKEN@ <> OR
    _RUHA-RC-OE @ RUHA-DOCUMENT-SLOT-ID@
        _RUHA-RC-NE @ RUHA-DOCUMENT-SLOT-ID@ <> OR
    _RUHA-RC-OE @ RUHA-DOCUMENT-ROW@ _RUHA-RC-NE @ RUHA-DOCUMENT-ROW@ <> OR
    _RUHA-RC-OE @ RUHA-DOCUMENT-COL@ _RUHA-RC-NE @ RUHA-DOCUMENT-COL@ <> OR
    _RUHA-RC-OE @ RUHA-DOCUMENT-HEIGHT@
        _RUHA-RC-NE @ RUHA-DOCUMENT-HEIGHT@ <> OR
    _RUHA-RC-OE @ RUHA-DOCUMENT-WIDTH@
        _RUHA-RC-NE @ RUHA-DOCUMENT-WIDTH@ <> OR ;

: _RUHA-RC-MENU-EPOCHS-DIFFER?  ( -- flag )
    _RUHA-RC-OE @ RUHA-DOCUMENT-MENU-EPOCH@
        _RUHA-RC-NE @ RUHA-DOCUMENT-MENU-EPOCH@ <>
    _RUHA-RC-OE @ RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@
        _RUHA-RC-NE @ RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@ <> OR ;

\ One span's slices of the document, from each directory's offset and
\ length: the snapshot's at OLD-BASE, the full capture's at NEW-BASE.
VARIABLE _RUHA-RC-OFF-XT
VARIABLE _RUHA-RC-BYTES-XT
: _RUHA-RC-SLICE  ( old-base new-base offset-xt bytes-xt -- oa ou na nu )
    _RUHA-RC-BYTES-XT ! _RUHA-RC-OFF-XT !
    _RUHA-RC-NE @ _RUHA-RC-OFF-XT @ EXECUTE +
    _RUHA-RC-NE @ _RUHA-RC-BYTES-XT @ EXECUTE
    ROT _RUHA-RC-OE @ _RUHA-RC-OFF-XT @ EXECUTE +
    _RUHA-RC-OE @ _RUHA-RC-BYTES-XT @ EXECUTE
    2SWAP ;

: _RUHA-RC-DESCRIPTORS!  ( oa ou na nu -- )
    _RUHA-RC-DNU ! _RUHA-RC-DNA ! _RUHA-RC-DOU ! _RUHA-RC-DOA ! ;
: _RUHA-RC-NATIVE!  ( oa ou na nu -- )
    _RUHA-RC-NNU ! _RUHA-RC-NNA ! _RUHA-RC-NOU ! _RUHA-RC-NOA ! ;
: _RUHA-RC-WORDS!  ( stride source-xt noff-xt nbytes-xt -- )
    _RUHA-RC-NBYTES-XT ! _RUHA-RC-NOFF-XT !
    _RUHA-RC-SOURCE-XT ! _RUHA-RC-STRIDE ! ;

\ The family's slices of the document and its descriptors' words.
: _RUHA-RC-FAMILY-SLICES  ( family -- )
    CASE
        RUHA-RC-MENUS OF
            _RUHA-RC-OLD @ RUHA-SNAPSHOT-RECORDS@ DROP _RUHA-B-RECORDS-A @
            ['] RUHA-DOCUMENT-RECORD-OFFSET@ ['] RUHA-DOCUMENT-RECORD-BYTES@
            _RUHA-RC-SLICE _RUHA-RC-DESCRIPTORS!
            _RUHA-RC-OLD @ RUHA-SNAPSHOT-TEXT@ DROP _RUHA-B-TEXT-A @
            ['] RUHA-DOCUMENT-TEXT-OFFSET@ ['] RUHA-DOCUMENT-TEXT-BYTES@
            _RUHA-RC-SLICE _RUHA-RC-NATIVE!
            UMSN-RECORD-SIZE ['] UMSN-RECORD-SOURCE-INDEX@ 0 0
        ENDOF
        RUHA-RC-COLLECTIONS OF
            _RUHA-RC-OLD @ RUHA-SNAPSHOT-COLLECTION-DESCRIPTORS@ DROP
            _RUHA-B-DESCRIPTORS-A @
            ['] RUHA-DOCUMENT-COLLECTION-DESCRIPTOR-OFFSET@
            ['] RUHA-DOCUMENT-COLLECTION-DESCRIPTOR-BYTES@
            _RUHA-RC-SLICE _RUHA-RC-DESCRIPTORS!
            _RUHA-RC-OLD @ RUHA-SNAPSHOT-COLLECTION-NATIVE@ DROP
            _RUHA-B-NATIVE-A @
            ['] RUHA-DOCUMENT-COLLECTION-NATIVE-OFFSET@
            ['] RUHA-DOCUMENT-COLLECTION-NATIVE-BYTES@
            _RUHA-RC-SLICE _RUHA-RC-NATIVE!
            UCSN-DESCRIPTOR-SIZE ['] UCSN-DESCRIPTOR-SOURCE-INDEX@
            ['] UCSN-DESCRIPTOR-NATIVE-OFFSET@ ['] UCSN-DESCRIPTOR-ENTRY-BYTES@
        ENDOF
        RUHA-RC-DATA-GRAPHICS OF
            _RUHA-RC-OLD @ RUHA-SNAPSHOT-DATA-GRAPHICS-DESCRIPTORS@ DROP
            _RUHA-B-DGRAPH-DESCRIPTORS-A @
            ['] RUHA-DOCUMENT-DATA-GRAPHICS-DESCRIPTOR-OFFSET@
            ['] RUHA-DOCUMENT-DATA-GRAPHICS-DESCRIPTOR-BYTES@
            _RUHA-RC-SLICE _RUHA-RC-DESCRIPTORS!
            _RUHA-RC-OLD @ RUHA-SNAPSHOT-DATA-GRAPHICS-NATIVE@ DROP
            _RUHA-B-DGRAPH-NATIVE-A @
            ['] RUHA-DOCUMENT-DATA-GRAPHICS-NATIVE-OFFSET@
            ['] RUHA-DOCUMENT-DATA-GRAPHICS-NATIVE-BYTES@
            _RUHA-RC-SLICE _RUHA-RC-NATIVE!
            \ The adapter carries a data-graphics descriptor opaquely and
            \ reads none of its native bounds, so a difference in their
            \ native bytes names no element.
            UDGSN-DESCRIPTOR-SIZE ['] UDGSN-DESCRIPTOR-SOURCE-INDEX@ 0 0
        ENDOF
        RUHA-RC-STATUS-FIELDS OF
            _RUHA-RC-OLD @ RUHA-SNAPSHOT-STATUS-FIELDS-DESCRIPTORS@ DROP
            _RUHA-B-SFIELD-DESCRIPTORS-A @
            ['] RUHA-DOCUMENT-STATUS-FIELDS-DESCRIPTOR-OFFSET@
            ['] RUHA-DOCUMENT-STATUS-FIELDS-DESCRIPTOR-BYTES@
            _RUHA-RC-SLICE _RUHA-RC-DESCRIPTORS!
            _RUHA-RC-OLD @ RUHA-SNAPSHOT-STATUS-FIELDS-NATIVE@ DROP
            _RUHA-B-SFIELD-NATIVE-A @
            ['] RUHA-DOCUMENT-STATUS-FIELDS-NATIVE-OFFSET@
            ['] RUHA-DOCUMENT-STATUS-FIELDS-NATIVE-BYTES@
            _RUHA-RC-SLICE _RUHA-RC-NATIVE!
            USFSN-DESCRIPTOR-SIZE ['] USFSN-DESCRIPTOR-SOURCE-INDEX@
            ['] USFSN-DESCRIPTOR-NATIVE-OFFSET@
            ['] USFSN-DESCRIPTOR-ENTRY-BYTES@
        ENDOF
        RUHA-RC-FIELDS OF
            _RUHA-RC-OLD @ RUHA-SNAPSHOT-FIELDS-DESCRIPTORS@ DROP
            _RUHA-B-FIELD-DESCRIPTORS-A @
            ['] RUHA-DOCUMENT-FIELDS-DESCRIPTOR-OFFSET@
            ['] RUHA-DOCUMENT-FIELDS-DESCRIPTOR-BYTES@
            _RUHA-RC-SLICE _RUHA-RC-DESCRIPTORS!
            _RUHA-RC-OLD @ RUHA-SNAPSHOT-FIELDS-NATIVE@ DROP
            _RUHA-B-FIELD-NATIVE-A @
            ['] RUHA-DOCUMENT-FIELDS-NATIVE-OFFSET@
            ['] RUHA-DOCUMENT-FIELDS-NATIVE-BYTES@
            _RUHA-RC-SLICE _RUHA-RC-NATIVE!
            UFLSN-DESCRIPTOR-SIZE ['] UFLSN-DESCRIPTOR-SOURCE-INDEX@
            ['] UFLSN-DESCRIPTOR-NATIVE-OFFSET@
            ['] UFLSN-DESCRIPTOR-ENTRY-BYTES@
        ENDOF
        \ Dialogs: a dialog is a widget, not an element of its document.
        >R
            _RUHA-RC-OLD @ RUHA-SNAPSHOT-DIALOGS-DESCRIPTORS@ DROP
            _RUHA-B-DIALOG-DESCRIPTORS-A @
            ['] RUHA-DOCUMENT-DIALOGS-DESCRIPTOR-OFFSET@
            ['] RUHA-DOCUMENT-DIALOGS-DESCRIPTOR-BYTES@
            _RUHA-RC-SLICE _RUHA-RC-DESCRIPTORS!
            _RUHA-RC-OLD @ RUHA-SNAPSHOT-DIALOGS-NATIVE@ DROP
            _RUHA-B-DIALOG-NATIVE-A @
            ['] RUHA-DOCUMENT-DIALOGS-NATIVE-OFFSET@
            ['] RUHA-DOCUMENT-DIALOGS-NATIVE-BYTES@
            _RUHA-RC-SLICE _RUHA-RC-NATIVE!
            UDLSN-DESCRIPTOR-SIZE 0
            ['] UDLSN-DESCRIPTOR-NATIVE-OFFSET@
            ['] UDLSN-DESCRIPTOR-ENTRY-BYTES@
        R>
    ENDCASE
    _RUHA-RC-WORDS! ;

\ The element the INDEX-th descriptor came from, read from the full
\ capture, or from the snapshot when the capture has fewer; -1 for none.
: _RUHA-RC-DESCRIPTOR-ELEMENT  ( index -- element|-1 )
    _RUHA-RC-SOURCE-XT @ 0= IF DROP -1 EXIT THEN
    _RUHA-RC-STRIDE @ *
    DUP _RUHA-RC-STRIDE @ + _RUHA-RC-DNU @ U> 0= IF
        _RUHA-RC-DNA @ + _RUHA-RC-SOURCE-XT @ EXECUTE EXIT
    THEN
    DUP _RUHA-RC-STRIDE @ + _RUHA-RC-DOU @ U> 0= IF
        _RUHA-RC-DOA @ + _RUHA-RC-SOURCE-XT @ EXECUTE EXIT
    THEN
    DROP -1 ;

\ The element whose native bytes, among the descriptors at A U, hold
\ offset AT of the document's native slice; -1 for none.
VARIABLE _RUHA-RC-AT
: _RUHA-RC-NATIVE-OWNER  ( at a u -- element|-1 )
    ROT _RUHA-RC-AT !
    _RUHA-RC-NOFF-XT @ 0= _RUHA-RC-SOURCE-XT @ 0= OR IF 2DROP -1 EXIT THEN
    _RUHA-RC-STRIDE @ / 0 ?DO
        DUP I _RUHA-RC-STRIDE @ * +
        _RUHA-RC-AT @ OVER _RUHA-RC-NOFF-XT @ EXECUTE - DUP 0< IF
            2DROP
        ELSE
            OVER _RUHA-RC-NBYTES-XT @ EXECUTE U< IF
                _RUHA-RC-SOURCE-XT @ EXECUTE NIP UNLOOP EXIT
            THEN DROP
        THEN
    LOOP DROP -1 ;

: _RUHA-RC-NATIVE-ELEMENT  ( at -- element|-1 )
    DUP _RUHA-RC-DNA @ _RUHA-RC-DNU @ _RUHA-RC-NATIVE-OWNER
    DUP 0< 0= IF NIP EXIT THEN DROP
    _RUHA-RC-DOA @ _RUHA-RC-DOU @ _RUHA-RC-NATIVE-OWNER ;

\ The record of the document whose owner is component instance OWNER.
: _RUHA-RC-RECORD  ( owner -- record|0 )
    _RUHA-B-ADAPTER @ _RUHA-A.CAPACITY @ 0 ?DO
        I _RUHA-B-ADAPTER @ _RUHA-RECORD-AT
        DUP _RUHA-R.SLOT @ ?DUP IF
            AHS.INST @ ?DUP IF
                CINST.ID @ 2 PICK = IF NIP UNLOOP EXIT THEN
            THEN
        THEN DROP
    LOOP DROP 0 ;

\ The element's id and revision, read in its document's context.
VARIABLE _RUHA-RC-RECORD-A
: _RUHA-RC-ELEMENT-BODY  ( -- )
    _RUHA-RC-RECORD-A @ _RUHA-R.UCTX @ ASHELL-CTX-SWITCH
    RUHA-RC-ELEMENT @ UIDL-ELEM-AT? 0= IF DROP EXIT THEN
    DUP UIDL-REVISION RUHA-RC-REVISION !
    UIDL-ID _RUHA-RC-ID-CAP MIN DUP RUHA-RC-ID-U !
    RUHA-RC-ID SWAP MOVE ;

\ Name the first difference: FAMILY, and ELEMENT or -1.
: _RUHA-RC-NAME  ( family element -- )
    RUHA-RC-ELEMENT ! RUHA-RC-FAMILY !
    _RUHA-RC-NE @ ?DUP 0= IF _RUHA-RC-OE @ THEN
    RUHA-DOCUMENT-OWNER-ID@ DUP RUHA-RC-OWNER !
    _RUHA-RC-RECORD DUP _RUHA-RC-RECORD-A ! ?DUP 0= IF EXIT THEN
    _RUHA-R.SLOT @ RUHA-RC-SLOT !
    RUHA-RC-ELEMENT @ 0< IF EXIT THEN
    ['] _RUHA-RC-ELEMENT-BODY CATCH DROP
    _RUHA-B-ORIGINAL-CTX @ ['] ASHELL-CTX-SWITCH CATCH IF DROP THEN ;

\ Whether the family's slices of the document differ; the first difference
\ is named.
: _RUHA-RC-FAMILY?  ( family -- differs? )
    DUP _RUHA-RC-F ! _RUHA-RC-FAMILY-SLICES
    _RUHA-RC-DOA @ _RUHA-RC-DOU @ _RUHA-RC-DNA @ _RUHA-RC-DNU @ _RUHA-RC-DIFF
    DUP 0< 0= IF
        _RUHA-RC-STRIDE @ / _RUHA-RC-DESCRIPTOR-ELEMENT
        _RUHA-RC-F @ SWAP _RUHA-RC-NAME -1 EXIT
    THEN DROP
    _RUHA-RC-NOA @ _RUHA-RC-NOU @ _RUHA-RC-NNA @ _RUHA-RC-NNU @ _RUHA-RC-DIFF
    DUP 0< 0= IF
        _RUHA-RC-NATIVE-ELEMENT _RUHA-RC-F @ SWAP _RUHA-RC-NAME -1 EXIT
    THEN DROP 0 ;

\ Whether document _RUHA-RC-I differs between the snapshot and the full
\ capture; the first difference is named.
: _RUHA-RC-DOCUMENT?  ( -- differs? )
    _RUHA-RC-PLACE-DIFFERS? IF RUHA-RC-DOCUMENTS -1 _RUHA-RC-NAME -1 EXIT THEN
    RUHA-RC-DIALOGS 1+ RUHA-RC-MENUS ?DO
        I _RUHA-RC-FAMILY? IF UNLOOP -1 EXIT THEN
    LOOP
    _RUHA-RC-MENU-EPOCHS-DIFFER? IF RUHA-RC-MENUS -1 _RUHA-RC-NAME -1 EXIT THEN
    0 ;

: _RUHA-RC-COMPARE  ( -- differs? )
    _RUHA-RC-CLEAR
    _RUHA-RC-OLD @ RUHA-SNAPSHOT-DOCUMENT-COUNT@ _RUHA-B-DOCUMENTS @ MIN
    DUP 0 ?DO
        I _RUHA-RC-ENTRIES
        _RUHA-RC-DOCUMENT? IF DROP UNLOOP -1 EXIT THEN
    LOOP
    \ A document shown in one and not the other.
    _RUHA-RC-OLD @ RUHA-SNAPSHOT-DOCUMENT-COUNT@ _RUHA-B-DOCUMENTS @ = IF
        DROP 0 EXIT
    THEN
    _RUHA-RC-ENTRIES RUHA-RC-DOCUMENTS -1 _RUHA-RC-NAME -1 ;

VARIABLE _RUHA-RC-FLAGS-SAVED

: _RUHA-RC-IN-DRAW  ( adapter actual-draw -- status differs? )
    _RUHA-B-DRAW ! _RUHA-B-ADAPTER !
    _RUHA-B-ADAPTER @ RUHA-VALID? 0= IF RUHA-S-INVALID 0 EXIT THEN
    \ The snapshot is the screen's last draw's, and still the one held.
    _RUHA-B-DRAW @ 0= IF RUHA-S-STALE 0 EXIT THEN
    _RUHA-B-DRAW @ _RUHA-B-ADAPTER @ _RUHA-A.LAST-DRAW @ <> IF
        RUHA-S-STALE 0 EXIT
    THEN
    _RUHA-B-ADAPTER @ _RUHA-A.LAST-STATUS @ DUP RUHA-S-OK <> IF 0 EXIT THEN
    DROP
    _RUHA-B-ADAPTER @ _RUHA-A.ACTIVE-BANK @ DUP 0< IF
        DROP RUHA-S-STALE 0 EXIT
    THEN
    _RUHA-B-ADAPTER @ _RUHA-SNAPSHOT-AT _RUHA-RC-OLD !
    _RUHA-RC-OLD @ _RUHA-S.DRAW-GENERATION @ _RUHA-B-DRAW @ <>
    _RUHA-RC-OLD @ _RUHA-S.GENERATION @
        _RUHA-B-ADAPTER @ _RUHA-A.GENERATION @ <> OR IF
        RUHA-S-STALE 0 EXIT
    THEN
    ASHELL-ACTIVE-CTX _RUHA-B-ORIGINAL-CTX !
    _RUHA-B-PREFLIGHT-GUARDED _RUHA-B-STATUS !
    ['] _RUHA-B-RESTORE CATCH IF RUHA-S-INVALID _RUHA-B-STATUS ! THEN
    _RUHA-B-STATUS @ RUHA-S-OK <> IF _RUHA-B-STATUS @ 0 EXIT THEN
    _RUHA-B-LOAD-PRIOR
    _RUHA-B-ADAPTER @ _RUHA-A.ACTIVE-BANK @ 0= IF 1 ELSE 0 THEN
        _RUHA-B-BANK !
    _RUHA-RC-OLD @ _RUHA-S.GENERATION @ _RUHA-B-GENERATION !
    _RUHA-B-BANK-SPANS
    _RUHA-SH-SAVE-FLAGS? 0= IF RUHA-S-UNAVAILABLE 0 EXIT THEN
    -1 _RUHA-B-FULL !
    _RUHA-B-BUILD
    0 _RUHA-B-FULL !
    _RUHA-SH-RESTORE-FLAGS
    _RUHA-B-STATUS @ RUHA-S-OK <> IF _RUHA-B-STATUS @ 0 EXIT THEN
    RUHA-S-OK _RUHA-RC-COMPARE ;

\ RUHA-REFRESH-CHECK ( adapter -- status differs? )
\   Compare a full capture of every visible document with the snapshot of
\   the screen's last draw.  STATUS is RUHA-S-OK when they were compared,
\   RUHA-S-STALE when the screen has drawn since that snapshot or holds
\   none, and otherwise why the capture could not be made.  DIFFERS? is
\   true when they differ, and RUHA-RC-* then name the first difference.
: RUHA-REFRESH-CHECK  ( adapter -- status differs? )
    ['] _RUHA-RC-IN-DRAW _SCR-WITH-DRAW-AUTHORITY ;

\ =====================================================================
\  Pictures
\ =====================================================================
\
\ Pictures are described afresh for each candidate instead of being kept in
\ the snapshot: the copies they ask for follow the terminal's pixel size and
\ the space the producer has, which change while no document redraws.  Each
\ visible document with no foreground paint over it describes its pictures
\ in its own UCTX, and every descriptor records the document's token.  A
\ pull copies one described copy's pixels from that document.

VARIABLE _RUHA-P-ADAPTER
VARIABLE _RUHA-P-A
VARIABLE _RUHA-P-U
VARIABLE _RUHA-P-USED
VARIABLE _RUHA-P-COUNT
VARIABLE _RUHA-P-STATUS
VARIABLE _RUHA-P-RECORD
VARIABLE _RUHA-P-ASK
VARIABLE _RUHA-P-ORIGINAL

: _RUHA-P-CLEAR  ( -- )
    0 _RUHA-P-ADAPTER ! 0 _RUHA-P-A ! 0 _RUHA-P-U ! 0 _RUHA-P-USED !
    0 _RUHA-P-COUNT ! 0 _RUHA-P-RECORD ! 0 _RUHA-P-ASK ! ;

\ The UCTX of a visible document whose cells no foreground paint covers,
\ or that only its own overlay covers, or 0.  The overlay lies in the
\ layer above the document's pictures, which keep their place.
: _RUHA-P-DOCUMENT-CTX  ( record -- uctx|0 )
    DUP _RUHA-P-ADAPTER @ _RUHA-RECORD-VISIBLE? 0= IF DROP 0 EXIT THEN
    DUP _RUHA-R.ROW @ OVER _RUHA-R.COL @
    2 PICK _RUHA-R.HEIGHT @ 3 PICK _RUHA-R.WIDTH @
        SCR-OCCLUSION-RECT? 0= IF 2DROP 0 EXIT THEN
    OVER _RUHA-R.SLOT @ AHS-OVERLAY? 0= AND IF
        DUP _RUHA-P-ADAPTER @ _RUHA-LAYERED? 0= IF DROP 0 EXIT THEN
    THEN
    _RUHA-R.UCTX @ ;

: _RUHA-P-RECORD-PICTURES  ( record -- )
    DUP _RUHA-P-RECORD ! _RUHA-P-DOCUMENT-CTX ?DUP 0= IF EXIT THEN
    DUP ASHELL-CTX-SWITCH ASHELL-ACTIVE-CTX <> IF
        RUHA-S-INVALID _RUHA-P-STATUS ! EXIT
    THEN
    \ Once the bank is short, the rest only count what they would take.
    _RUHA-P-STATUS @ RUHA-S-CAPACITY = IF 0 0 ELSE
        _RUHA-P-A @ _RUHA-P-USED @ + _RUHA-P-U @ _RUHA-P-USED @ -
    THEN
    _RUHA-P-ASK @ UPICSN-CAPTURE
    DUP UPICSN-S-UNAVAILABLE = IF 2DROP EXIT THEN
    DUP UPICSN-S-CAPACITY = IF
        DROP _RUHA-P-COUNT +! RUHA-S-CAPACITY _RUHA-P-STATUS ! EXIT
    THEN
    UPICSN-S-OK <> IF DROP RUHA-S-INVALID _RUHA-P-STATUS ! EXIT THEN
    DUP 0 ?DO
        _RUHA-P-RECORD @ _RUHA-R.TOKEN @
        _RUHA-P-A @ _RUHA-P-USED @ + I UPICSN-DESCRIPTOR-SIZE * +
            UPICSN-DOCUMENT!
    LOOP
    DUP _RUHA-P-COUNT +! UPICSN-DESCRIPTOR-SIZE * _RUHA-P-USED +! ;

: _RUHA-P-BODY  ( -- )
    _RUHA-P-ADAPTER @ _RUHA-A.CAPACITY @ 0 ?DO
        I _RUHA-P-ADAPTER @ _RUHA-RECORD-AT _RUHA-P-RECORD-PICTURES
        _RUHA-P-STATUS @ RUHA-S-INVALID = IF LEAVE THEN
    LOOP ;

: _RUHA-PICTURES-IN-DRAW
  ( a u ask requested-draw adapter actual-draw -- count status )
    >R _RUHA-P-ADAPTER !
    R> <> IF 2DROP DROP 0 RUHA-S-STALE _RUHA-P-CLEAR EXIT THEN
    _RUHA-P-ASK ! _RUHA-P-U ! _RUHA-P-A !
    _RUHA-P-ADAPTER @ RUHA-VALID? 0= IF 0 RUHA-S-INVALID _RUHA-P-CLEAR EXIT THEN
    _RUHA-P-U @ IF
        _RUHA-P-A @ _RUHA-P-U @ _RUHA-P-ADAPTER @ RUHA-SIZE MSPAN-OVERLAP? IF
            0 RUHA-S-INVALID _RUHA-P-CLEAR EXIT
        THEN
    THEN
    0 _RUHA-P-USED ! 0 _RUHA-P-COUNT ! RUHA-S-OK _RUHA-P-STATUS !
    ASHELL-ACTIVE-CTX _RUHA-P-ORIGINAL !
    ['] _RUHA-P-BODY CATCH IF RUHA-S-INVALID _RUHA-P-STATUS ! THEN
    _RUHA-P-ORIGINAL @ ['] ASHELL-CTX-SWITCH CATCH IF
        DROP RUHA-S-INVALID _RUHA-P-STATUS !
    THEN
    \ Only a complete description is left in the bank.
    _RUHA-P-STATUS @ RUHA-S-OK <> IF _RUHA-P-A @ _RUHA-P-USED @ 0 FILL THEN
    _RUHA-P-STATUS @ RUHA-S-INVALID = IF 0 ELSE _RUHA-P-COUNT @ THEN
    _RUHA-P-STATUS @ _RUHA-P-CLEAR ;

\ RUHA-PICTURES@
\   ( descriptors-a descriptors-u ask draw-generation adapter -- count status )
\   Describe every picture the attached visible documents show for this
\   completed draw into the caller's UPICSN descriptor bank, asking each for
\   the copy UPICSN-CAPTURE describes under ASK, each descriptor naming its
\   document's token.  CAPACITY, with how many descriptors it would take and
\   none written, when the bank is short; STALE when DRAW-GENERATION is not
\   the completed draw.
: RUHA-PICTURES@
    ['] _RUHA-PICTURES-IN-DRAW _SCR-WITH-DRAW-AUTHORITY ;

\ RUHA-PICTURE-PULL ( descriptor offset dest-a dest-u adapter -- status )
\   Copy DEST-U bytes from OFFSET of a described picture's file or copy
\   into DEST, from the document it was described in.  STALE once that
\   document or picture no longer shows it, or its file could not be read.
: _RUHA-PP-BODY  ( descriptor offset dest-a dest-u -- status )
    _RUHA-P-ADAPTER @ _RUHA-A.CAPACITY @ 0 ?DO
        I _RUHA-P-ADAPTER @ _RUHA-RECORD-AT DUP _RUHA-R.TOKEN @
        5 PICK UPICSN-DOCUMENT@ = IF
            _RUHA-P-DOCUMENT-CTX ?DUP 0= IF
                2DROP 2DROP RUHA-S-STALE UNLOOP EXIT
            THEN
            DUP ASHELL-CTX-SWITCH ASHELL-ACTIVE-CTX <> IF
                2DROP 2DROP RUHA-S-INVALID UNLOOP EXIT
            THEN
            UPICSN-PULL
            DUP UPICSN-S-OK = IF DROP RUHA-S-OK UNLOOP EXIT THEN
            UPICSN-S-STALE = IF RUHA-S-STALE ELSE RUHA-S-INVALID THEN
            UNLOOP EXIT
        THEN DROP
    LOOP
    2DROP 2DROP RUHA-S-STALE ;

: RUHA-PICTURE-PULL  ( descriptor offset dest-a dest-u adapter -- status )
    DUP RUHA-VALID? 0= IF DROP 2DROP 2DROP RUHA-S-INVALID EXIT THEN
    _RUHA-P-ADAPTER !
    2DUP _RUHA-P-ADAPTER @ RUHA-SIZE MSPAN-OVERLAP? IF
        2DROP 2DROP RUHA-S-INVALID _RUHA-P-CLEAR EXIT
    THEN
    ASHELL-ACTIVE-CTX _RUHA-P-ORIGINAL !
    ['] _RUHA-PP-BODY CATCH IF 2DROP 2DROP RUHA-S-INVALID THEN
    _RUHA-P-ORIGINAL @ ['] ASHELL-CTX-SWITCH CATCH IF DROP DROP RUHA-S-INVALID THEN
    _RUHA-P-CLEAR ;

\ RUHA-PICTURE-FAIL
\   ( document source-index root-key revision reason adapter -- status )
\   The rich side could not send picture REVISION at SOURCE-INDEX with
\   ROOT-KEY of DOCUMENT, by its token, because of the picture itself, for
\   REASON: its widget remembers why (UPICSN-FAIL), in that document's
\   context.  STALE once the document is gone or hidden or that place
\   shows another picture.
: _RUHA-PF-BODY  ( document source-index root-key revision reason -- status )
    _RUHA-P-ADAPTER @ _RUHA-A.CAPACITY @ 0 ?DO
        I _RUHA-P-ADAPTER @ _RUHA-RECORD-AT DUP _RUHA-R.TOKEN @
        6 PICK = IF
            _RUHA-P-DOCUMENT-CTX ?DUP 0= IF
                2DROP 2DROP DROP RUHA-S-STALE UNLOOP EXIT
            THEN
            DUP ASHELL-CTX-SWITCH ASHELL-ACTIVE-CTX <> IF
                2DROP 2DROP DROP RUHA-S-INVALID UNLOOP EXIT
            THEN
            >R >R >R NIP R> R> R> UPICSN-FAIL
            DUP UPICSN-S-OK = IF DROP RUHA-S-OK UNLOOP EXIT THEN
            UPICSN-S-STALE = IF RUHA-S-STALE ELSE RUHA-S-INVALID THEN
            UNLOOP EXIT
        THEN DROP
    LOOP
    2DROP 2DROP DROP RUHA-S-STALE ;

: RUHA-PICTURE-FAIL
  ( document source-index root-key revision reason adapter -- status )
    DUP RUHA-VALID? 0= IF DROP 2DROP 2DROP DROP RUHA-S-INVALID EXIT THEN
    _RUHA-P-ADAPTER !
    ASHELL-ACTIVE-CTX _RUHA-P-ORIGINAL !
    ['] _RUHA-PF-BODY CATCH IF 2DROP 2DROP DROP RUHA-S-INVALID THEN
    _RUHA-P-ORIGINAL @ ['] ASHELL-CTX-SWITCH CATCH IF DROP DROP RUHA-S-INVALID THEN
    _RUHA-P-CLEAR ;

\ =====================================================================
\  Root facts
\ =====================================================================
\
\  RUHA-ROOT-FACTS@ ( facts-a facts-u draw-generation adapter -- count status )
\    Record, for every root the snapshot this completed draw published
\    holds, what its capture read (uidl-root-facts.f): one URF record per
\    root, in directory order and, within a document, menus, collections,
\    data graphics, status fields, fields and the dialog.  Each record
\    names its document's token, and each is filled in that document's own
\    context, as the snapshot was.  CAPACITY, with how many records it
\    would take and none written, when the bank is short; STALE when
\    DRAW-GENERATION is not the completed draw or the draw published no
\    snapshot.

VARIABLE _RUHA-F-ADAPTER
VARIABLE _RUHA-F-A
VARIABLE _RUHA-F-U
VARIABLE _RUHA-F-USED
VARIABLE _RUHA-F-COUNT
VARIABLE _RUHA-F-STATUS
VARIABLE _RUHA-F-SNAP
VARIABLE _RUHA-F-ENTRY
VARIABLE _RUHA-F-TOKEN
VARIABLE _RUHA-F-XT
VARIABLE _RUHA-F-SIZE
VARIABLE _RUHA-F-ORIGINAL

\ The next record, or 0 once the bank is short, when only the count grows.
: _RUHA-F-NEXT  ( -- record|0 )
    1 _RUHA-F-COUNT +!
    _RUHA-F-STATUS @ RUHA-S-OK <> IF 0 EXIT THEN
    _RUHA-F-USED @ URF-SIZE + _RUHA-F-U @ U> IF
        RUHA-S-CAPACITY _RUHA-F-STATUS ! 0 EXIT
    THEN
    _RUHA-F-A @ _RUHA-F-USED @ + URF-SIZE _RUHA-F-USED +! ;

: _RUHA-F-TOKEN!  ( record -- )  _RUHA-F-TOKEN @ SWAP URF.TOKEN ! ;

\ One root's record, filled by XT ( descriptor record -- ).
: _RUHA-F-ROOT  ( descriptor xt -- )
    _RUHA-F-NEXT ?DUP 0= IF 2DROP EXIT THEN
    DUP >R SWAP EXECUTE R> _RUHA-F-TOKEN! ;

\ The records of the BYTES of SIZE-byte descriptors at A, filled by XT.
: _RUHA-F-EACH  ( a bytes size xt -- )
    _RUHA-F-XT ! DUP _RUHA-F-SIZE ! / 0 ?DO
        DUP I _RUHA-F-SIZE @ * + _RUHA-F-XT @ _RUHA-F-ROOT
    LOOP DROP ;

\ The context of the attached document TOKEN names, or 0.
: _RUHA-F-CTX  ( token -- uctx|0 )
    _RUHA-F-ADAPTER @ _RUHA-A.CAPACITY @ 0 ?DO
        I _RUHA-F-ADAPTER @ _RUHA-RECORD-AT
        DUP _RUHA-R.TOKEN @ 2 PICK = IF
            NIP _RUHA-R.UCTX @ UNLOOP EXIT
        THEN DROP
    LOOP DROP 0 ;

\ An entry with no slice, covered or empty, has no roots.
: _RUHA-F-SLICES?  ( entry -- flag )
    DUP RUHA-DOCUMENT-RECORD-BYTES@
    OVER RUHA-DOCUMENT-COLLECTION-DESCRIPTOR-BYTES@ OR
    OVER RUHA-DOCUMENT-DATA-GRAPHICS-DESCRIPTOR-BYTES@ OR
    OVER RUHA-DOCUMENT-STATUS-FIELDS-DESCRIPTOR-BYTES@ OR
    OVER RUHA-DOCUMENT-FIELDS-DESCRIPTOR-BYTES@ OR
    SWAP RUHA-DOCUMENT-DIALOGS-DESCRIPTOR-BYTES@ OR 0<> ;

: _RUHA-F-DOCUMENT  ( entry -- )
    DUP _RUHA-F-ENTRY ! DUP _RUHA-F-SLICES? 0= IF DROP EXIT THEN
    DUP RUHA-DOCUMENT-TOKEN@ _RUHA-F-TOKEN !
    RUHA-DOCUMENT-TOKEN@ _RUHA-F-CTX ?DUP 0= IF
        RUHA-S-INVALID _RUHA-F-STATUS ! EXIT
    THEN
    DUP ASHELL-CTX-SWITCH ASHELL-ACTIVE-CTX <> IF
        RUHA-S-INVALID _RUHA-F-STATUS ! EXIT
    THEN
    _RUHA-F-ENTRY @ RUHA-DOCUMENT-RECORD-BYTES@ ?DUP IF
        _RUHA-F-NEXT ?DUP IF
            >R UMSN-RECORD-SIZE /
            _RUHA-F-SNAP @ RUHA-SNAPSHOT-RECORDS@ DROP
                _RUHA-F-ENTRY @ RUHA-DOCUMENT-RECORD-OFFSET@ +
            SWAP R@ URF-MENUS R> _RUHA-F-TOKEN!
        ELSE DROP THEN
    THEN
    _RUHA-F-SNAP @ RUHA-SNAPSHOT-COLLECTION-DESCRIPTORS@ DROP
        _RUHA-F-ENTRY @ RUHA-DOCUMENT-COLLECTION-DESCRIPTOR-OFFSET@ +
    _RUHA-F-ENTRY @ RUHA-DOCUMENT-COLLECTION-DESCRIPTOR-BYTES@
    UCSN-DESCRIPTOR-SIZE ['] URF-COLLECTION _RUHA-F-EACH
    _RUHA-F-SNAP @ RUHA-SNAPSHOT-DATA-GRAPHICS-DESCRIPTORS@ DROP
        _RUHA-F-ENTRY @ RUHA-DOCUMENT-DATA-GRAPHICS-DESCRIPTOR-OFFSET@ +
    _RUHA-F-ENTRY @ RUHA-DOCUMENT-DATA-GRAPHICS-DESCRIPTOR-BYTES@
    UDGSN-DESCRIPTOR-SIZE ['] URF-DATA-GRAPHICS _RUHA-F-EACH
    _RUHA-F-SNAP @ RUHA-SNAPSHOT-STATUS-FIELDS-DESCRIPTORS@ DROP
        _RUHA-F-ENTRY @ RUHA-DOCUMENT-STATUS-FIELDS-DESCRIPTOR-OFFSET@ +
    _RUHA-F-ENTRY @ RUHA-DOCUMENT-STATUS-FIELDS-DESCRIPTOR-BYTES@
    USFSN-DESCRIPTOR-SIZE ['] URF-STATUS-FIELD _RUHA-F-EACH
    _RUHA-F-SNAP @ RUHA-SNAPSHOT-FIELDS-DESCRIPTORS@ DROP
        _RUHA-F-ENTRY @ RUHA-DOCUMENT-FIELDS-DESCRIPTOR-OFFSET@ +
    _RUHA-F-ENTRY @ RUHA-DOCUMENT-FIELDS-DESCRIPTOR-BYTES@
    UFLSN-DESCRIPTOR-SIZE ['] URF-FIELD _RUHA-F-EACH
    _RUHA-F-SNAP @ RUHA-SNAPSHOT-DIALOGS-DESCRIPTORS@ DROP
        _RUHA-F-ENTRY @ RUHA-DOCUMENT-DIALOGS-DESCRIPTOR-OFFSET@ +
    _RUHA-F-ENTRY @ RUHA-DOCUMENT-DIALOGS-DESCRIPTOR-BYTES@
    UDLSN-DESCRIPTOR-SIZE ['] URF-DIALOG _RUHA-F-EACH ;

: _RUHA-F-BODY  ( -- )
    _RUHA-F-SNAP @ RUHA-SNAPSHOT-DIRECTORY@ DROP
    _RUHA-F-SNAP @ RUHA-SNAPSHOT-DOCUMENT-COUNT@ 0 ?DO
        DUP I RUHA-DOCUMENT-SIZE * + _RUHA-F-DOCUMENT
        _RUHA-F-STATUS @ RUHA-S-INVALID = IF LEAVE THEN
    LOOP DROP ;

: _RUHA-FACTS-IN-DRAW
  ( a u requested-draw adapter actual-draw -- count status )
    >R _RUHA-F-ADAPTER !
    DUP R> <> IF DROP 2DROP 0 RUHA-S-STALE EXIT THEN
    >R _RUHA-F-U ! _RUHA-F-A !
    _RUHA-F-ADAPTER @ RUHA-VALID? 0= IF R> DROP 0 RUHA-S-INVALID EXIT THEN
    \ The facts describe the snapshot this draw published.
    _RUHA-F-ADAPTER @ _RUHA-A.LAST-STATUS @ RUHA-S-OK <>
    _RUHA-F-ADAPTER @ _RUHA-A.LAST-DRAW @ R@ <> OR IF
        R> DROP 0 RUHA-S-STALE EXIT
    THEN
    _RUHA-F-ADAPTER @ _RUHA-A.ACTIVE-BANK @ _RUHA-F-ADAPTER @
        _RUHA-SNAPSHOT-AT DUP _RUHA-F-SNAP !
    RUHA-SNAPSHOT-DRAW-GENERATION@ R> <> IF 0 RUHA-S-STALE EXIT THEN
    _RUHA-F-U @ IF
        _RUHA-F-A @ _RUHA-F-U @ _RUHA-F-ADAPTER @ RUHA-SIZE MSPAN-OVERLAP? IF
            0 RUHA-S-INVALID EXIT
        THEN
    THEN
    0 _RUHA-F-USED ! 0 _RUHA-F-COUNT ! RUHA-S-OK _RUHA-F-STATUS !
    ASHELL-ACTIVE-CTX _RUHA-F-ORIGINAL !
    ['] _RUHA-F-BODY CATCH IF RUHA-S-INVALID _RUHA-F-STATUS ! THEN
    _RUHA-F-ORIGINAL @ ['] ASHELL-CTX-SWITCH CATCH IF
        DROP RUHA-S-INVALID _RUHA-F-STATUS !
    THEN
    \ Only a complete set of records is left in the bank.
    _RUHA-F-STATUS @ RUHA-S-OK <> IF _RUHA-F-A @ _RUHA-F-USED @ 0 FILL THEN
    _RUHA-F-STATUS @ RUHA-S-INVALID = IF 0 ELSE _RUHA-F-COUNT @ THEN
    _RUHA-F-STATUS @ ;

: RUHA-ROOT-FACTS@  ( facts-a facts-u draw-generation adapter -- count status )
    ['] _RUHA-FACTS-IN-DRAW _SCR-WITH-DRAW-AUTHORITY ;

CREATE _RUHA-OWNED-END
_RUHA-OWNED-END _RUHA-OWNED-LIMIT !
