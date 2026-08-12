#!/usr/bin/env python3
"""Qualify the composed Desk -> Agent -> Library -> Burrow product journey.

``--static-only`` checks the closed product/profile authority contract without
starting MegaPad.  ``--product`` is the deliberately opt-in, high-step gate:
it builds the permanent focused profile, boots one timing-correct native core,
drives the ordinary Desk UI, approves the five mutations, and records MP64FS
free-space high-water evidence through ordinary completed storage writes.

The product journey is intentionally single-process and single-machine.  It
must not be run concurrently with another smoke, integration, or persistence
test.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import re
import sys
import time
from pathlib import Path
from typing import Final


LOCAL_TESTING: Final = Path(__file__).resolve().parent
ROOT: Final = LOCAL_TESTING.parent
SOURCE_ROOT: Final = ROOT / "akashic"
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402
from devices import STORAGE_CMD_WRITE  # noqa: E402


PROFILE: Final = "desktop-library-burrow"
FIXTURE: Final = LOCAL_TESTING / "desk-library-burrow.f"
CATALOG: Final = (
    SOURCE_ROOT / "tui" / "applets" / "desk" / "agent-cap-catalog.f"
)
ACCESS_POLICY: Final = (
    SOURCE_ROOT / "tui" / "applets" / "desk" / "agent-access-policy.f"
)
LIBRARY: Final = SOURCE_ROOT / "tui" / "applets" / "library" / "library.f"
STREAMS: Final = SOURCE_ROOT / "tui" / "applets" / "streams" / "streams.f"
AGENT: Final = SOURCE_ROOT / "tui" / "applets" / "agent" / "agent.f"

IMAGE: Final = Path("/tmp/akashic-desk-library-burrow.img")
TOTAL_SECTORS: Final = 8192
EXT_MEMORY_BYTES: Final = 128 << 20
NUM_CORES: Final = 1
COLS: Final = 132
ROWS: Final = 44

# These are checked-in qualification ceilings, never product capacities.  The
# product mode is intentionally explicit because this whole-Desktop journey
# needs user approval under the repository's heavyweight-test policy.
TOTAL_MAX_STEPS: Final = 24_000_000_000
CONFIGURE_MAX_STEPS: Final = 12_000_000_000
WAIT_MAX_STEPS: Final = 1_200_000_000
INPUT_MAX_STEPS: Final = 240_000_000
DEFAULT_TIMEOUT_SECONDS: Final = 600.0

CONFIGURED_MARKER: Final = "DESK LIBRARY BURROW CONFIGURED"
AGENT_PASS_MARKER: Final = "DESK LIBRARY BURROW AGENT PASS"
OUTER_QUIT_MARKER: Final = "DESK LIBRARY BURROW OUTER QUIT REQUEST"
PASS_MARKER: Final = "DESK LIBRARY BURROW PASS"
RUNNING_MARKER: Final = "DESK LIBRARY BURROW STATE RUNNING PASS"
STOPPED_MARKER: Final = "DESK LIBRARY BURROW STATE STOPPED PASS"

DOCUMENT_TITLE: Final = "N"
DOCUMENT_CONTENT: Final = "é"
COLLECTION_TITLE: Final = "Agent Burrow Reading List"
PROMPT: Final = "Run Library Burrow."

EXPECTED_CALLS: Final = (
    "library.status",
    "library.document.create",
    "library.collection.create",
    "streams.burrow.create",
    "streams.burrow.start",
    "streams.burrow.status",
    "streams.burrow.stop",
    "streams.burrow.status",
)
MUTATION_CALLS: Final = frozenset({2, 3, 4, 5, 7})
EXPECTED_FACETS: Final = {
    "CHAT": frozenset(),
    "READ": frozenset(
        {
            "streams.source.query",
            "streams.source.read",
            "library.status",
            "streams.burrow.status",
        }
    ),
    "ASSIST": frozenset(
        {
            "streams.source.query",
            "streams.source.read",
            "library.status",
            "library.document.create",
            "library.collection.create",
            "streams.burrow.status",
        }
    ),
    "OPERATOR": frozenset(
        {
            "streams.source.query",
            "streams.source.read",
            "library.status",
            "library.document.create",
            "library.collection.create",
            "streams.burrow.create",
            "streams.burrow.status",
            "streams.burrow.start",
            "streams.burrow.stop",
        }
    ),
}

CALL_RE: Final = re.compile(
    r"DESK LIBRARY BURROW CALL\s+([1-8])\s+([a-z0-9.-]+)"
)
RESULT_RE: Final = re.compile(
    r"DESK LIBRARY BURROW RESULT\s+([1-8])\s+([a-z0-9.-]+)\s+PASS"
)
FACET_RE: Final = re.compile(
    r"DESK LIBRARY BURROW FACET\s+"
    r"(CHAT|READ|ASSIST|OPERATOR)\s+([0-9]+)\s+PASS"
)
ASSERT_RE: Final = re.compile(r"DESK LIBRARY BURROW ASSERT\s+([0-9]+)")
CANDIDATE_RE: Final = re.compile(
    r'S"\s+([^"\r\n]+)"\s+S"\s+([^"\r\n]+)"'
    r"(.*?)\s+([0-9]+)\s+_DACAND!",
    re.DOTALL,
)


class JourneyFailure(RuntimeError):
    """A bounded product milestone failed."""


@dataclass(frozen=True)
class Candidate:
    component: str
    operation: str
    policy: str
    index: int


@dataclass(frozen=True)
class StableSpaceSample:
    label: str
    free_sectors: int


class SpaceLedger:
    """Observe valid MP64FS states without perturbing guest storage bytes."""

    def __init__(self, build_image: bytes) -> None:
        info = harness.MP64FS(bytearray(build_image)).info()
        self.build_free = int(info["free_sectors"])
        self.minimum_free = self.build_free
        self.completed_write_samples = 0
        self.transient_parse_failures = 0
        self.stable_samples: list[StableSpaceSample] = [
            StableSpaceSample("built-image", self.build_free)
        ]

    def observe_completed_write(self, image: bytearray) -> None:
        """Sample after one completed write effect; ignore torn interim views."""

        try:
            info = harness.MP64FS(bytearray(image)).info()
        except Exception:
            # MP64FS commits metadata over several block commands.  An
            # individual command boundary can therefore be a deliberately
            # transient view; only valid parses contribute high-water data.
            self.transient_parse_failures += 1
            return
        free = int(info["free_sectors"])
        self.completed_write_samples += 1
        self.minimum_free = min(self.minimum_free, free)

    def observe_stable(self, label: str, image: bytes | bytearray) -> int:
        """A named journey milestone must expose a valid filesystem."""

        info = harness.MP64FS(bytearray(image)).info()
        free = int(info["free_sectors"])
        self.minimum_free = min(self.minimum_free, free)
        self.stable_samples.append(StableSpaceSample(label, free))
        return free


def _forth_code(source: str) -> str:
    """Drop backslash comments while retaining executable Forth strings."""

    return "\n".join(line.split("\\", 1)[0] for line in source.splitlines())


def _candidates(source: str) -> tuple[Candidate, ...]:
    entries = tuple(
        Candidate(
            component=match.group(1),
            operation=match.group(2),
            policy=" ".join(match.group(3).split()),
            index=int(match.group(4)),
        )
        for match in CANDIDATE_RE.finditer(_forth_code(source))
    )
    if tuple(candidate.index for candidate in entries) != tuple(
        range(len(entries))
    ):
        raise AssertionError(
            "Desk Agent candidate indices are not closed and ordered"
        )
    return entries


def _facet_for(
    candidates: tuple[Candidate, ...],
    preset_token: str | None,
) -> frozenset[str]:
    if preset_token is None:
        return frozenset()
    live_components = {"org.akashic.library.applet", "org.akashic.streams"}
    return frozenset(
        candidate.operation
        for candidate in candidates
        if candidate.component in live_components
        and preset_token in candidate.policy
    )


def _assert_static_contracts() -> None:
    profile = harness.PROFILES[PROFILE]
    fixture = FIXTURE.read_text(encoding="utf-8")
    fixture_code = _forth_code(fixture)
    catalog = CATALOG.read_text(encoding="utf-8")
    access = ACCESS_POLICY.read_text(encoding="utf-8")
    library = LIBRARY.read_text(encoding="utf-8")
    streams = STREAMS.read_text(encoding="utf-8")
    agent = AGENT.read_text(encoding="utf-8")

    rabbit = "tui/applets/streams/rabbit-capabilities.f"
    streams_root = "tui/applets/streams/streams.f"
    assert profile.roots == (
        "tui/applets/desk/desk.f",
        "tui/applets/library/library.f",
        rabbit,
        streams_root,
        "tui/applets/agent/agent.f",
        "tui/applets/agent/providers/devtools/scripted.f",
    )
    assert profile.resources == (
        "tui/applets/desk/desk.toml",
        "tui/applets/library/library.uidl",
        "tui/applets/streams/streams.uidl",
        "tui/applets/agent/agent.uidl",
    )
    assert profile.linked is True
    assert profile.include_large_sample is False
    assert profile.total_sectors == TOTAL_SECTORS == 8192
    assert NUM_CORES == 1
    assert EXT_MEMORY_BYTES == 128 << 20
    assert TOTAL_MAX_STEPS == 24_000_000_000
    assert CONFIGURE_MAX_STEPS == TOTAL_MAX_STEPS // 2
    assert tuple(path for path, _ in profile.initial_files) == (
        "local_testing/streams-burrow-prov.f",
        "local_testing/desk-library-burrow.f",
    )
    assert dict(profile.initial_files)[
        "local_testing/desk-library-burrow.f"
    ] == harness._minify_forth(
        FIXTURE.read_text(encoding="utf-8")
    ).encode("utf-8")
    assert profile.autoexec.index(f"REQUIRE {rabbit}") < (
        profile.autoexec.index(f"REQUIRE {streams_root}")
    )
    assert profile.autoexec.index("DESK-LIBRARY-BURROW-CONFIGURE") < (
        profile.autoexec.index("DESK-LIBRARY-BURROW-RUN")
    )
    assert "networking.f" not in profile.roots
    assert "rabbit/client" not in profile.autoexec.lower()

    # The focused product must use the actual applet entries and their exact
    # component identities.  The fixture may wrap Streams INIT to inject its
    # caller-owned Burrow pools, but it may not substitute a test component.
    for source, entry, component, version in (
        (
            library,
            "LIBRARY-APPLET-ENTRY",
            "org.akashic.library.applet",
            "0.1.0",
        ),
        (streams, "STREAMS-ENTRY", "org.akashic.streams", "0.5.0"),
        (agent, "AGENT-ENTRY", "org.akashic.agent", "1.0.0"),
    ):
        assert f'S" {component}"' in source
        assert f'S" {version}"' in source
        assert entry in fixture_code
    assert (
        'AAP-PRESET-PRACTICE-LIBRARY-BURROW OF S" Burrow" ENDOF'
        in " ".join(agent.split())
    )
    assert 'S" PgDn to inspect all rows"' in agent
    assert 'S" [F6] Approve once  [F7] Deny"' in agent
    assert fixture_code.count("DESK-QUEUE-LAUNCH") == 3
    assert "AAP-PRESET-PRACTICE-LIBRARY-BURROW" in fixture_code
    assert "DESK-AGENT-ACCESS-PRESET!" in fixture_code
    assert CONFIGURED_MARKER in fixture
    assert AGENT_PASS_MARKER in fixture
    assert OUTER_QUIT_MARKER in fixture
    assert PASS_MARKER in fixture

    candidates = _candidates(catalog)
    assert len(candidates) == 23
    assert len({(item.component, item.operation) for item in candidates}) == 23
    actual_facets = {
        "CHAT": _facet_for(candidates, None),
        "READ": _facet_for(candidates, "DACAND-P-READ"),
        "ASSIST": _facet_for(candidates, "DACAND-P-ASSIST"),
        "OPERATOR": _facet_for(candidates, "DACAND-P-LIBRARY-BURROW"),
    }
    assert actual_facets == EXPECTED_FACETS
    assert {name: len(facet) for name, facet in actual_facets.items()} == {
        "CHAT": 0,
        "READ": 4,
        "ASSIST": 6,
        "OPERATOR": 9,
    }

    # Mutation authority is review-only and remains local.  Query/read are
    # Library peer-facet work for the next checkpoint, not ordinary Agent
    # authority in any access preset.
    by_operation = {item.operation: item for item in candidates}
    for operation in (
        "library.document.create",
        "library.collection.create",
        "streams.burrow.create",
        "streams.burrow.start",
        "streams.burrow.stop",
    ):
        policy = by_operation[operation].policy
        assert "DACAND-REVIEW-FLAGS" in policy
        assert "CAP-E-EXTERNAL" not in policy
        assert "CAP-E-DESTRUCTIVE" not in policy
    for excluded in (
        "library.document.query",
        "library.document.read",
        "library.collection.query",
        "streams.burrow.list",
        "streams.burrow.fetch",
        "rabbit.list",
        "rabbit.fetch",
    ):
        assert excluded not in by_operation
    assert "_C4-LIBRARY-BROAD-READS-ABSENT?" in fixture_code
    assert 'S" library.document.query"' in fixture_code
    assert 'S" library.document.read"' in fixture_code
    assert "_C4-NO-EXTERNAL-EFFECTS?" in fixture_code
    assert 'S" desk.practice-library-burrow"' in access
    assert "12 _DAPI-P @ AAP.TOOL-BUDGET !" in access
    operator_case = access[access.index("AAP-PRESET-PRACTICE-LIBRARY-BURROW OF") :]
    operator_case = operator_case[: operator_case.index("ENDOF")]
    assert "CAP-E-OBSERVE CAP-E-NAVIGATE OR" in operator_case
    assert "CAP-E-MUTATE OR CAP-E-PERSIST OR" in operator_case
    assert "CAP-E-EXTERNAL" not in operator_case
    assert "CAP-E-DESTRUCTIVE" not in operator_case

    compact_fixture = " ".join(fixture_code.split())
    assert (
        "CAP-E-OBSERVE CAP-E-MUTATE OR CAP-E-PERSIST OR "
        "CONSTANT _C4-LIVE-CHANGE-EFFECTS"
    ) in compact_fixture
    assert fixture_code.count("_C4-LIVE-CHANGE-EFFECTS") == 4

    call_table = re.search(
        r":\s+_C4-CAP\$\s+.*?\bCASE\b(.*?)\bENDCASE\s*;",
        fixture_code,
        re.DOTALL,
    )
    assert call_table is not None
    static_calls = tuple(
        (int(number), operation)
        for number, operation in re.findall(
            r'([0-9]+)\s+OF\s+S"\s+([a-z0-9.-]+)"\s+ENDOF',
            call_table.group(1),
        )
    )
    assert static_calls == tuple(enumerate(EXPECTED_CALLS))
    for marker in (
        "DESK LIBRARY BURROW CALL",
        "DESK LIBRARY BURROW RESULT",
        RUNNING_MARKER,
        STOPPED_MARKER,
    ):
        assert marker in fixture
    assert DOCUMENT_TITLE in fixture
    assert DOCUMENT_CONTENT in fixture
    assert COLLECTION_TITLE in fixture

    # Product sequencing must cross Agent's sealed gateway.  Directly
    # executing owner handlers or advancing the manager from the fixture
    # would make the UI journey supporting theatre rather than evidence.
    for forbidden in (
        "CAP.HANDLER-XT",
        "_LCAP-HANDLER-RUN",
        "_LCAP-STATUS-HANDLER",
        "_LCAP-DOCUMENT-CREATE-HANDLER",
        "_LCAP-COLLECTION-CREATE-HANDLER",
        "_SRBCAP-HANDLER-RUN",
        "_SRBCAP-CREATE-H",
        "_SRBCAP-STATUS-H",
        "_SRBCAP-START-H",
        "_SRBCAP-STOP-H",
        "SRBMGR-MUTATE",
        "SRBMGR-TICK",
        "SRBMGR-QUIESCE",
        "SRBMGR-OP-CREATE",
        "SRBMGR-OP-START",
        "SRBMGR-OP-STOP",
    ):
        assert forbidden not in fixture_code


class ProductJourney:
    def __init__(
        self,
        session: harness.MachineSession,
        profile: harness.Profile,
        ledger: SpaceLedger,
        timeout: float,
    ) -> None:
        self.session = session
        self.profile = profile
        self.ledger = ledger
        self.deadline = time.monotonic() + timeout
        self.total_steps = 0
        self.activity = "product startup"

    def _captured(self) -> tuple[str, str]:
        return self.session.raw_text(), self.session.snapshot().text()

    def _failure(self) -> str | None:
        raw, screen = self._captured()
        assertions = ASSERT_RE.findall(raw)
        if assertions:
            return (
                "guest reported Checkpoint 4 assertion "
                f"{assertions[-1]}"
            )
        marker = next(
            (
                item
                for item in self.profile.failure_markers
                if item in raw or item in screen
            ),
            None,
        )
        if marker is not None:
            return f"guest reported failure marker {marker!r}"
        forth_errors = harness._has_forth_error(raw)
        if forth_errors:
            return f"guest reported Forth error {forth_errors[-1]!r}"
        return None

    def _run_slice(self, step_budget: int) -> None:
        if self.total_steps >= TOTAL_MAX_STEPS:
            raise JourneyFailure(
                "product journey exhausted its checked-in ceiling while "
                f"waiting for {self.activity}"
            )
        if time.monotonic() >= self.deadline:
            raise JourneyFailure(
                "product journey exhausted its wall timeout while waiting "
                f"for {self.activity}"
            )
        remaining = min(
            step_budget,
            TOTAL_MAX_STEPS - self.total_steps,
        )
        report = self.session.run(
            max_steps=min(50_000_000, remaining),
            wall_timeout_s=min(
                1.5,
                max(0.05, self.deadline - time.monotonic()),
            ),
            advance_idle=True,
        )
        self.total_steps += report.steps
        failure = self._failure()
        if failure is not None:
            raise JourneyFailure(failure)
        if report.reason == "halted":
            raise JourneyFailure("MegaPad halted before the product milestone")
        if report.steps == 0:
            time.sleep(0.005)

    def wait_raw(
        self,
        marker: str,
        *,
        step_budget: int = WAIT_MAX_STEPS,
    ) -> None:
        self.activity = f"raw marker {marker!r}"
        local_remaining = min(
            step_budget,
            TOTAL_MAX_STEPS - self.total_steps,
        )
        while marker not in self.session.raw_text() and local_remaining > 0:
            before = self.total_steps
            self._run_slice(local_remaining)
            local_remaining -= self.total_steps - before
        if marker not in self.session.raw_text():
            raise JourneyFailure(f"timed out waiting for raw marker {marker!r}")

    def wait_screen(
        self,
        *markers: str,
        step_budget: int = WAIT_MAX_STEPS,
    ) -> None:
        self.activity = f"screen markers {markers!r}"
        local_remaining = min(
            step_budget,
            TOTAL_MAX_STEPS - self.total_steps,
        )
        while local_remaining > 0:
            text = self.session.snapshot().text()
            if all(marker in text for marker in markers):
                return
            before = self.total_steps
            self._run_slice(local_remaining)
            local_remaining -= self.total_steps - before
        text = self.session.snapshot().text()
        if not all(marker in text for marker in markers):
            missing = tuple(marker for marker in markers if marker not in text)
            raise JourneyFailure(f"timed out waiting for screen markers {missing!r}")

    def settle_input(self) -> None:
        remaining = min(
            INPUT_MAX_STEPS,
            TOTAL_MAX_STEPS - self.total_steps,
        )
        target_revision = self.session.revision + 1
        while remaining > 0:
            before = self.total_steps
            self._run_slice(remaining)
            remaining -= self.total_steps - before
            if (
                not self.session.system.uart.has_rx_data
                and self.session.revision >= target_revision
            ):
                return
        raise JourneyFailure("Desk did not consume and repaint after input")

    def type_text(self, text: str) -> None:
        """Preserve key order on the timing-correct full Desktop loop."""

        for character in text:
            self.session.send_text(character)
            self.settle_input()

    def sample(self, label: str) -> int:
        return self.ledger.observe_stable(
            label,
            self.session.system.storage._image_data,
        )

    def focus(self, slot: int, title: str) -> None:
        self.session.send_key(f"alt+{slot}")
        self.wait_screen(f"[{slot}:{title}*")

    def toggle_full_frame(self) -> None:
        self.session.send_key("alt+f")
        self.settle_input()

    def approve_once(self, call_number: int) -> None:
        self.wait_screen("PgDn to inspect all rows")
        for _ in range(33):
            if "[F6] Approve once" in self.session.snapshot().text():
                self.session.send_key("f6")
                return
            self.session.send_key("pagedown")
            self.settle_input()
        raise JourneyFailure(
            f"call {call_number} review did not unlock after bounded PageDown"
        )

    def verify_streams_state(self, state: str) -> None:
        self.focus(2, "Streams")
        self.toggle_full_frame()
        self.session.send_key("ctrl+b")
        self.wait_screen("burrow", "state", state, "collection")
        self.sample(f"Streams UI {state}")
        self.toggle_full_frame()

    def verify_library_views(self) -> None:
        self.focus(1, "Library")
        self.toggle_full_frame()
        self.session.send_key("ctrl+r")
        self.wait_screen(DOCUMENT_TITLE, DOCUMENT_CONTENT)
        self.sample("Library document visible")
        self.session.send_text("c")
        self.wait_screen(COLLECTION_TITLE)
        self.sample("Library collection visible")
        self.toggle_full_frame()

    def run(self) -> str:
        # Cold source qualification has to cover the whole linked Desktop
        # closure before this fixture can emit its first marker.  Keep that
        # startup allowance within the single journey ceiling while leaving
        # the other half for UI input, reviews, persistence, and teardown.
        self.wait_raw(CONFIGURED_MARKER, step_budget=CONFIGURE_MAX_STEPS)
        self.wait_screen("[1:Library", "[2:Streams", "[3:Agent")
        self.sample("Desk product ready")

        self.focus(3, "Agent")
        self.toggle_full_frame()
        self.wait_screen("Burrow", "Ready")
        self.session.send_key("ctrl+l")
        self.wait_screen("Ask:")
        self.type_text(PROMPT)
        self.session.send_key("enter")
        self.settle_input()

        for call_number, operation in enumerate(EXPECTED_CALLS, start=1):
            self.wait_raw(
                f"DESK LIBRARY BURROW CALL {call_number} {operation}"
            )
            if call_number in MUTATION_CALLS:
                self.approve_once(call_number)
            self.wait_raw(
                f"DESK LIBRARY BURROW RESULT {call_number} {operation} PASS"
            )
            self.sample(f"tool result {call_number} {operation}")

            if call_number == 6:
                self.wait_raw(RUNNING_MARKER)
                self.toggle_full_frame()
                self.verify_streams_state("running")
                self.focus(3, "Agent")
                self.toggle_full_frame()

        self.wait_raw(STOPPED_MARKER)
        self.wait_raw(AGENT_PASS_MARKER)
        self.toggle_full_frame()
        self.verify_streams_state("stopped")
        self.verify_library_views()

        # F12 is a test-only outer-input seam.  The fixture posts one normal
        # ASHELL-QUIT action only after the completed run; Desk itself then
        # performs ordinary child request-close, shutdown, and Practice fini.
        self.focus(3, "Agent")
        self.session.send_key("f12")
        self.wait_raw(OUTER_QUIT_MARKER)
        self.wait_raw(PASS_MARKER)
        self.sample("ordinary Desk teardown")
        raw = self.session.raw_text()
        self._assert_runtime_evidence(raw)
        return raw

    @staticmethod
    def _assert_runtime_evidence(raw: str) -> None:
        calls = tuple(
            (int(number), operation)
            for number, operation in CALL_RE.findall(raw)
        )
        expected_calls = tuple(enumerate(EXPECTED_CALLS, start=1))
        if calls != expected_calls:
            raise JourneyFailure(
                f"tool-call order changed: expected {expected_calls!r}, got {calls!r}"
            )
        results = tuple(
            (int(number), operation)
            for number, operation in RESULT_RE.findall(raw)
        )
        if results != expected_calls:
            raise JourneyFailure(f"tool-result order changed: {results!r}")
        facets = tuple(
            (name, int(count)) for name, count in FACET_RE.findall(raw)
        )
        expected_facets = tuple(
            (name, len(EXPECTED_FACETS[name]))
            for name in ("CHAT", "READ", "ASSIST", "OPERATOR")
        )
        if facets != expected_facets:
            raise JourneyFailure(
                f"live focused facet evidence changed: {facets!r}"
            )
        for marker in (
            RUNNING_MARKER,
            STOPPED_MARKER,
            AGENT_PASS_MARKER,
            OUTER_QUIT_MARKER,
            PASS_MARKER,
        ):
            if raw.count(marker) != 1:
                raise JourneyFailure(
                    f"terminal marker {marker!r} occurred {raw.count(marker)} times"
                )


def _run_product(image: Path, timeout: float) -> int:
    profile = harness.PROFILES[PROFILE]
    built = harness.build_image(PROFILE, image)
    if built.stat().st_size != TOTAL_SECTORS * 512:
        raise JourneyFailure("focused product image is not exactly 8192 sectors")
    ledger = SpaceLedger(built.read_bytes())
    started = time.monotonic()

    journey: ProductJourney | None = None
    try:
        with harness.MachineSession.from_bios(
            harness.MEGAPAD_ROOT / "bios.asm",
            storage_image=built,
            cols=COLS,
            rows=ROWS,
            batch_steps=500_000,
            ext_mem_size=EXT_MEMORY_BYTES,
            num_cores=NUM_CORES,
        ) as session:
            storage = session.system.storage
            original_complete = storage._complete

            def observed_complete(result: int, transferred: int) -> None:
                request = storage._active_request
                completed_write_effect = bool(
                    request is not None
                    and request[0] == STORAGE_CMD_WRITE
                    and storage._active_effect
                )
                original_complete(result, transferred)
                if completed_write_effect:
                    ledger.observe_completed_write(storage._image_data)

            storage._complete = observed_complete
            session.boot()
            journey = ProductJourney(session, profile, ledger, timeout)
            journey.run()
    except (AssertionError, JourneyFailure, RuntimeError, ValueError) as error:
        print(f"Desk Library Burrow product: FAIL\n  {error}")
        if journey is not None:
            raw = journey.session.raw_text()
            screen = journey.session.snapshot().text()
            elapsed = time.monotonic() - started
            print(
                f"  {journey.total_steps:,} guest steps in {elapsed:.2f}s; "
                f"MP64FS build/minimum {ledger.build_free}/"
                f"{ledger.minimum_free} free sectors"
            )
            for sample in ledger.stable_samples:
                print(f"    {sample.label}: {sample.free_sectors} free sectors")
            print(screen)
            print(raw[-8000:])
        return 1

    saved_free = ledger.observe_stable("saved final image", built.read_bytes())
    peak_consumed = ledger.build_free - ledger.minimum_free
    retained_consumed = ledger.build_free - saved_free
    largest_increment = max(
        (
            previous.free_sectors - current.free_sectors
            for previous, current in zip(
                ledger.stable_samples,
                ledger.stable_samples[1:],
            )
            if previous.free_sectors > current.free_sectors
        ),
        default=0,
    )
    elapsed = time.monotonic() - started
    if ledger.minimum_free <= largest_increment:
        print(
            "Desk Library Burrow product: FAIL\n"
            "  measured MP64FS headroom cannot absorb one more largest "
            "observed stable persistence increment\n"
            f"  minimum free: {ledger.minimum_free} sectors; "
            f"largest increment: {largest_increment} sectors"
        )
        return 1
    print(
        "Desk Library Burrow product: PASS\n"
        f"  image: {built}\n"
        f"  guest: {journey.total_steps:,} steps in {elapsed:.2f}s; "
        f"one core, {EXT_MEMORY_BYTES >> 20} MiB external memory\n"
        f"  MP64FS build: {ledger.build_free} free sectors "
        f"({ledger.build_free * 512:,} bytes)\n"
        f"  MP64FS observed minimum: {ledger.minimum_free} free sectors "
        f"({ledger.minimum_free * 512:,} bytes remaining headroom)\n"
        f"  MP64FS observed peak consumption: {peak_consumed} sectors "
        f"({peak_consumed * 512:,} bytes)\n"
        f"  MP64FS largest stable persistence increment: "
        f"{largest_increment} sectors ({largest_increment * 512:,} bytes); "
        "one-more-increment headroom PASS\n"
        f"  MP64FS final: {saved_free} free sectors; retained consumption "
        f"{retained_consumed} sectors ({retained_consumed * 512:,} bytes)\n"
        f"  storage evidence: {ledger.completed_write_samples} valid completed-"
        f"write samples, {ledger.transient_parse_failures} transient views ignored"
    )
    for sample in ledger.stable_samples:
        print(f"    {sample.label}: {sample.free_sectors} free sectors")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument("--product", action="store_true")
    parser.add_argument("--image", type=Path, default=IMAGE)
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_SECONDS)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be greater than zero")

    _assert_static_contracts()
    if args.static_only:
        print("DESK LIBRARY BURROW STATIC PASS")
        return 0
    return _run_product(args.image, args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
