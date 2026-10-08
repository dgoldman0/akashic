"""Execute real FIELD lowering, owned target packing and revision-bound input.

Only the outer producer-validity hook is scripted for point-target tests;
packing, bank/header authority, owner/generation checks and input lookup are
production words. Independent byte fixtures encode the canonical native ABI.
"""
import struct

import pytest

from test_rich_status_producer import StatusHarness
from test_rich_glyph_growth import MASK64


def model(*, kind=1, revision=17, label=b"Rate", text=b"value", state=3,
          flags=0, value=7, minimum=-20, maximum=30, step=4,
          choices=((-10, b"same"), (900, b"same"), (7, b"third"))):
    padded = lambda data: data + bytes((-len(data)) % 8)
    body = padded(label)
    if kind == 2:
        body += b"".join(struct.pack("<3Q", 24 + ((len(t)+7)&-8), n & MASK64, len(t))
                         + padded(t) for n, t in choices)
        minimum = maximum = step = 0
    elif kind == 3:
        body += padded(text)
        value = minimum = maximum = step = 0
    if not label:
        label_slot = (0, 0, 0, 0)
    else:
        label_slot = (0, 1, 1, 4)
    cells = (192 + len(body), 1, 23, kind, revision, 20, 3, state, flags,
             *label_slot, 1, 7, 1, 8, value, minimum, maximum, step,
             len(label), len(text) if kind == 3 else 0, len(choices) if kind == 2 else 0)
    return struct.pack("<24Q", *(n & MASK64 for n in cells)) + body


class FieldHarness(StatusHarness):
    def __init__(self, backend):
        super().__init__(backend, overrides={"RTHP-VALID?": ": RTHP-VALID? DROP -1 ;"},
                         extra_words=("RTHP-STORAGE-BYTES", "_RTHP-BUILD-FIELDS",
                                      "_RTHP-W-BUILD-OPTIONAL-FIELDS", "_RTHP-STRIP-FIELDS?",
                                      "_RTHP-COPY-FIELD-SOURCE?", "_RTHP-FIELDS-FIXED?",
                                      "_RTHP-TG-FIELD-TARGETS?", "RTHP-CONTROL-TARGET@",
                                      "_RTHP-FIELD-LATER-CLAIMS?", "_RTHP-D-CONTROL-COMPATIBLE?",
                                      "_RTHP-U-CLONE?", "_RTHP-TARGET-BANK-ENTRIES?",
                                      "RTE-CONTROL-PLAN-VALID?", "_RTHP-W-TOTAL"))

    def setup(self, *, field_native=1024, row=3, col=2, clip=None, **kwargs):
        self.producer = self.allocate(bytes(self.constant("RTHP-SIZE")))
        size, = self.results("RTHP-STORAGE-BYTES", 1, 1, 64, 256, 256, 512,
                             field_native, 32, 8)
        assert size
        self.arena_size = size
        self.arena = self.allocate(b"LEFTGUAR" + bytes(size) + b"RIGHTGUA") + 8
        for name, n in {"ARENA-A": self.arena, "ARENA-U": size, "MAX-DOCUMENTS": 1,
                        "MAX-RECORDS": 1, "MAX-TEXT": 64, "MAX-COLLECTION-NATIVE": 256,
                        "MAX-COLLECTION-DESCRIPTORS": 8, "MAX-COLLECTIONS": 4,
                        "MAX-CONTROLS": 5 + field_native//192, "MAX-DGRAPH-NATIVE": 256,
                        "MAX-DGRAPH-DESCRIPTORS": 1, "MAX-INSTRUMENT-REGIONS": 1,
                        "MAX-INSTRUMENTS": 2, "MAX-STATUS-NATIVE": 512, "MAX-STATICS": 7,
                        "MAX-FIELD-NATIVE": field_native, "MAX-FIELDS": field_native//192,
                        "MAX-COLS": 32, "MAX-ROWS": 8, "COLS": 32, "ROWS": 8,
                        "OWNER": 1, "OWNER-GEN": 2, "REGION": 7, "FIRST-OBJECT": 100,
                        "SOURCE-GEN": 9, "SOURCE-CONTENT-EPOCH": 29, "SOURCE-DRAW": 12,
                        "SURFACE-GEN": 12, "PHYSICAL-GEN": 1, "DOCUMENT-COUNT": 1}.items():
            self.field(self.producer, "_RTHP." + name, n)
        self.results("_RTHP-LAYOUT", self.producer)
        self.variable("_RTHP-W-P", self.producer)
        self.variable("_RTHP-W-DOCUMENTS", 1)
        self.dir = self.get("SOURCE-DIR-A")
        self.field(self.producer, "_RTHP.SOURCE-DIR-USED", self.constant("RUHA-DOCUMENT-SIZE"))
        self.runtime.memory.write_bytes(self.dir, struct.pack("<6Q", 11, 5, 0, 0, 8, 32))
        self.model = model(**kwargs)
        cr, cc, ch, cw = clip or (row, col, 3, 20)
        utf8 = len(kwargs.get("label", b"Rate"))
        if kwargs.get("kind", 1) == 3:
            utf8 += len(kwargs.get("text", b"value"))
        elif kwargs.get("kind", 1) == 2:
            utf8 += sum(len(t) for n, t in kwargs.get("choices", ((-10,b"same"),(900,b"same"),(7,b"third"))))
        self.descriptor = struct.pack("<16Q", 1, 4, 6, 99, 0, row, col, 3, 20,
                                      cr, cc, ch, cw, 3, len(self.model), utf8)
        self.runtime.memory.write_bytes(self.get("FIELD-NATIVE-A"), self.model)
        self.runtime.memory.write_bytes(self.get("FIELD-DESCRIPTORS-A"), self.descriptor)
        self.field(self.producer, "_RTHP.FIELD-DESCRIPTORS-USED", 128)
        self.field(self.producer, "_RTHP.FIELD-NATIVE-USED", len(self.model))
        for offset, n in ((192,0),(200,128),(208,0),(216,len(self.model))):
            self.runtime.memory.write64(self.dir+offset,n)

    def build(self):
        return self.results("_RTHP-BUILD-FIELDS", self.producer)

    def fixed(self):
        self.field(self.producer, "_RTHP.BASE-CLAIMS-USED", self.get("CLAIMS-USED"))
        return self.call("_RTHP-FIELDS-FIXED?", self.producer)

    def content(self):
        c = self.get("CONTROLS-A")
        a = self.runtime.memory.read64(c + self.offset("_RTE-CONTROL.CONTENT-A"))
        u = self.runtime.memory.read64(c + self.offset("_RTE-CONTROL.CONTENT-U"))
        return self.runtime.memory.read_bytes(a, u)

    def pack(self, index=0):
        bank = self.get(f"TARGET{index}-A")
        for name,n in {"COLS":32,"ROWS":8,"DOCUMENT-COUNT":1,"OWNER":1,"GENERATION":2,
                       "REGION":7,"FIRST-OBJECT":self.get("FIRST-OBJECT"), "DRAW":12,
                       "SOURCE-GEN":9,"PHYSICAL-GEN":1,"CONTENT-EPOCH":29,"GLYPH-RUN-LIMIT":256,
                       "CONTROL-COUNT":self.get("CONTROL-COUNT"),
                       "SOURCE-TEXT-USED":self.get("SOURCE-TEXT-USED"),
                       "FIELD-COUNT":self.get("FIELD-COUNT"),"FIELD-ITEMS":self.get("FIELD-ITEMS"),
                       "FIELD-UTF8":self.get("FIELD-UTF8")}.items():
            self.field(bank,"_RTHP-TB."+name,n)
        self.variable("_RTHP-TG-P",self.producer)
        self.variable("_RTHP-TG-BANK",bank)
        self.variable("_RTHP-TG-COUNT",0)
        self.variable("_RTHP-CT-P",self.producer)
        assert self.call("_RTHP-TG-FIELD-TARGETS?")
        self.field(bank,"_RTHP-TB.COUNT",self.variable("_RTHP-TG-COUNT"))
        assert self.call("_RTHP-PACK-ADMITTED-CANDIDATE",bank,self.producer)
        assert self.call("_RTHP-PACKED-BANK?",bank,self.producer)
        assert self.call("_RTHP-TARGET-BANK-HEADER?",bank,self.producer)
        assert self.call("_RTHP-TARGET-BANK-ENTRIES?")
        self.guards()
        return bank

    def activate(self, bank):
        self.field(self.producer,"_RTHP.TARGET-ACTIVE",bank)
        self.field(self.producer,"_RTHP.ACTIVE-DRAW",12)


@pytest.fixture(params=("python","native"))
def h(request):
    return FieldHarness(request.param)


@pytest.mark.parametrize("kind",(1,2,3))
def test_real_field_retains_authored_slots_revision_and_choice_accounting(h,kind):
    h.setup(kind=kind)
    assert h.build() == (0,)
    assert h.fixed()
    wire=h.content()
    header=struct.unpack("<IHHQIIiiIIiiIIqqqqII",wire[:96])
    assert header[:6] == (0x31434446,1,kind,17,0,0)
    assert header[6:14] == (1,0,4,1,7,1,8,1)
    assert h.get("CONTROL-COUNT") == h.get("FIELD-COUNT") == 1
    assert h.get("FIELD-ITEMS") == (3 if kind==2 else 0)
    assert h.get("FIELD-UTF8") == (17 if kind==2 else 9 if kind==3 else 4)
    assert h.get("CLAIMS-USED") == 80
    assert h.variable("_RTHP-W-GLYPH-FIRST") == 101
    h.guards()


@pytest.mark.parametrize("kind,intent,expected",((1,1,True),(1,11,True),(2,11,True),(3,1,True),(3,11,False)))
def test_input_uses_value_slot_and_independent_acknowledged_revision(h,kind,intent,expected):
    h.setup(kind=kind,revision=(1<<63)+9)
    assert h.build() == (0,)
    bank=h.pack();h.activate(bank)
    result=h.results("RTHP-CONTROL-TARGET@",1,2,100,intent,h.producer)
    assert result == ((4,9,(1<<63)+9,MASK64) if expected else (0,0,0,0))
    assert h.results("RTHP-CONTROL-TARGET@",1,3,100,intent,h.producer) == (0,0,0,0)


@pytest.mark.parametrize("kwargs",({"flags":1},{"state":1}))
def test_readonly_or_disabled_fields_display_without_return_targets(h,kwargs):
    h.setup(**kwargs);assert h.build() == (0,);assert h.fixed()
    bank=h.pack();h.activate(bank)
    assert h.results("RTHP-CONTROL-TARGET@",1,2,100,1,h.producer) == (0,0,0,0)
    assert h.get("FIELD-COUNT") == 1


@pytest.mark.parametrize("kwargs",({"state":0},{"clip":(3,2,2,20)},{"row":7},{"col":20}))
def test_hidden_clipped_or_outside_fields_leave_no_claims_or_ids(h,kwargs):
    h.setup(**kwargs);assert h.build() == (0,)
    assert h.get("FIELD-COUNT") == h.get("CONTROL-COUNT") == h.get("SOURCE-TEXT-USED") == h.get("CLAIMS-USED") == 0
    assert h.variable("_RTHP-W-GLYPH-FIRST") == 100


def test_invalid_native_field_is_invalid_not_optional_refusal(h):
    h.setup();h.runtime.memory.write64(h.get("FIELD-NATIVE-A")+32,0)
    assert h.results("_RTHP-W-BUILD-OPTIONAL-FIELDS") == (h.constant("RTE-S-INVALID"),)
    assert h.get("CLAIMS-USED") == h.get("FIELD-COUNT") == 0


def test_field_storage_admits_no_field_bank_and_rejects_a_partial_record(h):
    assert h.results("RTHP-STORAGE-BYTES",1,1,64,256,256,512,0,32,8)[0] > 0
    assert h.results("RTHP-STORAGE-BYTES",1,1,64,256,256,512,193,32,8)==(0,)


@pytest.mark.parametrize("feature,short", ((False,False),(True,False),(True,True)))
def test_field_source_copy_omits_unsupported_or_unaffordable_lane(h,feature,short):
    h.setup()
    snapshot=h.allocate(bytes(h.constant("RUHA-SNAPSHOT-SIZE")))
    descriptors=h.allocate(h.descriptor);native=h.allocate(h.model)
    directory=h.allocate(h.runtime.memory.read_bytes(h.dir,h.constant("RUHA-DOCUMENT-SIZE")))
    for offset,value in ((176,descriptors),(184,128),(192,native),(200,len(h.model))):
        h.runtime.memory.write64(snapshot+offset,value)
    h.variable("_RTHP-W-SNAP",snapshot);h.variable("_RTHP-W-DIRECTORY-A",directory)
    h.field(h.producer+h.offset("_RTHP.LIMITS"),"_RTE-L.FEATURES",0x1000 if feature else 0)
    if short:h.field(h.producer,"_RTHP.FIELD-NATIVE-U",len(h.model)-8)
    h.runtime.memory.write_bytes(h.get("FIELD-NATIVE-A"),bytes(len(h.model)))
    assert h.call("_RTHP-COPY-FIELD-SOURCE?")
    copied=feature and not short
    assert h.get("FIELD-DESCRIPTORS-USED")==128*copied
    assert h.get("FIELD-NATIVE-USED")==len(h.model)*copied
    assert h.runtime.memory.read_bytes(h.get("FIELD-NATIVE-A"),len(h.model)) == (h.model if copied else bytes(len(h.model)))
    assert h.build()==(0,)
    assert h.get("FIELD-COUNT")==int(copied)
    h.guards()


def test_invalid_source_extent_remains_invalid_without_field_capability(h):
    h.setup()
    snapshot=h.allocate(bytes(h.constant("RUHA-SNAPSHOT-SIZE")))
    descriptors=h.allocate(h.descriptor);native=h.allocate(h.model)
    directory=h.allocate(h.runtime.memory.read_bytes(h.dir,h.constant("RUHA-DOCUMENT-SIZE")))
    for offset,value in ((176,descriptors),(184,128),(192,native),(200,len(h.model))):
        h.runtime.memory.write64(snapshot+offset,value)
    h.runtime.memory.write64(directory+216,len(h.model)+8)
    h.variable("_RTHP-W-SNAP",snapshot);h.variable("_RTHP-W-DIRECTORY-A",directory)
    assert not h.call("_RTHP-COPY-FIELD-SOURCE?")
    assert h.get("FIELD-NATIVE-USED")==0
    h.guards()


def test_field_empty_label_is_canonical_and_selected_state_maps_to_control(h):
    h.setup(label=b"",state=7);assert h.build()==(0,);assert h.fixed()
    control=h.get("CONTROLS-A")
    assert h.runtime.memory.read64(control+32)==11
    assert h.runtime.memory.read64(control+120)==h.runtime.memory.read64(control+128)==0
    h.runtime.memory.write64(control+120,h.get("SOURCE-TEXT-A"))
    assert not h.fixed()


@pytest.mark.parametrize("mutation",("claim","id","text","revision","count","slot"))
def test_fixed_field_audit_rejects_corrupted_candidate(h,mutation):
    h.setup();assert h.build()==(0,);assert h.fixed()
    c=h.get("CONTROLS-A");a=h.runtime.memory.read64(c+152)
    if mutation=="claim":h.runtime.memory.write64(h.get("CLAIMS-A")+56,3)
    elif mutation=="id":h.runtime.memory.write64(c+16,101)
    elif mutation=="text":h.runtime.memory.write64(c+152,h.get("SOURCE-TEXT-A"))
    elif mutation=="revision":h.runtime.memory.write64(a+8,0)
    elif mutation=="count":h.field(h.producer,"_RTHP.FIELD-ITEMS",1)
    else:h.runtime.memory.write_bytes(a+40,struct.pack("<i",30))
    assert not h.fixed()


def test_local_field_capacity_rolls_back_only_owned_suffix(h):
    h.setup()
    prefix=struct.pack("<10Q",11,9,1,4,23,3,0,0,1,1)
    h.runtime.memory.write_bytes(h.get("CLAIMS-A"),prefix)
    h.field(h.producer,"_RTHP.CLAIMS-USED",80)
    h.field(h.producer,"_RTHP.SOURCE-TEXT-U",4)
    assert h.results("_RTHP-W-BUILD-OPTIONAL-FIELDS")== (0,)
    assert h.get("FIELD-COUNT")==h.get("CONTROL-COUNT")==h.get("SOURCE-TEXT-USED")==0
    assert h.get("CLAIMS-USED")==80
    assert h.runtime.memory.read_bytes(h.get("CLAIMS-A"),80)==prefix
    assert h.get("FIELD-REFUSED")==MASK64
    h.guards()


def test_overlapping_fields_strip_the_entire_optional_lane(h):
    h.setup()
    descriptor=bytearray(h.descriptor)
    struct.pack_into("<Q",descriptor,8,5);struct.pack_into("<Q",descriptor,32,len(h.model))
    h.runtime.memory.write_bytes(h.get("FIELD-DESCRIPTORS-A")+128,descriptor)
    h.runtime.memory.write_bytes(h.get("FIELD-NATIVE-A")+len(h.model),h.model)
    h.runtime.memory.write64(h.dir+200,256);h.runtime.memory.write64(h.dir+216,2*len(h.model))
    h.field(h.producer,"_RTHP.FIELD-DESCRIPTORS-USED",256)
    h.field(h.producer,"_RTHP.FIELD-NATIVE-USED",2*len(h.model))
    assert h.results("_RTHP-W-BUILD-OPTIONAL-FIELDS")== (0,)
    assert h.get("FIELD-COUNT")==h.get("CONTROL-COUNT")==h.get("SOURCE-TEXT-USED")==h.get("CLAIMS-USED")==0
    assert h.variable("_RTHP-W-GLYPH-FIRST")==100
    h.guards()


def test_field_overlap_with_other_semantic_family_refuses_rich(h):
    h.setup()
    prefix=struct.pack("<10Q",11,9,1,4,23,3,3,2,4,22)
    h.runtime.memory.write_bytes(h.get("CLAIMS-A"),prefix)
    h.field(h.producer,"_RTHP.CLAIMS-USED",80)
    assert h.results("_RTHP-W-BUILD-OPTIONAL-FIELDS")== (h.constant("RTE-S-UNAVAILABLE"),)
    assert h.get("FIELD-COUNT")==0
    assert h.get("CLAIMS-USED")==80
    assert h.runtime.memory.read_bytes(h.get("CLAIMS-A"),80)==prefix


def test_packed_field_owns_label_content_and_target_revision(h):
    h.setup(kind=2);assert h.build()==(0,)
    bank=h.pack();h.activate(bank)
    size,flag=h.results("_RTHP-TARGET-BANK-BYTES?",h.producer)
    assert flag
    before=h.runtime.memory.read_bytes(bank,size)
    h.runtime.memory.write_bytes(h.get("SOURCE-TEXT-A"),bytes(h.get("SOURCE-TEXT-USED")))
    h.runtime.memory.write_bytes(h.get("FIELD-NATIVE-A"),bytes(len(h.model)))
    assert h.runtime.memory.read_bytes(bank,size)==before
    assert h.results("RTHP-CONTROL-TARGET@",1,2,100,11,h.producer)==(4,9,17,MASK64)


@pytest.mark.parametrize("mutation",(None,"revision","value","selected","disabled","label","slot"))
def test_only_field_selection_can_change_in_content_preserving_delta(h,mutation):
    h.setup();assert h.build()==(0,)
    active=h.pack()
    assert h.call("_RTHP-STRIP-FIELDS?",h.producer)
    h.field(h.producer,"_RTHP.FIRST-OBJECT",200)
    assert h.build()==(0,)
    c=h.get("CONTROLS-A");a=h.runtime.memory.read64(c+152)
    if mutation=="revision":h.runtime.memory.write64(a+8,18)
    elif mutation=="value":h.runtime.memory.write64(a+56,8)
    elif mutation=="selected":h.runtime.memory.write64(c+32,11)
    elif mutation=="disabled":h.runtime.memory.write64(c+32,1)
    elif mutation=="label":h.runtime.memory.write_bytes(h.runtime.memory.read64(c+120),b"Pace")
    elif mutation=="slot":h.runtime.memory.write_bytes(a+40,struct.pack("<i",8))
    pending=h.pack(index=1)
    for name,value in (("P",h.producer),("ACTIVE",active),("PENDING",pending),("PENDING-FIRST",200)):
        h.variable("_RTHP-D-"+name,value)
    h.runtime.memory.write64(h.get("ORDER2-A"),1)
    assert h.call("_RTHP-D-CONTROL-COMPATIBLE?",0)==(mutation in (None,"selected"))
    assert h.variable("_RTHP-D-OPS")==int(mutation=="selected")
    h.guards()


def test_unchanged_field_clone_rebases_owned_spans_and_preserves_revision(h):
    h.setup(kind=3);assert h.build()==(0,)
    active=h.pack();h.activate(active)
    for name,value in (("P",h.producer),("ACTIVE",active),("DRAW",13),("SOURCE-GEN",10),("CONTENT-EPOCH",29)):
        h.variable("_RTHP-U-"+name,value)
    assert h.call("_RTHP-U-CLONE?")
    pending=h.variable("_RTHP-U-PENDING")
    assert pending!=active
    # Clone is deliberately unauthoritative until its revision fence commits.
    assert not h.call("_RTHP-PACKED-BANK?",pending,h.producer)
    old,=h.results("_RTHP-D-CONTROL-AT",0,active)
    new,=h.results("_RTHP-D-CONTROL-AT",0,pending)
    for offset in (120,152):
        before=h.runtime.memory.read64(old+offset);after=h.runtime.memory.read64(new+offset)
        size=h.runtime.memory.read64(old+offset+8)
        assert before!=after
        assert h.runtime.memory.read_bytes(before,size)==h.runtime.memory.read_bytes(after,size)
    entry=pending+h.constant("_RTHP-TARGET-BANK-HEADER-SIZE")
    assert h.runtime.memory.read64(entry+32)==17
    assert h.runtime.memory.read64(entry+40)==1<<1
    h.guards()


def test_distinct_mounted_roots_preserve_claim_identity_with_same_native_key(h):
    h.setup(row=0)
    descriptor=bytearray(h.descriptor)
    struct.pack_into("<Q",descriptor,8,5);struct.pack_into("<Q",descriptor,24,100)
    struct.pack_into("<Q",descriptor,32,len(h.model))
    for offset in (40,72):struct.pack_into("<Q",descriptor,offset,4)
    h.runtime.memory.write_bytes(h.get("FIELD-DESCRIPTORS-A")+128,descriptor)
    h.runtime.memory.write_bytes(h.get("FIELD-NATIVE-A")+len(h.model),h.model)
    h.runtime.memory.write64(h.dir+200,256);h.runtime.memory.write64(h.dir+216,2*len(h.model))
    h.field(h.producer,"_RTHP.FIELD-DESCRIPTORS-USED",256)
    h.field(h.producer,"_RTHP.FIELD-NATIVE-USED",2*len(h.model))
    assert h.build()==(0,);assert h.fixed()
    assert h.get("FIELD-COUNT")==2
    claims=h.get("CLAIMS-A");correlations=h.get("CORR-A")
    assert (h.runtime.memory.read64(claims+32),h.runtime.memory.read64(claims+80+32))==(99,100)
    assert (h.runtime.memory.read64(correlations+48),h.runtime.memory.read64(correlations+56+48))==(23,23)
    h.runtime.memory.write64(claims+32,23)
    assert not h.fixed()


@pytest.mark.parametrize("overlap",(False,True))
def test_field_overlap_with_later_instrument_claim_is_not_optional(h,overlap):
    h.setup();assert h.build()==(0,)
    row=3 if overlap else 0
    h.runtime.memory.write_bytes(h.get("CLAIMS-A")+80,struct.pack("<10Q",11,9,1,8,92,4,row,2,row+1,22))
    h.field(h.producer,"_RTHP.CLAIMS-USED",160)
    assert h.call("_RTHP-FIELD-LATER-CLAIMS?",h.producer)==(not overlap)


def test_full_producer_dependency_closure_compiles_in_native_runtime():
    from test_field_model import field_runtime
    runtime=field_runtime(("tui/rich-terminal/hybrid-screen-producer.f",))
    runtime.evaluate(b"RTHP-SIZE _RTHP-TARGET-BANK-HEADER-SIZE _RTHP-TARGET-ENTRY-SIZE",source_name="field-producer-abi")
    assert runtime.main_context.data.snapshot()==(4528,336,48)
    assert runtime.main_context.returns.snapshot()==()


@pytest.mark.parametrize("prefix", (0, 1))
def test_field_suffix_updates_authoritative_plan_extent_and_strip_restores_prefix(h, prefix):
    h.setup()
    if prefix:
        c = h.get("CONTROLS-A")
        for name, value in {"OWNER": 1, "GENERATION": 2, "ID": 100, "KIND": 1,
                            "STATE": 3, "REGION": 7, "HEIGHT": 1, "WIDTH": 32,
                            "ROOT-HEIGHT": 8, "ROOT-WIDTH": 32}.items():
            h.field(c, "_RTE-CONTROL." + name, value)
        h.field(h.producer, "_RTHP.CONTROL-COUNT", prefix)
    h.variable("_RTHP-W-TOTAL", prefix)
    assert h.build() == (0,)
    plan = h.producer + h.offset("_RTHP.CONTROL-PLAN")
    assert h.runtime.memory.read64(plan + h.offset("_RTE-CP.ITEMS-U")) == (prefix + 1) * 200
    assert h.call("RTE-CONTROL-PLAN-VALID?", plan)
    assert h.call("_RTHP-STRIP-FIELDS?", h.producer)
    assert h.runtime.memory.read64(plan + h.offset("_RTE-CP.ITEMS-U")) == prefix * 200
    if prefix:
        assert h.call("RTE-CONTROL-PLAN-VALID?", plan)
    else:
        assert h.runtime.memory.read_bytes(plan, h.constant("RTE-CONTROL-PLAN-SIZE")) == bytes(144)
