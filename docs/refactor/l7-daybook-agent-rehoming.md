# Refactor Landing L7 Agent and Daybook re-homing

Landing L7 fixes product ownership and dependency direction without replacing
an applet or removing behavior. Agent's provider, runtime, transcript, storage,
authentication, settings, tool, and renderer-free domain modules now live
beneath `tui/applets/agent/`. The remaining concrete Daybook document owner now
lives beneath `tui/applets/daybook/`. Their applet-specific documentation and
Agent widgets move with them; the old top-level product paths are deleted.

Renderer-free compilation remains a test boundary, not a standalone product
identity. Every moved module is still Agent- or Daybook-owned inside the Desk
ecosystem. No compatibility facade, second authority, format migration, larger
capacity, deferred applet, Game/Worlds/SoundLab work, or ext4 dependency enters
this landing.

## Public composition boundaries

`tui/applets/agent/service.f` is the one public Agent production seam consumed
by Desk composition. It loads the runtime, mandate, offline-provider, and VFS
conversation services that Desk actually constructs; Desk no longer imports
five private Agent implementation files. Focused renderer-free tests may still
require the exact applet-owned leaf they qualify.

Desk continues to consume Daybook through
`tui/applets/daybook/shared-document.f`, the public concrete resource-owner
service established by the prior owner/session landings. The architecture
policy admits exactly these two cross-applet edges:

- Desk access policy to the public Agent service; and
- Desk product composition to the public Daybook resource service.

The ratchet has explicit negative cases for Desk-to-Agent-runtime and
Desk-to-Daybook-applet imports, so naming public seams does not bless sibling
private dependencies. Shared TUI and independent libraries still import no
concrete applet.

## Access contract and Desk policy split

Agent's `access-profile.f` owns only the bounded record, selector constants,
structural validation, and generic status contract. Desk's
`agent-access-policy.f` owns the exact `desk.chat-only`,
`desk.practice-read`, and `desk.practice-assist` identities, labels, flags,
effects, dispositions, and budgets.

The runtime receives separate injected construction and exact-validation
callbacks. Preset selection builds into a runtime-owned candidate, runs both
structural and injected validation, and copies into the live profile only after
success. A callback that partially writes and fails, or reports success with a
malformed candidate, therefore preserves the previous profile, revision, and
disclosure accounting.

Desk binds both callbacks before its initial preset selection. The mandate
factory revalidates the stored profile with Desk's exact validator before it
allocates a child Context or compiles effects and budgets. A structurally valid
post-selection mutation cannot retain a trusted selector while changing the
authority it represents.

## Preservation characterization

The L1 `agent.provider-ui-commands` prerequisite is closed by
`agent-provider-ui-commands`. Its fixture parses a small real UIDL document,
wires the real Agent state/body elements, and invokes the production Clear,
Reconnect, and Refresh Models callbacks. It pins rendered Ready/Offline,
Streaming, Loading Models, and Model Catalog Error states; body/state dirtying;
exact success/failure toasts; unchanged active-run behavior; and exactly one
provider callback per request.

That characterization exposed and fixed one existing stack-contract defect:
`ARUNTIME-RUN-SETTINGS-REFRESH` now returns exactly one status cell. No action,
menu, shortcut, provider identity, capability, transcript rule, Daybook
resource behavior, or Desk service ID changes.

## Qualification

The final isolated L7 worktree records exact focused and linked results here.

| Command or profile | Result |
| --- | --- |
| `agent-provider-ui-commands` | 47 assertions; 1,771,276,847 guest steps |
| `agent` | PASS; 642,831,481 guest steps |
| `agent-access` | 85 assertions; 608,926,213 guest steps |
| `agent-security` | 337 assertions; 661,978,636 guest steps |
| `agent-persistence` | 69 assertions; 602,675,685 guest steps |
| `agent-widgets` | PASS; 576,850,283 guest steps |
| `daybook-contracts` | 140 assertions; 1,877,838,607 guest steps |
| `desk-service-table-contracts` | 92 assertions; 2,907,282,781 guest steps |
| `desktop-agent-hardening` | linked journey PASS; 16,700,000,000 guest steps |
| `desktop-resource` | linked journey PASS; 7,340,000,000 guest steps |
| focused L7/Daybook pytest | 9 passed |
| complete practical host gate | 207 passed; 0 skipped; 0 failed |

All rows were rerun against a frozen isolated L7 worktree. The Desk service
fixture initially exposed that its synthetic runtime lacked the newly required
exact validator; the fixture now installs the production Desk callbacks before
seeding its profile and passes all 92 assertions.

## Ratchet and exit rule

The frozen L7 architecture contains 388 modules and 1,307 resolved occurrences
and unique edges. It has 78 reviewed unresolved imports, no cycle, one existing
target-layer violation, five placement-debt modules, two provided-name issues,
one addressability issue, and no completion-marker issue. The graph, state,
placement, and unresolved digests are respectively
`c9886aa3538e3b72468a2b223dba034b647981bb217c8e21e013a5f1e50d9f2e`,
`6e3b6b6fc6f69c12cef9f8be203b970ad7e8dc58f8114e0390658386d8ad713a`,
`c540ef260753879f91579cc1480a47b4e9ae50f3d4dd335fa0a07378fb50745c`,
and `98fad31ab92dd0633ed32bc95f3c387e9d222001a4080f7e6926edaec16f21cb`.
The five remaining placement debts are exactly the Library files reserved for
the separate L8 landing.

The functional ledger now contains 12 covered, 15 partial, and two
prerequisite-only groups, with 22 remaining prerequisites and 110 evidence
references. L7 is complete only when the focused Agent/Daybook tests, linked
Desk journeys, both ratchets, packaging checks, and the complete practical host
gate pass together in the isolated L7 tree.
