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
"""

from __future__ import annotations

import random
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

