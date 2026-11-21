defmodule DopaTeam.ReportStoreTest do
  use ExUnit.Case, async: true

  alias DopaTeam.ReportStore

  defp start_store(context, options \\ []) do
    name = Module.concat(__MODULE__, "Store#{context.line}")
    start_supervised!({ReportStore, Keyword.put(options, :name, name)})
    name
  end

  test "a stored report can be fetched by its id", context do
    store = start_store(context)

    :ok = ReportStore.put(store, 1, :report)

    assert ReportStore.fetch(store, 1) == {:ok, :report}
  end

  test "an id with no report gives an error", context do
    store = start_store(context)

    assert ReportStore.fetch(store, 1) == :error
  end

  test "a report past its lifetime is not returned", context do
    store = start_store(context, ttl_ms: 0)

    :ok = ReportStore.put(store, 1, :report)

    assert ReportStore.fetch(store, 1) == :error
  end

  test "a sweep deletes reports past their lifetime", context do
    store = start_store(context, ttl_ms: 0)
    :ok = ReportStore.put(store, 1, :report)

    send(store, :sweep)
    _state = :sys.get_state(store)

    assert :ets.lookup(store, 1) == []
  end

  test "a sweep keeps reports within their lifetime", context do
    store = start_store(context)
    :ok = ReportStore.put(store, 1, :report)

    send(store, :sweep)
    _state = :sys.get_state(store)

    assert ReportStore.fetch(store, 1) == {:ok, :report}
  end

  test "the store sweeps on its own, again and again", context do
    store = start_store(context, ttl_ms: 0, sweep_every_ms: 1)
    :ok = ReportStore.put(store, 1, :report)

    pid = Process.whereis(store)
    1 = :erlang.trace(pid, true, [:receive])
    # two, so at least one came from a sweep scheduling the next
    assert_receive {:trace, ^pid, :receive, :sweep}
    assert_receive {:trace, ^pid, :receive, :sweep}
    _state = :sys.get_state(store)

    assert :ets.lookup(store, 1) == []
  end
end
