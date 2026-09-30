"""FIELD and SERIES probes retain exact CELL evidence at modal boundaries."""
from dataclasses import replace
import hashlib
import pytest
from test_rich_terminal_desktop_acceptance import _offer
from rich_terminal_desktop_acceptance import (
    PhysicalDesktopAcceptanceError, _require_cell_fallback_evidence,
)


@pytest.mark.parametrize('boundary', ['field-prompt', 'series-prompt'])
def test_field_prompt_fallback_keeps_exact_offer_and_cell_evidence(boundary):
    prompt = 'Frequency (40-2000 Hz): 40'
    offer = _offer(prompt, offer_id=73)
    offer = replace(offer, retained=replace(offer.retained, regions=()))
    evidence = _require_cell_fallback_evidence(boundary, offer, 19, (prompt,))
    assert (evidence.boundary, evidence.offer_id, evidence.generation) == (boundary, 73, 19)
    assert evidence.cell_text_sha256 == hashlib.sha256(offer.cell.text(trim_right=True).encode()).hexdigest()
    assert evidence.ready_markers == (prompt,)
    assert evidence.to_dict()['ready'] is True


@pytest.mark.parametrize('boundary', ['field-prompt', 'series-prompt'])
def test_field_prompt_boundary_does_not_excuse_missing_cell_prompt(boundary):
    with pytest.raises(PhysicalDesktopAcceptanceError, match=f'not {boundary}-ready'):
        _require_cell_fallback_evidence(boundary, _offer('unrelated'), 19,
                                       ('Frequency (40-2000 Hz): 40',))


def test_unknown_cell_fallback_boundary_still_refused():
    with pytest.raises(ValueError, match='CELL fallback boundary'):
        _require_cell_fallback_evidence('unknown', _offer('ready'), 19, ('ready',))
