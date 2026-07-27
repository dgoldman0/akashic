\ =====================================================================
\  crypto-acc.f - Shared EXT.CRYPTO accumulator ownership
\ =====================================================================
\  Several Megapad-64 cryptographic ISA units reuse per-core ACC0..ACC3.
\  Per-instruction atomicity is therefore insufficient: a cooperative
\  same-core task switch can let a different unit overwrite an operation
\  that spans multiple instructions.
\
\  This generic transaction is the outermost ownership boundary for every
\  library that retains state in those accumulators.  Unit-specific guards
\  protecting module scratch or protocol phase state are acquired only
\  inside this transaction.  The canonical order is:
\
\      CRYPTO-ACC transaction -> unit-specific guard
\
\  Public API:
\    CRYPTO-ACC-WITH-TRANSACTION   ( i*x xt -- j*x )
\    CRYPTO-ACC-TRANSACTION-MINE?  ( -- flag )
\    CRYPTO-ACC-RESERVED-OVERLAP?  ( address length -- flag )
\ =====================================================================

PROVIDED akashic-crypto-acc

REQUIRE ../concurrency/guard.f
REQUIRE ../utils/memory-span.f

GUARD-BLOCKING _crypto-acc-guard

CREATE _CACC-PUBLIC-ZERO
    0 , 0 , 0 , 0 ,

CREATE _CACC-SCRUB-LO 32 ALLOT
CREATE _CACC-SCRUB-HI 32 ALLOT

\ The transaction mutates its guard on entry/exit and writes all three scrub
\ buffers on outer exit.  A unit whose caller operands alias any of these
\ regions cannot preserve source bytes or a just-published result.  This
\ policy-neutral predicate lets every unit reject that geometry before it
\ acquires the transaction.
: CRYPTO-ACC-RESERVED-OVERLAP?  ( address length -- flag )
    2DUP
    _crypto-acc-guard GUARD-BLOCKING-SIZE
        MSPAN-OVERLAP? IF
        2DROP -1 EXIT
    THEN
    2DUP
    _CACC-PUBLIC-ZERO 32
        MSPAN-OVERLAP? IF
        2DROP -1 EXIT
    THEN
    2DUP
    _CACC-SCRUB-LO 32
        MSPAN-OVERLAP? IF
        2DROP -1 EXIT
    THEN
    _CACC-SCRUB-HI 32 MSPAN-OVERLAP? ;

\ A public zero raw multiply overwrites ACC0..ACC3, the Field ALU's
\ persistent prev_lo/prev_hi pair, and its tile destination.  Those values
\ are otherwise BIOS-readable and can contain a private-derived
\ intermediate when a higher-level operation returns or throws.
: _CACC-SCRUB  ( -- )
    _CACC-PUBLIC-ZERO 32 0 FILL
    _CACC-PUBLIC-ZERO _CACC-PUBLIC-ZERO
    _CACC-SCRUB-LO _CACC-SCRUB-HI FMUL-RAW
    _CACC-SCRUB-LO 32 0 FILL
    _CACC-SCRUB-HI 32 0 FILL ;

: _CACC-WITH-OUTER  ( i*x xt -- j*x )
    _crypto-acc-guard GUARD-ACQUIRE
    CATCH
    ['] _CACC-SCRUB CATCH
    _crypto-acc-guard GUARD-RELEASE
    ?DUP IF
        SWAP DROP THROW
    THEN
    ?DUP IF THROW THEN ;

: CRYPTO-ACC-TRANSACTION-MINE?  ( -- flag )
    _crypto-acc-guard GUARD-MINE? ;

\ Nested scopes preserve the accumulator chain for multi-operation Field
\ transactions.  Only the owner that first acquired the shared boundary
\ performs final scrubbing.
: CRYPTO-ACC-WITH-TRANSACTION  ( i*x xt -- j*x )
    CRYPTO-ACC-TRANSACTION-MINE? IF
        _crypto-acc-guard WITH-GUARD EXIT
    THEN
    _CACC-WITH-OUTER ;
