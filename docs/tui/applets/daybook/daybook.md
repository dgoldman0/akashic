# Daybook

Daybook is Akashic's daily planner for dated events, tasks, and notes. It runs
standalone through `DAYBOOK-RUN` or as an `APP-DESC` inside Desk through
`DAYBOOK-ENTRY`.

**Provider:** `akashic-tui-daybook`

## Ownership and exact targeting

Daybook owns human temporal entries and their planner semantics: dated tasks,
events, short notes, completion, and the later explicitly gated due/deferral,
recurrence, reminder, linked-resource, and visible automation records. It does
not own Library documents or corpus search, Streams acquisition timing, Grid
workbooks, Agent run history, every timestamp in the system, or a universal
backlink/daily-note tree. Long-form text belongs in a Library document edited
through Pad and may later be linked by an exact qualified locator.

Desk currently hosts the Daybook document service and its activation-local
registry/bus lifecycle. Daybook remains the semantic owner; hosting does not
make `/daybook.md` Desk data. Pad is an editing lens over that owner and never
receives Daybook authority merely by opening the text.

The selected day and agenda row are local UI conveniences. A consequential
typed or Agent-visible mutation must name the Daybook resource, exact item or
create precondition, admitted date/time/kind/text operands, and expected domain
revision. It may not infer the date or item from current selection. The landed
`daybook.task.capture` compatibility path still supplies the selected UI date
implicitly; it is therefore not the model for a general mutation and must not
be widened. Gate 9A replaces that surface after exact schemas are qualified;
Gate 1 changes no capability or runtime behavior.

## Current User Model

The default view combines a month calendar with the selected day's agenda.
When the app is too narrow for both panes, the agenda takes the full tile. The
agenda groups entries into Schedule, Tasks, and Notes and keeps one entry
selected for keyboard actions.

The agenda below its date header is a canonical list in sections (see
[list](../../widgets/list.md)): a heading for each kind, then that kind's
entries, with an entry's text and, for an event, its time as a second column.
Tasks have check boxes. Checking one, whether by Space, Enter, a press on its
CELL box, or a rich renderer's `CHECK`, marks it done or not done and saves, as
the Toggle Task action does. A day with no entries shows a line saying so
instead. A small row map, rebuilt when the date or entries change, turns the
list's rows into headings and entries; the list captures it as a `SECTIONS`
item view, so a rich terminal draws the headings, rows and check boxes itself.

The ordinary wide-layout boundary is exactly 72 columns by 14 rows. Daybook
owns only its ordinary responsive calendar/agenda widget, draw, and event
lifecycle. Its wide calendar is a canonical `TGRID` child: Daybook fills a
renderer-neutral `TEXT_GRID` model, and the widget uses that same model for CELL
drawing, keyboard selection, and generic collection observation. Daybook does
not register a semantic provider, expose a capture callback, call a terminal
API, or maintain rich-terminal revisions.

The calendar root is 25 by 10 physical cells with an 8-by-7 logical viewport:
one spanning month/year header, seven weekday headers, and up to 31 date cells.
The selected date is the primary item and the cached current date carries the
`CURRENT` state. Two exact 3,000-byte model banks make month updates atomic;
the inactive bank is built and deeply validated before the widget borrows it.
When the layout is narrow the parent omits the child draw and the agenda uses
the full tile. Generic mounted-widget discovery therefore sees precisely the
ordinary wide calendar lifecycle, without a parallel applet description.

Quick capture uses the shared non-blocking prompt widget. Creating or changing
an entry synchronizes its source immediately. A failed save leaves Daybook
visibly dirty. Closing a dirty Daybook is fail-closed and requires typing
`DISCARD`; a second close request is issued by the confirmation, so Desk does
not prompt the child twice.

## Automations

Inside Desk, F4 switches the body between the calendar and the automations
Desk runs for Daybook (see [automations](automations.md)): schedules, each
a reminder or an Agent run, and the items they made. The automations view
is a canonical list in sections, as the agenda is:

| Section | Holds |
|---|---|
| NEEDS REVIEW | Reminder firings and Agent runs awaiting review, newest first: `fired`, `missed`, or how a run ended and why, with when it was due |
| IN PROGRESS | Agent runs handed to Desk and not yet over: `waiting` or `running`, with when it was due |
| ACTIVE | Enabled schedules, soonest first, with the next time each fires in its zone |
| PAUSED | Paused schedules |
| COMPLETED | Series with nothing left to fire |
| ARCHIVED | Archived schedules, shown on request |

An Agent run's schedule says so, and says when it is not approved, for
example `Agent run, not approved, next 2026-10-12 09:00`. A run that
completed needs no review; one that ended any other way shows its outcome
and reason in full, such as `stopped for review: asked to use a tool`.

Enter on a schedule opens its details: a card for each fact, its title,
when it runs and runs next, and for an Agent run whether it is approved,
the model it names with its choices, its provider, its limits and its
prompt, exactly as Desk's approval says them; then a card for each of its
firings or runs, newest first, with how a run ended and its summary. R, Y
and X act on the Agent run there as they do on its row, the details follow
Desk as it fires and answers, and Escape returns to the list. A menu
action on the details closes them and acts on the schedule.

Enter or Space on a firing or a run marks it reviewed. P pauses or
resumes the selected schedule, A archives it or brings it back, and H shows
or hides archived schedules. Delete asks to type `DELETE` first, because a
deleted schedule is gone for good; an Agent run's items stay as short
records. For an Agent run, R runs it now, through Desk; Y asks Desk's user
to approve it, and the status line then says where that stands, as Desk
answers; and X cancels its run in progress. Escape returns to the
calendar. The Automations menu offers the same actions.

Ctrl+N in the automations view makes a new reminder in three prompts:

1. When, and the title: `HH:MM title` for the next time the clock reads
   HH:MM in the reminder's zone, or `YYYY-MM-DD HH:MM title` for a date.
2. How it repeats: `once` (or nothing), `daily`, `weekdays` (Monday to
   Friday), `weekly`, `monthly` or `yearly`, each counted from the start.
3. Its zone, as a POSIX TZ string such as `EST5EDT,M3.2.0,M11.1.0`.
   Nothing means the default zone, which the prompt names.

A wrong answer says why and asks again. Each new reminder draws a fresh
create key, so a submit that arrives twice still makes one reminder.
Automations, Default Zone sets the zone new automations start with; it
starts as `UTC0`.

Ctrl+G, anywhere in Daybook inside Desk, makes a new Agent run. It first
asks Desk for the models the Agent offers, and says so when there are
none. It then takes the reminder's three prompts, and after them:

4. A page for the model it uses, listed by name, then a page for each
   choice that model offers: its effort, its tier, where the first is the
   model's default, and how much it says, where the first is the model's
   default. Up and Down move, Enter chooses, and Escape leaves the new
   Agent run.
5. The minutes it may run, and the bytes of its reply it keeps: whole
   numbers above zero.
6. A page for its prompt, an editor of as many lines as it needs, whose
   room grows as it is typed. Ctrl+C, Ctrl+X and Ctrl+V copy, cut and
   paste. Ctrl+S creates the Agent run. Escape leaves it, but with a prompt
   typed the first Escape only asks, and any other key takes that back.

What the run may send the model is exactly its prompt. Once it is made,
Desk asks its user to approve the run as made, and the status line says
where that stands. A run Desk has not approved never runs. Daybook does not
close while a typed prompt would be lost.

The rows name records by position, so every action first checks that the
reminders have not changed since the rows were built. A firing that arrives
in between makes the action do nothing and say so, rather than act on
something the user did not see. Each action names the revision, or for a
review the last firing, that its row showed. Daybook rebuilds the rows on
its tick whenever Desk's runner or another action changes the reminders.
Daybook ticks while it has nothing to draw, so the view and the status line
follow what Desk does while the view sits idle.

Run outside Desk, Daybook has no reminder service, and the view says that
reminders run inside Desk. A clock that is not set, or a reminder file Desk
cannot use, shows as a note above the list.

## Standalone and Shared Modes

Standalone Daybook remains the control case: an instance with no runtime
endpoint reads `/daybook.md` directly and publishes with its private `VREPL`
staged replacement. An attached endpoint which fails to supply Context is
treated as broken runtime wiring and blocks instead of selecting this control
path. The genuine standalone behavior and its recovery contracts are
otherwise unchanged.

Inside Desk, Daybook instead discovers the active Context, resource registry,
request bus, and `org.akashic.resource.daybook` through its endpoint. That
named service lends an owner-held neutral `ROFFER`; the common
`resource-session.f` client validates it, copies its exact RID and owning pool,
and does not retain the offer pointer. It then retains the Desk-hosted owner and
attaches an activation-local exact `RREF`/`LBIND`. Loads request
`resource.snapshot`; saves request
`resource.replace` at the binding's exact revision and advances the binding only
after a successful owner commit. Daybook never receives the owner's VFS path,
replacement object, or private buffer.

The owner also exposes portable `resource.describe` metadata. It reports the
Daybook semantic RID but `domain_revision=0`: current component revision is an
activation-local concurrency guard, and Daybook has no retained domain-history
ledger from which it could honestly mint an exact qualified locator.

The session retains and revalidates the owner before borrowing its descriptor.
Explicit refresh retries only a bounded exact-reference race; repeated
contention is reported as transient stale state, while missing or invalid
services remain structural and block rather than being confused with stale
status codes.

If the owner reports a successful commit but the local binding cannot advance,
the commit remains authoritative: Daybook does not claim the save failed or
roll back a captured entry that is already durable. It clears the unusable
binding, marks the source blocked, and requires an explicit reload before any
later write.

If another lens commits first, save is rejected as stale, the edited model
stays dirty, and Daybook asks the user to reload before saving. Reload is the
explicit refresh boundary: it resolves the current resource reference,
reattaches the lens, and then snapshots. If a valid Desk Context is present but
any shared-resource service or attachment is unavailable, Daybook enters
`Shared resource blocked` mode and will not silently fall back to writing
`/daybook.md`.

`Edit Source in Pad` (Ctrl+O) emits the semantic resource URI from the current
binding in shared mode; standalone mode continues to emit `vfs:/daybook.md`.
Task capture persists through the same owner. Because general derived authority
does not yet exist, its nested replace is an explicitly approved, bounded
implementation hop inside the already-authorized `daybook.task.capture`
handler—not a reusable delegation mechanism.

This experiment does not make the VFS path globally exclusive. Trusted code
and File Explorer can still write `/daybook.md` directly, outside the owner's
revision sequence. The Daybook/Pad path therefore demonstrates coordinated
semantic lenses by convention, not system-wide mediation or Practice
ownership. The concrete owner now resides in the Daybook domain; Gate 2C did
not change this behavior.

## Durable Format

Daybook recognizes these UTF-8 Markdown records:

```markdown
# Daybook

- 2026-07-10 09:30 | Project review
- [ ] 2026-07-10 | Send the revised draft
- [x] 2026-07-10 | Morning walk
> 2026-07-10 | Keep this note legible outside the app
```

Import is deliberately strict and lossless. A source must contain one canonical
`# Daybook` heading before its records; blank lines and the three record forms
shown above are the only accepted lines. Dates and event times must be valid,
`[x]` is lowercase, record text is valid single-line UTF-8 of at most 120 bytes,
and the file may contain at most 96 records. Files over 32 KiB are rejected
before any read. Unknown or malformed lines, short reads, overlong text, and
capacity overflow reject the complete import rather than dropping or
truncating data.

Load uses an exact read and validates the complete buffer in a non-mutating
first pass. Only a successful second pass replaces the current model; every
failure preserves both the entries and dirty state. Reloading a dirty model
requires typing `RELOAD`, and a failed confirmed reload still preserves it.
Any load or recovery failure also blocks subsequent saves, preventing an edit
from overwriting the unaccepted external source. The status bar reports
`Source blocked`; saving is enabled again only after a clean reload (or a
confirmed reload when the in-memory model is dirty).

The exact-read path treats its file descriptor and previous VFS selector as
separate owned cleanup stages. It relinquishes each ownership marker before
calling the corresponding void cleanup operation, so a cleanup that completes
and then throws is never retried. Close and selector restoration are caught
independently, and restoration is still attempted when close fails. Any such
cleanup fault is normalized to a load I/O failure: parsing and publication do
not run, entries and dirty state remain unchanged, and the source becomes
blocked until a clean reload succeeds.

Save uses the generic VFS staged-replacement protocol. The candidate is written
and read back exactly, synchronized, and published through a checksummed
rollback marker and same-directory backup. Activation and every load recover a
pending replacement before opening `/daybook.md`; the live target is never
truncated in place. A committed target whose backup cleanup remains is treated
as saved, while ambiguous or corrupt recovery state fails closed.

## Keys

| Key | Action |
|---|---|
| Left / Right | Previous or next day |
| Page Up / Page Down | Previous or next week |
| Up / Down | Select an agenda entry, past headings |
| Space / Enter | Toggle the selected task |
| Home or `t` | Return to today |
| Ctrl+N | Capture a task |
| Ctrl+E | Capture an event as `HH:MM title` |
| Ctrl+Shift+N | Capture a note |
| Delete | Delete the selected entry |
| Ctrl+S | Save |
| Ctrl+R | Reload the current Daybook source |
| Ctrl+O | Edit the source in Pad (semantic resource in Desk) |
| Ctrl+Q | Quit standalone Daybook |
| F4 | Switch between the calendar and the automations (in Desk) |
| Ctrl+N | Make a new reminder (automations) |
| Ctrl+G | Make a new Agent run (in Desk) |
| Ctrl+S | Create the new Agent run (its prompt) |
| Enter | Open the selected schedule's details, or mark the selected firing or run reviewed (automations) |
| Space | Mark the selected firing or run reviewed (automations) |
| P | Pause or resume the selected schedule (automations) |
| A | Archive the selected schedule, or bring it back (automations) |
| H | Show or hide archived schedules (automations) |
| R | Run the selected Agent run now (automations) |
| Y | Ask Desk to approve the selected Agent run (automations) |
| X | Cancel the selected Agent run in progress (automations) |
| Delete | Delete the selected schedule after typing `DELETE` (automations) |
| Escape | Return to the calendar (automations) |

## Public Words

| Word | Stack | Purpose |
|---|---|---|
| `DAYBOOK-ENTRY` | `( desc -- )` | Fill an application descriptor for Desk |
| `DAYBOOK-RUN` | `( -- )` | Run Daybook in the shared app shell |

## Verification

`python3 local_testing/akashic_tui.py smoke --profile daybook` boots a seeded
disk, captures a task through the prompt, completes it, verifies the exact
Markdown record in live MP64FS state, resizes the terminal, and writes text,
cell, raw-terminal, and PNG captures under `local_testing/out/`.

`python3 local_testing/akashic_tui.py smoke --profile daybook-contracts` adds
deterministic checks for atomic strict import, unknown/malformed lines, the
96-record and 120-byte limits, pre-read oversize rejection, injected short
reads, staged persistence, interrupted-publication recovery, artifact cleanup,
corrupt-marker refusal, blocked-source overwrite prevention, dirty-state
preservation, and close negotiation. It also injects after-effect throws from
descriptor close and VFS-selector restoration, proving that both cleanup
stages are attempted exactly once, the descriptor free list remains intact,
the previous selector is restored, and no failed load publishes a model.

`python3 local_testing/test_daybook_shared_lens.py` supplies the four required
Desk services to two Daybook applet instances. It verifies snapshot/replace,
revision advancement, stale overwrite refusal, reload/reattach, semantic source
URI emission, nested task-capture persistence, and fail-closed behavior when a
valid Context exposes an incomplete shared-resource service set or an attached
endpoint loses its Context service.

`python3 local_testing/test_daybook_reminders_view.py` checks the reminders
view's rows: sections, order, titles, details and keys, every action with its
refusals for headings, rows out of range and rows older than the reminders,
missed firings, and the notes for no service, an unset clock and a damaged
file. It also checks the create prompts' answers, every repeat word, the
next-such-time rule, zones and the default zone, and a create submitted
twice.

The `desktop-daybook-reminders` smoke profile works reminders through
ordinary keys inside Desk, checking each change in the live reminder file:

- it reviews a firing, and pauses and resumes a daily reminder;
- it creates a reminder through the prompts and sees it fire on time;
- it sets the clock back over that firing and sees nothing fire again;
- it sets the clock two days ahead and sees one missed item;
- it boots a second machine from the disk as it then is, and finds the
  reminder's next firing and its missed item with nothing written at boot.

On the rich terminal, Desk with Daybook alone
(`physical_desktop_acceptance.py --applet daybook`) ends its journey by
waiting for a reminder made at boot and requiring Desk's notice in the
physically presented frame, rich and CELL.

## Deliberate Next Steps

The broader ecosystem design still calls for exact item identity, project/tag
fields, edit/reschedule/deferral, bounded planner search, due times,
qualified resource links, and later visible typed automations beyond
reminders. It does not authorize corpus-wide backlinks or a daily-note
document tree inside Daybook. Those features should build on this strict
calendar, prompt, recovery, VFS, and responsive-layout path rather than
changing the plain-text source-of-truth principle prematurely.
