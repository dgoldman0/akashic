# Canonical 22-stage physical Desktop journey — 2026-09-26

The full Desktop regression journey is now tracked. Its seven menu stages
previously existed only in the untracked wrapper `physical_menu_acceptance.py`;
they are now part of the canonical `DesktopAcceptanceJourney`. The tracked
guarded launcher `local_testing/physical_desktop_acceptance.py` was run once to
confirm the journey end to end with the native simulator. It **passed**.

This is functional regression evidence for the harness change. It is not a
timing comparison with earlier runs, and not UART, panel, or touch evidence.

## Bindings

Both source trees were clean at launch and unchanged at exit; the launcher
enforces both conditions.

| Binding | Value |
| --- | --- |
| Akashic | `78a6f9ef43307af121d133657bbeba9df8e3876c` (tree `bc142941b52ed6731c3a072edc155883683b2cc7`) |
| MegaPad | `370e2ac9e2093bb160bcb163d7b086a5d7f63f87` (tree `d321cddc1cbae7da4cbf130872cbca5e19eb63a5`) |
| Native extension SHA-256 | `120704dae29f3a22c29c38153d888b379e42277af566aa11d2f2c2a3ecfd6a4c` (the binary qualified on 2026-09-17) |
| Launcher SHA-256 | `85a513f9e7a52c6f733b2a6ec31b3dbdb9bda32314575891e37d3c5dff5c0c01` |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |

Profile and settings:

- `desktop-apt1` in ordinary source mode;
- simulator backend with `MEGAFORTH_EXECUTOR=native`;
- 280x84, 18 px font, 0.75 s action delay, 10 s hold;
- 900 s watchdog and 3.5 GiB aggregate-RSS stop.

No compiled Forth cache, step-limit change, or timing change was used.

```bash
python3 local_testing/physical_desktop_acceptance.py \
  --akashic-root . --megapad-root ../megapad \
  --font assets/fonts/DejaVuSansMono.ttf \
  --output-parent local_testing/out/physical-desktop-20260926
```

## Result

- Exit 0 with no stop reason, in 125.354 s including image build.
- Peak aggregate RSS 461,139,968 bytes (439.8 MiB).
- 18 milestones, in order:
  1. `desk-complete`
  2. `pad-file-menu-open`
  3. `pad-file-menu-closed`
  4. `pad-edited`
  5. `daybook-task-added`
  6. `daybook-date-advanced`
  7. `daybook-source-opened-in-pad`
  8. `pad-tab-activated`
  9. `desk-launcher-open`
  10. `soundlab-launch-source`
  11. `soundlab-instruments-live`
  12. `fexplorer-view-focused`
  13. `fexplorer-view-open`
  14. `fexplorer-view-closed`
  15. `daybook-go-focused`
  16. `daybook-go-open`
  17. `daybook-go-closed`
  18. `soundlab-restored-after-menus`
- 21 revision-bound inputs with zero manual input RPCs. The seven new inputs
  are:
  - `alt+2`;
  - the File Explorer View `CONTROL_EVENT`;
  - `escape` against the complete View popup;
  - `alt+3`;
  - the Daybook Go `CONTROL_EVENT`;
  - `escape` against the Go popup;
  - `alt+6`.
- 27 post-flip physical acknowledgements through the `pygame.display.flip`
  X11 sink.
- The initial (offer 1) and final (offer 27) CELL fallback gates both passed.

The milestone and input sequences match the September 12–17 wrapper runs,
such as `physical-menus-lr_4of8a` recorded in
`docs/rich-terminal/SIMULATOR-CALLS-PERFORMANCE-20260917.md`. The
`daybook-go-open` capture was inspected: the Go popup paints above the
calendar grid, and the complete 3x2 Desk, Pad's two tabs with the `~` edit,
and Sound Lab's live instruments are visible.

## Artifact hashes

The artifacts are in
`local_testing/out/physical-desktop-20260926/physical-desktop-b7ka8i6m/`,
which is ignored.

| File | SHA-256 |
| --- | --- |
| `evidence/manifest.json` | `53bee08b6dd86eb4014c5873fcd3387d3e6165435f2cfd4a1a761c6b383d84f0` |
| `evidence/performance-trace.json` | `a339db913251047cfb519a5ea8e4ad46f2b5493dd31f993a07b3e231cf904289` |
| `bindings.json` | `afc5a5ca8b837dd416a6af169c577e839bf15ce09e068682c54da51a698899c9` |
| `supervisor.json` | `a3c63272461cf0f9332e6454a918078e3e0f03f381c403f67d9cf5826af13e9f` |
