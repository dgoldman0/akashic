"""An open owner asks the real terminal for more space.

The complete PT module, Akashic engine, neutral facade and its APT-1 bridge
run against the real terminal driver; no Desktop starts.  The terminal
shares one budget between two owners, so it can say yes or have no room.
"""
from dataclasses import replace
from unittest.mock import patch

import pytest

import test_rich_terminal_cell_feed as cf
from test_rich_terminal_status_static import RICH, SOURCE, _clean, _word
from simulator.runtime import MegaForthRuntime
from tests.simulator.test_kdos_exceptions import _load_exceptions
from rich_terminal.retained_model import RetainedFeature


QUOTA_FIELDS = ("regions", "resources", "objects", "series",
                "resource_bytes", "utf8_bytes", "sample_slots")


class ResizeHarness(cf._FeedHarness):
    def __init__(self, backend):
        fixture = cf._fixture_source(20).replace(
            b"CREATE CF-OWNERS-MEM RTAPT-OWNER-SIZE 7 + ALLOT",
            b"CREATE CF-OWNERS-MEM RTAPT-OWNER-SIZE 2 * 7 + ALLOT",
        ).replace(
            b"CF-SESSION CF-OWNERS RTAPT-OWNER-SIZE CF-OPS",
            b"CF-SESSION CF-OWNERS RTAPT-OWNER-SIZE 2 * CF-OPS",
        )
        with patch.object(cf, "_fixture_source", return_value=fixture), patch.object(
            cf, "_load_exceptions", side_effect=lambda: _load_exceptions(
                MegaForthRuntime(execution_backend=backend))
        ):
            super().__init__(cf.SOURCE.read_bytes(), cols=20)
        self.runtime.evaluate((
            _word((RICH.parents[1] / "utils/string.f").read_text(), "/STRING")
            + "\n" + _clean(SOURCE) + "\n"
            + "\n".join(_clean((RICH / name).read_text()) for name in (
                "region-catalog.f", "family-batch.f", "provider-family.f")) + "\n"
            + _clean((RICH / "engine-apt1.f").read_text())
        ).encode(), source_name="production-neutral-apt1-bridge.f", step_budget=8_000_000)
        arena = self.runtime.define_created("RSZ-ARENA", initial_body=bytes(1031))
        self.arena = (arena.body_address + 7) & -8
        base = cf._retained_policy()
        with patch.object(cf, "_retained_policy", return_value=replace(
            base, features=RetainedFeature.CORE | RetainedFeature.STATUS_FIELDS,
            max_owner_records=2, max_live_owners=2,
            max_objects=8, total_utf8_bytes=256,
        )):
            self.attach()
        self.facade = self.arena
        self.quotas = self.arena + 256
        assert self.call("RTAPTE-INIT", self.engine, self.facade)[0] == (0,)

    def constant(self, name):
        return self.call(name)[0][0]

    def field(self, name, record):
        return self.runtime.memory.read64(self.call(name, record)[0][0])

    def owner(self, index):
        return self.constant("CF-OWNERS") + index * self.constant("RTAPT-OWNER-SIZE")

    def settle(self):
        for _ in range(16):
            status = self.call("RTAPT-STEP", self.engine)[0]
            self.service()
            if (self.field("_RTAPT-E.ACTIVE-KIND", self.engine) == 0
                    and self.field("_RTAPT-E.QUEUE-HEAD", self.engine) == 0):
                return status
        raise AssertionError("retained provider failed to settle")

    def open(self, owner, objects, utf8):
        assert self.call("RTE-OWNER-OPEN", owner, 1, 1, 0, objects, 0, 0, utf8, 0,
                         self.facade)[0] == (0,)
        assert self.settle() == (0,)
        assert self.state(owner) == self.constant("RTE-OWNER-ST-OPEN")

    def resize(self, owner, objects, utf8):
        return self.call("RTE-OWNER-RESIZE", owner, 1, 1, 0, objects, 0, 0, utf8, 0,
                         self.facade)[0]

    def state(self, owner):
        state, status = self.call("RTE-OWNER-STATE@", owner, 1, self.facade)[0]
        assert status == 0
        return state

    def held(self, owner):
        assert self.call("RTE-OWNER-QUOTAS@", self.quotas, owner, 1, self.facade)[0] == (0,)
        return tuple(self.runtime.memory.read64(self.quotas + 8 * i) for i in range(7))

    def terminal(self, owner):
        quotas = self.driver.core.owner_state.records[owner].quotas
        return tuple(getattr(quotas, name) for name in QUOTA_FIELDS)


@pytest.fixture(params=("python", "native"))
def harness(request):
    fixture = ResizeHarness(request.param)
    try:
        yield fixture
    finally:
        fixture.close()


def test_the_terminal_grants_more_space_and_the_owner_holds_it(harness):
    harness.open(1, objects=2, utf8=64)
    assert harness.resize(1, objects=5, utf8=200) == (0,)
    assert harness.state(1) == harness.constant("RTE-OWNER-ST-RESIZING")
    # Until the terminal answers, only what was granted counts.
    assert harness.held(1) == (1, 0, 2, 0, 0, 64, 0)

    assert harness.settle() == (0,)
    assert harness.state(1) == harness.constant("RTE-OWNER-ST-OPEN")
    assert harness.held(1) == (1, 0, 5, 0, 0, 200, 0)
    assert harness.terminal(1) == (1, 0, 5, 0, 0, 200, 0)
    assert harness.driver.core.capacity_denials == 0
    owner = harness.owner(0)
    assert all(harness.field(f"_RTAPT-O.ASK-{name}", owner) == 0 for name in (
        "REGIONS", "RESOURCES", "OBJECTS", "SERIES", "RES-BYTES", "UTF8-BYTES", "SAMPLES"))
    assert harness.call("RTAPT-VALID?", harness.engine)[0] == (harness.constant("TRUE"),)


def test_with_no_room_the_owner_keeps_what_it_had(harness):
    # Two owners share the terminal's eight objects.
    harness.open(1, objects=4, utf8=64)
    harness.open(2, objects=4, utf8=64)
    assert harness.resize(1, objects=5, utf8=64) == (0,)
    rejected = harness.constant("RTAPT-S-REJECTED")
    assert harness.settle() == (rejected,)
    assert harness.state(1) == harness.constant("RTE-OWNER-ST-OPEN")
    assert harness.held(1) == (1, 0, 4, 0, 0, 64, 0)
    assert harness.terminal(1) == (1, 0, 4, 0, 0, 64, 0)
    # The terminal keeps its own record of the refusal.
    assert harness.driver.core.capacity_denials == 1
    denial = harness.driver.core.last_capacity_denial
    assert (denial["request"], denial["owner_id"]) == ("OWNER_RESIZE", 1)
    assert (denial["requested"]["objects"], denial["held"]["objects"]) == (5, 4)
    assert harness.call("RTAPT-VALID?", harness.engine)[0] == (harness.constant("TRUE"),)

    # Once the other owner is gone there is room, and the same request is granted.
    assert harness.call("RTE-OWNER-DROP", 2, 1, harness.facade)[0] == (0,)
    harness.settle()
    assert harness.resize(1, objects=5, utf8=64) == (0,)
    assert harness.settle() == (0,)
    assert harness.held(1) == (1, 0, 5, 0, 0, 64, 0)


def test_a_request_must_not_shrink_and_asking_for_what_is_held_does_nothing(harness):
    harness.open(1, objects=4, utf8=64)
    invalid = harness.constant("RTE-S-INVALID")
    assert harness.resize(1, objects=3, utf8=200) == (invalid,)
    assert harness.resize(1, objects=4, utf8=64) == (0,)
    assert harness.state(1) == harness.constant("RTE-OWNER-ST-OPEN")
    assert harness.field("_RTAPT-E.QUEUE-HEAD", harness.engine) == 0
    # An owner that is not open cannot ask.
    assert harness.resize(2, objects=4, utf8=64) == (invalid,)
    # While one request waits, the owner cannot ask again.
    assert harness.resize(1, objects=5, utf8=64) == (0,)
    assert harness.resize(1, objects=6, utf8=64) == (harness.constant("RTE-S-WOULD-BLOCK"),)
    assert harness.settle() == (0,)
    assert harness.held(1) == (1, 0, 5, 0, 0, 64, 0)
