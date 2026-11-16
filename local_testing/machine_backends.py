#!/usr/bin/env python3
"""Run Akashic's ext4 journeys on MegaPad's emulator or on its simulator.

The emulator executes the MP64 instruction set, the BIOS and the storage
controller one beat at a time; it is the device-faithful reference.  The
simulator runs the same BIOS words, KDOS and Akashic source semantically,
in native code, and its storage service takes the same test faults and
records the same requests as the emulator's controller (MegaPad
docs/storage-faults.md).  ``AKASHIC_EXT4_BACKEND`` chooses where the ext4
tests run their journeys: ``emulator``, the default, or ``simulator``.  A
test that reads the emulator's processor state or its cycle counter runs on
the emulator whichever is chosen.

Either way a journey reports what each of its lines printed, without the
BIOS's echo of the line or its prompt, so a test's checks read the same
text from both machines.  Step budgets are written in emulator
instructions; ``budget`` gives the simulator's share of one.
"""

from __future__ import annotations

import math
import os
import re

BACKENDS = ("emulator", "simulator")
BACKEND = os.environ.get("AKASHIC_EXT4_BACKEND", "emulator")
if BACKEND not in BACKENDS:
    raise RuntimeError(
        f"AKASHIC_EXT4_BACKEND must be one of {', '.join(BACKENDS)}, "
        f"not {BACKEND!r}"
    )

# The simulator counts semantic steps, the emulator instructions.  On the
# standing ext4 sample the simulator's journeys took 0.12 to 0.21 of the
# emulator's steps for the same work, so a budget keeps the same margin on
# both when the simulator's is a quarter of the emulator's.
SIMULATOR_STEPS_PER_INSTRUCTION = 0.25


def chosen(backend: str | None = None) -> str:
    """BACKEND, or the backend the run chose."""

    backend = BACKEND if backend is None else backend
    if backend not in BACKENDS:
        raise ValueError(f"unknown machine backend {backend!r}")
    return backend


def budget(instructions: int, backend: str) -> int:
    """A step budget written in emulator instructions, for BACKEND."""

    if backend == "emulator":
        return instructions
    return max(1, math.ceil(instructions * SIMULATOR_STEPS_PER_INSTRUCTION))


class Printed(str):
    """What a journey printed: each line's output, joined by newlines.

    ``lines`` holds what each line printed, and ``complete`` whether it ran
    to its end, so a check can ask what one line printed.
    """

    lines: tuple[str, ...]
    complete: tuple[bool, ...]

    def __new__(cls, lines, complete):
        text = super().__new__(cls, "\n".join(lines))
        text.lines = tuple(lines)
        text.complete = tuple(complete)
        return text

    def emitted(self, marker: str) -> bool:
        """Whether a line printed MARKER as the whole of its output, or as
        the last of the lines its output holds."""

        return any(
            line == marker or line.endswith("\r\n" + marker)
            for line in self.lines
        )


def printable(sent) -> str:
    """The text of UART bytes SENT, without control bytes other than tab,
    CR and LF, as a terminal would show it."""

    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (9, 10, 13)) else ""
        for b in sent
    )


# ---------------------------------------------------------------------------
#  The emulator: the BIOS reads a line, echoes it and prompts again
# ---------------------------------------------------------------------------

def emulator_journey(system, sent, lines, max_steps: int) -> tuple[Printed, int]:
    """Feed LINES to the BIOS of SYSTEM, each when it waits for input, and
    return what each printed with the instructions run.

    SENT is the list the UART's bytes are captured into.  A line the budget
    left unread is missing from the result.  The BIOS echoes each line it
    reads and then prints a CR LF; when the line has run in interpreting
    state it prints `` ok`` and CR LF, then the ``> `` prompt before the
    next.  A line inside a definition prints neither.  A line that fails
    prints its diagnostic and the prompt without `` ok``.
    """

    starts = []
    steps = 0
    fed = 0
    while steps < max_steps:
        cpu = system.cpu
        if cpu.halted:
            break
        if cpu.idle and not system.uart.has_rx_data:
            if fed == len(lines):
                break
            starts.append(len(sent))
            system.uart.inject_input((lines[fed] + "\n").encode())
            fed += 1
            continue
        steps += max(system.run_batch(min(100_000, max_steps - steps)), 1)
    ends = [*starts[1:], len(sent)]
    printed = []
    complete = []
    for line, start, end in zip(lines, starts, ends):
        text, ran = _without_echo(printable(sent[start:end]), line)
        printed.append(text)
        complete.append(ran)
    return Printed(printed, complete), steps


def _without_echo(text: str, line: str) -> tuple[str, bool]:
    echo = "".join(ch for ch in line if " " <= ch <= "~")
    end = text.find("\r\n")
    if end < 0 or not echo.startswith(text[:end]):
        # The line was not read whole, as when a budget ends mid-line; what
        # the machine sent is kept as printed.
        return text, False
    # The echo is the line as read, which a shorter line buffer would cut.
    body = text[end + 2:]
    if body.endswith(" ok\r\n> "):
        return body[:-len(" ok\r\n> ")], True
    if body.endswith("> "):
        return body[:-len("> ")], False
    return body, True


# ---------------------------------------------------------------------------
#  The simulator: complete source evaluated a statement at a time
# ---------------------------------------------------------------------------

# Words that open and close what must be evaluated whole: a definition, and
# control structures interpreted outside one.
_OPENERS = {":", ":NONAME", "IF", "BEGIN", "DO", "?DO", "CASE"}
_CLOSERS = {";", "THEN", "UNTIL", "AGAIN", "REPEAT", "LOOP", "+LOOP", "ENDCASE"}
# Words that take the next name from the source.
_NAMING = {"CHAR", "[CHAR]", "'", "[']", "POSTPONE", "[COMPILE]", "CREATE",
           "VARIABLE", "2VARIABLE", "CONSTANT", "2CONSTANT", "VALUE", "TO",
           "DEFER", "IS", "BUFFER:", "FVARIABLE", "FCONSTANT", "MARKER"}
_STRINGS = {'."': '"', 'S"': '"', 'C"': '"', 'ABORT"': '"', ".(": ")",
            'S\\"': '"', 'Z"': '"'}


def statements(lines: list[str]) -> list[list[str]]:
    """LINES in runs that each complete a definition or control structure.

    The BIOS reads its terminal a line at a time and carries a definition
    or an interpreted IF from one line to the next.  The simulator
    evaluates complete source, so lines that leave one open are evaluated
    with the lines that close it.
    """

    groups = []
    current: list[str] = []
    depth = 0
    for line in lines:
        current.append(line)
        depth = max(0, depth + _depth_change(line))
        if depth == 0:
            groups.append(current)
            current = []
    if current:
        groups.append(current)
    return groups


_TOKEN = re.compile(r"\S+")


def _depth_change(line: str) -> int:
    """How many definitions and control structures LINE leaves open, less
    those it closes; comments, strings and names are skipped."""

    change = 0
    position = 0
    while True:
        match = _TOKEN.search(line, position)
        if match is None:
            break
        word = match.group().upper()
        position = match.end()
        if word == "\\":
            break
        if word == "(":
            end = line.find(")", position)
            if end < 0:
                break
            position = end + 1
        elif word in _STRINGS:
            end = line.find(_STRINGS[word], position + 1)
            if end < 0:
                break
            position = end + 1
        elif word in _NAMING:
            name = _TOKEN.search(line, position)
            if name is None:
                break
            position = name.end()
        elif word in _OPENERS:
            change += 1
        elif word in _CLOSERS:
            change -= 1
    return change


def simulator_journey(runtime, lines, max_steps: int) -> tuple[Printed, int]:
    """Evaluate LINES on RUNTIME a statement at a time and return what each
    printed with the semantic steps run.

    A statement's output is reported as its last line's.  An error ends the
    journey: its message follows what the failing statement printed, that
    line is marked incomplete, and the lines after it are missing.
    """

    from simulator.errors import SimulatorError
    from simulator.stacks import StackError

    printed: list[str] = []
    complete: list[bool] = []
    steps = 0
    for group in statements(list(lines)):
        source = ("\n".join(group) + "\n").encode()
        ran = True
        error = ""
        try:
            result = runtime.evaluate(
                source,
                source_name="journey",
                step_budget=max(0, max_steps - steps),
            )
            steps += result.semantic_steps
        except (SimulatorError, StackError) as raised:
            ran = False
            error = f"\r\n?? {type(raised).__name__}: {raised}"
        text = printable(runtime.drain_uart_output()) + error
        printed.extend([""] * (len(group) - 1) + [text])
        complete.extend([True] * (len(group) - 1) + [ran])
        if not ran:
            break
    return Printed(printed, complete), steps
