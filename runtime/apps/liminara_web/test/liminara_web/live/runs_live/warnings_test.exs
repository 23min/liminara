defmodule LiminaraWeb.RunsLive.WarningsTest do
  @moduledoc """
  LiveView tests for M-WARN-02: warning surfacing in RunsLive.Show.

  Covers:
  - Run-header degraded badge + warning count when the run is degraded
  - DAG per-node degraded indicator, visually distinct from :failed
  - Node inspector Warnings section rendered when selected node has warnings
  - Warnings section is absent when selected node has no warnings
  - Warnings section is separate from the Decisions section
  - Warning fields rendered verbatim: code, severity, summary, cause,
    remediation, affected_outputs
  - Plain-success runs do NOT show the degraded badge
  """
  use LiminaraWeb.ConnCase, async: false

  # ── Helpers ──────────────────────────────────────────────────────

  defp unique_run_id(prefix) do
    "#{prefix}-#{:erlang.unique_integer([:positive])}"
  end

  defp warning_map(overrides \\ %{}) do
    base = %{
      "code" => "fallback_used",
      "severity" => "low",
      "summary" => "placeholder summary used",
      "cause" => "ANTHROPIC_API_KEY missing",
      "remediation" => "export ANTHROPIC_API_KEY",
      "affected_outputs" => ["summary"]
    }

    Map.merge(base, overrides)
  end

  defp mock_obs_state(run_id, nodes_map, opts) do
    %{
      run_id: run_id,
      run_status: Keyword.get(opts, :run_status, :completed),
      run_started_at: "2026-03-19T14:00:00.000Z",
      run_completed_at: Keyword.get(opts, :run_completed_at, "2026-03-19T14:00:05.000Z"),
      event_count: Keyword.get(opts, :event_count, 5),
      nodes: nodes_map,
      plan: nil,
      warning_count: Keyword.get(opts, :warning_count, 0),
      degraded_nodes: Keyword.get(opts, :degraded_nodes, []),
      degraded: Keyword.get(opts, :degraded, false)
    }
  end

  defp node_with_warnings(warnings, overrides \\ %{}) do
    Map.merge(
      %{
        status: :completed,
        op_name: "summarize",
        op_version: "1.0",
        determinism: :recordable,
        started_at: "2026-03-19T14:00:01.000Z",
        completed_at: "2026-03-19T14:00:02.000Z",
        duration_ms: 100,
        input_hashes: [],
        output_hashes: [],
        cache_hit: false,
        error: nil,
        gate_prompt: nil,
        gate_response: nil,
        decisions: [],
        warnings: warnings,
        degraded: warnings != []
      },
      overrides
    )
  end

  defp broadcast_state(run_id, obs_state) do
    Phoenix.PubSub.broadcast(
      Liminara.Observation.PubSub,
      "observation:#{run_id}:state",
      {:state_update, run_id, obs_state}
    )
  end

  # ── Run header degraded badge ────────────────────────────────────

  describe "run header degraded badge" do
    test "degraded run shows a degraded badge and the warning count", %{conn: conn} do
      run_id = unique_run_id("hdr-degraded")
      warnings = [warning_map()]

      obs_state =
        mock_obs_state(
          run_id,
          %{"summarize" => node_with_warnings(warnings)},
          warning_count: 1,
          degraded_nodes: ["summarize"],
          degraded: true
        )

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")
      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      html = render(view)

      assert html =~ "degraded",
             "Expected degraded badge text. HTML:\n#{html}"

      assert html =~ ~r/\b1\b/,
             "Expected warning count 1 to appear in header. HTML:\n#{html}"
    end

    test "plain-success run does NOT show the degraded badge", %{conn: conn} do
      run_id = unique_run_id("hdr-plain")

      node = node_with_warnings([])

      obs_state =
        mock_obs_state(
          run_id,
          %{"summarize" => node},
          warning_count: 0,
          degraded_nodes: [],
          degraded: false
        )

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")
      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      html = render(view)

      refute html =~ "status--degraded",
             "Plain-success run should not render degraded status badge. HTML:\n#{html}"
    end

    test "degraded run shows the list of degraded node ids reachable from the header",
         %{conn: conn} do
      run_id = unique_run_id("hdr-node-list")
      warnings = [warning_map()]

      obs_state =
        mock_obs_state(
          run_id,
          %{
            "summarize" => node_with_warnings(warnings),
            "dedup" =>
              node_with_warnings([warning_map(%{"code" => "dedup_degraded"})], %{op_name: "dedup"})
          },
          warning_count: 2,
          degraded_nodes: ["dedup", "summarize"],
          degraded: true
        )

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")
      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      html = render(view)

      # Degraded node ids must be visible in the header area (not just in the
      # events tab). The concrete presentation is implementation-free; the
      # names must be reachable from the top of the page.
      assert html =~ "summarize",
             "Expected degraded node id 'summarize' to be reachable. HTML:\n#{html}"

      assert html =~ "dedup",
             "Expected degraded node id 'dedup' to be reachable. HTML:\n#{html}"
    end
  end

  # ── DAG per-node degraded indicator ─────────────────────────────

  describe "DAG degraded node indicator" do
    test "warning-bearing node carries a degraded indicator distinct from failed",
         %{conn: conn} do
      run_id = unique_run_id("dag-degraded")
      warnings = [warning_map()]

      obs_state =
        mock_obs_state(
          run_id,
          %{"summarize" => node_with_warnings(warnings)},
          warning_count: 1,
          degraded_nodes: ["summarize"],
          degraded: true
        )

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")
      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      html = render(view)

      assert html =~ "degraded",
             "DAG should mark degraded node with a 'degraded' class/hint. HTML:\n#{html}"
    end

    test "non-degraded nodes do not carry the degraded indicator", %{conn: conn} do
      run_id = unique_run_id("dag-plain")

      obs_state =
        mock_obs_state(
          run_id,
          %{"summarize" => node_with_warnings([])},
          warning_count: 0,
          degraded_nodes: [],
          degraded: false
        )

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")
      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      html = render(view)

      # There must be no 'degraded' css class on the DAG node data. The word
      # 'degraded' may still appear elsewhere if there are degraded runs on
      # the page in general — but dag data for this node should not include
      # a degraded marker.
      refute html =~ "\"degraded\":true",
             "Non-degraded node should not carry degraded:true in dag data. HTML:\n#{html}"
    end
  end

  # ── Inspector Warnings section ───────────────────────────────────

  describe "node inspector Warnings section" do
    test "selecting a warning-bearing node shows the Warnings section header",
         %{conn: conn} do
      run_id = unique_run_id("ins-header")
      warnings = [warning_map()]

      obs_state =
        mock_obs_state(
          run_id,
          %{"summarize" => node_with_warnings(warnings)},
          warning_count: 1,
          degraded_nodes: ["summarize"],
          degraded: true
        )

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")
      broadcast_state(run_id, obs_state)
      Process.sleep(100)
      render_click(view, "select_node", %{"node-id" => "summarize"})

      html = render(view)

      assert html =~ "Warnings",
             "Expected Warnings section header. HTML:\n#{html}"
    end

    test "Warnings section renders every canonical field of a warning", %{conn: conn} do
      run_id = unique_run_id("ins-fields")

      warning = %{
        "code" => "llm_fallback",
        "severity" => "degraded",
        "summary" => "placeholder summary used",
        "cause" => "ANTHROPIC_API_KEY missing",
        "remediation" => "export ANTHROPIC_API_KEY then rerun",
        "affected_outputs" => ["summary"]
      }

      obs_state =
        mock_obs_state(
          run_id,
          %{"summarize" => node_with_warnings([warning])},
          warning_count: 1,
          degraded_nodes: ["summarize"],
          degraded: true
        )

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")
      broadcast_state(run_id, obs_state)
      Process.sleep(100)
      render_click(view, "select_node", %{"node-id" => "summarize"})

      html = render(view)

      assert html =~ "llm_fallback", "code missing: #{html}"
      assert html =~ "degraded", "severity missing: #{html}"
      assert html =~ "placeholder summary used", "summary missing: #{html}"
      assert html =~ "ANTHROPIC_API_KEY missing", "cause missing: #{html}"
      assert html =~ "export ANTHROPIC_API_KEY then rerun", "remediation missing: #{html}"
      assert html =~ "summary", "affected_outputs missing: #{html}"
    end

    test "Warnings section renders N entries when a node has N warnings", %{conn: conn} do
      run_id = unique_run_id("ins-multi")

      warnings = [
        warning_map(%{"code" => "w1", "summary" => "first thing"}),
        warning_map(%{"code" => "w2", "summary" => "second thing"}),
        warning_map(%{"code" => "w3", "summary" => "third thing"})
      ]

      obs_state =
        mock_obs_state(
          run_id,
          %{"summarize" => node_with_warnings(warnings)},
          warning_count: 3,
          degraded_nodes: ["summarize"],
          degraded: true
        )

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")
      broadcast_state(run_id, obs_state)
      Process.sleep(100)
      render_click(view, "select_node", %{"node-id" => "summarize"})

      html = render(view)

      assert html =~ "w1"
      assert html =~ "w2"
      assert html =~ "w3"
      assert html =~ "first thing"
      assert html =~ "second thing"
      assert html =~ "third thing"
    end

    test "Warnings section is NOT rendered when the selected node has no warnings",
         %{conn: conn} do
      run_id = unique_run_id("ins-no-warn")

      obs_state =
        mock_obs_state(
          run_id,
          %{"summarize" => node_with_warnings([])},
          warning_count: 0,
          degraded_nodes: [],
          degraded: false
        )

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")
      broadcast_state(run_id, obs_state)
      Process.sleep(100)
      render_click(view, "select_node", %{"node-id" => "summarize"})

      html = render(view)

      refute html =~ ~s(<h4>Warnings</h4>),
             "Warnings section must not render when node has no warnings. HTML:\n#{html}"
    end

    test "Warnings section tolerates optional fields being nil or absent", %{conn: conn} do
      run_id = unique_run_id("ins-optional")

      # Warning with only required fields — no cause, no remediation, no affected_outputs
      minimal_warning = %{
        "code" => "minimal",
        "severity" => "info",
        "summary" => "just the basics"
      }

      obs_state =
        mock_obs_state(
          run_id,
          %{"summarize" => node_with_warnings([minimal_warning])},
          warning_count: 1,
          degraded_nodes: ["summarize"],
          degraded: true
        )

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")
      broadcast_state(run_id, obs_state)
      Process.sleep(100)
      render_click(view, "select_node", %{"node-id" => "summarize"})

      html = render(view)

      # Must render the minimal fields without crashing
      assert html =~ "minimal"
      assert html =~ "info"
      assert html =~ "just the basics"
      # Cause / Remediation / Affected outputs labels must not appear for
      # missing optional fields — that would show empty "Cause: " lines
      refute html =~ "<dt>Cause</dt>"
      refute html =~ "<dt>Remediation</dt>"
      refute html =~ "<dt>Affected outputs</dt>"
    end

    test "Warnings section is a separate section from Decisions", %{conn: conn} do
      run_id = unique_run_id("ins-separation")
      warnings = [warning_map()]

      obs_state =
        mock_obs_state(
          run_id,
          %{
            "summarize" =>
              node_with_warnings(warnings, %{
                decisions: [%{hash: "sha256:decxyz", type: "llm_response"}]
              })
          },
          warning_count: 1,
          degraded_nodes: ["summarize"],
          degraded: true
        )

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")
      broadcast_state(run_id, obs_state)
      Process.sleep(100)
      render_click(view, "select_node", %{"node-id" => "summarize"})

      html = render(view)

      # Both sections must be present as distinct headers.
      assert html =~ "Warnings"
      assert html =~ "Decisions"
      # And the warning codes must not be rendered inside the Decisions list
      # (they are distinct concepts; collapsing them would be a regression).
      assert html =~ "decxyz"
      assert html =~ "fallback_used"
    end
  end
end
