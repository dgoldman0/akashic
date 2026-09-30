# akashic-numeric-team — Running numeric work on several cores

A team is the calling core, the owner, plus worker cores 1 up to
`NTEAM-CORES − 1`. Each member has its own workspace, so the numeric
kernels, which hold no module state, run on all members at once. The team
kernels are in `team-blas1.md` and `team-stencil2d.md`.

```forth
REQUIRE numeric/team.f
```

`PROVIDED akashic-numeric-team`. Requires `numeric/array.f` and
`concurrency/worker-job.f`.

---

## Same bits on any number of cores

Every team kernel fixes its order of operations without regard to which
core runs a share. A reduction is split by its blocks, and its block values
are combined in block order. An element-wise kernel is split by tiles, and a
stencil by output rows. So a result is the same bits on one, two, three, or
four cores, and the tests check exactly that.

## How a call runs

A team kernel checks the whole call first, so a refused call writes nothing.
It then gives each member a task: an execution token, the member's share,
and the output span the share writes. `NTEAM-DISPATCH` submits the workers'
tasks as worker jobs, runs the owner's task, and waits for the rest.

When a worker core cannot take its job, the owner runs that share itself
with that member's workspace. That happens when the core is busy, or when
the caller is not core 0. `NTEAM-OWNED` counts those shares, and
`NTEAM-JOBS` counts the shares worker cores ran.

Workers read the caller's input arrays, which must not change during a call.
They write only their share's output span and their own workspace. One team
serves one owner at a time.

## Words

| Word | Stack | Result |
|---|---|---|
| `NTEAM-SIZE` | `( -- 128 )` | Bytes of a team descriptor |
| `NTEAM-BYTES` | `( cores ws-bytes -- bytes\|0 )` | Team memory for `cores` members with `ws-bytes` of workspace each; 0 when `cores < 1`, `ws-bytes < 0`, or the size is too large for a cell |
| `NTEAM-INIT` | `( addr bytes cores ws-bytes team -- status )` | Carve a team from the aligned span at `addr` |
| `NTEAM-CORES` | `( team -- n )` | Members, the owner included |
| `NTEAM-WS` | `( k team -- ws )` | Member `k`'s workspace descriptor |
| `NTEAM-SPAN` | `( team -- addr bytes )` | The team memory the members use |
| `NTEAM-APART?` | `( a u team -- flag )` | Does a span stay clear of the team memory? |
| `NTEAM-SHARE` | `( total k team -- start end )` | Member `k`'s share: from `k·total/n` up to `(k+1)·total/n` |
| `NTEAM-DISPATCH` | `( team -- status )` | Run every member's task; the first nonzero task status in member order, or `NUM-OK` |
| `NTEAM-JOBS` `NTEAM-OWNED` | `( team -- n )` | Counters since `NTEAM-INIT` |

`NTEAM-INIT` refuses `cores < 1` or `cores > N-FULL-CORES` (`NUM-E-RANGE`),
an unaligned address (`NUM-E-ALIGN`), and a span that is too small or would
wrap (`NUM-E-SPACE`). For each member, the span holds a workspace
(`ws-bytes` rounded up to whole tiles), a 256-byte record with the member's
workspace descriptor and task, and a 192-byte worker-job descriptor. HBW is
the usual place for it.

A team kernel writes its tasks through `NTEAM-TASK ( k team -- task )`, the
fields `NTASK.XT`, `NTASK.OUT-A`, `NTASK.OUT-U`, and `NTASK.ARGS` (192
bytes), and the 64 bytes of planning scratch at `NTEAM-PLAN`.

## Example

```forth
CREATE team NTEAM-SIZE ALLOT
4 u NHEAT-WS-BYTES NTEAM-BYTES CONSTANT team-bytes
HBW-TALIGN team-bytes HBW-ALLOT team-bytes 4 u NHEAT-WS-BYTES team NTEAM-INIT DROP
r u bc v team NHEAT-EXPLICIT  ( status )
```
