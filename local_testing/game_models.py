"""Host models of the game library's logic, for its suites to check against.

Each model states what a module must compute, independently of the Forth
that computes it.  A suite generates Forth that runs the module on the same
inputs, prints the results in a fixed line format, and compares them with
the model's.

Behaviour trees: ``bt_trees`` builds fixed and seeded random trees,
``bt_forth`` emits Forth that builds each tree, runs it for two entities
over several ticks and frees it inside a memory log, and ``bt_check``
compares the transcript with the model.  A leaf's status is a function of
its id, the entity and the tick, which the Forth passes as BT-RUN's ecs
argument, so the model knows what every leaf returns.

Fog of war: ``shadowcast`` is symmetric shadowcasting with exact rational
slopes, after Albert Ford's description of the algorithm, limited to a
radius, with every tile beyond the map's edge blocking sight and never
lit.  ``fog_maps`` makes the fixed maps of the plan's probe and seeded
random maps, ``fog_forth`` emits Forth that reveals three viewers into one
fog on each map, two before a hide and one after, and prints the layer
after each, and ``fog_check`` compares the layers with the oracle.
"""

from __future__ import annotations

import math
import random
from fractions import Fraction
from dataclasses import dataclass, field

SUCCESS, FAILURE, RUNNING = 0, 1, 2


# ── Behaviour trees ──────────────────────────────────────────────


@dataclass
class BtNode:
    kind: str                       # action condition sequence selector
                                    # parallel invert repeat cooldown
    children: list["BtNode"] = field(default_factory=list)
    arg: int = 0                    # repeat n, cooldown ticks, threshold
    leaf: int = -1                  # leaf id


def bt_leaf_status(leaf: int, eid: int, tick: int) -> int:
    return (leaf * 5 + eid * 3 + tick * 7 + leaf * tick) % 3


def bt_condition_flag(leaf: int, eid: int, tick: int) -> bool:
    return (leaf * 3 + eid + tick * 5) % 2 == 0


def bt_cells(node: BtNode) -> int:
    own = {"repeat": 1, "cooldown": 2}.get(node.kind, 0)
    return own + sum(bt_cells(child) for child in node.children)


def bt_run(node: BtNode, state: list[int], at: int, eid: int, tick: int,
           trace: list[int]) -> int:
    """The status of NODE, whose cells start at STATE[AT]."""
    kind = node.kind
    if kind == "action":
        trace.append(node.leaf)
        return bt_leaf_status(node.leaf, eid, tick)
    if kind == "condition":
        trace.append(node.leaf)
        return SUCCESS if bt_condition_flag(node.leaf, eid, tick) else FAILURE
    if kind in ("sequence", "selector"):
        go = SUCCESS if kind == "sequence" else FAILURE
        offset = at
        for child in node.children:
            status = bt_run(child, state, offset, eid, tick, trace)
            if status != go:
                return status
            offset += bt_cells(child)
        return go
    if kind == "parallel":
        succeeded = failed = 0
        offset = at
        for child in node.children:
            status = bt_run(child, state, offset, eid, tick, trace)
            if status == SUCCESS:
                succeeded += 1
            elif status == FAILURE:
                failed += 1
            offset += bt_cells(child)
        if succeeded >= node.arg:
            return SUCCESS
        if failed > len(node.children) - node.arg:
            return FAILURE
        return RUNNING
    child = node.children[0]
    if kind == "invert":
        status = bt_run(child, state, at, eid, tick, trace)
        return {SUCCESS: FAILURE, FAILURE: SUCCESS}.get(status, status)
    if kind == "repeat":
        status = bt_run(child, state, at + 1, eid, tick, trace)
        if status == SUCCESS:
            if node.arg == 0:
                return RUNNING
            done = state[at] + 1
            if done >= node.arg:
                state[at] = 0
                return SUCCESS
            state[at] = done
            return RUNNING
        if status == FAILURE:
            state[at] = 0
        return status
    if kind == "cooldown":
        if state[at] > 0:
            state[at] -= 1
            return state[at + 1]
        status = bt_run(child, state, at + 2, eid, tick, trace)
        if status != RUNNING:
            state[at + 1] = status
            state[at] = node.arg
        return status
    raise ValueError(kind)


def bt_blocks(node: BtNode) -> int:
    """Heap blocks a built tree holds: each node and each children array."""
    own = 1
    if node.kind in ("sequence", "selector", "parallel") and node.children:
        own += 1
    return own + sum(bt_blocks(child) for child in node.children)


class _Leaves:
    def __init__(self) -> None:
        self.next = 0

    def take(self, kind: str) -> BtNode:
        self.next += 1
        return BtNode(kind, leaf=self.next)


def _bt_random(rng: random.Random, leaves: _Leaves, depth: int) -> BtNode:
    if depth >= 4 or rng.random() < 0.25 + 0.18 * depth:
        return leaves.take("action" if rng.random() < 0.7 else "condition")
    kind = rng.choice(["sequence", "selector", "parallel", "invert",
                       "repeat", "cooldown", "sequence", "selector"])
    if kind in ("invert", "repeat", "cooldown"):
        arg = {"invert": 0, "repeat": rng.randint(0, 3),
               "cooldown": rng.randint(1, 3)}[kind]
        return BtNode(kind, [_bt_random(rng, leaves, depth + 1)], arg)
    count = rng.choice([0, 1, 2, 2, 3, 3])
    children = [_bt_random(rng, leaves, depth + 1) for _ in range(count)]
    arg = rng.randint(0, count + 1) if kind == "parallel" else 0
    return BtNode(kind, children, arg)


def bt_trees(seed: int = 20261123, count: int = 40) -> list[BtNode]:
    """The fixed nested shapes, then COUNT seeded random trees."""
    leaves = _Leaves()

    def a() -> BtNode:
        return leaves.take("action")

    def c() -> BtNode:
        return leaves.take("condition")

    fixed = [
        # a selector inside a sequence inside a selector
        BtNode("selector", [
            BtNode("sequence", [BtNode("selector", [a(), c()]), a()]), a()]),
        # a repeat over a cooldown, and a repeat over a repeat
        BtNode("repeat", [BtNode("cooldown", [a()], 2)], 3),
        BtNode("repeat", [BtNode("repeat", [a()], 2)], 2),
        # a parallel of composites
        BtNode("parallel", [BtNode("sequence", [a(), a()]),
                            BtNode("selector", [c(), a()]),
                            BtNode("invert", [a()])], 2),
        # stateful nodes on both sides of a composite
        BtNode("sequence", [BtNode("cooldown", [a()], 1),
                            BtNode("selector", [BtNode("repeat", [a()], 2), a()]),
                            BtNode("cooldown", [BtNode("invert", [c()])], 2)]),
    ]
    rng = random.Random(seed)
    return fixed + [_bt_random(rng, leaves, 0) for _ in range(count)]


def _bt_leaves(node: BtNode) -> list[BtNode]:
    if node.kind in ("action", "condition"):
        return [node]
    return [leaf for child in node.children for leaf in _bt_leaves(child)]


def _bt_build(node: BtNode) -> str:
    kind = node.kind
    if kind == "action":
        return f"' _BTL{node.leaf} BT-ACTION"
    if kind == "condition":
        return f"' _BTL{node.leaf} BT-CONDITION"
    if kind in ("invert", "repeat", "cooldown"):
        inner = _bt_build(node.children[0])
        if kind == "invert":
            return f"{inner} BT-INVERT"
        word = "BT-REPEAT" if kind == "repeat" else "BT-COOLDOWN"
        return f"{inner} {node.arg} {word}"
    parts = [_bt_build(child) for child in node.children]
    packed = f"{len(node.children)} _BTPACK"
    word = {"sequence": "BT-SEQUENCE", "selector": "BT-SELECTOR",
            "parallel": f"{node.arg} BT-PARALLEL"}[kind]
    return " ".join(parts + [packed, word])


BT_FORTH_SUPPORT = r"""
\ ── Behaviour trees against the host model ─────────────────────
\ A leaf logs its id and returns a status computed from its id, the
\ entity and the tick, which the trial passes as BT-RUN's ecs.
256 CELLS ALLOCATE DROP CONSTANT _BTT
VARIABLE _BTT-N
: _BTT-RESET  ( -- )  0 _BTT-N ! ;
: _BTT-LOG  ( id -- )
    _BTT-N @ 256 < IF _BTT _BTT-N @ CELLS + !  1 _BTT-N +! ELSE DROP THEN ;
: _BTT.  ( -- )  _BTT-N @ 0 ?DO _BTT I CELLS + @ . LOOP ;
: _BT-LEAF  ( eid tick id -- status )
    DUP _BTT-LOG
    >R  R@ 5 *  ROT 3 * +  OVER 7 * +  SWAP R> * +  3 MOD ;
: _BT-COND  ( eid tick id -- flag )
    DUP _BTT-LOG  3 *  ROT +  SWAP 5 * +  2 MOD 0= ;
64 CELLS ALLOCATE DROP CONSTANT _BTB
: _BTPACK  ( c1 .. cn n -- children n )
    DUP BEGIN DUP 0> WHILE 1- ROT OVER CELLS _BTB + ! REPEAT DROP
    _BTB SWAP ;
VARIABLE _BTR  VARIABLE _BTS1  VARIABLE _BTS2
: _BT-STATE-NEW  ( cells -- state|0 )
    ?DUP IF CELLS DUP ALLOCATE 0<> ABORT" BT test: state"
        TUCK SWAP 0 FILL ELSE 0 THEN ;
: _BT-STATE-OF  ( eid -- state )  1 = IF _BTS1 @ ELSE _BTS2 @ THEN ;
: _BT-TRIAL  ( id ticks -- )
    SWAP ." BTS: " . _BTR @ BT-STATE-CELLS . CR
    0 ?DO
        3 1 DO
            _BTT-RESET
            _BTR @ I _BT-STATE-OF I J BT-RUN
            ." BT: " J . I . . ." | " _BTT. CR
        LOOP
    LOOP ;
"""


def bt_forth(trees: list[BtNode], ticks: int = 12) -> str:
    """Forth that runs each tree for entities 1 and 2 over TICKS ticks."""
    lines = [BT_FORTH_SUPPORT, "DEPTH CONSTANT _BT-DEPTH0"]
    for tree in trees:
        for leaf in _bt_leaves(tree):
            if leaf.kind == "action":
                lines.append(f": _BTL{leaf.leaf} ( eid tick -- status ) "
                             f"{leaf.leaf} _BT-LEAF ;")
            else:
                lines.append(f": _BTL{leaf.leaf} ( eid tick -- flag ) "
                             f"{leaf.leaf} _BT-COND ;")
    for number, tree in enumerate(trees):
        lines += [
            "-1 MLOG-HOLD  MLOG-START",
            f"{_bt_build(tree)} _BTR !",
            "_BTR @ BT-STATE-CELLS _BT-STATE-NEW _BTS1 !",
            "_BTR @ BT-STATE-CELLS _BT-STATE-NEW _BTS2 !",
            f"{number} {ticks} _BT-TRIAL",
            "_BTR @ BT-FREE  _BTS1 @ FREE  _BTS2 @ FREE",
            "MLOG-STOP  0 MLOG-HOLD",
            f'." BTM: " {number} . MLOG-BALANCED? . MLOG-FREES . '
            f'DEPTH _BT-DEPTH0 - . CR',
        ]
    return "\n".join(lines) + "\n"


def bt_check(text: str, trees: list[BtNode], ticks: int = 12) -> list[str]:
    """Differences between the transcript and the model; empty when none."""
    problems: list[str] = []
    runs: dict[int, list[tuple[int, int, int, list[int]]]] = {}
    cells: dict[int, int] = {}
    memory: dict[int, tuple[int, int, int]] = {}
    current = None
    for line in text.splitlines():
        try:
            if line.startswith("BTS: "):
                number, count = (int(x) for x in line[5:].split())
                cells[number] = count
                runs[number] = []
                current = number
            elif line.startswith("BT: ") and current is not None:
                head, _, trace = line[4:].partition("|")
                tick, eid, status = (int(x) for x in head.split())
                runs[current].append((tick, eid, status,
                                      [int(x) for x in trace.split()]))
            elif line.startswith("BTM: "):
                number, balanced, frees, depth = (
                    int(x) for x in line[5:].split())
                memory[number] = (balanced, frees, depth)
        except ValueError:
            problems.append(f"unreadable line: {line!r}")
    for number, tree in enumerate(trees):
        if number not in runs:
            problems.append(f"tree {number}: no trial in the transcript")
            continue
        want_cells = bt_cells(tree)
        if cells[number] != want_cells:
            problems.append(f"tree {number}: {cells[number]} state cells, "
                            f"model {want_cells}")
        states = {1: [0] * want_cells, 2: [0] * want_cells}
        expected = []
        for tick in range(ticks):
            for eid in (1, 2):
                trace: list[int] = []
                status = bt_run(tree, states[eid], 0, eid, tick, trace)
                expected.append((tick, eid, status, trace))
        if runs[number] != expected:
            for got, want in zip(runs[number], expected):
                if got != want:
                    problems.append(f"tree {number}: tick {want[0]} entity "
                                    f"{want[1]}: got {got[2:]} model {want[2:]}")
                    break
            else:
                problems.append(f"tree {number}: {len(runs[number])} runs, "
                                f"model {len(expected)}")
        blocks = bt_blocks(tree) + (2 if want_cells else 0)
        balanced, frees, depth = memory.get(number, (0, -1, -1))
        if balanced != -1 or frees != blocks:
            problems.append(f"tree {number}: freed {frees} blocks, balanced "
                            f"{balanced}; model {blocks} blocks")
        if depth != 0:
            problems.append(f"tree {number}: stack depth {depth} after the trial")
    return problems



# ── Fog of war ───────────────────────────────────────────────────

_HALF = Fraction(1, 2)


def shadowcast(width: int, height: int, walls: set[tuple[int, int]],
               ox: int, oy: int, radius: int,
               edge_blocks: bool = True) -> set[tuple[int, int]]:
    """The tiles a viewer at (OX, OY) sees within RADIUS.

    A floor tile is seen when its centre lies within a row's slopes, a
    wall when any part of it does, and either only within the radius.
    With EDGE_BLOCKS false the map's outside is open ground, which must
    see the same tiles inside the map.
    """
    seen: set[tuple[int, int]] = set()
    if not (0 <= ox < width and 0 <= oy < height):
        return seen

    def inside(x: int, y: int) -> bool:
        return 0 <= x < width and 0 <= y < height

    def blocks(x: int, y: int) -> bool:
        return (x, y) in walls if inside(x, y) else edge_blocks

    seen.add((ox, oy))
    if radius <= 0:
        return seen
    for quadrant in range(4):
        def tile(depth: int, col: int) -> tuple[int, int]:
            return [(ox + col, oy - depth), (ox + depth, oy + col),
                    (ox + col, oy + depth), (ox - depth, oy + col)][quadrant]

        def scan(depth: int, start: Fraction, end: Fraction) -> None:
            previous = None
            first = math.floor(depth * start + _HALF)
            last = math.ceil(depth * end - _HALF)
            for col in range(first, last + 1):
                x, y = tile(depth, col)
                wall = blocks(x, y)
                if wall or depth * start <= col <= depth * end:
                    if depth * depth + col * col <= radius * radius and inside(x, y):
                        seen.add((x, y))
                if previous is True and not wall:
                    start = Fraction(2 * col - 1, 2 * depth)
                if previous is False and wall and depth < radius:
                    scan(depth + 1, start, Fraction(2 * col - 1, 2 * depth))
                previous = wall
            if previous is False and depth < radius:
                scan(depth + 1, start, end)

        scan(1, Fraction(-1), Fraction(1))
    return seen


@dataclass
class FogMap:
    width: int
    height: int
    walls: set[tuple[int, int]]
    viewers: list[tuple[int, int, int]]     # x y radius, three of them
    token: bool = False                     # blocking source: a token


def _fog_floor(rng: random.Random, fmap: "FogMap") -> tuple[int, int]:
    floors = [(x, y) for y in range(fmap.height) for x in range(fmap.width)
              if (x, y) not in fmap.walls]
    edges = [p for p in floors if p[0] in (0, fmap.width - 1)
             or p[1] in (0, fmap.height - 1)]
    pool = edges if edges and rng.random() < 0.3 else floors
    return rng.choice(pool)


def fog_maps(seed: int = 20261123, count: int = 30) -> list[FogMap]:
    """The probe's two maps, then COUNT seeded random maps."""
    maps = [
        FogMap(10, 10, {(3, 3), (4, 3), (5, 3)}, [(1, 3, 8), (8, 8, 4), (1, 1, 8)]),
        FogMap(10, 10, {(2, 2)}, [(0, 0, 8), (9, 9, 3), (5, 5, 10)], token=True),
    ]
    rng = random.Random(seed)
    for number in range(count):
        width, height = rng.randint(4, 24), rng.randint(4, 12)
        density = rng.choice([0.0, 0.1, 0.2, 0.3, 0.45])
        walls = {(x, y) for y in range(height) for x in range(width)
                 if rng.random() < density}
        if len(walls) == width * height:
            walls.discard((0, 0))
        fmap = FogMap(width, height, walls, [], token=number % 4 == 3)
        fmap.viewers = [(*_fog_floor(rng, fmap), rng.randint(0, 12))
                        for _ in range(3)]
        maps.append(fmap)
    return maps


FOG_FORTH_SUPPORT = r"""
\ ── Fog against the host oracle ────────────────────────────────
VARIABLE _FGT-FOG  VARIABLE _FGT-MAP
: _FGT-BEGIN  ( w h -- )  2DUP CMAP-NEW _FGT-MAP !  FOG-NEW _FGT-FOG ! ;
: _FGT-ROW!  ( addr u y -- )
    SWAP 0 ?DO
        OVER I + C@ [CHAR] # = IF _FGT-MAP @ I 2 PICK 1 CMAP-SET THEN
    LOOP 2DROP ;
: _FGT-TOKEN  ( x y ctx -- flag )  -ROT CMAP-SOLID? ;
: _FGT-USE-MAP  ( -- )  _FGT-FOG @ _FGT-MAP @ FOG-BLOCK-MAP! ;
: _FGT-USE-TOKEN  ( -- )  _FGT-FOG @ ['] _FGT-TOKEN _FGT-MAP @ FOG-BLOCK-XT! ;
: _FGT-END  ( -- )  _FGT-FOG @ FOG-FREE  _FGT-MAP @ CMAP-FREE ;
: _FGT-ROW.  ( fog y -- )
    OVER FOG-W 0 ?DO OVER I 2 PICK FOG-STATE [CHAR] 0 + EMIT LOOP 2DROP ;
: _FGT-GRID.  ( id step -- )
    ." FOGG: " SWAP . . CR
    _FGT-FOG @ FOG-H 0 ?DO ." FR: " _FGT-FOG @ I _FGT-ROW. CR LOOP ;
: _FGT-SEE  ( x y radius -- )  >R >R >R _FGT-FOG @ R> R> R> FOG-REVEAL ;
DEPTH CONSTANT _FGT-DEPTH0
"""


def fog_forth(maps: list[FogMap]) -> str:
    """Forth that reveals each map's viewers: two, a hide, then one."""
    lines = [FOG_FORTH_SUPPORT]
    for number, fmap in enumerate(maps):
        lines += ["-1 MLOG-HOLD  MLOG-START",
                  f"{fmap.width} {fmap.height} _FGT-BEGIN"]
        for y in range(fmap.height):
            row = "".join("#" if (x, y) in fmap.walls else "."
                          for x in range(fmap.width))
            lines.append(f'S" {row}" {y} _FGT-ROW!')
        lines.append("_FGT-USE-TOKEN" if fmap.token else "_FGT-USE-MAP")
        (x1, y1, r1), (x2, y2, r2), (x3, y3, r3) = fmap.viewers
        lines += [
            "_FGT-FOG @ FOG-RESET",
            f"{x1} {y1} {r1} _FGT-SEE  {number} 0 _FGT-GRID.",
            f"{x2} {y2} {r2} _FGT-SEE  {number} 1 _FGT-GRID.",
            f"_FGT-FOG @ FOG-HIDE-ALL  {x3} {y3} {r3} _FGT-SEE  {number} 2 _FGT-GRID.",
            "_FGT-END",
            "MLOG-STOP  0 MLOG-HOLD",
            f'." FOGM: " {number} . MLOG-BALANCED? . DEPTH _FGT-DEPTH0 - . CR',
        ]
    return "\n".join(lines) + "\n"


def fog_layers(fmap: FogMap) -> list[list[str]]:
    """The oracle's layer after each of a map's three steps, row by row."""
    (x1, y1, r1), (x2, y2, r2), (x3, y3, r3) = fmap.viewers
    first = shadowcast(fmap.width, fmap.height, fmap.walls, x1, y1, r1)
    second = shadowcast(fmap.width, fmap.height, fmap.walls, x2, y2, r2)
    third = shadowcast(fmap.width, fmap.height, fmap.walls, x3, y3, r3)

    def layer(visible: set, remembered: set) -> list[str]:
        return ["".join("2" if (x, y) in visible else
                        "1" if (x, y) in remembered else "0"
                        for x in range(fmap.width))
                for y in range(fmap.height)]

    return [layer(first, set()), layer(first | second, set()),
            layer(third, first | second)]


def fog_check(text: str, maps: list[FogMap]) -> list[str]:
    """Differences between the transcript's layers and the oracle's."""
    problems: list[str] = []
    grids: dict[tuple[int, int], list[str]] = {}
    memory: dict[int, tuple[int, int]] = {}
    current = None
    for line in text.splitlines():
        try:
            if line.startswith("FOGG: "):
                number, step = (int(x) for x in line[6:].split())
                current = grids.setdefault((number, step), [])
            elif line.startswith("FR: ") and current is not None:
                current.append(line[4:].strip())
            elif line.startswith("FOGM: "):
                number, balanced, depth = (int(x) for x in line[6:].split())
                memory[number] = (balanced, depth)
                current = None
        except ValueError:
            problems.append(f"unreadable line: {line!r}")
    for number, fmap in enumerate(maps):
        for step, want in enumerate(fog_layers(fmap)):
            got = grids.get((number, step))
            if got != want:
                where = "no layer"
                if got:
                    rows = [y for y, (a, b) in enumerate(zip(got, want)) if a != b]
                    where = f"rows {rows[:4]}: got {got[rows[0]] if rows else got} " \
                            f"oracle {want[rows[0]] if rows else want}"
                problems.append(f"map {number} step {step}: {where}")
        balanced, depth = memory.get(number, (0, -1))
        if balanced != -1:
            problems.append(f"map {number}: the memory log does not balance")
        if depth != 0:
            problems.append(f"map {number}: stack depth {depth} after the trial")
    return problems
