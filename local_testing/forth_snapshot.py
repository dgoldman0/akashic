#!/usr/bin/env python3
"""Build and reuse one KDOS snapshot of an Akashic module closure.

Focused tests load BIOS, KDOS, and a module closure once, keep the resulting
machine image, and then run each program from a copy of it.  The closure is
resolved from the modules' own ``REQUIRE`` markers, so a test names only its
roots.  It is compiled with the BIOS JIT on, as production KDOS compiles
autoexec modules; the prelude and test programs compile with it off.
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


# A machine that has stopped making progress, such as core 0 parked after an
# unhandled trap with console input it will never read, runs only a few
# instructions per batch.  That many such batches in a row is a stall.
_STALL_INSTRUCTIONS = 64
_STALL_BATCHES = 1_000


class MachineStalled(AssertionError):
    """The machine stopped making progress before its input was consumed."""


def _run_input(
    system: MegapadSystem,
    payload: bytes,
    max_steps: int,
    output: bytearray | None = None,
) -> int:
    pos = 0
    steps = 0
    quiet = 0
    while steps < max_steps:
        if system.cpu.halted:
            break
        if system.cpu.idle and not system.uart.has_rx_data:
            if pos >= len(payload):
                break
            chunk = _next_line(payload, pos)
            system.uart.inject_input(chunk)
            pos += len(chunk)
            quiet = 0
            continue
        executed = system.run_batch(min(100_000, max_steps - steps))
        steps += max(executed, 1)
        quiet = quiet + 1 if executed < _STALL_INSTRUCTIONS else 0
        if quiet >= _STALL_BATCHES:
            cpu = system.cpu
            tail = output.decode("utf-8", errors="replace")[-600:] if output else ""
            raise MachineStalled(
                f"machine stalled after {steps:,} steps with {len(payload) - pos:,} "
                f"input bytes unread: core 0 pc={cpu.pc:#x} idle={cpu.idle} "
                f"last vector={cpu.ivec_id}\n{tail}"
            )
    return steps


class ForthSnapshot:
    """One cached machine image with ``roots`` and their closure loaded.

    ``prelude`` lines run after the closure, as part of the image; tests use
    them to allocate fixtures once.  ``num_cores`` full cores are emulated on
    one host thread, whatever their number.
    """

    def __init__(
        self,
        roots: tuple[str, ...],
        *,
        prelude: tuple[str, ...] = (),
        num_cores: int = 1,
        ram_size: int = 1 << 20,
        ext_mem_size: int = 16 << 20,
        build_steps: int = 3_000_000_000,
    ) -> None:
        self.roots = roots
        self.prelude = prelude
        self.num_cores = num_cores
        self.ram_size = ram_size
        self.ext_mem_size = ext_mem_size
        self.build_steps = build_steps
        self._image = None
        self.last_steps = 0

    @property
    def modules(self) -> tuple[str, ...]:
        return dependency_order(SOURCE_ROOT, self.roots)

    def _new_system(self) -> tuple[MegapadSystem, bytearray]:
        system = MegapadSystem(
            ram_size=self.ram_size,
            ext_mem_size=self.ext_mem_size,
            num_cores=self.num_cores,
            worker_count=1,
        )
        output = bytearray()
        system.uart.on_tx = output.append
        return system, output

    def _build(self):
        started = time.perf_counter()
        bios = assemble((MEGAPAD_ROOT / "bios.asm").read_text())
        # Production KDOS compiles autoexec modules with the BIOS JIT on and
        # turns it off afterwards, so modules are compiled the same way here.
        source = _source_lines(MEGAPAD_ROOT / "kdos.f") + ["ENTER-USERLAND"]
        source += ["JIT-RESET", "JIT-ON"]
        for module in self.modules:
            source.extend(_source_lines(SOURCE_ROOT / module))
        source.append("JIT-OFF")
        source.extend(self.prelude)
        system, output = self._new_system()
        system.load_binary(0, bios)
        system.boot()
        steps = _run_input(
            system, ("\n".join(source) + "\n").encode(), self.build_steps, output,
        )
        text = output.decode("utf-8", errors="replace")
        errors = [
            line for line in text.splitlines()
            if "?" in line and ("not found" in line.lower() or "undefined" in line.lower())
        ]
        if errors:
            raise AssertionError("Forth compile errors:\n" + "\n".join(errors[-10:]))
        if not (system.cpu.idle and not system.uart.has_rx_data):
            raise AssertionError(f"snapshot build did not quiesce after {steps:,} steps")
        states = [
            {name: getattr(cpu, name) for name in _CPU_FIELDS} | {"regs": list(cpu.regs)}
            for cpu in system.cores
        ]
        self._image = (
            bios, bytes(system.cpu.mem), bytes(system._ext_mem),
            bytes(system._hbw_mem), states,
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
        bios, memory, ext_memory, hbw_memory, states = self._image
        system, output = self._new_system()
        system.load_binary(0, bios)
        system.boot()
        _run_input(system, b"", 5_000_000)
        system.cpu.mem[:len(memory)] = memory
        system._ext_mem[:len(ext_memory)] = ext_memory
        system._hbw_mem[:len(hbw_memory)] = hbw_memory
        for cpu, state in zip(system.cores, states):
            cpu.regs[:] = state["regs"]
            for name, value in state.items():
                if name != "regs":
                    setattr(cpu, name, value)
        if setup is not None:
            setup(system)
        output.clear()
        payload = ("\n".join(lines) + "\nBYE\n").encode()
        self.last_steps = _run_input(system, payload, max_steps, output)
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
