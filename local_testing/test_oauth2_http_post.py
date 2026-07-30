#!/usr/bin/env python3
"""Static and linked qualification for the generic OAuth 2 HTTP POST owner."""

from __future__ import annotations

import argparse
import re
import sys
import time
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


COMMON = LOCAL_TESTING / "o2-http-post-common.f"
MAIN_CONTRACT = LOCAL_TESTING / "o2-http-post-main.f"
ADMISSION_CONTRACT = LOCAL_TESTING / "o2-http-post-admit.f"
TRANSPORT_CONTRACT = LOCAL_TESTING / "o2-http-post-xport.f"
CLEANUP_CONTRACT = LOCAL_TESTING / "o2-http-post-clean.f"
CONTRACTS = (
    COMMON,
    MAIN_CONTRACT,
    ADMISSION_CONTRACT,
    TRANSPORT_CONTRACT,
    CLEANUP_CONTRACT,
)
SOURCE = (
    LOCAL_TESTING.parent
    / "akashic"
    / "security"
    / "oauth2"
    / "http-post.f"
)
TARGET = LOCAL_TESTING.parent / "akashic" / "net" / "http-target.f"
DOC = LOCAL_TESTING.parent / "docs" / "security" / "oauth2-http-post.md"

SUITES = (
    (
        "oauth2-http-post-main",
        Path("/tmp/akashic-oauth2-http-post-main.img"),
        "_O2HPT-RUN-MAIN",
        MAIN_CONTRACT,
    ),
    (
        "oauth2-http-post-admission",
        Path("/tmp/akashic-oauth2-http-post-admission.img"),
        "_O2HPT-RUN-ADMISSION",
        ADMISSION_CONTRACT,
    ),
    (
        "oauth2-http-post-transport",
        Path("/tmp/akashic-oauth2-http-post-transport.img"),
        "_O2HPT-RUN-TRANSPORT",
        TRANSPORT_CONTRACT,
    ),
    (
        "oauth2-http-post-cleanup",
        Path("/tmp/akashic-oauth2-http-post-cleanup.img"),
        "_O2HPT-RUN-CLEANUP",
        CLEANUP_CONTRACT,
    ),
)

PHASE_STEP_BUDGET = 250_000_000
PHASE_CHUNK_STEPS = 50_000_000
PASS_MARKER = "OAUTH2 HTTP POST PASS"
RESET_MARKER = "Megapad-64 Forth BIOS"


def _load_marker(contract: Path) -> str:
    return f"OAUTH2 HTTP POST {contract.stem.upper()} LOAD READY"


def _autoexec(entry: str, contract: Path) -> str:
    return rf"""\ autoexec.f - generic OAuth 2 HTTP POST contracts
ENTER-USERLAND
." OAUTH2 HTTP POST LOAD START" CR TX-FLUSH
REQUIRE security/oauth2/http-post.f
." OAUTH2 HTTP POST SOURCE READY" CR TX-FLUSH
REQUIRE local_testing/{contract.name}
." OAUTH2 HTTP POST FIXTURE READY" CR TX-FLUSH
DEPTH IF ." OAUTH2 HTTP POST LOAD STACK FAIL" CR TX-FLUSH THEN
." {_load_marker(contract)}" CR TX-FLUSH
KEY DROP
." OAUTH2 HTTP POST GATE RELEASED" CR TX-FLUSH
{entry}
"""


def _contract_bytes(path: Path) -> bytes:
    return harness._minify_forth(  # noqa: SLF001
        path.read_text(encoding="utf-8")
    ).encode("utf-8")


def _guest_failures(
    profile: harness.Profile,
    raw: str,
    screen: str,
) -> tuple[str, ...]:
    failures = list(harness._has_forth_error(raw))  # noqa: SLF001
    failures.extend(
        harness._matched_failure_markers(  # noqa: SLF001
            profile, raw, screen
        )
    )
    return tuple(dict.fromkeys(failures))


def _run_until_marker(
    session: harness.MachineSession,
    profile: harness.Profile,
    marker: str,
    *,
    timeout: float,
    reset_is_failure: bool = False,
) -> tuple[bool, int, float, str, tuple[str, ...]]:
    started = time.monotonic()
    deadline = started + timeout
    steps = 0
    reason = "step_budget"

    while steps < PHASE_STEP_BUDGET and time.monotonic() < deadline:
        raw = session.raw_text()
        screen = session.screen_text()
        if reset_is_failure and RESET_MARKER in raw:
            return (
                False,
                steps,
                time.monotonic() - started,
                "guest_reset",
                ("unexpected guest reset",),
            )
        failures = _guest_failures(profile, raw, screen)
        if failures:
            return (
                False,
                steps,
                time.monotonic() - started,
                "guest_failure",
                failures,
            )
        if marker in raw:
            return (
                True,
                steps,
                time.monotonic() - started,
                "matched",
                (),
            )

        remaining = PHASE_STEP_BUDGET - steps
        report = session.run(
            max_steps=min(PHASE_CHUNK_STEPS, remaining),
            wall_timeout_s=min(
                2.0,
                max(0.05, deadline - time.monotonic()),
            ),
            until_text=marker,
            text_scope="raw",
        )
        steps += report.steps
        reason = report.reason
        if report.reason in ("halted", "stalled", "idle"):
            break

    raw = session.raw_text()
    screen = session.screen_text()
    if reset_is_failure and RESET_MARKER in raw:
        return (
            False,
            steps,
            time.monotonic() - started,
            "guest_reset",
            ("unexpected guest reset",),
        )
    failures = _guest_failures(profile, raw, screen)
    if marker in raw and not failures:
        return (
            True,
            steps,
            time.monotonic() - started,
            "matched",
            (),
        )
    return (
        False,
        steps,
        time.monotonic() - started,
        reason,
        failures,
    )


def _finish_to_idle(
    session: harness.MachineSession,
    profile: harness.Profile,
    *,
    used_steps: int,
    started: float,
    timeout: float,
) -> tuple[bool, int, float, str, tuple[str, ...]]:
    steps = used_steps
    deadline = started + timeout
    reason = "step_budget"

    while steps < PHASE_STEP_BUDGET and time.monotonic() < deadline:
        remaining = PHASE_STEP_BUDGET - steps
        report = session.wait_for_idle(
            max_steps=min(PHASE_CHUNK_STEPS, remaining),
            wall_timeout_s=min(
                2.0,
                max(0.05, deadline - time.monotonic()),
            ),
        )
        steps += report.steps
        reason = report.reason
        raw = session.raw_text()
        screen = session.screen_text()
        failures = _guest_failures(profile, raw, screen)
        if failures:
            return (
                False,
                steps,
                time.monotonic() - started,
                "guest_failure",
                failures,
            )
        if report.reason == "idle":
            return (
                True,
                steps,
                time.monotonic() - started,
                "idle",
                (),
            )
        if report.reason in ("halted", "stalled"):
            break

    return (
        False,
        steps,
        time.monotonic() - started,
        reason,
        (),
    )


def _write_captures(
    profile_name: str,
    session: harness.MachineSession,
    raw: str,
) -> None:
    capture_root = harness.OUTPUT_ROOT / f"smoke-{profile_name}"
    screen = session.snapshot()
    screen.write_text(capture_root.with_suffix(".txt"))
    screen.write_json(capture_root.with_suffix(".cells.json"))
    screen.write_png(
        capture_root.with_suffix(".png"),
        font_path=(
            harness.AKASHIC_ROOT
            / "assets"
            / "fonts"
            / "DejaVuSansMono.ttf"
        ),
    )
    capture_root.with_suffix(".raw.txt").write_text(
        raw, encoding="utf-8"
    )


def _staged_smoke(
    profile_name: str,
    image_path: Path,
    contract: Path,
    *,
    timeout: float,
) -> bool:
    profile = harness.PROFILES[profile_name]
    load_marker = _load_marker(contract)
    combined_raw = ""

    with harness.MachineSession.from_bios(
        harness.MEGAPAD_ROOT / "bios.asm",
        storage_image=image_path,
        cols=120,
        rows=40,
        batch_steps=500_000,
        ext_mem_size=128 << 20,
        num_cores=1,
    ) as session:
        session.boot()

        load_started = time.monotonic()
        load = _run_until_marker(
            session,
            profile,
            load_marker,
            timeout=timeout,
        )
        load_raw = session.raw_text()
        combined_raw = load_raw

        if not load[0]:
            _write_captures(profile_name, session, combined_raw)
            print(
                f"Staged {profile_name}: FAIL\n"
                f"  load: {load[1]:,} steps in {load[2]:.2f}s; "
                f"stop={load[3]}"
            )
            for failure in load[4][-12:]:
                print(f"  load failure: {failure}")
            print(f"  recent guest output:\n{load_raw[-4000:]}")
            return False

        session.clear_output()
        session.send_text("x")

        entry_started = time.monotonic()
        execution = _run_until_marker(
            session,
            profile,
            PASS_MARKER,
            timeout=timeout,
            reset_is_failure=True,
        )
        if execution[0]:
            execution = _finish_to_idle(
                session,
                profile,
                used_steps=execution[1],
                started=entry_started,
                timeout=timeout,
            )
        entry_raw = session.raw_text()
        combined_raw = (
            load_raw
            + "\n--- staged entry ---\n"
            + entry_raw
        )
        _write_captures(profile_name, session, combined_raw)

        ok = execution[0] and PASS_MARKER in entry_raw
        print(
            f"Staged {profile_name}: {'PASS' if ok else 'FAIL'}\n"
            f"  load: {load[1]:,} steps in {load[2]:.2f}s; "
            f"stop={load[3]}\n"
            f"  entry: {execution[1]:,} steps in "
            f"{execution[2]:.2f}s; stop={execution[3]}"
        )
        if not ok:
            for failure in execution[4][-12:]:
                print(f"  entry failure: {failure}")
            print(f"  recent guest output:\n{entry_raw[-4000:]}")
        return ok


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing definition for {name}"
    return match.group("body")


def _assert_source_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    target = TARGET.read_text(encoding="utf-8")
    documentation = DOC.read_text(encoding="utf-8")
    fixtures = {
        path: path.read_text(encoding="utf-8") for path in CONTRACTS
    }
    fixture = "\n".join(fixtures.values())

    for contract in CONTRACTS:
        assert len(contract.name) <= 23
        fixture_key = re.search(
            r"(?m)^PROVIDED[ \t]+(\S+)$", fixtures[contract]
        )
        assert fixture_key is not None
        assert len(fixture_key.group(1)) <= 23
    for contract in CONTRACTS[1:]:
        loaded_fixture = fixtures[COMMON] + "\n" + fixtures[contract]
        words: dict[str, str] = {}
        for name in re.findall(
            r"(?mi)^:[ \t]+(\S+)", loaded_fixture
        ):
            folded = name.casefold()
            assert folded not in words, (
                "case-insensitive fixture word collision: "
                f"{words.get(folded)!r} and {name!r}"
            )
            words[folded] = name
    module_key = re.search(r"(?m)^PROVIDED[ \t]+(\S+)$", source)
    assert module_key is not None
    assert module_key.group(1) == "akashic-oauth2-httppost"
    assert len(module_key.group(1)) <= 23

    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER)\b", source
    ), "the generic transaction owner must keep state in caller memory"
    assert re.findall(r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source) == [
        "../../net/http-target.f",
        "../../net/form-urlencoded-writer.f",
        "../../net/http-request.f",
        "../../net/http-buffered.f",
        "../../net/media-type.f",
        "../../utils/memory-span.f",
        "../../utils/caller-span.f",
        "../../utils/string.f",
    ]
    assert "atproto/" not in source.lower()
    assert "tui/applets/streams" not in source.lower()
    assert "redirect" in source.lower()
    assert "HTARGET-REDIRECT" not in source

    public_words = (
        "OAUTH2-HTTP-POST-SIZE",
        "OAUTH2-HTTP-POST-CONFIGURE",
        "OAUTH2-HTTP-POST-BEGIN",
        "OAUTH2-HTTP-POST-CORRELATION-CAPACITY",
        "OAUTH2-HTTP-POST-CORRELATION!",
        "OAUTH2-HTTP-POST-CORRELATION@",
        "OAUTH2-HTTP-POST-EXTERNAL-SPAN-STATUS",
        "OAUTH2-HTTP-POST-FIELD",
        "OAUTH2-HTTP-POST-SEAL",
        "OAUTH2-HTTP-POST-START",
        "OAUTH2-HTTP-POST-POLL",
        "OAUTH2-HTTP-POST-CANCEL",
        "OAUTH2-HTTP-POST-CLEANUP-FINALIZE",
        "OAUTH2-HTTP-POST-WIPE",
        "OAUTH2-HTTP-POST-TARGET@",
        "OAUTH2-HTTP-POST-HTU$",
        "OAUTH2-HTTP-POST-BODY@",
        "OAUTH2-HTTP-POST-NONCE@",
        "OAUTH2-HTTP-POST-DPOP-INCLUDED?",
        "OAUTH2-HTTP-POST-DPOP-SENT?",
    )
    for word in public_words:
        assert word in source

    assert ": HTARGET-HTU$" in target
    htu = _word_body(target, "HTARGET-HTU$")
    assert "HTARGET-VALID?" in htu
    assert "_HTARGET-HTU-LENGTH" in htu
    assert "?DO" not in _word_body(target, "_HTARGET-HTU-LENGTH")

    configure = _word_body(source, "OAUTH2-HTTP-POST-CONFIGURE")
    assert configure.index("_O2HP-CONFIG-PREFLIGHT") < configure.index(
        "FILL"
    )
    preflight = _word_body(source, "_O2HP-CONFIG-PREFLIGHT")
    assert "_O2HP-RECONFIG-STATUS" in preflight
    assert preflight.count("_O2HP-SPAN-STATUS") == 5
    assert preflight.count("MSPAN-OVERLAP?") == 4
    assert "_O2HP-ARENA-GEOMETRY" in source

    valid = _word_body(source, "OAUTH2-HTTP-POST-VALID?")
    assert "_O2HP-PERSISTENT-ARENAS-DISJOINT?" in valid
    assert "OAUTH2-HTTP-POST-SIZE 8 - _O2HP-ZERO?" in valid
    assert "_O2HP-KIND-EXPECTED?" in valid
    assert "_O2HP-SUBORDINATE-BINDINGS?" in valid
    assert "_O2HP-FLAGS-CONSISTENT?" in valid
    assert "_O2HP-CORRELATION-CANONICAL?" in valid
    flags = _word_body(source, "_O2HP-FLAGS-CONSISTENT?")
    assert "OAUTH2-HTTP-POST-F-DPOP-SENT" in flags
    assert "OAUTH2-HTTP-POST-F-DPOP-INCLUDED" in flags
    assert "OAUTH2-HTTP-POST-F-AUTHORIZATION-SENT" in flags
    assert "OAUTH2-HTTP-POST-F-AUTHORIZATION-INCLUDED" in flags
    assert "OAUTH2-HTTP-POST-STATE-SEALED" in flags

    hreq_binding = _word_body(source, "_O2HP-HREQ-BINDING?")
    assert "_O2HP-HREQ-COUNTERS?" in hreq_binding
    assert "_O2HP-HREQ-STATE-COUNTERS?" in hreq_binding
    hbuf_binding = _word_body(source, "_O2HP-HBUF-BINDING?")
    assert "HBUF.BODY-U" in hbuf_binding
    assert "HBUF.FLAGS" in hbuf_binding
    assert "_O2HP-HBUF-PARSER-BINDING?" in hbuf_binding
    parser_binding = _word_body(
        source, "_O2HP-HBUF-PARSER-BINDING?"
    )
    for binding in (
        "HSTR.HEADERS-XT",
        "HSTR.BODY-XT",
        "HSTR.CONTEXT",
        "HSTR.BODY-LIMIT",
    ):
        assert binding in parser_binding
    subordinate = _word_body(
        source, "_O2HP-SUBORDINATE-BINDINGS?"
    )
    assert "HBUF-STATE-IDLE" in subordinate
    assert "_O2HP-HBUF-ACTIVE-STATE?" in subordinate
    assert "_O2HP-HBUF-CLEANUP-STATE?" in subordinate

    external = _word_body(
        source, "OAUTH2-HTTP-POST-EXTERNAL-SPAN-STATUS"
    )
    assert "OAUTH2-HTTP-POST-VALID?" in external
    assert "_O2HP-SPAN-STATUS" in external
    assert external.count("MSPAN-OVERLAP?") == 4
    for arena in (
        "_O2HP.REQUEST-A",
        "_O2HP.REQUEST-CAP",
        "_O2HP.FORM-A",
        "_O2HP.FORM-CAP",
        "_O2HP.RESPONSE-A",
        "_O2HP.RESPONSE-CAP",
    ):
        assert arena in external

    correlation = _word_body(
        source, "OAUTH2-HTTP-POST-CORRELATION!"
    )
    assert "OAUTH2-HTTP-POST-STATE-BUILDING" in correlation
    assert "OAUTH2-HTTP-POST-CORRELATION-CAPACITY" in correlation
    assert "_O2HP-SPAN-STATUS" in correlation
    assert "OAUTH2-HTTP-POST-S-CAPACITY" in correlation
    assert "OAUTH2-HTTP-POST-S-ALIAS" in correlation
    assert correlation.index("_O2HP-CLEAR-CORRELATION") < (
        correlation.index("MOVE")
    )
    reset = _word_body(source, "_O2HP-RESET-OPERATION")
    assert "_O2HP-CLEAR-CORRELATION" in reset

    seal = _word_body(source, "OAUTH2-HTTP-POST-SEAL")
    assert "FUEW-SEAL" in seal
    assert "FUEW-BODY@" in seal
    assert "HREQ-BODY" in seal
    assert "OAUTH2-HTTP-POST-F-DPOP-INCLUDED" in seal
    assert "_O2HP-OPTIONAL-REQUEST-ALIAS?" in seal

    port_preflight = _word_body(source, "_O2HP-PORT-PREFLIGHT")
    assert "_O2HP-COOPERATIVE-PORT?" in port_preflight
    assert "_O2HP-DETACHED-PORT?" in port_preflight
    assert "_O2HP-PORT-ALIASES?" in port_preflight
    start = _word_body(source, "OAUTH2-HTTP-POST-START")
    assert start.index("_O2HP-PORT-PREFLIGHT") < start.index("HBUF-START")
    poll = _word_body(source, "OAUTH2-HTTP-POST-POLL")
    assert poll.index("_O2HP-MARK-SEND-ATTEMPT") < poll.index("HBUF-POLL")

    harden = _word_body(source, "_O2HP-HEADER-HARDEN")
    for header in (
        'S" content-length"',
        'S" content-type"',
        'S" content-encoding"',
        'S" dpop-nonce"',
        'S" trailer"',
    ):
        assert header in harden
    assert "_O2HP-CAPTURE-NONCE" in harden
    nonce = _word_body(source, "_O2HP-CAPTURE-NONCE")
    assert nonce.index("_O2HP-CLEAR-NONCE") < nonce.index("CMOVE")
    nonce_value = _word_body(source, "_O2HP-NONCE-VALUE-DETAIL")
    assert "OAUTH2-HTTP-POST-NONCE-CAPACITY" in nonce_value

    admit = _word_body(source, "_O2HP-ADMIT-RESPONSE")
    assert admit.index("_O2HP-HEADER-HARDEN") < admit.index(
        "_O2HP-OAUTH-CANDIDATE?"
    )
    assert "400" in _word_body(source, "_O2HP-OAUTH-CANDIDATE?")
    assert "401" in _word_body(source, "_O2HP-OAUTH-CANDIDATE?")
    assert "OAUTH2-HTTP-POST-D-BODY-EMPTY" in admit
    assert "_O2HP-MEDIA-DETAIL" in admit

    terminal = _word_body(source, "_O2HP-HANDLE-HBUF-TERMINAL")
    assert terminal.index("_O2HP-ADMIT-RESPONSE") < terminal.index(
        "_O2HP-POISON-CLEANUP"
    )
    cancel = _word_body(source, "OAUTH2-HTTP-POST-CANCEL")
    assert cancel.count("_O2HP-HANDLE-HBUF-TERMINAL") == 2
    finalize = _word_body(
        source, "OAUTH2-HTTP-POST-CLEANUP-FINALIZE"
    )
    assert "_O2HP-PORT-PREFLIGHT" not in finalize
    assert "_O2HP-RETAINED-PORT-GEOMETRY?" in finalize
    assert "_O2HP-DETACHED-PORT?" in finalize
    assert "_O2HP-ADMIT-RESPONSE" in finalize
    assert "_O2HP-FINISH-CERTAIN" in finalize

    fixture_markers = (
        "_o2hpt-main-cases",
        "_O2HPT-RUN-MAIN",
        "_O2HPT-RUN-ADMISSION",
        "_O2HPT-RUN-TRANSPORT",
        "_O2HPT-RUN-CLEANUP",
        "_o2hpt-test-oauth-errors",
        "_o2hpt-test-http-outcomes",
        "_o2hpt-test-media-outcomes",
        "_o2hpt-test-nonce-outcomes",
        "_o2hpt-test-descriptor-invariants",
        "_o2hpt-test-alias-and-cancel",
        "_o2hpt-test-partial-send",
        "_o2hpt-test-cleanup-finalize",
        "OAUTH2-HTTP-POST-KIND-TOKEN",
        'S" grant_type"',
        'S" authorization_code"',
        'S" code"',
        'S" a b"',
        'S" DPoP: proof-value"',
        'S" Authorization: Basic client-secret"',
        'S" grant_type=authorization_code&code=a+b"',
        'S" Content-Encoding: identity"',
        'S" DPoP-Nonce: server-nonce-1"',
        "OAUTH2-HTTP-POST-O-SUCCESS",
        "OAUTH2-HTTP-POST-DPOP-INCLUDED?",
        "OAUTH2-HTTP-POST-DPOP-SENT?",
        "OAUTH2-HTTP-POST-CORRELATION!",
        "OAUTH2-HTTP-POST-CORRELATION@",
        "OAUTH2-HTTP-POST-EXTERNAL-SPAN-STATUS",
        "OAUTH2-HTTP-POST-WIPE",
        "HTARGET-HTU$",
        "OAUTH2-HTTP-POST-HTU$",
        "_o2hpt-request _O2HPT-REQUEST-CAPACITY",
        "_o2hpt-form _O2HPT-FORM-CAPACITY",
        "_o2hpt-response _O2HPT-RESPONSE-CAPACITY",
    )
    for marker in fixture_markers:
        assert marker in fixture
    assert fixture.count("OAUTH2-HTTP-POST-START") == 1
    assert "OAUTH2-HTTP-POST-F-DPOP-SENT _o2hpt-post" in fixture
    assert "process-wide non-reentrant" in documentation
    assert "must not call this owner" in documentation
    assert "borrowed source spans" in documentation
    assert "credential-bearing request" in documentation
    assert "exclusively owned and protected" in documentation
    assert re.search(
        r"optional opaque\s+correlation token remain", documentation
    )
    assert "Exact adjacency is accepted" in documentation
    assert not re.search(
        r"(?mi)\b(?:\?DO|DO|\+LOOP|LOOP)\b", fixture
    ), "the fixture must use cursor walks rather than indexed loops"

    for path, forth_source in (
        (SOURCE, source),
        (TARGET, target),
        *((path, forth_source) for path, forth_source in fixtures.items()),
    ):
        for line_number, line in enumerate(
            forth_source.splitlines(), start=1
        ):
            forth_code = line.split("\\", 1)[0]
            if "(" in forth_code:
                assert ")" in forth_code.split("(", 1)[1], (
                    "KDOS parenthesized comments must close on their "
                    f"physical line: {path}:{line_number}"
                )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--static-only",
        action="store_true",
        help="check source and fixture contracts without running an image",
    )
    parser.add_argument(
        "--suite",
        choices=("all", "main", "admission", "transport", "cleanup"),
        default="all",
        help="run all linked suites or one named suite",
    )
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    _assert_source_contracts()
    if args.static_only:
        print("OAUTH2 HTTP POST STATIC PASS")
        return 0

    suites = SUITES
    if args.suite != "all":
        suites = tuple(
            suite for suite in SUITES if suite[0].endswith(args.suite)
        )

    for profile, image_path, entry, contract in suites:
        harness.PROFILES[profile] = harness.Profile(
            roots=("security/oauth2/http-post.f",),
            resources=(),
            autoexec=_autoexec(entry, contract),
            ready_markers=(PASS_MARKER,),
            stable_markers=(PASS_MARKER,),
            failure_markers=(
                "OAUTH2 HTTP POST FAIL",
                "OAUTH2 HTTP POST ASSERT",
                "OAUTH2 HTTP POST STATUS",
                "OAUTH2 HTTP POST LOAD STACK FAIL",
                "DRIVER THROW",
                "dictionary full",
                "exception",
                "Module not found",
                "Path component not found",
                "? (not found)",
            ),
            initial_files=(
                (
                    f"local_testing/{COMMON.name}",
                    _contract_bytes(COMMON),
                ),
                (
                    f"local_testing/{contract.name}",
                    _contract_bytes(contract),
                ),
            ),
            linked=True,
            link_chunk_bytes=192 * 1024,
            include_large_sample=False,
            total_sectors=4096,
        )
        image = harness.build_image(profile, image_path)
        ok = _staged_smoke(
            profile,
            image,
            contract,
            timeout=args.timeout,
        )
        if not ok:
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
