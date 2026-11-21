#!/usr/bin/env python3
"""CASE defaults that keep their word's stack effect (math, interop, net, keys, widgets).

BIOS's ENDCASE drops the selector, so a CASE default must leave its
selector on top, as ``value SWAP`` does, for the default to have the
effect of the other branches.  The stack-effect checker of
toolchain/language reports a word whose default dropped the selector, or
pushed nothing, as a result depth that varies; reading every default
found more that left the right depth with the wrong cells.  Each case
here feeds the word a selector none of its branches name and checks the
cells it leaves:

- TRIG-SINCOS and F32T-SINCOS serve quadrant 3 from the default;
- COLOR-HSV>RGB's sector 5 returned the sector as its red channel;
- the ANOVA group store and fetch kept or gave no cells for a seventh
  group;
- the PNG header refused no colour type it does not know;
- the JSON value decoder, the MCP server's status text and dispatch,
  the MCP bus status, the authority table's grant states and the value
  copier returned the wrong number of cells;
- the HTTP resource poll faulted the phase number as a resource, and the
  connection step returned the connection under its status;
- the Rabbit builder's and router's owned spans and capability names;
- the key decoder wrote an unknown CSI or SS3 key's event through its
  selector, and an ESC O with no final byte through a stray 0;
- the text grid's handler and navigation, and the field widget's value.

Where the selector cannot reach the default through the word's callers,
a copy of the word's own source text is compiled over a stand-in for the
check that guards it, so the default runs as written.
"""

from __future__ import annotations

import re

from forth_snapshot import SOURCE_ROOT, ForthSnapshot, run_file_tests, transcript_checks


DEPTH = (
    "VARIABLE T-DEPTH",
    ": T{  ( -- )  DEPTH T-DEPTH ! ;",
    ': }T  ( -- )  DEPTH T-DEPTH @ - ." cells=" . ;',
)


def definition(module: str, name: str) -> list[str]:
    """The lines of NAME's colon definition in MODULE, as the source has them."""
    text = (SOURCE_ROOT / module).read_text(encoding="utf-8")
    match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", text)
    assert match, (module, name)
    return match.group().splitlines()


def numbers(printed: str, *names: str) -> dict[str, int]:
    """The integers printed after each NAME=, as a dictionary."""
    found = {}
    for name in names:
        match = re.search(rf"{re.escape(name)}=(-?\d+)", printed)
        if match:
            found[name] = int(match.group(1))
    return found


# ---------------------------------------------------------------------
# Math and the PNG header
# ---------------------------------------------------------------------

MATH = ForthSnapshot(
    ("math/trig.f", "math/fp32-trig.f", "math/color.f", "math/advanced-stats.f",
     "render/png.f"),
    prelude=DEPTH + (
        ": T-K16  ( fp16 -- n )  1000 INT>FP16 FP16-MUL FP16>INT ;",
        ": T-K32  ( fp32 -- n )  1000 INT>FP32 FP32-MUL FP32>INT ;",
        ": T-C100  ( fp16 -- n )  100 INT>FP16 FP16-MUL FP16>INT ;",
        "CREATE T-DEC 1 PNG-DEC-SIZE ALLOT",
        "\\ A one-pixel picture's header with depth 8 and colour type COLOUR.",
        ": T-IHDR  ( colour -- )  1 T-DEC PNG-DEC-INIT",
        "    _PN-STAGED 13 0 FILL  1 _PN-STAGED 3 + C!  1 _PN-STAGED 7 + C!",
        "    8 _PN-STAGED 8 + C!  _PN-STAGED 9 + C! ;",
    ),
)

math_check, math_check_fn, _ = transcript_checks(MATH.run)


def _near(printed: str, expected: dict[str, int], slack: int) -> bool:
    got = numbers(printed, *expected)
    return (len(got) == len(expected)
            and all(abs(got[k] - v) <= slack for k, v in expected.items()))


def test_sincos_serves_quadrant_three_from_the_default():
    # 5.0 radians lies in [3pi/2, 2pi): sin -0.9589, cos 0.2837.
    math_check_fn("FP16", [
        ': T1  0x4500 T{ TRIG-SINCOS }T T-K16 ." cos=" . T-K16 ." sin=" . ;',
        "T1",
    ], lambda p: "cells=1 " in p and _near(p, {"cos": 284, "sin": -959}, 6),
        "two cells, cos 0.284 and sin -0.959")
    math_check_fn("FP32", [
        ': T1  0x40A00000 T{ F32T-SINCOS }T T-K32 ." cos=" . T-K32 ." sin=" . ;',
        "T1",
    ], lambda p: "cells=1 " in p and _near(p, {"cos": 283, "sin": -958}, 2),
        "two cells, cos 0.2837 and sin -0.9589")


def test_hsv_sector_five_returns_value_p_and_q():
    # h 0.9 is sector 5 with fraction 0.4: (V, p, q) = (1.0, 0.0, 0.6).
    math_check_fn("sector 5", [
        ": T1  0x3B33 0x3C00 0x3C00 T{ COLOR-HSV>RGB }T"
        '      T-C100 ." b=" . T-C100 ." g=" . T-C100 ." r=" . ;',
        "T1",
    ], lambda p: "cells=0 " in p and _near(p, {"r": 100, "g": 0, "b": 60}, 1),
        "three cells, red 1.0, green 0 and blue 0.6")


def test_anova_groups_past_the_sixth():
    math_check("seventh group", [
        ": T1  11 22 6 T{ _AN-SET-GROUP }T"
        '      6 T{ _AN-GET-GROUP }T ." n=" . ." g=" .'
        '      33 44 2 _AN-SET-GROUP 2 _AN-GET-GROUP ." n2=" . ." g2=" . ;',
        "T1",
    ], "cells=-3 cells=1 n=0 g=0 n2=44 g2=33")


def test_png_header_refuses_an_unknown_colour_type():
    lines = [": _PN-DEPTH-OK?  ( depth colour -- flag )  2DROP -1 ;"]
    lines += definition("render/png.f", "_PN-IHDR")
    math_check("colour type 5", lines + [
        ': T1  5 T-IHDR T{ _PN-IHDR }T ." ok=" . ;',
        "T1",
    ], "cells=1 ok=0")
    math_check("colour type 2", lines + [
        ': T1  2 T-IHDR T{ _PN-IHDR }T ." ok=" . _PN.BPP _PN@ ." bpp=" . ;',
        "T1",
    ], "cells=1 ok=-1 bpp=3")


# ---------------------------------------------------------------------
# Interop: JSON values, MCP, the authority table, value copies
# ---------------------------------------------------------------------

INTEROP = ForthSnapshot(
    ("interop/codecs/json-value.f", "interop/mcp/server.f",
     "interop/mcp/component-adapter.f", "interop/authority.f", "interop/value.f"),
    prelude=DEPTH + (
        "CREATE T-V CV-SIZE ALLOT  T-V CV-INIT",
        "CREATE T-S CV-SIZE ALLOT  T-S CV-INIT",
        "CREATE T-D CV-SIZE ALLOT  T-D CV-INIT",
        "CREATE T-IN 256 ALLOT  VARIABLE T-IN-U",
        ": T-C,  ( c -- )  T-IN T-IN-U @ + C!  1 T-IN-U +! ;",
        "CREATE T-OUT 1024 ALLOT",
        "VARIABLE T-SRV",
        ': T-SRV-NEW  ( -- )  S" t" S" 1" MCP-SERVER-NEW DROP T-SRV ! ;',
        "CREATE T-BIND AUTH-BINDING-SIZE ALLOT",
        "CREATE T-GRANT AUTH-GRANT-SIZE ALLOT",
        "CREATE T-HANDLE INVOCATION-HANDLE-SIZE ALLOT",
        "VARIABLE T-TABLE",
        "\\ A table holding one grant issued for T-BIND, and its handle.",
        ": T-AUTH  ( -- )",
        "    7 99 AHT-NEW DROP T-TABLE !",
        "    T-BIND ABIND-INIT  7 T-BIND ABIND.EPOCH !  1 T-BIND ABIND.PRINCIPAL !",
        "    2 T-BIND ABIND.TARGET-ID !  3 T-BIND ABIND.TARGET-GEN !",
        '    S" op" T-BIND ABIND-OP! DROP  1 T-BIND ABIND.INVOCATION-ID !',
        "    T-GRANT AGR-INIT  T-BIND T-GRANT AGR-BIND! DROP",
        '    T-GRANT T-HANDLE T-TABLE @ AHT-ISSUE ." issued=" . ;',
    ),
)

interop_check, interop_check_fn, _ = transcript_checks(INTEROP.run)


def feed(data: bytes) -> list[str]:
    """Lines that append DATA to T-IN, a few dozen bytes to a line."""
    words = [f"{byte} T-C," for byte in data]
    return ["0 T-IN-U !"] + [" ".join(words[i:i + 12]) for i in range(0, len(words), 12)]


def test_json_value_decoder_refuses_an_unknown_type():
    interop_check("@", [
        ': T1  S" @" T-V T{ _IVJD-VALUE-R }T IVJSON-E-INVALID = ." invalid=" . ;',
        "T1",
    ], "cells=-2 invalid=-1")


def test_mcp_status_text_for_an_unlisted_status():
    interop_check("status 999", [
        ": T1  999 T{ _MS-STATUS-TEXT }T TYPE ;",
        "T1",
    ], "cells=1 Tool call failed")


def test_mcp_server_answers_a_result_message_with_an_error():
    message = b'{"jsonrpc":"2.0","id":1,"result":{}}'
    interop_check_fn("result message", feed(message) + [
        "T-SRV-NEW",
        ": T1  T-IN T-IN-U @ T-OUT 1024 T-SRV @ T{ MCP-SERVER-HANDLE }T",
        '      ." status=" . T-OUT SWAP TYPE ;',
        "T1",
    ], lambda p: "cells=-3 status=0 " in p and "Invalid Request" in p,
        "two cells, status 0 and an Invalid Request error")


def test_mcp_bus_status_for_an_unlisted_status():
    interop_check("status 999", [
        ': T1  999 T{ _MCPA-BUS-STATUS }T MCP-S-FAILED = ." failed=" . ;',
        "T1",
    ], "cells=0 failed=-1")


def test_authority_resolve_refuses_a_grant_in_an_unknown_state():
    interop_check("active grant", [
        ': T1  T-AUTH 0 T-BIND T-HANDLE T-TABLE @ T{ AHT-RESOLVE }T ." status=" . 0<> ." grant=" . ;',
        "T1",
    ], "issued=0 cells=-2 status=0 grant=-1")
    interop_check("state 99", [
        ": T1  T-AUTH 99 0 T-TABLE @ AHT-GRANT-NTH AGR.STATE !",
        '      0 T-BIND T-HANDLE T-TABLE @ T{ AHT-RESOLVE }T ." status=" . ." grant=" . ;',
        "T1",
    ], "issued=0 cells=-2 status=4 grant=0")


def test_value_copy_refuses_an_unknown_type():
    interop_check("type 99", [
        ": T1  99 T-S CV.TYPE !  T-S T-D T{ _CV-COPY-BODY }T",
        '      CV-E-TYPE = ." type-error=" . ;',
        "T1",
    ], "cells=-1 type-error=-1")


# ---------------------------------------------------------------------
# Net: the HTTP resource, the connection owner, Rabbit spans and names
# ---------------------------------------------------------------------

NET = ForthSnapshot(
    ("net/http-resource.f", "web/http-connection-owner.f",
     "net/rabbit/builder.f", "net/rabbit/router.f"),
    prelude=DEPTH + (
        "CREATE T-RES HTTP-RESOURCE-SIZE ALLOT",
        "CREATE T-CONN HTTP-CONNECTION-OWNER-SIZE ALLOT",
    ),
)

net_check, net_check_fn, _ = transcript_checks(NET.run)


def test_http_resource_poll_faults_an_unknown_phase():
    lines = [": HRES-VALID?  ( resource -- flag )  DROP -1 ;"]
    lines += definition("net/http-resource.f", "HRES-POLL")
    net_check("phase 99", lines + [
        ": T1  T-RES HRES-INIT  HRES-STATE-ACTIVE T-RES HRES.STATE !",
        "      99 T-RES HRES.PHASE !",
        '      T-RES T{ HRES-POLL }T HRES-S-FAULT = ." fault=" .',
        '      T-RES HRES.STATE @ HRES-STATE-FAULT = ." state=" .',
        '      T-RES HRES.DETAIL @ HRES-D-REQUEST = ." detail=" . ;',
        "T1",
    ], "cells=0 fault=-1 state=-1 detail=-1")


def test_connection_step_refuses_an_unknown_state():
    lines = [": HCONN-VALID?  ( connection -- flag )  DROP -1 ;"]
    lines += definition("web/http-connection-owner.f", "HCONN-STEP")
    net_check("state 99", lines + [
        ": T1  T-CONN HTTP-CONNECTION-OWNER-SIZE 0 FILL  99 T-CONN HCONN.STATE !",
        '      T-CONN T{ HCONN-STEP }T HCONN-S-INVALID = ." invalid=" . ;',
        "T1",
    ], "cells=0 invalid=-1")


def test_rabbit_owned_spans_past_the_last():
    builder = ["99 CONSTANT RMSGB-OWNED-SPAN-COUNT",
               ": RMSGB-VALID?  ( builder -- flag )  DROP -1 ;"]
    builder += definition("net/rabbit/builder.f", "RMSGB-OWNED-SPAN@")
    net_check("builder", builder + [
        ': T1  5 0 T{ RMSGB-OWNED-SPAN@ }T RMSGB-S-INVALID = ." invalid=" .'
        '      ." bytes=" . ." addr=" . ;',
        "T1",
    ], "cells=1 invalid=-1 bytes=0 addr=0")
    router = ["99 CONSTANT RROUTER-OWNED-SPAN-COUNT",
              ": RROUTER-VALID?  ( router -- flag )  DROP -1 ;"]
    router += definition("net/rabbit/router.f", "RROUTER-OWNED-SPAN@")
    net_check("router", router + [
        ': T1  5 0 T{ RROUTER-OWNED-SPAN@ }T RROUTER-S-INVALID = ." invalid=" .'
        '      ." bytes=" . ." addr=" . ;',
        "T1",
    ], "cells=1 invalid=-1 bytes=0 addr=0")


def test_rabbit_capability_name_for_an_unlisted_set():
    lines = ["-1 CONSTANT RABBIT-CAPS-KNOWN"]
    lines += definition("net/rabbit/builder.f", "_RMSGB-CAPS$")
    net_check("caps 4", lines + [
        ': T1  4 T{ _RMSGB-CAPS$ }T ." flag=" . ." u=" . ." a=" . ;',
        "T1",
    ], "cells=2 flag=0 u=0 a=0")


# ---------------------------------------------------------------------
# Keys and widgets
# ---------------------------------------------------------------------

TUI = ForthSnapshot(
    ("tui/keys.f", "tui/widgets/text-grid.f", "tui/field-model.f", "tui/widgets/field.f"),
    prelude=DEPTH + (
        "CREATE T-EV 24 ALLOT",
        ': T-EV.  ( -- )  ." type=" T-EV @ . ." code=" T-EV 8 + @ . ;',
        "\\ The low bytes an event written through a small number would change.",
        ": T-LOW  ( -- sum )  0  41 0 DO I C@ + LOOP ;",
        "CREATE T-SRC 8 ALLOT  VARIABLE T-SRC-N  VARIABLE T-SRC-I  VARIABLE T-OWNER",
        ": T-POLL  ( context -- byte has-byte )",
        "    DROP T-SRC-I @ T-SRC-N @ < IF",
        "        T-SRC T-SRC-I @ + C@  1 T-SRC-I +!  TRUE",
        "    ELSE 0 FALSE THEN ;",
        "CREATE T-FS 1031 ALLOT  : T-FM  ( -- a )  T-FS 7 + -8 AND ;",
        "CREATE T-BS 47 ALLOT  : T-FB  ( -- a )  T-BS 7 + -8 AND ;",
        "VARIABLE T-FU  VARIABLE T-FW",
        "\\ A bound text field showing abc, its kind then made unknown.",
        ": T-FIELD  ( -- )",
        "    T-FM 1024 T-FB UFLD-BUILDER-INIT DROP",
        "    3 UFLD-K-TEXT 11 12 1 3 0 T-FB UFLD-BEGIN DROP",
        "    0 0 0 0 0 5 1 5 T-FB UFLD-SLOTS DROP",
        "    0 0 T-FB UFLD-LABEL DROP",
        '    S" abc" T-FB UFLD-TEXT DROP',
        "    T-FB UFLD-FINISH DROP T-FU !",
        "    18 4 SCR-NEW SCR-USE",
        "    1 2 1 12 RGN-NEW FLD-NEW T-FW !",
        "    T-FM T-FU @ T-FW @ FLD-BIND DROP ;",
    ),
)

tui_check, tui_check_fn, _ = transcript_checks(TUI.run)


def test_csi_with_an_unknown_tilde_key_returns_a_character():
    tui_check("ESC [ 9 ~", [
        ": T1  T-EV 24 0 FILL  _KEY-BUF-RESET [CHAR] 9 _KEY-BUF-ADD [CHAR] ~ _KEY-BUF-ADD",
        '      T-LOW >R T-EV T{ _KEY-DECODE-CSI }T T-LOW R> = ." low-kept=" . T-EV. ;',
        "T1",
    ], "cells=-1 low-kept=-1 type=0 code=9")


def test_ss3_with_an_unknown_final_byte_returns_a_character():
    tui_check("ESC O M", [
        ": T1  T-EV 24 0 FILL  _KEY-BUF-RESET [CHAR] M _KEY-BUF-ADD",
        "      T-EV T{ _KEY-DECODE-SS3 }T T-EV. ;",
        "T1",
    ], "cells=-1 type=0 code=77")


def test_escape_o_without_a_final_byte_leaves_one_flag():
    # The source hands out O after the escape, then nothing, so the
    # wait for the SS3 final byte times out.
    tui_check("ESC O, timeout", [
        ": T1  T-EV 24 0 FILL  0 T-SRC-I !  1 T-SRC-N !  [CHAR] O T-SRC C!",
        "      1 _KEY-TIMEOUT !",
        '      T-OWNER [\'] T-POLL 0 0 KEY-SOURCE-ACQUIRE ." acquired=" . >R',
        "      27 _KEY-B0 !  T-LOW >R",
        '      T-EV T{ _KEY-DECODE-B0 }T ." flag=" .',
        '      T-LOW R> = ." low-kept=" . T-EV.',
        "      T-OWNER R> KEY-SOURCE-RELEASE DROP ;",
        "T1",
    ], "acquired=0 cells=0 flag=-1 low-kept=-1 type=0 code=79")


def test_text_grid_leaves_an_unhandled_special_key():
    tui_check("Home", [
        ": T1  T-EV 24 0 FILL  KEY-T-SPECIAL T-EV !  KEY-HOME T-EV 8 + !",
        '      7 T-EV 0 T{ _TGRID-HANDLE-IMPL }T ." consumed=" . ." below=" . ;',
        "T1",
    ], "cells=-1 consumed=0 below=7")


def test_text_grid_navigation_in_an_unknown_direction():
    lines = [": _TGRID-AVAILABLE-DATA?  ( item -- flag )  DROP -1 ;",
             ": USCOL-ITEM-KEY@  ( item -- key )  DROP 5 ;"]
    lines += definition("tui/widgets/text-grid.f", "_TGRID-NAV-CANDIDATE?")
    tui_check("direction 99", lines + [
        ": T1  0 _TGRID-NAV-CURRENT !  99 _TGRID-NAV-DIRECTION !",
        '      7 1234 T{ _TGRID-NAV-CANDIDATE? }T ." flag=" . ." below=" . ;',
        "T1",
    ], "cells=0 flag=0 below=7")


def test_field_of_an_unknown_kind_draws_no_value():
    # The bound check validates the model on every draw, so a copy of the
    # draw word over a stand-in for it reaches the kind's CASE.
    lines = [": _FLD-BOUND?  ( widget -- flag )  DROP -1 ;"]
    lines += definition("tui/widgets/field.f", "_FLD-DRAW-IMPL")
    tui_check("text kind", ["T-FIELD"] + lines + [
        ": T1  SCR-CLEAR RGN-ROOT T-FW @ WDG-REGION RGN-USE",
        "      7 T-FW @ T{ _FLD-DRAW-IMPL }T",
        '      1 7 SCR-GET CELL-CP@ ." at7=" . ." below=" . ;',
        "T1",
    ], "cells=-1 at7=97 below=7")
    tui_check("kind 99", ["T-FIELD"] + lines + [
        ": T1  99 T-FM UFLD-KIND-OFFSET + !",
        "      SCR-CLEAR RGN-ROOT T-FW @ WDG-REGION RGN-USE",
        "      7 T-FW @ T{ _FLD-DRAW-IMPL }T",
        '      1 7 SCR-GET CELL-CP@ ." at7=" . ." below=" . ;',
        "T1",
    ], "cells=-1 at7=32 below=7")


if __name__ == "__main__":
    run_file_tests(__file__)
