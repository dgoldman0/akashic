#!/usr/bin/env python3
"""Queries and captures of a list or a tree change nothing: not the
selection, not the scroll, not the revision.  They report what the rows
allow; the words that change the widget, and its draw, settle it."""

from test_field_model import PRELUDE, run_field

MODULES = ("tui/widgets/list.f", "tui/widgets/tree.f")


def run(program, minimum):
    run_field(PRELUDE + r'''
24 80 SCR-NEW SCR-USE
VARIABLE _WQ-R
: _WQ-MARK  ( w -- ) WDG-REVISION _WQ-R ! ;
: _WQ-SAME?  ( w -- flag ) WDG-REVISION _WQ-R @ = ;
: _LQ-KEY  ( index widget -- key ) DROP 1+ ;
: _LQ-FIELD  ( index column widget -- addr len ) 2DROP DROP S" row" ;
''' + program, minimum=minimum, extra_sources=MODULES)


def test_list_queries_report_the_settled_selection_and_change_nothing():
    run(r'''
0 0 3 20 RGN-NEW ' _LQ-KEY ' _LQ-FIELD LST-NEW CONSTANT _LQ
10 _LQ LST-RECOUNT  7 _LQ LST-SELECT  _LQ WDG-DRAW
_LQ LST-SELECTED 7 = _FM-A
\ The rows go down to two behind the list's back.  The queries report the
\ selection and the view two rows allow, and move neither, nor the
\ revision.
2 _LQ _LST-O-COUNT + !
_LQ _WQ-MARK
_LQ LST-SELECTED 1 = _FM-A
_LQ LST-SCROLL-INFO DROP 0= _FM-A 2 = _FM-A
_LQ _WQ-SAME? _FM-A
_LQ _LST-O-SEL + @ 7 = _FM-A
\ The draw settles them on the rows there are.
_LQ WDG-DRAW
_LQ _LST-O-SEL + @ 1 = _FM-A
_FM-DONE
''', minimum=7)


def test_list_scroll_info_follows_a_grown_body_without_moving_the_view():
    run(r'''
\ Ten rows at the end of a three-row body; then the region grows to eight,
\ as a container resizes its child before the list draws.
0 0 3 20 RGN-NEW ' _LQ-KEY ' _LQ-FIELD LST-NEW CONSTANT _LV
10 _LV LST-RECOUNT  _LV LST-SCROLL-END  _LV WDG-DRAW
VARIABLE _LV-TOP  _LV _LST-O-SCROLL + @ _LV-TOP !
_LV-TOP @ 0> _FM-A
0 0 8 20 _LV WDG-REGION RGN-BOUNDS!
_LV _WQ-MARK
\ The view the rows allow ends at the last row: offset = content - body.
: _LV-AT-END?  ( content offset visible -- flag ) ROT SWAP - = ;
_LV LST-SCROLL-INFO _LV-AT-END? _FM-A
_LV LST-SCROLL-INFO DROP NIP _LV-TOP @ < _FM-A
_LV _WQ-SAME? _FM-A
_LV _LST-O-SCROLL + @ _LV-TOP @ = _FM-A
_LV WDG-DRAW
_LV _LST-O-SCROLL + @ _LV-TOP @ < _FM-A
_FM-DONE
''', minimum=6)


def test_tree_queries_report_the_settled_selection_and_change_nothing():
    run(r'''
\ A root with _TQ-N children, numbered 2 on; a node's key is the node.
VARIABLE _TQ-N  3 _TQ-N !
: _TQ-CHILDREN  ( node -- first|0 ) 1 = _TQ-N @ 0> AND IF 2 ELSE 0 THEN ;
: _TQ-NEXT  ( node -- sibling|0 ) DUP 1 > OVER _TQ-N @ 1+ < AND IF 1+ ELSE DROP 0 THEN ;
: _TQ-LABEL  ( node -- addr len ) DROP S" node" ;
: _TQ-LEAF?  ( node -- flag ) 1 > ;
: _TQ-KEYS  ( parent-key node -- key ) NIP ;
0 0 3 20 RGN-NEW 1 ' _TQ-CHILDREN ' _TQ-NEXT ' _TQ-LABEL ' _TQ-LEAF? ' _TQ-KEYS
    TREE-NEW CONSTANT _TQ
_TQ TREE-EXPAND-ALL  _TQ 4 TREE-SELECT  _TQ WDG-DRAW
_TQ TREE-SELECTED-KEY 4 = _FM-A
\ Node 4 goes behind the tree's back.  The queries report the selection a
\ settle would leave, without moving it, the scroll or the revision.
2 _TQ-N !
_TQ _WQ-MARK
_TQ TREE-SELECTED-KEY 4 <> _FM-A
_TQ TREE-SELECTED 0<> _FM-A
_TQ TREE-SCROLL-INFO 2DROP DROP
_TQ _WQ-SAME? _FM-A
_TQ _TREE-O-CURSOR + @ 4 = _FM-A
\ The draw settles it on a shown row.
_TQ WDG-DRAW
_TQ _TREE-O-CURSOR + @ 4 <> _FM-A
_FM-DONE
''', minimum=6)
