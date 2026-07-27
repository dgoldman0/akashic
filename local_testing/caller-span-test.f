\ caller-span-test.f - Checked caller-managed span contracts

PROVIDED akashic-caller-span-contract

VARIABLE _cst-fails
VARIABLE _cst-checks
VARIABLE _cst-depth

: _cst-assert  ( flag -- )
    1 _cst-checks +!
    0= IF
        1 _cst-fails +!
        ." CALLER SPAN ASSERT " _cst-checks @ . CR
    THEN ;

: _cst-stack  ( -- )
    DEPTH _cst-depth @ = _cst-assert ;

CREATE _cst-buffer 32 ALLOT

: _cst-test-status-vocabulary  ( -- )
    CALLER-SPAN-S-OK 0 = _cst-assert
    CALLER-SPAN-S-RANGE 2 = _cst-assert
    CALLER-SPAN-S-PROTECTED 3 = _cst-assert
    CALLER-SPAN-S-PLATFORM 4 = _cst-assert

    CALLER-SPAN-S-OK CALLER-SPAN-STATUS-VALID? _cst-assert
    CALLER-SPAN-S-RANGE CALLER-SPAN-STATUS-VALID? _cst-assert
    CALLER-SPAN-S-PROTECTED CALLER-SPAN-STATUS-VALID? _cst-assert
    CALLER-SPAN-S-PLATFORM CALLER-SPAN-STATUS-VALID? _cst-assert
    1 CALLER-SPAN-STATUS-VALID? 0= _cst-assert
    -1 CALLER-SPAN-STATUS-VALID? 0= _cst-assert
    5 CALLER-SPAN-STATUS-VALID? 0= _cst-assert

    CALLER-SPAN-S-OK _CALLER-SPAN-BIOS>STATUS
        CALLER-SPAN-S-OK = _cst-assert
    CALLER-SPAN-S-RANGE _CALLER-SPAN-BIOS>STATUS
        CALLER-SPAN-S-RANGE = _cst-assert
    CALLER-SPAN-S-PROTECTED _CALLER-SPAN-BIOS>STATUS
        CALLER-SPAN-S-PROTECTED = _cst-assert
    1 _CALLER-SPAN-BIOS>STATUS
        CALLER-SPAN-S-PLATFORM = _cst-assert
    CALLER-SPAN-S-PLATFORM _CALLER-SPAN-BIOS>STATUS
        CALLER-SPAN-S-PLATFORM = _cst-assert
    _cst-stack ;

: _cst-test-empty-and-bank0  ( -- )
    0 0 CALLER-SPAN-STATUS
        CALLER-SPAN-S-OK = _cst-assert
    -1 0 CALLER-SPAN-STATUS
        CALLER-SPAN-S-OK = _cst-assert
    _cst-buffer 0 CALLER-SPAN-STATUS
        CALLER-SPAN-S-OK = _cst-assert
    _cst-buffer 32 CALLER-SPAN-STATUS
        CALLER-SPAN-S-OK = _cst-assert

    _cst-buffer -1 CALLER-SPAN-STATUS
        CALLER-SPAN-S-RANGE = _cst-assert
    -1 1 CALLER-SPAN-STATUS
        CALLER-SPAN-S-RANGE = _cst-assert
    0 1 CALLER-SPAN-STATUS
        CALLER-SPAN-S-RANGE = _cst-assert

    \ Byte one is inside the static BIOS footprint.  A live result-cell
    \ intersection is protected independently of that lower bound.
    1 1 CALLER-SPAN-STATUS
        CALLER-SPAN-S-PROTECTED = _cst-assert
    SP@ 16 - 16 CALLER-SPAN-STATUS
        CALLER-SPAN-S-PROTECTED = _cst-assert
    _cst-stack ;

: _cst-test-advertised-windows  ( -- )
    EXT-MEM-BASE 1 CALLER-SPAN-STATUS
        CALLER-SPAN-S-OK = _cst-assert
    HBW-BASE 1 CALLER-SPAN-STATUS
        CALLER-SPAN-S-OK = _cst-assert
    VRAM-BASE 1 CALLER-SPAN-STATUS
        CALLER-SPAN-S-OK = _cst-assert

    EXT-MEM-BASE EXT-MEM-SIZE + 1 - 2
        CALLER-SPAN-STATUS
        CALLER-SPAN-S-RANGE = _cst-assert
    EXT-MEM-BASE EXT-MEM-SIZE + 1
        CALLER-SPAN-STATUS
        CALLER-SPAN-S-RANGE = _cst-assert
    HBW-BASE HBW-SIZE + 1 - 2
        CALLER-SPAN-STATUS
        CALLER-SPAN-S-RANGE = _cst-assert
    VRAM-BASE VRAM-SIZE + 1 - 2
        CALLER-SPAN-STATUS
        CALLER-SPAN-S-RANGE = _cst-assert
    _cst-stack ;

: _CST-RUN  ( -- )
    0 _cst-fails !
    0 _cst-checks !
    DEPTH _cst-depth !
    ." CALLER SPAN RUN START" CR
    _cst-test-status-vocabulary
    _cst-test-empty-and-bank0
    _cst-test-advertised-windows
    _cst-stack
    _cst-fails @ 0= IF
        ." CALLER SPAN PASS " _cst-checks @ . CR
    ELSE
        ." CALLER SPAN FAIL " _cst-fails @ . CR
    THEN ;
