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
    # Add a field byte for byte, without USCOL-ITEMS-FIELD's cleaning.
    ": _FIELD-RAW  ( a u -- status )  DUP _B USCOL-ITEMS-FIELD-BEGIN >R _COPY R> ;",
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
            f"{content.viewport_first} {content.viewport_count} "
            f"{content.viewport_row} _B USCOL-ITEMS-SHAPE"
        )
        for column in content.columns:
            name = self._string(column.label)
            self.call(f"{int(column.kind)} {int(column.flags)} {name}$ _B USCOL-ITEMS-COLUMN")
        for item in content.items:
            self.item(item, content.columns)
        self.call("_B USCOL-ITEMS-END")
        self.lines.append("_B USCOL-BUILDER-FINISH DROP _U !")

    def item(self, item: ViewItem, columns: tuple[ItemColumn, ...]) -> None:
        self.call(
            f"{item.item_key} {item.parent_key} {item.ordinal} {item.depth} "
            f"{int(item.state)} {int(item.role)} _B USCOL-ITEMS-ITEM-BEGIN"
        )
        for index, item_field in enumerate(item.fields):
            name = self._string(item_field.text)
            if not item_field.runs:
                wrap = -1 if columns[index].wrap else 0
                self.call(f"{name}$ {wrap} _B USCOL-ITEMS-FIELD")
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
                     count=None, columns=1, row=0, column_flags=()) -> int:
    """Build ITEMS with the builder, skipping the Python value's own checks,
    and return the deep validation's status.  Fields are written byte for
    byte, past USCOL-ITEMS-FIELD's own cleaning, so the validation sees
    exactly the text given.  COLUMN_FLAGS gives the first columns' flags."""

    program = _Program()
    total = len(content_items) if total is None else total
    count = total if count is None else count
    program.lines.append("_O 4096 _B USCOL-BUILDER-INIT DROP")
    program.call("5 0 0 6 20 3 _B USCOL-ITEMS-BEGIN")
    program.call(f"{int(role)} 0 {total} {first} {count} {row} _B USCOL-ITEMS-SHAPE")
    for index in range(columns):
        name = program._string("")
        flags = column_flags[index] if index < len(column_flags) else 0
        program.call(f"1 {flags} {name}$ _B USCOL-ITEMS-COLUMN")
    for key, parent, ordinal, depth, state, item_role, texts in content_items:
        program.call(
            f"{key} {parent} {ordinal} {depth} {state} {item_role} _B USCOL-ITEMS-ITEM-BEGIN"
        )
        for text in texts:
            name = program._string(text)
            program.call(f"{name}$ _FIELD-RAW")
            program.call("_B USCOL-ITEMS-FIELD-END")
        program.call("_B USCOL-ITEMS-ITEM-END")
    program.call("_B USCOL-ITEMS-END")
    program.lines += ["_B USCOL-BUILDER-FINISH DROP _U !", "_VALIDATE _N"]
    _groups, numbers = _run(program.lines)
    assert numbers[: program.statuses] == [0] * program.statuses
    return numbers[program.statuses]


E, X, SEL, CUR, CHK, CHD, UNA = 4, 8, 1, 2, 16, 32, 64
ITEM, SECTION = 1, 2


def test_a_field_is_published_as_cell_shows_it() -> None:
    # USCOL-ITEMS-FIELD, as the tree uses it, publishes a C0 control, a
    # byte that cannot start a character, and a stray continuation byte as
    # U+FFFD each, and measure mode counts the bytes the copy writes.
    raw = b"x\x01\xff\x80y"
    content = ItemViewContent(
        9, ItemViewRole.LIST, ItemViewFlag(0), (ItemColumn(ItemColumnKind.TEXT),),
        1, 0, 1, (_item(1, 0, "x\ufffd\ufffd\ufffdy"),),
    )
    program = _Program()
    program.lines += [
        "CREATE _RAW " + " ".join(f"{byte} C," for byte in raw),
        f": _RAW$  _RAW {len(raw)} ;",
        "0 0 _B USCOL-BUILDER-INIT DROP",
        "5 0 0 6 20 3 _B USCOL-ITEMS-BEGIN DROP",
        "1 0 1 0 1 0 _B USCOL-ITEMS-SHAPE DROP",
        "1 0 0 0 _B USCOL-ITEMS-COLUMN DROP",
        "1 0 0 0 0 1 _B USCOL-ITEMS-ITEM-BEGIN DROP",
        "_RAW$ 0 _B USCOL-ITEMS-FIELD DROP",
        "_B USCOL-ITEMS-ITEM-END DROP _B USCOL-ITEMS-END DROP",
        "_B USCOL-BUILDER-FINISH _N _N",
        "_O 4096 _B USCOL-BUILDER-INIT DROP",
    ]
    program.call("5 0 0 6 20 3 _B USCOL-ITEMS-BEGIN")
    program.call("1 0 1 0 1 0 _B USCOL-ITEMS-SHAPE")
    program.call("1 0 0 0 _B USCOL-ITEMS-COLUMN")
    program.call("1 0 0 0 0 1 _B USCOL-ITEMS-ITEM-BEGIN")
    program.call("_RAW$ 0 _B USCOL-ITEMS-FIELD")
    program.call("_B USCOL-ITEMS-ITEM-END")
    program.call("_B USCOL-ITEMS-END")
    program.lines += [
        "_B USCOL-BUILDER-FINISH DROP DUP _U ! _N",
        "_VALIDATE _N",
        "_O _U @ _M 9 _X 4096 USITM-PACK _N _X SWAP _BYTES",
    ]
    groups, numbers = _run(program.lines)
    measure_status, measured = numbers[0], numbers[1]
    statuses = numbers[2 : 2 + program.statuses]
    copied, valid, packed = numbers[2 + program.statuses :]
    assert measure_status == 0 and statuses == [0] * program.statuses
    assert copied == measured
    assert (valid, packed) == (0, 0)
    (payload,) = groups
    assert decode_item_view_content(payload) == content


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


WRAP = 1


def _cards_content(viewport_row: int = 2) -> ItemViewContent:
    """Cards whose second column wraps: its fields keep their line feeds."""

    text = ItemColumn(ItemColumnKind.TEXT, "")
    wrapped = ItemColumn(ItemColumnKind.TEXT, "", wrap=True)
    return ItemViewContent(
        9, ItemViewRole.CARDS, ItemViewFlag(0), (text, wrapped),
        3, 1, 2,
        (
            _item(81, 1, "@mira", "one line\n\nand a paragraph"),
            _item(82, 2, "@rowan", "short"),
        ),
        viewport_row=viewport_row,
    )


def test_wrapping_cards_pack_their_flags_line_feeds_and_viewport_row() -> None:
    content = _cards_content()
    groups, numbers = _build_validate_pack(content)
    assert numbers[0] == 0
    (payload,) = groups
    assert len(payload) == content.wire_bytes
    decoded = decode_item_view_content(payload)
    assert decoded == content
    assert decoded.columns[1].wrap and decoded.viewport_row == 2


def test_a_wrapping_field_keeps_its_line_feeds_and_others_do_not() -> None:
    program = _Program()
    program.lines += [
        "CREATE _LF 97 C, 10 C, 98 C,",
        ": _LF$  _LF 3 ;",
        "_O 4096 _B USCOL-BUILDER-INIT DROP",
        "5 0 0 6 20 3 _B USCOL-ITEMS-BEGIN DROP",
        "5 0 1 0 1 0 _B USCOL-ITEMS-SHAPE DROP",
        "1 0 0 0 _B USCOL-ITEMS-COLUMN DROP",
        "1 1 0 0 _B USCOL-ITEMS-COLUMN DROP",
        "1 0 0 0 0 1 _B USCOL-ITEMS-ITEM-BEGIN DROP",
        "_LF$ 0 _B USCOL-ITEMS-FIELD DROP",
        "_LF$ -1 _B USCOL-ITEMS-FIELD DROP",
        "_B USCOL-ITEMS-ITEM-END DROP _B USCOL-ITEMS-END DROP",
        "_B USCOL-BUILDER-FINISH DROP _U !",
        "_VALIDATE _N",
        "_O _U @ _M 9 _X 4096 USITM-PACK _N _X SWAP _BYTES",
    ]
    groups, numbers = _run(program.lines)
    assert numbers == [0, 0]
    (payload,) = groups
    (item,) = decode_item_view_content(payload).items
    assert [f.text for f in item.fields] == ["a\ufffdb", "a\nb"]


def test_the_deep_validation_refuses_the_card_rules() -> None:
    card = [(1, 0, 0, 0, 0, ITEM, ["a", "b\nc"])]
    assert _validate_status(card, role=ItemViewRole.CARDS, columns=2,
                            column_flags=(0, WRAP), row=1) == 0
    # A line feed in a field whose column does not wrap.
    assert _validate_status(card, role=ItemViewRole.CARDS, columns=2) == 4
    # A wrapping column, or rows above the root, outside cards.
    assert _validate_status([(1, 0, 0, 0, 0, ITEM, ["a"])], role=ItemViewRole.LIST,
                            column_flags=(WRAP,)) == 4
    assert _validate_status([(1, 0, 0, 0, 0, ITEM, ["a"])], role=ItemViewRole.LIST,
                            row=1) == 4
    # A column flag the contract does not name.
    assert _validate_status([(1, 0, 0, 0, 0, ITEM, ["a"])], role=ItemViewRole.CARDS,
                            column_flags=(2,)) == 4
    # A card with a check box.
    assert _validate_status([(1, 0, 0, 0, CHK, ITEM, ["a"])],
                            role=ItemViewRole.CARDS) == 4
    # An empty view has its viewport at zero, rows included.
    assert _validate_status([], role=ItemViewRole.CARDS, row=1) == 4


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
        # The reserved field after the viewport row is not zero.
        "_CTL 1 _X 44 + C! _OK? 0 _X 44 + C!",
        # A text area carries no fields.
        "_CTL RTE-CONTROL-TEXT-AREA _C _RTE-CONTROL.KIND ! _OK?",
        "_CTL _OK?",
    ]
    _groups, numbers = _run(program.lines)
    assert numbers[: program.statuses] == [0] * program.statuses
    validate, pack, *verdicts = numbers[program.statuses :]
    assert (validate, pack) == (0, 0)
    assert verdicts == [-1, 0, 0, 0, 0, 0, 0, 0, 0, 0, -1]


# ---------------------------------------------------------------------
# Canonical widgets publish item views
# ---------------------------------------------------------------------

WIDGET_ROOTS = (
    "tui/widgets/tree.f",
    "tui/widgets/list.f",
    "tui/rich-terminal/uidl-semantic-items-itm1.f",
)

_CAPTURE = [
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
    # Validate the captured entry and pack it at content revision 9.
    ": _PUBLISH  ( -- )",
    "  _O _U @ _K 512 _M USCOL-ENTRY-VALIDATE _N",
    "  _O _U @ _M 9 _X 4096 USITM-PACK _N _X SWAP _BYTES ;",
]

_TREE = [
    "24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET",
    # Root -> (ChildA, ChildB -> Grandchild); four cells per node.
    "CREATE _TN 128 ALLOT",
    ': _TL-ROOT S" Root" ;',
    ': _TL-A    S" ChildA" ;',
    ': _TL-B    S" ChildB" ;',
    ': _TL-GC   S" Grandchild" ;',
    "_TN 32 + _TN ! 0 _TN 8 + ! _TL-ROOT _TN 24 + ! _TN 16 + !",
    "0 _TN 32 + ! _TN 64 + _TN 40 + ! _TL-A _TN 56 + ! _TN 48 + !",
    "_TN 96 + _TN 64 + ! 0 _TN 72 + ! _TL-B _TN 88 + ! _TN 80 + !",
    "0 _TN 96 + ! 0 _TN 104 + ! _TL-GC _TN 120 + ! _TN 112 + !",
    ": _TC  @ ;",
    ": _TN-NEXT  8 + @ ;",
    ": _TLB  DUP 16 + @ SWAP 24 + @ ;",
    ": _TLF  @ 0= ;",
    # Keys are node numbers from one.
    ": _TK  NIP _TN - 32 / 1+ ;",
    "VARIABLE _TW",
    "0 0 3 30 RGN-NEW _TN ' _TC ' _TN-NEXT ' _TLB ' _TLF ' _TK TREE-NEW _TW !",
    "_TW @ _TN TREE-EXPAND",
]


def test_a_tree_publishes_its_rows_and_carries_a_selection_out_of_view() -> None:
    program = _CAPTURE + _TREE + [
        "_TW @ _TN 64 + TREE-EXPAND",
        "_TW @ _TN 96 + TREE-SELECT",
        # Scroll back to the top: the selected Grandchild is below the view.
        "0 _TW @ TREE-SCROLL-SET",
        "42 _B _TW @ TREE-ITEM-VIEW-MEASURE _N _N",
        "42 _O 4096 _B _TW @ TREE-ITEM-VIEW-CAPTURE _N DUP _U ! _N",
        "_PUBLISH",
    ]
    output = _run_forth(program, roots=WIDGET_ROOTS).decode("utf-8", errors="replace")
    assert "not found" not in output and "underflow" not in output, output[-3000:]
    numbers = [int(value) for value in re.findall(r"\x02\s*(-?\d+)\s*\x03", output)]
    measure_status, measured, capture_status, copied, valid, packed = numbers
    assert (measure_status, capture_status, valid, packed) == (0, 0, 0, 0)
    assert measured == copied
    (payload,) = [
        bytes(int(token) for token in body.split())
        for body in re.findall("\x12(.*?)\x13", output, re.S)
    ]
    branch = S.EXPANDABLE | S.EXPANDED
    assert decode_item_view_content(payload) == ItemViewContent(
        9, ItemViewRole.TREE, ItemViewFlag(0), (ItemColumn(ItemColumnKind.TEXT, ""),),
        4, 0, 3,
        (
            _item(1, 0, "Root", state=branch),
            _item(2, 1, "ChildA", parent=1, depth=1),
            _item(3, 2, "ChildB", parent=1, depth=1, state=branch),
            _item(4, 3, "Grandchild", parent=3, depth=2, state=S.SELECTED),
        ),
    )


_TABLE = [
    "24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET",
    "CREATE _LCOLS LST-COLUMN-SIZE 2 * ALLOT",
    "_LCOLS LST-COLUMN-SIZE 2 * 0 FILL",
    ': _LNAME$ S" Name" ;',
    ': _LSIZE$ S" Size" ;',
    "LST-TEXT-COLUMN _LCOLS LST-COLUMN-KIND + !",
    "_LNAME$ _LCOLS LST-COLUMN-LABEL-U + ! _LCOLS LST-COLUMN-LABEL-A + !",
    "LST-NUMBER-COLUMN _LCOLS LST-COLUMN-SIZE + LST-COLUMN-KIND + !",
    "_LSIZE$ _LCOLS LST-COLUMN-SIZE + LST-COLUMN-LABEL-U + ! _LCOLS LST-COLUMN-SIZE + LST-COLUMN-LABEL-A + !",
    "6 _LCOLS LST-COLUMN-SIZE + LST-COLUMN-WIDTH + !",
    # Row n is named rn and is n * 10 bytes; keys are 100 + n.
    "CREATE _LBUF 8 ALLOT",
    ": _LNAME  ( index -- a u )  [CHAR] r _LBUF C! [CHAR] 0 + _LBUF 1+ C! _LBUF 2 ;",
    ": _LSIZE  ( index -- a u )  1+ 10 * DUP 10 / [CHAR] 0 + _LBUF 4 + C!",
    "  10 MOD [CHAR] 0 + _LBUF 5 + C! _LBUF 4 + 2 ;",
    ": _LK  ( index widget -- key )  DROP 100 + ;",
    ": _LTF  ( index column widget -- a u )  DROP IF _LSIZE ELSE _LNAME THEN ;",
    "VARIABLE _LW",
    # A two-row body under the header row.
    "0 0 3 30 RGN-NEW ' _LK ' _LTF LST-NEW _LW !",
    "_LCOLS 2 _LW @ LST-COLUMNS! 5 _LW @ LST-ROWS!",
]


def test_a_table_publishes_its_columns_view_and_selection() -> None:
    program = _CAPTURE + _TABLE + [
        "1 _LW @ LST-SELECT",
        # Scroll past the selection: rows 3 and 4 show, row 1 is selected.
        "3 _LW @ LST-SCROLL-SET",
        "42 _B _LW @ LST-ITEM-VIEW-MEASURE _N _N",
        "42 _O 4096 _B _LW @ LST-ITEM-VIEW-CAPTURE _N DUP _U ! _N",
        "_PUBLISH",
    ]
    output = _run_forth(program, roots=WIDGET_ROOTS).decode("utf-8", errors="replace")
    assert "not found" not in output and "underflow" not in output, output[-3000:]
    numbers = [int(value) for value in re.findall(r"\x02\s*(-?\d+)\s*\x03", output)]
    measure_status, measured, capture_status, copied, valid, packed = numbers
    assert (measure_status, capture_status, valid, packed) == (0, 0, 0, 0)
    assert measured == copied
    (payload,) = [
        bytes(int(token) for token in body.split())
        for body in re.findall("\x12(.*?)\x13", output, re.S)
    ]
    assert decode_item_view_content(payload) == ItemViewContent(
        9, ItemViewRole.TABLE, ItemViewFlag(0),
        (ItemColumn(ItemColumnKind.TEXT, "Name"), ItemColumn(ItemColumnKind.NUMBER, "Size")),
        5, 3, 2,
        (
            _item(101, 1, "r1", "20", state=S.SELECTED),
            _item(103, 3, "r3", "40"),
            _item(104, 4, "r4", "50"),
        ),
    )


# An agenda in sections: headings at rows 0, 2 and 5, and two columns, a
# title and a time.  Rows 3 and 4 have check boxes and row 4 is checked.
# Keys are 200 + row.
_AGENDA = [
    "24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET",
    "CREATE _SCOLS LST-COLUMN-SIZE 2 * ALLOT",
    "_SCOLS LST-COLUMN-SIZE 2 * 0 FILL",
    "LST-TEXT-COLUMN _SCOLS LST-COLUMN-KIND + !",
    "LST-TEXT-COLUMN _SCOLS LST-COLUMN-SIZE + LST-COLUMN-KIND + !",
    "5 _SCOLS LST-COLUMN-SIZE + LST-COLUMN-WIDTH + !",
    ': _S0 S" SCHEDULE" ; : _S1 S" Standup" ; : _S2 S" TASKS" ;',
    ': _S3 S" Buy milk" ; : _S4 S" Pay rent" ; : _S5 S" NOTES" ;',
    ': _S6 S" Idea" ; : _ST S" 09:30" ;',
    ": _STITLE  ( index -- a u )",
    "  CASE 0 OF _S0 ENDOF 1 OF _S1 ENDOF 2 OF _S2 ENDOF 3 OF _S3 ENDOF",
    "  4 OF _S4 ENDOF 5 OF _S5 ENDOF _S6 ROT ENDCASE ;",
    ": _SK  ( index widget -- key )  DROP 200 + ;",
    ": _SF  ( index column widget -- a u )",
    "  DROP IF 1 = IF _ST ELSE 0 0 THEN ELSE _STITLE THEN ;",
    ": _SR  ( index widget -- flags )  DROP",
    "  DUP 0= OVER 2 = OR SWAP 5 = OR IF LST-ROW-SECTION EXIT THEN",
    "  0 ;",
    ": _SRC  ( index widget -- flags )  OVER 3 = IF 2DROP LST-ROW-CHECKABLE EXIT THEN",
    "  OVER 4 = IF 2DROP LST-ROW-CHECKABLE LST-ROW-CHECKED OR EXIT THEN _SR ;",
    "VARIABLE _SW",
    "0 0 4 30 RGN-NEW ' _SK ' _SF LST-NEW _SW !",
    "_SCOLS 2 _SW @ LST-COLUMNS! ' _SRC _SW @ LST-ROW-FLAGS! 7 _SW @ LST-ROWS!",
]


def test_an_agenda_publishes_sections_with_check_boxes() -> None:
    program = _CAPTURE + _AGENDA + [
        # The first row that is not a heading starts selected.
        "_SW @ LST-SELECTED _N",
        # Show rows 3 to 6: the selected Standup is above the view, and row
        # 3's heading is too.
        "3 _SW @ LST-SCROLL-SET",
        "42 _B _SW @ LST-ITEM-VIEW-MEASURE _N _N",
        "42 _O 4096 _B _SW @ LST-ITEM-VIEW-CAPTURE _N DUP _U ! _N",
        "_PUBLISH",
    ]
    output = _run_forth(program, roots=WIDGET_ROOTS).decode("utf-8", errors="replace")
    assert "not found" not in output and "underflow" not in output, output[-3000:]
    numbers = [int(value) for value in re.findall(r"\x02\s*(-?\d+)\s*\x03", output)]
    selected, measure_status, measured, capture_status, copied, valid, packed = numbers
    assert selected == 1
    assert (measure_status, capture_status, valid, packed) == (0, 0, 0, 0)
    assert measured == copied
    (payload,) = [
        bytes(int(token) for token in body.split())
        for body in re.findall("\x12(.*?)\x13", output, re.S)
    ]
    box = S.CHECKABLE
    assert decode_item_view_content(payload) == ItemViewContent(
        9, ItemViewRole.SECTIONS, ItemViewFlag(0),
        (ItemColumn(ItemColumnKind.TEXT, ""), ItemColumn(ItemColumnKind.TEXT, "")),
        7, 3, 4,
        (
            _item(201, 1, "Standup", "09:30", parent=200, depth=1, state=S.SELECTED),
            _item(203, 3, "Buy milk", "", parent=202, depth=1, state=box),
            _item(204, 4, "Pay rent", "", parent=202, depth=1, state=box | S.CHECKED),
            _item(205, 5, "NOTES", role=ItemRole.SECTION),
            _item(206, 6, "Idea", "", parent=205, depth=1),
        ),
    )


CARD_ROOTS = WIDGET_ROOTS + ("text/syntax.f",)


def _forth_bytes(name: str, text: str | bytes) -> list[str]:
    data = text if isinstance(text, bytes) else text.encode("utf-8")
    return [f"CREATE {name} " + " ".join(f"{byte} C," for byte in data),
            f": {name}$  {name} {len(data)} ;"]


# Posts from outside the application as cards: a header line, the text,
# and a note.  Keys are 300 + row.  The second post's text holds a newline,
# a right-to-left override, a byte that cannot start a character, and a
# stray continuation byte.
_CARD_POST = "Read https://example.org/x now"
_CARD_ODD = b"a\nb\xe2\x80\xaec\xff\x80d"
_CARDS = [
    "24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET",
    *_forth_bytes("_C1", _CARD_POST),
    *_forth_bytes("_C2", _CARD_ODD),
    ': _CH0 S" @mira  09:30" ; : _CH1 S" @rowan  10:05" ;',
    ": _CK  ( index widget -- key )  DROP 300 + ;",
    ": _CF  ( index column widget -- a u )",
    "  DROP CASE",
    "    0 OF IF _CH1 ELSE _CH0 THEN ENDOF",
    "    1 OF IF _C2$ ELSE _C1$ THEN ENDOF",
    '    >R IF 0 0 ELSE S" reply" THEN R>',
    "  ENDCASE ;",
    ": _CSTYLE  ( text-a text-u map index column widget -- )  DROP DROP DROP SYN-SCAN-URLS ;",
    "CREATE _CCOLS LST-COLUMN-SIZE 3 * ALLOT",
    "_CCOLS LST-COLUMN-SIZE 3 * 0 FILL",
    "LST-TEXT-COLUMN _CCOLS LST-COLUMN-KIND + !",
    "LST-TEXT-COLUMN _CCOLS LST-COLUMN-SIZE + LST-COLUMN-KIND + !",
    "LST-TEXT-COLUMN _CCOLS LST-COLUMN-SIZE 2 * + LST-COLUMN-KIND + !",
    "VARIABLE _CW",
    # Six rows show two three-line cards.
    "0 0 6 30 RGN-NEW ' _CK ' _CF LST-NEW _CW !",
    "_CCOLS 3 _CW @ LST-COLUMNS! LST-CARDS LST-UNTRUSTED OR _CW @ LST-MODE!",
    "' _CSTYLE _CW @ LST-STYLE! 2 _CW @ LST-ROWS!",
]


def test_cards_publish_their_lines_style_runs_and_safe_text() -> None:
    program = _CAPTURE + _CARDS + [
        "1 _CW @ LST-SELECT",
        "42 _B _CW @ LST-ITEM-VIEW-MEASURE _N _N",
        "42 _O 4096 _B _CW @ LST-ITEM-VIEW-CAPTURE _N DUP _U ! _N",
        "_PUBLISH",
    ]
    output = _run_forth(program, roots=CARD_ROOTS).decode("utf-8", errors="replace")
    assert "not found" not in output and "underflow" not in output, output[-3000:]
    numbers = [int(value) for value in re.findall(r"\x02\s*(-?\d+)\s*\x03", output)]
    measure_status, measured, capture_status, copied, valid, packed = numbers
    assert (measure_status, capture_status, valid, packed) == (0, 0, 0, 0)
    assert measured == copied
    (payload,) = [
        bytes(int(token) for token in body.split())
        for body in re.findall("\x12(.*?)\x13", output, re.S)
    ]
    link = StyleRun(5, len("https://example.org/x"), TextStyle.LINK)
    text = ItemColumn(ItemColumnKind.TEXT, "")
    assert decode_item_view_content(payload) == ItemViewContent(
        9, ItemViewRole.CARDS, ItemViewFlag(0), (text, text, text),
        2, 0, 2,
        (
            _item(300, 0, "@mira  09:30", ItemField(_CARD_POST, (link,)), "reply"),
            # The newline and each byte that is not UTF-8 show as U+FFFD,
            # as CELL shows them, and the override as an invisible U+200B
            # that reorders nothing.
            _item(301, 1, "@rowan  10:05", "a\ufffdb\u200bc\ufffd\ufffdd", "",
                  state=S.SELECTED),
        ),
    )


# Card lists whose text column wraps, each in its own region.  Every field
# lives in one table, addressed by list, row and column; a list's context
# is its number, and its keys are 1000 * list + row + 1.
def _wrap_lists(cases: list[dict]) -> list[str]:
    lines = [
        "24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET",
        f"CREATE _WT {len(cases) * 128 * 16} ALLOT",
        ": _WT@  ( list index column -- a u )",
        "  SWAP 2 * + SWAP 128 * + 16 * _WT + DUP @ SWAP 8 + @ ;",
        ": _WK  ( index widget -- key )  LST-CONTEXT@ 1000 * + 1+ ;",
        ": _WF  ( index column widget -- a u )  LST-CONTEXT@ ROT ROT _WT@ ;",
        "CREATE _WCOLS LST-COLUMN-SIZE 2 * ALLOT",
        "_WCOLS LST-COLUMN-SIZE 2 * 0 FILL",
        "LST-TEXT-COLUMN _WCOLS LST-COLUMN-KIND + !",
        "LST-TEXT-COLUMN _WCOLS LST-COLUMN-SIZE + LST-COLUMN-KIND + !",
        "LST-COLUMN-WRAP _WCOLS LST-COLUMN-SIZE + LST-COLUMN-FLAGS + !",
        f"CREATE _WL {len(cases) * 8} ALLOT",
    ]
    for number, case in enumerate(cases):
        for index, fields in enumerate(case["cards"]):
            for column, text in enumerate(fields):
                name = f"_W{number}_{index}_{column}"
                data = text.encode("utf-8")
                lines.append(f"CREATE {name} " + " ".join(f"{b} C," for b in data))
                slot = ((number * 64 + index) * 2 + column) * 16
                lines.append(f"{name} _WT {slot} + ! {len(data)} _WT {slot} + 8 + !")
        lines += [
            f"0 0 {case['height']} {case['width']} RGN-NEW ' _WK ' _WF LST-NEW",
            f"DUP _WL {number * 8} + ! {number} OVER LST-CONTEXT!",
            f"_WCOLS 2 2 PICK LST-COLUMNS! LST-CARDS OVER LST-MODE!",
            f"{len(case['cards'])} SWAP LST-ROWS!",
            f"{case['offset']} _WL {number * 8} + @ LST-SCROLL-SET",
        ]
    return lines


def _wrap_capture(cases: list[dict]) -> list[tuple]:
    program = _CAPTURE + _wrap_lists(cases)
    for number in range(len(cases)):
        program += [
            f"_WL {number * 8} + @ LST-SCROLL-INFO _N _N _N",
            f"42 _O 4096 _B _WL {number * 8} + @ LST-ITEM-VIEW-CAPTURE _N DUP _U ! _N",
            "_PUBLISH",
        ]
    output = _run_forth(program, roots=CARD_ROOTS).decode("utf-8", errors="replace")
    assert "not found" not in output and "underflow" not in output, output[-3000:]
    numbers = [int(value) for value in re.findall(r"\x02\s*(-?\d+)\s*\x03", output)]
    payloads = [
        bytes(int(token) for token in body.split())
        for body in re.findall("\x12(.*?)\x13", output, re.S)
    ]
    results = []
    for number in range(len(cases)):
        visible, offset, total, status, _bytes, valid, packed = numbers[number * 7 : number * 7 + 7]
        assert (status, valid, packed) == (0, 0, 0), (number, status, valid, packed)
        results.append((total, offset, visible, decode_item_view_content(payloads[number])))
    return results


def _check_wrap_capture(case: dict, total: int, offset: int, visible: int,
                        content: ItemViewContent) -> None:
    """The published view is the one the terminal lays out: its viewport
    row lies inside its first card, and its viewport holds exactly the
    cards with a row in the body, by MegaPad's own row count."""

    from rich_terminal.semantic_items import card_row_count

    width, height = case["width"], case["height"]
    assert content.role is ItemViewRole.CARDS
    assert content.columns[1].wrap and not content.columns[0].wrap
    shown = content.shown_items()
    by_ordinal = {item.ordinal: item for item in content.items}
    rows = []
    for ordinal, fields in enumerate(case["cards"]):
        item = by_ordinal.get(ordinal)
        if item is None:
            # Not carried: count it from its text, as the terminal would.
            item = ViewItem(1, 0, ordinal, 0, ItemState(0), ItemRole.ITEM,
                            tuple(ItemField(t.replace("‮", "")) for t in fields))
        rows.append(card_row_count(content, item, width))
    assert total == sum(rows)
    assert visible == height
    first = content.viewport_first
    assert content.viewport_row < rows[first]
    assert offset == sum(rows[:first]) + content.viewport_row
    # The viewport is the cards with a row in the body.
    used, count = -content.viewport_row, 0
    for ordinal in range(first, len(rows)):
        if used >= height:
            break
        used += rows[ordinal]
        count += 1
    assert content.viewport_count == count == len(shown)
    # Nothing is left below while rows above are hidden.
    assert offset == 0 or offset + height <= total


def test_wrapping_cards_publish_their_viewport_row_and_line_feeds() -> None:
    case = {
        "width": 30, "height": 6, "offset": 2,
        "cards": [
            ("@mira", "The quick brown fox jumps over the lazy dog and keeps"
                      " running\nsecond paragraph"),
            ("@rowan", "short"),
            ("@kai", "a\n\nb"),
        ],
    }
    ((total, offset, visible, content),) = _wrap_capture([case])
    _check_wrap_capture(case, total, offset, visible, content)
    assert (content.viewport_first, content.viewport_row) == (0, 2)
    assert content.items[0].fields[1].text == case["cards"][0][1]
    assert content.items[2].fields[1].text == "a\n\nb"


def test_wrapping_cards_agree_with_the_terminal_on_random_lists() -> None:
    import random

    words = ["a", "bb", "ccc", "word", "longerword", "שלום",
             "中文", "x" * 23, "مرحبا"]
    generator = random.Random(28092026)
    cases = []
    for _ in range(10):
        cards = []
        for _ in range(generator.randint(1, 7)):
            text = ""
            for _ in range(generator.randint(0, 14)):
                text += generator.choice(words) + generator.choice([" ", " ", "  ", "\n"])
            cards.append((generator.choice(["@a", "@bee", "@c d"]), text))
        cases.append({
            "width": generator.randint(5, 40),
            "height": generator.randint(1, 9),
            "offset": generator.randint(0, 30),
            "cards": cards,
        })
    # Right-to-left text is costly to lay out, so a few lists per run keep
    # each run within its step budget.
    for start in range(0, len(cases), 3):
        batch = cases[start:start + 3]
        for case, (total, offset, visible, content) in zip(batch, _wrap_capture(batch)):
            _check_wrap_capture(case, total, offset, visible, content)
