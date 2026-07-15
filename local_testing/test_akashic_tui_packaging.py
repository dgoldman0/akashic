"""Deployment-linker regressions for bootable Akashic images."""

from __future__ import annotations

import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
if str(LOCAL_TESTING) not in sys.path:
    sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import (  # noqa: E402
    PROVIDED_RE,
    REQUIRE_RE,
    _minify_forth,
    build_image,
    dependency_closure,
)
from diskutil import MP64FS  # noqa: E402


def test_full_line_comments_follow_megapad_prefix_rule() -> None:
    assert _minify_forth("\\TOKEN DROP\n") == ""
    assert _minify_forth("  \\TOKEN DROP\n") == ""
    assert _minify_forth("S\\TOKEN DROP\n") == "S\\TOKEN DROP\n"


def test_only_ascii_space_is_a_megapad_source_delimiter() -> None:
    assert _minify_forth("\t\\ comment\n") == "\t\\ comment\n"
    assert _minify_forth(" \t\\ comment\n") == "\t\\ comment\n"
    assert _minify_forth("\N{NO-BREAK SPACE}42\n") == "\N{NO-BREAK SPACE}42\n"


def test_dependency_markers_require_ascii_space_separation() -> None:
    assert REQUIRE_RE.match("REQUIRE module.f")
    assert PROVIDED_RE.match("PROVIDED module-id")
    assert REQUIRE_RE.match("REQUIRE\tmodule.f") is None
    assert PROVIDED_RE.match("PROVIDED\tmodule-id") is None


def test_inline_comments_and_parser_word_input_remain_intact() -> None:
    sources = (
        "1 2 + \\ comment\n",
        ": \\ 42 ;\n",
        "CREATE \\ 8 ALLOT\n",
        "1 1 1 BUFFER \\ 8 ALLOT\n",
        "DNS-LOOKUP \\ DROP\n",
        "[CHAR] \\ EMIT ;\n",
        'S" a \\ path" DROP  \\ comment\n',
    )
    for source in sources:
        assert _minify_forth(source) == source


def test_only_flat_colon_header_stack_effect_is_removed() -> None:
    assert _minify_forth(": INC ( n -- n+1 ) 1+ ;\n") == (
        ": INC 1+ ;\n"
    )
    assert _minify_forth(": INC ( n -- n+1 )1+ ;\n") == (
        ": INC 1+ ;\n"
    )
    assert _minify_forth("64 CONSTANT XT \\ ( x -- y )\n") == (
        "64 CONSTANT XT \\ ( x -- y )\n"
    )
    assert _minify_forth("( x -- y )\n") == "( x -- y )\n"
    nested = ": INC ( n ( nested ) -- n+1 ) 1+ ;\n"
    assert _minify_forth(nested) == nested


def test_stack_looking_strings_and_unterminated_strings_are_preserved() -> None:
    source = 'S" literal ( x -- y ) text" DROP  \\ comment\n'
    assert _minify_forth(source) == source
    source = '0 ABORT" literal ( x -- y ) text" \\ comment\n'
    assert _minify_forth(source) == source
    source = 'S" unterminated   \n'
    assert _minify_forth(source) == source
    source = '." unterminated   \n'
    assert _minify_forth(source) == source
    source = '0 ABORT" unterminated   \n'
    assert _minify_forth(source) == source


def test_indentation_removal_does_not_touch_string_spaces() -> None:
    source = '    S"   retained text" DROP  \\ comment\n'
    assert _minify_forth(source) == (
        'S"   retained text" DROP  \\ comment\n'
    )


def test_conditional_control_tokens_are_never_compacted_out() -> None:
    for token in ("[IF]", "[ELSE]", "[THEN]", "[then]"):
        comment = f"  \\ skipped {token} marker\n"
        assert _minify_forth(comment) == comment.lstrip(" ")
        stack_effect = f": WORD ( -- {token} ) ;\n"
        assert _minify_forth(stack_effect) == stack_effect


def test_ordinary_streams_excludes_public_network_composition() -> None:
    modules = set(
        dependency_closure(("tui/applets/streams/streams.f",))
    )
    assert "tui/applets/streams/public-provider.f" in modules
    assert "tui/applets/streams/bluesky-public.f" not in modules
    assert "atproto/public-author-feed.f" not in modules
    assert "atproto/public-trust.f" not in modules
    assert "net/transports/kdos-tls.f" not in modules


def test_explicit_bluesky_composition_still_does_not_supply_trust() -> None:
    modules = set(
        dependency_closure(("tui/applets/streams/bluesky-public.f",))
    )
    assert "tui/applets/streams/streams.f" in modules
    assert "atproto/public-author-feed.f" in modules
    assert "net/transports/kdos-tls.f" in modules
    assert "atproto/public-trust.f" not in modules


def test_complete_desktop_fits_fixed_mp64fs_with_reserve(
    tmp_path: Path,
) -> None:
    image = build_image("desktop", tmp_path / "akashic-desktop.img")
    assert image.stat().st_size == 4096 * 512
    filesystem = MP64FS(bytearray(image.read_bytes()))
    info = filesystem.info()
    assert info["total_sectors"] == 4096
    assert info["free_sectors"] >= 64
