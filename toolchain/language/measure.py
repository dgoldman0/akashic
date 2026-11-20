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
import re
import subprocess
import sys
import time
from pathlib import Path

from .checker import Checker, Record
from .effects import Effect

BASE_MODULES = ("kdos.f", "networking.f", "rich-terminal.f", "tools.f", "graphics.f")
PROPAGATED = "calls a word whose effect is unknown"

# Comments such as "( eight-values -- )" count cells in words, so they
# cannot match cell for cell however right they are.
_PROSE_RE = re.compile(
    r"(?<![a-z])(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|"
    r"thirteen|fourteen|fifteen|sixteen|twenty|values|arguments|args|same|twice|"
    r"fields|results|cells)(?![a-z])"
)


def mismatch_kind(record: Record) -> str:
    text = (record.word.declared_text or "").lower()
    if _PROSE_RE.search(text):
        return "comment counts cells in words"
    return "other"


def tracked_forth(root: Path, pattern: str) -> list[str]:
    listed = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z", "--", pattern],
        check=True, capture_output=True,
    ).stdout.decode("utf-8")
    return sorted(name for name in listed.split("\0") if name.endswith(".f"))


def _dependency_markers(root: Path):
    """KDOS's REQUIRE rule, from the dependency tool the harness uses."""
    sys.path.insert(0, str(root / "local_testing"))
    try:
        from forth_dependencies import dependency_markers  # type: ignore
    finally:
        sys.path.pop(0)
    return dependency_markers


class Modules:
    """Each module's REQUIRE closure, in the order KDOS would load it.

    KDOS loads a module's REQUIREs where they appear, depth first, and
    loads each module once, so a module's dictionary holds the base
    vocabulary, then its closure in that order, then its own words.
    """

    def __init__(self, root: Path) -> None:
        self.root = root
        self.markers = _dependency_markers(root)
        self.texts: dict[str, str | None] = {}
        self.orders: dict[str, tuple[str, ...]] = {}
        self.missing: list[tuple[str, str]] = []

    def text(self, module: str) -> str | None:
        if module not in self.texts:
            path = self.root / module
            self.texts[module] = (path.read_text(encoding="utf-8", errors="replace")
                                  if path.is_file() else None)
        return self.texts[module]

    def requires(self, module: str) -> list[str]:
        text = self.text(module)
        if text is None:
            return []
        found = []
        try:
            markers = self.markers(text, module)
        except ValueError:
            return []
        for marker in markers:
            if self.text(marker.normalized) is None:
                self.missing.append((marker.normalized, module))
                continue
            found.append(marker.normalized)
        return found

    def order(self, module: str, visiting: frozenset = frozenset()) -> tuple[str, ...]:
        """The modules loaded before ``module``'s own text, in load order."""
        if module in self.orders:
            return self.orders[module]
        result: list[str] = []
        seen: set[str] = set()
        for dependency in self.requires(module):
            if dependency in visiting or dependency == module:
                continue  # a cycle: KDOS's PROVIDED guard stops it
            for item in self.order(dependency, visiting | {module}) + (dependency,):
                if item not in seen and item != module:
                    seen.add(item)
                    result.append(item)
        self.orders[module] = tuple(result)
        return self.orders[module]


def build(root: Path, megapad: Path, defines: list[str], groups: list[str]) -> Checker:
    checker = Checker()
    checker.load_bios(megapad)
    checker.load_base(megapad, BASE_MODULES)
    for text in defines:
        checker.load_text(text, "(defines)")
    base_words = dict(checker.words)
    modules = Modules(root)
    exports: dict[str, dict] = {}

    def load(module: str, group: str) -> None:
        if module in exports:
            return
        exports[module] = {}  # a placeholder that breaks REQUIRE cycles
        order = modules.order(module)
        for dependency in order:
            load(dependency, group)
        visible = dict(base_words)
        for dependency in order:
            visible.update(exports.get(dependency, {}))
        text = modules.text(module)
        defined = checker.begin_module(visible, group_of(module, group))
        if text is not None:
            checker.load_text(text, module)
        exports[module] = defined

    checker.missing = modules.missing  # type: ignore[attr-defined]
    patterns = {
        "library": ["akashic/*.f"],
        "tests": ["local_testing/*.f", "examples/*.f"],
    }
    for group in groups:
        for pattern in patterns[group]:
            for module in tracked_forth(root, pattern):
                load(module, group)
    return checker


def group_of(module: str, requested: str) -> str:
    """Library modules count as library wherever they are first reached."""
    return "library" if module.startswith("akashic/") else requested


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
    mismatch_kinds = collections.Counter(mismatch_kind(r) for r in mismatches)
    mismatch_examples = [
        {
            **_where(r, r.word.line, mismatch_kind(r)),
            "comment": f"( {r.word.declared_text} )",
            "inferred": effect_text(r.word.inferred),
        }
        for r in mismatches if mismatch_kind(r) == "other"
    ][: examples * 4]
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
    grounded = sum(1 for r in inferred if _grounded(r.word, {}))
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
        "mismatches by comment form": dict(mismatch_kinds.most_common()),
        "comments of failed definitions": dict(declared_only.most_common()),
        "inferred relying on a comment-only callee": relying,
        "inferred with no comment-only word anywhere below": grounded,
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
        if category == "mismatch other":
            if record.comparison == "mismatch" and mismatch_kind(record) == "other":
                chosen.append(record)
        elif category in (record.comparison, failure) or category in kinds:
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


def _grounded(word, memo: dict) -> bool:
    """Whether a word's effect rests on inference all the way down.

    Base words count as grounded, since their effects are given; a source
    word counts when it was inferred and every source word it calls is
    grounded in turn.
    """
    key = id(word)
    if key in memo:
        return memo[key]
    if word.origin != "source":
        return True
    if word.kind == "defer":
        return word.signature_source == "inferred"  # bound by IS to an inferred word
    if word.kind != "colon":
        return True  # variables, constants and created words have exact effects
    memo[key] = True  # a word that calls itself does not undo its own grounding
    # A word that runs an xt it is given is inferred at each call site.
    result = word.inferred is not None or word.higher_order
    if result and word.items:
        for op, arg, _ in word.items:
            if op in ("call", "xt") and arg is not word and not _grounded(arg, memo):
                result = False
                break
    memo[key] = result
    return result


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
