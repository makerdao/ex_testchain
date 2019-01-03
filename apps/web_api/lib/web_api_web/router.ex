defmodule WebApiWeb.Router do
  use WebApiWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", WebApiWeb do
    match :*, "/", IndexController, :index
    match :*, "/version", ChainController, :version
    get "/snapshot/:id", ChainController, :download_snapshot
  end

  scope "/api", WebApiWeb do
    pipe_through :api
  end
end
