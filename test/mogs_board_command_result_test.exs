defmodule Mogs.Board.Command.ResultTest do
  use ExUnit.Case, async: true
  alias Mogs.Board.Command.Result
  doctest Result
  import Result, only: [result: 1, merge: 2], warn: false

  test "the result function results only overrides" do
    assert %{__partial__: true, reply: 1} === result(reply: 1)

    assert %{__partial__: true, reply: 1, ok?: false, reason: "bad"} ===
             result(reply: 1, error: "bad")

    assert %{__partial__: true, reply: {:error, "bad"}, ok?: false, reason: "bad"} ===
             result(error: "bad")

    assert %{__partial__: true, board: :stuff} === result(board: :stuff)
    assert %{__partial__: true} === result(stop: false)
    assert %{__partial__: true} === result(stop: true, stop: false)
    assert %{__partial__: true, stop: {true, :normal}} === result(stop: true)
    assert %{__partial__: true, stop: {true, :failure}} === result(stop: :failure)
  end

  test "the result overrides can be casted to a full result" do
    default_board = :old_board
    default_reply = :rep
    defaults = %{__partial__: true, board: default_board, reply: default_reply}

    assert %Result{stop: false, board: default_board, reply: 1, ok?: true, reason: nil} ===
             cast_result(defaults, reply: 1)

    assert %Result{stop: false, board: default_board, reply: 1, ok?: false, reason: "bad"} ===
             cast_result(defaults, reply: 1, error: "bad")

    assert %Result{
             stop: false,
             board: default_board,
             reply: {:error, "bad"},
             ok?: false,
             reason: "bad"
           } ===
             cast_result(defaults, error: "bad")

    assert %Result{stop: false, board: :stuff, reply: default_reply, ok?: true, reason: nil} ===
             cast_result(defaults, board: :stuff)

    assert %Result{
             stop: {true, :byebye},
             board: :stuff,
             reply: default_reply,
             ok?: true,
             reason: nil
           } ===
             cast_result(defaults, board: :stuff, stop: :byebye)
  end

  defp cast_result(defaults, result_data) do
    merge(defaults, result(result_data))
  end
end
