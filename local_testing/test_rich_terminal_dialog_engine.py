"""Production neutral, provider and wire DIALOG and BUTTON routes on both
engines (APT-1-RETAINED-1 sections 9.3 and 9.4)."""
import struct
from unittest.mock import patch
import pytest
from test_rich_terminal_dlg1 import button, dialog
from test_rich_terminal_status_provider import ProviderHarness, RetainedFeature
from test_rich_terminal_status_static import MASK, _offset
import test_rich_terminal_cell_feed as cf

FEATURES = RetainedFeature.CORE | RetainedFeature.CONTROLS | RetainedFeature.DIALOGS
DIALOG, BUTTON = 15, 16
MESSAGE = b'Remove notes?'


def body(message=MESSAGE, **changes):
    """A 20 by 2 dialog: its title and message share the first row, apart,
    and its buttons sit on the second."""
    rect = dict(tx=0, ty=0, tw=6, th=1, mx=7, my=0, mw=13, mh=1)
    rect.update(changes)
    return dialog(message=message, **rect)


class DialogProvider(ProviderHarness):
    def __init__(self, backend):
        # Dialogs and buttons may be replaced in a DELTA, so each takes a
        # control ledger entry.
        original = cf._fixture_source

        def fixture(cols):
            return original(cols).replace(
                b"CREATE CF-LEDGER-MEM RTAPT-CONTROL-LEDGER-SIZE 7 + ALLOT",
                b"CREATE CF-LEDGER-MEM RTAPT-CONTROL-LEDGER-SIZE 4 * 7 + ALLOT",
            ).replace(b"CF-LEDGER RTAPT-CONTROL-LEDGER-SIZE\n",
                      b"CF-LEDGER RTAPT-CONTROL-LEDGER-SIZE 4 *\n")
        with patch.object(cf, "_fixture_source", side_effect=fixture):
            super().__init__(backend, features=FEATURES)

    def control(self, kind=DIALOG, payload=None, label=b'Delete', *, utf8=None,
                shortcut=b'', **changes):
        if payload is None:
            payload = body() if kind == DIALOG else button()
        if utf8 is None:
            utf8 = len(payload) - 56 if kind == DIALOG else 0
        text = self.allocate(label + shortcut + payload)
        values = dict(OWNER=1, GENERATION=1, ID=1, KIND=kind,
                      STATE=1 if kind == DIALOG else 3, Z=0 if kind == DIALOG else 1,
                      REGION=1, PARENT=0, ORDER=0, ROW=0, COL=0, HEIGHT=2, WIDTH=20,
                      **{'ROOT-HEIGHT':2, 'ROOT-WIDTH':20,
                         'LABEL-A':text if label else 0, 'LABEL-U':len(label),
                         'SHORTCUT-A':text+len(label) if shortcut else 0,
                         'SHORTCUT-U':len(shortcut),
                         'CONTENT-A':text+len(label)+len(shortcut), 'CONTENT-U':len(payload),
                         'CONTENT-ITEMS':0, 'CONTENT-UTF8':utf8,
                         'CONTENT-RUNS':0, 'CONTENT-FIELDS':0})
        values.update(changes)
        data = bytearray(200)
        for name, value in values.items():
            struct.pack_into('<Q', data, _offset('_RTE-CONTROL.'+name), value & MASK)
        return self.allocate(data), text

    def buttons(self, delete=b'Delete', delete_state=3, cancel_state=11):
        first, _ = self.control(BUTTON, button(4), delete, ID=2, STATE=delete_state,
                                ROW=1, COL=1, HEIGHT=1, WIDTH=8)
        second, _ = self.control(BUTTON, button(3), b'Cancel', ID=3, STATE=cancel_state,
                                 ROW=1, COL=11, HEIGHT=1, WIDTH=8)
        return first, second

    def define(self, record, replace=False):
        return self.call('RTE-CONTROL-REPLACE' if replace else 'RTE-CONTROL-DEFINE',
                         record, self.facade)[0]

    def direct(self, record, replace=False):
        values = struct.unpack('<25Q', self.runtime.memory.read_bytes(record, 200))
        return self.call('RTAPT-CONTROL-REPLACE' if replace else 'RTAPT-CONTROL-DEFINE',
                         *values, self.engine)[0]

    def ask(self):
        """Publish the dialog and its two buttons."""
        self.begin()
        record, text = self.control()
        for item in (record, *self.buttons()):
            assert self.define(item) == (0,)
        return text


@pytest.fixture(params=('python', 'native'))
def dlg(request):
    harness = DialogProvider(request.param)
    try:
        yield harness
    finally:
        harness.close()


def test_dialog_and_buttons_publish_exact_owned_content(dlg):
    text = dlg.ask()
    assert dlg.field('_RTAPT-E.OP-COUNT') == 4
    # Each copy is 160 bytes and its text, aligned: the dialog's title and
    # DLG1 (6 + 56 + 13), then each button's label and BTN1 (6 + 8).
    assert dlg.field('_RTAPT-E.COPY-USED') == 104 + 3*160 + 80 + 16 + 16
    dlg.runtime.memory.write_bytes(text, b'X'*(6+len(body())))
    dlg.publish()
    owner = dlg.installed()
    box, delete, cancel = (owner.controls[i] for i in (1, 2, 3))
    assert (box.kind.value, box.label, box.content.lines) == (DIALOG, 'Delete', ('Remove notes?',))
    assert (box.content.severity, box.content.content_revision, box.content.notice) == (3, 7, False)
    assert (delete.kind.value, delete.label, delete.content.destructive) == (BUTTON, 'Delete', True)
    assert (cancel.label, cancel.content.default, cancel.content.cancel) == ('Cancel', True, True)
    assert owner.usage.objects == 3
    assert owner.usage.utf8_bytes == 6 + len(MESSAGE) + 6 + 6
    assert dlg.owner_field('_RTAPT-O.ACTIVE-CONTROLS') == 3
    assert dlg.owner_field('_RTAPT-O.ACTIVE-CONTROL-UTF8') == 6 + len(MESSAGE) + 12


def test_dialog_replaces_newer_content_and_buttons_their_labels_and_states(dlg):
    dlg.ask()
    dlg.publish()
    dlg.begin('PT-RET-DELTA')
    record, _ = dlg.control(payload=body(b'Erase notes?', revision=8))
    assert dlg.define(record, replace=True) == (0,)
    for item in dlg.buttons(b'Erase', delete_state=11, cancel_state=3):
        assert dlg.define(item, replace=True) == (0,)
    dlg.publish(reveal=False)
    owner = dlg.installed()
    assert owner.controls[1].content.lines == ('Erase notes?',)
    assert owner.controls[1].content.content_revision == 8
    assert (owner.controls[2].label, owner.controls[2].state.value) == ('Erase', 11)
    assert owner.controls[3].state.value == 3
    assert owner.usage.utf8_bytes == 6 + 12 + 5 + 6
    assert dlg.owner_field('_RTAPT-O.ACTIVE-CONTROL-UTF8') == 6 + 12 + 5 + 6


def test_dialogs_and_buttons_need_negotiated_dialogs(dlg):
    dlg.begin()
    limits = dlg.call('_RTAPT-E.LIMITS', dlg.engine)[0][0]
    features = dlg.runtime.memory.read64(limits)
    for record in (dlg.control()[0], dlg.buttons()[0]):
        before = (dlg.field('_RTAPT-E.OP-COUNT'), dlg.field('_RTAPT-E.COPY-USED'),
                  dlg.owner_field('_RTAPT-O.PENDING-CONTROLS'))
        dlg.runtime.memory.write64(limits, features & ~0x8000)
        assert dlg.direct(record) == (dlg.constant('RTAPT-S-UNSUPPORTED'),)
        assert (dlg.field('_RTAPT-E.OP-COUNT'), dlg.field('_RTAPT-E.COPY-USED'),
                dlg.owner_field('_RTAPT-O.PENDING-CONTROLS')) == before
        dlg.runtime.memory.write64(limits, features)
        assert dlg.direct(record) == (0,)
    # The send path checks the feature again, and sends nothing without it.
    copied = dlg.field('_RTAPT-E.COPY-A') + 104
    op = dlg.field('_RTAPT-E.OPS-A') + 40
    dlg.runtime.memory.write64(limits, features & ~0x8000)
    for name, value in (('_RTAPT-CS-E', dlg.engine), ('_RTAPT-CS-P', op),
                        ('_RTAPT-CS-COPY', copied)):
        dlg.runtime.memory.write64(dlg.runtime.find(name).body_address, value)
    frames = dlg.driver.core.frames_received
    assert dlg.call('_RTAPT-SEND-CONTROL', 0)[0] == (dlg.constant('RTAPT-S-UNSUPPORTED'),)
    assert dlg.driver.core.frames_received == frames
    dlg.runtime.memory.write64(limits, features)
    assert dlg.call('RTAPT-RICH-CANCEL', dlg.engine)[0] == (0,)


INVALID = {
    'dialog-enabled': (DIALOG, {}, dict(STATE=3)),
    'dialog-parent': (DIALOG, {}, dict(PARENT=1)),
    'dialog-shortcut': (DIALOG, dict(shortcut=b'D'), {}),
    'dialog-items': (DIALOG, {}, {'CONTENT-ITEMS': 1}),
    'dialog-utf8': (DIALOG, dict(utf8=len(MESSAGE)+1), {}),
    'dialog-revision': (DIALOG, dict(payload=body(revision=0)), {}),
    'dialog-severity': (DIALOG, dict(payload=body(severity=5)), {}),
    'dialog-untitled-slot': (DIALOG, dict(label=b''), {}),
    'dialog-title-outside': (DIALOG, dict(payload=body(tw=21)), {}),
    'dialog-overlap': (DIALOG, dict(payload=body(tw=8)), {}),
    'dialog-lines': (DIALOG, dict(payload=body(b'Remove\nnotes?')), {}),
    'dialog-control-text': (DIALOG, dict(payload=body(b'Remove\tnotes')), {}),
    'dialog-button-content': (DIALOG, dict(payload=button(), utf8=0), {}),
    'button-unlabelled': (BUTTON, dict(label=b''), {}),
    'button-open': (BUTTON, {}, dict(STATE=7)),
    'button-parent': (BUTTON, {}, dict(PARENT=1)),
    'button-utf8': (BUTTON, dict(utf8=1), {}),
    'button-destructive-default': (BUTTON, dict(payload=button(5)), {}),
    'button-reserved-flag': (BUTTON, dict(payload=button(8)), {}),
    'button-long': (BUTTON, dict(payload=button()+b'\0'), {}),
    'button-dialog-content': (BUTTON, dict(payload=body()), {}),
    'button-control-label': (BUTTON, dict(label=b'De\x07lete'), {}),
}


@pytest.mark.parametrize('case', tuple(INVALID))
def test_malformed_dialogs_and_buttons_are_refused_on_both_paths(dlg, case):
    kind, arguments, changes = INVALID[case]
    dlg.begin()
    record, _ = dlg.control(kind, **arguments, **changes)
    before = (dlg.field('_RTAPT-E.OP-COUNT'), dlg.field('_RTAPT-E.COPY-USED'))
    assert dlg.define(record) == (dlg.constant('RTE-S-INVALID'),)
    assert dlg.direct(record) == (dlg.constant('RTAPT-S-INVALID'),)
    assert (dlg.field('_RTAPT-E.OP-COUNT'), dlg.field('_RTAPT-E.COPY-USED')) == before


def test_owned_dialog_and_button_copies_are_checked_again(dlg):
    dlg.ask()
    first = dlg.field('_RTAPT-E.COPY-A') + 104
    ops = dlg.field('_RTAPT-E.OPS-A')
    # The dialog's copy: its text holds the six-byte title, then DLG1.
    size = dlg.runtime.memory.read64(ops + 40 + 16)
    snapshot = dlg.runtime.memory.read_bytes(first, size)
    content = first + 160 + 6
    for offset, value in ((0, b'XLG1'), (8, bytes(8)), (16, b'\5'), (20, b'\14'),
                          (32, b'\25'), (56, b'\t'), (-6, b'\a')):
        dlg.runtime.memory.write_bytes(first, snapshot)
        dlg.runtime.memory.write_bytes(content + offset, value)
        assert dlg.call('_RTAPT-CONTROL-COPY-SHAPE?', first, size)[0] == (0,), offset
    for field, value in ((32, 3), (112, 1), (128, 1)):
        dlg.runtime.memory.write_bytes(first, snapshot)
        dlg.runtime.memory.write64(first + field, value)
        assert dlg.call('_RTAPT-CONTROL-COPY-SHAPE?', first, size)[0] == (0,), field
    dlg.runtime.memory.write_bytes(first, snapshot)
    assert dlg.call('_RTAPT-CONTROL-COPY-SHAPE?', first, size)[0] == (MASK,)
    # The first button's copy follows, with its label and BTN1.
    second = first + size
    size = dlg.runtime.memory.read64(ops + 80 + 16)
    snapshot = dlg.runtime.memory.read_bytes(second, size)
    for offset, value in ((166, b'\5'), (166, b'\x08'), (160, b'\a')):
        dlg.runtime.memory.write_bytes(second, snapshot)
        dlg.runtime.memory.write_bytes(second + offset, value)
        assert dlg.call('_RTAPT-CONTROL-COPY-SHAPE?', second, size)[0] == (0,), offset
    dlg.runtime.memory.write_bytes(second, snapshot)
    dlg.runtime.memory.write64(second + 104, 0)
    assert dlg.call('_RTAPT-CONTROL-COPY-SHAPE?', second, size)[0] == (0,)
    dlg.runtime.memory.write_bytes(second, snapshot)
    assert dlg.call('_RTAPT-CONTROL-COPY-SHAPE?', second, size)[0] == (MASK,)
    assert dlg.call('RTAPT-RICH-CANCEL', dlg.engine)[0] == (0,)


def test_dialog_kinds_map_through_the_bridge_and_to_the_wire(dlg):
    for kind in (DIALOG, BUTTON):
        assert dlg.call('_RTAPTE-CONTROL-KIND>RTAPT', kind)[0] == (kind,)
        assert dlg.call('_RTAPT-CONTROL-KIND>PT', kind)[0] == (kind, MASK)
