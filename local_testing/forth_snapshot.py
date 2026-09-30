#!/usr/bin/env python3
"""Build and reuse one KDOS snapshot of an Akashic module closure.

Focused tests load BIOS, KDOS, and a module closure once, keep the resulting
machine image, and then run each program from a copy of it.  The closure is
resolved from the modules' own ``REQUIRE`` markers, so a test names only its
roots.
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

from asm import assemble  # noqa: E402
from system import MegapadSystem  # noqa: E402


_CPU_FIELDS = (
    "pc", "psel", "xsel", "spsel", "flag_z", "flag_c", "flag_n", "flag_v",
    "flag_p", "flag_g", "flag_i", "flag_s", "d_reg", "q_out", "t_reg",
    "ivt_base", "ivec_id", "trap_addr", "halted", "idle", "cycle_count",
    "_ext_modifier",
)


def _source_lines(path: Path) -> list[str]:
    lines = []
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("\\"):
            continue
        if stripped.startswith("REQUIRE ") or stripped.startswith("PROVIDED "):
            continue
        lines.append(line)
    return lines


def _next_line(data: bytes, pos: int) -> bytes:
    end = data.find(b"\n", pos)
    return data[pos:end + 1] if end >= 0 else data[pos:]


def _run_input(system: MegapadSystem, payload: bytes, max_steps: int) -> int:
    pos = 0
    steps = 0
    while steps < max_steps:
        if system.cpu.halted:
            break
        if system.cpu.idle and not system.uart.has_rx_data:
            if pos >= len(payload):
                break
            chunk = _next_line(payload, pos)
            system.uart.inject_input(chunk)
            pos += len(chunk)
            continue
        executed = system.run_batch(min(100_000, max_steps - steps))
        steps += max(executed, 1)
    return steps


class ForthSnapshot:
    """One cached machine image with ``roots`` and their closure loaded.

    ``prelude`` lines run after the closure, as part of the image; tests use
    them to allocate fixtures once.
    """

    def __init__(
        self,
        roots: tuple[str, ...],
        *,
        prelude: tuple[str, ...] = (),
        ram_size: int = 1 << 20,
        ext_mem_size: int = 16 << 20,
        build_steps: int = 3_000_000_000,
    ) -> None:
        self.roots = roots
        self.prelude = prelude
        self.ram_size = ram_size
        self.ext_mem_size = ext_mem_size
        self.build_steps = build_steps
        self._image = None
        self.last_steps = 0

    @property
    def modules(self) -> tuple[str, ...]:
        return dependency_order(SOURCE_ROOT, self.roots)

    def _new_system(self) -> tuple[MegapadSystem, bytearray]:
        system = MegapadSystem(ram_size=self.ram_size, ext_mem_size=self.ext_mem_size)
        output = bytearray()
        system.uart.on_tx = output.append
        return system, output

    def _build(self):
        started = time.perf_counter()
        bios = assemble((MEGAPAD_ROOT / "bios.asm").read_text())
        source = _source_lines(MEGAPAD_ROOT / "kdos.f") + ["ENTER-USERLAND"]
        for module in self.modules:
            source.extend(_source_lines(SOURCE_ROOT / module))
        source.extend(self.prelude)
        system, output = self._new_system()
        system.load_binary(0, bios)
        system.boot()
        steps = _run_input(system, ("\n".join(source) + "\n").encode(), self.build_steps)
        text = output.decode("utf-8", errors="replace")
        errors = [
            line for line in text.splitlines()
            if "?" in line and ("not found" in line.lower() or "undefined" in line.lower())
        ]
        if errors:
            raise AssertionError("Forth compile errors:\n" + "\n".join(errors[-10:]))
        if not (system.cpu.idle and not system.uart.has_rx_data):
            raise AssertionError(f"snapshot build did not quiesce after {steps:,} steps")
        state = {name: getattr(system.cpu, name) for name in _CPU_FIELDS}
        state["regs"] = list(system.cpu.regs)
        self._image = (
            bios, bytes(system.cpu.mem), bytes(system._ext_mem),
            bytes(system._hbw_mem), state,
        )
        print(
            f"snapshot {', '.join(self.roots)}: {steps:,} steps in "
            f"{time.perf_counter() - started:.2f}s"
        )

    def run(
        self,
        lines: list[str],
        max_steps: int = 2_000_000_000,
        *,
        setup=None,
        inspect=None,
    ) -> str:
        """Run ``lines`` from a fresh copy of the snapshot; return UART text.

        KDOS echoes each input line (after the first, with a ``> `` prompt).
        Use :func:`program_output` to keep only what the program printed.
        ``setup(system)`` runs after the image is restored and before the
        program, for example to write input data into memory.
        ``inspect(system)`` runs after the program, before the machine is
        discarded, for example to read results from memory.
        """

        if self._image is None:
            self._build()
        bios, memory, ext_memory, hbw_memory, state = self._image
        system, output = self._new_system()
        system.load_binary(0, bios)
        system.boot()
        _run_input(system, b"", 5_000_000)
        system.cpu.mem[:len(memory)] = memory
        system._ext_mem[:len(ext_memory)] = ext_memory
        system._hbw_mem[:len(hbw_memory)] = hbw_memory
        system.cpu.regs[:] = state["regs"]
        for name, value in state.items():
            if name != "regs":
                setattr(system.cpu, name, value)
        if setup is not None:
            setup(system)
        output.clear()
        payload = ("\n".join(lines) + "\nBYE\n").encode()
        self.last_steps = _run_input(system, payload, max_steps)
        if inspect is not None:
            inspect(system)
        return output.decode("utf-8", errors="replace")


def program_output(output: str, lines: list[str]) -> str:
    """Drop KDOS's echo of the input lines and its ``ok`` acknowledgements."""

    typed = {line.strip() for line in lines}
    kept = []
    for line in output.replace("\r", "").splitlines():
        stripped = line.strip()
        if line.startswith("> ") or stripped in typed or stripped == "ok":
            continue
        kept.append(line)
    return "\n".join(kept)
