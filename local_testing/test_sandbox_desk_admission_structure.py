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


ADMISSION = Path("tui/applets/desk/sandbox-admission.f")

PUBLIC_WORDS = (
    "DESK-SBOX-ADMISSION-INIT",
    "DESK-SBOX-ADMISSION-VALID?",
    "DESK-SBOX-ADMISSION-PRACTICE@",
    "DESK-SBOX-ADMISSION-CONTEXT@",
    "DESK-SBOX-ADMISSION-ACTIVATION@",
    "DESK-SBOX-ADMISSION-MODULE@",
    "DESK-SBOX-ADMISSION-INVOKE",
    "DESK-SBOX-ADMISSION-RUN-SLICE",
    "DESK-SBOX-ADMISSION-RUN-STATE@",
    "DESK-SBOX-ADMISSION-CANCEL",
    "DESK-SBOX-ADMISSION-RESULT-TAKE",
    "DESK-SBOX-ADMISSION-CLOSE",
    "DESK-SBOX-ADMISSION-DRAIN",
    "DESK-SBOX-ADMISSION-RELEASE",
    "DESK-SBOX-RECEIPT-VALID?",
    "DESK-SBOX-RECEIPT-ACTIVATION@",
    "DESK-SBOX-RECEIPT-INVOCATION@",
    "DESK-SBOX-RECEIPT-PRACTICE@",
    "DESK-SBOX-RECEIPT-CONTEXT@",
    "DESK-SBOX-RECEIPT-MODULE@",
    "DESK-SBOX-RECEIPT-PAYLOAD@",
    "DESK-SBOX-RECEIPT-RELEASE",
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

    assert "tui/applets/desk/sandbox-component.f" in closure
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
    init = _definition(source, "DESK-SBOX-ADMISSION-INIT")

    assert "DESK-SBOX-CLASS-PURE" in source
    assert "DESK-SBOX-CLASS-PURE R@ _DSA.CLASS !" in source
    assert "EXECUTE" not in source
    assert "EVALUATE" not in source
    assert "class" not in re.search(
        r": DESK-SBOX-ADMISSION-INIT\s*\n?\s*\((.*?)\)",
        source,
        re.DOTALL,
    ).group(1).lower()
    assert "_DSAI-BOUNDARY" in init
    assert "_DSAI-BINDING-STATUS" in _definition(source, "_DSAI-BOUNDARY")


def test_receipt_copies_exact_correlation_before_publication() -> None:
    source = _source()

    for field in (
        "_DSRC-ACTIVATION-ID",
        "_DSRC-ACTIVATION-GENERATION",
        "_DSRC-INVOCATION-GENERATION",
        "_DSRC-PRACTICE-REVISION",
        "_DSRC-CONTEXT-ID",
        "_DSRC-CONTEXT-GENERATION",
        "_DSRC-CONTEXT-EPOCH",
        "_DSRC-MODULE-REVISION",
        "_DSRC-PRACTICE-RID",
        "_DSRC-MODULE-RID",
        "_DSRC-ENTRY",
        "_DSRC-RESULT",
    ):
        assert field in source
    take = _definition(source, "DESK-SBOX-ADMISSION-RESULT-TAKE")
    commit = _definition(source, "_DSART-COMMIT")
    assert "_DSART-COMMIT" in take
    assert "_DSC-RESULT-TAKE-PRECHECKED" in commit
    assert "_DSART-COPY-METADATA" in commit
    assert "_DSRC-MAGIC" in commit
    assert commit.index("_DSART-COPY-METADATA") < commit.index("_DSRC-MAGIC")


def test_receipt_accessors_reuse_the_validated_nested_result() -> None:
    source = _source()
    valid = _definition(source, "DESK-SBOX-RECEIPT-VALID?")
    payload = _definition(source, "DESK-SBOX-RECEIPT-PAYLOAD@")

    assert valid.count("DESK-SBOX-RESULT-VALID?") == 1
    assert "DESK-SBOX-RESULT-GENERATION@" not in valid
    assert "DESK-SBOX-RESULT-RUN-STATE@" not in valid
    assert "_DSR-GENERATION-VALIDATED@" in valid
    assert "_DSR-RUN-STATE-VALIDATED@" in valid
    assert "DESK-SBOX-RESULT-PAYLOAD@" not in payload
    assert "_DSR-PAYLOAD-VALIDATED@" in payload


def test_receipt_release_reuses_the_validated_nested_result() -> None:
    source = _source()
    release = _definition(source, "DESK-SBOX-RECEIPT-RELEASE")

    assert "DESK-SBOX-RECEIPT-VALID?" in release
    assert "_DSR-RELEASE-VALIDATED" in release
    assert "DESK-SBOX-RESULT-RELEASE" not in release


def test_receipt_preflight_covers_the_whole_live_invocation_graph() -> None:
    source = _source()
    active = _definition(source, "_DSA-ACTIVE-SHAPE?")
    receipt = _definition(source, "_DSA-RECEIPT-BOUNDARY")
    boundary = _definition(source, "_DSART-BOUNDARY")
    span = _definition(source, "_DSA-RESULT-SPAN-STATUS")
    validated_span = _definition(
        source,
        "_DSA-RESULT-SPAN-VALIDATED-STATUS",
    )

    assert active.count("DESK-SBOX-COMPONENT-VALID?") == 1
    assert "DESK-SBOX-COMPONENT-STATE@" not in active
    assert "_DSC.STATE @" in active
    assert "_DSART-RECEIPT 8 MSPAN-OVERLAP?" in receipt
    assert "_DSART-GENERATION 8 MSPAN-OVERLAP?" in receipt
    assert "_DSART-ADMISSION 8 MSPAN-OVERLAP?" in receipt
    assert "DESK-SBOX-RECEIPT-SIZE" in span
    assert "_DSC-TAKE-SPAN-STATUS" in span
    assert "DESK-SBOX-RECEIPT-SIZE" in validated_span
    assert "_DSC-TAKE-SPAN-VALIDATED" in validated_span
    assert boundary.index("_DSA-EXTERNAL-SPAN?") < boundary.index(
        "_DSA-RESULT-SPAN-STATUS"
    )


def test_admission_profile_is_registered_for_link_validation() -> None:
    harness = (LOCAL_TESTING / "akashic_tui.py").read_text(encoding="utf-8")

    assert 'PROFILES["sandbox-desk-admission"]' in harness
    assert '"tui/applets/desk/sandbox-admission.f"' in harness
    assert "SBOX DESK ADMISSION LOAD PASS" in harness
