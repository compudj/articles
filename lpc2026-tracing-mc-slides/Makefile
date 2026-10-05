# LPC 2026 Tracing Microconference: the slides.
#
#   make         build main.pdf, then run the checks below
#   make clean   remove build artifacts, keep the PDF
#
# XeLaTeX, not pdflatex: the fonts come from fontconfig -- IBM Plex when it is
# installed (Debian: fonts-ibm-plex), Lato + Noto Sans Mono otherwise -- and
# pdflatex cannot reach them.
#
# Builds run under nice/ionice: the machine building the deck may also be
# running benchmarks, and a LaTeX build must not perturb them.

DECK  := main
NICE  := nice -n 19 ionice -c3
LATEX := $(NICE) xelatex -interaction=nonstopmode -halt-on-error

.PHONY: all check check-overfull check-frame-open clean distclean
.DEFAULT_GOAL := all

all: $(DECK).pdf

# Two passes: the footer's frame number settles on the second.
$(DECK).pdf: $(DECK).tex
	$(LATEX) $(DECK).tex
	$(LATEX) $(DECK).tex
	@$(MAKE) --no-print-directory check

check: check-overfull check-frame-open

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
# title template does not show subtitles, so the content silently vanishes.
check-frame-open:
	@hits=$$(awk '/\\begin\{frame\}/ {f=1; next} f && /[^[:space:]]/ {if ($$0 ~ /^[[:space:]]*\{/) print FNR": "$$0; f=0}' $(DECK).tex | cut -c1-100); \
	if [ -n "$$hits" ]; then \
		echo "=== FRAME OPENS WITH A BRACE GROUP (swallowed as a subtitle):"; \
		printf '%s\n' "$$hits" | sed 's/^/    /'; \
	else \
		echo "=== frame openings OK"; \
	fi

clean:
	rm -f *.aux *.log *.nav *.out *.snm *.toc *.vrb *.fls *.fdb_latexmk

distclean: clean
	rm -f $(DECK).pdf
