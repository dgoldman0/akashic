\ critical.f — Critical Sections & Preemption Control for KDOS / Megapad-64
\
\ Critical sections combine preemption suppression with optional mutual
\ exclusion.  For code that must not be interrupted or re-scheduled
\ (MMIO register sequences, multi-step hardware operations), this is
\ the correct primitive.
\
\ Two layers:
\   CRITICAL-BEGIN / CRITICAL-END   — nestable preemption disable
\   CRITICAL-LOCK  / CRITICAL-UNLOCK — preemption disable + spinlock
\
\ Nesting model:
\   CRITICAL-BEGIN increments a depth counter.  Only the first
\   (outermost) call actually issues PREEMPT-OFF.  CRITICAL-END
\   decrements; only the final (outermost) call issues PREEMPT-ON.
\   This prevents inner scopes from re-enabling preemption prematurely.
\
\ CRITICAL-LOCK / CRITICAL-UNLOCK layer a KDOS hardware spinlock on
\ top of the preemption guard, giving multicore mutual exclusion.
\ Preemption is disabled BEFORE acquiring the spinlock (standard
\ lock-ordering discipline: disable scheduling → acquire lock).
\
\ WITH-CRITICAL and WITH-CRITICAL-LOCK provide RAII-style wrappers
\ that guarantee cleanup via CATCH.
\
\ Data:
\   _crit-depth   VARIABLE — nesting depth (per-core when extending
\                  to multicore; single cell for single-core baseline)
\
\ Dependencies: none (PREEMPT-OFF / PREEMPT-ON / LOCK / UNLOCK
\               are KDOS kernel words, always available)
\
\ Prefix: CRITICAL-  (public API)
\         _CRIT-     (internal helpers)
\
\ Load with:   REQUIRE critical.f

PROVIDED akashic-critical

\ =====================================================================
\  Nesting Depth Counter
\ =====================================================================

VARIABLE _crit-depth   0 _crit-depth !

\ =====================================================================
\  CRITICAL-BEGIN / CRITICAL-END — Nestable Preemption Disable
\ =====================================================================

\ CRITICAL-BEGIN ( -- )
\   Disable preemption if not already in a critical section.
\   Increments the nesting depth.  Safe to nest arbitrarily.
\
\   Example:
\     CRITICAL-BEGIN
\       ... MMIO register sequence ...
\       CRITICAL-BEGIN          \ inner — depth goes to 2
\         ... more MMIO work ...
\       CRITICAL-END            \ depth back to 1 — still protected
\     CRITICAL-END              \ depth 0 — preemption re-enabled

: CRITICAL-BEGIN  ( -- )
    _crit-depth @ 0= IF PREEMPT-OFF THEN
    1 _crit-depth +! ;

\ CRITICAL-END ( -- )
\   Decrement nesting depth.  Re-enable preemption only when the
\   outermost critical section exits (depth reaches 0).

: CRITICAL-END  ( -- )
    _crit-depth @ 1- DUP _crit-depth !
    0= IF PREEMPT-ON THEN ;

\ =====================================================================
\  CRITICAL-DEPTH — Query Nesting Depth
\ =====================================================================

\ CRITICAL-DEPTH ( -- n )
\   Return current nesting depth.  0 = not in a critical section.

: CRITICAL-DEPTH  ( -- n )
    _crit-depth @ ;

\ =====================================================================
\  WITH-CRITICAL — RAII-Style Preemption-Safe Scope
\ =====================================================================

\ WITH-CRITICAL ( xt -- )
\   Execute xt with preemption disabled.  If xt THROWs, preemption
\   is restored before the exception propagates.
\
\   Example:
\     ['] _ntt-load-xform  WITH-CRITICAL

: WITH-CRITICAL  ( xt -- )
    CRITICAL-BEGIN
    CATCH
    CRITICAL-END
    DUP IF THROW THEN
    DROP ;

\ =====================================================================
\  CRITICAL-LOCK / CRITICAL-UNLOCK — Preemption + Spinlock
\ =====================================================================

\ CRITICAL-LOCK ( lock# -- )
\   Disable preemption, then acquire hardware spinlock lock#.
\   The ordering (preempt-off first, then lock) prevents a
\   scenario where the scheduler preempts a task holding a
\   spinlock, potentially causing priority inversion or deadlock.

: CRITICAL-LOCK  ( lock# -- )
    CRITICAL-BEGIN  LOCK ;

\ CRITICAL-UNLOCK ( lock# -- )
\   Release hardware spinlock lock#, then re-enable preemption
\   (or decrement nesting depth).

: CRITICAL-UNLOCK  ( lock# -- )
    UNLOCK  CRITICAL-END ;

\ =====================================================================
\  WITH-CRITICAL-LOCK — RAII-Style Preemption + Spinlock Scope
\ =====================================================================

\ WITH-CRITICAL-LOCK ( xt lock# -- )
\   Disable preemption, acquire spinlock, execute xt, release
\   spinlock, restore preemption.  If xt THROWs, both the spinlock
\   and preemption state are properly restored before re-throw.
\
\   Example:
\     ['] _do-fwrite  2 WITH-CRITICAL-LOCK   \ spinlock 2 = FS

: WITH-CRITICAL-LOCK  ( xt lock# -- )
    DUP >R CRITICAL-LOCK
    CATCH
    R> CRITICAL-UNLOCK
    DUP IF THROW THEN
    DROP ;

\ =====================================================================
\  CRITICAL-INFO — Debug Display
\ =====================================================================

\ CRITICAL-INFO ( -- )
\   Print current critical-section state for debugging.

: CRITICAL-INFO  ( -- )
    ." [critical depth=" _crit-depth @ .  ." ]" CR ;

\ =====================================================================
\  Quick Reference
\ =====================================================================
\
\  CRITICAL-BEGIN       ( -- )            Enter critical section
\  CRITICAL-END         ( -- )            Leave critical section
\  CRITICAL-DEPTH       ( -- n )          Query nesting depth
\  WITH-CRITICAL        ( xt -- )         RAII preemption-safe scope
\  CRITICAL-LOCK        ( lock# -- )      Preempt-off + spinlock
\  CRITICAL-UNLOCK      ( lock# -- )      Release spinlock + preempt-on
\  WITH-CRITICAL-LOCK   ( xt lock# -- )   RAII preempt + spinlock scope
\  CRITICAL-INFO        ( -- )            Debug display
