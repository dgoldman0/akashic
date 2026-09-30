"""Explicit catalog aggregate admission stays scalar and mutation-free."""
import hashlib
import struct
from dataclasses import replace
from unittest.mock import patch
import pytest
from test_rich_terminal_status_provider import ProviderHarness, RetainedFeature
from test_rich_terminal_status_static import MASK
import test_rich_terminal_cell_feed as cf


class FamilyProvider(ProviderHarness):
    def __init__(self, backend, *, extra_features=RetainedFeature(0)):
        policy = replace(cf._retained_policy(),
                         features=RetainedFeature.CORE | RetainedFeature.PANES | extra_features,
                         max_operations_per_transaction=16,
                         max_retained_transaction_bytes=4096,
                         base_max_transaction_bytes=4096,
                         max_objects=4,total_utf8_bytes=128,
                         max_glyph_run_bytes=16 if extra_features & RetainedFeature.INSTRUMENT else 0)
        with patch.object(cf, "_retained_policy", return_value=policy):
            super().__init__(backend, features=(RetainedFeature.CORE |
                                               RetainedFeature.PANES | extra_features))
        # Negotiation may populate only the provider's documented limits cache.
        # All subsequent snapshots include that cache and every owned bank.
        assert self.call("RTAPT-LIMITS@", self.engine)[0][1] == 0

    def summary(self, changes=None):
        values = {0:1,8:1,16:20,24:2,32:1,40:544,456:2,464:2,
                  472:1,480:1,488:1,496:4,504:8,512:4,520:1,536:0x201}
        values.update(changes or {})
        data = bytearray(544)
        for offset,value in values.items():
            struct.pack_into("<Q",data,offset,value & MASK)
        return self.allocate(data)

    def snapshot(self):
        return tuple(hashlib.sha256(self.runtime.memory.read_bytes(a,u)).digest()
                     for a,u in ((self.engine,self.constant("RTAPT-ENGINE-SIZE")),
                                 (self.constant("CF-OWNERS"),self.constant("RTAPT-OWNER-SIZE")),
                                 (self.field("_RTAPT-E.OPS-A"),self.field("_RTAPT-E.OPS-U")),
                                 (self.field("_RTAPT-E.COPY-A"),self.field("_RTAPT-E.COPY-U"))))


@pytest.fixture(params=("python","native"))
def family(request):
    h = FamilyProvider(request.param)
    try:
        yield h
    finally:
        h.close()


def test_family_pane_catalog_is_admitted_once_without_mutation(family):
    h = family
    summary = h.summary()
    source = h.runtime.memory.read_bytes(summary,544)
    before = h.snapshot()
    assert h.call("RTAPT-FAMILY-PREFLIGHT",summary,h.engine)[0] == (0,)
    assert h.snapshot() == before
    assert h.runtime.memory.read_bytes(summary,544) == source
    assert h.runtime.memory.read_bytes(h.constant("_RTAPT-FA-WORK"),544) == bytes(544)


@pytest.mark.parametrize("changes",[
    {32:0},{40:456},{48:1},{112:1},{536:1},{536:0x221},{528:1},
    {456:1},{464:1},{472:2},{480:2},{504:16},{488:0},{512:5},
])
def test_family_malformed_fixed_summary_refuses_without_mutation(family,changes):
    h = family
    summary = h.summary(changes)
    before = h.snapshot()
    assert h.call("RTAPT-FAMILY-PREFLIGHT",summary,h.engine)[0] == (3,)
    assert h.snapshot() == before


def test_family_uses_exact_owned_copy_and_frame_capacities(family):
    h = family
    summary = h.summary()
    for field,exact in (("_RTAPT-E.COPY-U",400),):
        address = h.call(field,h.engine)[0][0]
        prior = h.runtime.memory.read64(address)
        h.runtime.memory.write64(address,exact-8)
        assert h.call("RTAPT-FAMILY-PREFLIGHT",summary,h.engine)[0] == (5,)
        h.runtime.memory.write64(address,exact)
        assert h.call("RTAPT-FAMILY-PREFLIGHT",summary,h.engine)[0] == (0,)
        h.runtime.memory.write64(address,prior)


def test_family_summary_cannot_alias_module_query_scratch(family):
    h = family
    before = h.snapshot()
    for word in ("_RTAPT-FA-WORK","_RTAPT-FA-SOURCE","_RTAPT-HAF-OWNER"):
        assert h.call("RTAPT-FAMILY-PREFLIGHT",h.constant(word),h.engine)[0] == (3,)
        assert h.snapshot() == before


@pytest.mark.parametrize("backend", ("python", "native"))
@pytest.mark.parametrize("features,changes,copy_bytes", [
    (RetainedFeature.STATUS_FIELDS,
     {320:1,328:4,336:8,344:4,352:2,360:184,368:1,480:2,536:0x601},584),
    (RetainedFeature.INSTRUMENT,
     {224:1,232:1,248:1,304:2,480:2,536:0x209},616),
    (RetainedFeature.CONTROLS | RetainedFeature.TASKBARS,
     {120:1,152:1,480:2,520:2,528:1,536:0xA41},560),
])
def test_family_mixed_families_share_catalog_once(backend,features,changes,copy_bytes):
    h = FamilyProvider(backend,extra_features=features)
    try:
        summary = h.summary(changes)
        before = h.snapshot()
        assert h.call("RTAPT-FAMILY-PREFLIGHT",summary,h.engine)[0] == (0,)
        assert h.snapshot() == before
        address = h.call("_RTAPT-E.COPY-U",h.engine)[0][0]
        prior = h.runtime.memory.read64(address)
        h.runtime.memory.write64(address,copy_bytes-8)
        assert h.call("RTAPT-FAMILY-PREFLIGHT",summary,h.engine)[0] == (5,)
        h.runtime.memory.write64(address,copy_bytes)
        assert h.call("RTAPT-FAMILY-PREFLIGHT",summary,h.engine)[0] == (0,)
        h.runtime.memory.write64(address,prior)
        assert h.snapshot() == before
    finally:
        h.close()


def test_family_capability_recheck_refuses_before_owner_or_bank_changes(family):
    h = family
    summary = h.summary()
    session = h.field("_RTAPT-E.SESSION")
    caps,_ = h.call("PT-RETAINED-CAPS@",session)[0]
    formats,_ = h.call("PT-RETAINED-FORMATS@",session)[0]
    original = h.runtime.memory.read64(caps+8)
    original_utf8 = h.runtime.memory.read64(formats+48)
    h.runtime.memory.write64(caps+8,original & ~0x800)
    h.runtime.memory.write64(formats+48,0)
    assert h.call("RTAPT-LIMITS@",h.engine)[0][1] == 0
    before = h.snapshot()
    assert h.call("RTAPT-FAMILY-PREFLIGHT",summary,h.engine)[0] == (4,)
    assert h.snapshot() == before
    h.runtime.memory.write64(caps+8,original)
    h.runtime.memory.write64(formats+48,original_utf8)


def test_family_summary_full_span_rejects_caller_bank_aliases(family):
    h = family
    for address in (h.engine,h.constant("CF-OWNERS"),
                    h.field("_RTAPT-E.OPS-A"),h.field("_RTAPT-E.COPY-A")):
        before = h.snapshot()
        assert h.call("RTAPT-FAMILY-PREFLIGHT",address,h.engine)[0] == (3,)
        assert h.snapshot() == before


@pytest.mark.parametrize("backend", ("python", "native"))
@pytest.mark.parametrize("sampled", (False, True))
def test_family_series_only_initial_admission_has_no_phantom_region(backend,sampled):
    from test_rich_terminal_series_engine import SeriesProvider
    h = SeriesProvider(backend,open_owner=False)
    try:
        values = {0:1,8:1,16:20,24:2,32:1,40:544,
                  384:1,392:1,400:9,408:9,416:40 if sampled else 0,
                  424:3 if sampled else 0,432:2 if sampled else 0,
                  440:16 if sampled else 0,536:0x19}
        payload = bytearray(544)
        for offset,value in values.items():
            struct.pack_into("<Q",payload,offset,value)
        summary = h.allocate(payload)
        before = h.snapshot()
        assert h.call("RTAPT-FAMILY-PREFLIGHT",summary,h.engine)[0] == (0,)
        assert h.snapshot() == before
        assert h.runtime.memory.read_bytes(summary,544) == payload
        h.runtime.memory.write64(summary+456,1)
        h.runtime.memory.write64(summary+464,1)
        assert h.call("RTAPT-FAMILY-PREFLIGHT",summary,h.engine)[0] == (3,)
        assert h.snapshot() == before
    finally:
        h.close()
