"""Real family emission preserves catalog identity, owned bytes and failure scope."""
from unittest.mock import patch
import pytest
from test_rich_terminal_family_bridge import Bridge
import test_rich_terminal_status_provider as stp
from test_rich_terminal_status_static import RICH, _clean


class Emitter(Bridge):
    def __init__(self,backend):
        bridge_source = (RICH / "engine-apt1.f").read_text()
        emitter_source = _clean((RICH / "shell-family-emit.f").read_text())
        def closure(source):
            result = _clean(source)
            if source == bridge_source:
                result += ("\n" + emitter_source +
                           "\n: FEM-FAIL 2DROP RTE-S-CAPACITY ;\n"
                           ": FEM-THROW 2DROP -321 THROW ;\n")
            return result
        with patch.object(stp,"_clean",side_effect=closure):
            super().__init__(backend)

    def start(self,batch,summary):
        assert self.call("RTE-FAMILY-BATCH-PREFLIGHT",batch,summary,self.shell)[0] == (0,)
        assert self.call("RTE-RETAINED-BEGIN",self.constant("RTE-RETAINED-REPLACE-START"),self.facade)[0] == (0,)


@pytest.fixture(params=("python","native"))
def emitter(request):
    h = Emitter(request.param)
    try:
        yield h
    finally:
        h.close()


def test_emits_six_families_and_each_catalog_region_once(emitter):
    h = emitter
    batch,summary,records = h.graph(mixed=True)
    h.start(batch,summary)
    assert h.call("RTE-FAMILY-BATCH-EMIT",batch,h.shell)[0] == (0,)
    assert h.field("_RTAPT-E.OP-COUNT") == 10
    assert h.field("_RTAPT-E.UPDATE-STATE") == h.constant("RTAPT-UPDATE-CAPTURING")
    assert h.runtime.memory.read_bytes(h.constant("_RTE-FEM-RUN"),152) == bytes(152)
    h.runtime.memory.write_bytes(records["title"],b"xxxx")
    h.runtime.memory.write_bytes(records["control_text"],b"xxxxxx")
    h.runtime.memory.write_bytes(records["glyph_text"],b"xxxx")
    h.publish()
    owner = h.installed()
    assert set(owner.regions) == {1,2}
    assert set(owner.controls) == {1,2,3}
    assert set(owner.objects) == {4,5,6,7}
    assert owner.objects[7].body.title == "Pane"
    assert owner.controls[2].label == "App"
    assert owner.controls[3].label == "Run"
    assert owner.objects[6].body.text == "Cell"
    assert len(owner.series) == 1


def test_zero_chrome_pane_keeps_explicit_empty_content_region(emitter):
    h = emitter
    batch,summary,records = h.graph()
    pane = records["pane"]
    # Keep logical geometry but use the canonical physically empty clip.
    catalog = h.runtime.memory.read64(batch+8)
    regions = h.runtime.memory.read64(catalog+32)
    for offset in (40,48,56,64):
        h.runtime.memory.write64(regions+96+offset,0)
    h.runtime.memory.write64(pane+120,0)
    h.runtime.memory.write64(pane+136,2)
    h.start(batch,summary)
    assert h.call("RTE-FAMILY-BATCH-EMIT",batch,h.shell)[0] == (0,)
    assert h.field("_RTAPT-E.OP-COUNT") == 3
    h.publish()
    assert h.installed().objects[1].body.content_region_id == 2


@pytest.mark.parametrize("word",("_RTE-FEM-BATCH","_RTE-FEM-SHELL","_RTE-FEM-RUN","_RTE-FEM-ENTRY"))
def test_emitter_rejects_borrowed_header_alias_before_any_store(emitter,word):
    h = emitter
    address = h.constant(word)
    before = h.read(address,72)
    provider = h.snapshot()
    assert h.call("RTE-FAMILY-BATCH-EMIT",address,h.shell)[0] == (h.constant("RTE-S-INVALID"),)
    assert h.read(address,72) == before
    assert h.snapshot() == provider


def test_invalid_membership_refuses_before_any_capture(emitter):
    h = emitter
    batch,summary,records = h.graph(mixed=True)
    h.start(batch,summary)
    h.runtime.memory.write64(records["pane"]+112,999)
    before = h.snapshot()
    assert h.call("RTE-FAMILY-BATCH-EMIT",batch,h.shell)[0] == (h.constant("RTE-S-INVALID"),)
    assert h.snapshot() == before


@pytest.mark.parametrize("word,status",(("FEM-FAIL","RTE-S-CAPACITY"),("FEM-THROW","RTE-S-INVALID")))
def test_provider_failure_is_returned_without_implicit_lifecycle_or_fallback(emitter,word,status):
    h = emitter
    batch,summary,records = h.graph(mixed=True)
    h.start(batch,summary)
    field = h.call("_RTE-F.STATIC-DEF-XT",h.facade)[0][0]
    original = h.runtime.memory.read64(field)
    h.runtime.memory.write64(field,h.runtime.find(word).xt)
    scene = h.driver.core.retained_state
    frames = h.driver.core.frames_received
    assert h.call("RTE-FAMILY-BATCH-EMIT",batch,h.shell)[0] == (h.constant(status),)
    # Regions, controls, series and waveform were captured before static failed.
    assert h.field("_RTAPT-E.OP-COUNT") == 7
    assert h.field("_RTAPT-E.UPDATE-STATE") == h.constant("RTAPT-UPDATE-CAPTURING")
    assert h.driver.core.retained_state is scene
    assert h.driver.core.frames_received == frames
    assert h.runtime.memory.read_bytes(h.constant("_RTE-FEM-RUN"),152) == bytes(152)
    h.runtime.memory.write64(field,original)
    assert h.call("RTE-RETAINED-CANCEL",h.facade)[0] == (0,)
    assert h.field("_RTAPT-E.OP-COUNT") == 0


def test_nested_text_cannot_alias_emitter_scratch(emitter):
    h = emitter
    batch,summary,records = h.graph()
    h.start(batch,summary)
    scratch = h.constant("_RTE-FEM-RUN")
    entry = h.runtime.memory.read64(batch+24)
    h.runtime.memory.write64(entry+24,scratch)
    h.runtime.memory.write64(records["pane"]+160,scratch)
    before = h.read(scratch,152)
    provider = h.snapshot()
    assert h.call("RTE-FAMILY-BATCH-EMIT",batch,h.shell)[0] == (h.constant("RTE-S-INVALID"),)
    assert h.read(scratch,152) == before
    assert h.snapshot() == provider
