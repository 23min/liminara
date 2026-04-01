defmodule LiminaraWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint LiminaraWeb.Endpoint
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import LiminaraWeb.ConnCase
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
