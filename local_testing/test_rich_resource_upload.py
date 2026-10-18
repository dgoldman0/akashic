"""An owner uploads, shows and drops pictures through the real terminal.

The complete PT module, Akashic engine, neutral facade and its APT-1 bridge
run against the real terminal driver; no Desktop starts.  Each check reads
what the terminal itself holds: its committed resources and their pixels,
its open upload, each owner's usage and reservation, the IMAGE objects it
shows, and its answers to pixel questions.  An upload's bytes are fed a
chunk at a time, as the job asks, from one block the harness reuses.
"""
from dataclasses import replace
import struct
from unittest.mock import patch

import pytest

import qoi_codec
import test_rich_terminal_cell_feed as cf
from test_rich_terminal_status_static import RICH, SOURCE, _clean, _word
from simulator.runtime import MegaForthRuntime
from tests.simulator.test_kdos_exceptions import _load_exceptions
from rich_terminal.retained_model import ResourceFormat, RetainedFeature
from rich_terminal.retained_scene import ImageBody, ImageClip, ImageFit
from rich_terminal.retained_wire import RetainedMessageType

ARENA_BYTES = 8192
CHUNK = 16
FEED_BYTES = 64

# The clip of an IMAGE that shows all of its 6 by 2 rectangle.
WHOLE = ImageClip(0, 0, 6, 2)


class UploadHarness(cf._FeedHarness):
    def __init__(self, backend, *, images=True):
        fixture = cf._fixture_source(20).replace(
            b"CREATE CF-OWNERS-MEM RTAPT-OWNER-SIZE 7 + ALLOT",
            b"CREATE CF-OWNERS-MEM RTAPT-OWNER-SIZE 2 * 7 + ALLOT",
        ).replace(
            b"CF-SESSION CF-OWNERS RTAPT-OWNER-SIZE CF-OPS",
            b"CF-SESSION CF-OWNERS RTAPT-OWNER-SIZE 2 * CF-OPS",
        ).replace(
            b"CREATE CF-OPS-MEM RTAPT-OP-SIZE 7 + ALLOT",
            b"CREATE CF-OPS-MEM RTAPT-OP-SIZE 16 * 7 + ALLOT",
        ).replace(b"CREATE CF-COPY-MEM 15 ALLOT", b"CREATE CF-COPY-MEM 4103 ALLOT").replace(
            b"CF-OPS RTAPT-OP-SIZE", b"CF-OPS RTAPT-OP-SIZE 16 *",
        ).replace(b"CF-COPY 8 CF-LEDGER", b"CF-COPY 4096 CF-LEDGER")
        with patch.object(cf, "_fixture_source", return_value=fixture), patch.object(
            cf, "_load_exceptions", side_effect=lambda: _load_exceptions(
                MegaForthRuntime(execution_backend=backend))
        ):
            super().__init__(cf.SOURCE.read_bytes(), cols=20)
        self.runtime.evaluate((
            _word((RICH.parents[1] / "utils/string.f").read_text(), "/STRING")
            + "\n" + _clean(SOURCE) + "\n"
            + "\n".join(_clean((RICH / name).read_text()) for name in (
                "region-catalog.f", "family-batch.f", "provider-family.f")) + "\n"
            + _clean((RICH / "engine-apt1.f").read_text())
        ).encode(), source_name="production-neutral-apt1-bridge.f", step_budget=8_000_000)
        arena = self.runtime.define_created("UPL-ARENA", initial_body=bytes(ARENA_BYTES + 7))
        self.arena = (arena.body_address + 7) & -8
        self.used = 0
        base = cf._retained_policy()
        pictures = dict(
            features=RetainedFeature.CORE | RetainedFeature.RGBA_IMAGE,
            max_resources=4, max_resource_chunk_bytes=CHUNK,
            # Raw pixels and QOI files; no PNG or JPEG.
            total_resource_bytes=1024,
            image_formats=ResourceFormat.RGBA8.bit | ResourceFormat.QOI.bit,
            max_image_width=16, max_image_height=16,
        ) if images else dict(features=RetainedFeature.CORE)
        with patch.object(cf, "_retained_policy", return_value=replace(
            base, max_owner_records=2, max_live_owners=2, max_regions=4,
            max_objects=8, total_utf8_bytes=0, **pictures,
        )):
            self.attach()
        self.facade = self.allocate(bytes(self.constant("RTE-FACADE-SIZE")))
        assert self.call("RTAPTE-INIT", self.engine, self.facade)[0] == (0,)
        # The block every chunk is read into, and the bytes being sent.
        self.block = self.allocate(bytes(FEED_BYTES))
        self.sending = b""

    def allocate(self, payload):
        address = self.arena + self.used
        self.used += (len(payload) + 7) & -8
        assert self.used <= ARENA_BYTES
        self.runtime.memory.write_bytes(address, payload)
        return address

    def constant(self, name):
        return self.call(name)[0][0]

    def field(self, name, record):
        return self.runtime.memory.read64(self.call(name, record)[0][0])

    def wants(self):
        """The chunk the upload wants: its offset and the most it carries."""

        offset, most, status = self.call("RTAPT-RESOURCE-WANTS@", self.engine)[0]
        assert status == 0
        return offset, most

    def feed(self):
        """Read the chunk the upload wants into the block and hand it over."""

        offset, most = self.wants()
        assert most <= FEED_BYTES
        chunk = self.sending[offset:offset + most]
        self.runtime.memory.write_bytes(self.block, chunk)
        assert self.call("RTAPT-RESOURCE-FEED", self.block, len(chunk),
                         self.engine)[0] == (0,)
        # The block may change as soon as the chunk has gone.
        return chunk

    def settle(self, limit=256):
        """Step until nothing is outstanding, feeding each chunk the upload
        wants; return every status seen."""

        statuses = []
        wants = self.constant("RTAPT-JOB-WANTS")
        for _ in range(limit):
            if self.job()[0] == wants:
                self.feed()
            statuses.append(self.call("RTAPT-STEP", self.engine)[0][0])
            self.service()
            if (self.field("_RTAPT-E.ACTIVE-KIND", self.engine) == 0
                    and self.field("_RTAPT-E.QUEUE-HEAD", self.engine) == 0
                    and self.job()[0] not in (self.constant("RTAPT-JOB-QUEUED"),
                                              wants)):
                return statuses
        raise AssertionError("retained provider failed to settle")

    def open(self, owner, resources, resource_bytes):
        # Two regions and objects: a rebuild holds its own beside the shown.
        assert self.call("RTE-OWNER-OPEN", owner, 1, 2, resources, 2, 0,
                         resource_bytes, 0, 0, 0, self.facade)[0] == (0,)
        self.settle()
        assert self.call("RTAPT-OWNER-STATE@", owner, 1, self.engine)[0] == (
            self.constant("RTAPT-OWNER-ST-OPEN"), 0)

    def upload(self, resource, width, height, data=None, *, owner=1,
               format="RTAPT-PICTURE-RGBA8"):
        data = bytes((7 * i + resource) & 255 for i in range(width * height * 4)) \
            if data is None else data
        format = self.constant(format) if isinstance(format, str) else format
        status = self.call("RTAPT-RESOURCE-UPLOAD", owner, 1, resource, format,
                           width, height, len(data), self.engine)[0][0]
        if status == 0:
            self.sending = data
        return status, data

    def drop(self, resource, byte_length, *, owner=1):
        return self.call("RTAPT-RESOURCE-DROP", owner, 1, resource, byte_length,
                         self.engine)[0][0]

    def job(self):
        state, kind, resource, result, status = self.call(
            "RTAPT-JOB@", self.engine)[0]
        assert status == 0
        return state, kind, resource, result

    def clear(self):
        assert self.call("RTAPT-JOB-CLEAR", self.engine)[0] == (0,)

    def store(self, owner=1):
        count, used, high, status = self.call("RTAPT-OWNER-RESOURCES@", owner, 1,
                                              self.engine)[0]
        assert status == 0
        return count, used, high

    def terminal_resources(self):
        state = self.driver.core.resource_state
        return {key[2]: resource for key, resource in state.resources.items()}

    def terminal_usage(self, owner=1):
        usage = self.driver.core.resource_state.usage.get((owner, 1))
        return (0, 0) if usage is None else (usage.resources, usage.bytes)

    def valid(self):
        return self.call("RTAPT-VALID?", self.engine)[0] == (self.constant("TRUE"),)

    def begin(self, mode="PT-RET-REPLACE-START", *, region=1):
        assert self.call("RTAPT-RICH-BEGIN", self.constant(mode), self.engine)[0] == (0,)
        if mode == "PT-RET-REPLACE-START":
            assert self.call("RTAPT-REGION-DEFINE", 1, 1, region, 0, 0, 20, 2,
                             0, 0, 0, 0, 0, 1, self.engine)[0] == (0,)

    def publish(self, reveal=True):
        if reveal and self.field("_RTAPT-E.RET-MODE", self.engine) == self.constant(
                "PT-RET-REPLACE-START"):
            self.publish(reveal=False)
            self.begin("PT-RET-REPLACE-CONTINUE")
        assert self.call("RTAPT-RICH-SEAL", self.constant(
            "PT-COMMIT-AND-REVEAL" if reveal else "PT-COMMIT"), self.engine)[0] == (0,)
        assert self.call("RTAPT-CELL-BEGIN", 20, 2, 0, 0, 0,
                         self.constant("PT-CELL-DELTA"), self.engine)[0] == (0,)
        assert self.call("RTAPT-CELL-CURSOR", 0, 0, 0, self.engine)[0] == (0,)
        assert self.call("RTAPT-CELL-COMMIT", self.engine)[0] in ((0,), (1,))
        self.settle()

    def image(self, resource, *, identity=1, region=1, fit="RTAPT-IMAGE-FIT-CONTAIN",
              backdrop=-1, **changes):
        fields = dict(owner=1, generation=1, id=identity, visible=-1, z=0,
                      region=region, parent=0, row=0, col=2, height=2, width=6,
                      resource=resource, fit=self.constant(fit), opacity=255,
                      backdrop=backdrop, reserved=0, clip_x=0, clip_y=0,
                      clip_cols=0, clip_rows=0)
        fields.update(changes)
        return self.allocate(struct.pack("<20q", *fields.values()))

    def image_static(self, picture, *, identity=1, region=1,
                     fit_name="RTE-IMAGE-FIT-CONTAIN", backdrop=-1, **changes):
        """The neutral IMAGE static: a static record of kind IMAGE."""
        fields = dict(owner=1, generation=1, id=identity, kind=self.constant("RTE-STATIC-IMAGE"),
                      visible=-1, z=0, region=region, parent=0, row=0, col=2, height=2,
                      width=6, root_height=2, root_width=20, fit=self.constant(fit_name),
                      opacity=255, backdrop=backdrop, label_a=0, label_u=0, value_a=0,
                      value_u=0, resource=picture, clip_x=0, clip_y=0, clip_cols=0,
                      clip_rows=0)
        fields.update(changes)
        return self.allocate(struct.pack("<26q", *fields.values()))

    def shown(self, identity=1):
        return self.driver.core.retained_state.active.owners[1].objects[identity]

    def pixels(self):
        *answer, status = self.call("RTAPT-PIXELS@", self.engine)[0]
        return tuple(answer), status


@pytest.fixture(params=("python", "native"))
def harness(request):
    fixture = UploadHarness(request.param)
    try:
        yield fixture
    finally:
        fixture.close()


def test_an_upload_asks_for_each_chunk_and_sends_exactly_what_it_is_given(harness):
    """The engine holds none of an upload's bytes.  Once the terminal has
    begun the upload, the job wants each chunk in turn, says where it starts
    and how long it may be, and sends what it is fed; the caller reuses one
    block for every chunk."""

    harness.open(1, resources=2, resource_bytes=512)
    status, data = harness.upload(5, 5, 2)              # 40 bytes: 16, 16, 8
    assert status == 0
    c = harness.constant
    queued, wants = c("RTAPT-JOB-QUEUED"), c("RTAPT-JOB-WANTS")
    assert harness.job()[:2] == (queued, c("RTAPT-JOB-UPLOAD"))
    assert harness.call("RTAPT-WORK-PENDING?", harness.engine)[0] == (c("TRUE"),)
    # The ID is used at once; the store holds nothing until the commit.
    assert harness.store() == (0, 0, 5)
    # No chunk is wanted before the terminal has begun the upload.
    assert harness.call("RTAPT-RESOURCE-WANTS@", harness.engine)[0] == (
        0, 0, c("RTAPT-S-INVALID"))
    _until(harness, lambda: harness.job()[0] == wants)
    assert harness.driver.core.resource_upload is not None

    core = harness.driver.core
    chunks = core.frames_received_by_type.get(int(RetainedMessageType.RESOURCE_CHUNK), 0)
    for offset, most in ((0, 16), (16, 16), (32, 8)):
        assert harness.job()[0] == wants
        # A job waiting for its caller gives the step nothing to send.
        assert harness.call("RTAPT-WORK-PENDING?", harness.engine)[0] == (0,)
        assert harness.call("RTAPT-STEP", harness.engine)[0] == (0,)
        assert harness.wants() == (offset, most)
        assert harness.feed() == data[offset:offset + most]
        assert harness.job()[0] == queued
        _until(harness, lambda: harness.job()[0] != queued
               and harness.field("_RTAPT-E.ACTIVE-KIND", harness.engine) == 0)
        # The terminal took the chunk; the block is the caller's again.
        harness.runtime.memory.write_bytes(harness.block, bytes(FEED_BYTES))
    assert core.frames_received_by_type[int(RetainedMessageType.RESOURCE_CHUNK)] \
        == chunks + 3
    assert harness.job() == (c("RTAPT-JOB-DONE"), c("RTAPT-JOB-UPLOAD"), 5, 0)
    resource = harness.terminal_resources()[5]
    assert (resource.width, resource.height) == (5, 2)
    assert resource.read(0, len(data)) == data
    assert harness.store() == (1, 40, 5)
    assert harness.terminal_usage() == (1, 40)
    assert core.resource_upload is None
    assert harness.valid()
    harness.clear()
    assert harness.job() == (0, 0, 0, 0)


def test_a_chunk_the_upload_does_not_want_is_refused_and_nothing_is_taken(harness):
    harness.open(1, resources=2, resource_bytes=512)
    c = harness.constant
    invalid, wants = c("RTAPT-S-INVALID"), c("RTAPT-JOB-WANTS")

    def feed(address, length):
        return harness.call("RTAPT-RESOURCE-FEED", address, length,
                            harness.engine)[0][0]

    # Out of turn: with no job, while it is queued, and while BEGIN awaits.
    assert feed(harness.block, 4) == invalid
    status, data = harness.upload(3, 4, 3)               # 48 bytes
    assert status == 0
    assert feed(harness.block, 4) == invalid
    assert harness.call("RTAPT-STEP", harness.engine)[0] == (0,)
    assert harness.job()[0] == c("RTAPT-JOB-AWAITING")
    assert feed(harness.block, 4) == invalid
    _until(harness, lambda: harness.job()[0] == wants)
    assert harness.wants() == (0, 16)
    # Empty, longer than wanted, at no address, or inside the engine.
    for address, length in ((harness.block, 0), (harness.block, 17), (0, 4),
                            (harness.engine, 4)):
        assert feed(address, length) == invalid, (address, length)
        assert harness.job()[0] == wants
        assert harness.field("_RTAPT-E.JOB-A", harness.engine) == 0
    assert harness.valid()
    # A shorter chunk is a chunk: the next one starts where it ended.
    harness.runtime.memory.write_bytes(harness.block, data[:5])
    assert feed(harness.block, 5) == 0
    assert feed(harness.block, 5) == invalid             # once it is fed
    _until(harness, lambda: harness.job()[0] == wants)
    assert harness.wants() == (5, 16)
    harness.settle()
    assert harness.terminal_resources()[3].read(0, len(data)) == data
    assert harness.valid()


def _answered(harness):
    """Service and step until nothing awaits the terminal."""

    for _ in range(16):
        harness.service()
        harness.call("RTAPT-STEP", harness.engine)
        if (harness.field("_RTAPT-E.ACTIVE-KIND", harness.engine) == 0
                and harness.field("_RTAPT-E.UPDATE-STATE", harness.engine) == 0):
            return
    raise AssertionError("the terminal did not answer")


def test_only_an_update_starts_beside_an_upload(harness):
    harness.open(1, resources=2, resource_bytes=512)
    assert harness.upload(1, 8, 2)[0] == 0
    busy = harness.constant("RTAPT-S-BUSY")

    def refused():
        # No owner request, other job or clear starts beside the upload.
        assert harness.call("RTE-OWNER-OPEN", 2, 1, 1, 0, 2, 0, 0, 0, 0, 0,
                            harness.facade)[0] != (0,)
        assert harness.upload(2, 1, 1)[0] == busy
        assert harness.drop(1, 64) == busy
        assert harness.call("RTAPT-PIXELS-ASK", 0, 0, 20, 2,
                            harness.engine)[0] == (busy,)
        assert harness.call("RTAPT-JOB-CLEAR", harness.engine)[0] == (busy,)

    refused()
    # BEGIN goes out.  While one of the job's frames awaits its answer, no
    # update begins either.
    assert harness.call("RTAPT-STEP", harness.engine)[0] == (0,)
    assert harness.call("RTAPT-RICH-BEGIN", harness.constant("RTAPT-RICH-DELTA"),
                        harness.engine)[0] == (busy,)
    assert harness.call("RTAPT-CELL-BEGIN", 20, 2, 0, 0, 0,
                        harness.constant("PT-CELL-DELTA"), harness.engine)[0] == (busy,)
    refused()
    _answered(harness)
    assert harness.job()[0] == harness.constant("RTAPT-JOB-WANTS")
    refused()
    harness.settle()
    assert harness.job()[0] == harness.constant("RTAPT-JOB-DONE")
    # A finished job still holds the slot until it is cleared.
    assert harness.upload(2, 1, 1)[0] == busy
    harness.clear()
    assert harness.upload(2, 1, 1)[0] == 0
    harness.settle()
    assert harness.store() == (2, 68, 2)


def _until(harness, done):
    """Service and step until DONE holds."""

    for _ in range(16):
        harness.service()
        harness.call("RTAPT-STEP", harness.engine)
        if done():
            return
    raise AssertionError("the terminal did not answer")


def test_updates_run_between_an_upload_s_frames_and_take_turns_with_it(harness):
    """APT-1-RETAINED-1 section 8: complete transactions run between an
    upload's frames.  The two take turns: the step that takes an update's
    answer sends the upload's next frame, and the step that takes one of the
    upload's answers sends nothing, so the screen's next frame goes first."""

    harness.open(1, resources=2, resource_bytes=512)
    core = harness.driver.core
    busy = harness.constant("RTAPT-S-BUSY")
    awaiting = harness.constant("RTAPT-JOB-AWAITING")
    _uploaded(harness, 1, 1, 1)
    harness.begin()
    assert harness.call("RTAPT-IMAGE-DEFINE", harness.image(1),
                        harness.engine)[0] == (0,)
    harness.publish()
    status, data = harness.upload(2, 8, 2)              # 64 bytes: four chunks
    assert status == 0

    def received(kind):
        return core.frames_received_by_type.get(int(kind), 0)

    def resource_frames():
        return sum(received(kind) for kind in (
            RetainedMessageType.RESOURCE_BEGIN, RetainedMessageType.RESOURCE_CHUNK,
            RetainedMessageType.RESOURCE_COMMIT)) - before

    before = 0
    before, chunks = resource_frames(), received(RetainedMessageType.RESOURCE_CHUNK)

    def job_state():
        return harness.job()[0]

    def update_idle():
        return harness.field("_RTAPT-E.UPDATE-STATE", harness.engine) == 0

    def begins():
        rich = harness.call("RTAPT-RICH-BEGIN", harness.constant("PT-RET-DELTA"),
                            harness.engine)[0][0]
        cell = harness.call("RTAPT-CELL-BEGIN", 20, 2, 0, 0, 0,
                            harness.constant("PT-CELL-DELTA"), harness.engine)[0][0]
        return rich, cell

    def commit():
        # The job waits while the frame is open, and until it is answered.
        assert harness.call("RTAPT-STEP", harness.engine)[0] == (busy,)
        assert harness.call("RTAPT-CELL-CURSOR", 0, 0, 0, harness.engine)[0] == (0,)
        assert harness.call("RTAPT-CELL-COMMIT", harness.engine)[0] == (0,)
        _until(harness, update_idle)

    # A retained update begins before the upload's first frame.  It may show
    # a committed picture but never the one on its way, and the job waits
    # while the update is captured and sealed.
    presents = received(RetainedMessageType.PRESENT_COMMIT)
    harness.begin("PT-RET-DELTA")
    assert harness.call("RTAPT-IMAGE-REPLACE", harness.image(2),
                        harness.engine)[0] == (harness.constant("RTAPT-S-INVALID"),)
    assert harness.call("RTAPT-IMAGE-REPLACE", harness.image(
        1, fit="RTAPT-IMAGE-FIT-COVER"), harness.engine)[0] == (0,)
    assert harness.call("RTAPT-STEP", harness.engine)[0] == (0,)
    assert harness.call("RTAPT-RICH-SEAL", harness.constant("PT-COMMIT"),
                        harness.engine)[0] == (0,)
    assert harness.call("RTAPT-STEP", harness.engine)[0] == (0,)
    harness.service()
    assert resource_frames() == 0
    assert harness.call("RTAPT-CELL-BEGIN", 20, 2, 0, 0, 0,
                        harness.constant("PT-CELL-DELTA"), harness.engine)[0] == (0,)
    commit()
    assert received(RetainedMessageType.PRESENT_COMMIT) == presents + 1
    assert harness.shown().body == ImageBody(1, ImageFit.COVER, 255, True, WHOLE)
    # The step that took the update's answer sent the upload's first frame.
    assert job_state() == awaiting

    for turn in range(6):                               # BEGIN, 4 chunks, COMMIT
        # No update begins while the job's frame awaits its answer, and the
        # step that takes the answer sends nothing more.
        assert job_state() == awaiting
        assert begins() == (busy, busy)
        _until(harness, lambda: job_state() != awaiting)
        assert resource_frames() == turn + 1
        if turn == 5:
            break
        if turn < 4:
            # The upload wants its next chunk; once fed, it waits to be sent.
            assert job_state() == harness.constant("RTAPT-JOB-WANTS")
            harness.feed()
        assert job_state() == harness.constant("RTAPT-JOB-QUEUED")
        assert core.resource_upload is not None
        # The screen's turn: a frame runs while the upload stays open.
        assert harness.call("RTAPT-CELL-BEGIN", 20, 2, 0, 0, 0,
                            harness.constant("PT-CELL-DELTA"), harness.engine)[0] == (0,)
        commit()
        assert received(RetainedMessageType.PRESENT_COMMIT) == presents + 2 + turn
        assert resource_frames() == turn + 1

    assert harness.job() == (harness.constant("RTAPT-JOB-DONE"),
                             harness.constant("RTAPT-JOB-UPLOAD"), 2, 0)
    assert core.resource_upload is None
    assert received(RetainedMessageType.RESOURCE_CHUNK) == chunks + 4
    assert harness.terminal_resources()[2].read(0, len(data)) == data
    assert harness.valid()

    # The next frame may show the new picture; with the job over, updates
    # follow one another freely.
    harness.clear()
    harness.begin("PT-RET-DELTA")
    assert harness.call("RTAPT-IMAGE-REPLACE", harness.image(2),
                        harness.engine)[0] == (0,)
    harness.publish(reveal=False)
    assert harness.shown().body == ImageBody(2, ImageFit.CONTAIN, 255, True, WHOLE)
    for _ in range(2):
        assert harness.call("RTAPT-CELL-BEGIN", 20, 2, 0, 0, 0,
                            harness.constant("PT-CELL-DELTA"), harness.engine)[0] == (0,)
        commit()
    assert harness.valid()


def test_the_owner_reservation_bounds_what_it_may_upload(harness):
    harness.open(1, resources=1, resource_bytes=40)
    capacity = harness.constant("RTAPT-S-CAPACITY")
    invalid = harness.constant("RTAPT-S-INVALID")
    assert harness.upload(1, 4, 3)[0] == capacity       # 48 bytes > 40
    assert harness.upload(1, 3, 3)[0] == 0              # 36 bytes fit
    harness.settle()
    harness.clear()
    assert harness.upload(2, 1, 1)[0] == capacity       # one resource only
    # IDs only rise, and a picture must match its bytes and fit the terminal.
    harness.call("RTAPT-OWNER-RESIZE", 1, 1, 2, 2, 2, 0, 80, 0, 0, 0, harness.engine)
    harness.settle()
    assert harness.upload(1, 1, 1)[0] == invalid
    assert harness.upload(2, 17, 1)[0] == invalid
    assert harness.upload(2, 1, 1, bytes(5))[0] == invalid
    # Only formats the terminal takes, and a file has some bytes.
    file = qoi_codec.encode(_picture(1, 1))
    assert harness.upload(2, 1, 1, file, format="RTAPT-PICTURE-PNG")[0] == invalid
    assert harness.upload(2, 1, 1, file, format=5)[0] == invalid
    assert harness.upload(2, 1, 1, file, format=0)[0] == invalid
    assert harness.upload(2, 1, 1, b"", format="RTAPT-PICTURE-QOI")[0] == invalid
    assert harness.store() == (1, 36, 1)
    assert harness.valid()


def _picture(width, height, seed=0):
    return [[((x * 70 + seed) & 255, (y * 90 + seed) & 255, (x * y * 30) & 255,
              255 if (x + y) % 3 else 128) for x in range(width)]
            for y in range(height)]


def test_a_file_goes_as_it_is_and_the_owner_holds_its_decoded_size(harness):
    """A QOI file the terminal decodes is sent unchanged.  The owner is
    charged the decoded picture, here 48 bytes, though the file is longer,
    and the terminal holds exactly the file's pixels."""

    rows = _picture(4, 3)
    file = qoi_codec.encode(rows)
    assert len(file) > 48
    harness.open(1, resources=1, resource_bytes=48)
    status, _ = harness.upload(7, 4, 3, file, format="RTAPT-PICTURE-QOI")
    assert status == 0
    assert harness.settle()[-1] == 0
    assert harness.job() == (harness.constant("RTAPT-JOB-DONE"),
                             harness.constant("RTAPT-JOB-UPLOAD"), 7, 0)
    resource = harness.terminal_resources()[7]
    assert (resource.width, resource.height) == (4, 3)
    assert resource.read(0, 48) == qoi_codec.rgba_bytes(rows)
    assert harness.store() == (1, 48, 7)
    assert harness.terminal_usage() == (1, 48)
    assert harness.valid()
    harness.clear()

    # Dropping it gives the decoded size back.
    assert harness.drop(7, 48) == 0
    harness.settle()
    assert harness.store() == (0, 0, 7)
    assert harness.valid()


@pytest.mark.parametrize("declared", ((3, 3), (4, 2)))
def test_a_file_that_is_not_its_declared_picture_fails_and_charges_nothing(
        harness, declared):
    harness.open(1, resources=2, resource_bytes=512)
    file = qoi_codec.encode(_picture(4, 3))
    assert harness.upload(3, *declared, file, format="RTAPT-PICTURE-QOI")[0] == 0
    statuses = harness.settle()
    # The step that took the refusal reconciled it, so it and the engine's
    # status stay OK: an update prepared next is not refused for the job.
    assert all(status == 0 for status in statuses), statuses
    assert harness.call("RTAPT-UPDATE-STATE@", harness.engine)[0] == (
        harness.constant("RTAPT-UPDATE-IDLE"), 0)
    # The terminal refused the bytes themselves, which the outcome says.
    assert harness.job() == (harness.constant("RTAPT-JOB-FAILED"),
                             harness.constant("RTAPT-JOB-UPLOAD"), 3,
                             harness.constant("RTAPT-S-BAD-CONTENT"))
    assert 3 not in harness.terminal_resources()
    assert harness.store() == (0, 0, 3)
    assert harness.terminal_usage() == (0, 0)
    assert harness.valid()


def test_a_cancel_ends_an_upload_before_or_after_the_terminal_opens_it(harness):
    harness.open(1, resources=2, resource_bytes=512)
    rejected = harness.constant("RTAPT-S-REJECTED")
    failed = harness.constant("RTAPT-JOB-FAILED")
    frames = harness.driver.core.frames_received
    assert harness.upload(1, 4, 4)[0] == 0
    assert harness.call("RTAPT-RESOURCE-CANCEL", harness.engine)[0] == (0,)
    assert harness.job()[0::3] == (failed, rejected)
    assert harness.driver.core.frames_received == frames
    harness.clear()

    assert harness.upload(2, 4, 4)[0] == 0
    # BEGIN goes out and the terminal opens the upload.
    assert harness.call("RTAPT-STEP", harness.engine)[0] == (0,)
    assert harness.call("RTAPT-RESOURCE-CANCEL", harness.engine)[0] == (
        harness.constant("RTAPT-S-BUSY"),)
    harness.service()
    assert harness.call("RTAPT-STEP", harness.engine)[0] == (0,)
    # It waits for its first chunk and is aborted from there.
    assert harness.job()[0] == harness.constant("RTAPT-JOB-WANTS")
    assert harness.driver.core.resource_upload is not None
    assert harness.call("RTAPT-RESOURCE-CANCEL", harness.engine)[0] == (0,)
    assert harness.job()[0] == harness.constant("RTAPT-JOB-QUEUED")
    harness.settle()
    assert harness.job()[0::3] == (failed, rejected)
    assert harness.driver.core.resource_upload is None
    assert 2 not in harness.terminal_resources()
    assert harness.store() == (0, 0, 2)
    assert harness.valid()
    harness.clear()

    # A chunk fed but not yet sent is dropped with the upload.
    core = harness.driver.core
    assert harness.upload(3, 4, 4)[0] == 0
    _until(harness, lambda: harness.job()[0] == harness.constant("RTAPT-JOB-WANTS"))
    chunks = core.frames_received_by_type.get(int(RetainedMessageType.RESOURCE_CHUNK), 0)
    harness.feed()
    assert harness.call("RTAPT-RESOURCE-CANCEL", harness.engine)[0] == (0,)
    assert harness.field("_RTAPT-E.JOB-A", harness.engine) == 0
    assert harness.valid()
    harness.settle()
    assert harness.job()[0::3] == (failed, rejected)
    assert core.frames_received_by_type.get(
        int(RetainedMessageType.RESOURCE_CHUNK), 0) == chunks
    assert core.resource_upload is None
    assert 3 not in harness.terminal_resources()
    assert harness.valid()


def test_a_drop_gives_the_usage_back_and_a_resize_the_reservation(harness):
    harness.open(1, resources=2, resource_bytes=200)
    assert harness.upload(1, 4, 4)[0] == 0
    harness.settle()
    harness.clear()
    assert harness.upload(2, 2, 2)[0] == 0
    harness.settle()
    harness.clear()
    assert harness.store() == (2, 80, 2)

    assert harness.drop(1, 64) == 0
    harness.settle()
    assert harness.job() == (harness.constant("RTAPT-JOB-DONE"),
                             harness.constant("RTAPT-JOB-DROP"), 1, 0)
    harness.clear()
    assert 1 not in harness.terminal_resources()
    assert harness.store() == (1, 16, 2)
    assert harness.terminal_usage() == (1, 16)

    # The reservation may now drop to what is used, never below it.
    invalid = harness.constant("RTAPT-S-INVALID")
    assert harness.call("RTAPT-OWNER-RESIZE", 1, 1, 2, 0, 2, 0, 16, 0, 0, 0,
                        harness.engine)[0] == (invalid,)
    assert harness.call("RTAPT-OWNER-RESIZE", 1, 1, 2, 1, 2, 0, 15, 0, 0, 0,
                        harness.engine)[0] == (invalid,)
    assert harness.call("RTAPT-OWNER-RESIZE", 1, 1, 2, 1, 2, 0, 16, 0, 0, 0,
                        harness.engine)[0] == (0,)
    harness.settle()
    quotas = harness.driver.core.owner_state.records[1].quotas
    assert (quotas.resources, quotas.resource_bytes) == (1, 16)

    # A drop of something the owner does not hold fails at the terminal.
    assert harness.drop(9, 16) == invalid               # above the high-water
    assert harness.drop(1, 16) == 0                     # already dropped
    harness.settle()
    assert harness.job()[3] == invalid
    assert harness.store() == (1, 16, 2)
    assert harness.valid()


def _uploaded(harness, resource, width, height):
    status, data = harness.upload(resource, width, height)
    assert status == 0
    harness.settle()
    assert harness.job()[0] == harness.constant("RTAPT-JOB-DONE")
    harness.clear()
    return data


def test_an_image_shows_a_committed_picture_in_its_rectangle(harness):
    harness.open(1, resources=2, resource_bytes=512)
    _uploaded(harness, 1, 4, 3)
    _uploaded(harness, 2, 2, 2)
    harness.begin()
    assert harness.call("RTAPT-IMAGE-DEFINE", harness.image(1),
                        harness.engine)[0] == (0,)
    # The copy is the descriptor; the frame is APT-1's header and payload,
    # with the clip every IMAGE carries.
    assert harness.field("_RTAPT-E.OP-COUNT", harness.engine) == 2
    assert harness.field("_RTAPT-E.COPY-USED", harness.engine) == 104 + 160
    assert harness.field("_RTAPT-E.RET-BYTES", harness.engine) == 104 + 136
    harness.publish()
    shown = harness.shown()
    assert shown.body == ImageBody(1, ImageFit.CONTAIN, 255, True, WHOLE)
    assert (shown.bounds.cell_x, shown.bounds.cell_y,
            shown.bounds.cell_cols, shown.bounds.cell_rows) == (2, 0, 6, 2)
    assert harness.valid()

    # A replacement may show another picture, scaled another way.
    harness.begin("PT-RET-DELTA")
    assert harness.call("RTAPT-IMAGE-REPLACE", harness.image(
        2, fit="RTAPT-IMAGE-FIT-COVER", backdrop=0, opacity=128),
        harness.engine)[0] == (0,)
    harness.publish(reveal=False)
    assert harness.shown().body == ImageBody(2, ImageFit.COVER, 128, False, WHOLE)
    assert harness.valid()


def test_an_image_shows_only_the_part_its_clip_names(harness):
    harness.open(1, resources=1, resource_bytes=512)
    _uploaded(harness, 1, 4, 3)
    harness.begin()
    assert harness.call("RTAPT-IMAGE-DEFINE", harness.image(
        1, row=-1, clip_y=1, clip_cols=6, clip_rows=1), harness.engine)[0] == (0,)
    # A clip changes nothing a frame counts: every IMAGE carries one.
    assert harness.field("_RTAPT-E.RET-BYTES", harness.engine) == 104 + 136
    harness.publish()
    shown = harness.shown()
    assert shown.body == ImageBody(1, ImageFit.CONTAIN, 255, True, ImageClip(0, 1, 6, 1))
    assert (shown.bounds.cell_y, shown.bounds.cell_rows) == (-1, 2)
    assert harness.valid()


def test_an_image_names_a_committed_resource_and_exact_fields(harness):
    harness.open(1, resources=2, resource_bytes=512)
    invalid = harness.constant("RTAPT-S-INVALID")
    harness.begin()
    # Nothing is committed yet, and no upload may start while a candidate
    # is open.
    assert harness.call("RTAPT-IMAGE-DEFINE", harness.image(1),
                        harness.engine)[0] == (invalid,)
    assert harness.upload(1, 1, 1)[0] == harness.constant("RTAPT-S-BUSY")
    assert harness.call("RTAPT-RICH-CANCEL", harness.engine)[0] == (0,)
    _uploaded(harness, 1, 1, 1)
    harness.begin()
    for changes in (dict(resource=2), dict(resource=0), dict(fit=3),
                    dict(opacity=256), dict(backdrop=1), dict(visible=2),
                    dict(parent=5), dict(reserved=1), dict(width=0),
                    dict(height=1 << 32), dict(col=1 << 31), dict(id=0),
                    # A clip has positive extents inside the 6 by 2 rectangle.
                    dict(clip_x=1), dict(clip_cols=6), dict(clip_cols=7, clip_rows=2),
                    dict(clip_y=1, clip_cols=6, clip_rows=2)):
        record = harness.image(1)
        for name, value in changes.items():
            offset = ("owner generation id visible z region parent row col height "
                      "width resource fit opacity backdrop reserved clip_x clip_y "
                      "clip_cols clip_rows").split().index(name)
            harness.runtime.memory.write64(record + 8 * offset, value & (2**64 - 1))
        assert harness.call("RTAPT-IMAGE-DEFINE", record,
                            harness.engine)[0] == (invalid,), changes
    # A region must come first in the same candidate.
    assert harness.call("RTAPT-IMAGE-DEFINE", harness.image(1, region=2),
                        harness.engine)[0] == (invalid,)
    assert harness.field("_RTAPT-E.OP-COUNT", harness.engine) == 1
    # A replacement names an image the owner already shows.
    assert harness.call("RTAPT-IMAGE-REPLACE", harness.image(1),
                        harness.engine)[0] == (invalid,)
    # Without the feature nothing is captured.
    limits = harness.call("_RTAPT-E.LIMITS", harness.engine)[0][0]
    features = harness.call("_RTAPT-L.FEATURES", limits)[0][0]
    saved = harness.runtime.memory.read64(features)
    harness.runtime.memory.write64(
        features, saved & ~harness.constant("RTAPT-F-IMAGE") & (2**64 - 1))
    assert harness.call("RTAPT-IMAGE-DEFINE", harness.image(1),
                        harness.engine)[0] == (harness.constant("RTAPT-S-UNSUPPORTED"),)
    harness.runtime.memory.write64(features, saved)
    assert harness.call("RTAPT-IMAGE-DEFINE", harness.image(1),
                        harness.engine)[0] == (0,)
    assert harness.valid()


def test_a_shown_picture_is_dropped_only_after_a_publication_stops_showing_it(harness):
    harness.open(1, resources=2, resource_bytes=512)
    _uploaded(harness, 1, 4, 3)
    harness.begin()
    assert harness.call("RTAPT-IMAGE-DEFINE", harness.image(1),
                        harness.engine)[0] == (0,)
    harness.publish()

    assert harness.drop(1, 48) == 0
    statuses = harness.settle()
    # The refusal is the job's outcome, not the engine's status.
    assert all(status == 0 for status in statuses), statuses
    assert harness.call("RTAPT-UPDATE-STATE@", harness.engine)[0] == (
        harness.constant("RTAPT-UPDATE-IDLE"), 0)
    assert harness.job()[0::3] == (harness.constant("RTAPT-JOB-FAILED"),
                                   harness.constant("RTAPT-S-BUSY"))
    assert 1 in harness.terminal_resources()
    assert harness.store() == (1, 48, 1)
    harness.clear()

    # IDs only rise, so the rebuild without the picture takes a new region.
    harness.begin(region=2)
    harness.publish()
    assert not harness.driver.core.retained_state.active.owners[1].objects
    assert harness.drop(1, 48) == 0
    harness.settle()
    assert harness.job()[0] == harness.constant("RTAPT-JOB-DONE")
    assert harness.store() == (0, 0, 1)
    assert harness.terminal_usage() == (0, 0)
    assert harness.valid()


def test_a_pixel_question_is_answered_for_the_selected_sink(harness):
    harness.driver.core.select_sink_cell_pixels((8, 16))
    busy = harness.constant("RTAPT-S-BUSY")
    invalid = harness.constant("RTAPT-S-INVALID")
    assert harness.pixels() == ((0, 0, 0), invalid)
    assert harness.call("RTAPT-PIXELS-ASK", 0, 0, 20, 2, harness.engine)[0] == (0,)
    assert harness.job()[:2] == (harness.constant("RTAPT-JOB-QUEUED"),
                                 harness.constant("RTAPT-JOB-PIXELS"))
    assert harness.pixels()[1] == busy
    # The question holds the engine like any job until it is answered.
    assert harness.call("RTAPT-STEP", harness.engine)[0] == (0,)
    assert harness.call("RTAPT-RICH-BEGIN", harness.constant("RTAPT-RICH-DELTA"),
                        harness.engine)[0] == (busy,)
    assert harness.call("RTAPT-PIXELS-ASK", 0, 0, 1, 1, harness.engine)[0] == (busy,)
    harness.settle()
    generation = harness.driver.core.geometry_generation
    assert harness.pixels() == ((generation, 160, 32), 0)
    query = harness.job()[2]
    assert query != 0
    assert harness.call("RTAPT-JOB-CLEAR", harness.engine)[0] == (0,)
    assert harness.pixels() == ((0, 0, 0), invalid)

    # Negative corners echo exactly; each question takes a new ID.
    assert harness.call("RTAPT-PIXELS-ASK", -1 & (2**64 - 1), -2 & (2**64 - 1),
                        3, 1, harness.engine)[0] == (0,)
    harness.settle()
    assert harness.pixels() == ((generation, 24, 16), 0)
    assert harness.job()[2] == query + 1
    harness.clear()

    # Without a pixel raster the terminal answers zero.
    harness.driver.core.select_sink_cell_pixels(None)
    assert harness.call("RTAPT-PIXELS-ASK", 0, 0, 20, 2, harness.engine)[0] == (0,)
    harness.settle()
    assert harness.pixels() == ((generation, 0, 0), 0)
    harness.clear()

    for bad in ((0, 0, 0, 1), (0, 0, 1, 0), (1 << 31, 0, 1, 1), (0, 0, 1 << 32, 1)):
        assert harness.call("RTAPT-PIXELS-ASK", *bad, harness.engine)[0] == (invalid,)
    assert harness.valid()


@pytest.mark.parametrize("backend", ("python", "native"))
def test_a_terminal_without_pictures_refuses_every_job(backend):
    harness = UploadHarness(backend, images=False)
    try:
        unsupported = harness.constant("RTAPT-S-UNSUPPORTED")
        harness.open(1, resources=0, resource_bytes=0)
        assert harness.call("RTAPT-PIXELS-ASK", 0, 0, 20, 2,
                            harness.engine)[0] == (unsupported,)
        assert harness.upload(1, 1, 1)[0] == unsupported
        assert harness.job() == (0, 0, 0, 0)
        assert harness.valid()
    finally:
        harness.close()


def test_the_neutral_facade_carries_every_picture_call(harness):
    harness.driver.core.select_sink_cell_pixels((8, 16))
    facade = harness.facade
    c = harness.constant
    harness.open(1, resources=2, resource_bytes=512)

    def job():
        *fields, status = harness.call("RTE-JOB@", facade)[0]
        assert status == c("RTE-S-OK")
        return tuple(fields)

    assert harness.call("RTE-PIXELS-ASK", 0, 0, 20, 2, facade)[0] == (0,)
    assert job()[:2] == (c("RTE-JOB-QUEUED"), c("RTE-JOB-PIXELS"))
    assert harness.call("RTE-PIXELS@", facade)[0][3] == c("RTE-S-WOULD-BLOCK")
    harness.settle()
    assert harness.call("RTE-PIXELS@", facade)[0] == (
        harness.driver.core.geometry_generation, 160, 32, c("RTE-S-OK"))
    assert harness.call("RTE-JOB-CLEAR", facade)[0] == (0,)

    data = bytes(range(48))
    invalid = c("RTE-S-INVALID")
    raw = c("RTE-PICTURE-RGBA8")
    assert harness.call("RTE-RESOURCE-UPLOAD", 1, 1, 1, raw, 4, 3, 0,
                        facade)[0] == (invalid,)
    assert harness.call("RTE-RESOURCE-UPLOAD", 1, 1, 1, 9, 4, 3, 48,
                        facade)[0] == (invalid,)
    assert job() == (c("RTE-JOB-NONE"), 0, 0, 0)
    assert harness.call("RTE-RESOURCE-WANTS@", facade)[0] == (0, 0, invalid)
    # The facade's limits say which formats the terminal takes.
    limits = harness.allocate(bytes(c("RTE-LIMITS-SIZE")))
    assert harness.call("RTE-LIMITS@", limits, facade)[0] == (0,)
    assert harness.call("RTE-LIMITS-IMAGE-FORMATS@", limits)[0] == (0b11,)
    assert [harness.call("RTE-LIMITS-PICTURE?", c(name), limits)[0][0] != 0
            for name in ("RTE-PICTURE-RGBA8", "RTE-PICTURE-QOI",
                         "RTE-PICTURE-PNG", "RTE-PICTURE-JPEG")] == [
        True, True, False, False]
    assert harness.call("RTE-RESOURCE-UPLOAD", 1, 1, 1, raw, 4, 3, 48,
                        facade)[0] == (0,)
    harness.sending = data
    # An update waits while one of the job's frames awaits its answer.
    assert harness.call("RTAPT-STEP", harness.engine)[0] == (0,)
    assert harness.call("RTE-RETAINED-BEGIN", c("RTE-RETAINED-REPLACE-START"),
                        facade)[0] == (c("RTE-S-WOULD-BLOCK"),)
    _until(harness, lambda: job()[0] == c("RTE-JOB-WANTS"))
    # The facade says which chunk the upload wants and hands it over.
    assert harness.call("RTE-RESOURCE-WANTS@", facade)[0] == (0, 16, c("RTE-S-OK"))
    harness.runtime.memory.write_bytes(harness.block, data[:16])
    for address, length in ((harness.block, 0), (harness.block, 17),
                            (facade, 16)):
        assert harness.call("RTE-RESOURCE-FEED", address, length,
                            facade)[0] == (invalid,)
    assert harness.call("RTE-RESOURCE-FEED", harness.block, 16, facade)[0] == (0,)
    assert job()[0] == c("RTE-JOB-QUEUED")
    harness.settle()
    assert job() == (c("RTE-JOB-DONE"), c("RTE-JOB-UPLOAD"), 1, 0)
    assert harness.terminal_resources()[1].read(0, 48) == data
    assert harness.call("RTE-JOB-CLEAR", facade)[0] == (0,)

    # A file the terminal refuses is the source's failure.
    file = qoi_codec.encode(_picture(4, 3))
    assert harness.call("RTE-RESOURCE-UPLOAD", 1, 1, 2, c("RTE-PICTURE-QOI"), 3, 3,
                        len(file), facade)[0] == (0,)
    harness.sending = file
    harness.settle()
    assert job() == (c("RTE-JOB-FAILED"), c("RTE-JOB-UPLOAD"), 2, c("RTE-S-SOURCE"))
    assert harness.call("RTE-JOB-CLEAR", facade)[0] == (0,)

    assert harness.call("RTE-RETAINED-BEGIN", c("RTE-RETAINED-REPLACE-START"),
                        facade)[0] == (0,)
    assert harness.call("RTE-REGION-DEFINE", 1, 1, 1, 0, 0, 20, 2, 0, 0, 0, 0, 0,
                        1, facade)[0] == (0,)
    # An IMAGE static: a bad fit, text, or no resource never reaches the
    # provider.
    for changes in (dict(fit=3), dict(label_u=1), dict(resource=0), dict(height=0),
                    dict(clip_x=1), dict(clip_cols=7, clip_rows=1)):
        assert harness.call("RTE-STATIC-DEFINE", harness.image_static(1, **changes),
                            facade)[0] == (invalid,), changes
    # The bridge carries its clip to the provider.
    assert harness.call("RTE-STATIC-DEFINE", harness.image_static(
        1, clip_x=2, clip_cols=4, clip_rows=2), facade)[0] == (0,)
    harness.publish()
    assert harness.shown().body == ImageBody(1, ImageFit.CONTAIN, 255, True,
                                             ImageClip(2, 0, 4, 2))

    assert harness.call("RTE-RESOURCE-DROP", 1, 1, 1, 48, facade)[0] == (0,)
    harness.settle()
    assert job() == (c("RTE-JOB-FAILED"), c("RTE-JOB-DROP"), 1,
                     c("RTE-S-WOULD-BLOCK"))
    assert harness.call("RTE-JOB-CLEAR", facade)[0] == (0,)
    assert harness.call("RTE-RESOURCE-CANCEL", facade)[0] == (invalid,)
    assert harness.valid()
