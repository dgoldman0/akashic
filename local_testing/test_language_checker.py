"""The checker core of Uroko, on small Forth programs.

The checker lives in ``toolchain/language``; ``docs/language/checker.md``
describes it.  Each test loads MegaPad's BIOS dictionary, KDOS and
``uroko.f``, which declares the base words' kinds, as the measurement does,
then a few definitions.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

AKASHIC_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(AKASHIC_ROOT))

from toolchain.language import effects as E  # noqa: E402
from toolchain.language.checker import Checker  # noqa: E402
from toolchain.language.effects import parse_effect, parse_holds  # noqa: E402
from toolchain.language.measure import effect_text, placement  # noqa: E402
from toolchain.language.source import LineCursor, parse_number  # noqa: E402
from toolchain.language.vocabulary import megapad_root  # noqa: E402

MEGAPAD_ROOT = megapad_root(Path(__file__).absolute().parents[1])


@pytest.fixture(scope="module")
def base_checker_state():
    if not (MEGAPAD_ROOT / "kdos.f").is_file():
        pytest.skip("MegaPad checkout not found; set MEGAPAD_ROOT")
    return MEGAPAD_ROOT


def check(megapad: Path, source: str, strict: bool = False) -> Checker:
    checker = Checker(strict=strict)
    checker.load_bios(megapad)
    checker.load_base(megapad, ("kdos.f", "uroko.f"))
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


def all_findings(checker: Checker) -> list[str]:
    return [f"{f.category}: {f.detail}" for f in checker.findings if f.group == "library"]


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


def test_no_kind_is_read_from_a_name():
    effect = parse_effect(" key-a key-u flag xt -- addr len ").effect
    assert {s.kind for s in effect.inputs + effect.alts[0]} == {E.X}
    assert {s.role for s in effect.inputs + effect.alts[0]} == {None}


def test_declared_kinds_follow_their_names_after_a_colon():
    parsed = parse_effect(" buf: span  c: char  n -- count: u ok: flag ")
    effect = parsed.effect
    assert [s.kind for s in effect.inputs] == [E.ADDR, E.COUNT, E.CHAR, E.X]
    assert [s.role for s in effect.inputs] == ["a", "u", None, None]
    assert [s.kind for s in effect.alts[0]] == [E.COUNT, E.FLAG]
    assert parsed.declared == 4 and parsed.problems == []
    # A bar inside a name says which values the cell may take.
    either = parse_effect(" rec -- port|0: addr status: n ").effect
    assert [(s.name, s.kind) for s in either.alts[0]] == [("port|0", E.ADDR), ("status", E.NUMBER)]


def test_token_effects_nest_and_holds_names_what_a_cell_holds():
    effect = parse_effect(" each: xt( item: addr -- keep: flag ) list -- ").effect
    token = effect.inputs[0]
    assert token.kind == E.XT and token.effect.shape() == "1 -- 1"
    assert token.effect.inputs[0].kind == E.ADDR
    held, problems, declaration = parse_holds(" holds: xt( text: span -- ) ")
    assert declaration and problems == []
    assert held.kind == E.XT and held.effect.shape() == "2 -- 0"
    # Inside a nested effect, i*x marks the token's effect variable, not the word's.
    outer = parse_effect(" run: xt( i*x -- j*x ) -- ").effect
    assert not outer.variable and outer.inputs[0].effect.variable


def test_malformed_declarations_are_reported():
    assert parse_effect(" a: blob -- ").problems == ["a: names an unknown kind 'blob'"]
    assert parse_effect(" a: -- ").problems == ["a: has no kind"]
    assert parse_effect(" run: xt( a -- b ").problems == ["xt( has no closing )"]
    assert parse_holds(" holds: u and more ")[1] == ["text after the declared kind: and more"]
    assert parse_holds(" the count ")[2] is False  # prose, not a declaration


def test_a_bar_alone_separates_alternatives_and_a_bar_inside_names_one_cell():
    whole = parse_effect(" -- s: span true | false ").effect
    assert [len(alt) for alt in whole.alts] == [3, 1]
    assert whole.alts[0][-1].fact == E.NONZERO and whole.alts[1][-1].fact == E.ZERO
    one_cell = parse_effect(" c-addr u -- dentry|0 ior ").effect
    assert [len(alt) for alt in one_cell.alts] == [2]
    found = parse_effect(" c-addr -- c-addr 0 |xt 1 |xt -1 ").effect
    assert [len(alt) for alt in found.alts] == [2, 2, 2]


def test_variable_effects_are_recognized():
    assert parse_effect(" i*x xt -- j*x ").effect.variable
    assert parse_effect(" n -- n*8 ").effect.variable is False


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


def test_a_branch_teaches_copies_of_the_cell_it_tested(base_checker_state):
    checker = check(base_checker_state, (
        ": RETHROW  ( ior -- )  DUP IF THROW THEN DROP ;\n"
    ))
    # In the true branch the cell left under the tested copy is nonzero, so
    # THROW never returns there.
    assert record(checker, "RETHROW").comparison == "match"


def test_a_constant_count_fixes_a_loop_that_changes_depth(base_checker_state):
    checker = check(base_checker_state, (
        ": DROP3  ( a b c -- )  3 0 DO DROP LOOP ;\n"
        ": PUSH2  ( -- i0 i1 )  2 0 DO I LOOP ;\n"
        ": UNKNOWN  ( ... n -- )  0 DO DROP LOOP ;\n"
    ))
    assert record(checker, "DROP3").comparison == "match"
    assert record(checker, "PUSH2").comparison == "match"
    assert record(checker, "UNKNOWN").failure.category == "loop changes the stack depth"


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
        ": FIELD:  ( offset \"name\" -- )  CREATE ,  DOES>  ( body: addr -- a: addr )"
        "  @ CURRENT @ + ;\n"
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


def test_a_comment_on_a_preceding_line_describes_its_own_modules_word(base_checker_state):
    checker = check(base_checker_state, (
        "\\ PAIR ( -- a b )\n"
        ": PAIR  1 2 ;\n"
    ))
    # Another module's PAIR, guarded or not, is a word of its own.
    checker.load_text(": PAIR  3 ;\n", "other.f")
    first, second = [r for r in checker.records if r.word.name == "PAIR"]
    assert first.word.declared_reason == "comment on a preceding line"
    assert first.comparison == "match"
    assert second.comparison == "no comment"


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
        ": MIXED  ( one: span two: span -- )  NIP NIP TYPE ;\n"
        "VARIABLE SLOT\n"
        ": KEEP  ( r: ref -- )  SLOT ! ;\n"
        ": UNDECLARED  ( a1 u1 a2 u2 -- )  NIP NIP TYPE ;\n"
    ))
    assert any(f.startswith("kind: flag used as an address") for f in findings(checker, "FLAG-AS-ADDRESS"))
    assert record(checker, "MIXED").comparison == "match"
    assert any(f.startswith("span: TYPE takes the address of one span")
               for f in findings(checker, "MIXED"))
    assert any("keeps a ref in plain memory" in f for f in findings(checker, "KEEP"))
    # Without declarations the cells are plain, and nothing is guessed.
    assert findings(checker, "UNDECLARED") == []


def test_kind_declarations_add_structs_and_kinds_of_number(base_checker_state):
    checker = check(base_checker_state, (
        "( kind: port struct )\n"
        "( kind: widget struct )\n"
        "( kind: port-status n )\n"
        ": PORT-USE  ( p: port -- s: port-status )  @ ;\n"
        ": FROM-ADDRESS  ( a: addr -- s: port-status )  PORT-USE ;\n"
        ": FROM-WIDGET  ( w: widget -- s: port-status )  PORT-USE ;\n"
        ": FROM-NUMBER  ( n: n -- s: port-status )  PORT-USE ;\n"
        ": STATUS-AS-COUNT  ( p: port -- n: u )  PORT-USE ;\n"
        "( kind: blob gadget )\n"
    ))
    assert findings(checker, "FROM-ADDRESS") == []  # an address may stand for a struct
    assert any(f.startswith("kind: named kinds differ: widget") for f in findings(checker, "FROM-WIDGET"))
    assert any(f.startswith("kind: number used as an address") for f in findings(checker, "FROM-NUMBER"))
    assert findings(checker, "STATUS-AS-COUNT") == []  # a kind of n mixes with numbers
    assert "declaration: kind: blob refines an unknown kind 'gadget'" in all_findings(checker)


def test_object_kinds_refine_ref_and_tagged_and_keep_apart_from_plain_data(base_checker_state):
    checker = check(base_checker_state, (
        "( kind: concept record )\n"
        "( kind: port struct )\n"
        ": NAME@  ( r: ref -- t: tagged )  @ ;\n"
        ": CONCEPT-NAME  ( c: concept -- t: tagged )  NAME@ ;\n"
        ": STRING-NAME  ( s: string -- t: tagged )  NAME@ ;\n"
        ": OPEN  ( p: port -- )  DROP ;\n"
        ": OPEN-CONCEPT  ( c: concept -- )  OPEN ;\n"
        ": TAGGED-AS-REF  ( t: tagged -- )  NAME@ DROP ;\n"
        ": COUNT-AS-TAGGED  ( n: u -- t: tagged )  NAME@ ;\n"
        ": SHOW  ( r: record -- )  DROP ;\n"
        ": SHOW-STRING  ( s: string -- )  SHOW ;\n"
        ": HANDLE-AS-ADDRESS  ( h: handle -- x )  @ ;\n"
        ": HANDLE-AS-REF  ( h: handle -- t: tagged )  NAME@ ;\n"
        "VARIABLE SLOT\n"
        ": KEEP-CONCEPT  ( c: concept -- )  SLOT ! ;\n"
        ": WRITE-CONCEPT  ( x c: concept -- )  ! ;\n"
    ))
    # Part 9d's rules hold for every kind that refines ref.
    assert findings(checker, "KEEP-CONCEPT") == ["managed rule: ! keeps a ref in plain memory"]
    assert findings(checker, "WRITE-CONCEPT") == [
        "managed rule: ! writes a managed object directly"]
    # A record kind is a record, a record a reference: both read directly.
    assert findings(checker, "CONCEPT-NAME") == []
    assert findings(checker, "STRING-NAME") == []
    # A struct is plain memory managed by hand, and a record is not one.
    assert any(f.startswith("kind: managed kind crosses plain data: concept")
               for f in findings(checker, "OPEN-CONCEPT"))
    # Only a reference is read as an address; a tagged word may be a fixnum.
    assert findings(checker, "TAGGED-AS-REF") == []  # a tagged word may stand for a ref
    assert any(f.startswith("kind: managed kind crosses plain data: u")
               for f in findings(checker, "COUNT-AS-TAGGED"))
    assert any(f.startswith("kind: object kinds differ: string")
               for f in findings(checker, "SHOW-STRING"))
    assert findings(checker, "HANDLE-AS-ADDRESS") == ["managed rule: @ reads through a handle"]
    assert any(f.startswith("kind: handle mixed with other data")
               for f in findings(checker, "HANDLE-AS-REF"))


def test_lists_and_handles_take_the_kind_of_what_they_hold(base_checker_state):
    checker = check(base_checker_state, (
        "( kind: concept record )\n"
        "( kind: topic record )\n"
        "( kind: path list( string ) )\n"
        ": LINKS  ( c: concept -- l: list( concept ) )  @ ;\n"
        ": WALK  ( l: list( record ) -- )  DROP ;\n"
        ": WALK-LINKS  ( c: concept -- )  LINKS WALK ;\n"
        ": TOPICS  ( l: list( topic ) -- )  DROP ;\n"
        ": TOPIC-LINKS  ( c: concept -- )  LINKS TOPICS ;\n"
        ": ANY-LIST  ( l: list -- )  DROP ;\n"
        ": PATH-LIST  ( p: path -- )  ANY-LIST ;\n"
        "VARIABLE SHOWN ( holds: handle( concept ) )\n"
        ": KEEP  ( h: handle( record ) -- )  DROP ;\n"
        ": KEEP-SHOWN  ( -- )  SHOWN @ KEEP ;\n"
        ": KEEP-TOPIC  ( h: handle( topic ) -- )  DROP ;\n"
        ": SHOWN-TOPIC  ( -- )  SHOWN @ KEEP-TOPIC ;\n"
    ))
    # list( concept ) refines list( record ), as a concept is a record.
    assert findings(checker, "WALK-LINKS") == []
    assert any(f.startswith("kind: object kinds differ: list(concept)")
               for f in findings(checker, "TOPIC-LINKS"))
    assert findings(checker, "PATH-LIST") == []
    assert findings(checker, "KEEP-SHOWN") == []
    assert any(f.startswith("kind: object kinds differ: handle(concept)")
               for f in findings(checker, "SHOWN-TOPIC"))
    assert checker.kind_parent("list(concept)") == "list(record)"
    assert checker.kind_parent("list(ref)") == E.LIST
    assert checker.kind_parent("handle(record)") == E.HANDLE


def test_parametric_kinds_are_checked_where_they_are_declared():
    assert parse_effect(" l: list( tagged ) -- ").effect.inputs[0].kind == E.LIST
    assert parse_effect(" h: handle( ref ) -- ").effect.inputs[0].kind == E.HANDLE
    assert parse_effect(" l: list( flag ) -- ").effect.inputs[0].kind == "list(flag)"
    assert parse_effect(" l: list( u ) -- ").problems == [
        "l: a list holds tagged words, and u is plain data"]
    assert parse_effect(" h: handle( tagged ) -- ").problems == [
        "h: a handle names an object, and tagged is not a kind of object"]
    assert parse_effect(" l: list( span ) -- ").problems == [
        "l: list( span ) names two cells, not one"]
    assert parse_effect(" l: list( string -- ").problems == ["list( has no closing )"]


def test_malformed_declarations_in_source_are_findings(base_checker_state):
    checker = check(base_checker_state, (
        ": ODD  ( a: blob -- )  DROP ;\n"
        "VARIABLE BROKEN ( holds: xt( a -- )\n"
        "VARIABLE PROSE ( the count of things )\n"
    ))
    assert findings(checker, "ODD") == ["declaration: a: names an unknown kind 'blob'"]
    # KDOS's ( counts the xt( inside, so this comment runs to the line's end.
    assert "declaration: the declaration's ( has no ) on its line" in all_findings(checker)
    assert len(all_findings(checker)) == 2


# Typed slots


def test_a_typed_variable_gives_the_token_it_holds_an_effect(base_checker_state):
    checker = check(base_checker_state, (
        "VARIABLE HOOK ( holds: xt( c: char -- ) )\n"
        ": SHOW  ( c -- )  EMIT ;\n"
        ": TWO  ( a b -- )  2DROP ;\n"
        ": RUN-HOOK  ( c -- )  HOOK @ EXECUTE ;\n"
        ": TRY-HOOK  ( c -- ior )  HOOK @ CATCH DUP IF NIP THEN ;\n"
        ": INSTALL  ( -- )  ['] SHOW HOOK ! ;\n"
        ": BAD-INSTALL  ( -- )  ['] TWO HOOK ! ;\n"
        ": UNTYPED  ( c -- )  HOOK CELL+ @ EXECUTE ;\n"
    ))
    assert record(checker, "RUN-HOOK").comparison == "match"
    assert record(checker, "RUN-HOOK").declared_tokens == 1
    assert record(checker, "TRY-HOOK").comparison == "match"
    assert findings(checker, "INSTALL") == [] and record(checker, "INSTALL").typed_stores_checked == 1
    assert any(f.startswith("token effect: TWO ( 2 -- 0 ) stored by ! into HOOK")
               for f in findings(checker, "BAD-INSTALL"))
    # The cell after a variable is outside it, so it holds nothing declared.
    assert record(checker, "UNTYPED").failure.category == "EXECUTE of an unknown xt"


def test_struct_fields_and_tables_declare_what_they_hold(base_checker_state):
    checker = check(base_checker_state, (
        "( kind: port struct )\n"
        " 0 CONSTANT _P-CONTEXT\n"
        " 8 CONSTANT _P-SEND ( holds: xt( buf: span context -- count: u ) )\n"
        ": P.SEND  ( p: port -- a )  _P-SEND + ;\n"
        ": PORT-SEND  ( buf: span p: port -- count: u )\n"
        "    DUP _P-CONTEXT + @ SWAP P.SEND @ EXECUTE ;\n"
        ": PORT-SEND-INLINE  ( buf: span p: port -- count: u )\n"
        "    DUP @ SWAP _P-SEND + @ EXECUTE ;\n"
        "CREATE OPS ( holds: xt( n -- n ) )\n"
        ": OP  ( n i -- n )  CELLS OPS + @ EXECUTE ;\n"
    ))
    assert record(checker, "PORT-SEND").comparison == "match"
    assert record(checker, "PORT-SEND-INLINE").comparison == "match"
    assert record(checker, "OP").comparison == "match"
    accessor = checker.lookup("P.SEND").signature.alts[0][0]
    assert accessor.holds is not None and accessor.holds.effect.shape() == "3 -- 1"


def test_a_named_effect_is_declared_once_and_shared_by_its_slots(base_checker_state):
    checker = check(base_checker_state, (
        "( kind: port struct )\n"
        "( kind: status n )\n"
        "( kind: port-io xt( buf: span context -- count: u s: status ) )\n"
        "( kind: port-recv port-io )\n"
        " 8 CONSTANT _P-RECV ( holds: port-io )\n"
        "16 CONSTANT _P-SEND ( holds: port-io )\n"
        ": PORT-RECV  ( buf: span p: port -- count: u s: status )\n"
        "    DUP @ SWAP _P-RECV + @ EXECUTE ;\n"
        ": PORT-SEND  ( buf: span p: port -- count: u s: status )\n"
        "    DUP @ SWAP _P-SEND + @ EXECUTE ;\n"
        ": GOOD-IO  ( buf: span context -- count: u s: status )  DROP NIP 0 ;\n"
        ": WRONG-IO  ( buf: span context -- count: u )  DROP NIP ;\n"
        ": INSTALL  ( p: port -- )  ['] GOOD-IO SWAP _P-RECV + ! ;\n"
        ": BAD-INSTALL  ( p: port -- )  ['] WRONG-IO SWAP _P-SEND + ! ;\n"
        ": WITH-IO  ( buf: span context io: port-recv -- count: u s: status )  EXECUTE ;\n"
        ": USE-IO  ( buf: span context -- count: u s: status )  ['] GOOD-IO WITH-IO ;\n"
    ))
    assert record(checker, "PORT-RECV").comparison == "match"
    assert record(checker, "PORT-SEND").comparison == "match"
    assert findings(checker, "INSTALL") == []
    assert record(checker, "INSTALL").typed_stores_checked == 1
    assert any(f.startswith("token effect: WRONG-IO ( 3 -- 1 ) stored by ! into")
               for f in findings(checker, "BAD-INSTALL"))
    # A second name for an effect, and a named effect as a typed input.
    assert record(checker, "WITH-IO").comparison == "match"
    assert not record(checker, "WITH-IO").word.higher_order
    assert record(checker, "USE-IO").comparison == "match" and findings(checker, "USE-IO") == []
    assert {name for group, name in checker.named_effects} == {"port-io", "port-recv"}


def test_named_effects_are_checked_where_they_are_declared(base_checker_state):
    checker = check(base_checker_state, (
        "( kind: hook xt( c: char -- ) )\n"
        "( kind: hook xt( c: char -- ) )\n"
        "( kind: hook xt( -- ) )\n"
        "( kind: hook struct )\n"
        "( kind: grab xt( i*x -- j*x ) )\n"
        "( kind: hooks list( hook ) )\n"
        "( kind: plain xt )\n"
    ))
    assert all_findings(checker) == [
        "declaration: kind: hook already names another effect",
        "declaration: kind: hook already names an effect",
        "declaration: kind: grab names an effect that is not fixed",
        "declaration: kind: hooks: list( xt ): an execution token is plain data",
        "declaration: kind: plain cannot refine xt",
    ]


def test_children_of_defining_words_take_holds_declarations(base_checker_state):
    checker = check(base_checker_state, (
        "VARIABLE _LAYOUT-OFF\n"
        ": CMP-FIELD:  ( current-state-cell bytes \"name\" -- )\n"
        "    CREATE SWAP , _LAYOUT-OFF @ , _LAYOUT-OFF +!\n"
        "    DOES>  ( body -- field-addr )  DUP @ @ SWAP 8 + @ + ;\n"
        ": CMP-CELL:  ( current-state-cell \"name\" -- )  8 CMP-FIELD: ;\n"
        "VARIABLE _STATE\n"
        "_STATE CMP-CELL: _ON-CLOSE ( holds: xt( context -- ior: n ) )\n"
        ": CLOSE  ( context -- ior )  _ON-CLOSE @ EXECUTE ;\n"
        "_STATE CMP-CELL: _COUNT ( holds: u )\n"
        ": BUMP  ( -- )  _COUNT @ 1+ _COUNT ! ;\n"
    ))
    assert record(checker, "CLOSE").comparison == "match"
    assert findings(checker, "BUMP") == []


def test_a_typed_token_input_is_checked_at_each_call(base_checker_state):
    checker = check(base_checker_state, (
        ": APPLY  ( n f: xt( n -- n ) -- n )  EXECUTE ;\n"
        ": DOUBLE  ( n -- n )  2* ;\n"
        ": PAIR  ( n -- n n )  DUP ;\n"
        ": USE  ( n -- n )  ['] DOUBLE APPLY ;\n"
        ": MISUSE  ( n -- n )  ['] PAIR APPLY ;\n"
        "0 VALUE CB ( holds: xt( -- ) )\n"
        ": RUN-CB  ( -- )  CB EXECUTE ;\n"
    ))
    assert not record(checker, "APPLY").word.higher_order
    assert record(checker, "APPLY").comparison == "match"
    assert record(checker, "USE").comparison == "match" and findings(checker, "USE") == []
    assert any(f.startswith("token effect: PAIR ( 1 -- 2 ) passed to APPLY")
               for f in findings(checker, "MISUSE"))
    assert record(checker, "RUN-CB").comparison == "match"


def test_a_setter_learns_the_effect_of_the_slot_it_fills(base_checker_state):
    checker = check(base_checker_state, (
        "VARIABLE HOOK ( holds: xt( n -- ) )\n"
        ": HOOK!  ( xt -- )  HOOK ! ;\n"
        ": SINK  ( n -- )  DROP ;\n"
        ": PAIR  ( n -- n n )  DUP ;\n"
        ": GOOD  ( -- )  ['] SINK HOOK! ;\n"
        ": BAD  ( -- )  ['] PAIR HOOK! ;\n"
    ))
    assert checker.lookup("HOOK!").signature.inputs[0].effect.shape() == "1 -- 0"
    assert findings(checker, "GOOD") == []
    assert any(f.startswith("token effect: PAIR") for f in findings(checker, "BAD"))


def test_a_token_given_to_an_inlined_word_makes_the_caller_run_what_it_is_given(base_checker_state):
    checker = check(base_checker_state, (
        ": RISKY  ( a b -- c )  + ;\n"
        ": WITH  ( xt n -- )  >R CATCH R> DROP THROW ;\n"
        ": OUTER  ( xt -- )  7 WITH ;\n"
        ": USE-OUTER  ( a b -- c )  ['] RISKY OUTER ;\n"
        ": INNER  ( i*x xt -- j*x )  3 WITH ;\n"
        ": NESTED  ( i*x xt n -- j*x )  DROP ['] INNER 5 WITH ;\n"
        ": USE-NESTED  ( a b -- c )  ['] RISKY 9 NESTED ;\n"
    ))
    assert record(checker, "OUTER").word.higher_order
    assert record(checker, "USE-OUTER").comparison == "match"
    # WITH inlined again inside its own inlining is nesting, not recursion.
    assert record(checker, "NESTED").word.higher_order
    assert record(checker, "USE-NESTED").comparison == "match"


# Spans and sub-spans


def test_a_prefix_checked_against_a_longer_span_is_part_of_it(base_checker_state):
    checker = check(base_checker_state, (
        ": PREFIX?  ( line: span prefix: span -- f: flag )\n"
        "    ROT OVER < IF 2DROP DROP 0 EXIT THEN  TUCK COMPARE 0= ;\n"
        ": PREFIX-UNCHECKED?  ( line: span prefix: span -- f: flag )\n"
        "    ROT DROP TUCK COMPARE 0= ;\n"
        ": COMMON  ( one: span two: span -- n: n )  ROT MIN TUCK COMPARE ;\n"
    ))
    assert findings(checker, "PREFIX?") == []
    assert any(f.startswith("span: COMPARE takes the address of one span (line)")
               for f in findings(checker, "PREFIX-UNCHECKED?"))
    assert findings(checker, "COMMON") == []


def test_a_bar_inside_a_label_names_the_values_its_cell_may_take(base_checker_state):
    effect = parse_effect(" r: addr -- port|0: nio-port status: n ").effect
    assert [s.name for s in effect.alts[0]] == ["port|0", "status"]
    assert len(effect.alts) == 1  # one cell, not two alternatives
    checker = check(base_checker_state, (
        "( kind: port struct )\n"
        "( kind: other struct )\n"
        ": ADOPT  ( r: addr -- port|0: port status: n )  @ 0 ;\n"
        ": USE-PORT  ( p: port -- )  DROP ;\n"
        ": USE-OTHER  ( o: other -- )  DROP ;\n"
        ": ADOPTED  ( r: addr -- )  ADOPT DROP ?DUP IF USE-PORT THEN ;\n"
        ": CONFUSED  ( r: addr -- )  ADOPT DROP ?DUP IF USE-OTHER THEN ;\n"
    ))
    # The cell is a port when it is not zero.
    assert record(checker, "ADOPT").comparison == "match"
    assert findings(checker, "ADOPTED") == []
    assert any(f.startswith("kind: named kinds differ: port")
               for f in findings(checker, "CONFUSED"))


def test_a_primed_output_span_is_part_of_the_input_span(base_checker_state):
    effect = parse_effect(" s: span n -- s': span ").effect
    assert [s.part_of for s in effect.alts[0]] == [0, 0]
    assert parse_effect(" s: span -- t: span ").effect.alts[0][0].part_of is None
    checker = check(base_checker_state, (
        ": SKIP1  ( s: span -- s': span )  1- SWAP 1+ SWAP ;\n"
        ": REST  ( s: span -- )  SKIP1 TYPE ;\n"
        ": CROSSED  ( one: span two: span -- )  SKIP1 ROT DROP NIP TYPE ;\n"
    ))
    assert findings(checker, "REST") == []
    assert any(f.startswith("span: TYPE takes the address of one span")
               for f in findings(checker, "CROSSED"))


# Strict placement


def test_strict_mode_trusts_no_comment(base_checker_state):
    source = (
        "VARIABLE VTABLE\n"
        ": OPAQUE  ( a -- b )  VTABLE @ EXECUTE ;\n"
        ": CALLER  ( a -- b )  OPAQUE 1+ ;\n"
        ": COUNTDOWN  ( n -- )  DUP IF 1- COUNTDOWN ELSE DROP THEN ;\n"
        ": WRONG-REC  ( n -- n )  DUP IF 1- WRONG-REC THEN DROP ;\n"
    )
    plain = check(base_checker_state, source)
    strict = check(base_checker_state, source, strict=True)
    assert record(plain, "CALLER").status == "inferred"
    assert record(strict, "CALLER").failure.category == "calls a word whose effect is unknown"
    assert record(strict, "COUNTDOWN").status == "inferred"
    assert record(plain, "WRONG-REC").status == "inferred"
    assert record(strict, "WRONG-REC").failure.category == "recursion the body does not confirm"


def test_placement_excludes_words_resting_on_declared_token_effects(base_checker_state):
    strict = check(base_checker_state, (
        "VARIABLE HOOK ( holds: xt( n -- n ) )\n"
        ": RUN-HOOK  ( n -- n )  HOOK @ EXECUTE ;\n"
        ": ABOVE  ( n -- n )  RUN-HOOK 1+ ;\n"
        ": PLAIN  ( n -- n )  1+ ;\n"
        ": ALSO-PLAIN  ( n -- n )  PLAIN PLAIN ;\n"
        "VARIABLE SLOT\n"
        ": BROKEN  ( -- )  SLOT @ EXECUTE ;\n"
        ": NAMES-ONLY  ( -- )  ['] BROKEN SLOT ! ;\n"
        ": DEAD-CODE  ( n -- n )  EXIT BROKEN ;\n"
    ), strict=True)
    summary, qualifying = placement(strict, "library", 3)
    names = {r.word.name for r in qualifying}
    # Naming a token, or a call no path reaches, leaves the effect to code.
    assert {"PLAIN", "ALSO-PLAIN", "NAMES-ONLY", "DEAD-CODE"} <= names
    assert not names & {"RUN-HOOK", "ABOVE", "BROKEN"}
    assert summary["inferred in the strict run"] == 6


def test_bios_effects_come_from_both_forms_of_the_dictionary_tables(base_checker_state):
    checker = check(base_checker_state, "")
    # Numbered tables put the word second; the span tables put it first.
    assert checker.lookup("WITHIN").signature.shape() == "3 -- 1"
    assert checker.lookup("CALLER-SPAN-STATUS").signature.shape() == "2 -- 1"


def test_megapad_is_found_beside_akashic_as_a_workspace_links_them(tmp_path, monkeypatch):
    # A workspace links checkouts that live elsewhere side by side.
    checkouts = tmp_path / "checkouts"
    (checkouts / "akashic").mkdir(parents=True)
    (checkouts / "megapad").mkdir()
    (checkouts / "megapad" / "kdos.f").write_text("")
    workspace = tmp_path / "workspace"
    (workspace / "megapad").mkdir(parents=True)
    (workspace / "megapad" / "kdos.f").write_text("")
    (workspace / "akashic").symlink_to(checkouts / "akashic")
    monkeypatch.delenv("MEGAPAD_ROOT", raising=False)
    assert megapad_root(workspace / "akashic") == workspace / "megapad"
    # Without a MegaPad in the workspace, the one beside the link's target.
    (workspace / "megapad" / "kdos.f").unlink()
    assert megapad_root(workspace / "akashic") == checkouts / "megapad"
    monkeypatch.setenv("MEGAPAD_ROOT", str(tmp_path / "chosen"))
    assert megapad_root(workspace / "akashic") == tmp_path / "chosen"


def test_kdos_catch_and_throw_keep_their_exact_meaning(base_checker_state):
    checker = check(base_checker_state, "")
    assert checker.lookup("CATCH").prim == "CATCH"
    assert checker.lookup("THROW").prim == "THROW"
    assert len([r for r in checker.records if r.group == "base"]) > 800


# The base words' declarations in MegaPad's uroko.f


def test_uroko_declares_the_base_words_kinds(base_checker_state):
    checker = Checker()
    checker.load_bios(base_checker_state)
    checker.load_base(base_checker_state)  # every base module, as the measurement loads them
    assert [f.detail for f in checker.findings if f.module == "uroko.f"] == []
    compare = checker.lookup("COMPARE").signature
    assert [s.role for s in compare.inputs] == ["a", "u", "a", "u"]
    assert [s.kind for s in checker.lookup("ALLOCATE").signature.alts[0]] == [E.ADDR, E.NUMBER]
    assert checker.lookup("FREE").declared_text == "a: addr --"
    # Words the dictionary's tables catalogue, with their kinds.
    assert checker.lookup("TERMSIZE").signature.shape() == "0 -- 2"
    assert checker.lookup("HBW-BASE").signature.alts[0][0].kind == E.ADDR
    assert checker.lookup("_RELOC-COUNT").signature.alts[0][0].holds.kind == E.COUNT
    assert checker.lookup("2@").signature.shape() == "1 -- 2"


def test_effect_declares_a_words_kinds_and_keeps_its_shape(base_checker_state):
    checker = check(base_checker_state, (
        ": PAIR  ( a b -- c )  + ;\n"
        "EFFECT PAIR ( a: addr n: n -- a': addr )\n"
        "EFFECT PAIR ( a -- b )\n"
        "EFFECT NOWHERE ( -- )\n"
        "EFFECT PAIR\n"
        "EFFECT PAIR ( a: blob n -- c )\n"
        ": SCREEN-AREA  ( -- n )  TERMSIZE * ;\n"
        ": HBW-END  ( -- a )  HBW-BASE HBW-SIZE + ;\n"
    ))
    assert [s.kind for s in checker.lookup("PAIR").signature.inputs] == [E.ADDR, E.NUMBER]
    assert all_findings(checker) == [
        "declaration: EFFECT PAIR ( 1 -- 1 ) changes its effect ( 2 -- 1 )",
        "declaration: EFFECT names NOWHERE, which no word defines",
        "declaration: EFFECT PAIR has no effect after its name",
        "declaration: a: names an unknown kind 'blob'",
    ]
    # Words whose effects the dictionary lacked before now infer.
    assert record(checker, "SCREEN-AREA").comparison == "match"
    assert record(checker, "HBW-END").word.inferred.alts[0][0].kind == E.ADDR
