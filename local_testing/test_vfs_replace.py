#!/usr/bin/env python3
"""Focused recovery and fault tests for utils/fs/vfs-replace.f.

The tests use the supported sibling MegaPad checkout.  Each case restores a
compiled Forth snapshot and uses a ram-backed VFS; phase tests materialize the
same target/stage/backup/marker states a persistent binding exposes after a
restart at each VFS-SYNC boundary.
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

from asm import assemble  # noqa: E402
from system import MegapadSystem  # noqa: E402


BIOS_PATH = MEGAPAD_ROOT / "bios.asm"
KDOS_PATH = MEGAPAD_ROOT / "kdos.f"
EVENT_F = AKASHIC_ROOT / "akashic" / "concurrency" / "event.f"
SEM_F = AKASHIC_ROOT / "akashic" / "concurrency" / "semaphore.f"
GUARD_F = AKASHIC_ROOT / "akashic" / "concurrency" / "guard.f"
UTF8_F = AKASHIC_ROOT / "akashic" / "text" / "utf8.f"
MEMORY_SPAN_F = AKASHIC_ROOT / "akashic" / "utils" / "memory-span.f"
CRC_F = AKASHIC_ROOT / "akashic" / "math" / "crc.f"
SHA3_F = AKASHIC_ROOT / "akashic" / "math" / "sha3.f"
VFS_F = AKASHIC_ROOT / "akashic" / "utils" / "fs" / "vfs.f"
REPLACE_F = AKASHIC_ROOT / "akashic" / "utils" / "fs" / "vfs-replace.f"


def _forth_lines(path: Path) -> list[str]:
    source: list[str] = []
    for line in path.read_text().splitlines():
        stripped = line.split("\\", 1)[0].strip()
        if not stripped:
            continue
        if stripped.startswith("REQUIRE ") or stripped.startswith("PROVIDED "):
            continue
        source.append(stripped)
    # Packing cuts UART prompt/idle round trips while allowing colon
    # compilation to span submissions.  Stay below the BIOS input limit.
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


def build_snapshot() -> None:
    global _snapshot
    if _snapshot is not None:
        return
    print("[*] Building VFS replacement snapshot ...")
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
    helpers = [
        "VARIABLE _TV",
        "CREATE _TR VREPL-SIZE ALLOT",
        "CREATE _TOUT 4096 ALLOT",
        "CREATE _BAD64 64 ALLOT _BAD64 64 88 FILL",
        "CREATE _TV-OPS VFS-OPS-SIZE ALLOT",
        "CREATE _TV-BINDING VFS-BINDING-DESC-SIZE ALLOT",
        "VARIABLE _TS-FD VARIABLE _TS-LEN",
        ": T-BINDING-RESET VFS-RAM-OPS _TV-OPS VFS-OPS-SIZE CMOVE "
        "VFS-RAM-BINDING _TV-BINDING VFS-BINDING-DESC-SIZE CMOVE "
        "_TV-OPS _TV-BINDING VB.OPS ! ;",
        ": T-VFS-NEW T-BINDING-RESET "
        "524288 A-XMEM ARENA-NEW IF -1 THROW THEN "
        "_TV-BINDING 0 VFS-NEW ?DUP IF THROW THEN ;",
        ": T-SETUP T-VFS-NEW _TV ! _TV @ VFS-USE "
        "_TV @ _TR VREPL-INIT DROP "
        'S\" /doc.txt\" S\" /doc.new\" S\" /doc.bak\" '
        'S\" /doc.txn\" _TR VREPL-PATHS! DROP _TR _VRO-R ! ;',
        ": T-PUT _TR _VRO-R ! _TV @ VFS-USE _VREPL-CREATE-WRITE ;",
        ': T-OLD-TARGET S" old" S" /doc.txt" T-PUT ;',
        ': T-NEW-STAGE S" new" S" /doc.new" T-PUT ;',
        ': T-OLD-BACKUP S" old" S" /doc.bak" T-PUT ;',
        ': T-CORRUPT-MARKER _BAD64 64 S" /doc.txn" T-PUT ;',
        ': T-SHORT-MARKER S" short" S" /doc.txn" T-PUT ;',
        "VARIABLE _TP-BUF VARIABLE _TP-LEN VARIABLE _TP-OFF "
        "VARIABLE _TP-IN VARIABLE _TP-VFS VARIABLE _TP-GUARDED",
        ": T-PART-READ _vfs-guard GUARD-MINE? _TP-GUARDED ! "
        "_TP-VFS ! _TP-IN ! _TP-OFF ! _TP-LEN ! "
        "_TP-BUF ! _TP-BUF @ _TP-LEN @ 2 MIN _TP-OFF @ "
        "_TP-IN @ _TP-VFS @ _VFS-RAM-READ ;",
        ": T-PART-WRITE _vfs-guard GUARD-MINE? _TP-GUARDED ! "
        "_TP-VFS ! _TP-IN ! _TP-OFF ! _TP-LEN ! "
        "_TP-BUF ! _TP-BUF @ _TP-LEN @ 2 MIN _TP-OFF @ "
        "_TP-IN @ _TP-VFS @ _VFS-RAM-WRITE ;",
        ": T-ZERO-XFER 2DROP 2DROP DROP 0 0 ;",
        ": T-NEG-XFER 2DROP 2DROP DROP -1 0 ;",
        ": T-LONG-XFER _TP-VFS ! _TP-IN ! _TP-OFF ! _TP-LEN ! "
        "DROP _TP-LEN @ 1+ 0 ;",
        ": T-SYNC _TV @ VFS-SYNC DROP ;",
        ": T-MARK _VRO-ORIGINAL ! S\" new\" _VRO-LEN ! _VRO-DATA ! "
        "_TR _VRO-R ! _TV @ VFS-USE _VREPL-WRITE-MARKER ;",
        ": T-SHOW VFS-OPEN DUP 0= IF DROP .\" <absent> \" EXIT THEN "
        "_TS-FD ! _TS-FD @ VFS-SIZE _TS-LEN ! "
        "_TOUT _TS-LEN @ _TS-FD @ VFS-READ _TS-LEN @ = IF "
        "_TOUT _TS-LEN @ TYPE SPACE ELSE .\" <read-error> \" THEN "
        "_TS-FD @ VFS-CLOSE ;",
        ": T-ARTIFACTS S\" /doc.new\" _TV @ VFS-RESOLVE 0<> . "
        "S\" /doc.bak\" _TV @ VFS-RESOLVE 0<> . "
        "S\" /doc.txn\" _TV @ VFS-RESOLVE 0<> . ;",
        ": T-LIE-WRITE 2DROP DROP NIP 0 ;",
        ": T-FAIL-ALL-SYNC DROP -1 ;",
        ": T-FAIL-COMMIT-SYNC DROP "
        "_VRO-TARGET? 0<> _VRO-BACKUP? 0<> AND "
        "_VRO-MARKER? 0= AND IF -1 ELSE 0 THEN ;",
        ": T-FAIL-CLEANUP-SYNC DROP "
        "_VRO-TARGET? 0<> _VRO-BACKUP? 0= AND "
        "_VRO-MARKER? 0= AND _VRO-STAGE? 0= AND "
        "IF -1 ELSE 0 THEN ;",
    ]
    sources = [
        EVENT_F, SEM_F, GUARD_F, UTF8_F, MEMORY_SPAN_F,
        CRC_F, VFS_F, SHA3_F, REPLACE_F,
    ]
    payload_lines = _forth_lines(KDOS_PATH) + ["ENTER-USERLAND"]
    for source in sources:
        if source == VFS_F:
            payload_lines.append("-1 CONSTANT GUARDED")
        payload_lines += _forth_lines(source)
    payload_lines += helpers
    data = ("\n".join(payload_lines) + "\n").encode()
    pos = 0
    steps = 0
    load_budget = 1_200_000_000
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
        if "? (not found)" in line.lower()
        or line.strip().lower() == "stack underflow"
        or "branch offset overflow" in line.lower()
    ]
    if pos < len(data) or not system.cpu.idle or errors:
        raise RuntimeError(
            f"VFS replacement load failed at {pos}/{len(data)} bytes; "
            f"idle={system.cpu.idle}, halted={system.cpu.halted}\n"
            + "\n".join(errors)
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


def run_forth(lines: list[str], max_steps: int = 120_000_000) -> str:
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
    tokens = [
        token for token in results.split()
        if token not in ("Bye!", "ok", ">")
    ]
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
            f"        output {output!r}"
        )


def main() -> int:
    build_snapshot()

    check(
        "paths must be distinct, normalized, same-parent, and MP64FS-safe",
        [
            "T-VFS-NEW CONSTANT _V _V _TR VREPL-INIT DROP",
            ': TP1 S" /a" S" /a" S" /a.b" S" /a.m" '
            '_TR VREPL-PATHS! . ; TP1',
            ': TP2 S" /a" S" /x/a.s" S" /a.b" S" /a.m" '
            '_TR VREPL-PATHS! . ; TP2',
            ': TP3 S" /this-component-is-over-23" S" /a.s" S" /a.b" '
            'S" /a.m" _TR VREPL-PATHS! . ; TP3',
        ],
        "3 3 3 ",
    )

    check(
        "derived companions are deterministic, distinct, and MP64FS-safe",
        [
            "T-VFS-NEW CONSTANT _DV CREATE _TR2 VREPL-SIZE ALLOT "
            "CREATE _TR3 VREPL-SIZE ALLOT",
            "_DV _TR VREPL-INIT DROP _DV _TR2 VREPL-INIT DROP "
            "_DV _TR3 VREPL-INIT DROP",
            ': TD1 S" /nested/abcdefghijklmnopqrstuvw" '
            '_TR VREPL-DERIVE-PATHS! . ; TD1',
            ': TD2 S" /nested/abcdefghijklmnopqrstuvw" '
            '_TR2 VREPL-DERIVE-PATHS! . ; TD2',
            ': TD3 S" /nested/abcdefghijklmnopqrstuvx" '
            '_TR3 VREPL-DERIVE-PATHS! . ; TD3',
            ': TDT S" /nested/abcdefghijklmnopqrstuvw" '
            '_TR VREPL.TARGET _TR VREPL.TARGET-LEN @ COMPARE 0= . ; TDT',
            "_TR VREPL.STAGE _TR VREPL.STAGE-LEN @ TYPE SPACE",
            "_TR VREPL.STAGE-LEN @ . _TR VREPL.BACKUP-LEN @ . "
            "_TR VREPL.MARKER-LEN @ .",
            "_TR VREPL.TARGET-BASE @ . _TR VREPL.STAGE-BASE @ . "
            "_TR VREPL.BACKUP-BASE @ . _TR VREPL.MARKER-BASE @ .",
            "_TR VREPL.STAGE _TR VREPL.STAGE-BASE @ + 1+ C@ EMIT SPACE "
            "_TR VREPL.BACKUP _TR VREPL.BACKUP-BASE @ + 1+ C@ EMIT "
            "SPACE _TR VREPL.MARKER _TR VREPL.MARKER-BASE @ + 1+ "
            "C@ EMIT SPACE",
            "_TR VREPL.STAGE _TR VREPL.STAGE-LEN @ "
            "_TR VREPL.BACKUP _TR VREPL.BACKUP-LEN @ COMPARE 0<> . "
            "_TR VREPL.STAGE _TR VREPL.STAGE-LEN @ "
            "_TR VREPL.MARKER _TR VREPL.MARKER-LEN @ COMPARE 0<> . "
            "_TR VREPL.BACKUP _TR VREPL.BACKUP-LEN @ "
            "_TR VREPL.MARKER _TR VREPL.MARKER-LEN @ COMPARE 0<> .",
            "_TR VREPL.STAGE _TR VREPL.STAGE-LEN @ _TR2 VREPL.STAGE "
            "_TR2 VREPL.STAGE-LEN @ COMPARE 0= . "
            "_TR VREPL.BACKUP _TR VREPL.BACKUP-LEN @ _TR2 VREPL.BACKUP "
            "_TR2 VREPL.BACKUP-LEN @ COMPARE 0= . "
            "_TR VREPL.MARKER _TR VREPL.MARKER-LEN @ _TR2 VREPL.MARKER "
            "_TR2 VREPL.MARKER-LEN @ COMPARE 0= .",
            "_TR VREPL.STAGE _TR VREPL.STAGE-LEN @ _TR3 VREPL.STAGE "
            "_TR3 VREPL.STAGE-LEN @ COMPARE 0<> .",
        ],
        "0 0 0 -1 /nested/.s-oerpusoag7zz5eenay2w "
        "31 31 31 8 8 8 8 s b m -1 -1 -1 -1 -1 -1 -1 ",
    )

    check(
        "derivation rejects reserved targets and parent-length overflow",
        [
            "T-VFS-NEW CONSTANT _DV _DV _TR VREPL-INIT DROP",
            ': TDR1 S" /.s-user" _TR VREPL-DERIVE-PATHS! . ; TDR1',
            ': TDR2 S" /.b-user" _TR VREPL-DERIVE-PATHS! . ; TDR2',
            ': TDR3 S" /.m-user" _TR VREPL-DERIVE-PATHS! . ; TDR3',
            "CREATE _LONG 256 ALLOT",
            ": TDR4 _LONG 250 97 FILL 47 _LONG C! "
            "11 1 DO 47 _LONG I 24 * + C! LOOP "
            "_LONG 250 _TR VREPL-DERIVE-PATHS! . ; TDR4",
        ],
        "3 3 3 3 ",
    )

    check(
        "derived paths drive the complete replacement protocol",
        [
            "T-VFS-NEW _TV ! _TV @ VFS-USE _TV @ _TR VREPL-INIT DROP",
            ': TDP S" /doc.txt" _TR VREPL-DERIVE-PATHS! . ; TDP',
            "_TR _VRO-R !",
            'S" old" S" /doc.txt" T-PUT . T-SYNC',
            'S" new" _TR VREPL-REPLACE . S" /doc.txt" T-SHOW',
            "_TR VREPL-STAGE$ _TV @ VFS-RESOLVE 0<> . "
            "_TR VREPL-BACKUP$ _TV @ VFS-RESOLVE 0<> . "
            "_TR VREPL-MARKER$ _TV @ VFS-RESOLVE 0<> .",
        ],
        "0 0 0 new 0 0 0 ",
    )

    check(
        "exact I/O loops legal partial transfers under one VFS guard",
        [
            "T-SETUP S\" /exact.txt\" _TV @ VFS-CREATE DROP "
            "S\" /exact.txt\" VFS-OPEN CONSTANT _EFD",
            "0 _TP-GUARDED ! ' T-PART-WRITE _TV-OPS "
            "VFS-OP-WRITE CELLS + !",
            'S" hello" _EFD VFS-WRITE-EXACT . _TP-GUARDED @ . '
            '_EFD VFS-TELL .',
            "_EFD VFS-REWIND 0 _TP-GUARDED ! ' T-PART-READ "
            "_TV-OPS VFS-OP-READ CELLS + !",
            "_TOUT 5 _EFD VFS-READ-EXACT . _TP-GUARDED @ . "
            "_TOUT 5 TYPE SPACE _EFD VFS-TELL . _EFD VFS-CLOSE",
        ],
        "0 -1 5 0 -1 hello 5 ",
    )

    check(
        "exact I/O rejects stalled and invalid binding counts",
        [
            "T-SETUP S\" /exact.txt\" _TV @ VFS-CREATE DROP "
            "S\" /exact.txt\" VFS-OPEN CONSTANT _EFD",
            "' T-ZERO-XFER _TV-OPS VFS-OP-WRITE CELLS + ! "
            'S" ab" _EFD VFS-WRITE-EXACT . _EFD VFS-TELL .',
            "' T-NEG-XFER _TV-OPS VFS-OP-WRITE CELLS + ! "
            'S" ab" _EFD VFS-WRITE-EXACT . _EFD VFS-TELL .',
            "' T-LONG-XFER _TV-OPS VFS-OP-WRITE CELLS + ! "
            'S" ab" _EFD VFS-WRITE-EXACT . _EFD VFS-TELL .',
            "_TOUT -1 _EFD VFS-WRITE-EXACT . "
            "0 2 _EFD VFS-WRITE-EXACT . 0 0 _EFD VFS-WRITE-EXACT .",
            "_EFD VFS-REWIND ' T-ZERO-XFER _TV-OPS "
            "VFS-OP-READ CELLS + ! _TOUT 2 _EFD VFS-READ-EXACT . "
            "_EFD VFS-TELL .",
            "' T-NEG-XFER _TV-OPS VFS-OP-READ CELLS + ! "
            "_TOUT 2 _EFD VFS-READ-EXACT . _EFD VFS-TELL .",
            "' T-LONG-XFER _TV-OPS VFS-OP-READ CELLS + ! "
            "_TOUT 2 _EFD VFS-READ-EXACT . _EFD VFS-TELL .",
        ],
        "9 0 67108874 0 67108874 0 1 1 0 9 0 67108874 0 67108874 0 ",
    )

    check(
        "VFS transaction holds the recursive public guard",
        [
            "T-SETUP",
            ': T-TX _vfs-guard GUARD-MINE? . '
            '_TV @ VFS-CUR = . ;',
            "' T-TX VFS-TRANSACTION",
        ],
        "-1 -1 ",
    )

    check(
        "VFS transaction excludes an unrelated full-core caller",
        [
            "T-SETUP VARIABLE _TX-START VARIABLE _TX-DONE "
            "0 _TX-START ! 0 _TX-DONE !",
            ": T-TX-WORKER -1 _TX-START ! VFS-CUR DROP "
            "-1 _TX-DONE ! ;",
            ": T-TX-HOLDER ['] T-TX-WORKER 1 CORE-RUN "
            "BEGIN _TX-START @ 0= WHILE YIELD? REPEAT "
            "2000 0 DO I DROP LOOP _TX-DONE @ . ;",
            "' T-TX-HOLDER VFS-TRANSACTION",
            "1 CORE-WAIT _TX-DONE @ .",
        ],
        "0 -1 ",
    )

    check(
        "replacement restores caller VFS context before unlock",
        [
            "T-SETUP T-VFS-NEW CONSTANT _OTHER _OTHER VFS-USE",
            'S" new" _TR VREPL-REPLACE .',
            "VFS-CUR _OTHER = .",
        ],
        "0 -1 ",
    )

    check(
        "existing target replacement commits and cleans companions",
        [
            "T-SETUP",
            "T-OLD-TARGET DROP T-SYNC",
            'S" new" _TR VREPL-REPLACE .',
            'S" /doc.txt" T-SHOW T-ARTIFACTS',
        ],
        "0 new 0 0 0 ",
    )

    check(
        "absent target can be created through the same protocol",
        [
            "T-SETUP",
            'S" new" _TR VREPL-REPLACE .',
            'S" /doc.txt" T-SHOW T-ARTIFACTS',
        ],
        "0 new 0 0 0 ",
    )

    check(
        "owner precondition rejects before staging",
        [
            "T-SETUP",
            "T-OLD-TARGET DROP T-SYNC",
            ": T-REJECT 2DROP 17 ;",
            "' T-REJECT 0 _TR VREPL-PRECONDITION! DROP",
            'S" new" _TR VREPL-REPLACE .',
            'S" /doc.txt" T-SHOW T-ARTIFACTS',
        ],
        "5 old 0 0 0 ",
    )

    check(
        "throwing owner precondition fails closed without leaking stack cells",
        [
            "T-SETUP DEPTH CONSTANT _PRE-DEPTH",
            ": T-PRE-THROW 2DROP -77 THROW ;",
            "' T-PRE-THROW 0 _TR VREPL-PRECONDITION! DROP",
            'S" new" _TR VREPL-REPLACE . DEPTH _PRE-DEPTH = .',
            "T-ARTIFACTS",
        ],
        "5 -1 0 0 0 ",
    )

    check(
        "precondition cannot recursively replace another descriptor",
        [
            "T-SETUP CREATE _TR2 VREPL-SIZE ALLOT",
            "_TV @ _TR2 VREPL-INIT DROP",
            ': TC2 S" /two.txt" S" /two.new" S" /two.bak" '
            'S" /two.txn" _TR2 VREPL-PATHS! DROP ; TC2',
            "VARIABLE _NESTED",
            ': T-NESTED 2DROP S" nested" _TR2 VREPL-REPLACE '
            '_NESTED ! 0 ;',
            "' T-NESTED 0 _TR VREPL-PRECONDITION! DROP",
            'S" new" _TR VREPL-REPLACE . _NESTED @ .',
        ],
        "0 6 ",
    )

    check(
        "reserved path collision with directory fails closed",
        [
            "T-SETUP",
            'S" doc.txt" _TV @ VFS-MKDIR .',
            'S" new" _TR VREPL-REPLACE .',
            'S" /doc.txt" _TV @ VFS-RESOLVE IN.TYPE @ . T-ARTIFACTS',
        ],
        "0 7 2 0 0 0 ",
    )

    check(
        "lying write is caught by readback before target mutation",
        [
            "T-SETUP",
            "T-OLD-TARGET DROP T-SYNC",
            "' T-LIE-WRITE _TV-OPS VFS-OP-WRITE CELLS + !",
            'S" new" _TR VREPL-REPLACE .',
            "' _VFS-RAM-WRITE _TV-OPS VFS-OP-WRITE CELLS + !",
            'S" /doc.txt" T-SHOW T-ARTIFACTS',
        ],
        "4 old 0 0 0 ",
    )

    check(
        "pre-rotation sync failure retains old target",
        [
            "T-SETUP T-OLD-TARGET DROP T-SYNC",
            "' T-FAIL-ALL-SYNC _TV-OPS VFS-OP-SYNCFS CELLS + !",
            'S" new" _TR VREPL-REPLACE .',
            "' _VFS-RAM-SYNCFS _TV-OPS VFS-OP-SYNCFS CELLS + !",
            'S" /doc.txt" T-SHOW T-ARTIFACTS',
        ],
        "4 old 0 0 0 ",
    )

    check(
        "commit-marker sync failure reports uncertain and keeps backup",
        [
            "T-SETUP T-OLD-TARGET DROP T-SYNC",
            "' T-FAIL-COMMIT-SYNC _TV-OPS VFS-OP-SYNCFS CELLS + !",
            'S" new" _TR VREPL-REPLACE .',
            "' _VFS-RAM-SYNCFS _TV-OPS VFS-OP-SYNCFS CELLS + !",
            'S" /doc.txt" T-SHOW T-ARTIFACTS',
        ],
        "9 new 0 -1 0 ",
    )

    check(
        "post-commit cleanup sync failure reports committed cleanup",
        [
            "T-SETUP T-OLD-TARGET DROP T-SYNC",
            "' T-FAIL-CLEANUP-SYNC _TV-OPS VFS-OP-SYNCFS CELLS + !",
            'S" new" _TR VREPL-REPLACE .',
            "' _VFS-RAM-SYNCFS _TV-OPS VFS-OP-SYNCFS CELLS + !",
            'S" /doc.txt" T-SHOW T-ARTIFACTS',
        ],
        "2 new 0 0 0 ",
    )

    # Crash after stage sync, before marker creation.
    check(
        "recover phase: verified stage without marker",
        [
            "T-SETUP",
            "T-OLD-TARGET DROP",
            "T-NEW-STAGE DROP T-SYNC",
            "_TR VREPL-RECOVER .",
            'S" /doc.txt" T-SHOW T-ARTIFACTS',
        ],
        "0 old 0 0 0 ",
    )

    # Crash after intent sync, before target rotation.
    check(
        "recover phase: durable marker before rotation",
        [
            "T-SETUP",
            "T-OLD-TARGET DROP",
            "T-NEW-STAGE DROP T-SYNC",
            "-1 T-MARK DROP T-SYNC",
            "_TR VREPL-RECOVER .",
            'S" /doc.txt" T-SHOW T-ARTIFACTS',
        ],
        "1 old 0 0 0 ",
    )

    # Crash after old target has become backup.
    check(
        "recover phase: backup and stage restore old target",
        [
            "T-SETUP",
            "T-OLD-TARGET DROP",
            "T-NEW-STAGE DROP T-SYNC",
            "-1 T-MARK DROP T-SYNC",
            "_VRO-TARGET>BACKUP DROP T-SYNC",
            "_TR VREPL-RECOVER .",
            'S" /doc.txt" T-SHOW T-ARTIFACTS',
        ],
        "1 old 0 0 0 ",
    )

    # Crash after candidate has target name but marker still denotes rollback.
    check(
        "recover phase: marked promoted target rolls back",
        [
            "T-SETUP",
            "T-OLD-TARGET DROP",
            "T-NEW-STAGE DROP T-SYNC",
            "-1 T-MARK DROP T-SYNC",
            "_VRO-TARGET>BACKUP DROP T-SYNC",
            "_VRO-STAGE>TARGET DROP T-SYNC",
            "_TR VREPL-RECOVER .",
            'S" /doc.txt" T-SHOW T-ARTIFACTS',
        ],
        "1 old 0 0 0 ",
    )

    # Crash after marker removal was synced, before backup cleanup.
    check(
        "recover phase: unmarked promoted target wins",
        [
            "T-SETUP",
            "T-OLD-TARGET DROP",
            "T-NEW-STAGE DROP T-SYNC",
            "-1 T-MARK DROP T-SYNC",
            "_VRO-TARGET>BACKUP DROP T-SYNC",
            "_VRO-STAGE>TARGET DROP T-SYNC",
            "_VRO-RM-MARKER DROP T-SYNC",
            "_TR VREPL-RECOVER .",
            'S" /doc.txt" T-SHOW T-ARTIFACTS',
        ],
        "0 new 0 0 0 ",
    )

    check(
        "recover phase: absent original rolls back to absence",
        [
            "T-SETUP",
            "T-NEW-STAGE DROP T-SYNC",
            "0 T-MARK DROP T-SYNC",
            "_VRO-STAGE>TARGET DROP T-SYNC",
            "_TR VREPL-RECOVER .",
            'S" /doc.txt" T-SHOW T-ARTIFACTS',
        ],
        "1 <absent> 0 0 0 ",
    )

    check(
        "unmarked missing target restores known backup",
        [
            "T-SETUP",
            "T-OLD-BACKUP DROP T-SYNC",
            "_TR VREPL-RECOVER .",
            'S" /doc.txt" T-SHOW T-ARTIFACTS',
        ],
        "1 old 0 0 0 ",
    )

    check(
        "corrupt marker fails closed and preserves backup",
        [
            "T-SETUP",
            "T-OLD-BACKUP DROP",
            "T-NEW-STAGE DROP",
            "T-CORRUPT-MARKER DROP T-SYNC",
            "_TR VREPL-RECOVER . T-ARTIFACTS",
        ],
        "8 -1 -1 -1 ",
    )

    check(
        "marker target-hash mismatch fails closed and preserves artifacts",
        [
            "T-SETUP T-OLD-BACKUP DROP T-NEW-STAGE DROP "
            "-1 T-MARK DROP T-SYNC",
            ': T-REBIND S" /other.txt" S" /doc.new" S" /doc.bak" '
            'S" /doc.txn" _TR VREPL-PATHS! . ; T-REBIND',
            "_TR VREPL-RECOVER . T-ARTIFACTS",
        ],
        "0 8 -1 -1 -1 ",
    )

    check(
        "short marker read has distinct fail-closed status",
        [
            "T-SETUP",
            "T-OLD-BACKUP DROP",
            "T-NEW-STAGE DROP",
            "T-SHORT-MARKER DROP T-SYNC",
            "_TR VREPL-RECOVER . T-ARTIFACTS",
        ],
        "8 -1 -1 -1 ",
    )

    print(f"\n{passed}/{passed + failed} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
