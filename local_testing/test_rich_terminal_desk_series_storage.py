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
                for word in ("_A1D-SCREEN-FIRST-U",)
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

    # Desk runs in normal mode.
    assert values("CHK-EVERY-FRAME @") == (0,)
    before = values("XMEM-HERE @ XMEM-LIMIT @")
    assert before[1] > before[0]
    assert values("_A1D-SETUP") == (0,)
    # RUHA's record and its document records lie in Desk's block, and its
    # banks and work spans in one block it took from Desk's memory source.
    # A proof that accepts only ranges inside one of those two blocks
    # therefore proves every span RUHA proves: the range from its lowest
    # span to the end of its highest first, then each block.
    assert values("_A1D-RUHA _RUHA-A.MEMORY @ _A1D-MEMORY =") == ((1 << 64) - 1,)
    assert values(
        "VARIABLE _RBLK-N  0 _RBLK-N ! "
        ": _RBLK-WITHIN? ( a u base bytes -- flag ) >R >R "
        "OVER R@ U< IF R> R> 2DROP 2DROP 0 EXIT THEN + R> R> + U> 0= ; "
        ": _RBLK-PROOF ( a u -- flag ) 1 _RBLK-N +! "
        "2DUP _A1D-RUHA _A1D-RUHA-BLOCK-U _RBLK-WITHIN? IF 2DROP -1 EXIT THEN "
        "_A1D-RUHA _RUHA-A.BLOCK-A @ _A1D-RUHA _RUHA-A.BLOCK-U @ _RBLK-WITHIN? ; "
        "_A1D-RUHA ' _RBLK-PROOF _RUHA-SAFE-PROVE? _RBLK-N @ 3 U> 0="
    ) == ((1 << 64) - 1,) * 2
    after = values("XMEM-HERE @ XMEM-LIMIT @")
    assert after[1] > after[0]
    assert values("_A1D-PHASE @ _A1D-PHASE-INSTALLED =") == ((1 << 64) - 1,)
    assert values("_A1D-SCREEN RTHP-VALID?") == ((1 << 64) - 1,)
    # The engine starts with one record in each working bank, taken from
    # Desk's memory source, and grows from there as frames need.
    engine = values("_A1D-RTAPT-ENGINE DUP _RTAPT-E.OP-CAP @ OVER _RTAPT-E.COPY-U @ "
                    "ROT DUP _RTAPT-E.CONTROL-LEDGER-CAP @ SWAP _RTAPT-E.MEMORY @ _A1D-MEMORY =")
    assert engine == (1, 8, 1, (1 << 64) - 1)
    # The screen producer owns its first, smallest arena and grows it from
    # the same memory source as draws need.
    assert values("_A1D-SCREEN _RTHP.MEMORY @ _A1D-MEMORY = "
                  "_A1D-SCREEN _RTHP.ARENA-U @ _A1D-SCREEN-FIRST-U = "
                  "_A1D-SCREEN-FIRST @") == ((1 << 64) - 1, (1 << 64) - 1, 0)
    capacities = values("_A1D-MEMORY MSRC-HELD@ _A1D-SCREEN-FIRST-U "
                        "RTAPT-OP-SIZE 8 + RTAPT-CONTROL-LEDGER-SIZE + "
                        "_A1D-RUHA _RUHA-A.BLOCK-U @")
    assert capacities[0] == capacities[1] + capacities[2] + capacities[3]
    assert values("_A1D-UNINSTALL") == (0,)
    # Everything taken from the memory source is given back.
    assert values("_A1D-MEMORY MSRC-HELD@") == (0,)
    released = values("XMEM-HERE @ XMEM-LIMIT @")
    assert released == after
    assert values("_A1D-PHASE @ _A1D-PHASE-COLD =") == ((1 << 64) - 1,)
    print("DESK SERIES STORAGE " + json.dumps({
        "external_mib": packaging.DESKTOP_APT1_EXT_MEM_MIB,
        "module_count": len(modules), "chunk_count": len(chunks),
        "before_setup": {"here": before[0], "limit": before[1], "remaining": before[1] - before[0]},
        "after_setup": {"here": after[0], "limit": after[1], "remaining": after[1] - after[0]},
        "memory_source_held": capacities[0],
        "producer_first_arena_bytes": capacities[1],
        "snapshot_adapter_block_bytes": capacities[3],
    }), flush=True)
