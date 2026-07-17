# Desk Gate 0 retained baseline

These files freeze the durable Streams records that existed when the final
Desk ecosystem contract was ratified. They are compatibility evidence, not a
new format and not seed data for ordinary users.

The valid records are produced through the production Forth encoders and
stores on a temporary MP64FS image. Each corrupt record differs from its valid
counterpart by one flipped byte at the start of the payload while retaining
the original payload CRC. Each future record retains the V1 payload, sets the
common-envelope format cell to `2`, and recomputes the header CRC so the V1
reader must classify it as `UNSUPPORTED`, not `CORRUPT`.

`draft-v1-legacy-r7.bin` is the exact historical compatibility witness:
revision `7`, UTF-8 text `exact ☂ café`, and no padding beyond its 15-byte
payload. Its SHA-256 is part of the migration boundary.

Regenerate intentionally from the nested repository root with:

```sh
python3 local_testing/generate_desk_gate0_fixtures.py
```

The command is deterministic. Any byte change must be reviewed against
`manifest.json`; do not update hashes merely to make a test pass. Verify the
host-side ledger and the production readers with:

```sh
python3 -m pytest -q local_testing/test_desk_gate0_baseline.py
python3 local_testing/akashic_tui.py smoke \
  --profile desk-gate0-baseline --max-steps 8000000000 --timeout 120
```

The executable profile also covers the important asymmetric state where a
valid nonempty `/streams-sources.bin` exists but
`/streams-observation.bin` does not. That state remains “never refreshed or
unproven companion loss”; it must never be rewritten as a proven clean empty
observation history.

`manifest.json` also retains the exact 27-profile deterministic Gate 0
matrix. Most profiles were qualified with an eight-billion-step, 120-second
ceiling. The complete Desk Agent hardening journey has a measured baseline of
15.21 billion steps and therefore uses its recorded 16-billion-step,
240-second override; lowering that ceiling is not evidence of a product
regression.
