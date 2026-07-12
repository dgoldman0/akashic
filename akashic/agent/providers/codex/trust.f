\ =====================================================================
\  trust.f - Reviewed TLS trust provisioning for the Codex source
\ =====================================================================
\  WE1 was retrieved from https://i.pki.goog/we1.crt on 2026-07-11.
\  SHA-256: A287FFAB762CC69A26D482037EDF701F653CE899025C62A7E5CB88BB9B419CBB
\  Validity: 2023-12-13 through 2029-02-20.
\
\  The same CA key is provisioned twice so the native trust store grants
\  exactly auth.openai.com and chatgpt.com. It grants no parent domain,
\  wildcard, API-key endpoint, or unrelated Google-hosted service.
\ =====================================================================

PROVIDED akashic-agent-codex-trust

REQUIRE ../../../net/base64.f

20260711 CONSTANT CODEX-TRUST-GENERATION
658 CONSTANT _CDTR-CERT-SIZE
880 CONSTANT _CDTR-B64-CAP
1408 CONSTANT _CDTR-BUNDLE-CAP

CREATE _CDTR-B64 _CDTR-B64-CAP ALLOT
CREATE _CDTR-CERT _CDTR-CERT-SIZE ALLOT
CREATE _CDTR-BUNDLE _CDTR-BUNDLE-CAP ALLOT

VARIABLE _CDTR-B64-U
VARIABLE _CDTR-POS
VARIABLE _CDTR-A
VARIABLE _CDTR-U
VARIABLE _CDTR-FLAGS

: _CDTR-B64,  ( addr len -- )
    DUP >R _CDTR-B64 _CDTR-B64-U @ + SWAP CMOVE
    R> _CDTR-B64-U +! ;

: _CDTR-DECODE  ( -- ior )
    0 _CDTR-B64-U !
    S" MIICjjCCAjOgAwIBAgIQf/NXaJvCTjAtkOGKQb0OHzAKBggqhkjOPQQDAjBQMSQwIgYDVQQLExtHbG9iYWxTaWduIEVDQyBSb290IENBIC0gUjQxEzARBgNVBAoTCkdsb2JhbFNpZ24xEzARBgNVBAMTCkdsb2JhbFNpZ24wHhcNMjMxMjEzMDkwMDAwWhcNMjkwMjIwMTQwMDAwWjA7MQswCQYD" _CDTR-B64,
    S" VQQGEwJVUzEeMBwGA1UEChMVR29vZ2xlIFRydXN0IFNlcnZpY2VzMQwwCgYDVQQDEwNXRTEwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAARvzTr+Z1dHTCEDhUDCR127WEcPQMFcF4XGGTfn1XzthkubgdnXGhOlCgP4mMTG6J7/EFmPLCaY9eYmJbsPAvpWo4IBAjCB/zAOBgNVHQ8BAf8EBAMC" _CDTR-B64,
    S" AYYwHQYDVR0lBBYwFAYIKwYBBQUHAwEGCCsGAQUFBwMCMBIGA1UdEwEB/wQIMAYBAf8CAQAwHQYDVR0OBBYEFJB3kjVnxP+ozKnme9mAeXvMk/k4MB8GA1UdIwQYMBaAFFSwe61FuOJAf/sKbvu+M8k8o4TVMDYGCCsGAQUFBwEBBCowKDAmBggrBgEFBQcwAoYaaHR0cDovL2kucGtpLmdvb2cv" _CDTR-B64,
    S" Z3NyNC5jcnQwLQYDVR0fBCYwJDAioCCgHoYcaHR0cDovL2MucGtpLmdvb2cvci9nc3I0LmNybDATBgNVHSAEDDAKMAgGBmeBDAECATAKBggqhkjOPQQDAgNJADBGAiEAokJL0LgR6SOLR02WWxccAq3ndXp4EMRveXMUVUxMWSMCIQDspFWa3fj7nLgouSdkcPy1SdOR2AGm9OQWs7veyXsBwA==" _CDTR-B64,
    _CDTR-B64 _CDTR-B64-U @ _CDTR-CERT _CDTR-CERT-SIZE B64-DECODE
    DUP _CDTR-CERT-SIZE <> IF DROP TLS-CERT-MALFORMED EXIT THEN
    DROP B64-OK? IF TLS-CERT-OK ELSE TLS-CERT-MALFORMED THEN ;

: _CDTR-C,  ( byte -- )
    _CDTR-BUNDLE _CDTR-POS @ + C! 1 _CDTR-POS +! ;

: _CDTR-U16,  ( value -- )
    DUP 8 RSHIFT 255 AND _CDTR-C,
    255 AND _CDTR-C, ;

: _CDTR-U32,  ( value -- )
    DUP 24 RSHIFT 255 AND _CDTR-C,
    DUP 16 RSHIFT 255 AND _CDTR-C,
    DUP 8 RSHIFT 255 AND _CDTR-C,
    255 AND _CDTR-C, ;

: _CDTR-BYTES,  ( addr len -- )
    _CDTR-U ! _CDTR-A !
    _CDTR-A @ _CDTR-BUNDLE _CDTR-POS @ + _CDTR-U @ CMOVE
    _CDTR-U @ _CDTR-POS +! ;

: _CDTR-ANCHOR,  ( scope-a scope-u flags -- )
    _CDTR-FLAGS ! _CDTR-U ! _CDTR-A !
    _CDTR-FLAGS @ _CDTR-U16,
    _CDTR-U @ _CDTR-U16,
    _CDTR-CERT-SIZE _CDTR-U32,
    _CDTR-A @ _CDTR-U @ _CDTR-BYTES,
    _CDTR-CERT _CDTR-CERT-SIZE _CDTR-BYTES, ;

: _CDTR-BUILD  ( -- addr len )
    0 _CDTR-POS !
    S" MPTA" _CDTR-BYTES,
    1 _CDTR-U16,
    2 _CDTR-U16,
    0 _CDTR-U32,
    CODEX-TRUST-GENERATION _CDTR-U32,
    S" auth.openai.com" 0 _CDTR-ANCHOR,
    S" chatgpt.com" 0 _CDTR-ANCHOR,
    _CDTR-BUNDLE _CDTR-POS @ ;

: CODEX-TRUST-INSTALL  ( -- ior )
    _CDTR-DECODE ?DUP IF EXIT THEN
    _CDTR-BUILD TLS-TRUST-LOAD ;
