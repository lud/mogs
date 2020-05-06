defmodule Mogs.Board.Command.ResultTest do
  use ExUnit.Case
  alias Mogs.Board.Command.Result
  doctest Result
  import Result, only: [return: 1, return: 2], warn: false

  test "the return function is versatile" do
    assert %{continue: true, board: nil, ok?: true} = return(reply: "myreply")

    assert %{reply: {:error, "badstuff"}, ok?: false} = return(error: "badstuff")
    assert %{reply: "detail", ok?: false} = return(error: "badstuff", reply: "detail")
    assert %{reply: "detail", ok?: false} = return(reply: "detail", error: "badstuff")

    assert %{continue: false, ok?: true, stop_reason: :normal, reply: nil} = return(stop: true)

    assert %{continue: false, ok?: true, stop_reason: :normal, reply: "rep"} =
             return(stop: true, reply: "rep")
  end
end
