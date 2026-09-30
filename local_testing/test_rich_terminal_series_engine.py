"""Owned SERIES/WAVEFORM capture through real PT and the real retained host.

The fixture executes complete production neutral/provider/PT sources. Only
caller-owned capacities and negotiated host limits are enlarged; no encoder,
sample validator, owner ledger or terminal scene operation is replaced.
"""

from dataclasses import replace
import hashlib
import struct
from unittest.mock import patch

import pytest

import test_rich_terminal_cell_feed as cf
from test_rich_terminal_status_provider import ProviderHarness, RetainedFeature
from test_rich_terminal_status_static import MASK, RICH, SOURCE, _clean, _word
from simulator.runtime import MegaForthRuntime
from simulator.memory import EXTERNAL_BASE
from simulator.platform import create_one_core_address_space
from tests.simulator.test_kdos_exceptions import _load_exceptions
from rich_terminal.retained_wire import RetainedMessageType


FEATURES = RetainedFeature.CORE | RetainedFeature.INSTRUMENT | RetainedFeature.SERIES
I64_MIN = -(1 << 63)
I64_MAX = (1 << 63) - 1


class SeriesProvider(ProviderHarness):
    """Independent bounded provider fixture; the inherited helpers are transport-only."""

    def __init__(self, backend, *, open_owner=True):
        fixture = cf._fixture_source(20).replace(
            b"12 CF-COLS 8 * + 256 MAX CONSTANT CF-MAX-PAY",
            b"2048 CONSTANT CF-MAX-PAY",
        ).replace(
            b"CREATE CF-OPS-MEM RTAPT-OP-SIZE 7 + ALLOT",
            b"CREATE CF-OPS-MEM RTAPT-OP-SIZE 512 * 7 + ALLOT",
        ).replace(
            b"CREATE CF-COPY-MEM 15 ALLOT", b"CREATE CF-COPY-MEM 262151 ALLOT",
        ).replace(
            b"CF-OPS RTAPT-OP-SIZE", b"CF-OPS RTAPT-OP-SIZE 512 *",
        ).replace(b"CF-COPY 8 CF-LEDGER", b"CF-COPY 262144 CF-LEDGER")
        with patch.object(cf, "_fixture_source", return_value=fixture), patch.object(
            cf, "_load_exceptions", side_effect=lambda: _load_exceptions(
                MegaForthRuntime(execution_backend=backend,
                                 memory=create_one_core_address_space(external_size=1 << 20))),
        ):
            cf._FeedHarness.__init__(self, cf.SOURCE.read_bytes(), cols=20)
        self.runtime.evaluate((
            _word((RICH.parents[1] / "utils/string.f").read_text(), "/STRING")
            + "\n" + _clean(SOURCE) + "\n"
            + _clean((RICH / "engine-apt1.f").read_text())
        ).encode(), source_name="production-series-neutral-bridge.f", step_budget=12_000_000)
        # The source arena is caller-owned external RAM, disjoint from the
        # actual dictionary-backed operation and copy banks.
        self.arena = EXTERNAL_BASE
        self.used = 0
        policy = replace(
            cf._retained_policy(), features=FEATURES, max_objects=4,
            max_series=4, max_operations_per_transaction=512,
            max_samples_per_append=64, max_history_per_series=16000,
            total_sample_slots=32000, total_utf8_bytes=128, max_glyph_run_bytes=128,
            client_to_terminal_max_payload=2048,
            max_retained_transaction_bytes=300000, base_max_transaction_bytes=300000,
        )
        with patch.object(cf, "_retained_policy", return_value=policy):
            self.attach()
        if open_owner:
            assert self.call("RTAPT-OWNER-OPEN", 1, 1, 2, 0, 4, 4, 0, 128, 32000,
                             self.engine)[0] == (0,)
            self.settle()
            assert self.call("RTAPT-OWNER-STATE@", 1, 1, self.engine)[0] == (
                self.constant("RTAPT-OWNER-ST-OPEN"), 0)
        self.facade = self.allocate(bytes(self.constant("RTE-FACADE-SIZE")))
        assert self.call("RTAPTE-INIT", self.engine, self.facade)[0] == (0,)

    def allocate(self, payload):
        address = self.arena + self.used
        self.used += (len(payload) + 7) & -8
        assert self.used <= 262144
        self.runtime.memory.write_bytes(address, payload)
        return address

    def settle(self):
        for _ in range(1024):
            status = self.call("RTAPT-STEP", self.engine)[0]
            assert status in ((0,), (1,)), status
            self.service()
            if self.field("_RTAPT-E.ACTIVE-KIND") == 0 and self.field("_RTAPT-E.QUEUE-HEAD") == 0:
                return
        raise AssertionError("bounded series publication failed to settle")

    def series(self, values=(), *, timestamps=None, capacity=None, interval=125,
               first=0, chunk=None, identity=1, generation=1):
        if timestamps is None:
            mode = 1
            payload = b"".join(struct.pack("<q", value) for value in values)
        else:
            mode, interval, first = 0, 0, 0
            assert len(timestamps) == len(values)
            payload = b"".join(struct.pack("<Qq", timestamp, value)
                               for timestamp, value in zip(timestamps, values))
        samples = self.allocate(payload) if payload else 0
        capacity = max(1, len(values)) if capacity is None else capacity
        chunk = (2 if payload else 0) if chunk is None else chunk
        fields = (1, generation, identity, capacity, mode, interval, first,
                  samples, len(payload), chunk, 0)
        return self.allocate(struct.pack("<11Q", *(value & MASK for value in fields))), samples

    def waveform(self, *, series=1, identity=1, generation=1):
        fields = (1, generation, identity, 4, MASK, 0, 1, 0, 0, 0, 2, 20,
                  2, 20, 0x5FD7FFFF, 0x4E4E4EFF, 0, 1,
                  I64_MIN, I64_MAX, 0, 0, 0, 0, 0, 0, series)
        return self.allocate(struct.pack("<27Q", *(value & MASK for value in fields)))

    def define(self, record, *, neutral=False):
        return self.call("RTE-SERIES-DEFINE" if neutral else "RTAPT-SERIES-DEFINE",
                         record, self.facade if neutral else self.engine)[0]

    def define_waveform(self, record, *, neutral=False):
        return self.call("RTE-INSTRUMENT-DEFINE" if neutral else "RTAPT-INSTRUMENT-DEFINE",
                         record, self.facade if neutral else self.engine)[0]

    def samples(self, identity=1, *, hidden=False):
        state = self.driver.core.retained_state
        scene = state.hidden if hidden else state.active
        return tuple((sample.timestamp_us, sample.value)
                     for sample in scene.owners[1].series[identity].samples)

    def snapshot(self):
        """Accounting and complete caller banks, including unused capacity."""
        return (
            self.field("_RTAPT-E.OP-COUNT"), self.field("_RTAPT-E.COPY-USED"),
            self.field("_RTAPT-E.RET-BYTES"),
            self.owner_field("_RTAPT-O.PENDING-SERIES"),
            self.owner_field("_RTAPT-O.PENDING-SERIES-HIGH"),
            self.owner_field("_RTAPT-O.PENDING-SAMPLES"),
            hashlib.sha256(self.runtime.memory.read_bytes(self.constant("CF-OWNERS"),
                                                         self.constant("RTAPT-OWNER-SIZE"))).digest(),
            hashlib.sha256(self.runtime.memory.read_bytes(self.field("_RTAPT-E.OPS-A"),
                                                         self.field("_RTAPT-E.OPS-U"))).digest(),
            hashlib.sha256(self.runtime.memory.read_bytes(self.field("_RTAPT-E.COPY-A"),
                                                         self.field("_RTAPT-E.COPY-U"))).digest(),
            self.driver.core.frames_received,
        )

    def operations(self):
        return tuple(struct.unpack("<5Q", self.runtime.memory.read_bytes(
            self.field("_RTAPT-E.OPS-A") + index * 40, 40))
            for index in range(self.field("_RTAPT-E.OP-COUNT")))

    def disable_series_limits(self):
        limits = self.call("_RTAPT-E.LIMITS", self.engine)[0][0]
        prior = self.runtime.memory.read_bytes(limits, 168)
        self.runtime.memory.write64(limits, self.runtime.memory.read64(limits) & ~16)
        for offset in (48, 128, 136, 144):
            self.runtime.memory.write64(limits + offset, 0)
        assert self.call("RTAPT-LIMITS-VALID?", limits)[0] == (MASK,)
        return limits, prior


@pytest.fixture(params=("python", "native"))
def series_provider(request):
    harness = SeriesProvider(request.param)
    try:
        yield harness
    finally:
        harness.close()


@pytest.mark.parametrize("explicit", (False, True))
def test_series_chunks_own_exact_signed_values_timestamps_and_waveform(series_provider, explicit):
    h = series_provider
    values = (I64_MIN, I64_MIN + 1, -1, 0, 1, I64_MAX)
    timestamps = (0, 2, 200, 1 << 63, MASK - 1, MASK) if explicit else None
    expected = tuple(zip(timestamps or tuple(1000 + 125 * i for i in range(6)), values))
    h.begin()
    record, source = h.series(values, timestamps=timestamps, capacity=11, first=1000)
    assert h.define(record, neutral=True) == (0,)
    waveform = h.waveform()
    assert h.define_waveform(waveform, neutral=True) == (0,)
    stride = 16 if explicit else 8
    assert h.field("_RTAPT-E.OP-COUNT") == 6
    assert h.field("_RTAPT-E.COPY-USED") == 104 + 48 * 4 + stride * 6 + 216
    assert h.field("_RTAPT-E.RET-BYTES") == 104 + 80 * 4 + stride * 6 + 152
    assert h.owner_field("_RTAPT-O.PENDING-SERIES") == 1
    assert h.owner_field("_RTAPT-O.PENDING-SAMPLES") == 11
    h.runtime.memory.write_bytes(source, b"X" * (stride * 6))
    h.runtime.memory.write_bytes(record, bytes(88))
    h.runtime.memory.write_bytes(waveform, bytes(216))
    h.publish()
    assert h.samples() == expected
    owner = h.installed()
    assert owner.series[1].history_capacity == 11
    assert owner.objects[1].body.series_id == 1
    assert owner.objects[1].body.minimum == I64_MIN
    assert owner.objects[1].body.maximum == I64_MAX
    assert owner.usage.series == 1 and owner.usage.sample_slots == 11
    assert h.owner_field("_RTAPT-O.ACTIVE-SERIES") == 1
    assert h.owner_field("_RTAPT-O.ACTIVE-SAMPLES") == 11
    assert h.driver.core.frames_received_by_type[int(RetainedMessageType.SERIES_DEFINE)] == 1
    assert h.driver.core.frames_received_by_type[int(RetainedMessageType.SERIES_REPLACE)] == 1
    assert h.driver.core.frames_received_by_type[int(RetainedMessageType.SERIES_APPEND)] == 2


def test_empty_history_reserves_capacity_without_sample_payload(series_provider):
    h = series_provider
    h.begin()
    record, _ = h.series(capacity=16000)
    assert h.define(record) == (0,)
    assert h.field("_RTAPT-E.OP-COUNT") == 2
    assert h.field("_RTAPT-E.COPY-USED") == 104 + 48
    assert h.define_waveform(h.waveform()) == (0,)
    h.publish()
    assert h.samples() == ()
    assert h.installed().usage.sample_slots == 16000


def test_hidden_commit_reveal_and_abort_keep_target_local_slot_reservations(series_provider):
    h = series_provider
    h.begin()
    record, _ = h.series((-7, 9), capacity=12)
    assert h.define(record) == (0,)
    assert h.define_waveform(h.waveform()) == (0,)
    h.publish(reveal=False)
    assert h.samples(hidden=True) == ((0, -7), (125, 9))
    assert h.owner_field("_RTAPT-O.HIDDEN-SERIES") == 1
    assert h.owner_field("_RTAPT-O.HIDDEN-SAMPLES") == 12
    assert h.owner_field("_RTAPT-O.ACTIVE-SAMPLES") == 0
    h.begin("PT-RET-REPLACE-CONTINUE")
    h.publish()
    original = h.driver.core.retained_state
    h.begin(region=2)
    record, source = h.series((33, 44), capacity=16000, identity=2)
    assert h.define(record) == (0,)
    copied, used = h.field("_RTAPT-E.COPY-A"), h.field("_RTAPT-E.COPY-USED")
    h.runtime.memory.write_bytes(source, bytes(16))
    assert h.call("RTAPT-RICH-CANCEL", h.engine)[0] == (0,)
    assert h.driver.core.retained_state is original
    assert h.owner_field("_RTAPT-O.ACTIVE-SAMPLES") == 12
    assert h.owner_field("_RTAPT-O.PENDING-SAMPLES") == 0
    assert h.runtime.memory.read_bytes(copied, used) == bytes(used)


@pytest.mark.parametrize("mode", ("PT-RET-DELTA", "PT-RET-REPLACE-CONTINUE"))
def test_series_definition_is_candidate_start_only(series_provider, mode):
    h = series_provider
    h.begin()
    record, _ = h.series((1,), capacity=2)
    assert h.define(record) == (0,)
    h.publish(reveal=mode == "PT-RET-DELTA")
    h.begin(mode)
    record, _ = h.series((2,), capacity=2, identity=2)
    before = h.snapshot()
    assert h.define(record) != (0,)
    assert h.snapshot() == before
    assert h.call("RTAPT-RICH-CANCEL", h.engine)[0] == (0,)


@pytest.mark.parametrize("offset,value", (
    (0, 0), (8, 2), (16, 0), (24, 0), (24, 16001), (32, 2),
    (40, 0), (48, MASK), (56, 0), (64, 7), (72, 0), (72, 65), (80, 1),
))
def test_invalid_series_refusal_is_atomic_before_copy_or_wire(series_provider, offset, value):
    h = series_provider
    h.begin()
    record, _ = h.series((I64_MIN, I64_MAX), capacity=2)
    h.runtime.memory.write64(record + offset, value)
    before = h.snapshot()
    assert h.define(record) != (0,)
    assert h.snapshot() == before
    assert h.call("RTAPT-RICH-CANCEL", h.engine)[0] == (0,)


def test_explicit_order_uniform_overflow_and_borrowed_aliases_refuse_atomically(series_provider):
    h = series_provider
    h.begin()
    probes = [h.series((1, 2), timestamps=(7, 7))[0],
              h.series((1, 2), timestamps=(8, 7))[0],
              h.series((1, 2, 3), interval=MASK)[0],
              h.series((1, 2), first=MASK)[0]]
    record, _ = h.series((1, 2))
    for source in (record, h.field("_RTAPT-E.COPY-A"), MASK - 7,
                   *(h.runtime.find(name).body_address
                     for name in ("_RTAPT-SD-I", "_RTAPT-SD-A", "_RTAPT-SF-A"))):
        h.runtime.memory.write64(record + 56, source)
        before = h.snapshot()
        assert h.define(record) != (0,)
        assert h.snapshot() == before
    for record in probes:
        before = h.snapshot()
        assert h.define(record) != (0,)
        assert h.snapshot() == before
    assert h.call("RTAPT-RICH-CANCEL", h.engine)[0] == (0,)


def test_capability_absence_and_missing_series_reference_precede_capture(series_provider):
    h = series_provider
    h.begin()
    record, _ = h.series((1, 2))
    limits, original_limits = h.disable_series_limits()
    before = h.snapshot()
    assert h.define(record) == (h.constant("RTAPT-S-UNSUPPORTED"),)
    assert h.snapshot() == before
    h.runtime.memory.write_bytes(limits, original_limits)
    before = h.snapshot()
    assert h.define_waveform(h.waveform(series=99)) != (0,)
    assert h.snapshot() == before
    assert h.define(record) == (0,)
    assert h.define_waveform(h.waveform()) == (0,)
    assert h.call("RTAPT-RICH-CANCEL", h.engine)[0] == (0,)


def test_declared_capacity_and_operation_budget_refuse_whole_series(series_provider):
    h = series_provider
    h.begin()
    owner = h.constant("CF-OWNERS")
    quota = h.call("_RTAPT-O.SAMPLES", owner)[0][0]
    h.runtime.memory.write64(quota, 10)
    record, _ = h.series((1,), capacity=11)
    before = h.snapshot()
    assert h.define(record) != (0,)
    assert h.snapshot() == before
    h.runtime.memory.write64(quota, 32000)
    # More chunks than negotiated/caller operation slots cannot capture a prefix.
    record, _ = h.series(tuple(range(513)), capacity=513, chunk=1)
    before = h.snapshot()
    assert h.define(record) != (0,)
    assert h.snapshot() == before
    assert h.call("RTAPT-RICH-CANCEL", h.engine)[0] == (0,)


def test_multiple_empty_histories_charge_the_sum_of_declared_capacities(series_provider):
    h = series_provider
    h.begin()
    for identity in (1, 2):
        record, _ = h.series(capacity=16000, identity=identity)
        assert h.define(record) == (0,)
    assert h.owner_field("_RTAPT-O.PENDING-SERIES") == 2
    assert h.owner_field("_RTAPT-O.PENDING-SAMPLES") == 32000
    record, _ = h.series(capacity=1, identity=3)
    before = h.snapshot()
    assert h.define(record) != (0,)
    assert h.snapshot() == before
    h.publish()
    assert h.installed().usage.series == 2
    assert h.installed().usage.sample_slots == 32000
    assert h.samples(1) == () and h.samples(2) == ()


@pytest.mark.parametrize("empty_first", (False, True))
def test_mixed_histories_preserve_each_reference_and_active_history_on_failure(
        series_provider, empty_first):
    h = series_provider
    h.begin()
    empty_id, sampled_id = (1, 2) if empty_first else (2, 1)
    for identity in (1, 2):
        if identity == empty_id:
            record, _ = h.series(capacity=9, identity=identity)
        else:
            record, _ = h.series((I64_MIN, I64_MAX), timestamps=(0, MASK),
                                 capacity=13, chunk=1, identity=identity)
        assert h.define(record) == (0,)
    for identity in (1, 2):
        assert h.define_waveform(h.waveform(series=identity, identity=identity)) == (0,)
    assert h.owner_field("_RTAPT-O.PENDING-SERIES") == 2
    assert h.owner_field("_RTAPT-O.PENDING-SAMPLES") == 22
    assert h.field("_RTAPT-E.OP-COUNT") == 7
    h.publish()
    assert h.samples(empty_id) == ()
    assert h.samples(sampled_id) == ((0, I64_MIN), (MASK, I64_MAX))
    assert h.installed().usage.series == 2
    assert h.installed().usage.sample_slots == 22
    assert tuple(h.installed().objects[index].body.series_id for index in (1, 2)) == (1, 2)
    original = h.driver.core.retained_state
    h.begin(region=2)
    record, _ = h.series((3, 4), first=MASK, capacity=5, identity=3)
    before = h.snapshot()
    assert h.define(record) != (0,)
    assert h.snapshot() == before
    assert h.call("RTAPT-RICH-CANCEL", h.engine)[0] == (0,)
    assert h.driver.core.retained_state is original
    assert h.owner_field("_RTAPT-O.ACTIVE-SERIES") == 2
    assert h.owner_field("_RTAPT-O.ACTIVE-SAMPLES") == 22
    assert h.samples(sampled_id) == ((0, I64_MIN), (MASK, I64_MAX))


def test_owned_replay_malformed_chunks_and_references_refuse_before_any_frame(series_provider):
    h = series_provider
    h.begin()
    record, _ = h.series((I64_MIN, 0, I64_MAX), capacity=8)
    assert h.define(record) == (0,)
    assert h.define_waveform(h.waveform()) == (0,)
    assert h.call("RTAPT-RICH-SEAL", h.constant("PT-COMMIT"), h.engine)[0] == (0,)
    assert h.call("_RTAPT-PUBLICATION-AUDIT?", 20, 2, h.engine)[0] == (MASK,)
    ops = h.operations()
    copy_base = h.field("_RTAPT-E.COPY-A")
    op_base = h.field("_RTAPT-E.OPS-A")
    definition, chunk, waveform = (copy_base + ops[index][1] for index in (1, 2, -1))
    mutations = (
        (definition + 24, 0), (definition + 32, 2),
        (chunk + 16, 99), (chunk + 40, 0), (chunk + 24, 2),
        (chunk + 32, MASK), (waveform + 208, 99),
        (op_base + 2 * 40 + 8, MASK - 7),
        (op_base + 2 * 40 + 16, 47),
        (op_base + 2 * 40 + 32, 0),
    )
    for address, value in mutations:
        original = h.runtime.memory.read64(address)
        h.runtime.memory.write64(address, value)
        before = h.snapshot()
        assert h.call("_RTAPT-PUBLICATION-AUDIT?", 20, 2, h.engine)[0] == (0,)
        assert h.snapshot() == before
        h.runtime.memory.write64(address, original)
    assert h.call("_RTAPT-PUBLICATION-AUDIT?", 20, 2, h.engine)[0] == (MASK,)
    assert h.call("RTAPT-RICH-CANCEL", h.engine)[0] == (0,)


def test_publication_rechecks_series_capability_before_wire(series_provider):
    h = series_provider
    h.begin()
    record, _ = h.series((1, 2), capacity=5)
    assert h.define(record) == (0,)
    assert h.define_waveform(h.waveform()) == (0,)
    assert h.call("RTAPT-RICH-SEAL", h.constant("PT-COMMIT"), h.engine)[0] == (0,)
    limits, original_limits = h.disable_series_limits()
    before = h.snapshot()
    assert h.call("_RTAPT-PUBLICATION-AUDIT?", 20, 2, h.engine)[0] == (0,)
    assert h.snapshot() == before
    h.runtime.memory.write_bytes(limits, original_limits)
    assert h.call("RTAPT-RICH-CANCEL", h.engine)[0] == (0,)


@pytest.mark.parametrize("backend", ("python", "native"))
@pytest.mark.parametrize("sampled", (False, True))
def test_series_only_aggregate_admission_uses_declared_slots_without_owner_open(backend, sampled):
    h = SeriesProvider(backend, open_owner=False)
    try:
        values = [0] * 57
        values[:4] = (1, 1, 20, 2)
        values[48:56] = (1, 1, 9, 9, 40 if sampled else 0,
                         3 if sampled else 0, 2 if sampled else 0, 16 if sampled else 0)
        original = struct.pack("<57Q", *values)
        summary = h.allocate(original)
        before = h.snapshot()
        assert h.call("RTAPT-HYBRID-PREFLIGHT", summary, h.engine)[0] == (0,)
        assert h.snapshot() == before
        assert h.runtime.memory.read_bytes(summary, 456) == original
        # Aggregate arithmetic is exact: capacity is neither sample count nor
        # just the bytes currently carried, even when the history is empty.
        for index, bad in ((50, 8), (51, 16001), (49, 0),
                           (53, 0 if sampled else 1), (55, 15 if sampled else 1)):
            h.runtime.memory.write64(summary + index * 8, bad)
            assert h.call("RTAPT-HYBRID-PREFLIGHT", summary, h.engine)[0] != (0,)
            assert h.snapshot() == before
            h.runtime.memory.write_bytes(summary, original)
        session = h.field("_RTAPT-E.SESSION")
        caps, caps_u = h.call("PT-RETAINED-CAPS@", session)[0]
        formats, formats_u = h.call("PT-RETAINED-FORMATS@", session)[0]
        old_caps = h.runtime.memory.read_bytes(caps, caps_u)
        old_formats = h.runtime.memory.read_bytes(formats, formats_u)
        h.runtime.memory.write64(caps + 8, h.runtime.memory.read64(caps + 8) & ~16)
        h.runtime.memory.write32(caps + 36, 0)
        h.runtime.memory.write32(formats + 28, 0)
        h.runtime.memory.write32(formats + 32, 0)
        h.runtime.memory.write64(formats + 40, 0)
        assert h.call("RTAPT-HYBRID-PREFLIGHT", summary, h.engine)[0] == (
            h.constant("RTAPT-S-UNSUPPORTED"),)
        assert h.snapshot() == before
        h.runtime.memory.write_bytes(caps, old_caps)
        h.runtime.memory.write_bytes(formats, old_formats)
    finally:
        h.close()


def test_full_soundlab_history_round_trips_without_decimation():
    h = SeriesProvider("native")
    try:
        h.begin()
        values = tuple((index % 65536) - 8000 for index in range(16000))
        record, source = h.series(values, capacity=16000, chunk=64)
        assert h.define(record, neutral=True) == (0,)
        assert h.define_waveform(h.waveform(), neutral=True) == (0,)
        assert h.field("_RTAPT-E.OP-COUNT") == 253
        assert h.field("_RTAPT-E.COPY-USED") == 104 + 48 * 251 + 128000 + 216
        h.runtime.memory.write_bytes(source, bytes(128000))
        h.publish()
        assert h.samples() == tuple((index * 125, value) for index, value in enumerate(values))
        assert h.samples()[-1] == (1999875, 7999)
        assert h.installed().usage.sample_slots == 16000
        assert h.driver.core.frames_received_by_type[int(RetainedMessageType.SERIES_DEFINE)] == 1
        assert h.driver.core.frames_received_by_type[int(RetainedMessageType.SERIES_REPLACE)] == 1
        assert h.driver.core.frames_received_by_type[int(RetainedMessageType.SERIES_APPEND)] == 249
    finally:
        h.close()
