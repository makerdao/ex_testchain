# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# General application configuration
config :web_api,
  namespace: WebApi

# Configures the endpoint
config :web_api, WebApiWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "Eli6LBSC+Td/9SiASJcR1untGi+VetKv0QA4qMFOaKVUsL0hoTQe2FrMNMXWoZWZ",
  render_errors: [view: WebApiWeb.ErrorView, accepts: ~w(json)],
  pubsub: [name: WebApi.PubSub,
           adapter: Phoenix.PubSub.PG2]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:user_id]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env}.exs"
