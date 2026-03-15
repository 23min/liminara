# Elixir Tooling Reference (2026)

Quality tools, AI aids, and development infrastructure for Elixir/OTP projects.
Last updated: 2026-03-15.

---

## Code quality stack

### Formatting: `mix format` + Quokka

`mix format` is built-in and non-negotiable. **Quokka** is a `mix format` plugin (fork of Adobe's Styler) that auto-fixes style issues on format — import sorting, pipe rewrites, deprecated code, number formatting, and more.

**Why Quokka over Styler:** Quokka reads your `.credo.exs` to decide which controversial rules to apply. Styler is all-or-nothing with no per-rule configuration. Quokka gives you the same rewrites with a safety valve for rules that cause semantic changes (e.g., `case true` → `if` doesn't raise on non-booleans).

```elixir
# mix.exs
{:quokka, "~> 2.12", only: [:dev, :test], runtime: false}
```

```elixir
# .formatter.exs
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Quokka],
  quokka: [
    only: [
      :blocks, :comment_directives, :configs, :defs,
      :deprecations, :module_directives, :pipes, :single_node, :tests
    ],
    files: %{included: ["lib/", "test/", "config/"], excluded: []}
  ]
]
```

- Quokka GitHub: https://github.com/emkguts/quokka
- Quokka hexdocs: https://hexdocs.pm/quokka/Quokka.html
- Styler (upstream): https://github.com/adobe/elixir-styler

### Static analysis: Credo

Standard linter for consistency, readability, refactoring opportunities. When using Quokka, disable the 28 overlapping Credo checks to avoid redundant work:

**Consistency:** `MultiAliasImportRequireUse`, `ParameterPatternMatching`
**Design:** `AliasUsage`
**Readability:** `AliasOrder`, `BlockPipe`, `LargeNumbers`, `ModuleDoc`, `MultiAlias`, `OneArityFunctionInPipe`, `ParenthesesOnZeroArityDefs`, `PipeIntoAnonymousFunctions`, `PreferImplicitTry`, `SinglePipe`, `StrictModuleLayout`, `StringSigils`, `UnnecessaryAliasExpansion`, `WithSingleClause`
**Refactor:** `CaseTrivialMatches`, `CondStatements`, `FilterCount`, `MapInto`, `MapJoin`, `NegatedConditionsInUnless`, `NegatedConditionsWithElse`, `PipeChainStart`, `RedundantWithClauseResult`, `UnlessWithElse`, `WithClauses`

```elixir
# mix.exs
{:credo, "~> 1.7", only: [:dev, :test], runtime: false}
```

- Credo GitHub: https://github.com/rrrene/credo

### Security: Sobelow

Security-focused static analysis for Phoenix apps. Catches SQL injection, XSS, directory traversal, hardcoded secrets. Add when Phoenix is introduced, not before.

```elixir
{:sobelow, "~> 0.13", only: [:dev, :test], runtime: false}
```

- Sobelow: https://github.com/nccgroup/sobelow

### Type checking: built-in type system + Dialyxir

Elixir's set-theoretic type system progression:

| Version    | Release  | Coverage                                                  |
|------------|----------|-----------------------------------------------------------|
| 1.17       | Jun 2024 | Patterns and guards                                       |
| 1.18       | Dec 2024 | Function calls, pattern/return type inference              |
| 1.19       | Oct 2025 | Protocols, anonymous functions, up to 4x faster compilation|
| 1.20       | Mid 2026 | All language constructs (RCs available since Jan 2026)     |
| 1.21       | Nov 2026 | Recursive and parametric types (planned)                   |

**Recommendation:** Target 1.20 for new projects. The built-in type warnings are on by default and catch real bugs at compile time — particularly valuable for AI-generated code.

Keep **Dialyxir** alongside for now. The built-in type system won't fully replace Dialyzer until ~1.22 (May 2027). They complement each other: built-in types are faster and catch more pattern errors; Dialyzer catches cross-module contract violations.

```elixir
{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
```

- Dialyxir: https://github.com/jeremyjh/dialyxir
- Type system blog posts: https://elixir-lang.org/blog/

### Validation pipeline

```bash
mix format --check-formatted
mix credo
mix dialyzer
mix test
```

---

## AI development aids

### HexDocs MCP server

Semantic search over Hex package documentation via MCP (Model Context Protocol). Lets AI assistants look up real OTP/Elixir/library docs instead of relying on training data. Uses vector embeddings + SQLite.

```bash
# Install
npx -y hexdocs-mcp-server
```

```json
// .claude/mcp.json (project-level) or ~/.claude/mcp.json (global)
{
  "mcpServers": {
    "hexdocs": {
      "command": "npx",
      "args": ["-y", "hexdocs-mcp-server"]
    }
  }
}
```

Tools: `resolve-library-id` (resolve name → Hex ID), `get-library-docs` (semantic doc search).

- GitHub: https://github.com/bradleygolden/hexdocs-mcp
- Hex: https://hex.pm/packages/hexdocs_mcp

### Context7 MCP server

Broader library documentation fetching, not Elixir-specific. Covers thousands of libraries across ecosystems. Good complement to HexDocs MCP.

- GitHub: https://github.com/upstash/context7

### What doesn't help AI assistants

**Language servers** (Expert LSP, ElixirLS, Lexical) help your *editor* with completions, go-to-definition, and inline diagnostics. They do NOT help Claude Code or other AI coding tools — those don't use LSP. Still worth setting up for your own editing experience.

---

## Language server: Expert LSP

The three community Elixir language servers (ElixirLS, Lexical, Next LS) merged into **Expert LSP** under the official `elixir-lang` org in August 2025. First RC (v0.1.0-rc.1) available late 2025.

| Version | Focus                                       |
|---------|---------------------------------------------|
| v0.1    | Stability, daily-driver ready               |
| v0.2    | Missing features from Next LS               |
| v0.3    | Missing features from ElixirLS              |
| v0.4    | Brand new features                          |

**For new projects:** Use Expert if comfortable with RC-stage software. ElixirLS remains the safe fallback until Expert v0.2+.

- Expert: https://github.com/elixir-lang/expert
- Website: https://expert-lsp.org/
- ElixirLS (legacy): https://github.com/elixir-lsp/elixir-ls

---

## Elixir MCP SDKs (for building MCP servers in Elixir)

If a project needs to expose capabilities via MCP (e.g., letting AI tools inspect runtime state):

- **Anubis MCP** — full MCP client/server SDK in Elixir, OTP supervision, GenServers. https://github.com/zoedsoupe/anubis-mcp
- **MCPEx** — MCP client implementation, spec-compliant. https://hexdocs.pm/mcp_ex/MCPEx.Client.html
- **erlmcp** — MCP SDK for Erlang, full OTP compliance. https://github.com/erlsci/erlmcp
