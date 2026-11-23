import Config

# The contents of this file are compiled into the server.
# If you need to source something from the environment, it should go in runtime.exs instead

config :nostrum,
  gateway_intents: :all,
  # The number of shards you want to run your bot under, or :auto.
  num_shards: :auto,
  log_dispatch_events: false,
  log_full_events: false

# nostrum keeps no messages by default; we keep the newest ones in memory so
# a deleted intro still says whose it was
config :nostrum,
  caches: %{messages: {Nostrum.Cache.MessageCache.Mnesia, []}}

# the module the consumer makes its discord api calls through
config :dopa_team, discord: DopaTeam.Discord.Nostrum

# how long the warning we post about a removed dm request stays up
config :dopa_team, dm_warning_delete_ms: 30_000

if config_env() == :test do
  import_config "test.exs"
end
