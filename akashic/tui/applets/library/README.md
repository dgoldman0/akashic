# Library applet

Status: bounded user-experience probe over the applet-owned Library service.
The executable lens is deliberately single-instance and calls only public
Library APIs; it neither opens Library-private VFS paths nor duplicates the
catalog, index, or mutation authority. Renderer-free service tests do not give
Library a product identity outside Desk.

The current slice can browse and search active, archived, or all records; page
through bounded results; create a managed document; rename its title;
archive/unarchive it; inspect and filter by collections; and inspect retained
managed-content history. A create is protected before first-use provisioning;
after its first owner dispatch, an explicit retry preserves the operation
identity and byte-exact request rather than risking a duplicate document after
an uncertain result.

Pad/projection integration, capture import, export, repair, restore, revision
comparison, and destructive tombstoning remain deferred UI work. The fixed
development arena identity is stable enough to reopen this probe's corpus, but
is not a user/profile identity or a migration policy.

The source is deliberately divided into `model.f`, applet-owned codecs and
formats, `repository.f`, `query.f`, `service.f`,
`projection-adapter.f`, `controller.f`, `view.f`, and the lifecycle/composition
entry `library.f`. There is no top-level Library product package or facade.

See the [full applet notes](../../../../docs/tui/applets/library/library.md).
