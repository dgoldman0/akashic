"""Execute exact production DLG1 and BTN1 validation on both simulator
engines (APT-1-RETAINED-1 sections 9.3 and 9.4)."""
from __future__ import annotations
import struct
import pytest
from test_rich_terminal_status_static import (
    ROOT, RICH, MASK, SENTINEL, MegaForthRuntime, _load_exceptions, _clean,
)

HEADER = struct.Struct('<IHHQIIiiIIiiII')
MESSAGE = 'Delete notes.md?\nIt cannot be undone.'.encode()


def dialog(*, message=MESSAGE, title=True, **changes):
    fields = dict(tag=0x31474C44, version=1, flags=0, revision=7, severity=3,
                  message_bytes=len(message),
                  tx=1, ty=0, tw=18 if title else 0, th=1 if title else 0,
                  mx=1, my=1, mw=18 if message else 0, mh=2 if message else 0)
    if not message:
        fields.update(mx=0, my=0)
    if not title:
        fields.update(tx=0)
    fields.update(changes)
    return HEADER.pack(*fields.values()) + message


def button(flags=0, *, tag=0x314E5442, version=1):
    return struct.pack('<IHH', tag, version, flags)


class DlgHarness:
    def __init__(self, backend):
        self.runtime = _load_exceptions(MegaForthRuntime(execution_backend=backend))
        source = [_clean((ROOT/'akashic/utils'/f).read_text())
                  for f in ('uint-range.f', 'memory-span.f')]
        source += [_clean((RICH/f).read_text()) for f in ('fdc1.f', 'dlg1.f')]
        self.runtime.evaluate('\n'.join(source).encode(), source_name='production-dlg1.f')
        self.serial = 0

    def alloc(self, payload):
        self.serial += 1
        return self.runtime.define_created(f'DL-MEM-{self.serial}', initial_body=payload).body_address

    def call(self, word, *args):
        stack = self.runtime.main_context.data
        assert stack.snapshot() == ()
        for value in (SENTINEL, *args):
            stack.push(value)
        self.runtime.execute(word, step_budget=1_000_000)
        values = stack.snapshot()
        stack.clear()
        assert values[0] == SENTINEL
        assert self.runtime.main_context.returns.snapshot() == ()
        return values[1:]

    def check(self, payload, title=b'Delete', cols=20, rows=5):
        a = self.alloc(payload)
        ta = self.alloc(title) if title else 0
        result = self.call('DLG1-VALIDATE', a, len(payload), ta, len(title), cols, rows)
        assert self.runtime.memory.read_bytes(a, len(payload)) == payload
        for name in ('_DLG1-A', '_DLG1-TITLE-A', '_DLG1-P', '_DLG1-LINE', '_DLG1-LINES'):
            assert self.runtime.memory.read64(self.runtime.find(name).body_address) == 0
        return result

    def button(self, payload):
        a = self.alloc(payload)
        return self.call('BTN1-VALIDATE', a, len(payload))


@pytest.fixture(scope='module', params=('python', 'native'))
def dlg(request):
    return DlgHarness(request.param)


@pytest.mark.parametrize('payload,title,expected', [
    (dialog(), b'Delete', (len(MESSAGE), MASK)),
    (dialog(title=False), b'', (len(MESSAGE), MASK)),
    (dialog(message=b''), b'Delete', (0, MASK)),
    (dialog(message=b'', title=False), b'', (0, MASK)),
    # A notice, an empty line between two others, and every severity.
    (dialog(flags=1, severity=4, message=b'Could not save', mh=1, title=False), b'', (14, MASK)),
    (dialog(message=b'a\n\nb', mh=3), b'Delete', (4, MASK)),
    (dialog(message=b'a\n', mh=2), b'Delete', (2, MASK)),
    (dialog(severity=0), b'Delete', (len(MESSAGE), MASK)),
])
def test_exact_valid_dialogs(dlg, payload, title, expected):
    assert dlg.check(payload, title) == expected


@pytest.mark.parametrize('payload,title', [
    (dialog(tag=0), b'Delete'), (dialog(version=2), b'Delete'),
    (dialog(flags=2), b'Delete'), (dialog(revision=0), b'Delete'),
    (dialog(severity=5), b'Delete'),
    (dialog(message_bytes=len(MESSAGE) - 1), b'Delete'),
    (dialog()[:-1], b'Delete'), (dialog() + b'x', b'Delete'),
    (dialog()[:55], b'Delete'),
    (dialog(), b''),                     # a title slot with no title
    (dialog(title=False), b'Delete'),    # a title with no slot
    (dialog(tw=20), b'Delete'),          # past the root's 20 columns
    (dialog(tx=-1), b'Delete'),
    (dialog(th=0), b'Delete'),
    (dialog(my=0), b'Delete'),           # the message slot over the title
    (dialog(mh=1), b'Delete'),           # two lines in one row
    (dialog(mh=0, mw=0, mx=0, my=0), b'Delete'),  # a message without its slot
    (dialog(message=b'', mx=1, my=1, mw=18, mh=1), b'Delete'),  # a slot, no message
    (dialog(my=4, mh=2), b'Delete'),     # past the root's 5 rows
])
def test_noncanonical_dialogs(dlg, payload, title):
    assert dlg.check(payload, title) == (0, 0)


@pytest.mark.parametrize('bad', [b'\t', b'\r', b'\0', b'\x7f', b'\xc2\x85', b'\xe2\x80\xa8',
                                 b'\xe2\x80\xa9', b'\xff', b'\xed\xa0\x80', b'\xe2\x82'])
def test_message_lines_and_title_are_clean_text(dlg, bad):
    message = b'one' + bad + b'\nb'
    assert dlg.check(dialog(message=message), b'Delete') == (0, 0)
    assert dlg.check(dialog(), b'Del' + bad) == (0, 0)


def test_authority_precedes_scratch_and_source_reads(dlg):
    assert dlg.call('DLG1-VALIDATE', 0, 56, 0, 0, 20, 5) == (0, 0)
    assert dlg.call('DLG1-VALIDATE', MASK - 10, 56, 0, 0, 20, 5) == (0, 0)
    a = dlg.alloc(dialog())
    assert dlg.call('DLG1-VALIDATE', a, len(dialog()), a, 1, 20, 5) == (0, 0)
    owned = dlg.runtime.find('_DLG1-A').body_address
    before = dlg.runtime.memory.read_bytes(owned, 16)
    assert dlg.call('DLG1-VALIDATE', owned, 56, 0, 0, 20, 5) == (0, 0)
    assert dlg.runtime.memory.read_bytes(owned, 16) == before
    assert dlg.call('DLG1-VALIDATE', a, len(dialog()), 0, 0, 0, 5) == (0, 0)
    assert dlg.call('DLG1-VALIDATE', a, len(dialog()), 0, 0, 20, 0) == (0, 0)


@pytest.mark.parametrize('flags,valid', [
    (0, True), (1, True), (2, True), (3, True), (4, True), (6, True),
    (5, False), (7, False), (8, False),
])
def test_button_flags(dlg, flags, valid):
    assert dlg.button(button(flags)) == ((MASK,) if valid else (0,))


def test_button_body_is_exact(dlg):
    for payload in (button()[:-1], button() + b'\0', button(tag=0), button(version=2)):
        assert dlg.button(payload) == (0,)
    assert dlg.call('BTN1-VALIDATE', 0, 8) == (0,)
