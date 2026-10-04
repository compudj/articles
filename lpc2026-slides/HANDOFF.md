# LPC 2026 talk — slide-deck handoff

Written 2026-09-30 so the slide work can continue offline on the laptop.
Everything below is self-contained: the laptop session will NOT have this
machine's Claude memory, so the standing rules are restated at the end.

## 1. The talk

- **Title:** RCU Pseudo-Transactions: Bridging the gap between RCU and STM
- **Venue:** Linux Plumbers Conference 2026, Refereed track.
  **6 October 2026, 10:00–10:45** (45 min incl. Q&A), "Small Hall", Prague
  Congress Centre. <https://lpc.events/event/20/contributions/2348/>
- **Speaker:** Mathieu Desnoyers (EfficiOS Inc.)
- **Audience:** kernel developers. Linus Torvalds *may* be in the room.
- **Abstract (verbatim):**

  > RCU data structures are notoriously complex to design mainly due to the
  > need to carefully manage how mutations are made observable to concurrent
  > readers.
  >
  > As a general solution to this problem, I am proposing a novel
  > transaction-based synchronisation mechanism: "RCU Pseudo-Transactions"
  > (rcu_txn).
  >
  > It applies both to userspace and kernel. It allows publishing complex
  > data structure mutations atomically to RCU readers, and synchronizing
  > updates from multiple writers, with minimal overhead on the read-side
  > (low-bit pointer tag check, predicted branch on rcu_dereference), and no
  > size overhead on the data structure nodes. It is composable: an object
  > can belong to multiple transaction-aware data structures, and
  > transactions allow it to become visible (or hidden) atomically.

## 2. Decisions taken (2026-09-30)

1. **Main focus: the single-writer (SW) txn API** — `rcu-txn-sw*.h`.
2. **P1 is the backbone.** Use its content freely
   (`p1-sw-flip-latch/main.tex`, figures, `data/*.csv`).
3. **Multiple writers = fine-grained locks around SW commits.** "We already
   offer fine-grained locking with the SW txn API." P1 exclusion is per
   *slot*; P1's writer-scaling figure is the evidence.
4. **The MW CAS-based engine (P2, sole-driver MCAS) is NOT presented.** No
   slide, not even a teaser.
5. **Dentry cache: in (2026-10-03).** The benchmarks finished (sweep of
   2026-10-02; re-taken 2026-10-03 at P1's engine pin, nothing moved, §7)
   and Mathieu cleared the figures for the talk. One slide (26)
   and one backup slide, on the bucket lock + SW txn engine only: the MW txn
   arms of the same benchmark fall under decision 4 and are not shown.
6. **Charts are static** (projected + PDF upload): no hover/tooltips; print the
   numbers that matter on the chart.
7. **Mechanism before guarantees (2026-10-04).** Mathieu: "for lpc, presenting
   the technical achievement first will catch the audience interest. _then_
   we contextualize it in the SOA". The flip-latch, lifecycle, read side,
   tags, exclusion and the API on one slide now follow slide 7; what the
   model provides, never new-then-old and "Between RCU and STM" come after
   them. Renumbering: old 11–16 → **8–13**, old 8–10 → **14–16**; slides 1–7
   and 17–33 keep their numbers. Commit messages and notes written before
   that date use the old numbers. Slides 14–16 carry the kicker "The
   guarantees" (Mathieu, 2026-10-04) and the others kept theirs, so the
   kickers read MODEL (7), MECHANISM (8–12), API (13), GUARANTEES (14–16),
   API (17–21).

Advice given (not yet a decision), because Linus may attend: the dcache is his
code, and "dissolve `rename_lock` + `d_seq`" is the claim most likely to be
challenged. Let the SW core stand on its own; if the dcache goes in, frame it
as "where this lands in the kernel", at most ~2 slides, with the fresh numbers.

## 3. Format — two routes

- **claude.ai Slides artifact (started, EMPTY):**
  <https://claude.ai/artifact/SeqLpDnifejUbvPVKanum5> — created from the Slides
  type, nothing published yet. Needs internet to edit; downloads as PDF/.pptx.
  The Artifact tool re-supplies the type's file format on each call
  (`project/deck.json` + one `project/slides/<id>.html` per slide).
- **Beamer in this repo (offline-friendly):** add `lpc2026-slides/main.tex`,
  reuse P1's TikZ/pgfplots figures and CSVs directly (`fig-fliplatch.tex`,
  `fig-anatomy.tex`, `fig-skew.tex`, `fig-list-insert.tex`,
  `fig-list-remove.tex`, `fig-tagword.tex`, the §7 pgfplots blocks). This is
  the route that survives a poor connection; the artifact can be filled later
  from the same outline if wanted.

## 4. Visual design (chosen for the artifact; reusable in Beamer)

Direction: developer/infrastructure, quiet, code-first. Fonts: **IBM Plex Sans**
(text + headings, 600 for headings) and **IBM Plex Mono** (code).

| Role | Hex | Contrast (checked) |
|---|---|---|
| Paper background | `#F5F3EE` | — |
| Alt paper | `#E9E5DC` | ink 13.4:1, muted 6.0:1 |
| Dark (section/statement slides) | `#17191E` | paper text 15.9:1, `#B8BDC7` 9.3:1 |
| Ink | `#1A1D23` | 15.2:1 on paper |
| Muted text | `#4F5561` | 6.75:1 on paper |
| Accent blue (the facility / "new") | `#2456A6` | 6.40:1 |
| Accent orange (plain RCU / "old", text-safe) | `#B04A0C` | 4.94:1 |
| Code panel bg / text | `#1F232B` / `#E8E4DA` | 12.4:1 |
| Code comment / keyword / blue | `#9AA3B2` / `#F2A65A` / `#8DB6F0` | 6.2 / 7.8 / 7.6:1 |

Writer-scaling chart series (CVD-checked, OKLab ΔE ≥ 9.4 for every pair under
protan/deutan/tritan simulation; also distinguished by dash + direct labels):
txn_sw bit-lock `#2456A6` solid; txn_sw stripes `#6A8BC6` dashed; rculist
stripes `#B04A0C` solid; one lock `#707682` dotted.

Type scale (artifact, 1920×1080): 88 cover / 60 titles / 36 lead / 30 body /
24 code, captions, footer.

## 5. Slide-by-slide draft (~25 slides, ~33 min + Q&A)

Timing guide ≈ 1.3 min/slide. `[opt]` = cut first if short on time.
Order and numbers are the deck's since the 2026-10-04 reorder (§2 item 7).
Numbers are P1's, engine pin 2793224e since the 2026-10-03 re-take (provenance in §7).

### A. The problem (~7 min)

**1. Cover.** Title; "Mathieu Desnoyers · EfficiOS"; "LPC 2026 · Prague ·
6 October 2026".

**2. RCU's contract.** Statement: *Readers pay nothing. In exchange, a writer
gets exactly one atomic operation: a single pointer store.* Three boxes: Build
(private, unconstrained) → **Publish (one store — the linearization point)** →
Reclaim (after a grace period). Punchline: a pseudo-transaction does not add a
fourth phase; it **widens the second one**.

**3. The kernel's list already needs two stores.**
```c
static inline void __list_del(struct list_head *prev, struct list_head *next)
{
	next->prev = prev;              /* N->prev: E -> P   plain store  */
	WRITE_ONCE(prev->next, next);   /* P->next: E -> N   marked store */
}
/* __list_add_rcu(): */
	new->next = next;                              /* private */
	new->prev = prev;                              /* private */
	rcu_assign_pointer(list_next_rcu(prev), new);  /* publishes new */
	next->prev = new;                              /* plain store, AFTER publish */
```
Consequence: `list_del_rcu()` poisons `prev` (`LIST_POISON2`); rculist ships
forward iterators only. Userspace RCU's `cds_list_*_rcu` has the identical shape.
Note: this was a considered trade (poison = use-after-delete debugging), not an
oversight — say so, it earns goodwill.

**4. Ordering is not what's missing.** Diagram P↔E↔N removal. Even with both
edges properly published they are *two* release stores = two instants: a reader
can see `P->next == N` while `N->prev == E`. Second failure: the removed node is
a ghost until its grace period, so the backward view trails the forward view by
up to a grace period. *No barrier fixes a window whose width is a grace period.*
Callout (the kernel's narrow exception, Dec 2024, Brauner; suggested/reviewed by
McKenney): `list_bidir_del_rcu()` + `list_bidir_prev_rcu()` let a reader step
back out of a ghost — useful, not a coherent reverse walk; can't mix with
`list_del_rcu()` on one list; sole in-tree caller `__ns_tree_adjoined_rcu()`
(kernel/nstree.c, next-20260226) takes one hop and never compares directions.

**5. Two structures, one object.** Hash index + LRU list. Two publishes: either
findable-but-not-ordered or ordered-but-not-findable. A writer-side lock over
both doesn't help — *the observer is a reader, which takes no lock*. (P1
`fig-skew`.)

**6. Today's remedies each pay somewhere.** Table:
copy the region → pay in allocation/footprint/reclaim per update (and pinned
nodes can't be copied: references the writer does not own); drain with a grace period →
writer waits; steer/validate the reader (seqcount retry like the dcache's
`d_seq`/`rename_lock`, per-element locks) → paid on *every* traversal; decline
(no reverse iterator).

### B. The model: the definition (~1.5 min)

**7. A pseudo-transaction.** Definition: a frozen set of {slot, old, new}
records made visible by one commit step. Table "journaling FS vs
pseudo-transaction" (P1 tab:fssense): journal txn closed ↔ record set frozen;
commit record ↔ commit step; old before / new after; never a partial batch ↔ no
slot and no instant is torn; readers not transactional ↔ plain RCU readers;
atomicity, not isolation ↔ atomicity, not opacity. *"Pseudo-" is a
disambiguation, not an apology.*

### C. The mechanism (~6 min)

**8. The flip-latch: one level of indirection.** Diagram (P1 `fig-fliplatch`):
slots → tagged proxy {old, new, group} → group {selector}. *Every proxy in a
group reads the same selector; one release store flips the set.*

**9. Lifecycle.** Table (P1 tab:lifecycle): before / Build / Install /
**Commit** / Settle / after; the reader's column reads o, o, o, **n**, n, n.
Install and settle both rewrite the slot yet change nothing a reader resolves;
settle *is* the uninstall; then `call_rcu()` the block.

**10. The read side is one branch.** (verified, 18809ea8)
```c
static inline void *urcu_txn_sw_resolve(void *v, uintptr_t tag)
{
	if (caa_likely(!urcu_txn_sw_is_proxy(v, tag)))  /* (v & tag) != tag */
		return v;
	return urcu_txn_sw_proxy_get(urcu_txn_sw_untag(v, tag));
}
/* proxy_get: proxy->ptr[uatomic_load(&proxy->group->selector, CMM_ACQUIRE)] */
```
Not parked: a test on a register already loaded + a predicted branch, **no
load**. Parked (install→settle only): proxy → group → selector → ptr[sel];
indexed, a data dependency, not a branch. Nice detail: untag *subtracts* the tag
so the compiler folds it into the load displacement.

**11. Tags.** Parked slot = `(record_address | tag)`; recognized iff
`(v & tag) == tag`. **Per-record tag**, because one commit may span structures
with different encodings (bit 0 vs a reserved nibble) — cross-structure
atomicity forces it. Records 16-byte aligned → 4 low bits. Store the tag, not a
tagged pointer → the descriptor can grow by realloc. Contract: no legitimate
slot value may carry the tag pattern (debug build asserts).

**12. Exclusion is per slot.** No install CAS, no conflict detection, no abort —
that is why it is cheap. Two writers on one slot silently corrupt;
`-DURCU_TXN_SW_EXCL_VALIDATE` aborts the process on a violation (free when off).
Fine-grained locks (per bucket, per node) are the ordinary way to meet it:
writers on disjoint slots commit concurrently. Commit fails only for want of
memory; `urcu_txn_sw_reserve()` up front rules that out.

### D. The API (~8 min; slide 13 here, slides 17–21 after the guarantees)

**13. The API on one slide.** (names verified at 18809ea8)
```c
struct urcu_txn_sw_txn txn;                    /* on-stack handle */

urcu_txn_sw_init(&txn);
urcu_txn_sw_reserve(&txn, 3);                  /* optional: rule out OOM up front */
old = urcu_txn_sw_load(&txn, &a->next, TAG);   /* sees this txn's pending writes */
urcu_txn_sw_record_chain(&txn, &a->next, old, x, TAG);
urcu_txn_sw_record(&txn, &b->prev, y, x, TAG); /* blind append */
if (urcu_txn_sw_commit(&txn) != URCU_TXN_STATUS_OK)
	/* URCU_TXN_STATUS_MEMORY_ERROR: nothing was published */;

/* reader, under rcu_read_lock(): */
v = urcu_txn_sw_resolve(rcu_dereference(*slot), TAG);
```
Commit: nr ≤ 1 → a plain release store, no proxy, freed at once; nr ≥ 2 →
park proxies, flip, settle, `call_rcu()` the block. OOM is sticky (check only
commit's status). Never returns ABORT.

### B, continued. The guarantees: what the model provides, where it stands (~4.5 min)

After the mechanism and the API since 2026-10-04 (§2 item 7).

**14. What it provides, and what it does not.** Provided: write-set atomicity;
no tearing; the commit linearizes at one point (scoped to the WRITE);
cross-structure atomicity — unit = one pseudo-txn (two commits = two
linearization points).
Not provided: **a reader is not a transaction of any kind**; no opacity, no
multi-read snapshot; no read validation in SW (under exclusion nothing to
validate against).

**15. Never new-then-old.** Selector written once 0→1, never back ⇒ a reader
resolving slots of one commit *along a dependency chain* sees o…o,n…n, never
n then o. Scope: an address dependency or an acquire; two independently-reached
slots (cached pointer, sibling subtrees) owe an acquire
(`-DURCU_DEREFERENCE_USE_VOLATILE` on weak ordering). Kernel aside: arm64 +
`CONFIG_LTO` already promotes `READ_ONCE()` to acquire for this reason.
New-then-old is exactly what forces seqcount-style read-side remedies; the
model forbids it by construction. `[opt]` Triplett's reverse-publish-order rule
for split edits.

**16. Between RCU and STM** (the title's bridge). Three columns: RCU — one slot
atomic, readers free | pseudo-txn — N slots atomic to readers, readers
uninstrumented, write set only | **opaque** STM — read+write sets,
isolation/opacity, a barrier on each transactional read (scoped 2026-10-04: the
column read "STM" and "a barrier on every read", which is not true of every
STM; see "STM reads can opt out" under the anticipated questions). *Isolation is a read-side cost once updates mutate in place;
we decline to charge readers for it.* Honest asterisk: RLU/existence give
readers strictly more, and charge more.

### D, continued. The API: the structures built on it

**17. The list: the reverse walk comes back.**
```c
rcu_read_lock();
urcu_txn_sw_list_for_each_entry_reverse_rcu(pos, &head, node)
	...;
rcu_read_unlock();

urcu_txn_sw_list_del_rcu(&e->node);   /* writer, under the embedder's locks */
call_rcu(&e->rcu, free_e);
```
Property: at every resolution, `a->next == b` ⇒ `b->prev == a`. A removed node
keeps its own next/prev (ghost) so a reader standing on it escapes either way.

**18. What a list edit records** (abridged from the header: `(void)` casts
and comments dropped):
```c
static inline int urcu_txn_sw_list_add_after_prepare(struct urcu_txn_sw_txn *txn,
		struct urcu_txn_sw_list_node *newp, struct urcu_txn_sw_list_node *pos)
{
	struct urcu_txn_sw_list_node *next = urcu_txn_sw_list_pending(txn, &pos->next);

	newp->prev = pos;               /* build: unreachable */
	newp->next = next;
	urcu_txn_sw_record_chain(txn, (void **) &pos->next, next, newp, URCU_TXN_SW_LIST_PROXY_TAG);
	urcu_txn_sw_record_chain(txn, (void **) &next->prev, pos, newp, URCU_TXN_SW_LIST_PROXY_TAG);
	return 0;
}
```
Two edges, one flip. `_rcu` wrappers = init + declare_disjoint + reserve(2) +
prepare + commit.

**19. One commit, two structures** (the abstract's composability claim):
```c
urcu_txn_sw_init(&txn);
urcu_txn_sw_reserve(&txn, 3);                                /* 1 hlist + 2 list edges */
urcu_txn_sw_hlist_add_head_prepare(&txn, &e->hnode, bucket);  /* findable */
urcu_txn_sw_list_add_after_prepare(&txn, &e->lru, &lru.node); /* ordered  */
ret = urcu_txn_sw_commit(&txn);
```
*E becomes findable and ordered at the same instant.* Same for hiding it.
(hlist `_prepare` asserts, debug, that the bracket stays rollbackable: reserve
before composing.)

**20. Read-your-own-writes.** Adjacent deletes P→E1→E2→N in one commit: the
second delete must see the *pending* `P->next`. `urcu_txn_sw_load()` returns the
pending new value; `record_chain()` fuses a second edit onto the record (keeps
the committed old, advances the new). Find = linear scan of a private array;
Bloom filter armed lazily for long write sets. Three obligations: search
through the txn load or before the first record; every anchor still live;
`urcu_txn_sw_declare_disjoint()` is a promise (`-DURCU_TXN_SW_DEBUG_DISJOINT`
traps a violation). Prior art: RYW is standard deferred-update STM; not claimed.

**21. `[opt]` hlist: one transacted edge.** Readers walk forward only, so an op
has one reader-visible edge; `pprev` is writer-only and plain-stored. A lone
insert/delete costs about an `rcu_assign_pointer()` (no proxy, no group, no
`call_rcu`) and still composes through `_prepare`.

### E. Cost (~6 min)

**22. Reader: zero loads, one branch.** Per node: rculist 8 instructions (2
branches, 2 loads); txn 10 (+1 test, +1 branch, **0 loads**). Bar chart, ratio
to rculist, no writer, two layouts (value at 192 readers; every curve is flat
in the reader count):

| arm | scattered (L2 hops) | walk order (L1 hops) |
|---|---|---|
| rculist + load | 0.964 | 0.932 |
| rculist + tag test (control) | 1.003 | 0.890 |
| **txn_sw_list** | **1.002** | **0.892** |
| rculist + load + test | 0.982 | 0.800 |

Message: on scattered nodes (a list allocated over time) the branch is **free**
— 1.002–1.003 of rculist at 1–192 readers, matching the control within 0.05%.
Only a list walked in allocation order that the prefetcher keeps in L1 shows it:
≈10.7%, the same as the control (10.6–10.8% against 10.4–11.2%; at 18809ea8 the
two were 2% apart, which was code layout). L3/DRAM-sized lists:
indistinguishable within noise (13% and 5%). Scaling 97.1–98.4% of ideal. Caveat to keep: few-% differences between the
load controls are code-level noise (P1 §7).

**23. Against schemes that give readers more.** (P1 tab:comparison + fig:readclass)

| | per-element state | extra loads | extra branches | reader guarantee | reader cost vs txn, scattered / walk |
|---|---|---|---|---|---|
| Existence | `eh_egi` field | 1 | 1 | per-element | 2–3% / 15–17% |
| RLU | object header | 1 | 1 | snapshot | 1–3% / 23–44% |
| MV-RLU | header + versions | ≥2 | ≥3 | snapshot | 1.43× / 3.01× (192 readers) |
| **This work** | **none** | **0** | 1 | never new-then-old | — |

*They charge readers more AND deliver more: a price, not a defect.* Existence
measured in its best layout (32-B element); MV-RLU global-clock config. Do not
rank write throughput across this boundary. The scattered figures are from two
readers up: at one reader existence and RLU read low in four runs of five in
the 2026-10-03 take (gaps of 7% and 9% there), unexplained and not quoted.

**24. Writer: 1.3–1.8×, and it is not the flip.** Big number **1.3–1.8×** (one
writer with readers, each under the mutex: scattered nodes 1.55–1.58 up to 4
readers and 1.61–1.80 beyond; walk order 1.34–1.39 up to 4 readers, 1.30 at 8,
1.26–1.52 up to 191). Figure: two bars on one cycle scale, the writer's thread
per update with ONE reader running, no mutex, sampled at retirement: rculist
129 cycles (write function 47, call_rcu 32, nodes 50); txn_sw_list 243 (write
function 70, call_rcu 38, nodes 21, **commit 19**, **descriptor slab 95**).
Mechanism: each update takes a fresh descriptor that must outlive a grace
period; more than half the slab's 95 cycles sit on four locked instructions
(pop lock taken and released, a compare-and-swap per pop and per push).

*Reworded 2026-10-04* (Mathieu: "four locked instructions" on the figure
"makes it look like this is necessary", while the rseq slab is closer to what
a kernel port would do, and the kernel "may be able to directly use kfree_rcu
and allocator rather than have a custom slab"). The slab segment's caption is
now "allocate, hand back"; under the figure: "Intrinsic: a fresh txn
descriptor per update, kept for a grace period. The commit: 19 cycles of 243."
and "Not intrinsic: this slab. Under rseq: no lock, no atomics. A kernel port
could use the allocator and `kfree_rcu()`." The kernel sentence is not P1's
and nothing about it is measured; slide 27 gets no line for it. The bars and
the headline are unchanged. The rseq build has ratios but no profile:
`HANDOFF-slab-profile.md` is the handoff for that investigation.

*What changed since the "about 2×" versions of this slide* (all 2026-10-03):
- Engine pin moved 18809ea8 → **2793224e**: batched descriptor retirement by
  default (`c21f5a38`), the record append inlined and `reserve(2)` no longer
  rounded up to 8 records (`79ef08e8`), the slab's cpu read from the rseq area
  (`4de8fabf`), no legacy barrier beside the slab freelist's cmpxchg
  (`2793224e`). Scattered-node ratio by step: 1.91–2.13 → 1.71–1.89 (batching)
  → 1.55–1.80.
- Controls at the pin: batch off (`-DURCU_TXN_SLAB_NO_BATCH`) 1.86–1.99
  scattered, 1.38–1.71 walk order, so batching is worth 9–23%; experimental
  rseq slab (`--enable-slab-rseq`) 1.47–1.50 scattered and 1.25–1.31 walk
  order up to 4 readers, no different from 8 readers up.
- **No ratio with no reader.** Earlier versions quoted 2.5–2.6× and profiled
  that configuration ("widest ratio, 3.0"). There rculist's writer defers nodes
  faster than the call_rcu worker on its own hardware thread frees them: the
  worker runs half the CPU without sleeping and the process grows 120–140 MiB/s
  (265 without the mutex). The transacted list stays flat. With 1–8 readers
  both are flat (`scripts/p1_steady_check.csv` in the benchmark tree). If asked
  "and with no readers?": say this, do not give a number.
- The profile is sampled at retirement (`EVENT=cycles`). The precise event on
  this machine charges a stall to the instructions that follow it and moved
  cost between categories from build to build; do not mix the two.
- Node allocation reads lower for the transacted writer (21 against 50 cycles).
  Not explained; do not claim it.

**25. Writers scale with fine-grained locks.** Line chart (P1 fig:writerscale): writers
on disjoint slots, plan unlocked → lock in ascending address order → validate →
commit; no readers. Lock bit in each node: **10.3 → 386 Mops/s at 192 writers
(38×)**; stripes 332; rculist under the same stripes 403; one global lock falls
from 12.0 to ~1 (**339×** below the bit lock). rculist leads 1.57× alone, 1.41×
at 2 writers and 1.03–1.28× from 4 to 96, level from 128 (0.94–1.04). Why rculist can't
use the in-node lock: its `prev` is unordered, so it would need a forward walk.
Caveats to say: each writer owns its slots (no retries), no lookup cost, memory
placement matters on this box (128 and 160 writers two-moded, up to 21%;
191→192 jump of 5–19% accepted). Both lists hold memory flat here.

### F. Kernel and close (~3 min)

**26. Dentry cache: bucket locks around SW commits.** Left: a userspace
model, two engines — the kernel's scheme (`d_seq` hand over hand,
`rename_lock`, `i_rwsem`) and bucket lock + SW txn (bit locks on the bucket
and child-list heads; a rename is one commit across both indexes; no `d_seq`,
no `rename_lock`, no lock in `readdir`). Right: `fig-dcache.tex`, 11 of the
22 rows of the benchmark tree's `figures/dcache_bucketlock_summary.png`
(engine ÷ baseline, log axis, a dot per measured point): on par (lookups at
10k–30k renames/s and at rest, allocating create/delete), faster (lookups at
100k–300k renames/s 1.18–1.85×, reverse walk 1.40–6.75×, readdir 1.11–3.38×,
create/delete in place 1.13–1.21×), slower (hits on objects being renamed
0.80–0.93×, at rest 0.90–0.96×), writers flat out (leaf 20.7–21.6×, directory
4.0–4.5×). Both "slower" rows are kept; the rows cut are on par or faster.
The hits row's low end was 0.84 in the 2026-10-02 sweep: the 160-reader point
(0.80) counts now because the engine's writers kept the pace there, and the
184-reader one dropped out because they did not. That region is noisy and its
cause is not established (benchmark README); if asked, say so.
Say "model" and "userspace" each time; the slide says userspace ratios are
not kernel evidence. Backup slide 33 has the baseline's fidelity, the
comparison rules, why it loses where it does, what the writers' lead
includes (`i_rwsem`, the cross-directory rename mutex) and what is not
modelled. Provenance in §7.
Which API, if asked (checked 2026-10-03 in `dcache_bucketlock.c` and the
engine tree): the model's index commits go through `rcu-txn.h`'s
single-writer path — `urcu_txn_store_sw()` + `urcu_txn_commit_sw()`, i.e.
`urcu_txn_desc_commit_sw()`: park by plain store, one release store of the
descriptor's status word, settle, retire after a grace period; no CAS, no
contention abort. Same park/flip/settle shape as slide 9, but it is NOT
`rcu-txn-sw.h`'s `urcu_txn_sw_commit()`, and its readers resolve with
`urcu_txn_resolve_record()` (record → descriptor status → old or new), not
through a proxy's group selector. The slide says "SW txn" and "one commit",
which hold; do not say the model uses the API of slides 13 and 17–19. Backup slide
33 states it ("How the model commits"), at Mathieu's request (2026-10-03):
the one place the deck names `rcu-txn.h`, and only its single-writer path.
Two limits of the model, to say out loud (Mathieu, 2026-10-03; on slide 26's
aside, slide 27's right column and backup 33; kernel facts checked in a
v7.3-rc5 tree, written up in the benchmark tree's
`experiments/dcache/README.md`, "What the model leaves out that a kernel port
needs"):
- **No reference count**, in either engine. Every walk stays inside one RCU
  read-side section; a handle is valid only while the caller keeps the object
  from being unlinked or evicted. The kernel leaves the RCU walk through
  `try_to_unlazy()`, which takes `d_lockref` before anything blocks, and
  `complete_walk()` ends every walk with a reference on its last component.
  A port needs that existence guarantee across blocking. Whether a count is
  the right tool or whether this is a use for hazard pointers is OPEN — not
  evaluated; say it as a question.
- **No `i_rwsem`** in the new engine: its `readdir` takes no lock, so the
  dentry cache stops needing it. But `i_rwsem` is the VFS's directory lock,
  held across the filesystem's own methods (`locking.rst`: `lookup` shared;
  `create`, `link`, `unlink`, `mkdir`, `rmdir`, `rename` exclusive; taken in
  `__start_dirop()` before the filesystem is called), so filesystems rely on
  it as mutual exclusion. Part of the writers' lead is that lock; a port
  that leaves the VFS alone does not get that part. The share is not
  isolated for renames (no engine arm keeps the baseline's locks).

**27. What a kernel port needs** `[Mathieu to confirm/fill: port status]`.
Grounded items: a spare low bit in the slot (list pointers are aligned); commit
fails only on OOM and before anything is parked → reserve up front in
non-sleeping context; one `call_rcu()` per multi-edge commit (batchable);
exclusion validator as a debug option. Where it would land: rculist reverse
walks (list_bidir users), cross-structure publish (hash + LRU), pinned objects
whose back edges must move in place. Right column, added 2026-10-03, "For the
dentry cache, also": reference counts, or hazard pointers? and `i_rwsem`:
filesystems rely on it (the two limits under slide 26; they are about the
model, not the facility). The slide is full: filling the placeholder means
cutting something.

**28. What it is not.** Not STM (no snapshot, no opacity); exclusion is the
embedder's (per slot, locks); tag contract; commit width grows with edges (a tall tower
commits many records where existence flips one group); writer 1.3–1.8×.

**29. Summary + availability.** Paper: `[arXiv link — TBD]`. Code:
github.com/compudj/userspace-rcu-dev @ `2793224e` (on GitHub since 2026-10-03), `include/urcu/`:
`rcu-txn-sw.h`, `rcu-txn-sw-list.h`, `rcu-txn-sw-hlist.h`, `rcu-txn-status.h`.
Questions.

### Backup slides / anticipated questions (answers are P1's)

- *Why not a seqcount?* Read-side retry on every traversal; detects after the
  fact. Here a reader never retries (and gets no snapshot either).
- *Why not copy?* Cost scales with the region; a pinned node can't be copied.
- *Isn't this existence?* Existence adds a per-element field (+1 load +1
  branch) and gives a stronger per-element guarantee; we add no per-element
  state. 2–3% / 15–17%.
- *HTM?* Commodity HTM may abort → needs a fallback that meets the same
  problem; s390 constrained txns: ≤32 instructions / 256 bytes.
- *Does the tag test need a barrier?* No: the proxy's immutable fields are
  reached through the dependency; only the selector is loaded with acquire, and
  only when parked.
- *Two writers race?* Silent corruption by contract; the validator catches it.
- *ABA?* Resolution goes through the descriptor, not the slot value; slot-value
  A-B-A is inert (P1 §8.1).
- *Isn't this MCAS?* (added 2026-10-03) The descriptor-and-status shape is:
  Harris, Fraser, Pratt, DISC 2002, and P1 §11 claims none of it. The nearest
  prior art is **Guerraoui, Kogan, Marathe, Zablotchi, "Efficient Multi-word
  Compare and Swap", DISC 2020 (arXiv 2008.02527)**: lock-free, helping,
  plain-CAS install with no RDCSS, `k+1` CAS, unlock **deferred** to
  reclamation by epochs they call similar to RCU, readers that do not write
  unless they meet an in-flight operation, and a proof that a lock-free
  disjoint-access-parallel k-CAS must CAS at least `k` locations.
  - Against the talk's SW engine: **zero CAS** (exclusion is outside that
    bound's hypotheses) and **eager settle** (their deferral saves `k` CASes
    and costs readers an indirection after every commit; a plain-store settle
    has little to save). P1 §11.1, §9.4.
  - The abstract says "novel". Do **not** defend the descriptor mechanism as
    new. What P1 §11.3 says it has not found is a marker that is transient,
    that RCU readers resolve through without waiting or writing, and that adds
    no per-element state.
  - The MW engine stays out of the talk (§2 item 4). If asked: it is the
    engine their paper is closest to — both install by plain CAS with no
    RDCSS — and it differs by settling at once and deciding with a store. It
    is not lock-free; theirs is. P2 was re-scoped on this the same day
    (`p2-sole-driver-mcas/SCOPE.md`, section dated 2026-10-03).
  - Where it is in the deck: backup slide 30 (the Q&A and its note), and one
    speaker note each on slide 8 (the flip-latch: lineage) and slide 9
    (lifecycle: "why settle at all?"). No main-line slide changed.
- *STM reads can opt out of the barrier.* (added 2026-10-04, on Mathieu's
  concern that slide 16's STM column claimed for STM in general what holds
  for some STMs.) They can, and the column is "Opaque STM" now. Read in the
  papers that day:
  - **Kestor, Dalessandro, Cristal, Scott, Unsal, "Interchangeable Back Ends
    for STM Compilers", TRANSACT 2011**: STAMP's original code "uses hand
    instrumentation of (only) 'important' loads and stores"; Intel's
    `transaction [[waiver]]` extension disables "instrumentation of many
    'unimportant' loads and stores"; a `transaction_pure` function runs
    inside an atomic transaction "without instrumentation on its loads and
    stores". So the programmer does choose, per load.
  - Weak atomicity (the term is Blundell, Lewis, Martin, IEEE CAL 2006; the
    paper itself was not read, only its abstract): reads outside any
    transaction are not instrumented.
  - **Howard and Walpole, "A Relativistic Enhancement to Software
    Transactional Memory", HotPar 2011**: relativistic (RCU) readers run
    "completely outside the transactional system", a SwissTM modified to
    replay a commit's writes in program order with the memory barriers and
    grace periods of the relativistic algorithm. It requires weak atomicity
    ("A strongly atomic transactional memory system would include the
    relativistic reads as part of its atomicity guarantee. This would impact
    read performance.") and says "in our system, readers can see partially
    completed commits". The nearest "RCU readers, transactional writers"
    work, and the contrast is the talk's claim: there the structure is kept
    always-consistent by write order and grace periods inside the commit;
    here N slots flip at once and no grace period is waited for.
  - What holds against all of them: a read that opts out of the barrier is
    not isolated. The cost follows the guarantee, which is the slide's lead.
  - **P1 says the same broad things and is NOT changed** (§8 item 12).

## 6. Engine API facts (verified at 18809ea8; names re-checked at 2793224e, `include/urcu/`)

`rcu-txn-sw.h` — two layers.
- Low level: `struct urcu_txn_sw_group { unsigned long selector; }`,
  `struct urcu_txn_sw_proxy { void *ptr[2]; struct urcu_txn_sw_group *group; }`,
  `urcu_txn_sw_group_init`, `urcu_txn_sw_proxy_init`,
  `urcu_txn_sw_is_proxy(v, tag)`, `urcu_txn_sw_untag(v, tag)` (subtracts),
  `urcu_txn_sw_proxy_get(proxy)`, `urcu_txn_sw_resolve(v, tag)`,
  `urcu_txn_sw_group_commit(group)` (release store of 1).
- Txn layer: `struct urcu_txn_sw_txn`; `urcu_txn_sw_init`,
  `urcu_txn_sw_init_inline` (lone-edge, caller storage), `urcu_txn_sw_reserve(t,
  cap)`, `urcu_txn_sw_record(t, slot, old, new, tag)` (blind append;
  pairwise-distinct slots), `urcu_txn_sw_load(t, slot, tag)` (RYW),
  `urcu_txn_sw_record_chain(...)` (fusing), `urcu_txn_sw_declare_disjoint(t)`,
  `urcu_txn_sw_install(t)` (white-box), `urcu_txn_sw_commit(t)` /
  `urcu_txn_sw_commit_flavor(t, call_rcu_fn, flavor)` → `enum urcu_txn_status`
  (OK or MEMORY_ERROR; the third argument since `e3241ffa`, NULL allowed).
  Debug knobs: `URCU_TXN_SW_EXCL_VALIDATE`, `URCU_TXN_SW_DEBUG_DISJOINT`; build
  option `URCU_TXN_SLAB_NO_BATCH` (batching is the default since `c21f5a38`);
  configure option `--enable-slab-rseq` (experimental). `urcu_txn_sw_reserve(t,
  n)` takes the smallest slab class that holds n since `79ef08e8` (a list op's
  descriptor is 224 bytes, not 416).
- `rcu-txn-sw-list.h`: `struct urcu_txn_sw_list_node { next, prev }`,
  `struct urcu_txn_sw_list_head { node }`, `URCU_TXN_SW_LIST_PROXY_TAG 1UL`,
  `urcu_txn_sw_list_{next,prev}_rcu`, `_pending`, `add_after/add_before/del/
  replace` in `_prepare` and `_rcu` forms, `add_rcu`, `add_tail_rcu`,
  iterators `for_each[_entry][_reverse]_rcu`.
- `rcu-txn-sw-hlist.h`: `URCU_TXN_SW_HLIST_TAG 1UL`, single-pointer head,
  `insert_at_slot/add_head/add_after/add_before/del/replace_prepare`, `_rcu`
  forms, `for_each[_entry]_rcu`.

**Two stale header comments found while reading (engine doc fixes, low
priority; both still there at 18809ea8, checked 2026-10-03:
`rcu-txn-sw.h:275`, `rcu-txn-sw-hlist.h:332`):**
1. `rcu-txn-sw.h`, the "Multi-edge flip transaction" block says "nothing
   observes buffered writes (there are no transactional loads at all)". The
   stale half is "nothing observes buffered writes": `urcu_txn_sw_load()`
   returns this txn's pending new value (RYW) and `record_chain()` fuses onto
   it. "No transactional loads" still holds if it means *validated* loads:
   `urcu_txn_sw_load()` records nothing, enters no read set and is not
   validated at commit (under exclusion there is nothing to validate; P1
   §6.4). Suggested fix: "record() itself does no same-slot reconcile;
   urcu_txn_sw_load()/record_chain() give read-your-own-writes; no load is
   validated at commit (there is no read set)."
2. `rcu-txn-sw-hlist.h`, `insert_at_slot_prepare`'s comment says it "Records …
   the writer-only &succ->pprev edge"; the code plain-stores `succ->pprev`
   (writer-only bookkeeping), it does not record it.
Worth fixing before the talk if the audience is pointed at the headers.

## 7. Numbers: provenance and caveats

All from P1 at engine pin **2793224e** (re-take of 2026-10-03: benchmark tree
`24dcb17`, with `af3dbad` adding `scripts/p1_figdata.py` and `p1_numbers.py`,
which regenerate P1's `data/fig-*.csv` and recompute every figure §7 quotes;
the engine branch is on GitHub at that commit). Setup: 2× AMD EPYC 9654 (96 cores/socket, 24 NUMA nodes),
worker i pinned to core i, ≤192 workers (one-writer sweep stops at 191
readers), liburcu QSBR, per-CPU call_rcu workers, jemalloc per-CPU arenas;
10,000-node list, 200-node churn; median of five 3 s runs after 4 s untimed
warm-up. Data: `p1-sw-flip-latch/data/fig-*.csv`; text: P1 §7.

- Always quote the reader-cost numbers **with their layout** (scattered vs walk
  order). The 10.7% is a property of an L1-resident arena-order list.
- Writer scaling: 64-B-aligned nodes, CHURN = 64 × writers, no readers, 2 s
  windows after warm-up; up to 96 writers memory on socket 0.
- These are publication-grade (measured on the quiet machine at the pin, the
  per-point machine log clean). Do not replace them with new runs without
  Mathieu's say-so (rules below).
- Engine trees for P1 must be configured with the benchmark Makefile's
  `URCU_CFLAGS` (`-O2 -DNDEBUG …`). The 18809ea8 tree was configured bare, so
  the numbers this deck carried before ran liburcu's own code at `-g -O2` with
  assertions (measured effect: none).
- The dentry-cache sweep below is at P1's pin, `2793224e`, since 2026-10-03,
  and built `-DNDEBUG`: until then the benchmark's engine arms ran liburcu's
  inline assertions and the seqlock baseline, which has none, did not. The
  re-take changed nothing a slide says: an engine's own throughput is within
  1% of the `c21f5a38` sweep in the median of 171 of 197 panel-and-engine
  groups, and slide 26's eleven medians moved by at most 1.6% (directory
  capacity 4%).

**Slide 26 and backup 33 (dentry cache)** are not P1's: benchmark tree
`efficios-trie-benchmark` at `253d8e4`, sweep `3225b8ec0e79-2793224e`
(2026-10-03, liburcu `2793224e`, no assertions), same machine. It replaced
sweep `c03704139064-c21f5a38` (2026-10-02, benchmark tree `3a79ed3`).
`make dcache-data` (`dcache-summary.py`) runs that tree's own
`scripts/plot_dcache_bucketlock_summary.py` up to its drawing code and writes
`data/dcache-summary{.csv,-points.csv,-macros.tex}`, which are committed (the
laptop has no benchmark tree). The chart, `\dcrange{key}` in the text and the
sweep id in the notes all read those files: no ratio is typed. The script
owns which rows appear and in what order; `fig-dcache.tex` owns their wording.
That tree's `scripts/check_dcache_figures.sh` reports every figure STALE on a
checkout without `urcu-txn-build/` (it cannot name the liburcu commit and
prints `-unknown`); the source hash it prints still matches the sweep's.

## 8. Open items

1. ~~Dentry-cache section~~ — **in, 2026-10-03** (§2 item 5, slide 26).
2. Kernel-port status for slide 27 (placeholder).
3. P1 public link (arXiv?) for slide 29 (placeholder).
4. ~~Format~~ — **decided 2026-09-30: Beamer** (§10). The claude.ai artifact
   stays empty.
5. Optional engine header doc fixes (§6).
6. ~~Slides 24–25 predate the batching default~~ — **done 2026-10-03**:
   Mathieu chose the re-take, then three engine changes, then a full re-take of
   P1 §7 at `2793224e`; slides 22–25, 27–29 and P1 follow it (§5 slide 24).
7. ~~Push `urcu-txn-dev`~~ — **done 2026-10-03** (GitHub tip `2793224e`).
8. ~~Commit the re-take~~ — **done 2026-10-03**: benchmark tree `24dcb17` and
   `af3dbad`; `articles` `e71e58f` (P1) and the deck commit that carries this
   line. Neither tree is pushed.
9. ~~P1's four changed claims~~ — **read by Mathieu 2026-10-03, kept as
   written**: no ratio with no reader; the profile at one reader, in cycles;
   traversal order "up to 4%"; the remedies paragraph quoting the experimental
   rseq slab. Decided the same day: the headline stays the DEFAULT build (the
   slab's freelist with atomics), the rseq slab stays a remedy.
10. ~~Re-sweep the dentry cache at `2793224e`~~ — **done 2026-10-03**
    (3 h 27 min, no conservation failure, every figure fresh), built
    `-DNDEBUG`; benchmark tree `253d8e4`; slides 26 and 33 read the new data
    (§7). Nothing moved but the hits row's low end, 0.84 → 0.80 (§5 slide 26).
11. Dentry cache, for a kernel port (Mathieu, 2026-10-03; §5 slide 26): how to
    hold a dentry across blocking — a reference count, or hazard pointers —
    is not evaluated; and the share of the writers' lead that is `i_rwsem`
    is not isolated (it would take an engine arm that keeps the baseline's
    two locks; not built, not run).
12. P1 and STM "in general" (Mathieu, 2026-10-04; §5, "STM reads can opt
    out"). Not edited. Three statements are broader than the sources allow:
    sec. 6.4's "What an STM does instead" ("Its read barrier sits on *every*
    read"; "Where the instrumentation itself is reduced, it is the compiler
    that reduces it, and it does not ask" — Intel's `[[waiver]]`,
    `transaction_pure` and STAMP's hand instrumentation are the programmer
    choosing); sec. 10.2's "STM instruments every read"; sec. 3.4's "weaker
    than STM". And Howard and Walpole (HotPar 2011) is not cited. The work
    is handed off in `p1-sw-flip-latch/HANDOFF-stm-scope.md`.

13. Profile of the descriptor slab with and without rseq (Mathieu,
    2026-10-04; §5 slide 24): how much of the slab's 95 cycles the rseq slab
    removes, and what is left. Handoff for the benchmark machine:
    `HANDOFF-slab-profile.md`. No run without Mathieu's go-ahead.

## 9. Standing rules (restated for the laptop session)

- **Never start a benchmark without Mathieu's explicit go-ahead.** Results from
  runs on the shared machine after 2026-07-28 are reference-only unless he
  confirms the box was quiet; paper benchmarks run a 4 s untimed warm-up.
- **Commits: `Signed-off-by: Mathieu Desnoyers` only** — never add
  `Co-Authored-By` or `Claude-Session` trailers.
- A rejected edit may already have written files: `git diff` before continuing.
- Series framing guardrails (P1 README): never claim "serializable",
  "opacity" or "STM" for the mechanism; "linearizable" scoped to the commit;
  write "a reader is not a transaction **of any kind**" (never "a reader is not
  a pseudo-transaction"); "never new-then-old", never "causal"; "flip-latch",
  never a bare "latch". The talk *title* says "bridging RCU and STM" — fine as
  positioning, not as a claim of STM semantics.
- Use the machine lightly while benchmarks run (no builds/sweeps without
  asking; LaTeX builds under `nice -n 19 ionice -c3`).

## 10. The Beamer deck (built 2026-09-30, laptop)

`make` builds `main.pdf` (XeLaTeX, two passes, under nice/ionice) and then
runs four checks: framing words (§9; the current hits are all deliberate
"no opacity"-type statements), placeholders still in the deck, overfull
boxes (i.e. content off a slide; currently none), and frames whose body opens
with a `{...}` group -- beamer silently takes that as the subtitle, and the
template shows none, so the content vanishes without a warning. `make notes` builds
`main-notes.pdf`, each slide followed by its speaker notes (the caveats of §5
and §7 live there).

- Slides 1–29 follow §5 one-for-one and keep its numbering (the placeholders
  point at it). Backup, after `\appendix`: 30 anticipated questions, 31
  Triplett's reverse-publish rule (the `[opt]` of slide 15), 32 P1's
  one-writer-with-readers curves, 33 the dentry-cache model and where it
  loses (added last, so nothing was renumbered).
- Charts read `../p1-sw-flip-latch/data/*.csv` in place, and the printed
  endpoint values come from the CSVs' last rows, so a re-take of P1's data
  flows into the slides with no hand edits.
- Figures are slide-sized re-lays of P1's TikZ (`fig-*.tex` here), not
  `\input`s of P1's files: P1's are paper-sized floats with long captions.
  If a P1 figure changes, port the change by hand.
- Fonts: IBM Plex (installed on the laptop 2026-09-30; the deck is laid out
  in it), else Lato + Noto Sans Mono as a fallback. Debian's Plex TTFs name
  the 600 weight "SmBld", upstream's OTFs "SemiBold"; the preamble takes
  either. A font change moves line breaks: rerun `make` and read the checks.
- Section dividers were replaced by a small section kicker above each title
  (no slot time to spare).
- Slide 18's lead ("Two edges, one flip") became part of its title, to fit.
- Slide 27 cross-checked against P1 (which has no kernel section; every item
  maps a P1 statement onto the kernel). Two changes from §5: the reserve line
  now follows P1 §4.5 ("before the first irreversible step"), with "under a
  spinlock" as the kernel reading; and "list_bidir users" became "a coherent
  reverse walk for rculist", because P1 §2.4 says list_bidir's sole caller
  takes one hop and never needs coherence. Worth Mathieu's look.
  The code on slides 10, 13 and 17–19 is §5's text (verified at 18809ea8 on the
  other machine), re-wrapped to fit; every identifier the deck names exists at
  2793224e (checked 2026-10-03), and no listing shows `commit_flavor`'s
  signature, the one that changed. Re-checked 2026-10-03 against the engine
  tree, `~/doc/userspace-rcu`, branch `urcu-txn-dev` at 18809ea8 (also the tip
  of `github-dev/urcu-txn-dev`): every listing matches the headers, as do the
  signatures and the commit's `nr <= 1` path, the 16-byte record alignment and
  the debug knobs. The dcache sweep's liburcu is `2793224e` too since 2026-10-03.
