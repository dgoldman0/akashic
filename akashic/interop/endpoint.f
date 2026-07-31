\ =====================================================================
\  endpoint.f - Request, intent, and service submission endpoint
\ =====================================================================
\  A live runtime instance may point CINST.ENDPOINT at one of these. The
\  endpoint says only how to enqueue a targeted request or semantic
\  intent; it has no Desk, TUI, agent, provider, or transport dependency.
\ =====================================================================

PROVIDED akashic-interop-endpoint

REQUIRE service-endpoint.f
REQUIRE request-bus.f

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

: CINST-POST  ( request caller -- status )
    DUP >R
    OVER CBR-CALLER!
    R> CINST.ENDPOINT @ IEND-POST ;

: CINST-POST-INTENT  ( id-a id-u request caller -- status )
    DUP >R
    OVER CBR-CALLER!
    R> CINST.ENDPOINT @ IEND-INTENT ;
