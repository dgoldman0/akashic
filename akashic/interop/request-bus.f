\ =====================================================================
\  request-bus.f - Bounded interoperable requests and owner dispatch
\ =====================================================================

PROVIDED akashic-interop-request-bus

REQUIRE ../runtime/registry.f
REQUIRE policy.f
REQUIRE authority.f
REQUIRE practice-turn.f
REQUIRE codecs/json-value.f
REQUIRE ../math/sha3.f
REQUIRE ../concurrency/guard.f

0  CONSTANT CBUS-S-OK
1  CONSTANT CBUS-S-INVALID
2  CONSTANT CBUS-S-NOT-FOUND
3  CONSTANT CBUS-S-STALE-INSTANCE
4  CONSTANT CBUS-S-STALE-REVISION
5  CONSTANT CBUS-S-DENIED
6  CONSTANT CBUS-S-NEEDS-APPROVAL
7  CONSTANT CBUS-S-BUSY
8  CONSTANT CBUS-S-TIMEOUT
9  CONSTANT CBUS-S-CANCELLED
10 CONSTANT CBUS-S-FAILED
11 CONSTANT CBUS-S-NO-HANDLER
12 CONSTANT CBUS-S-STALE-AUTHORITY
13 CONSTANT CBUS-S-EXPIRED-AUTHORITY
14 CONSTANT CBUS-S-CONSUMED-AUTHORITY
15 CONSTANT CBUS-S-AMBIGUOUS-HANDLER

-258 CONSTANT CBUS-E-DISPATCH-ACTIVE

1 CONSTANT CBR-F-APPROVED
2 CONSTANT CBR-F-CANCELLED
4 CONSTANT CBR-F-QUEUED
8 CONSTANT CBR-F-RUNNING
16 CONSTANT CBR-F-COMPLETE

CBR-F-QUEUED CBR-F-RUNNING OR CONSTANT CBR-F-BUSY-MASK

1 CONSTANT CBR-ASF-TYPED-IVJSON-SHA3
65536 CONSTANT CBR-ARGS-CANONICAL-MAX

\ Request structure.  Caller and target are stable runtime handles, never
\ raw instance pointers.  Practice identity, semantic resource identity, and
\ the invocation handle are inline: an operation descriptor pointer remains
\ activation-local metadata, while authority is resolved separately by the
\ target owner.
\
\ Substrate-freeze ABI note: RESOURCE-ID was appended at the former 432-byte
\ end of CBR.  The argument seal fields now follow it.  Every older field
\ retains its offset, but CBR-SIZE is now 512; precompiled clients which
\ allocate a former size are binary-incompatible and must be rebuilt.  A zero
\ RESOURCE-ID and zero argument-seal flags are the legacy defaults.
  0 CONSTANT _CBR-ID
  8 CONSTANT _CBR-TRACE
 16 CONSTANT _CBR-PRINCIPAL
 24 CONSTANT _CBR-CALLER-ID
 32 CONSTANT _CBR-CALLER-GEN
 40 CONSTANT _CBR-TARGET-ID
 48 CONSTANT _CBR-TARGET-GEN
 56 CONSTANT _CBR-CAP
 64 CONSTANT _CBR-DEADLINE
 72 CONSTANT _CBR-EXPECT-REV
 80 CONSTANT _CBR-FLAGS
 88 CONSTANT _CBR-STATUS
 96 CONSTANT _CBR-COMPLETE-XT       \ ( request -- )
104 CONSTANT _CBR-COMPLETE-DATA
112 CONSTANT _CBR-ARGS              \ inline CV-SIZE
152 CONSTANT _CBR-RESULT            \ inline CV-SIZE
192 CONSTANT _CBR-ERROR-A
200 CONSTANT _CBR-ERROR-U
208 CONSTANT _CBR-ACTUAL-REV
216 CONSTANT _CBR-START-MS
224 CONSTANT _CBR-END-MS
232 CONSTANT _CBR-RESERVED
240 CONSTANT _CBR-CONTEXT-ID
248 CONSTANT _CBR-CONTEXT-GEN
256 CONSTANT _CBR-EPOCH
264 CONSTANT _CBR-INVOCATION-ID
296 CONSTANT _CBR-PRACTICE-ID
328 CONSTANT _CBR-MANDATE-ID
360 CONSTANT _CBR-HANDLE
424 CONSTANT _CBR-TURN
432 CONSTANT _CBR-RESOURCE-ID
464 CONSTANT _CBR-ARGS-LEN
472 CONSTANT _CBR-ARGS-DIGEST
504 CONSTANT _CBR-ARGS-SEAL-FLAGS
512 CONSTANT CBR-SIZE

: CBR.ID             ( req -- a ) _CBR-ID + ;
: CBR.TRACE          ( req -- a ) _CBR-TRACE + ;
: CBR.PRINCIPAL      ( req -- a ) _CBR-PRINCIPAL + ;
: CBR.CALLER-ID      ( req -- a ) _CBR-CALLER-ID + ;
: CBR.CALLER-GEN     ( req -- a ) _CBR-CALLER-GEN + ;
: CBR.TARGET-ID      ( req -- a ) _CBR-TARGET-ID + ;
: CBR.TARGET-GEN     ( req -- a ) _CBR-TARGET-GEN + ;
: CBR.CAP            ( req -- a ) _CBR-CAP + ;
: CBR.DEADLINE       ( req -- a ) _CBR-DEADLINE + ;
: CBR.EXPECT-REV     ( req -- a ) _CBR-EXPECT-REV + ;
: CBR.FLAGS          ( req -- a ) _CBR-FLAGS + ;
: CBR.STATUS         ( req -- a ) _CBR-STATUS + ;
: CBR.COMPLETE-XT    ( req -- a ) _CBR-COMPLETE-XT + ;
: CBR.COMPLETE-DATA  ( req -- a ) _CBR-COMPLETE-DATA + ;
: CBR.ARGS           ( req -- value ) _CBR-ARGS + ;
: CBR.RESULT         ( req -- value ) _CBR-RESULT + ;
: CBR.ERROR-A        ( req -- a ) _CBR-ERROR-A + ;
: CBR.ERROR-U        ( req -- a ) _CBR-ERROR-U + ;
: CBR.ACTUAL-REV     ( req -- a ) _CBR-ACTUAL-REV + ;
: CBR.START-MS       ( req -- a ) _CBR-START-MS + ;
: CBR.END-MS         ( req -- a ) _CBR-END-MS + ;
: CBR.ERROR-CODE     ( req -- a ) _CBR-RESERVED + ;
: CBR.CONTEXT-ID     ( req -- a ) _CBR-CONTEXT-ID + ;
: CBR.CONTEXT-GEN    ( req -- a ) _CBR-CONTEXT-GEN + ;
: CBR.EPOCH          ( req -- a ) _CBR-EPOCH + ;
: CBR.INVOCATION-ID  ( req -- id ) _CBR-INVOCATION-ID + ;
: CBR.PRACTICE-ID    ( req -- id ) _CBR-PRACTICE-ID + ;
: CBR.MANDATE-ID     ( req -- id ) _CBR-MANDATE-ID + ;
: CBR.HANDLE         ( req -- handle ) _CBR-HANDLE + ;
: CBR.TURN           ( req -- turn-cell ) _CBR-TURN + ;
: CBR.RESOURCE-ID    ( req -- id ) _CBR-RESOURCE-ID + ;
: CBR.ARGS-LEN       ( req -- a ) _CBR-ARGS-LEN + ;
: CBR.ARGS-DIGEST    ( req -- digest ) _CBR-ARGS-DIGEST + ;
: CBR.ARGS-SEAL-FLAGS ( req -- a ) _CBR-ARGS-SEAL-FLAGS + ;

\ CBR lifecycle transitions share one recursive cross-core guard.  This is
\ deliberately independent of CBUS ring serialization: it prevents one
\ request envelope from being queued, dispatched, or lens-restamped twice,
\ including when the competing callers use different buses.
GUARD _CBR-LIFECYCLE-GUARD

: WITH-CBR-LIFECYCLE  ( xt -- )
    _CBR-LIFECYCLE-GUARD WITH-GUARD ;

: _CBR-LIFECYCLE-BUSY?-LOCKED  ( request -- flag )
    CBR.FLAGS @ CBR-F-BUSY-MASK AND 0<> ;

: _CBR-LIFECYCLE-BUSY?  ( request -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    _CBR-LIFECYCLE-BUSY?-LOCKED ;

: CBR-LIFECYCLE-BUSY?  ( request -- flag )
    ['] _CBR-LIFECYCLE-BUSY? WITH-CBR-LIFECYCLE ;

: _CBR-LIFECYCLE-QUEUE  ( request -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP _CBR-LIFECYCLE-BUSY?-LOCKED IF DROP 0 EXIT THEN
    DUP CBR.FLAGS DUP @ CBR-F-COMPLETE INVERT AND
        CBR-F-QUEUED OR SWAP !
    DROP -1 ;

: CBR-LIFECYCLE-QUEUE  ( request -- flag )
    ['] _CBR-LIFECYCLE-QUEUE WITH-CBR-LIFECYCLE ;

: _CBR-LIFECYCLE-RUN  ( request -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP _CBR-LIFECYCLE-BUSY?-LOCKED IF DROP 0 EXIT THEN
    DUP CBR.FLAGS DUP @
        CBR-F-QUEUED CBR-F-COMPLETE OR INVERT AND
        CBR-F-RUNNING OR SWAP !
    DROP -1 ;

: CBR-LIFECYCLE-RUN  ( request -- flag )
    ['] _CBR-LIFECYCLE-RUN WITH-CBR-LIFECYCLE ;

: _CBR-LIFECYCLE-CLAIM-QUEUED  ( request -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP CBR.FLAGS @ CBR-F-BUSY-MASK AND CBR-F-QUEUED <> IF
        DROP 0 EXIT
    THEN
    DUP CBR.FLAGS DUP @
        CBR-F-QUEUED CBR-F-COMPLETE OR INVERT AND
        CBR-F-RUNNING OR SWAP !
    DROP -1 ;

: _CBR-LIFECYCLE-CLAIM-QUEUED-GUARDED  ( request -- flag )
    ['] _CBR-LIFECYCLE-CLAIM-QUEUED WITH-CBR-LIFECYCLE ;

: _CBR-LIFECYCLE-COMPLETE  ( request -- )
    DUP 0= IF DROP EXIT THEN
    CBR.FLAGS DUP @ CBR-F-BUSY-MASK INVERT AND
        CBR-F-COMPLETE OR SWAP ! ;

: CBR-LIFECYCLE-COMPLETE  ( request -- )
    ['] _CBR-LIFECYCLE-COMPLETE WITH-CBR-LIFECYCLE ;

: _CBR-LIFECYCLE-RESET  ( request -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP _CBR-LIFECYCLE-BUSY?-LOCKED IF DROP 0 EXIT THEN
    0 SWAP CBR.FLAGS ! -1 ;

: CBR-LIFECYCLE-RESET  ( request -- flag )
    ['] _CBR-LIFECYCLE-RESET WITH-CBR-LIFECYCLE ;

: CBR-ERROR-CLEAR  ( request -- )
    DUP 0 SWAP CBR.ERROR-A !
    DUP 0 SWAP CBR.ERROR-U !
    0 SWAP CBR.ERROR-CODE ! ;

: CBR-ERROR!  ( addr len code request -- )
    >R
    R@ CBR.ERROR-CODE !
    R@ CBR.ERROR-U !
    R> CBR.ERROR-A ! ;

CREATE _CBRS-NUL 0 C,
CREATE _CBRS-CHECK SHA3-256-LEN ALLOT
VARIABLE _CBRS-REQ
VARIABLE _CBRS-VALUE
VARIABLE _CBRS-DST
VARIABLE _CBRS-BUF
VARIABLE _CBRS-LEN
VARIABLE _CBRS-STATUS
GUARD _cbr-args-seal-guard

: WITH-CBR-ARGS-SEAL  ( xt -- )
    _cbr-args-seal-guard WITH-GUARD ;

: _CBR-ARGS-DIGEST  ( value destination -- canonical-len status )
    _CBRS-DST ! _CBRS-VALUE !
    CBR-ARGS-CANONICAL-MAX ALLOCATE
    DUP IF 2DROP 0 IVJSON-E-NOMEM EXIT THEN
    DROP _CBRS-BUF !
    _CBRS-VALUE @ _CBRS-BUF @ CBR-ARGS-CANONICAL-MAX
        IVJSON-TYPED-ENCODE
    _CBRS-STATUS ! _CBRS-LEN !
    _CBRS-STATUS @ IF
        _CBRS-BUF @ FREE 0 _CBRS-STATUS @ EXIT
    THEN
    SHA3-256-BEGIN
    S" akashic.agent.cbr-args.typed-ivjson.v1" SHA3-256-ADD
    _CBRS-NUL 1 SHA3-256-ADD
    _CBRS-LEN 8 SHA3-256-ADD
    _CBRS-BUF @ _CBRS-LEN @ SHA3-256-ADD
    _CBRS-DST @ SHA3-256-END
    _CBRS-BUF @ FREE _CBRS-LEN @ 0 ;

: _CBR-ARGS-SEAL-CLEAR  ( request -- )
    DUP 0 SWAP CBR.ARGS-LEN !
    DUP CBR.ARGS-DIGEST SHA3-256-LEN 0 FILL
    0 SWAP CBR.ARGS-SEAL-FLAGS ! ;

: CBR-ARGS-SEAL-CLEAR  ( request -- )
    ['] _CBR-ARGS-SEAL-CLEAR WITH-CBR-ARGS-SEAL ;

: _CBR-ARGS-SEAL!  ( request -- status )
    DUP _CBRS-REQ ! _CBR-ARGS-SEAL-CLEAR
    _CBRS-REQ @ CBR.ARGS _CBRS-REQ @ CBR.ARGS-DIGEST _CBR-ARGS-DIGEST
    _CBRS-STATUS ! _CBRS-LEN !
    _CBRS-STATUS @ IF CBUS-S-INVALID EXIT THEN
    _CBRS-LEN @ _CBRS-REQ @ CBR.ARGS-LEN !
    CBR-ASF-TYPED-IVJSON-SHA3 _CBRS-REQ @ CBR.ARGS-SEAL-FLAGS !
    CBUS-S-OK ;

: CBR-ARGS-SEAL!  ( request -- status )
    ['] _CBR-ARGS-SEAL! WITH-CBR-ARGS-SEAL ;

: _CBR-ARGS-SEAL-MATCH?  ( request -- flag )
    DUP _CBRS-REQ ! CBR.ARGS-SEAL-FLAGS @
        CBR-ASF-TYPED-IVJSON-SHA3 AND 0= IF 0 EXIT THEN
    _CBRS-REQ @ CBR.ARGS _CBRS-CHECK _CBR-ARGS-DIGEST
    _CBRS-STATUS ! _CBRS-LEN !
    _CBRS-STATUS @ IF 0 EXIT THEN
    _CBRS-LEN @ _CBRS-REQ @ CBR.ARGS-LEN @ <> IF 0 EXIT THEN
    _CBRS-CHECK _CBRS-REQ @ CBR.ARGS-DIGEST SHA3-256-COMPARE ;

: CBR-ARGS-SEAL-MATCH?  ( request -- flag )
    ['] _CBR-ARGS-SEAL-MATCH? WITH-CBR-ARGS-SEAL ;

: CBR-NEW  ( -- req ior )
    CBR-SIZE ALLOCATE
    DUP IF EXIT THEN
    DROP DUP CBR-SIZE 0 FILL 0 ;

: CBR-FREE  ( req -- )
    DUP 0= IF DROP EXIT THEN
    DUP CBR.ARGS CV-FREE
    DUP CBR.RESULT CV-FREE
    DUP CBR.TURN @ ?DUP IF
        DUP PTURN-SIZE 0 FILL FREE
    THEN
    FREE ;

32 CONSTANT CBUS-CAPACITY

\ Bus descriptor + inline pointer ring.
  0 CONSTANT _CBUS-HEAD
  8 CONSTANT _CBUS-TAIL
 16 CONSTANT _CBUS-COUNT
 24 CONSTANT _CBUS-NEXT-ID
 32 CONSTANT _CBUS-REGISTRY
 40 CONSTANT _CBUS-POLICY
 48 CONSTANT _CBUS-DROPPED
 56 CONSTANT _CBUS-RESERVED
 64 CONSTANT _CBUS-RING
_CBUS-RING CBUS-CAPACITY 8 * + CONSTANT CBUS-SIZE

: CBUS.HEAD      ( bus -- a ) _CBUS-HEAD + ;
: CBUS.TAIL      ( bus -- a ) _CBUS-TAIL + ;
: CBUS.COUNT     ( bus -- a ) _CBUS-COUNT + ;
: CBUS.NEXT-ID   ( bus -- a ) _CBUS-NEXT-ID + ;
: CBUS.REGISTRY  ( bus -- a ) _CBUS-REGISTRY + ;
: CBUS.POLICY    ( bus -- a ) _CBUS-POLICY + ;
: CBUS.DROPPED   ( bus -- a ) _CBUS-DROPPED + ;
: CBUS.RING      ( bus -- a ) _CBUS-RING + ;
: CBUS.AUTHORITY ( bus -- a ) _CBUS-RESERVED + ;

\ Ring state, dispatch scratch, and the handler-to-revision owner commit form
\ one synchronous owner boundary.  The guard is recursive so policy,
\ capability, and completion callbacks may dispatch synchronously on the same
\ execution owner while other cores remain excluded.
GUARD _CBUS-DISPATCH-GUARD
VARIABLE _CBUS-DISPATCH-DEPTH
VARIABLE _CBUS-OWNER-OP-DEPTH

: CBUS-DISPATCHING?  ( -- flag )
    _CBUS-DISPATCH-GUARD GUARD-MINE?
    _CBUS-DISPATCH-DEPTH @ 0> AND ;

: _CBUS-OWNER-OP-ACTIVE?  ( -- flag )
    _CBUS-DISPATCH-GUARD GUARD-MINE?
    _CBUS-DISPATCH-DEPTH @ _CBUS-OWNER-OP-DEPTH @ + 0> AND ;

: CBUS-WITH-DISPATCH-QUIESCED  ( i*x xt -- j*x )
    _CBUS-DISPATCH-GUARD WITH-GUARD ;

: CBUS-AUTHORITY!  ( table bus -- ) CBUS.AUTHORITY ! ;

: CBUS-NEW  ( registry policy -- bus ior )
    >R >R
    CBUS-SIZE ALLOCATE
    DUP IF R> DROP R> DROP EXIT THEN
    DROP DUP CBUS-SIZE 0 FILL
    1 OVER CBUS.NEXT-ID !
    R> OVER CBUS.REGISTRY !
    R> OVER CBUS.POLICY !
    0 ;

: _CBUS-FREE-QUIESCED  ( bus -- ) ?DUP IF FREE THEN ;

: CBUS-FREE  ( bus -- )
    _CBUS-OWNER-OP-ACTIVE? IF
        DROP CBUS-E-DISPATCH-ACTIVE THROW
    THEN
    ['] _CBUS-FREE-QUIESCED CBUS-WITH-DISPATCH-QUIESCED ;

: _CBUS-POST-QUIESCED  ( request bus -- status )
    >R
    DUP 0= IF DROP R> DROP CBUS-S-INVALID EXIT THEN
    R@ CBUS.COUNT @ CBUS-CAPACITY >= IF
        1 R@ CBUS.DROPPED +!
        DROP R> DROP CBUS-S-BUSY EXIT
    THEN
    DUP CBR-LIFECYCLE-QUEUE 0= IF
        DROP R> DROP CBUS-S-BUSY EXIT
    THEN
    DUP CBR.ID @ 0= IF
        R@ CBUS.NEXT-ID @ OVER CBR.ID !
        1 R@ CBUS.NEXT-ID +!
    THEN
    R@ CBUS.HEAD @ 8 * R@ CBUS.RING + !
    R@ CBUS.HEAD @ 1+ CBUS-CAPACITY MOD R@ CBUS.HEAD !
    1 R@ CBUS.COUNT +!
    R> DROP CBUS-S-OK ;

: CBUS-POST  ( request bus -- status )
    ['] _CBUS-POST-QUIESCED CBUS-WITH-DISPATCH-QUIESCED ;

: _CBUS-POP-QUIESCED  ( bus -- request | 0 )
    DUP CBUS.COUNT @ 0= IF DROP 0 EXIT THEN
    DUP >R
    R@ CBUS.TAIL @ 8 * R@ CBUS.RING + DUP @ SWAP 0 SWAP !
    R@ CBUS.TAIL @ 1+ CBUS-CAPACITY MOD R@ CBUS.TAIL !
    -1 R> CBUS.COUNT +!
    NIP ;

: _CBUS-POP  ( bus -- request | 0 )
    ['] _CBUS-POP-QUIESCED CBUS-WITH-DISPATCH-QUIESCED ;

: _CBUS-POP-CLAIM-QUIESCED  ( bus -- request | 0 )
    \ Claim QUEUED -> RUNNING before removing the ring pointer.  The caller
    \ owns _CBUS-DISPATCH-GUARD, matching POST's dispatch/lifecycle lock
    \ order, so a public direct dispatch cannot observe an unowned gap.
    DUP CBUS.COUNT @ 0= IF DROP 0 EXIT THEN
    DUP >R
    R@ CBUS.TAIL @ 8 * R@ CBUS.RING + DUP @
    DUP 0= IF 2DROP DROP R> DROP 0 EXIT THEN
    DUP _CBR-LIFECYCLE-CLAIM-QUEUED-GUARDED 0= IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    SWAP 0 SWAP !
    R@ CBUS.TAIL @ 1+ CBUS-CAPACITY MOD R@ CBUS.TAIL !
    -1 R> CBUS.COUNT +!
    NIP ;

VARIABLE _CBD-REQ
VARIABLE _CBD-INST
VARIABLE _CBD-CAP
VARIABLE _CBD-BUS
VARIABLE _CBD-STATUS

CREATE _CBD-BINDING AUTH-BINDING-SIZE ALLOT

VARIABLE _CBAB-REQ
VARIABLE _CBAB-BIND
VARIABLE _CBAB-CAP

VARIABLE _CBTP-REQ
VARIABLE _CBTP-CAP
VARIABLE _CBTP-TURN

VARIABLE _CBC-CAP
VARIABLE _CBC-INST
VARIABLE _CBC-DESC

: _CBUS-CAP-BELONGS?  ( cap inst -- flag )
    _CBC-INST ! _CBC-CAP !
    _CBC-INST @ CINST-DESC DUP _CBC-DESC !
    COMP.CAPS-N @ 0= IF 0 EXIT THEN
    _CBC-CAP @ _CBC-DESC @ COMP.CAPS-A @ >=
    _CBC-CAP @ _CBC-DESC @ COMP.CAPS-A @
    _CBC-DESC @ COMP.CAPS-N @ CAP-DESC * + < AND
    _CBC-CAP @ _CBC-DESC @ COMP.CAPS-A @ - CAP-DESC MOD 0= AND ;

: _CBUS-CALL-HANDLER  ( -- )
    _CBD-REQ @ _CBD-INST @ _CBD-CAP @ CAP.HANDLER-XT @ EXECUTE
    _CBD-STATUS ! ;

: CBR-AUTH-BIND!  ( request binding -- status )
    _CBAB-BIND ! _CBAB-REQ !
    _CBAB-REQ @ CBR.CAP @ DUP 0= IF DROP AUTH-S-INVALID EXIT THEN
    _CBAB-CAP !
    _CBAB-BIND @ ABIND-INIT
    _CBAB-REQ @ CBR.EPOCH @ _CBAB-BIND @ ABIND.EPOCH !
    _CBAB-REQ @ CBR.PRINCIPAL @ _CBAB-BIND @ ABIND.PRINCIPAL !
    _CBAB-REQ @ CBR.CONTEXT-ID @ _CBAB-BIND @ ABIND.CONTEXT-ID !
    _CBAB-REQ @ CBR.CONTEXT-GEN @ _CBAB-BIND @ ABIND.CONTEXT-GEN !
    _CBAB-REQ @ CBR.TARGET-ID @ _CBAB-BIND @ ABIND.TARGET-ID !
    _CBAB-REQ @ CBR.TARGET-GEN @ _CBAB-BIND @ ABIND.TARGET-GEN !
    _CBAB-CAP @ CAP.EFFECTS @ _CBAB-BIND @ ABIND.EFFECTS !
    _CBAB-REQ @ CBR.EXPECT-REV @ _CBAB-BIND @ ABIND.EXPECT-REV !
    _CBAB-REQ @ CBR.INVOCATION-ID
        _CBAB-BIND @ ABIND.INVOCATION-ID RID-COPY
    _CBAB-REQ @ CBR.PRACTICE-ID
        _CBAB-BIND @ ABIND.PRACTICE-ID RID-COPY
    _CBAB-REQ @ CBR.MANDATE-ID
        _CBAB-BIND @ ABIND.MANDATE-ID RID-COPY
    _CBAB-REQ @ CBR.ARGS-SEAL-FLAGS @
        _CBAB-BIND @ ABIND.ARGS-SEAL-FLAGS !
    _CBAB-REQ @ CBR.ARGS-LEN @ _CBAB-BIND @ ABIND.ARGS-LEN !
    _CBAB-REQ @ CBR.ARGS-DIGEST _CBAB-BIND @ ABIND.ARGS-DIGEST
        SHA3-256-LEN MOVE
    _CBAB-CAP @ CAP-ID _CBAB-BIND @ ABIND-OP! ;

: CBR-TURN-PREPARE  ( request -- flag )
    DUP _CBTP-REQ ! CBR.CAP @ DUP 0= IF DROP 0 EXIT THEN
    _CBTP-CAP !
    _CBTP-REQ @ CBR.TURN @ ?DUP IF
        _CBTP-TURN !
    ELSE
        PTURN-SIZE ALLOCATE DUP IF 2DROP 0 EXIT THEN
        DROP DUP _CBTP-TURN ! _CBTP-REQ @ CBR.TURN !
    THEN
    _CBTP-TURN @ PTURN-INIT
    _CBTP-REQ @ CBR.INVOCATION-ID
        _CBTP-TURN @ PTURN.INVOCATION-ID RID-COPY
    _CBTP-REQ @ CBR.EPOCH @
        _CBTP-TURN @ PTURN.ACTIVATION-EPOCH !
    _CBTP-REQ @ CBR.CONTEXT-ID @
        _CBTP-TURN @ PTURN.CONTEXT-ID !
    _CBTP-REQ @ CBR.CONTEXT-GEN @
        _CBTP-TURN @ PTURN.CONTEXT-GENERATION !
    _CBTP-REQ @ CBR.TARGET-ID @
        _CBTP-TURN @ PTURN.TARGET-ID !
    _CBTP-REQ @ CBR.TARGET-GEN @
        _CBTP-TURN @ PTURN.TARGET-GENERATION !
    _CBTP-REQ @ CBR.EXPECT-REV @
        _CBTP-TURN @ PTURN.EXPECTED-REVISION !
    _CBTP-CAP @ CAP.EFFECTS @
        _CBTP-TURN @ PTURN.EFFECTS !
    _CBTP-CAP @ CAP-ID _CBTP-TURN @ PTURN-OP! 0= IF
        0 EXIT
    THEN
    _CBTP-TURN @ PTURN-STRUCTURAL-VALID? ;

: _CBUS-BUILD-BINDING  ( -- status )
    _CBD-REQ @ _CBD-BINDING CBR-AUTH-BIND! ;

: _CBUS-POLICY-DECISION  ( -- decision )
    _CBD-REQ @ CBR.PRINCIPAL @ _CBD-CAP @ CAP.EFFECTS @
    _CBD-BUS @ CBUS.POLICY @ CPOLICY-DECIDE ;

: _CBUS-GRANT-CLASS-VALID?  ( grant -- flag )
    _CBD-REQ @ CBR.MANDATE-ID RID-ZERO? IF DROP -1 EXIT THEN
    _CBD-CAP @ CAP.EFFECTS @ CAP-E-OBSERVE = IF
        AGR.FLAGS @ AGR-F-MANDATE-AUTO =
    ELSE
        AGR.FLAGS @ AGR-F-REVIEWED-COMMIT =
    THEN ;

\ Validate and consume at the serialized owner boundary immediately before
\ the handler is entered.  A failing/throwing effect is therefore not
\ silently replayable with the same approval.
: _CBUS-AUTHORITY-GATE  ( -- status )
    _CBD-REQ @ CBR.HANDLE IH-VALID? 0= IF
        _CBUS-POLICY-DECISION CPOL-APPROVAL = IF
            CBUS-S-NEEDS-APPROVAL
        ELSE
            CBUS-S-DENIED
        THEN
        EXIT
    THEN
    _CBUS-BUILD-BINDING ?DUP IF DROP CBUS-S-DENIED EXIT THEN
    MS@ _CBD-BINDING _CBD-REQ @ CBR.HANDLE
    _CBD-BUS @ CBUS.AUTHORITY @ AHT-CONSUME
    DUP AUTH-S-OK = IF
        OVER _CBUS-GRANT-CLASS-VALID? 0= IF
            2DROP CBUS-S-DENIED EXIT
        THEN
        _CBD-REQ @ CBR.TURN @ ?DUP IF
            >R OVER AGR.ID R> PTURN-GRANT!
        THEN
    THEN
    NIP
    CASE
        AUTH-S-OK OF CBUS-S-OK ENDOF
        AUTH-S-EXPIRED OF CBUS-S-EXPIRED-AUTHORITY ENDOF
        AUTH-S-CONSUMED OF CBUS-S-CONSUMED-AUTHORITY ENDOF
        AUTH-S-STALE-HANDLE OF CBUS-S-STALE-AUTHORITY ENDOF
        AUTH-S-REVOKED OF CBUS-S-STALE-AUTHORITY ENDOF
        CBUS-S-DENIED SWAP
    ENDCASE ;

: _CBUS-TURN-REQUIRED?  ( -- flag )
    _CBD-CAP @ CAP.EFFECTS @
    CAP-E-NAVIGATE CAP-E-MUTATE OR CAP-E-PERSIST OR
    CAP-E-DESTRUCTIVE OR CAP-E-EXTERNAL OR AND 0<> ;

: _CBUS-TURN-INDETERMINATE?  ( -- flag )
    _CBD-CAP @ CAP.EFFECTS @
    CAP-E-PERSIST CAP-E-DESTRUCTIVE OR CAP-E-EXTERNAL OR AND 0<> ;

: _CBUS-TURN-FAIL  ( -- )
    _CBUS-TURN-REQUIRED? 0= IF EXIT THEN
    _CBD-REQ @ CBR.TURN @ DUP 0= IF DROP EXIT THEN
    PTURN.STATE @ PTURN-S-RUNNING <> IF EXIT THEN
    _CBUS-TURN-INDETERMINATE? IF
        PTURN-S-INDETERMINATE
    ELSE
        PTURN-S-FAILED
    THEN
    _CBD-REQ @ CBR.TURN @ PTURN-TRANSITION DROP
    MS@ _CBD-REQ @ CBR.TURN @ PTURN.COMPLETED-MS ! ;

\ An exception outside the handler's ordinary status path can occur after a
\ Practice turn began but before owner commit.  At that point the boundary
\ cannot prove whether an external or persistent effect escaped, so a running
\ turn is conservatively indeterminate.  Pending/completed turns are left
\ alone.
: _CBUS-TURN-FAIL-UNEXPECTED  ( -- )
    _CBD-REQ @ CBR.TURN @ DUP 0= IF DROP EXIT THEN
    DUP PTURN.STATE @ PTURN-S-RUNNING <> IF DROP EXIT THEN
    DUP >R PTURN-S-INDETERMINATE SWAP PTURN-TRANSITION DROP
    MS@ R> PTURN.COMPLETED-MS ! ;

: _CBUS-COMPLETE  ( status -- )
    DUP CBUS-S-OK <> IF _CBD-REQ @ CBR.RESULT CV-FREE THEN
    _CBD-REQ @ CBR.STATUS !
    MS@ _CBD-REQ @ CBR.END-MS !
    _CBD-REQ @ CBR-LIFECYCLE-COMPLETE ;

: _CBUS-COMPLETE-CALLBACK  ( request -- )
    DUP 0= IF DROP EXIT THEN
    DUP CBR.COMPLETE-XT @ ?DUP IF EXECUTE ELSE DROP THEN ;

: _CBUS-DISPATCH-BODY  ( running-request bus -- status )
    _CBD-BUS ! DUP _CBD-REQ !
    DUP CBR-ERROR-CLEAR
    DUP CBR.RESULT CV-FREE
    MS@ OVER CBR.START-MS !
    DUP CBR.FLAGS @ CBR-F-CANCELLED AND IF
        DROP CBUS-S-CANCELLED DUP _CBUS-COMPLETE EXIT
    THEN
    DUP CBR.DEADLINE @ ?DUP IF
        MS@ SWAP > IF
            DROP CBUS-S-TIMEOUT DUP _CBUS-COMPLETE EXIT
        THEN
    THEN
    DUP CBR.TARGET-ID @ OVER CBR.TARGET-GEN @
    _CBD-BUS @ CBUS.REGISTRY @ CREG-INST-FIND DUP 0= IF
        DROP DROP CBUS-S-STALE-INSTANCE DUP _CBUS-COMPLETE EXIT
    THEN
    _CBD-INST !
    DUP CBR.CAP @ DUP 0= IF
        2DROP CBUS-S-NOT-FOUND DUP _CBUS-COMPLETE EXIT
    THEN
    _CBD-CAP !
    _CBD-CAP @ _CBD-INST @ _CBUS-CAP-BELONGS? 0= IF
        DROP CBUS-S-NO-HANDLER DUP _CBUS-COMPLETE EXIT
    THEN
    \ Belonging to the descriptor's array is not enough: descriptors can be
    \ mutated after registration, so owner dispatch validates the selected
    \ capability again at the last trusted boundary before using its fields.
    _CBD-CAP @ CAP-DESC-VALID? 0= IF
        DROP CBUS-S-INVALID DUP _CBUS-COMPLETE EXIT
    THEN
    DUP CBR.EXPECT-REV @ ?DUP IF
        _CBD-INST @ CINST.REVISION @ <> IF
            DROP CBUS-S-STALE-REVISION DUP _CBUS-COMPLETE EXIT
        THEN
    THEN
    DUP CBR.ARGS _CBD-CAP @ CAP.IN-SCHEMA @ ?DUP IF
        CS-VALIDATE-DEEP ?DUP IF
            2DROP CBUS-S-INVALID DUP _CBUS-COMPLETE EXIT
        THEN
    ELSE DROP THEN
    _CBD-BUS @ CBUS.AUTHORITY @
    OVER CBR.PRINCIPAL @ CPRINC-AGENT = AND IF
        _CBUS-TURN-REQUIRED? IF
            DUP CBR.TURN @ DUP 0= IF
                DROP 0
            ELSE
                PTURN-STRUCTURAL-VALID?
            THEN 0= IF
                DUP CBR-TURN-PREPARE 0= IF
                    DROP CBUS-S-INVALID DUP _CBUS-COMPLETE EXIT
                THEN
            THEN
        THEN
        _CBUS-AUTHORITY-GATE DUP CBUS-S-OK <> IF
            NIP DUP _CBUS-COMPLETE EXIT
        THEN DROP
        \ The grant binds the creation-time seal fields.  Recompute the
        \ canonical operand after authority consumption but before any turn
        \ or handler entry, so post-review mutation is denied and the one-shot
        \ grant cannot be replayed.
        DUP CBR.ARGS-SEAL-FLAGS @ CBR-ASF-TYPED-IVJSON-SHA3 AND IF
            DUP CBR-ARGS-SEAL-MATCH? 0= IF
                DROP CBUS-S-DENIED DUP _CBUS-COMPLETE EXIT
            THEN
        THEN
        _CBUS-TURN-REQUIRED? IF
            _CBD-INST @ CINST.REVISION @ MS@
            _CBD-REQ @ CBR.TURN @ PTURN-BEGIN 0= IF
                DROP CBUS-S-STALE-AUTHORITY DUP _CBUS-COMPLETE EXIT
            THEN
        THEN
    ELSE
        DUP CBR.FLAGS @ CBR-F-APPROVED AND 0= IF
            _CBUS-POLICY-DECISION
            DUP CPOL-DENY = IF
                2DROP CBUS-S-DENIED DUP _CBUS-COMPLETE EXIT
            THEN
            CPOL-APPROVAL = IF
                DROP CBUS-S-NEEDS-APPROVAL DUP _CBUS-COMPLETE EXIT
            THEN
        THEN
    THEN
    DROP
    _CBD-CAP @ CAP.HANDLER-XT @ 0= IF
        CBUS-S-NOT-FOUND DUP _CBUS-COMPLETE EXIT
    THEN
    CBUS-S-FAILED _CBD-STATUS !
    ['] _CBUS-CALL-HANDLER CATCH
    ?DUP IF
        S" Capability handler threw" ROT _CBD-REQ @ CBR-ERROR!
        _CBUS-TURN-FAIL
        CBUS-S-FAILED DUP _CBUS-COMPLETE EXIT
    THEN
    _CBD-STATUS @ DUP CBUS-S-OK = IF
        _CBD-REQ @ CBR.RESULT _CBD-CAP @ CAP.OUT-SCHEMA @ ?DUP IF
            CS-VALIDATE-DEEP ?DUP IF
                _CBD-REQ @ CBR.RESULT CV-TYPE@ CV-T-INT = IF
                    S" Capability output schema rejected an integer result"
                ELSE
                    S" Capability returned the wrong value type"
                THEN
                ROT _CBD-REQ @ CBR-ERROR!
                _CBUS-TURN-FAIL
                DROP CBUS-S-FAILED DUP _CBUS-COMPLETE EXIT
            THEN
        ELSE DROP THEN
        _CBD-CAP @ CAP.EFFECTS @
        CAP-E-NAVIGATE CAP-E-MUTATE OR CAP-E-PERSIST OR
        CAP-E-DESTRUCTIVE OR AND IF
            _CBD-INST @ CINST-TOUCH
        THEN
        _CBD-INST @ CINST.REVISION @ _CBD-REQ @ CBR.ACTUAL-REV !
        _CBD-REQ @ CBR.TURN @ IF
            _CBD-INST @ CINST.REVISION @ MS@
            _CBD-REQ @ CBR.TURN @ PTURN-OWNER-COMMIT 0= IF
                _CBUS-TURN-FAIL
                DROP CBUS-S-FAILED DUP _CBUS-COMPLETE EXIT
            THEN
        THEN
    ELSE
        _CBUS-TURN-FAIL
    THEN
    DUP _CBUS-COMPLETE ;

: _CBUS-DISPATCH-FRAMED  ( request bus -- status )
    \ Policy, authority, handler, and completion callbacks may all dispatch
    \ synchronously.  Protect the complete dispatch, not merely the handler:
    \ a nested call must restore its caller's scratch before the outer body
    \ resumes.  The fixed frame sits below CATCH's exception frame and is
    \ restored on both normal return and THROW.
    _CBD-REQ @ >R _CBD-INST @ >R _CBD-CAP @ >R _CBD-BUS @ >R
    ['] _CBUS-DISPATCH-BODY CATCH
    ?DUP IF
        \ The request was already claimed RUNNING before this frame.  Convert
        \ every unexpected owner-boundary exception into one terminal failed
        \ completion before restoring the caller's recursive-dispatch scratch.
        S" Capability dispatch threw before lifecycle completion"
        ROT _CBD-REQ @ CBR-ERROR!
        _CBUS-TURN-FAIL-UNEXPECTED
        CBUS-S-FAILED DUP _CBUS-COMPLETE
        >R 2DROP R>
    THEN
    R> _CBD-BUS ! R> _CBD-CAP ! R> _CBD-INST ! R> _CBD-REQ !
    ;

: _CBUS-DISPATCH-CLAIMED-GUARDED  ( running-request bus -- status )
    1 _CBUS-DISPATCH-DEPTH +!
    ['] _CBUS-DISPATCH-FRAMED CATCH
    -1 _CBUS-DISPATCH-DEPTH +!
    ?DUP IF THROW THEN ;

: _CBUS-DISPATCH-DIRECT-GUARDED  ( request bus -- status callback-request|0 )
    OVER 0= IF 2DROP CBUS-S-INVALID 0 EXIT THEN
    OVER CBR-LIFECYCLE-RUN 0= IF 2DROP CBUS-S-BUSY 0 EXIT THEN
    OVER >R
    _CBUS-DISPATCH-CLAIMED-GUARDED
    R> ;

: CBUS-DISPATCH  ( request bus -- status )
    \ A direct call may only claim an idle or completed envelope.  Callback
    \ eligibility travels on the data stack so recursive dispatch cannot
    \ overwrite shared scratch; rejected calls have no completion event.
    ['] _CBUS-DISPATCH-DIRECT-GUARDED _CBUS-DISPATCH-GUARD WITH-GUARD
    ?DUP IF _CBUS-COMPLETE-CALLBACK THEN ;

VARIABLE _CBP-BUS
VARIABLE _CBP-N

: _CBUS-PUMP-QUIESCED  ( max bus -- count )
    _CBP-BUS ! 0 _CBP-N !
    0 ?DO
        _CBP-BUS @ _CBUS-POP-CLAIM-QUIESCED ?DUP 0= IF LEAVE THEN
        DUP >R _CBP-BUS @ _CBUS-DISPATCH-CLAIMED-GUARDED
        R> _CBUS-COMPLETE-CALLBACK DROP
        1 _CBP-N +!
    LOOP
    _CBP-N @ ;

: _CBUS-PUMP-FRAMED  ( max bus -- count )
    _CBP-BUS @ >R _CBP-N @ >R
    ['] _CBUS-PUMP-QUIESCED CATCH
    R> _CBP-N ! R> _CBP-BUS !
    ?DUP IF THROW THEN ;

: _CBUS-PUMP-GUARDED  ( max bus -- count )
    1 _CBUS-OWNER-OP-DEPTH +!
    ['] _CBUS-PUMP-FRAMED CATCH
    -1 _CBUS-OWNER-OP-DEPTH +!
    ?DUP IF THROW THEN ;

: CBUS-PUMP  ( max bus -- count )
    ['] _CBUS-PUMP-GUARDED CBUS-WITH-DISPATCH-QUIESCED ;

VARIABLE _CBCA-BUS
VARIABLE _CBCA-N

: _CBUS-CANCEL-ALL-QUIESCED  ( bus -- count )
    _CBCA-BUS ! 0 _CBCA-N !
    BEGIN
        _CBCA-BUS @ _CBUS-POP ?DUP
    WHILE
        \ WHILE consumes the duplicated truth value and leaves the request;
        \ store that original instead of retaining one pointer per cancelled
        \ ring entry on the caller's data stack.
        _CBD-REQ !
        _CBCA-BUS @ _CBD-BUS !
        CBUS-S-CANCELLED _CBUS-COMPLETE
        _CBD-REQ @ _CBUS-COMPLETE-CALLBACK
        1 _CBCA-N +!
    REPEAT
    _CBCA-N @ ;

: _CBUS-CANCEL-ALL-FRAMED  ( bus -- count )
    _CBCA-BUS @ >R _CBCA-N @ >R
    _CBD-REQ @ >R _CBD-INST @ >R _CBD-CAP @ >R _CBD-BUS @ >R
    ['] _CBUS-CANCEL-ALL-QUIESCED CATCH
    R> _CBD-BUS ! R> _CBD-CAP ! R> _CBD-INST ! R> _CBD-REQ !
    R> _CBCA-N ! R> _CBCA-BUS !
    ?DUP IF THROW THEN ;

: _CBUS-CANCEL-ALL-GUARDED  ( bus -- count )
    1 _CBUS-OWNER-OP-DEPTH +!
    ['] _CBUS-CANCEL-ALL-FRAMED CATCH
    -1 _CBUS-OWNER-OP-DEPTH +!
    ?DUP IF THROW THEN ;

: CBUS-CANCEL-ALL  ( bus -- count )
    ['] _CBUS-CANCEL-ALL-GUARDED CBUS-WITH-DISPATCH-QUIESCED ;

: _CBR-APPROVE  ( request -- )
    DUP CBR.FLAGS DUP @ CBR-F-APPROVED OR SWAP !
    0 SWAP CBR.STATUS ! ;

: CBR-APPROVE  ( request -- )
    ['] _CBR-APPROVE WITH-CBR-LIFECYCLE ;

: _CBR-CANCEL  ( request -- )
    CBR.FLAGS DUP @ CBR-F-CANCELLED OR SWAP ! ;

: CBR-CANCEL  ( request -- )
    ['] _CBR-CANCEL WITH-CBR-LIFECYCLE ;
