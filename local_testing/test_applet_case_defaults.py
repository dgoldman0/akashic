#!/usr/bin/env python3
"""CASE defaults in the release applets that keep their word's stack effect.

BIOS's ENDCASE drops the selector, so a CASE default must leave its
selector on top for the default to have the effect of the other branches.
The stack-effect checker of toolchain/language found Agent, Daybook, Desk,
Grid, Library and Streams words whose default dropped the selector first
or pushed nothing, and reading the rest of each family found defaults that
left the right depth with the wrong cells, and handlers whose fall-through
after a CASE dropped a cell of their caller's.  Each case feeds the word a
selector its branches do not name and checks the cells it leaves:

- Agent: a context item of unknown kind, an unknown role and stream
  status, an unknown tool status, and a scripted run polled past its last
  step;
- Daybook: a month and weekday past the last, and a plain key the panel
  does not use;
- Desk: a catalog status it does not list;
- Grid: a non-ASCII key, a parser state it does not know, and formulas,
  whose operators now choose by IF;
- Library: a fact of unknown kind, index and compaction work in unknown
  phases and kinds, a query source in an unknown mode, and a page view it
  does not know whose query fails;
- Streams: compaction rows in unknown phases, a remote subscription
  action it does not know, and a post outcome it does not list.

Where the selector cannot reach the default through the word's callers,
a copy of the word's own source text is compiled over a stand-in for the
word that supplies the selector, so the default runs as written.  The
applets' instance-relative cells read a zeroed state allocated here.
"""

from __future__ import annotations

import re

from forth_snapshot import (
    SOURCE_ROOT,
    ForthSnapshot,
    megapad_module_lines,
    module_source_lines,
    run_file_tests,
    transcript_checks,
)


DEPTH = (
    "VARIABLE T-DEPTH",
    ": T{  ( -- )  DEPTH T-DEPTH ! ;",
    ': }T  ( -- )  DEPTH T-DEPTH @ - ." cells=" . ;',
    "CREATE T-EV 24 ALLOT",
    "\\ An event of TYPE and CODE with no modifiers.",
    ": T-EV!  ( type code -- )  T-EV 24 0 FILL  T-EV 8 + !  T-EV ! ;",
)


def definition(module: str, name: str) -> list[str]:
    """The lines of NAME's colon definition in MODULE, as the source has them."""
    text = (SOURCE_ROOT / module).read_text(encoding="utf-8")
    match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", text)
    assert match, (module, name)
    return match.group().splitlines()


def zeroed_state(size: str, current: str) -> str:
    return f"{size} ALLOCATE DROP DUP {size} 0 FILL {current} !"


# ---------------------------------------------------------------------
# Agent
# ---------------------------------------------------------------------

AGENT = ForthSnapshot(
    ("tui/applets/agent/model-context.f",
     "tui/applets/agent/providers/openai/request-codec.f",
     "tui/applets/agent/providers/openai/responses.f",
     "tui/applets/agent/providers/devtools/scripted.f"),
    prelude=DEPTH + (
        "CREATE T-ITEM AGENT-CONTEXT-ITEM-SIZE ALLOT",
        "CREATE T-SESSION 64 ALLOT",
        "VARIABLE T-MA  VARIABLE T-MU",
    ),
)

agent_check, agent_check_fn, _ = transcript_checks(AGENT.run)


def test_context_item_of_an_unknown_kind_is_invalid():
    agent_check("kind 99", [
        ": T1  T-ITEM AGENT-CONTEXT-ITEM-SIZE 0 FILL  99 T-ITEM ACTXI.KIND !",
        '      7 T-ITEM T{ ACTXI-VALID? }T ." valid=" . ." below=" . ;',
        "T1",
    ], "cells=0 valid=0 below=7")


def test_openai_role_of_an_unknown_role():
    agent_check("role 99", [
        ': T1  99 T{ _OAITR-ROLE }T ." flag=" . ." u=" . ." a=" . ;',
        "T1",
    ], "cells=2 flag=0 u=0 a=0")


def test_openai_stream_failure_of_an_unknown_status():
    lines = [": _OAIR-MARK-ERROR  ( a u context -- status )  DROP T-MU ! T-MA ! 0 ;"]
    lines += definition("tui/applets/agent/providers/openai/responses.f", "_OAIR-SSE-FAIL")
    agent_check("status 999", lines + [
        ': T1  999 T-SESSION T{ _OAIR-SSE-FAIL }T ." status=" . T-MA @ T-MU @ TYPE ;',
        "T1",
    ], "cells=-1 status=1 Responses stream parsing failed")


def test_scripted_tool_error_text_of_an_unknown_status():
    agent_check("status 99", [
        ": T1  99 T{ _SCRIPTED-TOOL-ERROR-TEXT }T TYPE ;",
        "T1",
    ], "cells=1 Tool request was not completed.")


def test_scripted_run_polled_past_its_last_step():
    agent_check("step 7", [
        "SCRIPTED-PROVIDER-NEW DROP APROV.CONTEXT @ CONSTANT T-SPC",
        ": T1  _SP-STREAMING T-SPC _SPC.STATE !  7 T-SPC _SPC.STEP !",
        '      0 T-SPC T{ _SCRIPTED-POLL }T ." ior=" . T-SPC _SPC.STEP @ ." step=" . ;',
        "T1",
    ], "cells=-1 ior=0 step=8")


# ---------------------------------------------------------------------
# Daybook and Grid
# ---------------------------------------------------------------------

CALENDAR_SHEET = ForthSnapshot(
    ("tui/applets/daybook/daybook.f", "tui/applets/grid/grid.f"),
    prelude=DEPTH + (
        zeroed_state("_DB-STATE-SIZE", "_DB-CURRENT-STATE"),
        zeroed_state("_GRID-STATE-SIZE", "_GRID-CURRENT-STATE"),
        "CREATE T-CSV 4 ALLOT",
    ),
)

sheet_check, sheet_check_fn, _ = transcript_checks(CALENDAR_SHEET.run)


def test_daybook_names_past_the_last():
    sheet_check("month 13", [
        ": T1  13 T{ _DB-MONTH-NAME }T TYPE ;",
        "T1",
    ], "cells=1 Month")
    sheet_check("weekday 7", [
        ": T1  7 T{ _DB-GRID-WEEKDAY }T TYPE ;",
        "T1",
    ], "cells=1 ?")


def test_daybook_leaves_a_plain_key_it_does_not_use():
    sheet_check("x", [
        ": T1  KEY-T-CHAR [CHAR] x T-EV!",
        '      7 T-EV 0 T{ _DB-PANEL-HANDLE }T ." consumed=" . ." below=" . ;',
        "T1",
    ], "cells=-1 consumed=0 below=7")


def test_grid_leaves_a_key_outside_ascii():
    sheet_check("233", [
        ": T1  KEY-T-CHAR 233 T-EV!",
        '      7 T-EV 0 T{ _GRID-PANEL-HANDLE }T ." consumed=" . ." below=" . ;',
        "T1",
    ], "cells=-1 consumed=0 below=7")


def test_grid_csv_scan_refuses_an_unknown_state():
    # The first step moves the scanner to a state no branch names.
    lines = [": _GCSV-STEP-START  ( -- )  99 _GCSV-STATE !  1 _GCSV-POS +! ;"]
    lines += definition("tui/applets/grid/grid.f", "_GRID-SCAN-CSV")
    sheet_check("state 99", lines + [
        ": T1  [CHAR] a T-CSV C!  [CHAR] b T-CSV 1+ C!",
        "      T-CSV _GRID-IO-BUF !  2 _GRID-IO-U !",
        '      7 0 T{ _GRID-SCAN-CSV }T _GRID-L-S-INVALID = ." invalid=" . ." below=" . ;',
        "T1",
    ], "cells=0 invalid=-1 below=7")


def test_grid_formulas_choose_their_operators():
    sheet_check("arithmetic", [
        ': T1  S" 2*3+8/2-1" T{ _GRID-EVAL-FORMULA }T ." ok=" . ." value=" . ;',
        "T1",
    ], "cells=0 ok=-1 value=9")
    sheet_check("division by zero", [
        ': T1  S" 4/0" _GRID-EVAL-FORMULA ." ok=" . ." value=" . ;',
        "T1",
    ], "ok=0 value=0")


# ---------------------------------------------------------------------
# Desk
# ---------------------------------------------------------------------

DESK = ForthSnapshot(("tui/app-catalog.f", "tui/app-loader.f"), prelude=DEPTH)

desk_check, desk_check_fn, _ = transcript_checks(DESK.run)


def test_desk_catalog_status_it_does_not_list():
    lines = definition("tui/applets/desk/desk.f", "_DESK-CATALOG-STATUS$")
    desk_check("status 999", lines + [
        ": T1  999 T{ _DESK-CATALOG-STATUS$ }T TYPE ;",
        "T1",
    ], "cells=1 unknown error")


# ---------------------------------------------------------------------
# Library
# ---------------------------------------------------------------------

LIBRARY = ForthSnapshot(
    ("tui/applets/library/model.f", "tui/applets/library/persistence-adapter.f",
     "tui/applets/library/query.f", "tui/applets/library/controller.f"),
    prelude=DEPTH + (
        zeroed_state("_LAPP-STATE-SIZE", "_LAPP-CURRENT-STATE"),
        "CREATE T-IX LIBPA-INDEX-WORK-SIZE ALLOT",
        "CREATE T-COM LIBPA-COMPACTION-CONTEXT-SIZE ALLOT",
        "CREATE T-QSR _LIBQSR-SIZE ALLOT",
        "LIBRARY-QUERY-WORK-SIZE ALLOCATE DROP CONSTANT T-QW",
    ),
)

library_check, library_check_fn, _ = transcript_checks(LIBRARY.run)


def test_library_fact_of_an_unknown_kind():
    library_check("kind 99", [
        ': T1  7 S" x" 99 T{ _LIBM-FACT-PAYLOAD? }T ." valid=" . ." below=" . ;',
        "T1",
    ], "cells=-2 valid=0 below=7")


def test_library_range_prefix_of_unknown_kinds():
    library_check("operation 99", [
        ": T1  T-IX LIBPA-INDEX-WORK-SIZE 0 FILL  99 T-IX _LIBPIX.OPERATION-KIND !",
        "      7 T-IX T{ _LIBPIX-RANGE-PREFIX-BUILD }T",
        '      LIBPA-S-INVALID = ." invalid=" . ." below=" . ;',
        "T1",
    ], "cells=0 invalid=-1 below=7")
    library_check("state member count 9", [
        ": T1  T-IX LIBPA-INDEX-WORK-SIZE 0 FILL",
        "      LIBPA-RANGE-DOCUMENT-STATE-CREATION T-IX _LIBPIX.OPERATION-KIND !",
        "      9 T-IX _LIBPIX.PROGRESS-LIMIT !",
        "      7 T-IX T{ _LIBPIX-RANGE-PREFIX-BUILD }T",
        '      LIBPA-S-INVALID = ." invalid=" . ." below=" . ;',
        "T1",
    ], "cells=0 invalid=-1 below=7")


def test_library_compaction_in_an_unknown_phase():
    library_check("next phase", [
        ": T1  T-COM LIBPA-COMPACTION-CONTEXT-SIZE 0 FILL  99 T-COM _LIBPACOM.PHASE !",
        "      7 T-COM T{ _LIBPACOM-NEXT-PHASE }T",
        '      T-COM _LIBPACOM.PHASE @ _LIBPACOM-PHASE-DONE = ." done=" . ." below=" . ;',
        "T1",
    ], "cells=-1 done=-1 below=7")
    library_check("dispatch", [
        ": T1  T-COM LIBPA-COMPACTION-CONTEXT-SIZE 0 FILL  99 T-COM _LIBPACOM.PHASE !",
        "      7 T-COM T{ _LIBPACOM-DISPATCH-ROW }T",
        '      LIBPA-S-CORRUPT = ." corrupt=" . ." below=" . ;',
        "T1",
    ], "cells=0 corrupt=-1 below=7")


def test_library_query_source_in_an_unknown_mode():
    library_check("mode 99", [
        ": T1  T-QSR _LIBQSR-SIZE 0 FILL  99 T-QW _LIBQW.MODE !",
        "      7 T-QSR T-QW T{ _LIBQSR-FETCH }T",
        '      LIBPA-S-INVALID = ." invalid=" . ." below=" . ;',
        "T1",
    ], "cells=-1 invalid=-1 below=7")


def test_library_page_of_an_unknown_view_whose_query_fails():
    lines = [": _LAPP-BUILD-QUERY  ( -- status )  5 ;"]
    lines += definition("tui/applets/library/controller.f", "_LAPP-PAGE-INITIALIZE")
    library_check("view 99", lines + [
        ": T1  99 _LAPP-VIEW !",
        '      7 T{ _LAPP-PAGE-INITIALIZE }T ." status=" . ." below=" . ;',
        "T1",
    ], "cells=1 status=5 below=7")


# ---------------------------------------------------------------------
# Streams
# ---------------------------------------------------------------------

STREAMS = ForthSnapshot(
    ("tui/applets/streams/compaction.f", "tui/applets/streams/operational-compaction.f",
     "tui/applets/streams/rabbit-remote-sub.f"),
    prelude=DEPTH + (
        "CREATE T-PAC STREAMS-PA-COMPACTION-CONTEXT-SIZE ALLOT",
        "CREATE T-SPC STREAMS-SPOOL-COMPACTION-CONTEXT-SIZE ALLOT",
        "CREATE T-SUB STREAMS-RABBIT-REMOTE-SUB-SIZE ALLOT",
    ),
)

streams_check, streams_check_fn, _ = transcript_checks(STREAMS.run)


def test_streams_compaction_rows_in_an_unknown_phase():
    streams_check("source compaction", [
        ": T1  T-PAC STREAMS-PA-COMPACTION-CONTEXT-SIZE 0 FILL  99 T-PAC _SPACOM.PHASE !",
        "      7 T-PAC T{ _SPACOM-DISPATCH-ROW }T",
        '      STREAMS-PA-S-CORRUPT = ." corrupt=" . ." below=" . ;',
        "T1",
    ], "cells=0 corrupt=-1 below=7")
    streams_check("spool compaction", [
        ": T1  T-SPC STREAMS-SPOOL-COMPACTION-CONTEXT-SIZE 0 FILL  99 T-SPC _SSPCOM.PHASE !",
        "      7 T-SPC T{ _SSPCOM-DISPATCH-ROW }T",
        '      STREAMS-SPOOL-S-CORRUPT = ." corrupt=" . ." below=" . ;',
        "T1",
    ], "cells=0 corrupt=-1 below=7")


def test_streams_remote_subscription_action_it_does_not_know():
    streams_check("action 99", [
        ": T1  T-SUB STREAMS-RABBIT-REMOTE-SUB-SIZE 0 FILL  99 T-SUB SRRS.EVENT-ACTION !",
        '      7 T-SUB T{ _SRRS-EVENT-SHAPE? }T ." shape=" . ." below=" . ;',
        "T1",
    ], "cells=0 shape=0 below=7")


AUTHENTICATED = ForthSnapshot(
    (),
    prelude=tuple(
        megapad_module_lines("networking.f")
        + module_source_lines(("tui/applets/streams/atproto-authenticated-provider.f",))
    ) + DEPTH + (
        "CREATE T-AUTH STREAMS-AT-AUTH-CONTEXT-SIZE ALLOT",
    ),
)

authenticated_check, _, _ = transcript_checks(AUTHENTICATED.run)


def test_streams_post_capture_of_an_unlisted_outcome():
    lines = [": AT-TEXT-POST-CONNECTOR-CREATE-OUTCOME@  ( owner -- outcome status )",
             "    DROP 99 AT-TEXT-POST-CONNECTOR-S-OK ;"]
    lines += definition("tui/applets/streams/atproto-authenticated-provider.f",
                        "_SATP-POST-CAPTURE")
    authenticated_check("outcome 99", lines + [
        ": T1  T-AUTH STREAMS-AT-AUTH-CONTEXT-SIZE 0 FILL",
        "      7 T-AUTH T{ _SATP-POST-CAPTURE }T",
        '      SAUTH-S-POST = ." post=" . SAUTH-S-INDETERMINATE = ." indeterminate=" .',
        '      SAUTH-STATE-POST-UNCERTAIN = ." uncertain=" . ." below=" . ;',
        "T1",
    ], "cells=2 post=-1 indeterminate=-1 uncertain=-1 below=7")


if __name__ == "__main__":
    run_file_tests(__file__)
