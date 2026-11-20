# The checker core of Leviathan's language

Status: prototype, 2026-11-20. This note describes host tooling that runs
and is measured, but the language it serves has no syntax yet, and the
checker's rules are drafts that the measurement is meant to test. Nothing
here is decided. The release plan's decisions 30 to 34 (fantasy-engine
`dev/PLAN.md`) set out the language, and fantasy-engine
`dev/ideas/language.md` holds its open questions.

Leviathan's language gives every word a checked stack effect and describes
data by kinds: plain data such as cells and spans, objects that a collector
manages, capabilities and tasks. Decision 32 starts the language with the
checker's core, which follows kinds through stack shuffles and the return
stack and needs nothing from LM1, and tries it on Akashic's existing Forth
before any syntax is written. This prototype is that core. It reads Forth
source the way KDOS reads it, infers each colon definition's stack effect
from its body and the effects of the words it calls, compares the result
with the definition's stack comment, and reports where kinds, spans and the
return stack are misused. The measurement of all of Akashic's Forth is
recorded in
[`local_testing/evidence/language-checker-20261120.md`](../../local_testing/evidence/language-checker-20261120.md).

## Where it lives

The checker is a Python package, `toolchain/language`, at the root of
Akashic. Akashic's host tools have so far lived in `local_testing`, beside
the test harness that builds images, but the release plan's Part 4a moves
image building out of the harness into a supported tool, and decision 32
runs the language's compiler inside that image builder. The checker is the
first piece of that compiler, so it starts in the folder the builder's
toolchain can share rather than in the harness it will leave. Python suits
host tooling; the rule that new emulator and simulator work starts in C++
covers the machine models, not the toolchain.

| File | Holds |
|------|-------|
| `toolchain/language/source.py` | KDOS's reading rules: tokens, comments, strings, numbers |
| `toolchain/language/effects.py` | Kinds, the names stack comments use for them, and the reading of a comment as an effect |
| `toolchain/language/vocabulary.py` | The BIOS dictionary and its documented effects |
| `toolchain/language/checker.py` | The dictionary, the outer interpreter, and the abstract interpretation of each definition |
| `toolchain/language/measure.py` | The measurement over Akashic's Forth, and a sampler for reviewing a category by hand |

`local_testing/test_language_checker.py` runs small programs against the
real BIOS and KDOS vocabulary in about two seconds. The measurement runs
from the Akashic checkout, with `MEGAPAD_ROOT` naming the MegaPad checkout
when it is not beside Akashic:

```
python3 -m toolchain.language.measure --json report.json
python3 -m toolchain.language.measure --groups library --sample mismatch --count 20
```

It takes about 12 seconds for the library and the Forth test drivers.

## Reading source as KDOS does

The checker follows the rules in MegaPad's `bios.asm` rather than standard
Forth's. Tokens are separated by ASCII spaces only, so a tab belongs to its
token. Any token that begins with a backslash ends the line, so `\foo` is a
comment. `(` is a word that skips to its matching `)`, counting nested
parentheses, and stops at the end of the line when none matches, so a
parenthesized comment never spans two lines. `S"`, `."` and `ABORT"` skip
one delimiter and take text up to the next double quote or the end of the
line. A false `[IF]` is skipped by scanning raw tokens, which reads
`[THEN]` even inside a comment, as BIOS does.

Names ignore case, and a later definition hides an earlier one. Because `:`
publishes its header before the body compiles, a definition that names
itself calls itself: there is no smudge bit, and the earlier word of that
name is out of reach inside the new one. `'` is not immediate, so inside a
definition it compiles a call that parses a name when the word runs.

Each module is checked against the dictionary an image would hold when the
module loads: the base vocabulary, then the modules its REQUIRE lines load,
in KDOS's depth-first order, each once. A word that a module uses without
the REQUIRE that defines it is therefore undefined, as it is to the image
builder's own closure (`local_testing/forth_dependencies.py`, whose
REQUIRE rule the measurement uses).

## The base vocabulary

The BIOS dictionary comes from `bios.asm` itself: every entry's name and
IMMEDIATE flag. The effects come from the word tables of MegaPad's
`docs/BIOS-DICTIONARY.md`, where generic cells are written `a`, `b`, `c`
and `d`. Four standard words the tables omit, `2!`, `2@`, `ON` and `CMOVE>`,
take their ANS effects. KDOS and MegaPad's other system modules,
`networking.f`, `rich-terminal.f`, `tools.f` and `graphics.f`, are then read
as Forth, and each of their words takes the effect its stack comment
declares.

Some words have meanings that no effect can state, and the checker gives
them exact rules: the shuffles, `PICK` and `ROLL` with a constant depth,
the return-stack words, `I` and `J`, `?DUP`, `EXECUTE`, `CATCH` and `THROW`
(which KDOS defines over `SP@` and `RP@`), `ABORT`, and the arithmetic and
memory words, whose kinds follow the cells they are given.

## Inferring an effect

A definition is analyzed when its `;` is reached, by running its body on
stacks of abstract values. Each value has a kind, an identity, and what is
known about it: a constant, whether it is zero or nonzero, the word an
execution token names, and the span it belongs to. A value keeps its
identity through every shuffle and through the return stack, which is how
the checker follows kinds, spans and execution tokens, and how it records
that an output passes an input through unchanged. Inputs appear as the body
reaches below what it pushed, so the effect's inputs are as deep as the
body reads.

Control flow follows the BIOS compiler's own structure. IF, ELSE and THEN
fork and join states. BEGIN with WHILE, REPEAT, UNTIL or AGAIN must leave
each pass at the depth it entered with. DO and ?DO park a two-cell frame
on the return stack: I reads the innermost index only when that frame is
on top, as BIOS's `I` reads a fixed offset, and J reads the next index only
when the two frames are adjacent; LEAVE, UNLOOP and EXIT must find the
frames they remove; and a definition must end with nothing it parked. A
counted loop with constant bounds, such as `26 0 DO DROP LOOP`, takes its
body's effect that many times. CASE, OF, ENDOF and ENDCASE follow BIOS,
where ENDCASE drops the selector.

States whose depths differ are kept apart rather than reported at once,
and so are states told apart by a cell known to be zero or nonzero. `?DUP`
splits a state in two, CATCH returns its success with a zero above the
word's outputs and its exception with a nonzero code above restored cells,
and a comment such as `( -- addr len true | false )` gives its callers one
state for each alternative. A later IF routes each state to the branch its
cell selects, so `?DUP IF`, `CATCH ?DUP IF THROW THEN` and a caller's
`FETCH? IF` all infer. At the end, states of different depths form an
effect with alternatives when their top cells tell them apart; otherwise
the result depth varies and the effect is not fixed.

An execution token compiled by `[']`, made by `[:` and `;]`, or held in a
CONSTANT names its word, so EXECUTE and CATCH take that word's effect. A
word that runs a token it was given, such as Akashic's `WITH-GUARD`, has
no fixed effect of its own; the checker runs its body again at each call
site with the caller's cells, which infers every guarded wrapper from the
word it wraps. A token read from memory names no word, and EXECUTE of it
fails.

A word that calls CREATE or another defining word makes words of its own.
Their effect is the effect of the part after DOES>, which runs with the new
word's body address on top, as in Akashic's `CMP-FIELD:`; without DOES>
they push their address. Recursion, through RECURSE or the definition's own
name, takes the effect the comment declares.

Callers see the inferred effect, with the comment's names and kinds where
the two line up. When a definition cannot be inferred, callers use its
comment, unless the definition runs an execution token it cannot follow,
since a comment such as `( xt -- )` says nothing of what that token takes.

## Comparing with the comment

The comment is the first parenthesized group after the name, a group split
over several paren comments until one holds `--`, a comment written in
backslash lines just after the name, or a `\ NAME ( effect )` line above
the definition, as KDOS writes them. A bar standing alone, or at a token's
edge as in `0 |xt 1`, separates alternatives; a bar inside a token, as in
`dentry|0`, names the values one cell may take. Names in quotes or angle
brackets, such as `"name"`, are text the word parses. Names such as `i*x`
or `...` mark an effect that is not fixed.

An inferred effect matches when its inputs and its output depths agree with
the comment's. It matches with pass-through when the comment lists deeper
cells that the body passes through untouched, as `( a b -- a c )` describes
a body that only reads `b`. Otherwise it mismatches, and the measurement
separates comments that count cells in words, such as
`( eight-values -- )`, from the rest.

## Kinds

Kinds start from the names Akashic's comments already use. `flag`, names
ending in `?` and `true` are flags; `xt` and names ending in `-xt` are
execution tokens; `addr`, `c-addr`, `buf`, `src`, `dst` and names ending in
`-a` or `-addr` are addresses; `u`, `len`, `count`, `size` and names ending
in `-u` or `-len` are counts; `n`, `index` and `offset` are signed numbers;
`ior` and `status` are status codes; `ref` and `handle` are the two kinds
release plan Part 9d is about. A name the table does not know names no
kind. Two letters depend on their comment: `a` and `p` name an address
beside a length or as a field accessor's lone output, and a plain cell
elsewhere, as in `( a b -- a/b )`. A number written in the source serves
as any plain kind.

Arithmetic keeps kinds where they are clear: an address plus an offset is
an address, two addresses subtract to a number, and anything with a cell of
unknown kind stays unknown. A loop index takes the kind of its start value,
so a loop over addresses yields addresses.

The checker reports a value whose kind cannot fill the slot it reaches.
Flags and numbers mix freely, since Forth tests any nonzero cell, and an
address may serve as a flag. The reports fall into classes of different
strength: an execution token used as data or data used as one, a flag used
as an address, an address used as a number or a number used as an address,
and a managed kind meeting plain data. Two adjacent comment names that read
as an address and a length mark a span, and a call that takes the address
of one span with the length of another is reported; a word declared
`( a u -- a u' )` that keeps its address returns a length of the same span.

For managed data the checker enforces what Part 9d's rules say in terms of
kinds: a `ref` may be read through directly (rule 1) but not written to
with `!` (rule 2), and it may not be kept in plain memory, a VALUE or the
dictionary (rule 4); a `handle` is not an address. The rules about windows
need words that open and close them, which do not exist yet.

## What the measurement found

On 2026-11-20 the checker inferred the effect of 42,842 of Akashic's
44,468 library colon definitions, 96.3 percent, and 42,150 of those agree
with their comments. Of the 245 that disagree, 119 have comments that count
cells in words. The 1,626 it could not infer fail mostly because they
execute a token the checker cannot name, usually one read from memory
(607), because their result depth varies (237), because they use a word
their REQUIRE closure lacks (139), or because they run a token they were
given (183, which their callers inline). 33,575 definitions, three
quarters of the library, have effects that rest on inference all the way
down, with no callee that only a comment describes. Reading samples of the
mismatches and failures found 46 real defects, from return-stack misuse to
stack leaks on error paths, 40 of them outside the areas the first release
leaves out; the evidence note lists them with file and line, and records
where the checker's own rules mislead.

## What is not built

- Syntax. No new spelling exists; the checker reads Forth and its comments.
- A compiler, placement on engines, a machine description, tasks, and any
  backend for LM1.
- Windows and handles. The checker knows the kinds `ref` and `handle` and
  three of Part 9d's rules; inserting windows and handles needs the words
  that open, close, make and release them.
- Declared kinds. Kinds come from informal names, and the measurement shows
  that names do not carry them reliably: `cap` names a capability record in
  one module and a capacity in another.
- Typed slots for execution tokens. A token kept in a variable or a record
  field has no effect the checker can see, which is the largest cause of
  failure.
- Kinds through loops. Each loop body runs once, plus the repeats of a
  counted loop, so a kind that changes on a later pass is not followed.
- Records and objects named after records, such as the sketch's `concept`.
  Names the table does not know carry no kind.
- Top-level evaluation beyond constants and shuffles. An `[IF]` whose
  condition the checker cannot evaluate has both branches read (112 such
  conditions in the library).
- POSTPONE, EVALUATE, `SP@`, `RP@` and immediate words of Akashic's own.
  Akashic defines none of the last and uses POSTPONE nowhere; definitions
  that use the others are reported as not inferred.
- Akashic's Forth test drivers. They lean on words their harness profiles
  load without a REQUIRE, so most of their definitions are undefined to the
  checker.

## What the prototype says about the open questions

**How kinds are written.** Inference from comment names works for flags,
execution tokens and spans, where the strong classes of report were
usually right, but address and number names are too ambiguous to check:
each of twelve sampled reports of an address used as a number, or the
reverse, came from a name with two meanings, such as `cap` for a capability
record and for a capacity, or from a field offset computed against address
zero. Kinds the checker can enforce need declared names, with record kinds
declared beside the records whose field accessors produce them.

**Spans are two cells.** Following value identity keeps a span whole
through any shuffle, and the checker reports a call that pairs one span's
address with another's length. Code legitimately compares a prefix of one
span against another span's length, so the language needs a sub-span: a
span shortened from the front or the back stays the same span.

**The return stack.** Tracking parked cells and loop frames together works
and finds real defects: `I` read after `>R` inside a loop, `R>` run more
often than `>R`, and LEAVE outside any DO. The checker would also report
EXIT inside a loop without UNLOOP, which Akashic does not contain. Code
that uses the return stack as a variable-length stack across loops, as
YAML-INT does, has no fixed effect and would have to stay plain Forth.

**What a word is as a value.** Execution tokens read from memory are the
largest single cause of failure: 533 definitions EXECUTE one and 28 CATCH
one, from vtables, callbacks and output vectors. A token stored with a
declared effect, in a typed variable or record field, would let those
calls be checked; words that run a token they are given already infer at
each call site. The score-guided search design needs the same thing in
words as values that carry each engine's compiled entry.

**Errors.** CATCH and THROW check precisely when the caught word is known,
because the exception's state differs from success by a nonzero code. A
THROW whose code is not known to be nonzero may return, so a word that
throws only on a path the checker cannot prove leaves two depths.

**Names and case.** The no-smudge rule matters to the language: a word
compiled to Forth cannot call an earlier word of its own name, and a later
word of the same name hides it everywhere after. The language's lists
holding words rather than names (decision 34) avoids the second problem for
quotations.
