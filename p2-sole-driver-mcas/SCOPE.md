# P2 — Sole-Driver MCAS: scope (living capture)

Working scope for the multi-writer engine paper. Status: **scoping in progress.**
Not prose; a stable artifact to push on. Open questions at the bottom.

Engine source of record: `userspace-rcu-txn` `include/urcu/rcu-mcas.h`
(+ `rcu-txn.h` front-end), HEAD `f07b6df0`. Pin the exact commit at draft time.

---

## Thesis

The sole-driver MCAS is a deliberate choice of **synchronization coarseness** —
coarse enough to stay simple, portable, and cache-friendly; fine enough to stay
parallelizable. Its progress class (**bounded-blocking**) is a *tail-latency*
property knowingly traded for *throughput*, not a failure to reach lock-freedom.

Same DNA as P1. P1 refused to overclaim the **consistency** model
(pseudo-transaction, not STM). P2 refuses to overclaim the **progress** class
(bounded-blocking, and here is why that is the right target). It states what it
gives up and argues the trade; it does not apologize.

The causal chain *is* the argument, and it is **measured, not hypothesized** — the
helping design was built, then replaced:

> Helping co-installs proxies (owner + helpers race to install each record), so
> install-ABA forced a per-record **FREE/BUSY/DONE** state machine — a per-record
> spinlatch. That *already* made helping bounded-blocking: helping never bought true
> lock-freedom, it bought a *more complex* bounded-blocking engine that lost on
> throughput (hot-CL traffic on the per-record machine, wasted helper work). Drop the
> helpers → **sole-driver** → no co-installer, so install-ABA cannot occur, the
> per-record install spinlatch vanishes, and the only residual wait is the coarse,
> per-*transaction* settle-wait. Coarser synchronization, fewer points, less hot-CL
> traffic — and it wins measured throughput.

---

## What P2 is — the engine mechanism (contribution list)

- **Sole-driver / single-driver discipline.** A transaction is driven only by its
  owner: no helping, no stealing. A thread tripping over an in-flight proxy
  bounded-waits for the owner to settle, then escalates (abort + retry at rising
  aging priority, ultimately the front-end fair-mutex). **No-helping is TOTAL — even
  reads:** a load never drives a foreign transaction (`urcu_mcas_read`'s own comment:
  *"Never drive E"*); it resolves a *decided* proxy, or bounded-waits the owner and
  falls back to the logical old. State this outright — it closes the "but your read
  policy helps" objection a careful reviewer (or Paul) would raise, and strengthens §2's
  no-RDCSS centerpiece: no foreign *installer*, and no foreign *driver* of any kind.
- **Tri-state status + descriptor-naming CAS.** UNDECIDED → SUCCEEDED (commit) /
  FAILED (abort); every slot transition is a descriptor-naming CAS; resolution
  goes through the status word, so a slot's plain value is never load-bearing.
- **⛔ SUPERSEDED 2026-10-03 — "no RDCSS" is NOT ours; see the section of that date
  at the end of this file. The bullet below is kept for the record only.**
  ~~No RDCSS — the CENTERPIECE engine claim (strongest novelty).~~ Plain value-CAS
  install is A-B-A-safe *by construction* under one driver — the classic re-plant A-B-A
  needs a foreign driver of your records, which the regime excludes. Linchpin: Guerraoui
  et al. (DISC 2020) tie RDCSS's whole purpose to *helping* ("provided the operation was
  not completed by a helping thread") — so removing helping makes RDCSS unnecessary.
  Frame as applied ownership logic (Israeli–Rappoport, PODC 1994), not a new primitive.
  Apparently unpublished. See ENGINE-CLAIMS LEDGER §2.
- **Owner-only settle → refcount-free reclamation POINT (not the reclamation scheme).**
  No foreign thread plants, drives, or steals a txn's records, so after settle no proxy
  names any slot. **Do NOT claim "reclaim descriptors via RCU"** — that is prior art
  (Arbel-Raviv–Brown's *named, benchmarked* RCU baseline, DISC 2017, over the author's own
  liburcu). Claim ONLY the sole-driver reachability property: terminal-and-settled is a
  *refcount-free* `call_rcu` point because nothing foreign can resurrect the records.
  HIGH overclaim risk — see ENGINE-CLAIMS LEDGER §5.
- **Deadlock-freedom by construction.** Records install in one global order
  (sorted by slot address at age ≥ 1; age-0 installs flat and bails at the first
  foreign proxy), so a committer holds only lower slots while waiting on a shared
  one.
- **Progress: bounded-blocking, adaptive coarseness.** Optimistic fine-grained by
  default; under aging pressure a handle escalates into a per-domain fair-mutex
  (MCS) lane whose budget scales with op cost. The engine *tunes* coarseness
  dynamically rather than committing to one point.
- **RSEQ time-slice extension — design lever, NOT yet in the test tree.**
  Preemption-*avoidance* for the preempted-owner tail: the driver defers preemption
  for a bounded window across the install→settle section, reaching settle before it
  is taken off-CPU — turning the worst-case tail from *bounded* into *rare*. Present
  it as the mechanism the bounded-blocking choice is designed to compose with, **not
  a measured result**: it is unimplemented in the test tree today, so the current
  throughput numbers are the pessimistic case *without* it — unclaimed upside, not a
  claim. **Correctness does not depend on it** (best-effort, bounded, not on every
  kernel); the aging→fair-mutex fallback carries the residual. **Claim boundary (Mathieu,
  2026-07-18):** nothing on the *mechanism* (the mainline rseq time-slice-extension series,
  Gleixner 2025, which the author took part in). The claim is the userspace **use for this
  specific purpose** — deferring preemption across the sole-driver install→settle window —
  *disclosed* as defensive prior art, plus the engine-level **observation** that it thins
  the preempted-owner tail from *bounded* to *rare*, which is what makes bounded-blocking
  practically competitive (ties to the coarseness thesis). Caveat: the *use pattern* itself
  (defer preemption of a critical-section holder so waiters don't stall) is textbook — cite
  the deferral lineage (schedctl; temporary non-preemption; scheduler-conscious sync),
  **do not claim the pattern.** What is *not obviously anticipated* (not "novel"): applying
  it to a **publish window of a bounded-blocking MCAS** rather than a mutex holder.
  Precision point: classic rseq (2018) *restarts* on preemption; TSE *defers* it — opposite.
  See ENGINE-CLAIMS LEDGER §6.
- **The RCU-forwarding tombstone — freeze-on-free primitive; CLAIMED as a COMPOSITION.**
  Per-slot atomicity is not operation atomicity, so *every* MW structure on the engine
  needs freeze-on-free to be usable. A removed pointer keeps the engine's **own descriptor
  proxy** in the slot as a grace-period-lifetime tombstone that (i) resolves to the **old**
  target, so a pre-existing RCU reader completes a linearizable pre-removal traversal of
  the still-live detached region, and (ii) is not the racing writer's expected plain
  pointer, so its disjoint-word CAS fails and it re-descends — reusing the existing
  descriptor-resolution read path, so readers get **no new code path**. No single
  ingredient is novel (related-work check, 2026-07-18); the claim is the **four-way
  composition** — lock-free + multi-writer + MCAS-descriptor-as-mark + RCU-grace lifetime
  — and it MUST carry a one-sentence distinction from GC relocation barriers (forwards to
  *old* / deletion / writer-*fails*, vs GC's to-new / relocation / writer-fixup). General
  to the engine ⇒ introduced here on the list/hlist user; only the wide-node packing is FT-specific.
- **Constraints (vs the SW flip-latch).** Engine owns tag bit 0 (2-byte alignment);
  record set frozen at commit; pairwise-distinct slots per txn.

---

## The coarseness thesis (the paper's spine)

1. **Install-ABA is helper-induced.** It arises only when threads *co-install* a
   txn's records (helping). The helping design paid for it with a per-record
   FREE/BUSY/DONE install spinlatch — which made helping bounded-blocking anyway, so
   lock-freedom was never actually on the table there.
2. **Sole-driver dissolves the hazard, not merely fixes it.** One installer per txn
   ⇒ no co-install ⇒ no install-ABA ⇒ no per-record install latch. The residual
   blocking is coarse (per-*transaction* settle-wait), not per-record.
3. **Why not DCAS/RDCSS.** The classic multi-installer fix for install-ABA, rejected
   before sole-driver made it moot: less portable, inconvenient to wire into existing
   structures, wastes hot cache-line budget. Sole-driver removes the need entirely.
4. **Adaptive coarseness.** Fine-grained optimistic default → coarse serial lane
   under contention; the escalation budget scales with op cost (front-end header).
5. **Preemption: avoid, don't tolerate.** Lock-free *tolerates* preemption at
   standing cost; sole-driver + RSEQ-TSE *avoids* it for the common case at ~zero
   cost, with the fallback for the rest. (RSEQ-TSE is a design lever, not yet in the
   test tree — so the measured throughput already wins *without* it; it is future
   tail upside.)

---

## Variations & Alternatives — LOAD-BEARING (implemented & measured, rejected)

Each was built and benchmarked, then rejected for throughput/practicality. This is
the strongest part of the paper: a *measured* design-space map, and — because
disclosing an implemented-then-rejected approach still enables it as prior art —
defensive coverage of the alternatives for free.

| Alternative (implemented, rejected) | Why rejected |
|---|---|
| **Helping** (owner + helpers co-install each record) | forced a per-record FREE/BUSY/DONE install spinlatch → bounded-blocking anyway; hot-CL traffic + wasted helper work; lost on throughput |
| **Abort-others** (committer aborts foreign txns in its path vs. waiting) | throughput. *Antecedent:* obstruction-free STM contention management — DSTM "Aggressive" (PODC 2003, *in P1*); Scherer–Scott (PODC 2005) ← wound-wait (1978) |
| **Txn-age tracking as resolution** (resolve slots by age/version, not status) | throughput; + the "age-as-resolution can't validate out-of-commit" trap. *Antecedent:* DSTM "Timestamp" manager / wound-wait / timestamp-ordering — **not** TL2/LSA (those are version-as-*validity*). Same lineage as abort-others. |
| **DCAS/RDCSS for install-ABA** | portability; integration friction; hot-CL budget |
| **Pure lock-freedom** (no bounded wait) | unreachable once co-install forced the per-record install latch; its only prize (preemption-immunity) comes cheaper via RSEQ-TSE |

Each row carries the decisive **throughput** measurement that justifies the
rejection (DECISION #1) — that measurement is the sole evaluation content P2 carries;
broader scaling/latency studies → P4.

---

## Limitations / what is NOT guaranteed (P1-style honesty)

- **Per-slot atomicity ≠ operation atomicity.** Disjoint-word structural races
  survive (delete-B vs. insert-after-B: both CAS *different* words, both succeed →
  lost node + UAF). This is the raw engine's boundary, and it is **why freeze-on-free
  is not optional** — a *usable* MW list needs it, so it appears in P2, not deferred.
  The fix is prior art (Harris marked-pointer deletion; EFRvB; Natarajan–Mittal): the
  remover marks the freed node's own `next` — the word the inserter would CAS — so the
  racing insert's expected-value CAS fails and it re-descends; the engine's proxy
  encoding supplies the mark (readers already mask it). The mark-and-retry base *and*
  the forwarding-through-a-mark mechanism are both prior art (the latter is GC
  relocation — Brooks / Sapphire / ZGC / Shenandoah — and Bronson's routing node); what
  P2 claims is their **composition** with an MCAS descriptor and an RCU-grace lifetime
  (DECISION #4) — general to every MW structure on the engine, so it belongs here, not in
  the FT paper. Only the wide-node *packing* (unified proxy/tombstone/`nr_child` state
  word, recompact-on-insert) is FT-specific.
- **Progress is bounded-blocking, not lock-free.** "Bounded-blocking" is *our*
  descriptive term (not an established class): the engine **waits** on a foreign owner, so
  it is **blocking and technically NOT obstruction-free** — but the FIFO-fair MCS
  escalation makes it **starvation-free** (stronger than deadlock-free) under a fair
  scheduler. Claim *that*, cited (Herlihy–Shavit taxonomy). Correctness is independent of
  RSEQ-TSE. See ENGINE-CLAIMS LEDGER §7.
- **Value-CAS atomicity.** A record is validated to hold its old at the
  linearization point, not to have been stable throughout; snapshot/version
  semantics are layered on top. Memory safety holds unconditionally.

---

## Boundaries (what P2 reuses / defers)

- **Reuse from P1:** the pseudo-transaction model, record/status/commit vocabulary,
  the tag scheme, and read-your-own-writes + disjoint declarations (now shared).
- **Defer to P3 (programming model):** the read-policy API
  (`load` / `load_optimistic` / `load_validate` / `load_committed`, which exists
  because a parker can be UNDECIDED), guards, and conflict/aging *declarations* —
  demonstrated on the *same* list/hlist user. **Not deferred:** freeze-on-free (needed
  to make P2's own example usable — DECISION #3) and the user structures themselves
  (each paper carries the same user as its practical example; the delta between papers
  is the engine capability, not the structure).
  - **The ONE back-edge guard is NOT deferred — DECISION #5 (Mathieu, 2026-07-18;
    PREMISE REVISED 2026-07-31).** The **conclusion stands unchanged**: introduce the
    guard **minimally in P2** (functional only — "fold this read into the commit's
    conflict set; commit fails if `succ` was deleted"), as the **read-side companion to
    the tombstone**, resolved the same way as freeze-on-free. Symmetry: forward edge
    *write*-validated, back edge *read*-validated. The *general* read-side model
    (read-policy taxonomy, à-la-carte guards + SoA, declarations, composition) stays in
    P3; P2's one guard is P3's on-ramp, and P2 must NOT claim the à-la-carte novelty
    (that is P3-1). Rejected alternative: a forward-only P2 example — regresses from P1
    and guts the tombstone's motivation. Source phrasing still holds: the
    `load_validate` "exists ONLY to guard the pprev write."

    **The original premise was wrong; do not restate it.** Superseded text, kept for the
    record: ~~"under MW its back-edge write (`succ->pprev`) has a read-side precondition —
    succ still live — on a **disjoint** slot (`succ->next`) it reads but does not write …
    Without it P2's own flagship example is not correct under MW → a forward dependency on
    P3."~~ That slot is **not disjoint from the write set**, and there is **no forward
    dependency on P3 for correctness**.

    *Derivation (against `rcu-txn-list.h` / `rcu-txn-hlist.h`, 2026-07-31).* `del(succ)`
    is a 3-edge commit whose **forward-unlink edge is `&pos->next: succ → succ_next`** —
    the same slot `insert_after(pos)` writes with the same expected old value `succ`.
    (Mirror for `insert_before(pos)`: it and `del(pos)` both name `&prev->next` with old
    `pos`; for the hlist, `*succ->pprev` **is** `&pos->next`.) So an unguarded insert
    always fails its old-value check there, and **no interleaving lets it COMMIT against
    a deleted successor**. The engine says so itself in `insert_after_prepare`: the guard
    makes "the pprev side serialize against del(succ) **exactly as @slot does**" — i.e.
    `@slot`/`&pos->next` is the *durable* serializer; the guard is *early* serialization.

    *What the guard actually buys — use these three, not the old premise.*
    **(a) The `-EAGAIN` vs `-ENOENT` termination protocol** ("a neighbour moved, re-read
    and proceed" vs "my anchor is gone, give up"). This is the half nothing else
    supplies. **(b) Deterministic early abort.** The back-edge write lands *inside* the
    dying node (`&succ->prev`), and the guard slot `&succ->next` sits in that same node
    at a **lower offset** (`struct { next, prev; }`), so the guard is reached before the
    back-edge install under **both** install regimes — slot-sorted at age ≥ 1, caller
    order at age 0. Without it, whether the abort precedes that write depends on the
    relative addresses of the predecessor node and the dying node, i.e. **on the
    allocator**. **(c)** Defence for the window **widened by composition** (a composing
    structure's foreign slots sitting between the two addresses).

    *Failure mode without the guard — all legal, none a correctness break.* A transient
    proxy planted in the dying node, plus the aborting transaction's settle store landing
    there later. Readers are unaffected: they resolve the proxy to its **logical old**
    value, which is exactly what a ghost's own pointers must keep saying. The node cannot
    be freed underneath it, because the whole attempt runs inside one RCU read-side
    section. The one thing that *would* break it — re-linking the node within a grace
    period — is what `sec:reclaim` already forbids.

    *Two guard SKIPS are load-bearing, not optimizations.* `insert_before` skips the
    validate when `prev == pos` (the immortal empty-list sentinel, where `&prev->next`
    **is** `&pos->next`, already written and serialized). `del_prepare` /
    `replace_prepare` skip it when `next == prev`, where recording it would put two
    records on one slot with **different expected-olds** — the per-slot reconcile merges
    them into a bogus record under `-DNDEBUG` and commits a marked-but-still-linked node.

    *Recorded in the paper:* `sec:guard` is rewritten to the engine's framing, with the
    derivation preserved in a drafting NOTE beside it so this is not reverted by someone
    reading SCOPE alone (commit `20cd31a`).
  - **P3 vocabulary caveat (verified in code, 2026-07-18):** the read policy is
    *stabilize (bounded-wait) vs. resolve-immediately*, **NOT** "help vs. optimistic."
    A load never helps/drives a parker (see the sole-driver bullet); the source header's
    "helping load … pays the parker's install" wording is *stale helping-era* language
    (`urcu_mcas_read` now only bounded-waits the owner, else falls back to the logical
    old). The rule reframed: take the **stabilizing** read iff you will act on the value
    (store / validate it), the **optimistic** read for pure navigation — rationale
    unchanged (an optimistic old on a slot you will store is doomed-if-the-parker-commits).
    Reframe this vocabulary when P3 is scoped.
- **Defer to P4 (evaluation):** the full comparative/scaling/tail-latency suite.
  P2 carries *only* the throughput that justifies each design choice (DECISION #1).

---

## DECISIONS

1. **P2 evaluation = only the throughput that justifies the choices** (Mathieu,
   2026-07-18). P2 carries the decisive throughput number behind each rejected
   alternative and each progress-class choice — nothing broader. Full comparative,
   scaling, and tail-latency studies → P4.

2. **The per-record spinlatch is historical (helping-era), not current** (Mathieu,
   2026-07-18). The FREE/BUSY/DONE per-record install spinlatch belonged to the prior
   helping/abort-others engine, where co-installing helpers created install-ABA.
   Sole-driver has no co-installer, so the current engine needs *no* per-record
   install latch (the header's "no install latch needed" = the current engine). The
   only bounded wait now is the coarse, per-txn cross-transaction settle-wait
   (proxy-as-spinlatch). The historical spinlatch is the empirical hinge of the
   coarseness thesis — recount it as the design that was measured and dropped, not as
   a current mechanism.

3. **Same user per paper; freeze-on-free lives in P2** (Mathieu, 2026-07-18).
   Resolves the wrapper question. Series convention: *each paper presents a concrete
   user of the engine as its practical example, and it is the same user (list, hlist)
   across papers* — so the paper-to-paper delta is exactly the engine capability being
   added. P2 shows P1's list/hlist under the MW engine, **including** freeze-on-free,
   because that is what makes a concurrent list actually usable (it must survive the
   delete/insert disjoint-word race). Its mark-and-retry base is cited prior art
   (Harris mark-on-delete); the RCU-forwarding delta is claimed here (DECISION #4). Not
   P3's job either way.

4. **Claim the RCU-forwarding tombstone in P2, not the FT paper** (Mathieu,
   2026-07-18). It is needed by *every* MW data structure on the engine, so it is a
   general engine-usability contribution and must be presented at first use (P2), not
   deferred to a late application paper. Claim scope: cite mark-and-retry as prior art
   (Harris; EFRvB; Natarajan–Mittal); claim the RCU-*forwarding* requirement (readers
   resolve through the mark to the RCU-live pre-mutation view, no helping) plus the
   reuse of the engine's proxy encoding (reader path unchanged) as the delta. Wide-node
   packing stays FT-specific. Due diligence: a related-work check on RCU + marked
   deletion before hard-claiming (anti-overclaim discipline — TODO #2).

   **REFINED (related-work check, 2026-07-18):** verdict *partially anticipated* — so
   claim the **composition**, not the forwarding mark as a new primitive. The
   forwarding-through-a-mark *mechanism* is prior art (concurrent relocating GC: Brooks
   1984, Sapphire 2001, ZGC, Shenandoah; and Bronson's routing node, PPoPP 2010);
   old-version reads are RCU/RLU/MVCC. What is unpublished is the four-way synthesis
   (lock-free + MW + MCAS-descriptor-as-tombstone + RCU-grace lifetime, no new reader
   path). Add one sentence distinguishing GC relocation (to-new / relocation /
   writer-fixup) from this (to-old / deletion / writer-fail). Base citations gain
   **LLX/SCX "finalize"** (Brown–Ellen–Ruppert, PODC 2013 — the closest freeze-on-free
   primitive) and **MCAS descriptor resolution** (Harris–Fraser–Pratt, DISC 2002 — the
   reader machinery reused). Full ledger below.

5. **Back-edge guard lands in P2, not P3** (Mathieu, 2026-07-18; **premise revised
   2026-07-31**). P2's bidirectional flagship carries one `load_validate(succ->next)` to
   guard the `pprev` write, so a minimal, functional guard is introduced in P2 — the
   read-side companion to the tombstone (forward edge write-validated, back edge
   read-validated), same logic as freeze-on-free. The *general* read-side model stays P3;
   P2 does not claim the à-la-carte novelty (P3-1). **The guard is not
   correctness-load-bearing** — `&pos->next` serializes the insert against `del(succ)`
   with or without it — so it earns its place on the termination protocol, deterministic
   early abort, and composition, NOT on "the example is broken without it." See the
   boundaries note for the derivation.

---

## RELATED WORK LEDGER (tombstone claim)

From the related-work check (2026-07-18). **Base** — cite, not claimed novel:
- Harris, *A Pragmatic Implementation of Non-Blocking Linked-Lists*, DISC 2001 — marked-pointer logical deletion.
- Ellen, Fatourou, Ruppert, van Breugel, *Non-blocking Binary Search Trees*, PODC 2010 — flag/mark via Info records.
- Natarajan & Mittal, *Fast Concurrent Lock-Free BSTs*, PPoPP 2014 — edge marking.
- Fraser, *Practical Lock-Freedom*, Cambridge UCAM-CL-TR-579, 2004 — MCAS trees.
- **Brown, Ellen, Ruppert, LLX/SCX, PODC 2013** — SCX *finalizes/freezes* a record set so later writes fail: the closest "freeze-on-free" primitive → headline base cite.
- **Harris, Fraser & Pratt, MCAS, DISC 2002** — readers resolve a descriptor to old-or-new; the reader machinery the tombstone reuses (base, not delta).

**Delta boundary** — cite AND distinguish (these constrain the novelty):
- Concurrent relocating GC: Brooks 1984; Sapphire (Hudson & Moss 2001); ZGC; Shenandoah — reader forwarded *through* a marked slot by a load barrier. **The likeliest novelty challenge; the mandatory one-sentence distinction.**
- Bronson, Casper, Chafi, Olukotun, *A Practical Concurrent BST*, PPoPP 2010 — logically-deleted "routing" node readers traverse through.
- Matveev et al., *Read-Log-Update*, SOSP 2015; Kim et al., *MV-RLU*, ASPLOS 2019 — MW + reader-visible old versions.
- Arbel & Attiya, *Concurrent Updates with RCU (Citrus)*, PODC 2014 — the RCU-tree baseline (RCU readers + per-node-locked writers) our lock-free MCAS writers improve on.
- Zhang, LaBorde, Lebanoff, Dechev, *LFTT*, SPAA 2016 — descriptor-in-node, readers interpret logical status.
- Arbel-Raviv & Brown, *Reuse, Don't Recycle*, DISC 2017 — descriptor lifetime/reuse (our tombstone extends a descriptor's life to a grace period).

### Deep-read DONE (2026-07-18) — composition confirmed; distinctions + landmines

No source realizes both halves (reader-forward-to-old **and** writer-fail-and-re-descend)
in the tombstone's configuration. Paper-ready distinctions (adapt for §9):

- **vs SCX (Brown–Ellen–Ruppert, PODC 2013):** SCX *finalize* already fails a concurrent
  writer and makes it re-descend, and keeps a persistent descriptor mark — but its
  descriptor sits in a separate `info` field readers **never consult** (reader
  correctness is a linearization lemma over plain reads, *not* forwarding). Ours occupies
  the pointer slot and resolves **in place to the old target**, so an in-flight RCU reader
  traverses the pre-removal structure through the field it already reads.
- **vs Reuse-don't-Recycle (Arbel-Raviv–Brown, DISC 2017):** their descriptors are
  *transient*, reused precisely to **avoid** grace-period reclamation; ours is **left** in
  the slot with a lifetime = the RCU grace period. We reuse only their resolution read
  path, not their lifetime.
- **vs ZGC / Shenandoah GC barriers (the likeliest reviewer challenge):** GC forwards to
  the **new** copy and **heals the writer so its store succeeds**, scoped to a relocation
  cycle over the same object. Ours inverts all three axes — forwards to the **old** target,
  makes the writer's CAS **fail and re-descend**, lives one RCU grace period, and denotes
  logical **deletion**, not relocation.

**Wording landmines (enforce at §6 drafting):**
- never bare "forwarding pointer" — always "resolves to the *old* target" (bare reads as Brooks/Shenandoah = to-new);
- never "self-healing" (ZGC's term for the *opposite* writer treatment);
- don't present "freeze"/"finalize" as ours (SCX owns them) — say we *share SCX's writer-fail effect* and *add* reader-forward-to-old + in-slot resolution + grace-period lifetime;
- don't claim the descriptor-in-slot *resolution read path* as new (Harris/RDCSS heritage) — claim only what it resolves *to*, its *lifetime*, and its *logical-deletion* meaning;
- Harris collision: "writer CAS fails on a deleted mark and re-descends" ≈ Harris 2001 — don't claim that half alone. The novelty is that the **same MCAS descriptor is at once the deletion mark AND an in-place old-target resolver for a grace-period window**, giving RCU readers a linearizable pre-removal traversal with **no new reader code path**.

**Citation forms (verified):** SCX = Brown, Ellen, Ruppert, PODC 2013, pp. 13–22 (cite the
extended full version for the `info`/`marked`/SCX-record internals); Reuse = Arbel-Raviv &
Brown, DISC 2017, LIPIcs 91, art. 4; ZGC = Yang & Wrigstad, *Deep Dive into ZGC*, ACM
TOPLAS 44(4), 2022; Shenandoah = Flood et al., PPPJ 2016; Brooks, LFP 1984; Sapphire =
Hudson & Moss, JGI'01 2001. Extracted primary text for exact quotes when drafting §9:
`scratchpad/scx.txt`, `reuse.txt`, `shenandoah.txt`.

---

## ENGINE-CLAIMS SoA LEDGER (2026-07-18)

Engine claims only (tombstone is the other ledger). **Main outcome: soften two overclaim
risks (§5, §6), elevate §2 to centerpiece.**

| # | Claim | Verdict | Framing |
|---|---|---|---|
| 1 | sole-driver / no-helping / bounded-blocking as a design point | partially anticipated (the *philosophy* is known) | **cite** "blocking-can-beat-lock-free" (David–Guerraoui–Trigonakis; Flat Combining); **claim** the specific engine, not the tradeoff insight |
| 2 | **no-RDCSS via single-driver** | ⛔ **VERDICT WRONG — RE-SCOPED 2026-10-03.** RDCSS-free value-CAS install is Guerraoui 2020's own result (helping kept, unlock deferred). ~~distinct mechanism / novel articulation — CENTERPIECE~~ | claim only the *sole-driver closure* and what it keeps that deferral gives up (eager settle, store-decide, one GP); ~~linchpin = Guerraoui 2020; apparently unpublished~~ |
| 3 | rejected-alternatives disclosure | accurate but under-attributed | attribution fixes below; abort-others + age-resolution are ONE lineage |
| 4 | adaptive coarseness (aging→fair MCS, cost-scaled budget) | partially anticipated — novel *recombination* | cite each component; claim only the integration |
| 5 | RCU descriptor reclamation | **well-known — HIGH overclaim risk** | DON'T claim RCU-reclaim; claim only the refcount-free reachability point |
| 6 | RSEQ-TSE preemption-avoidance | mechanism = prior art (Gleixner 2025); use *pattern* = textbook (schedctl/TNP/scheduler-conscious sync) | claim nothing on mechanism *or* pattern; **disclose the userspace use** (defensive) + claim the tail-thinning *observation*; "not obviously anticipated" = applying deferral to an MCAS *publish* window vs a mutex holder |
| 7 | "bounded-blocking" progress class | not an established term | define it yourself; NOT obstruction-free (it waits); **starvation-free** via fair MCS — claim that, cited |

**Rejected-alternatives attribution fixes (§3):**
- **helping** → Barnes (SPAA 1993, origin) + HFP 2002 (the MCAS instance, in P1).
- **abort-others** → obstruction-free STM contention management: DSTM "Aggressive"
  (Herlihy–Luchangco–Moir–Scherer, PODC 2003, *already in P1*); Scherer–Scott (PODC 2005);
  root = wound-wait (Rosenkrantz–Stearns–Lewis, TODS 1978).
- **age-resolution** → DSTM "Timestamp" manager / wound-wait/wait-die / timestamp-ordering
  (Reed 1978; Bernstein–Goodman 1981). **NOT TL2/LSA** — those are version-as-*validity*,
  cite only for that.
- abort-others and age-resolution are **one lineage** (obstruction-free STM CM →
  wound-wait), not two inventions.

**Must-cite (new, beyond P1's bibliography):**
- *Philosophy / progress:* David–Guerraoui–Trigonakis (SOSP 2013); Flat Combining
  (Hendler–Incze–Shavit–Tzafrir, SPAA 2010); obstruction-freedom (Herlihy–Luchangco–Moir,
  ICDCS 2003); Herlihy–Shavit *On the Nature of Progress* (OPODIS 2011) + AoMP;
  Fich–Luchangco–Moir–Shavit (DISC 2005); Israeli–Rappoport (PODC 1994); Dechev (ISORC 2010).
- *Rejected alts + adaptive:* Barnes (SPAA 1993); Scherer–Scott (PODC 2005);
  Rosenkrantz–Stearns–Lewis (TODS 1978); Bernstein–Goodman (Comp. Surveys 1981); LSA
  (Riegel–Felber–Fetzer, DISC 2006); TL2 (Dice–Shalev–Shavit, DISC 2006); Lim–Agarwal
  (ASPLOS 1994); MCS (Mellor-Crummey–Scott, TOCS 1991); Lock Cohorting (Dice–Marathe–Shavit,
  PPoPP 2012); Kogan–Petrank (PPoPP 2012); Scott–Scherer timeout locks (PPoPP 2001).
- *Reclamation:* Brown DEBRA (PODC 2015); Wen et al. IBR (PPoPP 2018); Sugiura–Ishikawa
  MCAS-without-GC (IEICE 2022).
- *Preemption deferral:* Edler–Lipkis–Schonberg (1988); Marsh–Scott–LeBlanc–Markatos
  (SOSP 1991); Kontothanassis–Wisniewski–Scott (TOCS 1997); Anderson et al. scheduler
  activations (SOSP 1991); Solaris schedctl (US Pat. 5,937,187, 1999); Dice–Harris survey
  (TRANSACT 2016); Gleixner et al. rseq-TSE (Linux, 2025).

**Verify-before-cite:** Barnes SPAA 1993 wording (ACM 403); Edler 1988 (attribution only);
Israeli–Rappoport spelling; wound-wait page range.

---

## OPEN QUESTIONS / TODO

1. **DONE** — same-user convention propagated to the series README (the "Same user in
   every paper" paragraph).
2. **DONE — related-work check (2026-07-18):** verdict *partially anticipated*; claim
   the composition, cite + distinguish GC relocation. See the RELATED WORK LEDGER and
   DECISION #4 REFINED. *Deep-read DONE (2026-07-18):* composition confirmed;
   per-source distinctions + wording landmines now in the ledger.
3. **DONE** — whole-series ordering pass folded into the README (dcache = standalone
   app paper; candidate order; same-user convention). *Open, deliberately:* the P4
   identity fork (standalone comparative paper vs. folded into the dcache paper).
4. **Uncommitted, held while iterating:** README (ordering pass) + this SCOPE.md.
5. **RESOLVED 2026-07-28 — re-measured; see the "THROUGHPUT RE-MEASURE" section
   at the end of this file. Three numbers held, one was wrong.** The text below
   is the original statement of the problem, kept for the record.

   ~~**BLOCKING BEFORE SUBMISSION — every throughput number in P2 is stale.**~~
   The headline `+21.7%` / `+25.8%` (sole-driver vs helping, §varhelping) and the
   `roughly 2.6` optimistic-vs-serialized factor (§escalation) were captured
   **2026-07-10** on engine tip `97443472`. P2's Availability section pins
   **`b3e23f9f`** (2026-07-25) — fourteen engine commits later, including
   `610d4792` (skip the partition for a non-mixed write-set), `6139087e` (fold
   `rcu-mcas.h` in, **retire the duplicate MCAS engine**) and `7be75ff6`
   (re-verb the read policy from helping to waiting). The paper pins one engine
   and reports another's numbers.

   P1 had exactly this defect and it was fixed by **re-measuring, not
   re-pinning** — re-pinning to the old commit would describe an engine nobody
   can build from the shipped tree.

   Two cautions, both learned the hard way on P1 (see its §7 notes):
   - *Refreshing is not just re-running.* P1's re-measurement exposed two
     methodology faults, each moving the result by more than the effect under
     test: a traversal-order asymmetry between arms (~15%, which had made the
     facility look 8% faster than plain RCU when it is at parity), and
     per-iteration loads of harness globals in some readers but not others.
     Neither applies verbatim (`bench_txn_3skiplist` has neither in its inner
     loop — checked) but confirm the two arms do identical work apart from the
     mechanism under test before trusting any refreshed figure.
   - *The helping arm no longer exists.* It was retired in `6139087e`, so a
     refresh cannot simply rebuild both arms at `b3e23f9f`. Either reconstruct
     helping at a pinned old commit **and** measure sole-driver there too, so the
     pair is internally consistent; or restate the claim as what it already is —
     a historical falsification measured at `97443472`, which is *why* helping is
     not in the shipped engine — and put the engine version beside the numbers
     instead of leaving it to Availability. The second is honest, cheaper, and
     matches the argument the section already makes.

---

## P2 SECTION OUTLINE (skeleton — bridge to drafting)

Parallels P1's shape where it reuses. Tags: **[P1]** = recap + cite, do not re-derive;
**[→P3]/[→P4]/[→FT]** = defer; **[cite]** = prior art from the ledger.

1. **Introduction.** The RCU bargain + P1's second atomic act **[P1]**; P2's move = the
   *concurrent* engine — same pseudo-txn model without the SW exclusion crutch. State
   the thesis (coarseness; bounded-blocking as tail-latency-for-throughput, *measured*).
   Contributions: sole-driver mechanism; measured design-space; the RCU-forwarding
   tombstone (composition); the same list/hlist under MW. Scope para: read-set
   validation **[→P3]**, wide-node packing **[→FT]**, full eval **[→P4]**.
2. **Background.** Pseudo-txn model recap + SW flip-latch's exclusion-bought simplicity
   **[P1]**; what breaks without exclusion — the two MW hazards (install-ABA;
   disjoint-word structural race). Motivates §§3 and 6.
3. **The sole-driver MCAS engine.** Frozen record set + tri-state status +
   descriptor-naming CAS + status-word resolution; sole-driver (owner-only, no helping);
   **no RDCSS** (value-CAS install A-B-A-safe by construction); owner-only settle →
   existence reclamation; constraints (tag bit 0, frozen set, distinct slots).
4. **Progress and the coarseness thesis.** Deadlock-freedom (sorted-address install,
   age-0 bail); bounded-blocking (cross-txn settle-wait); adaptive coarseness (aging →
   fair-mutex, budget scales with cost); RSEQ-TSE (design lever, unclaimed upside,
   correctness-independent); the trade stated plainly.
5. **Variations & alternatives (LOAD-BEARING).** The design evolution helping-era →
   sole-driver; the table (helping / abort-others / age-resolution / DCAS /
   pure-lock-freedom), each with the decisive throughput number; "bounded-blocking
   anyway ⇒ lock-freedom retired."
6. **The RCU-forwarding tombstone (freeze-on-free).** The disjoint-word hazard;
   mark-and-retry base **[cite Harris/EFRvB/N–M/SCX]**; the RCU twist (forward, don't
   poison); the **composition** claim (descriptor-as-tombstone + RCU-grace lifetime + no
   new reader path); the one-sentence GC-relocation distinction **[cite
   ZGC/Shenandoah/Bronson]**.
7. **Transacted structures — the same user, now MW.** The bidirectional list + hlist
   **[P1 structures]** under concurrent writers: same-slot contention resolved by the
   engine (install/abort/aging); disjoint-word coupling resolved by the tombstone (§6).
   Forward-ref richer read-set validation **[→P3]**.
8. **Limitations.** Per-slot ≠ operation atomicity (tombstone handles the shown users;
   general coupling = the freeze discipline); bounded-blocking not lock-free (correctness
   ⊥ RSEQ-TSE); value-CAS atomicity; the contracts.
9. **Related work.** MCAS lineage; lock-free-tree freeze (SCX etc.); RCU trees (Citrus);
   reader-forwarding to distinguish (GC relocation, Bronson); old-version reads
   (RLU/MV-RLU); descriptor reuse (Arbel-Raviv–Brown, LFTT). Draw from the ledger above.
10. **Conclusion.**
11. **Availability.** Pin **b5767298**; headers `rcu-mcas.h`, `rcu-txn.h`, the MW wrappers.

**Ordering — SETTLED (Mathieu, 2026-07-18): primitive first (§6 → §7).** The tombstone
is presented as a general engine primitive, then §7 demonstrates it on the list/hlist
user (the skeleton above already reflects this). §2's Background still names the
disjoint-word hazard, so §6 does not arrive unmotivated.

---

## 2026-07-28 — VOICE: `engine` → `facility`

Applying the rule P1 settled in commit `9bcb8da` ("say facility, not engine,
where the design is meant"): **facility** where the DESIGN is meant, **engine**
only where it names an implementation — a measured build arm, a pinned commit, a
header, a filename.

P1 said facility 113 times and engine 3; P2 said engine 100 and facility 5, which
is off-voice for the series. 74 lines changed. **The title changed with it**: "A
Bounded-Blocking Multi-Writer **Facility** for Atomic Multi-Slot Update", and
`\label{sec:engine}` became `sec:facility`.

**~28 uses of "engine" are deliberately KEPT**, all naming implementations:
the measured helping / sole-driver build arms of §5.1 and their footnotes, the
drafting comments about engine versions and the retired helping arm, the
Availability tree and its headers, and the `.csv` filenames. Do not "finish the
job" on those — they are the same three-uses-that-stay judgement P1 made.

Four spots needed judgement rather than substitution, because "facility" reads
wrong in them: "the status engine with an extra field" → *status mechanism*;
"the descriptor-and-status engine" (§9.5's ingredient list) → *mechanism*; "a
blocking engine can beat a lock-free one" → *a blocking **design***, matching the
wording §9.2 already used; and "the composition pattern a lock-plus-engine design
converges on" → *that pairing a lock with this facility converges on*.

Build unchanged otherwise: 19 pp, refs OK, terms OK, abstract 1892/1920 (up 4,
from the two swaps inside the abstract).

---

## 2026-07-28 — MIXED SW/MW RECORDS FOLDED IN

P2 pins `b3e23f9f`, which has carried the mixed single-writer / multi-writer
front-end since 2026-07-22 (`2a599d77`..`610d4792`), while the text still
described a multi-writer-only engine opposed to P1's flip-latch. That is the same
defect class as the stale numbers: **pinning one tree and describing another.**

**New §3.5 `sec:kinds`, "Two install disciplines, one linearization point".**
The install discipline is a property of the RECORD, chosen per slot: shared slots
planted by the sole-driver CAS, exclusive slots parked by a plain release store
that cannot fail. `prop:kindinvisible` — both kinds share the resolve header, so
the kind is writer-side only and no reader can tell which parked a slot; the
generality is free on the read side. Then the argument that this was even
available: two incompatible proxy layouts at one tag was a REPRESENTATION
problem, and one shared header dissolves it. Then abort is MW-only (so an all-SW
write set cannot contention-abort — it recovers P1's commit exactly), and mixing
is paid for only when `0 < nr_mw < nr`.

Threaded through the rest: **§3.1** record gains a `kind` (P1's triple stays a
triple — the kind is this paper's addition, not the companion's); **§3.6
Constraints + §8 Limitations** the kind is a property of the SLOT and must be
GLOBALLY consistent across every writer, MW always safe, SW a promise, uncheckable
by the facility, fail-safe MW-dominates within one txn; **§4.1** the install sort
covers the MW prefix only; **§4.2** bounded-blocking classifies a WRITE SET, not
the facility — the coarseness thesis at a finer grain; **§6** the worked
list/hlist are all-MW (they promise no lock), a guard is MW by construction, and
mixing does NOT rescue `pprev` (the contract has teeth); **§11** the front-end
swap, and that no separate MW-only header exists at this commit.

**Claim scope — settled by literature review, recorded in full in the
`p2-mixed-swmw-litreview` memory. Verdict: CONJUNCTION element, not a third
independent claim; not a close call.** The DESIGN POINT is prior art and charted:
Tang & Elmore (USENIX ATC'18) Fig. 1 design 2, *one protocol per record, multiple
protocols per transaction*, with MOCC (Wang & Kimura) a prior instantiation. New
**§9.4 `sec:relmixed`** grants them the design point and states what the k-CAS
setting buys instead: their two mixing-cost terms are both zero here, and their
cross-protocol atomicity is a serializability argument over separate commits
where ours is one status store. *(`check-terms` flags "serializability" on that
line — DELIBERATE, describes CormCC not us, marked with an inline comment. Do not
let an editing pass attach the word to our mechanism.)* §9.5 names the element and
draws its boundary: what is ours is not that disciplines can be mixed but that
mixing THESE TWO costs nothing on either side.

Patent sweep, six families (Oracle MCAS 10824424/11216274, Sun KCSS 8230421, Sun
7685583, Sun STM 9424015 + 7720891, MS PMwCAS) — all uniform-install, all
negative. Keep-worthy by-product: Oracle's MCAS claim 1 requires writing the
status *by CAS*; sole-driver writes it with a plain release store.

**Two citation additions independent of the claim decision.** §3.3 gains PathCAS
(`brown2022pathcas`), which corroborates `prop:abainstall` from the inside — it
adopts DCSS precisely to stop a helper "resurrecting a completed operation",
stronger than the Guerraoui cite alone. §5.1 + new §5.5 `sec:varversion` + a
`tab:variations` row gain `unno2026helping` (arXiv 2607.06034, 2026): independent
concurrent work that KEEPS helping, throttles it, and suppresses install-ABA with
**version embedding** instead of RDCSS. It confirms our helping-under-contention
diagnosis and draws the opposite conclusion. Recorded, not rejected — it is not
ours to reject, and the table caption now says which rows are which.

**STILL BLOCKING, UNCHANGED: item 5, every throughput number is stale.** Nothing
here re-measured anything. Note that `610d4792` implies a pure-MW commit costs
what the MW-only engine did — that is a DESIGN property read off the commit path,
**NOT a measurement**, and must not be presented as one.

Build: 23 pp, refs OK, escapes OK, abstract 1910/1920.

---

## 2026-07-28 — THROUGHPUT RE-MEASURE (closes BLOCKING item 5)

Same 2×96-core EPYC 9654, idle. `DUR=2000 RUNS=5`, **240 runs, 0 failures**, all
four arms through a conservation gate before any timing was trusted. Data and
scripts in `efficios-trie-benchmark`: `scripts/p2_engine_remeasure.csv`,
`scripts/p2_lane_scaling.csv`, `build_p2_remeasure_arms.sh`,
`run_p2_engine_remeasure.sh`, `analyze_p2_remeasure.py`.

**Three of four numbers held:**

| claim | was | now (median of 5) |
|---|---|---|
| §varhelping @192 writers | +21.7% | **+22.1%** (best +22.0%) |
| §varhelping under contention | +25.8% | **+27.0%** |
| §escalation lane factor | ~2.6× | **WRONG — see below** |

Run-to-run spread within a point ≤2.3%, so the A/B separation is real. The
margin also grows with writer count (+5% at 1 → +22% at 192), which is the shape
a contention argument should have, and it is now stated that way.

**Why the A/B is at `97443472`, and the drift check.** Helping was *deleted* in
`a07b67ba`, so it cannot be built at the pin at all; `97443472` is the last
commit carrying both disciplines. To answer "but that tree is retired", the
sole-driver arm was measured at BOTH commits: at the pin it is **0.5–3.1%
faster** at every writer count. So the A/B's winner is the shipped engine,
slightly improved. **Do not cut that paragraph** — without it the A/B describes
a dead tree.

**The `2.6×` lane factor was wrong, and wrong in the engine header too.** It is
not a workload property: the lane is one global critical section, so its
throughput is FLAT in the writer count while the optimistic path scales. The
ratio is a function of scale and means nothing without one —

    writers    1     2     4     8    16    32    64   128   192
    factor   1.0x  2.3x 25.4x 50.9x 97.6x  172x  303x  946x 1029x

`2.6×` is about the **two-writer** point. At the 192-writer scale P2 otherwise
discusses it is **~1029×**. Sanity check that the always-escalate arm measures
the funnel and not itself: at one writer the two builds are identical (1.30032 vs
1.30030). Origin of the bad figure: engine commit `d4150ee8` states it with no
core count and `rcu-txn.h`'s escalation comment repeated it — **the engine header
is fixed in the same batch**. §escalation now carries the curve as a small table.
The correction *strengthens* the section: funnelling a traversal mutator is
catastrophic at scale, which is exactly why the budget scales with cost.

**Three preparation traps** — each would have produced a plausible wrong number
rather than an error. Documented in `run_p2_engine_remeasure.sh`; read it before
refreshing again. (1) the committed A/B script passes the retired `--ryw 1` and
the parser's `else usage()` exits, writing zeros into the CSV as data; (2) the
historical arms need `-DURCU_TXN_RYW_DEFAULT=1` or `movesper 3` runs without
read-your-own-writes and corrupts; (3) `-DURCU_MCAS_STOCK` flips five things, so
the helping arm must restore the txn-layer defaults or the win absorbs the Bloom
widening. Arms verified distinct by counting `uatomic_cmpxchg` sites (7 vs 13),
and the build script fails if they are equal.

**Still open:** P2 has not had Mathieu's own first read, and nothing has gone to
Paul. The `existence` / RLU / MV-RLU comparative axis remains the evaluation
paper's, deliberately not measured here.

---

## 2026-07-28 — WRITER SCALING ADDED (§5.1), and the numbers pinned

**`sec:writerscaling` + `fig:writerscale` now measure the paper's premise.** P2
asserted that dropping exclusion buys writer scaling and never showed it. On the
companion paper's own bidirectional list: **6.40 → 321.34 M updates/s over 1→192
writers (50×)**, against the flip-latch-plus-exclusion arm **peaking at its FIRST
writer and declining to 1.02** — a sixth of its one-writer throughput on 192×
the hardware. The two are within 3% at one writer, so the scaling is not bought
by degrading the uncontended case.

**Three caveats are IN the figure and prose, not left to be discovered:**
writers are disjoint by construction (the strongest form of the objection to
exclusion, not a favourable case for us); there are **no readers at all**, which
for a read-mostly facility is close to an anti-workload; and the dotted ideal
guide shows the facility reaching only **26% of ideal** at 192 writers. Log-log
is deliberate — a linear *y* would erase the excluded curve onto the axis.

`mutex` was measured but is NOT plotted: the lock engines recycle a node in place
where the RCU ones defer every free, so its absolute level is not comparable. Its
*shape* (flat) is in the caption in words.

**§1 Scope was reconciled**, since it deferred "scaling" to the evaluation paper.
The rule it now states is the one to keep: what appears in P2 is throughput
justifying a choice made *in this paper* — against an alternative we built and
rejected, or the facility against itself. Comparative evaluation against
existence/RLU/MV-RLU stays deferred.

**Number corrections in the same batch** (benchmark `65aa758`, layout pinned):
- `sec:escalation`'s lane table: **64 writers REMOVED**, 48 and 80 added. That
  cell printed 303×; the serialized lane is bistable there (0.161 at 48, 0.046 at
  80, both ±0.1%; at 64 it flips run to run, ratio spanning ~270–810×).
- `sec:varhelping` contended margin: **+27.0% → "roughly +30%"**, deliberately
  loose. It read +27.0/+28.5/+29.9% across three sessions with the peak moving
  1920→960 keys/sl, while holding ~1.5% *within* a session. **Do not tighten
  without a fourth session agreeing twice.**
- Headline +22.1% → **+22.0%**; now reproduced across three sessions
  (+22.1/+21.2/+22.0), which the footnote states.

**Still open:** Mathieu's first read; nothing to Paul. And `fig:writerscale`'s
alignment caveat — cacheline-aligning nodes lowered the low-writer baseline while
leaving the peak, so the scaling ratio is slightly flattered; that is disclosed
in the benchmark commit but NOT yet in the paper.

---

## 2026-10-03 — GUERRAOUI ET AL. READ IN FULL: "no RDCSS" is not ours; first claim RE-SCOPED

**What happened.** `guerraoui2020mcas` (Guerraoui, Kogan, Marathe, Zablotchi,
*Efficient Multi-word Compare and Swap*, DISC 2020; full version arXiv
2008.02527, 28 pp) has been in the bib since scoping, and this paper used it for
**one sentence of its introduction** — RDCSS locks a word "provided that the
current operation was not completed by a helping thread" — as the "linchpin"
tying RDCSS to helping. Mathieu flagged it on 2026-10-03 as prior art that
*directly* relates to P2. Read in full, it is the nearest prior art this paper
has, and **its own algorithm is RDCSS-free**. Ledger item 2's verdict
("distinct mechanism / novel articulation — CENTERPIECE … apparently
unpublished") was wrong. The patent sweep of 2026-07-28 did look at an Oracle
MCAS family, but only for the mixed-install question.

**What their algorithm is.**

- **Plain value-CAS install, no RDCSS, helping KEPT, lock-free.** `k+1` CASes
  per uncontended `k`-CAS: `k` to acquire, one to finalize the status.
- **Deferred unlock.** A finalized descriptor is left in its words. A later MCAS
  on a word installs *its* descriptor over the old one (CAS on raw content); a
  plain value is written back only by **detach**, a CAS performed during
  reclamation.
- **Epoch reclamation, "similar to RCU"**, no refcount, two stages:
  `finalizedDescList` → (epoch scan) → detach by CAS → `detachedDescList` →
  (epoch scan) → free. The *detach* being behind an epoch is what closes the
  install ABA — "ABA prevention for free".
- **Readers do not write** unless they meet an ACTIVE operation, which they
  then **help** (`readInternal` calls `MCAS(parent)`).
- **Lower bound** (Thm 4): a lock-free, disjoint-access-parallel k-CAS must, in
  some execution, CAS at least `k` locations.
- **Appendix A.1 is our §3.3 trace**: Harris et al. with CAS in place of RDCSS.
- **The cost they name themselves:** "lower read performance (because of the
  extra level of indirection reads have to traverse when encountering a
  descriptor left in place after a completed MCAS)". List size 500, 80% reads:
  PMwCAS (eager unlock) ahead 1.2× on average; 100% reads: on par or slightly
  behind (A.7). Sizes 5 / 50: theirs ahead 2.6× / 2.2×. For read-dominated
  workloads A.6 has a **reader** scan epochs and detach by CAS, with small
  probability.

**Side by side** (this is `tab:closures` in the paper):

| | RDCSS (HFP 2002) | Deferred unlock (Guerraoui 2020) | Sole driver (P2) |
|---|---|---|---|
| cuts the §3.3 trace at | step 5 | steps 3–4 | step 2 |
| helping | yes | yes | none |
| progress | lock-free | lock-free | bounded-blocking |
| install | RDCSS | one CAS | one CAS |
| decision | CAS | CAS | **release store** |
| unlock / settle | eager, CAS | **deferred** to a later op or to reclamation | **eager, release store** |
| CAS per uncontended k-slot commit | 3k+1 | k+1 | **k** |
| slot after commit | plain | **descriptor** | plain |
| read meeting an in-flight op | helps | helps | resolves to old |
| descriptor reclaim | (GC assumed) | 2 epochs + detach pass, no refcount | 1 grace period, no refcount |

Our helping-era engine, by §5.2's own count, was **4k+1** (plant + FREE→BUSY +
FREE→DONE + settle-CAS per record, + status CAS).

**The claim as it now stands.** NOT "a sole-driver MCAS needs no RDCSS". It is:
*the install-time A-B-A can be closed by removing the second driver, and closing
it that way — unlike deferring the unlock — leaves the settle eager (no
descriptor outlives its commit in a slot), the decision a plain store, and the
descriptor unreachable when the commit returns.* A negative result twice over
(RDCSS unnecessary, deferral unnecessary); priced honestly: **not lock-free,
theirs is.** Register unchanged: "we are not aware of". The argument for
choosing it is the series' read-side thesis, which is exactly what Guerraoui's
own evaluation concedes at the read-heavy, low-contention end.

**What is superseded in THIS file — do not restate any of it:**

- Thesis, causal chain: "helping … *forced* a per-record … spinlatch … helping
  never bought true lock-freedom". True of the engine **we built**; false of
  helping as such. The latch was *our* closure. Guerraoui's is another, and it
  is lock-free.
- "No RDCSS — the CENTERPIECE engine claim" bullet, and ENGINE-CLAIMS LEDGER
  item 2 (both marked in place).
- Coarseness thesis #1 ("so lock-freedom was never actually on the table
  there") — keep only with "there" meaning *our helping engine*; #3 ("Why not
  DCAS/RDCSS … Sole-driver removes the need entirely") — so does deferral.
- Variations table row "Pure lock-freedom — unreachable once co-install forced
  the per-record install latch". It is reachable (Guerraoui); it was out of
  reach of *our* helping engine.
- ENGINE-CLAIMS LEDGER item 5: "refcount-free reclamation POINT" — refcount-free
  alone does not distinguish us (theirs has none either). What is ours: **one**
  grace period, **no detach pass**, the free point reached at commit return.

**What the +22% does and does not show.** It retired OUR helping path: a 4k+1,
latch-blocking design. It says nothing about a k+1, lock-free, latch-free helping
design, which we did not build. The paper now says so in §5.2, §5.6, the table
caption, the abstract and the conclusion. **Do not let an editing pass re-widen
"helping lost" into a claim about helping in general.**

**What changed in `main.tex`** (34 pp, was 30; abstract 1906/1920):

- Abstract: "most of all—no RDCSS" gone; deferral named as the other RDCSS-free
  route; "lock-freedom was never on the table" → "the lock-free one we did not
  build charges the reader".
- §1: new paragraph "What that trail does not show"; Contributions re-worded.
- §3.3 `sec:norddcss`: trace credited to their Appendix A.1; **three cuts** of
  the trace (RDCSS / deferred unlock / sole driver); "linchpin" paragraph
  replaced by "credited where it is due"; new **`tab:closures`**; the lower
  bound and why `k` (shared) and `0` (exclusive) are outside it.
- §3.4 `sec:settle`: their refcount-free two-stage epoch reclamation cited;
  ours narrowed to one grace period, no detach pass.
- §4.5 `sec:trade`: the ledger against the latched engine vs the narrower one
  against deferred unlock.
- §5.2 `sec:varhelping` (retitled "the latch we closed it with"): 4k+1; the
  scope-of-the-measurement paragraph.
- **New §5.6 `sec:vardefer`**, "Keeping the helpers, and deferring the settle".
- §5.7 `sec:varversion` opening; §5.8 `sec:varlockfree` rewritten.
- `tab:variations`: new row, re-worded Helping and Pure-lock-freedom rows, new
  caption; float changed `[t]` → `[tp]` (the extra row had pushed it to the last
  page of the paper).
- §8 Limitations, §9.1, §9.6 `sec:relclaims`, §10 Conclusion.
- `common/urcu-txn.bib`: new `guerraoui2020mcasfull` (arXiv full version), cited
  for Appendices A.1 / A.6 / A.7; the proceedings entry for everything else.

**P1** (`p1-sw-flip-latch/main.tex`): §11.1 gets a paragraph on their k-CAS —
the bound, why zero CAS under exclusion is outside it, eager vs deferred
settle; §9.4 `sec:varsettle` cites their deferred unlock as the published form
of the lazy settle it already describes (install-over, and conditional
detach); §11.3 cites them for status-resolution-without-writing and quiescence
reclamation, and for what "transient" excludes. **Slides:** one backup Q&A and
three speaker notes; no main-line slide changed (the MW engine is not in the
talk).

**Two observations about THEIR paper, recorded here and NOT in ours** (Mathieu
asked whether their scheme can suffer a structural ABA, i.e. whether a word ever
returns to a plain value):

1. In the algorithm they **prove** (Listing 3, App. A.2) it never does: the only
   write to a target word is the acquire CAS, and Lemma 10 says a location once
   acquired is never un-acquired. Structural ABA is impossible there outright —
   the CAS compares raw *content*, and a logical B→X→B is `plain B → &wd(T1) →
   &wd(T2)`. But §6 opens "presented so far under the assumption that no memory
   is ever reclaimed": **the proof does not cover detach**, which is the one
   transition back to plain. Its safety is the informal "for free" argument.
2. `readInternal` helps by calling `MCAS(parent)`, which runs its own
   `epochStart()/epochEnd()`. Under A.4's parity scheme (odd = inside) a helper
   in a nested call reads as **even**, i.e. quiescent, exactly while it is the
   stalled second driver. Read literally that reopens the ABA through detach. A
   real implementation surely uses a re-entrant guard; **their code has not been
   checked.** Do not put either point in the paper without checking it.

**OPEN — Mathieu's calls:**

1. **Claim structure.** The first claim is kept as an independent claim,
   re-scoped. The alternative is to fold it into the conjunction and let the
   paper have one claim. The text is written so that either reads true.
2. **Title and thesis.** Unchanged. "Sole-Driver MCAS" still names what is ours.
3. **The missing measurement:** an AOPT-style arm (helping + `call_rcu`-deferred
   detach) against sole-driver, with readers. Belongs to P4, against their
   code. Until then the choice rests on design grounds and on *their* numbers.
4. **Patents.** Re-read the Oracle family the sweep lists (US 10,824,424 /
   11,216,274 — presumably this algorithm; not confirmed) against the
   deferred-unlock design, before anything like §5.6's "set on this facility's
   substrate" paragraph is ever built.
5. **The engine header** (`rcu-txn-mcas.h`) says "A bare value-CAS is correct
   because the owner is the SOLE driver". True, and it owes Guerraoui et al. a
   line too. Not edited (the engine tree is read-only from here).
6. `README.md` line 27 still summarizes P2 as "(no-RDCSS)". Left alone.

### 2026-10-03, later the same day — ⛔ BLOCKING BEFORE SUBMISSION, and the goal is open again

**Mathieu: investigate the deferred-settle engine before publishing P2.** Two
things follow, and neither is resolved.

**1. The design note is committed, the prototype is deliberately not started.**
`efficios-trie-benchmark/design/rcu-mcas-deferred-settle.md` (commit `4326725`).
It is the missing arm of OPEN item 3 above, worked out at design level: helping
or abort-others, install-over a decided proxy so writers do not stall for the
grace period, detach by CAS from a `call_rcu` callback, decision by CAS, two
grace periods per descriptor.

**2. The goal question (Mathieu).** An engine close to the published algorithm
would be truly lock-free at the cost of overhead — a progress-guarantee vs
throughput trade. And the series' throughput target is already met by P1's
plain stores under the embedder's locks. So **lock-freedom may be a more
appealing goal for P2 than bounded-blocking.** If so, the paper's subject
changes: a lock-free multi-writer facility, with sole-driver as the measured,
throughput-leaning variation — the reverse of today's text.

**What the design note found that this paper does not yet say:**

- **A deferred detach is the first write to a transacted slot made OUTSIDE the
  read-side critical section its transaction ran in.** Today plant, settle and a
  loser's settle-back are all inside it, which is why one grace period covers
  free *and* reuse (`sec:reclaim`). With deferral, a node can be unlinked and
  freed before an earlier descriptor's detach callback runs, and the detach then
  CASes freed memory. This may be the strongest argument the eager settle has,
  and it is stronger than the reader indirection. **Unverified against their
  implementation** — do not write it into the paper as a defect of theirs.
- "Eager settle when nobody helped" is unsound as stated; a per-record rule
  (un-helped AND planted over a plain value) may hold. Unproven.
- A truly lock-free claim needs: address-ordered helpable transactions, ranked
  abort, no domain-wide lane, and the standing caveat that reclamation stays
  blocking.

**What re-targeting would cost the paper.** The closer P2 gets to the published
algorithm, the less of it is ours: what would remain is readers that never help,
the RCU integration, an answer to the detach-lifetime problem, the mixed record
kinds, and the hybrid if it holds. And OPEN item 4 moves from the margin to the
centre: the earlier sweep's one distinguishing element for sole-driver was that
it decides by plain store where the Oracle claim recites a CAS — an engine with
helpers decides by CAS. Mathieu's call, with counsel.

**State of the text.** The 2026-10-03 re-scope above is correct for the engine
that exists. Do not submit, and do not polish the bounded-blocking argument
further, until this is decided.

### 2026-10-03 — FRASER'S THESIS READ IN FULL (UCAM-CL-TR-579): cited for the shape, owed for much more

Mathieu: "we have it in our bibliography, but we fail to cite it in the papers."
It *was* cited — three times here, three in P1 — but only as a co-citation for
the descriptor-and-status "shape". Read in full (116 pp), it is the primary
source for several things this paper leaned on later papers for, or said without
a source. `common/urcu-txn.bib` now carries a by-section summary above the entry.

**What it changes in P2:**

- **The claim, once more, and more exactly.** The eager settle is *not ours
  either*: it is the release phase of the original algorithm (thesis §3.2.1: a
  location not owned "stores its logical value directly, allowing direct access
  with no further computation or memory accesses"). So the three designs are:
  HFP/Fraser = conditional install **+ eager release**; Guerraoui = **bare
  install** + deferred release; sole-driver = **bare install + eager release**,
  which neither has, bought by giving up helping. `sec:norddcss` and
  `sec:relclaims` now say exactly that. *Do not let "eager settle" be written
  as a novelty on its own.*
- **Primary source for "the conditional install exists because of helping".**
  Thesis §3.2.1, on CCAS: it "prevents a phase-one update from occurring 'too
  late'", when "a helping process could incorrectly reacquire a location after
  the MCAS operation has already succeeded". 2004 — sixteen years before the
  Guerraoui sentence this paper called its linchpin. Quoted in `sec:norddcss`.
- **`sec:soledriver`:** a read that need not help is Fraser's observation
  ("does not need to involve recursive helping"), though his MCAS read helps.
- **`sec:settle`:** practical MCAS as first built *reference-counts* its
  descriptors and reclaims only nodes by epochs (§5.2.2–5.2.3). That is the
  baseline "refcount-free" is measured against, and it was uncited.
- **`sec:deadlock`:** the address order is his (it bounds recursive helping).
- **`sec:varhelping`:** "excessive helping can generate harmful memory
  contention" (§2.1.3) — the diagnosis is his, not recent.
- **`sec:varabort`:** aborts ordered by descriptor address (FSTM, §3.3.2).
- **`sec:tombstoneclaim`:** his MCAS skip list unlinks a node, rewrites its own
  forward pointers and nulls its value in ONE MCAS — logical deletion in the
  commit that unlinks. This was in the RELATED WORK LEDGER as a base cite and
  never reached the text.
- **`sec:guard`:** new paragraph. The guard-as-record is FSTM's first form of
  read validation; Fraser names its cost and moves to a commit-time read phase,
  at the price of a fourth status and ordered aborts. P3's SCOPE has the note.
- **§9.1** lists the five places the paper leans on the thesis.

**What it changes in P1:** `sec:pertag` cites his fixed two-bit tag and the one
table that shares the patterns out — the documented instance of the design the
section argues against; `sec:vartag` cites his descriptor-pool alternative;
`sec:relmcas` says install/commit/settle *are* his acquire/decision/release
phases with the CASes replaced by stores; and **`sec:relclaims` gains a
paragraph conceding that the three-property combination is not a distinction
against MCAS** (an MCAS descriptor is transient, resolved through, and costs an
element only reserved bits). It distinguishes P1 among RCU-publication
mechanisms. Against MCAS the distinction is plain stores under exclusion,
readers that never write or help, and the per-record tag. *Mathieu to confirm
that concession; it is in his claims paragraph.*

**For the design note** (`rcu-mcas-deferred-settle.md`): address order, ranked
abort, type-stable descriptor memory and "not strictly lock-free" reclamation
all have their source here.
