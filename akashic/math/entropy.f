\ =====================================================================
\  entropy.f - Generic checked hardware entropy acquisition
\ =====================================================================
\  This module names the production entropy contract used by key generation,
\  OAuth, nonces, and salts.  The BIOS owns device access, complete physical
\  span qualification, protected-memory rejection, health checks, and
\  detected post-start cleanup.  Akashic neither knows the TRNG MMIO address
\  nor implements a second byte-at-a-time entropy path.
\
\  The module owns no mutable state.  Calls on different cores may proceed
\  independently through the shared hardware source; the device serializes
\  individual source operations.  A returned failure never represents a
\  successful acquisition.
\
\  Public API:
\    ENTROPY-READY?        ( -- flag )
\    ENTROPY-FILL          ( destination length -- status )
\    ENTROPY-STATUS-VALID? ( status -- flag )
\
\  Status:
\    0 OK, 1 UNAVAILABLE, 2 RANGE, 3 PROTECTED.
\ =====================================================================

PROVIDED akashic-entropy

0 CONSTANT ENTROPY-S-OK
1 CONSTANT ENTROPY-S-UNAVAILABLE
2 CONSTANT ENTROPY-S-RANGE
3 CONSTANT ENTROPY-S-PROTECTED

: ENTROPY-STATUS-VALID?  ( status -- flag )
    DUP ENTROPY-S-OK >=
    SWAP ENTROPY-S-PROTECTED <= AND ;

\ Capture the architectural words before publishing the Akashic bindings.
\ The wrappers deliberately add no CATCH: the BIOS documents one narrow
\ asynchronous STATUS-to-RAND8 bus-fault race that cannot be converted into a
\ trustworthy status or recoverable wipe.  Letting that architectural fault
\ propagate is more honest than reporting ordinary UNAVAILABLE.
' ENTROPY-FILL   CONSTANT _entropy-bios-fill-xt
' ENTROPY-READY? CONSTANT _entropy-bios-ready-xt

: ENTROPY-FILL  ( destination length -- status )
    _entropy-bios-fill-xt EXECUTE ;

: ENTROPY-READY?  ( -- flag )
    _entropy-bios-ready-xt EXECUTE ;
