\ =====================================================================
\  automation-owner.f - Daybook's reminder operations
\ =====================================================================
\  The owner gives the automation store's records their meaning: typed
\  operations that check what they are asked, edit the tables, and commit.
\
\  Every edit of a reminder names the revision the caller last saw and
\  moves it on by one, so a stale edit is a conflict instead of a silent
\  overwrite.  A create carries a key the caller chose: the same key with
\  the same request again finds the reminder it made, and the same key
\  with another request is a conflict.  A reminder's RID is the digest of
\  the store's identity and its create key.
\
\  Operations take NOW, the wall clock in milliseconds, or
\  DBAO-CLOCK-UNSET when the clock is not set.  One that must place the
\  next occurrence (create, replace, resume, unarchive) refuses without
\  it.  The others record an unknown time as zero.
\
\  For the runner, DBAO-DUE gives the earliest instant a reminder is due,
\  and DBAO-ACCEPT fires every reminder due at NOW.  A firing makes one
\  review item per reminder covering every occurrence up to NOW, merged
\  into an item still awaiting review at the same revision, so unreviewed
\  firings stay one item per reminder.  A single occurrence seen while the
\  clock ran continuously fired on time; anything else was missed.  The
\  next occurrence only moves forward, so a clock that jumps back never
\  fires anything twice.
\
\  Pausing or archiving a reminder stops it firing; resuming or
\  unarchiving starts it again from NOW, skipping what fell in between.
\  Deleting it removes its review items and leaves a tombstone.  Each
\  reminder keeps as many reviewed items as the store's retention says;
\  older ones are pruned and counted.
\
\  The owner is caller-serialized.
\
\  Public API:
\    DBAO-INIT        ( vfs path path-u owner -- status )
\    DBAO-OPEN        ( owner -- status )
\    DBAO-CLOSE       ( owner -- status )
\    DBAO-STORE       ( owner -- store )
\    DBAO-FIND        ( rid owner -- schedule|0 )
\    DBAO-CREATE      ( key draft now rid owner -- status )
\    DBAO-REPLACE     ( rid revision draft now owner -- status )
\    DBAO-PAUSE       ( rid revision now owner -- status )
\    DBAO-RESUME      ( rid revision now owner -- status )
\    DBAO-ARCHIVE     ( rid revision now owner -- status )
\    DBAO-UNARCHIVE   ( rid revision now owner -- status )
\    DBAO-DELETE      ( rid revision now owner -- status )
\    DBAO-REVIEW      ( id last now owner -- status )
\    DBAO-DEFAULT-ZONE!  ( address length owner -- status )
\    DBAO-DUE         ( owner -- utc-s found? )
\    DBAO-ACCEPT      ( now basis owner -- fired status )
\    DBAO-LAST-FIRED@ ( owner -- id )
\ =====================================================================

PROVIDED akashic-dbk-auto-owner

REQUIRE automation-store.f
REQUIRE ../../../math/sha3.f

DBAS-S-OK      CONSTANT DBAO-S-OK
DBAS-S-INVALID CONSTANT DBAO-S-INVALID
DBAS-S-NOMEM   CONSTANT DBAO-S-NOMEM
DBAS-S-IO      CONSTANT DBAO-S-IO
DBAS-S-BLOCKED CONSTANT DBAO-S-BLOCKED
DBAS-S-STATE   CONSTANT DBAO-S-STATE
DBAS-S-ENTROPY CONSTANT DBAO-S-ENTROPY
 7 CONSTANT DBAO-S-CLOCK       \ the clock is not set
 8 CONSTANT DBAO-S-NOT-FOUND
 9 CONSTANT DBAO-S-CONFLICT    \ a stale revision or a reused create key
10 CONSTANT DBAO-S-DELETED
11 CONSTANT DBAO-S-TITLE
12 CONSTANT DBAO-S-ZONE
13 CONSTANT DBAO-S-RULE
14 CONSTANT DBAO-S-NEVER       \ no occurrence at or after now

-1 CONSTANT DBAO-CLOCK-UNSET

\ A draft is what a create or replace asks for:
\    +0 recurrence rule (DBREC-SIZE)
\   +72 title: length cell, DBAS-TITLE-MAX bytes
\  +200 zone: length cell, TZ-STRING-MAX bytes
DBREC-SIZE CONSTANT _DBAO-D-TITLE
_DBAO-D-TITLE 8 + DBAS-TITLE-MAX + CONSTANT _DBAO-D-ZONE
_DBAO-D-ZONE 8 + TZ-STRING-MAX + CONSTANT DBAO-DRAFT-SIZE
: DBAO-D.RULE   ( draft -- rule ) ;
: DBAO-D.TITLE  ( draft -- field ) _DBAO-D-TITLE + ;
: DBAO-D.ZONE   ( draft -- field ) _DBAO-D-ZONE + ;

\ =====================================================================
\  The owner record
\ =====================================================================

0x524E574F42414442 CONSTANT _DBAO-MAGIC  \ "BDABOWNR"

 0 CONSTANT _DBAO-MAGIC-OFF
 8 CONSTANT _DBAO-SELF
16 CONSTANT _DBAO-LAST         \ the latest item DBAO-ACCEPT touched
\ Scratch for one operation.
24 CONSTANT _DBAO-NOW          \ the operation's clock
32 CONSTANT _DBAO-BASIS        \ ACCEPT's clock evidence
40 CONSTANT _DBAO-FIRED        \ reminders ACCEPT fired
48 CONSTANT _DBAO-K            \ an ordinal
56 CONSTANT _DBAO-UTC          \ its instant
64 CONSTANT _DBAO-OUT          \ a caller's buffer or draft
72 CONSTANT _DBAO-COUNT        \ occurrences in a firing
80 CONSTANT _DBAO-KIND         \ how a firing went
88 CONSTANT _DBAO-STORE
_DBAO-STORE DBAS-SIZE + 7 + -8 AND CONSTANT _DBAO-ZONE
_DBAO-ZONE TZ-SIZE + 7 + -8 AND CONSTANT _DBAO-RULE
_DBAO-RULE DBREC-SIZE + CONSTANT _DBAO-RID
_DBAO-RID RID-SIZE + CONSTANT _DBAO-DIGEST
\ A zone made canonical: length cell, TZ-STRING-MAX bytes.
_DBAO-DIGEST 32 + CONSTANT _DBAO-TEXT
_DBAO-TEXT 8 + TZ-STRING-MAX + 7 + -8 AND CONSTANT DBAO-SIZE

: _DBAO.MAGIC   ( owner -- a ) _DBAO-MAGIC-OFF + ;
: _DBAO.SELF    ( owner -- a ) _DBAO-SELF + ;
: _DBAO.LAST    ( owner -- a ) _DBAO-LAST + ;
: _DBAO.NOW     ( owner -- a ) _DBAO-NOW + ;
: _DBAO.BASIS   ( owner -- a ) _DBAO-BASIS + ;
: _DBAO.FIRED   ( owner -- a ) _DBAO-FIRED + ;
: _DBAO.K       ( owner -- a ) _DBAO-K + ;
: _DBAO.UTC     ( owner -- a ) _DBAO-UTC + ;
: _DBAO.OUT     ( owner -- a ) _DBAO-OUT + ;
: _DBAO.COUNT   ( owner -- a ) _DBAO-COUNT + ;
: _DBAO.KIND    ( owner -- a ) _DBAO-KIND + ;
: DBAO-STORE    ( owner -- store ) _DBAO-STORE + ;
: _DBAO.ZONE    ( owner -- zone ) _DBAO-ZONE + ;
: _DBAO.RULE    ( owner -- rule ) _DBAO-RULE + ;
: _DBAO.RID     ( owner -- rid ) _DBAO-RID + ;
: _DBAO.DIGEST  ( owner -- digest ) _DBAO-DIGEST + ;
: _DBAO.TEXT    ( owner -- field ) _DBAO-TEXT + ;

: DBAO-VALID?  ( owner -- flag )
    DUP 0= IF EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _DBAO.MAGIC @ _DBAO-MAGIC <> IF DROP 0 EXIT THEN
    DUP _DBAO.SELF @ = ;

\ The id of the latest review item DBAO-ACCEPT made or added to.
: DBAO-LAST-FIRED@  ( owner -- id ) _DBAO.LAST @ ;

\ OK when the store can take an operation.
: _DBAO-READY  ( owner -- status )
    DBAO-STORE DBAS-STATE@ DUP DBAS-READY = IF DROP DBAO-S-OK EXIT THEN
    DBAS-BLOCKED = IF DBAO-S-BLOCKED ELSE DBAO-S-STATE THEN ;

: _DBAO-COMMIT  ( owner -- status ) DBAO-STORE DBAS-COMMIT ;

\ Undoes an operation's uncommitted edits and returns STATUS.
: _DBAO-UNDO  ( status owner -- status )
    DBAO-STORE DBAS-REVERT ?DUP IF NIP THEN ;

\ =====================================================================
\  Lifecycle and reads
\ =====================================================================

\ Configures OWNER, DBAO-SIZE cell-aligned bytes, to keep its reminders
\ in the file at PATH in VFS.  The owner starts closed.
: DBAO-INIT  ( vfs path path-u owner -- status )
    DUP 0= OVER 7 AND OR IF 2DROP 2DROP DBAO-S-INVALID EXIT THEN
    DUP DBAO-VALID? IF 2DROP 2DROP DBAO-S-STATE EXIT THEN
    DUP DBAO-SIZE 0 FILL
    >R R@ DBAO-STORE DBAS-INIT ?DUP IF R> DBAO-SIZE 0 FILL EXIT THEN
    R@ DUP _DBAO.SELF !
    _DBAO-MAGIC R> _DBAO.MAGIC !
    DBAO-S-OK ;

\ Opens the store: OK, or BLOCKED with the store's reason.
: DBAO-OPEN  ( owner -- status )
    DUP DBAO-VALID? 0= IF DROP DBAO-S-INVALID EXIT THEN
    DBAO-STORE DBAS-OPEN ;

: DBAO-CLOSE  ( owner -- status )
    DUP DBAO-VALID? 0= IF DROP DBAO-S-INVALID EXIT THEN
    DBAO-STORE DBAS-CLOSE ;

\ The schedule RID names, or 0.  Records stay put until the next
\ operation.
: DBAO-FIND  ( rid owner -- schedule|0 )
    DBAO-STORE TUCK DBAS-FIND-SCHEDULE IF SWAP DBAS-SCHEDULE ELSE 2DROP 0 THEN ;

\ =====================================================================
\  Zones, drafts and placement
\ =====================================================================

\ Compiles a schedule's zone into the owner's scratch.
: _DBAO-ZONE!  ( schedule owner -- status )
    SWAP DBAS-S.ZONE DBAS-FIELD$ ROT _DBAO.ZONE TZ-PARSE ;

\ The canonical text of the zone in the owner's scratch.
: _DBAO-CANONICAL  ( owner -- status )
    DUP _DBAO.ZONE OVER _DBAO.TEXT 8 + TZ-STRING-MAX TZ-FORMAT
    ?DUP IF NIP NIP EXIT THEN
    SWAP _DBAO.TEXT ! DBAO-S-OK ;

\ Checks a draft's title, zone and rule.  The zone is left compiled and
\ canonical in the owner's scratch.
: _DBAO-DRAFT  ( draft owner -- status )
    OVER DBAO-D.TITLE DBAS-FIELD$ DBAS-TITLE-OK? 0= IF
        2DROP DBAO-S-TITLE EXIT
    THEN
    OVER DBAO-D.ZONE DBAS-FIELD$ 2 PICK _DBAO.ZONE TZ-PARSE IF
        2DROP DBAO-S-ZONE EXIT
    THEN
    DUP _DBAO-CANONICAL IF 2DROP DBAO-S-ZONE EXIT THEN
    SWAP DBAO-D.RULE SWAP _DBAO.ZONE DBREC-CHECK
    DUP DBREC-S-NEVER = IF DROP DBAO-S-NEVER EXIT THEN
    IF DBAO-S-RULE ELSE DBAO-S-OK THEN ;

\ The draft's first occurrence at or after NOW, into K and UTC.
: _DBAO-FIRST  ( draft owner -- status )
    >R R@ _DBAO.NOW @ 1000 / 1- SWAP DBAO-D.RULE R@ _DBAO.ZONE DBREC-NEXT
    IF 2DROP R> DROP DBAO-S-NEVER EXIT THEN
    R@ _DBAO.UTC ! R> _DBAO.K ! DBAO-S-OK ;

: _DBAO-COMPLETE  ( schedule -- )
    DBAS-COMPLETED OVER DBAS-S.STATE !
    0 OVER DBAS-S.NEXT !
    0 SWAP DBAS-S.NEXT-UTC ! ;

\ Places a schedule's next occurrence at its first at or after NOW, or
\ completes it when there is none.
: _DBAO-PLACE  ( schedule owner -- )
    2DUP _DBAO-ZONE! IF DROP _DBAO-COMPLETE EXIT THEN
    DUP _DBAO.NOW @ 1000 / 1- 2 PICK DBAS-S.RULE ROT _DBAO.ZONE DBREC-NEXT
    IF 2DROP _DBAO-COMPLETE EXIT THEN
    2 PICK DBAS-S.NEXT-UTC ! OVER DBAS-S.NEXT ! DROP ;

\ An edit: the next revision, and the time when the clock is set.
: _DBAO-TOUCH  ( now schedule -- )
    1 OVER DBAS-S.REVISION +!
    OVER 0< IF 2DROP EXIT THEN
    DBAS-S.MODIFIED ! ;

\ The live schedule RID names, at REVISION, for an edit.
: _DBAO-EDIT  ( rid revision owner -- schedule status )
    DUP _DBAO-READY ?DUP IF >R 2DROP DROP 0 R> EXIT THEN
    DBAO-STORE ROT OVER DBAS-FIND-SCHEDULE     ( revision store index found? )
    0= IF 2DROP DROP 0 DBAO-S-NOT-FOUND EXIT THEN
    SWAP DBAS-SCHEDULE                         ( revision schedule )
    DUP DBAS-S.STATE @ DBAS-TOMBSTONE = IF NIP DBAO-S-DELETED EXIT THEN
    TUCK DBAS-S.REVISION @ <> IF DBAO-S-CONFLICT EXIT THEN
    DBAO-S-OK ;

\ =====================================================================
\  Creating and replacing
\ =====================================================================

: _DBAO-RID-DOMAIN$      ( -- address length ) S" akashic.daybook.schedule.v1" ;
: _DBAO-REQUEST-DOMAIN$  ( -- address length ) S" akashic.daybook.create.v1" ;

\ The RID create KEY gives in this store, into the owner's scratch.
: _DBAO-RID!  ( key owner -- )
    SHA3-256-BEGIN
    _DBAO-RID-DOMAIN$ SHA3-256-ADD
    DUP DBAO-STORE DBAS-HEADER DBAS-H.STORE-ID RID-SIZE SHA3-256-ADD
    SWAP RID-SIZE SHA3-256-ADD
    _DBAO.RID SHA3-256-END ;

\ The digest of a checked draft: its rule, title and canonical zone.
: _DBAO-DIGEST  ( draft owner -- )
    SHA3-256-BEGIN
    _DBAO-REQUEST-DOMAIN$ SHA3-256-ADD
    OVER DBAO-D.RULE DBREC-SIZE SHA3-256-ADD
    OVER DBAO-D.TITLE DUP @ 8 + SHA3-256-ADD
    DUP _DBAO.TEXT DUP @ 8 + SHA3-256-ADD
    NIP _DBAO.DIGEST SHA3-256-END ;

\ Writes a checked draft into a schedule, with its next occurrence.
: _DBAO-FILL  ( draft schedule owner -- )
    >R
    OVER DBAO-D.RULE OVER DBAS-S.RULE DBREC-SIZE MOVE
    OVER DBAO-D.TITLE DBAS-FIELD$ 2 PICK DBAS-S.TITLE DBAS-TITLE-MAX DBAS-FIELD!
    R@ _DBAO.TEXT DBAS-FIELD$ 2 PICK DBAS-S.ZONE TZ-STRING-MAX DBAS-FIELD!
    R@ _DBAO.K @ OVER DBAS-S.NEXT !
    R> _DBAO.UTC @ SWAP DBAS-S.NEXT-UTC !
    DROP ;

\ Creates a reminder from DRAFT under create KEY, a caller-chosen
\ 32-byte value, and writes its RID to RID.
: DBAO-CREATE  ( key draft now rid owner -- status )
    >R R@ _DBAO.OUT ! R@ _DBAO.NOW !          ( key draft ; R: owner )
    R@ _DBAO-READY ?DUP IF NIP NIP R> DROP EXIT THEN
    R@ _DBAO.NOW @ 0< IF 2DROP R> DROP DBAO-S-CLOCK EXIT THEN
    OVER RID-ZERO? IF 2DROP R> DROP DBAO-S-INVALID EXIT THEN
    DUP R@ _DBAO-DRAFT ?DUP IF NIP NIP R> DROP EXIT THEN
    DUP R@ _DBAO-DIGEST
    \ A create this key already made answers again.
    OVER R@ DBAO-STORE DBAS-FIND-KEY IF        ( key draft index )
        NIP NIP R@ DBAO-STORE DBAS-KEY
        DUP DBAS-K.DIGEST 32 R@ _DBAO.DIGEST 32 COMPARE IF
            DROP R> DROP DBAO-S-CONFLICT EXIT
        THEN
        DBAS-K.RID R> _DBAO.OUT @ RID-COPY DBAO-S-OK EXIT
    THEN
    DROP
    DUP R@ _DBAO-FIRST ?DUP IF NIP NIP R> DROP EXIT THEN
    R@ DBAO-STORE DBAS-IDENTITY NIP ?DUP IF NIP NIP R> _DBAO-UNDO EXIT THEN
    OVER R@ _DBAO-RID!
    R@ _DBAO.RID R@ DBAO-STORE DBAS-FIND-SCHEDULE IF
        DROP 2DROP DBAO-S-CONFLICT R> _DBAO-UNDO EXIT
    THEN                                      ( key draft index )
    R@ DBAO-STORE DBAS-INSERT-SCHEDULE ?DUP IF
        NIP NIP NIP R> _DBAO-UNDO EXIT
    THEN                                      ( key draft schedule )
    R@ _DBAO.RID OVER RID-SIZE MOVE
    2DUP R@ _DBAO-FILL
    1 OVER DBAS-S.REVISION !
    R@ DBAO-STORE DBAS-HEADER DBAS-H.SERIAL DUP @ 2 PICK DBAS-S.SERIAL ! 1 SWAP +!
    DBAS-ENABLED OVER DBAS-S.STATE !
    DBAS-ACTION-REMINDER OVER DBAS-S.ACTION !
    R@ _DBAO.NOW @ OVER DBAS-S.CREATED !
    R@ _DBAO.NOW @ SWAP DBAS-S.MODIFIED !
    DROP                                      ( key )
    DUP R@ DBAO-STORE DBAS-FIND-KEY DROP
    R@ DBAO-STORE DBAS-INSERT-KEY ?DUP IF NIP NIP R> _DBAO-UNDO EXIT THEN
    SWAP OVER DBAS-K.KEY 32 MOVE
    R@ _DBAO.RID OVER DBAS-K.RID RID-SIZE MOVE
    R@ _DBAO.DIGEST SWAP DBAS-K.DIGEST 32 MOVE
    R@ _DBAO-COMMIT ?DUP IF R> DROP EXIT THEN
    R@ _DBAO.RID R> _DBAO.OUT @ RID-COPY DBAO-S-OK ;

\ Replaces a reminder's rule, title and zone.  It fires next at the new
\ rule's first occurrence at or after NOW.
: DBAO-REPLACE  ( rid revision draft now owner -- status )
    >R R@ _DBAO.NOW ! R@ _DBAO.OUT !          ( rid revision ; R: owner )
    R@ _DBAO-EDIT ?DUP IF NIP R> DROP EXIT THEN
    R@ _DBAO.NOW @ 0< IF DROP R> DROP DBAO-S-CLOCK EXIT THEN
    R@ _DBAO.OUT @ R@ _DBAO-DRAFT ?DUP IF NIP R> DROP EXIT THEN
    R@ _DBAO.OUT @ R@ _DBAO-FIRST ?DUP IF NIP R> DROP EXIT THEN
    R@ _DBAO.OUT @ OVER R@ _DBAO-FILL
    DUP DBAS-S.STATE @ DBAS-COMPLETED = IF DBAS-ENABLED OVER DBAS-S.STATE ! THEN
    R@ _DBAO.NOW @ SWAP _DBAO-TOUCH
    R> _DBAO-COMMIT ;

\ =====================================================================
\  Pausing, archiving and deleting
\ =====================================================================

\ Stops a reminder firing until it is resumed.
: DBAO-PAUSE  ( rid revision now owner -- status )
    TUCK _DBAO.NOW ! DUP >R _DBAO-EDIT ?DUP IF NIP R> DROP EXIT THEN
    DUP DBAS-S.STATE @ DBAS-ENABLED <> IF DROP R> DROP DBAO-S-STATE EXIT THEN
    DBAS-PAUSED OVER DBAS-S.STATE !
    R@ _DBAO.NOW @ SWAP _DBAO-TOUCH
    R> _DBAO-COMMIT ;

\ Starts a paused reminder again from its first occurrence at or after
\ NOW; occurrences while it was paused never fire.
: DBAO-RESUME  ( rid revision now owner -- status )
    TUCK _DBAO.NOW ! DUP >R _DBAO-EDIT ?DUP IF NIP R> DROP EXIT THEN
    DUP DBAS-S.STATE @ DBAS-PAUSED <> IF DROP R> DROP DBAO-S-STATE EXIT THEN
    R@ _DBAO.NOW @ 0< IF DROP R> DROP DBAO-S-CLOCK EXIT THEN
    DBAS-ENABLED OVER DBAS-S.STATE !
    DUP R@ _DBAO-PLACE
    R@ _DBAO.NOW @ SWAP _DBAO-TOUCH
    R> _DBAO-COMMIT ;

\ Hides a reminder and stops it firing.
: DBAO-ARCHIVE  ( rid revision now owner -- status )
    TUCK _DBAO.NOW ! DUP >R _DBAO-EDIT ?DUP IF NIP R> DROP EXIT THEN
    DUP DBAS-S.ARCHIVED @ IF DROP R> DROP DBAO-S-STATE EXIT THEN
    1 OVER DBAS-S.ARCHIVED !
    R@ _DBAO.NOW @ SWAP _DBAO-TOUCH
    R> _DBAO-COMMIT ;

\ Shows a reminder again.  One that was enabled fires from its first
\ occurrence at or after NOW.
: DBAO-UNARCHIVE  ( rid revision now owner -- status )
    TUCK _DBAO.NOW ! DUP >R _DBAO-EDIT ?DUP IF NIP R> DROP EXIT THEN
    DUP DBAS-S.ARCHIVED @ 0= IF DROP R> DROP DBAO-S-STATE EXIT THEN
    DUP DBAS-S.STATE @ DBAS-ENABLED = IF
        R@ _DBAO.NOW @ 0< IF DROP R> DROP DBAO-S-CLOCK EXIT THEN
        DUP R@ _DBAO-PLACE
    THEN
    0 OVER DBAS-S.ARCHIVED !
    R@ _DBAO.NOW @ SWAP _DBAO-TOUCH
    R> _DBAO-COMMIT ;

\ Removes every review item of a schedule.
: _DBAO-DROP-ITEMS  ( schedule owner -- )
    DBAO-STORE SWAP 0                         ( store schedule i )
    BEGIN DUP 3 PICK DBAS-OCCURRENCE-COUNT@ < WHILE
        DUP 3 PICK DBAS-OCCURRENCE DBAS-O.RID 2 PICK RID= IF
            DUP 3 PICK DBAS-DELETE-OCCURRENCE
        ELSE
            1+
        THEN
    REPEAT
    DROP 2DROP ;

\ Deletes a reminder and its review items.  Its RID stays taken.
: DBAO-DELETE  ( rid revision now owner -- status )
    TUCK _DBAO.NOW ! DUP >R _DBAO-EDIT ?DUP IF NIP R> DROP EXIT THEN
    DUP R@ _DBAO-DROP-ITEMS
    DUP DBAS-S.ARCHIVED OVER DBAS-S.CREATED OVER - 0 FILL
    DBAS-TOMBSTONE OVER DBAS-S.STATE !
    R@ _DBAO.NOW @ SWAP _DBAO-TOUCH
    R> _DBAO-COMMIT ;

\ =====================================================================
\  Reviewing
\ =====================================================================

\ How many of a reminder's items have been reviewed.
: _DBAO-REVIEWED-N  ( rid store -- n )
    0 OVER DBAS-OCCURRENCE-COUNT@ 0 ?DO        ( rid store n )
        I 2 PICK DBAS-OCCURRENCE
        DUP DBAS-O.STATE @ DBAS-REVIEWED = SWAP DBAS-O.RID 4 PICK RID= AND
        IF 1+ THEN
    LOOP
    NIP NIP ;

\ The index of a reminder's oldest reviewed item, which exists.
: _DBAO-OLDEST-REVIEWED  ( rid store -- index )
    DUP DBAS-OCCURRENCE-COUNT@ 0 ?DO
        I OVER DBAS-OCCURRENCE
        DUP DBAS-O.STATE @ DBAS-REVIEWED = SWAP DBAS-O.RID 3 PICK RID= AND
        IF 2DROP I UNLOOP EXIT THEN
    LOOP
    2DROP -1 ;

\ Prunes a reminder's reviewed items beyond the retention, oldest first,
\ and counts them.
: _DBAO-PRUNE  ( rid owner -- )
    DBAO-STORE
    BEGIN
        2DUP _DBAO-REVIEWED-N OVER DBAS-HEADER DBAS-H.RETAIN @ >
    WHILE
        2DUP _DBAO-OLDEST-REVIEWED OVER DBAS-DELETE-OCCURRENCE
        2DUP DBAS-FIND-SCHEDULE IF
            OVER DBAS-SCHEDULE 1 SWAP DBAS-S.PRUNED +!
        ELSE
            DROP
        THEN
    REPEAT
    2DROP ;

\ Marks review item ID reviewed.  LAST is the last ordinal the caller saw
\ in it, so firings merged into it since are not reviewed unseen.
: DBAO-REVIEW  ( id last now owner -- status )
    TUCK _DBAO.NOW ! DUP >R _DBAO-READY ?DUP IF NIP NIP R> DROP EXIT THEN
    SWAP R@ DBAO-STORE DBAS-FIND-OCCURRENCE 0= IF
        2DROP R> DROP DBAO-S-NOT-FOUND EXIT
    THEN
    R@ DBAO-STORE DBAS-OCCURRENCE              ( last item )
    DUP DBAS-O.STATE @ DBAS-DUE <> IF 2DROP R> DROP DBAO-S-STATE EXIT THEN
    TUCK DBAS-O.LAST @ <> IF DROP R> DROP DBAO-S-CONFLICT EXIT THEN
    DBAS-REVIEWED OVER DBAS-O.STATE !
    R@ _DBAO.NOW @ 0 MAX OVER DBAS-O.REVIEWED !
    DBAS-O.RID R@ _DBAO.RID RID-COPY
    R@ _DBAO.RID R@ _DBAO-PRUNE
    R> _DBAO-COMMIT ;

\ Sets the zone new reminders start with.
: DBAO-DEFAULT-ZONE!  ( address length owner -- status )
    DUP _DBAO-READY ?DUP IF NIP NIP NIP EXIT THEN
    >R R@ _DBAO.ZONE TZ-PARSE IF R> DROP DBAO-S-ZONE EXIT THEN
    R@ _DBAO-CANONICAL IF R> DROP DBAO-S-ZONE EXIT THEN
    R@ _DBAO.TEXT DBAS-FIELD$
        R@ DBAO-STORE DBAS-HEADER DBAS-H.ZONE TZ-STRING-MAX DBAS-FIELD!
    R> _DBAO-COMMIT ;

\ =====================================================================
\  Firing
\ =====================================================================

\ A reminder that fires: enabled and not archived.
: _DBAO-LIVE?  ( schedule -- flag )
    DUP DBAS-S.STATE @ DBAS-ENABLED = SWAP DBAS-S.ARCHIVED @ 0= AND ;

\ The earliest instant a live reminder is due, in UTC seconds; 0 0 when
\ none is.
: DBAO-DUE  ( owner -- utc-s found? )
    DUP _DBAO-READY IF DROP 0 0 EXIT THEN
    DBAO-STORE 0 0 ROT                         ( best found? store )
    DUP DBAS-SCHEDULE-COUNT@ 0 ?DO
        I OVER DBAS-SCHEDULE DUP _DBAO-LIVE? IF
            DBAS-S.NEXT-UTC @
            2 PICK IF 3 PICK MIN THEN          ( best found? store best' )
            ROT DROP ROT DROP -1 ROT
        ELSE
            DROP
        THEN
    LOOP
    DROP ;

\ The instant of a schedule's K-th occurrence, through the compiled zone.
: _DBAO-INSTANT  ( k schedule owner -- utc status )
    >R DBAS-S.RULE DBREC-OCCURRENCE ?DUP IF R> DROP EXIT THEN
    R> _DBAO.ZONE TZ-LOCAL>UTC NIP ;

\ The last occurrence at or before NOW, into K and UTC.  The rule run
\ without its end gives the first occurrence after NOW, or after an UNTIL
\ that came first; the one before it is the last due, within any COUNT
\ and never before the schedule's next, which is due.
: _DBAO-LAST-DUE  ( schedule owner -- )
    OVER DBAS-S.RULE OVER _DBAO.RULE DBREC-SIZE MOVE
    DBREC-END-NEVER OVER _DBAO.RULE DBREC.END !
    DUP _DBAO.NOW @ 1000 /
    2 PICK DBAS-S.RULE DBREC.END @ DBREC-END-UNTIL = IF
        2 PICK DBAS-S.RULE DBREC.LIMIT @ MIN
    THEN
    OVER _DBAO.RULE 2 PICK _DBAO.ZONE DBREC-NEXT NIP
    IF DROP 0 ELSE 1- THEN                     ( schedule owner k )
    2 PICK DBAS-S.RULE DBREC.END @ DBREC-END-COUNT = IF
        2 PICK DBAS-S.RULE DBREC.LIMIT @ MIN
    THEN
    2 PICK DBAS-S.NEXT @ MAX
    DUP 3 PICK 3 PICK _DBAO-INSTANT IF
        2DROP OVER DBAS-S.NEXT @ 2 PICK DBAS-S.NEXT-UTC @
    THEN                                       ( schedule owner k utc )
    2 PICK _DBAO.UTC ! OVER _DBAO.K ! 2DROP ;

\ The item still awaiting review for a schedule at its revision, or 0.
: _DBAO-PENDING  ( schedule owner -- item|0 )
    DBAO-STORE
    DUP DBAS-OCCURRENCE-COUNT@ 0 ?DO
        I OVER DBAS-OCCURRENCE                 ( schedule store item )
        DUP DBAS-O.STATE @ DBAS-DUE =
        OVER DBAS-O.REVISION @ 4 PICK DBAS-S.REVISION @ = AND
        OVER DBAS-O.RID 4 PICK RID= AND
        IF NIP NIP UNLOOP EXIT THEN
        DROP
    LOOP
    2DROP 0 ;

\ Adds this firing to an item still awaiting review.
: _DBAO-MERGE  ( item owner -- )
    OVER DBAS-O.KIND @ OVER _DBAO.KIND @ MAX 2 PICK DBAS-O.KIND !
    OVER DBAS-O.BASIS @ OVER _DBAO.BASIS @ MAX 2 PICK DBAS-O.BASIS !
    DUP _DBAO.COUNT @ 2 PICK DBAS-O.COUNT +!
    DUP _DBAO.K @ 2 PICK DBAS-O.LAST !
    DUP _DBAO.UTC @ 2 PICK DBAS-O.LAST-UTC !
    _DBAO.NOW @ SWAP DBAS-O.ACCEPTED ! ;

\ A new item awaiting review for this firing.
: _DBAO-APPEND  ( schedule owner -- item status )
    DUP DBAO-STORE DBAS-APPEND-OCCURRENCE ?DUP IF NIP NIP NIP 0 SWAP EXIT THEN
    OVER DBAO-STORE DBAS-HEADER DBAS-H.OCCURRENCE
        DUP @ 2 PICK DBAS-O.ID ! 1 SWAP +!
    2 PICK OVER DBAS-O.RID RID-SIZE MOVE
    2 PICK DBAS-S.REVISION @ OVER DBAS-O.REVISION !
    2 PICK DBAS-S.NEXT @ OVER DBAS-O.FIRST !
    2 PICK DBAS-S.NEXT-UTC @ OVER DBAS-O.FIRST-UTC !
    OVER _DBAO.K @ OVER DBAS-O.LAST !
    OVER _DBAO.UTC @ OVER DBAS-O.LAST-UTC !
    OVER _DBAO.COUNT @ OVER DBAS-O.COUNT !
    OVER _DBAO.KIND @ OVER DBAS-O.KIND !
    DBAS-DUE OVER DBAS-O.STATE !
    OVER _DBAO.BASIS @ OVER DBAS-O.BASIS !
    OVER _DBAO.NOW @ OVER DBAS-O.ACCEPTED !
    NIP NIP DBAO-S-OK ;

\ Records the firing of the occurrences from the schedule's next to K.
: _DBAO-RECORD  ( schedule owner -- status )
    OVER DBAS-S.NEXT @ OVER _DBAO.K @ SWAP - 1+ OVER _DBAO.COUNT !
    DUP _DBAO.BASIS @ DBAS-CONTINUOUS = OVER _DBAO.COUNT @ 1 = AND
    IF DBAS-ON-TIME ELSE DBAS-MISSED THEN OVER _DBAO.KIND !
    2DUP _DBAO-PENDING ?DUP IF
        DUP 2 PICK _DBAO-MERGE
    ELSE
        2DUP _DBAO-APPEND ?DUP IF NIP NIP NIP EXIT THEN
    THEN                                       ( schedule owner item )
    DBAS-O.ID @ 2DUP SWAP _DBAO.LAST !
    2 PICK DBAS-S.LAST !
    _DBAO.KIND @ SWAP DBAS-S.RESULT !
    DBAO-S-OK ;

\ Moves the schedule's next occurrence past NOW, or completes it.
: _DBAO-ADVANCE  ( schedule owner -- )
    DUP _DBAO.NOW @ 1000 / 2 PICK DBAS-S.RULE ROT _DBAO.ZONE DBREC-NEXT
    IF 2DROP _DBAO-COMPLETE EXIT THEN
    2 PICK DBAS-S.NEXT-UTC ! OVER DBAS-S.NEXT ! DROP ;

\ Fires one reminder if it is live and due.
: _DBAO-FIRE  ( schedule owner -- status )
    OVER _DBAO-LIVE? 0= IF 2DROP DBAO-S-OK EXIT THEN
    OVER DBAS-S.NEXT-UTC @ OVER _DBAO.NOW @ 1000 / > IF
        2DROP DBAO-S-OK EXIT
    THEN
    2DUP _DBAO-ZONE! IF 2DROP DBAO-S-INVALID EXIT THEN
    2DUP _DBAO-LAST-DUE
    2DUP _DBAO-RECORD ?DUP IF NIP NIP EXIT THEN
    2DUP _DBAO-ADVANCE
    NIP 1 SWAP _DBAO.FIRED +! DBAO-S-OK ;

\ Fires every reminder due at NOW, with BASIS the clock evidence
\ (DBAS-CONTINUOUS, DBAS-ACTIVATION or DBAS-JUMP), and commits once.
\ Returns how many reminders fired.
: DBAO-ACCEPT  ( now basis owner -- fired status )
    TUCK _DBAO.BASIS ! TUCK _DBAO.NOW !
    DUP _DBAO-READY ?DUP IF NIP 0 SWAP EXIT THEN
    DUP _DBAO.NOW @ 0< IF DROP 0 DBAO-S-CLOCK EXIT THEN
    DUP _DBAO.BASIS @ DBAS-CONTINUOUS DBAS-JUMP 1+ WITHIN 0= IF
        DROP 0 DBAO-S-INVALID EXIT
    THEN
    0 OVER _DBAO.FIRED !
    DUP DBAO-STORE DBAS-SCHEDULE-COUNT@ 0 ?DO
        I OVER DBAO-STORE DBAS-SCHEDULE OVER _DBAO-FIRE ?DUP IF
            SWAP _DBAO-UNDO 0 SWAP UNLOOP EXIT
        THEN
    LOOP
    DUP _DBAO.FIRED @ 0= IF DROP 0 DBAO-S-OK EXIT THEN
    DUP _DBAO-COMMIT ?DUP IF NIP 0 SWAP EXIT THEN
    _DBAO.FIRED @ DBAO-S-OK ;
