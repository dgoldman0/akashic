"""Keep the facts a DELTA comparison proves about the bank it builds.

The production comparison words run on seeded guest banks.  A comparison
proves its pending bank canonical, normalizes its object IDs, and keeps those
facts beside it.  When that bank is acknowledged and compared again as the
active bank, the kept facts must give exactly the result of the complete
audit: the same control map, identity index, slot map, base, and visible count.
"""

from __future__ import annotations

import random
import struct

import pytest

from test_rich_glyph_growth import GrowthHarness, MASK64


COLS, ROWS, MAX_CONTROLS = 8, 4, 16


def _identity(randomizer: random.Random) -> tuple[int, ...]:
    return tuple(randomizer.getrandbits(64) for _ in range(6))


class FactsHarness(GrowthHarness):
    def __init__(self, backend, *, producer_source=None):
        super().__init__(backend, producer_source=producer_source, extra_words=(
            "_RTHP-D-BUILD-CONTROL-MAP?", "_RTHP-D-TRY-GLYPH-LAYOUT?",
            "_RTHP-D-NORMALIZE", "_RTHP-D-KEEP-FACTS", "_RTHP-FACTS-PUBLISH",
            "_RTHP-D-KEPT?", "_RTHP-TARGET-ABORT"))
        self.item = self.constant("RTE-GLYPH-RUN-PLAN-ITEM-SIZE")
        self.control = self.constant("RTE-CONTROL-SIZE")
        self.correlation = self.constant("RUCP-CORRELATION-SIZE")
        self.header = self.constant("_RTHP-TARGET-BANK-HEADER-SIZE")
        self.producer = self.allocate(bytes(self.constant("RTHP-SIZE")))
        for name, value in (("_RTHP.MAX-COLS", COLS), ("_RTHP.MAX-ROWS", ROWS),
                            ("_RTHP.MAX-CONTROLS", MAX_CONTROLS),
                            ("_RTHP.MAX-DOCUMENTS", 1), ("_RTHP.MAX-TEXT", 8)):
            self.field(self.producer, name, value)
        self.bank_bytes, valid = self.results("_RTHP-TARGET-BANK-BYTES?", self.producer)
        assert valid == MASK64
        order2 = MAX_CONTROLS * 24
        annex = MAX_CONTROLS * 8
        glyph_map = COLS * ROWS * 8
        total = 2 * self.bank_bytes + order2 + 2 * annex + glyph_map
        self.arena = self.allocate(bytes(total))
        self.banks = (self.arena, self.arena + self.bank_bytes)
        self.order2 = self.arena + 2 * self.bank_bytes
        self.annexes = (self.order2 + order2, self.order2 + order2 + annex)
        self.glyph_map = self.annexes[1] + annex
        for name, value in (("_RTHP.ARENA-A", self.arena), ("_RTHP.ARENA-U", total),
                            ("_RTHP.TARGET0-A", self.banks[0]),
                            ("_RTHP.TARGET1-A", self.banks[1]),
                            ("_RTHP.ORDER2-A", self.order2), ("_RTHP.ORDER2-U", order2),
                            ("_RTHP.FACTS-INDEX0-A", self.annexes[0]),
                            ("_RTHP.FACTS-INDEX1-A", self.annexes[1]),
                            ("_RTHP.FACTS-INDEX-U", annex),
                            ("_RTHP.GLYPH-ID-MAP-A", self.glyph_map),
                            ("_RTHP.GLYPH-ID-MAP-U", glyph_map)):
            self.field(self.producer, name, value)

    def read(self, base, name):
        return self.runtime.memory.read64(base + self.offset(name))

    def facts(self, role):
        base = self.producer + self.offset(f"_RTHP.{role}-FACTS")
        return tuple(self.runtime.memory.read64(base + 8 * i) for i in range(6))

    def seed(self, bank, first, graph, source, runs, slots):
        """Write a fresh candidate: controls in GRAPH order, correlations in
        SOURCE order, then visible runs and invisible reserves up to SLOTS."""
        memory = self.runtime.memory
        memory.write_bytes(bank, bytes(self.bank_bytes))
        count = len(graph)
        for name, value in (("_RTHP-TB.COLS", COLS), ("_RTHP-TB.ROWS", ROWS),
                            ("_RTHP-TB.CONTROL-COUNT", count),
                            ("_RTHP-TB.GLYPH-SLOT-COUNT", slots),
                            ("_RTHP-TB.REGION", 900 + first),
                            ("_RTHP-TB.FIRST-OBJECT", first)):
            self.field(bank, name, value)
        controls = bank + self.header
        correlations = controls + count * self.control
        for ordinal in range(count):
            self.field(controls + ordinal * self.control, "_RTE-CONTROL.ID", first + ordinal)
        for position, identity in enumerate(source):
            ordinal = graph.index(identity)
            cells = (*identity[:4], first + ordinal, *identity[4:])
            memory.write_bytes(correlations + position * self.correlation,
                               struct.pack("<7Q", *cells))
        items = correlations + count * self.correlation
        refs = items + slots * self.item
        text = refs + slots * 16
        used = 0
        for index in range(slots):
            visible = index < len(runs)
            row, col, label = runs[index] if visible else (0, 0, b"")
            fields = (first + count + index, 0, row, col, 1, 1, ROWS, COLS, 0,
                      MASK64 if visible else 0, 0, 0, 0, len(label), 0)
            memory.write_bytes(items + index * self.item, struct.pack("<15Q", *fields))
            memory.write_bytes(refs + index * 16, struct.pack("<2Q", used, len(label)))
            memory.write_bytes(text + used, label)
            used += len(label)
        self.field(bank, "_RTHP-TB.GLYPH-TEXT-USED", used)

    def begin(self, active, pending, kept):
        for name, value in (("_RTHP-D-P", self.producer), ("_RTHP-D-ACTIVE", active),
                            ("_RTHP-D-PENDING", pending),
                            ("_RTHP-D-ACTIVE-FIRST", self.read(active, "_RTHP-TB.FIRST-OBJECT")),
                            ("_RTHP-D-PENDING-FIRST", self.read(pending, "_RTHP-TB.FIRST-OBJECT")),
                            ("_RTHP-D-OPS", 0), ("_RTHP-D-KEPT", MASK64 if kept else 0)):
            self.variable(name, value)

    def maps(self, active, pending, kept):
        """Both maps built from ACTIVE, with everything they derive about it."""
        self.begin(active, pending, kept)
        memory = self.runtime.memory
        controls = self.read(pending, "_RTHP-TB.CONTROL-COUNT")
        active_controls = self.read(active, "_RTHP-TB.CONTROL-COUNT")
        joined = self.call("_RTHP-D-BUILD-CONTROL-MAP?")
        result = [joined]
        if joined:
            index = self.variable("_RTHP-D-INDEX-A")
            result += [memory.read_bytes(self.order2, controls * 8),
                       memory.read_bytes(index, active_controls * 8)]
            mapped = self.call("_RTHP-D-BUILD-SLOT-MAP?")
            result.append(mapped)
            if mapped:
                slots = self.variable("_RTHP-D-SLOTS")
                result += [memory.read_bytes(self.glyph_map, slots * 8),
                           *(self.variable("_RTHP-D-" + name) for name in
                             ("ACTIVE-VISIBLE", "GLYPH-BASE", "SLOTS", "ACTIVE-SLOTS"))]
        return result

    def finish(self, pending):
        """Complete the comparison the production way and keep its facts."""
        if not self.call("_RTHP-D-TRY-GLYPH-LAYOUT?"):
            if not self.call("_RTHP-D-NORMALIZE-GLYPH-IDS?"):
                return False
            for index in range(self.read(pending, "_RTHP-TB.GLYPH-SLOT-COUNT")):
                if not self.call("_RTHP-D-GLYPH-COMPATIBLE-AND-MARK?", index):
                    return False
        if not self.call("_RTHP-D-NORMALIZE"):
            return False
        assert self.results("_RTHP-D-KEEP-FACTS") == ()
        return True

    def publish(self, bank):
        self.variable("_RTHP-TP-P", self.producer)
        self.variable("_RTHP-TP-BANK", bank)
        assert self.results("_RTHP-FACTS-PUBLISH") == ()
        memory = self.runtime.memory
        controls = self.read(bank, "_RTHP-TB.CONTROL-COUNT")
        slots = self.read(bank, "_RTHP-TB.GLYPH-SLOT-COUNT")
        items = bank + self.header + controls * (self.control + self.correlation)
        ids = [memory.read64(bank + self.header + i * self.control + self.offset("_RTE-CONTROL.ID"))
               for i in range(controls)]
        ids += [memory.read64(items + i * self.item) for i in range(slots)]
        frontier = max([self.read(self.producer, "_RTHP.NEXT-OBJECT"), *(i + 1 for i in ids)])
        self.field(self.producer, "_RTHP.NEXT-OBJECT", frontier)


@pytest.fixture(params=("python", "native"))
def harness(request):
    return FactsHarness(request.param)


def _frames(seed, count):
    """A seeded edit stream: text, moves, growth, shrinking, and new controls."""
    randomizer = random.Random(seed)
    identities = [_identity(randomizer) for _ in range(3)]
    cells = [(row, col) for row in range(ROWS) for col in range(COLS)]
    runs = {cell: b"A" for cell in randomizer.sample(cells, 6)}
    for _ in range(count):
        edit = randomizer.randrange(6)
        if edit == 0 and len(identities) < MAX_CONTROLS:
            identities.append(_identity(randomizer))
        elif edit == 1:
            free = [cell for cell in cells if cell not in runs]
            runs[randomizer.choice(free)] = b"N"
        elif edit == 2 and len(runs) > 1:
            del runs[randomizer.choice(sorted(runs))]
        elif edit == 3:
            cell = randomizer.choice(sorted(runs))
            free = [other for other in cells if other not in runs]
            runs[randomizer.choice(free)] = runs.pop(cell)
        for cell in randomizer.sample(sorted(runs), min(2, len(runs))):
            runs[cell] = bytes([65 + randomizer.randrange(26)])
        graph = identities.copy()
        source = identities.copy()
        randomizer.shuffle(graph)
        randomizer.shuffle(source)
        yield graph, source, sorted((row, col, label) for (row, col), label in runs.items())


@pytest.mark.parametrize("seed", range(6))
def test_kept_facts_give_exactly_the_complete_audit_over_an_edit_stream(harness, seed):
    active, pending = harness.banks
    harness.field(harness.producer, "_RTHP.NEXT-OBJECT", 100)
    kept_comparisons = fallbacks = 0
    started = False
    for graph, source, runs in _frames(seed, 40):
        first = harness.read(harness.producer, "_RTHP.NEXT-OBJECT")
        slots = len(runs)
        if started:
            slots = max(slots, harness.read(active, "_RTHP-TB.GLYPH-SLOT-COUNT"))
        harness.seed(pending, first, graph, source, runs, slots)
        if not started:
            # A full START bank has no kept facts.
            harness.publish(pending)
            assert harness.facts("ACTIVE")[0] == 0
            active, pending, started = pending, active, True
            continue
        harness.begin(active, pending, False)
        kept = harness.call("_RTHP-D-KEPT?")
        audited = harness.maps(active, pending, False)
        if kept:
            kept_comparisons += 1
            assert harness.maps(active, pending, True) == audited
        ok = audited[0] and audited[3] and harness.finish(pending)
        if ok:
            facts = harness.facts("PENDING")
            assert facts[0] == pending
            harness.publish(pending)
            assert harness.facts("ACTIVE") == facts
        else:
            # The comparison refused; publish a fresh START in its place.
            fallbacks += 1
            harness.seed(pending, first, graph, source, runs, len(runs))
            harness.publish(pending)
            assert harness.facts("ACTIVE")[0] == 0
        assert harness.facts("PENDING")[0] == 0
        active, pending = pending, active
    assert kept_comparisons >= 20
    assert fallbacks < kept_comparisons


def test_kept_facts_match_a_fresh_audit_of_the_normalized_bank(harness):
    """The facts equal what the audit itself derives from the kept bank."""
    active, pending = harness.banks
    randomizer = random.Random(7)
    identities = [_identity(randomizer) for _ in range(4)]
    runs = [(0, 1, b"A"), (0, 3, b"B"), (2, 0, b"C")]
    harness.field(harness.producer, "_RTHP.NEXT-OBJECT", 100)
    harness.seed(active, 100, identities, identities[::-1], runs, 3)
    harness.publish(active)
    grown = [*runs[:2], (1, 5, b"D"), (2, 0, b"E")]
    harness.seed(pending, 107, identities[::-1], identities, grown, 4)
    assert harness.maps(active, pending, False)[3]
    assert harness.finish(pending)
    bank, base, visible, slots, controls, last = harness.facts("PENDING")
    assert (bank, visible, slots, controls) == (pending, 4, 4, 4)
    harness.publish(pending)
    # Compare the new active bank against a third candidate, fully audited.
    harness.seed(active, 112, identities, identities, grown, 4)
    harness.maps(pending, active, False)
    assert harness.variable("_RTHP-D-GLYPH-BASE") == base
    assert harness.variable("_RTHP-D-ACTIVE-VISIBLE") == visible
    audited_index = harness.runtime.memory.read_bytes(harness.variable("_RTHP-D-INDEX-A"), 32)
    assert audited_index == harness.runtime.memory.read_bytes(harness.annexes[1], 32)
    ids = [harness.runtime.memory.read64(pending + harness.header + i * harness.control
                                         + harness.offset("_RTE-CONTROL.ID"))
           for i in range(4)]
    assert last == max(ids)


def _published_pair(harness):
    active, pending = harness.banks
    randomizer = random.Random(11)
    identities = [_identity(randomizer) for _ in range(2)]
    runs = [(0, 0, b"A"), (1, 1, b"B")]
    harness.field(harness.producer, "_RTHP.NEXT-OBJECT", 100)
    harness.seed(active, 100, identities, identities, runs, 2)
    harness.publish(active)
    harness.seed(pending, 104, identities, identities, runs, 2)
    assert harness.maps(active, pending, False)[3]
    assert harness.finish(pending)
    harness.publish(pending)
    harness.seed(active, 108, identities, identities, runs, 2)
    return pending, active, identities


def test_kept_facts_apply_only_to_their_exact_bank_and_counts(harness):
    active, pending, _ = _published_pair(harness)
    harness.begin(active, pending, False)
    assert harness.call("_RTHP-D-KEPT?")
    facts = harness.producer + harness.offset("_RTHP.ACTIVE-FACTS")
    memory = harness.runtime.memory
    for cell, value in ((0, pending), (3, 3), (4, 3)):
        saved = memory.read64(facts + cell * 8)
        memory.write64(facts + cell * 8, value)
        assert not harness.call("_RTHP-D-KEPT?")
        memory.write64(facts + cell * 8, saved)
    assert harness.call("_RTHP-D-KEPT?")


def test_kept_path_still_proves_the_id_permutation_and_namespace(harness):
    active, pending, identities = _published_pair(harness)
    memory = harness.runtime.memory
    controls = harness.read(active, "_RTHP-TB.CONTROL-COUNT")
    items = active + harness.header + controls * (harness.control + harness.correlation)
    saved = memory.read64(items + harness.item)
    memory.write64(items + harness.item, memory.read64(items))
    result = harness.maps(active, pending, True)
    assert result[0] and not result[3]
    memory.write64(items + harness.item, saved)
    assert harness.maps(active, pending, True)[3]
    # A candidate namespace that starts at a kept ID is refused by both paths.
    last = harness.facts("ACTIVE")[5]
    harness.seed(pending, last, identities, identities, [(0, 0, b"A"), (1, 1, b"B")], 2)
    assert not harness.maps(active, pending, True)[0]
    assert not harness.maps(active, pending, False)[0]
    harness.seed(pending, last + 1, identities, identities, [(0, 0, b"A"), (1, 1, b"B")], 2)
    assert harness.maps(active, pending, True)[0]


def test_abort_drops_pending_facts_and_other_publications_drop_active_facts(harness):
    active, pending, identities = _published_pair(harness)
    assert harness.facts("ACTIVE")[0] == active
    harness.maps(active, pending, True)
    assert harness.finish(pending)
    assert harness.facts("PENDING")[0] == pending
    assert harness.results("_RTHP-TARGET-ABORT", harness.producer) == ()
    assert harness.facts("PENDING")[0] == 0
    assert harness.facts("ACTIVE")[0] == active
    # A bank published without facts of its own leaves none active.
    harness.publish(pending)
    assert harness.facts("ACTIVE")[0] == 0
