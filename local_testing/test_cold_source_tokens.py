"""The cold-source loader with token forms in its containers.

A linked chunk of a token build keeps its AKSRC001 container and holds the
chunk's token form in place of its source (MegaPad's
docs/token-modules-proposal-2026-11-11.md).  The loader hands a payload
that begins as a token file to KDOS's TOKEN-EVALUATE-CHECKED and any other
to SOURCE-EVALUATE-CHECKED, after telling KDOS that the load of a source
file begins, so that the stamp of the load holds every chunk in order.

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
from tests.token_module_cases import A, C, STALE, stamps, tokens

LOADER = Path(__file__).resolve().with_name("cold-source-loader.f")
EVALUATE_FAILED = 12
PLAIN = b": S-WORD 7 ;\n"
START = stamps()[0]


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


def test_token_and_source_chunks_load_in_order_under_one_stamp() -> None:
    at = stamps(A, PLAIN)
    machine = Machine(
        {
            "tok-a.src": _container(tokens("a", 11, stamp=at[0])),
            "src-s.src": _container(PLAIN),
            "tok-c.src": _container(tokens("c", 30, stamp=at[2])),
        }
    )

    assert machine.run("COLD-SOURCE-LOAD tok-a.src  A-WORD") == (0, 11)
    assert machine.run("COLD-SOURCE-LOAD src-s.src  S-WORD") == (0, 7)
    # The source chunk is part of the stamp: the token chunk recorded after
    # it is current only because the loader said that its load began.
    assert machine.run("COLD-SOURCE-LOAD tok-c.src  C-WORD") == (0, 30)
    assert machine.run("LOAD-STAMP @") == (stamps(A, PLAIN, C)[3],)
    assert machine.named() == "tok-c.src"
    assert "cannot" not in machine.said()


def test_a_source_chunk_with_another_text_makes_the_next_token_chunk_stale() -> None:
    at = stamps(A, PLAIN)
    machine = Machine(
        {
            "tok-a.src": _container(tokens("a", 11, stamp=at[0])),
            "src-s.src": _container(b": S-WORD 8 ;\n"),
            "tok-c.src": _container(tokens("c", 30, stamp=at[2])),
        }
    )

    assert machine.run("COLD-SOURCE-LOAD tok-a.src") == (0,)
    assert machine.run("COLD-SOURCE-LOAD src-s.src  S-WORD") == (0, 8)
    here = machine.run("HERE LATEST")
    assert machine.run("COLD-SOURCE-LOAD tok-c.src  CSL-LAST-EVAL@") == (
        EVALUATE_FAILED, 7,
    )
    assert STALE in machine.said()
    assert machine.named() == "tok-c.src"
    assert machine.run("[DEFINED] C-WORD") == (0,)
    assert machine.run("HERE LATEST") == here


def test_a_token_chunk_that_cannot_be_replayed_is_reported_and_leaves_nothing() -> None:
    good = tokens("a", 11, stamp=START)
    machine = Machine(
        {
            "stale.src": _container(tokens("a", 11, stamp=START ^ 1)),
            "cut.src": _container(good[:-3]),
            "none.src": _container(tokens("a", 11, stamp=0)),
            "good.src": _container(good),
        }
    )
    here = machine.run("HERE LATEST")

    for name, status in (("stale.src", 7), ("cut.src", 6), ("none.src", 7)):
        assert machine.run(f"COLD-SOURCE-LOAD {name}  CSL-LAST-EVAL@") == (
            EVALUATE_FAILED, status,
        ), name
        said = machine.said()
        assert (STALE in said) == (status == 7), name
        assert machine.named() == name
        assert machine.run("[DEFINED] A-WORD") == (0,)
        assert machine.run("HERE LATEST") == here
    # Nothing a refused chunk did stands in the way of the right one.
    assert machine.run("COLD-SOURCE-LOAD good.src  A-WORD") == (0, 11)
    assert machine.run("COLD-SOURCE-LOAD absent.src") == (1,)
    assert machine.named() == "absent.src"
