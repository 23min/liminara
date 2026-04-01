defmodule LiminaraWeb.Router do
  use LiminaraWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LiminaraWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", LiminaraWeb do
    pipe_through :browser

    get "/", Plugs.Redirect, to: "/runs"
    live "/runs", RunsLive.Index, :index
    live "/runs/:id", RunsLive.Show, :show
  end
end
