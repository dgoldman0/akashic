\ =====================================================================
\  dispatch.f - The Agent's scheduled runs
\ =====================================================================
\  Desk's broker hands the Agent each approved scheduled run as a plain
\  request (interop/scheduled-dispatch.f) with the authority it compiled
\  for it.  The Agent starts the run on exactly the model the request
\  names, in a conversation of its own, records it in its run store
\  (storage/dispatch-store.f), and tells the broker how it stands and how
\  it ended.
\
\  The Agent runs one thing at a time.  A run it cannot start now, while
\  chat or another scheduled run is running, waits and keeps its place in
\  line; chat waits behind it, and cannot cancel it.  Before anything is
\  recorded, a run is refused when the Agent's provider is not the one
\  it names, the catalog does not offer its model exactly, the provider
\  is not ready, or its prompt does not fit the provider's input.  A run
\  that started ends completed; stopped for review when its model asks
\  for a tool or an approval; out of time; out of room for its reply,
\  which keeps no more than its limit; cancelled; or failed.  Its
\  transcript, the messages of its conversation, goes to the run store.
\
\  A run's correlation id is 2^48 plus its serial in the run store, so it
\  never meets a chat run's.  Statuses are the dispatch contract's
\  SDSP-S- values.  The dispatcher is caller-serialized: Desk calls it
\  from its loop, ADISP-PUMP after each runtime pump.
\
\  Before a user approves a schedule, Desk asks ADISP-VET whether the
\  Agent could run it, and Daybook offers the models ADISP-MODELS lists.
\
\  Public API:
\    ADISP-SIZE    ( -- bytes )
\    ADISP-INIT    ( runtime vfs dispatch -- status )
\    ADISP-FINI    ( dispatch -- )
\    ADISP-VALID?  ( dispatch -- flag )
\    ADISP-STORE   ( dispatch -- store )
\    ADISP-START   ( request amrun response dispatch -- status )
\    ADISP-VET     ( request dispatch -- reason|0 )
\    ADISP-MODELS  ( buffer capacity dispatch -- bytes status )
\    ADISP-STATUS  ( key response dispatch -- status )
\    ADISP-CANCEL  ( key reason dispatch -- status )
\    ADISP-IDLE?   ( dispatch -- flag )
\    ADISP-BUSY?   ( dispatch -- flag )
\    ADISP-PUMP    ( dispatch -- )
\ =====================================================================

PROVIDED akashic-agent-dispatch

REQUIRE runtime.f
REQUIRE run-settings.f
REQUIRE storage/dispatch-store.f
REQUIRE storage/thread-codec.f
REQUIRE ../../../utils/datetime.f
REQUIRE ../../../utils/record-table.f
REQUIRE ../../../utils/string.f

1 48 LSHIFT CONSTANT ADISP-RUN-BASE

\ The current run's phase.
0 CONSTANT _ADISP-P-NONE
1 CONSTANT _ADISP-P-RUNNING
2 CONSTANT _ADISP-P-ENDING     \ over; its end not yet recorded

\ A summary is an outcome, a reason and a count of reply bytes, with
\ their separators; the catalog's longest texts and a 19-digit count fit
\ well within this.
128 CONSTANT _ADISP-SUMMARY-CAP

0x5053494441474141 CONSTANT _ADISP-MAGIC   \ "AAGADISP"

  0 CONSTANT _ADISP-MAGIC-OFF
  8 CONSTANT _ADISP-SELF
 16 CONSTANT _ADISP-RUNTIME
 24 CONSTANT _ADISP-WAITING     \ RTAB-SIZE bytes: keys in the order they came
 48 CONSTANT _ADISP-PHASE
 56 CONSTANT _ADISP-KEY         \ the current run's dispatch key
 88 CONSTANT _ADISP-RUN-ID
 96 CONSTANT _ADISP-OUTPUT      \ the bytes of reply it may keep
104 CONSTANT _ADISP-CAUSE       \ why the Agent cancelled it, as an SACT-R- value
112 CONSTANT _ADISP-OUTCOME     \ how it ended, until that is recorded
120 CONSTANT _ADISP-REASON
128 CONSTANT _ADISP-REPLY-U
136 CONSTANT _ADISP-CONV        \ its conversation, until its end is recorded
\ The arguments of the START being answered; a vet uses the request.
144 CONSTANT _ADISP-REQUEST
152 CONSTANT _ADISP-AMRUN
160 CONSTANT _ADISP-RESPONSE
168 CONSTANT _ADISP-SUMMARY-U
176 CONSTANT _ADISP-DIGEST      \ 32 bytes: the digest of a request the key's run has
\ While a model list is measured or written: the bytes so far or the
\ address, and which.
208 CONSTANT _ADISP-AT
216 CONSTANT _ADISP-WRITE
224 CONSTANT _ADISP-DESIGNATION
_ADISP-DESIGNATION AGENT-RUN-DESIGNATION-SIZE + CONSTANT _ADISP-SUMMARY
_ADISP-SUMMARY _ADISP-SUMMARY-CAP + 7 + -8 AND CONSTANT _ADISP-STORE
_ADISP-STORE ADST-SIZE + CONSTANT ADISP-SIZE

: _ADISP.MAGIC        ( dispatch -- a ) _ADISP-MAGIC-OFF + ;
: _ADISP.SELF         ( dispatch -- a ) _ADISP-SELF + ;
: _ADISP.RUNTIME      ( dispatch -- a ) _ADISP-RUNTIME + ;
: _ADISP.WAITING      ( dispatch -- table ) _ADISP-WAITING + ;
: _ADISP.PHASE        ( dispatch -- a ) _ADISP-PHASE + ;
: _ADISP.KEY          ( dispatch -- key ) _ADISP-KEY + ;
: _ADISP.RUN-ID       ( dispatch -- a ) _ADISP-RUN-ID + ;
: _ADISP.OUTPUT       ( dispatch -- a ) _ADISP-OUTPUT + ;
: _ADISP.CAUSE        ( dispatch -- a ) _ADISP-CAUSE + ;
: _ADISP.OUTCOME      ( dispatch -- a ) _ADISP-OUTCOME + ;
: _ADISP.REASON       ( dispatch -- a ) _ADISP-REASON + ;
: _ADISP.REPLY-U      ( dispatch -- a ) _ADISP-REPLY-U + ;
: _ADISP.CONV         ( dispatch -- a ) _ADISP-CONV + ;
: _ADISP.REQUEST      ( dispatch -- a ) _ADISP-REQUEST + ;
: _ADISP.AMRUN        ( dispatch -- a ) _ADISP-AMRUN + ;
: _ADISP.RESPONSE     ( dispatch -- a ) _ADISP-RESPONSE + ;
: _ADISP.SUMMARY-U    ( dispatch -- a ) _ADISP-SUMMARY-U + ;
: _ADISP.DIGEST       ( dispatch -- a ) _ADISP-DIGEST + ;
: _ADISP.AT           ( dispatch -- a ) _ADISP-AT + ;
: _ADISP.WRITE        ( dispatch -- a ) _ADISP-WRITE + ;
: _ADISP.DESIGNATION  ( dispatch -- designation ) _ADISP-DESIGNATION + ;
: _ADISP.SUMMARY      ( dispatch -- a ) _ADISP-SUMMARY + ;
: ADISP-STORE         ( dispatch -- store ) _ADISP-STORE + ;

: ADISP-VALID?  ( dispatch -- flag )
    DUP 0= IF EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _ADISP.MAGIC @ _ADISP-MAGIC <> IF DROP 0 EXIT THEN
    DUP _ADISP.SELF @ = ;

: _ADISP-RT  ( dispatch -- runtime ) _ADISP.RUNTIME @ ;

\ The wall clock in milliseconds, or -1 while it is not set.  A run's
\ record says when it ran, a calendar instant.
: _ADISP-NOW  ( -- now ) DT-CLOCK-VALID? IF DT-NOW-MS ELSE -1 THEN ;

\ =====================================================================
\  Waiting runs
\ =====================================================================

\ Where KEY waits in line, or -1.
: _ADISP-WAITING-INDEX  ( key dispatch -- index|-1 )
    _ADISP.WAITING DUP RTAB-COUNT@ 0 ?DO          ( key table )
        I OVER 32 RTAB-NTH 32 3 PICK 32 COMPARE 0= IF
            2DROP I UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

\ Puts KEY at the end of the line, unless it is in line already.
: _ADISP-WAIT  ( key dispatch -- status )
    2DUP _ADISP-WAITING-INDEX 0< 0= IF 2DROP SDSP-S-WAITING EXIT THEN
    DUP _ADISP.WAITING 32 RTAB-RESERVE IF 2DROP SDSP-S-UNAVAILABLE EXIT THEN
    _ADISP.WAITING DUP RTAB-COUNT@ SWAP 32 RTAB-INSERT   ( key slot )
    32 MOVE SDSP-S-WAITING ;

\ Takes KEY out of line, if it is in line.
: _ADISP-UNWAIT  ( key dispatch -- )
    TUCK _ADISP-WAITING-INDEX DUP 0< IF 2DROP EXIT THEN
    SWAP _ADISP.WAITING 32 RTAB-DELETE ;

\ Whether KEY is first in line, or no run waits.
: _ADISP-FIRST?  ( key dispatch -- flag )
    _ADISP.WAITING DUP RTAB-COUNT@ 0= IF 2DROP -1 EXIT THEN
    0 SWAP 32 RTAB-NTH 32 SWAP 32 COMPARE 0= ;

\ Chat waits while a scheduled run waits or runs.
: _ADISP-HOLD  ( dispatch -- )
    DUP _ADISP.WAITING RTAB-COUNT@ 0<>
    OVER _ADISP.PHASE @ _ADISP-P-RUNNING = OR
    SWAP _ADISP-RT ARUNTIME-HOLD! ;


\ =====================================================================
\  Answers
\ =====================================================================

: _ADISP-SAY  ( address length dispatch -- )
    >R R@ _ADISP.SUMMARY-U @ OVER + _ADISP-SUMMARY-CAP > IF
        2DROP R> DROP EXIT
    THEN
    R@ _ADISP.SUMMARY R@ _ADISP.SUMMARY-U @ +         ( address length to )
    OVER R> _ADISP.SUMMARY-U +!
    SWAP MOVE ;

\ The summary of an end, into RESPONSE: the outcome, its reason, and how
\ many bytes of reply the run kept.  Never anything the run said.
: _ADISP-SUMMARY!  ( outcome reason reply-u response dispatch -- status )
    >R
    0 R@ _ADISP.SUMMARY-U !
    3 PICK SACT-OUTCOME$ R@ _ADISP-SAY
    2 PICK SACT-REASON$ DUP IF
        S" : " R@ _ADISP-SAY R@ _ADISP-SAY
    ELSE
        2DROP
    THEN
    OVER IF
        S" ; " R@ _ADISP-SAY
        OVER NUM>STR R@ _ADISP-SAY
        S"  bytes of reply" R@ _ADISP-SAY
    THEN
    NIP NIP NIP
    R@ _ADISP.SUMMARY R> _ADISP.SUMMARY-U @ ROT SDSP-SUMMARY! ;

\ Answers OUTCOME for REASON, after REPLY-U bytes of reply, into
\ RESPONSE, which already names the run: ENDED, or SMALL when the summary
\ does not fit.
: _ADISP-END!  ( outcome reason reply-u response dispatch -- status )
    >R
    3 PICK OVER SDSP-P.OUTCOME !
    2 PICK OVER SDSP-P.REASON !
    R> _ADISP-SUMMARY! ?DUP IF EXIT THEN
    SDSP-S-ENDED ;

\ Names RUN, a recorded run, in RESPONSE: its RID, its permission at its
\ revision, and its Practice.
: _ADISP-NAME!  ( run response -- )
    OVER ADST-R.RID OVER SDSP-P.RUN RID-COPY
    OVER ADST-R.PERMISSION OVER SDSP-P.PERMISSION RID-COPY
    OVER ADST-R.REVISION @ OVER SDSP-P.PERMISSION-REVISION !
    SWAP ADST-R.PRACTICE SWAP SDSP-P.PRACTICE RID-COPY ;

\ Names in RESPONSE what REQUEST names: no run, its permission at its
\ revision, and its Practice.
: _ADISP-NAME-REQUEST!  ( request response -- )
    DUP SDSP-P.RUN RID-CLEAR
    OVER SDSP-R.PERMISSION OVER SDSP-P.PERMISSION RID-COPY
    OVER SDSP-R.PERMISSION-REVISION @ OVER SDSP-P.PERMISSION-REVISION !
    SWAP SDSP-R.PRACTICE SWAP SDSP-P.PRACTICE RID-COPY ;

\ Answers how RUN, a recorded run, ended.
: _ADISP-ENDED  ( run response dispatch -- status )
    >R 2DUP _ADISP-NAME!
    SWAP DUP ADST-R.OUTCOME @ OVER ADST-R.REASON @ ROT ADST-R.REPLY-U @
    3 ROLL R> _ADISP-END! ;

\ Answers RUN, recorded with no end though it is not the current run: the
\ Agent was running it when it last stopped.
: _ADISP-LOST  ( run response dispatch -- status )
    >R TUCK _ADISP-NAME!
    SACT-O-INDETERMINATE SACT-R-INTERRUPTED 0 3 ROLL R> _ADISP-END! ;

\ Answers the current run, which is running: RESPONSE names it.
: _ADISP-RUNS  ( response dispatch -- status )
    DUP _ADISP.KEY SWAP ADISP-STORE ADST-FIND        ( response run|0 )
    ?DUP IF SWAP _ADISP-NAME! ELSE DROP THEN
    SDSP-S-RUNNING ;

\ Answers the current run, which is over though its end is not recorded.
: _ADISP-OVER  ( response dispatch -- status )
    2DUP _ADISP-RUNS DROP
    DUP _ADISP.OUTCOME @ OVER _ADISP.REASON @ 2 PICK _ADISP.REPLY-U @
    4 ROLL 4 ROLL _ADISP-END! ;

\ Answers OUTCOME for REASON for the request being started, which no
\ record names.
: _ADISP-TELL  ( outcome reason dispatch -- status )
    >R R@ _ADISP.REQUEST @ R@ _ADISP.RESPONSE @ _ADISP-NAME-REQUEST!
    0 R@ _ADISP.RESPONSE @ R> _ADISP-END! ;

\ Refuses the request being started, before anything was recorded, for
\ REASON: it ends blocked.
: _ADISP-REFUSE  ( reason dispatch -- status )
    >R R@ _ADISP.REQUEST @ SDSP-R.KEY R@ _ADISP-UNWAIT
    R@ _ADISP-HOLD
    SACT-O-BLOCKED SWAP R> _ADISP-TELL ;

\ =====================================================================
\  Ends
\ =====================================================================

\ The last assistant message of CONVERSATION, or 0.
: _ADISP-REPLY  ( conversation -- message|0 )
    0 OVER ACONV.COUNT @ 0 ?DO                       ( conversation found )
        I 2 PICK ACONV-NTH DUP AMSG.ROLE @ AROLE-ASSISTANT = IF
            NIP
        ELSE
            DROP
        THEN
    LOOP
    NIP ;

\ How many of U bytes of text at ADDRESS fit within LIMIT, cut at a
\ character: a cut never splits one.
: _ADISP-CUT  ( address u limit -- u' )
    2DUP > 0= IF DROP NIP EXIT THEN
    NIP
    BEGIN DUP WHILE
        2DUP + C@ 192 AND 128 <> IF NIP EXIT THEN
        1-
    REPEAT
    NIP ;

\ How a run that ended in runtime STATUS ended, as an outcome and a reason
\ the catalog pairs.  STOP is why it stopped for review (an ARUNTIME-STOP-
\ value), and WHY why the Agent cancelled it: for the user, a shutdown or
\ a revoked permission (SACT-R- values); each is 0 for none.  A run that
\ completed did, whoever asked it to stop too late.  A run its provider
\ ended on its own failed, unless only time ran out.  Whether its reply
\ ran out of room, its length tells.
: _ADISP-END  ( status stop why -- outcome reason )
    OVER ARUNTIME-STOP-TOOL = IF 2DROP DROP SACT-O-STOPPED SACT-R-TOOL EXIT THEN
    OVER ARUNTIME-STOP-APPROVAL = IF
        2DROP DROP SACT-O-STOPPED SACT-R-APPROVAL EXIT
    THEN
    NIP SWAP                                         ( why status )
    DUP ARUN-S-IDLE = IF 2DROP SACT-O-COMPLETED SACT-R-NONE EXIT THEN
    OVER IF DROP SACT-O-CANCELLED SWAP EXIT THEN
    NIP ARUN-S-EXPIRED = IF
        SACT-O-EXPIRED SACT-R-TIME
    ELSE
        SACT-O-FAILED SACT-R-PROVIDER-ERROR
    THEN ;

\ Takes the current run's end from the runtime once it is over: how it
\ ended, and its conversation, whose reply keeps no more than the run's
\ limit.  A reply past the limit ran out of room, however the run ended.
: _ADISP-COLLECT  ( dispatch -- )
    DUP _ADISP.PHASE @ _ADISP-P-RUNNING <> IF DROP EXIT THEN
    DUP _ADISP-RT ARUNTIME-RUN-ENDED? 0= IF DROP EXIT THEN
    >R R@ _ADISP-RT ARUNTIME-RUN-TAKE               ( conversation status stop )
    R@ _ADISP.CAUSE @ _ADISP-END                     ( conversation outcome reason )
    R@ _ADISP.REASON ! R@ _ADISP.OUTCOME !
    DUP R@ _ADISP.CONV !
    _ADISP-REPLY ?DUP IF                             ( message )
        DUP AMSG-TEXT R@ _ADISP.OUTPUT @ _ADISP-CUT   ( message u' )
        OVER AMSG.TEXT-U @ OVER <> IF
            SACT-O-EXPIRED R@ _ADISP.OUTCOME !
            SACT-R-OUTPUT R@ _ADISP.REASON !
        THEN
        DUP R@ _ADISP.REPLY-U ! SWAP AMSG.TEXT-U !
    ELSE
        0 R@ _ADISP.REPLY-U !
    THEN
    \ The transcript is what the run said; its model context only repeats
    \ it for the provider.
    R@ _ADISP.CONV @ ACONV.MODEL-CONTEXT @ ACTX-CLEAR
    _ADISP-P-ENDING R@ _ADISP.PHASE !
    R> _ADISP-HOLD ;

\ The current run's conversation encoded, into an allocation the caller
\ frees.
: _ADISP-TRANSCRIPT  ( dispatch -- address length status )
    _ADISP.CONV @ DUP ATHREAD-ENCODE-SIZE ?DUP IF NIP NIP 0 0 ROT EXIT THEN
                                                     ( conversation u )
    DUP ALLOCATE IF 2DROP DROP 0 0 ATHREAD-S-NOMEM EXIT THEN   ( conv u buffer )
    1 3 PICK 2 PICK 4 PICK ATHREAD-ENCODE ?DUP IF    ( conv u buffer length status )
        NIP SWAP FREE NIP NIP 0 0 ROT EXIT
    THEN                                             ( conv u buffer length )
    ROT DROP ROT DROP ATHREAD-S-OK ;

\ Writes the current run's end, with its transcript, to its record.  A
\ store whose disk or memory failed is tried again at the next pump; one
\ that cannot take the end at all is given up on, and a blocked store's
\ next open finds the run in flight.
: _ADISP-RECORD  ( dispatch -- )
    DUP _ADISP.PHASE @ _ADISP-P-ENDING <> IF DROP EXIT THEN
    >R
    R@ ADISP-STORE ADST-STATE@ ADST-READY = IF
        R@ _ADISP.KEY R@ ADISP-STORE ADST-FIND ?DUP IF   ( run )
            R@ _ADISP-TRANSCRIPT IF 2DROP 0 0 THEN       ( run address length )
            2DUP 4 PICK R@ ADISP-STORE ADST-TRANSCRIPT! DROP
            DROP ?DUP IF FREE THEN                       ( run )
            R@ _ADISP.OUTCOME @ R@ _ADISP.REASON @ R@ _ADISP.REPLY-U @
            _ADISP-NOW 4 ROLL R@ ADISP-STORE ADST-FINISH
            \ The disk or memory failing now may not fail next time.
            DUP ADST-S-IO = SWAP ADST-S-NOMEM = OR IF R> DROP EXIT THEN
        THEN
    THEN
    R@ _ADISP.CONV @ ACONV-FREE 0 R@ _ADISP.CONV !
    _ADISP-P-NONE R@ _ADISP.PHASE !
    R> _ADISP-HOLD ;

\ Cancels the current run, if it runs, for REASON, and takes its end.
: _ADISP-STOP  ( reason dispatch -- )
    DUP _ADISP.PHASE @ _ADISP-P-RUNNING <> IF 2DROP EXIT THEN
    TUCK _ADISP.CAUSE !
    ARUN-S-CANCELLED OVER _ADISP-RT ARUNTIME-RUN-STOP DROP
    _ADISP-COLLECT ;

\ Stops the current run once its reply passes its limit.
: _ADISP-OVERFLOW  ( dispatch -- )
    DUP _ADISP.PHASE @ _ADISP-P-RUNNING <> IF DROP EXIT THEN
    DUP _ADISP-RT ARUNTIME.ASSISTANT-MSG @ ?DUP 0= IF DROP EXIT THEN
    AMSG.TEXT-U @ OVER _ADISP.OUTPUT @ > 0= IF DROP EXIT THEN
    ARUN-S-EXPIRED SWAP _ADISP-RT ARUNTIME-RUN-STOP DROP ;

\ =====================================================================
\  Lifecycle
\ =====================================================================

: _ADISP-PATH$  ( -- address length ) S" /agent-dispatch.bin" ;

\ Configures DISPATCH, ADISP-SIZE cell-aligned bytes, for RUNTIME with its
\ run store in VFS, and opens the store, ending as interrupted any run it
\ shows in flight: the Agent was running it when it last stopped.  The
\ dispatcher works whatever state the store is in, so a store that cannot
\ be used can say why; the status is the store's, an ADST-S- value.
: ADISP-INIT  ( runtime vfs dispatch -- status )
    DUP 0= OVER 7 AND OR IF 2DROP DROP ADST-S-INVALID EXIT THEN
    DUP ADISP-VALID? IF 2DROP DROP ADST-S-STATE EXIT THEN
    2 PICK 0= IF 2DROP DROP ADST-S-INVALID EXIT THEN
    DUP ADISP-SIZE 0 FILL
    >R
    _ADISP-PATH$ R@ ADISP-STORE ADST-INIT ?DUP IF
        NIP R> ADISP-SIZE 0 FILL EXIT
    THEN
    R@ _ADISP.RUNTIME !
    R@ DUP _ADISP.SELF !
    _ADISP-MAGIC R@ _ADISP.MAGIC !
    R@ ADISP-STORE ADST-OPEN ?DUP IF R> DROP EXIT THEN
    _ADISP-NOW R> ADISP-STORE ADST-RECONCILE NIP ;

\ Ends the current run as Desk shuts down, records what it can, releases
\ chat, and closes the store.  The runtime stays its owner's.
: ADISP-FINI  ( dispatch -- )
    DUP ADISP-VALID? 0= IF DROP EXIT THEN
    SACT-R-SHUTDOWN OVER _ADISP-STOP
    DUP _ADISP-RECORD
    DUP _ADISP.CONV @ ?DUP IF ACONV-FREE THEN
    DUP _ADISP.WAITING 32 RTAB-FREE
    0 OVER _ADISP-RT ARUNTIME-HOLD!
    DUP ADISP-STORE ADST-CLOSE DROP
    ADISP-SIZE 0 FILL ;

\ Whether a run could start now: none of the Agent's is in flight or
\ ending, and the runtime is idle.
: ADISP-IDLE?  ( dispatch -- flag )
    DUP ADISP-VALID? 0= IF DROP 0 EXIT THEN
    DUP _ADISP.PHASE @ _ADISP-P-NONE <> IF DROP 0 EXIT THEN
    _ADISP-RT ARUNTIME-IDLE? ;

\ Whether a scheduled run waits or runs: Desk asks before shutting down.
: ADISP-BUSY?  ( dispatch -- flag )
    DUP ADISP-VALID? 0= IF DROP 0 EXIT THEN
    DUP _ADISP.WAITING RTAB-COUNT@ 0<>
    SWAP _ADISP.PHASE @ _ADISP-P-RUNNING = OR ;

\ Follows the current run: stops it once its reply passes its limit,
\ takes its end once it is over, and records that end.
: ADISP-PUMP  ( dispatch -- )
    DUP ADISP-VALID? 0= IF DROP EXIT THEN
    DUP _ADISP-OVERFLOW
    DUP _ADISP-COLLECT
    _ADISP-RECORD ;

\ =====================================================================
\  Starting a run
\ =====================================================================

\ The current run's dispatch key, or 0 when there is none.
: _ADISP-CURRENT  ( dispatch -- key|0 )
    DUP _ADISP.PHASE @ _ADISP-P-NONE = IF DROP 0 EXIT THEN
    _ADISP.KEY ;

\ The operands of the request being started.
: _ADISP-OPERANDS  ( dispatch -- operands )
    _ADISP.REQUEST @ SDSP-OPERANDS$ DROP ;

\ The designation the request being started names, into the dispatcher.
\ It borrows its strings from the request.
: _ADISP-DESIGNATE  ( dispatch -- designation )
    DUP _ADISP-OPERANDS SWAP _ADISP.DESIGNATION      ( operands designation )
    DUP ARDES-INIT
    OVER SACT-MODEL$ 2 PICK ARDES.MODEL-U ! OVER ARDES.MODEL-A !
    OVER SACT-EFFORT$ 2 PICK ARDES.EFFORT-U ! OVER ARDES.EFFORT-A !
    OVER SACT-TIER$ 2 PICK ARDES.TIER-U ! OVER ARDES.TIER-A !
    SWAP SACT-O.VERBOSITY @ OVER ARDES.VERBOSITY ! ;

\ Answers the request being started when its dispatch key names a run the
\ Agent knows, the current one or one it recorded, and leaves -1; else
\ leaves 0.  A request that is not the one its key's run was started for
\ conflicts, and starts nothing.
: _ADISP-KNOWN  ( dispatch -- status -1 | 0 )
    >R R@ _ADISP.REQUEST @ SDSP-R.KEY                ( key )
    R@ _ADISP-CURRENT ?DUP IF
        OVER 32 ROT 32 COMPARE 0= IF
            DROP R@ _ADISP.RESPONSE @ R@
            R@ _ADISP.PHASE @ _ADISP-P-RUNNING = IF _ADISP-RUNS ELSE _ADISP-OVER THEN
            R> DROP -1 EXIT
        THEN
    THEN
    R@ ADISP-STORE ADST-FIND ?DUP 0= IF R> DROP 0 EXIT THEN    ( run )
    R@ _ADISP.REQUEST @ R@ _ADISP.DIGEST ADST-DIGEST
    DUP ADST-R.DIGEST 32 R@ _ADISP.DIGEST 32 COMPARE IF
        DROP SACT-O-INDETERMINATE SACT-R-KEY-CONFLICT R> _ADISP-TELL -1 EXIT
    THEN
    DUP ADST-R.PHASE @ ADST-ENDED = IF
        R@ _ADISP.RESPONSE @ R> _ADISP-ENDED -1 EXIT
    THEN
    R@ _ADISP.RESPONSE @ R> _ADISP-LOST -1 ;

\ Whether the request being started must wait: the Agent is busy, or
\ another run is ahead of it in line.
: _ADISP-MUST-WAIT?  ( dispatch -- flag )
    DUP _ADISP.PHASE @ _ADISP-P-NONE <> IF DROP -1 EXIT THEN
    DUP _ADISP-RT ARUNTIME-IDLE? 0= IF DROP -1 EXIT THEN
    DUP _ADISP.REQUEST @ SDSP-R.KEY SWAP _ADISP-FIRST? 0= ;

\ Whether AMRUN may still disclose U bytes.
: _ADISP-ROOM?  ( u amrun -- flag )
    DUP AMRUN.MANDATE MAND.DISCLOSURE-BUDGET @ SWAP AMRUN.DISCLOSURE-USED @ -
    > 0= ;

\ Why the Agent cannot run the request being started on the model it
\ names, or 0 when it can: its provider is another, the catalog does not
\ offer exactly its model, the provider is not ready, or its prompt does
\ not fit the provider's input.
: _ADISP-RUNNABLE  ( dispatch -- reason|0 )
    >R R@ _ADISP-RT ARUNTIME.PROVIDER @              ( provider )
    R@ _ADISP-OPERANDS SACT-PROVIDER$
    2 PICK DUP APROV.ID-A @ SWAP APROV.ID-U @ COMPARE IF
        DROP R> DROP SACT-R-MODEL-UNAVAILABLE EXIT
    THEN
    \ Without a catalog, no designation stands.
    R@ _ADISP-RT ARUNTIME-RUN-SETTINGS               ( provider settings|0 )
    R@ _ADISP-DESIGNATE SWAP ARSET-DESIGNATION NIP   ( provider status )
    DUP ARSET-S-PENDING = IF 2DROP R> DROP SACT-R-AGENT-UNAVAILABLE EXIT THEN
    IF DROP R> DROP SACT-R-MODEL-UNAVAILABLE EXIT THEN
    DUP APROV.STATE @ APROV-S-READY <> IF
        DROP R> DROP SACT-R-AGENT-UNAVAILABLE EXIT
    THEN
    R> _ADISP-OPERANDS SACT-PROMPT$ ROT APROV-INPUT-FITS?
    IF 0 ELSE SACT-R-TOO-LARGE THEN ;

\ Why the Agent cannot run the request being started, or 0 when it can:
\ it cannot run it on its model, or its authority is no longer active or
\ cannot disclose the prompt.
: _ADISP-VET  ( dispatch -- reason|0 )
    DUP _ADISP-RUNNABLE ?DUP IF NIP EXIT THEN
    DUP _ADISP.AMRUN @ AMRUN-ACTIVE? 0= IF DROP SACT-R-INVALID EXIT THEN
    DUP _ADISP-OPERANDS SACT-PROMPT$ NIP SWAP _ADISP.AMRUN @ _ADISP-ROOM?
    IF 0 ELSE SACT-R-INVALID THEN ;

\ Ends the request being started, recorded but never started, as OUTCOME
\ for REASON, with the conversation its start left (or 0), and answers it.
: _ADISP-UNSTARTED  ( conversation outcome reason dispatch -- status )
    >R
    R@ _ADISP.REASON ! R@ _ADISP.OUTCOME ! R@ _ADISP.CONV !
    0 R@ _ADISP.REPLY-U !
    _ADISP-P-ENDING R@ _ADISP.PHASE !
    R@ _ADISP-RECORD
    R@ _ADISP.PHASE @ _ADISP-P-ENDING = IF
        \ Not yet recorded: the next pump tries again.
        R@ _ADISP.RESPONSE @ R> _ADISP-OVER EXIT
    THEN
    R@ _ADISP.REQUEST @ SDSP-R.KEY R@ ADISP-STORE ADST-FIND ?DUP IF
        R@ _ADISP.RESPONSE @ R> _ADISP-ENDED EXIT
    THEN
    R@ _ADISP.OUTCOME @ R@ _ADISP.REASON @ R> _ADISP-TELL ;

\ Starts the request being started: records it, then starts it in a
\ conversation of its own.
: _ADISP-LAUNCH  ( dispatch -- status )
    >R
    R@ _ADISP.REQUEST @ _ADISP-NOW R@ ADISP-STORE ADST-ACCEPT IF
        DROP SACT-R-AGENT-UNAVAILABLE R> _ADISP-REFUSE EXIT
    THEN                                             ( run )
    R@ _ADISP.REQUEST @ SDSP-R.KEY R@ _ADISP.KEY 32 MOVE
    ADST-R.SERIAL @ ADISP-RUN-BASE + R@ _ADISP.RUN-ID !
    R@ _ADISP-OPERANDS SACT-O.OUTPUT @ R@ _ADISP.OUTPUT !
    0 R@ _ADISP.CAUSE !
    R@ _ADISP.REQUEST @ SDSP-R.KEY R@ _ADISP-UNWAIT
    ACONV-NEW IF
        DROP 0 SACT-O-BLOCKED SACT-R-CAPACITY R> _ADISP-UNSTARTED EXIT
    THEN                                             ( conversation )
    R@ _ADISP.RUN-ID @ OVER ACONV.ID !
    R@ _ADISP-OPERANDS SACT-PROMPT$ R@ _ADISP.RUN-ID @ R@ _ADISP-DESIGNATE
    4 PICK R@ _ADISP.AMRUN @ R@ _ADISP-RT ARUNTIME-RUN-START IF
        SACT-O-FAILED SACT-R-PROVIDER-START R> _ADISP-UNSTARTED EXIT
    THEN
    R@ _ADISP.CONV !
    _ADISP-P-RUNNING R@ _ADISP.PHASE !
    R@ _ADISP-HOLD
    R@ _ADISP.RESPONSE @ R> _ADISP-RUNS DROP
    SDSP-S-STARTED ;

\ Starts the run REQUEST asks for, under AMRUN, the authority Desk's broker
\ compiled for it, and answers into RESPONSE as ADISP-STATUS would after:
\ STARTED, and the Agent owns AMRUN; WAITING, and the run keeps its place
\ in line; RUNNING or ENDED for a run the Agent knows by its key; or ENDED
\ for a run refused, blocked, or one that could not start.  AMRUN stays
\ the caller's unless the answer is STARTED.
: ADISP-START  ( request amrun response dispatch -- status )
    DUP ADISP-VALID? 0= IF 2DROP 2DROP SDSP-S-UNAVAILABLE EXIT THEN
    >R R@ _ADISP.RESPONSE ! R@ _ADISP.AMRUN ! R@ _ADISP.REQUEST !
    R@ _ADISP.REQUEST @ -1 SDSP-REQUEST-OK? IF R> DROP SDSP-S-INVALID EXIT THEN
    R@ _ADISP-KNOWN IF R> DROP EXIT THEN
    R@ _ADISP-MUST-WAIT? IF
        R@ _ADISP.REQUEST @ SDSP-R.KEY R@ _ADISP-WAIT R> _ADISP-HOLD EXIT
    THEN
    R@ _ADISP-VET ?DUP IF R> _ADISP-REFUSE EXIT THEN
    R> _ADISP-LAUNCH ;

\ How the run with dispatch KEY stands, into RESPONSE: RUNNING, WAITING,
\ ENDED, or UNKNOWN for a key the Agent never recorded.
: ADISP-STATUS  ( key response dispatch -- status )
    DUP ADISP-VALID? 0= IF 2DROP DROP SDSP-S-UNAVAILABLE EXIT THEN
    >R
    R@ _ADISP-CURRENT ?DUP IF
        2 PICK 32 ROT 32 COMPARE 0= IF
            NIP R@ _ADISP.PHASE @ _ADISP-P-RUNNING = IF
                R> _ADISP-RUNS
            ELSE
                R> _ADISP-OVER
            THEN
            EXIT
        THEN
    THEN
    OVER R@ _ADISP-WAITING-INDEX 0< 0= IF 2DROP R> DROP SDSP-S-WAITING EXIT THEN
    SWAP R@ ADISP-STORE ADST-FIND ?DUP 0= IF
        DROP R> DROP SDSP-S-UNKNOWN EXIT
    THEN                                             ( response run )
    DUP ADST-R.PHASE @ ADST-ENDED = IF SWAP R> _ADISP-ENDED EXIT THEN
    SWAP R> _ADISP-LOST ;

\ Cancels the run with dispatch KEY for REASON, which must be one that may
\ explain a cancelled run (otherwise the user's): one waiting gives up its
\ place, and the current run ends cancelled.
: ADISP-CANCEL  ( key reason dispatch -- status )
    DUP ADISP-VALID? 0= IF 2DROP DROP SDSP-S-UNAVAILABLE EXIT THEN
    >R
    SACT-O-CANCELLED OVER SACT-OUTCOME-OK? 0= IF DROP SACT-R-USER THEN
    OVER R@ _ADISP-WAITING-INDEX 0< 0= IF
        DROP R@ _ADISP-UNWAIT R> _ADISP-HOLD SDSP-S-OK EXIT
    THEN
    R@ _ADISP-CURRENT ?DUP IF
        2 PICK 32 ROT 32 COMPARE 0= IF
            NIP R@ _ADISP-STOP R> _ADISP-RECORD SDSP-S-OK EXIT
        THEN
    THEN
    DROP R> ADISP-STORE ADST-FIND IF SDSP-S-ENDED ELSE SDSP-S-UNKNOWN THEN ;

\ =====================================================================
\  Before a schedule is approved
\ =====================================================================

\ Why the Agent could not run REQUEST on the model it names, or 0 when it
\ could: the reason ADISP-START would refuse it for, before its authority
\ is looked at.  Desk asks before its user approves REQUEST, which names
\ no occurrence and has no authority yet.  A model the catalog does not
\ offer or a prompt too large for it stays so; an Agent that is not
\ connected, or whose catalog is still loading, may not.
: ADISP-VET  ( request dispatch -- reason|0 )
    DUP ADISP-VALID? 0= IF 2DROP SACT-R-AGENT-UNAVAILABLE EXIT THEN
    OVER 0 SDSP-REQUEST-OK? IF 2DROP SACT-R-INVALID EXIT THEN
    TUCK _ADISP.REQUEST ! _ADISP-RUNNABLE ;

\ Adds text to the model list: its bytes, or the text itself.
: _ADISP-STR+  ( address length dispatch -- )
    >R R@ _ADISP.WRITE @ IF R@ _ADISP.AT @ SACT-STR! R> _ADISP.AT ! EXIT THEN
    NIP SACT-STR-U R> _ADISP.AT +! ;

\ Adds a cell to the model list.
: _ADISP-CELL+  ( x dispatch -- )
    >R R@ _ADISP.WRITE @ IF R@ _ADISP.AT @ SDSP-PUT R> _ADISP.AT ! EXIT THEN
    DROP 8 R> _ADISP.AT +! ;

\ Adds an effort's or a tier's id and label.
: _ADISP-CHOICE+  ( choice dispatch -- )
    >R DUP ARCH-ID R@ _ADISP-STR+ ARCH-LABEL R> _ADISP-STR+ ;

\ Adds MODEL: its id, label and flags, then its efforts and its tiers.
: _ADISP-MODEL+  ( model dispatch -- )
    OVER ARMODEL-ID 2 PICK _ADISP-STR+
    OVER ARMODEL-LABEL 2 PICK _ADISP-STR+
    OVER ARMODEL.FLAGS @ ARMODEL-F-VERBOSITY AND IF SDSP-M-VERBOSITY ELSE 0 THEN
        OVER _ADISP-CELL+
    OVER ARMODEL.EFFORTS-N @ DUP 2 PICK _ADISP-CELL+
    0 ?DO I 2 PICK ARMODEL-EFFORT-NTH OVER _ADISP-CHOICE+ LOOP
    OVER ARMODEL.TIERS-N @ DUP 2 PICK _ADISP-CELL+
    0 ?DO I 2 PICK ARMODEL-TIER-NTH OVER _ADISP-CHOICE+ LOOP
    2DROP ;

\ Adds the list: how many models, the provider's id, then each model.
: _ADISP-LIST+  ( settings dispatch -- )
    OVER ARSET-MODEL-N OVER _ADISP-CELL+
    DUP _ADISP-RT ARUNTIME.PROVIDER @ DUP APROV.ID-A @ SWAP APROV.ID-U @
        2 PICK _ADISP-STR+
    OVER ARSET-MODEL-N 0 ?DO I 2 PICK ARSET-MODEL-NTH OVER _ADISP-MODEL+ LOOP
    2DROP ;

\ The models the Agent can run, as a model list (interop/scheduled-
\ dispatch.f) in BUFFER: its provider, and each model its catalog offers
\ with its efforts and tiers and whether it takes a verbosity.  The list
\ is measured before it is written: one longer than CAPACITY answers
\ SMALL with the bytes it needs.  An Agent without a ready catalog
\ answers UNAVAILABLE.
: ADISP-MODELS  ( buffer capacity dispatch -- bytes status )
    DUP ADISP-VALID? 0= IF 2DROP DROP 0 SDSP-S-UNAVAILABLE EXIT THEN
    DUP _ADISP-RT ARUNTIME-RUN-SETTINGS              ( buffer capacity dispatch settings|0 )
    DUP IF DUP ARSET.STATE @ ARSET-STATE-READY <> IF DROP 0 THEN THEN
    ?DUP 0= IF 2DROP DROP 0 SDSP-S-UNAVAILABLE EXIT THEN
    0 2 PICK _ADISP.AT ! 0 2 PICK _ADISP.WRITE !
    2DUP SWAP _ADISP-LIST+                           ( buffer capacity dispatch settings )
    OVER _ADISP.AT @ DUP 4 PICK > IF                 ( ... bytes )
        NIP NIP NIP NIP SDSP-S-SMALL EXIT
    THEN
    4 PICK SWAP 0 FILL
    3 PICK 2 PICK _ADISP.AT ! -1 2 PICK _ADISP.WRITE !
    OVER _ADISP-LIST+                                ( buffer capacity dispatch )
    _ADISP.AT @ ROT - NIP SDSP-S-OK ;
