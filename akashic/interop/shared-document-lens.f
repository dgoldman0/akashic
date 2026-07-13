\ =====================================================================
\  shared-document-lens.f - Reusable client for semantic text documents
\ =====================================================================
\  SDLENS contains only activation-local transport and exact-binding state.
\  It discovers one semantic resource through an applet endpoint, retains an
\  exact RREF/LBIND pair, and owns one reusable request envelope.  Parsing,
\  editing, dirty state, replace outcome handling, and backing paths remain
\  responsibilities of the consuming applet.
\
\  The resource contract is deliberately small and fixed:
\    resource.snapshot  ( null -- string )
\    resource.replace   ( string -- bool )
\ =====================================================================

PROVIDED akashic-interop-sdoc-lens

REQUIRE endpoint.f
REQUIRE lens-binding.f

\ =====================================================================
\  Public modes and operation status
\ =====================================================================

0 CONSTANT SDLENS-M-DIRECT
1 CONSTANT SDLENS-M-SHARED
2 CONSTANT SDLENS-M-BLOCKED

0 CONSTANT SDLENS-S-OK
1 CONSTANT SDLENS-S-STALE
2 CONSTANT SDLENS-S-STRUCTURAL

\ =====================================================================
\  Embedded lens state
\ =====================================================================

  0 CONSTANT _SDL-MODE
  8 CONSTANT _SDL-CONTEXT
 16 CONSTANT _SDL-RREG
 24 CONSTANT _SDL-BUS
 32 CONSTANT _SDL-OWNER
 40 CONSTANT _SDL-RID                    \ RID-SIZE bytes
 72 CONSTANT _SDL-REF                    \ RREF-SIZE bytes
152 CONSTANT _SDL-BIND                   \ LBIND-SIZE bytes
304 CONSTANT _SDL-SNAPSHOT-CAP
312 CONSTANT _SDL-REPLACE-CAP
320 CONSTANT _SDL-REQUEST
328 CONSTANT SDLENS-SIZE

: SDLENS.MODE          ( lens -- a ) _SDL-MODE + ;
: SDLENS.CONTEXT       ( lens -- a ) _SDL-CONTEXT + ;
: SDLENS.RREG          ( lens -- a ) _SDL-RREG + ;
: SDLENS.BUS           ( lens -- a ) _SDL-BUS + ;
: SDLENS.RID           ( lens -- id ) _SDL-RID + ;
: SDLENS.REF           ( lens -- ref ) _SDL-REF + ;
: SDLENS.BIND          ( lens -- binding ) _SDL-BIND + ;
: SDLENS.SNAPSHOT-CAP  ( lens -- a ) _SDL-SNAPSHOT-CAP + ;
: SDLENS.REPLACE-CAP   ( lens -- a ) _SDL-REPLACE-CAP + ;
: SDLENS.REQUEST       ( lens -- a ) _SDL-REQUEST + ;

: _SDLENS-STATE-INIT  ( lens -- )
    DUP SDLENS-SIZE 0 FILL
    SDLENS-M-DIRECT OVER SDLENS.MODE !
    DUP SDLENS.RID RID-CLEAR
    DUP SDLENS.REF RREF-INIT
    SDLENS.BIND LBIND-INIT ;

GUARD _SDLENS-GUARD

\ =====================================================================
\  Current exact attachment
\ =====================================================================

: _SDLENS-REFRESH-ONCE  ( lens -- lbind-status )
    >R
    R@ SDLENS.RID R@ SDLENS.CONTEXT @ R@ SDLENS.REF
        R@ SDLENS.RREG @ RREG-REF
    ?DUP IF DROP R> DROP LBIND-S-INVALID EXIT THEN
    R@ SDLENS.REF R@ SDLENS.CONTEXT @ R@ SDLENS.RREG @
        R@ SDLENS.BIND LBIND-ATTACH
    R> DROP ;

: _SDLENS-REFRESH-N  ( lens attempts -- status )
    DUP 0= IF 2DROP SDLENS-S-STALE EXIT THEN
    >R DUP _SDLENS-REFRESH-ONCE
    DUP LBIND-S-OK = IF 2DROP R> DROP SDLENS-S-OK EXIT THEN
    LBIND-S-STALE-REVISION <> IF
        DROP R> DROP SDLENS-S-STRUCTURAL EXIT
    THEN
    R> 1- RECURSE ;

: SDLENS-REFRESH  ( lens -- status )
    DUP 0= IF DROP SDLENS-S-STRUCTURAL EXIT THEN
    3 _SDLENS-REFRESH-N ;

\ =====================================================================
\  Discovery and lifecycle
\ =====================================================================

VARIABLE _SDLI-SERVICE-A
VARIABLE _SDLI-SERVICE-U
VARIABLE _SDLI-INSTANCE
VARIABLE _SDLI-LENS
VARIABLE _SDLI-OWNER

: _SDLENS-INIT-BLOCKED  ( -- )
    SDLENS-M-BLOCKED _SDLI-LENS @ SDLENS.MODE ! ;

: _SDLENS-SERVICE  ( id-a id-u destination -- service )
    >R _SDLI-INSTANCE @ CINST-SERVICE DUP R> ! ;

: _SDLENS-INIT  ( service-a service-u instance lens -- )
    _SDLI-LENS ! _SDLI-INSTANCE ! _SDLI-SERVICE-U ! _SDLI-SERVICE-A !
    _SDLI-LENS @ 0= IF EXIT THEN
    _SDLI-LENS @ _SDLENS-STATE-INIT
    _SDLI-INSTANCE @ 0= IF _SDLENS-INIT-BLOCKED EXIT THEN

    \ Only a truly endpoint-free instance is standalone.  Once an endpoint
    \ exists, every Practice service is mandatory and failure stays closed.
    _SDLI-INSTANCE @ CINST.ENDPOINT @ 0= IF EXIT THEN
    S" org.akashic.runtime.context" _SDLI-LENS @ SDLENS.CONTEXT
        _SDLENS-SERVICE
    DUP 0= IF DROP _SDLENS-INIT-BLOCKED EXIT THEN
    DUP CTX-VALID? 0= IF DROP _SDLENS-INIT-BLOCKED EXIT THEN
    CTX.FLAGS @ CTX-F-ACTIVE AND 0= IF _SDLENS-INIT-BLOCKED EXIT THEN

    S" org.akashic.runtime.resource-registry"
        _SDLI-LENS @ SDLENS.RREG _SDLENS-SERVICE
    DUP 0= IF DROP _SDLENS-INIT-BLOCKED EXIT THEN
    DUP RREG-VALID? 0= IF DROP _SDLENS-INIT-BLOCKED EXIT THEN
    _SDLI-LENS @ SDLENS.CONTEXT @ SWAP RREG-CONTEXT? 0= IF
        _SDLENS-INIT-BLOCKED EXIT
    THEN

    S" org.akashic.interop.request-bus" _SDLI-LENS @ SDLENS.BUS
        _SDLENS-SERVICE
    DUP 0= IF DROP _SDLENS-INIT-BLOCKED EXIT THEN
    DUP CBUS.REGISTRY @ _SDLI-LENS @ SDLENS.RREG @ RREG.COMPONENTS @ =
    OVER CBUS.POLICY @ DUP 0<> SWAP
        _SDLI-LENS @ SDLENS.CONTEXT @ CTX.POLICY @ = AND AND
    SWAP _SDLI-LENS @ SDLENS.CONTEXT @ CTX.QUEUE @ = AND 0= IF
        _SDLENS-INIT-BLOCKED EXIT
    THEN

    _SDLI-SERVICE-A @ _SDLI-SERVICE-U @
        _SDLI-INSTANCE @ CINST-SERVICE
    DUP 0= IF DROP _SDLENS-INIT-BLOCKED EXIT THEN
    DUP RID-PRESENT? 0= IF DROP _SDLENS-INIT-BLOCKED EXIT THEN
    _SDLI-LENS @ SDLENS.RID RID-COPY

    _SDLI-LENS @ SDLENS-REFRESH DUP IF
        DROP _SDLENS-INIT-BLOCKED EXIT
    THEN DROP

    \ Revision zero is used only for owner discovery.  Restore the retained
    \ primary reference from its exact binding immediately after resolution.
    0 _SDLI-LENS @ SDLENS.REF RREF.REVISION !
    _SDLI-LENS @ SDLENS.REF
        _SDLI-LENS @ SDLENS.CONTEXT @
        _SDLI-LENS @ SDLENS.RREG @ RREG-RESOLVE
    DUP IF 2DROP _SDLENS-INIT-BLOCKED EXIT THEN
    DROP DUP _SDLI-OWNER ! _SDLI-LENS @ _SDL-OWNER + !
    _SDLI-LENS @ SDLENS.BIND _SDLI-LENS @ SDLENS.REF LBIND-REF
    DUP IF DROP _SDLENS-INIT-BLOCKED EXIT THEN DROP
    _SDLI-OWNER @ DUP CINST.ID @ 0>
    OVER CINST.GENERATION @ 0> AND
    OVER CINST.REVISION @ 0> AND
    SWAP CINST-DESC COMP-CAPS-VALID? AND 0= IF
        _SDLENS-INIT-BLOCKED EXIT
    THEN

    S" resource.snapshot" _SDLI-OWNER @ CINST-DESC COMP-CAP-FIND
    DUP _SDLI-LENS @ SDLENS.SNAPSHOT-CAP !
    DUP 0= IF DROP _SDLENS-INIT-BLOCKED EXIT THEN
    CAP-DESC-VALID? 0= IF _SDLENS-INIT-BLOCKED EXIT THEN
    S" resource.replace" _SDLI-OWNER @ CINST-DESC COMP-CAP-FIND
    DUP _SDLI-LENS @ SDLENS.REPLACE-CAP !
    DUP 0= IF DROP _SDLENS-INIT-BLOCKED EXIT THEN
    CAP-DESC-VALID? 0= IF _SDLENS-INIT-BLOCKED EXIT THEN

    CBR-NEW DUP IF 2DROP _SDLENS-INIT-BLOCKED EXIT THEN
    DROP _SDLI-LENS @ SDLENS.REQUEST !
    SDLENS-M-SHARED _SDLI-LENS @ SDLENS.MODE ! ;

' _SDLENS-INIT CONSTANT _SDLENS-INIT-XT

: SDLENS-INIT  ( service-a service-u instance lens -- )
    \ Storage must be fresh or previously finalized; callers must not
    \ reinitialize a live lens without first releasing its owned request.
    _SDLENS-INIT-XT _SDLENS-GUARD WITH-GUARD ;

: SDLENS-FINI  ( lens -- )
    DUP 0= IF DROP EXIT THEN
    DUP SDLENS.REQUEST @ ?DUP IF CBR-FREE THEN
    _SDLENS-STATE-INIT ;
