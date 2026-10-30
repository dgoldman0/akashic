# Microcore kernels and where cores help Desk

Status: direction accepted on 2026-10-27; nothing is implemented. MegaPad's
`docs/microcore-kernels-plan.md` covers the hardware, the compiler and kernel
launch. This note covers where extra cores help Desk and what Akashic would
run on microcores.

## 1. Where cores help Desk

Desk's screen path stays on one core. Input, applet callbacks, drawing, both
rich-terminal producers, the publisher and MegaPad's terminal module all run
on the owner core by design ([app-shell.md](../tui/app-shell.md)). MegaPad's
`rich-terminal.f` requires a single UI/input-owner core, and terminal input
interrupts reach only core 0.

Moving applets to another core would not speed typing much, because building
the rich frame is most of a typed frame's work. In the October 13 profile it
took 89.3% of a keystroke's steps, and Desk's own painting 3.3%
([KEYSTROKE-FRAME-WORK.md](../rich-terminal/KEYSTROKE-FRAME-WORK.md)). After
part 3 of FRAMES-FOLLOW-CHANGE, a typed burst frame takes 11.36 million steps,
9.62 million of them to build the frame (branch `feature/frames-follow-change`,
`local_testing/evidence/frames-follow-change-part3-20261025.md`). A second
core could overlap at most the remaining share. A key would also appear no
sooner, because the frame is built after the applet handles the key.

The hardware limits the gain as well. The cores share one main bus and have no
data cache, and Forth stacks live in shared memory. Four cores ran the numeric
solver only 1.26 to 1.44 times faster than one, because they waited for the
bus ([scientific-computing-plan.md](../numeric/scientific-computing-plan.md)).
The way to a faster screen is cutting its work.

Extra cores suit heavy background work that never touches the screen: sandbox
jobs, which already run on spare full cores; numeric teams; and the kernels
below. Such work keeps the owner core responsive while it runs.

## 2. Kernel contract

A microcore kernel is a word written in a restricted Forth subset that
MegaPad's JIT compiles for microcores. On the Akashic side it follows the
[worker-job contract](worker-job.md). The owner prepares caller-owned input,
output and scratch buffers, and the kernel's class is `PURE`,
`SNAPSHOT-READ` or `EXCLUSIVE-BUFFER` (`akashic/runtime/concurrency-class.f`).
A kernel may not allocate, draw, touch UI, VFS or component state, use the
dictionary, perform I/O or throw. It returns a result code, and the owner
validates generation and revision before applying the output.

## 3. Candidate uses

- **Audio:** mixing, effects, synthesis and spectrum analysis for Sound Lab,
  using the cluster's FP unit and multiplier. Playback stays on core 0, which
  owns the allocator-backed staging ([output.md](../audio/output.md)).
- **Hashing:** Library's content digests, safe mode's frame seal (branch
  `feature/frames-follow-change`) and other large-block hashing, on the
  cluster's SHA-2 and CRC units.
- **Search:** scanning Library documents for a query, and ranking vectors on
  the tile engine. This work only reads, so it splits cleanly across a
  cluster's four microcores.
- **Simulation and analysis:** field updates for each tick of the proposed
  Worlds applet, and statistics, filters and FFTs for the proposed Observatory
  applet. Kernels that each write their own slice give the same result on
  every run, which Worlds' exact replay requires.
- **Plots:** sampling and binning data for the rich plot components.

A shared kernel facility moves into Akashic's substrate only after
independent consumers prove a common contract, following the ecosystem's
guardrail for shared substrate (the workspace's future-applet concepts note).
The first consumer comes first, with measurements.

## 4. Scheduling around Desk

Background kernels run while the owner core waits for input. They check a
pause flag between blocks, which the owner sets when it starts a frame. This
is a software rule; MegaPad's main arbiter keeps hard QoS as the hardware
guard.

## 5. Known issue: `par.f` and microcores

`PAR-USE-ALL` in [par.f](par.md) sends ordinary Forth execution tokens to
microcores. Today's BIOS Forth cannot run on a microcore (MegaPad's plan,
section 1), so that option would fault on the chip, and `par.f` has been
tested only on one core. Microcore work should use kernels once they exist.
