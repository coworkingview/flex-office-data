EXTENSION = coworkingview
EXTVERSION = 0.1.0

DATA = sql/$(EXTENSION)--$(EXTVERSION).sql
DOCS = README.md Changes

REGRESS = coworkingview
REGRESS_OPTS = --inputdir=test
EXTRA_CLEAN = results regression.diffs regression.out

PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

.PHONY: check-snapshot bundle

check-snapshot:
	python3 $(srcdir)/tools/build_sql.py --check

# pgxn-bundle archives the git root when run inside this monorepo. Stage a
# copy outside the work tree so the zip root is the extension itself.
bundle: check-snapshot
	rm -f coworkingview-$(EXTVERSION).zip
	stage=$$(mktemp -d); \
	cp -a . "$$stage/"; \
	rm -rf "$$stage/results" "$$stage/log" "$$stage/regression.diffs" \
		"$$stage/regression.out" "$$stage/tools/__pycache__" \
		"$$stage/coworkingview-$(EXTVERSION).zip"; \
	(cd "$$stage" && pgxn-bundle); \
	mv "$$stage/coworkingview-$(EXTVERSION).zip" .; \
	rm -rf "$$stage"
