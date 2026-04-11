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
