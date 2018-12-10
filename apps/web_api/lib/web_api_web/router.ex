defmodule WebApiWeb.Router do
  use WebApiWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", WebApiWeb do
    match :*, "/", IndexController, :index 
  end

  scope "/api", WebApiWeb do
    pipe_through :api
  end
end
