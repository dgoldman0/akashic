#!/usr/bin/env python3
"""Scalar L13 model for the four-tree Streams persistence topology.

The target-sized source, attempt, native-head, observation, and ordering
populations remain integers.  This module reuses the checked-page and B+tree
geometry already ratcheted to production by ``persistence_scale_model``; it
never materializes a target corpus.
"""

from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache

from persistence_scale_model import (
    APPLICATION_ROOT_PAGE_ALLOCATIONS,
    BLOB_WORKSPACE_BYTES,
    MAX_ALLOCATED_PAGES_PER_TRANSACTION,
    BTreeGeometry,
    IndexProfile,
    KeysetCost,
    keyset_page_cost,
    point_lookup_cost,
    sample_ranks,
)


STREAMS_INDEX_TREE_COUNT = 4
STREAMS_QUERY_PAGE_MAX = 32
STREAMS_BATCH_MAX = 8
STREAMS_NATIVE_COLLISION_MAX = 16
STREAMS_ACTIVE_ATTEMPT_MAX = 64
STREAMS_SOURCE_OBSERVATION_LIMIT = 10_000_000
STREAMS_SOURCE_REVISION_LIMIT = 10_000_000
STREAMS_RANGE_ROW_BYTES = 16 + 256 + 2_432
STREAMS_RANGE_PAGE_BYTES = STREAMS_QUERY_PAGE_MAX * STREAMS_RANGE_ROW_BYTES

STREAMS_WORKSTATION_SOURCES = 10_000
STREAMS_WORKSTATION_OBSERVATIONS = 1_000_000
STREAMS_WORKSTATION_ATTEMPTS = 2_000_000

STREAMS_LARGE_SOURCES = 100_000
STREAMS_LARGE_OBSERVATIONS = 10_000_000
STREAMS_LARGE_ATTEMPTS = 20_000_000

# The physical trees multiplex these longest family keys.  Every value is one
# 24-byte checked semantic-record reference.
STREAMS_DIRECTORY_KEY_BYTES = 41
STREAMS_ATTEMPT_KEY_BYTES = 73
STREAMS_IDENTITY_KEY_BYTES = 121
STREAMS_ORDERING_KEY_BYTES = 145
STREAMS_RECORD_REF_BYTES = 24

DIRECTORY_GEOMETRY = BTreeGeometry(
    STREAMS_DIRECTORY_KEY_BYTES, STREAMS_RECORD_REF_BYTES
)
ATTEMPT_GEOMETRY = BTreeGeometry(
    STREAMS_ATTEMPT_KEY_BYTES, STREAMS_RECORD_REF_BYTES
)
IDENTITY_GEOMETRY = BTreeGeometry(
    STREAMS_IDENTITY_KEY_BYTES, STREAMS_RECORD_REF_BYTES
)
ORDERING_GEOMETRY = BTreeGeometry(
    STREAMS_ORDERING_KEY_BYTES, STREAMS_RECORD_REF_BYTES
)


@dataclass(frozen=True, slots=True)
class StreamsScaleProfile:
    """One scalar-only Streams qualification population."""

    name: str
    sources: int
    observation_versions: int
    attempts: int
    active_attempts: int
    removed_source_tombstones: int
    native_heads: int
    threaded_observations: int
    indexes: tuple[IndexProfile, ...]
    materialized_target_items: int = 0

    def index(self, name: str) -> IndexProfile:
        for index in self.indexes:
            if index.name == name:
                return index
        raise KeyError(name)


def _profile(
    name: str,
    sources: int,
    observation_versions: int,
    attempts: int,
    *,
    native_heads: int | None = None,
    removed_source_tombstones: int = 0,
) -> StreamsScaleProfile:
    if (
        sources <= 0
        or observation_versions < 0
        or attempts < 0
        or removed_source_tombstones < 0
    ):
        raise ValueError("invalid Streams scale cardinality")
    if native_heads is None:
        native_heads = observation_versions
    if native_heads < 0 or native_heads > observation_versions:
        raise ValueError("native heads must be retained observation identities")
    active = min(sources, attempts, STREAMS_ACTIVE_ATTEMPT_MAX)
    # ``observation_versions`` always means immutable version rows, never
    # stable observation identities.  The default one-revision shape
    # maximizes native-head rows; a separate revision-rich profile exercises
    # many versions sharing fewer heads.  Observation ABI 1 carries no exact
    # thread evidence, so the reserved thread family has zero rows.
    threaded = 0
    return StreamsScaleProfile(
        name=name,
        sources=sources,
        observation_versions=observation_versions,
        attempts=attempts,
        active_attempts=active,
        removed_source_tombstones=removed_source_tombstones,
        native_heads=native_heads,
        threaded_observations=threaded,
        indexes=(
            IndexProfile(
                "directory",
                2 * sources + removed_source_tombstones + active,
                DIRECTORY_GEOMETRY,
            ),
            IndexProfile("attempts", attempts, ATTEMPT_GEOMETRY),
            IndexProfile(
                "identities",
                native_heads + observation_versions,
                IDENTITY_GEOMETRY,
            ),
            IndexProfile(
                "orderings",
                2 * observation_versions,
                ORDERING_GEOMETRY,
            ),
        ),
    )


WORKSTATION_PROFILE = _profile(
    "workstation",
    STREAMS_WORKSTATION_SOURCES,
    STREAMS_WORKSTATION_OBSERVATIONS,
    STREAMS_WORKSTATION_ATTEMPTS,
)
LARGE_PROFILE = _profile(
    "large",
    STREAMS_LARGE_SOURCES,
    STREAMS_LARGE_OBSERVATIONS,
    STREAMS_LARGE_ATTEMPTS,
)
REVISION_RICH_PROFILE = _profile(
    "revision-rich",
    STREAMS_WORKSTATION_SOURCES,
    STREAMS_WORKSTATION_OBSERVATIONS,
    STREAMS_WORKSTATION_ATTEMPTS,
    native_heads=STREAMS_WORKSTATION_OBSERVATIONS // 4,
)
REMOVAL_RICH_PROFILE = _profile(
    "removal-rich",
    STREAMS_WORKSTATION_SOURCES,
    STREAMS_WORKSTATION_OBSERVATIONS,
    STREAMS_WORKSTATION_ATTEMPTS,
    removed_source_tombstones=STREAMS_LARGE_SOURCES,
)


def streams_workstation_profile() -> StreamsScaleProfile:
    return WORKSTATION_PROFILE


def streams_large_profile() -> StreamsScaleProfile:
    return LARGE_PROFILE


def streams_revision_rich_profile() -> StreamsScaleProfile:
    return REVISION_RICH_PROFILE


def streams_removal_rich_profile() -> StreamsScaleProfile:
    return REMOVAL_RICH_PROFILE


@dataclass(frozen=True, slots=True)
class RefreshApplyCost:
    """Conservative all-new eight-candidate apply structure."""

    candidates: int
    identity_mutations: int
    ordering_mutations: int
    attempt_mutations: int
    active_mutations: int
    total_tree_mutations: int
    tallest_tree_height: int
    pages_reserved_per_mutation: int
    mutations_per_physical_transaction: int
    physical_transactions: int
    hidden_rollover_publications: int
    final_publications: int
    application_root_pages: int
    maximum_tree_page_writes: int
    corpus_proportional_allocation_bytes: int = 0


def refresh_apply_cost(
    profile: StreamsScaleProfile,
    candidates: int = STREAMS_BATCH_MAX,
) -> RefreshApplyCost:
    """Bound hidden-root staging without creating observations.

    Each changed candidate updates one native head and one observation
    revision, plus the ABI 1 global/source ordering rows.
    Finalization replaces the accepted attempt and removes its active row.
    """

    if candidates < 0 or candidates > STREAMS_BATCH_MAX:
        raise ValueError("candidate count exceeds the checked batch bound")
    identity_mutations = 2 * candidates
    ordering_mutations = 2 * candidates
    attempt_mutations = 1
    active_mutations = 1
    total = (
        identity_mutations
        + ordering_mutations
        + attempt_mutations
        + active_mutations
    )
    tallest = max(index.height for index in profile.indexes)
    pages_per_mutation = 2 * tallest + 1
    # Finalizer metadata consumes retirement/discard reservation, not the
    # allocated-page quotient.  The live staging precondition reserves only
    # the next worst-case mutation and one application-root allocation.
    mutation_room = (
        MAX_ALLOCATED_PAGES_PER_TRANSACTION
        - APPLICATION_ROOT_PAGE_ALLOCATIONS
    )
    per_transaction = max(1, mutation_room // pages_per_mutation)
    # ENSURE-NEXT runs after every mutation.  Exactly filling a tranche
    # publishes it and begins a fresh transaction; FINAL-PUBLISH then consumes
    # that fresh transaction even when no further tree mutation was needed.
    hidden_rollovers = 0 if total == 0 else total // per_transaction
    final_publications = 0 if total == 0 else 1
    physical_transactions = hidden_rollovers + final_publications
    return RefreshApplyCost(
        candidates=candidates,
        identity_mutations=identity_mutations,
        ordering_mutations=ordering_mutations,
        attempt_mutations=attempt_mutations,
        active_mutations=active_mutations,
        total_tree_mutations=total,
        tallest_tree_height=tallest,
        pages_reserved_per_mutation=pages_per_mutation,
        mutations_per_physical_transaction=per_transaction,
        physical_transactions=physical_transactions,
        hidden_rollover_publications=hidden_rollovers,
        final_publications=final_publications,
        application_root_pages=physical_transactions,
        maximum_tree_page_writes=total * pages_per_mutation,
    )


@dataclass(frozen=True, slots=True)
class StreamsHotPaths:
    source_point_reads: int
    latest_attempt_reads: int
    native_head_reads: int
    exact_revision_reads: int
    timeline_window: KeysetCost
    source_window: KeysetCost
    source_scope_rows: int
    fixed_btree_workspace_bytes: int
    fixed_blob_workspace_bytes: int
    fixed_range_page_bytes: int
    sampled_deep_ranks: tuple[int, ...]
    materialized_target_items: int = 0


@lru_cache(maxsize=2)
def hot_paths(profile: StreamsScaleProfile) -> StreamsHotPaths:
    directory = profile.index("directory")
    attempts = profile.index("attempts")
    identities = profile.index("identities")
    orderings = profile.index("orderings")
    deep_ranks = sample_ranks(orderings.cardinality, 64, seed=0x513EA013)
    start = deep_ranks[-1] if deep_ranks else 0
    start = min(start, orderings.cardinality)
    # Put a small source-scoped suffix at a deterministic family boundary.
    # This preserves the full physical tree height while forcing the range
    # model to prove prefix exhaustion before filling a 32-row result page.
    source_scope_rows = min(7, profile.observation_versions)
    source_start = orderings.cardinality - source_scope_rows
    return StreamsHotPaths(
        source_point_reads=point_lookup_cost(directory).page_reads,
        latest_attempt_reads=point_lookup_cost(attempts).page_reads,
        native_head_reads=point_lookup_cost(identities).page_reads,
        exact_revision_reads=point_lookup_cost(identities).page_reads,
        timeline_window=keyset_page_cost(
            ORDERING_GEOMETRY,
            orderings.cardinality,
            start,
            STREAMS_QUERY_PAGE_MAX,
            exclusive=True,
        ),
        source_window=keyset_page_cost(
            ORDERING_GEOMETRY,
            orderings.cardinality,
            source_start,
            STREAMS_QUERY_PAGE_MAX,
            exclusive=True,
        ),
        source_scope_rows=source_scope_rows,
        fixed_btree_workspace_bytes=point_lookup_cost(
            orderings
        ).peak_workspace_bytes,
        fixed_blob_workspace_bytes=BLOB_WORKSPACE_BYTES,
        fixed_range_page_bytes=STREAMS_RANGE_PAGE_BYTES,
        sampled_deep_ranks=deep_ranks,
    )


__all__ = [
    "ATTEMPT_GEOMETRY",
    "DIRECTORY_GEOMETRY",
    "IDENTITY_GEOMETRY",
    "LARGE_PROFILE",
    "ORDERING_GEOMETRY",
    "RefreshApplyCost",
    "REMOVAL_RICH_PROFILE",
    "REVISION_RICH_PROFILE",
    "STREAMS_ACTIVE_ATTEMPT_MAX",
    "STREAMS_BATCH_MAX",
    "STREAMS_INDEX_TREE_COUNT",
    "STREAMS_NATIVE_COLLISION_MAX",
    "STREAMS_QUERY_PAGE_MAX",
    "STREAMS_RANGE_PAGE_BYTES",
    "STREAMS_RANGE_ROW_BYTES",
    "STREAMS_SOURCE_OBSERVATION_LIMIT",
    "STREAMS_SOURCE_REVISION_LIMIT",
    "StreamsHotPaths",
    "StreamsScaleProfile",
    "WORKSTATION_PROFILE",
    "hot_paths",
    "refresh_apply_cost",
    "streams_large_profile",
    "streams_removal_rich_profile",
    "streams_revision_rich_profile",
    "streams_workstation_profile",
]
