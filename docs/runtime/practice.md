# Practice ownership and current boundary

Status: current prototype boundary. The runtime persists one minimal accepted
Practice head; it does not yet implement a catalog of named Practices or the
complete product surface described here.

A Practice answers: what activity am I in, what resources and roots are bound
into it, and what exact attenuated authority may act? It is durable contextual
structure, not a container that absorbs every product's records.

## Practice owns

- stable Practice identity and the accepted durable head;
- selected semantic root/resource bindings and vocabulary roots;
- candidate, attenuated, authorized, and revoked facets/authority policy;
- entry-lens declarations for an activity, separate from shell geometry; and
- recovery/read-only state and the minimum facts required for safe activation.

Practice does not own Library content or metadata, Streams sources or
observations, Daybook entries or schedule history, Grid workbooks, Agent
threads, arbitrary VFS trees, Desk layout/focus, or live provider/XIO state.
It is neither a universal knowledge base nor a workflow database.

## Binding, authority, and hosting are distinct

A durable Practice binding stores stable semantic RREF/root facts. It never
stores an activation-local `LBIND`, component pointer/generation, acquisition
token, live grant, or handler choice. A binding makes a resource relevant and
nameable; it does not copy the resource into Practice and does not grant read,
replace, refresh, delete, schedule, or external-effect authority.

Authority is declared and attenuated separately, then Desk and the Agent
runtime compile an exact live facet under the selected preset and Mandate.
Discovery, installation, visibility, a binding, or a preset is not by itself a
grant.

Practice owns which lenses form an entry into an activity. Desk owns the
validated shell layout, focus order, activation sequencing, and lifecycle that
realize those declarations. Desk may host Practice-scoped services, but it
does not thereby own the bound domain records.

## Exact targets

Consequential operations name the domain owner, stable target, complete
operands, and expected domain state. They may not depend on the current
Streams row, selected Daybook date, selected Grid cell, active Pad tab, focused
applet, or another hidden UI selection. Create/import instead uses its sealed
owner/catalog precondition plus an idempotency key. A qualified persistent
locator may be resolved to a live `LBIND` for a call, but failure never falls
forward to latest or ambient VFS access.

## Current implementation boundary

The landed runtime uses the fixed `/practice-head-a.bin` and
`/practice-head-b.bin` pair for one minimal accepted head. It carries identity
and revision plus current/previous, binding, cell, grant, manifest, schema,
export root, retention policy, and activation policy. This is not a
multi-Practice catalog, naming UI, layout store, domain database, or general
resource browser.

The store delegates only two-slot generation ordering and inactive publication
to `utils/generation-pair.f`. Practice still owns its exact record bytes,
paths, semantic head validation, status translation, fallback evidence, and
readonly recovery policy. Equal-generation records are accepted only when the
decoded heads are identical and deterministically select slot A; divergent
valid records fail closed as split-brain recovery evidence without publishing
either generation as authority. Semantic rejection records its generation in
the dedicated evidence field; when the older candidate is accepted, the
generation pair reclassifies and publishes that fallback consistently. A save
adopts the next generation in memory only after the inactive file has been
written and the VFS durability barrier succeeds.
Pair candidates retain stable descriptor identity while decoded heads remain
transient Practice-owned buffers used only for comparison and copying. Thus a
published selection cannot expose a head pointer after that buffer is freed.

L4 changes no persisted Practice bytes, paths, public word signatures,
activation order, or applet functionality. `PHEADVFS-SIZE` grows because the
current adapter directly embeds its caller-owned pair and candidates; callers
recompile against that current size, with no obsolete-size facade. RAM
authority now fails closed: split-brain evidence is separate from the
generation pair, and semantic fallback leaves every pair publication field
describing the accepted candidate. Multiple Practices, catalog/path design,
selection UI, entry-lens restoration, and richer inspection remain later
focused work; the prototype does not retain an obsolete parallel generation
implementation or a legacy compatibility path.
