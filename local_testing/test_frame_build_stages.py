#!/usr/bin/env python3
"""frame_build_stages.py charges a run's steps to frame-build stages."""

from __future__ import annotations

import json

import frame_build_stages as stages

ROOT = "_SIMULATOR-SESSION-ROOT"


def _chain(*words: str) -> str:
    """A chain as the profile writes it: innermost word first."""

    return " < ".join(reversed((ROOT,) + words))


def _interval(t_ns: int, chains: dict[str, int]) -> dict:
    return {"t_ns": t_ns, "steps": sum(chains.values()), "inclusive": {}, "leaf": {},
            "chains": chains}


def _present(t_ns: int, mode: str, size: int = 10) -> dict:
    return {"t_ns": t_ns, "retained_mode": mode, "bytes": size, "cell_mode": "NONE",
            "cell_spans": 0, "cells": 0, "retained_operations": 1}


BUILD = ("SCR-FLUSH?", "RTHP-PREPARE", "_RTHP-PREPARE-LIVE")


def test_a_chain_counts_once_in_each_stage_it_passes_through() -> None:
    records = [_interval(10, {
        # The engine's admission inside the candidate inside the build.
        _chain(*BUILD, "_RTHP-BUILD-OBSERVED-CANDIDATE", "RTE-HYBRID-PREFLIGHT"): 40,
        # Two storage checks nested in one chain count once.
        _chain(*BUILD, "RUHA-SNAPSHOT-FOR@", "RUHA-STORAGE-DISJOINT?",
               "MSPAN-STORAGE-DISJOINT?"): 6,
        _chain("DESK-PAINT-CB", "_UTUI-FILL-BG"): 9,
        _chain("SCR-FLUSH?", "_SCR-EMIT-SPANS"): 5,
    })]
    steps, chained, totals = stages.stage_steps(records)
    assert (steps, chained) == (60, 60)
    assert totals[stages.FRAME_BUILD] == 46
    assert totals["  producer candidate (_RTHP-BUILD-OBSERVED-CANDIDATE)"] == 40
    assert totals["    engine admission (RTE-HYBRID-PREFLIGHT)"] == 40
    assert totals["  documents' snapshot (RUHA-SNAPSHOT-FOR@)"] == 6
    assert totals["storage-aliasing checks (*STORAGE-DISJOINT?)"] == 6
    assert totals["Desk's painting (DESK-PAINT-CB)"] == 9
    assert stages.whole_run_split(records) == {
        "all": 60, "frame_build": 46, "desk_painting": 9, "background_fills": 9,
        "cell_flush_outside_producer": 5,
    }


def _trace() -> dict:
    return {"origin_ns": 1_000, "events": [
        {"event": "input_result", "method": "send_key", "elapsed_ns": 100},
        {"event": "input_result", "method": "activate_tab", "elapsed_ns": 1_000},
        {"event": "input_result", "method": "send_key", "elapsed_ns": 2_000},
        {"event": "acceptance_finished", "elapsed_ns": 3_000},
    ]}


def test_a_desk_interaction_runs_to_the_next_input_and_is_classed_by_its_presents(
        tmp_path, capsys) -> None:
    evidence = tmp_path / "evidence"
    (evidence / "screen-profile").mkdir(parents=True)
    (evidence / "performance-trace.json").write_text(json.dumps(_trace()))
    presents = [_present(1_500, "DELTA"),
                _present(2_500, "REPLACE_START", 900),
                _present(2_600, "REPLACE_CONTINUE", 100)]
    (evidence / "screen-profile" / "presents.jsonl").write_text(
        "".join(json.dumps(p) + "\n" for p in presents))
    # The DELTA's build is charged after its PRESENT, in a record that still
    # ends before the next input; the third input sent nothing.
    records = [_interval(1_800, {_chain(*BUILD): 8}),
               _interval(2_700, {_chain(*BUILD, "_RSHSP-BUILD-BATCH"): 20}),
               _interval(3_900, {_chain("DESK-PAINT-CB"): 3})]
    (evidence / "screen-profile" / "guest-words.jsonl").write_text(
        "".join(json.dumps(r) + "\n" for r in records))
    out = tmp_path / "rows.json"
    assert stages.main([str(tmp_path), "--json", str(out)]) == 0
    rows = json.loads(out.read_text())
    assert [row["window"] for row in rows] == ["input 1 (send_key)",
                                               "input 2 (activate_tab)"]
    assert rows[0]["stages"][stages.FRAME_BUILD] == 8
    assert rows[1]["presents"] == {"REPLACE_START": 1, "REPLACE_CONTINUE": 1}
    assert rows[1]["bytes"] == 1_000
    summary = stages.summary(rows)
    assert summary["DELTA"]["stages"][stages.FRAME_BUILD] == 8
    assert summary["START"]["stages"]["  shell batch (_RSHSP-BUILD-BATCH)"] == 20
    assert "input 2 (activate_tab)" in capsys.readouterr().out
    assert stages.main([str(tmp_path), "--summary"]) == 0
    assert "START, 1 interactions, mean:" in capsys.readouterr().out


def test_a_typing_burst_is_divided_by_its_frames(tmp_path) -> None:
    rows = [{"event": "trace_origin", "origin_ns": 1_000_000, "time_ns": 0}]
    for index, at in enumerate((100, 1_000, 1_200, 1_400)):
        rows.append({"event": "character_dispatched", "index": index, "time_ns": at})
    rows += [{"event": "typing_visible", "count": 1, "time_ns": 400},
             {"event": "typing_visible", "count": 4, "time_ns": 1_900}]
    (tmp_path / "screen-profile").mkdir()
    (tmp_path / "typing-trace.jsonl").write_text(
        "".join(json.dumps(row) + "\n" for row in rows))
    presents = [_present(1_000_300, "DELTA"), _present(1_001_300, "DELTA"),
                _present(1_001_600, "NONE"), _present(1_001_800, "DELTA")]
    (tmp_path / "screen-profile" / "presents.jsonl").write_text(
        "".join(json.dumps(p) + "\n" for p in presents))
    records = [_interval(1_000_350, {_chain(*BUILD): 30}),
               _interval(1_001_850, {_chain(*BUILD): 40, _chain("DESK-PAINT-CB"): 2})]
    (tmp_path / "screen-profile" / "guest-words.jsonl").write_text(
        "".join(json.dumps(r) + "\n" for r in records))
    out = tmp_path / "rows.json"
    assert stages.main([str(tmp_path), "--json", str(out)]) == 0
    isolated, burst = json.loads(out.read_text())
    assert isolated["stages"][stages.FRAME_BUILD] == 30
    # Two DELTAs in the burst; the PRESENT with no retained part is not a frame.
    assert burst["frames"] == 2
    assert burst["stages"][stages.FRAME_BUILD] == 20
    assert burst["steps_per_frame"] == 21
