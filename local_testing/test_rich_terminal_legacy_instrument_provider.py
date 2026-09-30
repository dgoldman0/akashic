"""Legacy instruments keep exact copied bodies after the SERIES ABI extension."""

import struct
from dataclasses import replace
from unittest.mock import patch

import pytest

from test_rich_terminal_status_provider import ProviderHarness, RetainedFeature
from test_rich_terminal_status_static import MASK
import test_rich_terminal_cell_feed as cf
from rich_terminal.retained_scene import MeterBody, ReadoutBody, StatusBody


@pytest.fixture(params=("python", "native"))
def provider(request):
    policy = replace(cf._retained_policy(), max_objects=4,
                     total_utf8_bytes=128, max_glyph_run_bytes=128)
    with patch.object(cf, "_retained_policy", return_value=policy):
        harness = ProviderHarness(
            request.param, features=RetainedFeature.CORE | RetainedFeature.INSTRUMENT,
        )
    try:
        yield harness
    finally:
        harness.close()


@pytest.mark.parametrize("kind", (1, 2, 3), ids=("readout", "meter", "status"))
def test_legacy_instrument_copy_wire_and_abort_without_series_capability(provider, kind):
    unit = provider.allocate(b"Hz") if kind == 1 else 0
    fields = [1, 1, 1, kind, MASK, 0, 1, 0, 0, 0, 1, 20, 2, 20,
              0x112233FF, 0x445566FF, 0, 0, 0, 0, 42, 0, 0, 0, 0, 0, 0]
    if kind == 1:
        fields[21:25] = [1, unit, 2, 4]
    elif kind == 2:
        fields[17:20] = [1, 0, 100]
    record = provider.allocate(struct.pack("<27Q", *fields))
    provider.begin()
    before = tuple(provider.field(name) for name in (
        "_RTAPT-E.OP-COUNT", "_RTAPT-E.COPY-USED", "_RTAPT-E.RET-BYTES",
    ))
    # The appended reference belongs only to WAVEFORM; legacy kinds must reject
    # it before copying or accounting, at both public layers.
    provider.runtime.memory.write64(record + 208, 7)
    for word, target, invalid in (("RTE-INSTRUMENT-DEFINE", provider.facade, "RTE-S-INVALID"),
                                  ("RTAPT-INSTRUMENT-DEFINE", provider.engine, "RTAPT-S-INVALID")):
        assert provider.call(word, record, target)[0] == (provider.constant(invalid),)
        assert tuple(provider.field(name) for name in (
            "_RTAPT-E.OP-COUNT", "_RTAPT-E.COPY-USED", "_RTAPT-E.RET-BYTES",
        )) == before
    provider.runtime.memory.write64(record + 208, 0)
    assert provider.call("RTE-INSTRUMENT-DEFINE", record, provider.facade)[0] == (0,)
    assert provider.field("_RTAPT-E.OP-COUNT") == 2
    assert provider.field("_RTAPT-E.COPY-USED") == 104 + 216 + (8 if kind == 1 else 0)
    provider.runtime.memory.write64(record + 160, 99)
    if unit:
        provider.runtime.memory.write_bytes(unit, b"xx")
    provider.publish()
    original = provider.driver.core.retained_state
    owner = provider.installed()
    body = owner.objects[1].body
    assert isinstance(body, {1: ReadoutBody, 2: MeterBody, 3: StatusBody}[kind])
    assert body.value == 42
    assert owner.usage.objects == 1 and owner.usage.utf8_bytes == (4 if kind == 1 else 0)
    assert not owner.series
    if kind == 1:
        assert body.unit == "Hz" and body.scale == 1
    elif kind == 2:
        assert (body.minimum, body.maximum, body.vertical, body.show_value) == (0, 100, False, True)
    else:
        assert body.shape == 0

    provider.begin(region=2)
    provider.runtime.memory.write64(record + 16, 2)
    provider.runtime.memory.write64(record + 48, 2)
    assert provider.call("RTE-INSTRUMENT-DEFINE", record, provider.facade)[0] == (0,)
    copied = provider.field("_RTAPT-E.COPY-A") + 104
    assert provider.runtime.memory.read64(copied + 160) == 99
    provider.runtime.memory.write64(record + 160, 3)
    assert provider.call("RTAPT-RICH-CANCEL", provider.engine)[0] == (0,)
    assert provider.driver.core.retained_state is original
    assert provider.installed().objects[1].body.value == 42
