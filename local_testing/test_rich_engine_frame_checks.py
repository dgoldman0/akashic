"""The calls every frame makes check the engine's state, and walk its ledgers
only with every-frame checks on (tui/check-mode.f).

The complete PT module and Akashic engine run against the real terminal
driver, as in the CELL-feed checks; no Desktop starts.
"""

import test_rich_terminal_cell_feed as cf

MASK64 = (1 << 64) - 1


def _top(harness, word, *inputs):
    return harness.call(word, *inputs)[0][-1]


def test_frame_calls_walk_the_ledgers_only_with_every_frame_checks():
    h = cf._FeedHarness(cf.SOURCE.read_bytes())
    memory = h.runtime.memory
    invalid = _top(h, "RTAPT-S-INVALID")
    switch = h.runtime.find("CHK-EVERY-FRAME").body_address
    owner = memory.read64(_top(h, "_RTAPT-E.OWNERS-A", h.engine))
    used = _top(h, "_RTAPT-O.RES-COUNT", owner)
    granted = memory.read64(_top(h, "_RTAPT-O.RESOURCES", owner))
    held = memory.read64(used)

    sound = _top(h, "RTAPT-LIMITS@", h.engine)
    assert sound != invalid
    assert _top(h, "RTAPT-VALID?", h.engine) == MASK64
    # An owner holding more resources than it was granted: a ledger that only
    # the engine writes is wrong, and nothing in the engine's state shows it.
    memory.write64(used, granted + 1)
    assert _top(h, "RTAPT-VALID?", h.engine) == 0
    # A frame's limits query walks the ledgers with every-frame checks on...
    assert _top(h, "RTAPT-LIMITS@", h.engine) == invalid
    # ...and in normal mode checks the engine's state only.  Explicit VALID?
    # walks them in both modes.
    memory.write64(switch, 0)
    assert _top(h, "RTAPT-LIMITS@", h.engine) == sound
    assert _top(h, "RTAPT-VALID?", h.engine) == 0
    memory.write64(switch, MASK64)
    memory.write64(used, held)
    assert _top(h, "RTAPT-LIMITS@", h.engine) == sound
