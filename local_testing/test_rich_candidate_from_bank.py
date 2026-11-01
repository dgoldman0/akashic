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

from test_rich_glyph_growth import MASK64, PRODUCER
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
            "_RTHP-UB-STATUS?", "_RTHP-UB-DOCUMENTS?", "_RTHP-W-LOWER-BEGIN",
            "_RTHP-W-APPEND-COLLECTION-CLAIMS?", "_RTHP-UB-MENU-CLAIMS?",
            "_RTHP-UB-MENUS-CLEAR?", "_RTHP-UB-MENU-SPLICE?"))

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


def test_an_instrument_claim_keeps_the_generation_of_its_data_graphics(h):
    """Each claim takes this snapshot's generation but an instrument's, which
    lies between the claims before the instruments and the status fields'
    and carries the generation of the data graphics it shows
    (FRAMES-FOLLOW-CHANGE 9c.4)."""
    h.candidate()
    bank = h.bank_on_screen()
    claims = h.results("_RTHP-PACK-CLAIMS-A", bank)[0]
    # The bank's second claim lies where an instrument's would.
    h.field(bank, "_RTHP-TB.BASE-CLAIMS", 80)
    h.runtime.memory.write64(claims + 80 + 8, 77)
    h.forget()
    h.field(h.producer, "_RTHP.SOURCE-GEN", 31)
    h.unpack()
    out = h.get("CLAIMS-A")
    assert [h.runtime.memory.read64(out + i * 80 + 8) for i in range(3)] == [31, 77, 31]


def test_a_correlation_keeps_naming_its_control_by_identity(h):
    """A menu's correlations keep their source order while its controls lie
    in graph order, so a correlation names its control by identity, which
    the unpack moves with the control's own."""
    h.candidate()
    corr = h.get("CORR-A")
    memory = h.runtime.memory
    memory.write64(corr + 32, 101)
    memory.write64(corr + 56 + 32, 100)
    h.bank_on_screen()
    h.forget()
    h.field(h.producer, "_RTHP.FIRST-OBJECT", 300)
    h.unpack()
    assert (memory.read64(corr + 32), memory.read64(corr + 56 + 32)) == (301, 300)


@pytest.mark.parametrize("ids, named, parent, out_named", (
    # A control defined before the other, with an identity past the last:
    # each correlation names the control in its own place, and the parent
    # lies in the place before its child.
    ((105, 100), (105, 100), 105, (300, 301)),
    # Correlations in another order, each found through the bank.
    ((105, 100), (100, 105), 105, (301, 300)),
    # A control dropped before both, which keep their order: the second
    # correlation's control lies as far from its number as the first's.
    ((101, 102), (102, 101), 101, (301, 300)),
    # A control defined last, after the controls numbered by place.
    ((100, 105), (100, 105), 100, (300, 301)),
), ids=("defined", "reordered", "dropped", "appended"))
def test_a_bank_numbered_by_identity_is_numbered_by_place(h, ids, named, parent, out_named):
    """A DELTA that defines or drops controls leaves the bank on screen
    numbered by the identities on screen until the next START, and they
    follow their places only in part (FRAMES-FOLLOW-CHANGE 9c.3b).  The
    unpack finds each identity a correlation or parent names in its place
    in the bank, and numbers the control there as a full lowering would."""
    h.candidate()
    bank = h.bank_on_screen()
    memory = h.runtime.memory
    size = h.constant("RTE-CONTROL-SIZE")
    controls, = h.results("_RTHP-PACK-CONTROLS-A", bank)
    correlations, = h.results("_RTHP-PACK-CORR-A", bank)
    for index in range(2):
        memory.write64(controls + index * size + h.offset("_RTE-CONTROL.ID"), ids[index])
        memory.write64(correlations + index * 56 + 32, named[index])
    memory.write64(controls + size + h.offset("_RTE-CONTROL.PARENT"), parent)
    before = h.spans()
    h.forget()
    h.field(h.producer, "_RTHP.FIRST-OBJECT", 300)
    h.unpack()
    out, corr = h.get("CONTROLS-A"), h.get("CORR-A")
    assert [memory.read64(out + i * size + h.offset("_RTE-CONTROL.ID"))
            for i in range(2)] == [300, 301]
    assert tuple(memory.read64(corr + i * 56 + 32) for i in range(2)) == out_named
    assert memory.read64(out + h.offset("_RTE-CONTROL.PARENT")) == 0
    assert memory.read64(out + size + h.offset("_RTE-CONTROL.PARENT")) == 300
    assert h.spans()["claims"] == before["claims"]


@pytest.mark.parametrize("where", ("correlation", "parent"))
def test_a_bank_naming_a_control_it_does_not_hold_is_not_taken(h, where):
    """A correlation or parent naming an identity the bank on screen does
    not hold has no place, so the bank cannot be taken."""
    h.candidate()
    bank = h.bank_on_screen()
    memory = h.runtime.memory
    if where == "correlation":
        correlations, = h.results("_RTHP-PACK-CORR-A", bank)
        memory.write64(correlations + 32, 102)
    else:
        controls, = h.results("_RTHP-PACK-CONTROLS-A", bank)
        memory.write64(controls + h.constant("RTE-CONTROL-SIZE")
                       + h.offset("_RTE-CONTROL.PARENT"), 102)
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


def test_the_full_lowering_claims_every_collection_after_a_refused_unpack(h):
    """A candidate taken from a bank with fields and a dialog takes their
    counts, and one refused afterwards leaves them.  The full lowering
    starts with no field or dialog lowered or refused, so the collections'
    claims, which end where the fields begin, reach the last collection."""
    h.candidate()
    memory = h.runtime.memory
    text_area = h.get("CONTROLS-A") + h.constant("RTE-CONTROL-SIZE")
    for name, value_ in (("ROW", 4), ("HEIGHT", 4), ("WIDTH", 32)):
        h.field(text_area, "_RTE-CONTROL." + name, value_)
    claim = h.get("CLAIMS-A") + h.constant("RUCL-CLAIM-SIZE")
    expected = memory.read_bytes(claim, h.constant("RUCL-CLAIM-SIZE"))
    left = (("FIELD-COUNT", 1), ("FIELD-ITEMS", 2), ("FIELD-UTF8", 3),
            ("FIELD-REFUSED", MASK64), ("DIALOG-COUNT", 1), ("DIALOG-CONTROLS", 1),
            ("DIALOG-UTF8", 4), ("DIALOG-REFUSED", MASK64))
    for name, value_ in left:
        h.field(h.producer, "_RTHP." + name, value_)
    h.results("_RTHP-W-LOWER-BEGIN", h.producer)
    assert [h.get(name) for name, _ in left] == [0] * len(left)
    # The collections lowered, their claims follow the menu bar's.
    memory.write_bytes(claim, bytes(h.constant("RUCL-CLAIM-SIZE")))
    h.variable("_RTHP-W-CLAIMS", 1)
    assert h.call("_RTHP-W-APPEND-COLLECTION-CLAIMS?")
    assert h.variable("_RTHP-W-CLAIMS") == 2
    assert memory.read_bytes(claim, h.constant("RUCL-CLAIM-SIZE")) == expected
    source = PRODUCER.read_text()
    lower = source[source.index(": _RTHP-W-LOWER  "):]
    lower = lower[:lower.index(" ;")]
    assert lower.index("_RTHP-W-LOWER-BEGIN") < lower.index("_RTHP-BUILD-CONTROLS")


# A claim: its attachment, generation, source, index, subkey and depth, then
# its rectangle, rows and columns from the first to past the last.
def claim(attachment, rect, *, index=20):
    return struct.pack("<10Q", attachment, 9, 1, index, 0, 0, *rect)


CLAIM = 80
BAR = (0, 0, 1, 32)          # a menu bar across the top
DROPDOWN = (1, 0, 4, 12)     # a menu open beneath it
TEXT = (4, 0, 8, 32)         # a text area beneath


def menus_setup(h, claims, *, documents=(11,), records=8):
    """A candidate holding CLAIMS, the menus' first, with a directory of
    DOCUMENTS by token and room for RECORDS menu claims."""
    h.setup(label=b"Ln", value=b"1", width=20, row=3, col=2, documents=len(documents))
    for index, token in enumerate(documents):
        h.document(index, token=token)
    h.runtime.memory.write_bytes(h.get("CLAIMS-A"), b"".join(claims))
    h.field(h.producer, "_RTHP.CLAIMS-USED", len(claims) * CLAIM)
    h.field(h.producer, "_RTHP.MAX-RECORDS", records)
    h.variable("_RTHP-UB-P", h.producer)


def test_a_documents_menu_claims_follow_those_of_the_documents_before_it(h):
    """The candidate from the bank on screen finds the claims of a moved
    document's menus among the menus' claims, which lie in the order of
    their documents (FRAMES-FOLLOW-CHANGE 9c.3c)."""
    menus_setup(h, [claim(11, BAR), claim(11, DROPDOWN), claim(12, BAR)],
                documents=(11, 12))
    h.field(h.producer, "_RTHP.MENU-CLAIMS", 3)
    for document, first, count in ((0, 0, 2), (1, 2, 1)):
        h.variable("_RTHP-W-DOCUMENT-I", document)
        assert h.call("_RTHP-UB-MENU-CLAIMS?")
        assert (h.variable("_RTHP-UB-MC-FIRST"), h.variable("_RTHP-UB-MC-N")) == (first, count)
    # Claims out of their documents' order, or of no document, are refused.
    for attachments in ((12, 11, 11), (11, 99, 12)):
        menus_setup(h, [claim(a, BAR) for a in attachments], documents=(11, 12))
        h.field(h.producer, "_RTHP.MENU-CLAIMS", 3)
        h.variable("_RTHP-W-DOCUMENT-I", 1)
        assert not h.call("_RTHP-UB-MENU-CLAIMS?")


def changed_menus(h, later, *, field_count=1, field_descriptors=128):
    """A candidate whose document 11 had the menu bar's claim and now has a
    menu open beneath it too, built past its claims: a text area's claim,
    then the claims LATER, as many fields' as FIELD-COUNT, then a dialog's,
    an instrument's and a status field's, where each is not None."""
    field, dialog, instrument, status = later
    claims = [claim(11, BAR), claim(11, TEXT, index=21)]
    bases = {}
    for name, rect in (("FIELD-BASE-CLAIMS", field), ("DIALOG-BASE-CLAIMS", dialog),
                       ("BASE-CLAIMS-USED", instrument), ("STATIC-BASE-CLAIMS", status)):
        bases[name] = len(claims) * CLAIM
        if rect is not None:
            claims.append(claim(11, rect, index=22 + len(claims)))
    menus_setup(h, claims)
    for name, value in bases.items():
        h.field(h.producer, "_RTHP." + name, value)
    h.field(h.producer, "_RTHP.MENU-CLAIMS", 1)
    h.field(h.producer, "_RTHP.FIELD-COUNT", field_count)
    h.field(h.producer, "_RTHP.FIELD-DESCRIPTORS-USED", field_descriptors)
    h.field(h.producer, "_RTHP.STATIC-COUNT", 1)
    built = h.get("CLAIMS-A") + h.get("CLAIMS-USED")
    h.runtime.memory.write_bytes(built, claim(11, BAR) + claim(11, DROPDOWN))
    for name, value in (("_RTHP-UB-MC-FIRST", 0), ("_RTHP-UB-MC-N", 1),
                        ("_RTHP-UB-MC-NEW", 2), ("_RTHP-UB-MC-A", built)):
        h.variable(name, value)
    return claims


@pytest.mark.parametrize("later, clear", (
    # A field, dialog and status field clear of the menus.
    (((5, 0, 6, 10), (5, 12, 7, 20), None, (7, 0, 8, 10)), True),
    # A field the open menu now covers.
    (((2, 2, 3, 10), None, None, None), False),
    # A dialog that met the menu bar.
    ((None, (0, 20, 3, 30), None, None), False),
    # A status field beneath the open menu.
    ((None, None, None, (3, 4, 4, 8)), False),
    # An instrument's claim is checked with the whole frame's, not here.
    ((None, None, (2, 2, 3, 10), (7, 0, 8, 10)), True),
))
def test_changed_menu_claims_are_taken_only_clear_of_the_lanes_that_check_them(h, later, clear):
    """The fields', dialogs' and status fields' lanes check each rectangle
    against the claims before it, the menus' among them, so the candidate
    takes menus whose claims changed only when none of those lanes' claims
    meets the menus' claims, the old or the new."""
    changed_menus(h, later)
    assert bool(h.call("_RTHP-UB-MENUS-CLEAR?")) == clear


def test_changed_menu_claims_need_every_checking_lane_unrefused(h):
    """A lane that holds nothing while the snapshot has items for it may
    have been refused because of the old claims."""
    changed_menus(h, (None, None, None, (7, 0, 8, 10)), field_count=0)
    assert not h.call("_RTHP-UB-MENUS-CLEAR?")
    changed_menus(h, (None, None, None, (7, 0, 8, 10)), field_count=0, field_descriptors=0)
    assert h.call("_RTHP-UB-MENUS-CLEAR?")


@pytest.mark.parametrize("old, new", ((2, 1), (1, 1), (1, 2), (1, 3)))
def test_menu_claims_built_again_take_the_old_ones_place(h, old, new):
    """The menus' claims built again replace the old, and the claims after
    them move on, with where each lane's claims begin."""
    menus = [claim(11, BAR), claim(11, DROPDOWN), claim(11, (1, 12, 3, 20))]
    later = [claim(11, TEXT, index=21), claim(11, (5, 0, 6, 10), index=22),
             claim(11, (7, 0, 8, 10), index=23)]
    menus_setup(h, [claim(11, BAR, index=40 + i) for i in range(old)] + later)
    bases = {"FIELD-BASE-CLAIMS": (old + 1) * CLAIM, "DIALOG-BASE-CLAIMS": (old + 2) * CLAIM,
             "BASE-CLAIMS-USED": (old + 2) * CLAIM, "STATIC-BASE-CLAIMS": (old + 2) * CLAIM}
    for name, value in bases.items():
        h.field(h.producer, "_RTHP." + name, value)
    h.field(h.producer, "_RTHP.MENU-CLAIMS", old)
    built = h.get("CLAIMS-A") + h.get("CLAIMS-USED")
    h.runtime.memory.write_bytes(built, b"".join(menus[:new]))
    for name, value in (("_RTHP-UB-MC-FIRST", 0), ("_RTHP-UB-MC-N", old),
                        ("_RTHP-UB-MC-NEW", new), ("_RTHP-UB-MC-A", built)):
        h.variable(name, value)
    assert h.call("_RTHP-UB-MENU-SPLICE?")
    assert h.get("MENU-CLAIMS") == new
    assert h.get("CLAIMS-USED") == (new + 3) * CLAIM
    assert h.runtime.memory.read_bytes(h.get("CLAIMS-A"), (new + 3) * CLAIM) == (
        b"".join(menus[:new]) + b"".join(later))
    moved = (new - old) * CLAIM
    for name, value in bases.items():
        assert h.get(name) == value + moved
    h.guards()


def test_menu_claims_that_do_not_fit_are_not_taken(h):
    """More claims than the menus may hold, or than the claims' storage
    holds past those that move, leave the candidate as it was."""
    menus_setup(h, [claim(11, BAR), claim(11, TEXT, index=21)], records=1)
    built = h.get("CLAIMS-A") + h.get("CLAIMS-USED")
    h.runtime.memory.write_bytes(built, claim(11, BAR) + claim(11, DROPDOWN))
    h.field(h.producer, "_RTHP.MENU-CLAIMS", 1)
    for name, value in (("_RTHP-UB-MC-FIRST", 0), ("_RTHP-UB-MC-N", 1),
                        ("_RTHP-UB-MC-NEW", 2), ("_RTHP-UB-MC-A", built)):
        h.variable(name, value)
    before = h.runtime.memory.read_bytes(h.get("CLAIMS-A"), 2 * CLAIM)
    assert not h.call("_RTHP-UB-MENU-SPLICE?")
    h.field(h.producer, "_RTHP.MAX-RECORDS", 8)
    h.field(h.producer, "_RTHP.CLAIMS-U", 4 * CLAIM)
    assert not h.call("_RTHP-UB-MENU-SPLICE?")
    assert h.runtime.memory.read_bytes(h.get("CLAIMS-A"), 2 * CLAIM) == before
    assert (h.get("MENU-CLAIMS"), h.get("CLAIMS-USED")) == (1, 2 * CLAIM)



def test_a_moved_menus_root_is_lowered_alone_by_the_full_lowerings_words(h):
    """The candidate plans a moved document's menus, and builds its menu
    claims, by the words the full lowering takes each document's with."""
    menus = h.definitions["_RTHP-UB-MENUS?"]
    assert "_RTHP-W-DOC-MENUS?" in menus and "_RTHP-W-DOC-MENU-CLAIMS?" in menus
    assert "_RTHP-W-DOC-MENUS?" in h.definitions["_RTHP-BUILD-MENU-CONTROLS?"]
    assert "_RTHP-W-DOC-MENU-CLAIMS?" in h.definitions["_RTHP-BUILD-CLAIMS?"]
    assert "URF-F-MENUS = IF _RTHP-UB-MENUS?" in " ".join(
        h.definitions["_RTHP-UB-MOVED?"].split())
