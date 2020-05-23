defmodule Mogs.Board.Command.ResultTest do
  use ExUnit.Case, async: true
  alias Mogs.Board.Command.Result
  doctest Result
  import Result, only: [return: 1, merge: 2], warn: false

  # test "the return function is versatile" do
  #   assert %{reply: {:error, "badstuff"}, ok?: false} = return(error: "badstuff")

  #   assert %{reply: "detail", ok?: false, reason: "badstuff"} =
  #            return(error: "badstuff", reply: "detail")

  #   assert %{reply: "detail", ok?: false, reason: "badstuff"} =
  #            return(reply: "detail", error: "badstuff")
  # end

  test "the return function returns only overrides" do
    assert %{__partial__: true, reply: 1} === return(reply: 1)

    assert %{__partial__: true, reply: 1, ok?: false, reason: "bad"} ===
             return(reply: 1, error: "bad")

    assert %{__partial__: true, reply: {:error, "bad"}, ok?: false, reason: "bad"} ===
             return(error: "bad")

    assert %{__partial__: true, board: :stuff} === return(board: :stuff)
    assert %{__partial__: true} === return(stop: false)
    assert %{__partial__: true} === return(stop: true, stop: false)
    assert %{__partial__: true, stop: {true, :normal}} === return(stop: true)
    assert %{__partial__: true, stop: {true, :failure}} === return(stop: :failure)
  end

  test "the result overrides can be casted to a full result" do
    default_board = :old_board
    default_reply = :rep
    defaults = %{__partial__: true, board: default_board, reply: default_reply}

    assert %Result{stop: false, board: default_board, reply: 1, ok?: true, reason: nil} ===
             cast_return(defaults, reply: 1)

    assert %Result{stop: false, board: default_board, reply: 1, ok?: false, reason: "bad"} ===
             cast_return(defaults, reply: 1, error: "bad")

    assert %Result{
             stop: false,
             board: default_board,
             reply: {:error, "bad"},
             ok?: false,
             reason: "bad"
           } ===
             cast_return(defaults, error: "bad")

    assert %Result{stop: false, board: :stuff, reply: default_reply, ok?: true, reason: nil} ===
             cast_return(defaults, board: :stuff)

    assert %Result{
             stop: {true, :byebye},
             board: :stuff,
             reply: default_reply,
             ok?: true,
             reason: nil
           } ===
             cast_return(defaults, board: :stuff, stop: :byebye)
  end

  defp cast_return(defaults, result_data) do
    merge(defaults, return(result_data))
  end
end
