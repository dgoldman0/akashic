"""Production neutral taskbar leaf and canonical parent/slot plan validation."""
import struct
import pytest
from test_rich_terminal_status_static import StaticHarness, MASK, _offset


class TaskbarNeutral(StaticHarness):
    def control(self, kind=10, label=None, **changes):
        label = (b'' if kind == 10 else b'Task') if label is None else label
        text = self.allocate(label) if label else 0
        values = dict(OWNER=1, GENERATION=2, ID=1 if kind == 10 else 2,
                      KIND=kind, STATE=3, REGION=1, PARENT=0 if kind == 10 else 1,
                      HEIGHT=1, WIDTH=30 if kind == 10 else 6,
                      **{'ROOT-HEIGHT':24, 'ROOT-WIDTH':80,
                         'LABEL-A':text, 'LABEL-U':len(label)})
        values.update(changes)
        return self.record('_RTE-CONTROL', 200, values)

    def graph(self):
        root = self.control()
        task = self.control(11, ID=2, ORDER=0, COL=0, STATE=11)
        launcher = self.control(12, ID=3, ORDER=1, COL=10)
        items = self.allocate(self.read(root,200)+self.read(task,200)+self.read(launcher,200))
        plan = self.record('_RTE-CP',144, dict(OWNER=1,GENERATION=2,
                    **{'SURFACE-COLS':80,'SURFACE-ROWS':24, 'REGION-ID':1,
                       'REGION-COLS':80,'REGION-ROWS':24,'ITEMS-A':items,'ITEMS-U':600}))
        return plan, items


@pytest.fixture(scope='module', params=('python','native'))
def neutral(request):
    return TaskbarNeutral(request.param)


@pytest.mark.parametrize('kind,state', [(10,0),(10,3),(11,0),(11,3),(11,11),(11,32),(11,35),(12,0),(12,3)])
def test_taskbar_leaf_valid_states(neutral,kind,state):
    assert neutral.call('RTE-CONTROL-VALID?',neutral.control(kind,STATE=state)) == (MASK,)


@pytest.mark.parametrize('kind,changes', [
    (10,{'PARENT':2}), (10,{'ORDER':1}), (10,{'HEIGHT':2}), (10,{'STATE':11}),
    (10,{'label':b'bar'}), (11,{'PARENT':0}), (11,{'Z':1}), (11,{'ROW':1}),
    (11,{'HEIGHT':2}), (11,{'WIDTH':0}), (11,{'STATE':43}), (11,{'STATE':4}),
    (11,{'STATE':16}), (11,{'label':b''}), (11,{'CONTENT-U':1}),
    (12,{'STATE':11}), (12,{'STATE':35}), (1,{'STATE':32}), (2,{'STATE':35}),
    (11,{'label':b'a\nb'}), (11,{'label':b'a\x7fb'}), (11,{'label':'a\u2028b'.encode()}),
])
def test_taskbar_leaf_rejects_wrong_kind_state_geometry_and_text(neutral,kind,changes):
    assert neutral.call('RTE-CONTROL-VALID?',neutral.control(kind,**changes)) == (0,)


def test_taskbar_plan_retains_authored_order_independent_of_slot_order(neutral):
    plan,items=neutral.graph()
    assert neutral.call('RTE-CONTROL-PLAN-VALID?',plan) == (MASK,)
    neutral.cell(items+200+_offset('_RTE-CONTROL.COL'),20)
    assert neutral.call('RTE-CONTROL-PLAN-VALID?',plan) == (MASK,)


@pytest.mark.parametrize('index,key,value', [
    (1,'PARENT',99),(1,'REGION',2),(1,'ROOT-WIDTH',70),(1,'COL',28),
    (2,'COL',5),(2,'ORDER',0),(2,'ORDER',(1<<32)),(2,'ID',4),
    (2,'PARENT',2),(2,'STATE',11),
])
def test_taskbar_plan_rejects_invalid_parent_slots_order_and_states(neutral,index,key,value):
    plan,items=neutral.graph()
    neutral.cell(items+index*200+_offset('_RTE-CONTROL.'+key),value)
    assert neutral.call('RTE-CONTROL-PLAN-VALID?',plan) == (0,)


def test_hidden_task_still_occupies_slot_and_selection_is_unique(neutral):
    plan,items=neutral.graph()
    neutral.cell(items+400+_offset('_RTE-CONTROL.KIND'),11)
    neutral.cell(items+400+_offset('_RTE-CONTROL.STATE'),11)
    assert neutral.call('RTE-CONTROL-PLAN-VALID?',plan) == (0,)
    neutral.cell(items+400+_offset('_RTE-CONTROL.STATE'),0)
    assert neutral.call('RTE-CONTROL-PLAN-VALID?',plan) == (MASK,)
    neutral.cell(items+400+_offset('_RTE-CONTROL.COL'),5)
    assert neutral.call('RTE-CONTROL-PLAN-VALID?',plan) == (0,)
