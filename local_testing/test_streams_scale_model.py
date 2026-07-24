#!/usr/bin/env python3
"""Fast scalar qualification for the frozen L13 Streams topology."""

from __future__ import annotations

import sys
from pathlib import Path


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import streams_scale_model as model  # noqa: E402


def test_profiles_are_scalar_and_match_the_l13_plan() -> None:
    workstation = model.streams_workstation_profile()
    large = model.streams_large_profile()

    assert (
        workstation.sources,
        workstation.observation_versions,
        workstation.attempts,
    ) == (10_000, 1_000_000, 2_000_000)
    assert (
        large.sources,
        large.observation_versions,
        large.attempts,
    ) == (100_000, 10_000_000, 20_000_000)
    assert workstation.materialized_target_items == 0
    assert large.materialized_target_items == 0
    assert workstation.removed_source_tombstones == 0
    assert large.removed_source_tombstones == 0
    assert len(workstation.indexes) == len(large.indexes) == 4
    assert model.streams_workstation_profile() is workstation
    assert model.streams_large_profile() is large


def test_revision_rich_shape_separates_versions_from_native_heads() -> None:
    profile = model.streams_revision_rich_profile()
    assert profile.observation_versions == 1_000_000
    assert profile.native_heads == 250_000
    assert profile.index("identities").cardinality == 1_250_000
    assert profile.threaded_observations == 0
    assert profile.index("orderings").cardinality == 2_000_000
    assert profile.materialized_target_items == 0


def test_removal_rich_shape_retains_one_stable_tombstone_row() -> None:
    profile = model.streams_removal_rich_profile()
    assert profile.sources == 10_000
    assert profile.removed_source_tombstones == 100_000
    assert profile.index("directory").cardinality == 120_064
    assert profile.materialized_target_items == 0


def test_four_physical_tree_cardinalities_and_heights_are_bounded() -> None:
    workstation = model.streams_workstation_profile()
    large = model.streams_large_profile()

    assert {item.name: item.cardinality for item in workstation.indexes} == {
        "directory": 20_064,
        "attempts": 2_000_000,
        "identities": 2_000_000,
        "orderings": 2_000_000,
    }
    assert {item.name: item.cardinality for item in large.indexes} == {
        "directory": 200_064,
        "attempts": 20_000_000,
        "identities": 20_000_000,
        "orderings": 20_000_000,
    }
    assert {item.name: item.height for item in workstation.indexes} == {
        "directory": 5,
        "attempts": 8,
        "identities": 8,
        "orderings": 8,
    }
    assert {item.name: item.height for item in large.indexes} == {
        "directory": 6,
        "attempts": 9,
        "identities": 9,
        "orderings": 9,
    }
    assert max(item.height for item in large.indexes) < 12


def test_key_widths_fit_the_neutral_tree_without_materialization() -> None:
    assert model.DIRECTORY_GEOMETRY.key_bytes == 41
    assert model.ATTEMPT_GEOMETRY.key_bytes == 73
    assert model.IDENTITY_GEOMETRY.key_bytes == 121
    assert model.ORDERING_GEOMETRY.key_bytes == 145
    for geometry in (
        model.DIRECTORY_GEOMETRY,
        model.ATTEMPT_GEOMETRY,
        model.IDENTITY_GEOMETRY,
        model.ORDERING_GEOMETRY,
    ):
        assert geometry.inline_value_bytes == 24
        assert geometry.key_bytes <= 256
        assert geometry.leaf_capacity == 11
        assert geometry.branch_fanout == 14


def test_deep_point_and_window_work_remains_corpus_independent() -> None:
    workstation = model.hot_paths(model.streams_workstation_profile())
    large = model.hot_paths(model.streams_large_profile())

    assert workstation.materialized_target_items == 0
    assert large.materialized_target_items == 0
    assert len(workstation.sampled_deep_ranks) == 64
    assert len(large.sampled_deep_ranks) == 64
    assert large.source_point_reads == 6
    assert large.latest_attempt_reads == 9
    assert large.native_head_reads == 9
    assert large.exact_revision_reads == 9
    assert large.timeline_window.returned_results <= 32
    assert large.source_scope_rows == 7
    assert large.source_window.returned_results == 7
    assert large.source_window.requested_results == 32
    assert large.source_window.height == large.timeline_window.height
    assert (
        workstation.fixed_btree_workspace_bytes
        == large.fixed_btree_workspace_bytes
        == 17_672
    )
    assert (
        workstation.fixed_blob_workspace_bytes
        == large.fixed_blob_workspace_bytes
        == 46_960
    )
    assert (
        workstation.fixed_range_page_bytes
        == large.fixed_range_page_bytes
        == 86_528
    )
    assert large.timeline_window.corpus_proportional_allocation_bytes == 0
    assert large.source_window.corpus_proportional_allocation_bytes == 0


def test_eight_candidate_apply_rolls_hidden_roots_in_bounded_transactions() -> None:
    workstation = model.refresh_apply_cost(
        model.streams_workstation_profile()
    )
    large = model.refresh_apply_cost(model.streams_large_profile())

    assert workstation.candidates == large.candidates == 8
    assert workstation.identity_mutations == large.identity_mutations == 16
    assert workstation.ordering_mutations == large.ordering_mutations == 16
    assert workstation.total_tree_mutations == large.total_tree_mutations == 34
    assert workstation.tallest_tree_height == 8
    assert large.tallest_tree_height == 9
    assert workstation.pages_reserved_per_mutation == 17
    assert large.pages_reserved_per_mutation == 19
    assert workstation.physical_transactions >= 2
    assert workstation.mutations_per_physical_transaction == 7
    assert large.mutations_per_physical_transaction == 6
    assert workstation.hidden_rollover_publications == 4
    assert large.hidden_rollover_publications == 5
    assert workstation.final_publications == large.final_publications == 1
    assert workstation.physical_transactions == 5
    assert large.physical_transactions == 6
    assert workstation.corpus_proportional_allocation_bytes == 0
    assert large.corpus_proportional_allocation_bytes == 0


def test_collision_and_batch_work_are_explicit_small_bounds() -> None:
    assert model.STREAMS_NATIVE_COLLISION_MAX == 16
    assert model.STREAMS_BATCH_MAX == 8
    assert model.STREAMS_QUERY_PAGE_MAX == 32
    assert model.STREAMS_ACTIVE_ATTEMPT_MAX == 64
    assert model.STREAMS_SOURCE_OBSERVATION_LIMIT == 10_000_000
    assert model.STREAMS_SOURCE_REVISION_LIMIT == 10_000_000


def test_forth_contract_exposes_range_and_collision_bounds() -> None:
    key_source = (
        HERE.parent / "akashic" / "tui" / "applets" / "streams"
        / "index-keys.f"
    ).read_text(encoding="utf-8")
    registry_source = (
        HERE.parent / "akashic" / "tui" / "applets" / "streams"
        / "source-registry.f"
    ).read_text(encoding="utf-8")
    assert "32  CONSTANT STREAMS-PI-RANGE-MAX" in key_source
    assert "16  CONSTANT STREAMS-PI-NATIVE-COLLISION-MAX" in key_source
    assert (
        "16       CONSTANT STREAMS-SOURCE-OBSERVATION-DEFAULT"
        in registry_source
    )
    assert (
        "4        CONSTANT STREAMS-SOURCE-REVISION-DEFAULT"
        in registry_source
    )
    assert (
        "10000000 CONSTANT STREAMS-SOURCE-OBSERVATION-MAX"
        in registry_source
    )
    assert (
        "10000000 CONSTANT STREAMS-SOURCE-REVISION-MAX"
        in registry_source
    )
