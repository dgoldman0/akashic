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


def test_desk_accepts_only_a_borrowed_sealed_owner_before_run() -> None:
    source = _source()
    setter = _definition(source, "DESK-SANDBOX-OWNER!")

    assert "REQUIRE sandbox-service.f" in source
    assert "_DESK-CURRENT-STATE @" in setter
    assert "SBOX-MODULE-OWNER-SEALED?" in setter
    assert re.search(
        r"_DESK-PENDING-(?:SBOX|SANDBOX)-OWNER\s+!",
        setter,
    )
    assert "ALLOCATE" not in setter
    assert "SBOX-MODULE-OWNER-RELEASE" not in setter


def test_desk_embeds_the_service_and_materializes_fixed_policy() -> None:
    source = _source()
    layout = source.split("CMP-LAYOUT-BEGIN", 1)[1].split(
        "CMP-LAYOUT-SIZE", 1
    )[0]

    assert re.search(
        r"_DESK-CURRENT-STATE\s+DESK-SBOX-JOB-SERVICE-SIZE"
        r"\s+CMP-FIELD:",
        layout,
    )
    init_call = source.index("DESK-SBOX-JOB-SERVICE-INIT")
    init_region = source[max(0, init_call - 5000) : init_call + 100]
    assert "SBOX-VALUE-LIMITS-BEGIN" in init_region
    assert "SBOX-VALUE-LIMIT!" in init_region
    assert "SBOX-VALUE-LIMITS-SEAL" in init_region
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
    service_release = fini.index("_DESK-SBOX-FINI")
    table_release = fini.index("_DESK-SERVICE-TABLE-FINI")
    assert service_release < table_release
    assert shutdown.index("_DSD-INTEROP-FINI") < shutdown.index(
        "_DSD-PRACTICE-FINI"
    )
    assert "SBOX-MODULE-OWNER-RELEASE" not in source
