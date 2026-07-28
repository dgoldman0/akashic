#!/usr/bin/env python3
"""Qualify full DNS-hostname capacity across generic HTTPS and TLS owners."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
HTTP_TARGET = ROOT / "akashic" / "net" / "http-target.f"
HTTP_RESOURCE = ROOT / "akashic" / "net" / "http-resource.f"
KDOS_TLS = ROOT / "akashic" / "net" / "transports" / "kdos-tls.f"
MEGAPAD_NETWORKING = ROOT.parent / "megapad" / "networking.f"

PASS_MARKER = "NETWORK HOSTNAME CAPACITY PASS"
BOOT_MAX_STEPS = 180_000_000
PHASE_MAX_STEPS = 120_000_000
LOAD_STAGES = (
    ("boot", "NETWORK HOSTNAME USERLAND READY"),
    ("event", "NETWORK HOSTNAME EVENT READY"),
    ("semaphore", "NETWORK HOSTNAME SEMAPHORE READY"),
    ("guard", "NETWORK HOSTNAME GUARD READY"),
    ("string", "NETWORK HOSTNAME STRING READY"),
    ("memory-span", "NETWORK HOSTNAME MEMORY SPAN READY"),
    ("http-target", "NETWORK HOSTNAME HTTP TARGET READY"),
    ("external-io", "NETWORK HOSTNAME EXTERNAL IO READY"),
    ("io-port", "NETWORK HOSTNAME IO PORT READY"),
    ("http-request", "NETWORK HOSTNAME HTTP REQUEST READY"),
    ("http-stream", "NETWORK HOSTNAME HTTP STREAM READY"),
    ("http-buffered", "NETWORK HOSTNAME HTTP BUFFERED READY"),
    ("media-type", "NETWORK HOSTNAME MEDIA TYPE READY"),
    ("http-resource", "NETWORK HOSTNAME HTTP RESOURCE READY"),
    ("fixture", "NETWORK HOSTNAME FIXTURE READY"),
)
STAGED_REQUIRES = (
    "concurrency/event.f",
    "concurrency/semaphore.f",
    "concurrency/guard.f",
    "utils/string.f",
    "utils/memory-span.f",
    "net/http-target.f",
    "net/external-io.f",
    "net/io-port.f",
    "net/http-request.f",
    "net/http-stream.f",
    "net/http-buffered.f",
    "net/media-type.f",
    "net/http-resource.f",
    "local_testing/net-host-cap.f",
)


def _assert_static_contracts() -> None:
    target = HTTP_TARGET.read_text(encoding="utf-8")
    resource = HTTP_RESOURCE.read_text(encoding="utf-8")
    transport = KDOS_TLS.read_text(encoding="utf-8")
    megapad = MEGAPAD_NETWORKING.read_text(encoding="utf-8")

    assert re.search(
        r"(?m)^253\s+CONSTANT HTARGET-HOST-CAPACITY$", target
    )
    assert re.search(
        r"(?m)^256\s+CONSTANT HTARGET-HOST-STORAGE$", target
    )
    assert (
        "_HT-HOST HTARGET-HOST-STORAGE + CONSTANT _HT-REQUEST" in target
    )

    assert re.search(
        r"(?m)^259\s+CONSTANT HRES-HOST-VALUE-MAX$", resource
    )
    assert re.search(
        r"(?m)^264\s+CONSTANT HRES-HOST-VALUE-STORAGE$", resource
    )
    assert (
        "_HRES-HOST-VALUE HRES-HOST-VALUE-STORAGE "
        "+ CONSTANT _HRES-LOCATION"
    ) in resource
    assert (
        "HRES.HOST-VALUE HRES-HOST-VALUE-STORAGE 0 FILL"
    ) in resource
    assert "HRES.HOST-VALUE 72 0 FILL" not in resource

    assert re.search(
        r"(?m)^253 CONSTANT KDOSTLS-HOST-CAPACITY$", transport
    )
    assert re.search(
        r"(?m)^256 CONSTANT KDOSTLS-HOST-STORAGE$", transport
    )
    assert (
        "_KDOSTLS-HOST-BUF KDOSTLS-HOST-STORAGE "
        "+ CONSTANT _KDOSTLS-PHASE"
    ) in transport
    assert (
        "TLS-SNI-HOST KDOSTLS-HOST-STORAGE 0 FILL" in transport
    )
    assert "MSPAN-OVERLAP? IF" in transport
    assert (
        "_KDTCFG-A @ _KDTCFG-T @ KDOSTLS.HOST-BUF <> IF" in transport
    )

    assert re.search(r"(?m)^253 CONSTANT DNS-NAME-MAX$", megapad)
    assert (
        "DNS-NAME-MAX CONSTANT TLS-SNI-HOST-CAPACITY" in megapad
    )
    assert re.search(
        r"(?m)^256 CONSTANT TLS-SNI-HOST-STORAGE$", megapad
    )
    assert re.search(
        r"TLS-SNI-LEN @ DUP 0< SWAP\s+"
        r"TLS-SNI-HOST-CAPACITY > OR",
        megapad,
    )
    assert "TLS-SNI-LEN @ 64 >" not in megapad
    assert "TLS-SNI-HOST-STORAGE XBUF TLS-SNI-HOST" in megapad
    assert "1280 CONSTANT TLS-CH-BUF-CAPACITY" in megapad
    bound = (
        "DUP _TBCH-FIXED @ + 9 + "
        "TLS-CH-BUF-CAPACITY > IF"
    )
    assert bound in megapad
    assert megapad.index(bound) < megapad.index(
        "TLS-TR-RESET", megapad.index(bound)
    )


def _fixture_source() -> str:
    return r"""
\ Full DNS hostname admission and cross-layer copy boundaries.
PROVIDED network-hostname-capacity-test

VARIABLE _NHC-FAILS
VARIABLE _NHC-CHECKS
VARIABLE _NHC-DEPTH
VARIABLE _NHC-HOST-U

CREATE _NHC-HOST 260 ALLOT
CREATE _NHC-URI 272 ALLOT
CREATE _NHC-TARGET HTARGET-SIZE 8 + ALLOT
CREATE _NHC-TARGET-TOO-LONG HTARGET-SIZE 8 + ALLOT
CREATE _NHC-RESOURCE HTTP-RESOURCE-SIZE 8 + ALLOT

: _NHC-ASSERT  ( flag -- )
    1 _NHC-CHECKS +!
    0= IF
        1 _NHC-FAILS +!
        ." NETWORK HOSTNAME CAPACITY ASSERT " _NHC-CHECKS @ . CR
    THEN ;

: _NHC-STACK  ( -- )
    DEPTH DUP _NHC-DEPTH @ <> IF
        ." NETWORK HOSTNAME CAPACITY STACK "
        _NHC-DEPTH @ . ." -> " DUP . CR .S CR
    THEN
    _NHC-DEPTH @ = _NHC-ASSERT ;

: _NHC-ZERO?  ( address length -- flag )
    BEGIN
        DUP
    WHILE
        OVER C@ IF 2DROP 0 EXIT THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP -1 ;

: _NHC-HOST!  ( length -- )
    DUP _NHC-HOST-U !
    DROP
    _NHC-HOST 260 [CHAR] a FILL
    [CHAR] . _NHC-HOST 63 + C!
    [CHAR] . _NHC-HOST 127 + C!
    [CHAR] . _NHC-HOST 191 + C! ;

: _NHC-URI!  ( host-length -- address length )
    _NHC-HOST!
    _NHC-URI 272 0 FILL
    S" https://" _NHC-URI SWAP CMOVE
    _NHC-HOST _NHC-URI 8 + _NHC-HOST-U @ CMOVE
    [CHAR] / _NHC-URI 8 + _NHC-HOST-U @ + C!
    _NHC-URI _NHC-HOST-U @ 9 + ;

: _NHC-URI-PORT!  ( -- address length )
    253 _NHC-HOST!
    _NHC-URI 272 0 FILL
    S" https://" _NHC-URI SWAP CMOVE
    _NHC-HOST _NHC-URI 8 + 253 CMOVE
    S" :65535/" _NHC-URI 261 + SWAP CMOVE
    _NHC-URI 268 ;

: _NHC-GEOMETRY  ( -- )
    HTARGET-HOST-CAPACITY 253 = _NHC-ASSERT
    HTARGET-HOST-STORAGE 256 = _NHC-ASSERT
    _HT-REQUEST _HT-HOST - HTARGET-HOST-STORAGE = _NHC-ASSERT
    HTARGET-SIZE 3424 = _NHC-ASSERT

    HRES-HOST-VALUE-MAX 259 = _NHC-ASSERT
    HRES-HOST-VALUE-STORAGE 264 = _NHC-ASSERT
    _HRES-LOCATION _HRES-HOST-VALUE -
        HRES-HOST-VALUE-STORAGE = _NHC-ASSERT
    HTTP-RESOURCE-SIZE 45888 = _NHC-ASSERT

    _NHC-STACK ;

: _NHC-HTTP-TARGET  ( -- )
    _NHC-TARGET HTARGET-SIZE 8 + 0xA5 FILL
    253 _NHC-URI! _NHC-TARGET HTARGET-PARSE
        HTARGET-S-OK = _NHC-ASSERT
    _NHC-TARGET HTARGET-VALID? _NHC-ASSERT
    _NHC-TARGET HTARGET-HOST$ NIP 253 = _NHC-ASSERT
    _NHC-TARGET HTARGET-HOST$
        _NHC-HOST 253 STR-STR= _NHC-ASSERT
    _NHC-TARGET HTARGET-SIZE + C@ 0xA5 = _NHC-ASSERT

    _NHC-TARGET-TOO-LONG HTARGET-SIZE 8 + 0xA5 FILL
    254 _NHC-URI! _NHC-TARGET-TOO-LONG HTARGET-PARSE
        HTARGET-S-HOST = _NHC-ASSERT
    _NHC-TARGET-TOO-LONG HTARGET-VALID? 0= _NHC-ASSERT
    _NHC-TARGET-TOO-LONG HTARGET-SIZE + C@
        0xA5 = _NHC-ASSERT
    _NHC-STACK ;

: _NHC-HTTP-RESOURCE  ( -- )
    _NHC-RESOURCE HTTP-RESOURCE-SIZE 8 + 0xA5 FILL
    _NHC-RESOURCE HRES-INIT

    _NHC-URI-PORT! _NHC-TARGET HTARGET-PARSE
        HTARGET-S-OK = _NHC-ASSERT
    _NHC-TARGET HTARGET-VALID? _NHC-ASSERT
    _NHC-TARGET HTARGET-HOST$ NIP 253 = _NHC-ASSERT
    _NHC-TARGET HTARGET-PORT@ 65535 = _NHC-ASSERT

    _NHC-TARGET _NHC-RESOURCE HRES.TARGETS
        HTARGET-SIZE CMOVE
    0 _NHC-RESOURCE HRES.CURRENT !
    _NHC-RESOURCE HRES.HOST-VALUE
        HRES-HOST-VALUE-STORAGE 0xA5 FILL
    _NHC-RESOURCE _HRES-HOST-BUILD _NHC-ASSERT
    _HRHOST-U @ HRES-HOST-VALUE-MAX = _NHC-ASSERT
    _NHC-RESOURCE HRES.HOST-VALUE 253
        _NHC-HOST 253 STR-STR= _NHC-ASSERT
    _NHC-RESOURCE HRES.HOST-VALUE 253 + C@
        [CHAR] : = _NHC-ASSERT
    _NHC-RESOURCE HRES.HOST-VALUE 254 + 5
        S" 65535" STR-STR= _NHC-ASSERT
    _NHC-RESOURCE HRES.HOST-VALUE
        HRES-HOST-VALUE-MAX +
        HRES-HOST-VALUE-STORAGE HRES-HOST-VALUE-MAX -
        _NHC-ZERO? _NHC-ASSERT
    _NHC-RESOURCE HTTP-RESOURCE-SIZE + C@
        0xA5 = _NHC-ASSERT
    _NHC-STACK ;

: _NHC-RUN  ( -- )
    0 _NHC-FAILS !
    0 _NHC-CHECKS !
    DEPTH _NHC-DEPTH !
    _NHC-GEOMETRY
    _NHC-HTTP-TARGET
    _NHC-HTTP-RESOURCE
    _NHC-FAILS @ 0= IF
        ." NETWORK HOSTNAME CAPACITY PASS " _NHC-CHECKS @ . CR
    ELSE
        ." NETWORK HOSTNAME CAPACITY FAIL " _NHC-FAILS @ .
        ." / " _NHC-CHECKS @ . CR
    THEN ;
"""


def _run_lifecycle(timeout: float) -> int:
    sys.path.insert(0, str(LOCAL_TESTING))
    import akashic_tui as harness

    fixture = harness._minify_forth(_fixture_source()).encode("utf-8")
    autoexec_parts = [
        "\\ autoexec.f - generic network hostname capacity\n",
        "ENTER-USERLAND\n",
        f'." {LOAD_STAGES[0][1]}" CR TX-FLUSH\n',
        "KEY DROP\n",
    ]
    for index, required_path in enumerate(STAGED_REQUIRES, start=1):
        autoexec_parts.append(f"REQUIRE {required_path}\n")
        if required_path == "local_testing/net-host-cap.f":
            autoexec_parts.extend(
                (
                    "DEPTH IF\n",
                    '  ." NETWORK HOSTNAME CAPACITY LOAD STACK FAIL" '
                    "CR TX-FLUSH\n",
                    "THEN\n",
                )
            )
        autoexec_parts.extend(
            (
                f'." {LOAD_STAGES[index][1]}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec_parts.append("_NHC-RUN\n")
    autoexec = "".join(autoexec_parts)

    profile_name = "network-hostname-capacity"
    image = Path("/tmp/akashic-network-hostname-capacity.img")
    harness.PROFILES[profile_name] = harness.Profile(
        roots=("net/http-resource.f",),
        resources=(),
        autoexec=autoexec,
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "NETWORK HOSTNAME CAPACITY FAIL",
            "NETWORK HOSTNAME CAPACITY ASSERT",
            "NETWORK HOSTNAME CAPACITY STACK",
            "NETWORK HOSTNAME CAPACITY LOAD STACK FAIL",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(("local_testing/net-host-cap.f", fixture),),
        linked=False,
        include_large_sample=False,
        total_sectors=2048,
    )
    image_path = harness.build_image(profile_name, image)
    profile = harness.PROFILES[profile_name]

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
        rows=44,
        batch_steps=500_000,
        ext_mem_size=128 << 20,
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
                max_steps=(
                    BOOT_MAX_STEPS
                    if stage_name == "boot"
                    else PHASE_MAX_STEPS
                ),
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
                    "Staged network-hostname-capacity: FAIL\n"
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
        root = harness.OUTPUT_ROOT / f"smoke-{profile_name}"
        root.with_suffix(".raw.txt").write_text(
            "".join(output),
            encoding="utf-8",
        )
        print(f"Staged network-hostname-capacity: {'PASS' if ok else 'FAIL'}")
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
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument("--lifecycle", action="store_true")
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("NETWORK HOSTNAME CAPACITY STATIC PASS")
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
