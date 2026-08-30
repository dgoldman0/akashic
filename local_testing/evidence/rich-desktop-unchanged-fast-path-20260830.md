# Rich Desktop certified-unchanged fast-path rerun — 2026-08-30

Status: successful non-normative performance evidence for the conservative
unchanged-representation shortcut. The complete ordinary Desk/Pad/Daybook
journey passed at the local pygame presentation-API boundary. This evidence
does not qualify physical UART delivery, panel scanout, e-paper settling,
touch, RTL cycles, or wall time on a future processor.

## Isolated committed revisions

The final run used clean isolated checkouts, not the concurrently edited rich
vertical worktrees:

- Akashic `f60811ec678f6e94d5fa32130582b96353786fa8`;
- MegaPad `3d7d819bdae305f4663023a942af702702c3ef86`;
- the pre-UART native accelerator matching that MegaPad revision.

This isolation matters. An earlier discarded attempt read the active MegaPad
worktree while its BIOS/UART capability fallback and native header were being
edited. Its native extension did not match the new header, so BIOS selected an
incomplete direct-UART path and lost CR/LF bytes written through an
unregistered ring. That attempt is neither semantic nor performance evidence.

The accepted command was the original hold-zero route:

```text
MEGAPAD_ROOT=<clean-megapad-3d7d819> \
python local_testing/akashic_tui.py accept \
  --profile desktop-apt1 \
  --hold-seconds 0 \
  --phase-profile \
  --phase-profile-max-events 4096
```

It linked 202 modules in 28 chunks, passed all twelve offers, and exited zero
after 193.524 seconds. The ignored raw artifact directory contained:

- `performance-trace.json`, SHA-256
  `288ee818d56b9206ea0506a848aed7c95e635f509af2ef185e3f2a82e09eb4aa`;
- `manifest.json`, SHA-256
  `34d58075d496c1eef82850b43b830c7ffb2927ded14da7eecff8d9a43df0aac1`.

## What the certificate proves

The UIDL aggregate carries a nonzero content epoch forward only when every
visible nonempty document came from its exact validated prior record/text
slice, no live recapture occurred, and the complete directory, document count,
record total, and text total are identical. This is a provenance certificate,
not a digest or a revision comparison.

The producer uses that epoch only when the prior packed target is the exact
physically acknowledged active target, its complete owner, generation,
geometry, object frontier, counts, text usage, physical generation, current
limits, and draw bindings validate, the new screen plan is non-forced, and the
complete CELL row-damage map is zero. It clones only the validated used packed
prefix into the inactive bank, rebases its two bank-local control text-pointer
forms, and emits the normal one-operation revision fence. Every failed or
ambiguous proof falls through to the ordinary complete build.

The shortcut still performs real work proportional to the retained target:
validated UIDL slice reuse, packed-target validation, one packed-prefix copy,
control-text pointer rebasing, and one row-damage scan. It deliberately avoids
the more expensive control, claim, residual, hybrid-preflight, packing,
inverse-map, and deep-delta passes. Logical revision, transaction, offer,
physical composition, and exact acknowledgement remain mandatory.

## Exact unchanged interaction

Offers 1 and 2 were the same concrete case used by the pre-change profile.
They advanced CELL, model, and retained revisions from 4 to 5 while retaining:

- draw count 809;
- complete pixel SHA-256
  `2c4f4ba2617814d1cf6583f450b71d12a8cc557b9069e154badd13b4442c18b9`;
- retained-only pixel SHA-256
  `35164eb37df45dce56ce1328977675c9a092da633d0696eb1c06ae638dcd5988`;
- retained-text SHA-256
  `2a79c7fc4bfafc719ccac9a9647aa6bfc63d15da5a556504b43eee6a68e9d0c3`.

Their exact offer-status gap fell from 69.5M retired guest instructions in the
qualified pre-change run to 44.0M: 25.5M fewer instructions, or 36.7%. A prior
isolated validation of the same source state measured 43.0M, so the intended
case repeated within one 500,000-instruction scheduler batch.

The phase observer saw ten, rather than eleven, complete visits to each of
control planning, claim planning, residual planning, hybrid preflight, target
packing, and delta comparison. That is direct evidence that offer 2 skipped
the ordinary reconstruction path rather than merely making its comparison
slightly cheaper.

Across the observer window, hybrid preflight fell from 159.5–170.5M to
146.5–156.5M instructions and delta comparison from 257–268M to 232.5–242.5M.
Their combined bounded reduction was 37.5–39.5M. The final observer stopped at
the final offer boundary while `WIRE_ENCODE` was still open; it had no drop,
read error, or straddling transition, but its complete-window phase attribution
is correctly marked incomplete for that terminal open phase.

## Whole-journey interpretation

The shortcut is a narrow interaction-latency win, not a general speedup claim.
Cold start through offer 1 increased from 4,088.5M to 4,093.5M instructions,
roughly 5M or 0.12%. From offer 1 through offer 12, the new run used 931.5M
instructions versus 936M before, 4.5M fewer. End to end through the final offer
was consequently almost unchanged: 5,025M versus 5,024.5M.

Later offer gaps moved in both directions, and the new run emitted 1,771
protocol frames and 237 machine publications versus 1,787 and 238 before. The
acceptance client and guest can expose different transient publications while
waiting for the same milestones, so those later differences are not assigned
to the shortcut. The supported conclusion is only that the certified unchanged
case became about 37% cheaper without weakening presentation or ACK semantics.

Cross-revision frame hashes differ because Fexplorer visibly reports the sizes
of the newly linked Akashic source chunks. A line-by-line comparison found only
those source-size labels; nonblack retained-pixel counts and all journey
milestones remained unchanged. Within the new run, offers 1 and 2 are exactly
pixel- and retained-text-identical as required.

## Physical boundary still open

The manifest's physical boundary remains `pygame.display.flip()` on X11. The
run did not traverse an attached UART, e-paper controller, panel waveform, or
settle sensor. It therefore cannot decide compression, a faster physical link,
partial-refresh thresholds, ghosting policy, color conversion, or touch
cadence.
