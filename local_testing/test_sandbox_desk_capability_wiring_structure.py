#!/usr/bin/env python3
"""Static contracts for how Desk hosts the shared sandbox capability."""

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

    assert "REQUIRE ../../../interop/sandbox-capability.f" in source
    assert "runtime/sandbox-job-service.f" not in source
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
    assert "SBOX-MODULE-OWNER" not in source


def test_desk_hosts_one_capability_bound_to_its_callers_policy() -> None:
    source = _source()
    layout = source.split("CMP-LAYOUT-BEGIN", 1)[1].split(
        "CMP-LAYOUT-SIZE", 1
    )[0]

    for cell in (
        "_DESK-SANDBOX",
        "_DESK-SBOX-POLICY",
        "_DESK-SBOX-CAPACITY",
        "_DESK-SBOX-SLICE",
        "_DESK-SBOX-ALLOWANCE",
    ):
        assert re.search(
            rf"_DESK-CURRENT-STATE\s+CMP-CELL:\s+{re.escape(cell)}\s",
            layout,
        ), cell
    assert "_DESK-SANDBOX-U" not in source
    desk_init = _definition(source, "DESK-INIT-CB")
    assert "_DESK-PENDING-SBOX-POLICY @ _DESK-SBOX-POLICY !" in desk_init
    assert "_DESK-PENDING-SBOX-CLEAR" in desk_init
    recovery = desk_init.split("DESK-RECOVERY? IF", 1)[1].split(
        "THEN", 1
    )[0]
    assert "_DESK-SBOX-STAGING-CLEAR" in recovery

    init = _definition(source, "_DESK-SBOX-INIT")
    ensure = init.index("SBOX-CAPABILITY-COMPONENT _DESK-REGISTRY @ CREG-TYPE-ENSURE")
    new = init.index("SBOX-CAPABILITY-COMPONENT CINST-NEW")
    bind = init.index("SBOX-CAPABILITY-BIND")
    register = init.index("_DESK-REGISTRY @ CREG-INST+")
    assert ensure < new < bind < register
    assert re.search(
        r"_DINI-CONTEXT\s+@\s+"
        r"_DESK-SBOX-POLICY\s+@\s+"
        r"_DESK-SBOX-SLICE\s+@\s+"
        r"_DESK-SBOX-ALLOWANCE\s+@\s+"
        r"_DESK-SBOX-CAPACITY\s+@\s+"
        r"_DSBI-INST\s+@\s+"
        r"SBOX-CAPABILITY-BIND",
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

    # The capability starts after Desk itself is registered.
    interop = _definition(source, "_DESK-INTEROP-INIT")
    assert interop.index("_DINI-INST @ _DESK-REGISTRY @ CREG-INST+") < (
        interop.index("_DESK-SBOX-INIT")
    )


def test_the_sandbox_is_a_capability_not_a_desk_service() -> None:
    source = _source()

    assert "pure-compute" not in source
    assert "SBOX-JOB-SUBMIT" not in source
    trusted = _definition(source, "_DESK-TRUSTED-COMP")
    assert "SBOX-CAPABILITY-COMPONENT" in trusted


def test_desk_ticks_the_capability_after_the_bus_and_before_children() -> None:
    tick = _definition(_source(), "DESK-TICK-CB")

    assert tick.count("SBOX-CAPABILITY-TICK") == 1
    assert "SBOX-JOB-SERVICE-TICK" not in tick
    pump = tick.index("CBUS-PUMP")
    sandbox_tick = tick.index("SBOX-CAPABILITY-TICK")
    child_tick = tick.index("_DESK-HOST AHOST-TICK")
    assert pump < sandbox_tick < child_tick


def test_child_release_drains_its_runs_before_xio_and_instance_free() -> None:
    desk = _source()
    release = _definition(desk, "_DESK-HOST-RELEASE")

    sandbox_drain = release.index("SBOX-CAPABILITY-OWNER-DRAIN")
    xio_release = release.index("_DESK-XIO-RELEASE-OWNER")
    assert sandbox_drain < xio_release
    # The closing child's identity is its owner token.
    assert re.search(
        r"_DHR-INST\s+@\s+CINST\.ID\s+@\s+"
        r"_DHR-INST\s+@\s+CINST\.GENERATION\s+@\s+"
        r"_DESK-SANDBOX\s+@\s+SBOX-CAPABILITY-OWNER-DRAIN",
        release,
    )

    host = _source(HOST)
    close = _definition(host, "_AHOST-CLOSE-SLOT-FORCE")
    assert close.index("_AHC-RELEASE") < close.index("_AHC-FREE-INST")


def test_desk_unbinds_before_tables_context_and_practice() -> None:
    source = _source()
    fini = _definition(source, "_DESK-INTEROP-FINI-QUIESCED")
    sandbox_fini = _definition(source, "_DESK-SBOX-FINI")
    shutdown = _definition(source, "DESK-SHUTDOWN-CB")

    unbind = sandbox_fini.index("SBOX-CAPABILITY-UNBIND")
    unregister = sandbox_fini.index("CREG-INST-")
    free = sandbox_fini.index("CINST-FREE")
    assert unbind < unregister < free
    assert "0 _DESK-SANDBOX !" in sandbox_fini
    service_release = fini.index("_DESK-SBOX-FINI")
    table_release = fini.index("_DESK-SERVICE-TABLE-FINI")
    cancel_all = fini.index("CBUS-CANCEL-ALL")
    assert service_release < cancel_all
    assert service_release < table_release
    assert shutdown.index("_DSD-INTEROP-FINI") < shutdown.index(
        "_DSD-PRACTICE-FINI"
    )
    assert "SBOX-MODULE-OWNER-RELEASE" not in source
