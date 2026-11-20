#!/usr/bin/env python3
"""The API-key adapter reports every credential status (agent/auth/api-key.f).

The stack-effect checker of toolchain/language found _AAK-SET, the
adapter's AAUTH-SECRET-SET ( secret-a secret-u auth -- status ), dropping
the selector in its CASE default, so ENDCASE dropped the status it meant to
return for a credential status other than OK and TOO-LONG, and the word
then took a cell of its caller's.  The cases set a secret through the
adapter's port: an empty one, which the credential refuses as invalid, one
longer than the credential holds, and one it keeps.
"""

from __future__ import annotations

from forth_snapshot import ForthSnapshot, run_file_tests, transcript_checks


SNAPSHOT = ForthSnapshot(
    ("tui/applets/agent/auth/api-key.f",),
    prelude=(
        "VARIABLE T-DEPTH",
        ": T{  ( -- )  DEPTH T-DEPTH ! ;",
        ': }T  ( -- )  DEPTH T-DEPTH @ - ." cells=" . ;',
        "CREATE T-CRED CREDENTIAL-SIZE ALLOT  T-CRED CRED-INIT",
        "CREATE T-AAK APIKEY-AUTH-SIZE ALLOT",
        "T-CRED T-AAK APIKEY-AUTH-INIT DROP",
        "CREATE T-LONG CRED-SECRET-CAPACITY 1+ ALLOT",
        "T-LONG CRED-SECRET-CAPACITY 1+ 65 FILL",
        ': T-SET.  ( secret-a secret-u -- )  T-AAK APIKEY-AUTH.PORT',
        '    T{ AAUTH-SECRET-SET }T ." status=" . ;',
    ),
)

check, check_fn, check_emitted = transcript_checks(SNAPSHOT.run)


def test_secret_set_reports_each_status():
    check("refused as invalid", [
        ': T1  7 S" " T-SET. ." below=" . ;',
        "T1",
    ], "cells=-2 status=2 below=7")
    check("too long", [
        ': T1  7 T-LONG CRED-SECRET-CAPACITY 1+ T-SET. ." below=" . ;',
        "T1",
    ], "cells=-2 status=3 below=7")
    check("kept", [
        ': T1  7 S" sk-test" T-SET. ." below=" .',
        '      T-AAK APIKEY-AUTH.PORT AAUTH.STATE @ AAUTH-STATE-READY = ." ready=" . ;',
        "T1",
    ], "cells=-2 status=0 below=7 ready=-1")


if __name__ == "__main__":
    run_file_tests(__file__)
