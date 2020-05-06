defmodule Mogs.Board.TimersTest do
  use ExUnit.Case

  defmodule NoTimers do
    defstruct a: 0, b: 0
  end

  defmodule MyBoard do
    @derive {Mogs.Board.Timers, :timers}
    defstruct timers: Mogs.Board.timers()
  end

  test "timers protocol is only for explicit implementations or struct with a key" do
    assert_raise Protocol.UndefinedError, fn ->
      Mogs.Board.Timers.pop_timer(%NoTimers{}, 0)
    end

    assert_raise Protocol.UndefinedError, fn ->
      Mogs.Board.Timers.pop_timer(%NoTimers{}, 0)
    end

    assert_raise Protocol.UndefinedError, fn ->
      Mogs.Board.Timers.pop_timer(:some_atom, 0)
    end
  end

  test "can setup a simple timer" do
    assert :empty === Mogs.Board.Timers.pop_timer(%MyBoard{}, 0)
  end
end
