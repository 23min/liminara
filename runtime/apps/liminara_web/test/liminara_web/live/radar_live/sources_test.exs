defmodule LiminaraWeb.RadarLive.SourcesTest do
  use LiminaraWeb.ConnCase, async: false

  alias Liminara.{Artifact, Decision, Event}

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    store_root = Path.join(tmp_dir, "store")
    runs_root = Path.join(tmp_dir, "runs")
    sources_path = Path.join(tmp_dir, "sources.jsonl")
    File.mkdir_p!(store_root)
    File.mkdir_p!(runs_root)

    prev_store = Application.get_env(:liminara_core, :store_root)
    prev_runs = Application.get_env(:liminara_core, :runs_root)
    prev_sources = Application.get_env(:liminara_radar, :sources_path)
    Application.put_env(:liminara_core, :store_root, store_root)
    Application.put_env(:liminara_core, :runs_root, runs_root)
    Application.put_env(:liminara_radar, :sources_path, sources_path)

    on_exit(fn ->
      if prev_store,
        do: Application.put_env(:liminara_core, :store_root, prev_store),
        else: Application.delete_env(:liminara_core, :store_root)

      if prev_runs,
        do: Application.put_env(:liminara_core, :runs_root, prev_runs),
        else: Application.delete_env(:liminara_core, :runs_root)

      if prev_sources,
        do: Application.put_env(:liminara_radar, :sources_path, prev_sources),
        else: Application.delete_env(:liminara_radar, :sources_path)
    end)

    %{store_root: store_root, runs_root: runs_root, sources_path: sources_path}
  end

  defp write_sources(path, sources) do
    content = Enum.map_join(sources, "\n", &Jason.encode!/1)
    File.write!(path, content)
  end

  defp create_run_with_health(runs_root, store_root, run_id, source_health) do
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

    health_json = Jason.encode!(source_health)
    {:ok, health_hash} = Artifact.Store.put(store_root, health_json)

    # Store keyed output hashes in decision store (matches real run behavior)
    Decision.Store.put_outputs(runs_root, run_id, "collect_items", %{
      "source_health" => health_hash,
      "items" => "sha256:fake"
    })

    {:ok, ev2} =
      Event.Store.append(
        runs_root,
        run_id,
        "op_completed",
        %{
          "node_id" => "collect_items",
          "output_hashes" => [health_hash, "sha256:fake"]
        },
        ev1.event_hash
      )

    Event.Store.append(
      runs_root,
      run_id,
      "run_completed",
      %{
        "outcome" => "success"
      },
      ev2.event_hash
    )
  end

  describe "sources dashboard" do
    test "renders the page", %{conn: conn, sources_path: sources_path} do
      write_sources(sources_path, [
        %{
          "id" => "hn",
          "name" => "Hacker News",
          "type" => "web",
          "tags" => ["news"],
          "enabled" => true
        }
      ])

      {:ok, _view, html} = live(conn, "/radar/sources")
      assert html =~ "Sources"
    end

    test "shows all configured sources", %{conn: conn, sources_path: sources_path} do
      write_sources(sources_path, [
        %{
          "id" => "hn",
          "name" => "Hacker News",
          "type" => "web",
          "tags" => ["news"],
          "enabled" => true
        },
        %{
          "id" => "arxiv",
          "name" => "ArXiv",
          "type" => "rss",
          "tags" => ["research"],
          "enabled" => true
        },
        %{
          "id" => "old_blog",
          "name" => "Old Blog",
          "type" => "rss",
          "tags" => ["tech"],
          "enabled" => false
        }
      ])

      {:ok, _view, html} = live(conn, "/radar/sources")
      assert html =~ "Hacker News"
      assert html =~ "ArXiv"
      assert html =~ "Old Blog"
    end

    test "shows source type and tags", %{conn: conn, sources_path: sources_path} do
      write_sources(sources_path, [
        %{
          "id" => "hn",
          "name" => "Hacker News",
          "type" => "web",
          "tags" => ["news", "tech"],
          "enabled" => true
        }
      ])

      {:ok, _view, html} = live(conn, "/radar/sources")
      assert html =~ "web"
      assert html =~ "news"
    end

    test "shows enabled/disabled status", %{conn: conn, sources_path: sources_path} do
      write_sources(sources_path, [
        %{
          "id" => "hn",
          "name" => "Hacker News",
          "type" => "web",
          "tags" => ["news"],
          "enabled" => true
        },
        %{
          "id" => "old",
          "name" => "Old Feed",
          "type" => "rss",
          "tags" => ["tech"],
          "enabled" => false
        }
      ])

      {:ok, _view, html} = live(conn, "/radar/sources")
      # Should have some indication of enabled/disabled state
      assert html =~ "enabled" or html =~ "disabled"
    end

    test "shows items contributed from last run", %{
      conn: conn,
      sources_path: sources_path,
      runs_root: runs_root,
      store_root: store_root
    } do
      write_sources(sources_path, [
        %{
          "id" => "hn",
          "name" => "Hacker News",
          "type" => "web",
          "tags" => ["news"],
          "enabled" => true
        }
      ])

      create_run_with_health(runs_root, store_root, "radar-20260403T060000-src00000", [
        %{"source_id" => "hn", "items_fetched" => 42, "error" => nil}
      ])

      {:ok, _view, html} = live(conn, "/radar/sources")
      assert html =~ "42"
    end

    test "highlights sources with zero contribution as cull candidates", %{
      conn: conn,
      sources_path: sources_path,
      runs_root: runs_root,
      store_root: store_root
    } do
      write_sources(sources_path, [
        %{
          "id" => "dead",
          "name" => "Dead Feed",
          "type" => "rss",
          "tags" => ["tech"],
          "enabled" => true
        }
      ])

      # Create 7+ runs with zero items for this source
      for i <- 1..7 do
        run_id = "radar-2026040#{i}T060000-zero#{String.pad_leading("#{i}", 4, "0")}"

        create_run_with_health(runs_root, store_root, run_id, [
          %{"source_id" => "dead", "items_fetched" => 0, "error" => nil}
        ])
      end

      {:ok, _view, html} = live(conn, "/radar/sources")
      assert html =~ "cull" or html =~ "inactive"
    end

    test "toggle enabled/disabled", %{conn: conn, sources_path: sources_path} do
      write_sources(sources_path, [
        %{
          "id" => "hn",
          "name" => "Hacker News",
          "type" => "web",
          "tags" => ["news"],
          "enabled" => true
        }
      ])

      {:ok, view, _html} = live(conn, "/radar/sources")

      # Toggle disable
      html = render_click(view, "toggle_enabled", %{"id" => "hn"})
      assert html =~ "disabled"

      # Verify file was updated
      {:ok, sources} = Liminara.Radar.Config.load(sources_path)
      source = Enum.find(sources, &(&1["id"] == "hn"))
      assert source["enabled"] == false
    end
  end
end
