\ =====================================================================
\  akashic/game/components.f — Common ECS Components
\ =====================================================================
\
\  Pre-defined component types for common game patterns.  Each
\  component is a fixed-size struct accessed via field offset
\  constants.  Register with ECS-REG-COMP, attach with ECS-ATTACH,
\  then read/write fields at the returned address.
\
\  Components:
\    C-POS        16 bytes   x, y position
\    C-VEL        16 bytes   dx, dy velocity
\    C-SPRITE      8 bytes   sprite handle / atlas tile-id
\    C-HEALTH     16 bytes   current, max HP
\    C-COLLIDER    8 bytes   collision layer bitmask
\    C-TIMER      16 bytes   ticks remaining, callback XT
\    C-TAG         8 bytes   user-defined tag integer
\    C-AI          8 bytes   FSM state pointer
\
\  Registration pattern:
\    ecs 16 ECS-REG-COMP CONSTANT C-POS
\
\  Usage pattern:
\    ecs eid C-POS ECS-ATTACH   \ ( -- addr )
\    42 OVER C-POS.X + !
\    99 SWAP C-POS.Y + !
\
\  Prefix: C- (component ID, user-stored), C-xxx. (field offsets)
\  Provider: akashic-game-components
\  Dependencies: ecs.f

PROVIDED akashic-game-components

REQUIRE ecs.f

\ =====================================================================
\  §1 — Position Component (16 bytes)
\ =====================================================================

0 CONSTANT C-POS.X
8 CONSTANT C-POS.Y
16 CONSTANT C-POS-SZ

\ =====================================================================
\  §2 — Velocity Component (16 bytes)
\ =====================================================================

0 CONSTANT C-VEL.DX
8 CONSTANT C-VEL.DY
16 CONSTANT C-VEL-SZ

\ =====================================================================
\  §3 — Sprite Component (8 bytes)
\ =====================================================================

0 CONSTANT C-SPR.TILE
8 CONSTANT C-SPR-SZ

\ =====================================================================
\  §4 — Health Component (16 bytes)
\ =====================================================================

0 CONSTANT C-HP.CUR
8 CONSTANT C-HP.MAX
16 CONSTANT C-HP-SZ

\ =====================================================================
\  §5 — Collider Component (8 bytes)
\ =====================================================================

0 CONSTANT C-COL.MASK
8 CONSTANT C-COL-SZ

\ =====================================================================
\  §6 — Timer Component (16 bytes)
\ =====================================================================

0 CONSTANT C-TMR.TICKS
8 CONSTANT C-TMR.XT
16 CONSTANT C-TMR-SZ

\ =====================================================================
\  §7 — Tag Component (8 bytes)
\ =====================================================================

0 CONSTANT C-TAG.VAL
8 CONSTANT C-TAG-SZ

\ =====================================================================
\  §8 — AI Component (8 bytes)
\ =====================================================================

0 CONSTANT C-AI.STATE
8 CONSTANT C-AI-SZ

\ =====================================================================
\  §9 — Bulk Registration Helper
\ =====================================================================
\
\  COMPS-REG-ALL ( ecs -- c-pos c-vel c-spr c-hp c-col c-tmr c-tag c-ai )
\    Registers all 8 standard components and leaves their IDs on the
\    stack.  Caller should store them in CONSTANTs or VARIABLEs.

: COMPS-REG-ALL  ( ecs -- c-pos c-vel c-spr c-hp c-col c-tmr c-tag c-ai )
    DUP C-POS-SZ ECS-REG-COMP SWAP
    DUP C-VEL-SZ ECS-REG-COMP SWAP
    DUP C-SPR-SZ ECS-REG-COMP SWAP
    DUP C-HP-SZ  ECS-REG-COMP SWAP
    DUP C-COL-SZ ECS-REG-COMP SWAP
    DUP C-TMR-SZ ECS-REG-COMP SWAP
    DUP C-TAG-SZ ECS-REG-COMP SWAP
    C-AI-SZ ECS-REG-COMP ;

\ =====================================================================
\  §10 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _comp-guard

' COMPS-REG-ALL CONSTANT _comp-reg-all-xt

: COMPS-REG-ALL _comp-reg-all-xt _comp-guard WITH-GUARD ;
[THEN] [THEN]
