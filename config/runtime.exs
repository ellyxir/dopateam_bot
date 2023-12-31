import Config

config :nostrum,
  token: System.get_env("DOPATEAM_TOKEN")

config :logger,
  # :debug, :warning, :info
  level: :warning
