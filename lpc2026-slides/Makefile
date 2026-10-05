# LPC 2026 talk: the slide deck.
#
#   make         build main.pdf, then run the checks below
#   make notes   build main-notes.pdf: every slide followed by its notes page
#   make clean   remove build artifacts, keep the PDFs
#   make dcache-data   rewrite data/ from the benchmark tree (BENCH=...)
#
# XeLaTeX, not pdflatex: the fonts come from fontconfig -- IBM Plex when it is
# installed (Debian: fonts-ibm-plex), Lato + Noto Sans Mono otherwise -- and
# pdflatex cannot reach them.
#
# Builds run under nice/ionice: the machine building the deck may also be
# running benchmarks, and a LaTeX build must not perturb them.

DECK  := main
P1    := ../p1-sw-flip-latch
NICE  := nice -n 19 ionice -c3
LATEX := $(NICE) xelatex -interaction=nonstopmode -halt-on-error

# fig-*.tex are \input by the deck and the plotted CSVs are read from P1 in
# place. make cannot see through either, and a stale PDF that reports success
# is worse than a failed build, so list them.
DEPS  := $(DECK).tex $(wildcard fig-*.tex) $(wildcard $(P1)/data/*.csv) \
         $(wildcard data/*) ../common/macros.tex efficios-logo.pdf

.PHONY: all notes check check-terms check-placeholders check-overfull \
        check-frame-open dcache-data \
        clean distclean
.DEFAULT_GOAL := all

all: $(DECK).pdf

# Two passes: the footer's frame total and TikZ's overlays settle on the second.
$(DECK).pdf: $(DEPS)
	$(LATEX) $(DECK).tex
	$(LATEX) $(DECK).tex
	@$(MAKE) --no-print-directory check

notes: $(DECK)-notes.pdf

$(DECK)-notes.pdf: $(DEPS)
	$(LATEX) -jobname=$(DECK)-notes '\def\withnotes{}\input{$(DECK)}'
	$(LATEX) -jobname=$(DECK)-notes '\def\withnotes{}\input{$(DECK)}'

# The dentry-cache slide's numbers, taken from the benchmark tree's sweep CSVs
# by that tree's own summary plot script. data/ is committed and never rebuilt
# implicitly: the benchmark tree is another repository, absent on the laptop.
# Reads CSVs only; runs no benchmark.
BENCH ?= $(HOME)/git/efficios-trie-benchmark
dcache-data:
	$(NICE) python3 dcache-summary.py $(BENCH)

check: check-terms check-placeholders check-overfull check-frame-open

# The series' framing guardrails (HANDOFF.md section 9, P1's README), checked
# mechanically as common/paper.mk checks the papers. Warns, never fails: "no
# opacity" is a legitimate thing for a slide to say. Each hit must be deliberate.
#   serializable / opacity  -> not provided
#   causal                  -> collides with causal consistency, a WEAKER model
#   bare "latch"            -> always "flip-latch"
#   "a reader is not a pseudo-transaction" -> "not a transaction of any kind"
check-terms:
	@hits=$$(grep -niE 'serializab|opacity|[^-]causal|per-slot lineariz|(^|[^-[:alpha:]])latch|reader is .{0,12}not.{0,2} a .{0,2}pseudo' $(DECK).tex fig-*.tex 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*%' | cut -c1-110 || true); \
	if [ -n "$$hits" ]; then \
		echo "=== TERMINOLOGY: review each -- must be deliberate (HANDOFF.md section 9):"; \
		printf '%s\n' "$$hits" | sed 's/^/    /'; \
	else \
		echo "=== terms OK: no banned framing words"; \
	fi

# Placeholders render as dashed orange boxes so they cannot be missed on
# screen; this lists them so they cannot be missed at build time either.
check-placeholders:
	@hits=$$(grep -nE '\\(placeholder|ph)\{' $(DECK).tex | grep -vE '^[0-9]+:[[:space:]]*%|newcommand' | cut -c1-100 || true); \
	if [ -n "$$hits" ]; then \
		echo "=== PLACEHOLDERS still in the deck:"; \
		printf '%s\n' "$$hits" | sed 's/^/    /'; \
	else \
		echo "=== placeholders: none"; \
	fi

# An overfull box on a slide is content running off its edge or into the
# footer: plain on the projector, silent in the build. Sub-point overruns are
# rounding, not layout, so only 1pt and up is reported.
check-overfull:
	@hits=$$(grep -E '^Overfull \\[hv]box \([1-9][0-9]*\.[0-9]+pt' $(DECK).log 2>/dev/null || true); \
	if [ -n "$$hits" ]; then \
		echo "=== OVERFULL (content off the slide?):"; \
		printf '%s\n' "$$hits" | sed 's/^/    /'; \
	else \
		echo "=== layout OK: no overfull boxes"; \
	fi

# A frame body that opens with a brace group loses it: beamer reads a group
# right after \begin{frame}{title} as the frame's SUBTITLE, and this deck's
# title template does not show subtitles, so the content silently vanishes
# with no warning and no overfull box. It happened twice while building the
# deck. Open with a command instead: \centerfig, \begingroup, \lead, ...
check-frame-open:
	@hits=$$(awk '/\\begin\{frame\}/ {f=1; next} f && /[^[:space:]]/ {if ($$0 ~ /^[[:space:]]*\{/) print FNR": "$$0; f=0}' $(DECK).tex | cut -c1-100); \
	if [ -n "$$hits" ]; then \
		echo "=== FRAME OPENS WITH A BRACE GROUP (swallowed as a subtitle):"; \
		printf '%s\n' "$$hits" | sed 's/^/    /'; \
	else \
		echo "=== frame openings OK"; \
	fi

clean:
	rm -f *.aux *.log *.nav *.out *.snm *.toc *.vrb *.listing *.fls *.fdb_latexmk

distclean: clean
	rm -f $(DECK).pdf $(DECK)-notes.pdf
