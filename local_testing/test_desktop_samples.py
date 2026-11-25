"""The Desktop's sample files in assets/samples/desktop are exactly what
local_testing/generate_desktop_samples.py writes.  Images take their samples
from that folder, and a configuration names it as its first documents."""

from __future__ import annotations

import re

import generate_desktop_samples as generator


def test_the_sample_folder_is_what_the_generator_writes():
    assert generator.differences() == []


def test_the_daybook_sample_falls_on_one_named_day():
    daybook = (generator.OUTPUT / "daybook.md").read_bytes()
    assert set(re.findall(rb"\d{4}-\d{2}-\d{2}", daybook)) == {
        generator.SAMPLE_DATE.encode()
    }
