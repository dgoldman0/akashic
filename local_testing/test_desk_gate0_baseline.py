"""Host-side integrity checks for the retained Desk Gate 0 baseline."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path


AKASHIC_ROOT = Path(__file__).resolve().parents[1]
WORKSPACE_ROOT = AKASHIC_ROOT.parent
FIXTURE_ROOT = Path(__file__).resolve().parent / "fixtures" / "desk-gate0"
MANIFEST_PATH = FIXTURE_ROOT / "manifest.json"
STREAMS_ROOT = AKASHIC_ROOT / "akashic" / "tui" / "applets" / "streams"
PINNED_CONTRACT_SHA256 = (
    "02725e3d36b0ee0f1fd7a238d1906fb60df8f07988776f3e0cfee247c4addedd"
)


def _manifest() -> dict:
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def _u64(record: bytes, offset: int) -> int:
    return int.from_bytes(record[offset : offset + 8], "little")


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def test_contract_pin_and_ratified_decisions() -> None:
    manifest = _manifest()
    assert manifest["schema"] == "akashic.desk.gate0-baseline.v1"
    assert manifest["ratification"]["status"] == "ratified"
    contract = manifest["ratification"]["contract"]
    assert contract["sha256"] == PINNED_CONTRACT_SHA256
    assert contract["bytes"] == 186417
    assert len(manifest["ratification"]["accepted_decisions"]) == 10

    # The workspace contract is intentionally outside the nested repository.
    # Verify it when this checkout is being tested in the canonical workspace,
    # while keeping the nested repository independently testable.
    workspace_contract = WORKSPACE_ROOT / contract["workspace_path"]
    if workspace_contract.is_file():
        content = workspace_contract.read_bytes()
        assert len(content) == contract["bytes"]
        assert _sha256(content) == contract["sha256"]


def test_fixture_hashes_and_common_envelopes() -> None:
    manifest = _manifest()
    fixtures = {entry["path"]: entry for entry in manifest["fixtures"]}
    assert set(fixtures) == {
        "source-v1-valid.bin",
        "source-v1-corrupt.bin",
        "source-v2-future.bin",
        "observation-v1-valid.bin",
        "observation-v1-corrupt.bin",
        "observation-v2-future.bin",
        "draft-v1-legacy-r7.bin",
    }

    for name, entry in fixtures.items():
        record = (FIXTURE_ROOT / name).read_bytes()
        assert len(record) == entry["bytes"]
        assert _sha256(record) == entry["sha256"]
        assert record[:8] == entry["magic_ascii"].encode("ascii")
        assert _u64(record, 8) == entry["format"]
        assert _u64(record, 16) == 64
        assert _u64(record, 56) == 0
        if "generation" in entry:
            assert _u64(record, 24) == entry["generation"]
        if "revision" in entry:
            assert _u64(record, 24) == entry["revision"]

    source_valid = (FIXTURE_ROOT / "source-v1-valid.bin").read_bytes()
    source_corrupt = (FIXTURE_ROOT / "source-v1-corrupt.bin").read_bytes()
    source_future = (FIXTURE_ROOT / "source-v2-future.bin").read_bytes()
    assert [
        index
        for index, (valid, corrupt) in enumerate(zip(source_valid, source_corrupt))
        if valid != corrupt
    ] == [64]
    assert source_future[64:] == source_valid[64:]
    assert _u64(source_valid, 32) == 36648

    observation_valid = (
        FIXTURE_ROOT / "observation-v1-valid.bin"
    ).read_bytes()
    observation_corrupt = (
        FIXTURE_ROOT / "observation-v1-corrupt.bin"
    ).read_bytes()
    observation_future = (
        FIXTURE_ROOT / "observation-v2-future.bin"
    ).read_bytes()
    assert [
        index
        for index, (valid, corrupt) in enumerate(
            zip(observation_valid, observation_corrupt)
        )
        if valid != corrupt
    ] == [64]
    assert observation_future[64:] == observation_valid[64:]
    assert _u64(observation_valid, 32) == 131072

    draft = (FIXTURE_ROOT / "draft-v1-legacy-r7.bin").read_bytes()
    assert _u64(draft, 32) == 15
    assert draft[64:] == "exact ☂ café".encode("utf-8")


def test_frozen_public_words_and_statuses_still_exist() -> None:
    manifest = _manifest()
    module_by_contract = {
        "source_registry": "source-registry.f",
        "source_store": "source-store.f",
        "observation_checkpoint": "observation-state.f",
        "observation_store": "observation-store.f",
        "legacy_draft_store": "draft-store.f",
    }
    for contract_name, module_name in module_by_contract.items():
        contract = manifest["durable_contracts"][contract_name]
        source = (STREAMS_ROOT / module_name).read_text(encoding="utf-8")
        words = contract.get("public_words", []) + contract.get(
            "public_accessors", []
        )
        assert words
        for word in words:
            assert re.search(
                rf"^:\s+{re.escape(word)}(?:\s|$)", source, re.MULTILINE
            ), f"{word} is no longer defined by {module_name}"
        for status, value in contract.get("statuses", {}).items():
            assert re.search(
                rf"^\s*{value}\s+CONSTANT\s+{re.escape(status)}\s*$",
                source,
                re.MULTILINE,
            ), f"{status} no longer has frozen value {value}"


def test_capability_and_scenario_ledgers_are_complete() -> None:
    manifest = _manifest()
    streams = (STREAMS_ROOT / "streams.f").read_text(encoding="utf-8")
    capabilities = manifest["capabilities"]
    assert len(capabilities) == 15
    assert len({capability["id"] for capability in capabilities}) == 15
    effect_tokens = {
        "observe": "CAP-E-OBSERVE",
        "mutate": "CAP-E-MUTATE",
        "persist": "CAP-E-PERSIST",
        "external": "CAP-E-EXTERNAL",
    }
    for capability in capabilities:
        assert f'S" {capability["id"]}"' in streams
        assert capability["input_schema"] in streams
        assert capability["output_schema"] in streams
        assert capability["kind"] in {"resource", "command"}
        assert capability["effects"]
        for effect in capability["effects"]:
            assert effect_tokens[effect] in streams

    scenarios = {entry["id"] for entry in manifest["scenario_ledger"]}
    assert {
        "retained-valid-corrupt-future-records",
        "nonempty-source-missing-observation-companion",
        "absent-first-use",
        "stale-generation",
        "interrupted-replacement",
        "uncertain-and-committed-cleanup",
        "selector-and-close-after-effect-restoration",
    } <= scenarios


def test_deterministic_profile_matrix_is_exact() -> None:
    matrix = _manifest()["deterministic_profile_matrix"]
    assert matrix["status"] == "green"
    assert matrix["common_max_steps"] == 8_000_000_000
    assert matrix["common_timeout_seconds"] == 120
    assert matrix["overrides"]["desktop-agent-hardening"] == {
        "max_steps": 16_000_000_000,
        "timeout_seconds": 240,
        "measured_steps": 15_210_000_000,
    }
    assert matrix["profiles"] == [
        "practice-contracts",
        "pad-resource-contracts",
        "desktop-resource",
        "daybook-contracts",
        "grid-contracts",
        "agent-persistence",
        "agent-ui",
        "desktop-agent-hardening",
        "streams-source-registry-contracts",
        "streams-source-store-contracts",
        "streams-observation-contracts",
        "streams-observation-store-contracts",
        "streams-observation-state-compile",
        "streams-source-owner-contracts",
        "streams-source-ui-contracts",
        "streams-syndec-contracts",
        "streams-syndication-http-contracts",
        "streams-configured-provider-compile",
        "streams-refresh-owner-compile",
        "streams-refresh-owner-contracts",
        "streams-manual-refresh-contracts",
        "streams-draft-contracts",
        "streams-contracts",
        "streams-page-contracts",
        "streams-xio-contracts",
        "streams-persistence-contracts",
        "desktop-streams",
    ]
    assert len(matrix["supplemental_evidence"]) == 3


def test_generator_uses_production_codecs_for_every_fixture() -> None:
    generator = (
        Path(__file__).resolve().parent / "generate_desk_gate0_fixtures.py"
    ).read_text(encoding="utf-8")
    for production_word in (
        "_STREAMS-SOURCE-STORE-ENCODE",
        "STREAMS-SOURCE-STORE-SAVE",
        "_STREAMS-OBSERVATION-STORE-ENCODE",
        "STREAMS-OBSERVATION-STORE-SAVE",
        "STREAMS-DRAFT-STORE-SAVE",
    ):
        assert production_word in generator
    for entry in _manifest()["fixtures"]:
        assert entry["path"] in generator
