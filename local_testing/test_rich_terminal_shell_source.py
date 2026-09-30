"""Bounded native shell provenance and exact acknowledged lifecycle probes."""
from dataclasses import replace
import json
import struct

import pytest
import akashic_tui  # noqa: F401
import rich_terminal_desktop_acceptance as a
from rich_terminal.retained_scene import ControlKind, ControlState, ObjectBounds
from rich_terminal.retained_view import PaneDraw, TaskBarDraw, TaskDraw
from test_rich_terminal_shell_acceptance import _region, _glyph, _offer

MASK = (1 << 64) - 1
R = a._LogicalRectangle
ERROR = a.PhysicalDesktopAcceptanceError


def fixture(selected=1, minimized=0, revision=1):
    """Independent ordinary entry table plus real validated retained draw values."""
    entries = []
    for slot in range(1, 7):
        if slot == minimized:
            continue
        col, row = ((slot - 1) % 3) * 4, ((slot - 1) // 3) * 3
        entries.append([slot, 1, int(slot == selected), row, col, 3, 4,
                        row, col, 3, 4, 100 + slot, 10 + slot, slot, slot,
                        "", f"Pane {slot}", ""])
    for slot in range(1, 7):
        entries.append([slot, 2, int(slot == selected) | (2 if slot == minimized else 0),
                        7, slot - 1, 1, 1, 0, 0, 0, 0, 100 + slot, 10 + slot,
                        slot, slot, str(slot), f"Task {slot}", ""])
    entries.append([1, 3, 32, 7, 8, 1, 4, 0, 0, 0, 0, 50, 2, 99, 1,
                    "Run!", "Launch existing.", "app.one"])
    size = 128 + len(entries) * 168
    strings = bytearray()
    records = []
    for entry in entries:
        record = entry[:15]
        for text in entry[15:]:
            raw = text.encode()
            record += [size + len(strings) if raw else 0, len(raw)]
            strings += raw
        records.extend(record)
    size += len(strings)
    header = [1, size, len(entries), len(entries), size, 50, 2, revision, 12, 8, 0, 6, 12, MASK, 0, 0]
    payload = struct.pack(f'<{16 + len(records)}Q', *header, *records) + strings
    model = a._decode_shell_model(bytes(payload))
    correlations = []
    panes, regions, tasks = [], [], []
    owner, generation = 7, 9
    actions = b'app.one'
    for entry in model.entries:
        index = entry.index
        b = entry.bounds
        rid = 10 + entry.identity if entry.kind == 1 else 2
        object_id = 1000 + entry.identity if entry.kind == 1 else 2000 + index
        content = rid if entry.kind == 1 else 0
        row = [index, entry.kind, entry.key, entry.identity, entry.owner_id, entry.owner_generation,
               object_id, 1 if entry.kind == 1 else 2, content,
               50, 2, revision, revision, 50, entry.action,
               0, len(entry.action_id.encode()), b.top, b.left, b.bottom - b.top, b.right - b.left,
               0, len((entry.title if entry.kind == 1 else entry.label).encode()), entry.flags]
        correlations.append(tuple(row))
        if entry.kind == 1:
            panes.append(PaneDraw(object_id, 0, ObjectBounds(b.left,b.top,4,3), rid,
                                 ObjectBounds(0,0,4,3), entry.title, bool(entry.flags & 1)))
            regions.append(_region(rid, tuple(_glyph(entry.identity*100+y,b.left,y,'....')
                                for y in range(b.top,b.bottom)),z=1,clip=(b.left,b.top,4,3)))
        else:
            state = 3 | (8 if entry.flags & 1 else 0) | (32 if entry.flags & 2 else 0) if entry.kind == 2 else 3
            tasks.append(TaskDraw(object_id,ControlKind.TASK if entry.kind == 2 else ControlKind.LAUNCHER,
                                 ControlState(state),index,ObjectBounds(b.left if entry.kind == 2 else 0,0,
                                                                      b.right-b.left,1),entry.label))
    task_root = TaskBarDraw(3001,ControlState(3),0,0,ObjectBounds(0,7,6,1),tuple(tasks[:-1]))
    launcher_root = TaskBarDraw(3002,ControlState(3),0,0,ObjectBounds(8,7,4,1),(tasks[-1],))
    for index, kind, control, col, width in ((-1,4,3001,0,6),(-2,5,3002,8,4)):
        correlations.append((index & MASK,kind,0,0,50,2,control,2,0,50,2,revision,revision,50,
                             0,0,0,7,col,1,width,0,0,0))
    # The full opaque residual precedes the content regions, not above them.
    residual = []
    occupied = {(x,y) for entry in model.entries if entry.kind == 1
                for x in range(entry.bounds.left,entry.bounds.right)
                for y in range(entry.bounds.top,entry.bounds.bottom)}
    for y in range(8):
        for x in range(12):
            if (x,y) not in occupied and not (y == 7 and (x < 6 or x >= 8)):
                residual.append(_glyph(4000+y*12+x,x,y,'.'))
    offer = _offer((_region(1,panes,z=-3,clip=(0,0,12,8)),
                    _region(3,residual,z=-2),*regions,
                    _region(2,(task_root,launcher_root),z=2,clip=(0,7,12,1))))
    offer = replace(offer, offer_id=revision,
                    scope=replace(offer.scope,model_revision=revision,cell_revision=revision,retained_revision=revision))
    projection = a.reconstruct_retained_screen(offer, require_menu_bar=False)
    source = a.ShellSource(model,tuple(correlations),actions,owner,generation,revision,revision,revision,
                          ((len(entries)-1,1),),{'work_capacity':65536,'work_used':12000+revision,
                          'bank_capacity':40960,'bank_used':8192,'model_bytes':len(payload)})
    return bytes(payload), source, offer, projection


class SourceClient:
    """Sparse bounded guest memory; a read outside populated spans is an error."""
    P=0x10000; E=0x20000; S=0x30000; B=0x40000; SHSN=0x50000; MODEL=0x60000
    TARGET=0x70000; INSTANCE=0x80000; STATE=0x90000; CATALOG=0xA0000
    SESSION=0xB0000; SCREEN=0xF0000; HOST=0xF1000; BORROWED=0xF2000

    def __init__(self, paused=False):
        payload,self.source,self.offer,self.projection=fixture()
        self.paused=paused; self.calls=[]; self.memory={}; self.words={}
        p=[0]*517; p[:3]=[0x3250444952425948,4136,self.P]
        p[5:7]=[self.TARGET,672];p[296:298]=[self.TARGET,self.TARGET+336]
        p[11:13]=[7,9];p[57]=1;p[298]=self.TARGET;p[302]=1;p[516]=self.S+176
        e=[0]*42;e[0]=0x5254415054454E47;e[1]=self.SESSION;e[31]=1;e[32:]=[1,0x2001,0,0,5,1,0,0,0,0]
        session=[0]*124;session[15]=3;session[19]=1;session[24:26]=[12,8]
        self.put(self.SESSION,session)
        s=[0]*30;s[:5]=[0x5253485350303031,240,self.S,self.P,self.SHSN]
        s[6:12]=[0xC0000,65536,self.B,40960,0xD0000,40960]
        s[12]=self.B;s[14]=self.TARGET;s[16]=1;s[19]=12001;s[20]=64;s[21]=49152
        s[22:]=[0x5254485045585431,64,self.S+176,self.S,0,0,0,0]
        self.put(self.P,p);self.put(self.E,e);self.put(self.S,s)
        corr=struct.pack(f'<{len(self.source.correlations)*24}Q',*(v for r in self.source.correlations for v in r))
        align=lambda n:(n+7)&~7
        mo=128;co=align(mo+len(payload));ao=align(co+len(corr));batch=align(ao+len(self.source.actions))
        b=[batch+128,batch,mo,len(payload),co,len(corr),ao,len(self.source.actions),0,0,
           self.TARGET,1,7,9,99,99]
        bank=bytearray(b[0]);bank[:128]=struct.pack('<16Q',*b)
        bank[mo:mo+len(payload)]=payload;bank[co:co+len(corr)]=corr;bank[ao:ao+len(self.source.actions)]=self.source.actions
        self.put(self.B,bank)
        self.put(self.TARGET,[7,9,12,8,0,1,0,1]+[0]*17+[0x3354475450485452]+[0]*16)
        shsn=[0x31534E53484B4141,160,self.SHSN,self.MODEL,49152,0xE0000,49152,
              self.MODEL,len(payload),1,self.SCREEN,0,self.INSTANCE,self.HOST,self.BORROWED,0,0,0,12,8]
        self.put(self.SHSN,shsn);self.put(self.MODEL,payload+b'\0'*7)
        self.put(self.BORROWED,payload+b'\0'*7)
        self.put(self.SCREEN,[12,8]+[0]*9+[1]);self.put(self.HOST,[0]*16+[self.BORROWED])
        self.put(self.INSTANCE,[1,self.STATE,50,2,1,0,0,0,0,0]);self.put(self.STATE,[self.CATALOG])
        self.put(self.CATALOG,[0x4143415444455343,0,0,99,1])
        catalog_entry=bytearray(496);struct.pack_into('<3Q',catalog_entry,0,1,0,7)
        catalog_entry[48:55]=b'app.one';struct.pack_into('<Q',catalog_entry,488,1)
        self.put(self.CATALOG+1232,catalog_entry)
        for name,address,values in (('_RTAPTSCBOP-CONTEXT',0x101,[self.P]),
             ('_RTAPTSCBI-ENGINE',0x201,[self.E]),('_DESK-CURRENT-STATE',0x301,[0]),
             ('_DESK-CATALOG',0x401,[0x301,0])):
            self.words[name]={'data_address':address};self.put(address,values)
        values={'_SHSN-INSTALLED':self.SHSN,'_SHSN-REFUSED':0,'_SCR-CUR':self.SCREEN,
                '_SHSN-H-H':self.HOST,'_SHSN-H-M':self.BORROWED,
                '_AH-SHELL-OBSERVER':0x777,'_AH-SHELL-OBSERVER-CTX':self.SHSN,
                '_ASHELL-DRAW-OBSERVER':0x888,'_ASHELL-DRAW-OBSERVER-CTX':self.SHSN}
        for index,(name,value) in enumerate(values.items()):
            address=0x501+index*16;self.words[name]={'data_address':address};self.put(address,[value])
        self.words['_SHSN-HOST-CALL']={'code':0x777};self.words['_SHSN-DRAW-CALL']={'code':0x888}

    def put(self,address,data):
        self.memory[address]=bytearray(struct.pack(f'<{len(data)}Q',*data) if isinstance(data,list) else data)

    def cell(self,address,index,value):
        struct.pack_into('<Q',self.memory[address],index*8,value)

    def request(self,method,**params):
        self.calls.append((method,params))
        if method=='status':return {'paused':self.paused,'error':None,'generation':11}
        if method in ('pause','resume'):
            self.paused=method=='pause';return {'paused':self.paused}
        if method=='forth':return {'words':{name:self.words[name] for name in params['names']}}
        assert method=='peek' and self.paused
        address,count=params['address'],params['count'];assert 1<=count<=256
        for base,raw in self.memory.items():
            if base<=address and address+count*8<=base+len(raw):
                return {'address':address,'cell_size':8,'values':list(struct.unpack_from(f'<{count}Q',raw,address-base))}
        raise AssertionError(f'out-of-fixture guest read {address:x}/{count}')


def test_native_shm_builder_and_snapshot_validator_decode_without_label_inference():
    from test_field_model import field_runtime
    from test_shell_snapshot import PRELUDE
    runtime=field_runtime(('tui/shell-snapshot.f',))
    runtime.evaluate((PRELUDE+'\n_SS-BUILD _SS-FREEZE _SS-VALID . _SS-F _SS-U @').encode(),
                     source_name='shell-python-oracle',step_budget=30_000_000)
    address,size=runtime.main_context.data.snapshot()
    assert runtime.drain_uart_output().decode().strip()=='0'
    model=a._decode_shell_model(runtime.memory.read_bytes(address,size))
    assert [(entry.kind,entry.component) for entry in model.entries]==[(1,(11,2,3)),(2,(11,2,3)),(3,(99,7,9))]
    assert model.entries[0].title=='Editor' and model.entries[2].action_id=='start'
    assert model.entries[0].content_bounds==R(0,0,19,9)


@pytest.mark.parametrize('offset,value',[(0,2),(8,0),(24,100),(32,127),(40,0),(48,0),(56,0),(64,0),
    (72,1<<32),(80,4),(88,12),(96,13),(104,0),(112,1),(128+8,4),(128+16,2),
    (128+24,8),(128+48,13),(128+88,0),(128+104,0),(128+15*8,100)])
def test_model_decoder_rejects_forged_owned_header_entry_and_text_extent(offset,value):
    payload,*_=fixture();raw=bytearray(payload);struct.pack_into('<Q',raw,offset,value)
    with pytest.raises(ERROR):a._decode_shell_model(bytes(raw))


def test_reader_owns_complete_model_and_correlations_and_restores_pause():
    client=SourceClient();source=a._read_shell_source(client,client.offer,11)
    evidence=a._require_shell_source_evidence(client.projection,client.offer,11,source)
    assert evidence['pane_count']==6 and evidence['taskbar_count']==2
    assert source.launcher_slots==((12,1),) and source.memory['work_used']==12001
    assert not client.paused
    client.memory[client.B][:]=b'\0'*len(client.memory[client.B])
    assert source.model.entries[-1].action_id=='app.one'
    assert all(params['count']<=256 for method,params in client.calls if method=='peek')
    assert [method for method,_ in client.calls][-1]=='resume'


@pytest.mark.parametrize('address,index,value',[
    (SourceClient.P,0,0),(SourceClient.S,0,0),(SourceClient.S,12,1234),(SourceClient.S,19,65537),
    (SourceClient.B,0,40961),(SourceClient.B,2,127),(SourceClient.B,3,49153),
    (SourceClient.B,4,129),(SourceClient.B,5,193),(SourceClient.B,6,1),
    (SourceClient.B,0,8191),(SourceClient.P,296,0),(SourceClient.P,6,335),
    (SourceClient.SHSN,8,49153),(SourceClient.INSTANCE,2,999),
    (SourceClient.CATALOG,4,33),(SourceClient.CATALOG,3,100),
])
def test_reader_rejects_malformed_spans_before_payload_reads_and_resumes(address,index,value):
    client=SourceClient();client.cell(address,index,value)
    with pytest.raises(ERROR):a._read_shell_source(client,client.offer,11)
    assert not client.paused


@pytest.mark.parametrize('address,index,value',[
    (SourceClient.E,14,3),(SourceClient.E,15,1),(SourceClient.E,31,2),
    (SourceClient.E,32,0),(SourceClient.E,33,0),(SourceClient.E,36,0),
    (SourceClient.E,37,2),(SourceClient.E,38,1),(SourceClient.S,14,8),
    (SourceClient.SHSN,9,2),(SourceClient.SHSN,11,MASK),
    (SourceClient.SESSION,15,4),(SourceClient.SESSION,19,2),(SourceClient.SESSION,33,1),
    (SourceClient.SESSION,54,1),(SourceClient.SESSION,24,13),(SourceClient.SESSION,37,MASK),
    (SourceClient.SESSION,48,MASK),(SourceClient.SESSION,51,1),(SourceClient.SCREEN,11,2),
    (SourceClient.HOST,16,1234),
])
def test_reader_waits_for_exact_idle_present_and_current_native_draw(address,index,value):
    client=SourceClient(paused=True);client.cell(address,index,value)
    assert a._read_shell_source(client,client.offer,11) is None
    assert client.paused and not any(method=='resume' for method,_ in client.calls)


def test_reader_transport_failure_does_not_resume_a_lost_boundary():
    client=SourceClient();request=client.request
    def broken(method,**params):
        if method=='peek':raise ConnectionError('lost boundary')
        return request(method,**params)
    client.request=broken
    with pytest.raises(ConnectionError):a._read_shell_source(client,client.offer,11)
    assert client.paused and not any(method=='resume' for method,_ in client.calls)


@pytest.mark.parametrize('name,value',[('_SHSN-INSTALLED',0),('_SHSN-REFUSED',MASK),
    ('_SCR-CUR',0),('_SHSN-H-H',1),('_SHSN-H-M',1),('_AH-SHELL-OBSERVER',1),
    ('_AH-SHELL-OBSERVER-CTX',1),('_ASHELL-DRAW-OBSERVER',1),('_ASHELL-DRAW-OBSERVER-CTX',1)])
def test_reader_refuses_replaced_hooks_refused_draw_or_foreign_live_source(name,value):
    client=SourceClient();client.cell(client.words[name]['data_address'],0,value)
    assert a._read_shell_source(client,client.offer,11) is None
    assert not client.paused


def test_reader_does_not_peek_a_guest_from_another_execution_generation():
    client=SourceClient()
    assert a._read_shell_source(client,client.offer,12) is None
    assert [method for method,_ in client.calls]==['status']


def test_reader_matches_live_borrowed_model_even_when_frozen_banks_still_agree():
    client=SourceClient();client.cell(client.BORROWED,7,2)
    assert a._read_shell_source(client,client.offer,11) is None
    assert not client.paused


@pytest.mark.parametrize('which',('copied_action','catalog_action','catalog_flags','catalog_id_extent','cmp_owner','cmp_extent'))
def test_reader_refuses_catalog_or_dictionary_provenance_mismatch(which):
    client=SourceClient()
    if which=='copied_action':
        b=struct.unpack_from('<16Q',client.memory[client.B]);client.memory[client.B][b[6]]=ord('x')
        # Reader copies bytes; source/retained bijection must reject corruption.
        source=a._read_shell_source(client,client.offer,11)
        with pytest.raises(ERROR):a._require_shell_source_evidence(client.projection,client.offer,11,source)
        return
    if which=='catalog_action':client.memory[client.CATALOG+1232][48]=ord('x')
    if which=='catalog_flags':client.cell(client.CATALOG+1232,0,9)
    if which=='catalog_id_extent':client.cell(client.CATALOG+1232,2,65)
    if which=='cmp_owner':client.cell(0x401,0,0x999)
    if which=='cmp_extent':client.cell(0x401,1,1<<40)
    with pytest.raises(ERROR):a._read_shell_source(client,client.offer,11)
    assert not client.paused


def test_exact_sized_unaligned_model_tail_never_reads_outside_owned_bytes():
    client=SourceClient();raw=client.memory[client.BORROWED]
    size=struct.unpack_from('<Q',raw,32)[0]
    assert size%8
    client.memory[client.BORROWED]=raw[:size]
    assert a._read_shell_source(client,client.offer,11) is not None
    reads=[p for method,p in client.calls if method=='peek' and client.BORROWED<=p['address']<client.BORROWED+size]
    assert all(p['address']+p['count']*8<=client.BORROWED+size for p in reads)
    assert reads[-1]['address']==client.BORROWED+size-8


@pytest.mark.parametrize('index,value',[(0,99),(2,999),(3,999),(4,999),(5,999),(6,999),
    (7,999),(8,999),(9,999),(10,999),(11,999),(12,999),(13,999),(14,999),(15,999),
    (16,999),(17,999),(18,999),(19,999),(20,999),(22,999),(23,999)])
def test_projection_provenance_refuses_each_wrong_identity_state_extent_or_lineage(index,value):
    _,source,offer,projection=fixture();rows=list(source.correlations);row=list(rows[0]);row[index]=value;rows[0]=tuple(row)
    with pytest.raises(ERROR):a._require_shell_source_evidence(projection,offer,1,replace(source,correlations=tuple(rows)))


def test_probe_requires_all_four_ordinary_transitions_and_final_launcher_result():
    probe=a.ShellAcceptanceProbe();sent=[]
    def sender(method,value,offer,generation):
        sent.append((method,value,offer.offer_id,generation));return 'progress'
    for selected,minimized,revision,expected in ((1,0,1,1),(2,0,2,2),(1,2,3,3),(2,0,4,4),(1,0,5,5)):
        _,source,offer,projection=fixture(selected,minimized,revision)
        if expected==5:
            assert not probe.after_present(projection,offer,revision+10,sender,lambda:None)
            assert probe.awaiting_source and not probe.complete and len(sent)==4
        complete=probe.after_present(projection,offer,revision+10,sender,lambda:source)
        assert probe.stage==expected and complete==(expected==5)
        assert not probe.awaiting_source
        if expected==4:assert not probe.complete
    assert [item[0] for item in sent]==['activate_shell_task','send_key','activate_shell_task','activate_shell_launcher']
    assert sent[1][1]=='alt+m' and probe.evidence['launcher']['component']==[1,101,11]
    assert len(probe.evidence['snapshots'])==5 and probe.evidence['memory_max']['work_used']==12005
    json.dumps(probe.evidence)


def test_probe_retries_only_same_ack_and_does_not_reuse_minimized_slot_ids():
    probe=a.ShellAcceptanceProbe();_,source,offer,projection=fixture()
    sent=[]
    def blocked(*args):sent.append(args);return 'backpressured'
    assert not probe.after_present(projection,offer,7,blocked,lambda:source)
    assert probe.stage==0 and probe.pending is not None
    assert not probe.retry_pending_current(offer,7,blocked)
    with pytest.raises(ERROR):probe.retry_pending_current(replace(offer,offer_id=2),7,blocked)
    assert len(sent)==2
    assert probe.retry_pending_current(offer,7,lambda *_:'progress') and probe.stage==1
    assert not probe.after_present(projection,offer,7,blocked,lambda:pytest.fail('must wait for new offer'))


def test_probe_does_not_complete_or_send_input_on_stale_source_or_unobserved_focus():
    probe=a.ShellAcceptanceProbe();_,source,offer,projection=fixture()
    assert not probe.after_present(projection,offer,1,lambda *_:pytest.fail('no source'),lambda:None)
    assert probe.awaiting_source
    assert not probe.after_present(projection,offer,1,lambda *_:'progress',lambda:source)
    _,source,offer,projection=fixture(revision=2)
    assert not probe.after_present(projection,offer,2,lambda *_:pytest.fail('focus not observed'),lambda:source)
    assert probe.stage==1


def _runner_same_ack_tick(tmp_path, probe, offer, projection, source_reader, sender):
    """Execute the actual runner's nested helpers and no-new-offer branch.

    Loading its CLI module would launch Desk. Extract its executable statements
    instead; only transport, time and artifact sinks are supplied by this test.
    No draw/present/ACK functions are supplied, so a duplicate use fails here.
    """
    import ast
    import copy
    from pathlib import Path
    from types import SimpleNamespace

    tree=ast.parse(Path(__file__).with_name('run_headless_grid_acceptance.py').read_text())
    functions={node.name:node for node in ast.walk(tree) if isinstance(node,ast.FunctionDef)}
    no_offer=next(node for node in ast.walk(functions['run_journey'])
                  if isinstance(node,ast.If) and ast.unparse(node.test)=='offer is None')
    wrapper=ast.parse('''
def make_tick():
    shell_deadline = 100.0
    last_progress = 100.0
    def tick():
        nonlocal shell_deadline, last_progress
        for _ in range(1):
            pass
    def deadline():
        return shell_deadline
    return tick, deadline
''')
    body=wrapper.body[0].body
    body[2:2]=[copy.deepcopy(functions[name]) for name in ('advance_shell','finish_acceptance')]
    tick=next(node for node in body if isinstance(node,ast.FunctionDef) and node.name=='tick')
    tick.body[1].body=[copy.deepcopy(no_offer)]
    clock=SimpleNamespace(now=60.0)
    saves=[];calls=[];report={}
    def request(method,**params):
        calls.append((method,params))
        assert method=='status'
        return {'runtime':{'mode':'simulator','executor':'native'}}
    namespace={'shell_probe':probe,'last_offer':offer,'last_generation':11,'last_projection':projection,
               'offer':None,'send_input':sender,'series_probe':None,
               'journey':SimpleNamespace(has_pending_input=False,stage=52,waiting='finished'),
               'time':SimpleNamespace(monotonic=lambda:clock.now,sleep=lambda _:None),
               'status':{},'OUT':tmp_path,'previous':SimpleNamespace(surface=object()),
               'pygame':SimpleNamespace(image=SimpleNamespace(save=lambda _surface,path:saves.append(path))),
               'display_offer_to_wire':lambda current:{'offer_id':current.offer_id},'json':json,
               'report':report,'checked_probe':lambda callback,*_:callback(),
               '_read_shell_source':lambda client,current,generation:source_reader(current,generation),
               'args':SimpleNamespace(require_status_fields=False),'client':SimpleNamespace(request=request)}
    exec(compile(ast.fix_missing_locations(wrapper),'<actual Desk same-ACK branch>','exec'),namespace)
    return (*namespace['make_tick'](),clock,report,saves,calls)


def test_runner_same_ack_source_retry_finishes_without_new_offer_input_or_ack(tmp_path):
    probe=a.ShellAcceptanceProbe();sent=[]
    def sender(*args):sent.append(args);return 'progress'
    for selected,minimized,revision in ((1,0,1),(2,0,2),(1,2,3),(2,0,4)):
        _,source,offer,projection=fixture(selected,minimized,revision)
        assert not probe.after_present(projection,offer,11,sender,lambda:source)
    _,source,offer,projection=fixture(1,0,5)
    assert not probe.after_present(projection,offer,11,sender,lambda:None)
    results=iter((None,source));reads=[]
    def reader(current,generation):
        assert current is offer and generation==11
        reads.append(current.offer_id);return next(results)
    tick,deadline,clock,report,saves,calls=_runner_same_ack_tick(tmp_path,probe,offer,projection,reader,sender)
    tick()
    assert deadline()==100 and probe.stage==4 and len(sent)==4 and reads==[5]
    assert not saves and not calls
    clock.now=61;tick()
    assert deadline() is None and probe.complete and len(sent)==4 and reads==[5,5]
    assert len(saves)==1 and saves[0].endswith('Desk-Shell-Verified.png')
    assert calls==[('status',{'detailed':False})] and report['final_runtime']['executor']=='native'
    assert json.loads((tmp_path/'shell-offer.json').read_text())=={'offer_id':5}
    assert report['shell_probe']['snapshots'][-1]['stage']==4


def test_runner_same_ack_backpressure_does_not_extend_deadline_or_repeat_action(tmp_path):
    probe=a.ShellAcceptanceProbe();_,source,offer,projection=fixture()
    assert not probe.after_present(projection,offer,11,lambda *_:pytest.fail('no native source'),lambda:None)
    statuses=iter(('backpressured','backpressured','progress'));attempts=[];reads=[]
    def sender(method,value,current,generation):
        attempts.append((method,value,current.offer_id,generation));return next(statuses)
    def reader(current,generation):reads.append(current.offer_id);return source
    tick,deadline,clock,report,saves,calls=_runner_same_ack_tick(tmp_path,probe,offer,projection,reader,sender)
    tick()
    assert probe.pending and probe.stage==0 and deadline()==100 and reads==[1]
    clock.now=61;tick()
    assert probe.stage==0 and deadline()==100 and len(attempts)==2 and reads==[1]
    clock.now=62;tick()
    assert probe.pending is None and probe.stage==1 and deadline()==102 and len(attempts)==3
    assert attempts[0]==attempts[1]==attempts[2]
    clock.now=63;tick()
    assert deadline()==102 and len(attempts)==3 and reads==[1]
    assert len(probe.evidence['actions'])==1 and not saves and not calls


def test_decoder_rejects_signed_min_overlay_key_like_native_snapshot_validator():
    payload,*_=fixture();raw=bytearray(payload)
    for index,value in ((0,1<<63),(2,8),(13,1<<63),(14,1<<63)):
        struct.pack_into('<Q',raw,128+index*8,value)
    with pytest.raises(ERROR,match='lifecycle identity'):a._decode_shell_model(bytes(raw))


def test_probe_valid_source_with_old_focus_cannot_satisfy_final_launcher_transition():
    probe=a.ShellAcceptanceProbe();sent=[]
    def sender(*args):sent.append(args);return 'progress'
    for selected,minimized,revision in ((1,0,1),(2,0,2),(1,2,3),(2,0,4)):
        _,source,offer,projection=fixture(selected,minimized,revision)
        probe.after_present(projection,offer,11,sender,lambda:source)
    _,source,offer,projection=fixture(2,0,5)
    assert not probe.after_present(projection,offer,11,sender,lambda:source)
    assert probe.stage==4 and not probe.complete and len(sent)==4
    _,source,offer,projection=fixture(1,0,6)
    assert probe.after_present(projection,offer,11,sender,lambda:source)
    assert probe.complete and len(sent)==4


def test_probe_rejects_reincarnated_component_even_with_matching_native_correlations():
    probe=a.ShellAcceptanceProbe();_,source,offer,projection=fixture()
    probe.after_present(projection,offer,11,lambda *_:'progress',lambda:source)
    _,source,offer,projection=fixture(2,0,2)
    changed={entry.index for entry in source.model.entries if entry.kind in (1,2) and entry.identity==1}
    entries=tuple(replace(entry,owner_generation=999) if entry.index in changed else entry
                  for entry in source.model.entries)
    rows=[]
    for row in source.correlations:
        if row[0] in changed:
            row=list(row);row[5]=999;row=tuple(row)
        rows.append(row)
    source=replace(source,model=replace(source.model,entries=entries),correlations=tuple(rows))
    # This is a coherent new native component, but not the original task.
    a._require_shell_source_evidence(projection,offer,11,source)
    with pytest.raises(ERROR,match='ordinary task lifecycle identities changed'):
        probe.after_present(projection,offer,11,lambda *_:pytest.fail('no reincarnated target'),lambda:source)
