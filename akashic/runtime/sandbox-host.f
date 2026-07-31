\ =====================================================================
\  sandbox-host.f - Thin Akashic lifecycle owner for one sandbox run
\ =====================================================================
\  Module installation and exact module revision resolution belong to
\  sandbox-module-owner.f.  This layer accepts one already resolved verified
\  plan and exact entry, creates a fresh capability-empty child Context, and
\  owns every mutable allocation used by one typed VM invocation.
\
\  The caller owns one zeroed, aligned SBOX-HOST-INVOCATION-SIZE-byte
\  descriptor and the canonical input/result buffers.  INIT copies the input
\  into a private arena.  FINISH publishes through SBOX-VM's disjoint canonical
\  result boundary and then destroys the child Context and all invocation
\  storage.  RELEASE performs the same cleanup without publishing a result.
\  Until either succeeds, the parent Context must remain allocated and the
\  resolved plan and its profile remain borrowed.  CANCEL and failed FINISH do
\  not end those borrows.
\
\  INIT receives already materialized value and execution limits from the
\  trusted activation-policy layer.  It enforces the plan profile's hard
\  ceilings; combining Context, Practice, declaration, and request policy is
\  deliberately not duplicated in this lifecycle owner.
\
\  There is no Desk, Agent, Practice persistence, module declaration, schema,
\  digest, cache, capability, VFS, network, or native callback behavior here.
\ =====================================================================

PROVIDED akashic-sbox-host

REQUIRE context.f
REQUIRE ../sandbox/vm.f

\ =====================================================================
\  Status and fixed caller-owned descriptor
\ =====================================================================

0  CONSTANT SBOX-HOST-S-OK
1  CONSTANT SBOX-HOST-S-INVALID
2  CONSTANT SBOX-HOST-S-CONTEXT
3  CONSTANT SBOX-HOST-S-ENTRY
4  CONSTANT SBOX-HOST-S-INPUT
5  CONSTANT SBOX-HOST-S-BUDGET
6  CONSTANT SBOX-HOST-S-NOMEM
7  CONSTANT SBOX-HOST-S-VM
8  CONSTANT SBOX-HOST-S-STATE
9  CONSTANT SBOX-HOST-S-RESULT
10 CONSTANT SBOX-HOST-S-ALIAS
11 CONSTANT SBOX-HOST-S-NOT-FOUND

: SBOX-HOST-STATUS-VALID?  ( status -- flag )
    DUP SBOX-HOST-S-OK >=
    SWAP SBOX-HOST-S-NOT-FOUND <= AND ;

1 CONSTANT _SHOST-PHASE-HOST-OWNS
2 CONSTANT _SHOST-PHASE-VM-OWNS

0x53424F58484F5354 CONSTANT _SHOST-MAGIC  \ "SBOXHOST"

  0 CONSTANT _SHI-MAGIC
  8 CONSTANT _SHI-SELF
 16 CONSTANT _SHI-STATE
 24 CONSTANT _SHI-CHILD
 32 CONSTANT _SHI-CHILD-ID
 40 CONSTANT _SHI-CHILD-GENERATION
 48 CONSTANT _SHI-PLAN
 56 CONSTANT _SHI-ENTRY
 64 CONSTANT _SHI-PARENT
 72 CONSTANT _SHI-TEMP-SOURCE
 80 CONSTANT _SHI-TEMP-SOURCE-U
 88 CONSTANT _SHI-TEMP-LIMITS
 96 CONSTANT _SHI-INSTRUCTION-BUDGET
104 CONSTANT _SHI-VALUE-OP-BUDGET
112 CONSTANT _SHI-COPY-BUDGET
120 CONSTANT _SHI-INPUT
128 CONSTANT _SHI-INPUT-U
136 CONSTANT _SHI-OUTPUT
144 CONSTANT _SHI-OUTPUT-U
152 CONSTANT _SHI-WORK
160 CONSTANT _SHI-WORK-U
168 CONSTANT _SHI-VM
176 CONSTANT _SHI-VM-U
184 CONSTANT _SHI-LIMITS
288 CONSTANT _SHI-BINDING
352 CONSTANT _SHI-VALUE-STATE
512 CONSTANT SBOX-HOST-INVOCATION-SIZE

: _SHI.MAGIC               ( host -- address ) _SHI-MAGIC + ;
: _SHI.SELF                ( host -- address ) _SHI-SELF + ;
: _SHI.STATE               ( host -- address ) _SHI-STATE + ;
: _SHI.CHILD               ( host -- address ) _SHI-CHILD + ;
: _SHI.CHILD-ID            ( host -- address ) _SHI-CHILD-ID + ;
: _SHI.CHILD-GENERATION    ( host -- address ) _SHI-CHILD-GENERATION + ;
: _SHI.PLAN                ( host -- address ) _SHI-PLAN + ;
: _SHI.ENTRY               ( host -- address ) _SHI-ENTRY + ;
: _SHI.PARENT              ( host -- address ) _SHI-PARENT + ;
: _SHI.TEMP-SOURCE         ( host -- address ) _SHI-TEMP-SOURCE + ;
: _SHI.TEMP-SOURCE-U       ( host -- address ) _SHI-TEMP-SOURCE-U + ;
: _SHI.TEMP-LIMITS         ( host -- address ) _SHI-TEMP-LIMITS + ;
: _SHI.INSTRUCTION-BUDGET  ( host -- address ) _SHI-INSTRUCTION-BUDGET + ;
: _SHI.VALUE-OP-BUDGET     ( host -- address ) _SHI-VALUE-OP-BUDGET + ;
: _SHI.COPY-BUDGET         ( host -- address ) _SHI-COPY-BUDGET + ;
: _SHI.INPUT               ( host -- address ) _SHI-INPUT + ;
: _SHI.INPUT-U             ( host -- address ) _SHI-INPUT-U + ;
: _SHI.OUTPUT              ( host -- address ) _SHI-OUTPUT + ;
: _SHI.OUTPUT-U            ( host -- address ) _SHI-OUTPUT-U + ;
: _SHI.WORK                ( host -- address ) _SHI-WORK + ;
: _SHI.WORK-U              ( host -- address ) _SHI-WORK-U + ;
: _SHI.VM                  ( host -- address ) _SHI-VM + ;
: _SHI.VM-U                ( host -- address ) _SHI-VM-U + ;
: _SHI.LIMITS              ( host -- limits ) _SHI-LIMITS + ;
: _SHI.BINDING             ( host -- binding ) _SHI-BINDING + ;
: _SHI.VALUE-STATE         ( host -- state ) _SHI-VALUE-STATE + ;

: _SHOST-SPAN?  ( address length -- flag )
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    CALLER-SPAN-STATUS CALLER-SPAN-S-OK = ;

: _SHOST-FIXED-SPAN?  ( host -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    SBOX-HOST-INVOCATION-SIZE _SHOST-SPAN? ;

: _SHOST-ZERO?  ( host -- flag )
    SBOX-HOST-INVOCATION-SIZE 0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _SHOST-HEADER?  ( host -- flag )
    DUP _SHOST-FIXED-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _SHI.MAGIC @ _SHOST-MAGIC <> IF DROP 0 EXIT THEN
    DUP _SHI.SELF @ OVER <> IF DROP 0 EXIT THEN
    DUP _SHI.STATE @ _SHOST-PHASE-VM-OWNS <> IF DROP 0 EXIT THEN
    DUP _SHI.PARENT @ 0= IF DROP 0 EXIT THEN
    DUP _SHI.CHILD-ID @ 0> 0= IF DROP 0 EXIT THEN
    DUP _SHI.CHILD-GENERATION @ 0> 0= IF DROP 0 EXIT THEN
    DUP _SHI.TEMP-SOURCE @ IF DROP 0 EXIT THEN
    DUP _SHI.TEMP-SOURCE-U @ IF DROP 0 EXIT THEN
    DUP _SHI.TEMP-LIMITS @ IF DROP 0 EXIT THEN
    DROP -1 ;

\ A child may retain trusted host-only Practice/owner/policy metadata copied
\ by CTX-CHILD-NEW.  The guest cannot reach that Context.  The service and
\ capability surfaces checked below must remain absent from the activation.
: _SHOST-CHILD-EMPTY?  ( child -- flag )
    DUP CTX-VALID? 0= IF DROP 0 EXIT THEN
    DUP CTX.FLAGS @ CTX-F-ACTIVE AND 0<>
    OVER CTX.FLAGS @ CTX-F-DISPOSABLE AND 0<> AND
    OVER CTX.BINDINGS @ 0= AND
    OVER CTX.FACETS @ 0= AND
    OVER CTX.AUTHORITY @ 0= AND
    OVER CTX.QUEUE @ 0= AND
    OVER CTX.WORDSET @ 0= AND
    SWAP CTX.VFS @ 0= AND ;

: _SHOST-CHILD-PARENT?  ( child parent -- flag )
    >R
    DUP CTX-VALID? 0= IF DROP R> DROP 0 EXIT THEN
    R@ CTX-VALID? 0= IF DROP R> DROP 0 EXIT THEN
    DUP CTX.PARENT-ID @ R@ CTX.ID @ =
    SWAP CTX.PARENT-GENERATION @ R@ CTX.GENERATION @ = AND
    R> DROP ;

: _SHOST-CHILD-MATCH?  ( host -- flag )
    >R
    R@ _SHI.CHILD @ DUP CTX-VALID? 0= IF
        DROP R> DROP 0 EXIT
    THEN
    DUP CTX.ID @ R@ _SHI.CHILD-ID @ =
    SWAP CTX.GENERATION @ R@ _SHI.CHILD-GENERATION @ = AND
    R> DROP ;

: _SHOST-ENTRY-TYPED?  ( entry plan -- flag )
    >R
    DUP 0< IF DROP R> DROP 0 EXIT THEN
    DUP R@ SBOX-PLAN-ENTRY-N@ >= IF DROP R> DROP 0 EXIT THEN
    R@ SBOX-PLAN-ENTRY-SIGNATURE@
    0= IF DROP R> DROP 0 EXIT THEN
    SBOX-ABI-SIGNATURE-VALUE-TO-VALUE =
    R> DROP ;

: _SHOST-LIMITS-COPY  ( source destination -- status )
    OVER SBOX-VALUE-LIMITS-VALID? 0= IF
        2DROP SBOX-VALUE-S-STATE EXIT
    THEN
    DUP SBOX-VALUE-LIMITS-BEGIN
    DUP IF -ROT 2DROP EXIT THEN
    DROP
    SBOX-VALUE-LIMIT-COUNT 0 ?DO
        I 2 PICK SBOX-VALUE-LIMIT@
        DUP IF
            2DROP 2DROP
            SBOX-VALUE-S-STATE UNLOOP EXIT
        THEN
        DROP
        I 2 PICK SBOX-VALUE-LIMIT!
        DUP IF -ROT 2DROP UNLOOP EXIT THEN
        DROP
    LOOP
    NIP SBOX-VALUE-LIMITS-SEAL ;

: _SHOST-DYNAMIC-DISJOINT?  ( host -- flag )
    >R
    R@ _SHI.CHILD @ CTX-SIZE
        R@ SBOX-HOST-INVOCATION-SIZE MSPAN-OVERLAP? IF
        R> DROP 0 EXIT
    THEN
    R@ _SHI.INPUT @ R@ _SHI.INPUT-U @
        R@ SBOX-HOST-INVOCATION-SIZE MSPAN-OVERLAP? IF
        R> DROP 0 EXIT
    THEN
    R@ _SHI.OUTPUT @ R@ _SHI.OUTPUT-U @
        R@ SBOX-HOST-INVOCATION-SIZE MSPAN-OVERLAP? IF
        R> DROP 0 EXIT
    THEN
    R@ _SHI.WORK @ R@ _SHI.WORK-U @
        R@ SBOX-HOST-INVOCATION-SIZE MSPAN-OVERLAP? IF
        R> DROP 0 EXIT
    THEN
    R@ _SHI.VM @ R@ _SHI.VM-U @
        R@ SBOX-HOST-INVOCATION-SIZE MSPAN-OVERLAP? 0=
    R> DROP ;

: _SHOST-VM-MATCH?  ( host -- flag )
    >R
    R@ _SHI.PLAN @
    R@ _SHI.BINDING
    R@ _SHI.VALUE-STATE
    R@ _SHI.WORK @
    R@ _SHI.WORK-U @
    R@ _SHI.VM @
    SBOX-VM-INSTANCE-BOUND?
    R> DROP ;

: _SHOST-INPUT-MATCH?  ( host -- flag )
    >R
    R@ _SHI.VALUE-STATE SBOX-VALUE-STATE-INPUT-SPAN@
    DUP IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    DROP
    R@ _SHI.INPUT-U @ =
    SWAP R@ _SHI.INPUT @ = AND
    R> DROP ;

: _SHOST-OUTPUT-MATCH?  ( host -- flag )
    >R
    R@ _SHI.VALUE-STATE SBOX-VALUE-STATE-OUTPUT-SPAN@
    DUP IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    DROP
    R@ _SHI.OUTPUT-U @ =
    SWAP R@ _SHI.OUTPUT @ = AND
    R> DROP ;

: _SHOST-ATTACHED?  ( host -- flag )
    DUP _SHOST-HEADER? 0= IF DROP 0 EXIT THEN
    DUP _SHOST-CHILD-MATCH? 0= IF DROP 0 EXIT THEN
    DUP _SHI.CHILD @ _SHOST-CHILD-EMPTY? 0= IF DROP 0 EXIT THEN
    DUP _SHI.CHILD @ OVER _SHI.PARENT @
        _SHOST-CHILD-PARENT? 0= IF DROP 0 EXIT THEN
    _SHOST-VM-MATCH? ;

: _SHOST-OWNED?  ( host -- flag )
    DUP _SHOST-ATTACHED? 0= IF DROP 0 EXIT THEN
    DUP _SHI.LIMITS SBOX-VALUE-LIMITS-VALID? 0= IF DROP 0 EXIT THEN
    DUP _SHI.PLAN @ SBOX-PLAN-VALID? 0= IF DROP 0 EXIT THEN
    DUP _SHI.ENTRY @ OVER _SHI.PLAN @
        _SHOST-ENTRY-TYPED? 0= IF DROP 0 EXIT THEN
    DUP _SHI.PLAN @ OVER _SHI.BINDING
        SBOX-BINDING-VALID-FOR? 0= IF DROP 0 EXIT THEN
    DUP _SHI.VM @ SBOX-VM-INSTANCE-VALID? 0= IF DROP 0 EXIT THEN
    DUP _SHOST-INPUT-MATCH? 0= IF DROP 0 EXIT THEN
    DUP _SHOST-OUTPUT-MATCH? 0= IF DROP 0 EXIT THEN
    DUP _SHI.PLAN @ SBOX-VM-INSTANCE-MEASURE
    DUP IF 2DROP DROP 0 EXIT THEN
    DROP
    OVER _SHI.VM-U @ <> IF DROP 0 EXIT THEN
    _SHOST-DYNAMIC-DISJOINT? ;

: SBOX-HOST-VALID?  ( host -- flag )
    DUP _SHOST-OWNED? 0= IF DROP 0 EXIT THEN
    _SHI.PARENT @ CTX.FLAGS @ CTX-F-ACTIVE AND 0<> ;

: _SHOST-ACTIVE?  ( host -- flag )
    DUP _SHOST-ATTACHED? 0= IF DROP 0 EXIT THEN
    _SHI.PARENT @ CTX.FLAGS @ CTX-F-ACTIVE AND 0<> ;

\ =====================================================================
\  Exact entry selection
\ =====================================================================

: SBOX-HOST-ENTRY-RESOLVE-EXACT
  ( name name-u plan -- entry|-1 status )
    DUP SBOX-PLAN-VALID? 0= IF
        2DROP DROP -1 SBOX-HOST-S-INVALID EXIT
    THEN
    1 PICK 0> 0= IF
        2DROP DROP -1 SBOX-HOST-S-ENTRY EXIT
    THEN
    2 PICK 2 PICK _SHOST-SPAN? 0= IF
        2DROP DROP -1 SBOX-HOST-S-INVALID EXIT
    THEN
    DUP SBOX-PLAN-ENTRY-N@ 0 ?DO
        I OVER SBOX-PLAN-ENTRY-NAME$
        4 PICK 4 PICK COMPARE 0= IF
            2DROP DROP I SBOX-HOST-S-OK UNLOOP EXIT
        THEN
    LOOP
    2DROP DROP -1 SBOX-HOST-S-NOT-FOUND ;

\ =====================================================================
\  Setup helpers
\ =====================================================================

: _SHOST-DROP5  ( x1 x2 x3 x4 x5 -- )
    2DROP 2DROP DROP ;

: _SHOST-STATIC-DISJOINT?
  ( parent plan source source-u limits host -- flag )
    >R
    4 PICK CTX-SIZE
        R@ SBOX-HOST-INVOCATION-SIZE MSPAN-OVERLAP? IF
        _SHOST-DROP5 R> DROP 0 EXIT
    THEN
    3 PICK DUP SBOX-PLAN-TOTAL@
        R@ SBOX-HOST-INVOCATION-SIZE MSPAN-OVERLAP? IF
        _SHOST-DROP5 R> DROP 0 EXIT
    THEN
    3 PICK SBOX-PLAN-PROFILE@ SBOX-PROFILE-SIZE
        R@ SBOX-HOST-INVOCATION-SIZE MSPAN-OVERLAP? IF
        _SHOST-DROP5 R> DROP 0 EXIT
    THEN
    2 PICK 2 PICK
        R@ SBOX-HOST-INVOCATION-SIZE MSPAN-OVERLAP? IF
        _SHOST-DROP5 R> DROP 0 EXIT
    THEN
    DUP SBOX-VALUE-LIMITS-SIZE
        R@ SBOX-HOST-INVOCATION-SIZE MSPAN-OVERLAP? IF
        _SHOST-DROP5 R> DROP 0 EXIT
    THEN
    _SHOST-DROP5 R> DROP -1 ;

: _SHOST-BUDGET-WITHIN?  ( requested field plan -- flag )
    SBOX-PLAN-PROFILE@ SBOX-PROFILE-LIMIT@
    DUP IF
        2DROP DROP 0 EXIT
    THEN
    DROP U> 0= ;

\ Stack input:
\   parent plan entry source source-u limits
\   instruction-budget value-op-budget copy-budget host
\ Stack output: the same ten inputs followed by status.
: _SHOST-INIT-BOUNDARY
    DUP _SHOST-FIXED-SPAN? 0= IF SBOX-HOST-S-INVALID EXIT THEN
    DUP _SHOST-ZERO? 0= IF SBOX-HOST-S-STATE EXIT THEN
    9 PICK CTX-VALID? 0= IF SBOX-HOST-S-CONTEXT EXIT THEN
    9 PICK CTX.FLAGS @ CTX-F-ACTIVE AND 0= IF
        SBOX-HOST-S-CONTEXT EXIT
    THEN
    8 PICK SBOX-PLAN-VALID? 0= IF SBOX-HOST-S-INVALID EXIT THEN
    7 PICK 9 PICK _SHOST-ENTRY-TYPED? 0= IF
        SBOX-HOST-S-ENTRY EXIT
    THEN
    5 PICK 0> 0= IF SBOX-HOST-S-INPUT EXIT THEN
    6 PICK 6 PICK _SHOST-SPAN? 0= IF SBOX-HOST-S-INPUT EXIT THEN
    4 PICK SBOX-VALUE-LIMITS-VALID? 0= IF
        SBOX-HOST-S-INPUT EXIT
    THEN
    3 PICK 0> 0= IF SBOX-HOST-S-BUDGET EXIT THEN
    2 PICK 0> 0= IF SBOX-HOST-S-BUDGET EXIT THEN
    1 PICK 0> 0= IF SBOX-HOST-S-BUDGET EXIT THEN
    3 PICK SBOX-PROFILE-LIMIT-MAX-BUDGET 10 PICK
        _SHOST-BUDGET-WITHIN? 0= IF SBOX-HOST-S-BUDGET EXIT THEN
    2 PICK SBOX-PROFILE-LIMIT-VALUE-OPS 10 PICK
        _SHOST-BUDGET-WITHIN? 0= IF SBOX-HOST-S-BUDGET EXIT THEN
    1 PICK SBOX-PROFILE-LIMIT-COPY-BYTES 10 PICK
        _SHOST-BUDGET-WITHIN? 0= IF SBOX-HOST-S-BUDGET EXIT THEN

    9 PICK 9 PICK 8 PICK 8 PICK 8 PICK 5 PICK
        _SHOST-STATIC-DISJOINT? 0= IF
        SBOX-HOST-S-ALIAS EXIT
    THEN
    SBOX-HOST-S-OK ;

: _SHOST-ALLOCATE  ( bytes pointer-cell length-cell -- status )
    >R >R
    DUP 0> 0= IF
        DROP R> DROP R> DROP SBOX-HOST-S-INVALID EXIT
    THEN
    DUP ALLOCATE
    DUP IF
        >R 2DROP R> DROP
        R> DROP R> DROP SBOX-HOST-S-NOMEM EXIT
    THEN
    DROP
    DUP 0= IF
        2DROP R> DROP R> DROP SBOX-HOST-S-NOMEM EXIT
    THEN
    DUP R@ !
    R> DROP
    OVER R@ !
    2DROP R> DROP
    SBOX-HOST-S-OK ;

: _SHOST-SCRUB-FREE  ( address length -- )
    OVER 0= IF 2DROP EXIT THEN
    DUP 0> IF 2DUP 0 FILL THEN
    DROP FREE ;

: _SHOST-SETUP-CHILD  ( host -- status )
    DUP _SHI.PARENT @ CTX-CHILD-NEW
    DUP IF
        >R 2DROP R> DROP SBOX-HOST-S-NOMEM EXIT
    THEN
    DROP
    DUP 2 PICK _SHI.CHILD !
    DUP CTX.ID @ 2 PICK _SHI.CHILD-ID !
    DUP CTX.GENERATION @ 2 PICK _SHI.CHILD-GENERATION !
    2DROP SBOX-HOST-S-OK ;

: _SHOST-SETUP-BINDING  ( host -- status )
    DUP _SHI.PLAN @ OVER _SHI.BINDING
        SBOX-BINDING-PURE-INIT
    SBOX-BINDING-S-OK = IF
        DROP SBOX-HOST-S-OK
    ELSE
        DROP SBOX-HOST-S-VM
    THEN ;

: _SHOST-SETUP-LIMITS  ( host -- status )
    DUP _SHI.TEMP-LIMITS @
    OVER _SHI.LIMITS
    _SHOST-LIMITS-COPY
    SBOX-VALUE-S-OK = IF
        DROP SBOX-HOST-S-OK
    ELSE
        DROP SBOX-HOST-S-INPUT
    THEN ;

: _SHOST-SETUP-WORK  ( host -- status )
    DUP _SHI.LIMITS SBOX-VALUE-WORK-MEASURE
    DUP IF
        2DROP DROP SBOX-HOST-S-INPUT EXIT
    THEN
    DROP
    OVER _SHI.WORK
    2 PICK _SHI.WORK-U
    _SHOST-ALLOCATE NIP ;

: _SHOST-SETUP-INPUT  ( host -- status )
    >R
    R@ _SHI.TEMP-SOURCE @
    R@ _SHI.TEMP-SOURCE-U @
    R@ _SHI.LIMITS
    R@ _SHI.WORK @
    R@ _SHI.WORK-U @
    SBOX-VALUE-INPUT-MEASURE
    DUP IF
        2DROP 2DROP DROP R> DROP SBOX-HOST-S-INPUT EXIT
    THEN
    DROP 2DROP DROP
    R@ _SHI.INPUT
    R@ _SHI.INPUT-U
    _SHOST-ALLOCATE
    DUP IF R> DROP EXIT THEN
    DROP

    R@ _SHI.TEMP-SOURCE @
    R@ _SHI.TEMP-SOURCE-U @
    R@ _SHI.LIMITS
    R@ _SHI.WORK @
    R@ _SHI.WORK-U @
    R@ _SHI.INPUT @
    R@ _SHI.INPUT-U @
    SBOX-VALUE-INPUT-DECODE
    DUP IF
        2DROP R> DROP SBOX-HOST-S-INPUT EXIT
    THEN
    DROP 1 <> IF
        R> DROP SBOX-HOST-S-INPUT EXIT
    THEN
    R> DROP SBOX-HOST-S-OK ;

: _SHOST-SETUP-OUTPUT  ( host -- status )
    >R
    R@ _SHI.LIMITS SBOX-VALUE-OUTPUT-MEASURE
    DUP IF
        2DROP R> DROP SBOX-HOST-S-INPUT EXIT
    THEN
    DROP
    R@ _SHI.OUTPUT
    R@ _SHI.OUTPUT-U
    _SHOST-ALLOCATE
    DUP IF R> DROP EXIT THEN
    DROP
    R@ _SHI.LIMITS
    R@ _SHI.OUTPUT @
    R@ _SHI.OUTPUT-U @
    SBOX-VALUE-OUTPUT-INIT
    SBOX-VALUE-S-OK <> IF
        R> DROP SBOX-HOST-S-INPUT EXIT
    THEN
    R> DROP SBOX-HOST-S-OK ;

: _SHOST-SETUP-STATE  ( host -- status )
    >R
    R@ _SHI.INPUT @
    R@ _SHI.OUTPUT @
    R@ _SHI.VALUE-STATE
    SBOX-VALUE-STATE-INIT
    SBOX-VALUE-S-OK =
    R> DROP
    IF SBOX-HOST-S-OK ELSE SBOX-HOST-S-INPUT THEN ;

: _SHOST-SETUP-VM  ( host -- status )
    >R
    R@ _SHI.PLAN @ SBOX-VM-INSTANCE-MEASURE
    DUP IF
        2DROP R> DROP SBOX-HOST-S-VM EXIT
    THEN
    DROP
    R@ _SHI.VM
    R@ _SHI.VM-U
    _SHOST-ALLOCATE
    DUP IF R> DROP EXIT THEN
    DROP

    R@ _SHI.PLAN @
    R@ _SHI.BINDING
    R@ _SHI.ENTRY @
    R@ _SHI.VALUE-STATE
    R@ _SHI.WORK @
    R@ _SHI.WORK-U @
    R@ _SHI.INSTRUCTION-BUDGET @
    R@ _SHI.VALUE-OP-BUDGET @
    R@ _SHI.COPY-BUDGET @
    R@ _SHI.VM @
    R@ _SHI.VM-U @
    SBOX-VM-INIT
    SBOX-VM-S-OK = IF
        _SHOST-PHASE-VM-OWNS R@ _SHI.STATE !
        R> DROP SBOX-HOST-S-OK
    ELSE
        R> DROP SBOX-HOST-S-VM
    THEN ;

: _SHOST-SETUP  ( host -- status )
    DUP _SHOST-SETUP-BINDING DUP IF NIP EXIT THEN DROP
    DUP _SHOST-SETUP-LIMITS DUP IF NIP EXIT THEN DROP
    DUP _SHOST-SETUP-WORK DUP IF NIP EXIT THEN DROP
    DUP _SHOST-SETUP-INPUT DUP IF NIP EXIT THEN DROP
    DUP _SHOST-SETUP-OUTPUT DUP IF NIP EXIT THEN DROP
    DUP _SHOST-SETUP-STATE DUP IF NIP EXIT THEN DROP
    DUP _SHOST-SETUP-VM DUP IF NIP EXIT THEN DROP
    _SHOST-SETUP-CHILD ;

\ =====================================================================
\  Cleanup and public invocation lifecycle
\ =====================================================================

: _SHOST-CLEANUP  ( host -- )
    >R
    R@ _SHI.STATE @ _SHOST-PHASE-VM-OWNS = IF
        R@ _SHI.VM @ ?DUP IF SBOX-VM-RELEASE DROP THEN
    THEN
    R@ _SHI.VM @ R@ _SHI.VM-U @ _SHOST-SCRUB-FREE
    R@ _SHI.WORK @ R@ _SHI.WORK-U @ _SHOST-SCRUB-FREE
    R@ _SHI.OUTPUT @ R@ _SHI.OUTPUT-U @ _SHOST-SCRUB-FREE
    R@ _SHI.INPUT @ R@ _SHI.INPUT-U @ _SHOST-SCRUB-FREE
    R@ _SHI.CHILD @ ?DUP IF
        0 OVER CTX.FLAGS !
        CTX-FREE
    THEN
    R@ SBOX-HOST-INVOCATION-SIZE 0 FILL
    R> DROP ;

\ Successful FINISH has causally scrubbed these exact host-owned buffers.
\ The private VM release checks that terminal seal and clears only its live
\ descriptor; an impossible causal failure falls back to generic cleanup.
: _SHOST-FREE-ZEROED  ( address -- )
    ?DUP IF FREE THEN ;

: _SHOST-CLEANUP-FINISHED  ( host -- )
    DUP _SHI.VM @ _SVM-RELEASE-FINISHED-VALIDATED
    SBOX-VM-S-OK <> IF
        _SHOST-CLEANUP EXIT
    THEN
    >R
    R@ _SHI.VM @ _SHOST-FREE-ZEROED
    R@ _SHI.WORK @ _SHOST-FREE-ZEROED
    R@ _SHI.OUTPUT @ _SHOST-FREE-ZEROED
    R@ _SHI.INPUT @ _SHOST-FREE-ZEROED
    R@ _SHI.CHILD @ ?DUP IF
        0 OVER CTX.FLAGS !
        CTX-FREE
    THEN
    R@ SBOX-HOST-INVOCATION-SIZE 0 FILL
    R> DROP ;

: _SHOST-DROP10
  ( x1 x2 x3 x4 x5 x6 x7 x8 x9 x10 -- )
    2DROP 2DROP 2DROP 2DROP 2DROP ;

\ Stack input:
\   parent plan entry source source-u limits
\   instruction-budget value-op-budget copy-budget host
\ Stack output: status.
: SBOX-HOST-INIT
    _SHOST-INIT-BOUNDARY
    DUP IF
        >R _SHOST-DROP10 R> EXIT
    THEN
    DROP

    DUP >R
    R@ SBOX-HOST-INVOCATION-SIZE 0 FILL
    R@ R@ _SHI.SELF !
    _SHOST-PHASE-HOST-OWNS R@ _SHI.STATE !
    9 PICK R@ _SHI.PARENT !
    8 PICK R@ _SHI.PLAN !
    7 PICK R@ _SHI.ENTRY !
    6 PICK R@ _SHI.TEMP-SOURCE !
    5 PICK R@ _SHI.TEMP-SOURCE-U !
    4 PICK R@ _SHI.TEMP-LIMITS !
    3 PICK R@ _SHI.INSTRUCTION-BUDGET !
    2 PICK R@ _SHI.VALUE-OP-BUDGET !
    1 PICK R@ _SHI.COPY-BUDGET !

    R@ _SHOST-SETUP
    DUP IF
        R@ _SHOST-CLEANUP
        >R _SHOST-DROP10 R> R> DROP EXIT
    THEN
    DROP

    R@ _SHI.CHILD @ DUP CTX.FLAGS @ CTX-F-ACTIVE OR
        OVER CTX.FLAGS !
    CTX-TOUCH
    0 R@ _SHI.TEMP-SOURCE !
    0 R@ _SHI.TEMP-SOURCE-U !
    0 R@ _SHI.TEMP-LIMITS !
    _SHOST-MAGIC R@ _SHI.MAGIC !

    R@ SBOX-HOST-VALID? 0= IF
        R@ _SHOST-CLEANUP
        _SHOST-DROP10 R> DROP SBOX-HOST-S-INVALID EXIT
    THEN
    _SHOST-DROP10 R> DROP SBOX-HOST-S-OK ;

: SBOX-HOST-RUN-STATE@  ( host -- run-state )
    DUP _SHOST-ACTIVE? 0= IF
        DROP SBOX-VM-RUN-INVALID EXIT
    THEN
    _SHI.VM @ SBOX-VM-RUN-STATE@ ;

: _SHOST-RUN-STATE-VALIDATED  ( host -- run-state )
    _SHI.VM @ _SVI.RUN-STATE @ ;

: _SHOST-RUN-SLICE-VALIDATED  ( max-steps host -- run-state )
    _SHI.VM @ _SVM-RUN-SLICE-VALIDATED ;

: SBOX-HOST-RUN-SLICE  ( max-steps host -- run-state )
    DUP _SHOST-ACTIVE? 0= IF
        2DROP SBOX-VM-RUN-INVALID EXIT
    THEN
    _SHI.VM @ SBOX-VM-RUN-SLICE ;

: SBOX-HOST-CANCEL  ( detail host -- status )
    DUP _SHOST-ATTACHED? 0= IF
        2DROP SBOX-HOST-S-INVALID EXIT
    THEN
    _SHI.VM @ SBOX-VM-CANCEL
    SBOX-VM-S-OK =
    IF SBOX-HOST-S-OK ELSE SBOX-HOST-S-STATE THEN ;

\ Measuring is result finalization preflight: the VM may convert a malformed
\ returned value graph into a deterministic terminal guest failure.
: SBOX-HOST-RESULT-MEASURE  ( host -- result-u|0 status )
    DUP _SHOST-ACTIVE? 0= IF
        DROP 0 SBOX-HOST-S-INVALID EXIT
    THEN
    _SHI.VM @ SBOX-VM-RESULT-MEASURE
    DUP SBOX-VM-S-OK = IF
        DROP SBOX-HOST-S-OK
    ELSE
        2DROP 0 SBOX-HOST-S-STATE
    THEN ;

\ The caller has already validated the host and the candidate span.  Keep the
\ overlap walk private so a checked adapter can reuse that proof atomically.
: _SHOST-SPAN-DISJOINT-VALIDATED?  ( address length host -- flag )
    >R
    2DUP R@ SBOX-HOST-INVOCATION-SIZE
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    2DUP R@ _SHI.CHILD @ CTX-SIZE
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    2DUP R@ _SHI.PARENT @ CTX-SIZE
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    2DUP R@ _SHI.PLAN @ DUP SBOX-PLAN-TOTAL@
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    2DUP R@ _SHI.PLAN @ SBOX-PLAN-PROFILE@ SBOX-PROFILE-SIZE
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    2DUP R@ _SHI.INPUT @ R@ _SHI.INPUT-U @
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    2DUP R@ _SHI.OUTPUT @ R@ _SHI.OUTPUT-U @
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    2DUP R@ _SHI.WORK @ R@ _SHI.WORK-U @
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    2DUP R@ _SHI.VM @ R@ _SHI.VM-U @
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    2DROP R> DROP -1 ;

\ A live host owns one complete invocation graph, not merely its fixed
\ descriptor.  Adapters use this predicate before publishing caller-owned
\ metadata so neither that metadata nor a direct result buffer can alias a
\ child Context, borrowed plan/profile, or any allocation FINISH will scrub.
: SBOX-HOST-SPAN-DISJOINT?  ( address length host -- flag )
    >R
    2DUP _SHOST-SPAN? 0= IF 2DROP R> DROP 0 EXIT THEN
    R@ SBOX-HOST-VALID? 0= IF 2DROP R> DROP 0 EXIT THEN
    R> _SHOST-SPAN-DISJOINT-VALIDATED? ;

: _SHOST-FINISH>STATUS  ( vm-status -- host-status )
    DUP SBOX-VM-S-ALIAS = IF DROP SBOX-HOST-S-ALIAS EXIT THEN
    DUP SBOX-VM-S-STATE = IF DROP SBOX-HOST-S-STATE EXIT THEN
    DROP SBOX-HOST-S-RESULT ;

\ The caller has validated the complete host graph and obtained REQUIRED from
\ this host's VM.  The proof may cross only a non-reentrant allocation of the
\ fresh, disjoint result buffer: no callback, yield, host/VM mutation, or
\ ownership change may intervene.  Recheck the new result span and capacity
\ before the transactional VM commit.
: _SHOST-FINISH-MEASURED-VALIDATED
  ( result result-capacity required host -- status )
    >R
    2 PICK 2 PICK _SHOST-SPAN? 0= IF
        2DROP DROP R> DROP SBOX-HOST-S-RESULT EXIT
    THEN
    2 PICK 2 PICK R@ _SHOST-SPAN-DISJOINT-VALIDATED? 0= IF
        2DROP DROP R> DROP SBOX-HOST-S-ALIAS EXIT
    THEN
    2 PICK 2 PICK _SVM-RESULT-SPAN-STATUS IF
        2DROP DROP R> DROP SBOX-HOST-S-RESULT EXIT
    THEN
    DUP 2 PICK U> IF
        2DROP DROP R> DROP SBOX-HOST-S-RESULT EXIT
    THEN

    2 PICK 2 PICK 2 PICK R@ _SHI.VM @
        _SVM-FINISH-MEASURED-VALIDATED
    DUP IF
        _SHOST-FINISH>STATUS >R
        2DROP DROP R> R> DROP EXIT
    THEN
    DROP
    R@ _SHOST-CLEANUP-FINISHED
    2DROP DROP R> DROP SBOX-HOST-S-OK ;

: SBOX-HOST-FINISH  ( result result-capacity host -- status )
    DUP SBOX-HOST-VALID? 0= IF
        2DROP DROP SBOX-HOST-S-INVALID EXIT
    THEN
    2 PICK 2 PICK _SHOST-SPAN? 0= IF
        2DROP DROP SBOX-HOST-S-RESULT EXIT
    THEN
    2 PICK 2 PICK 2 PICK
        _SHOST-SPAN-DISJOINT-VALIDATED? 0= IF
        2DROP DROP SBOX-HOST-S-ALIAS EXIT
    THEN
    2 PICK 2 PICK 2 PICK _SHI.VM @ SBOX-VM-FINISH
    DUP IF
        _SHOST-FINISH>STATUS >R
        2DROP DROP R> EXIT
    THEN
    DROP
    DUP _SHOST-CLEANUP-FINISHED
    2DROP DROP SBOX-HOST-S-OK ;

: SBOX-HOST-CONTEXT-IDENTITY@
  ( host -- id generation epoch status )
    DUP _SHOST-ACTIVE? 0= IF
        DROP 0 0 0 SBOX-HOST-S-INVALID EXIT
    THEN
    _SHI.CHILD @
    DUP CTX.ID @
    OVER CTX.GENERATION @
    ROT CTX.EPOCH @
    SBOX-HOST-S-OK ;

: SBOX-HOST-RELEASE  ( host -- status )
    DUP _SHOST-FIXED-SPAN? 0= IF
        DROP SBOX-HOST-S-INVALID EXIT
    THEN
    DUP _SHOST-ZERO? IF
        DROP SBOX-HOST-S-OK EXIT
    THEN
    DUP _SHOST-OWNED? 0= IF
        DROP SBOX-HOST-S-INVALID EXIT
    THEN
    _SHOST-CLEANUP SBOX-HOST-S-OK ;
