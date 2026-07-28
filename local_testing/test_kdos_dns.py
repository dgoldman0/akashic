#!/usr/bin/env python3
"""Qualify the generic caller-owned KDOS DNS exchange adapter."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
SOURCE = ROOT / "akashic" / "net" / "transports" / "kdos-dns.f"
DOC = ROOT / "docs" / "net" / "kdos-dns.md"
CONTRACT = LOCAL_TESTING / "kdos-dns-test.f"
NET_STUB = LOCAL_TESTING / "kdos-dns-net-stub.f"

PROFILE = "kdos-dns-contracts"
IMAGE = Path("/tmp/akashic-kdos-dns-contracts.img")
PASS_MARKER = "KDOS DNS CONTRACT PASS"
PHASE_MAX_STEPS = 120_000_000
LIFECYCLE_MAX_STEPS = 30_000_000
LOAD_STAGES = (
    ("net-stub", "KDOS DNS NET STUB READY"),
    ("memory-span", "KDOS DNS MEMORY SPAN READY"),
    ("caller-span", "KDOS DNS CALLER SPAN READY"),
    ("source", "KDOS DNS SOURCE READY"),
    ("fixture", "KDOS DNS FIXTURE READY"),
)
LIFECYCLE_STAGES = (
    ("admission", "KDOS DNS LIFE ADMISSION"),
    ("flags", "KDOS DNS LIFE FLAGS"),
    ("owner", "KDOS DNS LIFE OWNER"),
    ("root", "KDOS DNS LIFE ROOT"),
    ("binding", "KDOS DNS LIFE BINDING"),
    ("complete-prep", "KDOS DNS COMPLETE PREP"),
    ("complete-poll", "KDOS DNS COMPLETE POLL"),
    ("complete-response", "KDOS DNS COMPLETE RESPONSE"),
    ("complete", "KDOS DNS LIFE COMPLETE"),
    ("faults", "KDOS DNS LIFE FAULTS"),
    ("cleanup", "KDOS DNS LIFE CLEANUP"),
    ("reclaim", "KDOS DNS LIFE RECLAIM"),
    ("framing", "KDOS DNS LIFE FRAMING"),
    ("finish", PASS_MARKER),
)

AUTOEXEC = r"""\ autoexec.f - caller-owned KDOS DNS contracts
ENTER-USERLAND
REQUIRE local_testing/kdos-dns-net-stub.f
DEPTH IF ." KDOS DNS LOAD STACK FAIL net-stub" CR TX-FLUSH THEN
." KDOS DNS NET STUB READY" CR TX-FLUSH
KEY DROP
REQUIRE utils/memory-span.f
DEPTH IF ." KDOS DNS LOAD STACK FAIL memory-span" CR TX-FLUSH THEN
." KDOS DNS MEMORY SPAN READY" CR TX-FLUSH
KEY DROP
REQUIRE utils/caller-span.f
DEPTH IF ." KDOS DNS LOAD STACK FAIL caller-span" CR TX-FLUSH THEN
." KDOS DNS CALLER SPAN READY" CR TX-FLUSH
KEY DROP
REQUIRE net/transports/kdos-dns.f
DEPTH IF ." KDOS DNS LOAD STACK FAIL source" CR TX-FLUSH THEN
." KDOS DNS SOURCE READY" CR TX-FLUSH
KEY DROP
REQUIRE local_testing/kdos-dns-test.f
DEPTH IF ." KDOS DNS LOAD STACK FAIL fixture" CR TX-FLUSH THEN
." KDOS DNS FIXTURE READY" CR TX-FLUSH
KEY DROP
_KDT-RUN
TX-FLUSH
"""

def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing definition for {name}"
    return match.group("body")


def _assert_physical_comments(path: Path, source: str) -> None:
    for line_number, line in enumerate(source.splitlines(), start=1):
        forth_code = line.split("\\", 1)[0]
        if "(" in forth_code:
            assert ")" in forth_code.split("(", 1)[1], (
                "KDOS parenthesized comments must close on their "
                f"physical line: {path}:{line_number}"
            )


def _assert_static_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")
    doc_flat = " ".join(doc.split())
    fixture = CONTRACT.read_text(encoding="utf-8")
    net_stub = NET_STUB.read_text(encoding="utf-8")

    assert 0 < PHASE_MAX_STEPS <= 120_000_000
    assert 0 < LIFECYCLE_MAX_STEPS <= PHASE_MAX_STEPS
    assert all(marker in AUTOEXEC for _, marker in LOAD_STAGES)
    assert AUTOEXEC.count("KEY DROP") == len(LOAD_STAGES)
    assert "PROVIDED akashic-kdos-dns" in source
    assert re.findall(
        r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source
    ) == [
        "../../utils/memory-span.f",
        "../../utils/caller-span.f",
    ]
    assert not re.search(r"(?mi)^[ \t]*CREATE\b", source)
    for forbidden in (
        "REQUIRE ../../atproto/",
        "REQUIRE ../../security/oauth",
        "REQUIRE ../dns-txt.f",
        "REQUIRE ../../tui/",
    ):
        assert forbidden not in source

    for word in (
        "KDOSDNS-SIZE",
        "KDOSDNS-QUERY-MAX",
        "KDOSDNS-RESPONSE-MAX",
        "KDOSDNS-INIT",
        "KDOSDNS-VALID?",
        "KDOSDNS-START",
        "KDOSDNS-POLL",
        "KDOSDNS-CANCEL",
        "KDOSDNS-WIPE",
        "KDOSDNS-STATE@",
        "KDOSDNS-STATUS@",
        "KDOSDNS-PHASE@",
        "KDOSDNS-RESPONSE$",
        "KDOSDNS-USED-TCP?",
        "KDOSDNS-RCODE@",
        "KDOSDNS-FLAGS@",
        "KDOSDNS-EVIDENCE@",
        "KDOSDNS-STEP-COUNT@",
        "KDOSDNS-LAST-STEP-CYCLES@",
        "KDOSDNS-MAX-STEP-CYCLES@",
        "KDOSDNS-S-CLEANUP",
        "KDOSDNS-E-TRUNCATED",
        "KDOSDNS-E-TCP-LENGTH",
        "KDOSDNS-E-CLEANUP-FALLBACK",
    ):
        assert word in source

    assert re.search(r"(?m)^512[ \t]+CONSTANT KDOSDNS-QUERY-MAX$", source)
    assert re.search(
        r"(?m)^65535 CONSTANT KDOSDNS-RESPONSE-MAX$", source
    )
    assert re.search(r"(?m)^1368 CONSTANT KDOSDNS-SIZE$", source)
    assert "_KDNS-QUERY _KDNS-TCP-FRAME - 2 <>" in source

    query_valid = _word_body(source, "_KDNS-QUERY-VALID?")
    for marker in (
        "0x8000",
        "0x7800",
        "0x06CF",
        "NW16@ 1 <>",
        "KDOSDNS-WIRE-NAME-MAX",
        "KDOSDNS-QUERY-MAX",
    ):
        assert marker in query_valid

    next_port = _word_body(source, "_KDNS-NEXT-LOCAL-PORT")
    assert "RANDOM32" in next_port
    assert "_KDOSDNS-NEXT-PORT" not in source

    start = _word_body(source, "KDOSDNS-START")
    assert start.index("_KDNS-SPAN-STATUS") < start.index(
        "_KDNS-START-CLEAR"
    )
    assert start.index("_KDNS-QUERY-VALID?") < start.index(
        "_KDNS-START-CLEAR"
    )
    assert start.index("MSPAN-OVERLAP?") < start.index(
        "_KDNS-START-CLEAR"
    )
    assert "_KDNS.QUERY" in start
    assert "_KDNS-CAPTURE-QUESTION" in start
    assert "_KDOSDNS-OWNER !" in start
    assert start.index("_KDNS-START-SOURCES") < start.index(
        "_KDNS-START-CLEAR"
    )
    assert "CATCH IF KDOSDNS-S-FAULT EXIT THEN" in start

    question = _word_body(source, "_KDNS-QUESTION-MATCH?")
    for marker in (
        "_KDNS.QUERY-ID",
        "0x8000",
        "0x7800",
        "0x0040",
        "_KDNS-DECODE-NAME",
        "_KDNS.QTYPE",
        "_KDNS.QCLASS",
    ):
        assert marker in question

    udp = _word_body(source, "_KDNS-UDP-RECEIVE-ONE")
    for marker in (
        "IP-RECV",
        "IP-PROTO-UDP",
        "_KDNS.SERVER-IP IP=",
        "UDP-H.SPORT NW16@ 53 <>",
        "_KDNS.LOCAL-PORT",
        "UDP-VERIFY-CKSUM",
        "_KDNS-QUESTION-MATCH?",
        "_KDNS-CAPTURE-DIAGNOSTICS",
        "0x0200",
    ):
        assert marker in udp
    assert udp.index("_KDNS-QUESTION-MATCH?") < udp.index(
        "KDOSDNS-E-SERVER"
    )
    assert "_KDNS.RESPONSE @" in udp

    begin_tcp = _word_body(source, "_KDNS-BEGIN-TCP")
    for marker in (
        "_KDNS.USED-TCP",
        "_KDNS.TCP-PREFIX-U",
        "_KDNS.TCP-EXPECTED-U",
        "_KDNS.TCP-TX-OFFSET",
        "_KDNS.TCP-FRAME NW16!",
        "KDOSDNS-PHASE-TCP-OPEN",
        "KDOSDNS-PHASE-ARP-CHECK",
    ):
        assert marker in begin_tcp

    tcp_prefix = _word_body(source, "_KDNS-STEP-TCP-PREFIX")
    assert "_KDNS.TCP-PREFIX-U @ 2 =" in tcp_prefix
    assert "12 <" in tcp_prefix
    assert "_KDNS.RESPONSE-CAP" in tcp_prefix
    assert "KDOSDNS-E-TCP-LENGTH" in tcp_prefix

    tcp_body = _word_body(source, "_KDNS-STEP-TCP-BODY")
    for marker in (
        "_KDNS.TCP-EXPECTED-U",
        "_KDNS.RESPONSE @",
        "_KDNS-QUESTION-MATCH?",
        "_KDNS-CAPTURE-DIAGNOSTICS",
        "0x0200",
        "KDOSDNS-PHASE-TCP-CLOSE",
    ):
        assert marker in tcp_body

    poll = _word_body(source, "KDOSDNS-POLL")
    assert "['] _KDNS-POLL-INNER CATCH" in poll
    assert "['] _KDNS-POLL-NOW-INNER CATCH" in poll
    assert "_KDNS-STEP-RECORD" in poll
    assert "KDOSDNS-S-TIMEOUT" in poll
    assert "KDOSDNS-S-FAULT" in poll
    poll_now = _word_body(source, "_KDNS-POLL-NOW-INNER")
    assert "_KDNS-NOW@" in poll_now

    abort = _word_body(source, "_KDNS-TCP-ABORT")
    assert "CATCH IF 0 EXIT THEN" in abort
    assert "_KDAB-OK @ 0= IF 0 EXIT THEN" in abort
    assert abort.index("CATCH IF 0 EXIT THEN") < abort.index(
        "_KDNS.TCB !"
    )
    abort_inner = _word_body(source, "_KDNS-TCP-ABORT-INNER")
    assert "_KDNS-TCB-POINTER?" in abort_inner
    assert "may already be reused" in abort_inner

    fail = _word_body(source, "_KDNS-FAIL")
    assert "KDOSDNS-S-CLEANUP <>" in fail
    assert "_KDNS.TCB @ 0= IF" in fail
    assert "_KDNS-RELEASE-OWNER" in fail

    cancel = _word_body(source, "KDOSDNS-CANCEL")
    assert cancel.count("KDOSDNS-S-CLEANUP EXIT") >= 3
    assert cancel.index("_KDNS-TCP-ABORT") < cancel.index(
        "_KDNS-START-CLEAR"
    )

    wipe = _word_body(source, "KDOSDNS-WIPE")
    assert wipe.index("KDOSDNS-CANCEL") < wipe.index(
        "KDOSDNS-SIZE 0 FILL"
    )
    assert wipe.index("KDOSDNS-S-CLEANUP EXIT") < wipe.index(
        "KDOSDNS-SIZE 0 FILL"
    )

    for phrase in (
        "protocol-neutral",
        "caller-owned",
        "UDP is the normative first attempt",
        "exact retained query over TCP",
        "fresh unpredictable value for each logical query",
        "raw DNS message as normative",
        "contains no application-protocol, credential, feed",
        "one active `kdos-dns` adapter at a time",
        "serialize every other KDOS NIC reader",
        "`KDOSDNS-S-CLEANUP` without erasing",
        "not DNS authenticity",
        "real recursive-server journey",
        "https://www.rfc-editor.org/rfc/rfc1035.html",
        "https://www.rfc-editor.org/rfc/rfc7766.html",
    ):
        assert phrase in doc_flat

    assert len(CONTRACT.name) <= 23
    assert len(NET_STUB.name) <= 23
    assert "PROVIDED akashic-kdos-dns-net-stub" in net_stub
    for word in (
        "NW16@",
        "NW16!",
        "IP-RECV",
        "UDP-VERIFY-CKSUM",
        "UDP-SEND",
        "TCP-CONNECT",
        "TCP-SEND",
        "TCP-RECV",
        "TCP-ABORT",
        "TCB-INIT",
    ):
        assert word in net_stub
    assert "PROVIDED akashic-kdos-dns-contracts" in fixture
    for marker in (
        "_kdt-test-init-and-admission",
        "_kdt-test-query-flags",
        "_kdt-test-start-and-owner",
        "_kdt-test-root-question",
        "_kdt-test-question-binding",
        "_kdt-test-complete",
        "_kdt-test-timeout-and-faults",
        "_kdt-test-cleanup-proof",
        "_kdt-test-reclaimed-tcb",
        "_kdt-test-tcp-framing",
        "_kdt-step-complete",
        "_kdt-step-throw",
        "KDOSDNS-S-BUSY",
        "KDOSDNS-S-TIMEOUT",
        "KDOSDNS-S-FAULT",
        "KDOSDNS-E-TRUNCATED",
        "KDOSDNS-STEP-COUNT@",
        PASS_MARKER,
    ):
        assert marker in fixture
    for _, marker in LIFECYCLE_STAGES:
        assert marker in fixture

    for tcp_word in (
        "_KDNS-STEP-TCP-SEND",
        "_KDNS-STEP-TCP-PREFIX",
        "_KDNS-STEP-TCP-BODY",
    ):
        body = _word_body(source, tcp_word)
        assert "TCP-SEND DUP _KDTS-N !" not in body
        assert "TCP-RECV DUP _KDTS-N !" not in body
    assert "- DUP _KDTS-REMAIN !" not in _word_body(
        source, "_KDNS-STEP-TCP-SEND"
    )

    _assert_physical_comments(SOURCE, source)
    _assert_physical_comments(NET_STUB, net_stub)
    _assert_physical_comments(CONTRACT, fixture)


def _run_guest(timeout: float) -> int:
    sys.path.insert(0, str(LOCAL_TESTING))
    import akashic_tui as harness

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("net/transports/kdos-dns.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "KDOS DNS CONTRACT FAIL",
            "KDOS DNS ASSERT",
            "KDOS DNS STACK",
            "KDOS DNS LOAD STACK FAIL",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
            "(not found)",
        ),
        initial_files=(
            (
                "local_testing/kdos-dns-net-stub.f",
                NET_STUB.read_bytes(),
            ),
            (
                "local_testing/kdos-dns-test.f",
                CONTRACT.read_bytes(),
            ),
        ),
        linked=False,
        include_large_sample=False,
        total_sectors=2048,
    )
    image_path = harness.build_image(PROFILE, IMAGE)
    profile = harness.PROFILES[PROFILE]

    def failures(machine: object) -> tuple[str, ...]:
        raw = machine.raw_text()
        screen = machine.screen_text()
        found = list(harness._has_forth_error(raw))
        found.extend(
            harness._matched_failure_markers(profile, raw, screen)
        )
        return tuple(dict.fromkeys(found))

    with harness.MachineSession.from_bios(
        harness.MEGAPAD_ROOT / "bios.asm",
        storage_image=image_path,
        cols=120,
        rows=40,
        batch_steps=100_000,
        ext_mem_size=64 << 20,
        num_cores=1,
    ) as machine:
        machine.boot()
        reports = []
        output = []
        for index, (stage_name, stage_marker) in enumerate(LOAD_STAGES):
            if index:
                machine.clear_output()
                machine.send_text("x")
            report = machine.run(
                max_steps=PHASE_MAX_STEPS,
                wall_timeout_s=timeout,
                until_text=stage_marker,
                text_scope="raw",
            )
            raw = machine.raw_text()
            stage_failures = failures(machine)
            reports.append((stage_name, report))
            output.extend((f"\n--- load {stage_name} ---\n", raw))
            print(
                f"  {stage_name}: {report.steps:,} steps in "
                f"{report.elapsed_s:.2f}s; stop={report.reason}",
                flush=True,
            )
            if stage_marker not in raw or stage_failures:
                print(
                    "Staged kdos-dns-contracts: FAIL\n"
                    f"  {stage_name}: {report.steps:,} steps in "
                    f"{report.elapsed_s:.2f}s; stop={report.reason}"
                )
                for failure in stage_failures:
                    print(f"  {stage_name} failure: {failure}")
                print(f"  recent guest output:\n{raw[-4000:]}")
                return 1

        machine.clear_output()
        machine.send_text("x")
        lifecycle_reports = []
        for index, (stage_name, stage_marker) in enumerate(
            LIFECYCLE_STAGES
        ):
            if index:
                machine.clear_output()
                machine.send_text("x")
            report = machine.run(
                max_steps=LIFECYCLE_MAX_STEPS,
                wall_timeout_s=min(timeout, 30.0),
                until_text=stage_marker,
                text_scope="raw",
            )
            raw = machine.raw_text()
            stage_failures = failures(machine)
            lifecycle_reports.append((stage_name, report))
            output.extend((f"\n--- lifecycle {stage_name} ---\n", raw))
            print(
                f"  lifecycle-{stage_name}: {report.steps:,} steps in "
                f"{report.elapsed_s:.2f}s; stop={report.reason}",
                flush=True,
            )
            if stage_marker not in raw or stage_failures:
                print(f"Staged kdos-dns-contracts: FAIL ({stage_name})")
                for failure in stage_failures:
                    print(f"  lifecycle-{stage_name} failure: {failure}")
                print(f"  recent guest output:\n{raw[-4000:]}")
                return 1

        root = harness.OUTPUT_ROOT / f"smoke-{PROFILE}"
        root.with_suffix(".raw.txt").write_text(
            "".join(output),
            encoding="utf-8",
        )
        print("Staged kdos-dns-contracts: PASS")
        for stage_name, report in reports:
            print(
                f"  {stage_name}: {report.steps:,} steps in "
                f"{report.elapsed_s:.2f}s; stop={report.reason}"
            )
        for stage_name, report in lifecycle_reports:
            print(
                f"  lifecycle-{stage_name}: {report.steps:,} steps in "
                f"{report.elapsed_s:.2f}s; stop={report.reason}"
            )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--static-only",
        action="store_true",
        help="check source contracts without building or running an image",
    )
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("KDOS DNS STATIC PASS")
        return 0
    return _run_guest(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
