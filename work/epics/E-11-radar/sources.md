# Radar Sources

Curated source list for the Radar pack. Each source has an enabled flag for quick toggling.
Sources are organized by category. Health metrics are tracked per-run by the pipeline.

Last curated: 2026-04-01

## AI / LLM Orchestration & Agents

| # | Name | Type | URL | Feed URL | Tags | Enabled | Freq |
|---|------|------|-----|----------|------|---------|------|
| 1 | Anthropic News | rss | anthropic.com/news | `https://raw.githubusercontent.com/taobojlen/anthropic-rss-feed/main/anthropic_news_rss.xml` | ai, llm, anthropic | yes | 2-4x/mo |
| 2 | Anthropic Engineering | rss | anthropic.com/engineering | `https://raw.githubusercontent.com/conoro/anthropic-engineering-rss-feed/main/anthropic_engineering_rss.xml` | ai, llm, anthropic, engineering | yes | 1-2x/mo |
| 3 | OpenAI Blog | rss | openai.com/news | `https://openai.com/news/rss.xml` | ai, llm, openai | yes | 4-8x/mo |
| 4 | Google DeepMind Blog | rss | deepmind.google/blog | `https://deepmind.google/blog/rss.xml` | ai, research | yes | 4-6x/mo |
| 5 | Hugging Face Blog | rss | huggingface.co/blog | `https://huggingface.co/blog/feed.xml` | ai, ml, open-source, embeddings | yes | 4-8x/mo |
| 6 | LangChain Blog | rss | blog.langchain.com | `https://blog.langchain.com/rss` | ai, orchestration, agents | yes | 3-5x/mo |
| 7 | Simon Willison's Weblog | rss | simonwillison.net | `https://simonwillison.net/atom/everything/` | ai, llm, tooling, high-signal | yes | daily |
| 8 | arXiv cs.AI | rss | arxiv.org | `https://rss.arxiv.org/rss/cs.AI` | ai, research, academic | yes | daily (high vol) |
| 9 | arXiv cs.CL | rss | arxiv.org | `https://rss.arxiv.org/rss/cs.CL` | ai, nlp, research, academic | yes | daily (high vol) |

## Elixir / Erlang / BEAM

| # | Name | Type | URL | Feed URL | Tags | Enabled | Freq |
|---|------|------|-----|----------|------|---------|------|
| 10 | Elixir Forum | rss | elixirforum.com | `https://elixirforum.com/latest.rss` | elixir, community | yes | daily |
| 11 | Official Elixir Blog | rss | elixir-lang.org/blog | `https://elixir-lang.org/blog/atom.xml` | elixir, releases | yes | monthly |
| 12 | Erlang/OTP News | web | erlang.org/news | — | erlang, otp, releases | yes | monthly |
| 13 | BEAM Bloggers Webring | rss | beambloggers.com | `https://beambloggers.com/feed.xml` | elixir, erlang, beam | yes | daily |
| 14 | Underjord (Lars Wikman) | rss | underjord.io | `https://underjord.io/feed.xml` | elixir, beam, deep-dives | yes | 2-4x/mo |
| 15 | Fly.io Blog | rss | fly.io/blog | `https://fly.io/blog/feed.xml` | elixir, phoenix, infra | yes | 2-4x/mo |
| 16 | Fly.io Phoenix Files | rss | fly.io/phoenix-files | `https://fly.io/phoenix-files/feed.xml` | elixir, phoenix, liveview | yes | 1-2x/mo |
| 17 | Erlang Solutions Blog | web | erlang-solutions.com/blog | — | elixir, erlang, production | yes | 2-4x/mo |
| 18 | Planet Erlang | rss | planeterlang.com | `http://www.planeterlang.com/rss20.xml` | erlang, aggregator | yes | weekly |
| 19 | BEAM Radio Podcast | rss | podcast | `https://feeds.fireside.fm/beamradio/rss` | elixir, erlang, gleam | yes | biweekly |
| 20 | Elixir Status | rss | elixirstatus.com | `https://elixirstatus.com/rss` | elixir, community, projects | yes | daily |

## EU Sustainability & Compliance

| # | Name | Type | URL | Feed URL | Tags | Enabled | Freq |
|---|------|------|-----|----------|------|---------|------|
| 21 | EFRAG News | web | efrag.org/en/news-and-calendar/news | — | esrs, vsme, standards | yes | 2-4x/mo |
| 22 | ESG Today | rss | esgtoday.com | — | esg, csrd, regulation | yes | daily |
| 23 | EEA Press Releases | rss | eea.europa.eu | `https://www.eea.europa.eu/en/newsroom/rss-feeds/eeas-press-releases-rss` | eu, environment, policy | yes | 2-4x/mo |
| 24 | EEA Featured Articles | rss | eea.europa.eu | `https://www.eea.europa.eu/en/newsroom/rss-feeds/featured-articles-rss` | eu, environment, analysis | yes | 1-2x/mo |
| 25 | EEA Publications | rss | eea.europa.eu | `https://www.eea.europa.eu/en/newsroom/rss-feeds/publications-rss` | eu, environment, data | yes | 1-2x/mo |
| 26 | EC Environment News | web | environment.ec.europa.eu | — | eu, csrd, eudr, dpp, policy | yes | 2-4x/mo |
| 27 | Circularise Blog | web | circularise.com/blogs | — | dpp, supply-chain, espr | yes | 2-4x/mo |
| 28 | Coolset Academy | web | coolset.com/academy | — | esrs, csrd, eudr, guides | yes | 2-4x/mo |
| 29 | ESG Dive | web | esgdive.com | — | esg, regulation, corporate | yes | daily |

## Reproducible Computation / Workflow Engines

| # | Name | Type | URL | Feed URL | Tags | Enabled | Freq |
|---|------|------|-----|----------|------|---------|------|
| 30 | Dagster Blog | web | dagster.io/blog | — | dag, orchestration, python | yes | 2-4x/mo |
| 31 | Prefect Blog | web | prefect.io/blog | — | orchestration, python | yes | 2-4x/mo |
| 32 | Temporal Blog | web | temporal.io/blog | — | durable-execution, replay, events | yes | 2-4x/mo |
| 33 | DVC Blog | rss | dvc.org/blog | `https://dvc.org/blog/rss.xml` | reproducibility, ml, versioning | yes | 1-2x/mo |
| 34 | MLflow Blog | web | mlflow.org/blog | — | experiment-tracking, ml | yes | 1-2x/mo |
| 35 | NixOS Discourse | web | discourse.nixos.org | — | reproducibility, content-addressed | no | daily (high vol) |

## General Tech (filtered)

| # | Name | Type | URL | Feed URL | Tags | Enabled | Freq |
|---|------|------|-----|----------|------|---------|------|
| 36 | Lobsters (elixir+ai+ml) | rss | lobste.rs | `https://lobste.rs/t/elixir,ai,ml.rss` | tech, curated | yes | daily |
| 37 | Lobsters (distributed) | rss | lobste.rs | `https://lobste.rs/t/distributed.rss` | tech, distributed | yes | weekly |

## Hacker News (keyword-filtered via hnrss.org)

| # | Name | Type | URL | Feed URL | Tags | Enabled | Freq |
|---|------|------|-----|----------|------|---------|------|
| 38 | HN: Elixir | rss | hnrss.org | `https://hnrss.org/newest?q=elixir&points=5` | elixir, hn | yes | weekly |
| 39 | HN: LLM orchestration | rss | hnrss.org | `https://hnrss.org/newest?q=LLM+orchestration+OR+LangChain+OR+LangGraph&points=5` | ai, orchestration, hn | yes | weekly |
| 40 | HN: Reproducibility | rss | hnrss.org | `https://hnrss.org/newest?q=reproducible+computation+OR+reproducible+builds+OR+content-addressed&points=5` | reproducibility, hn | yes | weekly |
| 41 | HN: EU compliance | rss | hnrss.org | `https://hnrss.org/newest?q=CSRD+OR+ESRS+OR+digital+product+passport+OR+EU+AI+Act&points=3` | eu, compliance, hn | yes | weekly |
| 42 | HN: DAG workflows | rss | hnrss.org | `https://hnrss.org/newest?q=Dagster+OR+Prefect+OR+Temporal+OR+workflow+orchestration&points=5` | orchestration, hn | yes | weekly |
| 43 | HN: Erlang/BEAM | rss | hnrss.org | `https://hnrss.org/newest?q=erlang+OR+BEAM+OR+OTP&points=5` | erlang, beam, hn | yes | weekly |

## Swedish / Nordic Tech

| # | Name | Type | URL | Feed URL | Tags | Enabled | Freq |
|---|------|------|-----|----------|------|---------|------|
| 44 | Swedish Tech News | rss | swedishtechnews.com | `https://www.swedishtechnews.com/rss` | swedish, startups | yes | 5x/week |
| 45 | The Nordic Web | web | thenordicweb.com | — | nordic, startups | yes | weekly |
| 46 | Arctic Startup | web | arcticstartup.com | — | nordic, baltic, startups | yes | 2-4x/mo |

## Meta / Aggregators

| # | Name | Type | URL | Feed URL | Tags | Enabled | Freq |
|---|------|------|-----|----------|------|---------|------|
| 47 | Planet AI | rss | planet-ai.net | — | ai, aggregator | no | daily (high vol) |

---

## Source Types

- **rss** — standard RSS/Atom feed, parsed by feedparser
- **web** — no RSS feed available; fetch HTML page + extract with trafilatura. May need page-specific selectors.
- **api** — structured API (e.g., HN Algolia API as alternative to hnrss.org RSS)

## Notes

- Sources marked `enabled: no` are available but disabled by default (high volume or lower signal)
- arXiv feeds are high-volume (~50-100 items/day each). The dedup pipeline will naturally filter most. Consider adding keyword pre-filters in the fetch op.
- Web-type sources without RSS feeds need HTML fetching + extraction. These are more fragile — monitor health closely.
- Anthropic RSS feeds are community-maintained (GitHub repos). May lag or break. Consider adding direct HTML fetch as fallback.
- HN keyword feeds via hnrss.org have a `points=N` minimum score filter to reduce noise.
- NixOS Discourse disabled by default — very high volume, niche relevance.
- Planet AI disabled by default — aggregates many sources already in the list individually.

## Adding Sources

To add a source:
1. Add a row to the appropriate category table
2. Set `enabled: yes`
3. Run `mix radar.run` — new source appears in source health report
4. After a few runs, check contribution metrics

## Culling Sources

Sources are candidates for culling when:
- Zero items surviving dedup for 7+ consecutive runs
- Persistent fetch errors (HTTP 4xx/5xx, timeout) for 3+ runs
- All items are duplicates of other sources (redundant)

Review source health dashboard (M-RAD-04) and set `enabled: no`.
