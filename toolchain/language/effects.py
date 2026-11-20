"""Kinds and stack effects, and how stack comments name them.

A kind describes what a cell holds.  The plain kinds come from the informal
names Akashic's stack comments already use; ``ref`` and ``handle`` are the
kinds managed data is about (release plan Part 9d).  ``x`` is a cell of no
known kind, and ``lit`` is a number written in the source, which serves as
any plain kind: ``0`` is a null address as readily as a false flag.

A stack effect lists its inputs and one or more alternatives for its
outputs, each ordered from the deepest cell to the top.  Alternatives of
different depths are told apart by a known zero or nonzero top cell, as in
``( -- addr len true | false )``.  An output may be marked as one of the
inputs passed through unchanged, which inferred effects record exactly.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

X = "x"
LIT = "lit"
FLAG = "flag"
XT = "xt"
ADDR = "addr"
COUNT = "u"
NUMBER = "n"
CHAR = "char"
STATUS = "ior"
REF = "ref"
HANDLE = "handle"

PLAIN_NUMBERS = frozenset({COUNT, NUMBER, CHAR, STATUS})
MANAGED = frozenset({REF, HANDLE})

# Facts about a cell that the checker can route an IF on.
ZERO = 0
NONZERO = 1

_FLAG_NAMES = {"flag", "?", "bool", "true", "false", "ok"}
# Single letters that a comment uses as plain cells when it names a and b.
_GENERIC_LETTERS = {"a", "b", "c", "d"}
_XT_NAMES = {"xt", "cfa", "xt0"}
_ADDR_NAMES = {
    "addr", "a-addr", "c-addr", "ca", "adr", "address", "ptr",
    "buf", "buffer", "dst", "src", "dest", "str", "here",
}
# "a" and "p" name an address in "( a u -- )" and "( record -- a )", but
# plain numbers in math words such as "( a -- floor )"; _slots decides.
_CONTEXT_LETTERS = {"a", "p"}
_COUNT_NAMES = {
    "u", "len", "length", "count", "cnt", "size", "bytes", "nbytes",
    "n-bytes", "+n", "capacity", "cap", "#", "num", "u8", "u16", "u32", "u64",
}
# Akashic writes "i" for an instance as often as for an index, so single
# letters other than n and u name no kind.
_NUMBER_NAMES = {"n", "idx", "index", "offset", "off", "delta", "+n"}
_CHAR_NAMES = {"char", "byte", "c-char"}
_STATUS_NAMES = {"ior", "status", "err", "error", "rc", "wior", "throw-code"}
_GENERIC_NAMES = {"x", "w", "v", "val", "value", "item", "cell", "any"}

_ADDR_SUFFIXES = ("-a", "-addr", "-ptr", "-buf", "-buffer", "-adr", "-address")
_COUNT_SUFFIXES = (
    "-u", "-len", "-length", "-count", "-size", "-bytes", "-cap",
    "-capacity",
)
_NUMBER_SUFFIXES = ("-n", "-index", "-idx", "-offset", "-off")
_STATUS_SUFFIXES = ("-ior", "-status", "-err", "-error")
_XT_SUFFIXES = ("-xt",)

_TRAILING_RE = re.compile(r"(?<=[a-z?#])[0-9]*'*\Z")
_ARITH_RE = re.compile(r"\A([a-z#][a-z0-9#?-]*?[a-z0-9#?])([+*/][^ ]*|-[0-9n][^ ]*)\Z")


def base_name(name: str) -> str:
    """A comment name without numbering, primes or arithmetic suffixes.

    ``addr1``, ``addr'`` and ``addr+n`` all name an ``addr``; ``len-n``
    names a ``len``.
    """
    text = name.lower().strip(",.;:")
    match = _ARITH_RE.match(text)
    if match:
        text = match.group(1)
    text = _TRAILING_RE.sub("", text) or text
    return text


def kind_of_name(name: str, managed_names: dict[str, str]) -> str:
    """The kind an informal stack-comment name stands for."""
    raw = name.lower()
    if raw in managed_names:
        return managed_names[raw]
    if _is_number_literal(raw):
        return LIT
    text = base_name(raw)
    if text in _CONTEXT_LETTERS:
        return ADDR
    if text in managed_names:
        return managed_names[text]
    if text in _GENERIC_NAMES:
        return X
    if text in _FLAG_NAMES or text.endswith("?") or text.endswith("-flag"):
        return FLAG
    if text in _XT_NAMES or text.endswith(_XT_SUFFIXES) or text.startswith("xt-"):
        return XT
    if text in _ADDR_NAMES or text.endswith(_ADDR_SUFFIXES):
        return ADDR
    if text in _COUNT_NAMES or text.endswith(_COUNT_SUFFIXES):
        return COUNT
    if text in _NUMBER_NAMES or text.endswith(_NUMBER_SUFFIXES):
        return NUMBER
    if text in _CHAR_NAMES or text.endswith(("-char", "-byte")):
        return CHAR
    if text in _STATUS_NAMES or text.endswith(_STATUS_SUFFIXES):
        return STATUS
    return X


def _is_number_literal(text: str) -> bool:
    return bool(re.fullmatch(r"-?(0x[0-9a-f]+|[0-9]+)", text))


def name_fact(name: str) -> int | None:
    """Whether an output name says its cell is zero or nonzero."""
    text = name.lower()
    if text in ("0", "false", "0|false"):
        return ZERO
    if text in ("true", "-1") or (_is_number_literal(text) and int(text, 0) != 0):
        return NONZERO
    return None


def name_prefix(name: str) -> str | None:
    """The part of a hyphenated name before its last element, if any."""
    text = base_name(name)
    if "-" not in text.strip("-"):
        return None
    return text.rsplit("-", 1)[0]


def is_span_pair(first: str, second: str, managed_names: dict[str, str]) -> bool:
    """Whether two adjacent comment names describe one span: address, length."""
    if kind_of_name(first, managed_names) != ADDR:
        return False
    if kind_of_name(second, managed_names) not in (COUNT, NUMBER):
        return False
    if base_name(second) not in _COUNT_NAMES | {"n"} and not base_name(
        second
    ).endswith(_COUNT_SUFFIXES):
        return False
    one = name_prefix(first)
    two = name_prefix(second)
    if one is not None and two is not None and one != two:
        return False
    if (one is None) != (two is None):
        # "key-a u" or "addr key-u" pair a named span with an anonymous part.
        anonymous = second if one is not None else first
        if base_name(anonymous) not in _COUNT_NAMES | _ADDR_NAMES | {"n"}:
            return False
    return True


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


_VARIABLE_RE = re.compile(r"(\b[ijkmn]\*[a-z]|\.\.|…)")
_PARSE_RE = re.compile(r'\A(".*"|<.*>|\'.*\')\Z')


def parse_effect(text: str, managed_names: dict[str, str]) -> ParsedComment:
    """Read a stack comment's text (without its parentheses) as an effect."""
    tokens = text.replace("—", " -- ").split()
    if "--" not in tokens:
        return ParsedComment(None, "no --")
    split = tokens.index("--")
    left = tokens[:split]
    right = tokens[split + 1 :]
    if "--" in right:
        return ParsedComment(None, "two --")
    returns_r = False
    for side in (left, right):
        for marker in ("R:", "r:"):
            if marker in side:
                returns_r = True
                del side[side.index(marker) :]
    joined = " ".join(left + right)
    if _VARIABLE_RE.search(joined):
        return ParsedComment(
            Effect((), (), variable=True, text=text), "variable", left + right
        )
    parses = 0
    inputs: list[str] = []
    for token in left:
        if _PARSE_RE.match(token):
            parses += 1
            continue
        if "|" in token:
            return ParsedComment(
                Effect((), (), variable=True, text=text),
                "alternatives among inputs",
                left + right,
            )
        inputs.append(token)
    # A bar standing alone, or at a token's edge as in "0 |xt 1", separates
    # whole alternatives; a bar inside a token, as in "dentry|0", names the
    # values one cell may take.
    alternatives: list[list[str]] = [[]]
    for token in right:
        if _PARSE_RE.match(token):
            continue
        leading = token.startswith("|")
        trailing = token.endswith("|") and len(token) > 1
        core = token.strip("|")
        if leading or token == "|":
            alternatives.append([])
        if core:
            alternatives[-1].append(core)
        if trailing:
            alternatives.append([])
    alternatives = [alt for alt in alternatives if alt] or [[]]
    every = {base_name(name) for name in inputs} | {
        base_name(name) for names in alternatives for name in names
    }
    generic = {"a", "b"} <= every
    in_slots = _slots(inputs, managed_names, outputs=False, generic=generic)
    alts = tuple(
        _slots(names, managed_names, outputs=True, generic=generic) for names in alternatives
    )
    effect = Effect(
        tuple(in_slots), tuple(tuple(a) for a in alts), parses, False, text, returns_r
    )
    return ParsedComment(effect, None, inputs + [n for a in alternatives for n in a])


def _slots(names: list[str], managed_names: dict[str, str], outputs: bool,
           generic: bool = False) -> list[Slot]:
    slots = []
    for index, name in enumerate(names):
        base = base_name(name)
        if generic and base in _GENERIC_LETTERS:
            slots.append(Slot(name, X))
            continue
        if base in _CONTEXT_LETTERS:
            following = base_name(names[index + 1]) if index + 1 < len(names) else ""
            spans = following in _COUNT_NAMES or following == "n"
            accessor = outputs and len(names) == 1
            slots.append(Slot(name, ADDR if spans or accessor else X))
            continue
        if "|" in name:
            # One cell that holds one of several values, such as "dentry|0".
            kinds = {kind_of_name(part, managed_names) for part in name.split("|") if part}
            kinds.discard(LIT)
            slots.append(Slot(name, kinds.pop() if len(kinds) == 1 else X))
            continue
        kind = kind_of_name(name, managed_names)
        fact = name_fact(name) if outputs else None
        const = None
        if kind == LIT:
            const = int(name.lower(), 0)
            fact = ZERO if const == 0 else NONZERO
        slots.append(Slot(name, kind, fact, const))
    index = 0
    while index + 1 < len(slots):
        if slots[index].kind == ADDR and is_span_pair(
            names[index], names[index + 1], managed_names
        ):
            first, second = slots[index], slots[index + 1]
            slots[index] = Slot(first.name, first.kind, first.fact, first.const, index, "a")
            slots[index + 1] = Slot(
                second.name, second.kind, second.fact, second.const, index, "u"
            )
            index += 2
        else:
            index += 1
    return slots


def compatible(value_kind: str, param_kind: str) -> str | None:
    """None when a value of one kind may fill a slot of another; else a class.

    The classes name the mismatches the checker reports.  Numbers and flags
    mix freely, as Forth code uses any nonzero cell as true, and an address
    may serve as a flag, as code tests for a null pointer.
    """
    if param_kind in (X, LIT) or value_kind in (X, LIT) or value_kind == param_kind:
        return None
    if value_kind in MANAGED or param_kind in MANAGED:
        if value_kind == REF and param_kind == ADDR:
            return None  # rule 1: managed objects are read directly
        return "managed kind crosses plain data"
    if value_kind == XT or param_kind == XT:
        return "execution token mixed with data"
    numberish = PLAIN_NUMBERS | {FLAG}
    if value_kind in numberish and param_kind in numberish:
        return None
    if value_kind == ADDR and param_kind == FLAG:
        return None
    if value_kind == FLAG and param_kind == ADDR:
        return "flag used as an address"
    if value_kind == ADDR and param_kind in PLAIN_NUMBERS:
        return "address used as a number"
    if value_kind in PLAIN_NUMBERS and param_kind == ADDR:
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
