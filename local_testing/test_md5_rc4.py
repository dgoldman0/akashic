#!/usr/bin/env python3
"""Akashic math/md5.f and math/rc4.f against Python.

MD5 must agree with hashlib on short, block-edge and long inputs, summed
whole and in pieces of every size.  RC4 must agree with a reference written
from the algorithm and with the published test vectors, across calls that
continue one stream, with keys of every length PDF uses.
"""

from __future__ import annotations

import hashlib
import random

import pytest

from forth_dependencies import dependency_order
from test_uidl_collection_snapshot import AK, KDOS_PATH, _load_forth_lines
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime

BYTES = 2 << 20


class Machine:
    def __init__(self):
        self.runtime = MegaForthRuntime(
            memory=create_one_core_address_space(external_size=16 << 20, hbw_size=1 << 20),
            execution_backend="native",
        )
        self.runtime.evaluate(KDOS_PATH.read_bytes(), source_name="kdos.f")
        self.runtime.evaluate(b"ENTER-USERLAND", source_name="userland")
        source = []
        for module in dependency_order(AK, ("math/md5.f", "math/rc4.f")):
            source.extend(_load_forth_lines(AK / module))
        source += [
            f"{BYTES} XBUF MR-DATA",
            "64 XBUF MR-OUT",
            "CREATE MR-MD5S MD5-SIZE 7 + ALLOT  : MR-MD5  MR-MD5S 7 + -8 AND ;",
            "CREATE MR-RC4S RC4-SIZE 7 + ALLOT  : MR-RC4  MR-RC4S 7 + -8 AND ;",
            "512 XBUF MR-KEY",
        ]
        self.runtime.evaluate(("\n".join(source) + "\n").encode(), source_name="md5-rc4",
                              step_budget=50_000_000)
        self.runtime.drain_uart_output()
        self.data, self.out, self.key, self.md5_record, self.rc4_record = (
            self.word(name) for name in ("MR-DATA", "MR-OUT", "MR-KEY", "MR-MD5", "MR-RC4"))

    def word(self, name: str) -> int:
        self.runtime.execute(name)
        return self.runtime.main_context.data.pop()

    def call(self, name: str, *args: int) -> None:
        stack = self.runtime.main_context.data
        assert stack.depth() == 0
        for value in args:
            stack.push(value)
        self.runtime.execute(name, step_budget=2_000_000_000)
        assert stack.depth() == 0, name

    def md5(self, data: bytes, pieces: list[int] | None = None) -> bytes:
        self.runtime.memory.write_bytes(self.data, data)
        if pieces is None:
            self.call("MD5", self.data, len(data), self.out)
        else:
            self.call("MD5-INIT", self.md5_record)
            position = 0
            for size in pieces:
                self.call("MD5-UPDATE", self.data + position, size, self.md5_record)
                position += size
            assert position == len(data)
            self.call("MD5-FINAL", self.out, self.md5_record)
        return self.runtime.memory.read_bytes(self.out, 16)

    def rc4(self, key: bytes, data: bytes, pieces: list[int] | None = None) -> bytes:
        self.runtime.memory.write_bytes(self.key, key)
        self.runtime.memory.write_bytes(self.data, data)
        self.call("RC4-INIT", self.key, len(key), self.rc4_record)
        position = 0
        for size in pieces or [len(data)]:
            self.call("RC4-XOR", self.data + position, size, self.rc4_record)
            position += size
        return self.runtime.memory.read_bytes(self.data, len(data))


@pytest.fixture(scope="module")
def machine():
    return Machine()


def reference_rc4(key: bytes, data: bytes) -> bytes:
    s = list(range(256))
    j = 0
    for i in range(256):
        j = (j + s[i] + key[i % len(key)]) & 255
        s[i], s[j] = s[j], s[i]
    i = j = 0
    out = bytearray()
    for byte in data:
        i = (i + 1) & 255
        j = (j + s[i]) & 255
        s[i], s[j] = s[j], s[i]
        out.append(byte ^ s[(s[i] + s[j]) & 255])
    return bytes(out)


@pytest.mark.parametrize("size", (0, 1, 3, 55, 56, 57, 63, 64, 65, 119, 120, 128, 1000))
def test_md5_agrees_with_hashlib(machine, size):
    data = random.Random(size).randbytes(size)
    assert machine.md5(data) == hashlib.md5(data).digest()


def test_md5_of_the_rfc_examples(machine):
    for text, digest in ((b"", "d41d8cd98f00b204e9800998ecf8427e"),
                         (b"abc", "900150983cd24fb0d6963f7d28e17f72"),
                         (b"message digest", "f96b697d7cb7938d525a2f31aaf161d0")):
        assert machine.md5(text).hex() == digest


def test_md5_summed_in_pieces(machine):
    rng = random.Random(7)
    data = rng.randbytes(5_000)
    for _ in range(8):
        pieces, left = [], len(data)
        while left:
            size = min(left, rng.choice((1, 3, 63, 64, 65, rng.randint(1, 700))))
            pieces.append(size)
            left -= size
        assert machine.md5(data, pieces) == hashlib.md5(data).digest()


def test_md5_of_a_megabyte(machine):
    data = random.Random(9).randbytes(1 << 20)
    assert machine.md5(data) == hashlib.md5(data).digest()


def test_rc4_matches_the_published_vectors(machine):
    for key, text, cipher in ((b"Key", b"Plaintext", "bbf316e8d940af0ad3"),
                              (b"Wiki", b"pedia", "1021bf0420"),
                              (b"Secret", b"Attack at dawn", "45a01f645fc35b383552544b9bf5")):
        assert machine.rc4(key, text).hex() == cipher


@pytest.mark.parametrize("key_size", (1, 5, 7, 10, 16, 32, 255, 256))
def test_rc4_agrees_with_the_reference(machine, key_size):
    rng = random.Random(key_size)
    key, data = rng.randbytes(key_size), rng.randbytes(3_000)
    assert machine.rc4(key, data) == reference_rc4(key, data)


def test_rc4_stream_continues_across_calls(machine):
    rng = random.Random(11)
    key, data = rng.randbytes(16), rng.randbytes(2_000)
    pieces = [1, 255, 256, 7, 481, 1000]
    assert machine.rc4(key, data, pieces) == reference_rc4(key, data)


def test_rc4_decrypts_what_it_encrypts(machine):
    key, data = b"\x01\x02\x03\x04\x05", b"PDF strings are encrypted per object."
    assert machine.rc4(key, machine.rc4(key, data)) == data
