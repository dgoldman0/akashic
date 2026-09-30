"""Prompt dismissal must invalidate the ordinary status row it covered."""
import pytest
from test_soundlab_fields import _soundlab_runtime


@pytest.mark.parametrize('key,text', [('KEY-ESC','440'), ('KEY-ENTER','440'), ('KEY-ENTER','bad')])
def test_dismissed_soundlab_prompt_restores_unchanged_status_underlay(key,text):
    runtime = _soundlab_runtime(extra_sources=('liraq/uidl.f',))
    program = r'''
_SL-STATE-SIZE ALLOCATE THROW DUP _SL-CURRENT-STATE ! _SL-STATE-SIZE 0 FILL
80 24 SCR-NEW SCR-USE
S" <uidl><region id='status'/></uidl>" UIDL-PARSE 0= ABORT" prompt UIDL parse"
S" status" UIDL-BY-ID DUP 0= ABORT" prompt status missing"
_SL-E-SBAR !
22 0 1 80 RGN-NEW _SL-PROMPT-RGN !
_SL-PROMPT-RGN @ _SL-PROMPT-BUF _SL-PROMPT-CAP PRM-NEW _SL-PROMPT !
' _SL-PROMPT-CANCEL _SL-PROMPT @ PRM-ON-CANCEL
' _SL-PROMPT-SUBMIT _SL-PROMPT @ PRM-ON-SUBMIT
440 _SL-FREQUENCY ! 1 _SL-SELECTED ! _SL-PM-FREQUENCY _SL-PROMPT-MODE !
S" Frequency (40-2000 Hz):" S" TEXT" _SL-PROMPT @ PRM-SHOW
_SL-E-SBAR @ UIDL-CLEAN!
_SL-E-SBAR @ UIDL-DIRTY? ABORT" status should start clean"
CREATE _PROMPT-EVENT KEY-T-SPECIAL , EVENTKEY , 0 ,
_PROMPT-EVENT _SL-PROMPT @ WDG-HANDLE 0= ABORT" dismiss not handled"
_SL-PROMPT @ PRM-ACTIVE? ABORT" prompt stayed active"
_SL-PROMPT-MODE @ _SL-PM-NONE <> ABORT" prompt mode stayed active"
_SL-FREQUENCY @ 440 <> ABORT" dismissal changed frequency"
_SL-E-SBAR @ UIDL-DIRTY? 0= ABORT" status underlay not invalidated"
_SL-PROMPT @ PRM-FREE _SL-PROMPT-RGN @ RGN-FREE _SL-CURRENT-STATE @ FREE
." PROMPT RESTORE PASS" CR
'''.replace('TEXT',text).replace('EVENTKEY',key)
    try:
        runtime.evaluate(program.encode(), source_name='soundlab-prompt-restore', step_budget=20_000_000)
    except Exception as exc:
        raise AssertionError(runtime.uart_output.decode(errors='replace')) from exc
    assert 'PROMPT RESTORE PASS' in runtime.drain_uart_output().decode()
    assert runtime.main_context.data.snapshot() == ()
    assert runtime.main_context.returns.snapshot() == ()
