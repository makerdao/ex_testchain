defmodule WebApiWeb.Router do
  use WebApiWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", WebApiWeb do
    match :*, "/", IndexController, :index
    match :*, "/version", ChainController, :version
    get "/chains", ChainController, :chain_list
  end

  scope "/chain", WebApiWeb do
    pipe_through :api
    get "/snapshot/:id", ChainController, :download_snapshot
    get "/snapshots/:chain", ChainController, :snapshot_list
    delete "/:id", ChainController, :remove_chain
    get "/:id", ChainController, :details
  end
end
