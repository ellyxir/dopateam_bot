import Config

# The contents of this file are compiled into the server.
# If you need to source something from the environment, it should go in runtime.exs instead

config :nostrum,
  gateway_intents: :all,
  # The number of shards you want to run your bot under, or :auto.
  num_shards: :auto,
  log_dispatch_events: false,
  log_full_events: false

# the module the consumer makes its discord api calls through
config :dopa_team, discord: DopaTeam.Discord.Nostrum
