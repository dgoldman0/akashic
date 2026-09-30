"""Cold complete Desk source and actual rich setup at the selected memory size."""

import json

import akashic_tui as packaging
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime


def test_complete_desk_cold_source_setup_fits_selected_external_memory():
    runtime = MegaForthRuntime(
        memory=create_one_core_address_space(
            external_size=packaging.DESKTOP_APT1_EXT_MEM_MIB << 20,
            hbw_size=1 << 20,
        ),
        execution_backend="native",
    )
    runtime.evaluate((packaging.MEGAPAD_ROOT / "kdos.f").read_bytes(), source_name="kdos.f")
    profile = packaging.PROFILES["desktop-apt1"]
    runtime.evaluate(packaging._with_userland_xmem_reserve(
        "ENTER-USERLAND\n", profile.general_xmem_reserve_bytes,
    ).encode(), source_name="desk-cold-userland")
    for name in ("networking.f", "rich-terminal.f"):
        runtime.evaluate((packaging.MEGAPAD_ROOT / name).read_bytes(),
                         source_name=name, step_budget=40_000_000)
    modules = packaging.dependency_order(profile.roots)
    chunks = packaging._linked_chunks(
        modules, profile.link_chunk_bytes, profile.audited_link_line_bytes,
    )
    for name, content in chunks.items():
        try:
            runtime.evaluate(content, source_name=name, step_budget=80_000_000)
        except Exception:
            memory = {
                word: runtime.memory.read64(runtime.find(word).body_address)
                for word in ("XMEM-HERE", "XMEM-LIMIT")
            }
            memory.update({
                word: runtime.find(word).implementation.value
                for word in ("_A1D-SCREEN-ARENA-U", "_A1D-RTAPT-OPS-U", "_A1D-RTAPT-COPY-U")
                if runtime.find(word) is not None
            })
            print("DESK SERIES STORAGE FAILURE " + json.dumps(memory), flush=True)
            raise AssertionError((name, memory, runtime.uart_output.decode(errors="replace")[-2000:])) from None

    def values(program):
        assert runtime.main_context.data.snapshot() == ()
        runtime.evaluate(program.encode(), source_name="desk-storage-proof", step_budget=80_000_000)
        result = runtime.main_context.data.snapshot()
        for _ in result:
            runtime.main_context.data.pop()
        assert runtime.main_context.returns.snapshot() == ()
        return result

    before = values("XMEM-HERE @ XMEM-LIMIT @")
    assert before[1] > before[0]
    assert values("_A1D-SETUP") == (0,)
    after = values("XMEM-HERE @ XMEM-LIMIT @")
    assert after[1] > after[0]
    assert values("_A1D-PHASE @ _A1D-PHASE-INSTALLED =") == ((1 << 64) - 1,)
    assert values("_A1D-SCREEN RTHP-VALID?") == ((1 << 64) - 1,)
    capacities = values("_A1D-RTAPT-OP-RECORDS _A1D-RTAPT-COPY-U _A1D-SCREEN-ARENA-U")
    assert capacities[0] == packaging.DESKTOP_APT1_MAX_OPERATIONS
    assert values("_A1D-UNINSTALL") == (0,)
    released = values("XMEM-HERE @ XMEM-LIMIT @")
    assert released == after  # Cold composition banks are session-lifetime storage.
    assert values("_A1D-PHASE @ _A1D-PHASE-COLD =") == ((1 << 64) - 1,)
    print("DESK SERIES STORAGE " + json.dumps({
        "external_mib": packaging.DESKTOP_APT1_EXT_MEM_MIB,
        "module_count": len(modules), "chunk_count": len(chunks),
        "before_setup": {"here": before[0], "limit": before[1], "remaining": before[1] - before[0]},
        "after_setup": {"here": after[0], "limit": after[1], "remaining": after[1] - after[0]},
        "operation_records": capacities[0], "copy_bytes": capacities[1],
        "producer_arena_bytes": capacities[2],
    }), flush=True)
