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


def test_desk_gives_the_capability_module_storage_beside_its_files() -> None:
    source = _source()
    init = _definition(source, "_DESK-SBOX-INIT")

    register = init.index("_DESK-REGISTRY @ CREG-INST+")
    modules = init.index("SBOX-CAPABILITY-MODULES")
    publish = init.index("_DSBI-INST @ _DESK-SANDBOX !")
    assert register < modules < publish
    assert re.search(
        r"_DESK-REGISTRY\s+@\s+VFS-CUR\s+"
        r"_DESK-SBOX-CATALOG\$\s+_DESK-SBOX-PACK\$\s+"
        r"_DSBI-INST\s+@\s+SBOX-CAPABILITY-MODULES\s+"
        r"_DESK-SBOX-MODULES-STATUS\s+!",
        init,
    )
    # A store that cannot open leaves the sandbox running without modules.
    assert "EXIT" not in init[modules:publish]
    assert 'S" /sandbox-catalog.bin"' in source
    assert 'S" /sandbox-pack.bin"' in source


def test_desk_opens_the_sandbox_screens_as_ordinary_overlays() -> None:
    source = _source()
    surface = _source(DESK.parent / "sandbox-surface.f")

    assert "REQUIRE sandbox-surface.f" in source
    # Each screen is an ordinary UIDL document with a canonical list, with
    # no terminal or renderer of its own.
    assert "<uidl arrange=stack>" in surface
    assert "LST-NEW" in surface
    for word in ("APT1", "PT-", "RICH", "DRW-"):
        assert not re.search(rf"(?<![\w-]){re.escape(word)}", surface), word

    # Applets reach the capability through its intents.
    init = _definition(source, "_DESK-SBOX-INIT")
    assert init.index("CREG-TYPE-ENSURE") < init.index(
        "_DESK-INTENTS @ CINT-REGISTER-COMP"
    ) < init.index("CINST-NEW")

    # An open screen is modal like the launcher, and what the user chose is
    # carried out after the host's dispatch, not inside its callbacks.
    event = _definition(source, "DESK-EVENT-CB")
    assert event.index("_DESK-LAUNCHER-ID @ IF") < event.index(
        "_DESK-SBOX-OVERLAY-ID @ IF _DESK-SBOX-OVERLAY-EVENT EXIT THEN"
    )
    overlay_event = _definition(source, "_DESK-SBOX-OVERLAY-EVENT")
    assert overlay_event.index("AHOST-DISPATCH-KEY-ID") < overlay_event.index(
        "_DESK-SBOX-OVERLAY-SERVICE"
    )
    assert "SBOX-CAPABILITY-ANSWER" not in source

    # The prompt opens from the tick, after the capability has run.
    tick = _definition(source, "DESK-TICK-CB")
    assert tick.index("SBOX-CAPABILITY-TICK") < tick.index(
        "_DESK-SBOX-SURFACE-TICK"
    ) < tick.index("_DESK-HOST AHOST-TICK")
    surface_tick = _definition(source, "_DESK-SBOX-SURFACE-TICK")
    assert "PRM-ACTIVE?" in surface_tick
    assert "_DESK-LAUNCHER-ID @ IF EXIT THEN" in surface_tick

    # The prompt answers only the request it shows, and Refuse comes first.
    access = _definition(surface, "_SXS-ACCESS-SERVICE")
    assert access.index("SBOX-CAPABILITY-ASKING?") < access.index(
        "SBOX-CAPABILITY-ANSWER"
    )
    field = _definition(surface, "_SXS-ACCESS-FIELD")
    assert 'IF S" Allow" ELSE S" Refuse" THEN' in field

    # Alt+S opens the inspector.
    shortcut = _definition(source, "_DESK-SHORTCUT?")
    assert re.search(
        r"115\s+_DESK-ALT\?\s+IF\s+DROP\s+_DESK-SHOW-SBOX-MODULES", shortcut
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


def test_the_product_desktop_supplies_a_complete_sandbox_policy() -> None:
    import sys

    sys.path.insert(0, str(REPO_ROOT / "local_testing"))
    from akashic_tui import DESK_APPLETS, PROFILES, desktop_autoexec

    for rich in (False, True):
        autoexec = desktop_autoexec(DESK_APPLETS, rich=rich)
        policy = autoexec.index("_boot-sandbox\n")
        run = autoexec.index(
            "_boot-desktop-session-entry" if rich else "_boot-run-desktop"
        )
        assert policy < run
        assert "SBOX-LIMITS-BEGIN" in autoexec
        assert "SBOX-LIMITS-SEAL" in autoexec
        assert "DESK-SANDBOX-CONFIGURE" in autoexec
        # Every field of the limit record is bounded.
        for field in (
            "INSTRUCTION-BUDGET",
            "VALUE-OP-BUDGET",
            "COPY-BUDGET",
            "WALL-MS",
            "DEPTH",
            "BLOB-BYTES",
            "LIST-COUNT",
            "MAP-COUNT",
            "INPUT-NODES",
            "INPUT-BYTES",
            "OUTPUT-ARENA-NODES",
            "OUTPUT-ARENA-BYTES",
            "OUTPUT-RESULT-NODES",
            "OUTPUT-RESULT-BYTES",
        ):
            assert f"SBOX-LIMIT-{field} _boot-sandbox-limit" in autoexec, field

    # The focused journey proves the sandbox in Desk with the Agent alone,
    # and that Desk sleeps with it bound.
    sandbox = PROFILES["desktop-sandbox"]
    assert sandbox.idle_load_ceiling is not None
    assert "_boot-sandbox\n" in sandbox.autoexec
    assert "org.akashic.sandbox/test" in sandbox.autoexec

    # The narrow journey adds Probe, a second consumer reaching modules
    # through the sandbox's intents, and the Agent's install and invoke.
    modules = PROFILES["desktop-sandbox-modules"]
    assert modules.idle_load_ceiling is not None
    assert "_boot-sandbox\n" in modules.autoexec
    assert 'S" org.test.applet"' in modules.autoexec
    assert 'S" sandbox.authorize"' in modules.autoexec
    assert 'S" sandbox.invoke"' in modules.autoexec
    assert "org.akashic.sandbox/install" in modules.autoexec
    assert modules.autoexec.index("_sbp-desc DESK-QUEUE-LAUNCH") < (
        modules.autoexec.index("_boot-sandbox\n")
    )
