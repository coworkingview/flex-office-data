# Build the App Store tarball. The archive is unsigned: sign it with
# occ integrity:sign-app before upload. See ../PUBLISHING.md.

APP_ID := coworkingview
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
DIST := $(ROOT)/../dist
BUILD := $(ROOT)/build
STAGE := $(BUILD)/$(APP_ID)
TARBALL := $(DIST)/$(APP_ID).tar.gz

.PHONY: all npm-install build dist check clean test lint

all: dist

npm-install:
	npm ci

build: npm-install
	npm run build

dist: build
	rm -rf $(BUILD)
	mkdir -p $(STAGE)/js $(DIST)
	cp -a appinfo lib css img l10n $(STAGE)/
	cp -a js/. $(STAGE)/js/
	cp LICENSE README.md CHANGELOG.md $(STAGE)/
	find $(STAGE) -name '*.map' -delete
	tar -czf $(TARBALL) -C $(BUILD) $(APP_ID)
	python3 bin/check-tarball.py $(TARBALL)

check:
	python3 bin/check-tarball.py $(TARBALL)

test:
	composer test
	npm test

lint:
	composer lint
	npm run lint

clean:
	rm -rf $(BUILD) $(DIST) js node_modules vendor
