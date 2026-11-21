import Config

# tests must never log in to discord
if config_env() != :test do
  config :nostrum,
    token: System.get_env("DOPATEAM_TOKEN")
end

config :logger,
  # :debug, :warning, :info
  level: :warning
