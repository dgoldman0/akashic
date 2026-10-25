#!/usr/bin/env python3
"""What a typed letter's frame build spends on checks, by what each check is for.

This reads a typing cadence run made with --screen-profile and with every
call chain kept (MEGAPAD_PROFILE_CHAINS=0 MEGAPAD_PROFILE_CHAIN_DEPTH=0), as
local_testing/physical_typing_cadence.py writes it. It reports the isolated
first character and, per frame, the burst, as frame_build_stages.py does.

Every call chain under the frame build (_RTHP-PREPARE-LIVE) is charged to the
outermost check word it passes through, and that word's group:

- repeat: a check of data that nothing has written since it was last checked,
  such as a stored snapshot slice before reuse, menus copied from the
  acknowledged bank, the frozen bank, the engine's audit of its own state,
  or a proof the same frame already made;
- handover: a proof about memory layout or a header, which can change only
  when memory is handed over or grows;
- items: the checks of the items a frame sends, at capture or admission;
- state: whether a draw, an owner or an acknowledgement is still current.

Wrappers that mix checks with real work are not check words, so the checks
inside them are found instead. The backend's capacity and feature preflights
are reported apart as fit, less the engine audit they call. What no group or
fit claims is the frame build's other work: building, copying and comparing.

The profile charges the steps since each host boundary to the chain the
guest stopped in, so a word that costs less than a few hundredths of a
million steps a frame is not measured reliably.

Usage: frame_checks.py EVIDENCE [--json PATH]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

from screen_change_profile import Window, load_jsonl, typing_windows

ROOT = "_RTHP-PREPARE-LIVE"

REPEAT = {
    # RUHA re-validates another document's stored slices before reusing them.
    "UCSN-FROZEN-VALIDATE", "USFSN-FROZEN-VALIDATE", "UFLSN-FROZEN-VALIDATE",
    "UDLSN-FROZEN-VALIDATE",
    # Menus copied from the producer's acknowledged bank are checked again.
    "_RTHP-W-MENU-REUSE-PREFLIGHT?", "RTE-CONTROL-VALID?", "_RTHP-W-MENU-REUSE-TEXT?",
    # The shell checks its batch, freezes a proved copy and checks the copy,
    # then emission proves the batch's storage again.
    "RTE-FAMILY-BATCH-VALID?", "_RSHSP-BANK-VALID?", "_RSHFC-BATCH-OUTSIDE?",
    "_RTE-FEM-AUTHORITY?", "SHSN-FROZEN-VALIDATE", "_RSHPL-MODEL-OK?",
    "_RTE-RC-POS-SPAN?", "_RTE-RC-SPAN?",
    # The APT-1 engine audits its whole state at each backend call.
    "_RTAPT-ENGINE-VALID?",
    # The residual glyph planner checks every claim and span on each call.
    "_RGRP-CLAIM-VALID?", "_RGRP-RANGE-AUTHORITY?", "_RUCL-VALIDATE-ONE?",
    # The comparison checks the spans of the producer's own packs.
    "_RTHP-D-CONTROL-TEXT-SPANS?", "_RTHP-D-REF-VALID?", "_RTHP-TEXT-WITHIN?",
    # Cached UIDL relations and resolved targets are re-validated in depth.
    "_UTUI-MC-RELATION-VALID?", "_UTUI-RS-TARGET-VALID?", "UTUI-RESOLVED-VALID?",
    "_UTUI-MC-RGN-VALID?", "RTE-STATIC-VALID?",
}
HANDOVER = {
    # Each shell dispatch checks every header and proves its spans apart.
    "_RSHSP-AUTHORITY?", "_RSHSP-HEADER?", "_RSHSP-SPANS?", "_RSHSP-EXTERNAL?",
    "_RSHSP-SPAN?",
    # RUHA proves its banks apart from every document's storage.
    "RUHA-VALID?", "_RUHA-O-SPAN?", "_RUHA-STORAGE-DISJOINT-CURRENT?",
    "_RUHA-SCREEN-STORAGE-DISJOINT?", "_RUHA-SAFE-PROVE?",
    # Captures and admissions prove their caller spans.
    "_UCSN-RANGES?", "_UMSN-RANGES?", "_UFLSN-AUTHORITY?", "_USFSN-AUTHORITY?",
    "_UDLSN-AUTHORITY?", "_UCSN-AUTHORITY-DISJOINT?", "_RTE-FA-AUTHORITY?",
    "_RTE-HPV-FIXED-AUTHORITY?", "_RTE-HPV-ADMISSION-AUTHORITY?",
    "_RTE-CONTENT-SCRATCH-DISJOINT?", "_RTE-SPV-SPAN?", "MSPAN-SET-PROVE-DISJOINT?",
    "_RSHFC-SOURCE?", "RSHFC-STORAGE-DISJOINT?", "_RSHPL-SPANS?",
    # Headers of the producer's banks, the shell snapshot, the engine facade
    # and the screen.
    "_RTHP-TARGET-BANK-HEADER?", "_RTHP-W-DOCUMENT-SHAPE?", "SHSN-VALID?",
    "RTE-VALID?", "RTE-SHELL-VALID?", "_SCR-ACTIVE-STORAGE-VALID?", "MSPAN-SET-VALID?",
}
HANDOVER_PATTERN = re.compile(r"STORAGE-DISJOINT\?$|AUTHORITY-DISJOINT\?$")
ITEMS = {
    # The engine admits the producer's candidate.
    "_RTE-CONTROL-PLAN-VALID-BODY", "_RTE-HPV-SERIES?", "_RTE-HPV-INSTRUMENT?",
    "_RTE-HPV-STATIC?", "_RTE-HPV-GLYPH?", "_RTE-HPV-IDENTITY-RANGES?",
    "_RTE-GLYPH-RUN-TEXT?", "_RTE-STATIC-TEXT?",
    # Captures check what they read from UIDL and the widgets.
    "_UMSN-TEXT?", "_UMSN-V-RESOLVED?", "_UCSN-V-ARGS?", "USCOL-ENTRY-VALIDATE",
    "_USCOL-VALIDATE-TEXT", "_USCOL-VALIDATE-ITEMS", "USF-VALIDATE", "USF-TEXT?",
    "_SHSN-V-TEXT?", "UTF8-VALID?",
}
STATE = {"_RTHP-TG-APPEND-CURRENT?", "_UTUI-SFI-CURRENT?", "_SHSN-LD-CURRENT?"}
FIT = {"RTAPT-HYBRID-PREFLIGHT", "RTAPT-FAMILY-PREFLIGHT"}
GROUPS = ("repeat", "handover", "items", "state")


def group_of(word: str) -> str | None:
    if word in REPEAT:
        return "repeat"
    if word in HANDOVER or HANDOVER_PATTERN.search(word):
        return "handover"
    if word in ITEMS:
        return "items"
    if word in STATE:
        return "state"
    return None


def charge(records: list[dict], span: Window) -> dict:
    """The frame build's steps in SPAN, by group, check word and fit."""

    build = fit = 0
    groups: Counter[str] = Counter()
    words: Counter[tuple[str, str]] = Counter()
    for record in records:
        if not span.start_ns < record["t_ns"] <= span.end_ns:
            continue
        for chain, count in (record.get("chains") or {}).items():
            outward = chain.split(" < ")[::-1]
            if ROOT not in outward:
                continue
            build += count
            below = outward[outward.index(ROOT):]
            claimed = next(((word, group_of(word)) for word in below if group_of(word)), None)
            if claimed:
                words[claimed] += count
                groups[claimed[1]] += count
            elif FIT.intersection(below):
                fit += count
    return {"build": build, "fit": fit, "groups": groups, "words": words}


def typing_rows(evidence: Path) -> list[dict]:
    records = load_jsonl(evidence / "screen-profile" / "guest-words.jsonl")
    presents = load_jsonl(evidence / "screen-profile" / "presents.jsonl")
    rows = []
    for span in typing_windows(load_jsonl(evidence / "typing-trace.jsonl")):
        frames = max(1, sum(1 for p in presents if span.start_ns < p["t_ns"] <= span.end_ns
                            and p["retained_mode"] != "NONE"))
        found = charge(records, span)
        checks = sum(found["groups"].values())
        rows.append({
            "window": span.label,
            "frames": frames,
            "frame_build": found["build"] / frames,
            "checks": checks / frames,
            "groups": {g: found["groups"][g] / frames for g in GROUPS},
            "fit": found["fit"] / frames,
            "other_work": (found["build"] - checks - found["fit"]) / frames,
            "words": [{"group": g, "word": w, "steps": v / frames}
                      for (w, g), v in found["words"].most_common()],
        })
    return rows


def text(row: dict, least: float) -> str:
    million = 1e6
    share = f" ({row['checks'] / row['frame_build']:.0%})" if row["frame_build"] else ""
    lines = [f"{row['window']}: {row['frames']} frame(s), frame build "
             f"{row['frame_build'] / million:.2f}M a frame, checks "
             f"{row['checks'] / million:.2f}M{share}"]
    for group in GROUPS:
        lines.append(f"  {row['groups'][group] / million:6.2f}M  {group}")
        lines += [f"      {item['steps'] / million:5.2f}M  {item['word']}"
                  for item in row["words"]
                  if item["group"] == group and item["steps"] / million >= least]
    lines.append(f"  {row['fit'] / million:6.2f}M  fit (backend preflights less the engine audit)")
    lines.append(f"  {row['other_work'] / million:6.2f}M  other work: building, copying, comparing")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("evidence", type=Path,
                        help="a typing run's artifact directory")
    parser.add_argument("--least", type=float, default=0.01,
                        help="list check words of at least this many million steps a frame")
    parser.add_argument("--json", type=Path)
    args = parser.parse_args(argv)
    evidence = args.evidence
    if not (evidence / "typing-trace.jsonl").is_file():
        parser.error(f"{evidence} is not a typing cadence run")
    if not (evidence / "screen-profile").is_dir():
        parser.error(f"{evidence} has no screen-profile; run with --screen-profile")
    rows = typing_rows(evidence)
    print("\n\n".join(text(row, args.least) for row in rows))
    if args.json is not None:
        args.json.write_text(json.dumps(rows, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
