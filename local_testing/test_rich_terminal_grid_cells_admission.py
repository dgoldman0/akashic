"""Execute the bounded GRID_CELLS gate on the production Forth helpers.

The Python and native semantic backends compile unchanged helper closures.
Only the PT outbound-payload query used by limits copying is a fixed spy;
these tests neither boot Desktop nor model the Forth scanner in Python.
"""

from __future__ import annotations

import os
from pathlib import Path
import re
import struct
import sys

import pytest


ROOT = Path(__file__).resolve().parents[1]
RICH = ROOT / "akashic/tui/rich-terminal"
PAIRED = ROOT.parent / ROOT.name.replace("akashic-", "megapad-", 1)
MEGAPAD_ROOT = Path(os.environ.get(
    "MEGAPAD_ROOT", PAIRED if PAIRED != ROOT and PAIRED.is_dir()
    else ROOT.parent / "megapad"
))
sys.path.insert(0, str(MEGAPAD_ROOT))

from simulator.runtime import MegaForthRuntime  # noqa: E402


MASK64 = (1 << 64) - 1
SENTINEL = 0x1728394051627384
CORE_COLLECTIONS = 0xC1
GRID_CELLS = 0x2000
HEADER = struct.Struct("<IHHQIIIIIIIIQQII")
ITEM = struct.Struct("<QIIIIHHII")
SOURCES = (
    ROOT / "akashic/utils/uint-range.f",
    ROOT / "akashic/utils/memory-span.f",
    RICH / "stx1-roles.f",
    RICH / "engine.f",
    RICH / "apt1-engine.f",
    RICH / "engine-apt1.f",
)


def _definitions(source: str) -> dict[str, str]:
    source = re.sub(r"(?m)\\[^\n]*$", "", source)
    declarations = {}
    for match in re.finditer(r"(?ms)^: (\S+)(?=\s).*?;[ \t]*$", source):
        declarations[match[1]] = match[0]
    for match in re.finditer(r"(?m)^VARIABLE (\S+)\s*$", source):
        declarations[match[1]] = match[0]
    for match in re.finditer(
        r"(?m)^\s*(-?(?:0x[0-9A-Fa-f]+|[0-9]+))\s+CONSTANT\s+(\S+)",
        source,
    ):
        declarations[match[2]] = match[0]
    return declarations


def _word(source: str, name: str) -> str:
    return _definitions(source)[name]


def _stx1(items=()) -> bytes:
    """Encode exact framing; geometry and text semantics are not this gate."""
    result = bytearray(HEADER.pack(
        0x31585453, 1, 0, 1, 1, 80, 0, 0, 1, 80,
        len(items), 1, 0, 0, 0, 0,
    ))
    for index, (role, text, runs) in enumerate(items):
        result.extend(ITEM.pack(index + 1, 0, index * 8, 1, 8,
                                role, 0, len(text), runs))
        result.extend(text)
        result.extend(struct.pack("<III", 0, 1, 1) * runs)
    return bytes(result)


def _changed(payload: bytes, offset: int, fmt: str, value: int) -> bytes:
    changed = bytearray(payload)
    struct.pack_into(fmt, changed, offset, value)
    return bytes(changed)


def _control_copy(payload: bytes, *, kind=6, label=b"", shortcut=b"") -> bytes:
    # Existing retry-copy ABI: twenty native cells, then three byte spans.
    fixed = struct.pack("<20Q", 1, 1, 1, kind, 3, 0, 1, 0, 0,
                        0, 0, 80, 1, len(label), len(shortcut), len(payload),
                        0, 0, 0, 0)
    raw = fixed + label + shortcut + payload
    return raw + bytes((-len(raw)) & 7)


class GridGateHarness:
    def __init__(self, backend: str):
        self.definitions = {}
        for source in SOURCES:
            self.definitions.update(_definitions(source.read_text()))
        self.definitions["PT-OUTBOUND-MAX-PAYLOAD@"] = (
            ": PT-OUTBOUND-MAX-PAYLOAD@ ( session -- bytes ) DROP 512 ;"
        )
        chunks, included = [], set()

        def include(name):
            if name in included:
                return
            included.add(name)
            declaration = self.definitions[name]
            code = re.sub(r"\([^)]*\)", "", declaration)
            for token in code.split():
                if token != name and token in self.definitions:
                    include(token)
            chunks.append(declaration)

        for name in (
            "STX1R-ROLES?", "_RTAPT-GRID-CONTENT-STATUS",
            "_RTAPT-CONTROL-COPY-GRID-STATUS", "RTE-LIMITS-VALID?",
            "RTAPT-LIMITS-VALID?", "_RTAPT-LIMITS-COPY",
            "_RTAPTE-FEATURES>RTE",
        ):
            include(name)
        self.runtime = MegaForthRuntime(execution_backend=backend)
        self.runtime.evaluate("\n".join(chunks).encode(),
                              source_name="production-grid-cells-gates.f",
                              step_budget=3_000_000)
        self.serial = 0
        self.spans = []

    def allocate(self, payload: bytes, *, unaligned=False) -> int:
        self.serial += 1
        word = self.runtime.define_created(
            f"GRID-GATE-{self.serial}", initial_body=bytes(len(payload) + 32)
        )
        start = (word.body_address + 7) & -8
        address = start + 8 + int(unaligned)
        self.runtime.memory.write_bytes(start, b"L" * (address - start))
        self.runtime.memory.write_bytes(address, payload)
        self.runtime.memory.write_bytes(address + len(payload), b"RIGHTEND")
        self.spans.append((start, address + len(payload) + 8 - start))
        return address

    def variable(self, name, value):
        word = self.runtime.find(name)
        assert word is not None, name
        self.runtime.memory.write64(word.body_address, value)

    def call(self, name, *inputs, readonly=True):
        data = self.runtime.main_context.data
        assert data.snapshot() == ()
        before = [(address, self.runtime.memory.read_bytes(address, size))
                  for address, size in self.spans] if readonly else []
        for value in (SENTINEL, *inputs):
            data.push(value)
        self.runtime.execute(name, step_budget=3_000_000)
        result = data.snapshot()
        data.clear()
        assert result[0] == SENTINEL, (name, result)
        assert self.runtime.main_context.returns.snapshot() == (), name
        for address, payload in before:
            assert self.runtime.memory.read_bytes(address, len(payload)) == payload
        return result[1:]


@pytest.fixture(scope="module", params=("python", "native"))
def gate(request):
    return GridGateHarness(request.param)


@pytest.mark.parametrize("items,typed", [
    ((), False),
    (((1, b"", 0),), False),
    (((1, b"a", 0), (2, b"header", 0), (3, b"x", 0)), False),
    (((4, b"42", 0),), True),
    (((5, b"6*7", 0),), True),
    (((6, b"#N/A", 0),), True),
    (((1, b"prefix", 0), (4, b"42", 0)), True),
    (((1, b"a", 0), (2, b"unequal", 0), (6, b"error", 0)), True),
    # Style tails must be skipped before the next item header. This is a
    # framing-only value, not a claim that GRID permits style runs.
    (((1, b"abc", 2), (5, b"formula", 0)), True),
    # The narrow role gate does not duplicate UTF-8 or geometry validation.
    (((4, b"\xff", 0),), True),
])
def test_stx1_roles_follow_each_packed_item(gate, items, typed):
    payload = _stx1(items)
    address = gate.allocate(payload, unaligned=True)
    assert gate.call("STX1R-ROLES?", address, len(payload)) == (
        MASK64 if typed else 0, MASK64,
    )


def _malformed():
    payload = _stx1(((1, b"a", 0), (4, b"42", 0)))
    for name, offset, fmt, value in (
        ("tag", 0, "<I", 0), ("version", 4, "<H", 2),
        ("reserved", 6, "<H", 1), ("too-few-items", 40, "<I", 1),
        ("too-many-items", 40, "<I", 3),
        ("huge-item-count", 40, "<I", 0xFFFFFFFF),
        ("zero-role", 72 + 24, "<H", 0),
        ("unknown-role", 72 + 24, "<H", 7),
        ("huge-role", 72 + 24, "<H", 0xFFFF),
        ("second-role", 72 + 37 + 24, "<H", 7),
        ("huge-text", 72 + 28, "<I", 0xFFFFFFFF),
        ("huge-runs", 72 + 32, "<I", 0xFFFFFFFF),
        ("missing-run-tail", 72 + 37 + 32, "<I", 1),
    ):
        yield pytest.param(_changed(payload, offset, fmt, value), id=name)
    for length in (0, 71, 72, 107, len(payload) - 1):
        yield pytest.param(payload[:length], id=f"truncated-{length}")
    yield pytest.param(payload + b"x", id="trailing-byte")


@pytest.mark.parametrize("payload", list(_malformed()))
def test_stx1_rejects_malformed_framing_without_writes(gate, payload):
    address = gate.allocate(payload)
    result = gate.call("STX1R-ROLES?", address, len(payload))
    assert len(result) == 2 and result[1] == 0
    assert gate.call("_RTAPT-GRID-CONTENT-STATUS", address, len(payload),
                     6, CORE_COLLECTIONS | GRID_CELLS) == (3,)


@pytest.mark.parametrize("address,length", [
    (0, 72), (1, 0), (1, 71), (MASK64 - 31, 72), (MASK64, 72),
])
def test_stx1_refuses_absent_short_or_wrapping_spans(gate, address, length):
    assert gate.call("STX1R-ROLES?", address, length) == (0, 0)


@pytest.mark.parametrize("role", (1, 2, 3, 4, 5, 6))
def test_grid_role_capability_is_explicit(gate, role):
    payload = _stx1(((1, b"prefix", 0), (role, b"value", 0)))
    address = gate.allocate(payload)
    expected = 4 if role >= 4 else 0
    assert gate.call("_RTAPT-GRID-CONTENT-STATUS", address, len(payload),
                     6, CORE_COLLECTIONS) == (expected,)
    assert gate.call("_RTAPT-GRID-CONTENT-STATUS", address, len(payload),
                     6, CORE_COLLECTIONS | GRID_CELLS) == (0,)
    if role >= 4:
        for features in (CORE_COLLECTIONS, CORE_COLLECTIONS | GRID_CELLS):
            assert gate.call("_RTAPT-GRID-CONTENT-STATUS", address,
                             len(payload), 5, features) == (3,)


@pytest.mark.parametrize("role", (1, 4, 5, 6))
def test_copied_controls_gate_the_owned_content(gate, role):
    payload = _stx1(((1, b"prefix", 0), (role, b"value", 0)))
    copied = _control_copy(payload, label=b"abc", shortcut=b"longer")
    address = gate.allocate(copied)
    assert gate.call("_RTAPT-CONTROL-COPY-GRID-STATUS", address, len(copied),
                     CORE_COLLECTIONS) == (4 if role >= 4 else 0,)
    assert gate.call("_RTAPT-CONTROL-COPY-GRID-STATUS", address, len(copied),
                     CORE_COLLECTIONS | GRID_CELLS) == (0,)
    if role >= 4:
        text_area = _changed(copied, 24, "<Q", 5)
        text_area_address = gate.allocate(text_area)
        assert gate.call("_RTAPT-CONTROL-COPY-GRID-STATUS", text_area_address,
                         len(text_area), CORE_COLLECTIONS | GRID_CELLS) == (3,)


def _bad_copies():
    copied = _control_copy(_stx1(((4, b"42", 0),)))
    for length in (0, 159, 160, 231, 267):
        yield pytest.param(copied[:length], id=f"copy-truncated-{length}")
    for name, offset, value in (
        ("label-overrun", 104, len(copied)),
        ("shortcut-overrun", 112, len(copied)),
        ("content-overrun", 120, len(copied)),
        ("label-wrap", 104, MASK64),
        ("shortcut-wrap", 112, MASK64),
        ("content-wrap", 120, MASK64),
    ):
        yield pytest.param(_changed(copied, offset, "<Q", value), id=name)
    yield pytest.param(_changed(copied, 160 + 72 + 24, "<H", 7),
                       id="copied-forged-role")
    yield pytest.param(_changed(copied, 160 + 40, "<I", 0xFFFFFFFF),
                       id="copied-forged-count")


@pytest.mark.parametrize("copied", list(_bad_copies()))
def test_copied_control_forgery_cannot_escape_the_owned_span(gate, copied):
    address = gate.allocate(copied)
    assert gate.call("_RTAPT-CONTROL-COPY-GRID-STATUS", address, len(copied),
                     CORE_COLLECTIONS | GRID_CELLS) == (3,)


@pytest.mark.parametrize("address,length", [(0, 160), (MASK64 - 31, 160)])
def test_copied_control_refuses_null_and_wrapping_spans(gate, address, length):
    assert gate.call("_RTAPT-CONTROL-COPY-GRID-STATUS", address, length,
                     CORE_COLLECTIONS | GRID_CELLS) == (3,)


@pytest.mark.parametrize("features,valid", [
    (CORE_COLLECTIONS, True), (CORE_COLLECTIONS | GRID_CELLS, True),
    (CORE_COLLECTIONS | 0x400, True), (CORE_COLLECTIONS | 0x1000, True),
    (0x2001, False), (0x2041, False), (0x2081, False),
    *((CORE_COLLECTIONS | bit, True) for bit in (0x200, 0x800)),
    (0x801, False),
])
def test_grid_capability_keeps_existing_limits_abi_and_dependency(gate, features, valid):
    limits = [0] * 21
    for index, value in {0: features, 1: 1, 2: 1, 3: 1, 5: 16,
                         7: 16, 8: 4096, 15: 256, 20: 512}.items():
        limits[index] = value
    if features & 0x200:
        limits[3] = 2
    address = gate.allocate(struct.pack("<21Q", *limits))
    for word in ("RTE-LIMITS-VALID?", "RTAPT-LIMITS-VALID?"):
        assert gate.call(word, address) == (MASK64 if valid else 0,)


@pytest.mark.parametrize("wire,local", [(0x301, 0xC1), (0x8301, 0x20C1),
                                        (0x8701, 0x21C1), (0x1001, 0x401),
                                        (0x4101, 0x1041), (0x801,0x201),
                                        (0x2101,0x841)])
def test_wire_provider_and_neutral_feature_mapping_is_explicit(gate, wire, local):
    caps = bytearray(64)
    struct.pack_into("<Q", caps, 8, wire)
    caps_address = gate.allocate(caps)
    formats_address = gate.allocate(bytes(56))
    engine_address = gate.allocate(bytes(536))
    gate.variable("_RTAPT-LS-E", engine_address)
    gate.variable("_RTAPT-LS-CAPS-A", caps_address)
    gate.variable("_RTAPT-LS-FORMATS-A", formats_address)
    assert gate.call("_RTAPT-LIMITS-COPY", readonly=False) == (engine_address + 336,)
    assert gate.runtime.memory.read64(engine_address + 336) == local
    assert gate.call("_RTAPTE-FEATURES>RTE", local) == (local,)


def test_grid_gate_does_not_extend_records_or_scan_aggregate_preflight():
    engine = (RICH / "engine.f").read_text()
    provider = (RICH / "apt1-engine.f").read_text()
    bridge = (RICH / "engine-apt1.f").read_text()
    for source, declarations in (
        (engine, {"RTE-F-GRID-CELLS": 0x2000, "_RTE-FEATURE-MASK": 0x3FFF,
                  "RTE-LIMITS-SIZE": 168, "RTE-CONTROL-SIZE": 200,
                  "RTE-CONTROL-PLAN-SIZE": 144}),
        (provider, {"RTAPT-F-GRID-CELLS": 0x2000, "_RTAPT-FEATURE-MASK": 0x3FFF,
                    "_RTAPT-PT-F-GRID-CELLS": 0x8000, "RTAPT-LIMITS-SIZE": 168,
                    "RTAPT-OWNER-SIZE": 608, "RTAPT-ENGINE-SIZE": 552,
                    "RTAPT-CONFIG-SIZE": 80, "RTAPT-OP-SIZE": 40,
                    "RTAPT-CONTROL-LEDGER-SIZE": 64,
                    "_RTAPT-CONTROL-COPY-FIXED": 160}),
    ):
        definitions = _definitions(source)
        for name, value in declarations.items():
            assert int(definitions[name].split()[0], 0) == value
    for source, names in (
        (provider, ("RTAPT-CONTROL-PREFLIGHT", "_RTAPT-CONTROL-PREFLIGHT-BODY",
                    "_RTAPT-CONTROL-PREFLIGHT-ARITHMETIC?")),
        (bridge, ("_RTAPTE-CONTROL-PREFLIGHT",)),
    ):
        for name in names:
            body = _word(source, name)
            for forbidden in ("ITEMS-A", "?DO", "STX1R-ROLES?",
                              "_RTAPT-GRID-CONTENT-STATUS"):
                assert forbidden not in body, (name, forbidden)


def test_direct_copied_and_replay_gates_precede_effects():
    source = (RICH / "apt1-engine.f").read_text()
    limits = _word(source, "_RTAPT-CONTROL-LIMITS")
    assert "_RTAPT-GRID-CONTENT-STATUS" in limits
    common = _word(source, "_RTAPT-CONTROL-COMMON?")
    assert "_RTAPT-CONTROL-LIMITS" in common
    for name in ("_RTAPT-CONTROL-DEFINE-BODY", "_RTAPT-CONTROL-REPLACE-BODY"):
        body = _word(source, name)
        assert body.index("_RTAPT-CONTROL-COMMON?") < body.index("_RTAPT-CONTROL-CAPTURE")
    publication = _word(source, "_RTAPT-PUBLICATION-CONTROL?")
    assert publication.index("_RTAPT-CONTROL-COPY-CONTENT-STATUS") < publication.index(
        "_RTAPT-PUBLICATION-CONTROL-DELTA-DEFINE?"
    )
    sender = _word(source, "_RTAPT-SEND-CONTROL")
    assert sender.index("_RTAPT-CONTROL-COPY-CONTENT-STATUS") < sender.index(
        "PT-CONTROL-REPLACE ELSE PT-CONTROL-DEFINE"
    )
    scanner = (RICH / "stx1-roles.f").read_text()
    for declaration in _definitions(scanner).values():
        code = re.sub(r"\([^)]*\)", "", declaration)
        for forbidden in ("!", "C!", "L!", "W!", "MOVE", "FILL", "ALLOCATE"):
            assert forbidden not in code.split()
