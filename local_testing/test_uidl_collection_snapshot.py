#!/usr/bin/env python3
"""Focused emulator oracle for generic UIDL collection freezing."""

from __future__ import annotations

import os
import re
import sys
import time
from pathlib import Path


AKASHIC_ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = AKASHIC_ROOT.parent
MEGAPAD_ROOT = Path(os.environ.get("MEGAPAD_ROOT", PROJECT_ROOT / "megapad"))

sys.path.insert(0, str(MEGAPAD_ROOT))

from asm import assemble  # noqa: E402
from system import MegapadSystem  # noqa: E402


BIOS_PATH = MEGAPAD_ROOT / "bios.asm"
KDOS_PATH = MEGAPAD_ROOT / "kdos.f"
AK = AKASHIC_ROOT / "akashic"
SOURCE_PATHS = [
    AK / "concurrency" / "event.f",
    AK / "concurrency" / "semaphore.f",
    AK / "concurrency" / "guard.f",
    AK / "utils" / "uint-range.f",
    AK / "utils" / "memory-span.f",
    AK / "utils" / "string.f",
    AK / "utils" / "term.f",
    AK / "math" / "fp32.f",
    AK / "math" / "fixed.f",
    AK / "text" / "utf8.f",
    AK / "text" / "cell-width.f",
    AK / "markup" / "core.f",
    AK / "markup" / "xml.f",
    AK / "liraq" / "state-tree.f",
    AK / "liraq" / "lel.f",
    AK / "liraq" / "uidl.f",
    AK / "liraq" / "uidl-semantic.f",
    AK / "liraq" / "uidl-chrome.f",
    AK / "tui" / "cell.f",
    AK / "tui" / "ansi.f",
    AK / "tui" / "screen.f",
    AK / "tui" / "draw.f",
    AK / "tui" / "tui-sidecar.f",
    AK / "tui" / "box.f",
    AK / "tui" / "region.f",
    AK / "tui" / "layout.f",
    AK / "tui" / "keys.f",
    AK / "tui" / "widget.f",
    AK / "tui" / "widgets" / "tree.f",
    AK / "tui" / "widgets" / "input.f",
    AK / "tui" / "widgets" / "list.f",
    AK / "text" / "gap-buf.f",
    AK / "text" / "undo.f",
    AK / "tui" / "semantic-collections.f",
    AK / "tui" / "widgets" / "textarea.f",
    AK / "tui" / "widgets" / "dialog.f",
    AK / "tui" / "uidl-tui.f",
    AK / "tui" / "uidl-collection-snapshot.f",
]

# This oracle has no style declarations.  UIDL-TUI still needs the style ABI
# while it compiles, but loading the complete CSS and colour implementations
# would make an unrelated subsystem dominate this focused collection test.
STYLE_ABI_STUBS = [
    ": CSS-DECL-FIND ( a u prop-a prop-u -- 0 0 false ) 2DROP 2DROP 0 0 0 ;",
    ": CSS-PARSE-NUMBER ( a u -- a u 0 0 0 false ) 0 0 0 0 ;",
    ": CSS-PARSE-UNIT ( a u -- a u 0 0 ) 0 0 ;",
    ": CSS-EXPAND-TRBL ( a u -- a u a u a u a u 1 ) 2DUP 2DUP 2DUP 1 ;",
    ": TUI-PARSE-COLOR ( a u -- 0 false ) 2DROP 0 0 ;",
]

_snapshot = None


def _load_forth_lines(path: Path) -> list[str]:
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
    return data[pos : end + 1] if end >= 0 else data[pos:]


def _cpu_state(cpu) -> dict:
    fields = (
        "pc", "psel", "xsel", "spsel", "flag_z", "flag_c", "flag_n",
        "flag_v", "flag_p", "flag_g", "flag_i", "flag_s", "d_reg",
        "q_out", "t_reg", "ivt_base", "ivec_id", "trap_addr", "halted",
        "idle", "cycle_count", "_ext_modifier",
    )
    return {name: getattr(cpu, name) for name in fields} | {"regs": list(cpu.regs)}


def _restore_cpu(cpu, state: dict) -> None:
    cpu.regs[:] = state["regs"]
    for name, value in state.items():
        if name != "regs":
            setattr(cpu, name, value)


def _capture_uart(system: MegapadSystem) -> bytearray:
    output = bytearray()
    system.uart.on_tx = output.append
    return output


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


def _build_snapshot():
    global _snapshot
    if _snapshot is not None:
        return _snapshot

    started = time.perf_counter()
    bios = assemble(BIOS_PATH.read_text(encoding="utf-8"))
    source = _load_forth_lines(KDOS_PATH) + ["ENTER-USERLAND"]
    for path in SOURCE_PATHS:
        if path.name == "uidl-tui.f":
            source.extend(STYLE_ABI_STUBS)
        source.extend(_load_forth_lines(path))

    system = MegapadSystem(ram_size=1 << 20, ext_mem_size=16 << 20)
    output = _capture_uart(system)
    system.load_binary(0, bios)
    system.boot()
    steps = _run_input(system, ("\n".join(source) + "\n").encode(), 1_000_000_000)
    text = output.decode("utf-8", errors="replace")
    compile_errors = [
        line for line in text.splitlines()
        if "?" in line and ("not found" in line.lower() or "undefined" in line.lower())
    ]
    assert not compile_errors, "Forth compile errors:\n" + "\n".join(compile_errors[-10:])
    assert system.cpu.idle and not system.uart.has_rx_data, (
        f"snapshot build did not quiesce after {steps:,} steps\n{text[-10000:]}"
    )
    _snapshot = (bios, bytes(system.cpu.mem), bytes(system._ext_mem), _cpu_state(system.cpu))
    print(
        f"UIDL collection snapshot: {steps:,} steps in "
        f"{time.perf_counter() - started:.2f}s"
    )
    return _snapshot


def _run_forth(lines: list[str], max_steps: int = 250_000_000) -> str:
    bios, memory, ext_memory, state = _build_snapshot()
    system = MegapadSystem(ram_size=1 << 20, ext_mem_size=16 << 20)
    output = _capture_uart(system)
    system.load_binary(0, bios)
    system.boot()
    _run_input(system, b"", 5_000_000)
    system.cpu.mem[: len(memory)] = memory
    system._ext_mem[: len(ext_memory)] = ext_memory
    _restore_cpu(system.cpu, state)
    output.clear()
    _run_input(system, ("\n".join(lines) + "\nBYE\n").encode(), max_steps)
    return output.decode("utf-8", errors="replace")


def _oracle_program() -> list[str]:
    return [
        "VARIABLE _UC-FAILS", "VARIABLE _UC-CHECKS", "VARIABLE _UC-DEPTH",
        "VARIABLE _UC-SCR", "VARIABLE _UC-RGN",
        "VARIABLE _UC-EA", "VARIABLE _UC-EB", "VARIABLE _UC-EM",
        "VARIABLE _UC-WA", "VARIABLE _UC-WB", "VARIABLE _UC-WM",
        "VARIABLE _UC-MOUNT-RGN", "VARIABLE _UC-COUNT",
        "VARIABLE _UC-USED", "VARIABLE _UC-STATUS",
        "VARIABLE _UC-CAP-A", "VARIABLE _UC-CAP-U",
        "VARIABLE _UC-SAVED-INDEX",
        "VARIABLE _UC-ENTRY-A", "VARIABLE _UC-ENTRY-B",
        "CREATE _UC-NL 10 C,",
        "CREATE _UC-MOUNT-BUF 64 ALLOT",
        "CREATE _UC-BUILDER-MEM USCOL-BUILDER-SIZE 7 + ALLOT",
        "CREATE _UC-VALIDATION-MEM 256 7 + ALLOT",
        "CREATE _UC-WORK-MEM 896 7 + ALLOT",
        "CREATE _UC-DESCRIPTORS-MEM 224 7 + ALLOT",
        "CREATE _UC-NATIVE-MEM 2048 7 + ALLOT",
        "CREATE _UC-SMALL-MEM 8 7 + ALLOT",
        ": _UC-BUILDER _UC-BUILDER-MEM 7 + -8 AND ;",
        ": _UC-VALIDATION _UC-VALIDATION-MEM 7 + -8 AND ;",
        ": _UC-WORK _UC-WORK-MEM 7 + -8 AND ;",
        ": _UC-DESCRIPTORS _UC-DESCRIPTORS-MEM 7 + -8 AND ;",
        ": _UC-NATIVE _UC-NATIVE-MEM 7 + -8 AND ;",
        ": _UC-SMALL _UC-SMALL-MEM 7 + -8 AND ;",
        ': _UC-ASSERT 1 _UC-CHECKS +! 0= IF 1 _UC-FAILS +! ." UCSN ASSERT " _UC-CHECKS @ . CR THEN ;',
        ": _UC-STACK DEPTH _UC-DEPTH @ = _UC-ASSERT ;",
        ": _UC-D0 _UC-DESCRIPTORS ;",
        ": _UC-D1 _UC-DESCRIPTORS UCSN-DESCRIPTOR-SIZE + ;",
        ": _UC-INDEX ( elem -- index )",
        "  UIDL-ELEM-INDEX? 0= IF DROP -1 THEN ;",
        ": _UC-CAPTURE ( native-a native-u -- )",
        "  _UC-CAP-U ! _UC-CAP-A !",
        "  _UC-BUILDER _UC-VALIDATION 256 _UC-WORK 896",
        "  _UC-DESCRIPTORS 224 _UC-CAP-A @ _UC-CAP-U @ UCSN-CAPTURE",
        "  _UC-STATUS ! _UC-USED ! _UC-COUNT ! ;",
        "0 _UC-FAILS ! 0 _UC-CHECKS ! DEPTH _UC-DEPTH !",
        "80 24 SCR-NEW DUP _UC-SCR ! SCR-USE",
        "0 0 24 80 RGN-NEW _UC-RGN !",
        'S" <uidl><region arrange=flex><textarea id=a/><textarea id=b/><region id=mount/></region></uidl>" _UC-RGN @ UTUI-LOAD _UC-ASSERT',
        'S" a" UTUI-BY-ID DUP _UC-EA ! DUP 0<> _UC-ASSERT UTUI-WIDGET@ DUP _UC-WA ! 0<> _UC-ASSERT',
        'S" b" UTUI-BY-ID DUP _UC-EB ! DUP 0<> _UC-ASSERT UTUI-WIDGET@ DUP _UC-WB ! 0<> _UC-ASSERT',
        'S" mount" UTUI-BY-ID DUP _UC-EM ! DUP 0<> _UC-ASSERT DROP',
        'S" alpha one" _UC-WA @ TXTA-SET-TEXT',
        "_UC-NL 1 _UC-WA @ TXTA-INS-STR",
        'S" alpha two" _UC-WA @ TXTA-INS-STR',
        'S" beta two" _UC-WB @ TXTA-SET-TEXT',
        "0 2 _UC-WA @ TXTA-GUTTER!",
        "UTUI-PAINT",
        # Change focus after ordinary paint.  Capture can observe B as selected
        # only if the visitor seam resynchronizes canonical widget focus.
        "_UC-EB @ UTUI-FOCUS!",
        "2 40 4 20 RGN-NEW _UC-MOUNT-RGN !",
        "_UC-MOUNT-RGN @ _UC-MOUNT-BUF 64 TXTA-NEW _UC-WM !",
        'S" residual editor" _UC-WM @ TXTA-SET-TEXT',
        "_UC-WM @ _UC-EM @ UTUI-WIDGET-SET",
        "_UC-STACK",
        "_UC-NATIVE 2048 _UC-CAPTURE",
        "_UC-STACK",
        "_UC-STATUS @ UCSN-S-OK = _UC-ASSERT",
        "_UC-COUNT @ 2 = _UC-ASSERT",
        "_UC-USED @ 0> _UC-ASSERT",
        "_UC-D0 UCSN-DESCRIPTOR-SOURCE@ UCSN-SOURCE-UIDL = _UC-ASSERT",
        "_UC-D0 UCSN-DESCRIPTOR-SOURCE-INDEX@ _UC-EA @ _UC-INDEX = _UC-ASSERT",
        "_UC-D1 UCSN-DESCRIPTOR-SOURCE-INDEX@ _UC-EB @ _UC-INDEX = _UC-ASSERT",
        "_UC-D0 UCSN-DESCRIPTOR-ROOT-KEY@ 1 = _UC-ASSERT",
        "_UC-D1 UCSN-DESCRIPTOR-ROOT-KEY@ 1 = _UC-ASSERT",
        "_UC-D0 UCSN-DESCRIPTOR-NATIVE-OFFSET@ 0= _UC-ASSERT",
        "_UC-D1 UCSN-DESCRIPTOR-NATIVE-OFFSET@ 0> _UC-ASSERT",
        "_UC-D0 _UC-NATIVE UCSN-DESCRIPTOR-NATIVE DROP _UC-ENTRY-A !",
        "_UC-D1 _UC-NATIVE UCSN-DESCRIPTOR-NATIVE DROP _UC-ENTRY-B !",
        "_UC-ENTRY-A @ USCOL-ENTRY-FAMILY@ USCOL-F-TEXT-AREA = _UC-ASSERT",
        "_UC-ENTRY-B @ USCOL-ENTRY-FAMILY@ USCOL-F-TEXT-AREA = _UC-ASSERT",
        "_UC-ENTRY-A @ USCOL-TEXT-FIRST USCOL-ITEM-TEXT@ S\" alpha one\" STR-STR= _UC-ASSERT",
        "_UC-ENTRY-B @ USCOL-TEXT-FIRST USCOL-ITEM-TEXT@ S\" beta two\" STR-STR= _UC-ASSERT",
        "_UC-ENTRY-A @ USCOL-ROOT-STATE@ USCOL-STATE-SELECTED AND 0= _UC-ASSERT",
        "_UC-ENTRY-B @ USCOL-ROOT-STATE@ USCOL-STATE-SELECTED AND 0<> _UC-ASSERT",
        "_UC-D0 UCSN-DESCRIPTOR-COLUMN@ _UC-EA @ _UTUI-SIDECAR _UTUI-SC-COL@ 2 + = _UC-ASSERT",
        "_UC-D0 UCSN-DESCRIPTOR-WIDTH@ _UC-EA @ _UTUI-SIDECAR _UTUI-SC-W@ 2 - = _UC-ASSERT",
        "_UC-D0 UCSN-DESCRIPTOR-HEIGHT@ _UC-ENTRY-A @ USCOL-ROOT-HEIGHT@ = _UC-ASSERT",
        "_UC-WORK @ 0= _UC-ASSERT _UC-WORK 895 + C@ 0= _UC-ASSERT",
        "_UC-BUILDER @ 0= _UC-ASSERT _UC-VALIDATION @ 0= _UC-ASSERT",
        "_UC-D0 UCSN-DESCRIPTOR-SOURCE-INDEX@ _UC-SAVED-INDEX !",
        # Validation capacity is checked after the canonical producer has
        # copied a native prefix.  Refusal must scrub that touched prefix,
        # preserve the inactive descriptor bank, and clear all scratch.
        "_UC-NATIVE 2048 165 FILL",
        "_UC-BUILDER 0 0 _UC-WORK 896",
        "_UC-DESCRIPTORS 224 _UC-NATIVE 2048 UCSN-CAPTURE",
        "_UC-STATUS ! _UC-USED ! _UC-COUNT !",
        "_UC-STACK",
        "_UC-STATUS @ UCSN-S-CAPACITY = _UC-ASSERT",
        "_UC-COUNT @ 0= _UC-ASSERT _UC-USED @ 0= _UC-ASSERT",
        "_UC-NATIVE C@ 0= _UC-ASSERT",
        "_UC-NATIVE 2047 + C@ 165 = _UC-ASSERT",
        "_UC-D0 UCSN-DESCRIPTOR-SOURCE-INDEX@ _UC-SAVED-INDEX @ = _UC-ASSERT",
        "_UC-WORK @ 0= _UC-ASSERT _UC-WORK 895 + C@ 0= _UC-ASSERT",
        "_UC-BUILDER @ 0= _UC-ASSERT",
        "_UC-SMALL 8 165 FILL",
        "_UC-SMALL 8 _UC-CAPTURE",
        "_UC-STACK",
        "_UC-STATUS @ UCSN-S-CAPACITY = _UC-ASSERT",
        "_UC-COUNT @ 0= _UC-ASSERT _UC-USED @ 0= _UC-ASSERT",
        "_UC-SMALL C@ 165 = _UC-ASSERT",
        "_UC-D0 UCSN-DESCRIPTOR-SOURCE-INDEX@ _UC-SAVED-INDEX @ = _UC-ASSERT",
        "_UC-WB @ _TXTA-O-BUF-A + @ 4096 _UC-CAPTURE",
        "_UC-STACK",
        "_UC-STATUS @ UCSN-S-INVALID = _UC-ASSERT",
        "_UC-COUNT @ 0= _UC-ASSERT _UC-USED @ 0= _UC-ASSERT",
        "_UC-WB @ _TXTA-O-BUF-A + @ C@ 98 = _UC-ASSERT",
        "_UC-WM @ WDG-HIDE",
        "_UC-MOUNT-BUF 64 _UC-CAPTURE",
        "_UC-STACK",
        "_UC-STATUS @ UCSN-S-INVALID = _UC-ASSERT",
        "_UC-MOUNT-BUF C@ 114 = _UC-ASSERT",
        "_UC-EM @ UTUI-WIDGET@ _UC-WM @ = _UC-ASSERT",
        "_UC-STACK",
        "UTUI-DETACH",
        "_UC-WM @ TXTA-FREE _UC-MOUNT-RGN @ RGN-FREE",
        "_UC-STACK",
        '_UC-FAILS @ 0= IF ." UCSN TEST PASS " ELSE ." UCSN TEST FAIL " THEN _UC-CHECKS @ . _UC-FAILS @ . CR',
    ]


def test_uidl_collection_snapshot_freezes_direct_textareas_and_rejects_aliases():
    program = _oracle_program()
    assert not any("style=" in line.lower() for line in program)
    output = _run_forth(program)
    summary = re.search(r"UCSN TEST PASS\s+(\d+)\s+0", output)
    assert summary, output[-10000:]
    assert int(summary.group(1)) >= 35
