#!/usr/bin/env python3
"""tui/app-builder.f: the question before an install.

An applet the builder installs is native code that runs with the machine's
full authority, so ABUILD-INSTALL builds only a project the user allowed.
The suite runs the question's words on the native runtime: an install with
no answer is refused before anything is read or compiled; a question
waits, one at a time, with its project's path and place; a refusal and a
withdrawal leave nothing to install; an allowed answer covers only the
project it was asked for, and the install uses it up.  The builds
themselves run in the package contracts and test_image_system_check.py.
"""

from __future__ import annotations

import pytest

from native_forth import NativeForth


PRELUDE = r"""
\ Two places, as tokens: the builder only compares them.
4096 CONSTANT P1  8192 CONSTANT P2
\ A path longer than any a manifest takes.
CREATE LONG 300 ALLOT  LONG 300 47 FILL
: Q.  ( -- ) ABUILD-QUESTION@ . ;
: ASKING.  ( -- ) ABUILD-ASKING ROT ROT TYPE ."  " . ;
"""

SUITE = NativeForth(("tui/app-builder.f",), prelude=tuple(PRELUDE.strip().splitlines()))


@pytest.fixture(scope="module")
def forth():
    return SUITE.shared()


def run(forth, lines: list[str]) -> list[str]:
    output = forth.run(lines, 400_000_000).decode("latin-1")
    assert "??" not in output, output[-3000:]
    return [line.rstrip() for line in output.replace("\r", "").split("\n")
            if line.strip()]


def test_the_statement_says_what_an_install_means(forth):
    rows = run(forth, ["ABUILD-STATEMENT TYPE CR"])
    assert rows == [
        "Installing builds this project into a native applet. A native applet "
        "runs with this machine's full authority: it can read and change every "
        "file, use every signed-in account and reach the network, and the "
        "sandbox does not hold it. Install only code you trust."
    ]


def test_an_install_needs_an_allowed_question(forth):
    rows = run(forth, [
        "ABUILD-WITHDRAW",
        # Nothing asked: refused before anything is read.
        'S" /a.toml" P1 ABUILD-INSTALL . . CR',
        # A question waits, with its project, and blocks a second one.
        'S" /a.toml" P1 ABUILD-ASK . Q. ASKING. CR',
        'S" /b.toml" P2 ABUILD-ASK . Q. CR',
        # Unanswered, it installs nothing.
        'S" /a.toml" P1 ABUILD-INSTALL . . Q. CR',
        # Refused, it installs nothing either, and no longer waits.
        "0 ABUILD-ANSWER Q. ASKING. CR",
        'S" /a.toml" P1 ABUILD-INSTALL . . Q. CR',
        # An answer with no question waiting changes nothing.
        "-1 ABUILD-ANSWER Q. CR",
        "ABUILD-WITHDRAW Q. ASKING. CR",
    ])
    unconfirmed, ok, busy = -215, 0, -201
    asking, allowed, refused, none = 1, 2, 3, 0
    assert rows == [
        f"{unconfirmed} 0",
        f"{ok} {asking} /a.toml 4096",
        f"{busy} {asking}",
        f"{unconfirmed} 0 {asking}",
        f"{refused}  0",
        f"{unconfirmed} 0 {refused}",
        f"{refused}",
        f"{none}  0",
    ]


def test_an_allowed_answer_covers_its_project_alone(forth):
    rows = run(forth, [
        "ABUILD-WITHDRAW",
        'S" /a.toml" P1 ABUILD-ASK . -1 ABUILD-ANSWER Q. CR',
        # Another project, or the same one in another place, is refused and
        # leaves the answer standing.
        'S" /b.toml" P1 ABUILD-INSTALL . . Q. CR',
        'S" /a.toml" P2 ABUILD-INSTALL . . Q. CR',
        # The project allowed goes ahead and uses up the answer.  The native
        # runtime compiles no machine code, so the build stops there, as
        # test_image_system_check.py shows.
        'S" /a.toml" P1 ABUILD-INSTALL . . Q. CR',
        'S" /a.toml" P1 ABUILD-INSTALL . . CR',
    ])
    unconfirmed, unsupported, ok, allowed, none = -215, -214, 0, 2, 0
    assert rows == [
        f"{ok} {allowed}",
        f"{unconfirmed} 0 {allowed}",
        f"{unconfirmed} 0 {allowed}",
        f"{unsupported} 0 {none}",
        f"{unconfirmed} 0",
    ]


def test_a_question_takes_a_path_a_manifest_takes(forth):
    rows = run(forth, [
        "ABUILD-WITHDRAW",
        'S" " P1 ABUILD-ASK . Q. CR',
        "LONG 256 P1 ABUILD-ASK . Q. CR",
        "LONG 255 P1 ABUILD-ASK . Q. ABUILD-WITHDRAW CR",
    ])
    bounds, ok, none, asking = -203, 0, 0, 1
    assert rows == [f"{bounds} {none}", f"{bounds} {none}", f"{ok} {asking}"]
