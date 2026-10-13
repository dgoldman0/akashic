#!/usr/bin/env python3
"""utils/fs/link-path.f: the path a document's link names.

LPATH-RESOLVE is compared with a model of the rule on random targets and
bases at buffer sizes from none to LPATH-BOUND: the target without its
fragment and query, refused when it begins with an RFC 3986 scheme, taken
from the base's folder unless it starts with "/", its steps resolved,
absolute or relative as the target and base are, and never longer than the
caller's buffer.
"""

from __future__ import annotations

import random
import re

from forth_dependencies import dependency_order
from test_uidl_collection_snapshot import AK, KDOS_PATH, _load_forth_lines
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime

OK, EMPTY, SCHEME, ROOM = 0, 1, 2, 3
SCHEME_RE = re.compile(rb"[A-Za-z][A-Za-z0-9+.-]*:")


def model(target: bytes, base: bytes, cap: int) -> tuple[bytes, int]:
    for mark in (b"#", b"?"):
        target = target.split(mark)[0]
    if not target:
        return b"", EMPTY
    if SCHEME_RE.match(target):
        return b"", SCHEME
    absolute = target.startswith(b"/") or not base or base.startswith(b"/")
    steps: list[bytes] = []
    ups = 0

    def length() -> int:
        return sum(len(step) for step in steps) + len(steps) - (0 if absolute else 1)

    def put(step: bytes) -> bool:
        if (length() if steps else 0) + len(step) + (1 if absolute or steps else 0) > cap:
            return False
        steps.append(step)
        return True

    def walk(path: bytes) -> bool:
        nonlocal ups
        for step in path.split(b"/"):
            if step in (b"", b"."):
                continue
            if step == b"..":
                if len(steps) > ups:
                    steps.pop()
                elif not absolute:
                    if not put(step):
                        return False
                    ups += 1
                continue
            if not put(step):
                return False
        return True

    if not target.startswith(b"/"):
        folder = base[: base.rfind(b"/")] if b"/" in base else b""
        if not walk(folder):
            return b"", ROOM
    if not walk(target):
        return b"", ROOM
    if not steps:
        return ((b"/" if absolute else b"."), OK) if cap >= 1 else (b"", ROOM)
    if absolute:
        return b"".join(b"/" + step for step in steps), OK
    return b"/".join(steps), OK


PIECES = (b"a", b"bb", b".", b"..", b"", b"x.md", b"notes", "é".encode(), b"%20",
          b"a:b", b"c d")
PREFIXES = (b"", b"/", b"./", b"../", b"https:", b"mailto:", b"C:", b"a+b-c.d:",
            b"1a:", b"a b:", b"#", b"?")
SUFFIXES = (b"", b"#top", b"?q=1", b"#a?b", b"?a#b", b"/")
BASES = (b"", b"/", b"/doc.md", b"/dir/doc.md", b"dir/doc.md", b"/a/b/c/",
         b"/a/../b/./doc.md", b"/deep/er/still/doc.md", b"doc.md", b"../up/doc.md",
         b"./x/doc.md", b"a/../../b/doc.md")


def _cases(seed: int, count: int) -> list[tuple[bytes, bytes, int]]:
    rng = random.Random(seed)
    cases = []
    for _ in range(count):
        target = rng.choice(PREFIXES) + b"/".join(
            rng.choice(PIECES) for _ in range(rng.randrange(0, 5))) + rng.choice(SUFFIXES)
        base = rng.choice(BASES)
        bound = len(target) + len(base) + 1
        cap = rng.choice((bound, bound, rng.randrange(0, bound + 1), 0, 1))
        cases.append((target, base, cap))
    return cases


def _forth_string(name: str, data: bytes) -> list[str]:
    lines = [f"CREATE {name} {len(data)} ,"]
    if data:
        lines.append(" ".join(f"{byte} C," for byte in data))
    return lines


def test_paths_are_the_rules_paths() -> None:
    cases = _cases(5, 1200)
    runtime = MegaForthRuntime(
        memory=create_one_core_address_space(external_size=64 << 20, hbw_size=1 << 20),
        execution_backend="native",
    )
    runtime.evaluate(KDOS_PATH.read_bytes(), source_name="kdos.f")
    runtime.evaluate(b"ENTER-USERLAND", source_name="link-path-userland")
    source = []
    for module in dependency_order(AK, ("utils/fs/link-path.f",)):
        source.extend(_load_forth_lines(AK / module))
    runtime.evaluate(("\n".join(source) + "\n").encode(), source_name="link-path-closure",
                     step_budget=200_000_000)
    lines = [
        "CREATE LP-OUT 4096 ALLOT",
        ": LP-NIB  ( n -- )  DUP 10 < IF 48 + ELSE 87 + THEN EMIT ;",
        ": LP-HEX  ( a u -- )",
        "    0 ?DO DUP I + C@ DUP 4 RSHIFT LP-NIB 15 AND LP-NIB LOOP DROP ;",
        ": LP-STR  ( name -- a u )  DUP CELL+ SWAP @ ;",
        ": LP-TRY  ( target base cap -- )",
        "    >R >R LP-STR R> LP-STR LP-OUT R> LPATH-RESOLVE",
        '    ." R " DUP . OVER . DROP LP-OUT SWAP LP-HEX CR ;',
    ]
    for index, (target, base, cap) in enumerate(cases):
        lines += _forth_string(f"LT{index}", target) + _forth_string(f"LB{index}", base)
        lines.append(f"LT{index} LB{index} {cap} LP-TRY")
    lines.append('DEPTH ." @D:" . CR')
    runtime.evaluate(("\n".join(lines) + "\n").encode(),
                     source_name="link-path-proof", step_budget=500_000_000)
    output = runtime.drain_uart_output().decode("utf-8", errors="replace")
    assert "@D:0 " in output, output[-2000:]
    results = re.findall(r"R (\d+) (\d+) ([0-9a-f]*)", output)
    assert len(results) == len(cases), output[-2000:]
    for (target, base, cap), (status, length, data) in zip(cases, results):
        path = bytes.fromhex(data) if data else b""
        assert int(length) == len(path)
        got = (path, int(status))
        assert got == model(target, base, cap), (target, base, cap)
    statuses = {int(status) for status, _, _ in results}
    assert statuses == {OK, EMPTY, SCHEME, ROOM}
