#!/usr/bin/env python3
"""Akashic net/http-buffered.f inflating gzip bodies.

A buffered exchange asked for gzip inflates a body whose one
Content-Encoding is gzip into its buffer as the body arrives, whatever its
framing and however the port splits it.  The body as sent and as inflated
each count against the buffer, so a small body cannot grow past it.  A
damaged member, bytes after the member, and a body cut inside it are
refused, each with its own reason.  A body in any other coding, or one
the caller did not ask to inflate, is kept as it came.
"""

from __future__ import annotations

import gzip
import random
from dataclasses import dataclass

import pytest

from forth_dependencies import dependency_order
from test_inflate import _text, _zlib
from test_uidl_collection_snapshot import AK, KDOS_PATH, _load_forth_lines
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime

BYTES = 1 << 20
S_OK, S_PROTOCOL = 0, 5
C_IDENTITY, C_GZIP = 0, 1
B_OK, B_CAPACITY, B_DAMAGED, B_TRAILING, B_CUT = range(5)

PRELUDE = f"""
{BYTES} XBUF GZ-RESP
{BYTES} XBUF GZ-BODY
VARIABLE GZ-RESP-U  VARIABLE GZ-POS  VARIABLE GZ-CHUNK
CREATE GZ-PORT NET-IO-PORT-SIZE ALLOT
CREATE GZ-REQ HTTP-REQUEST-SIZE ALLOT
CREATE GZ-REQ-BUF 512 ALLOT
CREATE GZ-XS HTTP-BUFFERED-SIZE 7 + ALLOT
: GZ-X  GZ-XS 7 + -8 AND ;
: GZ-SEND  ( buffer length context -- count io-status )  DROP NIP NIO-S-OK ;
: GZ-RECV  ( buffer capacity context -- count io-status )
    DROP GZ-RESP-U @ GZ-POS @ - DUP 0= IF DROP 2DROP 0 NIO-S-EOF EXIT THEN
    MIN GZ-CHUNK @ MIN >R
    GZ-RESP GZ-POS @ + SWAP R@ CMOVE
    R@ GZ-POS +! R> NIO-S-OK ;
: GZ-NOP  ( context -- )  DROP ;
: GZ-PORT-INIT  ( -- )
    GZ-PORT NIO-INIT
    ['] GZ-SEND GZ-PORT NIO.SEND-XT !
    ['] GZ-RECV GZ-PORT NIO.RECV-XT !
    ['] GZ-NOP GZ-PORT NIO.POLL-XT !
    ['] GZ-NOP GZ-PORT NIO.CANCEL-XT !
    ['] GZ-NOP GZ-PORT NIO.CLOSE-XT ! ;
: GZ-REQUEST  ( -- )
    GZ-REQ-BUF 512 GZ-REQ HREQ-INIT DROP
    S" GET" S" /" GZ-REQ HREQ-BEGIN DROP
    S" example.test" GZ-REQ HREQ-HOST DROP
    GZ-REQ HREQ-CONNECTION-CLOSE DROP
    GZ-REQ HREQ-SEAL DROP ;
: GZ-AGAIN  ( -- status )
    0 GZ-POS !  GZ-PORT-INIT  GZ-REQUEST
    GZ-REQ GZ-PORT GZ-X HBUF-START DROP
    BEGIN GZ-X HBUF-POLL DUP HBUF-S-PENDING = WHILE DROP REPEAT ;
: GZ-RUN  ( capacity gzip? -- status )
    >R GZ-BODY SWAP GZ-X HBUF-INIT DROP  R> GZ-X HBUF-GZIP!  GZ-AGAIN ;
"""


@dataclass
class Result:
    status: int
    coding: int
    body_status: int
    parser_status: int
    reason: int
    body: bytes


class Exchange:
    def __init__(self):
        self.runtime = MegaForthRuntime(
            memory=create_one_core_address_space(external_size=32 << 20, hbw_size=1 << 20),
            execution_backend="native",
        )
        self.runtime.evaluate(KDOS_PATH.read_bytes(), source_name="kdos.f")
        self.runtime.evaluate(b"ENTER-USERLAND", source_name="userland")
        source = []
        for module in dependency_order(AK, ("net/http-buffered.f",)):
            source.extend(_load_forth_lines(AK / module))
        source.append(PRELUDE)
        self.runtime.evaluate(("\n".join(source) + "\n").encode(), source_name="http-gzip",
                              step_budget=200_000_000)
        self.runtime.drain_uart_output()
        self.response = self.word("GZ-RESP")
        self.body = self.word("GZ-BODY")
        self.reasons = {name: self.word(f"INFL-R-{name}") for name in ("HEADER", "SUM")}

    def word(self, *names: str) -> int:
        stack = self.runtime.main_context.data
        for name in names:
            self.runtime.execute(name)
        value = stack.pop()
        assert stack.depth() == 0
        return value

    def call(self, name: str, *args: int) -> int:
        stack = self.runtime.main_context.data
        for value in args:
            stack.push(value)
        self.runtime.execute(name, step_budget=2_000_000_000)
        value = stack.pop()
        assert stack.depth() == 0
        return value

    def store(self, name: str, value: int) -> None:
        stack = self.runtime.main_context.data
        stack.push(value)
        self.runtime.execute(name)
        self.runtime.execute("!")
        assert stack.depth() == 0

    def run(self, response: bytes, *, capacity: int, gzip_asked: bool = True,
            chunk: int = 4096, again: bool = False) -> Result:
        assert len(response) <= BYTES and capacity <= BYTES
        self.runtime.memory.write_bytes(self.response, response)
        self.store("GZ-RESP-U", len(response))
        self.store("GZ-CHUNK", chunk)
        if again:
            status = self.call("GZ-AGAIN")
        else:
            status = self.call("GZ-RUN", capacity, 1 if gzip_asked else 0)
        used = self.word("GZ-X", "HBUF.BODY-U", "@")
        return Result(
            status=status,
            coding=self.word("GZ-X", "HBUF-CODING@"),
            body_status=self.word("GZ-X", "HBUF-BODY-STATUS@"),
            parser_status=self.word("GZ-X", "HBUF.PARSER", "HSTR.STATUS", "@"),
            reason=self.word("GZ-X", "HBUF.INFL", "INFL-REASON@"),
            body=self.runtime.memory.read_bytes(self.body, used),
        )


@pytest.fixture(scope="module")
def exchange():
    return Exchange()


def response(payload: bytes, *, encoding: str | None = "gzip", framing: str = "length",
             code: str = "200 OK", headers: tuple[str, ...] = ()) -> bytes:
    lines = [f"HTTP/1.1 {code}", *headers]
    if encoding is not None:
        lines.append(f"Content-Encoding: {encoding}")
    if framing == "length":
        lines.append(f"Content-Length: {len(payload)}")
    elif framing == "chunked":
        lines.append("Transfer-Encoding: chunked")
        pieces = [payload[i:i + 333] for i in range(0, len(payload), 333)]
        payload = b"".join(b"%x\r\n" % len(p) + p + b"\r\n" for p in pieces) + b"0\r\n\r\n"
    else:
        assert framing == "close"
    return ("\r\n".join(lines) + "\r\n\r\n").encode() + payload


DATA = _text(20_000, seed=31) + random.Random(31).randbytes(1_500)
MEMBER = gzip.compress(DATA, mtime=0)


@pytest.mark.parametrize("framing", ("length", "chunked", "close"))
@pytest.mark.parametrize("chunk", (4096, 7))
def test_a_gzip_body_is_inflated_as_it_arrives(exchange, framing, chunk):
    result = exchange.run(response(MEMBER, framing=framing), capacity=len(DATA) + 100,
                          chunk=chunk)
    assert (result.status, result.coding, result.body_status) == (S_OK, C_GZIP, B_OK)
    assert result.body == DATA


def test_a_gzip_body_arriving_a_byte_at_a_time(exchange):
    data = _text(3_000, seed=32)
    result = exchange.run(response(gzip.compress(data, mtime=0), framing="chunked"),
                          capacity=len(data), chunk=1)
    assert (result.status, result.coding, result.body) == (S_OK, C_GZIP, data)


@pytest.mark.parametrize("name", ("x-gzip", "GZIP", "Gzip"))
def test_gzip_is_named_in_any_case_and_as_x_gzip(exchange, name):
    result = exchange.run(response(MEMBER, encoding=name), capacity=len(DATA))
    assert (result.status, result.coding, result.body) == (S_OK, C_GZIP, DATA)


@pytest.mark.parametrize("encoding", (None, "identity"))
def test_an_identity_body_is_kept_as_it_came(exchange, encoding):
    result = exchange.run(response(DATA, encoding=encoding), capacity=len(DATA))
    assert (result.status, result.coding, result.body) == (S_OK, C_IDENTITY, DATA)


def test_a_gzip_body_not_asked_for_is_kept_as_it_came(exchange):
    result = exchange.run(response(MEMBER), capacity=len(MEMBER), gzip_asked=False)
    assert (result.status, result.coding, result.body) == (S_OK, C_IDENTITY, MEMBER)


@pytest.mark.parametrize("headers, encoding", (
    ((), "br"),
    ((), "gzip, gzip"),
    (("Content-Encoding: gzip",), "gzip"),
))
def test_any_other_coding_is_kept_for_the_caller_to_refuse(exchange, headers, encoding):
    result = exchange.run(response(MEMBER, encoding=encoding, headers=headers),
                          capacity=len(MEMBER))
    assert (result.status, result.coding, result.body) == (S_OK, C_IDENTITY, MEMBER)


def test_a_body_that_inflates_to_exactly_the_buffer_is_taken(exchange):
    for chunk in (4096, 5):
        result = exchange.run(response(MEMBER), capacity=len(DATA), chunk=chunk)
        assert (result.status, result.body_status, result.body) == (S_OK, B_OK, DATA)


def test_a_body_that_inflates_past_the_buffer_is_refused(exchange):
    result = exchange.run(response(MEMBER), capacity=len(DATA) - 1)
    assert (result.status, result.body_status) == (S_PROTOCOL, B_CAPACITY)
    assert result.body == DATA[:-1]
    # A megabyte of zeros sent in about a kilobyte stops at the buffer.
    bomb = gzip.compress(bytes(BYTES), mtime=0)
    assert len(bomb) < 2_000
    result = exchange.run(response(bomb), capacity=65_536)
    assert (result.status, result.body_status, len(result.body)) == (
        S_PROTOCOL, B_CAPACITY, 65_536)


def test_a_body_sent_past_the_buffer_is_refused_though_it_inflates_within(exchange):
    data = random.Random(33).randbytes(8_000)
    stored = _zlib(data, 0, wbits=31)
    assert len(stored) > len(data)
    result = exchange.run(response(stored), capacity=len(data))
    assert (result.status, result.body_status) == (S_PROTOCOL, B_CAPACITY)
    result = exchange.run(response(stored), capacity=len(stored))
    assert (result.status, result.body) == (S_OK, data)


def test_a_damaged_body_is_refused_with_the_inflater_s_reason(exchange):
    damaged = bytearray(MEMBER)
    damaged[-8] ^= 1
    result = exchange.run(response(bytes(damaged)), capacity=len(DATA))
    assert (result.status, result.body_status, result.reason) == (
        S_PROTOCOL, B_DAMAGED, exchange.reasons["SUM"])
    damaged = bytearray(MEMBER)
    damaged[1] ^= 1
    result = exchange.run(response(bytes(damaged)), capacity=len(DATA))
    assert (result.status, result.body_status, result.reason) == (
        S_PROTOCOL, B_DAMAGED, exchange.reasons["HEADER"])


@pytest.mark.parametrize("chunk", (4096, 3))
def test_bytes_after_the_member_are_refused(exchange, chunk):
    for after in (b"x", MEMBER):
        result = exchange.run(response(MEMBER + after), capacity=2 * len(DATA), chunk=chunk)
        assert (result.status, result.body_status) == (S_PROTOCOL, B_TRAILING), (after[:1],)


@pytest.mark.parametrize("framing", ("close", "chunked"))
def test_a_body_cut_inside_its_member_is_refused(exchange, framing):
    for cut in (5, len(MEMBER) // 2, len(MEMBER) - 1):
        result = exchange.run(response(MEMBER[:cut], framing=framing), capacity=len(DATA))
        assert (result.status, result.body_status) == (S_PROTOCOL, B_CUT), cut


@pytest.mark.parametrize("code", ("200 OK", "204 No Content"))
def test_a_gzip_body_of_no_bytes_is_empty(exchange, code):
    result = exchange.run(response(b"", code=code), capacity=16)
    assert (result.status, result.coding, result.body_status, result.body) == (
        S_OK, C_GZIP, B_OK, b"")


def test_each_message_starts_identity(exchange):
    assert exchange.run(response(MEMBER), capacity=len(DATA)).coding == C_GZIP
    result = exchange.run(response(DATA, encoding=None), capacity=len(DATA), again=True)
    assert (result.status, result.coding, result.body_status, result.body) == (
        S_OK, C_IDENTITY, B_OK, DATA)
    damaged = bytearray(MEMBER)
    damaged[-8] ^= 1
    assert exchange.run(response(bytes(damaged)), capacity=len(DATA)).body_status == B_DAMAGED
    result = exchange.run(response(MEMBER), capacity=len(DATA), again=True)
    assert (result.status, result.body_status, result.reason, result.body) == (
        S_OK, B_OK, 0, DATA)
