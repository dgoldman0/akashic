#!/usr/bin/env python3
"""Static contracts for exact transient Desk sandbox admission."""

from __future__ import annotations

import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
AKASHIC_ROOT = REPO_ROOT / "akashic"
LOCAL_TESTING = REPO_ROOT / "local_testing"

sys.path.insert(0, str(LOCAL_TESTING))

from forth_dependencies import dependency_closure  # noqa: E402


ADMISSION = Path("runtime/sandbox-admission.f")

PUBLIC_WORDS = (
    "SBOX-ADMISSION-INIT",
    "SBOX-ADMISSION-VALID?",
    "SBOX-ADMISSION-PRACTICE@",
    "SBOX-ADMISSION-CONTEXT@",
    "SBOX-ADMISSION-ACTIVATION@",
    "SBOX-ADMISSION-MODULE@",
    "SBOX-ADMISSION-INVOKE",
    "SBOX-ADMISSION-RUN-SLICE",
    "SBOX-ADMISSION-RUN-STATE@",
    "SBOX-ADMISSION-CANCEL",
    "SBOX-ADMISSION-RESULT-TAKE",
    "SBOX-ADMISSION-CLOSE",
    "SBOX-ADMISSION-DRAIN",
    "SBOX-ADMISSION-RELEASE",
    "SBOX-RECEIPT-VALID?",
    "SBOX-RECEIPT-ACTIVATION@",
    "SBOX-RECEIPT-INVOCATION@",
    "SBOX-RECEIPT-PRACTICE@",
    "SBOX-RECEIPT-CONTEXT@",
    "SBOX-RECEIPT-MODULE@",
    "SBOX-RECEIPT-PAYLOAD@",
    "SBOX-RECEIPT-RELEASE",
)

FORBIDDEN_DEPENDENCY_FRAGMENTS = (
    "app-manifest",
    "app-catalog",
    "app-loader",
    "app-builder",
    "app-desc",
    "agent",
    "provider",
    "tool-gateway",
    "request-bus",
    "schema",
    "digest",
    "cache",
    "vfs",
    "capability",
    "uidl",
    "widget",
)


def _source() -> str:
    return (AKASHIC_ROOT / ADMISSION).read_text(encoding="utf-8")


def _definition(source: str, word: str) -> str:
    match = re.search(
        rf"^:\s+{re.escape(word)}(?:\s|$).*?;\s*$",
        source,
        re.MULTILINE | re.DOTALL,
    )
    assert match is not None, word
    return match.group(0)


def test_admission_dependency_boundary_excludes_native_and_effect_paths() -> None:
    closure = dependency_closure(AKASHIC_ROOT, (ADMISSION.as_posix(),))

    assert "runtime/sandbox-slot.f" in closure
    assert "runtime/sandbox-module-owner.f" in closure
    assert "runtime/sandbox-host.f" in closure
    assert "runtime/practice-head.f" in closure
    for module in closure:
        normalized = module.lower()
        assert not any(
            fragment in normalized
            for fragment in FORBIDDEN_DEPENDENCY_FRAGMENTS
        ), module


def test_admission_publishes_tuple_closed_lifecycle_and_receipt_api() -> None:
    source = _source()

    for word in PUBLIC_WORDS:
        definition = re.compile(
            rf"^:\s+{re.escape(word)}(?:\s|$)",
            re.MULTILINE,
        )
        assert definition.search(source) is not None, word


def test_admission_writes_its_execution_class_and_accepts_no_native_shape() -> None:
    source = _source()
    init = _definition(source, "SBOX-ADMISSION-INIT")

    assert "SBOX-CLASS-PURE" in source
    assert "SBOX-CLASS-PURE R@ _SBXA.CLASS !" in source
    assert "EXECUTE" not in source
    assert "EVALUATE" not in source
    assert "class" not in re.search(
        r": SBOX-ADMISSION-INIT\s*\n?\s*\((.*?)\)",
        source,
        re.DOTALL,
    ).group(1).lower()
    assert "_SBXAI-BOUNDARY" in init
    assert "_SBXAI-BINDING-STATUS" in _definition(source, "_SBXAI-BOUNDARY")


def test_receipt_copies_exact_correlation_before_publication() -> None:
    source = _source()

    for field in (
        "_SBXRC-ACTIVATION-ID",
        "_SBXRC-ACTIVATION-GENERATION",
        "_SBXRC-INVOCATION-GENERATION",
        "_SBXRC-PRACTICE-REVISION",
        "_SBXRC-CONTEXT-ID",
        "_SBXRC-CONTEXT-GENERATION",
        "_SBXRC-CONTEXT-EPOCH",
        "_SBXRC-MODULE-REVISION",
        "_SBXRC-PRACTICE-RID",
        "_SBXRC-MODULE-RID",
        "_SBXRC-ENTRY",
        "_SBXRC-RESULT",
    ):
        assert field in source
    take = _definition(source, "SBOX-ADMISSION-RESULT-TAKE")
    commit = _definition(source, "_SBXART-COMMIT")
    assert "_SBXART-COMMIT" in take
    assert "_SBXS-RESULT-TAKE-PRECHECKED" in commit
    assert "_SBXART-COPY-METADATA" in commit
    assert "_SBXRC-MAGIC" in commit
    assert commit.index("_SBXART-COPY-METADATA") < commit.index("_SBXRC-MAGIC")


def test_receipt_accessors_reuse_the_validated_nested_result() -> None:
    source = _source()
    valid = _definition(source, "SBOX-RECEIPT-VALID?")
    payload = _definition(source, "SBOX-RECEIPT-PAYLOAD@")

    assert valid.count("SBOX-SLOT-RESULT-VALID?") == 1
    assert "SBOX-SLOT-RESULT-GENERATION@" not in valid
    assert "SBOX-SLOT-RESULT-RUN-STATE@" not in valid
    assert "_SBXR-GENERATION-VALIDATED@" in valid
    assert "_SBXR-RUN-STATE-VALIDATED@" in valid
    assert "SBOX-SLOT-RESULT-PAYLOAD@" not in payload
    assert "_SBXR-PAYLOAD-VALIDATED@" in payload


def test_receipt_release_reuses_the_validated_nested_result() -> None:
    source = _source()
    release = _definition(source, "SBOX-RECEIPT-RELEASE")

    assert "SBOX-RECEIPT-VALID?" in release
    assert "_SBXR-RELEASE-VALIDATED" in release
    assert "SBOX-SLOT-RESULT-RELEASE" not in release


def test_receipt_preflight_covers_the_whole_live_invocation_graph() -> None:
    source = _source()
    active = _definition(source, "_SBXA-ACTIVE-SHAPE?")
    receipt = _definition(source, "_SBXA-RECEIPT-BOUNDARY")
    boundary = _definition(source, "_SBXART-BOUNDARY")
    span = _definition(source, "_SBXA-RESULT-SPAN-STATUS")
    validated_span = _definition(
        source,
        "_SBXA-SERVICE-RESULT-SPAN-STATUS",
    )

    assert active.count("SBOX-SLOT-VALID?") == 1
    assert "SBOX-SLOT-STATE@" not in active
    assert "_SBXS.STATE @" in active
    assert "_SBXART-RECEIPT 8 MSPAN-OVERLAP?" in receipt
    assert "_SBXART-GENERATION 8 MSPAN-OVERLAP?" in receipt
    assert "_SBXART-ADMISSION 8 MSPAN-OVERLAP?" in receipt
    assert "SBOX-RECEIPT-SIZE" in span
    assert "_SBXS-TAKE-SPAN-STATUS" in span
    assert "SBOX-RECEIPT-SIZE" in validated_span
    assert "_SBXS-TAKE-SPAN-VALIDATED" in validated_span
    assert boundary.index("_SBXA-EXTERNAL-SPAN?") < boundary.index(
        "_SBXA-RESULT-SPAN-STATUS"
    )


def test_admission_profile_is_registered_for_link_validation() -> None:
    harness = (LOCAL_TESTING / "akashic_tui.py").read_text(encoding="utf-8")

    assert 'PROFILES["sandbox-desk-admission"]' in harness
    assert '"runtime/sandbox-admission.f"' in harness
    assert "SBOX DESK ADMISSION LOAD PASS" in harness
