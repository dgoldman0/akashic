#!/usr/bin/env python3
"""screen_change_profile.py cuts a run's window and charges its steps."""

from __future__ import annotations

import json

import pytest

import screen_change_profile as profile


def _trace():
    return {
        "origin_ns": 1_000,
        "events": [
            {"event": "input_result", "method": "item_select", "elapsed_ns": 100},
            {"event": "input_result", "method": "activate_tab", "elapsed_ns": 1_000},
            {"event": "display_resources_ready", "elapsed_ns": 5_000},
            {"event": "input_result", "method": "send_key", "elapsed_ns": 7_000},
            {"event": "acceptance_finished", "elapsed_ns": 9_000},
        ],
    }


def _interval(t_ns, steps, **words):
    return {"t_ns": t_ns, "steps": steps, "inclusive": words, "leaf": words}


def test_a_window_runs_from_an_input_to_the_end_asked_for() -> None:
    trace = _trace()
    span = profile.window(trace, method="activate_tab", nth=None, until="resources")
    assert (span.start_ns, span.end_ns) == (2_000, 6_000)
    span = profile.window(trace, method=None, nth=1, until="next-input")
    assert (span.start_ns, span.end_ns) == (1_100, 2_000)
    # The last input runs to the end when no later input comes.
    span = profile.window(trace, method=None, nth=None, until="next-input")
    assert (span.start_ns, span.end_ns) == (8_000, 10_000)
    with pytest.raises(ValueError, match="no scroll"):
        profile.window(trace, method="scroll", nth=None, until="end")
    with pytest.raises(ValueError, match="not 3"):
        profile.window(trace, method="activate_tab", nth=3, until="end")


def test_a_summary_charges_each_present_the_steps_since_the_one_before() -> None:
    second = 1_000_000_000
    span = profile.Window(2 * second, 6 * second, "test")
    presents = [
        {"t_ns": 3 * second // 2, "cell_mode": "DELTA", "cell_spans": 1, "cells": 1,
         "retained_mode": "NONE", "retained_operations": 0, "bytes": 1},
        {"t_ns": 3 * second, "cell_mode": "NONE", "cell_spans": 0, "cells": 0,
         "retained_mode": "REPLACE_START", "retained_operations": 9, "bytes": 90},
        {"t_ns": 11 * second // 2, "cell_mode": "REPLACE", "cell_spans": 2, "cells": 20,
         "retained_mode": "NONE", "retained_operations": 0, "bytes": 200},
    ]
    intervals = [
        _interval(19 * second // 10, 50, DESK=50),
        _interval(5 * second // 2, 10, DESK=10, PAINT=10),
        _interval(3 * second, 20, PAINT=20),
        _interval(4 * second, 30, FLUSH=30),
        _interval(6 * second, 40, FLUSH=40),
        _interval(61 * second // 10, 70, DESK=70),
    ]
    summary = profile.summarize(presents, intervals, span)
    assert summary["steps"] == 100
    assert [(row["after_s"], row["cell_mode"], row["steps_before"])
            for row in summary["presents"]] == [(1.0, "NONE", 30), (3.5, "REPLACE", 30)]
    assert summary["inclusive"] == {"FLUSH": 70, "PAINT": 30, "DESK": 10}
    text = profile.report(summary, words=2)
    assert "100 guest steps" in text and "FLUSH" in text and "DESK" not in text


def test_the_command_reads_a_runs_evidence(tmp_path, capsys) -> None:
    evidence = tmp_path / "evidence"
    (evidence / "screen-profile").mkdir(parents=True)
    (evidence / "performance-trace.json").write_text(json.dumps(_trace()))
    (evidence / "screen-profile" / "presents.jsonl").write_text("")
    (evidence / "screen-profile" / "guest-words.jsonl").write_text(
        json.dumps(_interval(3_000, 12, DESK=12)) + "\n")
    out = tmp_path / "summary.json"
    assert profile.main([str(tmp_path), "--input", "activate_tab", "--until",
                         "resources", "--json", str(out)]) == 0
    assert "12 guest steps" in capsys.readouterr().out
    assert json.loads(out.read_text())["inclusive"] == {"DESK": 12}


def _typing_trace():
    rows = [{"event": "trace_origin", "origin_ns": 1_000_000, "time_ns": 0}]
    for index, at in enumerate((100, 1_000, 1_200)):
        rows.append({"event": "character_dispatched", "index": index, "time_ns": at})
    rows += [{"event": "typing_visible", "count": 1, "time_ns": 400},
             {"event": "typing_visible", "count": 3, "time_ns": 1_900}]
    return rows


def test_a_typing_run_is_read_as_its_isolated_character_and_its_burst() -> None:
    isolated, burst = profile.typing_windows(_typing_trace())
    assert (isolated.start_ns, isolated.end_ns) == (1_000_100, 1_000_400)
    assert (burst.start_ns, burst.end_ns) == (1_001_000, 1_001_900)
    assert burst.label == "burst of 2 characters"
    rows = _typing_trace()[1:]
    with pytest.raises(ValueError, match="no origin"):
        profile.typing_windows(rows)
    with pytest.raises(ValueError, match="showed"):
        profile.typing_windows(_typing_trace()[:-1])


def test_the_command_reads_a_typing_run(tmp_path, capsys) -> None:
    (tmp_path / "screen-profile").mkdir()
    (tmp_path / "typing-trace.jsonl").write_text(
        "\n".join(json.dumps(row) for row in _typing_trace()) + "\n")
    (tmp_path / "screen-profile" / "presents.jsonl").write_text("")
    (tmp_path / "screen-profile" / "guest-words.jsonl").write_text(
        json.dumps(_interval(1_000_300, 7, KEY=7)) + "\n"
        + json.dumps(_interval(1_001_500, 9, KEY=9)) + "\n")
    out = tmp_path / "summary.json"
    assert profile.main([str(tmp_path), "--json", str(out)]) == 0
    text = capsys.readouterr().out
    assert "isolated character" in text and "burst of 2 characters" in text
    assert [summary["steps"] for summary in json.loads(out.read_text())] == [7, 9]
