"""Host-only architecture ratchets for the bounded Streams SR2 runtime."""

from __future__ import annotations

import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
if str(LOCAL_TESTING) not in sys.path:
    sys.path.insert(0, str(LOCAL_TESTING))

from forth_dependencies import dependency_closure  # noqa: E402
from refactor_inventory import (  # noqa: E402
    MUTABLE_DEFINITION_KINDS,
    SOURCE_ROOT,
    _lexical_definitions,
)


FLOW_CORE = "tui/applets/streams/flow-core.f"
PAYLOAD_CARRIER = "tui/applets/streams/payload-carrier.f"
RUNTIME_PROFILE = "tui/applets/streams/runtime-profile.f"
EXECUTION_POOL = "tui/applets/streams/execution-pool.f"
HTTP_ROUTE = "tui/applets/streams/http-route.f"
HTTP_REQUEST = "web/http-request-stream.f"
HTTP_ROUTER = "web/http-router-owner.f"
HTTP_RESPONSE = "web/http-response-writer.f"
HTTP_CONNECTION = "web/http-connection-owner.f"
RUNTIME_MODULES = (
    FLOW_CORE,
    PAYLOAD_CARRIER,
    RUNTIME_PROFILE,
    EXECUTION_POOL,
)
HTTP_MODULES = (
    HTTP_REQUEST,
    HTTP_ROUTER,
    HTTP_RESPONSE,
    HTTP_CONNECTION,
    HTTP_ROUTE,
)

FORTH_WORD_DEFINITION_RES = (
    re.compile(r"(?m)^\s*:\s+(?P<name>\S+)"),
    re.compile(r"(?m)^[^\\\r\n]*\bCONSTANT\s+(?P<name>\S+)"),
    re.compile(
        r"(?m)^\s*(?:CREATE|VARIABLE|VALUE|DEFER|XBUF|GUARD)\s+"
        r"(?P<name>\S+)"
    ),
)


def _source(module: str) -> str:
    return (SOURCE_ROOT / module).read_text(encoding="utf-8")


def _defined_words(module: str) -> set[str]:
    source = _source(module)
    return {
        match.group("name")
        for pattern in FORTH_WORD_DEFINITION_RES
        for match in pattern.finditer(source)
    }


def test_streams_sr2_runtime_dependency_closure_is_storage_free() -> None:
    closure = set(dependency_closure(SOURCE_ROOT, RUNTIME_MODULES))
    forbidden_prefixes = (
        "persistence/",
        "utils/fs/",
        "net/",
        "web/",
        "atproto/",
        "library/",
        "tui/applets/library/",
    )
    forbidden_streams_prefixes = (
        "tui/applets/streams/source",
        "tui/applets/streams/observation",
    )
    forbidden_streams_modules = {
        "tui/applets/streams/repository.f",
        "tui/applets/streams/runtime-owner.f",
        "tui/applets/streams/streams.f",
    }

    assert set(RUNTIME_MODULES) <= closure
    assert not {
        module
        for module in closure
        if module.startswith(forbidden_prefixes)
        or module.startswith(forbidden_streams_prefixes)
        or module in forbidden_streams_modules
    }


def test_streams_sr2_runtime_owns_no_top_level_mutable_storage() -> None:
    mutable_definitions: dict[str, dict[str, list[str]]] = {}
    for module in RUNTIME_MODULES:
        definitions = _lexical_definitions(_source(module))
        owned = {
            kind: definitions[kind]
            for kind in MUTABLE_DEFINITION_KINDS
            if definitions[kind]
        }
        if owned:
            mutable_definitions[module] = owned

    assert mutable_definitions == {}


def test_streams_sr2_http_closure_is_storage_free_and_current() -> None:
    closure = set(dependency_closure(SOURCE_ROOT, (HTTP_ROUTE,)))
    forbidden_prefixes = (
        "persistence/",
        "utils/fs/",
        "atproto/",
        "library/",
        "tui/applets/library/",
        "tui/applets/streams/source",
        "tui/applets/streams/observation",
    )
    forbidden_modules = {
        "tui/applets/streams/repository.f",
        "tui/applets/streams/runtime-owner.f",
        "tui/applets/streams/streams.f",
    }

    assert set(HTTP_MODULES) <= closure
    assert not {
        module
        for module in closure
        if module.startswith(forbidden_prefixes)
        or module in forbidden_modules
    }


def test_streams_sr2_http_owns_no_top_level_mutable_storage() -> None:
    mutable_definitions: dict[str, dict[str, list[str]]] = {}
    for module in HTTP_MODULES:
        definitions = _lexical_definitions(_source(module))
        owned = {
            kind: definitions[kind]
            for kind in MUTABLE_DEFINITION_KINDS
            if definitions[kind]
        }
        if owned:
            mutable_definitions[module] = owned

    assert mutable_definitions == {}


def test_streams_sr2_runtime_replaces_the_sr1_inline_layout() -> None:
    runtime_words = set().union(*map(_defined_words, RUNTIME_MODULES))
    obsolete_sr1_words = {
        "STREAMS-FLOW-PAYLOAD-MAX",
        "STREAMS-FLOW-OP-MAX",
        "STREAMS-FLOW-QUEUE-CAPACITY",
        "STREAMS-EVENT-PAYLOAD-LIMIT",
        "STREAMS-CONNECTOR-OPERATION-LIMIT",
        "STREAMS-EVENT-OWNERSHIP-INLINE",
        "_SEVT-STATE-INLINE",
        "_SFL-INGRESS-PAYLOAD",
        "_SFL-EGRESS-PAYLOAD",
        "_SFL-OPERATION",
        "SFLOW.INGRESS-PAYLOAD",
        "SFLOW.EGRESS-PAYLOAD",
    }

    assert runtime_words.isdisjoint(obsolete_sr1_words)


def test_streams_sr2_runtime_introduces_no_prerelease_legacy_layer() -> None:
    closure = dependency_closure(SOURCE_ROOT, RUNTIME_MODULES)
    runtime_words = set().union(*map(_defined_words, RUNTIME_MODULES))
    prerelease_glut_terms = (
        "ABI",
        "LEGACY",
        "COMPAT",
        "VERSION",
        "MIGRAT",
        "ADAPTER",
        "READER",
        "RESERVED",
    )

    assert not {
        module
        for module in closure
        if any(term in Path(module).stem.upper() for term in prerelease_glut_terms)
    }
    assert not {
        word
        for word in runtime_words
        if any(term in word.upper() for term in prerelease_glut_terms)
    }


def test_streams_sr2_http_introduces_no_prerelease_legacy_surface() -> None:
    http_words = set().union(*map(_defined_words, HTTP_MODULES))
    prerelease_glut_terms = (
        "ABI",
        "LEGACY",
        "COMPAT",
        "MIGRAT",
        "DEPRECAT",
        "OLD-LAYOUT",
    )

    assert not {
        word
        for word in http_words
        if any(term in word.upper() for term in prerelease_glut_terms)
    }


def test_streams_sr2_runtime_exposes_external_workspace_contracts() -> None:
    required_words = {
        FLOW_CORE: {
            "STREAMS-FLOW-SIZE",
            "STREAMS-FLOW-WORKSPACE!",
            "SFLOW.PROFILE",
            "SFLOW.INGRESS-CARRIER",
            "SFLOW.EGRESS-CARRIER",
            "SFLOW.OPERATION",
            "SFLOW.OPERATION-CAPACITY",
            "SFLOW.BINDING-EPOCH",
            "SFLOW.INGRESS-CARRIER-EPOCH",
            "SFLOW.EGRESS-CARRIER-EPOCH",
            "STREAMS-FLOW-STATE-RECEIVING",
            "STREAMS-FLOW-INGRESS-BEGIN",
            "STREAMS-FLOW-INGRESS-APPEND",
            "STREAMS-FLOW-INGRESS-COMMIT",
            "STREAMS-FLOW-INGRESS-ABORT",
        },
        PAYLOAD_CARRIER: {
            "STREAMS-PAYLOAD-SIZE",
            "STREAMS-PAYLOAD-SEGMENT-SIZE",
            "STREAMS-PAYLOAD-SEGMENT-BYTES",
            "SPAY.SEGMENTS",
            "SPAY.SEGMENT-N",
            "SPAY.BYTE-CAP",
            "SPAY.BYTE-U",
            "SPAY.BINDING-EPOCH",
            "SPAY.GEOMETRY-DIGEST",
            "STREAMS-PAYLOAD-UNIFORM-GEOMETRY?",
            "STREAMS-PAYLOAD-APPEND-PAYLOAD",
            "STREAMS-PAYLOAD-READ",
        },
        RUNTIME_PROFILE: {
            "STREAMS-RUNTIME-INGRESS-SEGMENTS",
            "STREAMS-RUNTIME-EGRESS-SEGMENTS",
            "STREAMS-RUNTIME-INGRESS-CAPACITY",
            "STREAMS-RUNTIME-EGRESS-CAPACITY",
            "STREAMS-RUNTIME-OPERATION-CAPACITY",
            "STREAMS-RUNTIME-PAYLOAD-CAPACITY",
            "STREAMS-RUNTIME-SEGMENT-TABLE-BYTES",
        },
        EXECUTION_POOL: {
            "STREAMS-EXECUTION-ENTRY-SIZE",
            "STREAMS-EXECUTION-POOL-SIZE",
            "STREAMS-EXECUTION-PROFILE-RUNTIME-BYTES",
            "STREAMS-EXECUTION-FLOW-RUNTIME-BYTES",
            "STREAMS-EXECUTION-POOL-CAPACITY@",
            "STREAMS-EXECUTION-POOL-ACTIVE@",
            "STREAMS-EXECUTION-POOL-LEASE-AVAILABLE?",
            "STREAMS-EXECUTION-POOL-RUNTIME-BYTES@",
            "STREAMS-EXECUTION-POOL-ENTRY-RUNTIME-BYTES@",
        },
    }
    missing = {
        module: sorted(words - _defined_words(module))
        for module, words in required_words.items()
        if words - _defined_words(module)
    }

    assert missing == {}


def test_streams_sr2_http_exposes_caller_owned_lifecycle_contracts() -> None:
    required_words = {
        HTTP_REQUEST: {
            "WEB-HTTP-REQUEST-STREAM-SIZE",
            "WREQ-INIT",
            "WREQ-FEED",
            "WREQ-BODY-CONTINUE",
            "WREQ-LIMITS!",
        },
        HTTP_ROUTER: {
            "HROUTER-SIZE",
            "HROUTER-INIT",
            "HROUTER-ADD",
            "HROUTER-SEAL",
            "HROUTER-SPAN-DISJOINT?",
        },
        HTTP_RESPONSE: {
            "HTTP-RESPONSE-WRITER-SIZE",
            "HRESP-INIT",
            "HRESP-BODY-SOURCE",
            "HRESP-SEAL",
            "HRESP-SEND-STEP",
        },
        HTTP_CONNECTION: {
            "HTTP-CONNECTION-OWNER-SIZE",
            "HCONN-INIT",
            "HCONN-START",
            "HCONN-STEP",
            "HCONN-CANCEL",
            "HCONN-SPAN-DISJOINT?",
        },
        HTTP_ROUTE: {
            "STREAMS-HTTP-ROUTE-CONFIG-SIZE",
            "STREAMS-HTTP-ROUTE-OPERATION-SIZE",
            "STREAMS-HTTP-ROUTE-CONFIG-INIT",
            "STREAMS-HTTP-ROUTE-START",
            "STREAMS-HTTP-ROUTE-POLL",
            "STREAMS-HTTP-ROUTE-CANCEL",
            "STREAMS-HTTP-ROUTE-CLEANUP",
            "STREAMS-HTTP-ROUTE-GENERATION@",
            "STREAMS-HTTP-ROUTE-PAYLOAD-GENERATION@",
            "STREAMS-HTTP-DEMO-ROUTE-ADD",
        },
    }
    missing = {
        module: sorted(words - _defined_words(module))
        for module, words in required_words.items()
        if words - _defined_words(module)
    }

    assert missing == {}


def test_streams_sr2_qualification_surface_replaces_sr1_fixture_names() -> None:
    removed = (
        LOCAL_TESTING / "streams-sr1-core.f",
        LOCAL_TESTING / "test_streams_sr1_core.py",
        LOCAL_TESTING / "test_streams_sr1_static.py",
    )
    current = (
        LOCAL_TESTING / "streams-sr2-runtime.f",
        LOCAL_TESTING / "test_streams_sr2_runtime.py",
        LOCAL_TESTING / "test_streams_sr2_static.py",
    )

    assert not any(path.exists() for path in removed)
    assert all(path.is_file() for path in current)
