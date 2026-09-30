"""PANE captures real geometry and owned title bytes through production PT."""
import hashlib
import struct
import sys
from contextlib import contextmanager
from dataclasses import replace
from unittest.mock import patch
import pytest

from test_rich_terminal_status_provider import ProviderHarness, RetainedFeature
import test_rich_terminal_cell_feed as cf
from test_rich_terminal_status_static import MASK
from simulator.memory import MMIO_BASE, SparseAddressSpace
from simulator.platform import SYSINFO_OFFSET


def capture_snapshot(h):
    """Include full owned banks, accounting, and transport output on refusal."""
    spans = ((h.constant("CF-OWNERS"), h.constant("RTAPT-OWNER-SIZE")),
             (h.field("_RTAPT-E.OPS-A"), h.field("_RTAPT-E.OPS-U")),
             (h.field("_RTAPT-E.COPY-A"), h.field("_RTAPT-E.COPY-U")),
             (h.field("_RTAPT-E.CONTROL-LEDGER-A"), h.field("_RTAPT-E.CONTROL-LEDGER-U")))
    return (tuple(hashlib.sha256(h.runtime.memory.read_bytes(a, u)).digest() for a, u in spans),
            tuple(h.field(name) for name in ("_RTAPT-E.OP-COUNT", "_RTAPT-E.COPY-USED",
                  "_RTAPT-E.RET-BYTES", "_RTAPT-E.CONTROL-LEDGER-USED")),
            h.runtime.uart_output, h.driver.core.retained_state)


@contextmanager
def observe_poison_reads(h, address):
    """Observe the real MMIO boundary without changing native admission identities."""
    hits = []
    previous = sys.getprofile()
    code = SparseAddressSpace._mmio_preflight.__code__

    def observe(frame, event, arg):
        if (event == "call" and frame.f_code is code and
                frame.f_locals.get("self") is h.runtime.memory and
                frame.f_locals["resolved"].address == address):
            hits.append(address)
        if previous is not None:
            previous(frame, event, arg)

    sys.setprofile(observe)
    try:
        yield hits
    finally:
        sys.setprofile(previous)


def reject_corrupt_prefixes(h, op_index, minimum, capture):
    """A valid fixed tail must not authorize malformed earlier operation framing."""
    op = h.field("_RTAPT-E.OPS-A") + op_index * h.constant("RTAPT-OP-SIZE")
    original = h.runtime.memory.read_bytes(op, h.constant("RTAPT-OP-SIZE"))
    # Read-only SysInfo is valid guest memory but far outside the owned copy bank.
    poison = MMIO_BASE + SYSINFO_OFFSET
    with observe_poison_reads(h, poison) as reads:
        # Positive control executes through the same selected Python/native runtime.
        h.call("@", poison)
        assert reads, "MMIO observer did not see an actual guest load"
        reads.clear()
        for offset, value in ((8, (poison - h.field("_RTAPT-E.COPY-A")) & MASK),
                              (8, h.field("_RTAPT-E.COPY-USED") + 8), (8, 1),
                              (16, minimum - 8), (16, minimum + 1), (16, 1 << 63)):
            h.runtime.memory.write64(op + offset, value)
            before = capture_snapshot(h)
            assert capture() == (3,), (op_index, offset, value)
            assert capture_snapshot(h) == before
            assert not reads, "malformed prefix dereferenced outside its owned copy span"
            h.runtime.memory.write_bytes(op, original)


class PaneProvider(ProviderHarness):
    def __init__(self, backend):
        policy = replace(cf._retained_policy(), max_operations_per_transaction=32)
        with patch.object(cf, "_retained_policy", return_value=policy):
            super().__init__(backend, features=RetainedFeature.CORE | RetainedFeature.PANES)

    def pane(self, title=b"Pane", *, identity=1, focused=True, **overrides):
        text = self.allocate(title) if title else 0
        fields = dict(OWNER=1, GENERATION=1, ID=identity, KIND=1, VISIBLE=MASK,
                      Z=0, REGION=1, PARENT=0, ROW=0, COL=0, HEIGHT=2, WIDTH=20,
                      ROOT_HEIGHT=2, ROOT_WIDTH=20, CONTENT_REGION=2,
                      CONTENT_ROW=0, CONTENT_COL=0, CONTENT_HEIGHT=1,
                      CONTENT_WIDTH=19, FOCUSED=MASK if focused else 0,
                      TITLE_A=text, TITLE_U=len(title), RESERVED=0)
        fields.update(overrides)
        return self.allocate(struct.pack("<23Q", *(v & MASK for v in fields.values()))), text

    def begin(self, mode="PT-RET-REPLACE-START", *, clip=(0, 0, 19, 1), z=1, flags=3,
              region=1, content_region=2):
        super().begin(mode, region=region)
        if mode == "PT-RET-REPLACE-START":
            assert self.call("RTAPT-REGION-DEFINE", 1, 1, content_region, 0, 0, 20, 2,
                             *clip, z, flags, self.engine)[0] == (0,)

    def snapshot(self):
        return capture_snapshot(self)


@pytest.fixture(params=("python", "native"))
def pane_provider(request):
    h = PaneProvider(request.param)
    try:
        yield h
    finally:
        h.close()


def test_pane_define_copies_title_and_binds_exact_region_geometry(pane_provider):
    h = pane_provider
    h.begin()
    record, text = h.pane()
    assert h.call("RTAPT-PANE-DEFINE", record, h.engine)[0] == (0,)
    assert h.field("_RTAPT-E.OP-COUNT") == 3
    assert h.field("_RTAPT-E.COPY-USED") == 208 + 192
    assert h.field("_RTAPT-E.RET-BYTES") == 208 + 148
    copied = h.field("_RTAPT-E.COPY-A") + 208
    assert h.runtime.memory.read64(copied + 160) == 0
    h.runtime.memory.write_bytes(text, b"XXXX")
    h.runtime.memory.write64(record + 112, 999)
    h.publish()
    obj = h.installed().objects[1]
    assert obj.body.title == "Pane"
    assert obj.body.content_region_id == 2
    assert obj.body.content_bounds.cell_cols == 19
    assert h.installed().usage.utf8_bytes == 4


def test_pane_same_candidate_replace_and_committed_refusal(pane_provider):
    h = pane_provider
    h.begin()
    record, _ = h.pane(b"Original")
    assert h.call("RTAPT-PANE-DEFINE", record, h.engine)[0] == (0,)
    record, text = h.pane(b"Updated", focused=False)
    assert h.call("RTAPT-PANE-REPLACE", record, h.engine)[0] == (0,)
    h.runtime.memory.write_bytes(text, b"XXXXXXX")
    h.publish()
    original = h.driver.core.retained_state
    assert h.installed().objects[1].body.title == "Updated"
    assert not h.installed().objects[1].body.focused
    h.begin("PT-RET-DELTA")
    record, _ = h.pane(b"Later")
    before = h.snapshot()
    assert h.call("RTAPT-PANE-REPLACE", record, h.engine)[0] == (4,)
    assert h.snapshot() == before
    assert h.call("RTAPT-RICH-CANCEL", h.engine)[0] == (0,)
    assert h.driver.core.retained_state is original


@pytest.mark.parametrize("changes", [
    {"CONTENT_REGION": 1}, {"CONTENT_REGION": 3}, {"CONTENT_WIDTH": 21},
    {"CONTENT_HEIGHT": 3}, {"CONTENT_ROW": -1}, {"PARENT": 1},
    {"VISIBLE": 0}, {"FOCUSED": 1}, {"KIND": 2}, {"RESERVED": 1},
    {"ROOT_HEIGHT": 3}, {"ROOT_WIDTH": 21},
])
def test_pane_bad_scalars_and_missing_region_do_not_mutate(pane_provider, changes):
    h = pane_provider
    h.begin()
    record, _ = h.pane(**changes)
    before = h.snapshot()
    assert h.call("RTAPT-PANE-DEFINE", record, h.engine)[0] == (3,)
    assert h.snapshot() == before


@pytest.mark.parametrize("kwargs", [
    {"clip": (0, 0, 20, 2)}, {"z": -1}, {"z": 0, "flags": 1, "clip": (0, 0, 0, 0)},
])
def test_pane_rejects_unclipped_or_outside_or_earlier_content_region(pane_provider, kwargs):
    h = pane_provider
    h.begin(**kwargs)
    record, _ = h.pane()
    before = h.snapshot()
    assert h.call("RTAPT-PANE-DEFINE", record, h.engine)[0] == (3,)
    assert h.snapshot() == before


@pytest.mark.parametrize("title", [b"\n", b"\xc2\x85", b"\xe2\x80\xa8", b"\xff"])
def test_pane_title_requires_independent_single_line_utf8(pane_provider, title):
    h = pane_provider
    h.begin()
    record, _ = h.pane(title)
    before = h.snapshot()
    assert h.call("RTAPT-PANE-DEFINE", record, h.engine)[0] == (3,)
    assert h.snapshot() == before


def test_pane_content_region_is_unique_and_growth_refused(pane_provider):
    h = pane_provider
    h.begin()
    record, _ = h.pane()
    assert h.call("RTAPT-PANE-DEFINE", record, h.engine)[0] == (0,)
    before = h.snapshot()
    record, _ = h.pane(identity=2)
    assert h.call("RTAPT-PANE-DEFINE", record, h.engine)[0] == (3,)
    assert h.snapshot() == before
    record, _ = h.pane(b"Larger title")
    assert h.call("RTAPT-PANE-REPLACE", record, h.engine)[0] == (3,)
    assert h.snapshot() == before


def test_pane_empty_title_and_zero_chrome_are_valid(pane_provider):
    h = pane_provider
    h.begin(clip=(0, 0, 20, 2))
    record, _ = h.pane(b"", CONTENT_WIDTH=20, CONTENT_HEIGHT=2)
    assert h.call("RTAPT-PANE-DEFINE", record, h.engine)[0] == (0,)
    h.publish()
    assert h.installed().objects[1].body.title == ""


@pytest.mark.parametrize("offset,value", [(112, 1), (160, 1), (168, 1 << 32), (176, 1)])
def test_pane_owned_forgery_fails_publication_audit(pane_provider, offset, value):
    h = pane_provider
    h.begin()
    record, _ = h.pane()
    assert h.call("RTAPT-PANE-DEFINE", record, h.engine)[0] == (0,)
    copied = h.field("_RTAPT-E.COPY-A") + 208
    h.runtime.memory.write64(copied + offset, value)
    assert h.call("_RTAPT-PUBLICATION-AUDIT?", 20, 2, h.engine)[0] == (0,)


@pytest.mark.parametrize("prior", ("region", "pane"))
def test_pane_prior_copy_framing_is_checked_before_any_prefix_read(pane_provider, prior):
    h = pane_provider
    h.begin()
    record, _ = h.pane()
    if prior == "pane":
        assert h.call("RTAPT-PANE-DEFINE", record, h.engine)[0] == (0,)
        # Keep a valid final op so CAPTURE-READY cannot reject only the last frame.
        assert h.call("RTAPT-PANE-REPLACE", record, h.engine)[0] == (0,)
        index, minimum, word = 2, 184, "RTAPT-PANE-REPLACE"
    else:
        index, minimum, word = 0, 104, "RTAPT-PANE-DEFINE"
    reject_corrupt_prefixes(h, index, minimum,
                           lambda: h.call(word, record, h.engine)[0])


@pytest.mark.parametrize("mode", ("PT-RET-DELTA", "PT-RET-REPLACE-CONTINUE"))
def test_pane_define_only_accepts_complete_replacement_candidates(pane_provider, mode):
    h = pane_provider
    h.begin()
    record, _ = h.pane()
    assert h.call("RTAPT-PANE-DEFINE", record, h.engine)[0] == (0,)
    h.publish(reveal=mode == "PT-RET-DELTA")
    h.begin(mode)
    before = h.snapshot()
    assert h.call("RTAPT-PANE-DEFINE", record, h.engine)[0] == (4,)
    assert h.snapshot() == before
    assert h.call("RTAPT-RICH-CANCEL", h.engine)[0] == (0,)


def test_pane_aborted_replacement_preserves_active_host_and_scrubs_title(pane_provider):
    h = pane_provider
    h.begin()
    record, _ = h.pane(b"Active")
    assert h.call("RTAPT-PANE-DEFINE", record, h.engine)[0] == (0,)
    h.publish()
    active = h.driver.core.retained_state
    h.begin(region=3, content_region=4)
    record, _ = h.pane(b"Secret", identity=2, REGION=3, CONTENT_REGION=4)
    assert h.call("RTAPT-PANE-DEFINE", record, h.engine)[0] == (0,)
    copied, used = h.field("_RTAPT-E.COPY-A"), h.field("_RTAPT-E.COPY-USED")
    assert h.call("RTAPT-RICH-CANCEL", h.engine)[0] == (0,)
    assert h.driver.core.retained_state is active
    assert h.installed().objects[1].body.title == "Active"
    assert h.runtime.memory.read_bytes(copied, used) == bytes(used)


def test_pane_source_and_title_must_be_disjoint_from_private_state(pane_provider):
    h = pane_provider
    h.begin()
    record, _ = h.pane()
    for name in ("_RTAPT-PND-I", "_RTAPT-PG-I"):
        scratch = h.constant(name)
        before = h.snapshot()
        assert h.call("RTAPT-PANE-DEFINE", scratch, h.engine)[0] == (3,)
        h.runtime.memory.write64(record + 160, scratch)
        assert h.call("RTAPT-PANE-DEFINE", record, h.engine)[0] == (3,)
        assert h.snapshot() == before


def test_pane_missing_capability_refuses_capture_and_replay(pane_provider):
    h = pane_provider
    h.begin()
    record, _ = h.pane()
    limits = h.call("_RTAPT-E.LIMITS", h.engine)[0][0]
    features = h.runtime.memory.read64(limits)
    h.runtime.memory.write64(limits, features & ~h.constant("RTAPT-F-PANES"))
    # With CORE only, remove semantic UTF8 as required by negotiated limits.
    h.runtime.memory.write64(limits + 120, 0)
    before = h.snapshot()
    assert h.call("RTAPT-PANE-DEFINE", record, h.engine)[0] == (4,)
    assert h.snapshot() == before
    h.runtime.memory.write64(limits, features)
    h.runtime.memory.write64(limits + 120, 128)
    assert h.call("RTAPT-PANE-DEFINE", record, h.engine)[0] == (0,)
    h.runtime.memory.write64(limits, features & ~h.constant("RTAPT-F-PANES"))
    h.runtime.memory.write64(limits + 120, 0)
    assert h.call("_RTAPT-PUBLICATION-AUDIT?", 20, 2, h.engine)[0] == (0,)
