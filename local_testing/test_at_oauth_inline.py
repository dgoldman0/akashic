#!/usr/bin/env python3
"""Static and staged qualification for checked inline AT OAuth keys."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


SOURCE = ROOT / "akashic" / "atproto" / "oauth-deployment-inline.f"
DEPLOYMENT = ROOT / "akashic" / "atproto" / "oauth-deployment.f"
JWK = ROOT / "akashic" / "security" / "jose" / "jwk-p256.f"
JWK_SET = ROOT / "akashic" / "security" / "jose" / "jwk-set-p256.f"
KEY_OWNER = ROOT / "akashic" / "security" / "oauth2" / "key-p256.f"
VAULT = ROOT / "akashic" / "security" / "credential-vault.f"
PROFILE_FIXTURE = LOCAL_TESTING / "at-oauth-prof-test.f"
DEPLOYMENT_FIXTURE = LOCAL_TESTING / "at-oauth-deploy-test.f"
FIXTURE = LOCAL_TESTING / "at-oauth-inline-test.f"

PROFILE = "at-oauth-inline"
IMAGE = Path("/tmp/akashic-at-oauth-inline.img")
PASS_MARKER = "AT OAUTH INLINE PASS"
MAX_PHASE_STEPS = 180_000_000
FINISH_STEPS = 20_000_000


# The deployment binder and checked JWK path are the exact production bodies.
# The durable owner has a separate exact vault qualification.  This seam
# models only its public composition contract, with two independently
# controllable identities, because cv-deps.f intentionally retains only one
# persistent path and cannot represent simultaneous client and DPoP records.
SEAM_DOUBLES = r"""
PROVIDED akashic-cred-vault
PROVIDED akashic-oauth2-key-p256
PROVIDED atoi-seam

0  CONSTANT CVAULT-S-OK
1  CONSTANT CVAULT-S-INVALID
2  CONSTANT CVAULT-S-CAPACITY
3  CONSTANT CVAULT-S-ABSENT
4  CONSTANT CVAULT-S-REVOKED
5  CONSTANT CVAULT-S-CONFLICT
6  CONSTANT CVAULT-S-LOCKED
7  CONSTANT CVAULT-S-CALLBACK
8  CONSTANT CVAULT-S-ENTROPY
9  CONSTANT CVAULT-S-CRYPTO
10 CONSTANT CVAULT-S-AUTH
11 CONSTANT CVAULT-S-CORRUPT
12 CONSTANT CVAULT-S-UNSUPPORTED
13 CONSTANT CVAULT-S-IO
14 CONSTANT CVAULT-S-RECOVERY
15 CONSTANT CVAULT-S-BUSY
16 CONSTANT CVAULT-S-ROLLBACK
17 CONSTANT CVAULT-S-RANGE
18 CONSTANT CVAULT-S-PROTECTED
19 CONSTANT CVAULT-S-PLATFORM
20 CONSTANT CVAULT-S-INTERNAL

3480 CONSTANT CVAULT-SIZE
1 CONSTANT CVAULT-STATE-PRESENT

: CVAULT-STATUS-VALID?  ( status -- flag )
    DUP CVAULT-S-OK >= SWAP CVAULT-S-INTERNAL <= AND ;

VARIABLE _ATOID-VAULT-A
VARIABLE _ATOID-VAULT-U
VARIABLE _ATOID-VAULT-BUSY
VARIABLE _ATOID-EXTERNAL-STATUS
VARIABLE _ATOID-EXTERNAL-CALLS
VARIABLE _ATOID-WHOLE-SEEN

: CVAULT-EXTERNAL-SPAN-STATUS
  ( address length vault -- status )
    1 _ATOID-EXTERNAL-CALLS +!
    DUP _ATOID-VAULT-A @ <> IF
        2DROP DROP CVAULT-S-INVALID EXIT
    THEN
    DROP
    DUP 111928 = IF -1 _ATOID-WHOLE-SEEN ! THEN
    _ATOID-VAULT-BUSY @ IF
        2DROP CVAULT-S-BUSY EXIT
    THEN
    _ATOID-EXTERNAL-STATUS @ ?DUP IF
        >R 2DROP R> EXIT
    THEN
    2DUP CALLER-SPAN-STATUS
    DUP CALLER-SPAN-S-OK = IF
        DROP
    ELSE
        DUP CALLER-SPAN-S-RANGE = IF
            DROP 2DROP CVAULT-S-RANGE EXIT
        THEN
        DUP CALLER-SPAN-S-PROTECTED = IF
            DROP 2DROP CVAULT-S-PROTECTED EXIT
        THEN
        DROP 2DROP CVAULT-S-PLATFORM EXIT
    THEN
    2DUP _ATOID-VAULT-A @ _ATOID-VAULT-U @
    MSPAN-OVERLAP? IF
        2DROP CVAULT-S-INVALID EXIT
    THEN
    2DROP CVAULT-S-OK ;

: CVAULT-METADATA
  ( rid vault -- generation state kind secret-u status )
    2DROP
    _ATOID-VAULT-BUSY @ IF
        0 0 0 0 CVAULT-S-BUSY EXIT
    THEN
    1 CVAULT-STATE-PRESENT 0 336 CVAULT-S-OK ;

0  CONSTANT OAUTH2-P256-KEY-S-OK
1  CONSTANT OAUTH2-P256-KEY-S-INVALID
2  CONSTANT OAUTH2-P256-KEY-S-CAPACITY
3  CONSTANT OAUTH2-P256-KEY-S-ALIAS
4  CONSTANT OAUTH2-P256-KEY-S-STATE
5  CONSTANT OAUTH2-P256-KEY-S-ABSENT
6  CONSTANT OAUTH2-P256-KEY-S-REVOKED
7  CONSTANT OAUTH2-P256-KEY-S-CONFLICT
8  CONSTANT OAUTH2-P256-KEY-S-BUSY
9  CONSTANT OAUTH2-P256-KEY-S-CALLBACK
10 CONSTANT OAUTH2-P256-KEY-S-LOCKED
11 CONSTANT OAUTH2-P256-KEY-S-ENTROPY
12 CONSTANT OAUTH2-P256-KEY-S-CRYPTO
13 CONSTANT OAUTH2-P256-KEY-S-AUTH
14 CONSTANT OAUTH2-P256-KEY-S-CORRUPT
15 CONSTANT OAUTH2-P256-KEY-S-UNSUPPORTED
16 CONSTANT OAUTH2-P256-KEY-S-IO
17 CONSTANT OAUTH2-P256-KEY-S-RECOVERY
18 CONSTANT OAUTH2-P256-KEY-S-ROLLBACK
19 CONSTANT OAUTH2-P256-KEY-S-FORMAT
20 CONSTANT OAUTH2-P256-KEY-S-KEY
21 CONSTANT OAUTH2-P256-KEY-S-MISMATCH
22 CONSTANT OAUTH2-P256-KEY-S-RANGE
23 CONSTANT OAUTH2-P256-KEY-S-PROTECTED
24 CONSTANT OAUTH2-P256-KEY-S-PLATFORM
25 CONSTANT OAUTH2-P256-KEY-S-INTERNAL

1 CONSTANT OAUTH2-P256-KEY-ROLE-CLIENT
2 CONSTANT OAUTH2-P256-KEY-ROLE-DPOP
1 CONSTANT OAUTH2-P256-KEY-BINDING-F-CLIENT
2 CONSTANT OAUTH2-P256-KEY-BINDING-F-DPOP
80 CONSTANT OAUTH2-P256-KEY-SLOT-SIZE
192 CONSTANT OAUTH2-P256-KEY-BINDING-SIZE
336 CONSTANT OAUTH2-P256-KEY-RECORD-SIZE
256 CONSTANT OAUTH2-P256-KEY-KID-CAPACITY
65 CONSTANT OAUTH2-P256-KEY-PUBLIC-SIZE
32 CONSTANT OAUTH2-P256-KEY-THUMBPRINT-SIZE
17879 CONSTANT OAUTH2-P256-KEY-WORKSPACE-SIZE

: OAUTH2-P256-KEY-STATUS-VALID?  ( status -- flag )
    DUP OAUTH2-P256-KEY-S-OK >=
    SWAP OAUTH2-P256-KEY-S-INTERNAL <= AND ;

VARIABLE _ATOID-BINDING-FLAGS
VARIABLE _ATOID-BINDING-STATUS
VARIABLE _ATOID-CLIENT-STATUS
VARIABLE _ATOID-DPOP-STATUS
VARIABLE _ATOID-CLIENT-KID-A
VARIABLE _ATOID-CLIENT-KID-U
VARIABLE _ATOID-CLIENT-PUBLIC
VARIABLE _ATOID-CLIENT-THUMB
VARIABLE _ATOID-DPOP-PUBLIC
VARIABLE _ATOID-DPOP-THUMB
VARIABLE _ATOID-CLIENT-CALLS
VARIABLE _ATOID-DPOP-CALLS
VARIABLE _ATOID-OWNER-DEPTH
VARIABLE _ATOID-OWNER-MAX-DEPTH
VARIABLE _ATOID-SEQUENCE
VARIABLE _ATOID-VIOLATIONS

: OAUTH2-P256-KEY-BINDING-PRESENCE@
  ( binding binding-u -- flags status )
    DUP OAUTH2-P256-KEY-BINDING-SIZE <> IF
        2DROP 0 OAUTH2-P256-KEY-S-INVALID EXIT
    THEN
    OVER 0= IF
        2DROP 0 OAUTH2-P256-KEY-S-INVALID EXIT
    THEN
    2DROP
    _ATOID-BINDING-STATUS @ ?DUP IF
        0 SWAP EXIT
    THEN
    _ATOID-BINDING-FLAGS @ OAUTH2-P256-KEY-S-OK ;

0x41544F49444F4342 CONSTANT _ATOID-OWNER-GUARD
-19121 CONSTANT _ATOID-E-OWNER-STACK

VARIABLE _ATOID-OCB
VARIABLE _ATOID-OCTX
VARIABLE _ATOID-OKID-A
VARIABLE _ATOID-OKID-U
VARIABLE _ATOID-OPUBLIC
VARIABLE _ATOID-OTHUMB
VARIABLE _ATOID-OWORK
VARIABLE _ATOID-ORESULT
VARIABLE _ATOID-OSTATUS

: _ATOID-OWNER-CALLBACK-RUN  ( -- callback-result )
    DEPTH >R
    _ATOID-OWNER-GUARD
    _ATOID-OKID-A @ _ATOID-OKID-U @
    _ATOID-OPUBLIC @ _ATOID-OTHUMB @
    _ATOID-OCTX @
    _ATOID-OCB @ EXECUTE
    DEPTH R@ 2 + <> IF
        _ATOID-E-OWNER-STACK THROW
    THEN
    OVER _ATOID-OWNER-GUARD <> IF
        _ATOID-E-OWNER-STACK THROW
    THEN
    NIP
    R> DROP ;

: _ATOID-OWNER-CALLBACK-SAFE
  ( -- callback-result status )
    ['] _ATOID-OWNER-CALLBACK-RUN CATCH
    DUP IF
        DROP 0 OAUTH2-P256-KEY-S-CALLBACK EXIT
    THEN
    DROP OAUTH2-P256-KEY-S-OK ;

: _ATOID-OWNER-ENTER  ( -- )
    1 _ATOID-OWNER-DEPTH +!
    _ATOID-OWNER-DEPTH @ _ATOID-OWNER-MAX-DEPTH @ > IF
        _ATOID-OWNER-DEPTH @ _ATOID-OWNER-MAX-DEPTH !
    THEN
    -1 _ATOID-VAULT-BUSY !
    0 _ATOID-VAULT-BUSY ! ;

: _ATOID-OWNER-LEAVE  ( -- )
    -1 _ATOID-OWNER-DEPTH +! ;

: _ATOID-OWNER-WITH  ( binding binding-u vault callback context workspace role -- callback-result status )
    >R
    _ATOID-OWORK !
    _ATOID-OCTX !
    _ATOID-OCB !
    _ATOID-VAULT-A @ <> IF
        2DROP R> DROP 0 OAUTH2-P256-KEY-S-INVALID EXIT
    THEN
    OAUTH2-P256-KEY-BINDING-SIZE <> IF
        DROP R> DROP 0 OAUTH2-P256-KEY-S-INVALID EXIT
    THEN
    DROP
    _ATOID-OCB @ 0= IF
        R> DROP 0 OAUTH2-P256-KEY-S-INVALID EXIT
    THEN
    _ATOID-OWORK @ 0= IF
        R> DROP 0 OAUTH2-P256-KEY-S-INVALID EXIT
    THEN
    R@ OAUTH2-P256-KEY-ROLE-CLIENT = IF
        1 _ATOID-CLIENT-CALLS +!
        _ATOID-CLIENT-STATUS @ ?DUP IF
            >R _ATOID-OWORK @ OAUTH2-P256-KEY-WORKSPACE-SIZE
            0 FILL R> R> DROP 0 SWAP EXIT
        THEN
        _ATOID-SEQUENCE @ 0<> IF 1 _ATOID-VIOLATIONS +! THEN
        1 _ATOID-SEQUENCE !
        _ATOID-CLIENT-KID-A @ _ATOID-OKID-A !
        _ATOID-CLIENT-KID-U @ _ATOID-OKID-U !
        _ATOID-CLIENT-PUBLIC @ _ATOID-OPUBLIC !
        _ATOID-CLIENT-THUMB @ _ATOID-OTHUMB !
    ELSE
        1 _ATOID-DPOP-CALLS +!
        _ATOID-DPOP-STATUS @ ?DUP IF
            >R _ATOID-OWORK @ OAUTH2-P256-KEY-WORKSPACE-SIZE
            0 FILL R> R> DROP 0 SWAP EXIT
        THEN
        _ATOID-SEQUENCE @ 2 <> IF 1 _ATOID-VIOLATIONS +! THEN
        3 _ATOID-SEQUENCE !
        0 _ATOID-OKID-A !
        0 _ATOID-OKID-U !
        _ATOID-DPOP-PUBLIC @ _ATOID-OPUBLIC !
        _ATOID-DPOP-THUMB @ _ATOID-OTHUMB !
    THEN
    _ATOID-OWNER-DEPTH @ IF 1 _ATOID-VIOLATIONS +! THEN
    _ATOID-OWNER-ENTER
    _ATOID-OWNER-CALLBACK-SAFE
    _ATOID-OSTATUS !
    _ATOID-ORESULT !
    _ATOID-OWNER-LEAVE
    _ATOID-OWORK @ OAUTH2-P256-KEY-WORKSPACE-SIZE 0 FILL
    R> DROP
    _ATOID-ORESULT @ _ATOID-OSTATUS @ ;

: OAUTH2-P256-KEY-WITH-CLIENT
  ( binding binding-u vault callback context workspace -- callback-result status )
    OAUTH2-P256-KEY-ROLE-CLIENT _ATOID-OWNER-WITH ;

: OAUTH2-P256-KEY-WITH-DPOP
  ( binding binding-u vault callback context workspace -- callback-result status )
    OAUTH2-P256-KEY-ROLE-DPOP _ATOID-OWNER-WITH ;

' AT-OAUTH-DEPLOYMENT-WITH CONSTANT _ATOID-REAL-DEPLOY
' JOSE-JWK-SET-P256-SELECT CONSTANT _ATOID-REAL-SELECT

VARIABLE _ATOID-DEPLOY-ACTIVE
VARIABLE _ATOID-DEPLOY-CALLS
VARIABLE _ATOID-SELECT-ACTIVE
VARIABLE _ATOID-SELECT-CALLS
VARIABLE _ATOID-SELECT-MUTATION
VARIABLE _ATOID-SELECT-CLEAN
VARIABLE _ATOID-SELECT-PUBLIC
VARIABLE _ATOID-SELECT-THUMB
VARIABLE _ATOID-SELECT-WORK
VARIABLE _ATOID-EXPECT-JWKS-A
VARIABLE _ATOID-EXPECT-JWKS-U

: _ATOID-ZERO?  ( address length -- flag )
    BEGIN
        DUP
    WHILE
        OVER C@ IF 2DROP 0 EXIT THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP -1 ;

: AT-OAUTH-DEPLOYMENT-WITH  ( document document-u config profile callback context workspace -- callback-result status )
    1 _ATOID-DEPLOY-CALLS +!
    -1 _ATOID-DEPLOY-ACTIVE !
    _ATOID-REAL-DEPLOY EXECUTE
    0 _ATOID-DEPLOY-ACTIVE ! ;

: JOSE-JWK-SET-P256-SELECT
  ( source source-u kid kid-u public thumbprint workspace -- status )
    DUP _ATOID-SELECT-WORK !
    1 PICK _ATOID-SELECT-THUMB !
    2 PICK _ATOID-SELECT-PUBLIC !
    _ATOID-DEPLOY-ACTIVE @ 0= IF 1 _ATOID-VIOLATIONS +! THEN
    _ATOID-OWNER-DEPTH @ 1 <> IF 1 _ATOID-VIOLATIONS +! THEN
    _ATOID-SEQUENCE @ 1 <> IF 1 _ATOID-VIOLATIONS +! THEN
    2 _ATOID-SEQUENCE !
    6 PICK _ATOID-EXPECT-JWKS-A @ <> IF
        1 _ATOID-VIOLATIONS +!
    THEN
    5 PICK _ATOID-EXPECT-JWKS-U @ <> IF
        1 _ATOID-VIOLATIONS +!
    THEN
    1 _ATOID-SELECT-CALLS +!
    -1 _ATOID-SELECT-ACTIVE !
    _ATOID-REAL-SELECT EXECUTE
    0 _ATOID-SELECT-ACTIVE !
    _ATOID-SELECT-WORK @ JOSE-JWK-SET-P256-WORKSPACE-SIZE
    _ATOID-ZERO? _ATOID-SELECT-CLEAN !
    DUP JOSE-JWK-SET-P256-S-OK = IF
        _ATOID-SELECT-MUTATION @ 1 = IF
            _ATOID-SELECT-PUBLIC @ DUP C@ 1 XOR SWAP C!
        THEN
        _ATOID-SELECT-MUTATION @ 2 = IF
            _ATOID-SELECT-THUMB @ DUP C@ 1 XOR SWAP C!
        THEN
    THEN ;

: _ATOID-RESET  ( -- )
    0 _ATOID-VAULT-BUSY !
    0 _ATOID-EXTERNAL-STATUS !
    0 _ATOID-EXTERNAL-CALLS !
    0 _ATOID-WHOLE-SEEN !
    OAUTH2-P256-KEY-BINDING-F-CLIENT
    OAUTH2-P256-KEY-BINDING-F-DPOP OR
        _ATOID-BINDING-FLAGS !
    0 _ATOID-BINDING-STATUS !
    0 _ATOID-CLIENT-STATUS !
    0 _ATOID-DPOP-STATUS !
    0 _ATOID-CLIENT-CALLS !
    0 _ATOID-DPOP-CALLS !
    0 _ATOID-OWNER-DEPTH !
    0 _ATOID-OWNER-MAX-DEPTH !
    0 _ATOID-SEQUENCE !
    0 _ATOID-VIOLATIONS !
    0 _ATOID-DEPLOY-ACTIVE !
    0 _ATOID-DEPLOY-CALLS !
    0 _ATOID-SELECT-ACTIVE !
    0 _ATOID-SELECT-CALLS !
    0 _ATOID-SELECT-MUTATION !
    0 _ATOID-SELECT-CLEAN !
    0 _ATOID-EXPECT-JWKS-A !
    0 _ATOID-EXPECT-JWKS-U ! ;
"""


LOAD_STAGES = (
    ("memory-span", "utils/memory-span.f", "ATOI MEMORY READY"),
    ("caller-span", "utils/caller-span.f", "ATOI CALLER READY"),
    (
        "client-config",
        "security/oauth2/client-config.f",
        "ATOI CONFIG READY",
    ),
    ("string", "utils/string.f", "ATOI STRING READY"),
    ("json-object", "security/jose/json-object.f", "ATOI JSON READY"),
    (
        "client-metadata",
        "security/oauth2/client-metadata.f",
        "ATOI CLIENT META READY",
    ),
    ("http-target", "net/http-target.f", "ATOI HTTP TARGET READY"),
    ("did", "atproto/did.f", "ATOI DID READY"),
    ("handle", "atproto/handle.f", "ATOI HANDLE READY"),
    (
        "did-document",
        "atproto/did-document.f",
        "ATOI DID DOC READY",
    ),
    ("dns-txt", "net/dns-txt.f", "ATOI DNS READY"),
    ("identity", "atproto/identity.f", "ATOI IDENTITY READY"),
    (
        "resource-metadata",
        "security/oauth2/resource-metadata.f",
        "ATOI RMETA READY",
    ),
    ("oauth-metadata", "security/oauth2/metadata.f", "ATOI META READY"),
    ("oauth-profile", "atproto/oauth-profile.f", "ATOI PROFILE READY"),
    ("oauth-client", "atproto/oauth-client.f", "ATOI CLIENT READY"),
    (
        "deployment",
        "atproto/oauth-deployment.f",
        "ATOI DEPLOYMENT READY",
    ),
    ("base64url", "security/jose/base64url.f", "ATOI B64 READY"),
    ("sha256", "math/sha256.f", "ATOI SHA READY"),
    ("p256", "math/p256.f", "ATOI P256 READY"),
    ("jwk-p256", "security/jose/jwk-p256.f", "ATOI JWK READY"),
    (
        "jwk-set",
        "security/jose/jwk-set-p256.f",
        "ATOI JWK SET READY",
    ),
    ("seam", "local_testing/atoi-seam.f", "ATOI SEAM READY"),
    ("source", "local_testing/atoi-source.f", "ATOI SOURCE READY"),
    (
        "profile-fixture",
        "local_testing/at-oauth-prof-test.f",
        "ATOI PROFILE FIXTURE READY",
    ),
    (
        "deployment-fixture",
        "local_testing/at-oauth-deploy-test.f",
        "ATOI DEPLOY FIXTURE READY",
    ),
    (
        "fixture",
        "local_testing/at-oauth-inline-test.f",
        "ATOI FIXTURE READY",
    ),
)

GROUP_STAGES = (
    ("contracts", "_ATOIT-TEST-CONTRACTS", "ATOI CONTRACTS READY"),
    ("success", "_ATOIT-TEST-SUCCESS", "ATOI SUCCESS READY"),
    ("key-source", "_ATOIT-TEST-KEY-SOURCE", "ATOI KEY SOURCE READY"),
    ("binding", "_ATOIT-TEST-BINDING", "ATOI BINDING READY"),
    ("mismatch", "_ATOIT-TEST-MISMATCH", "ATOI MISMATCH READY"),
    ("owner", "_ATOIT-TEST-OWNER", "ATOI OWNER READY"),
    ("distinct", "_ATOIT-TEST-DISTINCT", "ATOI DISTINCT READY"),
    ("callbacks", "_ATOIT-TEST-CALLBACKS", "ATOI CALLBACKS READY"),
    ("preflight", "_ATOIT-TEST-PREFLIGHT", "ATOI PREFLIGHT READY"),
)

FAILURE_MARKERS = (
    "AT OAUTH INLINE FAIL",
    "AT OAUTH INLINE ASSERT",
    "AT OAUTH INLINE STATUS",
    "AT OAUTH INLINE STACK",
    "AT OAUTH INLINE LOAD STACK",
    "AT OAUTH PROFILE FAIL",
    "AT OAUTH PROFILE ASSERT",
    "AT OAUTH DEPLOYMENT FAIL",
    "AT OAUTH DEPLOYMENT ASSERT",
    "DRIVER THROW",
    "Branch offset overflow",
    "dictionary full",
    "exception",
    "Module not found",
    "Path component not found",
    "? (not found)",
)


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing Forth word {name}"
    return match.group("body")


def _requires(path: Path) -> list[str]:
    return re.findall(
        r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)",
        path.read_text(encoding="utf-8"),
    )


def _forth_code(source: str) -> str:
    return "\n".join(line.split("\\", 1)[0] for line in source.splitlines())


def _assert_physical_comments(path: Path, source: str) -> None:
    for line_number, line in enumerate(source.splitlines(), start=1):
        code = line.split("\\", 1)[0]
        if "(" in code:
            assert ")" in code.split("(", 1)[1], (
                "KDOS parenthesized comments must close on their physical "
                f"line: {path}:{line_number}"
            )


def _assert_vectors() -> None:
    x = "YP7UuiVanTHJYet0xjVtaMBJuJI7Yfps5mliLmDyn7Y"
    y = "eQP-EAi4vJmkGunpVii8ZPLxsgwtfp9Rd6PClNRGIpk"
    canonical = json.dumps(
        {"crv": "P-256", "kty": "EC", "x": x, "y": y},
        separators=(",", ":"),
        sort_keys=True,
    ).encode("ascii")
    expected = bytes.fromhex(
        "0cebf1bc9880748a95588905b79843b42ba75cb174055e3e246bf87fe00b4a6d"
    )
    assert hashlib.sha256(canonical).digest() == expected
    public = b"\x04" + base64.urlsafe_b64decode(x + "=")
    public += base64.urlsafe_b64decode(y + "=")
    assert len(public) == 65


def _assert_static_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    fixture = FIXTURE.read_text(encoding="utf-8")
    fixture_code = _forth_code(fixture)
    seam_code = _forth_code(SEAM_DOUBLES)

    assert 0 < FINISH_STEPS <= MAX_PHASE_STEPS
    assert len({name for name, _, _ in LOAD_STAGES}) == len(LOAD_STAGES)
    assert len({name for name, _, _ in GROUP_STAGES}) == len(GROUP_STAGES)
    markers = tuple(
        marker for _, _, marker in (*LOAD_STAGES, *GROUP_STAGES)
    )
    assert len(set(markers)) == len(markers)
    for name in (
        "atoi-seam.f",
        "atoi-source.f",
        PROFILE_FIXTURE.name,
        DEPLOYMENT_FIXTURE.name,
        FIXTURE.name,
    ):
        assert len(name.encode("ascii")) <= 23

    assert "PROVIDED akashic-at-oauth-inline" in source
    assert "PROVIDED at-oauth-inline-test" in fixture
    assert "111928 CONSTANT AT-OAUTH-INLINE-WORKSPACE-SIZE" in source
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        source,
    ), "inline composition must retain no module-owned mutable state"
    for required in (
        "oauth-deployment.f",
        "jwk-set-p256.f",
        "key-p256.f",
        "credential-vault.f",
    ):
        assert any(required in item for item in _requires(SOURCE))

    statuses = (
        "OK", "INVALID", "CAPACITY", "ALIAS", "CONFIG", "PROFILE",
        "METADATA", "CLIENT-ID", "APPLICATION", "GRANT", "RESPONSE",
        "REDIRECT", "SCOPE", "AUTH-METHOD", "AUTH-ALGORITHM", "DPOP",
        "KEY-SOURCE", "BINDING", "JWKS", "NOT-FOUND", "ABSENT",
        "REVOKED", "CONFLICT", "BUSY", "LOCKED", "ENTROPY", "CRYPTO",
        "AUTH", "CORRUPT", "UNSUPPORTED", "IO", "RECOVERY", "ROLLBACK",
        "FORMAT", "KEY", "MISMATCH", "DISTINCT", "CALLBACK", "INTERNAL",
        "RANGE", "PROTECTED", "PLATFORM",
    )
    for value, status in enumerate(statuses):
        assert re.search(
            rf"(?m)^{value}[ \t]+CONSTANT[ \t]+"
            rf"AT-OAUTH-INLINE-S-{re.escape(status)}$",
            source,
        )

    for word in (
        "AT-OAUTH-INLINE-WORKSPACE-CLEAR",
        "AT-OAUTH-INLINE-STATUS-VALID?",
        "AT-OAUTH-INLINE-WITH",
        "AT-OAUTH-DEPLOYMENT-WITH",
        "JOSE-JWK-SET-P256-SELECT",
        "OAUTH2-P256-KEY-BINDING-PRESENCE@",
        "OAUTH2-P256-KEY-WITH-CLIENT",
        "OAUTH2-P256-KEY-WITH-DPOP",
        "CVAULT-EXTERNAL-SPAN-STATUS",
    ):
        assert word in source

    callback = _word_body(source, "_ATOI-DEPLOYMENT-CALLBACK-RUN")
    ordered = (
        "_ATOI-CLIENT-OWNER-SAFE",
        "_ATOI-DPOP-OWNER-SAFE",
        "_ATOI-APPLICATION-SAFE",
    )
    positions = [callback.index(marker) for marker in ordered]
    assert positions == sorted(positions)
    client_callback = _word_body(source, "_ATOI-CLIENT-KEY-CALLBACK")
    assert "_ATOI-SELECT-SAFE" in client_callback
    for internal in (
        "_ATOI-CLIENT-KEY-CALLBACK",
        "_ATOI-DPOP-KEY-CALLBACK",
        "_ATOI-DEPLOYMENT-CALL",
        "_ATOI-SELECT-CALL",
    ):
        assert internal in source

    assert "CVAULT-EXTERNAL-SPAN-STATUS" in source
    assert source.count("_ATOI-EXTERNAL-STATUS") >= 5
    assert "JOSE-JWK-P256-CALLER-SPAN-STATUS" in source
    assert source.count("_ATOI-SPAN-STATUS") >= 7
    assert "MSPAN-OVERLAP?" in source
    assert source.index("CVAULT-EXTERNAL-SPAN-STATUS") < source.index(
        "AT-OAUTH-DEPLOYMENT-WITH"
    )
    for number in (
        "192", "448", "520", "552", "624", "656", "728", "760",
        "53760", "54520", "17879", "72400", "39528", "111928",
    ):
        assert number in source

    for marker in (
        "_ATOIT-TEST-CONTRACTS",
        "_ATOIT-TEST-SUCCESS",
        "_ATOIT-TEST-KEY-SOURCE",
        "_ATOIT-TEST-BINDING",
        "_ATOIT-TEST-MISMATCH",
        "_ATOIT-TEST-OWNER",
        "_ATOIT-TEST-DISTINCT",
        "_ATOIT-TEST-CALLBACKS",
        "_ATOIT-TEST-PREFLIGHT",
        "_ATOIT-FINISH",
        PASS_MARKER,
        "_ATOID-WHOLE-SEEN",
        "_ATOID-SELECT-MUTATION",
        "_ATOIT-INPUTS-UNCHANGED?",
        "_ATOIT-WORK-WIPED?",
    ):
        assert marker in fixture

    for code, label in (
        (_forth_code(source), "production source"),
        (fixture_code, "fixture"),
        (seam_code, "seam doubles"),
    ):
        assert not re.search(
            r"(?i)(?<![A-Za-z0-9_-])(?:\?DO|DO|\+LOOP|LOOP)"
            r"(?![A-Za-z0-9_-])",
            code,
        ), f"{label} must not borrow the DO-loop return stack"
    _assert_physical_comments(SOURCE, source)
    _assert_physical_comments(FIXTURE, fixture)
    _assert_physical_comments(Path("SEAM_DOUBLES"), SEAM_DOUBLES)
    _assert_vectors()


def _packed(path: Path, *, remove_requires: bool = False) -> bytes:
    return harness._minify_forth(
        path.read_text(encoding="utf-8"),
        remove_requires=remove_requires,
    ).encode("utf-8")


def _run_lifecycle(timeout: float) -> int:
    autoexec = [
        "\\ autoexec.f - checked inline AT OAuth key composition\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." AT OAUTH INLINE LOAD STACK '
                    f'{stage_name}" CR TX-FLUSH THEN\n'
                ),
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_ATOIT-INIT\n")
    for _, word, marker in GROUP_STAGES:
        autoexec.extend(
            (
                f"{word}\n",
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_ATOIT-FINISH\nTX-FLUSH\n")

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=(
            "atproto/oauth-deployment.f",
            "security/jose/jwk-set-p256.f",
        ),
        resources=(),
        autoexec="".join(autoexec),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=FAILURE_MARKERS,
        initial_files=(
            (
                "local_testing/atoi-seam.f",
                harness._minify_forth(SEAM_DOUBLES).encode("utf-8"),
            ),
            (
                "local_testing/atoi-source.f",
                _packed(SOURCE, remove_requires=True),
            ),
            (
                f"local_testing/{PROFILE_FIXTURE.name}",
                _packed(PROFILE_FIXTURE),
            ),
            (
                f"local_testing/{DEPLOYMENT_FIXTURE.name}",
                _packed(DEPLOYMENT_FIXTURE),
            ),
            (f"local_testing/{FIXTURE.name}", _packed(FIXTURE)),
        ),
        linked=False,
        include_large_sample=False,
        total_sectors=8192,
    )
    image = harness.build_image(PROFILE, IMAGE)
    profile = harness.PROFILES[PROFILE]
    reports: list[tuple[str, object]] = []

    with harness.MachineSession.from_bios(
        harness.MEGAPAD_ROOT / "bios.asm",
        storage_image=image,
        cols=120,
        rows=44,
        batch_steps=500_000,
        ext_mem_size=128 << 20,
        num_cores=1,
    ) as machine:
        machine.boot()
        stages = (*LOAD_STAGES, *GROUP_STAGES)
        for index, (stage_name, _, marker) in enumerate(stages):
            if index:
                machine.clear_output()
                machine.send_text("x")
            report = machine.run(
                max_steps=MAX_PHASE_STEPS,
                wall_timeout_s=timeout,
                until_text=marker,
                text_scope="raw",
            )
            raw = machine.raw_text()
            failures = tuple(
                dict.fromkeys(
                    (
                        *harness._has_forth_error(raw),
                        *harness._matched_failure_markers(
                            profile, raw, machine.screen_text()
                        ),
                    )
                )
            )
            reports.append((stage_name, report))
            if marker not in raw or failures:
                print(f"AT OAuth inline {stage_name}: FAIL")
                print(
                    f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
                    f"stop={report.reason}"
                )
                for failure in failures:
                    print(f"  {failure}")
                print(raw[-5000:])
                return 1
            print(
                f"AT OAuth inline {stage_name}: PASS "
                f"({report.steps:,} steps, {report.elapsed_s:.2f}s)",
                flush=True,
            )

        machine.clear_output()
        machine.send_text("x")
        report = machine.run(
            max_steps=FINISH_STEPS,
            wall_timeout_s=timeout,
            until_text=PASS_MARKER,
            text_scope="raw",
        )
        raw = machine.raw_text()
        failures = tuple(
            dict.fromkeys(
                (
                    *harness._has_forth_error(raw),
                    *harness._matched_failure_markers(
                        profile, raw, machine.screen_text()
                    ),
                )
            )
        )
        reports.append(("finish", report))
        if PASS_MARKER not in raw or failures:
            print("AT OAuth inline finish: FAIL")
            for failure in failures:
                print(f"  {failure}")
            print(raw[-5000:])
            return 1

    total_steps = sum(report.steps for _, report in reports)
    total_elapsed = sum(report.elapsed_s for _, report in reports)
    print(
        "AT OAuth inline lifecycle: PASS "
        f"({total_steps:,} steps, {total_elapsed:.2f}s)"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument("--lifecycle", action="store_true")
    parser.add_argument("--timeout", type=float, default=300.0)
    args = parser.parse_args()

    _assert_static_contracts()
    print("AT OAUTH INLINE STATIC PASS", flush=True)
    if args.static_only:
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
