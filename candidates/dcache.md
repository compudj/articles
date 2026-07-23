# Candidate paper: dentry cache over rcu-txn

**Status:** novelty inventory for a future paper. **Capture, not disclosure** —
nothing here is published yet; the point is a precise catalogue so the eventual
paper is a full *enabling* disclosure rather than a hint. Same reserve-don't-burn
discipline as the rest of the series.

**Working title (Mathieu):** *Improvements to the Linux kernel dentry cache with
RCU pseudo-transactions.* Framing still open — kernel-facing ("here is a better
dcache design") vs. userspace demonstrator ("here is what porting to urcu-txn
would win the kernel"). The artifact is a userspace reimplementation, so the honest
default is the demonstrator framing.

**Primary sources** (impl + benchmarks in `efficios-trie-benchmark/experiments/dcache/`,
figures at the benchmark-tree root `efficios-trie-benchmark/figures/`):
- `rename-shell-transition.md` — the base design note (shell/fold, walk causality,
  loop check, readdir; authoritative for everything except the writer engine).
- `design/dcache-dlm-sw.md` — the **writer-engine swap**: bucket lock + SW txn.
- `design/mixed-sw-mw-txn.md` — the mixed SW/MW record alternative (the one the
  metrics rejected; kept as the strongest *Variations and Alternatives* datapoint).
- `dcache_bucketlock.c` — the **converged implementation** (bucket lock + SW txn,
  fold-lock default). `dcache_txn.c` — the earlier all-MW-MCAS implementation.
  `dcache_seqlock.c` — the faithful kernel-style baseline (RCU hlist + global
  `rename_lock` + per-dentry `d_seq`), now also carrying a vendored kernel
  `rw_semaphore` per-dir arm.
- Figures: `dcache_{s3,churn_scaling,readdir_churn,optype,height,swmw}.png`.

**One-line thesis:** *the dentry cache is the hardest RCU user in the kernel, and
the thing that makes it hard is `rename`; can urcu-txn dissolve the kernel's two
global consistency mechanisms — `rename_lock` (whole-walk causality) and per-dentry
`d_seq` (per-component coherence) — without giving up the kernel bit-lock's cheap
add/unlink writer?* Answer, empirically: `d_seq` dissolves outright; the
global-retry role of `rename_lock` dissolves under the per-node/mark arm; and the
writer path is kept on the kernel bit-lock's budget by committing SW under a bucket
lock rather than by an MW MCAS.

> Novelty claims below are **candidates** — they still need a prior-art sweep of
> the filesystem/concurrency literature. Mathieu is the authority on what is
> genuinely new; this file catalogues what *looks* new and why.

---

## N0. The converged writer engine — bucket lock + SW txn, fold-lock chain (NEW headline)
*(design notes `dcache-dlm-sw.md`, `mixed-sw-mw-txn.md`; impl `dcache_bucketlock.c`)*

The design **converged on a writer engine chosen by the metrics, not a priori**
(2026-07-22). It is the smallest instance of the DLM+SW pattern: **reuse the Linux
kernel per-bucket bit-lock for the write path, but commit the existing transaction
via the SW form (plain stores) instead of the MW MCAS** — keeping the MW-txn
*reader* win untouched. So: the kernel's cheap writer *and* the txn's wait-free
reader, by construction.

**The hypothesis (`dcache-dlm-sw.md` §0).** On the kernel-faithful sweep the split
is clean: the bit-lock baseline **wins the write path** ~1.4–2× (a bit-lock +
hlist splice beats per-op MCAS), while the MW-txn **wins the read path** ~1.3–1.6×
(inline compare, wait-free, no `d_seq` spin). If the writer cost is dominated by the
atomic-RMW count of the MCAS commit, the fix is not to change *what* the dcache does
but *how the commit excludes writers*: acquire the bucket-head lock (1–2 CAS), then
commit SW (plain stores + one selector). Add/unlink fall to the bit-lock's two-CAS
budget; the reader is byte-for-byte unaffected.

**The durable argument (`dcache-dlm-sw.md` §0.2).** Beyond today's add/unlink,
DLM+SW commit cost is **flat in transaction size**: O(distinct locked heads) atomic
RMWs + O(records) *plain stores* + one selector, vs MW MCAS = O(records) CAS (+
helping on hot shared slots). The gap widens as an op touches more records — the
**LRU is the concrete next driver** (2–4 hot shared list slots re-pointed per
add/unlink/lookup, the MCAS worst case). Honest bound: the asymptotic win needs the
added records to *cluster under few locks* (an LRU list = one lock); a scattered
write-set pushes the lock count toward the record count (still trades
`cmpxchg+helping` for `lock+plain-store`, but not the asymptote).

### N0.1 The fold lock — shell-chain serialization, chosen by measurement

The host↔shell transition chain (`d_fwd`/`d_back`) is touched by concurrent
`call_rcu` fold workers, so it needs its own serialization. **Three options were
built and swept** (`dcache_swmw.png`):

- **legacy chain lock** — the demote (enqueue) AND all fold branches take one
  per-host lock; every chain mutation is a plain store, at the cost of coupling the
  producer to the folds.
- **mixed SW/MW** (`mixed-sw-mw-txn.md`) — the a-priori-elegant one: the chain
  rides the SW commit as MW records, one linearization point spans index+chain, and
  the chain lock is **retired** (−8 B/dentry, back under the seqlock footprint).
- **fold lock (the DEFAULT, winner)** — the demote is a `store_sw` folded into the
  SW index commit under the *bucket* lock (never touches the fold lock); a per-host
  **fold lock is taken only by the fold (dequeue) workers**, which rewrite the chain
  with plain stores.

**The metric picked fold lock**, and this is the point worth making: fold lock >
mixed SW/MW > chain lock on rename throughput (both vs concurrency and vs
rename-fraction); the reader panel is a wash (identical reader code — a pure
writer-side choice). The mixed txn's headline benefit **did not land** because the
chain was never the rename bottleneck (the multi-head *index* bucket-locking is —
`mixed-sw-mw-txn.md` §4 "honest perf scope"). And the **`+8 B pad` same-size control
(176 B) sits on top of the un-padded mixed line**, so the fold-lock win is
placement/discipline, not footprint.

**Why fold lock wins — a three-layer mechanism, each verified in
`dcache_bucketlock.c`:**
1. **Fewer atomics.** The fold rewrites the chain with plain `uatomic_store`s under
   the fold lock (no MW descriptor, no per-fold `call_rcu` of a descriptor); the
   enqueue stack is a pure `urcu_txn_commit_sw`.
2. **Decouple enqueue from fold.** The producer (demote) never touches the fold
   lock, so it never contends with a `call_rcu` worker; only folds do. *Exclusion
   nuance to state precisely in the paper:* the fold lock serializes fold-vs-fold on
   **relay** nodes (`d_back != NULL`); fold-vs-enqueue on a **top** is not covered by
   the fold lock — a top's `d_back` isn't stable under it — and is instead resolved
   by the **mark-recheck under the bucket lock**.
3. **Cache-line split.** CL0 = reader-hot identity+mark; **CL1 = the fold-lock line**
   (`d_fwd, d_back, d_fold_lock, d_dc, d_inode/d_isdir, d_rcu`); **CL2 = the
   structural-reader line** (`d_parent+d_moving`, `d_child_head+d_sib`, `d_id/d_host`)
   kept OFF the fold-lock line so `readdir` / a mover's ancestry walk doesn't bounce
   it. Kills false sharing between the foreground enqueue and the background fold.

This three-way comparison *is* the V&A section writing itself, with the numbers that
rejected each rejected option — strong both defensively (coverage) and academically
(an attributable, measured design verdict rather than an asserted one).

---

## The two Mathieu flagged verbally

### N1. "Host / shell" split — inline names AND stable-address identity, no recompaction
*(design note §Nodes, §Rename, §"Why the in-place name write is legal")*

One dentry plays two roles: an address-stable **content host** `C` (`&C` is its
children's parent key, never freed or relocated by a rename) and a transient
per-rename **shell** `S` carrying the new name, which becomes the named top and
forwards down to the host. Achieves **four things at once** that normally trade
off: (1) inline name bytes (kernel `d_iname` locality — compared off a cache line
the walk already loaded); (2) no per-object seqcount on the identity check; (3)
stable address identity (children keyed on `hash(&parent, name)` never rehash
across a parent rename); (4) lock-free/bucket-locked concurrent renames (no global
rename lock).

**Why it looks novel / what it beats.** An inline name mutated *in place* tears
under a lockless compare — which is exactly why the kernel needs `d_seq` — and
object COW would break address-stable identity. The escape: **spend an RCU grace
period** to carve a window in which no reader looks at a node's name, then do the
one in-place name write, keeping the address put. `call_rcu` *is* that
grace-period wait, so the fold schedule needs no explicit epoch counter. The
load-bearing invariant: while a host/relay is tombstoned (`d_back != NULL`) no
reader reads its name.

### N2. Walk-causality version — scalable replacement for the global `rename_lock`
*(design note §"Walk causality", §"A/B arm: per-node generation", §"mark arm")*

The shell kills `d_seq`'s job (per-component coherence) but **not**
`rename_lock`'s job (whole-walk causality — a reader can keep using a `cur` that
silently relocated mid-walk; see the deterministic repro). The paper's own
framing separates these two kernel jobs cleanly, which is itself worth stating.
**Three arms** were built and swept (`optype.png`, `height.png`):

- **Global `rename_gen`, folded into the commit.** A *txn-mitigated* counter (not a
  naked seqlock — an odd/even bracket assumes mutually-exclusive writers, false
  here). Reader brackets the whole walk with two plain reads. Cost: whole-tree
  retry, renames serialized — kernel parity. `optype.png` shows it **collapses on
  directory moves** (the whole-tree bump) while staying competitive on file moves
  (a file is never an interior waypoint, so it skips the bump).
- **Per-node generation (`DC_PER_NODE_GEN`).** A `d_seq` per content host, bumped
  only by that node's *own* move, stepped inside the same commit as the structural
  edge. Reader does a **versioned double-collect**: sample each path host's gen
  descending, re-read all at walk-end; unchanged everywhere ⇒ the whole path was
  simultaneously live. Sound by the **edge lemma** (a move of `Pᵢ` changes only
  `Pᵢ`'s own incoming edge). A disjoint-subtree rename bumps a gen this walk never
  reads — **no shared cacheline**, the point over the global counter.
- **Deletion MARK as the version (`DC_MARK_GEN`) — the DEFAULT.** No per-node gen
  word at all: walk causality rides the hlist **deletion mark** on `d_hash.next`
  (a rename's demote sets it), so the 8 bytes go to the name instead. Localized,
  counter-free; `height.png` shows the MARK reader stays ~8–24× the seqlock across
  move heights (eroding ~40% toward the root but never to parity), and `optype.png`
  shows it flat across file-vs-dir (no counter to collapse). This arm **retired the
  earlier `DC_IPARENT_SKIP` arm.**

**Two sub-insights inside N2 worth their own mention:**
- **Write-once identity turns the version into a pure *freshness* signal.** Because
  a rename never rewrites a name in place (it stacks a fresh shell), the version is
  not guarding a torn identity read — so the observe-then-read window closes with a
  cheap O(1) re-verify of the deletion mark, not a second identity read.
- **The versioned double-collect is the *sound* form; the version-less one is
  not.** Walking `d_parent` back up and checking two passes agree is defeated by
  move-away-move-back ABA and misses same-directory renames. So `d_parent` stays
  strictly the writer-side loop-check field; reader soundness rests on the
  versions / the mark.

---

## Further novelties in the design note (not yet flagged, worth capturing)

### N3. Lock-free cross-directory loop check via the commit's validate set
*(§"Cross-directory loop check")*

The kernel serializes `A→under→B` / `B→under→A` cycle formation with the global
`s_vfs_rename_mutex`. Here: fold the entire `T→root` ancestry walk into the
rename commit's validate set via `urcu_txn_load_validate` (since "is D an ancestor
of T" is a pure function of T's parent chain). A concurrent reparent of any
T-ancestor mutates a validated edge ⇒ the commit aborts ⇒ re-walk + re-check.
Livelock-free (every abort re-checks against strictly-more-committed state);
N-way cycles die the same way. A **lock-free replacement for a global rename
mutex** — the strongest single showcase of `load_validate`. (Residual: under the
bucket-lock+SW engine the loop check currently still leans on the global rename
serialization; folding it into the acquire is a named separate step,
`dcache-dlm-sw.md` §4.)

### N4. The fold cascade — per-node `call_rcu`, retry-on-abort, self-free-only
*(§"The fold cascade")*

Concurrent renames stack shells into a chain; per-shell `call_rcu(fold)` workers
converge it to a single content host under the newest name, each re-reading
neighbours and branching transfer-and-promote vs splice. Two rules make it safe:
**retry-on-abort** (adjacency serialization) and **self-free-only** (a node is
freed only by its own fold, never a neighbour's splice — which is why the chain is
doubly linked). Under the converged engine the fold takes the **fold lock** and
commits SW (N0.1); it converges regardless of worker firing order.

### N5. Write-once `d_host` skip pointer overlaid on `d_id` — O(1) host resolution
*(§"Directory listing", §"Implementation status")*

A reader/readdir/walk/fold/writer resolves the content host in **one hop** (host
reads the slot as its id, shell as a pointer to the tail host, discriminated by
`d_fwd==NULL`), overlaid at zero memory cost on the id field. Consequence: **chain
depth is never traversed by anyone**, so a mid-rename chain costs only *memory*,
not time. This also root-caused and fixed a **bistable ~60× liveness collapse**
(commit `08c069b`): a writer that *walked* the chain to measure depth turned a GP
stall into an O(n²) collapse — the relief valve's own trigger drove the starvation
it existed to relieve. A GP stall now degrades to bounded-rate memory growth,
fixable at its source (`rcu_thread_offline()` while blocking). Good "engineering
lesson" material even if not a headline novelty.

### N6. Atomic `RENAME_EXCHANGE` as two shell stacks in one commit
*(§"Atomic exchange")*

`stack_one_prepare()` (records, no commit) lets `dc_rename_exchange` compose two
shell stacks + both loop-checks + both reparents + the gen bump into **one** commit.
Property the old sequential-placeholder could not satisfy: a slot path is never
momentarily empty, so every reader lookup of a valid slot is POSITIVE (zero ABSENT
reads, stress-validated).

### N7. readdir as a lock-free RCU child-hlist walk (the second txn-hlist)
*(§"Directory listing")*

`readdir` needs only RCU-safe traversal (POSIX leaves concurrent-rename effect
unspecified) — no `rename_gen` bracket, no `d_seq`, no cursor. A per-directory
`rcu-txn-hlist`, O(1)-resolved via the `d_host` skip pointer. The *easy* case of
the port, and a clean second consumer of the txn-hlist. Its scaling under churn is
now a headline result (see readdir-vs-churn below).

---

## Evaluation already in hand (2×96-core EPYC)

Current figures at `efficios-trie-benchmark/figures/`. Arms include the seqlock
kernel baseline, the all-MW-txn deletion-MARK, and the **bucket lock + SW txn**
(fold-lock writer); some panels also carry the global/per-node arms and a vendored
kernel `rw_semaphore`. **Read the exact numbers off the current figures — they were
regenerated when the bucket-lock arm landed; the pre-bucket-lock S3 numbers in this
note's history are stale.**

- **`s3.png` — the reader question.** *Homogeneous mix* collapses on all arms
  (writer-bound: a rename ≈50× a lookup) — the wrong instrument, kept for honesty.
  *Role-split* isolates the read path: the MARK and bucket-lock arms scale reader
  throughput linearly to ~4k+ Mops/s at 184 readers while the seqlock stays flat
  near the floor (double-digit ×). The bucket-lock arm tracks the MARK arm — i.e.
  **it keeps the reader win while swapping the writer engine**, which is the whole
  claim.
- **`churn_scaling.png` — the writer question.** Decontended insert/remove scaling
  to 192 writers: the **bucket lock + SW txn lands on/above the seqlock (bit-lock)
  curve** and above the MW-txn arms (which coincide, since churn is bump-free). This
  is the CAS-count hypothesis confirmed: MCAS was per-op overhead on pure churn, and
  the SW commit removes it.
- **`readdir_churn.png` — the bias the lock-free arms escape.** On a hot dir, a
  seqlock rwlock forces a reader/writer-preference trade-off (reader-pref keeps
  listing fast but starves churn; writer-pref the reverse). The lock-free arms
  escape it: the bucket-lock arm lists fast under churn *and* its bit-lock add/unlink
  never blocks on a reader — leading both panels at every point.
- **`optype.png` / `height.png` — walk-causality arms.** File-vs-dir (the global
  seqcount collapses on dir moves; MARK/per-node/bucket-lock carry no counter and
  stay flat and high) and move-height (both localized arms erode ~40% toward the
  root but stay ~8–24× the seqlock, never parity).
- **`swmw.png` — the fold-lock verdict** (N0.1): fold lock > mixed SW/MW > chain
  lock on rename throughput; reader path a wash; the `+8 B pad` control isolates
  mechanism from footprint.

**Honest split of the headline** (keep it — the design note is scrupulous):
the *simplification* win (`d_seq` deleted, one reader rule) is real and
counter-independent; the *reader-scaling* win holds under per-node/MARK but the
global `rename_gen` reintroduces the whole-tree contention `rename_lock` had; and
the *writer* win is what the bucket-lock+SW engine adds on top (add/unlink back on
the kernel bit-lock budget). Three claims, stated separately.

Validation: 103-case stress suite + churn / rename / exchange / dir-move
conservation, TSAN + ASan clean, across the seqlock / txn / bucket-lock arms.

---

## Paper shape (updated sketch)

The natural spine: *rename is the hard part; the kernel pays two global taxes
(`rename_lock`, `d_seq`) and a per-op MCAS-free but bit-locked writer; the shell
dissolves `d_seq` unconditionally, the per-node/MARK version dissolves
`rename_lock`'s global-retry, and the bucket-lock+SW engine keeps the writer on the
kernel bit-lock's budget while keeping the txn reader.* **N0 (the converged engine,
chosen by measurement) is now a co-headline with N1+N2**; N3 (loop check) is the
strongest single `load_validate` demonstration; N4–N7 are the machinery; the figures
are the evidence. This paper leans **evaluation-heavy** relative to P1–P3, which is
fine — it is the applied capstone, and it exercises the whole engine (bucket-lock+SW
commit, MCAS reader, hlist, `load_validate`, RYW, `call_rcu` reclaim) on a genuinely
hard, recognizable problem.

Dependencies: needs the MW engine (P2) and the programming model (P3) as citable
prior parts (uses `load_validate`, `expect_conflict`, RYW, the four-flavour read
policy, and the SW commit form). It also **touches the DLM line** — bucket lock + SW
is the smallest DLM instance, and the mixed SW/MW record (`mixed-sw-mw-txn.md`) is a
shared primitive with the DLM-hybrid/LRU work — so cross-references there. Comes
**after** P2/P3 in the series despite already existing.

## Open questions the experiment itself lists
`..`/getpath (tombstoned host's name stale for an upward walker); negative
dentries; same-bucket rename (RYW handle, not `declare_disjoint`); escalation into
the fair-mutex lane; the loop-check residual (fold `T→root` into the acquire,
`dcache-dlm-sw.md` §4); the **LRU** driver (the mixed SW/MW record's real prize,
`mixed-sw-mw-txn.md` §5); provenance framing (relativistic-move / RCU-resize applied
to *identity*).
