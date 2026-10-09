#!/usr/bin/env python3
"""Canonical schema bytes, the JSON schema reader and sandbox schemas.

A Python reference reads the JSON form into canonical bytes
(docs/interop/schema-bytes.md).  The emulator must produce the same bytes,
refuse the same inputs with the same codes, refuse every noncanonical byte
variant, decode each document into a graph the JSON writer turns back into
the expected JSON, and digest it as hashlib does.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import Profile, PROFILES, build_image, smoke  # noqa: E402


# ---------------------------------------------------------------------
# Reference
# ---------------------------------------------------------------------

INVALID, TYPE, RANGE, DEPTH, CAPACITY, NOMEM, UNSUPPORTED = 1, 2, 3, 4, 5, 6, 7
B_INVALID, B_TYPE, B_DEPTH, B_CAPACITY = 1, 2, 3, 4

CELL_MIN, CELL_MAX = -(2 ** 63), 2 ** 63 - 1
MAX_DEPTH = 16
MAX_FIELDS = 256
JSON_MAX_CHILDREN = 64

NULL, BOOL, INT, F32, STRING, BYTES, LIST, MAP, RESOURCE = range(9)
NAMES = {"null": NULL, "boolean": BOOL, "integer": INT, "string": STRING,
         "array": LIST, "object": MAP}
SANDBOX_MASK = sum(1 << t for t in (NULL, BOOL, INT, STRING, BYTES, LIST, MAP))
LENGTH_TYPES = sum(1 << t for t in (STRING, BYTES, RESOURCE, LIST, MAP))
F_MIN, F_MAX, F_LEN, F_ITEM, F_FIELDS = 1, 2, 4, 8, 16
KNOWN = {"type", "minimum", "maximum", "maxLength", "maxItems",
         "maxProperties", "items", "properties", "required",
         "additionalProperties", "description"}
MAGIC = b"AKSCHEMA"


class Refused(Exception):
    def __init__(self, code: int) -> None:
        super().__init__(code)
        self.code = code


def le(n: int, width: int) -> bytes:
    return (n & ((1 << (8 * width)) - 1)).to_bytes(width, "little")


def is_int(v) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def decode_json(text: str):
    """JSON decoding as the interop codec does it."""
    def pairs(items):
        keys = [k for k, _ in items]
        if len(set(keys)) != len(keys):
            raise Refused(INVALID)
        return dict(items)
    try:
        value = json.loads(text, object_pairs_hook=pairs,
                           parse_float=lambda s: ("float", s))
    except json.JSONDecodeError:
        raise Refused(INVALID)

    def walk(v, depth):
        if depth >= MAX_DEPTH:
            raise Refused(DEPTH)
        if isinstance(v, tuple):
            raise Refused(UNSUPPORTED)
        if is_int(v) and not CELL_MIN <= v <= CELL_MAX:
            raise Refused(RANGE)
        if isinstance(v, (list, dict)):
            if len(v) > JSON_MAX_CHILDREN:
                raise Refused(CAPACITY)
            for child in (v.values() if isinstance(v, dict) else v):
                walk(child, depth + 1)
    walk(value, 0)
    return value


def type_mask(value) -> int:
    names = [value] if isinstance(value, str) else value
    if not isinstance(names, list) or not names:
        raise Refused(UNSUPPORTED)
    mask = 0
    for name in names:
        if not isinstance(name, str) or name not in NAMES:
            raise Refused(UNSUPPORTED)
        bit = 1 << NAMES[name]
        if mask & bit:
            raise Refused(UNSUPPORTED)
        mask |= bit
    return mask


def carried(mask, length, has_items, has_properties) -> bool:
    """JSON carries a container only within a known bound."""
    if mask & (1 << LIST):
        if length is None or length > JSON_MAX_CHILDREN:
            return False
        if not has_items and length != 0:
            return False
    if mask & (1 << MAP) and not has_properties and length != 0:
        return False
    return True


def read_node(v, depth: int) -> bytes:
    if depth >= MAX_DEPTH:
        raise Refused(DEPTH)
    if not isinstance(v, dict):
        raise Refused(TYPE)
    if any(k not in KNOWN for k in v):
        raise Refused(UNSUPPORTED)
    if "description" in v and not isinstance(v["description"], str):
        raise Refused(TYPE)
    if "type" not in v:
        raise Refused(UNSUPPORTED)
    mask = type_mask(v["type"])
    flags, tail = 0, b""
    bounds = {}
    for key, extreme, flag in (("minimum", CELL_MIN, F_MIN),
                               ("maximum", CELL_MAX, F_MAX)):
        if key in v:
            if not mask & (1 << INT) or not is_int(v[key]):
                raise Refused(TYPE)
            if v[key] != extreme:
                bounds[flag] = v[key]
                flags |= flag
    if F_MIN in bounds and F_MAX in bounds and bounds[F_MIN] > bounds[F_MAX]:
        raise Refused(TYPE)
    length, missing = None, 0
    for key, kind in (("maxLength", STRING), ("maxItems", LIST),
                      ("maxProperties", MAP)):
        allowed = mask & (1 << kind)
        if key not in v:
            missing += 1 if allowed else 0
            continue
        n = v[key]
        if not allowed or not is_int(n) or n < 0:
            raise Refused(TYPE)
        if length is not None and n != length:
            raise Refused(TYPE)
        length = n
    if length is not None and missing:
        raise Refused(TYPE)
    if length is not None:
        flags |= F_LEN
    items = v.get("items")
    if "items" in v:
        if not mask & (1 << LIST):
            raise Refused(TYPE)
        flags |= F_ITEM
    props = v.get("properties")
    required = v.get("required")
    if "properties" not in v:
        if "required" in v or "additionalProperties" in v:
            raise Refused(TYPE)
    else:
        if not mask & (1 << MAP) or "additionalProperties" not in v:
            raise Refused(TYPE)
        additional = v["additionalProperties"]
        if not isinstance(additional, bool):
            raise Refused(TYPE)
        if additional:
            raise Refused(UNSUPPORTED)
        if not isinstance(props, dict):
            raise Refused(TYPE)
        if not props:
            raise Refused(UNSUPPORTED)
        if len(props) > MAX_FIELDS:
            raise Refused(CAPACITY)
        if not isinstance(required, list):
            raise Refused(TYPE)
        seen = []
        for name in required:
            if not isinstance(name, str) or name not in props or name in seen:
                raise Refused(TYPE)
            seen.append(name)
        flags |= F_FIELDS
    if not carried(mask, length, "items" in v, "properties" in v):
        raise Refused(UNSUPPORTED)
    out = le(mask, 2) + bytes([flags, 0])
    if flags & F_MIN:
        out += le(bounds[F_MIN], 8)
    if flags & F_MAX:
        out += le(bounds[F_MAX], 8)
    if flags & F_LEN:
        out += le(length, 8)
    if flags & F_ITEM:
        out += read_node(items, depth + 1)
    if flags & F_FIELDS:
        out += le(len(props), 2)
        for key in sorted(props, key=lambda k: k.encode()):
            raw = key.encode()
            out += le(len(raw), 4) + raw + bytes([key in required])
            out += read_node(props[key], depth + 1)
    return out


def read(text: str) -> bytes:
    return MAGIC + read_node(decode_json(text), 0)


# The graph each document decodes to, for the writer's JSON.
def parse(doc: bytes):
    pos = len(MAGIC)

    def take(n):
        nonlocal pos
        chunk = doc[pos:pos + n]
        pos += n
        return chunk

    def signed(raw):
        return int.from_bytes(raw, "little", signed=True)

    def node():
        mask = int.from_bytes(take(2), "little")
        flags = take(2)[0]
        n = {"mask": mask}
        if flags & F_MIN:
            n["min"] = signed(take(8))
        if flags & F_MAX:
            n["max"] = signed(take(8))
        if flags & F_LEN:
            n["len"] = int.from_bytes(take(8), "little")
        if flags & F_ITEM:
            n["item"] = node()
        if flags & F_FIELDS:
            count = int.from_bytes(take(2), "little")
            fields = []
            for _ in range(count):
                size = int.from_bytes(take(4), "little")
                key = take(size).decode()
                required = take(1)[0]
                fields.append((key, required, node()))
            n["fields"] = fields
        return n
    return node()


def compatible(n, depth=0) -> bool:
    """IVJSON-SCHEMA-COMPATIBLE? for one decoded graph."""
    if depth >= MAX_DEPTH:
        return False
    mask = n["mask"]
    if mask & ((1 << F32) | (1 << BYTES)):
        return False
    if mask & (1 << LIST):
        if "len" not in n or n["len"] > JSON_MAX_CHILDREN:
            return False
        if "item" in n:
            if not compatible(n["item"], depth + 1):
                return False
        elif n["len"]:
            return False
    if mask & (1 << MAP):
        fields = n.get("fields", [])
        if not fields and ("len" not in n or n["len"]):
            return False
        if len(fields) > JSON_MAX_CHILDREN and (
                "len" not in n or n["len"] > JSON_MAX_CHILDREN):
            return False
        for _, _, schema in fields:
            if not compatible(schema, depth + 1):
                return False
    return True


WRITER_NAMES = {NULL: "null", BOOL: "boolean", INT: "integer",
                STRING: "string", LIST: "array", MAP: "object",
                RESOURCE: "string"}


def write(n) -> str:
    """The JSON the module's writer emits for one decoded graph."""
    mask = n["mask"]
    types = [WRITER_NAMES[t] for t in range(9)
             if mask & (1 << t)
             and not (t == RESOURCE and mask & (1 << STRING))]
    kind = json.dumps(types[0]) if len(types) == 1 else (
        "[" + ",".join(json.dumps(t) for t in types) + "]")
    # The writer emits keys as raw UTF-8.
    text = lambda k: json.dumps(k, ensure_ascii=False)
    parts = [f'"type":{kind}']
    if mask & (1 << INT):
        parts.append(f'"minimum":{n.get("min", CELL_MIN)}')
        parts.append(f'"maximum":{n.get("max", CELL_MAX)}')
    if "len" in n:
        if mask & (1 << LIST):
            parts.append(f'"maxItems":{n["len"]}')
        if mask & (1 << MAP):
            parts.append(f'"maxProperties":{n["len"]}')
        if mask & ((1 << STRING) | (1 << RESOURCE)):
            parts.append(f'"maxLength":{n["len"]}')
    if mask & (1 << LIST) and "item" in n:
        parts.append(f'"items":{write(n["item"])}')
    if mask & (1 << MAP) and n.get("fields"):
        props = ",".join(f"{text(k)}:{write(s)}"
                         for k, _, s in n["fields"])
        required = ",".join(text(k) for k, r, _ in n["fields"] if r)
        parts.append('"properties":{' + props + '}')
        parts.append('"required":[' + required + ']')
        parts.append('"additionalProperties":false')
    return "{" + ",".join(parts) + "}"


def digest(doc: bytes) -> bytes:
    return hashlib.sha3_256(b"akashic.sandbox.schema\x00" + doc).digest()


# ---------------------------------------------------------------------
# Cases
# ---------------------------------------------------------------------

def nest(depth: int) -> str:
    text = '{"type":"null"}'
    for _ in range(depth):
        text = '{"type":"array","items":' + text + ',"maxItems":1}'
    return text


GOOD = [
    '{"type":"null"}',
    '{"type":"boolean","description":"a flag"}',
    '{"type":"integer"}',
    '{"type":"integer","minimum":-5,"maximum":7}',
    '{"type":"integer","minimum":-9223372036854775808,'
    '"maximum":9223372036854775807}',
    '{"type":"integer","minimum":9223372036854775807}',
    '{"type":["integer"],"maximum":-9223372036854775808}',
    '{"type":"string","maxLength":0}',
    '{"type":["string","null"],"maxLength":64}',
    '{"type":"array","items":{"type":"string"},"maxItems":3}',
    '{"type":"array","maxItems":0}',
    '{"type":["array","object"],"maxItems":0,"maxProperties":0}',
    '{"type":"object","maxProperties":0}',
    '{"type":"array","items":{"type":"null"},"maxItems":64}',
    '{"type":"object","properties":{"z":{"type":"integer"},'
    '"a":{"type":"null"},"m":{"type":"boolean"}},'
    '"required":["m","z"],"additionalProperties":false}',
    '{"type":"object","properties":{"z":{"type":"null"},"é":'
    '{"type":"null"}},"required":[],"additionalProperties":false}',
    '{"type":"object","properties":{"":{"type":"string"}},'
    '"required":[""],"additionalProperties":false}',
    '{"type":"object","properties":{"inner":{"type":"object",'
    '"properties":{"b":{"type":"integer","minimum":0},"a":{"type":"array",'
    '"maxItems":5,"items":{"type":"object","properties":{"y":{"type":"null"},'
    '"x":{"type":"null"}},"required":["y"],"additionalProperties":false}}},'
    '"required":["a","b"],"additionalProperties":false},"after":'
    '{"type":"boolean"}},"required":["inner"],"additionalProperties":false}',
    '{"type":["null","boolean","integer","string","array","object"],'
    '"maxLength":0,"maxItems":0,"maxProperties":0}',
    # JSON counts every value's depth, so its deepest schema is 14 lists in.
    nest(MAX_DEPTH - 2),
]

BAD = [
    "{",
    '{"type":"integer","minimum":1.5}',
    '{"type":"integer","minimum":9223372036854775808}',
    '{"type":"object","properties":{"a":{"type":"null"},'
    '"a":{"type":"null"}},"required":[],"additionalProperties":false}',
    "[]",
    '{"type":"null","title":"x"}',
    '{"type":"null","description":7}',
    "{}",
    '{"type":"number"}',
    '{"type":[]}',
    '{"type":["null","null"]}',
    '{"type":["null",3]}',
    '{"type":7}',
    '{"type":"string","minimum":1}',
    '{"type":"integer","minimum":true}',
    '{"type":"integer","minimum":5,"maximum":4}',
    '{"type":"integer","maxLength":3}',
    '{"type":"string","maxLength":-1}',
    '{"type":["string","array"],"maxLength":3}',
    '{"type":["string","array"],"maxLength":3,"maxItems":4}',
    '{"type":"string","maxLength":"3"}',
    '{"type":"null","items":{"type":"null"}}',
    '{"type":"array","items":7}',
    '{"type":"array","items":{"type":"number"}}',
    '{"type":"object","required":[]}',
    '{"type":"object","additionalProperties":false}',
    '{"type":"null","properties":{"a":{"type":"null"}},"required":[],'
    '"additionalProperties":false}',
    '{"type":"object","properties":{"a":{"type":"null"}},"required":[]}',
    '{"type":"object","properties":{"a":{"type":"null"}},"required":[],'
    '"additionalProperties":0}',
    '{"type":"object","properties":{"a":{"type":"null"}},"required":[],'
    '"additionalProperties":true}',
    '{"type":"object","properties":[],"required":[],'
    '"additionalProperties":false}',
    '{"type":"object","properties":{},"required":[],'
    '"additionalProperties":false}',
    '{"type":"object","properties":{"a":{"type":"null"}},'
    '"additionalProperties":false}',
    '{"type":"object","properties":{"a":{"type":"null"}},"required":"a",'
    '"additionalProperties":false}',
    '{"type":"object","properties":{"a":{"type":"null"}},"required":["b"],'
    '"additionalProperties":false}',
    '{"type":"object","properties":{"a":{"type":"null"}},'
    '"required":["a","a"],"additionalProperties":false}',
    '{"type":"object","properties":{"a":{"type":"null"},"b":7},'
    '"required":[],"additionalProperties":false}',
    nest(MAX_DEPTH - 1),
    '{"type":"array"}',
    '{"type":"array","maxItems":1}',
    '{"type":"array","items":{"type":"null"},"maxItems":65}',
    '{"type":"object"}',
    '{"type":"object","maxProperties":1}',
]


def expected_bad(text: str) -> int:
    try:
        read(text)
    except Refused as refused:
        return refused.code
    raise AssertionError(text)


def node_bytes(mask, flags=0, rest=b"", reserved=0):
    return le(mask, 2) + bytes([flags, reserved]) + rest


INT_BIT = 1 << INT
NULL_NODE = node_bytes(1 << NULL)


def map_doc(*fields):
    out = le(len(fields), 2)
    for key, required, schema in fields:
        out += le(len(key), 4) + key + bytes([required]) + schema
    return MAGIC + node_bytes(1 << MAP, F_FIELDS, out)


def deep_items(depth):
    node = NULL_NODE
    for _ in range(depth):
        node = node_bytes(1 << LIST, F_ITEM, node)
    return MAGIC + node


# Byte documents MEASURE must refuse, with their codes.
REFUSED_BYTES = [
    (b"AKSCHEM", B_INVALID),
    (b"AKSCHEMB" + NULL_NODE, B_INVALID),
    (MAGIC + NULL_NODE[:3], B_INVALID),
    (MAGIC + NULL_NODE + b"\x00", B_INVALID),
    (MAGIC + node_bytes(0), B_INVALID),
    (MAGIC + node_bytes(1 << 9), B_INVALID),
    (MAGIC + node_bytes(1 << NULL, reserved=1), B_INVALID),
    (MAGIC + node_bytes(1 << NULL, 32), B_INVALID),
    (MAGIC + node_bytes(1 << STRING, F_MIN, le(1, 8)), B_INVALID),
    (MAGIC + node_bytes(INT_BIT, F_LEN, le(1, 8)), B_INVALID),
    (MAGIC + node_bytes(INT_BIT, F_ITEM, NULL_NODE), B_INVALID),
    (MAGIC + node_bytes(INT_BIT, F_FIELDS, le(0, 2)), B_INVALID),
    (MAGIC + node_bytes(INT_BIT, F_MIN, le(CELL_MIN, 8)), B_INVALID),
    (MAGIC + node_bytes(INT_BIT, F_MAX, le(CELL_MAX, 8)), B_INVALID),
    (MAGIC + node_bytes(INT_BIT, F_MIN | F_MAX, le(5, 8) + le(4, 8)),
     B_INVALID),
    (MAGIC + node_bytes(1 << STRING, F_LEN, le(-1, 8)), B_INVALID),
    (MAGIC + node_bytes(INT_BIT, F_MIN, le(1, 4)), B_INVALID),
    (MAGIC + node_bytes(1 << MAP, F_FIELDS, le(0, 2)), B_INVALID),
    (map_doc((b"b", 0, NULL_NODE), (b"a", 0, NULL_NODE)), B_INVALID),
    (map_doc((b"a", 0, NULL_NODE), (b"a", 0, NULL_NODE)), B_INVALID),
    (map_doc((b"\xff", 0, NULL_NODE)), B_INVALID),
    (map_doc((b"a", 2, NULL_NODE)), B_INVALID),
    (MAGIC + node_bytes(1 << MAP, F_FIELDS, le(MAX_FIELDS + 1, 2)),
     B_INVALID),
    (deep_items(MAX_DEPTH), B_DEPTH),
    (MAGIC + node_bytes(1 << F32), B_TYPE),
    (MAGIC + node_bytes(1 << RESOURCE), B_TYPE),
    (map_doc((b"a", 0, node_bytes(1 << F32))), B_TYPE),
]

# Canonical documents the JSON form cannot express.
EXTRA_GOOD = [
    MAGIC + node_bytes(1 << BYTES, F_LEN, le(9, 8)),
    deep_items(MAX_DEPTH - 1),
]


# ---------------------------------------------------------------------
# Forth fixture
# ---------------------------------------------------------------------

def hex_load(data: bytes) -> list[str]:
    text = data.hex()
    lines = ["_bx-begin"]
    lines += [f'S" {text[i:i + 96]}" _bx-add' for i in range(0, len(text), 96)]
    return lines + ["_bx-end"]


PRELUDE = r"""\ Generated: canonical schema bytes.
PROVIDED sbox-schema-bytes-tests

VARIABLE _sb-fails
VARIABLE _sb-checks
VARIABLE _sb-case
VARIABLE _sb-depth
VARIABLE _sb-ja
VARIABLE _sb-ju
VARIABLE _sb-ea
VARIABLE _sb-eu
VARIABLE _sb-wa
VARIABLE _sb-wu
VARIABLE _sb-da
VARIABLE _sb-out-u
VARIABLE _sb-store-u

CREATE _bx-pool 32768 ALLOT
VARIABLE _bx-top
VARIABLE _bx-start
CREATE _sb-out-raw 8192 ALLOT
CREATE _sb-store-raw 16384 15 + ALLOT
CREATE _sb-json 8192 ALLOT
CREATE _sb-digest 32 ALLOT
CREATE _sb-work-raw SBOX-DIGEST-WORKSPACE-SIZE 7 + ALLOT

: _sb-out  ( -- a ) _sb-out-raw ;
: _sb-store  ( -- a ) _sb-store-raw 7 + -8 AND ;
: _sb-work  ( -- a ) _sb-work-raw 7 + -8 AND ;

: _sb-assert  ( flag -- )
    1 _sb-checks +!
    0= IF
        1 _sb-fails +!
        ." SCHB ASSERT case " _sb-case @ . ." check " _sb-checks @ . CR
    THEN ;

: _bx-reset  ( -- ) 0 _bx-top ! ;
: _bx-begin  ( -- ) _bx-top @ _bx-start ! ;
: _hexval  ( c -- n )
    DUP [CHAR] a >= IF [CHAR] a - 10 + ELSE [CHAR] 0 - THEN ;
: _bx-add  ( c-addr u -- )
    2 / 0 ?DO
        DUP I 2 * + C@ _hexval 4 LSHIFT
        OVER I 2 * + 1+ C@ _hexval OR
        _bx-pool _bx-top @ + C!
        1 _bx-top +!
    LOOP DROP ;
: _bx-end  ( -- addr n )
    _bx-pool _bx-start @ + _bx-top @ _bx-start @ - ;

\ A document decodes into a graph the writer turns into EXPECTED JSON, and
\ its digest is DIGEST.
: _sb-decode-check  ( doc-a doc-u -- )
    2DUP SBCS-MEASURE 0= _sb-assert _sb-store-u !
    _sb-store-u @ 16384 <= _sb-assert
    2DUP _sb-store _sb-store-u @ 1- SBCS-DECODE
        CSB-E-CAPACITY = _sb-assert DROP
    2DUP _sb-store 4 + _sb-store-u @ SBCS-DECODE
        CSB-E-INVALID = _sb-assert DROP
    2DUP _sb-store _sb-store-u @ SBCS-DECODE 0= _sb-assert
    DUP CS-SCHEMA-VALIDATE 0= _sb-assert
    _sb-json 8192 CSJSON-ENCODE
    _sb-wu @ IF
        0= _sb-assert
        _sb-json SWAP _sb-wa @ _sb-wu @ COMPARE 0= _sb-assert
    ELSE
        \ The writer refuses what JSON cannot carry.
        IVJSON-E-UNSUPPORTED = _sb-assert DROP
    THEN
    _sb-digest _sb-work SBCS-DIGEST 0= _sb-assert
    _sb-digest 32 _sb-da @ 32 COMPARE 0= _sb-assert ;

\ JSON reads to EXPECTED bytes, which decode and digest as above.
: _sb-good  ( -- )
    _sb-ja @ _sb-ju @ _sb-out 8192 CSJSON-READ 0= _sb-assert
    DUP _sb-out-u !
    _sb-out SWAP _sb-ea @ _sb-eu @ COMPARE 0= _sb-assert
    \ The bytes are never longer than the JSON text plus the magic.
    _sb-out-u @ _sb-ju @ CSB-MAGIC-SIZE + <= _sb-assert
    \ One byte short of the result is a capacity failure.
    _sb-ja @ _sb-ju @ _sb-out _sb-out-u @ 1- CSJSON-READ
        IVJSON-E-CAPACITY = _sb-assert DROP
    _sb-out _sb-out-u @ _sb-decode-check ;

: _sb-bad  ( code -- )
    _sb-ja @ _sb-ju @ _sb-out 8192 CSJSON-READ
    ROT = _sb-assert 0= _sb-assert ;

: _sb-refused  ( code -- )
    _sb-ea @ _sb-eu @ SBCS-MEASURE ROT = _sb-assert 0= _sb-assert ;
"""

EPILOGUE = r"""
: _sb-finish  ( -- )
    0 _sb-case !
    DEPTH _sb-depth @ = _sb-assert
    _sb-fails @ IF
        ." SCHB FAIL " _sb-fails @ . ." / " _sb-checks @ . CR
    ELSE
        ." SCHB PASS " _sb-checks @ . CR
    THEN ;

_sb-finish
"""


def case(number: int, body: list[str]) -> list[str]:
    return (["MARKER _sb-mark", f": _sb-case-{number}  ( -- )",
             f"    {number} _sb-case ! _bx-reset"]
            + ["    " + line for line in body]
            + [";", f"_sb-case-{number}", "_sb-mark"])


def fixture() -> bytes:
    lines = [PRELUDE, "0 _sb-fails ! 0 _sb-checks ! DEPTH _sb-depth !"]
    number = 0
    for text in GOOD:
        number += 1
        doc = read(text)
        body = hex_load(text.encode())
        body += ["_sb-ju ! _sb-ja !"]
        body += hex_load(doc) + ["_sb-eu ! _sb-ea !"]
        body += hex_load(write(parse(doc)).encode()) + ["_sb-wu ! _sb-wa !"]
        body += hex_load(digest(doc)) + ["DROP _sb-da !", "_sb-good"]
        lines += case(number, body)
    for text in BAD:
        number += 1
        body = hex_load(text.encode()) + ["_sb-ju ! _sb-ja !",
                                          f"{expected_bad(text)} _sb-bad"]
        lines += case(number, body)
    for doc, code in REFUSED_BYTES:
        number += 1
        body = hex_load(doc) + ["_sb-eu ! _sb-ea !", f"{code} _sb-refused"]
        lines += case(number, body)
    for doc in EXTRA_GOOD:
        number += 1
        graph = parse(doc)
        body = (hex_load(write(graph).encode()) + ["_sb-wu ! _sb-wa !"]
                if compatible(graph) else ["0 _sb-wu !"])
        body += hex_load(digest(doc)) + ["DROP _sb-da !"]
        body += hex_load(doc) + ["_sb-decode-check"]
        lines += case(number, body)
    lines.append(EPILOGUE)
    return ("\n".join(lines) + "\n").encode()


def test_the_reference_matches_its_own_rules() -> None:
    assert read('{"type":"null"}') == MAGIC + bytes([1, 0, 0, 0])
    # Fields are ordered by raw UTF-8 bytes: "z" (0x7A) before "é" (0xC3).
    doc = read(next(t for t in GOOD if "\u00e9" in t))
    assert doc.index(b"z") < doc.index("é".encode())
    for text in GOOD:
        assert compatible(parse(read(text)))
    for text in BAD:
        expected_bad(text)


PROFILE_NAME = "sandbox-schema-bytes"


def test_schema_bytes_match_the_reference(tmp_path: Path) -> None:
    PROFILES[PROFILE_NAME] = Profile(
        roots=("interop/codecs/json-schema.f",
               "interop/codecs/sandbox-schema.f"),
        resources=(),
        autoexec=r"""\ autoexec.f - canonical schema bytes
ENTER-USERLAND
." [akashic] loading canonical schema bytes" CR TX-FLUSH
REQUIRE interop/codecs/json-schema.f
REQUIRE interop/codecs/sandbox-schema.f
REQUIRE local_testing/sbox-schb-test.f
""",
        ready_markers=("SCHB PASS",),
        stable_markers=("SCHB PASS",),
        failure_markers=(
            "SCHB FAIL",
            "SCHB ASSERT",
            "? (not found)",
            "Branch offset overflow",
            "dictionary full",
            "exception",
        ),
        linked=True,
        include_large_sample=False,
        initial_files=(("local_testing/sbox-schb-test.f", fixture()),),
    )
    image = build_image(PROFILE_NAME, tmp_path / "schema-bytes.img")
    assert smoke(
        PROFILE_NAME,
        image,
        cols=100,
        rows=30,
        max_steps=800_000_000,
        timeout=180.0,
    )
