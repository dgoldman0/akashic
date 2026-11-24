#!/usr/bin/env python3
"""Text maps (akashic/game/map.f).

A map is a UTF-8 text file: a header of `key: value` lines holding a
legend, then rows of glyphs.  A host reader below follows the same rules,
and the checks give the guest's reader maps from a seeded generator and
damaged copies of them, and expect each to answer as the host does: the
same three layers, spawns, legend and values, or the same refusal at the
same line.  Further checks name each refusal, load maps through places on
a RAM volume and on the MP64FS boot volume, and keep the heap flat over
repeated reads.  The checks run on native machines (native_forth.py).
"""
from __future__ import annotations

import random
import re
import sys

from toolchain.image.closure import dependency_order
from native_forth import (
    MEGAPAD_ROOT,
    SOURCE_ROOT,
    NativeForth,
    SharedMachine,
    load_sources,
    module_source,
)

sys.path.insert(0, str(MEGAPAD_ROOT))

from diskutil import MP64FS  # noqa: E402
from simulator.platform import create_address_space  # noqa: E402
from simulator.runtime import MegaForthRuntime  # noqa: E402
from simulator.storage import HostedStorageService  # noqa: E402

ROOTS = ("game/map.f", "utils/fs/place-replace.f")

# GMAP-S-* in game/map.f
(OK, MISSING, IO, NOMEM, UTF8, HEADER, SIZE, LEGEND, ROW,
 GLYPH) = range(10)
OPAQUE = 256

# =====================================================================
#  The host's reader
# =====================================================================

NAME = re.compile(rb"[A-Za-z0-9_-]+\Z")
NUMBER = re.compile(rb"[0-9]{1,18}\Z")


class Refused(Exception):
    def __init__(self, status: int, line: int) -> None:
        super().__init__(status, line)
        self.status, self.line = status, line


def lines_of(text: bytes) -> list[bytes]:
    """The text's lines, without their LF or a CR before it."""
    parts = text.split(b"\n")
    if parts and parts[-1] == b"":
        parts.pop()
    return [part[:-1] if part.endswith(b"\r") else part for part in parts]


def blank(line: bytes) -> bool:
    return line.strip(b" \t") == b""


def fields(value: bytes) -> list[bytes]:
    return [field for field in re.split(rb"[ \t]+", value) if field]


def glyph(field: bytes) -> str | None:
    text = field.decode("utf-8")
    return text if len(text) == 1 else None


def key_value(line: bytes) -> tuple[bytes, bytes] | None:
    if b":" not in line:
        return None
    key, value = line.split(b":", 1)
    if not NAME.match(key):
        return None
    return key, value.strip(b" \t")


def read_map(text: bytes) -> dict:
    """What GMAP-PARSE answers for TEXT, or Refused(status, line)."""
    lines = lines_of(text)
    if not text:
        raise Refused(HEADER, 1)
    # The first pass counts and checks each line's UTF-8 and form.
    rows_at = None
    for number, line in enumerate(lines, 1):
        try:
            line.decode("utf-8")
        except UnicodeDecodeError:
            raise Refused(UTF8, number)
        if blank(line):
            continue
        pair = key_value(line)
        if pair is None:
            raise Refused(HEADER, number)
        if pair[0] == b"rows":
            if pair[1]:
                raise Refused(HEADER, number)
            rows_at = number
            break
    if rows_at is None:
        raise Refused(HEADER, len(lines) + 1)
    # The second pass fills the legend and the values.
    tiles, marks, values = [], [], []
    size = {b"width": 0, b"height": 0}
    for number, line in enumerate(lines[:rows_at - 1], 1):
        if blank(line):
            continue
        key, value = key_value(line)
        taken = {t[0] for t in tiles} | {m[0] for m in marks}
        parts = fields(value) + [b""] * 4
        if key in (b"tile", b"spawn"):
            mark = key == b"spawn"
            if not mark and len(tiles) == 256:
                raise Refused(LEGEND, number)
            char = glyph(parts[0]) if parts[0] else None
            if char is None or char in taken:
                raise Refused(LEGEND, number)
            names = [m[1] for m in marks] if mark else [t[1] for t in tiles]
            if not NAME.match(parts[1]) or parts[1] in names:
                raise Refused(LEGEND, number)
            if mark:
                if parts[2] != b"on":
                    raise Refused(LEGEND, number)
                under = glyph(parts[3]) if parts[3] else None
                kinds = [t[0] for t in tiles]
                if under is None or under not in kinds:
                    raise Refused(LEGEND, number)
                if len(fields(value)) > 4:
                    raise Refused(LEGEND, number)
                marks.append((char, parts[1], kinds.index(under)))
            else:
                if not NUMBER.match(parts[2]) or int(parts[2]) > 255:
                    raise Refused(LEGEND, number)
                if parts[3] not in (b"clear", b"opaque"):
                    raise Refused(LEGEND, number)
                if len(fields(value)) > 4:
                    raise Refused(LEGEND, number)
                extra = int(parts[2]) | (OPAQUE if parts[3] == b"opaque" else 0)
                tiles.append((char, parts[1], extra))
            continue
        if key in [v[0] for v in values]:
            raise Refused(HEADER, number)
        if key in size:
            if not NUMBER.match(value) or int(value) == 0:
                raise Refused(SIZE, number)
            size[key] = int(value)
        values.append((key, value))
    w, h = size[b"width"], size[b"height"]
    if not w or not h:
        raise Refused(SIZE, rows_at)
    # The rows.
    tile_of = {t[0]: index for index, t in enumerate(tiles)}
    mark_of = {m[0]: index for index, m in enumerate(marks)}
    kinds, spawns = [], []
    for y in range(h):
        number = rows_at + 1 + y
        if number > len(lines):
            raise Refused(ROW, number)
        try:
            row = lines[number - 1].decode("utf-8")
        except UnicodeDecodeError:
            raise Refused(UTF8, number)
        for x in range(w):
            if x >= len(row):
                raise Refused(ROW, number)
            char = row[x]
            if char in tile_of:
                kinds.append(tile_of[char])
            elif char in mark_of:
                spawns.append((x, y, mark_of[char]))
                kinds.append(marks[mark_of[char]][2])
            else:
                raise Refused(GLYPH, number)
        if len(row) > w:
            raise Refused(ROW, number)
    for number in range(rows_at + h + 1, len(lines) + 1):
        if not blank(lines[number - 1]):
            raise Refused(ROW, number)
    return {
        "w": w, "h": h, "tiles": tiles, "marks": marks, "spawns": spawns,
        "values": values, "kinds": bytes(kinds),
        "cmap": bytes(tiles[k][2] & 255 for k in kinds),
        "sight": bytes(tiles[k][2] >> 8 for k in kinds),
    }


def answer(text: bytes) -> str:
    """The host's answer in the words the guest's PARSE. prints."""
    try:
        m = read_map(text)
    except Refused as refused:
        return f"{refused.status} {refused.line}"
    words = [OK, m["w"], m["h"], len(m["tiles"])]
    for char, name, extra in m["tiles"]:
        words += [ord(char), "x" + name.hex(), extra]
    words.append(len(m["marks"]))
    for char, name, under in m["marks"]:
        words += [ord(char), "x" + name.hex(), under]
    words.append(len(m["spawns"]))
    for spawn in m["spawns"]:
        words += list(spawn)
    words.append(len(m["values"]))
    for key, value in m["values"]:
        words += ["x" + key.hex(), "x" + value.hex()]
    words += ["x" + m[layer].hex() for layer in ("kinds", "cmap", "sight")]
    return " ".join(str(word) for word in words)


# =====================================================================
#  Maps from a seed
# =====================================================================

GLYPHS = list("#.=~,:;+*%&$!?^<>{}[]()|/abcdeghijkMNOPQRS0123456789") + [
    "█", "░", "▒", "·", "■", "Ω", "機",
    "\U0001f56f", "\U0001f4dc",
]
WORDS = ["floor", "shelf", "desk", "rug", "lamp-post", "door", "window",
         "stair_up", "archivist", "folio", "inkmite", "nest", "bell", "a1"]


def make_map(rng: random.Random) -> bytes:
    chars = rng.sample(GLYPHS, rng.randint(2, 12))
    n_tiles = rng.randint(1, len(chars) - 1)
    tile_chars, mark_chars = chars[:n_tiles], chars[n_tiles:]
    names = rng.sample(WORDS, len(WORDS))
    w, h = rng.randint(1, 30), rng.randint(1, 16)
    lines = []
    if rng.random() < 0.7:
        lines.append(f"name: Room {rng.randint(1, 999)}")
    header = [f"width: {w}", f"height: {h}"]
    for index, char in enumerate(tile_chars):
        sight = rng.choice(["clear", "opaque"])
        header.append(f"tile: {char} {names[index]}"
                      f"{rng.choice([' ', '  ', chr(9)])}{rng.randint(0, 255)} {sight}")
    for index, char in enumerate(mark_chars):
        under = rng.choice(tile_chars)
        header.append(f"spawn: {char} {names[index]} on {under}")
    if rng.random() < 0.5:
        header.append(f"turns: {rng.randint(10, 90)}")
    if rng.random() < 0.3:
        header.append("note:   lamps gutter at   dawn  ")
    # Keys stay in order where the tiles must precede the marks on them.
    lines += header[:2] + header[2:]
    if rng.random() < 0.3:
        lines.insert(rng.randint(0, len(lines)), "")
    lines.append("rows:")
    pool = tile_chars * 4 + mark_chars
    for _ in range(h):
        lines.append("".join(rng.choice(pool) for _ in range(w)))
    if rng.random() < 0.3:
        lines += ["", "  "]
    end = "\r\n" if rng.random() < 0.2 else "\n"
    text = end.join(lines)
    if rng.random() < 0.8:
        text += end
    return text.encode()


def damage(rng: random.Random, text: bytes) -> bytes:
    """A copy of TEXT with a byte, a character or a line changed."""
    lines = text.split(b"\n")
    choice = rng.randrange(7)
    if choice == 0:
        at = rng.randrange(len(text))
        return text[:at] + text[at + 1:]
    if choice == 1:
        at = rng.randrange(len(text) + 1)
        return text[:at] + rng.choice([b"#", b"Z", b" ", b":", b"\xc3", b"\xff"]) + text[at:]
    if choice == 2 and len(lines) > 1:
        at = rng.randrange(len(lines))
        return b"\n".join(lines[:at] + [lines[at]] + lines[at:])
    if choice == 3 and len(lines) > 1:
        at = rng.randrange(len(lines))
        return b"\n".join(lines[:at] + lines[at + 1:])
    if choice == 4 and len(lines) > 2:
        a, b = rng.sample(range(len(lines)), 2)
        lines[a], lines[b] = lines[b], lines[a]
        return b"\n".join(lines)
    if choice == 5:
        return text.replace(b"clear", b"clean", 1).replace(b" on ", b" in ", 1)
    at = rng.randrange(len(text))
    return text[:at] + bytes([rng.randrange(256)]) + text[at + 1:]


# =====================================================================
#  The guest
# =====================================================================

PRINT = (
    'VARIABLE M  VARIABLE TX-LEN  VARIABLE X0  CREATE TX 65536 ALLOT',
    '0 TX-LEN !',
    ': HX-DIGIT  ( c -- n )  DUP 97 >= IF 87 - ELSE 48 - THEN ;',
    ': HX+  ( a u -- )',
    '    0 ?DO',
    '        DUP I + C@ HX-DIGIT 4 LSHIFT  OVER I + 1+ C@ HX-DIGIT OR',
    '        TX TX-LEN @ + C!  1 TX-LEN +!',
    '    2 +LOOP DROP ;',
    ': TEXT  ( -- a u )  TX TX-LEN @  0 TX-LEN ! ;',
    ': H1  ( n -- )  DUP 10 < IF 48 ELSE 87 THEN + EMIT ;',
    ': H2  ( c -- )  DUP 4 RSHIFT H1 15 AND H1 ;',
    ': HX.  ( a u -- )  ." x" 0 ?DO DUP I + C@ H2 LOOP DROP SPACE ;',
    ': LAYER.  ( cmap -- )  DUP CMAP-DATA SWAP DUP CMAP-W SWAP CMAP-H * HX. ;',
    ': MAP.  ( map -- )',
    '    DUP GMAP-W . DUP GMAP-H .',
    '    DUP GMAP-TILES DUP . 0 ?DO DUP I GMAP-TILE-GLYPH .',
    '        DUP I GMAP-TILE-NAME HX.  DUP I _GMAP-TILE-ENTRY 24 + @ . LOOP',
    '    DUP GMAP-MARKS DUP . 0 ?DO DUP I GMAP-MARK-GLYPH .',
    '        DUP I GMAP-MARK-NAME HX.  DUP I GMAP-MARK-TILE . LOOP',
    '    DUP GMAP-SPAWNS DUP . 0 ?DO DUP I GMAP-SPAWN@ ROT . SWAP . . LOOP',
    '    DUP _GMAP-O-NVALUES + @ DUP . 0 ?DO',
    '        DUP _GMAP-O-VALUES + @ I _GMAP-ENTRY-SZ * +',
    '        DUP @ OVER 8 + @ HX.  DUP 16 + @ SWAP 24 + @ HX. LOOP',
    '    DUP GMAP-KINDS LAYER.  DUP GMAP-CMAP LAYER.  GMAP-SIGHT LAYER. ;',
    ': ANSWER.  ( map status -- )',
    '    DUP . IF DROP GMAP-WHERE . EXIT THEN DUP MAP. GMAP-FREE ;',
    ': PARSE.  ( -- )  TEXT GMAP-PARSE ANSWER. ;',
)

SUITE = NativeForth(("game/map.f",), prelude=PRINT)


def text_lines(data: bytes) -> list[str]:
    hexed = data.hex()
    return [f'S" {hexed[at:at + 128]}" HX+' for at in range(0, len(hexed), 128)]


def words(raw: bytes) -> str:
    text = "".join(chr(b) if 0x20 <= b < 0x7F or b in (10, 13, 9) else ""
                   for b in raw)
    assert "RESULT:" in text, text[-600:]
    tail = text.rsplit("RESULT:", 1)[1]
    assert "??" not in tail, tail[-600:]
    return " ".join(tail.split()).lower()


def parse_all(suite, texts, max_steps=4_000_000_000) -> list[str]:
    lines = []
    for index, text in enumerate(texts):
        lines += [f'." |{index} "', *text_lines(text), "PARSE."]
    got = words(suite.run(['." RESULT: "', *lines, 'CR'], max_steps))
    answers = [part.split(" ", 1)[1].strip() if " " in part.strip() else ""
               for part in got.split("|")[1:]]
    assert len(answers) == len(texts), (len(answers), len(texts))
    return answers


EXAMPLE = (
    "name: The Bindery\n"
    "width: 6\n"
    "height: 3\n"
    "tile: . floor 0 clear\n"
    "tile: # shelf 1 opaque\n"
    "spawn: @ archivist on .\n"
    "spawn: f folio on .\n"
    "rows:\n"
    "######\n"
    "#@.f.#\n"
    "######\n"
).encode()


def test_the_example_map_reads_as_its_text_says():
    """The module header's example: two tiles and two marks, the shelf
    blocking movement and sight, the archivist and a folio standing on
    floor, and a name the game reads."""
    (got,) = parse_all(SUITE, [EXAMPLE])
    assert got == answer(EXAMPLE), got
    assert got.startswith("0 6 3 2 46 x666c6f6f72 0 35 x7368656c66 257 "), got
    assert " 2 1 1 0 3 1 1 " in got, got


def test_maps_from_a_seed_read_as_the_host_reads_them():
    """Sixty maps from a seeded generator, with legends of up to twelve
    glyphs, three of them multibyte, CRLF and LF ends, blank lines and
    values with spaces inside, each read the same by guest and host."""
    rng = random.Random(20261123)
    texts = [make_map(rng) for _ in range(60)]
    for text, got in zip(texts, parse_all(SUITE, texts)):
        assert got == answer(text).lower(), (text, got)
        assert got.startswith("0 "), (text, got)


def test_damaged_maps_are_refused_where_the_host_refuses_them():
    """Three hundred damaged copies of seeded maps: a byte or character
    removed, added or replaced, a line doubled, dropped or moved, or a
    legend word misspelt.  Each answers what the host answers, the same
    refusal at the same line or the same map."""
    rng = random.Random(1123)
    texts = []
    for _ in range(300):
        texts.append(damage(rng, make_map(rng)))
    refused = 0
    for text, got in zip(texts, parse_all(SUITE, texts)):
        want = answer(text).lower()
        assert got == want, (text, got, want)
        refused += not want.startswith("0 ")
    assert 150 < refused < 300, refused


REFUSALS = [
    (b"", HEADER, 1),
    (b"width: 2\nheight: 1\ntile: . floor 0 clear\n..\n", HEADER, 4),
    (b"width: 2\nheight: 1\ntile: . floor 0 clear\n", HEADER, 4),
    (b"width 2\n", HEADER, 1),
    (b"wid th: 2\n", HEADER, 1),
    (b"width: 2\nwidth: 3\nrows:\n", HEADER, 2),
    (b"rows: 4\n", HEADER, 1),
    (b"name: caf\xc3\n", UTF8, 1),
    (b"height: 1\ntile: . floor 0 clear\nrows:\n.\n", SIZE, 3),
    (b"width: 0\nheight: 1\nrows:\n", SIZE, 1),
    (b"width: two\nheight: 1\nrows:\n", SIZE, 1),
    (b"width: 1\nheight: 1\ntile: . floor 256 clear\nrows:\n.\n", LEGEND, 3),
    (b"width: 1\nheight: 1\ntile: . floor 0 misty\nrows:\n.\n", LEGEND, 3),
    (b"width: 1\nheight: 1\ntile: .. floor 0 clear\nrows:\n.\n", LEGEND, 3),
    (b"width: 1\nheight: 1\ntile: . floor 0 clear extra\nrows:\n.\n",
     LEGEND, 3),
    (b"width: 1\nheight: 1\ntile: . floor 0 clear\ntile: . rug 0 clear\n"
     b"rows:\n.\n", LEGEND, 4),
    (b"width: 1\nheight: 1\ntile: . floor 0 clear\ntile: , floor 0 clear\n"
     b"rows:\n.\n", LEGEND, 4),
    (b"width: 1\nheight: 1\nspawn: @ hero on .\ntile: . floor 0 clear\n"
     b"rows:\n.\n", LEGEND, 3),
    (b"width: 1\nheight: 1\ntile: . floor 0 clear\nspawn: @ hero at .\n"
     b"rows:\n.\n", LEGEND, 4),
    (b"width: 1\nheight: 1\ntile: . fl@or 0 clear\nrows:\n.\n", LEGEND, 3),
    (b"width: 2\nheight: 2\ntile: . floor 0 clear\nrows:\n..\n.\n", ROW, 6),
    (b"width: 2\nheight: 2\ntile: . floor 0 clear\nrows:\n..\n...\n", ROW, 6),
    (b"width: 2\nheight: 2\ntile: . floor 0 clear\nrows:\n..\n", ROW, 6),
    (b"width: 2\nheight: 1\ntile: . floor 0 clear\nrows:\n..\n..\n", ROW, 6),
    (b"width: 2\nheight: 1\ntile: . floor 0 clear\nrows:\n.#\n", GLYPH, 5),
    (b"width: 2\nheight: 1\ntile: . floor 0 clear\nrows:\n.\xff\n", UTF8, 5),
]


def test_each_refusal_names_its_cause_and_line():
    """Each kind of refusal on a map made to show it, with the line a
    person editing the map in Pad would look at."""
    texts = [text for text, _, _ in REFUSALS]
    for (text, status, line), got in zip(REFUSALS, parse_all(SUITE, texts)):
        assert got == f"{status} {line}", (text, got)
        assert answer(text) == got, (text, answer(text))


def many_kinds(count: int) -> bytes:
    """A 16 by 16 map whose legend declares COUNT tile kinds and whose
    rows show the first 256, one a tile."""
    lines = ["width: 16", "height: 16"]
    lines += [f"tile: {chr(0x4E00 + kind)} k{kind} {kind % 7} clear"
              for kind in range(count)]
    lines.append("rows:")
    lines += ["".join(chr(0x4E00 + 16 * y + x) for x in range(16))
              for y in range(16)]
    return ("\n".join(lines) + "\n").encode()


def test_a_legend_holds_256_tile_kinds_and_refuses_more():
    """The kind layer holds a byte a tile, so a map declares at most 256
    tile kinds: 256 read, each tile its own kind, and a 257th tile line
    is refused where it stands."""
    full, over = many_kinds(256), many_kinds(257)
    got = parse_all(SUITE, [full, over])
    assert got[0] == answer(full).lower(), got[0][:200]
    assert f" x{bytes(range(256)).hex()} " in got[0]
    assert got[1] == f"{LEGEND} 259" == answer(over), got[1]


def test_repeated_reads_keep_the_heap_flat():
    """Ten more reads and frees of a seeded map after the first leave the
    extended heap where the first left it, and so do ten more refusals of
    a damaged copy after its first."""
    text = make_map(random.Random(5))
    damaged = text.replace(b"rows:", b"rows: x")
    lines = []
    for name, data in (("GOOD", text), ("BAD", damaged)):
        lines += [*text_lines(data),
                  f"CREATE {name} {len(data)} ALLOT  TX {name} {len(data)} CMOVE"
                  "  0 TX-LEN !",
                  f": {name}!  {name} TX {len(data)} CMOVE  {len(data)} TX-LEN ! ;"]
    lines += [": ONE  ( -- status )  TEXT GMAP-PARSE ?DUP IF NIP ELSE GMAP-FREE 0 THEN ;",
              "VARIABLE AGAIN",
              ": TEN  ( xt -- statuses growth )",
              "    AGAIN !  AGAIN @ EXECUTE ONE DROP  XMEM-HERE @ X0 !",
              "    0 10 0 DO AGAIN @ EXECUTE ONE OR LOOP  XMEM-HERE @ X0 @ - ;",
              "' GOOD! TEN . .  ' BAD! TEN . ."]
    got = words(SUITE.run(['." RESULT: "', *lines, 'CR'], 4_000_000_000))
    assert got == f"0 0 0 {HEADER}", got


# =====================================================================
#  Maps through places
# =====================================================================

PLACES = PRINT + (
    'VARIABLE VA  VARIABLE PVA  VARIABLE D-HOME  VARIABLE SET',
    'VARIABLE P-HOME  VARIABLE P-RO  VARIABLE REPL',
    ': T-SETUP  ( -- )',
    '    1048576 A-XMEM ARENA-NEW IF -1 THROW THEN',
    '    VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN VA !',
    '    S" game" VA @ VFS-MKDIR THROW',
    '    S" va" PLACES-VOLUME THROW PVA !  VA @ PVA @ PVOL-ATTACH THROW',
    '    S" game" S" /game" PLACE-WRITABLE PVA @ PLACES-DECLARE THROW D-HOME !',
    '    PLSET-NEW THROW SET !',
    '    PLACE-WRITABLE D-HOME @ SET @ PLSET-GRANT THROW P-HOME !',
    '    PLSET-NEW THROW >R',
    '    PLACE-READ-ONLY D-HOME @ R> PLSET-GRANT THROW P-RO !',
    '    VREPL-SIZE ALLOCATE THROW DUP VREPL-SIZE 0 FILL REPL ! ;',
    'T-SETUP',
    ': PUT  ( path-a path-u -- )',
    '    P-HOME @ -1 REPL @ PLACE-VREPL! THROW',
    '    TEXT REPL @ VREPL-REPLACE THROW ;',
)

PLACE_SUITE = NativeForth(ROOTS, prelude=PLACES)


def test_a_map_loads_through_a_place():
    """A map file in a home loads through the writable grant and through
    a read-only one, as an applet's origin is granted; a missing file and
    an empty one are refused."""
    lines = [*text_lines(EXAMPLE), 'S" /bindery.map" PUT',
             'S" /bindery.map" P-HOME @ GMAP-LOAD ANSWER.',
             'S" /bindery.map" P-RO @ GMAP-LOAD ANSWER.',
             'S" /none.map" P-RO @ GMAP-LOAD . .',
             'S" /empty.map" PUT',
             'S" /empty.map" P-RO @ GMAP-LOAD ANSWER.']
    got = words(PLACE_SUITE.run(['." RESULT: "', *lines, 'CR'], 400_000_000))
    want = answer(EXAMPLE)
    assert got == f"{want} {want} {MISSING} 0 {HEADER} 1".lower(), got


BOOT_HELPERS = PRINT + (
    ': T-BOOT  ( -- place )',
    '    S" boot" PLACES-VOLUME THROW',
    '    >R S" maps" S" /maps" PLACE-READ-ONLY R> PLACES-DECLARE THROW',
    '    PLSET-NEW THROW PLACE-READ-ONLY -ROT PLSET-GRANT THROW ;',
)


def test_a_shipped_map_loads_from_the_mp64fs_boot_volume():
    """A map the build put on the MP64FS boot volume loads through a
    read-only place over its folder, as an applet's origin there does."""
    fs = MP64FS(total_sectors=2048)
    fs.format()
    fs.mkdir("/maps")
    fs.inject_file("bindery.map", EXAMPLE, path="/maps")
    storage = HostedStorageService(bytes(fs.img))
    runtime = MegaForthRuntime(
        memory=create_address_space(external_size=128 << 20,
                                    hbw_size=1 << 20),
        execution_backend="native",
        storage=storage,
    )
    sources = [("kdos.f", (MEGAPAD_ROOT / "kdos.f").read_bytes()),
               ("userland", b"ENTER-USERLAND\n")]
    roots = ("game/map.f", "tui/platform/mp64fs-vfs.f")
    sources += [(module, module_source(SOURCE_ROOT / module))
                for module in dependency_order(SOURCE_ROOT, roots)]
    sources.append(("prelude", ("\n".join(BOOT_HELPERS) + "\n").encode()))
    load_sources(runtime, sources, 800_000_000)
    got = words(SharedMachine(runtime).run(
        ['." RESULT: "', 'S" /bindery.map" T-BOOT GMAP-LOAD ANSWER.', 'CR'],
        400_000_000))
    assert got == answer(EXAMPLE).lower(), got
