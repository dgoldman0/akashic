# UIDL Root Facts

**Provider:** `akashic-tui-uidl-root-facts`
**Prefix:** `URF-` (public), `_URF-` (private)

A document's snapshot captures its roots: its menus, each collection,
data-graphics, status-field and field root, and the dialog it shows. `URF`
records, for one root, what its capture read, so that a projection can tell
whether the root could have changed without capturing it again. Two records
of one root that are equal byte for byte describe captures of the same state.

The record keeps the newest revision among the UIDL elements the capture
reads, the revision of the widget it shows and of the model or view behind
that widget, the context it lays out against, and the geometry it was
captured at. UIDL's element revisions come from one count every document
shares (`UIDL-REVISION`), so an element changed after a capture carries a
revision newer than any that capture read, and the newest of them moves.
Widgets count their own changes (`WDG-REVISION`). The geometry is compared
directly, since the regions of mounted widgets carry no counter.

Each `URF-*` family word fills one record from the descriptor its snapshot
module wrote, in the document's own context and before that context changes
again. It reads UIDL's and UIDL-TUI's records directly, as UIDL-TUI does,
because each guarded public word costs a guard. A root whose element or
widget can no longer be found records the stamp `URF-UNKNOWN`, which no
capture can match, so that the root counts as changed. The caller fills each
record's document token afterwards.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `URF-MENUS` | `( records-a count record -- )` | The document's menus, as one root, from its UMSN records |
| `URF-COLLECTION` | `( descriptor record -- )` | A collection root, direct or mounted |
| `URF-DATA-GRAPHICS` | `( descriptor record -- )` | A mounted data-graphics root |
| `URF-STATUS-FIELD` | `( descriptor record -- )` | A status field |
| `URF-FIELD` | `( descriptor record -- )` | A mounted field, or the document's overlay prompt |
| `URF-DIALOG` | `( descriptor record -- )` | The dialog widget or dialog element the document shows |
| `URF-SAME?` | `( record-a record-b -- flag )` | Equal byte for byte, and neither unknown |
| `URF-ROOT?` | `( record family source index generation key -- flag )` | Whether a record names that root, whatever its document |

`URF-SIZE` is 152 and `URF-IDENTITY-SIZE` 48. The families are
`URF-F-MENUS=1`, `URF-F-COLLECTION=2`, `URF-F-DATA-GRAPHICS=3`,
`URF-F-STATUS-FIELD=4`, `URF-F-FIELD=5` and `URF-F-DIALOG=6`.

## Record schema

Each field is one cell. The first six name the root, and match the keys the
screen producer gives the items it lowers from it.

| Offset | Field | Accessor |
|---:|---|---|
| 0 | Document token | `URF.TOKEN` |
| 8 | Family | `URF.FAMILY` |
| 16 | Source kind, from the descriptor | `URF.SOURCE` |
| 24 | Source index; 0 for menus and dialogs | `URF.INDEX` |
| 32 | Source generation; 0 for menus and dialogs | `URF.GENERATION` |
| 40 | Root key; 0 for menus; the dialog's key for a dialog | `URF.KEY` |
| 48 | Newest element revision the capture reads | `URF.STAMP` |
| 56 | The widget's revision | `URF.WIDGET-REV` |
| 64 | The bound model's, the shown view's, or the dialog elements' count | `URF.MODEL-REV` |
| 72 | The screen's size, for an overlay prompt or a dialog | `URF.CONTEXT` |
| 80–104 | Captured row, column, height and width | `URF.ROW` … `URF.WIDTH` |
| 112–136 | Captured clip | `URF.CLIP-ROW` … `URF.CLIP-WIDTH` |
| 144 | Captured paint order | `URF.Z` |

## What each family reads

- **Menus.** The elements of the document's menu records and their
  ancestors. Opening a menu, moving focus into or out of one, and laying one
  out each count a change to the elements they touch.
- **Collections.** A direct root reads its element, its ancestors and its
  contents, such as a tab set's tabs, with the widget the element hosts, or
  for a media element the view it shows. A mounted root reads the widget its
  relation mounts and the element it is mounted under.
- **Data graphics.** The mounted widget and the element it is mounted
  under. An application changes a graphic by binding a new model, which
  counts a change to the widget.
- **Status fields.** The label, the status element it sits in, and their
  ancestors.
- **Fields.** A mounted field reads its widget, the model the widget is
  bound to, whose revision the application issues, and the element it is
  mounted under. The overlay field reads the prompt the document shows, by
  instance, which counts its input's changes, and the screen.
- **Dialogs.** A dialog widget the document shows, by instance, and the
  screen. A dialog element reads itself, its contents and its ancestors, the
  count of dialog-element changes, which every document shares, and the
  screen.

Pictures are not snapshot roots; they are described afresh for each draw
(`UPICSN`), and carry no facts yet.

## Users

`RUHA-ROOT-FACTS@` in `tui/rich-terminal/uidl-hybrid-adapter.f` records the
facts of every root of a published snapshot. With the shadow check on, the
screen producer keeps them beside each bank it builds and judges them in its
DELTA comparison (FRAMES-FOLLOW-CHANGE, part 9a.1).

## Tests

`local_testing/test_rich_root_facts.py` records the facts of a real textarea
document's snapshot, holds them across a draw that changed nothing, sees the
widget's revision move with new text and the stamp move with a change counted
on the element, and runs the producer's judge on seeded banks.
