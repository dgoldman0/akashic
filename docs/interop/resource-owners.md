# Resource owner directory

`akashic/interop/resource-owners.f` maps the owner id a
[qualified locator](qualified-locator.md) names (`QLOC-OWNER$`) to what
attaches a locator through that owner: its acquisition root and attach
word. The attach word has
[`RACQ-ATTACH`](resource-acquisition.md)'s effect,
`( locator root context rreg binding result -- status )`.

The component instance that runs an owner publishes it while it runs and
withdraws it as it stops. An owner id has one publication at a time. A
publication names its instance by id and generation, so a later instance
never replaces or withdraws an earlier one's. Only an instance the
component registry holds may publish. A publication whose instance the
registry no longer holds is dropped when it is next looked up, so an
owner that stopped without withdrawing is never reached.

An optional policy decides who may publish what:
`( owner-a owner-u instance context -- allowed? )`. Desk's policy lets
only the trusted built-in component that runs an owner publish it:
`org.akashic.library` only from `org.akashic.library.applet`.

The directory borrows each root, grows as owners publish, and is
caller-owned and caller-serialized.

| Word | Effect |
|---|---|
| `ROWN-SIZE` | `( -- u )` |
| `ROWN-INIT` | `( registry directory -- )` |
| `ROWN-FREE` | `( directory -- )` |
| `ROWN-POLICY!` | `( xt context directory -- )` |
| `ROWN-COUNT@` | `( directory -- n )` |
| `ROWN-PUBLISH` | `( owner-a owner-u root attach-xt instance directory -- status )` |
| `ROWN-WITHDRAW` | `( owner-a owner-u instance directory -- status )` |
| `ROWN-FIND` | `( owner-a owner-u directory -- entry\|0 )` |
| `ROWN-E.ROOT` `ROWN-E.ATTACH-XT` | `( entry -- a )` |
| `ROWN-ATTACH` | `( locator context rreg binding result directory -- status )` |

Statuses are `ROWN-S-OK`, `-INVALID`, `-TAKEN` (another instance publishes
that owner), `-NOT-FOUND`, `-NOMEM` and `-REFUSED` (the policy does not
allow it). An owner id is 1 to `QLOC-OWNER-MAX` bytes, as a locator can
carry. `ROWN-ATTACH` answers `RACQ-S-UNAVAILABLE` when no instance
publishes the owner the locator names, and `RACQ-S-INVALID` for a value
that is not a locator; otherwise it answers what the owner's attach word
answers.

## Users

Desk keeps one directory and lends it as the service
`org.akashic.runtime.resource-owners`, only to Library. Library publishes
its projection root there while its service is open inside Desk, and
withdraws it before its service closes. Desk's schedule broker attaches a
scheduled run's document through it, and Desk starts the owning applet
minimized when it is not running.

## Qualification

`local_testing/test_resource_owners.py` (native executor) checks
publishing, finding and withdrawing; what a publication must carry; that
one instance holds an owner and a later instance with the same id cannot
take it over; the policy; an owner whose instance is gone; growth past the
table's first room; and attaching through the published owner.
