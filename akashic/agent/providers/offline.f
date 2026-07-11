\ =====================================================================
\  offline.f - Native fallback provider with no external dependencies
\ =====================================================================

PROVIDED akashic-agent-offline-provider

REQUIRE ../provider-source.f

VARIABLE _OFP-PROVIDER

: _OFP-CONNECT  ( event-queue context -- ior )
    2DROP 0 ;

: _OFP-DISCONNECT  ( event-queue context -- )
    2DROP ;

: _OFP-START  ( turn event-queue context -- ior )
    2DROP DROP 1 ;

: _OFP-CANCEL  ( run-id event-queue context -- ior )
    2DROP DROP 0 ;

: _OFP-POLL  ( event-queue context -- ior )
    2DROP 0 ;

: OFFLINE-PROVIDER-FREE  ( provider -- )
    FREE ;

: OFFLINE-PROVIDER-NEW  ( -- provider ior )
    AGENT-PROVIDER-SIZE ALLOCATE
    DUP IF SWAP DROP 0 SWAP EXIT THEN
    DROP DUP _OFP-PROVIDER ! APROV-INIT
    S" org.akashic.agent.offline"
    _OFP-PROVIDER @ APROV.ID-U ! _OFP-PROVIDER @ APROV.ID-A !
    APROV-S-OFFLINE _OFP-PROVIDER @ APROV.STATE !
    ['] _OFP-CONNECT _OFP-PROVIDER @ APROV.CONNECT-XT !
    ['] _OFP-DISCONNECT _OFP-PROVIDER @ APROV.DISCONNECT-XT !
    ['] _OFP-START _OFP-PROVIDER @ APROV.START-XT !
    ['] _OFP-CANCEL _OFP-PROVIDER @ APROV.CANCEL-XT !
    ['] _OFP-POLL _OFP-PROVIDER @ APROV.POLL-XT !
    ['] OFFLINE-PROVIDER-FREE _OFP-PROVIDER @ APROV.FREE-XT !
    _OFP-PROVIDER @ 0 ;

: _OFFLINE-SOURCE-CREATE  ( context -- provider status )
    DROP OFFLINE-PROVIDER-NEW ;

: OFFLINE-SOURCE-FREE  ( source -- )
    DUP AGENT-PROVIDER-SOURCE-SIZE 0 FILL FREE ;

VARIABLE _OFS-SOURCE

: OFFLINE-SOURCE-NEW  ( -- source status )
    AGENT-PROVIDER-SOURCE-SIZE ALLOCATE
    DUP IF 2DROP 0 APSOURCE-S-NOMEM EXIT THEN
    DROP DUP _OFS-SOURCE ! APSOURCE-INIT
    S" org.akashic.agent.source.offline"
    _OFS-SOURCE @ APSOURCE.ID-U ! _OFS-SOURCE @ APSOURCE.ID-A !
    ['] _OFFLINE-SOURCE-CREATE _OFS-SOURCE @ APSOURCE.NEW-XT !
    ['] OFFLINE-SOURCE-FREE _OFS-SOURCE @ APSOURCE.FREE-XT !
    _OFS-SOURCE @ APSOURCE-S-OK ;
