\ =====================================================================
\  tool-gateway.f - Agent calls over the generic capability request bus
\ =====================================================================
\  This is the only agent-specific translation layer.  Component
\  discovery, policy, request execution, and results remain the generic
\  runtime/interop contracts; providers never receive applet pointers.
\ =====================================================================

PROVIDED akashic-agent-tool-gateway

REQUIRE ../runtime/registry.f
REQUIRE ../interop/capability.f
REQUIRE ../interop/request-bus.f
REQUIRE ../interop/codecs/json-value.f
REQUIRE mandate-run.f
REQUIRE ../concurrency/guard.f

0 CONSTANT ATOOLG-S-IDLE
1 CONSTANT ATOOLG-S-QUEUED
2 CONSTANT ATOOLG-S-APPROVAL
3 CONSTANT ATOOLG-S-COMPLETE

  0 CONSTANT _ATG-REGISTRY
  8 CONSTANT _ATG-BUS
 16 CONSTANT _ATG-CALLER
 24 CONSTANT _ATG-FOCUSED
 32 CONSTANT _ATG-REQUEST
 40 CONSTANT _ATG-STATE
 48 CONSTANT _ATG-RUN-ID
 56 CONSTANT _ATG-REVISION
 64 CONSTANT _ATG-NAME
104 CONSTANT _ATG-CATALOG-N
112 CONSTANT _ATG-REGISTRY-N
120 CONSTANT _ATG-CATALOG
64 CONSTANT ATOOLG-MAX-TOOLS
_ATG-CATALOG ATOOLG-MAX-TOOLS 8 * + CONSTANT _ATG-MANDATE-RUN
_ATG-MANDATE-RUN 8 + CONSTANT _ATG-ARGS-LEN
_ATG-ARGS-LEN 8 + CONSTANT _ATG-ARGS-DIGEST
_ATG-ARGS-DIGEST SHA3-256-LEN + CONSTANT _ATG-AUDIT-FLAGS
_ATG-AUDIT-FLAGS 8 + CONSTANT _ATG-RESULT-RESERVED
_ATG-RESULT-RESERVED 8 + CONSTANT AGENT-TOOL-GATEWAY-SIZE

1 CONSTANT ATOOLG-AF-ARGS-FINGERPRINT
2 CONSTANT ATOOLG-AF-RESULT-SUPPRESSED
65536 CONSTANT ATOOLG-ARGS-CANONICAL-MAX
4096 CONSTANT ATOOLG-ARGS-REVIEW-MAX
32768 CONSTANT ATOOLG-RESULT-JSON-CAPACITY
4 CONSTANT ATOOLG-RESULT-FALLBACK-BYTES       \ compact JSON `null`

\ Gateway state and the module scratch used to mutate it share one recursive
\ boundary.  No word may hold this guard while entering CBUS: completion runs
\ from inside CBUS dispatch and acquires the guard in the opposite direction.
GUARD _atoolg-state-guard

: ATOOLG.REGISTRY  ( gateway -- a ) _ATG-REGISTRY + ;
: ATOOLG.BUS       ( gateway -- a ) _ATG-BUS + ;
: ATOOLG.CALLER    ( gateway -- a ) _ATG-CALLER + ;
: ATOOLG.FOCUSED   ( gateway -- a ) _ATG-FOCUSED + ;
: ATOOLG.REQUEST   ( gateway -- a ) _ATG-REQUEST + ;
: ATOOLG.STATE     ( gateway -- a ) _ATG-STATE + ;
: ATOOLG.RUN-ID    ( gateway -- a ) _ATG-RUN-ID + ;
: ATOOLG.REVISION  ( gateway -- a ) _ATG-REVISION + ;
: ATOOLG.NAME      ( gateway -- value ) _ATG-NAME + ;
: ATOOLG.CATALOG-N ( gateway -- a ) _ATG-CATALOG-N + ;
: ATOOLG.REGISTRY-N ( gateway -- a ) _ATG-REGISTRY-N + ;
: ATOOLG.CATALOG   ( gateway -- a ) _ATG-CATALOG + ;
: ATOOLG.MANDATE-RUN ( gateway -- a ) _ATG-MANDATE-RUN + ;
: ATOOLG.ARGS-LEN    ( gateway -- a ) _ATG-ARGS-LEN + ;
: ATOOLG.ARGS-DIGEST ( gateway -- a ) _ATG-ARGS-DIGEST + ;
: ATOOLG.AUDIT-FLAGS ( gateway -- a ) _ATG-AUDIT-FLAGS + ;
: ATOOLG.RESULT-RESERVED ( gateway -- a ) _ATG-RESULT-RESERVED + ;

\ Refund some or all of a gateway's pre-dispatch result reservation.  The
\ gateway owns at most one request, so its cell is also the exact outstanding
\ reservation for cancellation and setup-failure cleanup.
: _ATOOLG-DISCLOSURE-REFUND  ( bytes gateway -- )
    >R
    DUP 0< IF DROP R> DROP EXIT THEN
    R@ ATOOLG.RESULT-RESERVED @ MIN
    DUP R@ ATOOLG.MANDATE-RUN @ ?DUP IF
        AMRUN-DISCLOSE-REFUND
    ELSE
        DROP
    THEN
    NEGATE R@ ATOOLG.RESULT-RESERVED +!
    R> DROP ;

: _ATOOLG-DISCLOSURE-REFUND-ALL  ( gateway -- )
    DUP ATOOLG.RESULT-RESERVED @ SWAP _ATOOLG-DISCLOSURE-REFUND ;

: ATOOLG-SCOPED?  ( gateway -- flag )
    ATOOLG.MANDATE-RUN @ 0<> ;

: ATOOLG-TOOL-N  ( gateway -- count ) ATOOLG.CATALOG-N @ ;

: ATOOLG-TOOL-NTH  ( index gateway -- cap | 0 )
    >R DUP 0< OVER R@ ATOOLG.CATALOG-N @ >= OR IF
        DROP R> DROP 0 EXIT
    THEN
    8 * R> ATOOLG.CATALOG + @ ;

VARIABLE _ATGFP-G
VARIABLE _ATGFP-BUF
VARIABLE _ATGFP-CAP
GUARD _atoolg-canonical-guard

\ The request owns a recursive CV-COPY of provider arguments.  Review,
\ audit, and dispatch all address this one immutable gateway request.
: ATOOLG-ARGS-VALUE  ( gateway -- value | 0 )
    ATOOLG.REQUEST @ DUP IF CBR.ARGS THEN ;

\ Canonical form is type-tagged IVJSON over the owned CV.  CV map insertion
\ order is preserved, so the same exact request has one byte encoding.
: _ATOOLG-ARGS-CANONICAL  ( buffer capacity gateway -- length status )
    _ATGFP-G ! _ATGFP-CAP ! _ATGFP-BUF !
    _ATGFP-G @ ATOOLG-ARGS-VALUE DUP 0= IF
        DROP 0 IVJSON-E-INVALID EXIT
    THEN
    _ATGFP-BUF @ _ATGFP-CAP @ IVJSON-TYPED-ENCODE ;

: ATOOLG-ARGS-CANONICAL  ( buffer capacity gateway -- length status )
    ['] _ATOOLG-ARGS-CANONICAL _atoolg-canonical-guard WITH-GUARD ;

\ Return caller-owned canonical bytes.  This avoids a borrowed module-global
\ review buffer whose contents another gateway could change after return.
: ATOOLG-ARGS-CANONICAL-ALLOC  ( gateway -- addr length status )
    >R ATOOLG-ARGS-CANONICAL-MAX ALLOCATE DUP IF
        NIP R> DROP 0 0 ROT EXIT
    THEN
    DROP DUP ATOOLG-ARGS-CANONICAL-MAX R> ATOOLG-ARGS-CANONICAL
    DUP IF
        >R DROP FREE 0 0 R>
    THEN ;

: _ATOOLG-ARGS-FINGERPRINT-CLEAR  ( gateway -- )
    DUP 0 SWAP ATOOLG.ARGS-LEN !
    DUP ATOOLG.ARGS-DIGEST SHA3-256-LEN 0 FILL
    0 SWAP ATOOLG.AUDIT-FLAGS ! ;

: _ATOOLG-ARGS-FINGERPRINT-LOCKED!  ( gateway -- status )
    DUP _ATGFP-G ! _ATOOLG-ARGS-FINGERPRINT-CLEAR
    _ATGFP-G @ ATOOLG.REQUEST @ DUP 0= IF
        DROP CBUS-S-INVALID EXIT
    THEN
    DUP CBR-ARGS-SEAL! ?DUP IF 2DROP CBUS-S-INVALID EXIT THEN
    DUP CBR.ARGS-LEN @ _ATGFP-G @ ATOOLG.ARGS-LEN !
    CBR.ARGS-DIGEST _ATGFP-G @ ATOOLG.ARGS-DIGEST
        SHA3-256-LEN MOVE
    ATOOLG-AF-ARGS-FINGERPRINT _ATGFP-G @ ATOOLG.AUDIT-FLAGS !
    CBUS-S-OK ;

: _ATOOLG-ARGS-FINGERPRINT!  ( gateway -- status )
    ['] _ATOOLG-ARGS-FINGERPRINT-LOCKED!
        _atoolg-canonical-guard WITH-GUARD ;

: ATOOLG-ARGS-FINGERPRINT  ( gateway -- digest-a digest-u canonical-u | 0 0 0 )
    DUP ATOOLG.AUDIT-FLAGS @ ATOOLG-AF-ARGS-FINGERPRINT AND 0= IF
        DROP 0 0 0 EXIT
    THEN
    DUP ATOOLG.ARGS-DIGEST SHA3-256-LEN ROT ATOOLG.ARGS-LEN @ ;

: _ATOOLG-ARGS-FINGERPRINT-MATCH?  ( gateway -- flag )
    DUP _ATGFP-G ! ATOOLG.AUDIT-FLAGS @
        ATOOLG-AF-ARGS-FINGERPRINT AND 0= IF 0 EXIT THEN
    _ATGFP-G @ ATOOLG.REQUEST @ DUP 0= IF DROP 0 EXIT THEN
    DUP CBR-ARGS-SEAL-MATCH? 0= IF DROP 0 EXIT THEN
    DUP CBR.ARGS-LEN @ _ATGFP-G @ ATOOLG.ARGS-LEN @ <> IF
        DROP 0 EXIT
    THEN
    CBR.ARGS-DIGEST _ATGFP-G @ ATOOLG.ARGS-DIGEST
        SHA3-256-COMPARE ;

: ATOOLG-ARGS-FINGERPRINT-MATCH?  ( gateway -- flag )
    ['] _ATOOLG-ARGS-FINGERPRINT-MATCH?
        _atoolg-canonical-guard WITH-GUARD ;

\ Approval is meaningful only when the complete immutable operand can be
\ presented to the reviewer.  This check lives below the UI so every caller,
\ including direct runtime and gateway clients, shares the same boundary.
: ATOOLG-ARGS-REVIEWABLE?  ( gateway -- flag )
    DUP ATOOLG.AUDIT-FLAGS @ ATOOLG-AF-ARGS-FINGERPRINT AND 0= IF
        DROP 0 EXIT
    THEN
    DUP ATOOLG.ARGS-LEN @ ATOOLG-ARGS-REVIEW-MAX > IF DROP 0 EXIT THEN
    ATOOLG-ARGS-FINGERPRINT-MATCH? ;

: _ATOOLG-EXPOSED?  ( cap -- flag )
    DUP CAP-DESC-VALID? 0= IF DROP 0 EXIT THEN
    DUP CAP.HANDLER-XT @ 0= IF DROP 0 EXIT THEN
    \ A null input schema is the established no-arguments `{}` projection.
    \ When a typed input exists it must share the same bounded JSON graph.
    DUP CAP.IN-SCHEMA @ ?DUP IF
        IVJSON-SCHEMA-COMPATIBLE? 0= IF DROP 0 EXIT THEN
    THEN
    DUP CAP.OUT-SCHEMA @ DUP 0= IF 2DROP 0 EXIT THEN
    IVJSON-SCHEMA-COMPATIBLE? 0= IF DROP 0 EXIT THEN
    CAP.KIND @ DUP CAP-K-COMMAND = SWAP CAP-K-RESOURCE = OR ;

VARIABLE _ATGH-CAP
VARIABLE _ATGH-G

: _ATOOLG-CATALOG-HAS?  ( cap gateway -- flag )
    _ATGH-G ! _ATGH-CAP !
    _ATGH-G @ ATOOLG.CATALOG-N @ 0 ?DO
        I _ATGH-G @ ATOOLG-TOOL-NTH CAP-ID
        _ATGH-CAP @ CAP-ID STR-STR= IF -1 UNLOOP EXIT THEN
    LOOP
    0 ;

VARIABLE _ATGA-CAP
VARIABLE _ATGA-INST
VARIABLE _ATGA-G

VARIABLE _ATGS-INST
VARIABLE _ATGS-CAP
VARIABLE _ATGS-G
VARIABLE _ATGS-RUN
VARIABLE _ATGS-FLAGS

: _ATOOLG-REQUIRED?  ( instance cap required-flags gateway -- flag )
    _ATGS-G ! _ATGS-FLAGS ! _ATGS-CAP ! _ATGS-INST !
    _ATGS-G @ ATOOLG.MANDATE-RUN @ ?DUP IF
        _ATGS-RUN !
        _ATGS-INST @ CINST.ID @ _ATGS-INST @ CINST.GENERATION @
        _ATGS-CAP @ _ATGS-FLAGS @ _ATGS-RUN @ AMRUN-OP? DUP IF
            _ATGS-FLAGS @ CFENTRY-F-DISCLOSE-RESULT AND IF
                CFENTRY.MAX-RESULT @ ATOOLG-RESULT-FALLBACK-BYTES >=
            ELSE
                DROP -1
            THEN
        THEN
    ELSE
        -1
    THEN ;

: _ATOOLG-CATALOG+  ( instance cap gateway -- status )
    _ATGA-G ! _ATGA-CAP ! _ATGA-INST !
    _ATGA-CAP @ _ATOOLG-EXPOSED? 0= IF 0 EXIT THEN
    _ATGA-INST @ _ATGA-CAP @
        CFENTRY-F-VISIBLE CFENTRY-F-DISCLOSE-RESULT OR
        _ATGA-G @ _ATOOLG-REQUIRED? 0= IF
        0 EXIT
    THEN
    _ATGA-CAP @ _ATGA-G @ _ATOOLG-CATALOG-HAS? IF 0 EXIT THEN
    _ATGA-G @ ATOOLG.CATALOG-N @ ATOOLG-MAX-TOOLS >= IF 1 EXIT THEN
    _ATGA-CAP @
    _ATGA-G @ ATOOLG.CATALOG-N @ 8 * _ATGA-G @ ATOOLG.CATALOG + !
    1 _ATGA-G @ ATOOLG.CATALOG-N +!
    0 ;

VARIABLE _ATGI-INST
VARIABLE _ATGI-G
VARIABLE _ATGI-DESC

: _ATOOLG-INSTANCE+  ( instance gateway -- status )
    _ATGI-G ! _ATGI-INST !
    _ATGI-INST @ 0= IF 0 EXIT THEN
    _ATGI-INST @ CINST-DESC _ATGI-DESC !
    _ATGI-DESC @ COMP.CAPS-N @ 0 ?DO
        _ATGI-INST @ I _ATGI-DESC @ COMP-CAP-NTH
            _ATGI-G @ _ATOOLG-CATALOG+
        ?DUP IF UNLOOP EXIT THEN
    LOOP
    0 ;

VARIABLE _ATGRF-G
VARIABLE _ATGRF-INST
VARIABLE _ATGRF-FOCUSED
VARIABLE _ATGLF-G
VARIABLE _ATGLF-INST

\ FOCUS is only an ambient preference, never an owning reference.  Validate
\ its pointer by equality against the live registry before any dereference;
\ applet close removes the registry entry before freeing the CINST.
: _ATOOLG-LIVE-FOCUSED  ( gateway -- instance | 0 )
    DUP _ATGLF-G ! ATOOLG.FOCUSED @ DUP 0= IF EXIT THEN
    _ATGLF-INST !
    _ATGLF-G @ ATOOLG.REGISTRY @ CREG.INST-N @ 0 ?DO
        I _ATGLF-G @ ATOOLG.REGISTRY @ CREG-INST-NTH
        _ATGLF-INST @ = IF _ATGLF-INST @ UNLOOP EXIT THEN
    LOOP
    0 _ATGLF-G @ ATOOLG.FOCUSED ! 0 ;

: ATOOLG-REFRESH  ( gateway -- status )
    DUP 0= IF DROP 1 EXIT THEN
    DUP _ATGRF-G !
    DUP ATOOLG.CATALOG ATOOLG-MAX-TOOLS 8 * 0 FILL
    0 SWAP ATOOLG.CATALOG-N !
    _ATGRF-G @ _ATOOLG-LIVE-FOCUSED DUP _ATGRF-FOCUSED !
    _ATGRF-G @ _ATOOLG-INSTANCE+
    ?DUP IF EXIT THEN
    _ATGRF-G @ ATOOLG.REGISTRY @ CREG.INST-N @ 0 ?DO
        I _ATGRF-G @ ATOOLG.REGISTRY @ CREG-INST-NTH DUP _ATGRF-INST !
        _ATGRF-FOCUSED @ <> IF
            _ATGRF-INST @ _ATGRF-G @ _ATOOLG-INSTANCE+ ?DUP IF
                UNLOOP EXIT
            THEN
        THEN
    LOOP
    _ATGRF-G @ ATOOLG.REGISTRY @ CREG.INST-N @
    _ATGRF-G @ ATOOLG.REGISTRY-N !
    1 _ATGRF-G @ ATOOLG.REVISION +!
    0 ;

VARIABLE _ATGFO-INST
VARIABLE _ATGFO-G

: ATOOLG-FOCUSED!  ( instance gateway -- status )
    _ATGFO-G ! _ATGFO-INST !
    _ATGFO-G @ ATOOLG-SCOPED? IF 0 EXIT THEN
    _ATGFO-INST @ _ATGFO-G @ ATOOLG.FOCUSED @ =
    _ATGFO-G @ ATOOLG.REGISTRY @ CREG.INST-N @
    _ATGFO-G @ ATOOLG.REGISTRY-N @ = AND IF 0 EXIT THEN
    _ATGFO-INST @ _ATGFO-G @ ATOOLG.FOCUSED !
    _ATGFO-G @ ATOOLG-REFRESH ;

VARIABLE _ATGM-RUN
VARIABLE _ATGM-G

: ATOOLG-MANDATE!  ( mandate-run gateway -- status )
    _ATGM-G ! _ATGM-RUN !
    _ATGM-G @ 0= _ATGM-RUN @ AMRUN-ACTIVE? 0= OR IF
        CBUS-S-INVALID EXIT
    THEN
    _ATGM-G @ ATOOLG.STATE @ ATOOLG-S-IDLE <> IF
        CBUS-S-BUSY EXIT
    THEN
    _ATGM-G @ ATOOLG.MANDATE-RUN @ _ATGM-RUN @ = IF
        _ATGM-G @ ATOOLG-REFRESH EXIT
    THEN
    _ATGM-RUN @ AMRUN-RETAIN ?DUP IF
        DROP CBUS-S-INVALID EXIT
    THEN
    _ATGM-G @ _ATOOLG-DISCLOSURE-REFUND-ALL
    _ATGM-G @ ATOOLG.MANDATE-RUN @ ?DUP IF AMRUN-RELEASE THEN
    _ATGM-RUN @ _ATGM-G @ ATOOLG.MANDATE-RUN !
    _ATGM-G @ ATOOLG-REFRESH ;

: ATOOLG-MANDATE-CLEAR  ( gateway -- status )
    DUP 0= IF DROP CBUS-S-INVALID EXIT THEN
    DUP ATOOLG.STATE @ ATOOLG-S-IDLE <> IF DROP CBUS-S-BUSY EXIT THEN
    DUP _ATOOLG-DISCLOSURE-REFUND-ALL
    DUP ATOOLG.MANDATE-RUN @ >R
    0 OVER ATOOLG.MANDATE-RUN !
    R> ?DUP IF AMRUN-RELEASE THEN
    ATOOLG-REFRESH ;

VARIABLE _ATGN-REG
VARIABLE _ATGN-BUS
VARIABLE _ATGN-CALLER

: ATOOLG-NEW  ( registry bus caller -- gateway ior )
    _ATGN-CALLER ! _ATGN-BUS ! _ATGN-REG !
    AGENT-TOOL-GATEWAY-SIZE ALLOCATE
    DUP IF EXIT THEN
    DROP DUP AGENT-TOOL-GATEWAY-SIZE 0 FILL
    _ATGN-REG @ OVER ATOOLG.REGISTRY !
    _ATGN-BUS @ OVER ATOOLG.BUS !
    _ATGN-CALLER @ OVER ATOOLG.CALLER !
    1 OVER ATOOLG.REVISION !
    DUP ATOOLG-REFRESH ?DUP IF
        >R FREE 0 R> EXIT
    THEN
    0 ;

VARIABLE _ATGF-A
VARIABLE _ATGF-U
VARIABLE _ATGF-G
VARIABLE _ATGF-INST
VARIABLE _ATGF-CAP

: _ATOOLG-FIND-ON  ( id-a id-u instance -- cap | 0 )
    DUP 0= IF DROP 2DROP 0 EXIT THEN
    CINST-DESC COMP-CAP-FIND ;

: ATOOLG-FIND  ( id-a id-u gateway -- instance cap | 0 0 )
    _ATGF-G ! _ATGF-U ! _ATGF-A !
    _ATGF-G @ _ATOOLG-LIVE-FOCUSED ?DUP IF
        DUP _ATGF-INST !
        _ATGF-A @ _ATGF-U @ ROT _ATOOLG-FIND-ON
        DUP IF
            DUP _ATOOLG-EXPOSED? IF
                _ATGF-INST @ OVER
                    CFENTRY-F-INVOKE CFENTRY-F-DISCLOSE-RESULT OR
                    _ATGF-G @ _ATOOLG-REQUIRED? IF
                    _ATGF-INST @ SWAP EXIT
                THEN
            THEN
        THEN DROP
    THEN
    _ATGF-G @ ATOOLG.REGISTRY @ CREG.INST-N @ 0 ?DO
        I _ATGF-G @ ATOOLG.REGISTRY @ CREG-INST-NTH
        DUP _ATGF-INST !
        _ATGF-A @ _ATGF-U @ ROT _ATOOLG-FIND-ON
        DUP IF
            DUP _ATOOLG-EXPOSED? IF
                _ATGF-INST @ OVER
                    CFENTRY-F-INVOKE CFENTRY-F-DISCLOSE-RESULT OR
                    _ATGF-G @ _ATOOLG-REQUIRED? IF
                    _ATGF-INST @ SWAP UNLOOP EXIT
                THEN
            THEN
        THEN DROP
    LOOP
    0 0 ;

\ Public gateway mutations defined above are wrapped here so their complete
\ bodies, including reservation refunds, cannot race a completion callback.
\ Their internal calls remain safe because the guard is recursive.
' ATOOLG-REFRESH CONSTANT _atoolg-refresh-xt
' ATOOLG-FOCUSED! CONSTANT _atoolg-focused-store-xt
' ATOOLG-MANDATE! CONSTANT _atoolg-mandate-store-xt
' ATOOLG-MANDATE-CLEAR CONSTANT _atoolg-mandate-clear-xt
' ATOOLG-FIND CONSTANT _atoolg-find-xt
' ATOOLG-NEW CONSTANT _atoolg-new-xt

: ATOOLG-REFRESH  ( gateway -- status )
    _atoolg-refresh-xt _atoolg-state-guard WITH-GUARD ;

: ATOOLG-FOCUSED!  ( instance gateway -- status )
    _atoolg-focused-store-xt _atoolg-state-guard WITH-GUARD ;

: ATOOLG-MANDATE!  ( mandate-run gateway -- status )
    _atoolg-mandate-store-xt _atoolg-state-guard WITH-GUARD ;

: ATOOLG-MANDATE-CLEAR  ( gateway -- status )
    _atoolg-mandate-clear-xt _atoolg-state-guard WITH-GUARD ;

: ATOOLG-FIND  ( id-a id-u gateway -- instance cap | 0 0 )
    _atoolg-find-xt _atoolg-state-guard WITH-GUARD ;

: ATOOLG-NEW  ( registry bus caller -- gateway ior )
    \ CBR/gateway heap ownership is core-0-only under KDOS.  Reject worker
    \ construction before ALLOCATE and serialize the module constructor frame.
    COREID IF 2DROP DROP 0 CBUS-S-INVALID EXIT THEN
    _atoolg-new-xt _atoolg-state-guard WITH-GUARD ;

CREATE _ATGIG-BIND AUTH-BINDING-SIZE ALLOT
CREATE _ATGIG-GRANT AUTH-GRANT-SIZE ALLOT
VARIABLE _ATGIG-GRANT-FLAGS
VARIABLE _ATGIG-FACET-FLAGS
VARIABLE _ATGIG-G
VARIABLE _ATGIG-AUTH
VARIABLE _ATGIG-REQ
VARIABLE _ATGIG-RUN
VARIABLE _ATGIG-EXPIRES

: _ATOOLG-ISSUE-GRANT  ( grant-flags required-facet-flags gateway -- status )
    _ATGIG-G ! _ATGIG-FACET-FLAGS ! _ATGIG-GRANT-FLAGS !
    _ATGIG-G @ ATOOLG.BUS @ CBUS.AUTHORITY @ DUP 0= IF
        DROP CBUS-S-INVALID EXIT
    THEN
    _ATGIG-AUTH !
    _ATGIG-G @ ATOOLG.REQUEST @ DUP 0= IF
        DROP CBUS-S-INVALID EXIT
    THEN
    _ATGIG-REQ !
    _ATGIG-G @ ATOOLG.MANDATE-RUN @ ?DUP IF
        DUP _ATGIG-RUN ! AMRUN-ACTIVE? 0= IF CBUS-S-DENIED EXIT THEN
        _ATGIG-REQ @ CBR.TARGET-ID @ _ATGIG-REQ @ CBR.TARGET-GEN @
        _ATGIG-REQ @ CBR.CAP @ _ATGIG-FACET-FLAGS @ _ATGIG-RUN @
        AMRUN-OP? 0= IF CBUS-S-DENIED EXIT THEN
        _ATGIG-GRANT-FLAGS @ AGR-F-MANDATE-AUTO = IF
            _ATGIG-REQ @ CBR.CAP @ CAP.EFFECTS @ CAP-E-OBSERVE <>
            IF CBUS-S-DENIED EXIT THEN
        THEN
        _ATGIG-GRANT-FLAGS @ AGR-F-REVIEWED-COMMIT = IF
            _ATGIG-REQ @ CBR.CAP @ CAP.EFFECTS @
            _ATGIG-RUN @ AMRUN.MANDATE MAND.ACTIVATION-EPOCH @
            MS@ _ATGIG-RUN @ AMRUN.MANDATE MAND-COMMIT-VALID? 0= IF
                CBUS-S-DENIED EXIT
            THEN
        THEN
    THEN
    _ATGIG-REQ @ _ATGIG-BIND CBR-AUTH-BIND! ?DUP IF EXIT THEN
    _ATGIG-GRANT AGR-INIT
    _ATGIG-BIND _ATGIG-GRANT AGR-BIND! ?DUP IF EXIT THEN
    _ATGIG-GRANT-FLAGS @ _ATGIG-GRANT AGR.FLAGS !
    MS@ 60000 + _ATGIG-EXPIRES !
    _ATGIG-G @ ATOOLG.MANDATE-RUN @ ?DUP IF
        AMRUN.DEADLINE-MS @ ?DUP IF
            _ATGIG-EXPIRES @ MIN _ATGIG-EXPIRES !
        THEN
    THEN
    _ATGIG-EXPIRES @ _ATGIG-GRANT AGR.EXPIRES !
    _ATGIG-GRANT _ATGIG-REQ @ CBR.HANDLE _ATGIG-AUTH @ AHT-ISSUE ;

0x7FFFFFFFFFFFFFFF CONSTANT _ATOOLG-DISCLOSURE-MAX
CREATE _ATGR-JSON ATOOLG-RESULT-JSON-CAPACITY ALLOT

\ Measure the exact compact JSON representation delivered to model context.
\ The scalar compatibility helper below saturates on a codec failure; the
\ completion gate instead substitutes a bounded null while preserving a
\ handler success that may already include committed owner-side effects.
: _ATOOLG-RESULT-JSON-SIZE-RAW  ( value -- bytes ior )
    _ATGR-JSON ATOOLG-RESULT-JSON-CAPACITY IVJSON-ENCODE ;

GUARD _atoolg-result-guard

\ Encoding is used only for measurement.  The scratch can contain exact tool
\ output, including credentials or private document text, so erase the whole
\ capacity before releasing the guard on both ordinary and exceptional exits.
: _ATOOLG-RESULT-JSON-SIZE-AROUND  ( value xt -- bytes ior )
    \ Keeping the cleanup frame independent of the encoder also makes the
    \ exceptional path directly testable instead of relying on a codec bug to
    \ throw after writing sensitive bytes.
    CATCH
    _ATGR-JSON ATOOLG-RESULT-JSON-CAPACITY 0 FILL
    ?DUP IF THROW THEN ;

: _ATOOLG-RESULT-JSON-SIZE-CLEAN  ( value -- bytes ior )
    ['] _ATOOLG-RESULT-JSON-SIZE-RAW _ATOOLG-RESULT-JSON-SIZE-AROUND ;

' _ATOOLG-RESULT-JSON-SIZE-CLEAN CONSTANT _atoolg-result-json-size-xt
: _ATOOLG-RESULT-JSON-SIZE
    _atoolg-result-json-size-xt _atoolg-result-guard WITH-GUARD ;

: _ATOOLG-RESULT-BYTES  ( value -- bytes )
    _ATOOLG-RESULT-JSON-SIZE
    DUP IF 2DROP _ATOOLG-DISCLOSURE-MAX ELSE DROP THEN ;

VARIABLE _ATGD-REQ
VARIABLE _ATGD-G
VARIABLE _ATGD-BYTES

: _ATOOLG-RESULT-SUPPRESS  ( error-a error-u error-code -- )
    _ATGD-REQ @ CBR.RESULT CV-FREE
    _ATGD-REQ @ CBR.RESULT CV-NULL!
    _ATGD-REQ @ CBR-ERROR!
    _ATGD-G @ ATOOLG.AUDIT-FLAGS DUP @
        ATOOLG-AF-RESULT-SUPPRESSED OR SWAP !
    ATOOLG-RESULT-FALLBACK-BYTES _ATGD-BYTES ! ;

: _ATOOLG-DISCLOSURE-GATE  ( request gateway -- status )
    _ATGD-G ! _ATGD-REQ !
    _ATGD-REQ @ CBR.STATUS @ CBUS-S-OK <> IF
        \ Approval is an intermediate dispatch result; keep its reservation
        \ across review and requeue.  Every terminal non-success refunds it.
        _ATGD-REQ @ CBR.STATUS @ CBUS-S-NEEDS-APPROVAL <> IF
            _ATGD-G @ _ATOOLG-DISCLOSURE-REFUND-ALL
        THEN
        AMRUN-S-OK EXIT
    THEN
    _ATGD-REQ @ CBR.RESULT _ATOOLG-RESULT-JSON-SIZE DUP IF
        >R DROP
        \ A handler may already have committed owner-side effects.  Preserve
        \ success and substitute a bounded JSON null even on an unscoped
        \ gateway, so a provider cannot interpret a projection defect as a
        \ retryable operation failure and duplicate the effect.
        S" Tool result was suppressed after an encoding contract breach"
            R> _ATOOLG-RESULT-SUPPRESS
    ELSE
        DROP _ATGD-BYTES !
    THEN
    _ATGD-G @ ATOOLG.MANDATE-RUN @ ?DUP 0= IF
        AMRUN-S-OK EXIT
    THEN
    DROP
    _ATGD-G @ ATOOLG.RESULT-RESERVED @ DUP
        ATOOLG-RESULT-FALLBACK-BYTES < IF
        DROP AMRUN-S-DENIED EXIT
    THEN
    _ATGD-BYTES @ < IF
        S" Tool result was suppressed after exceeding its declared bound"
            AMRUN-S-BUDGET _ATOOLG-RESULT-SUPPRESS
    THEN
    _ATGD-G @ ATOOLG.RESULT-RESERVED @ _ATGD-BYTES @ -
        _ATGD-G @ _ATOOLG-DISCLOSURE-REFUND
    \ The bytes left in AMRUN.DISCLOSURE-USED are now delivered usage, not
    \ an outstanding reservation.  Clearing this ownership cell without a
    \ second refund keeps CLEAR and the next call from erasing that charge.
    0 _ATGD-G @ ATOOLG.RESULT-RESERVED !
    AMRUN-S-OK ;

: _ATOOLG-COMPLETE-BODY  ( request -- )
    DUP _ATGD-REQ ! CBR.COMPLETE-DATA @ DUP _ATGD-G ! >R
    _ATGD-REQ @ _ATGD-G @ _ATOOLG-DISCLOSURE-GATE ?DUP IF
        _ATGD-REQ @ CBR.RESULT CV-FREE
        _ATGD-REQ @ CBR.ERROR-U @ 0= IF
            S" Mandate disclosure denied the tool result" ROT
                _ATGD-REQ @ CBR-ERROR!
            CBUS-S-DENIED
        ELSE
            DROP CBUS-S-FAILED
        THEN
        _ATGD-REQ @ CBR.STATUS !
    THEN
    _ATGD-REQ @
    CBR.STATUS @ CBUS-S-NEEDS-APPROVAL = IF
        ATOOLG-S-APPROVAL
    ELSE
        ATOOLG-S-COMPLETE
    THEN
    R@ ATOOLG.STATE !
    1 R> ATOOLG.REVISION +! ;

\ Pump callbacks run under the request-bus guard.  They enter only the gateway
\ state guard; every public POST/DISPATCH path releases it before entering the
\ bus, preventing an AB/BA lock cycle across cores.
' _ATOOLG-COMPLETE-BODY CONSTANT _atoolg-complete-body-xt
: _ATOOLG-COMPLETE  ( request -- )
    _atoolg-complete-body-xt _atoolg-state-guard WITH-GUARD ;

VARIABLE _ATGC-A
VARIABLE _ATGC-U
VARIABLE _ATGC-ARGS
VARIABLE _ATGC-RUN
VARIABLE _ATGC-G
VARIABLE _ATGC-INST
VARIABLE _ATGC-CAP
VARIABLE _ATGC-REQ
VARIABLE _ATGC-MRUN
VARIABLE _ATGC-RESERVED
VARIABLE _ATGC-ENTRY
VARIABLE _ATGC-MAX-RESULT
VARIABLE _ATGC-CALL-A
VARIABLE _ATGC-CALL-U

: _ATOOLG-REVOKE-REQUEST-HANDLE  ( gateway -- )
    DUP ATOOLG.REQUEST @ ?DUP IF
        DUP CBR.HANDLE IH-VALID? IF
            CBR.HANDLE SWAP ATOOLG.BUS @ CBUS.AUTHORITY @ ?DUP IF
                AHT-REVOKE DROP
            ELSE
                DROP
            THEN
        ELSE
            2DROP
        THEN
    ELSE
        DROP
    THEN ;

: ATOOLG-FREE  ( gateway -- )
    DUP 0= IF DROP EXIT THEN
    DUP ATOOLG.STATE @ DUP ATOOLG-S-QUEUED =
    SWAP ATOOLG-S-APPROVAL = OR IF
        DROP CBUS-E-DISPATCH-ACTIVE THROW
    THEN
    DUP _ATOOLG-DISCLOSURE-REFUND-ALL
    DUP _ATOOLG-REVOKE-REQUEST-HANDLE
    DUP ATOOLG.REQUEST @ ?DUP IF CBR-FREE THEN
    DUP ATOOLG.MANDATE-RUN @ >R
    0 OVER ATOOLG.MANDATE-RUN !
    R> ?DUP IF AMRUN-RELEASE THEN
    DUP ATOOLG.NAME CV-FREE
    FREE ;

: _ATOOLG-CALL-CLEANUP  ( status -- status )
    _ATGC-G @ _ATOOLG-DISCLOSURE-REFUND-ALL
    _ATGC-G @ _ATOOLG-REVOKE-REQUEST-HANDLE
    _ATGC-REQ @ ?DUP IF CBR-FREE THEN
    0 _ATGC-G @ ATOOLG.REQUEST !
    _ATGC-G @ ATOOLG.NAME CV-FREE
    _ATGC-G @ _ATOOLG-ARGS-FINGERPRINT-CLEAR
    ATOOLG-S-IDLE _ATGC-G @ ATOOLG.STATE !
    _ATGC-RESERVED @ IF
        _ATGC-G @ ATOOLG.MANDATE-RUN @ ?DUP IF AMRUN-TOOL-REFUND THEN
        0 _ATGC-RESERVED !
    THEN ;

: _ATOOLG-CALL-ERROR  ( status -- 0 0 0 0 status )
    >R 0 0 0 0 R> ;

: _ATOOLG-CALL-CLEANUP-ERROR  ( status -- 0 0 0 0 status )
    _ATOOLG-CALL-CLEANUP _ATOOLG-CALL-ERROR ;

: _ATOOLG-CALL-PREP
  ( id-a id-u args run-id call-a call-u gateway -- gateway mandate-run request bus status )
    _ATGC-G ! _ATGC-CALL-U ! _ATGC-CALL-A !
    _ATGC-RUN ! _ATGC-ARGS ! _ATGC-U ! _ATGC-A !
    0 _ATGC-REQ ! 0 _ATGC-MRUN ! 0 _ATGC-RESERVED !
    0 _ATGC-ENTRY ! 0 _ATGC-MAX-RESULT !
    _ATGC-CALL-U @ 0<
    _ATGC-CALL-U @ 0> _ATGC-CALL-A @ 0= AND OR IF
        CBUS-S-INVALID _ATOOLG-CALL-ERROR EXIT
    THEN
    _ATGC-G @ ATOOLG.STATE @ ATOOLG-S-IDLE <> IF
        CBUS-S-BUSY _ATOOLG-CALL-ERROR EXIT
    THEN
    _ATGC-G @ _ATOOLG-DISCLOSURE-REFUND-ALL
    _ATGC-A @ _ATGC-U @ _ATGC-G @ ATOOLG-FIND
    _ATGC-CAP ! _ATGC-INST !
    _ATGC-CAP @ 0= IF
        CBUS-S-NO-HANDLER _ATOOLG-CALL-ERROR EXIT
    THEN
    _ATGC-G @ ATOOLG.MANDATE-RUN @ ?DUP IF
        DUP _ATGC-MRUN ! AMRUN-TOOL-RESERVE ?DUP IF
            _ATOOLG-CALL-ERROR EXIT
        THEN
        -1 _ATGC-RESERVED !
        \ Reserve the facet's complete declared result allowance before any
        \ handler or reviewed effect can run.  Completion charges the actual
        \ compact JSON size and refunds the unused remainder.
        _ATGC-INST @ CINST.ID @ _ATGC-INST @ CINST.GENERATION @
        _ATGC-CAP @ CFENTRY-F-DISCLOSE-RESULT _ATGC-MRUN @ AMRUN-OP?
        DUP 0= IF
            DROP CBUS-S-DENIED _ATOOLG-CALL-CLEANUP-ERROR EXIT
        THEN _ATGC-ENTRY !
        _ATGC-ENTRY @ CFENTRY.MAX-RESULT @ DUP
        ATOOLG-RESULT-FALLBACK-BYTES < IF
            DROP
            CBUS-S-INVALID _ATOOLG-CALL-CLEANUP-ERROR EXIT
        THEN
        \ The provider projection cannot deliver more than its own bounded
        \ JSON buffer.  A broader facet remains callable: reserve the maximum
        \ deliverable value and suppress any larger handler result to null.
        ATOOLG-RESULT-JSON-CAPACITY MIN _ATGC-MAX-RESULT !
        _ATGC-MAX-RESULT @ _ATGC-ENTRY @ _ATGC-MRUN @
            AMRUN-DISCLOSE-RESERVE ?DUP IF
            _ATOOLG-CALL-CLEANUP-ERROR EXIT
        THEN
        _ATGC-MAX-RESULT @ _ATGC-G @ ATOOLG.RESULT-RESERVED !
    THEN
    CBR-NEW DUP IF
        NIP _ATOOLG-CALL-CLEANUP-ERROR EXIT
    THEN DROP
    DUP _ATGC-REQ ! _ATGC-G @ ATOOLG.REQUEST !
    _ATGC-A @ _ATGC-U @ _ATGC-G @ ATOOLG.NAME CV-STRING! ?DUP IF
        _ATOOLG-CALL-CLEANUP-ERROR EXIT
    THEN
    _ATGC-ARGS @ _ATGC-REQ @ CBR.ARGS CV-COPY ?DUP IF
        DROP CBUS-S-INVALID _ATOOLG-CALL-CLEANUP-ERROR EXIT
    THEN
    \ Seal the canonical deep copy before the request can enter the bus.
    _ATGC-G @ _ATOOLG-ARGS-FINGERPRINT! ?DUP IF
        _ATOOLG-CALL-CLEANUP-ERROR EXIT
    THEN
    CPRINC-AGENT _ATGC-REQ @ CBR.PRINCIPAL !
    _ATGC-G @ ATOOLG.CALLER @ ?DUP IF
        DUP CINST.ID @ _ATGC-REQ @ CBR.CALLER-ID !
        CINST.GENERATION @ _ATGC-REQ @ CBR.CALLER-GEN !
    THEN
    _ATGC-INST @ CINST.ID @ _ATGC-REQ @ CBR.TARGET-ID !
    _ATGC-INST @ CINST.GENERATION @ _ATGC-REQ @ CBR.TARGET-GEN !
    _ATGC-INST @ CINST.REVISION @ _ATGC-REQ @ CBR.EXPECT-REV !
    _ATGC-CAP @ _ATGC-REQ @ CBR.CAP !
    _ATGC-MRUN @ IF
        _ATGC-MRUN @ AMRUN.CONTEXT @ DUP CTX.ID @
            _ATGC-REQ @ CBR.CONTEXT-ID !
        CTX.GENERATION @ _ATGC-REQ @ CBR.CONTEXT-GEN !
        _ATGC-MRUN @ AMRUN.MANDATE MAND.ACTIVATION-EPOCH @
            _ATGC-REQ @ CBR.EPOCH !
        _ATGC-MRUN @ AMRUN.MANDATE MAND.PRACTICE-ID
            _ATGC-REQ @ CBR.PRACTICE-ID RID-COPY
        _ATGC-MRUN @ AMRUN.MANDATE MAND.ID
            _ATGC-REQ @ CBR.MANDATE-ID RID-COPY
    ELSE
        _ATGC-G @ ATOOLG.CALLER @ ?DUP IF
            DUP CINST.ID @ _ATGC-REQ @ CBR.CONTEXT-ID !
            CINST.GENERATION @ _ATGC-REQ @ CBR.CONTEXT-GEN !
        THEN
        _ATGC-G @ ATOOLG.BUS @ CBUS.AUTHORITY @ ?DUP IF
            AHT.EPOCH @ _ATGC-REQ @ CBR.EPOCH !
        THEN
    THEN
    _ATGC-REQ @ CBR.INVOCATION-ID RID-CLEAR
    _ATGC-RUN @ _ATGC-REQ @ CBR.INVOCATION-ID !
    _ATGC-G @ ATOOLG.REVISION @
        _ATGC-REQ @ CBR.INVOCATION-ID 8 + !
    _ATGC-INST @ CINST.ID @
        _ATGC-REQ @ CBR.INVOCATION-ID 16 + !
    _ATGC-INST @ CINST.GENERATION @
        _ATGC-REQ @ CBR.INVOCATION-ID 24 + !
    ['] _ATOOLG-COMPLETE _ATGC-REQ @ CBR.COMPLETE-XT !
    _ATGC-G @ _ATGC-REQ @ CBR.COMPLETE-DATA !
    _ATGC-RUN @ _ATGC-G @ ATOOLG.RUN-ID !
    _ATGC-CALL-U @ IF
        \ Fold the provider's call identity before publication.  The previous
        \ post-then-reseal sequence let another core dispatch a provisional
        \ invocation and consume the wrong automatic grant.
        SHA3-256-BEGIN
        _ATGC-G @ ATOOLG.RUN-ID 8 SHA3-256-ADD
        _ATGC-CALL-A @ _ATGC-CALL-U @ SHA3-256-ADD
        _ATGC-G @ ATOOLG.NAME DUP CV-DATA@ SWAP CV-LEN@ SHA3-256-ADD
        _ATGC-REQ @ CBR.INVOCATION-ID SHA3-256-END
    THEN
    _ATGC-MRUN @ IF
        _ATGC-INST @ _ATGC-CAP @ CFENTRY-F-AUTO-OBSERVE
            _ATGC-G @ _ATOOLG-REQUIRED? IF
            AGR-F-MANDATE-AUTO
            CFENTRY-F-INVOKE CFENTRY-F-AUTO-OBSERVE OR
            _ATGC-G @ _ATOOLG-ISSUE-GRANT ?DUP IF
                _ATOOLG-CALL-CLEANUP-ERROR EXIT
            THEN
        THEN
    THEN
    ATOOLG-S-QUEUED _ATGC-G @ ATOOLG.STATE !
    1 _ATGC-G @ ATOOLG.REVISION +!
    _ATGC-G @ _ATGC-MRUN @ _ATGC-REQ @
        _ATGC-G @ ATOOLG.BUS @ CBUS-S-OK ;

' _ATOOLG-CALL-PREP CONSTANT _atoolg-call-prep-xt

: _ATOOLG-CALL-PREP-GUARDED
  ( id-a id-u args run-id call-a call-u gateway -- gateway mandate-run request bus status )
    _atoolg-call-prep-xt _atoolg-state-guard WITH-GUARD ;

: _ATOOLG-POST-ROLLBACK-BODY  ( gateway mandate-run status -- status )
    >R _ATGC-MRUN ! DUP _ATGC-G !
    DUP ATOOLG.REQUEST @ _ATGC-REQ !
    _ATGC-MRUN @ 0<> _ATGC-RESERVED !
    R> _ATOOLG-CALL-CLEANUP ;

' _ATOOLG-POST-ROLLBACK-BODY CONSTANT _atoolg-post-rollback-xt
: _ATOOLG-POST-ROLLBACK  ( gateway mandate-run status -- status )
    _atoolg-post-rollback-xt _atoolg-state-guard WITH-GUARD ;

: _ATOOLG-CBUS-POST-CATCH  ( request bus -- status throw-code )
    ['] CBUS-POST CATCH DUP IF
        >R 2DROP CBUS-S-FAILED R>
    THEN ;

: _ATOOLG-CALL-POST
  ( gateway mandate-run request bus status -- status )
    DUP IF >R 2DROP 2DROP R> EXIT THEN DROP
    2SWAP 2>R
    _ATOOLG-CBUS-POST-CATCH
    2R> 2SWAP >R
    DUP IF
        _ATOOLG-POST-ROLLBACK
    ELSE
        >R 2DROP R>
    THEN
    R> ?DUP IF NIP THROW THEN ;

\ Build and seal under the gateway state boundary, then publish only after
\ releasing it.  The gateway/request pair returned on the data stack is this
\ call's owned continuation state; no module scratch is consulted by POST.
: ATOOLG-CALL  ( id-a id-u args run-id gateway -- status )
    \ Request construction owns KDOS heap storage and therefore remains on
    \ the owner core just like ATOOLG-NEW.  Reject before guarded preparation
    \ can reach CBR-NEW or any other allocator-backed path.
    COREID IF 2DROP 2DROP DROP CBUS-S-INVALID EXIT THEN
    >R 0 0 R> _ATOOLG-CALL-PREP-GUARDED _ATOOLG-CALL-POST ;

: ATOOLG-CALL-WITH-ID
  ( id-a id-u args run-id call-a call-u gateway -- status )
    COREID IF 2DROP 2DROP 2DROP DROP CBUS-S-INVALID EXIT THEN
    _ATOOLG-CALL-PREP-GUARDED _ATOOLG-CALL-POST ;

VARIABLE _ATGR-APPROVED
VARIABLE _ATGR-G

VARIABLE _ATGR-STATUS

0 CONSTANT _ATGR-ACTION-NONE
1 CONSTANT _ATGR-ACTION-POST
2 CONSTANT _ATGR-ACTION-DISPATCH

: _ATOOLG-ISSUE-APPROVAL  ( gateway -- status )
    AGR-F-REVIEWED-COMMIT
    CFENTRY-F-INVOKE CFENTRY-F-REVIEW-COMMIT OR ROT
    _ATOOLG-ISSUE-GRANT ;

: _ATOOLG-RESOLVE-ERROR  ( status -- 0 0 0 0 status )
    >R 0 0 0 0 R> ;

: _ATOOLG-RESOLVE-PREP
  ( approved gateway -- gateway action request bus status )
    _ATGR-G ! _ATGR-APPROVED !
    _ATGR-G @ ATOOLG.STATE @ ATOOLG-S-APPROVAL <> IF
        CBUS-S-INVALID _ATOOLG-RESOLVE-ERROR EXIT
    THEN
    _ATGR-APPROVED @ IF
        \ Review must authorize the exact owned arguments that were shown
        \ when the call was created.  Any mutation, codec drift, or operand
        \ too large for complete review denies, regardless of caller.
        _ATGR-G @ ATOOLG-ARGS-REVIEWABLE? 0= IF
            CBUS-S-DENIED _ATOOLG-RESOLVE-ERROR EXIT
        THEN
        _ATGR-G @ ATOOLG.BUS @ CBUS.AUTHORITY @ IF
            _ATGR-G @ _ATOOLG-ISSUE-APPROVAL DUP _ATGR-STATUS !
            IF _ATGR-STATUS @ _ATOOLG-RESOLVE-ERROR EXIT THEN
            ATOOLG-S-QUEUED _ATGR-G @ ATOOLG.STATE !
            1 _ATGR-G @ ATOOLG.REVISION +!
            _ATGR-G @ _ATGR-ACTION-POST
                _ATGR-G @ ATOOLG.REQUEST @
                _ATGR-G @ ATOOLG.BUS @ CBUS-S-OK EXIT
        ELSE
            _ATGR-G @ ATOOLG.REQUEST @ CBR-APPROVE
            ATOOLG-S-QUEUED _ATGR-G @ ATOOLG.STATE !
            1 _ATGR-G @ ATOOLG.REVISION +!
            _ATGR-G @ _ATGR-ACTION-DISPATCH
                _ATGR-G @ ATOOLG.REQUEST @
                _ATGR-G @ ATOOLG.BUS @ CBUS-S-OK EXIT
        THEN
    ELSE
        CBUS-S-DENIED _ATGR-G @ ATOOLG.REQUEST @ CBR.STATUS !
        MS@ _ATGR-G @ ATOOLG.REQUEST @ CBR.END-MS !
        _ATGR-G @ _ATOOLG-DISCLOSURE-REFUND-ALL
        ATOOLG-S-COMPLETE _ATGR-G @ ATOOLG.STATE !
        1 _ATGR-G @ ATOOLG.REVISION +!
        _ATGR-G @ _ATGR-ACTION-NONE 0 0 CBUS-S-OK EXIT
    THEN
    CBUS-S-FAILED _ATOOLG-RESOLVE-ERROR ;

' _ATOOLG-RESOLVE-PREP CONSTANT _atoolg-resolve-prep-xt
: _ATOOLG-RESOLVE-PREP-GUARDED
  ( approved gateway -- gateway action request bus status )
    _atoolg-resolve-prep-xt _atoolg-state-guard WITH-GUARD ;

: _ATOOLG-RESOLVE-ROLLBACK-BODY  ( gateway status -- status )
    >R
    DUP ATOOLG.STATE @ ATOOLG-S-QUEUED = IF
        DUP _ATOOLG-REVOKE-REQUEST-HANDLE
        ATOOLG-S-APPROVAL OVER ATOOLG.STATE !
        1 SWAP ATOOLG.REVISION +!
    ELSE
        DROP
    THEN
    R> ;

' _ATOOLG-RESOLVE-ROLLBACK-BODY CONSTANT _atoolg-resolve-rollback-xt
: _ATOOLG-RESOLVE-ROLLBACK  ( gateway status -- status )
    _atoolg-resolve-rollback-xt _atoolg-state-guard WITH-GUARD ;

: _ATOOLG-CBUS-DISPATCH-CATCH  ( request bus -- status throw-code )
    ['] CBUS-DISPATCH CATCH DUP IF
        >R 2DROP CBUS-S-FAILED R>
    THEN ;

: _ATOOLG-RESOLVE-POST  ( gateway action request bus -- status )
    _ATOOLG-CBUS-POST-CATCH
    >R SWAP DROP
    DUP IF _ATOOLG-RESOLVE-ROLLBACK ELSE NIP THEN
    R> ?DUP IF NIP THROW THEN ;

: _ATOOLG-RESOLVE-DISPATCH  ( gateway action request bus -- status )
    _ATOOLG-CBUS-DISPATCH-CATCH
    >R >R DROP
    R> DROP CBUS-S-OK
    R> ?DUP IF
        >R DROP CBUS-S-FAILED _ATOOLG-RESOLVE-ROLLBACK DROP
        R> THROW
    THEN
    NIP ;

: _ATOOLG-RESOLVE-PUBLISH
  ( gateway action request bus status -- status )
    DUP IF >R 2DROP 2DROP R> EXIT THEN DROP
    2 PICK CASE
        _ATGR-ACTION-NONE OF 2DROP 2DROP CBUS-S-OK ENDOF
        _ATGR-ACTION-POST OF _ATOOLG-RESOLVE-POST ENDOF
        _ATGR-ACTION-DISPATCH OF _ATOOLG-RESOLVE-DISPATCH ENDOF
        2DROP 2DROP CBUS-S-FAILED SWAP
    ENDCASE ;

: ATOOLG-RESOLVE  ( approved gateway -- status )
    _ATOOLG-RESOLVE-PREP-GUARDED _ATOOLG-RESOLVE-PUBLISH ;

: ATOOLG-CANCEL  ( gateway -- status )
    DUP ATOOLG.STATE @ CASE
        ATOOLG-S-IDLE OF DROP CBUS-S-OK ENDOF
        ATOOLG-S-QUEUED OF
            DUP _ATOOLG-REVOKE-REQUEST-HANDLE
            DUP ATOOLG.REQUEST @ CBR-CANCEL DROP CBUS-S-OK
        ENDOF
        ATOOLG-S-APPROVAL OF
            DUP ATOOLG.REQUEST @ DUP CBR-CANCEL
            CBUS-S-CANCELLED SWAP CBR.STATUS !
            DUP _ATOOLG-DISCLOSURE-REFUND-ALL
            ATOOLG-S-COMPLETE OVER ATOOLG.STATE !
            1 SWAP ATOOLG.REVISION +! CBUS-S-OK
        ENDOF
        2DROP CBUS-S-OK 0
    ENDCASE ;

: ATOOLG-CLEAR  ( gateway -- status )
    DUP ATOOLG.STATE @ DUP ATOOLG-S-QUEUED =
    SWAP ATOOLG-S-APPROVAL = OR IF DROP CBUS-S-BUSY EXIT THEN
    DUP _ATOOLG-REVOKE-REQUEST-HANDLE
    DUP _ATOOLG-DISCLOSURE-REFUND-ALL
    DUP ATOOLG.REQUEST @ ?DUP IF CBR-FREE THEN
    0 OVER ATOOLG.REQUEST !
    DUP ATOOLG.NAME CV-FREE
    DUP _ATOOLG-ARGS-FINGERPRINT-CLEAR
    ATOOLG-S-IDLE OVER ATOOLG.STATE !
    0 OVER ATOOLG.RUN-ID !
    1 SWAP ATOOLG.REVISION +! CBUS-S-OK ;

\ Lifecycle cleanup owns the same state/refund domain as preparation and
\ completion.  FREE may release the last retained AMRUN, but the guard itself
\ is module-owned, so WITH-GUARD never dereferences the freed gateway.
' ATOOLG-FREE CONSTANT _atoolg-free-xt
' ATOOLG-CANCEL CONSTANT _atoolg-cancel-xt
' ATOOLG-CLEAR CONSTANT _atoolg-clear-xt

: ATOOLG-FREE  ( gateway -- )
    _atoolg-free-xt _atoolg-state-guard WITH-GUARD ;

: ATOOLG-CANCEL  ( gateway -- status )
    _atoolg-cancel-xt _atoolg-state-guard WITH-GUARD ;

: ATOOLG-CLEAR  ( gateway -- status )
    _atoolg-clear-xt _atoolg-state-guard WITH-GUARD ;
