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


@pytest.mark.parametrize('address,index,value,reason',[
    (SourceClient.SESSION,48,1,'active-session-scope-or-output-state'),
    (SourceClient.E,31,2,'idle-provider-present-revision'),
    (SourceClient.E,32,0,'successful-present-completion'),
    (SourceClient.S,14,8,'acknowledged-target-draw'),
    (SourceClient.SHSN,9,2,'current-snapshot-observer-and-draw'),
    (SourceClient.SCREEN,11,2,'current-screen-and-borrowed-model'),
    (SourceClient.BORROWED,7,2,'current-borrowed-model-bytes'),
])
def test_reader_optional_diagnostics_identify_pending_without_extra_reads(address,index,value,reason):
    plain=SourceClient();plain.cell(address,index,value)
    observed=SourceClient();observed.cell(address,index,value)
    diagnostics={'old-result':'must-be-cleared'}
    assert a._read_shell_source(plain,plain.offer,11) is None
    assert a._read_shell_source(observed,observed.offer,11,diagnostics=diagnostics) is None
    assert observed.calls==plain.calls and not observed.paused
    assert diagnostics['pending_reason']==reason and 'old-result' not in diagnostics
    assert diagnostics['engine'][31]==(value if address==SourceClient.E and index==31 else 1)
    assert diagnostics['generation']==11 and diagnostics['offer_id']==observed.offer.offer_id
    json.dumps(diagnostics)


def test_reader_optional_diagnostics_report_ready_without_extra_reads():
    plain=SourceClient();observed=SourceClient();diagnostics={}
    expected=a._read_shell_source(plain,plain.offer,11)
    assert a._read_shell_source(observed,observed.offer,11,diagnostics=diagnostics)==expected
    assert observed.calls==plain.calls and diagnostics['ready'] and diagnostics['pending_reason'] is None
    assert diagnostics['snapshot'][9]==expected.draw and diagnostics['target'][7]==expected.physical_generation
    json.dumps(diagnostics)


def test_reader_matches_actual_desk_arena_without_limiting_unread_storage():
    client=SourceClient();client.cell(client.P,6,94107960)
    assert a._read_shell_source(client,client.offer,11) is not None
    target_reads=[params for method,params in client.calls if method=='peek' and params['address']==client.TARGET]
    assert target_reads==[{'address':client.TARGET,'count':42}]


def test_reader_allows_header_ending_exactly_at_the_arena_end():
    client=SourceClient();client.cell(client.P,6,336)
    assert a._read_shell_source(client,client.offer,11) is not None


@pytest.mark.parametrize('which',('alien-active','duplicate-slots'))
def test_reader_rejects_foreign_or_ambiguous_target_before_read(which):
    client=SourceClient()
    client.cell(client.P,298,client.TARGET+8) if which=='alien-active' else client.cell(client.P,297,client.TARGET)
    with pytest.raises(ERROR,match='outside the producer-owned arena'):
        a._read_shell_source(client,client.offer,11)
    assert not any(method=='peek' and client.TARGET<=params['address']<client.TARGET+672
                   for method,params in client.calls)


@pytest.mark.parametrize('arena,size,target',[
    (SourceClient.TARGET+8,672,SourceClient.TARGET),
    (SourceClient.TARGET,335,SourceClient.TARGET),
    (SourceClient.TARGET,MASK,SourceClient.TARGET),
    (SourceClient.TARGET,1<<63,SourceClient.TARGET),
    ((1<<63)+8,(1<<63)-8,(1<<63)+8),
    (SourceClient.TARGET,672,SourceClient.TARGET+1),
    (SourceClient.TARGET,336,SourceClient.TARGET+8),
    (0,SourceClient.TARGET+672,SourceClient.TARGET),
])
def test_reader_requires_native_arena_containment_before_target_read(arena,size,target):
    client=SourceClient();client.cell(client.P,5,arena);client.cell(client.P,6,size)
    client.cell(client.P,296,target);client.cell(client.P,298,target)
    diagnostics={}
    with pytest.raises(ERROR,match='outside the producer-owned arena'):
        a._read_shell_source(client,client.offer,11,diagnostics=diagnostics)
    assert not any(method=='peek' and params['address']==target for method,params in client.calls)
    assert diagnostics['producer'][5:7]==[arena,size] and 'bank' in diagnostics and 'target' not in diagnostics
    assert not client.paused


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
    def read_source(client,current,generation,*,diagnostics):
        source=source_reader(current,generation)
        diagnostics.update(fixture_pending=source is None)
        return source
    namespace={'shell_probe':probe,'last_offer':offer,'last_generation':11,'last_projection':projection,
               'offer':None,'send_input':sender,'series_probe':None,
               'journey':SimpleNamespace(has_pending_input=False,stage=52,waiting='finished'),
               'time':SimpleNamespace(monotonic=lambda:clock.now,sleep=lambda _:None),
               'status':{},'OUT':tmp_path,'previous':SimpleNamespace(surface=object()),
               'pygame':SimpleNamespace(image=SimpleNamespace(save=lambda _surface,path:saves.append(path))),
               'display_offer_to_wire':lambda current:{'offer_id':current.offer_id},'json':json,
               'report':report,'checked_probe':lambda callback,*_:callback(),
               '_read_shell_source':read_source,
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
    assert report['shell_last_offer']=={'offer_id':5,'pane_count':6,'taskbar_count':2}
    assert report['shell_source_diagnostic']=={'fixture_pending':True}
    clock.now=61;tick()
    assert deadline() is None and probe.complete and len(sent)==4 and reads==[5,5]
    assert len(saves)==1 and saves[0].endswith('Desk-Shell-Verified.png')
    assert calls==[('status',{'detailed':False})] and report['final_runtime']['executor']=='native'
    assert json.loads((tmp_path/'shell-offer.json').read_text())=={'offer_id':5}
    assert report['shell_probe']['snapshots'][-1]['stage']==4
    assert report['shell_source_diagnostic']=={'fixture_pending':False}


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
    assert report['shell_last_offer']=={'offer_id':1,'pane_count':6,'taskbar_count':2}
    assert report['shell_source_diagnostic']=={'fixture_pending':False}
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


def _readiness_projection(*, selected=False, slot=4):
    from test_rich_terminal_desktop_acceptance import _projection
    projection=_projection('READY\nData')
    # Desk's native task label, not a PANE title; the slot follows launch order.
    label=f'[{slot}:Grid*]' if selected else f'[{slot}:Grid]'
    state=ControlState.VISIBLE|ControlState.ENABLED
    if selected:state|=ControlState.SELECTED
    task=a._SemanticTaskClaim(a.ControlIdentity(1,1,160),ControlKind.TASK,state,8,
                             R(43,83,43+len(label),84),label,'')
    bar=a._SemanticTaskBarClaim(a.ControlIdentity(1,1,156),ControlState(3),R(0,83,62,84),(task,))
    return replace(projection,semantic_taskbar_claims=(bar,))


@pytest.mark.parametrize('slot',(4,1,12))
@pytest.mark.parametrize('selected',(False,True))
def test_readiness_accepts_exact_typed_grid_task_without_inventing_text(selected,slot):
    projection=_readiness_projection(selected=selected,slot=slot)
    text_before=projection.text
    assert 'Grid' not in text_before
    assert a._projection_marker_status(projection,('READY','Data','Grid'))==(True,())
    assert a._marker_status(projection.text,('Grid',))==(False,('Grid',))
    assert projection.text==text_before and 'Grid' not in projection.semantic_lines


@pytest.mark.parametrize('mutation',('root_hidden','root_disabled','task_hidden','task_disabled',
    'minimized','launcher','partial','zero_slot','padded_slot','wrong_row','short_slot','duplicate','wrong_selection','pane_title'))
def test_readiness_rejects_unavailable_or_noncanonical_task_metadata(mutation):
    projection=_readiness_projection();bar=projection.semantic_taskbar_claims[0];task=bar.tasks[0]
    if mutation=='root_hidden':bar=replace(bar,state=ControlState.ENABLED)
    if mutation=='root_disabled':bar=replace(bar,state=ControlState.VISIBLE)
    if mutation=='task_hidden':task=replace(task,state=ControlState.ENABLED)
    if mutation=='task_disabled':task=replace(task,state=ControlState.VISIBLE)
    if mutation=='minimized':task=replace(task,state=task.state|ControlState.MINIMIZED)
    if mutation=='launcher':task=replace(task,kind=ControlKind.LAUNCHER)
    if mutation=='partial':task=replace(task,label='[4:Grid Extra]')
    if mutation=='zero_slot':task=replace(task,label='[0:Grid]',bounds=R(43,83,51,84))
    if mutation=='padded_slot':task=replace(task,label='[04:Grid]',bounds=R(43,83,52,84))
    if mutation=='wrong_row':task=replace(task,bounds=R(43,82,51,83))
    if mutation=='short_slot':task=replace(task,bounds=R(43,83,50,84))
    if mutation=='wrong_selection':task=replace(task,state=task.state|ControlState.SELECTED)
    tasks=(task,task) if mutation=='duplicate' else (task,)
    projection=replace(projection,semantic_taskbar_claims=(replace(bar,tasks=tasks),))
    if mutation=='pane_title':
        pane=a._SemanticPaneClaim(1,1,900,1,2,R(0,0,92,41),R(0,0,92,41),'Grid',False)
        projection=replace(projection,semantic_taskbar_claims=(),semantic_pane_claims=(pane,))
    assert a._projection_marker_status(projection,('READY','Data','Grid'))==(False,('Grid',))
    assert 'Grid' not in projection.text


def test_readiness_preserves_legacy_text_and_does_not_expand_other_markers():
    from test_rich_terminal_desktop_acceptance import _projection
    assert a._projection_marker_status(_projection('Grid'),('Grid',))==(True,())
    projection=_readiness_projection()
    assert a._projection_marker_status(projection,('Grid','Gri','Grid Extra'))==(False,('Gri','Grid Extra'))


def test_journey_stage_zero_uses_same_typed_readiness_with_strict_semantic_gate():
    from test_rich_terminal_desktop_acceptance import _offer as desktop_offer
    projection=_readiness_projection();journey=a.DesktopAcceptanceJourney(('READY','Data','Grid'));sent=[]
    offer=desktop_offer('X',offer_id=1,pad_menu=True)
    journey.after_present(offer,1,projection,lambda *args:sent.append(args) or 'progress')
    assert journey.stage==1 and len(sent)==1 and sent[0][:2]==('send_key','alt+1')
    assert 'Grid' not in projection.text
    broken=replace(projection,semantic_collection_claims=())
    journey=a.DesktopAcceptanceJourney(('READY','Data','Grid'))
    with pytest.raises(ERROR,match='real semantic collection roots'):
        journey.after_present(offer,1,broken,lambda *_:pytest.fail('readiness must not bypass semantics'))


def test_cell_fallback_grid_marker_remains_required_even_with_retained_task():
    from test_rich_terminal_desktop_acceptance import _offer as desktop_offer
    with pytest.raises(ERROR,match='CELL fallback'):
        a._require_cell_fallback_evidence('initial',desktop_offer('Data'),1,('Grid',))


def _start_rebased_fixture(selected, minimized, revision, delta):
    """A real validated replacement plane with freshly assigned retained IDs."""
    payload,source,offer,_=fixture(selected,minimized,revision)
    regions=[]
    for region in offer.retained.regions:
        draws=[]
        for draw in region.draws:
            if isinstance(draw,PaneDraw):
                draw=replace(draw,object_id=draw.object_id+delta,content_region_id=draw.content_region_id+delta)
            elif isinstance(draw,TaskBarDraw):
                draw=replace(draw,control_id=draw.control_id+delta,
                             tasks=tuple(replace(task,control_id=task.control_id+delta) for task in draw.tasks))
            else:
                draw=replace(draw,object_id=draw.object_id+delta)
            draws.append(draw)
        regions.append(replace(region,region_id=region.region_id+delta,draws=tuple(draws)))
    offer=replace(offer,retained=replace(offer.retained,regions=tuple(regions)))
    rows=[]
    for row in source.correlations:
        row=list(row);row[6]+=delta;row[7]+=delta
        if row[8]:row[8]+=delta
        rows.append(tuple(row))
    source=replace(source,correlations=tuple(rows))
    projection=a.reconstruct_retained_screen(offer,require_menu_bar=False)
    a._require_shell_source_evidence(projection,offer,11,source)
    return payload,source,offer,projection


@pytest.mark.parametrize('pending_stage',(0,1,2,3))
def test_shell_pending_refresh_rebinds_new_start_then_finishes_exact_chosen_components(pending_stage):
    probe=a.ShellAcceptanceProbe();attempts=[]
    stages=((1,0),(2,0),(1,2),(2,0),(1,0))
    def accepted(method,value,offer,generation):
        attempts.append((method,value,offer.offer_id,generation,'progress'));return 'progress'
    def blocked(method,value,offer,generation):
        attempts.append((method,value,offer.offer_id,generation,'backpressured'));return 'backpressured'
    for index in range(pending_stage):
        _,source,offer,projection=fixture(*stages[index],index+1)
        assert not probe.after_present(projection,offer,11,accepted,lambda:source)
    _,source,offer,projection=fixture(*stages[pending_stage],pending_stage+1)
    assert not probe.after_present(projection,offer,11,blocked,lambda:source)
    old_pending=probe.pending;original_panes=probe.original_panes;target=probe.target;launcher=probe.launch_target
    assert probe.stage==pending_stage and old_pending is not None
    assert not probe.after_present(projection,offer,11,blocked,lambda:pytest.fail('same ACK retries its admitted input'))
    assert attempts[-2]==attempts[-1]
    # Change the initial selection too: stage0 must retain its first component,
    # not choose a different task merely because START changed the scene.
    refreshed_state=(3,0) if pending_stage==0 else stages[pending_stage]
    _,fresh_source,fresh_offer,fresh_projection=_start_rebased_fixture(*refreshed_state,10+pending_stage,10000)
    count=len(attempts)
    assert not probe.after_present(fresh_projection,fresh_offer,11,accepted,lambda:None)
    assert probe.pending is None and probe.awaiting_source and probe.stage==pending_stage
    assert len(attempts)==count and probe.original_panes==original_panes and probe.target==target
    assert probe.launch_target==launcher
    assert not probe.after_present(fresh_projection,fresh_offer,11,accepted,lambda:fresh_source)
    assert probe.stage==pending_stage+1 and len(attempts)==count+1 and not probe.awaiting_source
    assert probe.target==target and probe.original_panes==original_panes
    if pending_stage!=1:  # Alt+m has no retained ID, but needs the fresh ACK.
        assert attempts[-1][1]!=old_pending[1]
    assert attempts[-1][2]==fresh_offer.offer_id
    assert len(probe.evidence['snapshots'])==pending_stage+1
    assert probe.evidence['snapshots'][-1]['offer_id']==fresh_offer.offer_id
    for index in range(pending_stage+1,5):
        _,source,offer,projection=_start_rebased_fixture(*stages[index],20+index,20000+index*1000)
        complete=probe.after_present(projection,offer,11,accepted,lambda:source)
        assert complete==(index==4)
    assert probe.complete and len(probe.evidence['actions'])==4
    assert [snapshot['stage'] for snapshot in probe.evidence['snapshots']]==list(range(5))
    assert probe.evidence['launcher']['component']==[1,101,11]
    json.dumps(probe.evidence)


def test_initial_pending_refresh_refuses_changed_original_pane_geometry():
    probe=a.ShellAcceptanceProbe();_,source,offer,projection=fixture()
    probe.after_present(projection,offer,11,lambda *_:'backpressured',lambda:source)
    _,fresh_source,fresh_offer,fresh_projection=_start_rebased_fixture(1,0,2,10000)
    # A source-consistent move is still not the baseline layout this probe chose.
    original=probe.original_panes.copy();component=probe.target
    outer,content=original[component]
    probe.original_panes={**original,component:(replace(outer,left=outer.left+1),content)}
    with pytest.raises(ERROR,match='initial source refresh changed'):
        probe.after_present(fresh_projection,fresh_offer,11,lambda *_:pytest.fail('changed baseline'),lambda:fresh_source)
    assert probe.stage==0 and probe.pending is None and not probe.evidence['actions']


def test_initial_pending_refresh_cannot_credit_an_already_selected_unactivated_target():
    probe=a.ShellAcceptanceProbe();_,source,offer,projection=fixture()
    probe.after_present(projection,offer,11,lambda *_:'backpressured',lambda:source)
    target=probe.target
    _,fresh_source,fresh_offer,fresh_projection=_start_rebased_fixture(2,0,2,10000)
    with pytest.raises(ERROR,match='already selected the unactivated target'):
        probe.after_present(fresh_projection,fresh_offer,11,lambda *_:pytest.fail('focus already changed'),lambda:fresh_source)
    assert probe.stage==0 and probe.target==target and probe.pending is None
    assert not probe.evidence['actions']
