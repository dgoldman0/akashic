# AES-encrypted PDFs: the physical regression — 2026-10-12

Part 14's step 8 now opens AES-encrypted PDFs (AESV2, and AESV3 of
revisions 5 and 6) through CBC in MegaPad's AES engine and SHA-384 in its
BIOS. File Explorer's PDF reader therefore loads `math/aes.f`,
`math/sha256.f` and `math/sha512.f` with `pdf/crypt.f`. The guarded launcher
`local_testing/physical_desktop_acceptance.py` ran Desk with only File
Explorer, then the canonical Desktop journey, with the native simulator,
as the regression for that work. Both **passed**.

This is functional regression evidence. The times are the simulator's, not
a device's, and none of this is UART, panel or touch evidence. The journeys
are those of `pdf-journey-20261012.md`, unchanged: they preview the sample
PDFs, including the RC4-encrypted copy, but no AES file; qpdf's AES-128 and
AES-256 files are read by `local_testing/test_pdf_crypt.py` on the hosted
simulator, and the AES engine's CBC by `local_testing/test_aes_contract.py`
on the emulator with the real BIOS.

## Bindings

| Binding | Both runs |
| --- | --- |
| Akashic | `6dda16f2` (tree `8991bdf6`), clean |
| MegaPad | `870848cb` (tree `075a42db`), clean |
| Native extension SHA-256 | `5a06333a…` |
| Launcher SHA-256 | `e5f1b34a…` |
| Font | DejaVuSansMono.ttf, `b4a6c3e4…` |

`bindings.json` in each run's artifacts records the full hashes, the
styled faces and the fallback fonts. Neither tree changed during either
run; the launcher enforces that.

Profiles and settings: `desktop-apt1-fexp` and `desktop-apt1` in ordinary
source mode; simulator backend with the native executor; 280x84, 18 px
font, 0.75 s action delay, 10 s hold; 900 s watchdog and 3.5 GiB
aggregate-RSS stop. No compiled Forth cache, step-limit change or timing
change was used.

## Runs

| Run | Stages | Result | Wall time | Peak aggregate RSS |
| ---: | ---: | --- | ---: | ---: |
| Desk with only File Explorer (`--applet fexp`) | 34 | pass | 127.7 s | 505 MB |
| Canonical Desktop journey | 55 frames | pass | 244.7 s | 571 MB |

Against the earlier runs (129.9 s and 502 MB, 247.6 s and 571 MB), the
larger PDF reader costs no measurable time or memory in either journey.
