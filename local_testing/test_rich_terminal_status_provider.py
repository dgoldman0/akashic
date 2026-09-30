"""Real provider capture, abort and wire publication for static STATUS_FIELD."""
from dataclasses import replace
import struct
from unittest.mock import patch

import pytest

from test_rich_terminal_status_static import MASK, SOURCE, RICH, _clean, _word
import test_rich_terminal_cell_feed as cf
from simulator.runtime import MegaForthRuntime
from tests.simulator.test_kdos_exceptions import _load_exceptions
from rich_terminal.retained_model import RetainedFeature


class ProviderHarness(cf._FeedHarness):
    def __init__(self, backend, *, features=RetainedFeature.CORE | RetainedFeature.STATUS_FIELDS):
        fixture = cf._fixture_source(20).replace(
            b"CREATE CF-OPS-MEM RTAPT-OP-SIZE 7 + ALLOT",
            b"CREATE CF-OPS-MEM RTAPT-OP-SIZE 16 * 7 + ALLOT",
        ).replace(b"CREATE CF-COPY-MEM 15 ALLOT", b"CREATE CF-COPY-MEM 4103 ALLOT").replace(
            b"CF-OPS RTAPT-OP-SIZE", b"CF-OPS RTAPT-OP-SIZE 16 *",
        ).replace(b"CF-COPY 8 CF-LEDGER", b"CF-COPY 4096 CF-LEDGER")
        with patch.object(cf, "_fixture_source", return_value=fixture), patch.object(
            cf, "_load_exceptions", side_effect=lambda: _load_exceptions(
                MegaForthRuntime(execution_backend=backend))
        ):
            super().__init__(cf.SOURCE.read_bytes(), cols=20)
        self.runtime.evaluate((
            _word((RICH.parents[1] / "utils/string.f").read_text(), "/STRING")
            + "\n" + _clean(SOURCE) + "\n"
            + _clean((RICH / "engine-apt1.f").read_text())
        ).encode(), source_name="production-neutral-apt1-bridge.f", step_budget=8_000_000)
        arena = self.runtime.define_created("STP-ARENA", initial_body=bytes(8199))
        self.arena = (arena.body_address + 7) & -8
        self.used = 0
        base = cf._retained_policy()
        with patch.object(cf, "_retained_policy", return_value=replace(
            base, features=features,
            max_objects=4, total_utf8_bytes=128,
        )):
            self.attach()
        self.serial = 0
        assert self.call("RTAPT-OWNER-OPEN", 1, 1, 2, 0, 4, 0, 0, 128, 0, self.engine)[0] == (0,)
        self.settle()
        assert self.call("RTAPT-OWNER-STATE@", 1, 1, self.engine)[0][0] == self.constant("RTAPT-OWNER-ST-OPEN")
        self.facade = self.allocate(bytes(216))
        assert self.call("RTAPTE-INIT", self.engine, self.facade)[0] == (0,)

    def constant(self, name):
        return self.call(name)[0][0]

    def field(self, name):
        address = self.call(name, self.engine)[0][0]
        return self.runtime.memory.read64(address)

    def owner_field(self, name):
        address = self.call(name, self.constant("CF-OWNERS"))[0][0]
        return self.runtime.memory.read64(address)

    def allocate(self, payload):
        address = self.arena + self.used
        self.used += (len(payload) + 7) & -8
        assert self.used <= 8192
        self.runtime.memory.write_bytes(address, payload)
        return address

    def status(self, label=b"Ready", value=b"online", *, identity=1, region=1):
        text = self.allocate(label + value)
        fields = [1, 1, identity, 1, MASK, 0, region, 0, 0, 0, 1, 20,
                  2, 20, 6, 2, MASK, text if label else 0, len(label),
                  text + len(label) if value else 0, len(value), 0]
        record = self.allocate(struct.pack("<22Q", *fields))
        return record, text

    def begin(self, mode="PT-RET-REPLACE-START", *, region=1):
        assert self.call("RTAPT-RICH-BEGIN", self.constant(mode), self.engine)[0] == (0,)
        if mode == "PT-RET-REPLACE-START":
            assert self.call("RTAPT-REGION-DEFINE", 1, 1, region, 0, 0, 20, 2,
                             0, 0, 0, 0, 0, 1, self.engine)[0] == (0,)

    def settle(self):
        for _ in range(16):
            status = self.call("RTAPT-STEP", self.engine)[0]
            assert status in ((0,), (1,)), status
            self.service()
            if self.field("_RTAPT-E.ACTIVE-KIND") == 0 and self.field("_RTAPT-E.QUEUE-HEAD") == 0:
                return
        raise AssertionError("retained provider failed to settle")

    def publish(self, reveal=True):
        if reveal and self.field("_RTAPT-E.RET-MODE") == self.constant("PT-RET-REPLACE-START"):
            self.publish(reveal=False)
            self.begin("PT-RET-REPLACE-CONTINUE")
        assert self.call("RTAPT-RICH-SEAL", self.constant(
            "PT-COMMIT-AND-REVEAL" if reveal else "PT-COMMIT"), self.engine)[0] == (0,)
        assert self.call("RTAPT-CELL-BEGIN", 20, 2, 0, 0, 0,
                         self.constant("PT-CELL-DELTA"), self.engine)[0] == (0,)
        assert self.call("RTAPT-CELL-CURSOR", 0, 0, 0, self.engine)[0] == (0,)
        assert self.call("RTAPT-CELL-COMMIT", self.engine)[0] in ((0,), (1,))
        self.settle()

    def installed(self):
        return self.driver.core.retained_state.active.owners[1]


@pytest.fixture(params=("python", "native"))
def provider(request):
    harness = ProviderHarness(request.param)
    try:
        yield harness
    finally:
        harness.close()


def test_status_copies_both_fields_then_emits_exact_static_object(provider):
    provider.begin()
    record, text = provider.status()
    assert provider.call("RTAPT-STATIC-DEFINE", record, provider.engine)[0] == (0,)
    assert provider.field("_RTAPT-E.OP-COUNT") == 2
    assert provider.field("_RTAPT-E.COPY-USED") == 104 + 192
    assert provider.field("_RTAPT-E.RET-BYTES") == 104 + 136 + 11
    copied = provider.field("_RTAPT-E.COPY-A") + 104
    assert provider.runtime.memory.read64(copied + 136) == 0
    assert provider.runtime.memory.read64(copied + 152) == 0
    provider.runtime.memory.write_bytes(text, b"X" * 11)
    provider.runtime.memory.write64(record + 88, 999)
    provider.publish()
    owner = provider.installed()
    obj = owner.objects[1]
    assert (obj.body.label, obj.body.value, obj.body.label_cols) == ("Ready", "online", 6)
    assert obj.bounds.cell_cols == 20
    assert owner.usage.objects == 1 and owner.usage.utf8_bytes == 11
    assert provider.owner_field("_RTAPT-O.ACTIVE-UTF8") == 11


def test_status_replace_owns_source_and_abort_preserves_committed_owner(provider):
    provider.begin()
    record, _ = provider.status()
    assert provider.call("RTAPT-STATIC-DEFINE", record, provider.engine)[0] == (0,)
    provider.publish()
    original = provider.driver.core.retained_state
    provider.begin("PT-RET-DELTA")
    record, text = provider.status(b"State", b"paused")
    assert provider.call("RTAPT-STATIC-REPLACE", record, provider.engine)[0] == (0,)
    copied = provider.field("_RTAPT-E.COPY-A")
    assert provider.runtime.memory.read_bytes(copied + 176, 11) == b"Statepaused"
    provider.runtime.memory.write_bytes(text, b"X" * 11)
    assert provider.call("RTAPT-RICH-CANCEL", provider.engine)[0] == (0,)
    assert provider.driver.core.retained_state is original
    assert provider.field("_RTAPT-E.OP-COUNT") == 0
    assert provider.runtime.memory.read_bytes(copied, 192) == bytes(192)
    provider.begin("PT-RET-DELTA")
    record, text = provider.status(b"State", b"paused")
    assert provider.call("RTAPT-STATIC-REPLACE", record, provider.engine)[0] == (0,)
    provider.runtime.memory.write_bytes(text, b"Y" * 11)
    provider.publish(reveal=False)
    assert provider.installed().objects[1].body.label == "State"
    assert provider.installed().objects[1].body.value == "paused"
    assert provider.installed().usage.utf8_bytes == 11


def test_status_capability_refusal_precedes_copy_accounting_and_replay(provider):
    provider.begin()
    record, _ = provider.status()
    limits = provider.call("_RTAPT-E.LIMITS", provider.engine)[0][0]
    original_features = provider.runtime.memory.read64(limits)
    before = provider.runtime.memory.read_bytes(provider.engine, 536)
    provider.runtime.memory.write64(limits, original_features & ~0x400)
    denied_state = provider.runtime.memory.read_bytes(provider.engine, 536)
    frames = provider.driver.core.frames_received
    assert provider.call("RTAPT-STATIC-DEFINE", record, provider.engine)[0] == (
        provider.constant("RTAPT-S-UNSUPPORTED"),)
    assert provider.runtime.memory.read_bytes(provider.engine, 536) == denied_state
    assert provider.driver.core.frames_received == frames
    provider.runtime.memory.write64(limits, original_features)
    assert provider.runtime.memory.read_bytes(provider.engine, 536) == before
    assert provider.call("RTAPT-STATIC-DEFINE", record, provider.engine)[0] == (0,)
    op = provider.field("_RTAPT-E.OPS-A") + 40
    provider.runtime.memory.write64(limits, original_features & ~0x400)
    assert provider.call("_RTAPT-SEND-CAPTURED", op, provider.engine)[0] == (
        provider.constant("RTAPT-S-UNSUPPORTED"),)
    assert provider.driver.core.frames_received == frames
    provider.runtime.memory.write64(limits, original_features)
    assert provider.call("RTAPT-RICH-CANCEL", provider.engine)[0] == (0,)


def test_status_direct_span_alias_and_independent_text_reject_without_capture(provider):
    provider.begin()
    record, text = provider.status()
    count = provider.field("_RTAPT-E.OP-COUNT")
    provider.runtime.memory.write64(record + 136, record)
    assert provider.call("RTAPT-STATIC-DEFINE", record, provider.engine)[0] == (
        provider.constant("RTAPT-S-INVALID"),)
    for scratch in ("_RTAPT-STD-I", "_RTAPT-SOB-E", "_RTAPT-GT-OBJECT"):
        scratch_address = provider.runtime.find(scratch).body_address
        before = provider.runtime.memory.read_bytes(scratch_address, 11)
        provider.runtime.memory.write64(record + 136, scratch_address)
        assert provider.call("RTAPT-STATIC-DEFINE", record, provider.engine)[0] == (
            provider.constant("RTAPT-S-INVALID"),)
        assert provider.runtime.memory.read_bytes(scratch_address, 11) == before
    provider.runtime.memory.write64(record + 136, text)
    provider.runtime.memory.write_bytes(text, b"\xc2\x80adyonline")
    assert provider.call("RTAPT-STATIC-DEFINE", record, provider.engine)[0] == (
        provider.constant("RTAPT-S-INVALID"),)
    assert provider.field("_RTAPT-E.OP-COUNT") == count
    provider.runtime.memory.write_bytes(text, b"Readyonline")
    assert provider.call("RTAPT-STATIC-DEFINE", record, provider.engine)[0] == (0,)
    copy = provider.field("_RTAPT-E.COPY-A") + 104
    provider.runtime.memory.write64(copy + 152, text)
    assert provider.call("_RTAPT-STATIC-COPY-SHAPE?", copy, 192)[0] == (0,)
    provider.runtime.memory.write64(copy + 152, 0)
    assert provider.call("RTAPT-RICH-CANCEL", provider.engine)[0] == (0,)


def test_status_aggregate_preflight_matches_capture_without_item_bank(provider):
    summary = [0] * 48
    summary[:15] = [1, 1, 20, 2, 1, 0, 0, 20, 2, 0, 0, 0, 0, 0, 1]
    summary[40:47] = [1, 11, 16, 11, 1, 192, 1]
    payload = struct.pack("<48Q", *summary)
    address = provider.allocate(payload)
    assert provider.call("RTAPT-HYBRID-PREFLIGHT", address, provider.engine)[0] == (0,)
    assert provider.runtime.memory.read_bytes(address, 384) == payload
    assert provider.field("_RTAPT-E.OP-COUNT") == 0
    for field, value in ((360, 184), (368, 2), (320, 0), (344, 12)):
        provider.runtime.memory.write64(address + field, value)
        assert provider.call("RTAPT-HYBRID-PREFLIGHT", address, provider.engine)[0] == (
            provider.constant("RTAPT-S-INVALID"),)
        provider.runtime.memory.write_bytes(address, payload)
    # The static lane requires the shared base region even without other lanes.
    provider.runtime.memory.write_bytes(address + 32, bytes(88))
    assert provider.call("RTAPT-HYBRID-PREFLIGHT", address, provider.engine)[0] == (
        provider.constant("RTAPT-S-INVALID"),)


def test_static_neutral_bridge_maps_capability_and_dispatches_independent_lane(provider):
    assert provider.call("_RTAPTE-STATIC-LAYOUT?")[0] == (MASK,)
    assert provider.call("_RTAPTE-HYBRID-LAYOUT?")[0] == (MASK,)
    assert provider.call("_RTAPTE-FEATURES>RTE", 0x401)[0] == (0x401,)
    provider.begin()
    record, _ = provider.status()
    assert provider.call("RTE-STATIC-DEFINE", record, provider.facade)[0] == (0,)
    provider.publish()
    assert provider.installed().objects[1].body.label == "Ready"


def test_owned_static_copy_rejects_bounded_forgery(provider):
    provider.begin()
    record, _ = provider.status()
    assert provider.call("RTAPT-STATIC-DEFINE", record, provider.engine)[0] == (0,)
    address = provider.field("_RTAPT-E.COPY-A") + 104
    payload = provider.runtime.memory.read_bytes(address, 192)
    for offset, value in ((136, 1), (152, 1), (144, 1 << 32), (160, MASK),
                          (112, 0), (80, 2), (120, 5), (168, 1)):
        provider.runtime.memory.write64(address + offset, value)
        assert provider.call("_RTAPT-STATIC-COPY-SHAPE?", address, 192)[0] == (0,)
        provider.runtime.memory.write_bytes(address, payload)
    for length in (0, 175, 191, 193, MASK):
        assert provider.call("_RTAPT-STATIC-COPY-SHAPE?", address, length)[0] == (0,)
    assert provider.call("_RTAPT-STATIC-COPY-SHAPE?", 0, 192)[0] == (0,)
    provider.runtime.memory.write_bytes(address + 187, b"X")
    assert provider.call("_RTAPT-STATIC-COPY-SHAPE?", address, 192)[0] == (0,)
    provider.runtime.memory.write_bytes(address, payload)
    assert provider.call("RTAPT-RICH-CANCEL", provider.engine)[0] == (0,)


def test_changed_status_full_replacement_keeps_old_owner_on_abort_and_recounts_utf8(provider):
    provider.begin()
    record, _ = provider.status()
    assert provider.call("RTAPT-STATIC-DEFINE", record, provider.engine)[0] == (0,)
    provider.publish()
    original = provider.driver.core.retained_state
    provider.begin(region=2)
    record, text = provider.status(b"A", b"B", identity=2, region=2)
    assert provider.call("RTAPT-STATIC-DEFINE", record, provider.engine)[0] == (0,)
    assert provider.owner_field("_RTAPT-O.PENDING-UTF8") == 2
    provider.runtime.memory.write_bytes(text, b"XX")
    assert provider.call("RTAPT-RICH-CANCEL", provider.engine)[0] == (0,)
    assert provider.driver.core.retained_state is original
    assert provider.owner_field("_RTAPT-O.ACTIVE-UTF8") == 11
    assert provider.owner_field("_RTAPT-O.PENDING-UTF8") == 0
    provider.begin(region=2)
    record, _ = provider.status(b"A", b"B", identity=2, region=2)
    assert provider.call("RTAPT-STATIC-DEFINE", record, provider.engine)[0] == (0,)
    provider.publish()
    owner = provider.installed()
    assert set(owner.objects) == {2}
    assert owner.objects[2].body.label == "A" and owner.objects[2].body.value == "B"
    assert owner.usage.utf8_bytes == 2
    assert provider.owner_field("_RTAPT-O.ACTIVE-UTF8") == 2
