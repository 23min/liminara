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

  defp extract_dag_json!(html) do
    [_, raw] = Regex.run(~r/data-dag="([^"]*)"/, html)

    raw
    |> String.replace("&quot;", "\"")
    |> String.replace("&amp;", "&")
    |> Jason.decode!()
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

  # ── M-WARN-04 merged_bug_001: :partial run projection ────────────

  describe "partial run detail (state_update path)" do
    test "partial-with-warnings state projects as degraded and shows partial status",
         %{conn: conn} do
      run_id = unique_run_id("showpd")
      warnings = [warning_map()]

      obs_state =
        mock_obs_state(
          run_id,
          %{"warn" => node_with_warnings(warnings)},
          run_status: :partial,
          warning_count: 1,
          degraded_nodes: ["warn"],
          degraded: true
        )

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")
      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      html = render(view)

      assert html =~ "status--partial",
             "Partial run must render the 'status--partial' class. HTML:\n#{html}"

      assert html =~ "status--degraded",
             "Partial run with warnings must render the degraded badge. HTML:\n#{html}"
    end

    test "partial-with-zero-warnings state projects as partial but not degraded",
         %{conn: conn} do
      run_id = unique_run_id("showpp")

      obs_state =
        mock_obs_state(
          run_id,
          %{"ok" => node_with_warnings([])},
          run_status: :partial,
          warning_count: 0,
          degraded_nodes: [],
          degraded: false
        )

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")
      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      html = render(view)

      assert html =~ "status--partial",
             "Partial run must render the 'status--partial' class. HTML:\n#{html}"

      refute html =~ "status--degraded",
             "Partial run with zero warnings must not render degraded badge. HTML:\n#{html}"
    end
  end

  describe "partial run detail (run_event path: apply_event_type)" do
    # Exercises `RunsLive.Show.apply_event_type(_, "run_partial", _, _)`
    # via the `:run_event` :pg broadcast that Run.Server emits.
    test "run_partial event with warnings applies degraded: true to the live view model",
         %{conn: conn} do
      run_id = unique_run_id("show-partial-rp")

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      # Send events directly to the LiveView's :pg group.
      pids = :pg.get_members(:liminara, {:run, run_id})
      assert pids != [], "LiveView did not join {:run, run_id} :pg group"

      Enum.each(pids, fn pid ->
        send(
          pid,
          {:run_event, run_id,
           %{
             "event_type" => "run_started",
             "timestamp" => "2026-04-20T14:00:00.000Z",
             "payload" => %{
               "run_id" => run_id,
               "pack_id" => "test_pack",
               "pack_version" => "0.1.0",
               "plan_hash" => "sha256:abc"
             }
           }}
        )

        send(
          pid,
          {:run_event, run_id,
           %{
             "event_type" => "op_started",
             "timestamp" => "2026-04-20T14:00:01.000Z",
             "payload" => %{
               "node_id" => "warn",
               "op_id" => "warn_op",
               "op_version" => "1.0",
               "determinism" => "pure",
               "input_hashes" => []
             }
           }}
        )

        send(
          pid,
          {:run_event, run_id,
           %{
             "event_type" => "op_completed",
             "timestamp" => "2026-04-20T14:00:02.000Z",
             "payload" => %{
               "node_id" => "warn",
               "output_hashes" => [],
               "cache_hit" => false,
               "duration_ms" => 10,
               "warnings" => [warning_map()]
             }
           }}
        )

        send(
          pid,
          {:run_event, run_id,
           %{
             "event_type" => "run_partial",
             "timestamp" => "2026-04-20T14:00:05.000Z",
             "payload" => %{
               "run_id" => run_id,
               "error_type" => "run_failure",
               "error_message" => "one or more nodes failed",
               "failed_nodes" => ["fail"],
               "warning_summary" => %{
                 "warning_count" => 1,
                 "degraded_node_ids" => ["warn"]
               }
             }
           }}
        )
      end)

      Process.sleep(150)
      html = render(view)

      assert html =~ "status--partial",
             "Run-event apply_event_type must yield run_status 'partial'. HTML:\n#{html}"

      assert html =~ "status--degraded",
             "Run-event apply_event_type for run_partial must mark view_model degraded. HTML:\n#{html}"

      refute html =~ "status--failed",
             "Partial run must not degrade to status 'failed' on live event path. HTML:\n#{html}"
    end
  end

  describe "partial run detail (event-log fallback: build_from_events)" do
    # Exercises `derive_degraded_from_events/1`, `derive_status/1`,
    # `completed_at/1`, and `warning_summary_from_terminal_event/1` for
    # a run whose persisted event log ends with "run_partial" but has
    # no plan.json on disk (which is how this page degrades when the
    # Observation.Server can't start). We trigger the fallback by
    # appending events directly via Event.Store without writing a plan.
    #
    # These tests write into the supervised Event.Store's runs_root
    # (default `/tmp/liminara_runs/`). Without cleanup the persisted
    # fb-partial/fb-plain runs leak into any later test that mounts
    # `/runs` (e.g. RunsLive.IndexTest → load_runs_from_store), which
    # then observes a degraded/partial row from a sibling test and
    # fails its `refute html =~ "status--degraded"` assertion. We
    # cannot swap runs_root via `Application.put_env` because the
    # supervised store reads it once at startup; we clean the run
    # directory after each test instead.

    setup do
      runs_root =
        Application.get_env(:liminara_core, :runs_root) ||
          Path.join(System.tmp_dir!(), "liminara_runs")

      {:ok, supervised_runs_root: runs_root}
    end

    test "event log ending with run_partial projects degraded: true and status partial",
         %{conn: conn, supervised_runs_root: runs_root} do
      run_id = unique_run_id("fb-partial")
      on_exit(fn -> File.rm_rf!(Path.join(runs_root, run_id)) end)

      # Append events directly (no plan written) — guarantees
      # `try_start_obs_server` falls through to `build_view_model`.
      {:ok, _} =
        Liminara.Event.Store.append(
          run_id,
          "run_started",
          %{
            "run_id" => run_id,
            "pack_id" => "test_pack",
            "pack_version" => "0.1.0",
            "plan_hash" => "sha256:abc"
          },
          nil
        )

      {:ok, _} =
        Liminara.Event.Store.append(
          run_id,
          "op_started",
          %{
            "node_id" => "warn",
            "op_id" => "warn_op",
            "op_version" => "1.0",
            "determinism" => "pure",
            "input_hashes" => []
          },
          nil
        )

      {:ok, _} =
        Liminara.Event.Store.append(
          run_id,
          "op_completed",
          %{
            "node_id" => "warn",
            "output_hashes" => [],
            "cache_hit" => false,
            "duration_ms" => 10,
            "warnings" => [warning_map()]
          },
          nil
        )

      {:ok, _} =
        Liminara.Event.Store.append(
          run_id,
          "op_started",
          %{
            "node_id" => "fail",
            "op_id" => "fail_op",
            "op_version" => "1.0",
            "determinism" => "pure",
            "input_hashes" => []
          },
          nil
        )

      {:ok, _} =
        Liminara.Event.Store.append(
          run_id,
          "op_failed",
          %{
            "node_id" => "fail",
            "error_type" => "execution_error",
            "error_message" => "boom",
            "duration_ms" => 5
          },
          nil
        )

      {:ok, _} =
        Liminara.Event.Store.append(
          run_id,
          "run_partial",
          %{
            "run_id" => run_id,
            "error_type" => "run_failure",
            "error_message" => "one or more nodes failed",
            "failed_nodes" => ["fail"],
            "warning_summary" => %{
              "warning_count" => 1,
              "degraded_node_ids" => ["warn"]
            }
          },
          nil
        )

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      # Partial status badge is rendered as `<span class="status status--partial">`.
      assert html =~ ~s(class="status status--partial"),
             "Fallback build_from_events must render the partial status badge. HTML:\n#{html}"

      # Degraded badge is rendered as `<span class="status status--degraded" title="...">`.
      # (Bare "status--degraded" is also present as a CSS rule in the
      # layout, so we match the element shape instead of the class name.)
      assert html =~ ~s(class="status status--degraded" title=),
             "Fallback build_from_events for partial-with-warnings must render the degraded badge span. HTML:\n#{html}"

      refute html =~ ~s(class="status status--failed"),
             "Fallback path must not degrade to 'failed' for a :partial run. HTML:\n#{html}"
    end

    test "event log ending with run_partial and zero warnings projects status partial without degraded badge",
         %{conn: conn, supervised_runs_root: runs_root} do
      run_id = unique_run_id("fb-plain")
      on_exit(fn -> File.rm_rf!(Path.join(runs_root, run_id)) end)

      {:ok, _} =
        Liminara.Event.Store.append(
          run_id,
          "run_started",
          %{
            "run_id" => run_id,
            "pack_id" => "test_pack",
            "pack_version" => "0.1.0",
            "plan_hash" => "sha256:abc"
          },
          nil
        )

      {:ok, _} =
        Liminara.Event.Store.append(
          run_id,
          "run_partial",
          %{
            "run_id" => run_id,
            "error_type" => "run_failure",
            "error_message" => "one or more nodes failed",
            "failed_nodes" => ["fail"],
            "warning_summary" => %{"warning_count" => 0, "degraded_node_ids" => []}
          },
          nil
        )

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      assert html =~ ~s(class="status status--partial")

      refute html =~ ~s(class="status status--degraded" title=),
             "Fallback path with zero warnings must not render the degraded badge span. HTML:\n#{html}"
    end

    # ── bug_009 / AC4: per-node degraded preserved on fallback path ──
    #
    # The event-log fallback path (no plan.json on disk) must surface
    # per-node warnings and degraded state, just like the primary
    # observation path does via `observation_state_to_view_model/1`.
    # build_nodes/1 reduces op_completed events; it must carry
    # payload["warnings"] onto the per-node map so that:
    #   - nodes_only_dag_json tags the warning-emitting node with
    #     degraded: true (DAG pill),
    #   - find_in_view_model -> inspector Warnings section renders
    #     the warning's canonical fields.

    test "event log op_completed with warnings marks per-node degraded in DAG data on fallback",
         %{conn: conn, supervised_runs_root: runs_root} do
      run_id = unique_run_id("fb-dag-deg")
      on_exit(fn -> File.rm_rf!(Path.join(runs_root, run_id)) end)

      {:ok, _} =
        Liminara.Event.Store.append(
          run_id,
          "run_started",
          %{
            "run_id" => run_id,
            "pack_id" => "test_pack",
            "pack_version" => "0.1.0",
            "plan_hash" => "sha256:abc"
          },
          nil
        )

      {:ok, _} =
        Liminara.Event.Store.append(
          run_id,
          "op_started",
          %{
            "node_id" => "warn",
            "op_id" => "warn_op",
            "op_version" => "1.0",
            "determinism" => "pure",
            "input_hashes" => []
          },
          nil
        )

      {:ok, _} =
        Liminara.Event.Store.append(
          run_id,
          "op_completed",
          %{
            "node_id" => "warn",
            "output_hashes" => [],
            "cache_hit" => false,
            "duration_ms" => 10,
            "warnings" => [warning_map()]
          },
          nil
        )

      {:ok, _} =
        Liminara.Event.Store.append(
          run_id,
          "op_started",
          %{
            "node_id" => "plain",
            "op_id" => "plain_op",
            "op_version" => "1.0",
            "determinism" => "pure",
            "input_hashes" => []
          },
          nil
        )

      {:ok, _} =
        Liminara.Event.Store.append(
          run_id,
          "op_completed",
          %{
            "node_id" => "plain",
            "output_hashes" => [],
            "cache_hit" => false,
            "duration_ms" => 5
          },
          nil
        )

      {:ok, _} =
        Liminara.Event.Store.append(
          run_id,
          "run_completed",
          %{
            "run_id" => run_id,
            "warning_summary" => %{
              "warning_count" => 1,
              "degraded_node_ids" => ["warn"]
            }
          },
          nil
        )

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      # data-dag is interpolated as an HTML attribute; HEEx escapes double
      # quotes to &quot;. Extract the raw JSON, unescape, and decode so we
      # can assert per-node structure directly instead of fighting the
      # escape form with regex.
      dag = extract_dag_json!(html)

      warn_node = Enum.find(dag["nodes"], fn n -> n["id"] == "warn" end)
      plain_node = Enum.find(dag["nodes"], fn n -> n["id"] == "plain" end)

      assert warn_node, "Expected 'warn' node in fallback DAG. DAG:\n#{inspect(dag)}"
      assert plain_node, "Expected 'plain' node in fallback DAG. DAG:\n#{inspect(dag)}"

      assert warn_node["degraded"] == true,
             "'warn' node must carry degraded:true on fallback DAG. node:\n#{inspect(warn_node)}"

      refute plain_node["degraded"] == true,
             "'plain' node must not carry degraded:true on fallback DAG. node:\n#{inspect(plain_node)}"
    end

    test "event log op_completed warnings render in inspector Warnings section on fallback",
         %{conn: conn, supervised_runs_root: runs_root} do
      run_id = unique_run_id("fb-ins-warn")
      on_exit(fn -> File.rm_rf!(Path.join(runs_root, run_id)) end)

      warning = %{
        "code" => "llm_fallback",
        "severity" => "degraded",
        "summary" => "placeholder summary used",
        "cause" => "ANTHROPIC_API_KEY missing",
        "remediation" => "export ANTHROPIC_API_KEY then rerun",
        "affected_outputs" => ["summary"]
      }

      {:ok, _} =
        Liminara.Event.Store.append(
          run_id,
          "run_started",
          %{
            "run_id" => run_id,
            "pack_id" => "test_pack",
            "pack_version" => "0.1.0",
            "plan_hash" => "sha256:abc"
          },
          nil
        )

      {:ok, _} =
        Liminara.Event.Store.append(
          run_id,
          "op_started",
          %{
            "node_id" => "summarize",
            "op_id" => "summarize",
            "op_version" => "1.0",
            "determinism" => "recordable",
            "input_hashes" => []
          },
          nil
        )

      {:ok, _} =
        Liminara.Event.Store.append(
          run_id,
          "op_completed",
          %{
            "node_id" => "summarize",
            "output_hashes" => [],
            "cache_hit" => false,
            "duration_ms" => 10,
            "warnings" => [warning]
          },
          nil
        )

      {:ok, _} =
        Liminara.Event.Store.append(
          run_id,
          "run_completed",
          %{
            "run_id" => run_id,
            "warning_summary" => %{
              "warning_count" => 1,
              "degraded_node_ids" => ["summarize"]
            }
          },
          nil
        )

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")
      render_click(view, "select_node", %{"node-id" => "summarize"})
      html = render(view)

      assert html =~ "Warnings",
             "Expected inspector Warnings section header. HTML:\n#{html}"

      assert html =~ "llm_fallback", "code missing: #{html}"
      assert html =~ "placeholder summary used", "summary missing: #{html}"
      assert html =~ "ANTHROPIC_API_KEY missing", "cause missing: #{html}"
      assert html =~ "export ANTHROPIC_API_KEY then rerun", "remediation missing: #{html}"
    end
  end
end
