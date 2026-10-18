"""A modal region reaches the terminal only through a negotiated dialogs
family (APT-1-RETAINED-1 sections 4 and 8), through production PT."""
import pytest

from test_rich_terminal_status_provider import ProviderHarness, RetainedFeature
from test_rich_terminal_pane_provider import capture_snapshot

CONTROLS = RetainedFeature.CORE | RetainedFeature.CONTROLS


def _features(h):
    limits, status = h.call("RTAPT-LIMITS@", h.engine)[0]
    assert status == 0
    return h.runtime.memory.read64(limits)


def _define(h, flags):
    # Region 2, one row of the 20-column surface, above region 1.
    return h.call("RTAPT-REGION-DEFINE", 1, 1, 2, 0, 1, 20, 1,
                  0, 0, 0, 0, 1, flags, h.engine)[0]


@pytest.mark.parametrize("backend", ("python", "native"))
def test_a_modal_region_without_dialogs_is_unsupported(backend):
    h = ProviderHarness(backend, features=CONTROLS)
    try:
        assert not _features(h) & h.constant("RTAPT-F-DIALOGS")
        h.begin()
        before = capture_snapshot(h)
        assert _define(h, 5) == (4,)
        assert capture_snapshot(h) == before
        assert _define(h, 1) == (0,)
    finally:
        h.close()


@pytest.mark.parametrize("backend", ("python", "native"))
def test_a_negotiated_modal_region_reaches_the_terminal(backend):
    h = ProviderHarness(backend, features=CONTROLS | RetainedFeature.DIALOGS)
    try:
        assert _features(h) & h.constant("RTAPT-F-DIALOGS")
        h.begin()
        assert _define(h, 5) == (0,)
        h.publish()
        regions = h.installed().regions
        assert regions[2].modal and not regions[1].modal
    finally:
        h.close()
