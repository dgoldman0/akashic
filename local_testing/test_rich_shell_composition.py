"""Explicit shell composition bounds preserve the qualified default profile."""
from dataclasses import replace
import json

import pytest
import akashic_tui as packaging

from akashic_tui import (
    COLD_SOURCE_LOADER_PATH,
    DESKTOP_APT1_RICH_TERMINAL,
    MEGAPAD_NETWORKING_BOOT_LINE,
    _with_megapad_rich_terminal,
    _with_rich_desktop_boot_progress,
)


def _boot():
    return ("ENTER-USERLAND\n" + MEGAPAD_NETWORKING_BOOT_LINE + "\n"
            + f"REQUIRE {COLD_SOURCE_LOADER_PATH}\n"
            + "_BOOT-COLD-SOURCE fixture.f\n")


def test_shell_default_has_no_allocating_boot_declarations():
    profile = DESKTOP_APT1_RICH_TERMINAL
    assert (profile.guest_shell_work_bytes, profile.guest_shell_bank_bytes) == (0, 0)
    boot = _with_megapad_rich_terminal(_boot(), profile)
    assert "APT1-DESK-SHELL" not in boot
    assert _with_megapad_rich_terminal(boot, profile) == boot


def test_shell_explicit_bounds_are_canonical_before_source_and_boot_progress():
    profile = replace(DESKTOP_APT1_RICH_TERMINAL,
                      guest_shell_work_bytes=8192, guest_shell_bank_bytes=4096)
    boot = _with_megapad_rich_terminal(_boot(), profile)
    declarations = ("-1 CONSTANT APT1-DESK-SHELL-ENABLED\n"
                    "8192 CONSTANT APT1-DESK-SHELL-WORK-CAPACITY\n"
                    "4096 CONSTANT APT1-DESK-SHELL-BANK-CAPACITY\n")
    assert declarations in boot
    assert boot.index(declarations) < boot.index(f"REQUIRE {COLD_SOURCE_LOADER_PATH}")
    assert _with_megapad_rich_terminal(boot, profile) == boot
    progressed = _with_rich_desktop_boot_progress(boot, profile, ("fixture.f",))
    assert progressed.index(declarations) < progressed.index("system modules ready")
    assert profile.retained_policy == DESKTOP_APT1_RICH_TERMINAL.retained_policy
    with pytest.raises(RuntimeError, match="shell bounds"):
        _with_megapad_rich_terminal(boot, DESKTOP_APT1_RICH_TERMINAL)
    with pytest.raises(RuntimeError, match="shell bounds"):
        _with_megapad_rich_terminal(
            boot + "-1 CONSTANT APT1-DESK-SHELL-ENABLED\n", profile)
    with pytest.raises(RuntimeError, match="exactly once"):
        _with_megapad_rich_terminal(boot.replace("8192 CONSTANT APT1-DESK-SHELL",
                                                "8191 CONSTANT APT1-DESK-SHELL"), profile)


@pytest.mark.parametrize("work,bank", [
    (8, 0), (0, 8), (-8, 8), (8, -8), (8, 7), (7, 8),
    (0x100000000, 8), (8, 0x100000000),
])
def test_shell_partial_unaligned_or_overflowing_bounds_are_rejected(work, bank):
    with pytest.raises(ValueError):
        replace(DESKTOP_APT1_RICH_TERMINAL,
                guest_shell_work_bytes=work, guest_shell_bank_bytes=bank)


@pytest.mark.parametrize("bad", [True, 8.0, "8"])
@pytest.mark.parametrize("field", ["guest_shell_work_bytes", "guest_shell_bank_bytes"])
def test_shell_bounds_require_actual_integers(field, bad):
    with pytest.raises(TypeError):
        replace(DESKTOP_APT1_RICH_TERMINAL, **{field: bad})


def test_shell_opt_in_cold_setup_unwind_and_foreign_observer_preservation():
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
    # These are experimental test ceilings, not enabled shipping defaults.
    work_bytes, bank_bytes = 8 << 20, 4 << 20
    runtime.evaluate((
        "-1 CONSTANT APT1-DESK-SHELL-ENABLED\n"
        f"{work_bytes} CONSTANT APT1-DESK-SHELL-WORK-CAPACITY\n"
        f"{bank_bytes} CONSTANT APT1-DESK-SHELL-BANK-CAPACITY\n"
    ).encode(), source_name="shell-test-bounds")
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
    before = values("XMEM-HERE @ XMEM-LIMIT @")
    assert before[1] > before[0]
    assert values("_A1D-SHELL-SOURCE-U _A1D-SHELL-MAX-ENTRIES _A1D-SHELL-MAX-TEXT") == (49152, 140, 25504)
    setup = values("_A1D-SETUP")
    assert setup == (0,), (setup, values(
        "_A1D-PHASE @ _A1D-SHELL-PHASE @ "
        "_A1D-SCREEN RTHP-VALID? _A1D-SHELL-SOURCE SHSN-VALID? "
        "_A1D-SHELL-FACADE RTE-SHELL-VALID? _A1D-SHELL-PRODUCER RSHSP-VALID? "
        "_SHT-REFUSE-INSTALL @ _A1D-SCREEN _RTHP.PHASE @ "
        "_A1D-SHELL-PRODUCER _RSHSP.EXTENSION _A1D-SCREEN _RTHP-EXTENSION?"))
    assert values("_A1D-SHELL-PHASE @") == (5,)
    assert values("_A1D-OWNER _APTAS.CONTROL-CONTEXT @ _A1D-SHELL-PRODUCER =") == (true,)
    assert values("_A1D-OWNER _APTAS.CONTROL-XT @ ' RSHSP-CONTROL-TARGET@ =") == (true,)
    assert values("_A1D-SCREEN _RTHP.EXTENSION @ 0<>") == (true,)
    assert values("_A1D-UNINSTALL") == (0,)
    assert values("_A1D-SHELL-PHASE @ _SHSN-INSTALLED @ _A1D-SCREEN _RTHP.EXTENSION @") == (0, 0, 0)

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
    assert values("_A1D-UNINSTALL") == (0,)
    assert values("ASHELL-DRAW-OBSERVER@ AHOST-SHELL-OBSERVER@") == (0, 0, 0, 0)
    assert values("_SHSN-INSTALLED @ _A1D-SHELL-PHASE @") == (0, 0)
    values("0 _SHT-REFUSE-INSTALL !")
    assert values("_A1D-SETUP _A1D-UNINSTALL") == (0, 0)
    after = values("XMEM-HERE @ XMEM-LIMIT @")
    assert after == before
    print("DESK SHELL STORAGE " + json.dumps({
        "external_mib": packaging.DESKTOP_APT1_EXT_MEM_MIB,
        "work_capacity": work_bytes, "candidate_bank_capacity": bank_bytes,
        "source_bank_capacity": 49152,
        "xmem_here": after[0], "xmem_limit": after[1],
        "remaining": after[1] - after[0],
    }), flush=True)
