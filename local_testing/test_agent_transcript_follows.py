"""The Agent's transcript counts each change to the conversation it shows.

The transcript is a canonical card list whose callbacks read the
conversation, so the list knows that a card changed only when the Agent
tells it.  A reply streams into its message in place, and a message's state
changes its card's header in place, without the count of cards moving; the
Agent's panel tells the list of each such change before it draws it, so the
list's revision moves, which a projection reads to know that the cards
changed (uidl-root-facts.f).  These tests run the Agent's own words in the
native simulator, on a state block and an instance of their own, with a
runtime record that holds only a conversation, changed as the runtime
changes it: each event it handles moves the conversation's revision.
"""

from __future__ import annotations

from native_forth import NativeForth


PRELUDE = (
    "VARIABLE _AT-FAILS VARIABLE _AT-CHECKS",
    ': _AT-ASSERT 1 _AT-CHECKS +! 0= IF 1 _AT-FAILS +! ." AT ASSERT " _AT-CHECKS @ . CR THEN ;',
    ': _AT-DONE _AT-FAILS @ 0= IF ." AT PASS " ELSE ." AT FAIL " THEN _AT-CHECKS @ . CR ;',
    "80 24 SCR-NEW SCR-USE",
    "CREATE _AT-STATE _AG-STATE-SIZE ALLOT _AT-STATE _AG-STATE-SIZE 0 FILL",
    "_AT-STATE _AG-CURRENT-STATE !",
    # The instance the list's callbacks make current holds the state above.
    "CREATE _AT-INST COMP-INST ALLOT _AT-INST COMP-INST 0 FILL",
    "_AT-STATE _AT-INST CINST.STATE ! _AT-INST _AG-CURRENT-INSTANCE !",
    "CREATE _AT-RT AGENT-RUNTIME-SIZE ALLOT _AT-RT AGENT-RUNTIME-SIZE 0 FILL",
    "ACONV-NEW DROP _AT-RT ARUNTIME.CONVERSATION ! 1 _AT-RT ARUNTIME.REVISION !",
    "_AT-RT _AG-RUNTIME !",
    "0 0 20 80 RGN-NEW _AG-PANEL-INIT _AG-CARD-COLUMNS-INIT",
    "_AG-PANEL-RGN @ 0 0 1 1 RGN-SUB DUP _AG-LIST-RGN ! _AG-LIST-NEW _AG-LIST !",
    "VARIABLE _AT-REV VARIABLE _AT-FIRST",
    ": _AT-MARK ( -- ) _AG-LIST @ WDG-REVISION _AT-REV ! ;",
    ": _AT-MOVED? ( -- flag ) _AG-LIST @ WDG-REVISION _AT-REV @ <> ;",
    ": _AT-DRAW ( -- ) _AG-PANEL WDG-DRAW ;",
    ": _AT-COUNT ( -- n ) _AG-LIST @ LST-COUNT ;",
    # A message added at the conversation's end, as the runtime adds one.
    ": _AT-SAY ( a u role state -- ) 2SWAP 0 -ROT _AG-CONV ACONV-APPEND 0= _AT-ASSERT DROP ;",
    # The runtime counts each event it handles in itself and its conversation.
    ": _AT-HANDLED ( -- ) 1 _AT-RT ARUNTIME.REVISION +! 1 _AG-CONV ACONV.REVISION +! ;",
    ": _AT-LAST ( -- message ) _AG-CONV ACONV.COUNT @ 1- _AG-CONV ACONV-NTH ;",
    # A text delta streams into the last message.
    ": _AT-STREAM ( a u -- ) _AT-LAST AMSG-APPEND 0= _AT-ASSERT _AT-HANDLED ;",
    # The text and header the list's callbacks give for a card.
    ": _AT-TEXT-U ( row -- u ) 1 _AG-LIST @ _AG-CARD-FIELD NIP ;",
    ": _AT-HEADER ( row -- a u ) 0 _AG-LIST @ _AG-CARD-FIELD ;",
)

SUITE = NativeForth(("tui/applets/agent/agent.f",), prelude=PRELUDE)

# The request and the reply's first two deltas in the Agent's Desk journey,
# from the scripted provider.
REQUEST = 'S" approval check" AROLE-USER AMSG-S-COMPLETE _AT-SAY'
REPLY = (
    'S" " AROLE-ASSISTANT AMSG-S-STREAMING _AT-SAY',
    """S" Connected through Akashic's provider-neutral runtime. " _AT-STREAM""",
    'S" You asked: " _AT-STREAM',
)


def _run(lines: list[str]) -> str:
    return SUITE.run(lines + ["_AT-DONE"], 50_000_000).decode(errors="replace")


def _passed(output: str, minimum: int) -> None:
    assert "AT PASS" in output, output[-3000:]
    assert int(output.split("AT PASS")[1].split()[0]) >= minimum


def test_a_card_changed_in_place_counts_a_change_to_the_transcript():
    _passed(_run([
        "_AG-PANEL WDG-VISIBLE? _AT-ASSERT",
        # The request and the reply's empty message add two cards.
        REQUEST, REPLY[0],
        "_AT-MARK _AT-DRAW _AT-MOVED? _AT-ASSERT _AT-COUNT 2 = _AT-ASSERT",
        # Drawn again unchanged, the transcript counts nothing.
        "_AT-MARK _AT-DRAW _AT-MOVED? 0= _AT-ASSERT",
        # Each delta streams into the reply's card in place: the cards stay
        # two, the list counts the change, and its callbacks give the text
        # grown by the delta, 54 bytes and then 65.
        REPLY[1],
        "_AT-MARK _AT-DRAW _AT-MOVED? _AT-ASSERT _AT-COUNT 2 = _AT-ASSERT",
        "1 _AT-TEXT-U 54 = _AT-ASSERT",
        REPLY[2],
        "_AT-MARK _AT-DRAW _AT-MOVED? _AT-ASSERT _AT-COUNT 2 = _AT-ASSERT",
        "1 _AT-TEXT-U 65 = _AT-ASSERT",
        "_AT-MARK _AT-DRAW _AT-MOVED? 0= _AT-ASSERT",
        # The reply completes: its header loses the streaming mark in place.
        """1 _AT-HEADER S" AGENT  ..." COMPARE 0= _AT-ASSERT""",
        "AMSG-S-COMPLETE _AT-LAST AMSG.STATE ! _AT-HANDLED",
        "_AT-MARK _AT-DRAW _AT-MOVED? _AT-ASSERT _AT-COUNT 2 = _AT-ASSERT",
        """1 _AT-HEADER S" AGENT" COMPARE 0= _AT-ASSERT""",
        # A card added at the end is counted as before.
        """S" Persist the simulated change?" AROLE-SYSTEM AMSG-S-APPROVAL _AT-SAY""",
        "_AT-MARK _AT-DRAW _AT-MOVED? _AT-ASSERT _AT-COUNT 3 = _AT-ASSERT",
    ]), 22)


def test_another_conversation_at_the_same_revision_counts_a_change():
    _passed(_run([
        REQUEST, REPLY[0],
        "_AT-DRAW _AG-CONV _AT-FIRST !",
        # The runtime's conversation is replaced by one with as many
        # messages and the same revision, as loading a stored one may, which
        # the runtime counts in itself: the transcript follows the
        # conversation, not its revision alone.
        "ACONV-NEW DROP _AT-RT ARUNTIME.CONVERSATION ! 1 _AT-RT ARUNTIME.REVISION +!",
        'S" another request" AROLE-USER AMSG-S-COMPLETE _AT-SAY',
        'S" another reply" AROLE-ASSISTANT AMSG-S-COMPLETE _AT-SAY',
        "_AT-FIRST @ ACONV.REVISION @ _AG-CONV ACONV.REVISION !",
        "_AT-MARK _AT-DRAW _AT-MOVED? _AT-ASSERT _AT-COUNT 2 = _AT-ASSERT",
        "1 _AT-TEXT-U 13 = _AT-ASSERT",
    ]), 7)
