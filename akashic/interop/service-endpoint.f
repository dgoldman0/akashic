\ =====================================================================
\  service-endpoint.f - Lightweight runtime service discovery endpoint
\ =====================================================================
\  A live runtime instance may point CINST.ENDPOINT at this fixed record.
\  Service discovery is a borrowed-pointer lookup: the endpoint callback
\  owns routing and lifetime policy, while the caller receives no ownership
\  over the returned service.
\
\  The complete interop endpoint extends this same record with request and
\  intent callbacks.  Keeping the layout and service-only operations here
\  lets components discover runtime services without importing request-bus,
\  schema, JSON, authority, Desk, TUI, provider, or transport machinery.
\ =====================================================================

PROVIDED akashic-isvc-endpoint

REQUIRE ../runtime/instance.f

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

: IEND-SERVICE  ( id-a id-u endpoint -- service | 0 )
    DUP 0= IF DROP 2DROP 0 EXIT THEN
    DUP IEND.SERVICE-XT @ ?DUP 0= IF DROP 2DROP 0 EXIT THEN
    >R IEND.CONTEXT @ R> EXECUTE ;

: CINST-SERVICE  ( id-a id-u instance -- service | 0 )
    CINST.ENDPOINT @ IEND-SERVICE ;
