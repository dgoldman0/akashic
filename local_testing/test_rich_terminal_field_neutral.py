"""Full neutral FIELD descriptor and immutable hybrid graph checks."""
import struct
import pytest
from test_rich_terminal_fdc1 import content
from test_rich_terminal_status_static import StaticHarness, MASK, _offset


class FieldNeutral(StaticHarness):
    def control(self, body=None,label=b'Field',**changes):
        body=content() if body is None else body
        text=self.allocate(label+body)
        values=dict(OWNER=1,GENERATION=2,ID=1,KIND=13,STATE=3,REGION=1,
                    HEIGHT=1,WIDTH=20,**{'ROOT-HEIGHT':24,'ROOT-WIDTH':80,
                    'LABEL-A':text if label else 0,'LABEL-U':len(label),
                    'CONTENT-A':text+len(label),'CONTENT-U':len(body)})
        values.update(changes)
        return self.record('_RTE-CONTROL',200,values),text,len(label)+len(body)

    def field_graph(self,**changes):
        item,text,length=self.control(**changes)
        header=dict(OWNER=1,GENERATION=2,**{'SURFACE-COLS':80,'SURFACE-ROWS':24,
                    'REGION-ID':1,'REGION-COLS':80,'REGION-ROWS':24,
                    'ITEMS-A':item,'ITEMS-U':200})
        plan=self.record('_RTE-CP',144,header)
        hybrid=self.record('_RTE-HP',144,{'ATTEMPT':1,'SOURCE-GENERATION':1,
                   'SURFACE-GENERATION':1,'CONTROL-PLAN':plan,
                   'CONTROL-BYTES-A':text,'CONTROL-BYTES-U':length})
        admission=self.allocate(b'A'*384)
        return item,text,length,plan,hybrid,admission


@pytest.fixture(scope='module',params=('python','native'))
def neutral(request):
    return FieldNeutral(request.param)


@pytest.mark.parametrize('changes', [
    {'PARENT':1},{'PARENT':2},{'ORDER':1},{'STATE':8},{'STATE':4},{'STATE':16},
    {'CONTENT-RUNS':1},{'CONTENT-FIELDS':1},{'CONTENT-ITEMS':1},{'CONTENT-UTF8':1},
    {'HEIGHT':0},{'WIDTH':0},{'CONTENT-A':0},{'CONTENT-U':95},{'CONTENT-U':1<<32},
])
def test_field_descriptor_rejects_invalid_envelope_and_quota_claims(neutral,changes):
    item,_,_=neutral.control(**changes)
    assert neutral.call('RTE-CONTROL-VALID?',item) == (0,)


@pytest.mark.parametrize('body,changes',[
    (content(),{}),
    (content(label=False),{'label':b''}),
    (content(kind=3,text=b'abc'),{'CONTENT-UTF8':3}),
    (content(kind=2,value=-5,choices=((-5,b'A'),(80,b'A'))),{'CONTENT-ITEMS':2,'CONTENT-UTF8':2}),
    (content(flags=1),{'STATE':11}),
])
def test_field_control_is_distinct_from_collection_shapes(neutral,body,changes):
    item,_,_=neutral.control(body,**changes)
    assert neutral.call('RTE-CONTROL-VALID?',item) == (MASK,)


def test_field_hybrid_derives_family_and_text_aggregates_once(neutral):
    body=content(kind=2,value=1,choices=((1,b'a'),(2,b'bb')))
    item,text,length,plan,hybrid,admission=neutral.field_graph(body=body,
                                   **{'CONTENT-ITEMS':2,'CONTENT-UTF8':3})
    assert neutral.call('RTE-HYBRID-PREFLIGHT',hybrid,admission,neutral.facade,
                        readonly=False) == (0,)
    summary=struct.unpack('<48Q',neutral.read(admission,384))
    assert summary[15:23] == (1,length,(length+7)&-8,length,1,0,2,8)
    assert summary[47] == 1
    assert summary[39] == 0
    assert summary[40:47] == (0,)*7
    before=neutral.read(admission,384)
    neutral.cell(item+_offset('_RTE-CONTROL.CONTENT-UTF8'),2)
    assert neutral.call('RTE-HYBRID-PREFLIGHT',hybrid,admission,neutral.facade) == (5,)
    assert neutral.read(admission,384) == before


def test_field_sources_and_output_must_exclude_validator_scratch(neutral):
    item,text,length,plan,hybrid,admission=neutral.field_graph()
    owned=neutral.runtime.find('_FDC1-A').body_address
    before=neutral.read(owned,112)
    assert neutral.call('RTE-CONTROL-VALID?',owned) == (0,)
    neutral.cell(hybrid+_offset('_RTE-HP.CONTROL-BYTES-A'),owned)
    assert neutral.call('RTE-HYBRID-PREFLIGHT',hybrid,admission,neutral.facade) == (5,)
    assert neutral.read(owned,112) == before
    neutral.cell(hybrid+_offset('_RTE-HP.CONTROL-BYTES-A'),text)
    assert neutral.call('RTE-HYBRID-PREFLIGHT',hybrid,owned,neutral.facade) == (5,)
    assert neutral.read(owned,112) == before


@pytest.mark.parametrize('source', ('plan', 'items'))
def test_standalone_control_plan_excludes_fdc1_scratch_before_content_walk(neutral,source):
    item,text,length,plan,hybrid,admission=neutral.field_graph()
    assert neutral.call('RTE-CONTROL-PLAN-VALID?',plan) == (MASK,)
    owned=neutral.runtime.find('_FDC1-A').body_address
    size=144 if source == 'plan' else 200
    saved=neutral.read(owned,size)
    borrowed=neutral.read(plan if source == 'plan' else item,size)
    try:
        # An otherwise valid borrowed record aliases validator scratch. The
        # standalone API has no facade storage callback to reject it for us.
        neutral.write(owned,borrowed)
        if source == 'items':
            neutral.cell(plan+_offset('_RTE-CP.ITEMS-A'),owned)
        assert neutral.call('RTE-CONTROL-PLAN-VALID?',
                            owned if source == 'plan' else plan) == (0,)
        assert neutral.read(owned,size) == borrowed
    finally:
        neutral.write(owned,saved)
