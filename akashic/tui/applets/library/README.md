# Library applet

Status: bounded user-experience probe over the implemented headless Library
owner. The standalone applet is deliberately single-instance and calls only
public Library APIs; it neither opens Library-private VFS paths nor duplicates
the catalog, index, or mutation authority.

The current slice can browse and search active, archived, or all records; page
through bounded results; create a managed document; rename its title;
archive/unarchive it; inspect and filter by collections; and inspect retained
managed-content history. A create is protected before first-use provisioning;
after its first owner dispatch, an explicit retry preserves the operation
identity and byte-exact request rather than risking a duplicate document after
an uncertain result.

Pad/projection integration, capture import, export, repair, restore, revision
comparison, and destructive tombstoning remain deferred. The fixed development
arena identity is stable enough to reopen this probe's corpus, but is not a
user/profile identity or a migration policy. This applet is evidence-gathering
work ahead of the ordered gate, not a claim that Gate 5 is complete.

See the [full applet notes](../../../../docs/tui/applets/library/library.md).
