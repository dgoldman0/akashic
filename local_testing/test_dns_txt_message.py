#!/usr/bin/env python3
"""Qualify the generic caller-owned DNS TXT wire utility."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
SOURCE = ROOT / "akashic" / "net" / "dns-txt.f"
DOC = ROOT / "docs" / "net" / "dns-txt.md"
CONTRACT = LOCAL_TESTING / "dns-txt-message-test.f"

PROFILE = "dns-txt-message-contracts"
IMAGE = Path("/tmp/akashic-dns-txt-message-contracts.img")
PASS_MARKER = "DNS TXT MESSAGE PASS"
PHASE_MAX_STEPS = 180_000_000
LOAD_STAGES = (
    ("source", "DNS TXT SOURCE READY"),
    ("fixture", "DNS TXT FIXTURE READY"),
)

AUTOEXEC = r"""\ autoexec.f - caller-owned DNS TXT message contracts
ENTER-USERLAND
REQUIRE net/dns-txt.f
DEPTH IF ." DNS TXT LOAD STACK FAIL source" CR TX-FLUSH THEN
." DNS TXT SOURCE READY" CR TX-FLUSH
KEY DROP
REQUIRE local_testing/dns-txt-message-test.f
DEPTH IF ." DNS TXT LOAD STACK FAIL fixture" CR TX-FLUSH THEN
." DNS TXT FIXTURE READY" CR TX-FLUSH
KEY DROP
_DNTT-RUN
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
    lowered = source.lower()
    doc = DOC.read_text(encoding="utf-8")
    doc_flat = " ".join(doc.split())
    fixture = CONTRACT.read_text(encoding="utf-8")

    assert 0 < PHASE_MAX_STEPS <= 180_000_000
    assert all(marker in AUTOEXEC for _, marker in LOAD_STAGES)
    assert AUTOEXEC.count("KEY DROP") == len(LOAD_STAGES)
    assert "PROVIDED akashic-dns-txt" in source
    assert re.findall(
        r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source
    ) == [
        "../utils/memory-span.f",
        "../utils/caller-span.f",
    ]
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        source,
    ), "the generic utility must own no mutable module state"
    for forbidden in (
        "atproto",
        "streams",
        "oauth",
        "xrpc",
        "dns-resolve",
        "dns-server-ip",
        "udp-send",
        "tcp-",
        "kdos-tls",
    ):
        assert forbidden not in lowered

    for word in (
        "DNS-TXT-LABEL-MAX",
        "DNS-TXT-NAME-MAX",
        "DNS-TXT-WIRE-NAME-MAX",
        "DNS-TXT-QUERY-MAX",
        "DNS-TXT-VALUE-MAX",
        "DNS-TXT-MESSAGE-MAX",
        "DNS-TXT-COMPRESSION-HOPS-MAX",
        "DNS-TXT-QUERY-SIZE",
        "DNS-TXT-RESULT-SIZE",
        "DNS-TXT-RR-RESULT-SIZE",
        "DNS-TXT-ITER-SIZE",
        "DNS-TXT-STATUS-VALID?",
        "DNS-TXT-NAME-VALIDATE",
        "DNS-TXT-QUERY-BUILD",
        "DNS-TXT-QUERY-VALID?",
        "DNS-TXT-QUERY$",
        "DNS-TXT-QUERY-ID@",
        "DNS-TXT-QUERY-WIPE",
        "DNS-TXT-RR-RESULT-INIT",
        "DNS-TXT-RR-RESULT-VALID?",
        "DNS-TXT-RR-PRESENT?",
        "DNS-TXT-RR-PROVISIONAL?",
        "DNS-TXT-RR-PREFIX$",
        "DNS-TXT-RR-TOTAL-LENGTH@",
        "DNS-TXT-RR-COMPLETE?",
        "DNS-TXT-RR-STRING-COUNT@",
        "DNS-TXT-RR-TTL@",
        "DNS-TXT-RR-RESULT-WIPE",
        "DNS-TXT-ITER-BEGIN",
        "DNS-TXT-ITER-NEXT",
        "DNS-TXT-ITER-VALID?",
        "DNS-TXT-ITER-TERMINAL?",
        "DNS-TXT-ITER-VALIDATED?",
        "DNS-TXT-ITER-STATUS@",
        "DNS-TXT-ITER-RCODE@",
        "DNS-TXT-ITER-FLAGS@",
        "DNS-TXT-ITER-EVIDENCE@",
        "DNS-TXT-ITER-MATCHED-COUNT@",
        "DNS-TXT-ITER-WIPE",
        "DNS-TXT-CNAME-RESULT-SIZE",
        "DNS-TXT-CNAME-RESULT-INIT",
        "DNS-TXT-CNAME-RESULT-VALID?",
        "DNS-TXT-CNAME-PARSE",
        "DNS-TXT-CNAME-STATUS@",
        "DNS-TXT-CNAME-TARGET$",
        "DNS-TXT-CNAME-RCODE@",
        "DNS-TXT-CNAME-FLAGS@",
        "DNS-TXT-CNAME-EVIDENCE@",
        "DNS-TXT-CNAME-ANSWER-COUNT@",
        "DNS-TXT-CNAME-MATCHED-COUNT@",
        "DNS-TXT-CNAME-TTL@",
        "DNS-TXT-CNAME-RESULT-WIPE",
        "DNS-TXT-RESULT-INIT",
        "DNS-TXT-RESULT-VALID?",
        "DNS-TXT-PARSE",
        "DNS-TXT-STATUS@",
        "DNS-TXT-VALUE$",
        "DNS-TXT-RCODE@",
        "DNS-TXT-FLAGS@",
        "DNS-TXT-EVIDENCE@",
        "DNS-TXT-ANSWER-COUNT@",
        "DNS-TXT-MATCHED-COUNT@",
        "DNS-TXT-STRING-COUNT@",
        "DNS-TXT-TTL@",
        "DNS-TXT-RESULT-WIPE",
        "DNS-TXT-S-MALFORMED",
        "DNS-TXT-S-MISMATCH",
        "DNS-TXT-S-TRUNCATED",
        "DNS-TXT-S-RCODE",
        "DNS-TXT-S-NODATA",
        "DNS-TXT-S-DUPLICATE",
        "DNS-TXT-S-PROVISIONAL",
        "DNS-TXT-ITER-E-VALIDATED",
        "DNS-TXT-E-CNAME",
    ):
        assert word in source

    assert re.search(
        r"(?m)^304 CONSTANT DNS-TXT-QUERY-SIZE$", source
    )
    assert re.search(
        r"(?m)^512 CONSTANT DNS-TXT-RESULT-SIZE$", source
    )
    assert re.search(
        r"(?m)^512 CONSTANT DNS-TXT-CNAME-RESULT-SIZE$", source
    )
    assert re.search(
        r"(?m)^96 CONSTANT DNS-TXT-RR-RESULT-SIZE$", source
    )
    assert re.search(
        r"(?m)^512 CONSTANT DNS-TXT-ITER-SIZE$", source
    )
    assert re.search(r"(?m)^4096 CONSTANT DNS-TXT-VALUE-MAX$", source)
    assert re.search(r"(?m)^65535 CONSTANT DNS-TXT-MESSAGE-MAX$", source)
    assert "U>=" not in source

    build = _word_body(source, "DNS-TXT-QUERY-BUILD")
    assert build.index("_DNT-QUERY-STATUS") < build.index(
        "_DNT-QUERY-WRITE"
    )
    assert build.index("DNS-TXT-NAME-VALIDATE") < build.index(
        "_DNT-QUERY-WRITE"
    )
    assert build.index("MSPAN-OVERLAP?") < build.index(
        "_DNT-QUERY-WRITE"
    )

    write = _word_body(source, "_DNT-QUERY-WRITE")
    assert "0x0100" in write
    assert "_DNT-TYPE-TXT" in write
    assert "_DNT-CLASS-IN" in write
    assert write.index("_DNTQ-MAGIC-VALUE") > write.index(
        "_DNT-ENCODE-NAME"
    )

    init = _word_body(source, "DNS-TXT-RESULT-INIT")
    assert init.index("_DNT-RESULT-STATUS") < init.index("0 FILL")
    assert init.index("_DNT-SPAN-STATUS") < init.index("0 FILL")
    assert init.index("MSPAN-OVERLAP?") < init.index("0 FILL")
    assert init.index(
        "_DNTR-MAGIC-VALUE R@ _DNTR.MAGIC !"
    ) > init.index("DNS-TXT-S-EMPTY R@ _DNTR.STATUS !")

    result_valid = _word_body(source, "DNS-TXT-RESULT-VALID?")
    for marker in (
        "_DNTR.RCODE @",
        "_DNTR.FLAGS @",
        "_DNTR.EVIDENCE @",
        "_DNTR.ANSWER-COUNT @",
        "_DNTR.MATCHED-COUNT @",
        "_DNTR.STRING-COUNT @",
        "_DNTR.TTL @",
    ):
        assert marker in result_valid
    assert result_valid.count("_DNTR.MATCHED-COUNT @") >= 2
    assert "_DNT-RESULT-LIFECYCLE?" in result_valid

    stored_status = _word_body(source, "_DNT-RESULT-STORED-STATUS?")
    for marker in (
        "DNS-TXT-S-OK",
        "DNS-TXT-S-CAPACITY",
        "DNS-TXT-S-EMPTY",
        "DNS-TXT-S-DUPLICATE",
    ):
        assert marker in stored_status
    for forbidden in (
        "DNS-TXT-S-INVALID",
        "DNS-TXT-S-ALIAS",
        "DNS-TXT-S-RANGE",
        "DNS-TXT-S-PROTECTED",
        "DNS-TXT-S-PLATFORM",
    ):
        assert forbidden not in stored_status

    lifecycle = _word_body(source, "_DNT-RESULT-LIFECYCLE?")
    for marker in (
        "_DNT-RESULT-STORED-STATUS?",
        "DNS-TXT-E-RCODE",
        "DNS-TXT-E-VALUE",
        "DNS-TXT-E-TRUNCATED",
        "DNS-TXT-E-RESPONSE",
        "DNS-TXT-E-ID",
        "_DNT-RESULT-QUESTION?",
        "_DNT-RESULT-RESPONSE-FLAGS?",
        "_DNT-RESULT-RCODE-FLAGS?",
        "_DNT-RESULT-NO-MATCH?",
        "_DNT-RESULT-EMPTY-STATE?",
        "_DNT-RESULT-DIRECT-STATE?",
        "_DNT-RESULT-MALFORMED-STATE?",
        "_DNT-RESULT-MISMATCH-STATE?",
        "_DNT-RESULT-TRUNCATED-STATE?",
        "_DNT-RESULT-RCODE-STATE?",
        "_DNT-RESULT-NODATA-STATE?",
        "_DNT-RESULT-DUPLICATE-STATE?",
    ):
        assert marker in lifecycle

    parse = _word_body(source, "DNS-TXT-PARSE")
    assert parse.index("DNS-TXT-RESULT-VALID?") < parse.index(
        "_DNT-RESULT-RESET"
    )
    assert parse.index("DNS-TXT-QUERY-VALID?") < parse.index(
        "_DNT-RESULT-RESET"
    )
    assert parse.index("_DNT-SPAN-STATUS") < parse.index(
        "_DNT-RESULT-RESET"
    )
    assert parse.index("_DNT-PARSE-ALIASES?") < parse.index(
        "_DNT-RESULT-RESET"
    )
    assert "_DNT-RESULT-FAIL" in parse

    decoder = _word_body(source, "_DNT-NAME-DECODE")
    for marker in (
        "DNS-TXT-COMPRESSION-HOPS-MAX",
        "DNS-TXT-WIRE-NAME-MAX",
        "0xC0 AND",
        "_DNTR.MESSAGE-U",
        "_DNTR.NAME-POS @ U< 0=",
        "DNS-TXT-S-MALFORMED",
    ):
        assert marker in decoder

    question = _word_body(source, "_DNT-PARSE-QUESTION")
    assert "_DNT-NAME=QUERY?" in question
    assert "_DNT-TYPE-TXT" in question
    assert "_DNT-CLASS-IN" in question
    assert "DNS-TXT-E-QUESTION" in question

    txt = _word_body(source, "_DNT-PARSE-TXT-RDATA")
    assert "_DNTR.RDATA-END" in txt
    assert "_DNTR.STRING-COUNT +!" in txt
    assert "_DNTR.CAPACITY" in txt
    assert "CMOVE" in txt

    bind = _word_body(source, "_DNT-BIND-QUESTION")
    for marker in (
        "0x8000",
        "0x7800",
        "0x0040",
        "0x0200",
        "DNS-TXT-S-TRUNCATED",
        "DNS-TXT-S-RCODE",
        "_DNT-PARSE-QUESTION",
        "_DNTR.RCODE !",
    ):
        assert marker in bind
    assert bind.index("_DNT-PARSE-QUESTION") < bind.index("0x0200 AND")
    assert bind.index("_DNT-PARSE-QUESTION") < bind.index("_DNTR.RCODE !")

    body = _word_body(source, "_DNT-PARSE-BODY")
    for marker in (
        "_DNT-BIND-QUESTION",
        "DNS-TXT-S-NODATA",
        "DNS-TXT-S-DUPLICATE",
        "DNS-TXT-E-VALUE",
    ):
        assert marker in body
    assert body.count("_DNT-PARSE-SECTION") == 3

    framing = _word_body(source, "_DNT-TXT-NEXT-STRING")
    for marker in (
        "_DNTR.RDATA-POS",
        "_DNTR.RDATA-END",
        "_DNTR.MESSAGE",
        "DNS-TXT-S-MALFORMED",
    ):
        assert marker in framing
    assert "_DNT-TXT-NEXT-STRING" in txt

    iterator_txt = _word_body(source, "_DNTI-PARSE-TXT-RDATA")
    for marker in (
        "_DNT-TXT-NEXT-STRING",
        "_DNTI-PREFIX-COPY",
        "_DNTRR.TOTAL-U",
        "_DNTRR.COMPLETE",
        "_DNTRR.STRING-COUNT",
        "_DNTRR.TTL",
        "_DNTRR.PROVISIONAL",
    ):
        assert marker in iterator_txt
    iterator_prefix = _word_body(source, "_DNTI-PREFIX-COPY")
    for marker in (
        "_DNTRR.BUFFER",
        "_DNTRR.CAPACITY",
        "_DNTRR.PREFIX-U",
        "_DNT-U-MIN",
        "CMOVE",
    ):
        assert marker in iterator_prefix

    iterator_begin = _word_body(source, "DNS-TXT-ITER-BEGIN")
    assert iterator_begin.index("_DNT-ITER-STATUS") < iterator_begin.index(
        "DNS-TXT-ITER-SIZE 0 FILL"
    )
    assert iterator_begin.index(
        "DNS-TXT-RR-RESULT-VALID?"
    ) < iterator_begin.index("_DNTRR-RESET")
    assert iterator_begin.index(
        "DNS-TXT-QUERY-VALID?"
    ) < iterator_begin.index("_DNTRR-RESET")
    assert iterator_begin.index("_DNTI-ALIASES?") < iterator_begin.index(
        "_DNTRR-RESET"
    )
    assert "_DNT-BIND-QUESTION" in iterator_begin

    iterator_next = _word_body(source, "_DNTI-NEXT-ACTIVE")
    assert iterator_next.count("_DNT-PARSE-RR-HEADER") == 1
    assert iterator_next.count("_DNTI-DRAIN-SECTION") == 2
    for marker in (
        "_DNTI-PARSE-TXT-RDATA",
        "_DNTR.CURSOR",
        "_DNTR.MESSAGE-U",
        "DNS-TXT-ITER-E-VALIDATED",
        "_DNTI-PHASE-VALIDATED",
        "DNS-TXT-S-NODATA",
    ):
        assert marker in iterator_next

    iterator_valid = _word_body(source, "DNS-TXT-ITER-VALID?")
    for marker in (
        "DNS-TXT-RR-RESULT-VALID?",
        "DNS-TXT-QUERY-VALID?",
        "_DNTI-ALIASES?",
        "_DNTI-COMMON-VALID?",
        "_DNTI-ACTIVE-STATE?",
        "_DNTI-VALIDATED-STATE?",
        "_DNTI-FAILED-STATE?",
    ):
        assert marker in iterator_valid

    cname_init = _word_body(source, "DNS-TXT-CNAME-RESULT-INIT")
    assert cname_init.index("_DNT-CNAME-RESULT-STATUS") < cname_init.index(
        "0 FILL"
    )
    assert cname_init.index("_DNT-SPAN-STATUS") < cname_init.index("0 FILL")
    assert cname_init.index("MSPAN-OVERLAP?") < cname_init.index("0 FILL")

    cname_parse = _word_body(source, "DNS-TXT-CNAME-PARSE")
    assert cname_parse.index(
        "DNS-TXT-CNAME-RESULT-VALID?"
    ) < cname_parse.index("_DNTC-RESET")
    assert cname_parse.index(
        "DNS-TXT-QUERY-VALID?"
    ) < cname_parse.index("_DNTC-RESET")
    assert cname_parse.index("_DNT-PARSE-ALIASES?") < cname_parse.index(
        "_DNTC-RESET"
    )
    assert "_DNTC-PARSE-BODY" in cname_parse
    assert "_DNTC-FAIL" in cname_parse

    cname_body = _word_body(source, "_DNTC-PARSE-BODY")
    for marker in (
        "_DNT-BIND-QUESTION",
        "_DNTC-PARSE-SECTION",
        "_DNTR.CURSOR",
        "_DNTR.MESSAGE-U",
        "DNS-TXT-S-CAPACITY",
        "DNS-TXT-S-NODATA",
        "DNS-TXT-S-DUPLICATE",
        "DNS-TXT-E-CNAME",
    ):
        assert marker in cname_body
    assert cname_body.count("_DNTC-PARSE-SECTION") == 3

    cname_target = _word_body(source, "_DNTC-TARGET-DECODE")
    for marker in (
        "_DNT-NAME-DECODE",
        "_DNTR.NAME-NEXT",
        "_DNTR.RDATA-END",
        "_DNTC-TARGET-SCAN",
        "_DNTC-TARGET-COPY",
    ):
        assert marker in cname_target
    cname_copy = _word_body(source, "_DNTC-TARGET-COPY")
    assert cname_copy.count("_DNTR.BUFFER @") == 2

    compare = _word_body(source, "_DNT-NAME=QUERY?")
    assert "?DO" in compare and "LOOP" in compare
    assert not re.search(r"(?<![A-Za-z0-9_])R@?(?![A-Za-z0-9_])", compare)

    for phrase in (
        "protocol-neutral",
        "module owns no mutable state",
        "one `DNS-TXT-QUERY-SIZE` (304-byte)",
        "one `DNS-TXT-RESULT-SIZE` (512-byte)",
        "one `DNS-TXT-ITER-SIZE` (512-byte)",
        "one `DNS-TXT-RR-RESULT-SIZE` (96-byte)",
        "one `DNS-TXT-CNAME-RESULT-SIZE` (512-byte)",
        "4,096",
        "65,535",
        "compression chain",
        "exactly one direct `IN/TXT` answer",
        "CNAME traversal remains resolver work",
        "exactly one direct `IN/CNAME` RR",
        "supplies a fresh unpredictable transaction ID",
        "concatenated in wire order",
        "provisional",
        "mandatory terminal `present?` false",
        "drains every declared authority and additional RR",
        "`DNS-TXT-S-DUPLICATE`",
        "describe parser observations, not authenticity",
        "unsafe overlapping caller memory",
        "https://www.rfc-editor.org/rfc/rfc1035.html",
        "https://www.rfc-editor.org/rfc/rfc2181.html",
    ):
        assert phrase in doc_flat

    assert len(CONTRACT.name) <= 23
    assert "PROVIDED akashic-dns-txt-contracts" in fixture
    for marker in (
        "_dntt-test-name-and-query",
        "_dntt-test-result-lifecycle",
        "_dntt-test-success",
        "_dntt-test-result-corruption",
        "_dntt-test-no-data-and-unrelated",
        "_dntt-test-duplicate-and-capacity",
        "_dntt-test-header-outcomes",
        "_dntt-test-malformed-names",
        "_dntt-test-malformed-rdata",
        "_dntt-test-iterator-records",
        "_dntt-test-iterator-oversize",
        "_dntt-test-iterator-late-failure",
        "_dntt-test-iterator-header-diagnostics",
        "_dntt-test-cname",
        "DNS-TXT-ITER-BEGIN",
        "DNS-TXT-ITER-NEXT",
        "DNS-TXT-RR-PROVISIONAL?",
        "DNS-TXT-ITER-VALIDATED?",
        "DNS-TXT-ITER-E-VALIDATED",
        "DNS-TXT-ITER-RCODE@",
        "DNS-TXT-ITER-FLAGS@",
        "DNS-TXT-CNAME-PARSE",
        "DNS-TXT-CNAME-TARGET$",
        "DNS-TXT-E-CNAME",
        "_dntt-test-wipe",
        "DNS-TXT-S-ALIAS",
        "DNS-TXT-S-TRUNCATED",
        "DNS-TXT-S-RCODE",
        "DNS-TXT-S-DUPLICATE",
        PASS_MARKER,
    ):
        assert marker in fixture
    assert "_dntt-response-u @ _dntt-append-pointer" in fixture
    assert "16383 _dntt-append-pointer" in fixture
    assert "0x80000000 1 _dntt-append-owner-and-fixed" in fixture
    corruption = _word_body(fixture, "_dntt-test-result-corruption")
    for marker in (
        "DNS-TXT-S-CAPACITY",
        "DNS-TXT-S-NODATA",
        "DNS-TXT-S-DUPLICATE",
        "DNS-TXT-S-RCODE",
        "DNS-TXT-E-VALUE",
        "DNS-TXT-E-RCODE",
        "_DNTR.LENGTH",
        "_DNTR.STATUS",
        "_DNTR.RCODE",
        "_DNTR.FLAGS",
        "_DNTR.EVIDENCE",
        "_DNTR.MATCHED-COUNT",
        "_DNTR.STRING-COUNT",
        "DNS-TXT-RESULT-VALID? 0=",
    ):
        assert marker in corruption

    _assert_physical_comments(SOURCE, source)
    _assert_physical_comments(CONTRACT, fixture)


def _run_guest(timeout: float) -> int:
    sys.path.insert(0, str(LOCAL_TESTING))
    import akashic_tui as harness

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("net/dns-txt.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "DNS TXT MESSAGE FAIL",
            "DNS TXT ASSERT",
            "DNS TXT STACK",
            "DNS TXT LOAD STACK FAIL",
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
                "local_testing/dns-txt-message-test.f",
                CONTRACT.read_bytes(),
            ),
        ),
        linked=True,
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
        batch_steps=500_000,
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
            if stage_marker not in raw or stage_failures:
                print(
                    "Staged dns-txt-message-contracts: FAIL\n"
                    f"  {stage_name}: {report.steps:,} steps in "
                    f"{report.elapsed_s:.2f}s; stop={report.reason}"
                )
                for failure in stage_failures:
                    print(f"  {stage_name} failure: {failure}")
                print(f"  recent guest output:\n{raw[-4000:]}")
                return 1

        machine.clear_output()
        machine.send_text("x")
        lifecycle = machine.run(
            max_steps=PHASE_MAX_STEPS,
            wall_timeout_s=timeout,
            until_text=PASS_MARKER,
            text_scope="raw",
        )
        raw = machine.raw_text()
        lifecycle_failures = failures(machine)
        output.extend(("\n--- lifecycle ---\n", raw))
        ok = PASS_MARKER in raw and not lifecycle_failures
        root = harness.OUTPUT_ROOT / f"smoke-{PROFILE}"
        root.with_suffix(".raw.txt").write_text(
            "".join(output),
            encoding="utf-8",
        )
        print(
            f"Staged dns-txt-message-contracts: "
            f"{'PASS' if ok else 'FAIL'}"
        )
        for stage_name, report in reports:
            print(
                f"  {stage_name}: {report.steps:,} steps in "
                f"{report.elapsed_s:.2f}s; stop={report.reason}"
            )
        print(
            f"  lifecycle: {lifecycle.steps:,} steps in "
            f"{lifecycle.elapsed_s:.2f}s; stop={lifecycle.reason}"
        )
        if not ok:
            for failure in lifecycle_failures:
                print(f"  lifecycle failure: {failure}")
            print(f"  recent guest output:\n{raw[-4000:]}")
            return 1
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
        print("DNS TXT MESSAGE STATIC PASS")
        return 0
    return _run_guest(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
