"""Execute the production shell loop with deterministic input, clock and sinks.

Transport, app dispatch and draw sinks are deterministic doubles. The loop,
deferred FIFO, quit signal and tick policy are production Forth definitions.
"""
import os
from pathlib import Path
import re
import struct
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
MEGAPAD_ROOT = Path(os.environ.get('MEGAPAD_ROOT', ROOT.parent / 'megapad'))
sys.path.insert(0, str(MEGAPAD_ROOT))
from simulator.runtime import MegaForthRuntime

SOURCE = ROOT / 'akashic/tui/app-shell.f'
MASK64 = (1 << 64) - 1
BUDGET = 3_000_000


def definition(source, name):
    source = re.sub(r'(?m)\\[^\n]*$', '', source)
    match = re.search(r'(?ms)^: ' + re.escape(name) + r'(?=\s).*?;[ \t]*$', source)
    assert match, name
    return match[0]


class ShellLoop:
    def __init__(self, backend='native', *, source=None):
        source = SOURCE.read_text() if source is None else source
        self.runtime = MegaForthRuntime(execution_backend=backend)
        kdos = (MEGAPAD_ROOT / 'kdos.f').read_text()
        exceptions = kdos[kdos.index('CREATE _HANDLERS'):kdos.index('\\ BIOS dictionary emitters')]
        self.runtime.evaluate(exceptions.encode(), step_budget=BUDGET)
        prelude = r'''
        VARIABLE _ASHELL-RUNNING VARIABLE _ASHELL-DIRTY
        VARIABLE _ASHELL-TERM-OWNS VARIABLE _ASHELL-INST
        VARIABLE _ASHELL-TICK-MS VARIABLE _ASHELL-LAST-TICK
        VARIABLE _ASHELL-TICK-TMP VARIABLE _ASHELL-TOAST-WAS-VIS
        VARIABLE _UTUI-NEEDS-PAINT
        VARIABLE _ASHELL-DESC CREATE TEST-DESC 8 ALLOT
        TEST-DESC _ASHELL-DESC !
        : APP.TICK-XT ;
        CREATE _ASHELL-EV 24 ALLOT
        16 CONSTANT _ASHELL-POST-MAX
        CREATE _ASHELL-POST-Q _ASHELL-POST-MAX CELLS ALLOT
        VARIABLE _ASHELL-POST-HEAD VARIABLE _ASHELL-POST-TAIL
        VARIABLE TEST-NOW : MS@ TEST-NOW @ ;
        VARIABLE TEST-DRAW : SCR-DRAW-GENERATION@ TEST-DRAW @ ;
        : _ASHELL-ACTIVATE ;
        : ASHELL-TOAST-VISIBLE? -1 ;
        : _ASHELL-DIRTY-TOAST-RECT ;
        CREATE TEST-QUEUE 3072 ALLOT
        VARIABLE TEST-COUNT VARIABLE TEST-NEXT
        CREATE TEST-TRACE 16384 ALLOT VARIABLE TEST-TRACE-N
        : RECORD  ( value kind -- )
            TEST-TRACE-N @ 16 * TEST-TRACE + DUP ROT SWAP ! 8 + !
            1 TEST-TRACE-N +! ;
        VARIABLE TEST-FOCUS
        CREATE TEST-LENGTHS 16 ALLOT
        CREATE TEST-TEXT 2048 ALLOT
        : TEST-LENGTH  TEST-FOCUS @ 8 * TEST-LENGTHS + ;
        VARIABLE TEST-COST VARIABLE TEST-STOP-CODE
        VARIABLE TEST-POST-QUIT VARIABLE TEST-TICK-QUIT
        VARIABLE TEST-SERVICE-QUIT VARIABLE TEST-SERVICE-FAULT
        VARIABLE TEST-MODAL-CODE
        VARIABLE TEST-PAINTS VARIABLE TEST-STOP-PAINTS
        VARIABLE TEST-INJECT-YIELD
        '''
        keys = (ROOT / 'akashic/tui/keys.f').read_text()
        constants = '\n'.join(re.findall(r'(?m)^\d+ CONSTANT KEY-\S+.*$', keys))
        # The private budget and scratch belong to the actual drain helper.
        drain_state = ''
        if ': _ASHELL-DRAIN-INPUT ' in source:
            drain_state = '\n'.join(re.findall(
                r'(?m)^(?:\d+ CONSTANT _ASHELL-INPUT-\S+|VARIABLE _ASHELL-INPUT-\S+).*$', source))
        words = [definition(source, name) for name in (
            'ASHELL-QUIT', 'ASHELL-DIRTY!', 'ASHELL-POST', '_ASHELL-DRAIN-POSTED')]
        callbacks = r'''
        : TEST-POSTED
            TEST-FOCUS @ 1 XOR TEST-FOCUS !
            TEST-FOCUS @ 4 RECORD
            TEST-POST-QUIT @ IF ASHELL-QUIT THEN ;
        : _ASHELL-TERM-SERVICE
            TEST-NEXT @ 1 RECORD
            TEST-SERVICE-QUIT @ IF ASHELL-QUIT THEN
            TEST-SERVICE-FAULT @ IF -91 THROW THEN ;
        : _ASHELL-POLL-INPUT
            TEST-NEXT @ 2 RECORD
            TEST-NEXT @ TEST-COUNT @ >= IF 0 EXIT THEN
            TEST-QUEUE TEST-NEXT @ 24 * + _ASHELL-EV 24 CMOVE
            1 TEST-NEXT +! -1 ;
        : _ASHELL-DISPATCH-KEY
            TEST-FOCUS @ 1000 * OVER 8 + @ + 3 RECORD
            DUP 8 + @ TEST-STOP-CODE @ = IF DROP ASHELL-QUIT EXIT THEN
            DUP 8 + @ TEST-MODAL-CODE @ = IF 1 TEST-DRAW +! THEN
            DUP @ KEY-T-SPECIAL = IF
                DUP 8 + @ KEY-TAB = IF ['] TEST-POSTED ASHELL-POST THEN
                DUP 8 + @ KEY-BACKSPACE = IF
                    TEST-LENGTH DUP @ 1- 0 MAX SWAP !
                THEN
            THEN
            DUP @ KEY-T-CHAR = IF
                DUP 8 + @ TEST-TEXT TEST-FOCUS @ 1024 * +
                    TEST-LENGTH @ 8 * + !
                1 TEST-LENGTH +!
            THEN DROP
            TEST-COST @ TEST-NOW +!
            ASHELL-DIRTY! ;
        : _ASHELL-DISPATCH-MOUSE DROP TEST-NEXT @ 8 RECORD ;
        : _ASHELL-CHECK-RESIZE
            @ KEY-T-RESIZE = IF TEST-NEXT @ 9 RECORD THEN ;
        : _ASHELL-CHECK-HW-RESIZE TEST-NEXT @ 10 RECORD ;
        : TEST-TICK
            DROP TEST-NEXT @ 5 RECORD
            TEST-TICK-QUIT @ IF ASHELL-QUIT THEN ;
        : _ASHELL-PAINT
            TEST-NEXT @ 6 RECORD
            1 TEST-PAINTS +!
            TEST-PAINTS @ TEST-STOP-PAINTS @ >= IF ASHELL-QUIT THEN ;
        : YIELD?
            TEST-NEXT @ 7 RECORD
            TEST-INJECT-YIELD @ ?DUP IF
                TEST-COUNT ! 0 TEST-INJECT-YIELD !
            THEN ;
        '''
        words += [callbacks, definition(source, '_ASHELL-CHECK-TICK')]
        if drain_state:
            words += [drain_state, definition(source, '_ASHELL-DRAIN-INPUT')]
        words += [definition(source, '_ASHELL-LOOP'),
                  ": TEST-RUN ['] _ASHELL-LOOP CATCH ;"]
        self.runtime.evaluate((prelude + constants + '\n' + '\n'.join(words)).encode(),
                              step_budget=BUDGET)
        self.set('_ASHELL-RUNNING', MASK64)
        self.set('_ASHELL-TERM-OWNS', MASK64)
        self.set('_ASHELL-TICK-MS', 50)
        self.set('TEST-STOP-PAINTS', 1)
        self.set('TEST-STOP-CODE', MASK64)
        self.set('TEST-MODAL-CODE', MASK64)

    def address(self, name):
        return self.runtime.find(name).body_address

    def get(self, name):
        return self.runtime.memory.read64(self.address(name))

    def set(self, name, value):
        self.runtime.memory.write64(self.address(name), value & MASK64)

    def queue(self, events):
        payload = b''.join(struct.pack('<3Q', *event) for event in events)
        assert len(payload) <= 3072
        self.runtime.memory.write_bytes(self.address('TEST-QUEUE'), payload)
        self.set('TEST-COUNT', len(events))

    def tick(self, interval):
        self.set('_ASHELL-TICK-MS', interval)
        self.runtime.memory.write64(self.address('TEST-DESC'), self.runtime.find('TEST-TICK').xt)

    def run(self):
        self.runtime.execute('TEST-RUN', step_budget=BUDGET)
        data = self.runtime.main_context.data
        result = data.pop()
        assert data.snapshot() == ()
        assert self.runtime.main_context.returns.snapshot() == ()
        return result

    def trace(self, kind=None):
        address = self.address('TEST-TRACE')
        rows = [tuple(self.runtime.memory.read64(address + i * 16 + j * 8)
                      for j in range(2)) for i in range(self.get('TEST-TRACE-N'))]
        return rows if kind is None else [value for tag, value in rows if tag == kind]

    def text(self, focus=0):
        length = self.runtime.memory.read64(self.address('TEST-LENGTHS') + focus * 8)
        return ''.join(chr(self.runtime.memory.read64(self.address('TEST-TEXT') + focus * 1024 + i * 8))
                       for i in range(length))


def chars(text):
    return [(0, ord(c), 0) for c in text]


@pytest.fixture(params=('python', 'native'))
def shell(request):
    return ShellLoop(request.param)


def test_ready_keys_and_backspace_preserve_order_with_one_paint(shell):
    shell.queue(chars('ab') + [(1, 27, 0)] + chars('c'))
    assert shell.run() == 0
    assert shell.text() == 'ac'
    assert shell.trace(3) == [ord('a'), ord('b'), 27, ord('c')]
    assert shell.trace(6) == [4]


def test_posted_focus_transition_precedes_next_queued_key(shell):
    shell.queue(chars('a') + [(1, 24, 0)] + chars('b'))
    assert shell.run() == 0
    assert (shell.text(0), shell.text(1)) == ('a', 'b')
    trace = shell.trace()
    assert trace.index((3, 24)) < trace.index((4, 1)) < trace.index((3, 1000 + ord('b')))
    assert shell.trace(6) == [3]


def test_empty_queue_does_not_wait_for_a_later_key(shell):
    shell.queue(chars('a'))
    shell.set('TEST-COUNT', 0)
    shell.set('TEST-INJECT-YIELD', 1)
    shell.set('TEST-STOP-PAINTS', 2)
    assert shell.run() == 0
    assert shell.trace(6) == [0, 1]
    assert shell.trace(7) == [0]


def test_time_slice_yields_and_ticks_without_losing_backlog(shell):
    shell.queue(chars('abcdefghijklmnopqrst'))
    shell.set('TEST-COST', 1)
    shell.set('TEST-STOP-PAINTS', 3)
    shell.tick(4)
    assert shell.run() == 0
    assert shell.text() == 'abcdefghijklmnopqrst'
    assert shell.trace(6) == [8, 16, 20]
    assert shell.trace(7) == [8, 16]
    assert shell.trace(5) == [4, 8, 12, 16, 20]


def test_slow_callback_finishes_but_does_not_start_another_key(shell):
    shell.queue(chars('ab'))
    shell.set('TEST-COST', 9)
    assert shell.run() == 0
    assert shell.text() == 'a' and shell.get('TEST-NEXT') == 1


def test_elapsed_budget_survives_uptime_wrap(shell):
    shell.queue(chars('abcdefghij'))
    shell.set('TEST-NOW', MASK64 - 3)
    shell.set('TEST-COST', 1)
    assert shell.run() == 0
    assert shell.trace(6) == [8]


@pytest.mark.parametrize('stop', ('event', 'posted', 'tick', 'service'))
def test_stop_prevents_another_key_paint_or_yield(shell, stop):
    shell.queue([(1, 24, 0)] + chars('b'))
    if stop == 'event':
        shell.set('TEST-STOP-CODE', 24)
    elif stop == 'posted':
        shell.set('TEST-POST-QUIT', MASK64)
    elif stop == 'tick':
        shell.tick(0)
        shell.set('TEST-TICK-QUIT', MASK64)
    else:
        shell.set('TEST-SERVICE-QUIT', MASK64)
    assert shell.run() == 0
    assert shell.get('TEST-NEXT') == (0 if stop == 'service' else 1)
    assert not shell.trace(6) and not shell.trace(7)


def test_terminal_failure_does_not_poll_or_call_app(shell):
    shell.queue(chars('ab'))
    shell.set('TEST-SERVICE-FAULT', MASK64)
    assert shell.run() == (-91 & MASK64)
    assert shell.get('TEST-NEXT') == 0
    assert shell.trace() == [(1, 0)]


@pytest.mark.parametrize('event', ((2, 0, 0), (4, 80, 25)))
def test_pointer_and_resize_finish_the_pass_before_next_key(shell, event):
    shell.queue([event] + chars('a'))
    assert shell.run() == 0
    assert shell.get('TEST-NEXT') == 1 and shell.trace(6) == [1]


def test_callback_completed_draw_finishes_the_pass(shell):
    shell.queue(chars('ab'))
    shell.set('TEST-MODAL-CODE', ord('a'))
    assert shell.run() == 0
    assert shell.text() == 'a' and shell.trace(6) == [1]


def test_paste_delimiters_and_unicode_remain_separate_ordered_events(shell):
    shell.queue([(3, 1, 0)] + chars('é🦉') + [(3, 0, 0)])
    assert shell.run() == 0
    assert shell.text() == 'é🦉'
    assert shell.trace(3) == [1, ord('é'), ord('🦉'), 0]
    assert shell.trace(6) == [4]


def test_legacy_owner_still_checks_hardware_resize_between_events(shell):
    shell.set('_ASHELL-TERM-OWNS', 0)
    shell.queue(chars('ab'))
    assert shell.run() == 0
    assert shell.trace(10) == [1, 2, 2]
    assert shell.trace(6) == [2]
