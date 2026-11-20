"""Measure the checker on Akashic's Forth.

Run from the Akashic checkout::

    python3 -m toolchain.language.measure --json report.json

The run loads MegaPad's BIOS dictionary, KDOS and the system modules as the
base vocabulary, then every library file under ``akashic/`` in sorted order,
following each REQUIRE where it appears, then the Forth test drivers and
examples.  It reports how many colon definitions have an inferred effect,
how those compare with their stack comments, why the rest could not be
inferred, and what the kind, span and return-stack checks found.
"""

from __future__ import annotations

import argparse
import collections
import json
import os
import subprocess
import sys
import time
from pathlib import Path

from .checker import Checker, Record
from .effects import Effect

BASE_MODULES = ("kdos.f", "networking.f", "rich-terminal.f", "tools.f", "graphics.f")
PROPAGATED = "calls a word whose effect is unknown"


def tracked_forth(root: Path, pattern: str) -> list[str]:
    listed = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z", "--", pattern],
        check=True, capture_output=True,
    ).stdout.decode("utf-8")
    return sorted(name for name in listed.split("\0") if name.endswith(".f"))


def _normalizer(root: Path):
    """KDOS's REQUIRE path rule, from the dependency tool the harness uses."""
    sys.path.insert(0, str(root / "local_testing"))
    try:
        from forth_dependencies import normalize_module  # type: ignore
    finally:
        sys.path.pop(0)
    return normalize_module


def build(root: Path, megapad: Path, defines: list[str], groups: list[str]) -> Checker:
    checker = Checker()
    checker.load_bios(megapad)
    checker.load_base(megapad, BASE_MODULES)
    normalize = _normalizer(root)
    loaded: set[str] = set()
    missing: list[tuple[str, str]] = []

    def load(module: str) -> None:
        if module in loaded:
            return
        loaded.add(module)
        path = root / module
        if not path.is_file():
            missing.append((module, checker.module))
            return
        checker.load_text(path.read_text(encoding="utf-8", errors="replace"), module)

    def require(name: str, requiring: str) -> None:
        try:
            module = normalize(name, requiring)
        except ValueError:
            missing.append((name, requiring))
            return
        load(module)

    checker.require = require
    checker.missing = missing  # type: ignore[attr-defined]
    for text in defines:
        checker.load_text(text, "(defines)")
    patterns = {
        "library": ["akashic/*.f"],
        "tests": ["local_testing/*.f", "examples/*.f"],
    }
    for group in groups:
        checker.group = group
        for pattern in patterns[group]:
            for module in tracked_forth(root, pattern):
                load(module)
    return checker


def effect_text(effect: Effect | None) -> str:
    if effect is None:
        return "-"
    if effect.variable:
        return "( variable )"

    def names(slots):
        out = []
        for slot in slots:
            if slot.passthrough is not None:
                out.append(f"in{slot.passthrough}")
            elif slot.const is not None:
                out.append(str(slot.const))
            else:
                out.append(slot.kind)
        return " ".join(out)

    ins = names(effect.inputs)
    alts = " | ".join(names(alt) for alt in effect.alts) if effect.alts else "never returns"
    return f"( {ins} -- {alts} )".replace("(  --", "( --").replace("--  )", "-- )")


def summarize(checker: Checker, group: str, examples: int) -> dict:
    records = [r for r in checker.records if r.group == group]
    total = len(records)
    inferred = [r for r in records if r.status == "inferred"]
    failed = [r for r in records if r.status == "failed"]
    comparison = collections.Counter(r.comparison for r in inferred)
    declared_only = collections.Counter(
        r.comparison for r in records if r.status == "failed"
    )
    direct = collections.Counter()
    roots = collections.Counter()
    category_examples: dict[str, list] = collections.defaultdict(list)
    root_examples: dict[str, list] = collections.defaultdict(list)
    for record in failed:
        failure = record.failure
        assert failure is not None
        if failure.category == PROPAGATED:
            roots[failure.root[0]] += 1
            if len(root_examples[failure.root[0]]) < examples:
                root_examples[failure.root[0]].append(_where(record, failure.line, failure.detail))
        else:
            direct[failure.category] += 1
            if len(category_examples[failure.category]) < examples:
                category_examples[failure.category].append(
                    _where(record, failure.line, failure.detail))
    detail_counts: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    for record in failed:
        failure = record.failure
        if failure.category in ("undefined word", "BIOS word without a documented effect",
                                "computed PICK or ROLL depth", "EXECUTE of an unknown xt",
                                "CATCH of an unknown xt", "calls a word with a variable effect",
                                "deferred word without a declared effect"):
            detail_counts[failure.category][failure.detail.split(" (through")[0]] += 1
    mismatches = [r for r in inferred if r.comparison == "mismatch"]
    mismatch_examples = [
        {
            **_where(r, r.word.line, ""),
            "comment": f"( {r.word.declared_text} )",
            "inferred": effect_text(r.word.inferred),
        }
        for r in mismatches[: examples * 4]
    ]
    findings = collections.Counter()
    finding_examples: dict[str, list] = collections.defaultdict(list)
    for record in records:
        for finding in record.findings:
            key = finding.category
            if finding.category in ("kind", "managed rule", "return stack", "span"):
                key = f"{finding.category}: {finding.detail.split(':')[0]}"
                if finding.category == "return stack":
                    key = f"return stack: {finding.detail}"
            findings[key] += 1
            if len(finding_examples[key]) < examples:
                finding_examples[key].append({
                    "module": finding.module, "line": finding.line,
                    "word": finding.word, "detail": finding.detail,
                })
    relying = sum(1 for r in inferred if r.relies_on_declared)
    self_named = [r for r in records if r.hides_older]
    commented = sum(1 for r in records if r.word.declared is not None)
    preceding = sum(1 for r in records
                    if r.word.declared_reason == "comment on a preceding line")
    return {
        "definitions": total,
        "inferred": len(inferred),
        "failed": len(failed),
        "with a stack comment": commented,
        "comment on a preceding line": preceding,
        "comparison of inferred effects": dict(comparison.most_common()),
        "comments of failed definitions": dict(declared_only.most_common()),
        "inferred relying on a comment-only callee": relying,
        "failure categories": dict(direct.most_common()),
        "failure examples": category_examples,
        "propagated failures by root cause": dict(roots.most_common()),
        "propagated examples": root_examples,
        "failure details": {k: dict(v.most_common(15)) for k, v in detail_counts.items()},
        "mismatch examples": mismatch_examples,
        "findings": dict(findings.most_common()),
        "finding examples": finding_examples,
        "redefinitions that call their own name": [
            _where(r, r.word.line, f"hides {r.word.hides.module}:{r.word.hides.line}")
            for r in self_named[:examples * 4]
        ],
        "redefinitions that call their own name (count)": len(self_named),
    }


def sample(checker: Checker, root: Path, group: str, category: str, count: int,
           seed: int) -> str:
    """A fixed random sample of one category's definitions, with their source.

    The category is a comparison ("mismatch"), a failure category, or a
    finding category such as "kind" or "span".
    """
    import random

    chosen = []
    for record in checker.records:
        if record.group != group:
            continue
        failure = record.failure.category if record.failure else None
        kinds = {f.category for f in record.findings}
        if category in (record.comparison, failure) or category in kinds:
            chosen.append(record)
    picked = random.Random(seed).sample(chosen, min(count, len(chosen)))
    out = [f"{category}: {len(chosen)} definitions, {len(picked)} sampled (seed {seed})"]
    for record in sorted(picked, key=lambda r: (r.word.module, r.word.line)):
        word = record.word
        lines = (root / word.module).read_text(encoding="utf-8").split("\n")
        verdict = f"{record.status}, {record.comparison}"
        if record.failure:
            verdict += f"; {record.failure.category}: {record.failure.detail} (line {record.failure.line})"
        out.append(f"\n--- {word.module}:{word.line} {word.name}: {verdict}")
        out.append(f"    inferred {effect_text(word.inferred)}")
        for finding in record.findings:
            out.append(f"    finding at {finding.line}: {finding.category}: {finding.detail}")
        for number in range(word.line, (word.end_line or word.line) + 1):
            out.append(f"{number:6} {lines[number - 1]}")
    return "\n".join(out)


def _where(record: Record, line: int | None, detail: str) -> dict:
    return {"module": record.word.module, "line": line or record.word.line,
            "word": record.word.name, "detail": detail}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    here = Path(__file__).resolve().parents[2]
    configured = os.environ.get("MEGAPAD_ROOT")
    parser.add_argument("--akashic", type=Path, default=here)
    parser.add_argument("--megapad", type=Path,
                        default=Path(configured) if configured else here.parent / "megapad",
                        help="MegaPad checkout (default: MEGAPAD_ROOT, else beside Akashic)")
    parser.add_argument("--json", type=Path)
    parser.add_argument("--examples", type=int, default=6)
    parser.add_argument("--guarded", action="store_true",
                        help="define GUARDED as the test profiles do")
    parser.add_argument("--groups", default="library,tests")
    parser.add_argument("--sample", metavar="CATEGORY",
                        help="print a random sample of one category's definitions")
    parser.add_argument("--count", type=int, default=20)
    parser.add_argument("--seed", type=int, default=20261120)
    args = parser.parse_args(argv)
    defines = ["-1 CONSTANT GUARDED"] if args.guarded else []
    started = time.monotonic()
    groups = args.groups.split(",")
    checker = build(args.akashic, args.megapad, defines, groups)
    elapsed = time.monotonic() - started
    if args.sample:
        print(sample(checker, args.akashic, groups[0], args.sample, args.count, args.seed))
        return 0
    report = {
        "seconds": round(elapsed, 1),
        "guarded": args.guarded,
        "unknown [IF] conditions": checker.unknown_conditions,
        "missing modules": [list(m) for m in checker.missing[:20]],
        "undefined at top level": dict(collections.Counter(checker.top_undefined).most_common(20)),
        "base": summarize(checker, "base", args.examples),
    }
    for group in groups:
        report[group] = summarize(checker, group, args.examples)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, indent=1, default=str))
    for group in groups:
        part = report[group]
        print(f"{group}: {part['definitions']} definitions, {part['inferred']} inferred "
              f"({100 * part['inferred'] / max(part['definitions'], 1):.1f}%), "
              f"{part['failed']} not inferred")
        print("  comparison:", part["comparison of inferred effects"])
        print("  failures:", part["failure categories"])
        print("  propagated roots:", part["propagated failures by root cause"])
        print("  findings:", part["findings"])
    print(f"{elapsed:.1f} s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
