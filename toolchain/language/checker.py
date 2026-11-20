"""Infer stack effects of Forth definitions and follow kinds through them.

The checker loads source the way KDOS does: a word must be defined before it
is used, names ignore case so a later definition hides an earlier one, and a
colon definition can name itself, because ``:`` publishes its header at once
(BIOS ``w_colon`` sets LATEST before the body compiles).  Each colon
definition is analyzed at its ``;`` by abstract interpretation: the body
runs on stacks of abstract values, each with a kind, an identity and what is
known about it (a constant, a zero or nonzero fact, the word an execution
token names, the span it belongs to).  A value keeps its identity through
every shuffle and through the return stack, which is how the checker follows
kinds, spans and execution tokens.

Inputs are discovered as the body reaches below what it pushed.  Control
flow follows the BIOS compiler's own structure: IF, ELSE and THEN fork and
join states; BEGIN, WHILE, REPEAT, UNTIL and AGAIN check that each pass
leaves the depth it found; DO loops park a two-cell frame on the return
stack, which I, J, LEAVE, UNLOOP and EXIT must respect.  States whose depths
differ are kept apart, so ``( -- addr len true | false )`` is inferred when
an IF later routes on the known zero or nonzero top cell, as it does after
``?DUP`` and ``CATCH``.
"""

from __future__ import annotations

import itertools
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from . import effects as E
from .effects import (Effect, Slot, effect_shape, parse_effect, parse_holds,
                      parse_kind_declaration)
from .source import LineCursor, lines, parse_number, wrap
from .vocabulary import BASE_DECLARATIONS, bios_words

_ident_counter = itertools.count(1)
_span_counter = itertools.count(1)

CONTROL = {
    "IF", "ELSE", "THEN", "BEGIN", "UNTIL", "AGAIN", "WHILE", "REPEAT",
    "DO", "?DO", "LOOP", "+LOOP", "LEAVE", "UNLOOP", "EXIT", "RECURSE",
    "CASE", "OF", "ENDOF", "ENDCASE",
}

# Words that make a new definition when they run.
CREATING = {"CREATE", "VARIABLE", "CONSTANT", "VALUE", "DEFER", ":", "MARKER", "2VARIABLE", "2CONSTANT"}


class Fail(Exception):
    """A definition whose effect the checker cannot fix."""

    def __init__(self, category: str, detail: str = "", line: int | None = None,
                 root: tuple[str, str] | None = None) -> None:
        super().__init__(f"{category}: {detail}")
        self.category = category
        self.detail = detail
        self.line = line
        self.root = root or (category, detail)


class Value:
    """An abstract cell."""

    __slots__ = ("kind", "const", "xt", "fact", "span", "role", "origin", "ident", "source",
                 "disc", "effect", "holds", "array", "bounds", "rel_true", "rel_false")

    def __init__(self, kind: str = E.X, *, const: int | None = None, xt=None,
                 fact: int | None = None, span=None, role: str | None = None,
                 origin: str = "", ident=None, source: str = "computed",
                 disc: bool = False, effect: Effect | None = None,
                 holds: Slot | None = None, array: bool = False,
                 bounds: frozenset = frozenset(), rel_true: frozenset = frozenset(),
                 rel_false: frozenset = frozenset()) -> None:
        self.kind = kind
        self.const = const
        self.xt = xt
        if fact is None and const is not None:
            fact = E.ZERO if const == 0 else E.NONZERO
        self.fact = fact
        self.span = span
        self.role = role
        self.origin = origin
        self.ident = ident if ident is not None else next(_ident_counter)
        # Where the value came from: "input", "literal", "memory", "computed".
        self.source = source
        # True for a cell whose zero or nonzero value tells alternatives apart,
        # such as CATCH's code or the copies ?DUP leaves.
        self.disc = disc
        # A declared execution token's effect, as read from a typed slot.
        self.effect = effect
        # An address: what the cell it points at holds, and whether every
        # cell from here on holds the same (a CREATE table).  A field offset
        # declared with holds carries what its field holds.
        self.holds = holds
        self.array = array
        # Spans this value is known to be no longer than, beyond its own
        # span: a length checked against a span's length, or a MIN of two.
        self.bounds = bounds
        # A flag from comparing two lengths: (value ident, span) pairs whose
        # value is no longer than the span when the flag is true or false.
        self.rel_true = rel_true
        self.rel_false = rel_false

    def copy_with(self, **changes) -> "Value":
        """A copy with the same identity, as a branch learns more about it."""
        fields = {name: getattr(self, name) for name in self.__slots__}
        fields.update(changes)
        kind = fields.pop("kind")
        return Value(kind, **fields)

    def with_fact(self, fact: int | None, disc: bool | None = None) -> "Value":
        return self.copy_with(fact=fact, disc=self.disc if disc is None else disc)

    def __repr__(self) -> str:
        return f"<{self.kind} {self.origin}>"


def literal(number: int, origin: str = "") -> Value:
    return Value(E.LIT, const=wrap(number), origin=origin or str(number), source="literal")


class LoopFrame:
    """The two cells DO parks on the return stack: limit and index.

    The index has the kind of the start value, so a loop that walks
    addresses, as ``end start DO I C@ ... LOOP`` does, yields addresses.  A
    start written as a number serves as any kind, so its index has none.
    """

    __slots__ = ("index", "ident")

    def __init__(self, start: Value | None = None) -> None:
        kind = E.NUMBER
        if start is not None and start.kind in (E.ADDR, E.X, E.LIT):
            kind = E.X if start.kind == E.LIT else start.kind
        self.index = Value(kind, origin="loop index", source="computed")
        self.ident = next(_ident_counter)


class State:
    """One path's data and return stacks.

    ``items`` holds the cells above ``floor``: the stack is the entry stack
    less its top ``floor`` cells, with ``items`` pushed on it.
    """

    __slots__ = ("items", "floor", "r")

    def __init__(self, items=None, floor: int = 0, r=None) -> None:
        self.items = items if items is not None else []
        self.floor = floor
        self.r = r if r is not None else []

    def copy(self) -> "State":
        return State(list(self.items), self.floor, list(self.r))

    @property
    def depth(self) -> int:
        return len(self.items) - self.floor


@dataclass(eq=False)
class Word:
    """A dictionary entry."""

    name: str
    module: str
    line: int
    origin: str  # "bios", "base" (KDOS and system modules) or "source"
    immediate: bool = False
    kind: str = "colon"  # colon, variable, constant, value, create, defer, child, prim
    declared: Effect | None = field(default=None, repr=False)
    declared_text: str | None = None
    declared_reason: str | None = field(default=None, repr=False)
    signature: Effect | None = field(default=None, repr=False)
    signature_source: str | None = None  # inferred, declared, given
    inferred: Effect | None = field(default=None, repr=False)
    failure: Fail | None = field(default=None, repr=False)
    higher_order: bool = False
    items: list | None = field(default=None, repr=False)
    child: Effect | None = field(default=None, repr=False)
    parses: int = field(default=0, repr=False)
    prim: str | None = field(default=None, repr=False)
    xt: "Word | None" = field(default=None, repr=False)  # a constant holding an xt
    const: int | None = field(default=None, repr=False)
    compiling: bool = field(default=False, repr=False)
    record: "Record | None" = field(default=None, repr=False)
    hides: "Word | None" = field(default=None, repr=False)
    end_line: int = field(default=0, repr=False)
    # A data word's declared content: what its cell, value or field holds.
    holds: Slot | None = field(default=None, repr=False)
    # A kind declared with ( kind: NAME BASE ), kept in the dictionary under
    # a key no Forth token can spell, so REQUIRE closures carry it.
    kind_parent: str | None = field(default=None, repr=False)
    problems: list = field(default_factory=list, repr=False)
    declared_count: int = field(default=0, repr=False)


@dataclass
class Finding:
    category: str
    detail: str
    module: str
    line: int
    word: str
    group: str = ""


@dataclass
class Record:
    """What the checker found for one colon definition."""

    word: Word
    group: str
    status: str = "pending"  # inferred, failed
    comparison: str = ""
    failure: Fail | None = None
    relies_on_declared: set = field(default_factory=set)
    findings: list = field(default_factory=list)
    self_named: bool = False
    hides_older: bool = False
    # Calls whose effect came from a declaration rather than from code: a
    # token read from a typed slot, a typed token input, or a deferred word.
    declared_tokens: int = 0
    declared_token_sources: dict = field(default_factory=dict)
    # Declared items in the stack comment, and whether recursion assumed it.
    declared_items: int = 0
    recursion_assumed: bool = False
    # Tokens stored into slots that declare an effect: how many the checker
    # compared with the declaration, and how many it could not, because the
    # token came from a cell of unknown origin.
    typed_stores_checked: int = 0
    typed_stores_unchecked: int = 0


@dataclass
class Pending:
    """A colon definition being compiled."""

    word: Word
    items: list = field(default_factory=list)
    header_open: bool = True
    does_comment: str | None = None
    after_does: bool = False
    interp: bool = False
    outer: "Pending | None" = None
    quotation: bool = False
    header_lines: list = field(default_factory=list)
    header_parens: list = field(default_factory=list)
    header_done: bool = False


KIND_KEY = "KIND "  # dictionary keys of declared kinds; no token holds a space


class Checker:
    """Loads Forth source and checks each colon definition as it is defined.

    In strict mode no stack comment stands in for code: a definition whose
    effect cannot be inferred gives its callers nothing, recursion must
    confirm the effect it assumed, and a comment lends no zero or nonzero
    facts.  The words strict mode infers are the ones release plan decision
    32 allows on LM1, less those that rest on a declared token effect, which
    each record counts.
    """

    def __init__(self, strict: bool = False) -> None:
        self.strict = strict
        # Every kind declared anywhere, for comparing kinds that flow between
        # modules; resolving a name in a declaration uses the dictionary.
        self.all_kinds: dict[str, str] = {}
        self.words: dict[str, Word] = {}
        self.records: list[Record] = []
        self.findings: list[Finding] = []
        self.top: list[Value] = []
        self.base = 10
        self.pending: Pending | None = None
        self.skipping = False
        self.skip_depth = 0
        self.skip_else_stops = True
        self.cond_frames: list[str] = []
        self.group = "base"
        self.module = ""
        self.line = 0
        self.require: Callable[[str, str], None] | None = None
        self.unknown_conditions = 0
        self.top_undefined: dict[str, int] = {}
        # "\ NAME ( effect )" lines, which KDOS writes above a definition.
        self.preceding: dict[str, str] = {}
        self.inlining: list[Word] = []
        # Data words declared with ( holds: KIND ), as (group, word).
        self.typed_slots: list[tuple[str, Word]] = []
        # Kinds declared with ( kind: NAME BASE ), as (group, name).
        self.declared_kinds: list[tuple[str, str]] = []
        # When a list, each analyzed step appends (line, op, word, depths).
        self.trace: list | None = None
        self.defined_here: dict[str, Word] | None = None

    # ------------------------------------------------------------------
    # Loading

    def load_bios(self, megapad_root: Path) -> None:
        for name, entry in bios_words(megapad_root).items():
            word = Word(name, "bios.asm", 0, "bios", entry.immediate, "prim")
            if entry.effect_text:
                inner = entry.effect_text.strip()[1:-1]
                effect = parse_effect(inner).effect
                word.declared = effect
                word.declared_text = entry.effect_text
                word.parses = effect.parses if effect else 0
                if effect is not None and not effect.variable:
                    word.signature = effect
                    word.signature_source = "given"
            if name in PRIMS:
                word.prim = name
            self.words[name] = word
        self._declare_base_kinds("bios")

    def load_base(self, megapad_root: Path, modules: tuple[str, ...]) -> None:
        """Load KDOS and system modules; their words take their comments' effects."""
        self.group = "base"
        for module in modules:
            path = megapad_root / module
            self.load_text(path.read_text(encoding="utf-8", errors="replace"), module)
        self._declare_base_kinds("base")
        self.group = "library"

    def _declare_base_kinds(self, origin: str) -> None:
        """Give base words the kinds the toolchain declares for them.

        The base vocabulary's comments and tables name cells informally, so
        the kinds of its words are declared in the toolchain
        (``vocabulary.BASE_DECLARATIONS``), each with the shape its given
        effect already has.
        """
        for name, text in BASE_DECLARATIONS.items():
            word = self.words.get(name)
            if word is None or word.origin != origin:
                continue
            parsed = parse_effect(text[1:-1].strip(), self.resolve_kind)
            given = word.signature or word.declared
            effect = parsed.effect
            if effect is None or parsed.problems:
                raise ValueError(f"base declaration of {name} is malformed: {parsed.problems}")
            if given is not None and not given.variable and effect_shape(given) != effect_shape(effect):
                raise ValueError(f"base declaration of {name} changes its effect {given.shape()}")
            word.declared = effect
            word.declared_text = text[1:-1].strip()
            if word.prim is None or word.prim not in PRIM_HANDLERS:
                word.signature = effect
                word.signature_source = "given"

    # Kinds

    def resolve_kind(self, name: str) -> str | None:
        """The kind a declaration's name stands for, if this module sees it."""
        lowered = name.lower()
        builtin = E.BUILTIN_KINDS.get(lowered)
        if builtin is not None:
            return builtin
        entry = self.words.get(KIND_KEY + lowered.upper())
        return entry.name if entry is not None else None

    def kind_parent(self, kind: str) -> str | None:
        if kind in E.BUILTIN_PARENTS:
            return E.BUILTIN_PARENTS[kind]
        return self.all_kinds.get(kind)

    def compatible(self, value_kind: str, param_kind: str) -> str | None:
        return E.compatible(value_kind, param_kind, self.kind_parent)

    def refines(self, kind: str, ancestor: str) -> bool:
        """Whether ``kind`` is ``ancestor`` or a kind declared to refine it."""
        seen = set()
        while kind is not None and kind not in seen:
            if kind == ancestor:
                return True
            seen.add(kind)
            kind = self.kind_parent(kind)
        return False

    def declare_kind(self, name: str, parent: str) -> str | None:
        """Add a kind; a problem when the name already means another kind."""
        key = KIND_KEY + name.upper()
        existing = self.words.get(key)
        if existing is not None and existing.kind_parent != parent:
            return f"kind: {name} already refines {existing.kind_parent}"
        known = self.all_kinds.get(name)
        if known is not None and known != parent:
            return f"kind: {name} refines {known} elsewhere"
        entry = Word(name, self.module, self.line, self._origin(), kind="kind")
        entry.kind_parent = parent
        self.define_entry(key, entry)
        self.all_kinds[name] = parent
        return None

    def define_entry(self, key: str, word: Word) -> None:
        self.words[key] = word
        if self.defined_here is not None:
            self.defined_here[key] = word

    def declaration_problem(self, detail: str, name: str, record: "Record | None" = None,
                            line: int | None = None) -> None:
        self.findings.append(Finding("declaration", detail, self.module,
                                     line or self.line, name,
                                     record.group if record is not None else self.group))
        if record is not None:
            record.findings.append(self.findings[-1])

    def load_text(self, text: str, module: str) -> None:
        saved = (self.module, self.line, self.base)
        self.module = module
        for cursor in lines(text):
            self.line = cursor.number
            self._interpret_line(cursor)
        if self.pending is not None and self.pending.outer is None:
            # A definition left open at the end of a file is abandoned.
            self.pending = None
        self.module, self.line, _ = saved

    def define(self, word: Word) -> Word:
        key = word.name.upper()
        word.hides = self.words.get(key)
        self.words[key] = word
        if self.defined_here is not None:
            self.defined_here[key] = word
        return word

    def begin_module(self, visible: dict[str, Word], group: str) -> dict[str, Word]:
        """Start a module whose dictionary holds exactly what ``visible`` holds.

        The measurement checks each module against the base vocabulary and
        the modules its REQUIRE lines load, as an image would hold them.
        The returned map collects the words the module defines.
        """
        self.words = visible
        self.defined_here = {}
        self.group = group
        self.top.clear()
        self.base = 10
        self.skipping = False
        self.cond_frames.clear()
        self.pending = None
        return self.defined_here

    def lookup(self, name: str) -> Word | None:
        return self.words.get(name.upper())

    # ------------------------------------------------------------------
    # The outer interpreter

    def _interpret_line(self, cursor: LineCursor) -> None:
        while True:
            if self.skipping:
                self._skip_scan(cursor)
                if self.skipping:
                    return
                continue
            token = cursor.token()
            if token is None:
                return
            if token[0] == "\\":
                rest = cursor.rest()
                if token == "\\" and self.pending is None:
                    self._note_preceding(rest)
                elif token == "\\" and self.pending.header_open:
                    self._note_header_line(self.pending, rest)
                return
            if self.pending is not None and not self.pending.interp:
                self._compile(token, cursor)
            else:
                self._execute(token, cursor)

    def _note_header_line(self, pending: Pending, text: str) -> None:
        """A stack comment written in backslash lines just after the name.

        ``: NAME`` followed by ``\\ ( a b`` and ``\\   -- c )`` declares the
        effect across two comment lines, which the paren rule cannot.
        """
        if pending.header_done:
            return
        stripped = text.strip()
        if not pending.header_lines and not stripped.startswith("("):
            return
        pending.header_lines.append(stripped)
        joined = " ".join(pending.header_lines)
        cursor = LineCursor(joined, 0)
        if cursor.token() != "(":
            pending.header_lines.clear()
            return
        inner, closed = cursor.paren_closed()
        if not closed:
            return  # the comment continues on the next line
        if "--" in inner.split():
            self._set_declared(pending.word, inner)
            pending.word.declared_reason = pending.word.declared_reason or "comment in backslash lines"
            pending.header_done = True
        pending.header_lines.clear()

    def _note_preceding(self, text: str) -> None:
        """Remember a ``\\ NAME ( effect )`` line, read with BIOS's paren rule."""
        cursor = LineCursor(text, 0)
        name = cursor.token()
        if name is None or cursor.token() != "(":
            return
        comment = cursor.paren()
        if "--" in comment.split():
            self.preceding[name.upper()] = comment

    def _skip_scan(self, cursor: LineCursor) -> None:
        """Skip a false [IF] branch as BIOS does: raw tokens, no comments."""
        while True:
            token = cursor.token()
            if token is None:
                return
            upper = token.upper()
            if upper == "[IF]":
                self.skip_depth += 1
            elif upper == "[ELSE]":
                if self.skip_depth == 0 and self.skip_else_stops:
                    self.skipping = False
                    self.cond_frames.append("else")
                    return
            elif upper == "[THEN]":
                if self.skip_depth == 0:
                    self.skipping = False
                    return
                self.skip_depth -= 1

    def _start_skip(self, else_stops: bool) -> None:
        self.skipping = True
        self.skip_depth = 0
        self.skip_else_stops = else_stops

    def _pop_top(self) -> Value:
        if self.top:
            return self.top.pop()
        return Value(origin="top-level stack underflow")

    def _execute(self, token: str, cursor: LineCursor) -> None:
        upper = token.upper()
        if upper == "]" and self.pending is not None:
            self.pending.interp = False
            return
        word = self.words.get(upper)
        if word is None:
            number = parse_number(token, self.base)
            if number is not None:
                self.top.append(literal(number))
                return
            self.top_undefined[token] = self.top_undefined.get(token, 0) + 1
            self.top.clear()
            return
        handler = TOP_HANDLERS.get(upper) if word.origin in ("bios", "base") else None
        if handler is not None and (word.origin == "bios" or upper in BASE_TOP):
            handler(self, cursor, word)
            return
        self._run_at_top(word, cursor)

    def _run_at_top(self, word: Word, cursor: LineCursor) -> None:
        signature = word.signature
        if word.prim and word.prim in FOLDS:
            FOLDS[word.prim](self)
            return
        if signature is None or len(signature.alts) != 1:
            self.top.clear()
        else:
            args = [self._pop_top() for _ in signature.inputs]
            for slot in signature.alts[0]:
                if slot.passthrough is not None and slot.passthrough <= len(args):
                    self.top.append(args[slot.passthrough - 1])
                else:
                    self.top.append(Value(slot.kind, const=slot.const, xt=slot.xt,
                                          origin=f"{word.name} output"))
        parses = word.parses
        if word.child is not None and parses == 0:
            parses = 1
        names = [cursor.token() for _ in range(parses)]
        if word.child is not None and names and names[0]:
            child = Word(names[0], self.module, self.line, self._origin(), kind="child")
            child.signature = word.child
            child.signature_source = "child"
            child.declared = word.child
            self.define(child)
            # A field such as CMP-CELL: _X-HOOK ( holds: xt( -- ) ) declares
            # what the cell its child word pushes holds.
            held = self.read_holds(cursor, child)
            if held is not None:
                child.holds = held
                outs = word.child.alts
                if len(outs) == 1 and len(outs[0]) == 1:
                    slot = outs[0][0]
                    typed = Slot(slot.name, E.ADDR, holds=held)
                    child.signature = Effect(word.child.inputs, ((typed,),), word.child.parses,
                                             False, word.child.text)
                else:
                    self.declaration_problem(
                        f"holds: {child.name} pushes {word.child.shape()} cells, not one address",
                        child.name)

    def read_holds(self, cursor: LineCursor, word: Word) -> Slot | None:
        """A ``( holds: KIND )`` comment right after a data word's name.

        Any other comment is left for the interpreter, which skips it.
        """
        saved = cursor.pos
        if cursor.token() != "(":
            cursor.pos = saved
            return None
        text, closed = cursor.paren_closed()
        held, problems, declaration = parse_holds(text, self.resolve_kind)
        if not declaration:
            cursor.pos = saved
            return None
        if not closed:
            problems = problems + ["the declaration's ( has no ) on its line"]
        for problem in problems:
            self.declaration_problem(problem, word.name)
        if held is not None:
            self.typed_slots.append((self.group, word))
        return held

    def _origin(self) -> str:
        return "base" if self.group == "base" else "source"

    # ------------------------------------------------------------------
    # The compiler

    def _begin_colon(self, name: str | None, quotation: bool = False) -> None:
        word = Word(name or "(quotation)", self.module, self.line, self._origin())
        word.compiling = True
        if name:
            self.define(word)
        self.pending = Pending(word, outer=self.pending if quotation else None,
                               quotation=quotation)

    def _compile(self, token: str, cursor: LineCursor) -> None:
        pending = self.pending
        assert pending is not None
        line = self.line
        if token == "(":
            text = cursor.paren()
            if pending.header_open and not pending.header_done:
                # A long effect may run over several paren groups:
                # "( verb-a verb-u )" then "( xt router -- status )".
                pending.header_parens.append(text)
                joined = " ".join(pending.header_parens)
                self._set_declared(pending.word, joined)
                if "--" in joined.split():
                    pending.header_done = True
            elif pending.after_does and pending.does_comment is None:
                pending.does_comment = text
            return
        pending.header_open = False
        upper = token.upper()
        pending.after_does = False
        word = self.words.get(upper)
        if word is None:
            number = parse_number(token, self.base)
            if number is not None:
                pending.items.append(("lit", number, line))
            else:
                pending.items.append(("undefined", token, line))
            return
        if word.immediate:
            if word.origin == "bios" or (word.origin == "base" and upper in COMPILE_HANDLERS):
                handler = COMPILE_HANDLERS.get(upper)
                if handler is not None:
                    handler(self, cursor, pending, line)
                    if upper == "DOES>":
                        pending.after_does = True
                    return
                if upper in CONTROL:
                    pending.items.append(("ctl", upper, line))
                    return
                if word.prim:
                    pending.items.append(("call", word, line))
                    return
            pending.items.append(("immediate", word, line))
            return
        pending.items.append(("call", word, line))

    def _set_declared(self, word: Word, text: str) -> None:
        parsed = parse_effect(text, self.resolve_kind)
        word.declared_text = text.strip()
        word.declared = parsed.effect
        word.declared_reason = parsed.reason
        word.problems = list(parsed.problems)
        word.declared_count = parsed.declared
        if parsed.effect is None:
            word.declared_text = None if parsed.reason == "no --" else word.declared_text
            if parsed.reason == "no --":
                word.declared_reason = "comment without --"

    def _finish_colon(self) -> Word:
        pending = self.pending
        assert pending is not None
        word = pending.word
        word.items = pending.items
        word.end_line = self.line
        self.pending = pending.outer
        if word.declared_text is None and word.declared_reason is None:
            preceding = self.preceding.get(word.name.upper())
            if preceding is not None:
                self._set_declared(word, preceding)
                word.declared_reason = "comment on a preceding line"
        if self.group == "base" and word.name.upper() in PRIMS:
            word.prim = word.name.upper()  # KDOS defines CATCH and THROW
        record = Record(word, self.group)
        word.record = record
        for problem in word.problems:
            self.declaration_problem(problem, word.name, record, word.line)
        record.declared_items = word.declared_count
        record.self_named = any(
            op == "call" and arg is word for op, arg, _ in pending.items
        )
        record.hides_older = word.hides is not None and record.self_named
        self.records.append(record)
        # The word stays "compiling" while it is analyzed, so a call to its
        # own name, or RECURSE, takes the effect its comment declares.
        self._analyze_definition(word, pending, record)
        word.compiling = False
        return word

    # ------------------------------------------------------------------
    # Analysis of a colon definition

    def _analyze_definition(self, word: Word, pending: Pending, record: Record) -> None:
        items = pending.items
        does_at = next((i for i, item in enumerate(items) if item[0] == "does"), None)
        main = items if does_at is None else items[:does_at]
        does = None if does_at is None else items[does_at + 1 :]
        declared = word.declared if word.declared and not word.declared.variable else None
        analysis = Analysis(self, word, record, declared)
        try:
            try:
                inferred = analysis.infer(main)
            except RecursionError:
                # Tokens that lead back to one another would inline forever;
                # the host's own stack ends the expansion.
                raise Fail("inlining does not end", word.name, word.line)
            word.inferred = inferred
            record.status = "inferred"
        except Fail as failure:
            inferred = None
            word.failure = failure
            record.status = "failed"
            record.failure = failure
            if failure.category in ("EXECUTE of an input xt", "CATCH of an input xt"):
                word.higher_order = True
        record.relies_on_declared = analysis.relies_on_declared
        record.comparison = compare(inferred, word.declared, word.declared_reason,
                                    word.declared_text)
        if (inferred is not None and record.recursion_assumed and self.strict
                and record.comparison not in ("match", "match with pass-through")):
            # Recursion ran on the comment's effect; only an inferred effect
            # that agrees with it confirms the assumption.
            failure = Fail("recursion the body does not confirm",
                           f"{word.name} infers {inferred.shape()}", word.line)
            inferred = None
            word.inferred = None
            word.failure = failure
            record.status = "failed"
            record.failure = failure
        if inferred is not None:
            word.signature = merge_declared(inferred, word.declared, self, facts=not self.strict)
            word.signature_source = "inferred"
            if record.comparison in ("match", "match with pass-through") and word.declared:
                analysis.check_output_kinds(inferred, word.declared)
        elif (word.declared is not None and not word.declared.variable and not word.higher_order
              and not _runs_what_it_is_given(word) and not self.strict):
            word.signature = word.declared
            word.signature_source = "declared"
        # Defining words: what the words they make do when run.
        child = self._child_effect(main, does, word, record, pending.does_comment)
        if child is not None:
            word.child = child
        parses = sum(getattr(arg, "parses", 0) for op, arg, _ in main if op == "call")
        if word.declared is not None and word.declared.parses:
            parses = word.declared.parses
        word.parses = parses
        if self.group == "base" and word.declared is not None and not word.declared.variable:
            # Base vocabulary words take the effect their comment declares.
            word.signature = merge_declared(inferred, word.declared) if (
                inferred is not None and record.comparison == "match") else word.declared
            word.signature_source = "given"

    def _child_effect(self, main, does, word: Word, record: Record,
                      does_comment: str | None) -> Effect | None:
        creating = None
        for op, arg, _ in main:
            if op == "call" and (arg.name.upper() in CREATING and arg.origin in ("bios", "base")
                                 or arg.child is not None):
                creating = arg
        if creating is None:
            return None
        if does is not None:
            # "DOES> ( body -- x )" declares the child's effect with the body
            # address it receives on top.
            declared = None
            if does_comment is not None:
                parsed = parse_effect(does_comment, self.resolve_kind).effect
                if parsed is not None and not parsed.variable and parsed.inputs:
                    declared = Effect(parsed.inputs[:-1], parsed.alts, parsed.parses,
                                      False, parsed.text)
            child_word = Word(f"{word.name} (DOES>)", word.module, word.line, word.origin)
            analysis = Analysis(self, child_word, record, declared)
            try:
                return merge_declared(analysis.infer(does, body=True), declared, self,
                                      facts=not self.strict)
            except Fail as failure:
                record.findings.append(Finding("DOES> part", failure.category, word.module,
                                               failure.line or word.line, word.name,
                                               record.group))
                return None if self.strict else declared
        if creating.child is not None:
            return creating.child
        name = creating.name.upper()
        if name in ("CONSTANT", "VALUE", "2CONSTANT"):
            return Effect((), ((Slot("x"),),))
        if name in ("CREATE", "VARIABLE", "2VARIABLE"):
            return Effect((), ((Slot("addr", E.ADDR),),))
        return None

    def finding(self, record: Record | None, category: str, detail: str, line: int,
                word: Word) -> None:
        item = Finding(category, detail, word.module, line, word.name,
                       record.group if record is not None else self.group)
        if record is not None:
            record.findings.append(item)
        self.findings.append(item)


def _reaches_itself(word: Word) -> bool:
    """Whether a word's body calls it again through the words it calls.

    A word that runs a token it is given may be inlined again inside its
    own inlining, as WITH-GUARD is when the token it runs uses WITH-GUARD
    too; that is nesting, and only a call cycle in the source is recursion.
    """
    seen: set[int] = set()
    stack = [arg for op, arg, _ in (word.items or []) if op == "call"]
    while stack:
        callee = stack.pop()
        if callee is word:
            return True
        if id(callee) in seen or callee.origin != "source":
            continue
        seen.add(id(callee))
        stack.extend(arg for op, arg, _ in (callee.items or []) if op == "call")
    return False


def _learn_bounds(state: State, relations: frozenset) -> None:
    """After a branch, a length compared with a span's length bounds it.

    Each pair names a value, by identity, and a span the branch shows it to
    be no longer than; every copy of that value on either stack learns it.
    """
    for ident, span in relations:
        for stack in (state.items, state.r):
            for index, value in enumerate(stack):
                if isinstance(value, Value) and value.ident == ident and span not in value.bounds:
                    stack[index] = value.copy_with(bounds=value.bounds | {span})


def _runs_what_it_is_given(word: Word) -> bool:
    """A word that takes an xt and runs one the checker cannot follow.

    Its comment, such as ``( xt -- )``, says nothing of what that xt takes
    and leaves, so callers cannot rely on it.
    """
    failure = word.failure
    if failure is None or failure.category not in ("EXECUTE of an unknown xt",
                                                   "CATCH of an unknown xt"):
        return False
    return any(slot.kind == E.XT for slot in word.declared.inputs)


# ----------------------------------------------------------------------
# Comparing an inferred effect with a comment


def compare(inferred: Effect | None, declared: Effect | None, reason: str | None,
            text: str | None) -> str:
    if declared is None:
        if reason == "comment without --":
            return "comment is not an effect"
        return "no comment"
    if declared.variable:
        return "comment declares a variable effect"
    if inferred is None:
        return "not inferred"
    if not inferred.alts:
        return "never returns"
    inferred_in = len(inferred.inputs)
    declared_in = len(declared.inputs)
    inferred_net = sorted({len(alt) - inferred_in for alt in inferred.alts})
    declared_net = sorted({len(alt) - declared_in for alt in declared.alts})
    if inferred_in == declared_in and inferred_net == declared_net:
        return "match"
    if declared_in > inferred_in and inferred_net == declared_net:
        return "match with pass-through"
    return "mismatch"


def merge_declared(inferred: Effect, declared: Effect | None, checker: "Checker | None" = None,
                   facts: bool = True) -> Effect:
    """The inferred effect, with the comment's names and kinds where they line up.

    A declared kind replaces an inferred one that it refines, as a record
    kind refines the address a field accessor computes; an inferred kind
    that the declaration contradicts stays, and ``check_output_kinds``
    reports it.  The comment lends zero and nonzero facts only outside
    strict mode, where nothing a comment says may change what code infers.
    """
    if declared is None or declared.variable:
        return inferred
    if len(declared.inputs) != len(inferred.inputs) or declared.depths != inferred.depths:
        return inferred

    def pick(found: Slot, said: Slot) -> str:
        if said.kind == E.LIT or said.kind == E.X:
            return found.kind
        if found.kind in (E.X, E.LIT):
            return said.kind
        if checker is not None and checker.refines(said.kind, found.kind):
            return said.kind
        return found.kind

    inputs = tuple(
        Slot(d.name, pick(i, d), None, None, d.span, d.role, effect=d.effect or i.effect,
             holds=d.holds or i.holds, array=d.array or i.array)
        for i, d in zip(inferred.inputs, declared.inputs)
    )
    by_depth: dict[int, list] = {}
    for alt in declared.alts:
        by_depth.setdefault(len(alt), []).append(alt)
    alts = []
    for alt in inferred.alts:
        candidates = by_depth.get(len(alt))
        if not candidates:
            alts.append(alt)
            continue
        dalt = candidates[0]
        # Alternatives of one depth, such as "fdesc | 0", say nothing certain
        # about any one cell; only a lone alternative lends its facts.
        lone = len(candidates) == 1
        merged = []
        for index, (i, d) in enumerate(zip(alt, dalt)):
            kinds = {c[index].kind for c in candidates}
            kind = pick(i, d) if len(kinds) == 1 else i.kind
            fact = i.fact if (i.fact is not None or not lone or not facts) else d.fact
            merged.append(Slot(d.name, kind, fact, i.const, d.span if lone else None,
                               d.role if lone else None, i.passthrough, i.xt,
                               effect=i.effect or (d.effect if lone else None),
                               holds=i.holds or (d.holds if lone else None),
                               part_of=d.part_of if lone else None,
                               array=i.array or (d.array if lone else False)))
        alts.append(tuple(merged))
    return Effect(inputs, tuple(alts), inferred.parses, False, declared.text)


# ----------------------------------------------------------------------
# Abstract interpretation of one body


class Analysis:
    """Runs a body on abstract stacks and summarizes what it does."""

    def __init__(self, checker: Checker, word: Word, record: Record | None,
                 declared: Effect | None, parent: "Analysis | None" = None) -> None:
        self.checker = checker
        self.word = word
        self.record = record
        self.declared = declared
        self.parent = parent
        self.inputs: dict[int, Value] = {} if parent is None else parent.inputs
        self.max_floor = 0
        self.relies_on_declared: set = set() if parent is None else parent.relies_on_declared
        self.spans: dict[int, int] = {}
        self.line = word.line
        self.input_offset = 0

    # Inputs and stack access

    def input(self, number: int) -> Value:
        if self.parent is not None:
            return self.parent.input(number)
        value = self.inputs.get(number)
        if value is None:
            kind = E.X
            span = role = None
            name = f"input {number}"
            declared = self.declared
            slot = None
            declared_slot = declared is not None and number <= len(declared.inputs)
            if declared_slot:
                slot = declared.inputs[-number]
                kind = slot.kind if slot.kind != E.LIT else E.X
                name = slot.name
                if slot.span is not None:
                    span = self.spans.setdefault(slot.span, next(_span_counter))
                    role = slot.role
            value = Value(kind, origin=name, ident=("in", id(self), number), span=span,
                          role=role, source="input",
                          effect=slot.effect if declared_slot else None,
                          holds=slot.holds if declared_slot else None,
                          array=slot.array if declared_slot else False)
            self.inputs[number] = value
        return value

    def _note_floor(self, state: State) -> None:
        root = self
        while root.parent is not None:
            root = root.parent
        if state.floor > root.max_floor:
            root.max_floor = state.floor

    def pop(self, state: State) -> Value:
        if state.items:
            return state.items.pop()
        state.floor += 1
        self._note_floor(state)
        return self.input(state.floor)

    def need(self, state: State, count: int) -> None:
        while len(state.items) < count:
            state.floor += 1
            state.items.insert(0, self.input(state.floor))
        self._note_floor(state)

    def is_input(self, value: Value) -> bool:
        return isinstance(value.ident, tuple) and value.ident[0] == "in"

    def fail(self, category: str, detail: str = "", root=None) -> Fail:
        return Fail(category, detail, self.line, root)

    # Running

    def infer(self, items: list, body: bool = False) -> Effect:
        entry = State()
        if body:
            entry.items.append(Value(E.ADDR, origin="DOES> body", source="computed"))
        exits = self.run(items, [entry])
        return self.summarize(exits)

    def run(self, items: list, entry: list[State], segment: bool = False) -> list[State]:
        """Run ``items`` from ``entry`` and return the states that leave them.

        A segment is a loop body run again for a counted loop; it ends with
        its loop frame still parked, so the end-of-definition checks skip it.
        """
        current = entry
        control: list = []
        exits: list[State] = []
        trace = self.checker.trace if self.parent is None else None
        for index, (op, arg, line) in enumerate(items):
            self.line = line
            if trace is not None:
                trace.append((line, op, getattr(arg, "name", arg),
                              sorted((s.depth, len(s.r)) for s in current)))
            if op == "call":
                current = self.call_all(current, arg)
            elif op == "lit":
                for state in current:
                    state.items.append(literal(arg))
            elif op == "ctl":
                current = self.control(arg, current, control, exits, items, index)
            elif op == "xt":
                for state in current:
                    state.items.append(Value(E.XT, xt=arg, origin=f"['] {arg.name}",
                                             source="literal"))
            elif op == "str":
                for state in current:
                    span = next(_span_counter)
                    state.items.append(Value(E.ADDR, span=span, role="a", origin='S"',
                                             source="literal"))
                    state.items.append(Value(E.COUNT, const=arg, span=span, role="u",
                                             origin='S" length', source="literal"))
            elif op == "litval":
                for state in current:
                    state.items.append(Value(arg.kind, const=arg.const, xt=arg.xt,
                                             origin=arg.origin, source="literal"))
            elif op == "abortq":
                current = [s for s in current if self.pop(s).fact != E.NONZERO]
            elif op == "to":
                for state in current:
                    value = self.pop(state)
                    if value.kind == E.REF:
                        self.note("managed rule", "ref kept in a VALUE by TO")
                    if arg is not None and arg.holds is not None:
                        self.check_held(value, arg.holds, f"TO {arg.name}")
            elif op == "undefined":
                raise self.fail("undefined word", arg)
            elif op == "immediate":
                raise self.fail("immediate word of its own", arg.name)
            elif op == "postpone":
                raise self.fail("POSTPONE", arg)
            elif op == "does":
                break
        if control:
            raise self.fail("unbalanced control structure", str(control[-1][0]))
        if segment:
            if exits:
                raise self.fail("loop changes the stack depth", "EXIT inside a counted loop")
            return current
        for state in current:
            self.check_return_stack(state, "the end of the definition")
        exits.extend(current)
        return exits

    def note(self, category: str, detail: str) -> None:
        self.checker.finding(self.record, category, detail, self.line, self.root_word())

    def root_word(self) -> Word:
        analysis = self
        while analysis.parent is not None:
            analysis = analysis.parent
        return analysis.word

    def declared_token(self, source: str) -> None:
        """Note a call whose effect came from a declaration, not from code."""
        if self.record is not None:
            self.record.declared_tokens += 1
            sources = self.record.declared_token_sources
            sources[source] = sources.get(source, 0) + 1

    def check_return_stack(self, state: State, where: str) -> None:
        if not state.r:
            return
        if any(isinstance(item, LoopFrame) for item in state.r):
            self.note("return stack", f"{where} inside a DO loop without UNLOOP")
            raise self.fail("return stack misuse", f"{where} inside a DO loop without UNLOOP")
        self.note("return stack", f"{where} with {len(state.r)} cell(s) parked by >R")
        raise self.fail("return stack misuse", f"{where} with cells parked by >R")

    # Control flow

    def branch(self, states: list[State]) -> tuple[list[State], list[State]]:
        true_states, false_states = [], []
        for state in states:
            flag = self.pop(state)
            if flag.fact == E.ZERO:
                false_states.append(state)
            elif flag.fact == E.NONZERO:
                true_states.append(state)
            else:
                other = state.copy()
                _learn_bounds(state, flag.rel_true)
                _learn_bounds(other, flag.rel_false)
                true_states.append(state)
                false_states.append(other)
        return true_states, false_states

    def back_edge(self, states: list[State], head: list[State], what: str) -> None:
        """Each pass through a loop must leave the depths it started with."""
        shapes = {(s.depth, len(s.r)) for s in head}
        depths = {depth for depth, _ in shapes}
        for state in states:
            if (state.depth, len(state.r)) in shapes:
                continue
            if state.depth in depths:
                raise self.fail("loop changes the return stack depth", what)
            raise self.fail("loop changes the stack depth", what)

    def control(self, word: str, current: list[State], control: list, exits: list[State],
                items: list | None = None, index: int = 0):
        if word == "IF":
            true_states, false_states = self.branch(current)
            control.append(("orig", false_states))
            return true_states
        if word == "ELSE":
            kind, states = self._pop_control(control, "orig", word)
            control.append(("orig", current))
            return states
        if word == "THEN":
            kind, states = self._pop_control(control, "orig", word)
            return self.merge(current + states)
        if word == "BEGIN":
            control.append(("dest", [s.copy() for s in current]))
            return current
        if word == "UNTIL":
            true_states, false_states = self.branch(current)
            kind, head = self._pop_control(control, "dest", word)
            self.back_edge(false_states, head, "BEGIN ... UNTIL")
            return true_states
        if word == "AGAIN":
            kind, head = self._pop_control(control, "dest", word)
            self.back_edge(current, head, "BEGIN ... AGAIN")
            return []
        if word == "WHILE":
            true_states, false_states = self.branch(current)
            dest = self._pop_control(control, "dest", word)
            control.append(("orig", false_states))
            control.append(dest)
            return true_states
        if word == "REPEAT":
            kind, head = self._pop_control(control, "dest", word)
            self.back_edge(current, head, "BEGIN ... WHILE ... REPEAT")
            kind, states = self._pop_control(control, "orig", word)
            return states
        if word in ("DO", "?DO"):
            entered, skipped = [], []
            trips = set()
            for state in current:
                start = self.pop(state)
                limit = self.pop(state)
                if start.const is not None and limit.const is not None:
                    trips.add(limit.const - start.const)
                else:
                    trips.add(None)
                if word == "?DO":
                    skipped.append(state.copy())
                state.r.append(LoopFrame(start))
                entered.append(state)
            # A constant count, as in "26 0 DO DROP LOOP", fixes the effect
            # of a body that changes the depth on each pass.
            trip = trips.pop() if len(trips) == 1 else None
            control.append(("do", [s.copy() for s in entered], [], skipped, trip, index + 1))
            return entered
        if word in ("LOOP", "+LOOP"):
            if word == "+LOOP":
                for state in current:
                    self.pop(state)
            frame = self._pop_control(control, "do", word)
            _, head, leaves, skipped, trip, body_start = frame
            try:
                self.back_edge(current, head, "DO ... LOOP")
            except Fail:
                if (word != "LOOP" or trip is None or trip < 1 or leaves or skipped
                        or items is None):
                    raise
                body = items[body_start:index]
                for _ in range(trip - 1):
                    current = self.merge(self.run(body, current, segment=True))
            for state in current:
                self._unloop(state, word)
            return self.merge(current + leaves + skipped)
        if word == "LEAVE":
            frame = next((c for c in reversed(control) if c[0] == "do"), None)
            if frame is None:
                raise self.fail("LEAVE outside a DO loop")
            for state in current:
                self._unloop(state, "LEAVE")
            frame[2].extend(current)
            return []
        if word == "UNLOOP":
            for state in current:
                self._unloop(state, "UNLOOP")
            return current
        if word == "EXIT":
            for state in current:
                self.check_return_stack(state, "EXIT")
            exits.extend(current)
            return []
        if word == "RECURSE":
            return self.call_all(current, self.word)
        if word == "CASE":
            control.append(("case", []))
            return current
        if word == "OF":
            matched, unmatched = [], []
            for state in current:
                self.pop(state)
                selector = self.pop(state)
                other = state.copy()
                other.items.append(selector)
                matched.append(state)
                unmatched.append(other)
            control.append(("of", unmatched))
            return matched
        if word == "ENDOF":
            kind, unmatched = self._pop_control(control, "of", word)
            case = control[-1] if control and control[-1][0] == "case" else None
            if case is None:
                raise self.fail("unbalanced control structure", "ENDOF")
            case[1].extend(current)
            return unmatched
        if word == "ENDCASE":
            kind, ends = self._pop_control(control, "case", word)
            for state in current:
                self.pop(state)
            return self.merge(current + ends)
        raise self.fail("unknown control word", word)

    def _pop_control(self, control: list, kind: str, word: str):
        if not control or control[-1][0] != kind:
            raise self.fail("unbalanced control structure", word)
        return control.pop()

    def _unloop(self, state: State, word: str) -> None:
        if state.r and isinstance(state.r[-1], LoopFrame):
            state.r.pop()
            return
        if state.r:
            self.note("return stack", f"{word} with cells parked by >R above the loop frame")
            raise self.fail("return stack misuse", f"{word} with cells parked above the loop")
        raise self.fail("return stack misuse", f"{word} outside a DO loop")

    # Joining states

    def merge(self, states: list[State], by_fact: bool = True) -> list[State]:
        """Join states of one depth unless a cell that tells them apart differs.

        CATCH's success and its exception can leave the same depth, and code
        may move other cells before an IF reads the code; keeping the states
        apart until then lets that IF route each one.
        """
        if len(states) <= 1:
            return states
        groups: dict[tuple, list[State]] = {}
        for state in states:
            key: tuple = (state.depth,)
            if by_fact:
                key += tuple((index, value.fact) for index, value in enumerate(state.items)
                             if value.disc and value.fact is not None)
            groups.setdefault(key, []).append(state)
        merged = []
        for group in groups.values():
            merged.append(self._join(group))
        return merged

    def _join(self, group: list[State]) -> State:
        if len(group) == 1:
            return group[0]
        floor = max(s.floor for s in group)
        for state in group:
            self._lower(state, floor)
        rdepth = {len(s.r) for s in group}
        if len(rdepth) != 1:
            raise self.fail("branches leave the return stack at different depths")
        result = group[0]
        for other in group[1:]:
            result = State([self._join_values(a, b) for a, b in zip(result.items, other.items)],
                           floor, [self._join_r(a, b) for a, b in zip(result.r, other.r)])
        return result

    def _lower(self, state: State, floor: int) -> None:
        if state.floor < floor:
            missing = [self.input(k) for k in range(floor, state.floor, -1)]
            state.items[0:0] = missing
            state.floor = floor

    def _join_values(self, one: Value, two: Value) -> Value:
        if one is two:
            return one
        if one.ident == two.ident:
            fact = one.fact if one.fact == two.fact else None
            disc = one.disc and two.disc
            bounds = one.bounds & two.bounds
            if one.fact == fact and one.disc == disc and one.bounds == bounds:
                return one
            return one.copy_with(fact=fact, disc=disc, bounds=bounds)
        kind = E.join_kinds(one.kind, two.kind)
        xt = one.xt if one.xt is two.xt else None
        span = one.span if one.span == two.span and one.role == two.role else None
        const = one.const if one.const == two.const else None
        fact = one.fact if one.fact == two.fact else None
        if kind == E.LIT and const is None:
            kind = E.NUMBER
        effect = one.effect if one.effect == two.effect else None
        if effect is None and xt is None:
            # A known token joined with one read from a typed slot keeps the
            # slot's effect when the token's own effect agrees with it.
            for token, typed in ((one, two), (two, one)):
                if (token.xt is not None and typed.effect is not None
                        and token.xt.signature is not None
                        and effect_shape(token.xt.signature) == effect_shape(typed.effect)):
                    effect = typed.effect
            for typed, absent in ((one, two), (two, one)):
                if typed.effect is not None and absent.const == 0:
                    effect = typed.effect  # 0 is the absent token
        holds = one.holds if one.holds == two.holds else None
        if effect is not None or (xt is None and one.kind == two.kind == E.XT):
            kind = E.XT
        return Value(kind, const=const, xt=xt, fact=fact, span=span,
                     role=one.role if span else None, origin=f"{one.origin} or {two.origin}",
                     source=one.source if one.source == two.source else "computed",
                     effect=effect, holds=holds, array=one.array and two.array and bool(holds),
                     bounds=one.bounds & two.bounds)

    def _join_r(self, one, two):
        if one is two:
            return one
        if isinstance(one, LoopFrame) or isinstance(two, LoopFrame):
            if isinstance(one, LoopFrame) and isinstance(two, LoopFrame):
                return one
            raise self.fail("branches leave the return stack in different shapes")
        return self._join_values(one, two)

    # Calls

    def call_all(self, states: list[State], word: Word) -> list[State]:
        result: list[State] = []
        for state in states:
            result.extend(self.call(state, word))
        return self.merge(result)

    def call(self, state: State, word: Word) -> list[State]:
        if word.prim is not None:
            handler = PRIM_HANDLERS.get(word.prim)
            if handler is not None:
                return handler(self, state, word)
        recursive = word.compiling or (word in self.checker.inlining
                                       and _reaches_itself(word))
        if recursive:
            # The definition names itself: recursion uses its comment's
            # effect, which strict mode accepts only when the inferred effect
            # of the definition being analyzed confirms it.
            if word.declared is None or word.declared.variable:
                raise self.fail("recursion without a declared effect", word.name)
            if word is self.root_word():
                if self.record is not None:
                    self.record.recursion_assumed = True
            elif self.checker.strict:
                raise self.fail("recursion through a word still being analyzed", word.name)
            return self.apply(state, word.declared, word)
        if word.kind == "defer" and word.signature is not None:
            # A deferred word runs whatever token IS last stored in it.
            self.declared_token("deferred word")
            return self.apply(state, word.signature, word)
        if word.signature is not None:
            if word.signature_source == "declared" and word.origin == "source":
                self.relies_on_declared.add(word.name)
            return self.apply(state, word.signature, word)
        if word.higher_order:
            return self.inline(state, word)
        if word.kind == "defer":
            raise self.fail("deferred word without a declared effect", word.name)
        if word.failure is not None:
            raise self.fail("calls a word whose effect is unknown", word.name,
                            root=word.failure.root)
        if word.origin == "bios":
            raise self.fail("BIOS word without a documented effect", word.name)
        raise self.fail("calls a word whose effect is unknown", word.name)

    def inline(self, state: State, word: Word) -> list[State]:
        """Run a word that executes an xt it was given, with this caller's cells."""
        nested = Analysis(self.checker, word, self.record, None, parent=self)
        nested.line = self.line
        saved_r = state.r
        entry = State(state.items, state.floor, [])
        self.checker.inlining.append(word)
        try:
            exits = nested.run(word.items or [], [entry])
        except Fail as failure:
            raise Fail(failure.category, f"{failure.detail} (through {word.name})",
                       self.line, failure.root)
        finally:
            self.checker.inlining.pop()
        for exit_state in exits:
            exit_state.r = list(saved_r)
            self._note_floor(exit_state)
        return exits

    def apply(self, state: State, effect: Effect, word: Word) -> list[State]:
        if effect.variable:
            raise self.fail("calls a word with a variable effect", word.name)
        args = [self.pop(state) for _ in effect.inputs]
        args.reverse()
        for slot, value in zip(effect.inputs, args):
            self.check_kind(value, slot, word)
        self.check_spans(args, effect.inputs, word)
        if not effect.alts:
            return []
        results = []
        several = len(effect.alts) > 1
        for index, alt in enumerate(effect.alts):
            target = state if index == len(effect.alts) - 1 else state.copy()
            spans: dict[int, int] = {}
            # "( a u -- a u' )" keeps the address and shortens the length: the
            # new length belongs to the span the address came from.  An output
            # declared as part of an input span, as "s'" is of "s", belongs to
            # the span the caller passed.
            for slot in alt:
                if slot.span is not None and slot.passthrough is not None:
                    kept = args[-slot.passthrough]
                    if kept.span is not None:
                        spans.setdefault(slot.span, kept.span)
                if slot.span is not None and slot.part_of is not None:
                    source = args[slot.part_of] if slot.part_of < len(args) else None
                    if source is not None and source.span is not None:
                        spans.setdefault(slot.span, source.span)
            for position, slot in enumerate(alt):
                if slot.passthrough is not None:
                    target.items.append(args[-slot.passthrough])
                    continue
                span = None
                if slot.span is not None:
                    span = spans.setdefault(slot.span, next(_span_counter))
                disc = several and position == len(alt) - 1 and slot.fact is not None
                target.items.append(Value(slot.kind, const=slot.const, xt=slot.xt, fact=slot.fact,
                                          span=span, role=slot.role,
                                          origin=f"{word.name} output", source="computed",
                                          disc=disc, effect=slot.effect, holds=slot.holds,
                                          array=slot.array))
            results.append(target)
        return results

    def check_kind(self, value: Value, slot: Slot, word: Word) -> None:
        if value.kind == E.X and self.is_input(value) and slot.kind not in (E.X, E.LIT):
            value.kind = slot.kind  # the input is used as this kind
            return
        problem = self.checker.compatible(value.kind, slot.kind)
        if problem is not None:
            self.note("kind", f"{problem}: {value.kind} ({value.origin}) "
                              f"passed to {word.name} as {slot.name or slot.kind}")
            return
        if slot.kind == E.XT and slot.effect is not None:
            self.check_token(value, slot.effect, f"passed to {word.name} as {slot.name}")

    def check_token(self, value: Value, declared: Effect, where: str) -> bool | None:
        """Compare a token's effect with the one a slot or input declares.

        True when they agree, False when they differ (a finding), and None
        when the token is not known, as for a cell of unknown origin.
        """
        if value.xt is not None:
            actual = value.xt.signature
            name = value.xt.name
        elif value.effect is not None:
            actual = value.effect
            name = value.origin
        else:
            return None if value.const != 0 else True  # 0 is the absent token
        if actual is None or actual.variable or declared.variable:
            return None
        if effect_shape(actual) != effect_shape(declared):
            self.note("token effect", f"{name} ( {actual.shape()} ) {where}, "
                                      f"which declares ( {declared.shape()} )")
            return False
        for got, want in zip(actual.inputs, declared.inputs):
            problem = self.checker.compatible(want.kind, got.kind)
            if problem is not None:
                self.note("token effect", f"{name} takes {got.kind} where {where} "
                                          f"declares {want.kind}: {problem}")
                return False
        return True

    def check_held(self, value: Value, held: Slot, where: str) -> None:
        """A value stored where a declaration says what the cell holds."""
        if value.kind == E.X and self.is_input(value) and held.kind not in (E.X, E.LIT):
            value.kind = held.kind
            if held.effect is not None and value.effect is None:
                value.effect = held.effect
            return
        problem = self.checker.compatible(value.kind, held.kind)
        if problem is not None:
            self.note("kind", f"{problem}: {value.kind} ({value.origin}) stored by {where}, "
                              f"which holds {held.kind}")
            return
        if held.kind == E.XT and held.effect is not None:
            agreed = self.check_token(value, held.effect, f"stored by {where}")
            if self.record is not None:
                if agreed:
                    self.record.typed_stores_checked += 1
                elif agreed is None:
                    self.record.typed_stores_unchecked += 1

    def check_spans(self, args: list[Value], slots: tuple[Slot, ...], word: Word) -> None:
        """A declared span must receive an address and a length of one span.

        A length checked against a longer span's length, or the MIN of two
        lengths, is also a length of that span: it selects a part of it, as
        a prefix compared with another string's length does.
        """
        for index in range(len(slots) - 1):
            first, second = slots[index], slots[index + 1]
            if first.role != "a" or second.role != "u" or first.span != second.span:
                continue
            addr, length = args[index], args[index + 1]
            if addr.span is None or (length.span is None and not length.bounds):
                continue
            if addr.span == length.span:
                if addr.role == "u" and length.role == "a":
                    self.note("span", f"{word.name} takes a span with its cells swapped")
                continue
            if addr.span in length.bounds:
                continue
            self.note("span", f"{word.name} takes the address of one span "
                              f"({addr.origin}) with the length of another "
                              f"({length.origin})")

    def check_output_kinds(self, inferred: Effect, declared: Effect) -> None:
        by_depth = {len(alt): alt for alt in declared.alts}
        for alt in inferred.alts:
            dalt = by_depth.get(len(alt))
            if dalt is None:
                continue
            for got, want in zip(alt, dalt):
                if got.passthrough is not None:
                    got_kind = inferred.inputs[-got.passthrough].kind
                else:
                    got_kind = got.kind
                problem = self.checker.compatible(got_kind, want.kind)
                if problem is not None:
                    self.note("kind", f"{problem}: returns {got_kind} where the comment "
                                      f"says {want.name}: {want.kind}")
                    continue
                if want.kind == E.XT and want.effect is not None and got.xt is not None:
                    token = Value(E.XT, xt=got.xt, origin=got.name)
                    self.check_token(token, want.effect, f"returned as {want.name}")
                if want.holds is not None and got.holds is not None:
                    problem = self.checker.compatible(got.holds.kind, want.holds.kind)
                    if problem is not None:
                        self.note("kind", f"{problem}: returns the address of a cell holding "
                                          f"{got.holds.kind} where the comment says "
                                          f"{want.name}: {want.holds.kind}")

    # Summary

    def summarize(self, exits: list[State]) -> Effect:
        floor = self.max_floor
        for state in exits:
            self._lower(state, floor)
        exits = self.merge(exits, by_fact=False)
        inputs = tuple(
            Slot(self.input(k).origin, self.input(k).kind, effect=self.input(k).effect,
                 holds=self.input(k).holds, array=self.input(k).array)
            for k in range(floor, 0, -1)
        )
        if not exits:
            return Effect(inputs, ())
        if len(exits) > 1:
            facts = []
            for state in exits:
                top = state.items[-1] if state.items else None
                facts.append(None if top is None else top.fact)
            if len(exits) > 2 or None in facts or len(set(facts)) != len(facts):
                depths = sorted(s.depth for s in exits)
                raise self.fail("result depth varies",
                                "depths " + ", ".join(f"{d:+d}" for d in depths))
        alts = []
        for state in sorted(exits, key=lambda s: -s.depth):
            slots = []
            for value in state.items:
                passthrough = None
                if self.is_input(value) and value.ident[1] == id(self):
                    passthrough = value.ident[2]
                slots.append(Slot(value.origin, value.kind, value.fact, value.const,
                                  None, None, passthrough, value.xt, effect=value.effect,
                                  holds=value.holds, array=value.array))
            alts.append(tuple(slots))
        return Effect(inputs, tuple(alts))


# ----------------------------------------------------------------------
# Primitives with exact semantics


def _shuffle(pattern_in: int, order: tuple[int, ...]):
    """A stack shuffle: take ``pattern_in`` cells, push them in ``order``.

    Cells are numbered from 0 for the deepest taken.
    """

    def handler(analysis: Analysis, state: State, word: Word) -> list[State]:
        analysis.need(state, pattern_in)
        taken = state.items[len(state.items) - pattern_in :]
        del state.items[len(state.items) - pattern_in :]
        state.items.extend(taken[i] for i in order)
        return [state]

    return handler


def _qdup(analysis: Analysis, state: State, word: Word) -> list[State]:
    value = analysis.pop(state)
    if value.fact == E.ZERO:
        state.items.append(value)
        return [state]
    if value.fact == E.NONZERO:
        state.items.extend([value, value])
        return [state]
    zero = state.copy()
    zero.items.append(value.with_fact(E.ZERO, disc=True))
    nonzero = value.with_fact(E.NONZERO, disc=True)
    state.items.extend([nonzero, nonzero])
    return [state, zero]


def _pick(analysis: Analysis, state: State, word: Word) -> list[State]:
    depth = analysis.pop(state)
    if depth.const is None:
        raise analysis.fail("computed PICK or ROLL depth", "PICK")
    analysis.need(state, depth.const + 1)
    state.items.append(state.items[-1 - depth.const])
    return [state]


def _roll(analysis: Analysis, state: State, word: Word) -> list[State]:
    depth = analysis.pop(state)
    if depth.const is None:
        raise analysis.fail("computed PICK or ROLL depth", "ROLL")
    if depth.const > 0:
        analysis.need(state, depth.const + 1)
        value = state.items.pop(-1 - depth.const)
        state.items.append(value)
    return [state]


def _to_r(analysis: Analysis, state: State, word: Word) -> list[State]:
    value = analysis.pop(state)
    state.r.append(value)
    return [state]


def _r_from(analysis: Analysis, state: State, word: Word) -> list[State]:
    if not state.r:
        raise analysis.fail("return stack beyond the definition", "R> takes the caller's return address")
    value = state.r.pop()
    if isinstance(value, LoopFrame):
        analysis.note("return stack", "R> takes a DO loop's control cells")
        raise analysis.fail("return stack misuse", "R> inside a DO loop")
    state.items.append(value)
    return [state]


def _r_fetch(analysis: Analysis, state: State, word: Word) -> list[State]:
    if not state.r:
        raise analysis.fail("return stack beyond the definition", "R@ reads the caller's return address")
    value = state.r[-1]
    if isinstance(value, LoopFrame):
        state.items.append(value.index)  # inside DO, R is the loop counter
        return [state]
    state.items.append(value)
    return [state]


def _two_to_r(analysis: Analysis, state: State, word: Word) -> list[State]:
    second = analysis.pop(state)
    first = analysis.pop(state)
    state.r.extend([first, second])
    return [state]


def _two_r_from(analysis: Analysis, state: State, word: Word) -> list[State]:
    if len(state.r) < 2 or any(isinstance(v, LoopFrame) for v in state.r[-2:]):
        raise analysis.fail("return stack misuse", "2R> without two parked cells")
    second = state.r.pop()
    first = state.r.pop()
    state.items.extend([first, second])
    return [state]


def _two_r_fetch(analysis: Analysis, state: State, word: Word) -> list[State]:
    if len(state.r) < 2 or any(isinstance(v, LoopFrame) for v in state.r[-2:]):
        raise analysis.fail("return stack misuse", "2R@ without two parked cells")
    state.items.extend([state.r[-2], state.r[-1]])
    return [state]


def _loop_index(depth: int):
    """I and J read fixed return-stack offsets (BIOS w_i: RSP+16, w_j: RSP+32).

    I finds the innermost loop's index only when that loop's frame is on top
    of the return stack, and J the next loop's only when the two frames are
    adjacent; a cell parked by >R in between makes them read the wrong cell.
    """

    def handler(analysis: Analysis, state: State, word: Word) -> list[State]:
        frames = [item for item in state.r if isinstance(item, LoopFrame)]
        if len(frames) < depth:
            analysis.note("return stack", f"{word.name} outside the DO loops it reads")
            state.items.append(Value(E.NUMBER, origin=f"{word.name} outside a loop"))
            return [state]
        wanted = state.r[-depth:] if len(state.r) >= depth else []
        if not all(isinstance(item, LoopFrame) for item in wanted):
            analysis.note("return stack",
                          f"{word.name} reads a cell parked by >R, not a loop index")
            state.items.append(Value(E.X, origin=f"{word.name} misread"))
            return [state]
        state.items.append(state.r[-depth].index)
        return [state]

    return handler


def _execute(analysis: Analysis, state: State, word: Word) -> list[State]:
    xt = analysis.pop(state)
    if xt.xt is not None:
        return analysis.call(state, xt.xt)
    if xt.effect is not None and not xt.effect.variable:
        analysis.declared_token(_token_source(xt))
        return analysis.apply(state, xt.effect, _token_word(xt))
    if xt.source == "input":
        # A token the definition was given, run here or inside a word it
        # inlines: the definition runs what its callers pass.
        raise analysis.fail("EXECUTE of an input xt", xt.origin)
    raise analysis.fail("EXECUTE of an unknown xt", _xt_origin(xt))


def _token_source(value: Value) -> str:
    return "typed token input" if value.source == "input" else "typed slot"


def _token_word(value: Value) -> Word:
    """A stand-in dictionary entry for a token known only by its declared effect."""
    word = Word(f"token ({value.origin})", "", 0, "source")
    word.signature = value.effect
    return word


def _xt_origin(value: Value) -> str:
    if value.source == "input":
        return "an input"
    if value.origin.endswith("output") and value.origin.startswith("@"):
        return "a cell read from memory"
    return value.origin


def _catch(analysis: Analysis, state: State, word: Word) -> list[State]:
    xt = analysis.pop(state)
    if xt.xt is None and (xt.effect is None or xt.effect.variable):
        if xt.source == "input":
            raise analysis.fail("CATCH of an input xt", xt.origin)
        raise analysis.fail("CATCH of an unknown xt", _xt_origin(xt))
    thrown = state.copy()
    target = xt.xt if xt.xt is not None else _token_word(xt)
    consumed = len(target.signature.inputs) if target.signature is not None else 0
    analysis.need(thrown, consumed)
    for index in range(1, consumed + 1):
        thrown.items[-index] = Value(E.X, origin="cell restored by THROW")
    thrown.items.append(Value(E.NUMBER, fact=E.NONZERO, origin="CATCH exception", disc=True))
    if xt.xt is not None:
        normal = analysis.call(state, target)
    else:
        analysis.declared_token(_token_source(xt))
        normal = analysis.apply(state, xt.effect, target)
    for done in normal:
        done.items.append(Value(E.LIT, const=0, origin="CATCH success", source="literal",
                                disc=True))
    return normal + [thrown]


def _throw(analysis: Analysis, state: State, word: Word) -> list[State]:
    code = analysis.pop(state)
    if code.fact == E.NONZERO:
        return []
    return [state]


def _never(analysis: Analysis, state: State, word: Word) -> list[State]:
    return []


def _stack_pointer(analysis: Analysis, state: State, word: Word) -> list[State]:
    raise analysis.fail("direct stack-pointer access", word.name)


def _evaluate(analysis: Analysis, state: State, word: Word) -> list[State]:
    raise analysis.fail("EVALUATE of text", word.name)


def _depth(analysis: Analysis, state: State, word: Word) -> list[State]:
    state.items.append(Value(E.NUMBER, origin="DEPTH"))
    return [state]


def _constant(number: int):
    def handler(analysis: Analysis, state: State, word: Word) -> list[State]:
        state.items.append(literal(number, word.name))
        return [state]
    return handler


def _binary(result: Callable[[Value, Value], str], fold: Callable[[int, int], int] | None,
            want: tuple[str, str] = (E.X, E.X),
            post: Callable[[Value, Value, Value], Value] | None = None):
    def handler(analysis: Analysis, state: State, word: Word) -> list[State]:
        second = analysis.pop(state)
        first = analysis.pop(state)
        for value, kind in ((first, want[0]), (second, want[1])):
            analysis.check_kind(value, Slot(word.name, kind), word)
        const = None
        if fold is not None and first.const is not None and second.const is not None:
            try:
                const = wrap(fold(first.const, second.const))
            except ZeroDivisionError:
                const = None
        kind = result(first, second)
        if const is not None and kind in (E.NUMBER, E.COUNT):
            kind = E.LIT
        value = Value(kind, const=const, origin=f"{word.name} result")
        state.items.append(post(first, second, value) if post is not None else value)
        return [state]
    return handler


def _unary(result: Callable[[Value], str], fold: Callable[[int], int] | None,
           want: str = E.X, fact: Callable[[Value], int | None] | None = None,
           post: Callable[[Value, Value], Value] | None = None):
    def handler(analysis: Analysis, state: State, word: Word) -> list[State]:
        value = analysis.pop(state)
        analysis.check_kind(value, Slot(word.name, want), word)
        const = wrap(fold(value.const)) if fold is not None and value.const is not None else None
        kind = result(value)
        if const is not None and kind in (E.NUMBER, E.COUNT):
            kind = E.LIT
        known = fact(value) if fact is not None else None
        out = Value(kind, const=const, fact=known, origin=f"{word.name} result")
        state.items.append(post(value, out) if post is not None else out)
        return [state]
    return handler


_NUMERIC = E.PLAIN_NUMBERS | {E.LIT}


def _sum_kind(first: Value, second: Value) -> str:
    """Address plus offset is an address; a cell of unknown kind stays unknown.

    A number written in the source serves as any kind, an address among
    them, so a number plus such a constant has no kind.
    """
    kinds = (first.kind, second.kind)
    if kinds.count(E.ADDR) == 1:
        other = second.kind if first.kind == E.ADDR else first.kind
        return E.ADDR if other in _NUMERIC | {E.X} else E.X
    if kinds == (E.LIT, E.LIT):
        return E.LIT
    if E.LIT in kinds:
        return E.X
    if first.kind in _NUMERIC and second.kind in _NUMERIC:
        return E.NUMBER
    return E.X


def _difference_kind(first: Value, second: Value) -> str:
    if first.kind == E.ADDR and second.kind == E.ADDR:
        return E.NUMBER
    if first.kind == E.ADDR and second.kind in _NUMERIC:
        return E.ADDR
    if first.kind == E.LIT:
        # A constant may be an address, and an address less a number is one.
        return E.LIT if second.kind == E.LIT else E.X
    if first.kind in _NUMERIC and second.kind in _NUMERIC:
        return E.NUMBER
    return E.X


def _and_kind(first: Value, second: Value) -> str:
    if first.kind == E.ADDR and second.kind == E.LIT:
        return E.ADDR  # alignment, as in 7 + -8 AND
    if first.kind == E.LIT and second.kind == E.LIT:
        return E.LIT
    if first.kind == E.FLAG and second.kind == E.FLAG:
        return E.FLAG
    return _number(first, second)


def _bool(value: bool) -> int:
    return -1 if value else 0


def _number(first: Value, second: Value | None = None) -> str:
    values = (first,) if second is None else (first, second)
    return E.NUMBER if all(v.kind in _NUMERIC for v in values) else E.X


def _flag(_first: Value, _second: Value | None = None) -> str:
    return E.FLAG


def _same_or_number(value: Value) -> str:
    if value.kind in (E.ADDR, E.X):
        return value.kind
    return _number(value)


def _not_fact(value: Value) -> int | None:
    if value.fact == E.ZERO:
        return E.NONZERO
    if value.fact == E.NONZERO:
        return E.ZERO
    return None


def _u(x: int) -> int:
    return x & ((1 << 64) - 1)


def _fetch(kind: str, cell: bool = False):
    """A read; ``@`` of a typed slot gives what the slot's declaration holds."""
    def handler(analysis: Analysis, state: State, word: Word) -> list[State]:
        address = analysis.pop(state)
        if address.kind == E.HANDLE:
            analysis.note("managed rule", f"{word.name} reads through a handle")
        else:
            analysis.check_kind(address, Slot("addr", E.ADDR), word)
        held = address.holds if cell else None
        if held is not None:
            state.items.append(Value(held.kind, origin=f"{address.origin} @", source="memory",
                                     effect=held.effect, holds=held.holds, array=held.array))
        else:
            state.items.append(Value(kind, origin=f"@ output", source="memory"))
        return [state]
    return handler


def _store(cells: int, cell: bool = False):
    """A write; ``!`` into a typed slot must store what it declares."""
    def handler(analysis: Analysis, state: State, word: Word) -> list[State]:
        address = analysis.pop(state)
        values = [analysis.pop(state) for _ in range(cells)]
        if address.kind == E.REF:
            analysis.note("managed rule", f"{word.name} writes a managed object directly")
        elif address.kind == E.HANDLE:
            analysis.note("managed rule", f"{word.name} writes through a handle")
        else:
            analysis.check_kind(address, Slot("addr", E.ADDR), word)
        for value in values:
            if value.kind == E.REF:
                analysis.note("managed rule", f"{word.name} keeps a ref in plain memory")
        if cell and address.holds is not None:
            analysis.check_held(values[0], address.holds, f"! into {address.origin}")
        return [state]
    return handler


def _plus(analysis: Analysis, state: State, word: Word) -> list[State]:
    """``+``: a field offset declared with holds, added to a record's address,
    gives the address of a cell that holds the field's kind; an offset into a
    table declared with holds stays in the table."""
    second = analysis.pop(state)
    first = analysis.pop(state)
    const = None
    if first.const is not None and second.const is not None:
        const = wrap(first.const + second.const)
    kind = _sum_kind(first, second)
    if const is not None and kind in (E.NUMBER, E.COUNT):
        kind = E.LIT
    holds = None
    array = False
    for base, offset in ((first, second), (second, first)):
        if offset.holds is not None and offset.kind in _NUMERIC and base.holds is None:
            holds, kind, const = offset.holds, E.ADDR, None
        elif base.holds is not None and base.array and offset.kind in _NUMERIC | {E.X}:
            holds, array, kind, const = base.holds, True, E.ADDR, None
    state.items.append(Value(kind, const=const, origin=f"{word.name} result", holds=holds,
                             array=array))
    return [state]


def _cell_plus(analysis: Analysis, state: State, word: Word) -> list[State]:
    value = analysis.pop(state)
    analysis.check_kind(value, Slot(word.name, E.X), word)
    const = wrap(value.const + 8) if value.const is not None else None
    kind = _same_or_number(value)
    if const is not None and kind in (E.NUMBER, E.COUNT):
        kind = E.LIT
    keep = value.holds is not None and value.array
    state.items.append(Value(kind, const=const, origin=f"{word.name} result",
                             holds=value.holds if keep else None, array=keep))
    return [state]


def _compare(fold: Callable[[int, int], int], smaller_when_true: int):
    """A comparison; between lengths it also tells which bounds which.

    ``smaller_when_true`` is 0 when a true result shows the first operand
    is no longer than the second (``<``, ``<=``), 1 when it shows the
    second is no longer than the first (``>``, ``>=``).
    """
    def post(first: Value, second: Value, flag: Value) -> Value:
        pair = (first, second)
        when_true = _bound_pair(pair[smaller_when_true], pair[1 - smaller_when_true])
        when_false = _bound_pair(pair[1 - smaller_when_true], pair[smaller_when_true])
        if when_true or when_false:
            return flag.copy_with(rel_true=when_true, rel_false=when_false)
        return flag

    return _binary(_flag, fold, post=post)


def _bound_pair(smaller: Value, larger: Value) -> frozenset:
    """When ``smaller`` is no longer than ``larger``, a length of a span."""
    if larger.role == "u" and larger.span is not None and smaller.const is None:
        return frozenset({(smaller.ident, larger.span)})
    return frozenset()


def _min_post(first: Value, second: Value, result: Value) -> Value:
    """MIN of two lengths is no longer than the spans either belongs to."""
    bounds = set(first.bounds | second.bounds)
    for value in (first, second):
        if value.role == "u" and value.span is not None:
            bounds.add(value.span)
    return result.copy_with(bounds=frozenset(bounds)) if bounds else result


def _logic(fold: Callable[[int, int], int], keeps: str):
    """AND keeps what a true result shows of both flags; OR, of a false one."""
    def post(first: Value, second: Value, result: Value) -> Value:
        if keeps == "true" and (first.rel_true or second.rel_true):
            return result.copy_with(rel_true=first.rel_true | second.rel_true)
        if keeps == "false" and (first.rel_false or second.rel_false):
            return result.copy_with(rel_false=first.rel_false | second.rel_false)
        return result

    kind = _and_kind if keeps == "true" else (
        lambda a, b: E.FLAG if a.kind == b.kind == E.FLAG else _number(a, b))
    return _binary(kind, fold, post=post)


def _swap_relations(value: Value, result: Value) -> Value:
    """``0=`` and INVERT of a flag swap what its true and false results show."""
    if value.rel_true or value.rel_false:
        return result.copy_with(rel_true=value.rel_false, rel_false=value.rel_true)
    return result


def _comma(analysis: Analysis, state: State, word: Word) -> list[State]:
    value = analysis.pop(state)
    if value.kind == E.REF:
        analysis.note("managed rule", f"{word.name} keeps a ref in the dictionary")
    return [state]


PRIM_HANDLERS: dict[str, Callable] = {
    "DUP": _shuffle(1, (0, 0)),
    "DROP": _shuffle(1, ()),
    "SWAP": _shuffle(2, (1, 0)),
    "OVER": _shuffle(2, (0, 1, 0)),
    "ROT": _shuffle(3, (1, 2, 0)),
    "-ROT": _shuffle(3, (2, 0, 1)),
    "NIP": _shuffle(2, (1,)),
    "TUCK": _shuffle(2, (1, 0, 1)),
    "2DUP": _shuffle(2, (0, 1, 0, 1)),
    "2DROP": _shuffle(2, ()),
    "2SWAP": _shuffle(4, (2, 3, 0, 1)),
    "2OVER": _shuffle(4, (0, 1, 2, 3, 0, 1)),
    "2ROT": _shuffle(6, (2, 3, 4, 5, 0, 1)),
    "?DUP": _qdup,
    "PICK": _pick,
    "ROLL": _roll,
    ">R": _to_r,
    "R>": _r_from,
    "R@": _r_fetch,
    "2>R": _two_to_r,
    "2R>": _two_r_from,
    "2R@": _two_r_fetch,
    "I": _loop_index(1),
    "J": _loop_index(2),
    "EXECUTE": _execute,
    "CATCH": _catch,
    "THROW": _throw,
    "ABORT": _never,
    "QUIT": _never,
    "BYE": _never,
    "SP@": _stack_pointer,
    "SP!": _stack_pointer,
    "RP@": _stack_pointer,
    "RP!": _stack_pointer,
    "EVALUATE": _evaluate,
    "DEPTH": _depth,
    "TRUE": _constant(-1),
    "FALSE": _constant(0),
    "BL": _constant(32),
    "+": _plus,
    "-": _binary(_difference_kind, lambda a, b: a - b),
    "*": _binary(_number, lambda a, b: a * b),
    "/": _binary(_number, lambda a, b: int(a / b)),
    "MOD": _binary(_number, lambda a, b: a - b * int(a / b)),
    "AND": _logic(lambda a, b: a & b, "true"),
    "OR": _logic(lambda a, b: a | b, "false"),
    "XOR": _binary(_number, lambda a, b: a ^ b),
    "LSHIFT": _binary(_number, lambda a, b: a << b if 0 <= b < 64 else 0),
    "RSHIFT": _binary(_number, lambda a, b: _u(a) >> b if 0 <= b < 64 else 0),
    "MIN": _binary(_number, min, post=_min_post),
    "MAX": _binary(_number, max),
    "=": _binary(_flag, lambda a, b: _bool(a == b)),
    "<>": _binary(_flag, lambda a, b: _bool(a != b)),
    "<": _compare(lambda a, b: _bool(a < b), 0),
    ">": _compare(lambda a, b: _bool(a > b), 1),
    "<=": _compare(lambda a, b: _bool(a <= b), 0),
    ">=": _compare(lambda a, b: _bool(a >= b), 1),
    "U<": _compare(lambda a, b: _bool(_u(a) < _u(b)), 0),
    "U>": _compare(lambda a, b: _bool(_u(a) > _u(b)), 1),
    "1+": _unary(_same_or_number, lambda a: a + 1),
    "1-": _unary(_same_or_number, lambda a: a - 1),
    "CELL+": _cell_plus,
    "CELLS": _unary(_number, lambda a: a * 8),
    "2*": _unary(_number, lambda a: a * 2),
    "2/": _unary(_number, lambda a: a >> 1),
    "NEGATE": _unary(_number, lambda a: -a),
    "ABS": _unary(_number, abs),
    "INVERT": _unary(lambda v: E.FLAG if v.kind == E.FLAG else _number(v), lambda a: ~a,
                     fact=lambda v: _not_fact(v) if v.kind == E.FLAG else None,
                     post=_swap_relations),
    "0=": _unary(_flag, lambda a: _bool(a == 0), fact=_not_fact, post=_swap_relations),
    "0<>": _unary(_flag, lambda a: _bool(a != 0), fact=lambda v: v.fact),
    "0<": _unary(_flag, lambda a: _bool(a < 0)),
    "0>": _unary(_flag, lambda a: _bool(a > 0)),
    "@": _fetch(E.X, cell=True),
    "C@": _fetch(E.CHAR),
    "W@": _fetch(E.COUNT),
    "L@": _fetch(E.COUNT),
    "!": _store(1, cell=True),
    "C!": _store(1),
    "W!": _store(1),
    "L!": _store(1),
    "+!": _store(1),
    "2!": _store(2),
    ",": _comma,
}

PRIMS = frozenset(PRIM_HANDLERS)


# ----------------------------------------------------------------------
# Top-level words


def _top_colon(checker: Checker, cursor: LineCursor, word: Word) -> None:
    name = cursor.token()
    if name is None:
        return
    checker._begin_colon(name)


def _top_noname(checker: Checker, cursor: LineCursor, word: Word) -> None:
    checker._begin_colon(None)


def _top_create(kind: str, takes_value: bool):
    def handler(checker: Checker, cursor: LineCursor, word: Word) -> None:
        value = checker._pop_top() if takes_value else None
        name = cursor.token()
        if name is None:
            return
        new = Word(name, checker.module, checker.line, checker._origin(), kind=kind)
        held = None
        if kind in ("variable", "create", "constant", "value"):
            held = checker.read_holds(cursor, new)
            new.holds = held
        if kind in ("variable", "create"):
            # VARIABLE X ( holds: K ): X's cell holds K.  CREATE T ( holds: K ):
            # every cell of T's area holds K, as a table of tokens does.
            new.signature = Effect((), ((Slot("addr", E.ADDR, holds=held,
                                              array=kind == "create" and held is not None),),))
        elif kind == "constant":
            new.const = value.const if value is not None else None
            new.xt = value.xt if value is not None else None
            out_kind = E.XT if new.xt is not None else (
                value.kind if value is not None and value.kind not in (E.X,) else E.LIT)
            # N CONSTANT FIELD ( holds: K ) declares a field offset: added to
            # a record's address it gives the address of a cell holding K.
            new.signature = Effect((), ((Slot(name, out_kind, None, new.const, xt=new.xt,
                                              holds=held),),))
        elif kind == "value":
            # V VALUE X ( holds: K ): X pushes a K, and TO X must store one.
            out = Slot(name, held.kind if held is not None else (value.kind if value else E.X),
                       effect=held.effect if held is not None else None,
                       holds=held.holds if held is not None else None)
            new.signature = Effect((), ((out,),))
        elif kind == "marker":
            new.signature = Effect((), ((),))
        new.signature_source = "given"
        checker.define(new)
        if kind == "defer":
            new.signature = None
            # DEFER NAME ( effect ) declares what the deferred word will do.
            saved = cursor.pos
            if cursor.token() == "(":
                checker._set_declared(new, cursor.paren())
                for problem in new.problems:
                    checker.declaration_problem(problem, new.name)
                if new.declared is not None and not new.declared.variable:
                    new.signature = new.declared
            else:
                cursor.pos = saved
    return handler


def _top_tick(checker: Checker, cursor: LineCursor, word: Word) -> None:
    name = cursor.token()
    target = checker.lookup(name) if name else None
    checker.top.append(Value(E.XT, xt=target, origin=f"' {name}"))


def _top_char(checker: Checker, cursor: LineCursor, word: Word) -> None:
    name = cursor.token()
    checker.top.append(literal(ord(name[0]) if name else 0))


def _top_squote(checker: Checker, cursor: LineCursor, word: Word) -> None:
    text = cursor.quoted()
    span = next(_span_counter)
    checker.top.append(Value(E.ADDR, span=span, role="a", origin='S"'))
    checker.top.append(Value(E.COUNT, const=len(text.encode("utf-8")), span=span, role="u"))


def _top_dotquote(checker: Checker, cursor: LineCursor, word: Word) -> None:
    cursor.quoted()


def _top_abortquote(checker: Checker, cursor: LineCursor, word: Word) -> None:
    cursor.quoted()
    checker._pop_top()


def _top_paren(checker: Checker, cursor: LineCursor, word: Word) -> None:
    text, closed = cursor.paren_closed()
    declared, problems, declaration = parse_kind_declaration(text, checker.resolve_kind)
    if not declaration:
        return
    if not closed:
        problems = problems + ["the declaration's ( has no ) on its line"]
    for problem in problems:
        checker.declaration_problem(problem, "(kind)")
    if declared is not None:
        name, parent = declared
        problem = checker.declare_kind(name, parent)
        if problem is not None:
            checker.declaration_problem(problem, "(kind)")
        else:
            checker.declared_kinds.append((checker.group, name))


def _top_require(checker: Checker, cursor: LineCursor, word: Word) -> None:
    name = cursor.token()
    if name and checker.require is not None:
        checker.require(name, checker.module)


def _top_skip_name(checker: Checker, cursor: LineCursor, word: Word) -> None:
    cursor.token()


def _top_defined(defined: bool):
    def handler(checker: Checker, cursor: LineCursor, word: Word) -> None:
        name = cursor.token()
        found = name is not None and checker.lookup(name) is not None
        checker.top.append(literal(-1 if found == defined else 0))
    return handler


def _top_if(checker: Checker, cursor: LineCursor, word: Word) -> None:
    flag = checker._pop_top()
    if flag.const is None:
        checker.unknown_conditions += 1
        checker.cond_frames.append("both")
        return
    if flag.const != 0:
        checker.cond_frames.append("true")
        return
    checker._start_skip(else_stops=True)


def _top_else(checker: Checker, cursor: LineCursor, word: Word) -> None:
    if checker.cond_frames and checker.cond_frames[-1] == "both":
        return
    if checker.cond_frames:
        checker.cond_frames.pop()
    checker._start_skip(else_stops=False)


def _top_then(checker: Checker, cursor: LineCursor, word: Word) -> None:
    if checker.cond_frames:
        checker.cond_frames.pop()


def _top_immediate(checker: Checker, cursor: LineCursor, word: Word) -> None:
    latest = checker.records[-1].word if checker.records else None
    if latest is not None:
        latest.immediate = True


def _top_base(base: int):
    def handler(checker: Checker, cursor: LineCursor, word: Word) -> None:
        checker.base = base
    return handler


def _top_is(checker: Checker, cursor: LineCursor, word: Word) -> None:
    value = checker._pop_top()
    name = cursor.token()
    target = checker.lookup(name) if name else None
    if target is not None and target.kind == "defer" and value.xt is not None:
        bound = value.xt.signature
        if target.declared is None and bound is not None:
            target.signature = bound
            target.signature_source = "inferred"
        elif (target.declared is not None and not target.declared.variable and bound is not None
              and not bound.variable and effect_shape(bound) != effect_shape(target.declared)):
            checker.findings.append(Finding(
                "token effect", f"IS {target.name} binds {value.xt.name} ( {bound.shape()} ) "
                                f"to a deferred word declared ( {target.declared.shape()} )",
                checker.module, checker.line, target.name, checker.group))


def _top_to(checker: Checker, cursor: LineCursor, word: Word) -> None:
    name = cursor.token()
    value = checker._pop_top()
    target = checker.lookup(name) if name else None
    if target is not None and target.holds is not None:
        problem = checker.compatible(value.kind, target.holds.kind)
        if problem is not None:
            checker.findings.append(Finding(
                "kind", f"{problem}: {value.kind} stored by TO {target.name}, which holds "
                        f"{target.holds.kind}", checker.module, checker.line, target.name,
                checker.group))


def _top_semicolon(checker: Checker, cursor: LineCursor, word: Word) -> None:
    return


def _top_bracket_tick(checker: Checker, cursor: LineCursor, word: Word) -> None:
    _top_tick(checker, cursor, word)


TOP_HANDLERS: dict[str, Callable] = {
    ":": _top_colon,
    ":NONAME": _top_noname,
    "VARIABLE": _top_create("variable", False),
    "CREATE": _top_create("create", False),
    "CONSTANT": _top_create("constant", True),
    "VALUE": _top_create("value", True),
    "DEFER": _top_create("defer", False),
    "MARKER": _top_create("marker", False),
    "'": _top_tick,
    "[']": _top_bracket_tick,
    "CHAR": _top_char,
    "[CHAR]": _top_char,
    'S"': _top_squote,
    '."': _top_dotquote,
    'ABORT"': _top_abortquote,
    "(": _top_paren,
    "REQUIRE": _top_require,
    "PROVIDED": _top_skip_name,
    "FSLOAD": _top_skip_name,
    "[DEFINED]": _top_defined(True),
    "[UNDEFINED]": _top_defined(False),
    "[IF]": _top_if,
    "[ELSE]": _top_else,
    "[THEN]": _top_then,
    "IMMEDIATE": _top_immediate,
    "HEX": _top_base(16),
    "DECIMAL": _top_base(10),
    "IS": _top_is,
    "TO": _top_to,
    ";": _top_semicolon,
}

# KDOS defines these at Forth level; the top-level handlers model them.
BASE_TOP = {"DEFER", "IS", "REQUIRE", "PROVIDED", "MARKER"}


_TOP_WORD = Word("(top level)", "", 0, "source")


def _fold_top(name: str):
    """Run a shuffle or arithmetic word on the top-level stack, folding constants.

    Constants matter at the top level because CONSTANT and [IF] read them.
    """
    handler = PRIM_HANDLERS[name]

    def fold(checker: Checker) -> None:
        analysis = Analysis(checker, _TOP_WORD, None, None)
        state = State(list(checker.top), 0, [])
        try:
            results = handler(analysis, state, checker.words.get(name) or _TOP_WORD)
        except Fail:
            checker.top.clear()
            return
        if len(results) != 1:
            checker.top.clear()
            return
        result = results[0]
        checker.top[:] = [v for v in result.items if not analysis.is_input(v)]

    return fold


_FOLDABLE = (
    "DUP DROP SWAP OVER ROT -ROT NIP TUCK 2DUP 2DROP 2SWAP 2OVER 2ROT PICK ROLL TRUE FALSE "
    "BL + - * / MOD AND OR XOR LSHIFT RSHIFT MIN MAX = <> < > <= >= U< U> 1+ 1- CELL+ CELLS "
    "2* 2/ NEGATE ABS INVERT 0= 0<> 0< 0>"
).split()
FOLDS = {name: _fold_top(name) for name in _FOLDABLE}


# ----------------------------------------------------------------------
# Compile-time words


def _compile_semicolon(checker: Checker, cursor: LineCursor, pending: Pending, line: int) -> None:
    if pending.quotation:
        return
    checker._finish_colon()


def _compile_bracket(checker: Checker, cursor: LineCursor, pending: Pending, line: int) -> None:
    pending.interp = True


def _compile_literal(checker: Checker, cursor: LineCursor, pending: Pending, line: int) -> None:
    value = checker._pop_top()
    pending.items.append(("litval", value, line))


def _compile_squote(checker: Checker, cursor: LineCursor, pending: Pending, line: int) -> None:
    text = cursor.quoted()
    pending.items.append(("str", len(text.encode("utf-8")), line))


def _compile_dotquote(checker: Checker, cursor: LineCursor, pending: Pending, line: int) -> None:
    cursor.quoted()


def _compile_abortquote(checker: Checker, cursor: LineCursor, pending: Pending, line: int) -> None:
    cursor.quoted()
    pending.items.append(("abortq", None, line))


def _compile_char(checker: Checker, cursor: LineCursor, pending: Pending, line: int) -> None:
    name = cursor.token()
    pending.items.append(("lit", ord(name[0]) if name else 0, line))


def _compile_tick(checker: Checker, cursor: LineCursor, pending: Pending, line: int) -> None:
    name = cursor.token()
    target = checker.lookup(name) if name else None
    if target is None:
        pending.items.append(("undefined", name or "", line))
    else:
        pending.items.append(("xt", target, line))


def _compile_to(checker: Checker, cursor: LineCursor, pending: Pending, line: int) -> None:
    name = cursor.token()
    target = checker.lookup(name) if name else None
    pending.items.append(("to", target, line))


def _compile_postpone(checker: Checker, cursor: LineCursor, pending: Pending, line: int) -> None:
    name = cursor.token()
    pending.items.append(("postpone", name or "", line))


def _compile_does(checker: Checker, cursor: LineCursor, pending: Pending, line: int) -> None:
    pending.items.append(("does", None, line))


def _compile_quote_open(checker: Checker, cursor: LineCursor, pending: Pending, line: int) -> None:
    checker._begin_colon(None, quotation=True)


def _compile_quote_close(checker: Checker, cursor: LineCursor, pending: Pending, line: int) -> None:
    if not pending.quotation:
        return
    word = checker._finish_colon()
    outer = checker.pending
    if outer is not None:
        outer.items.append(("xt", word, line))


def _compile_at_top(name: str):
    def handler(checker: Checker, cursor: LineCursor, pending: Pending, line: int) -> None:
        TOP_HANDLERS[name](checker, cursor, checker.words[name])
    return handler


COMPILE_HANDLERS: dict[str, Callable] = {
    ";": _compile_semicolon,
    "[": _compile_bracket,
    "LITERAL": _compile_literal,
    'S"': _compile_squote,
    '."': _compile_dotquote,
    'ABORT"': _compile_abortquote,
    "[CHAR]": _compile_char,
    "[']": _compile_tick,
    "TO": _compile_to,
    "POSTPONE": _compile_postpone,
    "DOES>": _compile_does,
    "[:": _compile_quote_open,
    ";]": _compile_quote_close,
    "[IF]": _compile_at_top("[IF]"),
    "[ELSE]": _compile_at_top("[ELSE]"),
    "[THEN]": _compile_at_top("[THEN]"),
    "[DEFINED]": _compile_at_top("[DEFINED]"),
    "[UNDEFINED]": _compile_at_top("[UNDEFINED]"),
}
