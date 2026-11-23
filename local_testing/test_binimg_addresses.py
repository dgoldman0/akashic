#!/usr/bin/env python3
"""Addresses inside an MF64 image move with it when it loads elsewhere.

utils/binimg.f builds an image from the dictionary region compiled after
IMG-MARK; a load copies that region to wherever there is room and relocates
the immediates the BIOS recorded as addresses.  These tests build each image,
discard the build region, fill the memory it occupied with 0xAB bytes and
load the image at another address, so any build-time address the image still
holds points into the fill.

A VALUE's cell, a compiled TO and a POSTPONE'd XT are addresses the BIOS knows
to record.  A CONSTANT's value is not: the build cannot tell an address from
a number there, so a constant holding an address inside the image refuses
the build (IMG-E-ADDRESS) instead of loading with the build's address.
"""

from __future__ import annotations

import re

from forth_snapshot import ForthSnapshot, program_output

_snapshot = ForthSnapshot(("utils/binimg.f",))

# A buffer for the image, and the fill: a userland build's discard rolls HERE
# back through the 64 KiB relocation buffer, so the old segment lies past it.
FIXTURE = [
    "CREATE _ta-out 8192 ALLOT  VARIABLE _ta-used  VARIABLE _ta-cell",
    ": _ta-move  ( -- ) HERE 81920 171 FILL  4096 ALLOT ;",
]

MOVED = FIXTURE + [
    "IMG-MARK",
    "7 VALUE XVAL",
    ": XGET  ( -- n ) XVAL ;",
    ": XSET  ( n -- ) TO XVAL ;",
    ": XDOUBLE  ( n -- 2n ) 2 * ;",
    ": XPOST  ( -- ) POSTPONE XDOUBLE ; IMMEDIATE",
    ": XENTRY  ( -- ) ;",
    "' XENTRY S\" XENTRY\" IMG-ENTRY-NAMED THROW",
    "' XVAL 3 + @ _ta-cell !",
    "_ta-out 8192 IMG-BUILD-INTO THROW _ta-used !",
    "IMG-DISCARD THROW  _ta-move",
    "_ta-out _ta-used @ IMG-LOAD-MEM THROW",
    "' XVAL 3 + @ _ta-cell @ <> 60 EMIT . 62 EMIT",
    "60 EMIT XGET . 9 XSET XGET . _ta-cell @ C@ . 62 EMIT",
    ": USE  ( -- n ) 21 XPOST ;",
    "60 EMIT USE . 62 EMIT",
]


def _results(text: str) -> list[str]:
    return re.findall(r"<([^<>]*)>", text)


def test_value_to_and_postpone_use_the_loaded_images_own_addresses() -> None:
    text = program_output(_snapshot.run(MOVED, max_steps=400_000_000), MOVED)
    results = _results(text)
    assert len(results) == 3, text
    # The loaded VALUE's code names a cell other than the build's.
    assert results[0].split() == ["-1"], text
    # It reads 7 from its own cell and TO writes 9 there; the build's cell
    # still holds the fill.
    assert results[1].split() == ["7", "9", "171"], text
    # The POSTPONE'd XT is the loaded XDOUBLE's.
    assert results[2].split() == ["42"], text


def _refusal(definitions: list[str], entry: str) -> list[str]:
    program = FIXTURE + ["IMG-MARK", *definitions,
                         f": {entry} ;",
                         f"' {entry} S\" {entry}\" IMG-ENTRY-NAMED THROW",
                         "60 EMIT IMG-BUFFER-MAX NIP . IMG-DISCARD . 62 EMIT"]
    text = program_output(_snapshot.run(program, max_steps=400_000_000), program)
    results = _results(text)
    assert len(results) == 1, text
    return results[0].split()


def test_constant_holding_an_address_in_the_image_refuses_the_build() -> None:
    # IMG-E-ADDRESS is -13; the discard after it succeeds.
    assert _refusal(["HERE CONSTANT XH"], "XE1") == ["-13", "0"]
    assert _refusal([": XW 1 ;", "' XW CONSTANT XW-XT"], "XE2") == ["-13", "0"]
    # The segment's end is inside it: HERE as the last constant.
    assert _refusal([": XW2 2 ;", "HERE CONSTANT XEND"], "XE3") == ["-13", "0"]


def test_numbers_and_the_systems_own_addresses_stay_constants() -> None:
    assert _refusal(["5 CONSTANT XFIVE", "-1 CONSTANT XTRUE",
                     "' DUP CONSTANT XDUP-XT", ": XUSE XFIVE XDUP-XT EXECUTE ;"],
                    "XE4") == ["0", "0"]
