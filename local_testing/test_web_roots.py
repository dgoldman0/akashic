"""The global TLS root set: net/web-roots/ and net/web-roots.f.

The bundle is generate_web_roots.py's output from NSS's certdata.txt, so the
first check regenerates it and compares.  The second reads the bundle as
the verifier will: every record a global anchor, Mozilla's distrust dates
and NSS's imposed constraints in place.  The third boots a machine that
reads the bundle from a place over its boot volume through the registry,
loads all of it into KDOS, and verifies the server chains MegaPad captured
from public hosts (MegaPad's tests/fixtures/tls/webpki_chains.json) against
the whole set.
"""

from __future__ import annotations

import base64
import hashlib
import json
import re
import sys
import warnings
from pathlib import Path

LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

from cryptography import x509  # noqa: E402
from cryptography.utils import CryptographyDeprecationWarning  # noqa: E402

import akashic_tui as harness  # noqa: E402
import generate_web_roots as generator  # noqa: E402
from contract_script import run_profile_smoke  # noqa: E402

warnings.filterwarnings("ignore", category=CryptographyDeprecationWarning,
                        message="Parsed a serial number")

PASS = "WEB ROOTS PASS"


def _records(bundle: bytes):
    count = int.from_bytes(bundle[6:8], "big")
    position = 16
    for _ in range(count):
        flags, scope_u, constraints_u = (
            int.from_bytes(bundle[position + o:position + o + 2], "big")
            for o in (0, 2, 4))
        cert_u = int.from_bytes(bundle[position + 6:position + 10], "big")
        distrust = int.from_bytes(bundle[position + 10:position + 18], "big")
        body = position + 18
        yield {
            "flags": flags,
            "scope": bundle[body:body + scope_u],
            "constraints": bundle[body + scope_u:
                                  body + scope_u + constraints_u],
            "cert": bundle[body + scope_u + constraints_u:
                           body + scope_u + constraints_u + cert_u],
            "distrust": distrust,
        }
        position = body + scope_u + constraints_u + cert_u
    assert position == len(bundle)


def test_generator_reproduces_the_committed_files() -> None:
    certdata = generator.CERTDATA.read_bytes()
    assert hashlib.sha256(certdata).hexdigest() == generator.CERTDATA_SHA256
    bundle, kept, left_out = generator.build(certdata)
    assert generator.BUNDLE.read_bytes() == bundle
    assert generator.PIN.read_text(encoding="utf-8") == (
        generator.pin_source(bundle, len(kept), left_out))


def test_bundle_holds_the_nss_server_roots() -> None:
    bundle = generator.BUNDLE.read_bytes()
    pin = generator.PIN.read_text(encoding="utf-8")
    assert bundle[:6] == b"MPTA\x00\x02"
    records = list(_records(bundle))
    assert f"{len(records)} CONSTANT WEB-ROOTS-COUNT" in pin
    assert f"{len(bundle)} CONSTANT WEB-ROOTS-BYTES" in pin
    digest = hashlib.sha256(bundle).digest()
    pinned = bytes(int(b) for b in re.findall(r"(\d+) C,", pin))
    assert pinned == digest
    assert len(records) == 112
    assert all(r["flags"] == 0 and r["scope"] == b"" for r in records)
    assert sum(1 for r in records if r["distrust"]) == 4
    held = [r for r in records if r["constraints"]]
    assert len(held) == 1
    tubitak = x509.load_der_x509_certificate(held[0]["cert"])
    assert "TUBITAK" in tubitak.subject.rfc4514_string()
    assert held[0]["constraints"] == b"\x30\x09\xa0\x07\x30\x05\x82\x03.tr"
    for record in records:
        cert = x509.load_der_x509_certificate(record["cert"])
        assert cert.extensions.get_extension_for_class(
            x509.BasicConstraints).value.ca
    assert "e-Szigno TLS Root CA 2023" in pin


def _bytes_forth(name: str, data: bytes) -> list[str]:
    rows = [f"CREATE {name}"]
    for offset in range(0, len(data), 16):
        rows.append(" ".join(f"{b} C," for b in data[offset:offset + 16]))
    return rows


def _contract() -> bytes:
    fixture = json.loads((harness.MEGAPAD_ROOT / "tests" / "fixtures" /
                          "tls" / "webpki_chains.json").read_text())
    lines = [
        "VARIABLE _wr-fails  VARIABLE _wr-checks  VARIABLE _wr-depth",
        "VARIABLE _wr-place  VARIABLE _wr-n",
        ": _wr-assert  ( flag -- )",
        "    1 _wr-checks +!",
        '    0= IF 1 _wr-fails +! ." ASSERT " _wr-checks @ . CR THEN ;',
        "\\ A place over the boot volume's root, granted in a set of its own,",
        "\\ as composition makes the origin of an image's shipped files.",
        ": _wr-declare  ( -- )",
        '    S" boot" PLACES-VOLUME ABORT" WEB ROOTS FAIL volume"',
        '    >R S" files" S" /" PLACE-WRITABLE R> PLACES-DECLARE',
        '    ABORT" WEB ROOTS FAIL place"',
        '    PLSET-NEW ABORT" WEB ROOTS FAIL set" >R',
        '    PLACE-WRITABLE SWAP R> PLSET-GRANT ABORT" WEB ROOTS FAIL grant"',
        "    _wr-place ! ;",
        ": _wr-anchors  ( offset -- n )",
        "    0 _wr-n !",
        "    TLS-TRUST-COUNT @ 0 ?DO",
        "        I TLS-TRUST@ OVER + @ IF 1 _wr-n +! THEN",
        "    LOOP DROP _wr-n @ ;",
    ]
    checks = []
    for index, entry in enumerate(fixture["hosts"]):
        chain = [base64.b64decode(c) for c in entry["chain"]]
        for position, data in enumerate(chain):
            lines += _bytes_forth(f"_wr-h{index}c{position}", data)
        lines.append(f"CREATE _wr-h{index} /X509-CERT {len(chain)} * ALLOT")
        parse = [
            f"    _wr-h{index}c{position} {len(data)} "
            f"_wr-h{index} /X509-CERT {position} * + "
            "X509-DESC-PARSE 0= _wr-assert"
            for position, data in enumerate(chain)
        ]
        checks += parse + [
            f'    _wr-h{index} {len(chain)} S" {entry["host"]}" '
            f'{fixture["now"]} X509-VERIFY-CHAIN',
            f'    DUP ." {entry["host"]}=" . 0= _wr-assert',
        ]
    lines += [
        ": _WR-RUN  ( -- )",
        "    0 _wr-fails ! 0 _wr-checks ! DEPTH _wr-depth !",
        "    _wr-declare",
        "    _wr-place @ WEB-ROOTS-REGISTER MTRUST-S-OK = _wr-assert",
        '    MTRUST-FREEZE DUP ." FREEZE=" . MTRUST-S-OK = _wr-assert',
        "    MTRUST-COUNT@ WEB-ROOTS-COUNT = _wr-assert",
        "    TLS-TRUST-COUNT @ WEB-ROOTS-COUNT = _wr-assert",
        "    TTA-SCOPE-U _wr-anchors 0= _wr-assert",
        "    TTA-NC-U _wr-anchors 1 = _wr-assert",
        "    TTA-DISTRUST _wr-anchors 4 = _wr-assert",
        *checks,
        "    DEPTH _wr-depth @ = _wr-assert",
        "    _wr-fails @ 0= IF",
        '        ." WEB ROOTS PASS " _wr-checks @ .',
        "    ELSE",
        '        ." WEB ROOTS FAIL " _wr-fails @ . ."  / " _wr-checks @ .',
        "    THEN CR ;",
    ]
    return ("\n".join(lines) + "\n").encode()


def test_root_set_loads_through_a_place_and_verifies_captured_chains(
        tmp_path: Path, monkeypatch) -> None:
    profile = "web-roots-contract"
    harness.PROFILES[profile] = harness.Profile(
        roots=("tui/platform/mp64fs-vfs.f", "net/web-roots.f"),
        resources=("net/web-roots/web-roots.mpta",),
        autoexec=(
            "\\ autoexec.f - the global root set, loaded and used\n"
            "ENTER-USERLAND\n"
            "REQUIRE tui/platform/mp64fs-vfs.f\n"
            "REQUIRE net/web-roots.f\n"
            "REQUIRE local_testing/web-roots-test.f\n"
            "_WR-RUN\n"
        ),
        ready_markers=(PASS,),
        stable_markers=(PASS,),
        failure_markers=("WEB ROOTS FAIL", "(not found)", "exception"),
        initial_files=(("local_testing/web-roots-test.f", _contract()),),
        include_large_sample=False,
        smoke_timeout=600.0,
    )
    run_profile_smoke(profile, tmp_path, monkeypatch)
