#!/usr/bin/env python3
"""Static contracts for the bounded sandbox job service.

The executable gate (sandbox-job-service-gate) runs every job path.
These checks pin the shape it cannot see: what the service depends on,
where its limits come from, and which operations stay cheap.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
AKASHIC_ROOT = REPO_ROOT / "akashic"
LOCAL_TESTING = REPO_ROOT / "local_testing"

sys.path.insert(0, str(LOCAL_TESTING))

from forth_dependencies import dependency_closure  # noqa: E402


SERVICE = "runtime/sandbox-job-service.f"

PUBLIC_WORDS = (
    "SBOX-JOB-SERVICE-MEASURE",
    "SBOX-JOB-SERVICE-INIT",
    "SBOX-JOB-SERVICE-VALID?",
    "SBOX-JOB-SERVICE-OWNER?",
    "SBOX-JOB-SUBMIT",
    "SBOX-JOB-SERVICE-TICK",
    "SBOX-JOB-QUERY",
    "SBOX-JOB-CANCEL",
    "SBOX-JOB-RESULT-MEASURE",
    "SBOX-JOB-RESULT-TAKE",
    "SBOX-JOB-DISCARD",
    "SBOX-JOB-OWNER-DRAIN",
    "SBOX-JOB-SERVICE-CLOSE",
    "SBOX-JOB-SERVICE-DRAIN",
    "SBOX-JOB-SERVICE-RELEASE",
    "SBOX-JOB-SERVICE-STATE@",
    "SBOX-JOB-SERVICE-ACTIVATION@",
    "SBOX-JOB-SERVICE-COUNT",
    "SBOX-JOB-SERVICE-RUNNABLE",
    "SBOX-JOB-SERVICE-CAPACITY@",
    "SBOX-JOB-SERVICE-AUDIT",
)

# Operations on one job or the whole service.  AUDIT alone walks every
# job and proves each host's whole graph.
OPERATIONS = (
    "SBOX-JOB-SUBMIT",
    "SBOX-JOB-SERVICE-TICK",
    "SBOX-JOB-QUERY",
    "SBOX-JOB-CANCEL",
    "SBOX-JOB-RESULT-MEASURE",
    "SBOX-JOB-RESULT-TAKE",
    "SBOX-JOB-DISCARD",
    "SBOX-JOB-OWNER-DRAIN",
)


def _source() -> str:
    return (AKASHIC_ROOT / SERVICE).read_text(encoding="utf-8")


def _definition(source: str, word: str) -> str:
    match = re.search(
        rf"^:\s+{re.escape(word)}(?:\s|$).*?;\s*$",
        source,
        re.MULTILINE | re.DOTALL,
    )
    assert match is not None, word
    return match.group(0)


def _stack_effect(source: str, word: str) -> str:
    match = re.search(
        rf"^:\s+{re.escape(word)}\s*\n?\s*\((.*?)\)",
        source,
        re.MULTILINE | re.DOTALL,
    )
    assert match is not None, word
    return " ".join(match.group(1).lower().split())


def _closure(definitions: dict[str, str], word: str) -> str:
    """The text of WORD and every service word it reaches."""
    seen: set[str] = set()
    pending = [word]
    while pending:
        name = pending.pop()
        if name in seen or name not in definitions:
            continue
        seen.add(name)
        body = re.sub(r"\\[^\n]*|\([^)]*\)", "", definitions[name])
        pending.extend(token for token in body.split()[2:] if token != name)
    return "\n".join(definitions[name] for name in sorted(seen))


def _definitions(source: str) -> dict[str, str]:
    return {
        match[1]: match[0]
        for match in re.finditer(
            r"(?ms)^:\s+(\S+)(?=\s).*?;\s*$", source
        )
    }


def test_the_service_runs_plans_without_a_module_table_or_component() -> None:
    closure = dependency_closure(AKASHIC_ROOT, (SERVICE,))

    assert "runtime/sandbox-host.f" in closure
    assert "runtime/sandbox-limits.f" in closure
    for absent in (
        "runtime/sandbox-module-owner.f",
        "runtime/practice-head.f",
        "runtime/instance.f",
    ):
        assert absent not in closure, absent
    for module in closure:
        assert module.split("/")[0] in {"runtime", "sandbox", "utils"}, module


def test_the_service_publishes_its_complete_lifecycle() -> None:
    source = _source()

    for word in PUBLIC_WORDS:
        assert re.search(
            rf"^:\s+{re.escape(word)}(?:\s|$)", source, re.MULTILINE
        ), word
    assert "CINST" not in source
    assert "SBOX-RECEIPT" not in source


def test_capacity_is_measured_and_part_of_exact_initialization() -> None:
    source = _source()

    assert not re.search(r"CONSTANT\s+SBOX-JOB-CAPACITY\b", source)
    assert _stack_effect(source, "SBOX-JOB-SERVICE-MEASURE") == (
        "capacity -- service-u|0 status"
    )
    assert _stack_effect(source, "SBOX-JOB-SERVICE-INIT") == (
        "parent policy slice-steps allowance-ms activation-id capacity "
        "service service-u -- status"
    )
    boundary = _definition(source, "_SBXJI-BOUNDARY")
    assert "SBOX-JOB-SERVICE-MEASURE" in boundary
    assert "_SBXJI-SERVICE-U @ <>" in boundary
    assert "SBOX-LIMITS-BOUNDED?" in boundary
    init = _definition(source, "SBOX-JOB-SERVICE-INIT")
    assert "SBOX-LIMITS-COPY" in init
    for loop in ("_SBXJ-FIND", "_SBXJSUB-FREE", "_SBXJT-NEXT"):
        assert "_SBXJ.CAPACITY @ 0 ?DO" in _definition(source, loop), loop


def test_a_job_is_bound_to_an_opaque_owner_token() -> None:
    source = _source()

    assert _stack_effect(source, "SBOX-JOB-SUBMIT") == (
        "plan entry entry-u input input-u request|0 owner-id "
        "owner-generation service -- activation-id|0 job-generation|0 "
        "status"
    )
    for word in (
        "SBOX-JOB-QUERY",
        "SBOX-JOB-CANCEL",
        "SBOX-JOB-RESULT-MEASURE",
        "SBOX-JOB-DISCARD",
    ):
        assert _stack_effect(source, word).startswith(
            "activation-id job-generation owner-id owner-generation service"
        ), word
    find = _definition(source, "_SBXJ-FIND")
    assert "_SBXJS.OWNER-ID @" in find
    assert "_SBXJS.OWNER-GENERATION @" in find
    assert "SBOX-JOB-S-NOT-OWNER" in find


def test_effective_limits_narrow_the_policy_by_request() -> None:
    source = _source()
    limits = _definition(source, "_SBXJSUB-LIMITS")

    copy = limits.index("SBOX-LIMITS-COPY")
    meet = limits.index("SBOX-LIMITS-MEET")
    materialize = limits.index("SBOX-LIMITS-MATERIALIZE")
    assert copy < meet < materialize
    assert "_SBXJ.POLICY" in limits
    assert "SBOX-LIMIT-WALL-MS" in limits
    # The profile holds semantics only; it never narrows a limit.
    assert "PROFILE" not in limits
    # One effective record gives both the value and the activation limits.
    assert "_SBXJ.VALUE-LIMITS" in limits
    assert "_SBXJ.VM-LIMITS" in limits
    host = _definition(source, "_SBXJSUB-HOST")
    assert host.index("_SBXJ.VALUE-LIMITS") < host.index("_SBXJ.VM-LIMITS")
    # No budget or value limit is fixed in the service itself.
    assert not re.search(r"^\s*\d+\s+CONSTANT\s+_SBXJ-.*BUDGET", source,
                         re.MULTILINE)
    submit = _definition(source, "SBOX-JOB-SUBMIT")
    assert "_SBXJSUB-SCRUB" in submit


def test_tick_runs_jobs_within_its_allowance_and_enforces_deadlines() -> None:
    source = _source()
    tick = _definition(source, "SBOX-JOB-SERVICE-TICK")
    step = _definition(source, "_SBXJT-STEP")
    spent = _definition(source, "_SBXJT-SPENT?")

    assert "_SBXJ.RUNNABLE-N @ 0>" in tick
    assert "_SBXJT-SPENT?" in tick
    assert "_SBXJ.ALLOWANCE-MS @" in spent
    assert "MS@" in spent
    assert "_SBXJS.DEADLINE @" in step
    assert "SBOX-VM-CANCEL-DEADLINE" in step
    assert "_SBXJ.SLICE-STEPS @" in step
    assert "SBOX-HOST-RUN-SLICE" in step
    # At least one slice runs before the allowance is checked.
    assert tick.index("_SBXJT-STEP") < tick.index("_SBXJT-SPENT?")


def test_operations_check_only_the_header_and_the_job_they_touch() -> None:
    source = _source()
    definitions = _definitions(source)

    for word in OPERATIONS:
        reached = _closure(definitions, word)
        assert "SBOX-JOB-SERVICE-AUDIT" not in reached, word
        assert "SBOX-HOST-VALID?" not in reached, word
        assert "_SBXJA-" not in reached, word
    audit = _definition(source, "_SBXJA-JOB?")
    assert "SBOX-HOST-VALID?" in audit


def test_take_writes_the_result_into_the_callers_buffer_then_frees_the_job() -> None:
    source = _source()
    take = _definition(source, "SBOX-JOB-RESULT-TAKE")

    assert _stack_effect(source, "SBOX-JOB-RESULT-TAKE").startswith(
        "result result-capacity activation-id"
    )
    assert take.index("SBOX-HOST-FINISH") < take.index("_SBXJ-DISCARD")
    assert "MSPAN-OVERLAP?" in take
    discard = _definition(source, "_SBXJ-DISCARD")
    assert "SBOX-HOST-RELEASE" in discard
    assert "_SBXJ-HOST-LOST" in discard
