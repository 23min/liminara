[
  inputs: ["{mix,.formatter}.exs", "config/**/*.{ex,exs}"],
  plugins: [Quokka],
  quokka: [
    only: [
      :blocks,
      :comment_directives,
      :configs,
      :defs,
      :deprecations,
      :module_directives,
      :pipes,
      :single_node,
      :tests
    ],
    files: %{included: ["lib/", "test/", "config/"], excluded: []}
  ],
  subdirectories: ["apps/*"]
]
