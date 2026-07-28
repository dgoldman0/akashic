#!/usr/bin/env python3
"""Exact OAuth-session to credential-vault composition qualification."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
VAULT = ROOT / "akashic" / "security" / "credential-vault.f"
TOKEN_SET = ROOT / "akashic" / "security" / "oauth2" / "token-set.f"
SESSION = ROOT / "akashic" / "security" / "oauth2" / "session.f"
DEPS = LOCAL_TESTING / "cv-deps.f"
FIXTURE = LOCAL_TESTING / "oauth2-session-vault-test.f"

PHASE_MAX_STEPS = 180_000_000
PASS_MARKER = "OAUTH2 SESSION VAULT PASS"
LOAD_STAGES = (
    ("dependencies", "OAUTH2 SESSION VAULT DEPS READY"),
    ("vault", "OAUTH2 SESSION VAULT SOURCE READY"),
    ("token-set", "OAUTH2 SESSION VAULT TOKEN READY"),
    ("session", "OAUTH2 SESSION VAULT SESSION READY"),
    ("fixture", "OAUTH2 SESSION VAULT FIXTURE READY"),
)

# cv-deps predates the token/session owners and intentionally models only the
# guard surface used by the vault.  Extend that same single-threaded model in
# this runner instead of weakening or replacing either production body.
DETERMINISTIC_GUARD_EXTENSIONS = r"""
: GUARD-SPIN?  ( guard -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    24 + @ 0= ;

: GUARD-TRY-ACQUIRE  ( guard -- flag )
    DUP GUARD-SPIN? 0= IF DROP 0 EXIT THEN
    DUP @ DUP 0< IF 2DROP 0 EXIT THEN
    DROP
    1 OVER +!
    DROP -1 ;

: GUARD-ACQUIRE  ( guard -- )
    DUP GUARD-TRY-ACQUIRE 0= IF
        DROP -257 THROW
    THEN
    DROP ;

: GUARD-RELEASE  ( guard -- )
    DUP 0= IF DROP -257 THROW THEN
    DUP @ 0> 0= IF DROP -257 THROW THEN
    -1 SWAP +! ;

: WITH-GUARD  ( ... xt guard -- ... )
    DUP >R GUARD-ACQUIRE
    CATCH
    R> GUARD-RELEASE
    DUP IF THROW THEN
    DROP ;
"""


def _requires(path: Path) -> list[str]:
    return re.findall(
        r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)",
        path.read_text(encoding="utf-8"),
    )


def _assert_static_contracts() -> None:
    fixture = FIXTURE.read_text(encoding="utf-8")
    required_dependencies = (
        (
            VAULT,
            {
                "sealed-record.f",
                "../runtime/identity.f",
                "../utils/fs/vfs-fixed-snapshot.f",
                "../concurrency/guard.f",
            },
        ),
        (
            TOKEN_SET,
            {
                "../../utils/memory-span.f",
                "../../utils/caller-span.f",
                "../../concurrency/guard.f",
            },
        ),
        (
            SESSION,
            {
                "../credential-vault.f",
                "token-set.f",
                "../../runtime/identity.f",
                "../../concurrency/guard.f",
            },
        ),
    )
    for path, required in required_dependencies:
        assert required.issubset(set(_requires(path)))
    for provided in (
        "PROVIDED akashic-cred-vault",
        "PROVIDED akashic-oauth2-tokens",
        "PROVIDED akashic-oauth2-session",
    ):
        assert provided in (
            VAULT.read_text(encoding="utf-8")
            + TOKEN_SET.read_text(encoding="utf-8")
            + SESSION.read_text(encoding="utf-8")
        )
    for marker in (
        "PROVIDED oauth2-session-vault-test",
        "_O2SVT-RUN",
        PASS_MARKER,
        "CVAULT-INIT",
        "O2SESSION-INSTALL",
        "O2SESSION-OPEN",
        "O2SESSION-REFRESH-CLAIM",
        "O2SESSION-REFRESH-EXPOSE",
        "O2SESSION-REFRESH-COMMIT",
        "O2SESSION-LOGOUT",
        "O2SESSION-S-REVOKED",
        "CVAULT-FINI",
    ):
        assert marker in fixture
    for dependency in _requires(FIXTURE):
        lowered = dependency.lower()
        assert "atproto" not in lowered
        assert "streams" not in lowered

    for path in (VAULT, TOKEN_SET, SESSION, DEPS, FIXTURE):
        text = path.read_text(encoding="utf-8")
        for line_number, line in enumerate(text.splitlines(), start=1):
            forth_code = line.split("\\", 1)[0]
            if "(" in forth_code:
                assert ")" in forth_code.split("(", 1)[1], (
                    "KDOS parenthesized comments must close on their "
                    f"physical line: {path}:{line_number}"
                )


def _run_lifecycle(timeout: float) -> int:
    sys.path.insert(0, str(LOCAL_TESTING))
    import akashic_tui as harness

    def packed(path: Path, *, remove_requires: bool = False) -> bytes:
        return harness._minify_forth(
            path.read_text(encoding="utf-8"),
            remove_requires=remove_requires,
        ).encode("utf-8")

    dependency_source = (
        DEPS.read_text(encoding="utf-8")
        + "\n"
        + DETERMINISTIC_GUARD_EXTENSIONS
    )

    autoexec = (
        "\\ autoexec.f - exact OAuth session/vault composition\n"
        "ENTER-USERLAND\n"
        '." OAUTH2 SESSION VAULT LOAD START" CR TX-FLUSH\n'
        "REQUIRE local_testing/o2sv-deps.f\n"
        f'." {LOAD_STAGES[0][1]}" CR TX-FLUSH\n'
        "KEY DROP\n"
        "REQUIRE local_testing/o2sv-vault.f\n"
        f'." {LOAD_STAGES[1][1]}" CR TX-FLUSH\n'
        "KEY DROP\n"
        "REQUIRE local_testing/o2sv-token.f\n"
        f'." {LOAD_STAGES[2][1]}" CR TX-FLUSH\n'
        "KEY DROP\n"
        "REQUIRE local_testing/o2sv-session.f\n"
        f'." {LOAD_STAGES[3][1]}" CR TX-FLUSH\n'
        "KEY DROP\n"
        "REQUIRE local_testing/o2sv-test.f\n"
        "DEPTH IF\n"
        '  ." OAUTH2 SESSION VAULT LOAD STACK FAIL" CR TX-FLUSH\n'
        "THEN\n"
        f'." {LOAD_STAGES[4][1]}" CR TX-FLUSH\n'
        "KEY DROP\n"
        "_O2SVT-RUN\n"
    )

    profile_name = "oauth2-session-vault"
    image = Path("/tmp/akashic-oauth2-session-vault.img")
    harness.PROFILES[profile_name] = harness.Profile(
        roots=(),
        resources=(),
        autoexec=autoexec,
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "OAUTH2 SESSION VAULT FAIL",
            "OAUTH2 SESSION VAULT ASSERT",
            "OAUTH2 SESSION VAULT STACK",
            "OAUTH2 SESSION VAULT LOAD STACK FAIL",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            (
                "local_testing/o2sv-deps.f",
                harness._minify_forth(dependency_source).encode("utf-8"),
            ),
            (
                "local_testing/o2sv-vault.f",
                packed(VAULT, remove_requires=True),
            ),
            (
                "local_testing/o2sv-token.f",
                packed(TOKEN_SET, remove_requires=True),
            ),
            (
                "local_testing/o2sv-session.f",
                packed(SESSION, remove_requires=True),
            ),
            ("local_testing/o2sv-test.f", packed(FIXTURE)),
        ),
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

    def capture(machine: object, raw: str) -> None:
        root = harness.OUTPUT_ROOT / f"smoke-{profile_name}"
        screen = machine.snapshot()
        screen.write_text(root.with_suffix(".txt"))
        screen.write_json(root.with_suffix(".cells.json"))
        screen.write_png(
            root.with_suffix(".png"),
            font_path=(
                harness.AKASHIC_ROOT
                / "assets"
                / "fonts"
                / "DejaVuSansMono.ttf"
            ),
        )
        root.with_suffix(".raw.txt").write_text(raw, encoding="utf-8")

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
                capture(machine, "".join(output))
                print(
                    "Staged oauth2-session-vault: FAIL\n"
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
        capture(machine, "".join(output))
        print(f"Staged oauth2-session-vault: {'PASS' if ok else 'FAIL'}")
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
        print("OAUTH2 SESSION VAULT STATIC PASS")
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
