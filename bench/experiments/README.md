# Experiments

Systematic comparison of layout approaches.

Each experiment is a named configuration (version) applied to a fixed set of fixtures.
Results are reproducible: same version + same fixture = same output.

## Running

```sh
# Compare all versions on the standard fixture set:
node experiments/compare.mjs

# Output: experiments/results/<timestamp>/comparison.html
```

## Versions

Each version is a named configuration in `versions.mjs`. Adding a new version
means adding an entry there — no code changes needed.

## Metrics

Per version × fixture:
- Crossing count (on rendered polylines, not abstract edges)
- Edge overlap count (edges sharing identical Y at both endpoints)
- Direction changes (Y-reversals along routes)
- Trunk straightness (Y variance of trunk nodes)
- Total edge length
- Bounding box area
