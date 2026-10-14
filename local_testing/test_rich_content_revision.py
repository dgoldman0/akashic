"""A content control keeps its revision while its body is unchanged.

Every content control is packed with the frame's aggregate epoch as its
revision. The production comparison treats a body equal to the acknowledged
one in every byte but that revision as unchanged, and normalization gives it
back the revision the terminal holds, in the control and in its input target.
A changed body keeps the new epoch, which must be newer. Banks and content are
built here byte for byte; the comparison and normalization are production
words.
"""
import random
import struct

import pytest

from test_rich_glyph_growth import MASK64
from test_rich_kept_comparison_facts import FactsHarness, _identity

TEXT_AREA, ITEM_VIEW, DOCUMENT, MENU_ITEM = 5, 9, 14, 3
REGION = 7


class RevisionHarness(FactsHarness):
    def __init__(self, backend):
        super().__init__(backend, extra_words=(
            "_RTHP-D-CONTROL-COMPATIBLE?", "_RTHP-D-CONTROL-MARK-CHANGED?"))
        self.entry = self.constant("_RTHP-TARGET-ENTRY-SIZE")
        self.headers = {
            TEXT_AREA: (self.constant("USSTX-TAG"), self.constant("USSTX-CONTENT-HEADER-SIZE")),
            ITEM_VIEW: (self.constant("USITM-TAG"), self.constant("USITM-HEADER-SIZE")),
            DOCUMENT: (self.constant("USDOC-TAG"), self.constant("USDOC-HEADER-SIZE")),
        }

    def content(self, kind, revision, body):
        tag, header = self.headers[kind]
        fixed = struct.pack("<IHHQ", tag, 1, 0, revision)
        return fixed + bytes(header - len(fixed)) + body

    def seed(self, bank, *, first, epoch, controls, targets):
        """CONTROLS are (identity, kind, state, content-or-None) in graph and
        source order; TARGETS are (control ordinal, kind, revision)."""
        memory = self.runtime.memory
        memory.write_bytes(bank, bytes(self.bank_bytes))
        sources = [content for _, _, _, content in controls if content is not None]
        text_used = sum(len(content) for content in sources)
        for name, value in (("_RTHP-TB.COLS", 8), ("_RTHP-TB.ROWS", 4),
                            ("_RTHP-TB.CONTROL-COUNT", len(controls)),
                            ("_RTHP-TB.COUNT", len(targets)),
                            ("_RTHP-TB.GLYPH-SLOT-COUNT", 0),
                            ("_RTHP-TB.REGION", REGION),
                            ("_RTHP-TB.FIRST-OBJECT", first),
                            ("_RTHP-TB.CONTENT-EPOCH", epoch),
                            ("_RTHP-TB.SOURCE-TEXT-USED", text_used)):
            self.field(bank, name, value)
        for index, (ordinal, kind, revision) in enumerate(targets):
            entry = bank + self.header + index * self.entry
            for name, value in (("_RTHP-TE.ID", first + ordinal), ("_RTHP-TE.KIND", kind),
                                ("_RTHP-TE.REVISION", revision), ("_RTHP-TE.INTENTS", 1)):
                self.field(entry, name, value)
        control_base = bank + self.header + len(targets) * self.entry
        correlations = control_base + len(controls) * self.control
        source = correlations + len(controls) * self.correlation
        cursor = source
        for ordinal, (identity, kind, state, content) in enumerate(controls):
            control = control_base + ordinal * self.control
            for name, value in (("_RTE-CONTROL.ID", first + ordinal),
                                ("_RTE-CONTROL.KIND", kind),
                                ("_RTE-CONTROL.STATE", state),
                                ("_RTE-CONTROL.REGION", REGION)):
                self.field(control, name, value)
            if content is not None:
                memory.write_bytes(cursor, content)
                for name, value in (("_RTE-CONTROL.CONTENT-A", cursor),
                                    ("_RTE-CONTROL.CONTENT-U", len(content)),
                                    ("_RTE-CONTROL.CONTENT-ITEMS", 1),
                                    ("_RTE-CONTROL.CONTENT-UTF8", len(content))):
                    self.field(control, name, value)
                cursor += len(content)
            cells = (*identity[:4], first + ordinal, *identity[4:])
            memory.write_bytes(correlations + ordinal * self.correlation,
                               struct.pack("<7Q", *cells))
        return control_base

    def control_revision(self, control):
        address = self.runtime.memory.read64(control + self.offset("_RTE-CONTROL.CONTENT-A"))
        return struct.unpack("<Q", self.runtime.memory.read_bytes(address + 8, 8))[0]

    def compare(self, active, pending):
        """Pair, check and normalize the controls the production way.
        Returns None when the comparison refuses, else each control's
        changed flag."""
        self.begin(active, pending, False)
        assert self.call("_RTHP-D-BUILD-CONTROL-MAP?")
        changed = []
        for ordinal in range(self.read(pending, "_RTHP-TB.CONTROL-COUNT")):
            if not self.call("_RTHP-D-CONTROL-COMPATIBLE?", ordinal):
                return None
            flag = bool(self.variable("_RTHP-D-CHANGED") and self.variable("_RTHP-D-MATCHED"))
            if flag:
                assert self.call("_RTHP-D-CONTROL-MARK-CHANGED?")
            changed.append(flag)
        assert self.call("_RTHP-D-NORMALIZE")
        return changed


@pytest.fixture(params=("python", "native"))
def harness(request):
    return RevisionHarness(request.param)


def _frame(harness, bank, *, first, epoch, kind, revision, body, state=3, menu_revision=None):
    identities = [_identity(random.Random(11)), _identity(random.Random(12))]
    controls = [(identities[0], kind, state, harness.content(kind, revision, body)),
                (identities[1], MENU_ITEM, 3, None)]
    targets = [(0, kind, revision), (1, MENU_ITEM, menu_revision or epoch)]
    return harness.seed(bank, first=first, epoch=epoch, controls=controls, targets=targets)


def _target(harness, bank, index):
    entry = bank + harness.header + index * harness.entry
    return (harness.runtime.memory.read64(entry + harness.offset("_RTHP-TE.ID")),
            harness.runtime.memory.read64(entry + harness.offset("_RTHP-TE.REVISION")))


@pytest.mark.parametrize("kind", (TEXT_AREA, ITEM_VIEW, DOCUMENT))
def test_an_unchanged_body_keeps_the_acknowledged_revision(harness, kind):
    active, pending = harness.banks
    _frame(harness, active, first=100, epoch=5, kind=kind, revision=5, body=b"same body")
    controls = _frame(harness, pending, first=200, epoch=9, kind=kind, revision=9,
                      body=b"same body")
    assert harness.compare(active, pending) == [False, False]
    assert harness.control_revision(controls) == 5
    # The input target follows its control: final ID and the kept revision.
    assert _target(harness, pending, 0) == (100, 5)
    # A target without content keeps the revision it was extracted with.
    assert _target(harness, pending, 1) == (101, 9)


@pytest.mark.parametrize("kind", (TEXT_AREA, ITEM_VIEW, DOCUMENT))
def test_a_changed_body_takes_the_newer_revision(harness, kind):
    active, pending = harness.banks
    _frame(harness, active, first=100, epoch=5, kind=kind, revision=5, body=b"old body")
    controls = _frame(harness, pending, first=200, epoch=9, kind=kind, revision=9,
                      body=b"new body")
    assert harness.compare(active, pending) == [True, False]
    assert harness.control_revision(controls) == 9
    assert _target(harness, pending, 0) == (100, 9)


def test_a_state_change_alone_keeps_the_revision(harness):
    active, pending = harness.banks
    _frame(harness, active, first=100, epoch=5, kind=TEXT_AREA, revision=5, body=b"text")
    controls = _frame(harness, pending, first=200, epoch=9, kind=TEXT_AREA, revision=9,
                      body=b"text", state=1)
    assert harness.compare(active, pending) == [True, False]
    assert harness.control_revision(controls) == 5
    assert _target(harness, pending, 0) == (100, 5)


def test_a_changed_body_without_a_newer_revision_is_refused(harness):
    active, pending = harness.banks
    _frame(harness, active, first=100, epoch=5, kind=TEXT_AREA, revision=5, body=b"old")
    _frame(harness, pending, first=200, epoch=5, kind=TEXT_AREA, revision=5, body=b"new")
    assert harness.compare(active, pending) is None


def test_a_revision_above_its_banks_epoch_is_refused(harness):
    active, pending = harness.banks
    _frame(harness, active, first=100, epoch=5, kind=TEXT_AREA, revision=6, body=b"same")
    _frame(harness, pending, first=200, epoch=9, kind=TEXT_AREA, revision=9, body=b"same")
    assert harness.compare(active, pending) is None


def test_a_kept_revision_carries_across_frames_until_the_body_changes(harness):
    banks = list(harness.banks)
    epochs = (5, 9, 12, 15)
    bodies = (b"steady", b"steady", b"steady", b"edited")
    _frame(harness, banks[0], first=100, epoch=epochs[0], kind=TEXT_AREA,
           revision=epochs[0], body=bodies[0])
    expected = (5, 5, 15)
    first = 200
    for epoch, body, revision in zip(epochs[1:], bodies[1:], expected):
        active, pending = banks
        controls = _frame(harness, pending, first=first, epoch=epoch, kind=TEXT_AREA,
                          revision=epoch, body=body)
        assert harness.compare(active, pending) is not None
        assert harness.control_revision(controls) == revision
        assert _target(harness, pending, 0)[1] == revision
        banks.reverse()
        first += 100
