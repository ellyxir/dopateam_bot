defmodule DopaTeam.ReportStore do
  @moduledoc """
  Keeps built reports for a while, so paging through one doesn't fetch the
  members again.

  The store owns an ETS table named after it and is its only writer; readers
  look reports up in the table directly.
  """

  use GenServer

  @default_ttl_ms :timer.hours(1)
  @default_sweep_every_ms :timer.minutes(10)

  @enforce_keys [:table, :ttl_ms, :sweep_every_ms]
  defstruct [:table, :ttl_ms, :sweep_every_ms]

  # the store's state: its table, how long reports live and how often we
  # delete the expired ones
  @typep t() :: %__MODULE__{
           table: atom(),
           ttl_ms: non_neg_integer(),
           sweep_every_ms: pos_integer()
         }

  @typedoc "options for `start_link/1`"
  @type option() ::
          {:name, atom()} | {:ttl_ms, non_neg_integer()} | {:sweep_every_ms, pos_integer()}

  @typedoc "the id a report is stored under"
  @type id() :: term()

  @typedoc "a stored report"
  @type report() :: term()

  @doc """
  starts a store

  Options:
  * `name:` - names both the process and its table, defaults to this module
  * `ttl_ms:` - how long a report is kept, defaults to an hour
  * `sweep_every_ms:` - how often expired reports are deleted, defaults to
    ten minutes
  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(options) do
    name = Keyword.get(options, :name, __MODULE__)

    state = %__MODULE__{
      table: name,
      ttl_ms: Keyword.get(options, :ttl_ms, @default_ttl_ms),
      sweep_every_ms: Keyword.get(options, :sweep_every_ms, @default_sweep_every_ms)
    }

    GenServer.start_link(__MODULE__, state, name: name)
  end

  @doc "stores a report under an id"
  @spec put(store :: atom(), id(), report()) :: :ok
  def put(store \\ __MODULE__, id, report), do: GenServer.call(store, {:put, id, report})

  @doc """
  fetches the report stored under an id; it's an error if there is none, if
  it has expired, or if the store isn't running, such as while it restarts
  """
  @spec fetch(store :: atom(), id()) :: {:ok, report()} | :error
  def fetch(store \\ __MODULE__, id) do
    now = now_ms()

    case :ets.lookup(store, id) do
      [{^id, report, expires_at}] when now < expires_at -> {:ok, report}
      _expired_or_missing -> :error
    end
  rescue
    # the table goes with its owner, and lookup raises when it's gone
    ArgumentError -> :error
  end

  @impl true
  @spec init(t()) :: {:ok, t()}
  def init(%__MODULE__{table: name} = state) do
    ^name = :ets.new(name, [:named_table, :protected, read_concurrency: true])
    schedule_sweep(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:put, id, report}, _from, %__MODULE__{} = state) do
    true = :ets.insert(state.table, {id, report, now_ms() + state.ttl_ms})
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:sweep, %__MODULE__{} = state) do
    now = now_ms()
    # deletes every {id, report, expires_at} row with expires_at <= now
    _deleted = :ets.select_delete(state.table, [{{:_, :_, :"$1"}, [{:"=<", :"$1", now}], [true]}])
    schedule_sweep(state)
    {:noreply, state}
  end

  @spec schedule_sweep(t()) :: reference()
  defp schedule_sweep(%__MODULE__{} = state),
    do: Process.send_after(self(), :sweep, state.sweep_every_ms)

  # monotonic, so a change to the system clock can't expire reports early
  # or keep them forever
  @spec now_ms() :: integer()
  defp now_ms, do: System.monotonic_time(:millisecond)
end
