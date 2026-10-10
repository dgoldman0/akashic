# Supervised full-core worker jobs

`worker-job.f` provides a bounded one-shot worker contract. It is not a
thread pool, a second applet event loop, or permission to call arbitrary
Akashic words on another core.

The owner core allocates a `WJOB-SIZE` descriptor and disjoint caller-owned
input, output, and scratch spans. It prepares the descriptor with an explicit
execution class, generation, and caller tag, then submits it to one idle full
core. Only `PURE`, `SNAPSHOT-READ`, and `EXCLUSIVE-BUFFER` classes are accepted.
UI state, VFS state, component instances, allocators, dictionary mutation,
authority decisions, and semantic commits remain on the owner core.

The worker XT has stack effect `( job -- result-code )`. Zero means success;
a nonzero value is published as `WJOB-S-FAILED`. Worker XTs must be total and
must not `THROW` for expected failures: exceptions are not a cross-core result
channel, and ordinary failures belong in the explicit result code. The
supervisor does use KDOS's per-core `CATCH` chain as last-resort containment;
an accidental throw becomes the failed result. Cancellation is cooperative
through `WJOB-CANCELLED?`. A deadline set with `WJOB-DEADLINE!` is checked
when the XT returns, and an XT that works in units checks `WJOB-DUE?` between
them. Neither cancellation nor a deadline forcibly interrupts worker code.

An owner that sleeps while the job runs names a full core to wake with
`WJOB-NOTIFY! ( core job -- status )` while the job is prepared. After the
worker publishes the terminal state, it sends that core an IPI, so the result
is visible before the wake-up arrives. MegaPad's `IDLE-UNTIL` on core 0 takes
the IPI as a wake-up and consumes it.

The state sequence is `IDLE -> PREPARED -> RUNNING -> terminal -> REAPED`.
Terminal states are `SUCCEEDED`, `FAILED`, and `CANCELLED`. State/result
publication is serialized after output writes. The owner must poll, wait for
the physical core to become idle, validate its own activation epoch, instance
generation, resource revision, and job generation/tag, and only then apply the
output. `WJOB-REAP` refuses to release the slot while the physical core is
still running, so buffers and descriptors cannot be reused early.

All full-core dispatch in a host must be coordinated through one dispatcher.
Legacy direct `CORE-RUN` calls do not participate in the worker slot table and
can race a submission. A Desk integration should reserve core 0 for the owner
event loop and route applet background work through this substrate; applet
callbacks themselves never run concurrently.

## Emulator boundary and follow-up

MegaPad models separate guest-core register, stack, interrupt, mailbox, and
shared-memory state, but its host execution loop does not run those cores in
parallel. Cores advance in deterministic rounds of 1,000 instructions, and
sleeping cores are skipped. A round with one awake full core runs it on the
single-core fast path, so a session whose other cores sleep runs about as fast
as one core. A round with several awake cores runs in lock-step on the same
host thread: each core runs its register-only instructions, then each executes
its next memory instruction in turn. That costs a few times more per
instruction than a lone core on code the single-core JIT handles well, and
several CPU-bound workers divide the emulator's throughput rather than gaining
host speed. None of this is a cycle-accurate model of simultaneous bus
requests or hardware races.

`akashic_tui.py` takes `--cores` and `--clusters` for smoke, serve and accept.
The Desk sandbox journeys pass with four full cores, and the sandbox runs its
jobs on the other cores there; the four-core `desktop-sandbox-modules` journey
takes about as long as the one-core run. Truly host-parallel guest-core
execution is a separate emulator project requiring an intentional shared-RAM,
MMIO-ordering, spinlock, and deterministic-testing model.
