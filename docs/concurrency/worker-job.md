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

## The emulator and the simulator

MegaPad's emulator models separate guest-core register, stack, interrupt, mailbox, and
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

MegaPad's hosted simulator runs the same jobs semantically, on one to four
full cores (MegaPad's `docs/multicore-simulator-plan.md`, stages 3 and 4, and
section 5 of its simulator contract). A native scheduler runs the awake cores
in rounds: each takes a turn of up to 65,536 semantic steps, or until it
sleeps in `IDL`, finds a spinlock another core holds, or ends its work. Core 0
runs the host's dispatch and the other cores run the BIOS's worker loop, so a
job reaches its worker through the same mailbox and IPI as on the emulator,
and `WJOB-NOTIFY!`'s IPI ends the owner's `IDLE-UNTIL` on core 0. The host's
own evaluation of source is core 0's outer interpreter, which leaves the
other cores their turns between its words, so a line that starts a job and
waits for it ends. Time follows the round, so `CYCLES` values compare only
within one core. For a program whose synchronization fixes its outcome, as a
supervised job's does, the simulator gives the emulator's results; a program
that races gets one fixed outcome for each machine shape, not the emulator's
interleaving. A worker that reaches the compiler, the evaluator, dictionary
growth or terminal input takes the illegal-operation fault, -21, as KDOS's
core-0 contract requires.

`akashic_tui.py` takes `--cores` and `--clusters` for smoke, serve and accept;
the simulator takes full cores and no clusters, and
`physical_desktop_acceptance.py --cores` runs the physical Desktop journey on
them and records each core's semantic steps in the run's
`final-guest-diagnostics.json`. On the emulator the Desk sandbox journeys pass
with four full cores, and the sandbox runs its jobs on the other cores there;
the four-core `desktop-sandbox-modules` journey takes about as long as the
one-core run. Truly host-parallel guest-core execution is a separate project
for both machines; for the simulator, stage 8 of MegaPad's plan runs a
round's turns in parallel under a commit rule that keeps the sequential
order.
