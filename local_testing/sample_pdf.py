"""The sample PDFs on the Desktop disk, written the same on every host.

One three-page document in three copies: plain, tagged, and encrypted with
RC4 under the empty user password.  Its first page has a title, paragraphs
with a link to the last page and one to the web, and a bulleted and a
numbered list; its second a JPEG photograph and a picture of samples under
FlateDecode; its third a line of code and a link back.  An outline names
each page's sections.  The tagged copy marks each block's content and
gives the structure tree that says what each block is.

The text is set here, line by line, in the standard Helvetica fonts, whose
widths place each line and each link's rectangle.  Everything is integer
arithmetic or fixed bytes, so each copy is the same file on every host,
as the disk's other samples are.
"""

from __future__ import annotations

import hashlib
import struct
import zlib

import jpeg_baseline

# The standard fonts' widths of the ASCII characters 32 to 126.
HELVETICA = (
    278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278,
    556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,
    1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
    667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,
    333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
    556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584)
HELVETICA_BOLD = (
    278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278,
    556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333, 584, 584, 584, 611,
    975, 722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778,
    667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 333, 278, 333, 584, 556,
    333, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889, 611, 611,
    611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584)
BULLET = "•"            # WinAnsi 0x95, 350 thousandths wide in both fonts
FONTS = {"F1": ("Helvetica", HELVETICA), "F2": ("Helvetica-Bold", HELVETICA_BOLD),
         "F3": ("Courier", None)}

LEFT, TOP, MEASURE = 72, 720, 468


def _width(text: str, font: str, size: int) -> int:
    """TEXT's width in thousandths of a point."""

    table = FONTS[font][1]
    if table is None:
        return 600 * len(text) * size
    return sum((350 if c == BULLET else table[ord(c) - 32]) for c in text) * size


def _wrap(text: str, font: str, size: int, measure: int = MEASURE) -> list[str]:
    """TEXT broken at spaces into lines no wider than MEASURE points."""

    lines, line = [], ""
    for word in text.split(" "):
        trial = f"{line} {word}" if line else word
        if line and _width(trial, font, size) > measure * 1000:
            lines.append(line)
            line = word
        else:
            line = trial
    return lines + [line]


def _literal(text: str) -> bytes:
    data = text.encode("cp1252")
    return b"(" + data.replace(b"\\", b"\\\\").replace(b"(", b"\\(").replace(b")", b"\\)") + b")"


def _fixed(value: int) -> bytes:
    """A length in thousandths of a point, as a PDF number."""

    whole, part = divmod(value, 1000)
    return b"%d" % whole if part == 0 else (b"%d.%03d" % (whole, part)).rstrip(b"0")


class Page:
    """A page's content, its pictures and its links, set from the top."""

    def __init__(self, tagged: bool) -> None:
        self.tagged = tagged
        self.y = TOP * 1000
        self.ops: list[bytes] = []
        self.blocks: list[tuple[str, list[int]]] = []    # element kind, its MCIDs
        self.links: list[tuple[tuple[int, int, int, int], str]] = []
        self.marks: dict[str, int] = {}                   # a section's top, by name
        self.mcid = 0

    def _marked(self, kind: str, ops: bytes) -> int:
        if not self.tagged:
            self.ops.append(ops)
            return -1
        mcid = self.mcid
        self.mcid += 1
        tag = {"H1": b"H1", "H2": b"H2", "P": b"P", "Lbl": b"Lbl", "LBody": b"LBody",
               "Figure": b"Figure", "Code": b"Code"}[kind]
        self.ops.append(b"/" + tag + b" << /MCID %d >> BDC\n" % mcid + ops + b"EMC\n")
        return mcid

    def _line(self, font: str, size: int, x: int, text: str) -> bytes:
        return (b"BT /" + font.encode() + b" %d Tf " % size + _fixed(x) + b" "
                + _fixed(self.y) + b" Td " + _literal(text) + b" Tj ET\n")

    def heading(self, text: str, level: int, mark: str | None = None) -> None:
        # Sizes a layout without tags also reads as these levels: at least
        # 1.6 and 1.3 times the body's 11 points.
        size = 20 if level == 1 else 15
        self.y -= size * 1000 + (12000 if self.ops else 0)
        if mark:
            self.marks[mark] = (self.y + size * 1000) // 1000
        mcid = self._marked(f"H{level}", self._line("F2", size, LEFT * 1000, text))
        self.blocks.append((f"H{level}", [mcid]))
        self.y -= 6000

    def paragraph(self, text: str, links: tuple[tuple[str, str], ...] = ()) -> None:
        """A paragraph of TEXT in 11 point type, its LINKS each a phrase of
        it and where the phrase goes."""

        size, leading = 11, 14000
        lines = _wrap(text, "F1", size)
        self.y -= 6000
        ops, starts, at = [], [], 0
        for line in lines:
            self.y -= leading
            starts.append((at, self.y))
            ops.append(self._line("F1", size, LEFT * 1000, line))
            at += len(line) + 1
        mcid = self._marked("P", b"".join(ops))
        self.blocks.append(("P", [mcid]))
        for phrase, target in links:
            start = text.index(phrase)
            end = start + len(phrase)
            for (line_at, y), line in zip(starts, lines):
                lo, hi = max(start, line_at), min(end, line_at + len(line))
                if lo >= hi:
                    continue
                x0 = LEFT * 1000 + _width(line[:lo - line_at], "F1", size)
                x1 = LEFT * 1000 + _width(line[:hi - line_at], "F1", size)
                self.links.append(((x0, y - 3000, x1, y + 10000), target))

    def items(self, labels: list[str], texts: list[str], numbering: str) -> None:
        """A list: each item its label, then its text a little in; its
        NUMBERING, Disc or Decimal, is the tagged list's."""

        size = 11
        self.y -= 6000
        self.blocks.append(("L", [numbering]))
        for label, text in zip(labels, texts):
            self.y -= 14000
            label_op = self._line("F1", size, LEFT * 1000, label)
            body_op = self._line("F1", size, LEFT * 1000 + 18000, text)
            if self.tagged:
                self.blocks.append(("LI", [self._marked("Lbl", label_op),
                                           self._marked("LBody", body_op)]))
            else:
                self.ops.append(label_op + body_op)
        self.blocks.append(("END", []))

    def code(self, lines: list[str]) -> None:
        self.y -= 8000
        ops = []
        for line in lines:
            self.y -= 12000
            ops.append(self._line("F3", 10, LEFT * 1000, line))
        mcid = self._marked("Code", b"".join(ops))
        self.blocks.append(("Code", [mcid]))

    def picture(self, name: str, width: int, height: int) -> None:
        self.y -= 12000 + height * 1000
        ops = b"q %d 0 0 %d %d " % (width, height, LEFT) + _fixed(self.y) + b" cm /" + name.encode() + b" Do Q\n"
        mcid = self._marked("Figure", ops)
        self.blocks.append(("Figure", [mcid]))


def _sky() -> list[list[tuple[int, int, int]]]:
    """The disk's sunset, 160 by 100 pixels, without its transparent
    corners: a picture of samples has no alpha here."""

    rows = []
    for y in range(100):
        row = []
        for x in range(160):
            r, g, b = 30 + 200 * y // 70, 40 + 110 * y // 70, 120 - 50 * y // 70
            dx, dy = x - 112, y - 60
            if dx * dx + dy * dy < 16 * 16:
                r, g, b = 255, 214, 96
            hill = 66 + (abs(x % 64 - 32) * 3) // 8 - x // 20
            if y >= hill:
                r, g, b = 26, 70 + (y - hill) * 2, 44
            row.append(tuple(min(255, max(0, v)) for v in (r, g, b)))
        rows.append(row)
    return rows


def _pages(tagged: bool) -> list[Page]:
    first = Page(tagged)
    first.heading("A sample PDF", 1, "top")
    first.paragraph(
        "This document shows how Akashic reads a PDF: its text flows to the width of "
        "the view, a page at a time, as you scroll. A small program wrote it, so it is "
        "the same file on every disk.")
    first.paragraph(
        "The pictures are on the next page, and the last page has some code. Akashic "
        "is described at akashic.example on the web.",
        (("the last page", "#3"), ("akashic.example", "https://akashic.example/")))
    first.heading("Lists", 2, "lists")
    first.items([BULLET] * 3, ["Select a file in File Explorer.",
                               "Press c to see its contents.",
                               "Follow a link to read the page it names."], "Disc")
    first.items(["1.", "2.", "3."], ["Open the document.", "Scroll to the end.",
                                     "Go back to the top."], "Decimal")
    second = Page(tagged)
    second.heading("Pictures", 2, "pictures")
    second.paragraph("A photograph, kept as the JPEG file it was, which a rich terminal "
                     "shows:")
    second.picture("Im1", 240, 150)
    second.paragraph("The same sky, kept as samples that Akashic turns into a QOI file:")
    second.picture("Im2", 200, 125)
    second.paragraph("Both pictures are 160 by 100 pixels.")
    third = Page(tagged)
    third.heading("The end", 2, "end")
    third.paragraph("Some code, in a fixed-pitch font:")
    third.code([": SQUARE  ( n -- n*n )  DUP * ;", "9 SQUARE ."])
    third.paragraph("Back to the first page.", (("the first page", "#1"),))
    return [first, second, third]


# --------------------------------------------------------------------------
# The file
# --------------------------------------------------------------------------

PAD = bytes.fromhex("28bf4e5e4e758a4164004e56fffa01082e2e00b6d0683e802f0ca9fe6453697a")
FILE_ID = hashlib.md5(b"Akashic sample PDF").digest()
OWNER = b"owner"
PERMISSIONS = -4


def _rc4(key: bytes, data: bytes) -> bytes:
    s = list(range(256))
    j = 0
    for i in range(256):
        j = (j + s[i] + key[i % len(key)]) & 255
        s[i], s[j] = s[j], s[i]
    out, i, j = bytearray(), 0, 0
    for byte in data:
        i = (i + 1) & 255
        j = (j + s[i]) & 255
        s[i], s[j] = s[j], s[i]
        out.append(byte ^ s[(s[i] + s[j]) & 255])
    return bytes(out)


def _security() -> tuple[bytes, bytes, bytes]:
    """The standard security handler, revision 3, 128-bit RC4, the empty
    user password: the file key, /O and /U (PDF 32000-1 7.6.3.3)."""

    digest = hashlib.md5((OWNER + PAD)[:32]).digest()
    for _ in range(50):
        digest = hashlib.md5(digest).digest()
    owner = _rc4(digest, PAD)
    for i in range(1, 20):
        owner = _rc4(bytes(b ^ i for b in digest), owner)
    digest = hashlib.md5(PAD + owner + struct.pack("<i", PERMISSIONS) + FILE_ID).digest()
    for _ in range(50):
        digest = hashlib.md5(digest).digest()
    key = digest
    user = _rc4(key, hashlib.md5(PAD + FILE_ID).digest())
    for i in range(1, 20):
        user = _rc4(bytes(b ^ i for b in key), user)
    return key, owner, user + bytes(16)


class Writer:
    """Objects in order, each string and stream encrypted with its object's
    key when the file is."""

    def __init__(self, key: bytes | None) -> None:
        self.key = key
        self.objects: dict[int, bytes] = {}

    def _encrypt(self, num: int, data: bytes) -> bytes:
        if self.key is None:
            return data
        key = hashlib.md5(self.key + struct.pack("<I", num)[:3] + b"\0\0").digest()
        return _rc4(key[:min(len(self.key) + 5, 16)], data)

    def string(self, num: int, text: str) -> bytes:
        data = text.encode("utf-16-be") if any(ord(c) > 126 for c in text) else text.encode()
        if any(ord(c) > 126 for c in text):
            data = b"\xfe\xff" + data
        return b"<" + self._encrypt(num, data).hex().encode() + b">"

    def put(self, num: int, body: bytes) -> None:
        self.objects[num] = body

    def stream(self, num: int, entries: bytes, data: bytes) -> None:
        data = self._encrypt(num, data)
        self.objects[num] = (b"<< /Length %d " % len(data) + entries + b" >>\nstream\n"
                             + data + b"\nendstream")

    def file(self, trailer: bytes) -> bytes:
        out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
        offsets = {}
        for num in sorted(self.objects):
            offsets[num] = len(out)
            out += b"%d 0 obj\n" % num + self.objects[num] + b"\nendobj\n"
        size = max(self.objects) + 1
        xref = len(out)
        out += b"xref\n0 %d\n0000000000 65535 f\r\n" % size
        for num in range(1, size):
            out += (b"%010d 00000 n\r\n" % offsets[num]) if num in offsets else b"0000000000 00000 f\r\n"
        out += b"trailer\n<< /Size %d " % size + trailer + b" >>\nstartxref\n%d\n%%%%EOF\n" % xref
        return bytes(out)


def _document(tagged: bool = False, encrypted: bool = False) -> bytes:
    pages = _pages(tagged)
    key, owner, user = _security() if encrypted else (None, b"", b"")
    w = Writer(key)
    page_nums = [10 + 10 * i for i in range(len(pages))]      # 10, 20, 30; content +1
    fonts = b"<< " + b" ".join(
        b"/" + name.encode() + b" %d 0 R" % (100 + i) for i, name in enumerate(FONTS)) + b" >>"
    for i, (name, (base, _)) in enumerate(FONTS.items()):
        w.put(100 + i, b"<< /Type /Font /Subtype /Type1 /BaseFont /" + base.encode()
              + b" /Encoding /WinAnsiEncoding >>")
    sky = _sky()
    w.stream(110, b"/Type /XObject /Subtype /Image /Width 160 /Height 100 /ColorSpace "
             b"/DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode",
             jpeg_baseline.encode(sky, 85))
    w.stream(111, b"/Type /XObject /Subtype /Image /Width 160 /Height 100 /ColorSpace "
             b"/DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode",
             zlib.compress(bytes(c for row in sky for pixel in row for c in pixel), 9))
    # Links: each its annotation; a page's number "#N" means its first top.
    annotation = 120
    for p, page in enumerate(pages):
        annots = []
        for (x0, y0, x1, y1), target in page.links:
            rect = b"[" + b" ".join(_fixed(v) for v in (x0, y0, x1, y1)) + b"]"
            if target.startswith("#"):
                dest = b"[%d 0 R /XYZ 0 792 0]" % page_nums[int(target[1:]) - 1]
                w.put(annotation, b"<< /Type /Annot /Subtype /Link /Border [0 0 0] /Rect " + rect
                      + b" /Dest " + dest + b" >>")
            else:
                w.put(annotation, b"<< /Type /Annot /Subtype /Link /Border [0 0 0] /Rect " + rect
                      + b" /A << /S /URI /URI " + w.string(annotation, target) + b" >> >>")
            annots.append(b"%d 0 R" % annotation)
            annotation += 1
        resources = b"<< /Font " + fonts + (b" /XObject << /Im1 110 0 R /Im2 111 0 R >>" if p == 1 else b"") + b" >>"
        w.put(page_nums[p], b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources "
              + resources + b" /Contents %d 0 R" % (page_nums[p] + 1)
              + (b" /Annots [" + b" ".join(annots) + b"]" if annots else b"")
              + (b" /StructParents %d" % p if tagged else b"") + b" >>")
        w.stream(page_nums[p] + 1, b"/Filter /FlateDecode", zlib.compress(b"".join(page.ops), 9))
    w.put(2, b"<< /Type /Pages /Kids [" + b" ".join(b"%d 0 R" % n for n in page_nums)
          + b"] /Count %d >>" % len(pages))
    # The outline: the title with its lists under it, then each page's
    # section.
    def item(num: int, title: str, page: int, top: int, links: bytes) -> None:
        w.put(num, b"<< /Title " + w.string(num, title) + links
              + b" /Dest [%d 0 R /XYZ 0 %d 0] >>" % (page_nums[page], top))
    item(201, "A sample PDF", 0, pages[0].marks["top"],
         b" /Parent 200 0 R /Next 202 0 R /First 204 0 R /Last 204 0 R /Count 1")
    item(202, "Pictures", 1, pages[1].marks["pictures"],
         b" /Parent 200 0 R /Prev 201 0 R /Next 203 0 R")
    item(203, "The end", 2, pages[2].marks["end"], b" /Parent 200 0 R /Prev 202 0 R")
    item(204, "Lists", 0, pages[0].marks["lists"], b" /Parent 201 0 R")
    w.put(200, b"<< /Type /Outlines /First 201 0 R /Last 203 0 R /Count 4 >>")
    catalog = [b"/Type /Catalog /Pages 2 0 R /Outlines 200 0 R"]
    if tagged:
        catalog.append(b"/MarkInfo << /Marked true >> /StructTreeRoot 300 0 R")
        _structure(w, pages, page_nums)
    w.put(1, b"<< " + b" ".join(catalog) + b" >>")
    trailer = b"/Root 1 0 R /ID [<%s> <%s>]" % (FILE_ID.hex().encode(), FILE_ID.hex().encode())
    if encrypted:
        w.put(400, b"<< /Filter /Standard /V 2 /R 3 /Length 128 /P %d /O <%s> /U <%s> >>"
              % (PERMISSIONS, owner.hex().encode(), user.hex().encode()))
        trailer += b" /Encrypt 400 0 R"
    return w.file(trailer)


def _structure(w: Writer, pages: list[Page], page_nums: list[int]) -> None:
    """The structure tree: a Document of each page's elements, in order,
    each naming its marked content; a list's items under an L."""

    elements: list[bytes] = []                 # element bodies, numbered from 310
    parent_tree: list[list[int]] = []
    children: list[int] = []
    for p, page in enumerate(pages):
        by_mcid: dict[int, int] = {}
        current_list = None
        for kind, mcids in page.blocks:
            if kind == "L":
                numbering = mcids[0].encode()
                continue
            if kind == "END":
                current_list = None
                continue
            if kind == "LI":
                if current_list is None:
                    current_list = 310 + len(elements)
                    elements.append(b"")              # filled once its items are known
                    children.append(current_list)
                    list_items: list[int] = []
                item = 310 + len(elements)
                elements.append(b"")
                lbl, body = 310 + len(elements), 311 + len(elements)
                elements.append(b"<< /Type /StructElem /S /Lbl /P %d 0 R /K %d /Pg %d 0 R >>"
                                % (item, mcids[0], page_nums[p]))
                elements.append(b"<< /Type /StructElem /S /LBody /P %d 0 R /K %d /Pg %d 0 R >>"
                                % (item, mcids[1], page_nums[p]))
                elements[item - 310] = (b"<< /Type /StructElem /S /LI /P %d 0 R /K [%d 0 R %d 0 R] >>"
                                        % (current_list, lbl, body))
                list_items.append(item)
                by_mcid[mcids[0]], by_mcid[mcids[1]] = lbl, body
                elements[current_list - 310] = (
                    b"<< /Type /StructElem /S /L /P 301 0 R /A << /O /List /ListNumbering /"
                    + numbering + b" >> /K [" + b" ".join(b"%d 0 R" % n for n in list_items)
                    + b"] >>")
                continue
            current_list = None
            num = 310 + len(elements)
            elements.append(b"<< /Type /StructElem /S /%s /P 301 0 R /K %d /Pg %d 0 R >>"
                            % (kind.encode(), mcids[0], page_nums[p]))
            children.append(num)
            by_mcid[mcids[0]] = num
        parent_tree.append([by_mcid[m] for m in sorted(by_mcid)])
    for i, body in enumerate(elements):
        w.put(310 + i, body)
    w.put(300, b"<< /Type /StructTreeRoot /K 301 0 R /ParentTree 302 0 R >>")
    w.put(301, b"<< /Type /StructElem /S /Document /P 300 0 R /K ["
          + b" ".join(b"%d 0 R" % n for n in children) + b"] >>")
    w.put(302, b"<< /Nums [" + b" ".join(
        b"%d [" % p + b" ".join(b"%d 0 R" % n for n in refs) + b"]"
        for p, refs in enumerate(parent_tree)) + b"] >>")


SAMPLES = {
    "sample.pdf": _document(),
    "tagged.pdf": _document(tagged=True),
    "encrypted.pdf": _document(encrypted=True),
}
