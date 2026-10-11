\ =====================================================================
\  scheduled-action.f - The closed catalog of scheduled actions
\ =====================================================================
\  A schedule names one action from this catalog and carries its
\  operands as canonical bytes.  The catalog is closed: each action has
\  one schema, a class, and an exact operand layout.
\
\    daybook.reminder   manual review: a due item for review; runs nothing
\    agent.run.request  automatic: one bounded Agent run, which Desk's
\                       broker starts under a schedule permission
\
\  An Agent run's operands are variable length.  Every field is a cell
\  or a string: a cell holding its length, then its bytes, zero-padded
\  to a cell.  The fields come in a fixed order, so one request has one
\  encoding and one digest.  They hold the run's limits, the model it
\  must use, an optional exact context locator, and the prompt.  They
\  never hold a live grant, an LBIND, a component pointer or an XT.
\
\  The module also owns the closed vocabulary of outcomes and reasons
\  that Daybook, Desk and the Agent report with, and which pairs are
\  valid.
\ =====================================================================

PROVIDED akashic-sched-action

REQUIRE qualified-locator.f
REQUIRE ../math/sha3.f
REQUIRE ../text/utf8.f

\ =====================================================================
\  The catalog
\ =====================================================================

0 CONSTANT SACT-S-OK
1 CONSTANT SACT-S-ACTION     \ not in the catalog
2 CONSTANT SACT-S-SCHEMA     \ not the action's schema
3 CONSTANT SACT-S-SHAPE      \ lengths, padding or flags break the layout
4 CONSTANT SACT-S-BUDGET     \ a limit is not positive, or below the prompt
5 CONSTANT SACT-S-MODEL      \ a missing or malformed model designation
6 CONSTANT SACT-S-PROMPT     \ an empty prompt, or one that is not text
7 CONSTANT SACT-S-CONTEXT    \ context the catalog does not take yet
8 CONSTANT SACT-S-SMALL      \ the destination is too small

1 CONSTANT SACT-REMINDER
2 CONSTANT SACT-AGENT-RUN

1 CONSTANT SACT-MANUAL       \ a due item for review; never dispatched
2 CONSTANT SACT-AUTOMATIC    \ dispatched through Desk's broker

1 CONSTANT SACT-SCHEMA       \ every action's current schema

: _SACT-KNOWN?  ( action -- flag )
    DUP SACT-REMINDER = SWAP SACT-AGENT-RUN = OR ;

\ The class of ACTION at SCHEMA, or 0 when the catalog lacks it.
: SACT-CLASS  ( action schema -- class|0 )
    SACT-SCHEMA <> IF DROP 0 EXIT THEN
    DUP SACT-REMINDER = IF DROP SACT-MANUAL EXIT THEN
    SACT-AGENT-RUN = IF SACT-AUTOMATIC ELSE 0 THEN ;

: SACT-NAME$  ( action -- address length )
    DUP SACT-REMINDER = IF DROP S" daybook.reminder" EXIT THEN
    SACT-AGENT-RUN = IF S" agent.run.request" ELSE 0 0 THEN ;

\ =====================================================================
\  Strings
\ =====================================================================

: _SACT-PAD  ( u -- u' ) 7 + -8 AND ;

\ The bytes a string field of U bytes of text takes.
: SACT-STR-U  ( u -- bytes ) _SACT-PAD 8 + ;
: SACT-STR$  ( field -- address length ) DUP 8 + SWAP @ ;
: SACT-STR-NEXT  ( field -- next ) DUP @ SACT-STR-U + ;

\ Writes a string field at AT, whose padding the caller has zeroed; the
\ address after it.
: SACT-STR!  ( address length at -- at' )
    2DUP !
    DUP >R 8 + SWAP
    DUP >R MOVE
    R> SACT-STR-U R> + ;

: _SACT-ZERO?  ( address u -- flag )
    0 ?DO DUP I + C@ IF DROP 0 UNLOOP EXIT THEN LOOP DROP -1 ;

\ Whether the string field at FIELD lies wholly before END and its
\ padding is zero.
: _SACT-STR-FITS?  ( field end -- flag )
    OVER - 8 -                               ( field room )
    DUP 0< IF 2DROP 0 EXIT THEN
    OVER @                                   ( field room u )
    2DUP U< IF DROP 2DROP 0 EXIT THEN
    _SACT-PAD U< IF DROP 0 EXIT THEN         ( field )
    DUP @ DUP _SACT-PAD SWAP -               ( field npad )
    SWAP DUP @ + 8 + SWAP
    _SACT-ZERO? ;

\ Whether U bytes at ADDRESS are UTF-8 with no control character except
\ those ALLOWED names, as a mask of bits for codes below 32.  DEL is never
\ allowed.
: _SACT-TEXT?  ( address u allowed -- flag )
    -ROT 2DUP UTF8-VALID? 0= IF 2DROP DROP 0 EXIT THEN
    0 ?DO                                    ( allowed address )
        DUP I + C@
        DUP 127 = IF 2DROP DROP 0 UNLOOP EXIT THEN
        DUP 32 < IF
            1 SWAP LSHIFT 2 PICK AND 0= IF 2DROP 0 UNLOOP EXIT THEN
        ELSE DROP THEN
    LOOP
    2DROP -1 ;

\ Prompts may hold tabs and line feeds.
1536 CONSTANT _SACT-PROMPT-CONTROLS

\ Whether a field's text has no control character outside ALLOWED, and
\ at least one byte when NONEMPTY? is true.  The field fits.
: _SACT-TEXT-FIELD?  ( field allowed nonempty? -- flag )
    >R SWAP SACT-STR$ ROT
    R> IF OVER 0= IF 2DROP DROP 0 EXIT THEN THEN
    _SACT-TEXT? ;

\ Single-line display text: titles, trigger summaries, outcome summaries.
: SACT-LINE-OK?  ( address length -- flag ) 0 _SACT-TEXT? ;

\ =====================================================================
\  An Agent run's operands
\ =====================================================================

1 CONSTANT SACT-F-CONTEXT    \ the operands carry one exact context locator

\ The Agent's ARVERB- values: AUTO 0, LOW 1, MEDIUM 2, HIGH 3.
3 CONSTANT SACT-VERBOSITY-MAX

56 CONSTANT SACT-AGENT-HEAD
: SACT-O.SCHEMA      ( operands -- a ) ;
: SACT-O.FLAGS       ( operands -- a ) 8 + ;
: SACT-O.EFFECTS     ( operands -- a ) 16 + ;
: SACT-O.TIME        ( operands -- a ) 24 + ;       \ ms the run may take
: SACT-O.DISCLOSURE  ( operands -- a ) 32 + ;       \ bytes sent to the model
: SACT-O.OUTPUT      ( operands -- a ) 40 + ;       \ bytes of reply kept
: SACT-O.VERBOSITY   ( operands -- a ) 48 + ;
: SACT-O.PROVIDER    ( operands -- field ) SACT-AGENT-HEAD + ;
: SACT-O.MODEL       ( operands -- field ) SACT-O.PROVIDER SACT-STR-NEXT ;
: SACT-O.EFFORT      ( operands -- field ) SACT-O.MODEL SACT-STR-NEXT ;
: SACT-O.TIER        ( operands -- field ) SACT-O.EFFORT SACT-STR-NEXT ;

\ The context locator, or 0 when the run has none.
: SACT-O.CONTEXT  ( operands -- locator|0 )
    DUP SACT-O.FLAGS @ SACT-F-CONTEXT AND
    IF SACT-O.TIER SACT-STR-NEXT ELSE DROP 0 THEN ;

: SACT-O.PROMPT  ( operands -- field )
    DUP SACT-O.TIER SACT-STR-NEXT
    SWAP SACT-O.FLAGS @ SACT-F-CONTEXT AND IF QLOC-SIZE + THEN ;

: SACT-PROVIDER$  ( operands -- address length ) SACT-O.PROVIDER SACT-STR$ ;
: SACT-MODEL$     ( operands -- address length ) SACT-O.MODEL SACT-STR$ ;
: SACT-EFFORT$    ( operands -- address length ) SACT-O.EFFORT SACT-STR$ ;
: SACT-TIER$      ( operands -- address length ) SACT-O.TIER SACT-STR$ ;
: SACT-PROMPT$    ( operands -- address length ) SACT-O.PROMPT SACT-STR$ ;

: _SACT-BUDGET-OK?  ( operands -- flag )
    DUP SACT-O.TIME @ 0>
    OVER SACT-O.DISCLOSURE @ 0> AND
    SWAP SACT-O.OUTPUT @ 0> AND ;

\ The status of an Agent run's U bytes of operands.  A context locator is
\ refused until the catalog takes one.
: _SACT-AGENT-OK?  ( operands u -- status )
    DUP SACT-AGENT-HEAD < IF 2DROP SACT-S-SHAPE EXIT THEN
    OVER + SWAP                              ( end operands )
    DUP SACT-O.SCHEMA @ SACT-SCHEMA <> IF 2DROP SACT-S-SCHEMA EXIT THEN
    DUP SACT-O.FLAGS @ SACT-F-CONTEXT INVERT AND IF
        2DROP SACT-S-SHAPE EXIT
    THEN
    DUP SACT-O.FLAGS @ IF 2DROP SACT-S-CONTEXT EXIT THEN
    DUP SACT-O.EFFECTS @ IF 2DROP SACT-S-CONTEXT EXIT THEN
    DUP _SACT-BUDGET-OK? 0= IF 2DROP SACT-S-BUDGET EXIT THEN
    DUP SACT-O.VERBOSITY @ 0 SACT-VERBOSITY-MAX 1+ WITHIN 0= IF
        2DROP SACT-S-MODEL EXIT
    THEN
    DUP SACT-O.PROVIDER 2 PICK _SACT-STR-FITS? 0= IF 2DROP SACT-S-SHAPE EXIT THEN
    DUP SACT-O.PROVIDER 0 -1 _SACT-TEXT-FIELD? 0= IF 2DROP SACT-S-MODEL EXIT THEN
    DUP SACT-O.MODEL 2 PICK _SACT-STR-FITS? 0= IF 2DROP SACT-S-SHAPE EXIT THEN
    DUP SACT-O.MODEL 0 -1 _SACT-TEXT-FIELD? 0= IF 2DROP SACT-S-MODEL EXIT THEN
    DUP SACT-O.EFFORT 2 PICK _SACT-STR-FITS? 0= IF 2DROP SACT-S-SHAPE EXIT THEN
    DUP SACT-O.EFFORT 0 0 _SACT-TEXT-FIELD? 0= IF 2DROP SACT-S-MODEL EXIT THEN
    DUP SACT-O.TIER 2 PICK _SACT-STR-FITS? 0= IF 2DROP SACT-S-SHAPE EXIT THEN
    DUP SACT-O.TIER 0 0 _SACT-TEXT-FIELD? 0= IF 2DROP SACT-S-MODEL EXIT THEN
    DUP SACT-O.PROMPT 2 PICK _SACT-STR-FITS? 0= IF 2DROP SACT-S-SHAPE EXIT THEN
    DUP SACT-O.PROMPT _SACT-PROMPT-CONTROLS -1 _SACT-TEXT-FIELD? 0= IF
        2DROP SACT-S-PROMPT EXIT
    THEN
    \ The prompt itself is disclosed, so the limit must cover it.
    DUP SACT-O.PROMPT @ OVER SACT-O.DISCLOSURE @ > IF
        2DROP SACT-S-BUDGET EXIT
    THEN
    SACT-O.PROMPT SACT-STR-NEXT = IF SACT-S-OK ELSE SACT-S-SHAPE THEN ;

\ The status of U bytes of OPERANDS for ACTION at SCHEMA.  A reminder
\ takes none.
: SACT-OPERANDS-OK?  ( action schema operands u -- status )
    3 PICK _SACT-KNOWN? 0= IF 2DROP 2DROP SACT-S-ACTION EXIT THEN
    2 PICK SACT-SCHEMA <> IF 2DROP 2DROP SACT-S-SCHEMA EXIT THEN
    ROT DROP ROT                             ( operands u action )
    SACT-REMINDER = IF NIP IF SACT-S-SHAPE ELSE SACT-S-OK THEN EXIT THEN
    _SACT-AGENT-OK? ;

\ ---------------------------------------------------------------------
\  Building operands
\ ---------------------------------------------------------------------
\  A draft names the parts by address and length; encoding writes the
\  canonical bytes.  The draft is activation-local and never stored.

  0 CONSTANT _SACT-D-EFFECTS
  8 CONSTANT _SACT-D-TIME
 16 CONSTANT _SACT-D-DISCLOSURE
 24 CONSTANT _SACT-D-OUTPUT
 32 CONSTANT _SACT-D-VERBOSITY
 40 CONSTANT _SACT-D-PROVIDER         \ address, length
 56 CONSTANT _SACT-D-MODEL
 72 CONSTANT _SACT-D-EFFORT
 88 CONSTANT _SACT-D-TIER
104 CONSTANT _SACT-D-PROMPT
120 CONSTANT _SACT-D-CONTEXT          \ a locator, or 0
128 CONSTANT SACT-DRAFT-SIZE

: SACT-D.EFFECTS     ( draft -- a ) _SACT-D-EFFECTS + ;
: SACT-D.TIME        ( draft -- a ) _SACT-D-TIME + ;
: SACT-D.DISCLOSURE  ( draft -- a ) _SACT-D-DISCLOSURE + ;
: SACT-D.OUTPUT      ( draft -- a ) _SACT-D-OUTPUT + ;
: SACT-D.VERBOSITY   ( draft -- a ) _SACT-D-VERBOSITY + ;
: SACT-D.PROVIDER    ( draft -- a ) _SACT-D-PROVIDER + ;
: SACT-D.MODEL       ( draft -- a ) _SACT-D-MODEL + ;
: SACT-D.EFFORT      ( draft -- a ) _SACT-D-EFFORT + ;
: SACT-D.TIER        ( draft -- a ) _SACT-D-TIER + ;
: SACT-D.PROMPT      ( draft -- a ) _SACT-D-PROMPT + ;
: SACT-D.CONTEXT     ( draft -- a ) _SACT-D-CONTEXT + ;

: SACT-DRAFT-INIT  ( draft -- ) SACT-DRAFT-SIZE 0 FILL ;

\ Sets a draft string to U bytes at ADDRESS.
: SACT-D!  ( address u slot -- ) TUCK 8 + ! ! ;

: _SACT-D$  ( slot -- address u ) DUP @ SWAP 8 + @ ;

\ The bytes the draft's operands take.
: SACT-AGENT-SIZE  ( draft -- bytes )
    SACT-AGENT-HEAD
    OVER SACT-D.PROVIDER 8 + @ SACT-STR-U +
    OVER SACT-D.MODEL 8 + @ SACT-STR-U +
    OVER SACT-D.EFFORT 8 + @ SACT-STR-U +
    OVER SACT-D.TIER 8 + @ SACT-STR-U +
    OVER SACT-D.CONTEXT @ IF QLOC-SIZE + THEN
    SWAP SACT-D.PROMPT 8 + @ SACT-STR-U + ;

\ Writes the draft's operands at DEST, which holds CAP bytes, and checks
\ them.  A destination too small takes nothing and the result is the
\ size needed.
: SACT-AGENT-ENCODE  ( draft dest cap -- bytes status )
    2 PICK SACT-AGENT-SIZE                   ( draft dest cap u )
    TUCK < IF NIP NIP SACT-S-SMALL EXIT THEN ( draft dest u )
    2DUP 0 FILL >R                           ( draft dest ; R: u )
    SACT-SCHEMA OVER SACT-O.SCHEMA !
    OVER SACT-D.CONTEXT @ IF SACT-F-CONTEXT ELSE 0 THEN OVER SACT-O.FLAGS !
    OVER SACT-D.EFFECTS @ OVER SACT-O.EFFECTS !
    OVER SACT-D.TIME @ OVER SACT-O.TIME !
    OVER SACT-D.DISCLOSURE @ OVER SACT-O.DISCLOSURE !
    OVER SACT-D.OUTPUT @ OVER SACT-O.OUTPUT !
    OVER SACT-D.VERBOSITY @ OVER SACT-O.VERBOSITY !
    DUP SACT-AGENT-HEAD +                    ( draft dest at )
    2 PICK SACT-D.PROVIDER _SACT-D$ ROT SACT-STR!
    2 PICK SACT-D.MODEL _SACT-D$ ROT SACT-STR!
    2 PICK SACT-D.EFFORT _SACT-D$ ROT SACT-STR!
    2 PICK SACT-D.TIER _SACT-D$ ROT SACT-STR!
    2 PICK SACT-D.CONTEXT @ ?DUP IF OVER QLOC-SIZE MOVE QLOC-SIZE + THEN
    2 PICK SACT-D.PROMPT _SACT-D$ ROT SACT-STR! DROP
    NIP                                      ( dest )
    SACT-AGENT-RUN SACT-SCHEMA ROT R@ SACT-OPERANDS-OK?
    R> SWAP ;

\ ---------------------------------------------------------------------
\  The operand digest
\ ---------------------------------------------------------------------

CREATE _SACT-CELLS 24 ALLOT

\ SHA3-256 of the domain, ACTION, SCHEMA, U and the U bytes of operands:
\ what a permission binds.
: SACT-DIGEST  ( action schema operands u dest -- )
    >R
    3 PICK _SACT-CELLS !
    2 PICK _SACT-CELLS 8 + !
    DUP _SACT-CELLS 16 + !
    SHA3-256-BEGIN
    S" akashic.sched.operands.v1" SHA3-256-ADD
    _SACT-CELLS 24 SHA3-256-ADD
    SHA3-256-ADD 2DROP
    R> SHA3-256-END ;

\ =====================================================================
\  Outcomes and reasons
\ =====================================================================

1 CONSTANT SACT-O-COMPLETED
2 CONSTANT SACT-O-FAILED
3 CONSTANT SACT-O-CANCELLED
4 CONSTANT SACT-O-EXPIRED
5 CONSTANT SACT-O-STOPPED         \ stopped for review
6 CONSTANT SACT-O-BLOCKED         \ refused before it started
7 CONSTANT SACT-O-INDETERMINATE   \ whether it ran is unknown
8 CONSTANT SACT-O-NOT-STARTED

 0 CONSTANT SACT-R-NONE
 1 CONSTANT SACT-R-NOT-APPROVED
 2 CONSTANT SACT-R-REVOKED
 3 CONSTANT SACT-R-CHANGED
 4 CONSTANT SACT-R-PRACTICE
 5 CONSTANT SACT-R-AGENT-UNAVAILABLE
 6 CONSTANT SACT-R-MODEL-UNAVAILABLE
 7 CONSTANT SACT-R-TOO-LARGE
 8 CONSTANT SACT-R-CAPACITY
 9 CONSTANT SACT-R-INVALID
10 CONSTANT SACT-R-OVERLAP
11 CONSTANT SACT-R-CONTEXT-UNAVAILABLE
12 CONSTANT SACT-R-MISSED
13 CONSTANT SACT-R-RESTART
14 CONSTANT SACT-R-USER
15 CONSTANT SACT-R-SHUTDOWN
16 CONSTANT SACT-R-TOOL
17 CONSTANT SACT-R-APPROVAL
18 CONSTANT SACT-R-CONTEXT-STALE
19 CONSTANT SACT-R-TIME
20 CONSTANT SACT-R-OUTPUT
21 CONSTANT SACT-R-DISCLOSURE
22 CONSTANT SACT-R-PROVIDER-ERROR
23 CONSTANT SACT-R-PROVIDER-START
24 CONSTANT SACT-R-CONTEXT-READ
25 CONSTANT SACT-R-INTERNAL
26 CONSTANT SACT-R-INTERRUPTED
27 CONSTANT SACT-R-AGENT-STORE
28 CONSTANT SACT-R-AGENT-LOST
29 CONSTANT SACT-R-KEY-CONFLICT
30 CONSTANT _SACT-REASONS

\ For each reason, the outcomes it may explain, as bits 1 << outcome.
  2 CONSTANT _SACT-COMPLETED
  4 CONSTANT _SACT-FAILED
  8 CONSTANT _SACT-CANCELLED
 16 CONSTANT _SACT-EXPIRED
 32 CONSTANT _SACT-STOPPED
 64 CONSTANT _SACT-BLOCKED
128 CONSTANT _SACT-INDETERMINATE
256 CONSTANT _SACT-NOT-STARTED

CREATE _SACT-PAIRS
    _SACT-COMPLETED ,                            \ none
    _SACT-BLOCKED ,                              \ not approved
    _SACT-BLOCKED _SACT-CANCELLED OR ,           \ revoked
    _SACT-BLOCKED , _SACT-BLOCKED ,              \ changed, Practice
    _SACT-BLOCKED , _SACT-BLOCKED ,              \ Agent, model unavailable
    _SACT-BLOCKED , _SACT-BLOCKED ,              \ too large, capacity
    _SACT-BLOCKED , _SACT-BLOCKED ,              \ invalid, overlap
    _SACT-BLOCKED ,                              \ context unavailable
    _SACT-NOT-STARTED , _SACT-NOT-STARTED ,      \ missed, restart
    _SACT-CANCELLED , _SACT-CANCELLED ,          \ user, shutdown
    _SACT-STOPPED , _SACT-STOPPED , _SACT-STOPPED ,  \ tool, approval, stale
    _SACT-EXPIRED , _SACT-EXPIRED , _SACT-EXPIRED ,  \ time, output, disclosure
    _SACT-FAILED , _SACT-FAILED ,                \ provider error, start
    _SACT-FAILED , _SACT-FAILED ,                \ context read, internal
    _SACT-INDETERMINATE , _SACT-INDETERMINATE ,  \ interrupted, Agent store
    _SACT-INDETERMINATE , _SACT-INDETERMINATE ,  \ Agent lost, key conflict

\ Whether REASON may explain OUTCOME.
: SACT-OUTCOME-OK?  ( outcome reason -- flag )
    DUP 0 _SACT-REASONS WITHIN 0= IF 2DROP 0 EXIT THEN
    OVER SACT-O-COMPLETED SACT-O-NOT-STARTED 1+ WITHIN 0= IF 2DROP 0 EXIT THEN
    CELLS _SACT-PAIRS + @ SWAP RSHIFT 1 AND 0<> ;

: SACT-OUTCOME$  ( outcome -- address length )
    CASE
        SACT-O-COMPLETED     OF S" completed" ENDOF
        SACT-O-FAILED        OF S" failed" ENDOF
        SACT-O-CANCELLED     OF S" cancelled" ENDOF
        SACT-O-EXPIRED       OF S" ran out" ENDOF
        SACT-O-STOPPED       OF S" stopped for review" ENDOF
        SACT-O-BLOCKED       OF S" blocked" ENDOF
        SACT-O-INDETERMINATE OF S" indeterminate" ENDOF
        SACT-O-NOT-STARTED   OF S" not started" ENDOF
        >R 0 0 R>
    ENDCASE ;

: SACT-REASON$  ( reason -- address length )
    CASE
        SACT-R-NONE                OF 0 0 ENDOF
        SACT-R-NOT-APPROVED        OF S" not approved" ENDOF
        SACT-R-REVOKED             OF S" permission revoked" ENDOF
        SACT-R-CHANGED             OF S" changed since approval" ENDOF
        SACT-R-PRACTICE            OF S" another Practice" ENDOF
        SACT-R-AGENT-UNAVAILABLE   OF S" Agent unavailable" ENDOF
        SACT-R-MODEL-UNAVAILABLE   OF S" model unavailable" ENDOF
        SACT-R-TOO-LARGE           OF S" too large for the model" ENDOF
        SACT-R-CAPACITY            OF S" out of room" ENDOF
        SACT-R-INVALID             OF S" invalid request" ENDOF
        SACT-R-OVERLAP             OF S" a run is already in progress" ENDOF
        SACT-R-CONTEXT-UNAVAILABLE OF S" document unavailable" ENDOF
        SACT-R-MISSED              OF S" missed" ENDOF
        SACT-R-RESTART             OF S" Desk restarted before it ran" ENDOF
        SACT-R-USER                OF S" cancelled by you" ENDOF
        SACT-R-SHUTDOWN            OF S" Desk shut down" ENDOF
        SACT-R-TOOL                OF S" asked to use a tool" ENDOF
        SACT-R-APPROVAL            OF S" asked for approval" ENDOF
        SACT-R-CONTEXT-STALE       OF S" the document changed" ENDOF
        SACT-R-TIME                OF S" out of time" ENDOF
        SACT-R-OUTPUT              OF S" reply too long" ENDOF
        SACT-R-DISCLOSURE          OF S" over the disclosure limit" ENDOF
        SACT-R-PROVIDER-ERROR      OF S" provider error" ENDOF
        SACT-R-PROVIDER-START      OF S" provider did not start" ENDOF
        SACT-R-CONTEXT-READ        OF S" document unreadable" ENDOF
        SACT-R-INTERNAL            OF S" internal error" ENDOF
        SACT-R-INTERRUPTED         OF S" interrupted" ENDOF
        SACT-R-AGENT-STORE         OF S" Agent's record uncertain" ENDOF
        SACT-R-AGENT-LOST          OF S" Agent has no record of it" ENDOF
        SACT-R-KEY-CONFLICT        OF S" conflicting request" ENDOF
        >R 0 0 R>
    ENDCASE ;
