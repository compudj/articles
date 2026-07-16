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
| 1 | `p1-sw-flip-latch/` | RCU pseudo-transactions + the single-writer flip-latch | skeleton |
| 2 | `p2-sole-driver-mcas/` | Sole-driver MCAS: the multi-writer engine | not started |
| 3 | `p3-programming-model/` | Read policy, RYW chaining, declarations, wrappers | not started |
| 4 | `p4-evaluation/` | Evaluation | not started |

The Fractal Trie is **deferred** — work still heavily in progress.

**Order rationale.** Single-writer comes first: it is the simpler mechanism, it
establishes the record/status/commit vocabulary the multi-writer paper reuses,
and it makes P1 short. That matters because the first submission is the one
arXiv moderators use to size up a new account.

The programming model does not split evenly between the engines: read policy,
RYW chaining, guards, declarations, conflict/aging, and the abort lane are all
**multi-writer only** — under `sw` they are provably dead. Hence P3 follows P2.

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
  read+write pseudo-transaction.
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
