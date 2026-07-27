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
OPERATIONAL_SPOOL = "tui/applets/streams/operational-spool.f"
OPERATIONAL_COMPACTION = "tui/applets/streams/operational-compaction.f"
OPERATIONAL_DISPATCH = "tui/applets/streams/operational-dispatch.f"
EXECUTION_POOL = "tui/applets/streams/execution-pool.f"
SHA3_CONTEXT = "math/sha3-context.f"
OPERATIONAL_MODULES = (
    OPERATIONAL_RECORDS,
    OPERATIONAL_INDEX,
    OPERATIONAL_CONFIG_RECORDS,
    OPERATIONAL_SPOOL,
)
CURRENT_SR3_MODULES = (
    *OPERATIONAL_MODULES,
    OPERATIONAL_COMPACTION,
    OPERATIONAL_DISPATCH,
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
LOOP_CONTROL_RE = re.compile(
    r"(?<!\S)(?:\?DO|DO|\+LOOP|LOOP|2>R|2R>|2R@|>R|R>|R@)(?!\S)",
    re.IGNORECASE,
)
RETURN_STACK_TOKENS = {"2>R", "2R>", "2R@", ">R", "R>", "R@"}


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


def _colon_words(module: str) -> set[str]:
    return {
        match.group("name")
        for match in FORTH_WORD_DEFINITION_RES[0].finditer(_source(module))
    }


def _colon_definition(module: str, word: str) -> str:
    match = re.search(
        rf"(?ms)^\s*:\s+{re.escape(word)}(?:\s|$)(.*?)(?<!\S);(?=\s|$)",
        _source(module),
    )
    assert match is not None, f"missing colon definition: {module}:{word}"
    return match.group(1)


def _forth_code(source: str) -> str:
    code = "\n".join(line.split("\\", 1)[0] for line in source.splitlines())
    code = re.sub(r"\([^)]*\)", " ", code, flags=re.DOTALL)
    code = re.sub(r'(?:[A-Z.]*)?"[^"]*"', " ", code)
    return code


def _return_stack_uses_inside_do(source: str) -> list[tuple[int, str]]:
    """Report return-stack operators lexically nested inside DO/?DO loops."""
    depth = 0
    violations: list[tuple[int, str]] = []
    for line_number, line in enumerate(source.splitlines(), start=1):
        code = line.split("\\", 1)[0]
        code = re.sub(r"\([^)]*\)", " ", code)
        code = re.sub(r'(?:[A-Z.]*)?"[^"]*"', " ", code)
        for match in LOOP_CONTROL_RE.finditer(code):
            token = match.group(0).upper()
            if token in {"DO", "?DO"}:
                depth += 1
            elif token in {"LOOP", "+LOOP"}:
                depth = max(0, depth - 1)
            elif depth and token in RETURN_STACK_TOKENS:
                violations.append((line_number, token))
    return violations


def test_streams_sr3_cold_audit_loops_do_not_borrow_return_stack() -> None:
    sources = {
        "persistence/reclaim.f": _source("persistence/reclaim.f"),
        "library/persistence-adapter.f": _source(
            "tui/applets/library/persistence-adapter.f"
        ),
        "streams/operational-spool.f": _source(OPERATIONAL_SPOOL),
        "streams/operational-compaction.f": _source(
            OPERATIONAL_COMPACTION
        ),
        "streams/operational-dispatch.f": _source(OPERATIONAL_DISPATCH),
        "persist-reclaim-test.f": (
            LOCAL_TESTING / "persist-reclaim-test.f"
        ).read_text(encoding="utf-8"),
        "streams-sr3-admission.f": (
            LOCAL_TESTING / "streams-sr3-admission.f"
        ).read_text(encoding="utf-8"),
        "streams-sr3-delivery.f": (
            LOCAL_TESTING / "streams-sr3-delivery.f"
        ).read_text(encoding="utf-8"),
    }
    violations = {
        name: found
        for name, source in sources.items()
        if (found := _return_stack_uses_inside_do(source))
    }

    assert violations == {}


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


def test_streams_sr3_compaction_closure_is_neutral_and_current_only() -> None:
    closure = set(
        dependency_closure(SOURCE_ROOT, (OPERATIONAL_COMPACTION,))
    )
    current_streams_family = {
        *OPERATIONAL_MODULES,
        OPERATIONAL_COMPACTION,
    }
    neutral_infrastructure_prefixes = (
        "concurrency/",
        "math/",
        "persistence/",
        "text/",
        "utils/",
    )
    neutral_exact_modules = {
        "runtime/identity.f",
    }
    explicitly_displaced = {
        "tui/applets/streams/compaction.f",
        "tui/applets/streams/persistence-adapter.f",
        "tui/applets/streams/repository.f",
    }

    assert {
        module
        for module in closure
        if module.startswith("tui/applets/streams/")
    } == current_streams_family
    assert {
        "persistence/compaction.f",
        "persistence/btree.f",
        "persistence/blob.f",
        "persistence/core.f",
        "persistence/reclaim.f",
    } <= closure
    assert closure.isdisjoint(explicitly_displaced)
    assert not {
        module
        for module in closure
        if module not in current_streams_family
        and module not in neutral_exact_modules
        and not module.startswith(neutral_infrastructure_prefixes)
    }
    assert not {
        module
        for module in closure
        if module.startswith("tui/applets/library/")
        or module.startswith("tui/app-")
        or "http" in Path(module).name.lower()
    }


def test_streams_sr3_dispatch_closure_is_the_sr2_sr3_composition_edge() -> None:
    closure = set(dependency_closure(SOURCE_ROOT, (OPERATIONAL_DISPATCH,)))
    streams_closure = {
        module
        for module in closure
        if module.startswith("tui/applets/streams/")
    }

    assert streams_closure == {
        EXECUTION_POOL,
        "tui/applets/streams/flow-core.f",
        OPERATIONAL_CONFIG_RECORDS,
        OPERATIONAL_DISPATCH,
        OPERATIONAL_INDEX,
        OPERATIONAL_RECORDS,
        OPERATIONAL_SPOOL,
        "tui/applets/streams/payload-carrier.f",
        "tui/applets/streams/runtime-profile.f",
    }
    assert not {
        module
        for module in closure
        if module.startswith("tui/applets/library/")
        or module.startswith("tui/app-")
        or "http" in Path(module).name.lower()
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


def test_streams_sr3_dispatch_owns_no_mutable_storage() -> None:
    definitions = _lexical_definitions(_source(OPERATIONAL_DISPATCH))
    owned = {
        kind: definitions[kind]
        for kind in MUTABLE_DEFINITION_KINDS
        if definitions[kind]
    }

    assert owned == {}


def test_streams_sr3_compaction_is_entirely_caller_owned() -> None:
    definitions = _lexical_definitions(_source(OPERATIONAL_COMPACTION))
    owned = {
        kind: definitions[kind]
        for kind in MUTABLE_DEFINITION_KINDS
        if definitions[kind]
    }

    assert owned == {}


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
    operational_words = set().union(*map(_defined_words, CURRENT_SR3_MODULES))
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
        "STREAMS-OPRECEIPT-HEADER-CLASSIFY",
        "STREAMS-OPROOT-HEADER-CLASSIFY",
    } <= operational_words


def test_streams_sr3_dispatch_lifecycle_surface_is_exact() -> None:
    public_words = {
        word
        for word in _colon_words(OPERATIONAL_DISPATCH)
        if word.startswith("STREAMS-OPDISPATCH-")
    }

    assert public_words == {
        "STREAMS-OPDISPATCH-VALID?",
        "STREAMS-OPDISPATCH-STATE@",
        "STREAMS-OPDISPATCH-STATUS@",
        "STREAMS-OPDISPATCH-SPOOL-STATUS@",
        "STREAMS-OPDISPATCH-FLOW-STATUS@",
        "STREAMS-OPDISPATCH-SPOOL@",
        "STREAMS-OPDISPATCH-POOL@",
        "STREAMS-OPDISPATCH-FLOW@",
        "STREAMS-OPDISPATCH-LEASE@",
        "STREAMS-OPDISPATCH-GENERATION@",
        "STREAMS-OPDISPATCH-ATTEMPT@",
        "STREAMS-OPDISPATCH-COMPLETION@",
        "STREAMS-OPDISPATCH-PAYLOAD-U@",
        "STREAMS-OPDISPATCH-CLEANUP-ERROR@",
        "STREAMS-OPDISPATCH-INIT",
        "STREAMS-OPDISPATCH-BIND",
        "STREAMS-OPDISPATCH-ENQUEUE",
        "STREAMS-OPDISPATCH-DISPATCH",
        "STREAMS-OPDISPATCH-POLL",
        "STREAMS-OPDISPATCH-CANCEL",
        "STREAMS-OPDISPATCH-RELEASE",
    }


def test_streams_sr3_compaction_surface_is_exact_and_neutral() -> None:
    public_prefix = "STREAMS-SPOOL-COMPACTION-"
    public_colon_words = {
        word
        for word in _colon_words(OPERATIONAL_COMPACTION)
        if word.startswith(public_prefix)
    }
    words = _defined_words(OPERATIONAL_COMPACTION)

    assert public_colon_words == {
        "STREAMS-SPOOL-COMPACTION-CONTEXT-VALID?",
        "STREAMS-SPOOL-COMPACTION-STATUS@",
        "STREAMS-SPOOL-COMPACTION-CONTEXT-INIT",
        "STREAMS-SPOOL-COMPACTION-CANCEL",
        "STREAMS-SPOOL-COMPACTION-STEP-XT",
        "STREAMS-SPOOL-COMPACTION-FINALIZE-XT",
    }
    assert "STREAMS-SPOOL-COMPACTION-CONTEXT-SIZE" in words


def test_streams_sr3_dispatch_commits_authority_before_runtime_effect() -> None:
    enqueue = _forth_code(
        _colon_definition(
            OPERATIONAL_DISPATCH,
            "STREAMS-OPDISPATCH-ENQUEUE",
        )
    )
    dispatch = _forth_code(
        _colon_definition(
            OPERATIONAL_DISPATCH,
            "STREAMS-OPDISPATCH-DISPATCH",
        )
    )
    activate = _forth_code(
        _colon_definition(
            OPERATIONAL_DISPATCH,
            "_SOD-ACTIVATE-DURABLE",
        )
    )
    poll = _forth_code(
        _colon_definition(
            OPERATIONAL_DISPATCH,
            "STREAMS-OPDISPATCH-POLL",
        )
    )

    assert "STREAMS-SPOOL-ADMIT" in enqueue
    direct_effect_words = {
        "SCON.START-XT",
        "STREAMS-FLOW-START",
        "STREAMS-FLOW-STEP",
    }
    assert direct_effect_words.isdisjoint(enqueue.split())
    assert direct_effect_words.isdisjoint(dispatch.split())
    assert "STREAMS-FLOW-STEP" in poll
    assert poll.index("STREAMS-OPDISPATCH-STATE-ACTIVE") < poll.index(
        "STREAMS-FLOW-STEP"
    )
    assert dispatch.index("_SOD-STAGE-RUNTIME") < dispatch.index(
        "_SOD-ACTIVATE-DURABLE"
    )
    assert activate.index("STREAMS-SPOOL-ACTIVATE") < activate.index(
        "STREAMS-OPDISPATCH-STATE-ACTIVE"
    )


def test_streams_sr3_dispatch_checks_authority_before_runtime_acquisition() -> None:
    dispatch = _forth_code(
        _colon_definition(
            OPERATIONAL_DISPATCH,
            "STREAMS-OPDISPATCH-DISPATCH",
        )
    )
    classify = _forth_code(
        _colon_definition(
            OPERATIONAL_DISPATCH,
            "_SOD-CLASSIFY-STALE",
        )
    )
    activate = _forth_code(
        _colon_definition(
            OPERATIONAL_DISPATCH,
            "_SOD-ACTIVATE-DURABLE",
        )
    )
    replay_start = activate.index("DUP STREAMS-SPOOL-S-REPLAY = IF")
    replay_end = activate.index("THEN", replay_start)
    replay_branch = activate[replay_start:replay_end]

    assert dispatch.index("_SOD-CLASSIFY-STALE") < dispatch.index(
        "_SOD-ACQUIRE-RUNTIME"
    )
    assert "STREAMS-SPOOL-CLASSIFY-STALE" in classify
    assert "STREAMS-OPDISPATCH-S-BUSY EXIT" in replay_branch
    assert {
        "STREAMS-OPDISPATCH-S-OK",
        "STREAMS-OPDISPATCH-S-PENDING",
        "STREAMS-OPDISPATCH-STATE-ACTIVE",
    }.isdisjoint(replay_branch.split())


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


def test_streams_sr3_attempt_uses_only_the_current_receipt_reference_shape() -> None:
    words = _defined_words(OPERATIONAL_RECORDS)
    required = {
        "SOPATT.ENDPOINT-SEAL",
        "SOPATT.PROFILE",
        "SOPATT.READY-SEQUENCE",
        "SOPATT.DISPATCH-COUNT",
        "SOPROOT.RECEIPT-COUNT",
        "SOPROOT.RECEIPT-BYTES",
        "SOPROOT.CLEANUP-FAILED-COUNT",
        "SOPROOT.UNCOMPACTED-CLEANUP-COUNT",
    }
    receipt_accessors = {
        word for word in words if word.startswith("SOPATT.RECEIPT-")
    }
    root_sequence_accessors = {
        word for word in words if word.startswith("SOPROOT.NEXT-")
    }

    assert required <= words
    assert receipt_accessors == {
        "SOPATT.RECEIPT-POLICY",
        "SOPATT.RECEIPT-BYTE-LIMIT",
        "SOPATT.RECEIPT-ID",
        "SOPATT.RECEIPT-REF",
    }
    assert root_sequence_accessors == {
        "SOPROOT.NEXT-ACCEPTED-SEQUENCE",
        "SOPROOT.NEXT-READY-SEQUENCE",
    }


def test_streams_sr3_lifecycle_surface_is_exact_and_safe_only() -> None:
    words = _defined_words(OPERATIONAL_SPOOL)
    operational_words = set().union(*map(_defined_words, OPERATIONAL_MODULES))
    required = {
        "STREAMS-SPOOL-ATTEMPT@",
        "STREAMS-SPOOL-PAYLOAD-STREAM",
        "STREAMS-SPOOL-READY@",
        "STREAMS-SPOOL-ACTIVATE",
        "STREAMS-SPOOL-TERMINALIZE",
        "STREAMS-SPOOL-REQUEUE-SAFE",
        "STREAMS-SPOOL-RECEIPT@",
        "STREAMS-SPOOL-RECEIPT-STREAM",
        "STREAMS-SPOOL-CLEANUP-CANDIDATE@",
        "STREAMS-SPOOL-CLEANUP",
        "STREAMS-SPOOL-COMPLETION-INIT",
        "STREAMS-SPOOL-COMPLETION-VALID?",
    }
    forbidden = {
        "STREAMS-SPOOL-REQUEUE",
        "STREAMS-SPOOL-REQUEUE-FORCE",
        "STREAMS-SPOOL-RETRY-FORCE",
        "STREAMS-SPOOL-TERMINALIZE-FORCE",
        "SOPROOT.CLEANUP-BACKLOG",
        "SOPROOT.PHYSICAL-RETIREMENT",
        "SPOOLCAP.CLEANUP-BACKLOG",
        "SPOOLCAP.PHYSICAL-RETIREMENT",
    }

    assert required <= words
    assert operational_words.isdisjoint(forbidden)


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


def test_streams_sr3_root_and_index_agree_on_exactly_eight_trees() -> None:
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
        "usage": record_constants["STREAMS-OPROOT-TREE-USAGE"],
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
        "usage": index_constants["STREAMS-OI-TREE-OPERATIONAL-USAGE"],
    }

    assert record_constants["STREAMS-OPROOT-TREE-COUNT"] == 8
    assert index_constants["STREAMS-OI-TREE-COUNT"] == 8
    assert record_trees == index_trees
    assert set(record_trees.values()) == set(range(8))
    scopes = {
        value
        for name, value in index_constants.items()
        if name.startswith("STREAMS-OI-SCOPE-")
    }
    families = {
        value
        for name, value in index_constants.items()
        if name.startswith("STREAMS-OI-F-")
    }
    assert len(scopes) == 8
    assert 0 not in scopes
    assert len(families) == 10
    assert 0 not in families


def test_streams_sr3_endpoint_policy_is_pinned_only() -> None:
    config_constants = _integer_constants(OPERATIONAL_CONFIG_RECORDS)

    assert {
        name: value
        for name, value in config_constants.items()
        if name.startswith("STREAMS-OPCONN-ENDPOINT-")
    } == {
        "STREAMS-OPCONN-ENDPOINT-PINNED": 1,
    }


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
