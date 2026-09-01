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
    AK / "tui" / "widgets" / "text-grid.f",
    AK / "tui" / "widgets" / "tabs.f",
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
        "CREATE _UC-DESCRIPTORS-MEM 2 UCSN-DESCRIPTOR-BANK-BYTES 7 + ALLOT",
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
        "  _UC-DESCRIPTORS 2 UCSN-DESCRIPTOR-BANK-BYTES _UC-CAP-A @ _UC-CAP-U @ UCSN-CAPTURE",
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
        "_UC-D0 UCSN-DESCRIPTOR-SOURCE-GENERATION@ 0= _UC-ASSERT",
        "_UC-D1 UCSN-DESCRIPTOR-SOURCE-GENERATION@ 0= _UC-ASSERT",
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
        "_UC-D0 UCSN-DESCRIPTOR-CLIP-ROW@ _UC-D0 UCSN-DESCRIPTOR-ROW@ = _UC-ASSERT",
        "_UC-D0 UCSN-DESCRIPTOR-CLIP-COLUMN@ _UC-D0 UCSN-DESCRIPTOR-COLUMN@ = _UC-ASSERT",
        "_UC-D0 UCSN-DESCRIPTOR-CLIP-HEIGHT@ _UC-D0 UCSN-DESCRIPTOR-HEIGHT@ = _UC-ASSERT",
        "_UC-D0 UCSN-DESCRIPTOR-CLIP-WIDTH@ _UC-D0 UCSN-DESCRIPTOR-WIDTH@ = _UC-ASSERT",
        "_UC-WORK @ 0= _UC-ASSERT _UC-WORK 895 + C@ 0= _UC-ASSERT",
        "_UC-BUILDER @ 0= _UC-ASSERT _UC-VALIDATION @ 0= _UC-ASSERT",
        "_UC-D0 UCSN-DESCRIPTOR-SOURCE-INDEX@ _UC-SAVED-INDEX !",
        # Validation capacity is checked after the canonical producer has
        # copied a native prefix.  Refusal must scrub that touched prefix,
        # preserve the inactive descriptor bank, and clear all scratch.
        "_UC-NATIVE 2048 165 FILL",
        "_UC-BUILDER 0 0 _UC-WORK 896",
        "_UC-DESCRIPTORS 2 UCSN-DESCRIPTOR-BANK-BYTES _UC-NATIVE 2048 UCSN-CAPTURE",
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
    assert int(summary.group(1)) >= 40


def _mounted_relation_program() -> list[str]:
    """Exercise mounted canonical identity at the ordinary draw boundary."""

    return [
        "VARIABLE _UM-FAILS", "VARIABLE _UM-CHECKS", "VARIABLE _UM-DEPTH",
        "VARIABLE _UM-HEAP",
        "VARIABLE _UM-SCR", "VARIABLE _UM-DOC-RGN", "VARIABLE _UM-MOUNT",
        "VARIABLE _UM-OTHER", "VARIABLE _UM-SOURCE",
        "VARIABLE _UM-PANEL-RGN", "VARIABLE _UM-OTHER-RGN",
        "VARIABLE _UM-A-RGN", "VARIABLE _UM-B-RGN",
        "VARIABLE _UM-A", "VARIABLE _UM-B", "VARIABLE _UM-CTX",
        "VARIABLE _UM-REVERSE", "VARIABLE _UM-OMIT-B", "VARIABLE _UM-STATUS",
        "VARIABLE _UM-KA", "VARIABLE _UM-KB", "VARIABLE _UM-KB2",
        "VARIABLE _UM-G0", "VARIABLE _UM-G1",
        "VARIABLE _UM-CSTATUS", "VARIABLE _UM-COUNT", "VARIABLE _UM-USED",
        "VARIABLE _UM-CAP-A", "VARIABLE _UM-CAP-U",
        "VARIABLE _UM-ENTRY-A", "VARIABLE _UM-ENTRY-B",
        "VARIABLE _UM-FIND-W", "VARIABLE _UM-FIND-R", "VARIABLE _UM-FIND-N",
        "CREATE _UM-PANEL-MEM _WDG-HDR-SIZE 7 + ALLOT",
        "_UM-PANEL-MEM 7 + -8 AND CONSTANT _UM-PANEL",
        "CREATE _UM-OTHER-MEM _WDG-HDR-SIZE 7 + ALLOT",
        "_UM-OTHER-MEM 7 + -8 AND CONSTANT _UM-OTHER-WDG",
        "CREATE _UM-A-BUF 64 ALLOT", "CREATE _UM-B-BUF 64 ALLOT",
        "CREATE _UM-BUILDER-MEM USCOL-BUILDER-SIZE 7 + ALLOT",
        "CREATE _UM-VALIDATION-MEM 256 7 + ALLOT",
        "CREATE _UM-WORK-MEM 1024 7 + ALLOT",
        "CREATE _UM-DESCRIPTORS-MEM 2 UCSN-DESCRIPTOR-BANK-BYTES 7 + ALLOT",
        "CREATE _UM-NATIVE-MEM 2048 7 + ALLOT",
        ': _UM-ASSERT 1 _UM-CHECKS +! 0= IF 1 _UM-FAILS +! ." MOUNT ASSERT " _UM-CHECKS @ . CR THEN ;',
        ": _UM-STACK DEPTH _UM-DEPTH @ = _UM-ASSERT ;",
        ": _UM-BUILDER _UM-BUILDER-MEM 7 + -8 AND ;",
        ": _UM-VALIDATION _UM-VALIDATION-MEM 7 + -8 AND ;",
        ": _UM-WORK _UM-WORK-MEM 7 + -8 AND ;",
        ": _UM-DESCRIPTORS _UM-DESCRIPTORS-MEM 7 + -8 AND ;",
        ": _UM-NATIVE _UM-NATIVE-MEM 7 + -8 AND ;",
        ": _UM-D0 _UM-DESCRIPTORS ;",
        ": _UM-D1 _UM-DESCRIPTORS UCSN-DESCRIPTOR-SIZE + ;",
        ": _UM-CAPTURE-AT ( native-a native-u -- )",
        "  _UM-CAP-U ! _UM-CAP-A !",
        "  _UM-BUILDER _UM-VALIDATION 256 _UM-WORK 1024",
        "  _UM-DESCRIPTORS 2 UCSN-DESCRIPTOR-BANK-BYTES",
        "  _UM-CAP-A @ _UM-CAP-U @ UCSN-CAPTURE",
        "  _UM-CSTATUS ! _UM-USED ! _UM-COUNT ! ;",
        ": _UM-CAPTURE _UM-NATIVE 2048 _UM-CAPTURE-AT ;",
        ": _UM-HANDLE ( event widget -- consumed? ) 2DROP 0 ;",
        ": _UM-OTHER-DRAW ( widget -- ) DROP ;",
        ": _UM-DRAW-A _UM-A @ WDG-DRAW ;",
        ": _UM-DRAW-B _UM-OMIT-B @ 0= IF _UM-B @ WDG-DRAW THEN ;",
        ": _UM-PANEL-DRAW ( widget -- )",
        "  DROP 35 0 0 DRW-CHAR",
        "  _UM-REVERSE @ IF _UM-DRAW-B _UM-DRAW-A",
        "  ELSE _UM-DRAW-A _UM-DRAW-B THEN ;",
        ": _UM-FULL-BODY UTUI-PAINT ;",
        ": _UM-PARTIAL-BODY 0 1 _UM-A @ TXTA-DRAW-ROWS ;",
        ": _UM-FULL _UM-MOUNT @ UIDL-DIRTY!",
        "  ['] _UM-FULL-BODY UTUI-DRAW-OBSERVE _UM-STATUS ! ;",
        ": _UM-PARTIAL ['] _UM-PARTIAL-BODY UTUI-DRAW-OBSERVE _UM-STATUS ! ;",
        ": _UM-RELATION ( widget -- relation|0 )",
        "  _UM-FIND-W ! _UTUI-MC-HEAD @ _UM-FIND-R ! _UTUI-MC-COUNT @ _UM-FIND-N !",
        "  BEGIN _UM-FIND-N @ WHILE",
        "    _UM-FIND-R @ DUP 0= IF DROP 0 EXIT THEN",
        "    DUP _UTUI-MCR-WIDGET@ _UM-FIND-W @ = IF EXIT THEN",
        "    _UTUI-MCR-NEXT@ _UM-FIND-R ! -1 _UM-FIND-N +!",
        "  REPEAT 0 ;",
        "0 _UM-FAILS ! 0 _UM-CHECKS ! DEPTH _UM-DEPTH !",
        "HEAP-FREE-BYTES _UM-HEAP !",
        "UCTX-ALLOC DUP _UM-CTX ! 0<> _UM-ASSERT",
        "_UM-CTX @ UCTX-CLEAR _UM-CTX @ UCTX-RESTORE",
        "80 24 SCR-NEW DUP _UM-SCR ! SCR-USE",
        "0 0 24 80 RGN-NEW _UM-DOC-RGN !",
        'S" <uidl arrange=stack><region id=mount/><region id=other/></uidl>" _UM-DOC-RGN @ UTUI-LOAD _UM-ASSERT',
        'S" mount" UTUI-BY-ID DUP _UM-MOUNT ! DUP 0<> _UM-ASSERT',
        "UIDL-ELEM-INDEX? _UM-ASSERT _UM-SOURCE !",
        'S" other" UTUI-BY-ID DUP _UM-OTHER ! 0<> _UM-ASSERT',
        "_UM-MOUNT @ UTUI-ELEM-RGN RGN-NEW _UM-PANEL-RGN !",
        "_UM-OTHER @ UTUI-ELEM-RGN RGN-NEW _UM-OTHER-RGN !",
        "_UM-PANEL-RGN @ 1 1 2 24 RGN-SUB _UM-A-RGN !",
        "_UM-PANEL-RGN @ 4 1 2 24 RGN-SUB _UM-B-RGN !",
        # Keep the complete canonical extents while clipping A at the panel's
        # right edge and B at its bottom edge through ordinary RGN ancestry.
        "_UM-PANEL-RGN @ RGN-ROW 1+",
        "_UM-PANEL-RGN @ RGN-COL _UM-PANEL-RGN @ RGN-W + 4 -",
        "2 12 _UM-A-RGN @ RGN-BOUNDS!",
        "_UM-PANEL-RGN @ RGN-ROW _UM-PANEL-RGN @ RGN-H + 1 -",
        "_UM-PANEL-RGN @ RGN-COL 1+ 3 24 _UM-B-RGN @ RGN-BOUNDS!",
        "_UM-A-RGN @ _UM-A-BUF 64 TXTA-NEW _UM-A !",
        "_UM-B-RGN @ _UM-B-BUF 64 TXTA-NEW _UM-B !",
        "_UM-A @ TXTA-INSTANCE@ DUP 0<> _UM-ASSERT",
        "_UM-B @ TXTA-INSTANCE@ DUP 0<> _UM-ASSERT <> _UM-ASSERT",
        'S" nested alpha" _UM-A @ TXTA-SET-TEXT',
        'S" nested beta" _UM-B @ TXTA-SET-TEXT',
        "_UM-PANEL WDG-T-CANVAS _UM-PANEL-RGN @ ' _UM-PANEL-DRAW ' _UM-HANDLE WDG-INIT",
        "_UM-OTHER-WDG WDG-T-CANVAS _UM-OTHER-RGN @ ' _UM-OTHER-DRAW ' _UM-HANDLE WDG-INIT",
        "_UM-PANEL _UM-MOUNT @ UTUI-WIDGET-SET",
        "_UM-OTHER-WDG _UM-OTHER @ UTUI-WIDGET-SET",
        "_UM-A @ _UTUI-MC-GENUINE-TEXTAREA? _UM-ASSERT",
        "_UM-SOURCE @ _UTUI-MC-SOURCE _UTUI-MCS-GENERATION@ _UTUI-MC-GENERATION-VALID? _UM-ASSERT",
        "_UM-PANEL _UTUI-MC-ROOT-SOURCE? _UTUI-MC-S-OK = _UM-ASSERT _UM-ASSERT",
        "-1 _UTUI-PROJ-ATTACHED ! 0 _UM-REVERSE ! 0 _UM-OMIT-B !",
        "_UM-FULL _UM-STACK",
        "_UM-A @ _UTUI-MC-ASSOCIATE _UTUI-MC-S-OK = _UM-ASSERT",
        "_UM-STATUS @ _UTUI-MC-S-OK = _UM-ASSERT",
        "_UTUI-MC-COUNT @ 2 = _UM-ASSERT",
        "_UM-A @ _UM-RELATION DUP 0<> _UM-ASSERT",
        "DUP _UTUI-MCR-INSTANCE@ _UM-A @ TXTA-INSTANCE@ = _UM-ASSERT",
        "DUP _UTUI-MCR-SOURCE@ _UM-SOURCE @ = _UM-ASSERT",
        "DUP _UTUI-MCR-ROOT-KEY@ DUP _UM-KA ! 0<> _UM-ASSERT",
        "_UTUI-MCR-GENERATION@ DUP _UM-G0 ! _UTUI-MC-GENERATION-VALID? _UM-ASSERT",
        "_UM-B @ _UM-RELATION DUP 0<> _UM-ASSERT",
        "DUP _UTUI-MCR-INSTANCE@ _UM-B @ TXTA-INSTANCE@ = _UM-ASSERT",
        "DUP _UTUI-MCR-SOURCE@ _UM-SOURCE @ = _UM-ASSERT",
        "DUP _UTUI-MCR-ROOT-KEY@ DUP _UM-KB ! _UM-KA @ U> _UM-ASSERT",
        "_UTUI-MCR-GENERATION@ _UM-G0 @ = _UM-ASSERT",
        "_UM-PANEL-RGN @ RGN-ROW _UM-PANEL-RGN @ RGN-COL SCR-GET CELL-CP@ 35 = _UM-ASSERT",
        # The generic snapshot now freezes both nested canonical textareas;
        # the custom panel canvas is still only ordinary CELL/residual paint.
        "_UM-CAPTURE _UM-STACK",
        "_UM-CSTATUS @ UCSN-S-OK = _UM-ASSERT",
        "_UM-COUNT @ 2 = _UM-ASSERT _UM-USED @ 0> _UM-ASSERT",
        "_UM-D0 UCSN-DESCRIPTOR-SOURCE-INDEX@ _UM-SOURCE @ = _UM-ASSERT",
        "_UM-D1 UCSN-DESCRIPTOR-SOURCE-INDEX@ _UM-SOURCE @ = _UM-ASSERT",
        "_UM-D0 UCSN-DESCRIPTOR-SOURCE-GENERATION@ _UM-G0 @ = _UM-ASSERT",
        "_UM-D1 UCSN-DESCRIPTOR-SOURCE-GENERATION@ _UM-G0 @ = _UM-ASSERT",
        "_UM-D0 UCSN-DESCRIPTOR-ROOT-KEY@ _UM-KA @ = _UM-ASSERT",
        "_UM-D1 UCSN-DESCRIPTOR-ROOT-KEY@ _UM-KB @ = _UM-ASSERT",
        "_UM-D0 _UM-NATIVE UCSN-DESCRIPTOR-NATIVE DROP _UM-ENTRY-A !",
        "_UM-D1 _UM-NATIVE UCSN-DESCRIPTOR-NATIVE DROP _UM-ENTRY-B !",
        "_UM-ENTRY-A @ USCOL-TEXT-FIRST USCOL-ITEM-TEXT@ S\" nested alpha\" STR-STR= _UM-ASSERT",
        "_UM-ENTRY-B @ USCOL-TEXT-FIRST USCOL-ITEM-TEXT@ S\" nested beta\" STR-STR= _UM-ASSERT",
        "_UM-D0 UCSN-DESCRIPTOR-ROW@ _UM-A-RGN @ RGN-ROW = _UM-ASSERT",
        "_UM-D0 UCSN-DESCRIPTOR-COLUMN@ _UM-A-RGN @ RGN-COL = _UM-ASSERT",
        "_UM-D0 UCSN-DESCRIPTOR-HEIGHT@ 2 = _UM-ASSERT",
        "_UM-D0 UCSN-DESCRIPTOR-WIDTH@ 12 = _UM-ASSERT",
        "_UM-D0 UCSN-DESCRIPTOR-CLIP-WIDTH@ 4 = _UM-ASSERT",
        "_UM-D1 UCSN-DESCRIPTOR-HEIGHT@ 3 = _UM-ASSERT",
        "_UM-D1 UCSN-DESCRIPTOR-CLIP-HEIGHT@ 1 = _UM-ASSERT",
        "_UM-PANEL-RGN @ RGN-ROW _UM-PANEL-RGN @ RGN-COL SCR-GET CELL-CP@ 35 = _UM-ASSERT",
        # Save/disown/restore must transfer, not duplicate, the heap ledger.
        "_UM-CTX @ UCTX-SAVE UCTX-LIVE-DISOWN",
        "0 UCTX-LIVE? _UM-ASSERT _UTUI-MC-HEAD @ 0= _UM-ASSERT",
        "_UTUI-MC-COUNT @ 0= _UM-ASSERT",
        "_UM-CTX @ UCTX-RESTORE _UM-CTX @ UCTX-LIVE? _UM-ASSERT",
        "_UTUI-MC-COUNT @ 2 = _UM-ASSERT _UM-CAPTURE",
        "_UM-CSTATUS @ UCSN-S-OK = _UM-ASSERT _UM-COUNT @ 2 = _UM-ASSERT _UM-STACK",
        # Draw order is not identity order.
        "-1 _UM-REVERSE ! _UM-FULL _UM-STATUS @ _UTUI-MC-S-OK = _UM-ASSERT",
        "_UM-A @ _UM-RELATION _UTUI-MCR-ROOT-KEY@ _UM-KA @ = _UM-ASSERT",
        "_UM-B @ _UM-RELATION _UTUI-MCR-ROOT-KEY@ _UM-KB @ = _UM-ASSERT",
        "_UTUI-MC-COUNT @ 2 = _UM-ASSERT _UM-STACK",
        # A real partial-row draw updates A without retiring unseen B.
        'S" alpha partial" _UM-A @ TXTA-SET-TEXT',
        "_UM-ENTRY-A @ USCOL-TEXT-FIRST USCOL-ITEM-TEXT@ S\" nested alpha\" STR-STR= _UM-ASSERT",
        "_UM-PARTIAL _UM-STATUS @ _UTUI-MC-S-OK = _UM-ASSERT",
        "_UTUI-MC-COUNT @ 2 = _UM-ASSERT",
        "_UM-A @ _UM-RELATION _UTUI-MCR-ROOT-KEY@ _UM-KA @ = _UM-ASSERT",
        "_UM-B @ _UM-RELATION _UTUI-MCR-ROOT-KEY@ _UM-KB @ = _UM-ASSERT",
        "_UM-CAPTURE _UM-CSTATUS @ UCSN-S-OK = _UM-ASSERT",
        "_UM-D0 _UM-NATIVE UCSN-DESCRIPTOR-NATIVE DROP _UM-ENTRY-A !",
        "_UM-ENTRY-A @ USCOL-TEXT-FIRST USCOL-ITEM-TEXT@ S\" alpha partial\" STR-STR= _UM-ASSERT _UM-STACK",
        # A complete scan retires an omitted child; reappearance gets a new key.
        "0 _UM-REVERSE ! -1 _UM-OMIT-B ! _UM-FULL",
        "_UM-STATUS @ _UTUI-MC-S-OK = _UM-ASSERT _UTUI-MC-COUNT @ 1 = _UM-ASSERT",
        "_UM-A @ _UM-RELATION _UTUI-MCR-ROOT-KEY@ _UM-KA @ = _UM-ASSERT",
        "_UM-B @ _UM-RELATION 0= _UM-ASSERT",
        "_UM-CAPTURE _UM-CSTATUS @ UCSN-S-OK = _UM-ASSERT",
        "_UM-COUNT @ 1 = _UM-ASSERT _UM-STACK",
        "0 _UM-OMIT-B ! _UM-FULL _UTUI-MC-COUNT @ 2 = _UM-ASSERT",
        "_UM-B @ _UM-RELATION DUP 0<> _UM-ASSERT",
        "DUP _UTUI-MCR-ROOT-KEY@ DUP _UM-KB2 ! _UM-KB @ U> _UM-ASSERT",
        "_UTUI-MCR-GENERATION@ _UM-G0 @ = _UM-ASSERT",
        "_UM-CAPTURE _UM-CSTATUS @ UCSN-S-OK = _UM-ASSERT",
        "_UM-COUNT @ 2 = _UM-ASSERT",
        "_UM-D0 UCSN-DESCRIPTOR-ROOT-KEY@ _UM-KA @ = _UM-ASSERT",
        "_UM-D1 UCSN-DESCRIPTOR-ROOT-KEY@ _UM-KB2 @ = _UM-ASSERT _UM-STACK",
        # Detach fences borrowed pointers immediately; reattach changes generation.
        "0 _UM-MOUNT @ UTUI-WIDGET-SET _UTUI-MC-COUNT @ 0= _UM-ASSERT",
        "_UM-PANEL _UM-MOUNT @ UTUI-WIDGET-SET _UM-FULL",
        "_UM-STATUS @ _UTUI-MC-S-OK = _UM-ASSERT _UTUI-MC-COUNT @ 2 = _UM-ASSERT",
        "_UM-A @ _UM-RELATION DUP _UTUI-MCR-GENERATION@ DUP _UM-G1 !",
        "_UM-G0 @ <> _UM-ASSERT _UTUI-MCR-ROOT-KEY@ 0<> _UM-ASSERT",
        "_UM-B @ _UM-RELATION _UTUI-MCR-GENERATION@ _UM-G1 @ = _UM-ASSERT",
        "_UM-CAPTURE _UM-CSTATUS @ UCSN-S-OK = _UM-ASSERT",
        "_UM-COUNT @ 2 = _UM-ASSERT",
        "_UM-D0 UCSN-DESCRIPTOR-SOURCE-GENERATION@ _UM-G1 @ = _UM-ASSERT",
        "_UM-D1 UCSN-DESCRIPTOR-SOURCE-GENERATION@ _UM-G1 @ = _UM-ASSERT",
        # Every caller bank is rejected before mutation when it aliases a
        # nested TXTA source, relation record, ancestor RGN, or live UCTX.
        "_UM-A-BUF 64 _UM-CAPTURE-AT",
        "_UM-CSTATUS @ UCSN-S-INVALID = _UM-ASSERT",
        "_UM-COUNT @ 0= _UM-ASSERT _UM-USED @ 0= _UM-ASSERT",
        "_UM-A-BUF C@ 97 = _UM-ASSERT",
        "_UTUI-MC-HEAD @ DUP _UM-FIND-R ! _UTUI-MC-REL-SIZE _UM-CAPTURE-AT",
        "_UM-CSTATUS @ UCSN-S-INVALID = _UM-ASSERT",
        "_UTUI-MC-HEAD @ _UM-FIND-R @ = _UM-ASSERT",
        "_UM-PANEL-RGN @ RGN-SIZE _UM-CAPTURE-AT",
        "_UM-CSTATUS @ UCSN-S-INVALID = _UM-ASSERT",
        "_UM-PANEL-RGN @ RGN-W 0> _UM-ASSERT",
        # Revalidation scans every caller-mounted widget while associating a
        # nested relation, including unrelated non-collection widget headers.
        "_UM-OTHER-WDG _WDG-HDR-SIZE _UM-CAPTURE-AT",
        "_UM-CSTATUS @ UCSN-S-INVALID = _UM-ASSERT",
        "_UM-OTHER-WDG WDG-TYPE WDG-T-CANVAS = _UM-ASSERT",
        "_UM-CTX @ 2048 _UM-CAPTURE-AT",
        "_UM-CSTATUS @ UCSN-S-INVALID = _UM-ASSERT",
        "_UM-CTX @ UCTX-LIVE? _UM-ASSERT",
        # Generation identity is equality-only: signed wrap values remain live.
        "-2 _UM-SOURCE @ _UTUI-MC-SOURCE _UTUI-MCS-GENERATION!",
        "_UM-A @ _UM-RELATION _UTUI-MCR-O-GENERATION + -2 SWAP !",
        "_UM-B @ _UM-RELATION _UTUI-MCR-O-GENERATION + -2 SWAP !",
        "_UM-CAPTURE _UM-CSTATUS @ UCSN-S-OK = _UM-ASSERT",
        "_UM-COUNT @ 2 = _UM-ASSERT",
        "_UM-D0 UCSN-DESCRIPTOR-SOURCE-GENERATION@ -2 = _UM-ASSERT",
        "_UM-D1 UCSN-DESCRIPTOR-SOURCE-GENERATION@ -2 = _UM-ASSERT",
        "_UM-G1 @ _UM-SOURCE @ _UTUI-MC-SOURCE _UTUI-MCS-GENERATION!",
        "_UM-A @ _UM-RELATION _UTUI-MCR-O-GENERATION + _UM-G1 @ SWAP !",
        "_UM-B @ _UM-RELATION _UTUI-MCR-O-GENERATION + _UM-G1 @ SWAP !",
        "_UM-CAPTURE _UM-CSTATUS @ UCSN-S-OK = _UM-ASSERT _UM-STACK",
        "0 _UTUI-PROJ-ATTACHED ! UTUI-DETACH",
        "_UM-CTX @ UCTX-SAVE UCTX-LIVE-DISOWN _UM-CTX @ UCTX-FREE",
        "_UM-A @ TXTA-FREE _UM-B @ TXTA-FREE",
        "_UM-A-RGN @ RGN-FREE _UM-B-RGN @ RGN-FREE",
        "_UM-PANEL-RGN @ RGN-FREE _UM-OTHER-RGN @ RGN-FREE",
        "_UM-DOC-RGN @ RGN-FREE _UM-SCR @ SCR-FREE",
        "HEAP-FREE-BYTES _UM-HEAP @ = _UM-ASSERT",
        "_UM-STACK",
        '_UM-FAILS @ 0= IF ." MOUNT RELATION PASS " ELSE ." MOUNT RELATION FAIL " THEN _UM-CHECKS @ . _UM-FAILS @ . CR',
    ]


def test_mounted_canonical_relations_follow_full_partial_and_uctx_lifecycle():
    output = _run_forth(_mounted_relation_program())
    summary = re.search(r"MOUNT RELATION PASS\s+(\d+)\s+0", output)
    assert summary, output[-10000:]
    assert int(summary.group(1)) >= 100


def _mixed_mounted_collection_program() -> list[str]:
    """Freeze one ordinary mounted TEXT_AREA and TEXT_GRID together."""

    return [
        "VARIABLE _MG-FAILS", "VARIABLE _MG-CHECKS", "VARIABLE _MG-DEPTH",
        "VARIABLE _MG-HEAP", "VARIABLE _MG-SCR", "VARIABLE _MG-DOC-RGN",
        "VARIABLE _MG-MOUNT", "VARIABLE _MG-SOURCE", "VARIABLE _MG-PANEL-RGN",
        "VARIABLE _MG-AREA-RGN", "VARIABLE _MG-GRID-RGN",
        "VARIABLE _MG-AREA", "VARIABLE _MG-GRID", "VARIABLE _MG-REVERSE",
        "VARIABLE _MG-STATUS", "VARIABLE _MG-MODEL-U",
        "VARIABLE _MG-CAP-A", "VARIABLE _MG-CAP-U",
        "VARIABLE _MG-CSTATUS", "VARIABLE _MG-COUNT", "VARIABLE _MG-USED",
        "VARIABLE _MG-REL-W", "VARIABLE _MG-REL-R", "VARIABLE _MG-REL-N",
        "VARIABLE _MG-KA", "VARIABLE _MG-KG",
        "VARIABLE _MG-ENTRY-A", "VARIABLE _MG-ENTRY-G",
        "CREATE _MG-PANEL-MEM _WDG-HDR-SIZE 7 + ALLOT",
        "_MG-PANEL-MEM 7 + -8 AND CONSTANT _MG-PANEL",
        "CREATE _MG-AREA-BUF 64 ALLOT",
        "CREATE _MG-MODEL-MEM 512 7 + ALLOT",
        "CREATE _MG-BUILDER-MEM USCOL-BUILDER-SIZE 7 + ALLOT",
        "CREATE _MG-VALIDATION-MEM 256 7 + ALLOT",
        "CREATE _MG-WORK-MEM 768 7 + ALLOT",
        "CREATE _MG-DESCRIPTORS-MEM 2 UCSN-DESCRIPTOR-BANK-BYTES 7 + ALLOT",
        "CREATE _MG-NATIVE-MEM 1024 7 + ALLOT",
        "CREATE _MG-SUMMARY-MEM USCOL-SUMMARY-SIZE 7 + ALLOT",
        ': _MG-ASSERT 1 _MG-CHECKS +! 0= IF 1 _MG-FAILS +! ." MIXED ASSERT " _MG-CHECKS @ . CR THEN ;',
        ": _MG-STACK DEPTH _MG-DEPTH @ = _MG-ASSERT ;",
        ": _MG-BUILDER _MG-BUILDER-MEM 7 + -8 AND ;",
        ": _MG-VALIDATION _MG-VALIDATION-MEM 7 + -8 AND ;",
        ": _MG-WORK _MG-WORK-MEM 7 + -8 AND ;",
        ": _MG-DESCRIPTORS _MG-DESCRIPTORS-MEM 7 + -8 AND ;",
        ": _MG-NATIVE _MG-NATIVE-MEM 7 + -8 AND ;",
        ": _MG-MODEL _MG-MODEL-MEM 7 + -8 AND ;",
        ": _MG-SUMMARY _MG-SUMMARY-MEM 7 + -8 AND ;",
        ": _MG-D0 _MG-DESCRIPTORS ;",
        ": _MG-D1 _MG-DESCRIPTORS UCSN-DESCRIPTOR-SIZE + ;",
        ": _MG-OK USCOL-S-OK = _MG-ASSERT ;",
        ": _MG-BUILD-GRID ( -- )",
        "  _MG-MODEL 512 _MG-BUILDER USCOL-BUILDER-INIT _MG-OK",
        "  USCOL-F-TEXT-GRID 700 0 0 2 12 3 _MG-BUILDER",
        "    USCOL-TEXT-BEGIN _MG-OK",
        "  USCOL-CONTENT-READ-ONLY 1 1 0 0 1 1 _MG-BUILDER",
        "    USCOL-TEXT-SHAPE _MG-OK",
        "  101 0 0 0 _MG-BUILDER USCOL-TEXT-POSITIONS _MG-OK",
        '  101 0 0 1 1 USCOL-ROLE-CONTENT USCOL-ITEM-CURRENT S" grid cell"',
        "    _MG-BUILDER USCOL-TEXT-ITEM _MG-OK",
        "  _MG-BUILDER USCOL-TEXT-END _MG-OK",
        "  _MG-BUILDER USCOL-BUILDER-FINISH",
        "    SWAP _MG-MODEL-U ! USCOL-S-OK = _MG-ASSERT ;",
        ": _MG-CAPTURE-AT ( native-a native-u -- )",
        "  _MG-CAP-U ! _MG-CAP-A !",
        "  _MG-BUILDER _MG-VALIDATION 256 _MG-WORK 768",
        "  _MG-DESCRIPTORS 2 UCSN-DESCRIPTOR-BANK-BYTES",
        "  _MG-CAP-A @ _MG-CAP-U @ UCSN-CAPTURE",
        "  _MG-CSTATUS ! _MG-USED ! _MG-COUNT ! ;",
        ": _MG-CAPTURE _MG-NATIVE 1024 _MG-CAPTURE-AT ;",
        ": _MG-HANDLE ( event widget -- consumed? ) 2DROP 0 ;",
        ": _MG-PANEL-DRAW ( widget -- )",
        "  DROP _MG-REVERSE @ IF _MG-GRID @ WDG-DRAW _MG-AREA @ WDG-DRAW",
        "  ELSE _MG-AREA @ WDG-DRAW _MG-GRID @ WDG-DRAW THEN ;",
        ": _MG-FULL-BODY UTUI-PAINT ;",
        ": _MG-FULL _MG-MOUNT @ UIDL-DIRTY!",
        "  ['] _MG-FULL-BODY UTUI-DRAW-OBSERVE _MG-STATUS ! ;",
        ": _MG-RELATION ( widget -- relation|0 )",
        "  _MG-REL-W ! _UTUI-MC-HEAD @ _MG-REL-R ! _UTUI-MC-COUNT @ _MG-REL-N !",
        "  BEGIN _MG-REL-N @ WHILE",
        "    _MG-REL-R @ DUP 0= IF DROP 0 EXIT THEN",
        "    DUP _UTUI-MCR-WIDGET@ _MG-REL-W @ = IF EXIT THEN",
        "    _UTUI-MCR-NEXT@ _MG-REL-R ! -1 _MG-REL-N +!",
        "  REPEAT 0 ;",
        "0 _MG-FAILS ! 0 _MG-CHECKS ! DEPTH _MG-DEPTH !",
        "HEAP-FREE-BYTES _MG-HEAP !",
        "80 24 SCR-NEW DUP _MG-SCR ! SCR-USE",
        "0 0 24 80 RGN-NEW _MG-DOC-RGN !",
        'S" <uidl><region id=mount/></uidl>" _MG-DOC-RGN @ UTUI-LOAD _MG-ASSERT',
        'S" mount" UTUI-BY-ID DUP _MG-MOUNT ! DUP 0<> _MG-ASSERT',
        "UIDL-ELEM-INDEX? _MG-ASSERT _MG-SOURCE !",
        "_MG-MOUNT @ UTUI-ELEM-RGN RGN-NEW _MG-PANEL-RGN !",
        "_MG-PANEL-RGN @ 0 0 2 16 RGN-SUB _MG-AREA-RGN !",
        "_MG-PANEL-RGN @ 3 0 2 12 RGN-SUB _MG-GRID-RGN !",
        "_MG-AREA-RGN @ _MG-AREA-BUF 64 TXTA-NEW _MG-AREA !",
        "_MG-GRID-RGN @ TGRID-NEW _MG-GRID !",
        "_MG-AREA @ TXTA-INSTANCE@ _MG-GRID @ TGRID-INSTANCE@ = _MG-ASSERT",
        'S" text area" _MG-AREA @ TXTA-SET-TEXT',
        "_MG-BUILD-GRID _MG-MODEL-U @ 0> _MG-ASSERT",
        "_MG-MODEL _MG-MODEL-U @ _MG-VALIDATION 256 _MG-SUMMARY _MG-GRID @",
        "  TGRID-BIND _MG-OK",
        "_MG-PANEL WDG-T-CANVAS _MG-PANEL-RGN @",
        "  ' _MG-PANEL-DRAW ' _MG-HANDLE WDG-INIT",
        "_MG-PANEL _MG-MOUNT @ UTUI-WIDGET-SET",
        "_MG-AREA @ _UTUI-MC-GENUINE-COLLECTION? _MG-ASSERT",
        "_MG-GRID @ _UTUI-MC-GENUINE-COLLECTION? _MG-ASSERT",
        "-1 _UTUI-PROJ-ATTACHED ! 0 _MG-REVERSE ! _MG-FULL _MG-STACK",
        "_MG-STATUS @ _UTUI-MC-S-OK = _MG-ASSERT",
        "_UTUI-MC-COUNT @ 2 = _MG-ASSERT",
        "_MG-AREA @ _MG-RELATION DUP 0<> _MG-ASSERT",
        "DUP _UTUI-MCR-FAMILY@ USCOL-F-TEXT-AREA = _MG-ASSERT",
        "DUP _UTUI-MCR-INSTANCE@ _MG-AREA @ TXTA-INSTANCE@ = _MG-ASSERT",
        "_UTUI-MCR-ROOT-KEY@ DUP _MG-KA ! 0<> _MG-ASSERT",
        "_MG-GRID @ _MG-RELATION DUP 0<> _MG-ASSERT",
        "DUP _UTUI-MCR-FAMILY@ USCOL-F-TEXT-GRID = _MG-ASSERT",
        "DUP _UTUI-MCR-INSTANCE@ _MG-GRID @ TGRID-INSTANCE@ = _MG-ASSERT",
        "_UTUI-MCR-ROOT-KEY@ DUP _MG-KG ! 0<> _MG-ASSERT",
        "_MG-KA @ _MG-KG @ <> _MG-ASSERT",
        "_MG-AREA @ _MG-RELATION _MG-GRID @ _MG-RELATION <> _MG-ASSERT",
        # Reversing ordinary child draw order must not cross-wire equal
        # per-family instance tokens or assign new semantic root keys.
        "-1 _MG-REVERSE ! _MG-FULL _MG-STATUS @ _UTUI-MC-S-OK = _MG-ASSERT",
        "_UTUI-MC-COUNT @ 2 = _MG-ASSERT",
        "_MG-AREA @ _MG-RELATION DUP _UTUI-MCR-FAMILY@",
        "  USCOL-F-TEXT-AREA = _MG-ASSERT _UTUI-MCR-ROOT-KEY@",
        "  _MG-KA @ = _MG-ASSERT",
        "_MG-GRID @ _MG-RELATION DUP _UTUI-MCR-FAMILY@",
        "  USCOL-F-TEXT-GRID = _MG-ASSERT _UTUI-MCR-ROOT-KEY@",
        "  _MG-KG @ = _MG-ASSERT",
        "_MG-STACK _MG-CAPTURE _MG-STACK",
        "_MG-CSTATUS @ UCSN-S-OK = _MG-ASSERT",
        "_MG-COUNT @ 2 = _MG-ASSERT _MG-USED @ 0> _MG-ASSERT",
        "_MG-D0 UCSN-DESCRIPTOR-FAMILY@ USCOL-F-TEXT-AREA = _MG-ASSERT",
        "_MG-D1 UCSN-DESCRIPTOR-FAMILY@ USCOL-F-TEXT-GRID = _MG-ASSERT",
        "_MG-D0 UCSN-DESCRIPTOR-ROOT-KEY@ _MG-KA @ = _MG-ASSERT",
        "_MG-D1 UCSN-DESCRIPTOR-ROOT-KEY@ _MG-KG @ = _MG-ASSERT",
        "_MG-D0 _MG-NATIVE UCSN-DESCRIPTOR-NATIVE DROP _MG-ENTRY-A !",
        "_MG-D1 _MG-NATIVE UCSN-DESCRIPTOR-NATIVE DROP _MG-ENTRY-G !",
        "_MG-ENTRY-A @ USCOL-TEXT-FIRST USCOL-ITEM-TEXT@",
        '  S" text area" STR-STR= _MG-ASSERT',
        "_MG-ENTRY-G @ USCOL-TEXT-FIRST USCOL-ITEM-TEXT@",
        '  S" grid cell" STR-STR= _MG-ASSERT',
        "_MG-ENTRY-G @ USCOL-ENTRY-KEY@ _MG-KG @ = _MG-ASSERT",
        "_MG-MODEL USCOL-ENTRY-KEY@ 700 = _MG-ASSERT _MG-STACK",
        # Every caller bank is rejected before mutation when it aliases the
        # grid module, the bound model, or the live widget descriptor.
        "_TGRID-W 8 _MG-CAPTURE-AT",
        "_MG-CSTATUS @ UCSN-S-INVALID = _MG-ASSERT _MG-COUNT @ 0= _MG-ASSERT",
        "_MG-MODEL _MG-MODEL-U @ _MG-CAPTURE-AT",
        "_MG-CSTATUS @ UCSN-S-INVALID = _MG-ASSERT",
        "_MG-MODEL USCOL-ENTRY-FAMILY@ USCOL-F-TEXT-GRID = _MG-ASSERT",
        "_MG-MODEL USCOL-ENTRY-KEY@ 700 = _MG-ASSERT",
        "_MG-GRID @ _TGRID-DESC-SIZE _MG-CAPTURE-AT",
        "_MG-CSTATUS @ UCSN-S-INVALID = _MG-ASSERT",
        "_MG-GRID @ TGRID-INSTANCE@ 0<> _MG-ASSERT _MG-STACK",
        "0 _MG-MOUNT @ UTUI-WIDGET-SET 0 _UTUI-PROJ-ATTACHED ! UTUI-DETACH",
        "_MG-AREA @ TXTA-FREE _MG-GRID @ TGRID-FREE",
        "_MG-AREA-RGN @ RGN-FREE _MG-GRID-RGN @ RGN-FREE",
        "_MG-PANEL-RGN @ RGN-FREE _MG-DOC-RGN @ RGN-FREE",
        "_MG-SCR @ SCR-FREE HEAP-FREE-BYTES _MG-HEAP @ = _MG-ASSERT",
        "_MG-STACK",
        '_MG-FAILS @ 0= IF ." MIXED COLLECTION PASS " ELSE ." MIXED COLLECTION FAIL " THEN _MG-CHECKS @ . _MG-FAILS @ . CR',
    ]


def test_mounted_textarea_and_textgrid_share_one_generic_collection_path():
    output = _run_forth(_mixed_mounted_collection_program())
    summary = re.search(r"MIXED COLLECTION PASS\s+(\d+)\s+0", output)
    assert summary, output[-10000:]
    assert int(summary.group(1)) >= 35


def _tabset_collection_program() -> list[str]:
    """Freeze authored and caller-mounted TABSETs through ordinary UIDL."""

    return [
        "VARIABLE _AT-FAILS", "VARIABLE _AT-CHECKS", "VARIABLE _AT-DEPTH",
        "VARIABLE _AT-HEAP", "VARIABLE _AT-SCR", "VARIABLE _AT-DOC-RGN",
        "VARIABLE _AT-AUTH", "VARIABLE _AT-AUTH-0", "VARIABLE _AT-AUTH-1",
        "VARIABLE _AT-BAD-TYPE", "VARIABLE _AT-BAD-LABEL",
        "VARIABLE _AT-MOUNT", "VARIABLE _AT-AUTH-SOURCE",
        "VARIABLE _AT-MOUNT-SOURCE", "VARIABLE _AT-MOUNT-RGN",
        "VARIABLE _AT-WIDGET", "VARIABLE _AT-CONTENT-0",
        "VARIABLE _AT-CONTENT-1", "VARIABLE _AT-LABEL-A",
        "VARIABLE _AT-LABEL-U", "VARIABLE _AT-DRAW-STATUS",
        "VARIABLE _AT-CSTATUS", "VARIABLE _AT-COUNT", "VARIABLE _AT-USED",
        "VARIABLE _AT-CAP-A", "VARIABLE _AT-CAP-U",
        "VARIABLE _AT-REL-W", "VARIABLE _AT-REL-R", "VARIABLE _AT-REL-N",
        "VARIABLE _AT-MOUNT-KEY", "VARIABLE _AT-MOUNT-GENERATION",
        "VARIABLE _AT-ENTRY-A", "VARIABLE _AT-ENTRY-M",
        "VARIABLE _AT-A0", "VARIABLE _AT-A1", "VARIABLE _AT-M0",
        "VARIABLE _AT-M1",
        "CREATE _AT-BUILDER-MEM USCOL-BUILDER-SIZE 7 + ALLOT",
        "CREATE _AT-VALIDATION-MEM 256 7 + ALLOT",
        "CREATE _AT-WORK-MEM 1024 7 + ALLOT",
        "CREATE _AT-DESCRIPTORS-MEM 2 UCSN-DESCRIPTOR-BANK-BYTES 7 + ALLOT",
        "CREATE _AT-NATIVE-MEM 2048 7 + ALLOT",
        ': _AT-ASSERT 1 _AT-CHECKS +! 0= IF 1 _AT-FAILS +! ." TABSET ASSERT " _AT-CHECKS @ . CR THEN ;',
        ": _AT-STACK DEPTH _AT-DEPTH @ = _AT-ASSERT ;",
        ": _AT-BUILDER _AT-BUILDER-MEM 7 + -8 AND ;",
        ": _AT-VALIDATION _AT-VALIDATION-MEM 7 + -8 AND ;",
        ": _AT-WORK _AT-WORK-MEM 7 + -8 AND ;",
        ": _AT-DESCRIPTORS _AT-DESCRIPTORS-MEM 7 + -8 AND ;",
        ": _AT-NATIVE _AT-NATIVE-MEM 7 + -8 AND ;",
        ": _AT-D0 _AT-DESCRIPTORS ;",
        ": _AT-D1 _AT-DESCRIPTORS UCSN-DESCRIPTOR-SIZE + ;",
        ": _AT-INDEX ( elem -- index )",
        "  UIDL-ELEM-INDEX? 0= IF DROP -1 THEN ;",
        ": _AT-CAPTURE-AT ( native-a native-u -- )",
        "  _AT-CAP-U ! _AT-CAP-A !",
        "  _AT-BUILDER _AT-VALIDATION 256 _AT-WORK 1024",
        "  _AT-DESCRIPTORS 2 UCSN-DESCRIPTOR-BANK-BYTES",
        "  _AT-CAP-A @ _AT-CAP-U @ UCSN-CAPTURE",
        "  _AT-CSTATUS ! _AT-USED ! _AT-COUNT ! ;",
        ": _AT-CAPTURE _AT-NATIVE 2048 _AT-CAPTURE-AT ;",
        ": _AT-FULL-BODY UTUI-PAINT ;",
        ": _AT-FULL _AT-MOUNT @ UIDL-DIRTY!",
        "  ['] _AT-FULL-BODY UTUI-DRAW-OBSERVE _AT-DRAW-STATUS ! ;",
        ": _AT-RELATION ( widget -- relation|0 )",
        "  _AT-REL-W ! _UTUI-MC-HEAD @ _AT-REL-R !",
        "  _UTUI-MC-COUNT @ _AT-REL-N !",
        "  BEGIN _AT-REL-N @ WHILE",
        "    _AT-REL-R @ DUP 0= IF DROP 0 EXIT THEN",
        "    DUP _UTUI-MCR-WIDGET@ _AT-REL-W @ = IF EXIT THEN",
        "    _UTUI-MCR-NEXT@ _AT-REL-R ! -1 _AT-REL-N +!",
        "  REPEAT 0 ;",
        "0 _AT-FAILS ! 0 _AT-CHECKS ! DEPTH _AT-DEPTH !",
        "HEAP-FREE-BYTES _AT-HEAP !",
        "80 24 SCR-NEW DUP _AT-SCR ! SCR-USE",
        "0 0 24 80 RGN-NEW _AT-DOC-RGN !",
        'S" <uidl arrange=stack><tabs id=auth><tab id=auth-a label=Alpha key=Alt+A/><tab id=auth-b label=Beta key=Alt+B/></tabs><tabs id=bad-type><tab label=Good/><label text=oops/></tabs><tabs id=bad-label><tab/></tabs><region id=mount/></uidl>" _AT-DOC-RGN @ UTUI-LOAD _AT-ASSERT',
        'S" auth" UTUI-BY-ID DUP _AT-AUTH ! DUP 0<> _AT-ASSERT',
        "DUP _AT-INDEX DUP _AT-AUTH-SOURCE ! 0>= _AT-ASSERT DROP",
        'S" auth-a" UTUI-BY-ID DUP _AT-AUTH-0 ! 0<> _AT-ASSERT',
        'S" auth-b" UTUI-BY-ID DUP _AT-AUTH-1 ! 0<> _AT-ASSERT',
        'S" bad-type" UTUI-BY-ID DUP _AT-BAD-TYPE ! 0<> _AT-ASSERT',
        'S" bad-label" UTUI-BY-ID DUP _AT-BAD-LABEL ! 0<> _AT-ASSERT',
        'S" mount" UTUI-BY-ID DUP _AT-MOUNT ! DUP 0<> _AT-ASSERT',
        "DUP _AT-INDEX DUP _AT-MOUNT-SOURCE ! 0>= _AT-ASSERT DROP",
        "99 _AT-AUTH @ UTUI-TAB-SELECT",
        "_AT-AUTH @ _UTUI-TABS-ACTIVE@ 1 = _AT-ASSERT",
        "_AT-MOUNT @ UTUI-ELEM-RGN RGN-NEW _AT-MOUNT-RGN !",
        "_AT-MOUNT-RGN @ 2 TAB-NEW-CAP DUP _AT-WIDGET ! 0<> _AT-ASSERT",
        'S" Mounted Alpha" 2DUP _AT-LABEL-U ! _AT-LABEL-A !',
        "  _AT-WIDGET @ TAB-ADD DUP _AT-CONTENT-0 ! 0<> _AT-ASSERT",
        'S" Mounted Beta" _AT-WIDGET @ TAB-ADD',
        "  DUP _AT-CONTENT-1 ! 0<> _AT-ASSERT",
        "1 _AT-WIDGET @ TAB-SELECT",
        "_AT-WIDGET @ _AT-MOUNT @ UTUI-WIDGET-SET",
        "-1 _UTUI-PROJ-ATTACHED ! _AT-FULL _AT-STACK",
        "_AT-DRAW-STATUS @ _UTUI-MC-S-OK = _AT-ASSERT",
        "_UTUI-MC-COUNT @ 1 = _AT-ASSERT",
        "_AT-WIDGET @ _AT-RELATION DUP 0<> _AT-ASSERT",
        "DUP _UTUI-MCR-FAMILY@ USCOL-F-TABSET = _AT-ASSERT",
        "DUP _UTUI-MCR-INSTANCE@ _AT-WIDGET @ TAB-INSTANCE@ = _AT-ASSERT",
        "DUP _UTUI-MCR-SOURCE@ _AT-MOUNT-SOURCE @ = _AT-ASSERT",
        "DUP _UTUI-MCR-ROOT-KEY@ DUP _AT-MOUNT-KEY ! 0<> _AT-ASSERT",
        "_UTUI-MCR-GENERATION@ DUP _AT-MOUNT-GENERATION !",
        "  _UTUI-MC-GENERATION-VALID? _AT-ASSERT",
        "_AT-CAPTURE _AT-STACK",
        "_AT-CSTATUS @ UCSN-S-OK = _AT-ASSERT",
        # The two malformed authored roots remain ordinary residual paint;
        # neither contributes a partial semantic TABSET.
        "_AT-COUNT @ 2 = _AT-ASSERT _AT-USED @ 0> _AT-ASSERT",
        "_AT-D0 UCSN-DESCRIPTOR-SOURCE-INDEX@",
        "  _AT-AUTH-SOURCE @ = _AT-ASSERT",
        "_AT-D1 UCSN-DESCRIPTOR-SOURCE-INDEX@",
        "  _AT-MOUNT-SOURCE @ = _AT-ASSERT",
        "_AT-D0 UCSN-DESCRIPTOR-SOURCE-GENERATION@ 0= _AT-ASSERT",
        "_AT-D0 UCSN-DESCRIPTOR-ROOT-KEY@ 1 = _AT-ASSERT",
        "_AT-D1 UCSN-DESCRIPTOR-SOURCE-GENERATION@",
        "  _AT-MOUNT-GENERATION @ = _AT-ASSERT",
        "_AT-D1 UCSN-DESCRIPTOR-ROOT-KEY@ _AT-MOUNT-KEY @ = _AT-ASSERT",
        "_AT-D0 UCSN-DESCRIPTOR-FAMILY@ USCOL-F-TABSET = _AT-ASSERT",
        "_AT-D1 UCSN-DESCRIPTOR-FAMILY@ USCOL-F-TABSET = _AT-ASSERT",
        "_AT-D0 UCSN-DESCRIPTOR-HEIGHT@ 2 = _AT-ASSERT",
        "_AT-D1 UCSN-DESCRIPTOR-HEIGHT@ 2 = _AT-ASSERT",
        "_AT-D0 UCSN-DESCRIPTOR-WIDTH@",
        "  _AT-AUTH @ _UTUI-SIDECAR _UTUI-SC-W@ = _AT-ASSERT",
        "_AT-D1 UCSN-DESCRIPTOR-WIDTH@ _AT-MOUNT-RGN @ RGN-W = _AT-ASSERT",
        "_AT-D0 _AT-NATIVE UCSN-DESCRIPTOR-NATIVE DROP _AT-ENTRY-A !",
        "_AT-D1 _AT-NATIVE UCSN-DESCRIPTOR-NATIVE DROP _AT-ENTRY-M !",
        "_AT-ENTRY-A @ USCOL-TABSET-COUNT@ 2 = _AT-ASSERT",
        "_AT-ENTRY-M @ USCOL-TABSET-COUNT@ 2 = _AT-ASSERT",
        "_AT-ENTRY-A @ USCOL-TABSET-FIRST DUP _AT-A0 !",
        "  USCOL-TAB-NEXT _AT-A1 !",
        "_AT-ENTRY-M @ USCOL-TABSET-FIRST DUP _AT-M0 !",
        "  USCOL-TAB-NEXT _AT-M1 !",
        "_AT-A0 @ USCOL-TAB-KEY@ _AT-AUTH-0 @ _AT-INDEX 1+ = _AT-ASSERT",
        "_AT-A1 @ USCOL-TAB-KEY@ _AT-AUTH-1 @ _AT-INDEX 1+ = _AT-ASSERT",
        "_AT-A0 @ USCOL-TAB-ORDER@ 0= _AT-ASSERT",
        "_AT-A1 @ USCOL-TAB-ORDER@ 1 = _AT-ASSERT",
        "_AT-A0 @ USCOL-TAB-STATE@ USCOL-STATE-SELECTED AND 0= _AT-ASSERT",
        "_AT-A1 @ USCOL-TAB-STATE@ USCOL-STATE-SELECTED AND 0<> _AT-ASSERT",
        '_AT-A0 @ USCOL-TAB-LABEL@ S" Alpha" STR-STR= _AT-ASSERT',
        '_AT-A1 @ USCOL-TAB-LABEL@ S" Beta" STR-STR= _AT-ASSERT',
        '_AT-A0 @ USCOL-TAB-SHORTCUT@ S" Alt+A" STR-STR= _AT-ASSERT',
        '_AT-A1 @ USCOL-TAB-SHORTCUT@ S" Alt+B" STR-STR= _AT-ASSERT',
        "_AT-M0 @ USCOL-TAB-KEY@ 0 _AT-WIDGET @ TAB-KEY@ = _AT-ASSERT",
        "_AT-M1 @ USCOL-TAB-KEY@ 1 _AT-WIDGET @ TAB-KEY@ = _AT-ASSERT",
        "_AT-M0 @ USCOL-TAB-ORDER@ 0= _AT-ASSERT",
        "_AT-M1 @ USCOL-TAB-ORDER@ 1 = _AT-ASSERT",
        "_AT-M0 @ USCOL-TAB-STATE@ USCOL-STATE-SELECTED AND 0= _AT-ASSERT",
        "_AT-M1 @ USCOL-TAB-STATE@ USCOL-STATE-SELECTED AND 0<> _AT-ASSERT",
        '_AT-M0 @ USCOL-TAB-LABEL@ S" Mounted Alpha" STR-STR= _AT-ASSERT',
        '_AT-M1 @ USCOL-TAB-LABEL@ S" Mounted Beta" STR-STR= _AT-ASSERT',
        "_AT-M0 @ USCOL-TAB-SHORTCUT-BYTES@ 0= _AT-ASSERT",
        "_AT-M1 @ USCOL-TAB-SHORTCUT-BYTES@ 0= _AT-ASSERT _AT-STACK",
        # Every inactive output bank remains caller-owned, but it may not
        # alias direct inline state or any live canonical widget authority.
        "_AT-AUTH @ _UTUI-SIDECAR _UTUI-SC-WPTR@ DUP @ 1 = _AT-ASSERT",
        "8 _AT-CAPTURE-AT",
        "_AT-CSTATUS @ UCSN-S-INVALID = _AT-ASSERT",
        "_AT-AUTH @ _UTUI-TABS-ACTIVE@ 1 = _AT-ASSERT",
        "_AT-WIDGET @ _TAB-O-TABS + @",
        "  _AT-WIDGET @ _TAB-O-ENTRY-BYTES + @ _AT-CAPTURE-AT",
        "_AT-CSTATUS @ UCSN-S-INVALID = _AT-ASSERT",
        "0 _AT-WIDGET @ TAB-KEY@ 0<> _AT-ASSERT",
        "_AT-LABEL-A @ _AT-LABEL-U @ _AT-CAPTURE-AT",
        "_AT-CSTATUS @ UCSN-S-INVALID = _AT-ASSERT",
        "_AT-LABEL-A @ C@ 77 = _AT-ASSERT _AT-STACK",
        "0 _AT-MOUNT @ UTUI-WIDGET-SET 0 _UTUI-PROJ-ATTACHED ! UTUI-DETACH",
        "_AT-WIDGET @ TAB-FREE",
        "_AT-CONTENT-0 @ RGN-FREE _AT-CONTENT-1 @ RGN-FREE",
        "_AT-MOUNT-RGN @ RGN-FREE _AT-DOC-RGN @ RGN-FREE",
        "_AT-SCR @ SCR-FREE HEAP-FREE-BYTES _AT-HEAP @ = _AT-ASSERT",
        "_AT-STACK",
        '_AT-FAILS @ 0= IF ." TABSET COLLECTION PASS " ELSE ." TABSET COLLECTION FAIL " THEN _AT-CHECKS @ . _AT-FAILS @ . CR',
    ]


def test_authored_and_mounted_tabs_share_generic_tabset_capture():
    output = _run_forth(_tabset_collection_program())
    summary = re.search(r"TABSET COLLECTION PASS\s+(\d+)\s+0", output)
    assert summary, output[-10000:]
    assert int(summary.group(1)) >= 55


def _ruha_constructor_program() -> list[str]:
    """Compile ABI 3 over the UCSN snapshot and exercise its bank proof."""

    # The constructor does not call host lifecycle machinery.  Minimal ABI
    # stubs keep this focused oracle below a full app-shell/Desk source load.
    host_stubs = [
        ": AHOST.HEAD ;",
        ": AHOST.UIDL-READY-XT ;",
        ": AHOST.UIDL-READY-CONTEXT 8 + ;",
        ": AHS.NEXT ;",
        ": AHS.ID 8 + ;",
        ": AHS.UCTX 16 + ;",
        ": AHS.HAS-UIDL 24 + ;",
        ": AHS.RGN 32 + ;",
        ": AHS-CALLABLE? DROP -1 ;",
        ": AHS-VISIBLE? DROP -1 ;",
        ": AHOST-UIDL-READY! 2DROP DROP ;",
        "VARIABLE _RA-STUB-ACTIVE",
        ": ASHELL-CTX-SWITCH _RA-STUB-ACTIVE ! ;",
        ": ASHELL-ACTIVE-CTX _RA-STUB-ACTIVE @ ;",
    ]
    source = host_stubs
    source += _load_forth_lines(AK / "tui" / "uidl-menu-snapshot.f")
    source += _load_forth_lines(
        AK / "tui" / "rich-terminal" / "uidl-hybrid-adapter.f"
    )
    source += [
        "VARIABLE _RA-FAILS", "VARIABLE _RA-CHECKS", "VARIABLE _RA-DEPTH",
        "VARIABLE _RA-CTX", "VARIABLE _RA-SCR", "VARIABLE _RA-RGN",
        "VARIABLE _RA-TEXTAREA", "VARIABLE _RA-STATUS",
        "VARIABLE _RA-SNAP", "VARIABLE _RA-SNAP1",
        "VARIABLE _RA-DIR-A", "VARIABLE _RA-DIR-U",
        "VARIABLE _RA-DESC-A", "VARIABLE _RA-DESC-U",
        "VARIABLE _RA-NATIVE-A", "VARIABLE _RA-NATIVE-U",
        "VARIABLE _RA-ENTRY",
        "CREATE _RA-HOST 16 ALLOT",
        "CREATE _RA-SLOT 40 ALLOT",
        "CREATE _RA-RECORDS-MEM RUHA-RECORD-SIZE 7 + ALLOT",
        "CREATE _RA-WORK-MEM 2 UMSN-WORK-ENTRY-SIZE * 7 + ALLOT",
        "CREATE _RA-WORK-TEXT-MEM 64 7 + ALLOT",
        "CREATE _RA-VALIDATION-MEM 256 7 + ALLOT",
        "CREATE _RA-CWORK-MEM 1024 7 + ALLOT",
        "CREATE _RA-DIRECTORY-MEM 2 RUHA-DOCUMENT-SIZE * 7 + ALLOT",
        "CREATE _RA-MENU-RECORDS-MEM 2 UMSN-RECORD-SIZE * 7 + ALLOT",
        "CREATE _RA-MENU-TEXT-MEM 128 7 + ALLOT",
        "CREATE _RA-DESCRIPTORS-MEM 2 UCSN-DESCRIPTOR-SIZE * 7 + ALLOT",
        "CREATE _RA-NATIVE-MEM 1024 7 + ALLOT",
        "CREATE _RA-ADAPTER-MEM RUHA-SIZE 7 + ALLOT",
        "CREATE _RA-ADAPTER2-MEM RUHA-SIZE 7 + ALLOT",
        "CREATE _RA-ADAPTER3-MEM RUHA-SIZE 7 + ALLOT",
        ": _RA-RECORDS _RA-RECORDS-MEM 7 + -8 AND ;",
        ": _RA-WORK _RA-WORK-MEM 7 + -8 AND ;",
        ": _RA-WORK-TEXT _RA-WORK-TEXT-MEM 7 + -8 AND ;",
        ": _RA-VALIDATION _RA-VALIDATION-MEM 7 + -8 AND ;",
        ": _RA-CWORK _RA-CWORK-MEM 7 + -8 AND ;",
        ": _RA-DIRECTORY _RA-DIRECTORY-MEM 7 + -8 AND ;",
        ": _RA-MENU-RECORDS _RA-MENU-RECORDS-MEM 7 + -8 AND ;",
        ": _RA-MENU-TEXT _RA-MENU-TEXT-MEM 7 + -8 AND ;",
        ": _RA-DESCRIPTORS _RA-DESCRIPTORS-MEM 7 + -8 AND ;",
        ": _RA-NATIVE _RA-NATIVE-MEM 7 + -8 AND ;",
        ": _RA-ADAPTER _RA-ADAPTER-MEM 7 + -8 AND ;",
        ": _RA-ADAPTER2 _RA-ADAPTER2-MEM 7 + -8 AND ;",
        ": _RA-ADAPTER3 _RA-ADAPTER3-MEM 7 + -8 AND ;",
        ': _RA-ASSERT 1 _RA-CHECKS +! 0= IF 1 _RA-FAILS +! ." RUHA ASSERT " _RA-CHECKS @ . CR THEN ;',
        ": _RA-STACK DEPTH _RA-DEPTH @ = _RA-ASSERT ;",
        ": _RA-INIT-ARGS",
        "  _RA-RECORDS RUHA-RECORD-SIZE",
        "  _RA-WORK 2 UMSN-WORK-ENTRY-SIZE * _RA-WORK-TEXT 64",
        "  _RA-VALIDATION 256 _RA-CWORK 1024",
        "  _RA-DIRECTORY 2 RUHA-DOCUMENT-SIZE *",
        "  _RA-MENU-RECORDS 2 UMSN-RECORD-SIZE * _RA-MENU-TEXT 128",
        "  _RA-DESCRIPTORS 2 UCSN-DESCRIPTOR-SIZE * _RA-NATIVE 1024 ;",
        ": _RA-QUERY ( draw -- )",
        "  _RA-ADAPTER RUHA-SNAPSHOT-FOR@ _RA-STATUS ! _RA-SNAP !",
        "  _RA-SNAP @ RUHA-SNAPSHOT-DIRECTORY@ _RA-DIR-U ! _RA-DIR-A !",
        "  _RA-SNAP @ RUHA-SNAPSHOT-COLLECTION-DESCRIPTORS@",
        "    _RA-DESC-U ! _RA-DESC-A !",
        "  _RA-SNAP @ RUHA-SNAPSHOT-COLLECTION-NATIVE@",
        "    _RA-NATIVE-U ! _RA-NATIVE-A ! ;",
        ": _RA-FIRST-ENTRY ( -- entry )",
        "  _RA-DIR-A @ RUHA-DOCUMENT-COLLECTION-DESCRIPTOR-OFFSET@",
        "    _RA-DESC-A @ +",
        "  _RA-DIR-A @ RUHA-DOCUMENT-COLLECTION-NATIVE-OFFSET@",
        "    _RA-NATIVE-A @ + UCSN-DESCRIPTOR-NATIVE DROP ;",
        "0 _RA-FAILS ! 0 _RA-CHECKS ! DEPTH _RA-DEPTH !",
        "_RA-INIT-ARGS _RA-ADAPTER RUHA-INIT RUHA-S-OK = _RA-ASSERT",
        "_RA-STACK _RA-ADAPTER RUHA-VALID? _RA-ASSERT",
        "RUHA-DOCUMENT-SIZE 112 = _RA-ASSERT",
        "RUHA-SNAPSHOT-SIZE 112 = _RA-ASSERT",
        "RUHA-SIZE 592 = _RA-ASSERT",
        "_RA-ADAPTER _RUHA-A.COLLECTION-BUILDER _RA-ADAPTER - 296 = _RA-ASSERT",
        "_RA-ADAPTER _RUHA-A.SNAP-DESCRIPTOR-BANK-U @ UCSN-DESCRIPTOR-SIZE = _RA-ASSERT",
        "_RA-ADAPTER _RUHA-A.SNAP-NATIVE-BANK-U @ 512 = _RA-ASSERT",
        # A corrupted high-bit half length must not pass by wrapping when
        # doubled back to the positive total length.
        "-1 1 RSHIFT 1+ 512 +",
        "  _RA-ADAPTER _RUHA-A.SNAP-NATIVE-BANK-U !",
        "_RA-ADAPTER RUHA-VALID? 0= _RA-ASSERT",
        "512 _RA-ADAPTER _RUHA-A.SNAP-NATIVE-BANK-U !",
        "_RA-ADAPTER RUHA-VALID? _RA-ASSERT",
        # Replacing one external range with RUHA's own module span must fail
        # before any caller bank or the already valid adapter is cleared.
        "_RA-RECORDS RUHA-RECORD-SIZE",
        "_RA-WORK 2 UMSN-WORK-ENTRY-SIZE * _RA-WORK-TEXT 64",
        "_RUHA-OWNED-START 8 _RA-CWORK 1024",
        "_RA-DIRECTORY 2 RUHA-DOCUMENT-SIZE *",
        "_RA-MENU-RECORDS 2 UMSN-RECORD-SIZE * _RA-MENU-TEXT 128",
        "_RA-DESCRIPTORS 2 UCSN-DESCRIPTOR-SIZE * _RA-NATIVE 1024",
        "_RA-ADAPTER2 RUHA-INIT RUHA-S-INVALID = _RA-ASSERT",
        "_RA-ADAPTER RUHA-VALID? _RA-ASSERT _RA-STACK",
        # Exercise the complete generic capture seam with one ordinary UIDL
        # textarea.  The fake host supplies only the normal descriptor fields;
        # RUHA still attaches through the UIDL projection lifecycle.
        "_RA-ADAPTER RUHA-INSTALL RUHA-S-OK = _RA-ASSERT",
        "_RA-HOST 16 0 FILL _RA-SLOT 40 0 FILL",
        "_RA-SLOT _RA-HOST ! 77 _RA-SLOT AHS.ID !",
        "_RA-HOST _RA-ADAPTER RUHA-HOST-INIT RUHA-S-OK = _RA-ASSERT",
        "UCTX-ALLOC DUP _RA-CTX ! 0<> _RA-ASSERT",
        "_RA-CTX @ UCTX-CLEAR _RA-CTX @ UCTX-RESTORE",
        "_RA-CTX @ ASHELL-CTX-SWITCH",
        # Construction while a UCTX is live must reject an aliased caller bank
        # before clearing either that authority or the already valid adapter.
        "_RA-RECORDS RUHA-RECORD-SIZE",
        "_RA-WORK 2 UMSN-WORK-ENTRY-SIZE * _RA-WORK-TEXT 64",
        "_RA-CTX @ 256 _RA-CWORK 1024",
        "_RA-DIRECTORY 2 RUHA-DOCUMENT-SIZE *",
        "_RA-MENU-RECORDS 2 UMSN-RECORD-SIZE * _RA-MENU-TEXT 128",
        "_RA-DESCRIPTORS 2 UCSN-DESCRIPTOR-SIZE * _RA-NATIVE 1024",
        "_RA-ADAPTER3 RUHA-INIT RUHA-S-INVALID = _RA-ASSERT",
        "_RA-CTX @ UCTX-LIVE? _RA-ASSERT",
        "_RA-ADAPTER RUHA-VALID? _RA-ASSERT _RA-STACK",
        "80 24 SCR-NEW DUP _RA-SCR ! SCR-USE",
        "0 0 24 80 RGN-NEW _RA-RGN !",
        "_RA-CTX @ _RA-SLOT AHS.UCTX !",
        "-1 _RA-SLOT AHS.HAS-UIDL !",
        "_RA-RGN @ _RA-SLOT AHS.RGN !",
        'S" <uidl><textarea id=note/></uidl>" _RA-RGN @ UTUI-LOAD _RA-ASSERT',
        'S" note" UTUI-BY-ID UTUI-WIDGET@ DUP _RA-TEXTAREA ! 0<> _RA-ASSERT',
        'S" aggregate alpha" _RA-TEXTAREA @ TXTA-SET-TEXT',
        "_RA-HOST _RA-SLOT _RA-ADAPTER RUHA-AHOST-UIDL-READY",
        "  RUHA-S-OK = _RA-ASSERT",
        "UTUI-PAINT UTUI-DRAW-COMPLETE _RA-STACK",
        "1 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT",
        "_RA-SNAP @ DUP _RA-SNAP1 ! RUHA-SNAPSHOT-GENERATION@ 1 = _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-DRAW-GENERATION@ 1 = _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-CONTENT-EPOCH@ 1 = _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-DOCUMENT-COUNT@ 1 = _RA-ASSERT",
        "_RA-DIR-U @ RUHA-DOCUMENT-SIZE = _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-RECORDS@ NIP 0= _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-TEXT@ NIP 0= _RA-ASSERT",
        "_RA-DESC-U @ UCSN-DESCRIPTOR-SIZE = _RA-ASSERT",
        "_RA-NATIVE-U @ 0> _RA-ASSERT",
        "_RA-DIR-A @ RUHA-DOCUMENT-RECORD-BYTES@ 0= _RA-ASSERT",
        "_RA-DIR-A @ RUHA-DOCUMENT-COLLECTION-DESCRIPTOR-OFFSET@ 0= _RA-ASSERT",
        "_RA-DIR-A @ RUHA-DOCUMENT-COLLECTION-DESCRIPTOR-BYTES@",
        "  UCSN-DESCRIPTOR-SIZE = _RA-ASSERT",
        "_RA-DIR-A @ RUHA-DOCUMENT-COLLECTION-NATIVE-OFFSET@ 0= _RA-ASSERT",
        "_RA-FIRST-ENTRY DUP _RA-ENTRY ! USCOL-ENTRY-FAMILY@",
        "  USCOL-F-TEXT-AREA = _RA-ASSERT",
        "_RA-ENTRY @ USCOL-TEXT-FIRST USCOL-ITEM-TEXT@",
        '  S" aggregate alpha" STR-STR= _RA-ASSERT',
        # A clean collection-bearing document must take a new UCSN capture,
        # not the menu-only frozen-slice reuse path.
        "2 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT",
        "_RA-SNAP @ _RA-SNAP1 @ <> _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-GENERATION@ 2 = _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-CONTENT-EPOCH@ 2 = _RA-ASSERT",
        "_RA-FIRST-ENTRY USCOL-TEXT-FIRST USCOL-ITEM-TEXT@",
        '  S" aggregate alpha" STR-STR= _RA-ASSERT',
        # A normal subsequent paint dirties the same document and publishes
        # the new canonical editor value through the opposite aggregate bank.
        'S" aggregate beta" _RA-TEXTAREA @ TXTA-SET-TEXT',
        "UTUI-PAINT UTUI-DRAW-COMPLETE",
        "3 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-GENERATION@ 3 = _RA-ASSERT",
        "_RA-SNAP @ RUHA-SNAPSHOT-CONTENT-EPOCH@ 3 = _RA-ASSERT",
        "_RA-FIRST-ENTRY USCOL-TEXT-FIRST USCOL-ITEM-TEXT@",
        '  S" aggregate beta" STR-STR= _RA-ASSERT _RA-STACK',
        '_RA-FAILS @ 0= IF ." RUHA CONSTRUCTOR PASS " ELSE ." RUHA CONSTRUCTOR FAIL " THEN _RA-CHECKS @ . _RA-FAILS @ . CR',
    ]
    return source


def test_ruha_abi3_constructor_accepts_only_disjoint_caller_banks():
    output = _run_forth(_ruha_constructor_program())
    summary = re.search(r"RUHA CONSTRUCTOR PASS\s+(\d+)\s+0", output)
    assert summary, output[-10000:]
    assert int(summary.group(1)) >= 35
