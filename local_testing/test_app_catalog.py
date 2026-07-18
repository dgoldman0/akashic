#!/usr/bin/env python3
"""Focused codec, persistence, upsert, and resolver tests for app-catalog.f."""

from __future__ import annotations

from pathlib import Path
import sys


HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))

import test_vfs_replace as vrepl_test  # noqa: E402


def _chunk_line(line: str, limit: int = 180) -> list[str]:
    """Split a colon definition at whitespace outside Forth string literals."""
    chunks: list[str] = []
    rest = line.strip()
    while len(rest) > limit:
        in_string = False
        safe = -1
        index = 0
        while index < min(len(rest), limit + 1):
            if not in_string and rest.startswith('S"', index):
                in_string = True
                index += 2
                continue
            if in_string and rest[index] == '"':
                in_string = False
            elif not in_string and rest[index].isspace():
                safe = index
            index += 1
        if safe <= 0:
            return [line]
        chunks.append(rest[:safe])
        rest = rest[safe:].lstrip()
    if rest:
        chunks.append(rest)
    return chunks


def main() -> int:
    vrepl_test.build_snapshot()
    sources = (
        ROOT / "akashic" / "utils" / "string.f",
        ROOT / "akashic" / "runtime" / "instance.f",
        ROOT / "akashic" / "tui" / "app-desc.f",
        ROOT / "akashic" / "tui" / "app-catalog.f",
    )
    forth: list[str] = []
    for source in sources:
        forth.extend(vrepl_test._forth_lines(source))
    forth.extend(
        [
            "VARIABLE _CTV VARIABLE _CC1 VARIABLE _CC2 VARIABLE _CC3",
            "VARIABLE _CS VARIABLE _CU",
            "VARIABLE _CREL-N",
            "CREATE _CTCOMP COMP-DESC ALLOT CREATE _CTAPP APP-DESC ALLOT",
            "CREATE _CPCOMP COMP-DESC ALLOT CREATE _CPAPP APP-DESC ALLOT",
            "CREATE _CBUF ACAT-FILE-MAX 1+ ALLOT",
            "CREATE _CT-OPS VFS-OPS-SIZE ALLOT",
            "CREATE _CT-BINDING VFS-BINDING-DESC-SIZE ALLOT",
            ": CT-BINDING-RESET VFS-RAM-OPS _CT-OPS VFS-OPS-SIZE CMOVE "
            "VFS-RAM-BINDING _CT-BINDING VFS-BINDING-DESC-SIZE CMOVE "
            "_CT-OPS _CT-BINDING VB.OPS ! ;",
            ": CT-VFS-NEW CT-BINDING-RESET "
            "1048576 A-XMEM ARENA-NEW IF -1 THROW THEN "
            "_CT-BINDING 0 VFS-NEW ?DUP IF THROW THEN ;",
            ": CT-DESCS "
            "_CTCOMP COMP-DESC-INIT "
            'S" org.test.builtin" _CTCOMP COMP.ID-U ! _CTCOMP COMP.ID-A ! '
            'S" 1.0" _CTCOMP COMP.VERSION-U ! _CTCOMP COMP.VERSION-A ! '
            "_CTAPP APP-DESC-INIT _CTCOMP _CTAPP APP.COMP-DESC ! "
            'S" Built in" _CTAPP APP.TITLE-U ! _CTAPP APP.TITLE-A ! '
            "_CPCOMP COMP-DESC-INIT "
            'S" org.test.package" _CPCOMP COMP.ID-U ! _CPCOMP COMP.ID-A ! '
            'S" 2.0" _CPCOMP COMP.VERSION-U ! _CPCOMP COMP.VERSION-A ! '
            "_CPAPP APP-DESC-INIT _CPCOMP _CPAPP APP.COMP-DESC ! "
            'S" Package two" _CPAPP APP.TITLE-U ! _CPAPP APP.TITLE-A ! ;',
            ": CT-PKG1 "
            'S" org.test.package" S" Package one" S" 1.0" '
            'S" /pkg/app.toml" ACAT-F-ENABLED ACAT-F-PINNED OR '
            "_CC1 @ ACAT-UPSERT-PACKAGE ;",
            ": CT-PKG2 "
            'S" org.test.package" S" Package two" S" 2.0" '
            'S" /pkg/app-v2.toml" 0 _CC1 @ ACAT-UPSERT-PACKAGE ;',
            ": CT-PKG3 "
            'S" org.test.package" S" Package three" S" 3.0" '
            'S" /pkg/app-v3.toml" 0 _CC1 @ ACAT-UPSERT-PACKAGE ;',
            ": CT-FAIL-SYNC DROP -1 ;",
            ": CT-RESOLVE 2DROP _CPAPP ACAT-S-OK ;",
            ": CT-RELEASE DROP _CPAPP = IF 1 _CREL-N +! THEN ;",
            'S" CATRESULT " TYPE '
            "CT-VFS-NEW DUP _CTV ! VFS-USE "
            "_CTV @ ACAT-NEW _CS ! _CC1 ! _CS @ . "
            "_CC1 @ ACAT-ACTIVATE . "
            "CT-DESCS "
            "_CTAPP _DESK-BUILTIN-DEFAULT-FLAGS _CC1 @ "
            "ACAT-BIND-BUILTIN . _CC1 @ ACAT-COUNT . "
            'S" org.test.builtin" _CC1 @ ACAT-FIND-ID ACE.FLAGS @ . '
            "CT-PKG1 . _CC1 @ ACAT-COUNT . "
            "CT-PKG2 . "
            'S" org.test.package" _CC1 @ ACAT-FIND-ID DUP ACE-TITLE$ '
            "TYPE SPACE ACE.FLAGS @ . "
            'S" org.test.package" _CC1 @ ACAT-FIND-ID '
            "77 OVER ACE.SLOT ! DROP CT-PKG2 . "
            'S" org.test.package" _CC1 @ ACAT-FIND-ID ACE-TITLE$ '
            "TYPE SPACE "
            'S" org.test.package" _CC1 @ ACAT-FIND-ID '
            "0 SWAP _CC1 @ ACAT-MARK-SLOT "
            "' CT-FAIL-SYNC _CT-OPS VFS-OP-SYNCFS CELLS + ! "
            "CT-PKG3 . "
            "' _VFS-RAM-SYNCFS _CT-OPS VFS-OP-SYNCFS CELLS + ! "
            'S" org.test.package" _CC1 @ ACAT-FIND-ID ACE-TITLE$ '
            "TYPE SPACE "
            "' CT-RESOLVE 123 _CC1 @ ACAT-RESOLVER! "
            "' CT-RELEASE 456 _CC1 @ ACAT-RELEASER! "
            'S" org.test.package" _CC1 @ ACAT-FIND-ID _CC1 @ '
            "ACAT-RESOLVE SWAP _CPAPP = . . "
            "' CT-FAIL-SYNC _CT-OPS VFS-OP-SYNCFS CELLS + ! "
            "CT-PKG3 . "
            "' _VFS-RAM-SYNCFS _CT-OPS VFS-OP-SYNCFS CELLS + ! "
            "_CREL-N @ . "
            'S" org.test.package" _CC1 @ ACAT-FIND-ID _CC1 @ '
            "ACAT-RESOLVE SWAP _CPAPP = . . "
            "CT-PKG2 . _CREL-N @ . "
            'S" org.test.package" _CC1 @ ACAT-FIND-ID _CC1 @ '
            "ACAT-RESOLVE 2DROP "
            "_CC1 @ ACAT-FREE _CREL-N @ . "
            "_CTV @ ACAT-NEW _CS ! _CC2 ! _CS @ . "
            "_CC2 @ ACAT-ACTIVATE . _CC2 @ ACAT-COUNT . "
            'S" org.test.builtin" _CC2 @ ACAT-FIND-ID '
            "DUP ACE.DESC @ . ACE.STATE @ . "
            'S" org.test.package" _CC2 @ ACAT-FIND-ID '
            "DUP ACE.DESC @ . ACE.STATE @ . "
            "_CBUF ACAT-FILE-MAX _CC2 @ ACAT-ENCODE _CS ! _CU ! "
            "_CS @ . _CU @ . "
            "_CTV @ ACAT-NEW _CS ! _CC3 ! _CS @ . "
            "_CBUF _CU @ _CC3 @ ACAT-DECODE . _CC3 @ ACAT-COUNT . "
            "_CBUF _CU @ 1+ _CC3 @ ACAT-DECODE . _CC3 @ ACAT-COUNT . "
            "_CBUF 80 + DUP C@ 1 XOR SWAP C! "
            "_CBUF _CU @ _CC3 @ ACAT-DECODE . _CC3 @ ACAT-COUNT . "
            'S" CATEND" TYPE',
        ]
    )
    # The Desk default is duplicated here deliberately: app-catalog has no
    # Desk dependency, and a built-in caller owns its desired initial flags.
    forth = [
        line.replace(
            "_DESK-BUILTIN-DEFAULT-FLAGS",
            "ACAT-F-ENABLED ACAT-F-PINNED OR ACAT-F-AUTOSTART OR "
            "ACAT-F-BUILTIN OR",
        )
        for line in forth
    ]
    chunked: list[str] = []
    for line in forth:
        chunked.extend(_chunk_line(line))
    output = vrepl_test.run_forth(chunked, max_steps=600_000_000)
    results = output
    for command in chunked + ["BYE"]:
        results = results.replace(command + "\r\n", "")
        results = results.replace(command + "\n", "")
    start = results.rfind("CATRESULT")
    end = results.find("CATEND", start)
    if start < 0 or end < 0:
        print("FAIL: result markers missing")
        print(output[-8000:])
        return 1
    actual = " ".join(
        token
        for token in results[start + len("CATRESULT") : end].split()
        if token not in ("ok", ">")
    )
    expected = (
        "0 1 0 1 23 "
        "0 2 0 Package two 35 "
        "14 Package two 3 Package two -1 0 3 0 -1 0 0 1 2 "
        "0 0 2 0 0 0 1 "
        "0 992 0 0 2 2 2 2 2"
    )
    if actual != expected:
        print("FAIL: catalog result mismatch")
        print(f"expected: {expected}")
        print(f"actual:   {actual}")
        print(output[-8000:])
        return 1
    diagnostics = ("? (not found)", "Stack underflow", "Branch offset overflow")
    if any(item in output for item in diagnostics):
        print("FAIL: Forth diagnostics present")
        print(output[-8000:])
        return 1
    print("PASS: app catalog codec, persistence, upsert, and resolver")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
