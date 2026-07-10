\ =====================================================================
\  policy.f - Principals, effects, decisions, and one-use approvals
\ =====================================================================

PROVIDED akashic-interop-policy

REQUIRE capability.f

1 CONSTANT CPRINC-USER
2 CONSTANT CPRINC-SYSTEM
3 CONSTANT CPRINC-COMPONENT
4 CONSTANT CPRINC-AGENT

0 CONSTANT CPOL-DENY
1 CONSTANT CPOL-ALLOW
2 CONSTANT CPOL-APPROVAL

\ Policy descriptor: decision callback and caller-owned context.
 0 CONSTANT _CP-DECIDE-XT       \ ( principal effects context -- decision )
 8 CONSTANT _CP-CONTEXT
16 CONSTANT _CP-FLAGS
24 CONSTANT _CP-RESERVED
32 CONSTANT CPOLICY-SIZE

: CPOL.DECIDE-XT  ( policy -- a ) _CP-DECIDE-XT + ;
: CPOL.CONTEXT    ( policy -- a ) _CP-CONTEXT + ;
: CPOL.FLAGS      ( policy -- a ) _CP-FLAGS + ;

: CPOLICY-INIT  ( policy -- ) CPOLICY-SIZE 0 FILL ;

: CPOLICY-DEFAULT-DECIDE  ( principal effects context -- decision )
    DROP SWAP CPRINC-USER = IF DROP CPOL-ALLOW EXIT THEN
    DUP CAP-E-DESTRUCTIVE AND IF DROP CPOL-APPROVAL EXIT THEN
    DUP CAP-E-EXTERNAL AND IF DROP CPOL-APPROVAL EXIT THEN
    DUP CAP-E-PERSIST AND IF DROP CPOL-APPROVAL EXIT THEN
    DUP CAP-E-MUTATE AND IF DROP CPOL-APPROVAL EXIT THEN
    DROP CPOL-ALLOW ;

: CPOLICY-DECIDE  ( principal effects policy -- decision )
    DUP 0= IF DROP 0 CPOLICY-DEFAULT-DECIDE EXIT THEN
    DUP CPOL.DECIDE-XT @ ?DUP IF
        >R CPOL.CONTEXT @ R> EXECUTE
    ELSE
        DROP 0 CPOLICY-DEFAULT-DECIDE
    THEN ;
