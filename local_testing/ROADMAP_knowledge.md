# Knowledge Infrastructure — Roadmap

Libraries for curation, classification, annotation, retrieval, and
knowledge management on KDOS / Megapad-64.  Built on existing Akashic
infrastructure — arenas, strings, JSON, CBOR, datetime, state-tree,
DOM, math, crypto hashing.

The thesis: the world has products for knowledge management (Zotero,
Elasticsearch, Hypothes.is, PoolParty) but essentially zero compact,
embeddable *libraries* that expose the underlying primitives.  Some of
these are well-served in the Python ecosystem and we're building Forth
equivalents.  Others — marked ★ — are **genuinely novel**: no usable
library exists in *any* language.

**Date:** 2026-03-09
**Status:** Living document

---

## Table of Contents

- [Novelty Assessment](#novelty-assessment)
- [Architecture Overview](#architecture-overview)
- [Dependency Graph](#dependency-graph)
- [Phase 1 — Taxonomy Engine](#phase-1--taxonomy-engine)
- [Phase 2 — Inverted Index & Search](#phase-2--inverted-index--search)
- [Phase 3 — Content-Addressed Storage](#phase-3--content-addressed-storage)
- [Phase 4 — Annotation Engine ★](#phase-4--annotation-engine-)
- [Phase 5 — Temporal Interval Reasoning ★](#phase-5--temporal-interval-reasoning-)
- [Phase 6 — Branching Undo/Redo ★](#phase-6--branching-undoredo-)
- [Phase 7 — Attention Decay & Priority ★](#phase-7--attention-decay--priority-)
- [Phase 8 — Argument Structure ★](#phase-8--argument-structure-)
- [Phase 9 — Three-Way Structured Merge ★](#phase-9--three-way-structured-merge-)
- [Phase 10 — Consent & Delegation Chains ★](#phase-10--consent--delegation-chains-)
- [Phase 11 — Citation Graph](#phase-11--citation-graph)
- [Phase 12 — Concordance & Index Generator](#phase-12--concordance--index-generator)
- [Phase 13 — Provenance Tracker](#phase-13--provenance-tracker)
- [Phase 14 — Similarity & Deduplication](#phase-14--similarity--deduplication)
- [Phase 15 — Feed Curation & Digest ★](#phase-15--feed-curation--digest-)
- [Phase 16 — Progressive Disclosure ★](#phase-16--progressive-disclosure-)
- [Phase 17 — Conversation Structure ★](#phase-17--conversation-structure-)
- [Phase 18 — Reading Path Optimizer ★](#phase-18--reading-path-optimizer-)
- [Implementation Order](#implementation-order)
- [Design Constraints](#design-constraints)
- [Testing Strategy](#testing-strategy)

---

## Novelty Assessment

| Phase | Module | Python equivalent | Any-language lib? | Novel? |
|-------|--------|-------------------|-------------------|--------|
| 1 | Taxonomy | `rdflib` + SKOS (partial) | RDF engines, not taxonomy-specific | No |
| 2 | Search/IR | `tantivy-py`, dead `Whoosh` | Lucene, tantivy (Rust) | No |
| 3 | CAS | `hashfs` (minimal) | No standalone Merkle DAG engine | Partial |
| 4 | Annotation | — | W3C spec, no embeddable engine | **★ Yes** |
| 5 | Temporal intervals | — | Papers only | **★ Yes** |
| 6 | Branching undo | — | Emacs internals, not extractable | **★ Yes** |
| 7 | Attention decay | — | — | **★ Yes** |
| 8 | Argument structure | — | Papers only | **★ Yes** |
| 9 | 3-way structured merge | — | CRDTs are heavier, different model | **★ Yes** |
| 10 | Consent chains | — | Policy servers, no library | **★ Yes** |
| 11 | Citation graph | `citeproc-py`, `pybtex` | Exist | No |
| 12 | Concordance | NLTK `concordance()` (basic) | Basic, not pub-grade | Partial |
| 13 | Provenance | `prov` (W3C PROV-DM) | Exists | No |
| 14 | Similarity | `datasketch`, `dedupe` | Well-served | No |
| 15 | Feed curation | `feedparser` (parsing only) | Parsing, not curation logic | **★ Yes** |
| 16 | Progressive disclosure | — | — | **★ Yes** |
| 17 | Conversation structure | — | — | **★ Yes** |
| 18 | Reading path optimizer | — | — | **★ Yes** |

11 of 18 are genuinely novel (★).

---

## Architecture Overview

New modules live under `akashic/knowledge/` (or individual top-level
dirs for the larger ones).  They form three tiers:

```
Tier 3 — Applications
┌──────────────────────────────────────────────────────────┐
│  feed-curation   reading-path   conversation-structure   │
│  progressive-disclosure                                  │
└──────────────────────┬───────────────────────────────────┘
                       │ uses
Tier 2 — Engines
┌──────────────────────┴───────────────────────────────────┐
│  taxonomy   search   annotation   citation   concordance │
│  provenance   similarity   consent-chains                │
└──────────────────────┬───────────────────────────────────┘
                       │ uses
Tier 1 — Primitives
┌──────────────────────┴───────────────────────────────────┐
│  cas (content-addressed storage)   temporal-intervals    │
│  branching-undo   attention-decay   argument-structure   │
│  3way-merge                                              │
└──────────────────────┬───────────────────────────────────┘
                       │ uses
Existing Akashic
┌──────────────────────┴───────────────────────────────────┐
│  math/  utils/  cbor/  dom/  markup/  concurrency/       │
│  (string, json, toml, datetime, sha256, arena, fp16/32)  │
└──────────────────────────────────────────────────────────┘
```

**Hard rule:** Tier 1 modules depend only on existing Akashic.
Tier 2 modules may depend on Tier 1 + Akashic.  Tier 3 modules
may depend on Tier 2 + Tier 1 + Akashic.  No circular references.
No tier reaches down into another tier's internals.

---

## Dependency Graph

```
reading-path ─── taxonomy ─── cas
      │               │
      ├── attention-decay
      │
feed-curation ─── similarity ─── search
      │                │
      ├── attention-decay
      │
progressive-disclosure ─── annotation
      │
conversation-structure ─── temporal-intervals
      │                        │
      ├── argument-structure   │
                               │
provenance ─── temporal-intervals ─── datetime
      │
consent-chains ─── temporal-intervals
      │
citation ─── search
      │
concordance ─── search
      │
annotation ─── cas
      │
3way-merge ─── (json, state-tree)
      │
branching-undo ─── (arena)
      │
similarity ─── math/sha256, math/stats
      │
search ─── utils/string
      │
cas ─── math/sha256, cbor/dag-cbor
      │
taxonomy ─── utils/string
      │
attention-decay ─── math/fp16, utils/datetime
      │
temporal-intervals ─── utils/datetime
      │
argument-structure ─── (arena)
```

---

## Phase 1 — Taxonomy Engine

**Module:** `akashic/knowledge/taxonomy.f`
**Estimated size:** ~600–800 lines
**Novelty:** Equivalent to parts of `rdflib` + SKOS, but as a
standalone engine rather than an RDF framework.
**Depends on:** `utils/string.f`, arena allocator

A hierarchical classification system with broader/narrower term
relationships, synonym rings, and faceted navigation.

### Data Model

Each concept is a fixed-size descriptor in an arena:

| Offset | Size | Field |
|--------|------|-------|
| +0 | 8 | id (auto-incrementing) |
| +8 | 8 | parent-ptr (broader concept, 0 = top) |
| +16 | 8 | first-child-ptr (narrower concepts) |
| +24 | 8 | next-sibling-ptr |
| +32 | 8 | synonym-ring-ptr (circular list) |
| +40 | 8 | label-addr |
| +48 | 8 | label-len |
| +56 | 8 | facet-bits (up to 64 facet flags) |
| +64 | 8 | user-data |

### API

```
\ Lifecycle
TAX-CREATE          ( -- tax )              Create empty taxonomy
TAX-DESTROY         ( tax -- )              Free arena

\ Concept management
TAX-ADD             ( label len tax -- cid )    Add top-level concept
TAX-ADD-UNDER       ( label len parent tax -- cid ) Add narrower concept
TAX-REMOVE          ( cid tax -- )              Remove concept + subtree
TAX-MOVE            ( cid new-parent tax -- )   Reparent concept
TAX-RENAME          ( label len cid tax -- )    Change label

\ Synonym rings
TAX-ADD-SYNONYM     ( cid1 cid2 tax -- )    Link as synonyms
TAX-SYNONYMS        ( cid tax -- addr n )   List synonym ring

\ Traversal
TAX-PARENT          ( cid tax -- pid|0 )    Broader concept
TAX-CHILDREN        ( cid tax -- addr n )   Narrower concepts
TAX-ANCESTORS       ( cid tax -- addr n )   Path to root
TAX-DESCENDANTS     ( cid tax -- addr n )   Subtree (DFS)
TAX-DEPTH           ( cid tax -- n )        Levels from root

\ Faceted classification
TAX-SET-FACET       ( bit cid tax -- )      Set facet flag
TAX-CLEAR-FACET     ( bit cid tax -- )      Clear facet flag
TAX-FILTER-FACET    ( bits tax -- addr n )  All concepts matching facet mask

\ Search
TAX-FIND            ( label len tax -- cid|0 )      Exact label match
TAX-FIND-PREFIX     ( prefix len tax -- addr n )    Prefix search
TAX-FIND-SYNONYM    ( label len tax -- cid|0 )      Match including synonyms

\ Classification
TAX-CLASSIFY        ( item-id cid tax -- )          Assign item to concept
TAX-UNCLASSIFY      ( item-id cid tax -- )          Remove assignment
TAX-ITEMS           ( cid tax -- addr n )           Items under concept
TAX-ITEMS-DEEP      ( cid tax -- addr n )           Items under concept + descendants
TAX-CATEGORIES      ( item-id tax -- addr n )       Concepts an item belongs to
```

### Internals

- Arena-backed — bulk destroy, no per-node free
- Synonym rings are circular singly-linked lists (O(n) traverse,
  O(1) link/unlink)
- Facets as bit fields — 64 facets max, filter via AND mask against
  all concepts
- Item-to-concept mapping stored in a parallel hash table
  (FNV-1a, 256-slot)
- Polyhierarchy support: a concept can have multiple parents via
  explicit `TAX-ALIAS` links (secondary parent pointers stored in
  overflow list)

---

## Phase 2 — Inverted Index & Search

**Module:** `akashic/knowledge/search.f`
**Estimated size:** ~800–1,000 lines
**Novelty:** Tantivy (Rust) and Lucene (Java) exist; no Forth
or truly compact C equivalent for constrained environments.
**Depends on:** `utils/string.f`, `math/stats.f`, arena allocator

Self-contained inverted index with BM25 ranking, boolean queries,
phrase matching, and faceted drill-down.

### Data Model

**Inverted index** — hash table of term → posting list:

```
Term table: 1024-slot FNV-1a hash
  → each slot: ( term-addr term-len first-posting-ptr df )

Posting list: linked list of ( doc-id tf next-ptr )

Document table: 256-slot array
  → each slot: ( doc-id field-count total-terms user-ptr )
```

### API

```
\ Lifecycle
IX-CREATE           ( -- ix )               Create empty index
IX-DESTROY          ( ix -- )               Free arena

\ Indexing
IX-ADD-DOC          ( doc-id text len ix -- )    Tokenize & index document
IX-REMOVE-DOC       ( doc-id ix -- )             Remove from index
IX-DOC-COUNT        ( ix -- n )                  Number of indexed docs

\ Tokenization (configurable)
IX-SET-TOKENIZER    ( xt ix -- )            Custom tokenizer XT
IX-SET-STOPWORDS    ( addr n ix -- )        Stop word list

\ Query
IX-SEARCH           ( query len ix -- results n )   BM25-ranked search
IX-SEARCH-BOOL      ( query len ix -- results n )   Boolean query (AND/OR/NOT)
IX-SEARCH-PHRASE    ( phrase len ix -- results n )   Exact phrase match
IX-SEARCH-PREFIX    ( prefix len ix -- results n )   Prefix expansion

\ Results  ( each result is: doc-id score )
IX-RESULT-DOC       ( result -- doc-id )
IX-RESULT-SCORE     ( result -- score-fp16 )

\ Faceted search (integrates with taxonomy)
IX-ADD-FACET        ( doc-id facet-id ix -- )   Tag document with facet
IX-FILTER-FACET     ( facet-id results n ix -- filtered m )

\ Statistics
IX-TERM-DF          ( term len ix -- n )    Document frequency
IX-TERM-IDF         ( term len ix -- idf )  Inverse doc frequency (FP16)
IX-DOC-LEN          ( doc-id ix -- n )      Document length in terms
IX-AVG-LEN          ( ix -- avg )           Average document length (FP16)
```

### Internals

- BM25 scoring: `score = IDF × (tf × (k1+1)) / (tf + k1 × (1 - b + b × dl/avgdl))`
  with k1=1.2, b=0.75 (configurable)
- Tokenizer: whitespace split + lowercase + strip punctuation (default);
  pluggable via XT for language-specific stemmers
- Stop words: optional hash-set filter applied during indexing
- Phrase query: positional index stored as delta-encoded list per posting
- Boolean parsing: recursive descent, `AND`/`OR`/`NOT`/`(`, `)`
- Results returned as arena-allocated array, sorted by score descending

---

## Phase 3 — Content-Addressed Storage

**Module:** `akashic/knowledge/cas.f`
**Estimated size:** ~500–700 lines
**Novelty:** `hashfs` (Python) is trivial; IPFS bundles too much.
A standalone Merkle DAG engine without networking opinions.
**Depends on:** `math/sha256.f`, `cbor/dag-cbor.f`, arena allocator

Content-addressed block storage with Merkle DAG linking,
deduplication, integrity verification, and garbage collection.

### Data Model

Each block is identified by its SHA-256 hash (32 bytes).  Blocks
contain arbitrary bytes.  Links between blocks form a DAG encoded
via DAG-CBOR CID references.

```
Block table: 512-slot hash table (keyed by first 8 bytes of SHA-256)
  → each slot: ( hash[32] data-addr data-len ref-count pin-flag )

Root set: linked list of pinned block hashes
```

### API

```
\ Lifecycle
CAS-CREATE          ( -- cas )                  Create empty store
CAS-DESTROY         ( cas -- )                  Free all storage

\ Storage
CAS-PUT             ( data len cas -- hash )    Store block, return SHA-256 hash
CAS-GET             ( hash cas -- data len | 0 )  Retrieve by hash
CAS-HAS?            ( hash cas -- flag )        Existence check
CAS-DELETE          ( hash cas -- )             Remove (respects pin/refcount)
CAS-SIZE            ( cas -- n )                Total blocks stored

\ Merkle DAG
CAS-LINK            ( parent-hash child-hash cas -- )   Record DAG edge
CAS-CHILDREN        ( hash cas -- addr n )              Child hashes
CAS-PARENTS         ( hash cas -- addr n )              Parent hashes

\ Integrity
CAS-VERIFY          ( hash cas -- flag )        Recompute hash, compare
CAS-VERIFY-ALL      ( cas -- fail-count )       Verify entire store
CAS-VERIFY-DAG      ( root-hash cas -- flag )   Verify DAG from root down

\ Pinning & GC
CAS-PIN             ( hash cas -- )             Mark as root (prevent GC)
CAS-UNPIN           ( hash cas -- )             Remove root mark
CAS-GC              ( cas -- freed )            Collect unreachable blocks

\ Deduplication (automatic — CAS-PUT deduplicates by hash)
CAS-DEDUP-STATS     ( cas -- total deduped )    Count of dedup hits

\ Serialization
CAS-EXPORT          ( cas -- addr len )         Serialize store to bytes
CAS-IMPORT          ( addr len cas -- )         Load serialized store
```

### Internals

- SHA-256 for content hashing (32-byte keys)
- Hash table with open addressing (linear probing)
- Reference counting for shared blocks in DAG
- GC: mark-sweep from pinned roots through DAG links
- DAG link storage: per-block linked list of child hashes
- Export format: concatenated `( hash[32] len[4] data[len] )` blocks
  with DAG-CBOR link table appended

---

## Phase 4 — Annotation Engine ★

**Module:** `akashic/knowledge/annotation.f`
**Estimated size:** ~600–800 lines
**Novelty:** **Genuine gap.** W3C Web Annotation spec exists;
no embeddable implementation in any language.
**Depends on:** `utils/string.f`, `utils/datetime.f`, arena allocator

Structured annotations anchored to arbitrary content — text spans,
spatial regions, temporal ranges — with anchor repair, layers, and
serialization.

### Data Model

```
Annotation descriptor — 96 bytes:
  +0   id              8   Auto-incrementing
  +8   anchor-type     8   0=text-span, 1=spatial-rect, 2=temporal-range
  +16  anchor-start    8   Byte offset / x / start-ms
  +24  anchor-end      8   Byte offset / y / end-ms
  +32  anchor-extent-a 8   (unused for text) / width / (unused)
  +40  anchor-extent-b 8   (unused for text) / height / (unused)
  +48  body-addr       8   Annotation body text pointer
  +56  body-len        8   Body text length
  +64  layer-id        8   Layer/namespace ID
  +72  created         8   Timestamp (KDOS epoch)
  +80  modified        8   Timestamp
  +88  user-data       8   Application-specific pointer
```

### API

```
\ Lifecycle
ANN-CREATE          ( -- ann-store )            Create annotation store
ANN-DESTROY         ( ann-store -- )            Free all

\ Anchoring
ANN-TEXT-SPAN       ( start end body len store -- aid )      Anchor to byte range
ANN-SPATIAL-RECT    ( x y w h body len store -- aid )        Anchor to 2D region
ANN-TEMPORAL-RANGE  ( t0 t1 body len store -- aid )          Anchor to time span
ANN-REMOVE          ( aid store -- )
ANN-UPDATE-BODY     ( body len aid store -- )

\ Querying
ANN-AT-OFFSET       ( offset store -- addr n )      Annotations covering offset
ANN-AT-POINT        ( x y store -- addr n )         Annotations covering point
ANN-AT-TIME         ( t store -- addr n )           Annotations covering time
ANN-IN-RANGE        ( start end store -- addr n )   Annotations overlapping range
ANN-BY-LAYER        ( layer-id store -- addr n )    All in layer
ANN-ALL             ( store -- addr n )             All annotations
ANN-COUNT           ( store -- n )

\ Layers
ANN-LAYER-CREATE    ( name len store -- lid )       Create named layer
ANN-LAYER-VISIBLE   ( lid store -- flag )           Layer visibility
ANN-LAYER-SHOW      ( lid store -- )                Make visible
ANN-LAYER-HIDE      ( lid store -- )                Make invisible
ANN-LAYER-MERGE     ( src-lid dst-lid store -- )    Merge layers

\ Anchor repair (when underlying content shifts)
ANN-TEXT-SHIFT      ( offset delta store -- )    Shift all text anchors after offset
ANN-TEXT-REPAIR     ( old-text old-len new-text new-len store -- )
                    \ Heuristic reanchor after content edit (LCS-based)

\ Serialization (W3C Web Annotation compatible JSON-LD)
ANN-EXPORT-JSON     ( store -- addr len )
ANN-IMPORT-JSON     ( addr len store -- )
```

### Internals

- Arena-backed descriptors, interval tree for O(log n) overlap queries
- Anchor repair: longest common subsequence (LCS) to map old offsets
  to new offsets after text edits
- Layer system: each annotation carries a layer ID; layers are a
  flat table of `( lid name-addr name-len visible-flag )`
- Spatial queries: brute-force scan (sufficient for <10K annotations);
  R-tree upgrade if needed later
- Export format follows W3C Web Annotation Data Model (JSON-LD
  structure, not full RDF)

---

## Phase 5 — Temporal Interval Reasoning ★

**Module:** `akashic/knowledge/temporal.f`
**Estimated size:** ~400–600 lines
**Novelty:** **Genuine gap.** Allen's interval algebra is from 1983.
Academic implementations in papers only. Zero usable libraries in
any language.
**Depends on:** `utils/datetime.f`

James F. Allen's 13 interval relations with constraint propagation.

### The 13 Relations

```
  X before Y        |  XXXX          YYYY    |
  X meets Y         |  XXXX YYYY              |
  X overlaps Y      |  XXXX                   |
                     |     YYYY                |
  X starts Y        |  XXXX                   |
                     |  YYYYYYYY               |
  X during Y        |     XXXX                |
                     |  YYYYYYYY               |
  X finishes Y      |       XXXX              |
                     |  YYYYYYYY               |
  X equals Y        |  XXXX                   |
                     |  YYYY                   |
  + 6 inverses (after, met-by, overlapped-by, started-by, contains, finished-by)
```

### API

```
\ Intervals
TI-CREATE           ( start end -- interval )       Create interval
TI-START            ( interval -- start )
TI-END              ( interval -- end )

\ Relation testing (all return relation code 0–12)
TI-RELATE           ( a b -- relation )             Which of 13 relations?
TI-BEFORE?          ( a b -- flag )
TI-MEETS?           ( a b -- flag )
TI-OVERLAPS?        ( a b -- flag )
TI-STARTS?          ( a b -- flag )
TI-DURING?          ( a b -- flag )
TI-FINISHES?        ( a b -- flag )
TI-EQUALS?          ( a b -- flag )
TI-AFTER?           ( a b -- flag )
TI-CONTAINS?        ( a b -- flag )
\ ... (all 13)

\ Relation names
TI-RELATION-NAME    ( code -- addr len )   "before", "meets", etc.

\ Constraint network
TI-NET-CREATE       ( max-intervals -- net )
TI-NET-DESTROY      ( net -- )
TI-NET-ADD          ( interval net -- idx )
TI-NET-CONSTRAIN    ( idx1 rel-set idx2 net -- )    Constrain relation between pair
                    \ rel-set is a 13-bit mask of allowed relations
TI-NET-PROPAGATE    ( net -- consistent? )          Allen's path consistency
TI-NET-RELATION     ( idx1 idx2 net -- rel-set )    Current possible relations

\ Queries
TI-NET-BEFORE-ALL   ( idx net -- addr n )   All intervals constrained to be before idx
TI-NET-CONCURRENT   ( idx net -- addr n )   All that overlap/contain/etc.
TI-NET-SEQUENCE     ( net -- addr n )       Topological order (if fully constrained)

\ Calendar integration
TI-FROM-DATETIME    ( dt1 dt2 -- interval )         From datetime pair
TI-DURATION         ( interval -- seconds )         Duration in seconds
TI-GAP              ( a b -- seconds | -1 )         Gap between intervals (-1 if overlap)
```

### Internals

- Constraint network: N×N matrix of 13-bit relation sets
  (fits in 16-bit cells; N×N×2 bytes)
- Path consistency: Allen's algorithm — for each triple (i,j,k),
  intersect R(i,k) with composition of R(i,j) and R(j,k) using
  the 13×13 composition table
- Composition table: 169-entry lookup (`RELATION-COMPOSE[]`),
  each entry is a 13-bit set
- `TI-NET-PROPAGATE` runs path consistency to fixpoint
- Max ~64 intervals (64×64×2 = 8 KiB matrix), sufficient for
  scheduling / event reasoning

---

## Phase 6 — Branching Undo/Redo ★

**Module:** `akashic/knowledge/undo.f`
**Estimated size:** ~400–500 lines
**Novelty:** **Genuine gap.** Emacs has this internally.
No extractable, embeddable library anywhere.
**Depends on:** arena allocator

A tree-structured command history where branching at any point
preserves all alternate timelines.

### Data Model

```
History node — 48 bytes:
  +0   parent-ptr     8    Previous state (0 = root)
  +8   first-child    8    First branch from this point
  +16  next-sibling   8    Next branch at same parent
  +24  command-xt     8    Forward (do) execution token
  +32  undo-xt        8    Reverse (undo) execution token
  +40  data-ptr       8    Command-specific payload

History tree:
  +0   root-ptr       8
  +8   current-ptr    8    Where we are now
  +16  node-count     8
  +24  max-nodes      8    GC threshold
  +32  arena          8    Arena for nodes
```

### API

```
\ Lifecycle
UNDO-CREATE         ( max-nodes -- hist )       Create history tree
UNDO-DESTROY        ( hist -- )                 Free arena

\ Commands
UNDO-EXEC           ( do-xt undo-xt data hist -- )  Execute command, record new node
UNDO-UNDO           ( hist -- flag )            Undo: move to parent, exec undo-xt
UNDO-REDO           ( hist -- flag )            Redo: move to first child, exec do-xt
UNDO-REDO-BRANCH    ( n hist -- flag )          Redo: move to nth branch

\ Navigation
UNDO-CAN-UNDO?     ( hist -- flag )
UNDO-CAN-REDO?     ( hist -- flag )
UNDO-BRANCHES      ( hist -- n )               Number of branches at current node
UNDO-DEPTH          ( hist -- n )               Distance from root

\ Tree traversal
UNDO-PATH-TO-ROOT   ( hist -- addr n )         Node chain to root
UNDO-EACH-BRANCH    ( xt hist -- )             Iterate branches at current node
UNDO-WALK           ( xt hist -- )             DFS walk of entire tree

\ GC
UNDO-PRUNE          ( keep-depth hist -- freed )  Remove branches older than depth
UNDO-COMPACT        ( hist -- freed )             Remove unreachable branches

\ Serialization
UNDO-SNAPSHOT       ( hist -- addr len )          Serialize tree structure
UNDO-RESTORE        ( addr len hist -- )          Restore from snapshot
```

### Internals

- Arena-allocated node tree (child-sibling representation)
- `UNDO-EXEC` creates a new child of `current-ptr`, executes the
  do-xt, advances current
- `UNDO-UNDO` executes the undo-xt of `current-ptr`, retreats to parent
- `UNDO-REDO` follows first-child (default) or nth branch
- GC: mark all nodes reachable from current path to root + all
  branches; sweep unmarked; or prune by depth threshold
- Command data is caller-managed — the undo tree stores pointers,
  not copies (caller is responsible for data lifetime)

---

## Phase 7 — Attention Decay & Priority ★

**Module:** `akashic/knowledge/attention.f`
**Estimated size:** ~300–400 lines
**Novelty:** **Genuine gap.** Every feed algorithm, todo app, and
notification system reinvents this.  No library anywhere.
**Depends on:** `math/fp16.f`, `math/fp16-ext.f`, `math/trig.f`,
`utils/datetime.f`

Temporal relevance curves with a unified `score_at(time)` interface.

### Curve Types

```
Constant:     relevance = k                         (reference docs)
Exponential:  relevance = k × e^(-λt)               (news, messages)
Deadline:     relevance = k × (1/(deadline-t))       (tasks, deadlines)
Step:         relevance = k if t < deadline, 0 else  (expiring items)
Periodic:     relevance = k × (1 + sin(2πt/period)) (seasonal, weekly)
Gaussian:     relevance = k × e^(-(t-μ)²/2σ²)       (event-centered)
```

### API

```
\ Lifecycle
ATT-CREATE          ( type params... -- curve )  Create decay curve
ATT-DESTROY         ( curve -- )

\ Curve constructors
ATT-CONSTANT        ( k -- curve )               Flat relevance
ATT-DECAY           ( k half-life -- curve )      Exponential decay
ATT-DEADLINE        ( k deadline -- curve )        Urgency ramp
ATT-STEP            ( k deadline -- curve )        Binary cutoff
ATT-PERIODIC        ( k period phase -- curve )    Sinusoidal cycle
ATT-GAUSSIAN        ( k center sigma -- curve )    Bell curve

\ Scoring
ATT-SCORE           ( time curve -- score-fp16 )   Relevance at time
ATT-SCORE-NOW       ( curve -- score-fp16 )        Relevance at current time

\ Composition
ATT-ADD             ( curve1 curve2 -- combined )  Sum of curves
ATT-MUL             ( curve1 curve2 -- combined )  Product of curves
ATT-MAX             ( curve1 curve2 -- combined )  Point-wise max

\ Batch operations (for sorting)
ATT-RANK            ( curves n time -- indices )   Sort by score descending
ATT-TOP-K           ( curves n k time -- indices ) Top-k by score
ATT-THRESHOLD       ( curves n min-score time -- indices m )
                    \ All above threshold

\ Introspection
ATT-PEAK-TIME       ( curve -- time )          When is relevance highest?
ATT-ZERO-TIME       ( curve -- time )          When does relevance drop to ~0?
ATT-HALF-TIME       ( curve -- time )          When does relevance halve?
```

### Internals

- Each curve is a small descriptor (24–32 bytes): type tag + FP16
  parameters
- Exponential decay computed via `e^(-λt)` — λ derived from half-life
  as `ln(2)/half_life`; `ln` and `exp` approximated via FP16
  Taylor series or table lookup
- Deadline curves clamp to a max value to avoid infinity at t=deadline
- Composite curves (`ATT-ADD`, `ATT-MUL`, `ATT-MAX`) store pointers
  to operands, evaluated lazily
- `ATT-RANK`: populate temp array of (index, score), quicksort
  (reuse `math/sort.f`)
- All times in KDOS epoch seconds; datetime conversion via
  `utils/datetime.f`

---

## Phase 8 — Argument Structure ★

**Module:** `akashic/knowledge/argument.f`
**Estimated size:** ~500–600 lines
**Novelty:** **Genuine gap.** Toulmin model and Dung frameworks are
textbook AI/KR. Zero usable libraries.
**Depends on:** arena allocator

Data structures for modeling arguments, claims, evidence, attack/support
relations, and evaluating argumentation frameworks.

### Data Model

Supports both Toulmin and Dung models:

**Toulmin node** — 64 bytes:
```
  +0   id             8
  +8   type           8   0=claim, 1=grounds, 2=warrant, 3=backing,
                          4=rebuttal, 5=qualifier
  +16  text-addr      8
  +24  text-len       8
  +32  parent-ptr     8   The claim this supports/attacks
  +40  first-child    8   Sub-arguments
  +48  next-sibling   8
  +56  confidence     8   FP16 confidence score (0.0–1.0)
```

**Dung attack relation** — 24 bytes:
```
  +0   attacker-id    8
  +8   target-id      8
  +16  type           8   0=attack, 1=support
```

### API

```
\ Lifecycle
ARG-CREATE          ( -- framework )           Create empty framework
ARG-DESTROY         ( framework -- )

\ Toulmin model
ARG-CLAIM           ( text len fw -- nid )         Add a claim
ARG-GROUNDS         ( text len claim-nid fw -- nid )  Evidence for claim
ARG-WARRANT         ( text len claim-nid fw -- nid )  Inference license
ARG-BACKING         ( text len warrant-nid fw -- nid ) Support for warrant
ARG-REBUTTAL        ( text len claim-nid fw -- nid )   Counter-argument
ARG-QUALIFIER       ( text len claim-nid fw -- nid )   Degree of certainty

\ Dung abstract framework
ARG-ATTACKS         ( attacker-nid target-nid fw -- )   Record attack
ARG-SUPPORTS        ( supporter-nid target-nid fw -- )  Record support

\ Evaluation
ARG-GROUNDED        ( fw -- addr n )       Grounded extension (skeptical)
ARG-PREFERRED       ( fw -- addr n )       Preferred extensions (credulous)
ARG-IS-ACCEPTABLE?  ( nid fw -- flag )     Is node in grounded extension?
ARG-DEFEATED?       ( nid fw -- flag )     Is node defeated by undefeated attacker?

\ Traversal
ARG-ATTACKERS       ( nid fw -- addr n )   Who attacks this node?
ARG-SUPPORTERS      ( nid fw -- addr n )   Who supports this node?
ARG-DEPENDS-ON      ( nid fw -- addr n )   Transitive dependencies
ARG-CHAIN           ( nid fw -- addr n )   Full argument chain to root claim

\ Confidence propagation
ARG-SET-CONFIDENCE  ( score nid fw -- )
ARG-PROPAGATE       ( fw -- )              Propagate confidence through framework
ARG-STRENGTH        ( nid fw -- score )    Computed strength after propagation

\ Serialization
ARG-EXPORT-JSON     ( fw -- addr len )
ARG-IMPORT-JSON     ( addr len fw -- )
```

### Internals

- Grounded extension: iterative fixpoint — start with unattacked
  arguments, mark as accepted, mark their targets as defeated,
  repeat until stable
- Preferred extension: backtracking search for conflict-free,
  admissible sets (exponential worst case, but frameworks are
  typically small — <100 nodes)
- Confidence propagation: attacker reduces parent confidence by
  `(1 - attacker_confidence)`; supporter adds
  `supporter_confidence × weight`; iterate until convergence

---

## Phase 9 — Three-Way Structured Merge ★

**Module:** `akashic/knowledge/merge3.f`
**Estimated size:** ~500–700 lines
**Novelty:** **Genuine gap.** `json-merge-patch` (RFC 7396) is
trivial overwrite.  CRDTs are a different (heavier) model.
**Depends on:** `utils/json.f`, `utils/string.f`, arena allocator

Three-way merge for tree-structured data: given (base, mine, theirs),
produce a merged result with conflict markers.

### API

```
\ JSON merge
M3-JSON             ( base blen mine mlen theirs tlen -- result rlen conflicts )
                    Three-way merge of JSON documents.  Returns merged
                    JSON + count of unresolvable conflicts.

\ State-tree merge
M3-STATE-TREE       ( base mine theirs -- merged conflicts )
                    Three-way merge of state trees.

\ Generic tree merge (callback-based)
M3-TREE             ( base mine theirs compare-xt merge-xt -- merged conflicts )
                    Caller provides comparison and merge callbacks.

\ Diff (prerequisite for merge)
M3-DIFF             ( old olen new nlen -- edits n )
                    Structural diff — returns list of edit operations

\ Conflict resolution
M3-CONFLICT-COUNT   ( result -- n )
M3-CONFLICT-NTH     ( n result -- path plen mine-val mlen theirs-val tlen )
M3-RESOLVE          ( resolved-val rlen n result -- )   Resolve nth conflict manually
M3-RESOLVE-MINE     ( result -- )             Auto-resolve all: pick mine
M3-RESOLVE-THEIRS   ( result -- )             Auto-resolve all: pick theirs

\ Edit operations
M3-EDIT-TYPE        ( edit -- type )          0=add, 1=remove, 2=change, 3=move
M3-EDIT-PATH        ( edit -- addr len )      Path of edited node
M3-EDIT-VALUE       ( edit -- addr len )      New value (for add/change)
```

### Internals

- Diff algorithm: tree edit distance (simplified Zhang-Shasha for
  ordered trees, or path-based comparison for JSON objects)
- Merge: compute diff(base,mine) and diff(base,theirs), apply
  non-conflicting edits from both, flag conflicts where both
  modify the same path
- Conflict: same path edited differently in mine and theirs
- Non-conflict: path edited in only one side, or both sides make
  identical changes
- JSON-specific: object key ordering doesn't matter (set semantics
  for keys); array merge uses LCS for position alignment

---

## Phase 10 — Consent & Delegation Chains ★

**Module:** `akashic/knowledge/consent.f`
**Estimated size:** ~500–600 lines
**Novelty:** **Genuine gap.** GDPR made this legally required.
Every company rolls their own. No `pip install consent-chains`.
**Depends on:** `utils/datetime.f`, `math/sha256.f`, arena allocator

Modeling authorization chains: who authorized what, delegated to whom,
for what purpose, revocable when, with constraint propagation and
audit trail.

### Data Model

```
Consent grant — 80 bytes:
  +0   id             8   Grant ID
  +8   grantor        8   Who is giving consent
  +16  grantee        8   Who receives consent
  +24  scope-bits     8   Purpose flags (up to 64 purposes)
  +32  resource       8   What data/action this covers
  +40  granted-at     8   Timestamp
  +48  expires-at     8   Expiry (0 = no expiry)
  +56  parent-grant   8   Delegation chain (0 = root grant)
  +64  status         8   0=active, 1=revoked, 2=expired, 3=superseded
  +72  hash           8   SHA-256 of grant content (first 8 bytes)
```

### API

```
\ Lifecycle
CON-CREATE          ( -- chain )                Create consent store
CON-DESTROY         ( chain -- )

\ Granting
CON-GRANT           ( grantor grantee scope resource expiry chain -- gid )
                    Record a new consent grant
CON-DELEGATE        ( parent-gid new-grantee chain -- gid | 0 )
                    Delegate subset of existing grant (fails if scope would expand)
CON-REVOKE          ( gid chain -- )
                    Revoke grant + all downstream delegations

\ Querying
CON-CHECK           ( grantee scope resource chain -- flag )
                    Does grantee have active consent for scope+resource?
CON-CHECK-AT        ( grantee scope resource time chain -- flag )
                    Consent valid at specific time?
CON-GRANTS-FOR      ( grantee chain -- addr n )
                    All active grants for grantee
CON-GRANTS-BY       ( grantor chain -- addr n )
                    All grants issued by grantor
CON-CHAIN           ( gid chain -- addr n )
                    Delegation chain from grant to root

\ Lifecycle management
CON-EXPIRE-CHECK    ( chain -- n )             Mark expired grants, return count
CON-CLEANUP         ( chain -- n )             Remove revoked/expired grants
CON-ACTIVE-COUNT    ( chain -- n )

\ Constraint propagation
CON-SCOPE-EFFECTIVE ( gid chain -- scope-bits )
                    Effective scope (intersection of chain)
CON-CAN-DELEGATE?   ( gid scope chain -- flag )
                    Can this grant delegate the given scope?

\ Audit
CON-AUDIT-LOG       ( chain -- addr n )        Full audit trail
CON-AUDIT-FOR       ( resource chain -- addr n )
                    Audit trail for specific resource
CON-VERIFY          ( chain -- flag )          Verify hash chain integrity
```

### Internals

- Delegation rule: child grant scope must be a *subset* of parent
  scope (bitwise: `child-scope AND parent-scope = child-scope`).
  Expiry must be ≤ parent expiry.
- Revocation cascades: revoking a grant revokes all downstream
  delegations (walk child pointers)
- Effective scope: intersection (AND) of all scope-bits along the
  delegation chain to root
- Hash chain: each grant hashes `(grantor, grantee, scope, resource,
  granted-at, parent-hash)` for tamper detection
- Time-aware queries: check `granted-at ≤ t < expires-at` and
  `status = active` along chain

---

## Phase 11 — Citation Graph

**Module:** `akashic/knowledge/citation.f`
**Estimated size:** ~500–600 lines
**Novelty:** `citeproc-py` and `pybtex` exist in Python. Building
the Forth equivalent for completeness.
**Depends on:** `utils/string.f`, `utils/json.f`, arena allocator

Citation network modeling, bibliography formatting, and graph traversal.

### API

```
\ Lifecycle
CITE-CREATE         ( -- db )
CITE-DESTROY        ( db -- )

\ Record management
CITE-ADD            ( json len db -- rid )      Add bibliographic record (CSL-JSON)
CITE-REMOVE         ( rid db -- )
CITE-GET            ( rid db -- json len )
CITE-FIND           ( key len db -- rid | 0 )   Find by citation key

\ Citation links
CITE-CITES          ( rid-from rid-to db -- )    Record citation link
CITE-UNCITE         ( rid-from rid-to db -- )
CITE-REFS           ( rid db -- addr n )         What does this cite?
CITE-CITED-BY       ( rid db -- addr n )         What cites this?

\ Graph
CITE-DEGREE-IN      ( rid db -- n )              Citation count
CITE-DEGREE-OUT     ( rid db -- n )              Reference count
CITE-COMMON-REFS    ( rid1 rid2 db -- addr n )   Shared references (co-citation)
CITE-BFS            ( rid depth db -- addr n )   Citation neighborhood

\ Formatting
CITE-FORMAT-APA     ( rid db -- addr len )       APA 7th style
CITE-FORMAT-CHICAGO ( rid db -- addr len )       Chicago Manual
CITE-FORMAT-IEEE    ( rid db -- addr len )       IEEE style
CITE-BIBLIOGRAPHY   ( rids n style db -- addr len )  Full bibliography

\ Identifiers
CITE-DOI            ( rid db -- addr len | 0 )   Extract DOI
CITE-ISBN           ( rid db -- addr len | 0 )   Extract ISBN

\ Import/Export
CITE-IMPORT-BIBTEX  ( addr len db -- n )         Parse BibTeX, return count added
CITE-EXPORT-BIBTEX  ( db -- addr len )           Export as BibTeX
CITE-EXPORT-JSON    ( db -- addr len )           Export as CSL-JSON array
```

---

## Phase 12 — Concordance & Index Generator

**Module:** `akashic/knowledge/concordance.f`
**Estimated size:** ~400–500 lines
**Novelty:** NLTK has basic `concordance()`. Publication-grade
back-of-book indexing with see/see-also, subheadings, and range
collapsing doesn't exist as a library.
**Depends on:** `utils/string.f`, `knowledge/search.f` (tokenizer)

### API

```
\ Concordance (KWIC — keyword in context)
CONC-BUILD          ( text len window -- conc )    Build concordance
CONC-LOOKUP         ( word len conc -- addr n )    KWIC lines for word
CONC-ALL-TERMS      ( conc -- addr n )             All indexed terms
CONC-FREQUENCY      ( word len conc -- n )         Term frequency
CONC-DESTROY        ( conc -- )

\ Back-of-book index
IDX-CREATE          ( -- idx )
IDX-DESTROY         ( idx -- )
IDX-ADD-TERM        ( term len page idx -- )             Index a term at page
IDX-ADD-RANGE       ( term len page-start page-end idx -- )  Page range
IDX-ADD-SEE         ( term len target len idx -- )       "See" cross-reference
IDX-ADD-SEE-ALSO    ( term len target len idx -- )       "See also"
IDX-ADD-SUBHEAD     ( main len sub len page idx -- )     Subheading under main entry
IDX-SET-STOPWORDS   ( addr n idx -- )                    Ignore these terms

\ Index generation
IDX-GENERATE        ( idx -- addr len )    Formatted index as text
IDX-COLLAPSE-RANGES ( idx -- )             Merge consecutive pages: 1,2,3 → 1–3

\ Auto-indexing
IDX-AUTO            ( text len page idx -- )   Auto-extract significant terms
                    \ Uses TF threshold + stop-word filtering
```

---

## Phase 13 — Provenance Tracker

**Module:** `akashic/knowledge/provenance.f`
**Estimated size:** ~400–500 lines
**Novelty:** Python's `prov` library implements W3C PROV-DM.
Building Forth equivalent.
**Depends on:** `utils/datetime.f`, `utils/json.f`, arena allocator

W3C PROV-DM compatible: entities, activities, agents, and the
relations between them (used, generated, derived, attributed,
delegated, influenced).

### API

```
\ Lifecycle
PROV-CREATE         ( -- prov )
PROV-DESTROY        ( prov -- )

\ Core types
PROV-ENTITY         ( id len prov -- eid )          Something that exists
PROV-ACTIVITY       ( id len start end prov -- aid ) Something that happened
PROV-AGENT          ( id len prov -- gid )           Someone responsible

\ Relations (W3C PROV-DM)
PROV-USED           ( aid eid prov -- )              Activity used entity
PROV-GENERATED      ( eid aid prov -- )              Entity generated by activity
PROV-DERIVED        ( eid1 eid2 prov -- )            eid1 derived from eid2
PROV-ATTRIBUTED     ( eid gid prov -- )              Entity attributed to agent
PROV-ASSOCIATED     ( aid gid prov -- )              Activity associated with agent
PROV-DELEGATED      ( gid1 gid2 aid prov -- )        Agent delegated by agent for activity
PROV-INFLUENCED     ( id1 id2 prov -- )              Generic influence

\ Queries
PROV-HISTORY        ( eid prov -- addr n )           Derivation chain (ancestors)
PROV-ORIGIN         ( eid prov -- eid' | 0 )         Ultimate source entity
PROV-WHO            ( eid prov -- addr n )            Agents attributed/associated
PROV-WHEN           ( eid prov -- start end )         Time bounds from generating activity
PROV-DERIVED-FROM?  ( eid1 eid2 prov -- flag )        Transitive derivation check

\ Export (W3C PROV-JSON)
PROV-EXPORT-JSON    ( prov -- addr len )
PROV-IMPORT-JSON    ( addr len prov -- )
```

---

## Phase 14 — Similarity & Deduplication

**Module:** `akashic/knowledge/similarity.f`
**Estimated size:** ~500–600 lines
**Novelty:** `datasketch` and `dedupe` exist in Python. Building
Forth equivalent.
**Depends on:** `math/sha256.f`, `math/stats.f`, `utils/string.f`

MinHash, SimHash, and locality-sensitive hashing for near-duplicate
detection.

### API

```
\ Shingling
SIM-SHINGLES        ( text len k -- set )    k-character shingles
SIM-WORD-SHINGLES   ( text len k -- set )    k-word shingles

\ MinHash
SIM-MINHASH-CREATE  ( num-perms -- mh )       Create MinHash signature
SIM-MINHASH-UPDATE  ( set mh -- )             Add shingle set
SIM-MINHASH-JACCARD ( mh1 mh2 -- similarity ) Estimated Jaccard similarity (FP16)

\ SimHash (fingerprinting)
SIM-SIMHASH         ( text len -- hash64 )    64-bit SimHash fingerprint
SIM-HAMMING         ( h1 h2 -- distance )     Hamming distance between hashes
SIM-SIMHASH-SIMILAR?( h1 h2 threshold -- flag )

\ LSH (locality-sensitive hashing)
SIM-LSH-CREATE      ( bands rows -- lsh )     Create LSH index
SIM-LSH-INSERT      ( mh doc-id lsh -- )      Insert MinHash
SIM-LSH-QUERY       ( mh lsh -- addr n )      Candidate near-duplicates
SIM-LSH-DESTROY     ( lsh -- )

\ High-level
SIM-FIND-DUPES      ( texts lens n threshold -- pairs m )
                    Full pipeline: shingle → minhash → LSH → verify
SIM-PAIRWISE        ( texts lens n -- matrix )
                    Pairwise similarity matrix (FP16)
```

---

## Phase 15 — Feed Curation & Digest ★

**Module:** `akashic/knowledge/feed.f`
**Estimated size:** ~500–600 lines
**Novelty:** **Genuine gap.** `feedparser` does parsing. No library
does curation logic — dedup, scoring, bucketing, digest generation.
**Depends on:** `knowledge/similarity.f`, `knowledge/attention.f`,
`utils/datetime.f`, `utils/string.f`

### API

```
\ Lifecycle
FEED-CREATE         ( -- feed )
FEED-DESTROY        ( feed -- )

\ Ingestion
FEED-ADD-ITEM       ( title tlen body blen url ulen timestamp feed -- iid )
FEED-ADD-SOURCE     ( name len priority feed -- sid )
FEED-TAG-ITEM       ( iid tag len feed -- )

\ Deduplication (uses similarity module)
FEED-DEDUP          ( feed -- removed )        Remove near-duplicate items
FEED-SET-DEDUP-THRESHOLD ( threshold feed -- )  MinHash similarity threshold (FP16)

\ Scoring (uses attention module)
FEED-SET-DECAY      ( curve feed -- )          Default attention curve for items
FEED-SCORE          ( iid feed -- score )      Current relevance score
FEED-BOOST          ( factor iid feed -- )     Manual boost/bury (FP16 multiplier)

\ Querying
FEED-TOP            ( k feed -- addr n )       Top-k items by score
FEED-BY-TAG         ( tag len feed -- addr n ) Items matching tag
FEED-BY-SOURCE      ( sid feed -- addr n )     Items from source
FEED-SINCE          ( timestamp feed -- addr n ) Items newer than
FEED-UNREAD         ( feed -- addr n )         Unread items

\ Read tracking
FEED-MARK-READ      ( iid feed -- )
FEED-MARK-UNREAD    ( iid feed -- )
FEED-IS-READ?       ( iid feed -- flag )

\ Digest generation
FEED-DIGEST         ( max-items period feed -- addr n )
                    Generate digest: top items from period, deduped, ranked
FEED-DIGEST-TEXT    ( max-items period feed -- text len )
                    Formatted text digest

\ Queue management
FEED-QUEUE-ADD      ( iid priority feed -- )   Add to read-later queue
FEED-QUEUE-NEXT     ( feed -- iid | 0 )        Pop highest-priority
FEED-QUEUE-REORDER  ( feed -- )                Re-sort by current scores
FEED-QUEUE-DEPENDS  ( iid dep-iid feed -- )    "Read iid before dep-iid"
```

---

## Phase 16 — Progressive Disclosure ★

**Module:** `akashic/knowledge/disclosure.f`
**Estimated size:** ~400–500 lines
**Novelty:** **Genuine gap.** Every dashboard, docs site, and news
app reinvents this. No library models multi-level content with
focus/context navigation.
**Depends on:** `utils/string.f`, arena allocator

### Data Model

```
Disclosure node — 56 bytes:
  +0   id             8
  +8   parent-ptr     8
  +16  first-child    8
  +24  next-sibling   8
  +32  level          8   Detail level (0 = most summary, N = full detail)
  +40  content-addr   8   Content at this detail level
  +48  content-len    8
```

### API

```
\ Lifecycle
PD-CREATE           ( -- pd )
PD-DESTROY          ( pd -- )

\ Structure
PD-ADD              ( content len level parent pd -- nid )
PD-ADD-ROOT         ( content len level pd -- nid )
PD-SET-CONTENT      ( content len level nid pd -- )   Set content for level

\ Navigation
PD-SUMMARY          ( nid pd -- addr len )             Level 0 (briefest)
PD-DETAIL           ( nid pd -- addr len )             Highest level (fullest)
PD-AT-LEVEL         ( level nid pd -- addr len )       Content at specific level
PD-MAX-LEVEL        ( nid pd -- n )                    Deepest detail level

\ View generation
PD-VIEW             ( level pd -- addr n )     All nodes rendered at level
PD-VIEW-FOCUSED     ( focus-nid context-level detail-level pd -- addr n )
                    Focus node at detail-level, everything else at context-level
PD-EXPAND           ( nid pd -- )              Drill down: show children
PD-COLLAPSE         ( nid pd -- )              Roll up: show only summary

\ Outline
PD-OUTLINE          ( pd -- addr len )         Table-of-contents style outline
PD-BREADCRUMB       ( nid pd -- addr n )       Path from root to node (summaries)
```

---

## Phase 17 — Conversation Structure ★

**Module:** `akashic/knowledge/conversation.f`
**Estimated size:** ~500–600 lines
**Novelty:** **Genuine gap.** Forum software has ad-hoc threading.
No library models the *structure* of a conversation as a reusable
data model.
**Depends on:** `utils/datetime.f`, `knowledge/temporal.f`, arena allocator

### API

```
\ Lifecycle
CONV-CREATE         ( -- conv )
CONV-DESTROY        ( conv -- )

\ Turns
CONV-TURN           ( speaker text len timestamp conv -- tid )
                    Add a conversational turn
CONV-REPLY          ( parent-tid speaker text len timestamp conv -- tid )
                    Reply to specific turn (creates thread)

\ Topic tracking
CONV-TOPIC-START    ( topic len tid conv -- )    Mark turn as starting new topic
CONV-TOPIC-RESUME   ( topic len tid conv -- )    Mark turn as resuming old topic
CONV-TOPICS         ( conv -- addr n )           All topics mentioned
CONV-TOPIC-TURNS    ( topic len conv -- addr n ) All turns under topic

\ References
CONV-REFERS-TO      ( tid ref-tid conv -- )      "As I said earlier" link
CONV-REFS           ( tid conv -- addr n )        What does this turn reference?
CONV-REFD-BY        ( tid conv -- addr n )        What references this turn?

\ Threading
CONV-THREAD         ( tid conv -- addr n )        Full thread from root turn
CONV-FORKS          ( conv -- addr n )             Points where conversation branched
CONV-MAIN-THREAD    ( conv -- addr n )             Longest/primary thread

\ Stance tracking
CONV-AGREES         ( tid ref-tid conv -- )        Speaker agrees with reference
CONV-DISAGREES      ( tid ref-tid conv -- )        Speaker disagrees
CONV-QUESTIONS      ( tid ref-tid conv -- )        Speaker questions/requests
CONV-ANSWERS        ( tid ref-tid conv -- )        Speaker answers a question
CONV-STANCE         ( tid conv -- addr n )         All stance relations for turn

\ Summary
CONV-PARTICIPANTS   ( conv -- addr n )             All speakers
CONV-TURN-COUNT     ( conv -- n )
CONV-DURATION       ( conv -- start end )          Time span
CONV-SPEAKER-TURNS  ( speaker conv -- addr n )     Turns by specific speaker
```

---

## Phase 18 — Reading Path Optimizer ★

**Module:** `akashic/knowledge/readpath.f`
**Estimated size:** ~400–500 lines
**Novelty:** **Genuine gap.** Every MOOC has this as proprietary
backend. No library.
**Depends on:** `knowledge/taxonomy.f`, `knowledge/attention.f`,
arena allocator

### API

```
\ Lifecycle
RP-CREATE           ( -- rp )
RP-DESTROY          ( rp -- )

\ Corpus
RP-ADD-ITEM         ( title len effort rp -- iid )
                    Add item with estimated effort (minutes, FP16)
RP-PREREQ           ( iid-before iid-after rp -- )
                    Declare prerequisite relationship
RP-TAG              ( iid tag len rp -- )
                    Tag item (for goal-based filtering)

\ Learner state
RP-MARK-KNOWN       ( iid rp -- )            Learner already knows this
RP-MARK-COMPLETED   ( iid rp -- )            Learner has consumed this
RP-SET-GOAL         ( tag len rp -- )         "I want to understand X"

\ Path generation
RP-SHORTEST-PATH    ( rp -- iids n )         Shortest path to goal
                    \ Respects prereqs, skips known items.
                    \ Topological sort + known-item pruning.
RP-FULL-PATH        ( rp -- iids n )         Complete path (no shortcuts)
RP-ESTIMATED-TIME   ( rp -- minutes )        Total effort for shortest path

\ Feedback & adaptation
RP-TOO-HARD         ( iid rp -- )            Mark item as too difficult
                    \ Inserts prereqs of iid before it in the path
RP-TOO-EASY         ( iid rp -- )            Mark as too easy
                    \ Marks as completed, skips similar-level items
RP-RECALCULATE      ( rp -- )                Recompute path after feedback

\ Multiple paths
RP-ALT-PATHS        ( max-paths rp -- paths n )
                    Alternative valid orderings
RP-PATH-EFFORT      ( path rp -- minutes )   Effort estimate for a specific path

\ Visualization
RP-PREREQ-GRAPH     ( rp -- edges n )        All prerequisite edges
RP-PROGRESS         ( rp -- completed total ) Progress toward goal
```

### Internals

- Prerequisite graph: adjacency list (arena-allocated)
- Path generation: topological sort (Kahn's algorithm) filtered
  by goal reachability (reverse BFS from goal items) and pruned
  by known items
- Effort estimation: sum of effort values for remaining items
- `RP-TOO-HARD`: locate prereqs of item, insert before it, recalculate
- `RP-ALT-PATHS`: enumerate topological orderings up to max-paths
  (DFS with backtracking, bounded)

---

## Implementation Order

Priority ordering balances novelty, utility, and dependency:

### Tier 1 — Primitives (no inter-phase dependencies)

These can be built in any order or in parallel:

| Priority | Phase | Module | Est. Lines | Deps |
|----------|-------|--------|------------|------|
| 1a | 5 | Temporal intervals ★ | ~500 | datetime |
| 1b | 6 | Branching undo ★ | ~450 | arena |
| 1c | 7 | Attention decay ★ | ~350 | fp16, datetime |
| 1d | 8 | Argument structure ★ | ~550 | arena |
| 1e | 3 | Content-addressed storage | ~600 | sha256, dag-cbor |
| 1f | 9 | Three-way merge ★ | ~600 | json, string |

### Tier 2 — Engines (depend on Tier 1 or Akashic only)

| Priority | Phase | Module | Est. Lines | Deps |
|----------|-------|--------|------------|------|
| 2a | 1 | Taxonomy | ~700 | string, arena |
| 2b | 2 | Search/IR | ~900 | string, stats |
| 2c | 4 | Annotation ★ | ~700 | string, datetime, arena |
| 2d | 10 | Consent chains ★ | ~550 | datetime, sha256 |
| 2e | 14 | Similarity | ~550 | sha256, stats |
| 2f | 13 | Provenance | ~450 | datetime, json |
| 2g | 11 | Citation | ~550 | string, json |
| 2h | 12 | Concordance | ~450 | string, search |

### Tier 3 — Applications (depend on Tier 2)

| Priority | Phase | Module | Est. Lines | Deps |
|----------|-------|--------|------------|------|
| 3a | 15 | Feed curation ★ | ~550 | similarity, attention |
| 3b | 16 | Progressive disclosure ★ | ~450 | string, arena |
| 3c | 17 | Conversation structure ★ | ~550 | datetime, temporal |
| 3d | 18 | Reading path ★ | ~450 | taxonomy, attention |

### Total estimate: ~9,400 lines across 18 modules

For reference, Akashic is currently ~46,000 lines. This adds ~20%.

---

## Design Constraints

### Memory

- All modules use arena allocation for bulk teardown
- Constraint matrices (temporal intervals) sized for ~64 items
  (8 KiB) — configurable at create time
- Hash tables use open addressing with power-of-2 sizing
- No module allocates more than ~64 KiB at rest

### Naming

| Module | Public prefix | Internal prefix |
|--------|---------------|-----------------|
| Taxonomy | `TAX-` | `_TAX-` |
| Search | `IX-` | `_IX-` |
| CAS | `CAS-` | `_CAS-` |
| Annotation | `ANN-` | `_ANN-` |
| Temporal | `TI-` | `_TI-` |
| Undo | `UNDO-` | `_UND-` |
| Attention | `ATT-` | `_ATT-` |
| Argument | `ARG-` | `_ARG-` |
| Merge3 | `M3-` | `_M3-` |
| Consent | `CON-` | `_CON-` |
| Citation | `CITE-` | `_CIT-` |
| Concordance | `CONC-` | `_CONC-` |
| Provenance | `PROV-` | `_PROV-` |
| Similarity | `SIM-` | `_SIM-` |
| Feed | `FEED-` | `_FEED-` |
| Disclosure | `PD-` | `_PD-` |
| Conversation | `CONV-` | `_CONV-` |
| Reading path | `RP-` | `_RP-` |

### Error Handling

Standard Akashic pattern:

```forth
VARIABLE TAX-ERR
1 CONSTANT TAX-E-NOT-FOUND
2 CONSTANT TAX-E-CYCLE
3 CONSTANT TAX-E-FULL
: TAX-FAIL       ( code -- )  TAX-ERR ! ;
: TAX-OK?        ( -- flag )  TAX-ERR @ 0= ;
: TAX-CLEAR-ERR  ( -- )       0 TAX-ERR ! ;
```

### Internal Layering

Each file follows the standard 4-layer structure:

```forth
\ =====================================================================
\  Layer 0 — Constants, Error Codes, Descriptors
\ =====================================================================

\ =====================================================================
\  Layer 1 — Internal Helpers
\ =====================================================================

\ =====================================================================
\  Layer 2 — Public API
\ =====================================================================

\ =====================================================================
\  Layer 3 — Integration / Pipeline
\ =====================================================================
```

---

## Testing Strategy

Each module gets a companion Python test file under `tests/`:

- **Unit tests:** Each public word tested in isolation
- **Property tests:** Invariant verification (e.g., taxonomy parent
  of child is consistent after move; CAS hash always matches content;
  consent delegation scope is always subset of parent)
- **Round-trip tests:** Export → import produces identical structure
  (annotation, citation, provenance, consent)
- **Stress tests:** Fill to capacity, verify GC/cleanup, check
  arena teardown leaves no leaks

**Test count estimate:** ~40–60 tests per module, ~800–1,000 total.

Temporal interval reasoning gets a dedicated composition-table
verification test: all 169 entries of the Allen composition table
checked against known-correct results from Allen (1983).

Argument structure gets known Dung framework examples from the
literature (grounded extension of standard examples verified).

Three-way merge gets conflict-detection tests derived from known
git merge scenarios translated to JSON structures.
