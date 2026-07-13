#!/usr/bin/env python3
"""Run the trusted-local package acceptance profile across two cold boots."""

from __future__ import annotations

import argparse
import time
from pathlib import Path

from akashic_tui import (
    FTYPE_FORTH,
    MEGAPAD_ROOT,
    MP64FS,
    MachineSession,
    build_image,
)


COLD_AUTOEXEC = r"""\ autoexec.f - cold trusted-local package readback
ENTER-USERLAND
REQUIRE tui/app-loader.f
REQUIRE tui/app-catalog.f
REQUIRE tui/draw.f
REQUIRE utils/fs/drivers/vfs-mp64fs.f

VARIABLE _cold-fails
VARIABLE _cold-checks
VARIABLE _cold-vfs
VARIABLE _cold-cat
VARIABLE _cold-entry
VARIABLE _cold-desc
VARIABLE _cold-inst
VARIABLE _cold-here
VARIABLE _cold-latest

: _cold-assert  ( flag -- )
    1 _cold-checks +!
    0= IF 1 _cold-fails +! ." ASSERT " _cold-checks @ . CR THEN ;

: _cold-resolver  ( entry context -- desc status )
    DROP ACE-MANIFEST$ ALOAD-PATH ;

: _cold-cycle  ( -- )
    _cold-desc @ APP.COMP-DESC @ CINST-NEW
    DUP 0= _cold-assert DROP DUP 0<> _cold-assert _cold-inst !
    _cold-desc @ APP.INIT-XT @ ?DUP IF _cold-inst @ SWAP EXECUTE THEN
    _cold-desc @ APP.REQUEST-CLOSE-XT @ ?DUP IF
        APP-CLOSE-R-WINDOW _cold-inst @ ROT EXECUTE
        APP-CLOSE-D-ALLOW = _cold-assert
    THEN
    _cold-desc @ APP.SHUTDOWN-XT @ ?DUP IF
        _cold-inst @ SWAP EXECUTE
    THEN
    _cold-inst @ CINST-FREE 0 _cold-inst ! ;

: _cold-run  ( -- )
    0 _cold-fails ! 0 _cold-checks !
    2097152 A-XMEM ARENA-NEW IF -1 THROW THEN
    VMP-NEW DUP _cold-vfs !
    DUP VMP-INIT 0= _cold-assert VFS-USE
    _cold-vfs @ ACAT-NEW
    DUP ACAT-S-OK = _cold-assert DROP DUP _cold-cat !
    ACAT-ACTIVATE ACAT-S-OK = _cold-assert
    _cold-cat @ ACAT-COUNT 1 = _cold-assert
    S" local.hello" _cold-cat @ ACAT-FIND-ID
    DUP 0<> _cold-assert DUP _cold-entry !
    ACE-MANIFEST$ VFS-OPEN DUP 0<> _cold-assert ?DUP IF VFS-CLOSE THEN
    ['] _cold-resolver 0 _cold-cat @ ACAT-RESOLVER!
    _cold-entry @ _cold-cat @ ACAT-RESOLVE
    DUP ACAT-S-OK = _cold-assert DROP DUP 0<> _cold-assert _cold-desc !
    _cold-desc @ APP-DESC-VALID? _cold-assert
    _cold-desc @ APP.COMP-DESC @ DUP COMP.ID-A @ SWAP COMP.ID-U @
        S" local.hello" COMPARE 0= _cold-assert
    _cold-cycle _cold-cycle
    HERE _cold-here ! LATEST _cold-latest !
    _cold-entry @ _cold-cat @ ACAT-RESOLVE
    DUP ACAT-S-OK = _cold-assert DROP _cold-desc @ = _cold-assert
    HERE _cold-here @ = _cold-assert LATEST _cold-latest @ = _cold-assert
    _cold-fails @ 0= IF
        ." PACKAGE COLD BOOT PASS " _cold-checks @ .
    ELSE
        ." PACKAGE COLD BOOT FAIL " _cold-fails @ . ." / " _cold-checks @ .
    THEN CR ;

_cold-run
"""


def _run_until(image: Path, marker: str, failure: str, timeout: float) -> bytes:
    deadline = time.monotonic() + timeout
    steps = 0
    with MachineSession.from_bios(
        MEGAPAD_ROOT / "bios.asm",
        storage_image=image,
        cols=108,
        rows=34,
        batch_steps=500_000,
    ) as session:
        session.boot()
        while time.monotonic() < deadline and steps < 5_000_000_000:
            report = session.run(
                max_steps=50_000_000,
                wall_timeout_s=min(2.0, max(0.05, deadline - time.monotonic())),
                advance_idle=True,
            )
            steps += report.steps
            text = session.snapshot().text()
            if failure in text:
                raise RuntimeError(f"guest reported {failure!r}\n{text}")
            if marker in text:
                return bytes(session.system.storage._image_data)
            if report.reason in ("halted", "stalled"):
                break
        raw = session.raw_text()
        raise RuntimeError(f"timed out waiting for {marker!r}\n{raw[-4000:]}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--image",
        type=Path,
        default=Path("/tmp/akashic-package-two-boot.img"),
    )
    parser.add_argument("--timeout", type=float, default=150.0)
    args = parser.parse_args()

    image = build_image("package-contracts", args.image)
    first_disk = _run_until(
        image, "PACKAGE CONTRACTS PASS", "PACKAGE CONTRACTS FAIL", args.timeout
    )

    fs = MP64FS(bytearray(first_disk))
    fs.delete_file("autoexec.f")
    fs.inject_file("autoexec.f", COLD_AUTOEXEC.encode("utf-8"), ftype=FTYPE_FORTH)
    fs.save(image)

    _run_until(
        image, "PACKAGE COLD BOOT PASS", "PACKAGE COLD BOOT FAIL", args.timeout
    )
    print(f"Trusted-local package two-boot acceptance: PASS ({image})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
