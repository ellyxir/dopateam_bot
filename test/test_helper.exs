# `mix test` runs with --no-start, so we start only what the tests use
{:ok, _apps} = Application.ensure_all_started(:mox)

Mox.defmock(DopaTeam.DiscordMock, for: DopaTeam.Discord)

ExUnit.start()
