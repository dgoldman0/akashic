\ taxonomy.f — Hierarchical taxonomy engine for KDOS / Megapad-64
\
\ Arena-backed classification system with broader/narrower term
\ relationships, synonym rings, faceted categories, and item
\ classification.  Each taxonomy lives in a single KDOS arena,
\ enabling O(1) bulk teardown via ARENA-DESTROY.
\
\ Prefix: TAX-   (public API)
\         _TAX-  (internal helpers)
\
\ Load with:   REQUIRE taxonomy.f

REQUIRE ../utils/string.f

PROVIDED akashic-taxonomy

\ =====================================================================
\  Layer 0 — Constants and Error Codes
\ =====================================================================

\ --- Pool defaults ---
256 CONSTANT _TAX-DEF-CONCEPTS    \ default max concepts
512 CONSTANT _TAX-DEF-ITEMS       \ default max item-concept links
  8 CONSTANT _TAX-DEF-SYNONYMS    \ default max synonym-ring entries per ring

\ --- Error codes ---
VARIABLE TAX-ERR
0 CONSTANT TAX-E-OK
1 CONSTANT TAX-E-NOT-FOUND
2 CONSTANT TAX-E-FULL
3 CONSTANT TAX-E-CYCLE
4 CONSTANT TAX-E-DUP
5 CONSTANT TAX-E-POOL-FULL
6 CONSTANT TAX-E-BAD-ARG

: TAX-FAIL       ( code -- )     TAX-ERR ! ;
: TAX-OK?        ( -- flag )     TAX-ERR @ 0= ;
: TAX-CLEAR-ERR  ( -- )          0 TAX-ERR ! ;

\ =====================================================================
\  Layer 0 — Concept Node Layout (80 bytes = 10 cells)
\ =====================================================================
\
\  +0   id              Auto-incrementing concept ID
\  +8   parent-ptr      Broader concept (0 = top-level)
\ +16   first-child     First narrower concept (0 = leaf)
\ +24   last-child      Last narrower concept
\ +32   next-sibling    Next sibling at same parent
\ +40   prev-sibling    Previous sibling at same parent
\ +48   label-addr      Label string address
\ +56   label-len       Label string length
\ +64   facet-bits      Up to 64 facet flags
\ +72   syn-next        Next concept in synonym ring (0 = no synonyms)

80 CONSTANT _TAX-CONCEPT-SZ

: TC.ID        ( c -- addr )  ;             \ +0
: TC.PARENT    ( c -- addr )  8 + ;         \ +8
: TC.FCHILD    ( c -- addr )  16 + ;        \ +16
: TC.LCHILD    ( c -- addr )  24 + ;        \ +24
: TC.NEXT-SIB  ( c -- addr )  32 + ;        \ +32
: TC.PREV-SIB  ( c -- addr )  40 + ;        \ +40
: TC.LABEL-A   ( c -- addr )  48 + ;        \ +48
: TC.LABEL-L   ( c -- addr )  56 + ;        \ +56
: TC.FACETS    ( c -- addr )  64 + ;        \ +64
: TC.SYN-NEXT  ( c -- addr )  72 + ;        \ +72

\ =====================================================================
\  Layer 0 — Item-Concept Link Layout (24 bytes = 3 cells)
\ =====================================================================
\
\  +0   item-id         Application-supplied item identifier
\  +8   concept-ptr     Concept this item is classified under
\ +16   next-link       Next link in chain (for per-concept or per-item)

24 CONSTANT _TAX-LINK-SZ

: TL.ITEM      ( l -- addr )  ;             \ +0
: TL.CONCEPT   ( l -- addr )  8 + ;         \ +8
: TL.NEXT      ( l -- addr )  16 + ;        \ +16

\ =====================================================================
\  Layer 0 — Taxonomy Descriptor Layout (128 bytes = 16 cells)
\ =====================================================================
\
\  +0    arena          KDOS arena handle
\  +8    concept-base   Concept pool start
\ +16    concept-max    Max concept count
\ +24    concept-free   Free-list head (0 = empty)
\ +32    concept-used   Count of allocated concepts
\ +40    link-base      Item link pool start
\ +48    link-max       Max link count
\ +56    link-free      Link free-list head (0 = empty)
\ +64    link-used      Count of allocated links
\ +72    str-base       String pool start
\ +80    str-ptr        String pool bump pointer
\ +88    str-end        String pool end
\ +96    next-id        Next concept ID to assign
\ +104   root-list      First top-level concept (0 = empty)
\ +112   root-last      Last top-level concept
\ +120   item-hash-base Item→link hash table base (for TAX-CATEGORIES)

128 CONSTANT _TAX-DESCSZ

: TD.ARENA       ( tx -- addr )  ;              \ +0
: TD.CON-BASE    ( tx -- addr )  8 + ;          \ +8
: TD.CON-MAX     ( tx -- addr )  16 + ;         \ +16
: TD.CON-FREE    ( tx -- addr )  24 + ;         \ +24
: TD.CON-USED    ( tx -- addr )  32 + ;         \ +32
: TD.LINK-BASE   ( tx -- addr )  40 + ;         \ +40
: TD.LINK-MAX    ( tx -- addr )  48 + ;         \ +48
: TD.LINK-FREE   ( tx -- addr )  56 + ;         \ +56
: TD.LINK-USED   ( tx -- addr )  64 + ;         \ +64
: TD.STR-BASE    ( tx -- addr )  72 + ;         \ +72
: TD.STR-PTR     ( tx -- addr )  80 + ;         \ +80
: TD.STR-END     ( tx -- addr )  88 + ;         \ +88
: TD.NEXT-ID     ( tx -- addr )  96 + ;         \ +96
: TD.ROOT-LIST   ( tx -- addr )  104 + ;        \ +104
: TD.ROOT-LAST   ( tx -- addr )  112 + ;        \ +112
: TD.ITEM-HASH   ( tx -- addr )  120 + ;        \ +120

\ =====================================================================
\  Layer 0 — Item Hash Table Constants
\ =====================================================================
\
\ 256-slot hash table for O(1) item→link lookup.
\ Each slot is a single cell (pointer to first link for that bucket).

256 CONSTANT _TAX-HASH-SLOTS
  8 CONSTANT _TAX-HASH-CELLSZ
\ Total hash table size = 256 * 8 = 2048 bytes

\ =====================================================================
\  Current taxonomy handle
\ =====================================================================

VARIABLE _TAX-CUR

: TAX-USE  ( tx -- )  _TAX-CUR ! ;
: TAX-TX   ( -- tx )  _TAX-CUR @ ;

\ =====================================================================
\  Layer 0 — Scratch / temp variables
\ =====================================================================

\ Shared scratch — used across internal helpers.
\ Safe because Forth is single-threaded within a task.

VARIABLE _TAX-T1   VARIABLE _TAX-T2   VARIABLE _TAX-T3
VARIABLE _TAX-T4   VARIABLE _TAX-T5   VARIABLE _TAX-T6

\ Static result buffer for returning arrays of pointers.
\ Up to 256 results can be returned from queries.
256 CONSTANT _TAX-RBUF-MAX
CREATE _TAX-RBUF  _TAX-RBUF-MAX 8 * ALLOT
VARIABLE _TAX-RPOS     \ current write position in result buffer

: _TAX-RBUF-RESET  ( -- )  0 _TAX-RPOS ! ;
: _TAX-RBUF-PUSH   ( val -- )
    _TAX-RPOS @ _TAX-RBUF-MAX < IF
        _TAX-RBUF  _TAX-RPOS @ 8 * +  !
        1 _TAX-RPOS +!
    THEN ;
: _TAX-RBUF-RESULT ( -- addr n )  _TAX-RBUF  _TAX-RPOS @ ;

\ =====================================================================
\  Layer 1 — Free-List Initialization
\ =====================================================================

VARIABLE _TCIF-A

: _TAX-CON-INIT-FREE  ( -- )
    TAX-TX TD.CON-BASE @  _TCIF-A !
    TAX-TX TD.CON-MAX @  1- 0 DO
        _TCIF-A @  _TAX-CONCEPT-SZ +
        _TCIF-A @ !
        _TCIF-A @  _TAX-CONCEPT-SZ +  _TCIF-A !
    LOOP
    0  _TCIF-A @ !
    TAX-TX TD.CON-BASE @  TAX-TX TD.CON-FREE ! ;

VARIABLE _TLIF-A

: _TAX-LINK-INIT-FREE  ( -- )
    TAX-TX TD.LINK-BASE @  _TLIF-A !
    TAX-TX TD.LINK-MAX @  1- 0 DO
        _TLIF-A @  _TAX-LINK-SZ +
        _TLIF-A @ !
        _TLIF-A @  _TAX-LINK-SZ +  _TLIF-A !
    LOOP
    0  _TLIF-A @ !
    TAX-TX TD.LINK-BASE @  TAX-TX TD.LINK-FREE ! ;

\ =====================================================================
\  Layer 1 — Pool Allocation
\ =====================================================================

: _TAX-ALLOC-CONCEPT  ( -- node | 0 )
    TAX-TX TD.CON-FREE @
    DUP 0= IF  TAX-E-FULL TAX-FAIL EXIT  THEN
    DUP @  TAX-TX TD.CON-FREE !
    DUP _TAX-CONCEPT-SZ 0 FILL
    1 TAX-TX TD.CON-USED +! ;

: _TAX-FREE-CONCEPT  ( node -- )
    DUP _TAX-CONCEPT-SZ 0 FILL
    TAX-TX TD.CON-FREE @  OVER !
    TAX-TX TD.CON-FREE !
    -1 TAX-TX TD.CON-USED +! ;

: _TAX-ALLOC-LINK  ( -- link | 0 )
    TAX-TX TD.LINK-FREE @
    DUP 0= IF  TAX-E-FULL TAX-FAIL EXIT  THEN
    DUP @  TAX-TX TD.LINK-FREE !
    DUP _TAX-LINK-SZ 0 FILL
    1 TAX-TX TD.LINK-USED +! ;

: _TAX-FREE-LINK  ( link -- )
    DUP _TAX-LINK-SZ 0 FILL
    TAX-TX TD.LINK-FREE @  OVER !
    TAX-TX TD.LINK-FREE !
    -1 TAX-TX TD.LINK-USED +! ;

\ =====================================================================
\  Layer 1 — String Pool (bump allocator)
\ =====================================================================

VARIABLE _TXSC-D
VARIABLE _TXSC-L

: _TAX-STR-COPY  ( src len -- addr len )
    DUP _TXSC-L !
    TAX-TX TD.STR-PTR @  OVER +
    TAX-TX TD.STR-END @  > IF
        2DROP TAX-E-POOL-FULL TAX-FAIL 0 0 EXIT
    THEN
    TAX-TX TD.STR-PTR @  _TXSC-D !
    DROP
    _TXSC-L @ 0 ?DO
        DUP I + C@  _TXSC-D @ I + C!
    LOOP
    DROP
    _TXSC-L @ TAX-TX TD.STR-PTR +!
    _TXSC-D @ _TXSC-L @ ;

\ =====================================================================
\  Layer 1 — Hash Helpers (FNV-1a 64-bit for item IDs)
\ =====================================================================

: _TAX-HASH-ITEM  ( item-id -- bucket-idx )
    \ Simple modular hash for integer IDs
    DUP 0< IF NEGATE THEN
    _TAX-HASH-SLOTS MOD ;

: _TAX-HASH-SLOT  ( bucket-idx -- addr )
    _TAX-HASH-CELLSZ *  TAX-TX TD.ITEM-HASH @ + ;

\ =====================================================================
\  Layer 1 — Tree Manipulation Helpers
\ =====================================================================

\ _TAX-APPEND-CHILD ( child parent -- )
\   Append child as last child of parent.
: _TAX-APPEND-CHILD  ( child parent -- )
    _TAX-T1 !  _TAX-T2 !     \ T1=parent, T2=child
    _TAX-T1 @  _TAX-T2 @ TC.PARENT !
    0 _TAX-T2 @ TC.NEXT-SIB !
    0 _TAX-T2 @ TC.PREV-SIB !
    _TAX-T1 @ TC.FCHILD @ 0= IF
        \ First child
        _TAX-T2 @ _TAX-T1 @ TC.FCHILD !
        _TAX-T2 @ _TAX-T1 @ TC.LCHILD !
    ELSE
        \ Append after last child
        _TAX-T1 @ TC.LCHILD @  _TAX-T3 !
        _TAX-T3 @ _TAX-T2 @ TC.PREV-SIB !
        _TAX-T2 @ _TAX-T3 @ TC.NEXT-SIB !
        _TAX-T2 @ _TAX-T1 @ TC.LCHILD !
    THEN ;

\ _TAX-APPEND-ROOT ( concept -- )
\   Append concept to the top-level root list.
: _TAX-APPEND-ROOT  ( concept -- )
    _TAX-T1 !     \ T1=concept
    0 _TAX-T1 @ TC.PARENT !
    0 _TAX-T1 @ TC.NEXT-SIB !
    0 _TAX-T1 @ TC.PREV-SIB !
    TAX-TX TD.ROOT-LIST @ 0= IF
        _TAX-T1 @ TAX-TX TD.ROOT-LIST !
        _TAX-T1 @ TAX-TX TD.ROOT-LAST !
    ELSE
        TAX-TX TD.ROOT-LAST @  _TAX-T3 !
        _TAX-T3 @ _TAX-T1 @ TC.PREV-SIB !
        _TAX-T1 @ _TAX-T3 @ TC.NEXT-SIB !
        _TAX-T1 @ TAX-TX TD.ROOT-LAST !
    THEN ;

\ _TAX-DETACH ( concept -- )
\   Unlink concept from its parent (or root list).
: _TAX-DETACH  ( concept -- )
    _TAX-T1 !     \ T1=concept
    _TAX-T1 @ TC.PARENT @ _TAX-T2 !   \ T2=parent (0 if top-level)
    \ Fix previous sibling's next
    _TAX-T1 @ TC.PREV-SIB @ ?DUP IF
        _TAX-T1 @ TC.NEXT-SIB @  SWAP TC.NEXT-SIB !
    ELSE
        \ Was first child → update parent's first-child
        _TAX-T2 @ 0<> IF
            _TAX-T1 @ TC.NEXT-SIB @  _TAX-T2 @ TC.FCHILD !
        ELSE
            _TAX-T1 @ TC.NEXT-SIB @  TAX-TX TD.ROOT-LIST !
        THEN
    THEN
    \ Fix next sibling's prev
    _TAX-T1 @ TC.NEXT-SIB @ ?DUP IF
        _TAX-T1 @ TC.PREV-SIB @  SWAP TC.PREV-SIB !
    ELSE
        \ Was last child → update parent's last-child
        _TAX-T2 @ 0<> IF
            _TAX-T1 @ TC.PREV-SIB @  _TAX-T2 @ TC.LCHILD !
        ELSE
            _TAX-T1 @ TC.PREV-SIB @  TAX-TX TD.ROOT-LAST !
        THEN
    THEN
    0 _TAX-T1 @ TC.PARENT !
    0 _TAX-T1 @ TC.NEXT-SIB !
    0 _TAX-T1 @ TC.PREV-SIB ! ;

\ _TAX-IS-ANCESTOR? ( ancestor descendant -- flag )
\   Walk up from descendant; return -1 if ancestor is found.
: _TAX-IS-ANCESTOR?  ( ancestor descendant -- flag )
    BEGIN
        DUP 0<> WHILE
        2DUP = IF 2DROP -1 EXIT THEN
        TC.PARENT @
    REPEAT
    2DROP 0 ;

\ =====================================================================
\  Layer 1 — Synonym Ring Helpers
\ =====================================================================

\ Synonym rings are circular singly-linked lists via TC.SYN-NEXT.
\ A concept with no synonyms has SYN-NEXT = 0.
\ A ring of N synonyms: A→B→C→A (circular).

\ _TAX-SYN-LINK ( c1 c2 -- )
\   Link c1 and c2 into the same synonym ring.
\   If both are isolated: creates ring c1→c2→c1.
\   If one is in a ring: splices the other in.
\   If both in same ring: no-op.
: _TAX-SYN-LINK  ( c1 c2 -- )
    _TAX-T1 !  _TAX-T2 !      \ T1=c2, T2=c1
    _TAX-T2 @ _TAX-T1 @ = IF EXIT THEN   \ same concept
    \ Check if already in same ring
    _TAX-T1 @ TC.SYN-NEXT @ 0<> IF
        _TAX-T1 @  _TAX-T3 !   \ walk from c2
        BEGIN
            _TAX-T3 @ TC.SYN-NEXT @  _TAX-T4 !
            _TAX-T4 @ 0= IF 0 ELSE
                _TAX-T4 @ _TAX-T1 @ = IF
                    0   \ completed ring without finding c1
                ELSE
                    _TAX-T4 @ _TAX-T2 @ = IF
                        2DROP EXIT  \ already in same ring
                    ELSE
                        _TAX-T4 @ _TAX-T3 !
                        -1
                    THEN
                THEN
            THEN
        WHILE REPEAT
    THEN
    \ Splice: swap next pointers
    \ c1.next was A (or 0), c2.next was B (or 0)
    \ After: c1→B (or c2), c2→A (or c1)
    _TAX-T2 @ TC.SYN-NEXT @  _TAX-T3 !   \ T3 = c1's old next
    _TAX-T1 @ TC.SYN-NEXT @  _TAX-T4 !   \ T4 = c2's old next
    \ If c1 was isolated (next=0), treat as self-loop
    _TAX-T3 @ 0= IF _TAX-T2 @ _TAX-T3 ! THEN
    _TAX-T4 @ 0= IF _TAX-T1 @ _TAX-T4 ! THEN
    _TAX-T4 @  _TAX-T2 @ TC.SYN-NEXT !   \ c1.next = c2's old next
    _TAX-T3 @  _TAX-T1 @ TC.SYN-NEXT ! ; \ c2.next = c1's old next

\ _TAX-SYN-UNLINK ( concept -- )
\   Remove concept from its synonym ring.
: _TAX-SYN-UNLINK  ( concept -- )
    _TAX-T1 !     \ T1=concept to remove
    _TAX-T1 @ TC.SYN-NEXT @ 0= IF EXIT THEN   \ not in a ring
    _TAX-T1 @ TC.SYN-NEXT @  _TAX-T1 @ = IF
        \ Ring of 1 (self-loop) — just clear
        0 _TAX-T1 @ TC.SYN-NEXT !
        EXIT
    THEN
    \ Find predecessor in ring
    _TAX-T1 @ _TAX-T2 !   \ start at concept
    BEGIN
        _TAX-T2 @ TC.SYN-NEXT @  _TAX-T1 @ <> WHILE
        _TAX-T2 @ TC.SYN-NEXT @  _TAX-T2 !
    REPEAT
    \ T2 is predecessor: T2.next → T1 → T1.next
    _TAX-T1 @ TC.SYN-NEXT @  _TAX-T2 @ TC.SYN-NEXT !
    \ If predecessor now points to itself, clear it (ring of 1)
    _TAX-T2 @ TC.SYN-NEXT @  _TAX-T2 @ = IF
        0 _TAX-T2 @ TC.SYN-NEXT !
    THEN
    0 _TAX-T1 @ TC.SYN-NEXT ! ;

\ =====================================================================
\  Layer 1 — Item Link Helpers
\ =====================================================================

\ _TAX-ADD-ITEM-LINK ( item-id concept -- )
\   Create an item→concept classification link.
: _TAX-ADD-ITEM-LINK  ( item-id concept -- )
    _TAX-T1 !  _TAX-T2 !      \ T1=concept, T2=item-id
    _TAX-ALLOC-LINK DUP 0= IF DROP EXIT THEN
    _TAX-T3 !                  \ T3=new link
    _TAX-T2 @ _TAX-T3 @ TL.ITEM !
    _TAX-T1 @ _TAX-T3 @ TL.CONCEPT !
    \ Insert into item hash table
    _TAX-T2 @ _TAX-HASH-ITEM  _TAX-HASH-SLOT _TAX-T4 !
    _TAX-T4 @ @  _TAX-T3 @ TL.NEXT !     \ new.next = old head
    _TAX-T3 @  _TAX-T4 @ ! ;              \ slot = new

\ _TAX-REMOVE-ITEM-LINK ( item-id concept -- )
\   Remove item→concept classification link.
: _TAX-REMOVE-ITEM-LINK  ( item-id concept -- )
    _TAX-T1 !  _TAX-T2 !      \ T1=concept, T2=item-id
    _TAX-T2 @ _TAX-HASH-ITEM  _TAX-HASH-SLOT _TAX-T3 !  \ T3=slot addr
    _TAX-T3 @  @  _TAX-T4 !   \ T4=current link
    0 _TAX-T5 !               \ T5=previous link (0 = head)
    BEGIN
        _TAX-T4 @ 0<> WHILE
        _TAX-T4 @ TL.ITEM @ _TAX-T2 @ =
        _TAX-T4 @ TL.CONCEPT @ _TAX-T1 @ = AND IF
            \ Found — unlink
            _TAX-T5 @ 0= IF
                \ Head of bucket
                _TAX-T4 @ TL.NEXT @  _TAX-T3 @ !
            ELSE
                _TAX-T4 @ TL.NEXT @  _TAX-T5 @ TL.NEXT !
            THEN
            _TAX-T4 @ _TAX-FREE-LINK
            EXIT
        THEN
        _TAX-T4 @ _TAX-T5 !
        _TAX-T4 @ TL.NEXT @  _TAX-T4 !
    REPEAT ;

\ _TAX-HAS-ITEM-LINK? ( item-id concept -- flag )
\   Check if item is classified under concept.
: _TAX-HAS-ITEM-LINK?  ( item-id concept -- flag )
    _TAX-T1 !  _TAX-T2 !
    _TAX-T2 @ _TAX-HASH-ITEM  _TAX-HASH-SLOT @  _TAX-T3 !
    BEGIN
        _TAX-T3 @ 0<> WHILE
        _TAX-T3 @ TL.ITEM @ _TAX-T2 @ =
        _TAX-T3 @ TL.CONCEPT @ _TAX-T1 @ = AND IF
            -1 EXIT
        THEN
        _TAX-T3 @ TL.NEXT @  _TAX-T3 !
    REPEAT
    0 ;

\ _TAX-RM-CON-LINKS ( concept -- )
\   Remove all item links pointing to this concept.
\   Walks the entire link pool (brute force, acceptable for pool sizes ≤512).
: _TAX-RM-CON-LINKS  ( concept -- )
    _TAX-T1 !     \ T1=concept
    \ Walk all hash buckets
    _TAX-HASH-SLOTS 0 DO
        I _TAX-HASH-SLOT  _TAX-T2 !     \ T2=slot address
        _TAX-T2 @ @  _TAX-T3 !          \ T3=current link
        0 _TAX-T4 !                     \ T4=previous
        BEGIN
            _TAX-T3 @ 0<> WHILE
            _TAX-T3 @ TL.NEXT @ _TAX-T5 !   \ T5=next (save before free)
            _TAX-T3 @ TL.CONCEPT @ _TAX-T1 @ = IF
                \ Remove this link
                _TAX-T4 @ 0= IF
                    _TAX-T5 @  _TAX-T2 @ !
                ELSE
                    _TAX-T5 @  _TAX-T4 @ TL.NEXT !
                THEN
                _TAX-T3 @ _TAX-FREE-LINK
                \ Don't advance T4 (prev stays same)
            ELSE
                _TAX-T3 @ _TAX-T4 !   \ advance prev
            THEN
            _TAX-T5 @ _TAX-T3 !       \ advance current
        REPEAT
    LOOP ;

\ =====================================================================
\  Layer 1 — Concept Search Helpers
\ =====================================================================

\ _TAX-FIND-BY-LABEL ( label-a label-l start -- concept | 0 )
\   Linear scan of sibling chain starting at 'start', returns first
\   concept whose label matches exactly.
: _TAX-FIND-BY-LABEL  ( label-a label-l start -- concept | 0 )
    _TAX-T1 !  _TAX-T2 !  _TAX-T3 !     \ T1=start, T2=len, T3=addr
    BEGIN
        _TAX-T1 @ 0<> WHILE
        _TAX-T1 @ TC.LABEL-A @  _TAX-T1 @ TC.LABEL-L @
        _TAX-T3 @ _TAX-T2 @
        STR-STRI=
        IF _TAX-T1 @ EXIT THEN
        _TAX-T1 @ TC.NEXT-SIB @  _TAX-T1 !
    REPEAT
    0 ;

\ _TAX-DFS-FIND-LABEL ( label-a label-l node -- concept | 0 )
\   Depth-first search of entire subtree for a label match.
: _TAX-DFS-FIND-LABEL  ( label-a label-l node -- concept | 0 )
    _TAX-T4 !     \ T4=node
    \ Check this node
    _TAX-T4 @ TC.LABEL-A @  _TAX-T4 @ TC.LABEL-L @
    2OVER
    STR-STRI=
    IF 2DROP _TAX-T4 @ EXIT THEN
    \ Recurse into children
    _TAX-T4 @ TC.FCHILD @
    BEGIN
        DUP 0<> WHILE
        DUP >R
        2OVER R@ RECURSE
        DUP 0<> IF
            >R 2DROP R> R> DROP EXIT
        THEN
        DROP
        R> TC.NEXT-SIB @
    REPEAT
    DROP 2DROP 0 ;

\ =====================================================================
\  Layer 2 — Taxonomy Creation and Destruction
\ =====================================================================

VARIABLE _TXN-AR

: TAX-CREATE  ( arena -- tx )
    _TXN-AR !
    TAX-CLEAR-ERR
    \ Allot descriptor
    _TXN-AR @  _TAX-DESCSZ  ARENA-ALLOT
    DUP _TAX-DESCSZ 0 FILL
    DUP _TAX-T1 !
    _TXN-AR @ _TAX-T1 @ TD.ARENA !
    \ Allot concept pool
    _TXN-AR @  _TAX-DEF-CONCEPTS _TAX-CONCEPT-SZ * ARENA-ALLOT
    _TAX-T1 @ TD.CON-BASE !
    _TAX-DEF-CONCEPTS  _TAX-T1 @ TD.CON-MAX !
    0  _TAX-T1 @ TD.CON-FREE !
    0  _TAX-T1 @ TD.CON-USED !
    \ Allot link pool
    _TXN-AR @  _TAX-DEF-ITEMS _TAX-LINK-SZ * ARENA-ALLOT
    _TAX-T1 @ TD.LINK-BASE !
    _TAX-DEF-ITEMS  _TAX-T1 @ TD.LINK-MAX !
    0  _TAX-T1 @ TD.LINK-FREE !
    0  _TAX-T1 @ TD.LINK-USED !
    \ Allot item hash table
    _TXN-AR @  _TAX-HASH-SLOTS _TAX-HASH-CELLSZ * ARENA-ALLOT
    DUP _TAX-HASH-SLOTS _TAX-HASH-CELLSZ * 0 FILL
    _TAX-T1 @ TD.ITEM-HASH !
    \ String pool = remaining arena space
    _TXN-AR @ A.PTR @   _TAX-T1 @ TD.STR-BASE !
    _TXN-AR @ A.PTR @   _TAX-T1 @ TD.STR-PTR !
    _TXN-AR @ DUP A.BASE @ SWAP A.SIZE @ +
    _TAX-T1 @ TD.STR-END !
    _TAX-T1 @ TD.STR-END @  _TXN-AR @ A.PTR !
    \ Initialize starting ID
    1  _TAX-T1 @ TD.NEXT-ID !
    0  _TAX-T1 @ TD.ROOT-LIST !
    0  _TAX-T1 @ TD.ROOT-LAST !
    \ Set as current and build free lists
    _TAX-T1 @  TAX-USE
    _TAX-CON-INIT-FREE
    _TAX-LINK-INIT-FREE
    \ Return handle
    TAX-TX ;

: TAX-DESTROY  ( tx -- )
    TD.ARENA @  ARENA-DESTROY ;

\ =====================================================================
\  Layer 2 — Concept Management
\ =====================================================================

\ TAX-ADD ( label-a label-l -- concept )
\   Add a top-level concept.  Returns concept address.
: TAX-ADD  ( label-a label-l -- concept )
    TAX-CLEAR-ERR
    _TAX-ALLOC-CONCEPT DUP 0= IF >R 2DROP R> EXIT THEN
    >R  \ save concept on return stack
    \ Assign ID
    TAX-TX TD.NEXT-ID @  R@ TC.ID !
    1 TAX-TX TD.NEXT-ID +!
    \ Copy label
    _TAX-STR-COPY
    TAX-OK? 0= IF 2DROP R> _TAX-FREE-CONCEPT 0 EXIT THEN
    R@ TC.LABEL-L !
    R@ TC.LABEL-A !
    \ Initialize fields
    0 R@ TC.FACETS !
    0 R@ TC.SYN-NEXT !
    \ Append to root list
    R@ _TAX-APPEND-ROOT
    R> ;

\ TAX-ADD-UNDER ( label-a label-l parent -- concept )
\   Add a narrower concept under parent.
: TAX-ADD-UNDER  ( label-a label-l parent -- concept )
    TAX-CLEAR-ERR
    _TAX-T6 !     \ T6=parent
    _TAX-ALLOC-CONCEPT DUP 0= IF >R 2DROP R> EXIT THEN
    >R  \ save concept on return stack
    \ Assign ID
    TAX-TX TD.NEXT-ID @  R@ TC.ID !
    1 TAX-TX TD.NEXT-ID +!
    \ Copy label
    _TAX-STR-COPY
    TAX-OK? 0= IF 2DROP R> _TAX-FREE-CONCEPT 0 EXIT THEN
    R@ TC.LABEL-L !
    R@ TC.LABEL-A !
    0 R@ TC.FACETS !
    0 R@ TC.SYN-NEXT !
    \ Append under parent
    R@ _TAX-T6 @ _TAX-APPEND-CHILD
    R> ;

\ TAX-REMOVE ( concept -- )
\   Remove concept, its subtree, all item links, and synonym membership.
\   Recursive: frees children first, then self.
: TAX-REMOVE  ( concept -- )
    DUP 0= IF DROP EXIT THEN
    >R  \ save concept on return stack
    \ Remove children recursively
    R@ TC.FCHILD @
    BEGIN
        DUP 0<> WHILE
        DUP TC.NEXT-SIB @   \ save next before recurse
        SWAP RECURSE
    REPEAT
    DROP
    \ Remove synonym ring membership
    R@ _TAX-SYN-UNLINK
    \ Remove all item links for this concept
    R@ _TAX-RM-CON-LINKS
    \ Detach from parent/root
    R@ _TAX-DETACH
    \ Free the concept node
    R> _TAX-FREE-CONCEPT ;

\ TAX-MOVE ( concept new-parent -- )
\   Reparent concept under new-parent.  new-parent=0 means top-level.
\   Fails with TAX-E-CYCLE if new-parent is a descendant of concept.
\   NOTE: uses T4/T5 because _TAX-DETACH and _TAX-APPEND-CHILD clobber T1-T3.
: TAX-MOVE  ( concept new-parent -- )
    TAX-CLEAR-ERR
    _TAX-T5 !  _TAX-T4 !     \ T5=new-parent, T4=concept
    \ Check for cycle: new-parent must not be descendant of concept
    _TAX-T5 @ 0<> IF
        _TAX-T4 @  _TAX-T5 @  _TAX-IS-ANCESTOR? IF
            TAX-E-CYCLE TAX-FAIL EXIT
        THEN
    THEN
    \ Detach from current position
    _TAX-T4 @ _TAX-DETACH
    \ Attach to new parent (or root)
    _TAX-T5 @ 0= IF
        _TAX-T4 @ _TAX-APPEND-ROOT
    ELSE
        _TAX-T4 @ _TAX-T5 @ _TAX-APPEND-CHILD
    THEN ;

\ TAX-RENAME ( label-a label-l concept -- )
\   Change the label of a concept.
: TAX-RENAME  ( label-a label-l concept -- )
    TAX-CLEAR-ERR
    _TAX-T1 !     \ T1=concept
    _TAX-STR-COPY
    TAX-OK? 0= IF 2DROP EXIT THEN
    _TAX-T1 @ TC.LABEL-L !
    _TAX-T1 @ TC.LABEL-A ! ;

\ =====================================================================
\  Layer 2 — Concept Accessors
\ =====================================================================

: TAX-ID         ( concept -- id )       TC.ID @ ;
: TAX-LABEL      ( concept -- addr len ) DUP TC.LABEL-A @ SWAP TC.LABEL-L @ ;
: TAX-PARENT     ( concept -- parent|0 ) TC.PARENT @ ;
: TAX-FACETS@    ( concept -- bits )     TC.FACETS @ ;
: TAX-COUNT      ( -- n )               TAX-TX TD.CON-USED @ ;

\ =====================================================================
\  Layer 2 — Synonym API
\ =====================================================================

\ TAX-ADD-SYNONYM ( c1 c2 -- )
\   Link two concepts as synonyms.
: TAX-ADD-SYNONYM  ( c1 c2 -- )
    TAX-CLEAR-ERR
    _TAX-SYN-LINK ;

\ TAX-REMOVE-SYNONYM ( concept -- )
\   Remove concept from its synonym ring.
: TAX-REMOVE-SYNONYM  ( concept -- )
    _TAX-SYN-UNLINK ;

\ TAX-SYNONYMS ( concept -- addr n )
\   Return all concepts in the same synonym ring (including self).
\   Results in static buffer — not re-entrant.
: TAX-SYNONYMS  ( concept -- addr n )
    _TAX-RBUF-RESET
    DUP _TAX-RBUF-PUSH
    DUP TC.SYN-NEXT @ 0= IF
        DROP _TAX-RBUF-RESULT EXIT
    THEN
    DUP TC.SYN-NEXT @
    BEGIN
        DUP OVER <> WHILE    \ walk until we loop back to start
        DUP _TAX-RBUF-PUSH
        TC.SYN-NEXT @
    REPEAT
    DROP DROP
    _TAX-RBUF-RESULT ;

\ =====================================================================
\  Layer 2 — Facet API
\ =====================================================================

\ TAX-SET-FACET ( bit concept -- )
\   Set a facet bit (0–63).
: TAX-SET-FACET  ( bit concept -- )
    SWAP 1 SWAP LSHIFT
    OVER TC.FACETS @ OR
    SWAP TC.FACETS ! ;

\ TAX-CLEAR-FACET ( bit concept -- )
\   Clear a facet bit.
: TAX-CLEAR-FACET  ( bit concept -- )
    SWAP 1 SWAP LSHIFT INVERT
    OVER TC.FACETS @ AND
    SWAP TC.FACETS ! ;

\ TAX-HAS-FACET? ( bit concept -- flag )
\   Test a facet bit.
: TAX-HAS-FACET?  ( bit concept -- flag )
    TC.FACETS @
    SWAP 1 SWAP LSHIFT
    AND 0<> ;

\ TAX-FILTER-FACET ( mask -- addr n )
\   Return all concepts whose facet-bits AND mask = mask.
\   Walks entire concept pool.
: TAX-FILTER-FACET  ( mask -- )
    _TAX-RBUF-RESET
    _TAX-T1 !     \ T1=mask
    \ Walk allocated concept pool by scanning for non-zero IDs
    TAX-TX TD.CON-BASE @  _TAX-T2 !
    TAX-TX TD.CON-USED @  _TAX-T3 !    \ count of allocated
    0 _TAX-T4 !                         \ found counter
    BEGIN
        _TAX-T4 @ _TAX-T3 @ < WHILE
        _TAX-T2 @ TC.ID @ 0<> IF
            \ This slot is allocated
            _TAX-T2 @ TC.FACETS @  _TAX-T1 @ AND  _TAX-T1 @ = IF
                _TAX-T2 @ _TAX-RBUF-PUSH
            THEN
            1 _TAX-T4 +!
        THEN
        _TAX-T2 @ _TAX-CONCEPT-SZ +  _TAX-T2 !
    REPEAT
    _TAX-RBUF-RESULT ;

\ =====================================================================
\  Layer 2 — Traversal API
\ =====================================================================

\ TAX-CHILDREN ( concept -- addr n )
\   Return immediate narrower concepts.
: TAX-CHILDREN  ( concept -- addr n )
    _TAX-RBUF-RESET
    TC.FCHILD @
    BEGIN
        DUP 0<> WHILE
        DUP _TAX-RBUF-PUSH
        TC.NEXT-SIB @
    REPEAT
    DROP
    _TAX-RBUF-RESULT ;

\ TAX-ROOTS ( -- addr n )
\   Return all top-level concepts.
: TAX-ROOTS  ( -- addr n )
    _TAX-RBUF-RESET
    TAX-TX TD.ROOT-LIST @
    BEGIN
        DUP 0<> WHILE
        DUP _TAX-RBUF-PUSH
        TC.NEXT-SIB @
    REPEAT
    DROP
    _TAX-RBUF-RESULT ;

\ TAX-ANCESTORS ( concept -- addr n )
\   Return path from parent to root (not including self).
: TAX-ANCESTORS  ( concept -- addr n )
    _TAX-RBUF-RESET
    TC.PARENT @
    BEGIN
        DUP 0<> WHILE
        DUP _TAX-RBUF-PUSH
        TC.PARENT @
    REPEAT
    DROP
    _TAX-RBUF-RESULT ;

\ TAX-DEPTH ( concept -- n )
\   Levels from root (top-level = 0).
: TAX-DEPTH  ( concept -- n )
    0 SWAP
    TC.PARENT @
    BEGIN
        DUP 0<> WHILE
        SWAP 1+ SWAP
        TC.PARENT @
    REPEAT
    DROP ;

\ TAX-DESCENDANTS ( concept -- addr n )
\   DFS walk of entire subtree (not including self).
\   Uses internal recursion via the pool scan approach.
: TAX-DESCENDANTS  ( concept -- addr n )
    _TAX-RBUF-RESET
    TC.FCHILD @
    BEGIN
        DUP 0<> WHILE
        DUP _TAX-RBUF-PUSH
        \ Recurse children depth-first
        DUP TC.FCHILD @
        BEGIN
            DUP 0<> WHILE
            DUP _TAX-RBUF-PUSH
            \ We need full DFS but can't recurse from here;
            \ rely on the fact that _TAX-DFS-COLLECT does this.
            TC.NEXT-SIB @
        REPEAT
        DROP
        TC.NEXT-SIB @
    REPEAT
    DROP
    _TAX-RBUF-RESULT ;

\ _TAX-DFS-COLLECT ( node -- )
\   Recursive DFS: push all nodes in subtree (not including root).
: _TAX-DFS-COLLECT  ( node -- )
    TC.FCHILD @
    BEGIN
        DUP 0<> WHILE
        DUP _TAX-RBUF-PUSH
        DUP RECURSE
        TC.NEXT-SIB @
    REPEAT
    DROP ;

\ TAX-DESCENDANTS overwritten to use _TAX-DFS-COLLECT properly:
: TAX-DESCENDANTS  ( concept -- addr n )
    _TAX-RBUF-RESET
    _TAX-DFS-COLLECT
    _TAX-RBUF-RESULT ;

\ =====================================================================
\  Layer 2 — Search API
\ =====================================================================

\ TAX-FIND ( label-a label-l -- concept | 0 )
\   Find concept by exact label (case-insensitive).
\   Searches entire taxonomy via DFS from all roots.
: TAX-FIND  ( label-a label-l -- concept | 0 )
    TAX-TX TD.ROOT-LIST @
    BEGIN
        DUP 0<> WHILE
        DUP >R
        2OVER R@ _TAX-DFS-FIND-LABEL
        DUP 0<> IF
            >R 2DROP R> R> DROP EXIT
        THEN
        DROP
        R> TC.NEXT-SIB @
    REPEAT
    DROP 2DROP 0 ;

\ TAX-FIND-PREFIX ( prefix-a prefix-l -- addr n )
\   Find all concepts whose label starts with prefix.
\   Case-insensitive.  Brute-force pool scan.
: TAX-FIND-PREFIX  ( prefix-a prefix-l -- addr n )
    _TAX-RBUF-RESET
    _TAX-T1 !  _TAX-T2 !     \ T1=len, T2=addr
    TAX-TX TD.CON-BASE @  _TAX-T3 !
    TAX-TX TD.CON-USED @  _TAX-T4 !
    0 _TAX-T5 !
    BEGIN
        _TAX-T5 @ _TAX-T4 @ < WHILE
        _TAX-T3 @ TC.ID @ 0<> IF
            _TAX-T3 @ TC.LABEL-A @  _TAX-T3 @ TC.LABEL-L @
            _TAX-T2 @ _TAX-T1 @
            STR-STARTSI?
            IF _TAX-T3 @ _TAX-RBUF-PUSH THEN
            1 _TAX-T5 +!
        THEN
        _TAX-T3 @ _TAX-CONCEPT-SZ +  _TAX-T3 !
    REPEAT
    _TAX-RBUF-RESULT ;

\ TAX-FIND-SYNONYM ( label-a label-l -- concept | 0 )
\   Find concept by label, also searching synonym labels.
: TAX-FIND-SYNONYM  ( label-a label-l -- concept | 0 )
    TAX-TX TD.ROOT-LIST @
    BEGIN
        DUP 0<> WHILE
        DUP >R
        2OVER R@ _TAX-DFS-FIND-LABEL
        DUP 0<> IF
            >R 2DROP R> R> DROP EXIT
        THEN
        DROP
        R> TC.NEXT-SIB @
    REPEAT
    DROP
    \ Not found by own label — check all concepts' synonym rings
    \ Walk pool looking for synonym ring members with matching label
    TAX-TX TD.CON-BASE @  _TAX-T3 !
    TAX-TX TD.CON-USED @  _TAX-T4 !
    0 _TAX-T5 !
    BEGIN
        _TAX-T5 @ _TAX-T4 @ < WHILE
        _TAX-T3 @ TC.ID @ 0<> IF
            _TAX-T3 @ TC.LABEL-A @  _TAX-T3 @ TC.LABEL-L @
            2OVER STR-STRI= IF
                \ Found — return this concept (or the primary if in ring)
                2DROP _TAX-T3 @ EXIT
            THEN
            1 _TAX-T5 +!
        THEN
        _TAX-T3 @ _TAX-CONCEPT-SZ +  _TAX-T3 !
    REPEAT
    2DROP 0 ;

\ =====================================================================
\  Layer 2 — Classification API
\ =====================================================================

\ TAX-CLASSIFY ( item-id concept -- )
\   Assign item to concept.  No-op if already classified.
: TAX-CLASSIFY  ( item-id concept -- )
    TAX-CLEAR-ERR
    2DUP _TAX-HAS-ITEM-LINK? IF 2DROP EXIT THEN
    _TAX-ADD-ITEM-LINK ;

\ TAX-UNCLASSIFY ( item-id concept -- )
\   Remove item from concept.
: TAX-UNCLASSIFY  ( item-id concept -- )
    TAX-CLEAR-ERR
    _TAX-REMOVE-ITEM-LINK ;

\ TAX-ITEMS ( concept -- addr n )
\   All items classified directly under concept.
\   Walks hash table looking for links to this concept.
: TAX-ITEMS  ( concept -- addr n )
    _TAX-RBUF-RESET
    _TAX-T1 !
    _TAX-HASH-SLOTS 0 DO
        I _TAX-HASH-SLOT @  _TAX-T2 !
        BEGIN
            _TAX-T2 @ 0<> WHILE
            _TAX-T2 @ TL.CONCEPT @ _TAX-T1 @ = IF
                _TAX-T2 @ TL.ITEM @ _TAX-RBUF-PUSH
            THEN
            _TAX-T2 @ TL.NEXT @  _TAX-T2 !
        REPEAT
    LOOP
    _TAX-RBUF-RESULT ;

\ _TAX-COLLECT-DEEP ( concept -- )
\   Recursive helper: collect items for concept + all descendants into
\   the shared _TAX-RBUF (without resetting it).  Walks the hash table
\   once per concept node, then recurses children.
: _TAX-COLLECT-DEEP  ( concept -- )
    DUP _TAX-T1 !
    _TAX-HASH-SLOTS 0 DO
        I _TAX-HASH-SLOT @
        BEGIN
            DUP 0<> WHILE
            DUP TL.CONCEPT @ _TAX-T1 @ = IF
                DUP TL.ITEM @ _TAX-RBUF-PUSH
            THEN
            TL.NEXT @
        REPEAT
        DROP
    LOOP
    TC.FCHILD @
    BEGIN
        DUP 0<> WHILE
        DUP >R
        RECURSE
        R> TC.NEXT-SIB @
    REPEAT
    DROP ;

\ TAX-ITEMS-DEEP ( concept -- addr n )
\   All items classified under concept or any of its descendants.
: TAX-ITEMS-DEEP  ( concept -- addr n )
    _TAX-RBUF-RESET
    _TAX-COLLECT-DEEP
    _TAX-RBUF-RESULT ;

\ TAX-CATEGORIES ( item-id -- addr n )
\   All concepts an item is classified under.
: TAX-CATEGORIES  ( item-id -- addr n )
    _TAX-RBUF-RESET
    _TAX-T1 !
    _TAX-T1 @ _TAX-HASH-ITEM  _TAX-HASH-SLOT @  _TAX-T2 !
    BEGIN
        _TAX-T2 @ 0<> WHILE
        _TAX-T2 @ TL.ITEM @ _TAX-T1 @ = IF
            _TAX-T2 @ TL.CONCEPT @  _TAX-RBUF-PUSH
        THEN
        _TAX-T2 @ TL.NEXT @  _TAX-T2 !
    REPEAT
    _TAX-RBUF-RESULT ;

\ =====================================================================
\  Layer 3 — Iteration / Visitor API
\ =====================================================================

\ TAX-EACH-CHILD ( xt concept -- )
\   Call xt for each immediate child.  xt signature: ( concept -- )
: TAX-EACH-CHILD  ( xt concept -- )
    TC.FCHILD @
    BEGIN
        DUP 0<> WHILE
        DUP >R
        OVER EXECUTE
        R> TC.NEXT-SIB @
    REPEAT
    2DROP ;

\ TAX-EACH-ROOT ( xt -- )
\   Call xt for each top-level concept.  xt signature: ( concept -- )
: TAX-EACH-ROOT  ( xt -- )
    TAX-TX TD.ROOT-LIST @
    BEGIN
        DUP 0<> WHILE
        DUP >R
        OVER EXECUTE
        R> TC.NEXT-SIB @
    REPEAT
    2DROP ;

\ TAX-DFS ( xt concept -- )
\   Depth-first traversal of subtree.  xt called for each node
\   including the root concept.  xt signature: ( concept -- )
: TAX-DFS  ( xt concept -- )
    DUP >R
    OVER EXECUTE
    R> TC.FCHILD @
    BEGIN
        DUP 0<> WHILE
        DUP >R
        OVER SWAP RECURSE
        R> TC.NEXT-SIB @
    REPEAT
    2DROP ;

\ TAX-DFS-ALL ( xt -- )
\   Depth-first traversal of entire taxonomy.
: TAX-DFS-ALL  ( xt -- )
    TAX-TX TD.ROOT-LIST @
    BEGIN
        DUP 0<> WHILE
        DUP >R
        OVER SWAP TAX-DFS
        R> TC.NEXT-SIB @
    REPEAT
    2DROP ;

\ =====================================================================
\  Layer 3 — Diagnostics
\ =====================================================================

\ TAX-STATS ( -- concepts links )
\   Return current counts.
: TAX-STATS  ( -- concepts links )
    TAX-TX TD.CON-USED @
    TAX-TX TD.LINK-USED @ ;
