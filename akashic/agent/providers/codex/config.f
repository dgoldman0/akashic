\ =====================================================================
\  config.f - Source-pinned Codex endpoint and Responses configuration
\ =====================================================================

PROVIDED akashic-agent-codex-config

REQUIRE ../openai/config.f

: CODEX-BACKEND-HOST  ( -- addr len ) S" chatgpt.com" ;
: CODEX-RESPONSES-PATH  ( -- addr len ) S" /backend-api/codex/responses" ;
: CODEX-COMPAT-VERSION  ( -- addr len ) S" 0.144.0" ;
: CODEX-MODELS-PATH  ( -- addr len )
    S" /backend-api/codex/models?client_version=0.144.0" ;
: CODEX-PROVIDER-ID  ( -- addr len ) S" org.akashic.agent.codex" ;

: CODEX-CONFIG-INIT  ( config -- status )
    DUP OAIC-INIT >R
    CODEX-BACKEND-HOST R@ OAIC-HOST! ?DUP IF R> DROP EXIT THEN
    CODEX-RESPONSES-PATH R@ OAIC-PATH! ?DUP IF R> DROP EXIT THEN
    S" gpt-5.5" R@ OAIC-MODEL! ?DUP IF R> DROP EXIT THEN
    S" You are the integrated Akashic assistant. Work through the active applet capabilities, preserve user data, request review before persistent changes, and explain results in concise plain language."
    R@ OAIC-INSTRUCTIONS! R> DROP ;
