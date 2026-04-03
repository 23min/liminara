defmodule LiminaraWeb.RadarLive.NavigationTest do
  use LiminaraWeb.ConnCase, async: false

  describe "navigation" do
    test "radar briefings link present on runs page", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/runs")
      assert html =~ "/radar/briefings"
    end

    test "radar sources link present on briefings page", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/radar/briefings")
      assert html =~ "/radar/sources"
    end

    test "runs link present on briefings page", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/radar/briefings")
      assert html =~ "/runs"
    end
  end
end
