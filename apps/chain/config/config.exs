# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for
# 3rd-party users, it should be done in your "mix.exs" file.

config :porcelain, driver: Porcelain.Driver.Basic

# Amount of time in ms process allowed to perform "blocking" work before supervisor will terminate it
config :chain, kill_timeout: 60_000

