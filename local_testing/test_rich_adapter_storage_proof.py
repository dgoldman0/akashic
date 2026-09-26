"""Execute the production adapter-span proofs on both guest executors.

The authority and screen proofs share one enclose-then-split prover. Each
query seam models protected half-open ranges and invalid source state and
never dereferences query ranges, just like the unchanged storage APIs.
Production span enumeration, enclosure admission and exact fallback execute
against real adapter fields; a Python interval oracle checks their result.
"""

import random
import re
import struct

import pytest

from test_rich_glyph_growth import GrowthHarness, MASK64
from test_rich_terminal_control_map import MegaForthRuntime, ROOT, _definitions


SOURCE = ROOT / "akashic/tui/rich-terminal/uidl-hybrid-adapter.f"
SPANS = (
    "RECORDS", "WORK", "WORK-TEXT", "COLLECTION-VALIDATION", "COLLECTION-WORK",
    "SNAP-DIRECTORY", "SNAP-RECORDS", "SNAP-TEXT", "SNAP-DESCRIPTORS",
    "SNAP-NATIVE", "SNAP-DGRAPH-DESCRIPTORS", "SNAP-DGRAPH-NATIVE",
)
# Proof entry and the storage query it encloses.
PROOFS = {
    "authority": ("_RUHA-STORAGE-DISJOINT-CURRENT?",
                  "_RUHA-CURRENT-AUTHORITY-DISJOINT?"),
    "screen": ("_RUHA-SCREEN-STORAGE-DISJOINT?", "SCR-STORAGE-DISJOINT?"),
}


class StorageHarness(GrowthHarness):
    def __init__(self, backend, proof="authority", source=None):
        self.runtime = MegaForthRuntime(execution_backend=backend)
        self.entry, query = PROOFS[proof]
        self.definitions = _definitions(SOURCE.read_text() if source is None else source)
        self.definitions.update(_definitions(f"""
VARIABLE PROOF-QUERIES
VARIABLE PROOF-AUTHORITY-VALID
VARIABLE PROOF-PROTECTED-A
VARIABLE PROOF-PROTECTED-U
VARIABLE PROOF-EXTRA-RANGES
VARIABLE PROOF-EXTRA-COUNT
VARIABLE PROOF-QUERY-A
VARIABLE PROOF-QUERY-U
: {query} ( address bytes -- flag )
    1 PROOF-QUERIES +!
    DUP PROOF-QUERY-U ! OVER PROOF-QUERY-A !
    OVER 0= OVER 0> 0= OR IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    PROOF-AUTHORITY-VALID @ 0= IF 2DROP 0 EXIT THEN
    2DUP PROOF-PROTECTED-A @ PROOF-PROTECTED-U @ MSPAN-OVERLAP?
        IF 2DROP 0 EXIT THEN
    PROOF-EXTRA-COUNT @ 0 ?DO
        2DUP PROOF-EXTRA-RANGES @ I 16 * + DUP @ SWAP 8 + @
        MSPAN-OVERLAP? IF 2DROP 0 UNLOOP EXIT THEN
    LOOP 2DROP -1 ;
: PROOF-IN-LOOP ( adapter -- flag counter-sum )
    -1 0 3 0 DO
        2 PICK {self.entry} ROT AND SWAP R@ +
    LOOP ROT DROP ;
"""))
        chunks, seen = [], set()

        def include(name):
            if name in seen:
                return
            seen.add(name)
            declaration = self.definitions[name]
            code = re.sub(r"\\[^\n]*|\([^)]*\)", "", declaration)
            for token in code.split():
                if token != name and token in self.definitions:
                    include(token)
            chunks.append(declaration)

        include("PROOF-IN-LOOP")
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=3_000_000)
        self.serial = 0
        self.storage = self.allocate(b"LEFTGUAR" + bytes(self.constant("RUHA-SIZE"))
                                     + b"RIGHTGUA")
        self.adapter = self.storage + 8
        self.arena = self.allocate(b"untouched" * 1024)
        self.buffers = [(self.arena + i * 256, 64) for i in range(len(SPANS))]
        self.protected = (0, 0)
        self.extra_protected = []
        self.authority_valid = True

    def check(self, *, loop=False):
        for name, (address, length) in zip(SPANS, self.buffers):
            self.field(self.adapter, f"_RUHA-A.{name}-A", address & MASK64)
            self.field(self.adapter, f"_RUHA-A.{name}-U", length & MASK64)
        self.variable("PROOF-QUERIES", 0)
        self.variable("PROOF-AUTHORITY-VALID", MASK64 if self.authority_valid else 0)
        self.variable("PROOF-PROTECTED-A", self.protected[0])
        self.variable("PROOF-PROTECTED-U", self.protected[1])
        extras = b"".join(struct.pack("<2Q", *span) for span in self.extra_protected)
        self.variable("PROOF-EXTRA-RANGES", self.allocate(extras) if extras else 0)
        self.variable("PROOF-EXTRA-COUNT", len(self.extra_protected))
        before = self.runtime.memory.read_bytes(self.storage, self.constant("RUHA-SIZE") + 16)
        arena_before = self.runtime.memory.read_bytes(self.arena, 9 * 1024)
        result = self.results("PROOF-IN-LOOP" if loop else self.entry, self.adapter)
        assert len(result) == (2 if loop else 1)
        if loop:
            assert result[1] == 3  # R@ still observes the enclosing DO counter.
        spans = self.buffers + [(self.adapter, self.constant("RUHA-SIZE"))]
        expected = self.authority_valid and all(
            a != 0 and 0 < u < 1 << 63 and a + u <= MASK64
            and all(not (pu and a < pa + pu and pa < a + u)
                    for pa, pu in [self.protected, *self.extra_protected])
            for a, u in spans
        )
        assert result[0] == (MASK64 if expected else 0)
        assert self.runtime.memory.read_bytes(self.storage, len(before)) == before
        assert self.runtime.memory.read_bytes(self.arena, len(arena_before)) == arena_before
        assert self.variable("_RUHA-SAFE-LOW") == 0
        assert self.variable("_RUHA-SAFE-END") == 0
        for name in ("_RUHA-SAFE-HIGH", "_RUHA-SAFE-FIRST", "_RUHA-SAFE-LAST",
                     "_RUHA-SAFE-PROOF"):
            if self.runtime.find(name) is not None:
                assert self.variable(name) == 0
        # Each rejected node splits between actual starts. A complete binary
        # tree has at most 2*n-1 queries, independent of address spacing.
        assert self.variable("PROOF-QUERIES") <= (3 if loop else 1) * (2 * len(spans) - 1)
        return expected, self.variable("PROOF-QUERIES")


@pytest.fixture(params=[(backend, proof) for proof in PROOFS
                        for backend in ("python", "native")],
                ids=lambda param: "-".join(param))
def harness(request):
    backend, proof = request.param
    return StorageHarness(backend, proof)


def test_clustered_storage_uses_one_complete_query(harness):
    assert harness.check() == (True, 1)
    assert harness.variable("PROOF-QUERY-A") == harness.adapter
    assert harness.variable("PROOF-QUERY-U") == harness.buffers[-1][0] + 64 - harness.adapter


def test_interleaved_authority_splits_without_owning_gap(harness):
    harness.protected = (harness.arena + 64, 192)
    accepted, queries = harness.check()
    assert accepted and 1 < queries < 14


@pytest.mark.parametrize("index", range(13))
def test_every_buffer_and_descriptor_rejects_actual_overlap(harness, index):
    spans = harness.buffers + [(harness.adapter, harness.constant("RUHA-SIZE"))]
    harness.protected = (spans[index][0] + 1, 1)
    assert not harness.check()[0]


@pytest.mark.parametrize("invalid", [(0, 64), (1, 0), (1, -1), (MASK64 - 7, 8),
                                     (1, 1 << 63)])
def test_invalid_individual_span_cannot_hide_in_valid_enclosure(harness, invalid):
    harness.buffers[7] = invalid
    assert harness.check() == (False, 0)


def test_enclosure_larger_than_signed_count_uses_valid_individual_ranges(harness):
    harness.buffers[-1] = (MASK64 - 128, 64)
    assert harness.check() == (True, 2)


def test_invalid_authority_fails_closed(harness):
    harness.authority_valid = False
    assert not harness.check()[0]


def test_proof_reobserves_mutated_buffers_and_authority(harness):
    assert harness.check() == (True, 1)
    harness.protected = (harness.arena + 256, 64)
    assert not harness.check()[0]
    harness.buffers[1] = (harness.arena + 320, 64)
    assert harness.check()[0]
    harness.authority_valid = False
    assert not harness.check()[0]
    harness.authority_valid = True
    harness.protected = (0, 0)
    assert harness.check() == (True, 1)


@pytest.mark.parametrize("fallback", (False, True))
def test_enclosing_do_loop_survives_all_predicate_return_paths(harness, fallback):
    if fallback:
        harness.protected = (harness.arena + 64, 192)
    accepted, queries = harness.check(loop=True)
    assert accepted and (3 < queries < 42 if fallback else queries == 3)
    harness.protected = (harness.arena, 1)
    assert not harness.check(loop=True)[0]


def test_seeded_unsorted_and_nested_ranges_match_individual_interval_oracle(harness):
    randomizer = random.Random(0xADAF7E)
    for _ in range(60):
        harness.buffers = [(harness.arena + randomizer.randrange(512),
                            randomizer.randrange(1, 96)) for _ in SPANS]
        harness.protected = (harness.arena + randomizer.randrange(768),
                             randomizer.randrange(48))
        harness.check()


@pytest.mark.parametrize("reorder", (False, True))
def test_two_distant_allocations_need_three_queries_regardless_of_field_order(harness, reorder):
    harness.buffers[6:] = [(a + (1 << 24), u) for a, u in harness.buffers[6:]]
    harness.protected = (harness.arena + (1 << 16), 128)
    if reorder:
        random.Random(4102).shuffle(harness.buffers)
    assert harness.check() == (True, 3)


def test_equal_starts_query_the_longest_actual_span_and_terminate(harness):
    harness.buffers = [(harness.adapter, 8 * (i + 1)) for i in range(len(SPANS))]
    assert harness.check() == (True, 1)
    harness.protected = (harness.adapter + harness.constant("RUHA-SIZE") - 1, 1)
    assert harness.check() == (False, 1)


def test_split_never_clips_a_span_crossing_the_start_partition(harness):
    harness.buffers = [(harness.arena + i, 1) for i in range(len(SPANS))]
    harness.buffers[0] = (harness.arena, 4096)
    harness.protected = (harness.arena + 2048, 1)
    assert not harness.check()[0]
    harness.buffers[0] = (harness.arena, 2048)
    assert harness.check()[0]


def test_adjacent_high_bit_starts_split_without_midpoint_wrap(harness):
    first = MASK64 - 32
    harness.buffers = [(first + i * 2, 1) for i in range(len(SPANS))]
    harness.protected = (first + 1, 1)
    assert harness.check()[0]
    harness.protected = (first + 2, 1)
    assert not harness.check()[0]


def test_every_gap_protected_visits_both_children_and_reaches_query_bound(harness):
    spans = sorted(harness.buffers + [(harness.adapter, harness.constant("RUHA-SIZE"))])
    harness.extra_protected = [(a + u, b - a - u)
                               for (a, u), (b, _) in zip(spans, spans[1:])]
    assert all(u > 0 for _, u in harness.extra_protected)
    assert harness.check(loop=True) == (True, 3 * (2 * len(spans) - 1))
    harness.protected = (harness.buffers[6][0] + 1, 1)
    assert not harness.check(loop=True)[0]
