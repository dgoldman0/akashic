"""The rich Desktop profile is the shell-free base plus the shell."""
from dataclasses import replace
import json

import pytest
import akashic_tui as packaging

from akashic_tui import (
    COLD_SOURCE_LOADER_PATH,
    DESKTOP_APT1_RICH_TERMINAL,
    DESKTOP_APT1_RICH_TERMINAL_BASE,
    MEGAPAD_NETWORKING_BOOT_LINE,
    _with_megapad_rich_terminal,
    _with_rich_desktop_boot_progress,
)


def _boot():
    return ("ENTER-USERLAND\n" + MEGAPAD_NETWORKING_BOOT_LINE + "\n"
            + f"REQUIRE {COLD_SOURCE_LOADER_PATH}\n"
            + "_BOOT-COLD-SOURCE fixture.f\n")


def test_shell_free_base_has_no_shell_boot_declarations():
    profile = DESKTOP_APT1_RICH_TERMINAL_BASE
    assert profile.shell is False
    boot = _with_megapad_rich_terminal(_boot(), profile)
    assert "APT1-DESK-SHELL" not in boot
    assert _with_megapad_rich_terminal(boot, profile) == boot


def test_shell_selection_is_canonical_before_source_and_boot_progress():
    profile = replace(DESKTOP_APT1_RICH_TERMINAL_BASE, shell=True)
    boot = _with_megapad_rich_terminal(_boot(), profile)
    # Only the choice: the shell's storage grows from Desk's memory.
    declaration = "-1 CONSTANT APT1-DESK-SHELL-ENABLED\n"
    assert declaration in boot
    assert "SHELL-WORK-CAPACITY" not in boot and "SHELL-BANK-CAPACITY" not in boot
    assert boot.index(declaration) < boot.index(f"REQUIRE {COLD_SOURCE_LOADER_PATH}")
    assert _with_megapad_rich_terminal(boot, profile) == boot
    progressed = _with_rich_desktop_boot_progress(boot, profile, ("fixture.f",))
    assert progressed.index(declaration) < progressed.index("system modules ready")
    assert profile.retained_policy == DESKTOP_APT1_RICH_TERMINAL_BASE.retained_policy
    with pytest.raises(RuntimeError, match="shell selection"):
        _with_megapad_rich_terminal(boot, DESKTOP_APT1_RICH_TERMINAL_BASE)
    with pytest.raises(RuntimeError, match="shell selection"):
        _with_megapad_rich_terminal(boot + declaration, profile)


@pytest.mark.parametrize("bad", [1, 0, "yes", None])
def test_shell_selection_is_an_actual_bool(bad):
    with pytest.raises(TypeError):
        replace(DESKTOP_APT1_RICH_TERMINAL_BASE, shell=bad)


def test_shell_selection_adds_only_owned_shell_quotas_to_the_base():
    base = DESKTOP_APT1_RICH_TERMINAL_BASE
    selected = packaging.desktop_apt1_shell_profile()
    old, new = base.retained_policy, selected.retained_policy
    assert (packaging.DESKTOP_APT1_SHELL_MAX_ENTRIES,
            packaging.DESKTOP_APT1_SHELL_TEXT_BYTES) == (140, 25504)
    assert (packaging.DESKTOP_APT1_SHELL_CONTROL_LEDGER_BYTES,
            packaging.DESKTOP_APT1_SHELL_OP_BYTES,
            packaging.DESKTOP_APT1_SHELL_COPY_BYTES) == (18176, 17000, 90972)
    assert new.features == old.features | packaging.RetainedFeature.PANES | packaging.RetainedFeature.TASKBARS
    for name, delta in (('max_regions',143), ('max_objects',282),
                        ('max_operations_per_transaction',425), ('total_utf8_bytes',25504),
                        ('max_retained_transaction_bytes',77576), ('base_max_transaction_bytes',77576)):
        assert getattr(new, name) == getattr(old, name) + delta
    for name in ('guest_collection_native_bytes', 'guest_data_graphics_native_bytes',
                 'guest_status_field_native_bytes', 'guest_field_native_bytes',
                 'guest_rx_bytes', 'guest_tx_bytes', 'host_policy'):
        assert getattr(selected, name) == getattr(base, name)
    assert (base.shell, selected.shell) == (False, True)
    assert not old.features & (packaging.RetainedFeature.PANES | packaging.RetainedFeature.TASKBARS)
    with pytest.raises(ValueError, match='without the shell'):
        packaging.desktop_apt1_shell_profile(base=selected)


def test_rich_desktop_profile_selects_the_shell():
    # Changed draws with the acknowledged shell layout go out as retained
    # DELTAs, so the rich Desktop publishes its panes and taskbar by default.
    default = packaging.PROFILES['desktop-apt1']
    assert default.rich_terminal is DESKTOP_APT1_RICH_TERMINAL
    assert DESKTOP_APT1_RICH_TERMINAL == packaging.desktop_apt1_shell_profile()
    assert 'desktop-apt1-shell' not in packaging.PROFILES
    boot = _with_megapad_rich_terminal(_boot(), default.rich_terminal)
    assert "-1 CONSTANT APT1-DESK-SHELL-ENABLED\n" in boot


def test_shell_selection_grows_atomic_payload_and_transport_for_smaller_app_banks():
    base = replace(DESKTOP_APT1_RICH_TERMINAL_BASE,
                   guest_collection_native_bytes=80, guest_data_graphics_native_bytes=240,
                   guest_status_field_native_bytes=72, guest_field_native_bytes=192,
                   guest_tx_bytes=4136,
                   retained_policy=replace(DESKTOP_APT1_RICH_TERMINAL_BASE.retained_policy,
                                           client_to_terminal_max_payload=4096,
                                           max_samples_per_append=128))
    selected = packaging.desktop_apt1_shell_profile(base=base)
    assert selected.retained_policy.client_to_terminal_max_payload == 25608
    assert selected.guest_tx_bytes == 25648
    with pytest.raises(ValueError, match='selected native object'):
        replace(base, shell=True)


@pytest.mark.parametrize('change', [
    {'max_objects': (1 << 32) - 1},
    {'max_operations_per_transaction': (1 << 32) - 1},
    {'base_max_transaction_bytes': (1 << 32) - 1},
])
def test_shell_selection_rejects_overflow_instead_of_shrinking_existing_quotas(change):
    base = replace(DESKTOP_APT1_RICH_TERMINAL_BASE,
                   retained_policy=replace(DESKTOP_APT1_RICH_TERMINAL_BASE.retained_policy, **change))
    with pytest.raises(ValueError):
        packaging.desktop_apt1_shell_profile(base=base)


@pytest.mark.parametrize('shell_enabled', [False, True])
def test_shell_opt_in_cold_setup_unwind_and_foreign_observer_preservation(shell_enabled):
    """Exercise real constructors, with only INSTALL refusal injected by the test."""
    from simulator.platform import create_one_core_address_space
    from simulator.runtime import MegaForthRuntime

    runtime = MegaForthRuntime(
        memory=create_one_core_address_space(
            external_size=packaging.DESKTOP_APT1_EXT_MEM_MIB << 20,
            hbw_size=1 << 20,
        ), execution_backend="native",
    )
    runtime.evaluate((packaging.MEGAPAD_ROOT / "kdos.f").read_bytes(), source_name="kdos.f")
    profile = packaging.PROFILES["desktop-apt1"]
    runtime.evaluate(packaging._with_userland_xmem_reserve(
        "ENTER-USERLAND\n", profile.general_xmem_reserve_bytes,
    ).encode(), source_name="shell-userland")
    for name in ("networking.f", "rich-terminal.f"):
        runtime.evaluate((packaging.MEGAPAD_ROOT / name).read_bytes(),
                         source_name=name, step_budget=40_000_000)
    if shell_enabled:
        selected = packaging.desktop_apt1_shell_profile()
        boot = _with_megapad_rich_terminal(_boot(), selected)
        declarations = '\n'.join(line for line in boot.splitlines() if ' CONSTANT APT1-DESK-' in line)
        runtime.evaluate(declarations.encode(), source_name="shell-test-bounds")
    refusal = b"""
' RSHSP-INSTALL CONSTANT _SHT-REAL-INSTALL
VARIABLE _SHT-REFUSE-INSTALL
0 _SHT-REFUSE-INSTALL !
: RSHSP-INSTALL
    _SHT-REFUSE-INSTALL @ IF DROP RTE-S-UNAVAILABLE
    ELSE _SHT-REAL-INSTALL EXECUTE THEN ;
: _SHT-FOREIGN-DRAW DROP 2DROP ;
"""
    marker = b"PROVIDED akashic-tui-desk-apt1"
    injection_count = 0
    for name, content in packaging._linked_chunks(
        packaging.dependency_order(profile.roots),
        profile.link_chunk_bytes, profile.audited_link_line_bytes,
    ).items():
        injection_count += content.count(marker)
        content = content.replace(marker, refusal + marker)
        try:
            runtime.evaluate(content, source_name=name, step_budget=80_000_000)
        except Exception as error:
            raise AssertionError((name, repr(error), runtime.uart_output.decode(errors="replace")[-3000:])) from None
    assert injection_count == 1

    def values(program):
        assert runtime.main_context.data.snapshot() == ()
        runtime.evaluate(program.encode(), source_name="shell-lifecycle-proof", step_budget=80_000_000)
        result = runtime.main_context.data.snapshot()
        for _ in result:
            runtime.main_context.data.pop()
        assert runtime.main_context.returns.snapshot() == ()
        return result

    true = (1 << 64) - 1
    # The first setup takes the engine's first banks from the system heap;
    # every later setup and release reuses those blocks, so the heap's high
    # water stays where one cycle left it and nothing stays held.
    assert values('_A1D-SETUP _A1D-UNINSTALL') == (0, 0)
    assert values('_A1D-MEMORY MSRC-HELD@') == (0,)
    before = values("XMEM-HERE @ XMEM-LIMIT @")
    assert before[1] > before[0]
    # The screen producer starts from its smallest arena and grows it from
    # the memory source as draws need.
    assert values('''
        _A1D-UIDL-BINDINGS RTHP-FIRST-CAPACITIES RTHP-STORAGE-BYTES
        _A1D-SCREEN-FIRST-U =
    ''') == (true,)
    print('DESK SHELL PROVIDER STORAGE ' + json.dumps({
        'shell_enabled': shell_enabled, 'free_bytes': before[1] - before[0],
    }), flush=True)
    if not shell_enabled:
        assert values('_A1D-SETUP _A1D-UNINSTALL') == (0, 0)
        assert values('XMEM-HERE @ XMEM-LIMIT @') == before
        return
    setup = values("_A1D-SETUP")
    assert setup == (0,), (setup, values(
        "_A1D-PHASE @ _A1D-SHELL-PHASE @ "
        "_A1D-SCREEN RTHP-VALID? _A1D-SHELL-SOURCE SHSN-VALID? "
        "_A1D-SHELL-FACADE RTE-SHELL-VALID? _A1D-SHELL-PRODUCER RSHSP-VALID? "
        "_SHT-REFUSE-INSTALL @ _A1D-SCREEN _RTHP.PHASE @ "
        "_A1D-SHELL-PRODUCER _RSHSP.EXTENSION _A1D-SCREEN _RTHP-EXTENSION?"))
    assert values("_A1D-SHELL-PHASE @") == (5,)
    # The shell source and producer own their first, smallest storage from
    # Desk's memory source and grow it as models and candidates need.
    assert values("_A1D-SHELL-SOURCE _SHSN.MEMORY @ _A1D-MEMORY = "
                  "_A1D-SHELL-SOURCE _SHSN.A-U @ SHM-HEADER-SIZE = "
                  "_A1D-SHELL-SOURCE-A @ _A1D-SHELL-SOURCE-B @") == (true, true, 0, 0)
    assert values("_A1D-SHELL-PRODUCER _RSHSP.MEMORY @ _A1D-MEMORY = "
                  "_A1D-SHELL-PRODUCER _RSHSP.WORK-U @ RSHSP-FIRST-WORK-BYTES = "
                  "_A1D-SHELL-PRODUCER _RSHSP.A-U @ RSHSP-FIRST-BANK-BYTES = "
                  "_A1D-SHELL-WORK @ _A1D-SHELL-A @ _A1D-SHELL-B @") == (
        true, true, true, 0, 0, 0)
    assert values("_A1D-OWNER _APTAS.CONTROL-CONTEXT @ _A1D-SHELL-PRODUCER =") == (true,)
    assert values("_A1D-OWNER _APTAS.CONTROL-XT @ ' RSHSP-CONTROL-TARGET@ =") == (true,)
    assert values("_A1D-SCREEN _RTHP.EXTENSION @ 0<>") == (true,)
    assert values("_A1D-UNINSTALL") == (0,)
    assert values("_A1D-SHELL-PHASE @ _SHSN-INSTALLED @ _A1D-SCREEN _RTHP.EXTENSION @") == (0, 0, 0)
    assert values("_A1D-MEMORY MSRC-HELD@") == (0,)

    # SHSN-INIT succeeds; foreign ownership refuses INSTALL at shell phase2.
    values("' _SHT-FOREIGN-DRAW 73 ASHELL-DRAW-OBSERVE!")
    assert values("_A1D-SETUP SCB-S-INVALID = _A1D-SHELL-PHASE @") == (true, 2)
    assert values("_A1D-UNINSTALL") == (0,)
    assert values("ASHELL-DRAW-OBSERVER@ 73 = SWAP ' _SHT-FOREIGN-DRAW =") == (true, true)
    assert values("_SHSN-INSTALLED @ _A1D-SHELL-PHASE @") == (0, 0)
    values("0 0 ASHELL-DRAW-OBSERVE!")
    assert values("_A1D-SETUP _A1D-UNINSTALL") == (0, 0)

    # Real RSHSP-INIT succeeds; a refused INSTALL must not leave an extension.
    values("-1 _SHT-REFUSE-INSTALL !")
    assert values("_A1D-SETUP SCB-S-INVALID = _A1D-SHELL-PHASE @") == (true, 4)
    assert values("_A1D-SCREEN _RTHP.EXTENSION @") == (0,)
    assert values("_SHSN-INSTALLED @ _A1D-SHELL-SOURCE =") == (true,)
    assert values("_A1D-SHELL-PRODUCER _RSHSP.MEMORY @ _A1D-MEMORY =") == (true,)
    assert values("_A1D-UNINSTALL") == (0,)
    assert values("_A1D-MEMORY MSRC-HELD@") == (0,)
    assert values("ASHELL-DRAW-OBSERVER@ AHOST-SHELL-OBSERVER@") == (0, 0, 0, 0)
    assert values("_SHSN-INSTALLED @ _A1D-SHELL-PHASE @") == (0, 0)
    values("0 _SHT-REFUSE-INSTALL !")
    assert values("_A1D-SETUP _A1D-UNINSTALL") == (0, 0)
    after = values("XMEM-HERE @ XMEM-LIMIT @")
    assert after == before
    print("DESK SHELL STORAGE " + json.dumps({
        "external_mib": packaging.DESKTOP_APT1_EXT_MEM_MIB,
        "xmem_here": after[0], "xmem_limit": after[1],
        "remaining": after[1] - after[0],
    }), flush=True)
