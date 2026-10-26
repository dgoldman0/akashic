"""The claim ledger's record checks in normal mode and with every-frame checks.

The ledger turns a real menu capture's records into paint claims.  Each
record must be a menu record of the source's generation in both modes.  Its
structure and resolved geometry, which the menu capture checked when it
wrote the record, are checked again only with every-frame checks on
(check-mode.f).
"""

from native_forth import NativeForth

PRELUDE = (
    "CREATE _TB 4096 ALLOT  VARIABLE _TL",
    ": TR  0 _TL ! ;",
    ": TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;",
    ": TA  ( -- addr u ) _TB _TL @ ;",
    "VARIABLE _RGN_SLOT",
    ": T-RGN  0 0 24 80 RGN-NEW _RGN_SLOT ! ;",
    "80 24 SCR-NEW SCR-USE",
    # Caller banks for one menu capture: 32 work entries and records.
    "CREATE _MW-MEM 32 136 * 8 + ALLOT",
    ": _MW  _MW-MEM 7 + -8 AND ;",
    "CREATE _MR-MEM 32 192 * 8 + ALLOT",
    ": _MR  _MR-MEM 7 + -8 AND ;",
    "CREATE _MWT 512 ALLOT",
    "CREATE _MT 512 ALLOT",
    "VARIABLE _MCOUNT",
    ": T-CAPTURE ( generation -- )",
    "    _MW 32 136 * _MWT 512 _MR 32 192 * _MT 512 UMSN-CAPTURE",
    "    IF 2DROP -1 _MCOUNT ! ELSE DROP _MCOUNT ! THEN ;",
    # A request and claim bank for the captured records, generation 9.
    "CREATE _CQ-MEM 120 ALLOT",
    ": _CQ  _CQ-MEM 7 + -8 AND ;",
    "CREATE _CC-MEM 32 80 * 8 + ALLOT",
    ": _CC  _CC-MEM 7 + -8 AND ;",
    "VARIABLE _CSTATUS  VARIABLE _CCOUNT  VARIABLE _CSAVE",
    ": T-CLAIMS ( -- )",
    "    _CQ RUCL-REQUEST-CLEAR",
    "    7 9 _MCOUNT @ _CQ RUCL-REQUEST-ADMISSION!",
    "    80 24 0 0 24 80 _CQ RUCL-REQUEST-GEOMETRY!",
    "    _MR _MCOUNT @ 192 * _CC 32 80 * _CQ RUCL-REQUEST-STORAGE!",
    "    _CQ RUCL-BUILD _CSTATUS ! _CCOUNT ! ;",
    ": T-SHOW ( -- ) _CSTATUS @ . _CCOUNT @ . CR ;",
    ": T-FG ( -- a ) _MR _RUCL-R.RESOLVED _UTUI-RS.FG ;",
)

SUITE = NativeForth(("tui/rich-terminal/uidl-claim-ledger.f",), prelude=PRELUDE)

MENU = (
    "<uidl><menubar>"
    "<menu id=view label=View>"
    '<item id=hidden text="Show Hidden"/>'
    "<item id=refresh text=Refresh/>"
    "</menu>"
    "<menu id=help label=Help><item id=about text=About/></menu>"
    "</menubar></uidl>"
)


def test_normal_mode_claims_check_each_records_identity_not_its_structure() -> None:
    lines = ["T-RGN", "TR"]
    lines.extend(f"{ord(ch)} TC" for ch in MENU)
    lines.extend((
        "TA _RGN_SLOT @ UTUI-LOAD DROP",
        "9 T-CAPTURE",
        '." COUNT " _MCOUNT @ . CR',
        '." BASE " T-CLAIMS T-SHOW',
        # The first record's resolved foreground is out of range.
        "T-FG @ _CSAVE !  300 T-FG !",
        '." FG-NORMAL " T-CLAIMS T-SHOW',
        "-1 CHK-EVERY-FRAME !",
        '." FG-EVERY " T-CLAIMS T-SHOW',
        "_CSAVE @ T-FG !",
        # A record of another generation is refused in both modes.
        "_MR _RUCL-R.GENERATION @ _CSAVE !  10 _MR _RUCL-R.GENERATION !",
        '." GEN-EVERY " T-CLAIMS T-SHOW',
        "0 CHK-EVERY-FRAME !",
        '." GEN-NORMAL " T-CLAIMS T-SHOW',
        "_CSAVE @ _MR _RUCL-R.GENERATION !",
        '." AFTER " T-CLAIMS T-SHOW',
    ))
    raw = SUITE.run(lines, 200_000_000)
    text = "".join(chr(b) if 0x20 <= b < 0x7F or b == 10 else "" for b in raw)
    assert "??" not in text and "ABORT" not in text, text[-600:]
    results = {}
    for line in text.splitlines():
        words = line.split()
        if words and words[0] in ("COUNT", "BASE", "FG-EVERY", "FG-NORMAL",
                                  "GEN-NORMAL", "GEN-EVERY", "AFTER"):
            results[words[0]] = [int(word) for word in words[1:]]
    assert results["COUNT"][0] >= 6, text[-600:]
    ok, invalid = 0, 2
    status, claims = results["BASE"]
    assert status == ok
    assert results["FG-EVERY"][0] == invalid
    assert results["FG-NORMAL"] == [ok, claims]
    assert results["GEN-NORMAL"][0] == invalid
    assert results["GEN-EVERY"][0] == invalid
    assert results["AFTER"] == [ok, claims]
