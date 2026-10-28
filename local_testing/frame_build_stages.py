#!/usr/bin/env python3
"""Where a changed frame's guest steps go, stage by stage.

This reads a physical run made with --screen-profile and with every call
chain kept (MEGAPAD_PROFILE_CHAINS=0 MEGAPAD_PROFILE_CHAIN_DEPTH=0): a typing
cadence artifact (local_testing/physical_typing_cadence.py) or a Desk run's
evidence (local_testing/physical_desktop_acceptance.py). Each stage counts
the steps of every call chain that passes through any of its words, so a
word nested inside another word of the same stage is not counted twice.

A typing run is reported for the isolated character and per frame of the
burst, as in docs/rich-terminal/KEYSTROKE-FRAME-WORK.md. A Desk run is
reported per interaction, from one input to the next: the profile charges
steps in tenths of a second, and the record that holds a frame's build can
end after the frame's PRESENT, so a window that stops at the PRESENT can miss
the build. --summary prints instead, for a Desk run, the mean of each stage
over the interactions that sent only DELTAs and over those that sent a
START, and for any run the whole run's split between the frame build,
Desk's painting and the CELL flush. The split counts the whole run,
start-up included.

Usage: frame_build_stages.py EVIDENCE [--summary] [--json PATH]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

from screen_change_profile import Window, load_jsonl, typing_windows

# Each stage: its label and the words, or a pattern, whose chains it counts.
# Indented labels lie inside the stage above them.
STAGES: list[tuple[str, list[str] | re.Pattern]] = [
    ("rich producer (RTHP-PREPARE, RTHP-STEP)", ["RTHP-PREPARE", "RTHP-STEP"]),
    ("frame build (_RTHP-PREPARE-LIVE)", ["_RTHP-PREPARE-LIVE"]),
    ("  documents' snapshot (RUHA-SNAPSHOT-FOR@)", ["RUHA-SNAPSHOT-FOR@"]),
    ("  producer candidate (_RTHP-BUILD-OBSERVED-CANDIDATE)",
     ["_RTHP-BUILD-OBSERVED-CANDIDATE"]),
    ("    engine admission (RTE-HYBRID-PREFLIGHT)", ["RTE-HYBRID-PREFLIGHT"]),
    ("    producer glyphs (_RTHP-BUILD-GLYPHS?)", ["_RTHP-BUILD-GLYPHS?"]),
    ("    producer rows for the shell (_RTHP-SHELL-RESIDUE?)",
     ["_RTHP-SHELL-RESIDUE?"]),
    ("  target pack (_RTHP-TARGET-CANDIDATE?)", ["_RTHP-TARGET-CANDIDATE?"]),
    ("  comparison (_RTHP-DELTA-CANDIDATE?)", ["_RTHP-DELTA-CANDIDATE?"]),
    ("  shell batch (_RSHSP-BUILD-BATCH)", ["_RSHSP-BUILD-BATCH"]),
    ("    shell preflight (RTE-FAMILY-BATCH-PREFLIGHT)",
     ["RTE-FAMILY-BATCH-PREFLIGHT"]),
    ("    shell glyphs (_RSHSP-GLYPHS)", ["_RSHSP-GLYPHS"]),
    ("  shell freeze (_RSHSP-FREEZE)", ["_RSHSP-FREEZE"]),
    ("  shell emission (_RSHSP-DELTA-EMIT)", ["_RSHSP-DELTA-EMIT"]),
    ("  shell START emission (RTE-FAMILY-BATCH-EMIT)", ["RTE-FAMILY-BATCH-EMIT"]),
    ("  shell checks at each dispatch (_RSHSP-HEADER?, _RSHSP-AUTHORITY?)",
     ["_RSHSP-HEADER?", "_RSHSP-AUTHORITY?"]),
    ("  shell model compares (_RSHSP-CURRENT?, _RSHSP-DELTA-PROBE)",
     ["_RSHSP-CURRENT?", "_RSHSP-DELTA-PROBE"]),
    ("adapter checks (RUHA-VALID?, _RUHA-SAFE-PROVE?)",
     ["RUHA-VALID?", "_RUHA-SAFE-PROVE?"]),
    ("storage-aliasing checks (*STORAGE-DISJOINT?)",
     re.compile(r"STORAGE-DISJOINT\?$")),
    ("Desk's painting (DESK-PAINT-CB)", ["DESK-PAINT-CB"]),
]

FRAME_BUILD = "frame build (_RTHP-PREPARE-LIVE)"


def _hit(words: list[str], match: list[str] | re.Pattern) -> bool:
    if isinstance(match, list):
        return any(word in words for word in match)
    return any(match.search(word) for word in words)


def stage_steps(records: list[dict]) -> tuple[int, int, Counter]:
    """All steps of RECORDS, the steps their chains cover, and each stage's."""

    totals: Counter[str] = Counter()
    steps = chained = 0
    for record in records:
        steps += record["steps"]
        for chain, count in (record.get("chains") or {}).items():
            chained += count
            words = chain.split(" < ")
            for label, match in STAGES:
                if _hit(words, match):
                    totals[label] += count
    return steps, chained, totals


def _inside(span: Window, t_ns: int) -> bool:
    return span.start_ns < t_ns <= span.end_ns


def window_row(span: Window, records: list[dict], presents: list[dict],
               frames: int = 1) -> dict:
    """The stages of SPAN, divided by FRAMES."""

    steps, chained, totals = stage_steps([r for r in records if _inside(span, r["t_ns"])])
    shown = [p for p in presents if _inside(span, p["t_ns"])]
    return {
        "window": span.label,
        "seconds": round((span.end_ns - span.start_ns) / 1e9, 3),
        "frames": frames,
        "steps_per_frame": steps / frames,
        "chain_coverage": chained / steps if steps else 1.0,
        "presents": dict(Counter(p["retained_mode"] for p in shown)),
        "bytes": sum(p["bytes"] for p in shown),
        "stages": {label: totals[label] / frames for label, _ in STAGES},
    }


def typing_rows(evidence: Path, records: list[dict], presents: list[dict]) -> list[dict]:
    rows = []
    for span in typing_windows(load_jsonl(evidence / "typing-trace.jsonl")):
        frames = max(1, sum(1 for p in presents if _inside(span, p["t_ns"])
                            and p["retained_mode"] != "NONE"))
        rows.append(window_row(span, records, presents, frames))
    return rows


def desk_rows(evidence: Path, records: list[dict], presents: list[dict]) -> list[dict]:
    trace = json.loads((evidence / "performance-trace.json").read_text())
    origin = trace["origin_ns"]
    events = trace["events"]
    inputs = [event for event in events if event["event"] == "input_result"]
    rows = []
    for index, event in enumerate(inputs):
        start = origin + event["elapsed_ns"]
        following = inputs[index + 1] if index + 1 < len(inputs) else events[-1]
        span = Window(start, origin + following["elapsed_ns"],
                      f"input {index + 1} ({event.get('method')})")
        if any(_inside(span, p["t_ns"]) for p in presents):
            rows.append(window_row(span, records, presents))
    return rows


def whole_run_split(records: list[dict]) -> dict:
    """The whole run's steps: the frame build, Desk's painting and the part of
    it that fills backgrounds, and the CELL flush outside the producer."""

    split = Counter()
    for record in records:
        split["all"] += record["steps"]
        for chain, count in (record.get("chains") or {}).items():
            words = chain.split(" < ")
            if "_RTHP-PREPARE-LIVE" in words:
                split["frame_build"] += count
            if "DESK-PAINT-CB" in words:
                split["desk_painting"] += count
            if "_UTUI-FILL-BG" in words:
                split["background_fills"] += count
            if "SCR-FLUSH?" in words and "RTHP-PREPARE" not in words:
                split["cell_flush_outside_producer"] += count
    return dict(split)


def summary(rows: list[dict]) -> dict:
    """Each stage's mean over the interactions that sent only DELTAs, and
    over those that sent a START."""

    kinds: dict[str, list[dict]] = {}
    for row in rows:
        modes = row["presents"]
        kind = "START" if modes.get("REPLACE_START") else "DELTA" if modes.get("DELTA") else None
        if kind:
            kinds.setdefault(kind, []).append(row)
    return {
        kind: {
            "interactions": len(chosen),
            "stages": {label: sum(r["stages"][label] for r in chosen) / len(chosen)
                       for label, _ in STAGES},
        }
        for kind, chosen in kinds.items()
    }


def _text_row(row: dict) -> str:
    lines = [f"{row['window']}: {row['seconds']} s, {row['frames']} frame(s), "
             f"{row['steps_per_frame'] / 1e6:.2f}M steps a frame, presents "
             f"{row['presents']}, {row['bytes']:,} bytes"]
    lines += [f"  {value / 1e6:7.2f}M  {label}" for label, value in row["stages"].items()]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("evidence", type=Path,
                        help="a run's evidence directory, or the artifact holding it")
    parser.add_argument("--summary", action="store_true")
    parser.add_argument("--json", type=Path)
    args = parser.parse_args(argv)
    evidence = args.evidence
    if (evidence / "evidence").is_dir():
        evidence = evidence / "evidence"
    profile = evidence / "screen-profile"
    if not profile.is_dir():
        parser.error(f"{evidence} has no screen-profile; run with --screen-profile")
    records = load_jsonl(profile / "guest-words.jsonl")
    presents = load_jsonl(profile / "presents.jsonl")
    typing = (evidence / "typing-trace.jsonl").is_file()
    rows = (typing_rows if typing else desk_rows)(evidence, records, presents)
    coverage = min((row["chain_coverage"] for row in rows), default=1.0)
    if coverage < 0.999:
        print("warning: call chains cover only part of the steps; "
              "run with MEGAPAD_PROFILE_CHAINS=0 MEGAPAD_PROFILE_CHAIN_DEPTH=0",
              file=sys.stderr)
    if args.summary:
        result = {"split": whole_run_split(records),
                  "kinds": {} if typing else summary(rows)}
        if typing:
            result["windows"] = rows
        lines = [f"whole run: " + ", ".join(f"{k} {v / 1e6:.1f}M"
                                            for k, v in result["split"].items())]
        for kind, value in result["kinds"].items():
            lines.append(f"{kind}, {value['interactions']} interactions, mean:")
            lines += [f"  {v / 1e6:7.2f}M  {label}" for label, v in value["stages"].items()]
        for row in result.get("windows", []):
            lines.append(_text_row(row))
        print("\n".join(lines))
    else:
        result = rows
        print("\n\n".join(_text_row(row) for row in rows))
    if args.json is not None:
        args.json.write_text(json.dumps(result, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
