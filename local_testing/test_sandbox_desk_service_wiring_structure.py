#!/usr/bin/env python3
"""Static contracts for Desk's borrowed transient sandbox service wiring."""

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


def test_desk_accepts_only_a_measured_borrowed_configuration_before_run() -> None:
    source = _source()
    configure = _definition(source, "DESK-SANDBOX-CONFIGURE")

    assert "REQUIRE sandbox-service.f" in source
    assert _stack_effect(
        source,
        "DESK-SANDBOX-CONFIGURE",
    ) == "owner|0 capacity -- status"
    assert "_DESK-CURRENT-STATE @" in configure
    assert "SBOX-MODULE-OWNER-SEALED?" in configure
    assert "DESK-SBOX-JOB-SERVICE-MEASURE" in configure
    assert "_DESK-PENDING-SBOX-OWNER !" in configure
    assert "_DESK-PENDING-SBOX-CAPACITY !" in configure
    assert not re.search(
        r"^:\s+DESK-SANDBOX-OWNER!(?:\s|$)",
        source,
        re.MULTILINE,
    )
    assert "ALLOCATE" not in configure
    assert "SBOX-MODULE-OWNER-RELEASE" not in configure


def test_desk_owns_a_dynamic_measured_service_and_materializes_policy() -> None:
    source = _source()
    layout = source.split("CMP-LAYOUT-BEGIN", 1)[1].split(
        "CMP-LAYOUT-SIZE", 1
    )[0]

    assert "DESK-SBOX-JOB-SERVICE-SIZE" not in source
    assert not re.search(
        r"CMP-FIELD:\s+_DESK-SANDBOX\b",
        layout,
    )
    assert re.search(
        r"_DESK-CURRENT-STATE\s+CMP-CELL:\s+_DESK-SANDBOX\b",
        layout,
    )
    assert re.search(
        r"_DESK-CURRENT-STATE\s+CMP-CELL:\s+_DESK-SANDBOX-U\b",
        layout,
    )
    assert "_DESK-PENDING-SBOX-CAPACITY @" in source
    assert "_DESK-SBOX-CAPACITY !" in source
    desk_init = _definition(source, "DESK-INIT-CB")
    recovery = desk_init.split("DESK-RECOVERY? IF", 1)[1].split(
        "THEN", 1
    )[0]
    assert "0 _DESK-SBOX-OWNER !" in recovery
    assert "0 _DESK-SBOX-CAPACITY !" in recovery

    init = _definition(source, "_DESK-SBOX-INIT")
    assert "DESK-SBOX-JOB-SERVICE-MEASURE" in init
    assert "ALLOCATE" in init
    assert "SBOX-VALUE-LIMITS-BEGIN" in source
    assert "SBOX-VALUE-LIMIT!" in source
    assert "SBOX-VALUE-LIMITS-SEAL" in source
    assert re.search(
        r"_DESK-SBOX-CAPACITY\s+@\s+"
        r"_DESK-SANDBOX\s+@\s+"
        r"_DESK-SANDBOX-U\s+@\s+"
        r"DESK-SBOX-JOB-SERVICE-INIT",
        init,
    )
    for budget in (
        "INSTRUCTION",
        "VALUE-OP",
        "COPY",
        "SLICE",
    ):
        assert re.search(
            rf"CONSTANT\s+_DESK-(?:SBOX|SANDBOX)-{budget}"
            r"(?:-BUDGET|-STEPS)?\b",
            source,
        ), budget


def test_desk_publishes_only_the_exact_pure_compute_service_id() -> None:
    source = _source()
    setup = _definition(source, "_DESK-SERVICE-TABLE-SETUP")

    exact_id = 'S" org.akashic.sandbox.pure-compute"'
    assert source.count(exact_id) == 1
    assert exact_id in setup
    after_id = setup.split(exact_id, 1)[1]
    assert "[']" in after_id
    assert "_DESK-SERVICE+" in after_id


def test_desk_advances_one_sandbox_slice_before_child_ticks() -> None:
    tick = _definition(_source(), "DESK-TICK-CB")

    assert tick.count("DESK-SBOX-JOB-SERVICE-TICK") == 1
    sandbox_tick = tick.index("DESK-SBOX-JOB-SERVICE-TICK")
    child_tick = tick.index("_DESK-HOST AHOST-TICK")
    assert sandbox_tick < child_tick


def test_child_release_drains_sandbox_work_before_xio_and_instance_free() -> None:
    desk = _source()
    release = _definition(desk, "_DESK-HOST-RELEASE")

    sandbox_drain = release.index("DESK-SBOX-JOB-OWNER-DRAIN")
    xio_release = release.index("_DESK-XIO-RELEASE-OWNER")
    assert sandbox_drain < xio_release

    host = _source(HOST)
    close = _definition(host, "_AHOST-CLOSE-SLOT-FORCE")
    assert close.index("_AHC-RELEASE") < close.index("_AHC-FREE-INST")


def test_desk_releases_service_before_tables_context_and_practice() -> None:
    source = _source()
    fini = _definition(source, "_DESK-INTEROP-FINI-QUIESCED")
    sandbox_fini = _definition(source, "_DESK-SBOX-FINI")
    shutdown = _definition(source, "DESK-SHUTDOWN-CB")

    assert "DESK-SBOX-JOB-SERVICE-RELEASE" in sandbox_fini
    assert re.search(
        r"_DESK-SANDBOX\s+@\s+DUP\s+0=\s+IF",
        sandbox_fini,
    )
    assert "?DUP 0=" not in sandbox_fini
    assert re.search(
        r"_DESK-SANDBOX\s+@\s+"
        r"_DESK-SANDBOX-U\s+@\s+"
        r"DESK-SBOX-JOB-SERVICE-RELEASE",
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
