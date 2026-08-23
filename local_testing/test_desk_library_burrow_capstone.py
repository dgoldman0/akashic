#!/usr/bin/env python3
"""Qualify the framed Desk -> Library -> Rabbit Checkpoint-5 capstone.

Static mode checks the closed profile and composition boundary without
starting MegaPad.  Product mode deliberately retains Checkpoint 4's approved
single-core, source-loaded ceiling and is never run concurrently with another
smoke, integration, or persistence test.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Final

import akashic_tui as harness
import test_desk_library_burrow as checkpoint4


PROFILE = "desktop-library-burrow-capstone"
FIXTURE = Path(__file__).resolve().with_name(
    "desk-library-burrow-capstone.f"
)
PROVIDER = Path(__file__).resolve().with_name(
    "streams-library-rabbit-provider.f"
)
PROFILE_SOURCE = (
    Path(__file__).resolve().parents[1]
    / "akashic"
    / "tui"
    / "applets"
    / "streams"
    / "rabbit-library-profile.f"
)
IMAGE = Path("/tmp/akashic-desk-library-burrow-capstone.img")

REPLAY_DROP_MARKER: Final = (
    "DESK LIBRARY RABBIT START PROVIDER RECEIPT DROP PASS"
)
REPLAY_NO_EFFECT_MARKER: Final = (
    "DESK LIBRARY RABBIT START NO EFFECT PASS"
)
LIST_PASS_MARKER: Final = "DESK LIBRARY RABBIT LIST PASS"
FETCH_PASS_MARKER: Final = "DESK LIBRARY RABBIT FETCH PASS"
FROZEN_SCOPE_MARKER: Final = "DESK LIBRARY RABBIT FROZEN SCOPE PASS"
NONMEMBER_MARKER: Final = "DESK LIBRARY RABBIT NONMEMBER PASS"
STALE_REVISION_MARKER: Final = (
    "DESK LIBRARY RABBIT STALE REVISION PASS"
)
DATA_PLANE_PASS_MARKER: Final = "DESK LIBRARY RABBIT DATA PLANE PASS"
DATA_PLANE_MARKERS: Final = (
    LIST_PASS_MARKER,
    FETCH_PASS_MARKER,
    FROZEN_SCOPE_MARKER,
    NONMEMBER_MARKER,
    STALE_REVISION_MARKER,
    DATA_PLANE_PASS_MARKER,
)
CAPSTONE_MARKERS: Final = (
    REPLAY_DROP_MARKER,
    REPLAY_NO_EFFECT_MARKER,
    *DATA_PLANE_MARKERS,
)
LOAD_MARKERS: Final = (
    "DESK LIBRARY RABBIT LOAD C4 PROVIDER PASS",
    "DESK LIBRARY RABBIT LOAD C4 PRODUCT PASS",
    "DESK LIBRARY RABBIT LOAD C5 PROVIDER PASS",
    "DESK LIBRARY RABBIT LOAD C5 CAPSTONE PASS",
    "DESK LIBRARY RABBIT PRACTICE PASS",
)


def _assert_static_contracts() -> None:
    profile = harness.PROFILES[PROFILE]
    fixture = FIXTURE.read_text(encoding="utf-8")
    provider = PROVIDER.read_text(encoding="utf-8")
    production = PROFILE_SOURCE.read_text(encoding="utf-8")

    assert profile.linked is True
    assert profile.cold_source_packed is True
    assert profile.include_large_sample is False
    assert profile.total_sectors == checkpoint4.TOTAL_SECTORS == 8192
    assert checkpoint4.NUM_CORES == 1
    assert checkpoint4.EXT_MEMORY_BYTES == 128 << 20
    assert checkpoint4.TOTAL_MAX_STEPS == 24_000_000_000
    assert (
        checkpoint4.ProductJourney.configure_step_budget
        == checkpoint4.CONFIGURE_MAX_STEPS
    )
    assert (
        CapstoneProductJourney.configure_step_budget
        == checkpoint4.TOTAL_MAX_STEPS
    )
    assert profile.roots[:6] == harness.PROFILES[
        checkpoint4.PROFILE
    ].roots
    for root in (
        "tui/applets/streams/rabbit-library-profile.f",
        "net/transports/memory-duplex.f",
        "tui/applets/streams/rabbit-connector.f",
    ):
        assert root in profile.roots
    assert profile.initial_files == ()
    assert tuple(path for path, _ in profile.cold_source_initial_files) == (
        "c5-srbprov.f.lz",
        "c5-dlburrow.f.lz",
        "c5-slrabbit.f.lz",
        "c5-dlcap.f.lz",
    )
    for path, source in profile.cold_source_initial_files:
        assert path in profile.autoexec
        assert len(source) <= harness.COLD_SOURCE_RAW_MAX_BYTES
    assert "PROVIDED akashic-streams-rabbit-library-profile" in production
    assert "PROVIDED akashic-test-streams-library-rabbit-provider" in provider
    assert "PROVIDED akashic-test-c5-dlb" in fixture
    assert "library/service.f" not in production
    assert "library/controller.f" not in production
    assert "library/vfs" not in production
    assert "LIBRARY-READ-V1-RABBIT-SELECTOR$" in production
    assert "SLRGP-GRAPH-BASELINE?" in provider
    assert "SLRGP-CLIENT@" in provider
    assert "SLRGP-CONNECTOR@" in provider
    assert "SLRGP-CLIENT-BUILDER@" in provider
    assert "IVJSON-E-OK" not in fixture
    assert "U<=" not in fixture
    assert fixture.count("IVJSON-DECODE-AS-LIMIT 0=") == 2
    assert "['] _C5-GRAPH-CONFIGURE IS" not in fixture
    assert fixture.count("_C4-DEFER!") == 10
    assert fixture.count("_C5-CAPTURE-START ?DUP") == 1
    assert "_C5-CAPTURE-RUNNING-REPLAY ?DUP" in fixture
    assert (
        "_C5-START-ARG-REVISION @ 2 + = _C4-ASSERT"
    ) in fixture
    assert (
        "_C4-LIBRARY-DESC APP.COMP-DESC @\n"
        "        _DESK-REGISTRY @ CREG-INST-BY-DESC"
    ) in fixture
    assert profile.autoexec.count("_BOOT-COLD-SOURCE c5-") == 4
    load_positions = tuple(profile.autoexec.index(marker) for marker in LOAD_MARKERS)
    assert load_positions == tuple(sorted(load_positions))
    assert load_positions[-1] < profile.autoexec.index(
        "DESK-LIBRARY-BURROW-CONFIGURE"
    )
    for marker in CAPSTONE_MARKERS:
        assert marker in fixture


class CapstoneProductJourney(checkpoint4.ProductJourney):
    """Drive one physical replay while retaining eight logical tool results."""

    # The packed Checkpoint-5 closure must decode and source-compile before its
    # first flushed marker. Let that finite startup draw from the existing
    # whole-journey ceiling; ProductJourney._run_slice retains the absolute
    # 24-billion-step and wall-time bounds.
    configure_step_budget = checkpoint4.TOTAL_MAX_STEPS

    def __init__(
        self,
        session: harness.MachineSession,
        profile: harness.Profile,
        ledger: checkpoint4.SpaceLedger,
        timeout: float,
    ) -> None:
        super().__init__(session, profile, ledger, timeout)
        self.review_approvals = 0

    def approve_once(self, call_number: int) -> None:
        super().approve_once(call_number)
        self.review_approvals += 1

    def wait_fresh_review(
        self,
        call_number: int,
        after_revision: int,
        *,
        step_budget: int = checkpoint4.WAIT_MAX_STEPS,
    ) -> None:
        """Do not mistake the first start review for its identical replay."""

        self.activity = f"fresh review for call {call_number}"
        local_remaining = min(
            step_budget,
            checkpoint4.TOTAL_MAX_STEPS - self.total_steps,
        )
        while local_remaining > 0:
            text = self.session.snapshot().text()
            if (
                self.session.revision > after_revision
                and "PgDn to inspect all rows" in text
            ):
                return
            before = self.total_steps
            self._run_slice(local_remaining)
            local_remaining -= self.total_steps - before
        raise checkpoint4.JourneyFailure(
            f"call {call_number} replay did not present a fresh review"
        )

    def wait_raw_count(
        self,
        marker: str,
        count: int,
        *,
        step_budget: int = checkpoint4.WAIT_MAX_STEPS,
    ) -> None:
        self.activity = f"raw marker {marker!r} occurrence {count}"
        local_remaining = min(
            step_budget,
            checkpoint4.TOTAL_MAX_STEPS - self.total_steps,
        )
        while (
            self.session.raw_text().count(marker) < count
            and local_remaining > 0
        ):
            before = self.total_steps
            self._run_slice(local_remaining)
            local_remaining -= self.total_steps - before
        actual = self.session.raw_text().count(marker)
        if actual < count:
            raise checkpoint4.JourneyFailure(
                f"timed out waiting for occurrence {count} of raw marker "
                f"{marker!r}; observed {actual}"
            )

    def _drive_tool_call(self, call_number: int, operation: str) -> None:
        if call_number != 5:
            super()._drive_tool_call(call_number, operation)
            return

        call_marker = (
            f"DESK LIBRARY BURROW CALL {call_number} {operation}"
        )
        result_marker = (
            f"DESK LIBRARY BURROW RESULT {call_number} {operation} PASS"
        )

        self.wait_raw_count(call_marker, 1)
        self.approve_once(call_number)
        replay_revision = self.session.revision
        self.wait_raw(REPLAY_DROP_MARKER)

        # The scripted provider re-emits the identical call id and operands.
        # It therefore crosses the normal Agent review path a second time.
        self.wait_raw_count(call_marker, 2)
        self.wait_fresh_review(call_number, replay_revision)
        self.approve_once(call_number)
        self.wait_raw(REPLAY_NO_EFFECT_MARKER)
        self.wait_raw(result_marker)

    def _after_tool_result(self, call_number: int, operation: str) -> None:
        if call_number != 5:
            return
        for marker in DATA_PLANE_MARKERS:
            self.wait_raw(marker)
        self.sample("Rabbit LIST/FETCH data plane complete")

    def _assert_runtime_evidence(self, raw: str) -> None:
        if self.review_approvals != 6:
            raise checkpoint4.JourneyFailure(
                "review approval count changed: expected 6, got "
                f"{self.review_approvals}"
            )

        logical_calls = tuple(
            enumerate(checkpoint4.EXPECTED_CALLS, start=1)
        )
        physical_calls = (
            *logical_calls[:5],
            logical_calls[4],
            *logical_calls[5:],
        )
        call_matches = tuple(checkpoint4.CALL_RE.finditer(raw))
        calls = tuple(
            (int(match.group(1)), match.group(2))
            for match in call_matches
        )
        if calls != physical_calls:
            raise checkpoint4.JourneyFailure(
                "physical tool-call order changed: expected "
                f"{physical_calls!r}, got {calls!r}"
            )

        result_matches = tuple(checkpoint4.RESULT_RE.finditer(raw))
        results = tuple(
            (int(match.group(1)), match.group(2))
            for match in result_matches
        )
        if results != logical_calls:
            raise checkpoint4.JourneyFailure(
                f"logical tool-result order changed: {results!r}"
            )

        facets = tuple(
            (name, int(count))
            for name, count in checkpoint4.FACET_RE.findall(raw)
        )
        expected_facets = tuple(
            (name, len(checkpoint4.EXPECTED_FACETS[name]))
            for name in ("CHAT", "READ", "ASSIST", "OPERATOR")
        )
        if facets != expected_facets:
            raise checkpoint4.JourneyFailure(
                f"live focused facet evidence changed: {facets!r}"
            )

        for marker in (
            checkpoint4.RUNNING_MARKER,
            checkpoint4.STOPPED_MARKER,
            checkpoint4.AGENT_PASS_MARKER,
            checkpoint4.OUTER_QUIT_MARKER,
            checkpoint4.PASS_MARKER,
            *LOAD_MARKERS,
            *CAPSTONE_MARKERS,
        ):
            if raw.count(marker) != 1:
                raise checkpoint4.JourneyFailure(
                    f"terminal marker {marker!r} occurred "
                    f"{raw.count(marker)} times"
                )

        # The first provider callback deliberately withholds its receipt from
        # the scripted provider after Agent has recorded the result.  The
        # second physical request must then converge with NO_EFFECT, and the
        # framed data plane must finish before logical status call 6 begins.
        first_start = call_matches[4]
        second_start = call_matches[5]
        status_after_start = call_matches[6]
        start_result = result_matches[4]
        replay_drop = raw.index(REPLAY_DROP_MARKER)
        no_effect = raw.index(REPLAY_NO_EFFECT_MARKER)
        data_positions = tuple(raw.index(marker) for marker in DATA_PLANE_MARKERS)
        if not first_start.end() < replay_drop < second_start.start():
            raise checkpoint4.JourneyFailure(
                "provider receipt drop did not separate the two start calls"
            )
        if not second_start.end() < no_effect < status_after_start.start():
            raise checkpoint4.JourneyFailure(
                "NO_EFFECT convergence was not bounded by replay and status"
            )
        if not no_effect < start_result.start():
            raise checkpoint4.JourneyFailure(
                "logical start result preceded NO_EFFECT convergence"
            )
        if not start_result.end() < data_positions[0]:
            raise checkpoint4.JourneyFailure(
                "Rabbit data plane began before logical start convergence"
            )
        if data_positions != tuple(sorted(data_positions)):
            raise checkpoint4.JourneyFailure(
                "Rabbit data-plane evidence order changed"
            )
        if not data_positions[-1] < status_after_start.start():
            raise checkpoint4.JourneyFailure(
                "logical status call 6 began before the data plane completed"
            )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument("--product", action="store_true")
    parser.add_argument("--image", type=Path, default=IMAGE)
    parser.add_argument(
        "--timeout",
        type=float,
        default=checkpoint4.DEFAULT_TIMEOUT_SECONDS,
    )
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be greater than zero")

    checkpoint4._assert_static_contracts()
    _assert_static_contracts()
    if args.static_only:
        print("DESK LIBRARY RABBIT CAPSTONE STATIC PASS")
        return 0
    return checkpoint4._run_product(
        args.image,
        args.timeout,
        profile_name=PROFILE,
        journey_class=CapstoneProductJourney,
    )


if __name__ == "__main__":
    raise SystemExit(main())
