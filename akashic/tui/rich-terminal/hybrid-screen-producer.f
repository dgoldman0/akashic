\ =====================================================================
\  hybrid-screen-producer.f -- complete semantic screen producer
\ =====================================================================
\
\  This is the narrow production replacement for the temporary per-cell
\  screen plane.  It copies the completed visible-UIDL document directory and
\  its aggregate semantic snapshot, appends every document's controls and
\  claims, excludes their claimed cells from one coalesced glyph projection of
\  the ordinary screen, admits the combined candidate once, and carries each
\  immutable candidate through hidden START and physical reveal
\  acknowledgement.  Later completed draws use an ACK-baselined retained
\  DELTA only when the compact active snapshot proves stable identity and
\  topology; every uncertain case remains on the complete replacement path.
\
\  The caller supplies the first arena and the real lifecycle endpoints.
\  With a memory source attached, the arena then grows to what each draw's
\  content and surface need; without one it stays the caller's fixed bound.
\  CELL remains authoritative fallback, while a newer CELL frame is refused
\  until its matching rich replacement can be hidden and revealed exactly.
\
\  Prefix: RTHP- (public), _RTHP- (private)

PROVIDED akashic-tui-rterm-hybrid-screen-producer

REQUIRE uidl-hybrid-adapter.f
REQUIRE uidl-control-planner.f
REQUIRE uidl-instrument-planner.f
REQUIRE uidl-claim-ledger.f
REQUIRE uidl-semantic-content-stx1.f
REQUIRE uidl-semantic-items-itm1.f
REQUIRE uidl-semantic-documents-doc1.f
REQUIRE ../field-content.f
REQUIRE ../dialog-content.f
REQUIRE ../uidl-dialog-snapshot.f
REQUIRE residual-glyph-planner.f
REQUIRE engine.f
REQUIRE phase-profile.f
REQUIRE frame-shadow.f
REQUIRE ../check-mode.f
REQUIRE ../../math/crc.f
REQUIRE ../screen.f
REQUIRE ../uidl-picture-snapshot.f
REQUIRE ../../utils/memory-span.f
REQUIRE ../../utils/memory-source.f

CREATE _RTHP-OWNED-START
VARIABLE _RTHP-OWNED-LIMIT

0x3250444952425948 CONSTANT _RTHP-MAGIC  \ "HYBRIDP2"

: _RTHP.MAGIC          ( p -- a )        ;
: _RTHP.SIZE           ( p -- a )    8 + ;
: _RTHP.SELF           ( p -- a )   16 + ;
: _RTHP.ADAPTER        ( p -- a )   24 + ;
: _RTHP.FACADE         ( p -- a )   32 + ;
: _RTHP.ARENA-A        ( p -- a )   40 + ;
: _RTHP.ARENA-U        ( p -- a )   48 + ;
: _RTHP.MAX-RECORDS    ( p -- a )   56 + ;
: _RTHP.MAX-TEXT       ( p -- a )   64 + ;
: _RTHP.MAX-COLS       ( p -- a )   72 + ;
: _RTHP.MAX-ROWS       ( p -- a )   80 + ;
: _RTHP.OWNER          ( p -- a )   88 + ;
: _RTHP.OWNER-GEN      ( p -- a )   96 + ;
: _RTHP.REGION         ( p -- a )  104 + ;
: _RTHP.FIRST-OBJECT   ( p -- a )  112 + ;
: _RTHP.PHASE          ( p -- a )  120 + ;
: _RTHP.FAULT          ( p -- a )  128 + ;
: _RTHP.COLS           ( p -- a )  136 + ;
: _RTHP.ROWS           ( p -- a )  144 + ;
: _RTHP.SURFACE-GEN    ( p -- a )  152 + ;
: _RTHP.ATTEMPT        ( p -- a )  160 + ;
: _RTHP.SOURCE-GEN     ( p -- a )  168 + ;
: _RTHP.SOURCE-DRAW    ( p -- a )  176 + ;
: _RTHP.SOURCE-RECS-A  ( p -- a )  184 + ;
: _RTHP.SOURCE-RECS-U  ( p -- a )  192 + ;
: _RTHP.SOURCE-USED    ( p -- a )  200 + ;
: _RTHP.SOURCE-TEXT-A  ( p -- a )  208 + ;
: _RTHP.SOURCE-TEXT-U  ( p -- a )  216 + ;
: _RTHP.SOURCE-TEXT-USED ( p -- a ) 224 + ;
: _RTHP.LOOKUP-A       ( p -- a )  232 + ;
: _RTHP.LOOKUP-U       ( p -- a )  240 + ;
: _RTHP.ORDER-A        ( p -- a )  248 + ;
: _RTHP.ORDER-U        ( p -- a )  256 + ;
: _RTHP.ORDER2-A       ( p -- a )  264 + ;
: _RTHP.ORDER2-U       ( p -- a )  272 + ;
: _RTHP.CONTROLS-A     ( p -- a )  280 + ;
: _RTHP.CONTROLS-U     ( p -- a )  288 + ;
: _RTHP.CORR-A         ( p -- a )  296 + ;
: _RTHP.CORR-U         ( p -- a )  304 + ;
: _RTHP.CLAIMS-A       ( p -- a )  312 + ;
: _RTHP.CLAIMS-U       ( p -- a )  320 + ;
: _RTHP.CLAIMS-USED    ( p -- a )  328 + ;
: _RTHP.HEADS-A        ( p -- a )  336 + ;
: _RTHP.HEADS-U        ( p -- a )  344 + ;
: _RTHP.EVENTS-A       ( p -- a )  352 + ;
: _RTHP.EVENTS-U       ( p -- a )  360 + ;
: _RTHP.DIFF-A         ( p -- a )  368 + ;
: _RTHP.DIFF-U         ( p -- a )  376 + ;
: _RTHP.GLYPH-ITEMS-A  ( p -- a )  384 + ;
: _RTHP.GLYPH-ITEMS-U  ( p -- a )  392 + ;
: _RTHP.GLYPH-REFS-A   ( p -- a )  400 + ;
: _RTHP.GLYPH-REFS-U   ( p -- a )  408 + ;
: _RTHP.GLYPH-TEXT-A   ( p -- a )  416 + ;
: _RTHP.GLYPH-TEXT-U   ( p -- a )  424 + ;
: _RTHP.GLYPH-TEXT-USED ( p -- a ) 432 + ;
: _RTHP.CONTROL-COUNT  ( p -- a )  440 + ;
: _RTHP.GLYPH-COUNT    ( p -- a )  448 + ;
: _RTHP.PHYSICAL-GEN   ( p -- a )  456 + ;
: _RTHP.LIMITS         ( p -- a )  464 + ;
: _RTHP.RUCP-Q         ( p -- a )  648 + ;
: _RTHP.RUCL-Q         ( p -- a )  928 + ;
: _RTHP.RGRP-Q         ( p -- a ) 1040 + ;
: _RTHP.CONTROL-PLAN   ( p -- a ) 1320 + ;
: _RTHP.GLYPH-PLAN     ( p -- a ) 1464 + ;
: _RTHP.HYBRID         ( p -- a ) 1608 + ;
: _RTHP.ADMISSION      ( p -- a ) 1776 + ;
: _RTHP.RUN            ( p -- a ) 2280 + ;
: _RTHP.TARGET0-A      ( p -- a ) 2432 + ;
: _RTHP.TARGET1-A      ( p -- a ) 2440 + ;
: _RTHP.TARGET-ACTIVE  ( p -- a ) 2448 + ;
: _RTHP.TARGET-PENDING ( p -- a ) 2456 + ;
: _RTHP.NEXT-REGION    ( p -- a ) 2464 + ;
: _RTHP.NEXT-OBJECT    ( p -- a ) 2472 + ;
: _RTHP.ACTIVE-DRAW    ( p -- a ) 2480 + ;
: _RTHP.MAX-DOCUMENTS  ( p -- a ) 2488 + ;
: _RTHP.SOURCE-DIR-A   ( p -- a ) 2496 + ;
: _RTHP.SOURCE-DIR-U   ( p -- a ) 2504 + ;
: _RTHP.SOURCE-DIR-USED ( p -- a ) 2512 + ;
: _RTHP.DOCUMENT-COUNT ( p -- a ) 2520 + ;
\ After a candidate's glyphs are built, ROW-DAMAGE names the rows they
\ rebuilt; every other row was copied from the acknowledged target.
: _RTHP.ROW-DAMAGE-A   ( p -- a ) 2528 + ;
: _RTHP.ROW-DAMAGE-U   ( p -- a ) 2536 + ;
: _RTHP.GLYPH-ID-MAP-A ( p -- a ) 2544 + ;
: _RTHP.GLYPH-ID-MAP-U ( p -- a ) 2552 + ;
: _RTHP.DELTA-PLAN-VALID ( p -- a ) 2560 + ;
: _RTHP.DELTA-PLAN-ACTIVE ( p -- a ) 2568 + ;
: _RTHP.DELTA-PLAN-PENDING ( p -- a ) 2576 + ;
: _RTHP.DELTA-PLAN-ACTIVE-DRAW ( p -- a ) 2584 + ;
: _RTHP.DELTA-PLAN-PENDING-DRAW ( p -- a ) 2592 + ;
: _RTHP.DELTA-PLAN-CONTROLS ( p -- a ) 2600 + ;
: _RTHP.DELTA-PLAN-GLYPHS ( p -- a ) 2608 + ;
: _RTHP.DELTA-PLAN-ATTEMPT ( p -- a ) 2616 + ;
: _RTHP.DELTA-PLAN-SOURCE-GEN ( p -- a ) 2624 + ;
: _RTHP.DELTA-PLAN-PENDING-CONTENT ( p -- a ) 2632 + ;
: _RTHP.DELTA-PLAN-ACTIVE-CONTENT ( p -- a ) 2640 + ;
: _RTHP.SOURCE-CONTENT-EPOCH ( p -- a ) 2648 + ;
: _RTHP.MAX-COLLECTION-NATIVE ( p -- a ) 2656 + ;
: _RTHP.MAX-COLLECTIONS ( p -- a ) 2664 + ;
: _RTHP.MAX-CONTROLS   ( p -- a ) 2672 + ;
: _RTHP.SOURCE-MENU-TEXT-USED ( p -- a ) 2680 + ;
: _RTHP.COLLECTION-DESCRIPTORS-A ( p -- a ) 2688 + ;
: _RTHP.COLLECTION-DESCRIPTORS-U ( p -- a ) 2696 + ;
: _RTHP.COLLECTION-DESCRIPTORS-USED ( p -- a ) 2704 + ;
: _RTHP.COLLECTION-NATIVE-A ( p -- a ) 2712 + ;
: _RTHP.COLLECTION-NATIVE-U ( p -- a ) 2720 + ;
: _RTHP.COLLECTION-NATIVE-USED ( p -- a ) 2728 + ;
: _RTHP.SOURCE-COLLECTION-COUNT ( p -- a ) 2736 + ;
: _RTHP.MENU-CONTROL-COUNT ( p -- a ) 2744 + ;
: _RTHP.COLLECTION-COUNT ( p -- a ) 2752 + ;
: _RTHP.COLLECTION-ITEMS ( p -- a ) 2760 + ;
: _RTHP.COLLECTION-UTF8 ( p -- a ) 2768 + ;
: _RTHP.MAX-COLLECTION-DESCRIPTORS ( p -- a ) 2776 + ;
: _RTHP.RUIP-Q         ( p -- a ) 2784 + ; \ 368 bytes
: _RTHP.INSTRUMENT-PLAN ( p -- a ) 3152 + ; \ 72 bytes
: _RTHP.MAX-DGRAPH-NATIVE ( p -- a ) 3224 + ;
: _RTHP.MAX-DGRAPH-DESCRIPTORS ( p -- a ) 3232 + ;
: _RTHP.MAX-INSTRUMENT-REGIONS ( p -- a ) 3240 + ;
: _RTHP.MAX-INSTRUMENTS ( p -- a ) 3248 + ;
: _RTHP.DGRAPH-DESCRIPTORS-A ( p -- a ) 3256 + ;
: _RTHP.DGRAPH-DESCRIPTORS-U ( p -- a ) 3264 + ;
: _RTHP.DGRAPH-DESCRIPTORS-USED ( p -- a ) 3272 + ;
: _RTHP.DGRAPH-NATIVE-A ( p -- a ) 3280 + ;
: _RTHP.DGRAPH-NATIVE-U ( p -- a ) 3288 + ;
: _RTHP.DGRAPH-NATIVE-USED ( p -- a ) 3296 + ;
: _RTHP.SOURCE-DGRAPH-COUNT ( p -- a ) 3304 + ;
: _RTHP.INSTRUMENT-REGIONS-A ( p -- a ) 3312 + ;
: _RTHP.INSTRUMENT-REGIONS-U ( p -- a ) 3320 + ;
: _RTHP.INSTRUMENTS-A ( p -- a ) 3328 + ;
: _RTHP.INSTRUMENTS-U ( p -- a ) 3336 + ;
: _RTHP.INSTRUMENT-UNITS-A ( p -- a ) 3344 + ;
: _RTHP.INSTRUMENT-UNITS-U ( p -- a ) 3352 + ;
: _RTHP.INSTRUMENT-UNITS-USED ( p -- a ) 3360 + ;
: _RTHP.INSTRUMENT-CORR-A ( p -- a ) 3368 + ;
: _RTHP.INSTRUMENT-CORR-U ( p -- a ) 3376 + ;
: _RTHP.INSTRUMENT-REGION-COUNT ( p -- a ) 3384 + ;
: _RTHP.INSTRUMENT-COUNT ( p -- a ) 3392 + ;
: _RTHP.INSTRUMENT-LAST-REGION ( p -- a ) 3400 + ;
: _RTHP.INSTRUMENT-LAST ( p -- a ) 3408 + ;
: _RTHP.INSTRUMENT-CLAIM-COUNT ( p -- a ) 3416 + ;
: _RTHP.BASE-CLAIMS-USED ( p -- a ) 3424 + ;
: _RTHP.MENU-CLAIMS     ( p -- a ) 3432 + ;
: _RTHP.ACTIVE-FACTS   ( p -- a ) 3440 + ; \ 48 bytes
: _RTHP.PENDING-FACTS  ( p -- a ) 3488 + ; \ 48 bytes
: _RTHP.FACTS-INDEX0-A ( p -- a ) 3536 + ;
: _RTHP.FACTS-INDEX1-A ( p -- a ) 3544 + ;
: _RTHP.FACTS-INDEX-U  ( p -- a ) 3552 + ;
\ The completed draw last found unable to be shown rich; it is not built
\ again, and a newer completed draw is tried.
: _RTHP.REFUSED-DRAW   ( p -- a ) 3560 + ;

: _RTHP.MAX-STATUS-NATIVE        ( p -- a ) 3568 + ;
: _RTHP.MAX-STATICS              ( p -- a ) 3576 + ;
: _RTHP.STATUS-DESCRIPTORS-A     ( p -- a ) 3584 + ;
: _RTHP.STATUS-DESCRIPTORS-U     ( p -- a ) 3592 + ;
: _RTHP.STATUS-DESCRIPTORS-USED  ( p -- a ) 3600 + ;
: _RTHP.STATUS-NATIVE-A          ( p -- a ) 3608 + ;
: _RTHP.STATUS-NATIVE-U          ( p -- a ) 3616 + ;
: _RTHP.STATUS-NATIVE-USED       ( p -- a ) 3624 + ;
: _RTHP.STATICS-A                ( p -- a ) 3632 + ;
: _RTHP.STATICS-U                ( p -- a ) 3640 + ;
: _RTHP.STATIC-TEXT-A            ( p -- a ) 3648 + ;
: _RTHP.STATIC-TEXT-U            ( p -- a ) 3656 + ;
: _RTHP.STATIC-TEXT-USED         ( p -- a ) 3664 + ;
: _RTHP.STATIC-CORR-A            ( p -- a ) 3672 + ;
: _RTHP.STATIC-CORR-U            ( p -- a ) 3680 + ;
: _RTHP.STATIC-COUNT             ( p -- a ) 3688 + ;
: _RTHP.STATIC-LAST              ( p -- a ) 3696 + ;
: _RTHP.STATIC-BASE-CLAIMS       ( p -- a ) 3704 + ;
: _RTHP.STATIC-PLAN ( p -- a ) 3712 + ; \ 144 bytes

: _RTHP.MAX-FIELD-NATIVE         ( p -- a ) 3856 + ;
: _RTHP.MAX-FIELDS               ( p -- a ) 3864 + ;
: _RTHP.FIELD-DESCRIPTORS-A      ( p -- a ) 3872 + ;
: _RTHP.FIELD-DESCRIPTORS-U      ( p -- a ) 3880 + ;
: _RTHP.FIELD-DESCRIPTORS-USED   ( p -- a ) 3888 + ;
: _RTHP.FIELD-NATIVE-A           ( p -- a ) 3896 + ;
: _RTHP.FIELD-NATIVE-U           ( p -- a ) 3904 + ;
: _RTHP.FIELD-NATIVE-USED        ( p -- a ) 3912 + ;
: _RTHP.FIELD-COUNT              ( p -- a ) 3920 + ;
: _RTHP.FIELD-ITEMS              ( p -- a ) 3928 + ;
: _RTHP.FIELD-UTF8               ( p -- a ) 3936 + ;
: _RTHP.FIELD-BASE-CONTROLS      ( p -- a ) 3944 + ;
: _RTHP.FIELD-BASE-TEXT          ( p -- a ) 3952 + ;
: _RTHP.FIELD-BASE-CLAIMS        ( p -- a ) 3960 + ;
: _RTHP.FIELD-REFUSED            ( p -- a ) 3968 + ;

\ Independent SERIES namespace and immutable sample storage.
: _RTHP.MAX-SERIES                ( p -- a ) 3976 + ;
: _RTHP.SERIES-A                  ( p -- a ) 3984 + ;
: _RTHP.SERIES-U                  ( p -- a ) 3992 + ;
: _RTHP.SERIES-SAMPLES-A          ( p -- a ) 4000 + ;
: _RTHP.SERIES-SAMPLES-U          ( p -- a ) 4008 + ;
: _RTHP.SERIES-SAMPLES-USED       ( p -- a ) 4016 + ;
: _RTHP.SERIES-CORR-A             ( p -- a ) 4024 + ;
: _RTHP.SERIES-CORR-U             ( p -- a ) 4032 + ;
: _RTHP.SERIES-COUNT              ( p -- a ) 4040 + ;
: _RTHP.SERIES-LAST               ( p -- a ) 4048 + ;
: _RTHP.SERIES-SLOTS              ( p -- a ) 4056 + ;
: _RTHP.SERIES-CHUNKS             ( p -- a ) 4064 + ;
: _RTHP.SERIES-HISTORY-MAX        ( p -- a ) 4072 + ;
: _RTHP.SERIES-CHUNK-MAX          ( p -- a ) 4080 + ;
: _RTHP.SERIES-CHUNK-BYTES-MAX    ( p -- a ) 4088 + ;
: _RTHP.WAVEFORM-COUNT            ( p -- a ) 4096 + ;
: _RTHP.FIRST-SERIES              ( p -- a ) 4104 + ;
: _RTHP.NEXT-SERIES               ( p -- a ) 4112 + ;
: _RTHP.OMITTED-GRAPHS-A          ( p -- a ) 4120 + ;
: _RTHP.OMITTED-GRAPHS-U          ( p -- a ) 4128 + ;
: _RTHP.OMITTED-GRAPHS-USED       ( p -- a ) 4136 + ;
: _RTHP.SERIES-PLAN ( p -- a ) 4144 + ; \ 48 bytes
: _RTHP.EXTENSION ( p -- a ) 4192 + ; \ optional caller-owned extension64
\ True while an owner open this producer queued awaits the terminal's answer.
: _RTHP.OPEN-QUEUED ( p -- a ) 4200 + ;
\ Terminal space.  NEED is what the latest admitted or refused candidate
\ needs, HELD what the owner holds, ASK what this producer asks the terminal
\ for; each is one RTE-QUOTA-SIZE set.  ASK and NEED persist while a request
\ for more space waits, and RESUME-PHASE is the phase to return to when the
\ terminal answers.  A draw the terminal refused more space for is never
\ asked for again.
: _RTHP.RESUME-PHASE ( p -- a ) 4208 + ;
: _RTHP.SPACE-REFUSED-DRAW ( p -- a ) 4216 + ;
: _RTHP.NEED ( p -- a ) 4224 + ;
: _RTHP.HELD ( p -- a ) 4288 + ;
: _RTHP.ASK ( p -- a ) 4352 + ;
\ The fallback record read by RTHP-FALLBACK@: how many draws had a part
\ stay CELL, the latest such draw, which parts, why, and the quotas it
\ needed against those held (or bytes, when Desk's own memory refused).
: _RTHP.FALLBACKS ( p -- a ) 4416 + ;
: _RTHP.FALLBACK-DRAW ( p -- a ) 4424 + ;
: _RTHP.FALLBACK-PARTS ( p -- a ) 4432 + ;
: _RTHP.FALLBACK-REASON ( p -- a ) 4440 + ;
: _RTHP.FALLBACK-ASKED ( p -- a ) 4448 + ;
: _RTHP.FALLBACK-HELD ( p -- a ) 4512 + ;
: _RTHP.FALLBACK-BYTES-ASKED ( p -- a ) 4576 + ;
: _RTHP.FALLBACK-BYTES-HELD ( p -- a ) 4584 + ;
\ The memory source the arena grows into (0: the caller's fixed arena), and
\ an earlier arena kept only while the frame on screen has its bank there.
: _RTHP.MEMORY ( p -- a ) 4592 + ;
: _RTHP.KEPT-ARENA-A ( p -- a ) 4600 + ;
: _RTHP.KEPT-ARENA-U ( p -- a ) 4608 + ;
: _RTHP.KEPT-BANK-A ( p -- a ) 4616 + ;
: _RTHP.KEPT-BANK-U ( p -- a ) 4624 + ;
\ Pictures.  The arena's picture bank holds MAX-PICTURES descriptors, of
\ which the latest capture described PICTURE-COUNT under PICTURE-ASK: the
\ surface's pixels and the terminal's limits on one picture.
: _RTHP.MAX-PICTURES ( p -- a ) 4632 + ;
: _RTHP.PICTURES-A ( p -- a ) 4640 + ;
: _RTHP.PICTURES-U ( p -- a ) 4648 + ;
: _RTHP.PICTURE-COUNT ( p -- a ) 4656 + ;
: _RTHP.PICTURE-ASK ( p -- a ) 4664 + ; \ UPICSN-ASK-SIZE bytes
\ The pictures the terminal holds for the owner: a table from the memory
\ source with an entry for each resource the owner holds room for, and the
\ next resource ID, above every one the owner generation has used.
: _RTHP.RESOURCES-A ( p -- a ) 4736 + ;
: _RTHP.RESOURCES-U ( p -- a ) 4744 + ;
: _RTHP.NEXT-RESOURCE ( p -- a ) 4752 + ;
\ The one job the picture lane runs, as RTE-JOB-, the table entry it
\ uploads or drops, and the block an upload reads each chunk into: from the
\ memory source at its first chunk, the size of its largest, until it ends.
: _RTHP.LANE-JOB ( p -- a ) 4760 + ;
: _RTHP.LANE-ENTRY ( p -- a ) 4768 + ;
: _RTHP.CHUNK-A ( p -- a ) 4776 + ;
: _RTHP.CHUNK-U ( p -- a ) 4784 + ;
\ Counts every change in what a frame can show of its pictures: a pixel
\ size answered, or a picture newly held.  A frame built before is stale.
: _RTHP.PICTURE-EPOCH ( p -- a ) 4792 + ;
\ The draw in which the lane last failed; it starts nothing more in it.
: _RTHP.LANE-HOLD-DRAW ( p -- a ) 4800 + ;
\ Room for pictures.  LANE-REFUSED says why the terminal gave the lane no
\ more room, as RTHP-WHY-, and is zero until it does.  The lane then asks
\ for none until a build describes no picture, and each copy keeps within
\ LANE-BUDGET bytes, the room the owner held and no picture used then;
\ zero while no budget applies.  A picture that goes sets LANE-SHRINK
\ until the room it held is given back.
: _RTHP.LANE-REFUSED ( p -- a ) 4808 + ;
: _RTHP.LANE-BUDGET ( p -- a ) 4816 + ;
: _RTHP.LANE-SHRINK ( p -- a ) 4824 + ;
\ The lane's own request for room while the terminal decides: 1 for more,
\ 2 to give some back.
: _RTHP.LANE-RESIZE ( p -- a ) 4832 + ;
\ Nonzero once the lane failed to send a picture a build wanted, until it
\ starts sending one or a build describes no picture.  The rich side then
\ takes no picture, so CELL shows each one.
: _RTHP.LANE-FAILED ( p -- a ) 4840 + ;
\ The draw whose planes the visible runs of the glyph banks were planned
\ from, with the candidate's claims; zero while they hold no such plan.
\ An extension planning the same draw may take runs from them.
: _RTHP.GLYPH-DRAW ( p -- a ) 4848 + ;
\ The rest of what that plan was made from: a copy of the claims, the menu
\ claims among them, the first object ID, the run text limit and the
\ surface; and what it holds, its runs and text bytes.  A later build of
\ the same draw from all of these would write the same runs.
: _RTHP.GLYPH-CLAIMS-A ( p -- a ) 4856 + ;
: _RTHP.GLYPH-CLAIMS-U ( p -- a ) 4864 + ;
: _RTHP.GLYPH-CLAIMS-USED ( p -- a ) 4872 + ;
: _RTHP.GLYPH-MENUS ( p -- a ) 4880 + ;
: _RTHP.GLYPH-FIRST ( p -- a ) 4888 + ;
: _RTHP.GLYPH-LIMIT ( p -- a ) 4896 + ;
: _RTHP.GLYPH-COLS ( p -- a ) 4904 + ;
: _RTHP.GLYPH-ROWS ( p -- a ) 4912 + ;
: _RTHP.GLYPH-RUNS ( p -- a ) 4920 + ;
: _RTHP.GLYPH-TEXT ( p -- a ) 4928 + ;
\ Dialogs.  A document shows at most one; a dialog lowers to a DIALOG and
\ a BUTTON for each of its buttons, after the fields.  MAX-DIALOGS bounds
\ the descriptors and MAX-DIALOG-CONTROLS the controls the native bank can
\ hold: every dialog model holds its header and each button its record.
: _RTHP.MAX-DIALOG-NATIVE        ( p -- a ) 4936 + ;
: _RTHP.MAX-DIALOGS              ( p -- a ) 4944 + ;
: _RTHP.MAX-DIALOG-CONTROLS      ( p -- a ) 4952 + ;
: _RTHP.DIALOG-DESCRIPTORS-A     ( p -- a ) 4960 + ;
: _RTHP.DIALOG-DESCRIPTORS-U     ( p -- a ) 4968 + ;
: _RTHP.DIALOG-DESCRIPTORS-USED  ( p -- a ) 4976 + ;
: _RTHP.DIALOG-NATIVE-A          ( p -- a ) 4984 + ;
: _RTHP.DIALOG-NATIVE-U          ( p -- a ) 4992 + ;
: _RTHP.DIALOG-NATIVE-USED       ( p -- a ) 5000 + ;
: _RTHP.DIALOG-COUNT             ( p -- a ) 5008 + ;
: _RTHP.DIALOG-CONTROLS          ( p -- a ) 5016 + ;
: _RTHP.DIALOG-BASE-CONTROLS     ( p -- a ) 5024 + ;
: _RTHP.DIALOG-BASE-TEXT         ( p -- a ) 5032 + ;
: _RTHP.DIALOG-BASE-CLAIMS       ( p -- a ) 5040 + ;
: _RTHP.DIALOG-REFUSED           ( p -- a ) 5048 + ;
: _RTHP.DIALOG-UTF8              ( p -- a ) 5056 + ;
\ The seals of the pending and the acknowledged target banks, with every
\ check on (check-mode.f): 0, or the seal _RTHP-BANK-SEAL took of the bank
\ when its frame was sent.
: _RTHP.PENDING-SEAL             ( p -- a ) 5064 + ;
: _RTHP.ACTIVE-SEAL              ( p -- a ) 5072 + ;
\ Whether the candidate was built for Desk's shell, which plans the runs of
\ its own regions and admits its batch (RTHPX-PREPARE): such a candidate has
\ no runs or admission of its own.  BASE-Z is the Z of the candidate's one
\ region, above its instrument regions (_RTHP-BASE-LAYER!).
: _RTHP.SHELL-BUILT              ( p -- a ) 5080 + ;
: _RTHP.BASE-Z                   ( p -- a ) 5088 + ;
5096 CONSTANT RTHP-SIZE
40 CONSTANT _RTHP-STATIC-CORR-SIZE
80 CONSTANT _RTHP-SERIES-CORR-SIZE
\ An omitted graph: the cells it paints, row col row1 col1, and the token
\ of its document.
40 CONSTANT _RTHP-OMITTED-GRAPH-SIZE

: RTHP-BYTES  ( -- bytes )  RTHP-SIZE ;

0 CONSTANT _RTHP-PH-WAIT
1 CONSTANT _RTHP-PH-OPENING
2 CONSTANT _RTHP-PH-READY-START
3 CONSTANT _RTHP-PH-START-SEALED
4 CONSTANT _RTHP-PH-READY-REVEAL
5 CONSTANT _RTHP-PH-REVEAL-SEALED
6 CONSTANT _RTHP-PH-LIVE
7 CONSTANT _RTHP-PH-READY-DELTA
8 CONSTANT _RTHP-PH-DELTA-SEALED
\ A completed draw that cannot be shown rich replaces the rich frame with an
\ empty one: a hidden START with no operations, then its reveal carried with
\ the CELL frame.  BLANK is then an open owner with nothing retained, where
\ CELL shows every draw until a newer one can be shown rich again.
9 CONSTANT _RTHP-PH-READY-BLANK
10 CONSTANT _RTHP-PH-BLANK-SEALED
11 CONSTANT _RTHP-PH-READY-BLANK-REVEAL
12 CONSTANT _RTHP-PH-BLANK-REVEAL-SEALED
13 CONSTANT _RTHP-PH-BLANK
14 CONSTANT _RTHP-PH-FAULT
\ The frame does not fit what the owner holds, and the terminal has been
\ asked for more.  Nothing is captured meanwhile.
15 CONSTANT _RTHP-PH-RESIZING

\ Parts of a draw that stayed CELL, and why, as RTHP-FALLBACK@ reports
\ them.  Several parts of one draw combine; the reason is the latest.
1 CONSTANT RTHP-PART-FRAME
2 CONSTANT RTHP-PART-SHELL
4 CONSTANT RTHP-PART-STATICS
8 CONSTANT RTHP-PART-FIELDS
16 CONSTANT RTHP-PART-INSTRUMENTS
32 CONSTANT RTHP-PART-COLLECTIONS
64 CONSTANT RTHP-PART-GRAPHS
128 CONSTANT RTHP-PART-PICTURES
256 CONSTANT RTHP-PART-DIALOGS
\ The terminal said no to more space.
1 CONSTANT RTHP-WHY-REFUSED
\ More than the terminal offers at all, or a kind it does not take.
2 CONSTANT RTHP-WHY-LIMIT
\ Desk's own memory had no room.
3 CONSTANT RTHP-WHY-MEMORY
4 CONSTANT RTHP-WHY-OTHER
\ A check found the rich path's memory damaged; CHK-DAMAGE names what
\ (check-mode.f).
5 CONSTANT RTHP-WHY-DAMAGE

\ A table entry of the pictures the terminal holds: its resource ID, zero
\ when free, the copy's size in pixels and the bytes the owner holds for
\ it, its decoded size, whether it is still uploading, the format it was
\ sent in, and the picture it is a copy of: its document, element,
\ revision and root key, which tells an element's figures apart.  A copy
\ is that picture at that size and format, so nothing else is compared.
: _RTHP-RS.ID        ( entry -- a )      ;
: _RTHP-RS.WIDTH     ( entry -- a )  8 + ;
: _RTHP-RS.HEIGHT    ( entry -- a ) 16 + ;
: _RTHP-RS.BYTES     ( entry -- a ) 24 + ;
: _RTHP-RS.STATE     ( entry -- a ) 32 + ;
: _RTHP-RS.FORMAT    ( entry -- a ) 40 + ;
: _RTHP-RS.DOCUMENT  ( entry -- a ) 48 + ;
: _RTHP-RS.INDEX     ( entry -- a ) 56 + ;
: _RTHP-RS.REVISION  ( entry -- a ) 64 + ;
: _RTHP-RS.KEY       ( entry -- a ) 72 + ;
80 CONSTANT _RTHP-RESOURCE-SIZE
1 CONSTANT _RTHP-RS-UPLOADING
2 CONSTANT _RTHP-RS-HELD
\ An upload the lane stopped because its picture no longer shows.
3 CONSTANT _RTHP-RS-CANCELLED

0 CONSTANT _RTHP-STAGE-NONE
1 CONSTANT _RTHP-STAGE-FULL
2 CONSTANT _RTHP-STAGE-UNCHANGED

: _RTHP-TB.OWNER       ( bank -- a )      ;
: _RTHP-TB.GENERATION  ( bank -- a )  8 + ;
: _RTHP-TB.COLS        ( bank -- a ) 16 + ;
: _RTHP-TB.ROWS        ( bank -- a ) 24 + ;
: _RTHP-TB.COUNT       ( bank -- a ) 32 + ;
: _RTHP-TB.DRAW        ( bank -- a ) 40 + ;
: _RTHP-TB.SOURCE-GEN  ( bank -- a ) 48 + ;
: _RTHP-TB.PHYSICAL-GEN ( bank -- a ) 56 + ;
: _RTHP-TB.REGION      ( bank -- a ) 64 + ;
: _RTHP-TB.FIRST-OBJECT ( bank -- a ) 72 + ;
: _RTHP-TB.CONTROL-COUNT ( bank -- a ) 80 + ;
: _RTHP-TB.GLYPH-SLOT-COUNT ( bank -- a ) 88 + ;
: _RTHP-TB.SOURCE-TEXT-USED ( bank -- a ) 96 + ;
: _RTHP-TB.GLYPH-TEXT-USED ( bank -- a ) 104 + ;
: _RTHP-TB.PACKED-BYTES ( bank -- a ) 112 + ;
: _RTHP-TB.GLYPH-RUN-LIMIT ( bank -- a ) 120 + ;
: _RTHP-TB.CONTENT-EPOCH ( bank -- a ) 128 + ;
: _RTHP-TB.MENU-CONTROL-COUNT ( bank -- a ) 136 + ;
: _RTHP-TB.COLLECTION-COUNT ( bank -- a ) 144 + ;
: _RTHP-TB.COLLECTION-ITEMS ( bank -- a ) 152 + ;
: _RTHP-TB.COLLECTION-UTF8 ( bank -- a ) 160 + ;
: _RTHP-TB.MENU-TEXT-USED ( bank -- a ) 168 + ;
: _RTHP-TB.INSTRUMENT-REGION-COUNT ( bank -- a ) 176 + ;
: _RTHP-TB.INSTRUMENT-COUNT ( bank -- a ) 184 + ;
: _RTHP-TB.INSTRUMENT-UNIT-BYTES ( bank -- a ) 192 + ;
: _RTHP-TB.VALID       ( bank -- a ) 200 + ;
: _RTHP-TB.DOCUMENT-COUNT ( bank -- a ) 208 + ;
: _RTHP-TB.PROJECTION-RECTS ( bank -- a ) 216 + ;

0x3354475450485452 CONSTANT _RTHP-TARGET-VALID-MAGIC  \ "RTHPTGT3"

: _RTHP-TB.STATIC-COUNT ( bank -- a ) 224 + ;
: _RTHP-TB.STATIC-TEXT-BYTES ( bank -- a ) 232 + ;

: _RTHP-TB.FIELD-COUNT ( bank -- a ) 240 + ;
: _RTHP-TB.FIELD-ITEMS ( bank -- a ) 248 + ;
: _RTHP-TB.FIELD-UTF8 ( bank -- a ) 256 + ;

: _RTHP-TB.SERIES-COUNT            ( bank -- a ) 264 + ;
: _RTHP-TB.FIRST-SERIES            ( bank -- a ) 272 + ;
: _RTHP-TB.SERIES-SAMPLE-BYTES     ( bank -- a ) 280 + ;
: _RTHP-TB.SERIES-SLOTS            ( bank -- a ) 288 + ;
: _RTHP-TB.SERIES-CHUNKS           ( bank -- a ) 296 + ;
: _RTHP-TB.SERIES-HISTORY-MAX      ( bank -- a ) 304 + ;
: _RTHP-TB.SERIES-CHUNK-MAX        ( bank -- a ) 312 + ;
: _RTHP-TB.SERIES-CHUNK-BYTES-MAX  ( bank -- a ) 320 + ;
: _RTHP-TB.WAVEFORM-COUNT          ( bank -- a ) 328 + ;
\ The producer's PICTURE-EPOCH when the bank's candidate was captured.
: _RTHP-TB.PICTURE-EPOCH           ( bank -- a ) 336 + ;
\ The dialog lane: its controls, the dialogs among them, and their text.
: _RTHP-TB.DIALOG-CONTROLS         ( bank -- a ) 344 + ;
: _RTHP-TB.DIALOG-COUNT            ( bank -- a ) 352 + ;
: _RTHP-TB.DIALOG-UTF8             ( bank -- a ) 360 + ;

368 CONSTANT _RTHP-TARGET-BANK-HEADER-SIZE
32 CONSTANT _RTHP-PROJECTION-RECT-SIZE

: _RTHP-TE.ID          ( entry -- a )      ;
: _RTHP-TE.ROW         ( entry -- a )  8 + ;
: _RTHP-TE.COL         ( entry -- a ) 16 + ;
: _RTHP-TE.KIND        ( entry -- a ) 24 + ;

: _RTHP-TE.REVISION    ( entry -- a ) 32 + ;
: _RTHP-TE.INTENTS     ( entry -- a ) 40 + ;

48 CONSTANT _RTHP-TARGET-ENTRY-SIZE

: _RTHP-TARGET-ENTRY  ( index bank -- entry )
    SWAP _RTHP-TARGET-ENTRY-SIZE *
    _RTHP-TARGET-BANK-HEADER-SIZE + + ;

\ Facts a successful DELTA comparison proved about the bank it built.  BANK
\ names that exact target bank and is zero when no facts are kept.  Each
\ target bank also owns one arena annex for its identity-sorted control index.
: _RTHP-KF.BANK        ( facts -- a )      ;
: _RTHP-KF.BASE        ( facts -- a )  8 + ;
: _RTHP-KF.VISIBLE     ( facts -- a ) 16 + ;
: _RTHP-KF.SLOTS       ( facts -- a ) 24 + ;
: _RTHP-KF.CONTROLS    ( facts -- a ) 32 + ;
: _RTHP-KF.LAST-ID     ( facts -- a ) 40 + ;

48 CONSTANT _RTHP-KF-SIZE

: _RTHP-FACTS-INDEX  ( bank producer -- a )
    DUP _RTHP.TARGET0-A @ ROT = IF
        _RTHP.FACTS-INDEX0-A @
    ELSE
        _RTHP.FACTS-INDEX1-A @
    THEN ;

\ =====================================================================
\  Checked arena sizing
\ =====================================================================

: _RTHP-U32+?  ( a b -- sum flag )
    OVER + DUP ROT U< 0= OVER 0xFFFFFFFF U> 0= AND ;

\ Whether N fits a signed 32-bit field, as a retained origin does.
: _RTHP-I32?  ( n -- flag )  -2147483648 2147483648 WITHIN ;

: _RTHP-U32*?  ( a b -- product flag )
    UM* DUP IF 2DROP 0 0 EXIT THEN DROP
    DUP 0xFFFFFFFF U> 0= ;

: _RTHP-U+?  ( a b -- sum flag )
    OVER + DUP ROT U< 0= ;

: _RTHP-UMIN  ( a b -- min )
    2DUP U< IF DROP ELSE NIP THEN ;

: _RTHP-UMAX  ( a b -- max )
    2DUP U< IF NIP ELSE DROP THEN ;

: _RTHP-ALIGN8?  ( u -- aligned flag )
    7 _RTHP-U32+? 0= IF DROP 0 0 EXIT THEN
    7 INVERT AND -1 ;

: _RTHP-POS-U32?  ( u -- flag )
    DUP 0> SWAP 0xFFFFFFFF U> 0= AND ;

: _RTHP-U32?  ( u -- flag )
    DUP 0< IF DROP 0 EXIT THEN
    0xFFFFFFFF U> 0= ;

\ A valid TABSET consumes one 80-byte root and every nested TAB consumes at
\ least the aligned encoding for a one-byte label and no shortcut (48 bytes).
\ For any nonempty native collection bank, one root plus all remaining bytes
\ at that minimum child density is therefore a safe caller-derived upper
\ bound for the number of semantic CONTROL values it can produce.  This is a
\ storage bound only; the frozen descriptors/native entries still determine
\ the exact root and child counts admitted for a draw.
: RTHP-COLLECTION-CONTROL-CAPACITY  ( native-bytes -- controls|0 )
    DUP _RTHP-POS-U32? 0= IF DROP 0 EXIT THEN
    DUP USCOL-TABSET-FIXED-SIZE U< IF DROP 0 EXIT THEN
    USCOL-TABSET-FIXED-SIZE -
    1 0 USCOL-TAB-BYTES DUP 0= IF 2DROP 0 EXIT THEN
    / 1 _RTHP-U32+? 0= IF DROP 0 THEN ;

: _RTHP-TEXT-COLLECTION-CONTROL-KIND?  ( rte-kind -- flag )
    DUP RTE-CONTROL-TEXT-AREA =
    SWAP RTE-CONTROL-TEXT-GRID = OR ;

\ A root whose content is one semantic value: STX1 text, ITM1 items, or a
\ DOC1 document.
: _RTHP-CONTENT-CONTROL-KIND?  ( rte-kind -- flag )
    DUP _RTHP-TEXT-COLLECTION-CONTROL-KIND?
    OVER RTE-CONTROL-ITEM-VIEW = OR
    SWAP RTE-CONTROL-DOCUMENT = OR ;

: _RTHP-COLLECTION-CONTROL-KIND?  ( rte-kind -- flag )
    DUP _RTHP-CONTENT-CONTROL-KIND? IF DROP -1 EXIT THEN
    DUP RTE-CONTROL-TABSET =
    SWAP RTE-CONTROL-TAB = OR ;

: _RTHP-COLLECTION-ROOT-KIND?  ( rte-kind -- flag )
    DUP _RTHP-CONTENT-CONTROL-KIND? IF DROP -1 EXIT THEN
    RTE-CONTROL-TABSET = ;

: _RTHP-DIALOG-KIND?  ( rte-kind -- flag )
    DUP RTE-CONTROL-DIALOG = SWAP RTE-CONTROL-BUTTON = OR ;

\ The retained control kinds that can be hit-test targets.  A dialog is one
\ only for the wheel; its buttons take presses.
: _RTHP-TARGET-KIND?  ( rte-kind -- flag )
    DUP RTE-CONTROL-MENU = OVER RTE-CONTROL-MENU-ITEM = OR
    OVER RTE-CONTROL-TAB = OR
    OVER RTE-CONTROL-FIELD = OR
    OVER RTE-CONTROL-BUTTON = OR
    OVER RTE-CONTROL-DIALOG = OR
    SWAP _RTHP-CONTENT-CONTROL-KIND? OR ;

\ Which retained control kinds accept which reported intent.
: _RTHP-INTENT-SUITS?  ( intent rte-kind -- flag )
    SWAP CASE
        RTE-INTENT-ACTIVATE OF
            DUP RTE-CONTROL-MENU = OVER RTE-CONTROL-MENU-ITEM = OR
            OVER RTE-CONTROL-TAB = OR OVER RTE-CONTROL-BUTTON = OR
            SWAP RTE-CONTROL-FIELD = OR
        ENDOF
        RTE-INTENT-ADJUST OF RTE-CONTROL-FIELD = ENDOF
        RTE-INTENT-EXTEND OF
            DUP RTE-CONTROL-TEXT-AREA = SWAP RTE-CONTROL-FIELD = OR
        ENDOF
        RTE-INTENT-FOLLOW OF
            DUP RTE-CONTROL-TEXT-AREA = SWAP RTE-CONTROL-DOCUMENT = OR
        ENDOF
        RTE-INTENT-PLACE OF
            DUP _RTHP-TEXT-COLLECTION-CONTROL-KIND? SWAP RTE-CONTROL-FIELD = OR
        ENDOF
        RTE-INTENT-SCROLL OF
            DUP _RTHP-CONTENT-CONTROL-KIND? SWAP RTE-CONTROL-DIALOG = OR
        ENDOF
        RTE-INTENT-SELECT OF RTE-CONTROL-ITEM-VIEW = ENDOF
        RTE-INTENT-OPEN OF RTE-CONTROL-ITEM-VIEW = ENDOF
        RTE-INTENT-EXPAND OF RTE-CONTROL-ITEM-VIEW = ENDOF
        RTE-INTENT-COLLAPSE OF RTE-CONTROL-ITEM-VIEW = ENDOF
        RTE-INTENT-CHECK OF RTE-CONTROL-ITEM-VIEW = ENDOF
        NIP 0 SWAP
    ENDCASE ;

: _RTHP-KIND-INTENTS ( rte-kind -- mask )
    0 SWAP 12 1 DO
        I OVER _RTHP-INTENT-SUITS? IF SWAP 1 I LSHIFT OR SWAP THEN
    LOOP DROP ;

VARIABLE _RTHP-B-FIELD-NATIVE
VARIABLE _RTHP-B-FIELDS
VARIABLE _RTHP-B-DIALOG-NATIVE
VARIABLE _RTHP-B-DIALOGS
VARIABLE _RTHP-B-DIALOG-CONTROLS
VARIABLE _RTHP-B-STATUS-NATIVE
VARIABLE _RTHP-B-STATUS-STATICS
VARIABLE _RTHP-B-PICTURES
VARIABLE _RTHP-B-STATICS
VARIABLE _RTHP-B-RECORDS
VARIABLE _RTHP-B-DOCUMENTS
VARIABLE _RTHP-B-TEXT
VARIABLE _RTHP-B-COLLECTION-NATIVE
VARIABLE _RTHP-B-DGRAPH-NATIVE
VARIABLE _RTHP-B-COLLECTION-DESCRIPTORS
VARIABLE _RTHP-B-COLLECTIONS
VARIABLE _RTHP-B-DGRAPH-DESCRIPTORS
VARIABLE _RTHP-B-SERIES
VARIABLE _RTHP-B-INSTRUMENTS
VARIABLE _RTHP-B-INSTRUMENT-REGIONS
VARIABLE _RTHP-B-CONTROLS
VARIABLE _RTHP-B-CLAIMS
VARIABLE _RTHP-B-CONTROL-BYTES
VARIABLE _RTHP-B-COLS
VARIABLE _RTHP-B-ROWS
VARIABLE _RTHP-B-CELLS
VARIABLE _RTHP-B-TOTAL
VARIABLE _RTHP-B-TARGET-BYTES

VARIABLE _RTHP-TBS-TARGETS
VARIABLE _RTHP-TBS-DOCUMENTS
VARIABLE _RTHP-TBS-CONTROLS
VARIABLE _RTHP-TBS-CONTROL-BYTES
VARIABLE _RTHP-TBS-ROWS
VARIABLE _RTHP-TBS-CELLS
VARIABLE _RTHP-TBS-TOTAL

: _RTHP-TBS-ADD  ( bytes -- flag )
    _RTHP-TBS-TOTAL @ SWAP _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-TBS-TOTAL ! -1 ;

: _RTHP-TBS-MUL-ADD  ( count item-bytes -- flag )
    _RTHP-U32*? 0= IF DROP 0 EXIT THEN _RTHP-TBS-ADD ;

: _RTHP-TARGET-BYTES-CALC
  ( document-capacity target-capacity control-capacity control-byte-capacity cells rows -- bytes flag )
    _RTHP-TBS-ROWS ! _RTHP-TBS-CELLS ! _RTHP-TBS-CONTROL-BYTES !
    _RTHP-TBS-CONTROLS ! _RTHP-TBS-TARGETS ! _RTHP-TBS-DOCUMENTS !
    _RTHP-TARGET-BANK-HEADER-SIZE _RTHP-TBS-TOTAL !
    _RTHP-TBS-TARGETS @ _RTHP-TARGET-ENTRY-SIZE _RTHP-TBS-MUL-ADD
        0= IF 0 0 EXIT THEN
    _RTHP-TBS-CONTROLS @ RTE-CONTROL-SIZE _RTHP-TBS-MUL-ADD
        0= IF 0 0 EXIT THEN
    _RTHP-TBS-CONTROLS @ RUCP-CORRELATION-SIZE _RTHP-TBS-MUL-ADD
        0= IF 0 0 EXIT THEN
    _RTHP-TBS-CONTROL-BYTES @ _RTHP-ALIGN8?
        0= IF DROP 0 0 EXIT THEN _RTHP-TBS-ADD 0= IF 0 0 EXIT THEN
    _RTHP-TBS-CELLS @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE _RTHP-TBS-MUL-ADD
        0= IF 0 0 EXIT THEN
    _RTHP-TBS-CELLS @ RGRP-TEXT-REF-SIZE _RTHP-TBS-MUL-ADD
        0= IF 0 0 EXIT THEN
    _RTHP-TBS-CELLS @ 4 _RTHP-U32*? 0= IF DROP 0 0 EXIT THEN
        _RTHP-ALIGN8? 0= IF DROP 0 0 EXIT THEN
        _RTHP-TBS-ADD 0= IF 0 0 EXIT THEN
    _RTHP-TBS-DOCUMENTS @ RUHA-DOCUMENT-SIZE _RTHP-TBS-MUL-ADD
        0= IF 0 0 EXIT THEN
    _RTHP-TBS-ROWS @ _RTHP-ALIGN8?
        0= IF DROP 0 0 EXIT THEN _RTHP-TBS-ADD 0= IF 0 0 EXIT THEN
    _RTHP-TBS-CONTROLS @ _RTHP-PROJECTION-RECT-SIZE _RTHP-TBS-MUL-ADD
        0= IF 0 0 EXIT THEN
    _RTHP-TBS-TOTAL @ -1 ;

VARIABLE _RTHP-TBC-P

\ Immutable instrument payloads follow the ordinary packed target sections.
\ Capacity comes from the same caller bounds as the live planner; only used
\ records and unit bytes are copied.  Packed UNIT-A cells are byte offsets,
\ so neither source reuse nor moving a bank can leave borrowed pointers.
\ Each instrument also reserves one compact projection coverage rectangle.
: _RTHP-INSTRUMENT-BANK-BYTES?
  ( regions instruments unit-bytes -- bytes flag )
    _RTHP-ALIGN8? 0= IF DROP 2DROP 0 0 EXIT THEN >R
    RTE-INSTRUMENT-SIZE RUIP-CORRELATION-SIZE +
    _RTHP-PROJECTION-RECT-SIZE + _RTHP-U32*?
        0= IF 2DROP R> DROP 0 0 EXIT THEN
    R> _RTHP-U32+? 0= IF 2DROP 0 0 EXIT THEN >R
    RTE-INSTRUMENT-REGION-SIZE _RTHP-U32*?
        0= IF DROP R> DROP 0 0 EXIT THEN
    R> _RTHP-U32+? ;

: _RTHP-STATIC-BANK-BYTES? ( count text-bytes -- bytes flag )
    _RTHP-ALIGN8? 0= IF DROP DROP 0 0 EXIT THEN >R
    RTE-STATIC-SIZE _RTHP-STATIC-CORR-SIZE +
    _RTHP-PROJECTION-RECT-SIZE + _RTHP-U32*?
        0= IF DROP R> DROP 0 0 EXIT THEN
    R> _RTHP-U32+? ;

\ SERIES owns no projection rectangle: only the graph's objects cover cells.
: _RTHP-SERIES-BANK-BYTES? ( count sample-bytes -- bytes flag )
    _RTHP-ALIGN8? 0= IF DROP DROP 0 0 EXIT THEN >R
    RTE-SERIES-SIZE _RTHP-SERIES-CORR-SIZE + _RTHP-U32*?
        0= IF DROP R> DROP 0 0 EXIT THEN
    R> _RTHP-U32+? ;

: _RTHP-TARGET-BANK-BYTES?  ( producer -- bytes flag )
    _RTHP-TBC-P !
    _RTHP-TBC-P @ _RTHP.MAX-COLS @
    _RTHP-TBC-P @ _RTHP.MAX-ROWS @ _RTHP-U32*?
        0= IF DROP 0 0 EXIT THEN >R
    _RTHP-TBC-P @ _RTHP.MAX-DOCUMENTS @
    _RTHP-TBC-P @ _RTHP.MAX-CONTROLS @
    _RTHP-TBC-P @ _RTHP.MAX-CONTROLS @
    _RTHP-TBC-P @ _RTHP.MAX-TEXT @
    _RTHP-TBC-P @ _RTHP.MAX-COLLECTION-NATIVE @ _RTHP-U32+?
        0= IF DROP 2DROP DROP R> DROP 0 0 EXIT THEN
    _RTHP-TBC-P @ _RTHP.MAX-FIELD-NATIVE @ _RTHP-U32+?
        0= IF DROP 2DROP DROP R> DROP 0 0 EXIT THEN
    _RTHP-TBC-P @ _RTHP.MAX-DIALOG-NATIVE @ _RTHP-U32+?
        0= IF DROP 2DROP DROP R> DROP 0 0 EXIT THEN
    R> _RTHP-TBC-P @ _RTHP.MAX-ROWS @ _RTHP-TARGET-BYTES-CALC
        0= IF DROP 0 0 EXIT THEN >R
    _RTHP-TBC-P @ _RTHP.MAX-INSTRUMENT-REGIONS @
    _RTHP-TBC-P @ _RTHP.MAX-INSTRUMENTS @
    _RTHP-TBC-P @ _RTHP.MAX-DGRAPH-NATIVE @
        _RTHP-INSTRUMENT-BANK-BYTES? 0= IF DROP R> DROP 0 0 EXIT THEN
    R> _RTHP-U32+? 0= IF DROP 0 0 EXIT THEN >R
    _RTHP-TBC-P @ _RTHP.MAX-STATICS @
    _RTHP-TBC-P @ _RTHP.MAX-STATUS-NATIVE @ _RTHP-STATIC-BANK-BYTES?
        0= IF DROP R> DROP 0 0 EXIT THEN
    R> _RTHP-U32+? 0= IF DROP 0 0 EXIT THEN >R
    _RTHP-TBC-P @ _RTHP.MAX-SERIES @ _RTHP-TBC-P @ _RTHP.MAX-DGRAPH-NATIVE @
        _RTHP-SERIES-BANK-BYTES? 0= IF DROP R> DROP 0 0 EXIT THEN
    R> _RTHP-U32+? ;

: _RTHP-B-ADD  ( u -- flag )
    _RTHP-B-TOTAL @ SWAP _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-B-TOTAL ! -1 ;

: _RTHP-B-MUL-ADD  ( count item-bytes -- flag )
    _RTHP-U32*? 0= IF DROP 0 EXIT THEN _RTHP-B-ADD ;

: _RTHP-BYTES-BODY  ( -- bytes|0 )
    _RTHP-B-DOCUMENTS @ _RTHP-POS-U32? 0= IF 0 EXIT THEN
    _RTHP-B-RECORDS @ _RTHP-POS-U32? 0= IF 0 EXIT THEN
    _RTHP-B-TEXT @ _RTHP-POS-U32? 0= IF 0 EXIT THEN
    _RTHP-B-COLLECTION-NATIVE @ _RTHP-POS-U32? 0= IF 0 EXIT THEN
    _RTHP-B-COLLECTION-NATIVE @ 7 AND IF 0 EXIT THEN
    _RTHP-B-DGRAPH-NATIVE @ _RTHP-POS-U32? 0= IF 0 EXIT THEN
    _RTHP-B-DGRAPH-NATIVE @ 7 AND IF 0 EXIT THEN
    _RTHP-B-DGRAPH-NATIVE @ UDG-HEADER-SIZE U< IF 0 EXIT THEN
    _RTHP-B-COLLECTION-NATIVE @ USCOL-ENTRY-HEADER-SIZE /
        DUP 0= IF DROP 0 EXIT THEN _RTHP-B-COLLECTION-DESCRIPTORS !
    _RTHP-B-COLLECTION-NATIVE @ RTHP-COLLECTION-CONTROL-CAPACITY
        DUP 0= IF DROP 0 EXIT THEN _RTHP-B-COLLECTIONS !
    _RTHP-B-RECORDS @ _RTHP-B-COLLECTIONS @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN _RTHP-B-CONTROLS !
    _RTHP-B-DGRAPH-NATIVE @ UDG-HEADER-SIZE /
        _RTHP-B-RECORDS @ _RTHP-UMIN
        DUP 0= IF DROP 0 EXIT THEN _RTHP-B-DGRAPH-DESCRIPTORS !
    _RTHP-B-DGRAPH-NATIVE @ UDG-SERIES-HEADER-SIZE / _RTHP-B-SERIES !
    _RTHP-B-DGRAPH-NATIVE @ UDG-STATUS-RECORD-SIZE /
        DUP _RTHP-B-INSTRUMENTS !
    _RTHP-B-DGRAPH-DESCRIPTORS @ _RTHP-UMIN
        _RTHP-B-INSTRUMENT-REGIONS !
    _RTHP-B-STATUS-NATIVE @ _RTHP-U32? 0= IF 0 EXIT THEN
    _RTHP-B-STATUS-NATIVE @ 7 AND IF 0 EXIT THEN
    \ A static is a status field or a picture.
    _RTHP-B-PICTURES @ _RTHP-U32? 0= IF 0 EXIT THEN
    _RTHP-B-STATUS-NATIVE @ USF-HEADER-SIZE / DUP _RTHP-B-STATUS-STATICS !
    _RTHP-B-PICTURES @ _RTHP-U32+? 0= IF DROP 0 EXIT THEN _RTHP-B-STATICS !
    _RTHP-B-FIELD-NATIVE @ _RTHP-U32? 0= IF 0 EXIT THEN
    _RTHP-B-FIELD-NATIVE @ 7 AND IF 0 EXIT THEN
    _RTHP-B-FIELD-NATIVE @ UFLD-HEADER-SIZE / DUP _RTHP-B-FIELDS !
    _RTHP-B-CONTROLS @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN _RTHP-B-CONTROLS !
    _RTHP-B-DIALOG-NATIVE @ _RTHP-U32? 0= IF 0 EXIT THEN
    _RTHP-B-DIALOG-NATIVE @ 7 AND IF 0 EXIT THEN
    _RTHP-B-DIALOG-NATIVE @ UDLG-HEADER-SIZE / _RTHP-B-DIALOGS !
    _RTHP-B-DIALOG-NATIVE @ UDLG-BUTTON-HEADER-SIZE / DUP _RTHP-B-DIALOG-CONTROLS !
    _RTHP-B-CONTROLS @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN _RTHP-B-CONTROLS !
    _RTHP-B-CONTROLS @ _RTHP-B-INSTRUMENTS @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    _RTHP-B-STATICS @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN _RTHP-B-CLAIMS !
    _RTHP-B-TEXT @ _RTHP-B-COLLECTION-NATIVE @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    _RTHP-B-FIELD-NATIVE @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    _RTHP-B-DIALOG-NATIVE @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN _RTHP-B-CONTROL-BYTES !
    _RTHP-B-COLS @ _RTHP-POS-U32? 0= IF 0 EXIT THEN
    _RTHP-B-ROWS @ _RTHP-POS-U32? 0= IF 0 EXIT THEN
    _RTHP-B-COLS @ _RTHP-B-ROWS @ _RTHP-U32*?
        0= IF DROP 0 EXIT THEN DUP 0= IF DROP 0 EXIT THEN
        _RTHP-B-CELLS !
    0 _RTHP-B-TOTAL !
    _RTHP-B-DOCUMENTS @ RUHA-DOCUMENT-SIZE _RTHP-B-MUL-ADD
        0= IF 0 EXIT THEN
    _RTHP-B-RECORDS @ UMSN-RECORD-SIZE _RTHP-B-MUL-ADD
        0= IF 0 EXIT THEN
    _RTHP-B-CONTROL-BYTES @ _RTHP-ALIGN8? 0= IF DROP 0 EXIT THEN
        _RTHP-B-ADD 0= IF 0 EXIT THEN
    _RTHP-B-COLLECTION-DESCRIPTORS @ UCSN-DESCRIPTOR-SIZE
        _RTHP-B-MUL-ADD
        0= IF 0 EXIT THEN
    _RTHP-B-COLLECTION-NATIVE @ _RTHP-ALIGN8? 0= IF DROP 0 EXIT THEN
        _RTHP-B-ADD 0= IF 0 EXIT THEN
    _RTHP-B-DGRAPH-DESCRIPTORS @ UDGSN-DESCRIPTOR-SIZE
        _RTHP-B-MUL-ADD 0= IF 0 EXIT THEN
    _RTHP-B-DGRAPH-NATIVE @ _RTHP-ALIGN8? 0= IF DROP 0 EXIT THEN
        _RTHP-B-ADD 0= IF 0 EXIT THEN
    _RTHP-B-RECORDS @ RUCP-LOOKUP-ENTRY-SIZE _RTHP-B-MUL-ADD
        0= IF 0 EXIT THEN
    _RTHP-B-RECORDS @ 8 _RTHP-B-MUL-ADD 0= IF 0 EXIT THEN
    _RTHP-B-CONTROLS @ 24 _RTHP-B-MUL-ADD 0= IF 0 EXIT THEN
    _RTHP-B-CONTROLS @ 16 _RTHP-B-MUL-ADD 0= IF 0 EXIT THEN
    _RTHP-B-CONTROLS @ RTE-CONTROL-SIZE _RTHP-B-MUL-ADD
        0= IF 0 EXIT THEN
    _RTHP-B-CONTROLS @ RUCP-CORRELATION-SIZE _RTHP-B-MUL-ADD
        0= IF 0 EXIT THEN
    _RTHP-B-CLAIMS @ RUCL-CLAIM-SIZE _RTHP-B-MUL-ADD
        0= IF 0 EXIT THEN
    _RTHP-B-CLAIMS @ RUCL-CLAIM-SIZE _RTHP-B-MUL-ADD
        0= IF 0 EXIT THEN
    _RTHP-B-INSTRUMENT-REGIONS @ RTE-INSTRUMENT-REGION-SIZE
        _RTHP-B-MUL-ADD 0= IF 0 EXIT THEN
    _RTHP-B-INSTRUMENTS @ RTE-INSTRUMENT-SIZE
        _RTHP-B-MUL-ADD 0= IF 0 EXIT THEN
    _RTHP-B-DGRAPH-NATIVE @ _RTHP-ALIGN8? 0= IF DROP 0 EXIT THEN
        _RTHP-B-ADD 0= IF 0 EXIT THEN
    _RTHP-B-INSTRUMENTS @ RUIP-CORRELATION-SIZE
        _RTHP-B-MUL-ADD 0= IF 0 EXIT THEN
    _RTHP-B-SERIES @ _RTHP-B-DGRAPH-NATIVE @ _RTHP-SERIES-BANK-BYTES?
        0= IF DROP 0 EXIT THEN _RTHP-B-ADD 0= IF 0 EXIT THEN
    _RTHP-B-DGRAPH-DESCRIPTORS @ _RTHP-OMITTED-GRAPH-SIZE
        _RTHP-B-MUL-ADD 0= IF 0 EXIT THEN
    _RTHP-B-STATUS-STATICS @ USFSN-DESCRIPTOR-SIZE _RTHP-B-MUL-ADD
        0= IF 0 EXIT THEN
    _RTHP-B-PICTURES @ UPICSN-DESCRIPTOR-SIZE _RTHP-B-MUL-ADD 0= IF 0 EXIT THEN
    _RTHP-B-STATICS @ RTE-STATIC-SIZE _RTHP-STATIC-CORR-SIZE +
        _RTHP-B-MUL-ADD 0= IF 0 EXIT THEN
    _RTHP-B-STATUS-NATIVE @ 2 _RTHP-B-MUL-ADD 0= IF 0 EXIT THEN
    _RTHP-B-FIELDS @ UFLSN-DESCRIPTOR-SIZE _RTHP-B-MUL-ADD 0= IF 0 EXIT THEN
    _RTHP-B-FIELD-NATIVE @ _RTHP-B-ADD 0= IF 0 EXIT THEN
    _RTHP-B-DIALOGS @ UDLSN-DESCRIPTOR-SIZE _RTHP-B-MUL-ADD 0= IF 0 EXIT THEN
    _RTHP-B-DIALOG-NATIVE @ _RTHP-B-ADD 0= IF 0 EXIT THEN
    _RTHP-B-ROWS @ 1 _RTHP-U32+? 0= IF DROP 0 EXIT THEN
        RGRP-ROW-HEAD-SIZE _RTHP-B-MUL-ADD 0= IF 0 EXIT THEN
    _RTHP-B-CLAIMS @ 2 _RTHP-U32*? 0= IF DROP 0 EXIT THEN
        RGRP-EVENT-SIZE _RTHP-B-MUL-ADD 0= IF 0 EXIT THEN
    _RTHP-B-COLS @ 1 _RTHP-U32+? 0= IF DROP 0 EXIT THEN
        RGRP-PAIRED-DIFFERENCE-SIZE _RTHP-B-MUL-ADD 0= IF 0 EXIT THEN
    _RTHP-B-CELLS @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE _RTHP-B-MUL-ADD
        0= IF 0 EXIT THEN
    _RTHP-B-CELLS @ RGRP-TEXT-REF-SIZE _RTHP-B-MUL-ADD
        0= IF 0 EXIT THEN
    _RTHP-B-CELLS @ 4 _RTHP-U32*? 0= IF DROP 0 EXIT THEN
        _RTHP-ALIGN8? 0= IF DROP 0 EXIT THEN
        _RTHP-B-ADD 0= IF 0 EXIT THEN
    _RTHP-B-ROWS @ _RTHP-ALIGN8? 0= IF DROP 0 EXIT THEN
        _RTHP-B-ADD 0= IF 0 EXIT THEN
    _RTHP-B-CELLS @ 8 _RTHP-B-MUL-ADD 0= IF 0 EXIT THEN
    _RTHP-B-DOCUMENTS @
    _RTHP-B-CONTROLS @ _RTHP-B-CONTROLS @
        _RTHP-B-CONTROL-BYTES @ _RTHP-B-CELLS @ _RTHP-B-ROWS @
        _RTHP-TARGET-BYTES-CALC 0= IF DROP 0 EXIT THEN
    >R _RTHP-B-INSTRUMENT-REGIONS @ _RTHP-B-INSTRUMENTS @
        _RTHP-B-DGRAPH-NATIVE @ _RTHP-INSTRUMENT-BANK-BYTES?
        0= IF DROP R> DROP 0 EXIT THEN
    R> _RTHP-U32+? 0= IF DROP 0 EXIT THEN >R
    _RTHP-B-STATICS @ _RTHP-B-STATUS-NATIVE @ _RTHP-STATIC-BANK-BYTES?
        0= IF DROP R> DROP 0 EXIT THEN
    R> _RTHP-U32+? 0= IF DROP 0 EXIT THEN >R
    _RTHP-B-SERIES @ _RTHP-B-DGRAPH-NATIVE @ _RTHP-SERIES-BANK-BYTES?
        0= IF DROP R> DROP 0 EXIT THEN
    R> _RTHP-U32+? 0= IF DROP 0 EXIT THEN
        DUP _RTHP-B-TARGET-BYTES ! _RTHP-B-ADD 0= IF 0 EXIT THEN
    _RTHP-B-TARGET-BYTES @ _RTHP-B-ADD 0= IF 0 EXIT THEN
    _RTHP-B-TOTAL @ ;

: RTHP-STORAGE-BYTES
  ( max-documents max-records max-source-text max-collection-native max-data-graphics-native max-status-native max-field-native max-dialog-native max-pictures max-cols max-rows -- bytes|0 )
    _RTHP-B-ROWS ! _RTHP-B-COLS ! _RTHP-B-PICTURES !
    _RTHP-B-DIALOG-NATIVE !
    _RTHP-B-FIELD-NATIVE ! _RTHP-B-STATUS-NATIVE !
    _RTHP-B-DGRAPH-NATIVE !
    _RTHP-B-COLLECTION-NATIVE !
    _RTHP-B-TEXT ! _RTHP-B-RECORDS !
    _RTHP-B-DOCUMENTS !
    _RTHP-BYTES-BODY
    0 _RTHP-B-DOCUMENTS ! 0 _RTHP-B-RECORDS ! 0 _RTHP-B-TEXT !
    0 _RTHP-B-COLLECTION-NATIVE !
    0 _RTHP-B-DGRAPH-NATIVE ! 0 _RTHP-B-SERIES !
    0 _RTHP-B-COLLECTION-DESCRIPTORS ! 0 _RTHP-B-COLLECTIONS !
    0 _RTHP-B-DGRAPH-DESCRIPTORS ! 0 _RTHP-B-INSTRUMENTS !
    0 _RTHP-B-INSTRUMENT-REGIONS !
    0 _RTHP-B-CONTROLS ! 0 _RTHP-B-CLAIMS !
    0 _RTHP-B-CONTROL-BYTES !
    0 _RTHP-B-COLS ! 0 _RTHP-B-ROWS !
    0 _RTHP-B-CELLS ! 0 _RTHP-B-TOTAL ! 0 _RTHP-B-TARGET-BYTES !
    0 _RTHP-B-STATUS-NATIVE ! 0 _RTHP-B-STATICS !
    0 _RTHP-B-STATUS-STATICS ! 0 _RTHP-B-PICTURES !
    0 _RTHP-B-FIELD-NATIVE ! 0 _RTHP-B-FIELDS !
    0 _RTHP-B-DIALOG-NATIVE ! 0 _RTHP-B-DIALOGS !
    0 _RTHP-B-DIALOG-CONTROLS ! ;

\ =====================================================================
\  Construction and deterministic arena layout
\ =====================================================================

VARIABLE _RTHP-I-ADAPTER
VARIABLE _RTHP-I-FACADE
VARIABLE _RTHP-I-ARENA
VARIABLE _RTHP-I-ARENA-U
VARIABLE _RTHP-I-DOCUMENTS
VARIABLE _RTHP-I-RECORDS
VARIABLE _RTHP-I-TEXT
VARIABLE _RTHP-I-COLLECTION-NATIVE
VARIABLE _RTHP-I-FIELD-NATIVE
VARIABLE _RTHP-I-DIALOG-NATIVE
VARIABLE _RTHP-I-STATUS-NATIVE
VARIABLE _RTHP-I-PICTURES
VARIABLE _RTHP-I-DGRAPH-NATIVE
VARIABLE _RTHP-I-COLS
VARIABLE _RTHP-I-ROWS
VARIABLE _RTHP-I-OWNER
VARIABLE _RTHP-I-GEN
VARIABLE _RTHP-I-REGION
VARIABLE _RTHP-I-FIRST
VARIABLE _RTHP-I-FIRST-SERIES
VARIABLE _RTHP-I-P
VARIABLE _RTHP-I-REQUIRED
VARIABLE _RTHP-L-CURSOR
VARIABLE _RTHP-L-BYTES

: _RTHP-L-TAKE  ( bytes -- a )
    _RTHP-L-BYTES !
    _RTHP-L-CURSOR @
    _RTHP-L-BYTES @ _RTHP-L-CURSOR +! ;

: _RTHP-LAYOUT  ( producer -- )
    DUP _RTHP.ARENA-A @ _RTHP-L-CURSOR !
    DUP _RTHP.MAX-DOCUMENTS @ RUHA-DOCUMENT-SIZE *
        DUP 2 PICK _RTHP.SOURCE-DIR-U !
        _RTHP-L-TAKE OVER _RTHP.SOURCE-DIR-A !
    DUP _RTHP.MAX-RECORDS @ UMSN-RECORD-SIZE *
        DUP 2 PICK _RTHP.SOURCE-RECS-U !
        _RTHP-L-TAKE OVER _RTHP.SOURCE-RECS-A !
    DUP _RTHP.MAX-TEXT @ OVER _RTHP.MAX-COLLECTION-NATIVE @ +
    OVER _RTHP.MAX-FIELD-NATIVE @ + OVER _RTHP.MAX-DIALOG-NATIVE @ +
        DUP 2 PICK _RTHP.SOURCE-TEXT-U !
        _RTHP-ALIGN8? DROP _RTHP-L-TAKE
        OVER _RTHP.SOURCE-TEXT-A !
    DUP _RTHP.MAX-COLLECTION-DESCRIPTORS @ UCSN-DESCRIPTOR-SIZE *
        DUP 2 PICK _RTHP.COLLECTION-DESCRIPTORS-U !
        _RTHP-L-TAKE OVER _RTHP.COLLECTION-DESCRIPTORS-A !
    DUP _RTHP.MAX-COLLECTION-NATIVE @
        DUP 2 PICK _RTHP.COLLECTION-NATIVE-U !
        _RTHP-ALIGN8? DROP _RTHP-L-TAKE
        OVER _RTHP.COLLECTION-NATIVE-A !
    DUP _RTHP.MAX-DGRAPH-DESCRIPTORS @ UDGSN-DESCRIPTOR-SIZE *
        DUP 2 PICK _RTHP.DGRAPH-DESCRIPTORS-U !
        _RTHP-L-TAKE OVER _RTHP.DGRAPH-DESCRIPTORS-A !
    DUP _RTHP.MAX-DGRAPH-NATIVE @
        DUP 2 PICK _RTHP.DGRAPH-NATIVE-U !
        _RTHP-ALIGN8? DROP _RTHP-L-TAKE
        OVER _RTHP.DGRAPH-NATIVE-A !
    DUP _RTHP.MAX-RECORDS @ RUCP-LOOKUP-ENTRY-SIZE *
        DUP 2 PICK _RTHP.LOOKUP-U ! _RTHP-L-TAKE
        OVER _RTHP.LOOKUP-A !
    DUP _RTHP.MAX-RECORDS @ 8 *
        DUP 2 PICK _RTHP.ORDER-U ! _RTHP-L-TAKE
        OVER _RTHP.ORDER-A !
    \ ORDER2 also lends two ordinal-index slices to the bounded DELTA join.
    DUP _RTHP.MAX-CONTROLS @ 24 *
        DUP 2 PICK _RTHP.ORDER2-U ! _RTHP-L-TAKE
        OVER _RTHP.ORDER2-A !
    \ Each target bank's kept control-index annex.
    DUP _RTHP.MAX-CONTROLS @ 8 *
        DUP 2 PICK _RTHP.FACTS-INDEX-U ! _RTHP-L-TAKE
        OVER _RTHP.FACTS-INDEX0-A !
    DUP _RTHP.FACTS-INDEX-U @ _RTHP-L-TAKE
        OVER _RTHP.FACTS-INDEX1-A !
    DUP _RTHP.MAX-CONTROLS @ RTE-CONTROL-SIZE *
        DUP 2 PICK _RTHP.CONTROLS-U ! _RTHP-L-TAKE
        OVER _RTHP.CONTROLS-A !
    DUP _RTHP.MAX-CONTROLS @ RUCP-CORRELATION-SIZE *
        DUP 2 PICK _RTHP.CORR-U ! _RTHP-L-TAKE
        OVER _RTHP.CORR-A !
    DUP _RTHP.MAX-CONTROLS @ OVER _RTHP.MAX-INSTRUMENTS @ +
    OVER _RTHP.MAX-STATICS @ +
        RUCL-CLAIM-SIZE *
        DUP 2 PICK _RTHP.CLAIMS-U ! _RTHP-L-TAKE
        OVER _RTHP.CLAIMS-A !
    DUP _RTHP.CLAIMS-U @
        DUP 2 PICK _RTHP.GLYPH-CLAIMS-U ! _RTHP-L-TAKE
        OVER _RTHP.GLYPH-CLAIMS-A !
    DUP _RTHP.MAX-INSTRUMENT-REGIONS @ RTE-INSTRUMENT-REGION-SIZE *
        DUP 2 PICK _RTHP.INSTRUMENT-REGIONS-U ! _RTHP-L-TAKE
        OVER _RTHP.INSTRUMENT-REGIONS-A !
    DUP _RTHP.MAX-INSTRUMENTS @ RTE-INSTRUMENT-SIZE *
        DUP 2 PICK _RTHP.INSTRUMENTS-U ! _RTHP-L-TAKE
        OVER _RTHP.INSTRUMENTS-A !
    DUP _RTHP.MAX-DGRAPH-NATIVE @
        DUP 2 PICK _RTHP.INSTRUMENT-UNITS-U !
        _RTHP-ALIGN8? DROP _RTHP-L-TAKE
        OVER _RTHP.INSTRUMENT-UNITS-A !
    DUP _RTHP.MAX-INSTRUMENTS @ RUIP-CORRELATION-SIZE *
        DUP 2 PICK _RTHP.INSTRUMENT-CORR-U ! _RTHP-L-TAKE
        OVER _RTHP.INSTRUMENT-CORR-A !
    DUP _RTHP.MAX-SERIES @ RTE-SERIES-SIZE *
        DUP 2 PICK _RTHP.SERIES-U ! _RTHP-L-TAKE OVER _RTHP.SERIES-A !
    DUP _RTHP.MAX-SERIES @ _RTHP-SERIES-CORR-SIZE *
        DUP 2 PICK _RTHP.SERIES-CORR-U ! _RTHP-L-TAKE OVER _RTHP.SERIES-CORR-A !
    DUP _RTHP.MAX-DGRAPH-NATIVE @
        DUP 2 PICK _RTHP.SERIES-SAMPLES-U ! _RTHP-L-TAKE OVER _RTHP.SERIES-SAMPLES-A !
    DUP _RTHP.MAX-DGRAPH-DESCRIPTORS @ _RTHP-OMITTED-GRAPH-SIZE *
        DUP 2 PICK _RTHP.OMITTED-GRAPHS-U ! _RTHP-L-TAKE OVER _RTHP.OMITTED-GRAPHS-A !
    DUP _RTHP.MAX-STATICS @ OVER _RTHP.MAX-PICTURES @ -
        USFSN-DESCRIPTOR-SIZE *
        DUP 2 PICK _RTHP.STATUS-DESCRIPTORS-U ! _RTHP-L-TAKE
        OVER _RTHP.STATUS-DESCRIPTORS-A !
    DUP _RTHP.MAX-PICTURES @ UPICSN-DESCRIPTOR-SIZE *
        DUP 2 PICK _RTHP.PICTURES-U ! _RTHP-L-TAKE
        OVER _RTHP.PICTURES-A !
    DUP _RTHP.MAX-STATUS-NATIVE @
        DUP 2 PICK _RTHP.STATUS-NATIVE-U ! _RTHP-L-TAKE
        OVER _RTHP.STATUS-NATIVE-A !
    DUP _RTHP.MAX-STATICS @ RTE-STATIC-SIZE *
        DUP 2 PICK _RTHP.STATICS-U ! _RTHP-L-TAKE
        OVER _RTHP.STATICS-A !
    DUP _RTHP.MAX-STATUS-NATIVE @
        DUP 2 PICK _RTHP.STATIC-TEXT-U ! _RTHP-L-TAKE
        OVER _RTHP.STATIC-TEXT-A !
    DUP _RTHP.MAX-STATICS @ _RTHP-STATIC-CORR-SIZE *
        DUP 2 PICK _RTHP.STATIC-CORR-U ! _RTHP-L-TAKE
        OVER _RTHP.STATIC-CORR-A !
    DUP _RTHP.MAX-FIELDS @ UFLSN-DESCRIPTOR-SIZE *
        DUP 2 PICK _RTHP.FIELD-DESCRIPTORS-U ! _RTHP-L-TAKE
        OVER _RTHP.FIELD-DESCRIPTORS-A !
    DUP _RTHP.MAX-FIELD-NATIVE @
        DUP 2 PICK _RTHP.FIELD-NATIVE-U ! _RTHP-L-TAKE
        OVER _RTHP.FIELD-NATIVE-A !
    DUP _RTHP.MAX-DIALOGS @ UDLSN-DESCRIPTOR-SIZE *
        DUP 2 PICK _RTHP.DIALOG-DESCRIPTORS-U ! _RTHP-L-TAKE
        OVER _RTHP.DIALOG-DESCRIPTORS-A !
    DUP _RTHP.MAX-DIALOG-NATIVE @
        DUP 2 PICK _RTHP.DIALOG-NATIVE-U ! _RTHP-L-TAKE
        OVER _RTHP.DIALOG-NATIVE-A !
    DUP _RTHP.MAX-ROWS @ 1+ RGRP-ROW-HEAD-SIZE *
        DUP 2 PICK _RTHP.HEADS-U ! _RTHP-L-TAKE
        OVER _RTHP.HEADS-A !
    DUP _RTHP.MAX-CONTROLS @ OVER _RTHP.MAX-INSTRUMENTS @ +
    OVER _RTHP.MAX-STATICS @ +
        2 * RGRP-EVENT-SIZE *
        DUP 2 PICK _RTHP.EVENTS-U ! _RTHP-L-TAKE
        OVER _RTHP.EVENTS-A !
    DUP _RTHP.MAX-COLS @ 1+ RGRP-PAIRED-DIFFERENCE-SIZE *
        DUP 2 PICK _RTHP.DIFF-U ! _RTHP-L-TAKE
        OVER _RTHP.DIFF-A !
    DUP _RTHP.MAX-COLS @ OVER _RTHP.MAX-ROWS @ *
        RTE-GLYPH-RUN-PLAN-ITEM-SIZE *
        DUP 2 PICK _RTHP.GLYPH-ITEMS-U ! _RTHP-L-TAKE
        OVER _RTHP.GLYPH-ITEMS-A !
    DUP _RTHP.MAX-COLS @ OVER _RTHP.MAX-ROWS @ *
        RGRP-TEXT-REF-SIZE *
        DUP 2 PICK _RTHP.GLYPH-REFS-U ! _RTHP-L-TAKE
        OVER _RTHP.GLYPH-REFS-A !
    DUP _RTHP.MAX-COLS @ OVER _RTHP.MAX-ROWS @ * 4 *
        DUP 2 PICK _RTHP.GLYPH-TEXT-U !
        _RTHP-ALIGN8? DROP _RTHP-L-TAKE
        OVER _RTHP.GLYPH-TEXT-A !
    DUP _RTHP.MAX-ROWS @
        DUP 2 PICK _RTHP.ROW-DAMAGE-U !
        _RTHP-ALIGN8? DROP _RTHP-L-TAKE
        OVER _RTHP.ROW-DAMAGE-A !
    DUP _RTHP.MAX-COLS @ OVER _RTHP.MAX-ROWS @ * 8 *
        DUP 2 PICK _RTHP.GLYPH-ID-MAP-U ! _RTHP-L-TAKE
        OVER _RTHP.GLYPH-ID-MAP-A !
    DUP _RTHP-TARGET-BANK-BYTES? DROP
        _RTHP-L-TAKE OVER _RTHP.TARGET0-A !
    DUP _RTHP-TARGET-BANK-BYTES? DROP
        _RTHP-L-TAKE OVER _RTHP.TARGET1-A !
    DROP 0 _RTHP-L-CURSOR ! 0 _RTHP-L-BYTES ! ;

\ Optional complete-START extension.  Its descriptor and context are owned by
\ composition, installed before OWNER_OPEN, and immutable until the producer
\ is stopped.  A failed PREPARE falls back to the base projection unless the
\ owner can ask the terminal for the space it needed.  EMIT can refuse
\ only when PREPARE left no candidate; after emission begins it must return
\ the real failure so the complete retained capture is cancelled.
40 CONSTANT RTHP-EXTENSION-SIZE
0x5254485045585431 CONSTANT _RTHP-EXTENSION-MAGIC
: RTHPX.MAGIC ( x -- a ) ;
: RTHPX.SIZE ( x -- a ) 8 + ;
: RTHPX.SELF ( x -- a ) 16 + ;
: RTHPX.CONTEXT ( x -- a ) 24 + ;
: RTHPX.DISPATCH ( x -- a ) 32 + ;
0 CONSTANT RTHPX-PREPARE
1 CONSTANT RTHPX-EMIT
2 CONSTANT RTHPX-PUBLISH-CHECK
3 CONSTANT RTHPX-PUBLISH
4 CONSTANT RTHPX-ABORT
5 CONSTANT RTHPX-RETIRE
6 CONSTANT RTHPX-CURRENT
7 CONSTANT RTHPX-START-ACK
8 CONSTANT RTHPX-DELTA-PROBE
9 CONSTANT RTHPX-DELTA-PREPARE
10 CONSTANT RTHPX-DELTA-EMIT
\ Dispatch: ( event producer context -- rte-status ).  No unacknowledged
\ candidate may become input-visible during PREPARE, EMIT or PUBLISH-CHECK.
\ START-ACK follows a successful hidden START acknowledgement and base ID
\ advancement. It consumes extension IDs without publishing input authority.
\ A changed draw after an acknowledged one may become a DELTA: DELTA-PROBE
\ says cheaply whether the extension could publish it that way, DELTA-PREPARE
\ builds that candidate once the base producer has matched its identities,
\ and DELTA-EMIT sends it inside the open retained DELTA. A refused PROBE or
\ PREPARE leaves the draw to a complete START.
: RTHP-MODULE-STORAGE-DISJOINT? ( a u -- flag )
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    2DUP _RTHP-OWNED-START _RTHP-OWNED-LIMIT @ _RTHP-OWNED-START -
        MSPAN-OVERLAP? IF 2DROP 0 EXIT THEN
    2DUP _RUHA-I-OWNED-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    RTE-ADMISSION-STORAGE-DISJOINT? ;
: _RTHP-EXTENSION? ( extension producer -- flag )
    OVER 0= IF 2DROP -1 EXIT THEN
    OVER 7 AND IF 2DROP 0 EXIT THEN
    OVER RTHP-EXTENSION-SIZE RTHP-MODULE-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    OVER RTHP-EXTENSION-SIZE _SCR-MODULE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    _SCR-CUR @ IF
        OVER RTHP-EXTENSION-SIZE SCR-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    THEN
    OVER RTHP-EXTENSION-SIZE 2 PICK RTHP-SIZE MSPAN-OVERLAP? IF 2DROP 0 EXIT THEN
    OVER RTHP-EXTENSION-SIZE 2 PICK DUP _RTHP.ARENA-A @ SWAP _RTHP.ARENA-U @
        MSPAN-OVERLAP? IF 2DROP 0 EXIT THEN
    OVER RTHP-EXTENSION-SIZE 2 PICK _RTHP.FACADE @ RTE-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    DROP DUP RTHPX.MAGIC @ _RTHP-EXTENSION-MAGIC <>
    OVER RTHPX.SIZE @ RTHP-EXTENSION-SIZE <> OR
    OVER RTHPX.SELF @ 2 PICK <> OR
    OVER RTHPX.CONTEXT @ 0= OR SWAP RTHPX.DISPATCH @ 0= OR 0= ;
: _RTHP-EXTENSION-CALL ( event producer -- rte-status )
    DUP _RTHP.EXTENSION @ DUP 0= IF
        DROP NIP DROP RTE-S-UNAVAILABLE EXIT
    THEN
    DUP RTHPX.CONTEXT @ SWAP RTHPX.DISPATCH @ CATCH
    ?DUP IF >R DROP 2DROP R> DROP RTE-S-INVALID THEN ;
: _RTHP-EXTENSION-NOTIFY ( event producer -- ) _RTHP-EXTENSION-CALL DROP ;
: _RTHP-EXTENSION-CHECK ( event producer -- flag )
    DUP _RTHP.EXTENSION @ 0= IF 2DROP -1 EXIT THEN
    _RTHP-EXTENSION-CALL RTE-S-OK = ;

VARIABLE _RTHP-V-P

: _RTHP-VALID-BODY?  ( -- flag )
    _RTHP-V-P @ DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP RTHP-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP _RTHP.MAGIC @ _RTHP-MAGIC <> IF DROP 0 EXIT THEN
    DUP _RTHP.SIZE @ RTHP-SIZE <> IF DROP 0 EXIT THEN
    DUP _RTHP.SELF @ OVER <> IF DROP 0 EXIT THEN
    DUP _RTHP.PHASE @ _RTHP-PH-RESIZING U> IF DROP 0 EXIT THEN
    DUP _RTHP.FAULT @ 4 U< 0= IF DROP 0 EXIT THEN
    DUP _RTHP.ADAPTER @ RUHA-VALID? 0= IF DROP 0 EXIT THEN
    DUP _RTHP.FACADE @ RTE-VALID? 0= IF DROP 0 EXIT THEN
    DUP _RTHP.MAX-DOCUMENTS @ DUP 0> 0= IF 2DROP 0 EXIT THEN
    OVER _RTHP.ADAPTER @ RUHA-DOCUMENT-CAPACITY@ <> IF DROP 0 EXIT THEN
    DUP _RTHP.MAX-RECORDS @ _RTHP-POS-U32? 0= IF DROP 0 EXIT THEN
    DUP _RTHP.MAX-TEXT @ _RTHP-POS-U32? 0= IF DROP 0 EXIT THEN
    DUP _RTHP.MAX-COLLECTION-NATIVE @ DUP _RTHP-POS-U32? 0= IF
        2DROP 0 EXIT
    THEN
    DUP 7 AND IF 2DROP 0 EXIT THEN
    RTHP-COLLECTION-CONTROL-CAPACITY
    OVER _RTHP.MAX-COLLECTIONS @ <> IF
        DROP 0 EXIT
    THEN
    DUP _RTHP.MAX-COLLECTION-NATIVE @ USCOL-ENTRY-HEADER-SIZE /
        OVER _RTHP.MAX-COLLECTION-DESCRIPTORS @ <> IF DROP 0 EXIT THEN
    DUP _RTHP.MAX-DGRAPH-NATIVE @ _RTHP-POS-U32? 0= IF
        DROP 0 EXIT
    THEN
    DUP _RTHP.MAX-DGRAPH-NATIVE @ 7 AND IF DROP 0 EXIT THEN
    DUP _RTHP.MAX-DGRAPH-NATIVE @ UDG-HEADER-SIZE U< IF DROP 0 EXIT THEN
    DUP _RTHP.MAX-DGRAPH-NATIVE @ UDG-HEADER-SIZE /
    OVER _RTHP.MAX-RECORDS @ _RTHP-UMIN
    OVER _RTHP.MAX-DGRAPH-DESCRIPTORS @ <> IF DROP 0 EXIT THEN
    DUP _RTHP.MAX-DGRAPH-NATIVE @ UDG-SERIES-HEADER-SIZE /
    OVER _RTHP.MAX-SERIES @ <> IF DROP 0 EXIT THEN
    DUP _RTHP.FIRST-SERIES @ 0= OVER _RTHP.NEXT-SERIES @ 0= OR IF DROP 0 EXIT THEN
    DUP _RTHP.MAX-DGRAPH-NATIVE @ UDG-STATUS-RECORD-SIZE /
    OVER _RTHP.MAX-INSTRUMENTS @ <> IF DROP 0 EXIT THEN
    DUP _RTHP.MAX-DGRAPH-DESCRIPTORS @
    OVER _RTHP.MAX-INSTRUMENTS @ _RTHP-UMIN
    OVER _RTHP.MAX-INSTRUMENT-REGIONS @ <> IF DROP 0 EXIT THEN
    DUP _RTHP.MAX-STATUS-NATIVE @ _RTHP-U32? 0= IF DROP 0 EXIT THEN
    DUP _RTHP.MAX-STATUS-NATIVE @ 7 AND IF DROP 0 EXIT THEN
    DUP _RTHP.MAX-PICTURES @ _RTHP-U32? 0= IF DROP 0 EXIT THEN
    DUP _RTHP.MAX-STATUS-NATIVE @ USF-HEADER-SIZE /
        OVER _RTHP.MAX-PICTURES @ +
        OVER _RTHP.MAX-STATICS @ <> IF DROP 0 EXIT THEN
    DUP _RTHP.PICTURE-COUNT @ OVER _RTHP.MAX-PICTURES @ U> IF DROP 0 EXIT THEN
    \ The picture lane: one job of a known kind, a chunk block only while an
    \ upload runs, and a whole table or none.
    DUP _RTHP.LANE-JOB @ RTE-JOB-PIXELS U> IF DROP 0 EXIT THEN
    DUP _RTHP.CHUNK-A @ 0<>
        OVER _RTHP.LANE-JOB @ RTE-JOB-UPLOAD <> AND IF DROP 0 EXIT THEN
    DUP _RTHP.CHUNK-A @ 0= OVER _RTHP.CHUNK-U @ 0= <> IF DROP 0 EXIT THEN
    DUP _RTHP.RESOURCES-U @ _RTHP-RESOURCE-SIZE MOD IF DROP 0 EXIT THEN
    DUP _RTHP.RESOURCES-A @ 0= OVER _RTHP.RESOURCES-U @ 0= <> IF DROP 0 EXIT THEN
    DUP _RTHP.NEXT-RESOURCE @ 0= IF DROP 0 EXIT THEN
    \ A budget only follows a refusal, and the lane's own request for room
    \ only while the terminal decides.
    DUP _RTHP.LANE-REFUSED @ RTHP-WHY-OTHER U> IF DROP 0 EXIT THEN
    DUP _RTHP.LANE-BUDGET @ 0<> OVER _RTHP.LANE-REFUSED @ 0= AND IF DROP 0 EXIT THEN
    DUP _RTHP.LANE-RESIZE @ 2 U> IF DROP 0 EXIT THEN
    DUP _RTHP.LANE-RESIZE @ 0<>
        OVER _RTHP.PHASE @ _RTHP-PH-RESIZING <> AND IF DROP 0 EXIT THEN
    DUP _RTHP.MAX-FIELD-NATIVE @ _RTHP-U32? 0= IF DROP 0 EXIT THEN
    DUP _RTHP.MAX-FIELD-NATIVE @ 7 AND IF DROP 0 EXIT THEN
    DUP _RTHP.MAX-FIELD-NATIVE @ UFLD-HEADER-SIZE /
        OVER _RTHP.MAX-FIELDS @ <> IF DROP 0 EXIT THEN
    DUP _RTHP.MAX-DIALOG-NATIVE @ _RTHP-U32? 0= IF DROP 0 EXIT THEN
    DUP _RTHP.MAX-DIALOG-NATIVE @ 7 AND IF DROP 0 EXIT THEN
    DUP _RTHP.MAX-DIALOG-NATIVE @ UDLG-HEADER-SIZE /
        OVER _RTHP.MAX-DIALOGS @ <> IF DROP 0 EXIT THEN
    DUP _RTHP.MAX-DIALOG-NATIVE @ UDLG-BUTTON-HEADER-SIZE /
        OVER _RTHP.MAX-DIALOG-CONTROLS @ <> IF DROP 0 EXIT THEN
    DUP _RTHP.MAX-RECORDS @ OVER _RTHP.MAX-COLLECTIONS @
        _RTHP-U32+? 0= IF 2DROP 0 EXIT THEN
    OVER _RTHP.MAX-FIELDS @ _RTHP-U32+? 0= IF 2DROP 0 EXIT THEN
    OVER _RTHP.MAX-DIALOG-CONTROLS @ _RTHP-U32+? 0= IF 2DROP 0 EXIT THEN
    OVER _RTHP.MAX-CONTROLS @ <> IF DROP 0 EXIT THEN
    DUP _RTHP.MAX-TEXT @ OVER _RTHP.MAX-COLLECTION-NATIVE @
        _RTHP-U32+? 0= IF 2DROP 0 EXIT THEN
    OVER _RTHP.MAX-FIELD-NATIVE @ _RTHP-U32+? 0= IF 2DROP 0 EXIT THEN
    OVER _RTHP.MAX-DIALOG-NATIVE @ _RTHP-U32+? 0= IF 2DROP 0 EXIT THEN
    OVER _RTHP.SOURCE-TEXT-U @ <> IF DROP 0 EXIT THEN
    DUP _RTHP.TARGET-ACTIVE @ 0=
    OVER _RTHP.ACTIVE-DRAW @ 0= <> IF DROP 0 EXIT THEN
    DUP _RTHP.PHASE @ _RTHP-PH-LIVE = IF
        DUP _RTHP.SURFACE-GEN @
        OVER _RTHP.ACTIVE-DRAW @ <> IF DROP 0 EXIT THEN
    THEN
    DUP _RTHP.ARENA-A @ OVER _RTHP.ARENA-U @
        MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP _RTHP.KEPT-ARENA-A @ IF
        DUP _RTHP.MEMORY @ 0= IF DROP 0 EXIT THEN
        DUP _RTHP.TARGET-ACTIVE @ OVER _RTHP.KEPT-BANK-A @ <> IF
            DROP 0 EXIT
        THEN
    THEN
    DUP _RTHP.EXTENSION @ OVER _RTHP-EXTENSION? 0= IF DROP 0 EXIT THEN
    DROP -1 ;

: RTHP-VALID?  ( producer -- flag )
    _RTHP-V-P ! _RTHP-VALID-BODY? 0 _RTHP-V-P ! ;

: RTHP-EXTENSION-INSTALL ( extension producer -- scb-status )
    DUP RTHP-SIZE RTHP-MODULE-STORAGE-DISJOINT? 0= IF 2DROP SCB-S-INVALID EXIT THEN
    OVER IF OVER RTHP-EXTENSION-SIZE RTHP-MODULE-STORAGE-DISJOINT? 0= IF
        2DROP SCB-S-INVALID EXIT THEN THEN
    DUP RTHP-VALID? 0= IF 2DROP SCB-S-INVALID EXIT THEN
    DUP _RTHP.PHASE @ _RTHP-PH-WAIT <>
    OVER _RTHP.TARGET-ACTIVE @ 0<> OR
    OVER _RTHP.TARGET-PENDING @ 0<> OR IF 2DROP SCB-S-INVALID EXIT THEN
    2DUP _RTHP-EXTENSION? 0= IF 2DROP SCB-S-INVALID EXIT THEN
    DUP _RTHP.EXTENSION @ DUP IF 2 PICK <> IF 2DROP SCB-S-INVALID EXIT THEN ELSE DROP THEN
    _RTHP.EXTENSION ! SCB-S-OK ;

: RTHP-LIVE?  ( producer -- flag )
    DUP RTHP-VALID? 0= IF DROP 0 EXIT THEN
    _RTHP.TARGET-ACTIVE @ 0<> ;

: _RTHP-DOCUMENT-AT  ( index producer -- document )
    _RTHP.SOURCE-DIR-A @ SWAP RUHA-DOCUMENT-SIZE * + ;

\ =====================================================================
\  Revision-bound native semantic input targets
\ =====================================================================
\
\  CONTROL descendants intentionally carry no wire geometry: the renderer
\  lays them out from their semantic parent/order graph.  While a candidate is
\  sealed, its exact control/correlation/source relationship is reduced to a
\  compact point targets in the inactive caller-bounded bank.  Menu rows and
\  generic TAB children both use this one acknowledged control-ID route; no
\  target consults a live UIDL element or widget after sealing.  Each bank
\  explicitly reserves the complete maximum packed candidate, so failure to
\  retain an already-admitted candidate is an authority/invariant failure.
\  Only the bank belonging to the exactly acknowledged reveal is published,
\  and it remains untouched while a later replacement uses the other bank.

VARIABLE _RTHP-CT-P
VARIABLE _RTHP-CT-OWNER
VARIABLE _RTHP-CT-GENERATION
VARIABLE _RTHP-CT-ID
VARIABLE _RTHP-CT-CONTROL
VARIABLE _RTHP-CT-CORRELATION
VARIABLE _RTHP-CT-RECORD
VARIABLE _RTHP-CT-ORDINAL
VARIABLE _RTHP-CT-RESOLVED
VARIABLE _RTHP-CT-ROW
VARIABLE _RTHP-CT-COL
VARIABLE _RTHP-CT-H
VARIABLE _RTHP-CT-W
VARIABLE _RTHP-CT-END
VARIABLE _RTHP-CT-BYTES
VARIABLE _RTHP-CT-ATTACHMENT
VARIABLE _RTHP-CT-DOCUMENT
VARIABLE _RTHP-CT-DOCUMENT-I
VARIABLE _RTHP-CT-LOCAL
VARIABLE _RTHP-CT-RECORD-CURSOR
VARIABLE _RTHP-CT-TEXT-CURSOR
VARIABLE _RTHP-CT-DOC-RECORD-O
VARIABLE _RTHP-CT-DOC-RECORD-U
VARIABLE _RTHP-CT-DOC-RECORD-COUNT
VARIABLE _RTHP-CT-DOC-TEXT-O
VARIABLE _RTHP-CT-DOC-TEXT-U
VARIABLE _RTHP-CT-DOC-MATCHES
VARIABLE _RTHP-CT-TEXT-A
VARIABLE _RTHP-CT-TEXT-U
VARIABLE _RTHP-CT-TAB-ROOT
VARIABLE _RTHP-CT-TAB-ROOT-ID
VARIABLE _RTHP-CT-TAB-ROOT-ATTACHMENT
VARIABLE _RTHP-CT-TAB-ROOT-INDEX
VARIABLE _RTHP-CT-TAB-ROOT-KEY
VARIABLE _RTHP-CT-TAB-ROOT-GENERATION
VARIABLE _RTHP-CT-TAB-ROOT-ROW
VARIABLE _RTHP-CT-TAB-ROOT-COL
VARIABLE _RTHP-CT-TAB-ROOT-END
VARIABLE _RTHP-CT-TAB-ROOT-STATE
VARIABLE _RTHP-CT-TAB-POS
VARIABLE _RTHP-CT-TAB-NEXT

: _RTHP-CT-CLEAR  ( -- )
    0 _RTHP-CT-P ! 0 _RTHP-CT-OWNER ! 0 _RTHP-CT-GENERATION !
    0 _RTHP-CT-ID ! 0 _RTHP-CT-CONTROL ! 0 _RTHP-CT-CORRELATION !
    0 _RTHP-CT-RECORD ! 0 _RTHP-CT-ORDINAL !
    0 _RTHP-CT-RESOLVED ! 0 _RTHP-CT-ROW ! 0 _RTHP-CT-COL !
    0 _RTHP-CT-H ! 0 _RTHP-CT-W ! 0 _RTHP-CT-END !
    0 _RTHP-CT-BYTES ! 0 _RTHP-CT-ATTACHMENT !
    0 _RTHP-CT-DOCUMENT ! 0 _RTHP-CT-DOCUMENT-I ! 0 _RTHP-CT-LOCAL !
    0 _RTHP-CT-RECORD-CURSOR ! 0 _RTHP-CT-TEXT-CURSOR !
    0 _RTHP-CT-DOC-RECORD-O ! 0 _RTHP-CT-DOC-RECORD-U !
    0 _RTHP-CT-DOC-RECORD-COUNT !
    0 _RTHP-CT-DOC-TEXT-O ! 0 _RTHP-CT-DOC-TEXT-U !
    0 _RTHP-CT-DOC-MATCHES ! 0 _RTHP-CT-TEXT-A ! 0 _RTHP-CT-TEXT-U !
    0 _RTHP-CT-TAB-ROOT !
    0 _RTHP-CT-TAB-ROOT-ID ! 0 _RTHP-CT-TAB-ROOT-ATTACHMENT !
    0 _RTHP-CT-TAB-ROOT-INDEX ! 0 _RTHP-CT-TAB-ROOT-KEY !
    0 _RTHP-CT-TAB-ROOT-GENERATION !
    0 _RTHP-CT-TAB-ROOT-ROW ! 0 _RTHP-CT-TAB-ROOT-COL !
    0 _RTHP-CT-TAB-ROOT-END ! 0 _RTHP-CT-TAB-ROOT-STATE !
    0 _RTHP-CT-TAB-POS ! 0 _RTHP-CT-TAB-NEXT ! ;

VARIABLE _RTHP-AS-A
VARIABLE _RTHP-AS-U
VARIABLE _RTHP-AS-P

: _RTHP-ARENA-SPAN?  ( address bytes producer -- flag )
    _RTHP-AS-P ! _RTHP-AS-U ! _RTHP-AS-A !
    _RTHP-AS-A @ _RTHP-AS-U @ MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    _RTHP-AS-P @ _RTHP.ARENA-A @
    _RTHP-AS-P @ _RTHP.ARENA-U @ MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    _RTHP-AS-A @ _RTHP-AS-P @ _RTHP.ARENA-A @ U< IF 0 EXIT THEN
    _RTHP-AS-A @ _RTHP-AS-U @ +
    _RTHP-AS-P @ _RTHP.ARENA-A @
        _RTHP-AS-P @ _RTHP.ARENA-U @ + U> 0= ;

\ Final target extraction may run long after the copied candidate was planned.
\ Re-prove every source bank before the canonical traversal so caller-owned
\ storage cannot redirect that traversal outside the producer arena.
: _RTHP-CT-CANDIDATE-SHAPE?  ( -- flag )
    _RTHP-CT-P @ _RTHP.FAULT @ SCB-S-OK <> IF 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.SOURCE-GEN @ 0=
    _RTHP-CT-P @ _RTHP.SOURCE-CONTENT-EPOCH @ 0= OR
    _RTHP-CT-P @ _RTHP.SOURCE-DRAW @ 0= OR
    _RTHP-CT-P @ _RTHP.FIRST-OBJECT @ 0= OR IF 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.SOURCE-DRAW @
        _RTHP-CT-P @ _RTHP.SURFACE-GEN @ <> IF 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.COLS @ DUP 0> SWAP
        _RTHP-CT-P @ _RTHP.MAX-COLS @ U> 0= AND 0= IF 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.ROWS @ DUP 0> SWAP
        _RTHP-CT-P @ _RTHP.MAX-ROWS @ U> 0= AND 0= IF 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.DOCUMENT-COUNT @ DUP 0> 0= IF DROP 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.MAX-DOCUMENTS @ U> IF 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.DOCUMENT-COUNT @ RUHA-DOCUMENT-SIZE
        _RTHP-U32*? 0= IF DROP 0 EXIT THEN _RTHP-CT-BYTES !
    _RTHP-CT-BYTES @ _RTHP-CT-P @ _RTHP.SOURCE-DIR-USED @ <> IF
        0 EXIT
    THEN
    _RTHP-CT-P @ _RTHP.MAX-DOCUMENTS @ RUHA-DOCUMENT-SIZE
        _RTHP-U32*? 0= IF DROP 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.SOURCE-DIR-U @ <> IF 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.SOURCE-DIR-A @ 7 AND IF 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.SOURCE-DIR-A @
        _RTHP-CT-BYTES @ _RTHP-CT-P @ _RTHP-ARENA-SPAN?
        0= IF 0 EXIT THEN

    _RTHP-CT-P @ _RTHP.CONTROL-COUNT @ DUP
        _RTHP-CT-P @ _RTHP.MAX-CONTROLS @ U> IF DROP 0 EXIT THEN DROP
    _RTHP-CT-P @ _RTHP.MENU-CONTROL-COUNT @ DUP
        _RTHP-CT-P @ _RTHP.MAX-RECORDS @ U> IF DROP 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.CONTROL-COUNT @ U> IF 0 EXIT THEN

    _RTHP-CT-P @ _RTHP.MENU-CONTROL-COUNT @ UMSN-RECORD-SIZE
        _RTHP-U32*? 0= IF DROP 0 EXIT THEN _RTHP-CT-BYTES !
    _RTHP-CT-BYTES @ _RTHP-CT-P @ _RTHP.SOURCE-USED @ <> IF 0 EXIT THEN
    _RTHP-CT-BYTES @ _RTHP-CT-P @ _RTHP.SOURCE-RECS-U @ U> IF 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.SOURCE-RECS-A @ 7 AND IF 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.SOURCE-RECS-A @
        _RTHP-CT-BYTES @ _RTHP-CT-P @ _RTHP-ARENA-SPAN?
        0= IF 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.SOURCE-MENU-TEXT-USED @
        _RTHP-CT-P @ _RTHP.MAX-TEXT @ U> IF 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.SOURCE-TEXT-USED @
        _RTHP-CT-P @ _RTHP.SOURCE-TEXT-U @ U> IF 0 EXIT THEN

    _RTHP-CT-P @ _RTHP.CONTROL-COUNT @ RTE-CONTROL-SIZE
        _RTHP-U32*? 0= IF DROP 0 EXIT THEN _RTHP-CT-BYTES !
    _RTHP-CT-BYTES @ _RTHP-CT-P @ _RTHP.CONTROLS-U @ U> IF 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.CONTROLS-A @ 7 AND IF 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.CONTROLS-A @
        _RTHP-CT-BYTES @ _RTHP-CT-P @ _RTHP-ARENA-SPAN?
        0= IF 0 EXIT THEN

    _RTHP-CT-P @ _RTHP.CONTROL-COUNT @ RUCP-CORRELATION-SIZE
        _RTHP-U32*? 0= IF DROP 0 EXIT THEN _RTHP-CT-BYTES !
    _RTHP-CT-BYTES @ _RTHP-CT-P @ _RTHP.CORR-U @ U> IF 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.CORR-A @ 7 AND IF 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.CORR-A @
        _RTHP-CT-BYTES @ _RTHP-CT-P @ _RTHP-ARENA-SPAN? ;

: _RTHP-CT-DOCUMENT-GEOMETRY?  ( -- flag )
    _RTHP-CT-DOCUMENT @ RUHA-DOCUMENT-ROW@ DUP 0< IF DROP 0 EXIT THEN
    _RTHP-CT-DOCUMENT @ RUHA-DOCUMENT-HEIGHT@ DUP 0> 0= IF
        2DROP 0 EXIT
    THEN
    _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.ROWS @ U> IF 0 EXIT THEN
    _RTHP-CT-DOCUMENT @ RUHA-DOCUMENT-COL@ DUP 0< IF DROP 0 EXIT THEN
    _RTHP-CT-DOCUMENT @ RUHA-DOCUMENT-WIDTH@ DUP 0> 0= IF
        2DROP 0 EXIT
    THEN
    _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.COLS @ U> 0= ;

: _RTHP-CT-DOCUMENT-SHAPE?  ( -- flag )
    _RTHP-CT-DOCUMENT @ RUHA-DOCUMENT-TOKEN@ DUP 0= IF DROP 0 EXIT THEN
        _RTHP-CT-ATTACHMENT !
    _RTHP-CT-DOCUMENT @ RUHA-DOCUMENT-SLOT-ID@ 0= IF 0 EXIT THEN
    _RTHP-CT-DOCUMENT-GEOMETRY? 0= IF 0 EXIT THEN

    _RTHP-CT-DOCUMENT @ RUHA-DOCUMENT-RECORD-OFFSET@
        DUP _RTHP-CT-DOC-RECORD-O !
        _RTHP-CT-RECORD-CURSOR @ <> IF 0 EXIT THEN
    _RTHP-CT-DOCUMENT @ RUHA-DOCUMENT-RECORD-BYTES@
        DUP _RTHP-CT-DOC-RECORD-U !
    DUP 0< IF DROP 0 EXIT THEN
    DUP UMSN-RECORD-SIZE MOD IF DROP 0 EXIT THEN
    UMSN-RECORD-SIZE / _RTHP-CT-DOC-RECORD-COUNT !
    _RTHP-CT-RECORD-CURSOR @ _RTHP-CT-DOC-RECORD-U @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-CT-P @ _RTHP.SOURCE-USED @ U> IF DROP 0 EXIT THEN
        _RTHP-CT-RECORD-CURSOR !

    _RTHP-CT-DOCUMENT @ RUHA-DOCUMENT-TEXT-OFFSET@
        DUP _RTHP-CT-DOC-TEXT-O !
        _RTHP-CT-TEXT-CURSOR @ <> IF 0 EXIT THEN
    _RTHP-CT-DOCUMENT @ RUHA-DOCUMENT-TEXT-BYTES@
        DUP _RTHP-CT-DOC-TEXT-U !
    DUP 0< IF DROP 0 EXIT THEN
    _RTHP-CT-DOC-RECORD-U @ 0= OVER 0<> AND IF DROP 0 EXIT THEN
    _RTHP-CT-TEXT-CURSOR @ SWAP _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    DUP _RTHP-CT-P @ _RTHP.SOURCE-TEXT-USED @ U> IF DROP 0 EXIT THEN
        _RTHP-CT-TEXT-CURSOR !
    _RTHP-CT-DOC-RECORD-U @ 0=
    _RTHP-CT-DOCUMENT @ RUHA-DOCUMENT-MENU-EPOCH@ 0= <> IF 0 EXIT THEN
    _RTHP-CT-DOC-RECORD-U @ 0=
    _RTHP-CT-DOCUMENT @ RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@ 0= <>
        IF 0 EXIT THEN
    _RTHP-CT-DOCUMENT @ RUHA-DOCUMENT-MENU-EPOCH@
        _RTHP-CT-P @ _RTHP.SOURCE-GEN @ U> IF 0 EXIT THEN
    _RTHP-CT-DOCUMENT @ RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@
        _RTHP-CT-P @ _RTHP.SOURCE-GEN @ U> IF 0 EXIT THEN
    _RTHP-CT-DOCUMENT @ RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@
    _RTHP-CT-DOCUMENT @ RUHA-DOCUMENT-MENU-EPOCH@ U> IF 0 EXIT THEN
    -1 ;

: _RTHP-CT-RECORD-AT?  ( -- flag )
    _RTHP-CT-LOCAL @ UMSN-RECORD-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN
    _RTHP-CT-DOC-RECORD-O @ SWAP _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-CT-P @ _RTHP.SOURCE-USED @ U< 0= IF DROP 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.SOURCE-RECS-A @ + _RTHP-CT-RECORD !
    -1 ;

: _RTHP-CT-TARGET?  ( control -- flag )
    DUP _RTE-CONTROL.KIND @ DUP RTE-CONTROL-MENU =
        OVER RTE-CONTROL-MENU-ITEM = OR
        SWAP RTE-CONTROL-TAB = OR
    SWAP _RTE-CONTROL.STATE @
        RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR AND
        RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR = AND ;

: _RTHP-CT-FIND-CONTROL?  ( -- flag )
    _RTHP-CT-ID @ _RTHP-CT-P @ _RTHP.FIRST-OBJECT @ U< IF 0 EXIT THEN
    _RTHP-CT-ID @ _RTHP-CT-P @ _RTHP.FIRST-OBJECT @ -
    DUP _RTHP-CT-P @ _RTHP.CONTROL-COUNT @ U< 0= IF DROP 0 EXIT THEN
    RTE-CONTROL-SIZE * _RTHP-CT-P @ _RTHP.CONTROLS-A @ +
        _RTHP-CT-CONTROL ! -1 ;

: _RTHP-CT-CONTROL?  ( -- flag )
    _RTHP-CT-CONTROL @ DUP _RTE-CONTROL.OWNER @
        _RTHP-CT-OWNER @ <> IF DROP 0 EXIT THEN
    DUP _RTE-CONTROL.GENERATION @
        _RTHP-CT-GENERATION @ <> IF DROP 0 EXIT THEN
    DUP _RTE-CONTROL.ID @ _RTHP-CT-ID @ <> IF DROP 0 EXIT THEN
    _RTE-CONTROL.KIND @ DUP RTE-CONTROL-DOCUMENT = IF DROP -1 EXIT THEN
    DUP RTE-CONTROL-MENU-BAR < IF DROP 0 EXIT THEN
        RTE-CONTROL-ITEM-VIEW U> 0= ;

: _RTHP-CT-CORRELATION-AT?  ( ordinal -- flag )
    DUP _RTHP-CT-P @ _RTHP.MENU-CONTROL-COUNT @ U< 0= IF DROP 0 EXIT THEN
    DUP _RTHP-CT-ORDINAL !
    RUCP-CORRELATION-SIZE * _RTHP-CT-P @ _RTHP.CORR-A @ +
    DUP _RTHP-CT-CORRELATION !
    RUCP-CORRELATION-CONTROL-ID@ DUP _RTHP-CT-ID ! 0<> ;

: _RTHP-CT-COLLECTION-CORRELATION-AT?  ( ordinal -- flag )
    DUP _RTHP-CT-P @ _RTHP.MENU-CONTROL-COUNT @ U< IF DROP 0 EXIT THEN
    DUP _RTHP-CT-P @ _RTHP.CONTROL-COUNT @ U< 0= IF DROP 0 EXIT THEN
    DUP _RTHP-CT-ORDINAL !
    RUCP-CORRELATION-SIZE * _RTHP-CT-P @ _RTHP.CORR-A @ +
    DUP _RTHP-CT-CORRELATION !
    RUCP-CORRELATION-CONTROL-ID@ DUP _RTHP-CT-ID ! 0<> ;

: _RTHP-CT-CORRELATION?  ( -- flag )
    _RTHP-CT-CORRELATION @ DUP RUCP-CORRELATION-ATTACHMENT@
        _RTHP-CT-ATTACHMENT @ <> IF DROP 0 EXIT THEN
    DUP RUCP-CORRELATION-SOURCE@ UMSN-SOURCE-UIDL <> IF DROP 0 EXIT THEN
    DUP RUCP-CORRELATION-SCOPE@ IF DROP 0 EXIT THEN
    DUP RUCP-CORRELATION-SUBKEY@ IF DROP 0 EXIT THEN
    DUP RUCP-CORRELATION-LIFECYCLE-GENERATION@ IF DROP 0 EXIT THEN
    DUP RUCP-CORRELATION-CONTROL-ID@ _RTHP-CT-ID @ <> IF DROP 0 EXIT THEN
    DUP RUCP-CORRELATION-INDEX@ 0< IF DROP 0 EXIT THEN
    DROP -1 ;

: _RTHP-CT-KIND>RTE  ( umsn-kind -- rte-kind|0 )
    DUP UMSN-K-MENUBAR = IF DROP RTE-CONTROL-MENU-BAR EXIT THEN
    DUP UMSN-K-MENU = IF DROP RTE-CONTROL-MENU EXIT THEN
    DUP UMSN-K-ITEM = IF DROP RTE-CONTROL-MENU-ITEM EXIT THEN
    UMSN-K-SEPARATOR = IF RTE-CONTROL-MENU-SEPARATOR ELSE 0 THEN ;

: _RTHP-CT-RECORD?  ( -- flag )
    _RTHP-CT-RECORD @ DUP _UMSN-R.MAGIC @
        _UMSN-RECORD-MAGIC <> IF DROP 0 EXIT THEN
    DUP _UMSN-R.ABI @ _UMSN-RECORD-ABI <> IF DROP 0 EXIT THEN
    DUP _UMSN-R.BYTES @ UMSN-RECORD-SIZE <> IF DROP 0 EXIT THEN
    DUP _UMSN-R.SOURCE @ UMSN-SOURCE-UIDL <> IF DROP 0 EXIT THEN
    DUP UMSN-RECORD-GENERATION@
        _RTHP-CT-P @ _RTHP.SOURCE-GEN @ <> IF DROP 0 EXIT THEN
    DUP UMSN-RECORD-SOURCE-INDEX@
        _RTHP-CT-CORRELATION @ RUCP-CORRELATION-INDEX@ <> IF DROP 0 EXIT THEN
    DUP UMSN-RECORD-SUBKEY@
        _RTHP-CT-CORRELATION @ RUCP-CORRELATION-SUBKEY@ <> IF DROP 0 EXIT THEN
    DUP UMSN-RECORD-KIND@ _RTHP-CT-KIND>RTE DUP 0= IF
        2DROP 0 EXIT
    THEN
    _RTHP-CT-CONTROL @ _RTE-CONTROL.KIND @ <> IF DROP 0 EXIT THEN
    DUP UMSN-RECORD-STATE@
    RUCP-STATE>RTE
        _RTHP-CT-CONTROL @ _RTE-CONTROL.STATE @ <> IF DROP 0 EXIT THEN
    DROP -1 ;

: _RTHP-CT-GEOMETRY?  ( -- flag )
    _RTHP-CT-RECORD @ UMSN-RECORD-RESOLVED DROP _RTHP-CT-RESOLVED !
    _RTHP-CT-RESOLVED @ UTUI-RESOLVED-SIZE
        UTUI-RESOLVED-VALID? 0= IF 0 EXIT THEN
    _RTHP-CT-RESOLVED @ DUP @ _RTHP-CT-ROW !
    DUP 8 + @ _RTHP-CT-COL !
    DUP 16 + @ _RTHP-CT-H !
    24 + @ _RTHP-CT-W !
    _RTHP-CT-ROW @ 0< _RTHP-CT-COL @ 0< OR IF 0 EXIT THEN
    _RTHP-CT-H @ 0> _RTHP-CT-W @ 0> AND 0= IF 0 EXIT THEN
    _RTHP-CT-ROW @ _RTHP-CT-H @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN _RTHP-CT-END !
    _RTHP-CT-END @ _RTHP-CT-P @ _RTHP.ROWS @ U> IF 0 EXIT THEN
    _RTHP-CT-COL @ _RTHP-CT-W @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN _RTHP-CT-END !
    _RTHP-CT-END @ _RTHP-CT-P @ _RTHP.COLS @ U> IF 0 EXIT THEN
    _RTHP-CT-ROW @ _RTHP-CT-H @ 1- 2/ + _RTHP-CT-ROW !
    _RTHP-CT-COL @ _RTHP-CT-W @ 1- 2/ + _RTHP-CT-COL !
    -1 ;

: _RTHP-CT-ATTACHMENT?  ( attachment -- flag )
    DUP 0= IF DROP 0 EXIT THEN _RTHP-CT-ATTACHMENT !
    0 _RTHP-CT-DOC-MATCHES !
    _RTHP-CT-P @ _RTHP.DOCUMENT-COUNT @ 0 ?DO
        I _RTHP-CT-P @ _RTHP-DOCUMENT-AT RUHA-DOCUMENT-TOKEN@
            _RTHP-CT-ATTACHMENT @ = IF 1 _RTHP-CT-DOC-MATCHES +! THEN
    LOOP
    _RTHP-CT-DOC-MATCHES @ 1 = ;

: _RTHP-CT-COLLECTION-CORRELATION?  ( -- flag )
    _RTHP-CT-CORRELATION @ DUP RUCP-CORRELATION-ATTACHMENT@
        _RTHP-CT-ATTACHMENT? 0= IF DROP 0 EXIT THEN
    DUP RUCP-CORRELATION-SOURCE@ UMSN-SOURCE-UIDL <> IF DROP 0 EXIT THEN
    DUP RUCP-CORRELATION-INDEX@ 0< IF DROP 0 EXIT THEN
    DUP RUCP-CORRELATION-SUBKEY@ 0= IF DROP 0 EXIT THEN
    DUP RUCP-CORRELATION-LIFECYCLE-GENERATION@ 0< IF DROP 0 EXIT THEN
    DUP RUCP-CORRELATION-CONTROL-ID@ _RTHP-CT-ID @ <> IF DROP 0 EXIT THEN
    RUCP-CORRELATION-SCOPE@
    _RTHP-CT-CONTROL @ _RTE-CONTROL.KIND @ RTE-CONTROL-TAB = IF
        0<>
    ELSE
        0=
    THEN ;

: _RTHP-CT-COLLECTION-CONTROL-AT?  ( ordinal -- flag )
    _RTHP-CT-COLLECTION-CORRELATION-AT? 0= IF 0 EXIT THEN
    _RTHP-CT-FIND-CONTROL? 0= IF 0 EXIT THEN
    _RTHP-CT-CONTROL? 0= IF 0 EXIT THEN
    _RTHP-CT-CONTROL @ _RTE-CONTROL.KIND @
        _RTHP-COLLECTION-CONTROL-KIND? 0= IF 0 EXIT THEN
    _RTHP-CT-COLLECTION-CORRELATION? ;

: _RTHP-CT-TEXT-SPAN?  ( address bytes -- flag )
    _RTHP-CT-TEXT-U ! _RTHP-CT-TEXT-A !
    _RTHP-CT-TEXT-U @ 0= IF _RTHP-CT-TEXT-A @ 0= EXIT THEN
    _RTHP-CT-TEXT-A @ 0= IF 0 EXIT THEN
    _RTHP-CT-TEXT-A @ _RTHP-CT-TEXT-U @ MSPAN-NONWRAPPING? 0= IF
        0 EXIT
    THEN
    _RTHP-CT-P @ _RTHP.SOURCE-TEXT-A @
    _RTHP-CT-P @ _RTHP.SOURCE-TEXT-USED @ _RTHP-CT-P @
        _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    _RTHP-CT-TEXT-A @ _RTHP-CT-P @ _RTHP.SOURCE-TEXT-A @ U< IF
        0 EXIT
    THEN
    _RTHP-CT-TEXT-A @ _RTHP-CT-TEXT-U @ +
    _RTHP-CT-P @ _RTHP.SOURCE-TEXT-A @
        _RTHP-CT-P @ _RTHP.SOURCE-TEXT-USED @ + U> 0= ;

: _RTHP-CT-TABSET?  ( -- flag )
    _RTHP-CT-CONTROL @ _RTE-CONTROL.KIND @
        RTE-CONTROL-TABSET <> IF 0 EXIT THEN
    _RTHP-CT-CONTROL @ _RTE-CONTROL.PARENT @
    _RTHP-CT-CONTROL @ _RTE-CONTROL.ORDER @ OR IF 0 EXIT THEN
    _RTHP-CT-CONTROL @ _RTE-CONTROL.ROW @ DUP
        _RTHP-CT-TAB-ROOT-ROW ! DUP 0< IF DROP 0 EXIT THEN
    _RTHP-CT-CONTROL @ _RTE-CONTROL.HEIGHT @ DUP 0> 0= IF
        2DROP 0 EXIT
    THEN _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.ROWS @ U> IF 0 EXIT THEN
    _RTHP-CT-CONTROL @ _RTE-CONTROL.COL @ DUP
        _RTHP-CT-TAB-ROOT-COL ! DUP 0< IF DROP 0 EXIT THEN
    _RTHP-CT-CONTROL @ _RTE-CONTROL.WIDTH @ DUP 0> 0= IF
        2DROP 0 EXIT
    THEN _RTHP-U32+? 0= IF DROP 0 EXIT THEN DUP
        _RTHP-CT-TAB-ROOT-END !
    _RTHP-CT-P @ _RTHP.COLS @ U> IF 0 EXIT THEN
    _RTHP-CT-TAB-ROOT-COL @ 1 _RTHP-U32+?
        0= IF DROP 0 EXIT THEN _RTHP-CT-TAB-POS !
    _RTHP-CT-CONTROL @ DUP _RTHP-CT-TAB-ROOT !
        _RTE-CONTROL.ID @ _RTHP-CT-TAB-ROOT-ID !
    _RTHP-CT-CONTROL @ _RTE-CONTROL.STATE @
        _RTHP-CT-TAB-ROOT-STATE !
    _RTHP-CT-CORRELATION @ DUP RUCP-CORRELATION-ATTACHMENT@
        _RTHP-CT-TAB-ROOT-ATTACHMENT !
    DUP RUCP-CORRELATION-INDEX@ _RTHP-CT-TAB-ROOT-INDEX !
    DUP RUCP-CORRELATION-SCOPE@ IF DROP 0 EXIT THEN
    DUP RUCP-CORRELATION-SUBKEY@ _RTHP-CT-TAB-ROOT-KEY !
    RUCP-CORRELATION-LIFECYCLE-GENERATION@
        _RTHP-CT-TAB-ROOT-GENERATION !
    -1 ;

: _RTHP-CT-TAB-INVALID  ( -- target? valid? )  0 0 ;

: _RTHP-CT-TAB?  ( -- target? valid? )
    _RTHP-CT-TAB-ROOT @ 0= IF _RTHP-CT-TAB-INVALID EXIT THEN
    _RTHP-CT-CONTROL @ _RTE-CONTROL.KIND @
        RTE-CONTROL-TAB <> IF _RTHP-CT-TAB-INVALID EXIT THEN
    _RTHP-CT-CONTROL @ _RTE-CONTROL.PARENT @
        _RTHP-CT-TAB-ROOT-ID @ <> IF _RTHP-CT-TAB-INVALID EXIT THEN
    _RTHP-CT-CORRELATION @ DUP RUCP-CORRELATION-ATTACHMENT@
        _RTHP-CT-TAB-ROOT-ATTACHMENT @ <> IF
        DROP _RTHP-CT-TAB-INVALID EXIT
    THEN
    DUP RUCP-CORRELATION-INDEX@ _RTHP-CT-TAB-ROOT-INDEX @ <> IF
        DROP _RTHP-CT-TAB-INVALID EXIT
    THEN
    DUP RUCP-CORRELATION-SCOPE@ _RTHP-CT-TAB-ROOT-KEY @ <> IF
        DROP _RTHP-CT-TAB-INVALID EXIT
    THEN
    RUCP-CORRELATION-LIFECYCLE-GENERATION@
        _RTHP-CT-TAB-ROOT-GENERATION @ <> IF
        _RTHP-CT-TAB-INVALID EXIT
    THEN
    _RTHP-CT-CONTROL @ DUP _RTE-CONTROL.LABEL-U @ 0> 0= IF
        DROP _RTHP-CT-TAB-INVALID EXIT
    THEN
    DUP _RTE-CONTROL.LABEL-A @ OVER _RTE-CONTROL.LABEL-U @
        _RTHP-CT-TEXT-SPAN? 0= IF DROP _RTHP-CT-TAB-INVALID EXIT THEN
    DUP _RTE-CONTROL.SHORTCUT-A @ OVER _RTE-CONTROL.SHORTCUT-U @
        _RTHP-CT-TEXT-SPAN? 0= IF DROP _RTHP-CT-TAB-INVALID EXIT THEN
    DUP _RTE-CONTROL.STATE @ RTE-CONTROL-VISIBLE AND 0= IF
        DROP 0 -1 EXIT
    THEN
    _RTHP-CT-TAB-POS @ _RTHP-CT-COL !
    DUP _RTE-CONTROL.LABEL-U @ 2 _RTHP-U32+?
        0= IF 2DROP _RTHP-CT-TAB-INVALID EXIT THEN
    _RTHP-CT-TAB-POS @ SWAP _RTHP-U32+?
        0= IF DROP DROP _RTHP-CT-TAB-INVALID EXIT THEN
        _RTHP-CT-TAB-NEXT !
    DROP
    _RTHP-CT-TAB-NEXT @ _RTHP-CT-TAB-POS !
    _RTHP-CT-CONTROL @ _RTHP-CT-TARGET? 0= IF 0 -1 EXIT THEN
    _RTHP-CT-TAB-ROOT-STATE @
        RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR AND
        RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR <> IF 0 -1 EXIT THEN
    _RTHP-CT-COL @ _RTHP-CT-TAB-ROOT-END @ U< 0= IF
        0 -1 EXIT
    THEN
    _RTHP-CT-TAB-ROOT-ROW @ _RTHP-CT-ROW !
    -1 -1 ;

VARIABLE _RTHP-TG-P
VARIABLE _RTHP-TG-BANK
VARIABLE _RTHP-TG-BYTES
VARIABLE _RTHP-TG-COUNT

: _RTHP-TG-CLEAR  ( -- )
    _RTHP-CT-CLEAR
    0 _RTHP-TG-P ! 0 _RTHP-TG-BANK !
    0 _RTHP-TG-BYTES ! 0 _RTHP-TG-COUNT ! ;

: _RTHP-TG-APPEND-CURRENT?  ( -- flag )
    _RTHP-TG-COUNT @ _RTHP-TG-P @ _RTHP.MAX-CONTROLS @
        U< 0= IF 0 EXIT THEN
    _RTHP-TG-COUNT @ _RTHP-TG-BANK @ _RTHP-TARGET-ENTRY
    _RTHP-CT-ID @ OVER _RTHP-TE.ID !
    _RTHP-CT-ROW @ OVER _RTHP-TE.ROW !
    _RTHP-CT-COL @ OVER _RTHP-TE.COL !
    _RTHP-TG-P @ _RTHP.SOURCE-CONTENT-EPOCH @ OVER _RTHP-TE.REVISION !
    _RTHP-CT-CONTROL @ _RTE-CONTROL.KIND @ DUP
        _RTHP-KIND-INTENTS 2 PICK _RTHP-TE.INTENTS !
    SWAP _RTHP-TE.KIND !
    1 _RTHP-TG-COUNT +!
    -1 ;

\ An enabled text root is one positioned-input target.  Its routing cell is
\ the root's first cell: routing needs only a cell inside the ordinary
\ widget, because the item key and scalar offset travel with the event.
: _RTHP-CT-TEXT-ROOT?  ( -- target? valid? )
    _RTHP-CT-CONTROL @ _RTE-CONTROL.PARENT @
    _RTHP-CT-CONTROL @ _RTE-CONTROL.ORDER @ OR IF 0 0 EXIT THEN
    _RTHP-CT-CONTROL @ _RTE-CONTROL.ROW @ DUP _RTHP-CT-ROW !
        DUP 0< IF DROP 0 0 EXIT THEN
    _RTHP-CT-CONTROL @ _RTE-CONTROL.HEIGHT @ DUP 0> 0= IF
        2DROP 0 0 EXIT
    THEN _RTHP-U32+? 0= IF DROP 0 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.ROWS @ U> IF 0 0 EXIT THEN
    _RTHP-CT-CONTROL @ _RTE-CONTROL.COL @ DUP _RTHP-CT-COL !
        DUP 0< IF DROP 0 0 EXIT THEN
    _RTHP-CT-CONTROL @ _RTE-CONTROL.WIDTH @ DUP 0> 0= IF
        2DROP 0 0 EXIT
    THEN _RTHP-U32+? 0= IF DROP 0 0 EXIT THEN
    _RTHP-CT-P @ _RTHP.COLS @ U> IF 0 0 EXIT THEN
    _RTHP-CT-CONTROL @ _RTE-CONTROL.STATE @
        RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR AND
        RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR =
    -1 ;

: _RTHP-TG-COLLECTION-TARGETS?  ( -- flag )
    0 _RTHP-CT-TAB-ROOT !
    _RTHP-TG-P @ _RTHP.MENU-CONTROL-COUNT @ _RTHP-CT-ORDINAL !
    BEGIN _RTHP-CT-ORDINAL @
        _RTHP-TG-P @ _RTHP.CONTROL-COUNT @
        _RTHP-TG-P @ _RTHP.FIELD-COUNT @ -
        _RTHP-TG-P @ _RTHP.DIALOG-CONTROLS @ - U< WHILE
        _RTHP-CT-ORDINAL @ _RTHP-CT-COLLECTION-CONTROL-AT?
            0= IF 0 EXIT THEN
        _RTHP-CT-CONTROL @ _RTE-CONTROL.KIND @ DUP
            _RTHP-CONTENT-CONTROL-KIND? IF
            DROP 0 _RTHP-CT-TAB-ROOT !
            _RTHP-CT-TEXT-ROOT? 0= IF DROP 0 EXIT THEN
            IF _RTHP-TG-APPEND-CURRENT? 0= IF 0 EXIT THEN THEN
        ELSE
            DUP RTE-CONTROL-TABSET = IF
                DROP _RTHP-CT-TABSET? 0= IF 0 EXIT THEN
            ELSE
                RTE-CONTROL-TAB <> IF 0 EXIT THEN
                _RTHP-CT-TAB? 0= IF DROP 0 EXIT THEN
                IF _RTHP-TG-APPEND-CURRENT? 0= IF 0 EXIT THEN THEN
            THEN
        THEN
        1 _RTHP-CT-ORDINAL +!
    REPEAT
    -1 ;

\ FIELD return coordinates and revisions come only from the sealed FDC1.
\ Its value slot need not begin at the root's first cell.
: _RTHP-FLD-LE16@ ( a -- u ) DUP C@ SWAP 1+ C@ 8 LSHIFT OR ;
: _RTHP-FLD-LE32@ ( a -- u )
    DUP _RTHP-FLD-LE16@ SWAP 2 + _RTHP-FLD-LE16@ 16 LSHIFT OR ;
: _RTHP-FLD-LE64@ ( a -- u )
    DUP _RTHP-FLD-LE32@ SWAP 4 + _RTHP-FLD-LE32@ 32 LSHIFT OR ;

VARIABLE _RTHP-FT-CONTENT
VARIABLE _RTHP-FT-REVISION
VARIABLE _RTHP-FT-INTENTS

: _RTHP-CT-FIELD? ( -- target? valid? )
    _RTHP-CT-CONTROL @ DUP _RTE-CONTROL.KIND @ RTE-CONTROL-FIELD <> IF
        DROP 0 0 EXIT
    THEN
    DUP _RTE-CONTROL.PARENT @ OVER _RTE-CONTROL.ORDER @ OR
    OVER _RTE-CONTROL.SHORTCUT-A @ OR OVER _RTE-CONTROL.SHORTCUT-U @ OR
    OVER _RTE-CONTROL.CONTENT-RUNS @ OR OVER _RTE-CONTROL.CONTENT-FIELDS @ OR IF
        DROP 0 0 EXIT
    THEN
    DUP _RTE-CONTROL.LABEL-A @ OVER _RTE-CONTROL.LABEL-U @
        _RTHP-CT-TEXT-SPAN? 0= IF DROP 0 0 EXIT THEN
    DUP _RTE-CONTROL.CONTENT-A @ OVER _RTE-CONTROL.CONTENT-U @
        _RTHP-CT-TEXT-SPAN? 0= IF DROP 0 0 EXIT THEN
    DUP _RTE-CONTROL.CONTENT-A @ _RTHP-FT-CONTENT !
    DROP
    _RTHP-FT-CONTENT @ _RTHP-CT-CONTROL @ _RTE-CONTROL.CONTENT-U @
    _RTHP-CT-CONTROL @ _RTE-CONTROL.LABEL-A @
    _RTHP-CT-CONTROL @ _RTE-CONTROL.LABEL-U @
    _RTHP-CT-CONTROL @ _RTE-CONTROL.WIDTH @
    _RTHP-CT-CONTROL @ _RTE-CONTROL.HEIGHT @ FDC1-VALIDATE
        0= IF 2DROP 0 0 EXIT THEN
    _RTHP-CT-CONTROL @ _RTE-CONTROL.CONTENT-UTF8 @ <>
    SWAP _RTHP-CT-CONTROL @ _RTE-CONTROL.CONTENT-ITEMS @ <> OR IF 0 0 EXIT THEN
    _RTHP-FT-CONTENT @ 8 + _RTHP-FLD-LE64@ _RTHP-FT-REVISION !
    \ A TEXT field takes positions in its value; the others take a press
    \ and adjustments.
    _RTHP-FT-CONTENT @ 6 + _RTHP-FLD-LE16@ 3 = IF
        1 RTE-INTENT-PLACE LSHIFT 1 RTE-INTENT-EXTEND LSHIFT OR
    ELSE
        1 RTE-INTENT-ACTIVATE LSHIFT 1 RTE-INTENT-ADJUST LSHIFT OR
    THEN _RTHP-FT-INTENTS !
    _RTHP-CT-CONTROL @ _RTE-CONTROL.ROW @
    _RTHP-FT-CONTENT @ 44 + _RTHP-FLD-LE32@ _RTHP-U32+?
        0= IF DROP 0 0 EXIT THEN DUP _RTHP-CT-ROW !
    _RTHP-CT-P @ _RTHP.ROWS @ U< 0= IF 0 0 EXIT THEN
    _RTHP-CT-CONTROL @ _RTE-CONTROL.COL @
    _RTHP-FT-CONTENT @ 40 + _RTHP-FLD-LE32@ _RTHP-U32+?
        0= IF DROP 0 0 EXIT THEN DUP _RTHP-CT-COL !
    _RTHP-CT-P @ _RTHP.COLS @ U< 0= IF 0 0 EXIT THEN
    _RTHP-CT-CONTROL @ _RTE-CONTROL.STATE @
        RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR AND
        RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR =
    \ READ_ONLY takes no input; MASKED does.
    _RTHP-FT-CONTENT @ 16 + _RTHP-FLD-LE32@ 1 AND 0= AND -1 ;

\ The fields lie just before the dialog lane.
: _RTHP-TG-FIELD-TARGETS? ( -- flag )
    _RTHP-TG-P @ _RTHP.FIELD-COUNT @
    _RTHP-TG-P @ _RTHP.DIALOG-CONTROLS @ _RTHP-U32+? 0= IF DROP 0 EXIT THEN
        _RTHP-TG-P @ _RTHP.CONTROL-COUNT @ U> IF 0 EXIT THEN
    _RTHP-TG-P @ _RTHP.CONTROL-COUNT @ _RTHP-TG-P @ _RTHP.DIALOG-CONTROLS @ -
    DUP _RTHP-TG-P @ _RTHP.FIELD-COUNT @ - ?DO
        _RTHP-TG-P @ _RTHP.CONTROLS-A @ I RTE-CONTROL-SIZE * +
            DUP _RTHP-CT-CONTROL ! _RTE-CONTROL.ID @ _RTHP-CT-ID !
        _RTHP-CT-FIELD? 0= IF DROP 0 UNLOOP EXIT THEN IF
            _RTHP-TG-APPEND-CURRENT? 0= IF 0 UNLOOP EXIT THEN
            _RTHP-TG-COUNT @ 1- _RTHP-TG-BANK @ _RTHP-TARGET-ENTRY
            _RTHP-FT-REVISION @ OVER _RTHP-TE.REVISION !
            _RTHP-FT-INTENTS @ SWAP _RTHP-TE.INTENTS !
        THEN
    LOOP -1 ;

\ A shown, enabled BUTTON is a press target, routed like a text root to its
\ first cell, which the dialog's own button covers.  A DIALOG takes only the
\ wheel, below.
: _RTHP-CT-BUTTON? ( -- target? valid? )
    _RTHP-CT-CONTROL @ _RTE-CONTROL.KIND @ RTE-CONTROL-BUTTON <> IF 0 -1 EXIT THEN
    _RTHP-CT-TEXT-ROOT? ;

\ A dialog that is not a notice takes the wheel, which scrolls its message.
\ Its routing cell is its root's first cell, as a text root's is, and it is
\ a target while visible, having no enabled state.  The NOTICE flag is bit 0
\ of its DLG1 flags.
: _RTHP-CT-DIALOG? ( -- target? valid? )
    _RTHP-CT-CONTROL @ _RTE-CONTROL.KIND @ RTE-CONTROL-DIALOG <> IF 0 -1 EXIT THEN
    _RTHP-CT-CONTROL @ _RTE-CONTROL.CONTENT-A @ 6 + C@ UDLG-F-NOTICE AND IF
        0 -1 EXIT
    THEN
    _RTHP-CT-TEXT-ROOT? 0= IF DROP 0 0 EXIT THEN DROP
    _RTHP-CT-CONTROL @ _RTE-CONTROL.STATE @ RTE-CONTROL-VISIBLE AND 0<> -1 ;

: _RTHP-TG-DIALOG-TARGETS? ( -- flag )
    _RTHP-TG-P @ _RTHP.DIALOG-CONTROLS @
        _RTHP-TG-P @ _RTHP.CONTROL-COUNT @ U> IF 0 EXIT THEN
    _RTHP-TG-P @ _RTHP.CONTROL-COUNT @
    DUP _RTHP-TG-P @ _RTHP.DIALOG-CONTROLS @ - ?DO
        _RTHP-TG-P @ _RTHP.CONTROLS-A @ I RTE-CONTROL-SIZE * +
            DUP _RTHP-CT-CONTROL ! _RTE-CONTROL.ID @ _RTHP-CT-ID !
        _RTHP-CT-BUTTON? 0= IF DROP 0 UNLOOP EXIT THEN IF
            _RTHP-TG-APPEND-CURRENT? 0= IF 0 UNLOOP EXIT THEN
        THEN
        _RTHP-CT-DIALOG? 0= IF DROP 0 UNLOOP EXIT THEN IF
            _RTHP-TG-APPEND-CURRENT? 0= IF 0 UNLOOP EXIT THEN
        THEN
    LOOP -1 ;

: _RTHP-DELTA-PLAN-CLEAR  ( producer -- )
    _RTHP.DELTA-PLAN-VALID 88 0 FILL ;

: _RTHP-TARGET-ABORT  ( producer -- )
    DUP RTHPX-ABORT SWAP _RTHP-EXTENSION-NOTIFY
    DUP _RTHP-DELTA-PLAN-CLEAR
    0 OVER _RTHP.PENDING-FACTS _RTHP-KF.BANK !
    DUP _RTHP.TARGET-PENDING @ ?DUP IF
        0 SWAP _RTHP-TB.VALID !
    THEN
    0 OVER _RTHP.PENDING-SEAL !
    0 SWAP _RTHP.TARGET-PENDING ! _RTHP-TG-CLEAR ;

: _RTHP-TG-FAIL  ( -- false )
    _RTHP-TG-P @ ?DUP IF _RTHP-TARGET-ABORT ELSE _RTHP-TG-CLEAR THEN
    0 ;

: _RTHP-TARGET-INACTIVE  ( producer -- bank )
    DUP _RTHP.TARGET-ACTIVE @ OVER _RTHP.TARGET0-A @ = IF
        _RTHP.TARGET1-A @
    ELSE
        _RTHP.TARGET0-A @
    THEN ;

VARIABLE _RTHP-PK-STATICS-A
VARIABLE _RTHP-PK-STATICS-U
VARIABLE _RTHP-PK-STATIC-CORR-A
VARIABLE _RTHP-PK-STATIC-CORR-U
VARIABLE _RTHP-PK-STATIC-TEXT-A
VARIABLE _RTHP-PK-STATIC-TEXT-U
VARIABLE _RTHP-PK-STATIC
VARIABLE _RTHP-PK-P
VARIABLE _RTHP-PK-BANK
VARIABLE _RTHP-PK-BANK-U
VARIABLE _RTHP-PK-PREFIX
VARIABLE _RTHP-PK-TOTAL
VARIABLE _RTHP-PK-CONTROL-U
VARIABLE _RTHP-PK-CORR-U
VARIABLE _RTHP-PK-SOURCE-U
VARIABLE _RTHP-PK-ITEM-U
VARIABLE _RTHP-PK-REF-U
VARIABLE _RTHP-PK-GLYPH-U
VARIABLE _RTHP-PK-DIRECTORY-U
VARIABLE _RTHP-PK-MENU-ROWS-U
VARIABLE _RTHP-PK-INSTRUMENT-REGIONS-U
VARIABLE _RTHP-PK-INSTRUMENTS-U
VARIABLE _RTHP-PK-INSTRUMENT-CORR-U
VARIABLE _RTHP-PK-INSTRUMENT-UNITS-U
VARIABLE _RTHP-PK-PROJECTION-RECTS-U
VARIABLE _RTHP-PK-PACK-A
VARIABLE _RTHP-PK-CURSOR
VARIABLE _RTHP-PK-CONTROLS-A
VARIABLE _RTHP-PK-CORR-A
VARIABLE _RTHP-PK-SOURCE-A
VARIABLE _RTHP-PK-ITEMS-A
VARIABLE _RTHP-PK-REFS-A
VARIABLE _RTHP-PK-GLYPH-A
VARIABLE _RTHP-PK-DIRECTORY-A
VARIABLE _RTHP-PK-MENU-ROWS-A
VARIABLE _RTHP-PK-INSTRUMENT-REGIONS-A
VARIABLE _RTHP-PK-INSTRUMENTS-A
VARIABLE _RTHP-PK-INSTRUMENT-CORR-A
VARIABLE _RTHP-PK-INSTRUMENT-UNITS-A
VARIABLE _RTHP-PK-PROJECTION-RECTS-A
VARIABLE _RTHP-PK-CONTROL
VARIABLE _RTHP-PK-INSTRUMENT
VARIABLE _RTHP-PK-OLD-A
VARIABLE _RTHP-PK-OLD-U
VARIABLE _RTHP-PK-SPAN-A
VARIABLE _RTHP-PK-SPAN-U
VARIABLE _RTHP-PK-SPAN-CAP
VARIABLE _RTHP-PK-CHECK-ITEMS
VARIABLE _RTHP-PK-CHECK-REFS
VARIABLE _RTHP-PK-REF-O
VARIABLE _RTHP-PK-REF-U0

VARIABLE _RTHP-PK-SERIES-A
VARIABLE _RTHP-PK-SERIES-U
VARIABLE _RTHP-PK-SERIES-CORR-A
VARIABLE _RTHP-PK-SERIES-CORR-U
VARIABLE _RTHP-PK-SERIES-SAMPLES-A
VARIABLE _RTHP-PK-SERIES-SAMPLES-U
VARIABLE _RTHP-PK-SERIES

: _RTHP-PK-CLEAR  ( -- )
    0 _RTHP-PK-SERIES-A !
    0 _RTHP-PK-SERIES-U !
    0 _RTHP-PK-SERIES-CORR-A !
    0 _RTHP-PK-SERIES-CORR-U !
    0 _RTHP-PK-SERIES-SAMPLES-A !
    0 _RTHP-PK-SERIES-SAMPLES-U !
    0 _RTHP-PK-SERIES !

    0 _RTHP-PK-STATICS-A !
    0 _RTHP-PK-STATICS-U !
    0 _RTHP-PK-STATIC-CORR-A !
    0 _RTHP-PK-STATIC-CORR-U !
    0 _RTHP-PK-STATIC-TEXT-A !
    0 _RTHP-PK-STATIC-TEXT-U !
    0 _RTHP-PK-STATIC !
    0 _RTHP-PK-P ! 0 _RTHP-PK-BANK ! 0 _RTHP-PK-BANK-U !
    0 _RTHP-PK-PREFIX ! 0 _RTHP-PK-TOTAL !
    0 _RTHP-PK-CONTROL-U ! 0 _RTHP-PK-CORR-U !
    0 _RTHP-PK-SOURCE-U ! 0 _RTHP-PK-ITEM-U !
    0 _RTHP-PK-REF-U ! 0 _RTHP-PK-GLYPH-U !
    0 _RTHP-PK-DIRECTORY-U ! 0 _RTHP-PK-MENU-ROWS-U !
    0 _RTHP-PK-INSTRUMENT-REGIONS-U ! 0 _RTHP-PK-INSTRUMENTS-U !
    0 _RTHP-PK-INSTRUMENT-CORR-U ! 0 _RTHP-PK-INSTRUMENT-UNITS-U !
    0 _RTHP-PK-PROJECTION-RECTS-U !
    0 _RTHP-PK-PACK-A ! 0 _RTHP-PK-CURSOR !
    0 _RTHP-PK-CONTROLS-A ! 0 _RTHP-PK-CORR-A !
    0 _RTHP-PK-SOURCE-A ! 0 _RTHP-PK-ITEMS-A !
    0 _RTHP-PK-REFS-A ! 0 _RTHP-PK-GLYPH-A !
    0 _RTHP-PK-DIRECTORY-A ! 0 _RTHP-PK-MENU-ROWS-A !
    0 _RTHP-PK-INSTRUMENT-REGIONS-A ! 0 _RTHP-PK-INSTRUMENTS-A !
    0 _RTHP-PK-INSTRUMENT-CORR-A ! 0 _RTHP-PK-INSTRUMENT-UNITS-A !
    0 _RTHP-PK-PROJECTION-RECTS-A !
    0 _RTHP-PK-CONTROL ! 0 _RTHP-PK-INSTRUMENT !
    0 _RTHP-PK-OLD-A ! 0 _RTHP-PK-OLD-U !
    0 _RTHP-PK-SPAN-A ! 0 _RTHP-PK-SPAN-U ! 0 _RTHP-PK-SPAN-CAP !
    0 _RTHP-PK-CHECK-ITEMS ! 0 _RTHP-PK-CHECK-REFS !
    0 _RTHP-PK-REF-O ! 0 _RTHP-PK-REF-U0 ! ;

: _RTHP-PK-FINISH  ( flag -- flag )
    _RTHP-PK-CLEAR ;

: _RTHP-PK-ADD?  ( bytes -- flag )
    _RTHP-PK-TOTAL @ SWAP _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-PK-TOTAL ! -1 ;

: _RTHP-PK-TAKE  ( bytes -- address )
    _RTHP-PK-CURSOR @ SWAP _RTHP-PK-CURSOR +! ;

: _RTHP-PK-BOUNDED-SOURCE?  ( address used capacity -- flag )
    _RTHP-PK-SPAN-CAP ! _RTHP-PK-SPAN-U ! _RTHP-PK-SPAN-A !
    _RTHP-PK-SPAN-U @ _RTHP-PK-SPAN-CAP @ U> IF 0 EXIT THEN
    _RTHP-PK-SPAN-U @ 0= IF -1 EXIT THEN
    _RTHP-PK-SPAN-A @ _RTHP-PK-SPAN-U @ _RTHP-PK-P @
        _RTHP-ARENA-SPAN? ;

VARIABLE _RTHP-SH-B
VARIABLE _RTHP-SH-P
: _RTHP-SERIES-HEADER? ( bank producer -- flag )
    _RTHP-SH-P ! _RTHP-SH-B !
    _RTHP-SH-B @ _RTHP-TB.SERIES-COUNT @ _RTHP-SH-P @ _RTHP.MAX-SERIES @ U> IF 0 EXIT THEN
    _RTHP-SH-B @ _RTHP-TB.SERIES-SAMPLE-BYTES @
        _RTHP-SH-P @ _RTHP.SERIES-SAMPLES-U @ U> IF 0 EXIT THEN
    _RTHP-SH-B @ _RTHP-TB.SERIES-SAMPLE-BYTES @ 7 AND IF 0 EXIT THEN
    _RTHP-SH-B @ _RTHP-TB.WAVEFORM-COUNT @
        _RTHP-SH-B @ _RTHP-TB.INSTRUMENT-COUNT @ U> IF 0 EXIT THEN
    7 0 DO _RTHP-SH-B @ _RTHP-TB.SERIES-SAMPLE-BYTES I 8 * + @
        _RTHP-U32? 0= IF 0 UNLOOP EXIT THEN LOOP
    _RTHP-SH-B @ _RTHP-TB.SERIES-COUNT @ 0= IF
        8 0 DO _RTHP-SH-B @ _RTHP-TB.FIRST-SERIES I 8 * + @ IF 0 UNLOOP EXIT THEN LOOP
        -1 EXIT
    THEN
    _RTHP-SH-B @ _RTHP-TB.FIRST-SERIES @ DUP 0= IF DROP 0 EXIT THEN
    _RTHP-SH-B @ _RTHP-TB.SERIES-COUNT @ 1- _RTHP-U+?
        0= IF DROP 0 EXIT THEN DROP
    _RTHP-SH-B @ _RTHP-TB.SERIES-SLOTS @
        _RTHP-SH-B @ _RTHP-TB.SERIES-COUNT @ U< IF 0 EXIT THEN
    _RTHP-SH-B @ _RTHP-TB.SERIES-HISTORY-MAX @ DUP 0= IF DROP 0 EXIT THEN
    _RTHP-SH-B @ _RTHP-TB.SERIES-SLOTS @ U> IF 0 EXIT THEN
    _RTHP-SH-B @ _RTHP-TB.SERIES-SAMPLE-BYTES @ 0= IF
        _RTHP-SH-B @ _RTHP-TB.SERIES-CHUNKS @
        _RTHP-SH-B @ _RTHP-TB.SERIES-CHUNK-MAX @ OR
        _RTHP-SH-B @ _RTHP-TB.SERIES-CHUNK-BYTES-MAX @ OR 0= EXIT
    THEN
    _RTHP-SH-B @ _RTHP-TB.SERIES-CHUNKS @ 0<>
    _RTHP-SH-B @ _RTHP-TB.SERIES-CHUNK-MAX @ 0<> AND
    _RTHP-SH-B @ _RTHP-TB.SERIES-CHUNK-BYTES-MAX @ 0<> AND ;

\ A bank's dialog lane holds its dialogs and their buttons, each dialog
\ first, within the producer's capacities.
: _RTHP-TB-DIALOGS?  ( bank producer -- flag )
    >R
    DUP _RTHP-TB.DIALOG-CONTROLS @ R@ _RTHP.MAX-DIALOG-CONTROLS @ U> IF
        R> 2DROP 0 EXIT
    THEN
    DUP _RTHP-TB.DIALOG-COUNT @ R> _RTHP.MAX-DIALOGS @ U> IF DROP 0 EXIT THEN
    DUP _RTHP-TB.DIALOG-UTF8 @ _RTHP-U32? 0= IF DROP 0 EXIT THEN
    DUP _RTHP-TB.DIALOG-COUNT @ OVER _RTHP-TB.DIALOG-CONTROLS @ U> IF
        DROP 0 EXIT
    THEN
    DUP _RTHP-TB.DIALOG-CONTROLS @ IF _RTHP-TB.DIALOG-COUNT @ 0<> EXIT THEN
    DUP _RTHP-TB.DIALOG-COUNT @ SWAP _RTHP-TB.DIALOG-UTF8 @ OR 0= ;

: _RTHP-PK-LAYOUT?  ( -- flag )
    _RTHP-PK-BANK @ _RTHP-PK-P @ _RTHP-SERIES-HEADER? 0= IF 0 EXIT THEN
    _RTHP-PK-P @ _RTHP-TARGET-BANK-BYTES?
        0= IF DROP 0 EXIT THEN _RTHP-PK-BANK-U !
    _RTHP-PK-BANK @ _RTHP-TB.DOCUMENT-COUNT @ DUP
        0> 0= IF DROP 0 EXIT THEN
    DUP _RTHP-PK-P @ _RTHP.MAX-DOCUMENTS @ U> IF DROP 0 EXIT THEN
    RUHA-DOCUMENT-SIZE _RTHP-U32*? 0= IF DROP 0 EXIT THEN
        _RTHP-PK-DIRECTORY-U !
    _RTHP-PK-BANK @ _RTHP-TB.COUNT @
        _RTHP-PK-P @ _RTHP.MAX-CONTROLS @ U> IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.CONTROL-COUNT @
        _RTHP-PK-P @ _RTHP.MAX-CONTROLS @ U> IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.MENU-CONTROL-COUNT @ DUP
        _RTHP-PK-P @ _RTHP.MAX-RECORDS @ U> IF DROP 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.CONTROL-COUNT @ U> IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.COUNT @
        _RTHP-PK-BANK @ _RTHP-TB.CONTROL-COUNT @ U> IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.COLLECTION-COUNT @ DUP
        _RTHP-PK-P @ _RTHP.MAX-COLLECTIONS @ U> IF DROP 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.MENU-CONTROL-COUNT @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.FIELD-COUNT @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.DIALOG-CONTROLS @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.CONTROL-COUNT @ <> IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-PK-P @ _RTHP-TB-DIALOGS? 0= IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.FIELD-COUNT @ _RTHP-PK-P @ _RTHP.MAX-FIELDS @ U> IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.FIELD-ITEMS @ _RTHP-U32? 0= IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.FIELD-UTF8 @ _RTHP-U32? 0= IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.FIELD-COUNT @ 0= IF
        _RTHP-PK-BANK @ _RTHP-TB.FIELD-ITEMS @
        _RTHP-PK-BANK @ _RTHP-TB.FIELD-UTF8 @ OR IF 0 EXIT THEN
    THEN
    _RTHP-PK-BANK @ _RTHP-TB.COLLECTION-ITEMS @
        _RTHP-U32? 0= IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.COLLECTION-UTF8 @
        _RTHP-U32? 0= IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.COLLECTION-COUNT @ 0= IF
        _RTHP-PK-BANK @ _RTHP-TB.COLLECTION-ITEMS @
        _RTHP-PK-BANK @ _RTHP-TB.COLLECTION-UTF8 @ OR IF 0 EXIT THEN
    THEN
    _RTHP-PK-BANK @ _RTHP-TB.INSTRUMENT-REGION-COUNT @
        _RTHP-PK-P @ _RTHP.MAX-INSTRUMENT-REGIONS @ U> IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.INSTRUMENT-COUNT @
        _RTHP-PK-P @ _RTHP.MAX-INSTRUMENTS @ U> IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.INSTRUMENT-UNIT-BYTES @
        _RTHP-PK-P @ _RTHP.INSTRUMENT-UNITS-U @ U> IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.STATIC-COUNT @
        _RTHP-PK-P @ _RTHP.MAX-STATICS @ U> IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.STATIC-TEXT-BYTES @
        _RTHP-PK-P @ _RTHP.STATIC-TEXT-U @ U> IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.STATIC-COUNT @ 0= IF
        _RTHP-PK-BANK @ _RTHP-TB.STATIC-TEXT-BYTES @ IF 0 EXIT THEN
    THEN
    _RTHP-PK-BANK @ _RTHP-TB.INSTRUMENT-COUNT @ 0= IF
        _RTHP-PK-BANK @ _RTHP-TB.INSTRUMENT-REGION-COUNT @
        _RTHP-PK-BANK @ _RTHP-TB.INSTRUMENT-UNIT-BYTES @ OR IF
            0 EXIT
        THEN
    ELSE
        _RTHP-PK-BANK @ _RTHP-TB.INSTRUMENT-REGION-COUNT @ 0= IF
            0 EXIT
        THEN
    THEN
    _RTHP-PK-BANK @ _RTHP-TB.GLYPH-SLOT-COUNT @
        _RTHP-PK-BANK @ _RTHP-TB.COLS @
        _RTHP-PK-BANK @ _RTHP-TB.ROWS @ _RTHP-U32*?
        0= IF 2DROP 0 EXIT THEN U> IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.SOURCE-TEXT-USED @
        _RTHP-PK-P @ _RTHP.SOURCE-TEXT-U @ U> IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.MENU-TEXT-USED @ DUP
        _RTHP-PK-P @ _RTHP.MAX-TEXT @ U> IF DROP 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.SOURCE-TEXT-USED @ U> IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.COLLECTION-UTF8 @
    _RTHP-PK-BANK @ _RTHP-TB.FIELD-UTF8 @ _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.DIALOG-UTF8 @ _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.SOURCE-TEXT-USED @
    _RTHP-PK-BANK @ _RTHP-TB.MENU-TEXT-USED @ - U> IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.COLS @
        _RTHP-PK-BANK @ _RTHP-TB.ROWS @ _RTHP-U32*?
        0= IF DROP 0 EXIT THEN 4 _RTHP-U32*?
        0= IF DROP 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.GLYPH-TEXT-USED @ U< IF 0 EXIT THEN

    _RTHP-PK-BANK @ _RTHP-TB.COUNT @ _RTHP-TARGET-ENTRY-SIZE
        _RTHP-U32*? 0= IF DROP 0 EXIT THEN
    _RTHP-TARGET-BANK-HEADER-SIZE _RTHP-U32+?
        0= IF DROP 0 EXIT THEN _RTHP-PK-PREFIX !
    _RTHP-PK-PREFIX @ _RTHP-PK-BANK-U @ U> IF 0 EXIT THEN

    0 _RTHP-PK-TOTAL !
    _RTHP-PK-BANK @ _RTHP-TB.CONTROL-COUNT @ RTE-CONTROL-SIZE
        _RTHP-U32*? 0= IF DROP 0 EXIT THEN
        DUP _RTHP-PK-CONTROL-U ! _RTHP-PK-ADD? 0= IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.CONTROL-COUNT @ RUCP-CORRELATION-SIZE
        _RTHP-U32*? 0= IF DROP 0 EXIT THEN
        DUP _RTHP-PK-CORR-U ! _RTHP-PK-ADD? 0= IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.SOURCE-TEXT-USED @ _RTHP-ALIGN8?
        0= IF DROP 0 EXIT THEN
        DUP _RTHP-PK-SOURCE-U ! _RTHP-PK-ADD? 0= IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.GLYPH-SLOT-COUNT @
        RTE-GLYPH-RUN-PLAN-ITEM-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN
        DUP _RTHP-PK-ITEM-U ! _RTHP-PK-ADD? 0= IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.GLYPH-SLOT-COUNT @ RGRP-TEXT-REF-SIZE
        _RTHP-U32*? 0= IF DROP 0 EXIT THEN
        DUP _RTHP-PK-REF-U ! _RTHP-PK-ADD? 0= IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.GLYPH-TEXT-USED @ _RTHP-ALIGN8?
        0= IF DROP 0 EXIT THEN
        DUP _RTHP-PK-GLYPH-U ! _RTHP-PK-ADD? 0= IF 0 EXIT THEN
    _RTHP-PK-DIRECTORY-U @ _RTHP-PK-ADD? 0= IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.ROWS @ DUP _RTHP-POS-U32? 0= IF
        DROP 0 EXIT
    THEN
    DUP _RTHP-PK-P @ _RTHP.MAX-ROWS @ U> IF DROP 0 EXIT THEN
    _RTHP-ALIGN8? 0= IF DROP 0 EXIT THEN
        DUP _RTHP-PK-MENU-ROWS-U ! _RTHP-PK-ADD? 0= IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.INSTRUMENT-REGION-COUNT @
        RTE-INSTRUMENT-REGION-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN
        DUP _RTHP-PK-INSTRUMENT-REGIONS-U ! _RTHP-PK-ADD? 0= IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.INSTRUMENT-COUNT @
        RTE-INSTRUMENT-SIZE _RTHP-U32*? 0= IF DROP 0 EXIT THEN
        DUP _RTHP-PK-INSTRUMENTS-U ! _RTHP-PK-ADD? 0= IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.INSTRUMENT-COUNT @
        RUIP-CORRELATION-SIZE _RTHP-U32*? 0= IF DROP 0 EXIT THEN
        DUP _RTHP-PK-INSTRUMENT-CORR-U ! _RTHP-PK-ADD? 0= IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.INSTRUMENT-UNIT-BYTES @ _RTHP-ALIGN8?
        0= IF DROP 0 EXIT THEN
        DUP _RTHP-PK-INSTRUMENT-UNITS-U ! _RTHP-PK-ADD? 0= IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.STATIC-COUNT @ RTE-STATIC-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN
        DUP _RTHP-PK-STATICS-U ! _RTHP-PK-ADD? 0= IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.STATIC-COUNT @ _RTHP-STATIC-CORR-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN
        DUP _RTHP-PK-STATIC-CORR-U ! _RTHP-PK-ADD? 0= IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.STATIC-TEXT-BYTES @ _RTHP-ALIGN8?
        0= IF DROP 0 EXIT THEN
        DUP _RTHP-PK-STATIC-TEXT-U ! _RTHP-PK-ADD? 0= IF 0 EXIT THEN
    _RTHP-PK-P @ _RTHP.MAX-CONTROLS @
    _RTHP-PK-P @ _RTHP.MAX-INSTRUMENTS @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    _RTHP-PK-P @ _RTHP.MAX-STATICS @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.PROJECTION-RECTS @ SWAP U> IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.PROJECTION-RECTS @
        _RTHP-PROJECTION-RECT-SIZE _RTHP-U32*? 0= IF DROP 0 EXIT THEN
        DUP _RTHP-PK-PROJECTION-RECTS-U ! _RTHP-PK-ADD? 0= IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.SERIES-COUNT @ RTE-SERIES-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN DUP _RTHP-PK-SERIES-U ! _RTHP-PK-ADD? 0= IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.SERIES-COUNT @ _RTHP-SERIES-CORR-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN DUP _RTHP-PK-SERIES-CORR-U ! _RTHP-PK-ADD? 0= IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.SERIES-SAMPLE-BYTES @
        DUP _RTHP-PK-SERIES-SAMPLES-U ! _RTHP-PK-ADD? 0= IF 0 EXIT THEN
    _RTHP-PK-TOTAL @
        _RTHP-PK-BANK-U @ _RTHP-PK-PREFIX @ - U> IF 0 EXIT THEN

    _RTHP-PK-BANK @ _RTHP-PK-PREFIX @ _RTHP-U+?
        0= IF DROP 0 EXIT THEN DUP _RTHP-PK-PACK-A ! _RTHP-PK-CURSOR !
    _RTHP-PK-CONTROL-U @ _RTHP-PK-TAKE _RTHP-PK-CONTROLS-A !
    _RTHP-PK-CORR-U @ _RTHP-PK-TAKE _RTHP-PK-CORR-A !
    _RTHP-PK-SOURCE-U @ _RTHP-PK-TAKE _RTHP-PK-SOURCE-A !
    _RTHP-PK-ITEM-U @ _RTHP-PK-TAKE _RTHP-PK-ITEMS-A !
    _RTHP-PK-REF-U @ _RTHP-PK-TAKE _RTHP-PK-REFS-A !
    _RTHP-PK-GLYPH-U @ _RTHP-PK-TAKE _RTHP-PK-GLYPH-A !
    _RTHP-PK-DIRECTORY-U @ _RTHP-PK-TAKE _RTHP-PK-DIRECTORY-A !
    _RTHP-PK-MENU-ROWS-U @ _RTHP-PK-TAKE _RTHP-PK-MENU-ROWS-A !
    _RTHP-PK-INSTRUMENT-REGIONS-U @ _RTHP-PK-TAKE
        _RTHP-PK-INSTRUMENT-REGIONS-A !
    _RTHP-PK-INSTRUMENTS-U @ _RTHP-PK-TAKE _RTHP-PK-INSTRUMENTS-A !
    _RTHP-PK-INSTRUMENT-CORR-U @ _RTHP-PK-TAKE _RTHP-PK-INSTRUMENT-CORR-A !
    _RTHP-PK-INSTRUMENT-UNITS-U @ _RTHP-PK-TAKE _RTHP-PK-INSTRUMENT-UNITS-A !
    _RTHP-PK-STATICS-U @ _RTHP-PK-TAKE _RTHP-PK-STATICS-A !
    _RTHP-PK-STATIC-CORR-U @ _RTHP-PK-TAKE _RTHP-PK-STATIC-CORR-A !
    _RTHP-PK-STATIC-TEXT-U @ _RTHP-PK-TAKE _RTHP-PK-STATIC-TEXT-A !
    _RTHP-PK-PROJECTION-RECTS-U @ _RTHP-PK-TAKE
        _RTHP-PK-PROJECTION-RECTS-A !
    _RTHP-PK-SERIES-U @ _RTHP-PK-TAKE _RTHP-PK-SERIES-A !
    _RTHP-PK-SERIES-CORR-U @ _RTHP-PK-TAKE _RTHP-PK-SERIES-CORR-A !
    _RTHP-PK-SERIES-SAMPLES-U @ _RTHP-PK-TAKE _RTHP-PK-SERIES-SAMPLES-A !
    _RTHP-PK-CURSOR @
        _RTHP-PK-PACK-A @ _RTHP-PK-TOTAL @ + <> IF 0 EXIT THEN
    _RTHP-PK-TOTAL @ 0= IF -1 EXIT THEN
    _RTHP-PK-PACK-A @ _RTHP-PK-TOTAL @ _RTHP-PK-P @
        _RTHP-ARENA-SPAN? ;

: _RTHP-PK-SOURCE-SPANS?  ( -- flag )
    _RTHP-PK-P @ _RTHP.SOURCE-DIR-A @ 7 AND
    _RTHP-PK-P @ _RTHP.CONTROLS-A @ 7 AND OR
    _RTHP-PK-P @ _RTHP.CORR-A @ 7 AND OR
    _RTHP-PK-P @ _RTHP.GLYPH-ITEMS-A @ 7 AND OR
    _RTHP-PK-P @ _RTHP.GLYPH-REFS-A @ 7 AND OR
    _RTHP-PK-P @ _RTHP.INSTRUMENT-REGIONS-A @ 7 AND OR
    _RTHP-PK-P @ _RTHP.INSTRUMENTS-A @ 7 AND OR
    _RTHP-PK-P @ _RTHP.INSTRUMENT-CORR-A @ 7 AND OR
    _RTHP-PK-P @ _RTHP.STATICS-A @ 7 AND OR
    _RTHP-PK-P @ _RTHP.STATIC-CORR-A @ 7 AND OR
    _RTHP-PK-P @ _RTHP.SERIES-A @ 7 AND OR
    _RTHP-PK-P @ _RTHP.SERIES-CORR-A @ 7 AND OR
    _RTHP-PK-P @ _RTHP.SERIES-SAMPLES-A @ 7 AND OR IF 0 EXIT THEN
    _RTHP-PK-P @ _RTHP.CONTROLS-A @ _RTHP-PK-CONTROL-U @
        _RTHP-PK-P @ _RTHP.CONTROLS-U @ _RTHP-PK-BOUNDED-SOURCE?
        0= IF 0 EXIT THEN
    _RTHP-PK-P @ _RTHP.CORR-A @ _RTHP-PK-CORR-U @
        _RTHP-PK-P @ _RTHP.CORR-U @ _RTHP-PK-BOUNDED-SOURCE?
        0= IF 0 EXIT THEN
    _RTHP-PK-P @ _RTHP.SOURCE-TEXT-A @
        _RTHP-PK-BANK @ _RTHP-TB.SOURCE-TEXT-USED @
        _RTHP-PK-P @ _RTHP.SOURCE-TEXT-U @ _RTHP-PK-BOUNDED-SOURCE?
        0= IF 0 EXIT THEN
    _RTHP-PK-P @ _RTHP.GLYPH-ITEMS-A @ _RTHP-PK-ITEM-U @
        _RTHP-PK-P @ _RTHP.GLYPH-ITEMS-U @ _RTHP-PK-BOUNDED-SOURCE?
        0= IF 0 EXIT THEN
    _RTHP-PK-P @ _RTHP.GLYPH-REFS-A @ _RTHP-PK-REF-U @
        _RTHP-PK-P @ _RTHP.GLYPH-REFS-U @ _RTHP-PK-BOUNDED-SOURCE?
        0= IF 0 EXIT THEN
    _RTHP-PK-P @ _RTHP.GLYPH-TEXT-A @
        _RTHP-PK-BANK @ _RTHP-TB.GLYPH-TEXT-USED @
        _RTHP-PK-P @ _RTHP.GLYPH-TEXT-U @ _RTHP-PK-BOUNDED-SOURCE?
        0= IF 0 EXIT THEN
    _RTHP-PK-P @ _RTHP.SOURCE-DIR-USED @ _RTHP-PK-DIRECTORY-U @ <>
        IF 0 EXIT THEN
    _RTHP-PK-P @ _RTHP.SOURCE-DIR-A @ _RTHP-PK-DIRECTORY-U @
        _RTHP-PK-P @ _RTHP.SOURCE-DIR-U @ _RTHP-PK-BOUNDED-SOURCE?
        0= IF 0 EXIT THEN
    _RTHP-PK-P @ _RTHP.INSTRUMENT-REGIONS-A @
        _RTHP-PK-INSTRUMENT-REGIONS-U @
        _RTHP-PK-P @ _RTHP.INSTRUMENT-REGIONS-U @ _RTHP-PK-BOUNDED-SOURCE?
        0= IF 0 EXIT THEN
    _RTHP-PK-P @ _RTHP.INSTRUMENTS-A @ _RTHP-PK-INSTRUMENTS-U @
        _RTHP-PK-P @ _RTHP.INSTRUMENTS-U @ _RTHP-PK-BOUNDED-SOURCE?
        0= IF 0 EXIT THEN
    _RTHP-PK-P @ _RTHP.INSTRUMENT-CORR-A @ _RTHP-PK-INSTRUMENT-CORR-U @
        _RTHP-PK-P @ _RTHP.INSTRUMENT-CORR-U @ _RTHP-PK-BOUNDED-SOURCE?
        0= IF 0 EXIT THEN
    _RTHP-PK-P @ _RTHP.INSTRUMENT-UNITS-A @
        _RTHP-PK-BANK @ _RTHP-TB.INSTRUMENT-UNIT-BYTES @
        _RTHP-PK-P @ _RTHP.INSTRUMENT-UNITS-U @ _RTHP-PK-BOUNDED-SOURCE?
        0= IF 0 EXIT THEN
    _RTHP-PK-P @ _RTHP.STATICS-A @ _RTHP-PK-STATICS-U @
        _RTHP-PK-P @ _RTHP.STATICS-U @ _RTHP-PK-BOUNDED-SOURCE?
        0= IF 0 EXIT THEN
    _RTHP-PK-P @ _RTHP.STATIC-CORR-A @ _RTHP-PK-STATIC-CORR-U @
        _RTHP-PK-P @ _RTHP.STATIC-CORR-U @ _RTHP-PK-BOUNDED-SOURCE?
        0= IF 0 EXIT THEN
    _RTHP-PK-P @ _RTHP.STATIC-TEXT-A @
        _RTHP-PK-BANK @ _RTHP-TB.STATIC-TEXT-BYTES @
        _RTHP-PK-P @ _RTHP.STATIC-TEXT-U @ _RTHP-PK-BOUNDED-SOURCE? 0= IF 0 EXIT THEN
    _RTHP-PK-P @ _RTHP.SERIES-A @ _RTHP-PK-SERIES-U @
        _RTHP-PK-P @ _RTHP.SERIES-U @ _RTHP-PK-BOUNDED-SOURCE? 0= IF 0 EXIT THEN
    _RTHP-PK-P @ _RTHP.SERIES-CORR-A @ _RTHP-PK-SERIES-CORR-U @
        _RTHP-PK-P @ _RTHP.SERIES-CORR-U @ _RTHP-PK-BOUNDED-SOURCE? 0= IF 0 EXIT THEN
    _RTHP-PK-P @ _RTHP.SERIES-SAMPLES-A @ _RTHP-PK-SERIES-SAMPLES-U @
        _RTHP-PK-P @ _RTHP.SERIES-SAMPLES-U @ _RTHP-PK-BOUNDED-SOURCE? ;

: _RTHP-PK-TEXT-REBASE?  ( old-address bytes -- new-address flag )
    _RTHP-PK-OLD-U ! _RTHP-PK-OLD-A !
    _RTHP-PK-OLD-U @ 0= IF 0 -1 EXIT THEN
    _RTHP-PK-OLD-A @ _RTHP-PK-OLD-U @ MSPAN-NONWRAPPING? 0= IF
        0 0 EXIT
    THEN
    _RTHP-PK-OLD-A @ _RTHP-PK-P @ _RTHP.SOURCE-TEXT-A @ U< IF
        0 0 EXIT
    THEN
    _RTHP-PK-OLD-A @ _RTHP-PK-OLD-U @ +
    _RTHP-PK-P @ _RTHP.SOURCE-TEXT-A @
        _RTHP-PK-BANK @ _RTHP-TB.SOURCE-TEXT-USED @ + U> IF
        0 0 EXIT
    THEN
    _RTHP-PK-OLD-A @ _RTHP-PK-P @ _RTHP.SOURCE-TEXT-A @ -
    _RTHP-PK-SOURCE-A @ _RTHP-U+? ;

: _RTHP-PK-CONTROL-REBASE?  ( packed-control -- flag )
    _RTHP-PK-CONTROL !
    _RTHP-PK-CONTROL @ _RTE-CONTROL.LABEL-A @
    _RTHP-PK-CONTROL @ _RTE-CONTROL.LABEL-U @ _RTHP-PK-TEXT-REBASE?
        0= IF DROP 0 EXIT THEN
        _RTHP-PK-CONTROL @ _RTE-CONTROL.LABEL-A !
    _RTHP-PK-CONTROL @ _RTE-CONTROL.SHORTCUT-A @
    _RTHP-PK-CONTROL @ _RTE-CONTROL.SHORTCUT-U @ _RTHP-PK-TEXT-REBASE?
        0= IF DROP 0 EXIT THEN
        _RTHP-PK-CONTROL @ _RTE-CONTROL.SHORTCUT-A !
    _RTHP-PK-CONTROL @ _RTE-CONTROL.CONTENT-A @
    _RTHP-PK-CONTROL @ _RTE-CONTROL.CONTENT-U @ _RTHP-PK-TEXT-REBASE?
        0= IF DROP 0 EXIT THEN
        _RTHP-PK-CONTROL @ _RTE-CONTROL.CONTENT-A !
    -1 ;

: _RTHP-PK-REFS?  ( items-a refs-a -- flag )
    _RTHP-PK-CHECK-REFS ! _RTHP-PK-CHECK-ITEMS !
    _RTHP-PK-BANK @ _RTHP-TB.GLYPH-SLOT-COUNT @ 0 ?DO
        _RTHP-PK-CHECK-REFS @ I RGRP-TEXT-REF-SIZE * +
        DUP RGRP-TEXT-REF-OFFSET@ _RTHP-PK-REF-O !
        RGRP-TEXT-REF-LENGTH@ _RTHP-PK-REF-U0 !
        _RTHP-PK-REF-O @
            _RTHP-PK-BANK @ _RTHP-TB.GLYPH-TEXT-USED @ U> IF
            0 UNLOOP EXIT
        THEN
        _RTHP-PK-REF-U0 @
        _RTHP-PK-BANK @ _RTHP-TB.GLYPH-TEXT-USED @
            _RTHP-PK-REF-O @ - U> IF 0 UNLOOP EXIT THEN
        _RTHP-PK-CHECK-ITEMS @
            I RTE-GLYPH-RUN-PLAN-ITEM-SIZE * + _RTE-LPI.TEXT-CAPACITY @
            _RTHP-PK-REF-U0 @ <> IF 0 UNLOOP EXIT THEN
    LOOP
    -1 ;

: _RTHP-PK-BEGIN?  ( bank producer -- flag )
    _RTHP-PK-P ! _RTHP-PK-BANK !
    0 _RTHP-PK-BANK @ _RTHP-TB.VALID !
    0 _RTHP-PK-BANK @ _RTHP-TB.PACKED-BYTES !
    _RTHP-PK-P @ _RTHP.CLAIMS-USED @ DUP RUCL-CLAIM-SIZE MOD IF
        DROP 0 EXIT
    THEN
    RUCL-CLAIM-SIZE / DUP _RTHP-PK-P @ _RTHP.MENU-CLAIMS @ U< IF
        DROP 0 EXIT
    THEN
    _RTHP-PK-P @ _RTHP.MENU-CLAIMS @ -
        _RTHP-PK-BANK @ _RTHP-TB.PROJECTION-RECTS !
    _RTHP-PK-LAYOUT? 0= IF 0 EXIT THEN
    _RTHP-PK-SOURCE-SPANS? ;

\ Preserve the rows covered by menu replacements in each immutable target.
\ CONTROL children deliberately have no CELL rectangle; their host geometry
\ cannot recover this authority after the next source snapshot replaces it.
VARIABLE _RTHP-MR-CLAIMS
VARIABLE _RTHP-MR-COUNT
VARIABLE _RTHP-MR-ROWS
VARIABLE _RTHP-MR-HEIGHT
VARIABLE _RTHP-MR-CLAIM
VARIABLE _RTHP-MR-ROW0
VARIABLE _RTHP-MR-ROW1

: _RTHP-MENU-ROWS!  ( claims-a claims-u menu-count rows-a rows-u -- flag )
    _RTHP-MR-HEIGHT ! _RTHP-MR-ROWS ! _RTHP-MR-COUNT !
    DUP RUCL-CLAIM-SIZE MOD IF 2DROP 0 EXIT THEN
    DUP RUCL-CLAIM-SIZE / _RTHP-MR-COUNT @ U< IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    DROP _RTHP-MR-CLAIMS !
    _RTHP-MR-ROWS @ 0= _RTHP-MR-HEIGHT @ 0= OR IF 0 EXIT THEN
    _RTHP-MR-ROWS @ _RTHP-MR-HEIGHT @ MSPAN-NONWRAPPING? 0= IF
        0 EXIT
    THEN
    _RTHP-MR-ROWS @ _RTHP-MR-HEIGHT @ 0 FILL
    _RTHP-MR-COUNT @ 0 ?DO
        _RTHP-MR-CLAIMS @ I RUCL-CLAIM-SIZE * + DUP _RTHP-MR-CLAIM !
        RUCL-CLAIM-ROW0@ DUP _RTHP-MR-ROW0 ! 0< IF 0 UNLOOP EXIT THEN
        _RTHP-MR-CLAIM @ RUCL-CLAIM-ROW1@ DUP _RTHP-MR-ROW1 !
        _RTHP-MR-HEIGHT @ U> IF 0 UNLOOP EXIT THEN
        _RTHP-MR-ROW0 @ _RTHP-MR-ROW1 @ U< 0= IF 0 UNLOOP EXIT THEN
        _RTHP-MR-ROWS @ _RTHP-MR-ROW0 @ +
        _RTHP-MR-ROW1 @ _RTHP-MR-ROW0 @ - 1 FILL
    LOOP
    -1 ;

: _RTHP-PK-MENU-ROWS?  ( -- flag )
    _RTHP-PK-P @ _RTHP.CLAIMS-USED @ DUP
        _RTHP-PK-P @ _RTHP.CLAIMS-U @ U> IF DROP 0 EXIT THEN
    DUP IF
        _RTHP-PK-P @ _RTHP.CLAIMS-A @ OVER _RTHP-PK-P @
            _RTHP-ARENA-SPAN? 0= IF DROP 0 EXIT THEN
    THEN
    _RTHP-PK-P @ _RTHP.CLAIMS-A @ SWAP
    _RTHP-PK-P @ _RTHP.MENU-CLAIMS @
    _RTHP-PK-MENU-ROWS-A @ _RTHP-PK-BANK @ _RTHP-TB.ROWS @
    _RTHP-MENU-ROWS! ;

\ Keep the exact non-menu coverage geometry in each acknowledged bank.
\ Source generations and text revisions are intentionally absent: only these
\ rectangles determine which CELL pixels the residual planner suppresses.
\ Menu replacement rows retain their separate BACK/residue authority above.
VARIABLE _RTHP-PR-RECT
VARIABLE _RTHP-PR-COLS
VARIABLE _RTHP-PR-ROWS

: _RTHP-PROJECTION-RECT?  ( rect cols rows -- flag )
    _RTHP-PR-ROWS ! _RTHP-PR-COLS ! _RTHP-PR-RECT !
    _RTHP-PR-RECT @ @ 0< IF 0 EXIT THEN
    _RTHP-PR-RECT @ 8 + @ 0< IF 0 EXIT THEN
    _RTHP-PR-RECT @ @ _RTHP-PR-RECT @ 16 + @ U< 0= IF 0 EXIT THEN
    _RTHP-PR-RECT @ 8 + @ _RTHP-PR-RECT @ 24 + @ U< 0= IF 0 EXIT THEN
    _RTHP-PR-RECT @ 16 + @ _RTHP-PR-ROWS @ U> IF 0 EXIT THEN
    _RTHP-PR-RECT @ 24 + @ _RTHP-PR-COLS @ U> 0= ;

: _RTHP-PK-PROJECTION-RECTS?  ( -- flag )
    _RTHP-PK-BANK @ _RTHP-TB.PROJECTION-RECTS @ 0 ?DO
        _RTHP-PK-P @ _RTHP.CLAIMS-A @
        I _RTHP-PK-P @ _RTHP.MENU-CLAIMS @ + RUCL-CLAIM-SIZE * +
            _RUCL-C.ROW0 DUP
        _RTHP-PK-BANK @ _RTHP-TB.COLS @
        _RTHP-PK-BANK @ _RTHP-TB.ROWS @ _RTHP-PROJECTION-RECT? 0= IF
            DROP 0 UNLOOP EXIT
        THEN
        _RTHP-PK-PROJECTION-RECTS-A @ I _RTHP-PROJECTION-RECT-SIZE * +
            _RTHP-PROJECTION-RECT-SIZE MOVE
    LOOP -1 ;

: _RTHP-PK-INSTRUMENT-OFFSET?  ( instrument -- flag )
    _RTHP-PK-INSTRUMENT !
    _RTHP-PK-INSTRUMENT @ _RTE-INSTRUMENT.UNIT-A @ _RTHP-PK-OLD-A !
    _RTHP-PK-INSTRUMENT @ _RTE-INSTRUMENT.UNIT-U @ _RTHP-PK-OLD-U !
    _RTHP-PK-OLD-U @ 0= IF _RTHP-PK-OLD-A @ 0= EXIT THEN
    _RTHP-PK-OLD-A @ _RTHP-PK-P @ _RTHP.INSTRUMENT-UNITS-A @ U< IF
        0 EXIT
    THEN
    _RTHP-PK-OLD-A @ _RTHP-PK-P @ _RTHP.INSTRUMENT-UNITS-A @ -
        _RTHP-PK-OLD-A !
    _RTHP-PK-OLD-A @
        _RTHP-PK-BANK @ _RTHP-TB.INSTRUMENT-UNIT-BYTES @ U> IF 0 EXIT THEN
    _RTHP-PK-OLD-U @
    _RTHP-PK-BANK @ _RTHP-TB.INSTRUMENT-UNIT-BYTES @
        _RTHP-PK-OLD-A @ - U> IF 0 EXIT THEN
    _RTHP-PK-OLD-A @ _RTHP-PK-INSTRUMENT @ _RTE-INSTRUMENT.UNIT-A ! -1 ;


: _RTHP-PK-STATIC-TEXT-OFFSET? ( address bytes -- offset flag )
    DUP 0= IF DROP 0= IF 0 -1 ELSE 0 0 THEN EXIT THEN
    _RTHP-PK-OLD-U ! _RTHP-PK-OLD-A !
    _RTHP-PK-OLD-A @ _RTHP-PK-P @ _RTHP.STATIC-TEXT-A @ U< IF 0 0 EXIT THEN
    _RTHP-PK-OLD-A @ _RTHP-PK-P @ _RTHP.STATIC-TEXT-A @ -
        DUP _RTHP-PK-OLD-A !
    _RTHP-PK-OLD-U @ _RTHP-U32+? 0= IF DROP 0 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.STATIC-TEXT-BYTES @ U> IF 0 0 EXIT THEN
    _RTHP-PK-OLD-A @ -1 ;

: _RTHP-PK-STATIC-OFFSETS? ( item -- flag )
    _RTHP-PK-STATIC !
    _RTHP-PK-STATIC @ _RTE-STATIC.LABEL-A @
    _RTHP-PK-STATIC @ _RTE-STATIC.LABEL-U @ _RTHP-PK-STATIC-TEXT-OFFSET?
        0= IF DROP 0 EXIT THEN _RTHP-PK-STATIC @ _RTE-STATIC.LABEL-A !
    _RTHP-PK-STATIC @ _RTE-STATIC.VALUE-A @
    _RTHP-PK-STATIC @ _RTE-STATIC.VALUE-U @ _RTHP-PK-STATIC-TEXT-OFFSET?
        0= IF DROP 0 EXIT THEN _RTHP-PK-STATIC @ _RTE-STATIC.VALUE-A ! -1 ;

\ Packed sample references are offsets; moving an ACK bank cannot leave a
\ borrowed source pointer. Empty histories retain the canonical zero pair.
: _RTHP-PK-SERIES-OFFSET? ( record -- flag )
    _RTHP-PK-SERIES !
    _RTHP-PK-SERIES @ _RTE-SERIES.SAMPLES-A @ _RTHP-PK-OLD-A !
    _RTHP-PK-SERIES @ _RTE-SERIES.SAMPLES-U @ _RTHP-PK-OLD-U !
    _RTHP-PK-OLD-U @ 0= IF _RTHP-PK-OLD-A @ 0= EXIT THEN
    _RTHP-PK-OLD-A @ _RTHP-PK-P @ _RTHP.SERIES-SAMPLES-A @ U< IF 0 EXIT THEN
    _RTHP-PK-OLD-A @ _RTHP-PK-P @ _RTHP.SERIES-SAMPLES-A @ - DUP
        _RTHP-PK-OLD-A ! 7 AND IF 0 EXIT THEN
    _RTHP-PK-OLD-A @ _RTHP-PK-OLD-U @ _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.SERIES-SAMPLE-BYTES @ U> IF 0 EXIT THEN
    _RTHP-PK-OLD-A @ _RTHP-PK-SERIES @ _RTE-SERIES.SAMPLES-A ! -1 ;

: _RTHP-PK-COPY?  ( -- flag )
    _RTHP-PK-PACK-A @ _RTHP-PK-TOTAL @ 0 FILL
    _RTHP-PK-P @ _RTHP.CONTROLS-A @ _RTHP-PK-CONTROLS-A @
        _RTHP-PK-CONTROL-U @ MOVE
    _RTHP-PK-P @ _RTHP.CORR-A @ _RTHP-PK-CORR-A @
        _RTHP-PK-CORR-U @ MOVE
    _RTHP-PK-P @ _RTHP.SOURCE-TEXT-A @ _RTHP-PK-SOURCE-A @
        _RTHP-PK-BANK @ _RTHP-TB.SOURCE-TEXT-USED @ MOVE
    _RTHP-PK-P @ _RTHP.GLYPH-ITEMS-A @ _RTHP-PK-ITEMS-A @
        _RTHP-PK-ITEM-U @ MOVE
    _RTHP-PK-P @ _RTHP.GLYPH-REFS-A @ _RTHP-PK-REFS-A @
        _RTHP-PK-REF-U @ MOVE
    _RTHP-PK-P @ _RTHP.GLYPH-TEXT-A @ _RTHP-PK-GLYPH-A @
        _RTHP-PK-BANK @ _RTHP-TB.GLYPH-TEXT-USED @ MOVE
    _RTHP-PK-P @ _RTHP.SOURCE-DIR-A @ _RTHP-PK-DIRECTORY-A @
        _RTHP-PK-DIRECTORY-U @ MOVE
    _RTHP-PK-P @ _RTHP.INSTRUMENT-REGIONS-A @
        _RTHP-PK-INSTRUMENT-REGIONS-A @ _RTHP-PK-INSTRUMENT-REGIONS-U @ MOVE
    _RTHP-PK-P @ _RTHP.INSTRUMENTS-A @ _RTHP-PK-INSTRUMENTS-A @
        _RTHP-PK-INSTRUMENTS-U @ MOVE
    _RTHP-PK-P @ _RTHP.INSTRUMENT-CORR-A @ _RTHP-PK-INSTRUMENT-CORR-A @
        _RTHP-PK-INSTRUMENT-CORR-U @ MOVE
    _RTHP-PK-P @ _RTHP.INSTRUMENT-UNITS-A @ _RTHP-PK-INSTRUMENT-UNITS-A @
        _RTHP-PK-BANK @ _RTHP-TB.INSTRUMENT-UNIT-BYTES @ MOVE
    _RTHP-PK-P @ _RTHP.STATICS-A @ _RTHP-PK-STATICS-A @ _RTHP-PK-STATICS-U @ MOVE
    _RTHP-PK-P @ _RTHP.STATIC-CORR-A @ _RTHP-PK-STATIC-CORR-A @
        _RTHP-PK-STATIC-CORR-U @ MOVE
    _RTHP-PK-P @ _RTHP.STATIC-TEXT-A @ _RTHP-PK-STATIC-TEXT-A @
        _RTHP-PK-BANK @ _RTHP-TB.STATIC-TEXT-BYTES @ MOVE
    _RTHP-PK-P @ _RTHP.SERIES-A @ _RTHP-PK-SERIES-A @ _RTHP-PK-SERIES-U @ MOVE
    _RTHP-PK-P @ _RTHP.SERIES-CORR-A @ _RTHP-PK-SERIES-CORR-A @ _RTHP-PK-SERIES-CORR-U @ MOVE
    _RTHP-PK-P @ _RTHP.SERIES-SAMPLES-A @ _RTHP-PK-SERIES-SAMPLES-A @ _RTHP-PK-SERIES-SAMPLES-U @ MOVE
    _RTHP-PK-BANK @ _RTHP-TB.SERIES-COUNT @ 0 ?DO
        _RTHP-PK-SERIES-A @ I RTE-SERIES-SIZE * +
            _RTHP-PK-SERIES-OFFSET? 0= IF 0 UNLOOP EXIT THEN
    LOOP
    _RTHP-PK-BANK @ _RTHP-TB.STATIC-COUNT @ 0 ?DO
        _RTHP-PK-STATICS-A @ I RTE-STATIC-SIZE * +
            _RTHP-PK-STATIC-OFFSETS? 0= IF 0 UNLOOP EXIT THEN
    LOOP
    _RTHP-PK-MENU-ROWS? 0= IF 0 EXIT THEN
    _RTHP-PK-PROJECTION-RECTS? 0= IF 0 EXIT THEN
    _RTHP-PK-BANK @ _RTHP-TB.CONTROL-COUNT @ 0 ?DO
        _RTHP-PK-CONTROLS-A @ I RTE-CONTROL-SIZE * +
            _RTHP-PK-CONTROL-REBASE? 0= IF
            0 UNLOOP EXIT
        THEN
    LOOP
    _RTHP-PK-BANK @ _RTHP-TB.INSTRUMENT-COUNT @ 0 ?DO
        _RTHP-PK-INSTRUMENTS-A @ I RTE-INSTRUMENT-SIZE * +
            _RTHP-PK-INSTRUMENT-OFFSET? 0= IF 0 UNLOOP EXIT THEN
    LOOP
    _RTHP-PK-TOTAL @ _RTHP-PK-BANK @ _RTHP-TB.PACKED-BYTES !
    _RTHP-TARGET-VALID-MAGIC _RTHP-PK-BANK @ _RTHP-TB.VALID !
    -1 ;

: _RTHP-PACK-CANDIDATE  ( bank producer -- packed? )
    _RTHP-PK-BEGIN? 0= IF 0 _RTHP-PK-FINISH EXIT THEN
    _RTHP-PK-P @ _RTHP.GLYPH-ITEMS-A @
        _RTHP-PK-P @ _RTHP.GLYPH-REFS-A @ _RTHP-PK-REFS?
        0= IF 0 _RTHP-PK-FINISH EXIT THEN
    _RTHP-PK-COPY? _RTHP-PK-FINISH ;

\ Hybrid preflight has already proved every item/reference/text tuple in
\ this exact owned candidate.  The caller rebinds that admission immediately
\ before target construction, so normal packing can retain all span/layout
\ checks while avoiding the same complete glyph-reference traversal again.
: _RTHP-PACK-ADMITTED-CANDIDATE  ( bank producer -- packed? )
    _RTHP-PK-BEGIN? 0= IF 0 _RTHP-PK-FINISH EXIT THEN
    _RTHP-PK-COPY? _RTHP-PK-FINISH ;

: _RTHP-PACKED-BANK?  ( bank producer -- flag )
    OVER _RTHP-TB.VALID @ _RTHP-TARGET-VALID-MAGIC <> IF
        2DROP 0 _RTHP-PK-FINISH EXIT
    THEN
    _RTHP-PK-P ! _RTHP-PK-BANK !
    _RTHP-PK-LAYOUT? 0= IF 0 _RTHP-PK-FINISH EXIT THEN
    _RTHP-PK-TOTAL @ _RTHP-PK-BANK @ _RTHP-TB.PACKED-BYTES @ =
        _RTHP-PK-FINISH ;

\ Address words for an already validated packed target bank.  They do not
\ borrow the packing scratch variables, so a physically acknowledged bank
\ can remain one immutable source while a later candidate is assembled.
: _RTHP-PACK-A  ( bank -- a )
    DUP _RTHP-TB.COUNT @ _RTHP-TARGET-ENTRY-SIZE *
    _RTHP-TARGET-BANK-HEADER-SIZE + + ;

: _RTHP-PACK-CONTROLS-A  ( bank -- a )  _RTHP-PACK-A ;

: _RTHP-PACK-CORR-A  ( bank -- a )
    DUP _RTHP-PACK-CONTROLS-A SWAP _RTHP-TB.CONTROL-COUNT @
        RTE-CONTROL-SIZE * + ;

: _RTHP-PACK-SOURCE-A  ( bank -- a )
    DUP _RTHP-PACK-CORR-A SWAP _RTHP-TB.CONTROL-COUNT @
        RUCP-CORRELATION-SIZE * + ;

: _RTHP-PACK-ITEMS-A  ( bank -- a )
    DUP _RTHP-PACK-SOURCE-A SWAP _RTHP-TB.SOURCE-TEXT-USED @
        _RTHP-ALIGN8? DROP + ;

: _RTHP-PACK-REFS-A  ( bank -- a )
    DUP _RTHP-PACK-ITEMS-A SWAP _RTHP-TB.GLYPH-SLOT-COUNT @
        RTE-GLYPH-RUN-PLAN-ITEM-SIZE * + ;

: _RTHP-PACK-GLYPH-A  ( bank -- a )
    DUP _RTHP-PACK-REFS-A SWAP _RTHP-TB.GLYPH-SLOT-COUNT @
        RGRP-TEXT-REF-SIZE * + ;

: _RTHP-PACK-DIRECTORY-A  ( bank -- a )
    DUP _RTHP-PACK-GLYPH-A SWAP _RTHP-TB.GLYPH-TEXT-USED @
        _RTHP-ALIGN8? DROP + ;

: _RTHP-PACK-MENU-ROWS-A  ( bank -- a )
    DUP _RTHP-PACK-DIRECTORY-A SWAP _RTHP-TB.DOCUMENT-COUNT @
        RUHA-DOCUMENT-SIZE * + ;

: _RTHP-PACK-INSTRUMENT-REGIONS-A  ( bank -- a )
    DUP _RTHP-PACK-MENU-ROWS-A SWAP _RTHP-TB.ROWS @ _RTHP-ALIGN8? DROP + ;

: _RTHP-PACK-INSTRUMENTS-A  ( bank -- a )
    DUP _RTHP-PACK-INSTRUMENT-REGIONS-A SWAP _RTHP-TB.INSTRUMENT-REGION-COUNT @
        RTE-INSTRUMENT-REGION-SIZE * + ;

: _RTHP-PACK-INSTRUMENT-CORR-A  ( bank -- a )
    DUP _RTHP-PACK-INSTRUMENTS-A SWAP _RTHP-TB.INSTRUMENT-COUNT @
        RTE-INSTRUMENT-SIZE * + ;

: _RTHP-PACK-INSTRUMENT-UNITS-A  ( bank -- a )
    DUP _RTHP-PACK-INSTRUMENT-CORR-A SWAP _RTHP-TB.INSTRUMENT-COUNT @
        RUIP-CORRELATION-SIZE * + ;

: _RTHP-PACK-STATICS-A ( bank -- a )
    DUP _RTHP-PACK-INSTRUMENT-UNITS-A SWAP _RTHP-TB.INSTRUMENT-UNIT-BYTES @
        _RTHP-ALIGN8? DROP + ;

: _RTHP-PACK-STATIC-CORR-A ( bank -- a )
    DUP _RTHP-PACK-STATICS-A SWAP _RTHP-TB.STATIC-COUNT @ RTE-STATIC-SIZE * + ;

: _RTHP-PACK-STATIC-TEXT-A ( bank -- a )
    DUP _RTHP-PACK-STATIC-CORR-A SWAP _RTHP-TB.STATIC-COUNT @ _RTHP-STATIC-CORR-SIZE * + ;

: _RTHP-PACK-PROJECTION-RECTS-A  ( bank -- a )
    DUP _RTHP-PACK-STATIC-TEXT-A SWAP _RTHP-TB.STATIC-TEXT-BYTES @
        _RTHP-ALIGN8? DROP + ;


: _RTHP-PACK-SERIES-A ( bank -- a )
    DUP _RTHP-PACK-PROJECTION-RECTS-A SWAP _RTHP-TB.PROJECTION-RECTS @
        _RTHP-PROJECTION-RECT-SIZE * + ;
: _RTHP-PACK-SERIES-CORR-A ( bank -- a )
    DUP _RTHP-PACK-SERIES-A SWAP _RTHP-TB.SERIES-COUNT @ RTE-SERIES-SIZE * + ;
: _RTHP-PACK-SERIES-SAMPLES-A ( bank -- a )
    DUP _RTHP-PACK-SERIES-CORR-A SWAP _RTHP-TB.SERIES-COUNT @ _RTHP-SERIES-CORR-SIZE * + ;

: _RTHP-TARGET-CANDIDATE?  ( producer -- flag )
    DUP _RTHP-TARGET-ABORT _RTHP-TG-P !
    _RTHP-TG-P @ _RTHP-TARGET-INACTIVE _RTHP-TG-BANK !
    _RTHP-TG-P @ _RTHP-TARGET-BANK-BYTES?
        0= IF DROP _RTHP-TG-FAIL EXIT THEN _RTHP-TG-BYTES !
    _RTHP-TG-BANK @ _RTHP-TG-BYTES @ _RTHP-TG-P @
        _RTHP-ARENA-SPAN? 0= IF _RTHP-TG-FAIL EXIT THEN
    0 _RTHP-TG-BANK @ _RTHP-TB.VALID !

    _RTHP-TG-P @ _RTHP.OWNER @ _RTHP-TG-BANK @ _RTHP-TB.OWNER !
    _RTHP-TG-P @ _RTHP.OWNER-GEN @
        _RTHP-TG-BANK @ _RTHP-TB.GENERATION !
    _RTHP-TG-P @ _RTHP.COLS @ _RTHP-TG-BANK @ _RTHP-TB.COLS !
    _RTHP-TG-P @ _RTHP.ROWS @ _RTHP-TG-BANK @ _RTHP-TB.ROWS !
    0 _RTHP-TG-BANK @ _RTHP-TB.COUNT !
    _RTHP-TG-P @ _RTHP.SURFACE-GEN @ _RTHP-TG-BANK @ _RTHP-TB.DRAW !
    _RTHP-TG-P @ _RTHP.SOURCE-GEN @
        _RTHP-TG-BANK @ _RTHP-TB.SOURCE-GEN !
    _RTHP-TG-P @ _RTHP.PHYSICAL-GEN @
        _RTHP-TG-BANK @ _RTHP-TB.PHYSICAL-GEN !
    _RTHP-TG-P @ _RTHP.REGION @ _RTHP-TG-BANK @ _RTHP-TB.REGION !
    _RTHP-TG-P @ _RTHP.FIRST-OBJECT @
        _RTHP-TG-BANK @ _RTHP-TB.FIRST-OBJECT !
    _RTHP-TG-P @ _RTHP.CONTROL-COUNT @
        _RTHP-TG-BANK @ _RTHP-TB.CONTROL-COUNT !
    _RTHP-TG-P @ _RTHP.GLYPH-COUNT @
        _RTHP-TG-BANK @ _RTHP-TB.GLYPH-SLOT-COUNT !
    _RTHP-TG-P @ _RTHP.SOURCE-TEXT-USED @
        _RTHP-TG-BANK @ _RTHP-TB.SOURCE-TEXT-USED !
    _RTHP-TG-P @ _RTHP.GLYPH-TEXT-USED @
        _RTHP-TG-BANK @ _RTHP-TB.GLYPH-TEXT-USED !
    0 _RTHP-TG-BANK @ _RTHP-TB.PACKED-BYTES !
    _RTHP-TG-P @ _RTHP.LIMITS RTE-LIMITS-GLYPH-RUN-BYTES@
        _RTHP-TG-BANK @ _RTHP-TB.GLYPH-RUN-LIMIT !
    _RTHP-TG-P @ _RTHP.SOURCE-CONTENT-EPOCH @
        _RTHP-TG-BANK @ _RTHP-TB.CONTENT-EPOCH !
    _RTHP-TG-P @ _RTHP.MENU-CONTROL-COUNT @
        _RTHP-TG-BANK @ _RTHP-TB.MENU-CONTROL-COUNT !
    _RTHP-TG-P @ _RTHP.COLLECTION-COUNT @
        _RTHP-TG-BANK @ _RTHP-TB.COLLECTION-COUNT !
    _RTHP-TG-P @ _RTHP.COLLECTION-ITEMS @
        _RTHP-TG-BANK @ _RTHP-TB.COLLECTION-ITEMS !
    _RTHP-TG-P @ _RTHP.COLLECTION-UTF8 @
        _RTHP-TG-BANK @ _RTHP-TB.COLLECTION-UTF8 !
    _RTHP-TG-P @ _RTHP.SOURCE-MENU-TEXT-USED @
        _RTHP-TG-BANK @ _RTHP-TB.MENU-TEXT-USED !
    _RTHP-TG-P @ _RTHP.INSTRUMENT-REGION-COUNT @
        _RTHP-TG-BANK @ _RTHP-TB.INSTRUMENT-REGION-COUNT !
    _RTHP-TG-P @ _RTHP.INSTRUMENT-COUNT @
        _RTHP-TG-BANK @ _RTHP-TB.INSTRUMENT-COUNT !
    _RTHP-TG-P @ _RTHP.INSTRUMENT-UNITS-USED @
        _RTHP-TG-BANK @ _RTHP-TB.INSTRUMENT-UNIT-BYTES !
    _RTHP-TG-P @ _RTHP.SERIES-COUNT @ _RTHP-TG-BANK @ _RTHP-TB.SERIES-COUNT !
    _RTHP-TG-P @ _RTHP.SERIES-SLOTS @ _RTHP-TG-BANK @ _RTHP-TB.SERIES-SLOTS !
    _RTHP-TG-P @ _RTHP.SERIES-CHUNKS @ _RTHP-TG-BANK @ _RTHP-TB.SERIES-CHUNKS !
    _RTHP-TG-P @ _RTHP.SERIES-HISTORY-MAX @ _RTHP-TG-BANK @ _RTHP-TB.SERIES-HISTORY-MAX !
    _RTHP-TG-P @ _RTHP.SERIES-CHUNK-MAX @ _RTHP-TG-BANK @ _RTHP-TB.SERIES-CHUNK-MAX !
    _RTHP-TG-P @ _RTHP.SERIES-CHUNK-BYTES-MAX @ _RTHP-TG-BANK @ _RTHP-TB.SERIES-CHUNK-BYTES-MAX !
    _RTHP-TG-P @ _RTHP.WAVEFORM-COUNT @ _RTHP-TG-BANK @ _RTHP-TB.WAVEFORM-COUNT !
    _RTHP-TG-P @ _RTHP.SERIES-SAMPLES-USED @ _RTHP-TG-BANK @ _RTHP-TB.SERIES-SAMPLE-BYTES !
    _RTHP-TG-P @ _RTHP.SERIES-COUNT @ IF _RTHP-TG-P @ _RTHP.FIRST-SERIES @ ELSE 0 THEN
        _RTHP-TG-BANK @ _RTHP-TB.FIRST-SERIES !
    _RTHP-TG-P @ _RTHP.FIELD-COUNT @ _RTHP-TG-BANK @ _RTHP-TB.FIELD-COUNT !
    _RTHP-TG-P @ _RTHP.FIELD-ITEMS @ _RTHP-TG-BANK @ _RTHP-TB.FIELD-ITEMS !
    _RTHP-TG-P @ _RTHP.FIELD-UTF8 @ _RTHP-TG-BANK @ _RTHP-TB.FIELD-UTF8 !
    _RTHP-TG-P @ _RTHP.DIALOG-CONTROLS @
        _RTHP-TG-BANK @ _RTHP-TB.DIALOG-CONTROLS !
    _RTHP-TG-P @ _RTHP.DIALOG-COUNT @ _RTHP-TG-BANK @ _RTHP-TB.DIALOG-COUNT !
    _RTHP-TG-P @ _RTHP.DIALOG-UTF8 @ _RTHP-TG-BANK @ _RTHP-TB.DIALOG-UTF8 !
    _RTHP-TG-P @ _RTHP.STATIC-COUNT @ _RTHP-TG-BANK @ _RTHP-TB.STATIC-COUNT !
    _RTHP-TG-P @ _RTHP.STATIC-TEXT-USED @ _RTHP-TG-BANK @ _RTHP-TB.STATIC-TEXT-BYTES !
    _RTHP-TG-P @ _RTHP.PICTURE-EPOCH @ _RTHP-TG-BANK @ _RTHP-TB.PICTURE-EPOCH !
    _RTHP-TG-P @ _RTHP.DOCUMENT-COUNT @
        _RTHP-TG-BANK @ _RTHP-TB.DOCUMENT-COUNT !

    _RTHP-TG-P @ _RTHP-CT-P !
    _RTHP-TG-P @ _RTHP.OWNER @ _RTHP-CT-OWNER !
    _RTHP-TG-P @ _RTHP.OWNER-GEN @ _RTHP-CT-GENERATION !
    _RTHP-CT-CANDIDATE-SHAPE? 0= IF _RTHP-TG-FAIL EXIT THEN
    0 _RTHP-TG-COUNT !
    0 _RTHP-CT-ORDINAL ! 0 _RTHP-CT-DOCUMENT-I !
    0 _RTHP-CT-RECORD-CURSOR ! 0 _RTHP-CT-TEXT-CURSOR !
    BEGIN _RTHP-CT-DOCUMENT-I @
        _RTHP-TG-P @ _RTHP.DOCUMENT-COUNT @ U< WHILE
        _RTHP-CT-DOCUMENT-I @ _RTHP-TG-P @ _RTHP-DOCUMENT-AT
            _RTHP-CT-DOCUMENT !
        _RTHP-CT-DOCUMENT-SHAPE? 0= IF _RTHP-TG-FAIL EXIT THEN
        0 _RTHP-CT-LOCAL !
        BEGIN _RTHP-CT-LOCAL @ _RTHP-CT-DOC-RECORD-COUNT @ U< WHILE
        _RTHP-CT-ORDINAL @ _RTHP-CT-CORRELATION-AT?
            0= IF _RTHP-TG-FAIL EXIT THEN
        _RTHP-CT-RECORD-AT? 0= IF _RTHP-TG-FAIL EXIT THEN
        _RTHP-CT-FIND-CONTROL? 0= IF _RTHP-TG-FAIL EXIT THEN
        _RTHP-CT-CONTROL? 0= IF _RTHP-TG-FAIL EXIT THEN
        _RTHP-CT-CORRELATION? 0= IF _RTHP-TG-FAIL EXIT THEN
        _RTHP-CT-RECORD? 0= IF _RTHP-TG-FAIL EXIT THEN
        _RTHP-CT-CONTROL @ _RTHP-CT-TARGET? IF
            _RTHP-CT-RECORD @ UMSN-RECORD-STATE@
                UMSN-F-PAINTABLE AND IF
                _RTHP-CT-GEOMETRY? 0= IF _RTHP-TG-FAIL EXIT THEN
                _RTHP-TG-APPEND-CURRENT? 0= IF _RTHP-TG-FAIL EXIT THEN
            THEN
        THEN
        1 _RTHP-CT-LOCAL +! 1 _RTHP-CT-ORDINAL +!
        REPEAT
        1 _RTHP-CT-DOCUMENT-I +!
    REPEAT
    _RTHP-CT-ORDINAL @ _RTHP-TG-P @ _RTHP.MENU-CONTROL-COUNT @ <>
    _RTHP-CT-RECORD-CURSOR @ _RTHP-TG-P @ _RTHP.SOURCE-USED @ <> OR
    _RTHP-CT-TEXT-CURSOR @
        _RTHP-TG-P @ _RTHP.SOURCE-MENU-TEXT-USED @ <> OR IF
        _RTHP-TG-FAIL EXIT
    THEN
    _RTHP-TG-COLLECTION-TARGETS? 0= IF _RTHP-TG-FAIL EXIT THEN
    _RTHP-TG-FIELD-TARGETS? 0= IF _RTHP-TG-FAIL EXIT THEN
    _RTHP-TG-DIALOG-TARGETS? 0= IF _RTHP-TG-FAIL EXIT THEN
    _RTHP-TG-COUNT @ _RTHP-TG-BANK @ _RTHP-TB.COUNT !
    _RTHP-TG-BANK @ _RTHP-TG-P @ _RTHP-PACK-ADMITTED-CANDIDATE
        0= IF _RTHP-TG-FAIL EXIT THEN
    _RTHP-TG-BANK @ _RTHP-TG-P @ _RTHP.TARGET-PENDING !
    _RTHP-TG-CLEAR -1 ;

VARIABLE _RTHP-TV-P
VARIABLE _RTHP-TV-BANK
VARIABLE _RTHP-TV-BYTES
VARIABLE _RTHP-TV-ID
VARIABLE _RTHP-TV-ROW
VARIABLE _RTHP-TV-COL
VARIABLE _RTHP-TV-CELLS
VARIABLE _RTHP-TV-TEXT-CAP
VARIABLE _RTHP-TV-DOCUMENTS
VARIABLE _RTHP-TV-DIRECTORY
VARIABLE _RTHP-TV-DOCUMENT
VARIABLE _RTHP-TV-DOCUMENT-I
VARIABLE _RTHP-TV-DOCUMENT-J
VARIABLE _RTHP-TV-TOKEN
VARIABLE _RTHP-TV-RECORD-CURSOR
VARIABLE _RTHP-TV-TEXT-CURSOR
VARIABLE _RTHP-TV-RECORD-U
VARIABLE _RTHP-TV-TEXT-U
VARIABLE _RTHP-TV-EPOCH
VARIABLE _RTHP-TV-TOPOLOGY-EPOCH
VARIABLE _RTHP-TV-EXPECTED-RECORD-U

: _RTHP-TV-DOCUMENT-AT  ( index -- document )
    RUHA-DOCUMENT-SIZE * _RTHP-TV-DIRECTORY @ + ;

: _RTHP-TV-DOCUMENT-GEOMETRY?  ( -- flag )
    _RTHP-TV-DOCUMENT @ RUHA-DOCUMENT-ROW@ DUP 0< IF DROP 0 EXIT THEN
    _RTHP-TV-DOCUMENT @ RUHA-DOCUMENT-HEIGHT@ DUP 0> 0= IF
        2DROP 0 EXIT
    THEN
    _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.ROWS @ U> IF 0 EXIT THEN
    _RTHP-TV-DOCUMENT @ RUHA-DOCUMENT-COL@ DUP 0< IF DROP 0 EXIT THEN
    _RTHP-TV-DOCUMENT @ RUHA-DOCUMENT-WIDTH@ DUP 0> 0= IF
        2DROP 0 EXIT
    THEN
    _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.COLS @ U> 0= ;

: _RTHP-TV-DOCUMENT-UNIQUE?  ( -- flag )
    0 _RTHP-TV-DOCUMENT-J !
    BEGIN _RTHP-TV-DOCUMENT-J @ _RTHP-TV-DOCUMENT-I @ U< WHILE
        _RTHP-TV-DOCUMENT-J @ _RTHP-TV-DOCUMENT-AT
            RUHA-DOCUMENT-TOKEN@ _RTHP-TV-TOKEN @ = IF 0 EXIT THEN
        1 _RTHP-TV-DOCUMENT-J +!
    REPEAT
    -1 ;

: _RTHP-TARGET-MENU-DIRECTORY?  ( -- flag )
    _RTHP-TV-BANK @ _RTHP-TB.DOCUMENT-COUNT @ DUP
        0> 0= IF DROP 0 EXIT THEN
    DUP _RTHP-TV-P @ _RTHP.MAX-DOCUMENTS @ U> IF DROP 0 EXIT THEN
        _RTHP-TV-DOCUMENTS !
    _RTHP-TV-BANK @ _RTHP-PACK-DIRECTORY-A DUP
        7 AND IF DROP 0 EXIT THEN _RTHP-TV-DIRECTORY !
    _RTHP-TV-BANK @ _RTHP-TB.MENU-CONTROL-COUNT @ UMSN-RECORD-SIZE
        _RTHP-U32*? 0= IF DROP 0 EXIT THEN
        _RTHP-TV-EXPECTED-RECORD-U !
    0 _RTHP-TV-RECORD-CURSOR ! 0 _RTHP-TV-TEXT-CURSOR !
    0 _RTHP-TV-DOCUMENT-I !
    BEGIN _RTHP-TV-DOCUMENT-I @ _RTHP-TV-DOCUMENTS @ U< WHILE
        _RTHP-TV-DOCUMENT-I @ _RTHP-TV-DOCUMENT-AT
            _RTHP-TV-DOCUMENT !
        _RTHP-TV-DOCUMENT @ RUHA-DOCUMENT-TOKEN@ DUP
            0= IF DROP 0 EXIT THEN _RTHP-TV-TOKEN !
        _RTHP-TV-DOCUMENT @ RUHA-DOCUMENT-SLOT-ID@ 0= IF 0 EXIT THEN
        _RTHP-TV-DOCUMENT-GEOMETRY? 0= IF 0 EXIT THEN
        _RTHP-TV-DOCUMENT-UNIQUE? 0= IF 0 EXIT THEN

        _RTHP-TV-DOCUMENT @ RUHA-DOCUMENT-RECORD-OFFSET@
            _RTHP-TV-RECORD-CURSOR @ <> IF 0 EXIT THEN
        _RTHP-TV-DOCUMENT @ RUHA-DOCUMENT-RECORD-BYTES@ DUP
            0< IF DROP 0 EXIT THEN
        DUP UMSN-RECORD-SIZE MOD IF DROP 0 EXIT THEN
            _RTHP-TV-RECORD-U !
        _RTHP-TV-RECORD-CURSOR @ _RTHP-TV-RECORD-U @ _RTHP-U32+?
            0= IF DROP 0 EXIT THEN
        DUP _RTHP-TV-EXPECTED-RECORD-U @ U> IF DROP 0 EXIT THEN
            _RTHP-TV-RECORD-CURSOR !

        _RTHP-TV-DOCUMENT @ RUHA-DOCUMENT-TEXT-OFFSET@
            _RTHP-TV-TEXT-CURSOR @ <> IF 0 EXIT THEN
        _RTHP-TV-DOCUMENT @ RUHA-DOCUMENT-TEXT-BYTES@ DUP
            0< IF DROP 0 EXIT THEN _RTHP-TV-TEXT-U !
        _RTHP-TV-RECORD-U @ 0= _RTHP-TV-TEXT-U @ 0<> AND IF
            0 EXIT
        THEN
        _RTHP-TV-TEXT-CURSOR @ _RTHP-TV-TEXT-U @ _RTHP-U32+?
            0= IF DROP 0 EXIT THEN
        DUP _RTHP-TV-BANK @ _RTHP-TB.MENU-TEXT-USED @ U> IF
            DROP 0 EXIT
        THEN _RTHP-TV-TEXT-CURSOR !

        _RTHP-TV-DOCUMENT @ RUHA-DOCUMENT-MENU-EPOCH@
            _RTHP-TV-EPOCH !
        _RTHP-TV-DOCUMENT @ RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@
            _RTHP-TV-TOPOLOGY-EPOCH !
        _RTHP-TV-RECORD-U @ 0= _RTHP-TV-EPOCH @ 0= <> IF 0 EXIT THEN
        _RTHP-TV-RECORD-U @ 0=
            _RTHP-TV-TOPOLOGY-EPOCH @ 0= <> IF 0 EXIT THEN
        _RTHP-TV-EPOCH @ _RTHP-TV-BANK @ _RTHP-TB.SOURCE-GEN @ U> IF
            0 EXIT
        THEN
        _RTHP-TV-TOPOLOGY-EPOCH @
            _RTHP-TV-BANK @ _RTHP-TB.SOURCE-GEN @ U> IF 0 EXIT THEN
        _RTHP-TV-TOPOLOGY-EPOCH @ _RTHP-TV-EPOCH @ U> IF 0 EXIT THEN
        1 _RTHP-TV-DOCUMENT-I +!
    REPEAT
    _RTHP-TV-RECORD-CURSOR @ _RTHP-TV-EXPECTED-RECORD-U @ =
    _RTHP-TV-TEXT-CURSOR @
        _RTHP-TV-BANK @ _RTHP-TB.MENU-TEXT-USED @ = AND ;

\ What a check that runs only with every-frame checks on names when one of
\ the producer's target banks fails it (check-mode.f).
: _RTHP-BANKS-DAMAGED  ( -- c-addr u )  S" the screen producer's frame banks" ;

\ _RTHP-SEAL-OF ( a u -- seal )
\   A seal of the U bytes at A: their CRC-64, from the CRC engine
\   (math/crc.f).  It finds damage that leaves a record well formed: every
\   run of damage up to 64 bits long, and other damage all but once in
\   about 2^63 times.  A seal of 0 means none was taken, so when the engine
\   cannot be had the record is left without one, as it is in the rare case
\   that its CRC is 0.  The shell's banks use it too.
: _RTHP-SEAL-OF  ( a u -- seal )
    ['] CRC64 CATCH IF 2DROP 0 THEN ;

\ _RTHP-SEAL-TAKE ( a u -- seal )
\   The seal a record takes when it is sent: with every check on
\   (check-mode.f) the seal of its U bytes at A, and in normal mode, which
\   reads no seal, 0.  Taking a seal checks nothing, so it names nothing; a
\   later check compares it.  The shell's banks take theirs here too.
: _RTHP-SEAL-TAKE  ( a u -- seal )
    CHK-EVERY-FRAME? IF _RTHP-SEAL-OF ELSE 2DROP 0 THEN ;

\ A packed bank's seal covers its header, its entries and what it packed:
\ everything a later frame or a click reads of it.
: _RTHP-BANK-SPAN  ( bank -- a u )
    DUP _RTHP-TB.COUNT @ _RTHP-TARGET-ENTRY-SIZE *
    _RTHP-TARGET-BANK-HEADER-SIZE + OVER _RTHP-TB.PACKED-BYTES @ + ;
: _RTHP-BANK-SEAL  ( bank -- seal )  _RTHP-BANK-SPAN _RTHP-SEAL-OF ;

\ _RTHP-SEAL-HOLDS? ( seal now c-addr u -- flag )
\   Whether a record still holds what it held when it took SEAL, now that
\   its seal is NOW.  A record that took no seal, or one the engine cannot
\   seal now, is not vouched for, and nothing is named.  Otherwise the two
\   must match, and when they do not, the check names the structure C-ADDR
\   U as damaged.  The shell's banks use it too.
: _RTHP-SEAL-HOLDS?  ( seal now c-addr u -- flag )
    2OVER 0= SWAP 0= OR IF 2DROP 2DROP 0 EXIT THEN
    2SWAP = -ROT CHK-NAME ;

\ With every check on (check-mode.f) the pending bank is sealed once its
\ frame is sealed for sending, and the seal passes to the acknowledged bank
\ at publication.  The bank of the frame on screen is a base for a DELTA,
\ and routes a click, only while it holds what it held when it was sealed;
\ one that does not names the producer's banks as damaged.  A bank without
\ a seal, sent before every check was on, is not damaged as far as anything
\ shows, but nothing vouches for it either: the next frame goes out whole,
\ and no click is routed through it.
: _RTHP-SEAL-PENDING  ( producer -- )
    DUP _RTHP.TARGET-PENDING @ _RTHP-BANK-SPAN _RTHP-SEAL-TAKE
    SWAP _RTHP.PENDING-SEAL ! ;
: _RTHP-ACTIVE-SEALED?  ( producer -- flag )
    CHK-EVERY-FRAME? 0= IF DROP -1 EXIT THEN
    DUP _RTHP.ACTIVE-SEAL @ DUP 0= IF NIP EXIT THEN
    SWAP _RTHP.TARGET-ACTIVE @ _RTHP-BANK-SEAL
    _RTHP-BANKS-DAMAGED _RTHP-SEAL-HOLDS? ;

\ The bank at TV-BANK holds a packed frame, and its directory names at least
\ one document and no more than the producer allows.  With every-frame checks
\ off this stands for walking the packing and the menu directory again: the
\ producer packed both itself, and the engine admitted what it built from
\ them.  In runs with the shadow check on, each comparison that reads them is
\ also held against a fresh plan.
: _RTHP-TARGET-PACKED-NAMED?  ( -- flag )
    _RTHP-TV-BANK @ _RTHP-TB.VALID @ _RTHP-TARGET-VALID-MAGIC <> IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.DOCUMENT-COUNT @ DUP 0>
    SWAP _RTHP-TV-P @ _RTHP.MAX-DOCUMENTS @ U> 0= AND ;

\ What a bank at TV-BANK holds, once where it lives has been proved.  The
\ header's fields are checked in both modes; the packing and the menu
\ directory are walked again only with every-frame checks on (check-mode.f).
: _RTHP-TARGET-BANK-BODY?  ( -- flag )
    _RTHP-TV-BANK @ _RTHP-TB.OWNER @ 0=
    _RTHP-TV-BANK @ _RTHP-TB.GENERATION @ 0= OR IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.COLS @ DUP 0> SWAP
        _RTHP-TV-P @ _RTHP.MAX-COLS @ U> 0= AND 0= IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.ROWS @ DUP 0> SWAP
        _RTHP-TV-P @ _RTHP.MAX-ROWS @ U> 0= AND 0= IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.DRAW @ 0= IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.SOURCE-GEN @ 0= IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.CONTENT-EPOCH @ 0= IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.PHYSICAL-GEN @ 0= IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.REGION @ 0= IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.FIRST-OBJECT @ 0= IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.COUNT @
        _RTHP-TV-P @ _RTHP.MAX-CONTROLS @ U> IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.CONTROL-COUNT @
        _RTHP-TV-P @ _RTHP.MAX-CONTROLS @ U> IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.MENU-CONTROL-COUNT @ DUP
        _RTHP-TV-P @ _RTHP.MAX-RECORDS @ U> IF DROP 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.CONTROL-COUNT @ U> IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.COUNT @
        _RTHP-TV-BANK @ _RTHP-TB.CONTROL-COUNT @ U> IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.COLLECTION-COUNT @ DUP
        _RTHP-TV-P @ _RTHP.MAX-COLLECTIONS @ U> IF DROP 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.MENU-CONTROL-COUNT @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.FIELD-COUNT @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.DIALOG-CONTROLS @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.CONTROL-COUNT @ <> IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TV-P @ _RTHP-TB-DIALOGS? 0= IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.FIELD-COUNT @ _RTHP-TV-P @ _RTHP.MAX-FIELDS @ U> IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.FIELD-ITEMS @ _RTHP-U32? 0= IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.FIELD-UTF8 @ _RTHP-U32? 0= IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.FIELD-COUNT @ 0= IF
        _RTHP-TV-BANK @ _RTHP-TB.FIELD-ITEMS @
        _RTHP-TV-BANK @ _RTHP-TB.FIELD-UTF8 @ OR IF 0 EXIT THEN
    THEN
    _RTHP-TV-BANK @ _RTHP-TB.COLLECTION-ITEMS @
        _RTHP-U32? 0= IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.COLLECTION-UTF8 @
        _RTHP-U32? 0= IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.COLLECTION-COUNT @ 0= IF
        _RTHP-TV-BANK @ _RTHP-TB.COLLECTION-ITEMS @
        _RTHP-TV-BANK @ _RTHP-TB.COLLECTION-UTF8 @ OR IF 0 EXIT THEN
    THEN
    _RTHP-TV-BANK @ _RTHP-TB.INSTRUMENT-REGION-COUNT @
        _RTHP-TV-P @ _RTHP.MAX-INSTRUMENT-REGIONS @ U> IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.INSTRUMENT-COUNT @
        _RTHP-TV-P @ _RTHP.MAX-INSTRUMENTS @ U> IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.INSTRUMENT-UNIT-BYTES @
        _RTHP-TV-P @ _RTHP.INSTRUMENT-UNITS-U @ U> IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.STATIC-COUNT @
        _RTHP-TV-P @ _RTHP.MAX-STATICS @ U> IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.STATIC-TEXT-BYTES @
        _RTHP-TV-P @ _RTHP.STATIC-TEXT-U @ U> IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.STATIC-COUNT @ 0= IF
        _RTHP-TV-BANK @ _RTHP-TB.STATIC-TEXT-BYTES @ IF 0 EXIT THEN
    THEN
    _RTHP-TV-BANK @ _RTHP-TB.INSTRUMENT-COUNT @ 0= IF
        _RTHP-TV-BANK @ _RTHP-TB.INSTRUMENT-REGION-COUNT @
        _RTHP-TV-BANK @ _RTHP-TB.INSTRUMENT-UNIT-BYTES @ OR IF 0 EXIT THEN
    ELSE
        _RTHP-TV-BANK @ _RTHP-TB.INSTRUMENT-REGION-COUNT @ 0= IF
            0 EXIT
        THEN
    THEN
    _RTHP-TV-BANK @ _RTHP-TB.COLS @
        _RTHP-TV-BANK @ _RTHP-TB.ROWS @ _RTHP-U32*?
        0= IF DROP 0 EXIT THEN _RTHP-TV-CELLS !
    _RTHP-TV-BANK @ _RTHP-TB.GLYPH-SLOT-COUNT @
        _RTHP-TV-CELLS @ U> IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.SOURCE-TEXT-USED @
        _RTHP-TV-P @ _RTHP.SOURCE-TEXT-U @ U> IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.MENU-TEXT-USED @ DUP
        _RTHP-TV-P @ _RTHP.MAX-TEXT @ U> IF DROP 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.SOURCE-TEXT-USED @ U> IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.COLLECTION-UTF8 @
    _RTHP-TV-BANK @ _RTHP-TB.FIELD-UTF8 @ _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.DIALOG-UTF8 @ _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.SOURCE-TEXT-USED @
    _RTHP-TV-BANK @ _RTHP-TB.MENU-TEXT-USED @ - U> IF 0 EXIT THEN
    _RTHP-TV-CELLS @ 4 _RTHP-U32*?
        0= IF DROP 0 EXIT THEN _RTHP-TV-TEXT-CAP !
    _RTHP-TV-BANK @ _RTHP-TB.GLYPH-TEXT-USED @
        _RTHP-TV-TEXT-CAP @ U> IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TB.GLYPH-RUN-LIMIT @
        _RTHP-POS-U32? 0= IF 0 EXIT THEN
    _RTHP-TARGET-PACKED-NAMED? 0= IF 0 EXIT THEN
    CHK-EVERY-FRAME? 0= IF -1 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TV-P @ _RTHP-PACKED-BANK?
        _RTHP-BANKS-DAMAGED CHK-NAME 0= IF 0 EXIT THEN
    _RTHP-TARGET-MENU-DIRECTORY? _RTHP-BANKS-DAMAGED CHK-NAME ;

\ BANK is one of the producer's two target banks, and holds a frame.  The
\ layout placed both banks in the arena when the producer was set up and
\ each time it grew; the proof that the bank lies in it is made again only
\ with every-frame checks on (check-mode.f).
: _RTHP-TARGET-BANK-HEADER?  ( bank producer -- flag )
    _RTHP-TV-P ! _RTHP-TV-BANK !
    _RTHP-TV-BANK @ DUP 0= SWAP 7 AND OR IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TV-P @ _RTHP.TARGET0-A @ =
    _RTHP-TV-BANK @ _RTHP-TV-P @ _RTHP.TARGET1-A @ = OR
        0= IF 0 EXIT THEN
    CHK-EVERY-FRAME? IF
        _RTHP-TV-P @ _RTHP-TARGET-BANK-BYTES? _RTHP-BANKS-DAMAGED CHK-NAME
            0= IF DROP 0 EXIT THEN _RTHP-TV-BYTES !
        _RTHP-TV-BANK @ _RTHP-TV-BYTES @ _RTHP-TV-P @ _RTHP-ARENA-SPAN?
            _RTHP-BANKS-DAMAGED CHK-NAME 0= IF 0 EXIT THEN
    THEN
    _RTHP-TARGET-BANK-BODY? ;

\ ( address bytes base total -- flag ) the span lies inside [base, base+total).
: _RTHP-SPAN-IN?  ( address bytes base total -- flag )
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 2DROP 0 EXIT THEN
    >R >R
    2DUP MSPAN-NONWRAPPING? 0= IF R> R> 2DROP 2DROP 0 EXIT THEN
    OVER R@ U< IF R> R> 2DROP 2DROP 0 EXIT THEN
    + R> R> + U> 0= ;

\ Input routes to the frame on screen.  After the producer grew, that
\ frame's bank stays in the kept arena, at the size it had there, until the
\ frame that replaces it is shown.  No other use treats the kept bank as a
\ baseline: the replacing frame is a complete START.
: _RTHP-ACTIVE-BANK-HEADER?  ( bank producer -- flag )
    2DUP _RTHP.KEPT-BANK-A @ =
    OVER _RTHP.KEPT-ARENA-A @ 0<> AND 0= IF
        _RTHP-TARGET-BANK-HEADER? EXIT
    THEN
    _RTHP-TV-P ! _RTHP-TV-BANK !
    _RTHP-TV-BANK @ 7 AND IF 0 EXIT THEN
    _RTHP-TV-BANK @ _RTHP-TV-P @ _RTHP.KEPT-BANK-U @
    _RTHP-TV-P @ _RTHP.KEPT-ARENA-A @ _RTHP-TV-P @ _RTHP.KEPT-ARENA-U @
        _RTHP-SPAN-IN? 0= IF 0 EXIT THEN
    _RTHP-TARGET-BANK-BODY? ;

\ The arena kept from before the producer grew holds only the bank of the
\ frame on screen.  Once that frame is replaced or retired, it goes back.
: _RTHP-KEPT-ARENA-RELEASE  ( producer -- )
    >R
    R@ _RTHP.KEPT-ARENA-A @ 0= IF R> DROP EXIT THEN
    R@ _RTHP.TARGET-ACTIVE @ R@ _RTHP.KEPT-BANK-A @ = IF R> DROP EXIT THEN
    R@ _RTHP.KEPT-ARENA-A @ R@ _RTHP.KEPT-ARENA-U @ R@ _RTHP.MEMORY @ MSRC-FREE
    0 R@ _RTHP.KEPT-ARENA-A ! 0 R@ _RTHP.KEPT-ARENA-U !
    0 R@ _RTHP.KEPT-BANK-A ! 0 R> _RTHP.KEPT-BANK-U ! ;

: _RTHP-TARGET-BANK-ENTRIES?  ( -- flag )
    _RTHP-TV-BANK @ _RTHP-TB.COUNT @ 0 ?DO
        I _RTHP-TV-BANK @ _RTHP-TARGET-ENTRY
        DUP _RTHP-TE.ID @ DUP _RTHP-TV-ID !
        0= IF DROP 0 UNLOOP EXIT THEN
        DUP _RTHP-TE.ROW @ DUP _RTHP-TV-ROW ! 0< IF
            DROP 0 UNLOOP EXIT
        THEN
        _RTHP-TV-ROW @ _RTHP-TV-BANK @ _RTHP-TB.ROWS @ U< 0= IF
            DROP 0 UNLOOP EXIT
        THEN
        DUP _RTHP-TE.COL @ DUP _RTHP-TV-COL ! 0< IF
            DROP 0 UNLOOP EXIT
        THEN
        _RTHP-TV-COL @ _RTHP-TV-BANK @ _RTHP-TB.COLS @ U< 0= IF
            DROP 0 UNLOOP EXIT
        THEN
        DUP _RTHP-TE.REVISION @ 0= IF DROP 0 UNLOOP EXIT THEN
        DUP _RTHP-TE.INTENTS @ DUP 0= IF 2DROP 0 UNLOOP EXIT THEN
        OVER _RTHP-TE.KIND @ _RTHP-KIND-INTENTS INVERT AND IF
            DROP 0 UNLOOP EXIT
        THEN
        _RTHP-TE.KIND @ _RTHP-TARGET-KIND? 0= IF 0 UNLOOP EXIT THEN
    LOOP
    -1 ;

VARIABLE _RTHP-TP-P
VARIABLE _RTHP-TP-BANK
VARIABLE _RTHP-TP-NEXT-OBJECT
VARIABLE _RTHP-TP-NEXT-SERIES

\ The comparison that built a pending bank keeps its facts beside it.  Only
\ that exact bank's publication hands them to the active role; any other
\ publication leaves none.  No producer word writes a bank while it is active.
: _RTHP-FACTS-PUBLISH  ( -- )
    _RTHP-TP-P @ _RTHP.PENDING-FACTS _RTHP-KF.BANK @
        _RTHP-TP-BANK @ = IF
        _RTHP-TP-P @ _RTHP.PENDING-FACTS
        _RTHP-TP-P @ _RTHP.ACTIVE-FACTS _RTHP-KF-SIZE MOVE
    ELSE
        0 _RTHP-TP-P @ _RTHP.ACTIVE-FACTS _RTHP-KF.BANK !
    THEN
    0 _RTHP-TP-P @ _RTHP.PENDING-FACTS _RTHP-KF.BANK ! ;

\ A retained DELTA may publish new controls or glyphs above the prior object
\ frontier while preserving acknowledged control, instrument, and glyph IDs.
\ Derive the next safe frontier from the exact bank only at physical publish;
\ sealing, cancellation, and stale fallback must not consume candidate IDs.
: _RTHP-TARGET-NEXT-OBJECT?  ( -- flag )
    _RTHP-TP-P @ _RTHP.NEXT-OBJECT @ DUP 0= IF DROP 0 EXIT THEN
        _RTHP-TP-NEXT-OBJECT !
    _RTHP-TP-BANK @ _RTHP-TB.CONTROL-COUNT @ 0 ?DO
        _RTHP-TP-BANK @ _RTHP-PACK-CONTROLS-A
        I RTE-CONTROL-SIZE * + _RTE-CONTROL.ID @
            DUP 0= IF DROP 0 UNLOOP EXIT THEN
        1 _RTHP-U+? 0= IF DROP 0 UNLOOP EXIT THEN
        DUP _RTHP-TP-NEXT-OBJECT @ U> IF
            _RTHP-TP-NEXT-OBJECT !
        ELSE
            DROP
        THEN
    LOOP
    _RTHP-TP-BANK @ _RTHP-TB.GLYPH-SLOT-COUNT @ 0 ?DO
        _RTHP-TP-BANK @ _RTHP-PACK-ITEMS-A
        I RTE-GLYPH-RUN-PLAN-ITEM-SIZE * + _RTE-LPI.OBJECT @
            DUP 0= IF DROP 0 UNLOOP EXIT THEN
        1 _RTHP-U+? 0= IF DROP 0 UNLOOP EXIT THEN
        DUP _RTHP-TP-NEXT-OBJECT @ U> IF
            _RTHP-TP-NEXT-OBJECT !
        ELSE
            DROP
        THEN
    LOOP
    _RTHP-TP-BANK @ _RTHP-TB.FIELD-COUNT @
        _RTHP-TP-P @ _RTHP.FIELD-COUNT @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.FIELD-ITEMS @
        _RTHP-TP-P @ _RTHP.FIELD-ITEMS @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.FIELD-UTF8 @
        _RTHP-TP-P @ _RTHP.FIELD-UTF8 @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.DIALOG-CONTROLS @
        _RTHP-TP-P @ _RTHP.DIALOG-CONTROLS @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.DIALOG-COUNT @
        _RTHP-TP-P @ _RTHP.DIALOG-COUNT @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.DIALOG-UTF8 @
        _RTHP-TP-P @ _RTHP.DIALOG-UTF8 @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.STATIC-COUNT @ 0 ?DO
        _RTHP-TP-BANK @ _RTHP-PACK-STATICS-A I RTE-STATIC-SIZE * + _RTE-STATIC.ID @
            DUP 0= IF DROP 0 UNLOOP EXIT THEN
        1 _RTHP-U+? 0= IF DROP 0 UNLOOP EXIT THEN
        DUP _RTHP-TP-NEXT-OBJECT @ U> IF _RTHP-TP-NEXT-OBJECT ! ELSE DROP THEN
    LOOP
    _RTHP-TP-BANK @ _RTHP-TB.INSTRUMENT-COUNT @ 0 ?DO
        _RTHP-TP-BANK @ _RTHP-PACK-INSTRUMENTS-A
        I RTE-INSTRUMENT-SIZE * + _RTE-INSTRUMENT.ID @
            DUP 0= IF DROP 0 UNLOOP EXIT THEN
        1 _RTHP-U+? 0= IF DROP 0 UNLOOP EXIT THEN
        DUP _RTHP-TP-NEXT-OBJECT @ U> IF
            _RTHP-TP-NEXT-OBJECT !
        ELSE
            DROP
        THEN
    LOOP
    _RTHP-TP-P @ _RTHP.NEXT-SERIES @ DUP 0= IF DROP 0 EXIT THEN
        _RTHP-TP-NEXT-SERIES !
    _RTHP-TP-BANK @ _RTHP-TB.SERIES-COUNT @ IF
        _RTHP-TP-BANK @ _RTHP-TB.FIRST-SERIES @
        _RTHP-TP-BANK @ _RTHP-TB.SERIES-COUNT @ _RTHP-U+? 0= IF DROP 0 EXIT THEN
        DUP _RTHP-TP-NEXT-SERIES @ U> IF _RTHP-TP-NEXT-SERIES ! ELSE DROP THEN
    THEN
    -1 ;

: _RTHP-TARGET-PUBLISH?  ( producer -- flag )
    _RTHP-TP-P !
    _RTHP-TP-P @ _RTHP.PHASE @ _RTHP-PH-LIVE <> IF 0 EXIT THEN
    _RTHP-TP-P @ _RTHP.TARGET-PENDING @ DUP 0= IF DROP 0 EXIT THEN
        _RTHP-TP-BANK !
    _RTHP-TP-BANK @ _RTHP-TP-P @ _RTHP-TARGET-BANK-HEADER?
        0= IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TP-P @ _RTHP.TARGET-ACTIVE @ = IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.OWNER @
        _RTHP-TP-P @ _RTHP.OWNER @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.GENERATION @
        _RTHP-TP-P @ _RTHP.OWNER-GEN @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.COLS @
        _RTHP-TP-P @ _RTHP.COLS @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.ROWS @
        _RTHP-TP-P @ _RTHP.ROWS @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.DRAW @
        _RTHP-TP-P @ _RTHP.SURFACE-GEN @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.SOURCE-GEN @
        _RTHP-TP-P @ _RTHP.SOURCE-GEN @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.CONTENT-EPOCH @
        _RTHP-TP-P @ _RTHP.SOURCE-CONTENT-EPOCH @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.PHYSICAL-GEN @
        _RTHP-TP-P @ _RTHP.PHYSICAL-GEN @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.REGION @
        _RTHP-TP-P @ _RTHP.REGION @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.FIRST-OBJECT @
        _RTHP-TP-P @ _RTHP.FIRST-OBJECT @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.CONTROL-COUNT @
        _RTHP-TP-P @ _RTHP.CONTROL-COUNT @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.MENU-CONTROL-COUNT @
        _RTHP-TP-P @ _RTHP.MENU-CONTROL-COUNT @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.DOCUMENT-COUNT @
        _RTHP-TP-P @ _RTHP.DOCUMENT-COUNT @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.COLLECTION-COUNT @
        _RTHP-TP-P @ _RTHP.COLLECTION-COUNT @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.COLLECTION-ITEMS @
        _RTHP-TP-P @ _RTHP.COLLECTION-ITEMS @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.COLLECTION-UTF8 @
        _RTHP-TP-P @ _RTHP.COLLECTION-UTF8 @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.MENU-TEXT-USED @
        _RTHP-TP-P @ _RTHP.SOURCE-MENU-TEXT-USED @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.INSTRUMENT-REGION-COUNT @
        _RTHP-TP-P @ _RTHP.INSTRUMENT-REGION-COUNT @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.INSTRUMENT-COUNT @
        _RTHP-TP-P @ _RTHP.INSTRUMENT-COUNT @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.INSTRUMENT-UNIT-BYTES @
        _RTHP-TP-P @ _RTHP.INSTRUMENT-UNITS-USED @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.STATIC-COUNT @
        _RTHP-TP-P @ _RTHP.STATIC-COUNT @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.STATIC-TEXT-BYTES @
        _RTHP-TP-P @ _RTHP.STATIC-TEXT-USED @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.GLYPH-SLOT-COUNT @
        _RTHP-TP-P @ _RTHP.GLYPH-COUNT @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.SOURCE-TEXT-USED @
        _RTHP-TP-P @ _RTHP.SOURCE-TEXT-USED @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.GLYPH-TEXT-USED @
        _RTHP-TP-P @ _RTHP.GLYPH-TEXT-USED @ <> IF 0 EXIT THEN
    _RTHP-TP-BANK @ _RTHP-TB.GLYPH-RUN-LIMIT @
        _RTHP-TP-P @ _RTHP.LIMITS RTE-LIMITS-GLYPH-RUN-BYTES@
        <> IF 0 EXIT THEN
    _RTHP-TARGET-BANK-ENTRIES? 0= IF 0 EXIT THEN
    _RTHP-TARGET-NEXT-OBJECT? 0= IF 0 EXIT THEN
    RTHPX-PUBLISH-CHECK _RTHP-TP-P @ _RTHP-EXTENSION-CHECK 0= IF 0 EXIT THEN
    _RTHP-TP-NEXT-OBJECT @ _RTHP-TP-P @ _RTHP.NEXT-OBJECT !
    _RTHP-TP-NEXT-SERIES @ _RTHP-TP-P @ _RTHP.NEXT-SERIES !
    0 _RTHP-TP-P @ _RTHP.TARGET-PENDING !
    _RTHP-TP-BANK @ _RTHP-TB.DRAW @
        _RTHP-TP-P @ _RTHP.ACTIVE-DRAW !
    _RTHP-TP-BANK @ _RTHP-TP-P @ _RTHP.TARGET-ACTIVE !
    _RTHP-TP-P @ _RTHP.PENDING-SEAL @ _RTHP-TP-P @ _RTHP.ACTIVE-SEAL !
    0 _RTHP-TP-P @ _RTHP.PENDING-SEAL !
    _RTHP-TP-P @ _RTHP-KEPT-ARENA-RELEASE
    _RTHP-FACTS-PUBLISH
    RTHPX-PUBLISH _RTHP-TP-P @ _RTHP-EXTENSION-NOTIFY
    _RTHP-TP-P @ _RTHP-DELTA-PLAN-CLEAR
    0 _RTHP-TP-P ! 0 _RTHP-TP-BANK ! -1 ;

\ _RTHP-TARGET-RETIRE ( producer -- )
\   The terminal acknowledged the empty frame that replaced the rich one: no
\   control is left to route input to, and no bank is a baseline to compare
\   a later frame with.
: _RTHP-TARGET-RETIRE  ( producer -- )
    DUP RTHPX-RETIRE SWAP _RTHP-EXTENSION-NOTIFY
    DUP _RTHP-TARGET-ABORT
    DUP _RTHP.TARGET-ACTIVE @ ?DUP IF 0 SWAP _RTHP-TB.VALID ! THEN
    0 OVER _RTHP.TARGET-ACTIVE !
    0 OVER _RTHP.ACTIVE-SEAL !
    0 OVER _RTHP.ACTIVE-DRAW !
    DUP _RTHP-KEPT-ARENA-RELEASE
    0 SWAP _RTHP.ACTIVE-FACTS _RTHP-KF.BANK ! ;

VARIABLE _RTHP-TL-P
VARIABLE _RTHP-TL-BANK
VARIABLE _RTHP-TL-OWNER
VARIABLE _RTHP-TL-GENERATION
VARIABLE _RTHP-TL-ID
VARIABLE _RTHP-TL-MATCHES
VARIABLE _RTHP-TL-ROW
VARIABLE _RTHP-TL-COL
VARIABLE _RTHP-TL-KIND
VARIABLE _RTHP-TL-REVISION
VARIABLE _RTHP-TL-INTENTS
VARIABLE _RTHP-TL-INTENT

: _RTHP-TL-CLEAR  ( -- )
    0 _RTHP-TL-P ! 0 _RTHP-TL-BANK ! 0 _RTHP-TL-OWNER !
    0 _RTHP-TL-GENERATION ! 0 _RTHP-TL-ID !
    0 _RTHP-TL-MATCHES ! 0 _RTHP-TL-ROW ! 0 _RTHP-TL-COL !
    0 _RTHP-TL-KIND ! 0 _RTHP-TL-INTENT !
    0 _RTHP-TL-REVISION ! 0 _RTHP-TL-INTENTS ! ;

: _RTHP-TL-FAIL  ( -- row col revision false )
    _RTHP-TL-CLEAR 0 0 0 0 ;

: _RTHP-TARGET-BANK-FIND?  ( -- flag )
    0 _RTHP-TL-MATCHES !
    _RTHP-TL-BANK @ _RTHP-TB.COUNT @ 0 ?DO
        I _RTHP-TL-BANK @ _RTHP-TARGET-ENTRY
        DUP _RTHP-TE.ID @ DUP _RTHP-TV-ID !
        0= IF DROP 0 UNLOOP EXIT THEN
        DUP _RTHP-TE.ROW @ DUP _RTHP-TV-ROW ! 0< IF
            DROP 0 UNLOOP EXIT
        THEN
        _RTHP-TV-ROW @ _RTHP-TL-BANK @ _RTHP-TB.ROWS @ U< 0= IF
            DROP 0 UNLOOP EXIT
        THEN
        DUP _RTHP-TE.COL @ DUP _RTHP-TV-COL ! 0< IF
            DROP 0 UNLOOP EXIT
        THEN
        _RTHP-TV-COL @ _RTHP-TL-BANK @ _RTHP-TB.COLS @ U< 0= IF
            DROP 0 UNLOOP EXIT
        THEN
        _RTHP-TV-ID @ _RTHP-TL-ID @ = IF
            _RTHP-TV-ROW @ _RTHP-TL-ROW !
            _RTHP-TV-COL @ _RTHP-TL-COL !
            DUP _RTHP-TE.KIND @ _RTHP-TL-KIND !
            DUP _RTHP-TE.REVISION @ _RTHP-TL-REVISION !
            DUP _RTHP-TE.INTENTS @ _RTHP-TL-INTENTS !
            1 _RTHP-TL-MATCHES +!
        THEN
        DROP
    LOOP
    _RTHP-TL-MATCHES @ 1 = ;

\ RTHP-CONTROL-TARGET@
\   ( owner generation control-id intent producer -- row col revision found? )
\   Resolve one reported intent against the exact acknowledged target.  The
\   control must be a unique target of a kind that accepts the RTE-INTENT-*
\   value.  The cell lies inside the ordinary widget that drew it, and
\   revision is the target's exact semantic content revision. A collection's
\   revision is the aggregate epoch of the frame that last changed its body;
\   FIELD retains its independently authored revision.
: RTHP-CONTROL-TARGET@
  ( owner generation control-id intent producer -- row col revision found? )
    _RTHP-TL-P ! _RTHP-TL-INTENT ! _RTHP-TL-ID !
    _RTHP-TL-GENERATION ! _RTHP-TL-OWNER !
    _RTHP-TL-P @ RTHP-VALID? 0= IF _RTHP-TL-FAIL EXIT THEN
    _RTHP-TL-P @ _RTHP.TARGET-ACTIVE @ DUP 0= IF
        DROP _RTHP-TL-FAIL EXIT
    THEN _RTHP-TL-BANK !
    _RTHP-TL-BANK @ _RTHP-TL-P @ _RTHP-ACTIVE-BANK-HEADER?
        0= IF _RTHP-TL-FAIL EXIT THEN
    _RTHP-TL-P @ _RTHP-ACTIVE-SEALED? 0= IF _RTHP-TL-FAIL EXIT THEN
    _RTHP-TL-OWNER @ _RTHP-TL-BANK @ _RTHP-TB.OWNER @ <>
    _RTHP-TL-GENERATION @
        _RTHP-TL-BANK @ _RTHP-TB.GENERATION @ <> OR
    _RTHP-TL-BANK @ _RTHP-TB.OWNER @
        _RTHP-TL-P @ _RTHP.OWNER @ <> OR
    _RTHP-TL-BANK @ _RTHP-TB.GENERATION @
        _RTHP-TL-P @ _RTHP.OWNER-GEN @ <> OR
    _RTHP-TL-BANK @ _RTHP-TB.DRAW @
        _RTHP-TL-P @ _RTHP.ACTIVE-DRAW @ <> OR
    _RTHP-TL-ID @ 0= OR IF _RTHP-TL-FAIL EXIT THEN
    _RTHP-TARGET-BANK-FIND? 0= IF _RTHP-TL-FAIL EXIT THEN
    _RTHP-TL-INTENT @ _RTHP-TL-KIND @ _RTHP-INTENT-SUITS?
        0= IF _RTHP-TL-FAIL EXIT THEN
    _RTHP-TL-REVISION @ 0= IF _RTHP-TL-FAIL EXIT THEN
    1 _RTHP-TL-INTENT @ LSHIFT _RTHP-TL-INTENTS @ AND 0= IF
        _RTHP-TL-FAIL EXIT
    THEN
    _RTHP-TL-ROW @ _RTHP-TL-COL @ _RTHP-TL-REVISION @ -1
    _RTHP-TL-CLEAR ;

\ Every capacity follows from the selected byte and surface bounds in the
\ _RTHP-I- cells: at construction, and again whenever the arena grows.
: _RTHP-I-CAPACITIES!  ( producer -- )
    >R
    _RTHP-I-DOCUMENTS @ R@ _RTHP.MAX-DOCUMENTS !
    _RTHP-I-RECORDS @ R@ _RTHP.MAX-RECORDS !
    _RTHP-I-TEXT @ R@ _RTHP.MAX-TEXT !
    _RTHP-I-COLLECTION-NATIVE @ R@ _RTHP.MAX-COLLECTION-NATIVE !
    _RTHP-I-COLLECTION-NATIVE @ RTHP-COLLECTION-CONTROL-CAPACITY
        R@ _RTHP.MAX-COLLECTIONS !
    _RTHP-I-COLLECTION-NATIVE @ USCOL-ENTRY-HEADER-SIZE /
        R@ _RTHP.MAX-COLLECTION-DESCRIPTORS !
    _RTHP-I-DGRAPH-NATIVE @ R@ _RTHP.MAX-DGRAPH-NATIVE !
    _RTHP-I-DGRAPH-NATIVE @ UDG-HEADER-SIZE /
        _RTHP-I-RECORDS @ _RTHP-UMIN
        R@ _RTHP.MAX-DGRAPH-DESCRIPTORS !
    _RTHP-I-DGRAPH-NATIVE @ UDG-SERIES-HEADER-SIZE / R@ _RTHP.MAX-SERIES !
    _RTHP-I-DGRAPH-NATIVE @ UDG-STATUS-RECORD-SIZE /
        DUP R@ _RTHP.MAX-INSTRUMENTS !
        R@ _RTHP.MAX-DGRAPH-DESCRIPTORS @ _RTHP-UMIN
        R@ _RTHP.MAX-INSTRUMENT-REGIONS !
    _RTHP-I-PICTURES @ R@ _RTHP.MAX-PICTURES !
    _RTHP-I-STATUS-NATIVE @ DUP R@ _RTHP.MAX-STATUS-NATIVE !
        USF-HEADER-SIZE / _RTHP-I-PICTURES @ + R@ _RTHP.MAX-STATICS !
    _RTHP-I-FIELD-NATIVE @ DUP R@ _RTHP.MAX-FIELD-NATIVE !
        UFLD-HEADER-SIZE / R@ _RTHP.MAX-FIELDS !
    _RTHP-I-DIALOG-NATIVE @ DUP R@ _RTHP.MAX-DIALOG-NATIVE !
        DUP UDLG-HEADER-SIZE / R@ _RTHP.MAX-DIALOGS !
        UDLG-BUTTON-HEADER-SIZE / R@ _RTHP.MAX-DIALOG-CONTROLS !
    _RTHP-I-RECORDS @ R@ _RTHP.MAX-COLLECTIONS @ +
        R@ _RTHP.MAX-FIELDS @ + R@ _RTHP.MAX-DIALOG-CONTROLS @ +
        R@ _RTHP.MAX-CONTROLS !
    _RTHP-I-COLS @ R@ _RTHP.MAX-COLS !
    _RTHP-I-ROWS @ R> _RTHP.MAX-ROWS ! ;

: RTHP-INIT
\ adapter facade arena-a arena-u max-documents max-records max-source-text max-collection-native
\ max-data-graphics-native max-status-native max-field-native max-dialog-native max-pictures
\ max-cols max-rows owner owner-generation region first-object first-series producer -- scb-status
    _RTHP-I-P ! _RTHP-I-FIRST-SERIES ! _RTHP-I-FIRST ! _RTHP-I-REGION ! _RTHP-I-GEN !
    _RTHP-I-OWNER ! _RTHP-I-ROWS ! _RTHP-I-COLS ! _RTHP-I-PICTURES !
    _RTHP-I-DIALOG-NATIVE ! _RTHP-I-FIELD-NATIVE ! _RTHP-I-STATUS-NATIVE ! _RTHP-I-DGRAPH-NATIVE !
    _RTHP-I-COLLECTION-NATIVE ! _RTHP-I-TEXT !
    _RTHP-I-RECORDS ! _RTHP-I-DOCUMENTS !
    _RTHP-I-ARENA-U ! _RTHP-I-ARENA !
    _RTHP-I-FACADE ! _RTHP-I-ADAPTER !
    _RTHP-I-ADAPTER @ RUHA-VALID? 0= IF SCB-S-INVALID EXIT THEN
    _RTHP-I-FACADE @ RTE-VALID? 0= IF SCB-S-INVALID EXIT THEN
    _RTHP-I-DOCUMENTS @ _RTHP-POS-U32? 0= IF SCB-S-INVALID EXIT THEN
    _RTHP-I-ADAPTER @ RUHA-DOCUMENT-CAPACITY@
        _RTHP-I-DOCUMENTS @ <> IF SCB-S-INVALID EXIT THEN
    _RTHP-I-OWNER @ 0= _RTHP-I-GEN @ 0= OR
    _RTHP-I-REGION @ 0= OR _RTHP-I-FIRST @ 0= OR
    _RTHP-I-FIRST-SERIES @ 0= OR IF
        SCB-S-INVALID EXIT
    THEN
    _RTHP-I-DOCUMENTS @ _RTHP-I-RECORDS @ _RTHP-I-TEXT @
        _RTHP-I-COLLECTION-NATIVE @
        _RTHP-I-DGRAPH-NATIVE @ _RTHP-I-STATUS-NATIVE @ _RTHP-I-FIELD-NATIVE @
        _RTHP-I-DIALOG-NATIVE @
        _RTHP-I-PICTURES @ _RTHP-I-COLS @ _RTHP-I-ROWS @
        RTHP-STORAGE-BYTES DUP 0= IF DROP SCB-S-INVALID EXIT THEN
        _RTHP-I-REQUIRED !
    _RTHP-I-P @ 7 AND _RTHP-I-ARENA @ 7 AND OR IF
        SCB-S-INVALID EXIT
    THEN
    _RTHP-I-P @ RTHP-SIZE MSPAN-NONWRAPPING? 0= IF
        SCB-S-INVALID EXIT
    THEN
    _RTHP-I-ARENA @ _RTHP-I-ARENA-U @ MSPAN-NONWRAPPING? 0= IF
        SCB-S-INVALID EXIT
    THEN
    _RTHP-I-ARENA-U @ _RTHP-I-REQUIRED @ U< IF SCB-S-INVALID EXIT THEN
    _RTHP-I-P @ RTHP-SIZE _RTHP-I-ARENA @ _RTHP-I-REQUIRED @
        MSPAN-OVERLAP? IF SCB-S-INVALID EXIT THEN
    _RTHP-I-P @ RTHP-SIZE _RTHP-I-FACADE @
        RTE-STORAGE-DISJOINT? 0= IF SCB-S-INVALID EXIT THEN
    _RTHP-I-ARENA @ _RTHP-I-REQUIRED @ _RTHP-I-FACADE @
        RTE-STORAGE-DISJOINT? 0= IF SCB-S-INVALID EXIT THEN
    _RTHP-I-P @ RTHP-SIZE
        _RTHP-I-ADAPTER @ RUHA-SIZE MSPAN-OVERLAP? IF
        SCB-S-INVALID EXIT
    THEN
    _RTHP-I-ARENA @ _RTHP-I-REQUIRED @
        _RTHP-I-ADAPTER @ RUHA-SIZE MSPAN-OVERLAP? IF
        SCB-S-INVALID EXIT
    THEN
    _RTHP-I-P @ RTHP-SIZE 0 FILL
    RTHP-SIZE _RTHP-I-P @ _RTHP.SIZE !
    _RTHP-I-P @ DUP _RTHP.SELF !
    _RTHP-I-ADAPTER @ _RTHP-I-P @ _RTHP.ADAPTER !
    _RTHP-I-FACADE @ _RTHP-I-P @ _RTHP.FACADE !
    _RTHP-I-ARENA @ _RTHP-I-P @ _RTHP.ARENA-A !
    _RTHP-I-REQUIRED @ _RTHP-I-P @ _RTHP.ARENA-U !
    _RTHP-I-P @ _RTHP-I-CAPACITIES!
    _RTHP-I-OWNER @ _RTHP-I-P @ _RTHP.OWNER !
    _RTHP-I-GEN @ _RTHP-I-P @ _RTHP.OWNER-GEN !
    _RTHP-I-REGION @ _RTHP-I-P @ _RTHP.REGION !
    _RTHP-I-FIRST @ _RTHP-I-P @ _RTHP.FIRST-OBJECT !
    _RTHP-I-REGION @ _RTHP-I-P @ _RTHP.NEXT-REGION !
    _RTHP-I-FIRST @ _RTHP-I-P @ _RTHP.NEXT-OBJECT !
    _RTHP-I-FIRST-SERIES @ DUP _RTHP-I-P @ _RTHP.FIRST-SERIES !
        _RTHP-I-P @ _RTHP.NEXT-SERIES !
    0 _RTHP-I-P @ _RTHP.SOURCE-DRAW !
    0 _RTHP-I-P @ _RTHP.SOURCE-DIR-USED !
    0 _RTHP-I-P @ _RTHP.DOCUMENT-COUNT !
    0 _RTHP-I-P @ _RTHP.DGRAPH-DESCRIPTORS-USED !
    0 _RTHP-I-P @ _RTHP.DGRAPH-NATIVE-USED !
    0 _RTHP-I-P @ _RTHP.SOURCE-DGRAPH-COUNT !
    0 _RTHP-I-P @ _RTHP.INSTRUMENT-REGION-COUNT !
    0 _RTHP-I-P @ _RTHP.INSTRUMENT-COUNT !
    0 _RTHP-I-P @ _RTHP.INSTRUMENT-UNITS-USED !
    0 _RTHP-I-P @ _RTHP.INSTRUMENT-CLAIM-COUNT !
    0 _RTHP-I-P @ _RTHP.ACTIVE-DRAW !
    1 _RTHP-I-P @ _RTHP.NEXT-RESOURCE !
    _RTHP-PH-WAIT _RTHP-I-P @ _RTHP.PHASE !
    SCB-S-OK _RTHP-I-P @ _RTHP.FAULT !
    _RTHP-I-P @ _RTHP-LAYOUT
    _RTHP-I-P @ _RTHP.TARGET0-A @
        _RTHP-TARGET-BANK-HEADER-SIZE 0 FILL
    _RTHP-I-P @ _RTHP.TARGET1-A @
        _RTHP-TARGET-BANK-HEADER-SIZE 0 FILL
    _RTHP-MAGIC _RTHP-I-P @ _RTHP.MAGIC !
    _RTHP-I-P @ RTHP-VALID? IF SCB-S-OK ELSE SCB-S-INVALID THEN ;

\ RTHP-FIRST-CAPACITIES
\   ( -- records text collection-native data-graphics-native status-native
\        field-native dialog-native pictures cols rows )
\   The smallest capacities RTHP-INIT accepts.  A producer that grows from
\   a memory source starts here and takes what its first draw needs.
: RTHP-FIRST-CAPACITIES
  ( -- records text collection-native data-graphics-native status-native field-native dialog-native pictures cols rows )
    1 8
    USCOL-TABSET-FIXED-SIZE 7 + -8 AND USCOL-ENTRY-HEADER-SIZE _RTHP-UMAX
    UDG-HEADER-SIZE 7 + -8 AND 0 0 0 0 1 1 ;

\ RTHP-MEMORY! ( memory producer -- scb-status )
\   From now on the producer owns its arena, which the caller took from
\   MEMORY with exactly the bytes RTHP-STORAGE-BYTES gave for the capacities
\   it was initialized with, and grows into MEMORY as draws need.  Attach
\   it before the first draw.
: RTHP-MEMORY!  ( memory producer -- scb-status )
    DUP RTHP-VALID? 0= IF 2DROP SCB-S-INVALID EXIT THEN
    OVER MSRC-VALID? 0= IF 2DROP SCB-S-INVALID EXIT THEN
    DUP _RTHP.MEMORY @ IF 2DROP SCB-S-INVALID EXIT THEN
    DUP _RTHP.PHASE @ _RTHP-PH-WAIT <>
    OVER _RTHP.TARGET-ACTIVE @ 0<> OR
    OVER _RTHP.TARGET-PENDING @ 0<> OR IF 2DROP SCB-S-INVALID EXIT THEN
    _RTHP.MEMORY ! SCB-S-OK ;

\ RTHP-FINI ( producer -- )
\   Give back the arenas the producer owns and clear it.  Call it once the
\   terminal holds nothing of this producer's and nothing will step it.
\   Every picture claim goes, so CELL shows each picture.
: RTHP-FINI  ( producer -- )
    UPICSN-RELEASE-ALL
    DUP _RTHP.MAGIC @ _RTHP-MAGIC = OVER _RTHP.SELF @ 2 PICK = AND
    OVER _RTHP.MEMORY @ 0<> AND IF
        \ The newer arena was taken last, so it goes back first.
        DUP _RTHP.ARENA-A @ OVER _RTHP.ARENA-U @ 2 PICK _RTHP.MEMORY @ MSRC-FREE
        DUP _RTHP.KEPT-ARENA-A @ ?DUP IF
            OVER _RTHP.KEPT-ARENA-U @ 2 PICK _RTHP.MEMORY @ MSRC-FREE
        THEN
        DUP _RTHP.CHUNK-A @ ?DUP IF
            OVER _RTHP.CHUNK-U @ 2 PICK _RTHP.MEMORY @ MSRC-FREE
        THEN
        DUP _RTHP.RESOURCES-A @ ?DUP IF
            OVER _RTHP.RESOURCES-U @ 2 PICK _RTHP.MEMORY @ MSRC-FREE
        THEN
    THEN
    RTHP-SIZE 0 FILL ;


\ =====================================================================
\  One immutable combined candidate
\ =====================================================================

VARIABLE _RTHP-W-P
VARIABLE _RTHP-W-SNAP
VARIABLE _RTHP-W-STATUS
VARIABLE _RTHP-W-COUNT
VARIABLE _RTHP-W-TEXT
VARIABLE _RTHP-W-ALIGNED
VARIABLE _RTHP-W-MAX
VARIABLE _RTHP-W-LAST
VARIABLE _RTHP-W-GLYPH-FIRST
VARIABLE _RTHP-W-CLAIMS
VARIABLE _RTHP-W-DRAW
\ With Desk's shell installed, a build leaves the residual runs and the
\ admission to the shell's batch, which plans the runs of its own regions
\ and admits everything it sends.  ALONE asks for the candidate's own runs
\ and admission all the same: before the owner opens, since the owner is
\ sized from that admission, and when the shell cannot build its batch, so
\ the candidate is cut down to fit or goes out on its own.
VARIABLE _RTHP-W-ALONE
0 _RTHP-W-ALONE !
: _RTHP-W-SHELL-MODE?  ( -- flag )
    _RTHP-W-P @ _RTHP.EXTENSION @ 0<> _RTHP-W-ALONE @ 0= AND ;
VARIABLE _RTHP-W-DIRECTORY-A
VARIABLE _RTHP-W-DIRECTORY-U
VARIABLE _RTHP-W-RECORDS-A
VARIABLE _RTHP-W-RECORDS-U
VARIABLE _RTHP-W-TEXT-A
VARIABLE _RTHP-W-TEXT-U
VARIABLE _RTHP-W-DESCRIPTORS-A
VARIABLE _RTHP-W-DESCRIPTORS-U
VARIABLE _RTHP-W-NATIVE-A
VARIABLE _RTHP-W-NATIVE-U
VARIABLE _RTHP-W-DGRAPH-DESCRIPTORS-A
VARIABLE _RTHP-W-DGRAPH-DESCRIPTORS-U
VARIABLE _RTHP-W-DGRAPH-NATIVE-A
VARIABLE _RTHP-W-DGRAPH-NATIVE-U
VARIABLE _RTHP-W-SOURCE-COLLECTIONS
VARIABLE _RTHP-W-SOURCE-DGRAPHS
VARIABLE _RTHP-W-COPY-COLLECTIONS
VARIABLE _RTHP-W-DOCUMENTS
VARIABLE _RTHP-W-DOCUMENT-I
VARIABLE _RTHP-W-DOCUMENT
VARIABLE _RTHP-W-RECORD-CURSOR
VARIABLE _RTHP-W-TEXT-CURSOR
VARIABLE _RTHP-W-DESCRIPTOR-CURSOR
VARIABLE _RTHP-W-NATIVE-CURSOR
VARIABLE _RTHP-W-DGRAPH-DESCRIPTOR-CURSOR
VARIABLE _RTHP-W-DGRAPH-NATIVE-CURSOR
VARIABLE _RTHP-W-DOC-RECORD-O
VARIABLE _RTHP-W-DOC-RECORD-U
VARIABLE _RTHP-W-DOC-RECORD-COUNT
VARIABLE _RTHP-W-DOC-TEXT-O
VARIABLE _RTHP-W-DOC-TEXT-U
VARIABLE _RTHP-W-DOC-DESCRIPTOR-O
VARIABLE _RTHP-W-DOC-DESCRIPTOR-U
VARIABLE _RTHP-W-DOC-COLLECTION-COUNT
VARIABLE _RTHP-W-DOC-NATIVE-O
VARIABLE _RTHP-W-DOC-NATIVE-U
VARIABLE _RTHP-W-DOC-DGRAPH-DESCRIPTOR-O
VARIABLE _RTHP-W-DOC-DGRAPH-DESCRIPTOR-U
VARIABLE _RTHP-W-DOC-DGRAPH-COUNT
VARIABLE _RTHP-W-DOC-DGRAPH-NATIVE-O
VARIABLE _RTHP-W-DOC-DGRAPH-NATIVE-U
VARIABLE _RTHP-W-SOURCE-GEN
VARIABLE _RTHP-W-END
VARIABLE _RTHP-W-CONTENT-EPOCH
VARIABLE _RTHP-W-TOTAL
VARIABLE _RTHP-W-NEXT-ID
VARIABLE _RTHP-W-OUT-CONTROLS-A
VARIABLE _RTHP-W-OUT-CONTROLS-U
VARIABLE _RTHP-W-OUT-CORR-A
VARIABLE _RTHP-W-OUT-CORR-U
VARIABLE _RTHP-W-OUT-CLAIMS-A
VARIABLE _RTHP-W-OUT-CLAIMS-U
VARIABLE _RTHP-W-RUCP-HIGH-WATER
VARIABLE _RTHP-W-RUCP-LOOKUP-U
VARIABLE _RTHP-W-RUCP-ORDER-U
VARIABLE _RTHP-W-RUCP-CONTROL-U
VARIABLE _RTHP-W-RUCP-CORR-U

: _RTHP-W-DOCUMENT-GEOMETRY?  ( -- flag )
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-ROW@ DUP 0< IF DROP 0 EXIT THEN
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-HEIGHT@ DUP 0> 0= IF
        2DROP 0 EXIT
    THEN
    _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.ROWS @ U> IF 0 EXIT THEN
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-COL@ DUP 0< IF DROP 0 EXIT THEN
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-WIDTH@ DUP 0> 0= IF
        2DROP 0 EXIT
    THEN
    _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.COLS @ U> 0= ;

: _RTHP-W-DOCUMENT-SHAPE?  ( -- flag )
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-TOKEN@ 0= IF 0 EXIT THEN
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-SLOT-ID@ 0= IF 0 EXIT THEN
    _RTHP-W-DOCUMENT-GEOMETRY? 0= IF 0 EXIT THEN

    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-RECORD-OFFSET@
        DUP _RTHP-W-DOC-RECORD-O !
        _RTHP-W-RECORD-CURSOR @ <> IF 0 EXIT THEN
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-RECORD-BYTES@
        DUP _RTHP-W-DOC-RECORD-U !
    DUP 0< IF DROP 0 EXIT THEN
    DUP UMSN-RECORD-SIZE MOD IF DROP 0 EXIT THEN
    UMSN-RECORD-SIZE / _RTHP-W-DOC-RECORD-COUNT !
    _RTHP-W-RECORD-CURSOR @ _RTHP-W-DOC-RECORD-U @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-W-RECORDS-U @ U> IF DROP 0 EXIT THEN
    _RTHP-W-RECORD-CURSOR !

    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-TEXT-OFFSET@
        DUP _RTHP-W-DOC-TEXT-O !
        _RTHP-W-TEXT-CURSOR @ <> IF 0 EXIT THEN
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-TEXT-BYTES@
        DUP _RTHP-W-DOC-TEXT-U !
    DUP 0< IF DROP 0 EXIT THEN
    _RTHP-W-DOC-RECORD-U @ 0= OVER 0<> AND IF DROP 0 EXIT THEN
    _RTHP-W-TEXT-CURSOR @ SWAP _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    DUP _RTHP-W-TEXT-U @ U> IF DROP 0 EXIT THEN
        _RTHP-W-TEXT-CURSOR !
    _RTHP-W-DOC-RECORD-U @ 0=
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-MENU-EPOCH@ 0= <> IF 0 EXIT THEN
    _RTHP-W-DOC-RECORD-U @ 0=
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@ 0= <>
        IF 0 EXIT THEN
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-MENU-EPOCH@
        _RTHP-W-SOURCE-GEN @ U> IF 0 EXIT THEN
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@
        _RTHP-W-SOURCE-GEN @ U> IF 0 EXIT THEN
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-MENU-EPOCH@ U> IF 0 EXIT THEN

    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-COLLECTION-DESCRIPTOR-OFFSET@
        DUP _RTHP-W-DOC-DESCRIPTOR-O !
        _RTHP-W-DESCRIPTOR-CURSOR @ <> IF 0 EXIT THEN
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-COLLECTION-DESCRIPTOR-BYTES@
        DUP _RTHP-W-DOC-DESCRIPTOR-U !
    DUP 0< IF DROP 0 EXIT THEN
    DUP UCSN-DESCRIPTOR-SIZE MOD IF DROP 0 EXIT THEN
    UCSN-DESCRIPTOR-SIZE / _RTHP-W-DOC-COLLECTION-COUNT !
    _RTHP-W-DESCRIPTOR-CURSOR @ _RTHP-W-DOC-DESCRIPTOR-U @
        _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    DUP _RTHP-W-DESCRIPTORS-U @ U> IF DROP 0 EXIT THEN
        _RTHP-W-DESCRIPTOR-CURSOR !

    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-COLLECTION-NATIVE-OFFSET@
        DUP _RTHP-W-DOC-NATIVE-O !
        _RTHP-W-NATIVE-CURSOR @ <> IF 0 EXIT THEN
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-COLLECTION-NATIVE-BYTES@
        DUP _RTHP-W-DOC-NATIVE-U !
    DUP 0< IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    _RTHP-W-DOC-COLLECTION-COUNT @ 0= OVER 0= <> IF DROP 0 EXIT THEN
    _RTHP-W-NATIVE-CURSOR @ SWAP _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    DUP _RTHP-W-NATIVE-U @ U> IF DROP 0 EXIT THEN
        _RTHP-W-NATIVE-CURSOR !

    _RTHP-W-DOCUMENT @
        RUHA-DOCUMENT-DATA-GRAPHICS-DESCRIPTOR-OFFSET@
        DUP _RTHP-W-DOC-DGRAPH-DESCRIPTOR-O !
        _RTHP-W-DGRAPH-DESCRIPTOR-CURSOR @ <> IF 0 EXIT THEN
    _RTHP-W-DOCUMENT @
        RUHA-DOCUMENT-DATA-GRAPHICS-DESCRIPTOR-BYTES@
        DUP _RTHP-W-DOC-DGRAPH-DESCRIPTOR-U !
    DUP 0< IF DROP 0 EXIT THEN
    DUP UDGSN-DESCRIPTOR-SIZE MOD IF DROP 0 EXIT THEN
    UDGSN-DESCRIPTOR-SIZE / _RTHP-W-DOC-DGRAPH-COUNT !
    _RTHP-W-DGRAPH-DESCRIPTOR-CURSOR @
        _RTHP-W-DOC-DGRAPH-DESCRIPTOR-U @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-W-DGRAPH-DESCRIPTORS-U @ U> IF DROP 0 EXIT THEN
        _RTHP-W-DGRAPH-DESCRIPTOR-CURSOR !

    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-DATA-GRAPHICS-NATIVE-OFFSET@
        DUP _RTHP-W-DOC-DGRAPH-NATIVE-O !
        _RTHP-W-DGRAPH-NATIVE-CURSOR @ <> IF 0 EXIT THEN
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-DATA-GRAPHICS-NATIVE-BYTES@
        DUP _RTHP-W-DOC-DGRAPH-NATIVE-U !
    DUP 0< IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    _RTHP-W-DOC-DGRAPH-COUNT @ 0= OVER 0= <> IF DROP 0 EXIT THEN
    _RTHP-W-DGRAPH-NATIVE-CURSOR @ SWAP _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-W-DGRAPH-NATIVE-U @ U> IF DROP 0 EXIT THEN
        _RTHP-W-DGRAPH-NATIVE-CURSOR !
    -1 ;

: _RTHP-W-SNAPSHOT-SPANS?  ( -- flag )
    _RTHP-W-SNAP @ RUHA-SNAPSHOT-DOCUMENT-COUNT@
        DUP _RTHP-W-DOCUMENTS !
    DUP 0> 0= IF DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.MAX-DOCUMENTS @ U> IF 0 EXIT THEN

    _RTHP-W-SNAP @ RUHA-SNAPSHOT-DIRECTORY@
        _RTHP-W-DIRECTORY-U ! _RTHP-W-DIRECTORY-A !
    _RTHP-W-DOCUMENTS @ RUHA-DOCUMENT-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN
    _RTHP-W-DIRECTORY-U @ <> IF 0 EXIT THEN
    _RTHP-W-DIRECTORY-A @ DUP 0= SWAP 7 AND OR IF 0 EXIT THEN
    _RTHP-W-DIRECTORY-A @ _RTHP-W-DIRECTORY-U @
        MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    _RTHP-W-DIRECTORY-U @ _RTHP-W-P @ _RTHP.SOURCE-DIR-U @ U> IF
        0 EXIT
    THEN
    _RTHP-W-DIRECTORY-A @ _RTHP-W-DIRECTORY-U @
    _RTHP-W-P @ _RTHP.ARENA-A @ _RTHP-W-P @ _RTHP.ARENA-U @
        MSPAN-OVERLAP? IF 0 EXIT THEN

    _RTHP-W-SNAP @ RUHA-SNAPSHOT-RECORDS@
        _RTHP-W-RECORDS-U ! _RTHP-W-RECORDS-A !
    _RTHP-W-RECORDS-A @ DUP 0= SWAP 7 AND OR IF 0 EXIT THEN
    _RTHP-W-RECORDS-U @ DUP 0< IF DROP 0 EXIT THEN
    DUP UMSN-RECORD-SIZE MOD IF DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.SOURCE-RECS-U @ U> IF 0 EXIT THEN
    _RTHP-W-RECORDS-A @ _RTHP-W-RECORDS-U @
        MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    _RTHP-W-RECORDS-A @ _RTHP-W-RECORDS-U @
    _RTHP-W-P @ _RTHP.ARENA-A @ _RTHP-W-P @ _RTHP.ARENA-U @
        MSPAN-OVERLAP? IF 0 EXIT THEN

    _RTHP-W-SNAP @ RUHA-SNAPSHOT-TEXT@
        _RTHP-W-TEXT-U ! _RTHP-W-TEXT-A !
    _RTHP-W-TEXT-A @ 0= IF 0 EXIT THEN
    _RTHP-W-TEXT-U @ DUP 0< IF DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.MAX-TEXT @ U> IF 0 EXIT THEN
    _RTHP-W-TEXT-A @ _RTHP-W-TEXT-U @
        MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    _RTHP-W-TEXT-A @ _RTHP-W-TEXT-U @
    _RTHP-W-P @ _RTHP.ARENA-A @ _RTHP-W-P @ _RTHP.ARENA-U @
        MSPAN-OVERLAP? IF 0 EXIT THEN

    _RTHP-W-SNAP @ RUHA-SNAPSHOT-COLLECTION-DESCRIPTORS@
        _RTHP-W-DESCRIPTORS-U ! _RTHP-W-DESCRIPTORS-A !
    _RTHP-W-DESCRIPTORS-U @ DUP 0< IF DROP 0 EXIT THEN
    DUP UCSN-DESCRIPTOR-SIZE MOD IF DROP 0 EXIT THEN
    UCSN-DESCRIPTOR-SIZE / DUP _RTHP-W-SOURCE-COLLECTIONS !
    _RTHP-W-SNAP @ RUHA-SNAPSHOT-COLLECTION-COUNT@ <> IF 0 EXIT THEN
    _RTHP-W-DESCRIPTORS-U @ IF
        _RTHP-W-DESCRIPTORS-A @ DUP 0= SWAP 7 AND OR IF 0 EXIT THEN
        _RTHP-W-DESCRIPTORS-A @ _RTHP-W-DESCRIPTORS-U @
            MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
        _RTHP-W-DESCRIPTORS-A @ _RTHP-W-DESCRIPTORS-U @
        _RTHP-W-P @ _RTHP.ARENA-A @ _RTHP-W-P @ _RTHP.ARENA-U @
            MSPAN-OVERLAP? IF 0 EXIT THEN
    THEN

    _RTHP-W-SNAP @ RUHA-SNAPSHOT-COLLECTION-NATIVE@
        _RTHP-W-NATIVE-U ! _RTHP-W-NATIVE-A !
    _RTHP-W-NATIVE-U @ DUP 0< IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    _RTHP-W-SOURCE-COLLECTIONS @ 0= OVER 0= <> IF DROP 0 EXIT THEN
    IF
        _RTHP-W-NATIVE-A @ DUP 0= SWAP 7 AND OR IF 0 EXIT THEN
        _RTHP-W-NATIVE-A @ _RTHP-W-NATIVE-U @
            MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
        _RTHP-W-NATIVE-A @ _RTHP-W-NATIVE-U @
        _RTHP-W-P @ _RTHP.ARENA-A @ _RTHP-W-P @ _RTHP.ARENA-U @
            MSPAN-OVERLAP? IF 0 EXIT THEN
        _RTHP-W-DESCRIPTORS-A @ _RTHP-W-DESCRIPTORS-U @
        _RTHP-W-NATIVE-A @ _RTHP-W-NATIVE-U @
            MSPAN-OVERLAP? IF 0 EXIT THEN
    THEN
    _RTHP-W-DESCRIPTORS-U @
        _RTHP-W-P @ _RTHP.COLLECTION-DESCRIPTORS-U @ U> 0=
    _RTHP-W-NATIVE-U @
        _RTHP-W-P @ _RTHP.COLLECTION-NATIVE-U @ U> 0= AND
        _RTHP-W-COPY-COLLECTIONS !

    _RTHP-W-SNAP @ RUHA-SNAPSHOT-DATA-GRAPHICS-DESCRIPTORS@
        _RTHP-W-DGRAPH-DESCRIPTORS-U !
        _RTHP-W-DGRAPH-DESCRIPTORS-A !
    _RTHP-W-DGRAPH-DESCRIPTORS-U @ DUP 0< IF DROP 0 EXIT THEN
    DUP UDGSN-DESCRIPTOR-SIZE MOD IF DROP 0 EXIT THEN
    UDGSN-DESCRIPTOR-SIZE / DUP _RTHP-W-SOURCE-DGRAPHS !
    _RTHP-W-SNAP @ RUHA-SNAPSHOT-DATA-GRAPHICS-COUNT@ <> IF 0 EXIT THEN
    _RTHP-W-SOURCE-DGRAPHS @
        _RTHP-W-P @ _RTHP.MAX-DGRAPH-DESCRIPTORS @ U> IF 0 EXIT THEN
    _RTHP-W-DGRAPH-DESCRIPTORS-U @
        _RTHP-W-P @ _RTHP.DGRAPH-DESCRIPTORS-U @ U> IF 0 EXIT THEN
    _RTHP-W-DGRAPH-DESCRIPTORS-U @ IF
        _RTHP-W-DGRAPH-DESCRIPTORS-A @ DUP 0= SWAP 7 AND OR IF
            0 EXIT
        THEN
        _RTHP-W-DGRAPH-DESCRIPTORS-A @
            _RTHP-W-DGRAPH-DESCRIPTORS-U @
            MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
        _RTHP-W-DGRAPH-DESCRIPTORS-A @
            _RTHP-W-DGRAPH-DESCRIPTORS-U @
        _RTHP-W-P @ _RTHP.ARENA-A @ _RTHP-W-P @ _RTHP.ARENA-U @
            MSPAN-OVERLAP? IF 0 EXIT THEN
    THEN

    _RTHP-W-SNAP @ RUHA-SNAPSHOT-DATA-GRAPHICS-NATIVE@
        _RTHP-W-DGRAPH-NATIVE-U ! _RTHP-W-DGRAPH-NATIVE-A !
    _RTHP-W-DGRAPH-NATIVE-U @ DUP 0< IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    _RTHP-W-SOURCE-DGRAPHS @ 0= OVER 0= <> IF DROP 0 EXIT THEN
    DUP _RTHP-W-P @ _RTHP.DGRAPH-NATIVE-U @ U> IF DROP 0 EXIT THEN
    IF
        _RTHP-W-DGRAPH-NATIVE-A @ DUP 0= SWAP 7 AND OR IF 0 EXIT THEN
        _RTHP-W-DGRAPH-NATIVE-A @ _RTHP-W-DGRAPH-NATIVE-U @
            MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
        _RTHP-W-DGRAPH-NATIVE-A @ _RTHP-W-DGRAPH-NATIVE-U @
        _RTHP-W-P @ _RTHP.ARENA-A @ _RTHP-W-P @ _RTHP.ARENA-U @
            MSPAN-OVERLAP? IF 0 EXIT THEN
        _RTHP-W-DGRAPH-DESCRIPTORS-A @
            _RTHP-W-DGRAPH-DESCRIPTORS-U @
        _RTHP-W-DGRAPH-NATIVE-A @ _RTHP-W-DGRAPH-NATIVE-U @
            MSPAN-OVERLAP? IF 0 EXIT THEN
    THEN

    0 _RTHP-W-RECORD-CURSOR ! 0 _RTHP-W-TEXT-CURSOR !
    0 _RTHP-W-DESCRIPTOR-CURSOR ! 0 _RTHP-W-NATIVE-CURSOR !
    0 _RTHP-W-DGRAPH-DESCRIPTOR-CURSOR !
    0 _RTHP-W-DGRAPH-NATIVE-CURSOR !
    0 _RTHP-W-DOCUMENT-I !
    BEGIN _RTHP-W-DOCUMENT-I @ _RTHP-W-DOCUMENTS @ U< WHILE
        _RTHP-W-DIRECTORY-A @ _RTHP-W-DOCUMENT-I @ RUHA-DOCUMENT-SIZE * +
            _RTHP-W-DOCUMENT !
        _RTHP-W-DOCUMENT-SHAPE? 0= IF 0 EXIT THEN
        1 _RTHP-W-DOCUMENT-I +!
    REPEAT
    _RTHP-W-RECORD-CURSOR @ _RTHP-W-RECORDS-U @ =
    _RTHP-W-TEXT-CURSOR @ _RTHP-W-TEXT-U @ = AND
    _RTHP-W-DESCRIPTOR-CURSOR @ _RTHP-W-DESCRIPTORS-U @ = AND
    _RTHP-W-NATIVE-CURSOR @ _RTHP-W-NATIVE-U @ = AND
    _RTHP-W-DGRAPH-DESCRIPTOR-CURSOR @
        _RTHP-W-DGRAPH-DESCRIPTORS-U @ = AND
    _RTHP-W-DGRAPH-NATIVE-CURSOR @
        _RTHP-W-DGRAPH-NATIVE-U @ = AND ;

: _RTHP-W-STRIP-COLLECTION-DIRECTORY  ( -- )
    _RTHP-W-DOCUMENTS @ 0 ?DO
        I _RTHP-W-P @ _RTHP-DOCUMENT-AT
        0 OVER _RUHA-D.COLLECTION-DESCRIPTOR-OFF !
        0 OVER _RUHA-D.COLLECTION-DESCRIPTOR-U !
        0 OVER _RUHA-D.COLLECTION-NATIVE-OFF !
        0 SWAP _RUHA-D.COLLECTION-NATIVE-U !
    LOOP ;


\ The optional status lane is copied independently of menu, collection and
\ instrument storage.  RUHA has already deeply validated the frozen source;
\ these checks bind its exact per-document slices before any copy or omission.
VARIABLE _RTHP-SI-DA
VARIABLE _RTHP-SI-DU
VARIABLE _RTHP-SI-NA
VARIABLE _RTHP-SI-NU
VARIABLE _RTHP-SI-DC
VARIABLE _RTHP-SI-NC
VARIABLE _RTHP-SI-DOC
VARIABLE _RTHP-SI-COPY

: _RTHP-SI-SPAN? ( a u -- flag )
    DUP 0= IF 2DROP -1 EXIT THEN
    DUP 0< OVER 7 AND OR IF 2DROP 0 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.ARENA-A @ _RTHP-W-P @ _RTHP.ARENA-U @
        MSPAN-OVERLAP? 0= ;

: _RTHP-SI-DIRECTORY? ( -- flag )
    0 _RTHP-SI-DC ! 0 _RTHP-SI-NC !
    _RTHP-W-DOCUMENTS @ 0 ?DO
        _RTHP-W-DIRECTORY-A @ I RUHA-DOCUMENT-SIZE * + _RTHP-SI-DOC !
        _RTHP-SI-DOC @ RUHA-DOCUMENT-STATUS-FIELDS-DESCRIPTOR-OFFSET@
            _RTHP-SI-DC @ <> IF 0 UNLOOP EXIT THEN
        _RTHP-SI-DOC @ RUHA-DOCUMENT-STATUS-FIELDS-DESCRIPTOR-BYTES@
            DUP USFSN-DESCRIPTOR-SIZE MOD IF DROP 0 UNLOOP EXIT THEN
        _RTHP-SI-DC @ SWAP _RTHP-U32+?
            0= IF DROP 0 UNLOOP EXIT THEN
        DUP _RTHP-SI-DU @ U> IF DROP 0 UNLOOP EXIT THEN _RTHP-SI-DC !
        _RTHP-SI-DOC @ RUHA-DOCUMENT-STATUS-FIELDS-NATIVE-OFFSET@
            _RTHP-SI-NC @ <> IF 0 UNLOOP EXIT THEN
        _RTHP-SI-DOC @ RUHA-DOCUMENT-STATUS-FIELDS-NATIVE-BYTES@
            DUP 7 AND IF DROP 0 UNLOOP EXIT THEN
        DUP 0= _RTHP-SI-DOC @
            RUHA-DOCUMENT-STATUS-FIELDS-DESCRIPTOR-BYTES@ 0= <>
            IF DROP 0 UNLOOP EXIT THEN
        _RTHP-SI-NC @ SWAP _RTHP-U32+?
            0= IF DROP 0 UNLOOP EXIT THEN
        DUP _RTHP-SI-NU @ U> IF DROP 0 UNLOOP EXIT THEN _RTHP-SI-NC !
    LOOP
    _RTHP-SI-DC @ _RTHP-SI-DU @ =
    _RTHP-SI-NC @ _RTHP-SI-NU @ = AND ;

: _RTHP-SI-STRIP-DIRECTORY ( -- )
    _RTHP-W-DOCUMENTS @ 0 ?DO
        I _RTHP-W-P @ _RTHP-DOCUMENT-AT
        0 OVER 160 + ! 0 OVER 168 + ! 0 OVER 176 + ! 0 SWAP 184 + !
    LOOP ;

: _RTHP-COPY-STATUS-SOURCE? ( -- flag )
    0 _RTHP-W-P @ _RTHP.STATUS-DESCRIPTORS-USED !
    0 _RTHP-W-P @ _RTHP.STATUS-NATIVE-USED !
    _RTHP-W-SNAP @ RUHA-SNAPSHOT-STATUS-FIELDS-DESCRIPTORS@
        _RTHP-SI-DU ! _RTHP-SI-DA !
    _RTHP-W-SNAP @ RUHA-SNAPSHOT-STATUS-FIELDS-NATIVE@
        _RTHP-SI-NU ! _RTHP-SI-NA !
    _RTHP-SI-DA @ _RTHP-SI-DU @ _RTHP-SI-SPAN? 0= IF 0 EXIT THEN
    _RTHP-SI-NA @ _RTHP-SI-NU @ _RTHP-SI-SPAN? 0= IF 0 EXIT THEN
    _RTHP-SI-DU @ USFSN-DESCRIPTOR-SIZE MOD IF 0 EXIT THEN
    _RTHP-SI-DU @ USFSN-DESCRIPTOR-SIZE /
        _RTHP-W-SNAP @ RUHA-SNAPSHOT-STATUS-FIELDS-COUNT@ <> IF 0 EXIT THEN
    _RTHP-SI-DA @ _RTHP-SI-DU @ _RTHP-SI-NA @ _RTHP-SI-NU @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTHP-SI-DIRECTORY? 0= IF 0 EXIT THEN
    _RTHP-SI-DU @ _RTHP-W-P @ _RTHP.STATUS-DESCRIPTORS-U @ U> 0=
    _RTHP-SI-NU @ _RTHP-W-P @ _RTHP.STATUS-NATIVE-U @ U> 0= AND
    _RTHP-W-P @ _RTHP.LIMITS RTE-LIMITS-FEATURES@
        RTE-F-STATUS-FIELDS AND 0<> AND _RTHP-SI-COPY !
    _RTHP-SI-COPY @ 0= IF _RTHP-SI-STRIP-DIRECTORY -1 EXIT THEN
    _RTHP-SI-DA @ _RTHP-W-P @ _RTHP.STATUS-DESCRIPTORS-A @
        _RTHP-SI-DU @ MOVE
    _RTHP-SI-NA @ _RTHP-W-P @ _RTHP.STATUS-NATIVE-A @
        _RTHP-SI-NU @ MOVE
    _RTHP-SI-DU @ _RTHP-W-P @ _RTHP.STATUS-DESCRIPTORS-USED !
    _RTHP-SI-NU @ _RTHP-W-P @ _RTHP.STATUS-NATIVE-USED ! -1 ;

VARIABLE _RTHP-FI-DA
VARIABLE _RTHP-FI-DU
VARIABLE _RTHP-FI-NA
VARIABLE _RTHP-FI-NU
VARIABLE _RTHP-FI-DC
VARIABLE _RTHP-FI-NC
VARIABLE _RTHP-FI-DOC
VARIABLE _RTHP-FI-COPY

: _RTHP-FI-SPAN? ( a u -- flag )
    DUP 0= IF 2DROP -1 EXIT THEN
    DUP 0< OVER 7 AND OR IF 2DROP 0 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.ARENA-A @ _RTHP-W-P @ _RTHP.ARENA-U @
        MSPAN-OVERLAP? 0= ;

: _RTHP-FI-DIRECTORY? ( -- flag )
    0 _RTHP-FI-DC ! 0 _RTHP-FI-NC !
    _RTHP-W-DOCUMENTS @ 0 ?DO
        _RTHP-W-DIRECTORY-A @ I RUHA-DOCUMENT-SIZE * + _RTHP-FI-DOC !
        _RTHP-FI-DOC @ RUHA-DOCUMENT-FIELDS-DESCRIPTOR-OFFSET@
            _RTHP-FI-DC @ <> IF 0 UNLOOP EXIT THEN
        _RTHP-FI-DOC @ RUHA-DOCUMENT-FIELDS-DESCRIPTOR-BYTES@
            DUP UFLSN-DESCRIPTOR-SIZE MOD IF DROP 0 UNLOOP EXIT THEN
        _RTHP-FI-DC @ SWAP _RTHP-U32+?
            0= IF DROP 0 UNLOOP EXIT THEN
        DUP _RTHP-FI-DU @ U> IF DROP 0 UNLOOP EXIT THEN _RTHP-FI-DC !
        _RTHP-FI-DOC @ RUHA-DOCUMENT-FIELDS-NATIVE-OFFSET@
            _RTHP-FI-NC @ <> IF 0 UNLOOP EXIT THEN
        _RTHP-FI-DOC @ RUHA-DOCUMENT-FIELDS-NATIVE-BYTES@
            DUP 7 AND IF DROP 0 UNLOOP EXIT THEN
        DUP 0= _RTHP-FI-DOC @
            RUHA-DOCUMENT-FIELDS-DESCRIPTOR-BYTES@ 0= <>
            IF DROP 0 UNLOOP EXIT THEN
        _RTHP-FI-NC @ SWAP _RTHP-U32+?
            0= IF DROP 0 UNLOOP EXIT THEN
        DUP _RTHP-FI-NU @ U> IF DROP 0 UNLOOP EXIT THEN _RTHP-FI-NC !
    LOOP
    _RTHP-FI-DC @ _RTHP-FI-DU @ =
    _RTHP-FI-NC @ _RTHP-FI-NU @ = AND ;

: _RTHP-FI-STRIP-DIRECTORY ( -- )
    _RTHP-W-DOCUMENTS @ 0 ?DO
        I _RTHP-W-P @ _RTHP-DOCUMENT-AT
        0 OVER 192 + ! 0 OVER 200 + ! 0 OVER 208 + ! 0 SWAP 216 + !
    LOOP ;

: _RTHP-COPY-FIELD-SOURCE? ( -- flag )
    0 _RTHP-W-P @ _RTHP.FIELD-DESCRIPTORS-USED !
    0 _RTHP-W-P @ _RTHP.FIELD-NATIVE-USED !
    _RTHP-W-SNAP @ RUHA-SNAPSHOT-FIELDS-DESCRIPTORS@
        _RTHP-FI-DU ! _RTHP-FI-DA !
    _RTHP-W-SNAP @ RUHA-SNAPSHOT-FIELDS-NATIVE@
        _RTHP-FI-NU ! _RTHP-FI-NA !
    _RTHP-FI-DA @ _RTHP-FI-DU @ _RTHP-FI-SPAN? 0= IF 0 EXIT THEN
    _RTHP-FI-NA @ _RTHP-FI-NU @ _RTHP-FI-SPAN? 0= IF 0 EXIT THEN
    _RTHP-FI-DU @ UFLSN-DESCRIPTOR-SIZE MOD IF 0 EXIT THEN
    _RTHP-FI-DU @ UFLSN-DESCRIPTOR-SIZE /
        _RTHP-W-SNAP @ RUHA-SNAPSHOT-FIELDS-COUNT@ <> IF 0 EXIT THEN
    _RTHP-FI-DA @ _RTHP-FI-DU @ _RTHP-FI-NA @ _RTHP-FI-NU @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTHP-FI-DIRECTORY? 0= IF 0 EXIT THEN
    _RTHP-FI-DU @ _RTHP-W-P @ _RTHP.FIELD-DESCRIPTORS-U @ U> 0=
    _RTHP-FI-NU @ _RTHP-W-P @ _RTHP.FIELD-NATIVE-U @ U> 0= AND
    _RTHP-W-P @ _RTHP.LIMITS RTE-LIMITS-FEATURES@
        RTE-F-FIELDS AND 0<> AND _RTHP-FI-COPY !
    _RTHP-FI-COPY @ 0= IF _RTHP-FI-STRIP-DIRECTORY -1 EXIT THEN
    _RTHP-FI-DA @ _RTHP-W-P @ _RTHP.FIELD-DESCRIPTORS-A @
        _RTHP-FI-DU @ MOVE
    _RTHP-FI-NA @ _RTHP-W-P @ _RTHP.FIELD-NATIVE-A @
        _RTHP-FI-NU @ MOVE
    _RTHP-FI-DU @ _RTHP-W-P @ _RTHP.FIELD-DESCRIPTORS-USED !
    _RTHP-FI-NU @ _RTHP-W-P @ _RTHP.FIELD-NATIVE-USED ! -1 ;

\ A document's dialog is one UDLSN descriptor and its model, or nothing.
\ The directory places each document's slices in order, as for fields.
VARIABLE _RTHP-DI-DA
VARIABLE _RTHP-DI-DU
VARIABLE _RTHP-DI-NA
VARIABLE _RTHP-DI-NU
VARIABLE _RTHP-DI-DC
VARIABLE _RTHP-DI-NC
VARIABLE _RTHP-DI-DOC
VARIABLE _RTHP-DI-COPY

: _RTHP-DI-DIRECTORY? ( -- flag )
    0 _RTHP-DI-DC ! 0 _RTHP-DI-NC !
    _RTHP-W-DOCUMENTS @ 0 ?DO
        _RTHP-W-DIRECTORY-A @ I RUHA-DOCUMENT-SIZE * + _RTHP-DI-DOC !
        _RTHP-DI-DOC @ RUHA-DOCUMENT-DIALOGS-DESCRIPTOR-OFFSET@
            _RTHP-DI-DC @ <> IF 0 UNLOOP EXIT THEN
        _RTHP-DI-DOC @ RUHA-DOCUMENT-DIALOGS-DESCRIPTOR-BYTES@
            DUP UDLSN-DESCRIPTOR-SIZE U> IF DROP 0 UNLOOP EXIT THEN
            DUP 0<> OVER UDLSN-DESCRIPTOR-SIZE <> AND
            IF DROP 0 UNLOOP EXIT THEN
        _RTHP-DI-DC @ SWAP _RTHP-U32+?
            0= IF DROP 0 UNLOOP EXIT THEN
        DUP _RTHP-DI-DU @ U> IF DROP 0 UNLOOP EXIT THEN _RTHP-DI-DC !
        _RTHP-DI-DOC @ RUHA-DOCUMENT-DIALOGS-NATIVE-OFFSET@
            _RTHP-DI-NC @ <> IF 0 UNLOOP EXIT THEN
        _RTHP-DI-DOC @ RUHA-DOCUMENT-DIALOGS-NATIVE-BYTES@
            DUP 7 AND IF DROP 0 UNLOOP EXIT THEN
        DUP 0= _RTHP-DI-DOC @
            RUHA-DOCUMENT-DIALOGS-DESCRIPTOR-BYTES@ 0= <>
            IF DROP 0 UNLOOP EXIT THEN
        _RTHP-DI-NC @ SWAP _RTHP-U32+?
            0= IF DROP 0 UNLOOP EXIT THEN
        DUP _RTHP-DI-NU @ U> IF DROP 0 UNLOOP EXIT THEN _RTHP-DI-NC !
    LOOP
    _RTHP-DI-DC @ _RTHP-DI-DU @ =
    _RTHP-DI-NC @ _RTHP-DI-NU @ = AND ;

: _RTHP-DI-STRIP-DIRECTORY ( -- )
    _RTHP-W-DOCUMENTS @ 0 ?DO
        I _RTHP-W-P @ _RTHP-DOCUMENT-AT
        0 OVER 240 + ! 0 OVER 248 + ! 0 OVER 256 + ! 0 SWAP 264 + !
    LOOP ;

\ Without DIALOGS, or without room, the documents keep their dialogs as
\ CELL paint: the lane is empty and the directory names no dialog.
: _RTHP-COPY-DIALOG-SOURCE? ( -- flag )
    0 _RTHP-W-P @ _RTHP.DIALOG-DESCRIPTORS-USED !
    0 _RTHP-W-P @ _RTHP.DIALOG-NATIVE-USED !
    _RTHP-W-SNAP @ RUHA-SNAPSHOT-DIALOGS-DESCRIPTORS@
        _RTHP-DI-DU ! _RTHP-DI-DA !
    _RTHP-W-SNAP @ RUHA-SNAPSHOT-DIALOGS-NATIVE@
        _RTHP-DI-NU ! _RTHP-DI-NA !
    _RTHP-DI-DA @ _RTHP-DI-DU @ _RTHP-FI-SPAN? 0= IF 0 EXIT THEN
    _RTHP-DI-NA @ _RTHP-DI-NU @ _RTHP-FI-SPAN? 0= IF 0 EXIT THEN
    _RTHP-DI-DU @ UDLSN-DESCRIPTOR-SIZE MOD IF 0 EXIT THEN
    _RTHP-DI-DU @ UDLSN-DESCRIPTOR-SIZE /
        _RTHP-W-SNAP @ RUHA-SNAPSHOT-DIALOGS-COUNT@ <> IF 0 EXIT THEN
    _RTHP-DI-DA @ _RTHP-DI-DU @ _RTHP-DI-NA @ _RTHP-DI-NU @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTHP-DI-DIRECTORY? 0= IF 0 EXIT THEN
    _RTHP-DI-DU @ _RTHP-W-P @ _RTHP.DIALOG-DESCRIPTORS-U @ U> 0=
    _RTHP-DI-NU @ _RTHP-W-P @ _RTHP.DIALOG-NATIVE-U @ U> 0= AND
    _RTHP-W-P @ _RTHP.LIMITS RTE-LIMITS-FEATURES@
        RTE-F-DIALOGS AND 0<> AND _RTHP-DI-COPY !
    _RTHP-DI-COPY @ 0= IF _RTHP-DI-STRIP-DIRECTORY -1 EXIT THEN
    _RTHP-DI-DA @ _RTHP-W-P @ _RTHP.DIALOG-DESCRIPTORS-A @
        _RTHP-DI-DU @ MOVE
    _RTHP-DI-NA @ _RTHP-W-P @ _RTHP.DIALOG-NATIVE-A @
        _RTHP-DI-NU @ MOVE
    _RTHP-DI-DU @ _RTHP-W-P @ _RTHP.DIALOG-DESCRIPTORS-USED !
    _RTHP-DI-NU @ _RTHP-W-P @ _RTHP.DIALOG-NATIVE-USED ! -1 ;

: _RTHP-COPY-SNAPSHOT?  ( snapshot producer -- flag )
    _RTHP-W-P ! _RTHP-W-SNAP !
    _RTHP-W-SNAP @ RUHA-SNAPSHOT-DRAW-GENERATION@
        _RTHP-W-DRAW @ <> IF 0 EXIT THEN
    _RTHP-W-SNAP @ RUHA-SNAPSHOT-GENERATION@ DUP 0= IF DROP 0 EXIT THEN
        _RTHP-W-SOURCE-GEN !
    _RTHP-W-SNAP @ RUHA-SNAPSHOT-CONTENT-EPOCH@ DUP 0= IF
        DROP 0 EXIT
    THEN _RTHP-W-CONTENT-EPOCH !
    _RTHP-W-SNAPSHOT-SPANS? 0= IF 0 EXIT THEN

    _RTHP-W-DIRECTORY-A @ _RTHP-W-P @ _RTHP.SOURCE-DIR-A @
        _RTHP-W-DIRECTORY-U @ MOVE
    _RTHP-W-DIRECTORY-U @ _RTHP-W-P @ _RTHP.SOURCE-DIR-USED !
    _RTHP-COPY-STATUS-SOURCE? 0= IF 0 EXIT THEN
    _RTHP-COPY-FIELD-SOURCE? 0= IF 0 EXIT THEN
    0 _RTHP-W-P @ _RTHP.FIELD-REFUSED !
    0 _RTHP-W-P @ _RTHP.FIELD-COUNT !
    0 _RTHP-W-P @ _RTHP.FIELD-ITEMS !
    0 _RTHP-W-P @ _RTHP.FIELD-UTF8 !
    _RTHP-COPY-DIALOG-SOURCE? 0= IF 0 EXIT THEN
    0 _RTHP-W-P @ _RTHP.DIALOG-REFUSED !
    0 _RTHP-W-P @ _RTHP.DIALOG-COUNT !
    0 _RTHP-W-P @ _RTHP.DIALOG-CONTROLS !
    _RTHP-W-RECORDS-A @ _RTHP-W-P @ _RTHP.SOURCE-RECS-A @
        _RTHP-W-RECORDS-U @ MOVE
    _RTHP-W-RECORDS-U @ _RTHP-W-P @ _RTHP.SOURCE-USED !
    _RTHP-W-TEXT-A @ _RTHP-W-P @ _RTHP.SOURCE-TEXT-A @
        _RTHP-W-TEXT-U @ MOVE
    _RTHP-W-TEXT-U @ DUP
        _RTHP-W-P @ _RTHP.SOURCE-MENU-TEXT-USED !
        _RTHP-W-P @ _RTHP.SOURCE-TEXT-USED !
    _RTHP-W-DGRAPH-DESCRIPTORS-A @
        _RTHP-W-P @ _RTHP.DGRAPH-DESCRIPTORS-A @
        _RTHP-W-DGRAPH-DESCRIPTORS-U @ MOVE
    _RTHP-W-DGRAPH-DESCRIPTORS-U @
        _RTHP-W-P @ _RTHP.DGRAPH-DESCRIPTORS-USED !
    _RTHP-W-DGRAPH-NATIVE-A @ _RTHP-W-P @ _RTHP.DGRAPH-NATIVE-A @
        _RTHP-W-DGRAPH-NATIVE-U @ MOVE
    _RTHP-W-DGRAPH-NATIVE-U @
        _RTHP-W-P @ _RTHP.DGRAPH-NATIVE-USED !
    _RTHP-W-SOURCE-DGRAPHS @ _RTHP-W-P @ _RTHP.SOURCE-DGRAPH-COUNT !
    _RTHP-W-COPY-COLLECTIONS @ IF
        _RTHP-W-DESCRIPTORS-A @
        _RTHP-W-P @ _RTHP.COLLECTION-DESCRIPTORS-A @
            _RTHP-W-DESCRIPTORS-U @ MOVE
        _RTHP-W-DESCRIPTORS-U @
            _RTHP-W-P @ _RTHP.COLLECTION-DESCRIPTORS-USED !
        _RTHP-W-NATIVE-A @ _RTHP-W-P @ _RTHP.COLLECTION-NATIVE-A @
            _RTHP-W-NATIVE-U @ MOVE
        _RTHP-W-NATIVE-U @
            _RTHP-W-P @ _RTHP.COLLECTION-NATIVE-USED !
        _RTHP-W-SOURCE-COLLECTIONS @
            _RTHP-W-P @ _RTHP.SOURCE-COLLECTION-COUNT !
    ELSE
        0 _RTHP-W-P @ _RTHP.COLLECTION-DESCRIPTORS-USED !
        0 _RTHP-W-P @ _RTHP.COLLECTION-NATIVE-USED !
        0 _RTHP-W-P @ _RTHP.SOURCE-COLLECTION-COUNT !
        _RTHP-W-STRIP-COLLECTION-DIRECTORY
    THEN
    _RTHP-W-SOURCE-GEN @ _RTHP-W-P @ _RTHP.SOURCE-GEN !
    _RTHP-W-CONTENT-EPOCH @
        _RTHP-W-P @ _RTHP.SOURCE-CONTENT-EPOCH !
    _RTHP-W-DRAW @ _RTHP-W-P @ _RTHP.SOURCE-DRAW !
    _RTHP-W-DOCUMENTS @ _RTHP-W-P @ _RTHP.DOCUMENT-COUNT !
    _RTHP-W-P @ _RTHP.ATTEMPT @ 1 _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
        DUP 0= IF DROP 0 EXIT THEN _RTHP-W-P @ _RTHP.ATTEMPT !
    -1 ;

VARIABLE _RTHP-C-P
VARIABLE _RTHP-C-DRAW
VARIABLE _RTHP-C-RESULT

: _RTHP-CURRENT-FINISH  ( flag -- flag )
    _RTHP-C-RESULT !
    0 _RTHP-C-P ! 0 _RTHP-C-DRAW !
    _RTHP-C-RESULT @ ;

\ ( generation content-epoch documents -- flag ) against the copied source.
: _RTHP-C-SOURCE-IDENTITY?  ( generation content-epoch documents -- flag )
    _RTHP-C-P @ _RTHP.DOCUMENT-COUNT @ =
    SWAP _RTHP-C-P @ _RTHP.SOURCE-CONTENT-EPOCH @ = AND
    SWAP _RTHP-C-P @ _RTHP.SOURCE-GEN @ = AND ;

\ This is an O(1) identity check, not another caller-bank validation.  It
\ binds the copied semantic source and wrapped projection to the same latest
\ completed ordinary draw and to RUHA's still-open borrow gate, without
\ capturing, re-proving caller storage, or retaining a borrowed snapshot.
\ Flush retries while a sealed candidate awaits its ACK repeat only this.
: _RTHP-DRAW-CURRENT?  ( draw-generation producer -- flag )
    _RTHP-C-P ! _RTHP-C-DRAW !
    _RTHP-C-DRAW @ 0= IF 0 _RTHP-CURRENT-FINISH EXIT THEN
    SCR-DRAW-GENERATION@ _RTHP-C-DRAW @ <> IF
        0 _RTHP-CURRENT-FINISH EXIT
    THEN
    _RTHP-C-P @ _RTHP.HYBRID _RTE-HP.SURFACE-GENERATION @
        _RTHP-C-DRAW @ <> IF 0 _RTHP-CURRENT-FINISH EXIT THEN
    _RTHP-C-P @ _RTHP.SOURCE-DRAW @
        _RTHP-C-DRAW @ <> IF 0 _RTHP-CURRENT-FINISH EXIT THEN
    _RTHP-C-DRAW @ _RTHP-C-P @ _RTHP.ADAPTER @ RUHA-SNAPSHOT-IDENTITY@
    RUHA-S-OK <> IF 2DROP DROP 0 _RTHP-CURRENT-FINISH EXIT THEN
    _RTHP-C-SOURCE-IDENTITY? _RTHP-CURRENT-FINISH ;

: _RTHP-CANDIDATE-CURRENT?  ( producer -- flag )
    DUP _RTHP.SURFACE-GEN @ SWAP _RTHP-DRAW-CURRENT? ;

: _RTHP-W-COPIED-BEGIN  ( -- )
    _RTHP-W-P @ _RTHP.SOURCE-USED @ _RTHP-W-RECORDS-U !
    _RTHP-W-P @ _RTHP.SOURCE-MENU-TEXT-USED @ _RTHP-W-TEXT-U !
    _RTHP-W-P @ _RTHP.COLLECTION-DESCRIPTORS-USED @
        _RTHP-W-DESCRIPTORS-U !
    _RTHP-W-P @ _RTHP.COLLECTION-NATIVE-USED @ _RTHP-W-NATIVE-U !
    _RTHP-W-P @ _RTHP.DGRAPH-DESCRIPTORS-USED @
        _RTHP-W-DGRAPH-DESCRIPTORS-U !
    _RTHP-W-P @ _RTHP.DGRAPH-NATIVE-USED @
        _RTHP-W-DGRAPH-NATIVE-U !
    0 _RTHP-W-RECORD-CURSOR ! 0 _RTHP-W-TEXT-CURSOR !
    0 _RTHP-W-DESCRIPTOR-CURSOR ! 0 _RTHP-W-NATIVE-CURSOR !
    0 _RTHP-W-DGRAPH-DESCRIPTOR-CURSOR !
    0 _RTHP-W-DGRAPH-NATIVE-CURSOR !
    0 _RTHP-W-DOCUMENT-I ! ;

: _RTHP-W-COPIED-DOCUMENT?  ( -- flag )
    _RTHP-W-DOCUMENT-I @ _RTHP-W-P @ _RTHP-DOCUMENT-AT
        _RTHP-W-DOCUMENT !
    _RTHP-W-DOCUMENT-SHAPE? ;

: _RTHP-W-COPIED-COMPLETE?  ( -- flag )
    _RTHP-W-DOCUMENT-I @ _RTHP-W-P @ _RTHP.DOCUMENT-COUNT @ =
    _RTHP-W-RECORD-CURSOR @ _RTHP-W-P @ _RTHP.SOURCE-USED @ = AND
    _RTHP-W-TEXT-CURSOR @
        _RTHP-W-P @ _RTHP.SOURCE-MENU-TEXT-USED @ = AND
    _RTHP-W-DESCRIPTOR-CURSOR @
        _RTHP-W-P @ _RTHP.COLLECTION-DESCRIPTORS-USED @ = AND
    _RTHP-W-NATIVE-CURSOR @
        _RTHP-W-P @ _RTHP.COLLECTION-NATIVE-USED @ = AND
    _RTHP-W-DGRAPH-DESCRIPTOR-CURSOR @
        _RTHP-W-P @ _RTHP.DGRAPH-DESCRIPTORS-USED @ = AND
    _RTHP-W-DGRAPH-NATIVE-CURSOR @
        _RTHP-W-P @ _RTHP.DGRAPH-NATIVE-USED @ = AND ;

\ RUCP lookup and order work is indexed by sparse UMSN source index, not by
\ record ordinal.  The copied document is canonical, so its final record
\ carries the exact source-index high-water.  Bound that borrowed value
\ before exposing only the required prefixes of the shared work banks.
: _RTHP-W-RUCP-WORK-SPANS?  ( -- flag )
    _RTHP-W-DOC-RECORD-COUNT @ DUP 0= IF DROP 0 EXIT THEN
    1- UMSN-RECORD-SIZE *
    _RTHP-W-P @ _RTHP.SOURCE-RECS-A @
        _RTHP-W-DOC-RECORD-O @ + +
    UMSN-RECORD-SOURCE-INDEX@ DUP 0< IF DROP 0 EXIT THEN
    1 _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    DUP 0= IF DROP 0 EXIT THEN
    DUP _RTHP-W-P @ _RTHP.MAX-RECORDS @ U> IF DROP 0 EXIT THEN
        _RTHP-W-RUCP-HIGH-WATER !

    _RTHP-W-RUCP-HIGH-WATER @ RUCP-LOOKUP-ENTRY-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-W-P @ _RTHP.LOOKUP-U @ U> IF DROP 0 EXIT THEN
        _RTHP-W-RUCP-LOOKUP-U !
    _RTHP-W-RUCP-HIGH-WATER @ 8 _RTHP-U32*?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-W-P @ _RTHP.ORDER-U @ U> IF DROP 0 EXIT THEN
    DUP _RTHP-W-P @ _RTHP.ORDER2-U @ U> IF DROP 0 EXIT THEN
        _RTHP-W-RUCP-ORDER-U !
    -1 ;

: _RTHP-W-WRAP-CONTROL-PLAN?  ( -- flag )
    _RTHP-W-P @ _RTHP.CONTROL-PLAN RTE-CONTROL-PLAN-SIZE 0 FILL
    _RTHP-W-P @ _RTHP.CONTROL-COUNT @ 0= IF -1 EXIT THEN
    _RTHP-W-P @ _RTHP.OWNER @
        _RTHP-W-P @ _RTHP.CONTROL-PLAN _RTE-CP.OWNER !
    _RTHP-W-P @ _RTHP.OWNER-GEN @
        _RTHP-W-P @ _RTHP.CONTROL-PLAN _RTE-CP.GENERATION !
    _RTHP-W-P @ _RTHP.COLS @
        _RTHP-W-P @ _RTHP.CONTROL-PLAN _RTE-CP.SURFACE-COLS !
    _RTHP-W-P @ _RTHP.ROWS @
        _RTHP-W-P @ _RTHP.CONTROL-PLAN _RTE-CP.SURFACE-ROWS !
    _RTHP-W-P @ _RTHP.REGION @
        _RTHP-W-P @ _RTHP.CONTROL-PLAN _RTE-CP.REGION-ID !
    0 _RTHP-W-P @ _RTHP.CONTROL-PLAN _RTE-CP.REGION-X !
    0 _RTHP-W-P @ _RTHP.CONTROL-PLAN _RTE-CP.REGION-Y !
    _RTHP-W-P @ _RTHP.COLS @
        _RTHP-W-P @ _RTHP.CONTROL-PLAN _RTE-CP.REGION-COLS !
    _RTHP-W-P @ _RTHP.ROWS @
        _RTHP-W-P @ _RTHP.CONTROL-PLAN _RTE-CP.REGION-ROWS !
    0 _RTHP-W-P @ _RTHP.CONTROL-PLAN _RTE-CP.CLIP-X !
    0 _RTHP-W-P @ _RTHP.CONTROL-PLAN _RTE-CP.CLIP-Y !
    0 _RTHP-W-P @ _RTHP.CONTROL-PLAN _RTE-CP.CLIP-COLS !
    0 _RTHP-W-P @ _RTHP.CONTROL-PLAN _RTE-CP.CLIP-ROWS !
    0 _RTHP-W-P @ _RTHP.CONTROL-PLAN _RTE-CP.REGION-Z !
    RTE-REGION-VISIBLE
        _RTHP-W-P @ _RTHP.CONTROL-PLAN _RTE-CP.REGION-FLAGS !
    _RTHP-W-P @ _RTHP.CONTROLS-A @
        _RTHP-W-P @ _RTHP.CONTROL-PLAN _RTE-CP.ITEMS-A !
    _RTHP-W-P @ _RTHP.CONTROL-COUNT @ RTE-CONTROL-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN
        _RTHP-W-P @ _RTHP.CONTROL-PLAN _RTE-CP.ITEMS-U !
    -1 ;

\ Each RUCP build owns only its document's append slice.  Advertising the
\ remaining aggregate tail would turn RUCP's deliberate failure scrub into
\ a capacity-wide clear on every ordinary draw.
: _RTHP-W-CONTROL-OUTPUT?  ( -- flag )
    _RTHP-W-DOC-RECORD-COUNT @ RTE-CONTROL-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN _RTHP-W-RUCP-CONTROL-U !
    _RTHP-W-TOTAL @ RTE-CONTROL-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-W-P @ _RTHP.CONTROLS-U @ U> IF DROP 0 EXIT THEN
    DUP _RTHP-W-P @ _RTHP.CONTROLS-A @ + _RTHP-W-OUT-CONTROLS-A !
    _RTHP-W-P @ _RTHP.CONTROLS-U @ SWAP -
        _RTHP-W-RUCP-CONTROL-U @ U< IF 0 EXIT THEN
    _RTHP-W-RUCP-CONTROL-U @ _RTHP-W-OUT-CONTROLS-U !
    _RTHP-W-DOC-RECORD-COUNT @ RUCP-CORRELATION-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN _RTHP-W-RUCP-CORR-U !
    _RTHP-W-TOTAL @ RUCP-CORRELATION-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-W-P @ _RTHP.CORR-U @ U> IF DROP 0 EXIT THEN
    DUP _RTHP-W-P @ _RTHP.CORR-A @ + _RTHP-W-OUT-CORR-A !
    _RTHP-W-P @ _RTHP.CORR-U @ SWAP -
        _RTHP-W-RUCP-CORR-U @ U< IF 0 EXIT THEN
    _RTHP-W-RUCP-CORR-U @ _RTHP-W-OUT-CORR-U !
    -1 ;

\ A later full candidate may borrow only the immutable target bank whose
\ exact frame was physically acknowledged.  The retained RUHA directory is
\ the lineage index; no applet or renderer-specific scene participates.
VARIABLE _RTHP-W-MR-ACTIVE
VARIABLE _RTHP-W-MR-DIRECTORY
VARIABLE _RTHP-W-MR-CONTROLS
VARIABLE _RTHP-W-MR-CORR
VARIABLE _RTHP-W-MR-TEXT
VARIABLE _RTHP-W-MR-ENABLED
VARIABLE _RTHP-W-MR-ACTIVE-DOCUMENT
VARIABLE _RTHP-W-MR-MATCHES
VARIABLE _RTHP-W-MR-I
VARIABLE _RTHP-W-MR-ORDINAL
VARIABLE _RTHP-W-MR-COUNT
VARIABLE _RTHP-W-MR-OLD-CONTROLS
VARIABLE _RTHP-W-MR-OLD-CORR
VARIABLE _RTHP-W-MR-OLD-TEXT
VARIABLE _RTHP-W-MR-NEW-TEXT
VARIABLE _RTHP-W-MR-TEXT-U
VARIABLE _RTHP-W-MR-OLD-FIRST
VARIABLE _RTHP-W-MR-OLD-LAST
VARIABLE _RTHP-W-MR-NEW-FIRST
VARIABLE _RTHP-W-MR-NEW-NEXT
VARIABLE _RTHP-W-MR-NEW-TOTAL
VARIABLE _RTHP-W-MR-CONTROL
VARIABLE _RTHP-W-MR-CORRELATION
VARIABLE _RTHP-W-MR-RECORD
VARIABLE _RTHP-W-MR-ID
VARIABLE _RTHP-W-MR-PARENT
VARIABLE _RTHP-W-MR-SPAN-A
VARIABLE _RTHP-W-MR-SPAN-U
VARIABLE _RTHP-W-MR-SPAN-O
VARIABLE _RTHP-W-MR-PATCH-STATE
VARIABLE _RTHP-W-MR-KIND
VARIABLE _RTHP-W-MR-STATE
VARIABLE _RTHP-W-MR-PARENT-ID
VARIABLE _RTHP-W-MR-OPEN-SEEN
VARIABLE _RTHP-W-MR-SELECTED-SEEN

: _RTHP-W-MENU-REUSE-CLEAR  ( -- )
    0 _RTHP-W-MR-ACTIVE ! 0 _RTHP-W-MR-DIRECTORY !
    0 _RTHP-W-MR-CONTROLS ! 0 _RTHP-W-MR-CORR !
    0 _RTHP-W-MR-TEXT ! 0 _RTHP-W-MR-ENABLED !
    0 _RTHP-W-MR-ACTIVE-DOCUMENT ! 0 _RTHP-W-MR-MATCHES !
    0 _RTHP-W-MR-I ! 0 _RTHP-W-MR-ORDINAL ! 0 _RTHP-W-MR-COUNT !
    0 _RTHP-W-MR-OLD-CONTROLS ! 0 _RTHP-W-MR-OLD-CORR !
    0 _RTHP-W-MR-OLD-TEXT ! 0 _RTHP-W-MR-NEW-TEXT !
    0 _RTHP-W-MR-TEXT-U ! 0 _RTHP-W-MR-OLD-FIRST !
    0 _RTHP-W-MR-OLD-LAST ! 0 _RTHP-W-MR-NEW-FIRST !
    0 _RTHP-W-MR-NEW-NEXT !
    0 _RTHP-W-MR-NEW-TOTAL ! 0 _RTHP-W-MR-CONTROL !
    0 _RTHP-W-MR-CORRELATION ! 0 _RTHP-W-MR-RECORD !
    0 _RTHP-W-MR-ID ! 0 _RTHP-W-MR-PARENT !
    0 _RTHP-W-MR-SPAN-A ! 0 _RTHP-W-MR-SPAN-U !
    0 _RTHP-W-MR-SPAN-O !
    0 _RTHP-W-MR-PATCH-STATE ! 0 _RTHP-W-MR-KIND !
    0 _RTHP-W-MR-STATE ! 0 _RTHP-W-MR-PARENT-ID !
    0 _RTHP-W-MR-OPEN-SEEN ! 0 _RTHP-W-MR-SELECTED-SEEN ! ;

: _RTHP-W-MENU-REUSE-BASELINE?  ( -- flag )
    _RTHP-W-MENU-REUSE-CLEAR
    _RTHP-W-P @ _RTHP.TARGET-ACTIVE @ DUP 0= IF DROP 0 EXIT THEN
        _RTHP-W-MR-ACTIVE !
    _RTHP-W-MR-ACTIVE @ _RTHP-W-P @ _RTHP-TARGET-BANK-HEADER?
        0= IF 0 EXIT THEN
    _RTHP-W-MR-ACTIVE @ _RTHP-TB.OWNER @
        _RTHP-W-P @ _RTHP.OWNER @ <> IF 0 EXIT THEN
    _RTHP-W-MR-ACTIVE @ _RTHP-TB.GENERATION @
        _RTHP-W-P @ _RTHP.OWNER-GEN @ <> IF 0 EXIT THEN
    _RTHP-W-MR-ACTIVE @ _RTHP-TB.COLS @
        _RTHP-W-P @ _RTHP.COLS @ <> IF 0 EXIT THEN
    _RTHP-W-MR-ACTIVE @ _RTHP-TB.ROWS @
        _RTHP-W-P @ _RTHP.ROWS @ <> IF 0 EXIT THEN
    _RTHP-W-MR-ACTIVE @ _RTHP-TB.PHYSICAL-GEN @
        _RTHP-W-P @ _RTHP.PHYSICAL-GEN @ <> IF 0 EXIT THEN
    _RTHP-W-MR-ACTIVE @ _RTHP-TB.DRAW @ DUP 0= IF DROP 0 EXIT THEN
        _RTHP-W-P @ _RTHP.ACTIVE-DRAW @ <> IF 0 EXIT THEN
    _RTHP-W-MR-ACTIVE @ _RTHP-PACK-DIRECTORY-A
        _RTHP-W-MR-DIRECTORY !
    _RTHP-W-MR-ACTIVE @ _RTHP-PACK-CONTROLS-A
        _RTHP-W-MR-CONTROLS !
    _RTHP-W-MR-ACTIVE @ _RTHP-PACK-CORR-A _RTHP-W-MR-CORR !
    _RTHP-W-MR-ACTIVE @ _RTHP-PACK-SOURCE-A _RTHP-W-MR-TEXT !
    -1 ;

: _RTHP-W-MENU-REUSE-FIND-DOCUMENT?  ( -- flag )
    0 _RTHP-W-MR-MATCHES ! 0 _RTHP-W-MR-I !
    BEGIN _RTHP-W-MR-I @
        _RTHP-W-MR-ACTIVE @ _RTHP-TB.DOCUMENT-COUNT @ U< WHILE
        _RTHP-W-MR-DIRECTORY @
        _RTHP-W-MR-I @ RUHA-DOCUMENT-SIZE * +
        DUP RUHA-DOCUMENT-TOKEN@
            _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-TOKEN@ = IF
            DUP RUHA-DOCUMENT-SLOT-ID@
                _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-SLOT-ID@ <> IF
                DROP 0 EXIT
            THEN
            _RTHP-W-MR-ACTIVE-DOCUMENT !
            1 _RTHP-W-MR-MATCHES +!
        ELSE
            DROP
        THEN
        1 _RTHP-W-MR-I +!
    REPEAT
    _RTHP-W-MR-MATCHES @ 1 = ;

: _RTHP-W-MENU-REUSE-DOCUMENT?  ( -- flag )
    _RTHP-W-MENU-REUSE-FIND-DOCUMENT? 0= IF 0 EXIT THEN
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-MENU-EPOCH@ DUP
        0= IF DROP 0 EXIT THEN
    _RTHP-W-MR-ACTIVE-DOCUMENT @ RUHA-DOCUMENT-MENU-EPOCH@
        DUP 0= IF 2DROP 0 EXIT THEN
    = IF
        0 _RTHP-W-MR-PATCH-STATE !
    ELSE
        _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@
            DUP 0= IF DROP 0 EXIT THEN
        _RTHP-W-MR-ACTIVE-DOCUMENT @
            RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@
            DUP 0= IF 2DROP 0 EXIT THEN
        <> IF 0 EXIT THEN
        -1 _RTHP-W-MR-PATCH-STATE !
    THEN
    _RTHP-W-DOCUMENT @ 16 + 32
    _RTHP-W-MR-ACTIVE-DOCUMENT @ 16 + 32 COMPARE IF 0 EXIT THEN
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-RECORD-BYTES@
        DUP _RTHP-W-MR-ACTIVE-DOCUMENT @
            RUHA-DOCUMENT-RECORD-BYTES@ <> IF DROP 0 EXIT THEN
    UMSN-RECORD-SIZE / DUP 0= IF DROP 0 EXIT THEN
        _RTHP-W-MR-COUNT !
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-RECORD-OFFSET@
        UMSN-RECORD-SIZE / _RTHP-W-TOTAL @ <> IF 0 EXIT THEN
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-TEXT-BYTES@ DUP
        _RTHP-W-MR-TEXT-U !
    _RTHP-W-MR-ACTIVE-DOCUMENT @ RUHA-DOCUMENT-TEXT-BYTES@
        <> IF 0 EXIT THEN

    _RTHP-W-MR-ACTIVE-DOCUMENT @ RUHA-DOCUMENT-RECORD-OFFSET@
        UMSN-RECORD-SIZE / DUP _RTHP-W-MR-ORDINAL !
    RTE-CONTROL-SIZE _RTHP-U32*? 0= IF DROP 0 EXIT THEN
    _RTHP-W-MR-CONTROLS @ SWAP _RTHP-U+?
        0= IF DROP 0 EXIT THEN _RTHP-W-MR-OLD-CONTROLS !
    _RTHP-W-MR-ORDINAL @ RUCP-CORRELATION-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN
    _RTHP-W-MR-CORR @ SWAP _RTHP-U+?
        0= IF DROP 0 EXIT THEN _RTHP-W-MR-OLD-CORR !
    _RTHP-W-MR-TEXT @
    _RTHP-W-MR-ACTIVE-DOCUMENT @ RUHA-DOCUMENT-TEXT-OFFSET@
        _RTHP-U+? 0= IF DROP 0 EXIT THEN _RTHP-W-MR-OLD-TEXT !
    _RTHP-W-P @ _RTHP.SOURCE-TEXT-A @
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-TEXT-OFFSET@
        _RTHP-U+? 0= IF DROP 0 EXIT THEN _RTHP-W-MR-NEW-TEXT !
    _RTHP-W-MR-OLD-TEXT @ _RTHP-W-MR-TEXT-U @
    _RTHP-W-MR-NEW-TEXT @ _RTHP-W-MR-TEXT-U @ COMPARE IF 0 EXIT THEN

    _RTHP-W-MR-ACTIVE @ _RTHP-TB.FIRST-OBJECT @
        _RTHP-W-MR-ORDINAL @ _RTHP-U+?
        0= IF DROP 0 EXIT THEN DUP _RTHP-W-MR-OLD-FIRST !
    _RTHP-W-MR-COUNT @ 1- _RTHP-U+?
        0= IF DROP 0 EXIT THEN _RTHP-W-MR-OLD-LAST !
    _RTHP-W-NEXT-ID @ DUP _RTHP-W-MR-NEW-FIRST !
    _RTHP-W-MR-NEW-FIRST @ _RTHP-W-MR-COUNT @ _RTHP-U+?
        0= IF DROP 0 EXIT THEN
    DUP 0= IF DROP 0 EXIT THEN _RTHP-W-MR-NEW-NEXT !
    _RTHP-W-TOTAL @ _RTHP-W-MR-COUNT @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-W-P @ _RTHP.MAX-RECORDS @ U> IF DROP 0 EXIT THEN
        _RTHP-W-MR-NEW-TOTAL !
    _RTHP-W-CONTROL-OUTPUT? ;

: _RTHP-W-MENU-REUSE-TEXT?  ( address bytes -- flag )
    _RTHP-W-MR-SPAN-U ! _RTHP-W-MR-SPAN-A !
    _RTHP-W-MR-SPAN-U @ 0= IF
        _RTHP-W-MR-SPAN-A @ 0= EXIT
    THEN
    _RTHP-W-MR-SPAN-A @ 0= IF 0 EXIT THEN
    _RTHP-W-MR-SPAN-A @ _RTHP-W-MR-SPAN-U @
        MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    _RTHP-W-MR-SPAN-A @ _RTHP-W-MR-OLD-TEXT @ U< IF 0 EXIT THEN
    _RTHP-W-MR-SPAN-A @ _RTHP-W-MR-OLD-TEXT @ - DUP
        _RTHP-W-MR-TEXT-U @ U> IF DROP 0 EXIT THEN
        _RTHP-W-MR-SPAN-O !
    _RTHP-W-MR-SPAN-U @
        _RTHP-W-MR-TEXT-U @ _RTHP-W-MR-SPAN-O @ - U> 0= ;

: _RTHP-W-MENU-REUSE-CONTROLS?  ( -- flag )
    0 _RTHP-W-MR-I !
    BEGIN _RTHP-W-MR-I @ _RTHP-W-MR-COUNT @ U< WHILE
        _RTHP-W-MR-OLD-CONTROLS @
        _RTHP-W-MR-I @ RTE-CONTROL-SIZE * +
            DUP _RTHP-W-MR-CONTROL !
        _RTHP-W-MR-CONTROL @ _RTE-CONTROL.CONTENT-A @
        _RTHP-W-MR-CONTROL @ _RTE-CONTROL.CONTENT-U @ OR
        _RTHP-W-MR-CONTROL @ _RTE-CONTROL.CONTENT-ITEMS @ OR
        _RTHP-W-MR-CONTROL @ _RTE-CONTROL.CONTENT-UTF8 @ OR IF
            DROP 0 EXIT
        THEN
        _RTHP-W-MR-CONTROL @ _RTE-CONTROL.LABEL-A @
        _RTHP-W-MR-CONTROL @ _RTE-CONTROL.LABEL-U @
            _RTHP-W-MENU-REUSE-TEXT? 0= IF DROP 0 EXIT THEN
        _RTHP-W-MR-CONTROL @ _RTE-CONTROL.SHORTCUT-A @
        _RTHP-W-MR-CONTROL @ _RTE-CONTROL.SHORTCUT-U @
            _RTHP-W-MENU-REUSE-TEXT? 0= IF DROP 0 EXIT THEN
        RTE-CONTROL-VALID? 0= IF 0 EXIT THEN
        _RTHP-W-MR-CONTROL @ _RTE-CONTROL.OWNER @
            _RTHP-W-MR-ACTIVE @ _RTHP-TB.OWNER @ <> IF 0 EXIT THEN
        _RTHP-W-MR-CONTROL @ _RTE-CONTROL.GENERATION @
            _RTHP-W-MR-ACTIVE @ _RTHP-TB.GENERATION @ <> IF 0 EXIT THEN
        _RTHP-W-MR-OLD-FIRST @ _RTHP-W-MR-I @ + DUP _RTHP-W-MR-ID !
        _RTHP-W-MR-CONTROL @ _RTE-CONTROL.ID @ <> IF 0 EXIT THEN
        _RTHP-W-MR-CONTROL @ _RTE-CONTROL.KIND @ DUP
            RTE-CONTROL-MENU-BAR < SWAP
            RTE-CONTROL-MENU-SEPARATOR > OR IF 0 EXIT THEN
        _RTHP-W-MR-I @ 0= IF
            _RTHP-W-MR-CONTROL @ _RTE-CONTROL.KIND @
                RTE-CONTROL-MENU-BAR <> IF 0 EXIT THEN
        ELSE
            _RTHP-W-MR-CONTROL @ _RTE-CONTROL.KIND @
                RTE-CONTROL-MENU-BAR = IF 0 EXIT THEN
        THEN
        _RTHP-W-MR-CONTROL @ _RTE-CONTROL.REGION @
            _RTHP-W-MR-ACTIVE @ _RTHP-TB.REGION @ <> IF 0 EXIT THEN
        _RTHP-W-MR-CONTROL @ _RTE-CONTROL.ROOT-HEIGHT @
            _RTHP-W-MR-ACTIVE @ _RTHP-TB.ROWS @ <> IF 0 EXIT THEN
        _RTHP-W-MR-CONTROL @ _RTE-CONTROL.ROOT-WIDTH @
            _RTHP-W-MR-ACTIVE @ _RTHP-TB.COLS @ <> IF 0 EXIT THEN
        _RTHP-W-MR-CONTROL @ _RTE-CONTROL.PARENT @ DUP
            _RTHP-W-MR-PARENT ! IF
            _RTHP-W-MR-PARENT @ _RTHP-W-MR-OLD-FIRST @ U< IF 0 EXIT THEN
            _RTHP-W-MR-PARENT @ _RTHP-W-MR-ID @ U< 0= IF 0 EXIT THEN
        THEN
        1 _RTHP-W-MR-I +!
    REPEAT
    -1 ;

: _RTHP-W-MENU-REUSE-CORRELATIONS?  ( -- flag )
    _RTHP-W-RUCP-WORK-SPANS? 0= IF 0 EXIT THEN
    _RTHP-W-MR-COUNT @ 8 _RTHP-U32*? 0= IF DROP 0 EXIT THEN
    DUP _RTHP-W-P @ _RTHP.ORDER-U @ U> IF DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.ORDER-A @ SWAP 0 FILL
    0 _RTHP-W-MR-I !
    BEGIN _RTHP-W-MR-I @ _RTHP-W-MR-COUNT @ U< WHILE
        _RTHP-W-MR-OLD-CORR @
        _RTHP-W-MR-I @ RUCP-CORRELATION-SIZE * +
            _RTHP-W-MR-CORRELATION !
        _RTHP-W-P @ _RTHP.SOURCE-RECS-A @ _RTHP-W-DOC-RECORD-O @ +
        _RTHP-W-MR-I @ UMSN-RECORD-SIZE * + _RTHP-W-MR-RECORD !
        _RTHP-W-MR-CORRELATION @ RUCP-CORRELATION-ATTACHMENT@
            _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-TOKEN@ <> IF 0 EXIT THEN
        _RTHP-W-MR-CORRELATION @ RUCP-CORRELATION-SOURCE@
            UMSN-SOURCE-UIDL <> IF 0 EXIT THEN
        _RTHP-W-MR-CORRELATION @ RUCP-CORRELATION-SCOPE@ IF 0 EXIT THEN
        _RTHP-W-MR-RECORD @ UMSN-RECORD-SOURCE-INDEX@ DUP
            0< IF DROP 0 EXIT THEN
        DUP _RTHP-W-RUCP-HIGH-WATER @ U< 0= IF DROP 0 EXIT THEN
        _RTHP-W-MR-CORRELATION @ RUCP-CORRELATION-INDEX@
            <> IF 0 EXIT THEN
        _RTHP-W-MR-RECORD @ UMSN-RECORD-SUBKEY@ DUP
            IF DROP 0 EXIT THEN
        _RTHP-W-MR-CORRELATION @ RUCP-CORRELATION-SUBKEY@
            <> IF 0 EXIT THEN
        _RTHP-W-MR-CORRELATION @
            RUCP-CORRELATION-LIFECYCLE-GENERATION@ IF 0 EXIT THEN
        _RTHP-W-MR-CORRELATION @ RUCP-CORRELATION-CONTROL-ID@
            DUP _RTHP-W-MR-OLD-FIRST @ U< IF DROP 0 EXIT THEN
        DUP _RTHP-W-MR-OLD-LAST @ U> IF DROP 0 EXIT THEN
        _RTHP-W-MR-OLD-FIRST @ - 8 * _RTHP-W-P @ _RTHP.ORDER-A @ +
            DUP @ IF DROP 0 EXIT THEN
        1 SWAP !
        1 _RTHP-W-MR-I +!
    REPEAT
    -1 ;

\ A changed exact menu epoch may reuse controls only when the adapter's
\ collision-free topology lineage matches the physically acknowledged
\ document.  Retained controls and correlations are still proved before any
\ output write; this pass authenticates current records and mutable state only.
: _RTHP-W-MENU-PATCH-BIND?  ( -- flag )
    _RTHP-W-MR-OLD-CORR @
    _RTHP-W-MR-I @ RUCP-CORRELATION-SIZE * +
        _RTHP-W-MR-CORRELATION !
    _RTHP-W-MR-CORRELATION @ RUCP-CORRELATION-CONTROL-ID@
        DUP _RTHP-W-MR-ID !
    DUP _RTHP-W-MR-OLD-FIRST @ U< IF DROP 0 EXIT THEN
    DUP _RTHP-W-MR-OLD-LAST @ U> IF DROP 0 EXIT THEN
    _RTHP-W-MR-OLD-FIRST @ - RTE-CONTROL-SIZE *
    _RTHP-W-MR-OLD-CONTROLS @ + _RTHP-W-MR-CONTROL !
    _RTHP-W-P @ _RTHP.SOURCE-RECS-A @ _RTHP-W-DOC-RECORD-O @ +
    _RTHP-W-MR-I @ UMSN-RECORD-SIZE * + _RTHP-W-MR-RECORD !
    -1 ;

: _RTHP-W-MENU-PATCH-STATE?  ( umsn-kind umsn-state -- flag )
    2DUP _RTHP-W-MR-STATE ! _RTHP-W-MR-KIND !
    UMSN-STATE-VALID? ;

: _RTHP-W-MENU-PATCH-UNIQUE?  ( -- flag )
    _RTHP-W-MR-KIND @ UMSN-K-MENU = IF
        _RTHP-W-MR-STATE @ UMSN-F-OPEN AND IF
            _RTHP-W-MR-OPEN-SEEN @ IF 0 EXIT THEN
            -1 _RTHP-W-MR-OPEN-SEEN !
        THEN
        _RTHP-W-MR-STATE @ UMSN-F-SELECTED AND IF
            _RTHP-W-MR-SELECTED-SEEN @ IF 0 EXIT THEN
            -1 _RTHP-W-MR-SELECTED-SEEN !
        THEN
        -1 EXIT
    THEN
    _RTHP-W-MR-KIND @ UMSN-K-ITEM =
    _RTHP-W-MR-STATE @ UMSN-F-SELECTED AND 0<> AND IF
        _RTHP-W-MR-PARENT-ID @ DUP 0= IF DROP 0 EXIT THEN
        DUP _RTHP-W-MR-OLD-FIRST @ U< IF DROP 0 EXIT THEN
        _RTHP-W-MR-OLD-FIRST @ - 8 * _RTHP-W-P @ _RTHP.ORDER-A @ +
        DUP @ IF DROP 0 EXIT THEN -1 SWAP !
    THEN
    -1 ;

: _RTHP-W-MENU-PATCH-RECORD?  ( -- flag )
    _RTHP-W-MR-RECORD @ _UMSN-R.MAGIC @
        _UMSN-RECORD-MAGIC <> IF 0 EXIT THEN
    _RTHP-W-MR-RECORD @ _UMSN-R.ABI @
        _UMSN-RECORD-ABI <> IF 0 EXIT THEN
    _RTHP-W-MR-RECORD @ _UMSN-R.BYTES @
        UMSN-RECORD-SIZE <> IF 0 EXIT THEN
    _RTHP-W-MR-RECORD @ _UMSN-R.SOURCE @
        UMSN-SOURCE-UIDL <> IF 0 EXIT THEN
    _RTHP-W-MR-RECORD @ UMSN-RECORD-GENERATION@
        _RTHP-W-P @ _RTHP.SOURCE-GEN @ <> IF 0 EXIT THEN
    _RTHP-W-MR-RECORD @ UMSN-RECORD-SOURCE-INDEX@
        _RTHP-W-MR-CORRELATION @ RUCP-CORRELATION-INDEX@
        <> IF 0 EXIT THEN
    _RTHP-W-MR-RECORD @ UMSN-RECORD-SUBKEY@
        _RTHP-W-MR-CORRELATION @ RUCP-CORRELATION-SUBKEY@
        <> IF 0 EXIT THEN
    _RTHP-W-MR-RECORD @ UMSN-RECORD-KIND@ DUP _RTHP-W-MR-KIND !
        _RTHP-CT-KIND>RTE DUP 0= IF DROP 0 EXIT THEN
    _RTHP-W-MR-CONTROL @ _RTE-CONTROL.KIND @ <> IF 0 EXIT THEN
    _RTHP-W-MR-RECORD @ UMSN-RECORD-STATE@
    _RTHP-W-MR-KIND @ SWAP _RTHP-W-MENU-PATCH-STATE?
        0= IF 0 EXIT THEN
    _RTHP-W-MR-CONTROL @ _RTE-CONTROL.PARENT @
        _RTHP-W-MR-PARENT-ID !
    _RTHP-W-MENU-PATCH-UNIQUE? ;

: _RTHP-W-MENU-PATCH-PREFLIGHT?  ( -- flag )
    _RTHP-W-MR-PATCH-STATE @ 0= IF -1 EXIT THEN
    _RTHP-W-MR-COUNT @ 8 _RTHP-U32*? 0= IF DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.ORDER-A @ SWAP 0 FILL
    0 _RTHP-W-MR-I !
    0 _RTHP-W-MR-OPEN-SEEN ! 0 _RTHP-W-MR-SELECTED-SEEN !
    BEGIN _RTHP-W-MR-I @ _RTHP-W-MR-COUNT @ U< WHILE
        _RTHP-W-MENU-PATCH-BIND? 0= IF 0 EXIT THEN
        _RTHP-W-MENU-PATCH-RECORD? 0= IF 0 EXIT THEN
        1 _RTHP-W-MR-I +!
    REPEAT
    -1 ;

: _RTHP-W-MENU-REUSE-PREFLIGHT?  ( -- flag )
    _RTHP-W-MENU-REUSE-CONTROLS? 0= IF 0 EXIT THEN
    _RTHP-W-MENU-REUSE-CORRELATIONS? ;

: _RTHP-W-MENU-REBASE-TEXT  ( old-address -- new-address )
    DUP 0= IF EXIT THEN
    _RTHP-W-MR-OLD-TEXT @ - _RTHP-W-MR-NEW-TEXT @ + ;

: _RTHP-W-MENU-REUSE-COPY  ( -- )
    _RTHP-W-MR-OLD-CONTROLS @ _RTHP-W-OUT-CONTROLS-A @
        _RTHP-W-RUCP-CONTROL-U @ MOVE
    _RTHP-W-MR-OLD-CORR @ _RTHP-W-OUT-CORR-A @
        _RTHP-W-RUCP-CORR-U @ MOVE
    _RTHP-W-MR-COUNT @ 0 ?DO
        _RTHP-W-OUT-CONTROLS-A @ I RTE-CONTROL-SIZE * +
            DUP _RTHP-W-MR-CONTROL !
        _RTHP-W-P @ _RTHP.OWNER @ OVER _RTE-CONTROL.OWNER !
        _RTHP-W-P @ _RTHP.OWNER-GEN @ OVER _RTE-CONTROL.GENERATION !
        _RTHP-W-MR-NEW-FIRST @ I + OVER _RTE-CONTROL.ID !
        _RTHP-W-P @ _RTHP.REGION @ OVER _RTE-CONTROL.REGION !
        DUP _RTE-CONTROL.PARENT @ ?DUP IF
            _RTHP-W-MR-OLD-FIRST @ - _RTHP-W-MR-NEW-FIRST @ +
            OVER _RTE-CONTROL.PARENT !
        THEN
        DUP _RTE-CONTROL.LABEL-A @ _RTHP-W-MENU-REBASE-TEXT
            OVER _RTE-CONTROL.LABEL-A !
        DUP _RTE-CONTROL.SHORTCUT-A @ _RTHP-W-MENU-REBASE-TEXT
            OVER _RTE-CONTROL.SHORTCUT-A !
        DUP _RTE-CONTROL.CONTENT-A @ _RTHP-W-MENU-REBASE-TEXT
            SWAP _RTE-CONTROL.CONTENT-A !
    LOOP
    _RTHP-W-MR-COUNT @ 0 ?DO
        _RTHP-W-OUT-CORR-A @ I RUCP-CORRELATION-SIZE * +
        DUP _RUCP-X.CONTROL-ID @ _RTHP-W-MR-OLD-FIRST @ -
            _RTHP-W-MR-NEW-FIRST @ +
        SWAP _RUCP-X.CONTROL-ID !
    LOOP
    _RTHP-W-MR-NEW-TOTAL @ _RTHP-W-TOTAL !
    _RTHP-W-MR-NEW-NEXT @ _RTHP-W-NEXT-ID ! ;

: _RTHP-W-MENU-PATCH-STATES  ( -- )
    0 _RTHP-W-MR-I !
    BEGIN _RTHP-W-MR-I @ _RTHP-W-MR-COUNT @ U< WHILE
        _RTHP-W-MENU-PATCH-BIND? DROP
        _RTHP-W-MR-ID @ _RTHP-W-MR-OLD-FIRST @ -
            RTE-CONTROL-SIZE * _RTHP-W-OUT-CONTROLS-A @ +
        _RTHP-W-MR-RECORD @ UMSN-RECORD-STATE@ RUCP-STATE>RTE
            SWAP _RTE-CONTROL.STATE !
        1 _RTHP-W-MR-I +!
    REPEAT ;

\ The controls and correlations a reuse copies are the producer's own,
\ admitted when they were first sent, and REUSE-DOCUMENT? has matched the
\ document, its menu epochs and its text, so the preflight that checks them
\ again runs only with every-frame checks on (check-mode.f).  The patch
\ preflight, which reads the current records, runs in both modes, and the
\ shadow check compares each reuse with a fresh plan in the runs that turn
\ it on.
: _RTHP-W-MENU-REUSE?  ( -- reused? )
    _RTHP-W-MR-ENABLED @ 0= IF 0 EXIT THEN
    _RTHP-W-MENU-REUSE-DOCUMENT? 0= IF 0 EXIT THEN
    CHK-EVERY-FRAME? IF
        _RTHP-W-MENU-REUSE-PREFLIGHT? _RTHP-BANKS-DAMAGED CHK-NAME
            0= IF 0 EXIT THEN
    THEN
    _RTHP-W-MENU-PATCH-PREFLIGHT? 0= IF 0 EXIT THEN
    _RTHP-W-MENU-REUSE-COPY
    _RTHP-W-MR-PATCH-STATE @ IF _RTHP-W-MENU-PATCH-STATES THEN
    -1 ;

: _RTHP-W-CLAIM-OUTPUT?  ( -- flag )
    _RTHP-W-CLAIMS @ RUCL-CLAIM-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-W-P @ _RTHP.CLAIMS-U @ U> IF DROP 0 EXIT THEN
    DUP _RTHP-W-P @ _RTHP.CLAIMS-A @ + _RTHP-W-OUT-CLAIMS-A !
    _RTHP-W-P @ _RTHP.CLAIMS-U @ SWAP - _RTHP-W-OUT-CLAIMS-U !
    -1 ;

\ Ask the planner for the current document's menu controls, numbered from
\ NEXT-ID.  The caller names where the output goes.
: _RTHP-W-RUCP-REQUEST  ( next-id -- )
    >R
    _RTHP-W-P @ _RTHP.RUCP-Q RUCP-REQUEST-CLEAR
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-TOKEN@
    _RTHP-W-P @ _RTHP.OWNER @ _RTHP-W-P @ _RTHP.OWNER-GEN @
    _RTHP-W-P @ _RTHP.SOURCE-GEN @ R>
    _RTHP-W-P @ _RTHP.RUCP-Q RUCP-REQUEST-IDENTITY!
    _RTHP-W-P @ _RTHP.COLS @ _RTHP-W-P @ _RTHP.ROWS @
    _RTHP-W-P @ _RTHP.REGION @ 0 0
    _RTHP-W-P @ _RTHP.COLS @ _RTHP-W-P @ _RTHP.ROWS @
    0 0 0 0 0 RTE-REGION-VISIBLE
    _RTHP-W-P @ _RTHP.RUCP-Q RUCP-REQUEST-REGION!
    _RTHP-W-P @ _RTHP.SOURCE-RECS-A @
        _RTHP-W-DOC-RECORD-O @ +
    _RTHP-W-DOC-RECORD-U @
    _RTHP-W-DOC-TEXT-U @ IF
        _RTHP-W-P @ _RTHP.SOURCE-TEXT-A @
            _RTHP-W-DOC-TEXT-O @ +
        _RTHP-W-DOC-TEXT-U @
    ELSE
        0 0
    THEN
    _RTHP-W-P @ _RTHP.RUCP-Q RUCP-REQUEST-SOURCE!
    _RTHP-W-P @ _RTHP.LOOKUP-A @ _RTHP-W-RUCP-LOOKUP-U @
    _RTHP-W-P @ _RTHP.ORDER-A @ _RTHP-W-RUCP-ORDER-U @
    _RTHP-W-P @ _RTHP.ORDER2-A @ _RTHP-W-RUCP-ORDER-U @
    _RTHP-W-P @ _RTHP.RUCP-Q RUCP-REQUEST-WORK! ;

\ Shadow check of menu reuse (frame-shadow.f).  A document whose menu
\ controls reuse copied from the acknowledged bank is also planned afresh,
\ into a scratch block, as a document whose menu changed would be: the
\ planner's status, count, text and last identity must be what reuse
\ implies, and its controls and correlations must equal the copied ones.
\ The items are 3N, 3N+1 and 3N+2 for the Nth document.
VARIABLE _RTHP-SM-A
VARIABLE _RTHP-SM-U
VARIABLE _RTHP-SM-HEAD
VARIABLE _RTHP-SM-CONTROLS
VARIABLE _RTHP-SM-CORR

: _RTHP-SH-MENU  ( -- )
    _RTHP-W-DRAW @ FSHD-DRAW !
    _RTHP-W-RUCP-CONTROL-U @ _RTHP-W-RUCP-CORR-U @ +
        RTE-CONTROL-PLAN-SIZE + 8 CELLS +
        _RTHP-SM-A _RTHP-SM-U FSHD-GROW
    DUP 0= IF DROP FSHD-SKIP EXIT THEN
    DUP _RTHP-SM-HEAD ! 8 CELLS +
    DUP _RTHP-SM-CONTROLS ! _RTHP-W-RUCP-CONTROL-U @ +
    DUP _RTHP-SM-CORR ! _RTHP-W-RUCP-CORR-U @ +
    _RTHP-W-RUCP-WORK-SPANS? 0= IF DROP FSHD-SKIP EXIT THEN
    _RTHP-W-MR-NEW-FIRST @ _RTHP-W-RUCP-REQUEST
    RTE-CONTROL-PLAN-SIZE
    _RTHP-SM-CONTROLS @ _RTHP-W-RUCP-CONTROL-U @
    _RTHP-SM-CORR @ _RTHP-W-RUCP-CORR-U @
    _RTHP-W-P @ _RTHP.RUCP-Q RUCP-REQUEST-OUTPUT!
    _RTHP-W-P @ _RTHP.RUCP-Q RUCP-BUILD
    \ ( count text aligned max last status )
    _RTHP-SM-HEAD @ !
    _RTHP-SM-HEAD @ 3 CELLS + !
    2DROP
    _RTHP-SM-HEAD @ 2 CELLS + !
    _RTHP-SM-HEAD @ CELL+ !
    RUCP-S-OK _RTHP-SM-HEAD @ 4 CELLS + !
    _RTHP-W-DOC-RECORD-COUNT @ _RTHP-SM-HEAD @ 5 CELLS + !
    _RTHP-W-DOC-TEXT-U @ _RTHP-SM-HEAD @ 6 CELLS + !
    _RTHP-W-MR-NEW-NEXT @ 1- _RTHP-SM-HEAD @ 7 CELLS + !
    _RTHP-SM-HEAD @ 4 CELLS + 4 CELLS _RTHP-SM-HEAD @ 4 CELLS
        _RTHP-W-DOCUMENT-I @ 3 * FSHD-STAGE-PRODUCER-MENUS FSHD-SAME?
        0= IF EXIT THEN
    _RTHP-W-OUT-CONTROLS-A @ _RTHP-W-RUCP-CONTROL-U @
    _RTHP-SM-CONTROLS @ _RTHP-W-RUCP-CONTROL-U @
        _RTHP-W-DOCUMENT-I @ 3 * 1+ FSHD-STAGE-PRODUCER-MENUS FSHD-SAME? DROP
    _RTHP-W-OUT-CORR-A @ _RTHP-W-RUCP-CORR-U @
    _RTHP-SM-CORR @ _RTHP-W-RUCP-CORR-U @
        _RTHP-W-DOCUMENT-I @ 3 * 2 + FSHD-STAGE-PRODUCER-MENUS FSHD-SAME? DROP ;

: _RTHP-BUILD-MENU-CONTROLS?  ( producer -- flag )
    _RTHP-W-P !
    0 _RTHP-W-TOTAL !
    _RTHP-W-P @ _RTHP.FIRST-OBJECT @ _RTHP-W-NEXT-ID !
    \ Safe mode plans every menu afresh.
    CHK-SAFE? IF 0 ELSE _RTHP-W-MENU-REUSE-BASELINE? THEN _RTHP-W-MR-ENABLED !
    _RTHP-W-COPIED-BEGIN
    BEGIN _RTHP-W-DOCUMENT-I @
        _RTHP-W-P @ _RTHP.DOCUMENT-COUNT @ U< WHILE
        _RTHP-W-COPIED-DOCUMENT? 0= IF 0 EXIT THEN
        _RTHP-W-DOC-RECORD-COUNT @ IF
          _RTHP-W-MENU-REUSE? IF
            FSHD? IF _RTHP-SH-MENU THEN
          ELSE
            _RTHP-W-RUCP-WORK-SPANS? 0= IF 0 EXIT THEN
            _RTHP-W-NEXT-ID @ _RTHP-W-RUCP-REQUEST
            _RTHP-W-CONTROL-OUTPUT? 0= IF 0 EXIT THEN
            _RTHP-W-P @ _RTHP.CONTROL-PLAN RTE-CONTROL-PLAN-SIZE
            _RTHP-W-OUT-CONTROLS-A @ _RTHP-W-OUT-CONTROLS-U @
            _RTHP-W-OUT-CORR-A @ _RTHP-W-OUT-CORR-U @
            _RTHP-W-P @ _RTHP.RUCP-Q RUCP-REQUEST-OUTPUT!
            _RTHP-W-P @ _RTHP.RUCP-Q RUCP-BUILD
            _RTHP-W-STATUS ! _RTHP-W-LAST ! _RTHP-W-MAX !
            _RTHP-W-ALIGNED ! _RTHP-W-TEXT ! _RTHP-W-COUNT !
            _RTHP-W-STATUS @ RUCP-S-OK <> IF 0 EXIT THEN
            _RTHP-W-COUNT @ _RTHP-W-DOC-RECORD-COUNT @ <> IF 0 EXIT THEN
            _RTHP-W-TEXT @ _RTHP-W-DOC-TEXT-U @ <> IF 0 EXIT THEN
            _RTHP-W-TOTAL @ _RTHP-W-COUNT @ _RTHP-U32+?
                0= IF DROP 0 EXIT THEN
            DUP _RTHP-W-P @ _RTHP.MAX-RECORDS @ U> IF DROP 0 EXIT THEN
                _RTHP-W-TOTAL !
            _RTHP-W-LAST @ 1 _RTHP-U+? 0= IF DROP 0 EXIT THEN
                DUP 0= IF DROP 0 EXIT THEN _RTHP-W-NEXT-ID !
          THEN
        THEN
        1 _RTHP-W-DOCUMENT-I +!
    REPEAT
    _RTHP-W-COPIED-COMPLETE? 0= IF 0 EXIT THEN
    _RTHP-W-TOTAL @ _RTHP-W-P @ _RTHP.SOURCE-USED @
        UMSN-RECORD-SIZE / <> IF 0 EXIT THEN
    _RTHP-W-TOTAL @ DUP _RTHP-W-P @ _RTHP.MENU-CONTROL-COUNT !
        _RTHP-W-P @ _RTHP.CONTROL-COUNT !
    0 _RTHP-W-P @ _RTHP.COLLECTION-COUNT !
    0 _RTHP-W-P @ _RTHP.COLLECTION-ITEMS !
    0 _RTHP-W-P @ _RTHP.COLLECTION-UTF8 !
    _RTHP-W-NEXT-ID @ _RTHP-W-GLYPH-FIRST !
    -1 ;

VARIABLE _RTHP-W-COLLECTION-I
VARIABLE _RTHP-W-DESCRIPTOR
VARIABLE _RTHP-W-ENTRY
VARIABLE _RTHP-W-ENTRY-U
VARIABLE _RTHP-W-CONTENT-A
VARIABLE _RTHP-W-CONTENT-U
VARIABLE _RTHP-W-CONTENT-CURSOR
VARIABLE _RTHP-W-CONTENT-CAP
VARIABLE _RTHP-W-CONTROL
VARIABLE _RTHP-W-CORRELATION
VARIABLE _RTHP-W-KIND
VARIABLE _RTHP-W-STATE
VARIABLE _RTHP-W-ROW
VARIABLE _RTHP-W-COL
VARIABLE _RTHP-W-HEIGHT
VARIABLE _RTHP-W-WIDTH
VARIABLE _RTHP-W-COLLECTIONS
VARIABLE _RTHP-W-CONTENT-ITEMS
VARIABLE _RTHP-W-CONTENT-UTF8
VARIABLE _RTHP-W-CLAIM
VARIABLE _RTHP-W-ROW-END
VARIABLE _RTHP-W-COL-END
VARIABLE _RTHP-W-PRIOR-ROW-END
VARIABLE _RTHP-W-PRIOR-COL-END
VARIABLE _RTHP-W-PRIOR-CONTROL
VARIABLE _RTHP-W-PRIOR-CORRELATION
VARIABLE _RTHP-W-TAB-ROOT-ID
VARIABLE _RTHP-W-TAB
VARIABLE _RTHP-W-TAB-I
VARIABLE _RTHP-W-TAB-COUNT
VARIABLE _RTHP-W-TAB-LABEL-A
VARIABLE _RTHP-W-TAB-LABEL-U
VARIABLE _RTHP-W-TAB-SHORTCUT-A
VARIABLE _RTHP-W-TAB-SHORTCUT-U
VARIABLE _RTHP-W-TAB-UTF8
VARIABLE _RTHP-W-TAB-END
VARIABLE _RTHP-W-COPY-A
VARIABLE _RTHP-W-COPY-U
VARIABLE _RTHP-W-COPY-DST
VARIABLE _RTHP-W-COPY-END

: _RTHP-W-USCOL>RTE  ( uscol-status -- rte-status )
    DUP USCOL-S-OK = IF DROP RTE-S-OK EXIT THEN
    DUP USCOL-S-CAPACITY = IF DROP RTE-S-CAPACITY EXIT THEN
    DUP USCOL-S-UNSUPPORTED = OVER USCOL-S-UNAVAILABLE = OR IF
        DROP RTE-S-UNAVAILABLE EXIT
    THEN
    DROP RTE-S-INVALID ;

: _RTHP-USCOL-FAMILY>CONTROL-KIND  ( uscol-family -- rte-kind|0 )
    DUP USCOL-F-TEXT-AREA = IF
        DROP RTE-CONTROL-TEXT-AREA EXIT
    THEN
    DUP USCOL-F-TEXT-GRID = IF
        DROP RTE-CONTROL-TEXT-GRID EXIT
    THEN
    DUP USCOL-F-ITEM-VIEW = IF
        DROP RTE-CONTROL-ITEM-VIEW EXIT
    THEN
    DUP USCOL-F-DOCUMENT = IF
        DROP RTE-CONTROL-DOCUMENT EXIT
    THEN
    USCOL-F-TABSET = IF RTE-CONTROL-TABSET ELSE 0 THEN ;

: _RTHP-USCOL-FAMILY-FIXED-SIZE  ( uscol-family -- bytes|0 )
    DUP USCOL-F-TEXT-AREA =
    OVER USCOL-F-TEXT-GRID = OR IF
        DROP USCOL-TEXT-FIXED-SIZE EXIT
    THEN
    DUP USCOL-F-ITEM-VIEW = IF DROP USCOL-IV-FIXED-SIZE EXIT THEN
    DUP USCOL-F-DOCUMENT = IF DROP USCOL-DOC-FIXED-SIZE EXIT THEN
    USCOL-F-TABSET = IF USCOL-TABSET-FIXED-SIZE ELSE 0 THEN ;

: _RTHP-W-USCOL-STATE>RTE  ( uscol-state -- rte-state )
    0 SWAP
    DUP USCOL-STATE-VISIBLE AND IF SWAP RTE-CONTROL-VISIBLE OR SWAP THEN
    DUP USCOL-STATE-ENABLED AND IF SWAP RTE-CONTROL-ENABLED OR SWAP THEN
    USCOL-STATE-SELECTED AND IF RTE-CONTROL-SELECTED OR THEN ;

: _RTHP-W-COLLECTION-GEOMETRY?  ( -- flag )
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-ROW@ DUP _RTHP-W-ROW !
        0< IF 0 EXIT THEN
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-COLUMN@ DUP _RTHP-W-COL !
        0< IF 0 EXIT THEN
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-HEIGHT@ DUP _RTHP-W-HEIGHT !
        0> 0= IF 0 EXIT THEN
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-WIDTH@ DUP _RTHP-W-WIDTH !
        0> 0= IF 0 EXIT THEN
    _RTHP-W-ROW @ _RTHP-W-HEIGHT @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-W-ROW-END !
    _RTHP-W-P @ _RTHP.ROWS @ U> IF 0 EXIT THEN
    _RTHP-W-COL @ _RTHP-W-WIDTH @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-W-COL-END !
    _RTHP-W-P @ _RTHP.COLS @ U> IF 0 EXIT THEN
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-CLIP-ROW@ _RTHP-W-ROW @ =
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-CLIP-COLUMN@
        _RTHP-W-COL @ = AND
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-CLIP-HEIGHT@
        _RTHP-W-HEIGHT @ = AND
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-CLIP-WIDTH@
        _RTHP-W-WIDTH @ = AND ;

: _RTHP-W-COLLECTION-ENTRY?  ( -- flag )
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-SOURCE@
        UCSN-SOURCE-UIDL <> IF 0 EXIT THEN
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-SOURCE-INDEX@ 0< IF 0 EXIT THEN
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-SOURCE-GENERATION@ 0< IF
        0 EXIT
    THEN
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-ROOT-KEY@ 0= IF 0 EXIT THEN
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-ENTRY-BYTES@
        DUP _RTHP-W-ENTRY-U ! USCOL-ENTRY-HEADER-SIZE U< IF 0 EXIT THEN
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-NATIVE-OFFSET@
        DUP 0< IF DROP 0 EXIT THEN
    DUP _RTHP-W-DOC-NATIVE-U @ U> IF DROP 0 EXIT THEN
    _RTHP-W-ENTRY-U @ _RTHP-W-DOC-NATIVE-U @ ROT - U> IF 0 EXIT THEN
    _RTHP-W-P @ _RTHP.COLLECTION-NATIVE-A @
        _RTHP-W-DOC-NATIVE-O @ +
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-NATIVE-OFFSET@ +
        DUP _RTHP-W-ENTRY !
    _RTHP-W-ENTRY-U @ MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    _RTHP-W-ENTRY @ USCOL-ENTRY-BYTES@ _RTHP-W-ENTRY-U @ <> IF 0 EXIT THEN
    _RTHP-W-ENTRY @ USCOL-ENTRY-FAMILY-ABI@
        USCOL-FAMILY-ABI <> IF 0 EXIT THEN
    _RTHP-W-ENTRY @ USCOL-ENTRY-FAMILY@
        DUP _RTHP-USCOL-FAMILY-FIXED-SIZE DUP 0= IF 2DROP 0 EXIT THEN
        _RTHP-W-ENTRY-U @ U> IF DROP 0 EXIT THEN
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-FAMILY@ <> IF 0 EXIT THEN
    _RTHP-W-ENTRY @ USCOL-ENTRY-KEY@
        _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-ROOT-KEY@ <> IF 0 EXIT THEN
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-SUMMARY DUP
        USCOL-SUMMARY-FAMILY@
        _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-FAMILY@ <> IF DROP 0 EXIT THEN
    DUP USCOL-SUMMARY-ROOT-KEY@
        _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-ROOT-KEY@ <> IF DROP 0 EXIT THEN
    USCOL-SUMMARY-ENTRY-BYTES@ _RTHP-W-ENTRY-U @ <> IF 0 EXIT THEN
    _RTHP-W-ENTRY @ USCOL-ROOT-HEIGHT@ _RTHP-W-HEIGHT @ <>
    _RTHP-W-ENTRY @ USCOL-ROOT-WIDTH@ _RTHP-W-WIDTH @ <> OR 0= ;

\ Mounted roots currently inherit their containing UIDL source's resolved z,
\ while canonical root-key order carries identity rather than nested paint
\ order.  Until ordinary draw observation freezes a relative paint ordinal,
\ two already-supported mounted roots at the same z may not overlap.  This
\ check runs during collection lowering, before either menu or collection
\ claims are emitted; refusal therefore returns through the menu-only path.
: _RTHP-W-COLLECTION-NONOVERLAPPING?  ( -- flag )
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-SOURCE-GENERATION@ 0= IF
        -1 EXIT
    THEN
    _RTHP-W-TOTAL @ _RTHP-W-P @ _RTHP.MENU-CONTROL-COUNT @ ?DO
        _RTHP-W-P @ _RTHP.CORR-A @ I RUCP-CORRELATION-SIZE * +
            DUP _RTHP-W-PRIOR-CORRELATION !
        RUCP-CORRELATION-LIFECYCLE-GENERATION@ IF
            _RTHP-W-P @ _RTHP.CONTROLS-A @ I RTE-CONTROL-SIZE * +
                DUP _RTHP-W-PRIOR-CONTROL !
            DUP _RTE-CONTROL.KIND @ _RTHP-COLLECTION-ROOT-KIND? IF
            _RTE-CONTROL.Z @
                _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-Z@ = IF
                _RTHP-W-PRIOR-CONTROL @ _RTE-CONTROL.ROW @
                _RTHP-W-PRIOR-CONTROL @ _RTE-CONTROL.HEIGHT @
                    _RTHP-U32+? 0= IF DROP 0 UNLOOP EXIT THEN
                    _RTHP-W-PRIOR-ROW-END !
                _RTHP-W-PRIOR-CONTROL @ _RTE-CONTROL.COL @
                _RTHP-W-PRIOR-CONTROL @ _RTE-CONTROL.WIDTH @
                    _RTHP-U32+? 0= IF DROP 0 UNLOOP EXIT THEN
                    _RTHP-W-PRIOR-COL-END !
                _RTHP-W-ROW @ _RTHP-W-PRIOR-ROW-END @ U<
                _RTHP-W-PRIOR-CONTROL @ _RTE-CONTROL.ROW @
                    _RTHP-W-ROW-END @ U< AND
                _RTHP-W-COL @ _RTHP-W-PRIOR-COL-END @ U< AND
                _RTHP-W-PRIOR-CONTROL @ _RTE-CONTROL.COL @
                    _RTHP-W-COL-END @ U< AND IF
                    0 UNLOOP EXIT
                THEN
            THEN
            ELSE DROP THEN
        THEN
    LOOP
    -1 ;

: _RTHP-W-COLLECTION-OUTPUT?  ( -- flag )
    _RTHP-W-TOTAL @ _RTHP-W-P @ _RTHP.MAX-CONTROLS @ U< 0= IF 0 EXIT THEN
    _RTHP-W-TOTAL @ RTE-CONTROL-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN
    DUP RTE-CONTROL-SIZE _RTHP-U32+? 0= IF 2DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.CONTROLS-U @ U> IF DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.CONTROLS-A @ + DUP _RTHP-W-CONTROL !
        RTE-CONTROL-SIZE 0 FILL
    _RTHP-W-TOTAL @ RUCP-CORRELATION-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN
    DUP RUCP-CORRELATION-SIZE _RTHP-U32+? 0= IF 2DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.CORR-U @ U> IF DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.CORR-A @ + DUP _RTHP-W-CORRELATION !
        RUCP-CORRELATION-SIZE 0 FILL
    -1 ;

\ An item view's content is ITM1, a document's DOC1, and a text root's
\ STX1.
: _RTHP-W-ITEM-VIEW?  ( -- flag )  _RTHP-W-KIND @ RTE-CONTROL-ITEM-VIEW = ;
: _RTHP-W-DOCUMENT?   ( -- flag )  _RTHP-W-KIND @ RTE-CONTROL-DOCUMENT = ;

: _RTHP-W-COLLECTION-CONTENT  ( -- rte-status )
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-SUMMARY
    _RTHP-W-ITEM-VIEW? IF
        USCOL-SUMMARY-ITM1-BYTES
    ELSE _RTHP-W-DOCUMENT? IF
        USCOL-SUMMARY-DOC1-BYTES
    ELSE
        USCOL-SUMMARY-STX1-BYTES
    THEN THEN
    DUP USCOL-S-OK <> IF NIP _RTHP-W-USCOL>RTE EXIT THEN
    DROP DUP _RTHP-W-CONTENT-U ! DROP
    _RTHP-W-CONTENT-CURSOR @ _RTHP-W-CONTENT-U @ _RTHP-U32+?
        0= IF DROP RTE-S-CAPACITY EXIT THEN
    _RTHP-W-P @ _RTHP.SOURCE-TEXT-U @ U> IF
        DROP RTE-S-CAPACITY EXIT
    THEN
    _RTHP-W-P @ _RTHP.SOURCE-TEXT-A @
        _RTHP-W-CONTENT-CURSOR @ + DUP _RTHP-W-CONTENT-A !
    _RTHP-W-P @ _RTHP.SOURCE-TEXT-U @ _RTHP-W-CONTENT-CURSOR @ -
        _RTHP-W-CONTENT-CAP !
    _RTHP-W-ENTRY @ _RTHP-W-ENTRY-U @
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-SUMMARY
    _RTHP-W-P @ _RTHP.SOURCE-CONTENT-EPOCH @
    _RTHP-W-CONTENT-A @ _RTHP-W-CONTENT-CAP @
    _RTHP-W-ITEM-VIEW? IF USITM-PACK ELSE
        _RTHP-W-DOCUMENT? IF USDOC-PACK ELSE USSTX-PACK THEN
    THEN
    _RTHP-W-STATUS ! _RTHP-W-COUNT !
    _RTHP-W-STATUS @ USCOL-S-OK <> IF
        _RTHP-W-STATUS @ _RTHP-W-USCOL>RTE EXIT
    THEN
    _RTHP-W-COUNT @ _RTHP-W-CONTENT-U @ <> IF RTE-S-INVALID EXIT THEN
    _RTHP-W-CONTENT-CURSOR @ _RTHP-W-CONTENT-U @ +
        _RTHP-W-CONTENT-CURSOR !
    RTE-S-OK ;

\ The frozen native entry has already passed deep collection validation.
\ Typed grid roles require their own negotiated capability; omit that whole
\ root before allocating output, IDs or paint claims so its ordinary cells
\ remain available to the residual producer.  Plain grids still lower.
: _RTHP-W-COLLECTION-SUPPORTED?  ( -- flag )
    _RTHP-W-KIND @ RTE-CONTROL-TEXT-GRID <> IF -1 EXIT THEN
    _RTHP-W-P @ _RTHP.LIMITS RTE-LIMITS-FEATURES@
        RTE-F-GRID-CELLS AND IF -1 EXIT THEN
    _RTHP-W-ENTRY @ USCOL-TEXT-GRID-TYPED? 0= ;

: _RTHP-W-WRITE-TEXT-COLLECTION  ( -- rte-status )
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-FAMILY@
        _RTHP-USCOL-FAMILY>CONTROL-KIND
        DUP 0= IF DROP RTE-S-INVALID EXIT THEN _RTHP-W-KIND !
    _RTHP-W-COLLECTION-GEOMETRY? 0= IF RTE-S-UNAVAILABLE EXIT THEN
    _RTHP-W-COLLECTION-ENTRY? 0= IF RTE-S-INVALID EXIT THEN
    _RTHP-W-COLLECTION-SUPPORTED? 0= IF RTE-S-OK EXIT THEN
    _RTHP-W-COLLECTION-NONOVERLAPPING? 0= IF RTE-S-UNAVAILABLE EXIT THEN
    _RTHP-W-COLLECTION-OUTPUT? 0= IF RTE-S-CAPACITY EXIT THEN
    _RTHP-W-COLLECTION-CONTENT DUP RTE-S-OK <> IF EXIT THEN DROP
    _RTHP-W-ENTRY @ USCOL-ROOT-STATE@ _RTHP-W-USCOL-STATE>RTE
        _RTHP-W-STATE !

    _RTHP-W-P @ _RTHP.OWNER @ _RTHP-W-CONTROL @ _RTE-CONTROL.OWNER !
    _RTHP-W-P @ _RTHP.OWNER-GEN @
        _RTHP-W-CONTROL @ _RTE-CONTROL.GENERATION !
    _RTHP-W-NEXT-ID @ _RTHP-W-CONTROL @ _RTE-CONTROL.ID !
    _RTHP-W-KIND @ _RTHP-W-CONTROL @ _RTE-CONTROL.KIND !
    _RTHP-W-STATE @ _RTHP-W-CONTROL @ _RTE-CONTROL.STATE !
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-Z@
        _RTHP-W-CONTROL @ _RTE-CONTROL.Z !
    _RTHP-W-P @ _RTHP.REGION @ _RTHP-W-CONTROL @ _RTE-CONTROL.REGION !
    _RTHP-W-ROW @ _RTHP-W-CONTROL @ _RTE-CONTROL.ROW !
    _RTHP-W-COL @ _RTHP-W-CONTROL @ _RTE-CONTROL.COL !
    _RTHP-W-HEIGHT @ _RTHP-W-CONTROL @ _RTE-CONTROL.HEIGHT !
    _RTHP-W-WIDTH @ _RTHP-W-CONTROL @ _RTE-CONTROL.WIDTH !
    _RTHP-W-P @ _RTHP.ROWS @
        _RTHP-W-CONTROL @ _RTE-CONTROL.ROOT-HEIGHT !
    _RTHP-W-P @ _RTHP.COLS @
        _RTHP-W-CONTROL @ _RTE-CONTROL.ROOT-WIDTH !
    _RTHP-W-CONTENT-A @ _RTHP-W-CONTROL @ _RTE-CONTROL.CONTENT-A !
    _RTHP-W-CONTENT-U @ _RTHP-W-CONTROL @ _RTE-CONTROL.CONTENT-U !
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-SUMMARY
        USCOL-SUMMARY-ITEM-COUNT@
        DUP _RTHP-W-CONTROL @ _RTE-CONTROL.CONTENT-ITEMS !
        _RTHP-W-CONTENT-ITEMS @ SWAP _RTHP-U32+?
        0= IF DROP RTE-S-CAPACITY EXIT THEN _RTHP-W-CONTENT-ITEMS !
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-SUMMARY
        USCOL-SUMMARY-UTF8-BYTES@
        DUP _RTHP-W-CONTROL @ _RTE-CONTROL.CONTENT-UTF8 !
        _RTHP-W-CONTENT-UTF8 @ SWAP _RTHP-U32+?
        0= IF DROP RTE-S-CAPACITY EXIT THEN _RTHP-W-CONTENT-UTF8 !
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-SUMMARY
        USCOL-SUMMARY-RUN-COUNT@
        _RTHP-W-CONTROL @ _RTE-CONTROL.CONTENT-RUNS !
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-SUMMARY
        USCOL-SUMMARY-FIELD-COUNT@
        _RTHP-W-CONTROL @ _RTE-CONTROL.CONTENT-FIELDS !

    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-TOKEN@
        _RTHP-W-CORRELATION @ _RUCP-X.ATTACHMENT !
    UMSN-SOURCE-UIDL _RTHP-W-CORRELATION @ _RUCP-X.SOURCE !
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-SOURCE-INDEX@
        _RTHP-W-CORRELATION @ _RUCP-X.INDEX !
    0 _RTHP-W-CORRELATION @ _RUCP-X.SCOPE !
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-ROOT-KEY@
        _RTHP-W-CORRELATION @ _RUCP-X.SUBKEY !
    _RTHP-W-NEXT-ID @ _RTHP-W-CORRELATION @ _RUCP-X.CONTROL-ID !
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-SOURCE-GENERATION@
        _RTHP-W-CORRELATION @ _RUCP-X.LIFECYCLE-GENERATION !

    _RTHP-W-TOTAL @ 1 _RTHP-U32+? 0= IF DROP RTE-S-CAPACITY EXIT THEN
        _RTHP-W-TOTAL !
    _RTHP-W-COLLECTIONS @ 1 _RTHP-U32+? 0= IF
        DROP RTE-S-CAPACITY EXIT
    THEN DUP _RTHP-W-P @ _RTHP.MAX-COLLECTIONS @ U> IF
        DROP RTE-S-CAPACITY EXIT
    THEN _RTHP-W-COLLECTIONS !
    _RTHP-W-NEXT-ID @ 1 _RTHP-U+? 0= IF DROP RTE-S-CAPACITY EXIT THEN
        DUP 0= IF DROP RTE-S-CAPACITY EXIT THEN _RTHP-W-NEXT-ID !
    RTE-S-OK ;

\ Copy a TAB label or optional shortcut out of the frozen native entry and
\ into the producer's caller-owned SOURCE-TEXT bank.  Packed ACK baselines can
\ consequently rebase every CONTROL string without borrowing collection
\ snapshot storage.  Canonical empty strings retain the engine's 0/0 shape.
: _RTHP-W-COPY-TAB-TEXT  ( source-a source-u -- destination-a status )
    _RTHP-W-COPY-U ! _RTHP-W-COPY-A !
    _RTHP-W-COPY-U @ 0= IF 0 RTE-S-OK EXIT THEN
    _RTHP-W-COPY-A @ _RTHP-W-COPY-U @ MSPAN-NONWRAPPING? 0= IF
        0 RTE-S-INVALID EXIT
    THEN
    _RTHP-W-CONTENT-CURSOR @ _RTHP-W-COPY-U @ _RTHP-U32+?
        0= IF DROP 0 RTE-S-CAPACITY EXIT THEN
    DUP _RTHP-W-P @ _RTHP.SOURCE-TEXT-U @ U> IF
        DROP 0 RTE-S-CAPACITY EXIT
    THEN _RTHP-W-COPY-END !
    _RTHP-W-P @ _RTHP.SOURCE-TEXT-A @
        _RTHP-W-CONTENT-CURSOR @ + _RTHP-W-COPY-DST !
    _RTHP-W-COPY-A @ _RTHP-W-COPY-DST @ _RTHP-W-COPY-U @ MOVE
    _RTHP-W-COPY-END @ _RTHP-W-CONTENT-CURSOR !
    _RTHP-W-COPY-DST @ RTE-S-OK ;

: _RTHP-W-TAB-CORRELATION!  ( semantic-subkey semantic-scope -- )
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-TOKEN@
        _RTHP-W-CORRELATION @ _RUCP-X.ATTACHMENT !
    UMSN-SOURCE-UIDL _RTHP-W-CORRELATION @ _RUCP-X.SOURCE !
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-SOURCE-INDEX@
        _RTHP-W-CORRELATION @ _RUCP-X.INDEX !
    _RTHP-W-CORRELATION @ _RUCP-X.SCOPE !
    _RTHP-W-CORRELATION @ _RUCP-X.SUBKEY !
    _RTHP-W-NEXT-ID @ _RTHP-W-CORRELATION @ _RUCP-X.CONTROL-ID !
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-SOURCE-GENERATION@
        _RTHP-W-CORRELATION @ _RUCP-X.LIFECYCLE-GENERATION ! ;

: _RTHP-W-COMMIT-COLLECTION-CONTROL  ( -- rte-status )
    _RTHP-W-TOTAL @ 1 _RTHP-U32+? 0= IF DROP RTE-S-CAPACITY EXIT THEN
    DUP _RTHP-W-P @ _RTHP.MAX-CONTROLS @ U> IF
        DROP RTE-S-CAPACITY EXIT
    THEN _RTHP-W-TOTAL !
    _RTHP-W-COLLECTIONS @ 1 _RTHP-U32+? 0= IF
        DROP RTE-S-CAPACITY EXIT
    THEN DUP _RTHP-W-P @ _RTHP.MAX-COLLECTIONS @ U> IF
        DROP RTE-S-CAPACITY EXIT
    THEN _RTHP-W-COLLECTIONS !
    _RTHP-W-NEXT-ID @ 1 _RTHP-U+? 0= IF DROP RTE-S-CAPACITY EXIT THEN
    DUP 0= IF DROP RTE-S-CAPACITY EXIT THEN _RTHP-W-NEXT-ID !
    RTE-S-OK ;

: _RTHP-W-TAB-COMMON!  ( -- )
    _RTHP-W-P @ _RTHP.OWNER @ _RTHP-W-CONTROL @ _RTE-CONTROL.OWNER !
    _RTHP-W-P @ _RTHP.OWNER-GEN @
        _RTHP-W-CONTROL @ _RTE-CONTROL.GENERATION !
    _RTHP-W-NEXT-ID @ _RTHP-W-CONTROL @ _RTE-CONTROL.ID !
    _RTHP-W-P @ _RTHP.REGION @ _RTHP-W-CONTROL @ _RTE-CONTROL.REGION !
    _RTHP-W-P @ _RTHP.ROWS @
        _RTHP-W-CONTROL @ _RTE-CONTROL.ROOT-HEIGHT !
    _RTHP-W-P @ _RTHP.COLS @
        _RTHP-W-CONTROL @ _RTE-CONTROL.ROOT-WIDTH ! ;

: _RTHP-W-WRITE-TABSET-ROOT  ( -- rte-status )
    _RTHP-W-COLLECTION-OUTPUT? 0= IF RTE-S-CAPACITY EXIT THEN
    _RTHP-W-TAB-COMMON!
    _RTHP-W-NEXT-ID @ _RTHP-W-TAB-ROOT-ID !
    RTE-CONTROL-TABSET _RTHP-W-CONTROL @ _RTE-CONTROL.KIND !
    _RTHP-W-ENTRY @ USCOL-ROOT-STATE@ _RTHP-W-USCOL-STATE>RTE
        _RTHP-W-CONTROL @ _RTE-CONTROL.STATE !
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-Z@
        _RTHP-W-CONTROL @ _RTE-CONTROL.Z !
    _RTHP-W-ROW @ _RTHP-W-CONTROL @ _RTE-CONTROL.ROW !
    _RTHP-W-COL @ _RTHP-W-CONTROL @ _RTE-CONTROL.COL !
    _RTHP-W-HEIGHT @ _RTHP-W-CONTROL @ _RTE-CONTROL.HEIGHT !
    _RTHP-W-WIDTH @ _RTHP-W-CONTROL @ _RTE-CONTROL.WIDTH !
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-ROOT-KEY@ 0
        _RTHP-W-TAB-CORRELATION!
    _RTHP-W-COMMIT-COLLECTION-CONTROL ;

: _RTHP-W-WRITE-TAB  ( -- rte-status )
    _RTHP-W-TAB @ USCOL-TAB-LABEL@ _RTHP-W-COPY-TAB-TEXT
        DUP RTE-S-OK <> IF NIP EXIT THEN DROP _RTHP-W-TAB-LABEL-A !
    _RTHP-W-TAB @ USCOL-TAB-LABEL-BYTES@ _RTHP-W-TAB-LABEL-U !
    _RTHP-W-TAB @ USCOL-TAB-SHORTCUT@ _RTHP-W-COPY-TAB-TEXT
        DUP RTE-S-OK <> IF NIP EXIT THEN DROP _RTHP-W-TAB-SHORTCUT-A !
    _RTHP-W-TAB @ USCOL-TAB-SHORTCUT-BYTES@ _RTHP-W-TAB-SHORTCUT-U !
    _RTHP-W-TAB-LABEL-U @ _RTHP-W-TAB-SHORTCUT-U @ _RTHP-U32+?
        0= IF DROP RTE-S-CAPACITY EXIT THEN
    _RTHP-W-TAB-UTF8 @ SWAP _RTHP-U32+? 0= IF
        DROP RTE-S-CAPACITY EXIT
    THEN _RTHP-W-TAB-UTF8 !

    _RTHP-W-COLLECTION-OUTPUT? 0= IF RTE-S-CAPACITY EXIT THEN
    _RTHP-W-TAB-COMMON!
    RTE-CONTROL-TAB _RTHP-W-CONTROL @ _RTE-CONTROL.KIND !
    _RTHP-W-TAB @ USCOL-TAB-STATE@ _RTHP-W-USCOL-STATE>RTE
        _RTHP-W-CONTROL @ _RTE-CONTROL.STATE !
    _RTHP-W-TAB-ROOT-ID @ _RTHP-W-CONTROL @ _RTE-CONTROL.PARENT !
    _RTHP-W-TAB @ USCOL-TAB-ORDER@
        _RTHP-W-CONTROL @ _RTE-CONTROL.ORDER !
    _RTHP-W-TAB-LABEL-A @ _RTHP-W-CONTROL @ _RTE-CONTROL.LABEL-A !
    _RTHP-W-TAB-LABEL-U @ _RTHP-W-CONTROL @ _RTE-CONTROL.LABEL-U !
    _RTHP-W-TAB-SHORTCUT-A @
        _RTHP-W-CONTROL @ _RTE-CONTROL.SHORTCUT-A !
    _RTHP-W-TAB-SHORTCUT-U @
        _RTHP-W-CONTROL @ _RTE-CONTROL.SHORTCUT-U !
    _RTHP-W-TAB @ USCOL-TAB-KEY@
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-ROOT-KEY@
        _RTHP-W-TAB-CORRELATION!
    _RTHP-W-COMMIT-COLLECTION-CONTROL ;

: _RTHP-W-WRITE-TABSET  ( -- rte-status )
    _RTHP-W-ENTRY @ USCOL-TABSET-COUNT@ DUP _RTHP-W-TAB-COUNT !
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-SUMMARY
        USCOL-SUMMARY-CHILD-COUNT@ <> IF RTE-S-INVALID EXIT THEN
    _RTHP-W-WRITE-TABSET-ROOT DUP RTE-S-OK <> IF EXIT THEN DROP
    _RTHP-W-ENTRY @ USCOL-TABSET-FIRST _RTHP-W-TAB !
    _RTHP-W-ENTRY @ _RTHP-W-ENTRY-U @ + _RTHP-W-TAB-END !
    0 _RTHP-W-TAB-I ! 0 _RTHP-W-TAB-UTF8 !
    BEGIN _RTHP-W-TAB-I @ _RTHP-W-TAB-COUNT @ U< WHILE
        _RTHP-W-TAB @ USCOL-TAB-HEADER-SIZE _RTHP-U+?
            0= IF DROP RTE-S-INVALID EXIT THEN
        _RTHP-W-TAB-END @ U> IF RTE-S-INVALID EXIT THEN
        _RTHP-W-TAB @ USCOL-TAB-LABEL-BYTES@
        _RTHP-W-TAB @ USCOL-TAB-SHORTCUT-BYTES@ USCOL-TAB-BYTES
            DUP 0= IF DROP RTE-S-INVALID EXIT THEN
        _RTHP-W-TAB @ SWAP _RTHP-U+? 0= IF
            DROP RTE-S-INVALID EXIT
        THEN DUP _RTHP-W-TAB-END @ U> IF DROP RTE-S-INVALID EXIT THEN
        DROP
        _RTHP-W-WRITE-TAB DUP RTE-S-OK <> IF EXIT THEN DROP
        _RTHP-W-TAB @ USCOL-TAB-NEXT _RTHP-W-TAB !
        1 _RTHP-W-TAB-I +!
    REPEAT
    _RTHP-W-TAB @ _RTHP-W-TAB-END @ <> IF RTE-S-INVALID EXIT THEN
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-SUMMARY
        USCOL-SUMMARY-UTF8-BYTES@ _RTHP-W-TAB-UTF8 @ <> IF
        RTE-S-INVALID EXIT
    THEN
    _RTHP-W-CONTENT-UTF8 @ _RTHP-W-TAB-UTF8 @ _RTHP-U32+?
        0= IF DROP RTE-S-CAPACITY EXIT THEN _RTHP-W-CONTENT-UTF8 !
    RTE-S-OK ;

: _RTHP-W-WRITE-COLLECTION  ( -- rte-status )
    _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-FAMILY@
        DUP _RTHP-USCOL-FAMILY>CONTROL-KIND 0= IF
        DROP RTE-S-INVALID EXIT
    THEN
    USCOL-F-TABSET <> IF _RTHP-W-WRITE-TEXT-COLLECTION EXIT THEN
    _RTHP-W-COLLECTION-GEOMETRY? 0= IF RTE-S-UNAVAILABLE EXIT THEN
    _RTHP-W-COLLECTION-ENTRY? 0= IF RTE-S-INVALID EXIT THEN
    _RTHP-W-COLLECTION-NONOVERLAPPING? 0= IF RTE-S-UNAVAILABLE EXIT THEN
    _RTHP-W-WRITE-TABSET ;

\ An item view becomes a control only when the terminal negotiated item
\ views, and a document only when it negotiated documents; otherwise each
\ stays on the residual path with the rest of its widget's cells, and text
\ collections still lower.
: _RTHP-W-LOWERS-FAMILY?  ( uscol-family -- flag )
    DUP _RTHP-USCOL-FAMILY>CONTROL-KIND 0= IF DROP 0 EXIT THEN
    DUP USCOL-F-ITEM-VIEW = IF
        DROP _RTHP-W-P @ _RTHP.LIMITS RTE-LIMITS-FEATURES@
            RTE-F-CONTROL-ITEMS AND 0<> EXIT
    THEN
    USCOL-F-DOCUMENT <> IF -1 EXIT THEN
    _RTHP-W-P @ _RTHP.LIMITS RTE-LIMITS-FEATURES@
        RTE-F-CONTROL-DOCUMENTS AND 0<> ;

: _RTHP-W-LOWER-COLLECTIONS  ( -- rte-status )
    _RTHP-W-P @ _RTHP.SOURCE-MENU-TEXT-USED @ _RTHP-W-CONTENT-CURSOR !
    0 _RTHP-W-COLLECTIONS ! 0 _RTHP-W-CONTENT-ITEMS !
    0 _RTHP-W-CONTENT-UTF8 !
    _RTHP-W-COPIED-BEGIN
    BEGIN _RTHP-W-DOCUMENT-I @ _RTHP-W-P @ _RTHP.DOCUMENT-COUNT @ U< WHILE
        _RTHP-W-COPIED-DOCUMENT? 0= IF RTE-S-INVALID EXIT THEN
        0 _RTHP-W-COLLECTION-I !
        BEGIN _RTHP-W-COLLECTION-I @
            _RTHP-W-DOC-COLLECTION-COUNT @ U< WHILE
            _RTHP-W-P @ _RTHP.COLLECTION-DESCRIPTORS-A @
            _RTHP-W-DOC-DESCRIPTOR-O @ +
            _RTHP-W-COLLECTION-I @ UCSN-DESCRIPTOR-SIZE * +
                _RTHP-W-DESCRIPTOR !
            _RTHP-W-DESCRIPTOR @ UCSN-DESCRIPTOR-FAMILY@
                _RTHP-W-LOWERS-FAMILY? IF
                _RTHP-W-WRITE-COLLECTION DUP RTE-S-OK <> IF EXIT THEN DROP
            THEN
            1 _RTHP-W-COLLECTION-I +!
        REPEAT
        1 _RTHP-W-DOCUMENT-I +!
    REPEAT
    _RTHP-W-COPIED-COMPLETE? 0= IF RTE-S-INVALID EXIT THEN
    _RTHP-W-CONTENT-CURSOR @ _RTHP-W-P @ _RTHP.SOURCE-TEXT-USED !
    _RTHP-W-TOTAL @ _RTHP-W-P @ _RTHP.CONTROL-COUNT !
    _RTHP-W-COLLECTIONS @ _RTHP-W-P @ _RTHP.COLLECTION-COUNT !
    _RTHP-W-CONTENT-ITEMS @ _RTHP-W-P @ _RTHP.COLLECTION-ITEMS !
    _RTHP-W-CONTENT-UTF8 @ _RTHP-W-P @ _RTHP.COLLECTION-UTF8 !
    _RTHP-W-NEXT-ID @ _RTHP-W-GLYPH-FIRST !
    RTE-S-OK ;

: _RTHP-W-STRIP-COLLECTIONS?  ( -- flag )
    _RTHP-W-P @ _RTHP.MENU-CONTROL-COUNT @ DUP _RTHP-W-TOTAL !
        _RTHP-W-P @ _RTHP.CONTROL-COUNT !
    _RTHP-W-P @ _RTHP.SOURCE-MENU-TEXT-USED @
        _RTHP-W-P @ _RTHP.SOURCE-TEXT-USED !
    0 _RTHP-W-P @ _RTHP.COLLECTION-COUNT !
    0 _RTHP-W-P @ _RTHP.COLLECTION-ITEMS !
    0 _RTHP-W-P @ _RTHP.COLLECTION-UTF8 !
    _RTHP-W-P @ _RTHP.FIRST-OBJECT @ _RTHP-W-TOTAL @ _RTHP-U+?
        0= IF DROP 0 EXIT THEN
    DUP 0= IF DROP 0 EXIT THEN DUP _RTHP-W-NEXT-ID !
        _RTHP-W-GLYPH-FIRST !
    _RTHP-W-WRAP-CONTROL-PLAN? ;

\ The producer writes every CONTROL and borrowed byte into its own bounded
\ banks.  Wrap that internal result here; the mandatory hybrid preflight is
\ the one semantic and provider-admission pass before any owner is opened.
: _RTHP-BUILD-CONTROLS  ( producer -- rte-status )
    DUP _RTHP-W-P ! _RTHP-BUILD-MENU-CONTROLS? 0= IF
        RTE-S-INVALID EXIT
    THEN
    _RTHP-W-LOWER-COLLECTIONS DUP RTE-S-OK <> IF
        DUP RTE-S-CAPACITY = OVER RTE-S-UNAVAILABLE = OR IF
            DROP _RTHP-W-STRIP-COLLECTIONS? 0= IF RTE-S-INVALID EXIT THEN
            RTE-S-OK EXIT
        THEN
        EXIT
    THEN DROP
    _RTHP-W-WRAP-CONTROL-PLAN? 0= IF RTE-S-INVALID EXIT THEN
    RTE-S-OK ;

: _RTHP-W-APPEND-COLLECTION-CLAIM?  ( control-index -- flag )
    DUP RTE-CONTROL-SIZE * _RTHP-W-P @ _RTHP.CONTROLS-A @ +
        DUP _RTHP-W-CONTROL !
    DUP _RTE-CONTROL.KIND @ _RTHP-COLLECTION-CONTROL-KIND?
        0= IF 2DROP 0 EXIT THEN
    _RTE-CONTROL.KIND @ RTE-CONTROL-TAB = IF DROP -1 EXIT THEN
    RUCP-CORRELATION-SIZE * _RTHP-W-P @ _RTHP.CORR-A @ +
        _RTHP-W-CORRELATION !
    _RTHP-W-CORRELATION @ RUCP-CORRELATION-CONTROL-ID@
        _RTHP-W-CONTROL @ _RTE-CONTROL.ID @ <> IF 0 EXIT THEN
    _RTHP-W-CORRELATION @ RUCP-CORRELATION-ATTACHMENT@ 0= IF 0 EXIT THEN
    _RTHP-W-CORRELATION @ RUCP-CORRELATION-SOURCE@
        UMSN-SOURCE-UIDL <> IF 0 EXIT THEN
    _RTHP-W-CORRELATION @ RUCP-CORRELATION-INDEX@ 0< IF 0 EXIT THEN
    _RTHP-W-CORRELATION @ RUCP-CORRELATION-SCOPE@ IF 0 EXIT THEN
    _RTHP-W-CORRELATION @ RUCP-CORRELATION-SUBKEY@ 0= IF 0 EXIT THEN
    _RTHP-W-CORRELATION @ RUCP-CORRELATION-LIFECYCLE-GENERATION@
        0< IF 0 EXIT THEN
    _RTHP-W-CONTROL @ _RTE-CONTROL.STATE @ RTE-CONTROL-VISIBLE AND 0= IF
        -1 EXIT
    THEN
    _RTHP-W-CONTROL @ _RTE-CONTROL.ROW @ _RTHP-W-ROW !
    _RTHP-W-CONTROL @ _RTE-CONTROL.COL @ _RTHP-W-COL !
    _RTHP-W-CONTROL @ _RTE-CONTROL.HEIGHT @ _RTHP-W-HEIGHT !
    _RTHP-W-CONTROL @ _RTE-CONTROL.WIDTH @ _RTHP-W-WIDTH !
    _RTHP-W-ROW @ _RTHP-W-HEIGHT @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN _RTHP-W-END !
    _RTHP-W-END @ _RTHP-W-P @ _RTHP.ROWS @ U> IF 0 EXIT THEN
    _RTHP-W-COL @ _RTHP-W-WIDTH @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-W-P @ _RTHP.COLS @ U> IF DROP 0 EXIT THEN
    _RTHP-W-CLAIMS @ _RTHP-W-P @ _RTHP.MAX-CONTROLS @ U< 0= IF
        DROP 0 EXIT
    THEN _RTHP-W-MAX !
    _RTHP-W-CLAIMS @ RUCL-CLAIM-SIZE *
        _RTHP-W-P @ _RTHP.CLAIMS-A @ + _RTHP-W-CLAIM !
    _RTHP-W-CORRELATION @ RUCP-CORRELATION-ATTACHMENT@
    _RTHP-W-P @ _RTHP.SOURCE-GEN @
    _RTHP-W-CORRELATION @ RUCP-CORRELATION-SOURCE@
    _RTHP-W-CORRELATION @ RUCP-CORRELATION-INDEX@
    _RTHP-W-CORRELATION @ RUCP-CORRELATION-SUBKEY@
    _RTHP-W-CONTROL @ _RTE-CONTROL.Z @
    _RTHP-W-ROW @ _RTHP-W-COL @ _RTHP-W-END @ _RTHP-W-MAX @
    _RTHP-W-CLAIM @ RUCL-ADMITTED-RECTANGLE!
        RUCL-S-OK <> IF 0 EXIT THEN
    1 _RTHP-W-CLAIMS +!
    -1 ;

: _RTHP-W-APPEND-COLLECTION-CLAIMS?  ( -- flag )
    _RTHP-W-P @ _RTHP.CONTROL-COUNT @ _RTHP-W-P @ _RTHP.FIELD-COUNT @ -
    _RTHP-W-P @ _RTHP.DIALOG-CONTROLS @ -
    _RTHP-W-P @ _RTHP.MENU-CONTROL-COUNT @ ?DO
        I _RTHP-W-APPEND-COLLECTION-CLAIM? 0= IF 0 UNLOOP EXIT THEN
    LOOP
    -1 ;

: _RTHP-BUILD-CLAIMS?  ( producer -- flag )
    _RTHP-W-P !
    0 _RTHP-W-CLAIMS !
    _RTHP-W-COPIED-BEGIN
    BEGIN _RTHP-W-DOCUMENT-I @
        _RTHP-W-P @ _RTHP.DOCUMENT-COUNT @ U< WHILE
        _RTHP-W-COPIED-DOCUMENT? 0= IF 0 EXIT THEN
        _RTHP-W-DOC-RECORD-COUNT @ IF
            _RTHP-W-P @ _RTHP.RUCL-Q RUCL-REQUEST-CLEAR
            _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-TOKEN@
            _RTHP-W-P @ _RTHP.SOURCE-GEN @
            _RTHP-W-DOC-RECORD-COUNT @
            _RTHP-W-P @ _RTHP.RUCL-Q RUCL-REQUEST-ADMISSION!
            _RTHP-W-P @ _RTHP.COLS @ _RTHP-W-P @ _RTHP.ROWS @
            _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-ROW@
            _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-COL@
            _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-HEIGHT@
            _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-WIDTH@
            _RTHP-W-P @ _RTHP.RUCL-Q RUCL-REQUEST-GEOMETRY!
            _RTHP-W-P @ _RTHP.SOURCE-RECS-A @
                _RTHP-W-DOC-RECORD-O @ +
            _RTHP-W-DOC-RECORD-U @
            _RTHP-W-CLAIM-OUTPUT? 0= IF 2DROP 0 EXIT THEN
            _RTHP-W-OUT-CLAIMS-A @ _RTHP-W-OUT-CLAIMS-U @
            _RTHP-W-P @ _RTHP.RUCL-Q RUCL-REQUEST-STORAGE!
            _RTHP-W-P @ _RTHP.RUCL-Q RUCL-BUILD
            _RTHP-W-STATUS ! _RTHP-W-COUNT !
            _RTHP-W-STATUS @ RUCL-S-OK <> IF 0 EXIT THEN
            _RTHP-W-COUNT @ _RTHP-W-DOC-RECORD-COUNT @ U> IF 0 EXIT THEN
            _RTHP-W-CLAIMS @ _RTHP-W-COUNT @ _RTHP-U32+?
                0= IF DROP 0 EXIT THEN
            DUP _RTHP-W-P @ _RTHP.MAX-RECORDS @ U> IF DROP 0 EXIT THEN
                _RTHP-W-CLAIMS !
        THEN
        1 _RTHP-W-DOCUMENT-I +!
    REPEAT
    _RTHP-W-COPIED-COMPLETE? 0= IF 0 EXIT THEN
    _RTHP-W-CLAIMS @ _RTHP-W-P @ _RTHP.MENU-CLAIMS !
    _RTHP-W-APPEND-COLLECTION-CLAIMS? 0= IF 0 EXIT THEN
    _RTHP-W-CLAIMS @ RUCL-CLAIM-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN _RTHP-W-P @ _RTHP.CLAIMS-USED !
    -1 ;

\ ---------------------------------------------------------------------
\  The layer above a document: its own overlay
\ ---------------------------------------------------------------------
\ A document's overlay, the prompt it opens or the dialog widget it shows,
\ lies in the layer above the document's roots: the shell candidate puts
\ it in a modal region over the pane, and this producer's one region paints
\ it after them by its depth.  So an overlay's claim may meet the claims of
\ its own document's roots beneath it, and theirs may meet it; the residual
\ plan excludes the union of both.  Every other meeting of claims is
\ refused as before.
: _RTHP-OVERLAY-SOURCE? ( source-kind -- flag )
    DUP UFLSN-SOURCE-OVERLAY = SWAP UDLSN-SOURCE-OVERLAY = OR ;

\ CLAIM is a root of the document TOKEN beneath an overlay at depth Z: no
\ overlay itself, and lower.
: _RTHP-BENEATH? ( claim token z -- flag )
    >R OVER RUCL-CLAIM-ATTACHMENT@ <> IF R> 2DROP 0 EXIT THEN
    DUP RUCL-CLAIM-SOURCE@ _RTHP-OVERLAY-SOURCE? IF R> 2DROP 0 EXIT THEN
    RUCL-CLAIM-Z@ R> < ;

\ CLAIM is the overlay of the document TOKEN, above a root at depth Z.
: _RTHP-OVERLAY-ABOVE? ( claim token z -- flag )
    >R OVER RUCL-CLAIM-ATTACHMENT@ <> IF R> 2DROP 0 EXIT THEN
    DUP RUCL-CLAIM-SOURCE@ _RTHP-OVERLAY-SOURCE? 0= IF R> 2DROP 0 EXIT THEN
    RUCL-CLAIM-Z@ R> > ;

\ Documents lie in layers too.  An overlay slot's document, such as one of
\ Desk's screens, is the layer above the others (RUHA-DOCUMENT-LAYER@): the
\ shell's candidate puts it in a region above the panes beneath it, so the
\ claims of documents in different layers may meet, while those of one
\ layer may not.  This producer's own region cannot order two documents,
\ so its candidate holding such a meeting goes out only through the
\ shell's (_RTHP-CROSS-LAYERED?).
: _RTHP-LAYER-OF  ( token producer -- layer )
    DUP _RTHP.DOCUMENT-COUNT @ 0 ?DO
        I OVER _RTHP-DOCUMENT-AT DUP RUHA-DOCUMENT-TOKEN@ 3 PICK = IF
            RUHA-DOCUMENT-LAYER@ NIP NIP UNLOOP EXIT
        THEN DROP
    LOOP 2DROP 0 ;

\ CLAIM's document and the document TOKEN names lie in different layers.
: _RTHP-OTHER-LAYER?  ( claim token producer -- flag )
    >R SWAP RUCL-CLAIM-ATTACHMENT@ R@ _RTHP-LAYER-OF
    SWAP R> _RTHP-LAYER-OF <> ;

\ ---------------------------------------------------------------------
\  Canonical UFLD -> genuine FIELD controls, with an independent source lane
\ ---------------------------------------------------------------------
VARIABLE _RTHP-FF-P
VARIABLE _RTHP-FF-DOC
VARIABLE _RTHP-FF-DA
VARIABLE _RTHP-FF-DU
VARIABLE _RTHP-FF-NA
VARIABLE _RTHP-FF-NU
VARIABLE _RTHP-FF-DESC
VARIABLE _RTHP-FF-ENTRY
VARIABLE _RTHP-FF-CONTROL
VARIABLE _RTHP-FF-CORR
VARIABLE _RTHP-FF-ROW
VARIABLE _RTHP-FF-COL
VARIABLE _RTHP-FF-H
VARIABLE _RTHP-FF-W
VARIABLE _RTHP-FF-ROW1
VARIABLE _RTHP-FF-COL1
VARIABLE _RTHP-FF-CLAIM
VARIABLE _RTHP-FF-OVERLAP
VARIABLE _RTHP-FF-LABEL-A
VARIABLE _RTHP-FF-LABEL-U
VARIABLE _RTHP-FF-CONTENT-A
VARIABLE _RTHP-FF-CONTENT-U
VARIABLE _RTHP-FF-TEXT-END
VARIABLE _RTHP-FF-CLAIM-END
VARIABLE _RTHP-FF-ID
VARIABLE _RTHP-FF-CHOICES
VARIABLE _RTHP-FF-UTF8

: _RTHP-FIELD-CLEAR ( producer -- )
    0 OVER _RTHP.FIELD-COUNT ! 0 OVER _RTHP.FIELD-ITEMS !
    0 SWAP _RTHP.FIELD-UTF8 ! ;

: _RTHP-DIALOG-CLEAR ( producer -- )
    0 OVER _RTHP.DIALOG-COUNT ! 0 OVER _RTHP.DIALOG-CONTROLS !
    0 SWAP _RTHP.DIALOG-UTF8 ! ;

: _RTHP-FIELD-NEXT? ( producer -- flag )
    DUP _RTHP.FIRST-OBJECT @ SWAP _RTHP.CONTROL-COUNT @
        _RTHP-U+? 0= IF DROP 0 EXIT THEN
    DUP 0= IF DROP 0 EXIT THEN _RTHP-W-GLYPH-FIRST ! -1 ;

\ The dialog lane follows the fields, so it goes with them.
: _RTHP-STRIP-FIELDS? ( producer -- flag )
    DUP _RTHP-FIELD-CLEAR DUP _RTHP-DIALOG-CLEAR
    DUP _RTHP.FIELD-BASE-CONTROLS @ OVER _RTHP.CONTROL-COUNT !
    DUP _RTHP.FIELD-BASE-TEXT @ OVER _RTHP.SOURCE-TEXT-USED !
    DUP _RTHP.FIELD-BASE-CLAIMS @ OVER _RTHP.CLAIMS-USED !
    DUP _RTHP-W-P ! _RTHP-FIELD-NEXT? 0= IF 0 EXIT THEN
    _RTHP-W-WRAP-CONTROL-PLAN? ;

\ The claim just met is a root of the prompt's own document beneath it,
\ when the field placed is the document's overlay prompt.
: _RTHP-FF-CLAIM-BENEATH? ( -- flag )
    _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-SOURCE@ UFLSN-SOURCE-OVERLAY <> IF 0 EXIT THEN
    _RTHP-FF-CLAIM @ _RTHP-FF-DOC @ RUHA-DOCUMENT-TOKEN@
    _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-Z@ _RTHP-BENEATH? ;

\ The claim just met lies in another layer than the field: a root of its
\ document beneath its overlay prompt, or a claim of a document in another
\ layer.
: _RTHP-FF-CLAIM-LAYERED? ( -- flag )
    _RTHP-FF-CLAIM-BENEATH? IF -1 EXIT THEN
    _RTHP-FF-CLAIM @ _RTHP-FF-DOC @ RUHA-DOCUMENT-TOKEN@ _RTHP-FF-P @ _RTHP-OTHER-LAYER? ;

: _RTHP-FF-GEOMETRY? ( -- flag )
    0 _RTHP-FF-OVERLAP !
    _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-ROW@ DUP _RTHP-FF-ROW !
        0< IF 0 EXIT THEN
    _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-COLUMN@ DUP _RTHP-FF-COL !
        0< IF 0 EXIT THEN
    _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-HEIGHT@ DUP _RTHP-FF-H !
        0> 0= IF 0 EXIT THEN
    _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-WIDTH@ DUP _RTHP-FF-W !
        0> 0= IF 0 EXIT THEN
    _RTHP-FF-ROW @ _RTHP-FF-H @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN DUP _RTHP-FF-ROW1 !
    _RTHP-FF-P @ _RTHP.ROWS @ U> IF 0 EXIT THEN
    _RTHP-FF-COL @ _RTHP-FF-W @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN DUP _RTHP-FF-COL1 !
    _RTHP-FF-P @ _RTHP.COLS @ U> IF 0 EXIT THEN
    _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-CLIP-ROW@ _RTHP-FF-ROW @ >
    _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-CLIP-COLUMN@ _RTHP-FF-COL @ > OR
        IF 0 EXIT THEN
    _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-CLIP-ROW@
    _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-CLIP-HEIGHT@ +
        _RTHP-FF-ROW1 @ < IF 0 EXIT THEN
    _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-CLIP-COLUMN@
    _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-CLIP-WIDTH@ +
        _RTHP-FF-COL1 @ < IF 0 EXIT THEN
    _RTHP-FF-P @ _RTHP.CLAIMS-USED @ RUCL-CLAIM-SIZE / 0 ?DO
        _RTHP-FF-P @ _RTHP.CLAIMS-A @ I RUCL-CLAIM-SIZE * + _RTHP-FF-CLAIM !
        _RTHP-FF-ROW @ _RTHP-FF-CLAIM @ RUCL-CLAIM-ROW1@ <
        _RTHP-FF-ROW1 @ _RTHP-FF-CLAIM @ RUCL-CLAIM-ROW0@ > AND
        _RTHP-FF-COL @ _RTHP-FF-CLAIM @ RUCL-CLAIM-COL1@ < AND
        _RTHP-FF-COL1 @ _RTHP-FF-CLAIM @ RUCL-CLAIM-COL0@ > AND IF
        _RTHP-FF-CLAIM-LAYERED? 0= IF
            1 _RTHP-FF-OVERLAP !
            I RUCL-CLAIM-SIZE * _RTHP-FF-P @ _RTHP.FIELD-BASE-CLAIMS @ U< IF
                2 _RTHP-FF-OVERLAP !
            THEN 0 UNLOOP EXIT
        THEN THEN
    LOOP -1 ;

: _RTHP-FF-STATE ( native-state -- control-state )
    DUP UFLD-STATE-VISIBLE UFLD-STATE-ENABLED OR AND SWAP
    UFLD-STATE-SELECTED AND IF RTE-CONTROL-SELECTED OR THEN ;

: _RTHP-FF-WRITE ( -- rte-status )
    _RTHP-FF-ENTRY @ UFLD-STATE@ UFLD-STATE-VISIBLE AND 0= IF RTE-S-OK EXIT THEN
    _RTHP-FF-GEOMETRY? 0= IF
        _RTHP-FF-OVERLAP @ IF RTE-S-UNAVAILABLE ELSE RTE-S-OK THEN EXIT
    THEN
    _RTHP-FF-P @ _RTHP.FIELD-COUNT @ _RTHP-FF-P @ _RTHP.MAX-FIELDS @
        U< 0= IF RTE-S-CAPACITY EXIT THEN
    _RTHP-FF-P @ _RTHP.CONTROL-COUNT @ _RTHP-FF-P @ _RTHP.MAX-CONTROLS @
        U< 0= IF RTE-S-CAPACITY EXIT THEN
    _RTHP-FF-P @ _RTHP.FIRST-OBJECT @ _RTHP-FF-P @ _RTHP.CONTROL-COUNT @
        _RTHP-U+? 0= IF DROP RTE-S-INVALID EXIT THEN _RTHP-FF-ID !
    _RTHP-FF-ID @ 1 _RTHP-U+? 0= IF DROP RTE-S-INVALID EXIT THEN DROP
    _RTHP-FF-ENTRY @ UFLD-LABEL@ _RTHP-FF-LABEL-U ! _RTHP-FF-LABEL-A !
    _RTHP-FF-ENTRY @ DUP UFLD-BYTES@ UFLDC-BYTES
        0<> IF DROP RTE-S-INVALID EXIT THEN _RTHP-FF-CONTENT-U !
    _RTHP-FF-CONTENT-U @ _RTHP-FF-LABEL-U @ _RTHP-U32+?
        0= IF DROP RTE-S-INVALID EXIT THEN
    _RTHP-FF-P @ _RTHP.SOURCE-TEXT-USED @ _RTHP-U32+?
        0= IF DROP RTE-S-INVALID EXIT THEN DUP _RTHP-FF-TEXT-END !
    _RTHP-FF-P @ _RTHP.SOURCE-TEXT-U @ U> IF RTE-S-CAPACITY EXIT THEN
    _RTHP-FF-P @ _RTHP.CLAIMS-USED @ RUCL-CLAIM-SIZE _RTHP-U32+?
        0= IF DROP RTE-S-INVALID EXIT THEN DUP _RTHP-FF-CLAIM-END !
    _RTHP-FF-P @ _RTHP.CLAIMS-U @ U> IF RTE-S-CAPACITY EXIT THEN
    _RTHP-FF-ENTRY @ UFLD-CHOICE-COUNT@ _RTHP-FF-P @ _RTHP.FIELD-ITEMS @
        _RTHP-U32+? 0= IF DROP RTE-S-INVALID EXIT THEN _RTHP-FF-CHOICES !
    _RTHP-FF-ENTRY @ UFLD-UTF8-BYTES@ DUP
        _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-UTF8-BYTES@ <> IF
        DROP RTE-S-INVALID EXIT
    THEN _RTHP-FF-P @ _RTHP.FIELD-UTF8 @ _RTHP-U32+?
        0= IF DROP RTE-S-INVALID EXIT THEN _RTHP-FF-UTF8 !
    _RTHP-FF-P @ _RTHP.CONTROLS-A @
        _RTHP-FF-P @ _RTHP.CONTROL-COUNT @ RTE-CONTROL-SIZE * +
        DUP _RTHP-FF-CONTROL ! RTE-CONTROL-SIZE 0 FILL
    _RTHP-FF-P @ _RTHP.CORR-A @
        _RTHP-FF-P @ _RTHP.CONTROL-COUNT @ RUCP-CORRELATION-SIZE * +
        DUP _RTHP-FF-CORR ! RUCP-CORRELATION-SIZE 0 FILL
    _RTHP-FF-P @ _RTHP.OWNER @ _RTHP-FF-CONTROL @ _RTE-CONTROL.OWNER !
    _RTHP-FF-P @ _RTHP.OWNER-GEN @ _RTHP-FF-CONTROL @ _RTE-CONTROL.GENERATION !
    _RTHP-FF-ID @ _RTHP-FF-CONTROL @ _RTE-CONTROL.ID !
    RTE-CONTROL-FIELD _RTHP-FF-CONTROL @ _RTE-CONTROL.KIND !
    _RTHP-FF-ENTRY @ UFLD-STATE@ _RTHP-FF-STATE _RTHP-FF-CONTROL @ _RTE-CONTROL.STATE !
    _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-Z@ _RTHP-FF-CONTROL @ _RTE-CONTROL.Z !
    _RTHP-FF-P @ _RTHP.REGION @ _RTHP-FF-CONTROL @ _RTE-CONTROL.REGION !
    _RTHP-FF-ROW @ _RTHP-FF-CONTROL @ _RTE-CONTROL.ROW !
    _RTHP-FF-COL @ _RTHP-FF-CONTROL @ _RTE-CONTROL.COL !
    _RTHP-FF-H @ _RTHP-FF-CONTROL @ _RTE-CONTROL.HEIGHT !
    _RTHP-FF-W @ _RTHP-FF-CONTROL @ _RTE-CONTROL.WIDTH !
    _RTHP-FF-P @ _RTHP.ROWS @ _RTHP-FF-CONTROL @ _RTE-CONTROL.ROOT-HEIGHT !
    _RTHP-FF-P @ _RTHP.COLS @ _RTHP-FF-CONTROL @ _RTE-CONTROL.ROOT-WIDTH !
    _RTHP-FF-P @ _RTHP.SOURCE-TEXT-A @ _RTHP-FF-P @ _RTHP.SOURCE-TEXT-USED @ +
        _RTHP-FF-CONTENT-A !
    _RTHP-FF-LABEL-U @ IF
        _RTHP-FF-LABEL-A @ _RTHP-FF-CONTENT-A @ _RTHP-FF-LABEL-U @ MOVE
        _RTHP-FF-CONTENT-A @ _RTHP-FF-CONTROL @ _RTE-CONTROL.LABEL-A !
        _RTHP-FF-LABEL-U @ _RTHP-FF-CONTROL @ _RTE-CONTROL.LABEL-U !
    THEN
    _RTHP-FF-LABEL-U @ _RTHP-FF-CONTENT-A +!
    _RTHP-FF-ENTRY @ DUP UFLD-BYTES@
    _RTHP-FF-CONTENT-A @ _RTHP-FF-CONTENT-U @ UFLDC-PACK
        0<> IF DROP RTE-S-INVALID EXIT THEN
    _RTHP-FF-CONTENT-U @ <> IF RTE-S-INVALID EXIT THEN
    _RTHP-FF-CONTENT-A @ _RTHP-FF-CONTROL @ _RTE-CONTROL.CONTENT-A !
    _RTHP-FF-CONTENT-U @ _RTHP-FF-CONTROL @ _RTE-CONTROL.CONTENT-U !
    _RTHP-FF-ENTRY @ UFLD-CHOICE-COUNT@ _RTHP-FF-CONTROL @ _RTE-CONTROL.CONTENT-ITEMS !
    _RTHP-FF-ENTRY @ UFLD-UTF8-BYTES@ _RTHP-FF-LABEL-U @ -
        _RTHP-FF-CONTROL @ _RTE-CONTROL.CONTENT-UTF8 !
    _RTHP-FF-DOC @ RUHA-DOCUMENT-TOKEN@ _RTHP-FF-CORR @ _RUCP-X.ATTACHMENT !
    _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-SOURCE@ _RTHP-FF-CORR @ _RUCP-X.SOURCE !
    _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-SOURCE-INDEX@ _RTHP-FF-CORR @ _RUCP-X.INDEX !
    _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-ROOT-KEY@ _RTHP-FF-CORR @ _RUCP-X.SUBKEY !
    _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-SOURCE-GENERATION@
        _RTHP-FF-CORR @ _RUCP-X.LIFECYCLE-GENERATION !
    \ Positive native key in SCOPE distinguishes this mounted FIELD identity
    \ from collection roots (scope zero), without inventing a USCOL record.
    _RTHP-FF-ENTRY @ UFLD-KEY@ _RTHP-FF-CORR @ _RUCP-X.SCOPE !
    _RTHP-FF-ID @ _RTHP-FF-CORR @ _RUCP-X.CONTROL-ID !
    _RTHP-FF-DOC @ RUHA-DOCUMENT-TOKEN@
    _RTHP-FF-P @ _RTHP.SOURCE-GEN @
    _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-SOURCE@
    _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-SOURCE-INDEX@
    _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-ROOT-KEY@ _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-Z@
    _RTHP-FF-ROW @ _RTHP-FF-COL @ _RTHP-FF-ROW1 @ _RTHP-FF-COL1 @
    _RTHP-FF-P @ _RTHP.CLAIMS-A @ _RTHP-FF-P @ _RTHP.CLAIMS-USED @ +
        RUCL-ADMITTED-RECTANGLE! RUCL-S-OK <> IF RTE-S-INVALID EXIT THEN
    _RTHP-FF-TEXT-END @ _RTHP-FF-P @ _RTHP.SOURCE-TEXT-USED !
    _RTHP-FF-CLAIM-END @ _RTHP-FF-P @ _RTHP.CLAIMS-USED !
    _RTHP-FF-CHOICES @ _RTHP-FF-P @ _RTHP.FIELD-ITEMS !
    _RTHP-FF-UTF8 @ _RTHP-FF-P @ _RTHP.FIELD-UTF8 !
    1 _RTHP-FF-P @ _RTHP.CONTROL-COUNT +!
    1 _RTHP-FF-P @ _RTHP.FIELD-COUNT +! RTE-S-OK ;

: _RTHP-BUILD-FIELDS ( producer -- rte-status )
    0 _RTHP-FF-OVERLAP !
    DUP _RTHP-FF-P ! DUP _RTHP-FIELD-CLEAR
    DUP _RTHP.CONTROL-COUNT @ OVER _RTHP.FIELD-BASE-CONTROLS !
    DUP _RTHP.SOURCE-TEXT-USED @ OVER _RTHP.FIELD-BASE-TEXT !
    DUP _RTHP.CLAIMS-USED @ OVER _RTHP.FIELD-BASE-CLAIMS !
    _RTHP.FIELD-REFUSED @ IF RTE-S-OK EXIT THEN
    _RTHP-FF-P @ _RTHP.DOCUMENT-COUNT @ 0 ?DO
        I _RTHP-FF-P @ _RTHP-DOCUMENT-AT _RTHP-FF-DOC !
        _RTHP-FF-DOC @ RUHA-DOCUMENT-FIELDS-DESCRIPTOR-BYTES@ _RTHP-FF-DU !
        _RTHP-FF-P @ _RTHP.FIELD-DESCRIPTORS-A @
        _RTHP-FF-DOC @ RUHA-DOCUMENT-FIELDS-DESCRIPTOR-OFFSET@ + _RTHP-FF-DA !
        _RTHP-FF-DOC @ RUHA-DOCUMENT-FIELDS-NATIVE-BYTES@ _RTHP-FF-NU !
        _RTHP-FF-P @ _RTHP.FIELD-NATIVE-A @
        _RTHP-FF-DOC @ RUHA-DOCUMENT-FIELDS-NATIVE-OFFSET@ + _RTHP-FF-NA !
        _RTHP-FF-DU @ UFLSN-DESCRIPTOR-SIZE MOD IF RTE-S-INVALID UNLOOP EXIT THEN
        _RTHP-FF-DOC @ RUHA-DOCUMENT-FIELDS-DESCRIPTOR-OFFSET@
        _RTHP-FF-DU @ _RTHP-U32+? 0= IF DROP RTE-S-INVALID UNLOOP EXIT THEN
        _RTHP-FF-P @ _RTHP.FIELD-DESCRIPTORS-USED @ U> IF RTE-S-INVALID UNLOOP EXIT THEN
        _RTHP-FF-DOC @ RUHA-DOCUMENT-FIELDS-NATIVE-OFFSET@
        _RTHP-FF-NU @ _RTHP-U32+? 0= IF DROP RTE-S-INVALID UNLOOP EXIT THEN
        _RTHP-FF-P @ _RTHP.FIELD-NATIVE-USED @ U> IF RTE-S-INVALID UNLOOP EXIT THEN
        _RTHP-FF-DU @ UFLSN-DESCRIPTOR-SIZE / 0 ?DO
            _RTHP-FF-DA @ I UFLSN-DESCRIPTOR-SIZE * + _RTHP-FF-DESC !
            _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-NATIVE-OFFSET@
            _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-ENTRY-BYTES@ _RTHP-U32+?
                0= IF DROP RTE-S-INVALID UNLOOP UNLOOP EXIT THEN
            _RTHP-FF-NU @ U> IF RTE-S-INVALID UNLOOP UNLOOP EXIT THEN
            _RTHP-FF-DESC @ _RTHP-FF-NA @ UFLSN-DESCRIPTOR-NATIVE
                OVER _RTHP-FF-ENTRY ! UFLD-VALIDATE UFLD-S-OK <>
                IF RTE-S-INVALID UNLOOP UNLOOP EXIT THEN
            _RTHP-FF-ENTRY @ UFLD-WIDTH@ _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-WIDTH@ <>
            _RTHP-FF-ENTRY @ UFLD-HEIGHT@ _RTHP-FF-DESC @ UFLSN-DESCRIPTOR-HEIGHT@ <> OR
                IF RTE-S-INVALID UNLOOP UNLOOP EXIT THEN
            _RTHP-FF-WRITE DUP RTE-S-OK <> IF UNLOOP UNLOOP EXIT THEN DROP
        LOOP
    LOOP
    _RTHP-FF-P @ _RTHP-W-P !
    _RTHP-W-WRAP-CONTROL-PLAN? 0= IF RTE-S-INVALID EXIT THEN
    _RTHP-FF-P @ _RTHP-FIELD-NEXT? 0= IF RTE-S-INVALID EXIT THEN
    RTE-S-OK ;

: _RTHP-W-BUILD-OPTIONAL-FIELDS ( -- rte-status )
    _RTHP-W-P @ _RTHP-BUILD-FIELDS
    DUP RTE-S-CAPACITY = OVER RTE-S-UNAVAILABLE = OR IF
        DROP _RTHP-W-P @ _RTHP-STRIP-FIELDS? 0= IF RTE-S-INVALID EXIT THEN
        -1 _RTHP-W-P @ _RTHP.FIELD-REFUSED !
        _RTHP-FF-OVERLAP @ 2 = IF RTE-S-UNAVAILABLE ELSE RTE-S-OK THEN
    THEN ;

\ ---------------------------------------------------------------------
\  Canonical UDLG -> DIALOG and BUTTON controls, after the fields
\ ---------------------------------------------------------------------
\ A document shows at most one dialog.  It lowers to a DIALOG root where
\ the dialog lies, its title the label and DLG1 the content, then a BUTTON
\ root for each shown button at the dialog's origin plus the button's
\ slot, its label and BTN1.  The DIALOG claims its whole rectangle, so its
\ buttons and the rest of its paint lie inside that claim.  Every control's
\ correlation names the dialog, by its key in SUBKEY and SCOPE: index 0 is
\ the DIALOG, index i+1 its button i.  A dialog off its document, partly
\ off the screen, or over another dialog stays CELL; one over an earlier
\ family's claim leaves the draw CELL, as a field does.

\ A dialog is its document's overlay, over all of its paint: the depth a
\ document's prompt takes.

VARIABLE _RTHP-DD-P
VARIABLE _RTHP-DD-DOC
VARIABLE _RTHP-DD-DESC
VARIABLE _RTHP-DD-ENTRY
VARIABLE _RTHP-DD-BUTTON
VARIABLE _RTHP-DD-ROW
VARIABLE _RTHP-DD-COL
VARIABLE _RTHP-DD-ROW1
VARIABLE _RTHP-DD-COL1
VARIABLE _RTHP-DD-CLAIM
VARIABLE _RTHP-DD-OVERLAP
VARIABLE _RTHP-DD-SHOWN
VARIABLE _RTHP-DD-CONTENT-U
VARIABLE _RTHP-DD-TEXT
VARIABLE _RTHP-DD-UTF8
VARIABLE _RTHP-DD-AT
VARIABLE _RTHP-DD-INDEX
VARIABLE _RTHP-DD-ID
VARIABLE _RTHP-DD-CONTROL
VARIABLE _RTHP-DD-CORR
VARIABLE _RTHP-DD-KIND
VARIABLE _RTHP-DD-STATE
VARIABLE _RTHP-DD-ORDINAL
VARIABLE _RTHP-DD-CR
VARIABLE _RTHP-DD-CC
VARIABLE _RTHP-DD-CH
VARIABLE _RTHP-DD-CW
VARIABLE _RTHP-DD-Z
VARIABLE _RTHP-DD-CONTENTS

: _RTHP-STRIP-DIALOGS? ( producer -- flag )
    DUP _RTHP-DIALOG-CLEAR
    DUP _RTHP.DIALOG-BASE-CONTROLS @ OVER _RTHP.CONTROL-COUNT !
    DUP _RTHP.DIALOG-BASE-TEXT @ OVER _RTHP.SOURCE-TEXT-USED !
    DUP _RTHP.DIALOG-BASE-CLAIMS @ OVER _RTHP.CLAIMS-USED !
    DUP _RTHP-W-P ! _RTHP-FIELD-NEXT? 0= IF 0 EXIT THEN
    _RTHP-W-WRAP-CONTROL-PLAN? ;

\ A dialog lies just below its contents' depth: a widget's buttons, or
\ an element's roots.
: _RTHP-DD-DIALOG-Z ( -- z )  _RTHP-DD-DESC @ UDLSN-DESCRIPTOR-Z@ 1- ;

\ The claim met is one of the dialog element's contents: a root of the
\ same document wholly inside it, above it.
: _RTHP-DD-CONTENT? ( -- flag )
    _RTHP-DD-DESC @ UDLSN-DESCRIPTOR-SOURCE@ UDLSN-SOURCE-ELEMENT <> IF 0 EXIT THEN
    _RTHP-DD-CLAIM @ RUCL-CLAIM-ATTACHMENT@ _RTHP-DD-DOC @ RUHA-DOCUMENT-TOKEN@ <>
        IF 0 EXIT THEN
    _RTHP-DD-CLAIM @ RUCL-CLAIM-Z@ _RTHP-DD-DIALOG-Z > 0= IF 0 EXIT THEN
    _RTHP-DD-CLAIM @ RUCL-CLAIM-ROW0@ _RTHP-DD-ROW @ < 0=
    _RTHP-DD-CLAIM @ RUCL-CLAIM-ROW1@ _RTHP-DD-ROW1 @ > 0= AND
    _RTHP-DD-CLAIM @ RUCL-CLAIM-COL0@ _RTHP-DD-COL @ < 0= AND
    _RTHP-DD-CLAIM @ RUCL-CLAIM-COL1@ _RTHP-DD-COL1 @ > 0= AND ;

\ The claim just met is a root of the dialog widget's own document beneath
\ it: the dialog is the document's overlay.
: _RTHP-DD-BENEATH? ( -- flag )
    _RTHP-DD-DESC @ UDLSN-DESCRIPTOR-SOURCE@ UDLSN-SOURCE-OVERLAY <> IF 0 EXIT THEN
    _RTHP-DD-CLAIM @ _RTHP-DD-DOC @ RUHA-DOCUMENT-TOKEN@
    _RTHP-DD-DIALOG-Z _RTHP-BENEATH? ;

\ The claim just met lies in another layer than the dialog: a root of its
\ document beneath its dialog widget, or a claim of a document in another
\ layer.
: _RTHP-DD-LAYERED? ( -- flag )
    _RTHP-DD-BENEATH? IF -1 EXIT THEN
    _RTHP-DD-CLAIM @ _RTHP-DD-DOC @ RUHA-DOCUMENT-TOKEN@ _RTHP-DD-P @ _RTHP-OTHER-LAYER? ;

\ The dialog lies on the screen and inside its document, and meets no
\ earlier claim but its contents', or, for a dialog widget, its document's
\ roots beneath it.  OVERLAP is 2 for a claim before the
\ dialog lane, 1 for an earlier dialog's.  A dialog element whose contents
\ are not all there would hide the painted text of those left out, so it
\ stays painted text too.
: _RTHP-DD-GEOMETRY? ( -- flag )
    0 _RTHP-DD-OVERLAP ! 0 _RTHP-DD-CONTENTS !
    _RTHP-DD-DESC @ UDLSN-DESCRIPTOR-ROW@ DUP _RTHP-DD-ROW !
        0< IF 0 EXIT THEN
    _RTHP-DD-DESC @ UDLSN-DESCRIPTOR-COLUMN@ DUP _RTHP-DD-COL !
        0< IF 0 EXIT THEN
    _RTHP-DD-DESC @ UDLSN-DESCRIPTOR-HEIGHT@ DUP 0> 0= IF DROP 0 EXIT THEN
    _RTHP-DD-ROW @ SWAP _RTHP-U32+?
        0= IF DROP 0 EXIT THEN DUP _RTHP-DD-ROW1 !
    _RTHP-DD-P @ _RTHP.ROWS @ U> IF 0 EXIT THEN
    _RTHP-DD-DESC @ UDLSN-DESCRIPTOR-WIDTH@ DUP 0> 0= IF DROP 0 EXIT THEN
    _RTHP-DD-COL @ SWAP _RTHP-U32+?
        0= IF DROP 0 EXIT THEN DUP _RTHP-DD-COL1 !
    _RTHP-DD-P @ _RTHP.COLS @ U> IF 0 EXIT THEN
    _RTHP-DD-DOC @ RUHA-DOCUMENT-ROW@ _RTHP-DD-ROW @ >
    _RTHP-DD-DOC @ RUHA-DOCUMENT-COL@ _RTHP-DD-COL @ > OR IF 0 EXIT THEN
    _RTHP-DD-DOC @ RUHA-DOCUMENT-ROW@ _RTHP-DD-DOC @ RUHA-DOCUMENT-HEIGHT@ +
        _RTHP-DD-ROW1 @ < IF 0 EXIT THEN
    _RTHP-DD-DOC @ RUHA-DOCUMENT-COL@ _RTHP-DD-DOC @ RUHA-DOCUMENT-WIDTH@ +
        _RTHP-DD-COL1 @ < IF 0 EXIT THEN
    _RTHP-DD-P @ _RTHP.CLAIMS-USED @ RUCL-CLAIM-SIZE / 0 ?DO
        _RTHP-DD-P @ _RTHP.CLAIMS-A @ I RUCL-CLAIM-SIZE * + _RTHP-DD-CLAIM !
        _RTHP-DD-ROW @ _RTHP-DD-CLAIM @ RUCL-CLAIM-ROW1@ <
        _RTHP-DD-ROW1 @ _RTHP-DD-CLAIM @ RUCL-CLAIM-ROW0@ > AND
        _RTHP-DD-COL @ _RTHP-DD-CLAIM @ RUCL-CLAIM-COL1@ < AND
        _RTHP-DD-COL1 @ _RTHP-DD-CLAIM @ RUCL-CLAIM-COL0@ > AND IF
        _RTHP-DD-LAYERED? 0= IF
            _RTHP-DD-CONTENT? IF
                1 _RTHP-DD-CONTENTS +!
            ELSE
                1 _RTHP-DD-OVERLAP !
                I RUCL-CLAIM-SIZE * _RTHP-DD-P @ _RTHP.DIALOG-BASE-CLAIMS @ U< IF
                    2 _RTHP-DD-OVERLAP !
                THEN 0 UNLOOP EXIT
            THEN
        THEN THEN
    LOOP
    _RTHP-DD-CONTENTS @ _RTHP-DD-DESC @ UDLSN-DESCRIPTOR-CONTENTS@ = ;

: _RTHP-DD-BUTTON-STATE ( native-state -- control-state )
    0 OVER UDLG-STATE-VISIBLE AND IF RTE-CONTROL-VISIBLE OR THEN
    OVER UDLG-STATE-ENABLED AND IF RTE-CONTROL-ENABLED OR THEN
    SWAP UDLG-STATE-SELECTED AND IF RTE-CONTROL-SELECTED OR THEN ;

\ The text, controls and claim the dialog takes, all checked before any is
\ written: DLG1 after the title, and BTN1 after each shown button's label
\ and shortcut.
: _RTHP-DD-MEASURE ( -- rte-status )
    _RTHP-DD-ENTRY @ DUP UDLG-BYTES@ UDLGC-DIALOG-BYTES
        0<> IF DROP RTE-S-INVALID EXIT THEN _RTHP-DD-CONTENT-U !
    _RTHP-DD-ENTRY @ UDLG-TITLE-BYTES@ _RTHP-DD-CONTENT-U @ _RTHP-U32+?
        0= IF DROP RTE-S-INVALID EXIT THEN _RTHP-DD-TEXT !
    _RTHP-DD-ENTRY @ UDLG-TITLE-BYTES@ _RTHP-DD-ENTRY @ UDLG-MESSAGE-BYTES@
        _RTHP-U32+? 0= IF DROP RTE-S-INVALID EXIT THEN _RTHP-DD-UTF8 !
    0 _RTHP-DD-SHOWN !
    _RTHP-DD-ENTRY @ UDLG-BUTTON-FIRST _RTHP-DD-BUTTON !
    _RTHP-DD-ENTRY @ UDLG-BUTTON-COUNT@ 0 ?DO
        _RTHP-DD-BUTTON @ UDLG-BUTTON-STATE@ UDLG-STATE-VISIBLE AND IF
            1 _RTHP-DD-SHOWN +!
            _RTHP-DD-BUTTON @ UDLG-BUTTON-LABEL@ NIP
            _RTHP-DD-BUTTON @ UDLG-BUTTON-SHORTCUT@ NIP _RTHP-U32+?
                0= IF DROP RTE-S-INVALID UNLOOP EXIT THEN DUP
            _RTHP-DD-UTF8 @ _RTHP-U32+? 0= IF 2DROP RTE-S-INVALID UNLOOP EXIT THEN
                _RTHP-DD-UTF8 !
            UDLGC-BUTTON-SIZE + _RTHP-DD-TEXT @ _RTHP-U32+?
                0= IF DROP RTE-S-INVALID UNLOOP EXIT THEN _RTHP-DD-TEXT !
        THEN
        _RTHP-DD-BUTTON @ UDLG-BUTTON-NEXT _RTHP-DD-BUTTON !
    LOOP
    _RTHP-DD-P @ _RTHP.DIALOG-UTF8 @ _RTHP-DD-UTF8 @ _RTHP-U32+?
        0= IF DROP RTE-S-INVALID EXIT THEN DROP
    _RTHP-DD-P @ _RTHP.DIALOG-COUNT @ _RTHP-DD-P @ _RTHP.MAX-DIALOGS @
        U< 0= IF RTE-S-CAPACITY EXIT THEN
    _RTHP-DD-SHOWN @ 1+ _RTHP-DD-P @ _RTHP.DIALOG-CONTROLS @ _RTHP-U32+?
        0= IF DROP RTE-S-INVALID EXIT THEN
    _RTHP-DD-P @ _RTHP.MAX-DIALOG-CONTROLS @ U> IF RTE-S-CAPACITY EXIT THEN
    _RTHP-DD-SHOWN @ 1+ _RTHP-DD-P @ _RTHP.CONTROL-COUNT @ _RTHP-U32+?
        0= IF DROP RTE-S-INVALID EXIT THEN
    _RTHP-DD-P @ _RTHP.MAX-CONTROLS @ U> IF RTE-S-CAPACITY EXIT THEN
    _RTHP-DD-TEXT @ _RTHP-DD-P @ _RTHP.SOURCE-TEXT-USED @ _RTHP-U32+?
        0= IF DROP RTE-S-INVALID EXIT THEN
    _RTHP-DD-P @ _RTHP.SOURCE-TEXT-U @ U> IF RTE-S-CAPACITY EXIT THEN
    _RTHP-DD-P @ _RTHP.CLAIMS-USED @ RUCL-CLAIM-SIZE _RTHP-U32+?
        0= IF DROP RTE-S-INVALID EXIT THEN
    _RTHP-DD-P @ _RTHP.CLAIMS-U @ U> IF RTE-S-CAPACITY EXIT THEN
    \ Every control's ID and the one after the last.
    _RTHP-DD-P @ _RTHP.FIRST-OBJECT @ _RTHP-DD-P @ _RTHP.CONTROL-COUNT @
        _RTHP-U+? 0= IF DROP RTE-S-INVALID EXIT THEN
    _RTHP-DD-SHOWN @ 1+ _RTHP-U+? 0= IF DROP RTE-S-INVALID EXIT THEN DROP
    RTE-S-OK ;

\ Copy bytes to the dialog's text and give where they went, 0 for none.
: _RTHP-DD-COPY ( a u -- a' )
    DUP 0= IF 2DROP 0 EXIT THEN
    _RTHP-DD-AT @ SWAP DUP >R MOVE _RTHP-DD-AT @ R> _RTHP-DD-AT +! ;

\ One control of the lane at INDEX, from KIND, STATE, the CR CC CH CW
\ rectangle and ORDINAL; INDEX moves on.
: _RTHP-DD-CONTROL! ( -- )
    _RTHP-DD-P @ _RTHP.CONTROLS-A @ _RTHP-DD-INDEX @ RTE-CONTROL-SIZE * +
        DUP _RTHP-DD-CONTROL ! RTE-CONTROL-SIZE 0 FILL
    _RTHP-DD-P @ _RTHP.CORR-A @ _RTHP-DD-INDEX @ RUCP-CORRELATION-SIZE * +
        DUP _RTHP-DD-CORR ! RUCP-CORRELATION-SIZE 0 FILL
    _RTHP-DD-P @ _RTHP.FIRST-OBJECT @ _RTHP-DD-INDEX @ + _RTHP-DD-ID !
    _RTHP-DD-P @ _RTHP.OWNER @ _RTHP-DD-CONTROL @ _RTE-CONTROL.OWNER !
    _RTHP-DD-P @ _RTHP.OWNER-GEN @ _RTHP-DD-CONTROL @ _RTE-CONTROL.GENERATION !
    _RTHP-DD-ID @ _RTHP-DD-CONTROL @ _RTE-CONTROL.ID !
    _RTHP-DD-KIND @ _RTHP-DD-CONTROL @ _RTE-CONTROL.KIND !
    _RTHP-DD-STATE @ _RTHP-DD-CONTROL @ _RTE-CONTROL.STATE !
    _RTHP-DD-Z @ _RTHP-DD-CONTROL @ _RTE-CONTROL.Z !
    _RTHP-DD-P @ _RTHP.REGION @ _RTHP-DD-CONTROL @ _RTE-CONTROL.REGION !
    _RTHP-DD-CR @ _RTHP-DD-CONTROL @ _RTE-CONTROL.ROW !
    _RTHP-DD-CC @ _RTHP-DD-CONTROL @ _RTE-CONTROL.COL !
    _RTHP-DD-CH @ _RTHP-DD-CONTROL @ _RTE-CONTROL.HEIGHT !
    _RTHP-DD-CW @ _RTHP-DD-CONTROL @ _RTE-CONTROL.WIDTH !
    _RTHP-DD-P @ _RTHP.ROWS @ _RTHP-DD-CONTROL @ _RTE-CONTROL.ROOT-HEIGHT !
    _RTHP-DD-P @ _RTHP.COLS @ _RTHP-DD-CONTROL @ _RTE-CONTROL.ROOT-WIDTH !
    _RTHP-DD-DOC @ RUHA-DOCUMENT-TOKEN@ _RTHP-DD-CORR @ _RUCP-X.ATTACHMENT !
    _RTHP-DD-DESC @ UDLSN-DESCRIPTOR-SOURCE@ _RTHP-DD-CORR @ _RUCP-X.SOURCE !
    _RTHP-DD-ORDINAL @ _RTHP-DD-CORR @ _RUCP-X.INDEX !
    _RTHP-DD-DESC @ UDLSN-DESCRIPTOR-KEY@ DUP _RTHP-DD-CORR @ _RUCP-X.SUBKEY !
        _RTHP-DD-CORR @ _RUCP-X.SCOPE !
    1 _RTHP-DD-CORR @ _RUCP-X.LIFECYCLE-GENERATION !
    _RTHP-DD-ID @ _RTHP-DD-CORR @ _RUCP-X.CONTROL-ID !
    1 _RTHP-DD-INDEX +! ;

: _RTHP-DD-LABEL! ( a u -- )
    DUP >R _RTHP-DD-COPY _RTHP-DD-CONTROL @ _RTE-CONTROL.LABEL-A !
    R> _RTHP-DD-CONTROL @ _RTE-CONTROL.LABEL-U ! ;

: _RTHP-DD-SHORTCUT! ( a u -- )
    DUP >R _RTHP-DD-COPY _RTHP-DD-CONTROL @ _RTE-CONTROL.SHORTCUT-A !
    R> _RTHP-DD-CONTROL @ _RTE-CONTROL.SHORTCUT-U ! ;

: _RTHP-DD-CONTENT! ( bytes -- )
    _RTHP-DD-AT @ _RTHP-DD-CONTROL @ _RTE-CONTROL.CONTENT-A !
    DUP _RTHP-DD-CONTROL @ _RTE-CONTROL.CONTENT-U ! _RTHP-DD-AT +! ;

: _RTHP-DD-BUTTONS! ( -- rte-status )
    RTE-CONTROL-BUTTON _RTHP-DD-KIND !
    _RTHP-DD-DESC @ UDLSN-DESCRIPTOR-Z@ _RTHP-DD-Z !
    _RTHP-DD-ENTRY @ UDLG-BUTTON-FIRST _RTHP-DD-BUTTON !
    _RTHP-DD-ENTRY @ UDLG-BUTTON-COUNT@ 0 ?DO
        _RTHP-DD-BUTTON @ UDLG-BUTTON-STATE@ UDLG-STATE-VISIBLE AND IF
            _RTHP-DD-BUTTON @ UDLG-BUTTON-STATE@ _RTHP-DD-BUTTON-STATE
                _RTHP-DD-STATE !
            _RTHP-DD-BUTTON @ UDLG-BUTTON-SLOT@ _RTHP-DD-CW ! _RTHP-DD-CH !
                _RTHP-DD-COL @ + _RTHP-DD-CC ! _RTHP-DD-ROW @ + _RTHP-DD-CR !
            I 1+ _RTHP-DD-ORDINAL !
            _RTHP-DD-CONTROL!
            _RTHP-DD-BUTTON @ UDLG-BUTTON-LABEL@ _RTHP-DD-LABEL!
            _RTHP-DD-BUTTON @ UDLG-BUTTON-SHORTCUT@ _RTHP-DD-SHORTCUT!
            _RTHP-DD-BUTTON @ _RTHP-DD-AT @ UDLGC-BUTTON-SIZE UDLGC-BUTTON-PACK
                0<> IF DROP RTE-S-INVALID UNLOOP EXIT THEN
            UDLGC-BUTTON-SIZE <> IF RTE-S-INVALID UNLOOP EXIT THEN
            UDLGC-BUTTON-SIZE _RTHP-DD-CONTENT!
        THEN
        _RTHP-DD-BUTTON @ UDLG-BUTTON-NEXT _RTHP-DD-BUTTON !
    LOOP RTE-S-OK ;

: _RTHP-DD-WRITE ( -- rte-status )
    _RTHP-DD-GEOMETRY? 0= IF
        _RTHP-DD-OVERLAP @ IF RTE-S-UNAVAILABLE ELSE RTE-S-OK THEN EXIT
    THEN
    _RTHP-DD-MEASURE DUP RTE-S-OK <> IF EXIT THEN DROP
    _RTHP-DD-P @ _RTHP.SOURCE-TEXT-A @ _RTHP-DD-P @ _RTHP.SOURCE-TEXT-USED @ +
        _RTHP-DD-AT !
    _RTHP-DD-P @ _RTHP.CONTROL-COUNT @ _RTHP-DD-INDEX !
    RTE-CONTROL-DIALOG _RTHP-DD-KIND ! RTE-CONTROL-VISIBLE _RTHP-DD-STATE !
    _RTHP-DD-DIALOG-Z _RTHP-DD-Z !
    _RTHP-DD-ROW @ _RTHP-DD-CR ! _RTHP-DD-COL @ _RTHP-DD-CC !
    _RTHP-DD-ROW1 @ _RTHP-DD-ROW @ - _RTHP-DD-CH !
    _RTHP-DD-COL1 @ _RTHP-DD-COL @ - _RTHP-DD-CW !
    0 _RTHP-DD-ORDINAL !
    _RTHP-DD-CONTROL!
    _RTHP-DD-ENTRY @ UDLG-TITLE@ _RTHP-DD-LABEL!
    _RTHP-DD-ENTRY @ DUP UDLG-BYTES@ _RTHP-DD-AT @ _RTHP-DD-CONTENT-U @
        UDLGC-DIALOG-PACK 0<> IF DROP RTE-S-INVALID EXIT THEN
    _RTHP-DD-CONTENT-U @ <> IF RTE-S-INVALID EXIT THEN
    _RTHP-DD-CONTENT-U @ _RTHP-DD-CONTENT!
    _RTHP-DD-ENTRY @ UDLG-MESSAGE-BYTES@
        _RTHP-DD-CONTROL @ _RTE-CONTROL.CONTENT-UTF8 !
    _RTHP-DD-BUTTONS! DUP RTE-S-OK <> IF EXIT THEN DROP
    _RTHP-DD-DOC @ RUHA-DOCUMENT-TOKEN@
    _RTHP-DD-P @ _RTHP.SOURCE-GEN @
    _RTHP-DD-DESC @ UDLSN-DESCRIPTOR-SOURCE@ 0
    _RTHP-DD-DESC @ UDLSN-DESCRIPTOR-KEY@ _RTHP-DD-DIALOG-Z
    _RTHP-DD-ROW @ _RTHP-DD-COL @ _RTHP-DD-ROW1 @ _RTHP-DD-COL1 @
    _RTHP-DD-P @ _RTHP.CLAIMS-A @ _RTHP-DD-P @ _RTHP.CLAIMS-USED @ +
        RUCL-ADMITTED-RECTANGLE! RUCL-S-OK <> IF RTE-S-INVALID EXIT THEN
    _RTHP-DD-AT @ _RTHP-DD-P @ _RTHP.SOURCE-TEXT-A @ -
        _RTHP-DD-P @ _RTHP.SOURCE-TEXT-USED !
    RUCL-CLAIM-SIZE _RTHP-DD-P @ _RTHP.CLAIMS-USED +!
    _RTHP-DD-INDEX @ _RTHP-DD-P @ _RTHP.CONTROL-COUNT @ -
        DUP _RTHP-DD-P @ _RTHP.DIALOG-CONTROLS +!
        _RTHP-DD-P @ _RTHP.CONTROL-COUNT +!
    1 _RTHP-DD-P @ _RTHP.DIALOG-COUNT +!
    _RTHP-DD-UTF8 @ _RTHP-DD-P @ _RTHP.DIALOG-UTF8 +!
    RTE-S-OK ;

: _RTHP-BUILD-DIALOGS ( producer -- rte-status )
    0 _RTHP-DD-OVERLAP !
    DUP _RTHP-DD-P ! DUP _RTHP-DIALOG-CLEAR
    DUP _RTHP.CONTROL-COUNT @ OVER _RTHP.DIALOG-BASE-CONTROLS !
    DUP _RTHP.SOURCE-TEXT-USED @ OVER _RTHP.DIALOG-BASE-TEXT !
    DUP _RTHP.CLAIMS-USED @ OVER _RTHP.DIALOG-BASE-CLAIMS !
    _RTHP.DIALOG-REFUSED @ IF RTE-S-OK EXIT THEN
    _RTHP-DD-P @ _RTHP.DOCUMENT-COUNT @ 0 ?DO
        I _RTHP-DD-P @ _RTHP-DOCUMENT-AT _RTHP-DD-DOC !
        _RTHP-DD-DOC @ RUHA-DOCUMENT-DIALOGS-DESCRIPTOR-BYTES@ IF
            _RTHP-DD-DOC @ RUHA-DOCUMENT-DIALOGS-DESCRIPTOR-OFFSET@
                UDLSN-DESCRIPTOR-SIZE _RTHP-U32+?
                0= IF DROP RTE-S-INVALID UNLOOP EXIT THEN
            _RTHP-DD-P @ _RTHP.DIALOG-DESCRIPTORS-USED @ U> IF
                RTE-S-INVALID UNLOOP EXIT
            THEN
            _RTHP-DD-DOC @ RUHA-DOCUMENT-DIALOGS-NATIVE-OFFSET@
            _RTHP-DD-DOC @ RUHA-DOCUMENT-DIALOGS-NATIVE-BYTES@ _RTHP-U32+?
                0= IF DROP RTE-S-INVALID UNLOOP EXIT THEN
            _RTHP-DD-P @ _RTHP.DIALOG-NATIVE-USED @ U> IF
                RTE-S-INVALID UNLOOP EXIT
            THEN
            _RTHP-DD-P @ _RTHP.DIALOG-DESCRIPTORS-A @
                _RTHP-DD-DOC @ RUHA-DOCUMENT-DIALOGS-DESCRIPTOR-OFFSET@ +
                _RTHP-DD-DESC !
            \ The slice is exactly one frozen dialog and its model.
            _RTHP-DD-DESC @ _RTHP-DD-DOC @ RUHA-DOCUMENT-DIALOGS-DESCRIPTOR-BYTES@
            _RTHP-DD-P @ _RTHP.DIALOG-NATIVE-A @
                _RTHP-DD-DOC @ RUHA-DOCUMENT-DIALOGS-NATIVE-OFFSET@ +
            _RTHP-DD-DOC @ RUHA-DOCUMENT-DIALOGS-NATIVE-BYTES@
            UDLSN-FROZEN-VALIDATE UDLSN-S-OK <> IF RTE-S-INVALID UNLOOP EXIT THEN
            _RTHP-DD-DESC @ _RTHP-DD-P @ _RTHP.DIALOG-NATIVE-A @
                _RTHP-DD-DOC @ RUHA-DOCUMENT-DIALOGS-NATIVE-OFFSET@ +
                UDLSN-DESCRIPTOR-NATIVE DROP _RTHP-DD-ENTRY !
            _RTHP-DD-WRITE DUP RTE-S-OK <> IF UNLOOP EXIT THEN DROP
        THEN
    LOOP
    _RTHP-DD-P @ _RTHP-W-P !
    _RTHP-W-WRAP-CONTROL-PLAN? 0= IF RTE-S-INVALID EXIT THEN
    _RTHP-DD-P @ _RTHP-FIELD-NEXT? 0= IF RTE-S-INVALID EXIT THEN
    RTE-S-OK ;

: _RTHP-W-BUILD-OPTIONAL-DIALOGS ( -- rte-status )
    _RTHP-W-P @ _RTHP-BUILD-DIALOGS
    DUP RTE-S-CAPACITY = OVER RTE-S-UNAVAILABLE = OR IF
        DROP _RTHP-W-P @ _RTHP-STRIP-DIALOGS? 0= IF RTE-S-INVALID EXIT THEN
        -1 _RTHP-W-P @ _RTHP.DIALOG-REFUSED !
        _RTHP-DD-OVERLAP @ 2 = IF RTE-S-UNAVAILABLE ELSE RTE-S-OK THEN
    THEN ;

\ ---------------------------------------------------------------------
\  Generic DATA_GRAPHICS -> retained INSTRUMENT family
\ ---------------------------------------------------------------------

VARIABLE _RTHP-W-INSTRUMENT-REGIONS
VARIABLE _RTHP-W-INSTRUMENTS
VARIABLE _RTHP-W-INSTRUMENT-UNITS
VARIABLE _RTHP-W-INSTRUMENT-CLAIMS
VARIABLE _RTHP-W-INSTRUMENT-LAST-REGION
VARIABLE _RTHP-W-INSTRUMENT-LAST
VARIABLE _RTHP-W-FIRST-INSTRUMENT-REGION
VARIABLE _RTHP-W-FIRST-INSTRUMENT
VARIABLE _RTHP-W-DOC-INSTRUMENT-REGIONS
VARIABLE _RTHP-W-DOC-INSTRUMENTS
VARIABLE _RTHP-W-DOC-INSTRUMENT-UNITS
VARIABLE _RTHP-W-DOC-INSTRUMENT-CLAIMS
VARIABLE _RTHP-W-DOC-LAST-INSTRUMENT-REGION
VARIABLE _RTHP-W-DOC-LAST-INSTRUMENT
VARIABLE _RTHP-W-RUIP-STATUS
VARIABLE _RTHP-W-SUFFIX-BASE
VARIABLE _RTHP-W-SUFFIX-CAP
VARIABLE _RTHP-W-SUFFIX-USED
VARIABLE _RTHP-W-OUT-INSTRUMENT-REGIONS-A
VARIABLE _RTHP-W-OUT-INSTRUMENT-REGIONS-U
VARIABLE _RTHP-W-OUT-INSTRUMENTS-A
VARIABLE _RTHP-W-OUT-INSTRUMENTS-U
VARIABLE _RTHP-W-OUT-INSTRUMENT-UNITS-A
VARIABLE _RTHP-W-OUT-INSTRUMENT-UNITS-U
VARIABLE _RTHP-W-OUT-INSTRUMENT-CORR-A
VARIABLE _RTHP-W-OUT-INSTRUMENT-CORR-U

: _RTHP-W-SUFFIX?
  ( base capacity used -- address remaining flag )
    _RTHP-W-SUFFIX-USED ! _RTHP-W-SUFFIX-CAP !
        _RTHP-W-SUFFIX-BASE !
    _RTHP-W-SUFFIX-USED @ _RTHP-W-SUFFIX-CAP @ U> IF
        0 0 0 EXIT
    THEN
    _RTHP-W-SUFFIX-CAP @ _RTHP-W-SUFFIX-USED @ - DUP 0= IF
        DROP 0 0 -1 EXIT
    THEN
    _RTHP-W-SUFFIX-BASE @ _RTHP-W-SUFFIX-USED @ _RTHP-U+?
        0= IF 2DROP 0 0 0 EXIT THEN
    SWAP -1 ;

: _RTHP-W-INSTRUMENT-FIRSTS?  ( -- flag )
    _RTHP-W-P @ _RTHP.REGION @ 1 _RTHP-U+?
        0= IF DROP 0 EXIT THEN
    _RTHP-W-INSTRUMENT-REGIONS @ _RTHP-U+?
        0= IF DROP 0 EXIT THEN DUP 0= IF DROP 0 EXIT THEN
        _RTHP-W-FIRST-INSTRUMENT-REGION !
    _RTHP-W-P @ _RTHP.FIRST-OBJECT @
    _RTHP-W-P @ _RTHP.CONTROL-COUNT @ _RTHP-U+?
        0= IF DROP 0 EXIT THEN
    _RTHP-W-INSTRUMENTS @ _RTHP-U+?
        0= IF DROP 0 EXIT THEN DUP 0= IF DROP 0 EXIT THEN
        _RTHP-W-FIRST-INSTRUMENT !
    -1 ;

: _RTHP-W-INSTRUMENT-OUTPUTS?  ( -- flag )
    _RTHP-W-INSTRUMENT-REGIONS @ RTE-INSTRUMENT-REGION-SIZE
        _RTHP-U32*? 0= IF DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.INSTRUMENT-REGIONS-A @
    _RTHP-W-P @ _RTHP.INSTRUMENT-REGIONS-U @ ROT
        _RTHP-W-SUFFIX? 0= IF 2DROP 0 EXIT THEN
        _RTHP-W-OUT-INSTRUMENT-REGIONS-U !
        _RTHP-W-OUT-INSTRUMENT-REGIONS-A !
    _RTHP-W-INSTRUMENTS @ RTE-INSTRUMENT-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.INSTRUMENTS-A @
    _RTHP-W-P @ _RTHP.INSTRUMENTS-U @ ROT
        _RTHP-W-SUFFIX? 0= IF 2DROP 0 EXIT THEN
        _RTHP-W-OUT-INSTRUMENTS-U !
        _RTHP-W-OUT-INSTRUMENTS-A !
    _RTHP-W-P @ _RTHP.INSTRUMENT-UNITS-A @
    _RTHP-W-P @ _RTHP.INSTRUMENT-UNITS-U @
    _RTHP-W-INSTRUMENT-UNITS @ _RTHP-W-SUFFIX?
        0= IF 2DROP 0 EXIT THEN
        _RTHP-W-OUT-INSTRUMENT-UNITS-U !
        _RTHP-W-OUT-INSTRUMENT-UNITS-A !
    _RTHP-W-INSTRUMENTS @ RUIP-CORRELATION-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.INSTRUMENT-CORR-A @
    _RTHP-W-P @ _RTHP.INSTRUMENT-CORR-U @ ROT
        _RTHP-W-SUFFIX? 0= IF 2DROP 0 EXIT THEN
        _RTHP-W-OUT-INSTRUMENT-CORR-U !
        _RTHP-W-OUT-INSTRUMENT-CORR-A !
    _RTHP-W-CLAIM-OUTPUT? ;

\ SERIES has its own namespace and copied immutable samples.  The summary
\ below is recomputed from the owned records, never inferred from graph text.
VARIABLE _RTHP-SQ-P
VARIABLE _RTHP-SQ-R
VARIABLE _RTHP-SQ-OFF
VARIABLE _RTHP-SQ-SLOTS
VARIABLE _RTHP-SQ-HISTORY
VARIABLE _RTHP-SQ-CHUNKS
VARIABLE _RTHP-SQ-MAX
VARIABLE _RTHP-SQ-BYTES
VARIABLE _RTHP-SQ-WAVES
VARIABLE _RTHP-SQ-N
VARIABLE _RTHP-SQ-Q
VARIABLE _RTHP-SQ-STRIDE

: _RTHP-SERIES-CLEAR ( producer -- )
    DUP _RTHP.SERIES-COUNT 8 8 * 0 FILL
    0 OVER _RTHP.SERIES-SAMPLES-USED !
    0 OVER _RTHP.OMITTED-GRAPHS-USED !
    _RTHP.SERIES-PLAN RTE-SERIES-PLAN-SIZE 0 FILL ;

: _RTHP-SERIES-SUMMARY? ( producer -- flag )
    _RTHP-SQ-P !
    0 _RTHP-SQ-OFF ! 0 _RTHP-SQ-SLOTS ! 0 _RTHP-SQ-HISTORY !
    0 _RTHP-SQ-CHUNKS ! 0 _RTHP-SQ-MAX ! 0 _RTHP-SQ-BYTES !
    0 _RTHP-SQ-WAVES !
    _RTHP-SQ-P @ _RTHP.SERIES-COUNT @ _RTHP-SQ-P @ _RTHP.MAX-SERIES @ U> IF 0 EXIT THEN
    _RTHP-SQ-P @ _RTHP.SERIES-A @ 7 AND
    _RTHP-SQ-P @ _RTHP.SERIES-CORR-A @ 7 AND OR
    _RTHP-SQ-P @ _RTHP.SERIES-SAMPLES-A @ 7 AND OR IF 0 EXIT THEN
    _RTHP-SQ-P @ _RTHP.SERIES-COUNT @ RTE-SERIES-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-SQ-P @ _RTHP.SERIES-U @ U> IF DROP 0 EXIT THEN
    _RTHP-SQ-P @ _RTHP.SERIES-A @ SWAP _RTHP-SQ-P @ _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    _RTHP-SQ-P @ _RTHP.SERIES-COUNT @ _RTHP-SERIES-CORR-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-SQ-P @ _RTHP.SERIES-CORR-U @ U> IF DROP 0 EXIT THEN
    _RTHP-SQ-P @ _RTHP.SERIES-CORR-A @ SWAP _RTHP-SQ-P @ _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    _RTHP-SQ-P @ _RTHP.SERIES-SAMPLES-USED @ DUP 7 AND IF DROP 0 EXIT THEN
    DUP _RTHP-SQ-P @ _RTHP.SERIES-SAMPLES-U @ U> IF DROP 0 EXIT THEN
    _RTHP-SQ-P @ _RTHP.SERIES-SAMPLES-A @ SWAP
        _RTHP-SQ-P @ _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    _RTHP-SQ-P @ _RTHP.INSTRUMENT-COUNT @
        DUP _RTHP-SQ-P @ _RTHP.MAX-INSTRUMENTS @ U> IF DROP 0 EXIT THEN
    RTE-INSTRUMENT-SIZE _RTHP-U32*? 0= IF DROP 0 EXIT THEN
    DUP _RTHP-SQ-P @ _RTHP.INSTRUMENTS-U @ U> IF DROP 0 EXIT THEN
    _RTHP-SQ-P @ _RTHP.INSTRUMENTS-A @ SWAP
        _RTHP-SQ-P @ _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    _RTHP-SQ-P @ _RTHP.SERIES-COUNT @ 0 ?DO
        _RTHP-SQ-P @ _RTHP.SERIES-A @ I RTE-SERIES-SIZE * + _RTHP-SQ-R !
        _RTHP-SQ-R @ _RTE-SERIES.OWNER @ _RTHP-SQ-P @ _RTHP.OWNER @ <>
        _RTHP-SQ-R @ _RTE-SERIES.GENERATION @ _RTHP-SQ-P @ _RTHP.OWNER-GEN @ <> OR IF 0 UNLOOP EXIT THEN
        _RTHP-SQ-P @ _RTHP.FIRST-SERIES @ I _RTHP-U+? 0= IF DROP 0 UNLOOP EXIT THEN
        _RTHP-SQ-R @ _RTE-SERIES.ID @ <> IF 0 UNLOOP EXIT THEN
        _RTHP-SQ-R @ _RTE-SERIES.SAMPLES-U @ DUP IF
            _RTHP-SQ-P @ _RTHP.SERIES-SAMPLES-A @ _RTHP-SQ-OFF @ +
            _RTHP-SQ-R @ _RTE-SERIES.SAMPLES-A @ <> IF DROP 0 UNLOOP EXIT THEN
        ELSE
            _RTHP-SQ-R @ _RTE-SERIES.SAMPLES-A @ IF DROP 0 UNLOOP EXIT THEN
        THEN
        _RTHP-SQ-OFF @ _RTHP-U32+? 0= IF DROP 0 UNLOOP EXIT THEN
        DUP _RTHP-SQ-P @ _RTHP.SERIES-SAMPLES-USED @ U> IF DROP 0 UNLOOP EXIT THEN _RTHP-SQ-OFF !
        _RTHP-SQ-R @ RTE-SERIES-VALID? 0= IF 0 UNLOOP EXIT THEN
        _RTHP-SQ-SLOTS @ _RTHP-SQ-R @ _RTE-SERIES.CAPACITY @ _RTHP-U32+?
            0= IF DROP 0 UNLOOP EXIT THEN _RTHP-SQ-SLOTS !
        _RTHP-SQ-R @ _RTE-SERIES.CAPACITY @ _RTHP-SQ-HISTORY @ MAX _RTHP-SQ-HISTORY !
        _RTHP-SQ-R @ _RTE-SERIES.MODE @ IF 8 ELSE 16 THEN _RTHP-SQ-STRIDE !
        _RTHP-SQ-R @ _RTE-SERIES.SAMPLES-U @ _RTHP-SQ-STRIDE @ / _RTHP-SQ-N !
        _RTHP-SQ-R @ _RTE-SERIES.CHUNK-SAMPLES @ _RTHP-SQ-Q !
        _RTHP-SQ-Q @ _RTHP-SQ-MAX @ MAX _RTHP-SQ-MAX !
        _RTHP-SQ-N @ _RTHP-SQ-Q @ MIN _RTHP-SQ-STRIDE @ *
            _RTHP-SQ-BYTES @ MAX _RTHP-SQ-BYTES !
        _RTHP-SQ-N @ IF _RTHP-SQ-N @ _RTHP-SQ-Q @ /MOD SWAP IF 1+ THEN ELSE 0 THEN
        _RTHP-SQ-CHUNKS @ _RTHP-U32+? 0= IF DROP 0 UNLOOP EXIT THEN _RTHP-SQ-CHUNKS !
    LOOP
    _RTHP-SQ-OFF @ _RTHP-SQ-P @ _RTHP.SERIES-SAMPLES-USED @ <> IF 0 EXIT THEN
    _RTHP-SQ-P @ _RTHP.INSTRUMENT-COUNT @ 0 ?DO
        _RTHP-SQ-P @ _RTHP.INSTRUMENTS-A @ I RTE-INSTRUMENT-SIZE * +
        _RTE-INSTRUMENT.KIND @ RTE-INSTRUMENT-WAVEFORM = IF 1 _RTHP-SQ-WAVES +! THEN
    LOOP -1 ;

: _RTHP-SERIES-SUMMARY! ( -- )
    _RTHP-SQ-SLOTS @ _RTHP-SQ-P @ _RTHP.SERIES-SLOTS !
    _RTHP-SQ-HISTORY @ _RTHP-SQ-P @ _RTHP.SERIES-HISTORY-MAX !
    _RTHP-SQ-CHUNKS @ _RTHP-SQ-P @ _RTHP.SERIES-CHUNKS !
    _RTHP-SQ-MAX @ _RTHP-SQ-P @ _RTHP.SERIES-CHUNK-MAX !
    _RTHP-SQ-BYTES @ _RTHP-SQ-P @ _RTHP.SERIES-CHUNK-BYTES-MAX !
    _RTHP-SQ-WAVES @ _RTHP-SQ-P @ _RTHP.WAVEFORM-COUNT ! ;

: _RTHP-W-SERIES-REQUEST? ( -- flag )
    _RTHP-W-P @ _RTHP.FIRST-SERIES @ _RTHP-W-P @ _RTHP.SERIES-COUNT @ _RTHP-U+?
        0= IF DROP 0 EXIT THEN DUP 0= IF DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.LIMITS
    _RTHP-W-P @ _RTHP.SERIES-COUNT @ _RTHP-W-P @ _RTHP.SERIES-SLOTS @
    _RTHP-W-P @ _RTHP.RUIP-Q RUIP-REQUEST-SERIES-IDENTITY!
    _RTHP-W-P @ _RTHP.SERIES-PLAN RTE-SERIES-PLAN-SIZE
    _RTHP-W-P @ _RTHP.SERIES-A @ _RTHP-W-P @ _RTHP.SERIES-U @
    _RTHP-W-P @ _RTHP.SERIES-COUNT @ RTE-SERIES-SIZE * _RTHP-W-SUFFIX?
        0= IF 2DROP 2DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.RUIP-Q RUIP-REQUEST-SERIES-PLAN!
    _RTHP-W-P @ _RTHP.SERIES-SAMPLES-A @ _RTHP-W-P @ _RTHP.SERIES-SAMPLES-U @
    _RTHP-W-P @ _RTHP.SERIES-SAMPLES-USED @ _RTHP-W-SUFFIX? 0= IF 2DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.SERIES-CORR-A @ _RTHP-W-P @ _RTHP.SERIES-CORR-U @
    _RTHP-W-P @ _RTHP.SERIES-COUNT @ _RTHP-SERIES-CORR-SIZE * _RTHP-W-SUFFIX?
        0= IF 2DROP 2DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.OMITTED-GRAPHS-A @ _RTHP-W-P @ _RTHP.OMITTED-GRAPHS-U @
    _RTHP-W-P @ _RTHP.OMITTED-GRAPHS-USED @ _RTHP-W-SUFFIX?
        0= IF 2DROP 2DROP 2DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.RUIP-Q RUIP-REQUEST-SERIES-AUXILIARY!
    -1 ;

VARIABLE _RTHP-OG-N
VARIABLE _RTHP-OG-A
VARIABLE _RTHP-OG-D
VARIABLE _RTHP-OG-R
VARIABLE _RTHP-OG-C
VARIABLE _RTHP-OG-Y1
VARIABLE _RTHP-OG-X1
VARIABLE _RTHP-OG-P
VARIABLE _RTHP-OG-CLAIM

\ Expand ordinal scratch backwards so no unread ordinal is overwritten.
\ Rectangles describe omitted ordinary painting and never enter the claims.
: _RTHP-W-OMITTED-GRAPHS? ( -- flag )
    _RTHP-W-P @ _RTHP.RUIP-Q RUIP-REQUEST-OMITTED-COUNT@ _RTHP-OG-N !
    _RTHP-OG-N @ _RTHP-OMITTED-GRAPH-SIZE _RTHP-U32*? 0= IF DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.OMITTED-GRAPHS-USED @ _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    DUP _RTHP-W-P @ _RTHP.OMITTED-GRAPHS-U @ U> IF DROP 0 EXIT THEN >R
    _RTHP-W-P @ _RTHP.OMITTED-GRAPHS-A @
        _RTHP-W-P @ _RTHP.OMITTED-GRAPHS-USED @ + _RTHP-OG-A !
    BEGIN _RTHP-OG-N @ WHILE
        -1 _RTHP-OG-N +!
        _RTHP-OG-A @ _RTHP-OG-N @ 8 * + @
        DUP _RTHP-W-DOC-DGRAPH-DESCRIPTOR-U @ UDGSN-DESCRIPTOR-SIZE / U< 0= IF DROP R> DROP 0 EXIT THEN
        UDGSN-DESCRIPTOR-SIZE * _RTHP-W-P @ _RTHP.DGRAPH-DESCRIPTORS-A @ +
            _RTHP-W-DOC-DGRAPH-DESCRIPTOR-O @ + _RTHP-OG-D !
        _RTHP-OG-D @ UDGSN-DESCRIPTOR-CLIP-ROW@ 0 MAX _RTHP-OG-R !
        _RTHP-OG-D @ UDGSN-DESCRIPTOR-CLIP-COLUMN@ 0 MAX _RTHP-OG-C !
        _RTHP-OG-D @ UDGSN-DESCRIPTOR-CLIP-ROW@
        _RTHP-OG-D @ UDGSN-DESCRIPTOR-CLIP-HEIGHT@ +
            _RTHP-W-P @ _RTHP.ROWS @ MIN 0 MAX _RTHP-OG-Y1 !
        _RTHP-OG-D @ UDGSN-DESCRIPTOR-CLIP-COLUMN@
        _RTHP-OG-D @ UDGSN-DESCRIPTOR-CLIP-WIDTH@ +
            _RTHP-W-P @ _RTHP.COLS @ MIN 0 MAX _RTHP-OG-X1 !
        _RTHP-OG-A @ _RTHP-OG-N @ _RTHP-OMITTED-GRAPH-SIZE * + DUP
        _RTHP-OG-R @ OVER ! _RTHP-OG-C @ OVER 8 + !
        _RTHP-OG-Y1 @ OVER 16 + ! _RTHP-OG-X1 @ OVER 24 + !
        _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-TOKEN@ SWAP 32 + ! DROP
    REPEAT R> _RTHP-W-P @ _RTHP.OMITTED-GRAPHS-USED ! -1 ;

: _RTHP-W-SERIES-ACCUMULATE? ( -- flag )
    _RTHP-W-P @ _RTHP.SERIES-COUNT @
    _RTHP-W-P @ _RTHP.RUIP-Q RUIP-REQUEST-SERIES-COUNT@ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN DUP _RTHP-W-P @ _RTHP.MAX-SERIES @ U> IF DROP 0 EXIT THEN
        _RTHP-W-P @ _RTHP.SERIES-COUNT !
    _RTHP-W-P @ _RTHP.SERIES-SAMPLES-USED @
    _RTHP-W-P @ _RTHP.RUIP-Q RUIP-REQUEST-SAMPLE-BYTES@ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN DUP _RTHP-W-P @ _RTHP.SERIES-SAMPLES-U @ U> IF DROP 0 EXIT THEN
        _RTHP-W-P @ _RTHP.SERIES-SAMPLES-USED !
    _RTHP-W-P @ _RTHP.SERIES-SLOTS @
    _RTHP-W-P @ _RTHP.RUIP-Q RUIP-REQUEST-SAMPLE-SLOTS@ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN _RTHP-W-P @ _RTHP.SERIES-SLOTS !
    _RTHP-W-P @ _RTHP.RUIP-Q RUIP-REQUEST-SERIES-COUNT@ IF
        _RTHP-W-P @ _RTHP.FIRST-SERIES @ _RTHP-W-P @ _RTHP.SERIES-COUNT @ 1- _RTHP-U+?
            0= IF DROP 0 EXIT THEN
        DUP _RTHP-W-P @ _RTHP.RUIP-Q RUIP-REQUEST-LAST-SERIES@ <> IF DROP 0 EXIT THEN
        _RTHP-W-P @ _RTHP.SERIES-LAST !
    THEN _RTHP-W-OMITTED-GRAPHS? ;

: _RTHP-W-WRAP-SERIES? ( -- flag )
    _RTHP-W-P @ _RTHP.SERIES-PLAN RTE-SERIES-PLAN-SIZE 0 FILL
    _RTHP-W-P @ _RTHP-SERIES-SUMMARY? 0= IF 0 EXIT THEN _RTHP-SERIES-SUMMARY!
    _RTHP-W-P @ _RTHP.SERIES-COUNT @ 0= IF -1 EXIT THEN
    _RTHP-W-P @ _RTHP.OWNER @ _RTHP-W-P @ _RTHP.SERIES-PLAN _RTE-SRP.OWNER !
    _RTHP-W-P @ _RTHP.OWNER-GEN @ _RTHP-W-P @ _RTHP.SERIES-PLAN _RTE-SRP.GENERATION !
    _RTHP-W-P @ _RTHP.COLS @ _RTHP-W-P @ _RTHP.SERIES-PLAN _RTE-SRP.SURFACE-COLS !
    _RTHP-W-P @ _RTHP.ROWS @ _RTHP-W-P @ _RTHP.SERIES-PLAN _RTE-SRP.SURFACE-ROWS !
    _RTHP-W-P @ _RTHP.SERIES-A @ _RTHP-W-P @ _RTHP.SERIES-PLAN _RTE-SRP.ITEMS-A !
    _RTHP-W-P @ _RTHP.SERIES-COUNT @ RTE-SERIES-SIZE *
        _RTHP-W-P @ _RTHP.SERIES-PLAN _RTE-SRP.ITEMS-U ! -1 ;

\ The claim just met lies in a layer above the omitted graph's document,
\ which paints over the graph in CELL too.
: _RTHP-OG-ABOVE? ( -- flag )
    _RTHP-OG-CLAIM @ RUCL-CLAIM-ATTACHMENT@ _RTHP-OG-P @ _RTHP-LAYER-OF
    _RTHP-OG-A @ 32 + @ _RTHP-OG-P @ _RTHP-LAYER-OF > ;

: _RTHP-OMITTED-DISJOINT? ( producer -- flag )
    _RTHP-OG-P !
    _RTHP-OG-P @ _RTHP.OMITTED-GRAPHS-USED @ _RTHP-OMITTED-GRAPH-SIZE / 0 ?DO
        _RTHP-OG-P @ _RTHP.OMITTED-GRAPHS-A @ I _RTHP-OMITTED-GRAPH-SIZE * + _RTHP-OG-A !
        _RTHP-OG-A @ @ _RTHP-OG-A @ 16 + @ <
        _RTHP-OG-A @ 8 + @ _RTHP-OG-A @ 24 + @ < AND IF
            _RTHP-OG-P @ _RTHP.CLAIMS-USED @ RUCL-CLAIM-SIZE / 0 ?DO
                _RTHP-OG-P @ _RTHP.CLAIMS-A @ I RUCL-CLAIM-SIZE * + _RTHP-OG-CLAIM !
                _RTHP-OG-A @ @ _RTHP-OG-CLAIM @ RUCL-CLAIM-ROW1@ <
                _RTHP-OG-A @ 16 + @ _RTHP-OG-CLAIM @ RUCL-CLAIM-ROW0@ > AND
                _RTHP-OG-A @ 8 + @ _RTHP-OG-CLAIM @ RUCL-CLAIM-COL1@ < AND
                _RTHP-OG-A @ 24 + @ _RTHP-OG-CLAIM @ RUCL-CLAIM-COL0@ > AND
                _RTHP-OG-ABOVE? 0= AND IF
                    0 UNLOOP UNLOOP EXIT
                THEN
            LOOP
        THEN
    LOOP -1 ;

: _RTHP-W-RUIP-REQUEST?  ( -- flag )
    _RTHP-W-INSTRUMENT-FIRSTS? 0= IF 0 EXIT THEN
    _RTHP-W-INSTRUMENT-OUTPUTS? 0= IF 0 EXIT THEN
    _RTHP-W-P @ _RTHP.RUIP-Q RUIP-REQUEST-CLEAR
    _RTHP-W-DOCUMENT @ RUHA-DOCUMENT-TOKEN@
    _RTHP-W-P @ _RTHP.OWNER @ _RTHP-W-P @ _RTHP.OWNER-GEN @
    _RTHP-W-FIRST-INSTRUMENT-REGION @
    _RTHP-W-FIRST-INSTRUMENT @
    _RTHP-W-P @ _RTHP.RUIP-Q RUIP-REQUEST-IDENTITY!
    _RTHP-W-P @ _RTHP.COLS @ _RTHP-W-P @ _RTHP.ROWS @
    _RTHP-W-P @ _RTHP.RUIP-Q RUIP-REQUEST-SURFACE!
    _RTHP-W-P @ _RTHP.DGRAPH-DESCRIPTORS-A @
        _RTHP-W-DOC-DGRAPH-DESCRIPTOR-O @ +
    _RTHP-W-DOC-DGRAPH-DESCRIPTOR-U @
    _RTHP-W-P @ _RTHP.DGRAPH-NATIVE-A @
        _RTHP-W-DOC-DGRAPH-NATIVE-O @ +
    _RTHP-W-DOC-DGRAPH-NATIVE-U @
    _RTHP-W-P @ _RTHP.RUIP-Q RUIP-REQUEST-SOURCE!
    _RTHP-W-P @ _RTHP.INSTRUMENT-PLAN RTE-INSTRUMENT-PLAN-SIZE
    _RTHP-W-OUT-INSTRUMENT-REGIONS-A @
        _RTHP-W-OUT-INSTRUMENT-REGIONS-U @
    _RTHP-W-OUT-INSTRUMENTS-A @ _RTHP-W-OUT-INSTRUMENTS-U @
    _RTHP-W-P @ _RTHP.RUIP-Q RUIP-REQUEST-PLAN!
    _RTHP-W-OUT-INSTRUMENT-UNITS-A @
        _RTHP-W-OUT-INSTRUMENT-UNITS-U @
    _RTHP-W-OUT-CLAIMS-A @ _RTHP-W-OUT-CLAIMS-U @
    _RTHP-W-OUT-INSTRUMENT-CORR-A @
        _RTHP-W-OUT-INSTRUMENT-CORR-U @
    _RTHP-W-P @ _RTHP.RUIP-Q RUIP-REQUEST-AUXILIARY!
    _RTHP-W-SERIES-REQUEST? ;

: _RTHP-W-RUIP-IDS?  ( -- flag )
    _RTHP-W-DOC-INSTRUMENTS @ 0= IF
        _RTHP-W-DOC-INSTRUMENT-REGIONS @
        _RTHP-W-DOC-INSTRUMENT-UNITS @ OR
        _RTHP-W-DOC-INSTRUMENT-CLAIMS @ OR
        _RTHP-W-DOC-LAST-INSTRUMENT-REGION @ OR
        _RTHP-W-DOC-LAST-INSTRUMENT @ OR 0= EXIT
    THEN
    _RTHP-W-DOC-INSTRUMENT-REGIONS @ 0= IF 0 EXIT THEN
    _RTHP-W-FIRST-INSTRUMENT @
    _RTHP-W-DOC-INSTRUMENTS @ 1- _RTHP-U+?
        0= IF DROP 0 EXIT THEN
    _RTHP-W-DOC-LAST-INSTRUMENT @ <> IF 0 EXIT THEN
    _RTHP-W-FIRST-INSTRUMENT-REGION @
    _RTHP-W-DOC-INSTRUMENT-REGIONS @ 1- _RTHP-U+?
        0= IF DROP 0 EXIT THEN
    _RTHP-W-DOC-LAST-INSTRUMENT-REGION @ = ;

: _RTHP-W-RUIP-ACCUMULATE?  ( -- flag )
    _RTHP-W-SERIES-ACCUMULATE? 0= IF 0 EXIT THEN
    _RTHP-W-RUIP-IDS? 0= IF 0 EXIT THEN
    _RTHP-W-INSTRUMENT-REGIONS @
    _RTHP-W-DOC-INSTRUMENT-REGIONS @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-W-P @ _RTHP.MAX-INSTRUMENT-REGIONS @ U> IF
        DROP 0 EXIT
    THEN _RTHP-W-INSTRUMENT-REGIONS !
    _RTHP-W-INSTRUMENTS @ _RTHP-W-DOC-INSTRUMENTS @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-W-P @ _RTHP.MAX-INSTRUMENTS @ U> IF DROP 0 EXIT THEN
        _RTHP-W-INSTRUMENTS !
    _RTHP-W-INSTRUMENT-UNITS @
    _RTHP-W-DOC-INSTRUMENT-UNITS @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-W-P @ _RTHP.INSTRUMENT-UNITS-U @ U> IF DROP 0 EXIT THEN
        _RTHP-W-INSTRUMENT-UNITS !
    _RTHP-W-INSTRUMENT-CLAIMS @
    _RTHP-W-DOC-INSTRUMENT-CLAIMS @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN _RTHP-W-INSTRUMENT-CLAIMS !
    _RTHP-W-CLAIMS @ _RTHP-W-DOC-INSTRUMENT-CLAIMS @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    DUP RUCL-CLAIM-SIZE _RTHP-U32*?
        0= IF 2DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.CLAIMS-U @ U> IF DROP 0 EXIT THEN
        _RTHP-W-CLAIMS !
    _RTHP-W-DOC-INSTRUMENTS @ IF
        _RTHP-W-DOC-LAST-INSTRUMENT-REGION @
            _RTHP-W-INSTRUMENT-LAST-REGION !
        _RTHP-W-DOC-LAST-INSTRUMENT @ _RTHP-W-INSTRUMENT-LAST !
    THEN
    -1 ;

: _RTHP-W-WRAP-INSTRUMENT-PLAN?  ( -- flag )
    _RTHP-W-P @ _RTHP.INSTRUMENT-PLAN
        RTE-INSTRUMENT-PLAN-SIZE 0 FILL
    _RTHP-W-INSTRUMENTS @ 0= IF
        _RTHP-W-INSTRUMENT-REGIONS @ _RTHP-W-INSTRUMENT-UNITS @ OR
        _RTHP-W-INSTRUMENT-CLAIMS @ OR
        _RTHP-W-INSTRUMENT-LAST-REGION @ OR
        _RTHP-W-INSTRUMENT-LAST @ OR 0= EXIT
    THEN
    _RTHP-W-P @ _RTHP.OWNER @
        _RTHP-W-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.OWNER !
    _RTHP-W-P @ _RTHP.OWNER-GEN @
        _RTHP-W-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.GENERATION !
    _RTHP-W-P @ _RTHP.COLS @
        _RTHP-W-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.SURFACE-COLS !
    _RTHP-W-P @ _RTHP.ROWS @
        _RTHP-W-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.SURFACE-ROWS !
    _RTHP-W-P @ _RTHP.INSTRUMENT-REGIONS-A @
        _RTHP-W-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.REGIONS-A !
    _RTHP-W-INSTRUMENT-REGIONS @ RTE-INSTRUMENT-REGION-SIZE *
        _RTHP-W-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.REGIONS-U !
    _RTHP-W-P @ _RTHP.INSTRUMENTS-A @
        _RTHP-W-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.ITEMS-A !
    _RTHP-W-INSTRUMENTS @ RTE-INSTRUMENT-SIZE *
        _RTHP-W-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.ITEMS-U !
    -1 ;

: _RTHP-BUILD-INSTRUMENTS  ( producer -- rte-status )
    DUP _RTHP-SERIES-CLEAR _RTHP-W-P !
    0 _RTHP-W-INSTRUMENT-REGIONS ! 0 _RTHP-W-INSTRUMENTS !
    0 _RTHP-W-INSTRUMENT-UNITS ! 0 _RTHP-W-INSTRUMENT-CLAIMS !
    0 _RTHP-W-INSTRUMENT-LAST-REGION ! 0 _RTHP-W-INSTRUMENT-LAST !
    _RTHP-W-P @ _RTHP.CLAIMS-USED @ DUP
        _RTHP-W-P @ _RTHP.BASE-CLAIMS-USED !
    DUP RUCL-CLAIM-SIZE MOD IF DROP RTE-S-INVALID EXIT THEN
        RUCL-CLAIM-SIZE / _RTHP-W-CLAIMS !
    _RTHP-W-COPIED-BEGIN
    BEGIN _RTHP-W-DOCUMENT-I @
        _RTHP-W-P @ _RTHP.DOCUMENT-COUNT @ U< WHILE
        _RTHP-W-COPIED-DOCUMENT? 0= IF RTE-S-INVALID EXIT THEN
        _RTHP-W-DOC-DGRAPH-DESCRIPTOR-U @ IF
            _RTHP-W-RUIP-REQUEST? 0= IF RTE-S-INVALID EXIT THEN
            _RTHP-W-P @ _RTHP.RUIP-Q RUIP-BUILD
            _RTHP-W-RUIP-STATUS ! _RTHP-W-DOC-LAST-INSTRUMENT !
            _RTHP-W-DOC-LAST-INSTRUMENT-REGION !
            _RTHP-W-DOC-INSTRUMENT-CLAIMS !
            _RTHP-W-DOC-INSTRUMENT-UNITS !
            _RTHP-W-DOC-INSTRUMENTS !
            _RTHP-W-DOC-INSTRUMENT-REGIONS !
            _RTHP-W-RUIP-STATUS @ RUIP-S-CAPACITY = IF
                RTE-S-CAPACITY EXIT
            THEN
            _RTHP-W-RUIP-STATUS @ RUIP-S-OK <> IF RTE-S-INVALID EXIT THEN
            _RTHP-W-RUIP-ACCUMULATE? 0= IF RTE-S-INVALID EXIT THEN
        THEN
        1 _RTHP-W-DOCUMENT-I +!
    REPEAT
    _RTHP-W-COPIED-COMPLETE? 0= IF RTE-S-INVALID EXIT THEN
    _RTHP-W-INSTRUMENTS @ _RTHP-W-P @ _RTHP.INSTRUMENT-COUNT !
    _RTHP-W-INSTRUMENT-REGIONS @
        _RTHP-W-P @ _RTHP.INSTRUMENT-REGION-COUNT !
    _RTHP-W-INSTRUMENT-UNITS @
        _RTHP-W-P @ _RTHP.INSTRUMENT-UNITS-USED !
    _RTHP-W-INSTRUMENT-CLAIMS @
        _RTHP-W-P @ _RTHP.INSTRUMENT-CLAIM-COUNT !
    _RTHP-W-INSTRUMENT-LAST-REGION @
        _RTHP-W-P @ _RTHP.INSTRUMENT-LAST-REGION !
    _RTHP-W-INSTRUMENT-LAST @ _RTHP-W-P @ _RTHP.INSTRUMENT-LAST !
    _RTHP-W-CLAIMS @ RUCL-CLAIM-SIZE _RTHP-U32*?
        0= IF DROP RTE-S-INVALID EXIT THEN
        _RTHP-W-P @ _RTHP.CLAIMS-USED !
    _RTHP-W-WRAP-INSTRUMENT-PLAN? 0= IF RTE-S-INVALID EXIT THEN
    _RTHP-W-WRAP-SERIES? 0= IF RTE-S-INVALID EXIT THEN
    _RTHP-W-P @ _RTHP.FIRST-OBJECT @
    _RTHP-W-P @ _RTHP.CONTROL-COUNT @ _RTHP-U+?
        0= IF DROP RTE-S-INVALID EXIT THEN
    _RTHP-W-INSTRUMENTS @ _RTHP-U+?
        0= IF DROP RTE-S-INVALID EXIT THEN
    DUP 0= IF DROP RTE-S-INVALID EXIT THEN _RTHP-W-GLYPH-FIRST !
    RTE-S-OK ;

: _RTHP-W-STRIP-INSTRUMENTS?  ( -- flag )
    _RTHP-W-P @ _RTHP-SERIES-CLEAR
    _RTHP-W-P @ _RTHP.INSTRUMENT-PLAN
        RTE-INSTRUMENT-PLAN-SIZE 0 FILL
    0 _RTHP-W-P @ _RTHP.INSTRUMENT-REGION-COUNT !
    0 _RTHP-W-P @ _RTHP.INSTRUMENT-COUNT !
    0 _RTHP-W-P @ _RTHP.INSTRUMENT-UNITS-USED !
    0 _RTHP-W-P @ _RTHP.INSTRUMENT-CLAIM-COUNT !
    0 _RTHP-W-P @ _RTHP.INSTRUMENT-LAST-REGION !
    0 _RTHP-W-P @ _RTHP.INSTRUMENT-LAST !
    _RTHP-W-P @ _RTHP.FIRST-OBJECT @
    _RTHP-W-P @ _RTHP.CONTROL-COUNT @ _RTHP-U+?
        0= IF DROP 0 EXIT THEN DUP 0= IF DROP 0 EXIT THEN
        _RTHP-W-GLYPH-FIRST !
    -1 ;

\ Restore the exact base claim prefix after an optional instrument attempt has
\ appended any tentative claims.  Instrument construction is suffix-only, so
\ shrinking the authoritative used extent is sufficient; stale bytes outside
\ it carry no authority and the base planner need not run again.
: _RTHP-W-RESTORE-BASE-CLAIMS?  ( -- flag )
    _RTHP-W-STRIP-INSTRUMENTS? 0= IF 0 EXIT THEN
    _RTHP-W-P @ _RTHP.BASE-CLAIMS-USED @
    DUP RUCL-CLAIM-SIZE MOD IF DROP 0 EXIT THEN
    DUP _RTHP-W-P @ _RTHP.CLAIMS-USED @ U> IF DROP 0 EXIT THEN
    _RTHP-W-P @ _RTHP.CLAIMS-USED !
    -1 ;

\ Instrument semantics are optional.  Normalize a local planner refusal at
\ every construction site before residual glyphs are derived from the claim
\ set; callers see OK with the entire family absent, or the original status.
VARIABLE _RTHP-FL-P
VARIABLE _RTHP-FL-FIRST
VARIABLE _RTHP-FL-LAST
VARIABLE _RTHP-FL-FIELD
VARIABLE _RTHP-FL-LATER

: _RTHP-FIELD-LATER-CLAIMS? ( producer -- flag )
    _RTHP-FL-P !
    _RTHP-FL-P @ _RTHP.FIELD-COUNT @ 0= IF -1 EXIT THEN
    _RTHP-FL-P @ _RTHP.FIELD-BASE-CLAIMS @ RUCL-CLAIM-SIZE / _RTHP-FL-FIRST !
    _RTHP-FL-FIRST @ _RTHP-FL-P @ _RTHP.FIELD-COUNT @ + _RTHP-FL-LAST !
    _RTHP-FL-LAST @ _RTHP-FL-FIRST @ ?DO
        _RTHP-FL-P @ _RTHP.CLAIMS-A @ I RUCL-CLAIM-SIZE * + _RTHP-FL-FIELD !
        _RTHP-FL-P @ _RTHP.CLAIMS-USED @ RUCL-CLAIM-SIZE /
        _RTHP-FL-LAST @ ?DO
            _RTHP-FL-P @ _RTHP.CLAIMS-A @ I RUCL-CLAIM-SIZE * + _RTHP-FL-LATER !
            _RTHP-FL-FIELD @ RUCL-CLAIM-ROW0@ _RTHP-FL-LATER @ RUCL-CLAIM-ROW1@ <
            _RTHP-FL-FIELD @ RUCL-CLAIM-ROW1@ _RTHP-FL-LATER @ RUCL-CLAIM-ROW0@ > AND
            _RTHP-FL-FIELD @ RUCL-CLAIM-COL0@ _RTHP-FL-LATER @ RUCL-CLAIM-COL1@ < AND
            _RTHP-FL-FIELD @ RUCL-CLAIM-COL1@ _RTHP-FL-LATER @ RUCL-CLAIM-COL0@ > AND IF
                0 UNLOOP UNLOOP EXIT
            THEN
        LOOP
    LOOP -1 ;

\ Noninteractive graph regions can cover a whole pane while their objects
\ occupy only sparse rectangles. Keep their region input barriers behind the
\ shared interactive/residual region, without changing their relative order.
VARIABLE _RTHP-BZ-P
VARIABLE _RTHP-BZ-Z
VARIABLE _RTHP-BZ-A
VARIABLE _RTHP-BZ-B
VARIABLE _RTHP-BZ-FIRST
VARIABLE _RTHP-BZ-LAST

: _RTHP-BASE-REGION-Z? ( producer -- z flag )
    _RTHP-BZ-P ! 0 _RTHP-BZ-Z !
    _RTHP-BZ-P @ _RTHP.INSTRUMENT-REGION-COUNT @
    _RTHP-BZ-P @ _RTHP.MAX-INSTRUMENT-REGIONS @ U> IF 0 0 EXIT THEN
    _RTHP-BZ-P @ _RTHP.INSTRUMENT-REGION-COUNT @ DUP IF
        RTE-INSTRUMENT-REGION-SIZE _RTHP-U32*? 0= IF DROP 0 0 EXIT THEN
        DUP _RTHP-BZ-P @ _RTHP.INSTRUMENT-REGIONS-U @ U> IF DROP 0 0 EXIT THEN
        _RTHP-BZ-P @ _RTHP.INSTRUMENT-REGIONS-A @ SWAP
            _RTHP-BZ-P @ _RTHP-ARENA-SPAN? 0= IF 0 0 EXIT THEN
    ELSE DROP THEN
    _RTHP-BZ-P @ _RTHP.INSTRUMENT-REGION-COUNT @ 0 ?DO
        _RTHP-BZ-P @ _RTHP.INSTRUMENT-REGIONS-A @
            I RTE-INSTRUMENT-REGION-SIZE * + _RTE-IR.Z @
        DUP -2147483648 < OVER 2147483647 >= OR IF
            DROP 0 0 UNLOOP EXIT
        THEN
        1+ _RTHP-BZ-Z @ MAX _RTHP-BZ-Z !
    LOOP _RTHP-BZ-Z @ -1 ;

: _RTHP-BASE-Z-FIXED? ( z producer -- flag )
    SWAP >R _RTHP-BASE-REGION-Z?
    IF R> = ELSE DROP R> DROP 0 THEN ;

\ Reordering is safe only when graph objects do not overlap any previously
\ admitted control claim but their own document's overlay, which paints
\ above them in either order.  Static claims are separately checked
\ against all earlier families; the residual planner excludes every
\ admitted claim.
: _RTHP-BASE-CLAIMS-DISJOINT? ( producer -- flag )
    _RTHP-BZ-P !
    _RTHP-BZ-P @ _RTHP.BASE-CLAIMS-USED @ DUP RUCL-CLAIM-SIZE MOD IF
        DROP 0 EXIT
    THEN RUCL-CLAIM-SIZE / _RTHP-BZ-FIRST !
    _RTHP-BZ-FIRST @ _RTHP-BZ-P @ _RTHP.INSTRUMENT-CLAIM-COUNT @
        _RTHP-U32+? 0= IF DROP 0 EXIT THEN DUP _RTHP-BZ-LAST !
    RUCL-CLAIM-SIZE _RTHP-U32*? 0= IF DROP 0 EXIT THEN
    _RTHP-BZ-P @ _RTHP.CLAIMS-USED @ U> IF 0 EXIT THEN
    _RTHP-BZ-P @ _RTHP.CLAIMS-USED @ _RTHP-BZ-P @ _RTHP.CLAIMS-U @ U> IF
        0 EXIT
    THEN
    _RTHP-BZ-FIRST @ 0 ?DO
        _RTHP-BZ-P @ _RTHP.CLAIMS-A @ I RUCL-CLAIM-SIZE * + _RTHP-BZ-A !
        _RTHP-BZ-LAST @ _RTHP-BZ-FIRST @ ?DO
            _RTHP-BZ-P @ _RTHP.CLAIMS-A @ I RUCL-CLAIM-SIZE * + _RTHP-BZ-B !
            _RTHP-BZ-A @ RUCL-CLAIM-ROW0@ _RTHP-BZ-B @ RUCL-CLAIM-ROW1@ <
            _RTHP-BZ-A @ RUCL-CLAIM-ROW1@ _RTHP-BZ-B @ RUCL-CLAIM-ROW0@ > AND
            _RTHP-BZ-A @ RUCL-CLAIM-COL0@ _RTHP-BZ-B @ RUCL-CLAIM-COL1@ < AND
            _RTHP-BZ-A @ RUCL-CLAIM-COL1@ _RTHP-BZ-B @ RUCL-CLAIM-COL0@ > AND IF
            _RTHP-BZ-A @ _RTHP-BZ-B @ RUCL-CLAIM-ATTACHMENT@
                _RTHP-BZ-B @ RUCL-CLAIM-Z@ _RTHP-OVERLAY-ABOVE?
            _RTHP-BZ-A @ _RTHP-BZ-B @ RUCL-CLAIM-ATTACHMENT@
                _RTHP-BZ-P @ _RTHP-OTHER-LAYER? OR 0= IF
                0 UNLOOP UNLOOP EXIT
            THEN THEN
        LOOP
    LOOP -1 ;

: _RTHP-BASE-LAYER! ( producer -- flag )
    DUP _RTHP-BASE-CLAIMS-DISJOINT? 0= IF DROP 0 EXIT THEN
    _RTHP-BASE-REGION-Z? 0= IF DROP 0 EXIT THEN DROP
    _RTHP-BZ-Z @ _RTHP-BZ-P @ _RTHP.BASE-Z !
    _RTHP-BZ-P @ _RTHP.CONTROL-COUNT @ IF
        _RTHP-BZ-Z @ _RTHP-BZ-P @ _RTHP.CONTROL-PLAN _RTE-CP.REGION-Z !
    THEN
    _RTHP-BZ-P @ _RTHP.STATIC-COUNT @ IF
        _RTHP-BZ-Z @ _RTHP-BZ-P @ _RTHP.STATIC-PLAN _RTE-SP.REGION-Z !
    THEN
    _RTHP-BZ-P @ _RTHP.GLYPH-COUNT @ IF
        _RTHP-BZ-Z @ _RTHP-BZ-P @ _RTHP.GLYPH-PLAN _RTE-LP.REGION-Z !
    THEN -1 ;

: _RTHP-W-BUILD-OPTIONAL-INSTRUMENTS  ( -- rte-status )
    _RTHP-W-P @ _RTHP-BUILD-INSTRUMENTS
    DUP RTE-S-CAPACITY = OVER RTE-S-UNAVAILABLE = OR IF
        DROP _RTHP-W-RESTORE-BASE-CLAIMS? 0= IF RTE-S-INVALID EXIT THEN
        RTE-S-OK
    THEN
    DUP RTE-S-OK = IF
        _RTHP-W-P @ _RTHP-BASE-CLAIMS-DISJOINT? 0= IF
            DROP RTE-S-UNAVAILABLE EXIT
        THEN
        _RTHP-W-P @ _RTHP-BASE-REGION-Z? 0= IF
            2DROP RTE-S-UNAVAILABLE EXIT
        THEN DROP
    THEN ;


\ ---------------------------------------------------------------------
\ Structured one-row status fields.  Each accepted object owns its exact
\ ordinary CELL rectangle; partial clips and overlaps remain residual.
\ ---------------------------------------------------------------------
VARIABLE _RTHP-SS-OVERLAP
VARIABLE _RTHP-SS-P
VARIABLE _RTHP-SS-DOC
VARIABLE _RTHP-SS-DESC
VARIABLE _RTHP-SS-ENTRY
VARIABLE _RTHP-SS-ITEM
VARIABLE _RTHP-SS-CORR
VARIABLE _RTHP-SS-DA
VARIABLE _RTHP-SS-DU
VARIABLE _RTHP-SS-NA
VARIABLE _RTHP-SS-NU
VARIABLE _RTHP-SS-ROW
VARIABLE _RTHP-SS-COL
VARIABLE _RTHP-SS-WIDTH
VARIABLE _RTHP-SS-END
VARIABLE _RTHP-SS-TEXT
VARIABLE _RTHP-SS-NEXT
VARIABLE _RTHP-SS-CLAIM
VARIABLE _RTHP-SS-INDEX

: _RTHP-STATIC-CLEAR ( producer -- )
    DUP _RTHP.STATIC-PLAN RTE-STATIC-PLAN-SIZE 0 FILL
    0 OVER _RTHP.STATIC-COUNT ! 0 OVER _RTHP.STATIC-TEXT-USED !
    0 SWAP _RTHP.STATIC-LAST ! ;

: _RTHP-STATIC-GLYPH-FIRST? ( producer -- flag )
    DUP _RTHP.FIRST-OBJECT @ OVER _RTHP.CONTROL-COUNT @ _RTHP-U+?
        0= IF 2DROP 0 EXIT THEN
    OVER _RTHP.INSTRUMENT-COUNT @ _RTHP-U+?
        0= IF 2DROP 0 EXIT THEN
    SWAP _RTHP.STATIC-COUNT @ _RTHP-U+?
        0= IF DROP 0 EXIT THEN DUP 0= IF DROP 0 EXIT THEN
    _RTHP-W-GLYPH-FIRST ! -1 ;

: _RTHP-STRIP-STATICS? ( producer -- flag )
    DUP _RTHP-STATIC-CLEAR
    DUP _RTHP.STATIC-BASE-CLAIMS @ DUP RUCL-CLAIM-SIZE MOD IF
        2DROP 0 EXIT
    THEN
    OVER _RTHP.CLAIMS-USED @ U> IF DROP 0 EXIT THEN
    DUP _RTHP.STATIC-BASE-CLAIMS @ OVER _RTHP.CLAIMS-USED !
    _RTHP-STATIC-GLYPH-FIRST? ;

: _RTHP-SS-GEOMETRY? ( -- flag )
    0 _RTHP-SS-OVERLAP !
    _RTHP-SS-DESC @ USFSN-DESCRIPTOR-HEIGHT@ 1 <> IF 0 EXIT THEN
    _RTHP-SS-DESC @ USFSN-DESCRIPTOR-ROW@ DUP _RTHP-SS-ROW !
        0< IF 0 EXIT THEN
    _RTHP-SS-ROW @ _RTHP-SS-P @ _RTHP.ROWS @ U< 0= IF 0 EXIT THEN
    _RTHP-SS-DESC @ USFSN-DESCRIPTOR-COLUMN@ DUP _RTHP-SS-COL !
        0< IF 0 EXIT THEN
    _RTHP-SS-DESC @ USFSN-DESCRIPTOR-WIDTH@ DUP _RTHP-SS-WIDTH !
        0> 0= IF 0 EXIT THEN
    _RTHP-SS-COL @ _RTHP-SS-WIDTH @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN DUP _RTHP-SS-END !
    _RTHP-SS-P @ _RTHP.COLS @ U> IF 0 EXIT THEN
    _RTHP-SS-DESC @ USFSN-DESCRIPTOR-CLIP-ROW@ _RTHP-SS-ROW @ >
    _RTHP-SS-DESC @ USFSN-DESCRIPTOR-CLIP-COLUMN@ _RTHP-SS-COL @ > OR
        IF 0 EXIT THEN
    _RTHP-SS-DESC @ USFSN-DESCRIPTOR-CLIP-ROW@
    _RTHP-SS-DESC @ USFSN-DESCRIPTOR-CLIP-HEIGHT@ +
        _RTHP-SS-ROW @ 1+ < IF 0 EXIT THEN
    _RTHP-SS-DESC @ USFSN-DESCRIPTOR-CLIP-COLUMN@
    _RTHP-SS-DESC @ USFSN-DESCRIPTOR-CLIP-WIDTH@ +
        _RTHP-SS-END @ < IF 0 EXIT THEN
    _RTHP-SS-P @ _RTHP.CLAIMS-USED @ RUCL-CLAIM-SIZE / 0 ?DO
        _RTHP-SS-P @ _RTHP.CLAIMS-A @ I RUCL-CLAIM-SIZE * +
            _RTHP-SS-CLAIM !
        _RTHP-SS-ROW @ _RTHP-SS-CLAIM @ RUCL-CLAIM-ROW1@ <
        _RTHP-SS-ROW @ 1+ _RTHP-SS-CLAIM @ RUCL-CLAIM-ROW0@ > AND
        _RTHP-SS-COL @ _RTHP-SS-CLAIM @ RUCL-CLAIM-COL1@ < AND
        _RTHP-SS-END @ _RTHP-SS-CLAIM @ RUCL-CLAIM-COL0@ > AND IF
        _RTHP-SS-CLAIM @ _RTHP-SS-DOC @ RUHA-DOCUMENT-TOKEN@
            _RTHP-SS-DESC @ USFSN-DESCRIPTOR-Z@ _RTHP-OVERLAY-ABOVE?
        _RTHP-SS-CLAIM @ _RTHP-SS-DOC @ RUHA-DOCUMENT-TOKEN@
            _RTHP-SS-P @ _RTHP-OTHER-LAYER? OR 0=
            IF
                1 _RTHP-SS-OVERLAP !
                I RUCL-CLAIM-SIZE *
                _RTHP-SS-P @ _RTHP.STATIC-BASE-CLAIMS @ U< IF
                    2 _RTHP-SS-OVERLAP !
                THEN
                0 UNLOOP EXIT
            THEN THEN
    LOOP -1 ;

: _RTHP-SS-TEXT! ( source bytes -- address bytes )
    DUP 0= IF 2DROP 0 0 EXIT THEN
    _RTHP-SS-P @ _RTHP.STATIC-TEXT-A @
    _RTHP-SS-P @ _RTHP.STATIC-TEXT-USED @ + _RTHP-SS-TEXT !
    2DUP _RTHP-SS-TEXT @ SWAP MOVE NIP
    DUP _RTHP-SS-P @ _RTHP.STATIC-TEXT-USED +!
    _RTHP-SS-TEXT @ SWAP ;

: _RTHP-SS-WRITE ( -- rte-status )
    _RTHP-SS-ENTRY @ USF-FLAGS@ USF-F-VISIBLE AND 0= IF RTE-S-OK EXIT THEN
    _RTHP-SS-GEOMETRY? 0= IF
        _RTHP-SS-OVERLAP @ IF RTE-S-UNAVAILABLE ELSE RTE-S-OK THEN EXIT
    THEN
    _RTHP-SS-P @ _RTHP.STATIC-COUNT @ DUP _RTHP-SS-INDEX !
        _RTHP-SS-P @ _RTHP.MAX-STATICS @ U< 0= IF RTE-S-CAPACITY EXIT THEN
    _RTHP-SS-ENTRY @ USF-LABEL-BYTES@
    _RTHP-SS-ENTRY @ USF-VALUE-BYTES@ _RTHP-U32+?
        0= IF DROP RTE-S-INVALID EXIT THEN
    _RTHP-SS-P @ _RTHP.STATIC-TEXT-USED @ _RTHP-U32+?
        0= IF DROP RTE-S-INVALID EXIT THEN
    _RTHP-SS-P @ _RTHP.STATIC-TEXT-U @ U> IF RTE-S-CAPACITY EXIT THEN
    _RTHP-SS-P @ _RTHP.CLAIMS-USED @ RUCL-CLAIM-SIZE _RTHP-U32+?
        0= IF DROP RTE-S-INVALID EXIT THEN
    DUP _RTHP-SS-NEXT ! _RTHP-SS-P @ _RTHP.CLAIMS-U @ U> IF
        RTE-S-CAPACITY EXIT
    THEN
    _RTHP-SS-P @ _RTHP-STATIC-GLYPH-FIRST? 0= IF RTE-S-INVALID EXIT THEN
    _RTHP-SS-P @ _RTHP.STATICS-A @
        _RTHP-SS-INDEX @ RTE-STATIC-SIZE * + DUP _RTHP-SS-ITEM !
        RTE-STATIC-SIZE 0 FILL
    _RTHP-SS-P @ _RTHP.OWNER @ _RTHP-SS-ITEM @ _RTE-STATIC.OWNER !
    _RTHP-SS-P @ _RTHP.OWNER-GEN @ _RTHP-SS-ITEM @ _RTE-STATIC.GENERATION !
    _RTHP-W-GLYPH-FIRST @ DUP _RTHP-SS-P @ _RTHP.STATIC-LAST !
        _RTHP-SS-ITEM @ _RTE-STATIC.ID !
    RTE-STATIC-STATUS-FIELD _RTHP-SS-ITEM @ _RTE-STATIC.KIND !
    -1 _RTHP-SS-ITEM @ _RTE-STATIC.VISIBLE !
    _RTHP-SS-DESC @ USFSN-DESCRIPTOR-Z@ _RTHP-SS-ITEM @ _RTE-STATIC.Z !
    _RTHP-SS-P @ _RTHP.REGION @ _RTHP-SS-ITEM @ _RTE-STATIC.REGION !
    _RTHP-SS-ROW @ _RTHP-SS-ITEM @ _RTE-STATIC.ROW !
    _RTHP-SS-COL @ _RTHP-SS-ITEM @ _RTE-STATIC.COL !
    1 _RTHP-SS-ITEM @ _RTE-STATIC.HEIGHT !
    _RTHP-SS-WIDTH @ _RTHP-SS-ITEM @ _RTE-STATIC.WIDTH !
    _RTHP-SS-P @ _RTHP.ROWS @ _RTHP-SS-ITEM @ _RTE-STATIC.ROOT-HEIGHT !
    _RTHP-SS-P @ _RTHP.COLS @ _RTHP-SS-ITEM @ _RTE-STATIC.ROOT-WIDTH !
    _RTHP-SS-ENTRY @ USF-LABEL-COLS@ _RTHP-SS-ITEM @ _RTE-STATIC.LABEL-COLS !
    _RTHP-SS-ENTRY @ USF-SEVERITY@ _RTHP-SS-ITEM @ _RTE-STATIC.SEVERITY !
    _RTHP-SS-ENTRY @ USF-FLAGS@ USF-F-EMPHASIZED AND 0<>
        _RTHP-SS-ITEM @ _RTE-STATIC.EMPHASIZED !
    _RTHP-SS-ENTRY @ USF-LABEL@ _RTHP-SS-TEXT!
        _RTHP-SS-ITEM @ _RTE-STATIC.LABEL-U !
        _RTHP-SS-ITEM @ _RTE-STATIC.LABEL-A !
    _RTHP-SS-ENTRY @ USF-VALUE@ _RTHP-SS-TEXT!
        _RTHP-SS-ITEM @ _RTE-STATIC.VALUE-U !
        _RTHP-SS-ITEM @ _RTE-STATIC.VALUE-A !
    _RTHP-SS-P @ _RTHP.STATIC-CORR-A @
        _RTHP-SS-INDEX @ _RTHP-STATIC-CORR-SIZE * + _RTHP-SS-CORR !
    _RTHP-SS-DOC @ RUHA-DOCUMENT-TOKEN@ _RTHP-SS-CORR @ !
    _RTHP-SS-DESC @ USFSN-DESCRIPTOR-SOURCE-INDEX@ _RTHP-SS-CORR @ 8 + !
    _RTHP-SS-DESC @ USFSN-DESCRIPTOR-SOURCE-GENERATION@ _RTHP-SS-CORR @ 16 + !
    _RTHP-SS-DESC @ USFSN-DESCRIPTOR-ROOT-KEY@ _RTHP-SS-CORR @ 24 + !
    _RTHP-SS-ENTRY @ USF-KEY@ _RTHP-SS-CORR @ 32 + !
    _RTHP-SS-DOC @ RUHA-DOCUMENT-TOKEN@
    _RTHP-SS-P @ _RTHP.SOURCE-GEN @
    _RTHP-SS-DESC @ USFSN-DESCRIPTOR-SOURCE@
    _RTHP-SS-DESC @ USFSN-DESCRIPTOR-SOURCE-INDEX@
    _RTHP-SS-ENTRY @ USF-KEY@
    _RTHP-SS-DESC @ USFSN-DESCRIPTOR-Z@
    _RTHP-SS-ROW @ _RTHP-SS-COL @ _RTHP-SS-ROW @ 1+ _RTHP-SS-END @
    _RTHP-SS-P @ _RTHP.CLAIMS-A @ _RTHP-SS-P @ _RTHP.CLAIMS-USED @ +
        RUCL-ADMITTED-RECTANGLE! RUCL-S-OK <> IF RTE-S-INVALID EXIT THEN
    _RTHP-SS-NEXT @ _RTHP-SS-P @ _RTHP.CLAIMS-USED !
    1 _RTHP-SS-P @ _RTHP.STATIC-COUNT +! RTE-S-OK ;

: _RTHP-SS-WRAP ( -- )
    _RTHP-SS-P @ _RTHP.STATIC-PLAN RTE-STATIC-PLAN-SIZE 0 FILL
    _RTHP-SS-P @ _RTHP.STATIC-COUNT @ 0= IF EXIT THEN
    _RTHP-SS-P @ _RTHP.OWNER @ _RTHP-SS-P @ _RTHP.STATIC-PLAN _RTE-SP.OWNER !
    _RTHP-SS-P @ _RTHP.OWNER-GEN @ _RTHP-SS-P @ _RTHP.STATIC-PLAN _RTE-SP.GENERATION !
    _RTHP-SS-P @ _RTHP.COLS @ _RTHP-SS-P @ _RTHP.STATIC-PLAN _RTE-SP.SURFACE-COLS !
    _RTHP-SS-P @ _RTHP.ROWS @ _RTHP-SS-P @ _RTHP.STATIC-PLAN _RTE-SP.SURFACE-ROWS !
    _RTHP-SS-P @ _RTHP.REGION @ _RTHP-SS-P @ _RTHP.STATIC-PLAN _RTE-SP.REGION-ID !
    _RTHP-SS-P @ _RTHP.COLS @ _RTHP-SS-P @ _RTHP.STATIC-PLAN _RTE-SP.REGION-COLS !
    _RTHP-SS-P @ _RTHP.ROWS @ _RTHP-SS-P @ _RTHP.STATIC-PLAN _RTE-SP.REGION-ROWS !
    RTE-REGION-VISIBLE _RTHP-SS-P @ _RTHP.STATIC-PLAN _RTE-SP.REGION-FLAGS !
    _RTHP-SS-P @ _RTHP.STATICS-A @ _RTHP-SS-P @ _RTHP.STATIC-PLAN _RTE-SP.ITEMS-A !
    _RTHP-SS-P @ _RTHP.STATIC-COUNT @ RTE-STATIC-SIZE *
        _RTHP-SS-P @ _RTHP.STATIC-PLAN _RTE-SP.ITEMS-U ! ;

\ Pictures the terminal holds follow the status fields as IMAGE statics,
\ each fitted inside its picture's cells over a backdrop the renderer
\ paints, so the CELL picture beneath never shows through.  A picture the
\ terminal does not hold yet, or whose cells another root claims, stays
\ CELL.
VARIABLE _RTHP-RF-P
VARIABLE _RTHP-RF-DESC
VARIABLE _RTHP-RF-ENTRY

: _RTHP-RF-MATCH?  ( held-only? -- flag )
    _RTHP-RF-ENTRY @ _RTHP-RS.ID @ 0= IF DROP 0 EXIT THEN
    IF _RTHP-RF-ENTRY @ _RTHP-RS.STATE @ _RTHP-RS-HELD <> IF 0 EXIT THEN THEN
    _RTHP-RF-ENTRY @ _RTHP-RS.WIDTH @
        _RTHP-RF-DESC @ UPICSN-COPY-WIDTH@ <> IF 0 EXIT THEN
    _RTHP-RF-ENTRY @ _RTHP-RS.HEIGHT @
        _RTHP-RF-DESC @ UPICSN-COPY-HEIGHT@ <> IF 0 EXIT THEN
    _RTHP-RF-ENTRY @ _RTHP-RS.FORMAT @
        _RTHP-RF-DESC @ UPICSN-FORMAT@ <> IF 0 EXIT THEN
    _RTHP-RF-ENTRY @ _RTHP-RS.DOCUMENT @
        _RTHP-RF-DESC @ UPICSN-DOCUMENT@ <> IF 0 EXIT THEN
    _RTHP-RF-ENTRY @ _RTHP-RS.INDEX @
        _RTHP-RF-DESC @ UPICSN-SOURCE-INDEX@ <> IF 0 EXIT THEN
    _RTHP-RF-ENTRY @ _RTHP-RS.KEY @
        _RTHP-RF-DESC @ UPICSN-ROOT-KEY@ <> IF 0 EXIT THEN
    _RTHP-RF-ENTRY @ _RTHP-RS.REVISION @
        _RTHP-RF-DESC @ UPICSN-REVISION@ = ;

\ The entry for the copy DESCRIPTOR describes, held by the terminal or,
\ unless HELD-ONLY, still uploading; 0 when there is none.
: _RTHP-RESOURCE-FOR  ( descriptor held-only? producer -- entry|0 )
    _RTHP-RF-P ! SWAP _RTHP-RF-DESC !
    _RTHP-RF-P @ _RTHP.RESOURCES-U @ _RTHP-RESOURCE-SIZE / 0 ?DO
        _RTHP-RF-P @ _RTHP.RESOURCES-A @ I _RTHP-RESOURCE-SIZE * +
            _RTHP-RF-ENTRY !
        DUP _RTHP-RF-MATCH? IF DROP _RTHP-RF-ENTRY @ UNLOOP EXIT THEN
    LOOP DROP 0 ;

VARIABLE _RTHP-RB-BEST

\ The newest copy the terminal holds of the picture DESCRIPTOR describes,
\ at any size: the same document, element, root key and revision; 0 when
\ none.
: _RTHP-RESOURCE-BEFORE  ( descriptor producer -- entry|0 )
    _RTHP-RF-P ! _RTHP-RF-DESC ! 0 _RTHP-RB-BEST !
    _RTHP-RF-DESC @ UPICSN-REVISION@ 0= IF 0 EXIT THEN
    _RTHP-RF-P @ _RTHP.RESOURCES-U @ _RTHP-RESOURCE-SIZE / 0 ?DO
        _RTHP-RF-P @ _RTHP.RESOURCES-A @ I _RTHP-RESOURCE-SIZE * +
            _RTHP-RF-ENTRY !
        _RTHP-RF-ENTRY @ _RTHP-RS.STATE @ _RTHP-RS-HELD =
        _RTHP-RF-ENTRY @ _RTHP-RS.DOCUMENT @
            _RTHP-RF-DESC @ UPICSN-DOCUMENT@ = AND
        _RTHP-RF-ENTRY @ _RTHP-RS.INDEX @
            _RTHP-RF-DESC @ UPICSN-SOURCE-INDEX@ = AND
        _RTHP-RF-ENTRY @ _RTHP-RS.KEY @
            _RTHP-RF-DESC @ UPICSN-ROOT-KEY@ = AND
        _RTHP-RF-ENTRY @ _RTHP-RS.REVISION @
            _RTHP-RF-DESC @ UPICSN-REVISION@ = AND IF
            _RTHP-RB-BEST @ 0= IF -1 ELSE
                _RTHP-RF-ENTRY @ _RTHP-RS.ID @
                    _RTHP-RB-BEST @ _RTHP-RS.ID @ U>
            THEN
            IF _RTHP-RF-ENTRY @ _RTHP-RB-BEST ! THEN
        THEN
    LOOP _RTHP-RB-BEST @ ;

\ The resource a described picture shows: its own copy once the terminal
\ holds it.  While that copy is still on its way, the newest copy of the
\ same picture the terminal holds stays authoritative until the new one
\ replaces it.  Otherwise none, and the picture stays CELL.
: _RTHP-SHOWN-FOR  ( descriptor producer -- entry|0 )
    OVER UPICSN-STATE@ UPICSN-C-READY = IF
        2DUP -1 SWAP _RTHP-RESOURCE-FOR ?DUP IF NIP NIP EXIT THEN
    ELSE
        OVER UPICSN-STATE@ UPICSN-C-PENDING <> IF 2DROP 0 EXIT THEN
    THEN
    _RTHP-RESOURCE-BEFORE ;

VARIABLE _RTHP-SI-DESC
VARIABLE _RTHP-SI-ENTRY
VARIABLE _RTHP-SI-ROW
VARIABLE _RTHP-SI-COL
VARIABLE _RTHP-SI-ROW-END
VARIABLE _RTHP-SI-COL-END

\ The picture's document is one the frame carries.
: _RTHP-SI-DOCUMENT?  ( -- flag )
    _RTHP-SS-P @ _RTHP.DOCUMENT-COUNT @ 0 ?DO
        I _RTHP-SS-P @ _RTHP-DOCUMENT-AT RUHA-DOCUMENT-TOKEN@
        _RTHP-SI-DESC @ UPICSN-DOCUMENT@ = IF -1 UNLOOP EXIT THEN
    LOOP 0 ;

\ The claim at index I, and whether it meets the part shown.
: _RTHP-SI-CLAIM-MEETS?  ( i -- flag )
    _RTHP-SS-P @ _RTHP.CLAIMS-A @ SWAP RUCL-CLAIM-SIZE * + _RTHP-SS-CLAIM !
    _RTHP-SI-ROW @ _RTHP-SS-CLAIM @ RUCL-CLAIM-ROW1@ <
    _RTHP-SI-ROW-END @ _RTHP-SS-CLAIM @ RUCL-CLAIM-ROW0@ > AND
    _RTHP-SI-COL @ _RTHP-SS-CLAIM @ RUCL-CLAIM-COL1@ < AND
    _RTHP-SI-COL-END @ _RTHP-SS-CLAIM @ RUCL-CLAIM-COL0@ > AND ;

\ Whether the claim just met is the picture's own document's root and
\ holds all of the part shown.
: _RTHP-SI-OWN-CLAIM?  ( -- flag )
    _RTHP-SS-CLAIM @ RUCL-CLAIM-ATTACHMENT@ _RTHP-SI-DESC @ UPICSN-DOCUMENT@ =
    _RTHP-SS-CLAIM @ RUCL-CLAIM-SOURCE-INDEX@
        _RTHP-SI-DESC @ UPICSN-SOURCE-INDEX@ = AND
    _RTHP-SS-CLAIM @ RUCL-CLAIM-ROW0@ _RTHP-SI-ROW @ > 0= AND
    _RTHP-SS-CLAIM @ RUCL-CLAIM-COL0@ _RTHP-SI-COL @ > 0= AND
    _RTHP-SS-CLAIM @ RUCL-CLAIM-ROW1@ _RTHP-SI-ROW-END @ < 0= AND
    _RTHP-SS-CLAIM @ RUCL-CLAIM-COL1@ _RTHP-SI-COL-END @ < 0= AND ;

\ The part of the picture shown lies on the surface at a paint order a
\ claim takes, inside the picture's whole rectangle, which may reach off
\ the surface.  An element's own picture claims that part, which no other
\ root of its layer claims.  A figure leaves its part to the claim of its
\ document's root, which must hold all of it.
: _RTHP-SI-GEOMETRY?  ( -- flag )
    _RTHP-SI-DESC @ UPICSN-HEIGHT@ DUP 0> 0= SWAP _RTHP-I32? 0= OR IF 0 EXIT THEN
    _RTHP-SI-DESC @ UPICSN-WIDTH@ DUP 0> 0= SWAP _RTHP-I32? 0= OR IF 0 EXIT THEN
    _RTHP-SI-DESC @ UPICSN-ROW@ _RTHP-I32? 0= IF 0 EXIT THEN
    _RTHP-SI-DESC @ UPICSN-COLUMN@ _RTHP-I32? 0= IF 0 EXIT THEN
    \ The part shown: some of the whole rectangle.
    _RTHP-SI-DESC @ UPICSN-CLIP-ROW@ 0< IF 0 EXIT THEN
    _RTHP-SI-DESC @ UPICSN-CLIP-COLUMN@ 0< IF 0 EXIT THEN
    _RTHP-SI-DESC @ UPICSN-CLIP-HEIGHT@ 0> 0= IF 0 EXIT THEN
    _RTHP-SI-DESC @ UPICSN-CLIP-WIDTH@ 0> 0= IF 0 EXIT THEN
    _RTHP-SI-DESC @ UPICSN-CLIP-ROW@ _RTHP-SI-DESC @ UPICSN-CLIP-HEIGHT@ +
        _RTHP-SI-DESC @ UPICSN-HEIGHT@ > IF 0 EXIT THEN
    _RTHP-SI-DESC @ UPICSN-CLIP-COLUMN@ _RTHP-SI-DESC @ UPICSN-CLIP-WIDTH@ +
        _RTHP-SI-DESC @ UPICSN-WIDTH@ > IF 0 EXIT THEN
    _RTHP-SI-DESC @ UPICSN-ROW@ _RTHP-SI-DESC @ UPICSN-CLIP-ROW@ +
        DUP _RTHP-SI-ROW ! 0< IF 0 EXIT THEN
    _RTHP-SI-DESC @ UPICSN-COLUMN@ _RTHP-SI-DESC @ UPICSN-CLIP-COLUMN@ +
        DUP _RTHP-SI-COL ! 0< IF 0 EXIT THEN
    _RTHP-SI-ROW @ _RTHP-SI-DESC @ UPICSN-CLIP-HEIGHT@ +
        DUP _RTHP-SI-ROW-END ! _RTHP-SS-P @ _RTHP.ROWS @ > IF 0 EXIT THEN
    _RTHP-SI-COL @ _RTHP-SI-DESC @ UPICSN-CLIP-WIDTH@ +
        DUP _RTHP-SI-COL-END ! _RTHP-SS-P @ _RTHP.COLS @ > IF 0 EXIT THEN
    _RTHP-SI-DESC @ UPICSN-Z@ DUP 0< SWAP 255 > OR IF 0 EXIT THEN
    _RTHP-SI-DESC @ UPICSN-FIGURE? IF
        _RTHP-SS-P @ _RTHP.CLAIMS-USED @ RUCL-CLAIM-SIZE / 0 ?DO
            I _RTHP-SI-CLAIM-MEETS? IF
                _RTHP-SS-CLAIM @ _RTHP-SI-DESC @ UPICSN-DOCUMENT@
                    _RTHP-SS-P @ _RTHP-OTHER-LAYER? 0= IF
                    _RTHP-SI-OWN-CLAIM? UNLOOP EXIT
                THEN
            THEN
        LOOP 0 EXIT
    THEN
    _RTHP-SS-P @ _RTHP.CLAIMS-USED @ RUCL-CLAIM-SIZE / 0 ?DO
        I _RTHP-SI-CLAIM-MEETS? IF
        _RTHP-SS-CLAIM @ _RTHP-SI-DESC @ UPICSN-DOCUMENT@
            _RTHP-SI-DESC @ UPICSN-Z@ _RTHP-OVERLAY-ABOVE?
        _RTHP-SS-CLAIM @ _RTHP-SI-DESC @ UPICSN-DOCUMENT@
            _RTHP-SS-P @ _RTHP-OTHER-LAYER? OR 0=
            IF 0 UNLOOP EXIT THEN THEN
    LOOP -1 ;

: _RTHP-SI-WRITE  ( -- rte-status )
    _RTHP-SS-P @ _RTHP.STATIC-COUNT @ DUP _RTHP-SS-INDEX !
        _RTHP-SS-P @ _RTHP.MAX-STATICS @ U< 0= IF RTE-S-INVALID EXIT THEN
    \ A figure adds no claim; its document's root holds its cells.
    _RTHP-SS-P @ _RTHP.CLAIMS-USED @
    _RTHP-SI-DESC @ UPICSN-FIGURE? 0= IF
        RUCL-CLAIM-SIZE _RTHP-U32+? 0= IF DROP RTE-S-INVALID EXIT THEN
    THEN
    DUP _RTHP-SS-NEXT ! _RTHP-SS-P @ _RTHP.CLAIMS-U @ U> IF
        RTE-S-INVALID EXIT
    THEN
    _RTHP-SS-P @ _RTHP-STATIC-GLYPH-FIRST? 0= IF RTE-S-INVALID EXIT THEN
    _RTHP-SS-P @ _RTHP.STATICS-A @
        _RTHP-SS-INDEX @ RTE-STATIC-SIZE * + DUP _RTHP-SS-ITEM !
        RTE-STATIC-SIZE 0 FILL
    _RTHP-SS-P @ _RTHP.OWNER @ _RTHP-SS-ITEM @ _RTE-STATIC.OWNER !
    _RTHP-SS-P @ _RTHP.OWNER-GEN @ _RTHP-SS-ITEM @ _RTE-STATIC.GENERATION !
    _RTHP-W-GLYPH-FIRST @ DUP _RTHP-SS-P @ _RTHP.STATIC-LAST !
        _RTHP-SS-ITEM @ _RTE-STATIC.ID !
    RTE-STATIC-IMAGE _RTHP-SS-ITEM @ _RTE-STATIC.KIND !
    -1 _RTHP-SS-ITEM @ _RTE-STATIC.VISIBLE !
    _RTHP-SI-DESC @ UPICSN-Z@ _RTHP-SS-ITEM @ _RTE-STATIC.Z !
    _RTHP-SS-P @ _RTHP.REGION @ _RTHP-SS-ITEM @ _RTE-STATIC.REGION !
    _RTHP-SI-DESC @ UPICSN-ROW@ _RTHP-SS-ITEM @ _RTE-STATIC.ROW !
    _RTHP-SI-DESC @ UPICSN-COLUMN@ _RTHP-SS-ITEM @ _RTE-STATIC.COL !
    _RTHP-SI-DESC @ UPICSN-HEIGHT@ _RTHP-SS-ITEM @ _RTE-STATIC.HEIGHT !
    _RTHP-SI-DESC @ UPICSN-WIDTH@ _RTHP-SS-ITEM @ _RTE-STATIC.WIDTH !
    \ A picture shown whole has no clip.
    _RTHP-SI-DESC @ UPICSN-CLIP-HEIGHT@ _RTHP-SI-DESC @ UPICSN-HEIGHT@ <>
    _RTHP-SI-DESC @ UPICSN-CLIP-WIDTH@ _RTHP-SI-DESC @ UPICSN-WIDTH@ <> OR IF
        _RTHP-SI-DESC @ UPICSN-CLIP-COLUMN@ _RTHP-SS-ITEM @ _RTE-STATIC.CLIP-X !
        _RTHP-SI-DESC @ UPICSN-CLIP-ROW@ _RTHP-SS-ITEM @ _RTE-STATIC.CLIP-Y !
        _RTHP-SI-DESC @ UPICSN-CLIP-WIDTH@ _RTHP-SS-ITEM @ _RTE-STATIC.CLIP-COLS !
        _RTHP-SI-DESC @ UPICSN-CLIP-HEIGHT@ _RTHP-SS-ITEM @ _RTE-STATIC.CLIP-ROWS !
    THEN
    _RTHP-SS-P @ _RTHP.ROWS @ _RTHP-SS-ITEM @ _RTE-STATIC.ROOT-HEIGHT !
    _RTHP-SS-P @ _RTHP.COLS @ _RTHP-SS-ITEM @ _RTE-STATIC.ROOT-WIDTH !
    RTE-IMAGE-FIT-CONTAIN _RTHP-SS-ITEM @ _RTE-STATIC.FIT !
    255 _RTHP-SS-ITEM @ _RTE-STATIC.OPACITY !
    -1 _RTHP-SS-ITEM @ _RTE-STATIC.BACKDROP !
    _RTHP-SI-ENTRY @ _RTHP-RS.ID @ _RTHP-SS-ITEM @ _RTE-STATIC.RESOURCE !
    \ A picture's correlation and claim name its document, its element,
    \ the generation every direct UIDL root has, and its root key: one for
    \ an element's own picture, a figure's block key.
    _RTHP-SS-P @ _RTHP.STATIC-CORR-A @
        _RTHP-SS-INDEX @ _RTHP-STATIC-CORR-SIZE * + _RTHP-SS-CORR !
    _RTHP-SI-DESC @ UPICSN-DOCUMENT@ _RTHP-SS-CORR @ !
    _RTHP-SI-DESC @ UPICSN-SOURCE-INDEX@ _RTHP-SS-CORR @ 8 + !
    0 _RTHP-SS-CORR @ 16 + !
    _RTHP-SI-DESC @ UPICSN-ROOT-KEY@ _RTHP-SS-CORR @ 24 + !
    0 _RTHP-SS-CORR @ 32 + !
    _RTHP-SI-DESC @ UPICSN-FIGURE? IF
        1 _RTHP-SS-P @ _RTHP.STATIC-COUNT +! RTE-S-OK EXIT
    THEN
    _RTHP-SI-DESC @ UPICSN-DOCUMENT@
    _RTHP-SS-P @ _RTHP.SOURCE-GEN @
    UPICSN-SOURCE-UIDL
    _RTHP-SI-DESC @ UPICSN-SOURCE-INDEX@
    0
    _RTHP-SI-DESC @ UPICSN-Z@
    _RTHP-SI-ROW @ _RTHP-SI-COL @ _RTHP-SI-ROW-END @ _RTHP-SI-COL-END @
    _RTHP-SS-P @ _RTHP.CLAIMS-A @ _RTHP-SS-P @ _RTHP.CLAIMS-USED @ +
        RUCL-ADMITTED-RECTANGLE! RUCL-S-OK <> IF RTE-S-INVALID EXIT THEN
    _RTHP-SS-NEXT @ _RTHP-SS-P @ _RTHP.CLAIMS-USED !
    1 _RTHP-SS-P @ _RTHP.STATIC-COUNT +! RTE-S-OK ;

: _RTHP-BUILD-IMAGES  ( -- rte-status )
    _RTHP-SS-P @ _RTHP.PICTURE-COUNT @ 0 ?DO
        _RTHP-SS-P @ _RTHP.PICTURES-A @ I UPICSN-DESCRIPTOR-SIZE * +
            _RTHP-SI-DESC !
        _RTHP-SI-DESC @ _RTHP-SS-P @ _RTHP-SHOWN-FOR
            DUP _RTHP-SI-ENTRY ! IF
            _RTHP-SI-DOCUMENT? IF
                _RTHP-SI-GEOMETRY? IF
                    _RTHP-SI-WRITE DUP RTE-S-OK <> IF UNLOOP EXIT THEN
                    DROP
                THEN
            THEN
        THEN
    LOOP RTE-S-OK ;

: _RTHP-BUILD-STATICS ( producer -- rte-status )
    0 _RTHP-SS-OVERLAP !
    DUP _RTHP-SS-P ! DUP _RTHP-STATIC-CLEAR
    DUP _RTHP.CLAIMS-USED @ SWAP _RTHP.STATIC-BASE-CLAIMS !
    _RTHP-SS-P @ _RTHP.DOCUMENT-COUNT @ 0 ?DO
        I _RTHP-SS-P @ _RTHP-DOCUMENT-AT _RTHP-SS-DOC !
        _RTHP-SS-DOC @ RUHA-DOCUMENT-STATUS-FIELDS-DESCRIPTOR-BYTES@ _RTHP-SS-DU !
        _RTHP-SS-P @ _RTHP.STATUS-DESCRIPTORS-A @
        _RTHP-SS-DOC @ RUHA-DOCUMENT-STATUS-FIELDS-DESCRIPTOR-OFFSET@ + _RTHP-SS-DA !
        _RTHP-SS-DOC @ RUHA-DOCUMENT-STATUS-FIELDS-NATIVE-BYTES@ _RTHP-SS-NU !
        _RTHP-SS-P @ _RTHP.STATUS-NATIVE-A @
        _RTHP-SS-DOC @ RUHA-DOCUMENT-STATUS-FIELDS-NATIVE-OFFSET@ + _RTHP-SS-NA !
        _RTHP-SS-DU @ USFSN-DESCRIPTOR-SIZE MOD IF RTE-S-INVALID UNLOOP EXIT THEN
        _RTHP-SS-DOC @ RUHA-DOCUMENT-STATUS-FIELDS-DESCRIPTOR-OFFSET@
        _RTHP-SS-DU @ _RTHP-U32+? 0= IF DROP RTE-S-INVALID UNLOOP EXIT THEN
        _RTHP-SS-P @ _RTHP.STATUS-DESCRIPTORS-USED @ U> IF RTE-S-INVALID UNLOOP EXIT THEN
        _RTHP-SS-DOC @ RUHA-DOCUMENT-STATUS-FIELDS-NATIVE-OFFSET@
        _RTHP-SS-NU @ _RTHP-U32+? 0= IF DROP RTE-S-INVALID UNLOOP EXIT THEN
        _RTHP-SS-P @ _RTHP.STATUS-NATIVE-USED @ U> IF RTE-S-INVALID UNLOOP EXIT THEN
        _RTHP-SS-DU @ USFSN-DESCRIPTOR-SIZE / 0 ?DO
            _RTHP-SS-DA @ I USFSN-DESCRIPTOR-SIZE * + _RTHP-SS-DESC !
            _RTHP-SS-DESC @ USFSN-DESCRIPTOR-NATIVE-OFFSET@
            _RTHP-SS-DESC @ USFSN-DESCRIPTOR-ENTRY-BYTES@ _RTHP-U32+?
                0= IF DROP RTE-S-INVALID UNLOOP UNLOOP EXIT THEN
            _RTHP-SS-NU @ U> IF RTE-S-INVALID UNLOOP UNLOOP EXIT THEN
            _RTHP-SS-DESC @ _RTHP-SS-NA @ USFSN-DESCRIPTOR-NATIVE
                OVER _RTHP-SS-ENTRY ! USF-VALIDATE USF-S-OK <>
                IF RTE-S-INVALID UNLOOP UNLOOP EXIT THEN
            _RTHP-SS-ENTRY @ USF-WIDTH@
                _RTHP-SS-DESC @ USFSN-DESCRIPTOR-WIDTH@ <>
                IF RTE-S-INVALID UNLOOP UNLOOP EXIT THEN
            _RTHP-SS-WRITE DUP RTE-S-OK <>
                IF UNLOOP UNLOOP EXIT THEN DROP
        LOOP
    LOOP
    _RTHP-BUILD-IMAGES DUP RTE-S-OK <> IF EXIT THEN DROP
    _RTHP-SS-WRAP
    _RTHP-SS-P @ _RTHP-STATIC-GLYPH-FIRST? 0= IF RTE-S-INVALID EXIT THEN
    RTE-S-OK ;

: _RTHP-W-BUILD-OPTIONAL-STATICS ( -- rte-status )
    _RTHP-W-P @ _RTHP-BUILD-STATICS
    DUP RTE-S-CAPACITY = OVER RTE-S-UNAVAILABLE = OR IF
        DROP _RTHP-W-P @ _RTHP-STRIP-STATICS? 0= IF RTE-S-INVALID EXIT THEN
        \ Identity order cannot prove the final painter of overlapping roots.
        \ Within this lane, strip all status claims.  Across older semantic
        \ families, propagate refusal so the normal empty-frame transition
        \ retires the old rich plane before the complete CELL frame is shown.
        _RTHP-SS-OVERLAP @ 2 = IF RTE-S-UNAVAILABLE ELSE RTE-S-OK THEN
    THEN ;

VARIABLE _RTHP-GP-P
VARIABLE _RTHP-GP-SLOTS
VARIABLE _RTHP-GP-BYTES

\ Rebuild the complete-root plan header around an already assembled dense
\ row-major item bank.  Both full RGRP capture and damage assembly use this
\ exact wrapper before reserve and hybrid preflight.
: _RTHP-WRAP-GLYPH-PLAN?  ( slots producer -- flag )
    _RTHP-GP-P ! _RTHP-GP-SLOTS !
    _RTHP-GP-SLOTS @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN _RTHP-GP-BYTES !
    _RTHP-GP-BYTES @ _RTHP-GP-P @ _RTHP.GLYPH-ITEMS-U @ U> IF
        0 EXIT
    THEN
    _RTHP-GP-P @ _RTHP.GLYPH-PLAN RTE-GLYPH-RUN-PLAN-SIZE 0 FILL
    _RTHP-GP-SLOTS @ 0= IF -1 EXIT THEN
    _RTHP-GP-P @ _RTHP.OWNER @
        _RTHP-GP-P @ _RTHP.GLYPH-PLAN _RTE-LP.OWNER !
    _RTHP-GP-P @ _RTHP.OWNER-GEN @
        _RTHP-GP-P @ _RTHP.GLYPH-PLAN _RTE-LP.GENERATION !
    _RTHP-GP-P @ _RTHP.COLS @
        _RTHP-GP-P @ _RTHP.GLYPH-PLAN _RTE-LP.SURFACE-COLS !
    _RTHP-GP-P @ _RTHP.ROWS @
        _RTHP-GP-P @ _RTHP.GLYPH-PLAN _RTE-LP.SURFACE-ROWS !
    _RTHP-GP-P @ _RTHP.REGION @
        _RTHP-GP-P @ _RTHP.GLYPH-PLAN _RTE-LP.REGION-ID !
    _RTHP-GP-P @ _RTHP.COLS @
        _RTHP-GP-P @ _RTHP.GLYPH-PLAN _RTE-LP.REGION-COLS !
    _RTHP-GP-P @ _RTHP.ROWS @
        _RTHP-GP-P @ _RTHP.GLYPH-PLAN _RTE-LP.REGION-ROWS !
    0 _RTHP-GP-P @ _RTHP.GLYPH-PLAN _RTE-LP.CLIP-X !
    0 _RTHP-GP-P @ _RTHP.GLYPH-PLAN _RTE-LP.CLIP-Y !
    0 _RTHP-GP-P @ _RTHP.GLYPH-PLAN _RTE-LP.CLIP-COLS !
    0 _RTHP-GP-P @ _RTHP.GLYPH-PLAN _RTE-LP.CLIP-ROWS !
    RTE-REGION-VISIBLE
        _RTHP-GP-P @ _RTHP.GLYPH-PLAN _RTE-LP.REGION-FLAGS !
    _RTHP-GP-P @ _RTHP.GLYPH-ITEMS-A @
        _RTHP-GP-P @ _RTHP.GLYPH-PLAN _RTE-LP.ITEMS-A !
    _RTHP-GP-BYTES @
        _RTHP-GP-P @ _RTHP.GLYPH-PLAN _RTE-LP.ITEMS-U !
    -1 ;

: _RTHP-BUILD-GLYPHS-FULL?  ( producer -- flag )
    _RTHP-W-P !
    _RTHP-W-P @ _RTHP.RGRP-Q RGRP-REQUEST-CLEAR
    _RTHP-W-P @ _RTHP.OWNER @ _RTHP-W-P @ _RTHP.OWNER-GEN @
    _RTHP-W-P @ _RTHP.REGION @ _RTHP-W-GLYPH-FIRST @
    _RTHP-W-P @ _RTHP.RGRP-Q RGRP-REQUEST-IDENTITY!
    _RTHP-W-P @ _RTHP.COLS @ _RTHP-W-P @ _RTHP.ROWS @ 0 0
    _RTHP-W-P @ _RTHP.COLS @ _RTHP-W-P @ _RTHP.ROWS @
    0 0 0 0 0 RTE-REGION-VISIBLE 0
    _RTHP-W-P @ _RTHP.RGRP-Q RGRP-REQUEST-REGION!
    _RTHP-W-P @ _RTHP.LIMITS RTE-LIMITS-GLYPH-RUN-BYTES@
    _RTHP-W-P @ _RTHP.RGRP-Q RGRP-REQUEST-LIMIT!
    _RTHP-W-P @ _RTHP.CLAIMS-USED @ IF
        _RTHP-W-P @ _RTHP.CLAIMS-A @ _RTHP-W-P @ _RTHP.CLAIMS-USED @
    ELSE
        0 0
    THEN
    _RTHP-W-P @ _RTHP.RGRP-Q RGRP-REQUEST-CLAIMS!
    _RTHP-W-P @ _RTHP.HEADS-A @ _RTHP-W-P @ _RTHP.HEADS-U @
    _RTHP-W-P @ _RTHP.EVENTS-A @ _RTHP-W-P @ _RTHP.EVENTS-U @
    _RTHP-W-P @ _RTHP.DIFF-A @ _RTHP-W-P @ _RTHP.DIFF-U @
    _RTHP-W-P @ _RTHP.RGRP-Q RGRP-REQUEST-WORK!
    _RTHP-W-P @ _RTHP.GLYPH-PLAN RTE-GLYPH-RUN-PLAN-SIZE
    _RTHP-W-P @ _RTHP.GLYPH-ITEMS-A @
    _RTHP-W-P @ _RTHP.GLYPH-ITEMS-U @
    _RTHP-W-P @ _RTHP.GLYPH-REFS-A @
    _RTHP-W-P @ _RTHP.GLYPH-REFS-U @
    _RTHP-W-P @ _RTHP.GLYPH-TEXT-A @
    _RTHP-W-P @ _RTHP.GLYPH-TEXT-U @
    _RTHP-W-P @ _RTHP.RGRP-Q RGRP-REQUEST-OUTPUT!
    _RTHP-W-P @ _RTHP.MENU-CLAIMS @
    _RTHP-W-P @ _RTHP.RGRP-Q RGRP-BUILD-PAIRED
    _RTHP-W-STATUS ! _RTHP-W-LAST ! _RTHP-W-MAX !
    _RTHP-W-ALIGNED ! _RTHP-W-TEXT ! _RTHP-W-COUNT !
    _RTHP-W-STATUS @ RGRP-S-OK <> IF 0 EXIT THEN
    _RTHP-W-COUNT @ _RTHP-W-P @ _RTHP.GLYPH-COUNT !
    _RTHP-W-TEXT @ _RTHP-W-P @ _RTHP.GLYPH-TEXT-USED !
    -1 ;

\ ---------------------------------------------------------------------
\ ACK-baselined row-damage assembly
\ ---------------------------------------------------------------------
\
\ A clean row is reusable only when the committed screen watermark names the
\ physically acknowledged target, the screen's exact immutable flush plan
\ marks its CELL bytes unchanged, and no opaque claim rectangle on that row
\ came or went between the acknowledged and current projections: a
\ rectangle both have covers the same cells in both.  Menu
\ replacement rows come from both the current ledger and the ACKed bitmap;
\ exact residue damage also prevents reuse when CELL bytes happen to match.  Every other
\ row is rebuilt through the ordinary RGRP subregion API.  The resulting stream
\ is assigned fresh sequential IDs and is therefore byte-equivalent to a
\ complete row-major build before reserve.

VARIABLE _RTHP-RD-P
VARIABLE _RTHP-RD-BANK
VARIABLE _RTHP-RD-FRONT
VARIABLE _RTHP-RD-RESIDUE
VARIABLE _RTHP-RD-PROJECTION-DAMAGE-A
VARIABLE _RTHP-RD-PROJECTION-DAMAGE-U
VARIABLE _RTHP-RD-BACK
VARIABLE _RTHP-RD-COLS
VARIABLE _RTHP-RD-ROWS
VARIABLE _RTHP-RD-FRONT-DRAW
VARIABLE _RTHP-RD-DRAW
VARIABLE _RTHP-RD-FORCE
VARIABLE _RTHP-RD-CELL-DAMAGE-A
VARIABLE _RTHP-RD-CELL-DAMAGE-U
VARIABLE _RTHP-RD-ROW
VARIABLE _RTHP-RD-CLAIM
VARIABLE _RTHP-RD-ROW0
VARIABLE _RTHP-RD-ROW1
VARIABLE _RTHP-RD-ACTIVE-I
VARIABLE _RTHP-RD-ROW-FIRST
VARIABLE _RTHP-RD-ROW-LIMIT
VARIABLE _RTHP-RD-COVER
VARIABLE _RTHP-RD-MORE
VARIABLE _RTHP-RD-ITEM
VARIABLE _RTHP-RD-REF
VARIABLE _RTHP-RD-END
VARIABLE _RTHP-RD-ACTIVE-ITEMS
VARIABLE _RTHP-RD-ACTIVE-REFS
VARIABLE _RTHP-RD-ACTIVE-TEXT
VARIABLE _RTHP-RD-ITEM-CAP
VARIABLE _RTHP-RD-REF-CAP
VARIABLE _RTHP-RD-OUT-COUNT
VARIABLE _RTHP-RD-OUT-TEXT
VARIABLE _RTHP-RD-COUNT-BASE
VARIABLE _RTHP-RD-TEXT-BASE
VARIABLE _RTHP-RD-SRC-O
VARIABLE _RTHP-RD-SRC-U
VARIABLE _RTHP-RD-NEXT
VARIABLE _RTHP-RD-DEST-ITEM
VARIABLE _RTHP-RD-DEST-REF
VARIABLE _RTHP-RD-OUT-ITEMS-A
VARIABLE _RTHP-RD-OUT-ITEMS-U
VARIABLE _RTHP-RD-OUT-REFS-A
VARIABLE _RTHP-RD-OUT-REFS-U
VARIABLE _RTHP-RD-OUT-TEXT-A
VARIABLE _RTHP-RD-OUT-TEXT-U
VARIABLE _RTHP-RD-FIRST-ID
VARIABLE _RTHP-RD-HEADS-U
VARIABLE _RTHP-RD-EVENTS-U
VARIABLE _RTHP-RD-DIFF-U
VARIABLE _RTHP-RD-ROW-CAP

: _RTHP-RD-DAMAGE!  ( row -- )
    _RTHP-RD-P @ _RTHP.ROW-DAMAGE-A @ + -1 SWAP C! ;

: _RTHP-RD-DAMAGE?  ( row -- flag )
    _RTHP-RD-P @ _RTHP.ROW-DAMAGE-A @ + C@ 0<> ;

: _RTHP-RD-ELIGIBLE?  ( -- flag )
    _RTHP-RD-FORCE @ IF 0 EXIT THEN
    _RTHP-RD-COLS @ _RTHP-RD-P @ _RTHP.COLS @ <>
    _RTHP-RD-ROWS @ _RTHP-RD-P @ _RTHP.ROWS @ <> OR IF 0 EXIT THEN
    _RTHP-RD-ROWS @ _RTHP-RD-P @ _RTHP.ROW-DAMAGE-U @ U> IF 0 EXIT THEN
    _RTHP-RD-P @ _RTHP.ROW-DAMAGE-A @ 0= IF 0 EXIT THEN
    _RTHP-RD-P @ _RTHP.TARGET-ACTIVE @ DUP 0= IF DROP 0 EXIT THEN
        _RTHP-RD-BANK !
    _RTHP-RD-BANK @ _RTHP-RD-P @ _RTHP-TARGET-BANK-HEADER?
        0= IF 0 EXIT THEN
    _RTHP-RD-BANK @ _RTHP-TB.OWNER @
        _RTHP-RD-P @ _RTHP.OWNER @ <>
    _RTHP-RD-BANK @ _RTHP-TB.GENERATION @
        _RTHP-RD-P @ _RTHP.OWNER-GEN @ <> OR IF 0 EXIT THEN
    _RTHP-RD-BANK @ _RTHP-TB.COLS @ _RTHP-RD-COLS @ <>
    _RTHP-RD-BANK @ _RTHP-TB.ROWS @ _RTHP-RD-ROWS @ <> OR IF 0 EXIT THEN
    _RTHP-RD-BANK @ _RTHP-TB.PHYSICAL-GEN @
        _RTHP-RD-P @ _RTHP.PHYSICAL-GEN @ <> IF 0 EXIT THEN
    _RTHP-RD-BANK @ _RTHP-TB.GLYPH-RUN-LIMIT @
        _RTHP-RD-P @ _RTHP.LIMITS RTE-LIMITS-GLYPH-RUN-BYTES@
        <> IF 0 EXIT THEN
    _RTHP-RD-FRONT-DRAW @ _RTHP-RD-BANK @ _RTHP-TB.DRAW @ <>
    _RTHP-RD-FRONT-DRAW @ _RTHP-RD-P @ _RTHP.ACTIVE-DRAW @ <> OR IF
        0 EXIT
    THEN
    _RTHP-RD-DRAW @ _RTHP-W-DRAW @ = ;

: _RTHP-RD-MARK-CELL-DAMAGE?  ( -- flag )
    _RTHP-RD-CELL-DAMAGE-A @ 0= IF 0 EXIT THEN
    _RTHP-RD-CELL-DAMAGE-U @ _RTHP-RD-ROWS @ <> IF 0 EXIT THEN
    _RTHP-RD-CELL-DAMAGE-A @ _RTHP-RD-CELL-DAMAGE-U @
        MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    _RTHP-RD-CELL-DAMAGE-A @
    _RTHP-RD-P @ _RTHP.ROW-DAMAGE-A @ _RTHP-RD-ROWS @ MOVE
    -1 ;

\ Projection-only changes need the same row authority as CELL damage.  An
\ ordinary write may update residue even when BACK already holds that value.
: _RTHP-RD-MARK-PROJECTION-DAMAGE?  ( -- flag )
    _RTHP-RD-PROJECTION-DAMAGE-A @ 0= IF 0 EXIT THEN
    _RTHP-RD-PROJECTION-DAMAGE-U @ _RTHP-RD-ROWS @ <> IF 0 EXIT THEN
    _RTHP-RD-PROJECTION-DAMAGE-A @ _RTHP-RD-PROJECTION-DAMAGE-U @
        MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    _RTHP-RD-ROWS @ 0 ?DO
        _RTHP-RD-PROJECTION-DAMAGE-A @ I + C@ IF I _RTHP-RD-DAMAGE! THEN
    LOOP
    -1 ;

: _RTHP-RD-MARK-ACKED-MENUS?  ( -- flag )
    _RTHP-RD-BANK @ _RTHP-PACK-MENU-ROWS-A
    _RTHP-RD-ROWS @ _RTHP-RD-P @ _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    _RTHP-RD-ROWS @ 0 ?DO
        _RTHP-RD-BANK @ _RTHP-PACK-MENU-ROWS-A I + C@ IF
            I _RTHP-RD-DAMAGE!
        THEN
    LOOP
    -1 ;

VARIABLE _RTHP-RD-PROJECTION-SAME
VARIABLE _RTHP-RD-RECTS
VARIABLE _RTHP-RD-RECT

: _RTHP-RD-PROJECTION-SAME?  ( -- flag )
    _RTHP-RD-P @ _RTHP.CLAIMS-USED @ RUCL-CLAIM-SIZE /
    _RTHP-RD-P @ _RTHP.MENU-CLAIMS @ -
        _RTHP-RD-BANK @ _RTHP-TB.PROJECTION-RECTS @ <> IF 0 EXIT THEN
    _RTHP-RD-BANK @ _RTHP-TB.PROJECTION-RECTS @ 0 ?DO
        _RTHP-RD-P @ _RTHP.CLAIMS-A @
        I _RTHP-RD-P @ _RTHP.MENU-CLAIMS @ + RUCL-CLAIM-SIZE * +
            _RUCL-C.ROW0 _RTHP-PROJECTION-RECT-SIZE
        _RTHP-RD-RECTS @ I _RTHP-PROJECTION-RECT-SIZE * +
            _RTHP-PROJECTION-RECT-SIZE COMPARE IF 0 UNLOOP EXIT THEN
    LOOP -1 ;

VARIABLE _RTHP-RD-FIND

\ Whether the rectangle at RECT is among the acknowledged non-menu ones.
: _RTHP-RD-ACKED-RECT?  ( rect -- flag )
    _RTHP-RD-FIND !
    _RTHP-RD-BANK @ _RTHP-TB.PROJECTION-RECTS @ 0 ?DO
        _RTHP-RD-FIND @ _RTHP-PROJECTION-RECT-SIZE
        _RTHP-RD-RECTS @ I _RTHP-PROJECTION-RECT-SIZE * +
            _RTHP-PROJECTION-RECT-SIZE
        COMPARE 0= IF -1 UNLOOP EXIT THEN
    LOOP 0 ;

\ Whether the rectangle at RECT is among the current non-menu claims'.
: _RTHP-RD-CURRENT-RECT?  ( rect -- flag )
    _RTHP-RD-FIND !
    _RTHP-RD-P @ _RTHP.CLAIMS-USED @ RUCL-CLAIM-SIZE /
    _RTHP-RD-P @ _RTHP.MENU-CLAIMS @ ?DO
        _RTHP-RD-FIND @ _RTHP-PROJECTION-RECT-SIZE
        _RTHP-RD-P @ _RTHP.CLAIMS-A @ I RUCL-CLAIM-SIZE * +
            _RUCL-C.ROW0 _RTHP-PROJECTION-RECT-SIZE
        COMPARE 0= IF -1 UNLOOP EXIT THEN
    LOOP 0 ;

\ The rows of each acknowledged rectangle the current projection lacks.
: _RTHP-RD-MARK-OLD-PROJECTION?  ( -- flag )
    _RTHP-RD-PROJECTION-SAME @ IF -1 EXIT THEN
    _RTHP-RD-BANK @ _RTHP-TB.PROJECTION-RECTS @ 0 ?DO
        _RTHP-RD-RECTS @ I _RTHP-PROJECTION-RECT-SIZE * + DUP _RTHP-RD-RECT !
        _RTHP-RD-COLS @ _RTHP-RD-ROWS @ _RTHP-PROJECTION-RECT? 0= IF
            0 UNLOOP EXIT
        THEN
        _RTHP-RD-RECT @ _RTHP-RD-CURRENT-RECT? 0= IF
            _RTHP-RD-RECT @ 16 + @ _RTHP-RD-RECT @ @ ?DO
                I _RTHP-RD-DAMAGE!
            LOOP
        THEN
    LOOP -1 ;

: _RTHP-RD-MARK-CURRENT-CLAIMS?  ( -- flag )
    _RTHP-RD-P @ _RTHP.CLAIMS-USED @ DUP
        _RTHP-RD-P @ _RTHP.CLAIMS-U @ U> IF DROP 0 EXIT THEN
    DUP RUCL-CLAIM-SIZE MOD IF DROP 0 EXIT THEN
    DUP RUCL-CLAIM-SIZE / _RTHP-RD-P @ _RTHP.MENU-CLAIMS @ U< IF
        DROP 0 EXIT
    THEN
    DUP IF
        _RTHP-RD-P @ _RTHP.CLAIMS-A @ OVER _RTHP-RD-P @
            _RTHP-ARENA-SPAN? 0= IF DROP 0 EXIT THEN
    THEN
    _RTHP-RD-BANK @ _RTHP-PACK-PROJECTION-RECTS-A _RTHP-RD-RECTS !
    _RTHP-RD-PROJECTION-SAME? _RTHP-RD-PROJECTION-SAME !
    _RTHP-RD-MARK-OLD-PROJECTION? 0= IF DROP 0 EXIT THEN
    _RTHP-RD-PROJECTION-SAME @ IF
        DROP _RTHP-RD-P @ _RTHP.MENU-CLAIMS @
    ELSE RUCL-CLAIM-SIZE / THEN
    0 ?DO
        _RTHP-RD-P @ _RTHP.CLAIMS-A @ I RUCL-CLAIM-SIZE * +
            DUP _RTHP-RD-CLAIM !
        RUCL-CLAIM-ROW0@ DUP _RTHP-RD-ROW0 ! 0< IF
            0 UNLOOP EXIT
        THEN
        _RTHP-RD-CLAIM @ RUCL-CLAIM-ROW1@
            DUP _RTHP-RD-ROW1 ! 0< IF 0 UNLOOP EXIT THEN
        _RTHP-RD-ROW0 @ _RTHP-RD-ROW1 @ U< 0= IF 0 UNLOOP EXIT THEN
        _RTHP-RD-ROW1 @ _RTHP-RD-ROWS @ U> IF 0 UNLOOP EXIT THEN
        \ Every menu's rows, and those of each other claim new to them.
        I _RTHP-RD-P @ _RTHP.MENU-CLAIMS @ U< IF -1 ELSE
            _RTHP-RD-CLAIM @ _RUCL-C.ROW0 _RTHP-RD-ACKED-RECT? 0=
        THEN IF
            _RTHP-RD-ROW1 @ _RTHP-RD-ROW0 @ ?DO
                I _RTHP-RD-DAMAGE!
            LOOP
        THEN
    LOOP
    -1 ;

\ The producer descriptor contains the RGRP request and plan header; every
\ variable-size bank lives in its one arena.  Prove those two authorities
\ disjoint from the guarded screen once for the complete frame callback.
\ Row-local RGRP calls can then retain all non-screen range checks without
\ repeating nine recursive screen graph audits per damaged row.
: _RTHP-RD-SCREEN-AUTHORITY?  ( -- flag )
    _RTHP-RD-P @ RTHP-SIZE
    _RTHP-RD-P @ _RTHP.ARENA-A @ _RTHP-RD-P @ _RTHP.ARENA-U @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTHP-RD-P @ RTHP-SIZE SCR-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    _RTHP-RD-P @ _RTHP.ARENA-A @ _RTHP-RD-P @ _RTHP.ARENA-U @
        SCR-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    _RTHP-RD-P @ _RTHP.ROW-DAMAGE-A @ _RTHP-RD-ROWS @
        _RTHP-RD-P @ _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    _RTHP-RD-P @ _RTHP.GLYPH-ITEMS-A @
    _RTHP-RD-P @ _RTHP.GLYPH-ITEMS-U @
        _RTHP-RD-P @ _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    _RTHP-RD-P @ _RTHP.GLYPH-REFS-A @
    _RTHP-RD-P @ _RTHP.GLYPH-REFS-U @
        _RTHP-RD-P @ _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    _RTHP-RD-P @ _RTHP.GLYPH-TEXT-A @
    _RTHP-RD-P @ _RTHP.GLYPH-TEXT-U @
        _RTHP-RD-P @ _RTHP-ARENA-SPAN? ;

\ Restrict every row planner invocation to the storage that one row can
\ actually consume.  This keeps both normal authority checks and exceptional
\ scrubbing bounded by the damaged slice rather than the complete screen.
: _RTHP-RD-WORK-BOUNDS?  ( -- flag )
    _RTHP-RD-P @ _RTHP.CLAIMS-USED @ IF
        _RTHP-RD-P @ _RTHP.CLAIMS-A @
        _RTHP-RD-P @ _RTHP.CLAIMS-USED @
        _RTHP-RD-P @ _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    THEN
    2 RGRP-ROW-HEAD-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN DUP _RTHP-RD-HEADS-U !
    _RTHP-RD-P @ _RTHP.HEADS-U @ U> IF 0 EXIT THEN
    _RTHP-RD-P @ _RTHP.HEADS-A @ _RTHP-RD-HEADS-U @
        _RTHP-RD-P @ _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    _RTHP-RD-P @ _RTHP.CLAIMS-USED @ RUCL-CLAIM-SIZE /
        2 _RTHP-U32*? 0= IF DROP 0 EXIT THEN
        RGRP-EVENT-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN DUP _RTHP-RD-EVENTS-U !
    _RTHP-RD-P @ _RTHP.EVENTS-U @ U> IF 0 EXIT THEN
    _RTHP-RD-EVENTS-U @ IF
        _RTHP-RD-P @ _RTHP.EVENTS-A @ _RTHP-RD-EVENTS-U @
        _RTHP-RD-P @ _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    THEN
    _RTHP-RD-COLS @ 1 _RTHP-U32+? 0= IF DROP 0 EXIT THEN
        RGRP-PAIRED-DIFFERENCE-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN DUP _RTHP-RD-DIFF-U !
    _RTHP-RD-P @ _RTHP.DIFF-U @ U> IF 0 EXIT THEN
    _RTHP-RD-P @ _RTHP.DIFF-A @ _RTHP-RD-DIFF-U @
        _RTHP-RD-P @ _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    -1 ;

: _RTHP-RD-ACTIVE-ITEM  ( index -- item )
    RTE-GLYPH-RUN-PLAN-ITEM-SIZE * _RTHP-RD-ACTIVE-ITEMS @ + ;

: _RTHP-RD-ACTIVE-REF  ( index -- ref )
    RGRP-TEXT-REF-SIZE * _RTHP-RD-ACTIVE-REFS @ + ;

\ Establish the exact acknowledged residual interval stream for one row.
\ Its gaps are reused with it: rectangles that came or went, old and current
\ menu rows, and exact CELL/residue damage have already marked their rows.
: _RTHP-RD-SCAN-ACTIVE-ROW?  ( -- flag )
    _RTHP-RD-ACTIVE-I @ _RTHP-RD-ROW-FIRST !
    0 _RTHP-RD-COVER ! -1 _RTHP-RD-MORE !
    BEGIN
        _RTHP-RD-ACTIVE-I @
            _RTHP-RD-BANK @ _RTHP-TB.GLYPH-SLOT-COUNT @ U<
        _RTHP-RD-MORE @ AND
    WHILE
        _RTHP-RD-ACTIVE-I @ _RTHP-RD-ACTIVE-ITEM
            DUP _RTHP-RD-ITEM !
        _RTE-LPI.VISIBLE @ 0= IF
            0 _RTHP-RD-MORE !
        ELSE
            _RTHP-RD-ITEM @ _RTE-LPI.ROW @ DUP
                _RTHP-RD-ROW @ < IF DROP 0 EXIT THEN
            _RTHP-RD-ROW @ > IF
                0 _RTHP-RD-MORE !
            ELSE
                _RTHP-RD-ITEM @ _RTE-LPI.HEIGHT @ 1 <> IF 0 EXIT THEN
                _RTHP-RD-ITEM @ _RTE-LPI.COL @ DUP 0< IF
                    DROP 0 EXIT
                THEN
                DUP _RTHP-RD-COVER @ U< IF DROP 0 EXIT THEN
                _RTHP-RD-ITEM @ _RTE-LPI.WIDTH @ DUP 0> 0= IF
                    2DROP 0 EXIT
                THEN
                _RTHP-U32+? 0= IF DROP 0 EXIT THEN DUP _RTHP-RD-END !
                _RTHP-RD-COLS @ U> IF 0 EXIT THEN
                _RTHP-RD-END @ _RTHP-RD-COVER !
                1 _RTHP-RD-ACTIVE-I +!
            THEN
        THEN
    REPEAT
    _RTHP-RD-ACTIVE-I @ _RTHP-RD-ROW-LIMIT !
    -1 ;

: _RTHP-RD-COPY-ACTIVE-ONE?  ( index -- flag )
    DUP _RTHP-RD-ACTIVE-ITEM _RTHP-RD-ITEM !
        _RTHP-RD-ACTIVE-REF _RTHP-RD-REF !
    _RTHP-RD-OUT-COUNT @ _RTHP-RD-ITEM-CAP @ U< 0= IF 0 EXIT THEN
    _RTHP-RD-OUT-COUNT @ _RTHP-RD-REF-CAP @ U< 0= IF 0 EXIT THEN
    _RTHP-RD-P @ _RTHP.GLYPH-ITEMS-A @
        _RTHP-RD-OUT-COUNT @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE * +
        DUP _RTHP-RD-DEST-ITEM !
    _RTHP-RD-ITEM @ SWAP RTE-GLYPH-RUN-PLAN-ITEM-SIZE MOVE
    _RTHP-W-GLYPH-FIRST @ _RTHP-RD-OUT-COUNT @ _RTHP-U+?
        0= IF DROP 0 EXIT THEN DUP 0= IF DROP 0 EXIT THEN
        _RTHP-RD-DEST-ITEM @ _RTE-LPI.OBJECT !

    _RTHP-RD-REF @ RGRP-TEXT-REF-OFFSET@ _RTHP-RD-SRC-O !
    _RTHP-RD-REF @ RGRP-TEXT-REF-LENGTH@ _RTHP-RD-SRC-U !
    _RTHP-RD-ITEM @ _RTE-LPI.TEXT-CAPACITY @
        _RTHP-RD-SRC-U @ <> IF 0 EXIT THEN
    _RTHP-RD-SRC-O @
        _RTHP-RD-BANK @ _RTHP-TB.GLYPH-TEXT-USED @ U> IF 0 EXIT THEN
    _RTHP-RD-SRC-U @
        _RTHP-RD-BANK @ _RTHP-TB.GLYPH-TEXT-USED @
        _RTHP-RD-SRC-O @ - U> IF 0 EXIT THEN
    _RTHP-RD-OUT-TEXT @ _RTHP-RD-SRC-U @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN DUP _RTHP-RD-NEXT !
    _RTHP-RD-P @ _RTHP.GLYPH-TEXT-U @ U> IF 0 EXIT THEN
    _RTHP-RD-SRC-U @ IF
        _RTHP-RD-ACTIVE-TEXT @ _RTHP-RD-SRC-O @ +
        _RTHP-RD-P @ _RTHP.GLYPH-TEXT-A @ _RTHP-RD-OUT-TEXT @ +
        _RTHP-RD-SRC-U @ MOVE
    THEN
    _RTHP-RD-P @ _RTHP.GLYPH-REFS-A @
        _RTHP-RD-OUT-COUNT @ RGRP-TEXT-REF-SIZE * +
        DUP _RTHP-RD-DEST-REF ! RGRP-TEXT-REF-SIZE 0 FILL
    _RTHP-RD-OUT-TEXT @ _RTHP-RD-DEST-REF @ _RGRP-T.OFFSET !
    _RTHP-RD-SRC-U @ _RTHP-RD-DEST-REF @ _RGRP-T.BYTES !
    _RTHP-RD-NEXT @ _RTHP-RD-OUT-TEXT !
    1 _RTHP-RD-OUT-COUNT +!
    -1 ;

: _RTHP-RD-COPY-ACTIVE-ROW?  ( -- flag )
    _RTHP-RD-ROW-LIMIT @ _RTHP-RD-ROW-FIRST @ ?DO
        I _RTHP-RD-COPY-ACTIVE-ONE? 0= IF 0 UNLOOP EXIT THEN
    LOOP
    -1 ;

: _RTHP-RD-ROW-OUTPUT?  ( -- flag )
    _RTHP-RD-COLS @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN _RTHP-RD-ROW-CAP !
    _RTHP-RD-OUT-COUNT @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN DUP _RTHP-RD-NEXT !
    _RTHP-RD-P @ _RTHP.GLYPH-ITEMS-U @ U> IF 0 EXIT THEN
    _RTHP-RD-P @ _RTHP.GLYPH-ITEMS-U @ _RTHP-RD-NEXT @ -
        _RTHP-RD-ROW-CAP @ _RTHP-UMIN
        DUP _RTHP-RD-OUT-ITEMS-U ! IF
        _RTHP-RD-P @ _RTHP.GLYPH-ITEMS-A @ _RTHP-RD-NEXT @ +
            DUP _RTHP-RD-OUT-ITEMS-A !
        _RTHP-RD-OUT-ITEMS-U @ _RTHP-RD-P @ _RTHP-ARENA-SPAN?
            0= IF 0 EXIT THEN
    ELSE 0 _RTHP-RD-OUT-ITEMS-A ! THEN
    _RTHP-RD-COLS @ RGRP-TEXT-REF-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN _RTHP-RD-ROW-CAP !
    _RTHP-RD-OUT-COUNT @ RGRP-TEXT-REF-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN DUP _RTHP-RD-NEXT !
    _RTHP-RD-P @ _RTHP.GLYPH-REFS-U @ U> IF 0 EXIT THEN
    _RTHP-RD-P @ _RTHP.GLYPH-REFS-U @ _RTHP-RD-NEXT @ -
        _RTHP-RD-ROW-CAP @ _RTHP-UMIN
        DUP _RTHP-RD-OUT-REFS-U ! IF
        _RTHP-RD-P @ _RTHP.GLYPH-REFS-A @ _RTHP-RD-NEXT @ +
            DUP _RTHP-RD-OUT-REFS-A !
        _RTHP-RD-OUT-REFS-U @ _RTHP-RD-P @ _RTHP-ARENA-SPAN?
            0= IF 0 EXIT THEN
    ELSE 0 _RTHP-RD-OUT-REFS-A ! THEN
    _RTHP-RD-OUT-TEXT @ _RTHP-RD-P @ _RTHP.GLYPH-TEXT-U @ U> IF
        0 EXIT
    THEN
    _RTHP-RD-COLS @ 4 _RTHP-U32*?
        0= IF DROP 0 EXIT THEN _RTHP-RD-ROW-CAP !
    _RTHP-RD-P @ _RTHP.GLYPH-TEXT-U @ _RTHP-RD-OUT-TEXT @ -
        _RTHP-RD-ROW-CAP @ _RTHP-UMIN
        DUP _RTHP-RD-OUT-TEXT-U ! IF
        _RTHP-RD-P @ _RTHP.GLYPH-TEXT-A @ _RTHP-RD-OUT-TEXT @ +
            DUP _RTHP-RD-OUT-TEXT-A !
        _RTHP-RD-OUT-TEXT-U @ _RTHP-RD-P @ _RTHP-ARENA-SPAN?
            0= IF 0 EXIT THEN
    ELSE 0 _RTHP-RD-OUT-TEXT-A ! THEN
    -1 ;

: _RTHP-RD-NORMALIZE-ROW?  ( -- flag )
    _RTHP-W-COUNT @ 0 ?DO
        _RTHP-RD-P @ _RTHP.GLYPH-ITEMS-A @
        _RTHP-RD-COUNT-BASE @ I + RTE-GLYPH-RUN-PLAN-ITEM-SIZE * +
            _RTHP-RD-ITEM !
        _RTHP-RD-ITEM @ _RTE-LPI.ROW @ 0<> IF 0 UNLOOP EXIT THEN
        _RTHP-RD-ROW @ _RTHP-RD-ITEM @ _RTE-LPI.ROW !
        _RTHP-RD-ROWS @ _RTHP-RD-ITEM @ _RTE-LPI.ROOT-HEIGHT !
        _RTHP-RD-COLS @ _RTHP-RD-ITEM @ _RTE-LPI.ROOT-WIDTH !
        _RTHP-RD-P @ _RTHP.GLYPH-REFS-A @
        _RTHP-RD-COUNT-BASE @ I + RGRP-TEXT-REF-SIZE * +
            DUP _RTHP-RD-REF !
        RGRP-TEXT-REF-OFFSET@
        _RTHP-RD-TEXT-BASE @ _RTHP-U32+? 0= IF
            DROP 0 UNLOOP EXIT
        THEN
        _RTHP-RD-REF @ _RGRP-T.OFFSET !
    LOOP
    -1 ;

: _RTHP-RD-BUILD-ROW?  ( -- flag )
    _RTHP-RD-ROW-OUTPUT? 0= IF 0 EXIT THEN
    _RTHP-RD-OUT-COUNT @ _RTHP-RD-COUNT-BASE !
    _RTHP-RD-OUT-TEXT @ _RTHP-RD-TEXT-BASE !
    _RTHP-W-GLYPH-FIRST @ _RTHP-RD-OUT-COUNT @ _RTHP-U+?
        0= IF DROP 0 EXIT THEN DUP 0= IF DROP 0 EXIT THEN
        _RTHP-RD-FIRST-ID !
    _RTHP-RD-P @ _RTHP.RGRP-Q RGRP-REQUEST-CLEAR
    _RTHP-RD-P @ _RTHP.OWNER @ _RTHP-RD-P @ _RTHP.OWNER-GEN @
    _RTHP-RD-P @ _RTHP.REGION @ _RTHP-RD-FIRST-ID @
    _RTHP-RD-P @ _RTHP.RGRP-Q RGRP-REQUEST-IDENTITY!
    _RTHP-RD-COLS @ _RTHP-RD-ROWS @ 0 _RTHP-RD-ROW @
    _RTHP-RD-COLS @ 1 0 0 0 0 0 RTE-REGION-VISIBLE 0
    _RTHP-RD-P @ _RTHP.RGRP-Q RGRP-REQUEST-REGION!
    _RTHP-RD-P @ _RTHP.LIMITS RTE-LIMITS-GLYPH-RUN-BYTES@
    _RTHP-RD-P @ _RTHP.RGRP-Q RGRP-REQUEST-LIMIT!
    _RTHP-RD-P @ _RTHP.CLAIMS-USED @ IF
        _RTHP-RD-P @ _RTHP.CLAIMS-A @
        _RTHP-RD-P @ _RTHP.CLAIMS-USED @
    ELSE 0 0 THEN
    _RTHP-RD-P @ _RTHP.RGRP-Q RGRP-REQUEST-CLAIMS!
    _RTHP-RD-P @ _RTHP.HEADS-A @ _RTHP-RD-HEADS-U @
    _RTHP-RD-EVENTS-U @ IF
        _RTHP-RD-P @ _RTHP.EVENTS-A @ _RTHP-RD-EVENTS-U @
    ELSE 0 0 THEN
    _RTHP-RD-P @ _RTHP.DIFF-A @ _RTHP-RD-DIFF-U @
    _RTHP-RD-P @ _RTHP.RGRP-Q RGRP-REQUEST-WORK!
    _RTHP-RD-P @ _RTHP.GLYPH-PLAN RTE-GLYPH-RUN-PLAN-SIZE
    _RTHP-RD-OUT-ITEMS-A @ _RTHP-RD-OUT-ITEMS-U @
    _RTHP-RD-OUT-REFS-A @ _RTHP-RD-OUT-REFS-U @
    _RTHP-RD-OUT-TEXT-A @ _RTHP-RD-OUT-TEXT-U @
    _RTHP-RD-P @ _RTHP.RGRP-Q RGRP-REQUEST-OUTPUT!
    _RTHP-RD-BACK @ _RTHP-RD-RESIDUE @
    _RTHP-RD-COLS @ _RTHP-RD-ROWS @
    _RTHP-RD-P @ _RTHP.MENU-CLAIMS @
    _RTHP-RD-P @ _RTHP.RGRP-Q _RGRP-BUILD-PAIRED-FROM-AUTHORIZED-PLANES
    _RTHP-W-STATUS ! _RTHP-W-LAST ! _RTHP-W-MAX !
    _RTHP-W-ALIGNED ! _RTHP-W-TEXT ! _RTHP-W-COUNT !
    _RTHP-W-STATUS @ RGRP-S-OK <> IF 0 EXIT THEN
    _RTHP-RD-NORMALIZE-ROW? 0= IF 0 EXIT THEN
    _RTHP-RD-COUNT-BASE @ _RTHP-W-COUNT @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN _RTHP-RD-OUT-COUNT !
    _RTHP-RD-TEXT-BASE @ _RTHP-W-TEXT @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN DUP
        _RTHP-RD-P @ _RTHP.GLYPH-TEXT-U @ U> IF DROP 0 EXIT THEN
        _RTHP-RD-OUT-TEXT !
    -1 ;

: _RTHP-RD-FINISH?  ( -- flag )
    BEGIN _RTHP-RD-ACTIVE-I @
        _RTHP-RD-BANK @ _RTHP-TB.GLYPH-SLOT-COUNT @ U< WHILE
        _RTHP-RD-ACTIVE-I @ _RTHP-RD-ACTIVE-ITEM
            _RTE-LPI.VISIBLE @ IF 0 EXIT THEN
        1 _RTHP-RD-ACTIVE-I +!
    REPEAT
    _RTHP-RD-OUT-COUNT @ DUP _RTHP-RD-P @ _RTHP.GLYPH-COUNT !
        _RTHP-RD-P @ _RTHP-WRAP-GLYPH-PLAN? 0= IF 0 EXIT THEN
    _RTHP-RD-OUT-TEXT @ _RTHP-RD-P @ _RTHP.GLYPH-TEXT-USED !
    -1 ;

\ Mark the rows a plan of this draw must build again: those of CELL and
\ residue damage, the acknowledged and current menus' rows, and the rows of
\ claims that came or went.  Every other row keeps the acknowledged frame's
\ cells, residue, menus and claims, so its runs are the acknowledged ones.
: _RTHP-RD-MARK-BODY?  ( -- flag )
    _RTHP-RD-ELIGIBLE? 0= IF 0 EXIT THEN
    _RTHP-RD-SCREEN-AUTHORITY? 0= IF 0 EXIT THEN
    _RTHP-RD-MARK-CELL-DAMAGE? 0= IF 0 EXIT THEN
    _RTHP-RD-MARK-PROJECTION-DAMAGE? 0= IF 0 EXIT THEN
    _RTHP-RD-MARK-ACKED-MENUS? 0= IF 0 EXIT THEN
    _RTHP-RD-MARK-CURRENT-CLAIMS? ;

: _RTHP-RD-BUILD-BODY?  ( -- flag )
    _RTHP-RD-MARK-BODY? 0= IF 0 EXIT THEN
    _RTHP-RD-WORK-BOUNDS? 0= IF 0 EXIT THEN
    _RTHP-RD-BANK @ _RTHP-PACK-ITEMS-A _RTHP-RD-ACTIVE-ITEMS !
    _RTHP-RD-BANK @ _RTHP-PACK-REFS-A _RTHP-RD-ACTIVE-REFS !
    _RTHP-RD-BANK @ _RTHP-PACK-GLYPH-A _RTHP-RD-ACTIVE-TEXT !
    _RTHP-RD-P @ _RTHP.GLYPH-ITEMS-U @
        RTE-GLYPH-RUN-PLAN-ITEM-SIZE / _RTHP-RD-ITEM-CAP !
    _RTHP-RD-P @ _RTHP.GLYPH-REFS-U @
        RGRP-TEXT-REF-SIZE / _RTHP-RD-REF-CAP !
    0 _RTHP-RD-ACTIVE-I ! 0 _RTHP-RD-OUT-COUNT !
    0 _RTHP-RD-OUT-TEXT !
    _RTHP-RD-ROWS @ 0 ?DO
        I _RTHP-RD-ROW !
        _RTHP-RD-SCAN-ACTIVE-ROW? 0= IF 0 UNLOOP EXIT THEN
        I _RTHP-RD-DAMAGE? IF
            _RTHP-RD-BUILD-ROW? 0= IF 0 UNLOOP EXIT THEN
        ELSE
            _RTHP-RD-COPY-ACTIVE-ROW? 0= IF 0 UNLOOP EXIT THEN
        THEN
    LOOP
    _RTHP-RD-FINISH? ;

: _RTHP-RD-CLEAR-PLANE-BORROW  ( flag -- flag )
    0 _RTHP-RD-FRONT ! 0 _RTHP-RD-BACK ! 0 _RTHP-RD-RESIDUE !
    0 _RTHP-RD-PROJECTION-DAMAGE-A ! 0 _RTHP-RD-PROJECTION-DAMAGE-U !
    0 _RTHP-RD-CELL-DAMAGE-A ! 0 _RTHP-RD-CELL-DAMAGE-U ! ;

: _RTHP-RD-PLANES!
  ( front-a back-a cols rows front-draw draw force? damage-a damage-u residue-a projection-damage-a projection-damage-u -- )
    _RTHP-RD-PROJECTION-DAMAGE-U ! _RTHP-RD-PROJECTION-DAMAGE-A !
    _RTHP-RD-RESIDUE !
    _RTHP-RD-CELL-DAMAGE-U ! _RTHP-RD-CELL-DAMAGE-A !
    _RTHP-RD-FORCE ! _RTHP-RD-DRAW ! _RTHP-RD-FRONT-DRAW !
    _RTHP-RD-ROWS ! _RTHP-RD-COLS ! _RTHP-RD-BACK ! _RTHP-RD-FRONT ! ;

\ Run XT on the borrowed planes; whatever it does, no plane stays borrowed.
: _RTHP-RD-IN-PLANES  ( xt -- flag )
    CATCH DUP IF
        0 _RTHP-RD-CLEAR-PLANE-BORROW DROP THROW
    THEN
    DROP _RTHP-RD-CLEAR-PLANE-BORROW ;

: _RTHP-RD-BUILD-IN-PLANES
  ( front-a back-a cols rows front-draw draw force? damage-a damage-u residue-a projection-damage-a projection-damage-u -- flag )
    _RTHP-RD-PLANES! ['] _RTHP-RD-BUILD-BODY? _RTHP-RD-IN-PLANES ;

: _RTHP-RD-MARK-IN-PLANES
  ( front-a back-a cols rows front-draw draw force? damage-a damage-u residue-a projection-damage-a projection-damage-u -- flag )
    _RTHP-RD-PLANES! ['] _RTHP-RD-MARK-BODY? _RTHP-RD-IN-PLANES ;

: _RTHP-BUILD-GLYPHS-DAMAGE?  ( producer -- flag )
    _RTHP-RD-P !
    ['] _RTHP-RD-BUILD-IN-PLANES SCR-WITH-PROJECTION-FRAME-PLANES ;

\ Only the rows to build again, for Desk's shell, which copies the runs of
\ its regions' other rows from its own acknowledged bank.
: _RTHP-MARK-GLYPHS-DAMAGE?  ( producer -- flag )
    _RTHP-RD-P !
    ['] _RTHP-RD-MARK-IN-PLANES SCR-WITH-PROJECTION-FRAME-PLANES ;

\ A complete build rebuilds every row.
: _RTHP-ROWS-ALL-REBUILT  ( producer -- )
    DUP _RTHP.ROW-DAMAGE-A @ ?DUP IF
        SWAP DUP _RTHP.ROWS @ SWAP _RTHP.ROW-DAMAGE-U @ MIN -1 FILL
    ELSE DROP THEN ;

\ The glyph banks already hold the plan a build would make when they hold
\ a plan of the same draw made from the same claims, menu claims, first
\ object ID, run text limit and surface: the planner reads nothing else.
\ A frame that needed more space from the terminal is built again for the
\ same draw once it has it, and keeps its runs.
VARIABLE _RTHP-GK-P

: _RTHP-GLYPHS-HELD?  ( producer -- flag )
    _RTHP-GK-P !
    _RTHP-GK-P @ _RTHP.GLYPH-DRAW @ DUP 0= IF DROP 0 EXIT THEN
        _RTHP-W-DRAW @ <> IF 0 EXIT THEN
    _RTHP-GK-P @ _RTHP.GLYPH-COLS @ _RTHP-GK-P @ _RTHP.COLS @ <> IF 0 EXIT THEN
    _RTHP-GK-P @ _RTHP.GLYPH-ROWS @ _RTHP-GK-P @ _RTHP.ROWS @ <> IF 0 EXIT THEN
    _RTHP-GK-P @ _RTHP.GLYPH-LIMIT @
        _RTHP-GK-P @ _RTHP.LIMITS RTE-LIMITS-GLYPH-RUN-BYTES@ <> IF 0 EXIT THEN
    _RTHP-GK-P @ _RTHP.GLYPH-MENUS @
        _RTHP-GK-P @ _RTHP.MENU-CLAIMS @ <> IF 0 EXIT THEN
    _RTHP-GK-P @ _RTHP.GLYPH-FIRST @ _RTHP-W-GLYPH-FIRST @ <> IF 0 EXIT THEN
    _RTHP-GK-P @ _RTHP.GLYPH-CLAIMS-USED @
        _RTHP-GK-P @ _RTHP.CLAIMS-USED @ <> IF 0 EXIT THEN
    _RTHP-GK-P @ _RTHP.GLYPH-CLAIMS-A @ _RTHP-GK-P @ _RTHP.GLYPH-CLAIMS-USED @
    _RTHP-GK-P @ _RTHP.CLAIMS-A @ _RTHP-GK-P @ _RTHP.CLAIMS-USED @
        COMPARE 0= ;

\ Record what the plan just built was made from.  Claims the copy cannot
\ hold leave a count no build has, so no later build keeps this plan.
: _RTHP-GLYPHS-KEEP  ( producer -- )
    _RTHP-GK-P !
    _RTHP-GK-P @ _RTHP.CLAIMS-USED @
    DUP _RTHP-GK-P @ _RTHP.GLYPH-CLAIMS-U @ U> IF
        DROP -1 _RTHP-GK-P @ _RTHP.GLYPH-CLAIMS-USED !
    ELSE
        DUP _RTHP-GK-P @ _RTHP.GLYPH-CLAIMS-USED !
        _RTHP-GK-P @ _RTHP.CLAIMS-A @ _RTHP-GK-P @ _RTHP.GLYPH-CLAIMS-A @
            ROT MOVE
    THEN
    _RTHP-GK-P @ _RTHP.MENU-CLAIMS @ _RTHP-GK-P @ _RTHP.GLYPH-MENUS !
    _RTHP-W-GLYPH-FIRST @ _RTHP-GK-P @ _RTHP.GLYPH-FIRST !
    _RTHP-GK-P @ _RTHP.LIMITS RTE-LIMITS-GLYPH-RUN-BYTES@
        _RTHP-GK-P @ _RTHP.GLYPH-LIMIT !
    _RTHP-GK-P @ _RTHP.COLS @ _RTHP-GK-P @ _RTHP.GLYPH-COLS !
    _RTHP-GK-P @ _RTHP.ROWS @ _RTHP-GK-P @ _RTHP.GLYPH-ROWS !
    _RTHP-GK-P @ _RTHP.GLYPH-COUNT @ _RTHP-GK-P @ _RTHP.GLYPH-RUNS !
    _RTHP-GK-P @ _RTHP.GLYPH-TEXT-USED @ _RTHP-GK-P @ _RTHP.GLYPH-TEXT !
    _RTHP-W-DRAW @ _RTHP-GK-P @ _RTHP.GLYPH-DRAW ! ;

\ Shadow check of the glyph shortcuts (frame-shadow.f).  A held plan and a
\ plan of only the damaged rows are shortcuts: planning every row must give
\ the same runs.  After either, the full planner runs over the same banks;
\ its counts, plan header, runs, references and text are compared with the
\ shortcut's, which a scratch block kept, as items 0 to 4.  The shortcut's
\ result and its row damage are then put back, so the frame goes on as it
\ would with the check off.
VARIABLE _RTHP-SG-A
VARIABLE _RTHP-SG-U
VARIABLE _RTHP-SG-P
VARIABLE _RTHP-SG-COUNT
VARIABLE _RTHP-SG-TEXT
VARIABLE _RTHP-SG-ROWS
VARIABLE _RTHP-SG-HEAD
VARIABLE _RTHP-SG-PLAN
VARIABLE _RTHP-SG-ITEMS
VARIABLE _RTHP-SG-REFS
VARIABLE _RTHP-SG-GLYPH-TEXT
VARIABLE _RTHP-SG-DAMAGE
VARIABLE _RTHP-SG-W-COUNT
VARIABLE _RTHP-SG-W-TEXT
VARIABLE _RTHP-SG-W-ALIGNED
VARIABLE _RTHP-SG-W-MAX
VARIABLE _RTHP-SG-W-LAST
VARIABLE _RTHP-SG-W-STATUS

: _RTHP-SG-ITEMS-U  ( count -- bytes )  RTE-GLYPH-RUN-PLAN-ITEM-SIZE * ;
: _RTHP-SG-REFS-U   ( count -- bytes )  RGRP-TEXT-REF-SIZE * ;

\ Scratch for the shortcut's result: two cells of its counts and two of the
\ full plan's, its plan header, runs, references, text and row damage.
: _RTHP-SG-LAYOUT?  ( -- flag )
    _RTHP-SG-P @ _RTHP.GLYPH-COUNT @ _RTHP-SG-COUNT !
    _RTHP-SG-P @ _RTHP.GLYPH-TEXT-USED @ _RTHP-SG-TEXT !
    _RTHP-SG-P @ _RTHP.ROW-DAMAGE-A @ IF
        _RTHP-SG-P @ _RTHP.ROWS @ _RTHP-SG-P @ _RTHP.ROW-DAMAGE-U @ MIN
    ELSE
        0
    THEN _RTHP-SG-ROWS !
    4 CELLS RTE-GLYPH-RUN-PLAN-SIZE +
    _RTHP-SG-COUNT @ _RTHP-SG-ITEMS-U +
    _RTHP-SG-COUNT @ _RTHP-SG-REFS-U +
    _RTHP-SG-TEXT @ 7 + -8 AND + _RTHP-SG-ROWS @ +
        _RTHP-SG-A _RTHP-SG-U FSHD-GROW
    DUP 0= IF EXIT THEN
    DUP _RTHP-SG-HEAD ! 4 CELLS +
    DUP _RTHP-SG-PLAN ! RTE-GLYPH-RUN-PLAN-SIZE +
    DUP _RTHP-SG-ITEMS ! _RTHP-SG-COUNT @ _RTHP-SG-ITEMS-U +
    DUP _RTHP-SG-REFS ! _RTHP-SG-COUNT @ _RTHP-SG-REFS-U +
    DUP _RTHP-SG-GLYPH-TEXT ! _RTHP-SG-TEXT @ 7 + -8 AND +
    _RTHP-SG-DAMAGE ! -1 ;

: _RTHP-SG-SAVE  ( -- )
    _RTHP-SG-COUNT @ _RTHP-SG-HEAD @ !
    _RTHP-SG-TEXT @ _RTHP-SG-HEAD @ CELL+ !
    _RTHP-SG-P @ _RTHP.GLYPH-PLAN _RTHP-SG-PLAN @ RTE-GLYPH-RUN-PLAN-SIZE MOVE
    _RTHP-SG-P @ _RTHP.GLYPH-ITEMS-A @ _RTHP-SG-ITEMS @
        _RTHP-SG-COUNT @ _RTHP-SG-ITEMS-U MOVE
    _RTHP-SG-P @ _RTHP.GLYPH-REFS-A @ _RTHP-SG-REFS @
        _RTHP-SG-COUNT @ _RTHP-SG-REFS-U MOVE
    _RTHP-SG-P @ _RTHP.GLYPH-TEXT-A @ _RTHP-SG-GLYPH-TEXT @
        _RTHP-SG-TEXT @ MOVE
    _RTHP-SG-P @ _RTHP.ROW-DAMAGE-A @ _RTHP-SG-DAMAGE @
        _RTHP-SG-ROWS @ MOVE ;

: _RTHP-SG-RESTORE  ( -- )
    _RTHP-SG-COUNT @ _RTHP-SG-P @ _RTHP.GLYPH-COUNT !
    _RTHP-SG-TEXT @ _RTHP-SG-P @ _RTHP.GLYPH-TEXT-USED !
    _RTHP-SG-PLAN @ _RTHP-SG-P @ _RTHP.GLYPH-PLAN RTE-GLYPH-RUN-PLAN-SIZE MOVE
    _RTHP-SG-ITEMS @ _RTHP-SG-P @ _RTHP.GLYPH-ITEMS-A @
        _RTHP-SG-COUNT @ _RTHP-SG-ITEMS-U MOVE
    _RTHP-SG-REFS @ _RTHP-SG-P @ _RTHP.GLYPH-REFS-A @
        _RTHP-SG-COUNT @ _RTHP-SG-REFS-U MOVE
    _RTHP-SG-GLYPH-TEXT @ _RTHP-SG-P @ _RTHP.GLYPH-TEXT-A @
        _RTHP-SG-TEXT @ MOVE
    _RTHP-SG-DAMAGE @ _RTHP-SG-P @ _RTHP.ROW-DAMAGE-A @
        _RTHP-SG-ROWS @ MOVE ;

\ The full plan, keeping the build's own results as they were.  A plan the
\ full planner refuses counts as a plan of no length, which differs.
: _RTHP-SG-FULL  ( -- )
    _RTHP-W-COUNT @ _RTHP-SG-W-COUNT ! _RTHP-W-TEXT @ _RTHP-SG-W-TEXT !
    _RTHP-W-ALIGNED @ _RTHP-SG-W-ALIGNED ! _RTHP-W-MAX @ _RTHP-SG-W-MAX !
    _RTHP-W-LAST @ _RTHP-SG-W-LAST ! _RTHP-W-STATUS @ _RTHP-SG-W-STATUS !
    _RTHP-SG-P @ _RTHP-BUILD-GLYPHS-FULL? IF
        _RTHP-SG-P @ _RTHP.GLYPH-COUNT @
        _RTHP-SG-P @ _RTHP.GLYPH-TEXT-USED @
    ELSE
        -1 -1
    THEN
    _RTHP-SG-HEAD @ 3 CELLS + ! _RTHP-SG-HEAD @ 2 CELLS + !
    _RTHP-SG-W-COUNT @ _RTHP-W-COUNT ! _RTHP-SG-W-TEXT @ _RTHP-W-TEXT !
    _RTHP-SG-W-ALIGNED @ _RTHP-W-ALIGNED ! _RTHP-SG-W-MAX @ _RTHP-W-MAX !
    _RTHP-SG-W-LAST @ _RTHP-W-LAST ! _RTHP-SG-W-STATUS @ _RTHP-W-STATUS ! ;

: _RTHP-SG-COMPARE  ( -- )
    _RTHP-SG-HEAD @ 2 CELLS _RTHP-SG-HEAD @ 2 CELLS + 2 CELLS
        0 FSHD-STAGE-PRODUCER-GLYPHS FSHD-SAME? 0= IF EXIT THEN
    _RTHP-SG-PLAN @ RTE-GLYPH-RUN-PLAN-SIZE
    _RTHP-SG-P @ _RTHP.GLYPH-PLAN RTE-GLYPH-RUN-PLAN-SIZE
        1 FSHD-STAGE-PRODUCER-GLYPHS FSHD-SAME? DROP
    _RTHP-SG-ITEMS @ _RTHP-SG-COUNT @ _RTHP-SG-ITEMS-U
    _RTHP-SG-P @ _RTHP.GLYPH-ITEMS-A @ _RTHP-SG-COUNT @ _RTHP-SG-ITEMS-U
        2 FSHD-STAGE-PRODUCER-GLYPHS FSHD-SAME? DROP
    _RTHP-SG-REFS @ _RTHP-SG-COUNT @ _RTHP-SG-REFS-U
    _RTHP-SG-P @ _RTHP.GLYPH-REFS-A @ _RTHP-SG-COUNT @ _RTHP-SG-REFS-U
        3 FSHD-STAGE-PRODUCER-GLYPHS FSHD-SAME? DROP
    _RTHP-SG-GLYPH-TEXT @ _RTHP-SG-TEXT @
    _RTHP-SG-P @ _RTHP.GLYPH-TEXT-A @ _RTHP-SG-TEXT @
        4 FSHD-STAGE-PRODUCER-GLYPHS FSHD-SAME? DROP ;

: _RTHP-SH-GLYPHS  ( producer -- )
    _RTHP-SG-P !
    _RTHP-W-DRAW @ FSHD-DRAW !
    _RTHP-SG-LAYOUT? 0= IF FSHD-SKIP EXIT THEN
    _RTHP-SG-SAVE
    _RTHP-SG-FULL
    _RTHP-SG-COMPARE
    _RTHP-SG-RESTORE ;

\ Either way the visible runs are those of the planes of the draw being
\ built, with the candidate's claims, which GLYPH-DRAW then records.  A
\ plan the banks hold already is kept as a complete build leaves it.  In
\ safe mode (check-mode.f) every draw's plan is built whole.
\ A document's roots may lie beneath its own overlay, or an overlay pane's
\ document (RUHA-LAYERS!), only while what lies above them is in the
\ candidate, with claims over all the cells they share, since that is what
\ shows there.  A family refused after the roots
\ beneath it were admitted, for space or by the terminal, would leave them
\ claiming cells where CELL shows the overlay, so such a draw cannot be
\ shown rich.
VARIABLE _RTHP-LC-P VARIABLE _RTHP-LC-DOC VARIABLE _RTHP-LC-CLAIM
VARIABLE _RTHP-LC-MET VARIABLE _RTHP-LC-HELD
VARIABLE _RTHP-LC-R0 VARIABLE _RTHP-LC-C0 VARIABLE _RTHP-LC-R1 VARIABLE _RTHP-LC-C1
: _RTHP-LC-AREA!  ( row col height width -- )
    2 PICK + _RTHP-LC-C1 ! 2 PICK + _RTHP-LC-R1 !
    _RTHP-LC-C0 ! _RTHP-LC-R0 ! ;
: _RTHP-LC-MEETS?  ( claim -- flag )
    DUP RUCL-CLAIM-ROW0@ _RTHP-LC-R1 @ <
    OVER RUCL-CLAIM-ROW1@ _RTHP-LC-R0 @ > AND
    OVER RUCL-CLAIM-COL0@ _RTHP-LC-C1 @ < AND
    SWAP RUCL-CLAIM-COL1@ _RTHP-LC-C0 @ > AND ;
: _RTHP-LC-HOLDS?  ( claim -- flag )
    DUP RUCL-CLAIM-ROW0@ _RTHP-LC-R0 @ > 0=
    OVER RUCL-CLAIM-ROW1@ _RTHP-LC-R1 @ < 0= AND
    OVER RUCL-CLAIM-COL0@ _RTHP-LC-C0 @ > 0= AND
    SWAP RUCL-CLAIM-COL1@ _RTHP-LC-C1 @ < 0= AND ;
: _RTHP-LC-DOCUMENT?  ( -- flag )
    _RTHP-LC-DOC @ RUHA-DOCUMENT-OVERLAY@
    DUP 0> 2 PICK 0> AND 0= IF 2DROP 2DROP -1 EXIT THEN
    _RTHP-LC-AREA! 0 _RTHP-LC-MET ! 0 _RTHP-LC-HELD !
    _RTHP-LC-P @ _RTHP.CLAIMS-USED @ RUCL-CLAIM-SIZE / 0 ?DO
        _RTHP-LC-P @ _RTHP.CLAIMS-A @ I RUCL-CLAIM-SIZE * + _RTHP-LC-CLAIM !
        _RTHP-LC-CLAIM @ RUCL-CLAIM-ATTACHMENT@
            _RTHP-LC-DOC @ RUHA-DOCUMENT-TOKEN@ = IF
            _RTHP-LC-CLAIM @ RUCL-CLAIM-SOURCE@ _RTHP-OVERLAY-SOURCE? IF
                _RTHP-LC-CLAIM @ _RTHP-LC-HOLDS? IF -1 _RTHP-LC-HELD ! THEN
            ELSE
                _RTHP-LC-CLAIM @ _RTHP-LC-MEETS? IF -1 _RTHP-LC-MET ! THEN
            THEN
        THEN
    LOOP
    _RTHP-LC-MET @ 0= _RTHP-LC-HELD @ OR ;
\ An overlay pane's document paints all of its cells, so wherever a claim
\ of a document beneath it meets them, one claim of the pane's document
\ must hold that part.
VARIABLE _RTHP-LC-LOWER VARIABLE _RTHP-LC-UPPER
: _RTHP-LC-HOLDS-PART?  ( -- flag )
    _RTHP-LC-UPPER @ RUCL-CLAIM-ROW0@
        _RTHP-LC-LOWER @ RUCL-CLAIM-ROW0@ _RTHP-LC-R0 @ MAX > 0=
    _RTHP-LC-UPPER @ RUCL-CLAIM-ROW1@
        _RTHP-LC-LOWER @ RUCL-CLAIM-ROW1@ _RTHP-LC-R1 @ MIN < 0= AND
    _RTHP-LC-UPPER @ RUCL-CLAIM-COL0@
        _RTHP-LC-LOWER @ RUCL-CLAIM-COL0@ _RTHP-LC-C0 @ MAX > 0= AND
    _RTHP-LC-UPPER @ RUCL-CLAIM-COL1@
        _RTHP-LC-LOWER @ RUCL-CLAIM-COL1@ _RTHP-LC-C1 @ MIN < 0= AND ;
: _RTHP-LC-HELD-BENEATH?  ( -- flag )
    _RTHP-LC-P @ _RTHP.CLAIMS-USED @ RUCL-CLAIM-SIZE / 0 ?DO
        _RTHP-LC-P @ _RTHP.CLAIMS-A @ I RUCL-CLAIM-SIZE * + _RTHP-LC-UPPER !
        _RTHP-LC-UPPER @ RUCL-CLAIM-ATTACHMENT@ _RTHP-LC-DOC @ RUHA-DOCUMENT-TOKEN@ =
        _RTHP-LC-HOLDS-PART? AND IF -1 UNLOOP EXIT THEN
    LOOP 0 ;
: _RTHP-LC-PANE?  ( -- flag )
    _RTHP-LC-DOC @ RUHA-DOCUMENT-ROW@ _RTHP-LC-DOC @ RUHA-DOCUMENT-COL@
    _RTHP-LC-DOC @ RUHA-DOCUMENT-HEIGHT@ _RTHP-LC-DOC @ RUHA-DOCUMENT-WIDTH@
        _RTHP-LC-AREA!
    _RTHP-LC-P @ _RTHP.CLAIMS-USED @ RUCL-CLAIM-SIZE / 0 ?DO
        _RTHP-LC-P @ _RTHP.CLAIMS-A @ I RUCL-CLAIM-SIZE * + _RTHP-LC-LOWER !
        _RTHP-LC-LOWER @ _RTHP-LC-MEETS?
        _RTHP-LC-LOWER @ RUCL-CLAIM-ATTACHMENT@ _RTHP-LC-P @ _RTHP-LAYER-OF
            _RTHP-LC-DOC @ RUHA-DOCUMENT-LAYER@ < AND IF
            _RTHP-LC-HELD-BENEATH? 0= IF 0 UNLOOP EXIT THEN
        THEN
    LOOP -1 ;
: _RTHP-LAYERS-COVERED?  ( producer -- flag )
    _RTHP-LC-P !
    _RTHP-LC-P @ _RTHP.DOCUMENT-COUNT @ 0 ?DO
        I _RTHP-LC-P @ _RTHP-DOCUMENT-AT _RTHP-LC-DOC !
        _RTHP-LC-DOCUMENT? 0= IF 0 UNLOOP EXIT THEN
        _RTHP-LC-DOC @ RUHA-DOCUMENT-LAYER@ IF
            _RTHP-LC-PANE? 0= IF 0 UNLOOP EXIT THEN
        THEN
    LOOP -1 ;

\ _RTHP-CROSS-LAYERED? ( producer -- flag )
\   A claim of a document meets the cells of an overlay pane's document
\   above it.
: _RTHP-CROSS-LAYERED?  ( producer -- flag )
    _RTHP-LC-P !
    _RTHP-LC-P @ _RTHP.DOCUMENT-COUNT @ 0 ?DO
        I _RTHP-LC-P @ _RTHP-DOCUMENT-AT _RTHP-LC-DOC !
        _RTHP-LC-DOC @ RUHA-DOCUMENT-LAYER@ IF
            _RTHP-LC-DOC @ RUHA-DOCUMENT-ROW@ _RTHP-LC-DOC @ RUHA-DOCUMENT-COL@
            _RTHP-LC-DOC @ RUHA-DOCUMENT-HEIGHT@ _RTHP-LC-DOC @ RUHA-DOCUMENT-WIDTH@
                _RTHP-LC-AREA!
            _RTHP-LC-P @ _RTHP.CLAIMS-USED @ RUCL-CLAIM-SIZE / 0 ?DO
                _RTHP-LC-P @ _RTHP.CLAIMS-A @ I RUCL-CLAIM-SIZE * + _RTHP-LC-LOWER !
                _RTHP-LC-LOWER @ _RTHP-LC-MEETS?
                _RTHP-LC-LOWER @ RUCL-CLAIM-ATTACHMENT@ _RTHP-LC-P @ _RTHP-LAYER-OF
                    _RTHP-LC-DOC @ RUHA-DOCUMENT-LAYER@ < AND IF
                    -1 UNLOOP UNLOOP EXIT
                THEN
            LOOP
        THEN
    LOOP 0 ;

\ What the residue of any plan of this draw needs: no omitted graph meets
\ a claim, and every root beneath an overlay lies under claims of it.
: _RTHP-RESIDUE-GATES?  ( producer -- flag )
    DUP _RTHP-OMITTED-DISJOINT? 0= IF
        DROP RGRP-S-UNREPRESENTABLE _RTHP-W-STATUS ! 0 EXIT
    THEN
    _RTHP-LAYERS-COVERED? 0= IF
        RGRP-S-UNREPRESENTABLE _RTHP-W-STATUS ! 0 EXIT
    THEN -1 ;

\ With Desk's shell installed, a build of the candidate's own runs is a
\ build alone, from a frame on screen whose runs are the shell's, which no
\ bank of this producer holds, so it plans every row.
: _RTHP-BUILD-GLYPHS?  ( producer -- flag )
    DUP _RTHP-RESIDUE-GATES? 0= IF DROP 0 EXIT THEN
    CHK-SAFE? IF 0 ELSE DUP _RTHP-GLYPHS-HELD? THEN IF
        DUP _RTHP.GLYPH-RUNS @ OVER _RTHP.GLYPH-COUNT !
        DUP _RTHP.GLYPH-TEXT @ OVER _RTHP.GLYPH-TEXT-USED !
        DUP _RTHP-ROWS-ALL-REBUILT
        DUP _RTHP.GLYPH-RUNS @ OVER _RTHP-WRAP-GLYPH-PLAN? IF
            FSHD? IF DUP _RTHP-SH-GLYPHS THEN
            DROP -1 EXIT
        THEN
    THEN
    0 OVER _RTHP.GLYPH-DRAW !
    CHK-SAFE? OVER _RTHP.EXTENSION @ 0<> OR IF 0 ELSE DUP _RTHP-BUILD-GLYPHS-DAMAGE? THEN IF
        FSHD? IF DUP _RTHP-SH-GLYPHS THEN
    ELSE
        DUP _RTHP-ROWS-ALL-REBUILT
        DUP _RTHP-BUILD-GLYPHS-FULL? 0= IF DROP 0 EXIT THEN
    THEN
    _RTHP-GLYPHS-KEEP -1 ;

\ For Desk's shell, which plans the runs of its own regions from the same
\ planes and claims: the residue passes the same gates, the candidate holds
\ no runs, and ROW-DAMAGE names the rows the shell's plans must build again
\ (every row in safe mode, or when the frame on screen cannot vouch for
\ the others).  The glyph banks then hold no plan of any draw.
: _RTHP-SHELL-RESIDUE?  ( producer -- flag )
    DUP _RTHP-RESIDUE-GATES? 0= IF DROP 0 EXIT THEN
    0 OVER _RTHP.GLYPH-DRAW !
    CHK-SAFE? IF 0 ELSE DUP _RTHP-MARK-GLYPHS-DAMAGE? THEN
        0= IF DUP _RTHP-ROWS-ALL-REBUILT THEN
    0 OVER _RTHP.GLYPH-COUNT ! 0 OVER _RTHP.GLYPH-TEXT-USED !
    0 SWAP _RTHP-WRAP-GLYPH-PLAN? ;

\ _RTHP-W-GLYPH-REFUSAL ( -- rte-status )
\   Why the glyph plan that _RTHP-BUILD-GLYPHS? just refused was refused.
\   A plan that outgrows the glyph banks is CAPACITY: the text bank holds
\   four bytes a cell, the most a cell of one scalar needs, so characters of
\   several scalars can outgrow it.  A cell the retained plane cannot show,
\   a blinking one or one wider than a glyph run, is UNAVAILABLE.  Only a
\   broken plane or request is INVALID.  The frame is then handled as any
\   frame that cannot be shown rich.
: _RTHP-W-GLYPH-REFUSAL  ( -- rte-status )
    _RTHP-W-STATUS @ DUP RGRP-S-CAPACITY = IF DROP RTE-S-CAPACITY EXIT THEN
    RGRP-S-UNREPRESENTABLE = IF RTE-S-UNAVAILABLE EXIT THEN
    RTE-S-INVALID ;

\ A candidate never speculates about future glyph growth.  A new/replacement
\ START has exactly the current glyph topology.  A smaller draw may preserve
\ already-acknowledged slots so DELTA clears its unused tail.  Genuine growth
\ may append visible glyphs only when that live namespace ends at the owner
\ frontier and the semantic control graph has no additions.
VARIABLE _RTHP-R-P
VARIABLE _RTHP-R-ACTUAL
VARIABLE _RTHP-R-CEILING
VARIABLE _RTHP-R-BANK-U
VARIABLE _RTHP-R-USED
VARIABLE _RTHP-R-BYTES
VARIABLE _RTHP-R-TARGET
VARIABLE _RTHP-R-SLOTS
VARIABLE _RTHP-R-ACTIVE
VARIABLE _RTHP-R-ITEM
VARIABLE _RTHP-R-REF

: _RTHP-R-ADD?  ( bytes -- flag )
    _RTHP-R-USED @ SWAP _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-R-USED ! -1 ;

: _RTHP-R-MUL-ADD?  ( count item-bytes -- flag )
    _RTHP-U32*? 0= IF DROP 0 EXIT THEN _RTHP-R-ADD? ;

: _RTHP-R-LIMIT  ( slots -- )
    _RTHP-R-CEILING @ _RTHP-UMIN _RTHP-R-CEILING ! ;

: _RTHP-R-REMAINING-LIMIT  ( total used -- )
    2DUP U< IF 2DROP 0 ELSE - THEN _RTHP-R-LIMIT ;

: _RTHP-R-BANK-CEILING?  ( -- flag )
    _RTHP-R-P @ _RTHP-TARGET-BANK-BYTES?
        0= IF DROP 0 EXIT THEN _RTHP-R-BANK-U !
    _RTHP-TARGET-BANK-HEADER-SIZE _RTHP-R-USED !
    \ TARGET-CANDIDATE has not run yet.  Every control is therefore retained
    \ as the conservative upper bound for its menu-or-tab target prefix.
    _RTHP-R-P @ _RTHP.CONTROL-COUNT @ _RTHP-TARGET-ENTRY-SIZE
        _RTHP-R-MUL-ADD? 0= IF 0 EXIT THEN
    _RTHP-R-P @ _RTHP.CONTROL-COUNT @ RTE-CONTROL-SIZE
        _RTHP-R-MUL-ADD? 0= IF 0 EXIT THEN
    _RTHP-R-P @ _RTHP.CONTROL-COUNT @ RUCP-CORRELATION-SIZE
        _RTHP-R-MUL-ADD? 0= IF 0 EXIT THEN
    _RTHP-R-P @ _RTHP.SOURCE-TEXT-USED @ _RTHP-ALIGN8?
        0= IF DROP 0 EXIT THEN _RTHP-R-ADD? 0= IF 0 EXIT THEN
    _RTHP-R-P @ _RTHP.GLYPH-TEXT-USED @ _RTHP-ALIGN8?
        0= IF DROP 0 EXIT THEN _RTHP-R-ADD? 0= IF 0 EXIT THEN
    _RTHP-R-P @ _RTHP.DOCUMENT-COUNT @ RUHA-DOCUMENT-SIZE
        _RTHP-R-MUL-ADD? 0= IF 0 EXIT THEN
    _RTHP-R-P @ _RTHP.ROWS @ _RTHP-ALIGN8?
        0= IF DROP 0 EXIT THEN _RTHP-R-ADD? 0= IF 0 EXIT THEN
    _RTHP-R-P @ _RTHP.INSTRUMENT-REGION-COUNT @
    _RTHP-R-P @ _RTHP.INSTRUMENT-COUNT @
    _RTHP-R-P @ _RTHP.INSTRUMENT-UNITS-USED @
        _RTHP-INSTRUMENT-BANK-BYTES? 0= IF DROP 0 EXIT THEN
        _RTHP-R-ADD? 0= IF 0 EXIT THEN
    _RTHP-R-P @ _RTHP.STATIC-COUNT @ _RTHP-R-P @ _RTHP.STATIC-TEXT-USED @
        _RTHP-STATIC-BANK-BYTES? 0= IF DROP 0 EXIT THEN
        _RTHP-R-ADD? 0= IF 0 EXIT THEN
    _RTHP-R-P @ _RTHP.SERIES-COUNT @ _RTHP-R-P @ _RTHP.SERIES-SAMPLES-USED @
        _RTHP-SERIES-BANK-BYTES? 0= IF DROP 0 EXIT THEN
        _RTHP-R-ADD? 0= IF 0 EXIT THEN
    _RTHP-R-USED @ _RTHP-R-BANK-U @ U> IF 0 EXIT THEN
    _RTHP-R-BANK-U @ _RTHP-R-USED @ -
    RTE-GLYPH-RUN-PLAN-ITEM-SIZE RGRP-TEXT-REF-SIZE + /
        _RTHP-R-CEILING !
    -1 ;

: _RTHP-R-SLOT-CEILING?  ( -- flag )
    _RTHP-R-BANK-CEILING? 0= IF 0 EXIT THEN
    _RTHP-R-P @ _RTHP.COLS @ _RTHP-R-P @ _RTHP.ROWS @ _RTHP-U32*?
        0= IF DROP 0 EXIT THEN _RTHP-R-LIMIT
    _RTHP-R-P @ _RTHP.GLYPH-ITEMS-U @
        RTE-GLYPH-RUN-PLAN-ITEM-SIZE / _RTHP-R-LIMIT
    _RTHP-R-P @ _RTHP.GLYPH-REFS-U @ RGRP-TEXT-REF-SIZE /
        _RTHP-R-LIMIT
    _RTHP-R-P @ _RTHP.CONTROL-COUNT @
    _RTHP-R-P @ _RTHP.COLLECTION-ITEMS @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    _RTHP-R-P @ _RTHP.FIELD-ITEMS @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    _RTHP-R-P @ _RTHP.INSTRUMENT-COUNT @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    _RTHP-R-P @ _RTHP.STATIC-COUNT @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    _RTHP-R-P @ _RTHP.LIMITS RTE-LIMITS-OBJECTS@ SWAP
        _RTHP-R-REMAINING-LIMIT
    _RTHP-R-P @ _RTHP.CONTROL-COUNT @
    _RTHP-R-P @ _RTHP.INSTRUMENT-COUNT @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    _RTHP-R-P @ _RTHP.STATIC-COUNT @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    _RTHP-R-P @ _RTHP.INSTRUMENT-REGION-COUNT @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    _RTHP-R-P @ _RTHP.CONTROL-COUNT @
    _RTHP-R-P @ _RTHP.GLYPH-COUNT @ OR
    _RTHP-R-P @ _RTHP.STATIC-COUNT @ OR IF
        1 _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    THEN
    _RTHP-R-P @ _RTHP.SERIES-COUNT @ _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-R-P @ _RTHP.SERIES-CHUNKS @ _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-R-P @ _RTHP.LIMITS RTE-LIMITS-OPS@ SWAP
        _RTHP-R-REMAINING-LIMIT
    -1 ;

: _RTHP-R-PLAN-SLOTS?  ( slots -- flag )
    DUP _RTHP-R-SLOTS !
    RTE-GLYPH-RUN-PLAN-ITEM-SIZE _RTHP-U32*?
        0= IF DROP 0 EXIT THEN _RTHP-R-BYTES !
    _RTHP-R-P @ _RTHP.GLYPH-PLAN RTE-GLYPH-RUN-PLAN-SIZE 0 FILL
    _RTHP-R-SLOTS @ 0= IF -1 EXIT THEN
    _RTHP-R-P @ _RTHP.OWNER @
        _RTHP-R-P @ _RTHP.GLYPH-PLAN _RTE-LP.OWNER !
    _RTHP-R-P @ _RTHP.OWNER-GEN @
        _RTHP-R-P @ _RTHP.GLYPH-PLAN _RTE-LP.GENERATION !
    _RTHP-R-P @ _RTHP.COLS @
        _RTHP-R-P @ _RTHP.GLYPH-PLAN _RTE-LP.SURFACE-COLS !
    _RTHP-R-P @ _RTHP.ROWS @
        _RTHP-R-P @ _RTHP.GLYPH-PLAN _RTE-LP.SURFACE-ROWS !
    _RTHP-R-P @ _RTHP.REGION @
        _RTHP-R-P @ _RTHP.GLYPH-PLAN _RTE-LP.REGION-ID !
    _RTHP-R-P @ _RTHP.COLS @
        _RTHP-R-P @ _RTHP.GLYPH-PLAN _RTE-LP.REGION-COLS !
    _RTHP-R-P @ _RTHP.ROWS @
        _RTHP-R-P @ _RTHP.GLYPH-PLAN _RTE-LP.REGION-ROWS !
    0 _RTHP-R-P @ _RTHP.GLYPH-PLAN _RTE-LP.CLIP-X !
    0 _RTHP-R-P @ _RTHP.GLYPH-PLAN _RTE-LP.CLIP-Y !
    0 _RTHP-R-P @ _RTHP.GLYPH-PLAN _RTE-LP.CLIP-COLS !
    0 _RTHP-R-P @ _RTHP.GLYPH-PLAN _RTE-LP.CLIP-ROWS !
    RTE-REGION-VISIBLE
        _RTHP-R-P @ _RTHP.GLYPH-PLAN _RTE-LP.REGION-FLAGS !
    _RTHP-R-P @ _RTHP.GLYPH-ITEMS-A @
        _RTHP-R-P @ _RTHP.GLYPH-PLAN _RTE-LP.ITEMS-A !
    _RTHP-R-BYTES @ _RTHP-R-P @ _RTHP.GLYPH-PLAN _RTE-LP.ITEMS-U !
    -1 ;

: _RTHP-STRIP-GLYPH-RESERVE  ( producer -- )
    _RTHP-R-P !
    _RTHP-R-ACTUAL @ _RTHP-R-PLAN-SLOTS? DROP
    _RTHP-R-ACTUAL @ _RTHP-R-P @ _RTHP.GLYPH-COUNT ! ;

: _RTHP-RESERVE-GLYPHS?  ( producer -- flag )
    _RTHP-R-P !
    _RTHP-R-P @ _RTHP.GLYPH-COUNT @ DUP _RTHP-R-ACTUAL !
        _RTHP-R-TARGET !
    _RTHP-R-SLOT-CEILING? 0= IF -1 EXIT THEN

    \ Reuse only an already acknowledged topology which still fits every
    \ current storage/provider bound.  New banks and topology growth retain
    \ the exact current count; later DELTA admission independently decides
    \ whether actual glyph growth can extend the acknowledged frontier.
    0 _RTHP-R-ACTIVE !
    _RTHP-R-P @ _RTHP.TARGET-ACTIVE @ DUP IF
        DUP _RTHP-R-P @ _RTHP-TARGET-BANK-HEADER? IF
            _RTHP-R-ACTIVE !
        ELSE
            DROP
        THEN
    ELSE
        DROP
    THEN
    _RTHP-R-ACTIVE @ IF
        _RTHP-R-ACTIVE @ _RTHP-TB.GLYPH-SLOT-COUNT @ _RTHP-R-SLOTS !
        _RTHP-R-SLOTS @ _RTHP-R-ACTUAL @ U< 0=
        _RTHP-R-SLOTS @ _RTHP-R-CEILING @ U> 0= AND IF
            _RTHP-R-SLOTS @ _RTHP-R-TARGET !
        THEN
    THEN
    _RTHP-R-TARGET @ _RTHP-R-ACTUAL @ = IF -1 EXIT THEN

    \ Prove the next object ID as well as the last reserved ID so padding can
    \ never turn a valid real candidate into an ID-wrap failure later.
    _RTHP-W-GLYPH-FIRST @ DUP 0= IF DROP -1 EXIT THEN
    _RTHP-R-TARGET @ _RTHP-U+? 0= IF DROP -1 EXIT THEN DROP

    _RTHP-R-TARGET @ _RTHP-R-ACTUAL @ ?DO
        _RTHP-R-P @ _RTHP.GLYPH-ITEMS-A @
            I RTE-GLYPH-RUN-PLAN-ITEM-SIZE * + DUP _RTHP-R-ITEM !
            RTE-GLYPH-RUN-PLAN-ITEM-SIZE 0 FILL
        _RTHP-W-GLYPH-FIRST @ I +
            _RTHP-R-ITEM @ _RTE-LPI.OBJECT !
        1 _RTHP-R-ITEM @ _RTE-LPI.HEIGHT !
        1 _RTHP-R-ITEM @ _RTE-LPI.WIDTH !
        _RTHP-R-P @ _RTHP.ROWS @
            _RTHP-R-ITEM @ _RTE-LPI.ROOT-HEIGHT !
        _RTHP-R-P @ _RTHP.COLS @
            _RTHP-R-ITEM @ _RTE-LPI.ROOT-WIDTH !
        _RTHP-R-P @ _RTHP.GLYPH-REFS-A @
            I RGRP-TEXT-REF-SIZE * + DUP _RTHP-R-REF !
            RGRP-TEXT-REF-SIZE 0 FILL
        _RTHP-R-P @ _RTHP.GLYPH-TEXT-USED @
            _RTHP-R-REF @ _RGRP-T.OFFSET !
    LOOP
    _RTHP-R-TARGET @ _RTHP-R-PLAN-SLOTS? 0= IF
        _RTHP-R-P @ _RTHP-STRIP-GLYPH-RESERVE
        -1 EXIT
    THEN
    _RTHP-R-TARGET @ _RTHP-R-P @ _RTHP.GLYPH-COUNT !
    -1 ;

: _RTHP-WRAP-HYBRID  ( producer -- )
    DUP _RTHP-BASE-LAYER! DROP _RTHP-W-P !
    _RTHP-W-P @ _RTHP.HYBRID RTE-HYBRID-PLAN-SIZE 0 FILL
    _RTHP-W-P @ _RTHP.ATTEMPT @
        _RTHP-W-P @ _RTHP.HYBRID _RTE-HP.ATTEMPT !
    _RTHP-W-P @ _RTHP.SOURCE-GEN @
        _RTHP-W-P @ _RTHP.HYBRID _RTE-HP.SOURCE-GENERATION !
    _RTHP-W-P @ _RTHP.SOURCE-DRAW @
        _RTHP-W-P @ _RTHP.HYBRID _RTE-HP.SURFACE-GENERATION !
    _RTHP-W-P @ _RTHP.CONTROL-COUNT @ IF
        _RTHP-W-P @ _RTHP.CONTROL-PLAN
            _RTHP-W-P @ _RTHP.HYBRID _RTE-HP.CONTROL-PLAN !
        _RTHP-W-P @ _RTHP.SOURCE-TEXT-USED @ IF
            _RTHP-W-P @ _RTHP.SOURCE-TEXT-A @
                _RTHP-W-P @ _RTHP.HYBRID _RTE-HP.CONTROL-BYTES-A !
        THEN
        _RTHP-W-P @ _RTHP.SOURCE-TEXT-USED @
            _RTHP-W-P @ _RTHP.HYBRID _RTE-HP.CONTROL-BYTES-U !
    THEN
    _RTHP-W-P @ _RTHP.SERIES-COUNT @ IF
        _RTHP-W-P @ _RTHP.SERIES-PLAN
            _RTHP-W-P @ _RTHP.HYBRID _RTE-HP.SERIES-PLAN !
        _RTHP-W-P @ _RTHP.SERIES-SAMPLES-USED @ IF
            _RTHP-W-P @ _RTHP.SERIES-SAMPLES-A @
                _RTHP-W-P @ _RTHP.HYBRID _RTE-HP.SERIES-SAMPLES-A !
        THEN
        _RTHP-W-P @ _RTHP.SERIES-SAMPLES-USED @
            _RTHP-W-P @ _RTHP.HYBRID _RTE-HP.SERIES-SAMPLES-U !
    THEN
    _RTHP-W-P @ _RTHP.INSTRUMENT-COUNT @ IF
        _RTHP-W-P @ _RTHP.INSTRUMENT-PLAN
            _RTHP-W-P @ _RTHP.HYBRID _RTE-HP.INSTRUMENT-PLAN !
        _RTHP-W-P @ _RTHP.INSTRUMENT-UNITS-USED @ IF
            _RTHP-W-P @ _RTHP.INSTRUMENT-UNITS-A @
                _RTHP-W-P @ _RTHP.HYBRID
                    _RTE-HP.INSTRUMENT-BYTES-A !
        THEN
        _RTHP-W-P @ _RTHP.INSTRUMENT-UNITS-USED @
            _RTHP-W-P @ _RTHP.HYBRID _RTE-HP.INSTRUMENT-BYTES-U !
    THEN
    _RTHP-W-P @ _RTHP.STATIC-COUNT @ IF
        _RTHP-W-P @ _RTHP.STATIC-PLAN
            _RTHP-W-P @ _RTHP.HYBRID _RTE-HP.STATIC-PLAN !
        _RTHP-W-P @ _RTHP.STATIC-TEXT-USED @ IF
            _RTHP-W-P @ _RTHP.STATIC-TEXT-A @
                _RTHP-W-P @ _RTHP.HYBRID _RTE-HP.STATIC-BYTES-A !
        THEN
        _RTHP-W-P @ _RTHP.STATIC-TEXT-USED @
            _RTHP-W-P @ _RTHP.HYBRID _RTE-HP.STATIC-BYTES-U !
    THEN
    _RTHP-W-P @ _RTHP.GLYPH-COUNT @ IF
        _RTHP-W-P @ _RTHP.GLYPH-PLAN
            _RTHP-W-P @ _RTHP.HYBRID _RTE-HP.GLYPH-PLAN !
        _RTHP-W-P @ _RTHP.GLYPH-REFS-A @
            _RTHP-W-P @ _RTHP.HYBRID _RTE-HP.GLYPH-REFS-A !
        _RTHP-W-P @ _RTHP.GLYPH-COUNT @ RGRP-TEXT-REF-SIZE *
            _RTHP-W-P @ _RTHP.HYBRID _RTE-HP.GLYPH-REFS-U !
        _RTHP-W-P @ _RTHP.GLYPH-TEXT-USED @ IF
            _RTHP-W-P @ _RTHP.GLYPH-TEXT-A @
                _RTHP-W-P @ _RTHP.HYBRID _RTE-HP.GLYPH-TEXT-A !
        THEN
        _RTHP-W-P @ _RTHP.GLYPH-TEXT-USED @
            _RTHP-W-P @ _RTHP.HYBRID _RTE-HP.GLYPH-TEXT-U !
    THEN ;

: _RTHP-W-PREFLIGHT-HYBRID  ( -- rte-status )
    BEGIN
        \ Base-layer derivation and its refusal are neutral profile time.
        _RTPROF-PH-OTHER _RTPROF-MARK
        _RTHP-W-P @ _RTHP-BASE-LAYER! 0= IF RTE-S-UNAVAILABLE EXIT THEN
        _RTPROF-PH-HYBRID-PREFLIGHT _RTPROF-MARK
        _RTHP-W-P @ _RTHP.ADMISSION RTE-HYBRID-ADMISSION-SIZE 0 FILL
        _RTHP-W-P @ _RTHP.HYBRID _RTHP-W-P @ _RTHP.ADMISSION
        _RTHP-W-P @ _RTHP.FACADE @ RTE-HYBRID-PREFLIGHT
        _RTPROF-PH-OTHER _RTPROF-MARK
        DUP _RTHP-W-STATUS !
        DUP RTE-S-CAPACITY =
        _RTHP-W-P @ _RTHP.GLYPH-COUNT @ _RTHP-R-ACTUAL @ U> AND
    WHILE
        DROP
        _RTPROF-PH-RESERVE-WRAP _RTPROF-MARK
        _RTHP-W-P @ _RTHP-STRIP-GLYPH-RESERVE
        _RTHP-W-P @ _RTHP-WRAP-HYBRID
        _RTPROF-PH-OTHER _RTPROF-MARK
    REPEAT ;

\ A refusal of Desk's own memory also keeps the bytes asked for and held.
VARIABLE _RTHP-W-MEMORY-ASKED
VARIABLE _RTHP-W-MEMORY-HELD

\ The frame did not fit.  First let the provider grow its own working
\ storage, from the memory its caller gave it, to what the admission
\ needed.  The first refusal of a draw is kept for the fallback record: it
\ is what the whole frame needed.
: _RTHP-GROW-STORAGE?  ( producer -- grew? )
    _RTHP.FACADE @ RTE-STORAGE-GROW
    DUP RTE-S-OK = IF DROP 2DROP -1 EXIT THEN
    RTE-S-CAPACITY = _RTHP-W-MEMORY-ASKED @ 0= AND IF
        _RTHP-W-MEMORY-HELD ! _RTHP-W-MEMORY-ASKED !
    ELSE 2DROP THEN 0 ;

\ Admit the candidate.  A frame that does not fit first lets the provider
\ grow its working storage to what the admission needed, from the memory
\ its caller gave it, and is admitted once more.  Every smaller retry is
\ admitted the same way, since a part of the frame may fit where all of it
\ did not.
: _RTHP-W-ADMIT  ( -- rte-status )
    _RTHP-W-PREFLIGHT-HYBRID
    DUP RTE-S-CAPACITY = IF
        _RTHP-W-P @ _RTHP-GROW-STORAGE? IF DROP _RTHP-W-PREFLIGHT-HYBRID THEN
    THEN ;

\ A candidate for Desk's shell holds no runs and is not admitted on its
\ own: the shell plans the runs of its regions and admits its whole batch,
\ this candidate's items among them (RTHPX-PREPARE).  Its layers are set as
\ the admission would check them.
: _RTHP-W-FOR-SHELL  ( -- rte-status )
    _RTPROF-PH-RESIDUAL-PLAN _RTPROF-MARK
    _RTHP-W-P @ _RTHP-SHELL-RESIDUE?
    _RTPROF-PH-OTHER _RTPROF-MARK
        0= IF _RTHP-W-GLYPH-REFUSAL EXIT THEN
    _RTHP-W-P @ _RTHP-BASE-LAYER! 0= IF RTE-S-UNAVAILABLE EXIT THEN
    _RTPROF-PH-RESERVE-WRAP _RTPROF-MARK
    _RTHP-W-P @ _RTHP-WRAP-HYBRID
    _RTPROF-PH-OTHER _RTPROF-MARK
    RTE-S-OK ;

\ An opaque combined refusal of a candidate containing collections triggers
\ this family-isolation retry.  Rebuild the exact same ordinary frame without
\ collection claims so every refused cell returns to residual GLYPH_RUN
\ coverage.  The rebuilt candidate reaches the same mandatory hybrid preflight
\ before any owner is opened.
: _RTHP-W-REBUILD-MENU-ONLY  ( -- rte-status )
    _RTHP-W-P @ _RTHP-FIELD-CLEAR _RTHP-W-P @ _RTHP-DIALOG-CLEAR
    _RTHP-W-STRIP-COLLECTIONS? 0= IF RTE-S-INVALID EXIT THEN
    _RTHP-W-P @ _RTHP-BUILD-CLAIMS? 0= IF RTE-S-INVALID EXIT THEN
    _RTHP-W-BUILD-OPTIONAL-FIELDS
        DUP RTE-S-OK <> IF EXIT THEN DROP
    _RTHP-W-BUILD-OPTIONAL-DIALOGS
        DUP RTE-S-OK <> IF EXIT THEN DROP
    _RTHP-W-BUILD-OPTIONAL-INSTRUMENTS
        DUP RTE-S-OK <> IF EXIT THEN DROP
    _RTHP-W-BUILD-OPTIONAL-STATICS
        DUP RTE-S-OK <> IF EXIT THEN DROP
    _RTHP-W-P @ _RTHP-BUILD-GLYPHS? 0= IF _RTHP-W-GLYPH-REFUSAL EXIT THEN
    _RTHP-W-P @ _RTHP-RESERVE-GLYPHS? 0= IF RTE-S-INVALID EXIT THEN
    _RTHP-W-P @ _RTHP-WRAP-HYBRID
    _RTHP-W-ADMIT ;

\ If the selected provider cannot admit the optional instrument family, drop
\ only that generic family, restore the already validated base claim prefix,
\ and return every affected CELL pixel to residual projection.  No tentative
\ instrument claim remains authoritative during this retry.
: _RTHP-W-REBUILD-WITHOUT-INSTRUMENTS  ( -- rte-status )
    _RTHP-W-RESTORE-BASE-CLAIMS? 0= IF RTE-S-INVALID EXIT THEN
    _RTHP-W-BUILD-OPTIONAL-STATICS
        DUP RTE-S-OK <> IF EXIT THEN DROP
    _RTHP-W-P @ _RTHP-BUILD-GLYPHS? 0= IF _RTHP-W-GLYPH-REFUSAL EXIT THEN
    _RTHP-W-P @ _RTHP-RESERVE-GLYPHS? 0= IF RTE-S-INVALID EXIT THEN
    _RTHP-W-P @ _RTHP-WRAP-HYBRID
    _RTHP-W-ADMIT ;

: _RTHP-W-REBUILD-WITHOUT-STATICS ( -- rte-status )
    _RTHP-W-P @ _RTHP-STRIP-STATICS? 0= IF RTE-S-INVALID EXIT THEN
    _RTHP-W-P @ _RTHP-BUILD-GLYPHS? 0= IF _RTHP-W-GLYPH-REFUSAL EXIT THEN
    _RTHP-W-P @ _RTHP-RESERVE-GLYPHS? 0= IF RTE-S-INVALID EXIT THEN
    _RTHP-W-P @ _RTHP-WRAP-HYBRID _RTHP-W-ADMIT ;

: _RTHP-RTE>SCB  ( rte-status -- scb-status )
    DUP RTE-S-OK = IF DROP SCB-S-OK EXIT THEN
    DUP RTE-S-WOULD-BLOCK = IF DROP SCB-S-WOULD-BLOCK EXIT THEN
    DUP RTE-S-SESSION-LOST = IF DROP SCB-S-SESSION-LOST EXIT THEN
    DROP SCB-S-INVALID ;

VARIABLE _RTHP-N-P
VARIABLE _RTHP-N-REGION
VARIABLE _RTHP-N-OBJECT
VARIABLE _RTHP-N-SERIES

: _RTHP-SELECT-NEXT-IDS?  ( producer -- flag )
    _RTHP-N-P !
    _RTHP-N-P @ _RTHP.NEXT-REGION @ DUP 0= IF DROP 0 EXIT THEN
        _RTHP-N-P @ _RTHP.REGION !
    _RTHP-N-P @ _RTHP.NEXT-OBJECT @ DUP 0= IF DROP 0 EXIT THEN
        _RTHP-N-P @ _RTHP.FIRST-OBJECT !
    _RTHP-N-P @ _RTHP.NEXT-SERIES @ DUP 0= IF DROP 0 EXIT THEN
        _RTHP-N-P @ _RTHP.FIRST-SERIES !
    -1 ;

\ Opaque provider refusal removes the complete FIELD suffix and rebuilds
\ all dependent IDs/claims from its exact pre-field prefix.  The dialog
\ lane after the fields is built again unless it was refused itself.
: _RTHP-W-REBUILD-WITHOUT-FIELDS ( -- rte-status )
    _RTHP-W-P @ _RTHP-STRIP-FIELDS? 0= IF RTE-S-INVALID EXIT THEN
    -1 _RTHP-W-P @ _RTHP.FIELD-REFUSED !
    _RTHP-W-BUILD-OPTIONAL-DIALOGS DUP RTE-S-OK <> IF EXIT THEN DROP
    _RTHP-W-BUILD-OPTIONAL-INSTRUMENTS DUP RTE-S-OK <> IF EXIT THEN DROP
    _RTHP-W-BUILD-OPTIONAL-STATICS DUP RTE-S-OK <> IF EXIT THEN DROP
    _RTHP-W-P @ _RTHP-BUILD-GLYPHS? 0= IF _RTHP-W-GLYPH-REFUSAL EXIT THEN
    _RTHP-W-P @ _RTHP-RESERVE-GLYPHS? 0= IF RTE-S-INVALID EXIT THEN
    _RTHP-W-P @ _RTHP-WRAP-HYBRID _RTHP-W-ADMIT ;

\ Opaque provider refusal removes the complete dialog suffix and rebuilds
\ every later family from its exact pre-dialog prefix.
: _RTHP-W-REBUILD-WITHOUT-DIALOGS ( -- rte-status )
    _RTHP-W-P @ _RTHP-STRIP-DIALOGS? 0= IF RTE-S-INVALID EXIT THEN
    -1 _RTHP-W-P @ _RTHP.DIALOG-REFUSED !
    _RTHP-W-BUILD-OPTIONAL-INSTRUMENTS DUP RTE-S-OK <> IF EXIT THEN DROP
    _RTHP-W-BUILD-OPTIONAL-STATICS DUP RTE-S-OK <> IF EXIT THEN DROP
    _RTHP-W-P @ _RTHP-BUILD-GLYPHS? 0= IF _RTHP-W-GLYPH-REFUSAL EXIT THEN
    _RTHP-W-P @ _RTHP-RESERVE-GLYPHS? 0= IF RTE-S-INVALID EXIT THEN
    _RTHP-W-P @ _RTHP-WRAP-HYBRID _RTHP-W-ADMIT ;

\ The last object the candidate numbers, or 0 when it numbers none.  A
\ candidate built for Desk's shell has no admission to say: it numbers its
\ controls, then its instruments, then its status fields, from its first
\ object, and no runs.
: _RTHP-CANDIDATE-LAST-OBJECT  ( producer -- object )
    DUP _RTHP.SHELL-BUILT @ IF
        DUP _RTHP.CONTROL-COUNT @ OVER _RTHP.INSTRUMENT-COUNT @ +
        OVER _RTHP.STATIC-COUNT @ + ?DUP 0= IF DROP 0 EXIT THEN
        SWAP _RTHP.FIRST-OBJECT @ + 1- EXIT
    THEN
    DUP _RTHP.ADMISSION _RTE-HA.GLYPH-COUNT @ IF
        _RTHP.ADMISSION _RTE-HA.GLYPH-LAST @
    ELSE
        DUP _RTHP.ADMISSION _RTE-HA.STATIC-COUNT @ IF
            _RTHP.ADMISSION _RTE-HA.STATIC-LAST @
        ELSE
        DUP _RTHP.ADMISSION _RTE-HA.INSTRUMENT-COUNT @ IF
            _RTHP.ADMISSION _RTE-HA.INSTRUMENT-LAST @
        ELSE
            _RTHP.ADMISSION _RTE-HA.CONTROL-LAST @
        THEN THEN
    THEN ;

: _RTHP-CANDIDATE-NEXT?  ( producer -- next-region next-object flag )
    _RTHP-N-P !
    _RTHP-N-P @ _RTHP.FIRST-SERIES @ DUP 0= IF DROP 0 0 0 EXIT THEN
    _RTHP-N-P @ _RTHP.NEXT-SERIES @ <> IF 0 0 0 EXIT THEN
    _RTHP-N-P @ _RTHP.FIRST-SERIES @ _RTHP-N-P @ _RTHP.SERIES-COUNT @
        _RTHP-U+? 0= IF DROP 0 0 0 EXIT THEN _RTHP-N-SERIES !
    _RTHP-N-P @ _RTHP.REGION @ DUP 0= IF DROP 0 0 0 EXIT THEN
    _RTHP-N-P @ _RTHP.NEXT-REGION @ <> IF 0 0 0 EXIT THEN
    _RTHP-N-P @ _RTHP.REGION @ 1 _RTHP-U+?
        0= IF DROP 0 0 0 EXIT THEN
    _RTHP-N-P @ _RTHP.INSTRUMENT-REGION-COUNT @ _RTHP-U+?
        0= IF DROP 0 0 0 EXIT THEN _RTHP-N-REGION !
    _RTHP-N-P @ _RTHP.FIRST-OBJECT @ DUP 0= IF DROP 0 0 0 EXIT THEN
    _RTHP-N-P @ _RTHP.NEXT-OBJECT @ <> IF 0 0 0 EXIT THEN
    _RTHP-N-P @ _RTHP-CANDIDATE-LAST-OBJECT DUP 0= IF
        DROP
        \ A candidate of no objects is a frame with series in it, or as
        \ part of the batch of Desk's shell, which has objects of its own.
        _RTHP-N-P @ _RTHP.SERIES-COUNT @ 0=
        _RTHP-N-P @ _RTHP.SHELL-BUILT @ 0= AND IF 0 0 0 EXIT THEN
        _RTHP-N-REGION @ _RTHP-N-P @ _RTHP.NEXT-OBJECT @ -1 EXIT
    THEN
    DUP _RTHP-N-P @ _RTHP.FIRST-OBJECT @ U< IF DROP 0 0 0 EXIT THEN
    1 _RTHP-U+? 0= IF DROP 0 0 0 EXIT THEN _RTHP-N-OBJECT !
    _RTHP-N-REGION @ _RTHP-N-OBJECT @ -1 ;

: _RTHP-ADVANCE-IDS?  ( producer -- flag )
    DUP _RTHP-N-P ! _RTHP-CANDIDATE-NEXT? 0= IF 2DROP 0 EXIT THEN
    _RTHP-N-P @ _RTHP.NEXT-OBJECT !
    _RTHP-N-P @ _RTHP.NEXT-REGION !
    _RTHP-N-SERIES @ _RTHP-N-P @ _RTHP.NEXT-SERIES !
    -1 ;

VARIABLE _RTHP-F-P
VARIABLE _RTHP-F-STATUS

\ A producer that faults shows no picture: every claim goes, and CELL
\ shows each picture.
: _RTHP-FAULT-RESULT  ( scb-status producer -- scb-status false false )
    UPICSN-RELEASE-ALL
    _RTHP-F-P ! _RTHP-F-STATUS !
    _RTHP-F-STATUS @ _RTHP-F-P @ _RTHP.FAULT !
    _RTHP-PH-FAULT _RTHP-F-P @ _RTHP.PHASE !
    _RTHP-F-STATUS @ 0 0 ;

\ Terminal space is asked for as needed.  An owner opens with what its
\ first frame needs, and a later frame that needs more asks the terminal to
\ grow the owner.  Each ask adds half again of what is needed, so a frame
\ that grows a little does not ask on every draw; it never asks for more
\ than the terminal offers at all.  When the terminal refuses that, the
\ exact need is asked for once more.
: _RTHP-Q@  ( index quotas -- u )  SWAP 8 * + @ ;
: _RTHP-Q!  ( u index quotas -- )  SWAP 8 * + ! ;

\ What the terminal offers at all for each quota, from the limits it
\ negotiated.  Frames need no resources; the pictures the terminal holds
\ do.
: _RTHP-Q-LIMIT  ( index producer -- u )
    _RTHP.LIMITS SWAP CASE
        0 OF RTE-LIMITS-REGIONS@ ENDOF
        1 OF RTE-LIMITS-RESOURCES@ ENDOF
        2 OF RTE-LIMITS-OBJECTS@ ENDOF
        3 OF RTE-LIMITS-SERIES@ ENDOF
        4 OF RTE-LIMITS-RESOURCE-BYTES@ ENDOF
        5 OF RTE-LIMITS-UTF8-BYTES@ ENDOF
        6 OF RTE-LIMITS-SAMPLE-SLOTS@ ENDOF
        7 OF RTE-LIMITS-TOTAL-PATH-POINTS@ ENDOF
        NIP 0 SWAP
    ENDCASE ;

\ The needs of the latest admission on this producer's facade.  NEED is
\ zero when that admission stopped before counting them.
: _RTHP-NEED@  ( producer -- flag )
    DUP _RTHP.NEED RTE-QUOTA-SIZE 0 FILL
    DUP _RTHP.NEED SWAP _RTHP.FACADE @ RTE-ADMISSION-NEEDS@
    RTE-S-OK = ;

\ The quotas the owner holds.  HELD is zero while no owner is open.
: _RTHP-HELD@  ( producer -- flag )
    DUP _RTHP.HELD RTE-QUOTA-SIZE 0 FILL
    DUP _RTHP.HELD OVER _RTHP.OWNER @ 2 PICK _RTHP.OWNER-GEN @
    3 PICK _RTHP.FACADE @ RTE-OWNER-QUOTAS@ NIP RTE-S-OK = ;

: _RTHP-NEED-BEYOND-LIMITS?  ( producer -- flag )
    8 0 DO
        I OVER _RTHP.NEED _RTHP-Q@ I 2 PICK _RTHP-Q-LIMIT U> IF
            DROP -1 UNLOOP EXIT
        THEN
    LOOP DROP 0 ;

: _RTHP-NEED-BEYOND-HELD?  ( producer -- flag )
    8 0 DO
        I OVER _RTHP.NEED _RTHP-Q@ I 2 PICK _RTHP.HELD _RTHP-Q@ U> IF
            DROP -1 UNLOOP EXIT
        THEN
    LOOP DROP 0 ;

: _RTHP-HELD-COVERS-ASK?  ( producer -- flag )
    8 0 DO
        I OVER _RTHP.HELD _RTHP-Q@ I 2 PICK _RTHP.ASK _RTHP-Q@ U< IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP DROP -1 ;

: _RTHP-ASK-IS-NEED?  ( producer -- flag )
    DUP _RTHP.ASK SWAP _RTHP.NEED RTE-QUOTA-SIZE TUCK COMPARE 0= ;

\ ASK for every quota the frame needs more of than is held: the need plus
\ half again, within what the terminal offers.  Others stay as held.
: _RTHP-ASK-GROWN  ( producer -- )
    8 0 DO
        I OVER _RTHP.NEED _RTHP-Q@ DUP
        I 3 PICK _RTHP.HELD _RTHP-Q@ U> IF
            DUP 1 RSHIFT + I 2 PICK _RTHP-Q-LIMIT _RTHP-UMIN
        ELSE
            DROP I OVER _RTHP.HELD _RTHP-Q@
        THEN
        I 2 PICK _RTHP.ASK _RTHP-Q!
    LOOP DROP ;

\ ASK for exactly what the frame needs, never less than is held.
: _RTHP-ASK-EXACT  ( producer -- )
    8 0 DO
        I OVER _RTHP.NEED _RTHP-Q@ I 2 PICK _RTHP.HELD _RTHP-Q@ _RTHP-UMAX
        I 2 PICK _RTHP.ASK _RTHP-Q!
    LOOP DROP ;

: _RTHP-OPEN  ( producer -- rte-status )
    >R R@ _RTHP.OWNER @ R@ _RTHP.OWNER-GEN @
    0 R@ _RTHP.ASK _RTHP-Q@ 1 R@ _RTHP.ASK _RTHP-Q@
    2 R@ _RTHP.ASK _RTHP-Q@ 3 R@ _RTHP.ASK _RTHP-Q@
    4 R@ _RTHP.ASK _RTHP-Q@ 5 R@ _RTHP.ASK _RTHP-Q@
    6 R@ _RTHP.ASK _RTHP-Q@ 7 R@ _RTHP.ASK _RTHP-Q@
    R> _RTHP.FACADE @ RTE-OWNER-OPEN ;

: _RTHP-RESIZE  ( producer -- rte-status )
    >R R@ _RTHP.OWNER @ R@ _RTHP.OWNER-GEN @
    0 R@ _RTHP.ASK _RTHP-Q@ 1 R@ _RTHP.ASK _RTHP-Q@
    2 R@ _RTHP.ASK _RTHP-Q@ 3 R@ _RTHP.ASK _RTHP-Q@
    4 R@ _RTHP.ASK _RTHP-Q@ 5 R@ _RTHP.ASK _RTHP-Q@
    6 R@ _RTHP.ASK _RTHP-Q@ 7 R@ _RTHP.ASK _RTHP-Q@
    R> _RTHP.FACADE @ RTE-OWNER-RESIZE ;

\ Before an owner opens: what the admitted first frame needs, with room to
\ grow, within what the terminal offers.
: _RTHP-PLAN-OPEN?  ( producer -- flag )
    DUP _RTHP-NEED@ 0= IF DROP 0 EXIT THEN
    DUP _RTHP.HELD RTE-QUOTA-SIZE 0 FILL
    _RTHP-ASK-GROWN -1 ;

\ ASK was exactly the need: nothing beyond it and nothing below what is held.
: _RTHP-ASK-WAS-EXACT?  ( producer -- flag )
    8 0 DO
        I OVER _RTHP.NEED _RTHP-Q@ I 2 PICK _RTHP.HELD _RTHP-Q@ _RTHP-UMAX
        I 2 PICK _RTHP.ASK _RTHP-Q@ <> IF DROP 0 UNLOOP EXIT THEN
    LOOP DROP -1 ;

\ The frame did not fit.  When the owner is open, the frame needs more than
\ it holds but no more than the terminal offers, and the terminal has not
\ already refused this draw, ask for more and wait for the answer.  The
\ phase that asked resumes once the terminal answers.
: _RTHP-ASK-FOR-SPACE?  ( producer -- flag )
    SCR-DRAW-GENERATION@ OVER _RTHP.SPACE-REFUSED-DRAW @ = IF DROP 0 EXIT THEN
    DUP _RTHP-HELD@ 0= IF DROP 0 EXIT THEN
    DUP _RTHP-NEED@ 0= IF DROP 0 EXIT THEN
    DUP _RTHP-NEED-BEYOND-LIMITS? IF DROP 0 EXIT THEN
    DUP _RTHP-NEED-BEYOND-HELD? 0= IF DROP 0 EXIT THEN
    DUP _RTHP-ASK-GROWN
    DUP _RTHP-RESIZE RTE-S-OK <> IF
        SCR-DRAW-GENERATION@ SWAP _RTHP.SPACE-REFUSED-DRAW ! 0 EXIT
    THEN
    DUP _RTHP.PHASE @ OVER _RTHP.RESUME-PHASE !
    _RTHP-PH-RESIZING SWAP _RTHP.PHASE ! -1 ;

\ Why the latest admission on this producer's facade refused its frame:
\ more than the terminal offers at all, or a kind it does not take; more
\ than the owner holds, once the terminal has refused more; or something
\ else.  Leaves NEED and HELD describing that frame.
: _RTHP-REFUSAL-WHY  ( producer -- reason )
    DUP _RTHP-HELD@ DROP
    DUP _RTHP-NEED@ 0= IF DROP RTHP-WHY-LIMIT EXIT THEN
    DUP _RTHP-NEED-BEYOND-LIMITS? IF DROP RTHP-WHY-LIMIT EXIT THEN
    _RTHP-NEED-BEYOND-HELD? IF RTHP-WHY-REFUSED ELSE RTHP-WHY-OTHER THEN ;

\ Record that PARTS of the current draw stayed CELL, and why, with the
\ quotas NEED and HELD describe.  A new draw starts a new entry; parts of
\ the same draw combine.  Nothing is drawn; the host, logs and tests read
\ the record through RTHP-FALLBACK@.
\ NOTE records no amounts; ENTRY adds the quotas NEED and HELD hold.
: _RTHP-FALLBACK-NOTE  ( parts reason producer -- )
    >R R@ _RTHP.FALLBACK-REASON !
    SCR-DRAW-GENERATION@ DUP R@ _RTHP.FALLBACK-DRAW @ <> IF
        R@ _RTHP.FALLBACK-DRAW !
        1 R@ _RTHP.FALLBACKS +!
        0 R@ _RTHP.FALLBACK-PARTS !
    ELSE DROP THEN
    R@ _RTHP.FALLBACK-PARTS @ OR R@ _RTHP.FALLBACK-PARTS !
    \ ASKED, HELD and the two byte cells are contiguous.
    R> _RTHP.FALLBACK-ASKED RTE-QUOTA-SIZE 2 * 16 + 0 FILL ;

: _RTHP-FALLBACK-ENTRY  ( parts reason producer -- )
    OVER >R DUP >R _RTHP-FALLBACK-NOTE
    R@ _RTHP.NEED R@ _RTHP.FALLBACK-ASKED RTE-QUOTA-SIZE MOVE
    R@ _RTHP.HELD R@ _RTHP.FALLBACK-HELD RTE-QUOTA-SIZE MOVE
    R> R> RTHP-WHY-MEMORY = IF
        _RTHP-W-MEMORY-ASKED @ OVER _RTHP.FALLBACK-BYTES-ASKED !
        _RTHP-W-MEMORY-HELD @ OVER _RTHP.FALLBACK-BYTES-HELD !
    THEN DROP ;

\ How many checks had named damage when the current draw's build began
\ (check-mode.f), so that a refusal can tell whether damage caused it.
VARIABLE _RTHP-W-DAMAGE-MARK
0 _RTHP-W-DAMAGE-MARK !
: _RTHP-W-DAMAGED?  ( -- flag )  CHK-DAMAGE-COUNT @ _RTHP-W-DAMAGE-MARK @ <> ;

\ Why a refused frame stays CELL: damage a check found while the draw was
\ built, then the terminal's answers, then Desk's memory when the provider
\ could not grow and nothing else explains it.
: _RTHP-REFUSAL-REASON  ( producer -- reason )
    _RTHP-W-DAMAGED? IF DROP RTHP-WHY-DAMAGE EXIT THEN
    _RTHP-REFUSAL-WHY
    DUP RTHP-WHY-OTHER = _RTHP-W-MEMORY-ASKED @ 0<> AND IF
        DROP RTHP-WHY-MEMORY
    THEN ;

: _RTHP-FALLBACK!  ( parts producer -- )
    DUP _RTHP-REFUSAL-REASON SWAP _RTHP-FALLBACK-ENTRY ;

\ An extension could not build its part.  When it ran out of its own
\ storage and nothing the terminal holds explains it, that is Desk's memory;
\ otherwise the latest admission says why.
: _RTHP-EXTENSION-FALLBACK!  ( parts extension-status producer -- )
    >R R@ _RTHP-REFUSAL-REASON
    SWAP RTE-S-CAPACITY = OVER RTHP-WHY-OTHER = AND IF
        DROP RTHP-WHY-MEMORY
    THEN
    R> _RTHP-FALLBACK-ENTRY ;

\ RTHP-FALLBACK@ ( producer -- count draw parts reason )
\   How many draws had a part stay CELL because it did not fit or was not
\   taken, and for the latest one its draw generation, the RTHP-PART- bits
\   that stayed CELL and the RTHP-WHY- reason.  RTHP-FALLBACK-QUOTAS gives
\   the quota sets it needed and held; RTHP-FALLBACK-BYTES@ the bytes, when
\   Desk's own memory refused.
: RTHP-FALLBACK@  ( producer -- count draw parts reason )
    >R R@ _RTHP.FALLBACKS @ R@ _RTHP.FALLBACK-DRAW @
    R@ _RTHP.FALLBACK-PARTS @ R> _RTHP.FALLBACK-REASON @ ;

: RTHP-FALLBACK-QUOTAS  ( producer -- needed held )
    DUP _RTHP.FALLBACK-ASKED SWAP _RTHP.FALLBACK-HELD ;

: RTHP-FALLBACK-BYTES@  ( producer -- needed held )
    DUP _RTHP.FALLBACK-BYTES-ASKED @ SWAP _RTHP.FALLBACK-BYTES-HELD @ ;

\ Build from one aggregate observation of DRAW.  The caller obtained
\ SNAPSHOT and STATUS from RUHA-SNAPSHOT-FOR@ for that completed draw in
\ the same synchronous call, with no application callback, yield, or
\ screen switch since, so the observation and its storage proofs are exact.
\ The parts of the frame present when it was first admitted, and why a
\ refusal happened, for the fallback record.
VARIABLE _RTHP-W-HAD
VARIABLE _RTHP-W-WHY

\ ---------------------------------------------------------------------
\  The pictures a draw shows
\ ---------------------------------------------------------------------
\
\  With a memory source and a terminal that takes pictures, each build
\  describes the pictures its draw shows into the arena's picture bank: a
\  picture whose file the terminal decodes as that file, and any other by
\  asking it for a copy of the pixels the terminal shows it at.  A bank too
\  small says how many it takes; the arena grows to them and the build
\  describes them again.

VARIABLE _RTHP-W-PICTURES-NEED
VARIABLE _RTHP-W-PICTURES-STATUS
VARIABLE _RTHP-W-PICTURES-ARENA

: _RTHP-LANE-ON?  ( producer -- flag )
    DUP _RTHP.MEMORY @ 0= IF DROP 0 EXIT THEN
    _RTHP.LIMITS RTE-LIMITS-FEATURES@ RTE-F-IMAGE AND 0<> ;

\ The picture files the terminal decodes, as PIC-F- formats, one by one.
: _RTHP-FILES>PICTURES  ( rte-formats -- pic-formats )
    0 SWAP
    DUP RTE-PICTURE-QOI 1- RSHIFT 1 AND IF
        SWAP 1 PIC-F-QOI 1- LSHIFT OR SWAP
    THEN
    DUP RTE-PICTURE-PNG 1- RSHIFT 1 AND IF
        SWAP 1 PIC-F-PNG 1- LSHIFT OR SWAP
    THEN
    DUP RTE-PICTURE-JPEG 1- RSHIFT 1 AND IF
        SWAP 1 PIC-F-JPEG 1- LSHIFT OR SWAP
    THEN
    DROP ;

\ The terminal's limits on one picture and the files it decodes, into the
\ ask, within the room the owner holds once the terminal has refused more.
\ The lane takes the pictures a build describes, so their CELL views decode
\ nothing, until it fails to send one; CELL then shows them all.
: _RTHP-PICTURE-LIMITS!  ( producer -- )
    DUP _RTHP.LIMITS RTE-LIMITS-IMAGE-FORMATS@ _RTHP-FILES>PICTURES
        OVER _RTHP.PICTURE-ASK UPICSN-ASK.FORMATS !
    DUP _RTHP.LANE-FAILED @ 0=
        OVER _RTHP.PICTURE-ASK UPICSN-ASK.CLAIM !
    DUP _RTHP.LIMITS RTE-LIMITS-IMAGE-WIDTH@
        OVER _RTHP.PICTURE-ASK UPICSN-ASK.MAX-W !
    DUP _RTHP.LIMITS RTE-LIMITS-IMAGE-HEIGHT@
        OVER _RTHP.PICTURE-ASK UPICSN-ASK.MAX-H !
    DUP _RTHP.LIMITS RTE-LIMITS-RESOURCE-BYTES@
    OVER _RTHP.LANE-BUDGET @ ?DUP IF
        OVER IF _RTHP-UMIN ELSE NIP THEN
    THEN
    SWAP _RTHP.PICTURE-ASK UPICSN-ASK.BUDGET ! ;

\ A terminal that takes no pictures, or a producer with no memory for
\ them, leaves every picture CELL, and a draw that shows any says why.
\ Counting them asks nothing of them: the ask is cleared, so the pixel
\ size is asked afresh if the lane comes on again, and every claim goes.
: _RTHP-W-PICTURES-OFF  ( -- )
    UPICSN-RELEASE-ALL
    _RTHP-W-P @ _RTHP.PICTURE-ASK UPICSN-ASK-SIZE 0 FILL
    0 0 _RTHP-W-P @ _RTHP.PICTURE-ASK _RTHP-W-DRAW @ _RTHP-W-P @ _RTHP.ADAPTER @
        RUHA-PICTURES@ RUHA-S-CAPACITY <> IF DROP EXIT THEN
    0= IF EXIT THEN
    RTHP-PART-PICTURES
    _RTHP-W-P @ _RTHP.MEMORY @ IF RTHP-WHY-LIMIT ELSE RTHP-WHY-MEMORY THEN
    _RTHP-W-P @ _RTHP-FALLBACK-NOTE ;

: _RTHP-W-PICTURES  ( -- )
    0 _RTHP-W-PICTURES-NEED ! 0 _RTHP-W-P @ _RTHP.PICTURE-COUNT !
    RUHA-S-OK _RTHP-W-PICTURES-STATUS !
    _RTHP-W-P @ _RTHP-LANE-ON? 0= IF _RTHP-W-PICTURES-OFF EXIT THEN
    _RTHP-W-P @ _RTHP-PICTURE-LIMITS!
    _RTHP-W-P @ _RTHP.PICTURES-A @ _RTHP-W-P @ _RTHP.PICTURES-U @
    _RTHP-W-P @ _RTHP.PICTURE-ASK _RTHP-W-DRAW @ _RTHP-W-P @ _RTHP.ADAPTER @
        RUHA-PICTURES@ DUP _RTHP-W-PICTURES-STATUS !
    DUP RUHA-S-OK = IF
        DROP DUP _RTHP-W-PICTURES-NEED ! _RTHP-W-P @ _RTHP.PICTURE-COUNT ! EXIT
    THEN
    RUHA-S-CAPACITY = IF _RTHP-W-PICTURES-NEED ! EXIT THEN
    \ Pictures that cannot be described stay CELL.
    DROP RTHP-PART-PICTURES RTHP-WHY-OTHER _RTHP-W-P @ _RTHP-FALLBACK-NOTE ;

\ Once the arena has grown, or for a bank that was too small, describe
\ the pictures again into the arena the candidate is built in.
: _RTHP-W-PICTURES-AGAIN  ( -- )
    _RTHP-W-P @ _RTHP.ARENA-A @ _RTHP-W-PICTURES-ARENA @ =
    _RTHP-W-PICTURES-STATUS @ RUHA-S-CAPACITY <> AND IF EXIT THEN
    _RTHP-W-PICTURES
    _RTHP-W-PICTURES-STATUS @ RUHA-S-CAPACITY = IF
        RTHP-PART-PICTURES RTHP-WHY-MEMORY _RTHP-W-P @ _RTHP-FALLBACK-NOTE
    THEN ;

\ ---------------------------------------------------------------------
\  An arena that follows the content
\ ---------------------------------------------------------------------
\
\  With a memory source attached, a draw whose snapshot or surface no
\  longer fits the arena gets a new one.  Content takes half again of
\  room, so a document that keeps growing does not regrow on every draw;
\  the surface is taken exactly.  Nothing shrinks.  The new arena is laid
\  out from scratch.  The frame on screen keeps its bank in the old arena,
\  which goes back once that frame is replaced or retired, and the frame
\  that replaces it is a complete START.

VARIABLE _RTHP-G-GROW
VARIABLE _RTHP-G-BYTES
VARIABLE _RTHP-G-ARENA
\ Diagnostics: arenas grown, and how many of them kept the frame on screen.
VARIABLE _RTHP-DIAG-ARENA-GROWTHS
VARIABLE _RTHP-DIAG-ARENA-KEPT

: _RTHP-G-CONTENT  ( need held -- capacity )
    2DUP U> IF DROP -1 _RTHP-G-GROW ! DUP 1 RSHIFT + EXIT THEN NIP ;
: _RTHP-G-NATIVE  ( need held -- capacity )  _RTHP-G-CONTENT 7 + -8 AND ;
: _RTHP-G-SURFACE  ( need held -- capacity )
    2DUP U> IF DROP -1 _RTHP-G-GROW ! EXIT THEN NIP ;

\ ( native-bytes count header-bytes -- need ) a native bank holds at least
\ one header for each of its descriptors.
: _RTHP-G-NATIVE-NEED  ( native-bytes count header-bytes -- need )
    * _RTHP-UMAX ;

\ The capacities this draw needs, into the _RTHP-I- cells.
: _RTHP-G-CAPACITIES  ( -- )
    0 _RTHP-G-GROW !
    _RTHP-W-P @ >R
    R@ _RTHP.MAX-DOCUMENTS @ _RTHP-I-DOCUMENTS !
    _RTHP-W-SNAP @ RUHA-SNAPSHOT-RECORDS@ NIP UMSN-RECORD-SIZE /
        _RTHP-W-SNAP @ RUHA-SNAPSHOT-DATA-GRAPHICS-COUNT@ _RTHP-UMAX
        R@ _RTHP.MAX-RECORDS @ _RTHP-G-CONTENT _RTHP-I-RECORDS !
    _RTHP-W-SNAP @ RUHA-SNAPSHOT-TEXT@ NIP
        R@ _RTHP.MAX-TEXT @ _RTHP-G-CONTENT _RTHP-I-TEXT !
    _RTHP-W-SNAP @ RUHA-SNAPSHOT-COLLECTION-NATIVE@ NIP
        _RTHP-W-SNAP @ RUHA-SNAPSHOT-COLLECTION-COUNT@
        USCOL-ENTRY-HEADER-SIZE _RTHP-G-NATIVE-NEED
        R@ _RTHP.MAX-COLLECTION-NATIVE @ _RTHP-G-NATIVE
        _RTHP-I-COLLECTION-NATIVE !
    _RTHP-W-SNAP @ RUHA-SNAPSHOT-DATA-GRAPHICS-NATIVE@ NIP
        _RTHP-W-SNAP @ RUHA-SNAPSHOT-DATA-GRAPHICS-COUNT@
        UDG-HEADER-SIZE _RTHP-G-NATIVE-NEED
        R@ _RTHP.MAX-DGRAPH-NATIVE @ _RTHP-G-NATIVE _RTHP-I-DGRAPH-NATIVE !
    _RTHP-W-SNAP @ RUHA-SNAPSHOT-STATUS-FIELDS-NATIVE@ NIP
        _RTHP-W-SNAP @ RUHA-SNAPSHOT-STATUS-FIELDS-COUNT@
        USF-HEADER-SIZE _RTHP-G-NATIVE-NEED
        R@ _RTHP.MAX-STATUS-NATIVE @ _RTHP-G-NATIVE _RTHP-I-STATUS-NATIVE !
    _RTHP-W-SNAP @ RUHA-SNAPSHOT-FIELDS-NATIVE@ NIP
        _RTHP-W-SNAP @ RUHA-SNAPSHOT-FIELDS-COUNT@
        UFLD-HEADER-SIZE _RTHP-G-NATIVE-NEED
        R@ _RTHP.MAX-FIELD-NATIVE @ _RTHP-G-NATIVE _RTHP-I-FIELD-NATIVE !
    _RTHP-W-SNAP @ RUHA-SNAPSHOT-DIALOGS-NATIVE@ NIP
        _RTHP-W-SNAP @ RUHA-SNAPSHOT-DIALOGS-COUNT@
        UDLG-HEADER-SIZE _RTHP-G-NATIVE-NEED
        R@ _RTHP.MAX-DIALOG-NATIVE @ _RTHP-G-NATIVE _RTHP-I-DIALOG-NATIVE !
    _RTHP-W-PICTURES-NEED @
        R@ _RTHP.MAX-PICTURES @ _RTHP-G-CONTENT _RTHP-I-PICTURES !
    R@ _RTHP.COLS @ R@ _RTHP.MAX-COLS @ _RTHP-G-SURFACE _RTHP-I-COLS !
    R@ _RTHP.ROWS @ R> _RTHP.MAX-ROWS @ _RTHP-G-SURFACE _RTHP-I-ROWS ! ;

\ The current arena either holds the bank of the frame on screen, and is
\ kept until that frame is replaced, or holds nothing anyone still reads.
: _RTHP-G-RETIRE-ARENA  ( producer -- )
    >R
    R@ _RTHP.TARGET-ACTIVE @ ?DUP IF
        R@ _RTHP.KEPT-BANK-A @ <> IF
            R@ _RTHP.ARENA-A @ R@ _RTHP.KEPT-ARENA-A !
            R@ _RTHP.ARENA-U @ R@ _RTHP.KEPT-ARENA-U !
            R@ _RTHP.TARGET-ACTIVE @ R@ _RTHP.KEPT-BANK-A !
            R@ _RTHP-TARGET-BANK-BYTES? DROP R@ _RTHP.KEPT-BANK-U !
            1 _RTHP-DIAG-ARENA-KEPT +!
            R> DROP EXIT
        THEN
    THEN
    R@ _RTHP.ARENA-A @ R@ _RTHP.ARENA-U @ R> _RTHP.MEMORY @ MSRC-FREE ;

\ ( a u producer -- flag ) a block from the memory source must be as
\ separate from everything the producer touches as a caller's arena.
: _RTHP-G-SEPARATE?  ( a u producer -- flag )
    >R
    2DUP MSPAN-NONWRAPPING? 0= IF R> DROP 2DROP 0 EXIT THEN
    2DUP R@ RTHP-SIZE MSPAN-OVERLAP? IF R> DROP 2DROP 0 EXIT THEN
    2DUP R@ _RTHP.ADAPTER @ RUHA-SIZE MSPAN-OVERLAP? IF
        R> DROP 2DROP 0 EXIT
    THEN
    R> _RTHP.FACADE @ RTE-STORAGE-DISJOINT? ;

: _RTHP-GROW-ARENA  ( -- rte-status )
    _RTHP-W-P @ _RTHP.MEMORY @ 0= IF RTE-S-OK EXIT THEN
    _RTHP-G-CAPACITIES
    _RTHP-G-GROW @ 0= IF RTE-S-OK EXIT THEN
    \ Every caller sets a pending bank aside before it builds.
    _RTHP-W-P @ _RTHP.TARGET-PENDING @ IF RTE-S-INVALID EXIT THEN
    _RTHP-I-DOCUMENTS @ _RTHP-I-RECORDS @ _RTHP-I-TEXT @
        _RTHP-I-COLLECTION-NATIVE @ _RTHP-I-DGRAPH-NATIVE @
        _RTHP-I-STATUS-NATIVE @ _RTHP-I-FIELD-NATIVE @ _RTHP-I-DIALOG-NATIVE @
        _RTHP-I-PICTURES @ _RTHP-I-COLS @ _RTHP-I-ROWS @ RTHP-STORAGE-BYTES
    \ Sizes no arena can hold are left to the snapshot copy to refuse.
    DUP 0= IF DROP RTE-S-OK EXIT THEN
    DUP _RTHP-G-BYTES !
    _RTHP-W-P @ _RTHP.MEMORY @ MSRC-ALLOC DUP 0= IF
        DROP
        _RTHP-W-MEMORY-ASKED @ 0= IF
            _RTHP-G-BYTES @ _RTHP-W-MEMORY-ASKED !
            _RTHP-W-P @ _RTHP.MEMORY @ MSRC-HELD@ _RTHP-W-MEMORY-HELD !
        THEN
        RTHP-WHY-MEMORY _RTHP-W-WHY ! RTE-S-CAPACITY EXIT
    THEN _RTHP-G-ARENA !
    _RTHP-G-ARENA @ _RTHP-G-BYTES @ _RTHP-W-P @ _RTHP-G-SEPARATE?
        S" Desk's memory source" CHK-HANDOVER 0= IF
        _RTHP-G-ARENA @ _RTHP-G-BYTES @ _RTHP-W-P @ _RTHP.MEMORY @ MSRC-FREE
        RTE-S-INVALID EXIT
    THEN
    _RTHP-G-ARENA @ _RTHP-G-BYTES @ 0 FILL
    _RTHP-W-P @ _RTHP-KEPT-ARENA-RELEASE
    _RTHP-W-P @ _RTHP-G-RETIRE-ARENA
    _RTHP-G-ARENA @ _RTHP-W-P @ _RTHP.ARENA-A !
    _RTHP-G-BYTES @ _RTHP-W-P @ _RTHP.ARENA-U !
    _RTHP-W-P @ _RTHP-I-CAPACITIES!
    _RTHP-W-P @ _RTHP-LAYOUT
    1 _RTHP-DIAG-ARENA-GROWTHS +!
    \ No candidate built in the old arena may pass as current.  The kept
    \ bank's facts stay with it: only a DELTA reads them, and no DELTA
    \ starts from a kept bank.
    0 _RTHP-W-P @ _RTHP.SOURCE-DRAW !
    0 _RTHP-W-P @ _RTHP.GLYPH-DRAW !
    RTE-S-OK ;

\ The optional parts a candidate carries now.
: _RTHP-PRESENT-PARTS  ( producer -- parts )
    0 OVER _RTHP.STATIC-COUNT @ IF RTHP-PART-STATICS OR THEN
    OVER _RTHP.FIELD-COUNT @ IF RTHP-PART-FIELDS OR THEN
    OVER _RTHP.DIALOG-CONTROLS @ IF RTHP-PART-DIALOGS OR THEN
    OVER _RTHP.INSTRUMENT-COUNT @ 2 PICK _RTHP.SERIES-COUNT @ OR IF
        RTHP-PART-INSTRUMENTS OR
    THEN
    SWAP _RTHP.COLLECTION-COUNT @ IF RTHP-PART-COLLECTIONS OR THEN ;

\ ---------------------------------------------------------------------
\  Root facts, for the shadow check's judge
\ ---------------------------------------------------------------------
\
\  With the shadow check on, each candidate's roots carry the facts of
\  what their captures read (RUHA-ROOT-FACTS@, uidl-root-facts.f).  Two
\  blocks from the heap hold them, each tagged with the generation of the
\  snapshot its records describe, so that the bank on screen keeps the
\  facts it was built from while the next candidate's are recorded in the
\  other.  The comparison judges them (_RTHP-ROOT-BEGIN).

\ Block 1 and block 2: each an address and size from the heap, a count of
\ records, and the snapshot generation they describe.  0 names no block.
VARIABLE _RTHP-ROOT-A1
VARIABLE _RTHP-ROOT-U1
VARIABLE _RTHP-ROOT-N1
VARIABLE _RTHP-ROOT-GEN1
VARIABLE _RTHP-ROOT-A2
VARIABLE _RTHP-ROOT-U2
VARIABLE _RTHP-ROOT-N2
VARIABLE _RTHP-ROOT-GEN2
VARIABLE _RTHP-ROOT-PARTS1
VARIABLE _RTHP-ROOT-PARTS2
0 _RTHP-ROOT-A1 ! 0 _RTHP-ROOT-U1 ! 0 _RTHP-ROOT-N1 ! 0 _RTHP-ROOT-GEN1 !
0 _RTHP-ROOT-A2 ! 0 _RTHP-ROOT-U2 ! 0 _RTHP-ROOT-N2 ! 0 _RTHP-ROOT-GEN2 !
0 _RTHP-ROOT-PARTS1 ! 0 _RTHP-ROOT-PARTS2 !
: _RTHP-ROOT.A    ( block -- a )  1 = IF _RTHP-ROOT-A1 ELSE _RTHP-ROOT-A2 THEN ;
: _RTHP-ROOT.U    ( block -- a )  1 = IF _RTHP-ROOT-U1 ELSE _RTHP-ROOT-U2 THEN ;
: _RTHP-ROOT.N    ( block -- a )  1 = IF _RTHP-ROOT-N1 ELSE _RTHP-ROOT-N2 THEN ;
: _RTHP-ROOT.GEN  ( block -- a )
    1 = IF _RTHP-ROOT-GEN1 ELSE _RTHP-ROOT-GEN2 THEN ;
\ The optional parts the block's candidate carried once built
\ (_RTHP-PRESENT-PARTS).
: _RTHP-ROOT.PARTS  ( block -- a )
    1 = IF _RTHP-ROOT-PARTS1 ELSE _RTHP-ROOT-PARTS2 THEN ;

VARIABLE _RTHP-ROOT-P
VARIABLE _RTHP-ROOT-B

\ The block for the next candidate's facts: one that does not hold those
\ of the bank on screen.
: _RTHP-ROOT-PENDING-BLOCK  ( producer -- block )
    _RTHP.TARGET-ACTIVE @ ?DUP IF _RTHP-TB.SOURCE-GEN @ ELSE 0 THEN
    1 _RTHP-ROOT.GEN @ = IF 2 ELSE 1 THEN ;

: _RTHP-ROOT-CAPTURE  ( -- count status )
    _RTHP-ROOT-B @ _RTHP-ROOT.A @ _RTHP-ROOT-B @ _RTHP-ROOT.U @
    _RTHP-W-DRAW @ _RTHP-ROOT-P @ _RTHP.ADAPTER @ RUHA-ROOT-FACTS@ ;

\ Record the facts of the snapshot this candidate copied, tagged with its
\ generation.  A block too small grows once to what the snapshot needs; a
\ heap that cannot give it leaves the candidate without facts, which the
\ comparison then does not judge, and counts a skipped comparison.
: _RTHP-ROOT-RECORD  ( producer -- )
    FSHD? 0= IF DROP EXIT THEN
    DUP _RTHP-ROOT-P ! _RTHP-ROOT-PENDING-BLOCK _RTHP-ROOT-B !
    0 _RTHP-ROOT-B @ _RTHP-ROOT.GEN ! 0 _RTHP-ROOT-B @ _RTHP-ROOT.N !
    _RTHP-ROOT-CAPTURE
    DUP RUHA-S-CAPACITY = IF
        DROP URF-SIZE * _RTHP-ROOT-B @ _RTHP-ROOT.A _RTHP-ROOT-B @ _RTHP-ROOT.U
            FSHD-GROW 0= IF FSHD-SKIP EXIT THEN
        _RTHP-ROOT-CAPTURE
    THEN
    RUHA-S-OK <> IF DROP EXIT THEN
    _RTHP-ROOT-B @ _RTHP-ROOT.N !
    0 _RTHP-ROOT-B @ _RTHP-ROOT.PARTS !
    _RTHP-ROOT-P @ _RTHP.SOURCE-GEN @ _RTHP-ROOT-B @ _RTHP-ROOT.GEN ! ;

\ The candidate whose facts were recorded is built: keep the parts it carries.
: _RTHP-ROOT-PARTS!  ( producer -- )
    FSHD? 0= IF DROP EXIT THEN
    _RTHP-PRESENT-PARTS _RTHP-ROOT-B @ _RTHP-ROOT.PARTS ! ;

: _RTHP-BUILD-OBSERVED-CANDIDATE
  ( snapshot status draw producer -- rte-status built? )
    _RTHP-W-P ! _RTHP-W-DRAW ! _RTHP-W-STATUS ! _RTHP-W-SNAP !
    RTHP-WHY-OTHER _RTHP-W-WHY !
    0 _RTHP-W-MEMORY-ASKED ! 0 _RTHP-W-MEMORY-HELD !
    _RTHP-W-P @ _RTHP.NEED RTE-QUOTA-SIZE 0 FILL
    _RTHP-W-P @ _RTHP.HELD RTE-QUOTA-SIZE 0 FILL
    \ A lifecycle edge still settling is waited for.  A snapshot with no
    \ document to publish is a draw that cannot be shown rich.
    _RTHP-W-STATUS @ RUHA-S-STALE = IF RTE-S-WOULD-BLOCK 0 EXIT THEN
    _RTHP-W-STATUS @ RUHA-S-UNAVAILABLE = IF RTE-S-UNAVAILABLE 0 EXIT THEN
    _RTHP-W-STATUS @ RUHA-S-CAPACITY = IF
        RTHP-WHY-MEMORY _RTHP-W-WHY ! RTE-S-CAPACITY 0 EXIT
    THEN
    _RTHP-W-STATUS @ RUHA-S-OK <> IF RTE-S-INVALID 0 EXIT THEN
    _RTPROF-PH-SNAPSHOT-IMPORT _RTPROF-MARK
    _RTHP-W-P @ _RTHP.LIMITS _RTHP-W-P @ _RTHP.FACADE @ RTE-LIMITS@
    _RTPROF-PH-OTHER _RTPROF-MARK
        DUP _RTHP-W-STATUS !
    DUP RTE-S-UNAVAILABLE = OVER RTE-S-WOULD-BLOCK = OR IF
        DROP RTE-S-WOULD-BLOCK 0 EXIT
    THEN
    DUP RTE-S-OK <> IF 0 EXIT THEN DROP
    \ A snapshot, surface or picture count the arena no longer fits grows
    \ it first.
    _RTHP-W-PICTURES
    _RTHP-W-P @ _RTHP.ARENA-A @ _RTHP-W-PICTURES-ARENA !
    _RTHP-GROW-ARENA DUP RTE-S-OK <> IF 0 EXIT THEN DROP
    _RTHP-W-PICTURES-AGAIN
    _RTPROF-PH-SNAPSHOT-IMPORT _RTPROF-MARK
    _RTHP-W-SNAP @ _RTHP-W-P @ _RTHP-COPY-SNAPSHOT?
    _RTPROF-PH-OTHER _RTPROF-MARK
        0= IF RTE-S-INVALID 0 EXIT THEN
    _RTHP-W-P @ _RTHP-ROOT-RECORD
    _RTPROF-PH-SNAPSHOT-IMPORT _RTPROF-MARK
    _RTHP-W-P @ _RTHP-SELECT-NEXT-IDS?
    _RTPROF-PH-OTHER _RTPROF-MARK
        0= IF RTE-S-INVALID 0 EXIT THEN
    _RTPROF-PH-CONTROL-PLAN _RTPROF-MARK
    _RTHP-W-P @ _RTHP-BUILD-CONTROLS
    _RTPROF-PH-OTHER _RTPROF-MARK
    DUP _RTHP-W-STATUS !
    DUP RTE-S-OK <> IF 0 EXIT THEN DROP
    _RTPROF-PH-CLAIM-PLAN _RTPROF-MARK
    _RTHP-W-P @ _RTHP-BUILD-CLAIMS?
    _RTPROF-PH-OTHER _RTPROF-MARK
        0= IF RTE-S-INVALID 0 EXIT THEN
    _RTHP-W-BUILD-OPTIONAL-FIELDS
    DUP RTE-S-OK <> IF 0 EXIT THEN DROP
    _RTHP-W-BUILD-OPTIONAL-DIALOGS
    DUP RTE-S-OK <> IF 0 EXIT THEN DROP
    _RTHP-W-BUILD-OPTIONAL-INSTRUMENTS
    DUP RTE-S-OK <> IF 0 EXIT THEN DROP
    _RTHP-W-BUILD-OPTIONAL-STATICS
    DUP RTE-S-OK <> IF 0 EXIT THEN DROP
    _RTHP-W-P @ _RTHP-PRESENT-PARTS _RTHP-W-HAD !
    \ A request to build alone holds for one build.
    _RTHP-W-SHELL-MODE? 0 _RTHP-W-ALONE !
    DUP _RTHP-W-P @ _RTHP.SHELL-BUILT ! IF
        _RTHP-W-FOR-SHELL
    ELSE
        _RTPROF-PH-RESIDUAL-PLAN _RTPROF-MARK
        _RTHP-W-P @ _RTHP-BUILD-GLYPHS?
        _RTPROF-PH-OTHER _RTPROF-MARK
            0= IF _RTHP-W-GLYPH-REFUSAL 0 EXIT THEN
        _RTPROF-PH-RESERVE-WRAP _RTPROF-MARK
        _RTHP-W-P @ _RTHP-RESERVE-GLYPHS?
        _RTPROF-PH-OTHER _RTPROF-MARK
            0= IF RTE-S-INVALID 0 EXIT THEN
        _RTPROF-PH-RESERVE-WRAP _RTPROF-MARK
        _RTHP-W-P @ _RTHP-WRAP-HYBRID
        _RTPROF-PH-OTHER _RTPROF-MARK
        _RTHP-W-ADMIT
        \ A frame that still does not fit asks the terminal for more space.
        DUP RTE-S-CAPACITY = IF
            _RTHP-W-P @ _RTHP-ASK-FOR-SPACE? IF DROP RTE-S-WOULD-BLOCK 0 EXIT THEN
        THEN
        DUP RTE-S-OK <> IF _RTHP-W-P @ _RTHP-REFUSAL-REASON _RTHP-W-WHY ! THEN
        \ An opaque refusal cannot identify its optional family.  Strip status
        \ before each older-family retry.  Rebuilding menu/instrument choices may
        \ admit status again, so the final attempt also gets a status-free retry.
        \ No refused family leaves claims in the residual projection.
        DUP RTE-S-CAPACITY = OVER RTE-S-UNAVAILABLE = OR
        _RTHP-W-P @ _RTHP.STATIC-COUNT @ 0<> AND IF
            DROP _RTHP-W-REBUILD-WITHOUT-STATICS
        THEN
        DUP RTE-S-CAPACITY = OVER RTE-S-UNAVAILABLE = OR
        _RTHP-W-P @ _RTHP.DIALOG-CONTROLS @ 0<> AND IF
            DROP _RTHP-W-REBUILD-WITHOUT-DIALOGS
        THEN
        DUP RTE-S-CAPACITY = OVER RTE-S-UNAVAILABLE = OR
        _RTHP-W-P @ _RTHP.STATIC-COUNT @ 0<> AND IF
            DROP _RTHP-W-REBUILD-WITHOUT-STATICS
        THEN
        DUP RTE-S-CAPACITY = OVER RTE-S-UNAVAILABLE = OR
        _RTHP-W-P @ _RTHP.FIELD-COUNT @ 0<> AND IF
            DROP _RTHP-W-REBUILD-WITHOUT-FIELDS
        THEN
        DUP RTE-S-CAPACITY = OVER RTE-S-UNAVAILABLE = OR
        _RTHP-W-P @ _RTHP.STATIC-COUNT @ 0<> AND IF
            DROP _RTHP-W-REBUILD-WITHOUT-STATICS
        THEN
        DUP RTE-S-CAPACITY = OVER RTE-S-UNAVAILABLE = OR
        _RTHP-W-P @ _RTHP.INSTRUMENT-COUNT @
        _RTHP-W-P @ _RTHP.SERIES-COUNT @ OR 0<> AND IF
            DROP _RTHP-W-REBUILD-WITHOUT-INSTRUMENTS
        THEN
        DUP RTE-S-CAPACITY = OVER RTE-S-UNAVAILABLE = OR
        _RTHP-W-P @ _RTHP.STATIC-COUNT @ 0<> AND IF
            DROP _RTHP-W-REBUILD-WITHOUT-STATICS
        THEN
        DUP RTE-S-CAPACITY = OVER RTE-S-UNAVAILABLE = OR
        _RTHP-W-P @ _RTHP.COLLECTION-COUNT @ 0<> AND IF
            DROP _RTHP-W-REBUILD-MENU-ONLY
        THEN
        DUP RTE-S-CAPACITY = OVER RTE-S-UNAVAILABLE = OR
        _RTHP-W-P @ _RTHP.STATIC-COUNT @ 0<> AND IF
            DROP _RTHP-W-REBUILD-WITHOUT-STATICS
        THEN
        DUP RTE-S-CAPACITY = OVER RTE-S-UNAVAILABLE = OR
        _RTHP-W-P @ _RTHP.INSTRUMENT-COUNT @
        _RTHP-W-P @ _RTHP.SERIES-COUNT @ OR 0<> AND IF
            DROP _RTHP-W-REBUILD-WITHOUT-INSTRUMENTS
        THEN
        DUP RTE-S-CAPACITY = OVER RTE-S-UNAVAILABLE = OR
        _RTHP-W-P @ _RTHP.STATIC-COUNT @ 0<> AND IF
            DROP _RTHP-W-REBUILD-WITHOUT-STATICS
        THEN
    THEN
    DUP RTE-S-OK <> IF 0 EXIT THEN DROP
    \ Graphs the terminal's series limits cannot take stay CELL, as do the
    \ families stripped above.
    _RTHP-W-P @ _RTHP.OMITTED-GRAPHS-USED @ IF
        RTHP-PART-GRAPHS RTHP-WHY-LIMIT _RTHP-W-P @ _RTHP-FALLBACK-NOTE
    THEN
    _RTHP-W-HAD @ _RTHP-W-P @ _RTHP-PRESENT-PARTS INVERT AND ?DUP IF
        _RTHP-W-WHY @ _RTHP-W-P @ _RTHP-FALLBACK-ENTRY
    THEN
    _RTHP-W-P @ _RTHP-CANDIDATE-NEXT? 0= IF
        2DROP RTE-S-INVALID 0 EXIT
    THEN 2DROP
    _RTHP-W-DRAW @ _RTHP-W-P @ _RTHP-DRAW-CURRENT? 0= IF
        RTE-S-WOULD-BLOCK 0 EXIT
    THEN
    _RTHP-W-P @ _RTHP.SOURCE-DRAW @ _RTHP-W-P @ _RTHP.SURFACE-GEN !
    _RTHP-W-P @ _RTHP-ROOT-PARTS!
    RTE-S-OK -1 ;

\ In safe mode (check-mode.f) a draw whose build a check refused for damage
\ cannot be shown rich: CELL shows it, the fallback record gives damage as
\ the reason, and CHK-DAMAGE names what was damaged.  Rich is tried again
\ once a newer draw completes, with every check run again.  Otherwise a
\ refusal for damage stays INVALID, as any broken record is.
: _RTHP-DAMAGE-REFUSAL  ( rte-status built? -- rte-status built? )
    DUP IF EXIT THEN
    OVER RTE-S-INVALID = CHK-SAFE? AND _RTHP-W-DAMAGED? AND IF
        2DROP RTHP-WHY-DAMAGE _RTHP-W-WHY ! RTE-S-UNAVAILABLE 0
    THEN ;

\ The layers the terminal can show above a document's roots: a prompt's
\ field with fields, a dialog with dialogs, and an overlay pane with dialogs
\ when an extension, Desk's shell, gives the pane a region of its own above
\ the panes beneath it (RUHA-LAYERS!).  An overlay pane's document is a
\ dialog, as each of Desk's screens is.
: _RTHP-RUHA-LAYERS  ( producer -- flags )
    DUP _RTHP.LIMITS RTE-LIMITS-FEATURES@
    DUP RTE-F-FIELDS AND IF RUHA-LAYER-FIELDS ELSE 0 THEN
    SWAP RTE-F-DIALOGS AND IF
        RUHA-LAYER-DIALOGS OR
        SWAP _RTHP.EXTENSION @ IF RUHA-LAYER-PANES OR THEN
    ELSE NIP THEN ;

: _RTHP-BUILD-CANDIDATE  ( producer -- rte-status built? )
    _RTPROF-PH-OTHER _RTPROF-MARK
    _RTHP-W-P !
    CHK-DAMAGE-COUNT @ _RTHP-W-DAMAGE-MARK !
    SCR-DRAW-GENERATION@ DUP 0= IF
        DROP RTE-S-WOULD-BLOCK 0 EXIT
    THEN _RTHP-W-DRAW !
    _RTHP-W-P @ _RTHP-RUHA-LAYERS _RTHP-W-P @ _RTHP.ADAPTER @ RUHA-LAYERS!
        RUHA-S-OK <> IF RTE-S-INVALID 0 EXIT THEN
    _RTPROF-PH-UIDL-AGGREGATE _RTPROF-MARK
    _RTHP-W-DRAW @ _RTHP-W-P @ _RTHP.ADAPTER @ RUHA-SNAPSHOT-FOR@
    _RTPROF-PH-OTHER _RTPROF-MARK
    _RTHP-W-DRAW @ _RTHP-W-P @ _RTHP-BUILD-OBSERVED-CANDIDATE
    _RTHP-DAMAGE-REFUSAL ;

\ Build the candidate with its own runs and admission, even with Desk's
\ shell installed (_RTHP-W-ALONE).  The build takes the request at its
\ mode decision, and one that stopped before it leaves none behind.
: _RTHP-BUILD-ALONE  ( producer -- rte-status built? )
    -1 _RTHP-W-ALONE ! _RTHP-BUILD-CANDIDATE 0 _RTHP-W-ALONE ! ;

\ _RTHP-REFUSE-DRAW ( producer -- )
\   The completed draw just built cannot be shown rich.  CELL shows it, the
\   fallback record says so, and rich is tried again once a newer draw
\   completes.
: _RTHP-REFUSE-DRAW  ( producer -- )
    RTHP-PART-FRAME _RTHP-W-WHY @ 2 PICK _RTHP-FALLBACK-ENTRY
    _RTHP-W-DRAW @ SWAP _RTHP.REFUSED-DRAW ! ;

\ Before an owner opens, a draw that cannot be shown rich leaves CELL output
\ as it is and keeps waiting for a newer draw.  The owner is sized from the
\ candidate's own admission, so the candidate is built alone.
: _RTHP-TRY-CANDIDATE  ( producer -- scb-status started? )
    _RTHP-W-P !
    _RTHP-W-P @ _RTHP-BUILD-ALONE IF
        DUP RTE-S-OK <> IF DROP SCB-S-INVALID 0 EXIT THEN DROP
    ELSE
        DUP RTE-S-UNAVAILABLE = OVER RTE-S-CAPACITY = OR IF
            DROP _RTHP-W-P @ _RTHP-REFUSE-DRAW
            SCB-S-OK 0 EXIT
        THEN
        DUP RTE-S-WOULD-BLOCK = IF DROP SCB-S-OK 0 EXIT THEN
        _RTHP-RTE>SCB 0 EXIT
    THEN
    _RTHP-W-P @ _RTHP-PLAN-OPEN? 0= IF SCB-S-INVALID 0 EXIT THEN
    _RTHP-PH-OPENING _RTHP-W-P @ _RTHP.PHASE !
    _RTHP-W-P @ _RTHP-OPEN DUP _RTHP-W-STATUS !
    DUP RTE-S-OK = _RTHP-W-P @ _RTHP.OPEN-QUEUED !
    DUP RTE-S-OK = OVER RTE-S-WOULD-BLOCK = OR IF
        DROP SCB-S-OK -1 EXIT
    THEN
    RTE-S-SESSION-LOST = IF SCB-S-SESSION-LOST -1 EXIT THEN
    SCB-S-INVALID -1 ;

: _RTHP-REBUILD-RESULT  ( rte-status built? -- scb-status built? )
    IF
        DUP RTE-S-OK = IF DROP SCB-S-OK -1 EXIT THEN
        DROP SCB-S-INVALID 0 EXIT
    THEN
    DUP RTE-S-WOULD-BLOCK = IF DROP SCB-S-WOULD-BLOCK 0 EXIT THEN
    \ Family and glyph-reserve normalization has already converged, so this
    \ completed draw cannot be shown rich.  An empty frame replaces the rich
    \ one and its reveal carries CELL; until the empty frame is sealed the
    \ CELL offer waits, so no newer CELL frame shows under the older rich one.
    DUP RTE-S-CAPACITY = OVER RTE-S-UNAVAILABLE = OR IF
        \ An empty frame shows no picture: CELL shows each one.
        DROP _RTHP-W-P @ _RTHP-REFUSE-DRAW UPICSN-RELEASE-ALL
        _RTHP-PH-READY-BLANK _RTHP-W-P @ _RTHP.PHASE !
        SCB-S-WOULD-BLOCK 0 EXIT
    THEN
    _RTHP-RTE>SCB 0 ;

: _RTHP-REBUILD-CANDIDATE  ( producer -- scb-status built? )
    _RTHP-BUILD-CANDIDATE _RTHP-REBUILD-RESULT ;

\ =====================================================================
\  STEP lifecycle
\ =====================================================================

VARIABLE _RTHP-S-P
VARIABLE _RTHP-S-COLS
VARIABLE _RTHP-S-ROWS
VARIABLE _RTHP-S-GEN
VARIABLE _RTHP-S-STATE
VARIABLE _RTHP-S-STATUS

: _RTHP-CALL-SURFACE?  ( cols rows generation producer -- flag )
    _RTHP-S-P ! _RTHP-S-GEN ! _RTHP-S-ROWS ! _RTHP-S-COLS !
    _RTHP-S-COLS @ 0> _RTHP-S-ROWS @ 0> AND
    _RTHP-S-GEN @ 0<> AND 0= IF 0 EXIT THEN
    \ A fixed arena bounds the surface; one that grows takes it as it is.
    _RTHP-S-P @ _RTHP.MEMORY @ 0= IF
        _RTHP-S-COLS @ _RTHP-S-P @ _RTHP.MAX-COLS @ U>
        _RTHP-S-ROWS @ _RTHP-S-P @ _RTHP.MAX-ROWS @ U> OR IF 0 EXIT THEN
    THEN
    SCR-W _RTHP-S-COLS @ = SCR-H _RTHP-S-ROWS @ = AND
    _RTHP-S-P @ _RTHP.PHASE @ _RTHP-PH-WAIT <> IF
        _RTHP-S-COLS @ _RTHP-S-P @ _RTHP.COLS @ = AND
        _RTHP-S-ROWS @ _RTHP-S-P @ _RTHP.ROWS @ = AND
        _RTHP-S-GEN @ _RTHP-S-P @ _RTHP.PHYSICAL-GEN @ = AND
    THEN ;

\ The terminal refused the owner this producer queued, even at exactly the
\ first frame's need.  CELL keeps showing the draw, the fallback record says
\ so, and the owner is asked for again only once a newer draw completes,
\ not on every service turn.
: _RTHP-OPEN-REFUSED  ( producer -- scb-status more? output-needed? )
    0 OVER _RTHP.OPEN-QUEUED !
    DUP _RTHP.SOURCE-DRAW @ OVER _RTHP.REFUSED-DRAW !
    RTHP-PART-FRAME RTHP-WHY-REFUSED 2 PICK _RTHP-FALLBACK-ENTRY
    _RTHP-PH-WAIT SWAP _RTHP.PHASE !
    SCB-S-OK 0 0 ;

\ A FREE owner after a queued open means the terminal refused it: an open
\ that asked for room to grow asks once more for exactly the need.  An open
\ that could not be queued is simply tried again.
: _RTHP-STEP-OPENING  ( producer -- scb-status more? output-needed? )
    DUP _RTHP.OWNER @ OVER _RTHP.OWNER-GEN @
    2 PICK _RTHP.FACADE @ RTE-OWNER-STATE@
    _RTHP-S-STATUS ! _RTHP-S-STATE !
    _RTHP-S-STATUS @ RTE-S-SESSION-LOST = IF
        SCB-S-SESSION-LOST SWAP _RTHP-FAULT-RESULT EXIT
    THEN
    _RTHP-S-STATE @ RTE-OWNER-ST-OPEN =
    _RTHP-S-STATUS @ RTE-S-OK = AND IF
        0 OVER _RTHP.OPEN-QUEUED !
        _RTHP-PH-READY-START OVER _RTHP.PHASE !
        DROP SCB-S-OK 0 -1 EXIT
    THEN
    _RTHP-S-STATE @ RTE-OWNER-ST-OPENING = IF
        DROP SCB-S-OK -1 0 EXIT
    THEN
    _RTHP-S-STATE @ RTE-OWNER-ST-FREE =
    _RTHP-S-STATUS @ RTE-S-OK = AND IF
        DUP _RTHP.OPEN-QUEUED @ IF
            DUP _RTHP-ASK-WAS-EXACT? IF _RTHP-OPEN-REFUSED EXIT THEN
            DUP _RTHP-ASK-EXACT
        THEN
        DUP _RTHP-OPEN DUP _RTHP-S-STATUS !
        DUP RTE-S-OK = 2 PICK _RTHP.OPEN-QUEUED !
        DUP RTE-S-OK = OVER RTE-S-WOULD-BLOCK = OR IF
            2DROP SCB-S-OK -1 0 EXIT
        THEN
        RTE-S-SESSION-LOST = IF
            SCB-S-SESSION-LOST SWAP _RTHP-FAULT-RESULT EXIT
        THEN
    THEN
    SCB-S-INVALID SWAP _RTHP-FAULT-RESULT ;

\ The terminal answers a request for more space.  Yes resumes the phase
\ that asked, whose next PREPARE builds the frame again.  No to an ask with
\ room to grow asks once more for exactly the need.  No to that marks the
\ draw refused, so the rebuilt frame leaves what does not fit as CELL and
\ the fallback record says why.  The picture lane keeps its own refusal,
\ so a refused picture never keeps a frame from growing.
: _RTHP-STEP-RESIZING  ( producer -- scb-status more? output-needed? )
    DUP _RTHP.OWNER @ OVER _RTHP.OWNER-GEN @
    2 PICK _RTHP.FACADE @ RTE-OWNER-STATE@
    _RTHP-S-STATUS ! _RTHP-S-STATE !
    _RTHP-S-STATUS @ RTE-S-SESSION-LOST = IF
        SCB-S-SESSION-LOST SWAP _RTHP-FAULT-RESULT EXIT
    THEN
    _RTHP-S-STATUS @ RTE-S-OK <> IF
        SCB-S-INVALID SWAP _RTHP-FAULT-RESULT EXIT
    THEN
    _RTHP-S-STATE @ RTE-OWNER-ST-RESIZING = IF DROP SCB-S-OK -1 0 EXIT THEN
    _RTHP-S-STATE @ RTE-OWNER-ST-OPEN <> IF
        SCB-S-INVALID SWAP _RTHP-FAULT-RESULT EXIT
    THEN
    DUP _RTHP-HELD@ 0= IF SCB-S-INVALID SWAP _RTHP-FAULT-RESULT EXIT THEN
    DUP _RTHP-HELD-COVERS-ASK? 0= IF
        DUP _RTHP-ASK-WAS-EXACT? 0= IF
            DUP _RTHP-ASK-EXACT
            DUP _RTHP-RESIZE RTE-S-OK = IF DROP SCB-S-OK -1 0 EXIT THEN
        THEN
        DUP _RTHP.LANE-RESIZE @ IF
            RTHP-WHY-REFUSED OVER _RTHP.LANE-REFUSED !
        ELSE
            SCR-DRAW-GENERATION@ OVER _RTHP.SPACE-REFUSED-DRAW !
        THEN
    THEN
    0 OVER _RTHP.LANE-RESIZE !
    DUP _RTHP.RESUME-PHASE @ SWAP _RTHP.PHASE !
    SCB-S-OK 0 -1 ;

VARIABLE _RTHP-Z-P
VARIABLE _RTHP-Z-ACCEPT
VARIABLE _RTHP-Z-RETRY
VARIABLE _RTHP-Z-OUTPUT

: _RTHP-Z-ABORT-START-TARGET  ( -- )
    _RTHP-Z-ACCEPT @ _RTHP-PH-READY-REVEAL = IF
        _RTHP-Z-P @ _RTHP-TARGET-ABORT
        EXIT
    THEN
    _RTHP-Z-ACCEPT @ _RTHP-PH-LIVE =
    _RTHP-Z-RETRY @ _RTHP-PH-READY-DELTA = AND IF
        _RTHP-Z-P @ _RTHP-TARGET-ABORT
    THEN ;

: _RTHP-STEP-SEALED
  ( accepted-phase retry-phase output-after? producer -- scb-status more? output-needed? )
    _RTHP-Z-P ! _RTHP-Z-OUTPUT ! _RTHP-Z-RETRY ! _RTHP-Z-ACCEPT !
    _RTHP-Z-P @ _RTHP.FACADE @ RTE-UPDATE-STATE@
    _RTHP-S-STATUS ! _RTHP-S-STATE !
    _RTHP-S-STATUS @ RTE-S-SESSION-LOST = IF
        _RTHP-Z-ABORT-START-TARGET
        SCB-S-SESSION-LOST _RTHP-Z-P @ _RTHP-FAULT-RESULT EXIT
    THEN
    \ Provider rejection is reported while the sealed update is still
    \ cancellable.  Consume STALE before treating SEALED as ordinary wait.
    _RTHP-S-STATE @ DUP RTE-UPDATE-SEALED =
    SWAP RTE-UPDATE-IDLE = OR
    _RTHP-S-STATUS @ RTE-S-STALE = AND IF
        _RTHP-Z-P @ _RTHP.FACADE @ RTE-RETAINED-CANCEL
        DUP RTE-S-SESSION-LOST = IF
            _RTHP-Z-ABORT-START-TARGET
            DROP SCB-S-SESSION-LOST _RTHP-Z-P @ _RTHP-FAULT-RESULT EXIT
        THEN
        RTE-S-OK <> IF
            _RTHP-Z-ABORT-START-TARGET
            SCB-S-INVALID _RTHP-Z-P @ _RTHP-FAULT-RESULT EXIT
        THEN
        _RTHP-Z-ABORT-START-TARGET
        _RTHP-Z-RETRY @ _RTHP-Z-P @ _RTHP.PHASE !
        SCB-S-OK 0 -1 EXIT
    THEN
    _RTHP-S-STATE @ RTE-UPDATE-SEALED =
    _RTHP-S-STATUS @ RTE-S-OK = AND IF SCB-S-OK 0 -1 EXIT THEN
    _RTHP-S-STATE @ RTE-UPDATE-PUBLISHING =
    _RTHP-S-STATE @ RTE-UPDATE-AWAITING = OR IF
        SCB-S-OK -1 0 EXIT
    THEN
    _RTHP-S-STATE @ RTE-UPDATE-IDLE =
    _RTHP-S-STATUS @ RTE-S-OK = AND IF
        _RTHP-Z-ACCEPT @ _RTHP-PH-READY-REVEAL = IF
            _RTHP-Z-P @ _RTHP-ADVANCE-IDS? 0= IF
                _RTHP-Z-P @ _RTHP-TARGET-ABORT
                SCB-S-INVALID _RTHP-Z-P @ _RTHP-FAULT-RESULT EXIT
            THEN
            RTHPX-START-ACK _RTHP-Z-P @ _RTHP-EXTENSION-CHECK 0= IF
                _RTHP-Z-P @ _RTHP-TARGET-ABORT
                SCB-S-INVALID _RTHP-Z-P @ _RTHP-FAULT-RESULT EXIT
            THEN
        THEN
        _RTHP-Z-ACCEPT @ _RTHP-Z-P @ _RTHP.PHASE !
        _RTHP-Z-ACCEPT @ _RTHP-PH-LIVE = IF
            _RTHP-Z-P @ _RTHP-TARGET-PUBLISH? 0= IF
                SCB-S-INVALID _RTHP-Z-P @ _RTHP-FAULT-RESULT EXIT
            THEN
        THEN
        _RTHP-Z-ACCEPT @ _RTHP-PH-BLANK = IF
            _RTHP-Z-P @ _RTHP-TARGET-RETIRE
        THEN
        _RTHP-Z-OUTPUT @ IF SCB-S-OK 0 -1 ELSE SCB-S-OK 0 0 THEN
        EXIT
    THEN
    _RTHP-Z-ABORT-START-TARGET
    SCB-S-INVALID _RTHP-Z-P @ _RTHP-FAULT-RESULT ;

\ The frame on screen shows its pictures as the terminal now could.
: _RTHP-PICTURES-CURRENT?  ( producer -- flag )
    DUP _RTHP.TARGET-ACTIVE @ DUP 0= IF 2DROP -1 EXIT THEN
    _RTHP-TB.PICTURE-EPOCH @ SWAP _RTHP.PICTURE-EPOCH @ = ;

\ =====================================================================
\  Pictures the terminal holds
\ =====================================================================
\
\  While a frame is live, STEP runs the picture lane's one job at a time.
\  It asks how many pixels the surface has whenever the surface changes
\  and a picture needs a copy made to fit it; a picture whose file the
\  terminal decodes goes at its own size and needs no answer.  It gives
\  back a picture no frame shows and the latest build no longer wants; and
\  uploads a file or copy the latest build described as ready, first
\  asking the terminal for exactly the room it needs when the owner holds
\  too little.  A copy that replaces another of the same picture needs room
\  for both, since the old one shows until the terminal holds the new one.
\  A pixel answer for a draw with pictures, and each picture the terminal
\  comes to hold, leave the frame on screen stale, so the draw is built
\  again, and the lane waits for that frame before it does more.  No frame
\  is prepared while the pixel question or a drop runs, each one short
\  exchange, or while one of the job's frames awaits its answer.  Frames do
\  go out during an upload, between its chunks.
\
\  An upload reads each chunk from the picture's source only when the
\  terminal is ready for it, into one block the size of its largest chunk,
\  so the lane never holds a whole picture.  An upload stops once the
\  latest build no longer describes its picture, or when a chunk's read
\  finds the picture no longer shows that file or copy, so the link carries
\  no picture that will not be seen.
\
\  When the terminal refuses more room, the lane asks for none until a
\  build describes no picture.  Copies are then made to fit the room the
\  owner holds and no picture uses, since a smaller picture is still the
\  whole picture; with no such room a picture stays as it is and the
\  fallback record says why.  Room no picture uses goes back once no
\  picture is on its way.  A draw in which a job failed starts nothing
\  more; a newer draw tries again.

VARIABLE _RTHP-L-P
VARIABLE _RTHP-L-STATE
VARIABLE _RTHP-L-KIND
VARIABLE _RTHP-L-ITEM
VARIABLE _RTHP-L-RESULT
VARIABLE _RTHP-L-STATUS
VARIABLE _RTHP-L-DESC
VARIABLE _RTHP-L-ENTRY
VARIABLE _RTHP-L-INDEX
VARIABLE _RTHP-L-USED
VARIABLE _RTHP-L-USED-BYTES
\ The bytes the owner holds for the wanted copy, its decoded size, and the
\ bytes its upload sends.
VARIABLE _RTHP-L-BYTES
VARIABLE _RTHP-L-SEND
VARIABLE _RTHP-L-FREE
\ The chunk an upload wants: where it starts, and how many bytes are read.
VARIABLE _RTHP-L-OFFSET
VARIABLE _RTHP-L-CHUNK

: _RTHP-L-ENTRIES  ( -- n )
    _RTHP-L-P @ _RTHP.RESOURCES-U @ _RTHP-RESOURCE-SIZE / ;
: _RTHP-L-ENTRY-AT  ( index -- entry )
    _RTHP-RESOURCE-SIZE * _RTHP-L-P @ _RTHP.RESOURCES-A @ + ;
: _RTHP-L-DESCRIPTOR-AT  ( index -- descriptor )
    UPICSN-DESCRIPTOR-SIZE * _RTHP-L-P @ _RTHP.PICTURES-A @ + ;

: _RTHP-L-CHUNK-FREE  ( -- )
    _RTHP-L-P @ _RTHP.CHUNK-A @ ?DUP IF
        _RTHP-L-P @ _RTHP.CHUNK-U @ _RTHP-L-P @ _RTHP.MEMORY @ MSRC-FREE
    THEN
    0 _RTHP-L-P @ _RTHP.CHUNK-A ! 0 _RTHP-L-P @ _RTHP.CHUNK-U ! ;

\ A block from the memory source for the lane, kept apart from everything
\ the producer touches; 0 when the source has no room.
: _RTHP-L-ALLOC  ( bytes -- a|0 )
    DUP _RTHP-L-P @ _RTHP.MEMORY @ MSRC-ALLOC DUP 0= IF NIP EXIT THEN
    2DUP SWAP _RTHP-L-P @ _RTHP-G-SEPARATE? S" Desk's memory source" CHK-HANDOVER
        IF NIP EXIT THEN
    SWAP _RTHP-L-P @ _RTHP.MEMORY @ MSRC-FREE 0 ;

\ Start nothing more in this draw; HOLD also notes why pictures stay CELL.
: _RTHP-L-PAUSE  ( -- )
    SCR-DRAW-GENERATION@ _RTHP-L-P @ _RTHP.LANE-HOLD-DRAW ! ;
: _RTHP-L-HOLD  ( reason -- )
    RTHP-PART-PICTURES SWAP _RTHP-L-P @ _RTHP-FALLBACK-NOTE _RTHP-L-PAUSE ;
\ The lane could not send a picture a build wants, for REASON.  Every
\ picture goes back to CELL, which shows it, until the lane sends one.
: _RTHP-L-FAIL  ( reason -- )
    _RTHP-L-HOLD -1 _RTHP-L-P @ _RTHP.LANE-FAILED ! UPICSN-RELEASE-ALL ;

: _RTHP-L-HELD-BACK?  ( -- flag )
    SCR-DRAW-GENERATION@ _RTHP-L-P @ _RTHP.LANE-HOLD-DRAW @ = ;

: _RTHP-L-FAULT  ( scb-status -- scb-status more? output-needed? )
    _RTHP-L-P @ _RTHP-FAULT-RESULT ;

\ The resources the table's entries take and their bytes.
: _RTHP-L-USE  ( -- )
    0 _RTHP-L-USED ! 0 _RTHP-L-USED-BYTES !
    _RTHP-L-ENTRIES 0 ?DO
        I _RTHP-L-ENTRY-AT DUP _RTHP-RS.ID @ IF
            1 _RTHP-L-USED +! _RTHP-RS.BYTES @ _RTHP-L-USED-BYTES +!
        ELSE DROP THEN
    LOOP ;

\ Ask the terminal for the room ASK names, as the lane's REQUEST: 1 for
\ more, 2 to give some back.  The phase that asked resumes once it answers.
: _RTHP-L-RESIZE  ( request -- rte-status )
    _RTHP-L-P @ _RTHP-RESIZE DUP RTE-S-OK = IF
        SWAP _RTHP-L-P @ _RTHP.LANE-RESIZE !
        _RTHP-L-P @ _RTHP.PHASE @ _RTHP-L-P @ _RTHP.RESUME-PHASE !
        _RTHP-PH-RESIZING _RTHP-L-P @ _RTHP.PHASE ! EXIT
    THEN
    NIP ;

\ ---------------------------------------------------------------------
\  A finished job
\ ---------------------------------------------------------------------

\ The pixels the surface has.  An answer the terminal could not give
\ leaves them unknown, and pictures CELL, until the surface changes.  A
\ change matters only to a draw that shows pictures.
: _RTHP-L-PIXELS-DONE  ( -- output? )
    _RTHP-L-STATE @ RTE-JOB-DONE = _RTHP-L-RESULT @ RTE-S-OK = AND IF
        _RTHP-L-P @ _RTHP.FACADE @ RTE-PIXELS@ RTE-S-OK <> IF
            2DROP DROP 0 0
        ELSE ROT DROP THEN
    ELSE 0 0 THEN
    _RTHP-L-P @ _RTHP.PICTURE-ASK UPICSN-ASK.PIXEL-H @ OVER <>
    _RTHP-L-P @ _RTHP.PICTURE-ASK UPICSN-ASK.PIXEL-W @ 3 PICK <> OR >R
    _RTHP-L-P @ _RTHP.PICTURE-ASK UPICSN-ASK.PIXEL-H !
    _RTHP-L-P @ _RTHP.PICTURE-ASK UPICSN-ASK.PIXEL-W !
    R> _RTHP-L-P @ _RTHP.PICTURE-COUNT @ 0<> AND
    DUP IF 1 _RTHP-L-P @ _RTHP.PICTURE-EPOCH +! THEN ;

\ The terminal refused the bytes of the upload's picture as no picture of
\ its size.  The picture's widget remembers it, so no build sends that
\ picture again until the widget is given another source, and CELL shows
\ it.  The frame on screen is stale, so the lane waits for the frame built
\ again, which describes the picture as failed.
: _RTHP-L-REFUSED  ( -- )
    _RTHP-L-ENTRY @ _RTHP-RS.DOCUMENT @ _RTHP-L-ENTRY @ _RTHP-RS.INDEX @
    _RTHP-L-ENTRY @ _RTHP-RS.KEY @
    _RTHP-L-ENTRY @ _RTHP-RS.REVISION @ PIC-R-DAMAGED
    _RTHP-L-P @ _RTHP.ADAPTER @ RUHA-PICTURE-FAIL DROP
    1 _RTHP-L-P @ _RTHP.PICTURE-EPOCH +! ;

\ A copy the terminal now holds leaves the frame on screen stale.  One the
\ lane stopped is forgotten.  One whose bytes the terminal refused stays
\ CELL, and the other pictures stay rich.  One the terminal had no room
\ for, or that failed otherwise, waits for a newer draw while CELL shows
\ the pictures.
: _RTHP-L-UPLOAD-DONE  ( -- output? )
    _RTHP-L-P @ _RTHP.LANE-ENTRY @ _RTHP-L-ENTRY-AT _RTHP-L-ENTRY !
    _RTHP-L-STATE @ RTE-JOB-DONE = _RTHP-L-RESULT @ RTE-S-OK = AND IF
        _RTHP-RS-HELD _RTHP-L-ENTRY @ _RTHP-RS.STATE !
        1 _RTHP-L-P @ _RTHP.PICTURE-EPOCH +! -1 EXIT
    THEN
    _RTHP-L-ENTRY @ _RTHP-RS.STATE @ _RTHP-RS-CANCELLED = IF
        _RTHP-L-ENTRY @ _RTHP-RESOURCE-SIZE 0 FILL 0 EXIT
    THEN
    _RTHP-L-RESULT @ RTE-S-SOURCE = IF
        _RTHP-L-REFUSED _RTHP-L-ENTRY @ _RTHP-RESOURCE-SIZE 0 FILL -1 EXIT
    THEN
    _RTHP-L-ENTRY @ _RTHP-RESOURCE-SIZE 0 FILL
    _RTHP-L-RESULT @ RTE-S-CAPACITY = IF RTHP-WHY-REFUSED ELSE RTHP-WHY-OTHER THEN
        _RTHP-L-FAIL 0 ;

\ A picture the terminal would not give back may still be shown; it stays
\ held, and nothing more starts in this draw.  Room a picture no longer
\ takes may go back to the terminal too.
: _RTHP-L-DROP-DONE  ( -- )
    _RTHP-L-P @ _RTHP.LANE-ENTRY @ _RTHP-L-ENTRY-AT _RTHP-L-ENTRY !
    _RTHP-L-STATE @ RTE-JOB-DONE = _RTHP-L-RESULT @ RTE-S-OK = AND IF
        _RTHP-L-ENTRY @ _RTHP-RESOURCE-SIZE 0 FILL
        -1 _RTHP-L-P @ _RTHP.LANE-SHRINK ! EXIT
    THEN
    RTHP-WHY-OTHER _RTHP-L-HOLD ;

\ The latest build's description of the picture the upload sends: the
\ ready descriptor whose copy the upload's entry is, or 0 once no build
\ describes that picture at that size and in that format.
: _RTHP-L-SENDING  ( -- descriptor|0 )
    _RTHP-L-P @ _RTHP.PICTURE-COUNT @ 0 ?DO
        I _RTHP-L-DESCRIPTOR-AT DUP UPICSN-STATE@ UPICSN-C-READY = IF
            DUP 0 _RTHP-L-P @ _RTHP-RESOURCE-FOR _RTHP-L-ENTRY @ = IF
                UNLOOP EXIT
            THEN
        THEN DROP
    LOOP 0 ;

\ Stop the upload, so the link carries no picture that will not be seen.
\ Once its last frame awaits the terminal it can only finish, and its
\ picture then goes back like any other no frame wants.
: _RTHP-L-STOP  ( -- scb-status more? output-needed? )
    _RTHP-L-P @ _RTHP.FACADE @ RTE-RESOURCE-CANCEL
    DUP RTE-S-OK = IF
        DROP _RTHP-RS-CANCELLED _RTHP-L-ENTRY @ _RTHP-RS.STATE !
        SCB-S-OK -1 0 EXIT
    THEN
    RTE-S-SESSION-LOST = IF SCB-S-SESSION-LOST _RTHP-L-FAULT EXIT THEN
    SCB-S-OK -1 0 ;

\ The upload wants its next chunk, of the picture DESCRIPTOR describes:
\ read it into the lane's block from the picture's source and hand it
\ over.  The block comes from the memory source at the first chunk, the
\ size of the largest, and goes back when the upload ends.  A read that
\ finds the picture no longer showing that file or copy stops the upload,
\ and the lane starts nothing more in this draw: the draw that changed the
\ picture describes it again.  A block the memory source refuses, or a
\ read that fails otherwise, stops it too, and CELL then shows every
\ picture.
: _RTHP-L-FEED  ( descriptor -- scb-status more? output-needed? )
    _RTHP-L-DESC !
    _RTHP-L-P @ _RTHP.FACADE @ RTE-RESOURCE-WANTS@ RTE-S-OK <> IF
        2DROP SCB-S-INVALID _RTHP-L-FAULT EXIT
    THEN
    _RTHP-L-CHUNK ! _RTHP-L-OFFSET !
    _RTHP-L-P @ _RTHP.CHUNK-A @ 0= IF
        _RTHP-L-CHUNK @ _RTHP-L-ALLOC ?DUP 0= IF
            RTHP-WHY-MEMORY _RTHP-L-FAIL _RTHP-L-STOP EXIT
        THEN
        _RTHP-L-P @ _RTHP.CHUNK-A !
        _RTHP-L-CHUNK @ _RTHP-L-P @ _RTHP.CHUNK-U !
    THEN
    _RTHP-L-CHUNK @ _RTHP-L-P @ _RTHP.CHUNK-U @ _RTHP-UMIN _RTHP-L-CHUNK !
    _RTHP-L-DESC @ _RTHP-L-OFFSET @
    _RTHP-L-P @ _RTHP.CHUNK-A @ _RTHP-L-CHUNK @
    _RTHP-L-P @ _RTHP.ADAPTER @ RUHA-PICTURE-PULL
    DUP RUHA-S-OK <> IF
        RUHA-S-STALE = IF _RTHP-L-PAUSE ELSE RTHP-WHY-OTHER _RTHP-L-FAIL THEN
        _RTHP-L-STOP EXIT
    THEN DROP
    _RTHP-L-P @ _RTHP.CHUNK-A @ _RTHP-L-CHUNK @
    _RTHP-L-P @ _RTHP.FACADE @ RTE-RESOURCE-FEED RTE-S-OK <> IF
        SCB-S-INVALID _RTHP-L-FAULT EXIT
    THEN
    SCB-S-OK -1 0 ;

: _RTHP-L-POLL  ( -- scb-status more? output-needed? )
    _RTHP-L-P @ _RTHP.FACADE @ RTE-JOB@ _RTHP-L-STATUS ! _RTHP-L-RESULT !
        _RTHP-L-ITEM ! _RTHP-L-KIND ! _RTHP-L-STATE !
    _RTHP-L-STATUS @ RTE-S-SESSION-LOST = IF SCB-S-SESSION-LOST _RTHP-L-FAULT EXIT THEN
    _RTHP-L-STATUS @ RTE-S-OK <> IF SCB-S-INVALID _RTHP-L-FAULT EXIT THEN
    \ An upload still to send stops once the latest build no longer
    \ describes its picture, and is fed each chunk it wants.
    _RTHP-L-STATE @ DUP RTE-JOB-QUEUED = SWAP RTE-JOB-WANTS = OR
    _RTHP-L-KIND @ RTE-JOB-UPLOAD = AND
    _RTHP-L-P @ _RTHP.LANE-JOB @ RTE-JOB-UPLOAD = AND IF
        _RTHP-L-P @ _RTHP.LANE-ENTRY @ _RTHP-L-ENTRY-AT _RTHP-L-ENTRY !
        _RTHP-L-ENTRY @ _RTHP-RS.STATE @ _RTHP-RS-UPLOADING = IF
            _RTHP-L-SENDING DUP 0= IF DROP _RTHP-L-STOP EXIT THEN
            _RTHP-L-STATE @ RTE-JOB-WANTS = IF _RTHP-L-FEED EXIT THEN
            DROP
        THEN
    THEN
    _RTHP-L-STATE @ DUP RTE-JOB-QUEUED = OVER RTE-JOB-AWAITING = OR
    SWAP RTE-JOB-WANTS = OR IF
        SCB-S-OK -1 0 EXIT
    THEN
    _RTHP-L-STATE @ DUP RTE-JOB-DONE <> SWAP RTE-JOB-FAILED <> AND
    _RTHP-L-KIND @ _RTHP-L-P @ _RTHP.LANE-JOB @ <> OR IF
        SCB-S-INVALID _RTHP-L-FAULT EXIT
    THEN
    0
    _RTHP-L-KIND @ RTE-JOB-PIXELS = IF DROP _RTHP-L-PIXELS-DONE THEN
    _RTHP-L-KIND @ RTE-JOB-UPLOAD = IF DROP _RTHP-L-UPLOAD-DONE THEN
    _RTHP-L-KIND @ RTE-JOB-DROP = IF _RTHP-L-DROP-DONE THEN
    _RTHP-L-CHUNK-FREE
    0 _RTHP-L-P @ _RTHP.LANE-JOB ! 0 _RTHP-L-P @ _RTHP.LANE-ENTRY !
    _RTHP-L-P @ _RTHP.FACADE @ RTE-JOB-CLEAR RTE-S-OK <> IF
        DROP SCB-S-INVALID _RTHP-L-FAULT EXIT
    THEN
    >R SCB-S-OK 0 R> ;

\ ---------------------------------------------------------------------
\  The next job
\ ---------------------------------------------------------------------

\ A picture the latest build described needs a copy made to fit the
\ surface's pixels, rather than going as its file.
: _RTHP-L-COPIES?  ( -- flag )
    _RTHP-L-P @ _RTHP.PICTURE-COUNT @ 0 ?DO
        I _RTHP-L-DESCRIPTOR-AT UPICSN-FORMAT@ PIC-F-RGBA8 = IF
            -1 UNLOOP EXIT
        THEN
    LOOP 0 ;

: _RTHP-L-ASK-PIXELS  ( -- scb-status more? output-needed? )
    \ The question is about this surface.  No frame is built until the
    \ answer, which replaces the pixels known before.
    _RTHP-L-P @ _RTHP.COLS @
        _RTHP-L-P @ _RTHP.PICTURE-ASK UPICSN-ASK.SURFACE-COLS !
    _RTHP-L-P @ _RTHP.ROWS @
        _RTHP-L-P @ _RTHP.PICTURE-ASK UPICSN-ASK.SURFACE-ROWS !
    0 0 _RTHP-L-P @ _RTHP.COLS @ _RTHP-L-P @ _RTHP.ROWS @
    _RTHP-L-P @ _RTHP.FACADE @ RTE-PIXELS-ASK
    DUP RTE-S-OK = IF
        DROP RTE-JOB-PIXELS _RTHP-L-P @ _RTHP.LANE-JOB ! SCB-S-OK -1 0 EXIT
    THEN
    DUP RTE-S-SESSION-LOST = IF DROP SCB-S-SESSION-LOST _RTHP-L-FAULT EXIT THEN
    \ Busy for now: ask again on a later step.
    RTE-S-WOULD-BLOCK = IF
        0 _RTHP-L-P @ _RTHP.PICTURE-ASK UPICSN-ASK.SURFACE-COLS !
        SCB-S-OK -1 0 EXIT
    THEN
    \ A terminal that cannot be asked leaves this surface's pixels unknown.
    0 _RTHP-L-P @ _RTHP.PICTURE-ASK UPICSN-ASK.PIXEL-W !
    0 _RTHP-L-P @ _RTHP.PICTURE-ASK UPICSN-ASK.PIXEL-H !
    SCB-S-OK 0 0 ;

\ BANK's frame shows resource ID.
: _RTHP-L-SHOWN?  ( id bank -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    DUP _RTHP-TB.STATIC-COUNT @ 0 ?DO
        DUP _RTHP-PACK-STATICS-A I RTE-STATIC-SIZE * +
        DUP _RTE-STATIC.KIND @ RTE-STATIC-IMAGE =
        SWAP _RTE-STATIC.RESOURCE @ 3 PICK = AND IF
            2DROP -1 UNLOOP EXIT
        THEN
    LOOP 2DROP 0 ;

\ A ready picture the latest build described shows ENTRY's copy.
: _RTHP-L-WANTED?  ( entry -- flag )
    _RTHP-L-P @ _RTHP.PICTURE-COUNT @ 0 ?DO
        I _RTHP-L-DESCRIPTOR-AT DUP UPICSN-STATE@ UPICSN-C-READY = IF
            0 _RTHP-L-P @ _RTHP-RESOURCE-FOR OVER = IF
                DROP -1 UNLOOP EXIT
            THEN
        ELSE DROP THEN
    LOOP DROP 0 ;

\ The first held picture no frame shows and no build wants, or -1.
: _RTHP-L-DROP-INDEX  ( -- index|-1 )
    _RTHP-L-ENTRIES 0 ?DO
        I _RTHP-L-ENTRY-AT _RTHP-L-ENTRY !
        _RTHP-L-ENTRY @ _RTHP-RS.STATE @ _RTHP-RS-HELD = IF
            _RTHP-L-ENTRY @ _RTHP-RS.ID @
                _RTHP-L-P @ _RTHP.TARGET-ACTIVE @ _RTHP-L-SHOWN? 0=
            _RTHP-L-ENTRY @ _RTHP-RS.ID @
                _RTHP-L-P @ _RTHP.TARGET-PENDING @ _RTHP-L-SHOWN? 0= AND
            _RTHP-L-ENTRY @ _RTHP-L-WANTED? 0= AND IF I UNLOOP EXIT THEN
        THEN
    LOOP -1 ;

: _RTHP-L-START-DROP  ( index -- scb-status more? output-needed? )
    DUP _RTHP-L-P @ _RTHP.LANE-ENTRY ! _RTHP-L-ENTRY-AT _RTHP-L-ENTRY !
    _RTHP-L-P @ _RTHP.OWNER @ _RTHP-L-P @ _RTHP.OWNER-GEN @
    _RTHP-L-ENTRY @ _RTHP-RS.ID @ _RTHP-L-ENTRY @ _RTHP-RS.BYTES @
    _RTHP-L-P @ _RTHP.FACADE @ RTE-RESOURCE-DROP
    DUP RTE-S-OK = IF
        DROP RTE-JOB-DROP _RTHP-L-P @ _RTHP.LANE-JOB ! SCB-S-OK -1 0 EXIT
    THEN
    0 _RTHP-L-P @ _RTHP.LANE-ENTRY !
    DUP RTE-S-SESSION-LOST = IF DROP SCB-S-SESSION-LOST _RTHP-L-FAULT EXIT THEN
    RTE-S-WOULD-BLOCK = IF SCB-S-OK -1 0 EXIT THEN
    RTHP-WHY-OTHER _RTHP-L-HOLD SCB-S-OK 0 0 ;

\ The first ready picture the latest build described whose copy the
\ terminal neither holds nor is being sent, or 0.
: _RTHP-L-WANTED  ( -- descriptor|0 )
    _RTHP-L-P @ _RTHP.PICTURE-COUNT @ 0 ?DO
        I _RTHP-L-DESCRIPTOR-AT DUP UPICSN-STATE@ UPICSN-C-READY = IF
            DUP 0 _RTHP-L-P @ _RTHP-RESOURCE-FOR 0= IF UNLOOP EXIT THEN
        THEN DROP
    LOOP 0 ;

\ A picture the latest build described still waits for its copy, or for
\ the terminal to hold it.
: _RTHP-L-ON-ITS-WAY?  ( -- flag )
    _RTHP-L-P @ _RTHP.PICTURE-COUNT @ 0 ?DO
        I _RTHP-L-DESCRIPTOR-AT DUP UPICSN-STATE@
        DUP UPICSN-C-PENDING = IF 2DROP -1 UNLOOP EXIT THEN
        UPICSN-C-READY = IF
            0 _RTHP-L-P @ _RTHP-RESOURCE-FOR 0= IF -1 UNLOOP EXIT THEN
        ELSE DROP THEN
    LOOP 0 ;

\ The owner holds room for one more resource of BYTES.
: _RTHP-L-ROOM?  ( -- flag )
    1 _RTHP-L-P @ _RTHP.HELD _RTHP-Q@ _RTHP-L-USED @ U> 0= IF 0 EXIT THEN
    _RTHP-L-USED-BYTES @ _RTHP-L-BYTES @ _RTHP-U+? 0= IF DROP 0 EXIT THEN
    4 _RTHP-L-P @ _RTHP.HELD _RTHP-Q@ U> 0= ;

\ The terminal refused the lane more room, or could never give it, for
\ REASON.  A smaller copy still shows the whole picture: when the owner
\ holds a resource and at least a pixel's bytes that no picture uses, and
\ fewer than copies keep within now, the pictures are described again to
\ fit them.  Otherwise each stays as it is, and the fallback record says
\ why.
: _RTHP-L-FIT-HELD  ( reason -- scb-status more? output-needed? )
    DUP _RTHP-L-P @ _RTHP.LANE-REFUSED !
    4 _RTHP-L-P @ _RTHP.HELD _RTHP-Q@ _RTHP-L-USED-BYTES @
        2DUP U> IF - ELSE 2DROP 0 THEN _RTHP-L-FREE !
    1 _RTHP-L-P @ _RTHP.HELD _RTHP-Q@ _RTHP-L-USED @ U>
    _RTHP-L-FREE @ 4 U< 0= AND
    _RTHP-L-P @ _RTHP.LANE-BUDGET @ DUP 0= SWAP _RTHP-L-FREE @ U> OR AND IF
        DROP
        _RTHP-L-FREE @ _RTHP-L-P @ _RTHP.LANE-BUDGET !
        1 _RTHP-L-P @ _RTHP.PICTURE-EPOCH +!
        SCB-S-OK 0 -1 EXIT
    THEN
    _RTHP-L-FAIL SCB-S-OK 0 0 ;

\ Ask the terminal for exactly what the owner holds and room for one more
\ resource of BYTES.  A copy that replaces another of the same picture
\ needs room for both while the old one shows, and USE counts it.
: _RTHP-L-ASK-ROOM  ( -- scb-status more? output-needed? )
    _RTHP-L-P @ _RTHP.HELD _RTHP-L-P @ _RTHP.NEED RTE-QUOTA-SIZE MOVE
    _RTHP-L-USED @ 1+ 1 _RTHP-L-P @ _RTHP.NEED _RTHP-Q@ _RTHP-UMAX
        1 _RTHP-L-P @ _RTHP.NEED _RTHP-Q!
    _RTHP-L-USED-BYTES @ _RTHP-L-BYTES @ _RTHP-U+? 0= IF
        DROP RTHP-WHY-LIMIT _RTHP-L-FIT-HELD EXIT
    THEN
    4 _RTHP-L-P @ _RTHP.NEED _RTHP-Q@ _RTHP-UMAX
        4 _RTHP-L-P @ _RTHP.NEED _RTHP-Q!
    _RTHP-L-P @ _RTHP-NEED-BEYOND-LIMITS? IF
        RTHP-WHY-LIMIT _RTHP-L-FIT-HELD EXIT
    THEN
    _RTHP-L-P @ _RTHP-ASK-EXACT
    1 _RTHP-L-RESIZE
    DUP RTE-S-OK = IF DROP SCB-S-OK -1 0 EXIT THEN
    DUP RTE-S-SESSION-LOST = IF DROP SCB-S-SESSION-LOST _RTHP-L-FAULT EXIT THEN
    RTE-S-WOULD-BLOCK = IF SCB-S-OK -1 0 EXIT THEN
    RTHP-WHY-REFUSED _RTHP-L-FIT-HELD ;

\ The table has an entry for each resource the owner holds room for.
: _RTHP-L-TABLE?  ( -- flag )
    1 _RTHP-L-P @ _RTHP.HELD _RTHP-Q@
    DUP _RTHP-L-ENTRIES U> 0= IF DROP -1 EXIT THEN
    _RTHP-RESOURCE-SIZE * DUP _RTHP-L-ALLOC DUP 0= IF 2DROP 0 EXIT THEN
    2DUP SWAP 0 FILL
    _RTHP-L-P @ _RTHP.RESOURCES-A @ ?DUP IF
        OVER _RTHP-L-P @ _RTHP.RESOURCES-U @ MOVE
        _RTHP-L-P @ _RTHP.RESOURCES-A @ _RTHP-L-P @ _RTHP.RESOURCES-U @
            _RTHP-L-P @ _RTHP.MEMORY @ MSRC-FREE
    THEN
    _RTHP-L-P @ _RTHP.RESOURCES-A ! _RTHP-L-P @ _RTHP.RESOURCES-U ! -1 ;

: _RTHP-L-FREE-INDEX  ( -- index|-1 )
    _RTHP-L-ENTRIES 0 ?DO
        I _RTHP-L-ENTRY-AT _RTHP-RS.ID @ 0= IF I UNLOOP EXIT THEN
    LOOP -1 ;

\ A picture format as the facade names it; 0 for none it knows.
: _RTHP-PICTURE>RTE  ( pic-format -- rte-format )
    DUP PIC-F-RGBA8 = IF DROP RTE-PICTURE-RGBA8 EXIT THEN
    DUP PIC-F-QOI = IF DROP RTE-PICTURE-QOI EXIT THEN
    DUP PIC-F-PNG = IF DROP RTE-PICTURE-PNG EXIT THEN
    PIC-F-JPEG = IF RTE-PICTURE-JPEG EXIT THEN
    0 ;

\ Send the wanted file or copy as the next resource.  Nothing is read yet:
\ the upload asks for each chunk in turn (_RTHP-L-FEED).
: _RTHP-L-START-UPLOAD  ( -- scb-status more? output-needed? )
    _RTHP-L-DESC @ UPICSN-COPY-WIDTH@ _RTHP-L-DESC @ UPICSN-COPY-HEIGHT@ * 4 *
        _RTHP-L-BYTES !
    _RTHP-L-DESC @ UPICSN-COPY-BYTES@ _RTHP-L-SEND !
    _RTHP-L-P @ _RTHP-HELD@ 0= IF SCB-S-INVALID _RTHP-L-FAULT EXIT THEN
    _RTHP-L-USE
    _RTHP-L-ROOM? 0= IF
        _RTHP-L-P @ _RTHP.LANE-REFUSED @ ?DUP IF _RTHP-L-FIT-HELD EXIT THEN
        _RTHP-L-ASK-ROOM EXIT
    THEN
    _RTHP-L-TABLE? 0= IF RTHP-WHY-MEMORY _RTHP-L-FAIL SCB-S-OK 0 0 EXIT THEN
    _RTHP-L-FREE-INDEX DUP 0< IF
        DROP RTHP-WHY-OTHER _RTHP-L-FAIL SCB-S-OK 0 0 EXIT
    THEN _RTHP-L-INDEX !
    _RTHP-L-INDEX @ _RTHP-L-ENTRY-AT _RTHP-L-ENTRY !
    _RTHP-L-P @ _RTHP.NEXT-RESOURCE @ _RTHP-L-ENTRY @ _RTHP-RS.ID !
    _RTHP-L-DESC @ UPICSN-COPY-WIDTH@ _RTHP-L-ENTRY @ _RTHP-RS.WIDTH !
    _RTHP-L-DESC @ UPICSN-COPY-HEIGHT@ _RTHP-L-ENTRY @ _RTHP-RS.HEIGHT !
    _RTHP-L-BYTES @ _RTHP-L-ENTRY @ _RTHP-RS.BYTES !
    _RTHP-RS-UPLOADING _RTHP-L-ENTRY @ _RTHP-RS.STATE !
    _RTHP-L-DESC @ UPICSN-FORMAT@ _RTHP-L-ENTRY @ _RTHP-RS.FORMAT !
    _RTHP-L-DESC @ UPICSN-DOCUMENT@ _RTHP-L-ENTRY @ _RTHP-RS.DOCUMENT !
    _RTHP-L-DESC @ UPICSN-SOURCE-INDEX@ _RTHP-L-ENTRY @ _RTHP-RS.INDEX !
    _RTHP-L-DESC @ UPICSN-ROOT-KEY@ _RTHP-L-ENTRY @ _RTHP-RS.KEY !
    _RTHP-L-DESC @ UPICSN-REVISION@ _RTHP-L-ENTRY @ _RTHP-RS.REVISION !
    _RTHP-L-P @ _RTHP.OWNER @ _RTHP-L-P @ _RTHP.OWNER-GEN @
    _RTHP-L-ENTRY @ _RTHP-RS.ID @
    _RTHP-L-ENTRY @ _RTHP-RS.FORMAT @ _RTHP-PICTURE>RTE
    _RTHP-L-ENTRY @ _RTHP-RS.WIDTH @ _RTHP-L-ENTRY @ _RTHP-RS.HEIGHT @
    _RTHP-L-SEND @ _RTHP-L-P @ _RTHP.FACADE @ RTE-RESOURCE-UPLOAD
    DUP RTE-S-OK = IF
        DROP 1 _RTHP-L-P @ _RTHP.NEXT-RESOURCE +!
        _RTHP-L-INDEX @ _RTHP-L-P @ _RTHP.LANE-ENTRY !
        0 _RTHP-L-P @ _RTHP.LANE-FAILED !
        RTE-JOB-UPLOAD _RTHP-L-P @ _RTHP.LANE-JOB ! SCB-S-OK -1 0 EXIT
    THEN
    _RTHP-L-ENTRY @ _RTHP-RESOURCE-SIZE 0 FILL
    DUP RTE-S-SESSION-LOST = IF DROP SCB-S-SESSION-LOST _RTHP-L-FAULT EXIT THEN
    RTE-S-WOULD-BLOCK = IF SCB-S-OK -1 0 EXIT THEN
    RTHP-WHY-OTHER _RTHP-L-FAIL SCB-S-OK 0 0 ;

\ Give back the room no picture uses: the owner keeps exactly the
\ resources its pictures take and their bytes.  A terminal that keeps the
\ room anyway is not asked again until another picture goes.
: _RTHP-L-GIVE-BACK  ( -- scb-status more? output-needed? )
    0 _RTHP-L-P @ _RTHP.LANE-SHRINK !
    _RTHP-L-P @ _RTHP-HELD@ 0= IF SCB-S-INVALID _RTHP-L-FAULT EXIT THEN
    _RTHP-L-USE
    1 _RTHP-L-P @ _RTHP.HELD _RTHP-Q@ _RTHP-L-USED @ U>
    4 _RTHP-L-P @ _RTHP.HELD _RTHP-Q@ _RTHP-L-USED-BYTES @ U> OR 0= IF
        SCB-S-OK 0 0 EXIT
    THEN
    _RTHP-L-P @ _RTHP.HELD _RTHP-L-P @ _RTHP.ASK RTE-QUOTA-SIZE MOVE
    _RTHP-L-USED @ 1 _RTHP-L-P @ _RTHP.ASK _RTHP-Q!
    _RTHP-L-USED-BYTES @ 4 _RTHP-L-P @ _RTHP.ASK _RTHP-Q!
    _RTHP-L-P @ _RTHP.ASK _RTHP-L-P @ _RTHP.NEED RTE-QUOTA-SIZE MOVE
    2 _RTHP-L-RESIZE
    DUP RTE-S-OK = IF DROP SCB-S-OK -1 0 EXIT THEN
    RTE-S-SESSION-LOST = IF SCB-S-SESSION-LOST _RTHP-L-FAULT EXIT THEN
    SCB-S-OK 0 0 ;

: _RTHP-L-FINISH  ( scb-status more? output-needed? -- same )
    0 _RTHP-L-P ! 0 _RTHP-L-DESC ! 0 _RTHP-L-ENTRY !
    0 _RTHP-L-OFFSET ! 0 _RTHP-L-CHUNK ! ;

: _RTHP-LANE-BODY  ( -- scb-status more? output-needed? )
    _RTHP-L-P @ _RTHP-LANE-ON? 0= IF SCB-S-OK 0 0 EXIT THEN
    _RTHP-L-P @ _RTHP.LANE-JOB @ IF
        _RTHP-L-P @ RTHP-VALID? 0= IF SCB-S-INVALID 0 0 EXIT THEN
        _RTHP-L-POLL EXIT
    THEN
    _RTHP-L-P @ _RTHP.PICTURE-ASK UPICSN-ASK.SURFACE-COLS @
        _RTHP-L-P @ _RTHP.COLS @ <>
    _RTHP-L-P @ _RTHP.PICTURE-ASK UPICSN-ASK.SURFACE-ROWS @
        _RTHP-L-P @ _RTHP.ROWS @ <> OR
    _RTHP-L-COPIES? AND IF
        _RTHP-L-P @ RTHP-VALID? 0= IF SCB-S-INVALID 0 0 EXIT THEN
        _RTHP-L-ASK-PIXELS EXIT
    THEN
    \ The frame on screen was built before the latest change in what it can
    \ show of its pictures: wait for the one built again.
    _RTHP-L-P @ _RTHP-PICTURES-CURRENT? 0= IF SCB-S-OK 0 0 EXIT THEN
    \ A build that describes no picture ends a refusal or failure: the next
    \ picture asks the terminal again, and the rich side takes it.
    _RTHP-L-P @ _RTHP.PICTURE-COUNT @ 0= IF
        0 _RTHP-L-P @ _RTHP.LANE-REFUSED ! 0 _RTHP-L-P @ _RTHP.LANE-BUDGET !
        0 _RTHP-L-P @ _RTHP.LANE-FAILED !
    THEN
    _RTHP-L-HELD-BACK? IF SCB-S-OK 0 0 EXIT THEN
    _RTHP-L-DROP-INDEX DUP 0< 0= IF
        _RTHP-L-P @ RTHP-VALID? 0= IF DROP SCB-S-INVALID 0 0 EXIT THEN
        _RTHP-L-START-DROP EXIT
    THEN DROP
    \ Room no picture uses goes back once no picture is on its way.
    _RTHP-L-P @ _RTHP.LANE-SHRINK @ IF
        _RTHP-L-ON-ITS-WAY? 0= IF
            _RTHP-L-P @ RTHP-VALID? 0= IF SCB-S-INVALID 0 0 EXIT THEN
            _RTHP-L-GIVE-BACK EXIT
        THEN
    THEN
    \ Uploads wait for a rich frame to show them in.
    _RTHP-L-P @ _RTHP.PHASE @ _RTHP-PH-LIVE <> IF SCB-S-OK 0 0 EXIT THEN
    _RTHP-L-WANTED DUP 0= IF DROP SCB-S-OK 0 0 EXIT THEN _RTHP-L-DESC !
    _RTHP-L-P @ RTHP-VALID? 0= IF SCB-S-INVALID 0 0 EXIT THEN
    _RTHP-L-START-UPLOAD ;

\ _RTHP-LANE-STEP ( producer -- scb-status more? output-needed? )
\   The picture lane's step for a LIVE or BLANK producer.
: _RTHP-LANE-STEP  ( producer -- scb-status more? output-needed? )
    _RTHP-L-P ! _RTHP-LANE-BODY _RTHP-L-FINISH ;

\ A LIVE producer's step publishes nothing.  Before it runs the picture
\ lane it checks only that this is the producer and the surface is
\ unchanged; the lane proves the whole producer with RTHP-VALID? before it
\ acts, as every other step and preparation does.
: _RTHP-LIVE-IDLE?  ( producer -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP RTHP-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP _RTHP.MAGIC @ _RTHP-MAGIC <> IF DROP 0 EXIT THEN
    DUP _RTHP.SIZE @ RTHP-SIZE <> IF DROP 0 EXIT THEN
    DUP _RTHP.SELF @ OVER <> IF DROP 0 EXIT THEN
    _RTHP.PHASE @ _RTHP-PH-LIVE = ;

: RTHP-STEP
  ( cols rows generation budget producer -- scb-status more? output-needed? )
    _RTPROF-PH-OTHER _RTPROF-MARK
    _RTHP-S-P ! DROP _RTHP-S-GEN ! _RTHP-S-ROWS ! _RTHP-S-COLS !
    _RTHP-S-P @ _RTHP-LIVE-IDLE? 0= IF
        _RTHP-S-P @ RTHP-VALID? 0= IF SCB-S-INVALID 0 0 EXIT THEN
    THEN
    _RTHP-S-COLS @ _RTHP-S-ROWS @ _RTHP-S-GEN @ _RTHP-S-P @
        _RTHP-CALL-SURFACE? 0= IF
        SCB-S-INVALID _RTHP-S-P @ _RTHP-FAULT-RESULT EXIT
    THEN
    _RTHP-S-P @ _RTHP.PHASE @ _RTHP-PH-FAULT = IF
        _RTHP-S-P @ _RTHP.FAULT @ 0 0 EXIT
    THEN
    _RTHP-S-P @ _RTHP.PHASE @ _RTHP-PH-WAIT = IF
        _RTHP-S-COLS @ _RTHP-S-P @ _RTHP.COLS !
        _RTHP-S-ROWS @ _RTHP-S-P @ _RTHP.ROWS !
        _RTHP-S-GEN @ _RTHP-S-P @ _RTHP.PHYSICAL-GEN !
        SCR-DRAW-GENERATION@ _RTHP-S-P @ _RTHP.REFUSED-DRAW @ = IF
            SCB-S-OK 0 0 EXIT
        THEN
        _RTHP-S-P @ _RTHP-TRY-CANDIDATE
        IF
            DUP SCB-S-OK = IF DROP SCB-S-OK -1 0 EXIT THEN
            _RTHP-S-P @ _RTHP-FAULT-RESULT EXIT
        THEN
        DUP SCB-S-OK = IF DROP SCB-S-OK 0 0 EXIT THEN
        _RTHP-S-P @ _RTHP-FAULT-RESULT EXIT
    THEN
    _RTHP-S-P @ _RTHP.PHASE @ _RTHP-PH-OPENING = IF
        _RTHP-S-P @ _RTHP-STEP-OPENING EXIT
    THEN
    _RTHP-S-P @ _RTHP.PHASE @ _RTHP-PH-RESIZING = IF
        _RTHP-S-P @ _RTHP-STEP-RESIZING EXIT
    THEN
    _RTHP-S-P @ _RTHP.PHASE @ _RTHP-PH-READY-START = IF
        SCB-S-OK 0 -1 EXIT
    THEN
    _RTHP-S-P @ _RTHP.PHASE @ _RTHP-PH-START-SEALED = IF
        _RTHP-PH-READY-REVEAL _RTHP-PH-READY-START -1 _RTHP-S-P @
        _RTHP-STEP-SEALED EXIT
    THEN
    _RTHP-S-P @ _RTHP.PHASE @ _RTHP-PH-READY-REVEAL = IF
        SCB-S-OK 0 -1 EXIT
    THEN
    _RTHP-S-P @ _RTHP.PHASE @ _RTHP-PH-REVEAL-SEALED = IF
        _RTHP-PH-LIVE _RTHP-PH-READY-REVEAL 0 _RTHP-S-P @
        _RTHP-STEP-SEALED EXIT
    THEN
    _RTHP-S-P @ _RTHP.PHASE @ _RTHP-PH-READY-DELTA = IF
        SCB-S-OK 0 -1 EXIT
    THEN
    _RTHP-S-P @ _RTHP.PHASE @ _RTHP-PH-DELTA-SEALED = IF
        _RTHP-PH-LIVE _RTHP-PH-READY-DELTA 0 _RTHP-S-P @
        _RTHP-STEP-SEALED EXIT
    THEN
    _RTHP-S-P @ _RTHP.PHASE @ _RTHP-PH-LIVE = IF
        _RTHP-S-P @ _RTHP-LANE-STEP EXIT
    THEN
    _RTHP-S-P @ _RTHP.PHASE @ _RTHP-PH-READY-BLANK = IF
        SCB-S-OK 0 -1 EXIT
    THEN
    _RTHP-S-P @ _RTHP.PHASE @ _RTHP-PH-BLANK-SEALED = IF
        _RTHP-PH-READY-BLANK-REVEAL _RTHP-PH-READY-BLANK -1 _RTHP-S-P @
        _RTHP-STEP-SEALED EXIT
    THEN
    _RTHP-S-P @ _RTHP.PHASE @ _RTHP-PH-READY-BLANK-REVEAL = IF
        SCB-S-OK 0 -1 EXIT
    THEN
    _RTHP-S-P @ _RTHP.PHASE @ _RTHP-PH-BLANK-REVEAL-SEALED = IF
        _RTHP-PH-BLANK _RTHP-PH-READY-BLANK-REVEAL 0 _RTHP-S-P @
        _RTHP-STEP-SEALED EXIT
    THEN
    _RTHP-S-P @ _RTHP.PHASE @ _RTHP-PH-BLANK = IF
        _RTHP-S-P @ _RTHP-LANE-STEP EXIT
    THEN
    SCB-S-INVALID _RTHP-S-P @ _RTHP-FAULT-RESULT ;

\ =====================================================================
\  Final mutation-safe emission and PREPARE
\ =====================================================================

VARIABLE _RTHP-X-P
VARIABLE _RTHP-X-I-ITEM
VARIABLE _RTHP-X-I-REGION
VARIABLE _RTHP-X-I-A
VARIABLE _RTHP-X-I-U
VARIABLE _RTHP-X-I-NEXT
VARIABLE _RTHP-X-I-UNIT-BYTES
VARIABLE _RTHP-X-I-UNIT-ALIGNED
VARIABLE _RTHP-X-I-UNIT-MAX
VARIABLE _RTHP-X-I-FORMATTED
VARIABLE _RTHP-X-I-FORMATTED-MAX
VARIABLE _RTHP-X-I-READOUTS
VARIABLE _RTHP-X-I-METERS
VARIABLE _RTHP-X-I-STATUSES
VARIABLE _RTHP-X-I-PLOTS
VARIABLE _RTHP-X-I-POLYLINES
VARIABLE _RTHP-X-I-PATH-POINTS
VARIABLE _RTHP-X-I-PATH-MAX
VARIABLE _RTHP-X-I-LAST
VARIABLE _RTHP-X-I-REGION-LAST

\ The candidate was admitted on its own, so its admission summary describes
\ it.  A candidate built for Desk's shell has no admission of its own: the
\ shell's batch, which holds its items, is admitted before anything is sent.
: _RTHP-X-ADMITTED?  ( -- flag )  _RTHP-X-P @ _RTHP.SHELL-BUILT @ 0= ;

: _RTHP-X-I-CLEAR  ( -- )
    0 _RTHP-X-I-ITEM ! 0 _RTHP-X-I-REGION !
    0 _RTHP-X-I-A ! 0 _RTHP-X-I-U ! 0 _RTHP-X-I-NEXT !
    0 _RTHP-X-I-UNIT-BYTES ! 0 _RTHP-X-I-UNIT-ALIGNED !
    0 _RTHP-X-I-UNIT-MAX ! 0 _RTHP-X-I-FORMATTED !
    0 _RTHP-X-I-FORMATTED-MAX ! 0 _RTHP-X-I-READOUTS !
    0 _RTHP-X-I-METERS ! 0 _RTHP-X-I-STATUSES !
    0 _RTHP-X-I-PLOTS ! 0 _RTHP-X-I-POLYLINES !
    0 _RTHP-X-I-PATH-POINTS ! 0 _RTHP-X-I-PATH-MAX !
    0 _RTHP-X-I-LAST ! 0 _RTHP-X-I-REGION-LAST ! ;

: _RTHP-X-I-UNIT-AUTHORITY?  ( -- flag )
    _RTHP-X-I-ITEM @ _RTE-INSTRUMENT.UNIT-A @ _RTHP-X-I-A !
    _RTHP-X-I-ITEM @ _RTE-INSTRUMENT.UNIT-U @ DUP _RTHP-X-I-U !
    0= IF _RTHP-X-I-A @ 0= EXIT THEN
    _RTHP-X-I-A @ 0= IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.INSTRUMENT-UNITS-A @
    _RTHP-X-I-UNIT-BYTES @ _RTHP-U+?
        0= IF DROP 0 EXIT THEN
    _RTHP-X-I-A @ <> IF 0 EXIT THEN
    _RTHP-X-I-A @ _RTHP-X-I-U @ MSPAN-NONWRAPPING? ;

: _RTHP-X-I-ADD-UNIT?  ( -- flag )
    _RTHP-X-I-UNIT-BYTES @ _RTHP-X-I-U @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-X-P @ _RTHP.INSTRUMENT-UNITS-USED @ U> IF
        DROP 0 EXIT
    THEN _RTHP-X-I-UNIT-BYTES !
    _RTHP-X-I-U @ _RTHP-ALIGN8? 0= IF DROP 0 EXIT THEN
    _RTHP-X-I-UNIT-ALIGNED @ SWAP _RTHP-U32+?
        0= IF DROP 0 EXIT THEN _RTHP-X-I-UNIT-ALIGNED !
    \ A line's points are not unit text.
    _RTHP-X-I-ITEM @ _RTE-INSTRUMENT.KIND @ RTE-INSTRUMENT-POLYLINE = IF
        -1 EXIT
    THEN
    _RTHP-X-I-U @ _RTHP-X-I-UNIT-MAX @ MAX
        _RTHP-X-I-UNIT-MAX ! -1 ;

: _RTHP-X-I-ADD-FORMATTED?  ( -- flag )
    _RTHP-X-I-ITEM @ _RTE-INSTRUMENT.FORMATTED-U @
        DUP _RTHP-X-I-NEXT !
    _RTHP-X-I-FORMATTED @ SWAP _RTHP-U32+?
        0= IF DROP 0 EXIT THEN _RTHP-X-I-FORMATTED !
    _RTHP-X-I-NEXT @ _RTHP-X-I-FORMATTED-MAX @ MAX
        _RTHP-X-I-FORMATTED-MAX ! -1 ;

: _RTHP-X-I-KIND?  ( -- flag )
    _RTHP-X-I-ITEM @ _RTE-INSTRUMENT.KIND @
    DUP RTE-INSTRUMENT-READOUT = IF
        DROP _RTHP-X-I-READOUTS @ 1 _RTHP-U32+?
            0= IF DROP 0 EXIT THEN _RTHP-X-I-READOUTS ! -1 EXIT
    THEN
    DUP RTE-INSTRUMENT-METER = IF
        DROP _RTHP-X-I-METERS @ 1 _RTHP-U32+?
            0= IF DROP 0 EXIT THEN _RTHP-X-I-METERS ! -1 EXIT
    THEN
    DUP RTE-INSTRUMENT-WAVEFORM = IF DROP -1 EXIT THEN
    DUP RTE-INSTRUMENT-PLOT = IF
        DROP _RTHP-X-I-PLOTS @ 1 _RTHP-U32+?
            0= IF DROP 0 EXIT THEN _RTHP-X-I-PLOTS ! -1 EXIT
    THEN
    DUP RTE-INSTRUMENT-POLYLINE = IF
        DROP _RTHP-X-I-POLYLINES @ 1 _RTHP-U32+?
            0= IF DROP 0 EXIT THEN _RTHP-X-I-POLYLINES !
        _RTHP-X-I-U @ 4 RSHIFT
        DUP _RTHP-X-I-PATH-MAX @ MAX _RTHP-X-I-PATH-MAX !
        _RTHP-X-I-PATH-POINTS @ SWAP _RTHP-U32+?
            0= IF DROP 0 EXIT THEN _RTHP-X-I-PATH-POINTS ! -1 EXIT
    THEN
    RTE-INSTRUMENT-STATUS <> IF 0 EXIT THEN
    _RTHP-X-I-STATUSES @ 1 _RTHP-U32+?
        0= IF DROP 0 EXIT THEN _RTHP-X-I-STATUSES ! -1 ;

: _RTHP-X-I-REGIONS?  ( -- flag )
    0 _RTHP-X-I-REGION-LAST !
    _RTHP-X-P @ _RTHP.INSTRUMENT-REGION-COUNT @ 0 ?DO
        _RTHP-X-P @ _RTHP.INSTRUMENT-REGIONS-A @
            I RTE-INSTRUMENT-REGION-SIZE * + _RTHP-X-I-REGION !
        _RTHP-X-P @ _RTHP.REGION @ I 1+ _RTHP-U+?
            0= IF DROP 0 UNLOOP EXIT THEN
        _RTHP-X-I-REGION @ _RTE-IR.ID @ <> IF 0 UNLOOP EXIT THEN
        _RTHP-X-I-REGION @ _RTE-IR.ID @ _RTHP-X-I-REGION-LAST !
    LOOP
    _RTHP-X-I-REGION-LAST @
        _RTHP-X-P @ _RTHP.INSTRUMENT-LAST-REGION @ = ;

: _RTHP-X-I-ITEMS?  ( -- flag )
    0 _RTHP-X-I-LAST !
    _RTHP-X-P @ _RTHP.INSTRUMENT-COUNT @ 0 ?DO
        _RTHP-X-P @ _RTHP.INSTRUMENTS-A @ I RTE-INSTRUMENT-SIZE * +
            _RTHP-X-I-ITEM !
        _RTHP-X-I-UNIT-AUTHORITY? 0= IF 0 UNLOOP EXIT THEN
        _RTHP-X-I-ADD-UNIT? 0= IF 0 UNLOOP EXIT THEN
        _RTHP-X-I-ADD-FORMATTED? 0= IF 0 UNLOOP EXIT THEN
        _RTHP-X-I-KIND? 0= IF 0 UNLOOP EXIT THEN
        _RTHP-X-P @ _RTHP.FIRST-OBJECT @
        _RTHP-X-P @ _RTHP.CONTROL-COUNT @ _RTHP-U+?
            0= IF DROP 0 UNLOOP EXIT THEN
        I _RTHP-U+? 0= IF DROP 0 UNLOOP EXIT THEN
        _RTHP-X-I-ITEM @ _RTE-INSTRUMENT.ID @ <> IF 0 UNLOOP EXIT THEN
        _RTHP-X-I-ITEM @ _RTE-INSTRUMENT.ID @ _RTHP-X-I-LAST !
    LOOP
    -1 ;

: _RTHP-X-INSTRUMENT-AGGREGATES?  ( -- flag )
    _RTHP-X-I-CLEAR
    _RTHP-X-I-REGIONS? 0= IF 0 EXIT THEN
    _RTHP-X-I-ITEMS? 0= IF 0 EXIT THEN
    _RTHP-X-I-UNIT-BYTES @
        _RTHP-X-P @ _RTHP.INSTRUMENT-UNITS-USED @ =
    _RTHP-X-I-LAST @ _RTHP-X-P @ _RTHP.INSTRUMENT-LAST @ = AND
    _RTHP-X-ADMITTED? 0= IF EXIT THEN
    _RTHP-X-I-UNIT-BYTES @ _RTHP-X-P @ _RTHP.ADMISSION
        _RTE-HA.INSTRUMENT-UNIT-BYTES @ = AND
    _RTHP-X-I-UNIT-ALIGNED @ _RTHP-X-P @ _RTHP.ADMISSION
        _RTE-HA.INSTRUMENT-UNIT-ALIGNED @ = AND
    _RTHP-X-I-UNIT-MAX @ _RTHP-X-P @ _RTHP.ADMISSION
        _RTE-HA.INSTRUMENT-UNIT-MAX @ = AND
    _RTHP-X-I-FORMATTED @ _RTHP-X-P @ _RTHP.ADMISSION
        _RTE-HA.INSTRUMENT-FORMATTED-BYTES @ = AND
    _RTHP-X-I-FORMATTED-MAX @ _RTHP-X-P @ _RTHP.ADMISSION
        _RTE-HA.INSTRUMENT-FORMATTED-MAX @ = AND
    _RTHP-X-I-READOUTS @ _RTHP-X-P @ _RTHP.ADMISSION
        _RTE-HA.READOUT-COUNT @ = AND
    _RTHP-X-I-METERS @ _RTHP-X-P @ _RTHP.ADMISSION
        _RTE-HA.METER-COUNT @ = AND
    _RTHP-X-I-STATUSES @ _RTHP-X-P @ _RTHP.ADMISSION
        _RTE-HA.STATUS-COUNT @ = AND
    _RTHP-X-I-PLOTS @ _RTHP-X-P @ _RTHP.ADMISSION
        _RTE-HA.PLOT-COUNT @ = AND
    _RTHP-X-I-POLYLINES @ _RTHP-X-P @ _RTHP.ADMISSION
        _RTE-HA.POLYLINE-COUNT @ = AND
    _RTHP-X-I-PATH-POINTS @ _RTHP-X-P @ _RTHP.ADMISSION
        _RTE-HA.PATH-POINTS @ = AND
    _RTHP-X-I-PATH-MAX @ _RTHP-X-P @ _RTHP.ADMISSION
        _RTE-HA.PATH-POINTS-MAX @ = AND
    _RTHP-X-I-LAST @ _RTHP-X-P @ _RTHP.ADMISSION
        _RTE-HA.INSTRUMENT-LAST @ = AND ;

\ The candidate's controls of one kind: item views, which need
\ CONTROL-ITEMS, or documents, which need CONTROL-DOCUMENTS.
: _RTHP-X-KIND-COUNT  ( rte-kind -- count )
    0 SWAP
    _RTHP-X-P @ _RTHP.CONTROL-COUNT @ 0 ?DO
        _RTHP-X-P @ _RTHP.CONTROLS-A @ I RTE-CONTROL-SIZE * +
            _RTE-CONTROL.KIND @ OVER = IF SWAP 1+ SWAP THEN
    LOOP DROP ;

: _RTHP-INSTRUMENT-FIXED?  ( -- flag )
    _RTHP-X-P @ _RTHP.INSTRUMENT-COUNT @
        _RTHP-X-P @ _RTHP.MAX-INSTRUMENTS @ U> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.INSTRUMENT-REGION-COUNT @
        _RTHP-X-P @ _RTHP.MAX-INSTRUMENT-REGIONS @ U> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.INSTRUMENT-UNITS-USED @
        _RTHP-X-P @ _RTHP.INSTRUMENT-UNITS-U @ U> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.INSTRUMENT-CLAIM-COUNT @
        _RTHP-X-P @ _RTHP.INSTRUMENT-COUNT @ U> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.BASE-CLAIMS-USED @ DUP RUCL-CLAIM-SIZE MOD IF
        DROP 0 EXIT
    THEN
    _RTHP-X-P @ _RTHP.INSTRUMENT-CLAIM-COUNT @ RUCL-CLAIM-SIZE
        _RTHP-U32*? 0= IF 2DROP 0 EXIT THEN
    _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-X-P @ _RTHP.STATIC-BASE-CLAIMS @ <> IF 0 EXIT THEN

    _RTHP-X-ADMITTED? IF
        _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.INSTRUMENT-REGION-COUNT @
            _RTHP-X-P @ _RTHP.INSTRUMENT-REGION-COUNT @ <> IF 0 EXIT THEN
        _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.INSTRUMENT-COUNT @
            _RTHP-X-P @ _RTHP.INSTRUMENT-COUNT @ <> IF 0 EXIT THEN
        _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.INSTRUMENT-UNIT-BYTES @
            _RTHP-X-P @ _RTHP.INSTRUMENT-UNITS-USED @ <> IF 0 EXIT THEN
        _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.INSTRUMENT-LAST @
            _RTHP-X-P @ _RTHP.INSTRUMENT-LAST @ <> IF 0 EXIT THEN
    THEN

    _RTHP-X-P @ _RTHP.INSTRUMENT-COUNT @ 0= IF
        _RTHP-X-P @ _RTHP.INSTRUMENT-REGION-COUNT @
        _RTHP-X-P @ _RTHP.INSTRUMENT-UNITS-USED @ OR
        _RTHP-X-P @ _RTHP.INSTRUMENT-LAST-REGION @ OR
        _RTHP-X-P @ _RTHP.INSTRUMENT-LAST @ OR
        _RTHP-X-P @ _RTHP.INSTRUMENT-CLAIM-COUNT @ OR IF 0 EXIT THEN
        _RTHP-X-ADMITTED? IF
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.READOUT-COUNT @
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.METER-COUNT @ OR
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.STATUS-COUNT @ OR
            _RTHP-X-P @ _RTHP.ADMISSION
                _RTE-HA.INSTRUMENT-UNIT-ALIGNED @ OR
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.INSTRUMENT-UNIT-MAX @ OR
            _RTHP-X-P @ _RTHP.ADMISSION
                _RTE-HA.INSTRUMENT-FORMATTED-BYTES @ OR
            _RTHP-X-P @ _RTHP.ADMISSION
                _RTE-HA.INSTRUMENT-FORMATTED-MAX @ OR
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.PLOT-COUNT @ OR
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.POLYLINE-COUNT @ OR
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.PATH-POINTS @ OR
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.PATH-POINTS-MAX @ OR IF 0 EXIT THEN
        THEN
        _RTHP-X-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.OWNER @
        _RTHP-X-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.GENERATION @ OR
        _RTHP-X-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.SURFACE-COLS @ OR
        _RTHP-X-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.SURFACE-ROWS @ OR
        _RTHP-X-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.REGIONS-A @ OR
        _RTHP-X-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.REGIONS-U @ OR
        _RTHP-X-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.ITEMS-A @ OR
        _RTHP-X-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.ITEMS-U @ OR
        _RTHP-X-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.RESERVED @ OR IF
            0 EXIT
        THEN
        _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.INSTRUMENT-PLAN @
        _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.INSTRUMENT-BYTES-A @ OR
        _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.INSTRUMENT-BYTES-U @ OR 0=
        EXIT
    THEN

    _RTHP-X-P @ _RTHP.INSTRUMENT-REGION-COUNT @ 0= IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.REGION @
    _RTHP-X-P @ _RTHP.INSTRUMENT-REGION-COUNT @ _RTHP-U+?
        0= IF DROP 0 EXIT THEN
    _RTHP-X-P @ _RTHP.INSTRUMENT-LAST-REGION @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.FIRST-OBJECT @
    _RTHP-X-P @ _RTHP.CONTROL-COUNT @ _RTHP-U+?
        0= IF DROP 0 EXIT THEN
    _RTHP-X-P @ _RTHP.INSTRUMENT-COUNT @ 1- _RTHP-U+?
        0= IF DROP 0 EXIT THEN
    _RTHP-X-P @ _RTHP.INSTRUMENT-LAST @ <> IF 0 EXIT THEN

    _RTHP-X-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.OWNER @
        _RTHP-X-P @ _RTHP.OWNER @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.GENERATION @
        _RTHP-X-P @ _RTHP.OWNER-GEN @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.SURFACE-COLS @
        _RTHP-X-P @ _RTHP.COLS @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.SURFACE-ROWS @
        _RTHP-X-P @ _RTHP.ROWS @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.REGIONS-A @
        _RTHP-X-P @ _RTHP.INSTRUMENT-REGIONS-A @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.REGIONS-U @
        _RTHP-X-P @ _RTHP.INSTRUMENT-REGION-COUNT @
            RTE-INSTRUMENT-REGION-SIZE * <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.ITEMS-A @
        _RTHP-X-P @ _RTHP.INSTRUMENTS-A @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.ITEMS-U @
        _RTHP-X-P @ _RTHP.INSTRUMENT-COUNT @ RTE-INSTRUMENT-SIZE * <>
        IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.INSTRUMENT-PLAN _RTE-IP.RESERVED @ IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.INSTRUMENT-PLAN @
        _RTHP-X-P @ _RTHP.INSTRUMENT-PLAN <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.INSTRUMENT-UNITS-USED @ IF
        _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.INSTRUMENT-BYTES-A @
            _RTHP-X-P @ _RTHP.INSTRUMENT-UNITS-A @ <> IF 0 EXIT THEN
    ELSE
        _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.INSTRUMENT-BYTES-A @ IF
            0 EXIT
        THEN
    THEN
    _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.INSTRUMENT-BYTES-U @
        _RTHP-X-P @ _RTHP.INSTRUMENT-UNITS-USED @ <> IF 0 EXIT THEN
    _RTHP-X-INSTRUMENT-AGGREGATES? ;


VARIABLE _RTHP-SX-P
VARIABLE _RTHP-SX-ITEM
VARIABLE _RTHP-SX-TEXT
VARIABLE _RTHP-SX-ALIGNED
VARIABLE _RTHP-SX-MAX
VARIABLE _RTHP-SX-LAST
VARIABLE _RTHP-SX-CLAIM
VARIABLE _RTHP-SX-U
VARIABLE _RTHP-SX-IMAGES
VARIABLE _RTHP-SX-NEXT
VARIABLE _RTHP-SX-CORR
VARIABLE _RTHP-SX-ROW
VARIABLE _RTHP-SX-COL
VARIABLE _RTHP-SX-ROW-END
VARIABLE _RTHP-SX-COL-END

: _RTHP-SX-SPAN? ( address bytes -- flag )
    DUP 0= IF DROP 0= EXIT THEN
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP _RTHP-SX-U !
    _RTHP-SX-P @ _RTHP.STATIC-TEXT-A @ _RTHP-SX-TEXT @ +
        ROT <> IF DROP 0 EXIT THEN
    _RTHP-SX-TEXT @ SWAP _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    DUP _RTHP-SX-P @ _RTHP.STATIC-TEXT-USED @ U> IF DROP 0 EXIT THEN
    _RTHP-SX-TEXT ! -1 ;

\ The part of the valid static ITEM shown: its clip, or all of it.  Its
\ origin fits 32 signed bits and its clip lies inside it.
: _RTHP-SX-SHOWN  ( -- )
    _RTHP-SX-ITEM @ _RTE-STATIC.ROW @ _RTHP-SX-ROW !
    _RTHP-SX-ITEM @ _RTE-STATIC.COL @ _RTHP-SX-COL !
    _RTHP-SX-ITEM @ _RTE-STATIC-UNCLIPPED? IF
        _RTHP-SX-ITEM @ _RTE-STATIC.HEIGHT @ _RTHP-SX-ROW @ + _RTHP-SX-ROW-END !
        _RTHP-SX-ITEM @ _RTE-STATIC.WIDTH @ _RTHP-SX-COL @ + _RTHP-SX-COL-END !
        EXIT
    THEN
    _RTHP-SX-ITEM @ _RTE-STATIC.CLIP-Y @ _RTHP-SX-ROW +!
    _RTHP-SX-ITEM @ _RTE-STATIC.CLIP-X @ _RTHP-SX-COL +!
    _RTHP-SX-ITEM @ _RTE-STATIC.CLIP-ROWS @ _RTHP-SX-ROW @ + _RTHP-SX-ROW-END !
    _RTHP-SX-ITEM @ _RTE-STATIC.CLIP-COLS @ _RTHP-SX-COL @ + _RTHP-SX-COL-END ! ;

\ Whether static I is a figure: a picture whose shown part a claim made
\ before the statics, by its own root, holds.  It takes no claim of its
\ own.
: _RTHP-SX-IN-ROOT?  ( i -- flag )
    _RTHP-SX-ITEM @ _RTE-STATIC.KIND @ RTE-STATIC-IMAGE <> IF DROP 0 EXIT THEN
    _RTHP-STATIC-CORR-SIZE * _RTHP-SX-P @ _RTHP.STATIC-CORR-A @ + _RTHP-SX-CORR !
    _RTHP-SX-P @ _RTHP.STATIC-BASE-CLAIMS @ RUCL-CLAIM-SIZE / 0 ?DO
        _RTHP-SX-P @ _RTHP.CLAIMS-A @ I RUCL-CLAIM-SIZE * + _RTHP-SX-CLAIM !
        _RTHP-SX-CLAIM @ RUCL-CLAIM-ATTACHMENT@ _RTHP-SX-CORR @ @ =
        _RTHP-SX-CLAIM @ RUCL-CLAIM-SOURCE-INDEX@ _RTHP-SX-CORR @ 8 + @ = AND
        _RTHP-SX-CLAIM @ RUCL-CLAIM-ROW0@ _RTHP-SX-ROW @ > 0= AND
        _RTHP-SX-CLAIM @ RUCL-CLAIM-COL0@ _RTHP-SX-COL @ > 0= AND
        _RTHP-SX-CLAIM @ RUCL-CLAIM-ROW1@ _RTHP-SX-ROW-END @ < 0= AND
        _RTHP-SX-CLAIM @ RUCL-CLAIM-COL1@ _RTHP-SX-COL-END @ < 0= AND
            IF -1 UNLOOP EXIT THEN
    LOOP 0 ;

\ Any other static takes the next claim after the base, which is exactly
\ the part of it shown.
: _RTHP-SX-OWN-CLAIM?  ( -- flag )
    _RTHP-SX-NEXT @ RUCL-CLAIM-SIZE _RTHP-U32+? 0= IF DROP 0 EXIT THEN
        _RTHP-SX-P @ _RTHP.CLAIMS-USED @ U> IF 0 EXIT THEN
    _RTHP-SX-P @ _RTHP.CLAIMS-A @ _RTHP-SX-NEXT @ + _RTHP-SX-CLAIM !
    _RTHP-SX-CLAIM @ RUCL-CLAIM-ROW0@ _RTHP-SX-ROW @ =
    _RTHP-SX-CLAIM @ RUCL-CLAIM-COL0@ _RTHP-SX-COL @ = AND
    _RTHP-SX-CLAIM @ RUCL-CLAIM-ROW1@ _RTHP-SX-ROW-END @ = AND
    _RTHP-SX-CLAIM @ RUCL-CLAIM-COL1@ _RTHP-SX-COL-END @ = AND
        0= IF 0 EXIT THEN
    RUCL-CLAIM-SIZE _RTHP-SX-NEXT +! -1 ;

: _RTHP-STATICS-FIXED? ( producer -- flag )
    _RTHP-SX-P !
    _RTHP-SX-P @ _RTHP.STATIC-COUNT @
        _RTHP-SX-P @ _RTHP.MAX-STATICS @ U> IF 0 EXIT THEN
    _RTHP-SX-P @ _RTHP.STATIC-TEXT-USED @
        _RTHP-SX-P @ _RTHP.STATIC-TEXT-U @ U> IF 0 EXIT THEN
    _RTHP-SX-P @ _RTHP.STATIC-BASE-CLAIMS @ DUP _RTHP-SX-NEXT !
        DUP RUCL-CLAIM-SIZE MOD IF DROP 0 EXIT THEN
        _RTHP-SX-P @ _RTHP.CLAIMS-USED @ U> IF 0 EXIT THEN
    _RTHP-SX-P @ _RTHP.STATICS-A @
    _RTHP-SX-P @ _RTHP.STATIC-COUNT @ RTE-STATIC-SIZE *
    _RTHP-SX-P @ _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    _RTHP-SX-P @ _RTHP.STATIC-TEXT-A @
    _RTHP-SX-P @ _RTHP.STATIC-TEXT-USED @
    _RTHP-SX-P @ _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    0 _RTHP-SX-TEXT ! 0 _RTHP-SX-ALIGNED ! 0 _RTHP-SX-MAX ! 0 _RTHP-SX-LAST !
    0 _RTHP-SX-IMAGES !
    _RTHP-SX-P @ _RTHP.STATIC-COUNT @ 0 ?DO
        _RTHP-SX-P @ _RTHP.STATICS-A @ I RTE-STATIC-SIZE * + _RTHP-SX-ITEM !
        _RTHP-SX-ITEM @ _RTE-STATIC.OWNER @ _RTHP-SX-P @ _RTHP.OWNER @ <>
        _RTHP-SX-ITEM @ _RTE-STATIC.GENERATION @ _RTHP-SX-P @ _RTHP.OWNER-GEN @ <> OR
        _RTHP-SX-ITEM @ _RTE-STATIC.REGION @ _RTHP-SX-P @ _RTHP.REGION @ <> OR
        _RTHP-SX-ITEM @ _RTE-STATIC.ROOT-HEIGHT @ _RTHP-SX-P @ _RTHP.ROWS @ <> OR
        _RTHP-SX-ITEM @ _RTE-STATIC.ROOT-WIDTH @ _RTHP-SX-P @ _RTHP.COLS @ <> OR
            IF 0 UNLOOP EXIT THEN
        _RTHP-SX-P @ _RTHP.FIRST-OBJECT @
        _RTHP-SX-P @ _RTHP.CONTROL-COUNT @ _RTHP-U+?
            0= IF DROP 0 UNLOOP EXIT THEN
        _RTHP-SX-P @ _RTHP.INSTRUMENT-COUNT @ _RTHP-U+?
            0= IF DROP 0 UNLOOP EXIT THEN
        I _RTHP-U+? 0= IF DROP 0 UNLOOP EXIT THEN
        DUP _RTHP-SX-LAST ! _RTHP-SX-ITEM @ _RTE-STATIC.ID @ <>
            IF 0 UNLOOP EXIT THEN
        _RTHP-SX-ITEM @ _RTE-STATIC.LABEL-A @
        _RTHP-SX-ITEM @ _RTE-STATIC.LABEL-U @ _RTHP-SX-SPAN? 0=
            IF 0 UNLOOP EXIT THEN
        _RTHP-SX-ITEM @ _RTE-STATIC.VALUE-A @
        _RTHP-SX-ITEM @ _RTE-STATIC.VALUE-U @ _RTHP-SX-SPAN? 0=
            IF 0 UNLOOP EXIT THEN
        _RTHP-SX-ITEM @ RTE-STATIC-VALID? 0= IF 0 UNLOOP EXIT THEN
        _RTHP-SX-ITEM @ _RTE-STATIC.VISIBLE @ -1 <> IF 0 UNLOOP EXIT THEN
        _RTHP-SX-ITEM @ _RTE-STATIC.KIND @ RTE-STATIC-IMAGE = IF
            1 _RTHP-SX-IMAGES +!
        THEN
        \ The part shown lies on the surface; the rest may reach off it.
        _RTHP-SX-SHOWN
        _RTHP-SX-ROW @ 0< _RTHP-SX-COL @ 0< OR IF 0 UNLOOP EXIT THEN
        _RTHP-SX-ROW-END @ _RTHP-SX-P @ _RTHP.ROWS @ > IF 0 UNLOOP EXIT THEN
        _RTHP-SX-COL-END @ _RTHP-SX-P @ _RTHP.COLS @ > IF 0 UNLOOP EXIT THEN
        I _RTHP-SX-IN-ROOT? 0= IF
            _RTHP-SX-OWN-CLAIM? 0= IF 0 UNLOOP EXIT THEN
        THEN
        _RTHP-SX-ITEM @ _RTE-STATIC.LABEL-U @
        _RTHP-SX-ITEM @ _RTE-STATIC.VALUE-U @ + DUP
            _RTHP-SX-MAX @ MAX _RTHP-SX-MAX !
        _RTHP-ALIGN8? 0= IF DROP 0 UNLOOP EXIT THEN
        _RTHP-SX-ALIGNED @ _RTHP-U32+? 0= IF DROP 0 UNLOOP EXIT THEN
        _RTHP-SX-ALIGNED !
    LOOP
    _RTHP-SX-NEXT @ _RTHP-SX-P @ _RTHP.CLAIMS-USED @ <> IF 0 EXIT THEN
    _RTHP-SX-TEXT @ _RTHP-SX-P @ _RTHP.STATIC-TEXT-USED @ <>
    _RTHP-SX-LAST @ _RTHP-SX-P @ _RTHP.STATIC-LAST @ <> OR IF 0 EXIT THEN
    _RTHP-SX-P @ _RTHP.SHELL-BUILT @ 0= IF
        _RTHP-SX-P @ _RTHP.ADMISSION _RTE-HA.STATIC-COUNT @
            _RTHP-SX-P @ _RTHP.STATIC-COUNT @ <>
        _RTHP-SX-P @ _RTHP.ADMISSION _RTE-HA.STATIC-TEXT @ _RTHP-SX-TEXT @ <> OR
        _RTHP-SX-P @ _RTHP.ADMISSION _RTE-HA.STATIC-ALIGNED @ _RTHP-SX-ALIGNED @ <> OR
        _RTHP-SX-P @ _RTHP.ADMISSION _RTE-HA.STATIC-MAX @ _RTHP-SX-MAX @ <> OR
        _RTHP-SX-P @ _RTHP.ADMISSION _RTE-HA.STATIC-LAST @ _RTHP-SX-LAST @ <> OR
        _RTHP-SX-P @ _RTHP.ADMISSION _RTE-HA.STATIC-OPS @
            _RTHP-SX-P @ _RTHP.STATIC-COUNT @ <> OR
        _RTHP-SX-P @ _RTHP.ADMISSION _RTE-HA.STATIC-IMAGES @
            _RTHP-SX-IMAGES @ <> OR IF 0 EXIT THEN
        \ The neutral copy holds each status field's record and text; the
        \ provider counts what a picture takes.
        _RTHP-SX-P @ _RTHP.STATIC-COUNT @ _RTHP-SX-IMAGES @ - RTE-STATIC-SIZE *
            _RTHP-SX-ALIGNED @ _RTHP-U32+? 0= IF DROP 0 EXIT THEN
        _RTHP-SX-P @ _RTHP.ADMISSION _RTE-HA.STATIC-COPY @ <> IF 0 EXIT THEN
    THEN
    _RTHP-SX-P @ _RTHP.STATIC-COUNT @ 0= IF
        RTE-STATIC-PLAN-SIZE 8 / 0 ?DO
            _RTHP-SX-P @ _RTHP.STATIC-PLAN I 8 * + @ IF 0 UNLOOP EXIT THEN
        LOOP
        _RTHP-SX-P @ _RTHP.HYBRID _RTE-HP.STATIC-PLAN @
        _RTHP-SX-P @ _RTHP.HYBRID _RTE-HP.STATIC-BYTES-A @ OR
        _RTHP-SX-P @ _RTHP.HYBRID _RTE-HP.STATIC-BYTES-U @ OR 0= EXIT
    THEN
    _RTHP-SX-P @ _RTHP.STATIC-PLAN _RTE-SP.OWNER @ _RTHP-SX-P @ _RTHP.OWNER @ <>
    _RTHP-SX-P @ _RTHP.STATIC-PLAN _RTE-SP.GENERATION @ _RTHP-SX-P @ _RTHP.OWNER-GEN @ <> OR
    _RTHP-SX-P @ _RTHP.STATIC-PLAN _RTE-SP.SURFACE-COLS @ _RTHP-SX-P @ _RTHP.COLS @ <> OR
    _RTHP-SX-P @ _RTHP.STATIC-PLAN _RTE-SP.SURFACE-ROWS @ _RTHP-SX-P @ _RTHP.ROWS @ <> OR
    _RTHP-SX-P @ _RTHP.STATIC-PLAN _RTE-SP.REGION-ID @ _RTHP-SX-P @ _RTHP.REGION @ <> OR
    _RTHP-SX-P @ _RTHP.STATIC-PLAN _RTE-SP.REGION-COLS @ _RTHP-SX-P @ _RTHP.COLS @ <> OR
    _RTHP-SX-P @ _RTHP.STATIC-PLAN _RTE-SP.REGION-ROWS @ _RTHP-SX-P @ _RTHP.ROWS @ <> OR
    _RTHP-SX-P @ _RTHP.STATIC-PLAN _RTE-SP.REGION-FLAGS @ RTE-REGION-VISIBLE <> OR
    _RTHP-SX-P @ _RTHP.STATIC-PLAN _RTE-SP.ITEMS-A @ _RTHP-SX-P @ _RTHP.STATICS-A @ <> OR
    _RTHP-SX-P @ _RTHP.STATIC-PLAN _RTE-SP.ITEMS-U @
        _RTHP-SX-P @ _RTHP.STATIC-COUNT @ RTE-STATIC-SIZE * <> OR IF 0 EXIT THEN
    _RTHP-SX-P @ _RTHP.STATIC-PLAN _RTE-SP.REGION-X @
    _RTHP-SX-P @ _RTHP.STATIC-PLAN _RTE-SP.REGION-Y @ OR
    _RTHP-SX-P @ _RTHP.STATIC-PLAN _RTE-SP.CLIP-X @ OR
    _RTHP-SX-P @ _RTHP.STATIC-PLAN _RTE-SP.CLIP-Y @ OR
    _RTHP-SX-P @ _RTHP.STATIC-PLAN _RTE-SP.CLIP-COLS @ OR
    _RTHP-SX-P @ _RTHP.STATIC-PLAN _RTE-SP.CLIP-ROWS @ OR
    _RTHP-SX-P @ _RTHP.STATIC-PLAN _RTE-SP.RESERVED @ OR IF 0 EXIT THEN
    _RTHP-SX-P @ _RTHP.STATIC-PLAN _RTE-SP.REGION-Z @
        _RTHP-SX-P @ _RTHP-BASE-Z-FIXED? 0= IF 0 EXIT THEN
    _RTHP-SX-P @ _RTHP.HYBRID _RTE-HP.STATIC-PLAN @
        _RTHP-SX-P @ _RTHP.STATIC-PLAN <> IF 0 EXIT THEN
    _RTHP-SX-P @ _RTHP.HYBRID _RTE-HP.STATIC-BYTES-U @ _RTHP-SX-TEXT @ <> IF 0 EXIT THEN
    _RTHP-SX-P @ _RTHP.HYBRID _RTE-HP.STATIC-BYTES-A @
    _RTHP-SX-TEXT @ IF _RTHP-SX-P @ _RTHP.STATIC-TEXT-A @ = ELSE 0= THEN ;

VARIABLE _RTHP-FX-P
VARIABLE _RTHP-FX-I
VARIABLE _RTHP-FX-C
VARIABLE _RTHP-FX-X
VARIABLE _RTHP-FX-CLAIM
VARIABLE _RTHP-FX-TEXT
VARIABLE _RTHP-FX-ITEMS
VARIABLE _RTHP-FX-UTF8

: _RTHP-FX-TEXT? ( address bytes -- flag )
    DUP 0= IF DROP 0= EXIT THEN
    OVER _RTHP-FX-P @ _RTHP.SOURCE-TEXT-A @ _RTHP-FX-TEXT @ + <> IF 2DROP 0 EXIT THEN
    _RTHP-FX-TEXT @ SWAP _RTHP-U32+? 0= IF 2DROP 0 EXIT THEN NIP
    DUP _RTHP-FX-P @ _RTHP.SOURCE-TEXT-USED @ U> IF DROP 0 EXIT THEN
    _RTHP-FX-TEXT ! -1 ;

: _RTHP-FIELDS-FIXED? ( producer -- flag )
    _RTHP-FX-P !
    _RTHP-FX-P @ _RTHP.FIELD-COUNT @ DUP
        _RTHP-FX-P @ _RTHP.MAX-FIELDS @ U> IF DROP 0 EXIT THEN
    _RTHP-FX-P @ _RTHP.CONTROL-COUNT @ U> IF 0 EXIT THEN
    _RTHP-FX-P @ _RTHP.FIELD-COUNT @ 0= IF
        _RTHP-FX-P @ _RTHP.FIELD-ITEMS @
        _RTHP-FX-P @ _RTHP.FIELD-UTF8 @ OR 0= EXIT
    THEN
    _RTHP-FX-P @ _RTHP.FIELD-BASE-CONTROLS @
    _RTHP-FX-P @ _RTHP.FIELD-COUNT @ _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-FX-P @ _RTHP.DIALOG-BASE-CONTROLS @ <> IF 0 EXIT THEN
    _RTHP-FX-P @ _RTHP.FIELD-BASE-CONTROLS @
    _RTHP-FX-P @ _RTHP.MENU-CONTROL-COUNT @
    _RTHP-FX-P @ _RTHP.COLLECTION-COUNT @ + <> IF 0 EXIT THEN
    _RTHP-FX-P @ _RTHP.FIELD-BASE-CLAIMS @ DUP RUCL-CLAIM-SIZE MOD IF DROP 0 EXIT THEN
    _RTHP-FX-P @ _RTHP.FIELD-COUNT @ RUCL-CLAIM-SIZE _RTHP-U32*?
        0= IF 2DROP 0 EXIT THEN
    _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-FX-P @ _RTHP.DIALOG-BASE-CLAIMS @ <> IF 0 EXIT THEN
    _RTHP-FX-P @ _RTHP.CONTROLS-A @
    _RTHP-FX-P @ _RTHP.CONTROL-COUNT @ RTE-CONTROL-SIZE *
        _RTHP-FX-P @ _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    _RTHP-FX-P @ _RTHP.CORR-A @
    _RTHP-FX-P @ _RTHP.CONTROL-COUNT @ RUCP-CORRELATION-SIZE *
        _RTHP-FX-P @ _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    _RTHP-FX-P @ _RTHP.CLAIMS-A @ _RTHP-FX-P @ _RTHP.BASE-CLAIMS-USED @
        _RTHP-FX-P @ _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    _RTHP-FX-P @ _RTHP.SOURCE-TEXT-A @ _RTHP-FX-P @ _RTHP.SOURCE-TEXT-USED @
        _RTHP-FX-P @ _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    _RTHP-FX-P @ _RTHP.FIELD-BASE-TEXT @ DUP _RTHP-FX-TEXT !
        _RTHP-FX-P @ _RTHP.SOURCE-TEXT-USED @ U> IF 0 EXIT THEN
    0 _RTHP-FX-ITEMS ! 0 _RTHP-FX-UTF8 !
    _RTHP-FX-P @ _RTHP-CT-P !
    _RTHP-FX-P @ _RTHP.FIELD-COUNT @ 0 ?DO
        I _RTHP-FX-P @ _RTHP.FIELD-BASE-CONTROLS @ + _RTHP-FX-I !
        _RTHP-FX-P @ _RTHP.CONTROLS-A @ _RTHP-FX-I @ RTE-CONTROL-SIZE * +
            DUP _RTHP-FX-C ! _RTHP-CT-CONTROL !
        _RTHP-FX-C @ RTE-CONTROL-VALID? 0= IF 0 UNLOOP EXIT THEN
        _RTHP-FX-C @ _RTE-CONTROL.OWNER @ _RTHP-FX-P @ _RTHP.OWNER @ <>
        _RTHP-FX-C @ _RTE-CONTROL.GENERATION @ _RTHP-FX-P @ _RTHP.OWNER-GEN @ <> OR
        _RTHP-FX-C @ _RTE-CONTROL.REGION @ _RTHP-FX-P @ _RTHP.REGION @ <> OR IF 0 UNLOOP EXIT THEN
        _RTHP-FX-P @ _RTHP.FIRST-OBJECT @ _RTHP-FX-I @ _RTHP-U+?
            0= IF DROP 0 UNLOOP EXIT THEN
        _RTHP-FX-C @ _RTE-CONTROL.ID @ <> IF 0 UNLOOP EXIT THEN
        _RTHP-FX-C @ _RTE-CONTROL.ROOT-HEIGHT @ _RTHP-FX-P @ _RTHP.ROWS @ <>
        _RTHP-FX-C @ _RTE-CONTROL.ROOT-WIDTH @ _RTHP-FX-P @ _RTHP.COLS @ <> OR IF 0 UNLOOP EXIT THEN
        _RTHP-FX-C @ _RTE-CONTROL.STATE @ RTE-CONTROL-VISIBLE AND 0= IF 0 UNLOOP EXIT THEN
        _RTHP-CT-FIELD? 0= IF DROP 0 UNLOOP EXIT THEN DROP
        _RTHP-FX-C @ _RTE-CONTROL.LABEL-A @ _RTHP-FX-C @ _RTE-CONTROL.LABEL-U @
            _RTHP-FX-TEXT? 0= IF 0 UNLOOP EXIT THEN
        _RTHP-FX-C @ _RTE-CONTROL.CONTENT-A @ _RTHP-FX-C @ _RTE-CONTROL.CONTENT-U @
            _RTHP-FX-TEXT? 0= IF 0 UNLOOP EXIT THEN
        _RTHP-FX-P @ _RTHP.CORR-A @ _RTHP-FX-I @ RUCP-CORRELATION-SIZE * + _RTHP-FX-X !
        \ A document's field comes from its UIDL source or, last, its overlay.
        _RTHP-FX-X @ RUCP-CORRELATION-CONTROL-ID@ _RTHP-FX-C @ _RTE-CONTROL.ID @ <>
        _RTHP-FX-X @ RUCP-CORRELATION-SOURCE@ DUP UFLSN-SOURCE-UIDL <>
            SWAP UFLSN-SOURCE-OVERLAY <> AND OR
        _RTHP-FX-X @ RUCP-CORRELATION-INDEX@ 0< OR
        _RTHP-FX-X @ RUCP-CORRELATION-ATTACHMENT@ 0= OR
        _RTHP-FX-X @ RUCP-CORRELATION-SCOPE@ 0= OR
        _RTHP-FX-X @ RUCP-CORRELATION-SUBKEY@ 0= OR
        _RTHP-FX-X @ RUCP-CORRELATION-LIFECYCLE-GENERATION@ 0= OR IF 0 UNLOOP EXIT THEN
        _RTHP-FX-P @ _RTHP.CLAIMS-A @ _RTHP-FX-P @ _RTHP.FIELD-BASE-CLAIMS @ +
            I RUCL-CLAIM-SIZE * + _RTHP-FX-CLAIM !
        _RTHP-FX-CLAIM @ RUCL-CLAIM-ATTACHMENT@ _RTHP-FX-X @ RUCP-CORRELATION-ATTACHMENT@ <>
        _RTHP-FX-CLAIM @ RUCL-CLAIM-SOURCE-GENERATION@ _RTHP-FX-P @ _RTHP.SOURCE-GEN @ <> OR
        _RTHP-FX-CLAIM @ RUCL-CLAIM-SOURCE@ _RTHP-FX-X @ RUCP-CORRELATION-SOURCE@ <> OR
        _RTHP-FX-CLAIM @ RUCL-CLAIM-SOURCE-INDEX@ _RTHP-FX-X @ RUCP-CORRELATION-INDEX@ <> OR
        _RTHP-FX-CLAIM @ RUCL-CLAIM-SUBKEY@ _RTHP-FX-X @ RUCP-CORRELATION-SUBKEY@ <> OR
        _RTHP-FX-CLAIM @ RUCL-CLAIM-Z@ _RTHP-FX-C @ _RTE-CONTROL.Z @ <> OR IF 0 UNLOOP EXIT THEN
        _RTHP-FX-CLAIM @ RUCL-CLAIM-ROW0@ _RTHP-FX-C @ _RTE-CONTROL.ROW @ <>
        _RTHP-FX-CLAIM @ RUCL-CLAIM-COL0@ _RTHP-FX-C @ _RTE-CONTROL.COL @ <> OR
        _RTHP-FX-CLAIM @ RUCL-CLAIM-ROW1@
            _RTHP-FX-C @ _RTE-CONTROL.ROW @ _RTHP-FX-C @ _RTE-CONTROL.HEIGHT @ + <> OR
        _RTHP-FX-CLAIM @ RUCL-CLAIM-COL1@
            _RTHP-FX-C @ _RTE-CONTROL.COL @ _RTHP-FX-C @ _RTE-CONTROL.WIDTH @ + <> OR IF 0 UNLOOP EXIT THEN
        _RTHP-FX-ITEMS @ _RTHP-FX-C @ _RTE-CONTROL.CONTENT-ITEMS @ _RTHP-U32+?
            0= IF DROP 0 UNLOOP EXIT THEN _RTHP-FX-ITEMS !
        _RTHP-FX-C @ _RTE-CONTROL.LABEL-U @ _RTHP-FX-C @ _RTE-CONTROL.CONTENT-UTF8 @
            _RTHP-U32+? 0= IF DROP 0 UNLOOP EXIT THEN
        _RTHP-FX-UTF8 @ _RTHP-U32+? 0= IF DROP 0 UNLOOP EXIT THEN _RTHP-FX-UTF8 !
    LOOP
    _RTHP-FX-TEXT @ _RTHP-FX-P @ _RTHP.DIALOG-BASE-TEXT @ =
    _RTHP-FX-ITEMS @ _RTHP-FX-P @ _RTHP.FIELD-ITEMS @ = AND
    _RTHP-FX-UTF8 @ _RTHP-FX-P @ _RTHP.FIELD-UTF8 @ = AND ;

\ The dialog lane runs from the end of the fields to the end of the
\ controls, of the base claims, one a dialog, and of the text.  Each dialog
\ comes first and its buttons, inside it, follow; all name it.
VARIABLE _RTHP-DX-P
VARIABLE _RTHP-DX-I
VARIABLE _RTHP-DX-C
VARIABLE _RTHP-DX-X
VARIABLE _RTHP-DX-DIALOG
VARIABLE _RTHP-DX-DIALOG-X
VARIABLE _RTHP-DX-DIALOGS
VARIABLE _RTHP-DX-UTF8

: _RTHP-DX-CLAIM? ( -- flag )
    _RTHP-DX-P @ _RTHP.CLAIMS-A @ _RTHP-DX-P @ _RTHP.DIALOG-BASE-CLAIMS @ +
        _RTHP-DX-DIALOGS @ RUCL-CLAIM-SIZE * + _RTHP-FX-CLAIM !
    _RTHP-FX-CLAIM @ RUCL-CLAIM-ATTACHMENT@ _RTHP-DX-X @ RUCP-CORRELATION-ATTACHMENT@ <>
    _RTHP-FX-CLAIM @ RUCL-CLAIM-SOURCE-GENERATION@ _RTHP-DX-P @ _RTHP.SOURCE-GEN @ <> OR
    _RTHP-FX-CLAIM @ RUCL-CLAIM-SOURCE@ _RTHP-DX-X @ RUCP-CORRELATION-SOURCE@ <> OR
    _RTHP-FX-CLAIM @ RUCL-CLAIM-SOURCE-INDEX@ OR
    _RTHP-FX-CLAIM @ RUCL-CLAIM-SUBKEY@ _RTHP-DX-X @ RUCP-CORRELATION-SUBKEY@ <> OR
    _RTHP-FX-CLAIM @ RUCL-CLAIM-Z@ _RTHP-DX-C @ _RTE-CONTROL.Z @ <> OR IF 0 EXIT THEN
    _RTHP-FX-CLAIM @ RUCL-CLAIM-ROW0@ _RTHP-DX-C @ _RTE-CONTROL.ROW @ <>
    _RTHP-FX-CLAIM @ RUCL-CLAIM-COL0@ _RTHP-DX-C @ _RTE-CONTROL.COL @ <> OR
    _RTHP-FX-CLAIM @ RUCL-CLAIM-ROW1@
        _RTHP-DX-C @ _RTE-CONTROL.ROW @ _RTHP-DX-C @ _RTE-CONTROL.HEIGHT @ + <> OR
    _RTHP-FX-CLAIM @ RUCL-CLAIM-COL1@
        _RTHP-DX-C @ _RTE-CONTROL.COL @ _RTHP-DX-C @ _RTE-CONTROL.WIDTH @ + <> OR
    0= ;

: _RTHP-DX-DIALOG? ( -- flag )
    _RTHP-DX-X @ RUCP-CORRELATION-INDEX@ IF 0 EXIT THEN
    _RTHP-DX-C @ _RTE-CONTROL.STATE @ RTE-CONTROL-VISIBLE <> IF 0 EXIT THEN
    _RTHP-DX-C @ _RTE-CONTROL.CONTENT-A @ _RTHP-DX-C @ _RTE-CONTROL.CONTENT-U @
    _RTHP-DX-C @ _RTE-CONTROL.LABEL-A @ _RTHP-DX-C @ _RTE-CONTROL.LABEL-U @
    _RTHP-DX-C @ _RTE-CONTROL.WIDTH @ _RTHP-DX-C @ _RTE-CONTROL.HEIGHT @
        DLG1-VALIDATE 0= IF DROP 0 EXIT THEN
    _RTHP-DX-C @ _RTE-CONTROL.CONTENT-UTF8 @ <> IF 0 EXIT THEN
    _RTHP-DX-CLAIM? 0= IF 0 EXIT THEN
    _RTHP-DX-C @ _RTHP-DX-DIALOG ! _RTHP-DX-X @ _RTHP-DX-DIALOG-X !
    1 _RTHP-DX-DIALOGS +! -1 ;

: _RTHP-DX-BUTTON? ( -- flag )
    _RTHP-DX-DIALOG @ 0= IF 0 EXIT THEN
    _RTHP-DX-X @ RUCP-CORRELATION-INDEX@ 0= IF 0 EXIT THEN
    _RTHP-DX-X @ RUCP-CORRELATION-ATTACHMENT@
        _RTHP-DX-DIALOG-X @ RUCP-CORRELATION-ATTACHMENT@ <>
    _RTHP-DX-X @ RUCP-CORRELATION-SOURCE@
        _RTHP-DX-DIALOG-X @ RUCP-CORRELATION-SOURCE@ <> OR
    _RTHP-DX-X @ RUCP-CORRELATION-SUBKEY@
        _RTHP-DX-DIALOG-X @ RUCP-CORRELATION-SUBKEY@ <> OR IF 0 EXIT THEN
    _RTHP-DX-C @ _RTE-CONTROL.STATE @
        RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR RTE-CONTROL-SELECTED OR
        INVERT AND IF 0 EXIT THEN
    _RTHP-DX-C @ _RTE-CONTROL.CONTENT-A @ _RTHP-DX-C @ _RTE-CONTROL.CONTENT-U @
        BTN1-VALIDATE 0= IF 0 EXIT THEN
    _RTHP-DX-C @ _RTE-CONTROL.CONTENT-UTF8 @ IF 0 EXIT THEN
    _RTHP-DX-C @ _RTE-CONTROL.LABEL-U @ 0= IF 0 EXIT THEN
    _RTHP-DX-C @ _RTE-CONTROL.Z @ _RTHP-DX-DIALOG @ _RTE-CONTROL.Z @ 1+ <> IF 0 EXIT THEN
    _RTHP-DX-C @ _RTE-CONTROL.ROW @ _RTHP-DX-DIALOG @ _RTE-CONTROL.ROW @ <
    _RTHP-DX-C @ _RTE-CONTROL.COL @ _RTHP-DX-DIALOG @ _RTE-CONTROL.COL @ < OR
    _RTHP-DX-C @ _RTE-CONTROL.ROW @ _RTHP-DX-C @ _RTE-CONTROL.HEIGHT @ +
        _RTHP-DX-DIALOG @ _RTE-CONTROL.ROW @ _RTHP-DX-DIALOG @ _RTE-CONTROL.HEIGHT @ + > OR
    _RTHP-DX-C @ _RTE-CONTROL.COL @ _RTHP-DX-C @ _RTE-CONTROL.WIDTH @ +
        _RTHP-DX-DIALOG @ _RTE-CONTROL.COL @ _RTHP-DX-DIALOG @ _RTE-CONTROL.WIDTH @ + > OR
    0= ;

: _RTHP-DIALOGS-FIXED? ( producer -- flag )
    _RTHP-DX-P !
    _RTHP-DX-P @ _RTHP.DIALOG-CONTROLS @
        _RTHP-DX-P @ _RTHP.MAX-DIALOG-CONTROLS @ U> IF 0 EXIT THEN
    _RTHP-DX-P @ _RTHP.DIALOG-COUNT @
        _RTHP-DX-P @ _RTHP.MAX-DIALOGS @ U> IF 0 EXIT THEN
    _RTHP-DX-P @ _RTHP.DIALOG-BASE-CONTROLS @
    _RTHP-DX-P @ _RTHP.DIALOG-CONTROLS @ _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-DX-P @ _RTHP.CONTROL-COUNT @ <> IF 0 EXIT THEN
    _RTHP-DX-P @ _RTHP.MENU-CONTROL-COUNT @ _RTHP-DX-P @ _RTHP.COLLECTION-COUNT @ +
    _RTHP-DX-P @ _RTHP.FIELD-COUNT @ +
        _RTHP-DX-P @ _RTHP.DIALOG-BASE-CONTROLS @ <> IF 0 EXIT THEN
    _RTHP-DX-P @ _RTHP.DIALOG-BASE-CLAIMS @ DUP RUCL-CLAIM-SIZE MOD IF DROP 0 EXIT THEN
    _RTHP-DX-P @ _RTHP.DIALOG-COUNT @ RUCL-CLAIM-SIZE _RTHP-U32*?
        0= IF 2DROP 0 EXIT THEN
    _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-DX-P @ _RTHP.BASE-CLAIMS-USED @ <> IF 0 EXIT THEN
    _RTHP-DX-P @ _RTHP.DIALOG-BASE-TEXT @ DUP _RTHP-FX-TEXT !
        _RTHP-DX-P @ _RTHP.SOURCE-TEXT-USED @ U> IF 0 EXIT THEN
    _RTHP-DX-P @ _RTHP.DIALOG-CONTROLS @ 0= IF
        _RTHP-DX-P @ _RTHP.DIALOG-COUNT @ _RTHP-DX-P @ _RTHP.DIALOG-UTF8 @ OR
            IF 0 EXIT THEN
        _RTHP-FX-TEXT @ _RTHP-DX-P @ _RTHP.SOURCE-TEXT-USED @ = EXIT
    THEN
    _RTHP-DX-P @ _RTHP.CONTROLS-A @
    _RTHP-DX-P @ _RTHP.CONTROL-COUNT @ RTE-CONTROL-SIZE *
        _RTHP-DX-P @ _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    _RTHP-DX-P @ _RTHP.CORR-A @
    _RTHP-DX-P @ _RTHP.CONTROL-COUNT @ RUCP-CORRELATION-SIZE *
        _RTHP-DX-P @ _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    _RTHP-DX-P @ _RTHP.CLAIMS-A @ _RTHP-DX-P @ _RTHP.BASE-CLAIMS-USED @
        _RTHP-DX-P @ _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    _RTHP-DX-P @ _RTHP.SOURCE-TEXT-A @ _RTHP-DX-P @ _RTHP.SOURCE-TEXT-USED @
        _RTHP-DX-P @ _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    0 _RTHP-DX-DIALOG ! 0 _RTHP-DX-DIALOG-X !
    0 _RTHP-DX-DIALOGS ! 0 _RTHP-DX-UTF8 !
    _RTHP-DX-P @ _RTHP-FX-P !
    _RTHP-DX-P @ _RTHP.DIALOG-CONTROLS @ 0 ?DO
        I _RTHP-DX-P @ _RTHP.DIALOG-BASE-CONTROLS @ + _RTHP-DX-I !
        _RTHP-DX-P @ _RTHP.CONTROLS-A @ _RTHP-DX-I @ RTE-CONTROL-SIZE * +
            _RTHP-DX-C !
        _RTHP-DX-P @ _RTHP.CORR-A @ _RTHP-DX-I @ RUCP-CORRELATION-SIZE * +
            _RTHP-DX-X !
        _RTHP-DX-C @ RTE-CONTROL-VALID? 0= IF 0 UNLOOP EXIT THEN
        _RTHP-DX-C @ _RTE-CONTROL.OWNER @ _RTHP-DX-P @ _RTHP.OWNER @ <>
        _RTHP-DX-C @ _RTE-CONTROL.GENERATION @ _RTHP-DX-P @ _RTHP.OWNER-GEN @ <> OR
        _RTHP-DX-C @ _RTE-CONTROL.REGION @ _RTHP-DX-P @ _RTHP.REGION @ <> OR
            IF 0 UNLOOP EXIT THEN
        _RTHP-DX-P @ _RTHP.FIRST-OBJECT @ _RTHP-DX-I @ _RTHP-U+?
            0= IF DROP 0 UNLOOP EXIT THEN
        _RTHP-DX-C @ _RTE-CONTROL.ID @ <> IF 0 UNLOOP EXIT THEN
        _RTHP-DX-C @ _RTE-CONTROL.ROOT-HEIGHT @ _RTHP-DX-P @ _RTHP.ROWS @ <>
        _RTHP-DX-C @ _RTE-CONTROL.ROOT-WIDTH @ _RTHP-DX-P @ _RTHP.COLS @ <> OR
            IF 0 UNLOOP EXIT THEN
        _RTHP-DX-C @ _RTE-CONTROL.PARENT @ _RTHP-DX-C @ _RTE-CONTROL.ORDER @ OR
            IF 0 UNLOOP EXIT THEN
        _RTHP-DX-X @ RUCP-CORRELATION-CONTROL-ID@ _RTHP-DX-C @ _RTE-CONTROL.ID @ <>
        _RTHP-DX-X @ RUCP-CORRELATION-SOURCE@ DUP UDLSN-SOURCE-OVERLAY <>
            SWAP UDLSN-SOURCE-ELEMENT <> AND OR
        _RTHP-DX-X @ RUCP-CORRELATION-ATTACHMENT@ 0= OR
        _RTHP-DX-X @ RUCP-CORRELATION-SCOPE@ 0= OR
        _RTHP-DX-X @ RUCP-CORRELATION-SUBKEY@
            _RTHP-DX-X @ RUCP-CORRELATION-SCOPE@ <> OR
        _RTHP-DX-X @ RUCP-CORRELATION-LIFECYCLE-GENERATION@ 1 <> OR
            IF 0 UNLOOP EXIT THEN
        _RTHP-DX-C @ _RTE-CONTROL.KIND @ RTE-CONTROL-DIALOG = IF
            _RTHP-DX-DIALOG? 0= IF 0 UNLOOP EXIT THEN
        ELSE
            _RTHP-DX-C @ _RTE-CONTROL.KIND @ RTE-CONTROL-BUTTON <>
                IF 0 UNLOOP EXIT THEN
            _RTHP-DX-BUTTON? 0= IF 0 UNLOOP EXIT THEN
        THEN
        _RTHP-DX-C @ _RTE-CONTROL.LABEL-A @ _RTHP-DX-C @ _RTE-CONTROL.LABEL-U @
            _RTHP-FX-TEXT? 0= IF 0 UNLOOP EXIT THEN
        _RTHP-DX-C @ _RTE-CONTROL.SHORTCUT-A @ _RTHP-DX-C @ _RTE-CONTROL.SHORTCUT-U @
            _RTHP-FX-TEXT? 0= IF 0 UNLOOP EXIT THEN
        _RTHP-DX-C @ _RTE-CONTROL.CONTENT-A @ _RTHP-DX-C @ _RTE-CONTROL.CONTENT-U @
            _RTHP-FX-TEXT? 0= IF 0 UNLOOP EXIT THEN
        _RTHP-DX-C @ _RTE-CONTROL.LABEL-U @ _RTHP-DX-C @ _RTE-CONTROL.SHORTCUT-U @
            _RTHP-U32+? 0= IF DROP 0 UNLOOP EXIT THEN
        _RTHP-DX-C @ _RTE-CONTROL.CONTENT-UTF8 @ _RTHP-U32+?
            0= IF DROP 0 UNLOOP EXIT THEN
        _RTHP-DX-UTF8 @ _RTHP-U32+? 0= IF DROP 0 UNLOOP EXIT THEN _RTHP-DX-UTF8 !
    LOOP
    _RTHP-FX-TEXT @ _RTHP-DX-P @ _RTHP.SOURCE-TEXT-USED @ =
    _RTHP-DX-DIALOGS @ _RTHP-DX-P @ _RTHP.DIALOG-COUNT @ = AND
    _RTHP-DX-UTF8 @ _RTHP-DX-P @ _RTHP.DIALOG-UTF8 @ = AND ;

\ Compare the independently recomputed snapshot summary with both producer
\ counters and neutral admission before the first captured operation.
: _RTHP-SERIES-FIXED? ( producer -- flag )
    DUP _RTHP-SERIES-SUMMARY? 0= IF DROP 0 EXIT THEN _RTHP-SQ-P !
    _RTHP-SQ-P @ _RTHP.SHELL-BUILT @ 0= IF
        _RTHP-SQ-P @ _RTHP.SERIES-COUNT @
        _RTHP-SQ-P @ _RTHP.ADMISSION _RTE-HA.SERIES-COUNT @ <> IF 0 EXIT THEN
        _RTHP-SQ-P @ _RTHP.SERIES-LAST @
        _RTHP-SQ-P @ _RTHP.ADMISSION _RTE-HA.SERIES-LAST @ <> IF 0 EXIT THEN
        _RTHP-SQ-P @ _RTHP.SERIES-SLOTS @
        _RTHP-SQ-P @ _RTHP.ADMISSION _RTE-HA.SERIES-SLOTS @ <> IF 0 EXIT THEN
        _RTHP-SQ-P @ _RTHP.SERIES-HISTORY-MAX @
        _RTHP-SQ-P @ _RTHP.ADMISSION _RTE-HA.SERIES-HISTORY-MAX @ <> IF 0 EXIT THEN
        _RTHP-SQ-P @ _RTHP.SERIES-SAMPLES-USED @
        _RTHP-SQ-P @ _RTHP.ADMISSION _RTE-HA.SERIES-SAMPLE-BYTES @ <> IF 0 EXIT THEN
        _RTHP-SQ-P @ _RTHP.SERIES-CHUNKS @
        _RTHP-SQ-P @ _RTHP.ADMISSION _RTE-HA.SERIES-CHUNKS @ <> IF 0 EXIT THEN
        _RTHP-SQ-P @ _RTHP.SERIES-CHUNK-MAX @
        _RTHP-SQ-P @ _RTHP.ADMISSION _RTE-HA.SERIES-CHUNK-SAMPLES-MAX @ <> IF 0 EXIT THEN
        _RTHP-SQ-P @ _RTHP.SERIES-CHUNK-BYTES-MAX @
        _RTHP-SQ-P @ _RTHP.ADMISSION _RTE-HA.SERIES-CHUNK-BYTES-MAX @ <> IF 0 EXIT THEN
        _RTHP-SQ-P @ _RTHP.WAVEFORM-COUNT @
        _RTHP-SQ-P @ _RTHP.ADMISSION _RTE-HA.WAVEFORM-COUNT @ <> IF 0 EXIT THEN
    THEN
    _RTHP-SQ-SLOTS @ _RTHP-SQ-P @ _RTHP.SERIES-SLOTS @ <> IF 0 EXIT THEN
    _RTHP-SQ-HISTORY @ _RTHP-SQ-P @ _RTHP.SERIES-HISTORY-MAX @ <> IF 0 EXIT THEN
    _RTHP-SQ-CHUNKS @ _RTHP-SQ-P @ _RTHP.SERIES-CHUNKS @ <> IF 0 EXIT THEN
    _RTHP-SQ-MAX @ _RTHP-SQ-P @ _RTHP.SERIES-CHUNK-MAX @ <> IF 0 EXIT THEN
    _RTHP-SQ-BYTES @ _RTHP-SQ-P @ _RTHP.SERIES-CHUNK-BYTES-MAX @ <> IF 0 EXIT THEN
    _RTHP-SQ-WAVES @ _RTHP-SQ-P @ _RTHP.WAVEFORM-COUNT @ <> IF 0 EXIT THEN
    _RTHP-SQ-P @ _RTHP.HYBRID _RTE-HP.SERIES-SAMPLES-U @
        _RTHP-SQ-P @ _RTHP.SERIES-SAMPLES-USED @ <> IF 0 EXIT THEN
    _RTHP-SQ-P @ _RTHP.SERIES-SAMPLES-USED @ IF
        _RTHP-SQ-P @ _RTHP.HYBRID _RTE-HP.SERIES-SAMPLES-A @
        _RTHP-SQ-P @ _RTHP.SERIES-SAMPLES-A @ <> IF 0 EXIT THEN
    ELSE
        _RTHP-SQ-P @ _RTHP.HYBRID _RTE-HP.SERIES-SAMPLES-A @ IF 0 EXIT THEN
    THEN
    _RTHP-SQ-P @ _RTHP.SERIES-COUNT @ 0= IF
        _RTHP-SQ-P @ _RTHP.SERIES-LAST @
        _RTHP-SQ-P @ _RTHP.HYBRID _RTE-HP.SERIES-PLAN @ OR 0= EXIT
    THEN
    _RTHP-SQ-P @ _RTHP.HYBRID _RTE-HP.SERIES-PLAN @
        _RTHP-SQ-P @ _RTHP.SERIES-PLAN <> IF 0 EXIT THEN
    _RTHP-SQ-P @ _RTHP.SERIES-PLAN _RTE-SRP.ITEMS-A @
        _RTHP-SQ-P @ _RTHP.SERIES-A @ <> IF 0 EXIT THEN
    _RTHP-SQ-P @ _RTHP.SERIES-PLAN _RTE-SRP.ITEMS-U @
        _RTHP-SQ-P @ _RTHP.SERIES-COUNT @ RTE-SERIES-SIZE * <> IF 0 EXIT THEN
    _RTHP-SQ-P @ _RTHP.SERIES-PLAN _RTE-SRP.OWNER @
        _RTHP-SQ-P @ _RTHP.OWNER @ <> IF 0 EXIT THEN
    _RTHP-SQ-P @ _RTHP.SERIES-PLAN _RTE-SRP.GENERATION @
        _RTHP-SQ-P @ _RTHP.OWNER-GEN @ <> IF 0 EXIT THEN
    _RTHP-SQ-P @ _RTHP.SERIES-PLAN _RTE-SRP.SURFACE-COLS @
        _RTHP-SQ-P @ _RTHP.COLS @ <> IF 0 EXIT THEN
    _RTHP-SQ-P @ _RTHP.SERIES-PLAN _RTE-SRP.SURFACE-ROWS @
        _RTHP-SQ-P @ _RTHP.ROWS @ <> IF 0 EXIT THEN
    _RTHP-SQ-P @ _RTHP.FIRST-SERIES @
    _RTHP-SQ-P @ _RTHP.SERIES-COUNT @ 1- _RTHP-U+? 0= IF DROP 0 EXIT THEN
    _RTHP-SQ-P @ _RTHP.SERIES-LAST @ = ;

: _RTHP-FIXED-BODY?  ( -- flag )
    _RTHP-X-P @ _RTHP-SERIES-FIXED? 0= IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.SURFACE-GEN @ 0= IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.SOURCE-CONTENT-EPOCH @ 0= IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.SOURCE-DRAW @
        _RTHP-X-P @ _RTHP.SURFACE-GEN @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.REGION @
        _RTHP-X-P @ _RTHP.NEXT-REGION @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.FIRST-OBJECT @
        _RTHP-X-P @ _RTHP.NEXT-OBJECT @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.DGRAPH-DESCRIPTORS-USED @ DUP
        _RTHP-X-P @ _RTHP.DGRAPH-DESCRIPTORS-U @ U> IF DROP 0 EXIT THEN
    DUP UDGSN-DESCRIPTOR-SIZE MOD IF DROP 0 EXIT THEN
    UDGSN-DESCRIPTOR-SIZE / DUP
        _RTHP-X-P @ _RTHP.SOURCE-DGRAPH-COUNT @ <> IF DROP 0 EXIT THEN
    _RTHP-X-P @ _RTHP.MAX-DGRAPH-DESCRIPTORS @ U> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.DGRAPH-NATIVE-USED @ DUP
        _RTHP-X-P @ _RTHP.DGRAPH-NATIVE-U @ U> IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    0= _RTHP-X-P @ _RTHP.SOURCE-DGRAPH-COUNT @ 0= <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.CLAIMS-USED @
        _RTHP-X-P @ _RTHP.CLAIMS-U @ U> IF 0 EXIT THEN
    _RTHP-X-ADMITTED? IF
        _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.OWNER @
            _RTHP-X-P @ _RTHP.OWNER @ <> IF 0 EXIT THEN
        _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.GENERATION @
            _RTHP-X-P @ _RTHP.OWNER-GEN @ <> IF 0 EXIT THEN
        _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.SURFACE-COLS @
            _RTHP-X-P @ _RTHP.COLS @ <> IF 0 EXIT THEN
        _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.SURFACE-ROWS @
            _RTHP-X-P @ _RTHP.ROWS @ <> IF 0 EXIT THEN
        _RTHP-X-P @ _RTHP.CONTROL-COUNT @
        _RTHP-X-P @ _RTHP.GLYPH-COUNT @ OR
        _RTHP-X-P @ _RTHP.STATIC-COUNT @ OR IF
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.REGION-ID @
                _RTHP-X-P @ _RTHP.REGION @ <> IF 0 EXIT THEN
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.REGION-X @
                0<> IF 0 EXIT THEN
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.REGION-Y @
                0<> IF 0 EXIT THEN
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.REGION-COLS @
                _RTHP-X-P @ _RTHP.COLS @ <> IF 0 EXIT THEN
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.REGION-ROWS @
                _RTHP-X-P @ _RTHP.ROWS @ <> IF 0 EXIT THEN
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.CLIP-X @
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.CLIP-Y @ OR
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.CLIP-COLS @ OR
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.CLIP-ROWS @ OR IF
                0 EXIT
            THEN
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.REGION-Z @
                _RTHP-X-P @ _RTHP-BASE-Z-FIXED? 0= IF 0 EXIT THEN
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.REGION-FLAGS @
                RTE-REGION-VISIBLE <> IF 0 EXIT THEN
        ELSE
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.REGION-ID @
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.REGION-X @ OR
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.REGION-Y @ OR
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.REGION-COLS @ OR
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.REGION-ROWS @ OR
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.CLIP-X @ OR
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.CLIP-Y @ OR
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.CLIP-COLS @ OR
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.CLIP-ROWS @ OR
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.REGION-Z @ OR
            _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.REGION-FLAGS @ OR IF
                0 EXIT
            THEN
        THEN
        _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.CONTROL-COUNT @
            _RTHP-X-P @ _RTHP.CONTROL-COUNT @ <> IF 0 EXIT THEN
        _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.CONTROL-BYTES @
            _RTHP-X-P @ _RTHP.SOURCE-TEXT-USED @ <> IF 0 EXIT THEN
        _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.CONTROL-COLLECTIONS @
            _RTHP-X-P @ _RTHP.COLLECTION-COUNT @ <> IF 0 EXIT THEN
        _RTHP-X-P @ _RTHP.COLLECTION-ITEMS @ _RTHP-X-P @ _RTHP.FIELD-ITEMS @
            _RTHP-U32+? 0= IF DROP 0 EXIT THEN
        _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.CONTROL-ITEMS @ <> IF 0 EXIT THEN
        _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.FIELD-CONTROLS @
            _RTHP-X-P @ _RTHP.FIELD-COUNT @ <> IF 0 EXIT THEN
        _RTHP-X-P @ _RTHP.SOURCE-MENU-TEXT-USED @
        _RTHP-X-P @ _RTHP.COLLECTION-UTF8 @ _RTHP-U32+?
            0= IF DROP 0 EXIT THEN
        _RTHP-X-P @ _RTHP.FIELD-UTF8 @ _RTHP-U32+?
            0= IF DROP 0 EXIT THEN
        _RTHP-X-P @ _RTHP.DIALOG-UTF8 @ _RTHP-U32+?
            0= IF DROP 0 EXIT THEN
        _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.CONTROL-UTF8 @
            <> IF 0 EXIT THEN
        _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.GLYPH-COUNT @
            _RTHP-X-P @ _RTHP.GLYPH-COUNT @ <> IF 0 EXIT THEN
        _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.GLYPH-TEXT @
            _RTHP-X-P @ _RTHP.GLYPH-TEXT-USED @ <> IF 0 EXIT THEN
    THEN
    _RTHP-X-P @ _RTHP-FIELDS-FIXED? 0= IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP-DIALOGS-FIXED? 0= IF 0 EXIT THEN
    _RTHP-INSTRUMENT-FIXED? 0= IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP-BASE-CLAIMS-DISJOINT? 0= IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP-STATICS-FIXED? 0= IF 0 EXIT THEN
    _RTHP-X-ADMITTED? IF
        _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.CONTROL-ITEM-VIEWS @
            RTE-CONTROL-ITEM-VIEW _RTHP-X-KIND-COUNT <> IF 0 EXIT THEN
        _RTHP-X-P @ _RTHP.ADMISSION _RTE-HA.DOCUMENT-CONTROLS @
            RTE-CONTROL-DOCUMENT _RTHP-X-KIND-COUNT <> IF 0 EXIT THEN
    THEN

    _RTHP-X-P @ _RTHP.CONTROL-COUNT @ IF
    _RTHP-X-P @ _RTHP.CONTROL-PLAN _RTE-CP.OWNER @
        _RTHP-X-P @ _RTHP.OWNER @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.CONTROL-PLAN _RTE-CP.GENERATION @
        _RTHP-X-P @ _RTHP.OWNER-GEN @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.CONTROL-PLAN _RTE-CP.SURFACE-COLS @
        _RTHP-X-P @ _RTHP.COLS @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.CONTROL-PLAN _RTE-CP.SURFACE-ROWS @
        _RTHP-X-P @ _RTHP.ROWS @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.CONTROL-PLAN _RTE-CP.REGION-ID @
        _RTHP-X-P @ _RTHP.REGION @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.CONTROL-PLAN _RTE-CP.REGION-X @ 0<> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.CONTROL-PLAN _RTE-CP.REGION-Y @ 0<> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.CONTROL-PLAN _RTE-CP.REGION-COLS @
        _RTHP-X-P @ _RTHP.COLS @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.CONTROL-PLAN _RTE-CP.REGION-ROWS @
        _RTHP-X-P @ _RTHP.ROWS @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.CONTROL-PLAN _RTE-CP.CLIP-X @
    _RTHP-X-P @ _RTHP.CONTROL-PLAN _RTE-CP.CLIP-Y @ OR
    _RTHP-X-P @ _RTHP.CONTROL-PLAN _RTE-CP.CLIP-COLS @ OR
    _RTHP-X-P @ _RTHP.CONTROL-PLAN _RTE-CP.CLIP-ROWS @ OR IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.CONTROL-PLAN _RTE-CP.REGION-Z @
        _RTHP-X-P @ _RTHP-BASE-Z-FIXED? 0= IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.CONTROL-PLAN _RTE-CP.REGION-FLAGS @
        RTE-REGION-VISIBLE <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.CONTROL-PLAN _RTE-CP.ITEMS-A @
        _RTHP-X-P @ _RTHP.CONTROLS-A @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.CONTROL-PLAN _RTE-CP.ITEMS-U @
        _RTHP-X-P @ _RTHP.CONTROL-COUNT @ RTE-CONTROL-SIZE * <>
        IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.CONTROL-PLAN _RTE-CP.RESERVED @ 0<> IF 0 EXIT THEN
    THEN

    _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.ATTEMPT @
        _RTHP-X-P @ _RTHP.ATTEMPT @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.SOURCE-GENERATION @
        _RTHP-X-P @ _RTHP.SOURCE-GEN @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.SURFACE-GENERATION @
        _RTHP-X-P @ _RTHP.SURFACE-GEN @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.CONTROL-COUNT @ IF
        _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.CONTROL-PLAN @
            _RTHP-X-P @ _RTHP.CONTROL-PLAN <> IF 0 EXIT THEN
        _RTHP-X-P @ _RTHP.SOURCE-TEXT-USED @ IF
            _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.CONTROL-BYTES-A @
                _RTHP-X-P @ _RTHP.SOURCE-TEXT-A @ <> IF 0 EXIT THEN
        ELSE
            _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.CONTROL-BYTES-A @
                0<> IF 0 EXIT THEN
        THEN
        _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.CONTROL-BYTES-U @
            _RTHP-X-P @ _RTHP.SOURCE-TEXT-USED @ <> IF 0 EXIT THEN
    ELSE
        _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.CONTROL-PLAN @
        _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.CONTROL-BYTES-A @ OR
        _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.CONTROL-BYTES-U @ OR IF
            0 EXIT
        THEN
    THEN
    _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.RESERVED @ 0<> IF 0 EXIT THEN

    _RTHP-X-P @ _RTHP.GLYPH-COUNT @ 0= IF
        _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.GLYPH-PLAN @ 0=
        _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.GLYPH-REFS-A @ 0= AND
        _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.GLYPH-REFS-U @ 0= AND
        _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.GLYPH-TEXT-A @ 0= AND
        _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.GLYPH-TEXT-U @ 0= AND EXIT
    THEN
    _RTHP-X-P @ _RTHP.GLYPH-PLAN _RTE-LP.OWNER @
        _RTHP-X-P @ _RTHP.OWNER @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.GLYPH-PLAN _RTE-LP.GENERATION @
        _RTHP-X-P @ _RTHP.OWNER-GEN @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.GLYPH-PLAN _RTE-LP.SURFACE-COLS @
        _RTHP-X-P @ _RTHP.COLS @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.GLYPH-PLAN _RTE-LP.SURFACE-ROWS @
        _RTHP-X-P @ _RTHP.ROWS @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.GLYPH-PLAN _RTE-LP.REGION-ID @
        _RTHP-X-P @ _RTHP.REGION @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.GLYPH-PLAN _RTE-LP.REGION-X @ 0<> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.GLYPH-PLAN _RTE-LP.REGION-Y @ 0<> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.GLYPH-PLAN _RTE-LP.REGION-COLS @
        _RTHP-X-P @ _RTHP.COLS @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.GLYPH-PLAN _RTE-LP.REGION-ROWS @
        _RTHP-X-P @ _RTHP.ROWS @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.GLYPH-PLAN _RTE-LP.CLIP-X @
    _RTHP-X-P @ _RTHP.GLYPH-PLAN _RTE-LP.CLIP-Y @ OR
    _RTHP-X-P @ _RTHP.GLYPH-PLAN _RTE-LP.CLIP-COLS @ OR
    _RTHP-X-P @ _RTHP.GLYPH-PLAN _RTE-LP.CLIP-ROWS @ OR IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.GLYPH-PLAN _RTE-LP.REGION-Z @
        _RTHP-X-P @ _RTHP-BASE-Z-FIXED? 0= IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.GLYPH-PLAN _RTE-LP.REGION-FLAGS @
        RTE-REGION-VISIBLE <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.GLYPH-PLAN _RTE-LP.ITEMS-A @
        _RTHP-X-P @ _RTHP.GLYPH-ITEMS-A @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.GLYPH-PLAN _RTE-LP.ITEMS-U @
        _RTHP-X-P @ _RTHP.GLYPH-COUNT @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE * <>
        IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.GLYPH-PLAN _RTE-LP.RESERVED @ 0<> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.GLYPH-PLAN @
        _RTHP-X-P @ _RTHP.GLYPH-PLAN <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.GLYPH-REFS-A @
        _RTHP-X-P @ _RTHP.GLYPH-REFS-A @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.GLYPH-REFS-U @
        _RTHP-X-P @ _RTHP.GLYPH-COUNT @ RGRP-TEXT-REF-SIZE * <>
        IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.GLYPH-TEXT-A @
        _RTHP-X-P @ _RTHP.GLYPH-TEXT-A @ <> IF 0 EXIT THEN
    _RTHP-X-P @ _RTHP.HYBRID _RTE-HP.GLYPH-TEXT-U @
        _RTHP-X-P @ _RTHP.GLYPH-TEXT-USED @ = ;

: _RTHP-FIXED?  ( producer -- flag )
    _RTHP-X-P ! _RTHP-FIXED-BODY?
    _RTHP-X-I-CLEAR 0 _RTHP-X-P ! ;

VARIABLE _RTHP-E-P
VARIABLE _RTHP-E-ITEM
VARIABLE _RTHP-E-REF
VARIABLE _RTHP-E-TEXT
VARIABLE _RTHP-E-ALIGNED
VARIABLE _RTHP-E-MAX
VARIABLE _RTHP-E-LAST
VARIABLE _RTHP-E-NEXT
VARIABLE _RTHP-E-FIELDS
VARIABLE _RTHP-E-COLLECTIONS
VARIABLE _RTHP-E-CONTENT-ITEMS
VARIABLE _RTHP-E-CONTROL-UTF8
VARIABLE _RTHP-TW-A
VARIABLE _RTHP-TW-U
VARIABLE _RTHP-TW-BASE
VARIABLE _RTHP-TW-TOTAL

: _RTHP-TEXT-WITHIN?  ( a u base total -- flag )
    _RTHP-TW-TOTAL ! _RTHP-TW-BASE ! _RTHP-TW-U ! _RTHP-TW-A !
    _RTHP-TW-U @ 0= IF -1 EXIT THEN
    _RTHP-TW-A @ _RTHP-TW-U @ MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    _RTHP-TW-BASE @ _RTHP-TW-TOTAL @ MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    _RTHP-TW-A @ _RTHP-TW-BASE @ U< IF 0 EXIT THEN
    _RTHP-TW-A @ _RTHP-TW-U @ +
    _RTHP-TW-BASE @ _RTHP-TW-TOTAL @ + U> 0= ;

\ ---------------------------------------------------------------------
\  Compact ACK-baseline DELTA comparison
\ ---------------------------------------------------------------------
\
\  These address words are used only after both target-bank headers, validity
\  magic, and exact PACKED-BYTES lengths have been checked.  They do not borrow
\  the packing scratch variables: validation clears those variables before it
\  returns, while a delta must hold two immutable layouts at once.

: _RTHP-D-PACK-A  ( bank -- a )
    DUP _RTHP-TB.COUNT @ _RTHP-TARGET-ENTRY-SIZE *
    _RTHP-TARGET-BANK-HEADER-SIZE + + ;

: _RTHP-D-CONTROLS-A  ( bank -- a )  _RTHP-D-PACK-A ;

: _RTHP-D-CORR-A  ( bank -- a )
    DUP _RTHP-D-CONTROLS-A SWAP _RTHP-TB.CONTROL-COUNT @
        RTE-CONTROL-SIZE * + ;

: _RTHP-D-SOURCE-A  ( bank -- a )
    DUP _RTHP-D-CORR-A SWAP _RTHP-TB.CONTROL-COUNT @
        RUCP-CORRELATION-SIZE * + ;

: _RTHP-D-ITEMS-A  ( bank -- a )
    DUP _RTHP-D-SOURCE-A SWAP _RTHP-TB.SOURCE-TEXT-USED @
        _RTHP-ALIGN8? DROP + ;

: _RTHP-D-REFS-A  ( bank -- a )
    DUP _RTHP-D-ITEMS-A SWAP _RTHP-TB.GLYPH-SLOT-COUNT @
        RTE-GLYPH-RUN-PLAN-ITEM-SIZE * + ;

: _RTHP-D-GLYPH-A  ( bank -- a )
    DUP _RTHP-D-REFS-A SWAP _RTHP-TB.GLYPH-SLOT-COUNT @
        RGRP-TEXT-REF-SIZE * + ;

: _RTHP-D-CONTROL-AT  ( index bank -- control )
    _RTHP-D-CONTROLS-A SWAP RTE-CONTROL-SIZE * + ;

: _RTHP-D-CORR-AT  ( index bank -- correlation )
    _RTHP-D-CORR-A SWAP RUCP-CORRELATION-SIZE * + ;

: _RTHP-D-ITEM-AT  ( index bank -- item )
    _RTHP-D-ITEMS-A SWAP RTE-GLYPH-RUN-PLAN-ITEM-SIZE * + ;

: _RTHP-D-REF-AT  ( index bank -- ref )
    _RTHP-D-REFS-A SWAP RGRP-TEXT-REF-SIZE * + ;

VARIABLE _RTHP-D-P
VARIABLE _RTHP-D-ACTIVE
VARIABLE _RTHP-D-PENDING
VARIABLE _RTHP-D-I
VARIABLE _RTHP-D-ACTIVE-C
VARIABLE _RTHP-D-PENDING-C
VARIABLE _RTHP-D-CONTROL-ORDINAL
VARIABLE _RTHP-D-ACTIVE-X
VARIABLE _RTHP-D-PENDING-X
VARIABLE _RTHP-D-ACTIVE-I
VARIABLE _RTHP-D-PENDING-I
VARIABLE _RTHP-D-ACTIVE-R
VARIABLE _RTHP-D-PENDING-R
VARIABLE _RTHP-D-ACTIVE-FIRST
VARIABLE _RTHP-D-PENDING-FIRST
VARIABLE _RTHP-D-EXPECTED-A
VARIABLE _RTHP-D-EXPECTED-P
VARIABLE _RTHP-D-OFFSET-A
VARIABLE _RTHP-D-OFFSET-P
VARIABLE _RTHP-D-OPS
VARIABLE _RTHP-D-EMITTED
VARIABLE _RTHP-D-CHANGED
VARIABLE _RTHP-D-PLAN-CONTROLS
VARIABLE _RTHP-D-PLAN-GLYPHS
VARIABLE _RTHP-D-MATCHED
VARIABLE _RTHP-D-CONTROL-MAP-VALUE
VARIABLE _RTHP-D-PLAN-MAP-VALUE
VARIABLE _RTHP-D-PLAN-DEFINE
VARIABLE _RTHP-D-PLAN-LAST-DEFINE
VARIABLE _RTHP-D-CI-X1
VARIABLE _RTHP-D-CI-X2

: _RTHP-D-CONTROL-MAP-AT  ( pending-control-ordinal -- a )
    8 * _RTHP-D-P @ _RTHP.ORDER2-A @ + ;

: _RTHP-D-PLAN-CONTROL-AT  ( plan-index -- control-index definition? )
    _RTHP-D-CONTROL-MAP-AT @
    DUP 1 AND SWAP 2/ SWAP ;

VARIABLE _RTHP-D-T1-A
VARIABLE _RTHP-D-T1-U
VARIABLE _RTHP-D-T1-BASE
VARIABLE _RTHP-D-T1-TOTAL
VARIABLE _RTHP-D-T2-A
VARIABLE _RTHP-D-T2-U
VARIABLE _RTHP-D-T2-BASE
VARIABLE _RTHP-D-T2-TOTAL

: _RTHP-D-TEXTS-EQUAL?
  ( a1 u1 base1 total1 a2 u2 base2 total2 -- flag )
    _RTHP-D-T2-TOTAL ! _RTHP-D-T2-BASE !
    _RTHP-D-T2-U ! _RTHP-D-T2-A !
    _RTHP-D-T1-TOTAL ! _RTHP-D-T1-BASE !
    _RTHP-D-T1-U ! _RTHP-D-T1-A !
    _RTHP-D-T1-A @ _RTHP-D-T1-U @
        _RTHP-D-T1-BASE @ _RTHP-D-T1-TOTAL @ _RTHP-TEXT-WITHIN?
        0= IF 0 EXIT THEN
    _RTHP-D-T2-A @ _RTHP-D-T2-U @
        _RTHP-D-T2-BASE @ _RTHP-D-T2-TOTAL @ _RTHP-TEXT-WITHIN?
        0= IF 0 EXIT THEN
    _RTHP-D-T1-U @ _RTHP-D-T2-U @ <> IF 0 EXIT THEN
    _RTHP-D-T1-U @ 0= IF -1 EXIT THEN
    _RTHP-D-T1-A @ _RTHP-D-T1-U @
    _RTHP-D-T2-A @ _RTHP-D-T2-U @ COMPARE 0= ;

\ Reuse the exact acknowledged instrument graph while controls/glyphs change.
\ The canonical planner supplies source-order identities. A topology, source
\ generation, region, style, value, or unit change still requires START. IDs
\ alone may differ in a fresh candidate; delayed plans require normalized IDs.
VARIABLE _RTHP-IR-A
VARIABLE _RTHP-IR-P
VARIABLE _RTHP-IR-NORMALIZED
VARIABLE _RTHP-IR-OLD
VARIABLE _RTHP-IR-NEW
VARIABLE _RTHP-IR-XOLD
VARIABLE _RTHP-IR-XNEW
VARIABLE _RTHP-IR-REGION

: _RTHP-IR-EQUAL?  ( a1 a2 bytes -- flag )
    DUP >R SWAP R> COMPARE 0= ;

VARIABLE _RTHP-YR-A
VARIABLE _RTHP-YR-P
VARIABLE _RTHP-YR-NORMALIZED
VARIABLE _RTHP-YR-OLD
VARIABLE _RTHP-YR-NEW
VARIABLE _RTHP-YR-XOLD
VARIABLE _RTHP-YR-XNEW
VARIABLE _RTHP-YR-OFF
VARIABLE _RTHP-YR-REGION

: _RTHP-YR-ITEM? ( index -- flag )
    DUP >R
    _RTHP-YR-A @ _RTHP-PACK-SERIES-A SWAP RTE-SERIES-SIZE * + _RTHP-YR-OLD !
    _RTHP-YR-P @ _RTHP-PACK-SERIES-A R@ RTE-SERIES-SIZE * + _RTHP-YR-NEW !
    _RTHP-YR-A @ _RTHP-PACK-SERIES-CORR-A R@ _RTHP-SERIES-CORR-SIZE * + _RTHP-YR-XOLD !
    _RTHP-YR-P @ _RTHP-PACK-SERIES-CORR-A R@ _RTHP-SERIES-CORR-SIZE * + _RTHP-YR-XNEW !
    _RTHP-YR-A @ _RTHP-TB.FIRST-SERIES @ R@ +
        _RTHP-YR-OLD @ _RTE-SERIES.ID @ <> IF R> DROP 0 EXIT THEN
    _RTHP-YR-P @ _RTHP-TB.FIRST-SERIES @ R> +
        _RTHP-YR-NEW @ _RTE-SERIES.ID @ <> IF 0 EXIT THEN
    _RTHP-YR-OLD @ _RTHP-YR-NEW @ 16 _RTHP-IR-EQUAL? 0= IF 0 EXIT THEN
    _RTHP-YR-OLD @ 24 + _RTHP-YR-NEW @ 24 + RTE-SERIES-SIZE 24 -
        _RTHP-IR-EQUAL? 0= IF 0 EXIT THEN
    _RTHP-YR-XOLD @ _RTHP-YR-XNEW @ 56 _RTHP-IR-EQUAL? 0= IF 0 EXIT THEN
    _RTHP-YR-XOLD @ 72 + @ _RTHP-YR-XNEW @ 72 + @ OR IF 0 EXIT THEN
    _RTHP-YR-XOLD @ 64 + @ _RTHP-YR-OLD @ _RTE-SERIES.ID @ <>
    _RTHP-YR-XNEW @ 64 + @ _RTHP-YR-NEW @ _RTE-SERIES.ID @ <> OR IF 0 EXIT THEN
    _RTHP-YR-XOLD @ 56 + @ _RTHP-YR-XNEW @ 56 + @ OR IF
        _RTHP-YR-XOLD @ 56 + @ _RTHP-YR-A @ _RTHP-TB.REGION @ - DUP _RTHP-YR-REGION !
        DUP 0= SWAP _RTHP-YR-A @ _RTHP-TB.INSTRUMENT-REGION-COUNT @ U> OR IF 0 EXIT THEN
        _RTHP-YR-XNEW @ 56 + @ _RTHP-YR-P @ _RTHP-TB.REGION @ -
            _RTHP-YR-REGION @ <> IF 0 EXIT THEN
    THEN
    _RTHP-YR-NORMALIZED @ IF
        _RTHP-YR-OLD @ _RTE-SERIES.ID @ _RTHP-YR-NEW @ _RTE-SERIES.ID @ <>
        _RTHP-YR-XOLD @ 56 + @ _RTHP-YR-XNEW @ 56 + @ <> OR IF 0 EXIT THEN
    THEN
    _RTHP-YR-NEW @ _RTE-SERIES.SAMPLES-U @ IF
        _RTHP-YR-NEW @ _RTE-SERIES.SAMPLES-A @ _RTHP-YR-OFF @ <> IF 0 EXIT THEN
    ELSE
        _RTHP-YR-NEW @ _RTE-SERIES.SAMPLES-A @ IF 0 EXIT THEN
    THEN
    _RTHP-YR-OFF @ _RTHP-YR-NEW @ _RTE-SERIES.SAMPLES-U @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-YR-P @ _RTHP-TB.SERIES-SAMPLE-BYTES @ U> IF DROP 0 EXIT THEN
        _RTHP-YR-OFF ! -1 ;

: _RTHP-SERIES-REUSABLE? ( active pending normalized? -- flag )
    _RTHP-YR-NORMALIZED ! _RTHP-YR-P ! _RTHP-YR-A !
    _RTHP-YR-A @ _RTHP-TB.SERIES-COUNT @
        _RTHP-YR-P @ _RTHP-TB.SERIES-COUNT @ <> IF 0 EXIT THEN
    _RTHP-YR-A @ _RTHP-TB.SERIES-SAMPLE-BYTES
        _RTHP-YR-P @ _RTHP-TB.SERIES-SAMPLE-BYTES 7 8 * _RTHP-IR-EQUAL? 0= IF 0 EXIT THEN
    0 _RTHP-YR-OFF !
    _RTHP-YR-A @ _RTHP-TB.SERIES-COUNT @ 0 ?DO
        I _RTHP-YR-ITEM? 0= IF 0 UNLOOP EXIT THEN
    LOOP
    _RTHP-YR-OFF @ _RTHP-YR-P @ _RTHP-TB.SERIES-SAMPLE-BYTES @ <> IF 0 EXIT THEN
    _RTHP-YR-A @ _RTHP-PACK-SERIES-SAMPLES-A
    _RTHP-YR-P @ _RTHP-PACK-SERIES-SAMPLES-A
    _RTHP-YR-OFF @ _RTHP-IR-EQUAL? ;

: _RTHP-SERIES-NORMALIZE ( active pending -- )
    _RTHP-YR-P ! _RTHP-YR-A !
    _RTHP-YR-A @ _RTHP-TB.SERIES-COUNT @ 0 ?DO
        _RTHP-YR-A @ _RTHP-PACK-SERIES-A I RTE-SERIES-SIZE * + _RTE-SERIES.ID @
        _RTHP-YR-P @ _RTHP-PACK-SERIES-A I RTE-SERIES-SIZE * + _RTE-SERIES.ID !
        _RTHP-YR-A @ _RTHP-PACK-SERIES-CORR-A I _RTHP-SERIES-CORR-SIZE * + 56 +
        _RTHP-YR-P @ _RTHP-PACK-SERIES-CORR-A I _RTHP-SERIES-CORR-SIZE * + 56 + 16 MOVE
    LOOP
    _RTHP-YR-A @ _RTHP-TB.FIRST-SERIES @ _RTHP-YR-P @ _RTHP-TB.FIRST-SERIES ! ;

: _RTHP-IR-SERIES? ( -- flag )
    _RTHP-IR-OLD @ _RTE-INSTRUMENT.KIND @ DUP RTE-INSTRUMENT-WAVEFORM <>
    SWAP RTE-INSTRUMENT-PLOT <> AND IF
        _RTHP-IR-OLD @ _RTE-INSTRUMENT.SERIES-ID @
        _RTHP-IR-NEW @ _RTE-INSTRUMENT.SERIES-ID @ OR 0= EXIT
    THEN
    _RTHP-IR-OLD @ _RTE-INSTRUMENT.SERIES-ID @
        _RTHP-IR-A @ _RTHP-TB.FIRST-SERIES @ - DUP
        _RTHP-IR-A @ _RTHP-TB.SERIES-COUNT @ U< 0= IF DROP 0 EXIT THEN
    _RTHP-IR-NEW @ _RTE-INSTRUMENT.SERIES-ID @
        _RTHP-IR-P @ _RTHP-TB.FIRST-SERIES @ - <> IF 0 EXIT THEN
    _RTHP-IR-NORMALIZED @ IF
        _RTHP-IR-OLD @ _RTE-INSTRUMENT.SERIES-ID @
        _RTHP-IR-NEW @ _RTE-INSTRUMENT.SERIES-ID @ =
    ELSE -1 THEN ;

: _RTHP-IR-REGIONS?  ( -- flag )
    _RTHP-IR-A @ _RTHP-TB.INSTRUMENT-REGION-COUNT @ 0 ?DO
        _RTHP-IR-A @ _RTHP-PACK-INSTRUMENT-REGIONS-A
            I RTE-INSTRUMENT-REGION-SIZE * + _RTHP-IR-OLD !
        _RTHP-IR-P @ _RTHP-PACK-INSTRUMENT-REGIONS-A
            I RTE-INSTRUMENT-REGION-SIZE * + _RTHP-IR-NEW !
        _RTHP-IR-OLD @ 8 + _RTHP-IR-NEW @ 8 +
            RTE-INSTRUMENT-REGION-SIZE 8 - _RTHP-IR-EQUAL?
            0= IF 0 UNLOOP EXIT THEN
        _RTHP-IR-A @ _RTHP-TB.REGION @ I 1+ _RTHP-U+?
            0= IF DROP 0 UNLOOP EXIT THEN
        _RTHP-IR-OLD @ _RTE-IR.ID @ <> IF 0 UNLOOP EXIT THEN
        _RTHP-IR-P @ _RTHP-TB.REGION @ I 1+ _RTHP-U+?
            0= IF DROP 0 UNLOOP EXIT THEN
        _RTHP-IR-NEW @ _RTE-IR.ID @ <> IF 0 UNLOOP EXIT THEN
        _RTHP-IR-NORMALIZED @ IF
            _RTHP-IR-OLD @ @ _RTHP-IR-NEW @ @ <> IF 0 UNLOOP EXIT THEN
        THEN
    LOOP -1 ;

: _RTHP-IR-ITEM?  ( -- flag )
    _RTHP-IR-OLD @ _RTHP-IR-NEW @ 16 _RTHP-IR-EQUAL? 0= IF 0 EXIT THEN
    _RTHP-IR-OLD @ 24 + _RTHP-IR-NEW @ 24 + 24 _RTHP-IR-EQUAL?
        0= IF 0 EXIT THEN
    _RTHP-IR-OLD @ 56 + _RTHP-IR-NEW @ 56 +
        208 56 - _RTHP-IR-EQUAL? 0= IF 0 EXIT THEN
    _RTHP-IR-SERIES? 0= IF 0 EXIT THEN
    _RTHP-IR-XOLD @ _RTHP-IR-XNEW @ 56 _RTHP-IR-EQUAL? 0= IF 0 EXIT THEN
    _RTHP-IR-XOLD @ _RUIP-X.RESERVED @
        _RTHP-IR-XNEW @ _RUIP-X.RESERVED @ OR IF 0 EXIT THEN
    _RTHP-IR-OLD @ _RTE-INSTRUMENT.ID @ DUP 0= IF DROP 0 EXIT THEN
        _RTHP-IR-XOLD @ _RUIP-X.INSTRUMENT-ID @ <> IF 0 EXIT THEN
    _RTHP-IR-NEW @ _RTE-INSTRUMENT.ID @ DUP 0= IF DROP 0 EXIT THEN
        _RTHP-IR-XNEW @ _RUIP-X.INSTRUMENT-ID @ <> IF 0 EXIT THEN
    _RTHP-IR-OLD @ _RTE-INSTRUMENT.REGION @ DUP
        _RTHP-IR-XOLD @ _RUIP-X.REGION-ID @ <> IF DROP 0 EXIT THEN
    _RTHP-IR-A @ _RTHP-TB.REGION @ - DUP _RTHP-IR-REGION !
        0= IF 0 EXIT THEN
    _RTHP-IR-REGION @
        _RTHP-IR-A @ _RTHP-TB.INSTRUMENT-REGION-COUNT @ U> IF 0 EXIT THEN
    _RTHP-IR-NEW @ _RTE-INSTRUMENT.REGION @ DUP
        _RTHP-IR-XNEW @ _RUIP-X.REGION-ID @ <> IF DROP 0 EXIT THEN
    _RTHP-IR-P @ _RTHP-TB.REGION @ - _RTHP-IR-REGION @ <> IF 0 EXIT THEN
    _RTHP-IR-NORMALIZED @ IF
        _RTHP-IR-OLD @ _RTE-INSTRUMENT.ID @
            _RTHP-IR-NEW @ _RTE-INSTRUMENT.ID @ <> IF 0 EXIT THEN
        _RTHP-IR-OLD @ _RTE-INSTRUMENT.REGION @
            _RTHP-IR-NEW @ _RTE-INSTRUMENT.REGION @ <> IF 0 EXIT THEN
    THEN
    _RTHP-IR-NEW @ _RTE-INSTRUMENT.UNIT-A @ DUP
        _RTHP-IR-P @ _RTHP-TB.INSTRUMENT-UNIT-BYTES @ U> IF DROP 0 EXIT THEN
    _RTHP-IR-P @ _RTHP-TB.INSTRUMENT-UNIT-BYTES @ SWAP -
        _RTHP-IR-NEW @ _RTE-INSTRUMENT.UNIT-U @ U< 0= ;

: _RTHP-INSTRUMENTS-REUSABLE?  ( active pending normalized? -- flag )
    _RTHP-IR-NORMALIZED ! _RTHP-IR-P ! _RTHP-IR-A !
    _RTHP-IR-A @ _RTHP-IR-P @ _RTHP-IR-NORMALIZED @
        _RTHP-SERIES-REUSABLE? 0= IF 0 EXIT THEN
    _RTHP-IR-A @ _RTHP-TB.INSTRUMENT-COUNT @
        _RTHP-IR-P @ _RTHP-TB.INSTRUMENT-COUNT @ <>
    _RTHP-IR-A @ _RTHP-TB.INSTRUMENT-REGION-COUNT @
        _RTHP-IR-P @ _RTHP-TB.INSTRUMENT-REGION-COUNT @ <> OR
    _RTHP-IR-A @ _RTHP-TB.INSTRUMENT-UNIT-BYTES @
        _RTHP-IR-P @ _RTHP-TB.INSTRUMENT-UNIT-BYTES @ <> OR IF 0 EXIT THEN
    _RTHP-IR-REGIONS? 0= IF 0 EXIT THEN
    _RTHP-IR-A @ _RTHP-TB.INSTRUMENT-COUNT @ 0 ?DO
        _RTHP-IR-A @ _RTHP-PACK-INSTRUMENTS-A I RTE-INSTRUMENT-SIZE * +
            _RTHP-IR-OLD !
        _RTHP-IR-P @ _RTHP-PACK-INSTRUMENTS-A I RTE-INSTRUMENT-SIZE * +
            _RTHP-IR-NEW !
        _RTHP-IR-A @ _RTHP-PACK-INSTRUMENT-CORR-A I RUIP-CORRELATION-SIZE * +
            _RTHP-IR-XOLD !
        _RTHP-IR-P @ _RTHP-PACK-INSTRUMENT-CORR-A I RUIP-CORRELATION-SIZE * +
            _RTHP-IR-XNEW !
        _RTHP-IR-ITEM? 0= IF 0 UNLOOP EXIT THEN
    LOOP
    _RTHP-IR-A @ _RTHP-PACK-INSTRUMENT-UNITS-A
    _RTHP-IR-P @ _RTHP-PACK-INSTRUMENT-UNITS-A
    _RTHP-IR-P @ _RTHP-TB.INSTRUMENT-UNIT-BYTES @ _RTHP-IR-EQUAL? ;

: _RTHP-INSTRUMENTS-NORMALIZE  ( active pending -- )
    2DUP _RTHP-SERIES-NORMALIZE
    _RTHP-IR-P ! _RTHP-IR-A !
    _RTHP-IR-A @ _RTHP-TB.INSTRUMENT-REGION-COUNT @ 0 ?DO
        _RTHP-IR-A @ _RTHP-PACK-INSTRUMENT-REGIONS-A
            I RTE-INSTRUMENT-REGION-SIZE * + @
        _RTHP-IR-P @ _RTHP-PACK-INSTRUMENT-REGIONS-A
            I RTE-INSTRUMENT-REGION-SIZE * + !
    LOOP
    _RTHP-IR-A @ _RTHP-TB.INSTRUMENT-COUNT @ 0 ?DO
        _RTHP-IR-A @ _RTHP-PACK-INSTRUMENTS-A I RTE-INSTRUMENT-SIZE * +
            _RTHP-IR-OLD !
        _RTHP-IR-P @ _RTHP-PACK-INSTRUMENTS-A I RTE-INSTRUMENT-SIZE * +
            _RTHP-IR-NEW !
        _RTHP-IR-OLD @ _RTE-INSTRUMENT.SERIES-ID @
            _RTHP-IR-NEW @ _RTE-INSTRUMENT.SERIES-ID !
        _RTHP-IR-OLD @ _RTE-INSTRUMENT.ID @
            _RTHP-IR-NEW @ _RTE-INSTRUMENT.ID !
        _RTHP-IR-OLD @ _RTE-INSTRUMENT.REGION @
            _RTHP-IR-NEW @ _RTE-INSTRUMENT.REGION !
        _RTHP-IR-A @ _RTHP-PACK-INSTRUMENT-CORR-A
            I RUIP-CORRELATION-SIZE * + _RUIP-X.REGION-ID
        _RTHP-IR-P @ _RTHP-PACK-INSTRUMENT-CORR-A
            I RUIP-CORRELATION-SIZE * + _RUIP-X.REGION-ID 16 MOVE
    LOOP ;

\ The active bank's kept facts apply only to that exact bank at its exact
\ glyph and control counts.  Otherwise this comparison derives them afresh.

\ Status is noninteractive.  A DELTA keeps the whole static lane when its
\ frozen ordinary identity, geometry and roles match; each field's severity,
\ emphasis, label and value may change and are then replaced.
\ Changed status uses the existing complete replacement transaction.
VARIABLE _RTHP-SR-A
VARIABLE _RTHP-SR-P
VARIABLE _RTHP-SR-OLD
VARIABLE _RTHP-SR-NEW
VARIABLE _RTHP-SR-NORMALIZED

: _RTHP-STATICS-REUSABLE? ( active pending normalized? -- flag )
    _RTHP-SR-NORMALIZED ! _RTHP-SR-P ! _RTHP-SR-A !
    _RTHP-SR-A @ _RTHP-TB.STATIC-COUNT @
        _RTHP-SR-P @ _RTHP-TB.STATIC-COUNT @ <> IF 0 EXIT THEN
    _RTHP-SR-A @ _RTHP-PACK-STATIC-CORR-A
    _RTHP-SR-P @ _RTHP-PACK-STATIC-CORR-A
    _RTHP-SR-A @ _RTHP-TB.STATIC-COUNT @ _RTHP-STATIC-CORR-SIZE *
        _RTHP-IR-EQUAL? 0= IF 0 EXIT THEN
    _RTHP-SR-A @ _RTHP-TB.STATIC-COUNT @ 0 ?DO
        _RTHP-SR-A @ _RTHP-PACK-STATICS-A I RTE-STATIC-SIZE * + _RTHP-SR-OLD !
        _RTHP-SR-P @ _RTHP-PACK-STATICS-A I RTE-STATIC-SIZE * + _RTHP-SR-NEW !
        _RTHP-SR-OLD @ _RTHP-SR-NEW @ 16 _RTHP-IR-EQUAL? 0= IF 0 UNLOOP EXIT THEN
        _RTHP-SR-OLD @ 24 + _RTHP-SR-NEW @ 24 + 24 _RTHP-IR-EQUAL? 0=
            IF 0 UNLOOP EXIT THEN
        _RTHP-SR-OLD @ 56 + _RTHP-SR-NEW @ 56 + 0 _RTE-STATIC.SEVERITY 56 -
            _RTHP-IR-EQUAL? 0= IF 0 UNLOOP EXIT THEN
        \ A picture shown through another clip has moved, as one moved has.
        _RTHP-SR-OLD @ _RTE-STATIC.CLIP-X _RTHP-SR-NEW @ _RTE-STATIC.CLIP-X
            RTE-STATIC-SIZE 0 _RTE-STATIC.CLIP-X - _RTHP-IR-EQUAL? 0= IF
            0 UNLOOP EXIT
        THEN
        _RTHP-SR-OLD @ _RTE-STATIC.ID @ 0=
        _RTHP-SR-NEW @ _RTE-STATIC.ID @ 0= OR IF 0 UNLOOP EXIT THEN
        _RTHP-SR-OLD @ _RTE-STATIC.REGION @ _RTHP-SR-A @ _RTHP-TB.REGION @ <>
        _RTHP-SR-NEW @ _RTE-STATIC.REGION @ _RTHP-SR-P @ _RTHP-TB.REGION @ <> OR
            IF 0 UNLOOP EXIT THEN
        _RTHP-SR-NORMALIZED @ IF
            _RTHP-SR-OLD @ _RTE-STATIC.ID @ _RTHP-SR-NEW @ _RTE-STATIC.ID @ <>
                IF 0 UNLOOP EXIT THEN
        THEN
    LOOP -1 ;

: _RTHP-STATICS-NORMALIZE ( active pending -- )
    _RTHP-SR-P ! _RTHP-SR-A !
    _RTHP-SR-A @ _RTHP-TB.STATIC-COUNT @ 0 ?DO
        _RTHP-SR-A @ _RTHP-PACK-STATICS-A I RTE-STATIC-SIZE * + _RTHP-SR-OLD !
        _RTHP-SR-P @ _RTHP-PACK-STATICS-A I RTE-STATIC-SIZE * + _RTHP-SR-NEW !
        _RTHP-SR-OLD @ _RTE-STATIC.ID @ _RTHP-SR-NEW @ _RTE-STATIC.ID !
        _RTHP-SR-OLD @ _RTE-STATIC.REGION @ _RTHP-SR-NEW @ _RTE-STATIC.REGION !
    LOOP ;

VARIABLE _RTHP-D-KEPT

: _RTHP-D-KEPT?  ( -- flag )
    _RTHP-D-P @ _RTHP.ACTIVE-FACTS
    DUP _RTHP-KF.BANK @ _RTHP-D-ACTIVE @ <> IF DROP 0 EXIT THEN
    DUP _RTHP-KF.SLOTS @
        _RTHP-D-ACTIVE @ _RTHP-TB.GLYPH-SLOT-COUNT @ <> IF DROP 0 EXIT THEN
    _RTHP-KF.CONTROLS @
        _RTHP-D-ACTIVE @ _RTHP-TB.CONTROL-COUNT @ = ;

\ Diagnostics: the check of the DELTA gate under way, so a refusal can say
\ which check refused it (_RTHP-DIAG-DELTA-WHY counts them).
VARIABLE _RTHP-D-WHY

\ ---------------------------------------------------------------------
\  The root facts' judge
\ ---------------------------------------------------------------------
\
\  With the shadow check on, a comparison whose two banks both keep root
\  facts judges them.  Every control and status field the comparison finds
\  new or changed belongs to a root whose facts moved since the bank on
\  screen, and instruments that differ belong to data-graphics roots of
\  which one moved; otherwise the facts missed a change, and the shadow
\  check counts a difference of its root-facts stage.  A comparison of two
\  banks built from one snapshot, or of a bank without facts, is not
\  judged.  The counts say how many comparisons were judged, how many
\  roots their pending banks held, how many of those changed or went, and
\  how many items were judged.  Pictures carry no facts yet, so the
\  statics that show them are not judged.

VARIABLE _RTHP-ROOT-OLD          \ block of the bank on screen, or 0
VARIABLE _RTHP-ROOT-NEW          \ block of the pending bank, or 0

VARIABLE _RTHP-DIAG-ROOT-FRAMES
VARIABLE _RTHP-DIAG-ROOT-ROOTS
VARIABLE _RTHP-DIAG-ROOT-CHANGED
VARIABLE _RTHP-DIAG-ROOT-ITEMS

\ The identity sought.
VARIABLE _RTHP-ROOT-K-TOKEN
VARIABLE _RTHP-ROOT-K-FAMILY
VARIABLE _RTHP-ROOT-K-SOURCE
VARIABLE _RTHP-ROOT-K-INDEX
VARIABLE _RTHP-ROOT-K-GEN
VARIABLE _RTHP-ROOT-K-KEY

: _RTHP-ROOT-FIND-BLOCK  ( generation -- block|0 )
    DUP 0= IF EXIT THEN
    DUP 1 _RTHP-ROOT.GEN @ = IF DROP 1 EXIT THEN
    2 _RTHP-ROOT.GEN @ = IF 2 ELSE 0 THEN ;

: _RTHP-ROOT-RECORD-AT  ( index block -- record )
    _RTHP-ROOT.A @ SWAP URF-SIZE * + ;

: _RTHP-ROOT-IS?  ( record -- flag )
    DUP URF.TOKEN @ _RTHP-ROOT-K-TOKEN @ <> IF DROP 0 EXIT THEN
    _RTHP-ROOT-K-FAMILY @ _RTHP-ROOT-K-SOURCE @ _RTHP-ROOT-K-INDEX @
    _RTHP-ROOT-K-GEN @ _RTHP-ROOT-K-KEY @ URF-ROOT? ;

\ The record in BLOCK naming the identity sought, trying index HINT first,
\ since the roots of two banks mostly lie in the same order.
: _RTHP-ROOT-FIND  ( hint block -- record|0 )
    OVER 0 MAX OVER _RTHP-ROOT.N @ < IF
        2DUP _RTHP-ROOT-RECORD-AT DUP _RTHP-ROOT-IS? IF NIP NIP EXIT THEN DROP
    THEN NIP
    DUP _RTHP-ROOT.N @ 0 ?DO
        I OVER _RTHP-ROOT-RECORD-AT DUP _RTHP-ROOT-IS? IF NIP UNLOOP EXIT THEN
        DROP
    LOOP DROP 0 ;

: _RTHP-ROOT-SEEK!  ( record -- )
    DUP URF.TOKEN @ _RTHP-ROOT-K-TOKEN !
    DUP URF.FAMILY @ _RTHP-ROOT-K-FAMILY !
    DUP URF.SOURCE @ _RTHP-ROOT-K-SOURCE !
    DUP URF.INDEX @ _RTHP-ROOT-K-INDEX !
    DUP URF.GENERATION @ _RTHP-ROOT-K-GEN !
    URF.KEY @ _RTHP-ROOT-K-KEY ! ;

\ Whether the root at INDEX of block FROM is not in block TO with the same
\ facts: it is new, it went, or its facts moved.
: _RTHP-ROOT-MOVED?  ( index from to -- flag )
    >R 2DUP _RTHP-ROOT-RECORD-AT DUP _RTHP-ROOT-SEEK!   ( index from record )
    NIP SWAP R> _RTHP-ROOT-FIND ?DUP 0= IF DROP -1 EXIT THEN
    URF-SAME? 0= ;

\ The roots of block FROM not in block TO with the same facts, of FAMILY,
\ or of every family when FAMILY is 0.
VARIABLE _RTHP-ROOT-FROM
VARIABLE _RTHP-ROOT-TO
VARIABLE _RTHP-ROOT-ONLY
: _RTHP-ROOT-MOVES  ( family from to -- count )
    _RTHP-ROOT-TO ! _RTHP-ROOT-FROM ! _RTHP-ROOT-ONLY !
    0 _RTHP-ROOT-FROM @ _RTHP-ROOT.N @ 0 ?DO
        _RTHP-ROOT-ONLY @ IF
            I _RTHP-ROOT-FROM @ _RTHP-ROOT-RECORD-AT URF.FAMILY @
                _RTHP-ROOT-ONLY @ =
        ELSE -1 THEN
        IF I _RTHP-ROOT-FROM @ _RTHP-ROOT-TO @ _RTHP-ROOT-MOVED? IF 1+ THEN THEN
    LOOP ;

\ Begin judging the comparison of PRODUCER's banks: find their facts, and
\ count the roots that changed or went.
: _RTHP-ROOT-BEGIN  ( producer -- )
    0 _RTHP-ROOT-OLD ! 0 _RTHP-ROOT-NEW !
    FSHD? 0= IF DROP EXIT THEN
    DUP _RTHP.TARGET-ACTIVE @ SWAP _RTHP.TARGET-PENDING @
    2DUP 0= SWAP 0= OR IF 2DROP EXIT THEN
    _RTHP-TB.SOURCE-GEN @ SWAP _RTHP-TB.SOURCE-GEN @     ( new-gen old-gen )
    2DUP = IF 2DROP EXIT THEN
    _RTHP-ROOT-FIND-BLOCK SWAP _RTHP-ROOT-FIND-BLOCK         ( old new )
    2DUP 0= SWAP 0= OR IF 2DROP EXIT THEN
    _RTHP-ROOT-NEW ! _RTHP-ROOT-OLD !
    1 _RTHP-DIAG-ROOT-FRAMES +!
    _RTHP-ROOT-NEW @ _RTHP-ROOT.N @ _RTHP-DIAG-ROOT-ROOTS +!
    \ The roots that are new or moved, and those that went.
    0 _RTHP-ROOT-NEW @ _RTHP-ROOT-OLD @ _RTHP-ROOT-MOVES
    0 _RTHP-ROOT-OLD @ _RTHP-ROOT.N @ 0 ?DO
        I _RTHP-ROOT-OLD @ _RTHP-ROOT-RECORD-AT _RTHP-ROOT-SEEK!
        I _RTHP-ROOT-NEW @ _RTHP-ROOT-FIND 0= IF 1+ THEN
    LOOP + _RTHP-DIAG-ROOT-CHANGED +! ;

\ The optional part a family's items make up, or 0 for menus.
: _RTHP-ROOT-PART  ( family -- part|0 )
    DUP URF-F-COLLECTION = IF DROP RTHP-PART-COLLECTIONS EXIT THEN
    DUP URF-F-FIELD = IF DROP RTHP-PART-FIELDS EXIT THEN
    DUP URF-F-DIALOG = IF DROP RTHP-PART-DIALOGS EXIT THEN
    DUP URF-F-STATUS-FIELD = IF DROP RTHP-PART-STATICS EXIT THEN
    URF-F-DATA-GRAPHICS = IF RTHP-PART-INSTRUMENTS ELSE 0 THEN ;

\ Whether the two banks differ in carrying the sought root's family: its
\ items then came or went with the family, which lowering, not the root,
\ decided, as when the terminal had no room for it before.
: _RTHP-ROOT-PART-MOVED?  ( -- flag )
    _RTHP-ROOT-K-FAMILY @ _RTHP-ROOT-PART
    _RTHP-ROOT-OLD @ _RTHP-ROOT.PARTS @ _RTHP-ROOT-NEW @ _RTHP-ROOT.PARTS @ XOR
    AND 0<> ;

\ Judge one item the comparison found new or changed, whose root is the
\ identity sought: held when that root is new, its facts moved, or its
\ family came with this bank.  ITEM numbers it, should it be the first
\ difference.
: _RTHP-ROOT-JUDGE  ( item -- )
    1 _RTHP-DIAG-ROOT-ITEMS +!
    0 _RTHP-ROOT-NEW @ _RTHP-ROOT-FIND ?DUP 0= IF
        0 SWAP FSHD-STAGE-ROOT-FACTS FSHD-HELD EXIT
    THEN
    0 _RTHP-ROOT-OLD @ _RTHP-ROOT-FIND ?DUP 0= IF
        DROP -1 SWAP FSHD-STAGE-ROOT-FACTS FSHD-HELD EXIT
    THEN
    URF-SAME? 0= _RTHP-ROOT-PART-MOVED? OR
    SWAP FSHD-STAGE-ROOT-FACTS FSHD-HELD ;

\ Seek the root of the pending bank's control INDEX, from its correlation
\ and kind; false for a control no document root projects.
: _RTHP-ROOT-CONTROL-ROOT?  ( index -- flag )
    _RTHP-D-PENDING @ _RTHP-PACK-CORR-A OVER RUCP-CORRELATION-SIZE * +
    DUP RUCP-CORRELATION-ATTACHMENT@ _RTHP-ROOT-K-TOKEN !
    DUP RUCP-CORRELATION-SOURCE@ _RTHP-ROOT-K-SOURCE !
    DUP RUCP-CORRELATION-INDEX@ _RTHP-ROOT-K-INDEX !
    DUP RUCP-CORRELATION-LIFECYCLE-GENERATION@ _RTHP-ROOT-K-GEN !
    DUP RUCP-CORRELATION-SUBKEY@ _RTHP-ROOT-K-KEY !
    SWAP _RTHP-D-PENDING @ _RTHP-PACK-CONTROLS-A SWAP RTE-CONTROL-SIZE * +
        _RTE-CONTROL.KIND @                           ( correlation kind )
    DUP RTE-CONTROL-MENU-BAR RTE-CONTROL-MENU-SEPARATOR 1+ WITHIN IF
        2DROP URF-F-MENUS _RTHP-ROOT-K-FAMILY !
        0 _RTHP-ROOT-K-SOURCE ! 0 _RTHP-ROOT-K-INDEX !
        0 _RTHP-ROOT-K-GEN ! 0 _RTHP-ROOT-K-KEY ! -1 EXIT
    THEN
    DUP RTE-CONTROL-TAB = IF
        DROP RUCP-CORRELATION-SCOPE@ _RTHP-ROOT-K-KEY !
        URF-F-COLLECTION _RTHP-ROOT-K-FAMILY ! -1 EXIT
    THEN
    NIP
    DUP RTE-CONTROL-TEXT-AREA = OVER RTE-CONTROL-TEXT-GRID = OR
    OVER RTE-CONTROL-TABSET = OR OVER RTE-CONTROL-ITEM-VIEW = OR
    OVER RTE-CONTROL-DOCUMENT = OR IF
        DROP URF-F-COLLECTION _RTHP-ROOT-K-FAMILY ! -1 EXIT
    THEN
    DUP RTE-CONTROL-FIELD = IF
        DROP URF-F-FIELD _RTHP-ROOT-K-FAMILY ! -1 EXIT
    THEN
    DUP RTE-CONTROL-DIALOG = SWAP RTE-CONTROL-BUTTON = OR IF
        URF-F-DIALOG _RTHP-ROOT-K-FAMILY !
        0 _RTHP-ROOT-K-INDEX ! 0 _RTHP-ROOT-K-GEN ! -1 EXIT
    THEN
    0 ;

: _RTHP-ROOT-JUDGE-CONTROL  ( index -- )
    _RTHP-ROOT-NEW @ 0= IF DROP EXIT THEN
    DUP _RTHP-ROOT-CONTROL-ROOT? IF _RTHP-ROOT-JUDGE ELSE DROP THEN ;

\ Seek the root of the pending bank's static INDEX: a status field's;
\ false for a picture's.
: _RTHP-ROOT-STATIC-ROOT?  ( index -- flag )
    _RTHP-D-PENDING @ _RTHP-PACK-STATICS-A OVER RTE-STATIC-SIZE * +
        _RTE-STATIC.KIND @ RTE-STATIC-STATUS-FIELD <> IF DROP 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-PACK-STATIC-CORR-A SWAP _RTHP-STATIC-CORR-SIZE * +
    DUP @ _RTHP-ROOT-K-TOKEN !
    URF-F-STATUS-FIELD _RTHP-ROOT-K-FAMILY !
    USFSN-SOURCE-UIDL _RTHP-ROOT-K-SOURCE !
    DUP 8 + @ _RTHP-ROOT-K-INDEX !
    DUP 16 + @ _RTHP-ROOT-K-GEN !
    24 + @ _RTHP-ROOT-K-KEY ! -1 ;

\ The comparison found instruments it cannot keep, which a DELTA never
\ carries: they must belong to a data-graphics root that changed or went.
: _RTHP-ROOT-INSTRUMENTS  ( -- )
    _RTHP-ROOT-NEW @ 0= IF EXIT THEN
    1 _RTHP-DIAG-ROOT-ITEMS +!
    URF-F-DATA-GRAPHICS _RTHP-ROOT-NEW @ _RTHP-ROOT-OLD @ _RTHP-ROOT-MOVES
    URF-F-DATA-GRAPHICS _RTHP-ROOT-OLD @ _RTHP-ROOT-NEW @ _RTHP-ROOT-MOVES OR
    0<> 131072 FSHD-STAGE-ROOT-FACTS FSHD-HELD ;

: _RTHP-D-BIND?  ( producer -- flag )
    0 _RTHP-D-KEPT !
    _RTHP-D-P !
    1 _RTHP-D-WHY !
    _RTHP-D-P @ _RTHP.TARGET-ACTIVE @ DUP 0= IF DROP 0 EXIT THEN
        _RTHP-D-ACTIVE !
    _RTHP-D-P @ _RTHP.TARGET-PENDING @ DUP 0= IF DROP 0 EXIT THEN
        _RTHP-D-PENDING !
    _RTHP-D-ACTIVE @ _RTHP-D-PENDING @ = IF 0 EXIT THEN
    2 _RTHP-D-WHY !
    _RTHP-D-ACTIVE @ _RTHP-D-P @ _RTHP-TARGET-BANK-HEADER?
        0= IF 0 EXIT THEN
    _RTHP-D-P @ _RTHP-ACTIVE-SEALED? 0= IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-D-P @ _RTHP-TARGET-BANK-HEADER?
        0= IF 0 EXIT THEN
    3 _RTHP-D-WHY !
    _RTHP-D-PENDING @ _RTHP-TB.SERIES-COUNT @
        _RTHP-D-P @ _RTHP.SERIES-COUNT @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.SERIES-SAMPLE-BYTES @
        _RTHP-D-P @ _RTHP.SERIES-SAMPLES-USED @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.SERIES-SLOTS @
        _RTHP-D-P @ _RTHP.SERIES-SLOTS @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.SERIES-CHUNKS @
        _RTHP-D-P @ _RTHP.SERIES-CHUNKS @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.SERIES-HISTORY-MAX @
        _RTHP-D-P @ _RTHP.SERIES-HISTORY-MAX @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.SERIES-CHUNK-MAX @
        _RTHP-D-P @ _RTHP.SERIES-CHUNK-MAX @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.SERIES-CHUNK-BYTES-MAX @
        _RTHP-D-P @ _RTHP.SERIES-CHUNK-BYTES-MAX @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.WAVEFORM-COUNT @
        _RTHP-D-P @ _RTHP.WAVEFORM-COUNT @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.SERIES-COUNT @ IF
        _RTHP-D-PENDING @ _RTHP-TB.FIRST-SERIES @ _RTHP-D-P @ _RTHP.FIRST-SERIES @ <> IF 0 EXIT THEN
    THEN
    4 _RTHP-D-WHY !
    _RTHP-D-PENDING @ _RTHP-TB.INSTRUMENT-COUNT @
        _RTHP-D-P @ _RTHP.INSTRUMENT-COUNT @ <>
    _RTHP-D-PENDING @ _RTHP-TB.INSTRUMENT-REGION-COUNT @
        _RTHP-D-P @ _RTHP.INSTRUMENT-REGION-COUNT @ <> OR
    _RTHP-D-PENDING @ _RTHP-TB.INSTRUMENT-UNIT-BYTES @
        _RTHP-D-P @ _RTHP.INSTRUMENT-UNITS-USED @ <> OR IF 0 EXIT THEN
    5 _RTHP-D-WHY !
    _RTHP-D-ACTIVE @ _RTHP-D-PENDING @
        _RTHP-D-P @ _RTHP.DELTA-PLAN-VALID @
        _RTHP-INSTRUMENTS-REUSABLE? 0= IF _RTHP-ROOT-INSTRUMENTS 0 EXIT THEN
    6 _RTHP-D-WHY !
    _RTHP-D-PENDING @ _RTHP-TB.STATIC-COUNT @
        _RTHP-D-P @ _RTHP.STATIC-COUNT @ <>
    _RTHP-D-PENDING @ _RTHP-TB.STATIC-TEXT-BYTES @
        _RTHP-D-P @ _RTHP.STATIC-TEXT-USED @ <> OR IF 0 EXIT THEN
    7 _RTHP-D-WHY !
    _RTHP-D-ACTIVE @ _RTHP-D-PENDING @
        _RTHP-D-P @ _RTHP.DELTA-PLAN-VALID @
        _RTHP-STATICS-REUSABLE? 0= IF 0 EXIT THEN

    8 _RTHP-D-WHY !
    _RTHP-D-ACTIVE @ _RTHP-TB.OWNER @
        _RTHP-D-P @ _RTHP.OWNER @ <>
    _RTHP-D-PENDING @ _RTHP-TB.OWNER @
        _RTHP-D-P @ _RTHP.OWNER @ <> OR IF 0 EXIT THEN
    _RTHP-D-ACTIVE @ _RTHP-TB.GENERATION @
        _RTHP-D-P @ _RTHP.OWNER-GEN @ <>
    _RTHP-D-PENDING @ _RTHP-TB.GENERATION @
        _RTHP-D-P @ _RTHP.OWNER-GEN @ <> OR IF 0 EXIT THEN
    _RTHP-D-ACTIVE @ _RTHP-TB.COLS @
        _RTHP-D-P @ _RTHP.COLS @ <>
    _RTHP-D-PENDING @ _RTHP-TB.COLS @
        _RTHP-D-P @ _RTHP.COLS @ <> OR IF 0 EXIT THEN
    _RTHP-D-ACTIVE @ _RTHP-TB.ROWS @
        _RTHP-D-P @ _RTHP.ROWS @ <>
    _RTHP-D-PENDING @ _RTHP-TB.ROWS @
        _RTHP-D-P @ _RTHP.ROWS @ <> OR IF 0 EXIT THEN
    _RTHP-D-ACTIVE @ _RTHP-TB.PHYSICAL-GEN @
        _RTHP-D-P @ _RTHP.PHYSICAL-GEN @ <>
    _RTHP-D-PENDING @ _RTHP-TB.PHYSICAL-GEN @
        _RTHP-D-P @ _RTHP.PHYSICAL-GEN @ <> OR IF 0 EXIT THEN
    _RTHP-D-ACTIVE @ _RTHP-TB.GLYPH-RUN-LIMIT @
        _RTHP-D-P @ _RTHP.LIMITS RTE-LIMITS-GLYPH-RUN-BYTES@ <>
    _RTHP-D-PENDING @ _RTHP-TB.GLYPH-RUN-LIMIT @
        _RTHP-D-P @ _RTHP.LIMITS RTE-LIMITS-GLYPH-RUN-BYTES@ <> OR IF
        0 EXIT
    THEN
    9 _RTHP-D-WHY !
    _RTHP-D-ACTIVE @ _RTHP-TB.DRAW @
        _RTHP-D-P @ _RTHP.ACTIVE-DRAW @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.DRAW @
        _RTHP-D-P @ _RTHP.SURFACE-GEN @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.SOURCE-GEN @
        _RTHP-D-P @ _RTHP.SOURCE-GEN @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.CONTENT-EPOCH @
        _RTHP-D-P @ _RTHP.SOURCE-CONTENT-EPOCH @ <> IF 0 EXIT THEN
    10 _RTHP-D-WHY !
    _RTHP-D-ACTIVE @ _RTHP-TB.CONTROL-COUNT @
        _RTHP-D-PENDING @ _RTHP-TB.CONTROL-COUNT @ U> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.CONTROL-COUNT @
        _RTHP-D-P @ _RTHP.CONTROL-COUNT @ <> IF 0 EXIT THEN
    _RTHP-D-ACTIVE @ _RTHP-TB.MENU-CONTROL-COUNT @
        _RTHP-D-PENDING @ _RTHP-TB.MENU-CONTROL-COUNT @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.MENU-CONTROL-COUNT @
        _RTHP-D-P @ _RTHP.MENU-CONTROL-COUNT @ <> IF 0 EXIT THEN
    11 _RTHP-D-WHY !
    _RTHP-D-ACTIVE @ _RTHP-TB.DOCUMENT-COUNT @
        _RTHP-D-PENDING @ _RTHP-TB.DOCUMENT-COUNT @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.DOCUMENT-COUNT @
        _RTHP-D-P @ _RTHP.DOCUMENT-COUNT @ <> IF 0 EXIT THEN
    12 _RTHP-D-WHY !
    _RTHP-D-ACTIVE @ _RTHP-TB.COLLECTION-COUNT @
        _RTHP-D-PENDING @ _RTHP-TB.COLLECTION-COUNT @ U> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.COLLECTION-COUNT @
        _RTHP-D-P @ _RTHP.COLLECTION-COUNT @ <> IF 0 EXIT THEN
    13 _RTHP-D-WHY !
    _RTHP-D-PENDING @ _RTHP-TB.FIELD-COUNT @
        _RTHP-D-P @ _RTHP.FIELD-COUNT @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.FIELD-COUNT @
        _RTHP-D-ACTIVE @ _RTHP-TB.FIELD-COUNT @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.FIELD-ITEMS @
        _RTHP-D-P @ _RTHP.FIELD-ITEMS @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.FIELD-ITEMS @
        _RTHP-D-ACTIVE @ _RTHP-TB.FIELD-ITEMS @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.FIELD-UTF8 @
        _RTHP-D-P @ _RTHP.FIELD-UTF8 @ <> IF 0 EXIT THEN
    \ The fields' text may differ in length from the acknowledged bank's, as
    \ a prompt's does with every key typed: each field is compared, and
    \ replaced when its content is newer, on its own.
    14 _RTHP-D-WHY !
    _RTHP-D-PENDING @ _RTHP-TB.DIALOG-CONTROLS @
        _RTHP-D-P @ _RTHP.DIALOG-CONTROLS @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.DIALOG-CONTROLS @
        _RTHP-D-ACTIVE @ _RTHP-TB.DIALOG-CONTROLS @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.DIALOG-COUNT @
        _RTHP-D-P @ _RTHP.DIALOG-COUNT @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.DIALOG-COUNT @
        _RTHP-D-ACTIVE @ _RTHP-TB.DIALOG-COUNT @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.DIALOG-UTF8 @
        _RTHP-D-P @ _RTHP.DIALOG-UTF8 @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.DIALOG-UTF8 @
        _RTHP-D-ACTIVE @ _RTHP-TB.DIALOG-UTF8 @ <> IF 0 EXIT THEN

    15 _RTHP-D-WHY !
    _RTHP-D-PENDING @ _RTHP-TB.COLLECTION-ITEMS @
        _RTHP-D-P @ _RTHP.COLLECTION-ITEMS @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.COLLECTION-UTF8 @
        _RTHP-D-P @ _RTHP.COLLECTION-UTF8 @ <> IF 0 EXIT THEN
    _RTHP-D-ACTIVE @ _RTHP-TB.MENU-TEXT-USED @
        _RTHP-D-PENDING @ _RTHP-TB.MENU-TEXT-USED @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.MENU-TEXT-USED @
        _RTHP-D-P @ _RTHP.SOURCE-MENU-TEXT-USED @ <> IF 0 EXIT THEN
    16 _RTHP-D-WHY !
    _RTHP-D-PENDING @ _RTHP-TB.GLYPH-SLOT-COUNT @
        _RTHP-D-P @ _RTHP.GLYPH-COUNT @ <> IF 0 EXIT THEN
    _RTHP-D-ACTIVE @ _RTHP-TB.FIRST-OBJECT @ _RTHP-D-ACTIVE-FIRST !
    _RTHP-D-PENDING @ _RTHP-TB.FIRST-OBJECT @ _RTHP-D-PENDING-FIRST !
    _RTHP-D-KEPT? _RTHP-D-KEPT !
    -1 ;

: _RTHP-D-PLAN-START?  ( -- flag )
    _RTHP-D-P @ _RTHP-DELTA-PLAN-CLEAR
    0 _RTHP-D-PLAN-CONTROLS ! 0 _RTHP-D-PLAN-GLYPHS !
    _RTHP-D-PENDING @ _RTHP-TB.CONTROL-COUNT @ 8 _RTHP-U32*?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-D-P @ _RTHP.ORDER2-U @ U> IF DROP 0 EXIT THEN
    DUP IF
        _RTHP-D-P @ _RTHP.ORDER2-A @ OVER _RTHP-D-P @
            _RTHP-ARENA-SPAN? 0= IF DROP 0 EXIT THEN
    THEN DROP
    -1 ;

: _RTHP-D-PLAN-CONTROL-STORE?  ( definition? -- flag )
    _RTHP-D-PLAN-DEFINE !
    _RTHP-D-CONTROL-ORDINAL @ DUP _RTHP-U+?
        0= IF DROP 0 EXIT THEN
    _RTHP-D-PLAN-DEFINE @ IF
        1 _RTHP-U+? 0= IF DROP 0 EXIT THEN
    THEN
    _RTHP-D-P @ _RTHP.ORDER2-A @
        _RTHP-D-PLAN-CONTROLS @ 8 * + !
    1 _RTHP-D-PLAN-CONTROLS +! -1 ;

: _RTHP-D-PLAN-CONTROL!  ( -- flag )
    0 _RTHP-D-PLAN-CONTROL-STORE? ;

: _RTHP-D-PLAN-CONTROL-DEFINE!  ( -- flag )
    -1 _RTHP-D-PLAN-CONTROL-STORE? ;

\ Three caller-bounded ORDER2 slices hold the final graph map and two sorted
\ indexes.  Each index cell packs a correlation ordinal above a graph ordinal.
\ The checked U32 byte products below prove both ordinals fit their 32-bit
\ halves; no control ID, pointer, or semantic identity is truncated or hashed.
VARIABLE _RTHP-D-INDEX-A
VARIABLE _RTHP-D-INDEX-B
VARIABLE _RTHP-D-INDEX-N
VARIABLE _RTHP-D-INDEX-A-N
VARIABLE _RTHP-D-INDEX-BYTES
VARIABLE _RTHP-D-INDEX-LAST-ID
VARIABLE _RTHP-D-INDEX-ID
VARIABLE _RTHP-D-INDEX-ORDINAL
VARIABLE _RTHP-D-JOIN-CURSOR
VARIABLE _RTHP-D-JOIN-A
VARIABLE _RTHP-D-JOIN-B
VARIABLE _RTHP-D-JOIN-ENTRY

VARIABLE _RTHP-D-SORT-A
VARIABLE _RTHP-D-SORT-N
VARIABLE _RTHP-D-SORT-BANK
VARIABLE _RTHP-D-SORT-MODE
VARIABLE _RTHP-D-SORT-BASE
VARIABLE _RTHP-D-SORT-STRIDE
VARIABLE _RTHP-D-SORT-SOURCE
VARIABLE _RTHP-D-SORT-DEST
VARIABLE _RTHP-D-SORT-START
VARIABLE _RTHP-D-SORT-MIDDLE
VARIABLE _RTHP-D-SORT-END
VARIABLE _RTHP-D-SORT-LEFT
VARIABLE _RTHP-D-SORT-RIGHT
VARIABLE _RTHP-D-SORT-OUT
VARIABLE _RTHP-D-SORT-RUNS

: _RTHP-D-INDEX-AT  ( ordinal index -- a ) SWAP 8 * + ;

: _RTHP-D-INDEX-CORRELATION  ( packed-index bank -- correlation )
    SWAP 32 RSHIFT SWAP _RTHP-D-CORR-AT ;

\ Compare exactly the six semantic cells: attachment, source, index, subkey,
\ lifecycle generation and source-global scope.  CONTROL-ID at +32 is not an
\ identity field.  Unsigned scalar ordering is only an index order; equality
\ remains identical to the former byte/field predicate, including high bits.
: _RTHP-D-CORRELATION-COMPARE  ( correlation1 correlation2 -- -1|0|1 )
    _RTHP-D-CI-X2 ! _RTHP-D-CI-X1 !
    6 0 DO
        I DUP 4 >= IF 1+ THEN 8 *
        DUP _RTHP-D-CI-X1 @ + @ SWAP _RTHP-D-CI-X2 @ + @
        2DUP = IF 2DROP ELSE
            U< IF -1 ELSE 1 THEN UNLOOP EXIT
        THEN
    LOOP 0 ;

\ Sort modes 0/1 join graph records and source-order correlations by complete
\ control ID.  Mode 2 orders their packed associations by semantic identity.
\ The immutable bank's key base and stride are bound once per sort.
: _RTHP-D-SORT-KEY-A  ( ordinal -- key-a )
    _RTHP-D-SORT-STRIDE @ * _RTHP-D-SORT-BASE @ + ;

: _RTHP-D-SORT-LESS?  ( left right -- flag )
    _RTHP-D-SORT-MODE @ 2 = IF
        32 RSHIFT _RTHP-D-SORT-KEY-A
        SWAP 32 RSHIFT _RTHP-D-SORT-KEY-A SWAP
        _RTHP-D-CORRELATION-COMPARE 0< EXIT
    THEN
    _RTHP-D-SORT-KEY-A @ SWAP _RTHP-D-SORT-KEY-A @ SWAP U< ;

: _RTHP-D-SORT-AT  ( ordinal -- a )
    _RTHP-D-SORT-SOURCE @ _RTHP-D-INDEX-AT ;

: _RTHP-D-SORT-RUN-END  ( first -- exclusive-end )
    1+
    BEGIN DUP _RTHP-D-SORT-N @ U< WHILE
        DUP _RTHP-D-SORT-AT @ OVER 1- _RTHP-D-SORT-AT @
            _RTHP-D-SORT-LESS? IF EXIT THEN
        1+
    REPEAT ;

: _RTHP-D-SORT-COPY-TAIL  ( first exclusive-end -- )
    OVER - 8 * >R
    _RTHP-D-SORT-AT
    _RTHP-D-SORT-OUT @ _RTHP-D-SORT-DEST @ _RTHP-D-INDEX-AT
    R> MOVE ;

: _RTHP-D-SORT-MERGE  ( -- )
    _RTHP-D-SORT-START @ DUP _RTHP-D-SORT-LEFT ! _RTHP-D-SORT-OUT !
    _RTHP-D-SORT-MIDDLE @ _RTHP-D-SORT-RIGHT !
    BEGIN
        _RTHP-D-SORT-LEFT @ _RTHP-D-SORT-MIDDLE @ U<
        _RTHP-D-SORT-RIGHT @ _RTHP-D-SORT-END @ U< AND
    WHILE
        _RTHP-D-SORT-RIGHT @ _RTHP-D-SORT-AT @
        _RTHP-D-SORT-LEFT @ _RTHP-D-SORT-AT @
        _RTHP-D-SORT-LESS? IF
            _RTHP-D-SORT-RIGHT @ _RTHP-D-SORT-AT @
            1 _RTHP-D-SORT-RIGHT +!
        ELSE
            _RTHP-D-SORT-LEFT @ _RTHP-D-SORT-AT @
            1 _RTHP-D-SORT-LEFT +!
        THEN
        _RTHP-D-SORT-OUT @ _RTHP-D-SORT-DEST @ _RTHP-D-INDEX-AT !
        1 _RTHP-D-SORT-OUT +!
    REPEAT
    _RTHP-D-SORT-LEFT @ _RTHP-D-SORT-MIDDLE @ U< IF
        _RTHP-D-SORT-LEFT @ _RTHP-D-SORT-MIDDLE @
    ELSE
        _RTHP-D-SORT-RIGHT @ _RTHP-D-SORT-END @
    THEN _RTHP-D-SORT-COPY-TAIL ;

: _RTHP-D-SORT-FINISH  ( -- )
    _RTHP-D-SORT-SOURCE @ _RTHP-D-SORT-A @ <> IF
        _RTHP-D-SORT-SOURCE @ _RTHP-D-SORT-A @
            _RTHP-D-SORT-N @ 8 * MOVE
        _RTHP-D-SORT-A @ _RTHP-D-SORT-SOURCE !
    THEN ;

\ Merge adjacent natural runs through the already bounded map prefix, which
\ has no result authority until the join.  Ordered inputs take one scan;
\ each merge pass at least halves the run count, retaining O(n log n) work
\ for reversed or hostile keys.  No bank bytes or additional storage change.
: _RTHP-D-INDEX-SORT  ( index count bank mode -- )
    _RTHP-D-SORT-MODE ! _RTHP-D-SORT-BANK !
    DUP _RTHP-D-SORT-N ! SWAP DUP _RTHP-D-SORT-A ! _RTHP-D-SORT-SOURCE !
    DUP 2 U< IF DROP EXIT THEN
    DROP
    _RTHP-D-P @ _RTHP.ORDER2-A @ _RTHP-D-SORT-DEST !
    _RTHP-D-SORT-BANK @ _RTHP-D-SORT-MODE @ 0= IF
        _RTHP-D-CONTROLS-A _RTE-CONTROL.ID RTE-CONTROL-SIZE
    ELSE
        _RTHP-D-CORR-A
        _RTHP-D-SORT-MODE @ 2 <> IF _RUCP-X.CONTROL-ID THEN
        RUCP-CORRELATION-SIZE
    THEN _RTHP-D-SORT-STRIDE ! _RTHP-D-SORT-BASE !
    BEGIN
        0 _RTHP-D-SORT-START ! 0 _RTHP-D-SORT-RUNS !
        BEGIN _RTHP-D-SORT-START @ _RTHP-D-SORT-N @ U< WHILE
            _RTHP-D-SORT-START @ _RTHP-D-SORT-RUN-END _RTHP-D-SORT-MIDDLE !
            _RTHP-D-SORT-MIDDLE @ _RTHP-D-SORT-N @ = IF
                _RTHP-D-SORT-START @ 0= IF _RTHP-D-SORT-FINISH EXIT THEN
                _RTHP-D-SORT-N @ _RTHP-D-SORT-END !
                _RTHP-D-SORT-START @ DUP _RTHP-D-SORT-OUT !
                    _RTHP-D-SORT-N @ _RTHP-D-SORT-COPY-TAIL
            ELSE
                _RTHP-D-SORT-MIDDLE @ _RTHP-D-SORT-RUN-END _RTHP-D-SORT-END !
                _RTHP-D-SORT-MERGE
            THEN
            1 _RTHP-D-SORT-RUNS +!
            _RTHP-D-SORT-END @ _RTHP-D-SORT-START !
        REPEAT
        _RTHP-D-SORT-SOURCE @ _RTHP-D-SORT-DEST @
            _RTHP-D-SORT-SOURCE ! _RTHP-D-SORT-DEST !
        _RTHP-D-SORT-RUNS @ 1 =
    UNTIL
    _RTHP-D-SORT-FINISH ;

: _RTHP-D-INDEX-WORK?  ( -- flag )
    _RTHP-D-PENDING @ _RTHP-TB.CONTROL-COUNT @ _RTHP-D-INDEX-N !
    _RTHP-D-ACTIVE @ _RTHP-TB.CONTROL-COUNT @
        DUP _RTHP-D-INDEX-A-N ! _RTHP-D-INDEX-N @ U> IF 0 EXIT THEN
    _RTHP-D-INDEX-N @ 24 _RTHP-U32*? 0= IF DROP 0 EXIT THEN
    DUP _RTHP-D-P @ _RTHP.ORDER2-U @ U> IF DROP 0 EXIT THEN
    DUP IF
        _RTHP-D-P @ _RTHP.ORDER2-A @ DUP 7 AND IF 2DROP 0 EXIT THEN
        OVER _RTHP-D-P @ _RTHP-ARENA-SPAN? 0= IF DROP 0 EXIT THEN
    THEN DROP
    _RTHP-D-INDEX-N @ 8 * DUP _RTHP-D-INDEX-BYTES !
    _RTHP-D-P @ _RTHP.ORDER2-A @ + DUP _RTHP-D-INDEX-A !
    _RTHP-D-INDEX-BYTES @ + _RTHP-D-INDEX-B ! -1 ;

\ Active IDs need not follow graph order after earlier semantic reordering.
\ Sorting both ID indexes proves a complete, duplicate-free bijection, then
\ retains each correlation's real graph ordinal in its packed association.
: _RTHP-D-ACTIVE-CONTROL-INDEX?  ( -- flag )
    _RTHP-D-INDEX-A-N @ 0 ?DO
        I DUP _RTHP-D-INDEX-A @ _RTHP-D-INDEX-AT !
        I DUP _RTHP-D-INDEX-B @ _RTHP-D-INDEX-AT !
    LOOP
    _RTHP-D-INDEX-A @ _RTHP-D-INDEX-A-N @ _RTHP-D-ACTIVE @
        0 _RTHP-D-INDEX-SORT
    _RTHP-D-INDEX-B @ _RTHP-D-INDEX-A-N @ _RTHP-D-ACTIVE @
        1 _RTHP-D-INDEX-SORT
    0 _RTHP-D-INDEX-LAST-ID !
    _RTHP-D-INDEX-A-N @ 0 ?DO
        I _RTHP-D-INDEX-A @ _RTHP-D-INDEX-AT @
            DUP _RTHP-D-INDEX-ORDINAL !
            _RTHP-D-ACTIVE @ _RTHP-D-CONTROL-AT _RTE-CONTROL.ID @
            DUP _RTHP-D-INDEX-ID !
        _RTHP-D-INDEX-LAST-ID @ U> 0= IF 0 UNLOOP EXIT THEN
        _RTHP-D-INDEX-ID @ _RTHP-D-PENDING-FIRST @ U< 0= IF
            0 UNLOOP EXIT
        THEN
        I _RTHP-D-INDEX-B @ _RTHP-D-INDEX-AT @
            DUP _RTHP-D-ACTIVE @ _RTHP-D-CORR-AT
                RUCP-CORRELATION-CONTROL-ID@ _RTHP-D-INDEX-ID @ <> IF
            DROP 0 UNLOOP EXIT
        THEN
        32 LSHIFT _RTHP-D-INDEX-ORDINAL @ OR
            I _RTHP-D-INDEX-A @ _RTHP-D-INDEX-AT !
        _RTHP-D-INDEX-ID @ _RTHP-D-INDEX-LAST-ID !
    LOOP -1 ;

\ A fresh pending control ID encodes its graph ordinal only after every
\ graph record has proved that namespace.  Correlations may be arbitrarily
\ ordered; the sentinel map rejects duplicate IDs and proves full coverage.
: _RTHP-D-PENDING-CONTROL-INDEX?  ( -- flag )
    _RTHP-D-P @ _RTHP.ORDER2-A @ _RTHP-D-INDEX-BYTES @ 255 FILL
    _RTHP-D-INDEX-N @ 0 ?DO
        _RTHP-D-PENDING-FIRST @ I _RTHP-U+? 0= IF DROP 0 UNLOOP EXIT THEN
        I _RTHP-D-PENDING @ _RTHP-D-CONTROL-AT _RTE-CONTROL.ID @ <>
            IF 0 UNLOOP EXIT THEN
    LOOP
    _RTHP-D-INDEX-N @ 0 ?DO
        I _RTHP-D-PENDING @ _RTHP-D-CORR-AT RUCP-CORRELATION-CONTROL-ID@
        DUP _RTHP-D-PENDING-FIRST @ U< IF DROP 0 UNLOOP EXIT THEN
        _RTHP-D-PENDING-FIRST @ - DUP _RTHP-D-INDEX-ORDINAL !
        _RTHP-D-INDEX-N @ U< 0= IF 0 UNLOOP EXIT THEN
        _RTHP-D-INDEX-ORDINAL @ _RTHP-D-CONTROL-MAP-AT DUP @ -1 <> IF
            DROP 0 UNLOOP EXIT
        THEN 0 SWAP !
        I 32 LSHIFT _RTHP-D-INDEX-ORDINAL @ OR
            I _RTHP-D-INDEX-B @ _RTHP-D-INDEX-AT !
    LOOP -1 ;

: _RTHP-D-SORT-IDENTITIES?  ( index count bank -- flag )
    2 _RTHP-D-INDEX-SORT
    _RTHP-D-SORT-N @ 2 U< IF -1 EXIT THEN
    _RTHP-D-SORT-N @ 1 ?DO
        I 1- _RTHP-D-SORT-AT @ _RTHP-D-SORT-BANK @
            _RTHP-D-INDEX-CORRELATION
        I _RTHP-D-SORT-AT @ _RTHP-D-SORT-BANK @
            _RTHP-D-INDEX-CORRELATION
        _RTHP-D-CORRELATION-COMPARE 0< 0= IF 0 UNLOOP EXIT THEN
    LOOP -1 ;

\ Merge unique identities once.  An unmatched pending identity is growth;
\ an unmatched active identity is deletion and refuses DELTA.  The resulting
\ ORDER2 prefix remains indexed by pending graph ordinal, preserving its
\ parent-first order for later compatibility, normalization and wire planning.
: _RTHP-D-JOIN-CONTROL-INDEXES?  ( -- flag )
    \ Sorting borrowed this prefix as scratch.  Only this merge publishes
    \ graph-map entries, and an unmatched pending identity must start at zero.
    _RTHP-D-P @ _RTHP.ORDER2-A @ _RTHP-D-INDEX-BYTES @ 0 FILL
    0 _RTHP-D-JOIN-CURSOR !
    _RTHP-D-INDEX-N @ 0 ?DO
        I _RTHP-D-INDEX-B @ _RTHP-D-INDEX-AT @
        DUP 0xFFFFFFFF AND _RTHP-D-CONTROL-MAP-AT _RTHP-D-JOIN-ENTRY !
        _RTHP-D-PENDING @ _RTHP-D-INDEX-CORRELATION _RTHP-D-JOIN-B !
        _RTHP-D-JOIN-CURSOR @ _RTHP-D-INDEX-A-N @ U< IF
            _RTHP-D-JOIN-CURSOR @ _RTHP-D-INDEX-A @ _RTHP-D-INDEX-AT @
                DUP _RTHP-D-JOIN-A !
                _RTHP-D-ACTIVE @ _RTHP-D-INDEX-CORRELATION
            _RTHP-D-JOIN-B @ _RTHP-D-CORRELATION-COMPARE
            DUP 0< IF DROP 0 UNLOOP EXIT THEN
            0= IF
                _RTHP-D-JOIN-A @ 0xFFFFFFFF AND 1+
                    _RTHP-D-JOIN-ENTRY @ !
                1 _RTHP-D-JOIN-CURSOR +!
            THEN
        THEN
    LOOP
    _RTHP-D-JOIN-CURSOR @ _RTHP-D-INDEX-A-N @ = ;

\ The comparison that built the active bank sorted its correlation/graph
\ associations by semantic identity and proved them unique.  Join that exact
\ index from the bank's annex; its IDs must still precede this namespace.
: _RTHP-D-KEPT-CONTROL-INDEX?  ( -- flag )
    _RTHP-D-INDEX-A-N @ 0= IF -1 EXIT THEN
    _RTHP-D-P @ _RTHP.ACTIVE-FACTS _RTHP-KF.LAST-ID @
        _RTHP-D-PENDING-FIRST @ U< 0= IF 0 EXIT THEN
    _RTHP-D-INDEX-A-N @ 8 *
        DUP _RTHP-D-P @ _RTHP.FACTS-INDEX-U @ U> IF DROP 0 EXIT THEN
    _RTHP-D-ACTIVE @ _RTHP-D-P @ _RTHP-FACTS-INDEX
        DUP ROT _RTHP-D-P @ _RTHP-ARENA-SPAN? 0= IF DROP 0 EXIT THEN
    _RTHP-D-INDEX-A ! -1 ;

: _RTHP-D-BUILD-CONTROL-MAP?  ( -- flag )
    _RTHP-D-INDEX-WORK? 0= IF 0 EXIT THEN
    _RTHP-D-KEPT @ IF
        _RTHP-D-KEPT-CONTROL-INDEX? 0= IF 0 EXIT THEN
    ELSE
        _RTHP-D-ACTIVE-CONTROL-INDEX? 0= IF 0 EXIT THEN
    THEN
    _RTHP-D-PENDING-CONTROL-INDEX? 0= IF 0 EXIT THEN
    _RTHP-D-KEPT @ 0= IF
        _RTHP-D-INDEX-A @ _RTHP-D-INDEX-A-N @ _RTHP-D-ACTIVE @
            _RTHP-D-SORT-IDENTITIES? 0= IF 0 EXIT THEN
    THEN
    _RTHP-D-INDEX-B @ _RTHP-D-INDEX-N @ _RTHP-D-PENDING @
        _RTHP-D-SORT-IDENTITIES? 0= IF 0 EXIT THEN
    _RTHP-D-JOIN-CONTROL-INDEXES? ;

\ All expensive source-order and semantic resolution is complete before this
\ cached pair is used.  Reacquire packed CONTROL pointers by graph ordinal so
\ tombstone extension may safely repack the pending bank between calls.
: _RTHP-D-CONTROL-PAIR  ( pending-control-ordinal -- flag )
    DUP _RTHP-D-CONTROL-ORDINAL !
    _RTHP-D-PENDING @ _RTHP-TB.CONTROL-COUNT @ U< 0= IF 0 EXIT THEN
    _RTHP-D-CONTROL-ORDINAL @ _RTHP-D-PENDING @ _RTHP-D-CONTROL-AT
        DUP _RTHP-D-PENDING-C ! _RTE-CONTROL.ID @ _RTHP-D-EXPECTED-P !
    _RTHP-D-PENDING-FIRST @ _RTHP-D-CONTROL-ORDINAL @ _RTHP-U+?
        0= IF DROP 0 EXIT THEN
    _RTHP-D-EXPECTED-P @ <> IF 0 EXIT THEN
    _RTHP-D-CONTROL-ORDINAL @ _RTHP-D-CONTROL-MAP-AT @
        DUP _RTHP-D-CONTROL-MAP-VALUE !
    DUP 0= IF
        DROP 0 _RTHP-D-MATCHED !
        0 _RTHP-D-ACTIVE-C ! 0 _RTHP-D-ACTIVE-I ! -1 EXIT
    THEN
    DUP 0< IF NEGATE THEN
    DUP 0> 0= IF DROP 0 EXIT THEN
    1- DUP _RTHP-D-ACTIVE-I !
    _RTHP-D-ACTIVE @ _RTHP-TB.CONTROL-COUNT @ U< 0= IF 0 EXIT THEN
    _RTHP-D-ACTIVE-I @ _RTHP-D-ACTIVE @ _RTHP-D-CONTROL-AT
        DUP _RTHP-D-ACTIVE-C ! _RTE-CONTROL.ID @ _RTHP-D-EXPECTED-A !
    _RTHP-D-EXPECTED-A @ DUP 0= IF DROP 0 EXIT THEN
    _RTHP-D-PENDING-FIRST @ U< 0= IF 0 EXIT THEN
    -1 _RTHP-D-MATCHED ! -1 ;

: _RTHP-D-CONTROL-MARK-CHANGED?  ( -- flag )
    _RTHP-D-CONTROL-ORDINAL @ _RTHP-D-CONTROL-MAP-AT DUP @
    DUP 0= IF 2DROP -1 EXIT THEN
    DUP 0< IF 2DROP -1 EXIT THEN
    NEGATE SWAP ! -1 ;

VARIABLE _RTHP-D-RAW-ID
VARIABLE _RTHP-D-RAW-ORDINAL

: _RTHP-D-RAW-CONTROL-REFERENCE?  ( raw-control-id -- flag )
    DUP _RTHP-D-RAW-ID !
    _RTHP-D-PENDING-FIRST @ U< IF 0 EXIT THEN
    _RTHP-D-RAW-ID @ _RTHP-D-PENDING-FIRST @ -
        DUP _RTHP-D-RAW-ORDINAL !
    _RTHP-D-PENDING @ _RTHP-TB.CONTROL-COUNT @ U< 0= IF 0 EXIT THEN
    _RTHP-D-RAW-ORDINAL @ _RTHP-D-PENDING @ _RTHP-D-CONTROL-AT
        _RTE-CONTROL.ID @ _RTHP-D-RAW-ID @ = ;

: _RTHP-D-PARENT-TOPOLOGY?  ( -- flag )
    _RTHP-D-ACTIVE-C @ _RTE-CONTROL.PARENT @ DUP _RTHP-D-OFFSET-A !
    _RTHP-D-PENDING-C @ _RTE-CONTROL.PARENT @ DUP _RTHP-D-OFFSET-P !
    OR 0= IF -1 EXIT THEN
    _RTHP-D-OFFSET-A @ 0= _RTHP-D-OFFSET-P @ 0= OR IF 0 EXIT THEN
    _RTHP-D-OFFSET-P @ _RTHP-D-RAW-CONTROL-REFERENCE?
        0= IF 0 EXIT THEN
    _RTHP-D-RAW-ORDINAL @ _RTHP-D-CONTROL-MAP-AT @ DUP 0= IF
        DROP 0 EXIT
    THEN
    DUP 0< IF NEGATE THEN
    DUP 0> 0= IF DROP 0 EXIT THEN
    1- DUP _RTHP-D-ACTIVE @ _RTHP-TB.CONTROL-COUNT @ U< 0= IF
        DROP 0 EXIT
    THEN
    _RTHP-D-ACTIVE @ _RTHP-D-CONTROL-AT _RTE-CONTROL.ID @
        _RTHP-D-OFFSET-A @ = ;

: _RTHP-D-CONTROL-LABEL-EQUAL?  ( -- flag )
    _RTHP-D-ACTIVE-C @ _RTE-CONTROL.LABEL-A @
    _RTHP-D-ACTIVE-C @ _RTE-CONTROL.LABEL-U @
    _RTHP-D-ACTIVE @ _RTHP-D-SOURCE-A
    _RTHP-D-ACTIVE @ _RTHP-TB.SOURCE-TEXT-USED @
    _RTHP-D-PENDING-C @ _RTE-CONTROL.LABEL-A @
    _RTHP-D-PENDING-C @ _RTE-CONTROL.LABEL-U @
    _RTHP-D-PENDING @ _RTHP-D-SOURCE-A
    _RTHP-D-PENDING @ _RTHP-TB.SOURCE-TEXT-USED @
        _RTHP-D-TEXTS-EQUAL? ;

: _RTHP-D-CONTROL-SHORTCUT-EQUAL?  ( -- flag )
    _RTHP-D-ACTIVE-C @ _RTE-CONTROL.SHORTCUT-A @
    _RTHP-D-ACTIVE-C @ _RTE-CONTROL.SHORTCUT-U @
    _RTHP-D-ACTIVE @ _RTHP-D-SOURCE-A
    _RTHP-D-ACTIVE @ _RTHP-TB.SOURCE-TEXT-USED @
    _RTHP-D-PENDING-C @ _RTE-CONTROL.SHORTCUT-A @
    _RTHP-D-PENDING-C @ _RTE-CONTROL.SHORTCUT-U @
    _RTHP-D-PENDING @ _RTHP-D-SOURCE-A
    _RTHP-D-PENDING @ _RTHP-TB.SOURCE-TEXT-USED @
        _RTHP-D-TEXTS-EQUAL? ;

: _RTHP-D-CONTROL-CONTENT-EQUAL?  ( -- flag )
    _RTHP-D-ACTIVE-C @ _RTE-CONTROL.CONTENT-A @
    _RTHP-D-ACTIVE-C @ _RTE-CONTROL.CONTENT-U @
    _RTHP-D-ACTIVE @ _RTHP-D-SOURCE-A
    _RTHP-D-ACTIVE @ _RTHP-TB.SOURCE-TEXT-USED @
    _RTHP-D-PENDING-C @ _RTE-CONTROL.CONTENT-A @
    _RTHP-D-PENDING-C @ _RTE-CONTROL.CONTENT-U @
    _RTHP-D-PENDING @ _RTHP-D-SOURCE-A
    _RTHP-D-PENDING @ _RTHP-TB.SOURCE-TEXT-USED @
        _RTHP-D-TEXTS-EQUAL? ;

VARIABLE _RTHP-D-SPAN-C
VARIABLE _RTHP-D-SPAN-BANK

\ Whether a control's texts lie inside its bank's source text.  The
\ comparison reads only banks the producer packed itself, from items the
\ engine admitted, so this and _RTHP-D-REF-VALID? check them only with
\ every-frame checks on (check-mode.f).
: _RTHP-D-CONTROL-TEXTS-WITHIN?  ( -- flag )
    _RTHP-D-SPAN-C @ _RTE-CONTROL.LABEL-A @
    _RTHP-D-SPAN-C @ _RTE-CONTROL.LABEL-U @
    _RTHP-D-SPAN-BANK @ _RTHP-D-SOURCE-A
    _RTHP-D-SPAN-BANK @ _RTHP-TB.SOURCE-TEXT-USED @
        _RTHP-TEXT-WITHIN? 0= IF 0 EXIT THEN
    _RTHP-D-SPAN-C @ _RTE-CONTROL.SHORTCUT-A @
    _RTHP-D-SPAN-C @ _RTE-CONTROL.SHORTCUT-U @
    _RTHP-D-SPAN-BANK @ _RTHP-D-SOURCE-A
    _RTHP-D-SPAN-BANK @ _RTHP-TB.SOURCE-TEXT-USED @
        _RTHP-TEXT-WITHIN? 0= IF 0 EXIT THEN
    _RTHP-D-SPAN-C @ _RTE-CONTROL.CONTENT-A @
    _RTHP-D-SPAN-C @ _RTE-CONTROL.CONTENT-U @
    _RTHP-D-SPAN-BANK @ _RTHP-D-SOURCE-A
    _RTHP-D-SPAN-BANK @ _RTHP-TB.SOURCE-TEXT-USED @
        _RTHP-TEXT-WITHIN? ;
: _RTHP-D-CONTROL-TEXT-SPANS?  ( control bank -- flag )
    CHK-EVERY-FRAME? 0= IF 2DROP -1 EXIT THEN
    _RTHP-D-SPAN-BANK ! _RTHP-D-SPAN-C !
    _RTHP-D-CONTROL-TEXTS-WITHIN? _RTHP-BANKS-DAMAGED CHK-NAME ;

\ STX1 is canonical little-endian and may begin at a merely byte-aligned
\ address.  Never use native @ to recover its monotonic content revision.
: _RTHP-D-BYTE-LE16@  ( a -- u )
    DUP C@ SWAP 1+ C@ 8 LSHIFT OR ;

: _RTHP-D-BYTE-LE32@  ( a -- u )
    DUP _RTHP-D-BYTE-LE16@
    SWAP 2 + _RTHP-D-BYTE-LE16@ 16 LSHIFT OR ;

: _RTHP-D-BYTE-LE64@  ( a -- u )
    DUP _RTHP-D-BYTE-LE32@
    SWAP 4 + _RTHP-D-BYTE-LE32@ 32 LSHIFT OR ;

VARIABLE _RTHP-D-REV-C
VARIABLE _RTHP-D-REV-BANK
VARIABLE _RTHP-D-REV-A
VARIABLE _RTHP-D-REV-U
VARIABLE _RTHP-D-REV-ACTIVE
VARIABLE _RTHP-D-REV-PENDING

\ STX1, ITM1 and DOC1 all begin with the tag, version 1, a zero reserved
\ field, and the content revision.
: _RTHP-D-CONTENT-HEADER  ( control -- tag header-bytes )
    _RTE-CONTROL.KIND @ DUP RTE-CONTROL-ITEM-VIEW = IF
        DROP USITM-TAG USITM-HEADER-SIZE EXIT
    THEN
    RTE-CONTROL-DOCUMENT = IF USDOC-TAG USDOC-HEADER-SIZE EXIT THEN
    USSTX-TAG USSTX-CONTENT-HEADER-SIZE ;

\ A body takes the aggregate epoch of the frame that changed it and keeps it
\ while it stays unchanged, so a bank's revisions never exceed its epoch.
: _RTHP-D-CONTENT-REVISION?  ( control bank -- revision flag )
    _RTHP-D-REV-BANK ! _RTHP-D-REV-C !
    _RTHP-D-REV-C @ _RTE-CONTROL.CONTENT-U @ DUP _RTHP-D-REV-U !
    _RTHP-D-REV-C @ _RTHP-D-CONTENT-HEADER NIP U< IF 0 0 EXIT THEN
    _RTHP-D-REV-C @ _RTE-CONTROL.CONTENT-A @ DUP _RTHP-D-REV-A !
    _RTHP-D-REV-U @
    _RTHP-D-REV-BANK @ _RTHP-D-SOURCE-A
    _RTHP-D-REV-BANK @ _RTHP-TB.SOURCE-TEXT-USED @
        _RTHP-TEXT-WITHIN? 0= IF 0 0 EXIT THEN
    _RTHP-D-REV-A @ _RTHP-D-BYTE-LE32@
    _RTHP-D-REV-C @ _RTHP-D-CONTENT-HEADER DROP <> IF 0 0 EXIT THEN
    _RTHP-D-REV-A @ 4 + _RTHP-D-BYTE-LE16@ 1 <>
        IF 0 0 EXIT THEN
    _RTHP-D-REV-A @ 6 + _RTHP-D-BYTE-LE16@ IF 0 0 EXIT THEN
    _RTHP-D-REV-A @ 8 + _RTHP-D-BYTE-LE64@ DUP 0= IF DROP 0 0 EXIT THEN
    DUP _RTHP-D-REV-BANK @ _RTHP-TB.CONTENT-EPOCH @ U> IF
        DROP 0 0 EXIT
    THEN
    -1 ;

: _RTHP-D-CONTROL-CONTENT-NEWER?  ( -- flag )
    _RTHP-D-ACTIVE-C @ _RTHP-D-ACTIVE @ _RTHP-D-CONTENT-REVISION?
        0= IF DROP 0 EXIT THEN _RTHP-D-REV-ACTIVE !
    _RTHP-D-PENDING-C @ _RTHP-D-PENDING @ _RTHP-D-CONTENT-REVISION?
        0= IF DROP 0 EXIT THEN _RTHP-D-REV-PENDING !
    _RTHP-D-REV-PENDING @ _RTHP-D-REV-ACTIVE @ U> ;

\ FDC1 and DLG1 carry their control's own revision at offset 8, which the
\ field or dialog advances with every change it shows; no frame epoch
\ bounds it.
: _RTHP-D-OWN-HEADER  ( control -- tag header-bytes )
    _RTE-CONTROL.KIND @ RTE-CONTROL-DIALOG = IF
        DLG1-TAG DLG1-HEADER-SIZE EXIT
    THEN
    UFLDC-TAG UFLDC-HEADER-SIZE ;

: _RTHP-D-OWN-REVISION?  ( control bank -- revision flag )
    _RTHP-D-REV-BANK ! _RTHP-D-REV-C !
    _RTHP-D-REV-C @ _RTE-CONTROL.CONTENT-U @ DUP _RTHP-D-REV-U !
    _RTHP-D-REV-C @ _RTHP-D-OWN-HEADER NIP U< IF 0 0 EXIT THEN
    _RTHP-D-REV-C @ _RTE-CONTROL.CONTENT-A @ DUP _RTHP-D-REV-A !
    _RTHP-D-REV-U @
    _RTHP-D-REV-BANK @ _RTHP-D-SOURCE-A
    _RTHP-D-REV-BANK @ _RTHP-TB.SOURCE-TEXT-USED @
        _RTHP-TEXT-WITHIN? 0= IF 0 0 EXIT THEN
    _RTHP-D-REV-A @ _RTHP-D-BYTE-LE32@
        _RTHP-D-REV-C @ _RTHP-D-OWN-HEADER DROP <> IF 0 0 EXIT THEN
    _RTHP-D-REV-A @ 8 + _RTHP-D-BYTE-LE64@ DUP 0= IF DROP 0 0 EXIT THEN
    -1 ;

: _RTHP-D-OWN-NEWER?  ( -- flag )
    _RTHP-D-ACTIVE-C @ _RTHP-D-ACTIVE @ _RTHP-D-OWN-REVISION?
        0= IF DROP 0 EXIT THEN _RTHP-D-REV-ACTIVE !
    _RTHP-D-PENDING-C @ _RTHP-D-PENDING @ _RTHP-D-OWN-REVISION?
        0= IF DROP 0 EXIT THEN _RTHP-D-REV-PENDING !
    _RTHP-D-REV-PENDING @ _RTHP-D-REV-ACTIVE @ U> ;

\ True when both contents are valid and equal in every byte but the 8-byte
\ revision that STX1, ITM1 and DOC1 all carry at offset 8 of their headers.
\ Such a body is unchanged: it keeps the revision the terminal holds.
: _RTHP-D-CONTROL-BODY-EQUAL?  ( -- flag )
    _RTHP-D-ACTIVE-C @ _RTHP-D-ACTIVE @ _RTHP-D-CONTENT-REVISION?
        NIP 0= IF 0 EXIT THEN
    _RTHP-D-PENDING-C @ _RTHP-D-PENDING @ _RTHP-D-CONTENT-REVISION?
        NIP 0= IF 0 EXIT THEN
    _RTHP-D-ACTIVE-C @ _RTE-CONTROL.CONTENT-U @
        _RTHP-D-PENDING-C @ _RTE-CONTROL.CONTENT-U @ <> IF 0 EXIT THEN
    _RTHP-D-ACTIVE-C @ _RTE-CONTROL.CONTENT-A @ 8
    _RTHP-D-ACTIVE @ _RTHP-D-SOURCE-A
    _RTHP-D-ACTIVE @ _RTHP-TB.SOURCE-TEXT-USED @
    _RTHP-D-PENDING-C @ _RTE-CONTROL.CONTENT-A @ 8
    _RTHP-D-PENDING @ _RTHP-D-SOURCE-A
    _RTHP-D-PENDING @ _RTHP-TB.SOURCE-TEXT-USED @
        _RTHP-D-TEXTS-EQUAL? 0= IF 0 EXIT THEN
    _RTHP-D-ACTIVE-C @ _RTE-CONTROL.CONTENT-A @ 16 +
    _RTHP-D-ACTIVE-C @ _RTE-CONTROL.CONTENT-U @ 16 -
    _RTHP-D-ACTIVE @ _RTHP-D-SOURCE-A
    _RTHP-D-ACTIVE @ _RTHP-TB.SOURCE-TEXT-USED @
    _RTHP-D-PENDING-C @ _RTE-CONTROL.CONTENT-A @ 16 +
    _RTHP-D-PENDING-C @ _RTE-CONTROL.CONTENT-U @ 16 -
    _RTHP-D-PENDING @ _RTHP-D-SOURCE-A
    _RTHP-D-PENDING @ _RTHP-TB.SOURCE-TEXT-USED @
        _RTHP-D-TEXTS-EQUAL? ;

: _RTHP-D-CONTROL-COMPATIBLE?  ( index -- flag )
    _RTHP-D-CONTROL-PAIR 0= IF 0 EXIT THEN
    _RTHP-D-MATCHED @ 0= IF
        _RTHP-D-PENDING-C @ _RTE-CONTROL.KIND @ DUP RTE-CONTROL-FIELD =
            SWAP _RTHP-DIALOG-KIND? OR IF 0 EXIT THEN
        _RTHP-D-PENDING-C @ _RTE-CONTROL.REGION @
            _RTHP-D-PENDING @ _RTHP-TB.REGION @ <> IF 0 EXIT THEN
        _RTHP-D-PENDING-C @ _RTHP-D-PENDING @
            _RTHP-D-CONTROL-TEXT-SPANS? 0= IF 0 EXIT THEN
        -1 _RTHP-D-CHANGED ! 1 _RTHP-D-OPS +! -1 EXIT
    THEN
    _RTHP-D-ACTIVE-C @ 16 _RTHP-D-PENDING-C @ 16 COMPARE IF 0 EXIT THEN
    _RTHP-D-ACTIVE-C @ _RTE-CONTROL.KIND @
        _RTHP-D-PENDING-C @ _RTE-CONTROL.KIND @ <> IF 0 EXIT THEN
    _RTHP-D-ACTIVE-C @ _RTE-CONTROL.Z @
        _RTHP-D-PENDING-C @ _RTE-CONTROL.Z @ <> IF 0 EXIT THEN
    _RTHP-D-ACTIVE-C @ _RTE-CONTROL.REGION @
        _RTHP-D-ACTIVE @ _RTHP-TB.REGION @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING-C @ _RTE-CONTROL.REGION @
        _RTHP-D-PENDING @ _RTHP-TB.REGION @ <> IF 0 EXIT THEN
    _RTHP-D-PARENT-TOPOLOGY? 0= IF 0 EXIT THEN
    _RTHP-D-ACTIVE-C @ 64 + 56
        _RTHP-D-PENDING-C @ 64 + 56 COMPARE IF 0 EXIT THEN
    _RTHP-D-ACTIVE-C @ _RTHP-D-ACTIVE @
        _RTHP-D-CONTROL-TEXT-SPANS? 0= IF 0 EXIT THEN
    _RTHP-D-PENDING-C @ _RTHP-D-PENDING @
        _RTHP-D-CONTROL-TEXT-SPANS? 0= IF 0 EXIT THEN
    0 _RTHP-D-CHANGED !
    _RTHP-D-ACTIVE-C @ _RTE-CONTROL.STATE @
        _RTHP-D-PENDING-C @ _RTE-CONTROL.STATE @ <> IF
        -1 _RTHP-D-CHANGED !
    THEN
    _RTHP-D-PENDING-C @ _RTE-CONTROL.KIND @ DUP RTE-CONTROL-FIELD =
        SWAP RTE-CONTROL-DIALOG = OR IF
        \ A field or dialog keeps its label, a dialog's title, and its
        \ geometry is exact; a field also keeps every state bit but
        \ SELECTED.  Its FDC1 or DLG1 content may change, as a prompt's does
        \ with every key, when its revision is strictly newer: one
        \ CONTROL-REPLACE carries it.  Any other change needs a complete
        \ candidate replacement.
        _RTHP-D-PENDING-C @ _RTE-CONTROL.KIND @ RTE-CONTROL-FIELD = IF
            _RTHP-D-ACTIVE-C @ _RTE-CONTROL.STATE @
            _RTHP-D-PENDING-C @ _RTE-CONTROL.STATE @ XOR
                RTE-CONTROL-SELECTED INVERT AND IF 0 EXIT THEN
        THEN
        _RTHP-D-CONTROL-LABEL-EQUAL? 0= IF 0 EXIT THEN
        _RTHP-D-CONTROL-SHORTCUT-EQUAL? 0= IF 0 EXIT THEN
        _RTHP-D-ACTIVE-C @ _RTE-CONTROL.CONTENT-RUNS 16
            _RTHP-D-PENDING-C @ _RTE-CONTROL.CONTENT-RUNS 16 COMPARE IF 0 EXIT THEN
        _RTHP-D-CONTROL-CONTENT-EQUAL? IF
            _RTHP-D-ACTIVE-C @ _RTE-CONTROL.CONTENT-ITEMS 16
                _RTHP-D-PENDING-C @ _RTE-CONTROL.CONTENT-ITEMS 16
                COMPARE IF 0 EXIT THEN
        ELSE
            _RTHP-D-OWN-NEWER? 0= IF 0 EXIT THEN
            -1 _RTHP-D-CHANGED !
        THEN
        _RTHP-D-CHANGED @ IF 1 _RTHP-D-OPS +! THEN -1 EXIT
    THEN
    _RTHP-D-ACTIVE-C @ _RTE-CONTROL.KIND @ DUP
        _RTHP-CONTENT-CONTROL-KIND? IF
        DROP
        _RTHP-D-CONTROL-LABEL-EQUAL? 0= IF 0 EXIT THEN
        _RTHP-D-CONTROL-SHORTCUT-EQUAL? 0= IF 0 EXIT THEN
        \ An unchanged body is unchanged even though this frame stamped it
        \ with its own epoch; normalization restores the revision it keeps.
        _RTHP-D-CONTROL-CONTENT-EQUAL? IF -1 ELSE
            _RTHP-D-CONTROL-BODY-EQUAL?
        THEN IF
            _RTHP-D-ACTIVE-C @ _RTE-CONTROL.CONTENT-ITEMS @
                _RTHP-D-PENDING-C @ _RTE-CONTROL.CONTENT-ITEMS @ <>
                IF 0 EXIT THEN
            _RTHP-D-ACTIVE-C @ _RTE-CONTROL.CONTENT-UTF8 @
                _RTHP-D-PENDING-C @ _RTE-CONTROL.CONTENT-UTF8 @ <>
                IF 0 EXIT THEN
            _RTHP-D-ACTIVE-C @ _RTE-CONTROL.CONTENT-RUNS @
                _RTHP-D-PENDING-C @ _RTE-CONTROL.CONTENT-RUNS @ <>
                IF 0 EXIT THEN
            _RTHP-D-ACTIVE-C @ _RTE-CONTROL.CONTENT-FIELDS @
                _RTHP-D-PENDING-C @ _RTE-CONTROL.CONTENT-FIELDS @ <>
                IF 0 EXIT THEN
        ELSE
            _RTHP-D-CONTROL-CONTENT-NEWER? 0= IF 0 EXIT THEN
            -1 _RTHP-D-CHANGED !
        THEN
    ELSE DUP RTE-CONTROL-BUTTON = IF
        \ A button may change its label, shortcut and BTN1 roles as well as
        \ its state; BTN1 carries no items or text.
        DROP
        _RTHP-D-ACTIVE-C @ _RTE-CONTROL.CONTENT-ITEMS 32
            _RTHP-D-PENDING-C @ _RTE-CONTROL.CONTENT-ITEMS 32
            COMPARE IF 0 EXIT THEN
        _RTHP-D-CONTROL-LABEL-EQUAL? 0= IF -1 _RTHP-D-CHANGED ! THEN
        _RTHP-D-CONTROL-SHORTCUT-EQUAL? 0= IF -1 _RTHP-D-CHANGED ! THEN
        _RTHP-D-CONTROL-CONTENT-EQUAL? 0= IF -1 _RTHP-D-CHANGED ! THEN
    ELSE DUP RTE-CONTROL-TAB = IF
        DROP
        _RTHP-D-ACTIVE-C @ _RTE-CONTROL.CONTENT-ITEMS @
            _RTHP-D-PENDING-C @ _RTE-CONTROL.CONTENT-ITEMS @ <>
            IF 0 EXIT THEN
        _RTHP-D-ACTIVE-C @ _RTE-CONTROL.CONTENT-UTF8 @
            _RTHP-D-PENDING-C @ _RTE-CONTROL.CONTENT-UTF8 @ <>
            IF 0 EXIT THEN
        _RTHP-D-ACTIVE-C @ _RTE-CONTROL.CONTENT-RUNS @
            _RTHP-D-PENDING-C @ _RTE-CONTROL.CONTENT-RUNS @ <>
            IF 0 EXIT THEN
        _RTHP-D-CONTROL-CONTENT-EQUAL? 0= IF 0 EXIT THEN
        _RTHP-D-CONTROL-LABEL-EQUAL? 0= IF
            -1 _RTHP-D-CHANGED !
        THEN
        _RTHP-D-CONTROL-SHORTCUT-EQUAL? 0= IF
            -1 _RTHP-D-CHANGED !
        THEN
    ELSE
        DROP
        _RTHP-D-ACTIVE-C @ _RTE-CONTROL.CONTENT-ITEMS @
            _RTHP-D-PENDING-C @ _RTE-CONTROL.CONTENT-ITEMS @ <>
            IF 0 EXIT THEN
        _RTHP-D-ACTIVE-C @ _RTE-CONTROL.CONTENT-UTF8 @
            _RTHP-D-PENDING-C @ _RTE-CONTROL.CONTENT-UTF8 @ <>
            IF 0 EXIT THEN
        _RTHP-D-ACTIVE-C @ _RTE-CONTROL.CONTENT-RUNS @
            _RTHP-D-PENDING-C @ _RTE-CONTROL.CONTENT-RUNS @ <>
            IF 0 EXIT THEN
        _RTHP-D-CONTROL-LABEL-EQUAL? 0= IF 0 EXIT THEN
        _RTHP-D-CONTROL-SHORTCUT-EQUAL? 0= IF 0 EXIT THEN
        _RTHP-D-CONTROL-CONTENT-EQUAL? 0= IF 0 EXIT THEN
    THEN THEN THEN
    _RTHP-D-CHANGED @ IF 1 _RTHP-D-OPS +! THEN
    -1 ;

: _RTHP-D-GLYPH-EXPECTED?  ( first non-glyph-count index -- id flag )
    _RTHP-D-I !
    _RTHP-U+? 0= IF DROP 0 0 EXIT THEN
    _RTHP-D-I @ _RTHP-U+? ;

VARIABLE _RTHP-D-REF-ITEM
VARIABLE _RTHP-D-REF-REF
VARIABLE _RTHP-D-REF-BANK

: _RTHP-D-REF-WITHIN?  ( -- flag )
    _RTHP-D-REF-REF @ RGRP-TEXT-REF-OFFSET@ _RTHP-D-OFFSET-P !
    _RTHP-D-REF-REF @ RGRP-TEXT-REF-LENGTH@ _RTHP-D-EXPECTED-P !
    _RTHP-D-OFFSET-P @
        _RTHP-D-REF-BANK @ _RTHP-TB.GLYPH-TEXT-USED @ U> IF 0 EXIT THEN
    _RTHP-D-EXPECTED-P @
        _RTHP-D-REF-BANK @ _RTHP-TB.GLYPH-TEXT-USED @
        _RTHP-D-OFFSET-P @ - U> IF 0 EXIT THEN
    _RTHP-D-REF-ITEM @ _RTE-LPI.TEXT-CAPACITY @
        _RTHP-D-EXPECTED-P @ = ;
: _RTHP-D-REF-VALID?  ( item ref bank -- flag )
    CHK-EVERY-FRAME? 0= IF 2DROP DROP -1 EXIT THEN
    _RTHP-D-REF-BANK ! _RTHP-D-REF-REF ! _RTHP-D-REF-ITEM !
    _RTHP-D-REF-WITHIN? _RTHP-BANKS-DAMAGED CHK-NAME ;

\ A spatially normalized ACK bank keeps records in row-major presentation
\ order while object IDs become a permutation of the original contiguous
\ slot namespace.  This caller-bounded inverse map gives DELTA comparison an
\ O(1) route from one stable object ID back to its acknowledged packed item.
VARIABLE _RTHP-D-GLYPH-BASE
VARIABLE _RTHP-D-SLOTS
VARIABLE _RTHP-D-ACTIVE-SLOTS
VARIABLE _RTHP-D-APPEND-INDEX
VARIABLE _RTHP-D-MAP-A
VARIABLE _RTHP-D-MAP-U
VARIABLE _RTHP-D-MAP-BYTES
VARIABLE _RTHP-D-BANK-BYTES
VARIABLE _RTHP-D-MAP-ID
VARIABLE _RTHP-D-MAP-ENTRY
VARIABLE _RTHP-D-ACTIVE-VISIBLE
VARIABLE _RTHP-D-PENDING-VISIBLE
VARIABLE _RTHP-D-ACTIVE-CURSOR
VARIABLE _RTHP-D-PENDING-CURSOR
VARIABLE _RTHP-D-TAIL-CURSOR
VARIABLE _RTHP-D-POOL-FIRST
VARIABLE _RTHP-D-POOL-LIMIT
VARIABLE _RTHP-D-SCAN-BANK
VARIABLE _RTHP-D-SCAN-VISIBLE
VARIABLE _RTHP-D-SCAN-TAIL
VARIABLE _RTHP-D-SCAN-PRIOR-ROW
VARIABLE _RTHP-D-SCAN-PRIOR-END
VARIABLE _RTHP-D-SCAN-ROW
VARIABLE _RTHP-D-SCAN-COL
VARIABLE _RTHP-D-SCAN-END

: _RTHP-D-MAP-AT  ( slot -- a )
    8 * _RTHP-D-MAP-A @ + ;

: _RTHP-D-ID>MAP?  ( id -- entry-a flag )
    DUP _RTHP-D-GLYPH-BASE @ U< IF DROP 0 0 EXIT THEN
    _RTHP-D-GLYPH-BASE @ - DUP _RTHP-D-SLOTS @ U< 0= IF
        DROP 0 0 EXIT
    THEN
    _RTHP-D-MAP-AT -1 ;

: _RTHP-D-REF-TEXT-EMPTY?  ( ref -- flag )
    RGRP-TEXT-REF-LENGTH@ 0= ;

: _RTHP-D-CANONICAL-BEGIN  ( bank -- )
    _RTHP-D-SCAN-BANK !
    0 _RTHP-D-SCAN-VISIBLE ! 0 _RTHP-D-SCAN-TAIL !
    -1 _RTHP-D-SCAN-PRIOR-ROW ! 0 _RTHP-D-SCAN-PRIOR-END ! ;

\ Validate one item in the exact ordering contract consumed by row-damage
\ reuse.  Callers own the single bounded traversal and may fuse their own
\ per-slot proof after this succeeds.  IDs deliberately are not part of this
\ check: acknowledged slots carry stable IDs while fresh slots are monotone.
: _RTHP-D-CANONICAL-SLOT?  ( index -- flag )
    DUP _RTHP-D-SCAN-BANK @ _RTHP-D-ITEM-AT _RTHP-D-PENDING-I !
    _RTHP-D-SCAN-BANK @ _RTHP-D-REF-AT _RTHP-D-PENDING-R !
    _RTHP-D-PENDING-I @ _RTE-LPI.PARENT @ IF 0 EXIT THEN
    _RTHP-D-PENDING-I @ _RTE-LPI.RESERVED @ IF 0 EXIT THEN
    _RTHP-D-PENDING-I @ _RTE-LPI.VISIBLE @ _RTE-BOOL? 0= IF
        0 EXIT
    THEN
    _RTHP-D-PENDING-I @ _RTE-LPI.FG-RGBA @
        0xFFFFFFFF U> IF 0 EXIT THEN
    _RTHP-D-PENDING-I @ _RTE-LPI.BG-RGBA @
        0xFFFFFFFF U> IF 0 EXIT THEN
    _RTHP-D-PENDING-I @ _RTE-LPI.ATTRS @
        _RTE-GLYPH-RUN-ATTRS? 0= IF 0 EXIT THEN
    _RTHP-D-PENDING-I @ _RTE-LPI.ROOT-HEIGHT @
        _RTHP-D-SCAN-BANK @ _RTHP-TB.ROWS @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING-I @ _RTE-LPI.ROOT-WIDTH @
        _RTHP-D-SCAN-BANK @ _RTHP-TB.COLS @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING-I @ _RTHP-D-PENDING-R @
    _RTHP-D-SCAN-BANK @ _RTHP-D-REF-VALID? 0= IF 0 EXIT THEN
    _RTHP-D-PENDING-I @ _RTE-LPI.VISIBLE @ IF
        _RTHP-D-SCAN-TAIL @ IF 0 EXIT THEN
        _RTHP-D-PENDING-I @ _RTE-LPI.HEIGHT @ 1 <> IF 0 EXIT THEN
        _RTHP-D-PENDING-I @ _RTE-LPI.ROW @ DUP
            _RTHP-D-SCAN-ROW ! 0< IF 0 EXIT THEN
        _RTHP-D-SCAN-ROW @
            _RTHP-D-SCAN-BANK @ _RTHP-TB.ROWS @ U< 0= IF 0 EXIT THEN
        _RTHP-D-PENDING-I @ _RTE-LPI.COL @ DUP
            _RTHP-D-SCAN-COL ! 0< IF 0 EXIT THEN
        _RTHP-D-PENDING-I @ _RTE-LPI.WIDTH @ DUP 0> 0= IF
            DROP 0 EXIT
        THEN
        _RTHP-D-SCAN-COL @ SWAP _RTHP-U32+?
            0= IF DROP 0 EXIT THEN DUP _RTHP-D-SCAN-END !
        _RTHP-D-SCAN-BANK @ _RTHP-TB.COLS @ U> IF 0 EXIT THEN
        _RTHP-D-SCAN-VISIBLE @ IF
            _RTHP-D-SCAN-ROW @ _RTHP-D-SCAN-PRIOR-ROW @ < IF
                0 EXIT
            THEN
            _RTHP-D-SCAN-ROW @ _RTHP-D-SCAN-PRIOR-ROW @ =
            _RTHP-D-SCAN-COL @ _RTHP-D-SCAN-PRIOR-END @ U< AND IF
                0 EXIT
            THEN
        THEN
        _RTHP-D-SCAN-ROW @ _RTHP-D-SCAN-PRIOR-ROW !
        _RTHP-D-SCAN-END @ _RTHP-D-SCAN-PRIOR-END !
        1 _RTHP-D-SCAN-VISIBLE +!
    ELSE
        -1 _RTHP-D-SCAN-TAIL !
        _RTHP-D-PENDING-I @ _RTE-LPI.ROW @ IF 0 EXIT THEN
        _RTHP-D-PENDING-I @ _RTE-LPI.COL @ IF 0 EXIT THEN
        _RTHP-D-PENDING-I @ _RTE-LPI.HEIGHT @ 1 <> IF 0 EXIT THEN
        _RTHP-D-PENDING-I @ _RTE-LPI.WIDTH @ 1 <> IF 0 EXIT THEN
        _RTHP-D-PENDING-I @ _RTE-LPI.TEXT-CAPACITY @ IF 0 EXIT THEN
        _RTHP-D-PENDING-R @ _RTHP-D-REF-TEXT-EMPTY? 0= IF 0 EXIT THEN
    THEN
    -1 ;

: _RTHP-D-GLYPH-BOUNDS?  ( -- flag )
    _RTHP-D-ACTIVE @ _RTHP-TB.GLYPH-SLOT-COUNT @
        DUP _RTHP-D-ACTIVE-SLOTS !
    _RTHP-D-PENDING @ _RTHP-TB.GLYPH-SLOT-COUNT @ MAX _RTHP-D-SLOTS !
    _RTHP-D-ACTIVE-SLOTS @ 0= IF
        _RTHP-D-P @ _RTHP.NEXT-OBJECT @ DUP 0= IF DROP 0 EXIT THEN
            _RTHP-D-GLYPH-BASE !
    ELSE _RTHP-D-KEPT @ IF
        \ The slot map still proves every active ID lies in this interval.
        _RTHP-D-P @ _RTHP.ACTIVE-FACTS _RTHP-KF.BASE @
            DUP 0= IF DROP 0 EXIT THEN _RTHP-D-GLYPH-BASE !
    ELSE
        0 _RTHP-D-ACTIVE @ _RTHP-D-ITEM-AT _RTE-LPI.OBJECT @
            DUP 0= IF DROP 0 EXIT THEN _RTHP-D-GLYPH-BASE !
        _RTHP-D-ACTIVE-SLOTS @ 1 ?DO
            I _RTHP-D-ACTIVE @ _RTHP-D-ITEM-AT _RTE-LPI.OBJECT @
                DUP 0= IF DROP 0 UNLOOP EXIT THEN
                _RTHP-D-GLYPH-BASE @ _RTHP-UMIN
                _RTHP-D-GLYPH-BASE !
        LOOP
    THEN THEN
    _RTHP-D-GLYPH-BASE @ _RTHP-D-SLOTS @ _RTHP-U+?
        0= IF DROP 0 EXIT THEN DROP
    _RTHP-D-SLOTS @ _RTHP-D-ACTIVE-SLOTS @ U> IF
        _RTHP-D-ACTIVE @ _RTHP-TB.CONTROL-COUNT @
            _RTHP-D-PENDING @ _RTHP-TB.CONTROL-COUNT @ <> IF 0 EXIT THEN
        _RTHP-D-ACTIVE @ _RTHP-TB.INSTRUMENT-COUNT @
            _RTHP-D-PENDING @ _RTHP-TB.INSTRUMENT-COUNT @ <> IF 0 EXIT THEN
        _RTHP-D-GLYPH-BASE @ _RTHP-D-ACTIVE-SLOTS @ _RTHP-U+?
            0= IF DROP 0 EXIT THEN
        _RTHP-D-P @ _RTHP.NEXT-OBJECT @ <> IF 0 EXIT THEN
    THEN
    -1 ;

: _RTHP-D-GROWTH-CONTROLS?  ( -- flag )
    _RTHP-D-SLOTS @ _RTHP-D-ACTIVE-SLOTS @ U> 0= IF -1 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.CONTROL-COUNT @ 0 ?DO
        I _RTHP-D-CONTROL-MAP-AT @ 0= IF 0 UNLOOP EXIT THEN
    LOOP -1 ;

\ The comparison that built the active bank proved every slot canonical as its
\ pending bank.  Normalization since wrote only object IDs and canonical
\ tombstones, and no word writes an active bank.  Still prove the IDs one
\ exact permutation of the slot interval, which also proves the kept base.
: _RTHP-D-KEPT-SLOT-MAP?  ( -- flag )
    _RTHP-D-ACTIVE @ _RTHP-D-ITEMS-A
    _RTHP-D-ACTIVE-SLOTS @ 0 ?DO
        DUP _RTE-LPI.OBJECT @ _RTHP-D-ID>MAP?
            0= IF 2DROP 0 UNLOOP EXIT THEN
        DUP _RTHP-D-MAP-A @ - 8 /
            _RTHP-D-ACTIVE-SLOTS @ U< 0= IF 2DROP 0 UNLOOP EXIT THEN
        DUP @ IF 2DROP 0 UNLOOP EXIT THEN
        I 1+ SWAP !
        RTE-GLYPH-RUN-PLAN-ITEM-SIZE +
    LOOP DROP
    _RTHP-D-P @ _RTHP.ACTIVE-FACTS _RTHP-KF.VISIBLE @
        _RTHP-D-ACTIVE-VISIBLE !
    -1 ;

: _RTHP-D-BUILD-SLOT-MAP?  ( -- flag )
    _RTHP-D-GLYPH-BOUNDS? 0= IF 0 EXIT THEN
    _RTHP-D-GROWTH-CONTROLS? 0= IF 0 EXIT THEN
    _RTHP-D-P @ _RTHP.GLYPH-ID-MAP-A @ DUP 0= SWAP 7 AND OR IF
        0 EXIT
    THEN
    _RTHP-D-P @ _RTHP.GLYPH-ID-MAP-A @ _RTHP-D-MAP-A !
    _RTHP-D-P @ _RTHP.GLYPH-ID-MAP-U @ _RTHP-D-MAP-U !
    _RTHP-D-SLOTS @ 8 _RTHP-U32*? 0= IF DROP 0 EXIT THEN
    DUP _RTHP-D-MAP-U @ U> IF DROP 0 EXIT THEN
    DUP IF
        _RTHP-D-MAP-A @ OVER _RTHP-D-P @ _RTHP-ARENA-SPAN?
            0= IF DROP 0 EXIT THEN
    THEN
    _RTHP-D-MAP-BYTES !
    _RTHP-D-P @ _RTHP-TARGET-BANK-BYTES?
        0= IF DROP 0 EXIT THEN _RTHP-D-BANK-BYTES !
    _RTHP-D-MAP-A @ _RTHP-D-MAP-BYTES @
    _RTHP-D-P @ _RTHP.TARGET0-A @ _RTHP-D-BANK-BYTES @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTHP-D-MAP-A @ _RTHP-D-MAP-BYTES @
    _RTHP-D-P @ _RTHP.TARGET1-A @ _RTHP-D-BANK-BYTES @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTHP-D-MAP-A @ _RTHP-D-MAP-BYTES @ 0 FILL
    _RTHP-D-KEPT @ IF _RTHP-D-KEPT-SLOT-MAP? EXIT THEN
    _RTHP-D-ACTIVE @ _RTHP-D-CANONICAL-BEGIN
    _RTHP-D-ACTIVE-SLOTS @ 0 ?DO
        I _RTHP-D-CANONICAL-SLOT? 0= IF 0 UNLOOP EXIT THEN
        _RTHP-D-PENDING-I @ _RTE-LPI.OBJECT @
            DUP _RTHP-D-MAP-ID ! _RTHP-D-ID>MAP?
            0= IF DROP 0 UNLOOP EXIT THEN
            DUP _RTHP-D-MAP-A @ - 8 /
                _RTHP-D-ACTIVE-SLOTS @ U< 0= IF DROP 0 UNLOOP EXIT THEN
            DUP @ IF DROP 0 UNLOOP EXIT THEN
        I 1+ SWAP !
    LOOP
    _RTHP-D-SCAN-VISIBLE @ _RTHP-D-ACTIVE-VISIBLE !
    -1 ;

: _RTHP-D-ACTIVE-INDEX?  ( id -- index flag )
    DUP _RTHP-D-MAP-ID ! _RTHP-D-ID>MAP?
        0= IF DROP 0 0 EXIT THEN
    DUP _RTHP-D-MAP-ENTRY !
    @ DUP 0< 0= IF DROP 0 0 EXIT THEN
    NEGATE 1- DUP _RTHP-D-ACTIVE-SLOTS @ U< 0= IF DROP 0 0 EXIT THEN
    DUP _RTHP-D-ACTIVE @ _RTHP-D-ITEM-AT
        DUP _RTHP-D-ACTIVE-I ! _RTE-LPI.OBJECT @
        _RTHP-D-MAP-ID @ <> IF DROP 0 0 EXIT THEN
    -1 ;

: _RTHP-D-SLOT-USE?  ( active-index pending-index -- flag )
    _RTHP-D-PENDING-CURSOR ! _RTHP-D-ACTIVE-CURSOR !
    _RTHP-D-ACTIVE-CURSOR @ _RTHP-D-ACTIVE-SLOTS @ U< 0= IF 0 EXIT THEN
    _RTHP-D-PENDING-CURSOR @ _RTHP-D-SLOTS @ U< 0= IF 0 EXIT THEN
    _RTHP-D-ACTIVE-CURSOR @ _RTHP-D-ACTIVE @ _RTHP-D-ITEM-AT
        DUP _RTHP-D-ACTIVE-I ! _RTE-LPI.OBJECT @
        DUP _RTHP-D-MAP-ID ! _RTHP-D-ID>MAP?
        0= IF DROP 0 EXIT THEN DUP _RTHP-D-MAP-ENTRY !
    @ _RTHP-D-ACTIVE-CURSOR @ 1+ <> IF 0 EXIT THEN
    _RTHP-D-MAP-ENTRY @ DUP @ NEGATE SWAP !
    _RTHP-D-MAP-ID @
    _RTHP-D-PENDING-CURSOR @ _RTHP-D-PENDING @ _RTHP-D-ITEM-AT
        _RTE-LPI.OBJECT !
    -1 ;

: _RTHP-D-ANCHOR-COMPARE  ( -- -1|0|1 )
    _RTHP-D-ACTIVE-I @ _RTE-LPI.ROW @
    _RTHP-D-PENDING-I @ _RTE-LPI.ROW @
    2DUP < IF 2DROP -1 EXIT THEN
    > IF 1 EXIT THEN
    _RTHP-D-ACTIVE-I @ _RTE-LPI.COL @
    _RTHP-D-PENDING-I @ _RTE-LPI.COL @
    2DUP < IF 2DROP -1 EXIT THEN
    > IF 1 ELSE 0 THEN ;

: _RTHP-D-MATCH-ANCHORS?  ( -- flag )
    \ Validate the pending ordering and freshly captured namespace while
    \ performing the mandatory object-ID clear for anchor matching.
    _RTHP-D-PENDING @ _RTHP-D-CANONICAL-BEGIN
    _RTHP-D-SLOTS @ 0 ?DO
        I _RTHP-D-CANONICAL-SLOT? 0= IF 0 UNLOOP EXIT THEN
        _RTHP-D-PENDING-FIRST @
        _RTHP-D-PENDING @ _RTHP-TB.CONTROL-COUNT @
        _RTHP-D-PENDING @ _RTHP-TB.INSTRUMENT-COUNT @ +
        _RTHP-D-PENDING @ _RTHP-TB.STATIC-COUNT @ + I
            _RTHP-D-GLYPH-EXPECTED? 0= IF DROP 0 UNLOOP EXIT THEN
        _RTHP-D-PENDING-I @ _RTE-LPI.OBJECT @
            <> IF 0 UNLOOP EXIT THEN
        0 _RTHP-D-PENDING-I @ _RTE-LPI.OBJECT !
    LOOP
    _RTHP-D-SCAN-VISIBLE @ _RTHP-D-PENDING-VISIBLE !
    0 _RTHP-D-ACTIVE-CURSOR ! 0 _RTHP-D-PENDING-CURSOR !
    BEGIN
        _RTHP-D-ACTIVE-CURSOR @ _RTHP-D-ACTIVE-VISIBLE @ U<
        _RTHP-D-PENDING-CURSOR @ _RTHP-D-PENDING-VISIBLE @ U< AND
    WHILE
        _RTHP-D-ACTIVE-CURSOR @ _RTHP-D-ACTIVE @ _RTHP-D-ITEM-AT
            _RTHP-D-ACTIVE-I !
        _RTHP-D-PENDING-CURSOR @ _RTHP-D-PENDING @ _RTHP-D-ITEM-AT
            _RTHP-D-PENDING-I !
        _RTHP-D-ANCHOR-COMPARE DUP 0< IF
            DROP 1 _RTHP-D-ACTIVE-CURSOR +!
        ELSE DUP 0> IF
            DROP 1 _RTHP-D-PENDING-CURSOR +!
        ELSE
            DROP
            _RTHP-D-ACTIVE-CURSOR @ _RTHP-D-PENDING-CURSOR @
                _RTHP-D-SLOT-USE? 0= IF 0 EXIT THEN
            1 _RTHP-D-ACTIVE-CURSOR +!
            1 _RTHP-D-PENDING-CURSOR +!
        THEN THEN
    REPEAT
    -1 ;

: _RTHP-D-NEXT-UNMATCHED-VISIBLE?  ( -- index flag )
    BEGIN _RTHP-D-PENDING-CURSOR @
        _RTHP-D-PENDING-VISIBLE @ U< WHILE
        _RTHP-D-PENDING-CURSOR @ DUP
            _RTHP-D-PENDING @ _RTHP-D-ITEM-AT _RTE-LPI.OBJECT @ 0= IF
            1 _RTHP-D-PENDING-CURSOR +! -1 EXIT
        THEN
        DROP 1 _RTHP-D-PENDING-CURSOR +!
    REPEAT
    0 0 ;

: _RTHP-D-ACTIVE-UNUSED?  ( active-index -- flag )
    _RTHP-D-ACTIVE @ _RTHP-D-ITEM-AT _RTE-LPI.OBJECT @
        _RTHP-D-ID>MAP? 0= IF DROP 0 EXIT THEN @ 0> ;

: _RTHP-D-ASSIGN-VISIBLE-POOL?  ( first limit -- flag )
    _RTHP-D-POOL-LIMIT ! _RTHP-D-POOL-FIRST !
    BEGIN _RTHP-D-POOL-FIRST @ _RTHP-D-POOL-LIMIT @ U< WHILE
        _RTHP-D-POOL-FIRST @ _RTHP-D-ACTIVE-UNUSED? IF
            _RTHP-D-NEXT-UNMATCHED-VISIBLE? IF
                _RTHP-D-POOL-FIRST @ SWAP _RTHP-D-SLOT-USE?
                    0= IF 0 EXIT THEN
            ELSE
                DROP -1 EXIT
            THEN
        THEN
        1 _RTHP-D-POOL-FIRST +!
    REPEAT
    -1 ;

: _RTHP-D-CANONICAL-TOMBSTONE!  ( active-index pending-index -- flag )
    _RTHP-D-PENDING-CURSOR ! _RTHP-D-ACTIVE-CURSOR !
    _RTHP-D-PENDING-CURSOR @ _RTHP-D-PENDING @ _RTHP-D-ITEM-AT
        DUP _RTHP-D-PENDING-I ! RTE-GLYPH-RUN-PLAN-ITEM-SIZE 0 FILL
    _RTHP-D-ACTIVE-CURSOR @ _RTHP-D-PENDING-CURSOR @
        _RTHP-D-SLOT-USE? 0= IF 0 EXIT THEN
    1 _RTHP-D-PENDING-I @ _RTE-LPI.HEIGHT !
    1 _RTHP-D-PENDING-I @ _RTE-LPI.WIDTH !
    _RTHP-D-PENDING @ _RTHP-TB.ROWS @
        _RTHP-D-PENDING-I @ _RTE-LPI.ROOT-HEIGHT !
    _RTHP-D-PENDING @ _RTHP-TB.COLS @
        _RTHP-D-PENDING-I @ _RTE-LPI.ROOT-WIDTH !
    _RTHP-D-PENDING-CURSOR @ _RTHP-D-PENDING @ _RTHP-D-REF-AT
        DUP _RTHP-D-PENDING-R ! RGRP-TEXT-REF-SIZE 0 FILL
    _RTHP-D-PENDING @ _RTHP-TB.GLYPH-TEXT-USED @
        _RTHP-D-PENDING-R @ _RGRP-T.OFFSET !
    -1 ;

: _RTHP-D-ASSIGN-PENDING-TAIL?  ( -- flag )
    _RTHP-D-PENDING-VISIBLE @ _RTHP-D-TAIL-CURSOR !
    _RTHP-D-ACTIVE-SLOTS @ 0 ?DO
        I _RTHP-D-ACTIVE-UNUSED? IF
            _RTHP-D-TAIL-CURSOR @ _RTHP-D-SLOTS @ U< 0= IF
                0 UNLOOP EXIT
            THEN
            I _RTHP-D-TAIL-CURSOR @ _RTHP-D-CANONICAL-TOMBSTONE!
                0= IF 0 UNLOOP EXIT THEN
            1 _RTHP-D-TAIL-CURSOR +!
        THEN
    LOOP
    _RTHP-D-TAIL-CURSOR @ _RTHP-D-SLOTS @ <> IF 0 EXIT THEN
    \ Unique slot consumption plus exact tail cardinality constructs the full
    \ ID bijection.  The following compatibility/mark/compaction pass rejects
    \ any invalid, duplicate, or unconsumed identity before publication.
    -1 ;

\ Assign only real unmatched visible glyphs after every reusable ACK slot.
\ New IDs extend the proven contiguous glyph interval at the owner frontier.
: _RTHP-D-APPEND-VISIBLE?  ( -- flag )
    _RTHP-D-SLOTS @ _RTHP-D-ACTIVE-SLOTS @ ?DO
        _RTHP-D-NEXT-UNMATCHED-VISIBLE? 0= IF DROP 0 UNLOOP EXIT THEN
        _RTHP-D-APPEND-INDEX !
        I _RTHP-D-MAP-AT DUP @ IF DROP 0 UNLOOP EXIT THEN
        _RTHP-D-APPEND-INDEX @ 1+ NEGATE SWAP !
        _RTHP-D-GLYPH-BASE @ I +
        _RTHP-D-APPEND-INDEX @ _RTHP-D-PENDING @ _RTHP-D-ITEM-AT
            _RTE-LPI.OBJECT !
    LOOP -1 ;

: _RTHP-D-NORMALIZE-GLYPH-IDS?  ( -- flag )
    _RTHP-D-PENDING @ _RTHP-TB.GLYPH-SLOT-COUNT @
        _RTHP-D-SLOTS @ <> IF 0 EXIT THEN
    _RTHP-D-MATCH-ANCHORS? 0= IF 0 EXIT THEN
    0 _RTHP-D-PENDING-CURSOR !
    _RTHP-D-ACTIVE-VISIBLE @ _RTHP-D-ACTIVE-SLOTS @
        _RTHP-D-ASSIGN-VISIBLE-POOL? 0= IF 0 EXIT THEN
    0 _RTHP-D-ACTIVE-VISIBLE @
        _RTHP-D-ASSIGN-VISIBLE-POOL? 0= IF 0 EXIT THEN
    _RTHP-D-APPEND-VISIBLE? 0= IF 0 EXIT THEN
    _RTHP-D-NEXT-UNMATCHED-VISIBLE? IF DROP 0 EXIT THEN DROP
    _RTHP-D-ASSIGN-PENDING-TAIL? ;

: _RTHP-D-GLYPH-PAIR?  ( pending-index -- flag )
    _RTHP-D-I !
    _RTHP-D-I @ _RTHP-D-PENDING @ _RTHP-D-ITEM-AT
        DUP _RTHP-D-PENDING-I !
        _RTE-LPI.OBJECT @ _RTHP-D-ACTIVE-INDEX?
        0= IF DROP 0 EXIT THEN _RTHP-D-ACTIVE-CURSOR !
    _RTHP-D-I @ _RTHP-D-PENDING @ _RTHP-D-REF-AT
        _RTHP-D-PENDING-R !
    _RTHP-D-ACTIVE-CURSOR @ _RTHP-D-ACTIVE @ _RTHP-D-REF-AT
        _RTHP-D-ACTIVE-R !
    -1 ;

: _RTHP-D-GLYPH-TEXT-EQUAL?  ( -- flag )
    _RTHP-D-ACTIVE-R @ RGRP-TEXT-REF-OFFSET@ _RTHP-D-OFFSET-A !
    _RTHP-D-ACTIVE-R @ RGRP-TEXT-REF-LENGTH@ _RTHP-D-EXPECTED-A !
    _RTHP-D-PENDING-R @ RGRP-TEXT-REF-OFFSET@ _RTHP-D-OFFSET-P !
    _RTHP-D-PENDING-R @ RGRP-TEXT-REF-LENGTH@ _RTHP-D-EXPECTED-P !
    _RTHP-D-ACTIVE @ _RTHP-D-GLYPH-A _RTHP-D-OFFSET-A @ +
    _RTHP-D-EXPECTED-A @
    _RTHP-D-ACTIVE @ _RTHP-D-GLYPH-A
    _RTHP-D-ACTIVE @ _RTHP-TB.GLYPH-TEXT-USED @
    _RTHP-D-PENDING @ _RTHP-D-GLYPH-A _RTHP-D-OFFSET-P @ +
    _RTHP-D-EXPECTED-P @
    _RTHP-D-PENDING @ _RTHP-D-GLYPH-A
    _RTHP-D-PENDING @ _RTHP-TB.GLYPH-TEXT-USED @
        _RTHP-D-TEXTS-EQUAL? ;

\ GLYPH-PAIR retains both the exact active item and its unique consumed map
\ entry.  Compare the complete payload, then turn that same entry directly
\ into the compact-plan marker without resolving the pending identity again.
\ Appended slots have no acknowledged payload to replace.  Their map entry
\ proves a single real visible pending run owns each new frontier ID.
: _RTHP-D-GLYPH-APPEND-AND-MARK?  ( index -- flag )
    _RTHP-D-I !
    _RTHP-D-I @ _RTHP-D-PENDING @ _RTHP-D-ITEM-AT
        DUP _RTHP-D-PENDING-I ! _RTE-LPI.OBJECT @
        _RTHP-D-ID>MAP? 0= IF DROP 0 EXIT THEN
    DUP _RTHP-D-MAP-ENTRY !
    _RTHP-D-MAP-A @ - 8 / _RTHP-D-ACTIVE-SLOTS @ U< IF 0 EXIT THEN
    _RTHP-D-MAP-ENTRY @ @ _RTHP-D-I @ 1+ NEGATE <> IF 0 EXIT THEN
    _RTHP-D-PENDING-I @ _RTE-LPI.VISIBLE @ -1 <> IF 0 EXIT THEN
    _RTHP-D-I @ _RTHP-D-PENDING @ _RTHP-D-REF-AT
        _RTHP-D-PENDING-R !
    _RTHP-D-PENDING-I @ _RTHP-D-PENDING-R @ _RTHP-D-PENDING @
        _RTHP-D-REF-VALID? 0= IF 0 EXIT THEN
    _RTHP-D-I @ 1+ _RTHP-D-MAP-ENTRY @ !
    1 _RTHP-D-OPS +! -1 ;

: _RTHP-D-GLYPH-COMPATIBLE-AND-MARK?  ( index -- flag )
    DUP _RTHP-D-PENDING @ _RTHP-D-ITEM-AT _RTE-LPI.OBJECT @
        _RTHP-D-P @ _RTHP.NEXT-OBJECT @ U< 0= IF
        _RTHP-D-GLYPH-APPEND-AND-MARK? EXIT
    THEN
    _RTHP-D-GLYPH-PAIR? 0= IF 0 EXIT THEN
    _RTHP-D-ACTIVE-I @ _RTE-LPI.OBJECT @
        _RTHP-D-PENDING-I @ _RTE-LPI.OBJECT @ <> IF 0 EXIT THEN
    _RTHP-D-ACTIVE-I @ _RTE-LPI.PARENT @
    _RTHP-D-PENDING-I @ _RTE-LPI.PARENT @ OR IF 0 EXIT THEN
    _RTHP-D-ACTIVE-I @ _RTHP-D-ACTIVE-R @ _RTHP-D-ACTIVE @
        _RTHP-D-REF-VALID? 0= IF 0 EXIT THEN
    _RTHP-D-PENDING-I @ _RTHP-D-PENDING-R @ _RTHP-D-PENDING @
        _RTHP-D-REF-VALID? 0= IF 0 EXIT THEN
    0 _RTHP-D-CHANGED !
    _RTHP-D-ACTIVE-I @ 8 + 112
        _RTHP-D-PENDING-I @ 8 + 112 COMPARE IF
        -1 _RTHP-D-CHANGED !
    THEN
    _RTHP-D-GLYPH-TEXT-EQUAL? 0= IF -1 _RTHP-D-CHANGED ! THEN
    _RTHP-D-MAP-ENTRY @ DUP @ 0< 0= IF DROP 0 EXIT THEN
    _RTHP-D-CHANGED @ IF
        _RTHP-D-I @ 1+ 1 _RTHP-D-OPS +!
    ELSE
        0
    THEN SWAP !
    -1 ;

\ Text-only updates commonly keep the entire glyph layout.  The active bank's
\ slots are canonical, by BUILD-SLOT-MAP's audit or by the facts kept from the
\ comparison that built it, and its IDs were just proved one permutation:
\ its visible runs come first and any invisible tombstones form its tail.
\ Exact equality of every non-ID item byte transfers that layout proof to
\ the pending bank, tail included; its fresh IDs, text references and map
\ entries still need their own checks.  A miss changes neither bank nor the
\ map, so the general spatial matcher can run immediately with its original
\ inputs.
VARIABLE _RTHP-D-LAYOUT-A-ITEMS
VARIABLE _RTHP-D-LAYOUT-P-ITEMS
VARIABLE _RTHP-D-LAYOUT-A-REFS
VARIABLE _RTHP-D-LAYOUT-P-REFS
VARIABLE _RTHP-D-LAYOUT-A-TEXT
VARIABLE _RTHP-D-LAYOUT-P-TEXT
VARIABLE _RTHP-D-LAYOUT-FIRST

: _RTHP-D-GLYPH-LAYOUT?  ( -- flag )
    _RTHP-D-ACTIVE-SLOTS @ _RTHP-D-SLOTS @ <> IF 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.GLYPH-SLOT-COUNT @
        _RTHP-D-SLOTS @ <> IF 0 EXIT THEN
    _RTHP-D-ACTIVE @ _RTHP-TB.ROWS @
        _RTHP-D-PENDING @ _RTHP-TB.ROWS @ <>
    _RTHP-D-ACTIVE @ _RTHP-TB.COLS @
        _RTHP-D-PENDING @ _RTHP-TB.COLS @ <> OR IF 0 EXIT THEN
    _RTHP-D-SLOTS @ 0= IF -1 EXIT THEN
    _RTHP-D-ACTIVE @ _RTHP-D-ITEMS-A _RTHP-D-LAYOUT-A-ITEMS !
    _RTHP-D-PENDING @ _RTHP-D-ITEMS-A _RTHP-D-LAYOUT-P-ITEMS !
    _RTHP-D-ACTIVE @ _RTHP-D-REFS-A _RTHP-D-LAYOUT-A-REFS !
    _RTHP-D-PENDING @ _RTHP-D-REFS-A _RTHP-D-LAYOUT-P-REFS !
    _RTHP-D-ACTIVE @ _RTHP-D-GLYPH-A _RTHP-D-LAYOUT-A-TEXT !
    _RTHP-D-PENDING @ _RTHP-D-GLYPH-A _RTHP-D-LAYOUT-P-TEXT !
    _RTHP-D-PENDING @ _RTHP-TB.CONTROL-COUNT @
    _RTHP-D-PENDING @ _RTHP-TB.INSTRUMENT-COUNT @ _RTHP-U+?
        0= IF DROP 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-TB.STATIC-COUNT @ _RTHP-U+?
        0= IF DROP 0 EXIT THEN
    _RTHP-D-PENDING-FIRST @ _RTHP-U+?
        0= IF DROP 0 EXIT THEN DUP _RTHP-D-LAYOUT-FIRST !
    _RTHP-D-SLOTS @ 1- _RTHP-U+? 0= IF DROP 0 EXIT THEN DROP
    _RTHP-D-SLOTS @ 0 ?DO
        _RTHP-D-LAYOUT-A-ITEMS @ I RTE-GLYPH-RUN-PLAN-ITEM-SIZE * +
            _RTHP-D-ACTIVE-I !
        _RTHP-D-LAYOUT-P-ITEMS @ I RTE-GLYPH-RUN-PLAN-ITEM-SIZE * +
            _RTHP-D-PENDING-I !
        _RTHP-D-PENDING-I @ _RTE-LPI.OBJECT @
            _RTHP-D-LAYOUT-FIRST @ I + <> IF 0 UNLOOP EXIT THEN
        _RTHP-D-ACTIVE-I @ 8 + RTE-GLYPH-RUN-PLAN-ITEM-SIZE 8 -
        _RTHP-D-PENDING-I @ 8 + RTE-GLYPH-RUN-PLAN-ITEM-SIZE 8 -
            COMPARE IF 0 UNLOOP EXIT THEN
        _RTHP-D-PENDING-I @
        _RTHP-D-LAYOUT-P-REFS @ I RGRP-TEXT-REF-SIZE * +
        _RTHP-D-PENDING @ _RTHP-D-REF-VALID? 0= IF 0 UNLOOP EXIT THEN
        _RTHP-D-ACTIVE-I @ _RTE-LPI.OBJECT @ _RTHP-D-ID>MAP?
            0= IF DROP 0 UNLOOP EXIT THEN
        @ I 1+ <> IF 0 UNLOOP EXIT THEN
    LOOP -1 ;

\ A successful proof fixes both packed layouts for this immediate pass.
\ Every visible anchor keeps its original ordinal, and every tombstone of
\ the tail its acknowledged ID in order, exactly as the general matcher
\ would assign them.  A tail reference takes the canonical form the general
\ tail pass writes.  Populate the same sparse change markers for ordinary
\ compaction; do not retain this proof at emit.
: _RTHP-D-TRY-GLYPH-LAYOUT?  ( -- flag )
    _RTHP-D-GLYPH-LAYOUT? 0= IF 0 EXIT THEN
    \ The unchanged-frame revision fence also needs this draw's visible count,
    \ which equal item bytes make the acknowledged one.
    _RTHP-D-ACTIVE-VISIBLE @ _RTHP-D-PENDING-VISIBLE !
    _RTHP-D-SLOTS @ 0 ?DO
        _RTHP-D-LAYOUT-A-ITEMS @ I RTE-GLYPH-RUN-PLAN-ITEM-SIZE * + @
        DUP _RTHP-D-LAYOUT-P-ITEMS @ I RTE-GLYPH-RUN-PLAN-ITEM-SIZE * + !
        _RTHP-D-GLYPH-BASE @ - _RTHP-D-MAP-AT _RTHP-D-MAP-ENTRY !
        I _RTHP-D-ACTIVE-VISIBLE @ U< 0= IF
            _RTHP-D-LAYOUT-P-REFS @ I RGRP-TEXT-REF-SIZE * +
                DUP RGRP-TEXT-REF-SIZE 0 FILL
            _RTHP-D-PENDING @ _RTHP-TB.GLYPH-TEXT-USED @ SWAP _RGRP-T.OFFSET !
        THEN
        _RTHP-D-LAYOUT-A-REFS @ I RGRP-TEXT-REF-SIZE * +
            DUP RGRP-TEXT-REF-OFFSET@ _RTHP-D-LAYOUT-A-TEXT @ +
            SWAP RGRP-TEXT-REF-LENGTH@
        _RTHP-D-LAYOUT-P-REFS @ I RGRP-TEXT-REF-SIZE * +
            DUP RGRP-TEXT-REF-OFFSET@ _RTHP-D-LAYOUT-P-TEXT @ +
            SWAP RGRP-TEXT-REF-LENGTH@
        COMPARE IF I 1+ 1 _RTHP-D-OPS +! ELSE 0 THEN
        _RTHP-D-MAP-ENTRY @ !
    LOOP -1 ;

\ A completed ordinary draw may prove retained-equivalent to its acknowledged
\ surface after stable-identity normalization.  RET_DELTA deliberately forbids
\ an empty transaction, but falling back to REPLACE_START would redefine the
\ complete surface merely to obtain the next physical revision.  Mark one
\ already acknowledged slot for an idempotent replacement instead.  Prefer the
\ canonical invisible tail so the revision carrier has no visible payload;
\ semantic controls and then the first visible glyph remain generic fallbacks
\ for banks without a reserve.
: _RTHP-D-PLAN-FENCE-GLYPH?  ( pending-index -- flag )
    DUP _RTHP-D-I !
    DUP _RTHP-D-SLOTS @ U< 0= IF DROP 0 EXIT THEN
    _RTHP-D-PENDING @ _RTHP-D-ITEM-AT _RTE-LPI.OBJECT @
        _RTHP-D-ID>MAP? 0= IF DROP 0 EXIT THEN
    DUP @ 0<> IF DROP 0 EXIT THEN
    _RTHP-D-I @ 1+ SWAP !
    1 _RTHP-D-OPS +! -1 ;

: _RTHP-D-PLAN-REVISION-FENCE?  ( -- flag )
    _RTHP-D-PENDING-VISIBLE @ _RTHP-D-SLOTS @ U< IF
        _RTHP-D-PENDING-VISIBLE @ _RTHP-D-PLAN-FENCE-GLYPH? EXIT
    THEN
    _RTHP-D-PENDING @ _RTHP-TB.CONTROL-COUNT @ IF
        0 _RTHP-D-CONTROL-PAIR 0= IF 0 EXIT THEN
        _RTHP-D-MATCHED @ 0= IF 0 EXIT THEN
        _RTHP-D-CONTROL-MARK-CHANGED? 0= IF 0 EXIT THEN
        1 _RTHP-D-OPS +! -1 EXIT
    THEN
    _RTHP-D-SLOTS @ IF 0 _RTHP-D-PLAN-FENCE-GLYPH? EXIT THEN
    0 ;

\ Compact changed pending ordinals forward in stable object-ID order.  DELTA
\ replacements are independent atomic object mutations.  New definitions
\ follow them in increasing frontier order.  The write cursor never passes the
\ read cursor, making the in-place compaction overlap-safe.
: _RTHP-D-PLAN-COMPACT-GLYPHS  ( -- flag )
    0 _RTHP-D-PLAN-GLYPHS !
    _RTHP-D-SLOTS @ 0 ?DO
        I _RTHP-D-MAP-AT @ DUP 0< IF DROP 0 UNLOOP EXIT THEN
        ?DUP IF
            1- DUP _RTHP-D-SLOTS @ U< 0= IF
                DROP 0 UNLOOP EXIT
            THEN
            2* I _RTHP-D-ACTIVE-SLOTS @ U< 0= IF 1+ THEN
            _RTHP-D-MAP-A @ _RTHP-D-PLAN-GLYPHS @ 8 * + !
            1 _RTHP-D-PLAN-GLYPHS +!
        THEN
    LOOP -1 ;

\ Convert the signed semantic map into the existing delayed wire-plan words.
\ Load each map cell before writing because the compact output may occupy that
\ same cell.  At most one operation is emitted per input ordinal, so the write
\ cursor never reaches an unread cell.
: _RTHP-D-PLAN-COMPACT-CONTROLS?  ( -- flag )
    0 _RTHP-D-PLAN-CONTROLS !
    _RTHP-D-PENDING @ _RTHP-TB.CONTROL-COUNT @ 0 ?DO
        I _RTHP-D-CONTROL-MAP-AT @ _RTHP-D-PLAN-MAP-VALUE !
        _RTHP-D-PLAN-MAP-VALUE @ 0= IF
            I _RTHP-D-CONTROL-ORDINAL !
            _RTHP-D-PLAN-CONTROL-DEFINE! 0= IF 0 UNLOOP EXIT THEN
        ELSE
            _RTHP-D-PLAN-MAP-VALUE @ 0< IF
                I _RTHP-D-CONTROL-ORDINAL !
                _RTHP-D-PLAN-CONTROL! 0= IF 0 UNLOOP EXIT THEN
            THEN
        THEN
    LOOP -1 ;

: _RTHP-D-PLAN-SEAL  ( -- )
    _RTHP-D-ACTIVE @
        _RTHP-D-P @ _RTHP.DELTA-PLAN-ACTIVE !
    _RTHP-D-PENDING @
        _RTHP-D-P @ _RTHP.DELTA-PLAN-PENDING !
    _RTHP-D-ACTIVE @ _RTHP-TB.DRAW @
        _RTHP-D-P @ _RTHP.DELTA-PLAN-ACTIVE-DRAW !
    _RTHP-D-PENDING @ _RTHP-TB.DRAW @
        _RTHP-D-P @ _RTHP.DELTA-PLAN-PENDING-DRAW !
    _RTHP-D-PLAN-CONTROLS @
        _RTHP-D-P @ _RTHP.DELTA-PLAN-CONTROLS !
    _RTHP-D-PLAN-GLYPHS @
        _RTHP-D-P @ _RTHP.DELTA-PLAN-GLYPHS !
    _RTHP-D-P @ _RTHP.ATTEMPT @
        _RTHP-D-P @ _RTHP.DELTA-PLAN-ATTEMPT !
    _RTHP-D-PENDING @ _RTHP-TB.SOURCE-GEN @
        _RTHP-D-P @ _RTHP.DELTA-PLAN-SOURCE-GEN !
    _RTHP-D-PENDING @ _RTHP-TB.CONTENT-EPOCH @
        _RTHP-D-P @ _RTHP.DELTA-PLAN-PENDING-CONTENT !
    _RTHP-D-ACTIVE @ _RTHP-TB.CONTENT-EPOCH @
        _RTHP-D-P @ _RTHP.DELTA-PLAN-ACTIVE-CONTENT !
    -1 _RTHP-D-P @ _RTHP.DELTA-PLAN-VALID ! ;

\ The compact glyph plan uses the same low DEFINE bit as the control plan.
: _RTHP-D-PLAN-GLYPH-AT  ( plan-index -- glyph-index definition? )
    8 * _RTHP-D-P @ _RTHP.GLYPH-ID-MAP-A @ + @
    DUP 1 AND SWAP 2/ SWAP ;

VARIABLE _RTHP-D-PLAN-LAST-GLYPH
VARIABLE _RTHP-D-PLAN-NEXT-GLYPH
VARIABLE _RTHP-D-PLAN-NEW-GLYPHS

: _RTHP-D-PLAN-GLYPHS-VALID?  ( -- flag )
    _RTHP-D-GLYPH-BOUNDS? 0= IF 0 EXIT THEN
    0 _RTHP-D-PLAN-LAST-GLYPH ! 0 _RTHP-D-PLAN-NEW-GLYPHS !
    _RTHP-D-P @ _RTHP.NEXT-OBJECT @ _RTHP-D-PLAN-NEXT-GLYPH !
    _RTHP-D-PLAN-GLYPHS @ 0 ?DO
        I _RTHP-D-PLAN-GLYPH-AT _RTHP-D-PLAN-DEFINE !
        DUP _RTHP-D-PENDING @ _RTHP-TB.GLYPH-SLOT-COUNT @ U< 0= IF
            DROP 0 UNLOOP EXIT
        THEN
        _RTHP-D-PENDING @ _RTHP-D-ITEM-AT DUP _RTHP-D-PENDING-I !
            _RTE-LPI.OBJECT @ DUP _RTHP-D-MAP-ID !
        _RTHP-D-PLAN-LAST-GLYPH @ U> 0= IF 0 UNLOOP EXIT THEN
        _RTHP-D-MAP-ID @ _RTHP-D-PLAN-LAST-GLYPH !
        _RTHP-D-PLAN-DEFINE @ IF
            _RTHP-D-SLOTS @ _RTHP-D-ACTIVE-SLOTS @ U> 0= IF
                0 UNLOOP EXIT
            THEN
            _RTHP-D-MAP-ID @ _RTHP-D-PLAN-NEXT-GLYPH @ <> IF
                0 UNLOOP EXIT
            THEN
            _RTHP-D-PENDING-I @ _RTE-LPI.VISIBLE @ -1 <> IF
                0 UNLOOP EXIT
            THEN
            _RTHP-D-PLAN-NEXT-GLYPH @ 1 _RTHP-U+?
                0= IF DROP 0 UNLOOP EXIT THEN _RTHP-D-PLAN-NEXT-GLYPH !
            1 _RTHP-D-PLAN-NEW-GLYPHS +!
        ELSE
            _RTHP-D-MAP-ID @ _RTHP-D-GLYPH-BASE @ U< IF
                0 UNLOOP EXIT
            THEN
            _RTHP-D-MAP-ID @ _RTHP-D-GLYPH-BASE @ -
                _RTHP-D-ACTIVE-SLOTS @ U< 0= IF 0 UNLOOP EXIT THEN
        THEN
    LOOP
    _RTHP-D-PLAN-NEW-GLYPHS @
        _RTHP-D-SLOTS @ _RTHP-D-ACTIVE-SLOTS @ - = ;

: _RTHP-D-PLAN-BIND?  ( producer -- flag )
    _RTHP-D-BIND? 0= IF 0 EXIT THEN
    _RTHP-D-P @ _RTHP.DELTA-PLAN-VALID @ 0= IF 0 EXIT THEN
    _RTHP-D-P @ _RTHP.DELTA-PLAN-ACTIVE @
        _RTHP-D-ACTIVE @ <> IF 0 EXIT THEN
    _RTHP-D-P @ _RTHP.DELTA-PLAN-PENDING @
        _RTHP-D-PENDING @ <> IF 0 EXIT THEN
    _RTHP-D-P @ _RTHP.DELTA-PLAN-ACTIVE-DRAW @
        _RTHP-D-ACTIVE @ _RTHP-TB.DRAW @ <> IF 0 EXIT THEN
    _RTHP-D-P @ _RTHP.DELTA-PLAN-PENDING-DRAW @
        _RTHP-D-PENDING @ _RTHP-TB.DRAW @ <> IF 0 EXIT THEN
    _RTHP-D-P @ _RTHP.DELTA-PLAN-ATTEMPT @
        _RTHP-D-P @ _RTHP.ATTEMPT @ <> IF 0 EXIT THEN
    _RTHP-D-P @ _RTHP.DELTA-PLAN-SOURCE-GEN @
        _RTHP-D-PENDING @ _RTHP-TB.SOURCE-GEN @ <> IF 0 EXIT THEN
    _RTHP-D-P @ _RTHP.DELTA-PLAN-PENDING-CONTENT @
        _RTHP-D-PENDING @ _RTHP-TB.CONTENT-EPOCH @ <> IF 0 EXIT THEN
    _RTHP-D-P @ _RTHP.DELTA-PLAN-ACTIVE-CONTENT @
        _RTHP-D-ACTIVE @ _RTHP-TB.CONTENT-EPOCH @ <> IF 0 EXIT THEN
    _RTHP-D-ACTIVE @ _RTHP-TB.GLYPH-SLOT-COUNT @
        _RTHP-D-PENDING @ _RTHP-TB.GLYPH-SLOT-COUNT @ U> IF 0 EXIT THEN
    _RTHP-D-P @ _RTHP.DELTA-PLAN-CONTROLS @
        DUP _RTHP-D-PLAN-CONTROLS !
        _RTHP-D-PENDING @ _RTHP-TB.CONTROL-COUNT @ U> IF 0 EXIT THEN
    _RTHP-D-PLAN-CONTROLS @ 8 _RTHP-U32*?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-D-P @ _RTHP.ORDER2-U @ U> IF DROP 0 EXIT THEN
    DUP IF
        _RTHP-D-P @ _RTHP.ORDER2-A @ OVER _RTHP-D-P @
            _RTHP-ARENA-SPAN? 0= IF DROP 0 EXIT THEN
    THEN DROP
    _RTHP-D-P @ _RTHP.DELTA-PLAN-GLYPHS @
        DUP _RTHP-D-PLAN-GLYPHS !
        _RTHP-D-PENDING @ _RTHP-TB.GLYPH-SLOT-COUNT @ U> IF 0 EXIT THEN
    _RTHP-D-PLAN-GLYPHS @ 8 _RTHP-U32*?
        0= IF DROP 0 EXIT THEN
    DUP _RTHP-D-P @ _RTHP.GLYPH-ID-MAP-U @ U> IF DROP 0 EXIT THEN
    DUP IF
        _RTHP-D-P @ _RTHP.GLYPH-ID-MAP-A @ OVER _RTHP-D-P @
            _RTHP-ARENA-SPAN? 0= IF DROP 0 EXIT THEN
    THEN DROP
    _RTHP-D-PLAN-GLYPHS-VALID? 0= IF 0 EXIT THEN
    0 _RTHP-D-PLAN-LAST-DEFINE !
    _RTHP-D-PLAN-CONTROLS @ 0 ?DO
        I _RTHP-D-PLAN-CONTROL-AT _RTHP-D-PLAN-DEFINE !
        DUP _RTHP-D-PENDING @ _RTHP-TB.CONTROL-COUNT @ U< 0= IF
            DROP 0 UNLOOP EXIT
        THEN
        _RTHP-D-PENDING @ _RTHP-D-CONTROL-AT _RTE-CONTROL.ID @
        _RTHP-D-PLAN-DEFINE @ IF
            _RTHP-D-SLOTS @ _RTHP-D-ACTIVE-SLOTS @ U> IF
                DROP 0 UNLOOP EXIT
            THEN
            DUP _RTHP-D-P @ _RTHP.NEXT-OBJECT @ U< IF
                DROP 0 UNLOOP EXIT
            THEN
            DUP _RTHP-D-PLAN-LAST-DEFINE @ U> 0= IF
                DROP 0 UNLOOP EXIT
            THEN _RTHP-D-PLAN-LAST-DEFINE !
            _RTHP-D-PLAN-LAST-DEFINE @ 1 _RTHP-U+?
                0= IF DROP 0 UNLOOP EXIT THEN DROP
        ELSE
            _RTHP-D-P @ _RTHP.NEXT-OBJECT @ U< 0= IF
                0 UNLOOP EXIT
            THEN
        THEN
    LOOP
    _RTHP-D-PLAN-CONTROLS @ _RTHP-D-PLAN-GLYPHS @ OR 0<> ;

: _RTHP-D-CONTROL-REFERENCES-NORMALIZABLE?  ( -- flag )
    _RTHP-D-PENDING @ _RTHP-TB.CONTROL-COUNT @ 0 ?DO
        I _RTHP-D-PENDING @ _RTHP-D-CONTROL-AT DUP
            _RTE-CONTROL.ID @ _RTHP-D-RAW-CONTROL-REFERENCE?
                0= IF DROP 0 UNLOOP EXIT THEN
        _RTE-CONTROL.PARENT @ ?DUP IF
            _RTHP-D-RAW-CONTROL-REFERENCE? 0= IF 0 UNLOOP EXIT THEN
        THEN
        I _RTHP-D-PENDING @ _RTHP-D-CORR-AT
            RUCP-CORRELATION-CONTROL-ID@
            _RTHP-D-RAW-CONTROL-REFERENCE? 0= IF 0 UNLOOP EXIT THEN
    LOOP -1 ;

: _RTHP-D-TARGETS-NORMALIZABLE?  ( -- flag )
    _RTHP-D-PENDING @ _RTHP-TB.COUNT @ 0 ?DO
        I _RTHP-D-PENDING @ _RTHP-TARGET-ENTRY _RTHP-TE.ID @
            _RTHP-D-RAW-CONTROL-REFERENCE? 0= IF 0 UNLOOP EXIT THEN
    LOOP -1 ;

VARIABLE _RTHP-D-CANDIDATE-GLYPHS

: _RTHP-D-EXTEND-TOMBSTONES?  ( -- flag )
    _RTHP-D-PENDING @ _RTHP-TB.GLYPH-SLOT-COUNT @
        _RTHP-D-CANDIDATE-GLYPHS !
    _RTHP-D-ACTIVE @ _RTHP-TB.GLYPH-SLOT-COUNT @
        _RTHP-D-CANDIDATE-GLYPHS @ U> 0= IF -1 EXIT THEN
    _RTHP-D-ACTIVE @ _RTHP-TB.GLYPH-SLOT-COUNT @
    _RTHP-D-CANDIDATE-GLYPHS @ ?DO
        _RTHP-D-P @ _RTHP.GLYPH-ITEMS-A @
            I RTE-GLYPH-RUN-PLAN-ITEM-SIZE * + DUP _RTHP-D-PENDING-I !
            RTE-GLYPH-RUN-PLAN-ITEM-SIZE 0 FILL
        _RTHP-D-PENDING-FIRST @
        _RTHP-D-PENDING @ _RTHP-TB.CONTROL-COUNT @
        _RTHP-D-PENDING @ _RTHP-TB.INSTRUMENT-COUNT @ +
        _RTHP-D-PENDING @ _RTHP-TB.STATIC-COUNT @ + I
            _RTHP-D-GLYPH-EXPECTED? 0= IF
            DROP 0 UNLOOP EXIT
        THEN _RTHP-D-PENDING-I @ _RTE-LPI.OBJECT !
        1 _RTHP-D-PENDING-I @ _RTE-LPI.HEIGHT !
        1 _RTHP-D-PENDING-I @ _RTE-LPI.WIDTH !
        _RTHP-D-PENDING @ _RTHP-TB.ROWS @
            _RTHP-D-PENDING-I @ _RTE-LPI.ROOT-HEIGHT !
        _RTHP-D-PENDING @ _RTHP-TB.COLS @
            _RTHP-D-PENDING-I @ _RTE-LPI.ROOT-WIDTH !
        _RTHP-D-P @ _RTHP.GLYPH-REFS-A @
            I RGRP-TEXT-REF-SIZE * + DUP _RTHP-D-PENDING-R !
            RGRP-TEXT-REF-SIZE 0 FILL
        _RTHP-D-P @ _RTHP.GLYPH-TEXT-USED @
            _RTHP-D-PENDING-R @ _RGRP-T.OFFSET !
    LOOP
    _RTHP-D-ACTIVE @ _RTHP-TB.GLYPH-SLOT-COUNT @ DUP
        _RTHP-D-P @ _RTHP.GLYPH-COUNT !
        _RTHP-D-PENDING @ _RTHP-TB.GLYPH-SLOT-COUNT !
    \ The delayed DELTA route consumes the packed bank, not the scratch plan.
    \ Keep the scratch count equal to that bank so a later BIND can prove it;
    \ fallback restores the preflighted count and plan wrapper.  Admission is
    \ deliberately never altered by this acknowledged-topology extension.
    _RTHP-D-PENDING @ _RTHP-D-P @ _RTHP-PACK-CANDIDATE 0= IF
        _RTHP-D-CANDIDATE-GLYPHS @ DUP
            _RTHP-D-P @ _RTHP.GLYPH-COUNT !
            _RTHP-D-PENDING @ _RTHP-TB.GLYPH-SLOT-COUNT !
        0 EXIT
    THEN
    -1 ;

: _RTHP-D-RESTORE-FRESH-CANDIDATE  ( -- )
    _RTHP-D-P @ _RTHP-R-P !
    _RTHP-D-CANDIDATE-GLYPHS @ DUP
        _RTHP-D-P @ _RTHP.GLYPH-COUNT !
        _RTHP-R-PLAN-SLOTS? DROP
    _RTHP-D-P @ _RTHP-WRAP-HYBRID
    _RTHP-D-P @ _RTHP-TARGET-ABORT ;

VARIABLE _RTHP-D-LAST-ID

: _RTHP-D-RAW>NORMALIZED?  ( raw-control-id -- control-id flag )
    DUP _RTHP-D-PENDING-FIRST @ U< IF DROP 0 0 EXIT THEN
    _RTHP-D-PENDING-FIRST @ - DUP
        _RTHP-D-PENDING @ _RTHP-TB.CONTROL-COUNT @ U< 0= IF
        DROP 0 0 EXIT
    THEN
    _RTHP-D-PENDING @ _RTHP-D-CONTROL-AT _RTE-CONTROL.ID @
        DUP 0<> ;

\ An unchanged body keeps the revision the terminal already holds for it,
\ whatever its state, as RETAINED-1 requires of a state-only replacement.
\ Only the pending bank's own copy of the content changes.
: _RTHP-D-KEEP-CONTENT-REVISION  ( -- )
    _RTHP-D-PENDING-C @ _RTE-CONTROL.KIND @
        _RTHP-CONTENT-CONTROL-KIND? 0= IF EXIT THEN
    _RTHP-D-CONTROL-BODY-EQUAL? 0= IF EXIT THEN
    _RTHP-D-ACTIVE-C @ _RTE-CONTROL.CONTENT-A @ 8 +
    _RTHP-D-PENDING-C @ _RTE-CONTROL.CONTENT-A @ 8 + 8 MOVE ;

VARIABLE _RTHP-D-TARGET-E

\ Move one input target to its control's final ID.  A content target also
\ takes its control's content revision as normalization has just settled
\ it, so positioned and item input names exactly the content the terminal
\ holds.  Other targets keep the revision they were extracted with.
: _RTHP-D-NORMALIZE-TARGET?  ( entry -- flag )
    DUP _RTHP-D-TARGET-E ! _RTHP-TE.ID @
    DUP _RTHP-D-RAW>NORMALIZED? 0= IF 2DROP 0 EXIT THEN
    _RTHP-D-TARGET-E @ _RTHP-TE.ID !
    _RTHP-D-TARGET-E @ _RTHP-TE.KIND @
        _RTHP-CONTENT-CONTROL-KIND? 0= IF DROP -1 EXIT THEN
    _RTHP-D-PENDING-FIRST @ - _RTHP-D-PENDING @ _RTHP-D-CONTROL-AT
    _RTHP-D-PENDING @ _RTHP-D-CONTENT-REVISION? 0= IF DROP 0 EXIT THEN
    _RTHP-D-TARGET-E @ _RTHP-TE.REVISION ! -1 ;

: _RTHP-D-NORMALIZE  ( -- flag )
    \ Stable glyph IDs have already been written into the spatially ordered
    \ inactive bank.  First turn the packed control array into the exact
    \ graph-ordinal-to-final-ID map.  Only after that pass consumes every raw
    \ semantic pair do parent, correlation, and input-target references move
    \ through the immutable ordinal map; no partially rewritten ID is ever
    \ used as lookup authority.
    0 _RTHP-D-LAST-ID !
    _RTHP-D-PENDING @ _RTHP-TB.CONTROL-COUNT @ 0 ?DO
        I _RTHP-D-CONTROL-PAIR 0= IF 0 UNLOOP EXIT THEN
        _RTHP-D-MATCHED @ IF
            _RTHP-D-KEEP-CONTENT-REVISION
            _RTHP-D-ACTIVE-C @ _RTE-CONTROL.ID @
        ELSE
            _RTHP-D-EXPECTED-P @
        THEN
        DUP _RTHP-D-LAST-ID @ U> IF DUP _RTHP-D-LAST-ID ! THEN
        _RTHP-D-PENDING-C @ _RTE-CONTROL.ID !
        _RTHP-D-ACTIVE @ _RTHP-TB.REGION @
            _RTHP-D-PENDING-C @ _RTE-CONTROL.REGION !
    LOOP
    _RTHP-D-PENDING @ _RTHP-TB.CONTROL-COUNT @ 0 ?DO
        I _RTHP-D-PENDING @ _RTHP-D-CONTROL-AT DUP
            _RTHP-D-PENDING-C ! _RTE-CONTROL.PARENT @ ?DUP IF
            _RTHP-D-RAW>NORMALIZED? 0= IF
                DROP 0 UNLOOP EXIT
            THEN _RTHP-D-PENDING-C @ _RTE-CONTROL.PARENT !
        THEN
        I _RTHP-D-PENDING @ _RTHP-D-CORR-AT DUP
            _RTHP-D-PENDING-X ! RUCP-CORRELATION-CONTROL-ID@
            _RTHP-D-RAW>NORMALIZED? 0= IF
                DROP 0 UNLOOP EXIT
            THEN _RTHP-D-PENDING-X @ _RUCP-X.CONTROL-ID !
    LOOP
    _RTHP-D-PENDING @ _RTHP-TB.COUNT @ 0 ?DO
        I _RTHP-D-PENDING @ _RTHP-TARGET-ENTRY
        _RTHP-D-NORMALIZE-TARGET? 0= IF 0 UNLOOP EXIT THEN
    LOOP
    _RTHP-D-ACTIVE @ _RTHP-D-PENDING @ _RTHP-INSTRUMENTS-NORMALIZE
    _RTHP-D-ACTIVE @ _RTHP-D-PENDING @ _RTHP-STATICS-NORMALIZE
    _RTHP-D-ACTIVE @ _RTHP-TB.SERIES-COUNT @ IF
        _RTHP-D-ACTIVE @ _RTHP-TB.FIRST-SERIES @ _RTHP-D-P @ _RTHP.FIRST-SERIES !
    THEN
    _RTHP-D-ACTIVE @ _RTHP-TB.REGION @ DUP
        _RTHP-D-PENDING @ _RTHP-TB.REGION !
        _RTHP-D-P @ _RTHP.REGION !
    _RTHP-D-ACTIVE-FIRST @ DUP
        _RTHP-D-PENDING @ _RTHP-TB.FIRST-OBJECT !
        _RTHP-D-P @ _RTHP.FIRST-OBJECT ! -1 ;

\ Everything the next comparison would derive from this bank as the active
\ one has just been proved: its slots are canonical with PENDING-VISIBLE
\ visible, its object IDs are one permutation of the interval at GLYPH-BASE,
\ and INDEX-B is its identity-sorted control index with unique IDs up to
\ LAST-ID.  Keep them beside the bank.  A bank without kept facts is simply
\ audited in full by the next comparison.
\ A comparison of candidates built for Desk's shell holds no runs: the
\ pending bank has none, the acknowledged bank's are not on screen, and
\ none is planned, kept or restored.
: _RTHP-D-NO-GLYPHS  ( -- )
    0 _RTHP-D-CANDIDATE-GLYPHS ! 0 _RTHP-D-SLOTS ! 0 _RTHP-D-ACTIVE-SLOTS !
    0 _RTHP-D-ACTIVE-VISIBLE ! 0 _RTHP-D-PENDING-VISIBLE !
    0 _RTHP-D-GLYPH-BASE ! 0 _RTHP-D-PLAN-GLYPHS ! ;

: _RTHP-D-KEEP-FACTS  ( -- )
    _RTHP-D-P @ _RTHP.PENDING-FACTS 0 OVER _RTHP-KF.BANK !
    _RTHP-D-INDEX-BYTES @ _RTHP-D-P @ _RTHP.FACTS-INDEX-U @ U> IF
        DROP EXIT
    THEN
    _RTHP-D-PENDING @ _RTHP-D-P @ _RTHP-FACTS-INDEX
        DUP _RTHP-D-INDEX-BYTES @ _RTHP-D-P @ _RTHP-ARENA-SPAN?
        0= IF 2DROP EXIT THEN
    _RTHP-D-INDEX-B @ SWAP _RTHP-D-INDEX-BYTES @ MOVE
    _RTHP-D-GLYPH-BASE @ OVER _RTHP-KF.BASE !
    _RTHP-D-PENDING-VISIBLE @ OVER _RTHP-KF.VISIBLE !
    _RTHP-D-PENDING @ _RTHP-TB.GLYPH-SLOT-COUNT @ OVER _RTHP-KF.SLOTS !
    _RTHP-D-PENDING @ _RTHP-TB.CONTROL-COUNT @ OVER _RTHP-KF.CONTROLS !
    _RTHP-D-LAST-ID @ OVER _RTHP-KF.LAST-ID !
    _RTHP-D-PENDING @ SWAP _RTHP-KF.BANK ! ;

\ A packed status-field text reference is an offset into its bank's copy.
: _RTHP-D-STATIC-SPAN ( field bank -- a u )
    _RTHP-PACK-STATIC-TEXT-A OVER @ + SWAP 8 + @ ;
: _RTHP-D-SPAN<> ( a1 u1 a2 u2 -- flag )
    2 PICK OVER <> IF 2DROP 2DROP -1 EXIT THEN
    DUP 0= IF 2DROP 2DROP 0 EXIT THEN COMPARE 0<> ;
VARIABLE _RTHP-DS-OLD
VARIABLE _RTHP-DS-NEW
CREATE _RTHP-DS-RECORD-S RTE-STATIC-SIZE 7 + ALLOT
: _RTHP-DS-RECORD ( -- record ) _RTHP-DS-RECORD-S 7 + -8 AND ;
\ The static in place INDEX shows something other than it did: a status
\ field's severity, emphasis or text, or a picture's opacity, backdrop or
\ resource, which share those places.
: _RTHP-D-STATIC-CHANGED?  ( index -- flag )
    DUP _RTHP-D-ACTIVE @ _RTHP-PACK-STATICS-A SWAP RTE-STATIC-SIZE * + _RTHP-DS-OLD !
    _RTHP-D-PENDING @ _RTHP-PACK-STATICS-A SWAP RTE-STATIC-SIZE * + _RTHP-DS-NEW !
    _RTHP-DS-OLD @ _RTE-STATIC.SEVERITY @ _RTHP-DS-NEW @ _RTE-STATIC.SEVERITY @ <>
    _RTHP-DS-OLD @ _RTE-STATIC.EMPHASIZED @ _RTHP-DS-NEW @ _RTE-STATIC.EMPHASIZED @ <>
    OR _RTHP-DS-OLD @ _RTE-STATIC.RESOURCE @ _RTHP-DS-NEW @ _RTE-STATIC.RESOURCE @ <>
    OR IF -1 EXIT THEN
    _RTHP-DS-OLD @ _RTE-STATIC.LABEL-A _RTHP-D-ACTIVE @ _RTHP-D-STATIC-SPAN
    _RTHP-DS-NEW @ _RTE-STATIC.LABEL-A _RTHP-D-PENDING @ _RTHP-D-STATIC-SPAN
    _RTHP-D-SPAN<> IF -1 EXIT THEN
    _RTHP-DS-OLD @ _RTE-STATIC.VALUE-A _RTHP-D-ACTIVE @ _RTHP-D-STATIC-SPAN
    _RTHP-DS-NEW @ _RTE-STATIC.VALUE-A _RTHP-D-PENDING @ _RTHP-D-STATIC-SPAN
    _RTHP-D-SPAN<> ;
\ The pending status field in place INDEX with its text references as
\ addresses, as the facade takes them.  An empty text keeps a zero address.
: _RTHP-D-STATIC-REBASE ( field -- )
    DUP 8 + @ IF _RTHP-D-PENDING @ _RTHP-PACK-STATIC-TEXT-A SWAP +!
    ELSE 0 SWAP ! THEN ;
: _RTHP-D-STATIC-RECORD  ( index -- record )
    _RTHP-D-PENDING @ _RTHP-PACK-STATICS-A SWAP RTE-STATIC-SIZE * +
        _RTHP-DS-RECORD RTE-STATIC-SIZE MOVE
    _RTHP-DS-RECORD _RTE-STATIC.LABEL-A _RTHP-D-STATIC-REBASE
    _RTHP-DS-RECORD _RTE-STATIC.VALUE-A _RTHP-D-STATIC-REBASE
    _RTHP-DS-RECORD ;

\ The pending bank's statics that changed, each judged.
: _RTHP-ROOT-STATIC-CHANGES  ( -- count )
    0 _RTHP-D-PENDING @ _RTHP-TB.STATIC-COUNT @ 0 ?DO
        I _RTHP-D-STATIC-CHANGED? IF
            1+
            _RTHP-ROOT-NEW @ IF
                I _RTHP-ROOT-STATIC-ROOT? IF
                    I 65536 + _RTHP-ROOT-JUDGE
                THEN
            THEN
        THEN
    LOOP ;

: _RTHP-DELTA-CANDIDATE?  ( producer -- flag )
    DUP _RTHP-ROOT-BEGIN
    0 _RTHP-D-WHY !
    DUP _RTHP-DELTA-PLAN-CLEAR
    DUP _RTHP.TARGET-ACTIVE @ 0=
    OVER _RTHP.TARGET-PENDING @ 0= OR IF DROP 0 EXIT THEN
    DUP _RTHP-D-BIND? 0= IF DROP 0 EXIT THEN DROP
    20 _RTHP-D-WHY !
    _RTHP-D-PLAN-START? 0= IF 0 EXIT THEN
    21 _RTHP-D-WHY !
    _RTHP-D-CONTROL-REFERENCES-NORMALIZABLE? 0= IF 0 EXIT THEN
    22 _RTHP-D-WHY !
    _RTHP-D-TARGETS-NORMALIZABLE? 0= IF 0 EXIT THEN
    23 _RTHP-D-WHY !
    _RTHP-D-BUILD-CONTROL-MAP? 0= IF 0 EXIT THEN
    0 _RTHP-D-OPS !
    _RTHP-D-PENDING @ _RTHP-TB.CONTROL-COUNT @ 0 ?DO
        24 _RTHP-D-WHY !
        I _RTHP-D-CONTROL-COMPATIBLE? 0= IF 0 UNLOOP EXIT THEN
        _RTHP-D-CHANGED @ IF I _RTHP-ROOT-JUDGE-CONTROL THEN
        _RTHP-D-CHANGED @ _RTHP-D-MATCHED @ AND IF
            25 _RTHP-D-WHY !
            _RTHP-D-CONTROL-MARK-CHANGED?
                0= IF 0 UNLOOP EXIT THEN
        THEN
    LOOP
    _RTHP-ROOT-STATIC-CHANGES _RTHP-D-OPS +!
    _RTHP-D-P @ _RTHP.SHELL-BUILT @ IF
        \ Desk's shell sends the runs of its own regions, and fences a frame
        \ in which nothing changed, from its own banks: the applications'
        \ items are all this comparison matches.
        _RTHP-D-NO-GLYPHS
    ELSE
        26 _RTHP-D-WHY !
        _RTHP-D-BUILD-SLOT-MAP? 0= IF 0 EXIT THEN
        27 _RTHP-D-WHY !
        _RTHP-D-EXTEND-TOMBSTONES? 0= IF 0 EXIT THEN
        28 _RTHP-D-WHY !
        _RTHP-D-TRY-GLYPH-LAYOUT? 0= IF
            _RTHP-D-NORMALIZE-GLYPH-IDS? 0= IF
                _RTHP-D-RESTORE-FRESH-CANDIDATE 0 EXIT
            THEN
            _RTHP-D-SLOTS @ 0 ?DO
                I _RTHP-D-GLYPH-COMPATIBLE-AND-MARK? 0= IF
                    _RTHP-D-RESTORE-FRESH-CANDIDATE 0 UNLOOP EXIT
                THEN
            LOOP
        THEN
        29 _RTHP-D-WHY !
        _RTHP-D-OPS @ 0= IF
            _RTHP-D-PLAN-REVISION-FENCE? 0= IF
                _RTHP-D-RESTORE-FRESH-CANDIDATE 0 EXIT
            THEN
        THEN
        30 _RTHP-D-WHY !
        _RTHP-D-PLAN-COMPACT-GLYPHS 0= IF
            _RTHP-D-RESTORE-FRESH-CANDIDATE 0 EXIT
        THEN
    THEN
    31 _RTHP-D-WHY !
    _RTHP-D-NORMALIZE 0= IF
        _RTHP-D-RESTORE-FRESH-CANDIDATE 0 EXIT
    THEN
    32 _RTHP-D-WHY !
    _RTHP-D-PLAN-COMPACT-CONTROLS? 0= IF
        _RTHP-D-RESTORE-FRESH-CANDIDATE 0 EXIT
    THEN
    _RTHP-D-KEEP-FACTS
    _RTHP-D-PLAN-SEAL -1 ;

\ ---------------------------------------------------------------------
\  Exact unchanged-content shortcut
\ ---------------------------------------------------------------------
\
\  This route is intentionally narrower than ordinary retained DELTA.  RUHA
\  must prove that the current visible semantic aggregate inherited the exact
\  acknowledged content epoch through validated slice reuse, while the screen
\  must prove an admitted non-forced frame with zero CELL damage against the
\  draw carried by that physically acknowledged target.  Only then may the
\  immutable target be cloned into the inactive bank and advanced with the
\  existing one-operation revision fence.  Every ambiguity returns false and
\  leaves TARGET-PENDING and DELTA-PLAN-VALID clear for the full build.

\ One live stage may hand the unchanged probe's exact aggregate observation
\ to its own rebuild.  Only _RTHP-STAGE-LIVE-CANDIDATE consumes it, and it
\ clears the handoff on entry, so an observation never crosses calls.
VARIABLE _RTHP-PROBE-SNAP
VARIABLE _RTHP-PROBE-STATUS
VARIABLE _RTHP-PROBE-DRAW

: _RTHP-PROBE-CLEAR  ( -- )
    0 _RTHP-PROBE-SNAP ! 0 _RTHP-PROBE-STATUS ! 0 _RTHP-PROBE-DRAW ! ;

VARIABLE _RTHP-U-P
VARIABLE _RTHP-U-ACTIVE
VARIABLE _RTHP-U-PENDING
VARIABLE _RTHP-U-SNAP
VARIABLE _RTHP-U-STATUS
VARIABLE _RTHP-U-DRAW
VARIABLE _RTHP-U-SOURCE-GEN
VARIABLE _RTHP-U-CONTENT-EPOCH
VARIABLE _RTHP-U-DOCUMENTS
VARIABLE _RTHP-U-ATTEMPT
VARIABLE _RTHP-U-BANK-U
VARIABLE _RTHP-U-PREFIX
VARIABLE _RTHP-U-COPY-U
VARIABLE _RTHP-U-OLD-CONTROL
VARIABLE _RTHP-U-NEW-CONTROL
VARIABLE _RTHP-U-TEXT-A
VARIABLE _RTHP-U-TEXT-U
VARIABLE _RTHP-U-TEXT-O

VARIABLE _RTHP-U-COLS
VARIABLE _RTHP-U-ROWS
VARIABLE _RTHP-U-FRONT-DRAW
VARIABLE _RTHP-U-PLANE-DRAW
VARIABLE _RTHP-U-FORCE
VARIABLE _RTHP-U-DAMAGE-A
VARIABLE _RTHP-U-DAMAGE-U
VARIABLE _RTHP-U-ROW
VARIABLE _RTHP-U-RESULT

: _RTHP-U-FINISH  ( flag -- flag )
    _RTHP-U-RESULT !
    _RTHP-U-RESULT @ 0= IF
        _RTHP-U-PENDING @ ?DUP IF 0 SWAP _RTHP-TB.VALID ! THEN
    THEN
    0 _RTHP-U-P ! 0 _RTHP-U-ACTIVE ! 0 _RTHP-U-PENDING !
    0 _RTHP-U-SNAP ! 0 _RTHP-U-STATUS ! 0 _RTHP-U-DRAW !
    0 _RTHP-U-SOURCE-GEN ! 0 _RTHP-U-CONTENT-EPOCH !
    0 _RTHP-U-DOCUMENTS ! 0 _RTHP-U-ATTEMPT !
    0 _RTHP-U-BANK-U ! 0 _RTHP-U-PREFIX ! 0 _RTHP-U-COPY-U !
    0 _RTHP-U-OLD-CONTROL ! 0 _RTHP-U-NEW-CONTROL !
    0 _RTHP-U-TEXT-A ! 0 _RTHP-U-TEXT-U ! 0 _RTHP-U-TEXT-O !
    _RTHP-U-RESULT @ ;

: _RTHP-U-ACTIVE?  ( -- flag )
    _RTHP-U-P @ _RTHP.PHASE @ _RTHP-PH-LIVE <> IF 0 EXIT THEN
    _RTHP-U-P @ _RTHP.TARGET-PENDING @ IF 0 EXIT THEN
    _RTHP-U-P @ _RTHP.TARGET-ACTIVE @ DUP 0= IF DROP 0 EXIT THEN
        _RTHP-U-ACTIVE !
    _RTHP-U-ACTIVE @ _RTHP-U-P @ _RTHP-TARGET-BANK-HEADER?
        0= IF 0 EXIT THEN
    _RTHP-TARGET-BANK-ENTRIES? 0= IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.OWNER @
        _RTHP-U-P @ _RTHP.OWNER @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.GENERATION @
        _RTHP-U-P @ _RTHP.OWNER-GEN @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.COLS @
        _RTHP-U-P @ _RTHP.COLS @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.ROWS @
        _RTHP-U-P @ _RTHP.ROWS @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.PHYSICAL-GEN @
        _RTHP-U-P @ _RTHP.PHYSICAL-GEN @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.REGION @
        _RTHP-U-P @ _RTHP.REGION @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.FIRST-OBJECT @
        _RTHP-U-P @ _RTHP.FIRST-OBJECT @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.CONTROL-COUNT @
        _RTHP-U-P @ _RTHP.CONTROL-COUNT @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.MENU-CONTROL-COUNT @
        _RTHP-U-P @ _RTHP.MENU-CONTROL-COUNT @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.DOCUMENT-COUNT @
        _RTHP-U-P @ _RTHP.DOCUMENT-COUNT @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.COLLECTION-COUNT @
        _RTHP-U-P @ _RTHP.COLLECTION-COUNT @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.COLLECTION-ITEMS @
        _RTHP-U-P @ _RTHP.COLLECTION-ITEMS @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.COLLECTION-UTF8 @
        _RTHP-U-P @ _RTHP.COLLECTION-UTF8 @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.MENU-TEXT-USED @
        _RTHP-U-P @ _RTHP.SOURCE-MENU-TEXT-USED @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.SERIES-COUNT @
        _RTHP-U-P @ _RTHP.SERIES-COUNT @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.SERIES-SAMPLE-BYTES @
        _RTHP-U-P @ _RTHP.SERIES-SAMPLES-USED @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.SERIES-SLOTS @
        _RTHP-U-P @ _RTHP.SERIES-SLOTS @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.SERIES-CHUNKS @
        _RTHP-U-P @ _RTHP.SERIES-CHUNKS @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.SERIES-HISTORY-MAX @
        _RTHP-U-P @ _RTHP.SERIES-HISTORY-MAX @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.SERIES-CHUNK-MAX @
        _RTHP-U-P @ _RTHP.SERIES-CHUNK-MAX @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.SERIES-CHUNK-BYTES-MAX @
        _RTHP-U-P @ _RTHP.SERIES-CHUNK-BYTES-MAX @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.WAVEFORM-COUNT @
        _RTHP-U-P @ _RTHP.WAVEFORM-COUNT @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.SERIES-COUNT @ IF
        _RTHP-U-ACTIVE @ _RTHP-TB.FIRST-SERIES @ _RTHP-U-P @ _RTHP.FIRST-SERIES @ <> IF 0 EXIT THEN
    THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.INSTRUMENT-REGION-COUNT @
        _RTHP-U-P @ _RTHP.INSTRUMENT-REGION-COUNT @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.INSTRUMENT-COUNT @
        _RTHP-U-P @ _RTHP.INSTRUMENT-COUNT @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.INSTRUMENT-UNIT-BYTES @
        _RTHP-U-P @ _RTHP.INSTRUMENT-UNITS-USED @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.FIELD-COUNT @
        _RTHP-U-P @ _RTHP.FIELD-COUNT @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.FIELD-ITEMS @
        _RTHP-U-P @ _RTHP.FIELD-ITEMS @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.FIELD-UTF8 @
        _RTHP-U-P @ _RTHP.FIELD-UTF8 @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.DIALOG-CONTROLS @
        _RTHP-U-P @ _RTHP.DIALOG-CONTROLS @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.DIALOG-COUNT @
        _RTHP-U-P @ _RTHP.DIALOG-COUNT @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.DIALOG-UTF8 @
        _RTHP-U-P @ _RTHP.DIALOG-UTF8 @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.STATIC-COUNT @
        _RTHP-U-P @ _RTHP.STATIC-COUNT @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.STATIC-TEXT-BYTES @
        _RTHP-U-P @ _RTHP.STATIC-TEXT-USED @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.GLYPH-SLOT-COUNT @
        _RTHP-U-P @ _RTHP.GLYPH-COUNT @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.SOURCE-TEXT-USED @
        _RTHP-U-P @ _RTHP.SOURCE-TEXT-USED @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.GLYPH-TEXT-USED @
        _RTHP-U-P @ _RTHP.GLYPH-TEXT-USED @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.DRAW @ DUP 0= IF DROP 0 EXIT THEN
        DUP _RTHP-U-P @ _RTHP.ACTIVE-DRAW @ <>
        OVER _RTHP-U-P @ _RTHP.SOURCE-DRAW @ <> OR
        SWAP _RTHP-U-P @ _RTHP.SURFACE-GEN @ <> OR IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.SOURCE-GEN @ DUP 0= IF DROP 0 EXIT THEN
        _RTHP-U-P @ _RTHP.SOURCE-GEN @ <> IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.CONTENT-EPOCH @ DUP 0= IF
        DROP 0 EXIT
    THEN _RTHP-U-P @ _RTHP.SOURCE-CONTENT-EPOCH @ <> IF 0 EXIT THEN

    \ Query into non-authoritative inline scratch.  A changed or malformed
    \ limit record merely rejects this shortcut; the acknowledged bank stays
    \ active and the ordinary rebuild will refresh all candidate scratch.
    _RTHP-U-P @ _RTHP.ADMISSION
    _RTHP-U-P @ _RTHP.FACADE @ RTE-LIMITS@
    DUP RTE-S-OK <> IF DROP 0 EXIT THEN DROP
    _RTHP-U-P @ _RTHP.ADMISSION RTE-LIMITS-SIZE
    _RTHP-U-P @ _RTHP.LIMITS RTE-LIMITS-SIZE COMPARE IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.GLYPH-RUN-LIMIT @
    _RTHP-U-P @ _RTHP.ADMISSION RTE-LIMITS-GLYPH-RUN-BYTES@ = ;

: _RTHP-U-SNAPSHOT?  ( -- flag )
    SCR-DRAW-GENERATION@ DUP 0= IF DROP 0 EXIT THEN
    DUP _RTHP-U-P @ _RTHP.ACTIVE-DRAW @ = IF DROP 0 EXIT THEN
        _RTHP-U-DRAW !
    _RTPROF-PH-UIDL-AGGREGATE _RTPROF-MARK
    _RTHP-U-DRAW @ _RTHP-U-P @ _RTHP.ADAPTER @ RUHA-SNAPSHOT-FOR@
    _RTPROF-PH-OTHER _RTPROF-MARK
    2DUP _RTHP-PROBE-STATUS ! _RTHP-PROBE-SNAP !
    _RTHP-U-DRAW @ _RTHP-PROBE-DRAW !
    _RTHP-U-STATUS ! _RTHP-U-SNAP !
    _RTHP-U-STATUS @ RUHA-S-OK <> IF 0 EXIT THEN
    _RTHP-U-SNAP @ RUHA-SNAPSHOT-DRAW-GENERATION@
        _RTHP-U-DRAW @ <> IF 0 EXIT THEN
    _RTHP-U-SNAP @ RUHA-SNAPSHOT-GENERATION@ DUP 0= IF DROP 0 EXIT THEN
        DUP _RTHP-U-ACTIVE @ _RTHP-TB.SOURCE-GEN @ = IF DROP 0 EXIT THEN
        _RTHP-U-SOURCE-GEN !
    _RTHP-U-SNAP @ RUHA-SNAPSHOT-CONTENT-EPOCH@ DUP 0= IF
        DROP 0 EXIT
    THEN DUP _RTHP-U-ACTIVE @ _RTHP-TB.CONTENT-EPOCH @ <> IF
        DROP 0 EXIT
    THEN _RTHP-U-CONTENT-EPOCH !
    _RTHP-U-SNAP @ RUHA-SNAPSHOT-DOCUMENT-COUNT@ DUP 0= IF
        DROP 0 EXIT
    THEN DUP _RTHP-U-P @ _RTHP.DOCUMENT-COUNT @ <> IF
        DROP 0 EXIT
    THEN _RTHP-U-DOCUMENTS !
    _RTHP-U-P @ _RTHP.ATTEMPT @ 1 _RTHP-U32+?
        0= IF DROP 0 EXIT THEN DUP 0= IF DROP 0 EXIT THEN
        _RTHP-U-ATTEMPT !
    -1 ;

: _RTHP-U-TEXT-REBASE?  ( active-address bytes -- pending-address flag )
    _RTHP-U-TEXT-U ! _RTHP-U-TEXT-A !
    _RTHP-U-TEXT-U @ 0= IF
        _RTHP-U-TEXT-A @ 0= IF 0 -1 ELSE 0 0 THEN EXIT
    THEN
    _RTHP-U-TEXT-A @ _RTHP-U-TEXT-U @
        MSPAN-NONWRAPPING? 0= IF 0 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-D-SOURCE-A DUP
        _RTHP-U-TEXT-A @ U> IF DROP 0 0 EXIT THEN
    _RTHP-U-TEXT-A @ SWAP - _RTHP-U-TEXT-O !
    _RTHP-U-TEXT-O @ _RTHP-U-TEXT-U @ _RTHP-U+?
        0= IF DROP 0 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.SOURCE-TEXT-USED @ U> IF 0 0 EXIT THEN
    _RTHP-U-PENDING @ _RTHP-D-SOURCE-A _RTHP-U-TEXT-O @ _RTHP-U+?
        0= IF DROP 0 0 EXIT THEN
    DUP _RTHP-U-TEXT-U @ MSPAN-NONWRAPPING? 0= IF DROP 0 0 EXIT THEN
    -1 ;

: _RTHP-U-REBASE-CONTROLS?  ( -- flag )
    _RTHP-U-ACTIVE @ _RTHP-TB.CONTROL-COUNT @ 0 ?DO
        I _RTHP-U-ACTIVE @ _RTHP-D-CONTROL-AT
            _RTHP-U-OLD-CONTROL !
        I _RTHP-U-PENDING @ _RTHP-D-CONTROL-AT
            _RTHP-U-NEW-CONTROL !
        _RTHP-U-OLD-CONTROL @ _RTE-CONTROL.LABEL-A @
        _RTHP-U-OLD-CONTROL @ _RTE-CONTROL.LABEL-U @
            _RTHP-U-TEXT-REBASE? 0= IF DROP 0 UNLOOP EXIT THEN
            _RTHP-U-NEW-CONTROL @ _RTE-CONTROL.LABEL-A !
        _RTHP-U-OLD-CONTROL @ _RTE-CONTROL.SHORTCUT-A @
        _RTHP-U-OLD-CONTROL @ _RTE-CONTROL.SHORTCUT-U @
            _RTHP-U-TEXT-REBASE? 0= IF DROP 0 UNLOOP EXIT THEN
            _RTHP-U-NEW-CONTROL @ _RTE-CONTROL.SHORTCUT-A !
        _RTHP-U-OLD-CONTROL @ _RTE-CONTROL.CONTENT-A @
        _RTHP-U-OLD-CONTROL @ _RTE-CONTROL.CONTENT-U @
            _RTHP-U-TEXT-REBASE? 0= IF DROP 0 UNLOOP EXIT THEN
            _RTHP-U-NEW-CONTROL @ _RTE-CONTROL.CONTENT-A !
    LOOP
    -1 ;

: _RTHP-U-CLONE?  ( -- flag )
    _RTHP-U-P @ _RTHP-TARGET-BANK-BYTES?
        0= IF DROP 0 EXIT THEN _RTHP-U-BANK-U !
    _RTHP-U-ACTIVE @ _RTHP-TB.COUNT @ _RTHP-TARGET-ENTRY-SIZE
        _RTHP-U32*? 0= IF DROP 0 EXIT THEN
    _RTHP-TARGET-BANK-HEADER-SIZE _RTHP-U32+?
        0= IF DROP 0 EXIT THEN DUP _RTHP-U-PREFIX !
    _RTHP-U-ACTIVE @ _RTHP-TB.PACKED-BYTES @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN DUP _RTHP-U-COPY-U !
    _RTHP-U-BANK-U @ U> IF 0 EXIT THEN
    _RTHP-U-P @ _RTHP-TARGET-INACTIVE DUP
        _RTHP-U-PENDING ! _RTHP-U-ACTIVE @ = IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-U-COPY-U @ _RTHP-U-P @
        _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    _RTHP-U-PENDING @ _RTHP-U-BANK-U @ _RTHP-U-P @
        _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-U-BANK-U @
    _RTHP-U-PENDING @ _RTHP-U-BANK-U @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-U-PENDING @ _RTHP-U-COPY-U @ MOVE
    0 _RTHP-U-PENDING @ _RTHP-TB.VALID !
    _RTHP-U-DRAW @ _RTHP-U-PENDING @ _RTHP-TB.DRAW !
    _RTHP-U-SOURCE-GEN @ _RTHP-U-PENDING @ _RTHP-TB.SOURCE-GEN !
    _RTHP-U-CONTENT-EPOCH @
        _RTHP-U-PENDING @ _RTHP-TB.CONTENT-EPOCH !
    _RTHP-U-REBASE-CONTROLS? ;

: _RTHP-U-FENCE-PLAN?  ( -- flag )
    _RTHP-U-P @ _RTHP-D-P !
    _RTHP-U-ACTIVE @ _RTHP-D-ACTIVE !
    _RTHP-U-PENDING @ _RTHP-D-PENDING !
    _RTHP-U-ACTIVE @ _RTHP-TB.FIRST-OBJECT @
        _RTHP-D-ACTIVE-FIRST !
    _RTHP-U-PENDING @ _RTHP-TB.FIRST-OBJECT @
        _RTHP-D-PENDING-FIRST !
    _RTHP-D-PLAN-START? 0= IF 0 EXIT THEN
    \ The exact acknowledged bank has already passed complete target and
    \ engine validation, and the pending bank is its byte-identical clone.
    \ Select one idempotent replacement directly rather than rebuilding the
    \ full inverse glyph map merely to rediscover a revision carrier.
    _RTHP-U-PENDING @ _RTHP-TB.CONTROL-COUNT @ IF
        0 _RTHP-U-P @ _RTHP.ORDER2-A @ !
        1 _RTHP-D-PLAN-CONTROLS ! -1 EXIT
    THEN
    _RTHP-U-PENDING @ _RTHP-TB.GLYPH-SLOT-COUNT @ 0= IF 0 EXIT THEN
    _RTHP-U-P @ _RTHP.GLYPH-ID-MAP-A @ DUP 0= SWAP 7 AND OR IF
        0 EXIT
    THEN
    _RTHP-U-P @ _RTHP.GLYPH-ID-MAP-U @ 8 U< IF 0 EXIT THEN
    _RTHP-U-P @ _RTHP.GLYPH-ID-MAP-A @ 8 _RTHP-U-P @
        _RTHP-ARENA-SPAN? 0= IF 0 EXIT THEN
    0 _RTHP-U-P @ _RTHP.GLYPH-ID-MAP-A @ !
    1 _RTHP-D-PLAN-GLYPHS ! -1 ;

\ The probe's aggregate payload is no longer read here; its identity must
\ still be RUHA's current, open borrow for this exact draw.
: _RTHP-U-SNAPSHOT-CURRENT?  ( -- flag )
    _RTHP-U-DRAW @ _RTHP-U-P @ _RTHP.ADAPTER @ RUHA-SNAPSHOT-IDENTITY@
    RUHA-S-OK <> IF 2DROP DROP 0 EXIT THEN
    _RTHP-U-DOCUMENTS @ =
    SWAP _RTHP-U-CONTENT-EPOCH @ = AND
    SWAP _RTHP-U-SOURCE-GEN @ = AND ;

: _RTHP-U-COMMIT  ( -- )
    _RTHP-U-ACTIVE @ _RTHP-TB.REGION @
        _RTHP-U-P @ _RTHP.REGION !
    _RTHP-U-ACTIVE @ _RTHP-TB.FIRST-OBJECT @
        _RTHP-U-P @ _RTHP.FIRST-OBJECT !
    _RTHP-U-ACTIVE @ _RTHP-TB.CONTROL-COUNT @
        _RTHP-U-P @ _RTHP.CONTROL-COUNT !
    _RTHP-U-ACTIVE @ _RTHP-TB.MENU-CONTROL-COUNT @
        _RTHP-U-P @ _RTHP.MENU-CONTROL-COUNT !
    _RTHP-U-ACTIVE @ _RTHP-TB.COLLECTION-COUNT @
        _RTHP-U-P @ _RTHP.COLLECTION-COUNT !
    _RTHP-U-ACTIVE @ _RTHP-TB.COLLECTION-ITEMS @
        _RTHP-U-P @ _RTHP.COLLECTION-ITEMS !
    _RTHP-U-ACTIVE @ _RTHP-TB.COLLECTION-UTF8 @
        _RTHP-U-P @ _RTHP.COLLECTION-UTF8 !
    _RTHP-U-ACTIVE @ _RTHP-TB.MENU-TEXT-USED @
        _RTHP-U-P @ _RTHP.SOURCE-MENU-TEXT-USED !
    _RTHP-U-ACTIVE @ _RTHP-TB.INSTRUMENT-REGION-COUNT @
        _RTHP-U-P @ _RTHP.INSTRUMENT-REGION-COUNT !
    _RTHP-U-ACTIVE @ _RTHP-TB.INSTRUMENT-COUNT @
        _RTHP-U-P @ _RTHP.INSTRUMENT-COUNT !
    _RTHP-U-ACTIVE @ _RTHP-TB.INSTRUMENT-UNIT-BYTES @
        _RTHP-U-P @ _RTHP.INSTRUMENT-UNITS-USED !
    _RTHP-U-ACTIVE @ _RTHP-TB.FIELD-COUNT @
        _RTHP-U-P @ _RTHP.FIELD-COUNT !
    _RTHP-U-ACTIVE @ _RTHP-TB.FIELD-ITEMS @
        _RTHP-U-P @ _RTHP.FIELD-ITEMS !
    _RTHP-U-ACTIVE @ _RTHP-TB.FIELD-UTF8 @
        _RTHP-U-P @ _RTHP.FIELD-UTF8 !
    _RTHP-U-ACTIVE @ _RTHP-TB.DIALOG-CONTROLS @
        _RTHP-U-P @ _RTHP.DIALOG-CONTROLS !
    _RTHP-U-ACTIVE @ _RTHP-TB.DIALOG-COUNT @
        _RTHP-U-P @ _RTHP.DIALOG-COUNT !
    _RTHP-U-ACTIVE @ _RTHP-TB.DIALOG-UTF8 @
        _RTHP-U-P @ _RTHP.DIALOG-UTF8 !
    _RTHP-U-ACTIVE @ _RTHP-TB.SERIES-COUNT @ _RTHP-U-P @ _RTHP.SERIES-COUNT !
    _RTHP-U-ACTIVE @ _RTHP-TB.SERIES-SAMPLE-BYTES @ _RTHP-U-P @ _RTHP.SERIES-SAMPLES-USED !
    _RTHP-U-ACTIVE @ _RTHP-TB.SERIES-SLOTS @ _RTHP-U-P @ _RTHP.SERIES-SLOTS !
    _RTHP-U-ACTIVE @ _RTHP-TB.SERIES-CHUNKS @ _RTHP-U-P @ _RTHP.SERIES-CHUNKS !
    _RTHP-U-ACTIVE @ _RTHP-TB.SERIES-HISTORY-MAX @ _RTHP-U-P @ _RTHP.SERIES-HISTORY-MAX !
    _RTHP-U-ACTIVE @ _RTHP-TB.SERIES-CHUNK-MAX @ _RTHP-U-P @ _RTHP.SERIES-CHUNK-MAX !
    _RTHP-U-ACTIVE @ _RTHP-TB.SERIES-CHUNK-BYTES-MAX @ _RTHP-U-P @ _RTHP.SERIES-CHUNK-BYTES-MAX !
    _RTHP-U-ACTIVE @ _RTHP-TB.WAVEFORM-COUNT @ _RTHP-U-P @ _RTHP.WAVEFORM-COUNT !
    _RTHP-U-ACTIVE @ _RTHP-TB.SERIES-COUNT @ IF
        _RTHP-U-ACTIVE @ _RTHP-TB.FIRST-SERIES @ DUP _RTHP-U-P @ _RTHP.FIRST-SERIES !
        _RTHP-U-ACTIVE @ _RTHP-TB.SERIES-COUNT @ + 1- _RTHP-U-P @ _RTHP.SERIES-LAST !
    ELSE 0 _RTHP-U-P @ _RTHP.SERIES-LAST ! THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.STATIC-COUNT @ _RTHP-U-P @ _RTHP.STATIC-COUNT !
    _RTHP-U-ACTIVE @ _RTHP-TB.STATIC-TEXT-BYTES @ _RTHP-U-P @ _RTHP.STATIC-TEXT-USED !
    _RTHP-U-ACTIVE @ _RTHP-TB.GLYPH-SLOT-COUNT @
        _RTHP-U-P @ _RTHP.GLYPH-COUNT !
    _RTHP-U-ACTIVE @ _RTHP-TB.SOURCE-TEXT-USED @
        _RTHP-U-P @ _RTHP.SOURCE-TEXT-USED !
    _RTHP-U-ACTIVE @ _RTHP-TB.GLYPH-TEXT-USED @
        _RTHP-U-P @ _RTHP.GLYPH-TEXT-USED !
    _RTHP-U-SOURCE-GEN @ _RTHP-U-P @ _RTHP.SOURCE-GEN !
    _RTHP-U-CONTENT-EPOCH @
        _RTHP-U-P @ _RTHP.SOURCE-CONTENT-EPOCH !
    _RTHP-U-DRAW @ DUP _RTHP-U-P @ _RTHP.SOURCE-DRAW !
        _RTHP-U-P @ _RTHP.SURFACE-GEN !
    _RTHP-U-DOCUMENTS @ _RTHP-U-P @ _RTHP.DOCUMENT-COUNT !
    _RTHP-U-ATTEMPT @ DUP _RTHP-U-P @ _RTHP.ATTEMPT !
        _RTHP-U-P @ _RTHP.HYBRID _RTE-HP.ATTEMPT !
    _RTHP-U-SOURCE-GEN @
        _RTHP-U-P @ _RTHP.HYBRID _RTE-HP.SOURCE-GENERATION !
    _RTHP-U-DRAW @
        _RTHP-U-P @ _RTHP.HYBRID _RTE-HP.SURFACE-GENERATION !
    _RTHP-TARGET-VALID-MAGIC _RTHP-U-PENDING @ _RTHP-TB.VALID !
    _RTHP-U-PENDING @ _RTHP-U-P @ _RTHP.TARGET-PENDING !
    \ PLAN-SEAL publishes DELTA-PLAN-VALID last.  No fallible operation
    \ follows these authoritative candidate stores.
    _RTHP-D-PLAN-SEAL ;

: _RTHP-U-ZERO-DAMAGE?  ( -- flag )
    _RTHP-U-DAMAGE-A @ 0= IF 0 EXIT THEN
    _RTHP-U-DAMAGE-U @ _RTHP-U-ROWS @ <> IF 0 EXIT THEN
    _RTHP-U-DAMAGE-A @ _RTHP-U-DAMAGE-U @
        MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    0 _RTHP-U-ROW !
    BEGIN _RTHP-U-ROW @ _RTHP-U-ROWS @ U< WHILE
        _RTHP-U-DAMAGE-A @ _RTHP-U-ROW @ + C@ IF 0 EXIT THEN
        1 _RTHP-U-ROW +!
    REPEAT
    -1 ;

: _RTHP-U-PLANE-BODY?  ( -- flag )
    SCR-PROJECTION-DIRTY? IF 0 EXIT THEN
    _RTHP-U-FORCE @ IF 0 EXIT THEN
    _RTHP-U-COLS @ _RTHP-U-P @ _RTHP.COLS @ <>
    _RTHP-U-ROWS @ _RTHP-U-P @ _RTHP.ROWS @ <> OR IF 0 EXIT THEN
    _RTHP-U-FRONT-DRAW @
        _RTHP-U-ACTIVE @ _RTHP-TB.DRAW @ <>
    _RTHP-U-FRONT-DRAW @
        _RTHP-U-P @ _RTHP.ACTIVE-DRAW @ <> OR IF 0 EXIT THEN
    _RTHP-U-PLANE-DRAW @ _RTHP-U-DRAW @ <> IF 0 EXIT THEN
    _RTHP-U-ZERO-DAMAGE? 0= IF 0 EXIT THEN
    \ Recheck the aggregate's identity while the exact screen frame is still
    \ immutable, then publish only the inactive target and sealed plan.
    _RTHP-U-SNAPSHOT-CURRENT? 0= IF 0 EXIT THEN
    _RTHP-U-COMMIT -1 ;

: _RTHP-U-CLEAR-PLANE-BORROW  ( flag -- flag )
    0 _RTHP-U-DAMAGE-A ! 0 _RTHP-U-DAMAGE-U !
    0 _RTHP-U-COLS ! 0 _RTHP-U-ROWS !
    0 _RTHP-U-FRONT-DRAW ! 0 _RTHP-U-PLANE-DRAW !
    0 _RTHP-U-FORCE ! 0 _RTHP-U-ROW ! ;

: _RTHP-U-IN-PLANES
  ( front-a back-a cols rows front-draw draw force? damage-a damage-u -- flag )
    _RTHP-U-DAMAGE-U ! _RTHP-U-DAMAGE-A ! _RTHP-U-FORCE !
    _RTHP-U-PLANE-DRAW ! _RTHP-U-FRONT-DRAW !
    _RTHP-U-ROWS ! _RTHP-U-COLS ! 2DROP
    _RTHP-U-PLANE-BODY? _RTHP-U-CLEAR-PLANE-BORROW ;

: _RTHP-U-SCREEN-CALL  ( -- flag )
    ['] _RTHP-U-IN-PLANES SCR-WITH-FRAME-PLANES ;

: _RTHP-U-SCREEN?  ( -- flag )
    ['] _RTHP-U-SCREEN-CALL CATCH DUP IF
        DROP 0 _RTHP-U-CLEAR-PLANE-BORROW EXIT
    THEN DROP ;

\ Pictures sit outside the semantic aggregate, so a draw that shows any,
\ or a frame that shows any or was built before the pixel size or a held
\ picture changed, takes the full build.
: _RTHP-U-PICTURES-QUIET?  ( -- flag )
    _RTHP-U-P @ _RTHP.PICTURE-COUNT @ IF 0 EXIT THEN
    _RTHP-U-P @ _RTHP-PICTURES-CURRENT? 0= IF 0 EXIT THEN
    _RTHP-U-ACTIVE @ _RTHP-TB.STATIC-COUNT @ 0 ?DO
        _RTHP-U-ACTIVE @ _RTHP-PACK-STATICS-A I RTE-STATIC-SIZE * +
            _RTE-STATIC.KIND @ RTE-STATIC-IMAGE = IF 0 UNLOOP EXIT THEN
    LOOP -1 ;

: _RTHP-UNCHANGED-CANDIDATE?  ( producer -- flag )
    _RTHP-U-P !
    _RTHP-U-ACTIVE? 0= IF 0 _RTHP-U-FINISH EXIT THEN
    _RTHP-U-PICTURES-QUIET? 0= IF 0 _RTHP-U-FINISH EXIT THEN
    _RTHP-U-SNAPSHOT? 0= IF 0 _RTHP-U-FINISH EXIT THEN
    _RTHP-U-CLONE? 0= IF 0 _RTHP-U-FINISH EXIT THEN
    _RTHP-U-FENCE-PLAN? 0= IF 0 _RTHP-U-FINISH EXIT THEN
    _RTHP-U-SCREEN? _RTHP-U-FINISH ;

VARIABLE _RTHP-D-RUN-ITEM
VARIABLE _RTHP-D-RUN-REF
VARIABLE _RTHP-D-RUN-TEXT
VARIABLE _RTHP-D-RUN-TOTAL
VARIABLE _RTHP-D-RUN-P

: _RTHP-D-RUN!  ( item ref text-base text-total producer -- flag )
    _RTHP-D-RUN-P ! _RTHP-D-RUN-TOTAL ! _RTHP-D-RUN-TEXT !
    _RTHP-D-RUN-REF ! _RTHP-D-RUN-ITEM !
    _RTHP-D-RUN-REF @ RGRP-TEXT-REF-OFFSET@ _RTHP-D-OFFSET-P !
    _RTHP-D-RUN-REF @ RGRP-TEXT-REF-LENGTH@ _RTHP-D-EXPECTED-P !
    _RTHP-D-OFFSET-P @ _RTHP-D-RUN-TOTAL @ U> IF 0 EXIT THEN
    _RTHP-D-EXPECTED-P @
        _RTHP-D-RUN-TOTAL @ _RTHP-D-OFFSET-P @ - U> IF 0 EXIT THEN
    _RTHP-D-RUN-ITEM @ _RTE-LPI.TEXT-CAPACITY @
        _RTHP-D-EXPECTED-P @ <> IF 0 EXIT THEN
    _RTHP-D-RUN-P @ _RTHP.RUN DUP RTE-GLYPH-RUN-SIZE 0 FILL
    _RTHP-D-RUN-P @ _RTHP.OWNER @ OVER _RTE-GLYPH-RUN.OWNER !
    _RTHP-D-RUN-P @ _RTHP.OWNER-GEN @ OVER _RTE-GLYPH-RUN.GENERATION !
    _RTHP-D-RUN-ITEM @ _RTE-LPI.OBJECT @ OVER _RTE-GLYPH-RUN.OBJECT !
    _RTHP-D-RUN-P @ _RTHP.REGION @ OVER _RTE-GLYPH-RUN.REGION !
    _RTHP-D-RUN-ITEM @ 8 + OVER 32 + 96 MOVE
    _RTHP-D-EXPECTED-P @ IF
        _RTHP-D-RUN-TEXT @ _RTHP-D-OFFSET-P @ +
            OVER _RTE-GLYPH-RUN.TEXT-A !
    ELSE
        0 OVER _RTE-GLYPH-RUN.TEXT-A !
    THEN
    _RTHP-D-EXPECTED-P @ SWAP _RTE-GLYPH-RUN.TEXT-U !
    -1 ;

: _RTHP-EMIT-DELTA  ( producer -- rte-status )
    _RTHP-D-PLAN-BIND? 0= IF RTE-S-INVALID EXIT THEN
    \ A delayed READY_DELTA retry reaches this point only after CAPTURE-SLOT
    \ and retained BEGIN admit the exact attempt-bound candidate.  Keep the
    \ plan until target abort or physical publication so a refused abandon can
    \ safely retry after the engine slot becomes cancellable.
    0 _RTHP-D-EMITTED !
    _RTHP-D-PLAN-CONTROLS @ 0 ?DO
        I _RTHP-D-PLAN-CONTROL-AT _RTHP-D-PLAN-DEFINE ! DUP
            _RTHP-D-PENDING @ _RTHP-TB.CONTROL-COUNT @ U< 0= IF
            DROP RTE-S-INVALID UNLOOP EXIT
        THEN
        _RTHP-D-PENDING @ _RTHP-D-CONTROL-AT _RTHP-D-PENDING-C !
        _RTHP-D-PENDING-C @ _RTHP-D-P @ _RTHP.FACADE @
        _RTHP-D-PLAN-DEFINE @ IF
            RTE-CONTROL-DEFINE
        ELSE
            RTE-CONTROL-REPLACE
        THEN DUP RTE-S-OK <> IF
            UNLOOP EXIT
        THEN DROP 1 _RTHP-D-EMITTED +!
    LOOP
    _RTHP-D-PLAN-GLYPHS @ 0 ?DO
        I _RTHP-D-PLAN-GLYPH-AT _RTHP-D-PLAN-DEFINE ! DUP
            _RTHP-D-PENDING @ _RTHP-TB.GLYPH-SLOT-COUNT @ U< 0= IF
            DROP RTE-S-INVALID UNLOOP EXIT
        THEN
        DUP _RTHP-D-PENDING @ _RTHP-D-ITEM-AT _RTHP-D-PENDING-I !
        _RTHP-D-PENDING @ _RTHP-D-REF-AT _RTHP-D-PENDING-R !
        _RTHP-D-PENDING-I @ _RTHP-D-PENDING-R @
        _RTHP-D-PENDING @ _RTHP-D-GLYPH-A
        _RTHP-D-PENDING @ _RTHP-TB.GLYPH-TEXT-USED @ _RTHP-D-P @
            _RTHP-D-RUN! 0= IF RTE-S-INVALID UNLOOP EXIT THEN
        _RTHP-D-P @ _RTHP.RUN _RTHP-D-P @ _RTHP.FACADE @
        _RTHP-D-PLAN-DEFINE @ IF
            RTE-GLYPH-RUN-DEFINE
        ELSE
            RTE-GLYPH-RUN-REPLACE
        THEN DUP RTE-S-OK <> IF
            UNLOOP EXIT
        THEN DROP 1 _RTHP-D-EMITTED +!
    LOOP
    _RTHP-D-EMITTED @
        _RTHP-D-PLAN-CONTROLS @ _RTHP-D-PLAN-GLYPHS @ + <> IF RTE-S-INVALID EXIT THEN
    \ Changed status fields follow; the active and pending banks give them.
    _RTHP-D-PENDING @ _RTHP-TB.STATIC-COUNT @ 0 ?DO
        I _RTHP-D-STATIC-CHANGED? IF
            I _RTHP-D-STATIC-RECORD _RTHP-D-P @ _RTHP.FACADE @ RTE-STATIC-REPLACE
            DUP RTE-S-OK <> IF UNLOOP EXIT THEN DROP 1 _RTHP-D-EMITTED +!
        THEN
    LOOP
    _RTHP-D-EMITTED @ 0> IF RTE-S-OK ELSE RTE-S-INVALID THEN ;

: _RTHP-E-ADD-TEXT?  ( bytes -- flag )
    _RTHP-E-NEXT !
    _RTHP-E-TEXT @ _RTHP-E-NEXT @ _RTHP-U32+?
        0= IF DROP 0 EXIT THEN _RTHP-E-TEXT !
    _RTHP-E-NEXT @ _RTHP-ALIGN8? 0= IF DROP 0 EXIT THEN
    _RTHP-E-ALIGNED @ SWAP _RTHP-U32+?
        0= IF DROP 0 EXIT THEN _RTHP-E-ALIGNED !
    _RTHP-E-MAX @ _RTHP-E-NEXT @ MAX _RTHP-E-MAX ! -1 ;

: _RTHP-E-ADD-UTF8?  ( bytes -- flag )
    _RTHP-E-CONTROL-UTF8 @ SWAP _RTHP-U32+?
        0= IF DROP 0 EXIT THEN _RTHP-E-CONTROL-UTF8 ! -1 ;

: _RTHP-E-ADD-CONTENT-ITEMS?  ( count -- flag )
    _RTHP-E-CONTENT-ITEMS @ SWAP _RTHP-U32+?
        0= IF DROP 0 EXIT THEN _RTHP-E-CONTENT-ITEMS ! -1 ;

: _RTHP-EMIT-CONTROLS  ( producer -- rte-status )
    _RTHP-E-P !
    0 _RTHP-E-TEXT ! 0 _RTHP-E-ALIGNED ! 0 _RTHP-E-MAX !
    0 _RTHP-E-LAST !
    0 _RTHP-E-FIELDS ! 0 _RTHP-E-COLLECTIONS ! 0 _RTHP-E-CONTENT-ITEMS !
    0 _RTHP-E-CONTROL-UTF8 !
    _RTHP-E-P @ _RTHP.CONTROL-COUNT @ 0 ?DO
        _RTHP-E-P @ _RTHP.CONTROLS-A @ I RTE-CONTROL-SIZE * +
            DUP _RTHP-E-ITEM !
        DUP _RTE-CONTROL.LABEL-A @ OVER _RTE-CONTROL.LABEL-U @
        _RTHP-E-P @ _RTHP.SOURCE-TEXT-A @
        _RTHP-E-P @ _RTHP.SOURCE-TEXT-USED @ _RTHP-TEXT-WITHIN?
            0= IF DROP RTE-S-INVALID UNLOOP EXIT THEN
        DUP _RTE-CONTROL.SHORTCUT-A @ OVER _RTE-CONTROL.SHORTCUT-U @
        _RTHP-E-P @ _RTHP.SOURCE-TEXT-A @
        _RTHP-E-P @ _RTHP.SOURCE-TEXT-USED @ _RTHP-TEXT-WITHIN?
            0= IF DROP RTE-S-INVALID UNLOOP EXIT THEN
        DUP _RTE-CONTROL.CONTENT-A @ OVER _RTE-CONTROL.CONTENT-U @
        _RTHP-E-P @ _RTHP.SOURCE-TEXT-A @
        _RTHP-E-P @ _RTHP.SOURCE-TEXT-USED @ _RTHP-TEXT-WITHIN?
            0= IF DROP RTE-S-INVALID UNLOOP EXIT THEN
        DUP _RTE-CONTROL.LABEL-U @ OVER _RTE-CONTROL.SHORTCUT-U @
            _RTHP-U32+? 0= IF 2DROP RTE-S-INVALID UNLOOP EXIT THEN
        OVER _RTE-CONTROL.CONTENT-U @ _RTHP-U32+?
            0= IF 2DROP RTE-S-INVALID UNLOOP EXIT THEN
            _RTHP-E-ADD-TEXT? 0= IF DROP RTE-S-INVALID UNLOOP EXIT THEN
        DUP _RTE-CONTROL.LABEL-U @ OVER _RTE-CONTROL.SHORTCUT-U @
            _RTHP-U32+? 0= IF 2DROP RTE-S-INVALID UNLOOP EXIT THEN
        OVER _RTE-CONTROL.CONTENT-UTF8 @ _RTHP-U32+?
            0= IF 2DROP RTE-S-INVALID UNLOOP EXIT THEN
            _RTHP-E-ADD-UTF8? 0= IF DROP RTE-S-INVALID UNLOOP EXIT THEN
        DUP _RTE-CONTROL.CONTENT-ITEMS @ _RTHP-E-ADD-CONTENT-ITEMS?
            0= IF DROP RTE-S-INVALID UNLOOP EXIT THEN
        DUP _RTE-CONTROL.KIND @ _RTHP-COLLECTION-CONTROL-KIND? IF
            _RTHP-E-COLLECTIONS @ 1 _RTHP-U32+?
                0= IF 2DROP RTE-S-INVALID UNLOOP EXIT THEN
                _RTHP-E-COLLECTIONS !
        THEN
        DUP _RTE-CONTROL.KIND @ RTE-CONTROL-FIELD = IF 1 _RTHP-E-FIELDS +! THEN
        DUP _RTE-CONTROL.ID @ DUP _RTHP-E-LAST @ U> 0= IF
            2DROP RTE-S-INVALID UNLOOP EXIT
        THEN _RTHP-E-LAST !
        _RTHP-E-P @ _RTHP.FACADE @ RTE-CONTROL-DEFINE
        DUP RTE-S-OK <> IF UNLOOP EXIT THEN DROP
    LOOP
    _RTHP-E-TEXT @ _RTHP-E-P @ _RTHP.ADMISSION _RTE-HA.CONTROL-BYTES @ =
    _RTHP-E-ALIGNED @ _RTHP-E-P @ _RTHP.ADMISSION
        _RTE-HA.CONTROL-ALIGNED @ = AND
    _RTHP-E-MAX @ _RTHP-E-P @ _RTHP.ADMISSION _RTE-HA.CONTROL-MAX @ = AND
    _RTHP-E-LAST @ _RTHP-E-P @ _RTHP.ADMISSION _RTE-HA.CONTROL-LAST @ = AND
    _RTHP-E-FIELDS @ _RTHP-E-P @ _RTHP.ADMISSION _RTE-HA.FIELD-CONTROLS @ = AND
    _RTHP-E-COLLECTIONS @ _RTHP-E-P @ _RTHP.ADMISSION
        _RTE-HA.CONTROL-COLLECTIONS @ = AND
    _RTHP-E-CONTENT-ITEMS @ _RTHP-E-P @ _RTHP.ADMISSION
        _RTE-HA.CONTROL-ITEMS @ = AND
    _RTHP-E-CONTROL-UTF8 @ _RTHP-E-P @ _RTHP.ADMISSION
        _RTE-HA.CONTROL-UTF8 @ = AND
    IF RTE-S-OK ELSE RTE-S-INVALID THEN ;

VARIABLE _RTHP-E-REGION
VARIABLE _RTHP-E-READOUTS
VARIABLE _RTHP-E-METERS
VARIABLE _RTHP-E-STATUSES
VARIABLE _RTHP-E-FORMATTED
VARIABLE _RTHP-E-FORMATTED-MAX
VARIABLE _RTHP-E-PLOTS
VARIABLE _RTHP-E-POLYLINES
VARIABLE _RTHP-E-PATH-POINTS
VARIABLE _RTHP-E-PATH-MAX

: _RTHP-EMIT-STATICS ( producer -- rte-status )
    DUP _RTHP-SX-P ! _RTHP-STATICS-FIXED? 0= IF RTE-S-INVALID EXIT THEN
    _RTHP-SX-P @ _RTHP.STATIC-COUNT @ 0 ?DO
        _RTHP-SX-P @ _RTHP.STATICS-A @ I RTE-STATIC-SIZE * +
        _RTHP-SX-P @ _RTHP.FACADE @ RTE-STATIC-DEFINE
            DUP RTE-S-OK <> IF UNLOOP EXIT THEN DROP
    LOOP RTE-S-OK ;

: _RTHP-EMIT-INSTRUMENT-REGIONS  ( producer -- rte-status )
    _RTHP-E-P ! 0 _RTHP-E-LAST !
    _RTHP-E-P @ _RTHP.INSTRUMENT-REGION-COUNT @ 0 ?DO
        _RTHP-E-P @ _RTHP.INSTRUMENT-REGIONS-A @
            I RTE-INSTRUMENT-REGION-SIZE * + DUP _RTHP-E-REGION !
        DUP _RTE-IR.ID @ DUP _RTHP-E-LAST @ U> 0= IF
            2DROP RTE-S-INVALID UNLOOP EXIT
        THEN
        _RTHP-E-P @ _RTHP.REGION @ I 1+ _RTHP-U+?
            0= IF 2DROP DROP RTE-S-INVALID UNLOOP EXIT THEN
        <> IF DROP RTE-S-INVALID UNLOOP EXIT THEN
        DUP _RTE-IR.ID @ _RTHP-E-LAST !
        DROP
        _RTHP-E-P @ _RTHP.OWNER @ _RTHP-E-P @ _RTHP.OWNER-GEN @
        _RTHP-E-REGION @ _RTE-IR.ID @
        _RTHP-E-REGION @ _RTE-IR.X @
        _RTHP-E-REGION @ _RTE-IR.Y @
        _RTHP-E-REGION @ _RTE-IR.COLS @
        _RTHP-E-REGION @ _RTE-IR.ROWS @
        _RTHP-E-REGION @ _RTE-IR.CLIP-X @
        _RTHP-E-REGION @ _RTE-IR.CLIP-Y @
        _RTHP-E-REGION @ _RTE-IR.CLIP-COLS @
        _RTHP-E-REGION @ _RTE-IR.CLIP-ROWS @
        _RTHP-E-REGION @ _RTE-IR.Z @
        _RTHP-E-REGION @ _RTE-IR.FLAGS @
        _RTHP-E-P @ _RTHP.FACADE @ RTE-REGION-DEFINE
        DUP RTE-S-OK <> IF UNLOOP EXIT THEN DROP
    LOOP
    _RTHP-E-LAST @ _RTHP-E-P @ _RTHP.INSTRUMENT-LAST-REGION @ =
    _RTHP-E-P @ _RTHP.INSTRUMENT-REGION-COUNT @
        _RTHP-E-P @ _RTHP.ADMISSION
            _RTE-HA.INSTRUMENT-REGION-COUNT @ = AND
    IF RTE-S-OK ELSE RTE-S-INVALID THEN ;

: _RTHP-E-ADD-FORMATTED?  ( bytes -- flag )
    DUP _RTHP-E-FORMATTED-MAX @ MAX _RTHP-E-FORMATTED-MAX !
    _RTHP-E-FORMATTED @ SWAP _RTHP-U32+?
        0= IF DROP 0 EXIT THEN _RTHP-E-FORMATTED ! -1 ;

\ A line's points count as unit bytes but not toward the longest unit.
: _RTHP-E-ADD-UNIT?  ( instrument -- flag )
    _RTHP-E-MAX @ SWAP
    DUP _RTE-INSTRUMENT.UNIT-U @ _RTHP-E-ADD-TEXT? 0= IF 2DROP 0 EXIT THEN
    _RTE-INSTRUMENT.KIND @ RTE-INSTRUMENT-POLYLINE = IF
        _RTHP-E-MAX !
    ELSE DROP THEN -1 ;

\ A line, its points, and the most in one line.
: _RTHP-E-PATH?  ( instrument -- flag )
    _RTHP-E-POLYLINES @ 1 _RTHP-U32+? 0= IF 2DROP 0 EXIT THEN
        _RTHP-E-POLYLINES !
    _RTE-INSTRUMENT.UNIT-U @ 4 RSHIFT
    DUP _RTHP-E-PATH-MAX @ MAX _RTHP-E-PATH-MAX !
    _RTHP-E-PATH-POINTS @ SWAP _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RTHP-E-PATH-POINTS ! -1 ;

: _RTHP-E-INSTRUMENT-KIND?  ( instrument -- flag )
    DUP _RTE-INSTRUMENT.KIND @ RTE-INSTRUMENT-POLYLINE = IF
        _RTHP-E-PATH? EXIT
    THEN
    _RTE-INSTRUMENT.KIND @
    DUP RTE-INSTRUMENT-READOUT = IF
        DROP _RTHP-E-READOUTS @ 1 _RTHP-U32+?
            0= IF DROP 0 EXIT THEN _RTHP-E-READOUTS ! -1 EXIT
    THEN
    DUP RTE-INSTRUMENT-METER = IF
        DROP _RTHP-E-METERS @ 1 _RTHP-U32+?
            0= IF DROP 0 EXIT THEN _RTHP-E-METERS ! -1 EXIT
    THEN
    DUP RTE-INSTRUMENT-WAVEFORM = IF DROP -1 EXIT THEN
    DUP RTE-INSTRUMENT-PLOT = IF
        DROP _RTHP-E-PLOTS @ 1 _RTHP-U32+?
            0= IF DROP 0 EXIT THEN _RTHP-E-PLOTS ! -1 EXIT
    THEN
    RTE-INSTRUMENT-STATUS <> IF 0 EXIT THEN
    _RTHP-E-STATUSES @ 1 _RTHP-U32+?
        0= IF DROP 0 EXIT THEN _RTHP-E-STATUSES ! -1 ;

VARIABLE _RTHP-ES-P
: _RTHP-EMIT-SERIES ( producer -- rte-status )
    DUP _RTHP-ES-P ! _RTHP-SERIES-FIXED? 0= IF RTE-S-INVALID EXIT THEN
    _RTHP-ES-P @ _RTHP.SERIES-COUNT @ 0 ?DO
        _RTHP-ES-P @ _RTHP.SERIES-A @ I RTE-SERIES-SIZE * +
        _RTHP-ES-P @ _RTHP.FACADE @ RTE-SERIES-DEFINE
        DUP RTE-S-OK <> IF UNLOOP EXIT THEN DROP
    LOOP RTE-S-OK ;

: _RTHP-EMIT-INSTRUMENTS  ( producer -- rte-status )
    _RTHP-E-P !
    0 _RTHP-E-TEXT ! 0 _RTHP-E-ALIGNED ! 0 _RTHP-E-MAX !
    0 _RTHP-E-LAST ! 0 _RTHP-E-READOUTS ! 0 _RTHP-E-METERS !
    0 _RTHP-E-STATUSES ! 0 _RTHP-E-FORMATTED !
    0 _RTHP-E-FORMATTED-MAX !
    0 _RTHP-E-PLOTS ! 0 _RTHP-E-POLYLINES !
    0 _RTHP-E-PATH-POINTS ! 0 _RTHP-E-PATH-MAX !
    _RTHP-E-P @ _RTHP.INSTRUMENT-COUNT @ 0 ?DO
        _RTHP-E-P @ _RTHP.INSTRUMENTS-A @ I RTE-INSTRUMENT-SIZE * +
            DUP _RTHP-E-ITEM !
        DUP _RTE-INSTRUMENT.UNIT-A @ OVER _RTE-INSTRUMENT.UNIT-U @
        _RTHP-E-P @ _RTHP.INSTRUMENT-UNITS-A @
        _RTHP-E-P @ _RTHP.INSTRUMENT-UNITS-USED @ _RTHP-TEXT-WITHIN?
            0= IF DROP RTE-S-INVALID UNLOOP EXIT THEN
        DUP _RTHP-E-ADD-UNIT?
            0= IF DROP RTE-S-INVALID UNLOOP EXIT THEN
        DUP _RTE-INSTRUMENT.FORMATTED-U @ _RTHP-E-ADD-FORMATTED?
            0= IF DROP RTE-S-INVALID UNLOOP EXIT THEN
        DUP _RTHP-E-INSTRUMENT-KIND?
            0= IF DROP RTE-S-INVALID UNLOOP EXIT THEN
        DUP _RTE-INSTRUMENT.ID @ DUP _RTHP-E-LAST @ U> 0= IF
            2DROP RTE-S-INVALID UNLOOP EXIT
        THEN
        _RTHP-E-P @ _RTHP.FIRST-OBJECT @
        _RTHP-E-P @ _RTHP.CONTROL-COUNT @ _RTHP-U+?
            0= IF 2DROP DROP RTE-S-INVALID UNLOOP EXIT THEN
        I _RTHP-U+? 0= IF 2DROP DROP RTE-S-INVALID UNLOOP EXIT THEN
        <> IF DROP RTE-S-INVALID UNLOOP EXIT THEN
        DUP _RTE-INSTRUMENT.ID @ _RTHP-E-LAST !
        _RTHP-E-P @ _RTHP.FACADE @ RTE-INSTRUMENT-DEFINE
        DUP RTE-S-OK <> IF UNLOOP EXIT THEN DROP
    LOOP
    _RTHP-E-TEXT @ _RTHP-E-P @ _RTHP.INSTRUMENT-UNITS-USED @ =
    _RTHP-E-TEXT @ _RTHP-E-P @ _RTHP.ADMISSION
        _RTE-HA.INSTRUMENT-UNIT-BYTES @ = AND
    _RTHP-E-ALIGNED @ _RTHP-E-P @ _RTHP.ADMISSION
        _RTE-HA.INSTRUMENT-UNIT-ALIGNED @ = AND
    _RTHP-E-MAX @ _RTHP-E-P @ _RTHP.ADMISSION
        _RTE-HA.INSTRUMENT-UNIT-MAX @ = AND
    _RTHP-E-FORMATTED @ _RTHP-E-P @ _RTHP.ADMISSION
        _RTE-HA.INSTRUMENT-FORMATTED-BYTES @ = AND
    _RTHP-E-FORMATTED-MAX @ _RTHP-E-P @ _RTHP.ADMISSION
        _RTE-HA.INSTRUMENT-FORMATTED-MAX @ = AND
    _RTHP-E-READOUTS @ _RTHP-E-P @ _RTHP.ADMISSION
        _RTE-HA.READOUT-COUNT @ = AND
    _RTHP-E-METERS @ _RTHP-E-P @ _RTHP.ADMISSION
        _RTE-HA.METER-COUNT @ = AND
    _RTHP-E-STATUSES @ _RTHP-E-P @ _RTHP.ADMISSION
        _RTE-HA.STATUS-COUNT @ = AND
    _RTHP-E-PLOTS @ _RTHP-E-P @ _RTHP.ADMISSION
        _RTE-HA.PLOT-COUNT @ = AND
    _RTHP-E-POLYLINES @ _RTHP-E-P @ _RTHP.ADMISSION
        _RTE-HA.POLYLINE-COUNT @ = AND
    _RTHP-E-PATH-POINTS @ _RTHP-E-P @ _RTHP.ADMISSION
        _RTE-HA.PATH-POINTS @ = AND
    _RTHP-E-PATH-MAX @ _RTHP-E-P @ _RTHP.ADMISSION
        _RTE-HA.PATH-POINTS-MAX @ = AND
    _RTHP-E-LAST @ _RTHP-E-P @ _RTHP.INSTRUMENT-LAST @ = AND
    _RTHP-E-LAST @ _RTHP-E-P @ _RTHP.ADMISSION
        _RTE-HA.INSTRUMENT-LAST @ = AND
    IF RTE-S-OK ELSE RTE-S-INVALID THEN ;

: _RTHP-GLYPH-RUN!  ( item ref producer -- flag )
    _RTHP-E-P ! _RTHP-E-REF ! _RTHP-E-ITEM !
    _RTHP-E-REF @ RGRP-TEXT-REF-OFFSET@
        _RTHP-E-TEXT @ <> IF 0 EXIT THEN
    _RTHP-E-REF @ RGRP-TEXT-REF-LENGTH@ DUP _RTHP-E-NEXT !
        _RTHP-E-ITEM @ _RTE-LPI.TEXT-CAPACITY @ <> IF 0 EXIT THEN
    _RTHP-E-TEXT @ _RTHP-E-P @ _RTHP.GLYPH-TEXT-USED @ U> IF 0 EXIT THEN
    _RTHP-E-NEXT @ _RTHP-E-P @ _RTHP.GLYPH-TEXT-USED @
        _RTHP-E-TEXT @ - U> IF 0 EXIT THEN
    _RTHP-E-P @ _RTHP.RUN DUP RTE-GLYPH-RUN-SIZE 0 FILL
    _RTHP-E-P @ _RTHP.OWNER @ OVER _RTE-GLYPH-RUN.OWNER !
    _RTHP-E-P @ _RTHP.OWNER-GEN @ OVER _RTE-GLYPH-RUN.GENERATION !
    _RTHP-E-ITEM @ _RTE-LPI.OBJECT @ OVER _RTE-GLYPH-RUN.OBJECT !
    _RTHP-E-P @ _RTHP.REGION @ OVER _RTE-GLYPH-RUN.REGION !
    _RTHP-E-ITEM @ 8 + OVER 32 + 96 MOVE
    DROP
    _RTHP-E-NEXT @ IF
        _RTHP-E-P @ _RTHP.GLYPH-TEXT-A @ _RTHP-E-TEXT @ +
            _RTHP-E-P @ _RTHP.RUN _RTE-GLYPH-RUN.TEXT-A !
    ELSE
        0 _RTHP-E-P @ _RTHP.RUN _RTE-GLYPH-RUN.TEXT-A !
    THEN
    _RTHP-E-NEXT @ _RTHP-E-P @ _RTHP.RUN _RTE-GLYPH-RUN.TEXT-U !
    -1 ;

: _RTHP-EMIT-GLYPHS  ( producer -- rte-status )
    _RTHP-E-P !
    0 _RTHP-E-TEXT ! 0 _RTHP-E-ALIGNED ! 0 _RTHP-E-MAX !
    0 _RTHP-E-LAST !
    _RTHP-E-P @ _RTHP.GLYPH-COUNT @ 0 ?DO
        _RTHP-E-P @ _RTHP.GLYPH-ITEMS-A @
            I RTE-GLYPH-RUN-PLAN-ITEM-SIZE * + _RTHP-E-ITEM !
        _RTHP-E-P @ _RTHP.GLYPH-REFS-A @
            I RGRP-TEXT-REF-SIZE * + _RTHP-E-REF !
        _RTHP-E-ITEM @ _RTHP-E-REF @ _RTHP-E-P @
            _RTHP-GLYPH-RUN! 0= IF RTE-S-INVALID UNLOOP EXIT THEN
        _RTHP-E-REF @ RGRP-TEXT-REF-LENGTH@
            _RTHP-E-ADD-TEXT? 0= IF RTE-S-INVALID UNLOOP EXIT THEN
        _RTHP-E-ITEM @ _RTE-LPI.OBJECT @ DUP _RTHP-E-LAST @ U> 0= IF
            DROP RTE-S-INVALID UNLOOP EXIT
        THEN _RTHP-E-LAST !
        _RTHP-E-P @ _RTHP.RUN _RTHP-E-P @ _RTHP.FACADE @
            RTE-GLYPH-RUN-DEFINE DUP RTE-S-OK <> IF UNLOOP EXIT THEN DROP
    LOOP
    _RTHP-E-TEXT @ _RTHP-E-P @ _RTHP.GLYPH-TEXT-USED @ =
    _RTHP-E-TEXT @ _RTHP-E-P @ _RTHP.ADMISSION _RTE-HA.GLYPH-TEXT @ = AND
    _RTHP-E-ALIGNED @ _RTHP-E-P @ _RTHP.ADMISSION
        _RTE-HA.GLYPH-ALIGNED @ = AND
    _RTHP-E-MAX @ _RTHP-E-P @ _RTHP.ADMISSION _RTE-HA.GLYPH-MAX @ = AND
    _RTHP-E-LAST @ _RTHP-E-P @ _RTHP.ADMISSION _RTE-HA.GLYPH-LAST @ = AND
    IF RTE-S-OK ELSE RTE-S-INVALID THEN ;

VARIABLE _RTHP-P-P
VARIABLE _RTHP-P-EXTENSION
VARIABLE _RTHP-P-XSTATUS
VARIABLE _RTHP-P-COLS
VARIABLE _RTHP-P-ROWS
VARIABLE _RTHP-P-GEN
VARIABLE _RTHP-P-STATUS
VARIABLE _RTHP-P-STATE

: _RTHP-CAPTURE-SLOT  ( producer -- scb-status )
    DUP _RTHP.FACADE @ RTE-UPDATE-STATE@
    _RTHP-P-STATUS ! _RTHP-P-STATE !
    _RTHP-P-STATUS @ RTE-S-SESSION-LOST = IF
        DROP SCB-S-SESSION-LOST EXIT
    THEN
    _RTHP-P-STATE @ RTE-UPDATE-IDLE = IF
        _RTHP-P-STATUS @ RTE-S-OK = IF DROP SCB-S-OK ELSE DROP SCB-S-INVALID THEN
        EXIT
    THEN
    _RTHP-P-STATE @ RTE-UPDATE-CAPTURING =
    _RTHP-P-STATE @ RTE-UPDATE-SEALED = OR IF
        _RTHP.FACADE @ RTE-RETAINED-CANCEL _RTHP-RTE>SCB EXIT
    THEN
    DROP SCB-S-WOULD-BLOCK ;

: _RTHP-CANCEL-STATUS  ( rte-status producer -- scb-status )
    SWAP _RTHP-P-STATUS !
    DUP _RTHP.FACADE @ RTE-RETAINED-CANCEL
    DUP RTE-S-SESSION-LOST = IF 2DROP SCB-S-SESSION-LOST EXIT THEN
    RTE-S-OK <> IF DROP SCB-S-INVALID EXIT THEN
    DROP _RTHP-P-STATUS @ _RTHP-RTE>SCB ;

\ The base projection's START: one full-surface region with its controls,
\ instruments, statics and residual runs. It publishes the screen when no
\ extension is installed and when an installed one cannot build the draw.
: _RTHP-EMIT-BASE-START ( -- rte-status )
    _RTHP-P-P @ _RTHP.CONTROL-COUNT @
    _RTHP-P-P @ _RTHP.GLYPH-COUNT @ OR
    _RTHP-P-P @ _RTHP.STATIC-COUNT @ OR IF
        _RTHP-P-P @ _RTHP.OWNER @ _RTHP-P-P @ _RTHP.OWNER-GEN @
        _RTHP-P-P @ _RTHP.REGION @ 0 0
        _RTHP-P-P @ _RTHP.COLS @ _RTHP-P-P @ _RTHP.ROWS @
        0 0 0 0 _RTHP-P-P @ _RTHP.ADMISSION _RTE-HA.REGION-Z @
        RTE-REGION-VISIBLE _RTHP-P-P @ _RTHP.FACADE @ RTE-REGION-DEFINE
        DUP RTE-S-OK <> IF
            EXIT
        THEN DROP
    THEN
    _RTHP-P-P @ _RTHP-EMIT-INSTRUMENT-REGIONS
    DUP RTE-S-OK <> IF
        EXIT
    THEN DROP
    _RTHP-P-P @ _RTHP-EMIT-CONTROLS
    DUP RTE-S-OK <> IF
        EXIT
    THEN DROP
    _RTHP-P-P @ _RTHP-EMIT-SERIES
    DUP RTE-S-OK <> IF
        EXIT
    THEN DROP
    _RTHP-P-P @ _RTHP-EMIT-INSTRUMENTS
    DUP RTE-S-OK <> IF
        EXIT
    THEN DROP
    _RTHP-P-P @ _RTHP-EMIT-STATICS
    DUP RTE-S-OK <> IF
        EXIT
    THEN DROP
    _RTHP-P-P @ _RTHP-EMIT-GLYPHS
    DUP RTE-S-OK <> IF
        EXIT
    THEN DROP
    RTE-S-OK ;

\ Diagnostics: candidates built for Desk's shell that were built again
\ alone because the shell could not build its batch.
VARIABLE _RTHP-DIAG-ALONE-REBUILDS

: _RTHP-PREPARE-START  ( producer -- scb-status )
    _RTPROF-PH-OTHER _RTPROF-MARK
    _RTHP-P-P !
    _RTHP-P-P @ _RTHP-TARGET-ABORT
    _RTHP-P-P @ _RTHP-CAPTURE-SLOT DUP SCB-S-OK <> IF EXIT THEN DROP
    _RTPROF-PH-CANDIDATE-VALIDATE _RTPROF-MARK
    _RTHP-P-P @ _RTHP-FIXED?
    _RTPROF-PH-OTHER _RTPROF-MARK
        0= IF SCB-S-INVALID EXIT THEN
    _RTPROF-PH-TARGET-PACK _RTPROF-MARK
    _RTHP-P-P @ _RTHP-TARGET-CANDIDATE?
    _RTPROF-PH-OTHER _RTPROF-MARK
        0= IF SCB-S-INVALID EXIT THEN
    0 _RTHP-W-MEMORY-ASKED ! 0 _RTHP-W-MEMORY-HELD !
    RTHPX-PREPARE _RTHP-P-P @ _RTHP-EXTENSION-CALL
        DUP _RTHP-P-XSTATUS ! RTE-S-OK = _RTHP-P-EXTENSION !
    \ An installed extension that could not build may need more engine
    \ working storage; try once more after it grew.
    _RTHP-P-EXTENSION @ 0= _RTHP-P-P @ _RTHP.EXTENSION @ 0<> AND IF
        _RTHP-P-P @ _RTHP-GROW-STORAGE? IF
            RTHPX-ABORT _RTHP-P-P @ _RTHP-EXTENSION-NOTIFY
            RTHPX-PREPARE _RTHP-P-P @ _RTHP-EXTENSION-CALL
                DUP _RTHP-P-XSTATUS ! RTE-S-OK = _RTHP-P-EXTENSION !
        THEN
    THEN
    _RTHP-P-EXTENSION @ 0= IF
        RTHPX-ABORT _RTHP-P-P @ _RTHP-EXTENSION-NOTIFY
        \ An installed extension that could not build may only need more
        \ terminal space; otherwise its part stays CELL under the base START.
        _RTHP-P-P @ _RTHP.EXTENSION @ IF
            _RTHP-P-P @ _RTHP-ASK-FOR-SPACE? IF
                _RTHP-P-P @ _RTHP-TARGET-ABORT
                _RTHP-P-P @ _RTHP.TARGET-ACTIVE @ IF
                    SCB-S-WOULD-BLOCK
                ELSE SCB-S-OK THEN EXIT
            THEN
            \ A candidate built for the shell has no runs or admission of
            \ its own.  Built alone, it is cut down to fit as a candidate
            \ going out on its own is, and offered to the shell again; if
            \ the shell still cannot build, it goes out alone.
            _RTHP-P-P @ _RTHP.SHELL-BUILT @ IF
                1 _RTHP-DIAG-ALONE-REBUILDS +!
                _RTHP-P-P @ _RTHP-TARGET-ABORT
                _RTHP-P-P @ _RTHP-BUILD-ALONE _RTHP-REBUILD-RESULT
                0= IF EXIT THEN DROP
                _RTHP-P-P @ RECURSE EXIT
            THEN
            RTHP-PART-SHELL _RTHP-P-XSTATUS @ _RTHP-P-P @
                _RTHP-EXTENSION-FALLBACK!
            \ This projection's one region cannot order a document beneath
            \ an overlay pane's, which only the shell's regions paint in
            \ order, so CELL shows this draw.
            _RTHP-P-P @ _RTHP-CROSS-LAYERED? IF
                _RTHP-P-P @ _RTHP-TARGET-ABORT
                _RTHP-P-P @ _RTHP.SOURCE-DRAW @ _RTHP-W-DRAW !
                _RTHP-P-P @ _RTHP-REFUSAL-REASON _RTHP-W-WHY !
                _RTHP-P-P @ _RTHP-REFUSE-DRAW UPICSN-RELEASE-ALL
                _RTHP-PH-READY-BLANK _RTHP-P-P @ _RTHP.PHASE !
                SCB-S-WOULD-BLOCK EXIT
            THEN
        THEN
    THEN
    _RTPROF-PH-RTAPT-CAPTURE _RTPROF-MARK
    RTE-RETAINED-REPLACE-START _RTHP-P-P @ _RTHP.FACADE @
        RTE-RETAINED-BEGIN DUP RTE-S-OK <> IF
        _RTPROF-PH-OTHER _RTPROF-MARK
        _RTHP-P-P @ _RTHP-TARGET-ABORT
        _RTHP-P-P @ _RTHP-CANCEL-STATUS EXIT
    THEN DROP
    _RTHP-P-EXTENSION @ IF
        RTHPX-EMIT _RTHP-P-P @ _RTHP-EXTENSION-CALL
    ELSE _RTHP-EMIT-BASE-START THEN
    DUP RTE-S-OK <> IF
        _RTPROF-PH-OTHER _RTPROF-MARK
        _RTHP-P-P @ _RTHP-TARGET-ABORT
        _RTHP-P-P @ _RTHP-CANCEL-STATUS EXIT
    THEN DROP
    RTE-COMMIT _RTHP-P-P @ _RTHP.FACADE @ RTE-RETAINED-SEAL
    _RTPROF-PH-OTHER _RTPROF-MARK
    DUP RTE-S-OK <> IF
        _RTHP-P-P @ _RTHP-TARGET-ABORT
        _RTHP-P-P @ _RTHP-CANCEL-STATUS EXIT
    THEN DROP
    _RTHP-P-P @ _RTHP-SEAL-PENDING
    _RTHP-PH-START-SEALED _RTHP-P-P @ _RTHP.PHASE ! SCB-S-OK ;

: _RTHP-ACTIVE-DRAW-CURRENT?  ( producer -- flag )
    DUP RTHPX-CURRENT SWAP _RTHP-EXTENSION-CHECK 0= IF DROP 0 EXIT THEN
    DUP _RTHP-PICTURES-CURRENT? 0= IF DROP 0 EXIT THEN
    _RTHP.ACTIVE-DRAW @ DUP 0= IF DROP 0 EXIT THEN
    SCR-DRAW-GENERATION@ = ;

\ Once a rich frame is active, this word may refuse CELL but may never let a
\ newer CELL frame pass under the older rich overlay.  Abandon only the
\ unacknowledged target map, rebuild against the completed draw with the
\ current ID frontier, and seal another full hidden START before returning OK.
: _RTHP-RECAPTURE-START  ( producer -- scb-status )
    DUP _RTHP-P-P ! _RTHP-CAPTURE-SLOT
    DUP SCB-S-OK <> IF EXIT THEN DROP
    _RTHP-P-P @ _RTHP-TARGET-ABORT
    _RTHP-PH-READY-START _RTHP-P-P @ _RTHP.PHASE !
    _RTHP-P-P @ _RTHP-REBUILD-CANDIDATE 0= IF EXIT THEN DROP
    _RTHP-P-P @ _RTHP-PREPARE-START ;

\ Rebuild from the unchanged probe's observation when it reached RUHA for
\ the current draw: nothing between that probe and this rebuild runs
\ application code, yields, or switches screens.  Otherwise observe anew.
: _RTHP-REBUILD-LIVE-CANDIDATE  ( producer -- scb-status built? )
    _RTHP-PROBE-DRAW @ DUP 0= SWAP SCR-DRAW-GENERATION@ <> OR IF
        _RTHP-PROBE-CLEAR _RTHP-REBUILD-CANDIDATE EXIT
    THEN
    >R _RTHP-PROBE-SNAP @ _RTHP-PROBE-STATUS @ _RTHP-PROBE-DRAW @
    _RTHP-PROBE-CLEAR
    R> _RTHP-BUILD-OBSERVED-CANDIDATE _RTHP-REBUILD-RESULT ;

: _RTHP-STAGE-LIVE-CANDIDATE  ( producer -- scb-status stage-route )
    _RTPROF-PH-OTHER _RTPROF-MARK
    CHK-DAMAGE-COUNT @ _RTHP-W-DAMAGE-MARK !
    _RTHP-PROBE-CLEAR
    DUP _RTHP-P-P ! _RTHP-CAPTURE-SLOT
    DUP SCB-S-OK <> IF _RTHP-STAGE-NONE EXIT THEN DROP
    _RTHP-P-P @ _RTHP-TARGET-ABORT
    \ The unchanged route republishes the base target alone, so an installed
    \ extension, which owns the published scene, always takes the full build,
    \ as does every frame in safe mode.
    _RTHP-P-P @ _RTHP.EXTENSION @ 0= CHK-SAFE? 0= AND IF
        _RTHP-P-P @ _RTHP-UNCHANGED-CANDIDATE? IF
            _RTHP-PROBE-CLEAR
            SCB-S-OK _RTHP-STAGE-UNCHANGED EXIT
        THEN
    THEN
    _RTHP-P-P @ _RTHP-REBUILD-LIVE-CANDIDATE
        DUP 0= IF EXIT THEN DROP DROP
    _RTPROF-PH-CANDIDATE-VALIDATE _RTPROF-MARK
    _RTHP-P-P @ _RTHP-FIXED?
    _RTPROF-PH-OTHER _RTPROF-MARK
        0= IF SCB-S-INVALID _RTHP-STAGE-NONE EXIT THEN
    _RTPROF-PH-TARGET-PACK _RTPROF-MARK
    _RTHP-P-P @ _RTHP-TARGET-CANDIDATE?
    _RTPROF-PH-OTHER _RTPROF-MARK
        0= IF
        SCB-S-INVALID _RTHP-STAGE-NONE EXIT
    THEN
    SCB-S-OK _RTHP-STAGE-FULL ;

: _RTHP-DELTA-ACKED-RECAPTURE  ( producer -- scb-status )
    DUP _RTHP-P-P !
    _RTHP-PH-LIVE OVER _RTHP.PHASE !
    DUP _RTHP-TARGET-PUBLISH? 0= IF DROP SCB-S-INVALID EXIT THEN
    _RTHP-RECAPTURE-START ;

: _RTHP-DELTA-STALE  ( producer -- scb-status )
    \ RECAPTURE checks the engine slot before abandoning the pending bank.
    \ PUBLISHING/AWAITING must retain that bank so a later exact ACK can still
    \ promote it even when a newer ordinary draw has already superseded it.
    DUP _RTHP-P-P ! _RTHP.FACADE @ RTE-UPDATE-STATE@
        _RTHP-P-STATUS ! _RTHP-P-STATE !
    _RTHP-P-STATUS @ RTE-S-SESSION-LOST = IF
        _RTHP-P-P @ _RTHP-TARGET-ABORT SCB-S-SESSION-LOST EXIT
    THEN
    _RTHP-P-P @ _RTHP.PHASE @ _RTHP-PH-DELTA-SEALED =
    _RTHP-P-STATE @ RTE-UPDATE-IDLE = AND
    _RTHP-P-STATUS @ RTE-S-OK = AND IF
        \ STEP has not observed this ACK yet, but physical completion is
        \ already exact.  Promote before chasing the newer ordinary draw.
        _RTHP-P-P @ _RTHP-DELTA-ACKED-RECAPTURE EXIT
    THEN
    _RTHP-P-P @ _RTHP-RECAPTURE-START ;

: _RTHP-D-ABANDON  ( rte-status producer -- scb-status )
    DUP _RTHP-P-P ! _RTHP-CANCEL-STATUS
    DUP SCB-S-SESSION-LOST = IF
        _RTHP-P-P @ _RTHP-TARGET-ABORT EXIT
    THEN
    DROP _RTHP-P-P @ _RTHP-DELTA-STALE ;

: _RTHP-PREPARE-DELTA  ( producer -- scb-status )
    _RTPROF-PH-OTHER _RTPROF-MARK
    DUP _RTHP-P-P ! _RTHP-CAPTURE-SLOT
    DUP SCB-S-OK <> IF EXIT THEN DROP
    _RTPROF-PH-RTAPT-CAPTURE _RTPROF-MARK
    RTE-RETAINED-DELTA _RTHP-P-P @ _RTHP.FACADE @
        RTE-RETAINED-BEGIN DUP RTE-S-OK <> IF
        _RTPROF-PH-OTHER _RTPROF-MARK
        _RTHP-P-P @ _RTHP-D-ABANDON EXIT
    THEN DROP
    _RTHP-P-P @ _RTHP.EXTENSION @ IF
        RTHPX-DELTA-EMIT _RTHP-P-P @ _RTHP-EXTENSION-CALL
    ELSE _RTHP-P-P @ _RTHP-EMIT-DELTA THEN
    DUP RTE-S-OK <> IF
        _RTPROF-PH-OTHER _RTPROF-MARK
        _RTHP-P-P @ _RTHP-D-ABANDON EXIT
    THEN DROP
    RTE-COMMIT _RTHP-P-P @ _RTHP.FACADE @ RTE-RETAINED-SEAL
    _RTPROF-PH-OTHER _RTPROF-MARK
    DUP RTE-S-OK <> IF _RTHP-P-P @ _RTHP-D-ABANDON EXIT THEN DROP
    _RTHP-P-P @ _RTHP-SEAL-PENDING
    _RTHP-PH-DELTA-SEALED _RTHP-P-P @ _RTHP.PHASE ! SCB-S-OK ;

\ _RTHP-PREPARE-REVEAL ( sealed-phase producer -- scb-status )
\   Seal the empty CONTINUE that reveals the hidden replacement, a rich
\   candidate or the empty frame, and enter SEALED-PHASE.
VARIABLE _RTHP-P-SEALED

: _RTHP-PREPARE-REVEAL  ( sealed-phase producer -- scb-status )
    _RTPROF-PH-OTHER _RTPROF-MARK
    SWAP _RTHP-P-SEALED !
    DUP _RTHP-P-P ! _RTHP-CAPTURE-SLOT DUP SCB-S-OK <> IF EXIT THEN DROP
    _RTPROF-PH-RTAPT-CAPTURE _RTPROF-MARK
    RTE-RETAINED-REPLACE-CONTINUE _RTHP-P-P @ _RTHP.FACADE @
        RTE-RETAINED-BEGIN DUP RTE-S-OK <> IF
        _RTPROF-PH-OTHER _RTPROF-MARK
        _RTHP-P-P @ _RTHP-CANCEL-STATUS EXIT
    THEN DROP
    RTE-COMMIT-AND-REVEAL _RTHP-P-P @ _RTHP.FACADE @ RTE-RETAINED-SEAL
    _RTPROF-PH-OTHER _RTPROF-MARK
    DUP RTE-S-OK <> IF _RTHP-P-P @ _RTHP-CANCEL-STATUS EXIT THEN DROP
    _RTHP-P-SEALED @ _RTHP-P-P @ _RTHP.PHASE ! SCB-S-OK ;

\ _RTHP-BLANK-BEGIN ( producer -- scb-status )
\   Seal the empty hidden START that replaces the rich frame.  The screen
\   adapter publishes it without CELL and refuses the CELL offer, which the
\   empty frame's reveal later carries.  An update still publishing is
\   waited for.
: _RTHP-BLANK-BEGIN  ( producer -- scb-status )
    _RTPROF-PH-OTHER _RTPROF-MARK
    DUP _RTHP-P-P ! DUP _RTHP-TARGET-ABORT
    _RTHP-CAPTURE-SLOT DUP SCB-S-OK <> IF EXIT THEN DROP
    _RTPROF-PH-RTAPT-CAPTURE _RTPROF-MARK
    RTE-RETAINED-REPLACE-START _RTHP-P-P @ _RTHP.FACADE @
        RTE-RETAINED-BEGIN DUP RTE-S-OK <> IF
        _RTPROF-PH-OTHER _RTPROF-MARK
        _RTHP-P-P @ _RTHP-CANCEL-STATUS EXIT
    THEN DROP
    RTE-COMMIT _RTHP-P-P @ _RTHP.FACADE @ RTE-RETAINED-SEAL
    _RTPROF-PH-OTHER _RTPROF-MARK
    DUP RTE-S-OK <> IF _RTHP-P-P @ _RTHP-CANCEL-STATUS EXIT THEN DROP
    _RTHP-PH-BLANK-SEALED _RTHP-P-P @ _RTHP.PHASE ! SCB-S-OK ;

\ _RTHP-PREPARE-BLANK ( producer -- scb-status )
\   Nothing is retained, so CELL shows any draw as it is.  A newer completed
\   draw is tried again, and one that can be shown rich goes back through a
\   full hidden replacement.
: _RTHP-PREPARE-BLANK  ( producer -- scb-status )
    _RTPROF-PH-OTHER _RTPROF-MARK
    DUP _RTHP-P-P !
    SCR-DRAW-GENERATION@ SWAP _RTHP.REFUSED-DRAW @ = IF SCB-S-OK EXIT THEN
    _RTHP-P-P @ _RTHP-CAPTURE-SLOT DUP SCB-S-OK <> IF EXIT THEN DROP
    _RTHP-P-P @ _RTHP-BUILD-CANDIDATE IF
        RTE-S-OK <> IF SCB-S-INVALID EXIT THEN
        _RTHP-PH-READY-START _RTHP-P-P @ _RTHP.PHASE !
        _RTHP-P-P @ _RTHP-PREPARE-START EXIT
    THEN
    DUP RTE-S-CAPACITY = OVER RTE-S-UNAVAILABLE = OR IF
        DROP _RTHP-P-P @ _RTHP-REFUSE-DRAW SCB-S-OK EXIT
    THEN
    DUP RTE-S-WOULD-BLOCK = IF DROP SCB-S-OK EXIT THEN
    _RTHP-RTE>SCB ;

\ Diagnostics: changed draws the base producer could not match as a DELTA,
\ and how many each check of the gate refused (_RTHP-D-WHY); slot 40 counts
\ changed draws the live stage could not build.
VARIABLE _RTHP-DIAG-DELTA-REFUSALS
CREATE _RTHP-DIAG-DELTA-WHY 64 CELLS ALLOT
_RTHP-DIAG-DELTA-WHY 64 CELLS 0 FILL
: _RTHP-DIAG-WHY+  ( code -- )  63 MIN CELLS _RTHP-DIAG-DELTA-WHY + 1 SWAP +! ;
: _RTHP-PREPARE-LIVE  ( producer -- scb-status )
    _RTPROF-PH-OTHER _RTPROF-MARK
    _RTHP-P-P !
    _RTHP-P-P @ _RTHP-ACTIVE-DRAW-CURRENT? IF SCB-S-OK EXIT THEN
    \ A draw the extension cannot publish as a DELTA goes straight to START.
    RTHPX-DELTA-PROBE _RTHP-P-P @ _RTHP-EXTENSION-CHECK 0= IF
        _RTHP-P-P @ _RTHP-RECAPTURE-START EXIT
    THEN
    _RTHP-P-P @ _RTHP-STAGE-LIVE-CANDIDATE
    DUP _RTHP-STAGE-UNCHANGED = IF
        2DROP
        _RTHP-PH-READY-DELTA _RTHP-P-P @ _RTHP.PHASE !
        _RTHP-P-P @ _RTHP-PREPARE-DELTA EXIT
    THEN
    DUP _RTHP-STAGE-FULL = IF
        2DROP
        _RTPROF-PH-DELTA-COMPARE-NORMALIZE _RTPROF-MARK
        _RTHP-P-P @ _RTHP-DELTA-CANDIDATE?
        _RTPROF-PH-OTHER _RTPROF-MARK
        IF
            \ The base candidate now carries acknowledged identities, so an
            \ extension refusing the DELTA needs a fresh build for its START.
            RTHPX-DELTA-PREPARE _RTHP-P-P @ _RTHP-EXTENSION-CHECK 0= IF
                _RTHP-P-P @ _RTHP-RECAPTURE-START EXIT
            THEN
            _RTHP-PH-READY-DELTA _RTHP-P-P @ _RTHP.PHASE !
            _RTHP-P-P @ _RTHP-PREPARE-DELTA
        ELSE
            1 _RTHP-DIAG-DELTA-REFUSALS +! _RTHP-D-WHY @ _RTHP-DIAG-WHY+
            _RTHP-PH-READY-START _RTHP-P-P @ _RTHP.PHASE !
            _RTHP-P-P @ _RTHP-PREPARE-START
        THEN EXIT
    THEN
    DROP
    DUP SCB-S-WOULD-BLOCK = IF EXIT THEN DROP
    40 _RTHP-DIAG-WHY+
    _RTHP-P-P @ _RTHP-RECAPTURE-START ;

: _RTHP-REVEAL-STALE  ( producer -- scb-status )
    DUP _RTHP-P-P ! _RTHP.FACADE @ RTE-UPDATE-STATE@
        _RTHP-P-STATUS ! _RTHP-P-STATE !
    _RTHP-P-STATUS @ RTE-S-SESSION-LOST = IF
        _RTHP-P-P @ _RTHP-TARGET-ABORT SCB-S-SESSION-LOST EXIT
    THEN
    _RTHP-P-STATE @ RTE-UPDATE-IDLE =
    _RTHP-P-STATUS @ RTE-S-OK = AND IF
        \ The exact physical reveal completed before STEP observed its ACK.
        \ Promote that immutable bank first, then derive the newer draw from
        \ the acknowledged baseline instead of transmitting another START.
        _RTHP-PH-LIVE _RTHP-P-P @ _RTHP.PHASE !
        _RTHP-P-P @ _RTHP-TARGET-PUBLISH? 0= IF
            SCB-S-INVALID EXIT
        THEN
        _RTHP-P-P @ _RTHP-PREPARE-LIVE EXIT
    THEN
    _RTHP-P-P @ _RTHP-RECAPTURE-START ;

\ Frames run between an upload's frames, taking turns with them, so an
\ upload never holds up the screen.  While one of the job's frames awaits
\ its answer the engine takes no update, so no frame is prepared.  The
\ pixel question and a drop are one short exchange each: a frame waits for
\ them too, so none is built at a pixel size about to change or shows a
\ picture being given back.  OK when a frame may be prepared.
: _RTHP-LANE-HOLDS-FRAMES  ( producer -- scb-status )
    DUP _RTHP.LANE-JOB @ DUP 0= IF 2DROP SCB-S-OK EXIT THEN
    DUP RTE-JOB-PIXELS = SWAP RTE-JOB-DROP = OR IF
        DROP SCB-S-WOULD-BLOCK EXIT
    THEN
    _RTHP.FACADE @ RTE-JOB@
    DUP RTE-S-OK <> IF >R 2DROP 2DROP R> _RTHP-RTE>SCB EXIT THEN
    DROP 2DROP DROP
    RTE-JOB-AWAITING = IF SCB-S-WOULD-BLOCK ELSE SCB-S-OK THEN ;

: RTHP-PREPARE  ( cols rows generation producer -- scb-status )
    _RTPROF-PH-OTHER _RTPROF-MARK
    _RTHP-P-P ! _RTHP-P-GEN ! _RTHP-P-ROWS ! _RTHP-P-COLS !
    _RTHP-P-P @ RTHP-VALID? 0= IF SCB-S-INVALID EXIT THEN
    _RTHP-P-COLS @ _RTHP-P-ROWS @ _RTHP-P-GEN @ _RTHP-P-P @
        _RTHP-CALL-SURFACE? 0= IF SCB-S-INVALID EXIT THEN
    _RTHP-P-P @ _RTHP.PHASE @ _RTHP-PH-FAULT = IF
        _RTHP-P-P @ _RTHP.FAULT @ EXIT
    THEN
    \ While the terminal decides, a live rich frame keeps any newer CELL
    \ frame from showing under it; with none, CELL shows the draw.
    _RTHP-P-P @ _RTHP.PHASE @ _RTHP-PH-RESIZING = IF
        _RTHP-P-P @ _RTHP.TARGET-ACTIVE @ IF SCB-S-WOULD-BLOCK ELSE SCB-S-OK THEN
        EXIT
    THEN
    _RTHP-P-P @ _RTHP-LANE-HOLDS-FRAMES DUP SCB-S-OK <> IF EXIT THEN DROP
    _RTHP-P-P @ _RTHP.PHASE @ _RTHP-PH-READY-START = IF
        _RTHP-P-P @ _RTHP-CANDIDATE-CURRENT? IF
            _RTHP-P-P @ _RTHP-PREPARE-START
        ELSE
            _RTHP-P-P @ _RTHP-RECAPTURE-START
        THEN EXIT
    THEN
    _RTHP-P-P @ _RTHP.PHASE @ _RTHP-PH-START-SEALED = IF
        SCB-S-OK EXIT
    THEN
    _RTHP-P-P @ _RTHP.PHASE @ _RTHP-PH-READY-REVEAL = IF
        _RTHP-P-P @ _RTHP-CANDIDATE-CURRENT? IF
            _RTHP-PH-REVEAL-SEALED _RTHP-P-P @ _RTHP-PREPARE-REVEAL
        ELSE
            _RTHP-P-P @ _RTHP-RECAPTURE-START
        THEN EXIT
    THEN
    _RTHP-P-P @ _RTHP.PHASE @ _RTHP-PH-REVEAL-SEALED = IF
        \ A refused outer CELL offer may let Desk finish another draw before
        \ this sealed reveal is retried.  Promote an already acknowledged
        \ reveal before deriving that draw; cancel only while it is still
        \ genuinely pending.
        _RTHP-P-P @ _RTHP-CANDIDATE-CURRENT? IF
            SCB-S-OK
        ELSE
            _RTHP-P-P @ _RTHP-REVEAL-STALE
        THEN EXIT
    THEN
    _RTHP-P-P @ _RTHP.PHASE @ _RTHP-PH-READY-DELTA = IF
        _RTHP-P-P @ _RTHP-CANDIDATE-CURRENT?
        _RTHP-P-P @ _RTHP.TARGET-PENDING @ 0<> AND IF
            _RTHP-P-P @ _RTHP-PREPARE-DELTA
        ELSE
            _RTHP-P-P @ _RTHP-DELTA-STALE
        THEN EXIT
    THEN
    _RTHP-P-P @ _RTHP.PHASE @ _RTHP-PH-DELTA-SEALED = IF
        _RTHP-P-P @ _RTHP-CANDIDATE-CURRENT? IF
            SCB-S-OK
        ELSE
            _RTHP-P-P @ _RTHP-DELTA-STALE
        THEN EXIT
    THEN
    _RTHP-P-P @ _RTHP.PHASE @ _RTHP-PH-LIVE = IF
        _RTHP-P-P @ _RTHP-PREPARE-LIVE EXIT
    THEN
    _RTHP-P-P @ _RTHP.PHASE @ _RTHP-PH-READY-BLANK = IF
        _RTHP-P-P @ _RTHP-BLANK-BEGIN EXIT
    THEN
    _RTHP-P-P @ _RTHP.PHASE @ _RTHP-PH-READY-BLANK-REVEAL = IF
        _RTHP-PH-BLANK-REVEAL-SEALED _RTHP-P-P @ _RTHP-PREPARE-REVEAL EXIT
    THEN
    _RTHP-P-P @ _RTHP.PHASE @ _RTHP-PH-BLANK = IF
        _RTHP-P-P @ _RTHP-PREPARE-BLANK EXIT
    THEN
    SCB-S-OK ;

HERE _RTHP-OWNED-LIMIT !
