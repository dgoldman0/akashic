\ =====================================================================
\  run-grant.f - One-use grants for an Agent run's requests
\ =====================================================================
\  The request bus lets an Agent principal's request through only with
\  a one-use grant bound to that exact request (interop/authority.f).
\  AGRANT-ISSUE issues one into the request's handle from the run that
\  makes it: the run's Mandate must be active, and its facet must allow
\  the request's operation on its target with the flags asked for.  A
\  grant issued on the Mandate's say alone is only for observing; a
\  reviewed commit must fall in the Mandate's commit window.  A grant
\  lasts a minute, and never past the run's deadline.  A request made
\  with no run gets its grant without those checks.
\
\  Public API:
\    AGRANT-ISSUE  ( grant-flags facet-flags request run bus -- status )
\ =====================================================================

PROVIDED akashic-agent-run-grant

REQUIRE mandate-run.f
REQUIRE ../../../interop/request-bus.f
REQUIRE ../../../concurrency/guard.f

60000 CONSTANT AGRANT-LIFE-MS

CREATE _AGI-BIND AUTH-BINDING-SIZE ALLOT
CREATE _AGI-GRANT AUTH-GRANT-SIZE ALLOT
VARIABLE _AGI-GRANT-FLAGS
VARIABLE _AGI-FACET-FLAGS
VARIABLE _AGI-AUTH
VARIABLE _AGI-REQ
VARIABLE _AGI-RUN
VARIABLE _AGI-EXPIRES

GUARD _agrant-guard

: _AGRANT-ISSUE  ( grant-flags facet-flags request run bus -- status )
    DUP IF CBUS.AUTHORITY @ THEN _AGI-AUTH !
    _AGI-RUN ! _AGI-REQ ! _AGI-FACET-FLAGS ! _AGI-GRANT-FLAGS !
    _AGI-AUTH @ 0= _AGI-REQ @ 0= OR IF CBUS-S-INVALID EXIT THEN
    _AGI-RUN @ ?DUP IF
        AMRUN-ACTIVE? 0= IF CBUS-S-DENIED EXIT THEN
        _AGI-REQ @ CBR.TARGET-ID @ _AGI-REQ @ CBR.TARGET-GEN @
        _AGI-REQ @ CBR.CAP @ _AGI-FACET-FLAGS @ _AGI-RUN @
        AMRUN-OP? 0= IF CBUS-S-DENIED EXIT THEN
        _AGI-GRANT-FLAGS @ AGR-F-MANDATE-AUTO = IF
            _AGI-REQ @ CBR.CAP @ CAP.EFFECTS @ CAP-E-OBSERVE <>
            IF CBUS-S-DENIED EXIT THEN
        THEN
        _AGI-GRANT-FLAGS @ AGR-F-REVIEWED-COMMIT = IF
            _AGI-REQ @ CBR.CAP @ CAP.EFFECTS @
            _AGI-RUN @ AMRUN.MANDATE MAND.ACTIVATION-EPOCH @
            MS@ _AGI-RUN @ AMRUN.MANDATE MAND-COMMIT-VALID? 0= IF
                CBUS-S-DENIED EXIT
            THEN
        THEN
    THEN
    _AGI-REQ @ _AGI-BIND CBR-AUTH-BIND! ?DUP IF EXIT THEN
    _AGI-GRANT AGR-INIT
    _AGI-BIND _AGI-GRANT AGR-BIND! ?DUP IF EXIT THEN
    _AGI-GRANT-FLAGS @ _AGI-GRANT AGR.FLAGS !
    MS@ AGRANT-LIFE-MS + _AGI-EXPIRES !
    _AGI-RUN @ ?DUP IF
        AMRUN.DEADLINE-MS @ ?DUP IF
            _AGI-EXPIRES @ MIN _AGI-EXPIRES !
        THEN
    THEN
    _AGI-EXPIRES @ _AGI-GRANT AGR.EXPIRES !
    _AGI-GRANT _AGI-REQ @ CBR.HANDLE _AGI-AUTH @ AHT-ISSUE ;

' _AGRANT-ISSUE CONSTANT _agrant-issue-xt

\ Issues REQUEST a one-use grant of GRANT-FLAGS (AGR-F-) into its handle,
\ from RUN, whose facet must allow the request with FACET-FLAGS
\ (CFENTRY-F-), or from no run when RUN is 0.  BUS holds the authority
\ that seals it.  A CBUS-S- status.
: AGRANT-ISSUE  ( grant-flags facet-flags request run bus -- status )
    _agrant-issue-xt _agrant-guard WITH-GUARD ;
