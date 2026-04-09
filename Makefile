# Makefile — convenience targets for bench operations

.PHONY: fetch-corpora bench-report bench-test

fetch-corpora:
	node bench/scripts/fetch-corpora.mjs

bench-report:
	node bench/scripts/report-cli.mjs

bench-test:
	cd bench && npm test
