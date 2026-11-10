#!/usr/bin/env python3
"""Test suite for SLH-DSA-SHAKE-128s (akashic/math/sphincs-plus.f).

Tests individual components first (fast), then whole signatures against
the known answers OpenSSL produced (fixtures/slh-dsa/README.md).
"""
import hashlib
from pathlib import Path

from forth_snapshot import ForthSnapshot, run_file_tests, transcript_checks

FIXTURES = Path(__file__).resolve().parent / "fixtures" / "slh-dsa"
# OpenSSL's key from the seed 00..2f, and its deterministic signature of
# the message DE AD through the standard's internal interface.
KAT_PUBLIC_KEY = (FIXTURES / "shake-128s-seed-00-2f.pub").read_bytes()
KAT_SIGNATURE = (FIXTURES / "shake-128s-seed-00-2f-dead.sig").read_bytes()

SNAPSHOT = ForthSnapshot(
    ("math/sphincs-plus.f",),
    prelude=(
        ": _HEXNIB  DUP 10 < IF 48 + ELSE 87 + THEN EMIT ;",
        ": .HEX  ( addr n -- ) 0 ?DO DUP I + C@ DUP 4 RSHIFT _HEXNIB 15 AND _HEXNIB LOOP DROP ;",
        # HX stores the bytes its hex token spells at _HP and advances it.
        "VARIABLE _HP",
        ": _HEXD  ( c -- n )  DUP 58 < IF 48 - ELSE 87 - THEN ;",
        ": HX  ( \"hex\" -- )  BL WORD COUNT 2 / 0 ?DO DUP I 2* + DUP C@ _HEXD"
        " 4 LSHIFT SWAP 1+ C@ _HEXD OR _HP @ C! 1 _HP +! LOOP DROP ;",
        # Test buffers
        "CREATE _TSEED 48 ALLOT",
        "CREATE _TPK 32 ALLOT",
        "CREATE _TSK 64 ALLOT",
        "CREATE _TSIG 7856 ALLOT",
        "CREATE _TMSG 256 ALLOT",
        "CREATE _TBUF 1024 ALLOT",
    ),
)


def run_forth(lines, max_steps=800_000_000):
    return SNAPSHOT.run(lines, max_steps)


def _stored(buffer, data):
    """Forth lines that store DATA at BUFFER."""
    return [f"{buffer} _HP !"] + [
        "HX " + data[at:at + 100].hex() for at in range(0, len(data), 100)
    ]


# The checks read only what the program printed, and fail their test when a
# check fails or KDOS reports a failed line (forth_snapshot.transcript_checks).
check, check_fn, _ = transcript_checks(run_forth)


# ── Python reference: SHAKE-256 ──────────────────────────────────────

def shake256(data, outlen):
    """SHAKE-256 of data, output outlen bytes."""
    return hashlib.shake_256(data).digest(outlen)


# ── Tests: Constants ─────────────────────────────────────────────────

def test_constants():
    print("\n=== Constants ===")
    check("T01 SPX-N=16",
          ['SPX-N . CR'], "16")
    check("T02 SPX-SIG-LEN=7856",
          ['SPX-SIG-LEN . CR'], "7856")
    check("T03 SPX-PK-LEN=32",
          ['SPX-PK-LEN . CR'], "32")
    check("T04 SPX-SK-LEN=64",
          ['SPX-SK-LEN . CR'], "64")


# ── Tests: Big-endian helpers ────────────────────────────────────────

def test_be_helpers():
    print("\n=== Big-Endian Helpers ===")
    # BE32!: store 0xDEADBEEF, read back all 4 bytes on one line
    check("T05 BE32!-roundtrip",
          ['0xDEADBEEF _TBUF _SPX-BE32!',
           '_TBUF C@ . _TBUF 1+ C@ . _TBUF 2 + C@ . _TBUF 3 + C@ . CR'],
          "222 173 190 239")

    # BE64!: store 0x0102030405060708
    check("T06 BE64!-roundtrip",
          ['0x0102030405060708 _TBUF _SPX-BE64!',
           '_TBUF C@ . _TBUF 7 + C@ . CR'],
          "1 8")

    # BE24@: read 3 bytes
    check("T07 BE24@",
          ['0xAB _TBUF C!  0xCD _TBUF 1+ C!  0xEF _TBUF 2 + C!',
           '_TBUF _SPX-BE24@ . CR'],
          str(0xABCDEF))

    # BE16@: read 2 bytes
    check("T08 BE16@",
          ['0x12 _TBUF C!  0x34 _TBUF 1+ C!',
           '_TBUF _SPX-BE16@ . CR'],
          str(0x1234))


# ── Tests: ADRS manipulation ────────────────────────────────────────

def test_adrs():
    print("\n=== ADRS Manipulation ===")
    # Set type, check byte 19 (type is at bytes 16-19 BE)
    check("T09 ADRS-TYPE!",
          ['_SPX-ADRS-ZERO',
           '3 _SPX-ADRS-TYPE!',
           '_SPX-ADRS 19 + C@ . CR'],
          "3")

    # Set layer, check byte 3
    check("T10 ADRS-LAYER!",
          ['_SPX-ADRS-ZERO',
           '5 _SPX-ADRS-LAYER!',
           '_SPX-ADRS 3 + C@ . CR'],
          "5")

    # Set kp, check byte 23
    check("T11 ADRS-KP!",
          ['_SPX-ADRS-ZERO',
           '42 _SPX-ADRS-KP!',
           '_SPX-ADRS 23 + C@ . CR'],
          "42")

    # Set chain, check byte 27
    check("T12 ADRS-CHAIN!",
          ['_SPX-ADRS-ZERO',
           '7 _SPX-ADRS-CHAIN!',
           '_SPX-ADRS 27 + C@ . CR'],
          "7")

    # Set hash, check byte 31
    check("T13 ADRS-HASH!",
          ['_SPX-ADRS-ZERO',
           '9 _SPX-ADRS-HASH!',
           '_SPX-ADRS 31 + C@ . CR'],
          "9")

    # Type! does NOT clear bytes 20-31
    check("T14 TYPE!-no-autoclear",
          ['_SPX-ADRS-ZERO',
           '42 _SPX-ADRS-KP!',
           '7 _SPX-ADRS-CHAIN!',
           '1 _SPX-ADRS-TYPE!',  # switch type
           '_SPX-ADRS 23 + C@ . _SPX-ADRS 27 + C@ . CR'],
          "42 7")

    # The tree address is twelve bytes; a 64-bit index fills the low eight.
    expected_wots_pk = (
        "00000007"
        "00000000"
        "0102030405060708"
        "00000001"
        "0000002a"
        "00000000"
        "00000000"
    )
    check_fn("T14a WOTS-PK-address-canonicalization",
        ['_SPX-ADRS-ZERO',
         '7 _SPX-ADRS-LAYER!',
         '0x0102030405060708 _SPX-ADRS-TREE!',
         '42 _SPX-ADRS-KP!',
         '7 _SPX-ADRS-CHAIN!',
         '9 _SPX-ADRS-HASH!',
         '_SPX-ADRS-WOTS-PK!',
         '_SPX-ADRS 32 .HEX CR'],
        lambda out: expected_wots_pk in out.lower().replace(' ', ''),
        f"expected {expected_wots_pk}")


# ── Tests: base_w encoding ───────────────────────────────────────────

def test_base_w():
    print("\n=== base_w Encoding ===")
    # Encode byte 0xAB -> nibbles 0xA=10, 0xB=11
    check("T15 base_w-single-byte",
          ['0xAB _TBUF C!',
           '_TBUF 2 _SPX-BASE-W',
           '_SPX-WOTS-MSG C@ . _SPX-WOTS-MSG 1+ C@ . CR'],
          "10 11")

    # Encode 0x00 -> 0, 0
    check("T16 base_w-zero",
          ['0 _TBUF C!',
           '_TBUF 2 _SPX-BASE-W',
           '_SPX-WOTS-MSG C@ . _SPX-WOTS-MSG 1+ C@ . CR'],
          "0 0")

    # Encode 0xFF -> 15, 15
    check("T17 base_w-ff",
          ['0xFF _TBUF C!',
           '_TBUF 2 _SPX-BASE-W',
           '_SPX-WOTS-MSG C@ . _SPX-WOTS-MSG 1+ C@ . CR'],
          "15 15")


# ── Tests: WOTS+ checksum ───────────────────────────────────────────

def test_wots_checksum():
    print("\n=== WOTS+ Checksum ===")
    # All zeros -> checksum = 32*15 = 480 = 0x1E0
    # Nibbles: (480>>8)&15=1, (480>>4)&15=14, 480&15=0
    check("T18 checksum-all-zeros",
          ['_TBUF 16 0 FILL',
           '_TBUF _SPX-WOTS-ENCODE',
           '_SPX-WOTS-MSG 32 + C@ . _SPX-WOTS-MSG 33 + C@ . _SPX-WOTS-MSG 34 + C@ . CR'],
          "1 14 0")

    # All 0xFF -> each nibble is 15, checksum = 32*0 = 0, shifted = 0
    check("T19 checksum-all-ff",
          ['_TBUF 16 0xFF FILL',
           '_TBUF _SPX-WOTS-ENCODE',
           '_SPX-WOTS-MSG 32 + C@ . _SPX-WOTS-MSG 33 + C@ . _SPX-WOTS-MSG 34 + C@ . CR'],
          "0 0 0")


# ── Tests: T_1 hash function ────────────────────────────────────────

def test_t1_hash():
    print("\n=== T_1 Hash ===")
    # Compute T_1(PK.seed, ADRS, input) in Forth and Python.
    # PK.seed = 16 bytes of 0x01, ADRS = all zeros, input = 16 bytes of 0x02
    pk_seed = b'\x01' * 16
    adrs    = b'\x00' * 32
    inp     = b'\x02' * 16
    expected = shake256(pk_seed + adrs + inp, 16).hex()

    check_fn("T20 T_1-hash-value",
        ['_TBUF 16 0x01 FILL',           # PK.seed
         '_TBUF _SPX-PK-SEED !',
         '_SPX-ADRS-ZERO',
         '_TBUF 16 + 16 0x02 FILL',      # input
         '_TBUF 16 +  _TBUF 32 +  _SPX-T1',  # T1(in, dst)
         '_TBUF 32 + 16 .HEX CR'],
        lambda out: expected in out.strip().lower().replace(' ', ''),
        f"expected {expected}")


# ── Tests: production WOTS context layout ───────────────────────────

def test_wots_context_layout():
    print("\n=== WOTS Context Layout ===")
    pk_seed = bytes(range(0x00, 0x10))
    adrs    = bytes(range(0x20, 0x40))
    inp     = bytes(range(0x80, 0x90))
    expected = (pk_seed + adrs + inp).hex()

    check_fn("T21 WOTS-context-layout",
        [': _T21-INIT',
         '  16 0 DO I _TBUF I + C! LOOP',
         '  32 0 DO I 0x20 + _SPX-ADRS I + C! LOOP',
         '  16 0 DO I 0x80 + _TBUF 16 + I + C! LOOP ;',
         '_T21-INIT',
         '_TBUF _SPX-PK-SEED !',
         '_TBUF 16 + _SPX-WOTS-CONTEXT!',
         '_SPX-WOTS-CONTEXT 64 .HEX CR',
         '_SPX-WOTS-CONTEXT 64 0 FILL'],
        lambda out: expected in out.strip().lower().replace(' ', ''),
        f"expected {expected}")


    # The accelerator reads the context from Bank 0 and refuses one that
    # lies in extended memory, where the userland dictionary is.
    check("T21a WOTS-context-in-Bank-0",
          ['_SPX-WOTS-CONTEXT 64 + MEM-SIZE U> 0= . CR'],
          "-1")


# ── Tests: T_2 hash function ────────────────────────────────────────

def test_t2_hash():
    print("\n=== T_2 Hash ===")
    pk_seed = b'\x01' * 16
    adrs    = b'\x00' * 32
    left    = b'\x04' * 16
    right   = b'\x05' * 16
    expected = shake256(pk_seed + adrs + left + right, 16).hex()

    check_fn("T22 T_2-hash-value",
        ['_TBUF 16 0x01 FILL',           # PK.seed
         '_TBUF _SPX-PK-SEED !',
         '_SPX-ADRS-ZERO',
         '_TBUF 16 + 16 0x04 FILL',      # left
         '_TBUF 32 + 16 0x05 FILL',      # right
         '_TBUF 48 + 16 0 FILL',         # clear dst
         '_TBUF 16 +  _TBUF 32 +  _TBUF 48 +  _SPX-T2',
         '_TBUF 48 + 16 .HEX CR'],
        lambda out: expected in out.strip().lower().replace(' ', ''),
        f"expected {expected}")


# ── Tests: PRF function ─────────────────────────────────────────────

def test_prf():
    print("\n=== PRF ===")
    pk_seed = b'\x01' * 16
    sk_seed = b'\x06' * 16
    adrs    = b'\x00' * 32
    expected = shake256(pk_seed + adrs + sk_seed, 16).hex()

    check_fn("T23 PRF-value",
        ['_TBUF 16 0x01 FILL',           # PK.seed
         '_TBUF _SPX-PK-SEED !',
         '_TBUF 16 + 16 0x06 FILL',      # SK.seed
         '_TBUF 16 + _SPX-SK-SEED !',
         '_SPX-ADRS-ZERO',
         '_TBUF 32 + _SPX-PRF',
         '_TBUF 32 + 16 .HEX CR'],
        lambda out: expected in out.strip().lower().replace(' ', ''),
        f"expected {expected}")


# ── Tests: Chain function ────────────────────────────────────────────

def test_chain():
    print("\n=== WOTS+ Chain ===")
    # Test chain with 1 step: should be T_1 of input.
    # Chain(src, start=0, steps=1, dst) = T_1(input)
    # ADRS: type=WOTS_HASH(0), chain=0; the sequencer writes hash index 0
    # into its copied context without mutating the module ADRS.
    pk_seed = b'\x01' * 16
    adrs = bytearray(32)
    # The first copied step address is therefore all zeros.
    inp = b'\x07' * 16
    expected = shake256(pk_seed + bytes(adrs) + inp, 16).hex()

    check_fn("T24 chain-1-step",
        ['_TBUF 16 0x01 FILL',
         '_TBUF _SPX-PK-SEED !',
         '_SPX-ADRS-ZERO',
         '0 _SPX-ADRS-TYPE!',
         '0 _SPX-ADRS-CHAIN!',
         '_TBUF 16 + 16 0x07 FILL',      # src
         '_TBUF 16 +  0  1  _TBUF 32 + _SPX-CHAIN',  # chain 1 step
         '_TBUF 32 + 16 .HEX CR'],
        lambda out: expected in out.strip().lower().replace(' ', ''),
        f"expected {expected}")

    # Chain with 0 steps: should be copy
    check_fn("T25 chain-0-steps",
        ['_TBUF 16 0x01 FILL',
         '_TBUF _SPX-PK-SEED !',
         '_SPX-ADRS-ZERO',
         '0 _SPX-ADRS-TYPE!',
         '0 _SPX-ADRS-CHAIN!',
         '_TBUF 16 + 16 0x08 FILL',
         '_TBUF 32 + 16 0 FILL',
         '_TBUF 16 +  0  0  _TBUF 32 + _SPX-CHAIN',
         '_TBUF 32 + 16 .HEX CR'],
        lambda out: ('08' * 16) in out.strip().lower().replace(' ', ''),
        "expected 08*16 (copy)")

    # Chain with 2 steps: T_1(T_1(input)) with hash=0 then hash=1
    # step 0: ADRS.hash=0, T_1(input) → intermediate
    # step 1: ADRS.hash=1, T_1(intermediate) → result
    adrs0 = bytearray(32)
    intermediate = shake256(pk_seed + bytes(adrs0) + inp, 16)
    adrs1 = bytearray(32)
    adrs1[31] = 1  # hash index = 1
    expected2 = shake256(pk_seed + bytes(adrs1) + intermediate, 16).hex()

    check_fn("T26 chain-2-steps",
        ['_TBUF 16 0x01 FILL',
         '_TBUF _SPX-PK-SEED !',
         '_SPX-ADRS-ZERO',
         '0 _SPX-ADRS-TYPE!',
         '0 _SPX-ADRS-CHAIN!',
         '_TBUF 16 + 16 0x07 FILL',
         '_TBUF 16 +  0  2  _TBUF 32 + _SPX-CHAIN',
         '_TBUF 32 + 16 .HEX CR'],
        lambda out: expected2 in out.strip().lower().replace(' ', ''),
        f"expected {expected2}")

    # Nonzero start proves the adapter forwards the scalar independently of
    # ADRS.hash, and src=dst proves BIOS stages the exact context first.
    inp_start3 = b'\x09' * 16
    adrs_start3 = bytearray(32)
    adrs_start3[27] = 5  # chain address = 5, big-endian u32
    node = inp_start3
    for index in (3, 4):
        step_adrs = bytearray(adrs_start3)
        step_adrs[28:32] = index.to_bytes(4, "big")
        node = shake256(pk_seed + bytes(step_adrs) + node, 16)
    expected_start3 = node.hex()

    check_fn("T26a chain-start3-steps2",
        ['_TBUF 16 0x01 FILL',
         '_TBUF _SPX-PK-SEED !',
         '_SPX-ADRS-ZERO',
         '5 _SPX-ADRS-CHAIN!',
         '_TBUF 16 + 16 0x09 FILL',
         '_TBUF 16 + 3 2 _TBUF 32 + _SPX-CHAIN',
         ': _T26A-CTX-ZERO? 0 64 0 DO _SPX-WOTS-CONTEXT I + C@ OR LOOP 0= ;',
         '_TBUF 32 + 16 .HEX CR',
         '." CTX=" _T26A-CTX-ZERO? . CR'],
        lambda out: (
            expected_start3 in out.strip().lower().replace(' ', '')
            and "CTX=-1" in out.replace(" ", "")
        ),
        f"expected {expected_start3}")

    check_fn("T26b chain-src-equals-dst",
        ['_TBUF 16 0x01 FILL',
         '_TBUF _SPX-PK-SEED !',
         '_SPX-ADRS-ZERO',
         '5 _SPX-ADRS-CHAIN!',
         '_TBUF 16 + 16 0x09 FILL',
         '_TBUF 16 + 3 2 _TBUF 16 + _SPX-CHAIN',
         '_TBUF 16 + 16 .HEX CR'],
        lambda out: expected_start3 in out.strip().lower().replace(' ', ''),
        f"expected {expected_start3}")

    check_fn("T26c chain-error-nonpublication-and-wipe",
        ['_TBUF 16 0x01 FILL',
         '_TBUF _SPX-PK-SEED !',
         '_SPX-ADRS-ZERO',
         '_TBUF 16 + 16 0x09 FILL',
         '_TBUF 32 + 16 0xA5 FILL',
         ': _T26C-BAD _TBUF 16 + 15 1 _TBUF 32 + _SPX-CHAIN ;',
         ': _T26C-CTX-ZERO? 0 64 0 DO _SPX-WOTS-CONTEXT I + C@ OR LOOP 0= ;',
         '." IOR=" \' _T26C-BAD CATCH . CR',
         '." DST=" _TBUF 32 + 16 .HEX CR',
         '." CTX=" _T26C-CTX-ZERO? . CR'],
        lambda out: (
            "IOR=3" in out.replace(" ", "")
            and ("a5" * 16) in out.lower().replace(" ", "")
            and "CTX=-1" in out.replace(" ", "")
        ),
        "expected status 3, unchanged destination, and wiped context")


# ── Tests: Digest extraction ────────────────────────────────────────

def test_digest_extraction():
    print("\n=== Digest Extraction ===")
    # Fill _SPX-DIGEST with known pattern, extract FORS/tree/leaf indices.
    # We'll use a pattern where we know the bit layout.

    # Digest = 30 bytes, we set specific values.
    # FORS index extraction: 12-bit from big-endian starting at bit i*12.
    # For i=0: bits 0..11 from bytes 0..1 (top 12 bits of first 24 bits).
    # If byte[0]=0xAB (10101011), byte[1]=0xCD (11001101), byte[2]=0xEF
    # 24-bit val = 0xABCDEF, >> (12-0) = >> 12 = 0xABC, mask 0xFFF = 0xABC = 2748

    check("T27 FORS-IDX-0",
        ['0xAB _SPX-DIGEST C!',
         '0xCD _SPX-DIGEST 1+ C!',
         '0xEF _SPX-DIGEST 2 + C!',
         '0 _SPX-FORS-IDX . CR'],
        str(0xABC))

    # Leaf index: bytes 28-29, mask to 9 bits.
    # Set byte[28]=0x01, byte[29]=0xFF → 0x01FF = 511, mask 511 = 511
    check("T28 LEAF-IDX",
        ['_SPX-DIGEST 30 0 FILL',
         '0x01 _SPX-DIGEST 28 + C!',
         '0xFF _SPX-DIGEST 29 + C!',
         '_SPX-LEAF-IDX . CR'],
        "511")

    # Leaf index with overflow: byte[28]=0x02, byte[29]=0x03 -> 0x0203=515, mask 511 = 3
    check("T29 LEAF-IDX-mask",
        ['_SPX-DIGEST 30 0 FILL',
         '0x02 _SPX-DIGEST 28 + C!',
         '0x03 _SPX-DIGEST 29 + C!',
         '_SPX-LEAF-IDX . CR'],
        "3")


# ── Tests: Sign mode ─────────────────────────────────────────────────

def test_sign_mode():
    print("\n=== Sign Mode ===")
    check("T30 default-is-random",
          ['SPX-SIGN-MODE @ . CR'], "0")

    check("T31 set-deterministic",
          ['SPX-MODE-DETERMINISTIC SPX-SIGN-MODE !',
           'SPX-SIGN-MODE @ . CR',
           'SPX-MODE-RANDOM SPX-SIGN-MODE !'],  # restore
          "1")


# ── Tests: WOTS+ sign → pk_from_sig roundtrip ───────────────────────

def test_wots_roundtrip():
    """Sign a known hash, recover pk, verify the two pks match."""
    print("\n=== WOTS+ Roundtrip ===")
    # We generate WOTS+ pk directly, then sign, then recover pk from sig.
    # Both should match. Uses deterministic secrets via PRF.
    #
    # This is expensive (~35 chain iterations * 35 chains * 2 = ~2450 hash ops)
    # but still manageable in emulator.

    check_fn("T32 WOTS-sign-pk-roundtrip",
        [
            # Set up seeds
            '_TBUF 16 0x11 FILL',             # PK.seed
            '_TBUF _SPX-PK-SEED !',
            '_TBUF 16 + 16 0x22 FILL',        # SK.seed
            '_TBUF 16 + _SPX-SK-SEED !',
            # ADRS: layer=0, tree=0, kp=0
            '_SPX-ADRS-ZERO',
            '0 _SPX-ADRS-LAYER!',
            '0 _SPX-ADRS-TREE!',
            # Generate WOTS+ pk
            '0 _TBUF 32 + _SPX-WOTS-PK-GEN',   # pk → _TBUF+32 (16 bytes)
            # Now sign a test hash
            '_TBUF 48 + 16 0x33 FILL',          # msg hash = 0x33 * 16
            # Reset ADRS for sign
            '_SPX-ADRS-ZERO',
            '0 _SPX-ADRS-LAYER!',
            '0 _SPX-ADRS-TREE!',
            '0 _SPX-ADRS-KP!',
            '0 _SPX-ADRS-TYPE!',
            '_TBUF 48 + _TBUF 64 + _SPX-WOTS-SIGN',  # sig → _TBUF+64 (560 bytes)
            # Recover pk from sig
            '_SPX-ADRS-ZERO',
            '0 _SPX-ADRS-LAYER!',
            '0 _SPX-ADRS-TREE!',
            '0 _SPX-ADRS-KP!',
            '0 _SPX-ADRS-TYPE!',
            '_TBUF 48 + _TBUF 64 +  _TBUF 624 + _SPX-WOTS-PK-FROM-SIG',
            # Compare: _TBUF+32 (16 bytes) vs _TBUF+624 (16 bytes)
            ': _T32  0 16 0 DO _TBUF 32 + I + C@ _TBUF 624 + I + C@ XOR OR LOOP 0= IF ." WOTS-MATCH" ELSE ." WOTS-MISMATCH" THEN CR ;',
            '_T32',
        ],
        lambda out: "WOTS-MATCH" in out,
        "WOTS pk should match",
        max_steps=2_000_000_000)


# ── Tests: OpenSSL's known answers ───────────────────────────────────

_VERIFY_KAT = [
    '0xDE _TMSG C!  0xAD _TMSG 1+ C!',
    ': _KV  _TMSG 2 _TPK _TSIG SPX-SIG-LEN SPX-VERIFY'
    ' IF ." SPX-VERIFY-OK" ELSE ." SPX-VERIFY-FAIL" THEN CR ;',
    '_KV',
]


def _verdict(out, wanted):
    return any(line.strip() == wanted for line in out.split('\n'))


def test_verifies_openssl_signature():
    """SPX-VERIFY accepts the signature the standard defines."""
    print("\n=== Verify OpenSSL's Signature ===")
    check_fn("K01 verify-openssl-signature",
        [*_stored("_TPK", KAT_PUBLIC_KEY),
         *_stored("_TSIG", KAT_SIGNATURE),
         *_VERIFY_KAT],
        lambda out: _verdict(out, "SPX-VERIFY-OK"),
        "OpenSSL's signature should verify")


def test_rejects_altered_signature_message_and_key():
    """One flipped bit anywhere makes SPX-VERIFY refuse."""
    print("\n=== Verify Rejects Alterations ===")
    # The randomizer, a FORS secret, a FORS authentication node, and a WOTS
    # signature and an authentication node of the first and last layers.
    for offset in (0, 16, 40, 2928, 3500, 7152, 7855):
        altered = bytearray(KAT_SIGNATURE)
        altered[offset] ^= 0x01
        check_fn(f"K02 reject-signature-byte-{offset}",
            [*_stored("_TPK", KAT_PUBLIC_KEY),
             *_stored("_TSIG", bytes(altered)),
             *_VERIFY_KAT],
            lambda out: _verdict(out, "SPX-VERIFY-FAIL"),
            f"a flipped bit in signature byte {offset} should be refused")
    check_fn("K03 reject-other-message",
        [*_stored("_TPK", KAT_PUBLIC_KEY),
         *_stored("_TSIG", KAT_SIGNATURE),
         *_VERIFY_KAT[1:2],
         '0xDE _TMSG C!  0xAE _TMSG 1+ C!',
         '_KV'],
        lambda out: _verdict(out, "SPX-VERIFY-FAIL"),
        "another message should be refused")
    for offset in (0, 31):
        altered = bytearray(KAT_PUBLIC_KEY)
        altered[offset] ^= 0x80
        check_fn(f"K04 reject-key-byte-{offset}",
            [*_stored("_TPK", bytes(altered)),
             *_stored("_TSIG", KAT_SIGNATURE),
             *_VERIFY_KAT],
            lambda out: _verdict(out, "SPX-VERIFY-FAIL"),
            f"a flipped bit in key byte {offset} should be refused")


def test_full_roundtrip():
    """Key generation and signing reproduce OpenSSL's bytes.

    One signature is about 2.2 million hashes: close to two billion guest
    steps, several minutes in the emulator.
    """
    print("\n=== Full Roundtrip (SLOW) ===")
    check_fn("T33 keygen-sign-verify",
        [
            'SPX-MODE-DETERMINISTIC SPX-SIGN-MODE !',
            # Entire test body compiled (DO/LOOP/I/IF/THEN are compile-only)
            ': _T33',
            '  48 0 DO I _TSEED I + C! LOOP',
            '  _TSEED _TPK _TSK SPX-KEYGEN',
            '  _TMSG 32 0 FILL  0xDE _TMSG C!  0xAD _TMSG 1+ C!',
            '  _TMSG 2 _TSK _TSIG SPX-SIGN',
            '  _TMSG 2 _TPK _TSIG SPX-SIG-LEN SPX-VERIFY',
            '  IF ." SPX-VERIFY-OK" ELSE ." SPX-VERIFY-FAIL" THEN CR',
            '  ." PK=" _TPK SPX-PK-LEN .HEX CR',
            '  ." SIG=" _TSIG SPX-SIG-LEN .HEX CR',
            ';',
            '_T33',
        ],
        lambda out: (
            _verdict(out, "SPX-VERIFY-OK")
            and _verdict(out, "PK=" + KAT_PUBLIC_KEY.hex())
            and _verdict(out, "SIG=" + KAT_SIGNATURE.hex())
        ),
        "the key and the signature should be OpenSSL's, and verify",
        max_steps=4_000_000_000)


# ── Tests: Hardening (P06, P07, P08) ─────────────────────────────────

def test_p06_checksum_correctness():
    """P06: Verify checksum nibble extraction is correct for several inputs."""
    print("\n=== P06: Checksum Nibble Extraction ===")
    # All zeros: csum = 480 = 0x1E0 -> nibbles [1, 14, 0]
    # (covered by T18, but let's add an independent check)
    check("P06 csum-all-zero = [1,14,0]",
          ['_TBUF 16 0 FILL',
           '_TBUF _SPX-WOTS-ENCODE',
           '_SPX-WOTS-MSG 32 + C@ . _SPX-WOTS-MSG 33 + C@ . _SPX-WOTS-MSG 34 + C@ . CR'],
          "1 14 0")

    # All 0x77 (each nibble=7): csum = 32*8 = 256 = 0x100 -> nibbles [1, 0, 0]
    check("P06 csum-all-7 = [1,0,0]",
          ['_TBUF 16 0x77 FILL',
           '_TBUF _SPX-WOTS-ENCODE',
           '_SPX-WOTS-MSG 32 + C@ . _SPX-WOTS-MSG 33 + C@ . _SPX-WOTS-MSG 34 + C@ . CR'],
          "1 0 0")

    # All 0x11 (each nibble=1): csum = 32*14 = 448 = 0x1C0 -> nibbles [1, 12, 0]
    check("P06 csum-all-1 = [1,12,0]",
          ['_TBUF 16 0x11 FILL',
           '_TBUF _SPX-WOTS-ENCODE',
           '_SPX-WOTS-MSG 32 + C@ . _SPX-WOTS-MSG 33 + C@ . _SPX-WOTS-MSG 34 + C@ . CR'],
          "1 12 0")

    # All 0xFF (each nibble=15): csum = 0 -> nibbles [0, 0, 0]
    check("P06 csum-all-F = [0,0,0]",
          ['_TBUF 16 0xFF FILL',
           '_TBUF _SPX-WOTS-ENCODE',
           '_SPX-WOTS-MSG 32 + C@ . _SPX-WOTS-MSG 33 + C@ . _SPX-WOTS-MSG 34 + C@ . CR'],
          "0 0 0")


def test_p07_keygen_zeroization():
    """P07: _SPX-RNG-SEED is zeroed after success and checked failure."""
    print("\n=== P07: Keygen Seed Zeroization ===")
    check_fn("P07 _SPX-RNG-SEED zeroed",
        [
            '_TPK _TSK SPX-KEYGEN-RANDOM',
            ': _T07  0 48 0 DO _SPX-RNG-SEED I + C@ OR LOOP 0= IF .\" ZEROED\" ELSE .\" NOT-ZEROED\" THEN CR ;',
            '_T07',
        ],
        lambda out: any(line.strip() == "ZEROED" for line in out.split('\n')),
        "_SPX-RNG-SEED should be all zeros after keygen",
        max_steps=1_000_000_000)
    check("P07 failure zeroizes seed and preserves direct owner",
        [
            ': _T07-KEYGEN  _TPK _TSK SPX-KEYGEN-RANDOM ;',
            ': _T07-ZERO?  0 48 0 DO _SPX-RNG-SEED I + C@ OR LOOP 0= ;',
            ": _T07-FAIL  SHA3-256-MODE SHA3-BEGIN . [CHAR] / EMIT "
            "['] _T07-KEYGEN CATCH . [CHAR] / EMIT "
            "SHA3-CLEAR . [CHAR] / EMIT _T07-ZERO? . CR ;",
            '_T07-FAIL',
        ],
        "0 /2 /0 /-1")


def test_p08_siglen_validation():
    """P08: SPX-VERIFY rejects wrong sig-len."""
    print("\n=== P08: Sig-Len Validation ===")
    # Wrong length (0) -> immediate rejection
    check("P08 sig-len=0 rejected",
          ['_TMSG 2 _TPK _TSIG 0 SPX-VERIFY . CR'],
          "0")

    # Wrong length (7855 = SIG-LEN - 1) -> rejected
    check("P08 sig-len=7855 rejected",
          ['_TMSG 2 _TPK _TSIG 7855 SPX-VERIFY . CR'],
          "0")

    # Wrong length (7857 = SIG-LEN + 1) -> rejected
    check("P08 sig-len=7857 rejected",
          ['_TMSG 2 _TPK _TSIG 7857 SPX-VERIFY . CR'],
          "0")


# ── Main ─────────────────────────────────────────────────────────────

if __name__ == "__main__":
    run_file_tests(__file__)
