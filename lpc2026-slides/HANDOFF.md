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
   2026-10-02) and Mathieu cleared the figures for the talk. One slide (26)
   and one backup slide, on the bucket lock + SW txn engine only: the MW txn
   arms of the same benchmark fall under decision 4 and are not shown.
6. **Charts are static** (projected + PDF upload): no hover/tooltips; print the
   numbers that matter on the chart.

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
Numbers are P1's, engine pin 18809ea8 (provenance in §7).

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

### B. The model (~6 min)

**7. A pseudo-transaction.** Definition: a frozen set of {slot, old, new}
records made visible by one commit step. Table "journaling FS vs
pseudo-transaction" (P1 tab:fssense): journal txn closed ↔ record set frozen;
commit record ↔ commit step; old before / new after; never a partial batch ↔ no
slot and no instant is torn; readers not transactional ↔ plain RCU readers;
atomicity, not isolation ↔ atomicity, not opacity. *"Pseudo-" is a
disambiguation, not an apology.*

**8. What it provides, and what it does not.** Provided: write-set atomicity;
no tearing; the commit linearizes at one point (scoped to the WRITE);
cross-structure atomicity — unit = one pseudo-txn (two commits = two
linearization points).
Not provided: **a reader is not a transaction of any kind**; no opacity, no
multi-read snapshot; no read validation in SW (under exclusion nothing to
validate against).

**9. Never new-then-old.** Selector written once 0→1, never back ⇒ a reader
resolving slots of one commit *along a dependency chain* sees o…o,n…n, never
n then o. Scope: an address dependency or an acquire; two independently-reached
slots (cached pointer, sibling subtrees) owe an acquire
(`-DURCU_DEREFERENCE_USE_VOLATILE` on weak ordering). Kernel aside: arm64 +
`CONFIG_LTO` already promotes `READ_ONCE()` to acquire for this reason.
New-then-old is exactly what forces seqcount-style read-side remedies; the
model forbids it by construction. `[opt]` Triplett's reverse-publish-order rule
for split edits.

**10. Between RCU and STM** (the title's bridge). Three columns: RCU — one slot
atomic, readers free | pseudo-txn — N slots atomic to readers, readers
uninstrumented, write set only | STM — read+write sets, isolation/opacity, read
barrier on every read. *Isolation is a read-side cost once updates mutate in place;
we decline to charge readers for it.* Honest asterisk: RLU/existence give
readers strictly more, and charge more.

### C. The mechanism (~6 min)

**11. The flip-latch: one level of indirection.** Diagram (P1 `fig-fliplatch`):
slots → tagged proxy {old, new, group} → group {selector}. *Every proxy in a
group reads the same selector; one release store flips the set.*

**12. Lifecycle.** Table (P1 tab:lifecycle): before / Build / Install /
**Commit** / Settle / after; the reader's column reads o, o, o, **n**, n, n.
Install and settle both rewrite the slot yet change nothing a reader resolves;
settle *is* the uninstall; then `call_rcu()` the block.

**13. The read side is one branch.** (verified, 18809ea8)
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

**14. Tags.** Parked slot = `(record_address | tag)`; recognized iff
`(v & tag) == tag`. **Per-record tag**, because one commit may span structures
with different encodings (bit 0 vs a reserved nibble) — cross-structure
atomicity forces it. Records 16-byte aligned → 4 low bits. Store the tag, not a
tagged pointer → the descriptor can grow by realloc. Contract: no legitimate
slot value may carry the tag pattern (debug build asserts).

**15. Exclusion is per slot.** No install CAS, no conflict detection, no abort —
that is why it is cheap. Two writers on one slot silently corrupt;
`-DURCU_TXN_SW_EXCL_VALIDATE` aborts the process on a violation (free when off).
Fine-grained locks (per bucket, per node) are the ordinary way to meet it:
writers on disjoint slots commit concurrently. Commit fails only for want of
memory; `urcu_txn_sw_reserve()` up front rules that out.

### D. The API (~8 min)

**16. The API on one slide.** (names verified at 18809ea8)
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
| rculist + tag test (control) | 1.003 | 0.894 |
| **txn_sw_list** | **1.003** | **0.872** |
| rculist + load + test | 0.982 | 0.800 |

Message: on scattered nodes (a list allocated over time) the branch is **free**
— 1.002–1.003 of rculist at 1–192 readers, matching the control within 0.06%.
Only a list walked in allocation order that the prefetcher keeps in L1 shows it:
≈12.7% (control 10.7%). L3/DRAM-sized lists: indistinguishable within noise.
Scaling 97.4–98.4% of ideal. Caveat to keep: few-% differences between the
load controls are code-level noise (P1 §7).

**23. Against schemes that give readers more.** (P1 tab:comparison + fig:readclass)

| | per-element state | extra loads | extra branches | reader guarantee | reader cost vs txn, scattered / walk |
|---|---|---|---|---|---|
| Existence | `eh_egi` field | 1 | 1 | per-element | 3% / 15% |
| RLU | object header | 1 | 1 | snapshot | 2–6% / 22–44% |
| MV-RLU | header + versions | ≥2 | ≥3 | snapshot | 1.40× / 2.91× (192 readers) |
| **This work** | **none** | **0** | 1 | never new-then-old | — |

*They charge readers more AND deliver more: a price, not a defect.* Existence
measured in its best layout (32-B element); MV-RLU global-clock config. Do not
rank write throughput across this boundary.

**24. Writer: about 2×, and it is not the flip.** Big number **~2×** (one writer
with readers: 1.9–2.1 on scattered nodes; walk order 1.92 → 1.37 at 8 readers,
1.4–1.7 up to 191; 2.5–2.6 with no reader). Profile of the gap (no reader, no
mutex, widest ratio 3.0): `call_rcu` plumbing **46%**, staging **21%**,
descriptor slab **20%**, commit itself **11%**. Mechanism: one extra
grace-period-deferred free per update (the proxy block); call_rcu entered 3× as
often as plain RCU. Remedies: rseq-supplied CPU id / rseq enqueue in call_rcu
(helps plain RCU too), `URCU_TXN_SLAB_BATCH` (opt-in, off in these numbers),
single-edge commits need no proxy.

**25. Writers scale with fine-grained locks.** Line chart (P1 fig:writerscale): writers
on disjoint slots, plan unlocked → lock in ascending address order → validate →
commit; no readers. Lock bit in each node: **8.0 → 377 Mops/s at 192 writers
(47×)**; stripes 302; rculist under the same stripes 379; one global lock falls
from 8.9 to ~1 (**355×** below the bit lock). rculist leads 1.11–1.36× from
16–128 writers, level from 160 (0.91–1.01). Why rculist can't use the in-node
lock: its `prev` is unordered, so it would need a forward walk. Caveats to say:
each writer owns its slots (no retries), no lookup cost, memory placement
matters on this box (bistable across sockets; 191→192 jump accepted).

### F. Kernel and close (~3 min)

**26. Dentry cache: bucket locks around SW commits.** Left: a userspace
model, two engines — the kernel's scheme (`d_seq` hand over hand,
`rename_lock`, `i_rwsem`) and bucket lock + SW txn (bit locks on the bucket
and child-list heads; a rename is one commit across both indexes; no `d_seq`,
no `rename_lock`, no lock in `readdir`). Right: `fig-dcache.tex`, 11 of the
22 rows of the benchmark tree's `figures/dcache_bucketlock_summary.png`
(engine ÷ baseline, log axis, a dot per measured point): on par (lookups at
10k–30k renames/s and at rest, allocating create/delete), faster (lookups at
100k–300k renames/s 1.20–1.83×, reverse walk 1.41–7.16×, readdir 1.11–3.67×,
create/delete in place 1.14–1.23×), slower (hits on objects being renamed
0.84–0.93×, at rest 0.90–0.95×), writers flat out (leaf 20.8–21.5×, directory
4.1–4.5×). Both "slower" rows are kept; the rows cut are on par or faster.
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
contention abort. Same park/flip/settle shape as slide 12, but it is NOT
`rcu-txn-sw.h`'s `urcu_txn_sw_commit()`, and its readers resolve with
`urcu_txn_resolve_record()` (record → descriptor status → old or new), not
through a proxy's group selector. The slide says "SW txn" and "one commit",
which hold; do not say the model uses the API of slides 16–19. Backup slide
33 states it ("How the model commits"), at Mathieu's request (2026-10-03):
the one place the deck names `rcu-txn.h`, and only its single-writer path.

**27. What a kernel port needs** `[Mathieu to confirm/fill: port status]`.
Grounded items: a spare low bit in the slot (list pointers are aligned); commit
fails only on OOM and before anything is parked → reserve up front in
non-sleeping context; one `call_rcu()` per multi-edge commit (batchable);
exclusion validator as a debug option. Where it would land: rculist reverse
walks (list_bidir users), cross-structure publish (hash + LRU), pinned objects
whose back edges must move in place.

**28. What it is not.** Not STM (no snapshot, no opacity); exclusion is the
embedder's (per slot, locks); tag contract; commit width grows with edges (a tall tower
commits many records where existence flips one group); writer ~2×.

**29. Summary + availability.** Paper: `[arXiv link — TBD]`. Code:
github.com/compudj/userspace-rcu-dev @ `18809ea8`, `include/urcu/`:
`rcu-txn-sw.h`, `rcu-txn-sw-list.h`, `rcu-txn-sw-hlist.h`, `rcu-txn-status.h`.
Questions.

### Backup slides / anticipated questions (answers are P1's)

- *Why not a seqcount?* Read-side retry on every traversal; detects after the
  fact. Here a reader never retries (and gets no snapshot either).
- *Why not copy?* Cost scales with the region; a pinned node can't be copied.
- *Isn't this existence?* Existence adds a per-element field (+1 load +1
  branch) and gives a stronger per-element guarantee; we add no per-element
  state. 3% / 15%.
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
    speaker note each on slide 11 (the flip-latch: lineage) and slide 12
    (lifecycle: "why settle at all?"). No main-line slide changed.

## 6. Engine API facts (verified at 18809ea8, `include/urcu/`)

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
  `urcu_txn_sw_commit_flavor(t, call_rcu_fn)` → `enum urcu_txn_status`
  (OK or MEMORY_ERROR). Debug knobs: `URCU_TXN_SW_EXCL_VALIDATE`,
  `URCU_TXN_SW_DEBUG_DISJOINT`; build option `URCU_TXN_SLAB_BATCH`.
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

All from P1 at engine pin **18809ea8** (articles `57a6f4a`, writer-scaling
figure `5522c28`). Setup: 2× AMD EPYC 9654 (96 cores/socket, 24 NUMA nodes),
worker i pinned to core i, ≤192 workers (one-writer sweep stops at 191
readers), liburcu QSBR, per-CPU call_rcu workers, jemalloc per-CPU arenas;
10,000-node list, 200-node churn; median of five 3 s runs after 4 s untimed
warm-up. Data: `p1-sw-flip-latch/data/fig-*.csv`; text: P1 §7.

- Always quote the reader-cost numbers **with their layout** (scattered vs walk
  order). The 12.7% is a property of an L1-resident arena-order list.
- Writer scaling: 64-B-aligned nodes, CHURN = 64 × writers, no readers, 2 s
  windows after warm-up; up to 96 writers memory on socket 0.
- These are publication-grade (measured on the quiet machine at the pin). Do
  not replace them with new runs without Mathieu's say-so (rules below).

**Slide 26 and backup 33 (dentry cache)** are not P1's: benchmark tree
`efficios-trie-benchmark` at `3a79ed3`, sweep `c03704139064-c21f5a38`
(2026-10-02, liburcu `c21f5a38`), same machine.
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
  Triplett's reverse-publish rule (the `[opt]` of slide 9), 32 P1's
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
  The code on slides 13 and 16–19 is §5's text (verified at 18809ea8 on the
  other machine), re-wrapped to fit. Re-checked 2026-10-03 against the engine
  tree, `~/doc/userspace-rcu`, branch `urcu-txn-dev` at 18809ea8 (also the tip
  of `github-dev/urcu-txn-dev`): every listing matches the headers, as do the
  signatures and the commit's `nr <= 1` path, the 16-byte record alignment and
  the debug knobs. The dcache sweep's liburcu, `c21f5a38`, is in neither.
