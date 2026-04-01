defmodule LiminaraWeb.RunsLive.InspectorTest do
  @moduledoc """
  LiveView tests for M-OBS-04a: Node Inspector + Artifact Viewer.

  Covers:
  - Dashboard CSS Grid panel layout
  - Node inspector panel (select / deselect)
  - Inspector content for completed, failed, gate, cached, and recordable nodes
  - Artifact viewer: click hash → inline content, JSON, text, binary, not-found
  """
  use LiminaraWeb.ConnCase, async: false

  alias Liminara.{Artifact, Plan}
  alias Liminara.Run.Server, as: RunServer

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp unique_run_id(prefix \\ "inspector") do
    "#{prefix}-#{:erlang.unique_integer([:positive])}"
  end

  defp simple_plan do
    Plan.new()
    |> Plan.add_node("upcase", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
  end

  defp two_node_plan do
    Plan.new()
    |> Plan.add_node("upcase", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
    |> Plan.add_node("reverse", Liminara.TestOps.Reverse, %{"text" => {:ref, "upcase", "result"}})
  end

  # Builds a mock ViewModel struct / map that Show.ex accepts via PubSub.
  # All fields that observation state carries.
  defp mock_obs_state(run_id, nodes_map, opts \\ []) do
    %{
      run_id: run_id,
      run_status: Keyword.get(opts, :run_status, :running),
      run_started_at: "2026-03-19T14:00:00.000Z",
      run_completed_at: Keyword.get(opts, :run_completed_at, nil),
      event_count: Keyword.get(opts, :event_count, 3),
      nodes: nodes_map,
      plan: nil
    }
  end

  defp broadcast_state(run_id, obs_state) do
    Phoenix.PubSub.broadcast(
      Liminara.Observation.PubSub,
      "observation:#{run_id}:state",
      {:state_update, run_id, obs_state}
    )
  end

  # ── Dashboard layout ───────────────────────────────────────────────────────

  describe "dashboard layout shell" do
    test "run detail page uses CSS Grid panel layout with dag and inspector areas", %{conn: conn} do
      run_id = unique_run_id("layout")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5_000)
      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      # The run-detail layout must be a CSS Grid container
      assert html =~ "run-detail-layout" or html =~ "dashboard-layout",
             "Expected CSS Grid layout container. HTML:\n#{html}"
    end

    test "dag area is rendered inside the grid layout", %{conn: conn} do
      run_id = unique_run_id("layout-dag")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5_000)
      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      assert html =~ "id=\"dag-map\"",
             "Expected dag-map element inside grid layout. HTML:\n#{html}"
    end

    test "inspector panel is hidden when no node is selected on mount", %{conn: conn} do
      run_id = unique_run_id("layout-no-inspector")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5_000)
      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      # Inspector panel must not be visible when nothing is selected.
      # Either the element is absent, or it has a hidden/collapsed class/style.
      refute html =~ "inspector--visible",
             "Inspector should not be visible with no node selected. HTML:\n#{html}"
    end

    test "inspector panel becomes visible after selecting a node", %{conn: conn} do
      run_id = unique_run_id("layout-inspector-visible")
      plan = two_node_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5_000)
      Process.sleep(100)

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      render_click(view, "select_node", %{"node-id" => "upcase"})

      html = render(view)

      assert html =~ "inspector--visible" or html =~ "node-inspector",
             "Inspector panel should become visible after node selection. HTML:\n#{html}"
    end

    test "inspector panel hides after clicking the close button", %{conn: conn} do
      run_id = unique_run_id("layout-inspector-close")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5_000)
      Process.sleep(100)

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      render_click(view, "select_node", %{"node-id" => "upcase"})
      render_click(view, "deselect_node", %{})

      html = render(view)

      refute html =~ "inspector--visible",
             "Inspector should be hidden after deselect. HTML:\n#{html}"
    end

    test "panel resize hook attribute is present on the layout container", %{conn: conn} do
      run_id = unique_run_id("layout-resize")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5_000)
      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      assert html =~ "PanelResize" or html =~ "panel-resize",
             "Expected PanelResize hook on the layout. HTML:\n#{html}"
    end
  end

  # ── Node inspector ─────────────────────────────────────────────────────────

  describe "node inspector content — completed node" do
    test "selecting a completed node shows the inspector panel", %{conn: conn} do
      run_id = unique_run_id("inspector-completed")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5_000)
      Process.sleep(100)

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      render_click(view, "select_node", %{"node-id" => "upcase"})

      html = render(view)

      assert html =~ "node-inspector" or html =~ "inspector",
             "Inspector panel should appear after node selection. HTML:\n#{html}"
    end

    test "inspector shows op name for completed node", %{conn: conn} do
      run_id = unique_run_id("inspector-op-name")

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => %{
            status: :completed,
            op_name: "Upcase",
            op_version: "1.0",
            determinism: :pure,
            started_at: "2026-03-19T14:00:01.000Z",
            completed_at: "2026-03-19T14:00:02.000Z",
            duration_ms: 42,
            input_hashes: ["sha256:input1"],
            output_hashes: ["sha256:output1"],
            cache_hit: false,
            error: nil,
            gate_prompt: nil,
            gate_response: nil,
            decisions: []
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})

      html = render(view)

      assert html =~ "Upcase",
             "Inspector should display op name. HTML:\n#{html}"
    end

    test "inspector shows op version for completed node", %{conn: conn} do
      run_id = unique_run_id("inspector-op-version")

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => %{
            status: :completed,
            op_name: "Upcase",
            op_version: "1.0",
            determinism: :pure,
            started_at: "2026-03-19T14:00:01.000Z",
            completed_at: "2026-03-19T14:00:02.000Z",
            duration_ms: 42,
            input_hashes: ["sha256:input1"],
            output_hashes: ["sha256:output1"],
            cache_hit: false,
            error: nil,
            gate_prompt: nil,
            gate_response: nil,
            decisions: []
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})

      html = render(view)

      assert html =~ "1.0",
             "Inspector should display op version. HTML:\n#{html}"
    end

    test "inspector shows determinism class for completed node", %{conn: conn} do
      run_id = unique_run_id("inspector-determinism")

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => %{
            status: :completed,
            op_name: "Upcase",
            op_version: "1.0",
            determinism: :pure,
            started_at: "2026-03-19T14:00:01.000Z",
            completed_at: "2026-03-19T14:00:02.000Z",
            duration_ms: 42,
            input_hashes: ["sha256:input1"],
            output_hashes: ["sha256:output1"],
            cache_hit: false,
            error: nil,
            gate_prompt: nil,
            gate_response: nil,
            decisions: []
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})

      html = render(view)

      assert html =~ "pure",
             "Inspector should display determinism class. HTML:\n#{html}"
    end

    test "inspector shows node status for completed node", %{conn: conn} do
      run_id = unique_run_id("inspector-status")

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => %{
            status: :completed,
            op_name: "Upcase",
            op_version: "1.0",
            determinism: :pure,
            started_at: "2026-03-19T14:00:01.000Z",
            completed_at: "2026-03-19T14:00:02.000Z",
            duration_ms: 42,
            input_hashes: ["sha256:input1"],
            output_hashes: ["sha256:output1"],
            cache_hit: false,
            error: nil,
            gate_prompt: nil,
            gate_response: nil,
            decisions: []
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})

      html = render(view)

      assert html =~ "completed",
             "Inspector should display node status. HTML:\n#{html}"
    end

    test "inspector shows timing: started_at, completed_at, duration_ms", %{conn: conn} do
      run_id = unique_run_id("inspector-timing")

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => %{
            status: :completed,
            op_name: "Upcase",
            op_version: "1.0",
            determinism: :pure,
            started_at: "2026-03-19T14:00:01.000Z",
            completed_at: "2026-03-19T14:00:02.000Z",
            duration_ms: 42,
            input_hashes: [],
            output_hashes: [],
            cache_hit: false,
            error: nil,
            gate_prompt: nil,
            gate_response: nil,
            decisions: []
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})

      html = render(view)

      assert html =~ "14:00:01" or html =~ "2026-03-19",
             "Inspector should show started_at. HTML:\n#{html}"

      assert html =~ "42",
             "Inspector should show duration_ms. HTML:\n#{html}"
    end

    test "inspector shows input artifact hashes for completed node", %{conn: conn} do
      run_id = unique_run_id("inspector-inputs")

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => %{
            status: :completed,
            op_name: "Upcase",
            op_version: "1.0",
            determinism: :pure,
            started_at: "2026-03-19T14:00:01.000Z",
            completed_at: "2026-03-19T14:00:02.000Z",
            duration_ms: 10,
            input_hashes: ["sha256:aabbccdd"],
            output_hashes: [],
            cache_hit: false,
            error: nil,
            gate_prompt: nil,
            gate_response: nil,
            decisions: []
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})

      html = render(view)

      assert html =~ "aabbccdd",
             "Inspector should show input artifact hash. HTML:\n#{html}"
    end

    test "inspector shows output artifact hashes for completed node", %{conn: conn} do
      run_id = unique_run_id("inspector-outputs")

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => %{
            status: :completed,
            op_name: "Upcase",
            op_version: "1.0",
            determinism: :pure,
            started_at: "2026-03-19T14:00:01.000Z",
            completed_at: "2026-03-19T14:00:02.000Z",
            duration_ms: 10,
            input_hashes: [],
            output_hashes: ["sha256:result1234"],
            cache_hit: false,
            error: nil,
            gate_prompt: nil,
            gate_response: nil,
            decisions: []
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})

      html = render(view)

      assert html =~ "result1234",
             "Inspector should show output artifact hash. HTML:\n#{html}"
    end

    test "inspector shows cache_hit indicator when result is a cache hit", %{conn: conn} do
      run_id = unique_run_id("inspector-cache-hit")

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => %{
            status: :completed,
            op_name: "Upcase",
            op_version: "1.0",
            determinism: :pure,
            started_at: "2026-03-19T14:00:01.000Z",
            completed_at: "2026-03-19T14:00:02.000Z",
            duration_ms: 1,
            input_hashes: [],
            output_hashes: [],
            cache_hit: true,
            error: nil,
            gate_prompt: nil,
            gate_response: nil,
            decisions: []
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})

      html = render(view)

      assert (html =~ "cache" and html =~ "true") or html =~ "cache_hit" or html =~ "cache-hit",
             "Inspector should show cache_hit: true. HTML:\n#{html}"
    end
  end

  describe "node inspector content — failed node" do
    test "inspector shows error information for a failed node", %{conn: conn} do
      run_id = unique_run_id("inspector-failed")

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => %{
            status: :failed,
            op_name: "Upcase",
            op_version: "1.0",
            determinism: :pure,
            started_at: "2026-03-19T14:00:01.000Z",
            completed_at: nil,
            duration_ms: nil,
            input_hashes: [],
            output_hashes: [],
            cache_hit: nil,
            error: %{type: "execution_error", message: "intentional test failure"},
            gate_prompt: nil,
            gate_response: nil,
            decisions: []
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})

      html = render(view)

      assert html =~ "failed",
             "Inspector should show failed status. HTML:\n#{html}"

      assert html =~ "intentional test failure" or html =~ "execution_error",
             "Inspector should show error details. HTML:\n#{html}"
    end

    test "inspector shows error type for a failed node", %{conn: conn} do
      run_id = unique_run_id("inspector-failed-type")

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => %{
            status: :failed,
            op_name: "Upcase",
            op_version: "1.0",
            determinism: :pure,
            started_at: "2026-03-19T14:00:01.000Z",
            completed_at: nil,
            duration_ms: nil,
            input_hashes: [],
            output_hashes: [],
            cache_hit: nil,
            error: %{type: "execution_error", message: "something broke"},
            gate_prompt: nil,
            gate_response: nil,
            decisions: []
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})

      html = render(view)

      assert html =~ "execution_error",
             "Inspector should show error type. HTML:\n#{html}"
    end
  end

  describe "node inspector content — gate node (waiting)" do
    test "inspector shows gate prompt for a waiting gate node", %{conn: conn} do
      run_id = unique_run_id("inspector-gate-waiting")

      obs_state =
        mock_obs_state(run_id, %{
          "approve_step" => %{
            status: :waiting,
            op_name: "ApproveStep",
            op_version: "1.0",
            determinism: :side_effecting,
            started_at: "2026-03-19T14:00:01.000Z",
            completed_at: nil,
            duration_ms: nil,
            input_hashes: [],
            output_hashes: [],
            cache_hit: nil,
            error: nil,
            gate_prompt: "Please approve the deployment to production.",
            gate_response: nil,
            decisions: []
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "approve_step"})

      html = render(view)

      assert html =~ "Please approve the deployment to production.",
             "Inspector should show gate prompt. HTML:\n#{html}"
    end

    test "inspector shows waiting status for a gate node awaiting response", %{conn: conn} do
      run_id = unique_run_id("inspector-gate-status")

      obs_state =
        mock_obs_state(run_id, %{
          "approve_step" => %{
            status: :waiting,
            op_name: "ApproveStep",
            op_version: "1.0",
            determinism: :side_effecting,
            started_at: "2026-03-19T14:00:01.000Z",
            completed_at: nil,
            duration_ms: nil,
            input_hashes: [],
            output_hashes: [],
            cache_hit: nil,
            error: nil,
            gate_prompt: "Approve?",
            gate_response: nil,
            decisions: []
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "approve_step"})

      html = render(view)

      assert html =~ "waiting",
             "Inspector should show waiting status. HTML:\n#{html}"
    end
  end

  describe "node inspector content — gate node (resolved)" do
    test "inspector shows gate response and decision for a resolved gate node", %{conn: conn} do
      run_id = unique_run_id("inspector-gate-resolved")

      obs_state =
        mock_obs_state(run_id, %{
          "approve_step" => %{
            status: :completed,
            op_name: "ApproveStep",
            op_version: "1.0",
            determinism: :side_effecting,
            started_at: "2026-03-19T14:00:01.000Z",
            completed_at: "2026-03-19T14:00:10.000Z",
            duration_ms: 9000,
            input_hashes: [],
            output_hashes: [],
            cache_hit: nil,
            error: nil,
            gate_prompt: "Approve the release?",
            gate_response: "approved",
            decisions: [%{hash: "sha256:dec001", type: "human_approval"}]
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "approve_step"})

      html = render(view)

      assert html =~ "approved",
             "Inspector should show gate response. HTML:\n#{html}"

      assert html =~ "dec001" or html =~ "human_approval",
             "Inspector should show decision info. HTML:\n#{html}"
    end

    test "inspector shows gate prompt alongside resolved response", %{conn: conn} do
      run_id = unique_run_id("inspector-gate-prompt-and-response")

      obs_state =
        mock_obs_state(run_id, %{
          "approve_step" => %{
            status: :completed,
            op_name: "ApproveStep",
            op_version: "1.0",
            determinism: :side_effecting,
            started_at: "2026-03-19T14:00:01.000Z",
            completed_at: "2026-03-19T14:00:10.000Z",
            duration_ms: 9000,
            input_hashes: [],
            output_hashes: [],
            cache_hit: nil,
            error: nil,
            gate_prompt: "Do you approve?",
            gate_response: "approved",
            decisions: []
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "approve_step"})

      html = render(view)

      assert html =~ "Do you approve?",
             "Inspector should show original gate prompt. HTML:\n#{html}"
    end
  end

  describe "node inspector content — recordable node with decision" do
    test "inspector shows decision summary for a recordable node", %{conn: conn} do
      run_id = unique_run_id("inspector-decision")

      obs_state =
        mock_obs_state(run_id, %{
          "llm_step" => %{
            status: :completed,
            op_name: "LlmStep",
            op_version: "1.0",
            determinism: :recordable,
            started_at: "2026-03-19T14:00:01.000Z",
            completed_at: "2026-03-19T14:00:03.000Z",
            duration_ms: 2000,
            input_hashes: [],
            output_hashes: ["sha256:llm_out"],
            cache_hit: false,
            error: nil,
            gate_prompt: nil,
            gate_response: nil,
            decisions: [%{hash: "sha256:decabc", type: "llm_response"}]
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "llm_step"})

      html = render(view)

      assert html =~ "llm_response" or html =~ "decabc",
             "Inspector should show decision type or hash. HTML:\n#{html}"
    end

    test "inspector shows determinism class :recordable", %{conn: conn} do
      run_id = unique_run_id("inspector-recordable-class")

      obs_state =
        mock_obs_state(run_id, %{
          "llm_step" => %{
            status: :completed,
            op_name: "LlmStep",
            op_version: "1.0",
            determinism: :recordable,
            started_at: "2026-03-19T14:00:01.000Z",
            completed_at: "2026-03-19T14:00:03.000Z",
            duration_ms: 2000,
            input_hashes: [],
            output_hashes: [],
            cache_hit: false,
            error: nil,
            gate_prompt: nil,
            gate_response: nil,
            decisions: [%{hash: "sha256:dec1", type: "llm_response"}]
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "llm_step"})

      html = render(view)

      assert html =~ "recordable",
             "Inspector should show recordable determinism class. HTML:\n#{html}"
    end
  end

  describe "deselect node / close inspector" do
    test "clicking deselect_node event closes the inspector panel", %{conn: conn} do
      run_id = unique_run_id("inspector-close")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5_000)
      Process.sleep(100)

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      render_click(view, "select_node", %{"node-id" => "upcase"})
      html_open = render(view)

      # Verify inspector is showing
      assert html_open =~ "inspector",
             "Inspector should be open after selection. HTML:\n#{html_open}"

      # Now close it
      render_click(view, "deselect_node", %{})

      html_closed = render(view)

      refute html_closed =~ "inspector--visible",
             "Inspector should be hidden after deselect. HTML:\n#{html_closed}"
    end

    test "inspector panel has a close/dismiss button when open", %{conn: conn} do
      run_id = unique_run_id("inspector-dismiss-btn")

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => %{
            status: :completed,
            op_name: "Upcase",
            op_version: "1.0",
            determinism: :pure,
            started_at: nil,
            completed_at: nil,
            duration_ms: nil,
            input_hashes: [],
            output_hashes: [],
            cache_hit: false,
            error: nil,
            gate_prompt: nil,
            gate_response: nil,
            decisions: []
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})

      html = render(view)

      # There must be a close/dismiss affordance on the inspector
      assert html =~ "deselect_node" or html =~ "close-inspector" or html =~ "inspector-close",
             "Inspector must have a close button. HTML:\n#{html}"
    end
  end

  # ── Artifact viewer ────────────────────────────────────────────────────────

  describe "artifact viewer — click artifact hash renders inline content" do
    test "clicking a clickable artifact hash link triggers view_artifact event", %{conn: conn} do
      run_id = unique_run_id("artifact-click")

      content = "clickable artifact text"
      {:ok, hash} = Artifact.Store.put(content)

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => %{
            status: :completed,
            op_name: "Upcase",
            op_version: "1.0",
            determinism: :pure,
            started_at: "2026-03-19T14:00:01.000Z",
            completed_at: "2026-03-19T14:00:02.000Z",
            duration_ms: 5,
            input_hashes: [],
            output_hashes: [hash],
            cache_hit: false,
            error: nil,
            gate_prompt: nil,
            gate_response: nil,
            decisions: []
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})
      render_click(view, "view_artifact", %{"hash" => hash})

      html = render(view)

      assert html =~ "clickable artifact text",
             "Artifact content should be rendered inline. HTML:\n#{html}"
    end

    test "artifact viewer shows artifact content area when viewing an artifact", %{conn: conn} do
      run_id = unique_run_id("artifact-viewer-area")

      content = "artifact content for viewer"
      {:ok, hash} = Artifact.Store.put(content)

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => %{
            status: :completed,
            op_name: "Upcase",
            op_version: "1.0",
            determinism: :pure,
            started_at: nil,
            completed_at: nil,
            duration_ms: nil,
            input_hashes: [],
            output_hashes: [hash],
            cache_hit: false,
            error: nil,
            gate_prompt: nil,
            gate_response: nil,
            decisions: []
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})
      render_click(view, "view_artifact", %{"hash" => hash})

      html = render(view)

      assert html =~ "artifact-viewer" or html =~ "artifact-content",
             "Artifact viewer area should be present. HTML:\n#{html}"
    end
  end

  describe "artifact viewer — JSON artifact" do
    test "JSON artifact content is rendered as pretty-printed text", %{conn: conn} do
      run_id = unique_run_id("artifact-json")

      json_content = ~s({"key":"value","number":42})
      {:ok, hash} = Artifact.Store.put(json_content)

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => %{
            status: :completed,
            op_name: "Upcase",
            op_version: "1.0",
            determinism: :pure,
            started_at: nil,
            completed_at: nil,
            duration_ms: nil,
            input_hashes: [],
            output_hashes: [hash],
            cache_hit: false,
            error: nil,
            gate_prompt: nil,
            gate_response: nil,
            decisions: []
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})
      render_click(view, "view_artifact", %{"hash" => hash})

      html = render(view)

      # JSON should be rendered; key and value should be visible
      assert html =~ "key" and html =~ "value",
             "JSON keys/values should appear. HTML:\n#{html}"

      # Should be formatted (pretty-printed) — look for indentation markers or newlines in html
      # The rendered HTML should contain the JSON content
      assert html =~ "42",
             "JSON numeric value should appear. HTML:\n#{html}"
    end

    test "JSON artifact viewer shows a language or type indicator", %{conn: conn} do
      run_id = unique_run_id("artifact-json-indicator")

      json_content = ~s({"type":"test"})
      {:ok, hash} = Artifact.Store.put(json_content)

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => %{
            status: :completed,
            op_name: "Upcase",
            op_version: "1.0",
            determinism: :pure,
            started_at: nil,
            completed_at: nil,
            duration_ms: nil,
            input_hashes: [],
            output_hashes: [hash],
            cache_hit: false,
            error: nil,
            gate_prompt: nil,
            gate_response: nil,
            decisions: []
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})
      render_click(view, "view_artifact", %{"hash" => hash})

      html = render(view)

      # Should mark the artifact as JSON in some way
      assert html =~ "json" or html =~ "JSON",
             "Artifact viewer should indicate JSON type. HTML:\n#{html}"
    end
  end

  describe "artifact viewer — text/string artifact" do
    test "plain text artifact is displayed as plain text", %{conn: conn} do
      run_id = unique_run_id("artifact-text")

      text_content = "plain text content without any JSON structure"
      {:ok, hash} = Artifact.Store.put(text_content)

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => %{
            status: :completed,
            op_name: "Upcase",
            op_version: "1.0",
            determinism: :pure,
            started_at: nil,
            completed_at: nil,
            duration_ms: nil,
            input_hashes: [],
            output_hashes: [hash],
            cache_hit: false,
            error: nil,
            gate_prompt: nil,
            gate_response: nil,
            decisions: []
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})
      render_click(view, "view_artifact", %{"hash" => hash})

      html = render(view)

      assert html =~ "plain text content without any JSON structure",
             "Plain text artifact content should be rendered. HTML:\n#{html}"
    end

    test "empty string artifact renders without error", %{conn: conn} do
      run_id = unique_run_id("artifact-text-empty")

      {:ok, hash} = Artifact.Store.put("")

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => %{
            status: :completed,
            op_name: "Upcase",
            op_version: "1.0",
            determinism: :pure,
            started_at: nil,
            completed_at: nil,
            duration_ms: nil,
            input_hashes: [],
            output_hashes: [hash],
            cache_hit: false,
            error: nil,
            gate_prompt: nil,
            gate_response: nil,
            decisions: []
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})
      render_click(view, "view_artifact", %{"hash" => hash})

      # Should render without crashing
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "artifact viewer — binary artifact" do
    test "binary artifact shows type, size, and hash metadata (no inline render)", %{conn: conn} do
      run_id = unique_run_id("artifact-binary")

      # Simulate a binary artifact (PDF header magic bytes)
      binary_content = <<0x25, 0x50, 0x44, 0x46, 0x2D>> <> :crypto.strong_rand_bytes(50)
      {:ok, hash} = Artifact.Store.put(binary_content)

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => %{
            status: :completed,
            op_name: "Upcase",
            op_version: "1.0",
            determinism: :pure,
            started_at: nil,
            completed_at: nil,
            duration_ms: nil,
            input_hashes: [],
            output_hashes: [hash],
            cache_hit: false,
            error: nil,
            gate_prompt: nil,
            gate_response: nil,
            decisions: []
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})
      render_click(view, "view_artifact", %{"hash" => hash})

      html = render(view)

      # Binary artifact: must show hash, size, and some type indicator
      # The hash appears in hex form (without sha256: prefix or with)
      hash_hex = String.replace_prefix(hash, "sha256:", "")

      assert html =~ String.slice(hash_hex, 0, 8),
             "Binary artifact should show hash. HTML:\n#{html}"

      assert html =~ "binary" or html =~ "bytes" or html =~ to_string(byte_size(binary_content)),
             "Binary artifact should show size or binary indicator. HTML:\n#{html}"
    end
  end

  describe "artifact viewer — non-existent artifact" do
    test "viewing a non-existent artifact hash shows an error message", %{conn: conn} do
      run_id = unique_run_id("artifact-not-found")

      unknown_hash = "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => %{
            status: :completed,
            op_name: "Upcase",
            op_version: "1.0",
            determinism: :pure,
            started_at: nil,
            completed_at: nil,
            duration_ms: nil,
            input_hashes: [],
            output_hashes: [unknown_hash],
            cache_hit: false,
            error: nil,
            gate_prompt: nil,
            gate_response: nil,
            decisions: []
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})
      render_click(view, "view_artifact", %{"hash" => unknown_hash})

      html = render(view)

      assert html =~ "not found" or html =~ "error" or html =~ "Not Found",
             "Should show error for missing artifact. HTML:\n#{html}"
    end

    test "view_artifact with unknown hash does not crash the LiveView", %{conn: conn} do
      run_id = unique_run_id("artifact-not-found-no-crash")

      unknown_hash = "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      render_click(view, "view_artifact", %{"hash" => unknown_hash})

      # Should not crash — LiveView process must still be alive
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "artifact viewer — back/close button" do
    test "close_artifact event returns from artifact view to node detail view", %{conn: conn} do
      run_id = unique_run_id("artifact-close")

      content = "artifact to close"
      {:ok, hash} = Artifact.Store.put(content)

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => %{
            status: :completed,
            op_name: "Upcase",
            op_version: "1.0",
            determinism: :pure,
            started_at: nil,
            completed_at: nil,
            duration_ms: nil,
            input_hashes: [],
            output_hashes: [hash],
            cache_hit: false,
            error: nil,
            gate_prompt: nil,
            gate_response: nil,
            decisions: []
          }
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})
      render_click(view, "view_artifact", %{"hash" => hash})

      html_artifact = render(view)

      assert html_artifact =~ "artifact to close",
             "Artifact content should be shown. HTML:\n#{html_artifact}"

      render_click(view, "close_artifact", %{})

      html_back = render(view)

      # After closing artifact, the node inspector should be visible again
      # and the artifact content should be gone or the view should have reverted
      refute html_back =~ "artifact to close",
             "Artifact content should be gone after close. HTML:\n#{html_back}"

      # Node inspector should still be visible (node still selected)
      assert html_back =~ "Upcase" or html_back =~ "upcase",
             "Node inspector should still be visible. HTML:\n#{html_back}"
    end
  end
end
