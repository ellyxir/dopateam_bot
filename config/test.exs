import Config

# tests replace discord api calls with a mox mock, see test/test_helper.exs
config :dopa_team, discord: DopaTeam.DiscordMock

# delete dm request warnings straight away, so tests can wait for it
config :dopa_team, dm_warning_delete_ms: 0
