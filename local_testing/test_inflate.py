#!/usr/bin/env python3
"""Akashic utils/inflate.f against Python's zlib.

Streams Python's zlib makes, at every level and strategy and in each
wrapper, decode to the same bytes, fed whole, a byte at a time, and in
random pieces, into output of every size down to one byte.  Damaged
streams are refused with their reason, a cut stream never ends, and input
after a stream's end is not counted as used.
"""

from __future__ import annotations

import gzip
import random
import struct
import zlib

import pytest

from forth_dependencies import dependency_order
from test_uidl_collection_snapshot import AK, KDOS_PATH, _load_forth_lines
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime

IN_BYTES = 2 << 20
OUT_BYTES = 4 << 20
RAW, ZLIB, GZIP = 0, 1, 2
MORE, FULL, DONE, BAD = 0, 1, 2, 3


class Inflater:
    def __init__(self):
        self.runtime = MegaForthRuntime(
            memory=create_one_core_address_space(external_size=32 << 20, hbw_size=1 << 20),
            execution_backend="native",
        )
        self.runtime.evaluate(KDOS_PATH.read_bytes(), source_name="kdos.f")
        self.runtime.evaluate(b"ENTER-USERLAND", source_name="userland")
        source = []
        for module in dependency_order(AK, ("utils/inflate.f",)):
            source.extend(_load_forth_lines(AK / module))
        source += [
            f"{IN_BYTES} XBUF IT-IN",
            f"{OUT_BYTES} XBUF IT-OUT",
            "32768 XBUF IT-WIN",
            "CREATE IT-REC INFL-SIZE 7 + ALLOT",
            ": IT-R  IT-REC 7 + -8 AND ;",
        ]
        self.runtime.evaluate(("\n".join(source) + "\n").encode(), source_name="inflate",
                              step_budget=50_000_000)
        self.runtime.drain_uart_output()
        self.input = self.word("IT-IN")
        self.output = self.word("IT-OUT")
        self.window = self.word("IT-WIN")
        self.record = self.word("IT-R")
        self.reasons = {name: self.word(f"INFL-R-{name}") for name in (
            "HEADER", "WINDOW", "DICTIONARY", "BLOCK", "STORED", "CODES", "SYMBOL",
            "DISTANCE", "SUM", "LENGTH")}

    def word(self, name: str) -> int:
        self.runtime.execute(name)
        value = self.runtime.main_context.data.pop()
        assert self.runtime.main_context.data.depth() == 0
        return value

    def call(self, name: str, *args: int) -> tuple[int, ...]:
        stack = self.runtime.main_context.data
        assert stack.depth() == 0
        for value in args:
            stack.push(value)
        self.runtime.execute(name, step_budget=2_000_000_000)
        result = stack.snapshot()
        while stack.depth():
            stack.pop()
        return tuple(result)

    def inflate(self, data: bytes, wrapper: int, *, window: int = 32768,
                in_chunk: int | None = None, out_chunk: int | None = None,
                out_cap: int = OUT_BYTES, rng: random.Random | None = None):
        """Feed DATA in pieces; return (output, last status, reason, input used)."""

        assert len(data) <= IN_BYTES
        self.runtime.memory.write_bytes(self.input, data)
        self.call("INFL-INIT", self.window, window, wrapper, self.record)
        position = produced = 0
        while True:
            take = len(data) - position
            if in_chunk is not None:
                take = min(take, in_chunk if rng is None else rng.randint(1, in_chunk))
            room = out_cap - produced
            if out_chunk is not None:
                room = min(room, out_chunk if rng is None else rng.randint(1, out_chunk))
            used, given, status = self.call("INFL-FEED", self.input + position, take,
                                            self.output + produced, room, self.record)
            assert 0 <= used <= take and 0 <= given <= room, (used, take, given, room)
            position += used
            produced += given
            if status in (DONE, BAD):
                break
            if status == MORE:
                assert used == take
                if position == len(data):
                    break
            if status == FULL:
                assert given == room
                if produced == out_cap:
                    break
        reason = self.call("INFL-REASON@", self.record)[0]
        output = self.runtime.memory.read_bytes(self.output, produced)
        return output, status, reason, position


@pytest.fixture(scope="module")
def inflater():
    return Inflater()


def _zlib(data: bytes, level: int = 6, strategy: int = zlib.Z_DEFAULT_STRATEGY,
          wbits: int = 15) -> bytes:
    compressor = zlib.compressobj(level, zlib.DEFLATED, wbits, 9, strategy)
    return compressor.compress(data) + compressor.flush()


def _text(size: int, seed: int = 1) -> bytes:
    rng = random.Random(seed)
    words = [b"deflate", b"zlib", b"window", b"Huffman", b"distance", b"length",
             b"block", b"literal", b"the", b"of", b"a", b"stream", b"\n"]
    out = bytearray()
    while len(out) < size:
        out += rng.choice(words) + b" "
    return bytes(out[:size])


def test_an_empty_stream_and_a_short_one(inflater):
    for data in (b"", b"a", b"hello, world"):
        for wrapper, stream in ((ZLIB, _zlib(data)), (RAW, _zlib(data, wbits=-15)),
                                (GZIP, gzip.compress(data, mtime=0))):
            output, status, reason, used = inflater.inflate(stream, wrapper)
            assert (status, reason) == (DONE, 0), (data, wrapper)
            assert output == data and used == len(stream)


STRATEGIES = (zlib.Z_DEFAULT_STRATEGY, zlib.Z_FILTERED, zlib.Z_HUFFMAN_ONLY, zlib.Z_RLE,
              zlib.Z_FIXED)


@pytest.mark.parametrize("level", range(10))
def test_every_level_and_strategy_in_each_wrapper(inflater, level):
    data = _text(40_000, seed=level) + random.Random(level).randbytes(3_000)
    for strategy in STRATEGIES:
        streams = ((ZLIB, _zlib(data, level, strategy)),
                   (RAW, _zlib(data, level, strategy, wbits=-15)),
                   (GZIP, _zlib(data, level, strategy, wbits=31)))
        for wrapper, stream in streams:
            output, status, reason, used = inflater.inflate(stream, wrapper)
            assert (status, reason, used) == (DONE, 0, len(stream)), (level, strategy, wrapper)
            assert output == data


@pytest.mark.parametrize("in_chunk, out_chunk", ((1, None), (None, 1), (7, 3), (4096, 1)))
def test_fed_in_pieces_into_output_of_every_size(inflater, in_chunk, out_chunk):
    data = _text(6_000, seed=3) + b"\x00" * 700 + random.Random(3).randbytes(500)
    for wrapper, stream in ((ZLIB, _zlib(data, 9)), (GZIP, _zlib(data, 1, wbits=31)),
                            (RAW, _zlib(data, 0, wbits=-15))):
        output, status, reason, used = inflater.inflate(
            stream, wrapper, in_chunk=in_chunk, out_chunk=out_chunk)
        assert (status, reason, used, output) == (DONE, 0, len(stream), data)


def test_fed_in_random_pieces(inflater):
    rng = random.Random(11)
    for trial in range(6):
        data = _text(rng.randint(1, 30_000), seed=trial) + rng.randbytes(rng.randint(0, 2000))
        stream = _zlib(data, rng.randint(0, 9), rng.choice(STRATEGIES))
        output, status, reason, used = inflater.inflate(
            stream, ZLIB, in_chunk=rng.randint(1, 600), out_chunk=rng.randint(1, 900), rng=rng)
        assert (status, reason, output) == (DONE, 0, data), trial


def test_the_longest_matches_and_the_farthest_distance(inflater):
    run = b"x" * 100_000
    block = random.Random(5).randbytes(32_768)
    for data in (run, block + block, b"ab" * 40_000):
        stream = _zlib(data, 9)
        output, status, reason, _ = inflater.inflate(stream, ZLIB, out_chunk=1000)
        assert (status, reason, output) == (DONE, 0, data)


def test_stored_blocks_of_the_largest_size(inflater):
    data = random.Random(9).randbytes(200_000)
    stream = _zlib(data, 0)
    output, status, reason, used = inflater.inflate(stream, ZLIB, in_chunk=40_000)
    assert (status, reason, used, output) == (DONE, 0, len(stream), data)


@pytest.mark.parametrize("wbits", range(9, 16))
def test_a_window_as_large_as_the_stream_asks(inflater, wbits):
    data = _text(20_000, seed=wbits) * 2
    stream = _zlib(data, 9, wbits=wbits)
    output, status, reason, _ = inflater.inflate(stream, ZLIB, window=1 << wbits)
    assert (status, reason, output) == (DONE, 0, data)
    if wbits > 9:
        _, status, reason, _ = inflater.inflate(stream, ZLIB, window=1 << (wbits - 1))
        assert (status, reason) == (BAD, inflater.reasons["WINDOW"])


@pytest.mark.parametrize("window", (100, 300, 65536))
def test_a_window_that_is_no_power_of_two_in_range_is_refused(inflater, window):
    _, status, reason, used = inflater.inflate(_zlib(b"abc"), ZLIB, window=window)
    assert (status, reason, used) == (BAD, inflater.reasons["WINDOW"], 0)


def _gzip_member(data: bytes, *, name: bytes = b"", comment: bytes = b"",
                 extra: bytes = b"", hcrc: bool = False) -> bytes:
    flags = (4 if extra else 0) | (8 if name else 0) | (16 if comment else 0) | (2 if hcrc else 0)
    header = bytearray(b"\x1f\x8b\x08" + bytes([flags]) + b"\x00\x00\x00\x00\x00\xff")
    if extra:
        header += struct.pack("<H", len(extra)) + extra
    if name:
        header += name + b"\x00"
    if comment:
        header += comment + b"\x00"
    if hcrc:
        header += struct.pack("<H", zlib.crc32(header) & 0xFFFF)
    return (bytes(header) + _zlib(data, 6, wbits=-15)
            + struct.pack("<II", zlib.crc32(data), len(data) & 0xFFFFFFFF))


def test_a_gzip_header_s_fields_are_skipped_and_its_crc_checked(inflater):
    data = _text(5_000, seed=8)
    member = _gzip_member(data, name=b"notes.txt", comment=b"a comment",
                          extra=b"AB\x02\x00xy", hcrc=True)
    for in_chunk in (None, 1):
        output, status, reason, _ = inflater.inflate(member, GZIP, in_chunk=in_chunk)
        assert (status, reason, output) == (DONE, 0, data)
    damaged = bytearray(member)
    damaged[12] ^= 1                  # a byte of the extra field, under the header CRC
    _, status, reason, _ = inflater.inflate(bytes(damaged), GZIP)
    assert (status, reason) == (BAD, inflater.reasons["HEADER"])


def test_input_after_the_stream_is_not_used(inflater):
    data = _text(3_000, seed=4)
    for wrapper, stream in ((ZLIB, _zlib(data)), (GZIP, gzip.compress(data, mtime=0)),
                            (RAW, _zlib(data, wbits=-15))):
        for in_chunk in (None, 5):
            output, status, reason, used = inflater.inflate(stream + b"TRAILING", wrapper,
                                                            in_chunk=in_chunk)
            assert (status, reason, used, output) == (DONE, 0, len(stream), data)


def test_a_cut_stream_never_ends(inflater):
    data = _text(8_000, seed=6)
    for wrapper, stream in ((ZLIB, _zlib(data)), (GZIP, gzip.compress(data, mtime=0)),
                            (RAW, _zlib(data, wbits=-15))):
        for cut in (1, len(stream) // 2, len(stream) - 1):
            _, status, _, used = inflater.inflate(stream[:cut], wrapper)
            assert (status, used) == (MORE, cut), (wrapper, cut)


def test_a_finished_stream_stays_finished(inflater):
    stream = _zlib(b"done")
    inflater.inflate(stream, ZLIB)
    assert inflater.call("INFL-FEED", inflater.input, len(stream), inflater.output, 100,
                         inflater.record) == (0, 0, DONE)


def _raw_fixed(bits: str) -> bytes:
    """Bits, first read first, packed into bytes."""

    value = sum(1 << i for i, bit in enumerate(bits) if bit == "1")
    return value.to_bytes((len(bits) + 7) // 8, "little")


def test_damaged_streams_are_refused_with_their_reason(inflater):
    r = inflater.reasons
    good = _zlib(_text(2_000, seed=2), 9)
    cases = [
        (bytes([0x78, 0x9D]) + good[2:], ZLIB, r["HEADER"]),          # check bits wrong
        (bytes([0x78, 0xBB]) + b"\x00" * 4 + good[2:], ZLIB, r["DICTIONARY"]),
        (good[:-1] + bytes([good[-1] ^ 1]), ZLIB, r["SUM"]),
        (_raw_fixed("1" + "11"), RAW, r["BLOCK"]),                     # block type 3
        (bytes([0x01, 0x05, 0x00, 0x05, 0x00]) + b"hello", RAW, r["STORED"]),
        # A fixed block whose first symbol is a length: no byte to refer to.
        (_raw_fixed("1" + "10" + "0000001" + "00000"), RAW, r["DISTANCE"]),
        # A fixed block with the unused length symbol 286 (11000110).
        (_raw_fixed("1" + "10" + "11000110"), RAW, r["SYMBOL"]),
    ]
    for stream, wrapper, reason in cases:
        _, status, got, _ = inflater.inflate(stream, wrapper)
        assert (status, got) == (BAD, reason), (stream.hex(), wrapper)
    member = bytearray(gzip.compress(b"payload", mtime=0))
    member[-8] ^= 1
    assert inflater.inflate(bytes(member), GZIP)[1:3] == (BAD, r["SUM"])
    member = bytearray(gzip.compress(b"payload", mtime=0))
    member[-1] ^= 1
    assert inflater.inflate(bytes(member), GZIP)[1:3] == (BAD, r["LENGTH"])
    assert inflater.inflate(b"\x1f\x8c" + bytes(8), GZIP)[1:3] == (BAD, r["HEADER"])


def test_code_lengths_that_make_no_prefix_code_are_refused(inflater):
    # A dynamic block whose code-length code gives every symbol one bit.
    bits = "1" + "01" + "00000" + "00000" + "1111" + "001" * 19
    _, status, reason, _ = inflater.inflate(_raw_fixed(bits), RAW)
    assert (status, reason) == (BAD, inflater.reasons["CODES"])


def _far_reference(size: int) -> tuple[bytes, bytes]:
    """A raw stream of SIZE stored bytes, then a fixed block whose one pair
    copies three bytes from 32,768 back: distance code 29 with all thirteen
    extra bits set.  Zlib's own compressor never reaches that far."""

    data = random.Random(size).randbytes(size)
    stored = b"\x00" + struct.pack("<HH", size, size ^ 0xFFFF) + data
    bits = "1" + "10" + "0000001" + "11101" + "1" * 13 + "0000000"
    return stored + _raw_fixed(bits), data + data[size - 32_768:size - 32_768 + 3]


def test_a_reference_32768_bytes_back(inflater):
    stream, expected = _far_reference(32_768)
    for out_chunk in (None, 2):
        output, status, reason, _ = inflater.inflate(stream, RAW, out_chunk=out_chunk)
        assert (status, reason, output) == (DONE, 0, expected)
    _, status, reason, _ = inflater.inflate(stream, RAW, window=16_384)
    assert (status, reason) == (BAD, inflater.reasons["WINDOW"])


def test_with_no_window_the_output_is_the_window(inflater):
    data = _text(40_000, seed=21) + random.Random(21).randbytes(3_000) + b"\x00" * 5_000
    for level in (0, 1, 6, 9):
        for wrapper, stream in ((ZLIB, _zlib(data, level)), (RAW, _zlib(data, level, wbits=-15)),
                                (GZIP, _zlib(data, level, wbits=31))):
            output, status, reason, used = inflater.inflate(stream, wrapper, window=0)
            assert (status, reason, used) == (DONE, 0, len(stream)), (level, wrapper)
            assert output == data


@pytest.mark.parametrize("in_chunk, out_chunk", ((1, None), (None, 1), (7, 3)))
def test_with_no_window_fed_in_pieces(inflater, in_chunk, out_chunk):
    data = _text(6_000, seed=3) + b"\x00" * 700 + random.Random(3).randbytes(500)
    for wrapper, stream in ((ZLIB, _zlib(data, 9)), (GZIP, _zlib(data, 1, wbits=31)),
                            (RAW, _zlib(data, 0, wbits=-15))):
        output, status, reason, used = inflater.inflate(
            stream, wrapper, window=0, in_chunk=in_chunk, out_chunk=out_chunk)
        assert (status, reason, used, output) == (DONE, 0, len(stream), data)


def test_with_no_window_a_reference_reaches_back_into_the_output(inflater):
    stream, expected = _far_reference(32_768)
    for out_chunk in (None, 2):
        output, status, reason, _ = inflater.inflate(stream, RAW, window=0, out_chunk=out_chunk)
        assert (status, reason, output) == (DONE, 0, expected)


def test_with_no_window_each_feed_s_room_follows_the_output(inflater):
    stream = _zlib(_text(5_000, seed=5))
    inflater.runtime.memory.write_bytes(inflater.input, stream)
    # Before the stream gives a byte, any room begins it.
    inflater.call("INFL-INIT", 0, 0, ZLIB, inflater.record)
    assert inflater.call("INFL-FEED", inflater.input, 2, inflater.output + 64, 100,
                         inflater.record) == (2, 0, MORE)
    used, given, status = inflater.call("INFL-FEED", inflater.input + 2, len(stream) - 2,
                                        inflater.output, 1_000, inflater.record)
    assert (given, status) == (1_000, FULL)
    # Room that leaves a gap after the output is refused.
    assert inflater.call("INFL-FEED", inflater.input + 2 + used, len(stream) - 2 - used,
                         inflater.output + 1_001, 1_000, inflater.record) == (0, 0, BAD)
    assert inflater.call("INFL-REASON@", inflater.record) == (inflater.reasons["WINDOW"],)
