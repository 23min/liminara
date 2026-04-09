# Tier C: External Benchmark Corpora

## Sources

- **North DAGs**: http://www.graphdrawing.org/data/north-graphml.tgz
  AT&T/Bell Labs graph collection curated by Stephen North.

- **Random DAGs**: http://www.graphdrawing.org/data/random-dag-graphml.tgz
  Randomly generated directed acyclic graphs from graphdrawing.org.

## License

These datasets are published by [graphdrawing.org](http://www.graphdrawing.org/)
for academic benchmarking purposes. The archives are **not redistributed** in
this repository — they are fetched on demand via `make fetch-corpora` (or
`node bench/scripts/fetch-corpora.mjs`).

The downloaded archives and extracted files are gitignored.

## Usage

```sh
# From repo root:
make fetch-corpora

# Or directly:
node bench/scripts/fetch-corpora.mjs
```

Archives land in this directory as `north-graphml.tgz` and
`random-dag-graphml.tgz`. The GraphML loader extracts and converts them into
the bench fixture shape at runtime.
