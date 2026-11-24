#!/usr/bin/env python3
"""Generate Akashic's global TLS root set from NSS's certdata.txt.

The input is akashic/net/web-roots/certdata.txt, the file NSS builds its
root module from, taken unchanged from tag NSS_3_134_RTM and checked here
against its SHA-256.  The root set is every certificate whose NSS trust
object marks TLS server authentication CKT_NSS_TRUSTED_DELEGATOR, in the
file's order, as an MPTA version 2 bundle of global anchors:

- each record carries Mozilla's server distrust-after date
  (CKA_NSS_SERVER_DISTRUST_AFTER) when the root has one;
- the name constraints NSS imposes on some roots by subject in code
  (lib/certdb/genname.c, builtInNameConstraints) travel as the record's
  imposed constraints, so KDOS holds those roots as NSS does;
- a root whose key KDOS cannot verify, outside RSA of 2048 to 8192 bits with
  an exponent below 2^33 and ECDSA P-256 and P-384, is left out and listed.

It writes web-roots.mpta beside certdata.txt and web-roots-pin.f, the Forth
constants that pin the bundle's SHA-256, size and record count for
net/tls-trust-registry.f.  With --check it compares instead of writing, so a
test proves the committed files are this script's output.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

import warnings

from cryptography import x509
from cryptography.hazmat.primitives.asymmetric import ec, rsa
from cryptography.utils import CryptographyDeprecationWarning

# Some roots NSS trusts carry serial number zero, which RFC 5280 forbids
# for issued certificates; KDOS reads such a root as the self-signed anchor
# it is.
warnings.filterwarnings("ignore", category=CryptographyDeprecationWarning,
                        message="Parsed a serial number")

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "akashic" / "net" / "web-roots"
CERTDATA = OUT_DIR / "certdata.txt"
BUNDLE = OUT_DIR / "web-roots.mpta"
PIN = OUT_DIR / "web-roots-pin.f"

NSS_TAG = "NSS_3_134_RTM"
NSS_COMMIT = "72611a02c4348e03bccc684c32990b8c93497648"
CERTDATA_SHA256 = (
    "6d177e33ab54b338edfee24dc3868585833636716a320a725137ab4a15927292"
)

# lib/certdb/genname.c at NSS_3_134_RTM: subject DN -> imposed constraints.
NSS_IMPOSED_CONSTRAINTS = {
    # Agence Nationale de la Securite des Systemes d'Information (ANSSI)
    (
        b"\x30\x81\x85"
        b"\x31\x0B\x30\x09\x06\x03\x55\x04\x06\x13\x02" b"FR"
        b"\x31\x0F\x30\x0D\x06\x03\x55\x04\x08\x13\x06" b"France"
        b"\x31\x0E\x30\x0C\x06\x03\x55\x04\x07\x13\x05" b"Paris"
        b"\x31\x10\x30\x0E\x06\x03\x55\x04\x0A\x13\x07" b"PM/SGDN"
        b"\x31\x0E\x30\x0C\x06\x03\x55\x04\x0B\x13\x05" b"DCSSI"
        b"\x31\x0E\x30\x0C\x06\x03\x55\x04\x03\x13\x05" b"IGC/A"
        b"\x31\x23\x30\x21\x06\x09\x2A\x86\x48\x86\xF7\x0D\x01\x09\x01"
        b"\x16\x14" b"igca@sgdn.pm.gouv.fr"
    ): (
        b"\x30\x5D\xA0\x5B"
        + b"".join(b"\x30\x05\x82\x03" + tld for tld in (
            b".fr", b".gp", b".gf", b".mq", b".re", b".yt", b".pm",
            b".bl", b".mf", b".wf", b".pf", b".nc", b".tf"))
    ),
    # TUBITAK Kamu SM SSL Kok Sertifikasi - Surum 1
    (
        b"\x30\x81\xd2"
        b"\x31\x0b\x30\x09\x06\x03\x55\x04\x06\x13\x02" b"TR"
        b"\x31\x18\x30\x16\x06\x03\x55\x04\x07\x13\x0f" b"Gebze - Kocaeli"
        b"\x31\x42\x30\x40\x06\x03\x55\x04\x0a\x13\x39"
        b"Turkiye Bilimsel ve Teknolojik Arastirma Kurumu - TUBITAK"
        b"\x31\x2d\x30\x2b\x06\x03\x55\x04\x0b\x13\x24"
        b"Kamu Sertifikasyon Merkezi - Kamu SM"
        b"\x31\x36\x30\x34\x06\x03\x55\x04\x03\x13\x2d"
        b"TUBITAK Kamu SM SSL Kok Sertifikasi - Surum 1"
    ): b"\x30\x09\xa0\x07\x30\x05\x82\x03.tr",
}

ATTRIBUTE = re.compile(r"^(CKA_\w+) (\w+)(?: (.*))?$")


def parse_objects(text: str) -> list[dict]:
    """certdata.txt's objects, each a dict of attribute name to value."""
    objects: list[dict] = []
    current: dict | None = None
    lines = iter(text.splitlines())
    for line in lines:
        if not line.strip():
            if current is not None:
                objects.append(current)
                current = None
            continue
        if line.startswith("#"):
            continue
        match = ATTRIBUTE.match(line)
        if not match:
            continue
        name, kind, value = match.groups()
        if current is None:
            current = {}
        if kind == "MULTILINE_OCTAL":
            data = bytearray()
            for body in lines:
                if body == "END":
                    break
                data += bytes(int(octet, 8)
                              for octet in re.findall(r"\\(\d{3})", body))
            current[name] = bytes(data)
        elif kind == "UTF8":
            current[name] = value.strip('"')
        else:
            current[name] = f"{kind} {value}" if value else kind
    if current is not None:
        objects.append(current)
    return objects


def distrust_seconds(value) -> int:
    """CKA_NSS_SERVER_DISTRUST_AFTER as seconds since 1970, 0 for none."""
    if not isinstance(value, bytes):
        return 0
    stamp = datetime.strptime(value.decode("ascii"), "%y%m%d%H%M%SZ")
    return int(stamp.replace(tzinfo=timezone.utc).timestamp())


def verifiable(cert: x509.Certificate) -> bool:
    """KDOS's key profile."""
    key = cert.public_key()
    if isinstance(key, rsa.RSAPublicKey):
        return (2048 <= key.key_size <= 8192 and key.key_size % 8 == 0
                and key.public_numbers().e < 1 << 33)
    if isinstance(key, ec.EllipticCurvePublicKey):
        return key.curve.name in ("secp256r1", "secp384r1")
    return False


def record(cert: bytes, distrust_after: int, constraints: bytes) -> bytes:
    return (
        (0).to_bytes(2, "big") + (0).to_bytes(2, "big") +
        len(constraints).to_bytes(2, "big") + len(cert).to_bytes(4, "big") +
        distrust_after.to_bytes(8, "big") + constraints + cert
    )


def build(certdata: bytes) -> tuple[bytes, list[str], list[str]]:
    """The bundle, the labels it holds and the labels it leaves out."""
    objects = parse_objects(certdata.decode("utf-8"))
    certificates = {
        hashlib.sha1(obj["CKA_VALUE"]).digest(): obj
        for obj in objects
        if obj.get("CKA_CLASS") == "CK_OBJECT_CLASS CKO_CERTIFICATE"
    }
    records: list[bytes] = []
    kept: list[str] = []
    left_out: list[str] = []
    for obj in objects:
        if obj.get("CKA_CLASS") != "CK_OBJECT_CLASS CKO_NSS_TRUST":
            continue
        if obj.get("CKA_TRUST_SERVER_AUTH") != (
                "CK_TRUST CKT_NSS_TRUSTED_DELEGATOR"):
            continue
        cert_obj = certificates[obj["CKA_CERT_SHA1_HASH"]]
        der = cert_obj["CKA_VALUE"]
        cert = x509.load_der_x509_certificate(der)
        if not verifiable(cert):
            left_out.append(cert_obj["CKA_LABEL"])
            continue
        imposed = NSS_IMPOSED_CONSTRAINTS.get(cert.subject.public_bytes(), b"")
        records.append(record(
            der, distrust_seconds(cert_obj.get("CKA_NSS_SERVER_DISTRUST_AFTER")),
            imposed))
        kept.append(cert_obj["CKA_LABEL"])
    generation = int.from_bytes(hashlib.sha256(certdata).digest()[:8], "big")
    bundle = (
        b"MPTA" + (2).to_bytes(2, "big") + len(records).to_bytes(2, "big") +
        generation.to_bytes(8, "big") + b"".join(records)
    )
    return bundle, kept, left_out


def pin_source(bundle: bytes, count: int, left_out: list[str]) -> str:
    digest = hashlib.sha256(bundle).digest()
    rows = []
    for offset in range(0, 32, 8):
        rows.append("    " + " ".join(f"{byte} C," for byte in
                                       digest[offset:offset + 8]))
    omitted = "".join(f"\\    {label}\n" for label in left_out)
    return (
        "\\ =====================================================================\n"
        "\\  web-roots-pin.f - The pinned global TLS root set\n"
        "\\ =====================================================================\n"
        "\\  GENERATED by local_testing/generate_web_roots.py from NSS's\n"
        f"\\  certdata.txt at {NSS_TAG} ({NSS_COMMIT[:12]}), SHA-256\n"
        f"\\  {CERTDATA_SHA256}.\n"
        "\\  Do not edit; regenerate.  web-roots.mpta holds the roots NSS trusts\n"
        "\\  for TLS server authentication, with Mozilla's distrust-after dates\n"
        "\\  and NSS's imposed name constraints.  Left out, keys KDOS cannot\n"
        "\\  verify:\n"
        f"{omitted}"
        "\\ =====================================================================\n"
        "\n"
        "PROVIDED akashic-net-web-roots-pin\n"
        "\n"
        f"{count} CONSTANT WEB-ROOTS-COUNT\n"
        f"{len(bundle)} CONSTANT WEB-ROOTS-BYTES\n"
        "CREATE WEB-ROOTS-SHA256\n" + "\n".join(rows) + "\n"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true",
                        help="compare with the committed files instead")
    args = parser.parse_args()
    certdata = CERTDATA.read_bytes()
    actual = hashlib.sha256(certdata).hexdigest()
    if actual != CERTDATA_SHA256:
        print(f"certdata.txt SHA-256 {actual} is not {NSS_TAG}'s "
              f"{CERTDATA_SHA256}", file=sys.stderr)
        return 1
    bundle, kept, left_out = build(certdata)
    pin = pin_source(bundle, len(kept), left_out)
    if args.check:
        same = (BUNDLE.read_bytes() == bundle and
                PIN.read_text(encoding="utf-8") == pin)
        print("web roots match" if same else "web roots differ")
        return 0 if same else 1
    BUNDLE.write_bytes(bundle)
    PIN.write_text(pin, encoding="utf-8")
    print(f"{len(kept)} roots, {len(bundle)} bytes; left out: "
          + (", ".join(left_out) or "none"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
