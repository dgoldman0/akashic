"""Host-only architecture ratchets for the storage-free Streams SR1 core."""

from __future__ import annotations

import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
if str(LOCAL_TESTING) not in sys.path:
    sys.path.insert(0, str(LOCAL_TESTING))

from forth_dependencies import dependency_closure  # noqa: E402
from refactor_inventory import (  # noqa: E402
    MUTABLE_DEFINITION_KINDS,
    SOURCE_ROOT,
    _lexical_definitions,
)


FLOW_CORE = "tui/applets/streams/flow-core.f"
FLOW_CORE_PATH = SOURCE_ROOT / FLOW_CORE


def test_streams_sr1_core_dependency_closure_is_storage_free() -> None:
    closure = set(dependency_closure(SOURCE_ROOT, (FLOW_CORE,)))
    forbidden_prefixes = (
        "persistence/",
        "utils/fs/",
        "net/",
        "web/",
        "atproto/",
        "library/",
        "tui/applets/library/",
    )
    forbidden_streams_prefixes = (
        "tui/applets/streams/source",
        "tui/applets/streams/observation",
    )
    forbidden_streams_modules = {
        "tui/applets/streams/repository.f",
        "tui/applets/streams/runtime-owner.f",
        "tui/applets/streams/streams.f",
    }

    assert FLOW_CORE in closure
    assert not {
        module
        for module in closure
        if module.startswith(forbidden_prefixes)
        or module.startswith(forbidden_streams_prefixes)
        or module in forbidden_streams_modules
    }


def test_streams_sr1_core_owns_no_top_level_mutable_storage() -> None:
    definitions = _lexical_definitions(
        FLOW_CORE_PATH.read_text(encoding="utf-8")
    )
    mutable_definitions = {
        kind: definitions[kind]
        for kind in MUTABLE_DEFINITION_KINDS
        if definitions[kind]
    }

    assert mutable_definitions == {}
