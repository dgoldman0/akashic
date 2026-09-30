"""Selection-only FIELD deltas preserve a complete immutable sample history.

All producer sources, packing, matching, delta admission, normalization and
retry checks execute in the native runtime. The facade records emitted leaf
operations so an unexpected SERIES publication cannot hide behind final state.
"""
import struct

import pytest

from test_data_graphics_series import series_runtime
from test_rich_field_producer import FieldHarness, model
from test_rich_glyph_growth import MASK64


class FieldSeriesHarness(FieldHarness):
    def __init__(self):
        self.runtime=series_runtime(("tui/rich-terminal/hybrid-screen-producer.f",))
        self.serial=0
        self.cache={}
        self.runtime.evaluate(b"""
VARIABLE FS-REPLACEMENTS VARIABLE FS-OTHER
: FS-DISJOINT DROP 2DROP -1 ;
: FS-OTHER-CALL 2DROP 1 FS-OTHER +! RTE-S-OK ;
: FS-REPLACE 2DROP 1 FS-REPLACEMENTS +! RTE-S-OK ;
""",source_name="delta-observer")

    def constant(self,name):
        if name not in self.cache:self.cache[name]=self.results(name)[0]
        return self.cache[name]

    def offset(self,name):
        if name not in self.cache:self.cache[name]=self.results(name,0)[0]
        return self.cache[name]

    def setup(self):
        self.producer=self.allocate(bytes(self.constant("RTHP-SIZE")))
        n=131072
        self.arena_size,=self.results("RTHP-STORAGE-BYTES-FIELDS",1,1,64,256,n,0,1024,32,8)
        self.arena=self.allocate(b"LEFTGUAR"+bytes(self.arena_size)+b"RIGHTGUA")+8
        fields={
            "ARENA-A":self.arena,"ARENA-U":self.arena_size,"MAX-DOCUMENTS":1,
            "MAX-RECORDS":1,"MAX-TEXT":64,"MAX-COLLECTION-NATIVE":256,
            "MAX-COLLECTION-DESCRIPTORS":8,"MAX-COLLECTIONS":4,"MAX-CONTROLS":10,
            "MAX-DGRAPH-NATIVE":n,"MAX-DGRAPH-DESCRIPTORS":1,
            "MAX-INSTRUMENT-REGIONS":1,"MAX-INSTRUMENTS":n//128,
            "MAX-SERIES":n//72,"MAX-FIELD-NATIVE":1024,"MAX-FIELDS":5,
            "MAX-COLS":32,"MAX-ROWS":8,"COLS":32,"ROWS":8,
            "OWNER":1,"OWNER-GEN":2,"REGION":7,"FIRST-OBJECT":100,
            "SOURCE-GEN":9,"SOURCE-CONTENT-EPOCH":29,"SOURCE-DRAW":12,
            "SURFACE-GEN":12,"PHYSICAL-GEN":1,"DOCUMENT-COUNT":1,
            "FIRST-SERIES":300,"NEXT-SERIES":301,
        }
        for name,value in fields.items():self.field(self.producer,"_RTHP."+name,value)
        self.results("_RTHP-LAYOUT",self.producer)
        self.bank_size,valid=self.results("_RTHP-TARGET-BANK-BYTES?",self.producer)
        assert valid==MASK64
        self.dir=self.get("SOURCE-DIR-A")
        self.field(self.producer,"_RTHP.SOURCE-DIR-USED",self.constant("RUHA-DOCUMENT-SIZE"))
        self.runtime.memory.write_bytes(self.dir,struct.pack("<6Q",11,5,0,0,8,32))
        for name,value in {"INSTRUMENT-COUNT":1,"INSTRUMENT-REGION-COUNT":1,
                           "SERIES-COUNT":1,"SERIES-SLOTS":16000,"SERIES-SAMPLES-USED":128000,
                           "SERIES-CHUNKS":4,"SERIES-HISTORY-MAX":16000,
                           "SERIES-CHUNK-MAX":4096,"SERIES-CHUNK-BYTES-MAX":32768,
                           "WAVEFORM-COUNT":1,"GLYPH-COUNT":1,"GLYPH-TEXT-USED":1}.items():
            self.field(self.producer,"_RTHP."+name,value)
        self.field(self.producer+self.offset("_RTHP.LIMITS"),"_RTE-L.GLYPH-RUN-BYTES",256)
        self.samples=struct.pack("<16000q",*(i-8000 for i in range(16000)))
        self.runtime.memory.write_bytes(self.get("SERIES-SAMPLES-A"),self.samples)
        self.facade=self.allocate(bytes(self.constant("RTE-FACADE-SIZE")))
        for name,value in {"MAGIC":self.constant("_RTE-MAGIC"),
                           "SIZE":self.constant("RTE-FACADE-SIZE"),
                           "SELF":self.facade,"CONTEXT":1}.items():
            self.field(self.facade,"_RTE-F."+name,value)
        for offset in range(48,self.constant("RTE-FACADE-SIZE"),8):
            self.runtime.memory.write64(self.facade+offset,self.runtime.find("FS-OTHER-CALL").xt)
        self.field(self.facade,"_RTE-F.DISJOINT-XT",self.runtime.find("FS-DISJOINT").xt)
        self.field(self.facade,"_RTE-F.CONTROL-REPLACE-XT",self.runtime.find("FS-REPLACE").xt)
        self.field(self.producer,"_RTHP.FACADE",self.facade)
        self.active=self.stage(0,first=100,region=7,series=300,draw=12,selected=0)
        self.active_bytes=self.runtime.memory.read_bytes(self.active,self.bank_size)
        self.pending=self.stage(1,first=104,region=17,series=301,draw=13,selected=1)
        for name,value in {"TARGET-ACTIVE":self.active,"TARGET-PENDING":self.pending,
                           "ACTIVE-DRAW":12,"NEXT-OBJECT":104,"ATTEMPT":13}.items():
            self.field(self.producer,"_RTHP."+name,value)

    def stage(self,index,*,first,region,series,draw,selected):
        m=self.runtime.memory
        self.field(self.producer,"_RTHP.FIRST-OBJECT",first)
        self.field(self.producer,"_RTHP.REGION",region)
        self.field(self.producer,"_RTHP.FIRST-SERIES",series)
        for name,value in {"SURFACE-GEN":draw,"SOURCE-DRAW":draw,"SOURCE-GEN":draw,
                           "SOURCE-CONTENT-EPOCH":29+draw,"ATTEMPT":draw}.items():
            self.field(self.producer,"_RTHP."+name,value)
        self.field(self.producer,"_RTHP.CONTROL-COUNT",0)
        self.field(self.producer,"_RTHP.SOURCE-TEXT-USED",0)
        self.field(self.producer,"_RTHP.CLAIMS-USED",0)
        native=bytearray();descriptors=bytearray()
        for i in range(2):
            body=model(state=7 if i==selected else 3)
            descriptors.extend(struct.pack("<16Q",1,4+i,6,99,len(native),i*3,0,3,20,
                                            i*3,0,3,20,3,len(body),4))
            native.extend(body)
        m.write_bytes(self.get("FIELD-NATIVE-A"),native)
        m.write_bytes(self.get("FIELD-DESCRIPTORS-A"),descriptors)
        self.field(self.producer,"_RTHP.FIELD-NATIVE-USED",len(native))
        self.field(self.producer,"_RTHP.FIELD-DESCRIPTORS-USED",len(descriptors))
        for off,value in ((192,0),(200,len(descriptors)),(208,0),(216,len(native))):
            m.write64(self.dir+off,value)
        assert self.build()==(0,)
        m.write_bytes(self.get("INSTRUMENT-REGIONS-A"),struct.pack("<12Q",region+1,0,0,32,8,0,0,0,0,1,1,0))
        instrument=(1,2,first+2,4,MASK64,0,region+1,0,6,0,1,20,8,32,
                    0xFFFFFFFF,0x777777FF,0,0,-32768,32767,0,1,0,0,0,0,series)
        m.write_bytes(self.get("INSTRUMENTS-A"),struct.pack("<27Q",*(n&MASK64 for n in instrument)))
        m.write_bytes(self.get("INSTRUMENT-CORR-A"),struct.pack("<10Q",1,8,9,10,11,12,13,region+1,first+2,0))
        m.write_bytes(self.get("SERIES-A"),struct.pack("<11Q",1,2,series,16000,1,125,0,
                                                     self.get("SERIES-SAMPLES-A"),128000,4096,0))
        m.write_bytes(self.get("SERIES-CORR-A"),struct.pack("<10Q",1,8,9,10,11,12,14,region+1,series,0))
        item=(first+3,0,7,0,1,1,8,32,0,MASK64,0,0,0,1,0)
        m.write_bytes(self.get("GLYPH-ITEMS-A"),struct.pack("<15Q",*item))
        m.write_bytes(self.get("GLYPH-REFS-A"),struct.pack("<2Q",0,1))
        m.write_bytes(self.get("GLYPH-TEXT-A"),b"A")
        bank=self.get(f"TARGET{index}-A")
        headers={"COLS":32,"ROWS":8,"DOCUMENT-COUNT":1,"OWNER":1,"GENERATION":2,
                 "REGION":region,"FIRST-OBJECT":first,"DRAW":draw,"SOURCE-GEN":draw,
                 "PHYSICAL-GEN":1,"CONTENT-EPOCH":29+draw,"GLYPH-RUN-LIMIT":256,
                 "CONTROL-COUNT":2,"FIELD-COUNT":2,"FIELD-UTF8":8,
                 "SOURCE-TEXT-USED":self.get("SOURCE-TEXT-USED"),
                 "GLYPH-SLOT-COUNT":1,"GLYPH-TEXT-USED":1,"INSTRUMENT-COUNT":1,
                 "INSTRUMENT-REGION-COUNT":1,"SERIES-COUNT":1,"FIRST-SERIES":series,
                 "SERIES-SAMPLE-BYTES":128000,"SERIES-SLOTS":16000,"SERIES-CHUNKS":4,
                 "SERIES-HISTORY-MAX":16000,"SERIES-CHUNK-MAX":4096,
                 "SERIES-CHUNK-BYTES-MAX":32768,"WAVEFORM-COUNT":1}
        for name,value in headers.items():self.field(bank,"_RTHP-TB."+name,value)
        self.variable("_RTHP-TG-P",self.producer);self.variable("_RTHP-TG-BANK",bank)
        self.variable("_RTHP-TG-COUNT",0);self.variable("_RTHP-CT-P",self.producer)
        assert self.call("_RTHP-TG-FIELD-TARGETS?")
        self.field(bank,"_RTHP-TB.COUNT",self.variable("_RTHP-TG-COUNT"))
        assert self.call("_RTHP-PACK-CANDIDATE",bank,self.producer)
        assert self.call("_RTHP-TARGET-BANK-HEADER?",bank,self.producer), (
            index,self.results("_RTHP-PACKED-BANK?",bank,self.producer),
            self.results("_RTHP-TARGET-MENU-DIRECTORY?"),
        )
        return bank


@pytest.fixture
def mixed():
    h=FieldSeriesHarness();h.setup();return h


def test_selected_fields_reuse_full_history_through_delta_and_delayed_emit(mixed):
    h=mixed
    assert h.call("_RTHP-DELTA-CANDIDATE?",h.producer)
    assert h.get("DELTA-PLAN-CONTROLS")==2 and h.get("DELTA-PLAN-GLYPHS")==0
    assert h.call("_RTHP-D-PLAN-BIND?",h.producer)
    assert h.call("_RTHP-INSTRUMENTS-REUSABLE?",h.active,h.pending,MASK64)
    series=h.results("_RTHP-PACK-SERIES-A",h.pending)[0]
    wave=h.results("_RTHP-PACK-INSTRUMENTS-A",h.pending)[0]
    samples=h.results("_RTHP-PACK-SERIES-SAMPLES-A",h.pending)[0]
    assert h.runtime.memory.read64(series+16)==300
    assert h.runtime.memory.read64(wave+16)==102
    assert h.runtime.memory.read64(wave+208)==300
    assert h.runtime.memory.read_bytes(samples,128000)==h.samples
    assert h.results("_RTHP-EMIT-DELTA",h.producer)==(0,)
    assert h.variable("FS-REPLACEMENTS")==2 and h.variable("FS-OTHER")==0
    assert h.runtime.memory.read_bytes(h.active,len(h.active_bytes))==h.active_bytes
    assert h.get("NEXT-OBJECT")==104 and h.get("NEXT-SERIES")==301
    h.guards()


@pytest.mark.parametrize("mutation",["revision","value","disabled","geometry"])
def test_field_payload_or_nonselection_changes_still_refuse_history_delta(mixed,mutation):
    h=mixed
    control=h.results("_RTHP-D-CONTROL-AT",0,h.pending)[0]
    content=h.runtime.memory.read64(control+152)
    if mutation=="revision":h.runtime.memory.write64(content+8,18)
    elif mutation=="value":h.runtime.memory.write64(content+56,8)
    elif mutation=="disabled":h.runtime.memory.write64(control+32,1)
    else:h.runtime.memory.write64(control+80,1)
    before=h.runtime.memory.read_bytes(h.pending,h.bank_size)
    assert not h.call("_RTHP-DELTA-CANDIDATE?",h.producer)
    assert h.get("DELTA-PLAN-VALID")==0
    assert h.runtime.memory.read_bytes(h.pending,len(before))==before
    assert h.runtime.memory.read_bytes(h.active,len(h.active_bytes))==h.active_bytes
    assert h.variable("FS-REPLACEMENTS")==h.variable("FS-OTHER")==0


def test_native_pt_host_field_selection_delta_emits_no_history_operations():
    """The real provider/host accepts the exact unchanged-revision state edit."""
    from unittest.mock import patch
    import test_rich_terminal_cell_feed as cf
    import test_rich_terminal_series_engine as series
    from test_rich_terminal_field_engine import FieldProvider
    from rich_terminal.retained_model import RetainedFeature
    from rich_terminal.retained_wire import RetainedMessageType

    original=cf._fixture_source

    def fixture(cols):
        return original(cols).replace(
            b"CREATE CF-LEDGER-MEM RTAPT-CONTROL-LEDGER-SIZE 7 + ALLOT",
            b"CREATE CF-LEDGER-MEM RTAPT-CONTROL-LEDGER-SIZE 2 * 7 + ALLOT",
        ).replace(b"CF-LEDGER RTAPT-CONTROL-LEDGER-SIZE\n",
                  b"CF-LEDGER RTAPT-CONTROL-LEDGER-SIZE 2 *\n")

    with patch.object(cf,"_fixture_source",side_effect=fixture), patch.object(
            series,"FEATURES",series.FEATURES|RetainedFeature.CONTROLS|RetainedFeature.FIELDS):
        h=series.SeriesProvider("native")
    try:
        h.begin()
        values=tuple(i-8000 for i in range(16000))
        record,_=h.series(values,chunk=64,identity=300)
        assert h.define(record,neutral=True)==(0,)
        assert h.define_waveform(h.waveform(series=300,identity=102),neutral=True)==(0,)
        for i,state in enumerate((11,3)):
            control,_=FieldProvider.control(h,ID=100+i,ROW=i,STATE=state)
            assert FieldProvider.define(h,control)==(0,)
        h.publish()
        owner=h.installed()
        history,waveform=owner.series[300],owner.objects[102]
        before_samples=h.samples(300)
        before_frames=dict(h.driver.core.frames_received_by_type)
        h.begin("PT-RET-DELTA")
        for i,state in enumerate((3,11)):
            control,text=FieldProvider.control(h,ID=100+i,ROW=i,STATE=state)
            assert FieldProvider.define(h,control,replace=True)==(0,)
            # Committed replacement must be independent of both borrowed spans.
            h.runtime.memory.write_bytes(text,b"X"*(5+96))
            h.runtime.memory.write64(control+32,1)
        assert h.field("_RTAPT-E.OP-COUNT")==2
        assert all(op[0]==h.constant("_RTAPT-OP-CONTROL-REPLACE") for op in h.operations())
        h.publish(reveal=False)
        after=h.installed()
        assert after.series[300]==history and after.objects[102]==waveform
        assert h.samples(300)==before_samples==tuple((i*125,value) for i,value in enumerate(values))
        assert [int(after.controls[i].state) for i in (100,101)]==[3,11]
        assert [after.controls[i].content.content_revision for i in (100,101)]==[7,7]
        for kind in (RetainedMessageType.SERIES_DEFINE,RetainedMessageType.SERIES_REPLACE,
                     RetainedMessageType.SERIES_APPEND):
            assert h.driver.core.frames_received_by_type.get(int(kind),0)==before_frames.get(int(kind),0)
        assert h.driver.core.frames_received_by_type[int(RetainedMessageType.CONTROL_REPLACE)]-before_frames.get(
            int(RetainedMessageType.CONTROL_REPLACE),0)==2
    finally:
        h.close()
