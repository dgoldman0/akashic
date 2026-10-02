#!/usr/bin/env python3
"""Run focused Forth programs on the native runtime over KDOS and a closure.

Each run builds a fresh machine: KDOS, the roots' REQUIRE closure in
canonical load order, an optional prelude, then the program.  Nothing
carries over from one run to the next.  The closure is resolved from the
modules' own ``REQUIRE`` markers, so a suite names only its roots.

A suite whose closure takes too long to load for every check can instead
load one machine with :meth:`NativeForth.shared` and run each check in it.
Its checks must then reset any state they rely on.
"""

from __future__ import annotations

import os
import sys
import time
from pathlib import Path

from forth_dependencies import dependency_order


AKASHIC_ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = AKASHIC_ROOT / "akashic"
PROJECT_ROOT = AKASHIC_ROOT.parent
MEGAPAD_ROOT = Path(os.environ.get("MEGAPAD_ROOT", PROJECT_ROOT / "megapad"))

sys.path.insert(0, str(MEGAPAD_ROOT))

from simulator.errors import SimulatorError  # noqa: E402
from simulator.platform import create_one_core_address_space  # noqa: E402
from simulator.runtime import MegaForthRuntime  # noqa: E402
from simulator.stacks import StackError  # noqa: E402


def module_source(path: Path) -> bytes:
    """Return a module's text without its REQUIRE and PROVIDED markers."""

    kept = [
        line for line in path.read_text(encoding="utf-8").splitlines()
        if not line.lstrip().startswith(("REQUIRE ", "PROVIDED "))
    ]
    return ("\n".join(kept) + "\n").encode()


def _evaluate_program(runtime: MegaForthRuntime, lines: list[str], max_steps: int) -> bytes:
    """Run ``lines`` and return the bytes printed, then any error's message.

    A runtime error ends the program; its message follows the output, so a
    check that looks for the program's results fails and shows why.
    """

    error_text = b""
    try:
        runtime.evaluate(("\n".join(lines) + "\n").encode(),
                         source_name="program", step_budget=max_steps)
    except (SimulatorError, StackError) as error:
        error_text = f"\n?? {type(error).__name__}: {error}\n".encode()
    return runtime.drain_uart_output() + error_text


class NativeForth:
    """One suite's roots, prelude and machine.

    ``system_modules`` are MegaPad system modules loaded after
    ENTER-USERLAND, as a boot that selects them loads them.  ``prelude``
    lines run after the closure in every machine; suites use them for
    shared fixtures.  ``replace`` maps a closure module to lines loaded in
    its place, for a suite that stands in for one dependency.  ``load_steps``
    bounds everything loaded before the program.  With ``live_clock``, MS@
    follows host time, as the emulator's clock followed its cycles;
    otherwise it stays at zero.  ``external_size`` defaults to the canonical
    128 MiB of XMEM: KDOS sizes its dictionary index from free XMEM, and on a
    much smaller machine a large closure fills the index, after which every
    new definition scans the whole table.
    """

    def __init__(
        self,
        roots: tuple[str, ...],
        *,
        system_modules: tuple[str, ...] = (),
        prelude: tuple[str, ...] = (),
        replace: dict[str, tuple[str, ...]] | None = None,
        external_size: int = 128 << 20,
        load_steps: int = 800_000_000,
        live_clock: bool = False,
    ) -> None:
        self.roots = roots
        self.system_modules = system_modules
        self.prelude = prelude
        self.replace = dict(replace or {})
        self.external_size = external_size
        self.load_steps = load_steps
        self.live_clock = live_clock

    @property
    def modules(self) -> tuple[str, ...]:
        return dependency_order(SOURCE_ROOT, self.roots)

    def machine(self, *, cols: int = 80, rows: int = 24) -> MegaForthRuntime:
        """Return a fresh machine with KDOS, the closure and the prelude."""

        runtime = MegaForthRuntime(
            memory=create_one_core_address_space(
                external_size=self.external_size, hbw_size=1 << 20,
            ),
            execution_backend="native",
        )
        if self.live_clock:
            runtime.rtc.bind_monotonic_clock(time.monotonic_ns)
        runtime.set_terminal_geometry(cols, rows)
        runtime.consume_terminal_resized()
        sources = [("kdos.f", (MEGAPAD_ROOT / "kdos.f").read_bytes()),
                   ("userland", b"ENTER-USERLAND\n")]
        sources += [(name, (MEGAPAD_ROOT / name).read_bytes())
                    for name in self.system_modules]
        for module in self.modules:
            if module in self.replace:
                source = ("\n".join(self.replace[module]) + "\n").encode()
            else:
                source = module_source(SOURCE_ROOT / module)
            sources.append((module, source))
        if self.prelude:
            sources.append(("prelude", ("\n".join(self.prelude) + "\n").encode()))
        remaining = self.load_steps
        for name, source in sources:
            try:
                result = runtime.evaluate(source, source_name=name,
                                          step_budget=remaining)
            except (SimulatorError, StackError) as error:
                tail = runtime.uart_output.decode("utf-8", errors="replace")[-2000:]
                raise AssertionError(f"loading {name} failed: {error}\n{tail}") from error
            remaining -= result.semantic_steps
        runtime.drain_uart_output()
        return runtime

    def run(
        self,
        lines: list[str],
        max_steps: int,
        *,
        cols: int = 80,
        rows: int = 24,
        keys: bytes = b"",
        host_resize: tuple[int, int] | None = None,
    ) -> bytes:
        """Run ``lines`` on a fresh machine and return the bytes it printed.

        ``keys`` are queued as terminal input before the program starts.
        ``host_resize`` resizes the terminal from the host side first, which
        sets the guest's RESIZED flag.
        """

        runtime = self.machine(cols=cols, rows=rows)
        if host_resize is not None:
            runtime.set_terminal_geometry(*host_resize)
        if keys:
            runtime.inject_uart_input(keys)
        return _evaluate_program(runtime, lines, max_steps)

    def shared(self, *, cols: int = 80, rows: int = 24) -> SharedMachine:
        """Load one machine that runs every check of a suite in turn."""

        return SharedMachine(self.machine(cols=cols, rows=rows))


class SharedMachine:
    """One loaded machine; each run starts with empty stacks."""

    def __init__(self, runtime: MegaForthRuntime) -> None:
        self.runtime = runtime

    def run(self, lines: list[str], max_steps: int) -> bytes:
        context = self.runtime.main_context
        context.data.clear()
        context.returns.clear()
        return _evaluate_program(self.runtime, lines, max_steps)
