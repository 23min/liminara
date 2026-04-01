defmodule LiminaraObservation.MixProject do
  use Mix.Project

  def project do
    [
      app: :liminara_observation,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Liminara.Observation.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:liminara_core, in_umbrella: true},
      {:phoenix_pubsub, "~> 2.1"},
      {:jason, "~> 1.4"},
      {:ex_a2ui, path: "../../../ex_a2ui"},
      {:gun, "~> 2.1", only: :test}
    ]
  end
end
