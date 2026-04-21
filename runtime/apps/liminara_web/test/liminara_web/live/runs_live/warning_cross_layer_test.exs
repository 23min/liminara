defmodule LiminaraWeb.RunsLive.WarningCrossLayerTest do
  @moduledoc """
  M-WARN-04 AC5 cross-layer consistency guard.

  Each of the four M-WARN-04 bugs has its own focused per-layer test
  (`live_warning_integration_test.exs` for bug_005, `partial_run_integration_test.exs`
  for merged_bug_001, the `warning_count idempotence` describe block in
  `runs_live_index_test.exs` for bug_004, the `partial run detail (event-log
  fallback)` describe block in `warnings_test.exs` for bug_009). This file
  exercises all four fixes in a single place at the highest visible layer
  (LiveView render + ViewModel observation + runtime result) so a regression
  in any one layer surfaces immediately in a single file, without requiring
  a coordinated read across four test files.

  Test names read as specifications.
  """
  use LiminaraWeb.ConnCase, async: false

  alias Liminara.Observation.Server, as: ObsServer
  alias Liminara.Plan
  alias Liminara.Run.Server, as: RunServer

  # Runs here persist to the supervised Event.Store's runs_root (default
  # `/tmp/liminara_runs/`). Without cleanup they leak into sibling tests
  # in `RunsLive.IndexTest` and similar files, causing their
  # `refute html =~ "status--degraded"` assertions to see rows from this
  # file (the same cross-test leak that `warnings_test.exs` fallback
  # describe also guards against). We cannot swap `runs_root` via
  # `Application.put_env` because the supervised `Event.Store` reads
  # it once at startup.
  setup do
    runs_root =
      Application.get_env(:liminara_core, :runs_root) ||
        Path.join(System.tmp_dir!(), "liminara_runs")

    {:ok, supervised_runs_root: runs_root}
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp unique_run_id(prefix) do
    rand = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}-#{rand}"
  end

  defp cleanup_run(runs_root, run_id) do
    File.rm_rf!(Path.join(runs_root, run_id))
  end

  defp await_observation(obs_pid, condition_fn, timeout \\ 2000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await(obs_pid, condition_fn, deadline)
  end

  defp do_await(obs_pid, condition_fn, deadline) do
    state = ObsServer.get_state(obs_pid)

    cond do
      condition_fn.(state) ->
        state

      System.monotonic_time(:millisecond) > deadline ->
        flunk("timed out waiting for observation state. last=#{inspect(state, limit: 5)}")

      true ->
        Process.sleep(20)
        do_await(obs_pid, condition_fn, deadline)
    end
  end

  # A plan that warns and completes cleanly. Exercises bug_005.
  defp warn_only_plan do
    Plan.new()
    |> Plan.add_node("warn", Liminara.TestOps.WithSingleWarningUncachedSpec, %{
      "text" => {:literal, "hello"}
    })
  end

  # A fan-out plan: root feeds two independent branches; warn warns and
  # completes, fail always fails. Yields Run.Result.status == :partial.
  # Exercises merged_bug_001.
  defp partial_plan do
    Plan.new()
    |> Plan.add_node("root", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
    |> Plan.add_node("warn", Liminara.TestOps.WithSingleWarningUncachedSpec, %{
      "text" => {:ref, "root", "result"}
    })
    |> Plan.add_node("fail", Liminara.TestOps.Fail, %{"data" => {:ref, "root", "result"}})
  end

  # ── bug_005: live warning broadcast ──────────────────────────────

  describe "live warning broadcast reaches ViewModel without raising (bug_005)" do
    test "a real %Warning{} crosses Run.Server → :pg → ObsServer and Show renders degraded",
         %{conn: conn, supervised_runs_root: runs_root} do
      run_id = unique_run_id("x-bug005")
      on_exit(fn -> cleanup_run(runs_root, run_id) end)
      plan = warn_only_plan()

      {:ok, obs_pid} = ObsServer.start_link(run_id: run_id, plan: plan)
      ref = Process.monitor(obs_pid)

      RunServer.start(run_id, plan)
      {:ok, result} = RunServer.await(run_id, 5_000)
      assert result.status == :success

      # Observer survives the live broadcast (pre-fix: atom-keyed payload
      # crashed ViewModel.validate_warning_entry!/1).
      refute_receive {:DOWN, ^ref, :process, _pid, _reason}, 100
      assert Process.alive?(obs_pid)

      state = await_observation(obs_pid, fn s -> s.run_status == :completed end)
      assert state.nodes["warn"].degraded == true
      assert length(state.nodes["warn"].warnings) == 1

      # UI surfaces the degraded badge.
      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      assert html =~ ~s(class="status status--degraded"),
             "LiveView must render degraded badge for bug_005 live-warning run. HTML:\n#{html}"

      GenServer.stop(obs_pid)
    end
  end

  # ── merged_bug_001: :partial-with-warnings ───────────────────────

  describe "partial-with-warnings reaches every consumer as degraded (merged_bug_001)" do
    test "Run.Result, ViewModel, and Show LiveView all agree on :partial + degraded: true",
         %{conn: conn, supervised_runs_root: runs_root} do
      run_id = unique_run_id("x-merged001")
      on_exit(fn -> cleanup_run(runs_root, run_id) end)
      plan = partial_plan()

      {:ok, obs_pid} = ObsServer.start_link(run_id: run_id, plan: plan)

      RunServer.start(run_id, plan)
      {:ok, result} = RunServer.await(run_id, 5_000)

      # 1. CLI / Run.Result layer
      assert result.status == :partial
      assert result.degraded == true

      # 2. Observation ViewModel layer
      state = await_observation(obs_pid, fn s -> s.run_status == :partial end)
      assert state.run_status == :partial
      assert state.degraded == true
      assert state.nodes["warn"].degraded == true
      assert state.nodes["fail"].status == :failed

      # 3. Web LiveView (Show) layer
      {:ok, _view, html} = live(conn, "/runs/#{run_id}")

      assert html =~ ~s(class="status status--partial"),
             "Show must render partial status badge. HTML:\n#{html}"

      assert html =~ ~s(class="status status--degraded"),
             "Show must render degraded badge for partial-with-warnings. HTML:\n#{html}"

      refute html =~ ~s(class="status status--failed"),
             "Show must not collapse :partial to :failed. HTML:\n#{html}"

      GenServer.stop(obs_pid)
    end
  end

  # ── bug_004: runs-index idempotence on re-delivered terminals ────

  describe "runs-index warning_count stays stable on duplicate terminal (bug_004)" do
    test "a warning run rendered in the runs index shows degraded (N), not degraded (2N), after a real run",
         %{conn: conn, supervised_runs_root: runs_root} do
      # `run-` prefix so RunsLive.Index.real_run?/2 accepts the row
      # (the filter excludes pack_id="anonymous" runs unless the id
      # starts with a recognised prefix).
      run_id = unique_run_id("run-xlayer-bug004")
      on_exit(fn -> cleanup_run(runs_root, run_id) end)
      plan = warn_only_plan()

      {:ok, obs_pid} = ObsServer.start_link(run_id: run_id, plan: plan)

      RunServer.start(run_id, plan)
      {:ok, _result} = RunServer.await(run_id, 5_000)
      _ = await_observation(obs_pid, fn s -> s.run_status == :completed end)

      # Give the seal write + :pg broadcasts a moment to settle so
      # load_runs_from_store sees the persisted events.
      Process.sleep(100)

      # Mount the runs index after the run completes — load_runs_from_store
      # (on-disk path) + any incoming :pg broadcasts must not double-count.
      {:ok, _view, html} = live(conn, "/runs")

      # Scope the assertion to this run_id's row to stay robust against
      # sibling-test rows persisted in the shared default runs_root.
      # Pattern cribbed from runs_live_index_test.exs.
      row_regex = ~r|<tr[^>]*>\s*<td[^>]*>\s*<a[^>]*href="/runs/#{run_id}".*?</tr>|s

      assert html =~ run_id, "Run row must be rendered. HTML:\n#{html}"
      assert [row] = Regex.run(row_regex, html) |> List.wrap()

      assert row =~ "degraded (1)", "Runs index row must show degraded (1). Row:\n#{row}"
      refute row =~ "degraded (2)", "Runs index row must not double-count warnings. Row:\n#{row}"

      GenServer.stop(obs_pid)
    end
  end

  # ── bug_009: event-log fallback preserves per-node degraded ──────

  describe "event-log fallback preserves per-node degraded (bug_009)" do
    test "RunsLive.Show fallback path renders per-node degraded flag and inspector Warnings",
         %{conn: conn, supervised_runs_root: runs_root} do
      run_id = unique_run_id("x-bug009")
      on_exit(fn -> cleanup_run(runs_root, run_id) end)

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
              "degraded_node_ids" => ["warn"]
            }
          },
          nil
        )

      {:ok, view, html} = live(conn, "/runs/#{run_id}")

      # DAG pill: data-dag JSON carries "degraded":true for warn node.
      [_, raw_dag] = Regex.run(~r/data-dag="([^"]*)"/, html)

      dag =
        raw_dag
        |> String.replace("&quot;", "\"")
        |> String.replace("&amp;", "&")
        |> Jason.decode!()

      warn_node = Enum.find(dag["nodes"], fn n -> n["id"] == "warn" end)
      assert warn_node, "Expected 'warn' node in fallback DAG. DAG:\n#{inspect(dag)}"
      assert warn_node["degraded"] == true, "Fallback DAG must tag 'warn' node degraded:true"

      # Inspector Warnings section renders the canonical warning fields.
      render_click(view, "select_node", %{"node-id" => "warn"})
      inspector_html = render(view)

      assert inspector_html =~ "Warnings", "Expected Warnings section header"
      assert inspector_html =~ "llm_fallback", "Expected warning code"
      assert inspector_html =~ "placeholder summary used", "Expected warning summary"
      assert inspector_html =~ "ANTHROPIC_API_KEY missing", "Expected warning cause"
      assert inspector_html =~ "export ANTHROPIC_API_KEY then rerun", "Expected remediation"
    end
  end
end
