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
DIGEST = bytes(range(1, 33))
COPY_BYTES = 16 * 12 * 4


def descriptor(*, index=5, row=4, col=2, height=3, width=8, z=4, state=2,
               copy=(16, 12), digest=DIGEST, document=11, revision=3):
    """A UPICSN descriptor, as a build's capture leaves it."""
    w, h = copy
    return (struct.pack("<16Q", 1, index, 0, 1, row, col, height, width, z, state, 0,
                        w, h, w * h * 4, w, h) + digest
            + struct.pack("<2Q", document, revision))


def entry(*, ident=5, copy=(16, 12), state=2, digest=DIGEST):
    """A resource table entry: ID, size, bytes, HELD or UPLOADING, digest."""
    w, h = copy
    return struct.pack("<5Q", ident, w, h, w * h * 4, state) + digest


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
        images = sum(self.runtime.memory.read64(items + 176 * i + 24) == 2
                     for i in range(count))
        text = self.get("STATIC-TEXT-USED")
        aligned = (text + 7) & -8
        admission = self.producer + self.offset("_RTHP.ADMISSION")
        for name, value in (("STATIC-COUNT", count), ("STATIC-TEXT", text),
                            ("STATIC-ALIGNED", aligned), ("STATIC-MAX", text),
                            ("STATIC-LAST", 99 + count if count else 0),
                            ("STATIC-COPY", 176 * (count - images) + aligned),
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
    item = h.get("STATICS-A") + 176
    fields = struct.unpack("<22Q", h.runtime.memory.read_bytes(item, 176))
    # Owner, generation, ID, IMAGE, visible, z, region, no parent; rows 4..6
    # and columns 2..9 of the 32 by 8 root; CONTAIN, opaque, over a backdrop;
    # no text; resource 5.
    assert fields == (1, 2, 101, 2, MASK64, 4, 7, 0, 4, 2, 3, 8, 8, 32,
                      1, 255, MASK64, 0, 0, 0, 0, 5)
    size = h.constant("RUCL-CLAIM-SIZE")
    claim = h.runtime.memory.read_bytes(h.get("CLAIMS-A") + size, size)
    assert struct.unpack("<10Q", claim[:80]) == (11, 9, 1, 5, 0, 4, 4, 2, 7, 10)
    corr = h.runtime.memory.read_bytes(h.get("STATIC-CORR-A") + 40, 40)
    assert struct.unpack("<5Q", corr) == (11, 5, 0, 1, 0)
    h.admit_images()
    assert h.call("_RTHP-STATICS-FIXED?", h.producer)
    h.guards()


@pytest.mark.parametrize("case", ("uploading", "digest", "size", "pending", "document",
                                  "off-surface", "claimed", "paint"))
def test_a_picture_the_terminal_cannot_show_stays_cell(images, case):
    h = images
    h.setup(pictures=2)
    changes, held = {}, {}
    if case == "uploading":
        held["state"] = 1
    elif case == "digest":
        held["digest"] = bytes(32)
    elif case == "size":
        held["copy"] = (15, 12)
    elif case == "pending":
        changes["state"] = 1
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
        h.field(admission, "_RTE-HA.STATIC-COPY", 2 * 176 + ((text + 7) & -8))
    elif mutation == "claim":
        h.runtime.memory.write64(h.get("CLAIMS-A") + h.constant("RUCL-CLAIM-SIZE") + 64, 5)
    else:
        h.runtime.memory.write64(h.get("STATICS-A") + 176 + 80, 5)
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
    h.runtime.memory.write64(items + 176 + 168, 6)
    assert h.call("_RTHP-D-STATIC-CHANGED?", 1)
    assert not h.call("_RTHP-D-STATIC-CHANGED?", 0)
    assert h.call("_RTHP-STATICS-REUSABLE?", bank, other, 0)
    h.runtime.memory.write64(items + 176 + 64, 3)
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
        ": RTE-RESOURCE-UPLOAD DROP LP-UP-DIGEST ! LP-UP-U ! LP-UP-A ! "
        "LP-UP-H ! LP-UP-W ! LP-UP-ID ! 2DROP 1 LP-UPLOADS +! LP-UPLOAD-STATUS @ ;"
    ),
    "RTE-RESOURCE-DROP": (
        ": RTE-RESOURCE-DROP DROP LP-DROP-BYTES ! LP-DROP-ID ! 2DROP "
        "1 LP-DROPS +! LP-DROP-STATUS @ ;"
    ),
    "RUHA-PICTURE-PULL": (
        ": RUHA-PICTURE-PULL DROP LP-PULL-U ! LP-PULL-A ! LP-PULL-D ! "
        "1 LP-PULLS +! LP-PULL-STATUS @ ;"
    ),
}
_VARIABLES = (
    "LP-VALID", "LP-ON", "LP-DRAW", "LP-HELD-RESOURCES", "LP-HELD-BYTES", "LP-LIMIT",
    "LP-RESIZES", "LP-ASKED-RESOURCES", "LP-ASKED-BYTES", "LP-RESIZE-STATUS",
    "LP-REFUSE", "LP-HEAP-NEXT", "LP-ALLOCS", "LP-FREES", "LP-FREED",
    "LP-STATE", "LP-KIND", "LP-ITEM", "LP-RESULT", "LP-CLEARS",
    "LP-ASKS", "LP-ASK-COLS", "LP-ASK-ROWS", "LP-ASK-STATUS", "LP-PIXEL-W", "LP-PIXEL-H",
    "LP-UPLOADS", "LP-UP-ID", "LP-UP-W", "LP-UP-H", "LP-UP-A", "LP-UP-U", "LP-UP-DIGEST",
    "LP-UPLOAD-STATUS", "LP-DROPS", "LP-DROP-ID", "LP-DROP-BYTES", "LP-DROP-STATUS",
    "LP-PULLS", "LP-PULL-D", "LP-PULL-A", "LP-PULL-U", "LP-PULL-STATUS",
)


class LaneHarness:
    def __init__(self, backend):
        self.runtime = MegaForthRuntime(execution_backend=backend)
        self.definitions = _definitions(PRODUCER.read_text() + "\n" + SNAPSHOT.read_text())
        for path in (ROOT / "akashic/tui/screen.f", ADAPTER,
                     PRODUCER.parent / "residual-glyph-planner.f",
                     PRODUCER.parent / "uidl-claim-ledger.f"):
            for match in re.finditer(r"(?m)^\s*(\d+)\s+CONSTANT\s+(\S+)", path.read_text()):
                self.definitions.setdefault(match[2], match[0])
        for name in _VARIABLES:
            self.definitions[name] = f"VARIABLE {name}"
        self.definitions.update(_SEAMS)
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

        for name in (*_VARIABLES, "_RTHP-LANE-STEP", "_RTHP-PACK-STATICS-A"):
            include(name)
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=3_000_000)
        self.serial = 0
        self.producer = self.allocate(bytes(self.constant("RTHP-SIZE")))
        self.heap = self.allocate(bytes(1 << 16))
        self.pictures_bank = self.allocate(bytes(4 * 176))
        for name, value in (("LP-VALID", MASK64), ("LP-ON", MASK64), ("LP-DRAW", 7),
                            ("LP-LIMIT", 1 << 40), ("LP-HEAP-NEXT", self.heap),
                            ("LP-PIXEL-W", 256), ("LP-PIXEL-H", 128)):
            self.variable(name, value)
        for name in ("LP-ASK-STATUS", "LP-UPLOAD-STATUS", "LP-DROP-STATUS",
                     "LP-RESIZE-STATUS"):
            self.variable(name, self.constant("RTE-S-OK"))
        self.variable("LP-PULL-STATUS", self.constant("RUHA-S-OK"))
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
        return struct.unpack("<7Q", self.runtime.memory.read_bytes(base, 56))

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
        self.put("RESOURCES-U", 72 * len(entries))
        return table

    def held(self, resources, nbytes):
        self.variable("LP-HELD-RESOURCES", resources)
        self.variable("LP-HELD-BYTES", nbytes)

    def showing(self, ident):
        """A packed bank whose one static is an IMAGE of resource IDENT."""
        bank = self.allocate(bytes(8192))
        self.put("_RTHP-TB.STATIC-COUNT", 1, bank)
        items, = self.results("_RTHP-PACK-STATICS-A", bank)
        record = bytearray(176)
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


@pytest.mark.parametrize("outcome", ("no-pictures", "failed", "refused"))
def test_a_pixel_answer_that_changes_nothing_leaves_the_frame_current(lane, outcome):
    h = lane
    ok = h.constant("SCB-S-OK")
    if outcome == "refused":
        # A terminal that cannot be asked leaves the pixels unknown.
        h.variable("LP-ASK-STATUS", h.constant("RTE-S-UNAVAILABLE"))
        h.pictures([descriptor(state=0)])
        assert h.step() == (ok, 0, 0)
        assert h.get("LANE-JOB") == 0
    else:
        if outcome == "failed":
            h.pictures([descriptor(state=0)])
        assert h.step() == (ok, MASK64, 0)
        h.job("FAILED" if outcome == "failed" else "DONE", "PIXELS",
              "INVALID" if outcome == "failed" else "OK")
        assert h.step() == (ok, 0, 0)
    assert h.get("PICTURE-EPOCH") == 0
    assert h.ask()[:2] == (32, 8)
    assert h.ask()[2:4] == ((256, 128) if outcome == "no-pictures" else (0, 0))
    assert h.step() == (ok, 0, 0)


def test_a_ready_picture_is_sent_once_the_owner_has_room_for_it(lane):
    h = lane
    ok = h.constant("SCB-S-OK")
    h.surface_known()
    h.pictures([descriptor()])
    # The owner holds no room for pictures: ask for one more resource and
    # its bytes, and half again.
    assert h.step() == (ok, MASK64, 0)
    assert h.phase() == h.constant("_RTHP-PH-RESIZING")
    assert h.get("RESUME-PHASE") == h.constant("_RTHP-PH-LIVE")
    assert (h.variable("LP-ASKED-RESOURCES"), h.variable("LP-ASKED-BYTES")) == (
        1, COPY_BYTES * 3 // 2)
    assert h.variable("LP-UPLOADS") == 0
    # Granted.  The table takes an entry for each resource held, the copy is
    # pulled into staging and sent as the next resource.
    h.phase("LIVE")
    h.held(1, COPY_BYTES * 3 // 2)
    assert h.step() == (ok, MASK64, 0)
    assert h.get("RESOURCES-U") == 72
    assert (h.variable("LP-PULLS"), h.variable("LP-PULL-D"), h.variable("LP-PULL-U")) == (
        1, h.pictures_bank, COPY_BYTES)
    staging = h.get("STAGING-A")
    assert staging and h.variable("LP-PULL-A") == h.variable("LP-UP-A") == staging
    assert (h.variable("LP-UPLOADS"), h.variable("LP-UP-ID"), h.variable("LP-UP-W"),
            h.variable("LP-UP-H"), h.variable("LP-UP-U")) == (1, 1, 16, 12, COPY_BYTES)
    table = h.get("RESOURCES-A")
    assert h.variable("LP-UP-DIGEST") == table + 40
    assert h.runtime.memory.read_bytes(table, 72) == entry(ident=1, state=1)
    assert (h.get("NEXT-RESOURCE"), h.get("LANE-JOB")) == (2, h.constant("RTE-JOB-UPLOAD"))
    # The terminal holds it: the frame on screen is stale and staging goes back.
    h.job("DONE", "UPLOAD")
    assert h.step() == (ok, 0, MASK64)
    assert h.runtime.memory.read_bytes(table, 72) == entry(ident=1)
    assert (h.get("PICTURE-EPOCH"), h.get("STAGING-A"), h.get("LANE-JOB")) == (1, 0, 0)
    assert h.variable("LP-FREED") == COPY_BYTES
    # Nothing more to send.
    assert h.step() == (ok, 0, 0)
    assert h.variable("LP-UPLOADS") == 1


def test_uploads_wait_for_a_rich_frame_but_drops_do_not(lane):
    h = lane
    ok = h.constant("SCB-S-OK")
    h.surface_known()
    h.phase("BLANK")
    h.held(2, 4 * COPY_BYTES)
    h.pictures([descriptor(digest=bytes(32))])
    h.table([entry()])
    assert h.step() == (ok, MASK64, 0)
    assert (h.variable("LP-DROPS"), h.variable("LP-DROP-ID")) == (1, 5)
    h.job("DONE", "DROP")
    assert h.step() == (ok, 0, 0)
    assert h.step() == (ok, 0, 0)
    assert h.variable("LP-UPLOADS") == 0


def test_a_held_picture_no_frame_shows_and_no_build_wants_goes_back(lane):
    h = lane
    ok = h.constant("SCB-S-OK")
    h.surface_known()
    table = h.table([entry()])
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
    assert h.runtime.memory.read_bytes(table, 72) == bytes(72)


@pytest.mark.parametrize("failure", ("terminal", "stale", "memory", "limit", "room"))
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
        assert h.runtime.memory.read_bytes(h.get("RESOURCES-A"), 72) == bytes(72)
        reason = "REFUSED"
    elif failure == "stale":
        # The picture changed under the build that described it; the draw
        # that changed it describes it again.
        h.variable("LP-PULL-STATUS", h.constant("RUHA-S-STALE"))
        assert h.step() == (ok, 0, 0)
        assert h.variable("LP-FREED") == COPY_BYTES
        reason = None
    elif failure == "memory":
        h.variable("LP-REFUSE", MASK64)
        assert h.step() == (ok, 0, 0)
        reason = "MEMORY"
    elif failure == "limit":
        h.held(0, 0)
        h.variable("LP-LIMIT", COPY_BYTES - 1)
        assert h.step() == (ok, 0, 0)
        assert h.variable("LP-RESIZES") == 0
        reason = "LIMIT"
    else:
        h.held(0, 0)
        h.variable("LP-RESIZE-STATUS", h.constant("RTE-S-INVALID"))
        assert h.step() == (ok, 0, 0)
        assert h.get("SPACE-REFUSED-DRAW") == 7
        reason = "REFUSED"
    assert h.phase() == h.constant("_RTHP-PH-LIVE")
    if reason is None:
        assert h.get("FALLBACKS") == 0
    else:
        assert (h.get("FALLBACKS"), h.get("FALLBACK-DRAW"), h.get("FALLBACK-PARTS"),
                h.get("FALLBACK-REASON")) == (1, 7, h.constant("RTHP-PART-PICTURES"),
                                              h.constant("RTHP-WHY-" + reason))
    uploads, resizes = h.variable("LP-UPLOADS"), h.variable("LP-RESIZES")
    assert h.step() == (ok, 0, 0)
    assert (h.variable("LP-UPLOADS"), h.variable("LP-RESIZES")) == (uploads, resizes)
    # A newer draw tries again.
    h.variable("LP-DRAW", 8)
    for name, value in (("LP-REFUSE", 0), ("LP-LIMIT", 1 << 40)):
        h.variable(name, value)
    h.variable("LP-PULL-STATUS", h.constant("RUHA-S-OK"))
    h.variable("LP-RESIZE-STATUS", h.constant("RTE-S-OK"))
    assert h.step() == (ok, MASK64, 0)
    assert h.variable("LP-UPLOADS") + h.variable("LP-RESIZES") == uploads + resizes + 1


def test_no_frame_is_prepared_while_a_picture_job_runs() -> None:
    source = PRODUCER.read_text()
    prepare = re.search(r"(?ms)^: RTHP-PREPARE .*?;\s*$", source)[0]
    wait = prepare.index("_RTHP.LANE-JOB @ IF SCB-S-WOULD-BLOCK EXIT THEN")
    assert wait < prepare.index("_RTHP-PH-LIVE = IF") < prepare.index("_RTHP-PH-BLANK = IF")
