defmodule DopaTeam.WaterPing do
  use GenServer
  require Logger

  defstruct last_ping_sec: 0

  @typedoc "last_ping_sec is unix time seconds since last water ping or when genserver started, whichever is later"
  @type t :: %__MODULE__{
          last_ping_sec: integer()
        }

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  @impl GenServer
  def init(%__MODULE__{} = state) do
    # set initial timer to 0 so users can ping immediately
    {:ok, %{state | last_ping_sec: 0}}
  end

  @doc """
  	get current time
  """
  def now() do
    System.os_time(:second)
  end

  @doc """
  last ping time
  """
  @spec get_timer() :: integer()
  def get_timer() do
    GenServer.call(__MODULE__, {:get_timer})
  end

  @doc """
  	set the timer to now
  """
  @spec set_timer() :: integer()
  def set_timer() do
    GenServer.call(__MODULE__, {:set_timer})
  end

  @impl GenServer
  def handle_call({:get_timer}, _from, %__MODULE__{} = state) do
    {:reply, state.last_ping_sec, state}
  end

  @impl GenServer
  def handle_call({:set_timer}, _from, %__MODULE__{} = state) do
    ut = System.os_time(:second)
    {:reply, ut, %{state | last_ping_sec: ut}}
  end
end
