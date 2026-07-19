# urcu-txn paper series

Defensive publications on the userspace-RCU pseudo-transaction engine
(`rcu-txn` / `rcu-mcas`), targeting arXiv.

## Purpose

These are **defensive publications**: their job is to establish dated, public,
*enabling* prior art so the ideas stay freely usable. That differs from a normal
academic paper in three ways, and the difference shapes every document here:

1. **Coverage beats elegance.** A patent claim can cover an obvious variant of
   what is disclosed, so each paper carries a *Variations and Alternatives*
   section enumerating the design space we did not take. A normal paper cuts
   this; here it is load-bearing.
2. **Date beats polish.** arXiv timestamps on submission. Getting the core
   disclosure up early beats a perfect paper later.
3. **Enablement beats evaluation.** The pseudocode and the invariants are the
   defensive payload. Benchmarks strengthen the academic case but do almost
   nothing defensively — which is why evaluation is last, not first.

## The series

| # | Directory | Topic | Status |
|---|-----------|-------|--------|
| 1 | `p1-sw-flip-latch/` | RCU pseudo-transactions + the single-writer flip-latch | **drafted, complete prose; pinned b5767298** |
| 2 | `p2-sole-driver-mcas/` | Sole-driver MCAS: the MW engine (no-RDCSS) + logical deletion, applied | **first draft; pinned c7f428a8** ([`SCOPE.md`](p2-sole-driver-mcas/SCOPE.md)) |
| 3 | `p3-programming-model/` | Read-*set* validation: read policy, guards, declarations; the read-side snapshot menu (forward-refs DLM for the wait-free version/latch) | not started |
| 4 | `p4-evaluation/` | Comprehensive comparative evaluation (see fork below) | not started |

**Candidate further papers** (queued, not scheduled):

- **DLM-style hybrid.** MW-txn for a per-node lock + tombstone, SW-txn for the
  structural changes under that lock, plus the **GP-bounded version / wait-free
  single-bit latch** as its read-side snapshot layer (folded in 2026-07-19; no
  longer a standalone candidate). This is how the Fractal Trie reaches
  existence-like behaviour (commit width = number of *nodes*, not edges). The
  per-node lock is exactly what supplies the write-side serialization the clean
  parity latch needs — the SW flip-latch doubles as the version selector — which
  is why the latch belongs *here* rather than in P3 (Arm A, 2026-07-19). Design
  docs: the DLM scheme, and
  `efficios-trie-benchmark/design/rcu-gp-bounded-version.md` (version/latch). **SoA
  review done (2026-07-19): novel *composition*, not a new primitive** — the
  wait-free/torn-free single-bit-toggle read property is **Left-Right's**
  (Ramalhete–Correia, DISC 2015, which does it better: 0 retry vs ≤ 1). Claim only
  the mechanism (single in-place instance + RCU-GP-bounded seqcount + COW overflow
  + reader-drain outsourced to the already-paid grace period, zero reader-side
  writes); cite-and-distinguish **Left-Right, ARC (TPDS 2019), plain RCU, seqlock
  (Boehm 2012), and RLU** — no surveyed scheme occupies the single-instance +
  wait-free corner (the axes are anti-correlated). Both prior-art gaps are now
  **closed**: the version-snapshot / EBR family (second review — RLU is closest on
  footprint but copies per-write), and RCU's own GP flip-counter (it is
  grace-period *detection*, global/per-domain and per-CPU-split, confirmed against
  perfbook — not a per-node reader data-version). The boundary + two-axis map live
  in `rcu-gp-bounded-version.md` (benchmark tree commit `4118b04`). Demonstrator:
  extend the same-user list/hlist node with a **multi-word payload** —
  version-on-payload beside the lock/tombstone on the links.
- **Dentry cache over rcu-txn.** The Linux dcache ported from kernel to
  userspace on the txn engine — *"can urcu-txn dissolve `rename_lock`?"*.
  Landed + stress-validated (S3 results on 2×96-core EPYC). Full novelty
  inventory in [`candidates/dcache.md`](candidates/dcache.md); design note is
  `efficios-trie-benchmark/experiments/dcache/rename-shell-transition.md`.
  Headline novelties: the **host/shell** split (inline names + stable-address
  identity, no recompaction) and the **per-node move-detection generation** (a
  scalable replacement for the global `rename_lock`), plus a lock-free
  cross-dir loop check via `load_validate`. Depends on P2/P3 (uses the MW
  engine + programming model), so it slots after them despite already existing.
  **A standalone application paper, not P4's evaluation:** its novelties (host/shell,
  move-detection generation) are first-class contributions, not benchmark datapoints —
  though its 2×96-core scaling result is a headline workload P4 can cite.
- **Wait-free multi-word snapshot via a single-bit GP-gated seqcount latch**
  (suspected novel). A one-bit seqcount whose flips are gated to one per grace
  period per node, with a copy-on-write overflow escape, makes a torn-free
  multi-word read *also* wait-free (≤ 1 retry, constant in writer count).
  **No longer a standalone candidate (2026-07-19, Arm A): it folds into the
  DLM-hybrid paper above**, because its clean parity form needs the DLM per-node
  lock for write-side serialization (the SW flip-latch acts as the version
  selector). **Kept out of P1** — a full enabling disclosure beats a hint, and P1
  stays neutral on read-side progress class (§7.4). P3 references it in its
  read-side snapshot menu and forward-refs DLM for the construction. Design:
  `efficios-trie-benchmark/design/rcu-gp-bounded-version.md` (extracted from
  `rcu-txn-blob.md`).
- **Non-pointer transacted slots** (deferred with the above). The tag contract
  constrains *values*, not pointers, so a counter or bitmap word can be
  transacted by spending one payload bit. Cut from P1 (2026-07-17): **P1 is
  pointers-only**. The one genuinely useful non-pointer application is a
  **sequence counter** (Mathieu), which pairs naturally with the version/latch,
  now in the DLM-hybrid paper above. Note the trap that forced the cut: a "bitmap
  bit flips atomically with an accompanying pointer" example is *writer*-atomic
  (one commit) but gives readers no cross-slot snapshot — they read slot-by-slot —
  so consuming the pair needs a seqcount or recompaction. That belongs in the
  version/DLM paper, not P1.

**Candidate order** (all post-P3; dependency/readiness, not a commitment): **dcache**
first — it already exists (landed + validated), the most writeable and the strongest
application result; **DLM-hybrid** (now carrying the version/latch and the
non-pointer sequence counter) then the **Fractal Trie** are the deeper structural
line.

The Fractal Trie proper is **deferred** — work still heavily in progress. It is the
capstone of that line and carries the engine-specific *wide-node* packing (the
unified proxy/tombstone/`nr_child` state word, recompact-on-insert); the general
logical-deletion tombstone itself is **disclosed earlier, in P2** — as applied
prior art, with P2 claiming no novelty in it (see the P2 §6 rewrite, 2026-07-18).

**Order rationale.** Single-writer comes first: it is the simpler mechanism, it
establishes the record/status/commit vocabulary the multi-writer paper reuses,
and it makes P1 short. That matters because the first submission is the one
arXiv moderators use to size up a new account.

The programming model does not split evenly between the engines. As of
b5767298, **read-your-own-writes and disjoint declarations are shared** — the sw
engine gained both, so P1 demonstrates them and P3 will not have to introduce
them from scratch.

The P2/P3 line is **write-set vs read-set validation.** P2 owns write-set atomicity
and everything that makes a mutating structure *usable* under concurrency: the
sole-driver commit, the abort/aging/fair-mutex escalation *mechanism*, and — because
per-slot atomicity is not operation atomicity — **freeze-on-free**, whose general
primitive (the **RCU-forwarding tombstone**) is claimed in P2 as a general
engine-usability contribution. What remains **multi-writer-only and read-side** goes
to P3: the read-policy taxonomy (`load`/`load_optimistic`/`load_validate`/
`load_committed`, which exists only because a concurrent parker can be undecided),
guards, and the conflict/aging *declarations* that tune the escalation — the
validation a structure needs for a slot it *reads but does not write*. Under `sw`
these are provably dead. Hence P3 still follows P2.

**Same user in every paper.** Each paper presents the same consumer of the engine —
the bidirectional list and the hash list — as its worked example; the delta between
papers is the engine capability, not the structure. P1 shows the sw commit on them,
P2 the MW engine + freeze-on-free + tombstone, P3 the read-set validation — so a
reader watches one familiar structure gain each capability in turn.

**Evaluation is distributed, and P4 is comparative.** Each paper carries the
measurements that justify *its own* claims (P2 carries the throughput behind each
rejected alternative — [`SCOPE.md`](p2-sole-driver-mcas/SCOPE.md) DECISION #1). P4 is
then the *comprehensive comparative* study — against existence/RLU/MV-RLU, scaling,
tail latency — which does little defensively (hence last) but is the strongest
academic artifact. **Open fork:** P4 as a standalone comparative paper, vs. folding
the comparative study into the dcache application paper.

## Framing rule (do not soften)

The engine provides **atomic multi-slot writes with opt-in, per-slot read
validation**. It is *not* STM.

**Always "pseudo-transaction", never bare "transaction"** (use `\pseudotxn`).
The model is a transaction in the sense a *journaling filesystem* means it — an
atomic batch of writes made visible by a single commit record — not in the sense
STM means it. The descriptor is the journal; the status word is the commit
record. Filesystems have used "transaction" this way for decades without ever
meaning isolation; it is the database/STM sense that bundles isolation in. The
`pseudo-` prefix disambiguates for a concurrency audience that reads
"transaction" as ACID. It is not an apology: it marks what is deliberately
absent, and why — **isolation is paid for on the read side, and the RCU read
side is exactly what this engine refuses to charge.** The weakening is targeted,
not residual.

Bare "transaction" is fine only in proper nouns ("software transactional
memory", "transactional boosting") and when contrasting with the general notion.

- Never write "serializable" or "opacity".
- Keep "linearizable" scoped to the k-CAS write operation itself, never to a
  read+write pseudo-transaction. The defensible claim (Property 3, and the
  engine's own "this linearizes the *write*") is: **the commit is a linearizable
  write, with one linearization point at the commit step** — cite Herlihy & Wing
  1990. Two things are *also* true and worth saying so the scope is unmistakable:
  a single-slot read is itself linearizable (one atomic load), and a reader's
  multi-slot *traversal* is not one operation and has no linearization point at
  all. Never phrase it as "a committed pseudo-transaction is linearizable" — that
  reads as the whole read+write object and is the overclaim the prefix exists to
  prevent.
- A reader is **not** a transaction of any kind: each load resolves
  independently, so a traversal may straddle a commit. Write exactly that —
  **never "a reader is not a pseudo-transaction"**, which parses just as
  naturally as "not *merely* a pseudo-transaction (it gets a real one)", the
  exact inverse of the claim. The `\pseudotxn` macro makes this drift
  mechanical; it reached five places in P1 before being caught, and
  `check-terms` now greps for it.
- **"Isolation is a read-side cost" needs its precondition: *once you mutate in
  place*.** Unqualified it is false, and we say why ourselves: copy-on-write is
  one of RCU's three remedies, and a writer that path-copies and swaps a root
  gives readers a fully isolated snapshot at *zero* read-side cost — persistent
  data structures are the existence proof. The true claim is narrower and still
  enough: isolation is charged to the reader by designs that mutate in place,
  which is every design we compare against, ours included.
- **Do not say "per-slot linearizability"** — it undersells. Because the status
  word is written once and never back, a *dependency-chained* reader observes a
  monotone sequence: **old…old, new…new, never new-then-old**. A reader may lag
  a commit but never regresses across it. That is strictly more than per-slot
  independence and strictly less than a snapshot.
- **Do not say "causal"** — "causal consistency" is a specific model *weaker*
  than linearizability, and the collision would make the engine read as claiming
  less than it provides. Use "never new-then-old".
- The monotonicity caveat rides with the claim: the *selector's* monotonicity is
  unconditional, but what a reader's *sequence* inherits depends on dependency
  chaining. A non-chained reader under `-DURCU_DEREFERENCE_USE_VOLATILE` on
  weakly-ordered hardware owes itself an explicit acquire.
- Memory safety is unconditional. **Atomicity is conditional** on embedder
  contracts that are only opt-in checkable. Say so.

**Say "read-side critical section", not "read-side bracket".** It is the term
McKenney and the urcu source use ("Exit an RCU read-side critical section"); a
private synonym just makes the reader translate. Keep "bracket" for the
*writer's* `init..commit` transaction bracket, which is a different thing and is
what the engine's own docs call it. Note the distinction this buys in §3.4: a
reader *does* have a critical section — it keeps objects alive — but a critical
section is not a transaction, because it does not make the loads inside it a
unit.

**Read-side cost claims are about *loads*, not instructions.** The tag test is a
mask on a register plus one predicted branch: no load, but not free. Every
design in Table 1 branches — existence, RLU, MV-RLU, and this one — so the
branch is *not* where the comparison is decided, and implying otherwise is
unfair in our favour. What is ours alone is that the operand is already in a
register while everyone else must load theirs first. Say "no extra load", never
"charges the reader nothing".

**Do not append pledges of honesty to sentences.** "…and we say where", "…and we
say so", "…and we say what happens when it is not" — the paper *demonstrates*
that it names its costs; announcing it is weaker than doing it, and it reads as
defensive. Usually the pledge is redundant too: "the cost moves to the writer,
in the width of a commit, and we say where" had already said where. Either state
the fact (`silently commits stale pointers when it is not`), state the
convention impersonally (`properties that hold only under exclusion are marked
where they appear`), or just `\cref` the section that handles it. This is a
recurring tic, caught twice on review; bare "we" is fine where it does real work
("we describe", "we have not found", "this is why we say *pseudo-transaction*").

Overclaiming here is the single most damaging error available to this series —
it is what a reviewer punishes and what makes a defensive disclosure weaker,
not stronger.

## Building

```
make            # build all papers
make -C p1-sw-flip-latch          # one paper
make -C p1-sw-flip-latch draft    # with TODO/CITE/NOTE markers visible
make -C p1-sw-flip-latch arxiv    # arXiv submission tarball
```

### arXiv constraints baked into the build

- **pdflatex**, TeX Live 2025 — arXiv's default, and the same version installed
  locally, so local builds should reproduce on AutoTeX.
- **natbib + bibtex**, with the generated `.bbl` shipped. arXiv *does* run bib
  processing now, but a pre-generated `.bbl` removes a build variable, and
  biblatex's `.bbl` is version-locked to the biblatex/biber pair (TL2025 accepts
  only bbl format 3.3). natbib's is not.
- **No `..` paths in the submission.** AutoTeX unpacks into a single directory,
  so `\input{../common/preamble}` works locally and fails there. `make arxiv`
  flattens the tree, rewrites those paths, and compiles the staged copy before
  packing so breakage surfaces here rather than after upload.
- **pgfplots reads CSV directly**, so plot data ships inside the submission and
  figures are rebuildable from source with no external toolchain.

## Submission

- **Categories:** `cs.DC` primary, `cs.DS` secondary.
- **License:** CC BY 4.0.
- **Endorsement:** required — this is a first arXiv submission, and as of
  2026-01-21 automatic endorsement needs *both* an academic/research
  institutional email *and* prior arXiv authorship in the domain. Neither holds
  here, so a personal endorsement is required. CS is a single endorsement
  domain, so one endorsement covers `cs.DC` and `cs.DS`; only one positive
  endorsement is needed. Starting a submission generates the six-character
  endorsement code to pass to an endorser.

## Sources

Read-only references, not vendored:

- `/home/efficios/git/userspace-rcu-txn` — the engine. The large header block
  comments in `include/urcu/rcu-txn.h`, `rcu-mcas.h`, and `rcu-txn-sw.h` are the
  primary design documentation.
- `/home/efficios/git/efficios-trie-benchmark` — experiments.
- `/home/efficios/git/userspace-rcu` — Fractal Trie (deferred).

**Pin commits, not branches, in any Availability section.** For a defensive
publication the dated, specific artifact version *is* the deliverable.
