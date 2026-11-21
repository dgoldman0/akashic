"""Kinds, stack effects, and the declarations that state them.

Uroko writes a kind after an item's name and a colon, inside the ordinary
stack comment, as Factor writes stack effects::

    ( buf: span  c: concept -- n: u )

An item without a kind is a plain cell, and no kind is ever read from a
name.  ``span`` stands for two cells, an address and a length that bound one
piece of memory.  A slot that holds an execution token states the token's
effect as a nested comment, ``xt( text: span -- )``, and an item labelled
``holds:`` is the address of a cell holding the kind that follows, as in
``VARIABLE YAML-EMIT-XT ( holds: xt( text: span -- ) )``.  KDOS's ``(``
counts nested parentheses, so it skips the whole declaration as a comment.
A module names an effect once, ``( kind: nio-io xt( buf: span context --
count: u ) )``, and writes the name wherever a kind may stand, as in
``( holds: nio-io )``; the name stands for the effect.

The built-in kinds of plain data are ``cell`` (no kind), ``n``, ``u``,
``flag``, ``char``, ``addr``, ``span``, ``xt``, ``task``, and ``struct``, a
record in plain memory that code manages by hand.  The kinds of managed
data, the objects of release plan Part 9d that a collector manages, are
``tagged`` (any word in LM1's format), ``ref`` (a reference, valid only in
the window that read it), ``record``, ``string``, ``vector`` and ``bytes``
(references to those objects), ``list`` and ``list( k )`` (nil or a cons
cell, whose elements are of kind k), and ``handle`` and ``handle( k )`` (a
handle, which names an object of kind k).  ``struct`` refines ``addr``;
``record``, ``string``, ``vector`` and ``bytes`` refine ``ref``; ``ref`` and
``list`` refine ``tagged``; ``list( j )`` refines ``list( k )`` and
``handle( j )`` refines ``handle( k )`` when j refines k.  A handle is
neither a reference nor an address.

A source file adds kinds with ``( kind: NAME BASE )``, such as
``( kind: nio-port struct )`` for a struct, ``( kind: concept record )``
for a collected record or ``( kind: nio-status n )`` for a kind of number;
a named kind mixes freely with the kinds it refines but not with another
named kind.

A stack effect lists its inputs and one or more alternatives for its
outputs, each ordered from the deepest cell to the top.  Alternatives of
different depths are told apart by a known zero or nonzero top cell, as in
``( -- s: span true | false )``.  An output may be marked as one of the
inputs passed through unchanged, which inferred effects record exactly.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Callable

X = "x"
LIT = "lit"
FLAG = "flag"
XT = "xt"
ADDR = "addr"
COUNT = "u"
NUMBER = "n"
CHAR = "char"
TASK = "task"
STRUCT = "struct"
TAGGED = "tagged"
REF = "ref"
RECORD = "record"
STRING = "string"
VECTOR = "vector"
BYTES = "bytes"
LIST = "list"
HANDLE = "handle"

PLAIN_NUMBERS = frozenset({COUNT, NUMBER, CHAR})

# The names a declaration may use for the built-in kinds.  "span" is two
# cells and is handled where items become slots; "list( k )" and
# "handle( k )" are read where kinds are.
BUILTIN_KINDS = {
    "cell": X, "n": NUMBER, "u": COUNT, "flag": FLAG, "char": CHAR, "addr": ADDR,
    "xt": XT, "task": TASK, "struct": STRUCT, "tagged": TAGGED, "ref": REF,
    "record": RECORD, "string": STRING, "vector": VECTOR, "bytes": BYTES, "list": LIST,
    "handle": HANDLE,
}
# Built-in kinds that refine another: a struct is an address of plain
# memory; records, strings, vectors and bytevectors are references; and a
# reference or a list is a tagged word.
BUILTIN_PARENTS = {
    STRUCT: ADDR,
    RECORD: REF, STRING: REF, VECTOR: REF, BYTES: REF,
    REF: TAGGED, LIST: TAGGED,
}

# The forms that take a kind as a parameter, as "list( concept )" does.
_PARAMETRIC = {"list(": LIST, "handle(": HANDLE}
_OPENERS = ("xt(",) + tuple(_PARAMETRIC)


def builtin_parent(kind: str) -> str | None:
    """The kind a built-in or parametric kind refines, if any."""
    if kind in BUILTIN_PARENTS:
        return BUILTIN_PARENTS[kind]
    return parametric_parent(kind, builtin_parent)


def _parameter(kind: str) -> tuple[str, str] | None:
    """A parametric kind's form and parameter: "list(concept)" gives both."""
    for opener, form in _PARAMETRIC.items():
        if kind.startswith(opener) and kind.endswith(")"):
            return form, kind[len(opener):-1]
    return None


def chain(kind: str, parent: Callable[[str], "str | None"]) -> list[str]:
    """A kind and every kind it refines, ending with the kind it rests on."""
    found = [kind]
    seen = {kind}
    while True:
        up = parent(found[-1])
        if up is None or up in seen:
            return found
        found.append(up)
        seen.add(up)


def list_kind(element: str, parent: Callable[[str], "str | None"]) -> tuple[str | None, str | None]:
    """The kind ``list( element )``, or the reason it is not one.

    A list's elements are tagged words, so the element kind is one that
    rests on ``tagged``, or a flag or a character, which a tagged word
    holds as t or nil and as LM1's character.  A list of tagged words is
    the plain ``list``.
    """
    rests_on = chain(element, parent)[-1]
    if rests_on not in (TAGGED, FLAG, CHAR):
        return None, f"a list holds tagged words, and {element} is plain data"
    return (LIST if element == TAGGED else f"list({element})"), None


def handle_kind(target: str, parent: Callable[[str], "str | None"]) -> tuple[str | None, str | None]:
    """The kind ``handle( target )``, or the reason it is not one.

    A handle names an object, so the target is a reference kind or a list;
    a handle of any object is the plain ``handle``.
    """
    lineage = chain(target, parent)
    if REF not in lineage and LIST not in lineage:
        return None, f"a handle names an object, and {target} is not a kind of object"
    return (HANDLE if target == REF else f"handle({target})"), None


def parametric_parent(kind: str, parent: Callable[[str], "str | None"]) -> str | None:
    """What ``list( k )`` or ``handle( k )`` refines: the same form of k's parent.

    ``list( concept )`` refines ``list( record )``, which refines
    ``list( ref )`` and then the plain ``list``; a handle's kinds refine
    one another the same way, down to the plain ``handle``.
    """
    found = _parameter(kind)
    if found is None:
        return None
    form, inner = found
    up = parent(inner)
    if up is None:
        return form
    made, _ = (list_kind if form == LIST else handle_kind)(up, parent)
    return made if made is not None else form

# Facts about a cell that the checker can route an IF on.
ZERO = 0
NONZERO = 1


@dataclass(frozen=True)
class Slot:
    """One cell of an effect: its name in the comment, kind and what is known."""

    name: str
    kind: str = X
    fact: int | None = None
    const: int | None = None
    span: int | None = None  # index of this pair's first slot within its list
    role: str | None = None  # "a" for the address, "u" for the length
    passthrough: int | None = None  # outputs: input number, 1 = top input
    xt: object | None = None  # a known execution token's word
    effect: "Effect | None" = None  # the declared effect of an execution token
    holds: "Slot | None" = None  # an address: what the cell it points at holds
    part_of: int | None = None  # outputs: input slot whose span this one is part of
    array: bool = False  # an address: every cell from here on holds ``holds``


@dataclass(frozen=True)
class Effect:
    """A stack effect: inputs, output alternatives, and input-stream names."""

    inputs: tuple[Slot, ...]
    alts: tuple[tuple[Slot, ...], ...]
    parses: int = 0
    variable: bool = False
    text: str = ""
    returns_r: bool = False

    @property
    def depths(self) -> tuple[int, ...]:
        return tuple(sorted({len(alt) for alt in self.alts}))

    def shape(self) -> str:
        """The effect written as counts, such as ``2 -- 1|3``."""
        if self.variable:
            return "variable"
        outs = "|".join(str(len(alt)) for alt in self.alts) or "never returns"
        return f"{len(self.inputs)} -- {outs}"


@dataclass
class ParsedComment:
    effect: Effect | None
    reason: str | None = None
    names: list[str] = field(default_factory=list)
    problems: list[str] = field(default_factory=list)
    declared: int = 0  # items that carry a declared kind


# A resolver maps a kind name written in a declaration to the checker's kind,
# to the effect a named effect stands for, or to None when no such kind is
# visible.  Parents maps a kind to the kind it refines, which a parametric
# kind needs to check its parameter.
Resolver = Callable[[str], "str | Effect | None"]
Parents = Callable[[str], "str | None"]


def builtin_resolver(name: str) -> str | None:
    return BUILTIN_KINDS.get(name.lower())


_VARIABLE_RE = re.compile(r"(\b[ijkmn]\*[a-z]|\.\.|…)")
_PARSE_RE = re.compile(r'\A(".*"|<.*>|\'.*\')\Z')
# "name:" labels an item; a bar inside the name, as in "port|0:", names the
# values the cell may take, while a bar at its edge separates alternatives.
_LABEL_RE = re.compile(r"\A(?!\|)[^\s:()]+(?<!\|):\Z")


def _is_number_literal(text: str) -> bool:
    return bool(re.fullmatch(r"-?(0x[0-9a-f]+|[0-9]+)", text))


def name_fact(name: str) -> int | None:
    """Whether an output name states that its cell is zero or nonzero."""
    text = name.lower()
    if text in ("0", "false", "0|false"):
        return ZERO
    if text in ("true", "-1") or (_is_number_literal(text) and int(text, 0) != 0):
        return NONZERO
    return None


def _opens(token: str) -> bool:
    """Whether a token opens a nested form: ``xt(``, ``list(`` or ``handle(``."""
    return token.lower() in _OPENERS


def _tokens(text: str) -> list[str]:
    """Split a comment into tokens, with each opener and ``)`` standing alone."""
    out: list[str] = []
    for token in text.replace("—", " -- ").split():
        while True:
            lowered = token.lower()
            opener = next((o for o in _OPENERS if lowered.startswith(o) and len(token) > len(o)),
                          None)
            if opener is None:
                break
            out.append(token[: len(opener)])
            token = token[len(opener):]
        if _opens(token) or token == ")":
            out.append(token)
            continue
        closing = 0
        while token.endswith(")") and len(token) > 1 and "(" not in token:
            token = token[:-1]
            closing += 1
        out.append(token)
        out.extend(")" for _ in range(closing))
    return out


@dataclass
class _Item:
    """One item of a comment before it becomes slots."""

    name: str
    kind: str | None = None  # None: a plain cell
    effect: Effect | None = None
    holds: "_Item | None" = None
    span: bool = False
    declared: bool = False


class _Parser:
    """Reads one comment's tokens; nested ``xt( ... )`` effects recurse."""

    def __init__(self, tokens: list[str], resolve: Resolver, problems: list[str],
                 parents: Parents | None = None) -> None:
        self.tokens = tokens
        self.pos = 0
        self.resolve = resolve
        self.parents = parents or builtin_parent
        self.problems = problems
        self.declared = 0

    def nested(self) -> Effect | None:
        """The effect inside ``xt( ... )``, after its opening token."""
        depth = 1
        start = self.pos
        while self.pos < len(self.tokens):
            token = self.tokens[self.pos]
            self.pos += 1
            if _opens(token):
                depth += 1
            elif token == ")":
                depth -= 1
                if depth == 0:
                    inner = self.tokens[start : self.pos - 1]
                    parsed = _effect_from_tokens(inner, self.resolve, self.problems,
                                                 self.parents)
                    self.declared += parsed.declared
                    if parsed.effect is None:
                        self.problems.append(
                            f"xt( {' '.join(inner)} ) is not an effect ({parsed.reason})")
                        return None
                    effect = parsed.effect
                    return Effect(effect.inputs, effect.alts, effect.parses, effect.variable,
                                  " ".join(inner), effect.returns_r)
        self.problems.append("xt( has no closing )")
        return None

    def kind_expression(self, name: str) -> tuple[str | None, Effect | None]:
        """One kind at the cursor, as the kind and the effect a token kind has.

        A kind is a kind's name, ``xt( effect )``, the name of an effect that
        a ``( kind: NAME xt( effect ) )`` declaration named, or ``list( k )``
        or ``handle( k )`` around another kind.  The kind is None after a
        problem, which the parser records.
        """
        token = self.tokens[self.pos]
        self.pos += 1
        lowered = token.lower()
        if lowered == "xt(":
            return XT, self.nested()
        if lowered in _PARAMETRIC:
            form = _PARAMETRIC[lowered]
            if self.pos >= len(self.tokens) or self.tokens[self.pos] in (")", "--", "|"):
                self.problems.append(f"{name}: {form}( names no kind")
                return None, None
            if self.tokens[self.pos].lower() == "span":
                self.pos += 1
                inner, effect = None, None
                self.problems.append(f"{name}: {form}( span ) names two cells, not one")
            else:
                inner, effect = self.kind_expression(name)
            if self.pos >= len(self.tokens) or self.tokens[self.pos] != ")":
                self.problems.append(f"{name}: {form}( has no closing )")
                return None, None
            self.pos += 1
            if inner is None:
                return None, None
            if inner == XT:
                self.problems.append(f"{name}: {form}( xt ): an execution token is plain data")
                return None, None
            made, problem = (list_kind if form == LIST else handle_kind)(inner, self.parents)
            if problem is not None:
                self.problems.append(f"{name}: {problem}")
            return made, None
        kind = self.resolve(lowered)
        if kind is None:
            self.problems.append(f"{name}: names an unknown kind '{token}'")
            return None, None
        if isinstance(kind, Effect):
            return XT, kind  # a named effect: a token that runs it
        return kind, None

    def kind_item(self, name: str) -> _Item:
        """The kind after a ``name:`` label."""
        if self.pos >= len(self.tokens):
            self.problems.append(f"{name}: has no kind")
            return _Item(name)
        token = self.tokens[self.pos]
        if token.lower() == "span":
            self.pos += 1
            self.declared += 1
            return _Item(name, span=True, declared=True)
        if token in ("--", "|", ")") or _LABEL_RE.match(token):
            self.problems.append(f"{name}: has no kind")
            return _Item(name)
        kind, effect = self.kind_expression(name)
        if kind is None:
            return _Item(name)
        self.declared += 1
        return _Item(name, kind, effect=effect, declared=True)

    def item(self, token: str) -> _Item:
        if _LABEL_RE.match(token):
            name = token[:-1]
            if name.lower() == "holds":
                content = self.kind_item(name)
                if content.span:
                    self.problems.append("holds: a cell cannot hold a span, which is two cells")
                    content = _Item(name)
                return _Item(name, ADDR, holds=content, declared=content.declared)
            return self.kind_item(name)
        if _opens(token):
            # A kind written without a name, as "xt( n -- n )" alone.
            self.pos -= 1
            kind, effect = self.kind_expression(token.lower()[:-1])
            if kind is None:
                return _Item(token.lower()[:-1])
            self.declared += 1
            return _Item(token.lower()[:-1], kind, effect=effect, declared=True)
        return _Item(token)


def parse_effect(text: str, resolve: Resolver | None = None,
                 parents: Parents | None = None) -> ParsedComment:
    """Read a stack comment's text (without its parentheses) as an effect."""
    problems: list[str] = []
    tokens = _tokens(text)
    parsed = _effect_from_tokens(tokens, resolve or builtin_resolver, problems, parents)
    unclosed: list[str] = []
    for token in tokens:
        if _opens(token):
            unclosed.append(token.lower())
        elif token == ")" and unclosed:
            unclosed.pop()
    if unclosed:
        problems.append(f"{unclosed[0]} has no closing )")
    parsed.problems = list(dict.fromkeys(problems + parsed.problems))
    if parsed.effect is not None:
        parsed.effect = Effect(parsed.effect.inputs, parsed.effect.alts, parsed.effect.parses,
                               parsed.effect.variable, text, parsed.effect.returns_r)
    return parsed


def _top_level_split(tokens: list[str]) -> list[int]:
    """Positions of ``--`` outside any nested ``xt( ... )`` or parametric kind."""
    depth = 0
    found = []
    for index, token in enumerate(tokens):
        if _opens(token):
            depth += 1
        elif token == ")" and depth:
            depth -= 1
        elif token == "--" and depth == 0:
            found.append(index)
    return found


def _outer_tokens(tokens: list[str]) -> list[str]:
    depth = 0
    outer = []
    for token in tokens:
        if _opens(token):
            depth += 1
        elif token == ")" and depth:
            depth -= 1
        elif depth == 0:
            outer.append(token)
    return outer


def _effect_from_tokens(tokens: list[str], resolve: Resolver, problems: list[str],
                        parents: Parents | None = None) -> ParsedComment:
    splits = _top_level_split(tokens)
    if not splits:
        return ParsedComment(None, "no --")
    if len(splits) > 1:
        return ParsedComment(None, "two --")
    split = splits[0]
    left = tokens[:split]
    right = tokens[split + 1 :]
    returns_r = False
    for side in (left, right):
        for index, token in enumerate(side):
            # "R:" starts a return-stack picture; "r:" does too unless a kind
            # follows, as in "r: ref", where it names an item.
            following = side[index + 1].lower() if index + 1 < len(side) else ""
            if token == "R:" or (token == "r:" and not _opens(following) and following != "span"
                                 and resolve(following) is None):
                returns_r = True
                del side[index:]
                break
    outer = _outer_tokens(left + right)
    if _VARIABLE_RE.search(" ".join(outer)):
        return ParsedComment(Effect((), (), variable=True), "variable", outer)
    parses = 0
    in_items: list[_Item] = []
    parser = _Parser(left, resolve, problems, parents)
    while parser.pos < len(left):
        token = left[parser.pos]
        parser.pos += 1
        if _PARSE_RE.match(token):
            parses += 1
            continue
        if "|" in token:
            return ParsedComment(Effect((), (), variable=True), "alternatives among inputs", outer)
        if token == ")":
            problems.append("a ) closes nothing")
            continue
        in_items.append(parser.item(token))
    # A bar standing alone, or at a token's edge as in "0 |xt 1", separates
    # whole alternatives; a bar inside a token, as in "dentry|0", names the
    # values one cell may take.
    alternatives: list[list[_Item]] = [[]]
    out_parser = _Parser(right, resolve, problems, parents)
    while out_parser.pos < len(right):
        token = right[out_parser.pos]
        out_parser.pos += 1
        if _PARSE_RE.match(token):
            continue
        if token == ")":
            problems.append("a ) closes nothing")
            continue
        leading = token.startswith("|")
        trailing = token.endswith("|") and len(token) > 1
        core = token.strip("|")
        if leading or token == "|":
            alternatives.append([])
        if core:
            alternatives[-1].append(out_parser.item(core))
        if trailing:
            alternatives.append([])
    alternatives = [alt for alt in alternatives if alt] or [[]]
    in_slots = _slots(in_items, outputs=False)
    alts = tuple(tuple(_slots(items, outputs=True, inputs=in_items, in_slots=in_slots))
                 for items in alternatives)
    effect = Effect(tuple(in_slots), alts, parses, False, "", returns_r)
    names = [item.name for item in in_items] + [i.name for alt in alternatives for i in alt]
    return ParsedComment(effect, None, names, [], parser.declared + out_parser.declared)


def _slot(item: _Item, outputs: bool) -> Slot:
    if item.holds is not None:
        content = _slot(item.holds, outputs)
        return Slot(item.name, ADDR, holds=content)
    if item.kind is not None:
        return Slot(item.name, item.kind, effect=item.effect)
    name = item.name
    lowered = name.lower()
    if _is_number_literal(lowered):
        const = int(lowered, 0)
        return Slot(name, LIT, ZERO if const == 0 else NONZERO, const)
    if lowered in ("true", "false"):
        return Slot(name, FLAG, name_fact(name) if outputs else None)
    if "|" in name:
        # One cell that holds one of several values, such as "dentry|0".
        return Slot(name, X)
    return Slot(name, X, name_fact(name) if outputs else None)


def _slots(items: list[_Item], outputs: bool, inputs: list[_Item] | None = None,
           in_slots: list[Slot] | None = None) -> list[Slot]:
    slots: list[Slot] = []
    for item in items:
        if item.span:
            index = len(slots)
            part_of = None
            if outputs and inputs is not None and in_slots is not None:
                part_of = _span_source(item.name, inputs, in_slots)
            slots.append(Slot(item.name, ADDR, span=index, role="a", part_of=part_of))
            slots.append(Slot(item.name, COUNT, span=index, role="u", part_of=part_of))
        else:
            slots.append(_slot(item, outputs))
    return slots


def _span_source(name: str, inputs: list[_Item], in_slots: list[Slot]) -> int | None:
    """The input span an output span is part of: ``s'`` is part of ``s``.

    An output that repeats an input span's name with primes added is a piece
    of that span, as ``/STRING ( s: span n -- s': span )`` returns the end
    of the span it was given.
    """
    stem = name.rstrip("'")
    if stem == name:
        return None
    for index, slot in enumerate(in_slots):
        if slot.role == "a" and slot.name == stem:
            return index
    return None


def parse_holds(text: str, resolve: Resolver | None = None, parents: Parents | None = None
                ) -> tuple[Slot | None, list[str], bool]:
    """A data word's ``( holds: KIND )`` declaration.

    Returns the slot for what the cell holds, the declaration's problems,
    and whether the comment is a declaration at all (one that starts with
    ``holds:``); any other comment is prose.
    """
    tokens = _tokens(text)
    if not tokens or tokens[0].lower() != "holds:":
        return None, [], False
    problems: list[str] = []
    parser = _Parser(tokens, resolve or builtin_resolver, problems, parents)
    parser.pos = 1
    item = parser.kind_item("holds")
    if item.span:
        problems.append("holds: a cell cannot hold a span, which is two cells")
        item = _Item("holds")
    if parser.pos < len(tokens):
        problems.append(f"text after the declared kind: {' '.join(tokens[parser.pos:])}")
    if not item.declared:
        return None, problems, True
    return _slot(item, outputs=True), problems, True


def parse_kind_declaration(text: str, resolve: Resolver | None = None,
                           parents: Parents | None = None
                           ) -> tuple[tuple[str, "str | Effect"] | None, list[str], bool]:
    """A ``( kind: NAME BASE )`` declaration: the new kind and its base.

    The base is a kind's name or a parametric kind, as in
    ``( kind: path list( string ) )``.  A base written as an effect,
    ``( kind: nio-io xt( buf: span context -- count: u ) )``, names that
    effect instead, and so does the name of an effect named before: the
    declaration's second element is then the effect.  A token of any word
    with that effect may stand where the name is written.
    """
    tokens = _tokens(text)
    if not tokens or tokens[0].lower() != "kind:":
        return None, [], False
    if len(tokens) < 3:
        return None, ["kind: takes a name and the kind it refines"], True
    name, base = tokens[1].lower(), tokens[2].lower()
    if name in BUILTIN_KINDS or name == "span":
        return None, [f"kind: {name} is a built-in kind"], True
    if not re.fullmatch(r"[a-z0-9][a-z0-9._-]*", name):
        return None, [f"kind: '{tokens[1]}' is not a kind name"], True
    resolve = resolve or builtin_resolver
    effect = None
    if not _opens(base):
        if len(tokens) != 3:
            return None, ["kind: takes a name and the kind it refines"], True
        if base == "span":
            return None, [f"kind: {name} cannot refine span, which is two cells"], True
        parent = resolve(base)
        if parent is None:
            return None, [f"kind: {name} refines an unknown kind '{tokens[2]}'"], True
        if isinstance(parent, Effect):
            parent, effect = XT, parent
    else:
        problems: list[str] = []
        parser = _Parser(tokens, resolve, problems, parents)
        parser.pos = 2
        parent, effect = parser.kind_expression(name)
        if problems:
            return None, [f"kind: {problem}" for problem in problems], True
        if parser.pos < len(tokens):
            return None, ["kind: takes a name and the kind it refines"], True
    if parent == XT and effect is not None:
        if effect.variable:
            return None, [f"kind: {name} names an effect that is not fixed"], True
        return (name, effect), [], True
    if parent in (X, XT):
        return None, [f"kind: {name} cannot refine {base}"], True
    return (name, parent), [], True


def effect_key(effect: Effect) -> tuple:
    """What makes two effects the same: their shapes and their cells' kinds."""
    return (len(effect.inputs), effect.depths, tuple(slot.kind for slot in effect.inputs),
            tuple(tuple(slot.kind for slot in alt) for alt in effect.alts))


def effect_shape(effect: Effect) -> tuple[int, tuple[int, ...]]:
    return len(effect.inputs), effect.depths


def compatible(value_kind: str, param_kind: str, parents: Parents | None = None) -> str | None:
    """None when a value of one kind may fill a slot of another; else a class.

    A named kind mixes freely with the kinds it refines, so a struct serves
    as an address and an address may stand where a struct is expected, but
    two named kinds that do not refine one another do not mix, nor do two
    kinds of object, such as a string and a record.  Managed data stays
    apart from plain data, except that a reference may stand where an
    address is read, as rule 1 of Part 9d reads objects directly; a handle
    is neither.  Numbers and flags mix freely, as Forth code uses any
    nonzero cell as true, and an address may serve as a flag, as code tests
    for a null pointer.
    """
    if param_kind in (X, LIT) or value_kind in (X, LIT) or value_kind == param_kind:
        return None
    parent = parents or builtin_parent
    value_chain = chain(value_kind, parent)
    param_chain = chain(param_kind, parent)
    if param_kind in value_chain or value_kind in param_chain:
        return None
    value_base, param_base = value_chain[-1], param_chain[-1]
    if value_base == param_base:
        # Neither refines the other, yet both rest on one built-in kind: two
        # kinds of object, or two named kinds such as two structs or two
        # kinds of status.
        if value_base in (TAGGED, HANDLE):
            return "object kinds differ"
        return "named kinds differ"
    if REF in value_chain and param_kind == ADDR:
        return None  # rule 1: an object's words are read directly
    if HANDLE in (value_base, param_base):
        return "handle mixed with other data"
    if TAGGED in (value_base, param_base):
        return "managed kind crosses plain data"
    if value_base == XT or param_base == XT:
        return "execution token mixed with data"
    if value_base == TASK or param_base == TASK:
        return "task mixed with other data"
    numberish = PLAIN_NUMBERS | {FLAG}
    if value_base in numberish and param_base in numberish:
        return None
    if value_base == ADDR and param_base == FLAG:
        return None
    if value_base == FLAG and param_base == ADDR:
        return "flag used as an address"
    if value_base == ADDR and param_base in PLAIN_NUMBERS:
        return "address used as a number"
    if value_base in PLAIN_NUMBERS and param_base == ADDR:
        return "number used as an address"
    return "other"


def join_kinds(one: str, two: str) -> str:
    if one == two:
        return one
    if one == LIT:
        return two
    if two == LIT:
        return one
    if one in PLAIN_NUMBERS and two in PLAIN_NUMBERS:
        return NUMBER
    return X
