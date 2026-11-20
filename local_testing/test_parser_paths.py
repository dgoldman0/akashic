#!/usr/bin/env python3
"""Parser paths that left the wrong cells, held to their stack comments.

The stack-effect checker of toolchain/language found these paths returning
more or fewer cells than their words' comments promise, or reading the cells
of a span in the wrong order.  Each case runs the path on the emulator and
checks both the cells it leaves and their values:

- STR-PARSE-TOKEN on blank input gives the four cells of an empty token
  and an empty rest;
- YAML-BUILD-RESET, which yaml.f runs while it loads, keeps the default
  output vectors and leaves the stack alone;
- YAML-GET-FLOAT-STR, TOML-GET-FLOAT-STR and TOML-GET-DATETIME-STR give
  the token's span;
- the six parsers' FAIL words abort when told to, without taking a cell of
  the caller's as ABORT"'s flag;
- CSS-SKIP-VALUE steps over a character no value starts with, and
  CSS-EXPAND-TRBL gives nine zeros for an empty value;
- XML-GET-CDATA gives the section's text, closed or not;
- URL-QUERY-FIND gives three zeros for a key the query lacks.
"""

from __future__ import annotations

from forth_snapshot import ForthSnapshot, run_file_tests, transcript_checks


SNAPSHOT = ForthSnapshot(
    (
        "utils/string.f",
        "utils/yaml.f",
        "utils/toml.f",
        "utils/json.f",
        "css/css.f",
        "markup/xml.f",
        "net/url.f",
    ),
    prelude=(
        "VARIABLE T-DEPTH",
        ": T{  ( -- )  DEPTH T-DEPTH ! ;",
        ": }T  ( -- )  DEPTH T-DEPTH @ - .\" cells=\" . ;",
        ": T.SPAN  ( a u -- )  [CHAR] | EMIT TYPE [CHAR] | EMIT SPACE ;",
    ),
)

check, check_fn, check_emitted = transcript_checks(SNAPSHOT.run)


def test_parse_token_blank_input_gives_four_cells():
    check("blank input", [
        ': T1  S"    " T{ STR-PARSE-TOKEN }T . DROP . DROP ;',
        "T1",
    ], "cells=2 0 0")
    check("a token and its rest", [
        ': T1  S"  ab cd" STR-PARSE-TOKEN 2SWAP T.SPAN T.SPAN ;',
        "T1",
    ], "|ab| | cd|")


def test_yaml_build_reset_keeps_its_vectors():
    check("vectors after load", [
        ": T1  YAML-EMIT-XT @ ['] _YAML-DEFAULT-EMIT = ."
        "      YAML-TYPE-XT @ ['] _YAML-DEFAULT-TYPE = . ;",
        "T1",
    ], "-1 -1")
    check("reset after a buffer target", [
        "CREATE T-BUF 16 ALLOT",
        ": T1  T-BUF 16 YAML-SET-OUTPUT T{ YAML-BUILD-RESET }T"
        "      [CHAR] Q YAML-EMIT ;",
        "T1",
    ], "cells=0 Q")


def test_float_strings_give_the_token_span():
    check("YAML float", [
        ': T1  S"   3.25 # note" T{ YAML-GET-FLOAT-STR }T T.SPAN ;',
        "T1",
    ], "cells=0 |3.25|")
    check("YAML float at the end", [
        ': T1  S" -1.5e3" YAML-GET-FLOAT-STR T.SPAN ;',
        "T1",
    ], "|-1.5e3|")
    check("TOML float before a comma", [
        ': T1  S" 6.02e23, 2" T{ TOML-GET-FLOAT-STR }T T.SPAN ;',
        "T1",
    ], "cells=0 |6.02e23|")
    check("TOML datetime before a brace", [
        ': T1  S" 1979-05-27T07:32:00Z}" TOML-GET-DATETIME-STR T.SPAN ;',
        "T1",
    ], "|1979-05-27T07:32:00Z|")


FAIL_WORDS = (
    ("YAML-ABORT-ON-ERROR", "YAML-FAIL", "YAML error"),
    ("TOML-ABORT-ON-ERROR", "TOML-FAIL", "TOML error"),
    ("JSON-ABORT-ON-ERROR", "JSON-FAIL", "JSON error"),
    ("CSS-ABORT-ON-ERROR", "CSS-FAIL", "CSS error"),
    ("MU-ABORT-ON-ERROR", "MU-FAIL", "Markup error"),
    ("URL-ABORT-ON-ERROR", "URL-FAIL", "URL error"),
)


def test_fail_words_abort_when_told_to():
    # A zero under the code was the flag ABORT" took, so the word went on.
    for switch, fail, message in FAIL_WORDS:
        check(f"{fail} aborts", [
            f"-1 {switch} !",
            f': T1  0 3 {fail} ." WENT-ON" ;',
            "T1",
        ], message, not_expected="WENT-ON")
        check(f"{fail} records and returns", [
            f': T1  7 3 T{{ {fail} }}T . ;',
            "T1",
        ], "cells=-1 7")


def test_css_skip_value_steps_over_one_character():
    check("unknown character", [
        ': T1  S" !x" T{ CSS-SKIP-VALUE }T T.SPAN ;',
        "T1",
    ], "cells=0 |x|")


def test_css_expand_trbl_empty_value_gives_nine_cells():
    check("blank value", [
        ': T1  S"    " T{ CSS-EXPAND-TRBL }T . 2DROP 2DROP 2DROP 2DROP ;',
        "T1",
    ], "cells=7 0")
    check("two values", [
        ': T1  S" 1px 2px" T{ CSS-EXPAND-TRBL }T .'
        "      T.SPAN T.SPAN T.SPAN T.SPAN ;",
        "T1",
    ], "cells=7 2 |2px| |1px| |2px| |1px|")


def test_xml_cdata_gives_two_cells():
    check("closed section", [
        ': T1  S" <![CDATA[a<b]]> tail" T{ XML-GET-CDATA }T T.SPAN ;',
        "T1",
    ], "cells=0 |a<b|")
    check("unclosed section", [
        ': T1  S" <![CDATA[abc" T{ XML-GET-CDATA }T T.SPAN ;',
        "T1",
    ], "cells=0 |abc|")


def test_url_query_find_missing_key_gives_three_cells():
    check("missing key", [
        ': T1  S" a=1&b=2" S" c" T{ URL-QUERY-FIND }T . . . ;',
        "T1",
    ], "cells=-1 0 0 0")
    check("present key", [
        ': T1  S" a=1&b=22" S" b" T{ URL-QUERY-FIND }T . T.SPAN ;',
        "T1",
    ], "cells=-1 -1 |22|")


if __name__ == "__main__":
    run_file_tests(__file__)
