#!/usr/bin/env python3
"""Generate Desk Gate 0 golden records with the current Forth encoders.

This is intentionally a maintainer command, not part of an ordinary smoke
run.  The guest constructs canonical records through the production Streams
stores, the host extracts the exact MP64FS bytes, and the committed manifest
remains the review point for any later byte change.
"""

from __future__ import annotations

import tempfile
import time
from pathlib import Path

import akashic_tui as harness


PROFILE_NAME = "desk-gate0-fixture-generation"
FIXTURE_ROOT = (
    harness.AKASHIC_ROOT / "local_testing" / "fixtures" / "desk-gate0"
)

GUEST_TO_HOST = {
    "s-valid.bin": "source-v1-valid.bin",
    "s-corrupt.bin": "source-v1-corrupt.bin",
    "s-future.bin": "source-v2-future.bin",
    "o-valid.bin": "observation-v1-valid.bin",
    "o-corrupt.bin": "observation-v1-corrupt.bin",
    "o-future.bin": "observation-v2-future.bin",
    "d-legacy.bin": "draft-v1-legacy-r7.bin",
}


AUTOEXEC = r"""\ autoexec.f - one-shot Desk Gate 0 golden generation
ENTER-USERLAND
." [akashic] generating Desk Gate 0 fixtures" CR
REQUIRE utils/fs/drivers/vfs-mp64fs.f
REQUIRE tui/applets/streams/source-store.f
REQUIRE tui/applets/streams/observation-store.f
REQUIRE tui/applets/streams/draft-store.f

CREATE _g0-source STREAMS-SOURCE-SIZE ALLOT
CREATE _g0-registry STREAMS-SOURCE-REGISTRY-SIZE ALLOT
CREATE _g0-source-rid RID-SIZE ALLOT
CREATE _g0-namespace RID-SIZE ALLOT
CREATE _g0-source-store STREAMS-SOURCE-STORE-SIZE ALLOT
CREATE _g0-observation-store STREAMS-OBSERVATION-STORE-SIZE ALLOT
CREATE _g0-draft-store STREAMS-DRAFT-STORE-SIZE ALLOT
CREATE _g0-candidate OCHK-CANDIDATE-SIZE ALLOT
VARIABLE _g0-checkpoint
VARIABLE _g0-fd
VARIABLE _g0-data-a
VARIABLE _g0-data-u
VARIABLE _g0-path-a
VARIABLE _g0-path-u
VARIABLE _g0-record-u
VARIABLE _g0-status
VARIABLE _g0-check

: _g0-assert  ( flag -- )
    1 _g0-check +! 0= IF
        ." DESK GATE0 FIXTURE ASSERT " _g0-check @ . CR
        ABORT
    THEN ;

: _g0-put  ( data-a data-u path-a path-u -- )
    _g0-path-u ! _g0-path-a ! _g0-data-u ! _g0-data-a !
    _g0-path-a @ _g0-path-u @ VFS-CUR VFS-CREATE
        DUP 0<> _g0-assert DROP
    _g0-path-a @ _g0-path-u @ VFS-OPEN DUP _g0-fd ! 0<> _g0-assert
    _g0-data-a @ _g0-data-u @ _g0-fd @ VFS-WRITE-EXACT 0= _g0-assert
    _g0-fd @ VFS-CLOSE 0 _g0-fd !
    VFS-CUR VFS-SYNC 0= _g0-assert ;

: _g0-source!  ( -- )
    _g0-source-rid RID-CLEAR 0x101 _g0-source-rid !
    _g0-source STREAMS-SOURCE-INIT
    _g0-source-rid _g0-source STREAMS-SOURCE-ID! SSREG-S-OK = _g0-assert
    SSOURCE-KIND-SYNDICATION _g0-source SSOURCE.KIND !
    SSOURCE-FORMAT-JSON-FEED _g0-source SSOURCE.FORMAT !
    SSOURCE-F-ENABLED _g0-source SSOURCE.FLAGS !
    S" Gate 0 feed" _g0-source STREAMS-SOURCE-LABEL!
        SSREG-S-OK = _g0-assert
    S" https://example.test/gate0.json" _g0-source
        STREAMS-SOURCE-ENDPOINT! SSREG-S-OK = _g0-assert
    _g0-source _SSOURCE-CONFIG-VALID? _g0-assert ;

: _g0-source-fixtures  ( -- )
    _g0-source! _g0-registry STREAMS-SOURCE-REGISTRY-INIT
    _g0-source _g0-registry STREAMS-SOURCE-CREATE
        SSREG-S-OK = _g0-assert
    S" /s-valid.bin" VFS-CUR _g0-source-store
        STREAMS-SOURCE-STORE-INIT-AT SSSTORE-S-OK = _g0-assert
    _g0-registry 0 _g0-source-store STREAMS-SOURCE-STORE-SAVE
        SSSTORE-S-OK = _g0-assert

    _g0-registry _STREAMS-SOURCE-STORE-ENCODE
        _g0-status ! _g0-record-u !
    _g0-status @ SSSTORE-S-OK = _g0-assert
    _SSSTORE-RECORD STREAMS-SOURCE-STORE-HEADER-SIZE +
        DUP C@ 1 XOR SWAP C!
    _SSSTORE-RECORD _g0-record-u @ S" /s-corrupt.bin" _g0-put

    _g0-registry _STREAMS-SOURCE-STORE-ENCODE
        _g0-status ! _g0-record-u !
    _g0-status @ SSSTORE-S-OK = _g0-assert
    STREAMS-SOURCE-STORE-FORMAT-V1 1+
        _SSSTORE-RECORD _SSS-H-FORMAT + !
    _SSSTORE-RECORD _STREAMS-SOURCE-STORE-HEADER-CRC
        _SSSTORE-RECORD _SSS-H-HEADER-CRC + !
    _SSSTORE-RECORD _g0-record-u @ S" /s-future.bin" _g0-put ;

: _g0-candidate!  ( -- )
    _g0-candidate OCHK-CANDIDATE-INIT
    3 _g0-candidate OCC.FORMAT !
    OCHK-NATIVE-PROVIDER-ID _g0-candidate OCC.NATIVE-KIND !
    S" gate0-item" 2DUP _g0-candidate OCC.NATIVE-U !
        _g0-candidate OCC.NATIVE-A !
    S" Gate 0 observation" 2DUP _g0-candidate OCC.TITLE-U !
        _g0-candidate OCC.TITLE-A !
    S" https://example.test/items/gate0" 2DUP
        _g0-candidate OCC.URL-U ! _g0-candidate OCC.URL-A !
    S" Frozen observation fixture" 2DUP
        _g0-candidate OCC.SUMMARY-U ! _g0-candidate OCC.SUMMARY-A !
    S" Exact retained body" 2DUP _g0-candidate OCC.CONTENT-U !
        _g0-candidate OCC.CONTENT-A !
    S" 2026-07-17T12:00:00Z" 2DUP _g0-candidate OCC.PUBLISHED-U !
        _g0-candidate OCC.PUBLISHED-A !
    S" 2026-07-17T12:01:00Z" 2DUP _g0-candidate OCC.MODIFIED-U !
        _g0-candidate OCC.MODIFIED-A ! ;

: _g0-observation-fixtures  ( -- )
    STREAMS-OBSERVATION-CHECKPOINT-SIZE ALLOCATE 0= _g0-assert
        _g0-checkpoint !
    _g0-checkpoint @ OCHK-INIT
    _g0-namespace RID-CLEAR 0x202 _g0-namespace !
    _g0-source-rid 1 _g0-namespace SSOURCE-KIND-SYNDICATION
        S" https://example.test/gate0.json" _g0-checkpoint @ OCHK-BEGIN
        OCHK-S-OK = _g0-assert
    S" /o-valid.bin" VFS-CUR _g0-observation-store
        STREAMS-OBSERVATION-STORE-INIT-AT OSTORE-S-OK = _g0-assert
    _g0-checkpoint @ 0 _g0-observation-store
        STREAMS-OBSERVATION-STORE-SAVE OSTORE-S-OK = _g0-assert

    _g0-candidate!
    _g0-source-rid 1 S" https://example.test/gate0.json" 17 200
        _g0-candidate 1 _g0-checkpoint @ OCHK-APPLY
        OCHK-S-OK = _g0-assert
    _g0-source-rid _g0-checkpoint @ OCHK-SOURCE-FIND DUP 0<> _g0-assert
    1000 OVER OCS.STARTED-MS ! 1001 SWAP OCS.FINISHED-MS !
    _g0-checkpoint @ OCHK-SEAL
    _g0-checkpoint @ OCHK-VALID? _g0-assert
    _g0-checkpoint @ 1 _g0-observation-store
        STREAMS-OBSERVATION-STORE-SAVE OSTORE-S-OK = _g0-assert

    _g0-checkpoint @ _STREAMS-OBSERVATION-STORE-ENCODE
        _g0-status ! _g0-record-u !
    _g0-status @ OSTORE-S-OK = _g0-assert
    _OSTORE-RECORD STREAMS-OBSERVATION-STORE-HEADER-SIZE +
        DUP C@ 1 XOR SWAP C!
    _OSTORE-RECORD _g0-record-u @ S" /o-corrupt.bin" _g0-put

    _g0-checkpoint @ _STREAMS-OBSERVATION-STORE-ENCODE
        _g0-status ! _g0-record-u !
    _g0-status @ OSTORE-S-OK = _g0-assert
    STREAMS-OBSERVATION-STORE-FORMAT-V1 1+
        _OSTORE-RECORD _OSS-H-FORMAT + !
    _OSTORE-RECORD _STREAMS-OBSERVATION-STORE-HEADER-CRC
        _OSTORE-RECORD _OSS-H-HEADER-CRC + !
    _OSTORE-RECORD _g0-record-u @ S" /o-future.bin" _g0-put
    _g0-checkpoint @ FREE ;

: _g0-draft-fixture  ( -- )
    S" /d-legacy.bin" VFS-CUR _g0-draft-store
        STREAMS-DRAFT-STORE-INIT-AT SDSTORE-S-OK = _g0-assert
    S" exact ☂ café" 7 _g0-draft-store STREAMS-DRAFT-STORE-SAVE
        SDSTORE-S-OK = _g0-assert ;

: _g0-run  ( -- )
    0 _g0-check !
    1048576 A-XMEM ARENA-NEW DUP 0= _g0-assert DROP
    VMP-NEW DUP 0<> _g0-assert
    DUP VMP-INIT 0= _g0-assert
    VFS-USE
    VFS-CUR 0<> _g0-assert
    ." [gate0] source fixtures" CR
    _g0-source-fixtures
    ." [gate0] observation fixtures" CR
    _g0-observation-fixtures
    ." [gate0] draft fixture" CR
    _g0-draft-fixture
    ." DESK GATE0 FIXTURES READY" CR ;

_g0-run
"""


def _install_profile() -> None:
    harness.PROFILES[PROFILE_NAME] = harness.Profile(
        roots=(
            "utils/fs/drivers/vfs-mp64fs.f",
            "tui/applets/streams/source-store.f",
            "tui/applets/streams/observation-store.f",
            "tui/applets/streams/draft-store.f",
        ),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("DESK GATE0 FIXTURES READY",),
        stable_markers=("DESK GATE0 FIXTURES READY",),
        failure_markers=("DESK GATE0 FIXTURE ASSERT",),
        linked=True,
        include_large_sample=False,
        total_sectors=4096,
    )


def _run_guest(image_path: Path) -> harness.MP64FS:
    with harness.MachineSession.from_bios(
        harness.MEGAPAD_ROOT / "bios.asm",
        storage_image=image_path,
        cols=100,
        rows=30,
        batch_steps=500_000,
        ext_mem_size=harness.DEFAULT_EXT_MEM_MIB << 20,
        num_cores=1,
    ) as session:
        session.boot()
        deadline = time.monotonic() + 90.0
        steps = 0
        while steps < 4_000_000_000 and time.monotonic() < deadline:
            report = session.run(
                max_steps=min(50_000_000, 4_000_000_000 - steps),
                wall_timeout_s=min(2.0, max(0.05, deadline - time.monotonic())),
                advance_idle=True,
            )
            steps += report.steps
            transcript = session.raw_text()
            if "DESK GATE0 FIXTURES READY" in transcript:
                return harness.MP64FS(
                    bytearray(session.system.storage._image_data)
                )
            if "DESK GATE0 FIXTURE ASSERT" in transcript:
                raise RuntimeError(
                    f"guest fixture generation failed:\n{transcript[-12000:]}"
                )
            if report.reason in ("halted", "stalled"):
                break
        raise RuntimeError(
            "guest fixture generation did not reach its ready marker; "
            f"steps={steps:,}\n{session.raw_text()[-12000:]}"
        )


def main() -> int:
    _install_profile()
    FIXTURE_ROOT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="akashic-desk-gate0-") as tmp:
        image_path = Path(tmp) / "generation.img"
        harness.build_image(PROFILE_NAME, image_path)
        filesystem = _run_guest(image_path)
        for guest_name, host_name in GUEST_TO_HOST.items():
            content = filesystem.read_file(guest_name)
            target = FIXTURE_ROOT / host_name
            target.write_bytes(content)
            print(f"wrote {target.relative_to(harness.AKASHIC_ROOT)} ({len(content)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
