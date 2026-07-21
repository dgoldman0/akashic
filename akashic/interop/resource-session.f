\ =====================================================================
\  resource-session.f - Retained activation-local resource session
\ =====================================================================
\  A session discovers a semantic RID through an ordinary component
\  endpoint, retains the live owner through ROPOOL/RACQ, and owns the one
\  request envelope and exact binding used by its caller.  Capability
\  schemas remain the owner's contract: compact applet protocols and the
\  canonical RCON protocol use the same lifetime machinery.
\
\  The named resource service lends a neutral ROFFER containing its exact RID
\  and owner pool.  Initialization validates that offer against the discovered
\  runtime graph, copies both values, and never retains the offer pointer.
\  ROPOOL validates the RID/root/member graph while retaining it; the session
\  never dereferences an unretained CINST.  A successful session therefore
\  owns one RACQ token; a failed or endpoint-incomplete initialization owns
\  nothing.
\
\  STALE is deliberately sticky for ordinary operations.  Only an explicit
\  candidate attachment/commit or REFRESH may make the session ACTIVE again.
\  If an owner commit succeeds but local LBIND advancement fails, ADVANCE
\  returns COMMITTED-STALE, clears retryable local state, and retains the
\  token for explicit recovery or retryable finalization.
\ =====================================================================

PROVIDED akashic-interop-rsession

REQUIRE endpoint.f
REQUIRE resource-client.f
REQUIRE resource-owner-pool.f

\ =====================================================================
\  Public modes, statuses, and flags
\ =====================================================================

0 CONSTANT RSES-M-DIRECT
1 CONSTANT RSES-M-ACTIVE
2 CONSTANT RSES-M-BLOCKED
3 CONSTANT RSES-M-STALE

0   CONSTANT RSES-S-OK
200 CONSTANT RSES-S-INVALID
201 CONSTANT RSES-S-BLOCKED
202 CONSTANT RSES-S-STALE
203 CONSTANT RSES-S-COMMITTED-STALE
204 CONSTANT RSES-S-RELEASE
205 CONSTANT RSES-S-NOMEM
206 CONSTANT RSES-S-CAPABILITY

1 CONSTANT RSES-F-CANONICAL

0 CONSTANT _RSES-PREP-NONE
1 CONSTANT _RSES-PREP-AUTHORITATIVE
2 CONSTANT _RSES-PREP-CANDIDATE

3 CONSTANT RSES-REFRESH-ATTEMPTS
96 CONSTANT RSES-SERVICE-MAX

0x53534552 CONSTANT RSES-MAGIC       \ "RESS"
1          CONSTANT RSES-ABI-VERSION

\ =====================================================================
\  Caller-owned session state
\ =====================================================================

   0 CONSTANT _RSES-MAGIC
   8 CONSTANT _RSES-ABI
  16 CONSTANT _RSES-SIZE
  24 CONSTANT _RSES-MODE
  32 CONSTANT _RSES-FLAGS
  40 CONSTANT _RSES-PREPARED
  48 CONSTANT _RSES-INSTANCE
  56 CONSTANT _RSES-CONTEXT
  64 CONSTANT _RSES-RREG
  72 CONSTANT _RSES-BUS
  80 CONSTANT _RSES-OWNER
  88 CONSTANT _RSES-POOL
  96 CONSTANT _RSES-ROOT
 104 CONSTANT _RSES-SERVICE-A
 112 CONSTANT _RSES-SERVICE-U
 120 CONSTANT _RSES-RID                 \ RID-SIZE bytes
 152 CONSTANT _RSES-REF                 \ RREF-SIZE bytes
 232 CONSTANT _RSES-ACQUISITION         \ RACQ-RESULT-SIZE bytes
 440 CONSTANT _RSES-CLIENT              \ RCLI-SIZE bytes
 688 CONSTANT _RSES-CANDIDATE-REF       \ RREF-SIZE bytes
 768 CONSTANT _RSES-CANDIDATE-BIND      \ LBIND-SIZE bytes
 920 CONSTANT _RSES-LOCATOR             \ QLOC-SIZE bytes
1240 CONSTANT _RSES-SNAPSHOT
1248 CONSTANT _RSES-REPLACE
1256 CONSTANT _RSES-REQUEST
1264 CONSTANT _RSES-ADVANCE-XT
1272 CONSTANT _RSES-RESERVED
1280 CONSTANT _RSES-LATEST-REF          \ RREF-SIZE bytes
1360 CONSTANT RSES-SIZE

: RSES.MAGIC          ( session -- a ) _RSES-MAGIC + ;
: RSES.ABI            ( session -- a ) _RSES-ABI + ;
: RSES.SIZE           ( session -- a ) _RSES-SIZE + ;
: RSES.MODE           ( session -- a ) _RSES-MODE + ;
: RSES.FLAGS          ( session -- a ) _RSES-FLAGS + ;
: RSES.PREPARED       ( session -- a ) _RSES-PREPARED + ;
: RSES.INSTANCE       ( session -- a ) _RSES-INSTANCE + ;
: RSES.CONTEXT        ( session -- a ) _RSES-CONTEXT + ;
: RSES.RREG           ( session -- a ) _RSES-RREG + ;
: RSES.BUS            ( session -- a ) _RSES-BUS + ;
: RSES.OWNER          ( session -- a ) _RSES-OWNER + ;
: RSES.POOL           ( session -- a ) _RSES-POOL + ;
: RSES.ROOT           ( session -- a ) _RSES-ROOT + ;
: RSES.SERVICE-A      ( session -- a ) _RSES-SERVICE-A + ;
: RSES.SERVICE-U      ( session -- a ) _RSES-SERVICE-U + ;
: RSES.RID            ( session -- rid ) _RSES-RID + ;
: RSES.REF            ( session -- ref ) _RSES-REF + ;
: RSES.ACQUISITION    ( session -- result ) _RSES-ACQUISITION + ;
: RSES.CLIENT         ( session -- client ) _RSES-CLIENT + ;
: RSES.BIND           ( session -- binding ) RSES.CLIENT RCLI.BIND ;
: RSES.CANDIDATE-REF  ( session -- ref ) _RSES-CANDIDATE-REF + ;
: RSES.CANDIDATE-BIND ( session -- binding ) _RSES-CANDIDATE-BIND + ;
: RSES.LOCATOR        ( session -- locator ) _RSES-LOCATOR + ;
: RSES.SNAPSHOT       ( session -- a ) _RSES-SNAPSHOT + ;
: RSES.REPLACE        ( session -- a ) _RSES-REPLACE + ;
: RSES.REQUEST        ( session -- a ) _RSES-REQUEST + ;
: RSES.ADVANCE-XT     ( session -- a ) _RSES-ADVANCE-XT + ;
: RSES.LATEST-REF     ( session -- ref ) _RSES-LATEST-REF + ;

: RSES-HEADER?  ( session -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP RSES-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP RSES.MAGIC @ RSES-MAGIC =
    OVER RSES.ABI @ RSES-ABI-VERSION = AND
    OVER RSES.SIZE @ RSES-SIZE = AND
    SWAP _RSES-RESERVED + @ 0= AND ;

: _RSES-RESET  ( session -- )
    DUP RSES-SIZE 0 FILL
    RSES-MAGIC OVER RSES.MAGIC !
    RSES-ABI-VERSION OVER RSES.ABI !
    RSES-SIZE OVER RSES.SIZE !
    RSES-M-DIRECT OVER RSES.MODE !
    DUP RSES.RID RID-CLEAR
    DUP RSES.REF RREF-INIT
    DUP RSES.ACQUISITION RACQ-RESULT-INIT
    DUP RSES.CLIENT RCLI-CLEAR
    DUP RSES.CANDIDATE-REF RREF-INIT
    DUP RSES.CANDIDATE-BIND LBIND-INIT
    DUP RSES.LOCATOR QLOC-INIT
    DUP RSES.LATEST-REF RREF-INIT
    ['] LBIND-ADVANCE SWAP RSES.ADVANCE-XT ! ;

: RSES-ACTIVE?  ( session -- flag )
    DUP RSES-HEADER? 0= IF DROP 0 EXIT THEN
    RSES.MODE @ RSES-M-ACTIVE = ;

: RSES-STALE?  ( session -- flag )
    DUP RSES-HEADER? 0= IF DROP 0 EXIT THEN
    RSES.MODE @ RSES-M-STALE = ;

: RSES-CANONICAL?  ( session -- flag )
    DUP RSES-HEADER? 0= IF DROP 0 EXIT THEN
    RSES.FLAGS @ RSES-F-CANONICAL AND 0<> ;

: RSES-REPLACE?  ( session -- flag )
    DUP RSES-HEADER? 0= IF DROP 0 EXIT THEN
    RSES.REPLACE @ 0<> ;

\ =====================================================================
\  Runtime and capability discovery
\ =====================================================================

: _RSES-SERVICE-U?  ( length -- flag )
    DUP 0> SWAP RSES-SERVICE-MAX <= AND ;

: _RSES-BORROWED-PREFLIGHT  ( address length session -- status )
    >R
    OVER 0= IF 2DROP R> DROP RSES-S-BLOCKED EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF
        2DROP R> DROP RSES-S-BLOCKED EXIT
    THEN
    R@ RSES-SIZE MSPAN-OVERLAP? IF
        R> DROP RSES-S-INVALID EXIT
    THEN
    R> DROP RSES-S-OK ;

: _RSES-ENDPOINT-PREFLIGHT  ( endpoint session -- status )
    >R IENDPOINT-SIZE R> _RSES-BORROWED-PREFLIGHT ;

: _RSES-RUNTIME-SERVICES  ( endpoint -- context rreg bus )
    >R
    S" org.akashic.runtime.context" R@ IEND-SERVICE
    S" org.akashic.runtime.resource-registry" R@ IEND-SERVICE
    S" org.akashic.interop.request-bus" R> IEND-SERVICE ;

: _RSES-RUNTIME-RAW-PREFLIGHT
  ( context rreg bus session -- context rreg bus status )
    >R
    2 PICK CTX-SIZE R@ _RSES-BORROWED-PREFLIGHT
    DUP RSES-S-OK <> IF R> DROP EXIT THEN DROP
    1 PICK RREG-SIZE R@ _RSES-BORROWED-PREFLIGHT
    DUP RSES-S-OK <> IF R> DROP EXIT THEN DROP
    DUP CBUS-SIZE R@ _RSES-BORROWED-PREFLIGHT
    DUP RSES-S-OK <> IF R> DROP EXIT THEN DROP

    \ Derive pointers only from headers whose complete fixed spans were
    \ protected above.  Protect every raw target before any validator or
    \ relationship check can dereference it or classify the graph BLOCKED.
    1 PICK RREG.CONTEXT @ CTX-SIZE R@ _RSES-BORROWED-PREFLIGHT
    DUP RSES-S-OK <> IF R> DROP EXIT THEN DROP
    1 PICK RREG.COMPONENTS @ CREG-SIZE R@ _RSES-BORROWED-PREFLIGHT
    DUP RSES-S-OK <> IF R> DROP EXIT THEN DROP
    DUP CBUS.REGISTRY @ CREG-SIZE R@ _RSES-BORROWED-PREFLIGHT
    DUP RSES-S-OK <> IF R> DROP EXIT THEN DROP
    DUP CBUS.POLICY @ CPOLICY-SIZE R@ _RSES-BORROWED-PREFLIGHT
    DUP RSES-S-OK <> IF R> DROP EXIT THEN DROP
    2 PICK CTX.QUEUE @ CBUS-SIZE R@ _RSES-BORROWED-PREFLIGHT
    DUP RSES-S-OK <> IF R> DROP EXIT THEN DROP
    2 PICK CTX.POLICY @ CPOLICY-SIZE R@ _RSES-BORROWED-PREFLIGHT
    DUP RSES-S-OK <> IF R> DROP EXIT THEN DROP
    R> DROP RSES-S-OK ;

: _RSES-RUNTIME-VALIDATE
  ( context rreg bus -- context rreg bus status )
    2 PICK CTX-VALID? 0= IF RSES-S-BLOCKED EXIT THEN
    2 PICK CTX.FLAGS @ CTX-F-ACTIVE AND 0= IF
        RSES-S-BLOCKED EXIT
    THEN
    1 PICK RREG-VALID? 0= IF RSES-S-BLOCKED EXIT THEN
    2 PICK 2 PICK RREG-CONTEXT? 0= IF
        RSES-S-BLOCKED EXIT
    THEN
    DUP CBUS.REGISTRY @ 2 PICK RREG.COMPONENTS @ <> IF
        RSES-S-BLOCKED EXIT
    THEN
    DUP CBUS.POLICY @ DUP 0= IF
        DROP RSES-S-BLOCKED EXIT
    THEN
    3 PICK CTX.POLICY @ <> IF RSES-S-BLOCKED EXIT THEN
    2 PICK CTX.QUEUE @ OVER <> IF RSES-S-BLOCKED EXIT THEN
    RSES-S-OK ;

: _RSES-POOL-RAW-PREFLIGHT  ( pool session -- status )
    >R
    DUP ROPOOL-SIZE R@ _RSES-BORROWED-PREFLIGHT
    DUP RSES-S-OK <> IF NIP R> DROP EXIT THEN DROP

    DUP ROPOOL.SLOT-CAP @ ROPOOL-SLOT-BYTES
    DUP 0= IF 2DROP R> DROP RSES-S-BLOCKED EXIT THEN
    OVER ROPOOL.SLOTS @ SWAP R@ _RSES-BORROWED-PREFLIGHT
    DUP RSES-S-OK <> IF NIP R> DROP EXIT THEN DROP

    DUP ROPOOL.LEASE-CAP @ ROPOOL-LEASE-BYTES
    DUP 0= IF 2DROP R> DROP RSES-S-BLOCKED EXIT THEN
    OVER ROPOOL.LEASES @ SWAP R@ _RSES-BORROWED-PREFLIGHT
    DUP RSES-S-OK <> IF NIP R> DROP EXIT THEN DROP

    DUP ROPOOL.CONTEXT @ CTX-SIZE R@ _RSES-BORROWED-PREFLIGHT
    DUP RSES-S-OK <> IF NIP R> DROP EXIT THEN DROP
    DUP ROPOOL.CREG @ CREG-SIZE R@ _RSES-BORROWED-PREFLIGHT
    DUP RSES-S-OK <> IF NIP R> DROP EXIT THEN DROP
    DUP ROPOOL.RREG @ RREG-SIZE R@ _RSES-BORROWED-PREFLIGHT
    DUP RSES-S-OK <> IF NIP R> DROP EXIT THEN DROP

    \ RREG validators follow both of these pointers.  Protect the raw targets
    \ independently of whether the pool and endpoint graphs later agree.
    DUP ROPOOL.RREG @ RREG.CONTEXT @ CTX-SIZE
        R@ _RSES-BORROWED-PREFLIGHT
    DUP RSES-S-OK <> IF NIP R> DROP EXIT THEN DROP
    DUP ROPOOL.RREG @ RREG.COMPONENTS @ CREG-SIZE
        R@ _RSES-BORROWED-PREFLIGHT
    DUP RSES-S-OK <> IF NIP R> DROP EXIT THEN DROP
    DROP R> DROP RSES-S-OK ;

: _RSES-OFFER-RAW-PREFLIGHT  ( offer session -- status )
    >R
    DUP ROFFER-SIZE R@ _RSES-BORROWED-PREFLIGHT
    DUP RSES-S-OK <> IF NIP R> DROP EXIT THEN DROP
    ROFFER.POOL @ R> _RSES-POOL-RAW-PREFLIGHT ;

: _RSES-OFFER-VALIDATE  ( offer -- status )
    DUP ROFFER-VALID? 0= IF DROP RSES-S-BLOCKED EXIT THEN
    ROFFER-POOL@ ROPOOL-VALID?
        IF RSES-S-OK ELSE RSES-S-BLOCKED THEN ;

: _RSES-ACCEPT-OFFER  ( offer session -- flag )
    >R
    DUP ROFFER-VALID? 0= IF DROP R> DROP 0 EXIT THEN
    DUP ROFFER-POOL@ DUP ROPOOL-VALID? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    DUP ROPOOL-CONTEXT@ R@ RSES.CONTEXT @ <> IF
        2DROP R> DROP 0 EXIT
    THEN
    DUP ROPOOL-RREG@ R@ RSES.RREG @ <> IF
        2DROP R> DROP 0 EXIT
    THEN
    DUP ROPOOL-CREG@ R@ RSES.BUS @ CBUS.REGISTRY @ <> IF
        2DROP R> DROP 0 EXIT
    THEN
    DUP R@ RSES.POOL !
    DUP ROPOOL-RACQ DUP R@ RSES.ROOT ! RACQ-ROOT-VALID? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    DROP ROFFER-RID R@ RSES.RID RID-COPY
    R> DROP -1 ;

: _RSES-SNAPSHOT-CAP?  ( capability -- flag )
    DUP CAP-DESC-VALID? 0= IF DROP 0 EXIT THEN
    DUP CAP.KIND @ CAP-K-RESOURCE =
    SWAP CAP.EFFECTS @ CAP-E-OBSERVE = AND ;

: _RSES-REPLACE-CAP?  ( capability -- flag )
    DUP CAP-DESC-VALID? 0= IF DROP 0 EXIT THEN
    DUP CAP.KIND @ CAP-K-COMMAND =
    SWAP CAP.EFFECTS @ CAP-E-MUTATE CAP-E-PERSIST OR = AND ;

: _RSES-CACHE-CAPS  ( session -- status )
    >R
    R@ RSES.OWNER @ DUP 0= IF DROP R> DROP RSES-S-CAPABILITY EXIT THEN
    CINST-DESC DUP COMP-CAPS-VALID? 0= IF
        DROP R> DROP RSES-S-CAPABILITY EXIT
    THEN
    S" resource.snapshot" 2 PICK COMP-CAP-FIND
    DUP _RSES-SNAPSHOT-CAP? 0= IF
        2DROP R> DROP RSES-S-CAPABILITY EXIT
    THEN
    R@ RSES.SNAPSHOT !
    S" resource.replace" ROT COMP-CAP-FIND ?DUP IF
        DUP _RSES-REPLACE-CAP? 0= IF
            DROP R> DROP RSES-S-CAPABILITY EXIT
        THEN
        R@ RSES.REPLACE !
    THEN
    R> DROP RSES-S-OK ;

: _RSES-CAP?  ( capability session -- flag )
    >R
    DUP R@ RSES.SNAPSHOT @ =
    OVER R@ RSES.REPLACE @ =
    R@ RSES.REPLACE @ 0<> AND OR NIP
    R> DROP ;

\ =====================================================================
\  Acquisition and transactional initialization
\ =====================================================================

: _RSES-CANDIDATE-CLEAR  ( session -- )
    DUP RSES.PREPARED @ _RSES-PREP-CANDIDATE = IF
        _RSES-PREP-NONE OVER RSES.PREPARED !
    THEN
    DUP RSES.CANDIDATE-REF RREF-INIT
    RSES.CANDIDATE-BIND LBIND-CLEAR ;

: _RSES-TOKEN-HELD?  ( session -- flag )
    DUP RSES.ROOT @ DUP 0= IF 2DROP 0 EXIT THEN
    >R RSES.ACQUISITION RACQ.RESULT-TOKEN R>
    RACQ-TOKEN-FOR-ROOT? ;

: _RSES-OWNS-STORAGE?  ( session -- flag )
    DUP RSES.REQUEST @ 0<>
    SWAP RSES.ACQUISITION RACQ.RESULT-TOKEN RACQ.TOKEN-STATE @ 0<> OR ;

: _RSES-STORAGE-FRESH?  ( session -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP RSES-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP RSES-HEADER? IF
        DUP _RSES-OWNS-STORAGE? 0= SWAP DROP EXIT
    THEN
    DROP -1 ;

\ Public clearing is initialization, not finalization.  A live request or
\ acquisition token must survive for RSES-FINI to release it exactly.
: RSES-CLEAR  ( session -- )
    DUP _RSES-STORAGE-FRESH? 0= IF DROP EXIT THEN
    _RSES-RESET ;

: RSES-HELD?  ( session -- flag )
    DUP RSES-HEADER? 0= IF DROP 0 EXIT THEN
    _RSES-TOKEN-HELD? ;

: RSES-VALID?  ( session -- flag )
    DUP RSES-HEADER? 0= IF DROP 0 EXIT THEN
    DUP RSES.FLAGS @ RSES-F-CANONICAL INVERT AND IF DROP 0 EXIT THEN
    DUP RSES.PREPARED @ DUP _RSES-PREP-NONE >=
        SWAP _RSES-PREP-CANDIDATE <= AND 0= IF DROP 0 EXIT THEN
    DUP RSES.MODE @ DUP RSES-M-DIRECT >=
        SWAP RSES-M-STALE <= AND 0= IF DROP 0 EXIT THEN
    DUP RSES.MODE @ DUP RSES-M-DIRECT = SWAP RSES-M-BLOCKED = OR IF
        DUP _RSES-TOKEN-HELD? 0=
        SWAP RSES.REQUEST @ 0= AND EXIT
    THEN
    DUP _RSES-TOKEN-HELD? 0= IF DROP 0 EXIT THEN
    DUP RSES.REQUEST @ 0= IF DROP 0 EXIT THEN
    DUP RSES.CONTEXT @ CTX-VALID? 0= IF DROP 0 EXIT THEN
    DUP RSES.RREG @ RREG-VALID? 0= IF DROP 0 EXIT THEN
    DUP RSES.POOL @ ROPOOL-VALID? 0= IF DROP 0 EXIT THEN
    DUP RSES.POOL @ ROPOOL-CONTEXT@ OVER RSES.CONTEXT @ <> IF
        DROP 0 EXIT
    THEN
    DUP RSES.POOL @ ROPOOL-RREG@ OVER RSES.RREG @ <> IF
        DROP 0 EXIT
    THEN
    DUP RSES.BUS @ 0= IF DROP 0 EXIT THEN
    DUP RSES.POOL @ ROPOOL-CREG@
        OVER RSES.BUS @ CBUS.REGISTRY @ <> IF DROP 0 EXIT THEN
    DUP RSES.ROOT @ RACQ-ROOT-VALID? 0= IF DROP 0 EXIT THEN
    DUP RSES.POOL @ ROPOOL-RACQ OVER RSES.ROOT @ <> IF DROP 0 EXIT THEN
    DUP RSES.ACQUISITION RACQ-RESULT-VALID? 0= IF DROP 0 EXIT THEN
    DUP RSES.ACQUISITION RACQ.RESULT-REF RREF.ID
        OVER RSES.RID RID= 0= IF DROP 0 EXIT THEN
    DUP RSES.MODE @ RSES-M-ACTIVE = IF
        DUP RSES.BIND LBIND-VALID? 0= IF DROP 0 EXIT THEN
        DUP RSES.REF RREF-VALID? 0= IF DROP 0 EXIT THEN
        DUP RSES.REF RREF.ID OVER RSES.RID RID= 0= IF DROP 0 EXIT THEN
        DUP RSES.BIND LBIND.RESOURCE-ID
            OVER RSES.RID RID= 0= IF DROP 0 EXIT THEN
        DUP RSES.REF RREF.REVISION @
        OVER RSES.BIND LBIND.REVISION @ = 0= IF DROP 0 EXIT THEN
        DUP RSES.CONTEXT @ OVER RSES.BIND LBIND-CONTEXT? 0= IF
            DROP 0 EXIT
        THEN
        DUP RSES.BIND LBIND.TARGET-ID @
        OVER RSES.BIND LBIND.TARGET-GEN @
        2 PICK RSES.BUS @ CBUS.REGISTRY @ CREG-INST-FIND
        DUP 0= IF 2DROP 0 EXIT THEN
        DUP 2 PICK RSES.OWNER @ <> IF 2DROP 0 EXIT THEN
        DUP ROPOOL-MEMBER-POOL@ 2 PICK RSES.POOL @ <> IF
            2DROP 0 EXIT
        THEN
        DROP
    THEN
    DROP -1 ;

: _RSES-DETACH  ( session -- racq-status )
    DUP _RSES-TOKEN-HELD? 0= IF DROP RACQ-S-OK EXIT THEN
    >R
    R@ RSES.BIND DUP LBIND-VALID? 0= IF
        DROP R@ RSES.CANDIDATE-BIND
    THEN
    R@ RSES.ACQUISITION RACQ-DETACH
    R> DROP ;

: _RSES-RESOLVE-POOL  ( session -- status )
    >R
    R@ RSES.RID R@ RSES.CONTEXT @ R@ RSES.CANDIDATE-REF
        R@ RSES.RREG @ RREG-REF ?DUP IF
        DROP R> DROP RSES-S-BLOCKED EXIT
    THEN

    \ QLOC identity never carries the activation-local component revision.
    0 R@ RSES.CANDIDATE-REF RREF.REVISION !
    R@ RSES.ROOT @ RACQ-ROOT-OWNER$
        R@ RSES.CANDIDATE-REF R@ RSES.LOCATOR QLOC-IDENTITY!
        QLOC-S-OK <> IF R> DROP RSES-S-BLOCKED EXIT THEN

    R@ RSES.LOCATOR R@ RSES.POOL @ R@ RSES.CONTEXT @ R@ RSES.RREG @
        R@ RSES.CANDIDATE-BIND R@ RSES.ACQUISITION ROPOOL-ATTACH
    DUP RACQ-S-OK <> IF DROP R> DROP RSES-S-BLOCKED EXIT THEN DROP

    \ Only after ROPOOL has retained and revalidated the member may the
    \ session resolve the target and borrow its descriptor pointers.
    R@ RSES.CANDIDATE-BIND LBIND.TARGET-ID @
    R@ RSES.CANDIDATE-BIND LBIND.TARGET-GEN @
    R@ RSES.RREG @ RREG.COMPONENTS @ CREG-INST-FIND
    DUP 0= IF DROP R> DROP RSES-S-BLOCKED EXIT THEN
    DUP R@ RSES.OWNER !
    DUP ROPOOL-MEMBER-POOL@ R@ RSES.POOL @ <> IF
        DROP R> DROP RSES-S-BLOCKED EXIT
    THEN DROP
    R> DROP RSES-S-OK ;

: _RSES-CLIENT-INIT  ( session -- status )
    >R
    R@ _RSES-CACHE-CAPS ?DUP IF R> DROP EXIT THEN
    R@ RSES.ACQUISITION R@ RSES.CANDIDATE-BIND
        R@ RSES.CONTEXT @ R@ RSES.BUS @ R@ RSES.CLIENT RCLI-INIT
    DUP CBUS-S-OK = IF
        DROP RSES-F-CANONICAL R@ RSES.FLAGS !
    ELSE
        DROP R@ RSES.CLIENT RCLI-CLEAR
        R@ RSES.CANDIDATE-BIND R@ RSES.BIND LBIND-COPY
            LBIND-S-OK <> IF R> DROP RSES-S-BLOCKED EXIT THEN
    THEN
    R@ RSES.BIND R@ RSES.REF LBIND-REF
        LBIND-S-OK <> IF R> DROP RSES-S-BLOCKED EXIT THEN
    CBR-NEW DUP IF
        2DROP R> DROP RSES-S-NOMEM EXIT
    THEN
    DROP R@ RSES.REQUEST !
    R@ _RSES-CANDIDATE-CLEAR
    _RSES-PREP-NONE R@ RSES.PREPARED !
    RSES-M-ACTIVE R@ RSES.MODE !
    R> DROP RSES-S-OK ;

: _RSES-ROLLBACK-BLOCKED  ( session -- status )
    >R
    R@ _RSES-DETACH DUP RACQ-S-OK <> IF
        DROP RSES-M-STALE R@ RSES.MODE !
        R> DROP RSES-S-RELEASE EXIT
    THEN DROP
    R@ RSES.REQUEST @ ?DUP IF CBR-FREE THEN
    R@ _RSES-RESET
    RSES-M-BLOCKED R@ RSES.MODE !
    R> DROP RSES-S-BLOCKED ;

: _RSES-INIT-SPANS?  ( service-a service-u instance session -- flag )
    DUP _RSES-STORAGE-FRESH? 0= IF 2DROP 2DROP 0 EXIT THEN
    3 PICK 3 PICK MSPAN-NONWRAPPING? 0= IF 2DROP 2DROP 0 EXIT THEN
    3 PICK 3 PICK 2 PICK RSES-SIZE MSPAN-OVERLAP? IF
        2DROP 2DROP 0 EXIT
    THEN
    \ The session is normally embedded in CINST state.  Only the borrowed
    \ CINST header itself is an input span and must remain disjoint.
    OVER 0<> IF
        OVER COMP-INST MSPAN-NONWRAPPING? 0= IF
            2DROP 2DROP 0 EXIT
        THEN
        OVER COMP-INST 2 PICK RSES-SIZE MSPAN-OVERLAP? IF
            2DROP 2DROP 0 EXIT
        THEN
    THEN
    2DROP 2DROP -1 ;

: _RSES-BLOCK  ( service-a service-u instance session -- status )
    >R
    R@ _RSES-RESET
    DUP R@ RSES.INSTANCE !
    DROP 2DROP
    RSES-M-BLOCKED R@ RSES.MODE !
    R> DROP RSES-S-BLOCKED ;

: _RSES-DIRECT  ( service-a service-u instance session -- status )
    >R
    R@ _RSES-RESET
    DUP R@ RSES.INSTANCE !
    DROP 2DROP
    R> DROP RSES-S-OK ;

: _RSES-DROP-STAGED  ( endpoint offer context rreg bus -- )
    2DROP 2DROP DROP ;

: _RSES-INIT-STAGED  ( a u inst session endpoint offer ctx rreg bus -- status )
    5 PICK >R
    R@ _RSES-RESET
    6 PICK R@ RSES.INSTANCE !
    8 PICK R@ RSES.SERVICE-A !
    7 PICK R@ RSES.SERVICE-U !
    2 PICK R@ RSES.CONTEXT !
    1 PICK R@ RSES.RREG !
    DUP R@ RSES.BUS !
    3 PICK R@ _RSES-ACCEPT-OFFER 0= IF
        2DROP 2DROP 2DROP 2DROP DROP
        RSES-M-BLOCKED R@ RSES.MODE !
        R> DROP RSES-S-BLOCKED EXIT
    THEN
    2DROP 2DROP 2DROP 2DROP DROP
    R@ _RSES-RESOLVE-POOL ?DUP IF
        DROP R@ _RSES-ROLLBACK-BLOCKED R> DROP EXIT
    THEN
    R@ _RSES-CLIENT-INIT ?DUP IF
        DROP R@ _RSES-ROLLBACK-BLOCKED R> DROP EXIT
    THEN
    R> DROP RSES-S-OK ;

: RSES-INIT  ( service-a service-u instance session -- status )
    2OVER 2OVER _RSES-INIT-SPANS? 0= IF
        2DROP 2DROP RSES-S-INVALID EXIT
    THEN
    2 PICK _RSES-SERVICE-U? 0= IF _RSES-BLOCK EXIT THEN
    3 PICK 0= IF _RSES-BLOCK EXIT THEN
    3 PICK 3 PICK UTF8-VALID? 0= IF _RSES-BLOCK EXIT THEN
    OVER 0= IF _RSES-BLOCK EXIT THEN
    OVER CINST.ENDPOINT @
    DUP 0= IF DROP _RSES-DIRECT EXIT THEN
    DUP 2 PICK _RSES-ENDPOINT-PREFLIGHT
    DUP RSES-S-INVALID = IF
        DROP DROP 2DROP 2DROP RSES-S-INVALID EXIT
    THEN
    RSES-S-OK <> IF DROP _RSES-BLOCK EXIT THEN

    \ Stage each runtime service first, exactly once.  Keep those results on
    \ the return stack while the exact named service is queried once and last;
    \ no later endpoint callback can mutate the offer after discovery.
    DUP _RSES-RUNTIME-SERVICES
    >R >R >R
    4 PICK 4 PICK 2 PICK IEND-SERVICE
    R> R> R>

    \ Collect and protect the complete raw offer/pool/runtime geometry before
    \ any validator follows a nested pointer.  Alias refusal therefore remains
    \ byte-for-byte nonmutating even when the surrounding graph is malformed.
    3 PICK 6 PICK _RSES-OFFER-RAW-PREFLIGHT
    DUP RSES-S-INVALID = IF
        DROP _RSES-DROP-STAGED 2DROP 2DROP RSES-S-INVALID EXIT
    THEN
    RSES-S-OK <> IF
        _RSES-DROP-STAGED _RSES-BLOCK EXIT
    THEN
    5 PICK _RSES-RUNTIME-RAW-PREFLIGHT
    DUP RSES-S-INVALID = IF
        DROP _RSES-DROP-STAGED 2DROP 2DROP RSES-S-INVALID EXIT
    THEN
    RSES-S-OK <> IF
        _RSES-DROP-STAGED _RSES-BLOCK EXIT
    THEN

    \ With all endpoint calls and raw-span checks complete, validate the exact
    \ staged graph and only then reset/copy it into caller-owned session state.
    3 PICK _RSES-OFFER-VALIDATE RSES-S-OK <> IF
        _RSES-DROP-STAGED _RSES-BLOCK EXIT
    THEN
    _RSES-RUNTIME-VALIDATE RSES-S-OK <> IF
        _RSES-DROP-STAGED _RSES-BLOCK EXIT
    THEN
    _RSES-INIT-STAGED ;

\ =====================================================================
\  Exact candidate binding and explicit refresh
\ =====================================================================

: _RSES-CANDIDATE-MODE?  ( session -- flag )
    RSES.MODE @ DUP RSES-M-ACTIVE = SWAP RSES-M-STALE = OR ;

: RSES-CANDIDATE-ATTACH  ( reference session -- status )
    >R
    R@ RSES-HEADER? 0= IF DROP R> DROP RSES-S-INVALID EXIT THEN
    R@ _RSES-TOKEN-HELD? 0= R@ _RSES-CANDIDATE-MODE? 0= OR IF
        DROP R> DROP RSES-S-STALE EXIT
    THEN
    DUP RREF-VALID? 0= IF DROP R> DROP RSES-S-INVALID EXIT THEN
    DUP RREF.REVISION @ 0> 0= IF DROP R> DROP RSES-S-INVALID EXIT THEN
    DUP RREF.ID R@ RSES.RID RID= 0= IF
        DROP R> DROP RSES-S-INVALID EXIT
    THEN
    \ Stage the validated input before clearing candidate state.  Pad and
    \ other callers may intentionally pass RSES.CANDIDATE-REF itself; the
    \ public operation must not erase its own source.  _ATTACH-LATEST already
    \ supplies the scratch address, so avoid copying it onto itself.
    DUP R@ RSES.LATEST-REF = IF
        DROP
    ELSE
        R@ RSES.LATEST-REF RREF-COPY RREF-S-OK <> IF
            R@ RSES.LATEST-REF RREF-INIT
            R> DROP RSES-S-INVALID EXIT
        THEN
    THEN
    R@ _RSES-CANDIDATE-CLEAR
    R@ RSES.LATEST-REF R@ RSES.CANDIDATE-REF RREF-COPY
        RREF-S-OK <> IF
        R@ RSES.LATEST-REF RREF-INIT
        R> DROP RSES-S-INVALID EXIT
    THEN
    R@ RSES.LATEST-REF RREF-INIT
    R@ RSES.CANDIDATE-REF R@ RSES.CONTEXT @ R@ RSES.RREG @
        R@ RSES.CANDIDATE-BIND LBIND-ATTACH
    DUP LBIND-S-OK <> IF
        DUP LBIND-S-STALE-REVISION = IF
            DROP R@ _RSES-CANDIDATE-CLEAR R> DROP RSES-S-STALE EXIT
        THEN
        DROP R@ _RSES-CANDIDATE-CLEAR R> DROP RSES-S-BLOCKED EXIT
    THEN DROP
    R@ RSES.CANDIDATE-BIND LBIND.TARGET-ID @
        R@ RSES.OWNER @ CINST.ID @ <>
    R@ RSES.CANDIDATE-BIND LBIND.TARGET-GEN @
        R@ RSES.OWNER @ CINST.GENERATION @ <> OR IF
        R@ _RSES-CANDIDATE-CLEAR R> DROP RSES-S-BLOCKED EXIT
    THEN
    R@ RSES.CANDIDATE-BIND R@ RSES.CANDIDATE-REF LBIND-REF
        LBIND-S-OK <> IF
        R@ _RSES-CANDIDATE-CLEAR R> DROP RSES-S-BLOCKED EXIT
    THEN
    R> DROP RSES-S-OK ;

: _RSES-CANDIDATE-CORRELATED?  ( session -- flag )
    >R
    R@ _RSES-TOKEN-HELD? 0= IF R> DROP 0 EXIT THEN
    R@ RSES.POOL @ ROPOOL-VALID? 0= IF R> DROP 0 EXIT THEN
    R@ RSES.POOL @ ROPOOL-RACQ R@ RSES.ROOT @ <> IF
        R> DROP 0 EXIT
    THEN
    R@ RSES.ACQUISITION RACQ-RESULT-VALID? 0= IF R> DROP 0 EXIT THEN
    R@ RSES.ACQUISITION RACQ.RESULT-REF RREF.ID
        R@ RSES.RID RID= 0= IF R> DROP 0 EXIT THEN
    R@ RSES.CANDIDATE-REF RREF-VALID? 0= IF R> DROP 0 EXIT THEN
    R@ RSES.CANDIDATE-REF RREF.REVISION @ 0> 0= IF
        R> DROP 0 EXIT
    THEN
    R@ RSES.CANDIDATE-REF RREF.ID R@ RSES.RID RID= 0= IF
        R> DROP 0 EXIT
    THEN
    R@ RSES.CANDIDATE-BIND LBIND-VALID? 0= IF R> DROP 0 EXIT THEN
    R@ RSES.CONTEXT @ R@ RSES.CANDIDATE-BIND LBIND-CONTEXT? 0= IF
        R> DROP 0 EXIT
    THEN
    R@ RSES.CANDIDATE-BIND LBIND.RESOURCE-ID
        R@ RSES.RID RID= 0= IF R> DROP 0 EXIT THEN
    R@ RSES.CANDIDATE-REF RREF.REVISION @
        R@ RSES.CANDIDATE-BIND LBIND.REVISION @ <> IF
        R> DROP 0 EXIT
    THEN
    R@ RSES.BUS @ DUP 0= IF DROP R> DROP 0 EXIT THEN DROP
    R@ RSES.CANDIDATE-BIND LBIND.TARGET-ID @
    R@ RSES.CANDIDATE-BIND LBIND.TARGET-GEN @
    R@ RSES.BUS @ CBUS.REGISTRY @ CREG-INST-FIND
    DUP 0= IF DROP R> DROP 0 EXIT THEN
    DUP R@ RSES.OWNER @ <> IF DROP R> DROP 0 EXIT THEN
    DUP ROPOOL-MEMBER-POOL@ R@ RSES.POOL @ <> IF
        DROP R> DROP 0 EXIT
    THEN
    CINST.REVISION @ R@ RSES.CANDIDATE-REF RREF.REVISION @ =
    R> DROP ;

: RSES-CANDIDATE-COMMIT  ( session -- status )
    DUP RSES-HEADER? 0= IF DROP RSES-S-INVALID EXIT THEN
    DUP _RSES-CANDIDATE-MODE? 0= IF DROP RSES-S-STALE EXIT THEN
    DUP _RSES-CANDIDATE-CORRELATED? 0= IF
        DUP _RSES-CANDIDATE-CLEAR DROP RSES-S-STALE EXIT
    THEN
    >R
    \ Both sources and their correlation were validated above; the embedded,
    \ fixed-size destinations cannot fail or alias.  Publish without a
    \ fallible half-copy that could pair a new binding with an old reference.
    R@ RSES.CANDIDATE-BIND R@ RSES.BIND LBIND-SIZE CMOVE
    R@ RSES.CANDIDATE-REF R@ RSES.REF RREF-SIZE CMOVE
    R@ _RSES-CANDIDATE-CLEAR
    _RSES-PREP-NONE R@ RSES.PREPARED !
    RSES-M-ACTIVE R@ RSES.MODE !
    R> DROP RSES-S-OK ;

: _RSES-ATTACH-LATEST  ( session -- status )
    >R
    R@ RSES.RID R@ RSES.CONTEXT @ R@ RSES.LATEST-REF
        R@ RSES.RREG @ RREG-REF ?DUP IF
        DROP R> DROP RSES-S-STALE EXIT
    THEN
    R@ RSES.LATEST-REF R@ RSES-CANDIDATE-ATTACH
    R@ RSES.LATEST-REF RREF-INIT
    R> DROP ;

: RSES-REFRESH-N  ( session attempts -- status )
    DUP 1 < IF 2DROP RSES-S-INVALID EXIT THEN
    OVER RSES-HEADER? 0= IF 2DROP RSES-S-INVALID EXIT THEN
    OVER _RSES-TOKEN-HELD? 0= 2 PICK _RSES-CANDIDATE-MODE? 0= OR IF
        2DROP RSES-S-STALE EXIT
    THEN
    0 DO
        DUP _RSES-ATTACH-LATEST
        DUP RSES-S-OK = IF
            DROP DUP RSES-CANDIDATE-COMMIT NIP UNLOOP EXIT
        THEN
        DUP RSES-S-STALE <> IF
            NIP UNLOOP EXIT
        THEN
        DROP YIELD?
    LOOP
    RSES-M-STALE OVER RSES.MODE !
    DROP RSES-S-STALE ;

: RSES-REFRESH  ( session -- status )
    DUP RSES-HEADER? 0= IF DROP RSES-S-INVALID EXIT THEN
    DUP _RSES-TOKEN-HELD? 0= OVER _RSES-CANDIDATE-MODE? 0= OR IF
        DROP RSES-S-STALE EXIT
    THEN
    RSES-REFRESH-ATTEMPTS RSES-REFRESH-N ;

\ =====================================================================
\  Protocol-neutral request lifecycle
\ =====================================================================

: RSES-PREPARE  ( capability principal session -- status )
    >R
    R@ RSES-ACTIVE? 0= IF 2DROP R> DROP RSES-S-STALE EXIT THEN
    DUP CPRINC-USER < OVER CPRINC-AGENT > OR IF
        2DROP R> DROP RSES-S-INVALID EXIT
    THEN
    OVER R@ _RSES-CAP? 0= IF
        2DROP R> DROP RSES-S-CAPABILITY EXIT
    THEN
    R@ RSES.BIND R@ RSES.CONTEXT @ R@ RSES.REQUEST @ LBIND-REQUEST!
        LBIND-S-OK <> IF
        2DROP RSES-M-STALE R@ RSES.MODE !
        R> DROP RSES-S-STALE EXIT
    THEN
    DUP R@ RSES.REQUEST @ CBR.PRINCIPAL !
    OVER R@ RSES.REQUEST @ CBR.CAP !
    2DROP _RSES-PREP-AUTHORITATIVE R@ RSES.PREPARED !
    R> DROP RSES-S-OK ;

: RSES-CANDIDATE-PREPARE  ( capability principal session -- status )
    >R
    R@ RSES-HEADER? 0= R@ _RSES-CANDIDATE-MODE? 0= OR IF
        2DROP R> DROP RSES-S-STALE EXIT
    THEN
    R@ RSES.CANDIDATE-BIND LBIND-VALID? 0= IF
        2DROP R> DROP RSES-S-STALE EXIT
    THEN
    DUP CPRINC-USER < OVER CPRINC-AGENT > OR IF
        2DROP R> DROP RSES-S-INVALID EXIT
    THEN
    OVER R@ _RSES-CAP? 0= IF
        2DROP R> DROP RSES-S-CAPABILITY EXIT
    THEN
    R@ RSES.CANDIDATE-BIND R@ RSES.CONTEXT @ R@ RSES.REQUEST @
        LBIND-REQUEST! LBIND-S-OK <> IF
        2DROP R> DROP RSES-S-STALE EXIT
    THEN
    DUP R@ RSES.REQUEST @ CBR.PRINCIPAL !
    OVER R@ RSES.REQUEST @ CBR.CAP !
    2DROP _RSES-PREP-CANDIDATE R@ RSES.PREPARED !
    R> DROP RSES-S-OK ;

: RSES-DISPATCH  ( session -- status )
    DUP RSES-HEADER? 0= IF DROP RSES-S-INVALID EXIT THEN
    DUP RSES.PREPARED @ DUP _RSES-PREP-AUTHORITATIVE =
        SWAP _RSES-PREP-CANDIDATE = OR 0= IF
        DROP RSES-S-INVALID EXIT
    THEN
    DUP RSES.REQUEST @ OVER RSES.BUS @ CBUS-DISPATCH
    DUP CBUS-S-STALE-REVISION = IF
        OVER RSES.PREPARED @ _RSES-PREP-AUTHORITATIVE = IF
            RSES-M-STALE 2 PICK RSES.MODE !
        THEN
    THEN
    NIP ;

: _RSES-LOCAL-STALE  ( session -- )
    RSES-M-STALE OVER RSES.MODE !
    _RSES-PREP-NONE OVER RSES.PREPARED !
    DUP RSES.BIND LBIND-CLEAR
    RSES.REF RREF-INIT ;

: RSES-ADVANCE  ( session -- status )
    DUP RSES-ACTIVE? 0= IF DROP RSES-S-STALE EXIT THEN
    DUP RSES.PREPARED @ _RSES-PREP-AUTHORITATIVE <> IF
        DROP RSES-S-INVALID EXIT
    THEN
    DUP RSES.REQUEST @ CBR.STATUS @ CBUS-S-OK <> IF
        DROP RSES-S-INVALID EXIT
    THEN
    >R
    R@ RSES.REQUEST @ R@ RSES.CONTEXT @ R@ RSES.BIND
        R@ RSES.ADVANCE-XT @ EXECUTE
    DUP LBIND-S-OK <> IF
        DROP R@ RSES.REQUEST @ CBR.CAP @ R@ RSES.REPLACE @ =
        R@ _RSES-LOCAL-STALE R> DROP
        IF RSES-S-COMMITTED-STALE ELSE RSES-S-STALE THEN EXIT
    THEN DROP
    R@ RSES.BIND R@ RSES.REF LBIND-REF DUP LBIND-S-OK <> IF
        DROP R@ RSES.REQUEST @ CBR.CAP @ R@ RSES.REPLACE @ =
        R@ _RSES-LOCAL-STALE R> DROP
        IF RSES-S-COMMITTED-STALE ELSE RSES-S-STALE THEN EXIT
    THEN DROP
    _RSES-PREP-NONE R@ RSES.PREPARED !
    R> DROP RSES-S-OK ;

\ =====================================================================
\  Retryable finalization
\ =====================================================================

: RSES-FINI  ( session -- status )
    DUP RSES-HEADER? 0= IF DROP RSES-S-INVALID EXIT THEN
    DUP _RSES-DETACH DUP RACQ-S-OK <> IF
        2DROP RSES-S-RELEASE EXIT
    THEN DROP
    DUP RSES.REQUEST @ ?DUP IF CBR-FREE THEN
    _RSES-RESET RSES-S-OK ;
