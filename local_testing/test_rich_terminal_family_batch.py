"""Complete neutral family batches: exact identities, quotas, authority, callbacks."""
import re
import struct
import pytest
from test_rich_terminal_status_static import StaticHarness, MASK, RICH, SOURCE, _clean, _word

EXTRA = '\n'.join((RICH/name).read_text() for name in
                  ('stx1-roles.f','region-catalog.f','family-batch.f'))
ALL_SOURCE = SOURCE + EXTRA

def offset(name):
    m=re.search(r'\([^)]*\)\s*(?:(\d+)\s+\+)?\s*;',_word(ALL_SOURCE,name))
    return int(m[1] or 0)

class Families(StaticHarness):
    def __init__(self,backend):
        super().__init__(backend)
        self.runtime.evaluate(_clean(EXTRA).encode(),source_name='production-family-batch.f',step_budget=8_000_000)
        self.shell=self.allocate(struct.pack('<7Q',0x5254455348454C4C,56,0,self.facade,*([self.runtime.find('SF-CALLBACK').xt]*3)))
        self.cell(self.shell+16,self.shell)

    def record(self,prefix,length,fields):
        payload=bytearray(length)
        for k,v in fields.items():
            struct.pack_into('<Q',payload,offset(prefix+'.'+k),v&MASK)
        return self.allocate(payload)

    def region(self,id,y=0,h=24,z=0):
        return self.record('_RTE-IR',96,dict(ID=id,Y=y,COLS=80,ROWS=h,Z=z,FLAGS=3,
                                      **{'CLIP-Y':y,'CLIP-COLS':80,'CLIP-ROWS':h}))

    def plan(self,items,size,region):
        return self.allocate(struct.pack('<4Q',1,2,80,24)+self.read(region,88)+struct.pack('<3Q',items,size,0))

    def entry(self,kind,plan,text=0,n=0,refs=0):
        size={3:72,5:48}.get(kind,144)
        return self.allocate(struct.pack('<8Q',kind,plan,size,text,n,refs,16 if refs else 0,0))

    def finish(self,regions,entries):
        rows=self.allocate(b''.join(self.read(r,96) for r in regions)) if regions else 0
        cat=self.record('_RTE-RC',56,dict(OWNER=1,GENERATION=2,**{'SURFACE-COLS':80,'SURFACE-ROWS':24,'REGIONS-A':rows,'REGIONS-U':len(regions)*96}))
        vector=self.allocate(b''.join(self.read(e,64) for e in entries))
        batch=self.record('_RTE-FB',72,dict(ABI=1,ATTEMPT=1,**{'CATALOG-A':cat,'CATALOG-U':56,'FAMILIES-A':vector,'FAMILIES-U':len(entries)*64,'SOURCE-GENERATION':2,'SURFACE-GENERATION':3}))
        return batch,self.allocate(b'A'*544),cat,vector

    def graph(self,mixed=False):
        r1=self.region(1);r2=self.region(2,y=1,h=23,z=1)
        title=self.allocate(b'Pane')
        pane=self.record('_RTE-PANE',184,dict(OWNER=1,GENERATION=2,ID=7 if mixed else 1,KIND=1,VISIBLE=-1,REGION=1,HEIGHT=24,WIDTH=80,FOCUSED=-1,**{'ROOT-HEIGHT':24,'ROOT-WIDTH':80,'CONTENT-REGION':2,'CONTENT-ROW':1,'CONTENT-HEIGHT':23,'CONTENT-WIDTH':80,'TITLE-A':title,'TITLE-U':4}))
        pe=self.entry(6,self.plan(pane,184,r1),title,4)
        if not mixed:return (*self.finish([r1,r2],[pe]),dict(pane=pane))
        text=self.allocate(b'AppRun')
        values=[]
        for id,kind,col,w,state in [(1,10,0,80,3),(2,11,0,6,11),(3,12,10,6,3)]:
            values.append(self.record('_RTE-CONTROL',200,dict(OWNER=1,GENERATION=2,ID=id,KIND=kind,STATE=state,REGION=1,PARENT=0 if id==1 else 1,ORDER=0 if id<3 else 1,COL=col,HEIGHT=1,WIDTH=w,**{'ROOT-HEIGHT':24,'ROOT-WIDTH':80,'LABEL-A':0 if id==1 else text+(3 if id==3 else 0),'LABEL-U':0 if id==1 else 3})))
        ci=self.allocate(b''.join(self.read(x,200) for x in values));ce=self.entry(1,self.plan(ci,600,r1),text,6)
        sy=self.record('_RTE-SERIES',88,dict(OWNER=1,GENERATION=2,ID=1,CAPACITY=16000,MODE=1,**{'INTERVAL-US':125}))
        yp=self.record('_RTE-SRP',48,dict(OWNER=1,GENERATION=2,**{'SURFACE-COLS':80,'SURFACE-ROWS':24,'ITEMS-A':sy,'ITEMS-U':88}));ye=self.entry(5,yp)
        wave=self.record('_RTE-INSTRUMENT',216,dict(OWNER=1,GENERATION=2,ID=4,KIND=4,VISIBLE=-1,REGION=2,HEIGHT=4,WIDTH=20,MINIMUM=-32768,MAXIMUM=32767,**{'ROOT-HEIGHT':23,'ROOT-WIDTH':80,'SERIES-ID':1}))
        ir=self.allocate(self.read(r2,96));ip=self.record('_RTE-IP',72,dict(OWNER=1,GENERATION=2,**{'SURFACE-COLS':80,'SURFACE-ROWS':24,'REGIONS-A':ir,'REGIONS-U':96,'ITEMS-A':wave,'ITEMS-U':216}));ie=self.entry(3,ip)
        st=self.allocate(b'OK');si=self.record('_RTE-STATIC',176,dict(OWNER=1,GENERATION=2,ID=5,KIND=1,VISIBLE=-1,REGION=2,ROW=5,HEIGHT=1,WIDTH=10,**{'ROOT-HEIGHT':23,'ROOT-WIDTH':80,'VALUE-A':st,'VALUE-U':2}));se=self.entry(4,self.plan(si,176,r2),st,2)
        gt=self.allocate(b'Cell');gi=self.record('_RTE-LPI',120,dict(OBJECT=6,ROW=6,HEIGHT=1,WIDTH=10,VISIBLE=-1,**{'ROOT-HEIGHT':23,'ROOT-WIDTH':80,'TEXT-CAPACITY':4}));refs=self.allocate(struct.pack('<2Q',0,4));ge=self.entry(2,self.plan(gi,120,r2),gt,4,refs)
        return (*self.finish([r1,r2],[ce,ye,ie,se,ge,pe]),dict(pane=pane,control=ci,series=sy,wave=wave,static=si,glyph=gi,text=text,ip=ip))

@pytest.fixture(scope='module',params=('python','native'))
def families(request):return Families(request.param)

@pytest.mark.parametrize('mixed',[False,True])
def test_exact_mixed_batch_summary_and_empty_pane_region(families,mixed):
    b,o,c,v,items=families.graph(mixed)
    assert families.call('RTE-FAMILY-BATCH-VALID?',b)==(MASK,)
    assert families.call('RTE-SHELL-VALID?',families.shell)==(MASK,)
    assert families.call('_RTE-FA-AUTHORITY?',b,o,families.shell)==(MASK,)
    assert families.call('RTE-FAMILY-BATCH-PREFLIGHT',b,o,families.shell,readonly=False)==(0,)
    q=struct.unpack('<68Q',families.read(o,544))
    assert q[:6]==(1,2,80,24,1,544)
    assert q[6:15]==(0,)*9
    assert q[57:61]==(2,2,1,7 if mixed else 1)
    assert q[61:66]==(1,4,8,4,7 if mixed else 1)
    if mixed:
        assert q[15:23]==(3,6,16,3,3,0,0,6)
        assert q[28:33]==(1,1,0,0,0)
        assert q[40:47]==(1,2,8,2,5,184,1)
        assert q[48:57]==(1,1,16000,16000,0,0,0,0,1)
        assert q[66:]==(3,1|8|16|64|0x200|0x400|0x800)
    else:assert q[66:]==(0,1|0x200)

@pytest.mark.parametrize('target,key,value', [
    ('static','ID',4),('glyph','OBJECT',5),('pane','ID',6),
    ('wave','SERIES-ID',99),('series','CAPACITY',0),
    ('control','STATE',32),('static','SEVERITY',5),
])
def test_cross_family_ids_references_and_semantics_reject_before_provider(families,target,key,value):
    b,o,c,v,items=families.graph(True)
    prefixes={'static':'_RTE-STATIC','glyph':'_RTE-LPI','pane':'_RTE-PANE',
              'wave':'_RTE-INSTRUMENT','series':'_RTE-SERIES','control':'_RTE-CONTROL'}
    families.cell(items[target]+offset(prefixes[target]+'.'+key),value)
    before=families.read(o,544); calls=families.variable('SF-CALLS')
    assert families.call('RTE-FAMILY-BATCH-PREFLIGHT',b,o,families.shell)==(5,)
    assert families.read(o,544)==before and families.variable('SF-CALLS')==calls


def test_waveform_rejects_forward_history_entry(families):
    b,o,c,v,items=families.graph(True)
    entries=[families.read(v+i*64,64) for i in range(6)]
    families.write(v,b''.join([entries[0],entries[2],entries[1],*entries[3:]]))
    assert families.call('RTE-FAMILY-BATCH-VALID?',b)==(MASK,)
    assert families.call('RTE-FAMILY-BATCH-PREFLIGHT',b,o,families.shell)==(5,)


def test_duplicate_instrument_region_is_charged_once_across_entries(families):
    b,o,c,v,items=families.graph(True)
    wave=families.allocate(families.read(items['wave'],216))
    families.cell(wave+16,5)
    old_ir=struct.unpack('<Q',families.read(items['ip']+32,8))[0]
    ir=families.allocate(families.read(old_ir,96))
    ip=families.allocate(families.read(items['ip'],72));families.cell(ip+32,ir);families.cell(ip+48,wave)
    ie=families.entry(3,ip)
    for name,key,new in [('static','ID',6),('glyph','OBJECT',7),('pane','ID',8)]:
        prefix={'static':'_RTE-STATIC','glyph':'_RTE-LPI','pane':'_RTE-PANE'}[name]
        families.cell(items[name]+offset(prefix+'.'+key),new)
    entries=[families.read(v+i*64,64) for i in range(6)]
    vector=families.allocate(b''.join([*entries[:3],families.read(ie,64),*entries[3:]]))
    families.cell(b+24,vector);families.cell(b+32,7*64)
    assert families.call('RTE-FAMILY-BATCH-PREFLIGHT',b,o,families.shell,readonly=False)==(0,)
    q=struct.unpack('<68Q',families.read(o,544))
    assert q[28:30]==(1,2) and q[56]==2 and q[57]==2 and q[60]==8


@pytest.mark.parametrize('gap',[0,1])
def test_controls_remain_contiguous_across_region_plans(families,gap):
    b,o,c,v,items=families.graph(True)
    root=families.allocate(families.read(items['control'],200))
    families.cell(root+16,4+gap);families.cell(root+48,2);families.cell(root+104,23)
    old_ir=struct.unpack('<Q',families.read(items['ip']+32,8))[0]
    ce=families.entry(1,families.plan(root,200,old_ir))
    for name,key,new in [('wave','ID',5+gap),('static','ID',6+gap),('glyph','OBJECT',7+gap),('pane','ID',8+gap)]:
        prefix={'wave':'_RTE-INSTRUMENT','static':'_RTE-STATIC','glyph':'_RTE-LPI','pane':'_RTE-PANE'}[name]
        families.cell(items[name]+offset(prefix+'.'+key),new)
    entries=[families.read(v+i*64,64) for i in range(6)]
    vector=families.allocate(entries[0]+families.read(ce,64)+b''.join(entries[1:]))
    families.cell(b+24,vector);families.cell(b+32,7*64)
    assert families.call('RTE-FAMILY-BATCH-PREFLIGHT',b,o,families.shell,readonly=False)==((5 if gap else 0),)
    if not gap:
        q=struct.unpack('<68Q',families.read(o,544))
        assert q[15]==4 and q[19]==4 and q[66]==4


@pytest.mark.parametrize('result',[1,2,3,4,5,6,7,999])
def test_provider_refusal_keeps_output_unchanged(families,result):
    b,o,c,v,items=families.graph(True)
    before=families.read(o,544);calls=families.variable('SF-CALLS')
    families.variable('SF-STATUS',result)
    try:
        expected=result if result<=7 else 5
        assert families.call('RTE-FAMILY-BATCH-PREFLIGHT',b,o,families.shell)==(expected,)
        assert families.read(o,544)==before and families.variable('SF-CALLS')==calls+1
    finally:families.variable('SF-STATUS',0)


@pytest.mark.parametrize('output', ['batch','catalog','families','control','text','shell','facade',
                                     '_RTE-FA-SUMMARY','_RTE-RC-BATCH','_RTE-HPV-SUMMARY','_FDC1-A'])
def test_output_authority_rejected_before_writes(families,output):
    b,o,c,v,items=families.graph(True)
    spans={'batch':b,'catalog':c,'families':v,'shell':families.shell,'facade':families.facade,**items}
    address=spans[output] if output in spans else (families.call(output)[0] if output == '_RTE-FA-SUMMARY' else families.runtime.find(output).body_address)
    before=families.read(address,544);calls=families.variable('SF-CALLS')
    assert families.call('RTE-FAMILY-BATCH-PREFLIGHT',b,address,families.shell)==(5,)
    assert families.read(address,544)==before and families.variable('SF-CALLS')==calls


@pytest.mark.parametrize('source',['_RTE-FA-BATCH','_RTE-FA-SUMMARY','_RTE-RC-BATCH','_RTE-HPV-SUMMARY','_FDC1-A'])
def test_source_authority_rejected_before_scratch_stores(families,source):
    b,o,c,v,items=families.graph(True)
    address=(families.call(source)[0] if source == '_RTE-FA-SUMMARY' else families.runtime.find(source).body_address)
    before=families.read(address,200);calls=families.variable('SF-CALLS')
    families.cell(v+24,address)  # control display bank has six bytes
    assert families.call('RTE-FAMILY-BATCH-PREFLIGHT',b,o,families.shell)==(5,)
    assert families.read(address,200)==before and families.variable('SF-CALLS')==calls


def test_pane_shell_leaf_dispatch_and_empty_title(families):
    b,o,c,v,items=families.graph(False)
    p=items['pane']
    calls=families.variable('SF-CALLS')
    assert families.call('RTE-PANE-DEFINE',p,families.shell)==(0,)
    assert families.call('RTE-PANE-REPLACE',p,families.shell)==(0,)
    families.cell(p+160,0);families.cell(p+168,0)
    assert families.call('RTE-PANE-DEFINE',p,families.shell)==(0,)
    assert families.variable('SF-CALLS')==calls+3

@pytest.mark.parametrize('count,chunk',[(0,0),(1,1),(5,2),(16000,4096)])
def test_history_only_empty_catalog_and_exact_chunk_reservations(families,count,chunk):
    samples=families.allocate(struct.pack('<'+'q'*count,*([0]*count))) if count else 0
    history=families.record('_RTE-SERIES',88,dict(OWNER=1,GENERATION=2,ID=9,CAPACITY=16000,MODE=1,
                  **{'INTERVAL-US':125,'SAMPLES-A':samples,'SAMPLES-U':count*8,'CHUNK-SAMPLES':chunk}))
    plan=families.record('_RTE-SRP',48,dict(OWNER=1,GENERATION=2,
                  **{'SURFACE-COLS':80,'SURFACE-ROWS':24,'ITEMS-A':history,'ITEMS-U':88}))
    e=families.entry(5,plan,samples,count*8)
    b,o,c,v=families.finish([], [e])
    assert families.call('RTE-FAMILY-BATCH-PREFLIGHT',b,o,families.shell,readonly=False)==(0,)
    q=struct.unpack('<68Q',families.read(o,544))
    assert q[48:57]==(1,9,16000,16000,count*8,(count+chunk-1)//chunk if count else 0,chunk,min(count,chunk)*8,0)
    assert q[57:67]==(0,)*10
    assert q[67]==1|8|16


def test_provider_throw_scrubs_temporary_borrows_and_preserves_output(families):
    b,o,c,v,items=families.graph(True)
    families.runtime.evaluate(b': FAMILY-THROW 2DROP -999 THROW ;')
    callback=families.runtime.memory.read64(families.shell+32)
    before=families.read(o,544)
    families.cell(families.shell+32,families.runtime.find('FAMILY-THROW').xt)
    try:
        assert families.call('RTE-FAMILY-BATCH-PREFLIGHT',b,o,families.shell)==(5,)
        assert families.read(o,544)==before
        assert families.variable('_RTE-FA-BATCH')==0
        assert families.variable('_RTE-FA-ENTRY')==0
        assert families.read(families.call('_RTE-FA-SUMMARY')[0],544)==bytes(544)
    finally:families.cell(families.shell+32,callback)
