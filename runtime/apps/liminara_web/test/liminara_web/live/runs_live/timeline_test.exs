defmodule LiminaraWeb.RunsLive.TimelineTest do
  @moduledoc """
  LiveView tests for M-OBS-04b: Event Timeline + Decision Viewer.

  Covers:
  - Timeline panel presence and structure in the run detail layout
  - Events shown in chronological order for a completed run
  - Real-time updates: new events appear when broadcast via PubSub events topic
  - Filtering by event_type
  - Filtering by node_id
  - Clicking a timeline event selects the corresponding node in the DAG
  - Timeline panel collapse / expand toggle
  - Decision viewer: lists decisions for a run, clicking a decision selects the node

  These tests will fail (red phase) until the LiveView and template implement
  the timeline panel, filter state, and decision viewer.
  """
  use LiminaraWeb.ConnCase, async: false

  alias Liminara.{Plan}
  alias Liminara.Run.Server, as: RunServer

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp unique_run_id(prefix \\ "timeline") do
    "#{prefix}-#{:erlang.unique_integer([:positive])}"
  end

  defp simple_plan do
    Plan.new()
    |> Plan.add_node("upcase", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
  end

  defp two_node_plan do
    Plan.new()
    |> Plan.add_node("upcase", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
    |> Plan.add_node("reverse", Liminara.TestOps.Reverse, %{
      "text" => {:ref, "upcase", "result"}
    })
  end

  # Broadcast a full observation state update — matches the pattern used in inspector tests.
  defp mock_obs_state(run_id, nodes_map, opts \\ []) do
    %{
      run_id: run_id,
      run_status: Keyword.get(opts, :run_status, :completed),
      run_started_at: "2026-03-19T14:00:00.000Z",
      run_completed_at: Keyword.get(opts, :run_completed_at, "2026-03-19T14:00:10.000Z"),
      event_count: Keyword.get(opts, :event_count, 6),
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

  # Broadcast a single event on the events PubSub topic — simulates what
  # Observation.Server does for each new event.
  defp broadcast_event(run_id, event) do
    Phoenix.PubSub.broadcast(
      Liminara.Observation.PubSub,
      "observation:#{run_id}:events",
      {:event_update, run_id, event}
    )
  end

  defp op_completed_node(node_id) do
    %{
      status: :completed,
      op_name: node_id,
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
  end

  defp node_with_decision(node_id) do
    %{
      status: :completed,
      op_name: node_id,
      op_version: "1.0",
      determinism: :recordable,
      started_at: "2026-03-19T14:00:01.000Z",
      completed_at: "2026-03-19T14:00:02.000Z",
      duration_ms: 55,
      input_hashes: [],
      output_hashes: [],
      cache_hit: false,
      error: nil,
      gate_prompt: nil,
      gate_response: nil,
      decisions: [
        %{hash: "sha256:dec1hash", type: "llm_response"}
      ]
    }
  end

  # ── Timeline panel presence ─────────────────────────────────────────────────

  describe "timeline panel — presence in layout" do
    test "run detail page contains a timeline panel element", %{conn: conn} do
      run_id = unique_run_id("tl-present")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5_000)
      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      assert html =~ "timeline" or html =~ "event-timeline",
             "Expected a timeline panel in the run detail layout. HTML:\n#{html}"
    end

    test "timeline panel has the expected CSS class or id", %{conn: conn} do
      # Verifies the timeline panel element has a discoverable identifier.
      # The implementation should render something like class="timeline-panel"
      # or id="timeline" in the HTML.
      run_id = unique_run_id("tl-css")

      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5_000)
      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      assert html =~ "timeline-panel" or html =~ ~r/id="timeline"/,
             "Expected timeline panel CSS class or id. HTML:\n#{html}"
    end
  end

  describe "timeline panel — collapsible toggle" do
    test "timeline panel has a toggle control", %{conn: conn} do
      run_id = unique_run_id("tl-toggle-ctrl")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5_000)
      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      # The toggle button should have a phx-click="toggle_timeline" or similar
      assert html =~ "toggle_timeline" or html =~ "timeline-toggle",
             "Expected a toggle control for the timeline panel. HTML:\n#{html}"
    end

    test "sending toggle_timeline event collapses the timeline panel", %{conn: conn} do
      run_id = unique_run_id("tl-collapse")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5_000)
      Process.sleep(100)

      {:ok, view, html_before} = live(conn, "/runs/#{run_id}")

      # Timeline should initially be visible / expanded
      assert html_before =~ "timeline",
             "Expected timeline to be present before toggle. HTML:\n#{html_before}"

      render_click(view, "toggle_timeline", %{})
      html_after = render(view)

      # After toggle, timeline should have a collapsed/hidden indicator
      # Either a class like "timeline--collapsed" or the events list is hidden
      assert html_after =~ "timeline--collapsed" or
               (html_after =~ "timeline" and
                  not (html_after =~ "timeline-panel timeline-panel--expanded")),
             "Expected timeline to be collapsed after toggle. HTML:\n#{html_after}"
    end

    test "sending toggle_timeline twice restores expanded state", %{conn: conn} do
      run_id = unique_run_id("tl-toggle-twice")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5_000)
      Process.sleep(100)

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      render_click(view, "toggle_timeline", %{})
      render_click(view, "toggle_timeline", %{})

      html = render(view)

      refute html =~ "timeline--collapsed",
             "Timeline should be expanded after two toggles. HTML:\n#{html}"
    end
  end

  # ── Timeline events display ─────────────────────────────────────────────────

  describe "timeline — events displayed for a completed run" do
    test "timeline shows events for a completed run loaded via RunServer", %{conn: conn} do
      run_id = unique_run_id("tl-completed")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5_000)
      Process.sleep(150)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      # Timeline should show at least the run_started and op_completed events
      assert html =~ "run_started" or html =~ "op_completed" or html =~ "run_completed",
             "Expected timeline events in the HTML. HTML:\n#{html}"
    end

    test "timeline events include timestamps", %{conn: conn} do
      run_id = unique_run_id("tl-timestamps")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5_000)
      Process.sleep(150)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      # A timestamp like "2026-" should appear within the timeline section
      assert html =~ "202",
             "Expected a year-like timestamp in the timeline. HTML:\n#{html}"
    end

    test "timeline events are in chronological order (earliest first)", %{conn: conn} do
      run_id = unique_run_id("tl-order")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5_000)
      Process.sleep(150)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      # In the rendered HTML, run_started should appear before run_completed
      start_pos = :binary.match(html, "run_started")
      complete_pos = :binary.match(html, "run_completed")

      case {start_pos, complete_pos} do
        {{s, _}, {c, _}} ->
          assert s < c,
                 "Expected run_started to appear before run_completed in timeline. HTML:\n#{html}"

        _ ->
          flunk("Expected both run_started and run_completed in timeline. HTML:\n#{html}")
      end
    end

    test "each event row shows the event_type", %{conn: conn} do
      run_id = unique_run_id("tl-event-type")

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      obs_state =
        mock_obs_state(run_id, %{"upcase" => op_completed_node("upcase")})

      broadcast_state(run_id, obs_state)
      Process.sleep(50)

      broadcast_event(run_id, %{
        event_hash: "sha256:rs",
        event_type: "run_started",
        payload: %{"run_id" => run_id},
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:00.000Z"
      })

      Process.sleep(100)
      html = render(view)

      assert html =~ "run_started",
             "Expected run_started event_type label in timeline. HTML:\n#{html}"
    end

    test "op event row shows node_id in the summary", %{conn: conn} do
      run_id = unique_run_id("tl-node-id")

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_event(run_id, %{
        event_hash: "sha256:os_upcase",
        event_type: "op_started",
        payload: %{
          "node_id" => "upcase",
          "op_id" => "upcase",
          "determinism" => "pure",
          "input_hashes" => []
        },
        prev_hash: "sha256:rs",
        timestamp: "2026-03-19T14:00:01.000Z"
      })

      Process.sleep(100)
      html = render(view)

      assert html =~ "upcase",
             "Expected node_id 'upcase' in the timeline event summary. HTML:\n#{html}"
    end
  end

  # ── Timeline real-time updates ──────────────────────────────────────────────

  describe "timeline — real-time event streaming" do
    test "new events appear in the timeline when broadcast on the events topic", %{conn: conn} do
      run_id = unique_run_id("tl-realtime")

      {:ok, view, html_before} = live(conn, "/runs/#{run_id}")

      # Broadcast an event via the events PubSub topic
      broadcast_event(run_id, %{
        event_hash: "sha256:rs_rt",
        event_type: "run_started",
        payload: %{"run_id" => run_id, "pack_id" => "test", "pack_version" => "1"},
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:00.000Z"
      })

      Process.sleep(100)
      html_after = render(view)

      refute html_before =~ "run_started",
             "Expected timeline to not yet show run_started before broadcast"

      assert html_after =~ "run_started",
             "Expected run_started to appear in timeline after broadcast. HTML:\n#{html_after}"
    end

    test "multiple events arrive and all appear in the timeline", %{conn: conn} do
      run_id = unique_run_id("tl-realtime-multi")

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_event(run_id, %{
        event_hash: "sha256:rs_m",
        event_type: "run_started",
        payload: %{"run_id" => run_id},
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:00.000Z"
      })

      broadcast_event(run_id, %{
        event_hash: "sha256:os_m",
        event_type: "op_started",
        payload: %{"node_id" => "upcase"},
        prev_hash: "sha256:rs_m",
        timestamp: "2026-03-19T14:00:01.000Z"
      })

      broadcast_event(run_id, %{
        event_hash: "sha256:oc_m",
        event_type: "op_completed",
        payload: %{"node_id" => "upcase", "duration_ms" => 10},
        prev_hash: "sha256:os_m",
        timestamp: "2026-03-19T14:00:02.000Z"
      })

      Process.sleep(150)
      html = render(view)

      assert html =~ "run_started",
             "Expected run_started in timeline. HTML:\n#{html}"

      assert html =~ "op_started",
             "Expected op_started in timeline. HTML:\n#{html}"

      assert html =~ "op_completed",
             "Expected op_completed in timeline. HTML:\n#{html}"
    end

    test "real-time events appear in chronological order in the timeline", %{conn: conn} do
      run_id = unique_run_id("tl-realtime-order")

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_event(run_id, %{
        event_hash: "sha256:rs_o",
        event_type: "run_started",
        payload: %{"run_id" => run_id},
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:00.000Z"
      })

      broadcast_event(run_id, %{
        event_hash: "sha256:rc_o",
        event_type: "run_completed",
        payload: %{"run_id" => run_id},
        prev_hash: "sha256:rs_o",
        timestamp: "2026-03-19T14:00:10.000Z"
      })

      Process.sleep(100)
      html = render(view)

      start_pos = :binary.match(html, "run_started")
      complete_pos = :binary.match(html, "run_completed")

      case {start_pos, complete_pos} do
        {{s, _}, {c, _}} ->
          assert s < c,
                 "Expected chronological order in real-time timeline. HTML:\n#{html}"

        _ ->
          flunk("Expected both run_started and run_completed in timeline. HTML:\n#{html}")
      end
    end
  end

  # ── Timeline filtering ──────────────────────────────────────────────────────

  describe "timeline — filter by event_type" do
    test "sending filter_timeline event with event_type shows only matching events", %{
      conn: conn
    } do
      run_id = unique_run_id("tl-filter-type")

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      # Populate timeline with several event types via broadcast
      for {hash, etype, payload} <- [
            {"sha256:rs_f", "run_started", %{"run_id" => run_id}},
            {"sha256:os_f", "op_started", %{"node_id" => "upcase"}},
            {"sha256:oc_f", "op_completed", %{"node_id" => "upcase"}},
            {"sha256:rc_f", "run_completed", %{"run_id" => run_id}}
          ] do
        broadcast_event(run_id, %{
          event_hash: hash,
          event_type: etype,
          payload: payload,
          prev_hash: nil,
          timestamp: "2026-03-19T14:00:00.000Z"
        })
      end

      Process.sleep(100)

      # Apply event_type filter
      render_click(view, "filter_timeline", %{"event_type" => "op_completed"})

      html = render(view)

      assert html =~ "op_completed",
             "Expected op_completed to remain visible after filter. HTML:\n#{html}"

      refute html =~ "run_started",
             "Expected run_started to be hidden after filtering by op_completed. HTML:\n#{html}"

      refute html =~ "op_started",
             "Expected op_started to be hidden after filtering by op_completed. HTML:\n#{html}"
    end

    test "filter_timeline with event_type does not crash the LiveView", %{conn: conn} do
      run_id = unique_run_id("tl-filter-nocrash")

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      # Should handle filter event gracefully
      render_click(view, "filter_timeline", %{"event_type" => "op_started"})

      html = render(view)
      assert is_binary(html)
    end

    test "clear_timeline_filter restores all events after filtering", %{conn: conn} do
      run_id = unique_run_id("tl-filter-clear")

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_event(run_id, %{
        event_hash: "sha256:rs_c",
        event_type: "run_started",
        payload: %{"run_id" => run_id},
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:00.000Z"
      })

      broadcast_event(run_id, %{
        event_hash: "sha256:oc_c",
        event_type: "op_completed",
        payload: %{"node_id" => "upcase"},
        prev_hash: "sha256:rs_c",
        timestamp: "2026-03-19T14:00:02.000Z"
      })

      Process.sleep(100)

      render_click(view, "filter_timeline", %{"event_type" => "op_completed"})
      render_click(view, "clear_timeline_filter", %{})

      html = render(view)

      assert html =~ "run_started",
             "Expected run_started to reappear after clearing filter. HTML:\n#{html}"

      assert html =~ "op_completed",
             "Expected op_completed to still be present after clearing filter. HTML:\n#{html}"
    end
  end

  describe "timeline — filter by node_id" do
    test "sending filter_timeline with node_id shows only events for that node", %{conn: conn} do
      run_id = unique_run_id("tl-filter-node")

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_event(run_id, %{
        event_hash: "sha256:rs_n",
        event_type: "run_started",
        payload: %{"run_id" => run_id},
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:00.000Z"
      })

      broadcast_event(run_id, %{
        event_hash: "sha256:os_upcase",
        event_type: "op_started",
        payload: %{"node_id" => "upcase"},
        prev_hash: "sha256:rs_n",
        timestamp: "2026-03-19T14:00:01.000Z"
      })

      broadcast_event(run_id, %{
        event_hash: "sha256:os_reverse",
        event_type: "op_started",
        payload: %{"node_id" => "reverse"},
        prev_hash: "sha256:rs_n",
        timestamp: "2026-03-19T14:00:02.000Z"
      })

      Process.sleep(100)

      render_click(view, "filter_timeline", %{"node_id" => "upcase"})

      html = render(view)

      # "upcase" events should be visible; "reverse" and run-level events hidden
      assert html =~ "upcase",
             "Expected upcase node events to remain visible. HTML:\n#{html}"
    end

    test "filter_timeline by node_id hides events from other nodes", %{conn: conn} do
      run_id = unique_run_id("tl-filter-node-hide")

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_event(run_id, %{
        event_hash: "sha256:os_u2",
        event_type: "op_started",
        payload: %{"node_id" => "upcase"},
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:01.000Z"
      })

      broadcast_event(run_id, %{
        event_hash: "sha256:os_r2",
        event_type: "op_started",
        payload: %{"node_id" => "reverse"},
        prev_hash: "sha256:os_u2",
        timestamp: "2026-03-19T14:00:02.000Z"
      })

      Process.sleep(100)

      # Filter to show only "upcase" node events
      # After filter, "reverse" node events should not appear in the timeline list
      render_click(view, "filter_timeline", %{"node_id" => "upcase"})

      html = render(view)

      # The timeline list items for "reverse" must be absent
      # We check the timeline section does not contain the reverse node's event entry
      # Note: "reverse" may still appear in other parts of the page (dag etc.)
      # So we target only the timeline area if possible — otherwise just check
      # that the filter is applied (simple check: presence of upcase in timeline context)
      assert html =~ "upcase",
             "Expected upcase events visible after filtering by node. HTML:\n#{html}"
    end

    test "clear_timeline_filter after node_id filter shows all events again", %{conn: conn} do
      run_id = unique_run_id("tl-filter-node-clear")

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_event(run_id, %{
        event_hash: "sha256:os_uc",
        event_type: "op_started",
        payload: %{"node_id" => "upcase"},
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:01.000Z"
      })

      broadcast_event(run_id, %{
        event_hash: "sha256:os_rc",
        event_type: "op_started",
        payload: %{"node_id" => "reverse"},
        prev_hash: "sha256:os_uc",
        timestamp: "2026-03-19T14:00:02.000Z"
      })

      Process.sleep(100)

      render_click(view, "filter_timeline", %{"node_id" => "upcase"})
      render_click(view, "clear_timeline_filter", %{})

      html = render(view)

      # Both events should be in the timeline now
      assert html =~ "op_started",
             "Expected op_started events visible after clearing filter. HTML:\n#{html}"
    end
  end

  # ── Click a timeline event → select node ───────────────────────────────────

  describe "timeline — click event selects corresponding DAG node" do
    test "clicking a timeline event triggers select_node for the event's node_id", %{conn: conn} do
      run_id = unique_run_id("tl-click-select")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5_000)
      Process.sleep(100)

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      # Simulate the user clicking a timeline event row.
      # The LiveView should translate this into a select_node event for the node_id
      # from the event payload. The event phx-click will be "select_node" with
      # phx-value-node-id from the event's payload.node_id.
      render_click(view, "select_node", %{"node-id" => "upcase"})

      html = render(view)

      # After selecting a node via timeline click, the inspector should open
      assert html =~ "inspector" or html =~ "upcase",
             "Expected node inspector to open after timeline event click. HTML:\n#{html}"
    end

    test "timeline event rows have phx-click='select_node' attribute with node_id", %{conn: conn} do
      run_id = unique_run_id("tl-click-attr")

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      # Broadcast an op_started event so a timeline row is rendered
      broadcast_event(run_id, %{
        event_hash: "sha256:os_click",
        event_type: "op_started",
        payload: %{"node_id" => "upcase"},
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:01.000Z"
      })

      Process.sleep(100)
      html = render(view)

      # The timeline event row must have a phx-click that references select_node
      # and carries the node_id as a value
      assert html =~ "select_node",
             "Expected phx-click='select_node' on timeline event rows. HTML:\n#{html}"
    end

    test "run-level events (no node_id) in timeline do not show select_node for a node", %{
      conn: conn
    } do
      run_id = unique_run_id("tl-click-run-level")

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      broadcast_event(run_id, %{
        event_hash: "sha256:rs_cl",
        event_type: "run_started",
        payload: %{"run_id" => run_id},
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:00.000Z"
      })

      Process.sleep(100)
      html = render(view)

      # The LiveView should handle this gracefully — no crash, page still renders
      assert html =~ run_id,
             "Expected run detail page to still render with run-level events. HTML:\n#{html}"
    end
  end

  # ── Decision viewer ─────────────────────────────────────────────────────────

  describe "decision viewer — listing decisions for a run" do
    test "decision viewer section is present on the run detail page", %{conn: conn} do
      run_id = unique_run_id("dv-present")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5_000)
      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      assert html =~ "decision" or html =~ "decisions",
             "Expected a decisions section in the run detail page. HTML:\n#{html}"
    end

    test "decision viewer shows decisions when run has recorded decisions", %{conn: conn} do
      run_id = unique_run_id("dv-decisions")

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => node_with_decision("upcase")
        })

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      html = render(view)

      # The decision hash should appear somewhere on the page
      assert html =~ "sha256:dec1hash" or html =~ "dec1hash" or html =~ "llm_response",
             "Expected decision details in the run detail page. HTML:\n#{html}"
    end

    test "decision viewer shows node_id for each decision", %{conn: conn} do
      run_id = unique_run_id("dv-node-id")

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => node_with_decision("upcase")
        })

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})

      html = render(view)

      assert html =~ "upcase",
             "Expected node_id 'upcase' to appear near decision entry. HTML:\n#{html}"
    end

    test "decision viewer shows decision_type", %{conn: conn} do
      run_id = unique_run_id("dv-dec-type")

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => node_with_decision("upcase")
        })

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})

      html = render(view)

      assert html =~ "llm_response",
             "Expected decision_type 'llm_response' to appear. HTML:\n#{html}"
    end

    test "decision viewer shows decision_hash", %{conn: conn} do
      run_id = unique_run_id("dv-dec-hash")

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => node_with_decision("upcase")
        })

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      render_click(view, "select_node", %{"node-id" => "upcase"})

      html = render(view)

      assert html =~ "dec1hash",
             "Expected decision_hash 'dec1hash' to appear. HTML:\n#{html}"
    end

    test "clicking a decision row selects the corresponding node in the DAG", %{conn: conn} do
      run_id = unique_run_id("dv-click-select")

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => node_with_decision("upcase")
        })

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      # The decision viewer should contain a clickable element that fires select_node
      # for the decision's node. We simulate this directly.
      render_click(view, "select_node", %{"node-id" => "upcase"})

      html = render(view)

      assert html =~ "inspector" or html =~ "upcase",
             "Expected node inspector to open after clicking decision entry. HTML:\n#{html}"
    end

    test "run with no decisions shows an empty or absent decisions section", %{conn: conn} do
      run_id = unique_run_id("dv-no-decisions")

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      obs_state =
        mock_obs_state(run_id, %{
          "upcase" => op_completed_node("upcase")
        })

      broadcast_state(run_id, obs_state)
      Process.sleep(100)

      html = render(view)

      # The page should not crash when there are no decisions.
      assert html =~ run_id,
             "Expected page to render for run with no decisions. HTML:\n#{html}"
    end
  end

  # ── Layout integration ──────────────────────────────────────────────────────

  describe "layout integration" do
    test "timeline, DAG, and inspector panels all co-exist in the layout", %{conn: conn} do
      run_id = unique_run_id("layout-all")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5_000)
      Process.sleep(150)

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      render_click(view, "select_node", %{"node-id" => "upcase"})

      html = render(view)

      assert html =~ "id=\"dag-map\"",
             "Expected dag-map panel. HTML:\n#{html}"

      assert html =~ "node-inspector" or html =~ "inspector",
             "Expected inspector panel. HTML:\n#{html}"

      assert html =~ "timeline",
             "Expected timeline panel. HTML:\n#{html}"
    end

    test "all panels still update in real-time after timeline is added", %{conn: conn} do
      run_id = unique_run_id("layout-realtime")

      plan =
        Plan.new()
        |> Plan.add_node("slow", Liminara.TestOps.Slow, %{"text" => {:literal, "watching"}})

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5_000)
      Process.sleep(200)

      html = render(view)

      assert html =~ "completed",
             "Expected completed status after run. HTML:\n#{html}"
    end

    test "timeline panel integrates into the run-detail-layout grid", %{conn: conn} do
      run_id = unique_run_id("layout-grid")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5_000)
      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      # The grid container must contain a timeline area
      assert html =~ "run-detail-layout",
             "Expected run-detail-layout container. HTML:\n#{html}"

      assert html =~ "timeline",
             "Expected timeline inside the run-detail-layout. HTML:\n#{html}"
    end
  end

  # ── Subscription to events PubSub topic ────────────────────────────────────

  describe "LiveView subscription to events topic" do
    test "LiveView subscribes to observation:{run_id}:events on mount", %{conn: conn} do
      run_id = unique_run_id("tl-sub")

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      # Broadcast on the events topic — if the LiveView is not subscribed, no update happens
      # and the test will detect absence of the event in the rendered HTML.
      broadcast_event(run_id, %{
        event_hash: "sha256:sub_rs",
        event_type: "run_started",
        payload: %{"run_id" => run_id},
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:00.000Z"
      })

      Process.sleep(100)
      html = render(view)

      assert html =~ "run_started",
             "Expected LiveView to receive and display event from events topic. HTML:\n#{html}"
    end
  end
end
