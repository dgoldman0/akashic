#!/usr/bin/env python3
"""Focused transaction tests for File Explorer copy/cut paste.

The suite compiles the real Explorer dependency closure into MegaPad, then
drives the applet's status-returning transaction seam against a fault-injected
RAM VFS.  UI smoke coverage remains in ``akashic_tui.py``; these cases focus
on no-loss behavior, descriptor/context cleanup, and cut ordering.
"""

from __future__ import annotations

import os
from pathlib import Path
import sys
import time


PROJECT_ROOT = Path(__file__).resolve().parents[2]
AKASHIC_ROOT = Path(__file__).resolve().parents[1]
MEGAPAD_ROOT = Path(os.environ.get("MEGAPAD_ROOT", PROJECT_ROOT / "megapad"))
sys.path.insert(0, str(MEGAPAD_ROOT))
sys.path.insert(0, str(AKASHIC_ROOT / "local_testing"))

from asm import assemble  # noqa: E402
from system import MegapadSystem  # noqa: E402
from akashic_tui import SOURCE_ROOT, dependency_order  # noqa: E402


BIOS_PATH = MEGAPAD_ROOT / "bios.asm"
KDOS_PATH = MEGAPAD_ROOT / "kdos.f"
ROOT_MODULE = "tui/applets/fexplorer/fexplorer.f"
FEXPLORER_F = SOURCE_ROOT / ROOT_MODULE


def _forth_lines(path: Path) -> list[str]:
    source: list[str] = []
    for line in path.read_text().splitlines():
        stripped = line.split("\\", 1)[0].strip()
        if not stripped:
            continue
        if stripped.startswith("REQUIRE ") or stripped.startswith("PROVIDED "):
            continue
        source.append(stripped)
    packed_lines: list[str] = []
    packed = ""
    for line in source:
        candidate = f"{packed} {line}" if packed else line
        if len(candidate) <= 180:
            packed = candidate
        else:
            packed_lines.append(packed)
            packed = line
    if packed:
        packed_lines.append(packed)
    return packed_lines


def _packed_source(lines: list[str]) -> list[str]:
    """Pack an already-selected Forth source fragment."""
    source: list[str] = []
    for line in lines:
        stripped = line.split("\\", 1)[0].strip()
        if stripped:
            source.append(stripped)
    packed_lines: list[str] = []
    packed = ""
    for line in source:
        candidate = f"{packed} {line}" if packed else line
        if len(candidate) <= 180:
            packed = candidate
        else:
            packed_lines.append(packed)
            packed = line
    if packed:
        packed_lines.append(packed)
    return packed_lines


def _transaction_source() -> list[str]:
    """Select the actual applet transaction implementation for the fixture."""
    lines = FEXPLORER_F.read_text().splitlines()
    start = next(
        index for index, line in enumerate(lines)
        if line.startswith("16 CONSTANT _FCP-MAX-PATH-DEPTH")
    )
    end = next(
        index for index, line in enumerate(lines[start:], start)
        if line.startswith(": _FEXP-REFRESH-AFTER-MUTATION")
    )
    return _packed_source(lines[start:end])


def _next_line(data: bytes, pos: int) -> bytes:
    newline = data.find(b"\n", pos)
    return data[pos : newline + 1] if newline >= 0 else data[pos:]


def _capture_uart(system: MegapadSystem) -> bytearray:
    output = bytearray()
    system.uart.on_tx = output.append
    return output


def _uart_text(output: bytearray) -> str:
    return "".join(
        chr(value) if 0x20 <= value < 0x7F or value in (9, 10, 13) else ""
        for value in output
    )


_CPU_FIELDS = (
    "pc", "psel", "xsel", "spsel", "flag_z", "flag_c", "flag_n",
    "flag_v", "flag_p", "flag_g", "flag_i", "flag_s", "d_reg",
    "q_out", "t_reg", "ivt_base", "ivec_id", "trap_addr", "halted",
    "idle", "cycle_count", "_ext_modifier",
)


def _save_cpu(cpu) -> dict:
    return {name: getattr(cpu, name) for name in _CPU_FIELDS} | {
        "regs": list(cpu.regs)
    }


def _restore_cpu(cpu, state: dict) -> None:
    cpu.regs[:] = state["regs"]
    for name in _CPU_FIELDS:
        setattr(cpu, name, state[name])


_snapshot: tuple[bytes, bytes, list[dict], bytes] | None = None


HELPERS = [
    "VARIABLE _TV VARIABLE _TO",
    "CREATE _TOUT 256 ALLOT VARIABLE _TOUT-FD VARIABLE _TOUT-LEN",
    "VARIABLE _TP-DA VARIABLE _TP-DU VARIABLE _TP-PA VARIABLE _TP-PU",
    "VARIABLE _TF-WRITE-MODE VARIABLE _TF-WRITES",
    "VARIABLE _TF-DELETE-FAIL VARIABLE _TF-SYNC-FAIL-ONCE",
    "VARIABLE _TF-SYNC-AFTER VARIABLE _TF-CLOSE-CALLS",
    "VARIABLE _TF-CLOSE-THROW-AT VARIABLE _TF-USE-CALLS",
    "VARIABLE _TF-USE-THROW-AT",
    "VARIABLE _TF-GUARDED VARIABLE _TFW-B VARIABLE _TFW-L ",
    "VARIABLE _TFW-O VARIABLE _TFW-I VARIABLE _TFW-V",
    ": T-WRITE _TFW-V ! _TFW-I ! _TFW-O ! _TFW-L ! _TFW-B !",
    "_vfs-guard GUARD-MINE? IF TRUE _TF-GUARDED ! THEN",
    "_TF-WRITE-MODE @ 1 = IF 1 _TF-WRITES +!",
    "_TF-WRITES @ 2 = IF 0 EXIT THEN _TFW-L @ 2 MIN _TFW-L ! THEN",
    "_TF-WRITE-MODE @ 4 = IF -222 THROW THEN",
    "_TF-WRITE-MODE @ 2 = IF _TFW-L @ 2 MIN _TFW-L ! THEN",
    "_TFW-B @ _TFW-L @ _TFW-O @ _TFW-I @ _TFW-V @ _VFS-RAM-WRITE",
    "_TF-WRITE-MODE @ 3 = IF 88 _TFW-I @ IN.BDATA @ _TFW-O @ + C! THEN ;",
    ": T-DELETE _vfs-guard GUARD-MINE? IF TRUE _TF-GUARDED ! THEN "
    "_TF-DELETE-FAIL @ 2 = IF _VFS-RAM-DELETE DUP IF EXIT THEN "
    "DROP -224 THROW THEN _TF-DELETE-FAIL @ IF 2DROP -1 "
    "ELSE _VFS-RAM-DELETE THEN ;",
    ": T-SYNC _vfs-guard GUARD-MINE? IF TRUE _TF-GUARDED ! THEN",
    "_TF-SYNC-FAIL-ONCE @ IF 0 _TF-SYNC-FAIL-ONCE ! 2DROP -1",
    "ELSE _TF-SYNC-AFTER @ IF _VFS-RAM-SYNC DUP IF EXIT THEN "
    "DROP -225 THROW ELSE _VFS-RAM-SYNC THEN THEN ;",
    ": T-CLOSE-AFTER VFS-CLOSE 1 _TF-CLOSE-CALLS +! "
    "_TF-CLOSE-CALLS @ _TF-CLOSE-THROW-AT @ = IF -226 THROW THEN ;",
    ": T-USE-AFTER VFS-USE 1 _TF-USE-CALLS +! "
    "_TF-USE-CALLS @ _TF-USE-THROW-AT @ = IF -227 THROW THEN ;",
    ": T-RM-AFTER VFS-RM DUP IF EXIT THEN DROP -228 THROW ;",
    ": T-SYNC-AFTER VFS-SYNC DUP IF EXIT THEN DROP -229 THROW ;",
    "CREATE T-VTABLE VFS-VT-SIZE ALLOT",
    "VFS-RAM-VTABLE T-VTABLE VFS-VT-SIZE CMOVE",
    "' T-WRITE T-VTABLE VFS-VT-WRITE CELLS + !",
    "' T-DELETE T-VTABLE VFS-VT-DELETE CELLS + !",
    "' T-SYNC T-VTABLE VFS-VT-SYNC CELLS + !",
    ": T-VFS-NEW 524288 A-XMEM ARENA-NEW IF -1 THROW THEN "
    "T-VTABLE VFS-NEW ;",
    ": T-PUT _TP-PU ! _TP-PA ! _TP-DU ! _TP-DA !",
    "_TP-PA @ _TP-PU @ _TV @ VFS-CREATE DUP 0= IF -101 THROW THEN DROP",
    "_TV @ VFS-USE _TP-PA @ _TP-PU @ VFS-OPEN",
    "DUP 0= IF -102 THROW THEN DUP _TOUT-FD !",
    "_TP-DA @ _TP-DU @ ROT VFS-WRITE-EXACT IF -103 THROW THEN",
    "_TOUT-FD @ VFS-CLOSE _TV @ VFS-SYNC IF -104 THROW THEN ;",
    ": T-FD-FREE-COUNT 0 SWAP V.FDFREE @ BEGIN DUP WHILE "
    "SWAP 1+ SWAP FD.FREE @ REPEAT DROP ;",
    ": T-PRESENT? _TV @ VFS-RESOLVE 0<> ;",
    ": T-SHOW _TV @ VFS-USE VFS-OPEN",
    "DUP 0= IF DROP .\" <absent> \" EXIT THEN",
    "DUP _TOUT-FD ! DUP VFS-SIZE DUP _TOUT-LEN !",
    "_TOUT SWAP ROT VFS-READ-EXACT IF .\" <read-error> \" ELSE",
    "_TOUT _TOUT-LEN @ TYPE SPACE THEN _TOUT-FD @ VFS-CLOSE ;",
    ": T-CLIP-SRC S\" /src.txt\" DUP _FEXP-CLIP-PATH-LEN ! "
    "_FEXP-CLIP-PATH SWAP CMOVE "
    "S\" /src.txt\" _TV @ VFS-RESOLVE _FEXP-CLIP-IN ! ;",
    ": T-SELECT-DEST S\" /dest\" _TV @ VFS-RESOLVE _FEXP-SEL-IN ! ;",
    ": T-SETUP 0 _TF-WRITE-MODE ! 0 _TF-WRITES !",
    "0 _TF-DELETE-FAIL ! 0 _TF-SYNC-FAIL-ONCE ! 0 _TF-SYNC-AFTER !",
    "0 _TF-CLOSE-CALLS ! 0 _TF-CLOSE-THROW-AT !",
    "0 _TF-USE-CALLS ! 0 _TF-USE-THROW-AT !",
    "['] VFS-CLOSE _FCP-CLOSE-XT ! ['] VFS-USE _FCP-USE-XT !",
    "['] VFS-RM _FCP-RM-XT ! ['] VFS-SYNC _FCP-SYNC-XT !",
    "T-VFS-NEW _TV ! _TV @ _FEXP-VFS !",
    "_TV @ VFS-USE S\" dest\" _TV @ VFS-MKDIR THROW",
    "S\" payload-across-io\" S\" /src.txt\" T-PUT",
    "T-CLIP-SRC T-SELECT-DEST _FEXP-CLIP-COPY _FEXP-CLIP-OP !",
    "T-VFS-NEW _TO ! _TO @ VFS-USE 0 _TF-GUARDED ! ;",
]


def build_snapshot() -> None:
    global _snapshot
    if _snapshot is not None:
        return
    print("[*] Building Explorer transaction snapshot ...")
    started = time.monotonic()
    bios = assemble(BIOS_PATH.read_text())
    system = MegapadSystem(
        ram_size=4 * 1024 * 1024,
        ext_mem_size=16 * 1024 * 1024,
        num_cores=2,
    )
    output = _capture_uart(system)
    system.load_binary(0, bios)
    system.boot()
    payload_lines = _forth_lines(KDOS_PATH) + [
        "ENTER-USERLAND",
        "-1 CONSTANT GUARDED",
    ]
    for module in dependency_order(("utils/fs/vfs.f",)):
        payload_lines += _forth_lines(SOURCE_ROOT / module)
    payload_lines += _packed_source([
        "512 CONSTANT _FEXP-PATH-CAP",
        "32768 CONSTANT _FEXP-PREVIEW-CAP",
        "0 CONSTANT _FEXP-CLIP-NONE",
        "1 CONSTANT _FEXP-CLIP-COPY",
        "2 CONSTANT _FEXP-CLIP-CUT",
        "0 CONSTANT _FCP-S-OK",
        "1 CONSTANT _FCP-S-SOURCE",
        "2 CONSTANT _FCP-S-DESTINATION",
        "3 CONSTANT _FCP-S-SAME",
        "4 CONSTANT _FCP-S-CONFLICT",
        "5 CONSTANT _FCP-S-CREATE",
        "6 CONSTANT _FCP-S-IO",
        "7 CONSTANT _FCP-S-VERIFY",
        "8 CONSTANT _FCP-S-DELETE",
        "9 CONSTANT _FCP-S-DELETE-SYNC",
        "10 CONSTANT _FCP-S-ROLLBACK",
        "11 CONSTANT _FCP-S-INTERNAL",
        "VARIABLE _FEXP-VFS VARIABLE _FEXP-SEL-IN",
        "VARIABLE _FEXP-CLIP-IN VARIABLE _FEXP-CLIP-OP",
        "VARIABLE _FEXP-CLIP-PATH-LEN",
        "CREATE _FEXP-CLIP-PATH _FEXP-PATH-CAP ALLOT",
        "CREATE _FEXP-PATH-BUF _FEXP-PATH-CAP ALLOT",
        "CREATE _FEXP-PREV-BUF _FEXP-PREVIEW-CAP ALLOT",
        ": _FEXP-SELECTED _FEXP-SEL-IN @ ;",
        ": ASHELL-TOAST 2DROP ;",
    ])
    payload_lines += _transaction_source()
    payload_lines += HELPERS
    data = ("\n".join(payload_lines) + "\n").encode()
    pos = 0
    steps = 0
    load_budget = 2_000_000_000
    while steps < load_budget:
        if system.cpu.halted:
            break
        if system.cpu.idle and not system.uart.has_rx_data:
            if pos >= len(data):
                break
            chunk = _next_line(data, pos)
            system.uart.inject_input(chunk)
            pos += len(chunk)
        ran = system.run_batch(min(100_000, load_budget - steps))
        steps += max(ran, 1)
    transcript = _uart_text(output)
    errors = [
        line for line in transcript.splitlines()
        if line.strip().lower().endswith("? (not found)")
        or line.strip().lower() in {
            "stack underflow", "branch offset overflow",
            "compile-only word", "dictionary overflow",
        }
    ]
    if pos < len(data) or not system.cpu.idle or errors:
        raise RuntimeError(
            f"Explorer load failed at {pos}/{len(data)} bytes; "
            f"idle={system.cpu.idle}, halted={system.cpu.halted}\n"
            + "\n".join(errors[-30:])
            + "\n--- transcript tail ---\n"
            + transcript[-16000:]
        )
    _snapshot = (
        bios,
        bytes(system.cpu.mem),
        [_save_cpu(cpu) for cpu in system.cores],
        bytes(system._ext_mem),
    )
    print(
        f"[*] Snapshot ready: {steps:,} steps in "
        f"{time.monotonic() - started:.1f}s"
    )


def run_forth(lines: list[str], max_steps: int = 180_000_000) -> str:
    assert _snapshot is not None
    bios, memory, cpu_states, ext_memory = _snapshot
    system = MegapadSystem(
        ram_size=4 * 1024 * 1024,
        ext_mem_size=16 * 1024 * 1024,
        num_cores=2,
    )
    output = _capture_uart(system)
    system.load_binary(0, bios)
    system.boot()
    for _ in range(5_000_000):
        if system.cpu.idle and not system.uart.has_rx_data:
            break
        system.run_batch(10_000)
    system.cpu.mem[: len(memory)] = memory
    system._ext_mem[: len(ext_memory)] = ext_memory
    for cpu, state in zip(system.cores, cpu_states):
        _restore_cpu(cpu, state)
    tx_ring = system.cpu.regs[19]
    if 0 < tx_ring < len(memory):
        system.uart._tx_ring_base = tx_ring
    output.clear()
    data = ("\n".join(lines) + "\nBYE\n").encode()
    pos = 0
    steps = 0
    while steps < max_steps:
        if system.cpu.halted:
            break
        if system.cpu.idle and not system.uart.has_rx_data:
            if pos >= len(data):
                break
            chunk = _next_line(data, pos)
            system.uart.inject_input(chunk)
            pos += len(chunk)
        ran = system.run_batch(min(100_000, max_steps - steps))
        steps += max(ran, 1)
    transcript = _uart_text(output)
    if pos < len(data):
        raise RuntimeError(
            f"test stalled at {pos}/{len(data)} bytes\n{transcript[-5000:]}"
        )
    return transcript


passed = 0
failed = 0


def check(name: str, forth: list[str], expected: str) -> None:
    global passed, failed
    output = run_forth(forth)
    diagnostics = ("? (not found)", "Stack underflow", "Branch offset overflow")
    results = output
    for command in forth + ["BYE"]:
        results = results.replace(command + "\r\n", "")
        results = results.replace(command + "\n", "")
    tokens = [token for token in results.split() if token not in ("Bye!", "ok", ">")]
    results = " ".join(tokens) + " "
    wanted = " ".join(expected.split()) + " "
    if wanted in results and not any(item in output for item in diagnostics):
        passed += 1
        print(f"  PASS  {name}")
    else:
        failed += 1
        print(
            f"  FAIL  {name}\n"
            f"        expected {expected!r}\n"
            f"        results {results!r}\n"
            f"        output tail {output[-5000:]!r}"
        )


def main() -> int:
    build_snapshot()

    check(
        "copy is exact, guarded, context-safe, and descriptor-clean",
        [
            "T-SETUP _TV @ T-FD-FREE-COUNT CONSTANT _BEFORE "
            "_TV @ V.CWD @ CONSTANT _CWD",
            "2 _TF-WRITE-MODE ! _FCP-RUN .",
            'S" /src.txt" T-PRESENT? . S" /dest/src.txt" T-PRESENT? .',
            "VFS-CUR _TO @ = . _TF-GUARDED @ .",
            "_TV @ T-FD-FREE-COUNT _BEFORE = . _TV @ V.CWD @ _CWD = .",
            'S" /dest/src.txt" T-SHOW',
        ],
        "0 -1 -1 -1 -1 -1 -1 payload-across-io ",
    )

    check(
        "a zero-progress write rolls back the new destination",
        [
            "T-SETUP _TV @ T-FD-FREE-COUNT CONSTANT _BEFORE",
            "1 _TF-WRITE-MODE ! _FCP-RUN .",
            'S" /src.txt" T-PRESENT? . S" /dest/src.txt" T-PRESENT? .',
            "VFS-CUR _TO @ = . _TV @ T-FD-FREE-COUNT _BEFORE = .",
        ],
        "6 -1 0 -1 -1 ",
    )

    check(
        "a target sync failure rolls back before verification",
        [
            "T-SETUP TRUE _TF-SYNC-FAIL-ONCE ! _FCP-RUN .",
            'S" /src.txt" T-PRESENT? . S" /dest/src.txt" T-PRESENT? .',
            "VFS-CUR _TO @ = .",
        ],
        "6 -1 0 -1 ",
    )

    check(
        "destination corruption is detected and rolled back",
        [
            "T-SETUP 3 _TF-WRITE-MODE ! _FCP-RUN .",
            'S" /src.txt" T-PRESENT? . S" /dest/src.txt" T-PRESENT? .',
            "VFS-CUR _TO @ = .",
        ],
        "7 -1 0 -1 ",
    )

    check(
        "an unexpected write THROW preserves its I/O phase and unwinds",
        [
            "T-SETUP _TV @ T-FD-FREE-COUNT CONSTANT _BEFORE",
            "4 _TF-WRITE-MODE ! _FCP-RUN .",
            'S" /src.txt" T-PRESENT? . S" /dest/src.txt" T-PRESENT? .',
            "VFS-CUR _TO @ = . _TV @ T-FD-FREE-COUNT _BEFORE = .",
        ],
        "6 -1 0 -1 -1 ",
    )

    check(
        "after-effect close attempts both descriptors without double-close",
        [
            "T-SETUP _TV @ T-FD-FREE-COUNT CONSTANT _BEFORE "
            "1 _TF-CLOSE-THROW-AT ! ' T-CLOSE-AFTER _FCP-CLOSE-XT !",
            "_FCP-RUN .",
            'S" /src.txt" T-PRESENT? . S" /dest/src.txt" T-PRESENT? .',
            "VFS-CUR _TO @ = . _TV @ T-FD-FREE-COUNT _BEFORE = .",
            "_TF-CLOSE-CALLS @ . _FCP-FDS @ 0= . _FCP-FDD @ 0= .",
            "_FCP-RESIDUE @ 0= . _FCP-THROW @ -226 = .",
        ],
        "6 -1 0 -1 -1 2 -1 -1 -1 -1 ",
    )

    check(
        "after-effect rollback delete remains explicitly uncertain",
        [
            "T-SETUP _TV @ T-FD-FREE-COUNT CONSTANT _BEFORE",
            "1 _TF-WRITE-MODE ! ' T-RM-AFTER _FCP-RM-XT ! _FCP-RUN .",
            'S" /src.txt" T-PRESENT? . S" /dest/src.txt" T-PRESENT? .',
            "VFS-CUR _TO @ = . _TV @ T-FD-FREE-COUNT _BEFORE = .",
            "_FCP-RESIDUE @ . _FCP-CLEANUP-THROW @ -228 = .",
        ],
        "10 -1 0 -1 -1 -1 -1 ",
    )

    check(
        "after-effect rollback sync remains explicitly uncertain",
        [
            "T-SETUP _TV @ T-FD-FREE-COUNT CONSTANT _BEFORE",
            "1 _TF-WRITE-MODE ! ' T-SYNC-AFTER _FCP-SYNC-XT ! _FCP-RUN .",
            'S" /src.txt" T-PRESENT? . S" /dest/src.txt" T-PRESENT? .',
            "VFS-CUR _TO @ = . _TV @ T-FD-FREE-COUNT _BEFORE = .",
            "_FCP-RESIDUE @ . _FCP-CLEANUP-THROW @ -229 = .",
        ],
        "10 -1 0 -1 -1 -1 -1 ",
    )

    check(
        "after-effect selector restore preserves publication facts",
        [
            "T-SETUP _TV @ T-FD-FREE-COUNT CONSTANT _BEFORE "
            "2 _TF-USE-THROW-AT ! ' T-USE-AFTER _FCP-USE-XT !",
            "_FCP-RUN .",
            'S" /src.txt" T-PRESENT? . S" /dest/src.txt" T-PRESENT? .',
            "VFS-CUR _TO @ = . _TV @ T-FD-FREE-COUNT _BEFORE = .",
            "_TF-USE-CALLS @ . _FCP-COMMITTED @ . _FCP-RESIDUE @ 0= .",
            "_FCP-CLEANUP-THROW @ -227 = .",
        ],
        "11 -1 -1 -1 -1 2 -1 -1 -1 ",
    )

    check(
        "after-effect cut delete reports durable-state uncertainty",
        [
            "T-SETUP _FEXP-CLIP-CUT _FEXP-CLIP-OP ! "
            "' T-RM-AFTER _FCP-RM-XT ! _FCP-RUN .",
            'S" /src.txt" T-PRESENT? . S" /dest/src.txt" T-PRESENT? .',
            "VFS-CUR _TO @ = . _FCP-COMMITTED @ . _FCP-RESIDUE @ 0= .",
            "_FCP-THROW @ -228 = .",
        ],
        "9 0 -1 -1 -1 -1 -1 ",
    )

    check(
        "cut never removes source when post-copy delete fails",
        [
            "T-SETUP _FEXP-CLIP-CUT _FEXP-CLIP-OP ! TRUE _TF-DELETE-FAIL !",
            "_FCP-RUN .",
            'S" /src.txt" T-PRESENT? . S" /dest/src.txt" T-PRESENT? .',
            'S" /dest/src.txt" T-SHOW',
        ],
        "8 -1 -1 payload-across-io ",
    )

    check(
        "successful cut verifies destination before removing source",
        [
            "T-SETUP _FEXP-CLIP-CUT _FEXP-CLIP-OP ! _FCP-RUN .",
            'S" /src.txt" T-PRESENT? . S" /dest/src.txt" T-PRESENT? .',
            'S" /dest/src.txt" T-SHOW',
        ],
        "0 0 -1 payload-across-io ",
    )

    check(
        "same-path, collision, and directory sources are rejected pre-mutation",
        [
            "T-SETUP S\" /src.txt\" _TV @ VFS-RESOLVE _FEXP-SEL-IN ! "
            "_FCP-RUN .",
            "T-SELECT-DEST S\" existing\" S\" /dest/src.txt\" T-PUT "
            "_TO @ VFS-USE _FCP-RUN .",
            "S\" /dest\" DUP _FEXP-CLIP-PATH-LEN ! "
            "_FEXP-CLIP-PATH SWAP CMOVE _FCP-RUN .",
        ],
        "3 4 1 ",
    )

    check(
        "files larger than one Explorer buffer half copy without clipping",
        [
            "T-SETUP CREATE _TBIG 20000 ALLOT _TBIG 20000 65 FILL",
            'S" /big.bin" _TP-PU ! _TP-PA ! 20000 _TP-DU ! _TBIG _TP-DA !',
            "_TP-DA @ _TP-DU @ _TP-PA @ _TP-PU @ T-PUT",
            'S" /big.bin" DUP _FEXP-CLIP-PATH-LEN ! '
            "_FEXP-CLIP-PATH SWAP CMOVE",
            'S" /big.bin" _TV @ VFS-RESOLVE _FEXP-CLIP-IN ! T-SELECT-DEST',
            "_TO @ VFS-USE _FCP-RUN .",
            'S" /dest/big.bin" _TV @ VFS-RESOLVE DUP 0<> .',
            "DUP IF IN.SIZE-LO @ 20000 = ELSE DROP FALSE THEN .",
        ],
        "0 -1 -1 ",
    )

    print(f"\nExplorer transactions: {passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
