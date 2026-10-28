"""Execute real dialog lowering, owned target packing and button input.

A document's frozen UDLG dialog becomes one DIALOG control and a BUTTON for
each shown button, after the fields.  Only the outer producer-validity hook
is scripted; lowering, the audit, packing, bank authority and input lookup
are the production words.  Independent byte fixtures encode the UDLG, UDLSN,
DLG1 and BTN1 layouts.
"""
import struct

import pytest

from test_rich_status_producer import StatusHarness
from test_rich_glyph_growth import MASK64

TITLE = b"Delete"
MESSAGE = b"Remove notes.md?\nIt cannot be undone."
DLG1 = struct.Struct("<IHHQIIiiIIiiII")
SOURCE = 3
KEY = 42
# A UDLSN descriptor's bytes.
DESCRIPTOR = 80


def pad(data):
    return data + bytes((-len(data)) % 8)


def button(label, slot, roles, state, shortcut=b""):
    return (struct.pack("<9Q", 72 + len(pad(label)) + len(pad(shortcut)), roles, state,
                        *slot, len(label), len(shortcut)) + pad(label) + pad(shortcut))


# A 30 by 8 dialog: the title "Delete" on the top edge, two message lines,
# [ Delete ], destructive, beside [ Cancel ], the selected default and
# cancel button.
def model(*, revision=7, title=TITLE, buttons=None, width=30, height=8):
    buttons = buttons if buttons is not None else (
        (b"Delete", (6, 4, 1, 10), 4, 3), (b"Cancel", (6, 16, 1, 10), 3, 7))
    body = pad(title) + pad(MESSAGE) + b"".join(button(*b) for b in buttons)
    title_slot = (0, 2, 1, len(title)) if title else (0, 0, 0, 0)
    cells = (160 + len(body), 1, KEY, revision, width, height, 0, 3, *title_slot,
             2, 2, 2, 26, len(title), len(MESSAGE), len(buttons), 0)
    return struct.pack("<20Q", *cells) + body


class DialogHarness(StatusHarness):
    def __init__(self, backend):
        super().__init__(backend, overrides={"RTHP-VALID?": ": RTHP-VALID? DROP -1 ;"},
                         extra_words=("RTHP-STORAGE-BYTES", "_RTHP-BUILD-DIALOGS",
                                      "_RTHP-W-BUILD-OPTIONAL-DIALOGS", "_RTHP-STRIP-DIALOGS?",
                                      "_RTHP-COPY-DIALOG-SOURCE?", "_RTHP-DIALOGS-FIXED?",
                                      "_RTHP-TG-DIALOG-TARGETS?", "RTHP-CONTROL-TARGET@",
                                      "_RTHP-D-CONTROL-COMPATIBLE?", "_RTHP-U-CLONE?",
                                      "_RTHP-TARGET-BANK-ENTRIES?", "RTE-CONTROL-PLAN-VALID?",
                                      "_RTHP-W-TOTAL", "_RTHP-LAYERS-COVERED?"))

    def setup(self, *, dialog_native=1024, row=0, col=1, document=(0, 0, 8, 32), **kwargs):
        self.producer = self.allocate(bytes(self.constant("RTHP-SIZE")))
        size, = self.results("RTHP-STORAGE-BYTES", 1, 1, 64, 256, 256, 512,
                             0, dialog_native, 0, 32, 8)
        assert size
        self.arena_size = size
        self.arena = self.allocate(b"LEFTGUAR" + bytes(size) + b"RIGHTGUA") + 8
        for name, n in {"ARENA-A": self.arena, "ARENA-U": size, "MAX-DOCUMENTS": 1,
                        "MAX-RECORDS": 1, "MAX-TEXT": 64, "MAX-COLLECTION-NATIVE": 256,
                        "MAX-COLLECTION-DESCRIPTORS": 8, "MAX-COLLECTIONS": 4,
                        "MAX-CONTROLS": 5 + dialog_native // 72, "MAX-DGRAPH-NATIVE": 256,
                        "MAX-DGRAPH-DESCRIPTORS": 1, "MAX-INSTRUMENT-REGIONS": 1,
                        "MAX-INSTRUMENTS": 2, "MAX-STATUS-NATIVE": 512, "MAX-STATICS": 7,
                        "MAX-DIALOG-NATIVE": dialog_native, "MAX-DIALOGS": dialog_native // 160,
                        "MAX-DIALOG-CONTROLS": dialog_native // 72,
                        "MAX-COLS": 32, "MAX-ROWS": 8, "COLS": 32, "ROWS": 8,
                        "OWNER": 1, "OWNER-GEN": 2, "REGION": 7, "FIRST-OBJECT": 100,
                        "SOURCE-GEN": 9, "SOURCE-CONTENT-EPOCH": 29, "SOURCE-DRAW": 12,
                        "SURFACE-GEN": 12, "PHYSICAL-GEN": 1, "DOCUMENT-COUNT": 1}.items():
            self.field(self.producer, "_RTHP." + name, n)
        self.results("_RTHP-LAYOUT", self.producer)
        self.variable("_RTHP-W-P", self.producer)
        self.variable("_RTHP-W-DOCUMENTS", 1)
        self.dir = self.get("SOURCE-DIR-A")
        self.field(self.producer, "_RTHP.SOURCE-DIR-USED", self.constant("RUHA-DOCUMENT-SIZE"))
        self.runtime.memory.write_bytes(self.dir, struct.pack("<6Q", 11, 5, *document))
        self.model = model(**kwargs)
        self.row, self.col = row, col
        # A dialog widget's descriptor: its buttons lie at 255, and it has no
        # contents.
        self.descriptor = struct.pack("<10Q", SOURCE, KEY, 0, row, col,
                                      kwargs.get("height", 8), kwargs.get("width", 30),
                                      len(self.model), 255, 0)
        self.runtime.memory.write_bytes(self.get("DIALOG-NATIVE-A"), self.model)
        self.runtime.memory.write_bytes(self.get("DIALOG-DESCRIPTORS-A"), self.descriptor)
        self.field(self.producer, "_RTHP.DIALOG-DESCRIPTORS-USED", DESCRIPTOR)
        self.field(self.producer, "_RTHP.DIALOG-NATIVE-USED", len(self.model))
        for offset, n in ((240, 0), (248, DESCRIPTOR), (256, 0), (264, len(self.model))):
            self.runtime.memory.write64(self.dir + offset, n)

    def build(self):
        return self.results("_RTHP-BUILD-DIALOGS", self.producer)

    def fixed(self):
        self.field(self.producer, "_RTHP.BASE-CLAIMS-USED", self.get("CLAIMS-USED"))
        return self.call("_RTHP-DIALOGS-FIXED?", self.producer)

    def control(self, index):
        return self.get("CONTROLS-A") + index * self.constant("RTE-CONTROL-SIZE")

    def read(self, address, name):
        return self.runtime.memory.read64(address + self.offset(name))

    def span(self, control, name):
        a = self.read(control, f"_RTE-CONTROL.{name}-A")
        return self.runtime.memory.read_bytes(a, self.read(control, f"_RTE-CONTROL.{name}-U"))

    def correlation(self, index):
        x = self.get("CORR-A") + index * self.constant("RUCP-CORRELATION-SIZE")
        return struct.unpack("<7Q", self.runtime.memory.read_bytes(x, 56))

    def pack(self, index=0):
        bank = self.get(f"TARGET{index}-A")
        for name, n in {"COLS": 32, "ROWS": 8, "DOCUMENT-COUNT": 1, "OWNER": 1, "GENERATION": 2,
                        "REGION": 7, "FIRST-OBJECT": self.get("FIRST-OBJECT"), "DRAW": 12,
                        "SOURCE-GEN": 9, "PHYSICAL-GEN": 1, "CONTENT-EPOCH": 29,
                        "GLYPH-RUN-LIMIT": 256,
                        "CONTROL-COUNT": self.get("CONTROL-COUNT"),
                        "SOURCE-TEXT-USED": self.get("SOURCE-TEXT-USED"),
                        "DIALOG-CONTROLS": self.get("DIALOG-CONTROLS"),
                        "DIALOG-COUNT": self.get("DIALOG-COUNT"),
                        "DIALOG-UTF8": self.get("DIALOG-UTF8")}.items():
            self.field(bank, "_RTHP-TB." + name, n)
        self.variable("_RTHP-TG-P", self.producer)
        self.variable("_RTHP-TG-BANK", bank)
        self.variable("_RTHP-TG-COUNT", 0)
        self.variable("_RTHP-CT-P", self.producer)
        assert self.call("_RTHP-TG-DIALOG-TARGETS?")
        self.field(bank, "_RTHP-TB.COUNT", self.variable("_RTHP-TG-COUNT"))
        assert self.call("_RTHP-PACK-ADMITTED-CANDIDATE", bank, self.producer)
        assert self.call("_RTHP-PACKED-BANK?", bank, self.producer)
        assert self.call("_RTHP-TARGET-BANK-HEADER?", bank, self.producer)
        assert self.call("_RTHP-TARGET-BANK-ENTRIES?")
        self.guards()
        return bank

    def activate(self, bank):
        self.field(self.producer, "_RTHP.TARGET-ACTIVE", bank)
        self.field(self.producer, "_RTHP.ACTIVE-DRAW", 12)


@pytest.fixture(params=("python", "native"))
def h(request):
    return DialogHarness(request.param)


def test_a_dialog_lowers_to_one_dialog_and_its_buttons(h):
    h.setup()
    assert h.build() == (0,)
    assert h.fixed()
    assert (h.get("CONTROL-COUNT"), h.get("DIALOG-CONTROLS"), h.get("DIALOG-COUNT")) == (3, 3, 1)
    assert h.get("DIALOG-UTF8") == len(TITLE) + len(MESSAGE) + 12
    assert h.get("CLAIMS-USED") == h.constant("RUCL-CLAIM-SIZE")
    assert h.variable("_RTHP-W-GLYPH-FIRST") == 103
    dialog, delete, cancel = (h.control(i) for i in range(3))
    kinds = [h.read(c, "_RTE-CONTROL.KIND") for c in (dialog, delete, cancel)]
    assert kinds == [h.constant("RTE-CONTROL-DIALOG"), *[h.constant("RTE-CONTROL-BUTTON")] * 2]
    rects = [tuple(h.read(c, "_RTE-CONTROL." + n) for n in ("ROW", "COL", "HEIGHT", "WIDTH"))
             for c in (dialog, delete, cancel)]
    assert rects == [(0, 1, 8, 30), (6, 5, 1, 10), (6, 17, 1, 10)]
    assert [h.read(c, "_RTE-CONTROL.STATE") for c in (dialog, delete, cancel)] == [1, 3, 11]
    # The dialog lies just below its buttons.
    assert [h.read(c, "_RTE-CONTROL.Z") for c in (dialog, delete, cancel)] == [254, 255, 255]
    assert h.span(dialog, "LABEL") == TITLE
    assert h.span(dialog, "CONTENT") == DLG1.pack(
        0x31474C44, 1, 0, 7, 3, len(MESSAGE), 2, 0, 6, 1, 2, 2, 26, 2) + MESSAGE
    assert h.read(dialog, "_RTE-CONTROL.CONTENT-UTF8") == len(MESSAGE)
    assert (h.span(delete, "LABEL"), h.span(delete, "CONTENT")) == (
        b"Delete", struct.pack("<IHH", 0x314E5442, 1, 4))
    assert (h.span(cancel, "LABEL"), h.span(cancel, "CONTENT")) == (
        b"Cancel", struct.pack("<IHH", 0x314E5442, 1, 3))
    # Attachment, source, index, subkey, control ID, lifecycle and scope.
    assert [h.correlation(i) for i in range(3)] == [
        (11, SOURCE, i, KEY, 100 + i, 1, KEY) for i in range(3)]
    claim = struct.unpack("<10Q", h.runtime.memory.read_bytes(h.get("CLAIMS-A"), 80))
    assert claim == (11, 9, SOURCE, 0, KEY, 254, 0, 1, 8, 31)
    h.guards()


def test_a_button_carries_the_text_of_the_key_that_chooses_it(h):
    h.setup(buttons=((b"Delete", (6, 4, 1, 10), 4, 3, b"F9"), (b"Cancel", (6, 16, 1, 10), 3, 7)))
    assert h.build() == (0,)
    assert h.fixed()
    assert h.get("DIALOG-UTF8") == len(TITLE) + len(MESSAGE) + 12 + 2
    assert h.span(h.control(1), "SHORTCUT") == b"F9"
    assert h.read(h.control(2), "_RTE-CONTROL.SHORTCUT-U") == 0
    bank = h.pack()
    h.activate(bank)
    assert h.results("RTHP-CONTROL-TARGET@", 1, 2, 101, h.constant("RTE-INTENT-ACTIVATE"),
                     h.producer) == (6, 5, 29, MASK64)


def test_a_button_takes_a_press_at_its_first_cell_and_the_dialog_only_the_wheel(h):
    h.setup()
    assert h.build() == (0,)
    bank = h.pack()
    h.activate(bank)
    activate = h.constant("RTE-INTENT-ACTIVATE")
    assert h.results("RTHP-CONTROL-TARGET@", 1, 2, 101, activate, h.producer) == (
        6, 5, 29, MASK64)
    assert h.results("RTHP-CONTROL-TARGET@", 1, 2, 102, activate, h.producer) == (
        6, 17, 29, MASK64)
    assert h.results("RTHP-CONTROL-TARGET@", 1, 2, 100, activate, h.producer) == (0, 0, 0, 0)
    assert h.results("RTHP-CONTROL-TARGET@", 1, 2, 101,
                     h.constant("RTE-INTENT-ADJUST"), h.producer) == (0, 0, 0, 0)
    assert h.results("RTHP-CONTROL-TARGET@", 1, 3, 101, activate, h.producer) == (0, 0, 0, 0)
    # A wheel over the dialog scrolls it from its root's first cell; a
    # button takes none.
    scroll = h.constant("RTE-INTENT-SCROLL")
    assert h.results("RTHP-CONTROL-TARGET@", 1, 2, 100, scroll, h.producer) == (
        0, 1, 29, MASK64)
    assert h.results("RTHP-CONTROL-TARGET@", 1, 2, 101, scroll, h.producer) == (0, 0, 0, 0)


def test_hidden_or_disabled_buttons_show_no_target_and_keep_their_index(h):
    h.setup(buttons=((b"Delete", (6, 4, 1, 10), 4, 1), (b"Cancel", (6, 16, 1, 10), 3, 0)))
    assert h.build() == (0,)
    assert h.fixed()
    assert (h.get("CONTROL-COUNT"), h.get("DIALOG-CONTROLS")) == (2, 2)
    assert h.correlation(1)[2] == 1
    bank = h.pack()
    h.activate(bank)
    assert h.results("RTHP-CONTROL-TARGET@", 1, 2, 101, h.constant("RTE-INTENT-ACTIVATE"),
                     h.producer) == (0, 0, 0, 0)
    h.setup(buttons=((b"Delete", (6, 4, 1, 10), 4, 0), (b"Cancel", (6, 16, 1, 10), 3, 7)))
    assert h.build() == (0,)
    assert h.correlation(1)[2] == 2
    assert h.span(h.control(1), "LABEL") == b"Cancel"


def test_a_dialog_without_a_title_has_no_label(h):
    h.setup(title=b"")
    assert h.build() == (0,)
    assert h.fixed()
    assert h.read(h.control(0), "_RTE-CONTROL.LABEL-U") == 0
    assert h.read(h.control(0), "_RTE-CONTROL.LABEL-A") == 0
    assert h.get("DIALOG-UTF8") == len(MESSAGE) + 12


@pytest.mark.parametrize("kwargs", ({"row": 1}, {"col": 3}, {"document": (0, 0, 8, 30)},
                                    {"document": (1, 0, 7, 32)}))
def test_a_dialog_off_its_document_or_the_screen_stays_cell(h, kwargs):
    h.setup(**kwargs)
    assert h.build() == (0,)
    assert h.get("CONTROL-COUNT") == h.get("DIALOG-CONTROLS") == h.get("CLAIMS-USED") == 0
    assert h.get("SOURCE-TEXT-USED") == 0
    assert h.variable("_RTHP-W-GLYPH-FIRST") == 100
    assert h.fixed()


def test_a_dialog_widget_lies_above_its_own_documents_roots(h):
    # A root of the dialog's own document, at depth 3, beneath the dialog at
    # 254: the dialog widget is the document's overlay, in the layer above.
    h.setup()
    prefix = struct.pack("<10Q", 11, 9, 1, 4, 23, 3, 3, 2, 4, 22)
    h.runtime.memory.write_bytes(h.get("CLAIMS-A"), prefix)
    h.field(h.producer, "_RTHP.CLAIMS-USED", 80)
    assert h.results("_RTHP-W-BUILD-OPTIONAL-DIALOGS") == (0,)
    assert h.get("DIALOG-COUNT") == 1
    assert h.get("DIALOG-CONTROLS") == h.get("CONTROL-COUNT") == 3
    assert h.get("CLAIMS-USED") == 160
    assert h.runtime.memory.read_bytes(h.get("CLAIMS-A"), 80) == prefix
    assert h.get("DIALOG-REFUSED") == 0


@pytest.mark.parametrize("claim", (
    (12, 9, 1, 4, 23, 3, 3, 2, 4, 22),    # another document's root
    (11, 9, 1, 4, 23, 254, 3, 2, 4, 22),  # its own document's root, as high as the dialog
    (11, 9, 2, 0, 23, 3, 3, 2, 4, 22),    # its own document's prompt, another overlay
))
def test_a_dialog_over_anything_else_leaves_the_draw_cell(h, claim):
    h.setup()
    prefix = struct.pack("<10Q", *claim)
    h.runtime.memory.write_bytes(h.get("CLAIMS-A"), prefix)
    h.field(h.producer, "_RTHP.CLAIMS-USED", 80)
    assert h.results("_RTHP-W-BUILD-OPTIONAL-DIALOGS") == (h.constant("RTE-S-UNAVAILABLE"),)
    assert h.get("DIALOG-CONTROLS") == h.get("CONTROL-COUNT") == 0
    assert h.get("CLAIMS-USED") == 80
    assert h.runtime.memory.read_bytes(h.get("CLAIMS-A"), 80) == prefix
    assert h.get("DIALOG-REFUSED") == MASK64


def _beneath_the_dialog(h, *, overlay=(0, 1, 8, 30), root=(3, 2, 4, 22)):
    """A root of the dialog's own document at depth 3, and the directory's
    word that the document's roots may lie beneath its overlay's cells."""

    for name, n in zip(("ROW", "COL", "HEIGHT", "WIDTH"), overlay):
        h.runtime.memory.write64(h.dir + h.offset("_RUHA-D.OV-" + name), n)
    prefix = struct.pack("<10Q", 11, 9, 1, 4, 23, 3, *root)
    h.runtime.memory.write_bytes(h.get("CLAIMS-A"), prefix)
    h.field(h.producer, "_RTHP.CLAIMS-USED", 80)


def test_roots_beneath_a_dialog_are_covered_while_the_dialog_is_in_the_candidate(h):
    h.setup()
    _beneath_the_dialog(h)
    assert h.results("_RTHP-W-BUILD-OPTIONAL-DIALOGS") == (0,)
    assert h.get("DIALOG-COUNT") == 1
    assert h.results("_RTHP-LAYERS-COVERED?", h.producer) == (MASK64,)


def test_roots_beneath_a_refused_dialog_cannot_be_shown_rich(h):
    # The lane refuses the dialog for space after the root beneath it was
    # admitted, so the root would claim cells where CELL shows the dialog.
    h.setup()
    _beneath_the_dialog(h)
    h.field(h.producer, "_RTHP.SOURCE-TEXT-U", 40)
    assert h.results("_RTHP-W-BUILD-OPTIONAL-DIALOGS") == (0,)
    assert h.get("DIALOG-REFUSED") == MASK64
    assert h.results("_RTHP-LAYERS-COVERED?", h.producer) == (0,)


@pytest.mark.parametrize("kwargs", (
    {"overlay": (0, 0, 0, 0)},          # no overlay the roots may lie beneath
    {"root": (0, 0, 0, 0)},             # no root beneath it
))
def test_a_refused_dialog_with_nothing_beneath_it_leaves_the_draw_rich(h, kwargs):
    h.setup()
    _beneath_the_dialog(h, **kwargs)
    h.field(h.producer, "_RTHP.SOURCE-TEXT-U", 40)
    assert h.results("_RTHP-W-BUILD-OPTIONAL-DIALOGS") == (0,)
    assert h.results("_RTHP-LAYERS-COVERED?", h.producer) == (MASK64,)


def test_local_dialog_capacity_rolls_back_only_the_owned_suffix(h):
    h.setup()
    prefix = struct.pack("<10Q", 11, 9, 1, 4, 23, 3, 0, 0, 0, 0)
    h.runtime.memory.write_bytes(h.get("CLAIMS-A"), prefix)
    h.field(h.producer, "_RTHP.CLAIMS-USED", 80)
    h.field(h.producer, "_RTHP.SOURCE-TEXT-U", 40)
    assert h.results("_RTHP-W-BUILD-OPTIONAL-DIALOGS") == (0,)
    assert h.get("DIALOG-CONTROLS") == h.get("CONTROL-COUNT") == h.get("SOURCE-TEXT-USED") == 0
    assert h.get("CLAIMS-USED") == 80
    assert h.runtime.memory.read_bytes(h.get("CLAIMS-A"), 80) == prefix
    assert h.get("DIALOG-REFUSED") == MASK64
    # A refused lane builds nothing until the next draw copies its source.
    h.field(h.producer, "_RTHP.SOURCE-TEXT-U", 4096)
    assert h.build() == (0,)
    assert h.get("DIALOG-CONTROLS") == 0
    h.guards()


@pytest.mark.parametrize("mutation", ("revision", "key", "size"))
def test_a_dialog_slice_that_is_not_one_frozen_dialog_is_invalid(h, mutation):
    h.setup()
    if mutation == "revision":
        h.runtime.memory.write64(h.get("DIALOG-NATIVE-A") + 24, 0)
    elif mutation == "key":
        h.runtime.memory.write64(h.get("DIALOG-DESCRIPTORS-A") + 8, KEY + 1)
    else:
        h.runtime.memory.write64(h.get("DIALOG-DESCRIPTORS-A") + 48, 31)
    assert h.results("_RTHP-W-BUILD-OPTIONAL-DIALOGS") == (h.constant("RTE-S-INVALID"),)
    assert h.get("DIALOG-CONTROLS") == 0


@pytest.mark.parametrize("feature,short", ((False, False), (True, False), (True, True)))
def test_dialog_source_copy_omits_an_unnegotiated_or_unaffordable_lane(h, feature, short):
    h.setup()
    snapshot = h.allocate(bytes(h.constant("RUHA-SNAPSHOT-SIZE")))
    descriptors = h.allocate(h.descriptor)
    native = h.allocate(h.model)
    directory = h.allocate(h.runtime.memory.read_bytes(h.dir, h.constant("RUHA-DOCUMENT-SIZE")))
    for offset, value in ((208, descriptors), (216, DESCRIPTOR), (224, native), (232, len(h.model))):
        h.runtime.memory.write64(snapshot + offset, value)
    h.variable("_RTHP-W-SNAP", snapshot)
    h.variable("_RTHP-W-DIRECTORY-A", directory)
    h.field(h.producer + h.offset("_RTHP.LIMITS"), "_RTE-L.FEATURES",
            h.constant("RTE-F-DIALOGS") if feature else 0)
    if short:
        h.field(h.producer, "_RTHP.DIALOG-NATIVE-U", len(h.model) - 8)
    h.runtime.memory.write_bytes(h.get("DIALOG-NATIVE-A"), bytes(len(h.model)))
    assert h.call("_RTHP-COPY-DIALOG-SOURCE?")
    copied = feature and not short
    assert h.get("DIALOG-DESCRIPTORS-USED") == DESCRIPTOR * copied
    assert h.get("DIALOG-NATIVE-USED") == len(h.model) * copied
    entry = h.runtime.memory.read_bytes(h.dir + 240, 32)
    assert entry == (struct.pack("<4Q", 0, DESCRIPTOR, 0, len(h.model)) if copied else bytes(32))
    assert h.build() == (0,)
    assert h.get("DIALOG-COUNT") == int(copied)
    h.guards()


def test_a_dialog_extent_past_its_bank_is_invalid_without_the_feature(h):
    h.setup()
    snapshot = h.allocate(bytes(h.constant("RUHA-SNAPSHOT-SIZE")))
    descriptors = h.allocate(h.descriptor)
    native = h.allocate(h.model)
    directory = h.allocate(h.runtime.memory.read_bytes(h.dir, h.constant("RUHA-DOCUMENT-SIZE")))
    for offset, value in ((208, descriptors), (216, DESCRIPTOR), (224, native), (232, len(h.model))):
        h.runtime.memory.write64(snapshot + offset, value)
    h.runtime.memory.write64(directory + 264, len(h.model) + 8)
    h.variable("_RTHP-W-SNAP", snapshot)
    h.variable("_RTHP-W-DIRECTORY-A", directory)
    assert not h.call("_RTHP-COPY-DIALOG-SOURCE?")
    assert h.get("DIALOG-NATIVE-USED") == 0


@pytest.mark.parametrize("mutation", ("claim", "id", "text", "source", "count", "outside",
                                      "kind", "utf8"))
def test_the_dialog_audit_rejects_a_corrupted_candidate(h, mutation):
    h.setup()
    assert h.build() == (0,)
    assert h.fixed()
    dialog, delete = h.control(0), h.control(1)
    if mutation == "claim":
        h.runtime.memory.write64(h.get("CLAIMS-A") + 56, 2)
    elif mutation == "id":
        h.runtime.memory.write64(delete + h.offset("_RTE-CONTROL.ID"), 102)
    elif mutation == "text":
        h.runtime.memory.write64(delete + h.offset("_RTE-CONTROL.LABEL-A"), h.get("SOURCE-TEXT-A"))
    elif mutation == "source":
        h.runtime.memory.write64(h.get("CORR-A") + 56 + 8, 2)
    elif mutation == "count":
        h.field(h.producer, "_RTHP.DIALOG-COUNT", 2)
    elif mutation == "outside":
        h.runtime.memory.write64(delete + h.offset("_RTE-CONTROL.ROW"), 8)
    elif mutation == "kind":
        h.runtime.memory.write64(dialog + h.offset("_RTE-CONTROL.KIND"),
                                 h.constant("RTE-CONTROL-BUTTON"))
    else:
        h.runtime.memory.write64(dialog + h.offset("_RTE-CONTROL.CONTENT-UTF8"), 1)
    assert not h.fixed()


# A DELTA keeps a dialog's title and geometry; its DLG1 content may change
# only with a strictly newer revision, one CONTROL-REPLACE.  A button may
# change its label, roles and state.
DIALOG_DELTA_MUTATIONS = {
    None: (0, True, 0),
    "newer": (0, True, 1),
    "content": (0, False, 0),
    "newer-content": (0, True, 1),
    "title": (0, False, 0),
    "button-label": (1, True, 1),
    "button-roles": (1, True, 1),
    "button-state": (1, True, 1),
    "button-slot": (1, False, 0),
}


@pytest.mark.parametrize("mutation", tuple(DIALOG_DELTA_MUTATIONS))
def test_dialog_delta_keeps_title_and_takes_only_newer_content(h, mutation):
    h.setup()
    assert h.build() == (0,)
    active = h.pack()
    assert h.call("_RTHP-STRIP-DIALOGS?", h.producer)
    h.field(h.producer, "_RTHP.FIRST-OBJECT", 200)
    assert h.build() == (0,)
    dialog, delete = h.control(0), h.control(1)
    content = h.read(dialog, "_RTE-CONTROL.CONTENT-A")
    if mutation in ("newer", "newer-content"):
        h.runtime.memory.write64(content + 8, 8)
    if mutation in ("content", "newer-content"):
        h.runtime.memory.write_bytes(content + 56, b"P")
    elif mutation == "title":
        h.runtime.memory.write_bytes(h.read(dialog, "_RTE-CONTROL.LABEL-A"), b"Erase!")
    elif mutation == "button-label":
        h.runtime.memory.write_bytes(h.read(delete, "_RTE-CONTROL.LABEL-A"), b"Remove")
    elif mutation == "button-roles":
        h.runtime.memory.write_bytes(h.read(delete, "_RTE-CONTROL.CONTENT-A") + 6,
                                     struct.pack("<H", 0))
    elif mutation == "button-state":
        h.runtime.memory.write64(delete + h.offset("_RTE-CONTROL.STATE"), 1)
    elif mutation == "button-slot":
        h.runtime.memory.write64(delete + h.offset("_RTE-CONTROL.COL"), 6)
    pending = h.pack(index=1)
    for name, value in (("P", h.producer), ("ACTIVE", active), ("PENDING", pending),
                        ("PENDING-FIRST", 200)):
        h.variable("_RTHP-D-" + name, value)
    index, compatible, ops = DIALOG_DELTA_MUTATIONS[mutation]
    order = h.get("ORDER2-A")
    for i in range(3):
        h.runtime.memory.write64(order + 8 * i, i + 1)
    assert h.call("_RTHP-D-CONTROL-COMPATIBLE?", index) == compatible
    assert h.variable("_RTHP-D-OPS") == ops
    h.guards()


def test_a_new_dialog_has_no_delta_match(h):
    h.setup()
    assert h.build() == (0,)
    active = h.pack()
    assert h.call("_RTHP-STRIP-DIALOGS?", h.producer)
    h.field(h.producer, "_RTHP.FIRST-OBJECT", 200)
    assert h.build() == (0,)
    pending = h.pack(index=1)
    for name, value in (("P", h.producer), ("ACTIVE", active), ("PENDING", pending),
                        ("PENDING-FIRST", 200)):
        h.variable("_RTHP-D-" + name, value)
    h.runtime.memory.write_bytes(h.get("ORDER2-A"), bytes(24))
    for index in range(3):
        assert not h.call("_RTHP-D-CONTROL-COMPATIBLE?", index)


def test_an_unchanged_dialog_clone_rebases_its_owned_spans(h):
    h.setup()
    assert h.build() == (0,)
    active = h.pack()
    h.activate(active)
    for name, value in (("P", h.producer), ("ACTIVE", active), ("DRAW", 13),
                        ("SOURCE-GEN", 10), ("CONTENT-EPOCH", 29)):
        h.variable("_RTHP-U-" + name, value)
    assert h.call("_RTHP-U-CLONE?")
    pending = h.variable("_RTHP-U-PENDING")
    assert pending != active
    for index in range(3):
        old, = h.results("_RTHP-D-CONTROL-AT", index, active)
        new, = h.results("_RTHP-D-CONTROL-AT", index, pending)
        for name in ("LABEL", "CONTENT"):
            before = h.read(old, f"_RTE-CONTROL.{name}-A")
            after = h.read(new, f"_RTE-CONTROL.{name}-A")
            size = h.read(old, f"_RTE-CONTROL.{name}-U")
            assert before != after
            assert h.runtime.memory.read_bytes(before, size) == h.runtime.memory.read_bytes(
                after, size)
    assert h.read(pending, "_RTHP-TB.DIALOG-CONTROLS") == 3
    h.guards()


def test_dialog_storage_admits_no_dialog_bank_and_rejects_a_partial_header(h):
    assert h.results("RTHP-STORAGE-BYTES", 1, 1, 64, 256, 256, 512, 0, 0, 0, 32, 8)[0] > 0
    assert h.results("RTHP-STORAGE-BYTES", 1, 1, 64, 256, 256, 512, 0, 164, 0, 32, 8) == (0,)


def _element(h, *, contents=1, z=255):
    """Make the harness's dialog a dialog element whose CONTENTS roots paint
    at Z."""
    h.runtime.memory.write_bytes(h.get("DIALOG-DESCRIPTORS-A"), struct.pack(
        "<10Q", 4, KEY, 0, h.row, h.col, 8, 30, len(h.model), z, contents))


def _claim(h, *, attachment=11, z=255, rect=(2, 3, 5, 20)):
    """An earlier family's claim, before the dialog lane: attachment, source
    generation, source, index, subkey, z, then rows and columns."""
    at = h.get("CLAIMS-A") + h.get("CLAIMS-USED")
    h.runtime.memory.write_bytes(at, struct.pack("<10Q", attachment, 9, 1, 5, 1, z, *rect))
    h.field(h.producer, "_RTHP.CLAIMS-USED", h.get("CLAIMS-USED") + 80)


def test_a_dialog_elements_contents_are_admitted_above_it(h):
    """The roots of its document inside it, above it, are its contents: they
    may lie on its claim, and the dialog takes the depth below them."""
    h.setup()
    _element(h)
    _claim(h)
    assert h.build() == (0,)
    assert h.get("DIALOG-COUNT") == 1
    dialog, delete, cancel = (h.control(i) for i in range(3))
    assert [h.read(c, "_RTE-CONTROL.Z") for c in (dialog, delete, cancel)] == [254, 255, 255]
    assert [h.correlation(i)[1] for i in range(3)] == [4, 4, 4]
    claim = struct.unpack("<10Q", h.runtime.memory.read_bytes(h.get("CLAIMS-A") + 80, 80))
    assert claim == (11, 9, 4, 0, KEY, 254, 0, 1, 8, 31)
    assert h.fixed()
    h.guards()


def test_a_dialog_element_whose_contents_are_not_all_there_stays_painted(h):
    """A content left out would be painted text beneath the dialog's claim,
    so the dialog is left out too, and nothing is refused."""
    h.setup()
    _element(h, contents=2)
    _claim(h)
    assert h.build() == (0,)
    assert (h.get("DIALOG-COUNT"), h.get("DIALOG-CONTROLS")) == (0, 0)
    h.guards()


@pytest.mark.parametrize("attachment,z,rect", (
    (12, 255, (2, 3, 5, 20)),     # another document's root
    (11, 254, (2, 3, 5, 20)),     # not above it
    (11, 255, (2, 3, 9, 20)),     # not wholly inside it
))
def test_a_claim_that_is_not_its_content_still_refuses_the_dialog(h, attachment, z, rect):
    h.setup()
    _element(h)
    _claim(h, attachment=attachment, z=z, rect=rect)
    assert h.build() == (h.constant("RTE-S-UNAVAILABLE"),)
    h.guards()
