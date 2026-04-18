defmodule LiminaraWeb.RunsLive.IndexTest do
  @moduledoc """
  LiveView tests for the /runs page (RunsLive.Index).

  These tests are RED — RunsLive.Index does not exist yet.
  All tests should fail with a module-not-found or route error.
  """
  use LiminaraWeb.ConnCase, async: false

  alias Liminara.Plan
  alias Liminara.Run.Server, as: RunServer

  # ── Helpers ──────────────────────────────────────────────────────

  defp unique_run_id(prefix \\ "web-idx") do
    "#{prefix}-#{:erlang.unique_integer([:positive])}"
  end

  defp simple_plan do
    Plan.new()
    |> Plan.add_node("upcase", Liminara.TestOps.Upcase, %{
      "text" => {:literal, "hello"}
    })
  end

  # ── Basic rendering ──────────────────────────────────────────────

  describe "mount /runs" do
    test "renders the runs page with a heading", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/runs")

      assert html =~ "Runs"
    end

    test "renders an empty state when no runs exist", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/runs")

      # Page mounts without error even when runs list is empty
      assert html =~ "runs" or html =~ "Runs"
    end
  end

  # ── Runs list content ────────────────────────────────────────────

  describe "runs list content" do
    test "shows run_id for each run in the list", %{conn: conn} do
      # Create a run by writing directly to the event store
      run_id = unique_run_id("content-id")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5000)

      # Give PubSub time to propagate
      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs")

      assert html =~ run_id
    end

    test "shows pack_id for each run", %{conn: conn} do
      run_id = unique_run_id("content-pack")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "my_test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5000)

      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs")

      assert html =~ "my_test_pack"
    end

    test "shows status for each run", %{conn: conn} do
      run_id = unique_run_id("content-status")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5000)

      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs")

      # Status should be shown (completed, failed, running, etc.)
      assert html =~ "completed" or html =~ "success" or html =~ "running"
    end

    test "each run row contains a link to its detail page", %{conn: conn} do
      run_id = unique_run_id("content-link")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5000)

      Process.sleep(100)

      {:ok, _view, html} = live(conn, "/runs")

      # Each run should have a link to /runs/:id
      assert html =~ "/runs/#{run_id}"
    end
  end

  # ── Real-time updates ────────────────────────────────────────────

  describe "real-time updates" do
    test "new run appears in list without page reload", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/runs")

      run_id = unique_run_id("realtime-new")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5000)

      # Give PubSub time to deliver the update
      Process.sleep(200)

      html = render(view)
      assert html =~ run_id
    end

    test "run status updates in real-time from running to completed", %{conn: conn} do
      run_id = unique_run_id("realtime-status")

      # Use a slow plan so we can observe the running → completed transition
      plan =
        Plan.new()
        |> Plan.add_node("slow", Liminara.TestOps.Slow, %{"text" => {:literal, "watch me"}})

      {:ok, view, _html} = live(conn, "/runs")

      # Start a run (will take ~500ms)
      RunServer.start(run_id, plan, pack_id: "slow_pack", pack_version: "0.1.0")

      # Give a short sleep so running state is visible
      Process.sleep(50)
      html_mid = render(view)

      # Wait for completion
      {:ok, _result} = RunServer.await(run_id, 5000)
      Process.sleep(200)

      html_final = render(view)

      # The page should have updated with the final status
      # Either we saw "running" mid-run, or at least "completed" in final state
      assert html_mid =~ run_id or html_final =~ run_id
      assert html_final =~ "completed" or html_final =~ "success"
    end

    test "multiple runs appear in list as they complete", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/runs")

      run_id_1 = unique_run_id("multi-a")
      run_id_2 = unique_run_id("multi-b")
      plan = simple_plan()

      RunServer.start(run_id_1, plan, pack_id: "test_pack", pack_version: "0.1.0")
      RunServer.start(run_id_2, plan, pack_id: "test_pack", pack_version: "0.1.0")

      {:ok, _} = RunServer.await(run_id_1, 5000)
      {:ok, _} = RunServer.await(run_id_2, 5000)

      Process.sleep(200)

      html = render(view)
      assert html =~ run_id_1
      assert html =~ run_id_2
    end
  end

  # ── Degraded runs (M-WARN-02) ────────────────────────────────────

  describe "degraded run indicator" do
    test "run row shows a degraded indicator when warning_count > 0 and not failed",
         %{conn: conn} do
      # Directly simulate a run event with warning_summary via PubSub.
      {:ok, view, _html} = live(conn, "/runs")

      run_id = unique_run_id("deg-indicator")

      :pg.get_members(:liminara, :all_runs)
      |> Enum.each(fn pid ->
        send(
          pid,
          {:run_event, run_id,
           %{
             "event_type" => "run_started",
             "timestamp" => "2026-03-19T14:00:00.000Z",
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
             "event_type" => "run_completed",
             "timestamp" => "2026-03-19T14:00:05.000Z",
             "payload" => %{
               "run_id" => run_id,
               "outcome" => "success",
               "artifact_hashes" => [],
               "warning_summary" => %{
                 "warning_count" => 1,
                 "degraded_node_ids" => ["summarize"]
               }
             }
           }}
        )
      end)

      Process.sleep(150)
      html = render(view)

      assert html =~ "degraded",
             "Degraded run should carry a visible degraded indicator. HTML:\n#{html}"
    end

    test "plain-success run does NOT show a degraded indicator", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/runs")

      run_id = unique_run_id("plain-no-indicator")

      :pg.get_members(:liminara, :all_runs)
      |> Enum.each(fn pid ->
        send(
          pid,
          {:run_event, run_id,
           %{
             "event_type" => "run_started",
             "timestamp" => "2026-03-19T14:00:00.000Z",
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
             "event_type" => "run_completed",
             "timestamp" => "2026-03-19T14:00:05.000Z",
             "payload" => %{
               "run_id" => run_id,
               "outcome" => "success",
               "artifact_hashes" => [],
               "warning_summary" => %{"warning_count" => 0, "degraded_node_ids" => []}
             }
           }}
        )
      end)

      Process.sleep(150)
      html = render(view)

      # No row for this run should carry status--degraded badge
      refute html =~ "status--degraded",
             "Plain-success run should not carry degraded badge. HTML:\n#{html}"
    end

    test "failed run does NOT show a degraded indicator even with warnings",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/runs")

      run_id = unique_run_id("failed-warn")

      :pg.get_members(:liminara, :all_runs)
      |> Enum.each(fn pid ->
        send(
          pid,
          {:run_event, run_id,
           %{
             "event_type" => "run_started",
             "timestamp" => "2026-03-19T14:00:00.000Z",
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
             "event_type" => "run_failed",
             "timestamp" => "2026-03-19T14:00:05.000Z",
             "payload" => %{
               "run_id" => run_id,
               "error_type" => "op_failure",
               "error_message" => "broken",
               "warning_summary" => %{
                 "warning_count" => 2,
                 "degraded_node_ids" => ["a"]
               }
             }
           }}
        )
      end)

      Process.sleep(150)
      html = render(view)

      # Row status should be 'failed' — not 'degraded'.
      refute html =~ "status--degraded",
             "Failed run should not show degraded indicator. HTML:\n#{html}"

      assert html =~ "status--failed",
             "Failed run should show failed status. HTML:\n#{html}"
    end
  end

  # ── Navigation ───────────────────────────────────────────────────

  describe "navigation" do
    test "page contains a header or navigation link back to runs list", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/runs")

      # Should have some nav element referencing the runs index
      assert html =~ "/runs" or html =~ "Runs"
    end

    test "clicking a run link navigates to the run detail page", %{conn: conn} do
      run_id = unique_run_id("nav-click")
      plan = simple_plan()

      RunServer.start(run_id, plan, pack_id: "test_pack", pack_version: "0.1.0")
      {:ok, _result} = RunServer.await(run_id, 5000)

      Process.sleep(100)

      {:ok, view, _html} = live(conn, "/runs")

      # Navigate to the run detail using the link
      {:ok, _detail_view, detail_html} =
        view |> element("a[href='/runs/#{run_id}']") |> render_click() |> follow_redirect(conn)

      assert detail_html =~ run_id
    end
  end
end
