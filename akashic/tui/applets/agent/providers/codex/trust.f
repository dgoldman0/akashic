\ =====================================================================
\  trust.f - Reviewed TLS trust contribution for Codex endpoints
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

REQUIRE ../../../../../net/base64.f
REQUIRE ../../../../../net/tls-trust-registry.f

20260711 CONSTANT CODEX-TRUST-REVISION
658 CONSTANT _CDTR-CERT-SIZE
880 CONSTANT _CDTR-B64-CAP

CREATE _CDTR-B64 _CDTR-B64-CAP ALLOT
CREATE _CDTR-CERT _CDTR-CERT-SIZE ALLOT

VARIABLE _CDTR-B64-U

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

VARIABLE _CDTR-BUILDER

: _CDTR-EMIT  ( builder context -- status )
    DROP _CDTR-BUILDER !
    _CDTR-DECODE ?DUP IF EXIT THEN
    _CDTR-CERT _CDTR-CERT-SIZE S" auth.openai.com" 0
        _CDTR-BUILDER @ MTRUST-ANCHOR+ ?DUP IF EXIT THEN
    _CDTR-CERT _CDTR-CERT-SIZE S" chatgpt.com" 0
        _CDTR-BUILDER @ MTRUST-ANCHOR+ ;

: CODEX-TRUST-REGISTER  ( -- status )
    S" org.akashic.trust.codex" ['] _CDTR-EMIT 0 MTRUST-REGISTER ;
