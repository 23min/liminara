# LiminaraRadar

Radar pack — daily intelligence briefing pipeline. Fetches ~47 sources, extracts and embeds articles, clusters by topic, ranks by recency and relevance, and renders an HTML briefing. Python ops run via the `:port` executor; orchestration and replay live in Elixir. See `work/done/E-11-radar/` for the epic spec.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `liminara_radar` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:liminara_radar, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/liminara_radar>.

