"""Production neutral, provider and wire FIELD routes on both engines."""
import struct
import pytest
from test_rich_terminal_fdc1 import content, changed
from test_rich_terminal_status_provider import ProviderHarness, RetainedFeature
from test_rich_terminal_status_static import MASK, StaticHarness, _offset

FEATURES = RetainedFeature.CORE | RetainedFeature.CONTROLS | RetainedFeature.FIELDS


class FieldProvider(ProviderHarness):
    def __init__(self, backend):
        super().__init__(backend, features=FEATURES)

    def control(self, payload=None, label=b'Field', *, items=0, utf8=0, **changes):
        payload = content() if payload is None else payload
        text = self.allocate(label + payload)
        values = dict(OWNER=1, GENERATION=1, ID=1, KIND=13, STATE=3, Z=0,
                      REGION=1, PARENT=0, ORDER=0, ROW=0, COL=0, HEIGHT=1, WIDTH=20,
                      **{'ROOT-HEIGHT':2, 'ROOT-WIDTH':20, 'LABEL-A':text if label else 0,
                         'LABEL-U':len(label), 'SHORTCUT-A':0, 'SHORTCUT-U':0,
                         'CONTENT-A':text+len(label), 'CONTENT-U':len(payload),
                         'CONTENT-ITEMS':items, 'CONTENT-UTF8':utf8,
                         'CONTENT-RUNS':0, 'CONTENT-FIELDS':0})
        values.update(changes)
        data = bytearray(200)
        for name,value in values.items():
            struct.pack_into('<Q', data, _offset('_RTE-CONTROL.'+name), value & MASK)
        return self.allocate(data), text

    def define(self, record, replace=False):
        return self.call('RTE-CONTROL-REPLACE' if replace else 'RTE-CONTROL-DEFINE',
                         record, self.facade)[0]

    def direct(self, record, replace=False):
        values=struct.unpack('<25Q',self.runtime.memory.read_bytes(record,200))
        return self.call('RTAPT-CONTROL-REPLACE' if replace else 'RTAPT-CONTROL-DEFINE',
                         *values, self.engine)[0]


@pytest.fixture(params=('python','native'))
def field(request):
    harness=FieldProvider(request.param)
    try:
        yield harness
    finally:
        harness.close()


@pytest.mark.parametrize('body,items,utf8,value', [
    (content(),0,0,5),
    (content(kind=2,value=-99,choices=((-99,b'Sine'),(42,b'Square'))),2,10,-99),
    (content(kind=3,text='Café'.encode()),0,5,0),
])
def test_field_publication_owns_exact_source_and_shared_quotas(field,body,items,utf8,value):
    field.begin()
    record,text=field.control(body,items=items,utf8=utf8)
    assert field.define(record) == (0,)
    assert field.field('_RTAPT-E.OP-COUNT') == 2
    assert field.field('_RTAPT-E.COPY-USED') == 104+160+((5+len(body)+7)&-8)
    field.runtime.memory.write_bytes(text,b'X'*(5+len(body)))
    field.runtime.memory.write64(record+96,999)
    field.publish()
    owner=field.installed()
    control=owner.controls[1]
    assert control.kind.value == 13
    assert control.label == 'Field'
    assert control.content.value == value
    assert control.bounds.cell_cols == 20
    assert owner.usage.objects == 1+items
    assert owner.usage.utf8_bytes == 5+utf8
    assert field.owner_field('_RTAPT-O.ACTIVE-CONTROLS') == 1
    assert field.owner_field('_RTAPT-O.ACTIVE-CONTENT-ITEMS') == items
    assert field.owner_field('_RTAPT-O.ACTIVE-CONTROL-UTF8') == 5+utf8


def test_field_replace_choice_quota_delta_and_abort(field):
    field.begin()
    initial=content(kind=2,value=1,choices=((1,b'one'),(2,b'two')))
    record,_=field.control(initial,items=2,utf8=6)
    assert field.define(record) == (0,)
    field.publish()
    original=field.driver.core.retained_state
    field.begin('PT-RET-DELTA')
    newer=content(kind=3,text=b'x',revision=8)
    record,text=field.control(newer,utf8=1)
    assert field.define(record,replace=True) == (0,)
    field.runtime.memory.write_bytes(text,b'X'*(5+len(newer)))
    assert field.call('RTAPT-RICH-CANCEL',field.engine)[0] == (0,)
    assert field.driver.core.retained_state is original
    assert field.owner_field('_RTAPT-O.ACTIVE-CONTENT-ITEMS') == 2
    field.begin('PT-RET-DELTA')
    record,text=field.control(newer,utf8=1)
    assert field.define(record,replace=True) == (0,)
    field.runtime.memory.write_bytes(text,b'X'*(5+len(newer)))
    field.publish(reveal=False)
    assert field.installed().controls[1].content.text == 'x'
    assert field.installed().usage.objects == 1
    assert field.installed().usage.utf8_bytes == 6
    assert field.owner_field('_RTAPT-O.ACTIVE-CONTENT-ITEMS') == 0
    assert field.owner_field('_RTAPT-O.ACTIVE-CONTROL-UTF8') == 6


def test_field_capability_refusal_before_copy_accounting_and_replay(field):
    field.begin()
    record,_=field.control()
    limits=field.call('_RTAPT-E.LIMITS',field.engine)[0][0]
    features=field.runtime.memory.read64(limits)
    before=(field.field('_RTAPT-E.OP-COUNT'),field.field('_RTAPT-E.COPY-USED'),
            field.owner_field('_RTAPT-O.PENDING-CONTROLS'))
    field.runtime.memory.write64(limits,features & ~0x1000)
    assert field.direct(record) == (4,)
    assert (field.field('_RTAPT-E.OP-COUNT'),field.field('_RTAPT-E.COPY-USED'),
            field.owner_field('_RTAPT-O.PENDING-CONTROLS')) == before
    field.runtime.memory.write64(limits,features)
    assert field.direct(record) == (0,)
    copied=field.field('_RTAPT-E.COPY-A')+104
    op=field.field('_RTAPT-E.OPS-A')+40
    field.runtime.memory.write64(limits,features & ~0x1000)
    for name,value in (('_RTAPT-CS-E',field.engine),('_RTAPT-CS-P',op),('_RTAPT-CS-COPY',copied)):
        field.runtime.memory.write64(field.runtime.find(name).body_address,value)
    frames=field.driver.core.frames_received
    assert field.call('_RTAPT-SEND-CONTROL',0)[0] == (4,)
    assert field.driver.core.frames_received == frames
    field.runtime.memory.write64(limits,features)
    assert field.call('RTAPT-RICH-CANCEL',field.engine)[0] == (0,)


def test_field_rejects_declared_quota_forgery_and_bad_owned_content(field):
    field.begin()
    body=content(kind=2,value=1,choices=((1,b'a'),(2,b'b')))
    for items,utf8 in ((1,2),(2,1),(3,2)):
        record,_=field.control(body,items=items,utf8=utf8)
        assert field.define(record) == (5,)
        assert field.direct(record) == (3,)
    record,_=field.control(body,items=2,utf8=2)
    assert field.define(record) == (0,)
    copied=field.field('_RTAPT-E.COPY-A')+104
    size=field.runtime.memory.read64(field.field('_RTAPT-E.OPS-A')+40+16)
    snapshot=field.runtime.memory.read_bytes(copied,size)
    for offset,value in ((160+5+20,1),(160+5+8,0),(160+5+16,2),(160+5+96+12,1)):
        field.runtime.memory.write_bytes(copied,snapshot)
        field.runtime.memory.write64(copied+offset,value)
        assert field.call('_RTAPT-CONTROL-COPY-SHAPE?',copied,size)[0] == (0,)
    field.runtime.memory.write_bytes(copied,snapshot)
    assert field.call('RTAPT-RICH-CANCEL',field.engine)[0] == (0,)


def test_field_hybrid_and_standalone_admission_use_only_certified_aggregates(field):
    body=content(kind=2,value=1,choices=((1,b'a'),(2,b'bb')))
    record,text=field.control(body,items=2,utf8=3)
    plan=field.allocate(struct.pack('<18Q',1,1,20,2,1,0,0,20,2,0,0,0,0,0,1,record,200,0))
    wrapper=[0]*18
    wrapper[0:3]=[1,1,1]
    wrapper[3]=plan
    wrapper[9:11]=[text,5+len(body)]
    hybrid=field.allocate(struct.pack('<18Q',*wrapper))
    admission=field.allocate(b'A'*384)
    assert field.call('RTE-HYBRID-PREFLIGHT',hybrid,admission,field.facade)[0] == (0,)
    summary=list(struct.unpack('<48Q',field.runtime.memory.read_bytes(admission,384)))
    assert summary[15:23] == [1,5+len(body),(5+len(body)+7)&-8,5+len(body),1,0,2,8]
    assert summary[47] == 1
    # Standalone CONTROL preflight preserves its initial-owner-only behavior.
    assert field.call('RTE-CONTROL-PREFLIGHT',plan,field.facade)[0] == (1,)
    source=field.runtime.memory.read_bytes(text,5+len(body))
    field.runtime.memory.write_bytes(text,b'X'*len(source))
    assert field.call('RTAPT-HYBRID-PREFLIGHT',admission,field.engine)[0] == (0,)
    session=field.field('_RTAPT-E.SESSION')
    caps,length=field.call('PT-RETAINED-CAPS@',session)[0]
    assert length == 64
    features=field.runtime.memory.read64(caps+8)
    field.runtime.memory.write64(caps+8,features & ~0x4000)
    assert field.call('RTAPT-HYBRID-PREFLIGHT',admission,field.engine)[0] == (4,)
    field.runtime.memory.write64(caps+8,features)
    for count in (0,2,MASK):
        field.runtime.memory.write64(admission+376,count)
        assert field.call('RTAPT-HYBRID-PREFLIGHT',admission,field.engine)[0] == (3,)
    field.runtime.memory.write_bytes(text,source)


def test_field_malformed_copy_bounds_are_rejected_without_source_walk(field):
    field.begin()
    record,_=field.control()
    assert field.define(record) == (0,)
    copied=field.field('_RTAPT-E.COPY-A')+104
    size=field.runtime.memory.read64(field.field('_RTAPT-E.OPS-A')+40+16)
    assert field.call('_RTAPT-CONTROL-COPY-SHAPE?',0,size)[0] == (0,)
    assert field.call('_RTAPT-CONTROL-COPY-SHAPE?',MASK-7,size)[0] == (0,)
    assert field.call('_RTAPT-CONTROL-COPY-SHAPE?',copied,159)[0] == (0,)
    snapshot=field.runtime.memory.read_bytes(copied,size)
    for offset,value in ((104,1<<32),(120,1<<32),(120,MASK),(128,1<<32),(144,1),(152,1)):
        field.runtime.memory.write_bytes(copied,snapshot)
        field.runtime.memory.write64(copied+offset,value)
        assert field.call('_RTAPT-CONTROL-COPY-SHAPE?',copied,size)[0] == (0,)
    field.runtime.memory.write_bytes(copied,snapshot)
    field.runtime.memory.write_bytes(copied+size-1,b'X')
    assert field.call('_RTAPT-CONTROL-COPY-SHAPE?',copied,size)[0] == (0,)
    field.runtime.memory.write_bytes(copied,snapshot)
    assert field.call('RTAPT-RICH-CANCEL',field.engine)[0] == (0,)


def test_fields_limits_need_controls_and_exact_family_minima(field):
    limits=field.call('RTAPT-LIMITS@',field.engine)[0][0]
    raw=field.runtime.memory.read_bytes(limits,168)
    values=list(struct.unpack('<21Q',raw))
    assert values[0] == 0x1041
    probe=field.allocate(raw)
    for updates,valid in (({0:0x1041,8:376,20:176},True),
                           ({0:0x1001},False),({8:375},False),({20:175},False)):
        changed_values=values.copy()
        for index,value in updates.items():
            changed_values[index]=value
        field.runtime.memory.write_bytes(probe,struct.pack('<21Q',*changed_values))
        for word in ('RTE-LIMITS-VALID?','RTAPT-LIMITS-VALID?'):
            assert field.call(word,probe)[0] == (MASK if valid else 0,)
    assert field.call('_RTAPTE-FEATURES>RTE',0x1041)[0] == (0x1041,)
    assert field.call('_RTAPTE-CONTROL-KIND>RTAPT',13)[0] == (13,)
    assert field.call('_RTAPT-CONTROL-KIND>PT',13)[0] == (13,MASK)
