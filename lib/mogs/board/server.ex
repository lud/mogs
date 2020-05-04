defmodule Mogs.Board.Server do
  use GenServer
  require Logger
  require Record
  Record.defrecordp(:s, id: nil, mod: nil, board: nil)

  # @todo allow to define the timeout from the `use Mogs.Board` call
  @timeout 60000

  def start_link(opts) when is_list(opts) do
    mod = Keyword.fetch!(opts, :mod)
    id = Keyword.fetch!(opts, :id)
    name = Keyword.fetch!(opts, :name)
    load_info = Keyword.fetch!(opts, :load_info)
    Logger.debug(inspect(opts))
    GenServer.start_link(__MODULE__, {mod, id, load_info}, name: name, debug: [:trace])
  end

  @impl true
  def init({mod, id, load_info}) do
    with :sync <- load_mode(mod),
         {:ok, board} <- load_board(mod, id, load_info) do
      {:ok, s(id: id, mod: mod, board: board), @timeout}
    else
      :async -> {:ok, s(id: id, mod: mod, board: load_info), {:continue, :async_load}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:async_load, s(id: id, mod: mod, board: load_info) = state) do
    case load_board(mod, id, load_info) do
      {:ok, board} -> {:noreply, s(state, board: board), @timeout}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:read_board_state, fun}, _from, s(board: board) = state) do
    {:reply, fun.(board), state}
  end

  defp load_mode(mod) do
    case mod.load_mode() do
      :sync -> :sync
      :async -> :async
      other -> bad_return(mod, :load_mode, [], other)
    end
  end

  defp load_board(mod, id, load_info) do
    case mod.load(id, load_info) do
      {:ok, board} -> {:ok, board}
      {:error, _reason} = error -> error
      other -> bad_return(mod, :load, [id, load_info], other)
    end
  end

  defp bad_return(m, f, a, returned) do
    {:error, {:bad_return, {m, f, a}, returned}}
  end
end
