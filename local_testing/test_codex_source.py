"""The Codex provider source, tui/applets/agent/providers/codex/source.f.

The contract builds the source, its provider and a runtime on the emulator
and checks the configured hosts, device sign-in, the catalog's settings, the
Responses-lite header, and cleanup when cancellation fails.  The provider
contributes no TLS anchor: its hosts, like every public host, verify against
the machine's global root set, so the composed trust in this image, which
carries no root set, stays empty.
"""

from __future__ import annotations

import sys
from pathlib import Path

LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402
from contract_script import run_profile_smoke  # noqa: E402

AUTOEXEC = r"""\ autoexec.f - owned Codex provider source
ENTER-USERLAND
." [akashic] loading Codex provider source" CR
REQUIRE tui/applets/agent/providers/codex/source.f
REQUIRE tui/applets/agent/runtime.f
REQUIRE net/tls-trust-registry.f

VARIABLE _cm-fails
VARIABLE _cm-checks
VARIABLE _cm-depth
VARIABLE _cm-source
VARIABLE _cm-provider
VARIABLE _cm-runtime
VARIABLE _cm-trust-generation
VARIABLE _cm-cancels
VARIABLE _cm-closes
VARIABLE _cm-failure-source
VARIABLE _cm-auth-cancels
VARIABLE _cm-model-cancels
CREATE _cm-wire 4096 ALLOT
CREATE _cm-request HTTP-REQUEST-SIZE ALLOT
CREATE _cm-session 256 ALLOT
: _cm-assert  ( flag -- )
    1 _cm-checks +!
    0= IF 1 _cm-fails +! ." ASSERT " _cm-checks @ . CR THEN ;
: _cm-stack  ( -- )
    DEPTH DUP _cm-depth @ <> IF
        ." STACK " _cm-depth @ . ." -> " DUP . CR .S CR
    THEN
    _cm-depth @ = _cm-assert ;

: _cm-cancel  ( context -- ) DROP 1 _cm-cancels +! ;
: _cm-close  ( context -- ) DROP 1 _cm-closes +! -792 THROW ;
: _cm-auth-cancel-fail  ( context -- )
    DROP 1 _cm-auth-cancels +! -795 THROW ;
: _cm-auth-cancel-ok  ( context -- ) DROP 1 _cm-auth-cancels +! ;
: _cm-model-cancel  ( context -- ) DROP 1 _cm-model-cancels +! ;
: _cm-free-failure-source  ( -- ) _cm-failure-source @ CODEX-SOURCE-FREE ;

: _cm-test-cancel-exhaustion  ( -- )
    0 _cm-auth-cancels ! 0 _cm-model-cancels !
    CODEX-SOURCE-NEW
    DUP APSOURCE-S-OK = _cm-assert DROP _cm-failure-source !
    ['] _cm-auth-cancel-fail
    _cm-failure-source @ CODEX-SOURCE-AUTH-TRANSPORT
    KDOSTLS.PORT NIO.CANCEL-XT !
    ['] _cm-model-cancel
    _cm-failure-source @ CODEX-SOURCE-MODEL-TRANSPORT
    KDOSTLS.PORT NIO.CANCEL-XT !
    ['] _cm-free-failure-source CATCH
    KDOSTLS-E-CLEANUP NEGATE = _cm-assert
    _cm-auth-cancels @ 1 = _cm-assert
    _cm-model-cancels @ 1 = _cm-assert
    _cm-failure-source @ DUP APSOURCE.ID-A @ SWAP APSOURCE.ID-U @
    S" org.akashic.agent.source.codex" STR-STR= _cm-assert

    _cm-failure-source @ CODEX-SOURCE-AUTH-TRANSPORT KDOSTLS.PORT NIO-INIT
    ['] _cm-auth-cancel-ok
    _cm-failure-source @ CODEX-SOURCE-AUTH-TRANSPORT
    KDOSTLS.PORT NIO.CANCEL-XT !
    _cm-failure-source @ CODEX-SOURCE-FREE
    _cm-auth-cancels @ 2 = _cm-assert
    _cm-model-cancels @ 1 = _cm-assert ;

: _cm-run  ( -- )
    0 _cm-fails ! 0 _cm-checks ! 0 _cm-cancels ! 0 _cm-closes !
    DEPTH _cm-depth !
    TLS-TRUST-COUNT @ 0= _cm-assert
    CODEX-SOURCE-NEW
    DUP APSOURCE-S-OK = _cm-assert DROP _cm-source !
    ['] _cm-cancel _cm-source @ CODEX-SOURCE-AUTH-TRANSPORT
        KDOSTLS.PORT NIO.CANCEL-XT !
    ['] _cm-close _cm-source @ CODEX-SOURCE-AUTH-TRANSPORT
        KDOSTLS.PORT NIO.CLOSE-XT !
    ['] _cm-cancel _cm-source @ CODEX-SOURCE-MODEL-TRANSPORT
        KDOSTLS.PORT NIO.CANCEL-XT !
    ['] _cm-close _cm-source @ CODEX-SOURCE-MODEL-TRANSPORT
        KDOSTLS.PORT NIO.CLOSE-XT !
    TLS-TRUST-COUNT @ 0= _cm-assert
    TLS-TRUST-GENERATION @ 0= _cm-assert
    MTRUST-FREEZE MTRUST-S-OK = _cm-assert
    MTRUST-FROZEN? _cm-assert
    MTRUST-GENERATION@ DUP 0<> _cm-assert
    DUP _cm-trust-generation ! TLS-TRUST-GENERATION @ = _cm-assert
    MTRUST-FREEZE MTRUST-S-OK = _cm-assert
    _cm-source @ CODEX-SOURCE-CONFIG OAIC-HOST
    CODEX-BACKEND-HOST STR-STR= _cm-assert
    _cm-source @ CODEX-SOURCE-AUTH-TRANSPORT KDOSTLS-HOST
    CODEX-AUTH-HOST STR-STR= _cm-assert
    _cm-source @ CODEX-SOURCE-MODEL-TRANSPORT KDOSTLS-HOST
    CODEX-BACKEND-HOST STR-STR= _cm-assert
    _cm-source @ CODEX-SOURCE-AUTH CDA.AUTH AAUTH.METHODS @
    AAUTH-M-DEVICE AND 0<> _cm-assert

    _cm-source @ APSOURCE-PROVIDER-NEW
    DUP OAIR-S-OK = _cm-assert DROP _cm-provider !
    _cm-provider @ DUP APROV.ID-A @ SWAP APROV.ID-U @
    CODEX-PROVIDER-ID STR-STR= _cm-assert
    _cm-provider @ APROV-AUTH
    _cm-source @ CODEX-SOURCE-AUTH CDA.AUTH = _cm-assert
    \ The provider adds no anchor of its own: its hosts verify against the
    \ machine's global root set, absent from this image.
    TLS-TRUST-COUNT @ 0= _cm-assert
    TLS-TRUST-VERSION @ TLS-TRUST-FORMAT = _cm-assert
    TLS-TRUST-GENERATION @ _cm-trust-generation @ = _cm-assert
    _cm-provider @ APROV-RUN-SETTINGS
    _cm-source @ CODEX-SOURCE-CATALOG CDMC.SETTINGS = _cm-assert
    _cm-source @ CODEX-SOURCE-CATALOG CDMC.CONFIG @
    _cm-provider @ OPENAI-PROVIDER-CONFIG = _cm-assert
    \ A turn that names its model is configured from the catalog.
    _cm-provider @ APROV.CONTEXT @ DUP OAIR-C.DESIGNATE-XT @
    ['] CDMC-DESIGNATE = _cm-assert
    OAIR-C.DESIGNATE-CONTEXT @ _cm-source @ CODEX-SOURCE-CATALOG = _cm-assert
    _cm-provider @ APROV.FEATURES @ APROV-F-CONTEXT AND 0<> _cm-assert
    _cm-provider @ ARUNTIME-NEW DUP 0= _cm-assert DROP _cm-runtime !
    _cm-runtime @ ARUNTIME-AUTH DUP 0<> _cm-assert
    AAUTH.STATE @ AAUTH-STATE-SIGNED-OUT = _cm-assert
    _cm-runtime @ ARUNTIME-RUN-SETTINGS
    _cm-source @ CODEX-SOURCE-CATALOG CDMC.SETTINGS = _cm-assert
    S" hello" _cm-runtime @ ARUNTIME-SEND 4 = _cm-assert

    S" account-fixture"
    _cm-source @ CODEX-SOURCE-AUTH CDA.AUTH AAUTH.ACCOUNT-ID CV-STRING!
    0= _cm-assert
    _cm-provider @ OPENAI-PROVIDER-CONFIG OAIC.FLAGS DUP @
    OAIC-F-RESPONSES-LITE OR SWAP !
    _cm-wire 4096 _cm-request HREQ-INIT HREQ-S-OK = _cm-assert
    S" POST" CODEX-RESPONSES-PATH _cm-request HREQ-BEGIN
    HREQ-S-OK = _cm-assert
    _cm-session 256 0 FILL 42 _cm-session OAIR-S.THREAD-ID !
    _cm-provider @ OPENAI-PROVIDER-CONFIG _cm-session OAIR-S.CONFIG !
    _cm-request _cm-session _cm-provider @ _CODEX-HEADERS
    OAIR-S-OK = _cm-assert
    _cm-wire _cm-request HREQ.LENGTH @
    S" x-openai-internal-codex-responses-lite: true"
    STR-STR-CONTAINS _cm-assert
    \ The headers follow the session's own configuration, which a turn
    \ naming its model has, not the provider's.
    _cm-request HREQ-CLEAR
    S" POST" CODEX-RESPONSES-PATH _cm-request HREQ-BEGIN
    HREQ-S-OK = _cm-assert
    _cm-source @ CODEX-SOURCE-CONFIG _cm-session OAIR-S.CONFIG !
    _cm-request _cm-session _cm-provider @ _CODEX-HEADERS
    OAIR-S-OK = _cm-assert
    _cm-wire _cm-request HREQ.LENGTH @
    S" x-openai-internal-codex-responses-lite: true"
    STR-STR-CONTAINS 0= _cm-assert
    _cm-runtime @ ARUNTIME-FREE
    _cm-provider @ APROV-FREE
    _cm-source @ APSOURCE-FREE
    _cm-cancels @ 2 = _cm-assert
    _cm-closes @ 0= _cm-assert
    TLS-TRUST-COUNT @ 0= _cm-assert
    TLS-TRUST-GENERATION @ _cm-trust-generation @ = _cm-assert
    _cm-test-cancel-exhaustion
    _cm-stack
    _cm-fails @ 0= IF
        ." CODEX SOURCE PASS " _cm-checks @ .
    ELSE
        ." CODEX SOURCE FAIL " _cm-fails @ . ." / " _cm-checks @ .
    THEN CR ;

_cm-run
"""


def test_source(tmp_path: Path, monkeypatch) -> None:
    profile = "codex-source-contract"
    harness.PROFILES[profile] = harness.Profile(
        roots=(
            "tui/applets/agent/providers/codex/source.f",
            "tui/applets/agent/runtime.f",
            "net/tls-trust-registry.f",
        ),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("CODEX SOURCE PASS",),
        stable_markers=("CODEX SOURCE PASS",),
        failure_markers=("CODEX SOURCE FAIL", "(not found)", "exception"),
    )
    run_profile_smoke(profile, tmp_path, monkeypatch)
