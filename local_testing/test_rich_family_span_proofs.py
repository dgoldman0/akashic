"""A batch's spans are proved apart from provider storage by enclosure.

Family admission and family emission ask the provider's storage-disjoint
callback about one range covering every nonempty span, and fall back to one
query per span only when that range is refused. The answer must be exactly
the per-span one. A provider here rejects one chosen range and counts its
queries, so each case shows both the answer and which route gave it.
"""
import pytest

from test_rich_terminal_family_batch import Families
from test_rich_terminal_status_static import RICH, _clean

PROVIDER = """
VARIABLE PR-A VARIABLE PR-U VARIABLE PR-QUERIES
: PR-DISJOINT ( a u context -- flag )
    DROP 1 PR-QUERIES +! PR-A @ PR-U @ MSPAN-OVERLAP? 0= ;
"""


class SpanProofs(Families):
    def __init__(self, backend):
        super().__init__(backend)
        # The emission reads the switch for every-frame checks, which the
        # static engine has loaded (check-mode.f).
        self.runtime.evaluate(
            (_clean((RICH / "shell-family-emit.f").read_text()) + PROVIDER).encode(),
            source_name="production-family-emit.f", step_budget=8_000_000)
        # The facade's storage-disjoint callback (offset 40) becomes PR-DISJOINT.
        self.cell(self.facade + 40, self.runtime.find("PR-DISJOINT").xt)

    def protect(self, address, length):
        self.variable("PR-A", address)
        self.variable("PR-U", length)
        self.variable("PR-QUERIES", 0)

    def batch_spans(self, batch):
        count, = self.call("RTE-FAMILY-BATCH-SPAN-COUNT", batch)
        found = []
        for index in range(count):
            address, length = self.call("RTE-FAMILY-BATCH-SPAN@", index, batch)
            if length:
                found.append((address, length))
        return found

    def admit(self, batch, out):
        flag, = self.call("_RTE-FA-AUTHORITY?", batch, out, self.shell)
        return flag != 0, self.variable("PR-QUERIES")

    def emit(self, batch):
        flag, = self.call("_RTE-FEM-AUTHORITY?", batch, self.shell)
        return flag != 0, self.variable("PR-QUERIES")


@pytest.fixture(scope="module", params=("python", "native"))
def proofs(request):
    return SpanProofs(request.param)


@pytest.mark.parametrize("route", ("admit", "emit"))
def test_one_query_proves_every_span_when_their_enclosure_is_clear(proofs, route):
    batch, out, *_ = proofs.graph(mixed=True)
    # Protected storage below every span: the enclosure is clear.
    proofs.protect(proofs.facade, 8)
    accepted, queries = getattr(proofs, route)(*((batch, out) if route == "admit" else (batch,)))
    assert accepted
    spans = proofs.batch_spans(batch)
    assert len(spans) > 10
    # The fixed checks of the shell and its records, plus one for the spans.
    assert queries < len(spans)


@pytest.mark.parametrize("route", ("admit", "emit"))
def test_storage_between_spans_falls_back_to_the_per_span_answer(proofs, route):
    batch, out, *_ = proofs.graph(mixed=True)
    spans = sorted(proofs.batch_spans(batch))
    # The guard bytes after the lowest span lie inside the enclosure but
    # outside every span: the enclosure is refused and each span passes.
    address, length = spans[0]
    gap = address + length
    assert all(not (a <= gap < a + u) for a, u in spans)
    proofs.protect(gap, 1)
    accepted, queries = getattr(proofs, route)(*((batch, out) if route == "admit" else (batch,)))
    assert accepted
    assert queries > len(spans)


@pytest.mark.parametrize("route", ("admit", "emit"))
def test_storage_overlapping_a_span_is_refused(proofs, route):
    batch, out, *_ = proofs.graph(mixed=True)
    spans = sorted(proofs.batch_spans(batch))
    address, length = spans[len(spans) // 2]
    proofs.protect(address + length - 1, 1)
    accepted, _ = getattr(proofs, route)(*((batch, out) if route == "admit" else (batch,)))
    assert not accepted
