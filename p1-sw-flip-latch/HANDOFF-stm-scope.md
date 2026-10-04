# P1 — what the paper says about STM "in general": handoff

Written 2026-10-04, from the session that changed the LPC deck
(`lpc2026-slides`, commit `5492429`). For the session on the other machine,
which has the series' context in memory but none of what was read here.
Self-contained: every quote and every location is below.

**Nothing in P1 has been changed.** Everything in §4 and §5 is a proposal for
Mathieu to accept, reword or reject.

## 1. The concern

Mathieu, 2026-10-04, about the deck's slide "Between RCU and STM" (its STM
column said the reader pays "a barrier on every read" and gets "isolation,
opacity"):

> I am hesitant to present the STM column. What if specific STM
> implementations end up not having those characteristics. in other words, it
> may be true for STM "in general", but we may be doing a too broad statement
> here. (I also think this about P1) For instance, I recall that some STM
> implementations allow carving a read set which is not STM-instrumented (opt
> out) (I'm not sure what was the source there). So someone could say that
> our claim that STM has a barrier on "every read set" may be too broad.

The concern holds. The sources in §2 are counterexamples to "an STM puts a
barrier on every read", and P1 says that in three places (§4).

## 2. What was read

Quotes are from `pdftotext` of the PDFs; a hyphen at a line break may be lost
("nontransactional"), and `transaction pure` is the paper's `transaction_pure`
with the underscore lost in extraction.

### 2.1 Kestor, Dalessandro, Cristal, Scott, Unsal — "Interchangeable Back Ends for STM Compilers"

<https://sss.cs.purdue.edu/projects/transact11/papers/Kestor.pdf> (read in
full text). The venue, TRANSACT 2011, is inferred from the hosting path (the
workshop's site) and the PDF's date stamp, 2011/5/17; the PDF does not name it.

The programmer chooses which loads are instrumented, in three ways:

> For STAMP we consider both the original code, which uses hand
> instrumentation of (only) "important" loads and stores, and new versions
> written to the C++ TM standard. One new version lets the compiler
> instrument everything inside transactions; another uses Intel's transaction
> [[waiver]] extension to disable instrumentation of many "unimportant" loads
> and stores. Our results suggest that the scalability of STAMP depends
> critically on minimizing instrumentation.

> The Intel compiler, which we use for our experiments, implements certain
> extensions to the C++ TM standard. For example, a function can be declared
> with the transaction pure attribute, meaning that the programmer guarantees
> it to be idempotent, and thus safe to execute—even within an atomic
> transaction—without instrumentation on its loads and stores. Finally, the
> transaction [[waiver]] {} construct can be used to bracket a sequence of
> statements inside a transaction that should not be rolled back on abort.
> Waivered code is essentially unstructured open nesting; example use cases
> include debugging, statistics gathering, and semantically neutral operations
> like tree rebalancing.

And what the default costs:

> For Kmeans and Vacation, on the other hand, all of the back ends suffer
> significant performance loss compared to the manually-instrumented
> version—from 10–50%.

### 2.2 Howard and Walpole — "A Relativistic Enhancement to Software Transactional Memory", HotPar 2011

<https://www.usenix.org/legacy/event/hotpar11/tech/final_files/Howard.pdf>
(read in full text; Philip W. Howard and Jonathan Walpole, Portland State
University; page footer "USENIX HotPar 2011, Berkeley"). **Not in
`common/urcu-txn.bib`, not cited by P1.** Possibly the source Mathieu had in
mind: RCU readers that run with no STM instrumentation at all.

What it does:

> We propose combining relativistic programming and software transactional
> memory in a way that gets the best of both worlds: low-overhead
> linearly-scalable reads that never conflict with writes and scalable
> disjoint access parallel writes.

> We propose a novel method whereby read-only operations can be performed
> non-transactionally without violating the isolation guarantees of
> transactions.

> Our STM is derived from swissTM [6, 7]. We chose this as our starting point
> because it is a recent implementation that claims high performance and
> because it uses invisible reads and a re-do log rather than
> update-in-place.

> The lookup operation was left unmodified so that reads proceed outside
> transactions.

What it requires of the STM (section 3):

> 1. The transactional memory system must be weakly atomic.
> 2. Updates that eventually get rolled back must not be visible to readers.
> 3. The transactional memory system must honor the program order of writes
>    to memory. [...]
> 4. The transactional memory system must honor grace period delays between
>    memory writes.

> The first requirement is necessary because relativistic reads are supposed
> to be completely outside the transactional system. A strongly atomic
> transactional memory system would include the relativistic reads as part of
> its atomicity guarantee. This would impact read performance.

What its readers get, which is the contrast with P1:

> Most software transactional memory systems give the appearance of atomicity
> of transactions: other threads see all of the updates or none of them. As a
> result, the order in which updates are made visible in memory is
> irrelevant. However, in our system, readers can see partially completed
> commits.

> The writes are made visible to readers at commit time, so the grace period
> must be honored at commit time. Our implementation records the request for
> a grace period in the re-do log. Commits will be delayed when this entry in
> the re-do log is encountered.

> The transactional memory system will ensure that updates are isolated from
> each other, but since lookups happen outside the transactional system, this
> isolation does not extend to lookups.

Its Figure 1 is a linked-list move in three steps, captioned "A grace period
is required between the second and third steps": P1's "drain with a grace
period" remedy, carried inside a transaction's commit.

It also says, of non-transactional access in general:

> Many researchers admit that for performance and other reasons, it is often
> desirable to access some data non-transactionally. This is called
> privatization and it is difficult to do correctly [4, 10, 14, 15]. The
> nontransactional accesses can break the isolation guarantees of the
> transactional memory system.

### 2.3 Weak atomicity — NOT read

Blundell, Lewis, Martin, "Subtleties of Transactional Memory Atomicity
Semantics", IEEE Computer Architecture Letters, 2006
(<https://acg.cis.upenn.edu/papers/cal06_atomic_semantics.pdf>) is where the
terms weak and strong atomicity come from. Only a search engine's summary of
it was seen. The fact P1 would use it for — under weak atomicity a read
outside any transaction is not instrumented — is stated in a paper that was
read: Howard and Walpole's first requirement, quoted above.

### 2.4 Leads, from memory, NOT verified — do not write into the paper unread

- GCC's `transaction_pure` attribute (a search summary said "the compiler
  assumes that they do not have side-effects, thus, no instrumentation is
  performed"; the primary documentation was not read).
- STMs that are not opaque: snapshot-isolation STMs, STMs that tolerate
  doomed transactions. P1's bibliography has `riegel2006lsa`; nothing was
  checked. This bears on "isolation, opacity" as a property of STM in
  general, the other half of Mathieu's concern.
- Haskell's `readTVarIO`, TinySTM's unit loads.

## 3. What survives, and what to say instead

Every counterexample has the same shape: **a read that skips the barrier is
outside the guarantee.** A waivered or hand-uninstrumented load is not
validated; a read outside a transaction under weak atomicity is not isolated;
Howard and Walpole's readers "can see partially completed commits". So:

1. Tie the cost to the guarantee, not to the class of systems. Not "an STM
   instruments every read" but "a read an STM isolates is instrumented", or
   name the design point: an opaque STM (`guerraoui2008opacity`), TL2 for
   one (`dice2006tl2`).
2. P1's section 3.7 claim, "isolation is a read-side cost only once you
   mutate in place", is untouched, and Howard and Walpole support it in
   their own words ("A strongly atomic transactional memory system would
   include the relativistic reads as part of its atomicity guarantee. This
   would impact read performance.").
3. The positioning gets sharper, not weaker. Where an STM's reader goes
   uninstrumented it loses the atomic visibility of a commit. A
   pseudo-transaction is the point where a reader that pays one branch still
   gets it. Howard and Walpole keep the structure always-consistent by write
   order and grace periods inside the commit; P1 flips N slots at once and
   waits for no grace period to publish.

This is the second claim of this family that turned out too broad. The first
is recorded in P1's own guardrail comment in section 3.7 ("isolation is paid
for on the read side", false without "once you mutate in place").

## 4. The P1 passages

Line numbers are `p1-sw-flip-latch/main.tex` at `articles` commit `e71e58f`
(the last commit that touched P1). Section numbers are from `main.aux`.

### 4.1 Section 6.4, `\paragraph{What an STM does instead.}` (lines 1936–1958) — must change

Current text, the sentences at issue:

```latex
\paragraph{What an STM does instead.} An STM instruments reads by default, and
the difference is the bargain of this paper in miniature. Its read barrier sits
on \emph{every} read, so a search inside a
transaction is reconciled whether or not the caller gave it a thought --- and
every read pays, whether or not it needed to. That cost is well known, and the
literature attacks it from two directions, neither of them this one. The
programmer-facing dials we are aware of are over what stays in the read
\emph{set}: [early release, elastic transactions] ... Both reduce what a
conflict can invalidate; neither reduces what a read cost. Where the
instrumentation itself is reduced, it is the compiler that reduces it, and it
does not ask --- \citet{dragojevic2009captured} ...
Here reconciliation follows the accessor instead, and the choice is the
writer's. [...] The writer chooses per load what the STM applies wholesale, and
the reader is what the choice buys.
```

What is wrong:

- "Its read barrier sits on *every* read" and "every read pays": not in a
  hand-instrumented STM (STAMP's original code), nor under `[[waiver]]` or
  `transaction_pure` (§2.1).
- "The programmer-facing dials we are aware of are over what stays in the
  read set": we are now aware of dials over the instrumentation itself.
- "it is the compiler that reduces it, and it does not ask": the programmer
  reduces it too, and is asked.
- "two directions, neither of them this one": the hand-instrumentation
  direction IS close to this one (reconciliation follows the accessor the
  programmer picked), so the sentence overclaims the difference.
- "what the STM applies wholesale": true of the compiler's default only.

"An STM instruments reads by default" is the sentence that already has it
right for a language-level STM.

Draft replacement (keeps the paragraph's argument and its three citations,
adds one):

```latex
\paragraph{What an STM does instead.} A language-level STM instruments reads by
default, and the difference is the bargain of this paper in miniature. Inside a
transaction the compiler puts a read barrier on each load it cannot prove
private, so a search inside a transaction is reconciled whether or not the
caller gave it a thought --- and each of those reads pays, whether or not it
needed to. That cost is well known, and the literature attacks it from three
directions. Two programmer-facing dials are over what stays in the read
\emph{set}: \citet{herlihy2003dstm}'s \emph{early release} discards an object
already read, and \citet{felber2009elastic}'s elastic transactions let a caller
run a transaction in a mode that may drop what it has read and resume in a fresh
one. Both reduce what a conflict can invalidate; neither reduces what a read
cost. The compiler removes barriers by analysis:
\citet{dragojevic2009captured} find most of the barriers a baseline compiler
emits to be on memory captured by the transaction, and elide them. And the
programmer removes them by hand. A library-level STM instruments only the loads
routed through it, which is how the STAMP suite was written, and Intel's
compiler offers a \code{transaction\_pure} attribute and a \code{[[waiver]]}
block to the same end; \citet{kestor2011backends} report that the suite's
scalability depends critically on minimizing instrumentation. A load taken out
that way is outside what the transaction
guarantees, and that is the programmer's to justify. Here reconciliation
follows the accessor in the same way, and the choice is the writer's. A writer
that must walk its own pending state loads transactionally and pays the find;
one that need not, or that knows its slots are disjoint, pays nothing. What has
no counterpart there is the \emph{reader}: it is not in the scheme at all, its
traversal is plain \rcu, indistinguishable from a read outside any
\pseudotxn{} --- and the commit is atomic to it all the same, which is why the
reader carries none of the per-element state and none of the read-path work
\cref{sec:costcomparison} charges the alternatives.
```

To check before taking it: "which is how the STAMP suite was written" rests
on Kestor et al.'s sentence only (STAMP's own paper was not read); "Intel's
compiler offers" is as of 2011.

### 4.2 Section 10.2, "Transactional memory" (lines 3513–3555) — must change, and gains a paragraph

Line 3531:

```latex
less far here: STM instruments every read, so a search made inside a transaction
is reconciled too, whereas ours reconciles only the slots a writer records and
```

Draft: `less far here: an STM instruments a transaction's reads by default, so a
search made inside a transaction is reconciled too, whereas ...`

Lines 3516–3521, the opening, say STM offers "the strictly stronger contract
this facility declines: a transaction is atomic \emph{and} isolated, so a
reader's whole read set is mutually consistent". True of a transactional
reader of an opaque STM; "a reader's" is where it is too broad, since a
weakly atomic STM gives a reader outside a transaction nothing. Draft: "so a
\emph{transaction's} whole read set is mutually consistent".

New paragraph for this subsection (or for section 10.3, `sec:relrcu`, which
is where "multi-pointer atomicity under RCU" is surveyed; the other session
decides), draft:

```latex
One system takes \rcu readers out of an STM altogether.
\citet{howard2011relativistic} modify SwissTM so that lookups run as
relativistic readers, outside the transactional system, while updates are
transactions: writers gain the disjoint-access parallelism and conflict
detection this paper leaves to the embedder's locks, and readers pay nothing.
What their readers get is the opposite of what a \pseudotxn gives. The STM
replays a transaction's writes at commit in program order, with the memory
barriers and the grace periods the relativistic algorithm calls for, so
``readers can see partially completed commits'': the structure stays
consistent by the ordering discipline of \cref{sec:onestore}, grace-period
waits included, and a transaction's isolation ``does not extend to lookups''.
A \pseudotxn publishes its slots at one instant and waits for no grace period
to do it. The two are complementary: theirs is a way to run many writers, ours
a way to publish what one writer built.
```

To check before taking it: that `sec:onestore` is the right back-reference
for "keep the structure consistent by ordering and grace periods" (it may be
`sec:buildpublish` or the remedies list of section 1); and whether "the two
are complementary" is a claim P1 wants to make, given that P2 is the
multi-writer paper.

### 4.3 Section 3.4, "What is not guaranteed" (lines 756–758) — small

```latex
\textbf{There is no opacity and no multi-read snapshot.} This is weaker than
STM, deliberately and in exactly one direction: readers are plain \rcu readers
that pay no per-read barrier.
```

"Weaker than STM" compares a guarantee with a class. Draft: "This is weaker
than what an opaque STM gives a transaction's reads, deliberately and in
exactly one direction: ...". Separately, "pay no per-read barrier" sits
oddly beside the paper's own count of one test and one branch per
dereference; "no added load and no per-element state" is what the rest of
the paper says.

### 4.4 Probably fine; look, do not necessarily change

- Abstract, line 57: "The guarantee is deliberately weaker than software
  transactional memory." And the conclusion, line 3804, "weaker than
  transactional memory". Both compare guarantees, not costs. A purist would
  want "than a transaction's in software transactional memory".
- Section 3.2, line 549: "A database or an STM means something else: a unit
  that is atomic \emph{and} isolated". About what the word means. Fine.
- Section 1, lines 204–207 ("the established answers pay for it in the same
  place ... existence structures, RLU, and STM"). Still true once Howard and
  Walpole is cited, because their uninstrumented readers do not get
  multi-pointer atomicity. Worth a clause saying so, since a reviewer who
  knows that paper will think of it here.
- Section 11.3, "What this paper claims" (lines 3742–3754): the combination
  claimed is a transient marker that RCU readers resolve through without
  waiting or writing and with no per-element state. Howard and Walpole has
  no marker; it does not dent the claim. Their "novel method whereby
  read-only operations can be performed non-transactionally" should
  nonetheless be acknowledged where P1 says what it has not found.

### 4.5 The rest of the series

`grep` for the same phrases ("STM instruments", "barrier on every read",
"weaker than STM", "every read pays") found nothing in `README.md`,
`p2-sole-driver-mcas/main.tex`, `p2-sole-driver-mcas/SCOPE.md` or
`p3-programming-model/SCOPE.md`. Not searched by meaning, only by phrase.

## 5. Bibliography drafts for `common/urcu-txn.bib`

**Not verified against dblp**: dblp refused the fetch from this machine (an
"Access Denied" page). Fields come from the PDFs' front matter except where
marked. The file's convention is a `% verified: dblp.org/rec/...` comment;
these need that check before they go in.

```bibtex
% NOT yet verified against dblp. Title, authors and "USENIX HotPar 2011,
% Berkeley" are from the PDF; the workshop's ordinal (3rd) is from memory.
@inproceedings{howard2011relativistic,
  author       = {Philip W. Howard and Jonathan Walpole},
  title        = {A Relativistic Enhancement to Software Transactional Memory},
  booktitle    = {3rd {USENIX} Workshop on Hot Topics in Parallelism
                  ({HotPar} '11)},
  address      = {Berkeley, CA},
  year         = {2011},
  url          = {https://www.usenix.org/legacy/event/hotpar11/tech/final_files/Howard.pdf}
}

% NOT yet verified against dblp. Title and authors are from the PDF; the
% venue is inferred from the hosting path (transact11) and the PDF's date
% stamp (2011/5/17); the workshop's ordinal (6th) is from memory.
@inproceedings{kestor2011backends,
  author       = {Gokcen Kestor and Luke Dalessandro and Adri{\'a}n Cristal and
                  Michael L. Scott and Osman Unsal},
  title        = {Interchangeable Back Ends for {STM} Compilers},
  booktitle    = {6th {ACM} {SIGPLAN} Workshop on Transactional Computing
                  ({TRANSACT})},
  year         = {2011},
  url          = {https://sss.cs.purdue.edu/projects/transact11/papers/Kestor.pdf}
}

% NOT read, NOT verified. Only if P1 names weak atomicity. Volume and number
% are from memory.
@article{blundell2006subtleties,
  author       = {Colin Blundell and E Christopher Lewis and Milo M. K. Martin},
  title        = {Subtleties of Transactional Memory Atomicity Semantics},
  journal      = {{IEEE} Computer Architecture Letters},
  volume       = {5},
  number       = {2},
  year         = {2006},
  url          = {https://acg.cis.upenn.edu/papers/cal06_atomic_semantics.pdf}
}
```

## 6. What the deck did, so the two agree

`lpc2026-slides` commit `5492429`, slide 16 "Between RCU and STM": the third
column's header is "Opaque STM" (was "STM") and its "the reader pays" cell is
"a barrier on each transactional read" (was "a barrier on every read"). Title
and lead unchanged. Two speaker notes carry the opt-outs and Howard and
Walpole. `lpc2026-slides/HANDOFF.md` has the prepared answer ("STM reads can
opt out of the barrier", section 5) and open item 12, which points here.

If P1 settles on other words than "opaque STM", the deck should follow before
6 October.

## 7. Rules that apply (restated)

- Series framing rule (`README.md`, and the comment at the top of P1's
  abstract): never claim "serializable", "opacity" or "STM" for the
  mechanism. Describing what an STM does is allowed; `make` in
  `p1-sw-flip-latch` runs `check-terms` (`common/paper.mk`), which lists
  every "opacity" hit for review. "Opaque STM" does not match its pattern.
- "We have not found" and "we are not aware of" are the paper's register for
  absence claims (P1's own comment near line 3771).
- Commits end with `Signed-off-by: Mathieu Desnoyers` only.
- LaTeX builds under `nice -n 19 ionice -c3`; no benchmark without Mathieu's
  go-ahead. None of this needs one.

## 8. Open

1. Mathieu to decide the wording in §4.1–4.3 and whether Howard and Walpole
   goes in section 10.2 or 10.3.
2. Verify the three bibliography entries (§5).
3. Read Blundell et al. before citing it, or cite Howard and Walpole's
   requirement 1 for the same fact.
4. The other half of the concern — is "isolation, opacity" true of STM in
   general? — was not researched (§2.4). The scoping to "an opaque STM"
   sidesteps it; a sentence naming an STM that is not opaque would need its
   own reading.
5. Whether Howard and Walpole is the source Mathieu remembered is not
   established; `[[waiver]]` and early release (already cited) are the other
   candidates.
