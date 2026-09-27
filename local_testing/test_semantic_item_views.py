#!/usr/bin/env python3
"""Native item views to ITM1 (SEMANTIC-CONTENT-1).

A canonical source builds an item view with the USCOL builder, the one deep
validation proves it and writes its summary, and USITM-PACK writes ITM1,
which MegaPad's decoder must read back to the same value.  Every structural
rule the contract names is refused by the validation.
"""

from __future__ import annotations

import re

from test_widget_pointer import _run_forth  # also puts MegaPad on the path

from rich_terminal.semantic_content import StyleRun, TextStyle
from rich_terminal.semantic_items import (
    ItemColumn,
    ItemColumnKind,
    ItemField,
    ItemRole,
    ItemState,
    ItemViewContent,
    ItemViewFlag,
    ItemViewRole,
    ViewItem,
    decode_item_view_content,
)

ROOTS = (
    "tui/semantic-collections.f",
    "tui/rich-terminal/uidl-semantic-items-itm1.f",
    "tui/rich-terminal/engine.f",
)

S = ItemState
_SETUP = [
    "VARIABLE _U",
    "CREATE _B-S USCOL-BUILDER-SIZE 7 + ALLOT",
    "CREATE _O-S 4096 7 + ALLOT",
    "CREATE _K-S 512 7 + ALLOT",
    "CREATE _M-S USCOL-SUMMARY-SIZE 7 + ALLOT",
    "CREATE _X 4096 ALLOT",
    ": _B _B-S 7 + -8 AND ;",
    ": _O _O-S 7 + -8 AND ;",
    ": _K _K-S 7 + -8 AND ;",
    ": _M _M-S 7 + -8 AND ;",
    ": _N  ( n -- )  2 EMIT . 3 EMIT ;",
    ": _BYTES  ( a u -- )  18 EMIT 0 ?DO DUP I + C@ . LOOP DROP 19 EMIT ;",
    ": _VALIDATE  ( -- status )  _O _U @ _K 512 _M USCOL-ENTRY-VALIDATE ;",
    # Copy a field's text to the builder's destination, if it gave one.
    ": _COPY  ( src u dst|0 -- )  ?DUP IF SWAP MOVE ELSE 2DROP THEN ;",
]


class _Program:
    """Forth lines that build one item view; each builder status is printed."""

    def __init__(self) -> None:
        self.lines: list[str] = []
        self.strings: dict[str, str] = {}
        self.statuses = 0

    def _string(self, text: str) -> str:
        name = f"_S{len(self.strings)}"
        data = text.encode("utf-8")
        self.lines += [
            f"CREATE {name} " + " ".join(f"{byte} C," for byte in data),
            f": {name}$  {name} {len(data)} ;",
        ]
        self.strings[name] = text
        return name

    def call(self, text: str) -> None:
        self.lines.append(f"{text} _N")
        self.statuses += 1

    def begin(self, content: ItemViewContent, *, key=5, height=6, width=20) -> None:
        self.lines.append(f"_O 4096 _B USCOL-BUILDER-INIT DROP")
        self.call(f"{key} 0 0 {height} {width} 3 _B USCOL-ITEMS-BEGIN")
        self.call(
            f"{int(content.role)} {int(content.flags)} {content.item_total} "
            f"{content.viewport_first} {content.viewport_count} _B USCOL-ITEMS-SHAPE"
        )
        for column in content.columns:
            name = self._string(column.label)
            self.call(f"{int(column.kind)} {name}$ _B USCOL-ITEMS-COLUMN")
        for item in content.items:
            self.item(item)
        self.call("_B USCOL-ITEMS-END")
        self.lines.append("_B USCOL-BUILDER-FINISH DROP _U !")

    def item(self, item: ViewItem) -> None:
        self.call(
            f"{item.item_key} {item.parent_key} {item.ordinal} {item.depth} "
            f"{int(item.state)} {int(item.role)} _B USCOL-ITEMS-ITEM-BEGIN"
        )
        for item_field in item.fields:
            name = self._string(item_field.text)
            if not item_field.runs:
                self.call(f"{name}$ _B USCOL-ITEMS-FIELD")
                continue
            data = item_field.text.encode("utf-8")
            self.lines.append(
                f"{len(data)} _B USCOL-ITEMS-FIELD-BEGIN _N {name}$ ROT _COPY"
            )
            self.statuses += 1
            for run in item_field.runs:
                self.call(f"{run.start} {run.length} {int(run.meaning)} _B USCOL-ITEMS-FIELD-RUN")
            self.call("_B USCOL-ITEMS-FIELD-END")
        self.call("_B USCOL-ITEMS-ITEM-END")


def _run(lines: list[str]):
    output = _run_forth(_SETUP + lines, roots=ROOTS).decode("utf-8", errors="replace")
    assert "not found" not in output and "underflow" not in output, output[-3000:]
    groups = [
        bytes(int(token) for token in body.split())
        for body in re.findall("\x12(.*?)\x13", output, re.S)
    ]
    numbers = [int(value) for value in re.findall(r"\x02\s*(-?\d+)\s*\x03", output)]
    return groups, numbers


def _item(key, ordinal, *texts, parent=0, depth=0, state=0, role=ItemRole.ITEM):
    return ViewItem(key, parent, ordinal, depth, ItemState(state), role,
                    tuple(t if isinstance(t, ItemField) else ItemField(t) for t in texts))


def _tree() -> ItemViewContent:
    return ItemViewContent(
        9, ItemViewRole.TREE, ItemViewFlag(0), (ItemColumn(ItemColumnKind.TEXT, "Name"),),
        5, 0, 4,
        (
            _item(1, 0, "/", state=S.EXPANDABLE | S.EXPANDED),
            _item(2, 1, "docs", parent=1, depth=1, state=S.EXPANDABLE),
            _item(3, 2, "notes.md", parent=1, depth=1, state=S.CURRENT),
            _item(4, 3, "étude", parent=1, depth=1),
            # Past the viewport, but selected, so carried.
            _item(6, 4, "zeta.f", parent=1, depth=1, state=S.SELECTED),
        ),
    )


def _table() -> ItemViewContent:
    return ItemViewContent(
        9, ItemViewRole.TABLE, ItemViewFlag(0),
        (
            ItemColumn(ItemColumnKind.TEXT, "Name"),
            ItemColumn(ItemColumnKind.NUMBER, "Size"),
            ItemColumn(ItemColumnKind.TEXT, ""),
        ),
        3, 1, 2,
        (
            _item(70, 1, "large.txt", "2K", "file", state=S.CHECKABLE | S.CHECKED),
            _item(71, 2, ItemField("see [x](y)", (StyleRun(4, 6, TextStyle.LINK),)),
                  "54", "file"),
        ),
    )


def _build_validate_pack(content: ItemViewContent):
    program = _Program()
    program.begin(content)
    program.lines += [
        "_VALIDATE _N",
        "_M USCOL-SUMMARY-CHILD-COUNT@ _N",
        "_M USCOL-SUMMARY-ITEM-COUNT@ _N",
        "_M USCOL-SUMMARY-FIELD-COUNT@ _N",
        "_M USCOL-SUMMARY-UTF8-BYTES@ _N",
        "_M USCOL-SUMMARY-RUN-COUNT@ _N",
        "_M USCOL-SUMMARY-ITM1-BYTES _N _N",
        "_O _U @ _M 9 _X 4096 USITM-PACK _N _X SWAP _BYTES",
    ]
    groups, numbers = _run(program.lines)
    statuses = numbers[: program.statuses]
    assert statuses == [0] * program.statuses, statuses
    return groups, numbers[program.statuses :]


def test_a_tree_builds_validates_and_packs_to_the_same_itm1_value() -> None:
    content = _tree()
    groups, numbers = _build_validate_pack(content)
    status, columns, items, fields, utf8, runs, itm1_status, itm1_bytes, pack = numbers
    assert status == 0
    assert (columns, items, fields, runs) == (1, 5, 5, 0)
    assert utf8 == content.utf8_bytes
    assert (itm1_status, itm1_bytes) == (0, content.wire_bytes)
    assert pack == 0
    (payload,) = groups
    assert decode_item_view_content(payload) == content


def test_a_table_with_labels_numbers_checks_and_runs_packs_exactly() -> None:
    content = _table()
    groups, numbers = _build_validate_pack(content)
    assert numbers[0] == 0
    assert numbers[5] == 1          # one style run
    (payload,) = groups
    assert decode_item_view_content(payload) == content


def _validate_status(content_items, *, role=ItemViewRole.TREE, total=None, first=0,
                     count=None, columns=1) -> int:
    """Build ITEMS with the builder, skipping the Python value's own checks,
    and return the deep validation's status."""

    program = _Program()
    total = len(content_items) if total is None else total
    count = total if count is None else count
    program.lines.append("_O 4096 _B USCOL-BUILDER-INIT DROP")
    program.call("5 0 0 6 20 3 _B USCOL-ITEMS-BEGIN")
    program.call(f"{int(role)} 0 {total} {first} {count} _B USCOL-ITEMS-SHAPE")
    for _ in range(columns):
        name = program._string("")
        program.call(f"1 {name}$ _B USCOL-ITEMS-COLUMN")
    for key, parent, ordinal, depth, state, item_role, texts in content_items:
        program.call(
            f"{key} {parent} {ordinal} {depth} {state} {item_role} _B USCOL-ITEMS-ITEM-BEGIN"
        )
        for text in texts:
            name = program._string(text)
            program.call(f"{name}$ _B USCOL-ITEMS-FIELD")
        program.call("_B USCOL-ITEMS-ITEM-END")
    program.call("_B USCOL-ITEMS-END")
    program.lines += ["_B USCOL-BUILDER-FINISH DROP _U !", "_VALIDATE _N"]
    _groups, numbers = _run(program.lines)
    assert numbers[: program.statuses] == [0] * program.statuses
    return numbers[program.statuses]


E, X, SEL, CUR, CHK, CHD, UNA = 4, 8, 1, 2, 16, 32, 64
ITEM, SECTION = 1, 2


def test_the_deep_validation_refuses_every_structural_rule() -> None:
    ok = [(1, 0, 0, 0, E | X, ITEM, ["/"]), (2, 1, 1, 1, 0, ITEM, ["a"])]
    assert _validate_status(ok) == 0
    cases = [
        # A child of a collapsed parent.
        [(1, 0, 0, 0, E, ITEM, ["/"]), (2, 1, 1, 1, 0, ITEM, ["a"])],
        # Depth jumps by two.
        [(1, 0, 0, 0, E | X, ITEM, ["/"]), (2, 1, 1, 2, 0, ITEM, ["a"])],
        # Deeper than the item before, but not its child.
        [(1, 0, 0, 0, E | X, ITEM, ["/"]), (2, 9, 1, 1, 0, ITEM, ["a"])],
        # A parent later in the order.
        [(2, 1, 0, 0, 0, ITEM, ["a"]), (1, 0, 1, 0, E | X, ITEM, ["/"])],
        # Duplicate keys, and ordinals out of order.
        [(1, 0, 0, 0, 0, ITEM, ["a"]), (1, 0, 1, 0, 0, ITEM, ["b"])],
        [(1, 0, 1, 0, 0, ITEM, ["a"]), (2, 0, 0, 0, 0, ITEM, ["b"])],
        # Two selected, and an unavailable selected item.
        [(1, 0, 0, 0, SEL, ITEM, ["a"]), (2, 0, 1, 0, SEL, ITEM, ["b"])],
        [(1, 0, 0, 0, SEL | UNA, ITEM, ["a"]), (2, 0, 1, 0, 0, ITEM, ["b"])],
        # Checked without a check box; expanded without children.
        [(1, 0, 0, 0, CHD, ITEM, ["a"]), (2, 0, 1, 0, 0, ITEM, ["b"])],
        [(1, 0, 0, 0, X, ITEM, ["a"]), (2, 0, 1, 0, 0, ITEM, ["b"])],
        # A field with a control character, and more fields than columns.
        [(1, 0, 0, 0, 0, ITEM, ["a\tb"]), (2, 0, 1, 0, 0, ITEM, ["b"])],
        [(1, 0, 0, 0, 0, ITEM, ["a", "b"]), (2, 0, 1, 0, 0, ITEM, ["b"])],
    ]
    for items in cases:
        assert _validate_status(items) == 4, items
    # The viewport must be covered: two items, a viewport of three.
    assert _validate_status(ok, total=3, count=3) == 4
    # Flat roles hold only top-level items.
    assert _validate_status(ok, role=ItemViewRole.LIST) == 4
    # Sections: items belong to a section, and a section has no state.
    sections_ok = [(1, 0, 0, 0, 0, SECTION, ["TASKS"]),
                   (2, 1, 1, 1, CHK, ITEM, ["plan"])]
    assert _validate_status(sections_ok, role=ItemViewRole.SECTIONS) == 0
    assert _validate_status(
        [(1, 0, 0, 0, 0, SECTION, ["TASKS"]), (2, 0, 1, 0, 0, ITEM, ["plan"])],
        role=ItemViewRole.SECTIONS,
    ) == 4
    assert _validate_status(
        [(1, 0, 0, 0, SEL, SECTION, ["TASKS"]), (2, 1, 1, 1, 0, ITEM, ["plan"])],
        role=ItemViewRole.SECTIONS,
    ) == 4


def test_measure_mode_needs_exactly_the_copied_bytes() -> None:
    program = _Program()
    program.begin(_tree())
    copy = [line for line in program.lines]
    measured = [
        line.replace("_O 4096 _B USCOL-BUILDER-INIT DROP", "0 0 _B USCOL-BUILDER-INIT DROP")
        .replace("_B USCOL-BUILDER-FINISH DROP _U !", "_B USCOL-BUILDER-FINISH DROP _N")
        for line in copy
    ]
    _groups, numbers = _run(copy + ["_U @ _N"] + measured)
    half = program.statuses
    copied = numbers[half]
    assert numbers[: half] == [0] * half
    assert numbers[half + 1 : 2 * half + 1] == [0] * half
    assert numbers[-1] == copied


def test_the_neutral_engine_admits_only_exact_itm1_content() -> None:
    """An ITEM_VIEW control's scalars must agree with its ITM1 bytes."""

    program = _Program()
    program.begin(_table())
    program.lines += [
        "_VALIDATE _N",
        "VARIABLE _XU",
        "_O _U @ _M 9 _X 4096 USITM-PACK _N _XU !",
        "CREATE _C-S RTE-CONTROL-SIZE 7 + ALLOT",
        ": _C _C-S 7 + -8 AND ;",
        ": _CTL  _C RTE-CONTROL-SIZE 0 FILL",
        "  1 _C _RTE-CONTROL.OWNER ! 1 _C _RTE-CONTROL.GENERATION !",
        "  7 _C _RTE-CONTROL.ID ! RTE-CONTROL-ITEM-VIEW _C _RTE-CONTROL.KIND !",
        "  RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR _C _RTE-CONTROL.STATE !",
        "  3 _C _RTE-CONTROL.REGION !",
        "  6 _C _RTE-CONTROL.HEIGHT ! 20 _C _RTE-CONTROL.WIDTH !",
        "  24 _C _RTE-CONTROL.ROOT-HEIGHT ! 80 _C _RTE-CONTROL.ROOT-WIDTH !",
        "  _X _C _RTE-CONTROL.CONTENT-A ! _XU @ _C _RTE-CONTROL.CONTENT-U !",
        "  _M USCOL-SUMMARY-ITEM-COUNT@ _C _RTE-CONTROL.CONTENT-ITEMS !",
        "  _M USCOL-SUMMARY-UTF8-BYTES@ _C _RTE-CONTROL.CONTENT-UTF8 !",
        "  _M USCOL-SUMMARY-RUN-COUNT@ _C _RTE-CONTROL.CONTENT-RUNS !",
        "  _M USCOL-SUMMARY-FIELD-COUNT@ _C _RTE-CONTROL.CONTENT-FIELDS ! ;",
        ": _OK?  _C RTE-CONTROL-VALID? _N ;",
        "_CTL _OK?",
        "_CTL 1 _C _RTE-CONTROL.CONTENT-FIELDS +! _OK?",
        "_CTL 1 _C _RTE-CONTROL.CONTENT-UTF8 +! _OK?",
        "_CTL 1 _C _RTE-CONTROL.CONTENT-RUNS +! _OK?",
        "_CTL 1 _C _RTE-CONTROL.CONTENT-ITEMS +! _OK?",
        # Fewer fields than items, even if the length were right.
        "_CTL 1 _C _RTE-CONTROL.CONTENT-FIELDS ! _OK?",
        # The header's tag, then its carried count, disagree.
        "_CTL 0 _X C! _OK? 73 _X C!",
        "_CTL _X 36 + C@ 1+ _X 36 + C! _OK? _X 36 + C@ 1- _X 36 + C!",
        # A text area carries no fields.
        "_CTL RTE-CONTROL-TEXT-AREA _C _RTE-CONTROL.KIND ! _OK?",
        "_CTL _OK?",
    ]
    _groups, numbers = _run(program.lines)
    assert numbers[: program.statuses] == [0] * program.statuses
    validate, pack, *verdicts = numbers[program.statuses :]
    assert (validate, pack) == (0, 0)
    assert verdicts == [-1, 0, 0, 0, 0, 0, 0, 0, 0, -1]
