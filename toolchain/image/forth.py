"""Forth source text as the image tool reads and rewrites it.

The tokens of a source line, the module loads a line holds, and the
compaction, minification and line joining that linked chunks use.  KDOS's
own grammar for REQUIRE and PROVIDED lives in closure.py.
"""

from __future__ import annotations

import re

from .closure import REQUIRE_RE


COLON_STACK_EFFECT_RE = re.compile(
    r"^(?P<head> *: +[^ ]+) +(?P<effect>\([^()\r\n]*--[^()\r\n]*\))"
)
FORTH_CONDITIONAL_TOKENS = frozenset(("[IF]", "[ELSE]", "[THEN]"))
MEGAPAD_EVALUATE_SOURCE_MAX_BYTES = 255
FORTH_LINE_COALESCE_BARRIERS = frozenset(
    ("(", 'S"', 'C"', '."', 'ABORT"', ".(", "[IF]", "[ELSE]", "[THEN]")
)
FORTH_SPLIT_STACK_EFFECT_RE = re.compile(
    r"^\( [^()\r\n]*--[^()\r\n]*\) *$"
)


def _forth_byte_buffer(name: str, value: str) -> str:
    """Forth that holds VALUE's UTF-8 bytes in a buffer NAME, with their
    count in the constant NAME-u."""

    encoded = value.encode("utf-8")
    lines = [f"CREATE {name}"]
    for start in range(0, len(encoded), 24):
        chunk = encoded[start : start + 24]
        lines.append("  " + " ".join(f"{byte} C," for byte in chunk))
    lines.append(f"{len(encoded)} CONSTANT {name}-u")
    return "\n".join(lines)


def _forth_line_tokens(line: str) -> tuple[str, ...]:
    """Return executable words using MegaPad's ASCII-space token rules.

    The linked-source packer uses this stream to keep a colon definition in
    one MP64FS chunk.  Parser-word payloads are data, not executable tokens:
    in particular, a semicolon inside ``S\" ; detail`` must not look like the
    end of the surrounding definition.
    """
    tokens: list[str] = []
    quoted_next = False
    index = 0
    while index < len(line):
        while index < len(line) and line[index] == " ":
            index += 1
        if index >= len(line):
            break
        start = index
        while index < len(line) and line[index] != " ":
            index += 1
        token = line[start:index]
        upper = token.upper()
        if token.startswith("\\"):
            break
        if quoted_next:
            quoted_next = False
            continue
        tokens.append(token)
        if upper in {
            "'",
            "[']",
            "CHAR",
            "[CHAR]",
            "POSTPONE",
            "[COMPILE]",
            "[DEFINED]",
            "[UNDEFINED]",
        }:
            quoted_next = True
            continue
        if upper in {'S"', 'C"', '."', 'ABORT"'}:
            close = line.find('"', index)
            index = len(line) if close < 0 else close + 1
            continue
        if token == "(" or upper == ".(":
            close = line.find(")", index)
            index = len(line) if close < 0 else close + 1
            continue
    return tuple(tokens)


def _forth_line_contains_module_load(
    tokens: tuple[str, ...], command: str, module: str
) -> bool:
    """Find one module load using the guest's token and filename rules."""
    return any(
        tokens[index].upper() == command
        and tokens[index + 1].lower() == module.lower()
        for index in range(len(tokens) - 1)
    )


def _has_forth_conditional_token(text: str) -> bool:
    """Return whether MegaPad's raw conditional scanner observes a token."""
    return any(
        token.upper() in FORTH_CONDITIONAL_TOKENS
        for token in text.split(" ")
    )


def _compact_forth(
    text: str,
    *,
    remove_requires: bool = False,
    remove_stack_effects: bool = False,
) -> str:
    """Compact only syntax whose MegaPad interpretation is unambiguous.

    MegaPad separates source tokens on ASCII spaces. Its normal evaluator
    treats every token beginning with ``\\`` as an end-of-line comment, but
    conditional skip mode scans raw tokens without honoring comments or
    strings. Consequently full-line comments containing conditional-control
    tokens must remain in the linked source.

    Linked Akashic modules additionally drop a conventional flat stack-effect
    comment immediately after ``: name``. No inline comment is otherwise
    rewritten, so defining words and other source parsers need no host-side
    whitelist.
    """
    lines: list[str] = []
    for line in text.split("\n"):
        stripped = line.lstrip(" ")
        if not stripped:
            continue
        if stripped.startswith("\\"):
            if not _has_forth_conditional_token(stripped):
                continue
        if remove_requires and REQUIRE_RE.match(line):
            continue
        if remove_stack_effects:
            match = COLON_STACK_EFFECT_RE.match(line)
            if match and not _has_forth_conditional_token(
                match.group("effect")
            ):
                suffix = line[match.end() :].lstrip(" ")
                line = match.group("head")
                if suffix:
                    line += " " + suffix
        lines.append(line.lstrip(" "))
    return "".join(line + "\n" for line in lines)


def _minify_forth(text: str, *, remove_requires: bool = False) -> str:
    """Compact linked Akashic source without guessing parser-word input."""
    return _compact_forth(
        text,
        remove_requires=remove_requires,
        remove_stack_effects=True,
    )


def _strip_forth_noncode_lines(text: str) -> str:
    """Apply only blank-line, full-comment, and indentation compaction."""
    return _compact_forth(text)


def _coalesce_audited_forth_lines(
    source: bytes,
    maximum_bytes: int,
) -> bytes:
    """Join physical lines in a specifically audited Forth source closure.

    MegaPad evaluates each physical loader line through a 256-byte TIB, so
    generated lines may contain at most 255 source bytes.  A flat stack-effect
    comment immediately following a bare colon header is also redundant and
    removed.  Backslash comments consume the remainder of their input line,
    and delimiter parsers can do so when their closing delimiter is absent.
    Conditional tokens retain physical boundaries for the raw skip scanner,
    while PROVIDED must remain the first token on a line for KDOS's module
    pre-scan.  Those lines are therefore emitted unchanged and in isolation.

    This barrier set covers the built-in parsers used by the opted-in closure;
    it cannot infer arbitrary custom immediate words that observe an input-line
    boundary.  Callers must leave this transform disabled unless their complete
    source closure has been audited for that property.
    """
    if not 0 < maximum_bytes <= MEGAPAD_EVALUATE_SOURCE_MAX_BYTES:
        raise ValueError(
            "Linked Forth line limit must be between 1 and "
            f"{MEGAPAD_EVALUATE_SOURCE_MAX_BYTES} bytes"
        )

    output: list[bytes] = []
    current = bytearray()
    previous_tokens: tuple[str, ...] = ()

    def flush() -> None:
        if current:
            output.append(bytes(current))
            current.clear()

    for line in source.split(b"\n"):
        if not line:
            continue
        if len(line) > maximum_bytes:
            raise RuntimeError(
                f"Linked Forth source line exceeds {maximum_bytes} bytes"
            )
        text = line.decode("utf-8")
        tokens = tuple(token for token in text.split(" ") if token)
        if (
            len(previous_tokens) == 2
            and previous_tokens[0] == ":"
            and FORTH_SPLIT_STACK_EFFECT_RE.fullmatch(text)
            and not _has_forth_conditional_token(text)
        ):
            previous_tokens = tokens
            continue
        barrier = (
            any(token.startswith("\\") for token in tokens)
            or bool(tokens and tokens[0].upper() == "PROVIDED")
            or any(
                token.upper() in FORTH_LINE_COALESCE_BARRIERS
                for token in tokens
            )
        )
        if barrier:
            flush()
            output.append(line)
            previous_tokens = tokens
            continue

        separator = b" " if current else b""
        if len(current) + len(separator) + len(line) > maximum_bytes:
            flush()
            separator = b""
        current.extend(separator)
        current.extend(line)
        previous_tokens = tokens

    flush()
    return b"".join(line + b"\n" for line in output)
