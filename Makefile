# Top-level build for the urcu-txn paper series.

PAPERS := p1-sw-flip-latch p2-sole-driver-mcas p3-programming-model p4-evaluation

# Only descend into papers that actually have a Makefile yet.
ACTIVE := $(foreach p,$(PAPERS),$(if $(wildcard $(p)/Makefile),$(p),))

.PHONY: all draft clean distclean $(ACTIVE)

all: $(ACTIVE)

$(ACTIVE):
	@echo "=== $@"
	@$(MAKE) --no-print-directory -C $@

draft:
	@for p in $(ACTIVE); do echo "=== $$p (draft)"; $(MAKE) --no-print-directory -C $$p draft; done

clean:
	@for p in $(ACTIVE); do $(MAKE) --no-print-directory -C $$p clean; done

distclean:
	@for p in $(ACTIVE); do $(MAKE) --no-print-directory -C $$p distclean; done
