\ =====================================================================
\  scheduled-dispatch.f - The portable scheduled-dispatch contract
\ =====================================================================
\  Daybook's runner hands an accepted occurrence to Desk's broker
\  through this contract, and asks it for approvals and the models it
\  may name.  Daybook sees only the client record Desk fills; Desk and
\  the Agent see only plain requests.  Neither side imports the other.
\
\  A request is a fixed header followed by three strings: the
\  schedule's title, its trigger (a summary of when it runs), and its operands
\  (scheduled-action.f).  It carries the schedule's identity and
\  revision, the occurrence and its dispatch key, the permission it
\  names, and the digests a permission binds.  It holds no Daybook or
\  Agent object, LBIND, live grant, handler pointer or callback, so it
\  can be copied byte for byte.
\
\  A dispatch key is SHA3-256 of a domain, the store's identity, the
\  schedule RID and the occurrence id: one key per occurrence, which the
\  Agent maps to exactly one run.
\ =====================================================================

PROVIDED akashic-sched-dispatch

REQUIRE scheduled-action.f

0  CONSTANT SDSP-S-OK
1  CONSTANT SDSP-S-INVALID
2  CONSTANT SDSP-S-UNAVAILABLE   \ no broker, or it cannot answer now
3  CONSTANT SDSP-S-STARTED       \ the run started
4  CONSTANT SDSP-S-WAITING       \ accepted; waits for the Agent
5  CONSTANT SDSP-S-ENDED         \ finished; the response says how
6  CONSTANT SDSP-S-RUNNING
7  CONSTANT SDSP-S-UNKNOWN       \ the broker and the Agent know no such key
8  CONSTANT SDSP-S-PENDING       \ an approval awaits the user
9  CONSTANT SDSP-S-ALLOWED
10 CONSTANT SDSP-S-REFUSED
11 CONSTANT SDSP-S-GONE          \ the approval was withdrawn unanswered
12 CONSTANT SDSP-S-SMALL         \ a buffer is too small

\ How a request stands against the permissions.
1 CONSTANT SDSP-A-APPROVED
2 CONSTANT SDSP-A-NONE
3 CONSTANT SDSP-A-WITHDRAWN
4 CONSTANT SDSP-A-CHANGED
5 CONSTANT SDSP-A-PRACTICE
6 CONSTANT SDSP-A-UNAVAILABLE

\ Occurrence kinds, as Daybook records them.
1 CONSTANT SDSP-K-ON-TIME
2 CONSTANT SDSP-K-MISSED
3 CONSTANT SDSP-K-MANUAL         \ Run Now

\ =====================================================================
\  Requests
\ =====================================================================

288 CONSTANT SDSP-REQUEST-HEAD
: SDSP-R.ACTION      ( request -- a ) ;
: SDSP-R.SCHEMA      ( request -- a ) 8 + ;
: SDSP-R.PRACTICE    ( request -- rid ) 16 + ;
: SDSP-R.STORE       ( request -- id ) 48 + ;
: SDSP-R.SCHEDULE    ( request -- rid ) 80 + ;
: SDSP-R.REVISION    ( request -- a ) 112 + ;
: SDSP-R.OCCURRENCE  ( request -- a ) 120 + ;
: SDSP-R.KEY         ( request -- key ) 128 + ;
: SDSP-R.PERMISSION  ( request -- rid ) 160 + ;
: SDSP-R.PERMISSION-REVISION ( request -- a ) 192 + ;
: SDSP-R.OPERANDS-DIGEST ( request -- digest ) 200 + ;
: SDSP-R.TRIGGER-DIGEST  ( request -- digest ) 232 + ;
: SDSP-R.KIND        ( request -- a ) 264 + ;
: SDSP-R.TAIL-U      ( request -- a ) 272 + ;
: SDSP-R.SIZE        ( request -- a ) 280 + ;   \ the bytes it was sized for
: _SDSP-R.TAIL       ( request -- field ) SDSP-REQUEST-HEAD + ;

\ The bytes a request with strings of these lengths takes.
: SDSP-REQUEST-SIZE  ( title-u trigger-u operands-u -- bytes )
    SACT-STR-U SWAP SACT-STR-U + SWAP SACT-STR-U + SDSP-REQUEST-HEAD + ;

\ Zeroes BYTES of request, records its size, and readies its tail for the
\ three strings.
: SDSP-REQUEST-INIT  ( bytes request -- )
    2DUP SWAP 0 FILL SDSP-R.SIZE ! ;

\ Appends a string to the tail: the title, then the trigger (a summary of
\ when it runs), then the operands.  The request was sized for them.
: SDSP-TAIL+  ( address u request -- )
    DUP >R _SDSP-R.TAIL R@ SDSP-R.TAIL-U @ +   ( address u at )
    SACT-STR! R@ _SDSP-R.TAIL -                 ( tail-u )
    R> SDSP-R.TAIL-U ! ;

: SDSP-TITLE$  ( request -- address u ) _SDSP-R.TAIL SACT-STR$ ;
: SDSP-TRIGGER$  ( request -- address u ) _SDSP-R.TAIL SACT-STR-NEXT SACT-STR$ ;
: SDSP-OPERANDS$  ( request -- address u )
    _SDSP-R.TAIL SACT-STR-NEXT SACT-STR-NEXT SACT-STR$ ;

\ The request's whole size.
: SDSP-REQUEST-U  ( request -- bytes ) SDSP-R.TAIL-U @ SDSP-REQUEST-HEAD + ;

\ ---------------------------------------------------------------------
\  Dispatch keys
\ ---------------------------------------------------------------------

CREATE _SDSP-ID 8 ALLOT

\ The dispatch key of occurrence ID of schedule RID in the store with
\ identity STORE.
: SDSP-KEY  ( store rid id dest -- )
    >R _SDSP-ID !
    SHA3-256-BEGIN
    S" akashic.daybook.dispatch.v1" SHA3-256-ADD
    SWAP 32 SHA3-256-ADD 32 SHA3-256-ADD
    _SDSP-ID 8 SHA3-256-ADD
    R> SHA3-256-END ;

\ ---------------------------------------------------------------------
\  Checking a request
\ ---------------------------------------------------------------------

CREATE _SDSP-DIGEST 32 ALLOT

: _SDSP-ZERO32?  ( address -- flag )
    0 32 0 DO OVER I + C@ OR LOOP NIP 0= ;

\ Whether the tail holds exactly the three strings, the first two of
\ them one line of text.
: _SDSP-TAIL-OK?  ( request -- flag )
    DUP SDSP-R.TAIL-U @ DUP 0< IF 2DROP 0 EXIT THEN
    OVER _SDSP-R.TAIL + SWAP _SDSP-R.TAIL       ( end field )
    DUP 2 PICK _SACT-STR-FITS? 0= IF 2DROP 0 EXIT THEN
    DUP SACT-STR$ DUP 0= -ROT SACT-LINE-OK? 0= OR IF 2DROP 0 EXIT THEN
    SACT-STR-NEXT
    DUP 2 PICK _SACT-STR-FITS? 0= IF 2DROP 0 EXIT THEN
    DUP SACT-STR$ SACT-LINE-OK? 0= IF 2DROP 0 EXIT THEN
    SACT-STR-NEXT
    DUP 2 PICK _SACT-STR-FITS? 0= IF 2DROP 0 EXIT THEN
    SACT-STR-NEXT = ;

\ The status of REQUEST.  An OCCURRENCE? request hands over an accepted
\ occurrence: it names the Practice that approved it, and the kind, id and
\ dispatch key of the occurrence, which must be that occurrence's.  Any
\ other request (an approval, a standing check) names no occurrence and
\ may leave the Practice for Desk to supply.  Only automatic actions are
\ dispatched or approved.
: SDSP-REQUEST-OK?  ( request occurrence? -- status )
    >R
    DUP SDSP-R.SIZE @ OVER SDSP-R.TAIL-U @ SDSP-REQUEST-HEAD + <> IF
        DROP R> DROP SDSP-S-INVALID EXIT
    THEN
    DUP SDSP-R.ACTION @ OVER SDSP-R.SCHEMA @ SACT-CLASS SACT-AUTOMATIC <> IF
        DROP R> DROP SDSP-S-INVALID EXIT
    THEN
    DUP SDSP-R.STORE _SDSP-ZERO32?
    OVER SDSP-R.SCHEDULE _SDSP-ZERO32? OR
    OVER SDSP-R.REVISION @ 1 < OR IF DROP R> DROP SDSP-S-INVALID EXIT THEN
    DUP _SDSP-TAIL-OK? 0= IF DROP R> DROP SDSP-S-INVALID EXIT THEN
    DUP SDSP-R.ACTION @ OVER SDSP-R.SCHEMA @ 2 PICK SDSP-OPERANDS$
    SACT-OPERANDS-OK? IF DROP R> DROP SDSP-S-INVALID EXIT THEN
    DUP SDSP-R.ACTION @ OVER SDSP-R.SCHEMA @ 2 PICK SDSP-OPERANDS$
    _SDSP-DIGEST SACT-DIGEST
    _SDSP-DIGEST 32 2 PICK SDSP-R.OPERANDS-DIGEST 32 COMPARE IF
        DROP R> DROP SDSP-S-INVALID EXIT
    THEN
    R> IF
        DUP SDSP-R.PRACTICE _SDSP-ZERO32? IF DROP SDSP-S-INVALID EXIT THEN
        DUP SDSP-R.KIND @ SDSP-K-ON-TIME SDSP-K-MANUAL 1+ WITHIN 0=
        OVER SDSP-R.OCCURRENCE @ 1 < OR IF DROP SDSP-S-INVALID EXIT THEN
        DUP SDSP-R.STORE OVER SDSP-R.SCHEDULE 2 PICK SDSP-R.OCCURRENCE @
        _SDSP-DIGEST SDSP-KEY
        _SDSP-DIGEST 32 ROT SDSP-R.KEY 32 COMPARE
        IF SDSP-S-INVALID ELSE SDSP-S-OK THEN EXIT
    THEN
    DUP SDSP-R.KIND @ OVER SDSP-R.OCCURRENCE @ OR IF DROP SDSP-S-INVALID EXIT THEN
    SDSP-R.KEY _SDSP-ZERO32? IF SDSP-S-OK ELSE SDSP-S-INVALID THEN ;

\ =====================================================================
\  Responses
\ =====================================================================
\  The broker fills a response the caller sized; the summary, which
\  never holds run content, takes up to the capacity the caller set.

136 CONSTANT SDSP-RESPONSE-HEAD
: SDSP-P.OUTCOME     ( response -- a ) ;
: SDSP-P.REASON      ( response -- a ) 8 + ;
: SDSP-P.RUN         ( response -- rid ) 16 + ;
: SDSP-P.PERMISSION  ( response -- rid ) 48 + ;
: SDSP-P.PERMISSION-REVISION ( response -- a ) 80 + ;
: SDSP-P.PRACTICE    ( response -- rid ) 88 + ;
: SDSP-P.CAPACITY    ( response -- a ) 120 + ;
: SDSP-P.SUMMARY-U   ( response -- a ) 128 + ;
: SDSP-P.SUMMARY     ( response -- a ) SDSP-RESPONSE-HEAD + ;

: SDSP-RESPONSE-SIZE  ( capacity -- bytes ) 7 + -8 AND SDSP-RESPONSE-HEAD + ;

\ Clears a response for a summary of up to CAPACITY bytes.
: SDSP-RESPONSE-INIT  ( capacity response -- )
    2DUP SWAP SDSP-RESPONSE-SIZE 0 FILL SDSP-P.CAPACITY ! ;

: SDSP-SUMMARY$  ( response -- address u )
    DUP SDSP-P.SUMMARY SWAP SDSP-P.SUMMARY-U @ ;

\ Sets the summary.  One longer than the capacity records its length and
\ answers SMALL, so the caller can ask again with room for it.
: SDSP-SUMMARY!  ( address u response -- status )
    2DUP SDSP-P.SUMMARY-U !
    2DUP SDSP-P.CAPACITY @ > IF DROP 2DROP SDSP-S-SMALL EXIT THEN
    SDSP-P.SUMMARY SWAP MOVE SDSP-S-OK ;

\ =====================================================================
\  The client
\ =====================================================================
\  Desk fills a client record and gives it to Daybook's service.  Each
\  word answers UNAVAILABLE when the client is missing or not filled.
\
\    submit  ( request response context -- status )
\    status  ( key response context -- status )
\    cancel  ( key context -- status )
\    ask     ( request context -- ask-id status )
\    asked   ( ask-id response context -- status )
\    check   ( request context -- standing status )
\    models  ( buffer capacity context -- bytes status )
\    describe ( locator facts context -- status )

0x3154504F43505344 CONSTANT _SDSP-MAGIC   \ "DSPCOPT1"

  0 CONSTANT _SDSP-C-MAGIC
  8 CONSTANT _SDSP-C-SELF
 16 CONSTANT _SDSP-C-CONTEXT
 24 CONSTANT _SDSP-C-SUBMIT
 32 CONSTANT _SDSP-C-STATUS
 40 CONSTANT _SDSP-C-CANCEL
 48 CONSTANT _SDSP-C-ASK
 56 CONSTANT _SDSP-C-ASKED
 64 CONSTANT _SDSP-C-CHECK
 72 CONSTANT _SDSP-C-MODELS
 80 CONSTANT _SDSP-C-DESCRIBE
 88 CONSTANT SDSP-CLIENT-SIZE

: SDSP-C.SUBMIT-XT  ( client -- a ) _SDSP-C-SUBMIT + ;
: SDSP-C.STATUS-XT  ( client -- a ) _SDSP-C-STATUS + ;
: SDSP-C.CANCEL-XT  ( client -- a ) _SDSP-C-CANCEL + ;
: SDSP-C.ASK-XT     ( client -- a ) _SDSP-C-ASK + ;
: SDSP-C.ASKED-XT   ( client -- a ) _SDSP-C-ASKED + ;
: SDSP-C.CHECK-XT   ( client -- a ) _SDSP-C-CHECK + ;
: SDSP-C.MODELS-XT  ( client -- a ) _SDSP-C-MODELS + ;
: SDSP-C.DESCRIBE-XT  ( client -- a ) _SDSP-C-DESCRIBE + ;

\ A client for CONTEXT with no words yet.
: SDSP-CLIENT-INIT  ( context client -- )
    DUP SDSP-CLIENT-SIZE 0 FILL
    _SDSP-MAGIC OVER _SDSP-C-MAGIC + !
    DUP DUP _SDSP-C-SELF + !
    _SDSP-C-CONTEXT + ! ;

: SDSP-CLIENT-VALID?  ( client -- flag )
    DUP 0= IF EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _SDSP-C-MAGIC + @ _SDSP-MAGIC <> IF DROP 0 EXIT THEN
    DUP _SDSP-C-SELF + @ = ;

\ The word at SLOT of CLIENT and its context, or 0 when there is none.
: _SDSP-WORD  ( client slot -- context xt | 0 )
    OVER SDSP-CLIENT-VALID? 0= IF 2DROP 0 EXIT THEN
    OVER + @ DUP 0= IF NIP EXIT THEN
    SWAP _SDSP-C-CONTEXT + @ SWAP ;

: SDSP-SUBMIT  ( request response client -- status )
    _SDSP-C-SUBMIT _SDSP-WORD ?DUP IF EXECUTE EXIT THEN
    2DROP SDSP-S-UNAVAILABLE ;

: SDSP-STATUS  ( key response client -- status )
    _SDSP-C-STATUS _SDSP-WORD ?DUP IF EXECUTE EXIT THEN
    2DROP SDSP-S-UNAVAILABLE ;

: SDSP-CANCEL  ( key client -- status )
    _SDSP-C-CANCEL _SDSP-WORD ?DUP IF EXECUTE EXIT THEN
    DROP SDSP-S-UNAVAILABLE ;

: SDSP-ASK  ( request client -- ask-id status )
    _SDSP-C-ASK _SDSP-WORD ?DUP IF EXECUTE EXIT THEN
    DROP 0 SDSP-S-UNAVAILABLE ;

: SDSP-ASKED  ( ask-id response client -- status )
    _SDSP-C-ASKED _SDSP-WORD ?DUP IF EXECUTE EXIT THEN
    2DROP SDSP-S-UNAVAILABLE ;

: SDSP-CHECK  ( request client -- standing status )
    _SDSP-C-CHECK _SDSP-WORD ?DUP IF EXECUTE EXIT THEN
    DROP SDSP-A-UNAVAILABLE SDSP-S-UNAVAILABLE ;

: SDSP-MODELS  ( buffer capacity client -- bytes status )
    _SDSP-C-MODELS _SDSP-WORD ?DUP IF EXECUTE EXIT THEN
    2DROP 0 SDSP-S-UNAVAILABLE ;

\ ---------------------------------------------------------------------
\  What a document's owner says of it
\ ---------------------------------------------------------------------
\  DESCRIBE asks the owner of the document a locator names what it is
\  now: its title, into the caller's buffer, its current revision, and
\  its size.  A title longer than the buffer answers SMALL with its
\  length, and UNAVAILABLE says the owner could not be asked or does not
\  have the document.

 0 CONSTANT _SDSP-F-TITLE-A
 8 CONSTANT _SDSP-F-TITLE-CAP
16 CONSTANT _SDSP-F-TITLE-U
24 CONSTANT _SDSP-F-REVISION
32 CONSTANT _SDSP-F-SIZE
40 CONSTANT SDSP-FACTS-SIZE

: SDSP-F.TITLE-U   ( facts -- a ) _SDSP-F-TITLE-U + ;
: SDSP-F.REVISION  ( facts -- a ) _SDSP-F-REVISION + ;
: SDSP-F.SIZE      ( facts -- a ) _SDSP-F-SIZE + ;

\ Facts with a title buffer of CAP bytes at ADDRESS, and nothing known.
: SDSP-FACTS-INIT  ( address cap facts -- )
    DUP SDSP-FACTS-SIZE 0 FILL
    TUCK _SDSP-F-TITLE-CAP + ! _SDSP-F-TITLE-A + ! ;

\ The title, as far as the buffer holds it.
: SDSP-FACTS-TITLE$  ( facts -- address length )
    DUP _SDSP-F-TITLE-A + @ SWAP
    DUP SDSP-F.TITLE-U @ SWAP _SDSP-F-TITLE-CAP + @ MIN ;

\ Keeps the U bytes of title at ADDRESS: SMALL when they do not fit.
: SDSP-FACTS-TITLE!  ( address u facts -- status )
    2DUP SDSP-F.TITLE-U !
    2DUP _SDSP-F-TITLE-CAP + @ > IF DROP 2DROP SDSP-S-SMALL EXIT THEN
    _SDSP-F-TITLE-A + @ SWAP MOVE SDSP-S-OK ;

: SDSP-DESCRIBE  ( locator facts client -- status )
    _SDSP-C-DESCRIBE _SDSP-WORD ?DUP IF EXECUTE EXIT THEN
    2DROP SDSP-S-UNAVAILABLE ;

\ =====================================================================
\  Model lists
\ =====================================================================
\  The broker answers MODELS with the Agent's provider and the models it
\  can run, for a schedule to name one:
\
\    count, provider id string,
\    then per model: id string, label string, flags,
\                    effort count, then id and label strings per effort,
\                    tier count, then id and label strings per tier
\
\  A list is checked whole before it is read, so reading stays inside it.

1 CONSTANT SDSP-M-VERBOSITY     \ the model takes a verbosity

: SDSP-LIST-COUNT  ( list -- n ) @ ;
: SDSP-LIST-PROVIDER$  ( list -- address u ) 8 + SACT-STR$ ;
: SDSP-LIST-FIRST  ( list -- model ) 8 + SACT-STR-NEXT ;

: SDSP-MODEL-ID$  ( model -- address u ) SACT-STR$ ;
: SDSP-MODEL-LABEL$  ( model -- address u ) SACT-STR-NEXT SACT-STR$ ;
: SDSP-MODEL-FLAGS  ( model -- flags ) SACT-STR-NEXT SACT-STR-NEXT @ ;
\ A model's efforts: how many, and the first.
: SDSP-MODEL-EFFORTS  ( model -- n choice )
    SACT-STR-NEXT SACT-STR-NEXT 8 + DUP @ SWAP 8 + ;
: SDSP-CHOICE-ID$  ( choice -- address u ) SACT-STR$ ;
: SDSP-CHOICE-LABEL$  ( choice -- address u ) SACT-STR-NEXT SACT-STR$ ;
: SDSP-CHOICE-NEXT  ( choice -- choice' ) SACT-STR-NEXT SACT-STR-NEXT ;
\ Skips N choices.
: _SDSP-CHOICES  ( n choice -- after )
    SWAP 0 ?DO SDSP-CHOICE-NEXT LOOP ;
: SDSP-MODEL-TIERS  ( model -- n choice )
    SDSP-MODEL-EFFORTS _SDSP-CHOICES DUP @ SWAP 8 + ;
: SDSP-MODEL-NEXT  ( model -- model' ) SDSP-MODEL-TIERS _SDSP-CHOICES ;

\ Writes a cell at AT; the address after it.
: SDSP-PUT  ( x at -- at' ) TUCK ! 8 + ;

\ Whether the cell at AT lies before END.
: _SDSP-CELL-FITS?  ( at end -- flag ) SWAP 8 + SWAP > 0= ;

\ Whether N choices at CHOICE fit before END as text; the address after
\ them, or 0.
: _SDSP-CHOICES-OK  ( n choice end -- after|0 )
    ROT 0 ?DO                                ( choice end )
        OVER OVER _SACT-STR-FITS? 0= IF 2DROP 0 UNLOOP EXIT THEN
        OVER SACT-STR$ DUP 0= -ROT SACT-LINE-OK? 0= OR IF
            2DROP 0 UNLOOP EXIT
        THEN
        SWAP SACT-STR-NEXT SWAP
        OVER OVER _SACT-STR-FITS? 0= IF 2DROP 0 UNLOOP EXIT THEN
        OVER SACT-STR$ SACT-LINE-OK? 0= IF 2DROP 0 UNLOOP EXIT THEN
        SWAP SACT-STR-NEXT SWAP
    LOOP
    DROP ;

\ Whether one model at MODEL fits before END; the address after it, or 0.
: _SDSP-MODEL-OK  ( model end -- after|0 )
    OVER OVER _SACT-STR-FITS? 0= IF 2DROP 0 EXIT THEN
    OVER SACT-STR$ DUP 0= -ROT SACT-LINE-OK? 0= OR IF 2DROP 0 EXIT THEN
    SWAP SACT-STR-NEXT SWAP
    OVER OVER _SACT-STR-FITS? 0= IF 2DROP 0 EXIT THEN
    OVER SACT-STR$ SACT-LINE-OK? 0= IF 2DROP 0 EXIT THEN
    SWAP SACT-STR-NEXT SWAP                   ( flags-at end )
    OVER 8 + OVER _SDSP-CELL-FITS? 0= IF 2DROP 0 EXIT THEN
    SWAP 8 + SWAP                             ( efforts-at end )
    OVER OVER _SDSP-CELL-FITS? 0= IF 2DROP 0 EXIT THEN
    OVER @ ROT 8 + ROT                        ( n choice end )
    DUP >R _SDSP-CHOICES-OK R>                ( after|0 end )
    OVER 0= IF DROP EXIT THEN
    OVER OVER _SDSP-CELL-FITS? 0= IF 2DROP 0 EXIT THEN
    OVER @ ROT 8 + ROT _SDSP-CHOICES-OK ;

\ Whether U bytes at LIST are a model list, read wholly inside them.
: SDSP-LIST-OK?  ( list u -- flag )
    OVER + >R
    DUP R@ _SDSP-CELL-FITS? 0= IF DROP R> DROP 0 EXIT THEN
    DUP @ 0< IF DROP R> DROP 0 EXIT THEN
    DUP 8 + R@ _SACT-STR-FITS? 0= IF DROP R> DROP 0 EXIT THEN
    DUP 8 + SACT-STR$ DUP 0= -ROT SACT-LINE-OK? 0= OR IF
        DROP R> DROP 0 EXIT
    THEN
    DUP @ SWAP SDSP-LIST-FIRST                ( n model )
    BEGIN OVER WHILE
        R@ _SDSP-MODEL-OK DUP 0= IF NIP R> DROP EXIT THEN
        SWAP 1- SWAP
    REPEAT
    NIP R> = ;
