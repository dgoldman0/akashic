\ =================================================================
\  ed25519.f  —  Ed25519 Digital Signatures (RFC 8032)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: ED25519-
\  Depends on: sha512.f field.f
\
\  Public API:
\   ED25519-KEYGEN   ( seed pub priv -- )   derive keypair
\   ED25519-SIGN     ( msg len priv pub sig -- )  sign message
\   ED25519-VERIFY   ( msg len pub sig -- flag )  verify signature
\
\  Constants:
\   ED25519-KEY-LEN  ( -- 32 )
\   ED25519-SIG-LEN  ( -- 64 )
\
\  Not reentrant.
\ =================================================================

REQUIRE sha512.f
REQUIRE field.f

PROVIDED akashic-ed25519

32 CONSTANT ED25519-KEY-LEN
64 CONSTANT ED25519-SIG-LEN

\ -----------------------------------------------------------------
\  Curve constants — 32-byte LE buffers
\ -----------------------------------------------------------------

CREATE _ED-L  32 ALLOT  _ED-L 32 0 FILL
0x5812631A5CF5D3ED _ED-L !
0x14DEF9DEA2F79CD6 _ED-L 8 + !
0x0000000000000000 _ED-L 16 + !
0x1000000000000000 _ED-L 24 + !

\ Montgomery p_inv for subgroup order L.  Zero signals
\ "compute Montgomery inverse on demand" inside FIELD-LOAD-PRIME.
\ If profiling shows _ED-USE-L is hot, precompute the real value here.
CREATE _ED-PINV0  32 ALLOT  _ED-PINV0 32 0 FILL

CREATE _ED-R256  32 ALLOT  _ED-R256 32 0 FILL
0xD6EC31748D98951D _ED-R256 !
0xC6EF5BF4737DCF70 _ED-R256 8 + !
0xFFFFFFFFFFFFFFFE _ED-R256 16 + !
0x0FFFFFFFFFFFFFFF _ED-R256 24 + !

CREATE _ED-D  32 ALLOT  _ED-D 32 0 FILL
0x75EB4DCA135978A3 _ED-D !
0x00700A4D4141D8AB _ED-D 8 + !
0x8CC740797779E898 _ED-D 16 + !
0x52036CEE2B6FFE73 _ED-D 24 + !

CREATE _ED-BY  32 ALLOT  _ED-BY 32 0 FILL
0x6666666666666658 _ED-BY !
0x6666666666666666 _ED-BY 8 + !
0x6666666666666666 _ED-BY 16 + !
0x6666666666666666 _ED-BY 24 + !

CREATE _ED-BX  32 ALLOT  _ED-BX 32 0 FILL
0xC9562D608F25D51A _ED-BX !
0x692CC7609525A7B2 _ED-BX 8 + !
0xC0A4E231FDD6DC5C _ED-BX 16 + !
0x216936D3CD6E53FE _ED-BX 24 + !

CREATE _ED-SQRTM1  32 ALLOT  _ED-SQRTM1 32 0 FILL
0xC4EE1B274A0EA0B0 _ED-SQRTM1 !
0x2F431806AD2FE478 _ED-SQRTM1 8 + !
0x2B4D00993DFBD7A7 _ED-SQRTM1 16 + !
0x2B8324804FC1DF0B _ED-SQRTM1 24 + !

CREATE _ED-EXP38  32 ALLOT  _ED-EXP38 32 0 FILL
0xFFFFFFFFFFFFFFFE _ED-EXP38 !
0xFFFFFFFFFFFFFFFF _ED-EXP38 8 + !
0xFFFFFFFFFFFFFFFF _ED-EXP38 16 + !
0x0FFFFFFFFFFFFFFF _ED-EXP38 24 + !

CREATE _ED-ONE  32 ALLOT  _ED-ONE 32 0 FILL
0x0000000000000001 _ED-ONE !

\ Curve25519 prime p = 2^255 - 19  (32-byte LE)
CREATE _ED-P  32 ALLOT  _ED-P 32 0 FILL
0xFFFFFFFFFFFFFFED _ED-P !
0xFFFFFFFFFFFFFFFF _ED-P 8 + !
0xFFFFFFFFFFFFFFFF _ED-P 16 + !
0x7FFFFFFFFFFFFFFF _ED-P 24 + !

\ -----------------------------------------------------------------
\  Scratch buffers
\ -----------------------------------------------------------------

FIELD-BUF _ED-T1   FIELD-BUF _ED-T2   FIELD-BUF _ED-T3   FIELD-BUF _ED-T4
FIELD-BUF _ED-T5   FIELD-BUF _ED-T6   FIELD-BUF _ED-T7   FIELD-BUF _ED-T8

\ Extended points: 128 bytes each (X+0, Y+32, Z+64, T+96)
: _ED-POINT  CREATE 128 ALLOT ;
_ED-POINT _ED-PA    _ED-POINT _ED-PB
_ED-POINT _ED-PC    _ED-POINT _ED-PD
_ED-POINT _ED-BASE

CREATE _ED-H64  64 ALLOT
FIELD-BUF _ED-SC1   FIELD-BUF _ED-SC2   FIELD-BUF _ED-SC3
CREATE _ED-ENC1  32 ALLOT
CREATE _ED-ENC2  32 ALLOT

\ -----------------------------------------------------------------
\  Variables
\ -----------------------------------------------------------------

VARIABLE _ED-PP   VARIABLE _ED-QQ   VARIABLE _ED-RR
VARIABLE _ED-MSG-A   VARIABLE _ED-MSG-L
VARIABLE _ED-SA      \ scalar addr for smul
VARIABLE _ED-BVAL    \ current byte in smul
VARIABLE _ED-DEC-SIGN
VARIABLE _ED-BASE-OK   0 _ED-BASE-OK !

VARIABLE _ED-KG-SEED  VARIABLE _ED-KG-PUB  VARIABLE _ED-KG-PRIV
VARIABLE _ED-SG-PRIV  VARIABLE _ED-SG-PUB  VARIABLE _ED-SG-SIG
VARIABLE _ED-VF-PUB   VARIABLE _ED-VF-SIG
VARIABLE _ED-ENC-DST  VARIABLE _ED-R-HASH  VARIABLE _ED-R-DST

\ -----------------------------------------------------------------
\  Prime selection
\ -----------------------------------------------------------------

: _ED-USE-P  FIELD-USE-25519 ;
: _ED-USE-L  _ED-L _ED-PINV0 FIELD-LOAD-PRIME ;

\ -----------------------------------------------------------------
\  Point identity = (0, 1, 1, 0)
\ -----------------------------------------------------------------

: _ED-PT-ID  ( pt -- )
    DUP FIELD-ZERO
    DUP 32 + FIELD-ONE
    DUP 64 + FIELD-ONE
    96 + FIELD-ZERO ;

\ -----------------------------------------------------------------
\  Point doubling — dbl-2008-hwcd (a=-1)
\  P = _ED-PP @,  result = _ED-RR @
\ -----------------------------------------------------------------

: _ED-DBL  ( -- )
    _ED-USE-P
    _ED-PP @ _ED-T1 FIELD-SQR                      \ A = X^2
    _ED-PP @ 32 + _ED-T2 FIELD-SQR                 \ B = Y^2
    _ED-PP @ 64 + _ED-T3 FIELD-SQR                 \ Z^2
    _ED-T3 _ED-T3 _ED-T3 FIELD-ADD                 \ C = 2*Z^2
    _ED-T1 _ED-T4 FIELD-NEG                        \ D = -A
    _ED-PP @ _ED-PP @ 32 + _ED-T5 FIELD-ADD        \ X+Y
    _ED-T5 _ED-T5 FIELD-SQR                        \ (X+Y)^2
    _ED-T5 _ED-T1 _ED-T5 FIELD-SUB                 \ - A
    _ED-T5 _ED-T2 _ED-T5 FIELD-SUB                 \ E = (X+Y)^2 - A - B
    _ED-T4 _ED-T2 _ED-T6 FIELD-ADD                 \ G = D + B
    _ED-T6 _ED-T3 _ED-T7 FIELD-SUB                 \ F = G - C
    _ED-T4 _ED-T2 _ED-T8 FIELD-SUB                 \ H = D - B
    _ED-T5 _ED-T7 _ED-RR @ FIELD-MUL               \ X3 = E*F
    _ED-T6 _ED-T8 _ED-RR @ 32 + FIELD-MUL          \ Y3 = G*H
    _ED-T7 _ED-T6 _ED-RR @ 64 + FIELD-MUL          \ Z3 = F*G
    _ED-T5 _ED-T8 _ED-RR @ 96 + FIELD-MUL ;        \ T3 = E*H

\ -----------------------------------------------------------------
\  Point addition — add-2008-hwcd-4 (a=-1)
\  P = _ED-PP @,  Q = _ED-QQ @,  result = _ED-RR @
\ -----------------------------------------------------------------

: _ED-ADD  ( -- )
    _ED-USE-P
    _ED-PP @ 32 + _ED-PP @ _ED-T1 FIELD-SUB        \ Y1-X1
    _ED-QQ @ 32 + _ED-QQ @ _ED-T2 FIELD-SUB        \ Y2-X2
    _ED-T1 _ED-T2 _ED-T1 FIELD-MUL                 \ A = (Y1-X1)*(Y2-X2)
    _ED-PP @ 32 + _ED-PP @ _ED-T3 FIELD-ADD        \ Y1+X1
    _ED-QQ @ 32 + _ED-QQ @ _ED-T4 FIELD-ADD        \ Y2+X2
    _ED-T3 _ED-T4 _ED-T2 FIELD-MUL                 \ B = (Y1+X1)*(Y2+X2)
    _ED-PP @ 96 + _ED-QQ @ 96 + _ED-T3 FIELD-MUL  \ T1*T2
    _ED-T3 _ED-D _ED-T3 FIELD-MUL                  \ d*T1*T2
    _ED-T3 _ED-T3 _ED-T3 FIELD-ADD                 \ C = 2*d*T1*T2
    _ED-PP @ 64 + _ED-QQ @ 64 + _ED-T4 FIELD-MUL  \ Z1*Z2
    _ED-T4 _ED-T4 _ED-T4 FIELD-ADD                 \ D = 2*Z1*Z2
    _ED-T2 _ED-T1 _ED-T5 FIELD-SUB                 \ E = B - A
    _ED-T4 _ED-T3 _ED-T6 FIELD-SUB                 \ F = D - C
    _ED-T4 _ED-T3 _ED-T7 FIELD-ADD                 \ G = D + C
    _ED-T2 _ED-T1 _ED-T8 FIELD-ADD                 \ H = B + A
    _ED-T5 _ED-T6 _ED-RR @ FIELD-MUL               \ X3 = E*F
    _ED-T7 _ED-T8 _ED-RR @ 32 + FIELD-MUL          \ Y3 = G*H
    _ED-T6 _ED-T7 _ED-RR @ 64 + FIELD-MUL          \ Z3 = F*G
    _ED-T5 _ED-T8 _ED-RR @ 96 + FIELD-MUL ;        \ T3 = E*H

\ -----------------------------------------------------------------
\  Constant-time conditional copy (CMOV pattern)
\  Copies len bytes from src to dst when bit=1; no-op when bit=0.
\  Branchless: uses arithmetic mask (AND/XOR), no IF/THEN.
\ -----------------------------------------------------------------

VARIABLE _ED-CT-MSK

: _ED-CT-SELECT  ( dst src len bit -- )
    NEGATE _ED-CT-MSK !               \ bit=1 -> mask=-1, bit=0 -> 0
    0 ?DO                              \ ( dst src )
        OVER I + C@                    \ dst[I]         ( dst src d )
        OVER I + C@                    \ src[I]         ( dst src d s )
        OVER XOR _ED-CT-MSK @ AND     \ (s^d) & mask   ( dst src d masked )
        XOR                            \ d ^ masked     ( dst src result )
        2 PICK I + C!                  \ dst[I]=result  ( dst src )
    LOOP
    2DROP ;

\ -----------------------------------------------------------------
\  Scalar multiply:  result in _ED-PA
\  ( scalar-addr point-addr -- )
\  Constant-time double-and-always-add with CMOV selection.
\  No secret-dependent branches — immune to timing/power analysis.
\ -----------------------------------------------------------------

: _ED-SMUL  ( scalar point -- )
    _ED-QQ ! _ED-SA !
    _ED-PA _ED-PT-ID
    32 0 DO
        _ED-SA @ 31 I - + C@ _ED-BVAL !
        8 0 DO
            \ Double: PB = 2*PA (always)
            _ED-PA _ED-PP !  _ED-PB _ED-RR !  _ED-DBL
            _ED-PB _ED-PA 128 CMOVE
            \ Add: PB = PA + Q (always compute)
            _ED-PA _ED-PP !  _ED-QQ @ _ED-QQ !  _ED-PB _ED-RR !
            _ED-ADD
            \ Constant-time select: PA = bit ? PB : PA
            _ED-BVAL @ 7 I - RSHIFT 1 AND   ( bit: 0 or 1 )
            >R
            _ED-PA _ED-PB 128 R> _ED-CT-SELECT
        LOOP
    LOOP ;

\ -----------------------------------------------------------------
\  Point encode: extended -> 32-byte (RFC 8032)
\ -----------------------------------------------------------------

: _ED-ENCODE  ( pt dst -- )
    _ED-ENC-DST ! _ED-PP !
    _ED-USE-P
    _ED-PP @ 64 + _ED-T1 FIELD-INV                 \ Zinv
    _ED-PP @ 32 + _ED-T1 _ED-T2 FIELD-MUL          \ y = Y*Zinv
    _ED-PP @ _ED-T1 _ED-T3 FIELD-MUL                \ x = X*Zinv
    _ED-T2 _ED-ENC-DST @ 32 CMOVE                   \ copy y
    _ED-T3 C@ 1 AND IF
        _ED-ENC-DST @ 31 + DUP C@ 0x80 OR SWAP C!
    THEN ;

\ -----------------------------------------------------------------
\  32-byte unsigned comparison (LE): TRUE if a >= b
\ -----------------------------------------------------------------

: _ED-BYTES-GTE?  ( a b -- flag )
    31
    BEGIN
        DUP 0>= WHILE
        DUP >R
        2 PICK R@ + C@                 \ a[i]
        2 PICK R> + C@                 \ b[i]
        2DUP <> IF
            > NIP NIP NIP EXIT
        THEN
        2DROP
        1-
    REPEAT
    DROP 2DROP TRUE ;           \ a == b => a >= b => TRUE

\ -----------------------------------------------------------------
\  32-byte unsigned comparison (LE): TRUE if a < b
\ -----------------------------------------------------------------

: _ED-BYTES-LT?  ( a b -- flag )
    _ED-BYTES-GTE? 0= ;

\ -----------------------------------------------------------------
\  Point decode: 32 bytes -> extended point, returns flag
\  Rejects non-canonical y (y >= p) per RFC 8032 §5.1.3.
\ -----------------------------------------------------------------

: _ED-DECODE  ( buf pt -- flag )
    _ED-RR ! _ED-PP !
    _ED-USE-P
    _ED-PP @ 31 + C@ 7 RSHIFT _ED-DEC-SIGN !
    _ED-PP @ _ED-RR @ 32 + 32 CMOVE
    _ED-RR @ 32 + 31 + DUP C@ 0x7F AND SWAP C!
    \ ── P04: reject non-canonical y (y >= p) ──
    _ED-RR @ 32 + _ED-P _ED-BYTES-GTE? IF FALSE EXIT THEN
    _ED-RR @ 64 + FIELD-ONE
    _ED-RR @ 32 + _ED-T1 FIELD-SQR                 \ y^2
    _ED-T1 _FLD-ONE _ED-T2 FIELD-SUB               \ u = y^2-1
    _ED-D _ED-T1 _ED-T3 FIELD-MUL                  \ d*y^2
    _ED-T3 _FLD-ONE _ED-T3 FIELD-ADD               \ v = d*y^2+1
    _ED-T3 _ED-T4 FIELD-INV                        \ 1/v
    _ED-T2 _ED-T4 _ED-T5 FIELD-MUL                 \ x2 = u/v
    \ Check x2 = 0 (special case)
    _ED-T5 FIELD-ZERO? IF
        _ED-RR @ FIELD-ZERO                         \ X = 0
        _ED-DEC-SIGN @ IF
            FALSE EXIT                              \ nonzero sign but x=0 is invalid
        THEN
        _ED-RR @ _ED-RR @ 32 + _ED-RR @ 96 + FIELD-MUL
        TRUE EXIT
    THEN
    \ candidate x = x2^((p+3)/8)
    _ED-T5 _ED-EXP38 _ED-T6 FIELD-POW
    _ED-T6 _ED-T7 FIELD-SQR                        \ T6^2
    _ED-T7 _ED-T5 FIELD-EQ? IF
        \ good
    ELSE
        _ED-T6 _ED-SQRTM1 _ED-T6 FIELD-MUL
        _ED-T6 _ED-T7 FIELD-SQR
        _ED-T7 _ED-T5 FIELD-EQ? 0= IF
            FALSE EXIT
        THEN
    THEN
    _ED-T6 C@ 1 AND _ED-DEC-SIGN @ <> IF
        _ED-T6 _ED-T6 FIELD-NEG
    THEN
    _ED-T6 _ED-RR @ 32 CMOVE                       \ store X
    _ED-RR @ _ED-RR @ 32 + _ED-RR @ 96 + FIELD-MUL  \ T = X*Y
    TRUE ;

\ -----------------------------------------------------------------
\  Init base point
\ -----------------------------------------------------------------

: _ED-INIT-BASE  ( -- )
    _ED-BASE-OK @ IF EXIT THEN
    _ED-BX _ED-BASE 32 CMOVE
    _ED-BY _ED-BASE 32 + 32 CMOVE
    _ED-BASE 64 + FIELD-ONE
    _ED-USE-P
    _ED-BX _ED-BY _ED-BASE 96 + FIELD-MUL
    1 _ED-BASE-OK ! ;

\ -----------------------------------------------------------------
\  Reduce 64-byte hash to scalar mod L
\ -----------------------------------------------------------------

: _ED-REDUCE  ( hash64 result -- )
    _ED-R-DST ! _ED-R-HASH !
    _ED-USE-L
    _ED-R-HASH @ 32 + _ED-R256 _ED-SC3 FIELD-MUL    \ hi * R256 mod L
    _ED-R-HASH @ _ED-ONE _ED-R-DST @ FIELD-MUL       \ lo * 1 = lo mod L
    _ED-R-DST @ _ED-SC3 _ED-R-DST @ FIELD-ADD ;      \ reduced_lo + reduced_hi

\ -----------------------------------------------------------------
\  ED25519-KEYGEN  ( seed pub priv -- )
\ -----------------------------------------------------------------

: ED25519-KEYGEN  ( seed pub priv -- )
    _ED-KG-PRIV ! _ED-KG-PUB ! _ED-KG-SEED !
    _ED-INIT-BASE
    _ED-KG-SEED @ 32 _ED-H64 SHA512-HASH
    \ Clamp
    _ED-H64 C@ 0xF8 AND _ED-H64 C!
    _ED-H64 31 + C@ 0x3F AND _ED-H64 31 + C!
    _ED-H64 31 + C@ 0x40 OR  _ED-H64 31 + C!
    \ priv = clamped scalar + prefix
    _ED-H64 _ED-KG-PRIV @ 32 CMOVE
    _ED-H64 32 + _ED-KG-PRIV @ 32 + 32 CMOVE
    \ A = a * B
    _ED-KG-PRIV @ _ED-BASE _ED-SMUL
    _ED-PA _ED-KG-PUB @ _ED-ENCODE ;

\ -----------------------------------------------------------------
\  ED25519-SIGN  ( msg len priv pub sig -- )
\ -----------------------------------------------------------------

: ED25519-SIGN  ( msg len priv pub sig -- )
    _ED-SG-SIG ! _ED-SG-PUB ! _ED-SG-PRIV !
    _ED-MSG-L ! _ED-MSG-A !
    _ED-INIT-BASE
    \ r = SHA-512(prefix || msg) mod L
    SHA512-BEGIN
    _ED-SG-PRIV @ 32 + 32 SHA512-ADD
    _ED-MSG-A @ _ED-MSG-L @ SHA512-ADD
    _ED-H64 SHA512-END
    _ED-H64 _ED-SC1 _ED-REDUCE
    \ R = r * B
    _ED-SC1 _ED-BASE _ED-SMUL
    _ED-PA _ED-PC 128 CMOVE
    _ED-PC _ED-SG-SIG @ _ED-ENCODE
    \ h = SHA-512(R || pub || msg) mod L
    SHA512-BEGIN
    _ED-SG-SIG @ 32 SHA512-ADD
    _ED-SG-PUB @ 32 SHA512-ADD
    _ED-MSG-A @ _ED-MSG-L @ SHA512-ADD
    _ED-H64 SHA512-END
    _ED-H64 _ED-SC2 _ED-REDUCE
    \ S = (r + h*a) mod L
    _ED-USE-L
    _ED-SC2 _ED-SG-PRIV @ _ED-SC3 FIELD-MUL     \ h*a mod L
    _ED-SC1 _ED-SC3 _ED-SC3 FIELD-ADD             \ r + h*a mod L
    _ED-SC3 _ED-SG-SIG @ 32 + 32 CMOVE
    \ ── P05: zeroize secret-derived material ──
    _ED-H64 64 0 FILL
    _ED-SC1 32 0 FILL
    _ED-SC2 32 0 FILL
    _ED-SC3 32 0 FILL
    _ED-PA  128 0 FILL
    _ED-PB  128 0 FILL ;

\ -----------------------------------------------------------------
\  ED25519-VERIFY  ( msg len pub sig -- flag )
\ -----------------------------------------------------------------

: ED25519-VERIFY  ( msg len pub sig -- flag )
    _ED-VF-SIG ! _ED-VF-PUB !
    _ED-MSG-L ! _ED-MSG-A !
    _ED-INIT-BASE
    \ Decode A
    _ED-VF-PUB @ _ED-PC _ED-DECODE 0= IF FALSE EXIT THEN
    \ Decode R
    _ED-VF-SIG @ _ED-PD _ED-DECODE 0= IF FALSE EXIT THEN
    \ ── P02: reject malleable signatures (S >= L) ──
    _ED-VF-SIG @ 32 + _ED-L _ED-BYTES-GTE? IF FALSE EXIT THEN
    \ h = SHA-512(R||pub||msg) mod L
    SHA512-BEGIN
    _ED-VF-SIG @ 32 SHA512-ADD
    _ED-VF-PUB @ 32 SHA512-ADD
    _ED-MSG-A @ _ED-MSG-L @ SHA512-ADD
    _ED-H64 SHA512-END
    _ED-H64 _ED-SC1 _ED-REDUCE
    \ S*B  — encode immediately before second SMUL clobbers PB
    _ED-VF-SIG @ 32 + _ED-BASE _ED-SMUL
    _ED-PA _ED-ENC1 _ED-ENCODE
    \ h*A
    _ED-SC1 _ED-PC _ED-SMUL
    \ _ED-PA now has h*A.  Compute R + h*A -> PC
    _ED-PD _ED-PP !
    _ED-PA _ED-QQ !
    _ED-PC _ED-RR !
    _ED-ADD
    \ Compare S*B (ENC1) vs R+h*A (PC)
    _ED-PC _ED-ENC2 _ED-ENCODE
    _ED-ENC1 _ED-ENC2 FIELD-EQ?
    \ ── P05: zeroize scratch after verify ──
    _ED-H64 64 0 FILL
    _ED-SC1 32 0 FILL ;

\ ── Concurrency Guard ─────────────────────────────────────
REQUIRE ../concurrency/guard.f
GUARD _ed25519-guard

' ED25519-KEYGEN  CONSTANT _ed-keygen-xt
' ED25519-SIGN    CONSTANT _ed-sign-xt
' ED25519-VERIFY  CONSTANT _ed-verify-xt

: ED25519-KEYGEN  _ed-keygen-xt  _ed25519-guard WITH-GUARD ;
: ED25519-SIGN    _ed-sign-xt    _ed25519-guard WITH-GUARD ;
: ED25519-VERIFY  _ed-verify-xt  _ed25519-guard WITH-GUARD ;
