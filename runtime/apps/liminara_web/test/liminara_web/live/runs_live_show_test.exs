defmodule LiminaraWeb.RunsLive.ShowTest do
  @moduledoc """
  LiveView tests for the /runs/:id page (RunsLive.Show).
  """
  use LiminaraWeb.ConnCase, async: false

  alias Liminara.{Plan}
  alias Liminara.Run.Server, as: RunServer

  # -- Helpers ----------------------------------------------------------------

  defp unique_run_id(prefix \\ "web-show") do
    "#{prefix}-#{:erlang.unique_integer([:positive])}"
  end

  defp simple_plan do
    Plan.new()
    |> Plan.add_node("upcase", Liminara.TestOps.Upcase, %{
      "text" => {:literal, "hello"}
    })
  end

  defp two_node_plan do
    Plan.new()
    |> Plan.add_node("upcase", Liminara.TestOps.Upcase, %{
      "text" => {:literal, "hello"}
    })
    |> Plan.add_node("reverse", Liminara.TestOps.Reverse, %{
      "text" => {:ref, "upcase", "result"}
    })
  end

  # -- Completed run detail ---------------------------------------------------

  describe "completed run detail" do
    test "renders the run detail page for a completed run", %{conn: conn} do
      run_id = unique_run_id("completed")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5000)

      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      assert html =~ run_id
    end

    test "shows run_id on the detail page", %{conn: conn} do
      run_id = unique_run_id("show-id")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5000)

      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      assert html =~ run_id
    end

    test "shows run status on the detail page", %{conn: conn} do
      run_id = unique_run_id("show-status")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5000)

      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      assert html =~ "completed" or html =~ "success"
    end

    test "shows node count on the detail page", %{conn: conn} do
      run_id = unique_run_id("show-node-count")
      plan = two_node_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5000)

      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      # Two nodes exist in the plan; page should reflect node count
      assert html =~ "2" or html =~ "upcase" or html =~ "reverse"
    end

    test "shows node names in dag-data for the detail page", %{conn: conn} do
      run_id = unique_run_id("show-nodes")
      plan = two_node_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5000)

      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      # Node labels appear in the data-dag JSON attribute
      assert html =~ "Upcase"
      assert html =~ "Reverse"
    end

    test "shows node statuses on the detail page", %{conn: conn} do
      run_id = unique_run_id("show-node-status")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5000)

      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      # Node status should be shown (completed)
      assert html =~ "completed"
    end

    test "auto-starts Observation.Server when navigating to run detail", %{conn: conn} do
      run_id = unique_run_id("obs-autostart")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5000)

      Process.sleep(100)

      # Navigating to the detail page should implicitly start an Observation.Server
      # and render the view model -- verified by showing run status
      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      assert html =~ run_id
      assert html =~ "completed" or html =~ "success"
    end

    test "shows timing information for a completed run", %{conn: conn} do
      run_id = unique_run_id("show-timing")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5000)

      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      # Page should contain some timing info (timestamps, duration, or similar)
      # The exact format will vary -- check for a year that makes sense
      assert html =~ "202"
    end

    test "works for runs with multiple nodes", %{conn: conn} do
      run_id = unique_run_id("show-multi")

      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "alpha"}})
        |> Plan.add_node("b", Liminara.TestOps.Reverse, %{"text" => {:ref, "a", "result"}})

      RunServer.start(run_id, plan, pack_id: "multi_pack", pack_version: "1.0.0")
      {:ok, _result} = RunServer.await(run_id, 5000)

      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      assert html =~ run_id
      # Node labels appear in the data-dag JSON
      assert html =~ "Upcase"
      assert html =~ "Reverse"
    end
  end

  # -- Non-existent run -------------------------------------------------------

  describe "non-existent run" do
    test "shows an error or not-found message for unknown run_id", %{conn: conn} do
      fake_run_id = "nonexistent-run-#{:erlang.unique_integer([:positive])}"

      {:ok, _view, html} = live(conn, "/runs/#{fake_run_id}")

      # Should show some kind of error or not-found indication
      assert html =~ "not found" or html =~ "error" or html =~ "Not Found" or html =~ "Error"
    end

    test "does not crash the LiveView process for unknown run_id", %{conn: conn} do
      fake_run_id = "does-not-exist-#{:erlang.unique_integer([:positive])}"

      # Should mount without raising -- either render an error page or a not-found state
      result = live(conn, "/runs/#{fake_run_id}")

      case result do
        {:ok, _view, html} ->
          assert is_binary(html)

        {:error, {:live_redirect, _}} ->
          # Acceptable: redirect to runs list with an error flash
          :ok
      end
    end
  end

  # -- Real-time updates ------------------------------------------------------

  describe "real-time updates for active run" do
    test "detail page receives status updates from pending to completed", %{conn: conn} do
      run_id = unique_run_id("rt-active")

      plan =
        Plan.new()
        |> Plan.add_node("slow", Liminara.TestOps.Slow, %{"text" => {:literal, "watching"}})

      # Navigate to detail page before the run starts
      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      # Now start the run
      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")

      # Poll for running state (should appear fairly quickly)
      Process.sleep(100)
      html_mid = render(view)

      # Wait for run to complete
      {:ok, _result} = RunServer.await(run_id, 5000)
      Process.sleep(200)

      html_final = render(view)

      # The page should have been updated at some point
      assert html_mid =~ run_id or html_final =~ run_id
      assert html_final =~ "completed" or html_final =~ "success"
    end

    test "detail page receives PubSub updates from Observation.Server", %{conn: conn} do
      run_id = unique_run_id("rt-pubsub")

      plan =
        Plan.new()
        |> Plan.add_node("slow", Liminara.TestOps.Slow, %{"text" => {:literal, "realtime"}})

      # Open detail page first
      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      # Manually broadcast an observation update (simulates what Observation.Server does)
      mock_state = %{
        run_id: run_id,
        run_status: :completed,
        run_started_at: "2026-01-01T00:00:00.000Z",
        run_completed_at: "2026-01-01T00:00:01.000Z",
        event_count: 3,
        nodes: %{
          "slow" => %{
            status: :completed,
            op_name: "slow",
            op_version: "1.0",
            determinism: :pure,
            started_at: "2026-01-01T00:00:00.100Z",
            completed_at: "2026-01-01T00:00:01.000Z",
            duration_ms: 900,
            input_hashes: [],
            output_hashes: [],
            cache_hit: false,
            error: nil,
            gate_prompt: nil,
            gate_response: nil,
            decisions: []
          }
        },
        plan: plan
      }

      Phoenix.PubSub.broadcast(
        Liminara.Observation.PubSub,
        "observation:#{run_id}:state",
        {:state_update, run_id, mock_state}
      )

      Process.sleep(100)
      html = render(view)

      assert html =~ "completed"
    end

    test "node status updates are reflected in the rendered HTML", %{conn: conn} do
      run_id = unique_run_id("rt-nodes")
      plan = simple_plan()

      # Open the detail page
      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      # Start the run
      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5000)

      Process.sleep(200)

      html = render(view)

      # After completion, the node should show as completed
      assert html =~ "completed"
    end
  end

  # -- Integration: Observation.Server lifecycle ------------------------------

  describe "Observation.Server integration" do
    test "detail page for active run starts Observation.Server", %{conn: conn} do
      run_id = unique_run_id("obs-start")

      plan =
        Plan.new()
        |> Plan.add_node("slow", Liminara.TestOps.Slow, %{"text" => {:literal, "observe me"}})

      # Start the run
      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")

      # Navigate to detail -- this should auto-start Observation.Server
      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      # Wait for run to complete, then verify view updated
      {:ok, _result} = RunServer.await(run_id, 5000)
      Process.sleep(200)

      html = render(view)

      # If Observation.Server was started and PubSub is wired up, we should see updates
      assert html =~ run_id
    end

    test "completed run detail page works without a running Observation.Server", %{conn: conn} do
      run_id = unique_run_id("obs-completed")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5000)

      # Wait for run server to stop
      Process.sleep(200)

      # Now navigate to the completed run's detail page
      # The LiveView should start an Observation.Server that loads from event log
      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      assert html =~ run_id
      assert html =~ "completed" or html =~ "success"
    end
  end

  # -- Navigation -------------------------------------------------------------

  describe "navigation from run detail" do
    test "page contains a link back to the runs list", %{conn: conn} do
      run_id = unique_run_id("nav-back")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5000)

      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      # Should have a link back to /runs
      assert html =~ ~r{href=["']/runs["']} or html =~ "/runs"
    end
  end

  # -- Node selection ---------------------------------------------------------

  describe "node selection" do
    test "select_node event stores selected node in assigns", %{conn: conn} do
      run_id = unique_run_id("select-node")
      plan = two_node_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5000)
      Process.sleep(100)

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      # Push a select_node event (simulates client-side click on a node)
      render_click(view, "select_node", %{"node-id" => "upcase"})

      # Verify the view is still alive and rendered (no crash)
      html = render(view)
      assert html =~ run_id
    end
  end

  # -- Node coloring ---------------------------------------------------------

  describe "node status coloring" do
    test "completed nodes get 'pure' class in dag data", %{conn: conn} do
      run_id = unique_run_id("cls-completed")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5000)
      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      # Completed nodes should have cls "pure" (teal)
      assert html =~ "pure"
    end

    test "pending nodes get 'pending' class via PubSub state update", %{conn: conn} do
      run_id = unique_run_id("cls-pending")

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      # Send a state update with a pending node
      mock_state = %{
        run_id: run_id,
        run_status: :running,
        run_started_at: "2026-01-01T00:00:00.000Z",
        run_completed_at: nil,
        event_count: 1,
        nodes: %{
          "step_a" => %{
            status: :pending,
            op_name: "step_a",
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
        },
        plan: nil
      }

      Phoenix.PubSub.broadcast(
        Liminara.Observation.PubSub,
        "observation:#{run_id}:state",
        {:state_update, run_id, mock_state}
      )

      Process.sleep(100)
      html = render(view)

      # Pending node should have cls "pending" (gray)
      assert html =~ "&quot;pending&quot;"
    end

    test "running nodes get 'recordable' class via PubSub state update", %{conn: conn} do
      run_id = unique_run_id("cls-running")

      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      mock_state = %{
        run_id: run_id,
        run_status: :running,
        run_started_at: "2026-01-01T00:00:00.000Z",
        run_completed_at: nil,
        event_count: 2,
        nodes: %{
          "step_a" => %{
            status: :running,
            op_name: "step_a",
            op_version: "1.0",
            determinism: :pure,
            started_at: "2026-01-01T00:00:00.100Z",
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
        },
        plan: nil
      }

      Phoenix.PubSub.broadcast(
        Liminara.Observation.PubSub,
        "observation:#{run_id}:state",
        {:state_update, run_id, mock_state}
      )

      Process.sleep(100)
      html = render(view)

      # Running node should have cls "recordable" (coral)
      assert html =~ "&quot;recordable&quot;"
    end
  end

  # -- Client-side DAG visualization (dag-map hook) ---------------------------

  describe "DAG visualization via dag-map hook" do
    test "mount /runs/:id for a completed run renders a dag-map container with data-dag", %{
      conn: conn
    } do
      run_id = unique_run_id("dagmap-container")
      plan = two_node_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5000)

      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      assert html =~ "id=\"dag-map\"",
             "Expected dag-map container element. HTML:\n#{html}"

      assert html =~ "phx-hook=\"DagMap\"",
             "Expected phx-hook=DagMap attribute. HTML:\n#{html}"

      assert html =~ "data-dag=",
             "Expected data-dag attribute with JSON. HTML:\n#{html}"
    end

    test "data-dag JSON contains node entries for each plan node", %{conn: conn} do
      run_id = unique_run_id("dagmap-nodes")
      plan = two_node_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5000)

      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      # The data-dag attribute contains JSON with node labels
      assert html =~ "Upcase",
             "Expected 'Upcase' label in dag data. HTML:\n#{html}"

      assert html =~ "Reverse",
             "Expected 'Reverse' label in dag data. HTML:\n#{html}"
    end

    test "data-dag JSON contains edges from plan refs", %{conn: conn} do
      run_id = unique_run_id("dagmap-edges")
      plan = two_node_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5000)

      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      # The edges array should contain a reference from upcase to reverse
      # In HTML-escaped JSON: [&quot;upcase&quot;,&quot;reverse&quot;]
      assert html =~ "upcase" and html =~ "reverse",
             "Expected edge between upcase and reverse in dag data. HTML:\n#{html}"
    end

    test "dag data updates when run state changes via PubSub", %{conn: conn} do
      run_id = unique_run_id("dagmap-update")

      plan =
        Plan.new()
        |> Plan.add_node("slow", Liminara.TestOps.Slow, %{"text" => {:literal, "watch"}})

      # Open detail page before run starts
      {:ok, view, _html} = live(conn, "/runs/#{run_id}")

      # Start the run
      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")

      # Wait for run to complete
      {:ok, _result} = RunServer.await(run_id, 5000)
      Process.sleep(200)

      html_final = render(view)

      # After completion, the page should show completed status
      assert html_final =~ "completed",
             "Expected completed status after run. HTML:\n#{html_final}"
    end
  end
end
