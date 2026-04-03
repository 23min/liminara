defmodule Liminara.Radar.SchedulerTest do
  use ExUnit.Case, async: true

  alias Liminara.Radar.Scheduler

  describe "ms_until_next/2" do
    test "target time is in the future today" do
      # 05:00 now, target 06:00 → 1 hour
      now = ~U[2026-04-03 05:00:00Z]
      target = ~T[06:00:00]
      ms = Scheduler.ms_until_next(target, now)
      assert ms == 3_600_000
    end

    test "target time has already passed today → schedules for tomorrow" do
      # 07:00 now, target 06:00 → 23 hours
      now = ~U[2026-04-03 07:00:00Z]
      target = ~T[06:00:00]
      ms = Scheduler.ms_until_next(target, now)
      assert ms == 23 * 3_600_000
    end

    test "target time is exactly now → schedules for tomorrow" do
      now = ~U[2026-04-03 06:00:00Z]
      target = ~T[06:00:00]
      ms = Scheduler.ms_until_next(target, now)
      assert ms == 24 * 3_600_000
    end

    test "one minute before target" do
      now = ~U[2026-04-03 05:59:00Z]
      target = ~T[06:00:00]
      ms = Scheduler.ms_until_next(target, now)
      assert ms == 60_000
    end

    test "one second after target → tomorrow minus one second" do
      now = ~U[2026-04-03 06:00:01Z]
      target = ~T[06:00:00]
      ms = Scheduler.ms_until_next(target, now)
      assert ms == 24 * 3_600_000 - 1_000
    end
  end

  describe "GenServer lifecycle" do
    test "starts and reports next_run_at" do
      target = ~T[06:00:00]
      {:ok, pid} = Scheduler.start_link(daily_at: target, run_fn: fn -> :ok end)
      assert %DateTime{} = Scheduler.next_run_at(pid)
      GenServer.stop(pid)
    end

    test "last_run_at is nil before any run" do
      {:ok, pid} = Scheduler.start_link(daily_at: ~T[06:00:00], run_fn: fn -> :ok end)
      assert Scheduler.last_run_at(pid) == nil
      GenServer.stop(pid)
    end

    test "run_now/1 triggers a run and updates last_run_at" do
      test_pid = self()
      run_fn = fn -> send(test_pid, :ran) end

      {:ok, pid} = Scheduler.start_link(daily_at: ~T[23:59:59], run_fn: run_fn)
      assert Scheduler.last_run_at(pid) == nil

      Scheduler.run_now(pid)
      assert_receive :ran, 1_000

      assert %DateTime{} = Scheduler.last_run_at(pid)
      GenServer.stop(pid)
    end

    test "run_now/1 does not trigger concurrent runs" do
      test_pid = self()

      # A run_fn that blocks for a bit
      run_fn = fn ->
        send(test_pid, {:started, self()})
        Process.sleep(200)
        send(test_pid, {:finished, self()})
      end

      {:ok, pid} = Scheduler.start_link(daily_at: ~T[23:59:59], run_fn: run_fn)

      # First run
      Scheduler.run_now(pid)
      assert_receive {:started, _}, 1_000

      # Second run while first is active — should be skipped
      assert Scheduler.run_now(pid) == :already_running

      assert_receive {:finished, _}, 1_000
      GenServer.stop(pid)
    end

    test "scheduler handles run failure gracefully" do
      run_fn = fn -> raise "boom" end

      {:ok, pid} = Scheduler.start_link(daily_at: ~T[23:59:59], run_fn: run_fn)

      # Should not crash the scheduler
      Scheduler.run_now(pid)
      Process.sleep(100)

      assert Process.alive?(pid)
      # last_run_at is still updated even on failure
      assert %DateTime{} = Scheduler.last_run_at(pid)
      GenServer.stop(pid)
    end

    test "next_run_at updates after run_now" do
      {:ok, pid} = Scheduler.start_link(daily_at: ~T[06:00:00], run_fn: fn -> :ok end)
      before = Scheduler.next_run_at(pid)

      Scheduler.run_now(pid)
      Process.sleep(50)

      after_run = Scheduler.next_run_at(pid)
      # next_run_at should be recalculated (still ~24h from now, but a fresh timestamp)
      assert %DateTime{} = after_run
      # The exact value depends on wall clock, just verify it's a valid datetime
      assert DateTime.compare(after_run, before) in [:gt, :eq]
      GenServer.stop(pid)
    end
  end

  describe "scheduled trigger" do
    test "fires when timer elapses" do
      test_pid = self()
      run_fn = fn -> send(test_pid, :triggered) end

      # Use a very short interval by sending the :trigger message directly
      {:ok, pid} = Scheduler.start_link(daily_at: ~T[23:59:59], run_fn: run_fn)

      # Simulate timer firing
      send(pid, :trigger)
      assert_receive :triggered, 1_000

      assert %DateTime{} = Scheduler.last_run_at(pid)
      GenServer.stop(pid)
    end
  end
end
