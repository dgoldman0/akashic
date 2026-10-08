"""Real draw-plane acceptance evidence for canonical shell geometry and input.

These fixtures use the paired renderer's validated draw values. Pane titles
and task labels remain metadata; opaque pixels, source text and input authority
are separate assertions. No guest producer state is fabricated as provenance.
"""
from dataclasses import replace

import pytest
import akashic_tui  # noqa: F401 -- selects the paired MegaPad tree
import rich_terminal_desktop_acceptance as acceptance
from rich_terminal.appearance import FLOWING_APPEARANCE, REFERENCE_APPEARANCE
from rich_terminal.pygame_view import (
    ControlIdentity, ControlHitTarget, ControlSurface, PixelRect, RegionOcclusion,
    composite_draw_plane_result,
)
from rich_terminal.retained_scene import ControlKind, ControlState, ObjectBounds, RGBA
from rich_terminal.retained_view import (
    DisplayScope, GlyphRunDraw, PaneDraw, ReadoutDraw, RetainedDrawPlane,
    RetainedRegionDraw, TabDraw, TabSetDraw, TaskBarDraw, TaskDraw,
    retained_draw_order,
)
from shared.session import TerminalCell, TerminalDisplayOffer, TerminalSnapshot

COLS, ROWS = 12, 8
ACTIVE = ControlState.VISIBLE | ControlState.ENABLED
RECT = acceptance._LogicalRectangle
ERROR = acceptance.PhysicalDesktopAcceptanceError
WHITE, BLACK = RGBA(255,255,255,255), RGBA(0,0,0,255)


def _region(id, draws=(), *, z=0, clip=None, logical=(0,0,COLS,ROWS), owner=7):
    return RetainedRegionDraw(owner,9,id,*logical,*(clip or (0,0,0,0)),z,
                              clip is not None,retained_draw_order(tuple(draws)))


def _glyph(id,x,y,text):
    return GlyphRunDraw(id,0,ObjectBounds(x,y,len(text),1),WHITE,BLACK,0,text)


def _bar(*, enabled=True, child_enabled=True, selected=True, minimized=False,
         label=acceptance.PAD_FOCUS_MARKER, kind=ControlKind.TASK, row=7):
    task_state=ControlState.VISIBLE | (ControlState.ENABLED if child_enabled else 0)
    if selected:task_state |= ControlState.SELECTED
    if minimized:task_state |= ControlState.MINIMIZED
    tasks=(TaskDraw(501,kind,task_state,0,ObjectBounds(0,0,3,1),label),
           TaskDraw(502,ControlKind.LAUNCHER,ACTIVE,1,ObjectBounds(5,0,3,1),'Apps'))
    return TaskBarDraw(500,ACTIVE if enabled else ControlState.VISIBLE,0,0,
                       ObjectBounds(0,row,COLS,1),tasks)


def _offer(regions, *, cols=COLS,rows=ROWS):
    # Occupied CELL data cannot be credited as retained coverage or markers.
    cells=tuple(tuple(TerminalCell('X',(255,0,0),(0,0,255),0)
                      for _ in range(cols)) for _ in range(rows))
    snapshot=TerminalSnapshot(cols,rows,cells,0,0,True,True)
    scope=DisplayScope(1,1,0,1,0,1,1)
    plane=RetainedDrawPlane(True,True,tuple(sorted(regions,key=lambda r:(r.z_order,r.owner_id,r.region_id))))
    return TerminalDisplayOffer(1,scope,snapshot,plane)


def _scene(*, instruments=False,tabs=False,zero_chrome=False,
           title='TITLE ONLY',bar=None,late_bar=False,missing=False):
    bar=_bar() if bar is None else bar
    panes=[];contents=[];extra=[]
    slots=((0,6),(6,6)) if not zero_chrome else ((0,12),)
    for index,(left,width) in enumerate(slots):
        inset=0 if zero_chrome else 1
        content=ObjectBounds(inset,inset,width-2*inset,7-2*inset)
        x,y,w,h=left+inset,inset,content.cell_cols,content.cell_rows
        panes.append(PaneDraw(100+index,0,ObjectBounds(left,0,width,7),3+index,
                              content,title,index==0))
        draws=[]
        for row in range(y,y+h):
            if instruments and row==2:continue
            if tabs and row==1:continue
            if missing and index==0 and row==y:continue
            draws.append(_glyph(1000+index*100+row,x,row,chr(65+index)*w))
        if tabs:
            draws.append(TabSetDraw(200+index*10,ACTIVE,0,1,ObjectBounds(x,1,w,1),
                         (TabDraw(201+index*10,ACTIVE|ControlState.SELECTED,0,'Keep',''),)))
        contents.append(_region(3+index,draws,z=3,clip=(x,y,w,h)))
        if instruments:
            readout=ReadoutDraw(800+index,0,ObjectBounds(0,0,w,1),WHITE,BLACK,'42')
            extra.append(_region(10+index,(readout,),z=2,clip=(x,2,w,1),logical=(x,2,w,1)))
    return _offer([_region(1,panes,z=0,clip=(0,0,COLS,ROWS)),
                   _region(2,(bar,),z=4 if late_bar else 1,clip=(0,bar.bounds.cell_y,COLS,1)),
                   *extra,*contents])


def _project(offer):
    return acceptance.reconstruct_retained_screen(offer,require_menu_bar=False)


def _replace_region(offer,id,**changes):
    return _offer([replace(r,**changes) if r.region_id==id else r for r in offer.retained.regions])


def test_two_panes_taskbar_exact_coverage_identity_and_metadata_only_text():
    offer=_scene();projection=_project(offer)
    assert projection.glyph_cell_count==40
    assert len(acceptance._shell_scene_geometry(offer.retained,COLS,ROWS)[2])==COLS*ROWS-40
    assert projection.region_count==4
    panes=projection.semantic_pane_claims
    assert len(panes)==2
    assert [(p.owner_id,p.owner_generation,p.object_id,p.region_id,p.content_region_id,
             p.bounds,p.content_bounds,p.focused) for p in panes]==[
        (7,9,100,1,3,RECT(0,0,6,7),RECT(1,1,5,6),True),
        (7,9,101,1,4,RECT(6,0,12,7),RECT(7,1,11,6),False),
    ]
    bar,=projection.semantic_taskbar_claims
    assert bar.bounds==RECT(0,7,12,8)
    assert [(t.identity.control_id,t.kind,t.bounds,t.order) for t in bar.tasks]==[
        (501,ControlKind.TASK,RECT(0,7,3,8),0),(502,ControlKind.LAUNCHER,RECT(5,7,8,8),1)]
    for marker in ('TITLE ONLY',acceptance.PAD_FOCUS_MARKER,'Apps','X'):
        assert marker not in projection.text
        assert all(marker not in text for text in projection.semantic_lines)
        assert not acceptance._residual_contains(projection,marker,(0,0,COLS,ROWS))


def test_zero_chrome_keeps_title_out_of_coverage_and_source_text():
    plain=_project(_scene(zero_chrome=True,title=''))
    named=_project(_scene(zero_chrome=True,title='[Pad:focused] title cannot cover content'))
    assert plain.lines==named.lines
    assert plain.glyph_cell_count==named.glyph_cell_count==84
    assert len(acceptance._shell_scene_geometry(_scene(zero_chrome=True).retained,COLS,ROWS)[2])==12
    assert '[Pad:focused]' not in named.text
    with pytest.raises(ERROR,match='uncovered'):
        _project(_scene(zero_chrome=True,missing=True))


def test_pane_outer_rectangle_does_not_excuse_unpainted_content_hole():
    with pytest.raises(ERROR,match='uncovered'):
        _project(_scene(missing=True,title='AAAA'))


def test_instrument_regions_have_unique_absolute_pane_membership_and_no_glyph_claims():
    projection=_project(_scene(instruments=True))
    assert projection.region_count==6 and projection.instrument_region_count==2
    assert projection.clipped_region_count==6
    assert projection.instrument_cell_count==8 and projection.glyph_cell_count==32
    assert [(c.left,c.top,c.right,c.bottom) for c in projection.instrument_claims]==[(1,2,5,3),(7,2,11,3)]
    assert len(projection.semantic_pane_claims)==2


@pytest.mark.parametrize('changes',[
    {'clip_cols':3},
    {'logical_x':1,'logical_cols':11},
    {'clipped':False,'clip_x':0,'clip_y':0,'clip_cols':0,'clip_rows':0},
])
def test_content_region_requires_exact_clip_and_canonical_logical_root(changes):
    with pytest.raises((ERROR,ValueError)):
        _project(_replace_region(_scene(),3,**changes))


@pytest.mark.parametrize('failure',['missing','foreign-owner','before-chrome','self'])
def test_invalid_pane_reference_never_becomes_acceptance_evidence(failure):
    offer=_scene();regions=list(offer.retained.regions)
    with pytest.raises((ERROR,ValueError)):
        if failure=='missing':regions=[r for r in regions if r.region_id!=3]
        elif failure=='foreign-owner':regions=[replace(r,owner_id=8) if r.region_id==3 else r for r in regions]
        elif failure=='before-chrome':regions=[replace(r,z_order=-1) if r.region_id==3 else r for r in regions]
        else:
            chrome=regions[0]
            regions[0]=replace(chrome,draws=(replace(chrome.draws[0],content_region_id=1),chrome.draws[1]))
        _project(_offer(regions))


def test_orphan_region_and_foreign_owner_are_rejected():
    offer=_scene()
    with pytest.raises(ERROR,match='unrelated|nonmatching'):
        _project(_offer([*offer.retained.regions,_region(30,z=5,clip=(0,0,1,1))]))
    with pytest.raises(ERROR,match='owner'):
        _project(_replace_region(offer,2,owner_id=8))


def test_overlapping_material_and_pane_content_are_not_partial_evidence():
    with pytest.raises(ERROR,match='overlap|clip'):
        _project(_scene(bar=_bar(row=6)))
    offer=_scene();chrome=offer.retained.regions[0]
    moved=replace(chrome.draws[1],bounds=ObjectBounds(5,0,6,7))
    regions=[replace(chrome,draws=(chrome.draws[0],moved))]
    for region in offer.retained.regions[1:]:
        if region.region_id==4:
            region=replace(region,clip_x=6,
                draws=tuple(replace(d,bounds=replace(d.bounds,cell_x=6)) for d in region.draws))
        regions.append(region)
    with pytest.raises(ERROR,match='overlap'):
        _project(_offer(regions))


@pytest.mark.parametrize('changes',[
    {'clipped':False,'clip_x':0,'clip_y':0,'clip_cols':0,'clip_rows':0},
    {'clip_x':4,'clip_cols':4},
    {'z_order':4},
])
def test_instrument_membership_and_painter_order_are_not_inferred_from_labels(changes):
    with pytest.raises((ERROR,ValueError)):
        _project(_replace_region(_scene(instruments=True),10,**changes))


def test_late_fullframe_taskbar_is_rejected_for_its_input_barrier():
    with pytest.raises(ERROR,match='input|content|barrier|order|clip'):
        _project(_replace_region(_scene(tabs=True,late_bar=True),2,clip_y=0,clip_rows=ROWS))


def test_fullframe_residual_region_cannot_intrude_on_pane_claims():
    offer=_scene()
    intruder=_region(30,(_glyph(3000,1,1,'AAAA'),),z=0)
    with pytest.raises(ERROR,match='intrude|overlap'):
        _project(_offer([*offer.retained.regions,intruder]))


@pytest.mark.parametrize('enabled,child_enabled,selected,minimized',[
    (True,True,True,False),(False,True,True,False),
    (True,False,False,False),(True,True,False,True),(True,True,False,False),
])
def test_focus_evidence_requires_a_real_effectively_enabled_selected_task(enabled,child_enabled,selected,minimized):
    projection=_project(_scene(bar=_bar(enabled=enabled,child_enabled=child_enabled,
                                        selected=selected,minimized=minimized)))
    assert acceptance._taskbar_has_focus(projection,acceptance.PAD_FOCUS_MARKER)==(enabled and child_enabled and selected and not minimized)
    assert acceptance._taskbar_has_focus(projection,'[missing:focused]') is False


def test_focus_marker_in_title_and_launcher_metadata_cannot_forge_task_selection():
    projection=_project(_scene(title=acceptance.PAD_FOCUS_MARKER,
                     bar=_bar(selected=False,label=acceptance.PAD_FOCUS_MARKER)))
    assert not acceptance._taskbar_has_focus(projection,acceptance.PAD_FOCUS_MARKER)
    projection=_project(_scene(bar=_bar(selected=False,kind=ControlKind.LAUNCHER)))
    assert not acceptance._taskbar_has_focus(projection,acceptance.PAD_FOCUS_MARKER)


def test_duplicate_task_labels_do_not_establish_focus_or_button_identity():
    bar=_bar()
    second=replace(bar.tasks[1],kind=ControlKind.TASK,label=acceptance.PAD_FOCUS_MARKER)
    projection=_project(_scene(bar=replace(bar,tasks=(bar.tasks[0],second))))
    assert not acceptance._taskbar_has_focus(projection,acceptance.PAD_FOCUS_MARKER)
    with pytest.raises(ERROR,match='exactly one'):
        acceptance._taskbar_button_cell(projection,'[1:')


@pytest.fixture(scope='module')
def renderer():
    pygame=pytest.importorskip('pygame')
    pygame.font.init()
    return pygame,pygame.font.Font(None,16)


def _paint(renderer,offer,appearance):
    pygame,font=renderer
    surface=pygame.Surface((COLS*8,ROWS*12));surface.fill((191,29,53))
    return composite_draw_plane_result(pygame,surface,offer.retained,font,8,12,appearance=appearance)


@pytest.mark.parametrize('appearance',[REFERENCE_APPEARANCE,FLOWING_APPEARANCE])
def test_taskbar_claim_slots_match_real_hit_geometry_and_gaps_block(renderer,appearance):
    offer=_scene(tabs=True)
    projection=_project(offer);painted=_paint(renderer,offer,appearance)
    bar,=projection.semantic_taskbar_claims
    for task in bar.tasks:
        hit=painted.hit_test(task.bounds.left*8+1,task.bounds.top*12+1)
        assert isinstance(hit,ControlHitTarget) and hit.identity==task.identity
        assert (hit.rect.left,hit.rect.top,hit.rect.right,hit.rect.bottom)==(
            task.bounds.left*8,task.bounds.top*12,task.bounds.right*8,task.bounds.bottom*12)
    for x in (3,4,8,11):assert painted.hit_test(x*8+1,7*12+1) is None
    assert any(isinstance(entry,ControlSurface) for entry in painted.hit_entries)
    for x in (1,7):
        assert painted.hit_test(x*8+1,1*12+1) is not None


@pytest.mark.parametrize('root_enabled,child_enabled',[(False,True),(True,False)])
def test_disabled_task_input_does_not_pass_through_opaque_material(renderer,root_enabled,child_enabled):
    offer=_scene(bar=_bar(enabled=root_enabled,child_enabled=child_enabled,selected=False))
    projection=_project(offer);painted=_paint(renderer,offer,FLOWING_APPEARANCE)
    assert len(projection.semantic_taskbar_claims)==1
    assert painted.hit_test(1,7*12+1) is None
    assert any(isinstance(entry,ControlSurface) for entry in painted.hit_entries)


def test_zero_chrome_title_has_identical_actual_pixels(renderer):
    plain=_paint(renderer,_scene(zero_chrome=True,title=''),FLOWING_APPEARANCE)
    named=_paint(renderer,_scene(zero_chrome=True,title='A long metadata title'),FLOWING_APPEARANCE)
    pygame,_=renderer
    assert pygame.image.tobytes(plain.surface,'RGBA')==pygame.image.tobytes(named.surface,'RGBA')
    assert plain.hit_targets==named.hit_targets


def _acknowledged(offer, entries):
    state=acceptance._RetainedDisplayState()
    state.stage(offer,9)
    state.stage_frame_hit_map(offer,entries)
    assert state.finish_presentation({
        'status':'presented','presented':True,'revision':offer.scope.model_revision,
    })==offer.scope.model_revision
    return state,(offer.offer_id,offer.scope)


class _Client:
    def __init__(self):
        self.requests=[]

    def request(self,method,**params):
        self.requests.append((method,params))
        return {'status':'progress','accepted_events':1}


def _activate(client,offer,state,ack,*,method='activate_shell_task',value='7,9,501'):
    return acceptance._request_acceptance_input(
        client,method,value,offer,9,display_state=state,display_ack=ack,
        cell_width=8,cell_height=12,
    )


@pytest.mark.parametrize('method,control_id,kind,label',[
    ('activate_shell_task',501,ControlKind.TASK,acceptance.PAD_FOCUS_MARKER),
    ('activate_shell_launcher',502,ControlKind.LAUNCHER,'Apps'),
])
def test_shell_activation_uses_exact_acknowledged_real_slot(renderer,method,control_id,kind,label):
    offer=_scene(tabs=True,late_bar=True)
    painted=_paint(renderer,offer,FLOWING_APPEARANCE)
    state,ack=_acknowledged(offer,painted.hit_entries)
    identity=ControlIdentity(7,9,control_id)
    target,actual_label=acceptance._shell_hit_target(offer,state,ack,identity,kind)
    assert actual_label==label and target.identity==identity
    client=_Client()
    status,evidence=_activate(client,offer,state,ack,method=method,value=f'7,9,{control_id}')
    assert status=='progress' and len(client.requests)==1
    rpc,params=client.requests[0]
    assert rpc=='send_control_event'
    assert (params['owner_id'],params['owner_generation'],params['control_id'])==(7,9,control_id)
    assert params['display_offer_id']==offer.offer_id and params['generation']==9
    assert 'content_revision' not in params and 'adjustment' not in params
    assert evidence.semantic_target['kind']==kind.name
    assert evidence.semantic_target['label']==label
    assert evidence.semantic_target['pixel_rect']=={
        'left':target.rect.left,'top':target.rect.top,
        'right':target.rect.right,'bottom':target.rect.bottom,
    }
    # A correctly clipped late taskbar must preserve both pane controls.
    assert len(_project(offer).semantic_pane_claims)==2
    for x in (1,7):
        assert painted.hit_test(x*8+1,1*12+1) is not None


@pytest.mark.parametrize('mutation',[
    'no-ack','stale-offer','stale-scope','wrong-map','disabled-root',
    'disabled-child','wrong-kind','wrong-owner','wrong-generation',
    'wrong-control','no-target','duplicate-target','occluded',
])
def test_shell_activation_rejects_unproved_targets_without_sending(renderer,mutation):
    offer=_scene(bar=_bar(enabled=mutation!='disabled-root',
                          child_enabled=mutation!='disabled-child',selected=False))
    entries=_paint(renderer,offer,FLOWING_APPEARANCE).hit_entries
    task=next((e for e in entries if isinstance(e,ControlHitTarget)
               and e.identity.control_id==501),None)
    if mutation=='no-target':
        entries=tuple(e for e in entries if e is not task)
    if mutation=='duplicate-target':entries=(*entries,task)
    if mutation=='occluded':
        entries=(*entries,RegionOcclusion(7,9,50,PixelRect(0,84,24,96)))
    state,ack=_acknowledged(offer,entries)
    if mutation=='no-ack':ack=None
    if mutation=='stale-offer':ack=(offer.offer_id+1,offer.scope)
    if mutation=='stale-scope':ack=(offer.offer_id,replace(offer.scope,model_revision=2))
    if mutation=='wrong-map':
        state,_=_acknowledged(replace(offer,offer_id=2),entries)
    method='activate_shell_launcher' if mutation=='wrong-kind' else 'activate_shell_task'
    value={
        'wrong-owner':'8,9,501','wrong-generation':'7,10,501',
        'wrong-control':'7,9,599',
    }.get(mutation,'7,9,501')
    client=_Client()
    with pytest.raises(ERROR):
        _activate(client,offer,state,ack,method=method,value=value)
    assert client.requests==[]


def test_taskbar_slot_center_does_not_depend_on_long_label_width():
    projection=_project(_scene())
    assert acceptance._taskbar_button_cell(projection,'[1:')==(1,7)
    with pytest.raises(ERROR):
        acceptance._taskbar_button_cell(_project(_scene(bar=_bar(enabled=False))),'[1:')


def test_taskbar_gaps_only_cover_the_declared_root():
    offer=_scene()
    bar=replace(_bar(),bounds=ObjectBounds(0,7,8,1))
    regions=[replace(r,draws=(bar,),clip_cols=8) if r.region_id==2 else r
             for r in offer.retained.regions]
    with pytest.raises(ERROR,match='uncovered'):
        _project(_offer(regions))


def _short_bar_scene():
    offer=_scene()
    bar=replace(_bar(),bounds=ObjectBounds(0,7,8,1))
    regions=[replace(r,draws=(bar,),clip_cols=8) if r.region_id==2 else r
             for r in offer.retained.regions]
    return _offer([*regions,_region(30,(_glyph(3000,8,7,'TAIL'),),z=0)])


def test_short_taskbar_and_independent_residual_cover_exact_disjoint_bands():
    projection=_project(_short_bar_scene())
    assert projection.semantic_taskbar_claims[0].bounds==RECT(0,7,8,8)
    assert projection.glyph_cell_count==44
    assert acceptance._residual_contains(projection,'TAIL',(8,7,12,8))


def test_taskbar_region_clip_cannot_extend_beyond_its_declared_band():
    with pytest.raises(ERROR,match='clip|band'):
        _project(_replace_region(_short_bar_scene(),2,clip_cols=12))


def test_empty_pane_content_region_can_reference_independently_painted_instrument():
    offer=_scene()
    regions=[replace(r,draws=()) if r.region_id==3 else r for r in offer.retained.regions]
    instrument=ReadoutDraw(800,0,ObjectBounds(0,0,4,5),WHITE,BLACK,'42')
    regions.append(_region(10,(instrument,),z=2,logical=(1,1,4,5),clip=(1,1,4,5)))
    projection=_project(_offer(regions))
    assert len(projection.semantic_pane_claims)==2
    assert projection.instrument_cell_count==20 and projection.glyph_cell_count==20


def test_later_content_paint_withholds_covered_instrument_identity():
    offer=_scene(instruments=True)
    # One covered cell is enough to withhold the entire instrument claim.
    cover=TabSetDraw(200,ACTIVE,0,1,ObjectBounds(1,2,1,1),
                    (TabDraw(201,ACTIVE|ControlState.SELECTED,0,'Cover',''),))
    region=next(r for r in offer.retained.regions if r.region_id==3)
    offer=_replace_region(offer,3,draws=retained_draw_order((*region.draws,cover)))
    projection=_project(offer)
    assert [claim.object_id for claim in projection.instrument_claims]==[801]
    assert len(projection.semantic_tabset_claims)==1
    assert projection.semantic_tabset_claims[0].identity.control_id==200


def test_taskbar_only_scene_preserves_legacy_base_and_band_input(renderer):
    offer=_offer([
        _region(1,tuple(_glyph(1000+row,0,row,'A'*COLS) for row in range(7))),
        _region(2,(_bar(),),z=1,clip=(0,7,COLS,1)),
    ])
    projection=_project(offer)
    assert projection.semantic_pane_claims==()
    assert len(projection.semantic_taskbar_claims)==1 and projection.glyph_cell_count==84
    painted=_paint(renderer,offer,FLOWING_APPEARANCE)
    assert painted.hit_test(1,85).identity==ControlIdentity(7,9,501)


def test_task_and_launcher_bands_share_exact_clip_with_authored_divider(renderer):
    original=_bar()
    task_band=replace(original,bounds=ObjectBounds(0,7,3,1),tasks=(original.tasks[0],))
    launcher=replace(original.tasks[1],bounds=ObjectBounds(0,0,3,1),order=0)
    launch_band=replace(original,control_id=510,bounds=ObjectBounds(5,7,3,1),
                        tasks=(launcher,))
    offer=_scene()
    regions=[replace(r,draws=retained_draw_order((task_band,launch_band)),clip_cols=8)
             if r.region_id==2 else r for r in offer.retained.regions]
    residual=_region(30,(_glyph(3000,3,7,' |'),_glyph(3001,8,7,'TAIL')),z=0)
    offer=_offer([*regions,residual])
    projection=_project(offer)
    assert [bar.bounds for bar in projection.semantic_taskbar_claims]==[
        RECT(0,7,3,8),RECT(5,7,8,8),
    ]
    painted=_paint(renderer,offer,FLOWING_APPEARANCE)
    assert painted.hit_test(1,85).identity==ControlIdentity(7,9,501)
    assert painted.hit_test(41,85).identity==ControlIdentity(7,9,502)
    assert painted.hit_test(25,85) is None
    assert painted.hit_test(33,85) is None
    assert acceptance._residual_contains(projection,' |',(3,7,5,8))
