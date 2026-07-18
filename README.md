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
| 1 | `p1-sw-flip-latch/` | RCU pseudo-transactions + the single-writer flip-latch | **drafted, complete prose; pinned cefb0414** |
| 2 | `p2-sole-driver-mcas/` | Sole-driver MCAS: the multi-writer engine | not started |
| 3 | `p3-programming-model/` | Read policy, guards, conflict/aging, wrappers | not started |
| 4 | `p4-evaluation/` | Evaluation | not started |

**Candidate further papers** (queued, not scheduled):

- **DLM-style hybrid.** MW-txn for a per-node lock + tombstone, SW-txn for the
  structural changes under that lock, plus an optional seqcount. This is how the
  Fractal Trie reaches existence-like behaviour (commit width = number of
  *nodes*, not edges). A design document exists.
- **Dentry cache over rcu-txn.** The Linux dcache ported from kernel to
  userspace on the txn engine; experiment in
  `/home/efficios/git/efficios-trie-benchmark/experiment`.
  - *Candidate novelty (Mathieu's flag, framing his to finalize):* a **"host"
    vs "shell"** split that gives a dentry **inline names** *and* keeps a
    **stable address as node identity** (so no recompaction/relocation). The
    tension it resolves — as I understand it, to be confirmed — is that inline
    variable-length names normally force a node to move when the name changes,
    which would break address-as-identity; separating a fixed-identity host from
    a name-carrying shell decouples the two. No design doc yet
    (`design/rcu-txn-use-cases.md` only touches dentry in passing).
- **Wait-free multi-word snapshot via a single-bit GP-gated seqcount latch**
  (suspected novel; reserved). A one-bit seqcount whose flips are gated to one
  per grace period per node, with a copy-on-write overflow escape, makes a
  torn-free multi-word read *also* wait-free (≤ 1 retry, constant in writer
  count). Design in `efficios-trie-benchmark/design/rcu-txn-blob.md`
  ("Single-bit latch"). **Deliberately kept out of P1** — a full enabling
  disclosure is stronger prior art than a hint, and P1 stays neutral on read-side
  progress class (§7.4). Could stand alone or anchor the DLM-hybrid paper.

The Fractal Trie proper is **deferred** — work still heavily in progress.

**Order rationale.** Single-writer comes first: it is the simpler mechanism, it
establishes the record/status/commit vocabulary the multi-writer paper reuses,
and it makes P1 short. That matters because the first submission is the one
arXiv moderators use to size up a new account.

The programming model does not split evenly between the engines. As of
cefb0414, **read-your-own-writes and disjoint declarations are shared** — the sw
engine gained both, so P1 demonstrates them and P3 will not have to introduce
them from scratch. What remains **multi-writer only**: the full read policy (the
`load`/`load_optimistic`/`load_validate`/`load_committed` distinction, which
exists because a concurrent parker can be undecided), guards, conflict/aging,
and the abort lane — under `sw` these are provably dead. Hence P3 still follows
P2.

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
