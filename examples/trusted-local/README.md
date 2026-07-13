# Trusted-local Hello applet

This is the acceptance applet for Akashic's first creator loop. Copy
`hello.f` and `project.toml` to the machine as `/hello.f` and
`/hello.toml`, open the project manifest in Pad, and choose **Build &
Install**.

The package is native Forth with ambient authority. Its manifest and
SHA3 digests provide deterministic binding and corruption detection;
they do not provide sandboxing, signatures, or remote trust.
