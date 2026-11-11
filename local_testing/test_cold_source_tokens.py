"""The cold-source loader with token forms in its containers.

A linked chunk of a token build keeps its AKSRC001 container and holds the
chunk's token form in place of its source (MegaPad's
docs/token-modules-proposal-2026-11-11.md).  The loader hands a payload
that begins as a token file to KDOS's TOKEN-EVALUATE-CHECKED and any other
to SOURCE-EVALUATE-CHECKED.

These tests run the loader in the simulator with containers on the boot
disk.  The token files are those of MegaPad's tests/token_module_cases.py.
Each refusal plants one fault and holds the loader to reporting it, naming
the file, and leaving nothing of the chunk behind.
"""
from __future__ import annotations

from pathlib import Path

from diskutil import FTYPE_DATA, MP64FS

import akashic_tui
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime
from simulator.storage import HostedStorageService
from test_textarea import MEGAPAD_ROOT
from tests.token_module_cases import OTHER_SYSTEM, tokens

LOADER = Path(__file__).resolve().with_name("cold-source-loader.f")
EVALUATE_FAILED = 12
PLAIN = b": S-WORD 7 ;\n"


def _container(payload: bytes) -> bytes:
    return akashic_tui._pack_cold_source(
        payload, codec=akashic_tui.COLD_SOURCE_CODEC_STORED
    )


class Machine:
    """KDOS with the cold-source loader, and FILES on the boot disk."""

    def __init__(self, files: dict[str, bytes]) -> None:
        fs = MP64FS(total_sectors=2048)
        fs.format()
        for name, data in files.items():
            fs.inject_file(name, data, ftype=FTYPE_DATA)
        self.runtime = MegaForthRuntime(
            memory=create_one_core_address_space(external_size=128 << 20),
            execution_backend="native",
            storage=HostedStorageService(bytes(fs.img)),
        )
        self.runtime.evaluate(
            (MEGAPAD_ROOT / "kdos.f").read_bytes(), source_name="kdos.f"
        )
        self.runtime.evaluate(b"ENTER-USERLAND", source_name="userland")
        self.runtime.evaluate(LOADER.read_bytes(), source_name="loader")
        self.runtime.drain_uart_output()

    def run(self, source: str) -> tuple[int, ...]:
        self.runtime.evaluate(source.encode(), source_name="check")
        stack = self.runtime.main_context.data.snapshot()
        self.runtime.main_context.data.clear()
        assert self.runtime.main_context.returns.snapshot() == ()
        return stack

    def said(self) -> str:
        return " ".join(
            self.runtime.drain_uart_output().decode("latin-1").split()
        )

    def named(self) -> str:
        """The file the last load named."""

        self.said()
        self.run("CSL-LAST-NAME TYPE")
        return self.said()


def test_token_and_source_chunks_load_in_whatever_order() -> None:
    machine = Machine(
        {
            "tok-a.src": _container(tokens("a", 11)),
            "src-s.src": _container(PLAIN),
            "tok-c.src": _container(tokens("c", 30)),
        }
    )

    # A token chunk is used when it was built for this system, whatever was
    # loaded before it: another token chunk, a source chunk, or nothing.
    assert machine.run("COLD-SOURCE-LOAD tok-c.src  C-WORD") == (0, 30)
    assert machine.run("COLD-SOURCE-LOAD src-s.src  S-WORD") == (0, 7)
    assert machine.run("COLD-SOURCE-LOAD tok-a.src  A-WORD") == (0, 11)
    assert machine.named() == "tok-a.src"
    assert "cannot" not in machine.said()


def test_a_token_chunk_that_cannot_be_replayed_is_reported_and_leaves_nothing() -> None:
    good = tokens("a", 11)
    machine = Machine(
        {
            "other.src": _container(tokens("a", 11, boot_id=1)),
            "cut.src": _container(good[:-3]),
            "none.src": _container(tokens("a", 11, boot_id=0)),
            "good.src": _container(good),
        }
    )
    here = machine.run("HERE LATEST")

    for name, status in (("other.src", 7), ("cut.src", 6), ("none.src", 7)):
        assert machine.run(f"COLD-SOURCE-LOAD {name}  CSL-LAST-EVAL@") == (
            EVALUATE_FAILED, status,
        ), name
        said = machine.said()
        assert (OTHER_SYSTEM in said) == (status == 7), name
        assert machine.named() == name
        assert machine.run("[DEFINED] A-WORD") == (0,)
        assert machine.run("HERE LATEST") == here
    # Nothing a refused chunk did stands in the way of the right one.
    assert machine.run("COLD-SOURCE-LOAD good.src  A-WORD") == (0, 11)
    assert machine.run("COLD-SOURCE-LOAD absent.src") == (1,)
    assert machine.named() == "absent.src"
