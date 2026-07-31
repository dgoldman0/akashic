#!/usr/bin/env python3
"""Qualify the authenticated createRecord owner and its durable receipt."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
SOURCE_ROOT = ROOT / "akashic"
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402
import test_at_xrpc_auth_read as auth_read  # noqa: E402
import test_at_xrpc_exchange as xrpc_exchange  # noqa: E402
from forth_dependencies import dependency_order  # noqa: E402
from test_oauth2_p256_key import P256_JWK_DOUBLES  # noqa: E402


PROFILE = "at-create-record"
IMAGE = Path("/tmp/akashic-at-create-record.img")
PASS_MARKER = "CREATE RECORD E2E PASS"
MAX_PHASE_STEPS = 180_000_000
EXT_MEM_SIZE = 128 << 20
NUM_CORES = 1
LINKED = False

OWNER = SOURCE_ROOT / "atproto" / "create-record.f"
CODEC = SOURCE_ROOT / "atproto" / "create-record-codec.f"
DOC = ROOT / "docs" / "atproto" / "create-record.md"
CONTRACT = LOCAL_TESTING / "crec-e2e-test.f"

REPLACED_CRYPTO_MODULES = auth_read.REPLACED_CRYPTO_MODULES
REPLACED_TRANSPORT_MODULES = frozenset({"net/transports/kdos-tls.f"})
TRANSPORT_DOUBLE = xrpc_exchange.TRANSPORT_DOUBLE

RAW_MODULES = dependency_order(
    SOURCE_ROOT,
    (
        "atproto/create-record.f",
        "utils/fs/vfs.f",
    ),
)


def _module_items() -> tuple[auth_read.LoadItem, ...]:
    items: list[auth_read.LoadItem] = []
    sequence = 0
    crypto_seam_inserted = False
    transport_seam_inserted = False
    for module in RAW_MODULES:
        if module in REPLACED_CRYPTO_MODULES:
            continue
        if module in REPLACED_TRANSPORT_MODULES:
            sequence += 1
            items.append(
                auth_read.LoadItem(
                    name="deterministic-transport-seam",
                    guest="local_testing/cr-net.f",
                    marker="CREATE RECORD TRANSPORT SEAM READY",
                    inline=TRANSPORT_DOUBLE,
                    remove_requires=False,
                )
            )
            transport_seam_inserted = True
            continue
        if module == "security/oauth2/key-p256.f":
            sequence += 1
            items.append(
                auth_read.LoadItem(
                    name="deterministic-crypto-seam",
                    guest="local_testing/cr-seam.f",
                    marker="CREATE RECORD CRYPTO SEAM READY",
                    inline=P256_JWK_DOUBLES,
                    remove_requires=False,
                )
            )
            crypto_seam_inserted = True
        sequence += 1
        if module == "atproto/create-record.f":
            name = "production-create-record"
            marker = "CREATE RECORD PRODUCTION READY"
        else:
            name = f"module-{sequence:02d}"
            marker = f"CREATE RECORD MODULE {sequence:02d} READY"
        items.append(
            auth_read.LoadItem(
                name=name,
                guest=f"local_testing/cr-m{sequence:02d}.f",
                marker=marker,
                source=SOURCE_ROOT / module,
            )
        )
    assert crypto_seam_inserted
    assert transport_seam_inserted
    return tuple(items)


MODULE_ITEMS = _module_items()
FIXTURE_ITEMS = (
    auth_read.LoadItem(
        name="profile-fixture",
        guest="local_testing/cr-prof.f",
        marker="CREATE RECORD PROFILE FIXTURE READY",
        source=auth_read.PROFILE_FIXTURE,
        remove_requires=False,
    ),
    auth_read.LoadItem(
        name="client-fixture",
        guest="local_testing/cr-client.f",
        marker="CREATE RECORD CLIENT FIXTURE READY",
        source=auth_read.CLIENT_FIXTURE,
        remove_requires=False,
    ),
    auth_read.LoadItem(
        name="authenticated-session-fixture",
        guest="local_testing/cr-auth.f",
        marker="CREATE RECORD AUTH FIXTURE READY",
        source=auth_read.CONTRACT,
    ),
    auth_read.LoadItem(
        name="create-record-fixture",
        guest="local_testing/cr-e2e.f",
        marker="CREATE RECORD FIXTURE READY",
        source=CONTRACT,
    ),
)

RUNTIME_STAGES = (
    ("setup", "_ATXR-SETUP", "CREATE RECORD SETUP READY"),
    ("provision", "_ATXR-PROVISION", "CREATE RECORD KEY READY"),
    ("install", "_ATXR-INSTALL", "CREATE RECORD SESSION READY"),
    ("owner-restart", "_ATXR-RESTART", "CREATE RECORD REOPEN READY"),
    ("owner-setup", "_ATCRT-SETUP", "CREATE RECORD OWNERS READY"),
    ("local-admission", "_ATCRT-LOCAL", "CREATE RECORD LOCAL READY"),
    ("wire-failures", "_ATCRT-FAILURES", "CREATE RECORD FAILURES READY"),
    ("successful-write", "_ATCRT-SUCCESS", "CREATE RECORD SUCCESS READY"),
    (
        "owner-release",
        "_ATCRT-RELEASE-OWNERS",
        "CREATE RECORD OWNERS RELEASED",
    ),
    ("finish", "_ATCRT-FINISH", PASS_MARKER),
)

FAILURE_MARKERS = (
    "CREATE RECORD E2E FAIL",
    "AT XRPC AUTH READ FAIL",
    "AT XRPC AUTH READ ASSERT",
    "AT XRPC AUTH READ STATUS",
    "AT XRPC AUTH READ STACK",
    "AT XRPC LOAD STACK FAIL",
    "CREATE RECORD LOAD STACK FAIL",
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


def _forth_code(source: str) -> str:
    return "\n".join(
        line.split("\\", 1)[0] for line in source.splitlines()
    )


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing Forth word {name}"
    return match.group("body")


def _assert_static() -> None:
    owner = OWNER.read_text(encoding="utf-8")
    codec = CODEC.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")
    fixture = CONTRACT.read_text(encoding="utf-8")
    owner_code = _forth_code(owner)

    assert RAW_MODULES[-2:] == (
        "atproto/create-record-codec.f",
        "atproto/create-record.f",
    )
    assert "atproto/xrpc-exchange.f" in RAW_MODULES
    assert "utils/fs/vfs.f" in RAW_MODULES
    assert REPLACED_CRYPTO_MODULES < set(RAW_MODULES)
    assert NUM_CORES == 1
    assert EXT_MEM_SIZE == 128 << 20
    assert MAX_PHASE_STEPS == 180_000_000
    assert LINKED is False

    assert _requires(OWNER) == [
        "../utils/memory-span.f",
        "../utils/caller-span.f",
        "../utils/buffer-writer.f",
        "../net/http-target.f",
        "../net/external-io.f",
        "xrpc-exchange.f",
        "create-record-codec.f",
    ]
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        owner_code,
    )
    for forbidden in (
        "OWNER-POOL",
        "OWNER-TABLE",
        "OWNER-SLOTS",
        "INSTANCE-COUNT",
        "MAX-INSTANCES",
        "SLOT-COUNT",
    ):
        assert forbidden not in owner_code.upper()
    assert not re.search(
        r"(?mi)^[ \t]*\d+[ \t]+CONSTANT[ \t]+\S*"
        r"(?:POOL|SLOT|INSTANCE)",
        owner_code,
    )

    for marker in (
        "PROVIDED akashic-at-create-rec",
        "AT-CREATE-RECORD-RESULT-INIT",
        "AT-CREATE-RECORD-RESULT-OUTCOME@",
        "AT-CREATE-RECORD-RESULT-STATUS@",
        "AT-CREATE-RECORD-RESULT-HTTP@",
        "AT-CREATE-RECORD-RESULT-WIRE@",
        "AT-CREATE-RECORD-RESULT-URI@",
        "AT-CREATE-RECORD-RESULT-CID@",
        "AT-CREATE-RECORD-INIT",
        "AT-CREATE-RECORD-PREPARE",
        "AT-CREATE-RECORD-XIO-START",
        "AT-CREATE-RECORD-XIO-POLL",
        "AT-CREATE-RECORD-XIO-CANCEL",
        "AT-CREATE-RECORD-XIO-WIPE",
        "AT-CREATE-RECORD-OUTCOME-NO-EFFECT",
        "AT-CREATE-RECORD-OUTCOME-UNCERTAIN",
        "AT-CREATE-RECORD-OUTCOME-CREATED",
        "AT-XRPC-EXCHANGE-EXTERNAL-SPAN-STATUS",
        "ATCR.BODY-CAP !",
        "com.atproto.repo.createRecord",
    ):
        assert marker in owner
    init_body = _word_body(owner, "AT-CREATE-RECORD-INIT")
    assert "ATCR.BODY-A !" in init_body
    assert "ATCR.BODY-CAP !" in init_body
    assert "ATCR.WORKSPACE !" in init_body
    assert "ATCR.RESULT !" in init_body

    for marker in (
        "AT-CREATE-RECORD-BODY",
        "AT-CREATE-RECORD-RECEIPT",
        "JOSE-JSON-OBJECT-PARSE",
        "AT-CID-TEXT-CHECK",
        "AT-CID-CODEC-DAG-CBOR",
    ):
        assert marker in codec

    assert _requires(CONTRACT) == ["at-xrpc-auth-read-test.f"]
    assert "at-xrpc-exchange-test.f" not in fixture
    assert "_atxet-owner" not in fixture
    for marker in (
        "_ATCRT-SETUP",
        "_ATCRT-LOCAL",
        "_ATCRT-FAILURES",
        "_ATCRT-SUCCESS",
        "_ATCRT-RELEASE-OWNERS",
        "_ATCRT-FINISH",
        "_ATCRT-CREATE-BODY-A-CAPACITY",
        "_ATCRT-CREATE-BODY-B-CAPACITY",
        "_ATCRT-XREQUEST-A-CAPACITY",
        "_ATCRT-XREQUEST-B-CAPACITY",
        "_atcrt-owner-a",
        "_atcrt-owner-b",
        "_atcrt-context-a",
        "_atcrt-context-b",
        "NIO.CONTEXT !",
        "ATCT.CAPTURE-CAP",
        "AT-CREATE-RECORD-S-CAPACITY",
        "AT-CREATE-RECORD-S-ALIAS",
        "AT-CREATE-RECORD-OUTCOME-NO-EFFECT",
        "AT-CREATE-RECORD-OUTCOME-UNCERTAIN",
        "AT-CREATE-RECORD-OUTCOME-CREATED",
        "AT-XRPC-EXCHANGE-WIRE-UNCERTAIN",
        "AT-XRPC-EXCHANGE-WIRE-RESPONSE",
        "POST /xrpc/com.atproto.repo.createRecord HTTP/1.1",
        "Authorization: DPoP access-vertical",
        "https://pds.example/xrpc/com.atproto.repo.createRecord",
        "use_dpop_nonce",
        "pds-nonce-1",
        "PREPARE owns target, collection, key, and record",
        "result graph is self-contained",
    ):
        assert marker in fixture
    assert (
        "HTARGET-SIZE 512 + CONSTANT "
        "_ATCRT-CREATE-BODY-A-CAPACITY"
    ) in fixture
    assert (
        "HTARGET-SIZE 1024 + CONSTANT "
        "_ATCRT-CREATE-BODY-B-CAPACITY"
    ) in fixture
    assert "fixture-only" in fixture
    assert "production instance count" in fixture
    assert "_atcrt-active-exchange" not in fixture
    assert not re.search(
        r"(?i)(?<![A-Za-z0-9_-])(?:\?DO|DO|\+LOOP|LOOP)"
        r"(?![A-Za-z0-9_-])",
        _forth_code(fixture),
    ), "fixture must not borrow the DO-loop return stack"
    for callback in (
        "_atcrt-open",
        "_atcrt-send",
        "_atcrt-recv",
        "_atcrt-loss-recv",
        "_atcrt-close",
    ):
        body = _word_body(fixture, callback)
        assert "_atcrt-script-context" not in body
        assert "_atcrt-observe-context" not in body

    setup_body = _word_body(fixture, "_ATCRT-SETUP")
    local_body = _word_body(fixture, "_ATCRT-LOCAL")
    failures_body = _word_body(fixture, "_ATCRT-FAILURES")
    assert "_atcrt-init-results-and-owners" in setup_body
    assert "_atcrt-prepare-durable-b" in local_body
    assert failures_body.index("_atcrt-no-send") < failures_body.index(
        "_atcrt-loss-after-send"
    )
    assert failures_body.index("_atcrt-loss-after-send") < failures_body.index(
        "_atcrt-malformed-200"
    )
    assert failures_body.index("_atcrt-malformed-200") < failures_body.index(
        "AT-CREATE-RECORD-STATE-PREPARED"
    )
    assert [name for name, _, _ in RUNTIME_STAGES] == [
        "setup",
        "provision",
        "install",
        "owner-restart",
        "owner-setup",
        "local-admission",
        "wire-failures",
        "successful-write",
        "owner-release",
        "finish",
    ]

    for marker in (
        "There is no owner table or process-wide instance count",
        "caller may overwrite every collection, record-key, record, and target",
        "NO-EFFECT",
        "UNCERTAIN",
        "CREATED",
        "remain valid after XIO wipe",
        "no general write retry",
    ):
        assert marker in doc

    all_items = (*MODULE_ITEMS, *FIXTURE_ITEMS)
    assert len({item.name for item in all_items}) == len(all_items)
    assert len({item.marker for item in all_items}) == len(all_items)
    for item in all_items:
        assert len(Path(item.guest).name.encode("utf-8")) <= 23
        assert (item.source is None) != (item.inline is None)
    for path in {
        *(item.source for item in all_items if item.source),
        OWNER,
        CODEC,
        CONTRACT,
    }:
        auth_read._assert_physical_comments(  # noqa: SLF001
            path,
            path.read_text(encoding="utf-8"),
        )


def _initial_files() -> tuple[tuple[str, bytes], ...]:
    return tuple(
        (item.guest, auth_read._load_bytes(item))  # noqa: SLF001
        for item in (*MODULE_ITEMS, *FIXTURE_ITEMS)
    )


def _autoexec() -> str:
    lines = [
        "\\ autoexec.f - authenticated createRecord qualification\n",
        "ENTER-USERLAND\n",
    ]
    for item in (*MODULE_ITEMS, *FIXTURE_ITEMS):
        lines.extend(
            (
                f"REQUIRE {item.guest}\n",
                (
                    'DEPTH IF ." CREATE RECORD LOAD STACK FAIL '
                    f'{item.name}" CR TX-FLUSH THEN\n'
                ),
                f'." {item.marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    for _, word, marker in RUNTIME_STAGES:
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


def _run_vertical(timeout: float) -> int:
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=(),
        resources=(),
        autoexec=_autoexec(),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=FAILURE_MARKERS,
        initial_files=_initial_files(),
        linked=LINKED,
        include_large_sample=False,
        total_sectors=8192,
    )
    image_path = harness.build_image(PROFILE, IMAGE)
    profile = harness.PROFILES[PROFILE]
    stages = (
        *(
            (item.name, item.marker)
            for item in (*MODULE_ITEMS, *FIXTURE_ITEMS)
        ),
        *((name, marker) for name, _, marker in RUNTIME_STAGES),
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
        for index, (stage_name, marker) in enumerate(stages):
            if index:
                machine.clear_output()
                machine.send_text("x")
            report = machine.run(
                max_steps=MAX_PHASE_STEPS,
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
            if marker not in raw_text or failures:
                print(f"CREATE RECORD {stage_name}: FAIL")
                print(
                    f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
                    f"stop={report.reason}"
                )
                for failure in failures:
                    print(f"  {failure}")
                print(raw_text[-5000:])
                return 1
            print(
                f"CREATE RECORD {stage_name}: PASS "
                f"({report.steps:,} steps, {report.elapsed_s:.2f}s)",
                flush=True,
            )
    print("CREATE RECORD vertical: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument(
        "--vertical",
        action="store_true",
        help="run the staged single-core emulator qualification",
    )
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    _assert_static()
    if args.static_only:
        print("CREATE RECORD STATIC PASS")
        return 0
    return _run_vertical(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
