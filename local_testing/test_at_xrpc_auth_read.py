#!/usr/bin/env python3
"""Qualify one durable authenticated AT XRPC GET and buffered read."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
SOURCE_ROOT = ROOT / "akashic"
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402
from forth_dependencies import dependency_order  # noqa: E402
from test_oauth2_p256_key import P256_JWK_DOUBLES  # noqa: E402


PROFILE = "at-xrpc-auth-read"
IMAGE = Path("/tmp/akashic-at-xrpc-auth-read.img")
PASS_MARKER = "AT XRPC AUTH READ PASS"
XRPC_LOAD_MARKER = "AT XRPC PRODUCTION READY"

XRPC = SOURCE_ROOT / "atproto" / "xrpc.f"
HTTP_REQUEST = SOURCE_ROOT / "net" / "http-request.f"
HTTP_BUFFERED = SOURCE_ROOT / "net" / "http-buffered.f"
VFS = SOURCE_ROOT / "utils" / "fs" / "vfs.f"
VAULT = SOURCE_ROOT / "security" / "credential-vault.f"
KEY_OWNER = SOURCE_ROOT / "security" / "oauth2" / "key-p256.f"
SESSION = SOURCE_ROOT / "security" / "oauth2" / "session.f"

PROFILE_FIXTURE = LOCAL_TESTING / "at-oauth-prof-test.f"
CLIENT_FIXTURE = LOCAL_TESTING / "at-oauth-client-test.f"
CONTRACT = LOCAL_TESTING / "at-xrpc-auth-read-test.f"

MAX_PHASE_STEPS = 180_000_000
EXT_MEM_SIZE = 128 << 20
NUM_CORES = 1

# The exact key owner is retained while only its expensive mathematical
# construction dependencies are replaced by the established deterministic
# P-256/JWK/DPoP seam.  ECDSA and JWS are closure-only dependencies of the
# replaced DPoP constructor and therefore are not compiled into this image.
REPLACED_CRYPTO_MODULES = frozenset(
    {
        "math/p256.f",
        "security/jose/jwk-p256.f",
        "math/ecdsa-p256.f",
        "security/jose/jws-es256.f",
        "security/oauth2/dpop-es256.f",
    }
)

RAW_MODULES = dependency_order(
    SOURCE_ROOT,
    (
        "atproto/xrpc.f",
        "net/http-buffered.f",
        "utils/fs/vfs.f",
    ),
)


@dataclass(frozen=True)
class LoadItem:
    name: str
    guest: str
    marker: str
    source: Path | None = None
    inline: str | None = None
    remove_requires: bool = True


def _module_load_items() -> tuple[LoadItem, ...]:
    items: list[LoadItem] = []
    sequence = 0
    seam_inserted = False
    for module in RAW_MODULES:
        if module in REPLACED_CRYPTO_MODULES:
            continue
        if module == "security/oauth2/key-p256.f":
            sequence += 1
            items.append(
                LoadItem(
                    name="deterministic-crypto-seam",
                    guest="local_testing/ar-seam.f",
                    marker="AT XRPC CRYPTO SEAM READY",
                    inline=P256_JWK_DOUBLES,
                    remove_requires=False,
                )
            )
            seam_inserted = True
        sequence += 1
        if module == "atproto/xrpc.f":
            name = "production-xrpc"
            marker = XRPC_LOAD_MARKER
        else:
            name = f"module-{sequence:02d}"
            marker = f"AT XRPC MODULE {sequence:02d} READY"
        items.append(
            LoadItem(
                name=name,
                guest=f"local_testing/ar-m{sequence:02d}.f",
                marker=marker,
                source=SOURCE_ROOT / module,
            )
        )
    assert seam_inserted
    return tuple(items)


MODULE_LOAD_ITEMS = _module_load_items()

FIXTURE_LOAD_ITEMS = (
    LoadItem(
        name="profile-fixture",
        guest="local_testing/ar-prof.f",
        marker="AT XRPC PROFILE FIXTURE READY",
        source=PROFILE_FIXTURE,
        remove_requires=False,
    ),
    LoadItem(
        name="client-fixture",
        guest="local_testing/ar-client.f",
        marker="AT XRPC CLIENT FIXTURE READY",
        source=CLIENT_FIXTURE,
        remove_requires=False,
    ),
    LoadItem(
        name="auth-read-fixture",
        guest="local_testing/ar-fixture.f",
        marker="AT XRPC AUTH FIXTURE READY",
        source=CONTRACT,
    ),
)

RUNTIME_STAGES = (
    (
        "setup",
        "_ATXR-SETUP",
        "AT XRPC SETUP READY",
        MAX_PHASE_STEPS,
    ),
    (
        "provision",
        "_ATXR-PROVISION",
        "AT XRPC KEY READY",
        MAX_PHASE_STEPS,
    ),
    (
        "install",
        "_ATXR-INSTALL",
        "AT XRPC SESSION INSTALLED",
        MAX_PHASE_STEPS,
    ),
    (
        "owner-restart",
        "_ATXR-RESTART",
        "AT XRPC OWNERS REOPENED",
        MAX_PHASE_STEPS,
    ),
    (
        "request-build",
        "_ATXR-BUILD",
        "AT XRPC REQUEST READY",
        MAX_PHASE_STEPS,
    ),
    (
        "buffered-read",
        "_ATXR-READ",
        "AT XRPC RESPONSE READY",
        MAX_PHASE_STEPS,
    ),
    (
        "finish",
        "_ATXR-FINISH",
        PASS_MARKER,
        MAX_PHASE_STEPS,
    ),
)

FAILURE_MARKERS = (
    "AT XRPC AUTH READ FAIL",
    "AT XRPC AUTH READ ASSERT",
    "AT XRPC AUTH READ STATUS",
    "AT XRPC AUTH READ STACK",
    "AT XRPC LOAD STACK FAIL",
    "AT OAUTH PROFILE ASSERT",
    "AT OAUTH PROFILE STATUS",
    "AT OAUTH PROFILE STACK",
    "AT OAUTH CLIENT ASSERT",
    "AT OAUTH CLIENT STATUS",
    "AT OAUTH CLIENT STACK",
    "DRIVER THROW",
    "Branch offset overflow",
    "dictionary full",
    "exception",
    "Module not found",
    "Path component not found",
    "? (not found)",
)


def _requires(path: Path) -> list[str]:
    return re.findall(
        r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)",
        path.read_text(encoding="utf-8"),
    )


def _provided_ids(source: str) -> list[str]:
    return re.findall(
        r"(?mi)^[ \t]*PROVIDED[ \t]+(\S+)",
        source,
    )


def _forth_code(source: str) -> str:
    return "\n".join(
        line.split("\\", 1)[0] for line in source.splitlines()
    )


def _word_count(source: str, name: str) -> int:
    return len(
        re.findall(
            rf"(?<![A-Za-z0-9_-]){re.escape(name)}"
            rf"(?![A-Za-z0-9_-])",
            _forth_code(source),
        )
    )


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing Forth word {name}"
    return match.group("body")


def _assert_physical_comments(path: Path, source: str) -> None:
    for line_number, line in enumerate(source.splitlines(), start=1):
        code = line.split("\\", 1)[0]
        code = code.replace("[CHAR] (", "")
        if "(" in code:
            assert ")" in code.split("(", 1)[1], (
                "KDOS parenthesized comments must close on their physical "
                f"line: {path}:{line_number}"
            )


def _assert_static_contracts() -> None:
    fixture = CONTRACT.read_text(encoding="utf-8")
    xrpc = XRPC.read_text(encoding="utf-8")
    request = HTTP_REQUEST.read_text(encoding="utf-8")
    buffered = HTTP_BUFFERED.read_text(encoding="utf-8")
    vfs = VFS.read_text(encoding="utf-8")
    vault = VAULT.read_text(encoding="utf-8")
    key_owner = KEY_OWNER.read_text(encoding="utf-8")
    session = SESSION.read_text(encoding="utf-8")

    assert RAW_MODULES[-2:] == (
        "net/http-stream.f",
        "net/http-buffered.f",
    )
    assert "atproto/xrpc.f" in RAW_MODULES
    assert "utils/fs/vfs.f" in RAW_MODULES
    assert REPLACED_CRYPTO_MODULES < set(RAW_MODULES)
    assert all(
        module not in {
            item.source.relative_to(SOURCE_ROOT).as_posix()
            for item in MODULE_LOAD_ITEMS
            if item.source is not None
        }
        for module in REPLACED_CRYPTO_MODULES
    )

    module_names = [item.name for item in MODULE_LOAD_ITEMS]
    seam_index = module_names.index("deterministic-crypto-seam")
    key_index = next(
        index
        for index, item in enumerate(MODULE_LOAD_ITEMS)
        if item.source == KEY_OWNER
    )
    xrpc_index = module_names.index("production-xrpc")
    assert seam_index < key_index < xrpc_index
    assert MODULE_LOAD_ITEMS[xrpc_index].marker == XRPC_LOAD_MARKER
    assert xrpc_index < len(MODULE_LOAD_ITEMS)

    all_load_items = (*MODULE_LOAD_ITEMS, *FIXTURE_LOAD_ITEMS)
    all_stages = (
        *(
            (item.name, item.guest, item.marker, MAX_PHASE_STEPS)
            for item in all_load_items
        ),
        *RUNTIME_STAGES,
    )
    assert all(
        0 < stage_steps <= MAX_PHASE_STEPS
        for _, _, _, stage_steps in all_stages
    )
    assert len({name for name, _, _, _ in all_stages}) == len(all_stages)
    assert len({marker for _, _, marker, _ in all_stages}) == len(
        all_stages
    )
    assert NUM_CORES == 1
    assert EXT_MEM_SIZE == 128 << 20
    for item in all_load_items:
        assert len(Path(item.guest).name.encode("utf-8")) <= 23
        assert (item.source is None) != (item.inline is None)

    assert _requires(CONTRACT) == ["at-oauth-client-test.f"]
    for marker in (
        "PROVIDED at-xrpc-auth-read",
        "_ATXR-SETUP",
        "_ATXR-PROVISION",
        "_ATXR-INSTALL",
        "_ATXR-RESTART",
        "_ATXR-BUILD",
        "_ATXR-READ",
        "_ATXR-FINISH",
        "O2SESSION-RECORD-SIZE CVAULT-BACKING-SIZE",
        "VFS-RAM-OPS",
        "VFS-RAM-BINDING",
        "VFS-NEW",
        'S" vault"',
        "CVAULT-INIT",
        "OAUTH2-P256-KEY-PROVISION-DPOP",
        "OAUTH2-P256-KEY-SLOT-LOAD-DPOP",
        "OAUTH2-P256-KEY-BINDING-INIT",
        "O2SESSION-INSTALL",
        "O2SESSION-OPEN",
        "AT-XRPC-AUTH-GET-BUILD",
        "com.atproto.server.getSession",
        "Authorization: DPoP access-vertical",
        "DPoP: deterministic-dpop-proof",
        "HBUF-START",
        "HBUF-POLL",
        PASS_MARKER,
    ):
        assert marker in fixture
    assert "cv-deps.f" not in fixture
    assert "_CVTD-" not in fixture
    assert "0x61 FILL" in fixture
    assert "0x62 FILL" in fixture
    assert "_atxr-key-rid _atxr-session-rid RID= 0=" in fixture
    assert _word_count(fixture, "OAUTH2-P256-KEY-PROVISION-DPOP") == 1
    assert _word_count(fixture, "OAUTH2-P256-KEY-SLOT-LOAD-DPOP") == 1
    assert _word_count(fixture, "O2SESSION-INSTALL") == 1
    assert _word_count(fixture, "O2SESSION-OPEN") == 1
    assert _word_count(fixture, "AT-XRPC-AUTH-GET-BUILD") == 1
    assert _word_count(fixture, "HBUF-START") == 1
    assert not re.search(
        r"(?i)(?<![A-Za-z0-9_-])(?:\?DO|DO|\+LOOP|LOOP)"
        r"(?![A-Za-z0-9_-])",
        _forth_code(fixture),
    ), "focused fixture must not borrow the DO-loop return stack"

    restart = _word_body(fixture, "_ATXR-RESTART")
    for earlier, later in (
        ("O2SESSION-FINI", "CVAULT-FINI"),
        ("CVAULT-FINI", "_atxr-select-owner-b"),
        ("_atxr-configure-active-vault", "OAUTH2-P256-KEY-SLOT-LOAD-DPOP"),
        ("OAUTH2-P256-KEY-SLOT-LOAD-DPOP", "O2SESSION-OPEN"),
    ):
        assert restart.index(earlier) < restart.index(later)
    build = _word_body(fixture, "_ATXR-BUILD")
    assert build.index("_O2PKD-RESET") < build.index(
        "AT-XRPC-AUTH-GET-BUILD"
    )
    assert build.index("AT-XRPC-AUTH-GET-BUILD") < build.index(
        "Authorization: DPoP access-vertical"
    )
    read = _word_body(fixture, "_ATXR-READ")
    assert read.index("HBUF-START") < read.index("_atxr-poll-response")
    assert read.index("_atxr-poll-response") < read.index("HBUF.HTTP-CODE")

    assert "PROVIDED akashic-xrpc" in xrpc
    assert _requires(XRPC) == [
        "../utils/memory-span.f",
        "../utils/caller-span.f",
        "../utils/string.f",
        "../net/http-target.f",
        "../net/http-request.f",
        "../security/credential-vault.f",
        "../security/oauth2/client-config.f",
        "../security/oauth2/session.f",
        "../security/oauth2/key-p256.f",
        "oauth-profile.f",
        "oauth-client.f",
        "nsid.f",
    ]
    for marker in (
        "AT-XRPC-AUTH-GET-INPUT-SIZE",
        "AT-XRPC-AUTH-GET-WORKSPACE-SIZE",
        "AT-XRPC-AUTH-GET-BUILD",
        "HTARGET-HTU$",
        "OAUTH2-P256-KEY-DPOP-PROOF",
        "O2SESSION-WITH-ACCESS",
        "HREQ-AUTHORIZATION",
    ):
        assert marker in xrpc
    assert "HTARGET-HOST-CAPACITY 6 +" in xrpc
    finish = _word_body(xrpc, "_ATX-FINISH")
    assert finish.index("HREQ-CLEAR") < finish.index(
        "HTTP-REQUEST-SIZE 0 FILL"
    )
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        xrpc,
    ), "authenticated XRPC builder must own no mutable module-global state"
    assert "HREQ-AUTHORIZATION" in request
    assert "PROVIDED akashic-http-buffered" in buffered
    assert "PROVIDED akashic-vfs" in vfs
    assert "VFS-RAM-OPS" in vfs
    assert "PROVIDED akashic-cred-vault" in vault
    assert "PROVIDED akashic-oauth2-key-p256" in key_owner
    assert "PROVIDED akashic-oauth2-session" in session

    seam_ids = set(_provided_ids(P256_JWK_DOUBLES))
    assert {
        "akashic-p256",
        "akashic-jose-jwk-p256",
        "akashic-oauth2-dpop256",
    } <= seam_ids
    for marker in (
        "_O2PKD-RESET",
        "_O2PKD-DPOP-CALLS",
        "_O2PKD-DPOP-HTM-A",
        "_O2PKD-DPOP-HTU-A",
        "_O2PKD-DPOP-TOKEN-U",
        "deterministic-dpop-proof",
    ):
        assert marker in P256_JWK_DOUBLES

    runtime_names = [name for name, _, _, _ in RUNTIME_STAGES]
    assert runtime_names == [
        "setup",
        "provision",
        "install",
        "owner-restart",
        "request-build",
        "buffered-read",
        "finish",
    ]

    for path in (
        *(item.source for item in MODULE_LOAD_ITEMS if item.source),
        PROFILE_FIXTURE,
        CLIENT_FIXTURE,
        CONTRACT,
    ):
        source = path.read_text(encoding="utf-8")
        _assert_physical_comments(path, source)


def _packed(path: Path, *, remove_requires: bool = False) -> bytes:
    return harness._minify_forth(  # noqa: SLF001
        path.read_text(encoding="utf-8"),
        remove_requires=remove_requires,
    ).encode("utf-8")


def _load_bytes(item: LoadItem) -> bytes:
    if item.inline is not None:
        return harness._minify_forth(  # noqa: SLF001
            item.inline,
            remove_requires=item.remove_requires,
        ).encode("utf-8")
    assert item.source is not None
    return _packed(item.source, remove_requires=item.remove_requires)


def _autoexec() -> str:
    lines = [
        "\\ autoexec.f - durable authenticated AT XRPC read\n",
        "ENTER-USERLAND\n",
    ]
    for item in (*MODULE_LOAD_ITEMS, *FIXTURE_LOAD_ITEMS):
        lines.extend(
            (
                f"REQUIRE {item.guest}\n",
                (
                    'DEPTH IF ." AT XRPC LOAD STACK FAIL '
                    f'{item.name}" CR TX-FLUSH THEN\n'
                ),
                f'." {item.marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    for _, word, marker, _ in RUNTIME_STAGES:
        if marker == PASS_MARKER:
            lines.extend((f"{word}\n", "TX-FLUSH\n"))
        else:
            lines.extend(
                (
                    f"{word}\n",
                    f'." {marker}" CR TX-FLUSH\n',
                    "KEY DROP\n",
                )
            )
    return "".join(lines)


def _initial_files() -> tuple[tuple[str, bytes], ...]:
    return tuple(
        (item.guest, _load_bytes(item))
        for item in (*MODULE_LOAD_ITEMS, *FIXTURE_LOAD_ITEMS)
    )


def _run_vertical(timeout: float) -> int:
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=(),
        resources=(),
        autoexec=_autoexec(),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=FAILURE_MARKERS,
        initial_files=_initial_files(),
        linked=False,
        include_large_sample=False,
        total_sectors=8192,
    )
    image_path = harness.build_image(PROFILE, IMAGE)
    profile = harness.PROFILES[PROFILE]
    reports: list[tuple[str, object]] = []
    stages = (
        *(
            (item.name, item.guest, item.marker, MAX_PHASE_STEPS)
            for item in (*MODULE_LOAD_ITEMS, *FIXTURE_LOAD_ITEMS)
        ),
        *RUNTIME_STAGES,
    )

    with harness.MachineSession.from_bios(
        harness.MEGAPAD_ROOT / "bios.asm",
        storage_image=image_path,
        cols=120,
        rows=44,
        batch_steps=500_000,
        ext_mem_size=EXT_MEM_SIZE,
        num_cores=NUM_CORES,
    ) as machine:
        machine.boot()
        for index, (stage_name, _, marker, stage_steps) in enumerate(stages):
            if index:
                machine.clear_output()
                machine.send_text("x")
            report = machine.run(
                max_steps=stage_steps,
                wall_timeout_s=timeout,
                until_text=marker,
                text_scope="raw",
            )
            raw_text = machine.raw_text()
            failures = tuple(
                dict.fromkeys(
                    (
                        *harness._has_forth_error(raw_text),  # noqa: SLF001
                        *harness._matched_failure_markers(  # noqa: SLF001
                            profile,
                            raw_text,
                            machine.screen_text(),
                        ),
                    )
                )
            )
            reports.append((stage_name, report))
            if marker not in raw_text or failures:
                print(f"AT XRPC AUTH READ {stage_name}: FAIL")
                print(
                    f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
                    f"stop={report.reason}"
                )
                for failure in failures:
                    print(f"  {failure}")
                print(raw_text[-4000:])
                return 1
            print(
                f"AT XRPC AUTH READ {stage_name}: PASS "
                f"({report.steps:,} steps, {report.elapsed_s:.2f}s)",
                flush=True,
            )

    print("AT XRPC AUTH READ vertical: PASS")
    for stage_name, report in reports:
        print(
            f"  {stage_name}: {report.steps:,} steps in "
            f"{report.elapsed_s:.2f}s; stop={report.reason}"
        )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--static-only",
        action="store_true",
        help="check source, seam, packaging, and serial stage contracts",
    )
    mode.add_argument(
        "--vertical",
        action="store_true",
        help="run durable key/session restart through authenticated read",
    )
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("AT XRPC AUTH READ STATIC PASS")
        return 0
    return _run_vertical(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
