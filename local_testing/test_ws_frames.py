#!/usr/bin/env python3
"""WebSocket frames on a scripted transport (net/ws.f, RFC 6455).

The suite loads net/ws.f over a stand-in for the HTTP transport: HTTP-SEND
keeps the bytes a frame sends, and HTTP-RECV hands out a script of bytes and
then reports the connection closed.  The stand-ins are defined after
net/http.f and before net/ws.f, so the frame words compile against them.

The cases hold the frame words to their stack comments and to the RFC:

- WS-FRAME-SEND ( ctx opcode payload-a payload-u -- ) writes the header
  for each of the three length encodings and a mask key that the server
  applies as RFC 6455 section 5.3 says, byte i with key byte i mod 4,
  masks the payload as it sends it, across its staging chunks, and leaves
  the caller's bytes as they were;
- WS-FRAME-RECV ( ctx buf max -- opcode buf len ) reads a frame into the
  caller's buffer, unmasks a masked one in network byte order, stops at
  MAX, and answers a ping with a pong of its payload, which the caller
  still reads unmasked;
- WS-RECV ( ctx buf max -- opcode len ) joins a fragmented message and
  reports a close or a closed connection as -1;
- WS-CONNECT ( url-a url-u -- ctx | 0 ) returns one cell when the
  connection cannot be opened.

The transport keeps a window of 256 bytes sent, from offset T-SKIP on,
so a case can read the bytes around a staging chunk's edge.
"""

from __future__ import annotations

import re

from forth_snapshot import (
    ForthSnapshot,
    _source_lines,
    SOURCE_ROOT,
    megapad_module_lines,
    module_source_lines,
    run_file_tests,
    transcript_checks,
)


TRANSPORT = (
    "CREATE T-CAP 256 ALLOT  VARIABLE T-CAP-LEN  VARIABLE T-SENT  VARIABLE T-SKIP",
    "CREATE T-FEED 256 ALLOT  VARIABLE T-FEED-LEN  VARIABLE T-FEED-POS",
    ": TCP-POLL  ( -- ) ;",
    ": NET-IDLE  ( -- ) ;",
    "\\ Keep the 256 bytes sent from offset T-SKIP on, and count them all.",
    ": T-KEEP  ( c -- )",
    "    T-SENT @ T-SKIP @ - DUP 0 256 WITHIN IF",
    "        T-CAP + C!  1 T-CAP-LEN +!",
    "    ELSE 2DROP THEN  1 T-SENT +! ;",
    ": HTTP-SEND  ( buf len -- flag )  0 ?DO DUP I + C@ T-KEEP LOOP DROP -1 ;",
    "\\ A connection that cannot be opened.",
    ": HTTP-CONNECT  ( host-a host-u port tls? -- ctx )  2DROP 2DROP 0 ;",
    "\\ Hand out the scripted bytes, then -1 as a closed connection.",
    ": HTTP-RECV  ( buf max -- n )",
    "    T-FEED-LEN @ T-FEED-POS @ - DUP 0= IF DROP 2DROP -1 EXIT THEN",
    "    MIN T-FEED T-FEED-POS @ + ROT ROT",
    "    DUP >R CMOVE R> DUP T-FEED-POS +! ;",
)

HELPERS = (
    "VARIABLE T-DEPTH",
    ": T{  ( -- )  DEPTH T-DEPTH ! ;",
    ': }T  ( -- )  DEPTH T-DEPTH @ - ." cells=" . ;',
    ": F,  ( c -- )  T-FEED T-FEED-LEN @ + C!  1 T-FEED-LEN +! ;",
    ': CAP.  ( -- )  ." cap:" T-CAP-LEN @ 0 ?DO T-CAP I + C@ . LOOP ;',
    "CREATE T-PAY 256 ALLOT",
    "CREATE T-BUF 64 ALLOT",
    ": T-RESET  ( -- )  0 T-CAP-LEN ! 0 T-SENT ! 0 T-SKIP ! 0 T-FEED-LEN ! 0 T-FEED-POS !",
    "    T-BUF 64 238 FILL ;",
)

SNAPSHOT = ForthSnapshot(
    (),
    prelude=tuple(
        megapad_module_lines("networking.f")
        + module_source_lines(("net/http.f", "net/base64.f"))
        + list(TRANSPORT)
        + _source_lines(SOURCE_ROOT / "net/ws.f")
        + list(HELPERS)
    ),
)

check, check_fn, check_emitted = transcript_checks(SNAPSHOT.run)


def feed(data: bytes) -> str:
    return " ".join(f"{byte} F," for byte in data)


def captured(printed: str) -> list[int]:
    """The bytes CAP. printed, up to the first word that is not one."""
    values = []
    for word in printed.split("cap:", 1)[1].split():
        if not word.lstrip("-").isdigit():
            break
        values.append(int(word))
    return values


def unmasked(frame: list[int], key_at: int) -> bytes:
    key = frame[key_at:key_at + 4]
    payload = frame[key_at + 4:]
    return bytes(byte ^ key[i % 4] for i, byte in enumerate(payload))


def test_send_short_text_frame():
    def sent_hello(printed: str) -> bool:
        if "cells=-4 " not in printed:
            return False
        frame = captured(printed)
        return frame[:2] == [0x81, 0x80 | 5] and unmasked(frame, 2) == b"Hello"

    check_fn("short frame", [
        ': T1  T-RESET S" Hello" T-PAY SWAP CMOVE'
        "      0 1 T-PAY 5 T{ WS-FRAME-SEND }T CAP. ;",
        "T1",
    ], sent_hello, "a FIN text header, the mask bit, length 5 and Hello masked")


def test_send_frame_with_16_bit_length():
    def sent_200(printed: str) -> bool:
        if "cells=-4 " not in printed:
            return False
        frame = captured(printed)
        return (frame[:4] == [0x82, 0xFE, 0, 200]
                and unmasked(frame, 4) == bytes(i & 255 for i in range(200)))

    check_fn("16-bit length", [
        ": T1  T-RESET 200 0 DO I T-PAY I + C! LOOP"
        "      0 2 T-PAY 200 T{ WS-FRAME-SEND }T CAP. ;",
        "T1",
    ], sent_200, "a binary header with 126, length 200 and the bytes masked")


def test_send_frame_with_64_bit_length_stays_in_its_header():
    # The 64-bit length puts the mask key at bytes 10 to 13 of the 14-byte
    # header buffer; the key's store must not write past it.
    def sent_big(printed: str) -> bool:
        match = re.search(r"cells=-4 sent=(\d+) kept=(-?\d+) cap:", printed)
        if not match:
            return False
        frame = captured(printed)
        return (int(match.group(1)) == 14 + 65536 and match.group(2) == "-1"
                and frame[:10] == [0x82, 0xFF, 0, 0, 0, 0, 0, 1, 0, 0]
                and len(frame) == 256)

    check_fn("64-bit length", [
        "VARIABLE T-BIG  65536 ALLOCATE DROP T-BIG !",
        "VARIABLE T-AFTER",
        ": T1  T-RESET _WS-FHDR 14 + @ T-AFTER !"
        "      0 2 T-BIG @ 65536 T{ WS-FRAME-SEND }T"
        '      ." sent=" T-SENT @ .'
        '      ." kept=" _WS-FHDR 14 + @ T-AFTER @ = . CAP. ;',
        "T1",
    ], sent_big, "a 14-byte header with 127 and length 65536, nothing past it")


def test_send_leaves_the_callers_payload():
    def kept(printed: str) -> bool:
        frame = captured(printed)
        return ("payload=Hello" in printed and frame[:2] == [0x81, 0x80 | 5]
                and unmasked(frame, 2) == b"Hello")

    check_fn("payload kept", [
        ': T1  T-RESET S" Hello" T-PAY SWAP CMOVE'
        '      0 1 T-PAY 5 WS-FRAME-SEND ." payload=" T-PAY 5 TYPE CAP. ;',
        "T1",
    ], kept, "Hello still in the caller's buffer and Hello masked on the wire")


def test_send_masks_across_staging_chunks():
    # 1300 bytes go out in staging chunks of 1024; the window holds payload
    # bytes 1000 to 1255 of the frame, whose header and key take 8.
    payload = bytes((i * 7) & 255 for i in range(1300))

    def masked_across(printed: str) -> bool:
        match = re.search(r"sent=(\d+) key:((?:\d+ ){4})cap:", printed)
        if not match:
            return False
        key = [int(v) for v in match.group(2).split()]
        window = captured(printed)
        return (int(match.group(1)) == 8 + 1300 and len(window) == 256
                and all(b ^ key[(1000 + i) % 4] == payload[1000 + i]
                        for i, b in enumerate(window)))

    check_fn("chunks", [
        "VARIABLE T-BIGP  1300 ALLOCATE DROP T-BIGP !",
        ": T1  T-RESET T-BIGP @ 1300 0 DO I 7 * 255 AND OVER I + C! LOOP DROP",
        "      1008 T-SKIP !  0 2 T-BIGP @ 1300 WS-FRAME-SEND",
        '      ." sent=" T-SENT @ . ." key:" 4 0 DO _WS-FHDR 4 + I + C@ . LOOP CAP. ;',
        "T1",
    ], masked_across, "every byte around the chunk edge masked with key byte i mod 4")


def test_receive_unmasked_frame():
    check("unmasked", [
        f": T1  T-RESET {feed(bytes([0x81, 5]) + b'Hello')}"
        "      0 T-BUF 64 T{ WS-FRAME-RECV }T ROT . TYPE ;",
        "T1",
    ], "cells=0 1 Hello")


def test_receive_masked_frame_in_network_order():
    # RFC 6455 section 5.7: "Hello" masked with key 37 fa 21 3d.
    frame = bytes([0x81, 0x85, 0x37, 0xFA, 0x21, 0x3D, 0x7F, 0x9F, 0x4D, 0x51, 0x58])
    check("masked", [
        f": T1  T-RESET {feed(frame)}"
        "      0 T-BUF 64 T{ WS-FRAME-RECV }T ROT . TYPE ;",
        "T1",
    ], "cells=0 1 Hello")


def test_receive_stops_at_the_callers_maximum():
    key = bytes([0x11, 0x22, 0x33, 0x44])
    payload = bytes([1, 2, 3, 4, 5, 6])
    masked = bytes(b ^ key[i % 4] for i, b in enumerate(payload))
    check("four of six bytes", [
        f": T1  T-RESET {feed(bytes([0x82, 0x86]) + key + masked)}"
        "      0 T-BUF 4 T{ WS-FRAME-RECV }T ROT . NIP ."
        "      T-BUF 5 0 DO DUP I + C@ . LOOP DROP ;",
        "T1",
    ], "cells=0 2 4 1 2 3 4 238")


def test_receive_ping_answers_with_a_pong():
    def ponged(printed: str) -> bool:
        if "cells=0 9 0 " not in printed:
            return False
        frame = captured(printed)
        return frame[:2] == [0x8A, 0x80] and len(frame) == 6

    check_fn("ping", [
        f": T1  T-RESET {feed(bytes([0x89, 0]))}"
        "      0 T-BUF 64 T{ WS-FRAME-RECV }T ROT . NIP . CAP. ;",
        "T1",
    ], ponged, "a masked empty pong")


def test_receive_ping_payload_stays_unmasked_for_the_caller():
    def echoed(printed: str) -> bool:
        frame = captured(printed)
        return ("cells=0 9 ping" in printed and frame[:2] == [0x8A, 0x84]
                and unmasked(frame, 2) == b"ping")

    check_fn("ping payload", [
        f": T1  T-RESET {feed(bytes([0x89, 4]) + b'ping')}"
        "      0 T-BUF 64 T{ WS-FRAME-RECV }T ROT . TYPE CAP. ;",
        "T1",
    ], echoed, "the ping read as ping and a masked pong of it")


def test_recv_joins_fragments():
    frames = bytes([0x01, 3]) + b"abc" + bytes([0x80, 2]) + b"de"
    check("fragmented text", [
        f": T1  T-RESET {feed(frames)}"
        "      0 T-BUF 64 T{ WS-RECV }T . . T-BUF 5 TYPE ;",
        "T1",
    ], "cells=-1 5 1 abcde")


def test_recv_reports_close_and_closed_connection():
    check("close frame", [
        f": T1  T-RESET {feed(bytes([0x88, 0]))}"
        "      0 T-BUF 64 T{ WS-RECV }T . . ;",
        "T1",
    ], "cells=-1 0 -1")
    check("closed connection", [
        ": T1  T-RESET 0 T-BUF 64 T{ WS-RECV }T . . ;",
        "T1",
    ], "cells=-1 0 -1")


def test_connect_that_cannot_open_returns_one_cell():
    check("no connection", [
        ': T1  S" ws://example.org/x" T{ WS-CONNECT }T ." ctx=" .'
        '      WS-ERR @ WS-E-CONNECT = ." err=" . ;',
        "T1",
    ], "cells=-1 ctx=0 err=-1")


if __name__ == "__main__":
    run_file_tests(__file__)
