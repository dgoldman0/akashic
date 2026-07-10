# Grid

Grid is Akashic's small spreadsheet and CSV workspace. It runs standalone with
`GRID-RUN` or inside Desk through `GRID-ENTRY`.

**Provider:** `akashic-tui-grid`

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
`#ERR`. Recalculation is scalar and deterministic. It clears evaluation marks,
then evaluates the used rectangle while resolving referenced cells on demand.

## CSV Persistence

`/grid.csv` is both the native first-slice document and the interchange format.
The reader handles quoted fields, doubled quotes, commas, LF/CRLF records, and
empty cells. The writer quotes fields when required and preserves formula
source rather than serializing cached values.

Edits mark the sheet unsaved and repaint immediately. `Ctrl+S` performs an exact
truncate/write/sync; `Ctrl+R` reloads and recalculates the CSV file.

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

## Deliberate Next Steps

The larger Grid design still includes sparse pages, typed values, dependency-
directed incremental recalculation, more aggregate functions, ranges and undo,
multiple sheets, row/column operations, sorting/filtering, charts, and a
versioned workbook format. CSV remains the portable boundary as those arrive.
