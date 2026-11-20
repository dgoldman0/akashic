# Score-guided search

Status: proposed on 2026-11-20; nothing is built. This note designs a
library through which a program explores a tree of options while a scorer
rates each candidate, and the scores decide which branch the search follows.
It is written in Leviathan's language, which the release plan's decisions 30
to 34 describe (`dev/PLAN.md` and `dev/ideas/language.md` in
fantasy-engine), so every spelling below is a guess until the language's
syntax is settled. MegaPad's `docs/chiplet-interconnect-plan.md` §7 designs
the service that runs scorers for a search on another engine, and LM1's
`spec/04-soc.md` §8 states the same service from LM1's side.

## 1. What it does

Many programs choose among options by looking ahead. A planner places one
task after another into the free time of a day, a puzzle solver tries
moves, a game player weighs replies, and a map of concepts looks for
concepts worth linking. Each step makes candidate states, a scorer rates
every candidate with a number, and the best numbers decide which states the
search expands next. The program supplies its states and how to expand
them; the library supplies the search, the batching of candidates and the
scorers.

The two halves are different kinds of work. The tree is made of objects
that appear and die as the search goes: states, nodes, the frontier and the
paths back to the root. The scoring is arithmetic: a small network rates a
candidate with a few thousand multiply-adds, and a similarity between two
vectors of 256 bytes takes 256 of them. Because the library is written in
the language, it names neither kind of engine. The language places each
word from what it needs (decision 31), and a score request is a task, the
language's unit of work that crosses engines.

## 2. Where it runs

The machine description says which engines a machine has and what each
does well, and the toolchain places the library from it:

- Expanding states, keeping the frontier and walking paths allocate and
  follow objects, so they go to the engine where objects are cheap.
- A scorer calls the tile words, so it runs where the tile engines are, as
  any word that uses a device runs where the device is.
- A search that waits for scores does so as a task waits for its result:
  the program marks the hand-off, and no call hides one.

On Leviathan the description gives the search to the engine whose hardware
allocates and collects objects and switches threads while one waits, and
the scorers to the seven tile engines, and the scores arrive in the
searching engine's memory through the tile engine's direct path. On a
machine with one engine, everything runs there, and the search returns
the same result.

Borrowing pays when a score costs more than its hand-off. A two-layer
network of 64 inputs and 32 hidden units takes about 2,100 multiply-adds a
candidate. By estimate a tile engine does them in about 300 cycles a
candidate, while a scalar core takes several thousand, and the hand-off of
about 250 clocks is shared by a batch of 64 or more. A weighted sum of a
dozen features, by contrast, costs less to compute where the candidate is
made than to send. The library's scorers are tile kernels, and a program
whose rule is that small computes it inside its own expand word.

## 3. Search forms

The first release offers three forms, all built on one batched step:
expand some states, score all their children together, and keep the best.

- **Rank.** Score a list of candidates and keep the best `k`. This is a
  search of depth one, and suggestions use it.
- **Beam.** Keep the best `w` states at each depth. Every child of the beam
  is scored in one batch, split into requests of whole groups, and the best
  `w` children form the next beam. The search ends at a goal, at a depth,
  or when its budget runs out. It holds `w` states a level plus their
  paths, which suits planners and corrections.
- **Best-first.** Keep a frontier ordered by score, or by cost so far plus
  score where the problem counts cost. Each round takes the best `b`
  states, expands them and scores their children together. With `b` of one
  this is classic best-first search; a larger `b` trades exact order for
  fewer hand-offs. It suits puzzles and exploring a graph.

Monte Carlo tree search, for games, fits the same batched step: several
threads descend the tree at once, and the leaves they reach are scored
together. No first-release use needs it, so it comes later.

Every form gives the same result on every run and on every placement. Ties
are broken by the order in which candidates were made. A batch holds the
states the search's parameters select, whatever the timing: with `p`
requests in flight, batch `n` is taken from the frontier once the scores
of batch `n − p` are in and before any later scores are used.

## 4. Problems, scorers and budgets

A program describes its problem as a record of words:

| Field | Effect | Does |
|-------|--------|------|
| `expand` | `( state -- list )` | The state's children |
| `features` | `( state row -- )` | Writes the state's features into one row of a batch |
| `index` | `( state -- n )` | The state's entry in the scorer's table, for scorers that read indices |
| `goal?` | `( state -- flag )` | Whether the state ends the search |
| `cost` | `( state child -- n )` | The cost of the step, where cost counts |
| `key` | `( state -- n )` | A key that finds repeated states |

Only `expand` and one of `features` or `index` are required. A row is plain
data: a span of whole 64-byte tiles that the search lends the word for the
call.

A scorer is a value made where its parameters are loaded. It carries the
kernel's number on the engine that runs it, the input form the kernel
reads, rows of a stated number of tiles or 8-byte indices, and the format of
its results. A budget states the nodes to expand, a deadline, the beam
width or batch size, and the requests the search keeps in flight. A search
returns its best path, or the ranked list for `rank`, with each candidate's
score and a status: done, out of budget, past its deadline, cancelled, or
failed with the scorer's status.

## 5. A batch: memory and waiting

Each kind of data lives where its user is:

| Data | Lives in | Written by | Lasts |
|------|----------|------------|-------|
| States, nodes, frontier, paths | Objects on the searching engine | The search and `expand` | Until nothing uses them |
| Feature rows or indices | Plain data the scoring engine lends the search | `features` or `index` | One request |
| Parameters, such as weights, and feature tables | Plain data on the scoring engine, in its fast memory | The code that loads the scorer | While the scorer is registered |
| Scores | Images in memory the searching engine lends | The tile engine | One request |

A batch runs in five steps:

1. The search makes the children of the states it expands.
2. It writes each child's row, or its index, into the batch's input area.
3. `score` starts the scoring task and returns at once.
4. The search builds its next batch while this one is scored, if the budget
   allows more requests in flight.
5. `scores` waits for the task and gives its scores and status.

While a task waits, its hardware thread is blocked, and the thread's share
of its core goes to the core's other threads; the runtime may run another
task meanwhile. On one engine the scorer runs inside `score`, and `scores`
returns at once.

Each result image holds one group: 64 candidates for 8-bit inputs, whose
scores are 32-bit integers, 32 for FP16 and BF16, whose scores are
binary32, and 16 for FP32, whose scores are binary64. A search compares
integer scores directly and turns binary32 scores into integer keys that
order as the floats do.

Features cost the most to move. A row of 64 bytes crosses the scoring
engine's external memory twice, once written and once read, about 350
cycles a candidate by the interconnect plan's estimate, while the scores
of 64 candidates arrive in one store of about 40 cycles. Features should
therefore be quantized to 8 bits and kept short, and a scorer whose inputs
stay fixed between requests, such as one vector for each concept of a
subject, keeps them in a table on the scoring engine and reads candidates
by index.

## 6. Scorers

The first release ships three kernels:

- **Linear.** A weighted sum of 8-bit features plus a bias. Each candidate
  is a row, and one dot product a tile gives its score; with rows of 16
  bytes, one tile operation scores four candidates.
- **Two-layer network.** 8-bit inputs and weights, 32-bit sums, a rectifier
  and a shift back to 8 bits, then a linear output. The kernel turns a
  group's rows into one tile for each feature, then accumulates each hidden
  unit with the broadcast form of the tile engine's widening
  multiply-accumulate. A network of 64 inputs and 32 hidden units takes
  2,048 such operations for 64 candidates, about 20,000 cycles by
  estimate.
- **Similarity.** The dot product of each candidate's vector with a query
  vector, the vectors held in a table on the scoring engine and the
  candidates named by index. Concept and document vectors use it.

A program can register a kernel of its own, written in the language. A
kernel reads its group's inputs and its parameters, leaves one image of
results, allocates nothing, performs no I/O and throws nothing; a failure is
a status. These are the rules of Akashic's microcore kernels
([../concurrency/microcore-kernels.md](../concurrency/microcore-kernels.md)),
so a checked kernel can later run on a cluster's microcores as well as on a
full core.

Integer kernels give exactly the same scores on every engine that runs
them. Float kernels follow the tile engine's one fixed reduction order, so
they agree too.

## 7. Weights

Weights can come from three places:

- **Hand-set over named features.** An applet ships a weight for each
  feature it names, such as how late a planned task would finish. A person
  can read why a candidate ranks high, and the applet can show it. The
  model is limited to what a weighted sum of those features can say.
- **Learned on the machine.** The tile engines can train small models.
  Logistic regression on 64 features in FP16, with binary32 sums, takes
  two tile operations an example to score it and two broadcast
  multiply-accumulates to gather its share of the gradient, so a thousand
  examples over a hundred passes take about 400,000 tile operations, some
  ten million cycles with the Forth around them. A network of up to about
  ten thousand weights trains in about three times its forward cost per
  example. The sums follow a fixed order, so training gives the same
  weights on every run. The examples are the user's own choices, such as
  accepted and rejected suggestions, and they never leave the machine.
- **Trained elsewhere and shipped.** A network trained on a PC from a
  dataset can rate raw features, such as letters or board positions, that
  no hand-set rule covers. Its training data and recipe ship with it, under
  a licence the release can carry.

Recommended: each applet ships hand-set weights over named features, and
learns from its user's choices on the machine, keeping the learned weights
per Practice and offering a reset to the shipped ones. Shipped networks
wait for a use with raw features; none of the first users has one.

A weights file names its kernel, its format version, its features, its
shapes, its shift and its bias, and its weights. The code that loads a
scorer registers it under an owner Desk already tracks, such as an applet,
and the scorer is released when its owner closes.

## 8. The words

A sketch. Kinds follow the language: `tiles` is plain data, a span of whole
64-byte tiles in a stated format; `scores` is a span of result images;
`problem`, `scorer`, `list` and `state` are objects; `task` is a task.

```forth
\ Scoring
: score   ( tiles n scorer -- task )   ... ;   \ start; returns at once
: scores  ( task -- scores status )    ... ;   \ wait, then the results

\ Searches
: rank        ( list problem scorer k -- list status )         ... ;
: beam        ( state problem scorer width -- list status )    ... ;
: best-first  ( state problem scorer budget -- list status )   ... ;

\ Scorers, made where their parameters load
: scorer-linear   ( weights -- scorer )             ... ;
: scorer-network  ( weights -- scorer )             ... ;
: scorer-similar  ( table query -- scorer )         ... ;
: scorer-load     ( file -- scorer status )         ... ;
```

A planner's use:

```forth
RECORD plan  placed left  END-RECORD   \ tasks placed, tasks still to place

: plan-children  ( plan -- list )    ... ;   \ place the next task in each gap
: plan-features  ( plan tiles -- )   ... ;   \ lateness, gaps, preferences
: plan-done?     ( plan -- flag )    plan.left NULL? ;

: day-plan  ( plan scorer -- list status )
    [ plan-children ] [ plan-features ] [ plan-done? ] problem
    SWAP  16 beam ;
```

Nothing in `day-plan` says where it runs. On Leviathan, `beam` and the
three quotations run on the engine where objects are cheap, and the kernel
behind `scorer` runs on the tile engines; on one engine, all of it runs
there.

## 9. What the language needs

Beyond the first version of decision 32, which compiles every word to
Forth for MegaPad, the library needs:

- **Placement from a machine description**, for two engines or one, with
  tasks as the only points where work crosses between engines.
- **Tasks across engines**: starting a task on the other engine, waiting
  for it, cancelling it, and a status alongside each result, since an error
  never crosses as a throw.
- **A backend for the searching engine.** The proposal is that the
  compiler emit each engine's own system language: Forth that KDOS loads,
  as decision 32 has it, and Lisp that the Lisp engine's runtime compiles.
  Stack code becomes expressions from the checked stack effects, and a
  word whose effect the checker cannot fix stays on the engine whose
  backend is Forth.
- **Kinds for tile arrays**: spans of whole tiles in a stated format, the
  operations the kernels use, compiled to the tile words, and the
  accumulator's claim and release checked as a pair.
- **Words as values** that carry each engine's compiled entry, so a
  quotation written in the program reaches either engine. Quotations built
  while a program runs are not needed.
- **Objects on one engine.** The search's states and tree are objects. On a
  machine whose one engine has no collector, the tasks that make them need
  one. The smallest that serves a search is a heap that lives as long as
  its task, with the task's result copied out at the end and a check that
  nothing else escapes.

The release plan sizes these and decides how far the first release takes
them.

## 10. First users

- **Study's link suggestions** (recommended for the first release). The
  Study Practice keeps a growing map of its subject's concepts as managed
  data. The map suggests links: candidates are concepts within two links of
  the selected one and concepts that appear beside it in the bound
  documents, and best-first search over the map follows the most similar.
  The similarity kernel rates each candidate's vector, built once from the
  documents, against the selected concept's, and the search adds what the
  map itself knows, shared neighbours and distance, with hand-set weights.
  The user accepts or rejects each suggestion, and those choices train the
  weights. The map has no document of its own yet, so its suggestions are
  described here until it does.
- **Daybook's day planner** (recommended second). Given open tasks with
  durations and due times, beam search places them into the day's free time
  and proposes a plan, scored by lateness, preferred times, gaps left and
  changes of subject, with weights the user can see and adjust. Daybook
  lists bounded planner search among its next steps
  ([../tui/applets/daybook/daybook.md](../tui/applets/daybook/daybook.md)).
- **The Workshop's puzzle solver.** A sliding-tile puzzle solved by
  best-first search with a learned estimate of the distance to the goal,
  among the Workshop's examples. It shows both engines at work in one
  program, and it is the library's own end-to-end test.

Later candidates, with what holds each back:

- **Pad's spelling corrections.** Beam search through a word list, scored
  by a small network over letters. It needs a freely licensed word list and
  the editor's interface for offering corrections.
- **Library's ranked search.** The similarity kernel over document vectors.
  It ranks without searching a tree, and Library's search is exact today.
- **Streams' ranking of feed items** by what the user reads, learned on the
  machine. It ranks rather than searches, and it needs a policy for what
  may be learned from reading.
- **Grid's goal seek.** Finding the input that makes a formula reach a
  target is a search along one number, scored by evaluating formulas, not
  by tile work.
- **The Agent's next steps.** The Agent's provider chooses its steps, and
  every consequential step already waits for the user's approval.

Akashic's grid A* (`akashic/game/2d/pathfind.f`) serves Worlds, which the
first release leaves out, and stays as it is.

## 11. Testing

- Each kernel against a reference computed on the host, bit for bit.
- Each search form on one engine and on two, with the same result required.
- Repeated runs, with the same result required whatever the timing of the
  scores.
- Refusals, cancellation and a failed delivery of scores, each ending the
  search with its best so far and the matching status.
- Desk's frame, built on time while a long batch is scored.
- The first users' journeys, with Desk and the applet.

## 12. Open questions

- **Objects on one engine**: the task-lifetime heap of §9, a general
  collector, or a search kept in plain data.
- **Features read from the searching engine's memory.** Today the features
  cross the scoring engine's external memory twice. Tile operands read
  across the link would remove that traffic but are not built; the release
  plan's sizing study (D8) counts it.
- **Batch and pipeline defaults**, to be measured with the first users.
- **More engines for one search.** One worker core's tile engine serves at
  first; using several waits on the dispatcher, and the cluster engines on
  microcore kernels.
- **Monte Carlo tree search**, when a game or a planner under uncertainty
  needs it.
