defmodule Mogs.Timers do
  alias Mogs.Timers.Store
  @type board :: Store.t()

  # Borrowed types
  @type t :: TimeQueue.t()
  @type timer :: term
  @type ttl :: TimeQueue.ttl()
  @type pop_return :: TimeQueue.pop_return(board)
  @type enqueue_return :: TimeQueue.enqueue_return(board)

  @doc """
  Returns an empty timers structure to initialize timers in a board. This
  structure will contain the timers that commands may set on the board.

  The timers (implemented by the TimeQueue module) can be serialized (e.g with
  term_to_binary)
  """
  @spec new :: Mogs.Timers.t()
  def new() do
    TimeQueue.new()
  end

  @spec pop_timer(board, now :: integer) :: pop_return
  def pop_timer(board, now \\ TimeQueue.now())

  def pop_timer(board, now) do
    case TimeQueue.pop(Store.get_timers(board), now) do
      {:ok, entry, tq} -> {:ok, entry, Store.put_timers(board, tq)}
      other -> other
    end
  end

  @spec enqueue_timer(board, ttl, value :: any, now :: integer) :: enqueue_return
  def enqueue_timer(board, ttl, value, now \\ TimeQueue.now())

  def enqueue_timer(board, ttl, timer, now) do
    tq = Store.get_timers(board)
    {:ok, tref, tq} = TimeQueue.enqueue(tq, ttl, timer, now)

    {:ok, tref, Store.put_timers(board, tq)}
  end
end
