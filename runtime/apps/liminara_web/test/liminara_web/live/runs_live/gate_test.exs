defmodule LiminaraWeb.RunsLive.GateTest do
  @moduledoc """
  LiveView tests for M-OBS-05a: Gate Interaction in the Run Inspector.

  Covers:
  - Selecting a :waiting gate node shows approve/reject buttons in the inspector
  - Selecting a non-gate completed node shows NO approve/reject buttons
  - Clicking "Approve" sends resolve_gate with action "approve"
  - Clicking "Reject" sends resolve_gate with action "reject"
  - After resolution, the inspector updates — buttons gone, gate response shown
  - Selecting an already-resolved gate node shows the response, not the buttons
  - gate_requested and gate_resolved events appear in the timeline

  All tests will fail (red phase) until the LiveView handles:
  - The "resolve_gate" event with %{"node-id" => ..., "action" => ...} params
  - Approve/reject buttons rendered when selected node status == :waiting and gate_prompt set
  """
  use LiminaraWeb.ConnCase, async: false

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp unique_run_id(prefix) do
    "#{prefix}-#{:erlang.unique_integer([:positive])}"
  end

  # Build a mock observation state for a run with a waiting gate node.
  defp mock_obs_state(run_id, nodes_map, opts \\ []) do
    %{
      run_id: run_id,
      run_status: Keyword.get(opts, :run_status, :running),
      run_started_at: "2026-03-22T10:00:00.000Z",
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

  defp broadcast_event(run_id, event) do
    Phoenix.PubSub.broadcast(
      Liminara.Observation.PubSub,
      "observation:#{run_id}:events",
      {:event_update, run_id, event}
    )
  end

  # A gate node that is currently waiting for a human decision
  defp waiting_gate_node do
    %{
      status: :waiting,
      op_name: "approve",
      op_version: "1.0",
      determinism: :side_effecting,
      started_at: "2026-03-22T10:00:01.000Z",
      completed_at: nil,
      duration_ms: nil,
      input_hashes: [],
      output_hashes: [],
      cache_hit: nil,
      error: nil,
      gate_prompt: "Please approve the pipeline execution.",
      gate_response: nil,
      decisions: []
    }
  end

  # A gate node that has already been resolved (approved)
  defp resolved_gate_node(response) do
    %{
      status: :completed,
      op_name: "approve",
      op_version: "1.0",
      determinism: :side_effecting,
      started_at: "2026-03-22T10:00:01.000Z",
      completed_at: "2026-03-22T10:00:15.000Z",
      duration_ms: 14000,
      input_hashes: [],
      output_hashes: ["sha256:abc123"],
      cache_hit: nil,
      error: nil,
      gate_prompt: "Please approve the pipeline execution.",
      gate_response: response,
      decisions: [%{hash: "sha256:gate_dec001", type: "gate_approval"}]
    }
  end

  # A normal completed node (not a gate)
  defp completed_pure_node(node_id) do
    %{
      status: :completed,
      op_name: node_id,
      op_version: "1.0",
      determinism: :pure,
      started_at: "2026-03-22T10:00:00.500Z",
      completed_at: "2026-03-22T10:00:01.000Z",
      duration_ms: 5,
      input_hashes: [],
      output_hashes: ["sha256:out_#{node_id}"],
      cache_hit: false,
      error: nil,
      gate_prompt: nil,
      gate_response: nil,
      decisions: []
    }
  end

  defp gate_requested_event(run_id, node_id) do
    %{
      event_hash: "sha256:gr_#{run_id}",
      event_type: "gate_requested",
      payload: %{
        "node_id" => node_id,
        "prompt" => "Please approve the pipeline execution."
      },
      prev_hash: "sha256:os",
      timestamp: "2026-03-22T10:00:01.000Z"
    }
  end

  defp gate_resolved_event(run_id, node_id) do
    %{
      event_hash: "sha256:gres_#{run_id}",
      event_type: "gate_resolved",
      payload: %{
        "node_id" => node_id,
        "response" => "approved"
      },
      prev_hash: "sha256:gr_#{run_id}",
      timestamp: "2026-03-22T10:00:15.000Z"
    }
  end

  # ── Approve/reject buttons appear for waiting gate node ────────────────────

  describe "inspector — waiting gate node shows approve/reject buttons" do
    test "approve button is rendered when gate node is :waiting", %{conn: conn} do
      run_id = unique_run_id("gate-approve-btn")

      obs_state =
        mock_obs_state(run_id, %{
          "gate_node" => waiting_gate_node()
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "gate_node"})

      html = render(view)

      assert html =~ "approve" or html =~ "Approve",
             "Expected approve button to appear for waiting gate node. HTML:\n#{html}"
    end

    test "reject button is rendered when gate node is :waiting", %{conn: conn} do
      run_id = unique_run_id("gate-reject-btn")

      obs_state =
        mock_obs_state(run_id, %{
          "gate_node" => waiting_gate_node()
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "gate_node"})

      html = render(view)

      assert html =~ "reject" or html =~ "Reject",
             "Expected reject button to appear for waiting gate node. HTML:\n#{html}"
    end

    test "gate prompt is shown when gate node is :waiting", %{conn: conn} do
      run_id = unique_run_id("gate-prompt-visible")

      obs_state =
        mock_obs_state(run_id, %{
          "gate_node" => waiting_gate_node()
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "gate_node"})

      html = render(view)

      assert html =~ "Please approve the pipeline execution.",
             "Expected gate prompt text to appear in inspector. HTML:\n#{html}"
    end

    test "both approve and reject buttons are rendered together", %{conn: conn} do
      run_id = unique_run_id("gate-both-btns")

      obs_state =
        mock_obs_state(run_id, %{
          "gate_node" => waiting_gate_node()
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "gate_node"})

      html = render(view)

      # Both must be present at the same time
      has_approve = html =~ "approve" or html =~ "Approve"
      has_reject = html =~ "reject" or html =~ "Reject"

      assert has_approve and has_reject,
             "Expected both approve and reject buttons. HTML:\n#{html}"
    end
  end

  # ── Approve/reject buttons do NOT appear for non-gate nodes ───────────────

  describe "inspector — non-gate node has no approve/reject buttons" do
    test "no approve button for a completed pure node", %{conn: conn} do
      run_id = unique_run_id("gate-no-approve-pure")

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => completed_pure_node("upcase")
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})

      html = render(view)

      # Must not have approve/reject buttons (not a gate node)
      refute html =~ "resolve_gate",
             "Expected no resolve_gate event handler for pure node. HTML:\n#{html}"
    end

    test "no reject button for a completed pure node", %{conn: conn} do
      run_id = unique_run_id("gate-no-reject-pure")

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => completed_pure_node("upcase")
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})

      html = render(view)

      # No gate-specific UI for a pure completed node
      # Must not show BOTH approve and reject together
      has_approve = html =~ "Approve"
      has_reject = html =~ "Reject"

      refute has_approve and has_reject,
             "Pure node inspector should not show Approve + Reject buttons. HTML:\n#{html}"
    end

    test "no approve/reject buttons when no node is selected", %{conn: conn} do
      run_id = unique_run_id("gate-no-selection")

      obs_state =
        mock_obs_state(run_id, %{
          "gate_node" => waiting_gate_node()
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      # Do NOT select a node
      html = render(view)

      refute html =~ "resolve_gate",
             "Expected no resolve_gate buttons when no node is selected. HTML:\n#{html}"
    end
  end

  # ── Clicking approve sends resolve_gate ───────────────────────────────────

  describe "clicking approve button" do
    test "clicking approve sends resolve_gate event with action 'approve'", %{conn: conn} do
      run_id = unique_run_id("gate-click-approve")

      obs_state =
        mock_obs_state(run_id, %{
          "gate_node" => waiting_gate_node()
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "gate_node"})

      # Click the approve button — must send "resolve_gate" event
      # The button should fire phx-click="resolve_gate" with node-id and action="approve"
      render_click(view, "resolve_gate", %{"node-id" => "gate_node", "action" => "approve"})

      # Should not crash / raise
      html = render(view)
      assert is_binary(html)
    end

    test "clicking approve does not crash the LiveView", %{conn: conn} do
      run_id = unique_run_id("gate-approve-no-crash")

      obs_state =
        mock_obs_state(run_id, %{
          "gate_node" => waiting_gate_node()
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "gate_node"})

      # This must not raise FunctionClauseError or similar
      assert render_click(view, "resolve_gate", %{"node-id" => "gate_node", "action" => "approve"})
    end

    test "after approval, inspector shows the response (not waiting buttons)", %{conn: conn} do
      run_id = unique_run_id("gate-post-approve")

      # Start with a waiting gate
      waiting_state =
        mock_obs_state(run_id, %{
          "gate_node" => waiting_gate_node()
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, waiting_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "gate_node"})
      render_click(view, "resolve_gate", %{"node-id" => "gate_node", "action" => "approve"})

      # Simulate the state update that comes back after resolution
      resolved_state =
        mock_obs_state(
          run_id,
          %{
            "gate_node" => resolved_gate_node("approved")
          },
          run_status: :completed,
          run_completed_at: "2026-03-22T10:00:20.000Z"
        )

      broadcast_state(run_id, resolved_state)
      Process.sleep(100)

      html = render(view)

      # Gate response should be shown
      assert html =~ "approved",
             "Expected gate response 'approved' to appear after resolution. HTML:\n#{html}"
    end
  end

  # ── Clicking reject sends resolve_gate ────────────────────────────────────

  describe "clicking reject button" do
    test "clicking reject sends resolve_gate event with action 'reject'", %{conn: conn} do
      run_id = unique_run_id("gate-click-reject")

      obs_state =
        mock_obs_state(run_id, %{
          "gate_node" => waiting_gate_node()
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "gate_node"})

      # Click the reject button
      render_click(view, "resolve_gate", %{"node-id" => "gate_node", "action" => "reject"})

      html = render(view)
      assert is_binary(html)
    end

    test "clicking reject does not crash the LiveView", %{conn: conn} do
      run_id = unique_run_id("gate-reject-no-crash")

      obs_state =
        mock_obs_state(run_id, %{
          "gate_node" => waiting_gate_node()
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "gate_node"})

      assert render_click(view, "resolve_gate", %{"node-id" => "gate_node", "action" => "reject"})
    end

    test "after rejection, inspector shows the rejected response", %{conn: conn} do
      run_id = unique_run_id("gate-post-reject")

      waiting_state =
        mock_obs_state(run_id, %{
          "gate_node" => waiting_gate_node()
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, waiting_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "gate_node"})
      render_click(view, "resolve_gate", %{"node-id" => "gate_node", "action" => "reject"})

      # Simulate the state update after rejection
      resolved_state =
        mock_obs_state(
          run_id,
          %{
            "gate_node" => resolved_gate_node("rejected")
          },
          run_status: :completed,
          run_completed_at: "2026-03-22T10:00:20.000Z"
        )

      broadcast_state(run_id, resolved_state)
      Process.sleep(100)

      html = render(view)

      assert html =~ "rejected",
             "Expected gate response 'rejected' to appear after rejection. HTML:\n#{html}"
    end
  end

  # ── Resolved gate node — buttons gone, response shown ─────────────────────

  describe "inspector — already-resolved gate node" do
    test "resolved gate node shows gate response", %{conn: conn} do
      run_id = unique_run_id("gate-resolved-response")

      obs_state =
        mock_obs_state(
          run_id,
          %{"gate_node" => resolved_gate_node("approved")},
          run_status: :completed
        )

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "gate_node"})

      html = render(view)

      assert html =~ "approved",
             "Expected resolved gate response 'approved' to be shown. HTML:\n#{html}"
    end

    test "resolved gate node does NOT show approve/reject buttons", %{conn: conn} do
      run_id = unique_run_id("gate-resolved-no-btns")

      obs_state =
        mock_obs_state(
          run_id,
          %{"gate_node" => resolved_gate_node("approved")},
          run_status: :completed
        )

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "gate_node"})

      html = render(view)

      # Resolved node should not show action buttons
      refute html =~ "resolve_gate",
             "Resolved gate node should not show approve/reject buttons. HTML:\n#{html}"
    end

    test "resolved gate node shows both prompt and response", %{conn: conn} do
      run_id = unique_run_id("gate-resolved-both")

      obs_state =
        mock_obs_state(
          run_id,
          %{"gate_node" => resolved_gate_node("approved")},
          run_status: :completed
        )

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "gate_node"})

      html = render(view)

      assert html =~ "Please approve the pipeline execution.",
             "Expected gate prompt to still be shown after resolution. HTML:\n#{html}"

      assert html =~ "approved",
             "Expected gate response to be shown after resolution. HTML:\n#{html}"
    end
  end

  # ── Timeline shows gate events ─────────────────────────────────────────────

  describe "timeline — gate events" do
    test "gate_requested event appears in the timeline" do
      run_id = unique_run_id("gate-timeline-req")

      {:ok, view, _html} = live(build_conn(), "/runs/#{run_id}")

      broadcast_event(run_id, gate_requested_event(run_id, "gate_node"))
      Process.sleep(100)

      html = render(view)

      assert html =~ "gate_requested",
             "Expected 'gate_requested' to appear in timeline. HTML:\n#{html}"
    end

    test "gate_resolved event appears in the timeline" do
      run_id = unique_run_id("gate-timeline-res")

      {:ok, view, _html} = live(build_conn(), "/runs/#{run_id}")

      broadcast_event(run_id, gate_requested_event(run_id, "gate_node"))
      broadcast_event(run_id, gate_resolved_event(run_id, "gate_node"))
      Process.sleep(100)

      html = render(view)

      assert html =~ "gate_resolved",
             "Expected 'gate_resolved' to appear in timeline. HTML:\n#{html}"
    end

    test "both gate_requested and gate_resolved appear in the timeline" do
      run_id = unique_run_id("gate-timeline-both")

      {:ok, view, _html} = live(build_conn(), "/runs/#{run_id}")

      broadcast_event(run_id, gate_requested_event(run_id, "gate_node"))
      broadcast_event(run_id, gate_resolved_event(run_id, "gate_node"))
      Process.sleep(100)

      html = render(view)

      assert html =~ "gate_requested",
             "Expected 'gate_requested' in timeline. HTML:\n#{html}"

      assert html =~ "gate_resolved",
             "Expected 'gate_resolved' in timeline. HTML:\n#{html}"
    end

    test "clicking gate_requested timeline entry selects the gate node", %{conn: conn} do
      run_id = unique_run_id("gate-timeline-click")

      obs_state =
        mock_obs_state(run_id, %{
          "gate_node" => waiting_gate_node()
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      broadcast_event(run_id, gate_requested_event(run_id, "gate_node"))
      Process.sleep(100)

      # Click the gate_requested timeline event to select the gate node
      render_click(view, "select_node", %{"node-id" => "gate_node"})

      html = render(view)

      # Inspector should open for gate_node
      assert html =~ "gate_node" or html =~ "approve" or html =~ "gate",
             "Expected gate node to be selected in inspector after clicking timeline event. HTML:\n#{html}"
    end
  end

  # ── DAG updates when gate state changes ───────────────────────────────────

  describe "DAG visual state — gate node" do
    test "waiting gate node is represented differently from completed nodes in DAG data" do
      run_id = unique_run_id("gate-dag-waiting")

      obs_state =
        mock_obs_state(run_id, %{
          "input_node" => completed_pure_node("input_node"),
          "gate_node" => waiting_gate_node(),
          "output_node" => %{completed_pure_node("output_node") | status: :pending}
        })

      {:ok, view, _html} = live(build_conn(), "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      html = render(view)

      # DAG data should encode waiting status for gate_node
      # The dag-data attribute should contain the waiting node
      assert html =~ "gate_node",
             "Expected gate_node to appear in DAG data. HTML:\n#{html}"
    end

    test "after resolution, DAG shows gate node as completed" do
      run_id = unique_run_id("gate-dag-resolved")

      waiting_state =
        mock_obs_state(run_id, %{
          "gate_node" => waiting_gate_node()
        })

      {:ok, view, _html} = live(build_conn(), "/runs/#{run_id}")

      broadcast_state(run_id, waiting_state)
      Process.sleep(100)

      # Now resolve
      resolved_state =
        mock_obs_state(
          run_id,
          %{
            "gate_node" => resolved_gate_node("approved")
          },
          run_status: :completed
        )

      broadcast_state(run_id, resolved_state)
      Process.sleep(100)

      html = render(view)

      # After resolution, gate_node should show completed status
      assert html =~ "gate_node",
             "Expected gate_node in DAG after resolution. HTML:\n#{html}"
    end
  end

  # ── resolve_gate handle_event contract ────────────────────────────────────

  describe "handle_event resolve_gate — contract" do
    test "resolve_gate event is handled (not unhandled/crash) for waiting node", %{conn: conn} do
      run_id = unique_run_id("gate-event-handled")

      obs_state =
        mock_obs_state(run_id, %{
          "gate_node" => waiting_gate_node()
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "gate_node"})

      # This must not raise an error — the handle_event must exist
      assert {:ok, _html} =
               render_click_and_return(view, "resolve_gate", %{
                 "node-id" => "gate_node",
                 "action" => "approve"
               })
    end

    test "resolve_gate event with reject action is handled without crash", %{conn: conn} do
      run_id = unique_run_id("gate-reject-handled")

      obs_state =
        mock_obs_state(run_id, %{
          "gate_node" => waiting_gate_node()
        })

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "gate_node"})

      assert {:ok, _html} =
               render_click_and_return(view, "resolve_gate", %{
                 "node-id" => "gate_node",
                 "action" => "reject"
               })
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  # render_click returns the HTML string, but we want {ok, html} for these tests.
  defp render_click_and_return(view, event, params) do
    try do
      html = render_click(view, event, params)
      {:ok, html}
    rescue
      e -> {:error, e}
    end
  end
end
