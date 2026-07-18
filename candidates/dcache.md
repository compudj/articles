# Candidate paper: dentry cache over rcu-txn

**Status:** novelty inventory for a future paper. **Capture, not disclosure** —
nothing here is published yet; the point is a precise catalogue so the eventual
paper is a full *enabling* disclosure rather than a hint. Same reserve-don't-burn
discipline as the rest of the series.

**Primary sources** (all in `efficios-trie-benchmark/experiments/dcache/`):
- `rename-shell-transition.md` — the complete design note (authoritative).
- `dcache_txn.c` — the lock-free implementation (landed + stress-validated).
- `dcache_seqlock.c` — faithful kernel-style baseline (RCU hlist + global
  `rename_lock` + per-dentry `d_seq`).
- `README.md` — thesis and file map.
- Figures: `figures/dcache_s3.png` (lookup scaling), `dcache_readdir.png`.

**One-line thesis (from the experiment README):** *the dentry cache is the
hardest RCU user in the kernel, and the thing that makes it hard is `rename`;
can urcu-txn dissolve the kernel's two global consistency mechanisms —
`rename_lock` (whole-walk causality) and per-dentry `d_seq` (per-component
coherence)?* Answer, empirically: `d_seq` dissolves outright; the global-retry
role of `rename_lock` dissolves only under the per-node generation arm.

> Novelty claims below are **candidates** — they still need a prior-art sweep of
> the filesystem/concurrency literature. Mathieu is the authority on what is
> genuinely new; this file catalogues what *looks* new and why.

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
across a parent rename); (4) lock-free concurrent renames (MCAS, no global rename
lock).

**Why it looks novel / what it beats.** An inline name mutated *in place* tears
under a lockless compare — which is exactly why the kernel needs `d_seq` — and
object COW would break address-stable identity. The escape: **spend an RCU grace
period** to carve a window in which no reader looks at a node's name, then do the
one in-place name write, keeping the address put. `call_rcu` *is* that
grace-period wait, so the fold schedule needs no explicit epoch counter. The
load-bearing invariant: while a host/relay is tombstoned (`d_back != NULL`) no
reader reads its name.

### N2. Per-node move-detection generation — scalable replacement for the global `rename_lock`
*(design note §"Walk causality", §"A/B arm: per-node generation")*

The shell kills `d_seq`'s job (per-component coherence) but **not**
`rename_lock`'s job (whole-walk causality — a reader can keep using a `cur` that
silently relocated mid-walk; see the deterministic repro). The paper's own
framing separates these two kernel jobs cleanly, which is itself worth stating.
Two arms:

- **Global `rename_gen`, folded into the commit.** A *txn-mitigated* counter, not
  a naked seqlock: a classic odd/even seqlock bracket is **unusable** because it
  assumes mutually-exclusive writers and here renames are lock-free concurrent.
  Folding the bump into the MCAS commit gives atomicity + serialization for free
  (renames conflict on the slot and retry). Reader reads it plain (no odd/even),
  brackets the whole walk with two reads. Cost: whole-tree retry, renames
  serialized — kernel parity.
- **Per-node generation (`DC_PER_NODE_GEN`) — the scalable one.** A `d_seq` per
  content host, bumped only by that node's *own* move (never ancestors — bumping
  to the root just rebuilds the global counter on the hot line), stepped inside
  the same MCAS as the structural edge. Reader does a **versioned double-collect**:
  sample each path host's gen descending, re-read all at walk-end; unchanged
  everywhere ⇒ the whole path was simultaneously live at the leaf turnaround.
  Sound by the **edge lemma** (a move of `Pᵢ` changes only `Pᵢ`'s own incoming
  edge, because children key on the parent *address*). A rename down a disjoint
  subtree bumps a gen this walk never reads — **no shared cacheline**, the whole
  point over the global counter.

**Two sub-insights inside N2 worth their own mention:**
- **Write-once identity turns the version into a pure *freshness* signal.** Because
  a rename never rewrites a name in place (it stacks a fresh shell), the per-node
  version is not guarding a torn identity read — so the observe-then-read window
  (host counter reached only *after* the name match) closes with a cheap O(1)
  re-verify of the deletion mark on `top->d_hash.next`, not a second identity read
  or bucket re-scan.
- **The versioned double-collect is the *sound* form; the version-less one is
  not.** Walking `d_parent` back up and checking two passes agree is defeated by
  move-away-move-back ABA and misses same-directory renames. So `d_parent` stays
  strictly the writer-side loop-check field; reader soundness rests on the
  versions.

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
N-way cycles die the same way. This is a **lock-free replacement for a global
rename mutex** — a clean showcase of `load_validate` doing real work.

### N4. The fold cascade — per-node `call_rcu`, retry-on-abort, self-free-only
*(§"The fold cascade")*

Concurrent renames stack shells into a chain; per-shell `call_rcu(fold)` workers
converge it to a single content host under the newest name, each re-reading
neighbours and branching transfer-and-promote vs splice. Two rules make it safe:
**retry-on-abort** (adjacency serialization, same as the hlist) and
**self-free-only** (a node is freed only by its own fold, never a neighbour's
splice — which is why the chain is doubly linked). Converges regardless of worker
firing order.

### N5. Write-once `d_host` skip pointer overlaid on `d_id` — O(1) host resolution
*(§"Directory listing", §"Implementation status")*

A reader/readdir/walk/fold/writer resolves the content host in **one hop** (host
reads the slot as its id, shell as a pointer to the tail host, discriminated by
`d_fwd==NULL`), overlaid at zero memory cost on the id field. Consequence: **chain
depth is never traversed by anyone**, so a mid-rename chain costs only *memory*,
not time. This also root-caused and fixed a **bistable ~60× liveness collapse**
(commit `08c069b`): a writer that *walked* the chain to measure depth turned a GP
stall into an O(n²) collapse — the relief valve's own trigger drove the starvation
it existed to relieve. A GP stall now degrades to bounded-rate memory growth (the
honest consequence), fixable at its source (`rcu_thread_offline()` while blocking).
Good "engineering lesson" material even if not a headline novelty.

### N6. Atomic `RENAME_EXCHANGE` as two shell stacks in one commit
*(§"Atomic exchange")*

`stack_one_prepare()` (records, no commit) lets `dc_rename_exchange` compose two
shell stacks + both loop-checks + both reparents + the gen bump into **one** MCAS.
Property the old sequential-placeholder could not satisfy: a slot path is never
momentarily empty, so every reader lookup of a valid slot is POSITIVE (zero ABSENT
reads, stress-validated).

### N7. readdir as a lock-free RCU child-hlist walk (the second txn-hlist)
*(§"Directory listing")*

`readdir` needs only RCU-safe traversal (POSIX leaves concurrent-rename effect
unspecified) — no `rename_gen` bracket, no `d_seq`, no cursor. A per-directory
`rcu-txn-hlist`, O(1)-resolved via the `d_host` skip pointer. The *easy* case of
the port, and a clean second consumer of the txn-hlist.

---

## Evaluation already in hand (S3, `figures/dcache_s3.png`)

2×96-core EPYC, three arms (`seqlock`, `txn`-global, `txn`-per-node), 420 runs,
0 conservation failures, TSAN + ASan clean.
- **Role-split, 8 writers, sweep readers to 184:** per-node reader throughput
  keeps scaling (8 → **451 Mops/s** at 160 readers) while global saturates
  (~110–120 past ~128 readers) and seqlock never scales cleanly (40–93, retry
  storms). At full machine: per-node **3.7× global, 5.8× seqlock**.
- **Homogeneous mix** collapses on all three arms (writer-bound — a rename ≈50× a
  lookup), which is why the mix is the *wrong instrument* for the reader question.
  Honest and worth stating.
- **readdir** (`dcache_readdir.png`): txn walk scales to ~355 listings/s at 160
  readers vs per-dir rwsem saturating at ~15–29 — **~12×** at peak; leads at every
  reader count.

**Honest split of the headline** (the design note is scrupulous about this, keep
it): the *simplification* win (`d_seq` deleted, one reader rule) is real and
counter-independent; the *scaling* win on the reader path is real **only** under
per-node generations — the global `rename_gen` reintroduces exactly the
whole-tree contention `rename_lock` had. So "dissolve `rename_lock` + `d_seq`"
splits into two claims stated separately.

---

## Paper shape (first sketch)

The natural spine: *rename is the hard part; the kernel pays two global taxes
(`rename_lock`, `d_seq`); the shell dissolves `d_seq` unconditionally and the
per-node generation dissolves `rename_lock`'s global-retry.* N1 + N2 are the
headline; N3 (loop check) is the strongest single demonstration of the txn
engine's `load_validate`; N4–N7 are the machinery that makes it real; S3 is the
evidence. This paper leans **evaluation-heavy** relative to P1–P3, which is fine —
it is the applied capstone, and it exercises the whole engine (MCAS, hlist,
`load_validate`, RYW, `call_rcu` reclaim) on a genuinely hard, recognizable
problem.

Dependencies: needs the MW engine (P2) and the programming model (P3) as
citable prior parts, since it uses `load_validate`, `expect_conflict`, RYW, and
the four-flavour read policy. So this paper comes **after** P2/P3 in the series
order even though the experiment already exists.

## Open questions the experiment itself lists (design note §"Open questions")
`..`/getpath (tombstoned host's name stale for an upward walker); negative
dentries; same-bucket rename (RYW handle, not `declare_disjoint`); escalation into
the fair-mutex lane; provenance framing (relativistic-move / RCU-resize applied to
*identity*).
