\ =====================================================================
\  profile.f - Shared provisional RABBIT/1.0 scalar vocabulary
\ =====================================================================
\  These are wire/profile bounds and capability bits, not storage or
\  product capacities.  Keeping them below message, builder, and session
\  prevents construction from depending on the session/NIO owner.
\ =====================================================================

PROVIDED akashic-rabbit-profile

1 CONSTANT RABBIT-CAP-F-LANES
2 CONSTANT RABBIT-CAP-F-ASYNC
RABBIT-CAP-F-LANES RABBIT-CAP-F-ASYNC OR
    CONSTANT RABBIT-CAPS-LANES-ASYNC
RABBIT-CAPS-LANES-ASYNC CONSTANT RABBIT-CAPS-KNOWN

0xFFFF     CONSTANT RABBIT-LANE-MAX
0xFFFFFFFF CONSTANT RABBIT-CREDIT-MAX
-1         CONSTANT RABBIT-U64-MAX
