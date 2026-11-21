# The checker core of Uroko

Status: prototype, 2026-11-21. This note describes host tooling that runs
and is measured. The checker that ships runs on the machine instead,
written in Forth in MegaPad's `uroko.f` module, checking each definition as
it closes (decided 2026-11-20); this prototype settles its rules and
measures them on Akashic. Uroko is the language of Leviathan, the machine
of MegaPad and LM1; its written forms so far are the declaration of kinds
inside stack comments and the quotation in braces (decided 2026-11-20), and
the checker's other rules are drafts that the measurements test. The
release plan's decisions 30 to 34
(fantasy-engine `dev/PLAN.md`) set out the language, and fantasy-engine
`dev/ideas/language.md` holds its open questions.

Uroko gives every word a checked stack effect and describes data by kinds:
plain data such as cells and spans, objects that a collector manages,
capabilities and tasks. Decision 32 starts the language with the checker's
core, which follows kinds through stack shuffles and the return stack and
needs nothing from LM1, and tries it on Akashic's existing Forth. This
prototype is that core. It reads Forth source the way KDOS reads it, infers
each colon definition's stack effect from its body and the effects of the
words it calls, reads the kinds the source declares, compares the inferred
effect with the definition's stack comment, and reports where kinds, spans,
execution tokens and the return stack are misused. A strict run counts the
definitions whose effect it works out from code alone, which decision 32
makes the condition for placing a word on LM1. The measurements of all of
Akashic's Forth are recorded in
[`local_testing/evidence/language-checker-20261120.md`](../../local_testing/evidence/language-checker-20261120.md)
(the first round) and
[`local_testing/evidence/language-checker-declarations-20261120.md`](../../local_testing/evidence/language-checker-declarations-20261120.md)
(declarations, typed slots and strict placement).

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
| `toolchain/language/effects.py` | Kinds, effects, and the reading of declarations in stack comments |
| `toolchain/language/vocabulary.py` | The BIOS dictionary, its documented effects, and where MegaPad's base modules are found |
| `toolchain/language/checker.py` | The dictionary, the outer interpreter, and the abstract interpretation of each definition |
| `toolchain/language/measure.py` | The measurement over Akashic's Forth, its strict run, and a sampler for reviewing a category by hand |

`local_testing/test_language_checker.py` runs small programs against the
real BIOS and KDOS vocabulary, with `uroko.f`'s declarations, in about
eight seconds. The measurement runs from the Akashic checkout, with
`MEGAPAD_ROOT` naming the MegaPad checkout when it is not beside Akashic:

```
python3 -m toolchain.language.measure --json report.json
python3 -m toolchain.language.measure --groups library --placement lm1.txt
python3 -m toolchain.language.measure --groups library --sample mismatch --count 20
python3 -m toolchain.language.measure --groups library --sample "EXECUTE of an unknown xt" --strict
```

The first two run the ordinary and the strict analysis, about 15 seconds
each for the library; `--placement` writes the definitions that qualify for
LM1, one per line, and `--no-strict` skips the strict run.

`local_testing/test_language_checker_ratchet.py` is the findings ratchet.
It runs the checker over the plain library, with `GUARDED` undefined, in
about 15 seconds, and compares its counts with the baseline in
`local_testing/language_checker_counts.json`: the findings by type, the
inferred effects that mismatch their comments, and the definitions not
inferred, in all and by cause. A count that grows fails the test as a
regression. A count that falls fails it too, until the baseline records
the gain, so the baseline changes in the same commit as the change that
moves it, and this command writes it:

```
python3 -m toolchain.language.measure --groups library --no-strict --ratchet local_testing/language_checker_counts.json
```

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
REQUIRE rule the measurement uses). Declared kinds travel the same way: a
module sees the kinds its REQUIRE closure declares.

## Declaring kinds

A kind follows its item's name after a colon, inside the ordinary stack
comment, as Factor writes stack effects:

```forth
: NIO-RECV  ( buf: span port: nio-port -- count: u status: nio-status )
```

An item without a kind is a plain cell, and the checker reads no kind from
a name: `addr` and `flag` written alone are names of plain cells. The
source stays plain Forth, since KDOS's `(` skips the whole comment.

The kinds of plain data describe cells that code manages by hand:

| Kind | Stands for |
|------|------------|
| `cell` | Any cell; the same as an item without a kind |
| `n`, `u` | A signed number, an unsigned number or count |
| `flag`, `char` | A truth value, a character |
| `addr` | An address of plain memory |
| `span` | Two cells, an address and a length, that bound one piece of memory the caller provides |
| `struct` | A record in plain memory: the address of its fields; every struct kind refines it |
| `xt`, `xt( effect )` | An execution token, with or without the effect it runs |
| `task` | Work whose result comes later |

The kinds of managed data describe objects in LM1's tagged format that a
collector manages, which release plan Part 9d and MegaPad's
`docs/managed-data.md` specify:

| Kind | Stands for |
|------|------------|
| `tagged` | Any word in LM1's format: a fixnum, nil, t, a character or a reference |
| `ref` | A reference to an object, valid only inside the window in which it was read |
| `record` | A reference to a collected record; every record kind refines it |
| `string`, `vector`, `bytes` | A reference to a string, whose bytes are UTF-8, to a vector of tagged words, or to a bytevector |
| `list`, `list( k )` | Nil, or a reference to a cons cell; the second form says that the elements are of kind k |
| `handle`, `handle( k )` | A handle, which code keeps past a window; the second form names an object of kind k |

`struct` refines `addr`. `record`, `string`, `vector` and `bytes` refine
`ref`, and `ref` and `list` refine `tagged`. A parametric kind refines the
same form of what its parameter refines, so `list( concept )` refines
`list( record )`, then `list( ref )`, which is the plain `list`;
`handle( k )` refines `handle( j )` the same way, down to the plain `handle`.
A list holds tagged words, so its elements are of a kind that rests on
`tagged`, or flags or characters; a handle names an object, so its kind is
a reference kind or a list. A handle is neither a reference nor an address,
and the checker keeps the three apart.

A source file adds kinds with a comment of its own:
`( kind: nio-port struct )` declares a struct kind,
`( kind: concept record )` a kind of collected record,
`( kind: path list( string ) )` a kind of list, and
`( kind: nio-status n )` a kind of number. A named kind mixes freely with
the kinds it refines, so a struct serves as an address and an address may
stand where a struct is expected. The checker reports one named kind
standing for another when neither refines the other, as two structs or two
kinds of status do, and reports two kinds of object that differ, such as a
string where a record is expected or a `list( topic )` where a
`list( concept )` is.

A token's effect is a nested comment, which KDOS's counting of parentheses
skips with the rest: `each: xt( item: addr -- keep: flag )`. An item
labelled `holds:` is the address of a cell that holds the kind after it.
Data words declare what they hold with that label right after their name:

| Declaration | Meaning |
|-------------|---------|
| `VARIABLE HOOK ( holds: xt( c: char -- ) )` | HOOK's cell holds a token of that effect |
| `CREATE OPS ( holds: xt( n -- n ) )` | Every cell of the table holds one; an address computed from OPS by adding a number stays in the table |
| `0 VALUE CB ( holds: xt( -- ) )` | CB pushes such a token, and `TO CB` must store one |
| `8 CONSTANT _P-SEND ( holds: xt( ... ) )` | A field offset: added to a struct's address it gives the address of a cell holding the token |
| `_STATE CMP-CELL: _ON-CLOSE ( holds: xt( ... ) )` | The child of a defining word that pushes one address, such as Akashic's CMP-FIELD: and CMP-CELL:, declares what that address holds |
| `: P.SEND ( p: port -- holds: xt( ... ) )` | A colon definition returns the address of such a cell |

Because a field offset carries its declaration, an accessor written as
`: NIO.RECV-XT ( port -- a ) _NIO-RECV-XT + ;` needs none of its own: the
checker infers that it returns the address of a cell holding the token.

A module names an effect once and then uses the name wherever a kind may
stand. The NIO port's receive and send callbacks share one:

```forth
( kind: nio-io xt( buf: span context -- count: u status: nio-status ) )
 8 CONSTANT _NIO-RECV-XT  ( holds: nio-io )
16 CONSTANT _NIO-SEND-XT  ( holds: nio-io )
```

A named effect stands for its effect, so a token of any word with that
effect may fill a slot that names it, and `( kind: nio-recv nio-io )` gives
the same effect a second name. A name keeps one effect wherever it is
declared. Since KDOS's `(` ends with its line, a slot that spells out a
long effect makes a long line, and naming the effect keeps the slot's line
short and states the shared contract in one place.

Two spellings of item names are Uroko syntax, taken from Akashic's
comments. A bar inside a name lists the values one cell may take:
`port|0: nio-port` is one cell holding a port or zero, and the checker
gives the cell the kind `nio-port`, since zero serves as a null address of
any kind. A bar standing alone, or at a token's edge as in `0 |xt 1`,
separates alternatives instead. A prime after an output span's name makes
it part of the input span of that name: `/STRING ( s: span n -- s': span )`
returns the end of the span it was given, so the checker counts the
address and the length it returns as parts of the caller's span `s`.

Malformed declarations are findings: an unknown kind, a label with no kind
after it, an `xt(`, `list(` or `handle(` without its `)`, a list of plain
data or a handle of something other than an object, a `holds:` with text
after its kind, a kind that refines an unknown kind, a name declared again
as another kind or another effect, a named effect that is not fixed, and a
declaration whose `(` finds no `)` on its line. The last matters to KDOS as
well, since an unclosed comment runs to the end of its line and hides any
code after it there.

## The base vocabulary

The BIOS dictionary comes from `bios.asm` itself: every entry's name and
IMMEDIATE flag. The effects come from the word tables of MegaPad's
`docs/BIOS-DICTIONARY.md`, in either of their forms: most tables number
their words in a first column, and the newer ones start with the word. A
BIOS word the tables omit has no effect, and a definition that calls one
fails to infer. KDOS is then read as Forth, and each of its words takes the
effect its stack comment declares.

Those tables and comments name cells informally, so MegaPad's `uroko.f`, a
system module loaded after KDOS, declares the kinds of the base words in
Uroko's form, one word to a line:

```forth
EFFECT COMPARE   ( s1: span s2: span -- n: n )
EFFECT ALLOCATE  ( u: u -- a: addr ior: n )
EFFECT HBW-BASE  ( -- a: addr )
```

On the machine, `EFFECT` parses the name and records nothing yet, and KDOS's
`(` skips the effect as a comment, so the module loads wherever KDOS runs.
The checker reads the same lines: it gives the named word the declared
effect and kinds, and reports a declaration that names no word, is
malformed, or changes the shape of the word's effect in the tables or in
KDOS's comment. Uroko's checker on the machine will give `EFFECT` a body
that records each effect for the word it names, so that one file serves
both checkers. The checker reads MegaPad's other system modules,
`networking.f`, `rich-terminal.f`, `tools.f` and `graphics.f`, after
`uroko.f`, so they compile with its declarations in place, and their words
take their comments' effects. The checker finds MegaPad through
`MEGAPAD_ROOT`, or as the checkout beside Akashic's, and stops with an
error when that checkout has no `uroko.f`.

Some words have meanings that no effect can state, and the checker gives
them exact rules: the shuffles, `PICK` and `ROLL` with a constant depth,
the return-stack words, `I` and `J`, `?DUP`, `EXECUTE`, `CATCH` and `THROW`
(which KDOS defines over `SP@` and `RP@`), `ABORT`, and the arithmetic,
comparison and memory words, whose kinds follow the cells they are given.

## Inferring an effect

A definition is analyzed when its `;` is reached, by running its body on
stacks of abstract values. Each value has a kind, an identity, and what is
known about it: a constant, whether it is zero or nonzero, the word an
execution token names or the effect a declaration gives it, what the cell
an address points at holds, and the span it belongs to. A value keeps its
identity through every shuffle and through the return stack, which is how
the checker follows kinds, spans and execution tokens, and how it records
that an output passes an input through unchanged. Inputs appear as the body
reaches below what it pushed, so the effect's inputs are as deep as the
body reads, and an input takes the kind its declaration gives it.

Control flow follows the BIOS compiler's own structure. IF, ELSE and THEN
fork and join states, and a branch tells every copy of the cell it tested,
such as the one `DUP IF` leaves, which way it went. BEGIN with WHILE,
REPEAT, UNTIL or AGAIN must leave each pass at the depth it entered with.
DO and ?DO park a two-cell frame on the return stack: I reads the innermost
index only when that frame is on top, as BIOS's `I` reads a fixed offset,
and J reads the next index only when the two frames are adjacent; LEAVE,
UNLOOP and EXIT must find the frames they remove; and a definition must end
with nothing it parked. A counted loop with constant bounds, such as
`26 0 DO DROP LOOP`, takes its body's effect that many times. CASE, OF,
ENDOF and ENDCASE follow BIOS, where ENDCASE drops the selector.

States whose depths differ are kept apart rather than reported at once,
and so are states told apart by a cell known to be zero or nonzero. `?DUP`
splits a state in two, CATCH returns its success with a zero above the
word's outputs and its exception with a nonzero code above restored cells,
and a comment such as `( -- s: span true | false )` gives its callers one
state for each alternative. A later IF routes each state to the branch its
cell selects, so `?DUP IF`, `CATCH ?DUP IF THROW THEN` and a caller's
`FETCH? IF` all infer. At the end, states of different depths form an
effect with alternatives when their top cells tell them apart; otherwise
the result depth varies and the effect is not fixed.

An execution token compiled by `[']`, made by `[:` and `;]`, or held in a
CONSTANT names its word, so EXECUTE and CATCH take that word's effect. A
token read from a typed slot, or given as an input declared `xt( ... )`,
carries its declared effect, which EXECUTE and CATCH apply. A word that
runs a token it was given without a declared effect, such as Akashic's
`WITH-GUARD`, has no fixed effect of its own; the checker runs its body
again at each call site with the caller's cells, which infers every guarded
wrapper from the word it wraps. A definition that passes a token it was
given to such a word runs it too, so `JSON-WITH-BUILDER`, which hands its
token to `WITH-GUARD`, is inlined at its callers in turn, and a word may be
inlined inside its own inlining when the tokens differ, as `WITH-GUARD`
around `WITH-GUARD` is. A token read from untyped memory names no word, and
EXECUTE of it fails.

A word that calls CREATE or another defining word makes words of its own.
Their effect is the effect of the part after DOES>, which runs with the new
word's body address on top, as in Akashic's `CMP-FIELD:`; without DOES>
they push their address. Recursion, through RECURSE or the definition's own
name, takes the effect the comment declares.

Callers see the inferred effect, with the comment's names and kinds where
the two line up; a declared kind replaces an inferred one it refines, as a
struct kind refines the address a field accessor computes. When a
definition cannot be inferred, callers use its comment, unless the
definition runs an execution token it cannot follow, since a comment such
as `( xt: xt -- )` says nothing of what that token takes.

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

Values get kinds from declarations, from the base words' declared kinds,
and from the operations that make them: a comparison gives a flag, `C@` a
character, `HERE` and `ALLOCATE` addresses, `S"` a span, and a typed slot
what it holds. A number written in the source serves as any plain kind,
since `0` is a null address as readily as a false flag, and so does a sum
of such constants. Arithmetic keeps kinds where they are clear: an address
plus an offset is an address, two addresses subtract to a number, a
constant plus a number has no kind, since the constant may be an address,
and anything with a cell of unknown kind stays unknown. A loop index takes
the kind of its start value. An input of no declared kind takes the kind
its first use requires, and an input stored into a typed slot takes the
slot's kind, so a setter learns the effect of the token it stores.

The checker reports a value whose kind cannot fill the slot it reaches.
Flags and numbers mix freely, since Forth tests any nonzero cell, and an
address may serve as a flag. The reports fall into classes: an execution
token used as data or data used as one, a flag used as an address, an
address used as a number or a number used as an address, two named kinds
that differ, two kinds of object that differ, a task mixed with other data,
a managed kind meeting plain data, and a handle mixed with anything that is
not a handle. A token stored into a typed slot, passed as a typed input,
bound to a deferred word by IS or returned as a declared token is compared
with the declared effect, by its inputs and output depths and the kinds of
its inputs, and a difference is reported.

A declared span must receive the address and the length of one span. A call
that pairs one span's address with another's length is reported, unless the
length is known to fit the first span: on the branch where a comparison
showed it, as `line-u prefix-u <` shows for the prefix on its false side,
or as the MIN of two lengths, which fits both spans. That is how a prefix
of one string is compared with another string's length. A word declared
`( s: span -- s': span )`, or one that keeps its address as
`( a u -- a u' )` does, returns a part of the span it was given.

For managed data the checker enforces what Part 9d's rules say in terms of
kinds: a reference, of `ref` or any kind that refines it, may be read
through directly (rule 1) but not written to with `!` (rule 2), and it may
not be kept in plain memory, a VALUE or the dictionary (rule 4); a `handle`
is not an address. The checks of windows and handles that
fantasy-engine `dev/ideas/language.md` lists under "The rules as the
checker enforces them" need the `OBJ-` words that open and close windows
and make and release handles, which do not exist yet.

## Strict placement

Decision 32 places a word on LM1 only when the checker works out its
effect from the code all the way down, with the base words' effects given
and no stack comment trusted. The measurement's strict run applies that
rule: a definition whose effect cannot be inferred gives its callers no
effect, recursion keeps the effect it assumed only when the body's inferred
effect confirms it, comments lend no zero or nonzero facts, and a DOES>
part that fails gives its children none.

A definition qualifies when the strict run infers it and nothing at or
below it runs a token whose effect only a declaration states: a token read
from a typed slot, a typed token input, or a deferred word, whose token IS
may change at any time. The count follows the words each analysis ran, so
storing a token, or naming a word in code no path reaches, leaves a
definition's qualification to its own code. The strict run also reports the
larger count that admits declared token effects, since the checker compares
every token it sees stored into a typed slot with the slot's declaration.

The smaller count decides placement for plain Forth (decided 2026-11-20).
A KDOS execution token is the address of MegaPad code, so a word that runs
one from a slot can only run where that code is, and plain Forth can write a
slot through an address no checker follows. Such a word qualifies once its
module is compiled as Uroko: its slots then hold words as values, which
carry each engine's compiled entry, and every store into them is compiled by
Uroko or passes through a setter that checks the stored word's effect.
Existing Forth therefore reaches LM1 module by module as it is brought into
Uroko, which for most modules means writing the declarations this note
describes.

## What the measurements found

The first round inferred 96.3 percent of Akashic's 44,468 library colon
definitions and found 46 real defects by reading samples. The second round,
with declarations, typed slots and corrected readings of the base
vocabulary, infers 43,149 of 44,470 (97.0 percent), and the strict run
infers 36,509, of which 36,218 (81.4 percent) qualify for LM1. Reading kinds
only from declarations removes the 1,370 kind and managed-data reports that
names produced; the nine findings left come from code, and the four kind
reports among them are real defects. A pilot declared the token slots of
the NIO port and the KDOS TLS port, which made all but their four
token-running helpers infer and let the checker compare all 24 callback
stores in the library with the declarations. The evidence notes list the
figures, the defects and where the checker misleads.

After the rounds that fixed those defects, and with the base words' kinds
now read from `uroko.f` and the BIOS words the dictionary lacked now
catalogued, the checker infers 43,272 of 44,471 library definitions (97.3
percent), and the strict run infers 36,908, of which 36,611 (82.3 percent)
qualify for LM1. The findings ratchet's baseline holds the counts from
which later changes are measured.

## What is not built

- Syntax beyond declarations. Words, records, quotations and tasks are
  still written as Forth.
- A compiler, placement on engines, a machine description, tasks, and any
  backend for LM1.
- Windows and handles. The checker knows the kinds of objects and handles
  and three of Part 9d's rules; the eight checks of windows and handles,
  and inserting them, need the words that open, close, make and release
  them.
- Records as objects. A record kind such as the sketch's `concept` is
  declared and checked as a kind, but `RECORD`, which would define its
  fields and the check that narrows a reference to it, waits on the object
  side of Part 9d.
- Narrowing objects. A kind still mixes with the kinds it refines in both
  directions, so a `tagged` word or a `ref` may stand where a `concept` is
  expected, as an address may stand for a struct. Rule 7 of the checks of
  windows and handles makes that narrowing pass through `OBJ>REF` or a
  kind's check.
- Kinds through loops. Each loop body runs once, plus the repeats of a
  counted loop, so a kind that changes on a later pass is not followed.
- Offsets within spans. A length shortened by arithmetic loses its span, so
  `a n + u n -` is not checked as part of the span `a u`.
- Top-level evaluation beyond constants and shuffles. An `[IF]` whose
  condition the checker cannot evaluate has both branches read (104 such
  conditions in the library).
- POSTPONE, EVALUATE, `SP@`, `RP@` and immediate words of Akashic's own.
  Akashic defines none of the last and uses POSTPONE nowhere; definitions
  that use the others are reported as not inferred.
- Akashic's Forth test drivers. They lean on words their harness profiles
  load without a REQUIRE, so most of their definitions are undefined to the
  checker.

## What the prototype says about the open questions

**How kinds are written.** Declared kinds work as decided: a declaration
sits where Forth programmers already read effects, KDOS skips it, and the
checker reports a malformed one. KDOS's `(` ends with its line, so a field
holding a token with a long effect made a long line, up to 104 characters
in the second round's pilot. Named effects remove that cost: with the
callbacks' effects named once, the pilot's two modules have no line longer
than 85 characters, and callbacks that share a contract share its name.
Field offsets are the natural place for a struct's declarations in
Akashic's Forth, since every accessor and inline use inherits them.

**Spans are two cells.** Following value identity keeps a span whole
through any shuffle, and the checker reports a call that pairs one span's
address with another's length. Sub-spans now model the prefix idiom; spans
shortened by arithmetic remain to be modeled.

**The return stack.** Tracking parked cells and loop frames together works
and finds real defects: `I` read after `>R` inside a loop, `R>` run more
often than `>R`, and LEAVE outside any DO. Code that uses the return stack
as a variable-length stack across loops, as YAML-INT does, has no fixed
effect and would have to stay plain Forth.

**What a word is as a value.** Execution tokens the checker cannot name
remain the largest cause of failure: 583 definitions execute one, 526 of
them read from untyped memory, and in the strict run 4,913 more fail
through them. Typed slots let those calls be
checked, at a cost of one declaration per slot, and every store the
checker sees is compared with the declaration. Words that pick one token
from several of different effects, such as the VFS driver table, need words
as values whose kind is a family of effects.

**Errors.** CATCH and THROW check precisely when the caught word is known,
because the exception's state differs from success by a nonzero code. A
THROW whose code is not known to be nonzero may return, so a word that
throws only on a path the checker cannot prove leaves two depths; a branch
on a copy of the code now proves it.

**Names and case.** The no-smudge rule matters to the language: a word
compiled to Forth cannot call an earlier word of its own name, and a later
word of the same name hides it everywhere after. The language's lists
holding words rather than names (decision 34) avoids the second problem for
quotations.
