"""The passphrase keyring, akashic/security/passphrase-keyring.f.

Runs the contract local_testing/keyring-test.f on the native runtime over
the keyring's closure, with the keyring's file on a RAM volume of the
check's own (local_testing/test-root-place.f), at small iteration counts:
setup in steps and the progress it reports, the key the resolver lends and
the ids it refuses, lock and the wanted flag, a second keyring over the
same file with a wrong and a right passphrase, a change of passphrase and
count that keeps the key, a cancel, the sealed-record contract through the
keyring's resolver, a count changed in the file, which reads as
corrupt rather than as a wrong passphrase, and starting over: from a
locked keyring no passphrase opens, where a cancel keeps the old file and
the old key's secrets then read as an unknown key, and from files of
another size or header, which read as damaged.
"""

from __future__ import annotations

from pathlib import Path

from native_forth import NativeForth

LOCAL_TESTING = Path(__file__).resolve().parent

PRELUDE = (
    (LOCAL_TESTING / "test-root-place.f").read_text(encoding="utf-8")
    + (LOCAL_TESTING / "keyring-test.f").read_text(encoding="utf-8")
)

SUITE = NativeForth(
    ("security/passphrase-keyring.f", "utils/fs/vfs.f"),
    prelude=tuple(PRELUDE.splitlines()),
)


def test_contract() -> None:
    output = SUITE.run(["_KT-RUN"], 2_000_000_000).decode("latin-1")
    assert "KEYRING PASS" in output, output[-2000:]
    assert "KT ASSERT" not in output and "KEYRING FAIL" not in output, output[-2000:]
