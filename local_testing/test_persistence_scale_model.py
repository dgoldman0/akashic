#!/usr/bin/env python3
"""Fast analytical qualification for the L11 persistence scale model."""

from __future__ import annotations

from pathlib import Path
import re
import sys

import pytest


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import persistence_scale_model as model  # noqa: E402


SOURCE_ROOT = HERE.parent / "akashic"


def _forth_decimal_constant(module: str, name: str) -> int:
    source = (SOURCE_ROOT / module).read_text(encoding="utf-8")
    match = re.search(
        rf"(?m)^\s*(-?\d+)\s+CONSTANT\s+{re.escape(name)}(?:\s|$)",
        source,
    )
    assert match is not None, f"missing literal {name} in {module}"
    return int(match.group(1))


def test_analytical_geometry_is_ratcheted_to_production_constants() -> None:
    btree = "persistence/btree.f"
    assert _forth_decimal_constant(btree, "PBTREE-KEY-MAX") == model.BTREE_KEY_MAX_BYTES
    assert _forth_decimal_constant(btree, "PBTREE-VALUE-MAX") == model.BTREE_VALUE_MAX_BYTES
    assert _forth_decimal_constant(btree, "PBTREE-HEIGHT-MAX") == model.MAX_BTREE_HEIGHT
    assert _forth_decimal_constant(btree, "PBTREE-LEAF-CAPACITY") == model.LEAF_CAPACITY
    assert _forth_decimal_constant(btree, "PBTREE-BRANCH-CAPACITY") == model.BRANCH_CAPACITY
    assert _forth_decimal_constant(btree, "_PBTN-ENTRIES-OFF") == model.NODE_HEADER_BYTES
    assert _forth_decimal_constant(btree, "_PBTL-ENTRY-SIZE") == model.LEAF_ENTRY_BYTES
    assert _forth_decimal_constant(btree, "_PBTB-ENTRY-SIZE") == model.BRANCH_ENTRY_BYTES
    btree_source = (SOURCE_ROOT / btree).read_text(encoding="utf-8")
    assert "PBTREE-HEIGHT-MAX 2 * 1+ CONSTANT PBTREE-MUTATION-PAGE-MAX" in btree_source
    assert "PBTREE-MUTATION-PAGE-MAX CONSTANT PBTREE-ALLOCATION-MAX" in btree_source
    assert "PBTREE-MUTATION-PAGE-MAX CONSTANT PBTREE-RETIREMENT-MAX" in btree_source
    assert "PBTREE-BALANCED-CAPACITY-FOR-HEIGHT" in btree_source
    assert re.search(
        r"_PBTW-DEFERRED-OFF\s+8\s+\+\s+CONSTANT\s+PBTREE-WORK-SIZE",
        btree_source,
    )
    assert model.DEFAULT_OPERATION_WORKSPACE.total_bytes == 17_480

    blob = "persistence/blob.f"
    assert _forth_decimal_constant(blob, "PBLOB-CHUNK-SIZE") == model.BLOB_CHUNK_BYTES
    assert _forth_decimal_constant(blob, "PBLOB-MANIFEST-FANOUT") == 64
    assert _forth_decimal_constant(blob, "PBLOB-MAX-LEVEL") == 7
    assert _forth_decimal_constant(blob, "_PBLOB-BUCKETS") == 9
    frontier = _forth_decimal_constant(blob, "_PBW-FRONTIER")
    ref_size = _forth_decimal_constant("persistence/core.f", "PERSIST-REF-SIZE")
    calculated_blob_work = frontier + 9 * 64 * ref_size + model.BLOB_CHUNK_BYTES
    assert calculated_blob_work == model.BLOB_WORKSPACE_BYTES
    assert model.LIBRARY_INDEX_WORKSPACE_BYTES == 84_624
    assert (
        _forth_decimal_constant(
            "tui/applets/library/persistence-adapter.f",
            "LIBPA-INDEX-SLICE-MAX",
        )
        == model.LIBRARY_INDEX_SLICE_MAX
    )

    index_keys_source = (
        SOURCE_ROOT / "tui/applets/library/index-keys.f"
    ).read_text(encoding="utf-8")
    assert "LIB-TITLE-MAX 1+ CONSTANT _LIBPI-TITLE-SYMBOLS" in index_keys_source
    assert "_LIBPI-TITLE-SYMBOLS 9 * 7 + 8 / CONSTANT _LIBPI-TITLE-BYTES" in index_keys_source
    assert "_LIBPI-TITLE-BYTES RID-SIZE + CONSTANT LIBPI-TITLE-KEY-SIZE" in index_keys_source
    assert model.TITLE_BY_BYTES_GEOMETRY.key_bytes == 178

    reclaim = "persistence/reclaim.f"
    assert _forth_decimal_constant(reclaim, "RECLAIM-MAX-BATCH") == model.MAX_RECLAIM_BATCH
    assert (
        _forth_decimal_constant(reclaim, "RECLAIM-RETIRED-MAX")
        == model.MAX_RETIRED_PAGES_PER_TRANSACTION
    )
    assert (
        _forth_decimal_constant(reclaim, "RECLAIM-ALLOCATED-MAX")
        == model.MAX_ALLOCATED_PAGES_PER_TRANSACTION
    )
    assert (
        _forth_decimal_constant(reclaim, "RECLAIM-DISCARD-MAX")
        == model.MAX_DISCARDED_PAGES_PER_TRANSACTION
    )
    assert _forth_decimal_constant(reclaim, "RECLAIM-STATE-SIZE") == 128


def test_exact_checked_page_and_btree_geometry() -> None:
    assert model.PAGE_BYTES == 4096
    assert model.CHECKED_RECORD_ENVELOPE_BYTES == 64
    assert model.PAGE_PAYLOAD_BYTES == 4032
    assert model.SEGMENT_ALIGNMENT_BYTES == 8
    assert model.ATOMIC_ROOT_RECORD_BYTES == 160
    assert model.NODE_HEADER_BYTES == 64
    assert model.CELL_BYTES == 8
    assert model.PAGE_ID_BYTES == 8
    assert model.BTREE_KEY_MAX_BYTES == 256
    assert model.BTREE_VALUE_MAX_BYTES == 64
    assert model.LEAF_ENTRY_BYTES == 336
    assert model.BRANCH_ENTRY_BYTES == 272
    assert model.LEAF_CAPACITY == 11
    assert model.BRANCH_CAPACITY == 14

    assert (
        model.DOCUMENT_BY_RID_GEOMETRY.key_bytes,
        model.DOCUMENT_BY_RID_GEOMETRY.inline_value_bytes,
    ) == (32, 24)
    assert (
        model.DOCUMENT_BY_CREATION_GEOMETRY.key_bytes,
        model.DOCUMENT_BY_CREATION_GEOMETRY.inline_value_bytes,
    ) == (40, 32)
    assert (
        model.REVISION_BY_DOCUMENT_GEOMETRY.key_bytes,
        model.REVISION_BY_DOCUMENT_GEOMETRY.inline_value_bytes,
    ) == (40, 24)
    assert (
        model.EDGE_BY_SUBJECT_GEOMETRY.key_bytes,
        model.EDGE_BY_SUBJECT_GEOMETRY.inline_value_bytes,
    ) == (64, 0)
    assert (
        model.TITLE_BY_BYTES_GEOMETRY.key_bytes,
        model.TITLE_BY_BYTES_GEOMETRY.inline_value_bytes,
    ) == (178, 32)

    expected = (
        (model.DOCUMENT_BY_RID_GEOMETRY, 11, 14, 14),
        (model.DOCUMENT_BY_CREATION_GEOMETRY, 11, 14, 14),
        (model.REVISION_BY_DOCUMENT_GEOMETRY, 11, 14, 14),
        (model.EDGE_BY_SUBJECT_GEOMETRY, 11, 14, 14),
        (model.TITLE_BY_BYTES_GEOMETRY, 11, 14, 14),
        (model.LIFECYCLE_ORDER_GEOMETRY, 11, 14, 14),
    )
    for geometry, leaves, separators, fanout in expected:
        assert geometry.leaf_capacity == leaves
        assert geometry.branch_separator_capacity == separators
        assert geometry.branch_fanout == fanout
        assert geometry.minimum_leaf_occupancy == 6
        assert geometry.minimum_branch_fanout == 7

        leaf_used = model.NODE_HEADER_BYTES + leaves * geometry.leaf_entry_bytes
        assert leaf_used <= model.PAGE_PAYLOAD_BYTES
        assert leaf_used + geometry.leaf_entry_bytes > model.PAGE_PAYLOAD_BYTES

        branch_used = (
            model.NODE_HEADER_BYTES
            + separators * geometry.branch_entry_bytes
        )
        assert branch_used <= model.PAGE_PAYLOAD_BYTES
        assert branch_used + geometry.branch_entry_bytes > model.PAGE_PAYLOAD_BYTES

    assert tuple(
        model.DOCUMENT_BY_RID_GEOMETRY.balanced_capacity_for_height(height)
        for height in range(1, model.MAX_BTREE_HEIGHT + 1)
    ) == (
        11,
        89,
        635,
        4_457,
        31_211,
        218_489,
        1_529_435,
        10_706_057,
        74_942_411,
    )
    assert tuple(
        model.DOCUMENT_BY_RID_GEOMETRY.minimum_cardinality_for_height(height)
        for height in range(1, model.MAX_BTREE_HEIGHT + 1)
    ) == (
        1,
        12,
        90,
        636,
        4_458,
        31_212,
        218_490,
        1_529_436,
        10_706_058,
    )
    assert tuple(
        model.DOCUMENT_BY_RID_GEOMETRY.minimum_resident_cardinality(height)
        for height in range(1, model.MAX_BTREE_HEIGHT + 1)
    ) == (
        1,
        12,
        84,
        588,
        4_116,
        28_812,
        201_684,
        1_411_788,
        9_882_516,
    )
    assert model.DOCUMENT_BY_RID_GEOMETRY.monotonic_build_height_for(10_000_000) == 8
    assert model.DOCUMENT_BY_RID_GEOMETRY.height_for(10_000_000) == 9


def test_large_profile_is_scalar_and_all_point_paths_fit_height_limit() -> None:
    profile = model.library_large_profile()
    assert model.DOCUMENT_BY_RID_GEOMETRY.height_for(0) == 0
    assert profile.documents == 1_000_000
    assert profile.revisions == 10_000_000
    assert profile.edges == 10_000_000
    assert profile.materialized_target_items == 0
    assert model.library_large_profile() is profile

    expected_heights = {
        "record-directory": 9,
        "document-by-rid": 7,
        "document-by-creation": 7,
        "revision-by-document": 9,
        "edge-by-subject": 9,
        "title-by-bytes": 7,
        "lifecycle-order": 7,
    }
    assert {index.name: index.height for index in profile.indexes} == expected_heights

    for index in profile.indexes:
        assert index.height <= model.MAX_BTREE_HEIGHT
        assert index.point_page_reads == index.height
        assert index.geometry.minimum_resident_cardinality(index.height) <= index.cardinality
        if index.height < model.MAX_BTREE_HEIGHT:
            assert (
                index.geometry.minimum_resident_cardinality(index.height + 1)
                > index.cardinality
            )
        assert index.geometry.capacity_for_height(index.height) >= index.cardinality
        point = model.point_lookup_cost(index)
        assert point.page_reads == index.height
        assert point.allocation_events == 0
        assert point.corpus_proportional_allocation_bytes == 0


def test_large_profile_index_storage_is_an_explicit_scalar_bound() -> None:
    profile = model.library_large_profile()
    expected_pages = {
        "record-directory": 4_083_331,
        "document-by-rid": 194_440,
        "document-by-creation": 194_440,
        "revision-by-document": 1_944_443,
        "edge-by-subject": 1_944_443,
        "title-by-bytes": 194_440,
        "lifecycle-order": 194_440,
    }
    assert {
        index.name: index.page_count_upper_bound for index in profile.indexes
    } == expected_pages
    assert sum(index.page_count_upper_bound for index in profile.indexes) == 8_749_977
    assert sum(index.storage_bytes_upper_bound for index in profile.indexes) == 35_839_905_792
    assert profile.materialized_target_items == 0


def test_fixed_seed_rank_sampling_is_bounded_and_deterministic() -> None:
    first = model.sample_ranks(10_000_000, 64, seed=0x11)
    second = model.sample_ranks(10_000_000, 64, seed=0x11)
    different = model.sample_ranks(10_000_000, 64, seed=0x12)
    assert first == second
    assert first != different
    assert len(first) == 64
    assert len(set(first)) == 64
    assert first == tuple(sorted(first))
    assert 0 <= first[0] < first[-1] < 10_000_000
    assert first[-1] > 9_000_000
    assert model.sample_ranks(3, 64, seed=1) == (0, 1, 2)
    with pytest.raises(ValueError):
        model.sample_ranks(10_000_000, model.MAX_ANALYTIC_SAMPLES + 1)


def test_fixed_seed_large_profile_samples_drive_bounded_costs() -> None:
    """Exercise varied deep ranks without pretending to materialize the corpus."""

    profile = model.library_large_profile()
    for ordinal, index in enumerate(profile.indexes):
        ranks = model.sample_ranks(index.cardinality, 64, seed=0x5100 + ordinal)
        assert len(ranks) == 64
        for rank in ranks:
            point = model.point_lookup_cost(index)
            assert point.page_reads == index.height <= model.MAX_BTREE_HEIGHT
            requested = min(32, index.cardinality - rank)
            window = model.keyset_page_cost(
                index.geometry,
                index.cardinality,
                rank,
                requested,
            )
            assert window.returned_results == requested
            assert window.page_reads <= 66
            assert window.allocation_events == 0

    edge_index = profile.index("edge-by-subject")
    edge_ranks = model.sample_ranks(edge_index.cardinality, 64, seed=0xE66E)
    for ordinal, rank in enumerate(edge_ranks):
        requested_degree = 1 + ((rank ^ (ordinal * 0x9E37)) % 250_000)
        degree = min(requested_degree, edge_index.cardinality - rank)
        neighborhood = model.relationship_range_cost(
            edge_index.geometry,
            edge_index.cardinality,
            rank,
            degree,
        )
        assert neighborhood.degree == degree
        assert neighborhood.page_reads < neighborhood.full_scan_leaf_pages
        assert neighborhood.allocation_events == 0


def test_deep_keyset_windows_cost_height_plus_bounded_output_pages() -> None:
    profile = model.library_large_profile()
    for index in profile.indexes:
        deep_rank = min(
            model.sample_ranks(index.cardinality, 64, seed=0xC0DE)[-1],
            index.cardinality - 32,
        )
        cost = model.keyset_page_cost(
            index.geometry,
            index.cardinality,
            deep_rank,
            32,
        )
        assert cost.returned_results == 32
        assert cost.page_reads == cost.height + cost.result_page_reads
        assert cost.leaf_pages_touched == 7
        assert cost.internal_boundary_reads == cost.height - 2
        assert cost.page_reads == (60 if cost.height == 7 else 66)
        assert cost.comparison_bound == (1_091 if cost.height == 7 else 1_197)
        assert cost.page_reads < index.geometry.leaf_pages(index.cardinality)
        assert cost.allocation_events == 0
        assert cost.corpus_proportional_allocation_bytes == 0

        # The conservative cost deliberately ignores rank-to-leaf alignment;
        # deep continuation is therefore exactly the same bound as shallow.
        capacity = index.geometry.minimum_leaf_occupancy
        shallow_rank = capacity - 1
        deep_aligned_rank = shallow_rank + capacity * (
            (index.cardinality - shallow_rank - 32) // capacity
        )
        shallow = model.keyset_page_cost(
            index.geometry, index.cardinality, shallow_rank, 32
        )
        deep = model.keyset_page_cost(
            index.geometry, index.cardinality, deep_aligned_rank, 32
        )
        assert deep_aligned_rank > index.cardinality // 2
        assert deep.leaf_pages_touched == shallow.leaf_pages_touched
        assert deep.page_reads == shallow.page_reads
        assert deep.internal_boundary_reads == shallow.internal_boundary_reads

    revision_index = profile.index("revision-by-document")
    eof_window = model.keyset_page_cost(
        revision_index.geometry,
        revision_index.cardinality,
        revision_index.cardinality - 5,
        32,
    )
    assert eof_window.returned_results == 5
    assert eof_window.page_reads == 22


def test_high_degree_relationship_range_never_scans_the_edge_corpus() -> None:
    edge_index = model.library_large_profile().index("edge-by-subject")
    first_rank = 9_000_003
    degree = 250_000
    cost = model.relationship_range_cost(
        edge_index.geometry,
        edge_index.cardinality,
        first_rank,
        degree,
    )
    assert cost.degree == 250_000
    assert cost.slice_calls == 7_813
    assert cost.leaf_pages_touched == 54_691
    assert cost.internal_boundary_reads == 54_691
    assert cost.page_reads == 515_658
    assert cost.full_scan_leaf_pages == 909_091
    assert cost.page_reads < cost.full_scan_leaf_pages
    assert cost.allocation_events == 0
    assert cost.corpus_proportional_allocation_bytes == 0

    one_window = model.relationship_range_cost(
        edge_index.geometry,
        edge_index.cardinality,
        first_rank,
        32,
    )
    assert one_window.slice_calls == 1
    assert one_window.page_reads == 66


def test_metadata_mutation_separates_representative_and_structural_budgets() -> None:
    mutation = model.representative_metadata_mutation()
    assert {component.name: component.page_write_bound for component in mutation.components} == {
        "record-directory-replace": 9,
        "title-rekey": 28,
        "lifecycle-rekey": 28,
    }
    assert mutation.cow_index_page_writes == 65
    assert mutation.application_root_page_writes == 2
    assert mutation.reclaim_bucket_page_writes == 6
    assert mutation.representative_reclaim_maintenance_page_writes == 4
    assert mutation.reclaim_maintenance_max_page_writes_per_step == 1
    assert mutation.representative_metadata_page_writes == 77
    assert mutation.structural_metadata_page_write_ceiling == 139
    assert mutation.appended_record_bytes == 3072
    assert mutation.appended_record_physical_bytes == 3136
    assert mutation.authority_record_bytes == 160
    assert mutation.representative_checked_page_bytes_written == 315_392
    assert mutation.structural_checked_page_bytes_write_ceiling == 569_344
    assert mutation.representative_total_bytes_written == 318_688
    assert mutation.structural_total_bytes_write_ceiling == 572_640
    assert mutation.peak_workspace_bytes == 84_624
    assert mutation.allocation_events == 0
    assert mutation.corpus_proportional_allocation_bytes == 0


def test_representative_metadata_transaction_fits_reclaim_ledgers() -> None:
    transaction = model.representative_metadata_transaction()
    assert transaction.btree_page_allocations == 65
    assert transaction.application_root_allocations == 1
    assert transaction.reclaim_bucket_allocations == 3
    assert transaction.reclaim_bucket_page_writes == 6
    assert transaction.reclaim_maintenance_step_calls == 66
    assert transaction.representative_reclaim_maintenance_bucket_allocations == 4
    assert transaction.representative_reclaim_maintenance_page_writes == 4
    assert transaction.representative_reclaim_maintenance_metadata_retirements == 7
    assert transaction.structural_reclaim_maintenance_page_write_ceiling == 66
    assert transaction.consumer_issued_pages == 66
    assert transaction.representative_total_page_allocations == 73
    assert transaction.representative_total_page_writes == 77
    assert transaction.structural_total_page_write_ceiling == 139
    assert transaction.committed_page_retirements == 48
    assert transaction.representative_total_staged_retirements == 55
    assert transaction.current_generation_discards == 14
    assert (
        transaction.consumer_issued_pages
        <= model.MAX_ALLOCATED_PAGES_PER_TRANSACTION
    )
    assert (
        transaction.representative_total_staged_retirements
        <= model.MAX_RETIRED_PAGES_PER_TRANSACTION
    )
    assert (
        transaction.current_generation_discards
        <= model.MAX_DISCARDED_PAGES_PER_TRANSACTION
    )


@pytest.mark.parametrize(
    ("total", "offset", "requested", "returned", "first", "last", "touched"),
    (
        (100_000, 0, 0, 0, None, None, 0),
        (100_000, 0, 1, 1, 0, 0, 1),
        (100_000, 32_767, 1, 1, 0, 0, 1),
        (100_000, 32_767, 2, 2, 0, 1, 2),
        (100_000, 32_768, 32_768, 32_768, 1, 1, 1),
        (100_000, 32_768, 32_769, 32_769, 1, 2, 2),
        (65_537, 0, 65_537, 65_537, 0, 2, 3),
        (100_000, 99_999, 999, 1, 3, 3, 1),
        (100_000, 100_000, 999, 0, None, None, 0),
    ),
)
def test_32kib_blob_range_touch_counts(
    total: int,
    offset: int,
    requested: int,
    returned: int,
    first: int | None,
    last: int | None,
    touched: int,
) -> None:
    geometry = model.BlobGeometry()
    assert geometry.chunk_bytes == 32_768
    cost = geometry.range_cost(total, offset, requested)
    assert cost.returned_bytes == returned
    assert cost.first_chunk == first
    assert cost.last_chunk == last
    assert cost.chunks_touched == touched
    assert cost.manifest_level == 0
    assert cost.manifest_records_read == touched
    assert cost.data_records_read == touched
    assert cost.record_reads == touched * 2
    assert cost.peak_workspace_bytes == 46_936
    assert cost.allocation_events == 0
    assert cost.corpus_proportional_allocation_bytes == 0


def test_multilevel_blob_range_rereads_each_manifest_path_per_chunk() -> None:
    geometry = model.BlobGeometry()
    total = 65 * geometry.chunk_bytes
    cost = geometry.range_cost(total, geometry.chunk_bytes - 1, 3)
    assert cost.manifest_level == 1
    assert cost.chunks_touched == 2
    assert cost.manifest_records_read == 4
    assert cost.data_records_read == 2
    assert cost.record_reads == 6


def test_two_root_fence_blocks_reuse_through_fault_then_reuses_exact_page() -> None:
    reclamation = model.TwoRootReclamation(high_water_page_id=100)
    assert reclamation.root_generations == (1, 0)

    assert reclamation.publish(2)
    assert reclamation.root_generations == (1, 2)
    reclamation.retire(7, retirement_generation=2)
    assert reclamation.retirement_generation(7) == 2
    assert reclamation.reclaim() == ()

    roots_before_fault = reclamation.root_generations
    assert not reclamation.publish(3, committed=False)
    assert reclamation.root_generations == roots_before_fault
    assert reclamation.reclaim() == ()
    assert reclamation.allocate_page() == 100
    assert reclamation.high_water_page_id == 101

    assert reclamation.publish(3)
    assert reclamation.root_generations == (3, 2)
    assert reclamation.reclaim(max_pages=1) == (7,)
    assert reclamation.retired_count == 0
    assert reclamation.reusable_count == 1
    assert reclamation.allocate_page() == 7
    assert reclamation.high_water_page_id == 101


def test_reclamation_work_is_a_fixed_quantum() -> None:
    reclamation = model.TwoRootReclamation(high_water_page_id=1000)
    reclamation.publish(2)
    reclamation.publish(3)
    for page_id in range(40):
        reclamation.retire(page_id, retirement_generation=2)

    first = reclamation.reclaim(max_pages=model.MAX_RECLAIM_BATCH)
    assert len(first) == 32
    assert reclamation.retired_count == 8
    second = reclamation.reclaim(max_pages=8)
    assert len(second) == 8
    assert reclamation.retired_count == 0
    with pytest.raises(ValueError):
        reclamation.reclaim(max_pages=model.MAX_RECLAIM_BATCH + 1)


def test_repeated_churn_reuses_the_same_pages_without_high_water_growth() -> None:
    reclamation = model.TwoRootReclamation(high_water_page_id=100)
    reusable = (7, 8)

    for retiring_generation, fence_generation in ((2, 3), (4, 5)):
        assert reclamation.publish(retiring_generation)
        for page_id in reusable:
            reclamation.retire(page_id, retiring_generation)
        assert reclamation.reclaim() == ()
        assert reclamation.publish(fence_generation)
        assert reclamation.reclaim() == reusable
        before = reclamation.high_water_page_id
        assert tuple(reclamation.allocate_page() for _ in reusable) == reusable
        assert reclamation.high_water_page_id == before == 100


def test_four_store_interleaving_has_no_shared_roots_or_free_pages() -> None:
    stores = tuple(
        model.AnalyticStore.create(f"store-{number}", (number + 1) * 1000)
        for number in range(4)
    )
    assert len({id(store.reclamation) for store in stores}) == 4
    untouched = tuple(store.reclamation.root_generations for store in stores[1:])

    stores[0].publish(2)
    stores[0].retire(7, 2)
    assert stores[0].reclaim() == ()
    assert tuple(store.reclamation.root_generations for store in stores[1:]) == untouched
    assert all(store.operation_count == 0 for store in stores[1:])

    # Fixed interleave, intentionally not store-id order.
    for index in (2, 0, 3, 1):
        store = stores[index]
        if index != 0:
            store.publish(2)
            store.retire(index + 7, 2)
            assert store.reclaim() == ()
        store.publish(3)
        expected_page = 7 if index == 0 else index + 7
        assert store.reclaim(max_pages=1) == (expected_page,)
        high_water = store.reclamation.high_water_page_id
        assert store.allocate_page() == expected_page
        assert store.reclamation.high_water_page_id == high_water

    assert all(store.reclamation.root_generations == (3, 2) for store in stores)
    other_roots = tuple(store.reclamation.root_generations for store in stores[1:])
    stores[0].publish(4)
    assert stores[0].reclamation.root_generations == (3, 4)
    assert tuple(store.reclamation.root_generations for store in stores[1:]) == other_roots


def test_every_ordinary_cost_uses_fixed_caller_owned_workspace() -> None:
    workspaces = tuple(
        model.workspace_for_operation(cardinality)
        for cardinality in (0, 1, 1_000_000, 10_000_000, 10**18)
    )
    assert all(workspace is model.DEFAULT_OPERATION_WORKSPACE for workspace in workspaces)
    assert {workspace.total_bytes for workspace in workspaces} == {17_480}
    assert all(workspace.allocation_events_per_operation == 0 for workspace in workspaces)
    assert all(workspace.corpus_proportional_bytes == 0 for workspace in workspaces)

    profile = model.library_large_profile()
    index = profile.index("edge-by-subject")
    costs = (
        model.point_lookup_cost(index),
        model.keyset_page_cost(index.geometry, index.cardinality, 9_000_000, 32),
        model.relationship_range_cost(index.geometry, index.cardinality, 8_000_000, 1000),
        model.BlobGeometry().range_cost(10**12, 10**12 - 100, 32),
        model.representative_metadata_mutation(profile),
    )
    assert all(cost.allocation_events == 0 for cost in costs)
    assert all(cost.corpus_proportional_allocation_bytes == 0 for cost in costs)


def test_invalid_ranges_and_geometry_fail_closed() -> None:
    with pytest.raises(ValueError):
        model.BTreeGeometry(key_bytes=4000, inline_value_bytes=100)
    with pytest.raises(ValueError):
        model.keyset_page_cost(model.DOCUMENT_BY_RID_GEOMETRY, 100, 101, 1)
    with pytest.raises(ValueError):
        model.relationship_range_cost(model.EDGE_BY_SUBJECT_GEOMETRY, 100, 90, 11)
    with pytest.raises(ValueError):
        model.BlobGeometry().range_cost(100, 101, 1)
    with pytest.raises(ValueError):
        model.representative_metadata_mutation(appended_record_bytes=4096)
    with pytest.raises(ValueError):
        model.DOCUMENT_BY_RID_GEOMETRY.height_for(74_942_412)
