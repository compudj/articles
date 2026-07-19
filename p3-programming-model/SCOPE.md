# P3 — Read-Side Programming Model: scope (living capture)

Status: **scoping — early.** Claims articulated + SoA'd (2026-07-18); prose not started.
Engine source: `userspace-rcu-txn` `include/urcu/rcu-txn.h` (front-end read policy),
HEAD `f07b6df0`. Depends on P2 (`p2-sole-driver-mcas/SCOPE.md`).

---

## Thesis (honest version, post-SoA)

P3 is the **read-side** programming model — the complement to P2's write-side atomicity.
Stance: **read-side validation is opt-in and à la carte.** The base engine keeps NO read-set
(a commit validates only its write-set: each written slot `== old` at install); unguarded
reads are plain, barrier-free RCU loads; a structure pays for read validation only on the
specific *unwritten* slots whose stability its correctness needs.

**Novelty is SUBSTRATE, not idea (SoA verdict).** Selective / programmer-directed read
validation is a mature STM subfield (early release, elastic transactions, consistency-
oblivious programming, view transactions). *No P3 claim is novel as an idea.* What is
unoccupied is the *realization*: doing it on a **read-barrier-free RCU-MCAS base** where the
default read carries **no metadata**, validation **added opt-in per slot** (not relaxed *out*
of an instrumented read set), folded into a **k-CAS commit's conflict set**. **Reframe every
claim to claim the realization, not the concept.** For a defensive publication this is fine —
the enabling disclosure of the specific realization is the deliverable; idea-novelty is not
the bar.

---

## The claims (reframed per SoA)

**P3-1 — À-la-carte read-set validation on a barrier-free RCU base (HEADLINE).**
Verdict: **partially anticipated.** Claim the *substrate + opt-in direction*, NOT selectivity.
The default read is an ordinary RCU load with no version metadata; validation is *added* per
slot by folding one read into the commit's k-CAS conflict set — the inverse of *relaxing*
reads out of an instrumented read set. Granularity is **per-slot opt-in** (vs elastic's
per-*transaction*, early release's per-*object* opt-out) — state that explicitly.
Closest prior art: elastic transactions (Felber–Gramoli–Guerraoui, DISC 2009); early release
(DSTM, *in bib*); COP (Afek–Avni–Shavit, OPODIS 2011); view transactions (Afek–Morrison–Tzafrir).

**P3-2 — Read policy: stabilize-iff-you'll-act vs resolve-immediately; static call-sequence
property; the bounded-wait NEVER helps.** Verdict: **partially anticipated / modest
articulation.** Concede logical-old resolution + the navigation/act distinction are known
(early release, elastic; Bronson/Heller optimistic traversal). Claim the **no-helping
bounded-wait** — Harris–Fraser–Pratt's descriptor reader *helps* (mandatory `CASNRead` loop);
ours resolves-or-waits, never drives — and the **static checkability** as the novel articulation.
(Reinforces P2's total-no-helping story.)

**P3-3 — Guards as visible reads that validate AND serialize.** Verdict: **well-known** —
semi-visible reads (SkySTM/SNZI), visible reads (RSTM). Adopt-and-cite, do NOT headline. Only
defensible twist: **mechanism unification** — the visible read uses the *same descriptor-parking
primitive* as the k-CAS writes.

**P3-4 — Cross-structure atomic composition via `*_prepare` + RYW chaining.** Verdict:
**known-goal, narrow.** Concede STM composes trivially, and Composable Memory Transactions
(Harris et al. 2005) is a *different* axis (retry/orElse). Claim only the **discipline on a
non-STM RCU-MCAS base**: fold multi-structure edits into one k-CAS / one linearization point,
with RYW chaining across prepares, readers staying plain RCU. Consistency-model half → P2.

---

## Biggest overclaim risk + the defusing sentence (put IN the paper)

**P3-1 vs the relaxed-consistency-checks lineage.** Sharpest matches: **view transactions**
("critical view" = opt-in subset of reads to validate — almost verbatim) and **COP**
(uninstrumented navigation + validate at the mutation point). A reviewer WILL cite these and
ask *"how is opt-in per-slot guarding not a critical view on an RCU base?"* — the answer must
be in the paper, not found at rebuttal:

> Selective, programmer-directed read validation for traversal is well established (early
> release, elastic transactions, consistency-oblivious programming, view transactions). Our
> contribution is not selectivity but its **substrate**: on a read-barrier-free RCU-MCAS base
> the default read is an ordinary RCU load carrying **no version metadata**, and validation is
> added **opt-in per slot** by folding a single read into the commit's k-CAS conflict set —
> the inverse of relaxing reads **out** of an otherwise-instrumented read set.

The line that survives every comparison: every STM relaxation above still *instruments the
reads it keeps* (elastic's ver-val-ver; view's multiversion light read; early release's
validate-until-released). P3's unguarded read is a plain RCU load — no version, no clock, no
per-read check.

---

## The read-side programming model (content; corrected vocabulary)

- **Read policy** (stabilize vs resolve-immediately — **NOT** "help vs optimistic"; a load
  never drives a parker, see P2 SCOPE): `load` (RYW default; bounded-waits an undecided owner
  for a stable value, else falls back to logical-old), `load_optimistic` (resolve to
  logical-old immediately; navigation), `load_committed` (ignore own buffered writes). Rule:
  **stabilize iff the value enters the read/write set.**
- **Guards = opt-in read-set validation:** `load_validate` / `validate` fold a read into the
  conflict set (+ park a proxy → also serialize the guarded word).
- **Declarations:** `declare_disjoint` (distinct-slot fast path), `reserve` (pre-size), the
  aging→fair-mutex escalation (bounded-blocking → starvation-free) from the programmer's side.
- **Composition:** `*_prepare` + RYW chaining; traversal-composed edits.

---

## The read-side snapshot menu — validating read vs. version (Arm A, 2026-07-19)

P3 is the read-side *programming model*, so it presents the full menu of read-side
consistency tools and when to reach for each — which is what lifts it past a bare
guard paper. Two tools sit on **orthogonal axes** (composition scope × progress class):

- **Validating read** (P3's contribution, P3-1): fold a read into the commit's k-CAS
  conflict set (`load_validate`). *Composes a snapshot across structures*, opt-in per
  slot — but parks a proxy, contends, and is **not wait-free**.
- **Version-based snapshot** (GP-bounded seqcount / wait-free 1-bit latch): *single
  structure only*, but can be made **wait-free** (≤ 1 retry, constant in writer count).
  Source: `efficios-trie-benchmark/design/rcu-gp-bounded-version.md` (extracted from
  `rcu-txn-blob.md`).

The distinction P3 states (from that doc): *the validating transaction is the only one
that composes a snapshot across other structures; every version-based row snapshots one
structure alone — that, not progress class, is the reason to reach for it.* This is also
P3's honest boundary: for a wait-free single-structure snapshot, do NOT use P3's guards
(they park proxies and contend) — use a version.

**Scope split (Arm A, 2026-07-19).** The **wait-free GP-gated 1-bit latch folds into the
DLM-hybrid paper, not P3**, because its clean parity form needs per-node write
serialization = the DLM per-node lock (the SW flip-latch acts as the version selector;
under plain MW you'd need the messier enter/exit concurrent form). So P3 **carries the
menu / taxonomy** (composition-scope × progress-class) and the general version discussion
as positioning + boundary, and **forward-references DLM** for the wait-free construction.
P3 claims neither the version mechanism nor the latch. The version-on-payload
**demonstrator** (extend the same-user hlist node with a multi-word payload) lives in
**DLM**; P3's demonstrator stays the hlist **links** (the back-edge guard). A **SoA /
novelty review** on the latch travels to DLM before any hard claim. This resolves
open-question #2 (P3 thin-vs-merge) in the *keep P3 lean after P2, strengthen DLM*
direction — P2's `next paper` forward-refs stay valid.

## DEMONSTRATOR — decided (2026-07-18): the same hlist; guards are the back-edge dual

The same-user convention holds fully across P3 — **no richer structure is needed for guards.**
Grounded in source: `list.h`, `hlist.h`, and `skiplist.h` all use `load_validate`. In the
**bidirectional hlist** the guard has a clean, minimal role: an insert/delete writes a
neighbour's **back-edge** (`succ->pprev` / `next->pprev`) but does NOT write that neighbour's
`next`. A concurrent `del(succ)` marks `succ->next` (the freeze-on-free tombstone) and frees
succ. The forward write-old serializes only the forward chain; the back-edge write's
precondition — *succ is still live* — rides on a **disjoint slot** (`succ->next`) the op
**reads but does not write**. So it `load_validate`s `succ->next` (checking the mark), folding
exactly that one read into the k-CAS conflict set (`rcu-txn-hlist.h`: "the load-validate of
succ->next … exists ONLY to guard the pprev write").

This is the à-la-carte thesis (P3-1) made concrete: **one** slot guarded, for the back-edge's
liveness precondition; the rest of the traversal stays plain RCU reads. And it ties P3's
headline mechanism straight back to the series' founding motivation — the **bidirectional /
reverse-walk** P1's intro opens on: the forward edge is *write*-validated, the back edge is
*read*-validated. Same two-chain coherence, now on the read side.

- **hlist** (same user): read policy (the stabilize-vs-optimistic case) + guards (the pprev
  back-edge liveness guard) + `declare_disjoint` (distinct buckets).
- **skiplist** (optional add): the ordered/multi-level case — the +8.2% read-policy result and
  multi-`prepare`/one-commit composition; guards on the successor. Add for the ordered story,
  not because guards require it.

---

## Boundaries

- **Follows P2** (needs the engine + tombstone). **Reuses P1** (RYW + disjoint, shared).
- **P2 pre-introduces ONE guard** (decided, 2026-07-18; P2 DECISION #5): the bidirectional back-edge
  (`succ->pprev`) write forces a single `load_validate(succ->next)` to make P2's own flagship
  example correct under MW, so a *minimal, functional* guard lands in P2 (like freeze-on-free).
  P3 **generalizes** it into the à-la-carte read-set-validation facility (P3-1) + the SoA
  positioning; P3-1's *substrate* novelty is unaffected — P2 merely uses one instance.
- **MW-only:** every mechanism exists because a parker can be UNDECIDED — provably dead under sw.

---

## Must-cite (SoA, beyond the series bibliography)

- **Elastic transactions** — Felber–Gramoli–Guerraoui, DISC 2009 (closest to P3-1).
- **SwissTM / "Stretching TM"** — Dragojević–Guerraoui–Kapałka, PLDI 2009 (invisible reads; opacity baseline).
- **COP** — Afek–Avni–Shavit, OPODIS 2011 (uninstrumented traversal + checkpoint).
- **View transactions** — Afek–Morrison–Tzafrir, WTTM 2010 (*verify venue/year — workshop / brief announcement*).
- **SkySTM "Anatomy"** — Lev–Luchangco–Marathe–Moir–Nussbaum–Olszewski, TRANSACT 2009 (*workshop*; semi-visible reads — closest to P3-3).
- **Bronson–Casper–Chafi–Olukotun**, Practical Concurrent BST, PPoPP 2010 (optimistic traversal validation — P3-2).
- **Composable Memory Transactions** — Harris–Marlow–Peyton Jones–Herlihy, PPoPP 2005 (P3-4 baseline; *different* axis).
- **TL2** — Dice–Shalev–Shavit, DISC 2006 (write-buffering RYW — P3-4).
- **Citrus** — Arbel–Attiya, PODC 2014 (RCU reader baseline: *no* read validation — positions what P3 adds over plain RCU).
- Optional: ASTM (Marathe–Scherer–Scott, DISC 2005); lazy list (Heller et al., OPODIS 2005). Early release = DSTM (*already in bib*), invoke by name.
- **Verify-before-cite:** view-transactions venue/year; all page numbers via DBLP.

---

## OPEN QUESTIONS

1. **RESOLVED (2026-07-18) — see DEMONSTRATOR.** The same-user hlist already uses guards (the
   pprev back-edge liveness guard); no richer structure needed. Skiplist optional, for the
   ordered read-policy/composition story only.
2. **RESOLVED (Arm A, 2026-07-19).** P3's novelty is substrate-level, not idea-level —
   thinner than P2. Considered folding the wait-free 1-bit latch in to strengthen it;
   decided **against** because the latch needs the DLM per-node lock (it belongs in DLM,
   not a pre-DLM P3). Resolution: **keep P3 lean and right after P2** (guards / validation
   / read policy on the hlist links), grow it past a bare guard paper with the **read-side
   snapshot menu** (positioning + boundary vs. the version-based snapshot), and
   forward-ref DLM for the wait-free construction. Latch + version-on-payload demonstrator
   → DLM. P3 stays defensively complete (discloses the barrier-free-RCU opt-in-per-slot
   realization) without over-reaching on academic novelty. See the read-side-snapshot-menu
   section above.
