"""A DELTA defines and drops regions through the APT-1 engine.

FRAMES-FOLLOW-CHANGE 9c.2b.  A DELTA may define a region and the controls
in it, and drop a region on screen after the controls in it.  The engine
keeps no ledger of regions: it counts them, so a drop names a region the
terminal acknowledged, once, and its room is free for a region defined
after it.  A dropped region's identity stays used.  The commit's audit
refuses a drop of a region the transaction writes into, and a write into a
region it dropped before.

These tests run the production engine, its PT session and the terminal, on
both executors.  The owner holds two regions and four objects.
"""
import pytest

from test_rich_control_drop_engine import DropProvider
from test_rich_terminal_fdc1 import content


class RegionProvider(DropProvider):
    def region(self, identity, z=1):
        return self.call('RTAPT-REGION-DEFINE', 1, 1, identity, 0, 0, 20, 2,
                         0, 0, 0, 0, z, 1, self.engine)[0]

    def drop_region(self, region, owner=1, generation=1):
        return self.call('RTAPT-REGION-DROP', owner, generation, region, self.engine)[0]

    def one_field(self):
        """A START of field 1 in region 1."""
        self.begin()
        record, _ = self.control()
        assert self.direct(record) == (0,)
        self.publish()

    def overlay(self):
        """A DELTA that defines region 2 over region 1, with field 2 in it."""
        self.begin('PT-RET-DELTA')
        assert self.region(2) == (0,)
        record, _ = self.control(ID=2, REGION=2)
        assert self.direct(record) == (0,)
        self.publish(reveal=False)

    def regions(self):
        return sorted(self.installed().regions)


@pytest.fixture(params=('python', 'native'))
def regions(request):
    harness = RegionProvider(request.param)
    try:
        harness.one_field()
        yield harness
    finally:
        harness.close()


def test_a_delta_defines_a_region_and_the_control_in_it(regions):
    h = regions
    h.overlay()
    assert h.regions() == [1, 2]
    assert h.installed().controls[2].region_id == 2
    assert h.owner('ACTIVE-REGIONS', 'REGION-HIGH', 'ACTIVE-CONTROLS') == (2, 2, 2)


def test_a_control_goes_only_into_a_region_on_screen_or_one_defined_before_it(regions):
    h = regions
    h.begin('PT-RET-DELTA')
    record, _ = h.control(ID=2, REGION=2)
    assert h.direct(record) == (3,)
    assert h.capture() == (0, 0, 0)
    assert h.call('RTAPT-RICH-CANCEL', h.engine)[0] == (0,)


def test_a_delta_drops_a_region_after_the_controls_in_it(regions):
    h = regions
    h.overlay()
    h.begin('PT-RET-DELTA')
    assert h.drop(2) == (0,)
    assert h.call('RTE-REGION-DROP', 1, 1, 2, h.facade)[0] == (0,)
    # Two 24-byte copies and two 64-byte frames.
    assert h.capture() == (2, 48, 128)
    assert h.owner('PENDING-REGION-DROPS') == (1,)
    h.publish(reveal=False)
    assert h.regions() == [1]
    assert sorted(h.installed().controls) == [1]
    # The region's identity stays used.
    assert h.owner('ACTIVE-REGIONS', 'REGION-HIGH', 'PENDING-REGION-DROPS') == (1, 2, 0)
    h.begin('PT-RET-DELTA')
    assert h.region(2) == (3,)
    assert h.region(3) == (0,)
    h.publish(reveal=False)
    assert h.regions() == [1, 3]


def test_a_region_drop_frees_its_room_for_a_region_after_it(regions):
    h = regions
    h.overlay()
    h.begin('PT-RET-DELTA')
    # The owner's two regions are both on screen.
    assert h.region(3) == (5,)
    assert h.drop(2) == (0,)
    assert h.drop_region(2) == (0,)
    assert h.region(3) == (0,)
    record, _ = h.control(ID=3, REGION=3)
    assert h.direct(record) == (0,)
    h.publish(reveal=False)
    assert h.regions() == [1, 3]
    assert sorted(h.installed().controls) == [1, 3]
    assert h.owner('ACTIVE-REGIONS', 'REGION-HIGH') == (2, 3)


def test_a_cancel_keeps_the_region_a_drop_named(regions):
    h = regions
    h.overlay()
    state = h.driver.core.retained_state
    h.begin('PT-RET-DELTA')
    assert h.drop(2) == (0,)
    assert h.drop_region(2) == (0,)
    assert h.call('RTAPT-RICH-CANCEL', h.engine)[0] == (0,)
    assert h.driver.core.retained_state is state
    assert h.owner('ACTIVE-REGIONS', 'PENDING-REGION-DROPS') == (2, 0)


def test_a_region_drop_names_a_region_on_screen_once(regions):
    h = regions
    h.overlay()
    # A START replaces the screen whole, so it has nothing to drop.
    h.begin(region=3)
    assert h.drop_region(2) == (4,)
    assert h.call('RTAPT-RICH-CANCEL', h.engine)[0] == (0,)
    h.begin('PT-RET-DELTA')
    for owner, generation, region in ((1, 1, 9), (1, 2, 2), (2, 1, 2), (1, 1, 0), (0, 1, 2)):
        assert h.drop_region(region, owner, generation) == (3,)
        assert h.capture() == (0, 0, 0)
    assert h.drop(2) == (0,)
    assert h.drop_region(2) == (0,)
    assert h.drop_region(2) == (3,)
    # A region the capture defines is not on screen to drop.
    assert h.region(3) == (0,)
    assert h.drop_region(3) == (3,)
    assert h.owner('PENDING-REGION-DROPS') == (1,)
    assert h.call('RTAPT-RICH-CANCEL', h.engine)[0] == (0,)


@pytest.mark.parametrize('change', ('define', 'replace'))
def test_a_region_on_screen_takes_a_new_control_and_a_changed_one(regions, change):
    # Without the region's drop, the same definition and replacement commit.
    h = regions
    h.overlay()
    h.begin('PT-RET-DELTA')
    if change == 'define':
        record, _ = h.control(ID=3, REGION=2)
        assert h.direct(record) == (0,)
    else:
        record, _ = h.control(content(value=8, revision=8), ID=2, REGION=2)
        assert h.direct(record, replace=True) == (0,)
    h.publish(reveal=False)
    assert sorted(h.installed().controls) == ([1, 2, 3] if change == 'define' else [1, 2])


@pytest.mark.parametrize('order', ('drop-then-define', 'replace-then-drop', 'drop-then-replace'))
def test_the_commit_audit_refuses_a_write_into_a_region_dropped(regions, order):
    h = regions
    h.overlay()
    state = h.driver.core.retained_state
    h.begin('PT-RET-DELTA')
    if order == 'replace-then-drop':
        record, _ = h.control(content(value=8, revision=8), ID=2, REGION=2)
        assert h.direct(record, replace=True) == (0,)
    assert h.drop_region(2) == (0,)
    if order == 'drop-then-define':
        record, _ = h.control(ID=3, REGION=2)
        assert h.direct(record) == (0,)
    if order == 'drop-then-replace':
        record, _ = h.control(content(value=8, revision=8), ID=2, REGION=2)
        assert h.direct(record, replace=True) == (0,)
    assert h.commit() == (3,)
    assert h.call('RTAPT-RICH-CANCEL', h.engine)[0] == (0,)
    h.settle()
    assert h.driver.core.retained_state is state
    assert h.owner('ACTIVE-REGIONS', 'PENDING-REGION-DROPS') == (2, 0)
