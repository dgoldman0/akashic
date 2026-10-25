#!/usr/bin/env python3
"""The widget revision counts changes to what a widget shows, and only them."""

from test_field_model import PRELUDE, run_field

MODULES = ("tui/widget.f",)


def run(program, minimum):
    run_field(PRELUDE + WIDGET + program, minimum=minimum, extra_sources=MODULES)


# A label-typed header, made clean, and words that report how far its
# revision moved since _WR-MARK.
WIDGET = r'''
CREATE _WR-W 48 ALLOT
: _WR-NOP  ( widget -- ) DROP ;
: _WR-NOH  ( event widget -- consumed? ) 2DROP 0 ;
_WR-W WDG-T-LABEL 0 ' _WR-NOP ' _WR-NOH WDG-INIT
VARIABLE _WR-R
: _WR-MARK  ( -- ) _WR-W WDG-REVISION _WR-R ! ;
: _WR-MOVED  ( -- n ) _WR-W WDG-REVISION _WR-R @ - ;
: _WR-CLEAN  ( -- ) _WR-W WDG-CLEAN _WR-MARK ;
'''


def test_a_new_widget_starts_at_zero_and_wdg_dirty_moves_it():
    run(r'''
_WR-W WDG-REVISION 0= _FM-A
_WR-W WDG-VISIBLE? _FM-A _WR-W WDG-DIRTY? _FM-A
_WR-CLEAN
_WR-W WDG-DIRTY _WR-MOVED 1 = _FM-A _WR-W WDG-DIRTY? _FM-A
_WR-W WDG-DIRTY _WR-W WDG-DIRTY _WR-MOVED 3 = _FM-A
_FM-DONE
''', minimum=6)


def test_painting_clears_dirty_and_leaves_the_revision_and_flags_alone():
    run(r'''
_WR-W WDG-DIRTY _WR-W WDG-FOCUS-SET _WR-W WDG-DISABLE
_WR-MARK _WR-W WDG-CLEAN
_WR-MOVED 0= _FM-A _WR-W WDG-DIRTY? 0= _FM-A
\ The revision's bits leave every flag query as it was.
_WR-W WDG-VISIBLE? _FM-A _WR-W WDG-FOCUSED? _FM-A _WR-W WDG-DISABLED? _FM-A
_WR-W WDG-FLAGS 65535 AND WDG-F-VISIBLE WDG-F-FOCUSED OR WDG-F-DISABLED OR = _FM-A
_FM-DONE
''', minimum=6)


def test_each_base_word_that_changes_a_flag_moves_the_revision_and_marks_dirty():
    run(r'''
: _WR-ONCE ( xt -- ) _WR-CLEAN _WR-W SWAP EXECUTE
    _WR-MOVED 1 = _FM-A _WR-W WDG-DIRTY? _FM-A ;
' WDG-HIDE _WR-ONCE _WR-W WDG-VISIBLE? 0= _FM-A
' WDG-SHOW _WR-ONCE _WR-W WDG-VISIBLE? _FM-A
' WDG-DISABLE _WR-ONCE _WR-W WDG-DISABLED? _FM-A
' WDG-ENABLE _WR-ONCE _WR-W WDG-DISABLED? 0= _FM-A
' WDG-FOCUS-SET _WR-ONCE _WR-W WDG-FOCUSED? _FM-A
' WDG-FOCUS-CLR _WR-ONCE _WR-W WDG-FOCUSED? 0= _FM-A
_FM-DONE
''', minimum=18)


def test_a_base_word_that_changes_nothing_moves_nothing():
    run(r'''
: _WR-NONE ( xt -- ) _WR-CLEAN _WR-W SWAP EXECUTE _WR-MOVED 0= _FM-A ;
\ Visible, enabled and unfocused already.
' WDG-SHOW _WR-NONE ' WDG-ENABLE _WR-NONE ' WDG-FOCUS-CLR _WR-NONE
\ Hiding a hidden widget marks nothing either.
_WR-W WDG-HIDE ' WDG-HIDE _WR-NONE _WR-W WDG-DIRTY? 0= _FM-A
_WR-W WDG-SHOW _WR-W WDG-DISABLE ' WDG-DISABLE _WR-NONE
_WR-W WDG-FOCUS-SET ' WDG-FOCUS-SET _WR-NONE
_FM-DONE
''', minimum=7)


def test_wdg_flag_store_marks_only_a_change():
    run(r'''
_WR-CLEAN -1 WDG-F-FOCUSED _WR-W WDG-FLAG!
_WR-MOVED 1 = _FM-A _WR-W WDG-FOCUSED? _FM-A _WR-W WDG-DIRTY? _FM-A
\ Keeping a widget's state in step with an owner's changes nothing.
_WR-CLEAN -1 WDG-F-FOCUSED _WR-W WDG-FLAG!
_WR-MOVED 0= _FM-A _WR-W WDG-DIRTY? 0= _FM-A
_WR-CLEAN 0 WDG-F-FOCUSED _WR-W WDG-FLAG!
_WR-MOVED 1 = _FM-A _WR-W WDG-FOCUSED? 0= _FM-A
_WR-CLEAN 0 WDG-F-DISABLED _WR-W WDG-FLAG!
_WR-MOVED 0= _FM-A _WR-W WDG-DIRTY? 0= _FM-A
_FM-DONE
''', minimum=9)
