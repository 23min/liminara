defmodule LiminaraWeb.RadarLive.SchedulerUITest do
  use LiminaraWeb.ConnCase, async: false

  alias Liminara.Radar.Scheduler

  describe "scheduler status on briefings page" do
    test "shows scheduler status when scheduler is running", %{conn: conn} do
      {:ok, pid} = Scheduler.start_link(daily_at: ~T[06:00:00], run_fn: fn -> :ok end, name: :test_scheduler_ui)

      Application.put_env(:liminara_radar, :scheduler_pid, pid)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
        Application.delete_env(:liminara_radar, :scheduler_pid)
      end)

      {:ok, _view, html} = live(conn, "/radar/briefings")
      assert html =~ "Next run" or html =~ "Scheduler"
    end

    test "shows run now button", %{conn: conn} do
      {:ok, pid} = Scheduler.start_link(daily_at: ~T[06:00:00], run_fn: fn -> :ok end, name: :test_scheduler_btn)

      Application.put_env(:liminara_radar, :scheduler_pid, pid)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
        Application.delete_env(:liminara_radar, :scheduler_pid)
      end)

      {:ok, _view, html} = live(conn, "/radar/briefings")
      assert html =~ "Run now"
    end

    test "no scheduler section when scheduler is not running", %{conn: conn} do
      Application.delete_env(:liminara_radar, :scheduler_pid)

      {:ok, _view, html} = live(conn, "/radar/briefings")
      refute html =~ "Next run"
    end
  end
end
