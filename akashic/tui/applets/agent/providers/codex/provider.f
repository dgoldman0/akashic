\ =====================================================================
\  provider.f - Account-backed Codex Responses provider composition
\ =====================================================================
\  This composes the shared native Responses engine with ChatGPT account
\  authentication and Codex request headers. It owns no transport or tokens.
\ =====================================================================

PROVIDED akashic-agent-codex-provider

REQUIRE config.f
REQUIRE auth.f
REQUIRE ../openai/responses.f

VARIABLE _CDPH-REQ
VARIABLE _CDPH-S
VARIABLE _CDPH-P
VARIABLE _CDPH-A
VARIABLE _CDPH-U

: _CODEX-HEADERS  ( request session provider -- status )
    _CDPH-P ! _CDPH-S ! _CDPH-REQ !
    _CDPH-P @ APROV-AUTH AAUTH.ACCOUNT-ID DUP CV-TYPE@ CV-T-STRING <> IF
        DROP OAIR-S-AUTH EXIT
    THEN
    DUP CV-DATA@ SWAP CV-LEN@ DUP 0= IF 2DROP OAIR-S-AUTH EXIT THEN
    S" ChatGPT-Account-ID" 2SWAP _CDPH-REQ @ HREQ-HEADER
    ?DUP IF EXIT THEN
    S" originator" S" akashic" _CDPH-REQ @ HREQ-HEADER ?DUP IF EXIT THEN
    _CDPH-P @ OPENAI-PROVIDER-CONFIG OAIC-RESPONSES-LITE? IF
        S" x-openai-internal-codex-responses-lite" S" true"
        _CDPH-REQ @ HREQ-HEADER ?DUP IF EXIT THEN
    THEN
    _CDPH-S @ OAIR-S.THREAD-ID @ NUM>STR _CDPH-U ! _CDPH-A !
    S" session-id" _CDPH-A @ _CDPH-U @ _CDPH-REQ @ HREQ-HEADER
    ?DUP IF EXIT THEN
    S" thread-id" _CDPH-A @ _CDPH-U @ _CDPH-REQ @ HREQ-HEADER
    ?DUP IF EXIT THEN
    S" x-client-request-id" _CDPH-A @ _CDPH-U @ _CDPH-REQ @ HREQ-HEADER
    ?DUP IF EXIT THEN
    _CDPH-S @ OAIR-S.TURN-STATE-U @ IF
        S" x-codex-turn-state" _CDPH-S @ OAIR-S.TURN-STATE
        _CDPH-S @ OAIR-S.TURN-STATE-U @ _CDPH-REQ @ HREQ-HEADER
        ?DUP IF EXIT THEN
    THEN
    OAIR-S-OK ;

VARIABLE _CDPN-CONFIG
VARIABLE _CDPN-AUTH
VARIABLE _CDPN-PORT
VARIABLE _CDPN-P
VARIABLE _CDPN-STATUS

: CODEX-PROVIDER-NEW  ( config codex-auth-context port -- provider status )
    _CDPN-PORT ! _CDPN-AUTH ! _CDPN-CONFIG !
    _CDPN-CONFIG @ 0= _CDPN-AUTH @ 0= OR _CDPN-PORT @ 0= OR IF
        0 OAIR-S-INVALID EXIT
    THEN
    _CDPN-CONFIG @ _CDPN-AUTH @ CDA.AUTH _CDPN-PORT @ OPENAI-PROVIDER-NEW
    _CDPN-STATUS ! _CDPN-P !
    _CDPN-STATUS @ IF _CDPN-P @ _CDPN-STATUS @ EXIT THEN
    CODEX-PROVIDER-ID _CDPN-P @ APROV.ID-U ! _CDPN-P @ APROV.ID-A !
    ['] _CODEX-HEADERS _CDPN-P @ _CDPN-P @ OPENAI-PROVIDER-HEADERS!
    _CDPN-P @ OAIR-S-OK ;
