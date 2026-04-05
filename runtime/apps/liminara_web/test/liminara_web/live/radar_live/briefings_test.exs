defmodule LiminaraWeb.RadarLive.BriefingsTest do
  use LiminaraWeb.ConnCase, async: false

  alias Liminara.{Artifact, Decision, Event}

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    store_root = Path.join(tmp_dir, "store")
    runs_root = Path.join(tmp_dir, "runs")
    File.mkdir_p!(store_root)
    File.mkdir_p!(runs_root)

    # Override app config for this test
    prev_store = Application.get_env(:liminara_core, :store_root)
    prev_runs = Application.get_env(:liminara_core, :runs_root)
    Application.put_env(:liminara_core, :store_root, store_root)
    Application.put_env(:liminara_core, :runs_root, runs_root)

    on_exit(fn ->
      if prev_store,
        do: Application.put_env(:liminara_core, :store_root, prev_store),
        else: Application.delete_env(:liminara_core, :store_root)

      if prev_runs,
        do: Application.put_env(:liminara_core, :runs_root, prev_runs),
        else: Application.delete_env(:liminara_core, :runs_root)
    end)

    %{store_root: store_root, runs_root: runs_root}
  end

  defp create_radar_run(runs_root, store_root, run_id, opts \\ []) do
    status = Keyword.get(opts, :status, :completed)
    item_count = Keyword.get(opts, :item_count, 10)
    cluster_count = Keyword.get(opts, :cluster_count, 3)
    source_count = Keyword.get(opts, :source_count, 5)

    # Write run_started event
    {:ok, ev1} =
      Event.Store.append(
        runs_root,
        run_id,
        "run_started",
        %{
          "pack_id" => "radar",
          "pack_version" => "0.1.0",
          "plan_hash" => "sha256:fake"
        },
        nil
      )

    # Write op events for render_html (so we can extract the briefing)
    briefing_json =
      Jason.encode!(%{
        "run_id" => run_id,
        "date" => "2026-04-03",
        "stats" => %{
          "cluster_count" => cluster_count,
          "item_count" => item_count,
          "source_count" => source_count
        },
        "clusters" => [],
        "source_health" =>
          Enum.map(1..source_count, fn i ->
            %{
              "source_id" => "src_#{i}",
              "items_fetched" => div(item_count, source_count),
              "error" => nil
            }
          end)
      })

    {:ok, briefing_hash} = Artifact.Store.put(store_root, briefing_json)

    html_content = "<html><body><h1>Radar Briefing #{run_id}</h1></body></html>"
    {:ok, html_hash} = Artifact.Store.put(store_root, html_content)

    prev_hash = ev1.event_hash

    # Store keyed output hashes in decision store (matches real run behavior)
    Decision.Store.put_outputs(runs_root, run_id, "compose_briefing", %{
      "briefing" => briefing_hash
    })

    Decision.Store.put_outputs(runs_root, run_id, "render_html", %{"html" => html_hash})

    {:ok, ev2} =
      Event.Store.append(
        runs_root,
        run_id,
        "op_completed",
        %{
          "node_id" => "compose_briefing",
          "output_hashes" => [briefing_hash]
        },
        prev_hash
      )

    {:ok, ev3} =
      Event.Store.append(
        runs_root,
        run_id,
        "op_completed",
        %{
          "node_id" => "render_html",
          "output_hashes" => [html_hash]
        },
        ev2.event_hash
      )

    if status == :completed do
      Event.Store.append(
        runs_root,
        run_id,
        "run_completed",
        %{
          "outcome" => "success",
          "artifact_hashes" => %{"render_html" => %{"html" => html_hash}}
        },
        ev3.event_hash
      )
    end

    %{briefing_hash: briefing_hash, html_hash: html_hash}
  end

  describe "briefings list page" do
    test "renders the page with heading", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/radar/briefings")
      assert html =~ "Briefings"
    end

    test "shows empty state when no radar runs", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/radar/briefings")
      assert html =~ "No briefings"
    end

    test "lists completed radar runs", %{conn: conn, runs_root: runs_root, store_root: store_root} do
      create_radar_run(runs_root, store_root, "radar-20260403T060000-abc12345")

      {:ok, _view, html} = live(conn, "/radar/briefings")
      assert html =~ "radar-20260403T060000-abc12345"
    end

    test "shows status, item count, cluster count", %{
      conn: conn,
      runs_root: runs_root,
      store_root: store_root
    } do
      create_radar_run(runs_root, store_root, "radar-20260403T060000-abc12345",
        item_count: 42,
        cluster_count: 7
      )

      {:ok, _view, html} = live(conn, "/radar/briefings")
      assert html =~ "completed"
      assert html =~ "42"
      assert html =~ "7"
    end

    test "sorted by date newest first", %{
      conn: conn,
      runs_root: runs_root,
      store_root: store_root
    } do
      create_radar_run(runs_root, store_root, "radar-20260401T060000-old00000")
      create_radar_run(runs_root, store_root, "radar-20260403T060000-new00000")

      {:ok, _view, html} = live(conn, "/radar/briefings")

      # Newer run should appear before older
      new_pos = :binary.match(html, "radar-20260403T060000-new00000") |> elem(0)
      old_pos = :binary.match(html, "radar-20260401T060000-old00000") |> elem(0)
      assert new_pos < old_pos
    end

    test "clicking a run navigates to detail page", %{
      conn: conn,
      runs_root: runs_root,
      store_root: store_root
    } do
      create_radar_run(runs_root, store_root, "radar-20260403T060000-nav00000")

      {:ok, view, _html} = live(conn, "/radar/briefings")

      assert view
             |> element("a", "radar-20260403T060000-nav00000")
             |> has_element?()
    end
  end

  describe "briefing detail page" do
    test "renders HTML briefing inline", %{
      conn: conn,
      runs_root: runs_root,
      store_root: store_root
    } do
      create_radar_run(runs_root, store_root, "radar-20260403T060000-detail00")

      {:ok, _view, html} = live(conn, "/radar/briefings/radar-20260403T060000-detail00")
      assert html =~ "Radar Briefing radar-20260403T060000-detail00"
    end

    test "shows run metadata", %{conn: conn, runs_root: runs_root, store_root: store_root} do
      create_radar_run(runs_root, store_root, "radar-20260403T060000-meta0000",
        item_count: 55,
        cluster_count: 12,
        source_count: 8
      )

      {:ok, _view, html} = live(conn, "/radar/briefings/radar-20260403T060000-meta0000")
      assert html =~ "55"
      assert html =~ "12"
      assert html =~ "8"
    end

    test "shows source health summary", %{
      conn: conn,
      runs_root: runs_root,
      store_root: store_root
    } do
      create_radar_run(runs_root, store_root, "radar-20260403T060000-health00", source_count: 5)

      {:ok, _view, html} = live(conn, "/radar/briefings/radar-20260403T060000-health00")
      assert html =~ "src_1"
    end

    test "links to observation UI run detail", %{
      conn: conn,
      runs_root: runs_root,
      store_root: store_root
    } do
      run_id = "radar-20260403T060000-obslink0"
      create_radar_run(runs_root, store_root, run_id)

      {:ok, _view, html} = live(conn, "/radar/briefings/#{run_id}")
      assert html =~ "/runs/#{run_id}"
    end

    test "handles non-existent run gracefully", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/radar/briefings/nonexistent-run-id")
      assert html =~ "not found" or html =~ "Not found"
    end
  end
end
