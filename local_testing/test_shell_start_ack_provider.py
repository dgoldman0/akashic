"""Hidden START ACK consumes shell IDs before a newer ordinary draw recaptures.

The complete ordinary source closure, real PT/RTAPT provider and retained host
run natively. A caller-built legacy candidate and extension dispatch fixture
exercise the production hidden-ACK STEP branch. After real visible REVEAL, the
fixture explicitly calls sidecar PUBLISH; public constructor and core visible
TARGET-PUBLISH behavior are covered by the existing producer tests.
"""
from dataclasses import replace

import pytest

import test_rich_terminal_cell_feed as cf
from test_rich_terminal_status_provider import ProviderHarness, RetainedFeature
from test_rich_terminal_status_static import _clean
from test_shell_screen_producer import MODULES, STAGED
from test_field_model import field_runtime

MASK = (1 << 64) - 1
FEATURES = (RetainedFeature.CORE | RetainedFeature.CONTROLS |
            RetainedFeature.PANES | RetainedFeature.TASKBARS |
            RetainedFeature.STATUS_FIELDS)

ACK_FIXTURE = r'''
CREATE _AK-XS RTHP-EXTENSION-SIZE 7 + ALLOT
: _AK-X _AK-XS 7 + -8 AND ;
VARIABLE _AK-SUPPRESS VARIABLE _AK-CALLS
: _AK-DISPATCH ( event producer sidecar -- status )
    _RSHSP-S ! _RSHSP-P !
    DUP RTHPX-START-ACK = IF
        DROP 1 _AK-CALLS +!
        _AK-SUPPRESS @ IF RTE-S-OK ELSE _RSHSP-START-ACK THEN EXIT
    THEN
    DUP RTHPX-ABORT = IF DROP _SX-S _RSHSP-ABORT RTE-S-OK EXIT THEN
    DROP RTE-S-OK ;
: _AK-INIT
    _SX-SETUP
    _SX-F RTE-FACADE-SIZE 0 FILL CF-ENGINE _SX-F RTAPTE-INIT THROW
    _SX-FX RTE-SHELL-FACADE-SIZE 0 FILL _SX-F _SX-FX RTAPTE-SHELL-INIT THROW
    _SX-P _RTHP.LIMITS _SX-F RTE-LIMITS@ THROW
    10 _SX-P _RTHP.NEXT-REGION ! 100 _SX-P _RTHP.NEXT-OBJECT !
    1 _SX-P _RTHP.FIRST-SERIES ! 1 _SX-P _RTHP.NEXT-SERIES !
    1 _SX-P _RTHP.ADMISSION _RTE-HA.STATIC-COUNT !
    101 _SX-P _RTHP.ADMISSION _RTE-HA.STATIC-LAST !
    _AK-X RTHP-EXTENSION-SIZE 0 FILL
    _RTHP-EXTENSION-MAGIC _AK-X RTHPX.MAGIC !
    RTHP-EXTENSION-SIZE _AK-X RTHPX.SIZE ! _AK-X _AK-X RTHPX.SELF !
    _SX-S _AK-X RTHPX.CONTEXT ! ['] _AK-DISPATCH _AK-X RTHPX.DISPATCH !
    _AK-X _SX-P _RTHP.EXTENSION ! ;
: _AK-STEP
    _RTHP-PH-READY-REVEAL _RTHP-PH-READY-START -1 _SX-P _RTHP-STEP-SEALED ;
: _AK-NEW-DRAW
    1 _SS-M SHM.EPOCH +! _SX-OBSERVE
    _SX-P _RTHP-SELECT-NEXT-IDS? 0= IF -777 THROW THEN
    _SX-P _RTHP.REGION @ DUP _SX-CI _RTE-CONTROL.REGION ! _SX-SI _RTE-STATIC.REGION !
    _SX-P _RTHP.FIRST-OBJECT @ DUP _SX-CI _RTE-CONTROL.ID !
    1+ DUP _SX-SI _RTE-STATIC.ID ! DUP _SX-P _RTHP.STATIC-LAST !
    _SX-P _RTHP.ADMISSION _RTE-HA.STATIC-LAST !
    1 _SX-P _RTHP.ATTEMPT +! 1 _SX-P _RTHP.SOURCE-GEN +!
    SCR-DRAW-GENERATION@ DUP _SX-P _RTHP.SOURCE-DRAW ! _SX-P _RTHP.SURFACE-GEN !
    _SX-TARGET 8 + _SX-P _RTHP.TARGET-PENDING ! ;
: _AK-PUBLISH
    _SX-P _RTHP.TARGET-PENDING @ _SX-P _RTHP.TARGET-ACTIVE !
    _SX-P _RTHP.SOURCE-DRAW @ _SX-P _RTHP.ACTIVE-DRAW ! _RSHSP-PUBLISH ;
: _AK-EMIT _SX-S _RSHSP.PENDING @ DUP RSHSP-BANK.BATCH @ + _SX-FX RTE-FAMILY-BATCH-EMIT ;
'''


class HiddenAckHarness(cf._FeedHarness):
    constant = ProviderHarness.constant
    field = ProviderHarness.field
    owner_field = ProviderHarness.owner_field

    def __init__(self):
        runtime = field_runtime(MODULES)
        fixture = cf._fixture_source(32).replace(b"2 CONSTANT CF-ROWS", b"12 CONSTANT CF-ROWS")
        fixture = fixture.replace(b"RTAPT-OP-SIZE 7 + ALLOT", b"RTAPT-OP-SIZE 512 * 7 + ALLOT")
        fixture = fixture.replace(b"CF-OPS RTAPT-OP-SIZE", b"CF-OPS RTAPT-OP-SIZE 512 *")
        fixture = fixture.replace(b"CREATE CF-COPY-MEM 15 ALLOT", b"CREATE CF-COPY-MEM 65543 ALLOT")
        fixture = fixture.replace(b"CF-COPY 8 CF-LEDGER", b"CF-COPY 65536 CF-LEDGER")
        fixture = fixture.replace(b"RTAPT-CONTROL-LEDGER-SIZE 7 + ALLOT", b"RTAPT-CONTROL-LEDGER-SIZE 256 * 7 + ALLOT")
        fixture = fixture.replace(b"CF-LEDGER RTAPT-CONTROL-LEDGER-SIZE", b"CF-LEDGER RTAPT-CONTROL-LEDGER-SIZE 256 *")
        self.cols, self.runtime = 32, runtime
        self.backend = self.driver = None
        self.views, self.legacy_output = [], []
        self.runtime.evaluate(cf.ONE_CORE_UART_LOCK_SHIMS + cf.RICH_TERMINAL_SOURCE.read_bytes(),
            source_name="real-PT-transport", step_budget=20_000_000)
        rich = cf.ROOT / "akashic/tui/rich-terminal"
        memory = _clean((cf.ROOT / "akashic/utils/memory-source.f").read_text())
        self.runtime.evaluate((memory + "\n" + _clean(cf.SOURCE.read_text())).encode() + fixture,
            source_name="real-RTAPT-provider", step_budget=20_000_000)
        self.call("CF-INIT")
        self.engine = self.constant("CF-ENGINE")
        self.runtime.evaluate(("\n".join(_clean((rich / name).read_text()) for name in
            ("provider-family.f", "engine-apt1.f")) + STAGED + ACK_FIXTURE).encode(),
            source_name="real-shell-ack-fixture", step_budget=20_000_000)
        self.attach()
        assert self.call("RTAPT-OWNER-OPEN", 88, 99, 16, 0, 128, 0, 0, 8192, 0, self.engine)[0] == (0,)
        self.settle()
        self.call("_AK-INIT")
        self.p, self.s, self.facade = map(self.constant, ("_SX-P", "_SX-S", "_SX-F"))

    def call(self, word, *inputs):
        result = super().call(word, *inputs)
        failures = self.runtime.find("_SS-FAIL")
        if failures is not None:
            assert self.runtime.memory.read64(failures.body_address) == 0, self.runtime.uart_output.decode(errors="replace")
        return result

    def attach(self):
        maximum_payload = 2252
        maximum_transaction = 262144
        publication = maximum_transaction + 4096
        self.backend = cf.SimulatorSessionBackend(self.runtime, legacy_output_sink=self.legacy_output.append)
        self.driver = cf.RichTerminalDriver.attach(self.backend,
            cf.HostPortLimits(egress=cf.EgressWatermarks(high_bytes=publication*2,
                low_bytes=publication, high_batches=16, low_batches=2),
                retained_publication_bytes=publication, ingress_bytes=8192, ingress_events=16,
                ingress_control_bytes=4096, ingress_control_events=8, geometry_events=2),
            cf.TerminalConfig(max_payload=maximum_payload, max_transaction_bytes=maximum_transaction,
                terminal_receive_credit=maximum_transaction, max_cells=280*84,
                max_feed_bytes=publication, max_cols=280, max_rows=84, cols=32, rows=12),
            cf.DriverLimits(4096, 8), retained_policy=replace(cf._retained_policy(),
                features=FEATURES, max_regions=16, max_objects=128, total_utf8_bytes=8192,
                max_operations_per_transaction=512, max_glyph_run_bytes=256,
                client_to_terminal_max_payload=maximum_payload,
                max_retained_transaction_bytes=maximum_transaction, base_max_transaction_bytes=maximum_transaction),
            view_sink=self.views.append, session_id_factory=lambda: cf.SESSION_ID)
        self.call("CF-START")
        self.until(lambda: bool(self.cell("CF-ACTIVE")))
        self.call("CF-INITIAL-BEGIN")
        for row in range(12):
            self.call("CF-INITIAL-ROW", row)
        self.call("CF-INITIAL-COMMIT")
        self.until(lambda: self.cell("CF-RETAINED") == self.constant("PT-RET-ST-AVAILABLE"))
        assert self.driver.core.state is cf.TerminalState.ACTIVE

    def settle(self):
        for _ in range(128):
            assert self.call("RTAPT-STEP", self.engine)[0] in ((0,), (1,))
            self.service()
            if self.field("_RTAPT-E.ACTIVE-KIND") == 0 and self.field("_RTAPT-E.QUEUE-HEAD") == 0:
                return
        raise AssertionError("real hidden ACK did not settle")

    def get(self, word, base=None):
        return self.runtime.memory.read64(self.constant(word) if base is None else self.call(word, base)[0][0])

    def put(self, word, value, base=None):
        self.runtime.memory.write64(self.constant(word) if base is None else self.call(word, base)[0][0], value)

    def prepare(self):
        assert self.call("_RSHSP-PREPARE")[0] == (0,)
        bank = self.get("_RSHSP.PENDING", self.s)
        assert bank
        return bank

    def begin_emit(self):
        assert self.call("RTE-RETAINED-BEGIN", self.constant("RTE-RETAINED-REPLACE-START"), self.facade)[0] == (0,)
        return self.call("_AK-EMIT")[0]

    def seal(self, reveal=False):
        assert self.call("RTAPT-RICH-SEAL", self.constant("PT-COMMIT-AND-REVEAL" if reveal else "PT-COMMIT"), self.engine)[0] == (0,)
        assert self.call("RTAPT-CELL-BEGIN", 32, 12, 0, 0, 0, self.constant("PT-CELL-DELTA"), self.engine)[0] == (0,)
        assert self.call("RTAPT-CELL-CURSOR", 0, 0, 0, self.engine)[0] == (0,)
        assert self.call("RTAPT-CELL-COMMIT", self.engine)[0] in ((0,), (1,))

    def frontiers(self):
        return self.get("_RTHP.NEXT-REGION", self.p), self.get("_RTHP.NEXT-OBJECT", self.p)


@pytest.mark.parametrize("suppress_fix", (True, False), ids=("red-original-ack", "green-shell-ack"))
def test_hidden_start_ack_then_new_draw_uses_real_provider_highwaters(suppress_fix):
    h = HiddenAckHarness()
    try:
        h.put("_AK-SUPPRESS", int(suppress_fix))
        bank = h.prepare()
        target = h.get("_RSHSP.PENDING-TARGET", h.s)
        next_ids = (h.get("RSHSP-BANK.NEXT-REGION", bank), h.get("RSHSP-BANK.NEXT-OBJECT", bank))
        assert next_ids[0] > 11 and next_ids[1] > 102  # Shell consumes beyond legacy.
        assert h.frontiers() == (10, 100)
        assert h.begin_emit() == (0,)
        h.seal()
        # An emitted, unacknowledged capture has no ID or input authority.
        assert h.frontiers() == (10, 100)
        assert h.get("_RSHSP.ACTIVE", h.s) == 0
        h.settle()
        high = (h.owner_field("_RTAPT-O.REGION-HIGH"), h.owner_field("_RTAPT-O.OBJECT-HIGH"))
        assert high == (next_ids[0]-1, next_ids[1]-1)
        assert h.call("_AK-STEP")[0] == (0, 0, MASK)
        assert h.get("_AK-CALLS") == 1
        assert h.get("_RSHSP.ACTIVE", h.s) == 0
        assert h.get("_RSHSP.PENDING", h.s) == bank
        assert h.get("_RSHSP.PENDING-TARGET", h.s) == target
        assert h.frontiers() == ((11, 102) if suppress_fix else next_ids)
        h.call("_AK-NEW-DRAW")
        h.prepare()
        result = h.begin_emit()
        if suppress_fix:
            # Exact historical failure: a real hidden ACK consumed the first
            # shell range, but legacy advancement reused a provider region ID.
            assert result == (h.constant("RTE-S-INVALID"),)
            assert h.get("_RSHSP.ACTIVE", h.s) == 0
            assert h.owner_field("_RTAPT-O.REGION-HIGH") == high[0]
            assert h.call("RTAPT-RICH-CANCEL", h.engine)[0] == (0,)
            return
        assert result == (0,)
        assert h.get("_RTHP.REGION", h.p) > high[0]
        assert h.get("_RTHP.FIRST-OBJECT", h.p) > high[1]
        second = h.get("_RSHSP.PENDING", h.s)
        second_ids = (h.get("RSHSP-BANK.NEXT-REGION", second), h.get("RSHSP-BANK.NEXT-OBJECT", second))
        h.seal()
        h.settle()
        assert h.call("_AK-STEP")[0] == (0, 0, MASK)
        assert h.frontiers() == second_ids
        assert h.get("_RSHSP.ACTIVE", h.s) == 0
        assert h.call("_RSHSP-START-ACK")[0] == (0,)  # Idempotent, still hidden.
        assert h.frontiers() == second_ids
        assert h.get("_RSHSP.PENDING", h.s) == second
        assert h.call("RTE-RETAINED-BEGIN", h.constant("RTE-RETAINED-REPLACE-CONTINUE"), h.facade)[0] == (0,)
        h.seal(reveal=True)
        h.settle()
        assert h.get("_RSHSP.ACTIVE", h.s) == 0  # Provider reveal alone is not input authority.
        h.call("_AK-PUBLISH")
        assert h.get("_RSHSP.ACTIVE", h.s) == second
        assert h.get("_RSHSP.PENDING", h.s) == 0
        assert h.frontiers() == second_ids
        assert h.driver.core.retained_state.active.owners[88].objects
        assert h.call("_RSHSP-CURRENT?")[0] == (MASK,)
    finally:
        h.close()


def test_hidden_ack_boundaries_abort_and_larger_base_frontiers_never_publish_or_rewind():
    h = HiddenAckHarness()
    try:
        bank = h.prepare()
        before = h.frontiers()
        assert h.begin_emit() == (0,)
        assert h.call("RTAPT-RICH-CANCEL", h.engine)[0] == (0,)
        h.call("_RSHSP-ABORT", h.s)
        assert h.frontiers() == before
        assert h.get("_RSHSP.ACTIVE", h.s) == h.get("_RSHSP.PENDING", h.s) == 0
        assert h.owner_field("_RTAPT-O.REGION-HIGH") == 0
        assert h.owner_field("_RTAPT-O.OBJECT-HIGH") == 0
        bank = h.prepare()
        assert h.begin_emit() == (0,)
        h.seal()
        # No host service means no acknowledgement has arrived. The real core
        # wait branch must not invoke START-ACK for a merely sealed update.
        assert h.call("_AK-STEP")[0][0] == 0
        assert h.get("_AK-CALLS") == 0
        assert h.frontiers() == before
        h.settle()
        # Ordinary source authority may disappear before the old hidden ACK is
        # consumed. The exact immutable pending tuple remains its authority.
        old_draw = h.get("_RSHSP.PENDING-DRAW", h.s)
        assert h.call("_ASHELL-DRAW-OBSERVE", h.constant("ASHELL-DRAW-MODAL"))[0] == (0,)
        assert h.call("SHSN-SNAPSHOT-FOR@", old_draw, h.constant("_SX-C"))[0][2] != 0
        assert h.call("_AK-STEP")[0] == (0, 0, MASK)
        consumed = h.frontiers()
        assert consumed[0] > before[0] and consumed[1] > before[1]
        h.call("_RSHSP-ABORT", h.s)
        assert h.frontiers() == consumed  # Aborting after ACK cannot unconsume IDs.
        assert h.get("_RSHSP.ACTIVE", h.s) == h.get("_RSHSP.PENDING", h.s) == 0
        h.call("_AK-NEW-DRAW")
        bank = h.prepare()
        target = h.get("_RSHSP.PENDING-TARGET", h.s)
        draw = h.get("_RSHSP.PENDING-DRAW", h.s)
        bank_bytes = h.runtime.memory.read_bytes(bank, h.get("RSHSP-BANK.USED", bank))
        # These are unit boundaries for the exact helper called by the real ACK
        # branch above. Both valid-but-wrong lifecycle links and malformed frozen
        # metadata must refuse before advancing either producer frontier.
        for word, base, changed in (("_RSHSP.PENDING-TARGET", h.s, target+8),
                                    ("_RSHSP.PENDING-DRAW", h.s, draw+1),
                                    ("RSHSP-BANK.NEXT-REGION", bank, 0),
                                    ("RSHSP-BANK.NEXT-OBJECT", bank, 0)):
            original = h.get(word, base)
            h.put(word, changed, base)
            assert h.call("_RSHSP-START-ACK")[0] == (h.constant("RTE-S-INVALID"),)
            assert h.frontiers() == consumed
            assert h.get("_RSHSP.ACTIVE", h.s) == 0
            assert h.get("_RSHSP.PENDING", h.s) == bank
            h.put(word, original, base)
        assert h.runtime.memory.read_bytes(bank, len(bank_bytes)) == bank_bytes
        expected = (h.get("RSHSP-BANK.NEXT-REGION", bank), h.get("RSHSP-BANK.NEXT-OBJECT", bank))
        # Independent MAX behavior, including mixed ordering, not just both up.
        for base_ids in ((expected[0]+50, expected[1]-1),
                         (expected[0]-1, expected[1]+50),
                         (expected[0]+50, expected[1]+50)):
            h.put("_RTHP.NEXT-REGION", base_ids[0], h.p)
            h.put("_RTHP.NEXT-OBJECT", base_ids[1], h.p)
            maximum = tuple(map(max, base_ids, expected))
            assert h.call("_RSHSP-START-ACK")[0] == (0,)
            assert h.frontiers() == maximum
            assert h.call("_RSHSP-START-ACK")[0] == (0,)
            assert h.frontiers() == maximum
            assert h.get("_RSHSP.ACTIVE", h.s) == 0
            assert h.get("_RSHSP.PENDING", h.s) == bank
            assert h.get("_RSHSP.PENDING-TARGET", h.s) == target
            assert h.get("_RSHSP.PENDING-DRAW", h.s) == draw
        h.call("_AK-PUBLISH")
        assert h.frontiers() == maximum  # Visible publication is also monotonic.
        assert h.get("_RSHSP.ACTIVE", h.s) == bank
        assert h.get("_RSHSP.PENDING", h.s) == 0
        active = h.runtime.memory.read_bytes(bank, len(bank_bytes))
        assert active == bank_bytes
        assert h.call("_RSHSP-START-ACK")[0] == (0,)  # No pending candidate is a no-op.
        assert h.frontiers() == maximum
        assert h.get("_RSHSP.ACTIVE", h.s) == bank
    finally:
        h.close()
