#!/usr/bin/env python3
"""Run the existing offline KDOS TLS port contract in bounded stages."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent

PROFILE_NAME = "tls-port-staged"
IMAGE = Path("/tmp/akashic-tls-port-staged.img")
PHASE_MAX_STEPS = 180_000_000
NETWORKING_CHUNK_BYTES = 48 * 1024

LOAD_STAGES = (
    ("networking", "TLS PORT NETWORKING READY"),
    ("transport", "TLS PORT TRANSPORT READY"),
    ("fixture", "TLS PORT FIXTURE READY"),
)
RUN_BREAKS = (
    ("_ko-test-config", "configuration", "TLS PORT CONFIG READY"),
    ("_ko-test-start-terminals", "terminals", "TLS PORT TERMINALS READY"),
    ("_ko-test-open-shared", "shared-open", "TLS PORT SHARED OPEN READY"),
    (
        "_ko-test-publication-throws",
        "publication",
        "TLS PORT PUBLICATION READY",
    ),
    ("_ko-test-default-prefix", "default-prefix", "TLS PORT PREFIX READY"),
)


def _stage_line(marker: str, *, indent: str = "") -> str:
    return f'{indent}." {marker}" CR TX-FLUSH KEY DROP\n'


def _staged_autoexec(harness: object) -> str:
    base = harness.PROFILES["tls-port"].autoexec
    userland_entry = "ENTER-USERLAND\n"
    assert base.count(userland_entry) == 1
    base = base.replace(
        userland_entry,
        "".join(
            (
                userland_entry,
                (
                    'DEPTH IF ." TLS PORT LOAD STACK FAIL networking" '
                    "CR TX-FLUSH THEN\n"
                ),
                _stage_line(LOAD_STAGES[0][1]),
            )
        ),
        1,
    )

    transport_load = "REQUIRE net/transports/kdos-tls.f\n"
    assert base.count(transport_load) == 1
    base = base.replace(
        transport_load,
        "".join(
            (
                transport_load,
                (
                    'DEPTH IF ." TLS PORT LOAD STACK FAIL transport" '
                    "CR TX-FLUSH THEN\n"
                ),
                _stage_line(LOAD_STAGES[1][1]),
            )
        ),
        1,
    )

    invocation = "\n_ko-run\n"
    assert base.count(invocation) == 1

    for word, _, marker in RUN_BREAKS:
        call = f"    {word}\n"
        assert base.count(call) == 1, f"ambiguous TLS fixture call: {word}"
        base = base.replace(
            call,
            call + _stage_line(marker, indent="    "),
            1,
        )

    return base.replace(
        invocation,
        "".join(
            (
                (
                    '\nDEPTH IF ." TLS PORT LOAD STACK FAIL fixture" '
                    "CR TX-FLUSH THEN\n"
                ),
                _stage_line(LOAD_STAGES[2][1]),
                invocation,
                "TX-FLUSH\n",
            )
        ),
        1,
    )


def _load_harness() -> object:
    local_testing = str(LOCAL_TESTING)
    if local_testing not in sys.path:
        sys.path.insert(0, local_testing)
    import akashic_tui as harness

    return harness


def test_staged_autoexec_tracks_outbound_profile() -> None:
    """The staged runner must preserve the current outbound fixture."""
    harness = _load_harness()
    base = harness.PROFILES["tls-port"]
    staged = _staged_autoexec(harness)
    deployed = harness._with_megapad_networking(staged)

    networking_load = deployed.index("REQUIRE networking.f")
    networking_ready = deployed.index(LOAD_STAGES[0][1])
    handshake_interpose = deployed.index(
        "' TLS-HANDSHAKE-PUBLISH CONSTANT _ko-real-handshake-publish"
    )
    transport_load = deployed.index("REQUIRE net/transports/kdos-tls.f")
    assert networking_load < networking_ready
    assert networking_ready < handshake_interpose < transport_load
    for _, marker in LOAD_STAGES:
        assert deployed.count(marker) == 1
    for word, _, marker in RUN_BREAKS:
        assert deployed.count(f"    {word}\n") == 1
        assert deployed.count(marker) == 1
    for marker in (*base.ready_markers, *base.failure_markers):
        assert marker in deployed


def _networking_chunks(harness: object, source: str) -> tuple[bytes, ...]:
    compacted = harness._minify_forth(source).encode("utf-8")
    units: list[bytearray] = []
    unit = bytearray()
    definition_depth = 0
    conditional_depth = 0
    for line in compacted.splitlines(keepends=True):
        unit.extend(line)
        text = line.decode("utf-8").rstrip("\r\n")
        tokens = harness._forth_line_tokens(text)
        if tokens and (
            tokens[0] == ":" or tokens[0].upper() == ":NONAME"
        ):
            definition_depth = 1
        if definition_depth and any(
            token == ";"
            and (
                index == 0
                or tokens[index - 1].upper() not in {"CHAR", "[CHAR]"}
            )
            for index, token in enumerate(tokens)
        ):
            definition_depth = 0
        for token in text.split(" "):
            upper = token.upper()
            if upper == "[IF]":
                conditional_depth += 1
            elif upper == "[THEN]" and conditional_depth:
                conditional_depth -= 1
        if definition_depth == 0 and conditional_depth == 0:
            units.append(unit)
            unit = bytearray()
    if unit:
        raise RuntimeError("networking source ends inside a Forth source unit")

    chunks: list[bytearray] = []
    current = bytearray()
    for source_unit in units:
        if len(source_unit) > NETWORKING_CHUNK_BYTES:
            raise RuntimeError(
                "networking source unit exceeds staged chunk ceiling"
            )
        if (
            current
            and len(current) + len(source_unit) > NETWORKING_CHUNK_BYTES
        ):
            chunks.append(current)
            current = bytearray()
        current.extend(source_unit)
    if current:
        chunks.append(current)
    return tuple(bytes(chunk) for chunk in chunks)


def _install_compacted_networking(
    harness: object,
    image: Path,
) -> tuple[int, int, tuple[tuple[str, str], ...]]:
    source = (harness.MEGAPAD_ROOT / "networking.f").read_text(
        encoding="utf-8"
    )
    chunks = _networking_chunks(harness, source)
    compacted_bytes = sum(map(len, chunks))
    filesystem = harness.MP64FS(bytearray(image.read_bytes()))
    filesystem.delete_file("networking.f")
    filesystem.mkdir(".knet")
    loader = []
    stages = []
    for index, chunk in enumerate(chunks):
        name = f"n{index:02d}.f"
        path = f".knet/{name}"
        loader.append(f"REQUIRE {path}\n")
        if index + 1 < len(chunks):
            stage_name = f"networking-{index + 1:02d}"
            marker = f"TLS PORT NETWORKING CHUNK {index + 1:02d} READY"
            chunk += _stage_line(marker).encode("utf-8")
            stages.append((stage_name, marker))
        filesystem.inject_file(
            name,
            harness.pack_forth_source(chunk),
            ftype=harness.FTYPE_FORTH,
            path="/.knet",
        )
    filesystem.inject_file(
        "networking.f",
        harness.pack_forth_source("".join(loader).encode("utf-8")),
        ftype=harness.FTYPE_FORTH,
    )
    filesystem.save(image)
    return len(source.encode("utf-8")), compacted_bytes, tuple(stages)


def _failures(harness: object, profile: object, machine: object) -> tuple[str, ...]:
    raw = machine.raw_text()
    return tuple(
        dict.fromkeys(
            (
                *harness._has_forth_error(raw),
                *harness._matched_failure_markers(
                    profile,
                    raw,
                    machine.screen_text(),
                ),
            )
        )
    )


def _run_stage(
    harness: object,
    profile: object,
    machine: object,
    stage_name: str,
    marker: str,
    timeout: float,
) -> tuple[bool, object, str, tuple[str, ...]]:
    report = machine.run(
        max_steps=PHASE_MAX_STEPS,
        wall_timeout_s=timeout,
        until_text=marker,
        text_scope="raw",
    )
    raw = machine.raw_text()
    failures = _failures(harness, profile, machine)
    return marker in raw and not failures, report, raw, failures


def _run_lifecycle(timeout: float) -> int:
    harness = _load_harness()

    base = harness.PROFILES["tls-port"]
    assert len(base.ready_markers) == 1
    pass_marker = base.ready_markers[0]
    harness.PROFILES[PROFILE_NAME] = harness.Profile(
        roots=base.roots,
        resources=base.resources,
        autoexec=_staged_autoexec(harness),
        ready_markers=base.ready_markers,
        stable_markers=base.stable_markers,
        failure_markers=(
            *base.failure_markers,
            "TLS PORT LOAD STACK FAIL",
            "ASSERT ",
            "STACK ",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        linked=base.linked,
        include_large_sample=False,
        total_sectors=base.total_sectors,
    )
    image = harness.build_image(PROFILE_NAME, IMAGE)
    original_bytes, compacted_bytes, networking_stages = (
        _install_compacted_networking(
            harness,
            image,
        )
    )
    profile = harness.PROFILES[PROFILE_NAME]
    stages = (
        *networking_stages,
        *LOAD_STAGES,
        *((name, marker) for _, name, marker in RUN_BREAKS),
    )

    with harness.MachineSession.from_bios(
        harness.MEGAPAD_ROOT / "bios.asm",
        storage_image=image,
        cols=100,
        rows=32,
        batch_steps=500_000,
        ext_mem_size=128 << 20,
        num_cores=1,
    ) as machine:
        machine.boot()
        reports = []
        for index, (stage_name, marker) in enumerate(stages):
            if index:
                machine.clear_output()
                machine.send_text("x")
            ok, report, raw, failures = _run_stage(
                harness,
                profile,
                machine,
                stage_name,
                marker,
                timeout,
            )
            reports.append((stage_name, report))
            if not ok:
                print(f"Staged TLS port: FAIL ({stage_name})")
                print(
                    f"  {report.steps:,} steps in "
                    f"{report.elapsed_s:.2f}s; stop={report.reason}"
                )
                for failure in failures:
                    print(f"  {failure}")
                print(f"  recent guest output:\n{raw[-4000:]}")
                return 1

        machine.clear_output()
        machine.send_text("x")
        ok, report, raw, failures = _run_stage(
            harness,
            profile,
            machine,
            "finish",
            pass_marker,
            timeout,
        )
        reports.append(("finish", report))
        print(f"Staged TLS port: {'PASS' if ok else 'FAIL'}")
        print(
            "  compacted test-image networking: "
            f"{original_bytes:,} -> {compacted_bytes:,} bytes in "
            f"{len(networking_stages) + 1} chunks"
        )
        for stage_name, stage_report in reports:
            print(
                f"  {stage_name}: {stage_report.steps:,} steps in "
                f"{stage_report.elapsed_s:.2f}s; stop={stage_report.reason}"
            )
        if not ok:
            for failure in failures:
                print(f"  finish failure: {failure}")
            print(f"  recent guest output:\n{raw[-4000:]}")
            return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
