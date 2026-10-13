"""Pictures through the screen producer: IMAGE statics and the lane's jobs.

The real build, audit, comparison and lane words run on both executors.
The terminal's jobs, the owner's quotas, the memory source and the pull of
a picture's pixels are fixture seams; their own behaviour belongs to their
own units (test_rich_resource_upload.py, test_uidl_picture_snapshot.py).
No display or Desktop is started.
"""

import re
import struct

import pytest

from test_rich_glyph_growth import MASK64, PRODUCER
from test_rich_status_producer import StatusHarness
from test_rich_terminal_control_map import MegaForthRuntime, ROOT, _definitions


SNAPSHOT = ROOT / "akashic/tui/uidl-picture-snapshot.f"
ADAPTER = ROOT / "akashic/tui/rich-terminal/uidl-hybrid-adapter.f"
PICTURE = ROOT / "akashic/media/picture.f"
# The neutral static record's size, from the engine that defines it.
STATIC = int(re.search(r"(?m)^(\d+) CONSTANT RTE-STATIC-SIZE$",
                       (ROOT / "akashic/tui/rich-terminal/engine.f").read_text())[1])
COPY_BYTES = 16 * 12 * 4
RAW = 1          # PIC-F-RGBA8, and RTE-PICTURE-RGBA8


def descriptor(*, index=5, key=1, row=4, col=2, height=3, width=8, z=4, state=2,
               copy=(16, 12), format=RAW, nbytes=None, document=11, revision=3,
               clip=None, figure=False):
    """A UPICSN descriptor, as a build's capture leaves it: a copy's bytes
    are its pixels', a file's its length.  CLIP is the part shown, as row,
    column, height and width from the rectangle's corner; all of it unless
    given."""
    w, h = copy
    nbytes = w * h * 4 if nbytes is None else nbytes
    clip = (0, 0, height, width) if clip is None else clip
    return struct.pack("<24Q", 1, index, 0, key, row & MASK64, col & MASK64, height, width,
                       z, state, 0, w, h, nbytes, w, h, format, document, revision,
                       *(value & MASK64 for value in clip), MASK64 if figure else 0)


def entry(*, ident=5, copy=(16, 12), state=2, format=RAW, document=11, index=5,
          revision=3, key=1):
    """A resource table entry: ID, size, the decoded bytes the owner holds,
    state, the format it was sent in, and the document, element, revision
    and root key of the picture it is a copy of."""
    w, h = copy
    return struct.pack("<10Q", ident, w, h, w * h * 4, state, format,
                       document, index, revision, key)


# ---------------------------------------------------------------------
#  IMAGE statics
# ---------------------------------------------------------------------

class ImageHarness(StatusHarness):
    def __init__(self, backend):
        super().__init__(backend, extra_words=("_RTHP-D-STATIC-CHANGED?", "_RTHP-L-SHOWN?"))

    def pictures(self, descriptors=(), entries=()):
        bank = self.get("PICTURES-A")
        for index, item in enumerate(descriptors):
            self.runtime.memory.write_bytes(bank + len(item) * index, item)
        self.field(self.producer, "_RTHP.PICTURE-COUNT", len(descriptors))
        if entries:
            table = self.allocate(b"".join(entries))
            self.field(self.producer, "_RTHP.RESOURCES-A", table)
            self.field(self.producer, "_RTHP.RESOURCES-U", sum(map(len, entries)))

    def admit_images(self):
        count = self.get("STATIC-COUNT")
        items = self.get("STATICS-A")
        images = sum(self.runtime.memory.read64(items + STATIC * i + 24) == 2
                     for i in range(count))
        text = self.get("STATIC-TEXT-USED")
        aligned = (text + 7) & -8
        admission = self.producer + self.offset("_RTHP.ADMISSION")
        for name, value in (("STATIC-COUNT", count), ("STATIC-TEXT", text),
                            ("STATIC-ALIGNED", aligned), ("STATIC-MAX", text),
                            ("STATIC-LAST", 99 + count if count else 0),
                            ("STATIC-COPY", STATIC * (count - images) + aligned),
                            ("STATIC-OPS", count), ("STATIC-IMAGES", images)):
            self.field(admission, "_RTE-HA." + name, value)
        self.results("_RTHP-WRAP-HYBRID", self.producer)


@pytest.fixture(params=("python", "native"))
def images(request):
    return ImageHarness(request.param)


def test_a_held_picture_becomes_an_image_static_with_its_whole_claim(images):
    h = images
    h.setup(pictures=2)
    h.pictures([descriptor()], [entry()])
    assert h.build() == (0,)
    # The status field keeps its place; the picture follows it.
    assert h.get("STATIC-COUNT") == 2
    assert h.get("STATIC-LAST") == 101
    assert h.variable("_RTHP-W-GLYPH-FIRST") == 102
    item = h.get("STATICS-A") + STATIC
    fields = struct.unpack("<26Q", h.runtime.memory.read_bytes(item, STATIC))
    # Owner, generation, ID, IMAGE, visible, z, region, no parent; rows 4..6
    # and columns 2..9 of the 32 by 8 root; CONTAIN, opaque, over a backdrop;
    # no text; resource 5; no clip, since all of it shows.
    assert fields == (1, 2, 101, 2, MASK64, 4, 7, 0, 4, 2, 3, 8, 8, 32,
                      1, 255, MASK64, 0, 0, 0, 0, 5, 0, 0, 0, 0)
    size = h.constant("RUCL-CLAIM-SIZE")
    claim = h.runtime.memory.read_bytes(h.get("CLAIMS-A") + size, size)
    assert struct.unpack("<10Q", claim[:80]) == (11, 9, 1, 5, 0, 4, 4, 2, 7, 10)
    corr = h.runtime.memory.read_bytes(h.get("STATIC-CORR-A") + 40, 40)
    assert struct.unpack("<5Q", corr) == (11, 5, 0, 1, 0)
    h.admit_images()
    assert h.call("_RTHP-STATICS-FIXED?", h.producer)
    h.guards()


@pytest.mark.parametrize("case", ("uploading", "picture", "size", "pending", "failed",
                                  "document", "off-surface", "claimed", "paint"))
def test_a_picture_the_terminal_cannot_show_stays_cell(images, case):
    h = images
    h.setup(pictures=2)
    changes, held = {}, {}
    if case == "uploading":
        held["state"] = 1
    elif case == "picture":
        # Another picture's copy is no copy of this one.
        held["revision"] = 4
    elif case == "size":
        held.update(copy=(15, 12), revision=4)
    elif case == "pending":
        changes["state"] = 1
        held["revision"] = 4
    elif case == "failed":
        # Only a copy on its way keeps an older one showing.
        changes["state"] = 3
    elif case == "document":
        changes["document"] = 12
    elif case == "off-surface":
        changes["row"] = 6
    elif case == "claimed":
        # Rows 2..4 cross the status field's row 3.
        changes["row"] = 2
    else:
        changes["z"] = 256
    h.pictures([descriptor(**changes)], [entry(**held)])
    assert h.build() == (0,)
    assert h.get("STATIC-COUNT") == 1
    assert h.get("CLAIMS-USED") == h.constant("RUCL-CLAIM-SIZE")
    assert h.variable("_RTHP-W-GLYPH-FIRST") == 101
    h.guards()


@pytest.mark.parametrize("state", ("pending", "ready"))
def test_a_copy_on_its_way_shows_the_newest_held_copy_of_its_picture(images, state):
    """Section 5.4: the terminal resource on screen stays authoritative until
    the copy replacing it is held."""
    h = images
    h.setup(pictures=2)
    h.pictures([descriptor(state=1 if state == "pending" else 2, copy=(20, 15))],
               [entry(ident=5), entry(ident=7, copy=(8, 6)),
                entry(ident=9, revision=4), entry(ident=8, state=1, copy=(20, 15)),
                entry(ident=10, index=6), entry(ident=11, document=12)])
    assert h.build() == (0,)
    assert h.get("STATIC-COUNT") == 2
    # Not another picture's copy, one still uploading, nor another element's
    # or document's: the newest the terminal holds of this picture, at any
    # size.
    assert h.runtime.memory.read64(h.get("STATICS-A") + STATIC + 168) == 7
    h.admit_images()
    assert h.call("_RTHP-STATICS-FIXED?", h.producer)
    h.guards()


def test_a_picture_shows_its_own_copy_once_the_terminal_holds_it(images):
    h = images
    h.setup(pictures=2)
    # A newer copy of the same picture at another size does not stand in
    # for its own.
    h.pictures([descriptor()], [entry(ident=9, copy=(8, 6)), entry(ident=5)])
    assert h.build() == (0,)
    assert h.runtime.memory.read64(h.get("STATICS-A") + STATIC + 168) == 5
    h.guards()


@pytest.mark.parametrize("mutation", ("images", "copy", "claim", "height"))
def test_the_fixed_audit_counts_pictures_apart_from_status_fields(images, mutation):
    h = images
    h.setup(pictures=2)
    h.pictures([descriptor()], [entry()])
    assert h.build() == (0,)
    h.admit_images()
    assert h.call("_RTHP-STATICS-FIXED?", h.producer)
    admission = h.producer + h.offset("_RTHP.ADMISSION")
    if mutation == "images":
        h.field(admission, "_RTE-HA.STATIC-IMAGES", 0)
    elif mutation == "copy":
        # A picture's record is not part of the neutral copy.
        text = h.get("STATIC-TEXT-USED")
        h.field(admission, "_RTE-HA.STATIC-COPY", 2 * STATIC + ((text + 7) & -8))
    elif mutation == "claim":
        h.runtime.memory.write64(h.get("CLAIMS-A") + h.constant("RUCL-CLAIM-SIZE") + 64, 5)
    else:
        h.runtime.memory.write64(h.get("STATICS-A") + STATIC + 80, 5)
    assert not h.call("_RTHP-STATICS-FIXED?", h.producer)


def test_a_new_resource_for_a_picture_is_a_replacement_and_a_move_a_new_frame(images):
    h = images
    h.setup(pictures=2)
    h.pictures([descriptor()], [entry()])
    assert h.build() == (0,)
    bank = h.pack()
    assert h.call("_RTHP-L-SHOWN?", 5, bank)
    assert not h.call("_RTHP-L-SHOWN?", 6, bank)
    assert not h.call("_RTHP-L-SHOWN?", 5, 0)
    other = h.get("TARGET1-A")
    h.runtime.memory.write_bytes(other, h.runtime.memory.read_bytes(bank, h.bank_size))
    h.variable("_RTHP-D-ACTIVE", bank)
    h.variable("_RTHP-D-PENDING", other)
    assert not h.call("_RTHP-D-STATIC-CHANGED?", 1)
    items, = h.results("_RTHP-PACK-STATICS-A", other)
    h.runtime.memory.write64(items + STATIC + 168, 6)
    assert h.call("_RTHP-D-STATIC-CHANGED?", 1)
    assert not h.call("_RTHP-D-STATIC-CHANGED?", 0)
    assert h.call("_RTHP-STATICS-REUSABLE?", bank, other, 0)
    h.runtime.memory.write64(items + STATIC + 64, 3)
    assert not h.call("_RTHP-STATICS-REUSABLE?", bank, other, 0)


def _document_claim(h, *, rows=(0, 7), cols=(0, 32), index=5):
    """The claim the document's root on element INDEX made with the
    controls, before the statics are built: rows and columns, each end
    exclusive."""
    claim = struct.pack("<10Q", 11, 9, 1, index, 0, 4, rows[0], cols[0], rows[1], cols[1])
    h.runtime.memory.write_bytes(h.get("CLAIMS-A"), claim)
    h.field(h.producer, "_RTHP.CLAIMS-USED", len(claim))


@pytest.mark.parametrize("case", ("whole", "above", "foot"))
def test_a_figure_shows_the_part_its_document_shows_inside_the_document_claim(images, case):
    """A figure is an IMAGE of its whole rectangle, clipped to the part its
    document shows, which the document's root already claims: it adds no
    claim of its own."""
    h = images
    h.setup(pictures=2, row=7)
    _document_claim(h)
    place, clip = {
        # Rows 4..6, all of it shown: no clip.
        "whole": (dict(row=4, height=3), (0, 0, 0, 0)),
        # Rows -2..1: its top two rows are above the surface.
        "above": (dict(row=-2, height=4, clip=(2, 0, 2, 8)), (0, 2, 8, 2)),
        # Rows 5..8: the document's foot, at row 7, cuts its last two.
        "foot": (dict(row=5, height=4, clip=(0, 0, 2, 8)), (0, 0, 8, 2)),
    }[case]
    h.pictures([descriptor(key=3, figure=True, **place)], [entry(key=3)])
    assert h.build() == (0,)
    assert h.get("STATIC-COUNT") == 2
    # The document's claim and the status field's.
    assert h.get("CLAIMS-USED") == 2 * h.constant("RUCL-CLAIM-SIZE")
    item = h.get("STATICS-A") + STATIC
    fields = struct.unpack("<26Q", h.runtime.memory.read_bytes(item, STATIC))
    assert fields[8:12] == (place["row"] & MASK64, 2, place["height"], 8)
    # Resource 5, then the clip's column, row, columns and rows.
    assert fields[21:] == (5, *clip)
    corr = h.runtime.memory.read_bytes(h.get("STATIC-CORR-A") + 40, 40)
    assert struct.unpack("<5Q", corr) == (11, 5, 0, 3, 0)
    h.admit_images()
    assert h.call("_RTHP-STATICS-FIXED?", h.producer)
    h.guards()


@pytest.mark.parametrize("case", ("no-document", "other-element", "past-the-foot", "status"))
def test_a_figure_its_document_claim_does_not_hold_stays_cell(images, case):
    h = images
    h.setup(pictures=2, row=7)
    place = dict(row=4, height=3)
    if case == "other-element":
        _document_claim(h, index=6)
    elif case == "past-the-foot":
        # Rows 4..6 shown whole cross the document's foot at row 5.
        _document_claim(h, rows=(0, 5))
    elif case == "status":
        # Rows 5..7 shown whole reach the status field's row 7.
        _document_claim(h)
        place = dict(row=5, height=3)
    h.pictures([descriptor(key=3, figure=True, **place)], [entry(key=3)])
    assert h.build() == (0,)
    assert h.get("STATIC-COUNT") == 1
    h.guards()


def test_an_element_picture_partly_hidden_claims_only_the_part_shown(images):
    h = images
    h.setup(pictures=2)
    # Rows -1..2, its top row hidden: rows 0..2 show.
    h.pictures([descriptor(row=-1, height=4, clip=(1, 0, 3, 8))], [entry()])
    assert h.build() == (0,)
    assert h.get("STATIC-COUNT") == 2
    item = h.get("STATICS-A") + STATIC
    fields = struct.unpack("<26Q", h.runtime.memory.read_bytes(item, STATIC))
    assert fields[8:12] == (MASK64, 2, 4, 8)
    assert fields[21:] == (5, 0, 1, 8, 3)
    size = h.constant("RUCL-CLAIM-SIZE")
    claim = h.runtime.memory.read_bytes(h.get("CLAIMS-A") + size, size)
    assert struct.unpack("<4Q", claim[48:80]) == (0, 2, 3, 10)
    h.admit_images()
    assert h.call("_RTHP-STATICS-FIXED?", h.producer)
    h.guards()


@pytest.mark.parametrize("mutation", (None, "document", "clip"))
def test_the_fixed_audit_finds_a_figure_inside_its_document_claim(images, mutation):
    h = images
    h.setup(pictures=2, row=7)
    _document_claim(h)
    h.pictures([descriptor(key=3, figure=True, row=-2, height=4, clip=(2, 0, 2, 8))],
               [entry(key=3)])
    assert h.build() == (0,)
    h.admit_images()
    if mutation == "document":
        # The document's claim no longer holds the figure's rows.
        h.runtime.memory.write64(h.get("CLAIMS-A") + 48, 1)
    elif mutation == "clip":
        # Shown from row -1, off the surface.
        h.runtime.memory.write64(h.get("STATICS-A") + STATIC + 184, 1)
    assert bool(h.call("_RTHP-STATICS-FIXED?", h.producer)) is (mutation is None)


def test_a_picture_shown_through_another_clip_is_a_new_frame(images):
    h = images
    h.setup(pictures=2)
    h.pictures([descriptor(row=-1, height=4, clip=(1, 0, 3, 8))], [entry()])
    assert h.build() == (0,)
    bank = h.pack()
    other = h.get("TARGET1-A")
    h.runtime.memory.write_bytes(other, h.runtime.memory.read_bytes(bank, h.bank_size))
    assert h.call("_RTHP-STATICS-REUSABLE?", bank, other, 0)
    items, = h.results("_RTHP-PACK-STATICS-A", other)
    h.runtime.memory.write64(items + STATIC + 200, 2)
    assert not h.call("_RTHP-STATICS-REUSABLE?", bank, other, 0)


# ---------------------------------------------------------------------
#  The lane
# ---------------------------------------------------------------------

_SEAMS = {
    "RTHP-VALID?": ": RTHP-VALID? DROP LP-VALID @ ;",
    "_RTHP-LANE-ON?": ": _RTHP-LANE-ON? DROP LP-ON @ ;",
    "SCR-DRAW-GENERATION@": ": SCR-DRAW-GENERATION@ LP-DRAW @ ;",
    "_RTHP-HELD@": (
        ": _RTHP-HELD@ DUP _RTHP.HELD RTE-QUOTA-SIZE 0 FILL "
        "LP-HELD-RESOURCES @ OVER _RTHP.HELD 8 + ! "
        "LP-HELD-BYTES @ SWAP _RTHP.HELD 32 + ! -1 ;"
    ),
    "_RTHP-Q-LIMIT": ": _RTHP-Q-LIMIT 2DROP LP-LIMIT @ ;",
    "_RTHP-RESIZE": (
        ": _RTHP-RESIZE 1 LP-RESIZES +! DUP _RTHP.ASK 8 + @ LP-ASKED-RESOURCES ! "
        "_RTHP.ASK 32 + @ LP-ASKED-BYTES ! LP-RESIZE-STATUS @ ;"
    ),
    "_RTHP-G-SEPARATE?": ": _RTHP-G-SEPARATE? DROP 2DROP -1 ;",
    "MSRC-ALLOC": (
        ": MSRC-ALLOC DROP LP-REFUSE @ IF DROP 0 EXIT THEN "
        "LP-HEAP-NEXT @ TUCK + 7 + -8 AND LP-HEAP-NEXT ! 1 LP-ALLOCS +! ;"
    ),
    "MSRC-FREE": ": MSRC-FREE DROP LP-FREED +! DROP 1 LP-FREES +! ;",
    "RTE-JOB@": ": RTE-JOB@ DROP LP-STATE @ LP-KIND @ LP-ITEM @ LP-RESULT @ RTE-S-OK ;",
    "RTE-JOB-CLEAR": ": RTE-JOB-CLEAR DROP 1 LP-CLEARS +! RTE-S-OK ;",
    "RTE-PIXELS-ASK": (
        ": RTE-PIXELS-ASK DROP LP-ASK-ROWS ! LP-ASK-COLS ! 2DROP "
        "1 LP-ASKS +! LP-ASK-STATUS @ ;"
    ),
    "RTE-PIXELS@": ": RTE-PIXELS@ DROP 7 LP-PIXEL-W @ LP-PIXEL-H @ RTE-S-OK ;",
    "RTE-RESOURCE-UPLOAD": (
        ": RTE-RESOURCE-UPLOAD DROP LP-UP-U ! LP-UP-H ! LP-UP-W ! "
        "LP-UP-FORMAT ! LP-UP-ID ! 2DROP 1 LP-UPLOADS +! LP-UPLOAD-STATUS @ ;"
    ),
    "RTE-RESOURCE-WANTS@": (
        ": RTE-RESOURCE-WANTS@ DROP LP-WANT-OFFSET @ LP-WANT-MOST @ "
        "LP-WANT-STATUS @ ;"
    ),
    "RTE-RESOURCE-FEED": (
        ": RTE-RESOURCE-FEED DROP LP-FEED-U ! LP-FEED-A ! 1 LP-FEEDS +! "
        "LP-FEED-STATUS @ ;"
    ),
    "RTE-RESOURCE-DROP": (
        ": RTE-RESOURCE-DROP DROP LP-DROP-BYTES ! LP-DROP-ID ! 2DROP "
        "1 LP-DROPS +! LP-DROP-STATUS @ ;"
    ),
    "RUHA-PICTURE-PULL": (
        ": RUHA-PICTURE-PULL DROP LP-PULL-U ! LP-PULL-A ! LP-PULL-OFFSET ! "
        "LP-PULL-D ! 1 LP-PULLS +! LP-PULL-STATUS @ ;"
    ),
    "RUHA-PICTURE-FAIL": (
        ": RUHA-PICTURE-FAIL DROP LP-FAIL-REASON ! LP-FAIL-REVISION ! "
        "LP-FAIL-KEY ! LP-FAIL-INDEX ! LP-FAIL-DOCUMENT ! 1 LP-FAILS +! RUHA-S-OK ;"
    ),
    "RUHA-PICTURES@": (
        ": RUHA-PICTURES@ DROP LP-CAP-DRAW ! LP-CAP-ASK ! LP-CAP-U ! LP-CAP-A ! "
        "1 LP-CAPTURES +! LP-CAP-COUNT @ LP-CAP-STATUS @ ;"
    ),
    "RTE-RESOURCE-CANCEL": ": RTE-RESOURCE-CANCEL DROP 1 LP-CANCELS +! LP-CANCEL-STATUS @ ;",
    "RTE-OWNER-STATE@": ": RTE-OWNER-STATE@ DROP 2DROP LP-OWNER-STATE @ RTE-S-OK ;",
    "RTE-LIMITS-IMAGE-WIDTH@": ": RTE-LIMITS-IMAGE-WIDTH@ DROP LP-MAX-W @ ;",
    "RTE-LIMITS-IMAGE-HEIGHT@": ": RTE-LIMITS-IMAGE-HEIGHT@ DROP LP-MAX-H @ ;",
    "RTE-LIMITS-RESOURCE-BYTES@": ": RTE-LIMITS-RESOURCE-BYTES@ DROP LP-MAX-BYTES @ ;",
    "RTE-LIMITS-IMAGE-FORMATS@": ": RTE-LIMITS-IMAGE-FORMATS@ DROP LP-FORMATS @ ;",
    "UPICSN-RELEASE-ALL": ": UPICSN-RELEASE-ALL 1 LP-RELEASES +! ;",
}
_VARIABLES = (
    "LP-VALID", "LP-ON", "LP-DRAW", "LP-HELD-RESOURCES", "LP-HELD-BYTES", "LP-LIMIT",
    "LP-RESIZES", "LP-ASKED-RESOURCES", "LP-ASKED-BYTES", "LP-RESIZE-STATUS",
    "LP-REFUSE", "LP-HEAP-NEXT", "LP-ALLOCS", "LP-FREES", "LP-FREED",
    "LP-STATE", "LP-KIND", "LP-ITEM", "LP-RESULT", "LP-CLEARS",
    "LP-ASKS", "LP-ASK-COLS", "LP-ASK-ROWS", "LP-ASK-STATUS", "LP-PIXEL-W", "LP-PIXEL-H",
    "LP-UPLOADS", "LP-UP-ID", "LP-UP-W", "LP-UP-H", "LP-UP-U", "LP-UP-FORMAT",
    "LP-UPLOAD-STATUS", "LP-DROPS", "LP-DROP-ID", "LP-DROP-BYTES", "LP-DROP-STATUS",
    "LP-PULLS", "LP-PULL-D", "LP-PULL-OFFSET", "LP-PULL-A", "LP-PULL-U", "LP-PULL-STATUS",
    "LP-WANT-OFFSET", "LP-WANT-MOST", "LP-WANT-STATUS",
    "LP-FEEDS", "LP-FEED-A", "LP-FEED-U", "LP-FEED-STATUS",
    "LP-FAILS", "LP-FAIL-DOCUMENT", "LP-FAIL-INDEX", "LP-FAIL-KEY", "LP-FAIL-REVISION",
    "LP-FAIL-REASON",
    "LP-CANCELS", "LP-CANCEL-STATUS", "LP-OWNER-STATE", "LP-MAX-W", "LP-MAX-H", "LP-MAX-BYTES",
    "LP-FORMATS", "LP-RELEASES",
    "LP-CAPTURES", "LP-CAP-A", "LP-CAP-U", "LP-CAP-ASK", "LP-CAP-DRAW", "LP-CAP-COUNT",
    "LP-CAP-STATUS", "LP-BUILDS",
)
_LANE_ROOTS = ("_RTHP-LANE-STEP", "_RTHP-PACK-STATICS-A", "_RTHP-STEP-RESIZING",
               "_RTHP-PICTURE-LIMITS!", "_RTHP-W-PICTURES", "_RTHP-FAULT-RESULT",
               "RTHP-FINI")


class LaneHarness:
    def __init__(self, backend, *, roots=_LANE_ROOTS, seams=None):
        self.runtime = MegaForthRuntime(execution_backend=backend)
        self.definitions = _definitions(PRODUCER.read_text() + "\n" + SNAPSHOT.read_text())
        for path in (ROOT / "akashic/tui/screen.f", ADAPTER, PICTURE,
                     PRODUCER.parent / "residual-glyph-planner.f",
                     PRODUCER.parent / "uidl-claim-ledger.f"):
            for match in re.finditer(r"(?m)^\s*(\d+)\s+CONSTANT\s+(\S+)", path.read_text()):
                self.definitions.setdefault(match[2], match[0])
        for name in _VARIABLES:
            self.definitions[name] = f"VARIABLE {name}"
        self.definitions.update(_SEAMS)
        self.definitions.update(seams or {})
        chunks, seen = [], set()

        def include(name):
            if name in seen:
                return
            seen.add(name)
            declaration = self.definitions[name]
            code = re.sub(r"\\[^\n]*", "", declaration)
            code = re.sub(r"\([^)]*\)", "", code)
            for token in code.split():
                if token != name and token in self.definitions:
                    include(token)
            chunks.append(declaration)

        for name in (*_VARIABLES, *roots):
            include(name)
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=3_000_000)
        self.serial = 0
        self.producer = self.allocate(bytes(self.constant("RTHP-SIZE")))
        self.heap = self.allocate(bytes(1 << 16))
        self.pictures_bank = self.allocate(bytes(4 * len(descriptor())))
        self.entry_size = len(entry())
        for name, value in (("LP-VALID", MASK64), ("LP-ON", MASK64), ("LP-DRAW", 7),
                            ("LP-LIMIT", 1 << 40), ("LP-HEAP-NEXT", self.heap),
                            ("LP-PIXEL-W", 256), ("LP-PIXEL-H", 128)):
            self.variable(name, value)
        for name in ("LP-ASK-STATUS", "LP-UPLOAD-STATUS", "LP-DROP-STATUS",
                     "LP-RESIZE-STATUS", "LP-CANCEL-STATUS", "LP-WANT-STATUS",
                     "LP-FEED-STATUS"):
            self.variable(name, self.constant("RTE-S-OK"))
        self.variable("LP-PULL-STATUS", self.constant("RUHA-S-OK"))
        self.variable("LP-OWNER-STATE", self.constant("RTE-OWNER-ST-OPEN"))
        for name, value in (("COLS", 32), ("ROWS", 8), ("OWNER", 1), ("OWNER-GEN", 2),
                            ("MEMORY", 1), ("NEXT-RESOURCE", 1),
                            ("PICTURES-A", self.pictures_bank)):
            self.put(name, value)
        self.phase("LIVE")

    def allocate(self, data):
        self.serial += 1
        word = self.runtime.define_created(f"LANE-{self.serial}", initial_body=bytes(len(data) + 7))
        address = (word.body_address + 7) & -8
        self.runtime.memory.write_bytes(address, data)
        return address

    def constant(self, name):
        return int(self.definitions[name].split()[0], 0)

    def offset(self, name):
        match = re.search(r"\([^)]*\)\s*(?:(\d+)\s+\+)?\s*;", self.definitions[name])
        assert match, name
        return int(match[1] or 0)

    def get(self, name, base=None):
        return self.runtime.memory.read64((self.producer if base is None else base)
                                          + self.offset(name if "." in name else "_RTHP." + name))

    def put(self, name, value, base=None):
        self.runtime.memory.write64((self.producer if base is None else base)
                                    + self.offset(name if "." in name else "_RTHP." + name),
                                    value & MASK64)

    def ask(self):
        base = self.producer + self.offset("_RTHP.PICTURE-ASK")
        return struct.unpack("<9Q", self.runtime.memory.read_bytes(base, 72))

    def variable(self, name, value=None):
        word = self.runtime.dictionary.find(name.encode())
        if value is None:
            return self.runtime.memory.read64(word.body_address)
        self.runtime.memory.write64(word.body_address, value & MASK64)

    def phase(self, name=None):
        if name is not None:
            self.put("PHASE", self.constant("_RTHP-PH-" + name))
        return self.get("PHASE")

    def results(self, name, *inputs):
        stack = self.runtime.main_context.data
        assert stack.snapshot() == ()
        for value in inputs:
            stack.push(value)
        self.runtime.execute(name, step_budget=3_000_000)
        result = stack.snapshot()
        while stack.depth():
            stack.pop()
        assert self.runtime.main_context.returns.snapshot() == ()
        return result

    def step(self):
        return self.results("_RTHP-LANE-STEP", self.producer)

    def job(self, state, kind, result="OK"):
        self.variable("LP-STATE", self.constant("RTE-JOB-" + state))
        self.variable("LP-KIND", self.constant("RTE-JOB-" + kind))
        self.variable("LP-RESULT", self.constant("RTE-S-" + result))

    def wants(self, offset, most):
        """The upload wants the chunk of MOST bytes at OFFSET."""
        self.job("WANTS", "UPLOAD")
        self.variable("LP-WANT-OFFSET", offset)
        self.variable("LP-WANT-MOST", most)

    def fed(self):
        """What the lane read and handed over: the pulls, where from and
        into, and the feeds."""
        return tuple(self.variable(name) for name in (
            "LP-PULLS", "LP-PULL-OFFSET", "LP-PULL-A", "LP-PULL-U",
            "LP-FEEDS", "LP-FEED-A", "LP-FEED-U"))

    def surface_known(self):
        base = self.producer + self.offset("_RTHP.PICTURE-ASK")
        self.runtime.memory.write_bytes(base, struct.pack("<4Q", 32, 8, 256, 128))

    def pictures(self, descriptors):
        for index, item in enumerate(descriptors):
            self.runtime.memory.write_bytes(self.pictures_bank + len(item) * index, item)
        self.put("PICTURE-COUNT", len(descriptors))

    def table(self, entries):
        table = self.allocate(b"".join(entries))
        self.put("RESOURCES-A", table)
        self.put("RESOURCES-U", self.entry_size * len(entries))
        return table

    def entries(self):
        table, count = self.get("RESOURCES-A"), self.get("RESOURCES-U") // self.entry_size
        return [self.runtime.memory.read_bytes(table + self.entry_size * i, self.entry_size)
                for i in range(count)]

    def resizing(self):
        return self.results("_RTHP-STEP-RESIZING", self.producer)

    def held(self, resources, nbytes):
        self.variable("LP-HELD-RESOURCES", resources)
        self.variable("LP-HELD-BYTES", nbytes)

    def showing(self, ident):
        """A packed bank whose one static is an IMAGE of resource IDENT."""
        bank = self.allocate(bytes(8192))
        self.put("_RTHP-TB.STATIC-COUNT", 1, bank)
        items, = self.results("_RTHP-PACK-STATICS-A", bank)
        record = bytearray(STATIC)
        struct.pack_into("<Q", record, 24, 2)
        struct.pack_into("<Q", record, 168, ident)
        self.runtime.memory.write_bytes(items, bytes(record))
        return bank


@pytest.fixture(params=("python", "native"))
def lane(request):
    return LaneHarness(request.param)


def test_a_new_surface_asks_its_pixels_once_and_the_answer_restales_pictures(lane):
    h = lane
    ok = h.constant("SCB-S-OK")
    h.pictures([descriptor(state=0)])
    assert h.step() == (ok, MASK64, 0)
    assert (h.variable("LP-ASKS"), h.variable("LP-ASK-COLS"), h.variable("LP-ASK-ROWS")) == (1, 32, 8)
    assert h.get("LANE-JOB") == h.constant("RTE-JOB-PIXELS")
    h.job("QUEUED", "PIXELS")
    assert h.step() == (ok, MASK64, 0)
    h.job("AWAITING", "PIXELS")
    assert h.step() == (ok, MASK64, 0)
    h.job("DONE", "PIXELS")
    # A draw with pictures is built again to ask for copies at that size.
    assert h.step() == (ok, 0, MASK64)
    assert h.ask()[:4] == (32, 8, 256, 128)
    assert (h.get("PICTURE-EPOCH"), h.get("LANE-JOB"), h.variable("LP-CLEARS")) == (1, 0, 1)
    # The surface's pixels are known: nothing more to ask.
    assert h.step() == (ok, 0, 0)
    assert h.variable("LP-ASKS") == 1


def test_the_ask_claims_pictures_until_the_lane_fails_to_send_one(lane):
    """The rich side takes the pictures a build describes, so their CELL
    views decode nothing, until the lane fails to send one; CELL then shows
    them all.  A lane that only waits in this draw still takes them."""
    h = lane
    h.results("_RTHP-PICTURE-LIMITS!", h.producer)
    assert h.ask()[8] == MASK64
    h.put("LANE-HOLD-DRAW", 7)
    h.results("_RTHP-PICTURE-LIMITS!", h.producer)
    assert h.ask()[8] == MASK64
    h.put("LANE-FAILED", MASK64)
    h.results("_RTHP-PICTURE-LIMITS!", h.producer)
    assert h.ask()[8] == 0


def test_a_fault_or_the_end_of_the_producer_lets_every_picture_go(lane):
    h = lane
    assert h.results("_RTHP-FAULT-RESULT", h.constant("SCB-S-SESSION-LOST"),
                     h.producer) == (h.constant("SCB-S-SESSION-LOST"), 0, 0)
    assert h.variable("LP-RELEASES") == 1
    h.results("RTHP-FINI", h.producer)
    assert h.variable("LP-RELEASES") == 2


@pytest.mark.parametrize("outcome", ("failed", "refused"))
def test_a_pixel_answer_that_changes_nothing_leaves_the_frame_current(lane, outcome):
    h = lane
    ok = h.constant("SCB-S-OK")
    h.pictures([descriptor(state=0)])
    if outcome == "refused":
        # A terminal that cannot be asked leaves the pixels unknown.
        h.variable("LP-ASK-STATUS", h.constant("RTE-S-UNAVAILABLE"))
        assert h.step() == (ok, 0, 0)
        assert h.get("LANE-JOB") == 0
    else:
        assert h.step() == (ok, MASK64, 0)
        h.job("FAILED", "PIXELS", "INVALID")
        assert h.step() == (ok, 0, 0)
    assert h.get("PICTURE-EPOCH") == 0
    assert h.ask()[:4] == (32, 8, 0, 0)
    assert h.step() == (ok, 0, 0)


@pytest.mark.parametrize("pictures", ("none", "files"))
def test_no_pixel_question_is_asked_without_a_copy_to_make(lane, pictures):
    """A picture whose file the terminal decodes goes at its own size, so
    only a picture that needs a copy made asks how many pixels there are."""
    h = lane
    if pictures == "files":
        h.pictures([descriptor(format=2, nbytes=900),
                    descriptor(index=7, format=4, nbytes=4000, revision=8)])
    h.step()
    assert h.variable("LP-ASKS") == 0
    assert h.ask()[:4] == (0, 0, 0, 0)


def test_a_picture_file_goes_as_it_is(lane):
    """The file's bytes are sent, in its format, while the owner holds room
    for the picture decoded.  Nothing is read until the upload asks."""
    h = lane
    ok = h.constant("SCB-S-OK")
    h.held(1, COPY_BYTES)
    h.pictures([descriptor(format=2, nbytes=777)])
    assert h.step() == (ok, MASK64, 0)
    assert h.variable("LP-ASKS") == 0
    assert (h.variable("LP-UPLOADS"), h.variable("LP-UP-FORMAT"), h.variable("LP-UP-W"),
            h.variable("LP-UP-H"), h.variable("LP-UP-U")) == (
        1, h.constant("RTE-PICTURE-QOI"), 16, 12, 777)
    assert (h.variable("LP-PULLS"), h.get("CHUNK-A"), h.variable("LP-ALLOCS")) == (0, 0, 1)
    # The owner holds the decoded picture, whatever was sent.
    assert h.entries() == [entry(ident=1, state=1, format=2)]
    # The whole file fits one chunk: read once, into a block of its size.
    h.wants(0, 777)
    assert h.step() == (ok, MASK64, 0)
    block = h.get("CHUNK-A")
    assert block and h.get("CHUNK-U") == 777
    assert h.fed() == (1, 0, block, 777, 1, block, 777)
    assert h.variable("LP-PULL-D") == h.pictures_bank
    h.job("DONE", "UPLOAD")
    assert h.step() == (ok, 0, MASK64)
    assert h.entries() == [entry(ident=1, format=2)]
    assert (h.get("CHUNK-A"), h.get("CHUNK-U"), h.variable("LP-FREED")) == (0, 0, 777)


def test_a_ready_picture_is_sent_once_the_owner_has_room_for_it(lane):
    h = lane
    ok = h.constant("SCB-S-OK")
    h.surface_known()
    h.pictures([descriptor()])
    # The owner holds no room for pictures: ask, as the lane's own request,
    # for exactly one more resource and its bytes.
    assert h.step() == (ok, MASK64, 0)
    assert h.phase() == h.constant("_RTHP-PH-RESIZING")
    assert (h.get("RESUME-PHASE"), h.get("LANE-RESIZE")) == (h.constant("_RTHP-PH-LIVE"), 1)
    assert (h.variable("LP-ASKED-RESOURCES"), h.variable("LP-ASKED-BYTES")) == (1, COPY_BYTES)
    assert h.variable("LP-UPLOADS") == 0
    # Granted.  The table takes an entry for each resource held, the copy is
    # pulled into staging and sent as the next resource.
    h.held(1, COPY_BYTES)
    assert h.resizing() == (ok, 0, MASK64)
    assert (h.phase(), h.get("LANE-RESIZE"), h.get("LANE-REFUSED")) == (
        h.constant("_RTHP-PH-LIVE"), 0, 0)
    assert h.step() == (ok, MASK64, 0)
    assert h.get("RESOURCES-U") == h.entry_size
    assert (h.variable("LP-UPLOADS"), h.variable("LP-UP-ID"), h.variable("LP-UP-W"),
            h.variable("LP-UP-H"), h.variable("LP-UP-U")) == (1, 1, 16, 12, COPY_BYTES)
    assert h.variable("LP-UP-FORMAT") == h.constant("RTE-PICTURE-RGBA8")
    # The entry names the picture it is a copy of.
    assert h.entries() == [entry(ident=1, state=1)]
    assert (h.get("NEXT-RESOURCE"), h.get("LANE-JOB")) == (2, h.constant("RTE-JOB-UPLOAD"))
    # Each chunk is read as the upload asks for it, into one block the size
    # of the largest chunk, from the copy the latest build described.
    allocs = h.variable("LP-ALLOCS")
    h.wants(0, 500)
    assert h.step() == (ok, MASK64, 0)
    block = h.get("CHUNK-A")
    assert block and h.get("CHUNK-U") == 500
    assert h.fed() == (1, 0, block, 500, 1, block, 500)
    assert h.variable("LP-PULL-D") == h.pictures_bank
    h.job("AWAITING", "UPLOAD")
    assert h.step() == (ok, MASK64, 0)
    h.wants(500, COPY_BYTES - 500)
    assert h.step() == (ok, MASK64, 0)
    assert h.fed() == (2, 500, block, COPY_BYTES - 500, 2, block, COPY_BYTES - 500)
    assert h.variable("LP-ALLOCS") == allocs + 1
    # The terminal holds it: the frame on screen is stale and the block goes
    # back.
    h.job("DONE", "UPLOAD")
    assert h.step() == (ok, 0, MASK64)
    assert h.entries() == [entry(ident=1)]
    assert (h.get("PICTURE-EPOCH"), h.get("CHUNK-A"), h.get("LANE-JOB")) == (1, 0, 0)
    assert h.variable("LP-FREED") == 500
    # Nothing more to send.
    assert h.step() == (ok, 0, 0)
    assert h.variable("LP-UPLOADS") == 1


def test_a_replacement_asks_for_room_for_both_copies(lane):
    """The copy on screen shows until the terminal holds the one replacing
    it, so the owner needs room for both meanwhile."""
    h = lane
    ok = h.constant("SCB-S-OK")
    h.surface_known()
    h.held(1, COPY_BYTES)
    h.table([entry()])
    h.put("TARGET-ACTIVE", h.showing(5))
    h.pictures([descriptor(copy=(20, 15))])
    assert h.step() == (ok, MASK64, 0)
    assert h.variable("LP-DROPS") == 0
    assert (h.variable("LP-ASKED-RESOURCES"), h.variable("LP-ASKED-BYTES")) == (
        2, COPY_BYTES + 20 * 15 * 4)


def test_uploads_wait_for_a_rich_frame_but_drops_do_not(lane):
    h = lane
    ok = h.constant("SCB-S-OK")
    h.surface_known()
    h.phase("BLANK")
    h.held(2, 4 * COPY_BYTES)
    h.pictures([descriptor(revision=4)])
    h.table([entry()])
    assert h.step() == (ok, MASK64, 0)
    assert (h.variable("LP-DROPS"), h.variable("LP-DROP-ID")) == (1, 5)
    h.job("DONE", "DROP")
    assert h.step() == (ok, 0, 0)
    # The picture on its way may want the room it gave back.
    assert h.step() == (ok, 0, 0)
    assert (h.variable("LP-UPLOADS"), h.variable("LP-RESIZES")) == (0, 0)


def test_a_held_picture_no_frame_shows_and_no_build_wants_goes_back(lane):
    h = lane
    ok = h.constant("SCB-S-OK")
    h.surface_known()
    h.table([entry()])
    # Shown by the frame on screen, or by the one waiting: kept.
    h.put("TARGET-ACTIVE", h.showing(5))
    assert h.step() == (ok, 0, 0)
    h.put("TARGET-ACTIVE", 0)
    h.put("TARGET-PENDING", h.showing(5))
    assert h.step() == (ok, 0, 0)
    # Wanted by the latest build: kept.
    h.put("TARGET-PENDING", h.showing(6))
    h.pictures([descriptor()])
    assert h.step() == (ok, 0, 0)
    assert h.variable("LP-DROPS") == 0
    # Neither: given back.
    h.pictures([])
    assert h.step() == (ok, MASK64, 0)
    assert (h.variable("LP-DROPS"), h.variable("LP-DROP-ID"), h.variable("LP-DROP-BYTES")) == (
        1, 5, COPY_BYTES)
    assert h.get("LANE-JOB") == h.constant("RTE-JOB-DROP")
    h.job("DONE", "DROP")
    assert h.step() == (ok, 0, 0)
    assert h.entries() == [bytes(h.entry_size)]
    assert h.get("LANE-SHRINK") == MASK64


def test_a_picture_the_terminal_will_not_give_back_leaves_pictures_taken(lane):
    """A drop that fails stops the lane for the draw, but the rich side
    still shows its pictures, so none goes back to CELL."""
    h = lane
    ok = h.constant("SCB-S-OK")
    h.surface_known()
    h.table([entry()])
    assert h.step() == (ok, MASK64, 0)
    assert h.get("LANE-JOB") == h.constant("RTE-JOB-DROP")
    h.job("FAILED", "DROP", "INVALID")
    assert h.step() == (ok, 0, 0)
    assert h.entries() == [entry()]
    assert (h.get("LANE-HOLD-DRAW"), h.get("LANE-FAILED"), h.variable("LP-RELEASES")) == (
        7, 0, 0)


@pytest.mark.parametrize("answer", ("given", "kept"))
def test_room_no_picture_uses_goes_back_once_none_is_on_its_way(lane, answer):
    h = lane
    ok = h.constant("SCB-S-OK")
    h.surface_known()
    h.held(3, 4 * COPY_BYTES)
    h.table([entry(), entry(ident=6, revision=4)])
    h.put("TARGET-ACTIVE", h.showing(5))
    h.pictures([descriptor(), descriptor(index=7, state=1)])
    assert h.step() == (ok, MASK64, 0)
    assert (h.variable("LP-DROPS"), h.variable("LP-DROP-ID")) == (1, 6)
    h.job("DONE", "DROP")
    assert h.step() == (ok, 0, 0)
    assert h.get("LANE-SHRINK") == MASK64
    # A picture still decoding may want the room: nothing goes back yet.
    assert h.step() == (ok, 0, 0)
    assert h.variable("LP-RESIZES") == 0
    # Once none is on its way, the owner keeps exactly what its pictures take.
    h.pictures([descriptor()])
    assert h.step() == (ok, MASK64, 0)
    assert (h.variable("LP-RESIZES"), h.variable("LP-ASKED-RESOURCES"),
            h.variable("LP-ASKED-BYTES")) == (1, 1, COPY_BYTES)
    assert (h.phase(), h.get("RESUME-PHASE"), h.get("LANE-RESIZE"), h.get("LANE-SHRINK")) == (
        h.constant("_RTHP-PH-RESIZING"), h.constant("_RTHP-PH-LIVE"), 2, 0)
    if answer == "given":
        h.held(1, COPY_BYTES)
    assert h.resizing() == (ok, 0, MASK64)
    assert (h.phase(), h.get("LANE-RESIZE"), h.get("LANE-REFUSED")) == (
        h.constant("_RTHP-PH-LIVE"), 0, 0)
    # A terminal that keeps the room is not asked again until a picture goes.
    assert h.step() == (ok, 0, 0)
    assert h.variable("LP-RESIZES") == 1


def test_a_refusal_fits_a_smaller_copy_into_the_room_held(lane):
    h = lane
    ok = h.constant("SCB-S-OK")
    h.surface_known()
    h.held(2, 2 * COPY_BYTES)
    h.table([entry()])
    shown = h.showing(5)
    h.put("TARGET-ACTIVE", shown)
    h.pictures([descriptor(), descriptor(index=7, copy=(40, 30), revision=8)])
    # One more resource and the larger copy's bytes: the terminal says no.
    assert h.step() == (ok, MASK64, 0)
    assert (h.variable("LP-ASKED-RESOURCES"), h.variable("LP-ASKED-BYTES")) == (
        2, COPY_BYTES + 40 * 30 * 4)
    assert h.resizing() == (ok, 0, MASK64)
    # The lane keeps its own refusal: a frame of this draw may still grow.
    assert (h.get("LANE-REFUSED"), h.get("SPACE-REFUSED-DRAW"), h.get("LANE-RESIZE")) == (
        h.constant("RTHP-WHY-REFUSED"), 0, 0)
    # The room held and unused takes a smaller copy, still the whole picture:
    # the pictures are described again within it, and nothing is noted.
    assert h.step() == (ok, 0, MASK64)
    assert (h.get("LANE-BUDGET"), h.get("PICTURE-EPOCH"), h.get("FALLBACKS")) == (
        COPY_BYTES, 1, 0)
    h.variable("LP-MAX-BYTES", 1 << 26)
    h.results("_RTHP-PICTURE-LIMITS!", h.producer)
    assert h.ask()[6] == COPY_BYTES
    h.variable("LP-MAX-BYTES", COPY_BYTES // 2)
    h.results("_RTHP-PICTURE-LIMITS!", h.producer)
    assert h.ask()[6] == COPY_BYTES // 2
    # Nothing more until the frame on screen is built again.
    h.pictures([descriptor(), descriptor(index=7, revision=8)])
    assert h.step() == (ok, 0, 0)
    assert h.variable("LP-UPLOADS") == 0
    # The smaller copy then goes out with no more asking.
    h.put("_RTHP-TB.PICTURE-EPOCH", 1, shown)
    assert h.step() == (ok, MASK64, 0)
    assert (h.variable("LP-RESIZES"), h.variable("LP-UPLOADS"), h.variable("LP-UP-U")) == (
        1, 1, COPY_BYTES)


@pytest.mark.parametrize("why", ("refused", "limit"))
def test_a_refused_picture_stays_cell_until_no_picture_is_described(lane, why):
    h = lane
    ok = h.constant("SCB-S-OK")
    h.surface_known()
    h.pictures([descriptor()])
    if why == "refused":
        h.variable("LP-RESIZE-STATUS", h.constant("RTE-S-INVALID"))
    else:
        # More than the terminal offers at all is never asked for.
        h.variable("LP-LIMIT", COPY_BYTES - 1)
    asked = 1 if why == "refused" else 0
    # The owner holds no room to fit a smaller copy into.
    assert h.step() == (ok, 0, 0)
    assert h.variable("LP-RESIZES") == asked
    reason = h.constant("RTHP-WHY-" + why.upper())
    assert (h.get("LANE-REFUSED"), h.get("LANE-BUDGET"), h.get("SPACE-REFUSED-DRAW")) == (
        reason, 0, 0)
    assert (h.get("FALLBACKS"), h.get("FALLBACK-DRAW"), h.get("FALLBACK-PARTS"),
            h.get("FALLBACK-REASON")) == (1, 7, h.constant("RTHP-PART-PICTURES"), reason)
    # The rich side takes no picture now: CELL shows each one.
    assert (h.get("LANE-FAILED"), h.variable("LP-RELEASES")) == (MASK64, 1)
    h.results("_RTHP-PICTURE-LIMITS!", h.producer)
    assert h.ask()[8] == 0
    # Newer draws ask no more, and keep saying why.
    h.variable("LP-RESIZE-STATUS", h.constant("RTE-S-OK"))
    h.variable("LP-LIMIT", 1 << 40)
    h.variable("LP-DRAW", 8)
    assert h.step() == (ok, 0, 0)
    assert (h.variable("LP-RESIZES"), h.variable("LP-UPLOADS")) == (asked, 0)
    assert (h.get("FALLBACKS"), h.get("FALLBACK-DRAW"), h.get("FALLBACK-REASON")) == (
        2, 8, reason)
    # A draw with no picture ends the refusal; the next picture asks again,
    # and the rich side takes it.
    h.pictures([])
    h.variable("LP-DRAW", 9)
    assert h.step() == (ok, 0, 0)
    assert (h.get("LANE-REFUSED"), h.get("LANE-BUDGET"), h.get("LANE-FAILED")) == (0, 0, 0)
    h.pictures([descriptor()])
    h.variable("LP-DRAW", 10)
    assert h.step() == (ok, MASK64, 0)
    assert (h.phase(), h.variable("LP-RESIZES")) == (
        h.constant("_RTHP-PH-RESIZING"), asked + 1)


def test_a_frame_refused_more_space_leaves_pictures_going(lane):
    h = lane
    ok = h.constant("SCB-S-OK")
    h.surface_known()
    # A frame's own request, refused: the refusal is the frame's.
    h.phase("RESIZING")
    h.put("RESUME-PHASE", h.constant("_RTHP-PH-LIVE"))
    for name in ("_RTHP.NEED", "_RTHP.ASK"):
        h.runtime.memory.write64(h.producer + h.offset(name), 9)
    assert h.resizing() == (ok, 0, MASK64)
    assert (h.get("SPACE-REFUSED-DRAW"), h.get("LANE-REFUSED")) == (7, 0)
    # Pictures still go out in that draw.
    h.pictures([descriptor()])
    h.held(1, COPY_BYTES)
    assert h.step() == (ok, MASK64, 0)
    assert h.variable("LP-UPLOADS") == 1


@pytest.mark.parametrize("cancel", ("stopped", "too-late"))
@pytest.mark.parametrize("change", ("another", "resized", "none"))
def test_an_upload_whose_picture_the_latest_build_no_longer_describes_stops(
        lane, cancel, change):
    h = lane
    ok = h.constant("SCB-S-OK")
    h.surface_known()
    h.held(1, COPY_BYTES)
    h.pictures([descriptor()])
    assert h.step() == (ok, MASK64, 0)
    # While the latest build describes the picture, the upload goes on.
    h.job("QUEUED", "UPLOAD")
    assert h.step() == (ok, MASK64, 0)
    h.wants(0, 100)
    assert h.step() == (ok, MASK64, 0)
    h.job("AWAITING", "UPLOAD")
    assert h.step() == (ok, MASK64, 0)
    assert (h.variable("LP-FEEDS"), h.variable("LP-CANCELS")) == (1, 0)
    # A newer build describes another picture in the element, a copy of
    # another size, or no picture; nothing is asked of a frame awaiting the
    # terminal.
    h.pictures({"another": [descriptor(revision=4)], "resized": [descriptor(copy=(20, 15))],
                "none": []}[change])
    assert h.step() == (ok, MASK64, 0)
    assert h.variable("LP-CANCELS") == 0
    if cancel == "too-late":
        h.variable("LP-CANCEL-STATUS", h.constant("RTE-S-WOULD-BLOCK"))
    h.wants(100, 100)
    assert h.step() == (ok, MASK64, 0)
    assert (h.variable("LP-CANCELS"), h.variable("LP-PULLS")) == (1, 1)
    if cancel == "too-late":
        # It can only finish; the terminal then holds a picture no frame
        # wants, which goes back like any other.
        assert h.entries() == [entry(ident=1, state=1)]
        h.job("DONE", "UPLOAD")
        assert h.step() == (ok, 0, MASK64)
        assert h.entries() == [entry(ident=1)]
        return
    assert h.entries() == [entry(ident=1, state=3)]
    # Stopped, it is simply forgotten: nothing is noted and nothing waits.
    h.job("FAILED", "UPLOAD", "STALE")
    assert h.step()[:2] == (ok, 0)
    assert h.entries()[0] == bytes(h.entry_size)
    assert (h.get("FALLBACKS"), h.get("CHUNK-A"), h.get("LANE-HOLD-DRAW"),
            h.variable("LP-FREED")) == (0, 0, 0, 100)


@pytest.mark.parametrize("failure", ("stale", "invalid", "memory"))
def test_a_chunk_that_cannot_be_read_stops_its_upload(lane, failure):
    """A read that finds the picture no longer showing that file or copy
    stops the upload and waits for the draw that changed the picture.  A
    block the memory source refuses, or a read that fails otherwise, stops
    it and sends every picture back to CELL."""
    h = lane
    ok = h.constant("SCB-S-OK")
    h.surface_known()
    h.held(1, COPY_BYTES)
    h.pictures([descriptor()])
    assert h.step() == (ok, MASK64, 0)
    h.wants(0, 300)
    if failure == "memory":
        h.variable("LP-REFUSE", MASK64)
    else:
        h.variable("LP-PULL-STATUS", h.constant(
            "RUHA-S-STALE" if failure == "stale" else "RUHA-S-INVALID"))
    assert h.step() == (ok, MASK64, 0)
    assert (h.variable("LP-CANCELS"), h.variable("LP-FEEDS")) == (1, 0)
    assert h.entries() == [entry(ident=1, state=3)]
    assert h.variable("LP-PULLS") == (0 if failure == "memory" else 1)
    assert h.get("LANE-HOLD-DRAW") == 7
    if failure == "stale":
        assert (h.get("FALLBACKS"), h.get("LANE-FAILED"), h.variable("LP-RELEASES")) == (
            0, 0, 0)
    else:
        reason = "MEMORY" if failure == "memory" else "OTHER"
        assert (h.get("FALLBACKS"), h.get("FALLBACK-REASON")) == (
            1, h.constant("RTHP-WHY-" + reason))
        assert (h.get("LANE-FAILED"), h.variable("LP-RELEASES")) == (MASK64, 1)
    # The stopped upload ends; nothing more starts in this draw.
    h.variable("LP-REFUSE", 0)
    h.variable("LP-PULL-STATUS", h.constant("RUHA-S-OK"))
    h.job("FAILED", "UPLOAD", "STALE")
    assert h.step() == (ok, 0, 0)
    assert h.step() == (ok, 0, 0)
    assert (h.variable("LP-UPLOADS"), h.get("CHUNK-A")) == (1, 0)


def test_the_lane_waits_for_the_frame_built_after_a_change(lane):
    h = lane
    ok = h.constant("SCB-S-OK")
    h.surface_known()
    h.held(2, 2 * COPY_BYTES)
    h.table([entry(ident=6, revision=4)])
    h.pictures([descriptor()])
    stale = h.showing(9)
    h.put("TARGET-ACTIVE", stale)
    h.put("PICTURE-EPOCH", 1)
    assert h.step() == (ok, 0, 0)
    assert (h.variable("LP-DROPS"), h.variable("LP-UPLOADS"), h.variable("LP-RESIZES")) == (
        0, 0, 0)
    h.put("_RTHP-TB.PICTURE-EPOCH", 1, stale)
    assert h.step() == (ok, MASK64, 0)
    assert (h.variable("LP-DROPS"), h.variable("LP-DROP-ID")) == (1, 6)


@pytest.mark.parametrize("failure", ("terminal", "stale", "memory"))
def test_a_failed_picture_waits_for_a_newer_draw(lane, failure):
    h = lane
    ok = h.constant("SCB-S-OK")
    h.surface_known()
    h.pictures([descriptor()])
    h.held(1, COPY_BYTES)
    if failure == "terminal":
        assert h.step() == (ok, MASK64, 0)
        h.job("DONE", "UPLOAD", "CAPACITY")
        assert h.step() == (ok, 0, 0)
        assert h.entries() == [bytes(h.entry_size)]
        reason = "REFUSED"
    elif failure == "stale":
        # The picture changed under the build that described it; the draw
        # that changed it describes it again.
        assert h.step() == (ok, MASK64, 0)
        h.wants(0, COPY_BYTES)
        h.variable("LP-PULL-STATUS", h.constant("RUHA-S-STALE"))
        assert h.step() == (ok, MASK64, 0)
        h.job("FAILED", "UPLOAD", "STALE")
        assert h.step() == (ok, 0, 0)
        assert h.variable("LP-FREED") == COPY_BYTES
        reason = None
    else:
        h.variable("LP-REFUSE", MASK64)
        assert h.step() == (ok, 0, 0)
        reason = "MEMORY"
    assert h.phase() == h.constant("_RTHP-PH-LIVE")
    if reason is None:
        # Only waiting: the rich side still takes its pictures.
        assert (h.get("FALLBACKS"), h.get("LANE-FAILED"), h.variable("LP-RELEASES")) == (
            0, 0, 0)
    else:
        assert (h.get("FALLBACKS"), h.get("FALLBACK-DRAW"), h.get("FALLBACK-PARTS"),
                h.get("FALLBACK-REASON")) == (1, 7, h.constant("RTHP-PART-PICTURES"),
                                              h.constant("RTHP-WHY-" + reason))
        # Every picture goes back to CELL, which shows it.
        assert (h.get("LANE-FAILED"), h.variable("LP-RELEASES")) == (MASK64, 1)
    uploads, resizes = h.variable("LP-UPLOADS"), h.variable("LP-RESIZES")
    assert h.step() == (ok, 0, 0)
    assert (h.variable("LP-UPLOADS"), h.variable("LP-RESIZES")) == (uploads, resizes)
    # A newer draw tries again, and the rich side takes the pictures once
    # the upload starts.
    h.variable("LP-DRAW", 8)
    h.variable("LP-REFUSE", 0)
    h.variable("LP-PULL-STATUS", h.constant("RUHA-S-OK"))
    assert h.step() == (ok, MASK64, 0)
    assert (h.variable("LP-UPLOADS"), h.get("LANE-FAILED")) == (uploads + 1, 0)


@pytest.mark.parametrize("case", ("feature", "memory", "none-shown", "lane"))
def test_a_build_with_no_lane_says_why_its_pictures_stay_cell(lane, case):
    h = lane
    h.variable("_RTHP-W-P", h.producer)
    h.variable("_RTHP-W-DRAW", 7)
    h.surface_known()
    h.put("PICTURES-U", 4 * len(descriptor()))
    h.variable("LP-CAP-COUNT", 2)
    h.variable("LP-CAP-STATUS", h.constant("RUHA-S-CAPACITY"))
    if case == "memory":
        h.put("MEMORY", 0)
    if case == "none-shown":
        h.variable("LP-CAP-COUNT", 0)
        h.variable("LP-CAP-STATUS", h.constant("RUHA-S-OK"))
    if case == "lane":
        h.variable("LP-CAP-STATUS", h.constant("RUHA-S-OK"))
    else:
        h.variable("LP-ON", 0)
    assert h.results("_RTHP-W-PICTURES") == ()
    ask = h.producer + h.offset("_RTHP.PICTURE-ASK")
    assert (h.variable("LP-CAPTURES"), h.variable("LP-CAP-ASK"), h.variable("LP-CAP-DRAW")) == (
        1, ask, 7)
    if case == "lane":
        # Described into the picture bank, under the surface's pixels.
        assert (h.variable("LP-CAP-A"), h.variable("LP-CAP-U")) == (
            h.pictures_bank, 4 * len(descriptor()))
        assert (h.get("PICTURE-COUNT"), h.get("FALLBACKS")) == (2, 0)
        assert h.ask()[:4] == (32, 8, 256, 128)
        assert h.variable("LP-RELEASES") == 0
        return
    # Only counted: no bank, and an ask that asks no picture for a copy, so
    # the pixel size is asked afresh if the lane comes on.
    assert (h.variable("LP-CAP-A"), h.variable("LP-CAP-U")) == (0, 0)
    assert h.ask() == (0,) * 9
    # The lane takes no picture: every claim lapses, and CELL shows them.
    assert h.variable("LP-RELEASES") == 1
    assert h.get("PICTURE-COUNT") == 0
    if case == "none-shown":
        assert h.get("FALLBACKS") == 0
        return
    why = "LIMIT" if case == "feature" else "MEMORY"
    assert (h.get("FALLBACKS"), h.get("FALLBACK-DRAW"), h.get("FALLBACK-PARTS"),
            h.get("FALLBACK-REASON")) == (1, 7, h.constant("RTHP-PART-PICTURES"),
                                          h.constant("RTHP-WHY-" + why))


# Each way RTHP-PREPARE builds or passes on a frame counts one build.
_PREPARE_SEAMS = {
    "_RTPROF-PH-OTHER": "0 CONSTANT _RTPROF-PH-OTHER",
    "_RTPROF-MARK": ": _RTPROF-MARK DROP ;",
    "_RTHP-CALL-SURFACE?": ": _RTHP-CALL-SURFACE? 2DROP 2DROP -1 ;",
    "_RTHP-CANDIDATE-CURRENT?": ": _RTHP-CANDIDATE-CURRENT? DROP -1 ;",
    "_RTHP-PREPARE-REVEAL": ": _RTHP-PREPARE-REVEAL 2DROP 1 LP-BUILDS +! SCB-S-OK ;",
    **{name: f": {name} DROP 1 LP-BUILDS +! SCB-S-OK ;" for name in (
        "_RTHP-PREPARE-LIVE", "_RTHP-PREPARE-BLANK", "_RTHP-BLANK-BEGIN",
        "_RTHP-PREPARE-START", "_RTHP-RECAPTURE-START", "_RTHP-PREPARE-DELTA",
        "_RTHP-DELTA-STALE", "_RTHP-REVEAL-STALE")},
}


@pytest.mark.parametrize("backend", ("python", "native"))
@pytest.mark.parametrize("phase", ("LIVE", "BLANK", "READY-BLANK", "READY-START",
                                   "READY-DELTA"))
def test_frames_are_prepared_during_an_upload_but_wait_for_short_jobs(backend, phase):
    """Frames run between an upload's frames (APT-1-RETAINED-1 section 8),
    but not while one of them awaits its answer, when the engine takes no
    update.  The pixel question and a drop are one short exchange each, and
    a frame waits for them."""

    h = LaneHarness(backend, roots=("RTHP-PREPARE",), seams=_PREPARE_SEAMS)
    h.phase(phase)
    for kind, state, waits in ((None, None, False), ("UPLOAD", "QUEUED", False),
                               ("UPLOAD", "WANTS", False),
                               ("UPLOAD", "AWAITING", True), ("UPLOAD", "DONE", False),
                               ("PIXELS", "QUEUED", True), ("DROP", "QUEUED", True)):
        h.put("LANE-JOB", 0 if kind is None else h.constant("RTE-JOB-" + kind))
        if kind is not None:
            h.job(state, kind)
        builds = h.variable("LP-BUILDS")
        assert h.results("RTHP-PREPARE", 32, 8, 1, h.producer) == (
            h.constant("SCB-S-WOULD-BLOCK" if waits else "SCB-S-OK"),), (kind, state)
        assert h.variable("LP-BUILDS") == builds + (not waits), (kind, state)


@pytest.mark.parametrize("key", (1, 3))
def test_a_picture_whose_bytes_the_terminal_refuses_is_sent_once(lane, key):
    """The terminal refused a picture's bytes as no picture of their size.
    Its widget, named by its element and root key, an element's own
    picture's or a figure's, remembers it, so the frame built again
    describes it as failed and no build sends it again.  The lane notes no
    failure, so the other pictures stay rich."""
    h = lane
    ok = h.constant("SCB-S-OK")
    h.surface_known()
    h.held(2, 2 * COPY_BYTES)
    shown = h.showing(9)
    h.put("TARGET-ACTIVE", shown)
    other = descriptor(index=7, revision=8)
    h.pictures([descriptor(format=2, nbytes=700, key=key), other])
    assert h.step() == (ok, MASK64, 0)
    h.wants(0, 700)
    assert h.step() == (ok, MASK64, 0)
    h.job("FAILED", "UPLOAD", "SOURCE")
    assert h.step() == (ok, 0, MASK64)
    assert (h.variable("LP-FAILS"), h.variable("LP-FAIL-DOCUMENT"),
            h.variable("LP-FAIL-INDEX"), h.variable("LP-FAIL-KEY"),
            h.variable("LP-FAIL-REVISION"), h.variable("LP-FAIL-REASON")) == (
        1, 11, 5, key, 3, h.constant("PIC-R-DAMAGED"))
    assert h.entries()[0] == bytes(h.entry_size)
    assert (h.get("LANE-FAILED"), h.variable("LP-RELEASES"), h.get("FALLBACKS"),
            h.get("PICTURE-EPOCH"), h.get("CHUNK-A")) == (0, 0, 0, 1, 0)
    # Nothing more until the frame on screen is built again.
    assert h.step() == (ok, 0, 0)
    assert h.variable("LP-UPLOADS") == 1
    # Built again, the refused picture is described as failed and the other
    # picture goes.
    h.put("_RTHP-TB.PICTURE-EPOCH", 1, shown)
    h.pictures([descriptor(format=2, nbytes=700, state=3, key=key), other])
    assert h.step() == (ok, MASK64, 0)
    assert (h.variable("LP-UPLOADS"), h.variable("LP-UP-ID"), h.variable("LP-UP-U")) == (
        2, 2, COPY_BYTES)
    assert h.variable("LP-FAILS") == 1
