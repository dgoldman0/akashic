\ =====================================================================
\  automation-owner.f - Daybook's schedule operations
\ =====================================================================
\  The owner gives the automation store's records their meaning: typed
\  operations that check what they are asked, edit the tables, and commit.
\
\  A schedule names an action from the catalog (interop/scheduled-
\  action.f): a reminder, which makes an item for review, or an Agent
\  run, which Desk's broker starts under a schedule permission.  Every
\  edit of a schedule names the revision the caller last saw and moves it
\  on by one, so a stale edit is a conflict instead of a silent
\  overwrite.  A create carries a key the caller chose: the same key with
\  the same request again finds the schedule it made, and the same key
\  with another request is a conflict.  A schedule's RID is the digest of
\  the store's identity and its create key.
\
\  Operations take NOW, the wall clock in milliseconds, or
\  DBAO-CLOCK-UNSET when the clock is not set.  One that must place the
\  next occurrence (create, replace, resume, unarchive) or record when a
\  run was asked for refuses without it.  The others record an unknown
\  time as zero.
\
\  For the runner, DBAO-DUE gives the earliest instant a schedule is due,
\  DBAO-DUE-QUERY pages through the schedules due by an instant, and
\  DBAO-OCC-ACCEPT records one schedule's due occurrences.  A reminder's
\  firing makes one review item covering every occurrence up to NOW,
\  merged into an item still awaiting review at the same revision.  A
\  single occurrence seen while the clock ran continuously is on time;
\  anything else was missed.  The next occurrence only moves forward, so
\  a clock that jumps back never fires anything twice.
\
\  An Agent run's on-time occurrence is accepted with a dispatch key when
\  its permission stands and no run of the schedule is in flight;
\  otherwise it ends for review, blocked, with the reason.  A missed one
\  never starts: it ends for review as missed, merged like a reminder's.
\  Desk's broker then reports the run started (DBAO-OCC-STARTED) and
\  ended (DBAO-OCC-FINISH), by its key.  Run Now asks for a run by hand
\  through the same path.  Nothing is retried.
\
\  Pausing or archiving a schedule stops it firing; resuming or
\  unarchiving starts it again from NOW, skipping what fell in between.
\  Deleting it leaves a tombstone: a reminder's items go, and an Agent
\  run's become short records that keep when it ran, how it ended and its
\  run RID, but no summary.  Each schedule keeps as many reviewed items as
\  the store's retention says; older ones are pruned and counted.
\
\  The owner is caller-serialized.
\
\  Public API:
\    DBAO-INIT        ( vfs path path-u owner -- status )
\    DBAO-OPEN        ( owner -- status )
\    DBAO-CLOSE       ( owner -- status )
\    DBAO-STORE       ( owner -- store )
\    DBAO-FIND        ( rid owner -- schedule|0 )
\    DBAO-ACTION      ( rid owner -- action|0 )
\    DBAO-CREATE      ( key draft now rid owner -- status )
\    DBAO-REPLACE     ( rid revision draft now owner -- status )
\    DBAO-PAUSE DBAO-RESUME DBAO-ARCHIVE DBAO-UNARCHIVE DBAO-DELETE
\                     ( rid revision now owner -- status )
\    DBAO-AUTHORIZE   ( rid revision response now owner -- status )
\    DBAO-REVIEW      ( id last now owner -- status )
\    DBAO-DEFAULT-ZONE!  ( address length owner -- status )
\    DBAO-QUERY       ( cursor entries max owner -- n cursor' status )
\    DBAO-HISTORY     ( rid cursor entries max owner -- n cursor' status )
\    DBAO-DUE         ( owner -- utc-s found? )
\    DBAO-DUE-QUERY   ( through-s cursor entries max owner -- n cursor' status )
\    DBAO-OCC-ACCEPT  ( entry basis standing now owner -- id status )
\    DBAO-OCC-STARTED ( key run now owner -- status )
\    DBAO-OCC-FINISH  ( key response now owner -- status )
\    DBAO-RUN-NOW     ( rid revision now owner -- id status )
\    DBAO-TRIGGER-DIGEST  ( schedule dest -- )
\ =====================================================================

PROVIDED akashic-dbk-auto-owner

REQUIRE automation-store.f
REQUIRE ../../../math/sha3.f
REQUIRE ../../../interop/scheduled-dispatch.f

DBAS-S-OK      CONSTANT DBAO-S-OK
DBAS-S-INVALID CONSTANT DBAO-S-INVALID
DBAS-S-NOMEM   CONSTANT DBAO-S-NOMEM
DBAS-S-IO      CONSTANT DBAO-S-IO
DBAS-S-BLOCKED CONSTANT DBAO-S-BLOCKED
DBAS-S-STATE   CONSTANT DBAO-S-STATE
DBAS-S-ENTROPY CONSTANT DBAO-S-ENTROPY
 7 CONSTANT DBAO-S-CLOCK       \ the clock is not set
 8 CONSTANT DBAO-S-NOT-FOUND
 9 CONSTANT DBAO-S-CONFLICT    \ a stale revision, a reused create key, or
                               \ another answer for the same occurrence
10 CONSTANT DBAO-S-DELETED
11 CONSTANT DBAO-S-TITLE
12 CONSTANT DBAO-S-ZONE
13 CONSTANT DBAO-S-RULE
14 CONSTANT DBAO-S-NEVER       \ no occurrence at or after now
15 CONSTANT DBAO-S-ACCEPTED    \ that occurrence was accepted before
16 CONSTANT DBAO-S-BUSY        \ a run of the schedule is in flight
17 CONSTANT DBAO-S-REVIEW      \ an indeterminate run awaits review
18 CONSTANT DBAO-S-MANUAL      \ the action is never dispatched
19 CONSTANT DBAO-S-APPROVAL    \ the schedule is not approved
20 CONSTANT DBAO-S-OPERANDS    \ the action's operands are malformed
21 CONSTANT DBAO-S-ACTION      \ not an action, or not the schedule's

-1 CONSTANT DBAO-CLOCK-UNSET

\ A draft is what a create or replace asks for:
\    +0 recurrence rule (DBREC-SIZE)
\   +72 title: length cell, DBAS-TITLE-MAX bytes
\  +200 zone: length cell, TZ-STRING-MAX bytes
\  +336 action   +344 operands: address, length (none for a reminder)
DBREC-SIZE CONSTANT _DBAO-D-TITLE
_DBAO-D-TITLE 8 + DBAS-TITLE-MAX + CONSTANT _DBAO-D-ZONE
_DBAO-D-ZONE 8 + TZ-STRING-MAX + CONSTANT _DBAO-D-ACTION
_DBAO-D-ACTION 8 + CONSTANT _DBAO-D-OPERANDS
_DBAO-D-OPERANDS 16 + CONSTANT DBAO-DRAFT-SIZE
: DBAO-D.RULE      ( draft -- rule ) ;
: DBAO-D.TITLE     ( draft -- field ) _DBAO-D-TITLE + ;
: DBAO-D.ZONE      ( draft -- field ) _DBAO-D-ZONE + ;
: DBAO-D.ACTION    ( draft -- a ) _DBAO-D-ACTION + ;
: DBAO-D.OPERANDS  ( draft -- slot ) _DBAO-D-OPERANDS + ;

\ A due entry, as DBAO-DUE-QUERY writes it: +0 schedule RID
\ +32 revision   +40 the ordinal due next.
48 CONSTANT DBAO-DUE-SIZE
: DBAO-E.RID       ( entry -- rid ) ;
: DBAO-E.REVISION  ( entry -- a ) 32 + ;
: DBAO-E.ORDINAL   ( entry -- a ) 40 + ;

\ =====================================================================
\  The owner record
\ =====================================================================

0x524E574F42414442 CONSTANT _DBAO-MAGIC  \ "BDABOWNR"

  0 CONSTANT _DBAO-MAGIC-OFF
  8 CONSTANT _DBAO-SELF
 16 CONSTANT _DBAO-LAST        \ the latest item an operation made
\ Scratch for one operation.
 24 CONSTANT _DBAO-NOW         \ the operation's clock
 32 CONSTANT _DBAO-BASIS       \ an accept's clock evidence
 40 CONSTANT _DBAO-STANDING    \ an accept's permission standing
 48 CONSTANT _DBAO-K           \ an ordinal
 56 CONSTANT _DBAO-UTC         \ its instant
 64 CONSTANT _DBAO-OUT         \ a caller's buffer, draft or response
 72 CONSTANT _DBAO-COUNT       \ occurrences in a firing
 80 CONSTANT _DBAO-KIND        \ the occurrence's kind
 88 CONSTANT _DBAO-PHASE       \ an Agent run's phase, or 0
 96 CONSTANT _DBAO-OUTCOME
104 CONSTANT _DBAO-REASON
112 CONSTANT _DBAO-STORE
_DBAO-STORE DBAS-SIZE + 7 + -8 AND CONSTANT _DBAO-ZONE
_DBAO-ZONE TZ-SIZE + 7 + -8 AND CONSTANT _DBAO-RULE
_DBAO-RULE DBREC-SIZE + CONSTANT _DBAO-RID
_DBAO-RID RID-SIZE + CONSTANT _DBAO-DIGEST
\ A zone made canonical: length cell, TZ-STRING-MAX bytes.
_DBAO-DIGEST 32 + CONSTANT _DBAO-TEXT
_DBAO-TEXT 8 + TZ-STRING-MAX + 7 + -8 AND CONSTANT DBAO-SIZE

: _DBAO.MAGIC     ( owner -- a ) _DBAO-MAGIC-OFF + ;
: _DBAO.SELF      ( owner -- a ) _DBAO-SELF + ;
: _DBAO.LAST      ( owner -- a ) _DBAO-LAST + ;
: _DBAO.NOW       ( owner -- a ) _DBAO-NOW + ;
: _DBAO.BASIS     ( owner -- a ) _DBAO-BASIS + ;
: _DBAO.STANDING  ( owner -- a ) _DBAO-STANDING + ;
: _DBAO.K         ( owner -- a ) _DBAO-K + ;
: _DBAO.UTC       ( owner -- a ) _DBAO-UTC + ;
: _DBAO.OUT       ( owner -- a ) _DBAO-OUT + ;
: _DBAO.COUNT     ( owner -- a ) _DBAO-COUNT + ;
: _DBAO.KIND      ( owner -- a ) _DBAO-KIND + ;
: _DBAO.PHASE     ( owner -- a ) _DBAO-PHASE + ;
: _DBAO.OUTCOME   ( owner -- a ) _DBAO-OUTCOME + ;
: _DBAO.REASON    ( owner -- a ) _DBAO-REASON + ;
: DBAO-STORE      ( owner -- store ) _DBAO-STORE + ;
: _DBAO.ZONE      ( owner -- zone ) _DBAO-ZONE + ;
: _DBAO.RULE      ( owner -- rule ) _DBAO-RULE + ;
: _DBAO.RID       ( owner -- rid ) _DBAO-RID + ;
: _DBAO.DIGEST    ( owner -- digest ) _DBAO-DIGEST + ;
: _DBAO.TEXT      ( owner -- field ) _DBAO-TEXT + ;

: DBAO-VALID?  ( owner -- flag )
    DUP 0= IF EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _DBAO.MAGIC @ _DBAO-MAGIC <> IF DROP 0 EXIT THEN
    DUP _DBAO.SELF @ = ;

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

\ Configures OWNER, DBAO-SIZE cell-aligned bytes, to keep its schedules
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

\ The action of the schedule RID names, or 0 when it has none.
: DBAO-ACTION  ( rid owner -- action|0 ) DBAO-STORE DBAS-ACTION-OF ;

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

\ Checks a draft's action and operands, title, zone and rule.  The zone is
\ left compiled and canonical in the owner's scratch.
: _DBAO-DRAFT  ( draft owner -- status )
    OVER DBAO-D.ACTION @ DUP DBAS-ACTION-REMINDER =
    SWAP DBAS-ACTION-AGENT = OR 0= IF 2DROP DBAO-S-ACTION EXIT THEN
    OVER DBAO-D.ACTION @ SACT-SCHEMA 3 PICK DBAO-D.OPERANDS BSLOT$
    SACT-OPERANDS-OK? IF 2DROP DBAO-S-OPERANDS EXIT THEN
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

\ The digest a permission binds of when a schedule runs: its rule and its
\ canonical zone field.
: DBAO-TRIGGER-DIGEST  ( schedule dest -- )
    >R SHA3-256-BEGIN
    S" akashic.daybook.trigger.v1" SHA3-256-ADD
    DUP DBAS-S.RULE DBREC-SIZE SHA3-256-ADD
    DBAS-S.ZONE DUP @ 8 + SHA3-256-ADD
    R> SHA3-256-END ;

\ Whether a run of the schedule RID names is in flight.
: _DBAO-IN-FLIGHT?  ( rid owner -- flag )
    DBAO-STORE
    DUP DBAS-OCCURRENCE-COUNT@ 0 ?DO
        I OVER DBAS-OCCURRENCE
        DUP DBAS-O.STATE @ DBAS-IN-FLIGHT =
        OVER DBAS-O.ACTION @ DBAS-ACTION-AGENT = AND
        SWAP DBAS-O.RID 3 PICK RID= AND IF 2DROP -1 UNLOOP EXIT THEN
    LOOP
    2DROP 0 ;

\ Clears the permission an Agent run's schedule was approved under.
: _DBAO-DEAUTHORIZE  ( rid owner -- )
    DBAO-ACTION ?DUP IF DBAS-A.AUTHORIZED 80 0 FILL THEN ;

\ Whether REASON says Desk no longer grants a permission.
: _DBAO-REFUSAL?  ( reason -- flag )
    DUP SACT-R-REVOKED = OVER SACT-R-CHANGED = OR
    OVER SACT-R-NOT-APPROVED = OR SWAP SACT-R-PRACTICE = OR ;

\ Whether RESPONSE names the permission ACTION was approved under.
: _DBAO-HELD?  ( response action -- flag )
    OVER SDSP-P.PERMISSION OVER DBAS-A.PERMISSION RID=
    ROT SDSP-P.PERMISSION-REVISION @ ROT DBAS-A.PERMISSION-REVISION @ = AND ;

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

\ The digest of a checked draft: its rule, title, canonical zone, action
\ and operands.
: _DBAO-DIGEST  ( draft owner -- )
    SHA3-256-BEGIN
    _DBAO-REQUEST-DOMAIN$ SHA3-256-ADD
    OVER DBAO-D.RULE DBREC-SIZE SHA3-256-ADD
    OVER DBAO-D.TITLE DUP @ 8 + SHA3-256-ADD
    DUP _DBAO.TEXT DUP @ 8 + SHA3-256-ADD
    OVER DBAO-D.ACTION 8 SHA3-256-ADD
    OVER DBAO-D.OPERANDS 8 + 8 SHA3-256-ADD
    OVER DBAO-D.OPERANDS BSLOT$ SHA3-256-ADD
    NIP _DBAO.DIGEST SHA3-256-END ;

\ Writes a checked draft's rule, title and zone into a schedule, with its
\ next occurrence.
: _DBAO-FILL  ( draft schedule owner -- )
    >R
    OVER DBAO-D.RULE OVER DBAS-S.RULE DBREC-SIZE MOVE
    OVER DBAO-D.TITLE DBAS-FIELD$ 2 PICK DBAS-S.TITLE DBAS-TITLE-MAX DBAS-FIELD!
    R@ _DBAO.TEXT DBAS-FIELD$ 2 PICK DBAS-S.ZONE TZ-STRING-MAX DBAS-FIELD!
    R@ _DBAO.K @ OVER DBAS-S.NEXT !
    R> _DBAO.UTC @ SWAP DBAS-S.NEXT-UTC !
    DROP ;

\ A new action for the schedule RID names with the draft's operands.
: _DBAO-NEW-ACTION  ( draft owner -- status )
    DUP _DBAO.RID OVER DBAO-STORE DBAS-FIND-ACTION DROP
    OVER DBAO-STORE DBAS-INSERT-ACTION ?DUP IF NIP NIP NIP EXIT THEN
    OVER _DBAO.RID OVER DBAS-A.RID RID-SIZE MOVE
    DBAS-ACTION-AGENT OVER DBAS-A.ACTION !
    SACT-SCHEMA OVER DBAS-A.SCHEMA !
    ROT DBAO-D.OPERANDS BSLOT$ ROT DBAS-A.OPERANDS DBAS-BLOB!
    NIP ;

\ Creates a schedule from DRAFT under create KEY, a caller-chosen 32-byte
\ value, and writes its RID to RID.
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
    OVER DBAO-D.ACTION @ OVER DBAS-S.ACTION !
    R@ _DBAO.NOW @ OVER DBAS-S.CREATED !
    R@ _DBAO.NOW @ OVER DBAS-S.MODIFIED !
    DBAS-S.ACTION @ DBAS-ACTION-AGENT = IF      ( key draft )
        DUP R@ _DBAO-NEW-ACTION ?DUP IF NIP NIP R> _DBAO-UNDO EXIT THEN
    THEN
    DROP                                      ( key )
    DUP R@ DBAO-STORE DBAS-FIND-KEY DROP
    R@ DBAO-STORE DBAS-INSERT-KEY ?DUP IF NIP NIP R> _DBAO-UNDO EXIT THEN
    SWAP OVER DBAS-K.KEY 32 MOVE
    R@ _DBAO.RID OVER DBAS-K.RID RID-SIZE MOVE
    R@ _DBAO.DIGEST SWAP DBAS-K.DIGEST 32 MOVE
    R@ _DBAO-COMMIT ?DUP IF R> DROP EXIT THEN
    R@ _DBAO.RID R> _DBAO.OUT @ RID-COPY DBAO-S-OK ;

\ Whether a checked draft runs a schedule exactly as before: the same
\ rule, canonical zone and operands, so its approval still holds.
: _DBAO-SAME?  ( draft schedule owner -- flag )
    >R
    OVER DBAO-D.RULE DBREC-SIZE 2 PICK DBAS-S.RULE DBREC-SIZE COMPARE IF
        2DROP R> DROP 0 EXIT
    THEN
    R@ _DBAO.TEXT DUP @ 8 + 2 PICK DBAS-S.ZONE DUP @ 8 + COMPARE IF
        2DROP R> DROP 0 EXIT
    THEN
    DBAS-S.RID R> DBAO-ACTION ?DUP 0= IF DROP 0 EXIT THEN
    DBAS-A.OPERANDS BSLOT$ ROT DBAO-D.OPERANDS BSLOT$ COMPARE 0= ;

\ Replaces a schedule's rule, title, zone and operands; its action stays.
\ It fires next at the new rule's first occurrence at or after NOW.  A
\ change to when or how an Agent run runs needs approval again; a new
\ title alone does not.
: DBAO-REPLACE  ( rid revision draft now owner -- status )
    >R R@ _DBAO.NOW ! R@ _DBAO.OUT !          ( rid revision ; R: owner )
    R@ _DBAO-EDIT ?DUP IF NIP R> DROP EXIT THEN
    R@ _DBAO.NOW @ 0< IF DROP R> DROP DBAO-S-CLOCK EXIT THEN
    R@ _DBAO.OUT @ R@ _DBAO-DRAFT ?DUP IF NIP R> DROP EXIT THEN
    R@ _DBAO.OUT @ DBAO-D.ACTION @ OVER DBAS-S.ACTION @ <> IF
        DROP R> DROP DBAO-S-ACTION EXIT
    THEN
    R@ _DBAO.OUT @ R@ _DBAO-FIRST ?DUP IF NIP R> DROP EXIT THEN
    DUP DBAS-S.ACTION @ DBAS-ACTION-AGENT = IF
        R@ _DBAO.OUT @ OVER R@ _DBAO-SAME? 0= IF
            DUP DBAS-S.RID R@ _DBAO-DEAUTHORIZE
        THEN
        R@ _DBAO.OUT @ DBAO-D.OPERANDS BSLOT$
        2 PICK DBAS-S.RID R@ DBAO-ACTION DBAS-A.OPERANDS DBAS-BLOB!
        ?DUP IF NIP R> _DBAO-UNDO EXIT THEN
    THEN
    R@ _DBAO.OUT @ OVER R@ _DBAO-FILL
    DUP DBAS-S.STATE @ DBAS-COMPLETED = IF DBAS-ENABLED OVER DBAS-S.STATE ! THEN
    R@ _DBAO.NOW @ SWAP _DBAO-TOUCH
    R> _DBAO-COMMIT ;

\ Records the permission an Agent run's schedule was approved under, as
\ Desk's broker answered it in RESPONSE: the Practice, the permission and
\ its revision.
: DBAO-AUTHORIZE  ( rid revision response now owner -- status )
    >R R@ _DBAO.NOW ! R@ _DBAO.OUT !          ( rid revision ; R: owner )
    R@ _DBAO-EDIT ?DUP IF NIP R> DROP EXIT THEN
    DUP DBAS-S.ACTION @ DBAS-ACTION-AGENT <> IF DROP R> DROP DBAO-S-MANUAL EXIT THEN
    R@ _DBAO.OUT @ DUP SDSP-P.PRACTICE RID-ZERO?
    OVER SDSP-P.PERMISSION RID-ZERO? OR
    SWAP SDSP-P.PERMISSION-REVISION @ 1 < OR IF
        DROP R> DROP DBAO-S-INVALID EXIT
    THEN
    DBAS-S.RID R@ DBAO-ACTION                 ( action )
    1 OVER DBAS-A.AUTHORIZED !
    R@ _DBAO.OUT @ SDSP-P.PRACTICE OVER DBAS-A.PRACTICE RID-SIZE MOVE
    R@ _DBAO.OUT @ SDSP-P.PERMISSION OVER DBAS-A.PERMISSION RID-SIZE MOVE
    R@ _DBAO.OUT @ SDSP-P.PERMISSION-REVISION @ SWAP DBAS-A.PERMISSION-REVISION !
    R> _DBAO-COMMIT ;

\ =====================================================================
\  Retention
\ =====================================================================

\ An item of the schedule RID needing no more attention: reviewed, or a
\ run that completed.
: _DBAO-SETTLED?  ( item rid -- flag )
    OVER DBAS-O.RID RID= 0= IF DROP 0 EXIT THEN
    DBAS-O.STATE @ DUP DBAS-REVIEWED = SWAP DBAS-CLEAR = OR ;

: _DBAO-SETTLED-N  ( rid store -- n )
    0 OVER DBAS-OCCURRENCE-COUNT@ 0 ?DO        ( rid store n )
        I 2 PICK DBAS-OCCURRENCE 3 PICK _DBAO-SETTLED? IF 1+ THEN
    LOOP
    NIP NIP ;

\ The index of a schedule's oldest settled item, which exists.
: _DBAO-OLDEST-SETTLED  ( rid store -- index )
    DUP DBAS-OCCURRENCE-COUNT@ 0 ?DO
        I OVER DBAS-OCCURRENCE 2 PICK _DBAO-SETTLED? IF 2DROP I UNLOOP EXIT THEN
    LOOP
    2DROP -1 ;

\ Prunes a schedule's settled items beyond the retention, oldest first,
\ and counts them.
: _DBAO-PRUNE  ( rid owner -- )
    DBAO-STORE
    BEGIN
        2DUP _DBAO-SETTLED-N OVER DBAS-HEADER DBAS-H.RETAIN @ >
    WHILE
        2DUP _DBAO-OLDEST-SETTLED OVER DBAS-DELETE-OCCURRENCE
        2DUP DBAS-FIND-SCHEDULE IF
            OVER DBAS-SCHEDULE 1 SWAP DBAS-S.PRUNED +!
        ELSE
            DROP
        THEN
    REPEAT
    2DROP ;

\ =====================================================================
\  Pausing, archiving and deleting
\ =====================================================================

\ Stops a schedule firing until it is resumed.
: DBAO-PAUSE  ( rid revision now owner -- status )
    TUCK _DBAO.NOW ! DUP >R _DBAO-EDIT ?DUP IF NIP R> DROP EXIT THEN
    DUP DBAS-S.STATE @ DBAS-ENABLED <> IF DROP R> DROP DBAO-S-STATE EXIT THEN
    DBAS-PAUSED OVER DBAS-S.STATE !
    R@ _DBAO.NOW @ SWAP _DBAO-TOUCH
    R> _DBAO-COMMIT ;

\ Starts a paused schedule again from its first occurrence at or after
\ NOW; occurrences while it was paused never fire.
: DBAO-RESUME  ( rid revision now owner -- status )
    TUCK _DBAO.NOW ! DUP >R _DBAO-EDIT ?DUP IF NIP R> DROP EXIT THEN
    DUP DBAS-S.STATE @ DBAS-PAUSED <> IF DROP R> DROP DBAO-S-STATE EXIT THEN
    R@ _DBAO.NOW @ 0< IF DROP R> DROP DBAO-S-CLOCK EXIT THEN
    DBAS-ENABLED OVER DBAS-S.STATE !
    DUP R@ _DBAO-PLACE
    R@ _DBAO.NOW @ SWAP _DBAO-TOUCH
    R> _DBAO-COMMIT ;

\ Hides a schedule and stops it firing.
: DBAO-ARCHIVE  ( rid revision now owner -- status )
    TUCK _DBAO.NOW ! DUP >R _DBAO-EDIT ?DUP IF NIP R> DROP EXIT THEN
    DUP DBAS-S.ARCHIVED @ IF DROP R> DROP DBAO-S-STATE EXIT THEN
    1 OVER DBAS-S.ARCHIVED !
    R@ _DBAO.NOW @ SWAP _DBAO-TOUCH
    R> _DBAO-COMMIT ;

\ Shows a schedule again.  One that was enabled fires from its first
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

\ Whether a run of the schedule RID names ended indeterminate and awaits
\ review.
: _DBAO-UNCERTAIN?  ( rid owner -- flag )
    DBAO-STORE
    DUP DBAS-OCCURRENCE-COUNT@ 0 ?DO
        I OVER DBAS-OCCURRENCE
        DUP DBAS-O.OUTCOME @ SACT-O-INDETERMINATE =
        OVER DBAS-O.STATE @ DBAS-DUE = AND
        SWAP DBAS-O.RID 3 PICK RID= AND IF 2DROP -1 UNLOOP EXIT THEN
    LOOP
    2DROP 0 ;

\ Removes a reminder's items.  Keeps an Agent run's as short records,
\ without their summaries; one still awaiting review counts as reviewed
\ now.
: _DBAO-DROP-ITEMS  ( schedule owner -- )
    DUP _DBAO.NOW @ 0 MAX SWAP DBAO-STORE ROT 0   ( reviewed store schedule i )
    BEGIN DUP 3 PICK DBAS-OCCURRENCE-COUNT@ < WHILE
        DUP 3 PICK DBAS-OCCURRENCE              ( reviewed store schedule i item )
        DUP DBAS-O.RID 3 PICK RID= 0= IF
            DROP 1+
        ELSE DUP DBAS-O.ACTION @ DBAS-ACTION-AGENT <> IF
            DROP DUP 3 PICK DBAS-DELETE-OCCURRENCE
        ELSE
            0 0 2 PICK DBAS-O.SUMMARY DBAS-BLOB! DROP
            DBAS-F-AUDIT OVER DBAS-O.FLAGS !
            DUP DBAS-O.STATE @ DBAS-DUE = IF
                DBAS-REVIEWED OVER DBAS-O.STATE !
                4 PICK OVER DBAS-O.REVIEWED !
            THEN
            DROP 1+
        THEN THEN
    REPEAT
    2DROP 2DROP ;

\ Deletes a schedule.  A reminder's items go; an Agent run's become short
\ records, as many as the retention keeps.  Its RID stays taken.  A run
\ in flight, or one that ended indeterminate and awaits review, keeps it.
: DBAO-DELETE  ( rid revision now owner -- status )
    TUCK _DBAO.NOW ! DUP >R _DBAO-EDIT ?DUP IF NIP R> DROP EXIT THEN
    DUP DBAS-S.RID R@ _DBAO-IN-FLIGHT? IF DROP R> DROP DBAO-S-BUSY EXIT THEN
    DUP DBAS-S.RID R@ _DBAO-UNCERTAIN? IF DROP R> DROP DBAO-S-REVIEW EXIT THEN
    DUP R@ _DBAO-DROP-ITEMS
    DUP DBAS-S.RID R@ _DBAO-PRUNE
    DUP DBAS-S.RID R@ DBAO-STORE DBAS-FIND-ACTION IF
        R@ DBAO-STORE DBAS-DELETE-ACTION
    ELSE
        DROP
    THEN
    DUP DBAS-S.ARCHIVED OVER DBAS-S.CREATED OVER - 0 FILL
    DBAS-TOMBSTONE OVER DBAS-S.STATE !
    R@ _DBAO.NOW @ SWAP _DBAO-TOUCH
    R> _DBAO-COMMIT ;

\ =====================================================================
\  Reviewing
\ =====================================================================

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

\ Sets the zone new schedules start with.
: DBAO-DEFAULT-ZONE!  ( address length owner -- status )
    DUP _DBAO-READY ?DUP IF NIP NIP NIP EXIT THEN
    >R R@ _DBAO.ZONE TZ-PARSE IF R> DROP DBAO-S-ZONE EXIT THEN
    R@ _DBAO-CANONICAL IF R> DROP DBAO-S-ZONE EXIT THEN
    R@ _DBAO.TEXT DBAS-FIELD$
        R@ DBAO-STORE DBAS-HEADER DBAS-H.ZONE TZ-STRING-MAX DBAS-FIELD!
    R> _DBAO-COMMIT ;

\ =====================================================================
\  Paged reads
\ =====================================================================

\ The RIDs of up to MAX live schedules into ENTRIES, 32 bytes each, in
\ RID order from schedule index CURSOR; CURSOR' continues the page.
: DBAO-QUERY  ( cursor entries max owner -- n cursor' status )
    DUP _DBAO-READY ?DUP IF >R DROP 2DROP 0 SWAP R> EXIT THEN
    DBAO-STORE >R ROT 0 SWAP                   ( entries max n i ; R: store )
    BEGIN
        DUP R@ DBAS-SCHEDULE-COUNT@ < 2 PICK 4 PICK < AND
    WHILE
        DUP R@ DBAS-SCHEDULE DUP DBAS-S.STATE @ DBAS-TOMBSTONE <> IF
            4 PICK 3 PICK RID-SIZE * + RID-SIZE MOVE
            SWAP 1+ SWAP
        ELSE DROP THEN
        1+
    REPEAT
    R> DROP 2SWAP 2DROP DBAO-S-OK ;

\ The ids of up to MAX items of the schedule RID names into ENTRIES, a
\ cell each, newest first, skipping the CURSOR newest; CURSOR' continues.
: DBAO-HISTORY  ( rid cursor entries max owner -- n cursor' status )
    DUP _DBAO-READY ?DUP IF >R DROP 2DROP NIP 0 SWAP R> EXIT THEN
    >R R@ _DBAO.COUNT ! R@ _DBAO.OUT ! R@ _DBAO.K ! R@ _DBAO.RID RID-COPY
    0 0 R@ DBAO-STORE DBAS-OCCURRENCE-COUNT@   ( n seen i )
    BEGIN DUP 0> 3 PICK R@ _DBAO.COUNT @ < AND WHILE
        1- DUP R@ DBAO-STORE DBAS-OCCURRENCE
        DUP DBAS-O.RID R@ _DBAO.RID RID= IF
            2 PICK R@ _DBAO.K @ < IF
                DROP SWAP 1+ SWAP
            ELSE
                DBAS-O.ID @ 3 PICK CELLS R@ _DBAO.OUT @ + !
                ROT 1+ ROT 1+ ROT
            THEN
        ELSE DROP THEN
    REPEAT
    DROP DROP DUP R> _DBAO.K @ + DBAO-S-OK ;

\ =====================================================================
\  Firing
\ =====================================================================

\ A schedule that fires: enabled and not archived.
: _DBAO-LIVE?  ( schedule -- flag )
    DUP DBAS-S.STATE @ DBAS-ENABLED = SWAP DBAS-S.ARCHIVED @ 0= AND ;

\ The earliest instant a live schedule is due, in UTC seconds; 0 0 when
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

\ Up to MAX live schedules due by THROUGH-S into ENTRIES (DBAO-DUE-SIZE
\ bytes each), in RID order from schedule index CURSOR; CURSOR'
\ continues the page.
: DBAO-DUE-QUERY  ( through-s cursor entries max owner -- n cursor' status )
    >R
    R@ _DBAO-READY ?DUP IF >R 2DROP NIP 0 SWAP R> R> DROP EXIT THEN
    R@ _DBAO.COUNT ! R@ _DBAO.OUT ! SWAP R@ _DBAO.UTC !   ( cursor )
    0 SWAP                                                ( n i )
    BEGIN
        DUP R@ DBAO-STORE DBAS-SCHEDULE-COUNT@ <
        2 PICK R@ _DBAO.COUNT @ < AND
    WHILE
        DUP R@ DBAO-STORE DBAS-SCHEDULE                   ( n i s )
        DUP _DBAO-LIVE? OVER DBAS-S.NEXT-UTC @ R@ _DBAO.UTC @ > 0= AND IF
            2 PICK DBAO-DUE-SIZE * R@ _DBAO.OUT @ +       ( n i s entry )
            OVER DBAS-S.RID OVER RID-SIZE MOVE
            OVER DBAS-S.REVISION @ OVER DBAO-E.REVISION !
            SWAP DBAS-S.NEXT @ SWAP DBAO-E.ORDINAL !       ( n i )
            SWAP 1+ SWAP
        ELSE DROP THEN
        1+
    REPEAT
    R> DROP DBAO-S-OK ;

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

\ The item of a schedule at its revision still awaiting review with this
\ occurrence's outcome and reason, or 0.
: _DBAO-PENDING  ( schedule owner -- item|0 )
    DUP _DBAO.OUTCOME @ OVER _DBAO.REASON @ ROT DBAO-STORE   ( s outcome reason store )
    DUP DBAS-OCCURRENCE-COUNT@ 0 ?DO
        I OVER DBAS-OCCURRENCE                 ( s outcome reason store item )
        DUP DBAS-O.STATE @ DBAS-DUE =
        OVER DBAS-O.REVISION @ 6 PICK DBAS-S.REVISION @ = AND
        OVER DBAS-O.RID 6 PICK RID= AND
        OVER DBAS-O.OUTCOME @ 5 PICK = AND
        OVER DBAS-O.REASON @ 4 PICK = AND
        IF NIP NIP NIP NIP UNLOOP EXIT THEN
        DROP
    LOOP
    2DROP 2DROP 0 ;

\ Adds this firing to an item still awaiting review.
: _DBAO-MERGE  ( item owner -- )
    OVER DBAS-O.KIND @ OVER _DBAO.KIND @ MAX 2 PICK DBAS-O.KIND !
    OVER DBAS-O.BASIS @ OVER _DBAO.BASIS @ MAX 2 PICK DBAS-O.BASIS !
    DUP _DBAO.COUNT @ 2 PICK DBAS-O.COUNT +!
    DUP _DBAO.K @ 2 PICK DBAS-O.LAST !
    DUP _DBAO.UTC @ 2 PICK DBAS-O.LAST-UTC !
    DUP _DBAO.NOW @ 2 PICK DBAS-O.ACCEPTED !
    DUP _DBAO.PHASE @ IF _DBAO.NOW @ SWAP DBAS-O.ENDED ! ELSE 2DROP THEN ;

\ A new item for this occurrence.  An accepted Agent run gets its dispatch
\ key; one that ended at once awaits review.
: _DBAO-APPEND  ( schedule owner -- item status )
    DUP DBAO-STORE DBAS-APPEND-OCCURRENCE ?DUP IF NIP NIP NIP 0 SWAP EXIT THEN
    OVER DBAO-STORE DBAS-HEADER DBAS-H.OCCURRENCE
        DUP @ 2 PICK DBAS-O.ID ! 1 SWAP +!
    2 PICK OVER DBAS-O.RID RID-SIZE MOVE
    2 PICK DBAS-S.REVISION @ OVER DBAS-O.REVISION !
    OVER _DBAO.KIND @ DBAS-MANUAL = IF
        0 OVER DBAS-O.FIRST ! OVER _DBAO.NOW @ 1000 / OVER DBAS-O.FIRST-UTC !
    ELSE
        2 PICK DBAS-S.NEXT @ OVER DBAS-O.FIRST !
        2 PICK DBAS-S.NEXT-UTC @ OVER DBAS-O.FIRST-UTC !
    THEN
    OVER _DBAO.K @ OVER DBAS-O.LAST !
    OVER _DBAO.UTC @ OVER DBAS-O.LAST-UTC !
    OVER _DBAO.COUNT @ OVER DBAS-O.COUNT !
    OVER _DBAO.KIND @ OVER DBAS-O.KIND !
    OVER _DBAO.BASIS @ OVER DBAS-O.BASIS !
    OVER _DBAO.NOW @ OVER DBAS-O.ACCEPTED !
    2 PICK DBAS-S.ACTION @ OVER DBAS-O.ACTION !
    OVER _DBAO.PHASE @ DUP 2 PICK DBAS-O.PHASE !          ( schedule owner item phase )
    DBAS-ACCEPTED = IF
        DBAS-IN-FLIGHT OVER DBAS-O.STATE !
        OVER DBAO-STORE DBAS-HEADER DBAS-H.STORE-ID
        3 PICK DBAS-S.RID 2 PICK DBAS-O.ID @ 3 PICK DBAS-O.KEY SDSP-KEY
    ELSE
        DBAS-DUE OVER DBAS-O.STATE !
        OVER _DBAO.OUTCOME @ OVER DBAS-O.OUTCOME !
        OVER _DBAO.REASON @ OVER DBAS-O.REASON !
        OVER _DBAO.PHASE @ IF OVER _DBAO.NOW @ OVER DBAS-O.ENDED ! THEN
    THEN
    NIP NIP DBAO-S-OK ;

\ Records this occurrence: merged into an item still awaiting review with
\ the same outcome, or a new item.  An accepted run is always new.
: _DBAO-RECORD  ( schedule owner -- status )
    DUP _DBAO.PHASE @ DBAS-ACCEPTED = IF 0 ELSE 2DUP _DBAO-PENDING THEN
    ?DUP IF
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

\ Sets how an Agent run's occurrence ends at once: OUTCOME for REASON.
: _DBAO-ENDS  ( outcome reason owner -- )
    TUCK _DBAO.REASON ! TUCK _DBAO.OUTCOME ! DBAS-ENDED SWAP _DBAO.PHASE ! ;

\ What a standing other than approved means for an on-time run.
: _DBAO-STANDING-REASON  ( standing -- reason )
    CASE
        SDSP-A-WITHDRAWN OF SACT-R-REVOKED ENDOF
        SDSP-A-CHANGED   OF SACT-R-CHANGED ENDOF
        SDSP-A-PRACTICE  OF SACT-R-PRACTICE ENDOF
        SDSP-A-NONE      OF SACT-R-NOT-APPROVED ENDOF
        >R SACT-R-AGENT-UNAVAILABLE R>
    ENDCASE ;

\ How an Agent run's occurrence goes.  A missed one never starts.  An
\ on-time one is accepted when its permission stands, Daybook holds it
\ approved, and no run of the schedule is in flight; otherwise it is
\ blocked.  A permission Desk no longer grants is cleared here too.
: _DBAO-DECIDE  ( schedule owner -- )
    DUP _DBAO.KIND @ DBAS-MISSED = IF
        NIP SACT-O-NOT-STARTED SACT-R-MISSED ROT _DBAO-ENDS EXIT
    THEN
    DUP _DBAO.STANDING @ SDSP-A-APPROVED <> IF
        DUP _DBAO.STANDING @ DUP SDSP-A-UNAVAILABLE <> IF
            2 PICK DBAS-S.RID 2 PICK _DBAO-DEAUTHORIZE
        THEN
        _DBAO-STANDING-REASON SACT-O-BLOCKED SWAP ROT _DBAO-ENDS DROP EXIT
    THEN
    OVER DBAS-S.RID OVER DBAO-ACTION DBAS-A.AUTHORIZED @ 0= IF
        NIP SACT-O-BLOCKED SACT-R-NOT-APPROVED ROT _DBAO-ENDS EXIT
    THEN
    OVER DBAS-S.RID OVER _DBAO-IN-FLIGHT? IF
        NIP SACT-O-BLOCKED SACT-R-OVERLAP ROT _DBAO-ENDS EXIT
    THEN
    NIP 0 OVER _DBAO.OUTCOME ! 0 OVER _DBAO.REASON !
    DBAS-ACCEPTED SWAP _DBAO.PHASE ! ;

\ Accepts the occurrences of the schedule ENTRY names that are due at NOW
\ (an entry DBAO-DUE-QUERY wrote), with BASIS the clock evidence
\ (DBAS-CONTINUOUS, DBAS-ACTIVATION or DBAS-JUMP) and, for an Agent run,
\ STANDING its permission's standing (SDSP-A-*).  Commits, and returns
\ the item it made or added to.  An ordinal accepted before answers
\ ACCEPTED with the schedule's latest item.
: DBAO-OCC-ACCEPT  ( entry basis standing now owner -- id status )
    >R R@ _DBAO.NOW ! R@ _DBAO.STANDING ! R@ _DBAO.BASIS !    ( entry ; R: owner )
    R@ _DBAO-READY ?DUP IF NIP 0 SWAP R> DROP EXIT THEN
    R@ _DBAO.NOW @ 0< IF DROP 0 DBAO-S-CLOCK R> DROP EXIT THEN
    R@ _DBAO.BASIS @ DBAS-CONTINUOUS DBAS-JUMP 1+ WITHIN 0= IF
        DROP 0 DBAO-S-INVALID R> DROP EXIT
    THEN
    DUP DBAO-E.RID OVER DBAO-E.REVISION @ R@ _DBAO-EDIT    ( entry schedule status )
    ?DUP IF NIP NIP 0 SWAP R> DROP EXIT THEN
    DUP DBAS-S.NEXT @ 0= 2 PICK DBAO-E.ORDINAL @ 2 PICK DBAS-S.NEXT @ < OR IF
        NIP DBAS-S.LAST @ DBAO-S-ACCEPTED R> DROP EXIT
    THEN
    OVER DBAO-E.ORDINAL @ OVER DBAS-S.NEXT @ <> IF
        2DROP 0 DBAO-S-CONFLICT R> DROP EXIT
    THEN
    NIP
    DUP _DBAO-LIVE? 0= IF DROP 0 DBAO-S-STATE R> DROP EXIT THEN
    DUP DBAS-S.NEXT-UTC @ R@ _DBAO.NOW @ 1000 / > IF
        DROP 0 DBAO-S-STATE R> DROP EXIT
    THEN
    DUP R@ _DBAO-ZONE! IF DROP 0 DBAO-S-INVALID R> DROP EXIT THEN
    DUP R@ _DBAO-LAST-DUE
    DUP DBAS-S.NEXT @ R@ _DBAO.K @ SWAP - 1+ R@ _DBAO.COUNT !
    R@ _DBAO.BASIS @ DBAS-CONTINUOUS = R@ _DBAO.COUNT @ 1 = AND
    IF DBAS-ON-TIME ELSE DBAS-MISSED THEN R@ _DBAO.KIND !
    0 R@ _DBAO.PHASE ! 0 R@ _DBAO.OUTCOME ! 0 R@ _DBAO.REASON !
    DUP DBAS-S.ACTION @ DBAS-ACTION-AGENT = IF DUP R@ _DBAO-DECIDE THEN
    DUP R@ _DBAO-RECORD ?DUP IF NIP 0 SWAP R> _DBAO-UNDO EXIT THEN
    R@ _DBAO-ADVANCE
    R@ _DBAO-COMMIT ?DUP IF 0 SWAP R> DROP EXIT THEN
    R> _DBAO.LAST @ DBAO-S-OK ;

\ Asks for an Agent run of the schedule RID names by hand: an accepted
\ occurrence with its dispatch key, which does not move the schedule's
\ next.  Only an enabled, visible, approved schedule with no run in flight
\ takes one.
: DBAO-RUN-NOW  ( rid revision now owner -- id status )
    >R R@ _DBAO.NOW !                          ( rid revision ; R: owner )
    R@ _DBAO-EDIT ?DUP IF NIP 0 SWAP R> DROP EXIT THEN
    R@ _DBAO.NOW @ 0< IF DROP 0 DBAO-S-CLOCK R> DROP EXIT THEN
    DUP DBAS-S.ACTION @ DBAS-ACTION-AGENT <> IF
        DROP 0 DBAO-S-MANUAL R> DROP EXIT
    THEN
    DUP _DBAO-LIVE? 0= IF DROP 0 DBAO-S-STATE R> DROP EXIT THEN
    DUP DBAS-S.RID R@ DBAO-ACTION DBAS-A.AUTHORIZED @ 0= IF
        DROP 0 DBAO-S-APPROVAL R> DROP EXIT
    THEN
    DUP DBAS-S.RID R@ _DBAO-IN-FLIGHT? IF DROP 0 DBAO-S-BUSY R> DROP EXIT THEN
    DBAS-MANUAL R@ _DBAO.KIND !  DBAS-USER R@ _DBAO.BASIS !
    1 R@ _DBAO.COUNT !  0 R@ _DBAO.K !  R@ _DBAO.NOW @ 1000 / R@ _DBAO.UTC !
    DBAS-ACCEPTED R@ _DBAO.PHASE !  0 R@ _DBAO.OUTCOME !  0 R@ _DBAO.REASON !
    DUP R@ _DBAO-RECORD ?DUP IF NIP 0 SWAP R> _DBAO-UNDO EXIT THEN
    DROP
    R@ _DBAO-COMMIT ?DUP IF 0 SWAP R> DROP EXIT THEN
    R> _DBAO.LAST @ DBAO-S-OK ;

\ =====================================================================
\  Runs in flight
\ =====================================================================

\ The run with dispatch KEY, or 0.
: _DBAO-KEYED  ( key owner -- item|0 )
    OVER RID-ZERO? IF 2DROP 0 EXIT THEN
    DBAO-STORE DBAS-FIND-KEYED ;

\ Records that the Agent started the run with dispatch KEY as RUN.  The
\ same report again changes nothing; another run is a conflict.
: DBAO-OCC-STARTED  ( key run now owner -- status )
    >R R@ _DBAO.NOW ! R@ _DBAO-READY ?DUP IF NIP NIP R> DROP EXIT THEN
    SWAP R@ _DBAO-KEYED ?DUP 0= IF DROP R> DROP DBAO-S-NOT-FOUND EXIT THEN
    OVER RID-ZERO? IF 2DROP R> DROP DBAO-S-INVALID EXIT THEN   ( run item )
    DUP DBAS-O.PHASE @ DBAS-ACCEPTED <> IF
        DBAS-O.RUN RID= IF DBAO-S-OK ELSE DBAO-S-CONFLICT THEN R> DROP EXIT
    THEN
    TUCK DBAS-O.RUN RID-SIZE MOVE
    DBAS-RUNNING OVER DBAS-O.PHASE !
    R@ _DBAO.NOW @ 0 MAX SWAP DBAS-O.STARTED !
    R> _DBAO-COMMIT ;

\ Whether the run ran, by RESPONSE or by what ITEM recorded; CONFLICT
\ when they name different runs.
: _DBAO-RAN?  ( response item -- ran? status )
    OVER SDSP-P.RUN RID-ZERO? IF NIP DBAS-O.RUN RID-ZERO? 0= DBAO-S-OK EXIT THEN
    DUP DBAS-O.RUN RID-ZERO? IF 2DROP -1 DBAO-S-OK EXIT THEN
    DBAS-O.RUN SWAP SDSP-P.RUN RID= IF -1 DBAO-S-OK ELSE 0 DBAO-S-CONFLICT THEN ;

\ Whether RESPONSE ends ITEM as it already ended.
: _DBAO-SAME-END?  ( response item -- flag )
    OVER SDSP-P.OUTCOME @ OVER DBAS-O.OUTCOME @ =
    2 PICK SDSP-P.REASON @ 2 PICK DBAS-O.REASON @ = AND NIP NIP ;

\ Records how the run with dispatch KEY ended, from Desk's RESPONSE: its
\ outcome and reason, its run RID when it ran, and a summary without its
\ content.  A run that completed needs no review; any other end does.
\ The same answer again changes nothing; another is a conflict.
: DBAO-OCC-FINISH  ( key response now owner -- status )
    >R R@ _DBAO.NOW ! R@ _DBAO.OUT !           ( key ; R: owner )
    R@ _DBAO-READY ?DUP IF NIP R> DROP EXIT THEN
    R@ _DBAO-KEYED ?DUP 0= IF R> DROP DBAO-S-NOT-FOUND EXIT THEN   ( item )
    DUP DBAS-O.PHASE @ DBAS-ENDED = IF
        R@ _DBAO.OUT @ SWAP _DBAO-SAME-END?
        IF DBAO-S-OK ELSE DBAO-S-CONFLICT THEN R> DROP EXIT
    THEN
    R@ _DBAO.OUT @ DUP SDSP-P.OUTCOME @ SWAP SDSP-P.REASON @ SACT-OUTCOME-OK?
    0= IF DROP R> DROP DBAO-S-INVALID EXIT THEN
    R@ _DBAO.OUT @ DUP SDSP-P.SUMMARY-U @ SWAP SDSP-P.CAPACITY @ > IF
        DROP R> DROP DBAO-S-INVALID EXIT
    THEN
    R@ _DBAO.OUT @ SDSP-SUMMARY$ SACT-LINE-OK? 0= IF
        DROP R> DROP DBAO-S-INVALID EXIT
    THEN
    \ A run that ran cannot have been blocked or not started; one that
    \ never ran cannot have completed, run out, or stopped for review.
    R@ _DBAO.OUT @ OVER _DBAO-RAN? ?DUP IF NIP NIP R> DROP EXIT THEN
    R@ _DBAO.OUT @ SDSP-P.OUTCOME @ SWAP IF
        DUP SACT-O-BLOCKED = SWAP SACT-O-NOT-STARTED = OR
    ELSE
        DUP SACT-O-COMPLETED = OVER SACT-O-EXPIRED = OR SWAP SACT-O-STOPPED = OR
    THEN
    IF DROP R> DROP DBAO-S-INVALID EXIT THEN
    R@ _DBAO.OUT @ SDSP-SUMMARY$ 2 PICK DBAS-O.SUMMARY DBAS-BLOB!
    ?DUP IF NIP R> _DBAO-UNDO EXIT THEN
    \ A run the Agent started keeps its RID.
    R@ _DBAO.OUT @ SDSP-P.RUN RID-ZERO? 0= IF
        R@ _DBAO.OUT @ SDSP-P.RUN OVER DBAS-O.RUN RID-SIZE MOVE
    THEN
    R@ _DBAO.OUT @ SDSP-P.OUTCOME @ OVER DBAS-O.OUTCOME !
    R@ _DBAO.OUT @ SDSP-P.REASON @ OVER DBAS-O.REASON !
    DBAS-ENDED OVER DBAS-O.PHASE !
    R@ _DBAO.NOW @ 0 MAX OVER DBAS-O.ENDED !
    DUP DBAS-O.OUTCOME @ SACT-O-COMPLETED = IF DBAS-CLEAR ELSE DBAS-DUE THEN
        OVER DBAS-O.STATE !
    \ Desk refusing the permission Daybook holds clears its approval; a
    \ refusal of one it no longer holds changes nothing.
    DUP DBAS-O.REASON @ _DBAO-REFUSAL? IF
        DUP DBAS-O.RID R@ DBAO-ACTION ?DUP IF
            R@ _DBAO.OUT @ SWAP _DBAO-HELD? IF
                DUP DBAS-O.RID R@ _DBAO-DEAUTHORIZE
            THEN
        THEN
    THEN
    DBAS-O.RID R@ _DBAO.RID RID-COPY
    R@ _DBAO.RID R@ _DBAO-PRUNE
    R> _DBAO-COMMIT ;
