\ =====================================================================
\  service.f - Public Agent applet composition seam
\ =====================================================================
\  Desk hosts an Agent runtime, and the dispatcher that runs the Agent's
\  scheduled work, but does not own Agent provider, transcript, storage,
\  or run semantics.  This is the one public production import for that
\  composition; renderer-free tests may still require the focused
\  applet-owned modules directly.
\ =====================================================================

PROVIDED akashic-tui-agent-service

REQUIRE runtime.f
REQUIRE mandate-run.f
REQUIRE providers/offline.f
REQUIRE storage/vfs-conversation.f
REQUIRE dispatch.f
