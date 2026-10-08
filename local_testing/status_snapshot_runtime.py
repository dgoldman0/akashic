"""Admitted source-runtime execution of the actual UIDL snapshot closure.

The emulator oracle's guest-instruction ceiling slows the timing-correct
scheduler substantially. This helper uses the same real Forth dependency
closure and native source runtime; CSS parsing alone is replaced by the
existing no-style ABI fixture. Each invocation owns a fresh address space.
"""

from test_uidl_collection_snapshot import (
    MEGAPAD_ROOT, SOURCE_PATHS, STYLE_ABI_STUBS, _load_forth_lines,
)
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime


def run_status_forth(lines: list[str], max_steps: int = 20_000_000) -> str:
    runtime = MegaForthRuntime(
        memory=create_one_core_address_space(external_size=128 << 20),
        execution_backend="native",
    )
    runtime.evaluate((MEGAPAD_ROOT / "kdos.f").read_bytes(), source_name="kdos.f")
    runtime.evaluate(b"ENTER-USERLAND", source_name="status-snapshot-init")
    for path in SOURCE_PATHS:
        prefix = []
        if path.name == "data-graphics.f" and path.parent.name == "widgets":
            prefix.append(": TUI-RESOLVE-COLOR ( r g b -- index ) 3DROP 0 ;")
        if path.name == "uidl-tui.f":
            prefix.extend(STYLE_ABI_STUBS)
        runtime.evaluate("\n".join(prefix + _load_forth_lines(path)).encode(),
                         source_name=str(path), step_budget=20_000_000)
    runtime.drain_uart_output()
    try:
        runtime.evaluate("\n".join(lines).encode(), source_name="status-snapshot-checks",
                         step_budget=max_steps)
    except Exception as error:
        raise AssertionError(runtime.uart_output.decode(errors="replace")[-18000:]) from error
    return runtime.drain_uart_output().decode(errors="replace")
