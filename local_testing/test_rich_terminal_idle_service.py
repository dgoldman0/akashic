"""Execute the production service gate without a Desktop boot or PT session.

The existing storage, full audit, and PT boundaries are explicit spies. The
real fixed-state predicate and STEP dispatch decide which boundaries may run.
No guest ledger is certified by the no-work branch.
"""
import re

import pytest

from test_rich_terminal_control_map import ROOT, _definitions, MegaForthRuntime


SOURCE = ROOT / 'akashic/tui/rich-terminal/apt1-engine.f'


from test_rich_glyph_growth import GrowthHarness


class ServiceHarness(GrowthHarness):
    def __init__(self, backend):
        self.declarations = _definitions(SOURCE.read_text())
        stubs = '''
VARIABLE TEST-STORAGE-OK  -1 TEST-STORAGE-OK !
VARIABLE TEST-AUDIT-OK  -1 TEST-AUDIT-OK !
VARIABLE TEST-AUDITS
VARIABLE TEST-READY
VARIABLE TEST-POLLS
VARIABLE TEST-POLL-HAS
VARIABLE TEST-POLL-STATUS
VARIABLE TEST-ENDED
: _RTAPT-ENGINE-STORAGE? DROP TEST-STORAGE-OK @ ;
: _RTAPT-ENGINE-VALID? DROP 1 TEST-AUDITS +! TEST-AUDIT-OK @ ;
: _RTAPT-READY-STATUS DROP TEST-READY @ ;
: _RTAPT-SESSION-ENDED? DROP TEST-ENDED @ ;
: _RTAPT-POLL-COMPLETION
    DROP 1 TEST-POLLS +! TEST-POLL-STATUS @ TEST-POLL-HAS @ ;
: _RTAPT-QUARANTINE-ALL DROP ;
: _RTAPT-OWNER-SEND 2DROP 0 ;
: _RTAPT-QUEUE-POP DROP 0 ;
: _RTAPT-OWNER-ADMISSION-FAILED 2DROP -1 ;
'''
        overrides = _definitions(stubs)
        self.declarations.update(overrides)
        # The idle constants belong to the boot-selected system ABI.
        self.declarations.update({'PT-RET-NONE': '0 CONSTANT PT-RET-NONE',
                                  'PT-COMMIT': '0 CONSTANT PT-COMMIT',
                                  'PT-CELL-NONE': '0 CONSTANT PT-CELL-NONE'})
        chunks, seen = [stubs], set(re.findall(r'(?m)^(?::|VARIABLE) (\S+)', stubs))
        def include(name):
            if name in seen:
                return
            seen.add(name)
            declaration = self.declarations[name]
            code = re.sub(r'\([^)]*\)', '', declaration)
            for token in code.split():
                if token != name and token in self.declarations:
                    include(token)
            chunks.append(declaration)
        for name in ('_RTAPT-IDLE-SERVICE?', '_RTAPT-STEP-VALID?', 'RTAPT-STEP'):
            include(name)
        self.runtime = MegaForthRuntime(execution_backend=backend)
        self.runtime.evaluate('\n'.join(chunks).encode(), step_budget=3_000_000)
        self.definitions = self.declarations
        self.serial = 0
        self.engine = self.allocate(bytes(self.constant('RTAPT-ENGINE-SIZE')))

    def set(self, field, value):
        self.runtime.memory.write64(self.engine + self.offset('_RTAPT-E.' + field), value)

    def variable(self, name, value=None):
        address = self.runtime.dictionary.find(name).body_address
        if value is not None:
            self.runtime.memory.write64(address, value)
        return self.runtime.memory.read64(address)

    def call(self, word):
        return self.results(word, self.engine)


@pytest.fixture(params=['python', 'native'])
def service(request):
    return ServiceHarness(request.param)


def test_idle_poll_does_not_touch_unneeded_ledgers_or_completion(service):
    # No bank contents or pointers are consulted beyond the existing storage
    # boundary. Even a failing deep audit cannot affect a pure status poll.
    service.variable('TEST-AUDIT-OK', 0)
    for _ in range(3):
        assert service.call('RTAPT-STEP') == (0,)
    assert service.variable('TEST-AUDITS') == 0
    assert service.variable('TEST-POLLS') == 0
    assert service.runtime.memory.read64(service.engine + service.offset('_RTAPT-E.LAST-STATUS')) == 0


@pytest.mark.parametrize('field', [
    'UPDATE-STATE', 'ACTIVE-KIND', 'ACTIVE-O', 'QUEUE-HEAD', 'QUEUE-TAIL',
    'COUPLING', 'OP-COUNT', 'COPY-USED', 'RET-BYTES', 'SEND-INDEX',
    'RET-MODE', 'DISPOSITION', 'COLS', 'ROWS', 'CELL-SPANS', 'CELLS', 'CELL-MODE',
])
def test_nonidle_or_incoherent_state_reaches_full_audit_before_any_effect(service, field):
    service.set(field, 1)
    service.variable('TEST-AUDIT-OK', 0)
    assert service.call('RTAPT-STEP') == (service.constant('RTAPT-S-INVALID'),)
    assert service.variable('TEST-AUDITS') == 1
    assert service.variable('TEST-POLLS') == 0


def test_bad_storage_cannot_enter_no_work_branch(service):
    service.variable('TEST-STORAGE-OK', 0)
    service.variable('TEST-AUDIT-OK', 0)
    assert service.call('RTAPT-STEP') == (service.constant('RTAPT-S-INVALID'),)
    assert service.variable('TEST-AUDITS') == 1


@pytest.mark.parametrize('ready', [0, 1, 2, 3, 4])
def test_idle_service_preserves_readiness_and_sticky_status(service, ready):
    service.variable('TEST-READY', ready)
    assert service.call('RTAPT-STEP') == (ready,)
    assert service.variable('TEST-AUDITS') == 0
    assert service.runtime.memory.read64(service.engine + service.offset('_RTAPT-E.LAST-STATUS')) == ready


def test_active_completion_still_requires_full_audit_on_every_poll(service):
    service.set('ACTIVE-KIND', service.constant('_RTAPT-ACTIVE-OUTPUT'))
    service.set('UPDATE-STATE', service.constant('RTAPT-UPDATE-AWAITING'))
    assert service.call('RTAPT-STEP') == (service.constant('RTAPT-S-WOULD-BLOCK'),)
    assert service.variable('TEST-AUDITS') == service.variable('TEST-POLLS') == 1
    service.variable('TEST-AUDIT-OK', 0)
    assert service.call('RTAPT-STEP') == (service.constant('RTAPT-S-INVALID'),)
    assert service.variable('TEST-AUDITS') == 2
    assert service.variable('TEST-POLLS') == 1
