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
- **No RDCSS — the CENTERPIECE engine claim (strongest novelty).** Plain value-CAS
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
  - **The ONE back-edge guard is NOT deferred — DECISION #5 (Mathieu, 2026-07-18).**
    P2's flagship example is the *bidirectional* list/hlist; under MW its
    back-edge write (`succ->pprev`) has a read-side precondition — *succ still live* — on a
    disjoint slot (`succ->next`) it reads but does not write, so it needs a guard
    (`load_validate`; source: "exists ONLY to guard the pprev write"). Without it P2's own
    flagship example is not correct under MW → a forward dependency on P3. Resolve it the same
    way as freeze-on-free: introduce the guard **minimally in P2** (functional only — "fold
    this read into the commit's conflict set; commit fails if `succ` was deleted"), as the
    **read-side companion to the tombstone**. Symmetry: forward edge *write*-validated, back
    edge *read*-validated. The *general* read-side model (read-policy taxonomy, à-la-carte
    guards + SoA, declarations, composition) stays in P3; P2's one guard is P3's on-ramp, and
    P2 must NOT claim the à-la-carte novelty (that is P3-1). Rejected alternative: a
    forward-only P2 example — regresses from P1 and guts the tombstone's motivation.
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

5. **Back-edge guard lands in P2, not P3** (Mathieu, 2026-07-18). P2's bidirectional
   flagship forces one `load_validate(succ->next)` to guard the `pprev` write, so a minimal,
   functional guard is introduced in P2 — the read-side companion to the tombstone (forward
   edge write-validated, back edge read-validated), same logic as freeze-on-free. The
   *general* read-side model stays P3; P2 does not claim the à-la-carte novelty (P3-1). See
   the boundaries note for detail.

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
| 2 | **no-RDCSS via single-driver** | **distinct mechanism / novel articulation — CENTERPIECE** | claim as applied ownership logic; linchpin = Guerraoui 2020; apparently unpublished |
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
