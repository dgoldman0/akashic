"""DOCUMENT controls through the neutral facade and the APT-1 engine to the wire.

A DOC1 body with containers and a style run, from MegaPad's own encoder, is
defined through RTE-CONTROL-DEFINE and directly through RTAPT-CONTROL-DEFINE,
published, and installed by the terminal as the same document.  A document
smaller than STX1's smallest body is a document too, and totals that
disagree with the bytes are refused before anything is copied.
"""
import struct

import pytest

from test_rich_terminal_status_provider import ProviderHarness, RetainedFeature
from test_rich_terminal_status_static import MASK, _offset
from rich_terminal.retained_scene import ControlKind
from rich_terminal.semantic_content import StyleRun, TextStyle
from rich_terminal.semantic_documents import (
    BlockContainer,
    BlockKind,
    ContainerKind,
    DocumentBlock,
    DocumentContent,
    DocumentFlag,
    encode_document_content,
)

FEATURES = (RetainedFeature.CORE | RetainedFeature.CONTROLS
            | RetainedFeature.CONTROL_COLLECTIONS | RetainedFeature.CONTROL_DOCUMENTS)


def _document() -> DocumentContent:
    """Two blocks that fill the harness's root, 20 cells by 2 rows: a heading
    with a link, and a paragraph inside a quote and a numbered item."""

    quote = BlockContainer(ContainerKind.QUOTE, 2)
    item = BlockContainer(ContainerKind.NUMBERED_ITEM, 4, 3, True)
    return DocumentContent(
        7,
        DocumentFlag(0),
        (
            DocumentBlock(1, BlockKind.HEADING, "Notes", level=2,
                          runs=(StyleRun(0, 5, TextStyle.LINK),)),
            DocumentBlock(2, BlockKind.PARAGRAPH, "quoted", containers=(quote, item)),
        ),
    )


def _rule() -> DocumentContent:
    """One rule: 64 bytes of DOC1, fewer than STX1's smallest 72."""

    return DocumentContent(3, DocumentFlag(0), (DocumentBlock(1, BlockKind.RULE),))


class DocumentProvider(ProviderHarness):
    def __init__(self, backend):
        super().__init__(backend, features=FEATURES)

    def control(self, document: DocumentContent, **changes):
        payload = encode_document_content(document)
        text = self.allocate(payload)
        values = dict(OWNER=1, GENERATION=1, ID=1, KIND=14, STATE=3, Z=0,
                      REGION=1, PARENT=0, ORDER=0, ROW=0, COL=0, HEIGHT=2, WIDTH=20,
                      **{'ROOT-HEIGHT': 2, 'ROOT-WIDTH': 20, 'LABEL-A': 0, 'LABEL-U': 0,
                         'SHORTCUT-A': 0, 'SHORTCUT-U': 0,
                         'CONTENT-A': text, 'CONTENT-U': len(payload),
                         'CONTENT-ITEMS': len(document.blocks),
                         'CONTENT-UTF8': document.utf8_bytes,
                         'CONTENT-RUNS': document.style_run_count,
                         'CONTENT-FIELDS': sum(len(block.containers)
                                               for block in document.blocks)})
        values.update(changes)
        data = bytearray(200)
        for name, value in values.items():
            struct.pack_into('<Q', data, _offset('_RTE-CONTROL.' + name), value & MASK)
        return self.allocate(data), payload

    def define(self, record):
        return self.call('RTE-CONTROL-DEFINE', record, self.facade)[0]

    def direct(self, record):
        values = struct.unpack('<25Q', self.runtime.memory.read_bytes(record, 200))
        return self.call('RTAPT-CONTROL-DEFINE', *values, self.engine)[0]


@pytest.fixture(params=('python', 'native'))
def document(request):
    harness = DocumentProvider(request.param)
    try:
        yield harness
    finally:
        harness.close()


@pytest.mark.parametrize('route', ('define', 'direct'))
def test_a_document_reaches_the_terminal_whole(document, route):
    content = _document()
    document.begin()
    record, payload = document.control(content)
    assert getattr(document, route)(record) == (0,)
    copied = document.field('_RTAPT-E.COPY-A') + 104
    size = document.runtime.memory.read64(document.field('_RTAPT-E.OPS-A') + 40 + 16)
    assert document.call('_RTAPT-CONTROL-COPY-SHAPE?', copied, size)[0] != (0,)
    document.publish()
    owner = document.installed()
    control = owner.controls[1]
    assert control.kind is ControlKind.DOCUMENT
    assert encode_document_content(control.content) == payload
    assert owner.usage.objects == 1 + len(content.blocks)
    assert owner.usage.utf8_bytes == content.utf8_bytes


def test_a_document_smaller_than_stx1_is_still_a_document(document):
    content = _rule()
    document.begin()
    record, payload = document.control(content)
    assert len(payload) < 72
    assert document.define(record) == (0,)
    document.publish()
    assert encode_document_content(document.installed().controls[1].content) == payload


def test_totals_that_disagree_with_the_bytes_are_refused(document):
    content = _document()
    document.begin()
    for name in ('CONTENT-ITEMS', 'CONTENT-FIELDS', 'CONTENT-UTF8', 'CONTENT-RUNS'):
        right = {'CONTENT-ITEMS': len(content.blocks), 'CONTENT-FIELDS': 2,
                 'CONTENT-UTF8': content.utf8_bytes,
                 'CONTENT-RUNS': content.style_run_count}[name]
        record, _ = document.control(content, **{name: right + 1})
        assert document.define(record) == (5,), name
        assert document.direct(record) == (3,), name
    assert document.field('_RTAPT-E.OP-COUNT') == 1
    record, _ = document.control(content)
    assert document.define(record) == (0,)
    assert document.call('RTAPT-RICH-CANCEL', document.engine)[0] == (0,)
