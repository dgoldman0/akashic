\ contract-vm.f — Blockchain Contract VM for Megapad-64
\
\ Consumes akashic/utils/itc.f to execute sandboxed Forth contracts
\ on-chain.  Adds arena management, bounds-checked memory, gas
\ metering, chain-state words, contract storage, deploy/call API,
\ and TX integration.
\
\ Prefix: VM-   (public API)
\         _VM-  (internal helpers)
\
\ Load with:   REQUIRE store/contract-vm.f

REQUIRE ../utils/itc.f
REQUIRE ../store/state.f
REQUIRE ../store/block.f
REQUIRE ../consensus/consensus.f
REQUIRE ../store/tx.f
REQUIRE ../math/sha3.f
PROVIDED akashic-contract-vm

\ =====================================================================
\  1. Constants
\ =====================================================================

5 CONSTANT TX-DEPLOY          \ data[0] = deploy contract
6 CONSTANT TX-CALL            \ data[0] = call contract

\ Arena region sizes (bytes)
4096 CONSTANT _VM-ARENA-DATA-SZ
4096 CONSTANT _VM-ARENA-CODE-SZ
2048 CONSTANT _VM-ARENA-RSTK-SZ

\ Total arena = 10240 bytes
_VM-ARENA-DATA-SZ _VM-ARENA-CODE-SZ + _VM-ARENA-RSTK-SZ +
    CONSTANT _VM-ARENA-TOTAL

\ Fault codes (extend ITC-FAULT-* range, which uses 0–4)
10 CONSTANT VM-FAULT-OOB       \ out-of-bounds memory access
11 CONSTANT VM-FAULT-GAS       \ gas exhausted
12 CONSTANT VM-FAULT-NO-CODE   \ contract not found
13 CONSTANT VM-FAULT-DEPLOY    \ deployment error
14 CONSTANT VM-FAULT-STORAGE   \ contract storage full

\ Contract storage limits
256 CONSTANT _VM-STORE-SLOTS   \ max key-value slots per contract

\ Code map capacity
256 CONSTANT _VM-CODE-MAX

\ Gas defaults
1000000 CONSTANT VM-DEFAULT-GAS

\ =====================================================================
\  2. Code Map
\ =====================================================================
\
\ Maps contract address → (XMEM code-blob pointer, length).
\ A code blob is a serialized ITC image (via ITC-SAVE-IMAGE).
\ Max 256 contracts.  Linear scan for MVP.
\
\ Layout per entry: [32 B addr][1 cell ptr][1 cell len][1 cell store-ptr]
\ store-ptr = XMEM pointer to contract storage region, or 0.

56 CONSTANT _VM-CM-ESZ         \ 32 + 8 + 8 + 8 = 56
CREATE _VM-CODE-MAP  _VM-CODE-MAX _VM-CM-ESZ * ALLOT
VARIABLE _VM-CODE-COUNT

: _VM-CM-ENTRY  ( idx -- addr )
    _VM-CM-ESZ * _VM-CODE-MAP + ;

: _VM-CM-FIND  ( addr -- idx -1 | 0 )
    _VM-CODE-COUNT @ 0 ?DO
        DUP 32 I _VM-CM-ENTRY 32 COMPARE 0= IF
            DROP I -1 UNLOOP EXIT
        THEN
    LOOP
    DROP 0 ;

: _VM-CM-ADD  ( addr code-ptr code-len -- flag )
    _VM-CODE-COUNT @ _VM-CODE-MAX >= IF DROP 2DROP 0 EXIT THEN
    _VM-CODE-COUNT @ _VM-CM-ENTRY     ( addr ptr len entry )
    >R
    R@ 40 + !                         \ code-len at +40
    R@ 32 + !                         \ code-ptr at +32
    R@ 32 CMOVE                       \ 32-byte addr at +0
    0 R> 48 + !                       \ store-ptr = 0
    1 _VM-CODE-COUNT +!
    -1 ;

: _VM-CM-PTR@   ( idx -- ptr )   _VM-CM-ENTRY 32 + @ ;
: _VM-CM-LEN@   ( idx -- len )   _VM-CM-ENTRY 40 + @ ;
: _VM-CM-STORE@ ( idx -- ptr )   _VM-CM-ENTRY 48 + @ ;
: _VM-CM-STORE! ( ptr idx -- )   _VM-CM-ENTRY 48 + ! ;

\ =====================================================================
\  3. Arena Management
\ =====================================================================
\
\ Three regions in one XMEM allocation:
\   [ data (4 KB) | ITC code (4 KB) | R-stack (2 KB) ]
\ The data region is the ONLY region writable by the contract.

VARIABLE _VM-ARENA-BASE
VARIABLE _VM-ARENA-DATA-END
VARIABLE _VM-ARENA-CODE-BASE
VARIABLE _VM-ARENA-CODE-END
VARIABLE _VM-ARENA-RSTK-BASE
VARIABLE _VM-ARENA-RSTK-END
VARIABLE _VM-ARENA-HWM        \ lazy-zero high water mark (data)

: _VM-ARENA-ALLOC  ( -- flag )
    _VM-ARENA-TOTAL XMEM-ALLOT
    DUP 0= IF EXIT THEN              ( addr )
    DUP _VM-ARENA-BASE !             ( addr )
    _VM-ARENA-DATA-SZ +              ( data-end )
    DUP _VM-ARENA-DATA-END !         ( data-end=code-base )
    DUP _VM-ARENA-CODE-BASE !        ( code-base )
    _VM-ARENA-CODE-SZ +              ( code-end )
    DUP _VM-ARENA-CODE-END !         ( code-end=rstk-base )
    DUP _VM-ARENA-RSTK-BASE !        ( rstk-base )
    _VM-ARENA-RSTK-SZ +              ( rstk-end )
    _VM-ARENA-RSTK-END !             ( )
    _VM-ARENA-BASE @ _VM-ARENA-HWM !
    -1 ;

: _VM-ARENA-FREE  ( -- )
    _VM-ARENA-BASE @ ?DUP IF
        _VM-ARENA-TOTAL XMEM-FREE-BLOCK
        0 _VM-ARENA-BASE !
    THEN ;

\ =====================================================================
\  4. Bounds-Checked Memory Operations
\ =====================================================================
\
\ VM-@ / VM-! only touch the data region [base, base+4096).
\ Reads above HWM return 0 (lazy zero).  Writes advance HWM.

VARIABLE _VM-FAULT-CODE

: _VM-DATA-BOUNDS?  ( addr -- addr flag )
    DUP _VM-ARENA-BASE @ >=
    OVER _VM-ARENA-DATA-END @ < AND
    OVER 7 AND 0= AND ;

: _VM-CBOUNDS?  ( addr -- addr flag )
    DUP _VM-ARENA-BASE @ >=
    OVER _VM-ARENA-DATA-END @ < AND ;

: VM-@  ( addr -- val )
    _VM-DATA-BOUNDS? 0= IF
        DROP 0  VM-FAULT-OOB _VM-FAULT-CODE !  EXIT
    THEN
    DUP _VM-ARENA-HWM @ >= IF DROP 0 EXIT THEN
    @ ;

: VM-!  ( val addr -- )
    _VM-DATA-BOUNDS? 0= IF
        2DROP  VM-FAULT-OOB _VM-FAULT-CODE !  EXIT
    THEN
    DUP CELL+ _VM-ARENA-HWM @ > IF
        DUP CELL+ _VM-ARENA-HWM !
    THEN
    ! ;

: VM-C@  ( addr -- c )
    _VM-CBOUNDS? 0= IF
        DROP 0  VM-FAULT-OOB _VM-FAULT-CODE !  EXIT
    THEN
    DUP _VM-ARENA-HWM @ >= IF DROP 0 EXIT THEN
    C@ ;

: VM-C!  ( c addr -- )
    _VM-CBOUNDS? 0= IF
        2DROP  VM-FAULT-OOB _VM-FAULT-CODE !  EXIT
    THEN
    DUP 1+ _VM-ARENA-HWM @ > IF
        DUP 1+ _VM-ARENA-HWM !
    THEN
    C! ;

\ =====================================================================
\  5. Gas Metering
\ =====================================================================

VARIABLE _VM-GAS
VARIABLE _VM-GAS-USED
VARIABLE _VM-FAILED

CREATE _VM-GAS-TABLE  ITC-WL-MAX ALLOT  \ 1 byte per WL entry

: _VM-BURN  ( n -- )
    _VM-GAS-USED @ + DUP _VM-GAS-USED !
    _VM-GAS @ SWAP -
    DUP 0< IF DROP 0 _VM-GAS ! -1 _VM-FAILED !
    ELSE _VM-GAS ! THEN ;

: _VM-WL-GAS@  ( index -- cost )
    _VM-GAS-TABLE + C@ ;

: _VM-GAS-HOOK  ( index -- continue-flag )
    _VM-WL-GAS@ _VM-BURN
    _VM-FAILED @ 0= ;

\ =====================================================================
\  6. Execution Context
\ =====================================================================

VARIABLE _VM-CTX-BLOCKTIME
VARIABLE _VM-CTX-HEIGHT
VARIABLE _VM-CTX-STORE-IDX    \ code-map index of executing contract

CREATE _VM-ADDR-BUF  40 ALLOT   \ for address derivation
CREATE _VM-ADDR-OUT  32 ALLOT   \ SHA3 output

CREATE _VM-RET-BUF  256 ALLOT   \ VM-RETURN data
VARIABLE _VM-RET-LEN

CREATE _VM-CALLER-ADDR 32 ALLOT
CREATE _VM-SELF-ADDR   32 ALLOT

\ =====================================================================
\  7. Chain State Words
\ =====================================================================

: VM-BALANCE  ( -- n )
    5 _VM-BURN  _VM-CALLER-ADDR ST-BALANCE@ ;

: VM-SELF-BALANCE  ( -- n )
    5 _VM-BURN  _VM-SELF-ADDR ST-BALANCE@ ;

: VM-CALLER  ( -- addr )   _VM-CALLER-ADDR ;
: VM-SELF    ( -- addr )   _VM-SELF-ADDR ;
: VM-BLOCK#  ( -- n )      _VM-CTX-HEIGHT @ ;
: VM-BLOCK-TIME ( -- t )   _VM-CTX-BLOCKTIME @ ;

: VM-SHA3  ( addr len -- hash-addr hash-len )
    20 _VM-BURN
    _VM-ADDR-OUT SHA3-256-HASH
    _VM-ADDR-OUT 32 ;

: VM-LOG  ( addr len -- )
    5 _VM-BURN  TYPE ;

: VM-RETURN  ( addr len -- )
    1 _VM-BURN
    DUP 256 > IF 2DROP EXIT THEN
    DUP _VM-RET-LEN !
    _VM-RET-BUF SWAP CMOVE ;

: VM-REVERT  ( addr len -- )
    1 _VM-BURN
    DUP 256 > IF 2DROP ELSE
        DUP _VM-RET-LEN !
        _VM-RET-BUF SWAP CMOVE
    THEN
    -1 _VM-FAILED ! ;

\ =====================================================================
\  8. Contract Storage
\ =====================================================================
\
\ Per-contract key→value map.  Allocated lazily in XMEM on first
\ VM-ST-PUT.  Layout: [8B count][256 × (8B key, 8B value)] = 4104 B.

_VM-STORE-SLOTS 16 * 8 + CONSTANT _VM-STORE-SIZE

: _VM-STORE-ENSURE  ( -- ptr | 0 )
    _VM-CTX-STORE-IDX @ _VM-CM-STORE@ ?DUP IF EXIT THEN
    _VM-STORE-SIZE XMEM-ALLOT
    DUP 0= IF EXIT THEN
    DUP _VM-STORE-SIZE 0 FILL
    DUP _VM-CTX-STORE-IDX @ _VM-CM-STORE! ;

: _VM-STORE-SCAN  ( key store-ptr -- slot-addr -1 | 0 )
    DUP @ >R  8 +                     \ skip count → first slot
    R> 0 ?DO
        2DUP @ = IF NIP -1 UNLOOP EXIT THEN
        16 +
    LOOP
    2DROP 0 ;

: VM-ST-GET  ( key -- val flag )
    10 _VM-BURN
    _VM-CTX-STORE-IDX @ _VM-CM-STORE@
    DUP 0= IF DROP 0 0 EXIT THEN
    SWAP OVER _VM-STORE-SCAN IF 8 + @ -1 ELSE DROP 0 0 THEN ;

: VM-ST-PUT  ( val key -- )
    20 _VM-BURN
    _VM-STORE-ENSURE DUP 0= IF DROP 2DROP EXIT THEN
    OVER OVER _VM-STORE-SCAN IF       ( val key slot-addr )
        NIP 8 + ! EXIT                \ update existing
    THEN                              ( val key store-ptr )
    DUP @ _VM-STORE-SLOTS >= IF
        DROP 2DROP VM-FAULT-STORAGE _VM-FAULT-CODE ! EXIT
    THEN
    DUP >R                            ( val key store  R: store )
    DUP @ 16 * 8 + OVER +            ( val key store slot-addr )
    NIP                               ( val key slot-addr )
    DUP ROT SWAP !                    ( val slot  -- key stored )
    8 + !                             ( -- val stored )
    1 R> +! ;

: VM-ST-HAS?  ( key -- flag )
    5 _VM-BURN
    _VM-CTX-STORE-IDX @ _VM-CM-STORE@
    DUP 0= IF DROP 0 EXIT THEN
    SWAP OVER _VM-STORE-SCAN IF DROP -1 ELSE DROP 0 THEN ;

: VM-TRANSFER  ( amount to-addr -- flag )
    20 _VM-BURN
    OVER _VM-SELF-ADDR ST-BALANCE@ > IF 2DROP 0 EXIT THEN
    \ MVP placeholder — full balance mutation requires deeper
    \ state.f integration (field-level writes).
    2DROP -1 ;

\ =====================================================================
\  9. Whitelist Population
\ =====================================================================

: _VM-REG  ( xt gas c-addr u -- )
    >R >R                             ( xt gas  R: u c-addr )
    SWAP 0 R> R>                      ( gas xt 0 c-addr u )
    ITC-WL-ADD                        ( gas )
    _ITC-WL-COUNT @ 1- _VM-GAS-TABLE + C! ;

: _VM-REGISTER-CORE  ( -- )
    ITC-WL-RESET
    _VM-GAS-TABLE ITC-WL-MAX 0 FILL

    \ ── Stack (gas=1) ──
    ['] DUP     1 S" DUP"     _VM-REG
    ['] DROP    1 S" DROP"    _VM-REG
    ['] SWAP    1 S" SWAP"    _VM-REG
    ['] OVER    1 S" OVER"    _VM-REG
    ['] ROT     1 S" ROT"     _VM-REG
    ['] NIP     1 S" NIP"     _VM-REG
    ['] TUCK    1 S" TUCK"    _VM-REG
    ['] 2DUP    1 S" 2DUP"    _VM-REG
    ['] 2DROP   1 S" 2DROP"   _VM-REG
    ['] 2SWAP   1 S" 2SWAP"   _VM-REG
    ['] 2OVER   1 S" 2OVER"   _VM-REG

    \ ── Arithmetic (gas=1) ──
    ['] +       1 S" +"       _VM-REG
    ['] -       1 S" -"       _VM-REG
    ['] *       1 S" *"       _VM-REG
    ['] /       1 S" /"       _VM-REG
    ['] MOD     1 S" MOD"     _VM-REG
    ['] /MOD    1 S" /MOD"    _VM-REG
    ['] NEGATE  1 S" NEGATE"  _VM-REG
    ['] ABS     1 S" ABS"     _VM-REG
    ['] MIN     1 S" MIN"     _VM-REG
    ['] MAX     1 S" MAX"     _VM-REG
    ['] 1+      1 S" 1+"      _VM-REG
    ['] 1-      1 S" 1-"      _VM-REG

    \ ── Comparison (gas=1) ──
    ['] =       1 S" ="       _VM-REG
    ['] <>      1 S" <>"      _VM-REG
    ['] <       1 S" <"       _VM-REG
    ['] >       1 S" >"       _VM-REG
    ['] 0=      1 S" 0="      _VM-REG
    ['] 0<      1 S" 0<"      _VM-REG
    ['] 0>      1 S" 0>"      _VM-REG

    \ ── Logic (gas=1) ──
    ['] AND     1 S" AND"     _VM-REG
    ['] OR      1 S" OR"      _VM-REG
    ['] XOR     1 S" XOR"     _VM-REG
    ['] INVERT  1 S" INVERT"  _VM-REG
    ['] LSHIFT  1 S" LSHIFT"  _VM-REG
    ['] RSHIFT  1 S" RSHIFT"  _VM-REG

    \ ── Bounded memory (gas=2) ──
    ['] VM-@    2 S" @"       _VM-REG
    ['] VM-!    2 S" !"       _VM-REG
    ['] VM-C@   2 S" C@"      _VM-REG
    ['] VM-C!   2 S" C!"      _VM-REG

    \ ── Output (gas=1–5) ──
    ['] .       1 S" ."       _VM-REG
    ['] EMIT    1 S" EMIT"    _VM-REG
    ['] CR      1 S" CR"      _VM-REG
    ['] SPACE   1 S" SPACE"   _VM-REG
    ['] TYPE    5 S" TYPE"    _VM-REG

    \ ── Chain state (gas=1–20) ──
    ['] VM-BALANCE      5  S" VM-BALANCE"      _VM-REG
    ['] VM-SELF-BALANCE 5  S" VM-SELF-BALANCE" _VM-REG
    ['] VM-CALLER       1  S" VM-CALLER"       _VM-REG
    ['] VM-SELF         1  S" VM-SELF"         _VM-REG
    ['] VM-BLOCK#       1  S" VM-BLOCK#"       _VM-REG
    ['] VM-BLOCK-TIME   1  S" VM-BLOCK-TIME"   _VM-REG
    ['] VM-SHA3         20 S" VM-SHA3"         _VM-REG
    ['] VM-LOG          5  S" VM-LOG"          _VM-REG
    ['] VM-RETURN       1  S" VM-RETURN"       _VM-REG
    ['] VM-REVERT       1  S" VM-REVERT"       _VM-REG

    \ ── Contract storage (gas=5–20) ──
    ['] VM-ST-GET       10 S" VM-ST-GET"       _VM-REG
    ['] VM-ST-PUT       20 S" VM-ST-PUT"       _VM-REG
    ['] VM-ST-HAS?      5  S" VM-ST-HAS?"      _VM-REG

    \ ── Transfer (gas=20) ──
    ['] VM-TRANSFER     20 S" VM-TRANSFER"     _VM-REG
    ;

\ =====================================================================
\  10. Deploy & Call API
\ =====================================================================

VARIABLE _VM-DEP-TMP          \ temp XMEM buffer during deploy
VARIABLE _VM-DEP-ILEN         \ serialized image length
VARIABLE _VM-DEP-PERM         \ permanent XMEM blob address

: VM-DEPLOY  ( src len -- contract-addr | 0 )
    0 _VM-DEP-TMP !  0 _VM-DEP-ILEN !  0 _VM-DEP-PERM !

    \ 1. Allocate arena
    _VM-ARENA-ALLOC 0= IF 2DROP 0 EXIT THEN

    \ 2. Set data ptrs so VARIABLE doesn't crash during compile
    \    (VARIABLE values are NOT persistent across calls — use
    \    VM-ST-PUT / VM-ST-GET for persistent contract storage.)
    _VM-ARENA-BASE @ _ITC-DATA-PTR !
    _VM-ARENA-DATA-END @ _ITC-DATA-END !

    \ 3. Compile source into arena code region
    _VM-ARENA-CODE-BASE @ _VM-ARENA-CODE-SZ ITC-COMPILE
    DUP -1 = IF DROP _VM-ARENA-FREE 0 EXIT THEN
    DROP                              \ discard entry-count

    \ 4. Serialize ITC image to temp XMEM buffer
    _VM-ARENA-CODE-SZ 2* XMEM-ALLOT
    DUP 0= IF _VM-ARENA-FREE 0 EXIT THEN
    DUP _VM-DEP-TMP !

    _ITC-BUF-BASE @
    _ITC-CP @ _ITC-BUF-BASE @ -
    ITC-SAVE-IMAGE                    ( total-len )
    DUP _VM-DEP-ILEN !

    \ 5. Allocate permanent code blob
    DUP XMEM-ALLOT                   ( total-len perm-or-0 )
    DUP 0= IF
        2DROP                         \ drop 0 and total-len
        _VM-DEP-TMP @  _VM-ARENA-CODE-SZ 2*  XMEM-FREE-BLOCK
        _VM-ARENA-FREE 0 EXIT
    THEN
    DUP _VM-DEP-PERM !               ( total-len perm )

    \ 6. Copy temp → permanent
    _VM-DEP-TMP @  OVER  _VM-DEP-ILEN @  CMOVE
    \   CMOVE ( src dst u -- ) → copies from tmp to perm

    \ 7. Free temp buffer + arena
    _VM-DEP-TMP @  _VM-ARENA-CODE-SZ 2*  XMEM-FREE-BLOCK
    _VM-ARENA-FREE                    ( total-len perm )

    \ 8. Derive contract address = SHA3(caller-addr || nonce)
    _VM-CALLER-ADDR _VM-ADDR-BUF 32 CMOVE
    _VM-CALLER-ADDR ST-NONCE@ _VM-ADDR-BUF 32 + !
    _VM-ADDR-BUF 40 _VM-ADDR-OUT SHA3-256-HASH

    \ 9. Register in code map: ( addr code-ptr code-len -- flag )
    \   Stack is: total-len perm-addr.
    \   Need:     addr-out  perm-addr total-len
    SWAP _VM-ADDR-OUT -ROT            ( addr perm total )
    _VM-CM-ADD 0= IF 0 EXIT THEN

    \ 10. Return contract address pointer
    _VM-ADDR-OUT ;

\ ── VM-CALL ──

VARIABLE _VM-CALL-EADDR       \ entry name addr
VARIABLE _VM-CALL-ELEN        \ entry name len

: VM-CALL  ( contract-addr entry-addr entry-len gas -- fault-code )
    \ ── Set up gas & fault state ──
    _VM-GAS !  0 _VM-GAS-USED !  0 _VM-FAILED !
    0 _VM-FAULT-CODE !  0 _VM-RET-LEN !
    _VM-CALL-ELEN !  _VM-CALL-EADDR !
    \   Stack: contract-addr

    \ ── Look up contract in code map ──
    DUP _VM-CM-FIND 0= IF DROP VM-FAULT-NO-CODE EXIT THEN
    DUP _VM-CTX-STORE-IDX !          ( caddr cm-idx )
    SWAP _VM-SELF-ADDR 32 CMOVE      ( cm-idx )

    \ ── Set block context ──
    CHAIN-HEIGHT _VM-CTX-HEIGHT !

    \ ── Fetch code blob coordinates ──
    DUP _VM-CM-PTR@ SWAP _VM-CM-LEN@ ( code-ptr code-len )

    \ ── Allocate arena ──
    _VM-ARENA-ALLOC 0= IF 2DROP VM-FAULT-DEPLOY EXIT THEN

    \ ── Load ITC image ──
    ITC-LOAD-IMAGE
    DUP 0= IF DROP _VM-ARENA-FREE VM-FAULT-NO-CODE EXIT THEN
    DROP                              ( body-addr body-len )

    \ ── Copy body → arena code region ──
    _VM-ARENA-CODE-BASE @ SWAP        ( body-addr arena-code body-len )
    DUP >R                            ( body-addr arena-code body-len  R: blen )
    CMOVE                             ( -- )
    \   body-addr → arena-code, blen bytes
    R>                                ( blen )

    \ ── Save old BUF-BASE (compile-time) before overwriting ──
    _ITC-BUF-BASE @                   ( blen old-buf-base )

    \ ── Point ITC buffer at arena code ──
    _VM-ARENA-CODE-BASE @ _ITC-BUF-BASE !
    _VM-ARENA-CODE-BASE @ ROT + _ITC-BUF-END !
    \   buf-end = arena-code-base + body-len
    \   Stack: ( old-buf-base )

    \ ── Resolve entry name ──
    \   Entry table stores compile-time absolute offsets; convert
    \   to arena-relative by subtracting old BUF-BASE, then add
    \   the new arena code base.
    _VM-CALL-EADDR @ _VM-CALL-ELEN @ _ITC-ENT-FIND
    0= IF DROP _VM-ARENA-FREE ITC-FAULT-COMPILE EXIT THEN
    SWAP -                            ( entry-abs - old-base = rel-off )
    _VM-ARENA-CODE-BASE @ +           ( absolute-ip )

    \ ── Install gas hook & data region ──
    ['] _VM-GAS-HOOK _ITC-PRE-DISPATCH-XT !
    _VM-ARENA-BASE @      _ITC-DATA-PTR !
    _VM-ARENA-DATA-END @  _ITC-DATA-END !

    \ ── Execute ──
    _VM-ARENA-RSTK-BASE @ _VM-ARENA-RSTK-SZ ITC-EXECUTE

    \ ── Clean up ──
    0 _ITC-PRE-DISPATCH-XT !
    _VM-ARENA-FREE

    \ ── Override fault if gas exhausted ──
    _VM-FAILED @ IF DROP VM-FAULT-GAS THEN ;

\ =====================================================================
\  10b. Transaction Integration
\ =====================================================================

VARIABLE _VM-PREV-TX-EXT

: _VM-DO-DEPLOY  ( tx sender-idx -- flag )
    DROP
    DUP TX-DATA@ 1+                   ( tx src )
    SWAP TX-DATA-LEN@ 1-              ( src len )
    DUP 1 < IF 2DROP 0 EXIT THEN
    VM-DEPLOY 0<> ;

: _VM-DO-CALL  ( tx sender-idx -- flag )
    DROP
    DUP TX-DATA-LEN@ 34 < IF DROP 0 EXIT THEN
    DUP TX-DATA@ 1+                   ( tx contract-addr )
    SWAP DUP TX-DATA@ 33 +            ( caddr tx entry-start )
    SWAP TX-DATA-LEN@ 33 -            ( caddr entry-addr entry-len )
    VM-DEFAULT-GAS VM-CALL 0= ;

: _VM-TX-EXT  ( tx sender-idx -- flag )
    OVER TX-DATA-LEN@ 1 < IF 2DROP 0 EXIT THEN
    OVER TX-DATA@ C@
    DUP TX-DEPLOY = IF
        DROP
        OVER TX-FROM@ _VM-CALLER-ADDR 32 CMOVE
        _VM-DO-DEPLOY EXIT
    THEN
    DUP TX-CALL = IF
        DROP
        OVER TX-FROM@ _VM-CALLER-ADDR 32 CMOVE
        _VM-DO-CALL EXIT
    THEN
    DROP
    _VM-PREV-TX-EXT @ EXECUTE ;

\ =====================================================================
\  11. Initialization & Public API
\ =====================================================================

VARIABLE _VM-INITIALIZED

: VM-INIT  ( -- )
    _VM-INITIALIZED @ IF EXIT THEN
    _VM-REGISTER-CORE
    _VM-CODE-MAP _VM-CODE-MAX _VM-CM-ESZ * 0 FILL
    0 _VM-CODE-COUNT !
    0 _VM-ARENA-BASE !
    0 _VM-RET-LEN !  0 _VM-FAILED !
    _ST-TX-EXT-XT @ _VM-PREV-TX-EXT !
    ['] _VM-TX-EXT _ST-TX-EXT-XT !
    -1 _VM-INITIALIZED ! ;

: VM-DESTROY  ( -- )
    _VM-INITIALIZED @ 0= IF EXIT THEN
    _VM-PREV-TX-EXT @ _ST-TX-EXT-XT !
    ITC-WL-RESET
    _VM-CODE-MAP _VM-CODE-MAX _VM-CM-ESZ * 0 FILL
    0 _VM-CODE-COUNT !
    0 _VM-INITIALIZED ! ;

: VM-GAS-USED  ( -- n )    _VM-GAS-USED @ ;
: VM-RETURN-DATA ( -- addr len )  _VM-RET-BUF _VM-RET-LEN @ ;
: VM-CODE-COUNT  ( -- n )  _VM-CODE-COUNT @ ;

\ =====================================================================
\  12. Concurrency Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _vm-guard

' VM-INIT        CONSTANT _vm-init-xt
' VM-DESTROY     CONSTANT _vm-destroy-xt
' VM-DEPLOY      CONSTANT _vm-deploy-xt
' VM-CALL        CONSTANT _vm-call-xt
' VM-GAS-USED    CONSTANT _vm-gas-used-xt
' VM-RETURN-DATA CONSTANT _vm-ret-data-xt
' VM-CODE-COUNT  CONSTANT _vm-code-count-xt

: VM-INIT        _vm-init-xt       _vm-guard WITH-GUARD ;
: VM-DESTROY     _vm-destroy-xt    _vm-guard WITH-GUARD ;
: VM-DEPLOY      _vm-deploy-xt     _vm-guard WITH-GUARD ;
: VM-CALL        _vm-call-xt       _vm-guard WITH-GUARD ;
: VM-GAS-USED    _vm-gas-used-xt   _vm-guard WITH-GUARD ;
: VM-RETURN-DATA _vm-ret-data-xt   _vm-guard WITH-GUARD ;
: VM-CODE-COUNT  _vm-code-count-xt _vm-guard WITH-GUARD ;
[THEN] [THEN]

\ =====================================================================
\  Done.
\ =====================================================================
