# MLCM Benchmark Fixtures

## Available Sources

### OpenMetroMaps (primary)
- **URL**: https://github.com/OpenMetroMapsData
- **Format**: `.omm` (XML) — stations with coordinates, lines with station sequences
- **Cities**: Berlin (272 stations), Vienna, and others
- **License**: ODbL (Open Data Commons)
- **Notes**: Data from OpenStreetMap. Includes geographic and schematic variants.

### Cities Used in MLCM Papers

| Paper | Author | Year | Cities |
|-------|--------|------|--------|
| Mixed-Integer Metro Maps | Nöllenburg, Wolff | 2006 | Sydney CityRail, Vienna |
| Multicriteria Optimization | Stott, Rodgers | 2004 | Atlanta MARTA, Bucharest, Mexico City, Stockholm |
| Metro Maps Using Bézier Curves | Nöllenburg, Wolff | 2011 | Sydney, Vienna, Berlin |
| Edge-Path Bundling | Wallinger et al. | 2022 | Lisbon (60), Montreal (68), Taipei (96), Moscow (204), Berlin (272), Paris (304) |

### No Standard Benchmark Suite
Unlike graph drawing (which has graphdrawing.org with North/Random DAGs), metro-map
research does NOT have a shared downloadable benchmark. Researchers extract data
from OpenStreetMap or transit agencies. OpenMetroMaps is the closest thing.

### Best Downloadable Sources (from deep research)

| Source | Networks | Format | URL |
|--------|----------|--------|-----|
| **octi.cs.uni-freiburg.de** | 8 cities (Freiburg, Vienna, Stuttgart, Berlin, Sydney, Chicago, London, NYC) | JSON/GeoJSON | https://octi.cs.uni-freiburg.de/ |
| **juliuste/transit-map** | 6 cities (Berlin U-Bahn, Vienna, Stockholm, Lisbon, Nantes, Montpellier) | JSON | https://github.com/juliuste/transit-map |
| **OpenMetroMaps** | Berlin, Vienna | XML (.omm) | https://github.com/OpenMetroMapsData |
| **25 Cities Dataset** | 25 cities (Adelaide to Winnipeg) | SQLite/GTFS/CSV | https://zenodo.org/records/1186215 |
| **GLaDOS/OSF** | Rome-Lib (11,528 graphs), AT&T, North DAGs | JSON/GraphML | https://osf.io/j7ucv/ |

### Key Metro Network Properties

| Network | Stations | Edges | Lines | Max Lines/Edge |
|---------|----------|-------|-------|----------------|
| Atlanta MARTA | 38 | ~40 | 2 | 2 |
| Bucharest | 44 | ~47 | 4 | 2 |
| Lisbon | 60 | ~65 | 4 | 2 |
| Montreal | 68 | ~72 | 4 | 2 |
| Vienna Metro | ~83 | ~86 | 5 | 3 |
| Taipei | 96 | ~100 | 5 | 3 |
| Sydney CityRail | ~174 | ~190 | ~15 | ~8 |
| Moscow | 204 | ~220 | ~12 | ~4 |
| London Underground | ~270 | ~300 | 11 | 6 |
| Berlin U-Bahn | ~272 | ~280 | 10 | 4 |
| Paris Metro | ~304 | ~350 | 16 | 5 |

### Key Finding
The **juliuste/transit-map** repo is the most directly usable — 6 networks in JSON with station coordinates and line assignments, ready to convert to our fixture format.

## Strategy for dag-map

Since we can't easily download the exact datasets used in papers, we'll:

1. **Create our own benchmark suite** inspired by the literature:
   - Small: 10-20 stations, 3-4 lines (like Atlanta MARTA)
   - Medium: 40-60 stations, 5-8 lines (like Lisbon)
   - Large: 100+ stations, 10+ lines (like Vienna)

2. **Hand-craft 3-5 benchmark fixtures** that test specific MLCM challenges:
   - Diamond pattern (lines merge and split)
   - Trunk with symmetric branches
   - Dense interchange (5+ lines through one station)
   - Long parallel runs
   - Fan-in/fan-out

3. **Keep North DAGs** for regression testing on pure-topology graphs

4. **Eventually import OpenMetroMaps** data for real-world validation
