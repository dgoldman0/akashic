#!/usr/bin/env python3
"""frame_checks.py charges a typed letter's frame build to its checks."""

from __future__ import annotations

import json

import frame_checks as checks

ROOT = "_SIMULATOR-SESSION-ROOT"
BUILD = ("SCR-FLUSH?", "RTHP-PREPARE", "_RTHP-PREPARE-LIVE")


def _chain(*words: str) -> str:
    """A chain as the profile writes it: innermost word first."""

    return " < ".join(reversed((ROOT,) + words))


def _interval(t_ns: int, chains: dict[str, int]) -> dict:
    return {"t_ns": t_ns, "steps": sum(chains.values()), "inclusive": {}, "leaf": {},
            "chains": chains}


def _present(t_ns: int, mode: str) -> dict:
    return {"t_ns": t_ns, "retained_mode": mode, "bytes": 10, "cell_mode": "NONE",
            "cell_spans": 0, "cells": 0, "retained_operations": 1}


def _typing_trace() -> list[dict]:
    rows = [{"event": "trace_origin", "origin_ns": 1_000_000, "time_ns": 0}]
    for index, at in enumerate((100, 1_000, 1_200)):
        rows.append({"event": "character_dispatched", "index": index, "time_ns": at})
    rows += [{"event": "typing_visible", "count": 1, "time_ns": 400},
             {"event": "typing_visible", "count": 3, "time_ns": 1_900}]
    return rows


def _write_run(tmp_path, records: list[dict], presents: list[dict]) -> None:
    (tmp_path / "screen-profile").mkdir()
    (tmp_path / "typing-trace.jsonl").write_text(
        "".join(json.dumps(row) + "\n" for row in _typing_trace()))
    (tmp_path / "screen-profile" / "presents.jsonl").write_text(
        "".join(json.dumps(p) + "\n" for p in presents))
    (tmp_path / "screen-profile" / "guest-words.jsonl").write_text(
        "".join(json.dumps(r) + "\n" for r in records))


def test_a_chain_goes_to_its_outermost_check_and_wrappers_are_looked_through(tmp_path) -> None:
    burst = 1_001_500
    records = [_interval(burst, {
        # A stored slice's re-validation reads its items: the outer repeat wins.
        _chain(*BUILD, "RUHA-SNAPSHOT-FOR@", "_RUHA-B-PRIOR-ENTRY?",
               "UCSN-FROZEN-VALIDATE", "USCOL-ENTRY-VALIDATE"): 30,
        # A currency check that dispatches to the shell is a wrapper, so the
        # dispatch's header and span proof is found inside it.
        _chain(*BUILD, "_RTHP-ACTIVE-DRAW-CURRENT?", "_RSHSP-DISPATCH",
               "_RSHSP-AUTHORITY?", "_RSHSP-SPANS?"): 12,
        # A storage proof that only its name places is a handover.
        _chain(*BUILD, "_RTHP-BUILD-CANDIDATE", "SHSN-SOURCE-STORAGE-DISJOINT?"): 2,
        # Admission is a wrapper; the control plan's checks are the items'.
        _chain(*BUILD, "RTE-HYBRID-PREFLIGHT", "_RTE-HPV-CONTROL?",
               "_RTE-CONTROL-PLAN-VALID-BODY"): 8,
        # The backend's preflight is fit, less the engine audit it calls.
        _chain(*BUILD, "RTE-FAMILY-BATCH-PREFLIGHT", "RTAPT-FAMILY-PREFLIGHT",
               "_RTAPT-FAMILY-PREFLIGHT-BODY"): 1,
        _chain(*BUILD, "RTE-FAMILY-BATCH-PREFLIGHT", "RTAPT-FAMILY-PREFLIGHT",
               "_RTAPT-FAMILY-PREFLIGHT-BODY", "_RTAPT-ENGINE-VALID?"): 5,
        _chain(*BUILD, "_RTHP-TARGET-CANDIDATE?", "_RTHP-TG-APPEND-CURRENT?"): 3,
        # Building is other work, and painting is outside the frame build.
        _chain(*BUILD, "_RTHP-BUILD-CONTROLS"): 39,
        _chain("DESK-PAINT-CB", "_UTUI-FILL-BG"): 50,
    })]
    _write_run(tmp_path, records, [_present(1_001_300, "DELTA"), _present(1_001_800, "DELTA")])
    isolated, row = checks.typing_rows(tmp_path)
    assert isolated["frame_build"] == 0
    assert row["frames"] == 2
    assert row["frame_build"] == 100 / 2
    assert row["groups"] == {"repeat": 35 / 2, "handover": 14 / 2, "items": 8 / 2,
                             "state": 3 / 2}
    assert row["checks"] == 60 / 2
    assert row["fit"] == 1 / 2
    assert row["other_work"] == 39 / 2
    found = {(item["group"], item["word"]): item["steps"] for item in row["words"]}
    assert found[("repeat", "UCSN-FROZEN-VALIDATE")] == 30 / 2
    assert found[("handover", "_RSHSP-AUTHORITY?")] == 12 / 2
    assert found[("handover", "SHSN-SOURCE-STORAGE-DISJOINT?")] == 2 / 2
    assert ("items", "USCOL-ENTRY-VALIDATE") not in found


def test_the_command_reports_both_windows(tmp_path, capsys) -> None:
    records = [_interval(1_000_300, {_chain(*BUILD, "_RSHSP-PART-VALID?"): 4}),
               _interval(1_001_500, {_chain(*BUILD, "_RTHP-BUILD-CONTROLS"): 6})]
    _write_run(tmp_path, records, [_present(1_000_350, "DELTA"), _present(1_001_600, "DELTA")])
    out = tmp_path / "checks.json"
    assert checks.main([str(tmp_path), "--json", str(out)]) == 0
    text = capsys.readouterr().out
    assert "isolated character: 1 frame(s)" in text and "checks 0.00M (100%)" in text
    assert "burst of 2 characters" in text
    rows = json.loads(out.read_text())
    assert [row["checks"] for row in rows] == [4, 0]
    assert rows[1]["other_work"] == 6
