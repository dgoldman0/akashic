"""Host-only architecture ratchets for the current Streams SR3 outbox shape."""

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


OPERATIONAL_RECORDS = "tui/applets/streams/operational-records.f"
OPERATIONAL_INDEX = "tui/applets/streams/operational-index.f"
OPERATIONAL_CONFIG_RECORDS = (
    "tui/applets/streams/operational-config-records.f"
)
SHA3_CONTEXT = "math/sha3-context.f"
OPERATIONAL_MODULES = (
    OPERATIONAL_RECORDS,
    OPERATIONAL_INDEX,
    OPERATIONAL_CONFIG_RECORDS,
)

REPOSITORY_ROOT = SOURCE_ROOT.parent
SR3_DOC = (
    REPOSITORY_ROOT
    / "docs"
    / "tui"
    / "applets"
    / "streams"
    / "sr3-operational-durability.md"
)
INTEGRATION_DOC = SR3_DOC.with_name("information-integration.md")

FORTH_WORD_DEFINITION_RES = (
    re.compile(r"(?m)^\s*:\s+(?P<name>\S+)"),
    re.compile(r"(?m)^[^\\\r\n]*\bCONSTANT\s+(?P<name>\S+)"),
    re.compile(
        r"(?m)^\s*(?:CREATE|VARIABLE|VALUE|DEFER|XBUF|GUARD)\s+"
        r"(?P<name>\S+)"
    ),
)
INTEGER_CONSTANT_RE = re.compile(
    r"(?m)^\s*(?P<value>-?(?:0x[0-9A-Fa-f]+|\d+))\s+"
    r"CONSTANT\s+(?P<name>\S+)"
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


def _integer_constants(module: str) -> dict[str, int]:
    return {
        match.group("name"): int(match.group("value"), 0)
        for match in INTEGER_CONSTANT_RE.finditer(_source(module))
    }


def test_streams_sr3_operational_closure_is_neutral_persistence_only() -> None:
    closure = set(dependency_closure(SOURCE_ROOT, OPERATIONAL_MODULES))
    allowed_infrastructure_prefixes = (
        "concurrency/",
        "math/",
        "persistence/",
        "text/",
        "utils/",
    )
    allowed_exact_modules = {
        *OPERATIONAL_MODULES,
        "runtime/identity.f",
    }
    required_neutral_substrate = {
        "persistence/btree.f",
        "persistence/blob.f",
        "persistence/core.f",
        "persistence/reclaim.f",
    }

    assert set(OPERATIONAL_MODULES) <= closure
    assert required_neutral_substrate <= closure
    assert not {
        module
        for module in closure
        if module not in allowed_exact_modules
        and not module.startswith(allowed_infrastructure_prefixes)
    }


def test_streams_sr3_operational_modules_do_not_reenter_displaced_streams() -> None:
    closure = set(dependency_closure(SOURCE_ROOT, OPERATIONAL_MODULES))
    streams_closure = {
        module
        for module in closure
        if module.startswith("tui/applets/streams/")
    }
    explicitly_displaced = {
        "tui/applets/streams/authority-root.f",
        "tui/applets/streams/index-keys.f",
        "tui/applets/streams/migration.f",
        "tui/applets/streams/persistence-adapter.f",
        "tui/applets/streams/persistence-records.f",
        "tui/applets/streams/repository.f",
        "tui/applets/streams/runtime-owner.f",
        "tui/applets/streams/streams.f",
    }
    displaced_prefixes = (
        "tui/applets/streams/source",
        "tui/applets/streams/observation",
    )

    assert streams_closure == set(OPERATIONAL_MODULES)
    assert closure.isdisjoint(explicitly_displaced)
    assert not {
        module
        for module in closure
        if module.startswith(displaced_prefixes)
    }


def test_streams_sr3_operational_modules_own_no_mutable_storage() -> None:
    mutable_definitions: dict[str, dict[str, list[str]]] = {}
    for module in OPERATIONAL_MODULES:
        definitions = _lexical_definitions(_source(module))
        owned = {
            kind: definitions[kind]
            for kind in MUTABLE_DEFINITION_KINDS
            if definitions[kind]
        }
        if owned:
            mutable_definitions[module] = owned

    assert mutable_definitions == {}


def test_streams_sr3_geometry_guards_abort_during_interpretation() -> None:
    deferred_abort = re.compile(
        r"\[IF\]\s*(?:\\[^\r\n]*\r?\n\s*)*ABORT\"",
        re.IGNORECASE,
    )

    assert not {
        module
        for module in OPERATIONAL_MODULES
        if deferred_abort.search(_source(module))
    }


def test_streams_sr3_incremental_hash_is_caller_owned_and_software_only() -> None:
    closure = set(dependency_closure(SOURCE_ROOT, (SHA3_CONTEXT,)))
    words = _defined_words(SHA3_CONTEXT)
    definitions = _lexical_definitions(_source(SHA3_CONTEXT))
    owned_mutable = {
        kind: definitions[kind]
        for kind in MUTABLE_DEFINITION_KINDS
        if definitions[kind]
    }
    public_api = {
        "SHA3-256-CONTEXT-VALID?",
        "SHA3-256-CONTEXT-INIT",
        "SHA3-256-CONTEXT-UPDATE",
        "SHA3-256-CONTEXT-FINAL",
        "SHA3-256-CONTEXT-FINAL-COMPARE",
    }

    assert closure == {
        SHA3_CONTEXT,
        "utils/memory-span.f",
    }
    assert public_api <= words
    assert owned_mutable == {}


def test_streams_sr3_operational_shape_has_no_prerelease_legacy_surface() -> None:
    operational_words = set().union(*map(_defined_words, OPERATIONAL_MODULES))
    glut_terms = (
        "ABI",
        "COMPAT",
        "DEPRECAT",
        "LEGACY",
        "MIGRAT",
        "OLD-LAYOUT",
        "READER",
        "VERSION",
    )
    public_shape_constants = {
        name: value
        for module in OPERATIONAL_MODULES
        for name, value in _integer_constants(module).items()
        if name.startswith("STREAMS-") and "SHAPE" in name
    }

    assert not {
        word
        for word in operational_words
        if any(term in word.upper() for term in glut_terms)
        or re.search(r"(?:^|-)V\d+(?:-|$)", word.upper())
    }
    assert public_shape_constants == {
        "STREAMS-OPREC-SHAPE-CURRENT": 1,
    }
    assert {
        "STREAMS-OPATT-HEADER-CLASSIFY",
        "STREAMS-OPROOT-HEADER-CLASSIFY",
    } <= operational_words


def test_streams_sr3_operational_bytes_do_not_embed_sr2_runtime_records() -> None:
    source = "\n".join(map(_source, OPERATIONAL_MODULES))
    forbidden_descriptors = {
        "STREAMS-ATTEMPT-SIZE",
        "STREAMS-EVENT-SIZE",
        "STREAMS-FLOW-SIZE",
        "STREAMS-PAYLOAD-SIZE",
    }
    forbidden_field_prefixes = (
        "SATT.",
        "SEVT.",
        "SFLOW.",
        "SPAY.",
    )

    assert forbidden_descriptors.isdisjoint(source.split())
    assert not any(prefix in source for prefix in forbidden_field_prefixes)


def test_streams_sr3_configuration_embeds_no_secret_or_runtime_handle() -> None:
    words = _defined_words(OPERATIONAL_CONFIG_RECORDS)
    forbidden_handle_terms = (
        "ADDRESS",
        "CALLBACK",
        "CARRIER",
        "LEASE",
        "PASSWORD",
        "POINTER",
        "SECRET",
        "SESSION",
        "SOCKET",
        "TOKEN",
        "TRUST",
        "WORKSPACE",
    )
    credential_accessors = {
        word for word in words if word.startswith("SOPCONN.CREDENTIAL")
    }

    assert credential_accessors == {
        "SOPCONN.CREDENTIAL-ID",
        "SOPCONN.CREDENTIAL-POLICY",
    }
    assert not {
        word
        for word in words
        if any(term in word.upper() for term in forbidden_handle_terms)
    }


def test_streams_sr3_root_and_index_agree_on_exactly_seven_trees() -> None:
    record_constants = _integer_constants(OPERATIONAL_RECORDS)
    index_constants = _integer_constants(OPERATIONAL_INDEX)
    record_trees = {
        "connector": record_constants["STREAMS-OPROOT-TREE-CONNECTORS"],
        "flow": record_constants["STREAMS-OPROOT-TREE-FLOWS"],
        "checkpoint": record_constants["STREAMS-OPROOT-TREE-CHECKPOINTS"],
        "attempt": record_constants["STREAMS-OPROOT-TREE-ATTEMPTS"],
        "dispatch": record_constants["STREAMS-OPROOT-TREE-DISPATCH"],
        "terminal": record_constants["STREAMS-OPROOT-TREE-TERMINAL"],
        "idempotency": record_constants["STREAMS-OPROOT-TREE-IDEMPOTENCY"],
    }
    index_trees = {
        "connector": index_constants["STREAMS-OI-TREE-CONNECTOR-CONFIG"],
        "flow": index_constants["STREAMS-OI-TREE-FLOW-CONFIG"],
        "checkpoint": index_constants["STREAMS-OI-TREE-CHECKPOINT"],
        "attempt": index_constants["STREAMS-OI-TREE-ATTEMPT-DIRECTORY"],
        "dispatch": index_constants["STREAMS-OI-TREE-DISPATCH"],
        "terminal": index_constants[
            "STREAMS-OI-TREE-TERMINAL-RETENTION"
        ],
        "idempotency": index_constants["STREAMS-OI-TREE-IDEMPOTENCY"],
    }

    assert record_constants["STREAMS-OPROOT-TREE-COUNT"] == 7
    assert index_constants["STREAMS-OI-TREE-COUNT"] == 7
    assert record_trees == index_trees
    assert set(record_trees.values()) == set(range(7))


def test_streams_sr3_operational_contract_is_linked_and_in_progress() -> None:
    sr3_doc = SR3_DOC.read_text(encoding="utf-8")
    integration_doc = INTEGRATION_DOC.read_text(encoding="utf-8")
    normalized_sr3 = " ".join(sr3_doc.lower().split())
    normalized_integration = " ".join(integration_doc.lower().split())

    assert re.search(
        r"\*\*status:\*\*[^\n]*(?:\n[^\n]*)?in progress",
        sr3_doc,
        re.IGNORECASE,
    )
    assert (
        "[`sr3-operational-durability.md`](sr3-operational-durability.md)"
        in integration_doc
    )
    assert "sr3 implementation is in progress" in normalized_integration
    assert "one bounded durable egress outbox" in normalized_sr3
    assert "current root and semantic codecs" in normalized_sr3
    assert "one egress-outbox index" in normalized_sr3
    assert "must not leave a parallel prototype or compatibility seam behind" in (
        normalized_sr3
    )
    for module in OPERATIONAL_MODULES:
        assert "egress outbox" in _source(module).lower()
