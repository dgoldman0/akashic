"""The journeys for Desk with Sound Lab or Observatory alone, over synthetic frames.

Sound Lab, Observatory and Worlds stay out of the first release (decision 35
of fantasy-engine's release plan), so these checks run when asked for rather
than with each change.  The shipped applets' journeys stay in
test_rich_terminal_applet_journeys.py, whose frame helpers these share.
"""

from __future__ import annotations

from dataclasses import replace

import pytest

from test_rich_terminal_applet_journeys import (  # noqa: F401  The helpers the journeys share.
    ControlState,
    OBSERVATORY_DEMO_SERIES,
    ObservatoryJourney,
    PhysicalDesktopAcceptanceError,
    ROWS,
    SOUNDLAB_FIELD_ID,
    SemanticContentFlag,
    SemanticTextContent,
    SemanticTextItem,
    SemanticTextRole,
    SemanticTextState,
    SoundLabAloneJourney,
    _cell_offer,
    _held,
    _prompt,
    _run,
    _screen,
    _soundlab_field_claims,
    acceptance_runner,
    applet_journey,
)


# Sound Lab alone: its landmark line across row 60, columns 4 to 90.
SOUNDLAB_READY = ("SOUND LAB", "Waveform")
LANDMARK_ROW, LANDMARK_LEFT, LANDMARK_RIGHT = 60, 4, 90


def _landmarks(frequency: int):
    half, one = 0x7FFFFFFF, 0xFFFFFFFF
    pitch = LANDMARK_LEFT + frequency * (LANDMARK_RIGHT - LANDMARK_LEFT - 1) // 4000

    def line(identity, column, width, color, points):
        return acceptance_runner._InstrumentClaim(
            "POLYLINE", 1, 1, identity, column, LANDMARK_ROW, column + width,
            LANDMARK_ROW + 1, color, points)

    return pitch, (
        line(60_050, LANDMARK_LEFT, LANDMARK_RIGHT - LANDMARK_LEFT,
             (0x80, 0x80, 0x80, 0xFF), ((0, half), (one, half))),
        line(60_051, pitch, 1, (0x5F, 0xD7, 0xFF, 0xFF), ((half, 0), (half, one))),
        line(60_052, pitch + 3, 1, (0xFF, 0xD7, 0x00, 0xFF), ((half, 0), (half, one))),
    )


def _soundlab_frame(frequency: int, *, shown=True, prompt=None):
    rows = {1: "  SOUND LAB", 3: "  Waveform", ROWS - 1: "[1:Sound Lab*]"}
    frame = replace(_screen(rows, ()),
                    semantic_field_claims=_soundlab_field_claims(frequency),
                    instrument_claims=_landmarks(frequency)[1] if shown else ())
    return _held(frame, prompt) if prompt else frame


def _soundlab_cells(frequency: int):
    pitch = _landmarks(frequency)[0]
    drawn = ["─"] * (LANDMARK_RIGHT - LANDMARK_LEFT)
    for column in (pitch, pitch + 3):
        drawn[column - LANDMARK_LEFT] = "│"
    return _cell_offer(1, (
        (LANDMARK_ROW - 2, LANDMARK_LEFT, acceptance_runner.SOUNDLAB_LANDMARK_CAPTION),
        (LANDMARK_ROW - 1, pitch, "P"), (LANDMARK_ROW - 1, pitch + 3, "C"),
        (LANDMARK_ROW, LANDMARK_LEFT, "".join(drawn)),
    ))


def _frequency_prompt(typed: str, *, anchor: int = 0):
    prompt = _prompt(acceptance_runner.SOUNDLAB_FREQUENCY_PROMPT, typed, row=ROWS - 3)
    return replace(prompt, content=replace(prompt.content, anchor=anchor))


def test_soundlab_alone_moves_its_pitch_mark_with_a_new_render() -> None:
    journey = applet_journey("soundlab", SOUNDLAB_READY)
    assert isinstance(journey, SoundLabAloneJourney)
    before, after = _soundlab_cells(440), _soundlab_cells(880)
    held = _soundlab_cells(440)
    steps = (
        (before, _soundlab_frame(440)),
        (held, _soundlab_frame(440, prompt=_frequency_prompt("440", anchor=3))),
        (held, _soundlab_frame(440, prompt=_frequency_prompt("440"))),
        (held, _soundlab_frame(440, prompt=_frequency_prompt("880", anchor=3))),
        # The new setting leaves the analysis stale: no landmarks.
        (held, _soundlab_frame(880, shown=False)),
        (held, _soundlab_frame(880, shown=False)),
        (after, _soundlab_frame(880)),
    )
    results = _run(journey, steps)
    assert [(result.milestone, sent) for result, sent in results] == [
        ("soundlab-landmarks-shown", [("field_activate", f"1,1,{SOUNDLAB_FIELD_ID + 1}")]),
        ("soundlab-frequency-prompt", [("send_key", "ctrl+a")]),
        ("soundlab-frequency-selected", [("send_text", "880")]),
        ("soundlab-frequency-typed", [("send_key", "enter")]),
        ("soundlab-frequency-set", [("send_key", "f5")]),
        (None, []),
        ("soundlab-landmarks-moved", []),
    ]
    assert results[-1][0].complete


def test_soundlab_alone_refuses_cell_that_draws_its_marks_elsewhere() -> None:
    journey = applet_journey("soundlab", SOUNDLAB_READY)
    with pytest.raises(PhysicalDesktopAcceptanceError, match="name Sound Lab's mark"):
        _run(journey, ((_soundlab_cells(880), _soundlab_frame(440)),))


def _observatory_offer(samples, *, table=None, baseline_row=None, offer_id=1):
    """Desk with Observatory on the left: its plot over SAMPLES from row 20,
    its baseline along the row below, and its table listing TABLE."""

    from rich_terminal.retained_scene import ObjectBounds, RGBA, Sample
    from rich_terminal.retained_view import (
        PlotDraw, PolylineDraw, RetainedDrawPlane, RetainedRegionDraw,
        SeriesHistoryDraw, TextGridDraw,
    )

    offer = _cell_offer(offer_id, ((19, 2, "Upper amount projection"),))
    values = [value for _, value in samples]
    low, high = min(values), max(values)
    plot = PlotDraw(70_001, 0, ObjectBounds(2, 20, 70, 10), 1, low, high,
                    RGBA(0x5F, 0xD7, 0xFF, 0xFF), RGBA(0, 0, 0, 0), False,
                    len(samples) <= 70)
    line = PolylineDraw(70_002, 0, ObjectBounds(2, 30 if baseline_row is None else baseline_row,
                                                70, 1),
                        (acceptance_runner_point(0, 0x7FFFFFFF),
                         acceptance_runner_point(0xFFFFFFFF, 0x7FFFFFFF)),
                        0x20000000, RGBA(0x4E, 0x4E, 0x4E, 0xFF), False)
    shown = samples if table is None else table
    items = [SemanticTextItem(1, 0, 0, 1, 1, SemanticTextRole.COLUMN_HEADER,
                              SemanticTextState(0), "tick"),
             SemanticTextItem(2, 0, 1, 1, 1, SemanticTextRole.COLUMN_HEADER,
                              SemanticTextState(0), "upper amount")]
    for index, (tick, value) in enumerate(shown):
        items += [SemanticTextItem(10 + 2 * index, index + 1, 0, 1, 1,
                                   SemanticTextRole.ROW_HEADER, SemanticTextState(0), str(tick)),
                  SemanticTextItem(11 + 2 * index, index + 1, 1, 1, 1,
                                   SemanticTextRole.CONTENT, SemanticTextState(0), str(value))]
    content = SemanticTextContent(1, len(shown) + 1, 2, 0, 0, len(shown) + 1, 2,
                                  SemanticContentFlag(0), 0, 0, 0, 0, tuple(items))
    grid = TextGridDraw(70_003, ControlState.VISIBLE | ControlState.ENABLED, 0, 0,
                        ObjectBounds(2, 12, 40, 6), content)
    region = RetainedRegionDraw(1, 1, 2, 0, 0, 139, 83, 0, 0, 139, 83, 1, True,
                                (plot, line, grid))
    history = SeriesHistoryDraw(1, 1, 1, tuple(Sample(tick, value) for tick, value in samples))
    return replace(offer, retained=RetainedDrawPlane(
        True, True, offer.retained.regions + (region,), (history,)))


def acceptance_runner_point(x, y):
    from rich_terminal.retained_scene import Point
    return Point(x, y)


def test_observatory_plot_is_its_series_and_its_table_lists_the_same_samples() -> None:
    from rich_terminal_applet_journeys import _observatory_plot, _observatory_table

    bounds = (0, 0, 139, 83)
    offer = _observatory_offer(OBSERVATORY_DEMO_SERIES)
    plot, samples = _observatory_plot(offer, bounds)
    assert samples == OBSERVATORY_DEMO_SERIES
    assert (plot.left, plot.top, plot.right, plot.bottom) == (2, 20, 72, 30)
    assert _observatory_table(offer, bounds) == OBSERVATORY_DEMO_SERIES
    with pytest.raises(PhysicalDesktopAcceptanceError, match="baseline"):
        _observatory_plot(_observatory_offer(OBSERVATORY_DEMO_SERIES, baseline_row=31), bounds)


OBSERVATORY_READY = ("OBSERVATORY / SERIES PROFILE", "WORLDS / RESERVOIR FACILITY")
TELEMETRY = ((0, 9000), (1, 8750), (2, 8500), (3, 8250))


def _observatory_frame(focus: str, status: str = "Profiled 8 samples"):
    rows = {0: "  OBSERVATORY / SERIES PROFILE".ljust(140) + "  WORLDS / RESERVOIR FACILITY",
            ROWS - 3: "  " + status,
            ROWS - 1: f"[1:Observator{'*' if focus == 'observatory' else ''}] "
                      f"[2:Worlds{'*' if focus == 'worlds' else ''}]"}
    return _screen(rows, ())


def test_observatory_plots_its_series_then_worlds_telemetry_and_keeps_it_on_rerun() -> None:
    journey = applet_journey("observatory", OBSERVATORY_READY)
    assert isinstance(journey, ObservatoryJourney)
    demo = _observatory_offer(OBSERVATORY_DEMO_SERIES)
    telemetry = _observatory_offer(TELEMETRY)
    steps = (
        (demo, _observatory_frame("observatory")),
        # Focus has not moved yet.
        (demo, _observatory_frame("observatory")),
        (demo, _observatory_frame("worlds")),
        (demo, _observatory_frame("worlds")),
        (demo, _observatory_frame("worlds")),
        (demo, _observatory_frame("worlds")),
        # Desk brings Observatory forward before it has taken the run.
        (demo, _observatory_frame("observatory")),
        (telemetry, _observatory_frame("observatory", "Profiled 4 samples")),
        (telemetry, _observatory_frame("observatory", "Profiled 4 samples")),
    )
    results = _run(journey, steps)
    assert [(result.milestone, sent) for result, sent in results] == [
        ("observatory-plot-shown", [("send_key", "alt+2")]),
        (None, []),
        ("worlds-step-1", [("send_key", "s")]),
        ("worlds-step-2", [("send_key", "s")]),
        ("worlds-step-3", [("send_key", "s")]),
        ("worlds-analyze", [("send_key", "a")]),
        (None, []),
        ("observatory-plots-telemetry", [("send_key", "r")]),
        ("observatory-rerun-kept-plot", []),
    ]
    assert results[-1][0].complete


def test_observatory_takes_focus_back_when_worlds_keeps_it_after_analyze() -> None:
    journey = ObservatoryJourney(OBSERVATORY_READY)
    journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
    journey.stage = ObservatoryJourney.ANALYZE
    telemetry = _observatory_offer(TELEMETRY)
    steps = (
        (telemetry, _observatory_frame("worlds", "Profiled 4 samples")),
        (telemetry, _observatory_frame("observatory", "Profiled 4 samples")),
    )
    results = _run(journey, steps)
    assert [(result.milestone, sent) for result, sent in results] == [
        ("observatory-plots-telemetry", [("send_key", "alt+1")]),
        ("observatory-rerun", [("send_key", "r")]),
    ]


def test_observatory_counts_a_worlds_step_only_once_its_press_is_delivered() -> None:
    """A press refused for backpressure, then dropped for a newer frame, is
    sent again under the same milestone, so Worlds steps three times."""

    journey = ObservatoryJourney(OBSERVATORY_READY)
    journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
    journey.stage = ObservatoryJourney.WORLDS
    statuses = iter(("progress", "backpressured", "progress", "progress", "progress"))
    sent = []

    def sender(method, value, *_):
        sent.append((method, value))
        return next(statuses)

    milestones = [
        journey.after_present(_observatory_offer(OBSERVATORY_DEMO_SERIES, offer_id=offer_id),
                              9, _observatory_frame("worlds"), sender).milestone
        for offer_id in range(1, 6)
    ]
    assert milestones == ["worlds-step-1", "worlds-step-2", "worlds-step-2",
                          "worlds-step-3", "worlds-analyze"]
    assert sent == [("send_key", "s")] * 4 + [("send_key", "a")]
    assert journey.stage == ObservatoryJourney.ANALYZE


def test_observatory_refuses_a_handover_whose_status_lags_its_plot() -> None:
    journey = ObservatoryJourney(OBSERVATORY_READY)
    journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
    journey.stage = ObservatoryJourney.ANALYZE
    with pytest.raises(PhysicalDesktopAcceptanceError, match="lacks 'Profiled 4 samples'"):
        _run(journey, ((_observatory_offer(TELEMETRY), _observatory_frame("observatory")),))


def test_observatory_refuses_a_handover_without_a_sample_for_each_step() -> None:
    journey = ObservatoryJourney(OBSERVATORY_READY)
    journey._lineage = journey._offer_lineage(_cell_offer(1, ()), 9)
    journey.stage = ObservatoryJourney.ANALYZE
    with pytest.raises(PhysicalDesktopAcceptanceError, match="3 samples after 3 steps"):
        _run(journey, ((_observatory_offer(TELEMETRY[:3]),
                        _observatory_frame("observatory", "Profiled 3 samples")),))


def test_observatory_refuses_a_plot_whose_table_lists_other_samples() -> None:
    journey = applet_journey("observatory", OBSERVATORY_READY)
    offer = _observatory_offer(OBSERVATORY_DEMO_SERIES, table=TELEMETRY)
    with pytest.raises(PhysicalDesktopAcceptanceError, match="other samples than its table"):
        _run(journey, ((offer, _observatory_frame("observatory")),))
