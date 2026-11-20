"""The checker core of Leviathan's language, on small Forth programs.

The checker lives in ``toolchain/language``; ``docs/language/checker.md``
describes it.  Each test loads MegaPad's BIOS dictionary and KDOS as the
base vocabulary, as the measurement does, then a few definitions.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

AKASHIC_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(AKASHIC_ROOT))

from toolchain.language import effects as E  # noqa: E402
from toolchain.language.checker import Checker  # noqa: E402
from toolchain.language.effects import parse_effect  # noqa: E402
from toolchain.language.measure import effect_text  # noqa: E402
from toolchain.language.source import LineCursor, parse_number  # noqa: E402

MEGAPAD_ROOT = Path(os.environ.get("MEGAPAD_ROOT") or AKASHIC_ROOT.parent / "megapad")
MANAGED = {"ref": E.REF, "handle": E.HANDLE}


@pytest.fixture(scope="module")
def base_checker_state():
    if not (MEGAPAD_ROOT / "kdos.f").is_file():
        pytest.skip("MegaPad checkout not found; set MEGAPAD_ROOT")
    return MEGAPAD_ROOT


def check(megapad: Path, source: str) -> Checker:
    checker = Checker()
    checker.load_bios(megapad)
    checker.load_base(megapad, ("kdos.f",))
    checker.group = "library"
    checker.load_text(source, "test.f")
    return checker


def record(checker: Checker, name: str):
    for item in reversed(checker.records):
        if item.word.name == name:
            return item
    raise KeyError(name)


def findings(checker: Checker, name: str) -> list[str]:
    return [f"{f.category}: {f.detail}" for f in record(checker, name).findings]


# Reading source the way KDOS does


def test_tokens_split_on_spaces_only_and_backslash_tokens_end_the_line():
    cursor = LineCursor("DUP\tSWAP  OVER \\not-a-word ROT", 1)
    assert cursor.token() == "DUP\tSWAP"
    assert cursor.token() == "OVER"
    assert cursor.token() == "\\not-a-word"


def test_paren_comments_nest_and_stop_at_the_end_of_the_line():
    cursor = LineCursor("( a (b) -- c ) DUP", 1)
    assert cursor.token() == "("
    assert cursor.paren() == " a (b) -- c "
    assert cursor.token() == "DUP"
    open_cursor = LineCursor("( never closed DUP", 1)
    open_cursor.token()
    assert open_cursor.paren_closed() == (" never closed DUP", False)


def test_numbers_follow_the_bios_parser():
    assert parse_number("-0x10", 10) == -16
    assert parse_number("FF", 16) == 255
    assert parse_number("FF", 10) is None
    assert parse_number("-", 10) is None


# Stack comments


def test_comment_names_give_kinds_and_spans():
    effect = parse_effect(" key-a key-u flag -- addr len ", MANAGED).effect
    assert [s.kind for s in effect.inputs] == [E.ADDR, E.COUNT, E.FLAG]
    assert [s.role for s in effect.inputs] == ["a", "u", None]
    assert [s.role for s in effect.alts[0]] == ["a", "u"]


def test_math_letters_are_plain_cells_and_record_letters_are_addresses():
    math = parse_effect(" a b -- a/b ", MANAGED).effect
    assert [s.kind for s in math.inputs] == [E.X, E.X]
    accessor = parse_effect(" record -- a ", MANAGED).effect
    assert accessor.alts[0][0].kind == E.ADDR


def test_a_bar_alone_separates_alternatives_and_a_bar_inside_names_one_cell():
    whole = parse_effect(" -- addr len true | false ", MANAGED).effect
    assert [len(alt) for alt in whole.alts] == [3, 1]
    assert whole.alts[0][-1].fact == E.NONZERO and whole.alts[1][-1].fact == E.ZERO
    one_cell = parse_effect(" c-addr u -- dentry|0 ior ", MANAGED).effect
    assert [len(alt) for alt in one_cell.alts] == [2]
    found = parse_effect(" c-addr -- c-addr 0 |xt 1 |xt -1 ", MANAGED).effect
    assert [len(alt) for alt in found.alts] == [2, 2, 2]


def test_variable_effects_are_recognized():
    assert parse_effect(" i*x xt -- j*x ", MANAGED).effect.variable
    assert parse_effect(" n -- n*8 ", MANAGED).effect.variable is False


# Inference


def test_shuffles_keep_identity_through_user_words(base_checker_state):
    checker = check(base_checker_state, ": 3DUP  ( a b c -- a b c a b c )  DUP 2OVER ROT ;\n")
    item = record(checker, "3DUP")
    assert item.comparison == "match"
    assert effect_text(item.word.inferred) == "( x x x -- in3 in2 in1 in3 in2 in1 )"


def test_return_stack_parking_and_loop_frames(base_checker_state):
    checker = check(base_checker_state, (
        ": PARK  ( a b -- b )  >R DROP R> ;\n"
        ": LEAK  ( a -- )  >R ;\n"
        ": EARLY  ( n -- )  0 DO I 3 = IF EXIT THEN LOOP ;\n"
        ": MISREAD  ( n -- )  0 DO 5 >R I DROP R> DROP LOOP ;\n"
        ": COUNTER  ( n -- n' )  0 SWAP 0 ?DO R@ + LOOP ;\n"
    ))
    assert record(checker, "PARK").comparison == "match"
    assert record(checker, "LEAK").failure.category == "return stack misuse"
    assert "inside a DO loop without UNLOOP" in record(checker, "EARLY").failure.detail
    assert any("I reads a cell parked by >R" in f for f in findings(checker, "MISREAD"))
    assert record(checker, "COUNTER").comparison == "match"


def test_control_flow_and_unbalanced_branches(base_checker_state):
    checker = check(base_checker_state, (
        ": PICKY  ( n -- n' )  DUP 0< IF NEGATE ELSE 1+ THEN ;\n"
        ": /STRING  ( addr len n -- addr+n len-n )  ROT OVER + -ROT - ;\n"
        ": SPIN  ( a u -- )  BEGIN DUP WHILE 1 /STRING REPEAT 2DROP ;\n"
        ": GROW  ( n -- )  BEGIN DUP WHILE DUP 1- REPEAT DROP ;\n"
        ": LOPSIDED  ( a b -- c )  DUP IF + THEN ;\n"
        ": NAME-OF  ( n -- addr len )  CASE 1 OF S\" one\" ENDOF DROP S\" many\" ENDCASE ;\n"
    ))
    assert record(checker, "PICKY").comparison == "match"
    assert record(checker, "SPIN").comparison == "match"
    assert record(checker, "GROW").failure.category == "loop changes the stack depth"
    assert record(checker, "LOPSIDED").failure.category == "result depth varies"
    # ENDCASE drops the selector, so a default clause that drops it too loses a cell.
    assert record(checker, "NAME-OF").failure.category == "result depth varies"


def test_alternatives_are_routed_by_the_callers_if(base_checker_state):
    checker = check(base_checker_state, (
        ": FETCH?  ( key -- addr len true | false )  DUP IF 3 -1 ELSE DROP 0 THEN ;\n"
        ": USE  ( key -- len )  FETCH? IF NIP ELSE 0 THEN ;\n"
        ": PROBE  ( ior -- )  ?DUP IF . THEN ;\n"
    ))
    assert record(checker, "FETCH?").comparison == "match"
    assert effect_text(record(checker, "FETCH?").word.inferred) == "( x -- in1 3 -1 | 0 )"
    assert record(checker, "USE").comparison == "match"
    assert record(checker, "PROBE").comparison == "match"


def test_catch_and_words_that_execute_what_they_are_given(base_checker_state):
    checker = check(base_checker_state, (
        ": RISKY  ( a b -- c )  + ;\n"
        ": TRY  ( a b -- c ior )  ['] RISKY CATCH DUP IF NIP NIP 0 SWAP THEN ;\n"
        ": WITH  ( xt n -- )  >R CATCH R> DROP THROW ;\n"
        ": WRAPPED  ( a b -- c )  ['] RISKY 7 WITH ;\n"
        "' RISKY CONSTANT RISKY-XT\n"
        ": BY-CONSTANT  ( a b -- c )  RISKY-XT EXECUTE ;\n"
        ": BLIND  ( xt -- )  @ EXECUTE ;\n"
    ))
    assert record(checker, "TRY").comparison == "match"
    assert record(checker, "WITH").word.higher_order
    assert record(checker, "WRAPPED").comparison == "match"
    assert record(checker, "BY-CONSTANT").comparison == "match"
    blind = record(checker, "BLIND").failure
    assert (blind.category, blind.detail) == ("EXECUTE of an unknown xt", "a cell read from memory")


def test_defining_words_give_their_children_an_effect(base_checker_state):
    checker = check(base_checker_state, (
        "VARIABLE CURRENT\n"
        ": FIELD:  ( offset \"name\" -- )  CREATE ,  DOES>  ( body -- addr )  @ CURRENT @ + ;\n"
        "8 FIELD: .NEXT\n"
        ": WALK  ( -- addr )  .NEXT ;\n"
    ))
    assert record(checker, "WALK").comparison == "match"
    assert checker.lookup(".NEXT").signature.alts[0][0].kind == E.ADDR


def test_names_ignore_case_and_a_definition_can_name_itself(base_checker_state):
    checker = check(base_checker_state, (
        ": TWICE  ( n -- n' )  2* ;\n"
        ": twice  ( n -- n' )  TWICE 1+ ;\n"
    ))
    later = record(checker, "twice")
    # ":" publishes the header before the body compiles, so TWICE is twice.
    assert later.hides_older and later.self_named


def test_tick_inside_a_definition_parses_when_the_word_runs(base_checker_state):
    checker = check(base_checker_state, (
        "VARIABLE HOOK\n"
        ": SHOW  ( c -- )  EMIT ;\n"
        ": RESET-HOOK  ( -- )  ' SHOW HOOK ! ;\n"
    ))
    assert record(checker, "RESET-HOOK").comparison == "mismatch"


def test_kind_span_and_managed_findings(base_checker_state):
    checker = check(base_checker_state, (
        ": FLAG-AS-ADDRESS  ( n -- x )  0= @ ;\n"
        ": MIXED  ( a1 u1 a2 u2 -- )  NIP NIP TYPE ;\n"
        "VARIABLE SLOT\n"
        ": KEEP  ( ref -- )  SLOT ! ;\n"
    ))
    assert any(f.startswith("kind: flag used as an address") for f in findings(checker, "FLAG-AS-ADDRESS"))
    assert record(checker, "MIXED").comparison == "match"
    assert any(f.startswith("span: TYPE takes the address of one span")
               for f in findings(checker, "MIXED"))
    assert any("keeps a ref in plain memory" in f for f in findings(checker, "KEEP"))


def test_kdos_catch_and_throw_keep_their_exact_meaning(base_checker_state):
    checker = check(base_checker_state, "")
    assert checker.lookup("CATCH").prim == "CATCH"
    assert checker.lookup("THROW").prim == "THROW"
    assert len([r for r in checker.records if r.group == "base"]) > 800
