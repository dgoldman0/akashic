#!/usr/bin/env python3
"""frame-shadow.f counts each shortcut's comparison and keeps the first difference."""

from test_field_model import PRELUDE, run_field

MODULES = ("tui/rich-terminal/frame-shadow.f",)


def run(program, minimum=1):
    run_field(PRELUDE + program, minimum=minimum, extra_sources=MODULES)


SPANS = r'''
CREATE _FS-X 32 ALLOT CREATE _FS-Y 32 ALLOT
: _FS-FILL ( -- ) 32 0 DO I _FS-X I + C! I _FS-Y I + C! LOOP ;
'''


def test_the_check_is_off_until_turned_on_and_counts_equal_results():
    run(SPANS + r'''
FSHD? 0= _FM-A
-1 FSHD-ON ! FSHD? _FM-A 0 FSHD-ON ! FSHD? 0= _FM-A
FSHD-RESET _FS-FILL
_FS-X 32 _FS-Y 32 7 FSHD-STAGE-SNAPSHOT FSHD-SAME? _FM-A
\ Two empty results are equal without reading either.
0 0 0 0 1 FSHD-STAGE-SNAPSHOT FSHD-SAME? _FM-A
FSHD-CHECKS @ 2 = _FM-A FSHD-MISMATCHES @ 0= _FM-A
FSHD-FIRST-STAGE @ 0= _FM-A
_FM-DONE
''', minimum=8)


def test_the_first_difference_is_kept_and_later_ones_only_counted():
    run(SPANS + r'''
FSHD-RESET _FS-FILL 99 _FS-Y 5 + C! 42 FSHD-DRAW !
_FS-X 32 _FS-Y 32 3 FSHD-STAGE-SHELL-GLYPHS FSHD-SAME? 0= _FM-A
FSHD-MISMATCHES @ 1 = _FM-A
FSHD-FIRST-STAGE @ FSHD-STAGE-SHELL-GLYPHS = _FM-A
FSHD-FIRST-ITEM @ 3 = _FM-A FSHD-FIRST-OFFSET @ 5 = _FM-A
FSHD-FIRST-DRAW @ 42 = _FM-A
\ A shorter result differs where it ends, even when its bytes agree.
43 FSHD-DRAW !
_FS-X 32 _FS-X 16 9 FSHD-STAGE-PRODUCER-MENUS FSHD-SAME? 0= _FM-A
FSHD-MISMATCHES @ 2 = _FM-A FSHD-CHECKS @ 2 = _FM-A
FSHD-FIRST-STAGE @ FSHD-STAGE-SHELL-GLYPHS = _FM-A
FSHD-FIRST-OFFSET @ 5 = _FM-A FSHD-FIRST-DRAW @ 42 = _FM-A
FSHD-RESET FSHD-MISMATCHES @ 0= _FM-A FSHD-FIRST-OFFSET @ 0= _FM-A
_FS-X 32 _FS-X 16 9 FSHD-STAGE-PRODUCER-MENUS FSHD-SAME? 0= _FM-A
FSHD-FIRST-OFFSET @ 16 = _FM-A FSHD-FIRST-ITEM @ 9 = _FM-A
FSHD-FIRST-DRAW @ 43 = _FM-A
_FM-DONE
''', minimum=17)


def test_scratch_blocks_grow_in_their_own_variables_and_go_back_to_the_heap():
    run(r'''
VARIABLE _FS-A VARIABLE _FS-U VARIABLE _FS-A2 VARIABLE _FS-U2 VARIABLE _FS-B
0 _FS-A ! 0 _FS-U ! 0 _FS-A2 ! 0 _FS-U2 !
100 _FS-A _FS-U FSHD-GROW DUP 0<> _FM-A _FS-B !
_FS-B @ 7 AND 0= _FM-A _FS-A @ _FS-B @ = _FM-A _FS-U @ 100 = _FM-A
\ A smaller request keeps the block; a larger one replaces it.
40 _FS-A _FS-U FSHD-GROW _FS-B @ = _FM-A
1000 _FS-A _FS-U FSHD-GROW DUP 0<> _FM-A _FS-B ! _FS-U @ 1000 = _FM-A
_FS-B @ 1000 0 FILL
\ Another stage's block is its own.
10 _FS-A2 _FS-U2 FSHD-GROW DUP 0<> _FM-A _FS-B @ <> _FM-A
_FS-A _FS-U FSHD-FREE _FS-A @ 0= _FM-A _FS-U @ 0= _FM-A
_FS-A2 _FS-U2 FSHD-FREE
FSHD-RESET FSHD-SKIP FSHD-SKIPPED @ 1 = _FM-A
FSHD-RESET FSHD-SKIPPED @ 0= _FM-A
_FM-DONE
''', minimum=13)
