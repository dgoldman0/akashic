# Held files

`akashic/utils/fs/held-files.f` records which file keeps each document that
Desk hosts for one applet and lends to others. Daybook's document is the one
such document today: Daybook's owner keeps it in a file of its home, and Pad
edits it through the owner's service. Desk fills a table here from what each
owner says of its own file and lends the table under the service id
`org.akashic.fs.held`. An applet about to open or write a file by its path asks
the table first. A held file is reached through its owner's service, by the
document's identity, and is never written directly, so no applet spells
another applet's file. The places design gives the reason:
[places.md](places.md), "Who may write a file".

```forth
REQUIRE utils/fs/held-files.f
```

## Entries

An entry is a file and the service that lends the document it keeps. The file
is named by its place's declared name and its path. A declared name is the same
in every set the place is granted to, so a table that Desk fills through its
own place for a folder answers an applet that asks through its own place for
the same folder. A path starts at the place's folder with its slash, as the
`PLACE-` words take it. Entries are heap records, so their number follows
need.

## The words

```forth
HELD-SIZE                                   \ bytes of a table
HELD-INIT    ( table -- )
HELD-HOLD    ( path-a path-u place svc-a svc-u table -- ior )
HELD-RELEASE ( svc-a svc-u table -- )
HELD-CLEAR   ( table -- )
HELD-HOLDER  ( path-a path-u place table -- svc-a svc-u | 0 0 )
HELD-FILE    ( svc-a svc-u table -- path-a path-u name-a name-u | 0 0 0 0 )
```

`HELD-HOLD` records that the file at PATH in PLACE keeps the document the
service SVC lends, and refuses a missing place, path or service with
`VFS-E-INVALID`. `HELD-RELEASE` forgets every file of one service, and
`HELD-CLEAR` every file. `HELD-HOLDER` answers the service whose document a
file keeps, or `0 0`. `HELD-FILE` answers the file of a service's document: its
path and its place's name, which `PLSET-FIND` turns into a place of the asking
holder's own set.

## Who fills it

Desk records Daybook's file when it hosts Daybook's owner, from the owner's
`SDOC-PATH$` in the home Desk gives it, and forgets it when the owner is
deactivated. The document is lent only once the record exists. Pad asks the
table before it opens or saves a file by its path. The file that keeps the
document its session edits opens the shared document. A file that keeps a
document Pad has no session for is refused, since only that document's owner
writes it. Pad also names the shared tab by the file in its place of Pad's own
set, so the tab's saves reach the document again.

## Tests

`local_testing/test_held_files.py` fills a table through one set's place and
asks it through another set's place for the same folder. It also checks
release, clearing and refused holds. `pad-resource-contracts` drives Pad
against a table that a stand-in for Desk fills the same way.
