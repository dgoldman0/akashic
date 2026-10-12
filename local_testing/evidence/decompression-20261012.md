# Decompression: the inflater, PNG pictures in CELL, gzip web bodies — 2026-10-12

Part 13 of the [rich experience plan](../../docs/rich-terminal/RICH-EXPERIENCE-PLAN.md),
"Decompression", is done when "File Explorer's preview shows a PNG picture in
CELL, the inflater agrees with zlib on every check, and the web clients take
gzip bodies". This record gathers the checks for each, the physical regression
runs through the viewer, and step 6's measurements.

Guest steps are the simulator's semantic steps; an accelerated word counts as
one. The times are the simulator's, not a device's. None of this is UART,
panel, touch or live network evidence.

## Bindings

The physical runs bound clean source trees, unchanged at exit; the launcher
enforces both conditions.

| Binding | Value |
| --- | --- |
| Akashic | `f0625027b67d391de9f19741522216ab79183a0b` (tree `f23aea229cc850d5ed185f3a24d0f0a6c8e5172a`) |
| MegaPad | `2e1938ab09e5cd8f34e58c6a7e38d1eedb5400ed` (tree `e887ce652aae386e0306ad3bdaa7459ec30d270f`) |
| Native extension SHA-256 | `5a06333ad02eaf40b39fb67c2ce4a28069581073d625f1a6b351d212678ccbb6` |
| Launcher SHA-256 | `e5f1b34addac6c8d4556a2cf938bc93f536802750933197424b011a4a75ac316` |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |

Profile and settings: `desktop-apt1-fexp` and the damaged-picture profile in
ordinary source mode; simulator backend with the native executor; 18 px font,
0.75 s action delay, 10 s hold; 900 s watchdog and 3.5 GiB aggregate-RSS stop.
No compiled Forth cache, step-limit change or timing change was used.

## Physical regression runs

`local_testing/physical_desktop_acceptance.py --applet fexp` and
`--applet damaged`, one at a time:

| Run | Akashic | Result | Wall time | Peak aggregate RSS |
| --- | --- | --- | ---: | ---: |
| Desk with only File Explorer | `0ef80929` (PNG copies in CELL) | pass | 91.1 s | 492 MB |
| The damaged-picture check | `0ef80929` | pass | 48.3 s | 486 MB |
| Desk with only File Explorer | `f0625027` (final) | pass | 89.2 s | 492 MB |
| The damaged-picture check | `f0625027` (final) | pass | 45.5 s | 492 MB |

The first pair ran right after pictures began decoding PNG for CELL; the
second binds the final tree, after the inflater's no-window mode, the web
clients' gzip and the PNG row paths. File Explorer's sample picture is
`sunset.qoi`, and the rich side decodes pictures itself, so these runs prove
that the picture, PNG and inflater modules load and leave File Explorer's
journey and the damaged-picture refusal unchanged. They do not decode a PNG.

## PNG pictures in CELL

`PIC-START` decodes a PNG copy as it decodes QOI, a row at a time. The media
widget draws it in half blocks in CELL, through the same widget File Explorer's
preview uses:

- `test_media.py`: PNG copies of each kind, an interlaced PNG refused as
  unsupported, a zeroed PNG header as damaged.
- `test_media_widget.py`: a PNG drawn in blocks like a QOI picture, a PNG
  through the media widget, an interlaced PNG shown as its facts ("PNG,
  30 × 20").
- `test_uidl_picture_snapshot.py`: a PNG for a terminal that does not take
  PNG files gets a ready RGBA copy.
- `test_png.py` (35): every colour type and bit depth against Pillow, each
  filter, a palette with transparency, odd widths, fed in pieces; a damaged
  CRC, a cut IDAT, a missing IEND and an interlaced file refused.

## The inflater against zlib

- `test_adler32.py` (14): fixed and random data, fed in pieces, against
  `zlib.adler32`.
- `test_inflate.py` (41): every level and strategy in each wrapper; empty,
  tiny, random and repetitive data; the longest match and a hand-made
  reference 32,768 bytes back; stored blocks of 65,535 bytes; fed a byte at a
  time and in random pieces into output of every size down to one byte;
  damaged streams refused with each reason; cut streams that never end; input
  after the end left unused; and with no window, the output serving as the
  window.

## Gzip web bodies

The buffered exchange inflates a gzip body into the caller's response buffer,
which is the inflater's window; the bytes as sent and as inflated each count
against the buffer.

- `test_http_gzip.py` (27, native): each framing, split down to a byte at a
  time; x-gzip and any case; other codings kept as they came; a body
  inflating to exactly the buffer, one past it, and a 1 MB zip bomb stopped
  at 64 KB; a stored body sent past the buffer; a damaged member; trailing
  bytes and a second member; bodies cut inside the member; empty and 204
  bodies.
- The HTTP resource client's lifecycle contracts (`test_http_resource.py
  --lifecycle`): an inflated success, a damaged member, a body inflating past
  the budget, and a redirect whose gzip body takes the budget as sent. Pass,
  6.8 s.
- The public author feed profile: a gzip success, a damaged gzip body, and a
  body inflating past its 256 KiB. Pass, 30.6 s.
- The XRPC exchange's new gzip stage: a gzip getSession body inflated and
  admitted, a damaged member refused as `S-ENCODING`, a body inflating past
  the 4 KB arena refused as `S-CAPACITY`. 111 M of its 180 M steps. See the
  finding on XRPC tooling below for how it was run.

The buffered exchange's own contracts, the Streams syndication HTTP
contracts, the OAuth HTTP POST suites, the AT OAuth, inline, remote and
identity resource lifecycles, and the PAR vertical pass unchanged.

## Step 6's measurements

`local_testing/measure_decompression.py`, every output checked against
Python's zlib or the QOI reference decoder.

The inflater, steps per byte given, 200,000 bytes:

| Data | Blocks | Steps a byte |
| --- | --- | ---: |
| English-like text | stored (level 0) | 0.06 |
| English-like text | fixed codes (level 6, `Z_FIXED`) | 61.6 |
| English-like text | dynamic codes, level 1 | 112.1 |
| English-like text | dynamic codes, level 6 | 60.0 |
| English-like text | dynamic codes, level 9 | 52.9 |
| English-like text | level 6, zlib | 73.0 |
| English-like text | level 6, gzip | 63.5 |
| Random bytes | stored | 0.06 |
| Random bytes | stored, zlib | 13.1 |
| One byte repeated | level 9 | 3.4 |

The sample picture, 160 by 100, to RGBA rows:

| File | Bytes | Steps a pixel, first | Steps a pixel, final |
| --- | ---: | ---: | ---: |
| QOI | 4,601 | 120 | 120 |
| PNG, filter None, zlib level 6 | 2,327 | 519 | 146 |
| PNG, filter Up | 1,058 | 594 | 220 |
| PNG, filter Sub | 1,710 | 616 | 242 |
| PNG, filter Average | 1,917 | 746 | 372 |
| PNG, filter Paeth | 1,378 | 1,062 | 689 |
| PNG as Pillow writes it | 1,500 | 987 | 613 |
| PNG, Pillow optimize | 1,303 | 982 | 608 |

## Findings

- The first PNG costs showed the row's conversion to RGBA, a sample at a
  time, was most of the cost: for an eight-bit RGBA row it rewrote each byte
  unchanged. Such a row now goes out with one move, and an eight-bit RGB row
  without a transparent colour in a short loop (`f0625027`). The filters are
  now most of the cost, Paeth at about 136 steps a byte.
- Fixed codes cost about what dynamic ones do; level 1 costs most, since it
  leaves the most literals.
- The inflater's no-window mode, for a caller that keeps the whole output,
  costs the same steps as a 32 KB window and saves its memory; each gzip web
  client carries a 3,024-byte inflater record instead of 35.8 KB.
- Pre-existing tooling failures, not caused by this work. The XRPC exchange
  and auth-read verticals and both P-256 verticals failed the same way at the
  commit before it; the others fail on files it did not touch. The staged
  XRPC drivers (exchange, feed, bidirectional, create-record)
  never load MegaPad's networking.f, which `kdos-tls-port.f` needs, and stop
  at "TLS-E-BUSY ? (not found)"; networking.f inside their first stage passes
  its 180 M-step limit. The XRPC exchange stages were run through a scratch
  wrapper that loads networking.f as a stage of its own, every checked-in
  stage still at 180 M: all pass. The auth-read vertical fails its
  procedure-build stage at assert 157; the authenticated-provider vertical
  refuses `unicode-tables.f`, whose 42 KB unit passes its 12 KB checkpoint;
  the network hostname check expects `TLS-CH-BUF-CAPACITY` 1280 where
  MegaPad's is 1536; and the P-256 PAR and token verticals stop on a
  `PROVIDED` collision for `akashic-memory-span`.

## Not covered

- A physical run that previews a PNG in CELL: the physical journeys show the
  QOI sample, and the rich side decodes pictures itself. PNG in CELL is
  proved through the media widget's tests.
- Gzip bodies from a live server: the web clients' evidence is their
  deterministic fakes.
- Compressing, interlaced PNG in CELL (it shows the picture's facts), gzip
  files of several members (refused as trailing bytes in a web body), and
  colour profiles and gamma.
