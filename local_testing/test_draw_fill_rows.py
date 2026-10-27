"""A fill leaves alone the rows that already hold what it writes, exactly.

DRW-FILL-RECT checks each row of its rectangle with block compares and
writes only the rows whose cells, residue or provenance differ from what it
puts there; a row it leaves alone still counts as touched.  These units run
the real screen and draw sources on small guest screens.  From the same
seeded state each case runs the fill and the fill it replaced, kept here as
the reference, which drew every row with DRW-HLINE in a borrow of its own.
They compare every plane and flag the screen keeps and the damage plan a
flush makes from them.  Seeded documents of nested containers, styles, wide
characters, clips and layers are painted both ways frame after frame, and
their CELL output is compared byte for byte.
"""

from __future__ import annotations

import random
from collections import Counter

import pytest

from test_screen_projection_residue import MASK64, STEP_BUDGET, ScreenHarness


W, H = 14, 7
CELLS = W * H

# Screen descriptor fields (screen.f section 1).
PLANES = (("front", 16, 8 * CELLS), ("back", 24, 8 * CELLS),
          ("occlusion", 120, CELLS), ("residue", 128, 8 * CELLS),
          ("residue-front", 152, 8 * CELLS), ("touched", 112, H),
          ("damage", 104, H), ("residue-damage", 144, H))
FLAGS = (("dirty", 56), ("force", 64), ("flush-request", 80),
         ("draw-generation", 88), ("front-generation", 96),
         ("residue-dirty", 136))
PLAN = ("_SCR-FLUSH-MODE", "_SCR-SPAN-COUNT", "_SCR-CELL-COUNT",
        "_SCR-WORD-COUNT", "_SCR-SPAN-PEAK")

WORDS = """
\\ The fill DRW-FILL-RECT replaced: the same clipping, then each row drawn
\\ with DRW-HLINE, which takes a borrow of the plane of its own.
: REF-FILL-RECT  ( cp row col h w -- )
    _DRW-FR-W ! _DRW-FR-H ! _DRW-FR-COL !
    _DRW-FR-ROW ! _DRW-FR-CP !
    _DRW-FR-H @ 0> _DRW-FR-W @ 0> AND 0= IF EXIT THEN
    _DRW-FR-ROW @ _DRW-FR-H @
        _DRW-PHYSICAL-ROW-LOW _DRW-PHYSICAL-ROW-HIGH _DRW-CLIP-AXIS
    0= IF 2DROP EXIT THEN
    _DRW-FR-H ! _DRW-FR-ROW !
    _DRW-FR-COL @ _DRW-FR-W @
        _DRW-PHYSICAL-COL-LOW _DRW-PHYSICAL-COL-HIGH _DRW-CLIP-AXIS
    0= IF 2DROP EXIT THEN
    _DRW-FR-W ! _DRW-FR-COL !
    0 _DRW-FR-I !
    BEGIN _DRW-FR-I @ _DRW-FR-H @ < WHILE
        _DRW-FR-CP @
        _DRW-FR-ROW @ _DRW-FR-I @ +
        _DRW-FR-COL @
        _DRW-FR-W @
        DRW-HLINE
        1 _DRW-FR-I +!
    REPEAT ;

VARIABLE T-CP  VARIABLE T-ROW  VARIABLE T-COL  VARIABLE T-H  VARIABLE T-W
VARIABLE T-SCOPE  VARIABLE T-XT  VARIABLE T-TEXT-U
CREATE T-TEXT-BUF 64 ALLOT
: T-NEW   T-CP @ T-ROW @ T-COL @ T-H @ T-W @ DRW-FILL-RECT ;
: T-REF   T-CP @ T-ROW @ T-COL @ T-H @ T-W @ REF-FILL-RECT ;
: T-TEXT  T-TEXT-BUF T-TEXT-U @ T-ROW @ T-COL @ DRW-TEXT ;
: T-BODY  T-XT @ EXECUTE ;
: T-OVER  ['] T-BODY DRW-OVERLAY ;
\\ Scope 0 is ordinary paint, 1 a foreground overlay, 2 a replacement
\\ layer and 3 an overlay inside a replacement layer.
: T-RUN  ( xt -- )
    T-XT !
    T-SCOPE @ 1 = IF ['] T-BODY DRW-OVERLAY EXIT THEN
    T-SCOPE @ 2 = IF ['] T-BODY DRW-REPLACEMENT EXIT THEN
    T-SCOPE @ 3 = IF ['] T-OVER DRW-REPLACEMENT EXIT THEN
    T-BODY ;
: T-FILL-NEW  ['] T-NEW T-RUN ;
: T-FILL-REF  ['] T-REF T-RUN ;
: T-TEXT-RUN  ['] T-TEXT T-RUN ;

\\ The fill's clipping and the set-up of its row check, run in a borrow that
\\ writes nothing, leave the rectangle and cell it checks in its variables.
: T-CHECKABLE-BODY  _DRW-FR-CHECKABLE ;
: T-CHECKABLE  ( -- )
    0 _DRW-FR-CHECK !
    T-CP @ _DRW-FR-CP !  T-ROW @ _DRW-FR-ROW !  T-COL @ _DRW-FR-COL !
    T-H @ _DRW-FR-H !  T-W @ _DRW-FR-W !
    _DRW-FR-H @ 0> _DRW-FR-W @ 0> AND 0= IF EXIT THEN
    _DRW-FR-ROW @ _DRW-FR-H @
        _DRW-PHYSICAL-ROW-LOW _DRW-PHYSICAL-ROW-HIGH _DRW-CLIP-AXIS
    0= IF 2DROP EXIT THEN
    _DRW-FR-H ! _DRW-FR-ROW !
    _DRW-FR-COL @ _DRW-FR-W @
        _DRW-PHYSICAL-COL-LOW _DRW-PHYSICAL-COL-HIGH _DRW-CLIP-AXIS
    0= IF 2DROP EXIT THEN
    _DRW-FR-W ! _DRW-FR-COL !
    ['] T-CHECKABLE-BODY _DRW-WITH-BACK-MUTATION ;
: T-CHECKABLE-RUN  ['] T-CHECKABLE T-RUN ;
"""

STYLES = ((7, 0, 0), (2, 0, 0), (7, 4, 0), (7, 0, 1))
# Spaces mostly, as containers fill; a printable, a wide character, a
# combining mark that shows as a space, NUL, DEL and a wide emoji.
FILL_CPS = (32, 32, 32, 32, 32, 32, ord("x"), 0x4E00, 0x0301, 0, 0x7F, 0x1F600)
TEXTS = ("ab", "x", "\u6f22\u5b57", "a\u6f22", "\U0001F600b", "e\u0301",
         "  ", "abc def")


class FillHarness(ScreenHarness):
    def __init__(self, backend: str):
        super().__init__(backend)
        small = self.screen
        self.screen = self.new_screen()
        self.call("SCR-FREE", small)
        self.evaluate(WORDS)

    def new_screen(self) -> int:
        screen = self.call("SCR-NEW", W, H)[0]
        self.call("SCR-USE", screen)
        return screen

    def use(self, screen: int) -> None:
        self.screen = screen
        self.call("SCR-USE", screen)

    def set(self, name: str, value: int) -> None:
        self.runtime.memory.write64(self.address(name), value & MASK64)

    def get(self, name: str) -> int:
        return self.runtime.memory.read64(self.address(name))

    def steps(self, name: str) -> int:
        stack = self.runtime.main_context.data
        assert stack.snapshot() == ()
        steps = self.runtime.execute(name, step_budget=STEP_BUDGET).semantic_steps
        assert stack.snapshot() == ()
        assert self.runtime.main_context.returns.snapshot() == ()
        return steps

    def style(self, style: tuple[int, int, int]) -> None:
        self.call("DRW-STYLE!", *style)

    def clip(self, clip: tuple[int, ...] | None) -> None:
        """Set the origin and clip as a region sets them, from (on, origin
        row, origin column, clip row, clip column, height, width); None is
        no clip and no origin."""

        on, origin_row, origin_col, row, col, height, width = clip or (0,) * 7
        self.set("_DRW-ORIGIN-ROW", origin_row)
        self.set("_DRW-ORIGIN-COL", origin_col)
        self.set("_DRW-CLIP-ROW", row)
        self.set("_DRW-CLIP-COL", col)
        self.set("_DRW-CLIP-H", height)
        self.set("_DRW-CLIP-W", width)
        self.set("_DRW-CLIP-ON", -1 if on else 0)

    def fill(self, word: str, cp: int, row: int, col: int, height: int,
             width: int, scope: int = 0) -> int:
        for name, value in (("T-CP", cp), ("T-ROW", row), ("T-COL", col),
                            ("T-H", height), ("T-W", width), ("T-SCOPE", scope)):
            self.set(name, value)
        return self.steps(word)

    def text(self, text: str, row: int, col: int, scope: int = 0) -> int:
        data = text.encode()
        self.runtime.memory.write_bytes(self.address("T-TEXT-BUF"), data)
        for name, value in (("T-TEXT-U", len(data)), ("T-ROW", row),
                            ("T-COL", col), ("T-SCOPE", scope)):
            self.set(name, value)
        return self.steps("T-TEXT-RUN")

    def flush(self) -> bytes:
        self.runtime.drain_uart_output()
        assert self.call("SCR-FLUSH?") == (0,)
        return self.runtime.drain_uart_output()

    def _plane(self, offset: int) -> int:
        return self.runtime.memory.read64(self.screen + offset)

    def state(self) -> dict:
        """Every plane and flag of the screen and the global plan's validity."""

        memory = self.runtime.memory
        state = {name: memory.read_bytes(self._plane(offset), size)
                 for name, offset, size in PLANES}
        state.update({name: memory.read64(self.screen + offset) for name, offset in FLAGS})
        state["plan-valid"] = self.get("_SCR-PLAN-VALID")
        return state

    def restore(self, state: dict) -> None:
        memory = self.runtime.memory
        for name, offset, _size in PLANES:
            memory.write_bytes(self._plane(offset), state[name])
        for name, offset in FLAGS:
            memory.write64(self.screen + offset, state[name])
        self.set("_SCR-PLAN-VALID", state["plan-valid"])

    def plan(self) -> dict:
        """The damage plan a flush makes from the screen as it is now."""

        self.call("_SCR-COUNT-CHANGES")
        plan = {name: self.get(name) for name in PLAN}
        plan["damage"] = self.runtime.memory.read_bytes(self._plane(104), H)
        return plan


@pytest.fixture(params=("python", "native"))
def fills(request):
    harness = FillHarness(request.param)
    yield harness
    harness.close()


def _rect(rng: random.Random) -> tuple[int, int, int, int]:
    if rng.random() < 0.1:
        # Empty, or wholly outside the screen.
        return (rng.randint(-2, H + 1), rng.randint(-3, W + 1),
                rng.randint(-1, 1), rng.randint(-1, 1))
    return (rng.randint(-2, H - 1), rng.randint(-3, W - 1), rng.randint(1, H + 2),
            rng.randint(1, W + 3))


def _clip(rng: random.Random):
    if rng.random() < 0.4:
        return None
    if rng.random() < 0.1:
        # No clip, with an origin left behind, which drawing then ignores.
        return (0, rng.randint(-2, 2), rng.randint(-2, 2), 0, 0, 0, 0)
    return (1, rng.randint(-2, 3), rng.randint(-3, 5), rng.randint(-1, H - 1),
            rng.randint(-1, W - 1), rng.randint(0, H + 1), rng.randint(0, W + 2))


def _scribble(fills: FillHarness, rng: random.Random, cp: int, style, clip,
              rect, scope) -> None:
    """Paint the screen into a state a repaint meets: earlier fills of the
    same cell, text with wide characters, layers and committed frames, and
    then, as a container's parent does, the same fill over the same cells,
    in the same layer or another, with text over some of them."""

    fills.clip(None)
    for _ in range(rng.randint(1, 6)):
        fills.style(style if rng.random() < 0.6 else rng.choice(STYLES))
        layer = rng.choice((0, 0, 0, 1, 2))
        kind = rng.random()
        if kind < 0.5:
            fills.fill("T-FILL-REF", cp if rng.random() < 0.7 else rng.choice(FILL_CPS),
                       *_rect(rng), layer)
        elif kind < 0.85:
            fills.text(rng.choice(TEXTS), rng.randint(0, H - 1), rng.randint(-1, W - 1), layer)
        else:
            fills.flush()
    if rng.random() < 0.8:
        fills.style(style if rng.random() < 0.85 else rng.choice(STYLES))
        fills.clip(clip)
        row, col, height, width = rect
        above, left = rng.randint(0, 2), rng.randint(0, 2)
        fills.fill("T-FILL-REF", cp, row - above, col - left,
                   height + above + rng.randint(0, 2), width + left + rng.randint(0, 2),
                   scope if rng.random() < 0.6 else rng.choice((0, 1, 2, 3)))
        for _ in range(rng.choice((0, 0, 1, 2))):
            fills.style(rng.choice(STYLES))
            fills.text(rng.choice(TEXTS), row + rng.randint(0, max(0, height - 1)),
                       col + rng.randint(-1, max(0, width - 1)), rng.choice((0, 0, 1, 2)))
        if rng.random() < 0.3:
            fills.flush()
        fills.clip(None)
    memory = fills.runtime.memory
    if rng.random() < 0.25:
        # Arbitrary bytes, broken pairs among them, in each written plane.
        cells = [memory.read64(fills._plane(24) + 8 * i) for i in range(CELLS)]
        for _ in range(rng.randint(1, 6)):
            index = rng.randrange(CELLS)
            value = rng.choice((cells[index] | 0x0080000000000000,
                                cells[index] | 0x0100000000000000,
                                rng.randrange(256) << 40 | rng.randrange(256) << 32
                                | rng.randint(0x21, 0x7E),
                                cells[rng.randrange(CELLS)]))
            plane = rng.choice((24, 128))
            memory.write64(fills._plane(plane) + 8 * index, value)
        for _ in range(rng.randint(0, 3)):
            memory.write8(fills._plane(120) + rng.randrange(CELLS), rng.choice((0, 255, 7)))


def _rows(fills: FillHarness, cp: int, rect, scope: int) -> Counter:
    """What the fill finds in each row of its rectangle, read from the
    planes as they are now: whether it checks the rows at all, and for each
    checked row the first plane that differs from what it writes."""

    fills.fill("T-CHECKABLE-RUN", cp, *rect, scope)
    if not fills.get("_DRW-FR-CHECK"):
        return Counter(("not checked",))
    cell, top, left, height, width = (fills.get(name) for name in (
        "_DRW-FR-CELL", "_DRW-FR-AROW", "_DRW-FR-ACOL", "_DRW-FR-H", "_DRW-FR-W"))
    memory = fills.runtime.memory
    back, residue, occlusion = fills._plane(24), fills._plane(128), fills._plane(120)
    overlay = 255 if scope in (1, 3) else 0
    rows: Counter = Counter()
    for row in range(top, top + height):
        indices = range(row * W + left, row * W + left + width)
        if any(memory.read64(back + 8 * i) != cell for i in indices):
            rows["cells differ"] += 1
        elif any(memory.read64(residue + 8 * i) != cell for i in indices):
            # Inside a replacement layer the fill leaves the residue alone.
            rows["left alone over another residue" if scope == 2 else "residue differs"] += 1
        elif any(memory.read8(occlusion + i) != overlay for i in indices):
            rows["provenance differs"] += 1
        else:
            rows["left alone"] += 1
    return rows


def test_a_fill_leaves_the_state_the_fill_it_replaced_leaves(fills):
    rng = random.Random(7_20261027)
    found: Counter = Counter()
    for case in range(96):
        cp = rng.choice(FILL_CPS)
        style = rng.choice(STYLES)
        clip, rect, scope = _clip(rng), _rect(rng), rng.choice((0, 0, 0, 1, 2, 3))
        _scribble(fills, rng, cp, style, clip, rect, scope)
        start = fills.state()
        fills.style(style)
        fills.clip(clip)
        found += _rows(fills, cp, rect, scope)
        results = []
        for word in ("T-FILL-NEW", "T-FILL-REF"):
            fills.restore(start)
            fills.style(style)
            fills.clip(clip)
            steps = fills.fill(word, cp, *rect, scope)
            results.append((fills.state(), fills.plan(), steps))
        fills.clip(None)
        (new_state, new_plan, _), (ref_state, ref_plan, _) = results
        context = f"case {case}: cp {cp:#x} style {style} clip {clip} rect {rect} scope {scope}"
        assert new_state == ref_state, context
        assert new_plan == ref_plan, context
    # The seeds reach every kind of row the check can meet.
    assert set(found) == {"not checked", "cells differ", "residue differs",
                          "provenance differs", "left alone",
                          "left alone over another residue"}, found
    assert min(found.values()) >= 5 and found["left alone"] >= 40, found


def test_a_row_that_holds_the_fill_is_not_written_again(fills):
    fills.style((7, 4, 0))
    first = fills.fill("T-FILL-NEW", 32, 0, 0, H, W)
    again = fills.fill("T-FILL-NEW", 32, 0, 0, H, W)
    reference = fills.fill("T-FILL-REF", 32, 0, 0, H, W)
    assert again * 4 < reference, (first, again, reference)
    # One changed cell rewrites its row and leaves the others alone.
    fills.text("x", 3, 5)
    one_row = fills.fill("T-FILL-NEW", 32, 0, 0, H, W)
    assert again < one_row < again + 2 * reference // H, (again, one_row, reference)
    # Every row of the rectangle still counts as touched.
    assert fills.flush()
    fills.fill("T-FILL-NEW", 32, 1, 2, 3, 4)
    assert fills.state()["touched"] == bytes((0, 255, 255, 255, 0, 0, 0))
    assert fills.state()["dirty"] == MASK64


def _container(rng: random.Random, rect, origin, clip, style, depth: int,
               ops: list) -> None:
    """One container at RECT, local to ORIGIN: its fill, then its children
    or a label.  CLIP is the clip it paints under."""

    row, col, height, width = rect
    style = style if rng.random() < 0.7 else rng.choice(STYLES)
    ops.append(("style", style))
    ops.append(("fill", rect, rng.choice((0, 0, 0, 0, 2))))
    if depth < 3 and height >= 2 and width >= 4 and rng.random() < 0.85:
        clipped = rng.random() < 0.3
        if clipped:
            # The children paint in coordinates local to the container,
            # clipped to it within the clip it has, as a region gives them.
            top, left = origin[0] + row, origin[1] + col
            bottom, right = top + height, left + width
            if clip is not None:
                _on, _r, _c, c_row, c_col, c_height, c_width = clip
                top, left = max(top, c_row), max(left, c_col)
                bottom = min(bottom, c_row + c_height)
                right = min(right, c_col + c_width)
            origin = (origin[0] + row, origin[1] + col)
            clip = (1, *origin, top, left, max(0, bottom - top), max(0, right - left))
            ops.append(("clip", clip))
            row, col = 0, 0
        across = rng.random() < 0.5
        count = rng.randint(2, 3)
        span = width if across else height
        cuts = sorted(rng.sample(range(1, span), min(count - 1, span - 1)))
        edges = [0, *cuts, span]
        for start, end in zip(edges, edges[1:]):
            # A child may reach a cell past its parent, which the clip cuts.
            grow = 1 if clipped and rng.random() < 0.3 else 0
            child = ((row, col + start, height, end - start + grow) if across
                     else (row + start, col, end - start + grow, width))
            _container(rng, child, origin, clip, style, depth + 1, ops)
            ops.append(("style", style))
        if clipped:
            ops.append(("unclip", None))
    else:
        ops.append(("text", (rng.choice(TEXTS), row, col), rng.choice((0, 0, 0, 1))))


def _document(rng: random.Random) -> list:
    ops: list = []
    _container(rng, (0, 0, H, W), (0, 0), None, rng.choice(STYLES), 0, ops)
    return ops


def _changed(rng: random.Random, ops: list) -> list:
    """The same document with some labels' text and a style changed."""

    changed = []
    for op in ops:
        if op[0] == "text" and rng.random() < 0.4:
            (_text, row, col), scope = op[1], op[2]
            op = ("text", (rng.choice(TEXTS), row, col), scope)
        elif op[0] == "style" and rng.random() < 0.1:
            op = ("style", rng.choice(STYLES))
        changed.append(op)
    return changed


def _paint(fills: FillHarness, ops: list, word: str) -> int:
    """Paint OPS with the fill WORD; the steps its fills took."""

    clips = [None]
    steps = 0
    fills.clip(None)
    for kind, value, *scope in ops:
        if kind == "style":
            fills.style(value)
        elif kind == "fill":
            steps += fills.fill(word, 32, *value, scope[0])
        elif kind == "text":
            fills.text(*value, scope[0])
        elif kind == "clip":
            clips.append(value)
            fills.clip(value)
        else:
            clips.pop()
            fills.clip(clips[-1])
    fills.clip(None)
    return steps


def test_documents_paint_and_flush_the_same_frame_after_frame(fills):
    rng = random.Random(3_20261027)
    new_screen = fills.screen
    ref_screen = fills.new_screen()
    try:
        repaint_new = repaint_ref = 0
        for _document_index in range(4):
            document = _document(rng)
            frames = (document, document, _changed(rng, document), document)
            for index, ops in enumerate(frames):
                results = []
                for screen, word in ((new_screen, "T-FILL-NEW"), (ref_screen, "T-FILL-REF")):
                    fills.use(screen)
                    steps = _paint(fills, ops, word)
                    painted = fills.state()
                    output = fills.flush()
                    results.append((painted, output, fills.state(), steps))
                (new_painted, new_output, new_flushed, new_steps), \
                    (ref_painted, ref_output, ref_flushed, ref_steps) = results
                context = f"document {_document_index} frame {index}"
                assert new_painted == ref_painted, context
                assert new_output == ref_output, context
                assert new_flushed == ref_flushed, context
                if index == 1:
                    repaint_new += new_steps
                    repaint_ref += ref_steps
        # Repainting a document the screen already shows rewrites only rows
        # whose cells changed since the fill before: those under children
        # of another style, or text.
        assert repaint_new * 3 < repaint_ref * 2, (repaint_new, repaint_ref)
    finally:
        fills.use(new_screen)
        fills.call("SCR-FREE", ref_screen)
