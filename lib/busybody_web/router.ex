defmodule BusybodyWeb.Router do
  @moduledoc false

  use BusybodyWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BusybodyWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BusybodyWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/api", BusybodyWeb do
    pipe_through :api

    post "/register", ApiController, :register
    get "/apps", ApiController, :index
  end
end
