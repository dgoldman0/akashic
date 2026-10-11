#!/usr/bin/env python3
"""How much of a provider's input room a prompt takes.

JSON-ESTR-LEN is checked against what JSON-ESTR writes, OAI-TURN-INPUT-U
against what OAI-TURN-INPUT-JSON writes, at the exact boundary of the
buffer it writes into, and APROV-INPUT against the OpenAI provider's room
and a provider that bounds its input by memory alone.
"""

from __future__ import annotations

import pytest

from native_forth import NativeForth


PRELUDE = r"""
CREATE SB 4096 ALLOT  VARIABLE SU
CREATE OUT 4096 ALLOT
: SB!  ( c index -- ) SB + C! ;
\ What JSON-ESTR writes for the string in SB, and what JSON-ESTR-LEN says.
: ESC.  ( -- )
    JSON-BUILD-RESET OUT 4096 JSON-SET-OUTPUT SB SU @ JSON-ESTR
    JSON-OUTPUT-RESULT NIP . SB SU @ JSON-ESTR-LEN . ;

VARIABLE CX  VARIABLE BIG  VARIABLE BIG-U
CREATE TN AGENT-TURN-REQUEST-SIZE ALLOT
: SETUP  ( -- ) ACTX-NEW DROP CX ! 40000 ALLOCATE DROP BIG ! ;
SETUP
\ A turn with no history whose prompt is the U bytes at A.
: TURN  ( a u -- )
    TN ATURN-INIT 1 TN ATURN.THREAD-ID ! 1 TN ATURN.RUN-ID !
    TN ATURN.PROMPT-U ! TN ATURN.PROMPT-A !
    CX @ TN ATURN.CONTEXT ! 0 TN ATURN.CONTEXT-N !
    CX @ ACTX.REVISION @ TN ATURN.CONTEXT-REVISION ! ;
: PROVIDER$  ( -- a u ) S" org.akashic.agent.openai.responses" ;
\ The length and status of the turn's input written into CAPACITY bytes.
: INPUT  ( capacity -- length status )
    >R TN PROVIDER$ OUT R> OAI-TURN-INPUT-JSON ;
\ A prompt of U bytes of A in BIG.
: AS  ( u -- ) DUP BIG-U ! BIG @ SWAP 65 FILL ;

CREATE AUTH AGENT-PROVIDER-AUTH-SIZE ALLOT  AUTH AAUTH-INIT
CREATE PORT NET-IO-PORT-SIZE ALLOT
VARIABLE OAI  VARIABLE SCR
: PROVIDERS  ( -- )
    0 AUTH PORT OPENAI-PROVIDER-NEW DROP OAI ! SCRIPTED-PROVIDER-NEW DROP SCR ! ;
PROVIDERS
"""

SUITE = NativeForth(("tui/applets/agent/providers/openai/responses.f",
                     "tui/applets/agent/providers/devtools/scripted.f"),
                    prelude=tuple(PRELUDE.strip().splitlines()))


@pytest.fixture(scope="module")
def forth():
    return SUITE.shared()


def run(forth, lines: list[str], max_steps: int = 2_000_000_000) -> list[list[int]]:
    output = forth.run(lines, max_steps).decode("latin-1")
    assert "??" not in output, output[-3000:]
    return [[int(token) for token in line.split()]
            for line in output.replace("\r", "").split("\n") if line.strip()]


STRINGS = {
    "empty": b"",
    "plain text": b"Summarize the news.",
    "quotes and backslashes": b'say "hi" \\ there',
    "line breaks and tabs": b"one\ntwo\r\n\tthree",
    "backspace and form feed": b"a\x08b\x0cc",
    "other control bytes": b"\x01\x1f\x00",
    "delete and UTF-8": "\x7fcafé 日本".encode(),
}


def test_escaped_length_is_what_json_estr_writes(forth):
    lines = []
    for value in STRINGS.values():
        sets = " ".join(f"{byte} {index} SB!" for index, byte in enumerate(value))
        lines.append(f"{sets} {len(value)} SU ! ESC. CR")
    rows = run(forth, lines)
    assert len(rows) == len(STRINGS), rows
    for name, row in zip(STRINGS, rows):
        written, said = row
        assert said == written, name


def test_a_turns_input_size_is_exact(forth):
    rows = run(forth, [
        # Short prompts with escapes: the size is what the encoder writes.
        'S" hello" TURN 4096 INPUT . . S" hello" OAI-TURN-INPUT-U . CR',
        "SB 9 97 FILL 34 0 SB! 10 4 SB! 92 8 SB! SB 9 TURN 4096 INPUT . . "
        "SB 9 OAI-TURN-INPUT-U . CR",
        # The encoder fits it in exactly that many bytes, and not one fewer.
        "300 AS BIG @ BIG-U @ TURN BIG @ BIG-U @ OAI-TURN-INPUT-U DUP . "
        "DUP INPUT . . 1- INPUT . DROP CR",
    ])
    assert rows[0] == [0, 35, 35]
    status, written, said = rows[1]
    assert status == 0 and said == written
    size = rows[2][0]
    assert size == 300 + 30
    assert rows[2][1:] == [0, size, 2]


def test_the_room_a_provider_has(forth):
    rows = run(forth, [
        'S" hello" OAI @ APROV-INPUT . . S" hello" OAI @ APROV-INPUT-FITS? . CR',
        # The OpenAI provider holds a turn's input in 32768 bytes: a prompt
        # that takes exactly that fits, one more byte does not.
        "32738 AS BIG @ BIG-U @ OAI @ APROV-INPUT . . BIG @ BIG-U @ OAI @ APROV-INPUT-FITS? . "
        "32739 AS BIG @ BIG-U @ OAI @ APROV-INPUT . . BIG @ BIG-U @ OAI @ APROV-INPUT-FITS? . CR",
        # A provider that copies any prompt it is given has no room to say.
        "32739 AS BIG @ BIG-U @ SCR @ APROV-INPUT . . BIG @ BIG-U @ SCR @ APROV-INPUT-FITS? . CR",
    ])
    assert rows == [
        [32768, 35, -1],
        [32768, 32768, -1, 32768, 32769, 0],
        [-1, 32739, -1],
    ]
