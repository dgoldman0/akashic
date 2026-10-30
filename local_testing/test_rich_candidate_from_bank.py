"""The screen producer takes its candidate from the bank on screen.

When only text roots and status fields moved since the bank on screen, the
producer unpacks that bank into its candidate instead of lowering every
root: the controls, correlations and their text, the status fields with
theirs, and the claims, numbered and stamped as a full lowering numbers
and stamps them, with their counts and where each lane began.  Each moved
root is then lowered alone into its place by its lane's own words.

These tests run the production words over a candidate of one menu control,
one text area and one status field, whose status field the real lane
lowers: the candidate is packed into a bank as a frame on screen would be,
and unpacked again.  The text area's lowering in place, and the whole
path, are compared with a full lowering by the shadow check's unpack stage
in the physical journeys.
"""

from __future__ import annotations

import struct

import pytest

from test_rich_glyph_growth import MASK64
from test_rich_status_producer import StatusHarness

LABEL = b"File"
# A text root's content: its header, the revision at byte 8, and its body.
EPOCH = 9


def content(revision=EPOCH, body=b"hello, world"):
    return b"STX1" + bytes(4) + struct.pack("<Q", revision) + body


class BankHarness(StatusHarness):
    def __init__(self, backend):
        super().__init__(backend, extra_words=(
            "_RTHP-TG-HEADER!", "_RTHP-UB-ROOM?", "_RTHP-UB-CONTROLS?",
            "_RTHP-UB-STATICS?", "_RTHP-UB-TEXT-ROOM?", "_RTHP-UB-STATIC-ROOM?",
            "_RTHP-UB-STATUS?", "_RTHP-UB-DOCUMENTS?"))

    def candidate(self):
        """One menu bar labelled LABEL, one text area, and a status field."""
        self.setup(label=b"Ln", value=b"1", width=20, row=3, col=2)
        self.document(0, token=11)
        self.lower()

    def lower(self):
        """The candidate's controls, with a claim apiece, the menus' first,
        and its status field as the real lane lowers it."""
        memory = self.runtime.memory
        size = self.constant("RTE-CONTROL-SIZE")
        corr = self.constant("RUCP-CORRELATION-SIZE")
        text = self.get("SOURCE-TEXT-A")
        body = content()
        memory.write_bytes(text, LABEL + body)
        controls, correlations = self.get("CONTROLS-A"), self.get("CORR-A")
        for index, (kind, label, data) in enumerate((
                (self.constant("RTE-CONTROL-MENU-BAR"), (text, len(LABEL)), (0, 0)),
                (self.constant("RTE-CONTROL-TEXT-AREA"), (0, 0),
                 (text + len(LABEL), len(body))))):
            control = controls + index * size
            memory.write_bytes(control, bytes(size))
            for name, value_ in (("OWNER", 1), ("GENERATION", 2), ("ID", 100 + index),
                                 ("KIND", kind), ("STATE", 3), ("REGION", 7),
                                 ("LABEL-A", label[0]), ("LABEL-U", label[1]),
                                 ("CONTENT-A", data[0]), ("CONTENT-U", data[1])):
                self.field(control, "_RTE-CONTROL." + name, value_)
            memory.write_bytes(correlations + index * corr,
                               struct.pack("<7Q", 11, 1, 20 + index, 1, 100 + index, 0, 0))
        claims = self.get("CLAIMS-A")
        memory.write_bytes(claims, struct.pack("<10Q", 11, 9, 1, 20, 0, 0, 0, 0, 1, 32)
                           + struct.pack("<10Q", 11, 9, 1, 21, 1, 0, 4, 0, 8, 32))
        for name, value_ in (("CONTROL-COUNT", 2), ("MENU-CONTROL-COUNT", 1),
                             ("COLLECTION-COUNT", 1), ("SOURCE-MENU-TEXT-USED", len(LABEL)),
                             ("SOURCE-TEXT-USED", len(LABEL) + len(body)),
                             ("CLAIMS-USED", 160), ("MENU-CLAIMS", 1),
                             ("SOURCE-CONTENT-EPOCH", EPOCH), ("SHELL-CONTROLS", 0)):
            self.field(self.producer, "_RTHP." + name, value_)
        assert self.build() == (self.constant("RTE-S-OK"),)
        used = len(LABEL) + len(body)
        for name, value_ in (("FIELD-BASE-TEXT", used), ("DIALOG-BASE-TEXT", used),
                             ("FIELD-BASE-CLAIMS", 160), ("DIALOG-BASE-CLAIMS", 160),
                             ("BASE-CLAIMS-USED", 160)):
            self.field(self.producer, "_RTHP." + name, value_)

    def bank_on_screen(self):
        """The candidate packed into a bank, as a frame on screen keeps it."""
        bank = self.get("TARGET0-A")
        self.variable("_RTHP-TG-P", self.producer)
        self.variable("_RTHP-TG-BANK", bank)
        self.results("_RTHP-TG-HEADER!")
        assert self.call("_RTHP-PACK-ADMITTED-CANDIDATE", bank, self.producer)
        assert self.call("_RTHP-PACKED-BANK?", bank, self.producer)
        self.bank = bank
        self.variable("_RTHP-UB-P", self.producer)
        self.variable("_RTHP-UB-A", bank)
        self.variable("_RTHP-W-P", self.producer)
        return bank

    def spans(self):
        """The candidate's controls, correlations, text, claims and status
        fields, with their counts and lane bounds."""
        memory = self.runtime.memory
        n, statics = self.get("CONTROL-COUNT"), self.get("STATIC-COUNT")
        return {
            "controls": memory.read_bytes(self.get("CONTROLS-A"),
                                          n * self.constant("RTE-CONTROL-SIZE")),
            "correlations": memory.read_bytes(self.get("CORR-A"),
                                              n * self.constant("RUCP-CORRELATION-SIZE")),
            "text": memory.read_bytes(self.get("SOURCE-TEXT-A"), self.get("SOURCE-TEXT-USED")),
            "claims": memory.read_bytes(self.get("CLAIMS-A"), self.get("CLAIMS-USED")),
            "statics": memory.read_bytes(self.get("STATICS-A"),
                                         statics * self.constant("RTE-STATIC-SIZE")),
            "static_corr": memory.read_bytes(self.get("STATIC-CORR-A"), statics * 40),
            "static_text": memory.read_bytes(self.get("STATIC-TEXT-A"),
                                             self.get("STATIC-TEXT-USED")),
            "fields": tuple(self.get(name) for name in (
                "CONTROL-COUNT", "MENU-CONTROL-COUNT", "COLLECTION-COUNT",
                "SOURCE-TEXT-USED", "CLAIMS-USED", "MENU-CLAIMS", "FIELD-BASE-TEXT",
                "FIELD-BASE-CLAIMS", "DIALOG-BASE-TEXT", "DIALOG-BASE-CLAIMS",
                "BASE-CLAIMS-USED", "STATIC-BASE-CLAIMS", "STATIC-COUNT",
                "STATIC-TEXT-USED", "STATIC-LAST")),
        }

    def forget(self):
        """Overwrite every candidate span the unpack fills, but the menus'
        text, which is the snapshot's, and its counts."""
        memory = self.runtime.memory
        menu = self.get("SOURCE-MENU-TEXT-USED")
        for name, length in (("CONTROLS-A", 2 * self.constant("RTE-CONTROL-SIZE")),
                             ("CORR-A", 2 * self.constant("RUCP-CORRELATION-SIZE")),
                             ("CLAIMS-A", 240), ("STATICS-A", self.constant("RTE-STATIC-SIZE")),
                             ("STATIC-CORR-A", 40), ("STATIC-TEXT-A", 8)):
            memory.write_bytes(self.get(name), b"\xa5" * length)
        memory.write_bytes(self.get("SOURCE-TEXT-A") + menu, b"\xa5" * 24)
        for name in ("CONTROL-COUNT", "MENU-CONTROL-COUNT", "COLLECTION-COUNT",
                     "SOURCE-TEXT-USED", "CLAIMS-USED", "MENU-CLAIMS", "FIELD-BASE-TEXT",
                     "FIELD-BASE-CLAIMS", "DIALOG-BASE-TEXT", "DIALOG-BASE-CLAIMS",
                     "BASE-CLAIMS-USED", "STATIC-BASE-CLAIMS", "STATIC-COUNT",
                     "STATIC-TEXT-USED", "STATIC-LAST"):
            self.field(self.producer, "_RTHP." + name, 0)

    def unpack(self):
        assert self.call("_RTHP-UB-ROOM?")
        assert self.call("_RTHP-UB-CONTROLS?")
        assert self.call("_RTHP-UB-STATICS?")


@pytest.fixture(params=("python", "native"))
def h(request):
    return BankHarness(request.param)


def test_a_bank_unpacks_to_the_candidate_packed_into_it(h):
    h.candidate()
    h.bank_on_screen()
    before = h.spans()
    h.forget()
    h.unpack()
    assert h.spans() == before
    h.guards()


def test_the_unpack_numbers_each_item_as_a_full_lowering_would(h):
    """A candidate numbers its objects from the frontier, which moves on
    past the frame on screen's: each control, its correlation and the status
    field take the identity of their place from the candidate's first
    object, the menus' text keeps its place, and a text root's content
    takes this snapshot's content epoch."""
    h.candidate()
    h.bank_on_screen()
    before = h.spans()
    h.forget()
    h.field(h.producer, "_RTHP.FIRST-OBJECT", 300)
    h.field(h.producer, "_RTHP.SOURCE-CONTENT-EPOCH", 31)
    h.unpack()
    memory = h.runtime.memory
    size = h.constant("RTE-CONTROL-SIZE")
    for index in range(2):
        control = h.get("CONTROLS-A") + index * size
        assert memory.read64(control + h.offset("_RTE-CONTROL.ID")) == 300 + index
        assert memory.read64(h.get("CORR-A") + index * 56 + 32) == 300 + index
    statics = h.get("STATICS-A")
    assert memory.read64(statics + h.offset("_RTE-STATIC.ID")) == 302
    assert h.get("STATIC-LAST") == 302
    text_area = h.get("CONTROLS-A") + size
    revision = memory.read64(text_area + h.offset("_RTE-CONTROL.CONTENT-A"))
    assert memory.read64(revision + 8) == 31
    assert h.spans()["claims"] == before["claims"]


def test_a_bank_numbered_otherwise_is_not_taken(h):
    """The bank on screen numbers its controls by place from its first
    object, which shows where each parent lies; one that does not cannot
    be taken."""
    h.candidate()
    bank = h.bank_on_screen()
    controls, = h.results("_RTHP-PACK-CONTROLS-A", bank)
    h.runtime.memory.write64(controls + h.offset("_RTE-CONTROL.ID"), 105)
    h.forget()
    assert h.call("_RTHP-UB-ROOM?")
    assert not h.call("_RTHP-UB-CONTROLS?")


def test_a_text_that_grows_moves_what_follows_it(h):
    h.candidate()
    h.bank_on_screen()
    h.forget()
    h.unpack()
    memory = h.runtime.memory
    text = h.get("SOURCE-TEXT-A")
    size = h.constant("RTE-CONTROL-SIZE")
    text_area = h.get("CONTROLS-A") + size
    old = memory.read64(text_area + h.offset("_RTE-CONTROL.CONTENT-A"))
    body = memory.read_bytes(old, len(content()))
    # The menu bar's label ends where the text area's content begins.
    assert h.call("_RTHP-UB-TEXT-ROOM?", len(LABEL), 8)
    assert memory.read64(text_area + h.offset("_RTE-CONTROL.CONTENT-A")) == old + 8
    assert memory.read_bytes(old + 8, len(body)) == body
    assert memory.read64(h.get("CONTROLS-A") + h.offset("_RTE-CONTROL.LABEL-A")) == text
    used = len(LABEL) + len(content()) + 8
    assert (h.get("SOURCE-TEXT-USED"), h.get("FIELD-BASE-TEXT"),
            h.get("DIALOG-BASE-TEXT")) == (used, used, used)
    # A text that shrinks moves it back; one past the room left is refused.
    assert h.call("_RTHP-UB-TEXT-ROOM?", len(LABEL) + 8, -8 & MASK64)
    assert memory.read64(text_area + h.offset("_RTE-CONTROL.CONTENT-A")) == old
    assert h.get("SOURCE-TEXT-USED") == used - 8
    assert not h.call("_RTHP-UB-TEXT-ROOM?", len(LABEL), h.get("SOURCE-TEXT-U"))


def test_a_moved_status_field_is_lowered_alone_in_its_place(h):
    """The status field's value grows: lowered alone into the unpacked
    candidate, it gives what its lane gives the whole candidate."""
    h.candidate()
    h.bank_on_screen()
    h.forget()
    h.unpack()
    # The snapshot's status field now holds the longer value.
    memory = h.runtime.memory
    model = struct.pack("<9Q", 80, 1, 23, 20, 6, 2, 3, 2, 2) + b"Ln12" + bytes(4)
    memory.write_bytes(h.get("STATUS-NATIVE-A"), model)
    memory.write64(h.get("STATUS-DESCRIPTORS-A") + 15 * 8, 4)
    root = h.allocate(struct.pack("<6Q", 11, h.constant("URF-F-STATUS-FIELD"), 1, 4, 0, 1)
                      + bytes(h.constant("URF-SIZE") - 48))
    assert h.call("_RTHP-UB-STATUS?", root)
    unpacked = h.spans()
    assert unpacked["static_text"] == b"Ln12"
    # The full lowering of the same snapshot, into the same storage.
    h.lower()
    assert h.spans() == unpacked


def test_a_status_field_that_moves_its_rectangle_is_refused(h):
    h.candidate()
    h.bank_on_screen()
    h.forget()
    h.unpack()
    memory = h.runtime.memory
    # The descriptor's column: the field now lies elsewhere.
    memory.write64(h.get("STATUS-DESCRIPTORS-A") + 6 * 8, 4)
    memory.write64(h.get("STATUS-DESCRIPTORS-A") + 10 * 8, 4)
    root = h.allocate(struct.pack("<6Q", 11, h.constant("URF-F-STATUS-FIELD"), 1, 4, 0, 1)
                      + bytes(h.constant("URF-SIZE") - 48))
    assert not h.call("_RTHP-UB-STATUS?", root)


def test_every_document_must_lie_where_it_lay(h):
    h.candidate()
    h.bank_on_screen()
    assert h.call("_RTHP-UB-DOCUMENTS?")
    entry = h.get("SOURCE-DIR-A")
    h.runtime.memory.write64(entry + h.offset("_RUHA-D.ROW"), 1)
    assert not h.call("_RTHP-UB-DOCUMENTS?")
