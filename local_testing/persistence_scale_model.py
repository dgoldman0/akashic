#!/usr/bin/env python3
"""Bounded analytical reference model for the L11 persistence mechanics.

This module deliberately models counts and page geometry, not a synthetic
corpus.  A million documents and tens of millions of dependent records remain
integers throughout the model.  The only sampled values are explicitly capped,
fixed-seed ranks used to exercise deep positions.

The page arithmetic mirrors the neutral L10 store contract: a 4096-byte page
contains a 64-byte checked-record envelope and a 4032-byte opaque payload.  L11
owns the B+tree node layout inside that payload.  None of the types below has
Library vocabulary in its storage mechanics.  The named seven-index profile is
an explicit L12 target projection used to size the neutral L11 mechanisms; it
is not a claim that L11's create-only five-index adapter already implements the
complete Library repository.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from heapq import heappop, heappush
from random import Random


PAGE_BYTES = 4096
CHECKED_RECORD_ENVELOPE_BYTES = 64
CHECKED_ENVELOPE_BYTES = CHECKED_RECORD_ENVELOPE_BYTES
PAGE_PAYLOAD_BYTES = PAGE_BYTES - CHECKED_RECORD_ENVELOPE_BYTES
SEGMENT_ALIGNMENT_BYTES = 8
ATOMIC_ROOT_RECORD_BYTES = 160

NODE_HEADER_BYTES = 64
CELL_BYTES = 8
PAGE_ID_BYTES = CELL_BYTES
MAX_BTREE_HEIGHT = 9

BTREE_KEY_MAX_BYTES = 256
BTREE_VALUE_MAX_BYTES = 64
LEAF_ENTRY_BYTES = 2 * CELL_BYTES + BTREE_KEY_MAX_BYTES + BTREE_VALUE_MAX_BYTES
BRANCH_ENTRY_BYTES = 2 * CELL_BYTES + BTREE_KEY_MAX_BYTES
LEAF_CAPACITY = (PAGE_PAYLOAD_BYTES - NODE_HEADER_BYTES) // LEAF_ENTRY_BYTES
BRANCH_CAPACITY = (PAGE_PAYLOAD_BYTES - NODE_HEADER_BYTES) // BRANCH_ENTRY_BYTES

BLOB_CHUNK_BYTES = 32 * 1024
BLOB_WORKSPACE_BYTES = 46_936
LIBRARY_INDEX_WORKSPACE_BYTES = 84_624
MAX_ANALYTIC_SAMPLES = 256
MAX_RECLAIM_BATCH = 32
MAX_RETIRED_PAGES_PER_TRANSACTION = 64
MAX_ALLOCATED_PAGES_PER_TRANSACTION = 128
MAX_DISCARDED_PAGES_PER_TRANSACTION = 64
RECLAIM_MAINTENANCE_MAX_PAGE_WRITES_PER_STEP = 1

LIBRARY_DOCUMENTS = 1_000_000
LIBRARY_REVISIONS = 10_000_000
LIBRARY_EDGES = 10_000_000
LIBRARY_INDEX_SLICE_MAX = 32


def _ceil_div(numerator: int, denominator: int) -> int:
    if numerator < 0:
        raise ValueError("numerator must be non-negative")
    if denominator <= 0:
        raise ValueError("denominator must be positive")
    return (numerator + denominator - 1) // denominator


def _align_up(value: int, alignment: int) -> int:
    return _ceil_div(value, alignment) * alignment


@dataclass(frozen=True, slots=True)
class BTreeGeometry:
    """Exact fixed-slot capacity inside one checked 4096-byte page.

    The production btree stores canonical fixed-width slots even when a
    particular Library index uses shorter keys or values.  Leaves hold key and
    value lengths plus the maximum key/value bytes.  Branches hold one child,
    one high-key length and the maximum key bytes.  Consequently every current
    profile has the same conservative 11-entry leaf and 14-child branch
    fanout; the per-index widths below prove only that its values fit.
    """

    key_bytes: int
    inline_value_bytes: int

    def __post_init__(self) -> None:
        if self.key_bytes <= 0:
            raise ValueError("key_bytes must be positive")
        if self.key_bytes > BTREE_KEY_MAX_BYTES:
            raise ValueError("key_bytes exceeds the production btree maximum")
        if self.inline_value_bytes < 0:
            raise ValueError("inline_value_bytes must be non-negative")
        if self.inline_value_bytes > BTREE_VALUE_MAX_BYTES:
            raise ValueError("inline_value_bytes exceeds the production btree maximum")

    @property
    def leaf_entry_bytes(self) -> int:
        return LEAF_ENTRY_BYTES

    @property
    def branch_entry_bytes(self) -> int:
        return BRANCH_ENTRY_BYTES

    @property
    def leaf_capacity(self) -> int:
        return LEAF_CAPACITY

    @property
    def branch_separator_capacity(self) -> int:
        return BRANCH_CAPACITY

    @property
    def branch_fanout(self) -> int:
        return self.branch_separator_capacity

    @property
    def minimum_leaf_occupancy(self) -> int:
        """Non-root leaf occupancy preserved by split and delete balancing."""

        return (self.leaf_capacity + 1) // 2

    @property
    def minimum_branch_fanout(self) -> int:
        """Non-root branch occupancy preserved by split and delete balancing."""

        return self.branch_fanout // 2

    def capacity_for_height(self, height: int) -> int:
        """Return the theoretical fully packed capacity for one height."""

        if height < 1:
            raise ValueError("height must include at least the root/leaf page")
        return self.leaf_capacity * self.branch_fanout ** (height - 1)

    def balanced_capacity_for_height(self, height: int) -> int:
        """Return the cardinality guaranteed to fit without another root split.

        This is deliberately smaller than fully packed capacity.  A leaf
        overflow splits 12 entries into 6/6 and a branch overflow splits 15
        children into 7/8.  With delete-side borrow/merge preserving those
        non-root minima, the next root-split thresholds are 12, 90, 636, ...;
        therefore heights one through nine safely contain 11, 89, 635, ...
        live entries for every insertion order and subsequent balanced churn.
        """

        if height < 1:
            raise ValueError("height must include at least the root/leaf page")
        next_root_split = self.leaf_capacity + 1
        for _ in range(1, height):
            next_root_split = (
                next_root_split * self.minimum_branch_fanout
                + self.minimum_leaf_occupancy
            )
        return next_root_split - 1

    def minimum_cardinality_for_height(self, height: int) -> int:
        """Return the first monotonic-build cardinality requiring this height."""

        if height < 1:
            raise ValueError("height must include at least the root/leaf page")
        if height == 1:
            return 1
        return self.balanced_capacity_for_height(height - 1) + 1

    def monotonic_build_height_for(self, cardinality: int) -> int:
        """Return the insertion-threshold height without materializing nodes."""

        if cardinality < 0:
            raise ValueError("cardinality must be non-negative")
        if cardinality == 0:
            return 0
        wanted = cardinality
        height = 1
        while self.balanced_capacity_for_height(height) < wanted:
            height += 1
            if height > MAX_BTREE_HEIGHT:
                raise ValueError("cardinality exceeds the production height limit")
        return height

    def minimum_resident_cardinality(self, height: int) -> int:
        """Minimum live rows in a balanced tree that retains ``height`` levels.

        Deletion keeps every non-root leaf at least six rows full and every
        non-root branch at least seven children full, while a branch root may
        retain two children.  A tree that first grew at 90 rows can therefore
        remain height three after shrinking to 84 rows.  This resident-tree
        bound, rather than the insertion threshold, governs worst-case lookup
        and storage costs after churn.
        """

        if height < 1 or height > MAX_BTREE_HEIGHT:
            raise ValueError("height must be within the production limit")
        if height == 1:
            return 1
        return (
            2
            * self.minimum_leaf_occupancy
            * self.minimum_branch_fanout ** (height - 2)
        )

    def height_for(self, cardinality: int) -> int:
        """Return the maximum legal current height after balanced churn."""

        if cardinality < 0:
            raise ValueError("cardinality must be non-negative")
        if cardinality == 0:
            return 0
        if cardinality > self.balanced_capacity_for_height(MAX_BTREE_HEIGHT):
            raise ValueError("cardinality exceeds the production height limit")
        height = 1
        for candidate in range(2, MAX_BTREE_HEIGHT + 1):
            if self.minimum_resident_cardinality(candidate) > cardinality:
                break
            height = candidate
        return height

    def point_page_reads(self, cardinality: int) -> int:
        """A cold point lookup reads exactly one page at each tree level."""

        return self.height_for(cardinality)

    def leaf_pages(self, cardinality: int) -> int:
        """Return the fully packed lower bound for a complete leaf scan."""

        if cardinality < 0:
            raise ValueError("cardinality must be non-negative")
        return _ceil_div(cardinality, self.leaf_capacity)

    def page_count_upper_bound(self, cardinality: int) -> int:
        """Bound all pages in the tallest balanced tree retained after churn."""

        if cardinality < 0:
            raise ValueError("cardinality must be non-negative")
        if cardinality == 0:
            return 0
        height = self.height_for(cardinality)
        if height == 1:
            return 1
        # With a fixed cardinality and minimum occupancy, floor division is the
        # maximum number of non-root pages.  Iterate the selected resident
        # height exactly; stopping as soon as a level fits below the root would
        # incorrectly model only a freshly built tree and miss retained height.
        level_pages = cardinality // self.minimum_leaf_occupancy
        total_pages = level_pages
        for _ in range(height - 2):
            level_pages //= self.minimum_branch_fanout
            total_pages += level_pages
        return total_pages + 1  # the root


@dataclass(frozen=True, slots=True)
class IndexProfile:
    name: str
    cardinality: int
    geometry: BTreeGeometry

    def __post_init__(self) -> None:
        if not self.name:
            raise ValueError("index name must not be empty")
        if self.cardinality < 0:
            raise ValueError("index cardinality must be non-negative")

    @property
    def height(self) -> int:
        return self.geometry.height_for(self.cardinality)

    @property
    def point_page_reads(self) -> int:
        return self.geometry.point_page_reads(self.cardinality)

    @property
    def page_count_upper_bound(self) -> int:
        return self.geometry.page_count_upper_bound(self.cardinality)

    @property
    def storage_bytes_upper_bound(self) -> int:
        return self.page_count_upper_bound * PAGE_BYTES


@dataclass(frozen=True, slots=True)
class LibraryScaleProfile:
    """Scalar-only description of the large Library proving workload."""

    documents: int
    revisions: int
    edges: int
    indexes: tuple[IndexProfile, ...]
    materialized_target_items: int = 0

    def index(self, name: str) -> IndexProfile:
        for profile in self.indexes:
            if profile.name == name:
                return profile
        raise KeyError(name)


# These are the exact Library-owned key/value widths layered over the neutral
# fixed-slot tree.  Scope lives in the tree/root descriptors rather than being
# repeated in every key.  Directory/history values are 24-byte PERSIST-REFs;
# ordered indexes carry the stable 32-byte RID; an edge needs no value because
# both endpoint identities are present in its key.
DOCUMENT_BY_RID_GEOMETRY = BTreeGeometry(key_bytes=32, inline_value_bytes=24)
DOCUMENT_BY_CREATION_GEOMETRY = BTreeGeometry(key_bytes=40, inline_value_bytes=32)
REVISION_BY_DOCUMENT_GEOMETRY = BTreeGeometry(key_bytes=40, inline_value_bytes=24)
EDGE_BY_SUBJECT_GEOMETRY = BTreeGeometry(key_bytes=64, inline_value_bytes=0)
# The applet encodes 129 order symbols (128 title bytes plus an explicit
# terminator) as one MSB-first 9-bit stream, then appends the 32-byte RID.
# ceil(129 * 9 / 8) + 32 = 178 bytes.  This keeps embedded U+0000 and prefix
# titles distinct without narrowing the existing Library text contract.
TITLE_BY_BYTES_GEOMETRY = BTreeGeometry(key_bytes=178, inline_value_bytes=32)
LIFECYCLE_ORDER_GEOMETRY = BTreeGeometry(key_bytes=41, inline_value_bytes=32)


LARGE_LIBRARY_PROFILE = LibraryScaleProfile(
    documents=LIBRARY_DOCUMENTS,
    revisions=LIBRARY_REVISIONS,
    edges=LIBRARY_EDGES,
    indexes=(
        IndexProfile(
            "record-directory",
            LIBRARY_DOCUMENTS + LIBRARY_REVISIONS + LIBRARY_EDGES,
            DOCUMENT_BY_RID_GEOMETRY,
        ),
        IndexProfile("document-by-rid", LIBRARY_DOCUMENTS, DOCUMENT_BY_RID_GEOMETRY),
        IndexProfile(
            "document-by-creation",
            LIBRARY_DOCUMENTS,
            DOCUMENT_BY_CREATION_GEOMETRY,
        ),
        IndexProfile(
            "revision-by-document",
            LIBRARY_REVISIONS,
            REVISION_BY_DOCUMENT_GEOMETRY,
        ),
        IndexProfile("edge-by-subject", LIBRARY_EDGES, EDGE_BY_SUBJECT_GEOMETRY),
        IndexProfile(
            "title-by-bytes",
            LIBRARY_DOCUMENTS,
            TITLE_BY_BYTES_GEOMETRY,
        ),
        IndexProfile(
            "lifecycle-order",
            LIBRARY_DOCUMENTS,
            LIFECYCLE_ORDER_GEOMETRY,
        ),
    ),
)


def library_large_profile() -> LibraryScaleProfile:
    """Return the immutable profile; target cardinalities are never expanded."""

    return LARGE_LIBRARY_PROFILE


def sample_ranks(cardinality: int, sample_count: int = 64, seed: int = 0xA5A51C11) -> tuple[int, ...]:
    """Return a bounded deterministic rank sample from an arbitrarily large range."""

    if cardinality < 0:
        raise ValueError("cardinality must be non-negative")
    if sample_count < 0 or sample_count > MAX_ANALYTIC_SAMPLES:
        raise ValueError(f"sample_count must be between 0 and {MAX_ANALYTIC_SAMPLES}")
    count = min(cardinality, sample_count)
    if count == 0:
        return ()
    # random.sample has a range-specialized path; memory is proportional to the
    # explicitly bounded sample, never to cardinality.
    return tuple(sorted(Random(seed).sample(range(cardinality), count)))


@dataclass(frozen=True, slots=True)
class OperationWorkspace:
    """Caller-owned scratch reserved once per store/operation context."""

    page_buffer_bytes: int = 4 * PAGE_BYTES
    path_stack_bytes: int = MAX_BTREE_HEIGHT * 16
    key_scratch_bytes: int = BTREE_KEY_MAX_BYTES
    value_scratch_bytes: int = BTREE_VALUE_MAX_BYTES
    split_key_scratch_bytes: int = BTREE_KEY_MAX_BYTES
    allocated_page_ids_bytes: int = (2 * MAX_BTREE_HEIGHT + 1) * PAGE_ID_BYTES
    mutation_control_bytes: int = 5 * CELL_BYTES
    retired_page_ids_bytes: int = (2 * MAX_BTREE_HEIGHT + 1) * PAGE_ID_BYTES
    terminal_control_bytes: int = 4 * CELL_BYTES
    allocation_events_per_operation: int = 0
    corpus_proportional_bytes: int = 0

    @property
    def total_bytes(self) -> int:
        return (
            self.page_buffer_bytes
            + self.path_stack_bytes
            + self.key_scratch_bytes
            + self.value_scratch_bytes
            + self.split_key_scratch_bytes
            + self.allocated_page_ids_bytes
            + self.mutation_control_bytes
            + self.retired_page_ids_bytes
            + self.terminal_control_bytes
        )


DEFAULT_OPERATION_WORKSPACE = OperationWorkspace()


def workspace_for_operation(cardinality: int) -> OperationWorkspace:
    """Return fixed preallocated scratch, independent of corpus cardinality."""

    if cardinality < 0:
        raise ValueError("cardinality must be non-negative")
    return DEFAULT_OPERATION_WORKSPACE


@dataclass(frozen=True, slots=True)
class PointLookupCost:
    height: int
    page_reads: int
    peak_workspace_bytes: int
    allocation_events: int = 0
    corpus_proportional_allocation_bytes: int = 0


def point_lookup_cost(index: IndexProfile) -> PointLookupCost:
    height = index.height
    workspace = workspace_for_operation(index.cardinality)
    return PointLookupCost(
        height=height,
        page_reads=height,
        peak_workspace_bytes=workspace.total_bytes,
    )


@dataclass(frozen=True, slots=True)
class KeysetCost:
    cardinality: int
    start_rank: int
    requested_results: int
    returned_results: int
    height: int
    leaf_pages_touched: int
    internal_boundary_reads: int
    page_reads: int
    comparison_bound: int
    allocation_events: int = 0
    corpus_proportional_allocation_bytes: int = 0

    @property
    def result_page_reads(self) -> int:
        return max(0, self.page_reads - self.height)


def keyset_page_cost(
    geometry: BTreeGeometry,
    cardinality: int,
    start_rank: int,
    result_count: int,
    *,
    exclusive: bool = True,
) -> KeysetCost:
    """Bound a seek/resume followed by the current public cursor walk.

    ``start_rank`` determines only the remaining result count; the bound does
    not pretend rank identifies a physical leaf in a variably occupied tree.
    Every public ``NEXT`` currently resets the Btree's one-page cache, so each
    later row rereads its leaf.  Crossing a leaf boundary reads both the saved
    ancestor path and the new descent.  ``exclusive`` also allows RESUME's
    first result to cross a boundary after the stable last key.  The result is
    independent of how deep the rank lies in the corpus.
    """

    if cardinality < 0:
        raise ValueError("cardinality must be non-negative")
    if start_rank < 0 or start_rank > cardinality:
        raise ValueError("start_rank must lie within the index")
    if result_count < 0:
        raise ValueError("result_count must be non-negative")

    returned = min(result_count, cardinality - start_rank)
    height = geometry.height_for(cardinality)
    exhaustion_probe = result_count > returned
    if result_count == 0 or cardinality == 0:
        leaf_pages = 0
        internal_boundary_reads = 0
        page_reads = 0
        comparison_bound = 0
    elif returned == 0:
        # An EOF resume descends once, revalidates the terminal leaf, and may
        # ascend the complete saved path before proving exhaustion.
        leaf_pages = 1
        internal_boundary_reads = max(0, height - 1)
        page_reads = 2 * height - 1
        comparison_bound = 40 * height - 9
    elif exhaustion_probe and returned < geometry.minimum_leaf_occupancy:
        # The final fewer-than-six rows must share the terminal leaf.  A caller
        # filling a larger window then makes one terminal NEXT: it rereads that
        # leaf and ascends the complete path to prove EOF.
        leaf_pages = 1
        internal_boundary_reads = max(0, height - 1)
        page_reads = 2 * height + returned - 1
        comparison_bound = (
            27 * max(0, height - 1)
            + 31
            + 20 * (returned - 1)
            + 10
            + 13 * max(0, height - 1)
        )
    else:
        occupancy = geometry.minimum_leaf_occupancy
        if exclusive:
            leaf_transitions = _ceil_div(returned, occupancy)
        else:
            leaf_transitions = (returned + occupancy - 2) // occupancy
        leaf_pages = leaf_transitions + 1
        internal_boundary_reads = sum(
            _ceil_div(
                leaf_transitions,
                geometry.minimum_branch_fanout**level,
            )
            for level in range(1, max(1, height - 1))
        ) if height > 2 and leaf_transitions else 0

        # The first seek reads one root-to-leaf path.  Each later public NEXT
        # rereads the leaf after its per-call cache reset.  Every transition
        # reads one ancestor/new-descendant pair, plus such a pair for every
        # higher-level carry in the bounded cursor path.
        page_reads = (
            height
            + returned
            - 1
            + 2 * (leaf_transitions + internal_boundary_reads)
        )

        # Validation linearly proves canonical order within every fixed-slot
        # node.  The initial seek costs at most 27 comparisons per branch and
        # 31 at the leaf/emit pair.  Later rows cost 20; a leaf transition adds
        # 23, a possible exclusive pre-first transition adds another 10, and
        # each higher carry adds 26.
        comparison_bound = (
            27 * max(0, height - 1)
            + 31
            + 20 * (returned - 1)
            + 23 * leaf_transitions
            + (10 if exclusive and leaf_transitions else 0)
            + 26 * internal_boundary_reads
        )
        if exhaustion_probe:
            page_reads += height
            comparison_bound += 10 + 13 * max(0, height - 1)
    return KeysetCost(
        cardinality=cardinality,
        start_rank=start_rank,
        requested_results=result_count,
        returned_results=returned,
        height=height,
        leaf_pages_touched=leaf_pages,
        internal_boundary_reads=internal_boundary_reads,
        page_reads=page_reads,
        comparison_bound=comparison_bound,
    )


@dataclass(frozen=True, slots=True)
class RelationshipRangeCost:
    total_edges: int
    first_edge_rank: int
    degree: int
    height: int
    slice_calls: int
    leaf_pages_touched: int
    internal_boundary_reads: int
    page_reads: int
    full_scan_leaf_pages: int
    allocation_events: int = 0
    corpus_proportional_allocation_bytes: int = 0


def relationship_range_cost(
    geometry: BTreeGeometry,
    total_edges: int,
    first_edge_rank: int,
    degree: int,
) -> RelationshipRangeCost:
    """Bound a contiguous edge range through the public sliced Library API.

    Library returns at most ``LIBRARY_INDEX_SLICE_MAX`` rows per call and
    prepares a fresh cursor for every continuation.  Charge every call the
    worst-case full-window seek/walk bound, including the final partial call.
    This remains a scalar calculation while accounting for the repeated seeks
    that an unbounded single-cursor model would incorrectly omit.
    """

    if degree < 0:
        raise ValueError("degree must be non-negative")
    if first_edge_rank < 0 or first_edge_rank + degree > total_edges:
        raise ValueError("relationship range must be contained in the edge index")
    slice_calls = _ceil_div(degree, LIBRARY_INDEX_SLICE_MAX)
    if slice_calls:
        window = keyset_page_cost(
            geometry,
            total_edges,
            first_edge_rank,
            LIBRARY_INDEX_SLICE_MAX,
            exclusive=False,
        )
    else:
        window = keyset_page_cost(
            geometry,
            total_edges,
            first_edge_rank,
            0,
            exclusive=False,
        )
    return RelationshipRangeCost(
        total_edges=total_edges,
        first_edge_rank=first_edge_rank,
        degree=degree,
        height=window.height,
        slice_calls=slice_calls,
        leaf_pages_touched=slice_calls * window.leaf_pages_touched,
        internal_boundary_reads=slice_calls * window.internal_boundary_reads,
        page_reads=slice_calls * window.page_reads,
        full_scan_leaf_pages=geometry.leaf_pages(total_edges),
    )


@dataclass(frozen=True, slots=True)
class MutationComponent:
    name: str
    page_write_bound: int


@dataclass(frozen=True, slots=True)
class MetadataMutationCost:
    components: tuple[MutationComponent, ...]
    cow_index_page_writes: int
    application_root_page_writes: int
    reclaim_bucket_page_writes: int
    representative_reclaim_maintenance_page_writes: int
    reclaim_maintenance_max_page_writes_per_step: int
    representative_metadata_page_writes: int
    structural_metadata_page_write_ceiling: int
    appended_record_bytes: int
    appended_record_physical_bytes: int
    authority_record_bytes: int
    representative_checked_page_bytes_written: int
    structural_checked_page_bytes_write_ceiling: int
    representative_total_bytes_written: int
    structural_total_bytes_write_ceiling: int
    peak_workspace_bytes: int
    allocation_events: int = 0
    corpus_proportional_allocation_bytes: int = 0


@dataclass(frozen=True, slots=True)
class MetadataTransactionCost:
    """Representative accounting plus the unconditional step-write ceiling."""

    btree_page_allocations: int
    application_root_allocations: int
    reclaim_bucket_allocations: int
    reclaim_bucket_page_writes: int
    reclaim_maintenance_step_calls: int
    representative_reclaim_maintenance_bucket_allocations: int
    representative_reclaim_maintenance_page_writes: int
    representative_reclaim_maintenance_metadata_retirements: int
    committed_page_retirements: int
    current_generation_discards: int

    @property
    def consumer_issued_pages(self) -> int:
        """Pages recorded in RECLAIM's consumer-issued ledger."""

        return self.btree_page_allocations + self.application_root_allocations

    @property
    def representative_total_page_allocations(self) -> int:
        """Physical allocations in the settled two-pending-bucket scenario."""

        return (
            self.consumer_issued_pages
            + self.reclaim_bucket_allocations
            + self.representative_reclaim_maintenance_bucket_allocations
        )

    @property
    def representative_total_staged_retirements(self) -> int:
        """Committed pages plus metadata retired in the settled scenario."""

        return (
            self.committed_page_retirements
            + self.representative_reclaim_maintenance_metadata_retirements
        )

    @property
    def representative_total_page_writes(self) -> int:
        """Checked-page writes in the settled two-pending-bucket scenario."""

        # The application-root allocation is first claimed with a checked
        # placeholder write so reclaim finalization cannot independently use
        # the same high-water slot, then rewritten with the serialized root.
        return (
            self.consumer_issued_pages
            + self.application_root_allocations
            + self.reclaim_bucket_page_writes
            + self.representative_reclaim_maintenance_page_writes
        )

    @property
    def structural_reclaim_maintenance_page_write_ceiling(self) -> int:
        """One possible output-bucket write for every bounded step call."""

        return (
            self.reclaim_maintenance_step_calls
            * RECLAIM_MAINTENANCE_MAX_PAGE_WRITES_PER_STEP
        )

    @property
    def structural_total_page_write_ceiling(self) -> int:
        """Unconditional checked-page ceiling across all maintenance calls."""

        return (
            self.consumer_issued_pages
            + self.application_root_allocations
            + self.reclaim_bucket_page_writes
            + self.structural_reclaim_maintenance_page_write_ceiling
        )


def _replace_path_page_writes(index: IndexProfile) -> int:
    return index.height


def _rekey_page_write_bound(index: IndexProfile) -> int:
    # Deleting the old key may rebalance every non-root level (2h-1 writes),
    # then inserting the new key may split every level and add a root (2h+1).
    # They are two operations inside one adapter transaction, so both bounded
    # COW paths count even though pages superseded by the second are discarded.
    return 4 * index.height


def representative_metadata_mutation(
    profile: LibraryScaleProfile = LARGE_LIBRARY_PROFILE,
    appended_record_bytes: int = 3072,
) -> MetadataMutationCost:
    """Conservative COW write envelope for a metadata/title/status replacement.

    This is the explicitly deferred L12 seven-index re-key projection, not a
    claim about L11's create-only adapter.  It accounts separately for checked
    page traffic, the aligned segment record, and the atomic root record.  No
    corpus bank or aggregate edge array is copied.
    """

    if appended_record_bytes <= 0 or appended_record_bytes > PAGE_PAYLOAD_BYTES:
        raise ValueError("representative metadata record must fit one page payload")
    directory = profile.index("record-directory")
    title = profile.index("title-by-bytes")
    lifecycle = profile.index("lifecycle-order")
    components = (
        MutationComponent("record-directory-replace", _replace_path_page_writes(directory)),
        MutationComponent("title-rekey", _rekey_page_write_bound(title)),
        MutationComponent("lifecycle-rekey", _rekey_page_write_bound(lifecycle)),
    )
    cow_page_writes = sum(component.page_write_bound for component in components)
    transaction = representative_metadata_transaction(profile)
    representative_metadata_page_writes = (
        transaction.representative_total_page_writes
    )
    structural_metadata_page_write_ceiling = (
        transaction.structural_total_page_write_ceiling
    )
    appended_record_physical_bytes = _align_up(
        appended_record_bytes + CHECKED_RECORD_ENVELOPE_BYTES,
        SEGMENT_ALIGNMENT_BYTES,
    )
    representative_checked_page_bytes_written = (
        representative_metadata_page_writes * PAGE_BYTES
    )
    structural_checked_page_bytes_write_ceiling = (
        structural_metadata_page_write_ceiling * PAGE_BYTES
    )
    return MetadataMutationCost(
        components=components,
        cow_index_page_writes=cow_page_writes,
        application_root_page_writes=2 * transaction.application_root_allocations,
        reclaim_bucket_page_writes=transaction.reclaim_bucket_page_writes,
        representative_reclaim_maintenance_page_writes=(
            transaction.representative_reclaim_maintenance_page_writes
        ),
        reclaim_maintenance_max_page_writes_per_step=(
            RECLAIM_MAINTENANCE_MAX_PAGE_WRITES_PER_STEP
        ),
        representative_metadata_page_writes=(
            representative_metadata_page_writes
        ),
        structural_metadata_page_write_ceiling=(
            structural_metadata_page_write_ceiling
        ),
        appended_record_bytes=appended_record_bytes,
        appended_record_physical_bytes=appended_record_physical_bytes,
        authority_record_bytes=ATOMIC_ROOT_RECORD_BYTES,
        representative_checked_page_bytes_written=(
            representative_checked_page_bytes_written
        ),
        structural_checked_page_bytes_write_ceiling=(
            structural_checked_page_bytes_write_ceiling
        ),
        representative_total_bytes_written=(
            representative_checked_page_bytes_written
            + appended_record_physical_bytes
            + ATOMIC_ROOT_RECORD_BYTES
        ),
        structural_total_bytes_write_ceiling=(
            structural_checked_page_bytes_write_ceiling
            + appended_record_physical_bytes
            + ATOMIC_ROOT_RECORD_BYTES
        ),
        peak_workspace_bytes=LIBRARY_INDEX_WORKSPACE_BYTES,
    )


def representative_metadata_transaction(
    profile: LibraryScaleProfile = LARGE_LIBRARY_PROFILE,
) -> MetadataTransactionCost:
    """Account issued, retired, and discarded pages across one metadata re-key.

    The directory overwrite retires and replaces one committed path.  Each
    ordered re-key first performs a potentially balanced delete, then inserts
    through the current-generation root.  A different insert path can still
    retire up to ``height - 1`` untouched committed pages; a same-path insert
    can instead discard up to ``height`` pages written earlier in the proposal.
    These independent maxima size both ledgers without assuming they coincide.
    Reclaim bucket pages are internal physical allocations, not entries in the
    consumer's issued-page ledger.  Finalization prepares and then links each
    new bucket.  The adapter also makes one bounded maintenance call before
    every consumer allocation.  In the steady two-bucket envelope those calls
    rotate two pending buckets and promote their two payload batches, while the
    remaining calls are write-free because a ready bucket is already present.
    """

    directory = profile.index("record-directory")
    title = profile.index("title-by-bytes")
    lifecycle = profile.index("lifecycle-order")
    rekeys = (title, lifecycle)
    btree_allocations = directory.height + sum(4 * index.height for index in rekeys)
    committed_retirements = (
        directory.height
        + sum(3 * index.height - 2 for index in rekeys)
        + 1  # old application root
    )
    current_discards = sum(index.height for index in rekeys)
    pending_buckets = _ceil_div(committed_retirements, MAX_RECLAIM_BATCH)
    discard_buckets = _ceil_div(current_discards, MAX_RECLAIM_BATCH)
    reclaim_buckets = pending_buckets + discard_buckets
    maintenance_bucket_writes = 2 * pending_buckets
    # Two old input buckets and their two rotated output buckets become
    # unreachable.  The preceding 14-page discard bucket and both promoted
    # ready buckets are also exhausted by the 66 consumer allocations.
    maintenance_metadata_retirements = 2 * pending_buckets + 3
    return MetadataTransactionCost(
        btree_page_allocations=btree_allocations,
        application_root_allocations=1,
        reclaim_bucket_allocations=reclaim_buckets,
        reclaim_bucket_page_writes=2 * reclaim_buckets,
        reclaim_maintenance_step_calls=btree_allocations + 1,
        representative_reclaim_maintenance_bucket_allocations=(
            maintenance_bucket_writes
        ),
        representative_reclaim_maintenance_page_writes=(
            maintenance_bucket_writes
        ),
        representative_reclaim_maintenance_metadata_retirements=(
            maintenance_metadata_retirements
        ),
        committed_page_retirements=committed_retirements,
        current_generation_discards=current_discards,
    )


@dataclass(frozen=True, slots=True)
class BlobRangeCost:
    total_blob_bytes: int
    offset: int
    requested_bytes: int
    returned_bytes: int
    first_chunk: int | None
    last_chunk: int | None
    chunks_touched: int
    manifest_level: int
    manifest_records_read: int
    data_records_read: int
    record_reads: int
    peak_workspace_bytes: int
    allocation_events: int = 0
    corpus_proportional_allocation_bytes: int = 0


@dataclass(frozen=True, slots=True)
class BlobGeometry:
    chunk_bytes: int = BLOB_CHUNK_BYTES
    workspace_bytes: int = BLOB_WORKSPACE_BYTES

    def __post_init__(self) -> None:
        if self.chunk_bytes <= 0:
            raise ValueError("chunk_bytes must be positive")

    def chunk_count(self, total_blob_bytes: int) -> int:
        if total_blob_bytes < 0:
            raise ValueError("total_blob_bytes must be non-negative")
        return _ceil_div(total_blob_bytes, self.chunk_bytes)

    def manifest_level(self, total_blob_bytes: int) -> int:
        """Return the minimal production manifest level, or -1 when empty."""

        chunks = self.chunk_count(total_blob_bytes)
        if chunks == 0:
            return -1
        level = 0
        capacity = 64
        while chunks > capacity:
            level += 1
            capacity *= 64
            if level > 7:
                raise ValueError("blob exceeds the production manifest limit")
        return level

    def range_cost(
        self,
        total_blob_bytes: int,
        offset: int,
        requested_bytes: int,
    ) -> BlobRangeCost:
        """Return exact immutable-chunk touches for an EOF-clamped byte range."""

        if total_blob_bytes < 0:
            raise ValueError("total_blob_bytes must be non-negative")
        if offset < 0 or offset > total_blob_bytes:
            raise ValueError("offset must lie within the blob")
        if requested_bytes < 0:
            raise ValueError("requested_bytes must be non-negative")
        returned = min(requested_bytes, total_blob_bytes - offset)
        if returned == 0:
            first_chunk = None
            last_chunk = None
            chunks_touched = 0
        else:
            first_chunk = offset // self.chunk_bytes
            last_chunk = (offset + returned - 1) // self.chunk_bytes
            chunks_touched = last_chunk - first_chunk + 1
        manifest_level = self.manifest_level(total_blob_bytes)
        manifest_records_read = chunks_touched * (manifest_level + 1)
        data_records_read = chunks_touched
        return BlobRangeCost(
            total_blob_bytes=total_blob_bytes,
            offset=offset,
            requested_bytes=requested_bytes,
            returned_bytes=returned,
            first_chunk=first_chunk,
            last_chunk=last_chunk,
            chunks_touched=chunks_touched,
            manifest_level=manifest_level,
            manifest_records_read=manifest_records_read,
            data_records_read=data_records_read,
            record_reads=manifest_records_read + data_records_read,
            peak_workspace_bytes=self.workspace_bytes,
        )


@dataclass(slots=True)
class TwoRootReclamation:
    """Small executable model of the A/B-root reclamation safety fence.

    Generation zero represents an unused root slot.  A page retired by
    generation G is reusable only when *both* root records name generations at
    least G.  Until then the older valid root remains a possible recovery
    authority and may still reference the page.

    Retired pages live in a generation-ordered heap.  One reclaim call pops at
    most ``MAX_RECLAIM_BATCH`` entries, so neither its scan nor its output grows
    with the corpus or total free-page population.
    """

    high_water_page_id: int
    initial_root_generations: tuple[int, int] = (1, 0)
    _root_generations: list[int] = field(init=False, repr=False)
    _retired_by_page: dict[int, int] = field(default_factory=dict, init=False, repr=False)
    _retired_heap: list[tuple[int, int]] = field(default_factory=list, init=False, repr=False)
    _reusable_heap: list[int] = field(default_factory=list, init=False, repr=False)
    _reusable_pages: set[int] = field(default_factory=set, init=False, repr=False)

    def __post_init__(self) -> None:
        if self.high_water_page_id < 0:
            raise ValueError("high_water_page_id must be non-negative")
        if len(self.initial_root_generations) != 2:
            raise ValueError("exactly two root generations are required")
        if min(self.initial_root_generations) < 0:
            raise ValueError("root generations must be non-negative")
        self._root_generations = list(self.initial_root_generations)

    @property
    def root_generations(self) -> tuple[int, int]:
        return self._root_generations[0], self._root_generations[1]

    @property
    def authoritative_generation(self) -> int:
        return max(self._root_generations)

    @property
    def reclamation_floor(self) -> int:
        return min(self._root_generations)

    @property
    def retired_count(self) -> int:
        return len(self._retired_by_page)

    @property
    def reusable_count(self) -> int:
        return len(self._reusable_heap)

    def publish(self, generation: int, *, committed: bool = True) -> bool:
        """Publish into the older slot, or model a fault before publication."""

        if generation <= self.authoritative_generation:
            raise ValueError("publication generation must advance authority")
        if not committed:
            return False
        older_slot = 0 if self._root_generations[0] < self._root_generations[1] else 1
        self._root_generations[older_slot] = generation
        return True

    def retire(self, page_id: int, retirement_generation: int) -> None:
        """Record one unreachable page after its retiring root was committed."""

        if page_id < 0 or page_id >= self.high_water_page_id:
            raise ValueError("retired page must be below the fresh-page high-water mark")
        if retirement_generation <= 0 or retirement_generation > self.authoritative_generation:
            raise ValueError("retirement generation must already be authoritative")
        if page_id in self._retired_by_page or page_id in self._reusable_pages:
            raise ValueError("page is already retired or reusable")
        self._retired_by_page[page_id] = retirement_generation
        heappush(self._retired_heap, (retirement_generation, page_id))

    def retirement_generation(self, page_id: int) -> int | None:
        return self._retired_by_page.get(page_id)

    def reclaim(self, max_pages: int = MAX_RECLAIM_BATCH) -> tuple[int, ...]:
        """Move one bounded eligible quantum onto the reusable-page heap."""

        if max_pages < 0 or max_pages > MAX_RECLAIM_BATCH:
            raise ValueError(f"max_pages must be between 0 and {MAX_RECLAIM_BATCH}")
        reclaimed: list[int] = []
        floor = self.reclamation_floor
        while (
            len(reclaimed) < max_pages
            and self._retired_heap
            and self._retired_heap[0][0] <= floor
        ):
            retirement_generation, page_id = heappop(self._retired_heap)
            if self._retired_by_page.get(page_id) != retirement_generation:
                raise AssertionError("retirement heap and directory diverged")
            del self._retired_by_page[page_id]
            heappush(self._reusable_heap, page_id)
            self._reusable_pages.add(page_id)
            reclaimed.append(page_id)
        return tuple(reclaimed)

    def allocate_page(self) -> int:
        """Prefer a fenced reusable id; otherwise advance the scalar high water."""

        if self._reusable_heap:
            page_id = heappop(self._reusable_heap)
            self._reusable_pages.remove(page_id)
            return page_id
        page_id = self.high_water_page_id
        self.high_water_page_id += 1
        return page_id


@dataclass(slots=True)
class AnalyticStore:
    """Per-store wrapper used to prove there is no hidden process-global state."""

    store_id: str
    reclamation: TwoRootReclamation
    operation_count: int = 0

    @classmethod
    def create(cls, store_id: str, high_water_page_id: int) -> AnalyticStore:
        if not store_id:
            raise ValueError("store_id must not be empty")
        return cls(store_id, TwoRootReclamation(high_water_page_id))

    def publish(self, generation: int, *, committed: bool = True) -> bool:
        result = self.reclamation.publish(generation, committed=committed)
        self.operation_count += 1
        return result

    def retire(self, page_id: int, retirement_generation: int) -> None:
        self.reclamation.retire(page_id, retirement_generation)
        self.operation_count += 1

    def reclaim(self, max_pages: int = MAX_RECLAIM_BATCH) -> tuple[int, ...]:
        result = self.reclamation.reclaim(max_pages)
        self.operation_count += 1
        return result

    def allocate_page(self) -> int:
        page_id = self.reclamation.allocate_page()
        self.operation_count += 1
        return page_id


__all__ = [
    "AnalyticStore",
    "ATOMIC_ROOT_RECORD_BYTES",
    "BLOB_CHUNK_BYTES",
    "BLOB_WORKSPACE_BYTES",
    "BTreeGeometry",
    "BlobGeometry",
    "BlobRangeCost",
    "CHECKED_ENVELOPE_BYTES",
    "CHECKED_RECORD_ENVELOPE_BYTES",
    "DEFAULT_OPERATION_WORKSPACE",
    "DOCUMENT_BY_CREATION_GEOMETRY",
    "DOCUMENT_BY_RID_GEOMETRY",
    "EDGE_BY_SUBJECT_GEOMETRY",
    "IndexProfile",
    "KeysetCost",
    "LARGE_LIBRARY_PROFILE",
    "LIBRARY_DOCUMENTS",
    "LIBRARY_EDGES",
    "LIBRARY_INDEX_SLICE_MAX",
    "LIBRARY_INDEX_WORKSPACE_BYTES",
    "LIBRARY_REVISIONS",
    "LIFECYCLE_ORDER_GEOMETRY",
    "LibraryScaleProfile",
    "MAX_ANALYTIC_SAMPLES",
    "MAX_ALLOCATED_PAGES_PER_TRANSACTION",
    "MAX_BTREE_HEIGHT",
    "MAX_DISCARDED_PAGES_PER_TRANSACTION",
    "MAX_RECLAIM_BATCH",
    "MAX_RETIRED_PAGES_PER_TRANSACTION",
    "RECLAIM_MAINTENANCE_MAX_PAGE_WRITES_PER_STEP",
    "MetadataMutationCost",
    "MetadataTransactionCost",
    "MutationComponent",
    "NODE_HEADER_BYTES",
    "OperationWorkspace",
    "PAGE_BYTES",
    "PAGE_ID_BYTES",
    "PAGE_PAYLOAD_BYTES",
    "PointLookupCost",
    "REVISION_BY_DOCUMENT_GEOMETRY",
    "RelationshipRangeCost",
    "SEGMENT_ALIGNMENT_BYTES",
    "BRANCH_CAPACITY",
    "BRANCH_ENTRY_BYTES",
    "BTREE_KEY_MAX_BYTES",
    "BTREE_VALUE_MAX_BYTES",
    "CELL_BYTES",
    "LEAF_CAPACITY",
    "LEAF_ENTRY_BYTES",
    "TITLE_BY_BYTES_GEOMETRY",
    "TwoRootReclamation",
    "keyset_page_cost",
    "library_large_profile",
    "point_lookup_cost",
    "relationship_range_cost",
    "representative_metadata_mutation",
    "representative_metadata_transaction",
    "sample_ranks",
    "workspace_for_operation",
]
