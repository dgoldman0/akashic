"""Complete family admission and shell capture through the real RTAPT bridge."""
from dataclasses import replace
import hashlib
import struct
from unittest.mock import patch

import pytest

import test_rich_terminal_cell_feed as cf
from test_rich_terminal_family_batch import Families
from test_rich_terminal_status_provider import ProviderHarness, RetainedFeature
from test_rich_terminal_status_static import MASK

FEATURES = (RetainedFeature.CORE | RetainedFeature.CONTROLS | RetainedFeature.TASKBARS |
            RetainedFeature.PANES | RetainedFeature.INSTRUMENT | RetainedFeature.SERIES |
            RetainedFeature.STATUS_FIELDS)

# Wall-clock watchdog for the complete product bridge closure, not a guest step
# budget.  The closure compiles more source than the engine-only closure and
# took 59 to 63 seconds here, so the engine test's 60-second watchdog left it
# failing by chance.
BRIDGE_SOURCE_LOAD_WALL_SECONDS = 90.0


class Bridge(ProviderHarness):
    record = Families.record
    entry = Families.entry

    def __init__(self, backend):
        fixture = cf._fixture_source(20).replace(
            b"CREATE CF-LEDGER-MEM RTAPT-CONTROL-LEDGER-SIZE 7 + ALLOT",
            b"CREATE CF-LEDGER-MEM RTAPT-CONTROL-LEDGER-SIZE 8 * 7 + ALLOT",
        ).replace(b"CF-LEDGER RTAPT-CONTROL-LEDGER-SIZE",
                  b"CF-LEDGER RTAPT-CONTROL-LEDGER-SIZE 8 *")
        policy = replace(cf._retained_policy(), features=FEATURES, max_objects=16,
                         total_utf8_bytes=128, max_operations_per_transaction=32,
                         max_glyph_run_bytes=64, max_series=1,
                         max_samples_per_append=8, max_history_per_series=16000,
                         total_sample_slots=16000)
        with patch.object(cf, "_fixture_source", return_value=fixture), patch.object(
                cf, "_retained_policy", return_value=policy):
            super().__init__(backend, features=FEATURES)
        # Replace the small inherited owner using real acknowledged lifecycle calls.
        assert self.call("RTE-OWNER-DROP", 1, 1, self.facade)[0] == (0,)
        self.settle()
        assert self.call("RTE-OWNER-OPEN", 1, 2, 2, 0, 7, 1, 0, 128, 16000,
                         self.facade)[0] == (0,)
        self.settle()
        self.shell = self.allocate(bytes(56))
        assert self.call("RTAPTE-SHELL-INIT", self.facade, self.shell)[0] == (0,)
        self.limits = self.allocate(bytes(self.constant("RTE-LIMITS-SIZE")))
        assert self.call("RTE-LIMITS@", self.limits, self.facade)[0] == (0,)

    def attach(self):
        policy = replace(cf._retained_policy(), max_objects=16)
        with patch.object(cf, "_retained_policy", return_value=policy):
            super().attach()

    def read(self, address, length):
        return self.runtime.memory.read_bytes(address, length)

    def region(self, identity, *, y=0, height=2, z=0):
        return self.record("_RTE-IR", 96, dict(ID=identity, Y=y, COLS=20,
                           ROWS=height, Z=z, FLAGS=3,
                           **{"CLIP-Y": y, "CLIP-COLS": 20, "CLIP-ROWS": height}))

    def plan(self, items, size, region):
        return self.allocate(struct.pack("<4Q", 1, 2, 20, 2) + self.read(region, 88)
                             + struct.pack("<3Q", items, size, 0))

    def graph(self, mixed=False):
        r1 = self.region(1)
        r2 = self.region(2, y=1, height=1, z=1)
        title = self.allocate(b"Pane")
        pane = self.record("_RTE-PANE", 184, dict(OWNER=1, GENERATION=2,
            ID=7 if mixed else 1, KIND=1, VISIBLE=MASK, REGION=1, HEIGHT=2,
            WIDTH=20, FOCUSED=MASK, **{"ROOT-HEIGHT": 2, "ROOT-WIDTH": 20,
            "CONTENT-REGION": 2, "CONTENT-ROW": 1, "CONTENT-HEIGHT": 1,
            "CONTENT-WIDTH": 20, "TITLE-A": title, "TITLE-U": 4}))
        entries = []
        records = dict(pane=pane, title=title, regions=(r1, r2))
        if mixed:
            text = self.allocate(b"AppRun")
            controls = []
            for identity, kind, col, width, state in ((1,10,0,20,3), (2,11,0,6,35), (3,12,10,6,3)):
                controls.append(self.record("_RTE-CONTROL", 200, dict(OWNER=1,
                    GENERATION=2, ID=identity, KIND=kind, STATE=state, REGION=1,
                    PARENT=0 if identity == 1 else 1, ORDER=identity-2 if identity > 1 else 0,
                    COL=col, HEIGHT=1, WIDTH=width, **{"ROOT-HEIGHT": 2, "ROOT-WIDTH": 20,
                    "LABEL-A": 0 if identity == 1 else text+(3 if identity == 3 else 0),
                    "LABEL-U": 0 if identity == 1 else 3})))
            control = self.allocate(b"".join(self.read(x,200) for x in controls))
            entries.append(self.entry(1, self.plan(control,600,r1),text,6))
            series = self.record("_RTE-SERIES",88,dict(OWNER=1,GENERATION=2,ID=1,
                CAPACITY=16000,MODE=1,**{"INTERVAL-US":125}))
            sp = self.record("_RTE-SRP",48,dict(OWNER=1,GENERATION=2,
                **{"SURFACE-COLS":20,"SURFACE-ROWS":2,"ITEMS-A":series,"ITEMS-U":88}))
            entries.append(self.entry(5,sp))
            wave = self.record("_RTE-INSTRUMENT",216,dict(OWNER=1,GENERATION=2,
                ID=4,KIND=4,VISIBLE=MASK,REGION=2,HEIGHT=1,WIDTH=20,
                MINIMUM=-32768,MAXIMUM=32767,**{"ROOT-HEIGHT":1,"ROOT-WIDTH":20,"SERIES-ID":1}))
            ip = self.record("_RTE-IP",72,dict(OWNER=1,GENERATION=2,
                **{"SURFACE-COLS":20,"SURFACE-ROWS":2,"REGIONS-A":self.allocate(self.read(r2,96)),
                "REGIONS-U":96,"ITEMS-A":wave,"ITEMS-U":216}))
            entries.append(self.entry(3,ip))
            text2 = self.allocate(b"OK")
            static = self.record("_RTE-STATIC",176,dict(OWNER=1,GENERATION=2,
                ID=5,KIND=1,VISIBLE=MASK,REGION=2,HEIGHT=1,WIDTH=10,
                **{"ROOT-HEIGHT":1,"ROOT-WIDTH":20,"VALUE-A":text2,"VALUE-U":2}))
            entries.append(self.entry(4,self.plan(static,176,r2),text2,2))
            glyph_text = self.allocate(b"Cell")
            glyph = self.record("_RTE-LPI",120,dict(OBJECT=6,HEIGHT=1,WIDTH=10,
                VISIBLE=MASK,**{"ROOT-HEIGHT":1,"ROOT-WIDTH":20,"TEXT-CAPACITY":4}))
            refs = self.allocate(struct.pack("<2Q",0,4))
            entries.append(self.entry(2,self.plan(glyph,120,r2),glyph_text,4,refs))
            records.update(control=control, series=series, wave=wave, static=static,
                           glyph=glyph, glyph_text=glyph_text, control_text=text)
        entries.append(self.entry(6,self.plan(pane,184,r1),title,4))
        catalog = self.record("_RTE-RC",56,dict(OWNER=1,GENERATION=2,
            **{"SURFACE-COLS":20,"SURFACE-ROWS":2,
            "REGIONS-A":self.allocate(self.read(r1,96)+self.read(r2,96)),"REGIONS-U":192}))
        batch = self.record("_RTE-FB",72,dict(ABI=1,ATTEMPT=1,
            **{"CATALOG-A":catalog,"CATALOG-U":56,
            "FAMILIES-A":self.allocate(b"".join(self.read(e,64) for e in entries)),
            "FAMILIES-U":len(entries)*64,"SOURCE-GENERATION":2,"SURFACE-GENERATION":1}))
        return batch, self.allocate(b"A"*544), records

    def snapshot(self):
        spans = ((self.engine,self.constant("RTAPT-ENGINE-SIZE")),
                 (self.constant("CF-OWNERS"),self.constant("RTAPT-OWNER-SIZE")),
                 (self.field("_RTAPT-E.OPS-A"),self.field("_RTAPT-E.OPS-U")),
                 (self.field("_RTAPT-E.COPY-A"),self.field("_RTAPT-E.COPY-U")),
                 (self.field("_RTAPT-E.CONTROL-LEDGER-A"),self.field("_RTAPT-E.CONTROL-LEDGER-U")))
        return (tuple(hashlib.sha256(self.read(a,u)).digest() for a,u in spans),
                self.driver.core.frames_received, self.driver.core.retained_state)

    def begin_regions(self, records):
        assert self.call("RTE-RETAINED-BEGIN",self.constant("RTE-RETAINED-REPLACE-START"),self.facade)[0] == (0,)
        for region in records["regions"]:
            values = struct.unpack("<12Q",self.read(region,96))
            assert self.call("RTE-REGION-DEFINE",1,2,*values[:11],self.facade)[0] == (0,)


@pytest.fixture(params=("python","native"))
def bridge(request):
    h = Bridge(request.param)
    try:
        yield h
    finally:
        h.close()


def test_real_bridge_shell_lifecycle_and_feature_mapping(bridge):
    h = bridge
    assert h.call("RTE-VALID?",h.facade)[0] == (MASK,)
    assert h.call("RTE-SHELL-VALID?",h.shell)[0] == (MASK,)
    assert h.runtime.memory.read64(h.limits) == 1|8|16|64|0x200|0x400|0x800
    shell = h.read(h.shell,56)
    base = h.read(h.facade,256)
    assert h.call("RTAPTE-SHELL-INIT",h.facade,h.shell)[0] == (1,)
    assert h.read(h.shell,56) == shell
    assert h.call("RTAPTE-SHELL-FINI",h.shell)[0] == (0,)
    assert h.read(h.shell,56) == bytes(56)
    assert h.read(h.facade,256) == base
    assert h.call("RTAPTE-SHELL-FINI",h.shell)[0] == (0,)
    assert h.call("RTAPTE-SHELL-INIT",h.facade,h.shell)[0] == (0,)


def test_real_six_family_preflight_has_exact_scalars_and_no_provider_mutation(bridge):
    h = bridge
    batch,out,_ = h.graph(mixed=True)
    before = h.snapshot()
    assert h.call("RTE-FAMILY-BATCH-VALID?",batch)[0] == (MASK,)
    assert h.call("RTE-FAMILY-BATCH-PREFLIGHT",batch,out,h.shell)[0] == (0,)
    assert h.snapshot() == before
    q = struct.unpack("<68Q",h.read(out,544))
    assert q[:6] == (1,2,20,2,1,544)
    assert q[6:15] == (0,)*9
    assert q[15:23] == (3,6,16,3,3,0,0,6)
    assert q[23:28] == (1,4,8,4,6)
    assert q[28:33] == (1,1,0,0,0)
    assert q[38] == 4
    assert q[40:47] == (1,2,8,2,5,184,1)
    assert q[48:57] == (1,1,16000,16000,0,0,0,0,1)
    assert q[57:] == (2,2,1,7,1,4,8,4,7,3,1|8|16|64|0x200|0x400|0x800)



def test_controls_only_batch_has_global_object_ids_and_exact_quota(bridge):
    h = bridge
    batch,out,_ = h.graph(mixed=True)
    # Narrow the explicit graph to its first family and its one referenced region.
    catalog = h.runtime.memory.read64(batch+8)
    h.runtime.memory.write64(catalog+40,96)
    h.runtime.memory.write64(batch+32,64)
    before = h.snapshot()
    assert h.call("RTE-FAMILY-BATCH-PREFLIGHT",batch,out,h.shell)[0] == (0,)
    assert h.snapshot() == before
    q = struct.unpack("<68Q",h.read(out,544))
    assert q[15:23] == (3,6,16,3,3,0,0,6)
    assert q[23:57] == (0,)*34
    assert q[57:] == (1,1,1,3,0,0,0,0,0,3,1|64|0x800)
    # Controls consume the same object namespace even without another object family.
    h.runtime.memory.write64(out+472,0)
    h.runtime.memory.write64(out+480,0)
    assert h.call("RTAPT-FAMILY-PREFLIGHT",out,h.engine)[0] == (3,)
    assert h.snapshot() == before

def test_bridge_pane_and_taskbar_capture_owns_text_and_maps_minimized(bridge):
    h = bridge
    _,_,records = h.graph(mixed=True)
    h.begin_regions(records)
    for index in range(3):
        assert h.call("RTE-CONTROL-DEFINE",records["control"]+index*200,h.facade)[0] == (0,)
    assert h.call("RTE-PANE-DEFINE",records["pane"],h.shell)[0] == (0,)
    h.runtime.memory.write_bytes(records["title"],b"Next")
    h.runtime.memory.write64(records["pane"]+152,0)
    assert h.call("RTE-PANE-REPLACE",records["pane"],h.shell)[0] == (0,)
    h.runtime.memory.write_bytes(records["title"],b"XXXX")
    h.runtime.memory.write_bytes(records["control_text"],b"XXXXXX")
    h.publish()
    owner = h.installed()
    assert owner.objects[7].body.title == "Next"
    assert not owner.objects[7].body.focused
    assert owner.objects[7].body.content_region_id == 2
    assert [owner.controls[i].kind.value for i in (1,2,3)] == [10,11,12]
    assert owner.controls[2].state == 35
    assert owner.controls[2].label == "App"
    assert owner.controls[3].label == "Run"


def test_bridge_preflight_refusal_preserves_output_and_provider(bridge):
    h = bridge
    batch,out,_ = h.graph()
    original = h.read(out,544)
    caps,_ = h.call("PT-RETAINED-CAPS@",h.field("_RTAPT-E.SESSION"))[0]
    features = h.runtime.memory.read64(caps+8)
    h.runtime.memory.write64(caps+8,features & ~int(RetainedFeature.PANES))
    assert h.call("RTE-LIMITS@",h.limits,h.facade)[0] == (0,)
    before = h.snapshot()
    assert h.call("RTE-FAMILY-BATCH-PREFLIGHT",batch,out,h.shell)[0] == (2,)
    assert h.read(out,544) == original
    assert h.snapshot() == before
    h.runtime.memory.write64(caps+8,features)
    assert h.call("RTE-LIMITS@",h.limits,h.facade)[0] == (0,)
    copy_u = h.call("_RTAPT-E.COPY-U",h.engine)[0][0]
    capacity = h.runtime.memory.read64(copy_u)
    h.runtime.memory.write64(copy_u,392)
    before = h.snapshot()
    assert h.call("RTE-FAMILY-BATCH-PREFLIGHT",batch,out,h.shell)[0] == (3,)
    assert h.read(out,544) == original
    assert h.snapshot() == before
    h.runtime.memory.write64(copy_u,capacity)


def test_bridge_aliases_refuse_before_mutation(bridge):
    h = bridge
    batch,out,records = h.graph()
    for destination in (batch,h.facade,h.shell,h.engine,h.field("_RTAPT-E.COPY-A")):
        before = h.snapshot()
        source = h.read(batch,72)
        shell = h.read(h.shell,56)
        assert h.call("RTE-FAMILY-BATCH-PREFLIGHT",batch,destination,h.shell)[0] == (5,)
        assert h.read(batch,72) == source
        assert h.read(h.shell,56) == shell
        assert h.snapshot() == before
    before = h.snapshot()
    h.runtime.memory.write64(records["pane"]+160,h.shell)
    assert h.call("RTE-PANE-DEFINE",records["pane"],h.shell)[0] == (5,)
    assert h.snapshot() == before
    assert h.read(out,544) == b"A"*544


def test_complete_bridge_dependency_closure_compiles_in_cold_kdos():
    """Resolve real REQUIRE edges and compile the complete product bridge in KDOS."""
    import time
    import test_rich_terminal_engine_source_load as cold

    modules = cold.dependency_order(cold.SOURCE_ROOT, ("tui/rich-terminal/engine-apt1.f",))
    assert modules.index("tui/rich-terminal/region-catalog.f") < modules.index("tui/rich-terminal/family-batch.f")
    assert modules.index("tui/rich-terminal/provider-family.f") < modules.index("tui/rich-terminal/engine-apt1.f")
    source = cold._source_lines(cold.KDOS_PATH) + ["ENTER-USERLAND"]
    source.extend(cold._source_lines(cf.RICH_TERMINAL_SOURCE))
    for module in modules:
        source.extend(cold._source_lines(cold.SOURCE_ROOT / module))
    source.extend((": FB-CLOSURE-PROBE 30 EMIT RTE-FAMILY-ADMISSION-SIZE . "
                   "RTE-SHELL-FACADE-SIZE . RTE-FACADE-SIZE . "
                   "_RTAPTE-SHELL-LAYOUT? . 31 EMIT ;", "FB-CLOSURE-PROBE"))
    system = cold.MegapadSystem(ram_size=1 << 20, ext_mem_size=16 << 20)
    output = bytearray()
    system.uart.on_tx = output.append
    system.load_binary(0, cold.assemble(cold.BIOS_PATH.read_text(encoding="utf-8")))
    system.boot()
    payload = ("\n".join(source)+"\n").encode()
    position = 0
    complete = False
    deadline = time.monotonic()+BRIDGE_SOURCE_LOAD_WALL_SECONDS
    while time.monotonic() < deadline:
        if system.cpu.halted:
            break
        if system.cpu.idle and not system.uart.has_rx_data:
            if position >= len(payload):
                complete = True
                break
            line = cold._next_line(payload,position)
            system.uart.inject_input(line)
            position += len(line)
            continue
        system.run_batch(cold.RUN_BATCH_STEPS)
    assert complete, "bridge source load did not quiesce"
    assert not system.cpu.halted
    assert not cold._forth_errors(output), cold._forth_errors(output)[-10:]
    start = output.find(b"\x1e")
    end = output.find(b"\x1f",start+1)
    assert start >= 0 and end > start
    assert output[start+1:end].split() == [b"544",b"56",b"256",b"-1"]
