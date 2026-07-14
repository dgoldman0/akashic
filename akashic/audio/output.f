\ output.f — One-shot signed-PCM output for Megapad-64
\
\ This is the Akashic boundary for the board's buffer-oriented audio
\ device.  The hardware contract accepts interleaved signed PCM16 little
\ endian.  Akashic synthesis buffers conventionally contain FP16 bit
\ patterns in their 16-bit slots, so the FP16 entry point converts through
\ the canonical PCM-FP16>S16 policy before arming DMA.
\
\ Every submission is staged in driver-owned memory.  The staging block is
\ retained while STATUS.BUSY is set and is released only after the device
\ reports completion/error or acknowledges STOP.  This makes the raw entry
\ point safe even when its caller's source buffer is short-lived.
\
\ The shared device and staging state are serialized across core-0 tasks
\ with a blocking guard.  Mutating entry points reject worker-core calls
\ before touching MMIO or the core-0 allocator; snapshot queries remain
\ safe from any core.  Guard waits and device polling yield cooperatively.
\
\ Load with: REQUIRE audio/output.f
\
\ Public API:
\   AUDIO-OUT-PRESENT?       ( -- flag )
\   AUDIO-OUT-STATUS         ( -- status-bits )
\   AUDIO-OUT-CAPS           ( -- capability-bits )
\   AUDIO-OUT-GENERATION     ( -- u32 )
\   AUDIO-OUT-ERROR          ( -- device-error )
\   AUDIO-OUT-BUSY?          ( -- flag )
\   AUDIO-OUT-DONE?          ( -- flag )
\   AUDIO-OUT-PLAYING?       ( -- flag )
\   AUDIO-OUT-CAPTURE?       ( -- flag )
\   AUDIO-OUT-SINK?          ( -- flag )
\   AUDIO-OUT-SUBMIT-S16     ( addr frames rate chans timeout-ms -- status )
\   AUDIO-OUT-SUBMIT-FP16    ( buf timeout-ms -- status )
\   AUDIO-OUT-STOP           ( -- status )
\   AUDIO-OUT-CLEAR          ( -- status )

REQUIRE pcm.f
REQUIRE pcm-fp16.f
REQUIRE ../concurrency/guard.f

PROVIDED akashic-audio-output

\ =====================================================================
\  MMIO contract
\ =====================================================================

0xFFFFFF0000000C00 CONSTANT AUDIO-OUT-MMIO-BASE

AUDIO-OUT-MMIO-BASE        CONSTANT _AOUT-REG-CMD
AUDIO-OUT-MMIO-BASE  1 +   CONSTANT _AOUT-REG-STATUS
AUDIO-OUT-MMIO-BASE  2 +   CONSTANT _AOUT-REG-FORMAT
AUDIO-OUT-MMIO-BASE  3 +   CONSTANT _AOUT-REG-CHANS
AUDIO-OUT-MMIO-BASE  4 +   CONSTANT _AOUT-REG-RATE
AUDIO-OUT-MMIO-BASE  8 +   CONSTANT _AOUT-REG-DMA
AUDIO-OUT-MMIO-BASE 16 +   CONSTANT _AOUT-REG-FRAMES
AUDIO-OUT-MMIO-BASE 20 +   CONSTANT _AOUT-REG-GENERATION
AUDIO-OUT-MMIO-BASE 24 +   CONSTANT _AOUT-REG-ERROR
AUDIO-OUT-MMIO-BASE 25 +   CONSTANT _AOUT-REG-CAPS

1 CONSTANT AUDIO-OUT-CMD-SUBMIT
2 CONSTANT AUDIO-OUT-CMD-STOP
3 CONSTANT AUDIO-OUT-CMD-CLEAR

1 CONSTANT AUDIO-OUT-F-BUSY
2 CONSTANT AUDIO-OUT-F-DONE
4 CONSTANT AUDIO-OUT-F-ERROR
8 CONSTANT AUDIO-OUT-F-PLAYING
128 CONSTANT AUDIO-OUT-F-PRESENT

1 CONSTANT AUDIO-OUT-CAP-CAPTURE
2 CONSTANT AUDIO-OUT-CAP-SINK

1 CONSTANT AUDIO-OUT-FORMAT-S16LE

0 CONSTANT AUDIO-OUT-E-NONE
1 CONSTANT AUDIO-OUT-E-BUSY
2 CONSTANT AUDIO-OUT-E-FORMAT
3 CONSTANT AUDIO-OUT-E-CHANNELS
4 CONSTANT AUDIO-OUT-E-RATE
5 CONSTANT AUDIO-OUT-E-FRAMES
6 CONSTANT AUDIO-OUT-E-CAPACITY
7 CONSTANT AUDIO-OUT-E-MEMORY
8 CONSTANT AUDIO-OUT-E-SINK

\ Driver result codes.  DEVICE means that AUDIO-OUT-ERROR contains the
\ device-specific cause.  IO means that a catchable MMIO/allocator/library
\ exception interrupted the operation.
0 CONSTANT AUDIO-OUT-S-OK
1 CONSTANT AUDIO-OUT-S-ABSENT
2 CONSTANT AUDIO-OUT-S-INVALID
3 CONSTANT AUDIO-OUT-S-TOO-LARGE
4 CONSTANT AUDIO-OUT-S-BUSY
5 CONSTANT AUDIO-OUT-S-ALLOC
6 CONSTANT AUDIO-OUT-S-DEVICE
7 CONSTANT AUDIO-OUT-S-TIMEOUT
8 CONSTANT AUDIO-OUT-S-UNSUPPORTED
9 CONSTANT AUDIO-OUT-S-IO
10 CONSTANT AUDIO-OUT-S-CORE

1048576 CONSTANT AUDIO-OUT-MAX-BYTES
1000 CONSTANT _AOUT-CONTROL-LOCK-MS

\ =====================================================================
\  Safe, lock-free device snapshots
\ =====================================================================

\ A mapped device read is atomic at the width used here.  CATCH converts a
\ catchable absent-bus fault to zero.  Platforms whose bus fault cannot be
\ represented as a Forth exception must still provide the documented
\ unmapped-MMIO zero behavior.

: _AOUT-STATUS@  ( -- u )  _AOUT-REG-STATUS C@ ;
: _AOUT-CAPS@    ( -- u )  _AOUT-REG-CAPS C@ ;
: _AOUT-GEN@     ( -- u )  _AOUT-REG-GENERATION L@ ;
: _AOUT-ERROR@   ( -- u )  _AOUT-REG-ERROR C@ ;

: AUDIO-OUT-STATUS  ( -- status-bits )
    ['] _AOUT-STATUS@ CATCH ?DUP IF DROP 0 THEN ;

: AUDIO-OUT-CAPS  ( -- capability-bits )
    ['] _AOUT-CAPS@ CATCH ?DUP IF DROP 0 THEN ;

: AUDIO-OUT-GENERATION  ( -- u32 )
    ['] _AOUT-GEN@ CATCH ?DUP IF DROP 0 THEN ;

: AUDIO-OUT-ERROR  ( -- device-error )
    ['] _AOUT-ERROR@ CATCH ?DUP IF DROP 0 THEN ;

: AUDIO-OUT-PRESENT?  ( -- flag )
    AUDIO-OUT-STATUS AUDIO-OUT-F-PRESENT AND 0<> ;

: AUDIO-OUT-BUSY?  ( -- flag )
    AUDIO-OUT-STATUS AUDIO-OUT-F-BUSY AND 0<> ;

: AUDIO-OUT-DONE?  ( -- flag )
    AUDIO-OUT-STATUS AUDIO-OUT-F-DONE AND 0<> ;

: AUDIO-OUT-PLAYING?  ( -- flag )
    AUDIO-OUT-STATUS AUDIO-OUT-F-PLAYING AND 0<> ;

: AUDIO-OUT-CAPTURE?  ( -- flag )
    AUDIO-OUT-CAPS AUDIO-OUT-CAP-CAPTURE AND 0<> ;

: AUDIO-OUT-SINK?  ( -- flag )
    AUDIO-OUT-CAPS AUDIO-OUT-CAP-SINK AND 0<> ;

\ =====================================================================
\  Serialized submission state
\ =====================================================================

GUARD-BLOCKING _aout-guard

VARIABLE _AOUT-SRC
VARIABLE _AOUT-FRAMES
VARIABLE _AOUT-RATE
VARIABLE _AOUT-CHANS
VARIABLE _AOUT-TIMEOUT
VARIABLE _AOUT-BYTES
VARIABLE _AOUT-BUF
VARIABLE _AOUT-STAGE
VARIABLE _AOUT-STAGE-BYTES
VARIABLE _AOUT-INFLIGHT
VARIABLE _AOUT-DEADLINE

0 _AOUT-STAGE !
0 _AOUT-STAGE-BYTES !
0 _AOUT-INFLIGHT !

: _AOUT-FREE-STAGE  ( -- )
    \ Clear published ownership before entering the allocator.  If FREE
    \ itself throws, cleanup can still release the guard without leaving a
    \ stale pointer that a later call might free twice.
    _AOUT-STAGE @
    0 _AOUT-STAGE !
    0 _AOUT-STAGE-BYTES !
    0 _AOUT-INFLIGHT !
    ?DUP IF FREE THEN ;

\ Release a staging block only when it was never armed or the present
\ device has relinquished DMA ownership.  An absent/faulting device while
\ INFLIGHT is deliberately conservative: retaining at most 1 MiB is safer
\ than handing live DMA storage back to the allocator.
: _AOUT-REAP-STAGE  ( -- )
    _AOUT-STAGE @ 0= IF EXIT THEN
    _AOUT-INFLIGHT @ 0= IF _AOUT-FREE-STAGE EXIT THEN
    AUDIO-OUT-STATUS
    DUP AUDIO-OUT-F-PRESENT AND 0= IF DROP EXIT THEN
    AUDIO-OUT-F-BUSY AND IF EXIT THEN
    _AOUT-FREE-STAGE ;

: _AOUT-VALID-CHANS?  ( chans -- flag )
    DUP 1 = SWAP 2 = OR ;

\ Validate the normalized raw arguments and calculate the exact DMA span
\ without performing an overflowing multiply.
: _AOUT-VALIDATE  ( -- status )
    _AOUT-SRC @ 0= IF AUDIO-OUT-S-INVALID EXIT THEN
    _AOUT-FRAMES @ 1 < IF AUDIO-OUT-S-INVALID EXIT THEN
    _AOUT-RATE @ 8000 < IF AUDIO-OUT-S-INVALID EXIT THEN
    _AOUT-RATE @ 192000 > IF AUDIO-OUT-S-INVALID EXIT THEN
    _AOUT-CHANS @ _AOUT-VALID-CHANS? 0= IF
        AUDIO-OUT-S-INVALID EXIT
    THEN
    _AOUT-FRAMES @
    AUDIO-OUT-MAX-BYTES _AOUT-CHANS @ 2 * / > IF
        AUDIO-OUT-S-TOO-LARGE EXIT
    THEN
    _AOUT-FRAMES @ _AOUT-CHANS @ * 2 * _AOUT-BYTES !
    AUDIO-OUT-S-OK ;

\ Check the board before allocating or copying.  A retained in-flight
\ staging block means a previous timed-out device still owns its DMA span.
: _AOUT-PREPARE  ( -- status )
    AUDIO-OUT-PRESENT? 0= IF AUDIO-OUT-S-ABSENT EXIT THEN
    _AOUT-REAP-STAGE
    _AOUT-STAGE @ IF AUDIO-OUT-S-BUSY EXIT THEN
    AUDIO-OUT-BUSY? IF AUDIO-OUT-S-BUSY EXIT THEN
    AUDIO-OUT-CAPTURE? 0= IF AUDIO-OUT-S-UNSUPPORTED EXIT THEN
    AUDIO-OUT-PLAYING? IF
        AUDIO-OUT-CMD-STOP _AOUT-REG-CMD C!
        \ STOP retains older diagnostics by contract.  Only continuing
        \ playback proves that release failed; a later valid SUBMIT will
        \ replace a stale error with its own result.
        AUDIO-OUT-PLAYING? IF
            AUDIO-OUT-S-DEVICE EXIT
        THEN
    THEN
    AUDIO-OUT-S-OK ;

: _AOUT-ALLOC-STAGE  ( -- status )
    _AOUT-BYTES @ ALLOCATE
    DUP IF 2DROP AUDIO-OUT-S-ALLOC EXIT THEN
    DROP _AOUT-STAGE !
    _AOUT-BYTES @ _AOUT-STAGE-BYTES !
    0 _AOUT-INFLIGHT !
    AUDIO-OUT-S-OK ;

\ Poll only while holding the device guard, never a preemption critical
\ section.  STOP is the ownership barrier on timeout; if a future device
\ keeps BUSY asserted after STOP, _AOUT-REAP-STAGE retains the block.
: _AOUT-POLL  ( -- status )
    EPOCH@ _AOUT-TIMEOUT @ + _AOUT-DEADLINE !
    BEGIN
        AUDIO-OUT-STATUS
        DUP AUDIO-OUT-F-PRESENT AND 0= IF
            DROP AUDIO-OUT-S-ABSENT EXIT
        THEN
        DUP AUDIO-OUT-F-ERROR AND IF
            DROP AUDIO-OUT-S-DEVICE EXIT
        THEN
        AUDIO-OUT-F-DONE AND IF AUDIO-OUT-S-OK EXIT THEN
        EPOCH@ _AOUT-DEADLINE @ >= IF
            AUDIO-OUT-CMD-STOP _AOUT-REG-CMD C!
            AUDIO-OUT-S-TIMEOUT EXIT
        THEN
        YIELD?
    AGAIN ;

: _AOUT-SUBMIT-STAGE  ( -- status )
    AUDIO-OUT-FORMAT-S16LE _AOUT-REG-FORMAT C!
    _AOUT-CHANS @ _AOUT-REG-CHANS C!
    _AOUT-RATE @ _AOUT-REG-RATE L!
    _AOUT-STAGE @ _AOUT-REG-DMA !
    _AOUT-FRAMES @ _AOUT-REG-FRAMES L!
    \ Publish conservative ownership before the command write.  The MMIO
    \ implementation may begin synchronous DMA/capture work inside C!, so
    \ an exception from that write must never make cleanup treat the stage
    \ as an unarmed allocation.
    1 _AOUT-INFLIGHT !
    AUDIO-OUT-CMD-SUBMIT _AOUT-REG-CMD C!
    _AOUT-POLL
    >R _AOUT-REAP-STAGE R> ;

: _AOUT-S16-BODY  ( -- status )
    _AOUT-VALIDATE DUP IF EXIT THEN DROP
    _AOUT-PREPARE DUP IF EXIT THEN DROP
    _AOUT-ALLOC-STAGE DUP IF EXIT THEN DROP
    _AOUT-SRC @ _AOUT-STAGE @ _AOUT-BYTES @ CMOVE
    _AOUT-SUBMIT-STAGE ;

: _AOUT-DESCRIBE-FP16  ( -- status )
    _AOUT-BUF @ DUP 0= IF DROP AUDIO-OUT-S-INVALID EXIT THEN
    DUP PCM-FP16? 0= IF DROP AUDIO-OUT-S-INVALID EXIT THEN
    DUP PCM-DATA _AOUT-SRC !
    DUP PCM-LEN _AOUT-FRAMES !
    DUP PCM-RATE _AOUT-RATE !
    PCM-CHANS _AOUT-CHANS !
    _AOUT-VALIDATE ;

: _AOUT-CONVERT-FP16  ( -- )
    _AOUT-FRAMES @ _AOUT-CHANS @ * 0 ?DO
        _AOUT-SRC @ I 2 * + W@
        PCM-FP16>S16
        _AOUT-STAGE @ I 2 * + W!
    LOOP ;

: _AOUT-FP16-BODY  ( -- status )
    _AOUT-DESCRIBE-FP16 DUP IF EXIT THEN DROP
    _AOUT-PREPARE DUP IF EXIT THEN DROP
    _AOUT-ALLOC-STAGE DUP IF EXIT THEN DROP
    _AOUT-CONVERT-FP16
    _AOUT-SUBMIT-STAGE ;

: _AOUT-RELEASE-GUARD  ( -- )
    _aout-guard GUARD-RELEASE ;

\ CATCH protects guard ownership and reclaims any unarmed or completed
\ staging block before returning a stable driver status.  Cleanup and guard
\ release are separate caught phases so an allocator/reaper exception cannot
\ strand the blocking guard.  Cleanup failures take precedence over a body
\ result because driver ownership can no longer be guaranteed completely.
: _AOUT-CALL-LOCKED  ( xt -- status )
    CATCH ?DUP IF DROP AUDIO-OUT-S-IO THEN
    >R
    ['] _AOUT-REAP-STAGE CATCH ?DUP IF
        DROP R> DROP AUDIO-OUT-S-IO >R
    THEN
    ['] _AOUT-RELEASE-GUARD CATCH ?DUP IF
        DROP R> DROP AUDIO-OUT-S-IO >R
    THEN
    R> ;

\ AUDIO-OUT-SUBMIT-S16
\ Copy raw interleaved signed-PCM16 little-endian into driver staging and
\ submit it synchronously.  The caller may reuse addr after this word
\ returns.  timeout-ms bounds guard acquisition and post-command status
\ polling separately; it cannot interrupt a synchronous MMIO command/sink.
: AUDIO-OUT-SUBMIT-S16  ( addr frames rate chans timeout-ms -- status )
    COREID 0<> IF
        DROP 2DROP 2DROP AUDIO-OUT-S-CORE EXIT
    THEN
    DUP 0< IF
        DROP 2DROP 2DROP AUDIO-OUT-S-INVALID EXIT
    THEN
    >R
    _aout-guard R@ GUARD-ACQUIRE-TIMEOUT 0= IF
        R> DROP 2DROP 2DROP AUDIO-OUT-S-BUSY EXIT
    THEN
    R> _AOUT-TIMEOUT !
    _AOUT-CHANS !
    _AOUT-RATE !
    _AOUT-FRAMES !
    _AOUT-SRC !
    ['] _AOUT-S16-BODY _AOUT-CALL-LOCKED ;

\ AUDIO-OUT-SUBMIT-FP16
\ Accept a 16-bit mono/stereo PCM descriptor whose sample slots contain
\ normalized FP16 values.  Conversion uses the frozen PCM-FP16>S16 policy.
: AUDIO-OUT-SUBMIT-FP16  ( buf timeout-ms -- status )
    COREID 0<> IF 2DROP AUDIO-OUT-S-CORE EXIT THEN
    DUP 0< IF 2DROP AUDIO-OUT-S-INVALID EXIT THEN
    >R
    _aout-guard R@ GUARD-ACQUIRE-TIMEOUT 0= IF
        R> DROP DROP AUDIO-OUT-S-BUSY EXIT
    THEN
    R> _AOUT-TIMEOUT !
    _AOUT-BUF !
    ['] _AOUT-FP16-BODY _AOUT-CALL-LOCKED ;

: _AOUT-STOP-BODY  ( -- status )
    AUDIO-OUT-PRESENT? 0= IF AUDIO-OUT-S-ABSENT EXIT THEN
    AUDIO-OUT-CMD-STOP _AOUT-REG-CMD C!
    _AOUT-REAP-STAGE
    AUDIO-OUT-STATUS AUDIO-OUT-F-ERROR AND IF
        AUDIO-OUT-S-DEVICE EXIT
    THEN
    AUDIO-OUT-S-OK ;

: _AOUT-CLEAR-BODY  ( -- status )
    AUDIO-OUT-PRESENT? 0= IF AUDIO-OUT-S-ABSENT EXIT THEN
    AUDIO-OUT-CMD-CLEAR _AOUT-REG-CMD C!
    _AOUT-REAP-STAGE
    AUDIO-OUT-STATUS AUDIO-OUT-F-ERROR AND IF
        AUDIO-OUT-S-DEVICE EXIT
    THEN
    AUDIO-OUT-S-OK ;

: AUDIO-OUT-STOP  ( -- status )
    COREID 0<> IF AUDIO-OUT-S-CORE EXIT THEN
    _aout-guard _AOUT-CONTROL-LOCK-MS GUARD-ACQUIRE-TIMEOUT 0= IF
        AUDIO-OUT-S-BUSY EXIT
    THEN
    ['] _AOUT-STOP-BODY _AOUT-CALL-LOCKED ;

: AUDIO-OUT-CLEAR  ( -- status )
    COREID 0<> IF AUDIO-OUT-S-CORE EXIT THEN
    _aout-guard _AOUT-CONTROL-LOCK-MS GUARD-ACQUIRE-TIMEOUT 0= IF
        AUDIO-OUT-S-BUSY EXIT
    THEN
    ['] _AOUT-CLEAR-BODY _AOUT-CALL-LOCKED ;
