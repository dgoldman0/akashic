"""The image tool: build a machine's volumes from a description of it.

The modules, in the order they depend on one another:

- megapad: where Akashic and the MegaPad checkout sit;
- closure: KDOS's REQUIRE and PROVIDED grammar and a module's closure;
- forth: Forth source text as the tool reads and rewrites it;
- rich: the rich terminal's host bounds, the canonical Desktop's among them;
- desk: Desk's composition from a list of applets;
- ext4: the ext4 profile the volumes are built to;
- build: the volumes themselves (build.build).

Akashic's test harness (local_testing/akashic_tui.py) builds every profile
through build.build, and the fantasy-engine command builds configurations
with it.
"""
