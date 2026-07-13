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
through `WJOB-CANCELLED?`; a deadline is checked when the XT returns. Neither
cancellation nor a deadline forcibly interrupts worker code.

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
