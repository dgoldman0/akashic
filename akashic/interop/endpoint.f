\ =====================================================================
\  endpoint.f - Request, intent, and service submission endpoint
\ =====================================================================
\  A live runtime instance may point CINST.ENDPOINT at one of these. The
\  endpoint says only how to enqueue a targeted request or semantic
\  intent; it has no Desk, TUI, agent, provider, or transport dependency.
\ =====================================================================

PROVIDED akashic-interop-endpoint

REQUIRE request-bus.f

 0 CONSTANT _IEP-CONTEXT
 8 CONSTANT _IEP-POST-XT       \ ( request context -- status )
16 CONSTANT _IEP-INTENT-XT     \ ( id-a id-u request context -- status )
24 CONSTANT _IEP-SERVICE-XT    \ ( id-a id-u context -- service | 0 )
32 CONSTANT _IEP-FLAGS
40 CONSTANT IENDPOINT-SIZE

: IEND.CONTEXT    ( endpoint -- a ) _IEP-CONTEXT + ;
: IEND.POST-XT    ( endpoint -- a ) _IEP-POST-XT + ;
: IEND.INTENT-XT  ( endpoint -- a ) _IEP-INTENT-XT + ;
: IEND.SERVICE-XT ( endpoint -- a ) _IEP-SERVICE-XT + ;
: IEND.FLAGS      ( endpoint -- a ) _IEP-FLAGS + ;

: IENDPOINT-INIT  ( endpoint -- ) IENDPOINT-SIZE 0 FILL ;

: CBR-CALLER!  ( caller request -- )
    >R
    DUP CINST.ID @ R@ CBR.CALLER-ID !
    CINST.GENERATION @ R> CBR.CALLER-GEN ! ;

: CBR-TARGET!  ( target request -- )
    >R
    DUP CINST.ID @ R@ CBR.TARGET-ID !
    CINST.GENERATION @ R> CBR.TARGET-GEN ! ;

: IEND-POST  ( request endpoint -- status )
    DUP 0= IF 2DROP CBUS-S-NOT-FOUND EXIT THEN
    DUP IEND.POST-XT @ ?DUP 0= IF 2DROP CBUS-S-NOT-FOUND EXIT THEN
    >R IEND.CONTEXT @ R> EXECUTE ;

: IEND-INTENT  ( id-a id-u request endpoint -- status )
    DUP 0= IF 2DROP 2DROP CBUS-S-NOT-FOUND EXIT THEN
    DUP IEND.INTENT-XT @ ?DUP 0= IF
        2DROP 2DROP CBUS-S-NO-HANDLER EXIT
    THEN
    >R IEND.CONTEXT @ R> EXECUTE ;

: IEND-SERVICE  ( id-a id-u endpoint -- service | 0 )
    DUP 0= IF DROP 2DROP 0 EXIT THEN
    DUP IEND.SERVICE-XT @ ?DUP 0= IF DROP 2DROP 0 EXIT THEN
    >R IEND.CONTEXT @ R> EXECUTE ;

: CINST-POST  ( request caller -- status )
    DUP >R
    OVER CBR-CALLER!
    R> CINST.ENDPOINT @ IEND-POST ;

: CINST-POST-INTENT  ( id-a id-u request caller -- status )
    DUP >R
    OVER CBR-CALLER!
    R> CINST.ENDPOINT @ IEND-INTENT ;

: CINST-SERVICE  ( id-a id-u instance -- service | 0 )
    CINST.ENDPOINT @ IEND-SERVICE ;
