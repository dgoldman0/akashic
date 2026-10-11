#!/usr/bin/env python3
"""What a screen change sent and which guest words its steps ran under.

A physical run with --screen-profile leaves, beside its performance trace,
a screen-profile directory holding the simulator's records: each PRESENT the
guest sent (presents.jsonl) and, for each tenth of a second, the guest steps
charged to each word (guest-words.jsonl). Every record carries the host's
monotonic clock, as the trace does, so the two line up.

This reads one run and reports a window of it: from one input until the
next input, until the first picture the display holds after it, or until
the run ends. For the window it lists each PRESENT, with the guest steps run
since the one before, and the words the steps ran under, each counted with
everything it calls.

Usage: screen_change_profile.py EVIDENCE [--input METHOD] [--nth N]
                                [--until next-input|resources|end]
                                [--words N] [--json PATH]
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Window:
    start_ns: int
    end_ns: int
    label: str


def load_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def window(trace: dict, *, method: str | None, nth: int | None, until: str) -> Window:
    """The window from the chosen input to the chosen end, in trace time."""

    origin = trace["origin_ns"]
    events = trace["events"]
    inputs = [
        (index, event) for index, event in enumerate(events)
        if event["event"] == "input_result"
        and (method is None or event.get("method") == method)
    ]
    if not inputs:
        raise ValueError(f"the trace has no {method or 'input'} to start from")
    if nth is None:
        position, first = inputs[-1]
    else:
        if not 1 <= nth <= len(inputs):
            raise ValueError(f"the trace has {len(inputs)} such inputs, not {nth}")
        position, first = inputs[nth - 1]
    later = events[position + 1:]
    wanted = {
        "next-input": ("input_result",),
        "resources": ("display_resources_ready",),
        "end": ("acceptance_finished",),
    }[until]
    end = next((event for event in later if event["event"] in wanted), None)
    if end is None:
        end = next(
            (event for event in later if event["event"] == "acceptance_finished"),
            events[-1],
        )
    label = f"{first.get('method')} at {first['elapsed_ns'] / 1e9:.2f} s until {end['event']}"
    return Window(origin + first["elapsed_ns"], origin + end["elapsed_ns"], label)


def summarize(presents: list[dict], intervals: list[dict], span: Window) -> dict:
    """The PRESENTs and guest words of SPAN.  An interval of guest words
    belongs to the window when it ends inside it."""

    def inside(t_ns: int) -> bool:
        return span.start_ns < t_ns <= span.end_ns

    chosen = [interval for interval in intervals if inside(interval["t_ns"])]
    inclusive: Counter[str] = Counter()
    leaf: Counter[str] = Counter()
    for interval in chosen:
        inclusive.update(interval["inclusive"])
        leaf.update(interval["leaf"])
    steps = sum(interval["steps"] for interval in chosen)
    rows = []
    previous = span.start_ns
    for present in presents:
        if not inside(present["t_ns"]):
            continue
        before = sum(
            interval["steps"] for interval in chosen
            if previous < interval["t_ns"] <= present["t_ns"]
        )
        rows.append({
            "after_s": round((present["t_ns"] - span.start_ns) / 1e9, 3),
            "cell_mode": present["cell_mode"],
            "cell_spans": present["cell_spans"],
            "cells": present["cells"],
            "retained_mode": present["retained_mode"],
            "retained_operations": present["retained_operations"],
            "bytes": present["bytes"],
            "steps_before": before,
        })
        previous = present["t_ns"]
    return {
        "window": span.label,
        "seconds": round((span.end_ns - span.start_ns) / 1e9, 3),
        "steps": steps,
        "presents": rows,
        "inclusive": dict(inclusive.most_common()),
        "leaf": dict(leaf.most_common()),
    }


def report(summary: dict, words: int) -> str:
    steps = summary["steps"] or 1
    lines = [
        f"Window: {summary['window']}, {summary['seconds']:.2f} s, "
        f"{summary['steps']:,} guest steps",
        "",
        "  After  CELL                         Retained                      Bytes   Steps before",
    ]
    for row in summary["presents"]:
        cell = f"{row['cell_mode']} {row['cells']:,} cells/{row['cell_spans']} spans"
        retained = f"{row['retained_mode']} {row['retained_operations']} ops"
        lines.append(
            f"{row['after_s']:6.2f}s  {cell:<28} {retained:<28} "
            f"{row['bytes']:>7,} {row['steps_before']:>14,}"
        )
    lines += ["", "Words, each with everything it calls:"]
    for name, count in list(summary["inclusive"].items())[:words]:
        lines.append(f"{count:>14,} {100 * count / steps:5.1f}%  {name}")
    lines += ["", "Words the guest stopped in:"]
    for name, count in list(summary["leaf"].items())[:words]:
        lines.append(f"{count:>14,} {100 * count / steps:5.1f}%  {name}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("evidence", type=Path,
                        help="a run's evidence directory, or the artifact holding it")
    parser.add_argument("--input", dest="method",
                        help="start at an input of this method (default: any input)")
    parser.add_argument("--nth", type=int,
                        help="start at the Nth such input, counting from 1 "
                             "(default: the last)")
    parser.add_argument("--until", choices=("next-input", "resources", "end"),
                        default="next-input")
    parser.add_argument("--words", type=int, default=40)
    parser.add_argument("--json", type=Path)
    args = parser.parse_args(argv)
    evidence = args.evidence
    if (evidence / "evidence").is_dir():
        evidence = evidence / "evidence"
    profile = evidence / "screen-profile"
    if not profile.is_dir():
        parser.error(f"{evidence} has no screen-profile; run with --screen-profile")
    trace = json.loads((evidence / "performance-trace.json").read_text())
    span = window(trace, method=args.method, nth=args.nth, until=args.until)
    summary = summarize(
        load_jsonl(profile / "presents.jsonl"),
        load_jsonl(profile / "guest-words.jsonl"),
        span,
    )
    print(report(summary, args.words))
    if args.json is not None:
        args.json.write_text(json.dumps(summary, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
