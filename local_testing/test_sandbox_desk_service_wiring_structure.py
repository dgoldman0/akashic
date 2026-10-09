#!/usr/bin/env python3
"""Static contracts for how Desk composes the sandbox job service."""

from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DESK = (
    REPO_ROOT / "akashic" / "tui" / "applets" / "desk" / "desk.f"
)
HOST = REPO_ROOT / "akashic" / "tui" / "applet-host" / "host.f"


def _source(path: Path = DESK) -> str:
    return path.read_text(encoding="utf-8")


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


def test_desk_borrows_its_callers_sandbox_policy_before_run() -> None:
    source = _source()
    configure = _definition(source, "DESK-SANDBOX-CONFIGURE")

    assert "REQUIRE ../../../runtime/sandbox-job-service.f" in source
    assert _stack_effect(
        source,
        "DESK-SANDBOX-CONFIGURE",
    ) == "policy|0 capacity slice-steps allowance-ms -- status"
    assert "_DESK-CURRENT-STATE @" in configure
    assert "SBOX-JOB-SERVICE-MEASURE" in configure
    assert "SBOX-LIMITS-BOUNDED?" in configure
    for pending in ("POLICY", "CAPACITY", "SLICE", "ALLOWANCE"):
        assert f"_DESK-PENDING-SBOX-{pending} !" in configure, pending
    assert "ALLOCATE" not in configure
    assert "SBOX-LIMITS-COPY" not in configure
    assert "SBOX-MODULE-OWNER" not in source


def test_desk_builds_its_measured_service_from_the_callers_policy() -> None:
    source = _source()
    layout = source.split("CMP-LAYOUT-BEGIN", 1)[1].split(
        "CMP-LAYOUT-SIZE", 1
    )[0]

    assert not re.search(
        r"CMP-FIELD:\s+_DESK-SANDBOX\b",
        layout,
    )
    for cell in (
        "_DESK-SANDBOX",
        "_DESK-SANDBOX-U",
        "_DESK-SBOX-POLICY",
        "_DESK-SBOX-CAPACITY",
        "_DESK-SBOX-SLICE",
        "_DESK-SBOX-ALLOWANCE",
    ):
        assert re.search(
            rf"_DESK-CURRENT-STATE\s+CMP-CELL:\s+{re.escape(cell)}\s",
            layout,
        ), cell
    desk_init = _definition(source, "DESK-INIT-CB")
    assert "_DESK-PENDING-SBOX-POLICY @ _DESK-SBOX-POLICY !" in desk_init
    assert "_DESK-PENDING-SBOX-CLEAR" in desk_init
    recovery = desk_init.split("DESK-RECOVERY? IF", 1)[1].split(
        "THEN", 1
    )[0]
    assert "_DESK-SBOX-STAGING-CLEAR" in recovery

    init = _definition(source, "_DESK-SBOX-INIT")
    assert "SBOX-JOB-SERVICE-MEASURE" in init
    assert "ALLOCATE" in init
    assert re.search(
        r"_DINI-CONTEXT\s+@\s+"
        r"_DESK-SBOX-POLICY\s+@\s+"
        r"_DESK-SBOX-SLICE\s+@\s+"
        r"_DESK-SBOX-ALLOWANCE\s+@\s+"
        r"_DINI-INST\s+@\s+CINST\.ID\s+@\s+"
        r"_DESK-SBOX-CAPACITY\s+@\s+"
        r"_DESK-SANDBOX\s+@\s+"
        r"_DESK-SANDBOX-U\s+@\s+"
        r"SBOX-JOB-SERVICE-INIT",
        init,
    )
    # Every limit comes from the caller: Desk sets none of its own.
    for word in (
        "SBOX-LIMITS-BEGIN",
        "SBOX-LIMIT-CAP",
        "SBOX-VALUE-LIMIT!",
    ):
        assert word not in source, word
    assert not re.search(r"CONSTANT\s+_DESK-SBOX-", source)


def test_desk_publishes_only_the_exact_pure_compute_service_id() -> None:
    source = _source()
    setup = _definition(source, "_DESK-SERVICE-TABLE-SETUP")

    exact_id = 'S" org.akashic.sandbox.pure-compute"'
    assert source.count(exact_id) == 1
    assert exact_id in setup
    after_id = setup.split(exact_id, 1)[1]
    assert "[']" in after_id
    assert "_DESK-SERVICE+" in after_id


def test_desk_runs_sandbox_jobs_before_child_ticks() -> None:
    tick = _definition(_source(), "DESK-TICK-CB")

    assert tick.count("SBOX-JOB-SERVICE-TICK") == 1
    sandbox_tick = tick.index("SBOX-JOB-SERVICE-TICK")
    child_tick = tick.index("_DESK-HOST AHOST-TICK")
    assert sandbox_tick < child_tick


def test_child_release_drains_sandbox_work_before_xio_and_instance_free() -> None:
    desk = _source()
    release = _definition(desk, "_DESK-HOST-RELEASE")

    sandbox_drain = release.index("SBOX-JOB-OWNER-DRAIN")
    xio_release = release.index("_DESK-XIO-RELEASE-OWNER")
    assert sandbox_drain < xio_release
    # The closing child's identity is its owner token.
    assert re.search(
        r"_DHR-INST\s+@\s+CINST\.ID\s+@\s+"
        r"_DHR-INST\s+@\s+CINST\.GENERATION\s+@\s+"
        r"_DESK-SANDBOX\s+@\s+SBOX-JOB-OWNER-DRAIN",
        release,
    )

    host = _source(HOST)
    close = _definition(host, "_AHOST-CLOSE-SLOT-FORCE")
    assert close.index("_AHC-RELEASE") < close.index("_AHC-FREE-INST")


def test_desk_releases_service_before_tables_context_and_practice() -> None:
    source = _source()
    fini = _definition(source, "_DESK-INTEROP-FINI-QUIESCED")
    sandbox_fini = _definition(source, "_DESK-SBOX-FINI")
    shutdown = _definition(source, "DESK-SHUTDOWN-CB")

    assert "SBOX-JOB-SERVICE-RELEASE" in sandbox_fini
    assert re.search(
        r"_DESK-SANDBOX\s+@\s+DUP\s+0=\s+IF",
        sandbox_fini,
    )
    assert "?DUP 0=" not in sandbox_fini
    assert re.search(
        r"_DESK-SANDBOX\s+@\s+"
        r"_DESK-SANDBOX-U\s+@\s+"
        r"SBOX-JOB-SERVICE-RELEASE",
        sandbox_fini,
    )
    assert "FREE" in sandbox_fini
    assert "0 _DESK-SANDBOX !" in sandbox_fini
    assert "0 _DESK-SANDBOX-U !" in sandbox_fini
    service_release = fini.index("_DESK-SBOX-FINI")
    table_release = fini.index("_DESK-SERVICE-TABLE-FINI")
    assert service_release < table_release
    assert shutdown.index("_DSD-INTEROP-FINI") < shutdown.index(
        "_DSD-PRACTICE-FINI"
    )
    assert "SBOX-MODULE-OWNER-RELEASE" not in source
