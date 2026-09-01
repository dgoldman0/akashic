#!/usr/bin/env python3
"""Seconds-scale source contract for ordinary DATA_GRAPHICS consumers."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SOUNDLAB = ROOT / "akashic/tui/applets/soundlab/soundlab.f"
WORLDS = ROOT / "akashic/tui/applets/worlds/worlds.f"
OBSERVATORY = ROOT / "akashic/tui/applets/observatory/observatory.f"
WIDGET = ROOT / "akashic/tui/widgets/data-graphics.f"


def _definition(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:\s+{re.escape(name)}(?=\s).*?;[ \t]*(?:\\[^\n]*)?$",
        source,
    )
    assert match is not None, f"missing Forth definition {name}"
    return match.group(0)


def _ordered(source: str, *needles: str) -> None:
    positions = [source.index(needle) for needle in needles]
    assert positions == sorted(positions), needles


def _no_renderer_coupling(source: str, uidl: str) -> None:
    assert "REQUIRE ../../widgets/data-graphics.f" in source
    assert all(word in source for word in ("DGRAPH-NEW", "DGRAPH-BIND", "DGRAPH-FREE"))
    assert "WDG-DRAW-IN" in source
    assert "DGRAPH-DATA-GRAPHICS-CAPTURE" not in source
    assert "rich-terminal" not in source.lower()
    assert not re.search(r"\b(?:RICH|RTERM|SCENE|PROVIDER)-", source)
    lowered = uidl.lower()
    assert not any(
        token in lowered
        for token in (
            "data-graphics",
            "data_graphics",
            "instrument=",
            "provider=",
            "scene=",
            "rich-terminal",
            "retained-capacity",
            "terminal-buffer",
        )
    )


def _bind_before_flip(definition: str, active_word: str) -> None:
    _ordered(definition, "UDG-BUILDER-FINISH", "DGRAPH-BIND", active_word)


def test_applet_data_graphics_source_contract() -> None:
    sound = SOUNDLAB.read_text(encoding="utf-8")
    worlds = WORLDS.read_text(encoding="utf-8")
    observatory = OBSERVATORY.read_text(encoding="utf-8")
    widget = WIDGET.read_text(encoding="utf-8")

    for path, source in (
        (SOUNDLAB, sound),
        (WORLDS, worlds),
        (OBSERVATORY, observatory),
    ):
        _no_renderer_coupling(source, path.with_suffix(".uidl").read_text(encoding="utf-8"))

    # Sound Lab: eight canonical readouts, two meters, and three statuses.
    assert 112 + 5 * 144 + 3 * 152 + 2 * 144 + 3 * 128 == 1960
    assert "1960 CONSTANT _SL-DGRAPH-CAP" in sound
    assert "13 CONSTANT _SL-DGRAPH-OBJECT-COUNT" in sound
    sound_build = _definition(sound, "_SL-DGRAPH-REBUILD")
    assert sound_build.count("_SL-DGRAPH-BUILDER UDG-READOUT") == 8
    assert sound_build.count("_SL-DGRAPH-BUILDER UDG-METER") == 2
    assert sound_build.count("_SL-DGRAPH-BUILDER UDG-STATUS") == 3
    assert all(unit in sound_build for unit in ('S"  ppt"', 'S"  Hz"'))
    assert "_SL-M-PEAK @ _SL-FP16-PERCENT" in sound_build
    assert "_SL-M-DC @ _SL-FP16-PERMILLE" in sound_build
    assert "_SL-M-PITCH @ FP16>INT" in sound_build
    _bind_before_flip(sound_build, "_SL-DGRAPH-ACTIVE-A !")
    sound_view = _definition(sound, "_SL-INVALIDATE")
    sound_semantic = _definition(sound, "_SL-DGRAPH-INVALIDATE")
    assert "_SL-DGRAPH-REBUILD-D" not in sound_view
    assert "_SL-DGRAPH-REBUILD-D" in sound_semantic
    assert "_SL-DGRAPH-INVALIDATE" in _definition(sound, "_SL-PARAM-CHANGED")
    sound_draw = _definition(sound, "_SL-PANEL-DRAW")
    assert "_SL-LAYOUT _SL-DGRAPH-ENSURE-LAYOUT" in sound_draw
    assert "_SL-PANEL-RGN @ WDG-DRAW-IN" in sound_draw
    sound_tick = _definition(sound, "SOUNDLAB-TICK-CB")
    assert "_SL-DGRAPH-OWNED-ACTIVE @ <>" in sound_tick
    assert "_SL-DGRAPH-AUDIO-PRESENT @ <> OR" in sound_tick
    assert "APP-F-TICK-WHEN-CLEAN" in sound
    sound_init = _definition(sound, "SOUNDLAB-INIT-CB")
    _ordered(
        sound_init,
        "DGRAPH-NEW",
        "_SL-DGRAPH-REBUILD DGRAPH-S-OK",
        "_SL-RENDER _SL-INIT-RENDER-IOR !",
    )
    sound_stop = _definition(sound, "SOUNDLAB-SHUTDOWN-CB")
    _ordered(sound_stop, "DGRAPH-FREE", "_SL-PANEL-RGN @ ?DUP IF RGN-FREE")

    # Worlds: twelve readouts, two meters, three truthful statuses.
    assert 112 + 11 * 144 + 160 + 2 * 144 + 3 * 128 == 2528
    assert re.search(
        r"UDG-HEADER-SIZE\s+0 UDG-READOUT-RECORD-BYTES 11 \* \+\s+"
        r"16 UDG-READOUT-RECORD-BYTES \+\s+"
        r"UDG-METER-RECORD-SIZE 2 \* \+\s+"
        r"UDG-STATUS-RECORD-SIZE 3 \* \+\s+"
        r"CONSTANT _WORLD-DGRAPH-CAP",
        worlds,
    )
    assert "17 CONSTANT _WORLD-DGRAPH-OBJECT-COUNT" in worlds
    assert _definition(worlds, "_WORLD-DGRAPH-EMIT-READOUTS").count(
        "_WORLD-DGRAPH-READOUT"
    ) == 12
    assert _definition(worlds, "_WORLD-DGRAPH-EMIT-METERS").count(
        "_WORLD-DGRAPH-METER"
    ) == 2
    assert _definition(worlds, "_WORLD-DGRAPH-EMIT-STATUSES").count(
        "_WORLD-DGRAPH-STATUS"
    ) == 3
    world_build = _definition(worlds, "_WORLD-DGRAPH-REBUILD")
    assert "_WORLD-RUN WRUN-VALID?" in world_build
    _bind_before_flip(world_build, "_WORLD-DGRAPH-ACTIVE-A !")
    replay = _definition(worlds, "_WORLD-REPLAY-ACTION")
    _ordered(
        replay,
        "WRUN-REPLAY",
        "_WORLD-REPLAY-STATUS !",
        "_WORLD-REPLAY-ATTEMPTED !",
        "_WORLD-APPLY-STATUS",
    )
    world_panel = _definition(worlds, "_WORLD-PANEL-DRAW")
    assert "_WORLD-REPLAY-ATTEMPTED @" in world_panel
    assert "_WORLD-REPLAY-STATUS @ WRUN-S-OK = AND" in world_panel
    assert "_WORLD-PANEL-RGN @ WDG-DRAW-IN" in _definition(
        worlds, "_WORLD-DRAW-INSTRUMENT"
    )
    assert "_WORLD-PANEL-RGN @ WDG-DRAW-IN" in _definition(
        worlds, "_WORLD-DRAW-JOURNAL"
    )
    world_init = _definition(worlds, "WORLDS-INIT-CB")
    _ordered(world_init, "DGRAPH-NEW", "_WORLD-DGRAPH-REBUILD DGRAPH-S-OK")
    world_stop = _definition(worlds, "WORLDS-SHUTDOWN-CB")
    _ordered(world_stop, "DGRAPH-FREE", "_WORLD-PANEL-RGN @ ?DUP IF RGN-FREE")

    # Observatory: nine readouts plus a status tied only to a real profile attempt.
    assert 112 + 9 * 144 + 128 == 1536
    assert re.search(
        r"UDG-HEADER-SIZE\s+0 UDG-READOUT-RECORD-BYTES 9 \* \+\s+"
        r"UDG-STATUS-RECORD-SIZE \+\s+CONSTANT _OBS-DGRAPH-CAP",
        observatory,
    )
    assert "10 CONSTANT _OBS-DGRAPH-OBJECT-COUNT" in observatory
    assert _definition(observatory, "_OBS-DGRAPH-EMIT-READOUTS").count(
        "_OBS-DGRAPH-READOUT"
    ) == 9
    assert _definition(observatory, "_OBS-DGRAPH-EMIT-STATUS").count(
        "_OBS-DGRAPH-BUILDER UDG-STATUS"
    ) == 1
    obs_build = _definition(observatory, "_OBS-DGRAPH-REBUILD")
    _bind_before_flip(obs_build, "_OBS-DGRAPH-ACTIVE-A !")
    assert "_OBS-LAST-PROFILE-STATUS" in observatory
    assert "OBS-S-INVALID _OBS-LAST-PROFILE-STATUS !" in observatory
    accept = _definition(observatory, "_OBS-ACCEPT-SNAPSHOT")
    assert "_OBS-PROFILE-CANDIDATE DUP _OBS-LAST-PROFILE-STATUS !" in accept
    assert "_OBS-DGRAPH-REBUILD-D" not in _definition(
        observatory, "_OBS-VIEW-INVALIDATE"
    )
    assert "_OBS-DGRAPH-REBUILD-D" in _definition(
        observatory, "_OBS-PROFILE-INVALIDATE"
    )
    assert "_OBS-TABLE-REBUILD-D" in _definition(
        observatory, "_OBS-SERIES-INVALIDATE"
    )
    assert "_OBS-PANEL-RGN @ WDG-DRAW-IN" in _definition(
        observatory, "_OBS-DRAW-TABLE"
    )
    obs_init = _definition(observatory, "OBSERVATORY-INIT-CB")
    _ordered(obs_init, "DGRAPH-NEW", "_OBS-DGRAPH-REBUILD DGRAPH-S-OK")
    obs_stop = _definition(observatory, "OBSERVATORY-SHUTDOWN-CB")
    _ordered(obs_stop, "DGRAPH-FREE", "_OBS-PANEL-RGN @ ?DUP IF RGN-FREE")

    # Rebinding an equal renderer scratch size reuses that allocation while
    # unequal-size allocation remains complete before descriptor mutation.
    bind = _definition(widget, "DGRAPH-BIND")
    _ordered(
        bind,
        "_DGRAPH-B-OLD-SCRATCH !",
        "_DGRAPH-O-SCRATCH-U + @ =",
        "_DGRAPH-B-OLD-SCRATCH @ _DGRAPH-B-NEW-SCRATCH !",
        "ALLOCATE DUP IF",
        "_DGRAPH-O-MODEL-A + !",
        "_DGRAPH-B-OLD-SCRATCH @ ?DUP IF",
    )
    assert "_DGRAPH-B-NEW-SCRATCH @ <> IF FREE ELSE DROP THEN" in bind
