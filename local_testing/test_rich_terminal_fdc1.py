"""Execute exact production FDC1 validation on both simulator engines."""
from __future__ import annotations
import struct
import pytest
from test_rich_terminal_status_static import (
    ROOT, RICH, MASK, SENTINEL, MegaForthRuntime, _load_exceptions, _clean,
)

HEADER = struct.Struct('<IHHQIIiiIIiiIIqqqqII')


def content(kind=1, *, value=5, minimum=-10, maximum=10, step=3,
            choices=(), text=b'', label=True, **changes):
    fields = dict(tag=0x31434446, version=1, kind=kind, revision=7, flags=0,
                  reserved=0, lx=0, ly=0, lw=5 if label else 0, lh=1 if label else 0,
                  vx=6, vy=0, vw=14, vh=1, value=value, minimum=minimum,
                  maximum=maximum, step=step, count=len(choices), text_bytes=len(text))
    if kind != 1:
        fields.update(minimum=0, maximum=0, step=0)
    if kind == 3:
        fields['value'] = 0
    fields.update(changes)
    body = b''.join(struct.pack('<qII', v, len(label), 0) + label for v, label in choices)
    return HEADER.pack(*fields.values()) + body + text


def changed(payload, offset, fmt, value):
    data = bytearray(payload)
    struct.pack_into(fmt, data, offset, value)
    return bytes(data)


class FdcHarness:
    def __init__(self, backend):
        self.runtime = _load_exceptions(MegaForthRuntime(execution_backend=backend))
        source = [_clean((ROOT/'akashic/utils'/f).read_text())
                  for f in ('uint-range.f', 'memory-span.f')]
        source.append(_clean((RICH/'fdc1.f').read_text()))
        self.runtime.evaluate('\n'.join(source).encode(), source_name='production-fdc1.f')
        self.serial = 0

    def alloc(self, payload):
        self.serial += 1
        return self.runtime.define_created(f'FD-MEM-{self.serial}', initial_body=payload).body_address

    def check(self, payload, label=b'Field', cols=20, rows=1):
        a = self.alloc(payload)
        la = self.alloc(label) if label else 0
        result = self.call(a, len(payload), la, len(label), cols, rows)
        assert self.runtime.memory.read_bytes(a, len(payload)) == payload
        if label:
            assert self.runtime.memory.read_bytes(la, len(label)) == label
        for name in ('_FDC1-A', '_FDC1-OUTER-A', '_FDC1-P', '_FDC1-PREV'):
            assert self.runtime.memory.read64(self.runtime.find(name).body_address) == 0
        return result

    def call(self, *args):
        stack = self.runtime.main_context.data
        assert stack.snapshot() == ()
        for value in (SENTINEL, *args):
            stack.push(value)
        self.runtime.execute('FDC1-VALIDATE', step_budget=1_000_000)
        values = stack.snapshot()
        stack.clear()
        assert values[0] == SENTINEL
        assert self.runtime.main_context.returns.snapshot() == ()
        return values[1:]


@pytest.fixture(scope='module', params=('python', 'native'))
def fdc(request):
    return FdcHarness(request.param)


@pytest.mark.parametrize('payload,label,expected', [
    (content(), b'Field', (0, 0, MASK)),
    (content(value=-(1<<63), minimum=-(1<<63), maximum=(1<<63)-1, step=(1<<63)-1), b'Field', (0,0,MASK)),
    (content(label=False), b'', (0,0,MASK)),
    (content(kind=2, value=-99, choices=((-99,b'same'), (42,b'same'))), b'Field', (2,8,MASK)),
    (content(kind=3,text='État ✓'.encode()), b'Field', (0,9,MASK)),
    (content(kind=3), b'Field', (0,0,MASK)),
])
def test_exact_valid_values(fdc,payload,label,expected):
    assert fdc.check(payload,label) == expected


@pytest.mark.parametrize('changes', [
    {'tag':0}, {'version':2}, {'kind':0}, {'kind':4}, {'revision':0},
    {'flags':2}, {'reserved':1}, {'lx':-1}, {'lw':0}, {'lh':0},
    {'vx':-1}, {'vy':-1}, {'vw':0}, {'vh':0}, {'vw':15}, {'vh':2},
    {'vx':4}, {'value':11}, {'minimum':6}, {'maximum':4}, {'step':0}, {'step':-1},
    {'count':1}, {'text_bytes':1},
])
def test_noncanonical_header(fdc,changes):
    assert fdc.check(content(**changes)) == (0,0,0)


@pytest.mark.parametrize('payload', [
    content()[:-1], content()+b'\0',
    content(kind=2,choices=()),
    content(kind=2,value=1,choices=((1,b''),)),
    content(kind=2,value=1,choices=((1,b'A'),(1,b'B'))),
    content(kind=2,value=1,choices=((2,b'A'),)),
    changed(content(kind=2,value=1,choices=((1,b'A'),)),64,'<q',1),
    content(kind=2,value=1,choices=((1,b'A'),),text_bytes=1),
    changed(content(kind=3),56,'<q',1), content(kind=3,count=1), changed(content(kind=3),80,'<q',1),
    content(kind=3,text=b'A',text_bytes=0), content(kind=3,text=b'A',text_bytes=2),
])
def test_noncanonical_exact_tail(fdc,payload):
    assert fdc.check(payload) == (0,0,0)


@pytest.mark.parametrize('bad', [b'\0',b'\x01',b'\x7f',b'\xc2\x80',b'\xc2\x9f',b'\xe2\x80\xa8',b'\xe2\x80\xa9',b'\xc0\x80',b'\xed\xa0\x80',b'\xf4\x90\x80\x80',b'\xe2\x82'])
def test_every_text_span_is_clean_scalar_utf8(fdc,bad):
    assert fdc.check(content(),bad) == (0,0,0)
    assert fdc.check(content(kind=3,text=bad)) == (0,0,0)
    assert fdc.check(content(kind=2,value=1,choices=((1,bad),))) == (0,0,0)


def test_fixed_authority_precedes_scratch_and_source_reads(fdc):
    assert fdc.call(0,96,0,0,20,1) == (0,0,0)
    assert fdc.call(MASK-10,96,0,0,20,1) == (0,0,0)
    assert fdc.call(0,0,0,0,20,1) == (0,0,0)
    a=fdc.alloc(content())
    assert fdc.call(a,96,a,1,20,1) == (0,0,0)
    owned=fdc.runtime.find('_FDC1-A').body_address
    before=fdc.runtime.memory.read_bytes(owned,16)
    assert fdc.call(owned,96,0,0,20,1) == (0,0,0)
    assert fdc.call(a,96,owned,1,20,1) == (0,0,0)
    assert fdc.runtime.memory.read_bytes(owned,16) == before
