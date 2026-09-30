"""Exact bounded TASKBAR slots through real retained CONTROL publication."""
import pytest
from dataclasses import replace
from unittest.mock import patch
import test_rich_terminal_cell_feed as cf
from test_rich_terminal_status_provider import ProviderHarness, RetainedFeature
from test_rich_terminal_pane_provider import capture_snapshot, reject_corrupt_prefixes
from test_rich_terminal_status_static import MASK


class TaskbarProvider(ProviderHarness):
    def __init__(self, backend):
        fixture = cf._fixture_source(20).replace(
            b"CREATE CF-LEDGER-MEM RTAPT-CONTROL-LEDGER-SIZE 7 + ALLOT",
            b"CREATE CF-LEDGER-MEM RTAPT-CONTROL-LEDGER-SIZE 4 * 7 + ALLOT",
        ).replace(b"CF-LEDGER RTAPT-CONTROL-LEDGER-SIZE",
                  b"CF-LEDGER RTAPT-CONTROL-LEDGER-SIZE 4 *")
        policy = replace(cf._retained_policy(), max_operations_per_transaction=32)
        with patch.object(cf, "_fixture_source", return_value=fixture), patch.object(
                cf, "_retained_policy", return_value=policy):
            super().__init__(backend, features=(RetainedFeature.CORE | RetainedFeature.CONTROLS |
                                               RetainedFeature.TASKBARS))

    def control(self, identity, kind, *, label=b"", state=3, parent=0,
                order=0, row=1, col=0, width=20, region=1, height=1,
                shortcut=b"", **overrides):
        text = self.allocate(label) if label else 0
        shortcut_a = self.allocate(shortcut) if shortcut else 0
        fields = dict(owner=1, generation=1, identity=identity, kind=kind, state=state,
                      z=0, region=region, parent=parent, order=order, row=row, col=col,
                      height=height, width=width, root_height=2, root_width=20,
                      label_a=text, label_u=len(label), shortcut_a=shortcut_a,
                      shortcut_u=len(shortcut), content_a=0, content_u=0,
                      content_items=0, content_utf8=0, content_runs=0, content_fields=0)
        fields.update(overrides)
        return tuple(value & MASK for value in fields.values()), text

    def define(self, args):
        return self.call("RTAPT-CONTROL-DEFINE", *args, self.engine)[0]


@pytest.fixture(params=("python", "native"))
def taskbar_provider(request):
    h = TaskbarProvider(request.param)
    try:
        yield h
    finally:
        h.close()


def test_taskbar_exact_children_and_minimized_state(taskbar_provider):
    h = taskbar_provider
    h.begin()
    args,_ = h.control(1,10)
    assert h.define(args) == (0,)
    args,text = h.control(2,11,label=b"[App]",state=11,parent=1,row=0,width=6)
    assert h.define(args) == (0,)
    h.runtime.memory.write_bytes(text,b"XXXXX")
    args,_ = h.control(3,11,label=b"Mini",state=35,parent=1,order=1,row=0,col=7,width=5)
    assert h.define(args) == (0,)
    args,_ = h.control(4,12,label=b"Open",parent=1,order=2,row=0,col=13,width=7)
    assert h.define(args) == (0,)
    h.publish()
    owner = h.installed()
    assert [owner.controls[i].kind.value for i in (1,2,3,4)] == [10,11,11,12]
    assert owner.controls[2].label == "[App]"
    assert owner.controls[3].state & 32
    assert owner.controls[4].bounds.cell_x == 13
    assert owner.usage.objects == 4
    assert owner.usage.utf8_bytes == 13


def _root(h):
    args, _ = h.control(1, 10)
    assert h.define(args) == (0,)


def _slot(h, identity=2, **kwargs):
    defaults = dict(label=b"App", parent=1, row=0, width=6)
    defaults.update(kwargs)
    return h.control(identity, defaults.pop("kind", 11), **defaults)[0]


@pytest.mark.parametrize("changes", [
    {"parent": 0}, {"parent": 999}, {"parent": 2}, {"region": 2},
    {"row": 1}, {"col": -1}, {"height": 2}, {"width": 0},
    {"col": 18, "width": 3}, {"order": 1 << 32}, {"z": 1},
    {"state": 43}, {"state": 9}, {"state": 10}, {"state": 7},
    {"kind": 12, "state": 11}, {"kind": 12, "state": 35},
])
def test_taskbar_malformed_slot_is_atomic(taskbar_provider, changes):
    h = taskbar_provider
    h.begin()
    _root(h)
    # A second existing region makes same-region authority independently observable.
    assert h.call("RTAPT-REGION-DEFINE", 1, 1, 2, 0, 0, 20, 2,
                  0, 0, 0, 0, 0, 1, h.engine)[0] == (0,)
    args = _slot(h, **changes)
    before = capture_snapshot(h)
    assert h.define(args) == (3,)
    assert capture_snapshot(h) == before


def test_taskbar_root_shape_and_foreign_parent_kind(taskbar_provider):
    h = taskbar_provider
    h.begin()
    for changes in ({"height": 2}, {"parent": 1}, {"order": 1},
                    {"state": 11}, {"state": 35}, {"label": b"Root"},
                    {"shortcut": b"F1"}):
        args, _ = h.control(1, 10, **changes)
        before = capture_snapshot(h)
        assert h.define(args) == (3,), changes
        assert capture_snapshot(h) == before
    args, _ = h.control(1, 1)  # An ordinary menubar is not a TASKBAR parent.
    assert h.define(args) == (0,)
    before = capture_snapshot(h)
    assert h.define(_slot(h)) == (3,)
    assert capture_snapshot(h) == before


def test_taskbar_siblings_have_unique_orders_disjoint_slots_and_one_selection(taskbar_provider):
    h = taskbar_provider
    h.begin()
    _root(h)
    assert h.define(_slot(h, state=11)) == (0,)
    for changes in ({"col": 7, "order": 0}, {"col": 5, "order": 1},
                    {"col": 5, "order": 1, "state": 0},
                    {"col": 7, "order": 1, "state": 11}):
        before = capture_snapshot(h)
        assert h.define(_slot(h, 3, **changes)) == (3,), changes
        assert capture_snapshot(h) == before
    # Adjacent slots and sparse authored orders are legal; no packing is inferred.
    assert h.define(_slot(h, 3, col=6, order=9, state=35)) == (0,)
    h.publish()
    assert h.installed().controls[3].order == 9
    assert h.installed().controls[3].bounds.cell_x == 6


@pytest.mark.parametrize("label", (b"", b"\n", b"\xc2\x85", b"\xe2\x80\xa8", b"\xff"))
def test_taskbar_independent_strict_single_line_label(taskbar_provider, label):
    h = taskbar_provider
    h.begin()
    _root(h)
    before = capture_snapshot(h)
    assert h.define(_slot(h, label=label)) == (3,)
    assert capture_snapshot(h) == before


def test_taskbar_private_text_aliases_refuse_before_scratch_mutation(taskbar_provider):
    h = taskbar_provider
    h.begin()
    _root(h)
    for name in ("_RTAPT-CD-OWNER", "_RTAPT-TG-OWNER", "_RTAPT-HAF-OWNER"):
        scratch = h.constant(name)
        for span in ("label", "shortcut"):
            args = _slot(h, **{span + "_a": scratch, span + "_u": 1})
            before = capture_snapshot(h)
            scratch_before = h.runtime.memory.read64(scratch)
            assert h.define(args) == (3,), (name, span)
            assert h.runtime.memory.read64(scratch) == scratch_before
            assert capture_snapshot(h) == before


def test_taskbar_missing_capability_refuses_capture_and_replay(taskbar_provider):
    h = taskbar_provider
    h.begin()
    args, _ = h.control(1, 10)
    limits = h.call("_RTAPT-E.LIMITS", h.engine)[0][0]
    features = h.runtime.memory.read64(limits)
    h.runtime.memory.write64(limits, features & ~h.constant("RTAPT-F-TASKBARS"))
    before = capture_snapshot(h)
    assert h.define(args) == (4,)
    assert capture_snapshot(h) == before
    h.runtime.memory.write64(limits, features)
    assert h.define(args) == (0,)
    h.runtime.memory.write64(limits, features & ~h.constant("RTAPT-F-TASKBARS"))
    before = capture_snapshot(h)
    assert h.call("_RTAPT-PUBLICATION-AUDIT?", 20, 2, h.engine)[0] == (0,)
    assert capture_snapshot(h) == before


@pytest.mark.parametrize("prior", ("region", "root"))
def test_taskbar_prior_copy_framing_refuses_without_out_of_bank_reads(taskbar_provider, prior):
    h = taskbar_provider
    h.begin()
    _root(h)
    assert h.define(_slot(h)) == (0,)  # Valid final record independent of forged prefix.
    args = _slot(h, 3, col=7, order=1)
    reject_corrupt_prefixes(h, 0 if prior == "region" else 1,
                           104 if prior == "region" else 160, lambda: h.define(args))


def test_taskbar_replay_rechecks_geometry_graph_and_owned_text(taskbar_provider):
    h = taskbar_provider
    h.begin()
    _root(h)
    assert h.define(_slot(h)) == (0,)
    assert h.define(_slot(h, 3, col=7, order=1, state=11)) == (0,)
    # Native CONTROL fixed fields use x/y order, unlike the caller's row/col stack.
    copy = h.field("_RTAPT-E.COPY-A")
    slot = copy + 104 + 160
    original = h.runtime.memory.read_bytes(slot, 168)
    for offset, value in ((24, 10), (32, 43), (48, 2), (56, 999), (64, 1),
                          (72, 6), (80, 1), (96, 2), (120, 1), (104, 1 << 32)):
        h.runtime.memory.write64(slot + offset, value)
        before = capture_snapshot(h)
        assert h.call("_RTAPT-PUBLICATION-AUDIT?", 20, 2, h.engine)[0] == (0,), (offset, value)
        assert capture_snapshot(h) == before
        h.runtime.memory.write_bytes(slot, original)
    h.runtime.memory.write_bytes(slot + 160, b"\n")
    assert h.call("_RTAPT-PUBLICATION-AUDIT?", 20, 2, h.engine)[0] == (0,)


def test_taskbar_candidate_only_policy_and_abort_preserve_active_slots(taskbar_provider):
    h = taskbar_provider
    h.begin()
    _root(h)
    args = _slot(h)
    assert h.define(args) == (0,)
    before = capture_snapshot(h)
    assert h.call("RTAPT-CONTROL-REPLACE", *args, h.engine)[0] == (4,)
    assert capture_snapshot(h) == before
    h.publish()
    active = h.driver.core.retained_state
    h.begin("PT-RET-DELTA")
    before = capture_snapshot(h)
    assert h.define(_slot(h, 3)) == (4,)
    assert h.call("RTAPT-CONTROL-REPLACE", *args, h.engine)[0] == (4,)
    assert capture_snapshot(h) == before
    assert h.call("RTAPT-RICH-CANCEL", h.engine)[0] == (0,)
    assert h.driver.core.retained_state is active
    h.begin(region=2)
    root, _ = h.control(3, 10, region=2)
    assert h.define(root) == (0,)
    assert h.define(_slot(h, 4, parent=3, region=2, label=b"Private")) == (0,)
    copy, used = h.field("_RTAPT-E.COPY-A"), h.field("_RTAPT-E.COPY-USED")
    assert h.call("RTAPT-RICH-CANCEL", h.engine)[0] == (0,)
    assert h.driver.core.retained_state is active
    assert h.installed().controls[2].label == "App"
    assert h.runtime.memory.read_bytes(copy, used) == bytes(used)
