defmodule Mogs.TimersTest do
  use ExUnit.Case, async: true
  alias Mogs.Timers

  defmodule NoTimers do
    defstruct a: 0, b: 0
  end

  defmodule MyBoard do
    @derive {Timers.Store, :timers}
    defstruct timers: Timers.new()
  end

  test "timers protocol is only for explicit implementations or struct with a key" do
    assert_raise Protocol.UndefinedError, fn ->
      Timers.pop_timer(%NoTimers{}, 0)
    end

    assert_raise Protocol.UndefinedError, fn ->
      Timers.pop_timer(%NoTimers{}, 0)
    end

    assert_raise Protocol.UndefinedError, fn ->
      Timers.pop_timer(:some_atom, 0)
    end
  end

  test "can enqueue / pop timer" do
    timer = :some_timer
    board = %MyBoard{}
    assert :empty === Timers.pop_timer(board)
    assert {:ok, _, board} = Timers.enqueue_timer(board, {1, :ms}, timer)
    Process.sleep(50)
    assert {:ok, popped, board} = Timers.pop_timer(board)
    assert timer === TimeQueue.value(popped)
    assert :empty === Timers.pop_timer(board)
  end
end
