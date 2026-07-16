# Shared build rules for the urcu-txn paper series.
#
# Each paper's Makefile sets PAPER (the main .tex basename, without extension)
# and includes this file:
#
#     PAPER = main
#     include ../common/paper.mk
#
# Targets:
#   make            build the PDF (bibtex run automatically when needed)
#   make draft      build with TODO/CITE/NOTE markers visible
#   make arxiv      build the arXiv submission tarball (see below)
#   make clean      remove build artifacts, keep the PDF
#   make distclean  remove everything generated

PAPER    ?= main
COMMON   := ../common
BIB      := $(COMMON)/urcu-txn.bib
LATEX    := pdflatex -interaction=nonstopmode -halt-on-error
STAGE    := arxiv-stage
TARBALL  := $(PAPER)-arxiv.tar.gz

.PHONY: all draft arxiv clean distclean force check-refs check-abstract

# Belt and braces: make's default goal is the first target RULE in the file, so
# adding a rule above `all` silently hijacks a bare `make`. Pin it explicitly.
.DEFAULT_GOAL := all

all: $(PAPER).pdf

# ---------------------------------------------------------------------------
# Build mode tracking.
#
# The draft/final mode changes the OUTPUT but is not itself a file the PDF
# depends on. Without tracking it, `make` after `make draft` finds the PDF
# newer than every prerequisite, skips the rebuild, and leaves a PDF with TODO
# markers sitting there looking final -- i.e. you ship the draft. mode.txt is
# rewritten only when the mode actually changes, so it works as a real
# prerequisite and forces exactly the rebuilds that are needed.
# ---------------------------------------------------------------------------
MODE := $(if $(wildcard draft.flag),draft,final)

mode.txt: force
	@echo "$(MODE)" | cmp -s - $@ 2>/dev/null || echo "$(MODE)" > $@

force:

# Three passes: refs, then bibtex, then two more to settle cross-refs and
# cleveref. Cheap enough that tracking which passes are actually needed costs
# more than just running them.
# $(BIB) via wildcard: the bibliography is assembled separately, and a missing
# one must not block a skeleton build.
$(PAPER).pdf: $(PAPER).tex $(COMMON)/preamble.tex $(COMMON)/macros.tex $(wildcard $(BIB)) mode.txt
	$(LATEX) $(PAPER).tex
	@# bibtex's exit code is ignored on purpose -- a skeleton with no \cite yet
	@# makes it exit nonzero ("I found no \citation commands"), which is fine.
	@# But a MALFORMED bib also exits nonzero and silently drops entries,
	@# leaving [?] in the PDF while the build reports success. So the .blg is
	@# inspected explicitly rather than trusting the exit code.
	-@bibtex $(PAPER) >/dev/null 2>&1
	@if [ -f $(PAPER).blg ] && grep -qE "I was expecting|Illegal|I couldn't open|--line [0-9]+ of file" $(PAPER).blg; then \
		echo "=== BIBTEX ERRORS (entries may have been silently dropped):"; \
		grep -E "I was expecting|Illegal|I couldn't open|--line [0-9]+ of file" $(PAPER).blg | sed 's/^/    /'; \
		exit 1; \
	fi
	@if [ -f $(PAPER).blg ] && grep -q "didn't find a database entry" $(PAPER).blg; then \
		echo "=== MISSING BIB ENTRIES:"; \
		grep "didn't find a database entry" $(PAPER).blg | sed 's/^/    /'; \
	fi
	$(LATEX) $(PAPER).tex
	$(LATEX) $(PAPER).tex
	@$(MAKE) --no-print-directory check-refs
	@$(MAKE) --no-print-directory check-terms
	@$(MAKE) --no-print-directory check-escapes
	@$(MAKE) --no-print-directory check-abstract

# The recursive make re-evaluates MODE with draft.flag present, so mode.txt
# changes and the PDF rebuilds. Trap on exit so a mid-build latex failure never
# leaves the flag behind to poison the next submission build.
draft:
	@touch draft.flag
	@trap 'rm -f draft.flag' EXIT; $(MAKE) --no-print-directory $(PAPER).pdf

# ---------------------------------------------------------------------------
# arXiv submission.
#
# AutoTeX unpacks a submission into a SINGLE directory, so any \input{../common/...}
# escapes the submission root and fails there while working fine locally. This
# target stages a flat, self-contained copy and rewrites those paths.
#
# The .bbl is included deliberately: arXiv does run bibtex/biblatex now, but
# shipping a pre-generated .bbl removes a build variable, and we use natbib
# precisely because its .bbl format is not version-locked the way biblatex's is.
#
# The staged tree is compiled once before packing, so a broken submission is
# caught here rather than by AutoTeX after upload.
# ---------------------------------------------------------------------------
arxiv: $(PAPER).pdf
	@# A submission with [?] in it is not a submission. Unlike the normal build,
	@# this is fatal. Matches check-refs: trigger on the summary lines, because
	@# the per-citation message wraps at 79 columns and a long key splits the
	@# word "undefined" clean in half.
	@if grep -qE "There were undefined (references|citations)" $(PAPER).log 2>/dev/null; then \
		echo "=== REFUSING TO PACKAGE: undefined citations/references:"; \
		grep -ohE "Citation \`[^']+'|Reference \`[^']+'" $(PAPER).log | sort -u | sed 's/^/    /'; \
		exit 1; \
	fi
	@if [ -f draft.flag ] || [ "$$(cat mode.txt 2>/dev/null)" = "draft" ]; then \
		echo "=== REFUSING TO PACKAGE: last build was a DRAFT (markers would ship)."; \
		echo "    Run 'make' first, then 'make arxiv'."; \
		exit 1; \
	fi
	@rm -rf $(STAGE) $(TARBALL)
	@mkdir -p $(STAGE)
	@cp $(PAPER).tex $(STAGE)/
	@cp $(COMMON)/preamble.tex $(COMMON)/macros.tex $(STAGE)/
	@# Any \input'd fragments living beside the paper (figures drawn in TikZ,
	@# tables, etc). Without this the staged copy fails to compile -- which the
	@# verification step below catches, but only if these are meant to be here.
	@for f in fig-*.tex tab-*.tex; do [ -e "$$f" ] && cp "$$f" $(STAGE)/ || true; done
	@cp $(PAPER).bbl $(STAGE)/ 2>/dev/null || { echo "ERROR: no $(PAPER).bbl -- run 'make' first"; exit 1; }
	@if [ -d figures ]; then cp -r figures $(STAGE)/; fi
	@if [ -d data ]; then cp -r data $(STAGE)/; fi
	@sed -i 's|\.\./common/preamble|preamble|g; s|\.\./common/macros|macros|g' $(STAGE)/$(PAPER).tex
	@sed -i 's|\\bibliography{\.\./common/urcu-txn}|\\bibliography{urcu-txn}|g' $(STAGE)/$(PAPER).tex
	@echo "=== verifying staged submission compiles standalone..."
	@cd $(STAGE) && $(LATEX) $(PAPER).tex >/dev/null 2>&1 && $(LATEX) $(PAPER).tex >/dev/null 2>&1 \
		|| { echo "ERROR: staged copy does not compile -- fix before uploading"; exit 1; }
	@cd $(STAGE) && rm -f *.aux *.log *.out *.toc *.blg $(PAPER).pdf
	@tar czf $(TARBALL) -C $(STAGE) .
	@echo "=== $(TARBALL) ready:"
	@tar tzf $(TARBALL) | sed 's/^/    /'
	@echo "=== size: $$(du -h $(TARBALL) | cut -f1)"

# Reports undefined citations/references. A work-in-progress paper legitimately
# has these, so this WARNS rather than fails -- but `arxiv` treats it as fatal,
# because a submission with [?] in it is not a submission.
# Defined AFTER `all` so it cannot become the default goal.
# Trigger on LaTeX's SUMMARY lines, not the per-citation ones.
#
# Why: LaTeX hard-wraps .log lines at 79 columns, so a long key splits the
# message --
#   Package natbib Warning: Citation `mckenney2016beyondissaquah' on page 1 undefin
# -- and a "Citation .* undefined" regex silently MISSES it. This is not
# hypothetical: it shipped a false "refs OK" on a document rendering "[?]",
# and the identical regex in the arxiv guard would have packaged it. The
# summary lines ("There were undefined citations/references.") are short, never
# wrap, and are emitted whenever anything is undefined.
check-refs:
	@if grep -qE "There were undefined (references|citations)" $(PAPER).log 2>/dev/null; then \
		echo "=== WARNING: undefined citations/references:"; \
		grep -ohE "Citation \`[^']+'|Reference \`[^']+'" $(PAPER).log | sort -u | sed 's/^/    /' | head -20; \
	else \
		echo "=== refs OK: no undefined citations or references"; \
	fi

# Terminology audit. The series' central claim is that this engine is NOT STM,
# and the words carry that claim -- so the banned words are checked mechanically
# rather than left to editing discipline. Warns, never fails: a legitimate use
# exists for every one of these (naming prior art, or stating what we do NOT
# provide). The point is that each hit must be a DELIBERATE choice.
#   serializable / opacity  -> we do not provide these
#   causal                  -> collides with causal consistency, a WEAKER model
#   per-slot lineariz*      -> undersells; the guarantee is "never new-then-old"
# Bare "transaction" is not checked here: proper nouns (software transactional
# memory, transactional boosting) make it too noisy to be useful.
.PHONY: check-terms
check-terms:
	@# Whole lines, not grep -o matches: -o prints only the matched word, which
	@# strips the leading '%' and makes the comment filter below a no-op.
	@# "reader is not a \pseudotxn" is a real defect, not a style nit: it parses
	@# equally well as "not MERELY a pseudo-transaction (it gets a real one)",
	@# the exact inverse of the claim. The rule is "not a transaction of any
	@# kind". The \pseudotxn macro makes this drift mechanical -- it happened in
	@# five places at once -- so it is checked rather than left to vigilance.
	@# The windowed .{0,12} is deliberate: the phrase appears both bare and
	@# wrapped ("reader is \emph{not} a \pseudotxn"), and a regex anchored on
	@# "not a" silently misses the wrapped form -- which is exactly how the
	@# first version of this check passed while the defect was still present.
	@hits=$$(grep -niE 'serializab|opacity|[^-]causal|per-slot lineariz|reader is .{0,12}not.{0,2} a .{0,2}pseudotxn' $(PAPER).tex 2>/dev/null | grep -viE '^[0-9]+:[[:space:]]*%' | cut -c1-100 || true); \
	if [ -n "$$hits" ]; then \
		echo "=== TERMINOLOGY: review each -- must be deliberate (see README framing rule):"; \
		printf "%s\n" "$$hits" | sed 's/^/    /'; \
	else \
		echo "=== terms OK: no banned framing words"; \
	fi

# Bare LaTeX specials in editorial macro arguments.
#
# \TODO/\NOTE gobble their argument in a SUBMISSION build, so an unescaped _ or
# & inside one is invisible there and blows up only under `make draft` -- i.e.
# the failure hides until the moment you want to read your own notes. Identifier
# names (rcu_head, *_prepare, -DFOO_BAR) are exactly what these notes are full
# of, so this is a recurring, not a hypothetical, bug.
#
# Checks non-comment lines for an unescaped underscore. Warns only: a legitimate
# bare _ exists inside \code{}/\texttt{}/verbatim and in math mode.
.PHONY: check-escapes
check-escapes:
	@hits=$$(grep -nE '^[^%]*[^\\]_' $(PAPER).tex 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*%' | cut -c1-90 || true); \
	if [ -n "$$hits" ]; then \
		printf '%s\n' "=== BARE UNDERSCORE (fine in \\code{}/math; breaks draft builds in \\NOTE/\\TODO):"; \
		printf "%s\n" "$$hits" | sed 's/^/    /'; \
	else \
		echo "=== escapes OK: no bare underscores outside comments"; \
	fi

# arXiv's abstract METADATA field is capped at 1920 characters. The submission
# form silently truncates or rejects past that, and you find out at upload time
# with the paper otherwise ready to go -- so the cap is checked at build time.
#
# Counted from the rendered PDF, not the .tex: our macros expand to text LONGER
# than the source token (\pseudotxn -> "pseudo-transaction"), so counting source
# characters undercounts, which is the one direction that matters for a limit.
#
# wc -m, NOT wc -c: em-dashes and arrows are 3 bytes each in UTF-8, and a byte
# count reads ~25 chars over on a typical abstract. That difference is entirely
# capable of sending you editing prose that was already within the cap.
#
# The count is printed ALWAYS, not just on violation. The extraction range is a
# heuristic (page 1, "Abstract" to the page-number line), so a silently broken
# range must stay visible -- an earlier version of this check matched nothing,
# counted the whole document, and reported 10146 for a 400-word abstract. A
# number on every build is what makes that self-evident rather than a false OK.
ABSTRACT_MAX ?= 1920
check-abstract:
	@n=$$(pdftotext -f 1 -l 1 $(PAPER).pdf - 2>/dev/null \
	      | sed -n '/^Abstract/,/^1$$/p' | sed '1d;$$d' \
	      | tr -s ' \n' ' ' | wc -m); \
	if [ "$$n" -le 1 ]; then \
		echo "=== abstract: extraction found nothing -- check the range in check-abstract"; \
	elif [ "$$n" -gt $(ABSTRACT_MAX) ]; then \
		echo "=== ABSTRACT TOO LONG for arXiv: $$n chars > $(ABSTRACT_MAX) (metadata field cap)"; \
	else \
		echo "=== abstract OK: $$n / $(ABSTRACT_MAX) chars"; \
	fi

clean:
	rm -f *.aux *.log *.out *.toc *.bbl *.blg *.synctex.gz *.fdb_latexmk *.fls draft.flag mode.txt
	rm -rf $(STAGE)

distclean: clean
	rm -f $(PAPER).pdf $(TARBALL)
