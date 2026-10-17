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
    ButtonDraw, DialogDraw,
    DisplayScope, FieldDraw, GlyphRunDraw, PaneDraw, ReadoutDraw, RetainedDrawPlane,
    RetainedRegionDraw, StatusFieldDraw, TabDraw, TabSetDraw, TaskBarDraw, TaskDraw,
    retained_draw_order,
)
from rich_terminal.semantic_dialogs import ButtonContent, ButtonFlag, DialogContent, DialogFlag
from rich_terminal.semantic_fields import FieldContent, FieldFlag, FieldKind, FieldRect
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


def _prompt(x, y, w):
    """A prompt's TEXT field over one content row: label A, value hi."""
    content=FieldContent(1,FieldKind.TEXT,FieldFlag(0),FieldRect(0,0,1,1),
                         FieldRect(2,0,w-2,1),text='hi',caret=2,anchor=2)
    return FieldDraw(600,ACTIVE|ControlState.SELECTED,0,255,ObjectBounds(x,y,w,1),'A',content)


def _dialog(x, y, w):
    """A dialog over three content rows from Y: the message Go? on its first,
    and the buttons Y, the default, and N, the cancel button, on its last."""
    content=DialogContent(1,DialogFlag(0),3,FieldRect(0,0,0,0),FieldRect(0,0,w,1),
                          message='Go?')
    half=w//2
    return (DialogDraw(600,ControlState.VISIBLE,0,255,ObjectBounds(x,y,w,3),'',content),
            ButtonDraw(601,ACTIVE|ControlState.SELECTED,0,255,ObjectBounds(x,y+2,half,1),
                       'Y','',ButtonContent(ButtonFlag.DEFAULT)),
            ButtonDraw(602,ACTIVE,0,255,ObjectBounds(x+half,y+2,w-half,1),
                       'N','',ButtonContent(ButtonFlag.CANCEL)))


def _scene(*, instruments=False,tabs=False,zero_chrome=False,
           title='TITLE ONLY',bar=None,late_bar=False,missing=False,prompt=False,
           dialog=False):
    """Two panes and a taskbar.  With PROMPT, pane 0's last content row is a
    prompt's field in a MODAL region over that content, which holds the
    pane's controls inactive; with DIALOG, its last three rows are a dialog
    and its buttons there."""
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
        held=(prompt or dialog) and index==0
        for row in range(y,y+h):
            if instruments and row==2:continue
            if tabs and row==1:continue
            if missing and index==0 and row==y:continue
            if held and row>=y+h-(3 if dialog else 1):continue
            draws.append(_glyph(1000+index*100+row,x,row,chr(65+index)*w))
        if tabs:
            draws.append(TabSetDraw(200+index*10,ACTIVE,0,1,ObjectBounds(x,1,w,1),
                         (TabDraw(201+index*10,ACTIVE|ControlState.SELECTED,0,'Keep',''),)))
        region=_region(3+index,draws,z=3,clip=(x,y,w,h))
        if held:
            region=replace(region,inactive_controls=frozenset((200,201) if tabs else ()))
            overlay=_dialog(x,y+h-3,w) if dialog else (_prompt(x,y+h-1,w),)
            modal=_region(20,overlay,z=5,clip=(x,y,w,h))
            extra.append(replace(modal,modal=True))
        contents.append(region)
        if instruments:
            readout=ReadoutDraw(800+index,0,ObjectBounds(0,0,w,1),WHITE,BLACK,'42')
            extra.append(_region(10+index,(readout,),z=2,clip=(x,2,w,1),logical=(x,2,w,1)))
    return _offer([_region(1,panes,z=0,clip=(0,0,COLS,ROWS)),
                   _region(2,(bar,),z=4 if late_bar else 1,clip=(0,bar.bounds.cell_y,COLS,1)),
                   *extra,*contents])


def _screen_scene(*, depth=4, dialog=(3,2), modal_z=5, bar=None):
    """One zero-chrome pane of A and, over it, an overlay pane, one of
    Desk's screens: a dialog over rows 2 to 4 and columns 3 to 8 in a modal
    region over the whole screen, which holds the taskbar inactive beneath
    it.  The pane's glyphs leave the screen's cells to it."""
    pane=PaneDraw(100,0,ObjectBounds(0,0,COLS,7),3,ObjectBounds(0,0,COLS,7),'Files',True)
    screen=PaneDraw(101,0,ObjectBounds(3,2,6,3),4,ObjectBounds(0,0,6,3),'Applets',False)
    glyphs=[]
    for row in range(7):
        if 2<=row<5:
            glyphs+=[_glyph(1000+row*2,0,row,'AAA'),_glyph(1001+row*2,9,row,'AAA')]
        else:
            glyphs.append(_glyph(1000+row*2,0,row,'A'*COLS))
    bar=replace(_region(2,(_bar() if bar is None else bar,),z=1,clip=(0,7,COLS,1)),
                inactive_controls=frozenset((500,501,502)))
    modal=replace(_region(20,_dialog(*dialog,6),z=modal_z,clip=(0,0,COLS,ROWS)),modal=True)
    return _offer([_region(1,(pane,screen),z=0,clip=(0,0,COLS,ROWS)),bar,
                   _region(3,glyphs,z=3,clip=(0,0,COLS,7)),
                   _region(4,(),z=depth,clip=(3,2,6,3)),modal])


def _divider_screen_scene(*, top=2, height=3, gap=False):
    """Two panes with chrome side by side and, over the divider between
    them, an overlay pane, one of Desk's screens, over columns 3 to 8 from
    row TOP, its dialog over rows 2 to 4 in a modal region over the whole
    screen.  The screen's own glyphs fill its rows outside the dialog, over
    both panes' content and chrome; with GAP they leave the chrome out."""
    box=range(top,top+height)
    panes=[PaneDraw(100,0,ObjectBounds(0,0,6,7),3,ObjectBounds(1,1,4,5),'Files',True),
           PaneDraw(101,0,ObjectBounds(6,0,6,7),4,ObjectBounds(1,1,4,5),'Notes',False),
           PaneDraw(102,0,ObjectBounds(3,top,6,height),5,ObjectBounds(0,0,6,height),
                    'Applets',False)]
    contents=[]
    for index,(left,char) in enumerate(((1,'A'),(7,'B'))):
        glyphs=[]
        for row in range(1,6):
            if row not in box:
                glyphs.append(_glyph(1000+index*100+row,left,row,char*4))
            elif index==0:
                glyphs.append(_glyph(1000+row,1,row,char*2))
            else:
                glyphs.append(_glyph(1100+row,9,row,char*2))
        contents.append(_region(3+index,glyphs,z=3,clip=(left,1,4,5)))
    glyphs=[]
    for row in box:
        if 2<=row<5:continue
        glyphs+=([_glyph(1200+row*2,3,row,'SS'),_glyph(1201+row*2,7,row,'SS')] if gap
                 else [_glyph(1200+row*2,3,row,'S'*6)])
    bar=replace(_region(2,(_bar(),),z=1,clip=(0,7,COLS,1)),
                inactive_controls=frozenset((500,501,502)))
    modal=replace(_region(20,_dialog(3,2,6),z=5,clip=(0,0,COLS,ROWS)),modal=True)
    return _offer([_region(1,panes,z=0,clip=(0,0,COLS,ROWS)),bar,*contents,
                   _region(5,glyphs,z=4,clip=(3,top,6,height)),modal])


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


def test_an_overlay_pane_lies_over_the_pane_beneath_with_its_document_modal():
    """One of Desk's screens: its pane lies over the pane beneath, and its
    dialog is in a modal scope over the whole screen, taskbar included."""
    projection=_project(_screen_scene())
    panes=projection.semantic_pane_claims
    assert [(p.object_id,p.content_bounds) for p in panes]==[
        (100,RECT(0,0,12,7)),(101,RECT(3,2,9,5))]
    dialog,=projection.semantic_dialog_claims
    assert dialog.modal and (dialog.left,dialog.top,dialog.right,dialog.bottom)==(3,2,9,5)
    assert dialog.identity not in projection.inactive_controls
    assert ControlIdentity(7,9,500) in projection.inactive_controls


def test_a_screens_modal_scope_keeps_the_focused_task_beneath_it():
    """Desk disables its taskbar while a screen is open; the focused task
    keeps its selection beneath the screen's modal scope, inactive."""
    projection=_project(_screen_scene(bar=_bar(enabled=False)))
    assert acceptance._taskbar_has_focus(projection,acceptance.PAD_FOCUS_MARKER)
    projection=_project(_screen_scene(bar=_bar(enabled=False,selected=False)))
    assert not acceptance._taskbar_has_focus(projection,acceptance.PAD_FOCUS_MARKER)
    projection=_project(_screen_scene(bar=_bar(enabled=False,selected=False,minimized=True)))
    assert not acceptance._taskbar_has_focus(projection,acceptance.PAD_FOCUS_MARKER)


@pytest.mark.parametrize('top,height',[(2,3),(1,5)])
def test_an_overlay_pane_lies_over_the_divider_between_two_panes(top,height):
    """One of Desk's screens across the divider between two tiles: it hides
    the chrome it lies over, its dialog and its own glyphs covering it."""
    projection=_project(_divider_screen_scene(top=top,height=height))
    assert [p.object_id for p in projection.semantic_pane_claims]==[100,101,102]
    dialog,=projection.semantic_dialog_claims
    assert dialog.modal and (dialog.left,dialog.top,dialog.right,dialog.bottom)==(3,2,9,5)
    assert ControlIdentity(7,9,500) in projection.inactive_controls
    if height==5:
        assert projection.row_text(1)[3:9]=='S'*6
        assert projection.row_text(5)[3:9]=='S'*6


def test_a_screen_whose_glyphs_leave_out_the_divider_leaves_cells_uncovered():
    with pytest.raises(ERROR,match='uncovered'):
        _project(_divider_screen_scene(top=1,height=5,gap=True))


@pytest.mark.parametrize('changes,match',[
    # The screen's pane at the depth of the pane beneath it.
    ({'depth':3},'overlap'),
    # A dialog that reaches the taskbar row, outside every pane.
    ({'dialog':(3,5)},"neither Desk's prompt"),
    # A modal region beneath the screen's content.
    ({'modal_z':3},'beneath'),
])
def test_an_overlay_panes_document_needs_its_own_depth_and_pane(changes,match):
    with pytest.raises(ERROR,match=match):
        _project(_screen_scene(**changes))


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


def test_a_prompt_in_a_modal_region_over_its_pane_is_held_evidence():
    projection=_project(_scene(tabs=True,prompt=True))
    field,=projection.semantic_field_claims
    assert field.modal and field.label=='A' and field.content.text=='hi'
    assert (field.left,field.top,field.right,field.bottom)==(1,5,5,6)
    assert projection.inactive_controls=={ControlIdentity(7,9,200),ControlIdentity(7,9,201)}
    assert acceptance._prompt_claim(projection,'A',(0,0,6,7)) is field
    assert acceptance._prompt_claim(projection,'A',(6,0,12,7)) is None
    # The other pane's tabset stays active.
    assert ControlIdentity(7,9,210) not in projection.inactive_controls


@pytest.mark.parametrize('changes,message',[
    ({'clip_x':0,'clip_cols':5},'exactly one'),
    ({'z_order':2},'beneath'),
    # Unclipped, it would also stop the taskbar's points.
    ({'clipped':False,'clip_x':0,'clip_y':0,'clip_cols':0,'clip_rows':0},
     'clipped surface|blocks TASKBAR'),
])
def test_a_modal_region_must_hold_exactly_its_pane_content_above_it(changes,message):
    with pytest.raises(ERROR,match=message):
        _project(_replace_region(_scene(tabs=True,prompt=True),20,**changes))


def _desk_prompt_scene(*, row=ROWS-1, width=COLS, z=6, glyph=False):
    """Two panes with Desk's own prompt in place of the taskbar: one field
    across the last row in a MODAL region over the whole screen, above
    every other region.  With GLYPH a residual run paints on that row too."""
    held={3:frozenset((200,201)),4:frozenset((210,211))}
    regions=[replace(r,inactive_controls=held.get(r.region_id,frozenset()))
             for r in _scene(tabs=True).retained.regions if r.region_id!=2]
    if glyph:
        regions.append(_region(30,(_glyph(3000,0,ROWS-1,'Z'),),z=-1,clip=(0,0,COLS,ROWS)))
    modal=_region(21,(_prompt(0,row,width),),z=z,clip=(0,0,COLS,ROWS))
    return _offer([*regions,replace(modal,modal=True)])


def test_desks_prompt_holds_the_taskbar_row_in_a_whole_screen_modal_scope():
    projection=_project(_desk_prompt_scene())
    field,=projection.semantic_field_claims
    assert field.modal and (field.left,field.top,field.right,field.bottom)==(0,ROWS-1,COLS,ROWS)
    assert not projection.semantic_taskbar_claims
    # Every pane's controls are held beneath it.
    assert {ControlIdentity(7,9,200),ControlIdentity(7,9,201),
            ControlIdentity(7,9,210),ControlIdentity(7,9,211)}<=projection.inactive_controls


@pytest.mark.parametrize('changes,message',[
    ({'row':ROWS-2},"neither Desk's prompt"),
    ({'width':COLS-1},"neither Desk's prompt"),
    ({'z':2},'above every other region'),
    ({'glyph':True},'intrude'),
])
def test_desks_prompt_scope_must_be_its_row_alone_above_everything(changes,message):
    with pytest.raises(ERROR,match=message):
        _project(_desk_prompt_scene(**changes))


def test_a_field_region_that_is_not_modal_is_not_a_prompt():
    with pytest.raises(ERROR,match='unrelated|nonmatching'):
        _project(_replace_region(_scene(tabs=True,prompt=True),20,modal=False))


def test_a_dialog_and_its_buttons_in_a_modal_region_over_its_pane_are_held_evidence():
    projection=_project(_scene(tabs=True,dialog=True))
    dialog,=projection.semantic_dialog_claims
    assert dialog.modal and dialog.title=='' and dialog.content.message=='Go?'
    assert (dialog.left,dialog.top,dialog.right,dialog.bottom)==(1,3,5,6)
    assert [(button.label,button.left,button.top,button.right,button.bottom)
            for button in dialog.buttons]==[('Y',1,5,3,6),('N',3,5,5,6)]
    assert dialog.button('N').content.cancel and dialog.button('Y').content.default
    assert dialog.button('Z') is None
    assert projection.inactive_controls=={ControlIdentity(7,9,200),ControlIdentity(7,9,201)}
    assert ControlIdentity(7,9,210) not in projection.inactive_controls


def test_a_button_outside_its_dialog_is_refused():
    offer=_scene(tabs=True,dialog=True)
    region=next(r for r in offer.retained.regions if r.region_id==20)
    dialog,first,second=region.draws
    moved=replace(second,bounds=ObjectBounds(3,2,2,1))
    with pytest.raises(ERROR,match='no dialog'):
        _project(_replace_region(offer,20,draws=retained_draw_order((dialog,first,moved))))


def test_a_dialog_region_must_hold_exactly_its_pane_content_above_it():
    with pytest.raises(ERROR,match='beneath'):
        _project(_replace_region(_scene(tabs=True,dialog=True),20,z_order=2))


def _notice(x, y, w, *, severity=3, message='Saved'):
    """The app shell's notice: one row as wide as its bar, its message two
    cells in."""
    content=DialogContent(1,DialogFlag.NOTICE,severity,FieldRect(0,0,0,0),
                          FieldRect(2,0,w-4,1),message=message)
    return DialogDraw(700,ControlState.VISIBLE,0,0,ObjectBounds(x,y,w,1),'',content)


def _notice_scene(*, x=1, width=9, row=ROWS-1, z=7, clip=None, base=None):
    """The two panes and the taskbar, and a notice over the taskbar row in a
    region of its own above every other."""
    base=_scene() if base is None else base
    region=_region(40,(_notice(x,row,width),),z=z,clip=clip or (x,row,width,1))
    return _offer([*base.retained.regions,region])


def test_a_notice_lies_over_the_taskbar_in_a_region_of_its_own():
    projection=_project(_notice_scene())
    notice,=projection.semantic_dialog_claims
    assert notice.content.notice and notice.content.severity==3 and not notice.modal
    assert notice.content.message=='Saved' and notice.title==''
    assert (notice.left,notice.top,notice.right,notice.bottom)==(1,ROWS-1,10,ROWS)
    # The taskbar it covers stays semantic beneath it, and active.
    bar,=projection.semantic_taskbar_claims
    assert [task.identity.control_id for task in bar.tasks]==[501,502]
    assert not projection.inactive_controls


def test_a_notice_lies_over_desks_prompt():
    projection=_project(_notice_scene(base=_desk_prompt_scene()))
    notice,=projection.semantic_dialog_claims
    assert notice.content.notice and not projection.semantic_taskbar_claims


@pytest.mark.parametrize('changes,message',[
    ({'clip':(0,ROWS-1,COLS,1)},'not clipped to the notice'),
    ({'z':2},'above every other region'),
    ({'row':3},'over PANE content'),
])
def test_a_notice_lies_clipped_to_itself_above_everything_apart_from_panes(changes,message):
    with pytest.raises(ERROR,match=message):
        _project(_notice_scene(**changes))


def _status_scene(*, clip=(8,ROWS-1,4,1), x=8, row=ROWS-1, notice=False):
    """The two panes and a taskbar over columns 0 to 7, and Desk's status,
    A: ok, in a region of its own across the rest of the taskbar row; with
    NOTICE, a notice over columns 1 to 9 above it."""
    tasks=(TaskDraw(501,ControlKind.TASK,ACTIVE|ControlState.SELECTED,0,ObjectBounds(0,0,3,1),
                    acceptance.PAD_FOCUS_MARKER),
           TaskDraw(502,ControlKind.LAUNCHER,ACTIVE,1,ObjectBounds(5,0,3,1),'Apps'))
    bar=TaskBarDraw(500,ACTIVE,0,0,ObjectBounds(0,ROWS-1,8,1),tasks)
    base=_scene(bar=bar)
    regions=[replace(r,clip_cols=8) if r.region_id==2 else r for r in base.retained.regions]
    status=StatusFieldDraw(710,0,ObjectBounds(x,row,4,1),'A','ok',2)
    regions.append(_region(30,(status,),z=1,clip=clip))
    if notice:
        regions.append(_region(40,(_notice(1,ROWS-1,9),),z=7,clip=(1,ROWS-1,9,1)))
    return _offer(regions)


def test_desks_status_lies_across_the_taskbar_row_past_its_entries():
    offer=_status_scene()
    panes,bars,cells,roles=acceptance._shell_scene_geometry(offer.retained,COLS,ROWS)
    assert roles[30]=='status' and roles[2]=='taskbar'
    assert {(col,ROWS-1) for col in range(8,12)} <= cells
    claim,=_project(offer).semantic_status_field_claims
    assert (claim.label,claim.value,claim.label_cols)==('A','ok',2)
    assert (claim.left,claim.top,claim.right,claim.bottom)==(8,ROWS-1,12,ROWS)
    # A notice over it hides part of it and leaves the region a status.
    assert acceptance._shell_scene_geometry(
        _status_scene(notice=True).retained,COLS,ROWS)[3][30]=='status'


@pytest.mark.parametrize('changes,message',[
    ({'clip':(8,ROWS-2,4,2)},'taskbar row past its entries'),
    ({'clip':(8,ROWS-1,3,1),'x':8},'taskbar row past its entries'),
    ({'clip':(6,ROWS-1,6,1),'x':6},'shell material claims overlap'),
])
def test_desks_status_region_must_be_the_taskbar_row_past_its_entries(changes,message):
    with pytest.raises(ERROR,match=message):
        _project(_status_scene(**changes))
