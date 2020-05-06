defmodule Mogs.Board.Server do
  use GenServer, restart: :transient
  require Logger
  require Record
  Record.defrecordp(:s, id: nil, mod: nil, board: nil)
  alias Mogs.Board.Command.Result

  # @todo allow to define the timeout from the `use Mogs.Board` call
  @timeout 60_000

  def start_link(opts) when is_list(opts) do
    mod = Keyword.fetch!(opts, :mod)
    id = Keyword.fetch!(opts, :id)
    name = Keyword.fetch!(opts, :name)
    load_info = Keyword.fetch!(opts, :load_info)
    # debug: [:trace]
    GenServer.start_link(__MODULE__, {mod, id, load_info}, name: name)
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
    {:reply, fun.(board), state, @timeout}
  end

  @todo "Check result.ok? to tell if we write/broadcast the board"
  @impl true
  def handle_call({:run_command, command}, _from, s(board: board, mod: mod) = state) do
    case mod.handle_command(command, board) do
      %Result{continue: true, reply: reply, board: board} ->
        {:reply, reply, s(state, board: board), @timeout}

      %Result{continue: false, reply: reply, board: board, stop_reason: reason} ->
        {:stop, reason, reply, s(state, board: board)}
    end
  end

  defp load_mode(mod) do
    case mod.load_mode() do
      :sync -> :sync
      :async -> :async
      other -> {:bad_return, {mod, :load_mode, []}, other}
    end
  end

  defp load_board(mod, id, load_info) do
    case mod.load(id, load_info) do
      {:ok, board} -> {:ok, board}
      {:error, _reason} = error -> error
      other -> {:bad_return, {mod, :load, [id, load_info]}, other}
    end
  end
end
