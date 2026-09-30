"""Production neutral SERIES snapshots and same-candidate WAVEFORM references."""
import struct

import pytest

from test_rich_terminal_status_static import StaticHarness, MASK, _offset


class SeriesNeutral(StaticHarness):
    def series(self, values=(-32768, 0, 32767), *, mode=1, **changes):
        payload = (b"".join(struct.pack("<Qq", *pair) for pair in values)
                   if mode == 0 else struct.pack(f"<{len(values)}q", *values))
        samples = self.allocate(payload) if payload else 0
        fields = dict(OWNER=1, GENERATION=2, ID=7, CAPACITY=16000, MODE=mode,
                      **{"INTERVAL-US": 125 if mode else 0, "FIRST-US": 0,
                         "SAMPLES-A": samples, "SAMPLES-U": len(payload),
                         "CHUNK-SAMPLES": min(1024, len(values))})
        fields.update(changes)
        return self.record("_RTE-SERIES", 88, fields), samples, len(payload)

    def graph(self, values=(-32768, 0, 32767), *, mode=1, waveform=True,
              series_changes=None, wave_changes=None):
        item, samples, size = self.series(values, mode=mode, **(series_changes or {}))
        plan = self.record("_RTE-SRP", 48, {
            "OWNER": 1, "GENERATION": 2, "SURFACE-COLS": 80, "SURFACE-ROWS": 24,
            "ITEMS-A": item, "ITEMS-U": 88,
        })
        wave = region = instrument_plan = 0
        if waveform:
            fields = dict(OWNER=1, GENERATION=2, ID=3, KIND=4, VISIBLE=MASK,
                          REGION=2, HEIGHT=12, WIDTH=80, MINIMUM=-32768,
                          MAXIMUM=32767, **{"ROOT-HEIGHT": 24, "ROOT-WIDTH": 80,
                                           "SERIES-ID": 7, "OPTIONS": 1})
            fields.update(wave_changes or {})
            wave = self.record("_RTE-INSTRUMENT", 216, fields)
            region = self.record("_RTE-IR", 96, {"ID": 2, "COLS": 80, "ROWS": 24})
            instrument_plan = self.record("_RTE-IP", 72, {
                "OWNER": 1, "GENERATION": 2, "SURFACE-COLS": 80, "SURFACE-ROWS": 24,
                "REGIONS-A": region, "REGIONS-U": 96, "ITEMS-A": wave, "ITEMS-U": 216,
            })
        hybrid = self.record("_RTE-HP", 168, {
            "ATTEMPT": 1, "SOURCE-GENERATION": 1, "SURFACE-GENERATION": 1,
            "SERIES-PLAN": plan, "SERIES-SAMPLES-A": samples, "SERIES-SAMPLES-U": size,
            "INSTRUMENT-PLAN": instrument_plan,
        })
        admission = self.allocate(b"A" * 456)
        return item, samples, size, plan, wave, region, instrument_plan, hybrid, admission


@pytest.fixture(scope="module", params=("python", "native"))
def neutral(request):
    return SeriesNeutral(request.param)


@pytest.mark.parametrize("changes", [
    {"OWNER": 0}, {"GENERATION": 0}, {"ID": 0}, {"CAPACITY": 0},
    {"CAPACITY": 1}, {"CAPACITY": 1 << 32}, {"MODE": 2},
    {"INTERVAL-US": 0}, {"INTERVAL-US": MASK}, {"FIRST-US": MASK},
    {"CHUNK-SAMPLES": 0}, {"CHUNK-SAMPLES": 1 << 32}, {"RESERVED": 1},
    {"SAMPLES-A": 0}, {"SAMPLES-A": MASK - 7}, {"SAMPLES-U": 1},
])
def test_rejects_invalid_snapshot_before_public_callback(neutral, changes):
    item, _, _ = neutral.series(**changes)
    before = neutral.variable("SF-CALLS")
    assert neutral.call("RTE-SERIES-VALID?", item) == (0,)
    assert neutral.call("RTE-SERIES-DEFINE", item, neutral.facade) == (5,)
    assert neutral.variable("SF-CALLS") == before


@pytest.mark.parametrize("values,mode,changes,valid", [
    ((), 1, {}, True), ((), 0, {}, True),
    ((), 1, {"FIRST-US": 1}, False), ((), 1, {"CHUNK-SAMPLES": 1}, False),
    ((-(1 << 63), (1 << 63) - 1), 1, {"FIRST-US": MASK - 125}, True),
    (((0, -1), (MASK, 1)), 0, {}, True),
    (((2, -1), (2, 1)), 0, {}, False),
    (((2, -1), (1, 1)), 0, {}, False),
    (((1, -1),), 0, {"FIRST-US": 1}, False),
    (((1, -1),), 0, {"INTERVAL-US": 1}, False),
])
def test_exact_empty_signed_value_and_timestamp_semantics(neutral, values, mode, changes, valid):
    item, _, _ = neutral.series(values, mode=mode, **changes)
    assert neutral.call("RTE-SERIES-VALID?", item) == (MASK if valid else 0,)


@pytest.mark.parametrize("mode", (0, 1))
def test_full_16000_samples_remain_exact_and_reserve_capacity(neutral, mode):
    values = tuple((i * 7919) % 65536 - 32768 for i in range(16000))
    if mode == 0:
        values = tuple((i * 125, value) for i, value in enumerate(values))
    item, samples, size, plan, wave, region, ip, hybrid, admission = neutral.graph(values, mode=mode)
    before = neutral.read(samples, size)
    assert neutral.call("RTE-HYBRID-PREFLIGHT", hybrid, admission, neutral.facade,
                        readonly=False) == (0,)
    summary = struct.unpack("<57Q", neutral.read(admission, 456))
    stride = 16 if mode == 0 else 8
    assert summary[:5] == (1, 2, 80, 24, 0)
    assert summary[28:33] == (1, 1, 0, 0, 0)
    assert summary[48:] == (1, 7, 16000, 16000, size, 16, 1024, 1024 * stride, 1)
    assert size == 16000 * stride
    assert neutral.read(samples, size) == before
    assert neutral.call("RTE-INSTRUMENT-VALID?", wave) == (MASK,)


@pytest.mark.parametrize("changes", [
    {"SERIES-ID": 0}, {"SERIES-ID": 6}, {"SERIES-ID": 8},
    {"MINIMUM": 32767}, {"VALUE": 32768}, {"OPTIONS": 2},
    {"SCALE": 1}, {"MODE": 1}, {"UNIT-U": 1}, {"FORMATTED-U": 1},
])
def test_waveform_requires_exact_same_candidate_series_and_valid_body(neutral, changes):
    *_, hybrid, admission = neutral.graph(wave_changes=changes)
    assert neutral.call("RTE-HYBRID-PREFLIGHT", hybrid, admission, neutral.facade) == (5,)


def test_series_only_and_empty_graphs_have_no_phantom_objects_or_samples(neutral):
    *_, hybrid, admission = neutral.graph((), waveform=False)
    assert neutral.call("RTE-HYBRID-PREFLIGHT", hybrid, admission, neutral.facade,
                        readonly=False) == (0,)
    summary = struct.unpack("<57Q", neutral.read(admission, 456))
    assert summary[:5] == (1, 2, 80, 24, 0)
    assert summary[15:48] == (0,) * 33
    assert summary[48:] == (1, 7, 16000, 16000, 0, 0, 0, 0, 0)


@pytest.mark.parametrize("target", ("plan", "items", "samples", "output"))
def test_complete_source_graph_is_disjoint_before_scratch_writes(neutral, target):
    item, samples, size, plan, wave, region, ip, hybrid, admission = neutral.graph()
    owned = neutral.runtime.find("_RTE-SRPV-COUNT").body_address
    saved = neutral.read(owned, 64)
    if target == "plan":
        neutral.cell(hybrid + _offset("_RTE-HP.SERIES-PLAN"), owned)
    elif target == "items":
        neutral.cell(plan + _offset("_RTE-SRP.ITEMS-A"), owned)
    elif target == "samples":
        neutral.cell(hybrid + _offset("_RTE-HP.SERIES-SAMPLES-A"), owned)
    else:
        admission = owned
    assert neutral.call("RTE-HYBRID-PREFLIGHT", hybrid, admission, neutral.facade) == (5,)
    assert neutral.read(owned, 64) == saved


def test_sample_bank_is_dense_exact_and_cannot_alias_other_families(neutral):
    item, samples, size, plan, wave, region, ip, hybrid, admission = neutral.graph()
    neutral.cell(item + _offset("_RTE-SERIES.SAMPLES-A"), samples + 8)
    assert neutral.call("RTE-HYBRID-PREFLIGHT", hybrid, admission, neutral.facade) == (5,)

    neutral.cell(item + _offset("_RTE-SERIES.SAMPLES-A"), samples)
    neutral.cell(hybrid + _offset("_RTE-HP.SERIES-SAMPLES-U"), size + 8)
    assert neutral.call("RTE-HYBRID-PREFLIGHT", hybrid, admission, neutral.facade) == (5,)
    neutral.cell(hybrid + _offset("_RTE-HP.SERIES-SAMPLES-U"), size)
    neutral.cell(hybrid + _offset("_RTE-HP.SERIES-SAMPLES-A"), wave)
    assert neutral.call("RTE-HYBRID-PREFLIGHT", hybrid, admission, neutral.facade) == (5,)


def test_pure_planner_authority_excludes_limits_and_nested_parser_scratch(neutral):
    ordinary = neutral.allocate(bytes(168))
    assert neutral.call("RTE-ADMISSION-STORAGE-DISJOINT?", ordinary, 168) == (MASK,)
    assert neutral.call("RTE-ADMISSION-STORAGE-DISJOINT?", 0, 0) == (MASK,)
    for address, length in ((0, 8), (MASK - 7, 16)):
        assert neutral.call("RTE-ADMISSION-STORAGE-DISJOINT?", address, length) == (0,)
    for name in ("_RTE-LV-L", "_RTE-LV-FEATURES", "_RTE-SRPV-COUNT", "_FDC1-A"):
        address = neutral.runtime.find(name).body_address
        before = neutral.read(address, 8)
        assert neutral.call("RTE-ADMISSION-STORAGE-DISJOINT?", address, 8) == (0,)
        assert neutral.read(address, 8) == before


def test_limits_validator_rejects_self_alias_before_writing(neutral):
    for name in ("_RTE-LV-L", "_RTE-LV-FEATURES"):
        address = neutral.runtime.find(name).body_address
        before = neutral.read(address, 168)
        assert neutral.call("RTE-LIMITS-VALID?", address) == (0,)
        assert neutral.read(address, 168) == before


def test_multiple_series_keep_independent_ids_capacity_and_dense_samples(neutral):
    item, samples, size, plan, wave, region, ip, hybrid, admission = neutral.graph()
    second, other_samples, other_size = neutral.series((1, 2), ID=11, CAPACITY=400,
                                                     **{"CHUNK-SAMPLES": 1})
    bank = neutral.allocate(neutral.read(samples, size) + neutral.read(other_samples, other_size))
    items = neutral.allocate(neutral.read(item, 88) + neutral.read(second, 88))
    neutral.cell(items + _offset("_RTE-SERIES.SAMPLES-A"), bank)
    neutral.cell(items + 88 + _offset("_RTE-SERIES.SAMPLES-A"), bank + size)
    neutral.cell(plan + _offset("_RTE-SRP.ITEMS-A"), items)
    neutral.cell(plan + _offset("_RTE-SRP.ITEMS-U"), 176)
    neutral.cell(hybrid + _offset("_RTE-HP.SERIES-SAMPLES-A"), bank)
    neutral.cell(hybrid + _offset("_RTE-HP.SERIES-SAMPLES-U"), size + other_size)
    neutral.cell(wave + _offset("_RTE-INSTRUMENT.SERIES-ID"), 11)
    assert neutral.call("RTE-HYBRID-PREFLIGHT", hybrid, admission, neutral.facade,
                        readonly=False) == (0,)
    summary = struct.unpack("<57Q", neutral.read(admission, 456))
    assert summary[48:] == (2, 11, 16400, 16000, 40, 3, 3, 24, 1)
    before = neutral.read(admission, 456)
    for bad_id in (0, 7, 6):
        neutral.cell(items + 88 + _offset("_RTE-SERIES.ID"), bad_id)
        assert neutral.call("RTE-HYBRID-PREFLIGHT", hybrid, admission, neutral.facade) == (5,)
        assert neutral.read(admission, 456) == before
