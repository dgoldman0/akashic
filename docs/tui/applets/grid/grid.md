# Grid

Grid is Akashic's small spreadsheet and CSV workspace. It runs standalone with
`GRID-RUN` or inside Desk through `GRID-ENTRY`.

**Provider:** `akashic-tui-grid`

## Ownership and exact targeting

Grid owns workbook, sheet, cell, range, formula, recalculation, and tabular
import/export semantics. The current implementation has one bounded worksheet
backed by `/grid.csv`; named native workbooks and durable workbook identity are
later Grid work, not Library or Desk state. Grid does not own Library metadata,
corpus indexing, scheduling, provenance graphs, or a general database.

The selected cell is local UI state and may be exposed only as an observation.
It is not a consequential mutation target. A general or Agent-visible edit
must name the exact workbook, sheet, coordinate/range, complete value/formula
operands, and expected domain revision. The current
`grid.cell.set-selected` compatibility surface depends on hidden selection and
must not be widened; Gate 10A replaces it with exact-target operations. Gate 1
changes no capability or runtime behavior.

An eventual “Collect in Library” action copies one explicit admitted UTF-8
CSV/text export into a new immutable Library capture. It neither transfers the
Grid workbook to Library nor lets Library become a spreadsheet owner. Opening
that capture as a workbook would be an explicit Grid import with a new
Grid-owned identity.

## Worksheet

The current worksheet has 64 rows and 16 columns (`A1:P64`). Only visible rows
and columns are painted. Headers remain fixed while selection movement adjusts
the viewport, so the same widget works full-screen and in a compact Desk tile.

Cells retain their source text and a cached integer result. The formula bar
always shows the selected cell's source while formula cells display their
result in the sheet. Errors render as `#ERR` without preventing unrelated cells
from evaluating.

## Formulas

Formulas begin with `=` and currently support:

- signed integer literals;
- A1 cell references;
- `+`, `-`, `*`, and `/` with normal precedence;
- parentheses;
- inclusive ranges through `SUM(A1:B4)`;
- recursive references and cycle detection.

Division by zero, malformed expressions, invalid references, and cycles produce
`#ERR`. Dependency walks are bounded to 20 cells. A cycle and an acyclic chain
that exceeds that bound are tracked as distinct internal errors, and neither
can write beyond the evaluator stacks. Recalculation is scalar and
deterministic. It clears evaluation marks, then evaluates the used rectangle
while resolving referenced cells on demand.

## CSV Persistence

`/grid.csv` is both the native first-slice document and the interchange format.
The reader handles quoted fields, doubled quotes, commas, LF/CRLF records,
quoted line breaks, and empty cells. Import is intentionally strict: a sheet
may contain at most 64 rows and 16 columns, decoded fields may contain at most
40 bytes, quotes may only open at the start of a field, and only a delimiter,
record ending, or end-of-file may follow a closing quote. Lone CR bytes,
unclosed quotes, junk after a closing quote, invalid UTF-8, and over-limit data
are rejected rather than clipped or reinterpreted.

Reload first recovers any interrupted replacement, checks the file size before
reading, reads exactly the reported number of bytes, and validates the entire
CSV before clearing the current model. A failed reload therefore keeps the
current sheet and its dirty state. It also blocks saves, preventing a malformed
or uncertain external source from being overwritten until a clean recovery and
reload succeeds.

The exact-read path owns its file descriptor and previous VFS selector as
separate cleanup stages. Each ownership marker is cleared before its void
cleanup operation is called, so an operation that takes effect and then throws
cannot be retried. Close and selector restoration are caught independently,
and restoration is attempted even after a close fault. A cleanup fault becomes
a load I/O failure: CSV validation and model publication do not run, the sheet
and dirty state are preserved, and saves remain source-blocked until a clean
reload.

Edits mark the sheet unsaved and repaint immediately. `Ctrl+S` serializes into a
bounded buffer and uses checked staged replacement: the candidate is written,
read back, synced, and published without truncating the live file first.
Failures known to have rolled back leave the sheet dirty and immediately
retryable; only an ambiguous/corrupt replacement state blocks another save
until recovery and reload succeed.
`Ctrl+R` confirms before discarding unsaved edits, reloads, and recalculates.
Closing a dirty Grid also requires confirmation through the app lifecycle close
contract; the quit action itself only requests closure, so it cannot prompt a
second time.

## Keys

| Key | Action |
|---|---|
| Arrow keys | Move one cell |
| Tab / Shift+Tab | Move right or left |
| Page Up / Page Down | Move one visible page |
| Home / End | First or last used column |
| Enter or F2 | Edit the selected cell |
| Printable character | Replace the selected cell and begin editing |
| Delete | Clear the selected cell |
| Ctrl+G | Go to an A1 cell name |
| F9 | Recalculate |
| Ctrl+S | Save `/grid.csv` |
| Ctrl+R | Reload `/grid.csv` |
| Ctrl+Q | Quit standalone Grid |

## Public Words

| Word | Stack | Purpose |
|---|---|---|
| `GRID-ENTRY` | `( desc -- )` | Fill an application descriptor for Desk |
| `GRID-RUN` | `( -- )` | Run Grid in the shared app shell |

## Verification

`python3 local_testing/akashic_tui.py smoke --profile grid` edits `D2` to
`=B2*C2+5`, asserts the result `41`, asserts that `SUM(D2:D3)` updates to `91`,
saves and reloads the sheet, verifies quoted CSV and formula source in live
MP64FS bytes, reports a self-reference as `#ERR`, recovers after clearing it,
and checks the results after terminal resize.

`python3 local_testing/akashic_tui.py smoke --profile grid-eval` checks the
dependency-stack boundary, a maximum-depth chain, an over-depth chain, cycle
classification, and recovery on recalculation.

`python3 local_testing/akashic_tui.py smoke --profile grid-contracts` exercises
strict CSV acceptance and rejection at every shape bound, exact and oversized
reads, short-read preservation, source blocking, failed-sync rollback,
retry-after-rollback, replacement-artifact cleanup, and close-callback
registration in a live MP64 image. It injects after-effect throws from both
descriptor close and VFS-selector restoration and verifies single-attempt
cleanup, descriptor free-list integrity, selector restoration, and preservation
of the dirty model under both faults.

## Deliberate Next Steps

The larger Grid design still includes exact-target capabilities, named
open/save-as workbooks, typed values, dependency-directed incremental
recalculation, more aggregate functions, range selection and undo, multiple
sheets, row/column operations, sorting/filtering, charts, and a versioned
workbook format. CSV remains the portable interchange boundary as those
arrive.
