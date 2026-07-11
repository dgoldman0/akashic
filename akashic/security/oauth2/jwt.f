\ =====================================================================
\  jwt.f - Bounded JWT payload decoding for OAuth claim inspection
\ =====================================================================
\  This decodes claims only; it does not verify signatures. Callers must rely
\  on a trusted issuer exchange and use claims only for local routing/display.
\ =====================================================================

PROVIDED akashic-oauth2-jwt

REQUIRE ../../net/base64.f
REQUIRE ../../utils/json.f

0 CONSTANT O2JWT-S-OK
1 CONSTANT O2JWT-S-INVALID
2 CONSTANT O2JWT-S-CAPACITY

VARIABLE _O2J-A
VARIABLE _O2J-U
VARIABLE _O2J-D
VARIABLE _O2J-CAP
VARIABLE _O2J-FIRST
VARIABLE _O2J-SECOND
VARIABLE _O2J-N

: O2JWT-PAYLOAD  ( jwt-a jwt-u output-a output-u -- length status )
    _O2J-CAP ! _O2J-D ! _O2J-U ! _O2J-A !
    _O2J-A @ 0= _O2J-U @ 5 < OR _O2J-D @ 0= OR _O2J-CAP @ 0> 0= OR IF
        0 O2JWT-S-INVALID EXIT
    THEN
    -1 _O2J-FIRST ! -1 _O2J-SECOND !
    _O2J-U @ 0 ?DO
        _O2J-A @ I + C@ 46 = IF
            _O2J-FIRST @ 0< IF I _O2J-FIRST ! ELSE
                _O2J-SECOND @ 0< IF I _O2J-SECOND ! THEN
            THEN
        THEN
    LOOP
    _O2J-FIRST @ 1 < _O2J-SECOND @ _O2J-FIRST @ 1+ <= OR
    _O2J-SECOND @ _O2J-U @ 1- >= OR IF
        0 O2JWT-S-INVALID EXIT
    THEN
    _O2J-A @ _O2J-FIRST @ 1+ +
    _O2J-SECOND @ _O2J-FIRST @ 1+ -
    _O2J-D @ _O2J-CAP @ B64-DECODE-URL _O2J-N !
    B64-OK? 0= IF 0 O2JWT-S-INVALID EXIT THEN
    _O2J-N @ _O2J-CAP @ > IF 0 O2JWT-S-CAPACITY EXIT THEN
    _O2J-D @ _O2J-N @ JSON-VALID? 0= IF 0 O2JWT-S-INVALID EXIT THEN
    _O2J-D @ _O2J-N @ JSON-OBJECT? 0= IF 0 O2JWT-S-INVALID EXIT THEN
    _O2J-N @ O2JWT-S-OK ;
