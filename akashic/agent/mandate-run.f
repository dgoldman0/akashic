\ =====================================================================
\  mandate-run.f - Frozen owner-side Mandate and capability facet
\ =====================================================================
\  AMRUN owns immutable copies of one Mandate and its exact input/
\  disclosure facet for a provider run.  It owns budget counters, but no
\  capability authority.  Individual operations still require sealed
\  one-use grants consumed by the target owner.
\ =====================================================================

PROVIDED akashic-agent-mandrun

REQUIRE ../runtime/context.f
REQUIRE ../runtime/practice-head.f
REQUIRE ../interop/mandate.f
REQUIRE ../interop/capability-facet.f
REQUIRE ../concurrency/guard.f

0 CONSTANT AMRUN-S-OK
1 CONSTANT AMRUN-S-INVALID
2 CONSTANT AMRUN-S-NOMEM
3 CONSTANT AMRUN-S-INACTIVE
4 CONSTANT AMRUN-S-BUDGET
5 CONSTANT AMRUN-S-DENIED

1 CONSTANT AMRUN-STATE-FROZEN
2 CONSTANT AMRUN-STATE-CLOSED

1314016577 CONSTANT AMRUN-MAGIC       \ "AMRN"
1          CONSTANT AMRUN-ABI-VERSION

  0 CONSTANT _AMR-MAGIC
  8 CONSTANT _AMR-ABI
 16 CONSTANT _AMR-SIZE
 24 CONSTANT _AMR-STATE
 32 CONSTANT _AMR-START-MS
 40 CONSTANT _AMR-DEADLINE-MS
 48 CONSTANT _AMR-TOOLS-USED
 56 CONSTANT _AMR-DISCLOSURE-USED
 64 CONSTANT _AMR-CONTEXT
 72 CONSTANT _AMR-FLAGS
 80 CONSTANT _AMR-MANDATE
_AMR-MANDATE MAND-SIZE + CONSTANT _AMR-FACET
_AMR-FACET CFACET-SIZE + CONSTANT _AMR-REFS
_AMR-REFS 8 + CONSTANT _AMR-FREE-PENDING
_AMR-FREE-PENDING 8 + CONSTANT AGENT-MANDATE-RUN-SIZE

: AMRUN.MAGIC            ( run -- a ) _AMR-MAGIC + ;
: AMRUN.ABI              ( run -- a ) _AMR-ABI + ;
: AMRUN.SIZE             ( run -- a ) _AMR-SIZE + ;
: AMRUN.STATE            ( run -- a ) _AMR-STATE + ;
: AMRUN.START-MS         ( run -- a ) _AMR-START-MS + ;
: AMRUN.DEADLINE-MS      ( run -- a ) _AMR-DEADLINE-MS + ;
: AMRUN.TOOLS-USED       ( run -- a ) _AMR-TOOLS-USED + ;
: AMRUN.DISCLOSURE-USED  ( run -- a ) _AMR-DISCLOSURE-USED + ;
: AMRUN.CONTEXT          ( run -- a ) _AMR-CONTEXT + ;
: AMRUN.FLAGS            ( run -- a ) _AMR-FLAGS + ;
: AMRUN.MANDATE          ( run -- mandate ) _AMR-MANDATE + ;
: AMRUN.FACET            ( run -- facet ) _AMR-FACET + ;
: AMRUN.REFS             ( run -- a ) _AMR-REFS + ;
: AMRUN.FREE-PENDING     ( run -- a ) _AMR-FREE-PENDING + ;

\ All mutable lifecycle and accounting fields share this domain.  Gateways
\ retain a bound run, so AMRUN-FREE can close the owner reference immediately
\ while deferring physical reclamation until the final gateway releases it.
GUARD _amrun-accounting-guard

: AMRUN-STRUCTURAL-VALID?  ( run -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP AMRUN.MAGIC @ AMRUN-MAGIC =
    OVER AMRUN.ABI @ AMRUN-ABI-VERSION = AND
    OVER AMRUN.SIZE @ AGENT-MANDATE-RUN-SIZE >= AND
    OVER AMRUN.STATE @ AMRUN-STATE-FROZEN = AND
    OVER AMRUN.CONTEXT @ CTX-VALID? AND
    OVER AMRUN.MANDATE MAND-STRUCTURAL-VALID? AND
    SWAP AMRUN.FACET CFACET-VALID? AND ;

VARIABLE _AMN-HEAD
VARIABLE _AMN-CONTEXT
VARIABLE _AMN-MANDATE
VARIABLE _AMN-FACET
VARIABLE _AMN-RUN
VARIABLE _AMN-DEADLINE

: _AMRUN-SCOPE-VALID?  ( -- flag )
    _AMN-HEAD @ PHEAD-VALID? 0= IF 0 EXIT THEN
    _AMN-CONTEXT @ CTX-VALID? 0= IF 0 EXIT THEN
    _AMN-MANDATE @ MAND-STRUCTURAL-VALID? 0= IF 0 EXIT THEN
    _AMN-FACET @ CFACET-VALID? 0= IF 0 EXIT THEN
    _AMN-CONTEXT @ CTX.PRACTICE @ _AMN-HEAD @ <> IF 0 EXIT THEN
    _AMN-HEAD @ PHEAD.ID _AMN-MANDATE @ MAND.PRACTICE-ID RID= 0= IF
        0 EXIT
    THEN
    _AMN-HEAD @ PHEAD.ID _AMN-FACET @ CFACET.PRACTICE-ID RID= 0= IF
        0 EXIT
    THEN
    _AMN-CONTEXT @ CTX.ID @ _AMN-CONTEXT @ CTX.GENERATION @
        _AMN-MANDATE @ MAND-CONTEXT-MATCH? 0= IF 0 EXIT THEN
    _AMN-CONTEXT @ CTX.EPOCH @ _AMN-MANDATE @ MAND.ACTIVATION-EPOCH @ <>
        IF 0 EXIT THEN
    _AMN-CONTEXT @ CTX.ID @ _AMN-FACET @ CFACET.CONTEXT-ID @ <>
        IF 0 EXIT THEN
    _AMN-CONTEXT @ CTX.GENERATION @ _AMN-FACET @ CFACET.CONTEXT-GEN @ <>
        IF 0 EXIT THEN
    _AMN-CONTEXT @ CTX.EPOCH @ _AMN-FACET @ CFACET.EPOCH @ <>
        IF 0 EXIT THEN
    _AMN-FACET @ CFACET.ID _AMN-MANDATE @ MAND.INPUT-FACET-ID RID= 0= IF
        0 EXIT
    THEN
    _AMN-FACET @ CFACET.ID
        _AMN-MANDATE @ MAND.DISCLOSURE-FACET-ID RID= 0= IF 0 EXIT THEN
    _AMN-FACET @ CFACET.COUNT @ 0 ?DO
        I _AMN-FACET @ CFACET-NTH CFENTRY.EFFECTS @
        _AMN-MANDATE @ MAND-EFFECTS-VALID? 0= IF 0 UNLOOP EXIT THEN
    LOOP
    -1 ;

: AMRUN-NEW  ( practice-head child-context mandate facet -- run status )
    _AMN-FACET ! _AMN-MANDATE ! _AMN-CONTEXT ! _AMN-HEAD !
    _AMRUN-SCOPE-VALID? 0= IF 0 AMRUN-S-INVALID EXIT THEN
    AGENT-MANDATE-RUN-SIZE ALLOCATE DUP IF
        SWAP DROP 0 AMRUN-S-NOMEM EXIT
    THEN
    DROP DUP _AMN-RUN ! AGENT-MANDATE-RUN-SIZE 0 FILL
    AMRUN-MAGIC _AMN-RUN @ AMRUN.MAGIC !
    AMRUN-ABI-VERSION _AMN-RUN @ AMRUN.ABI !
    AGENT-MANDATE-RUN-SIZE _AMN-RUN @ AMRUN.SIZE !
    AMRUN-STATE-FROZEN _AMN-RUN @ AMRUN.STATE !
    1 _AMN-RUN @ AMRUN.REFS !
    _AMN-CONTEXT @ _AMN-RUN @ AMRUN.CONTEXT !
    _AMN-MANDATE @ _AMN-RUN @ AMRUN.MANDATE MAND-SIZE MOVE
    _AMN-FACET @ _AMN-RUN @ AMRUN.FACET CFACET-SIZE MOVE
    MS@ _AMN-RUN @ AMRUN.START-MS !
    0 _AMN-DEADLINE !
    _AMN-RUN @ AMRUN.MANDATE MAND.EXPIRES-MS @ _AMN-DEADLINE !
    _AMN-RUN @ AMRUN.MANDATE MAND.TIME-BUDGET-MS @ ?DUP IF
        MS@ + DUP 0> IF
            _AMN-DEADLINE @ DUP 0= IF
                DROP _AMN-DEADLINE !
            ELSE
                MIN _AMN-DEADLINE !
            THEN
        ELSE
            DROP
        THEN
    THEN
    _AMN-DEADLINE @ _AMN-RUN @ AMRUN.DEADLINE-MS !
    _AMN-RUN @ AMRUN.MANDATE MAND.ACTIVATION-EPOCH @ MS@
        _AMN-RUN @ AMRUN.MANDATE MAND-ACTIVE? 0= IF
        _AMN-RUN @ AGENT-MANDATE-RUN-SIZE 0 FILL FREE
        0 AMRUN-S-INACTIVE EXIT
    THEN
    _AMN-RUN @ AMRUN-S-OK ;

' AMRUN-NEW CONSTANT _amrun-new-xt
: AMRUN-NEW  ( practice-head child-context mandate facet -- run status )
    \ KDOS heap construction is core-0-only.  Fail before ALLOCATE on a
    \ worker, and serialize all core-0 task construction scratch.
    COREID IF 2DROP 2DROP 0 AMRUN-S-INVALID EXIT THEN
    _amrun-new-xt _amrun-accounting-guard WITH-GUARD ;

: AMRUN-ACTIVE?  ( run -- flag )
    DUP AMRUN-STRUCTURAL-VALID? 0= IF DROP 0 EXIT THEN
    DUP AMRUN.DEADLINE-MS @ ?DUP IF
        MS@ SWAP < 0= IF DROP 0 EXIT THEN
    THEN
    DUP AMRUN.MANDATE MAND.ACTIVATION-EPOCH @ MS@
        ROT AMRUN.MANDATE MAND-ACTIVE? ;

: _AMRUN-CLOSE  ( run -- )
    DUP 0= IF DROP EXIT THEN
    AMRUN-STATE-CLOSED SWAP AMRUN.STATE ! ;

: _AMRUN-DESTROY  ( run -- )
    DUP 0= IF DROP EXIT THEN
    DUP AMRUN.CONTEXT @ ?DUP IF CTX-FREE THEN
    DUP AGENT-MANDATE-RUN-SIZE 0 FILL FREE ;

: _AMRUN-RECORD-VALID?  ( run -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP AMRUN.MAGIC @ AMRUN-MAGIC =
    OVER AMRUN.ABI @ AMRUN-ABI-VERSION = AND
    SWAP AMRUN.SIZE @ AGENT-MANDATE-RUN-SIZE >= AND ;

: _AMRUN-RETAIN  ( run -- status )
    DUP _AMRUN-RECORD-VALID? 0= IF DROP AMRUN-S-INVALID EXIT THEN
    DUP AMRUN.FREE-PENDING @ IF DROP AMRUN-S-INACTIVE EXIT THEN
    DUP AMRUN-ACTIVE? 0= IF DROP AMRUN-S-INACTIVE EXIT THEN
    DUP AMRUN.REFS @ DUP 1 < OVER 0x7FFFFFFFFFFFFFFF >= OR IF
        2DROP AMRUN-S-INVALID EXIT
    THEN
    DROP 1 SWAP AMRUN.REFS +! AMRUN-S-OK ;

: _AMRUN-RELEASE  ( run -- )
    DUP _AMRUN-RECORD-VALID? 0= IF DROP EXIT THEN
    DUP AMRUN.REFS @ 0> IF -1 OVER AMRUN.REFS +! THEN
    DUP AMRUN.FREE-PENDING @ OVER AMRUN.REFS @ 0= AND IF
        _AMRUN-DESTROY
    ELSE
        DROP
    THEN ;

: _AMRUN-FREE  ( run -- )
    DUP _AMRUN-RECORD-VALID? 0= IF DROP EXIT THEN
    DUP AMRUN.FREE-PENDING @ IF DROP EXIT THEN
    AMRUN-STATE-CLOSED OVER AMRUN.STATE !
    -1 OVER AMRUN.FREE-PENDING !
    _AMRUN-RELEASE ;

VARIABLE _AMO-ID
VARIABLE _AMO-GEN
VARIABLE _AMO-CAP
VARIABLE _AMO-FLAGS
VARIABLE _AMO-RUN

: AMRUN-OP?  ( target-id target-generation cap required-flags run -- entry | 0 )
    _AMO-RUN ! _AMO-FLAGS ! _AMO-CAP ! _AMO-GEN ! _AMO-ID !
    _AMO-RUN @ AMRUN-ACTIVE? 0= IF 0 EXIT THEN
    _AMO-ID @ _AMO-GEN @ _AMO-CAP @ _AMO-RUN @ AMRUN.FACET
        CFACET-CAP-FIND DUP 0= IF EXIT THEN
    _AMO-CAP @ CAP.EFFECTS @ _AMO-FLAGS @ ROT CFENTRY-ALLOWS?
        IF
            _AMO-ID @ _AMO-GEN @ _AMO-CAP @ CAP-ID
                _AMO-RUN @ AMRUN.FACET CFACET-FIND
        ELSE
            0
        THEN ;

' AMRUN-ACTIVE? CONSTANT _amrun-active-xt
' AMRUN-OP? CONSTANT _amrun-op-xt

: AMRUN-ACTIVE?  ( run -- flag )
    _amrun-active-xt _amrun-accounting-guard WITH-GUARD ;

: AMRUN-OP?  ( target-id target-generation cap required-flags run -- entry | 0 )
    _amrun-op-xt _amrun-accounting-guard WITH-GUARD ;

\ Tool-count and disclosure-count changes share one transaction boundary.
\ A run may be referenced by more than one gateway, so per-gateway locking is
\ not sufficient here.  WITH-GUARD also releases this boundary if validation
\ or a future accounting backend throws.
: _AMRUN-TOOL-RESERVE  ( run -- status )
    DUP AMRUN-ACTIVE? 0= IF DROP AMRUN-S-INACTIVE EXIT THEN
    DUP AMRUN.MANDATE MAND.TOOL-BUDGET @ DUP 1 < IF
        2DROP AMRUN-S-BUDGET EXIT
    THEN
    OVER AMRUN.TOOLS-USED @ <= IF DROP AMRUN-S-BUDGET EXIT THEN
    1 SWAP AMRUN.TOOLS-USED +! AMRUN-S-OK ;

: _AMRUN-TOOL-REFUND  ( run -- )
    DUP AMRUN.TOOLS-USED @ 0> IF -1 SWAP AMRUN.TOOLS-USED +! ELSE DROP THEN ;

VARIABLE _AMD-N
VARIABLE _AMD-ENTRY
VARIABLE _AMD-RUN
VARIABLE _AMD-LIMIT
VARIABLE _AMDB-N
VARIABLE _AMDB-RUN
VARIABLE _AMDB-LIMIT

: _AMRUN-DISCLOSE-BYTES  ( bytes run -- status )
    _AMDB-RUN ! _AMDB-N !
    _AMDB-N @ 0< IF AMRUN-S-INVALID EXIT THEN
    _AMDB-RUN @ AMRUN-ACTIVE? 0= IF AMRUN-S-INACTIVE EXIT THEN
    _AMDB-RUN @ AMRUN.MANDATE MAND.DISCLOSURE-BUDGET @
        DUP _AMDB-LIMIT ! 1 < IF AMRUN-S-BUDGET EXIT THEN
    _AMDB-N @ _AMDB-LIMIT @ > IF AMRUN-S-BUDGET EXIT THEN
    _AMDB-RUN @ AMRUN.DISCLOSURE-USED @
        _AMDB-LIMIT @ _AMDB-N @ - > IF AMRUN-S-BUDGET EXIT THEN
    _AMDB-N @ _AMDB-RUN @ AMRUN.DISCLOSURE-USED +!
    AMRUN-S-OK ;

\ Release a prior disclosure reservation.  Cleanup is deliberately allowed
\ after a run has closed, provided its record is still alive; this is budget
\ accounting, not fresh authority.  Clamp defensively so a repeated cleanup
\ cannot drive the counter negative.
: _AMRUN-DISCLOSE-REFUND  ( bytes run -- )
    DUP 0= IF 2DROP EXIT THEN >R
    DUP 0< IF DROP R> DROP EXIT THEN
    R@ AMRUN.DISCLOSURE-USED @ MIN NEGATE
    R> AMRUN.DISCLOSURE-USED +! ;

: _AMRUN-DISCLOSE-RESERVE  ( bytes entry run -- status )
    _AMD-RUN ! _AMD-ENTRY ! _AMD-N !
    _AMD-N @ 0< IF AMRUN-S-INVALID EXIT THEN
    _AMD-RUN @ AMRUN-ACTIVE? 0= IF AMRUN-S-INACTIVE EXIT THEN
    _AMD-ENTRY @ CFENTRY-VALID? 0= IF AMRUN-S-INVALID EXIT THEN
    _AMD-ENTRY @ CFENTRY.FLAGS @ CFENTRY-F-DISCLOSE-RESULT AND 0= IF
        AMRUN-S-DENIED EXIT
    THEN
    _AMD-ENTRY @ CFENTRY.MAX-RESULT @ DUP _AMD-LIMIT !
    _AMD-N @ < IF AMRUN-S-BUDGET EXIT THEN
    _AMD-N @ _AMD-RUN @ _AMRUN-DISCLOSE-BYTES ;

' _AMRUN-TOOL-RESERVE CONSTANT _amrun-tool-reserve-xt
' _AMRUN-TOOL-REFUND CONSTANT _amrun-tool-refund-xt
' _AMRUN-DISCLOSE-BYTES CONSTANT _amrun-disclose-bytes-xt
' _AMRUN-DISCLOSE-REFUND CONSTANT _amrun-disclose-refund-xt
' _AMRUN-DISCLOSE-RESERVE CONSTANT _amrun-disclose-reserve-xt
' _AMRUN-CLOSE CONSTANT _amrun-close-xt
' _AMRUN-FREE CONSTANT _amrun-free-xt
' _AMRUN-RETAIN CONSTANT _amrun-retain-xt
' _AMRUN-RELEASE CONSTANT _amrun-release-xt

: AMRUN-CLOSE  ( run -- )
    _amrun-close-xt _amrun-accounting-guard WITH-GUARD ;

: AMRUN-FREE  ( run -- )
    _amrun-free-xt _amrun-accounting-guard WITH-GUARD ;

: AMRUN-RETAIN  ( run -- status )
    _amrun-retain-xt _amrun-accounting-guard WITH-GUARD ;

: AMRUN-RELEASE  ( run -- )
    _amrun-release-xt _amrun-accounting-guard WITH-GUARD ;

: AMRUN-TOOL-RESERVE  ( run -- status )
    _amrun-tool-reserve-xt _amrun-accounting-guard WITH-GUARD ;

: AMRUN-TOOL-REFUND  ( run -- )
    _amrun-tool-refund-xt _amrun-accounting-guard WITH-GUARD ;

: AMRUN-DISCLOSE-BYTES  ( bytes run -- status )
    _amrun-disclose-bytes-xt _amrun-accounting-guard WITH-GUARD ;

: AMRUN-DISCLOSE-REFUND  ( bytes run -- )
    _amrun-disclose-refund-xt _amrun-accounting-guard WITH-GUARD ;

: AMRUN-DISCLOSE-RESERVE  ( bytes entry run -- status )
    _amrun-disclose-reserve-xt _amrun-accounting-guard WITH-GUARD ;
