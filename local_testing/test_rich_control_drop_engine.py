"""A DELTA drops controls through the APT-1 engine.

FRAMES-FOLLOW-CHANGE 9c.2a.  RTAPT-CONTROL-DROP captures, in a DELTA, the
drop of a control on screen.  The dropped control's content items and UTF-8
bytes leave the owner's resulting targets, as a replacement stages them, and
its identity leaves the shared object count, so a definition after it may
take its room.  Its ledger entry goes when the terminal accepts the
transaction; a cancel keeps it.  The commit's audit refuses a drop that no
longer matches what the capture staged, and a control left or defined
under a parent the transaction drops.

These tests run the production engine, its PT session and the terminal, on
both executors.
"""
from unittest.mock import patch

import pytest

import test_rich_terminal_cell_feed as cf
from test_rich_terminal_fdc1 import content
from test_rich_terminal_field_engine import FEATURES, FieldProvider
from test_rich_terminal_status_provider import ProviderHarness, RetainedFeature

CHOICES = content(kind=2, value=1, choices=((1, b'one'), (2, b'two')))
TABS = FEATURES | RetainedFeature.CONTROL_COLLECTIONS
LEDGER = 4
TABSET = 7
TAB = 8


class DropProvider(FieldProvider):
    """The owner holds four objects and 128 UTF-8 bytes; the control ledger
    holds four controls."""

    def __init__(self, backend, features=FEATURES):
        original = cf._fixture_source

        def fixture(cols):
            return original(cols).replace(
                b"CREATE CF-LEDGER-MEM RTAPT-CONTROL-LEDGER-SIZE 7 + ALLOT",
                b"CREATE CF-LEDGER-MEM RTAPT-CONTROL-LEDGER-SIZE %d * 7 + ALLOT" % LEDGER,
            ).replace(b"CF-LEDGER RTAPT-CONTROL-LEDGER-SIZE",
                      b"CF-LEDGER RTAPT-CONTROL-LEDGER-SIZE %d *" % LEDGER)

        with patch.object(cf, "_fixture_source", side_effect=fixture):
            ProviderHarness.__init__(self, backend, features=features)

    def fields(self):
        """A START of two fields that fill the owner's objects: field 1 a
        choice of two items with eleven UTF-8 bytes, field 2 a number with
        five."""
        self.begin()
        first, _ = self.control(CHOICES, items=2, utf8=6)
        second, _ = self.control(ID=2, ROW=1)
        assert self.direct(first) == (0,)
        assert self.direct(second) == (0,)
        self.publish()

    def tab(self, identity=2, **changes):
        values = dict(ID=identity, KIND=TAB, STATE=11, PARENT=1, HEIGHT=0, WIDTH=0,
                      **{'CONTENT-A': 0})
        values.update(changes)
        record, _ = self.control(b'', label=b'Tab', **values)
        return record

    def tabs(self):
        """A START of tab set 1 holding tab 2."""
        self.begin()
        tabset, _ = self.control(b'', label=b'', KIND=TABSET, **{'CONTENT-A': 0})
        assert self.direct(tabset) == (0,)
        assert self.direct(self.tab()) == (0,)
        self.publish()

    def drop(self, control, owner=1, generation=1):
        return self.call('RTAPT-CONTROL-DROP', owner, generation, control, self.engine)[0]

    def owner(self, *names):
        return tuple(self.owner_field('_RTAPT-O.' + name) for name in names)

    def capture(self):
        return tuple(self.field('_RTAPT-E.' + name)
                     for name in ('OP-COUNT', 'COPY-USED', 'RET-BYTES'))

    def ledger(self):
        used = self.field('_RTAPT-E.CONTROL-LEDGER-USED')
        return self.runtime.memory.read_bytes(self.field('_RTAPT-E.CONTROL-LEDGER-A'),
                                              self.constant('RTAPT-CONTROL-LEDGER-SIZE') * used)

    def commit(self):
        """Seal and commit the DELTA; the status of its commit."""
        assert self.call('RTAPT-RICH-SEAL', self.constant('PT-COMMIT'), self.engine)[0] == (0,)
        assert self.call('RTAPT-CELL-BEGIN', 20, 2, 0, 0, 0,
                         self.constant('PT-CELL-DELTA'), self.engine)[0] == (0,)
        assert self.call('RTAPT-CELL-CURSOR', 0, 0, 0, self.engine)[0] == (0,)
        return self.call('RTAPT-CELL-COMMIT', self.engine)[0]


@pytest.fixture(params=('python', 'native'))
def drop(request):
    harness = DropProvider(request.param)
    try:
        yield harness
    finally:
        harness.close()


@pytest.fixture(params=('python', 'native'))
def tabs(request):
    harness = DropProvider(request.param, TABS)
    try:
        harness.tabs()
        yield harness
    finally:
        harness.close()


def test_a_delta_drops_a_control_and_gives_back_its_room(drop):
    drop.fields()
    assert sorted(drop.installed().controls) == [1, 2]
    assert drop.installed().usage.objects == 4
    assert drop.owner('ACTIVE-CONTROLS', 'ACTIVE-CONTENT-ITEMS', 'ACTIVE-UTF8') == (2, 2, 16)
    drop.begin('PT-RET-DELTA')
    assert drop.drop(1) == (0,)
    # One 24-byte copy and one 64-byte frame.  The resulting targets lose
    # field 1's two items and eleven bytes.
    assert drop.capture() == (1, 24, 64)
    assert drop.owner('PENDING-CONTROL-DROPS', 'PENDING-CONTENT-TARGET',
                      'PENDING-UTF8-TARGET') == (1, 0, 5)
    drop.publish(reveal=False)
    owner = drop.installed()
    assert sorted(owner.controls) == [2]
    assert (owner.usage.objects, owner.usage.utf8_bytes) == (1, 5)
    assert drop.owner('ACTIVE-CONTROLS', 'ACTIVE-CONTENT-ITEMS', 'ACTIVE-UTF8',
                      'ACTIVE-CONTROL-UTF8', 'CONTROL-HIGH') == (1, 0, 5, 5, 2)
    assert drop.owner('PENDING-CONTROL-DROPS', 'PENDING-CONTENT-TARGET',
                      'PENDING-UTF8-TARGET') == (0, 0, 0)
    assert drop.field('_RTAPT-E.CONTROL-LEDGER-USED') == 1


def test_a_drop_frees_its_room_for_a_definition_after_it(drop):
    drop.fields()
    drop.begin('PT-RET-DELTA')
    third, _ = drop.control(ID=3)
    # The owner's four objects are full until field 1 goes.
    assert drop.direct(third) == (5,)
    assert drop.capture() == (0, 0, 0)
    assert drop.call('RTE-CONTROL-DROP', 1, 1, 1, drop.facade)[0] == (0,)
    assert drop.direct(third) == (0,)
    drop.publish(reveal=False)
    owner = drop.installed()
    assert sorted(owner.controls) == [2, 3]
    assert owner.usage.objects == 2
    assert drop.owner('ACTIVE-CONTROLS', 'CONTROL-HIGH', 'ACTIVE-UTF8') == (2, 3, 10)
    assert drop.field('_RTAPT-E.CONTROL-LEDGER-USED') == 2


def test_a_cancel_keeps_the_control_a_drop_named(drop):
    drop.fields()
    state, ledger = drop.driver.core.retained_state, drop.ledger()
    drop.begin('PT-RET-DELTA')
    assert drop.drop(1) == (0,)
    assert drop.call('RTAPT-RICH-CANCEL', drop.engine)[0] == (0,)
    assert drop.driver.core.retained_state is state
    assert drop.ledger() == ledger
    assert drop.owner('ACTIVE-CONTROLS', 'PENDING-CONTROL-DROPS', 'PENDING-CONTENT-TARGET',
                      'PENDING-UTF8-TARGET') == (2, 0, 0, 0)
    drop.begin('PT-RET-DELTA')
    assert drop.drop(1) == (0,)
    drop.publish(reveal=False)
    assert sorted(drop.installed().controls) == [2]


def test_a_drop_names_a_control_on_screen_that_has_not_changed(drop):
    drop.fields()
    # A START replaces the screen whole, so it has nothing to drop.  Its
    # region takes a fresh identity.
    drop.begin(region=2)
    assert drop.drop(1) == (4,)
    assert drop.call('RTAPT-RICH-CANCEL', drop.engine)[0] == (0,)
    drop.begin('PT-RET-DELTA')
    for owner, generation, control in ((1, 1, 9), (1, 2, 1), (2, 1, 1), (1, 1, 0), (0, 1, 1)):
        assert drop.drop(control, owner, generation) == (3,)
        assert drop.capture() == (0, 0, 0)
        assert drop.owner('PENDING-CONTROL-DROPS') == (0,)
    assert drop.drop(1) == (0,)
    # Each control on screen changes once: no second drop, no replacement of
    # a control dropped, and no drop of one replaced.
    assert drop.drop(1) == (3,)
    first, _ = drop.control(CHOICES, items=2, utf8=6)
    assert drop.direct(first, replace=True) == (3,)
    second, _ = drop.control(content(value=8, revision=8), ID=2, ROW=1)
    assert drop.direct(second, replace=True) == (0,)
    assert drop.drop(2) == (3,)
    assert drop.owner('PENDING-CONTROL-DROPS', 'PENDING-CONTROL-REPLACEMENTS') == (1, 1)
    drop.publish(reveal=False)
    owner = drop.installed()
    assert sorted(owner.controls) == [2]
    assert owner.controls[2].content.value == 8


def test_the_commit_audit_refuses_a_drop_whose_copy_changed(drop):
    drop.fields()
    state, ledger = drop.driver.core.retained_state, drop.ledger()
    drop.begin('PT-RET-DELTA')
    assert drop.drop(1) == (0,)
    # The copy now names field 2, whose bytes the staged targets kept.
    drop.runtime.memory.write64(drop.field('_RTAPT-E.COPY-A') + 16, 2)
    # The refused commit keeps the sealed candidate for its caller to cancel.
    assert drop.commit() == (3,)
    assert drop.call('RTAPT-RICH-CANCEL', drop.engine)[0] == (0,)
    drop.settle()
    assert drop.driver.core.retained_state is state
    assert drop.ledger() == ledger
    assert drop.owner('ACTIVE-CONTROLS', 'PENDING-CONTROL-DROPS') == (2, 0)


def test_a_tab_set_goes_with_its_tab(tabs):
    assert sorted(tabs.installed().controls) == [1, 2]
    tabs.begin('PT-RET-DELTA')
    assert tabs.drop(1) == (0,)
    assert tabs.drop(2) == (0,)
    tabs.publish(reveal=False)
    assert tabs.installed().controls == {}
    assert tabs.owner('ACTIVE-CONTROLS', 'ACTIVE-UTF8') == (0, 0)
    assert tabs.field('_RTAPT-E.CONTROL-LEDGER-USED') == 0


@pytest.mark.parametrize('change', ('define', 'replace'))
def test_a_tab_set_on_screen_takes_a_new_tab_and_a_changed_one(tabs, change):
    # Without a drop, the same definition and replacement commit.
    tabs.begin('PT-RET-DELTA')
    if change == 'define':
        assert tabs.direct(tabs.tab(3, ORDER=1, STATE=3)) == (0,)
    else:
        assert tabs.direct(tabs.tab(STATE=3), replace=True) == (0,)
    tabs.publish(reveal=False)
    assert sorted(tabs.installed().controls) == ([1, 2, 3] if change == 'define' else [1, 2])


@pytest.mark.parametrize('order', ('drop-then-define', 'define-then-drop', 'drop-then-replace'))
def test_the_commit_audit_refuses_a_control_under_a_parent_dropped(tabs, order):
    state, ledger = tabs.driver.core.retained_state, tabs.ledger()
    tabs.begin('PT-RET-DELTA')
    if order == 'define-then-drop':
        assert tabs.direct(tabs.tab(3, ORDER=1, STATE=3)) == (0,)
    assert tabs.drop(1) == (0,)
    if order == 'drop-then-define':
        assert tabs.direct(tabs.tab(3, ORDER=1, STATE=3)) == (0,)
    if order == 'drop-then-replace':
        assert tabs.direct(tabs.tab(STATE=3), replace=True) == (0,)
    assert tabs.commit() == (3,)
    assert tabs.call('RTAPT-RICH-CANCEL', tabs.engine)[0] == (0,)
    tabs.settle()
    assert tabs.driver.core.retained_state is state
    assert tabs.ledger() == ledger
